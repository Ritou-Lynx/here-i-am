param([string]$MaintenanceDirectory,[string]$Root,[ValidateSet('orchestration','native','host')][string]$Mode='orchestration',[string]$Scenario='ended')
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
if($Mode -eq 'host'){
 # A synthetic hidden STATIC top-level window, independent of the real host.
 # Keep creation and destruction on one native thread, with a bounded lifetime.
 Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class SyntheticReadyWindow {
 [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern IntPtr CreateWindowEx(uint ex,string cls,string title,uint style,int x,int y,int w,int h,IntPtr parent,IntPtr menu,IntPtr instance,IntPtr data);
 [DllImport("user32.dll")]static extern bool DestroyWindow(IntPtr hwnd);
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
 public static void Run(string root,int delay){
  IntPtr hwnd=CreateWindowEx(0,"STATIC","Synthetic schema6 readiness",0,0,0,1,1,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero);
  if(hwnd==IntPtr.Zero)throw new InvalidOperationException("synthetic_window_create_failed");
  try{
   uint pid;uint tid=GetWindowThreadProcessId(hwnd,out pid);
   File.WriteAllText(Path.Combine(root,"window.tmp"),"{\"pid\":"+pid+",\"hwnd\":"+hwnd.ToInt64()+",\"thread\":"+tid+"}");
   File.Move(Path.Combine(root,"window.tmp"),Path.Combine(root,"window.json"));
   var watch=Stopwatch.StartNew();
   while(!File.Exists(Path.Combine(root,"destroy"))){if(watch.ElapsedMilliseconds>20000)throw new InvalidOperationException("synthetic_destroy_timeout");Thread.Sleep(20);}
  }finally{if(!DestroyWindow(hwnd))throw new InvalidOperationException("synthetic_window_destroy_failed");}
  File.WriteAllText(Path.Combine(root,"destroyed"),"true");
  Thread.Sleep(delay);
 }
}
'@
 [SyntheticReadyWindow]::Run($Root,$(if($Scenario -eq 'stays-alive'){15000}elseif($Scenario -eq 'exits'){1000}else{0}))
 exit 0
}
. (Join-Path $MaintenanceDirectory 'switch-login-task.ps1')
if($Mode -eq 'native'){
 Initialize-Schema6MaintenanceNative
 $info=[Diagnostics.ProcessStartInfo]::new()
 $info.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $info.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Mode host -Root "'+$Root+'" -Scenario "'+$Scenario+'"'
 $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
 $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $process=[Diagnostics.Process]::new();$process.StartInfo=$info;$lease=$null
 try {
  if(-not $process.Start()){throw 'synthetic_process_start_failed'}
  $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
  function Wait-SyntheticFile([string]$Name){
   $wait=[Diagnostics.Stopwatch]::StartNew()
   while(-not (Test-Path -LiteralPath (Join-Path $Root $Name))){
    if($process.HasExited -or $wait.ElapsedMilliseconds -gt 15000){throw 'synthetic_window_wait_failed'}
    Start-Sleep -Milliseconds 20
   }
  }
  Wait-SyntheticFile 'window.json'
  $record=Read-Schema6Json (Join-Path $Root 'window.json')
  if($record.pid -ne $process.Id){throw 'synthetic_pid_mismatch'}
  $ticks=(Get-Item -LiteralPath (Join-Path $Root 'window.json')).LastWriteTimeUtc.Ticks
  $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $session=[Diagnostics.Process]::GetCurrentProcess().SessionId
  # Always prove the very same window/identity is accepted before destruction.
  $lease=[Schema6MaintenanceHost]::Open($process.Id,[long]$record.hwnd,$ticks,$info.FileName,$owner,$session,[uint32]$record.thread)
  if($null -eq $lease){throw 'synthetic_live_lease_missing'}
  $lease.Dispose();$lease=$null
  $errorCode=$null;$returnedNull=$false;$elapsed=0
  if($Scenario -ne 'valid'){
   [IO.File]::WriteAllText((Join-Path $Root 'destroy'),'true');Wait-SyntheticFile 'destroyed'
   $watch=[Diagnostics.Stopwatch]::StartNew()
   try {
    $lease=[Schema6MaintenanceHost]::Open($process.Id,[long]$record.hwnd,$ticks,$info.FileName,$owner,$session,[uint32]$record.thread)
    $returnedNull=$null -eq $lease
   }catch{$errorCode=$_.Exception.InnerException.Message}
   $elapsed=$watch.ElapsedMilliseconds
  }else{[IO.File]::WriteAllText((Join-Path $Root 'destroy'),'true')}
  [Console]::Out.WriteLine((@{format='schema6-ready-native-test-v1';error=$errorCode;returnedNull=$returnedNull;elapsed=$elapsed;liveLeaseConfirmed=$true;exited=$process.HasExited}|ConvertTo-Json -Compress))
 }finally{
  if($lease){$lease.Dispose()}
  # Only this exact synthetic child is eligible for cleanup.
  if($process.Id -gt 0 -and -not $process.HasExited){$process.Kill();$process.WaitForExit()}
  $process.Dispose()
 }
 exit 0
}

# Pure orchestration: use the real Wait, with only native/task boundaries mocked.
function Assert-Schema6TaskUnchanged([string]$Name,$Binding){if($Scenario -eq 'assert-error'){throw 'synthetic_task_changed'}}
$script:Schema6TaskAdapter={param($Operation,$TaskName);if($Operation -ne 'State'){throw 'synthetic_unexpected_task_operation'};return 3}
$script:disposed=$false
function Get-Schema6LiveSessions($Binding){
 if($Scenario -eq 'live-error'){throw 'synthetic_live_error'}
 if($Scenario -eq 'live-exit'){
  $lease=[pscustomobject]@{}
  $lease|Add-Member -MemberType ScriptMethod -Name Dispose -Value {$script:disposed=$true}
  return [pscustomobject]@{Directory=(Join-Path $Root 'session-new');Lease=$lease}
 }
 return @()
}
$binding=[pscustomobject]@{Login=[pscustomobject]@{control_root=$Root}}
$timeout=if($Scenario -in @('timeout','live-exit')){1}else{60}
$watch=[Diagnostics.Stopwatch]::StartNew();$message=$null
try {Wait-Schema6LoginReady -Name 'Synthetic' -Binding $binding -PreviousSessions @((Join-Path $Root 'session-old')) -TimeoutSeconds $timeout}
catch{$message=$_.Exception.Message}
[Console]::Out.WriteLine((@{format='schema6-ready-exit-test-v1';message=$message;elapsed=$watch.ElapsedMilliseconds;disposed=$script:disposed}|ConvertTo-Json -Compress))
