param(
 [Parameter(Mandatory=$true)][string]$ControlDirectory,
 [Parameter(Mandatory=$true)][string]$RunId,
 [Parameter(Mandatory=$true)][int]$ChildPid,
 [switch]$CheckDatabase,[switch]$Server,[string]$PipeName
)
$ErrorActionPreference='Stop'
$env:PSModulePath="$PSHOME\Modules"
$script:BoundParent=$null;$script:BoundGuardian=$null;$script:BoundChild=$null
$script:LockIdentities=$null;$script:LaunchText=$null;$script:GuardianText=$null
$script:ProbeKey=$null
try {
 . (Join-Path $PSScriptRoot 'protected_paths.ps1')
 . (Join-Path $PSScriptRoot 'owned_job.ps1')
 Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
public static class Schema6ProbeNative {
 [StructLayout(LayoutKind.Sequential)] struct Info {
  public uint attributes,createdLow,createdHigh,accessLow,accessHigh,writeLow,writeHigh,volume,sizeHigh,sizeLow,links,indexHigh,indexLow;
 }
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFile(string name,uint access,uint share,IntPtr security,uint disposition,uint flags,IntPtr template);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle handle,out Info info);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetNamedPipeClientProcessId(SafePipeHandle pipe,out uint pid);
 public static string FileIdentity(string path) {
  using(var handle=CreateFile(path,0,7,IntPtr.Zero,3,0x00200000,IntPtr.Zero)) {
   Info info;if(handle.IsInvalid || !GetFileInformationByHandle(handle,out info) || (info.attributes&0x400)!=0 || info.links!=1)throw new Exception("probe_identity_failed");
   return info.volume.ToString("x8")+":"+info.indexHigh.ToString("x8")+info.indexLow.ToString("x8");
  }
 }
 public static uint ClientPid(NamedPipeServerStream pipe) {uint pid;if(!GetNamedPipeClientProcessId(pipe.SafePipeHandle,out pid))throw new Exception("probe_client_failed");return pid;}
 public static bool Equal(string a,string b) {if(a==null||b==null||a.Length!=b.Length)return false;int difference=0;for(int i=0;i<a.Length;i++)difference|=a[i]^b[i];return difference==0;}
 public static string ReadFrame(Stream pipe) {
  var buffer=new byte[8193];int used=0;var deadline=System.Diagnostics.Stopwatch.StartNew();
  while(used<buffer.Length) {
   var read=pipe.ReadAsync(buffer,used,buffer.Length-used);int remaining=15000-(int)deadline.ElapsedMilliseconds;
   if(remaining<=0||!read.Wait(remaining))throw new Exception("probe_read_timeout");
   int count=read.Result;if(count==0)throw new Exception("probe_incomplete_frame");
   for(int i=used;i<used+count;i++)if(buffer[i]==10) {
    if(i!=used+count-1||i>8192)throw new Exception("probe_frame_rejected");
    return new UTF8Encoding(false,true).GetString(buffer,0,i);
   }
   used+=count;
  }
  throw new Exception("probe_frame_rejected");
 }
 public static void WriteFrame(Stream pipe,string frame) {
  var bytes=new UTF8Encoding(false,true).GetBytes(frame+"\n");if(bytes.Length>8193)throw new Exception("probe_frame_rejected");
  var write=pipe.WriteAsync(bytes,0,bytes.Length);if(!write.Wait(15000))throw new Exception("probe_write_timeout");write.GetAwaiter().GetResult();
 }
}
'@
 function Assert-BoundProcesses {
  foreach($process in @($script:BoundParent,$script:BoundGuardian,$script:BoundChild)) {
   if($null -ne $process -and $process.HasExited){throw 'offline_process_lost'}
  }
 }
 function Invoke-OfflineCheck([bool]$Database) {
  Assert-BoundProcesses
  Assert-ProtectedPath $ControlDirectory -Root
  $launchText=Get-Content -LiteralPath (Join-Path $ControlDirectory 'launch.json') -Raw -Encoding UTF8
  $launch=$launchText | ConvertFrom-Json
  if($launch.token -cne $RunId -or $launch.lifecycle -cne $PSScriptRoot -or ($null -ne $script:LaunchText -and $launchText -cne $script:LaunchText)){throw 'offline_launch_unbound'}
  $expected=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $parent=Get-Process -Id $launch.parent_pid
  $guardian=$null;$child=$null
  try {
   if($parent.StartTime.ToUniversalTime().Ticks.ToString() -cne $launch.parent_started_ticks -or $parent.Path -ine $expected){throw 'offline_parent_unbound'}
   $guardianText=Get-Content -LiteralPath (Join-Path $ControlDirectory 'guardian-ready.json') -Raw -Encoding UTF8
   $ready=$guardianText | ConvertFrom-Json
   $guardian=Get-Process -Id $ready.pid
   if($ready.run_id -cne $RunId -or $guardian.Path -ine $expected -or $guardian.StartTime.ToUniversalTime().Ticks.ToString() -cne $ready.started_ticks -or
    ($null -ne $script:GuardianText -and $guardianText -cne $script:GuardianText)){throw 'offline_guardian_unbound'}
   $child=Get-Process -Id $ChildPid
   if($child.Path -ine (Join-Path $launch.release 'runtime\node.exe') -or -not [Schema6OwnedJob]::Contains($RunId,[uint32]$ChildPid)){throw 'offline_child_not_owned'}
   if($Server -and -not [Schema6OwnedJob]::Contains($RunId,[uint32]$PID)){throw 'offline_probe_not_owned'}
   if($null -eq $script:BoundParent){
    # Retain original process handles, never just reusable PIDs. Every request
    # still re-reads and validates parent/guardian identity and Job membership.
    $null=$parent.Handle;$null=$guardian.Handle;$null=$child.Handle
    $script:BoundParent=$parent;$script:BoundGuardian=$guardian;$script:BoundChild=$child
    $script:LaunchText=$launchText;$script:GuardianText=$guardianText
    $parent=$null;$guardian=$null;$child=$null
   }
   $settings=Get-Content -LiteralPath $launch.configuration_file -Raw -Encoding UTF8 | ConvertFrom-Json
   Assert-ProtectedPath $settings.recovery_custody_directory -Root
   $lockPaths=@((Join-Path $launch.state 'shortcut-mail-relay.runtime.lock'),(Join-Path $settings.recovery_custody_directory 'custody.lock'))
   $identities=@()
   foreach($lockPath in $lockPaths){
    Assert-ProtectedPath $lockPath
    $identities += [Schema6ProbeNative]::FileIdentity($lockPath)
    $busy=$false
    try{$handle=[IO.File]::Open($lockPath,'Open','ReadWrite','None');$handle.Dispose()}catch [IO.IOException]{$busy=$true}
    if(-not $busy){throw 'offline_lock_not_held'}
   }
   if($null -ne $script:LockIdentities -and ($identities -join '|') -cne ($script:LockIdentities -join '|')){throw 'offline_lock_identity_changed'}
   $script:LockIdentities=$identities
   if($Database){
    $handles=@()
    try{
     foreach($suffix in @('','-wal','-shm','-journal')){
      $file=Join-Path $launch.state ('i-core.sqlite'+$suffix)
      if($suffix -eq '' -or [IO.File]::Exists($file)){Assert-ProtectedPath $file;$handles += [IO.File]::Open($file,'Open','ReadWrite','None')}
     }
    }finally{foreach($handle in $handles){$handle.Dispose()}}
   }
   Assert-BoundProcesses
  }finally{foreach($process in @($parent,$guardian,$child)){if($null -ne $process){$process.Dispose()}}}
 }
 function Get-FrameMac([string]$Payload,[string]$Kind){
  $hmac=[Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes($script:ProbeKey))
  try{return ([BitConverter]::ToString($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes(('i-core-native-probe-'+$Kind+'-v1'+[char]0+$Payload))))).Replace('-','').ToLowerInvariant()}
  finally{$hmac.Dispose()}
 }
 function New-ProbeFrame($Body,[string]$Kind){
  $payload=$Body | ConvertTo-Json -Depth 5 -Compress
  return (@{payload=$payload;authentication=(Get-FrameMac $payload $Kind)} | ConvertTo-Json -Compress)
 }
 if(-not $Server){
  if($PipeName){throw 'offline_probe_arguments_rejected'}
  Invoke-OfflineCheck ([bool]$CheckDatabase)
  @{parent_pid=$script:BoundParent.Id;guardian_pid=$script:BoundGuardian.Id;child_pid=$ChildPid;checked=$true} | ConvertTo-Json -Compress
 }else{
  if($CheckDatabase -or $RunId -cnotmatch '\A[a-f0-9]{64}\z' -or $PipeName -cnotmatch '\AICoreSchema6Probe-[a-f0-9]{32}\z'){throw 'offline_probe_arguments_rejected'}
  Invoke-OfflineCheck $false
  $keyPath=Join-Path $ControlDirectory 'stop.key';Assert-ProtectedPath $keyPath
  $script:ProbeKey=[IO.File]::ReadAllText($keyPath)
  if($script:ProbeKey -cnotmatch '\A[a-f0-9]{64}\z'){throw 'offline_probe_key_rejected'}
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
  $security=[IO.Pipes.PipeSecurity]::new();$security.SetOwner($sid);$security.SetAccessRuleProtection($true,$false)
  foreach($identity in @($sid,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'))){$security.AddAccessRule([IO.Pipes.PipeAccessRule]::new($identity,[IO.Pipes.PipeAccessRights]::FullControl,[Security.AccessControl.AccessControlType]::Allow))}
  $sequence=[long]0;$stopping=$false
  while(-not $stopping){
   Assert-BoundProcesses
   $pipe=[IO.Pipes.NamedPipeServerStream]::new($PipeName,[IO.Pipes.PipeDirection]::InOut,1,[IO.Pipes.PipeTransmissionMode]::Byte,[IO.Pipes.PipeOptions]::Asynchronous,8192,8192,$security)
   try{
    # Publish once per sequence only after the next server instance exists.
    # Immutable names avoid Replace racing the client's full plain-path checks.
    $readyName=if($sequence -eq 0){$PipeName+'.ready.json'}else{$PipeName+'.ready-'+$sequence+'.json'}
    $readyPath=Join-Path $ControlDirectory $readyName
    if([IO.File]::Exists($readyPath)){throw 'offline_probe_ready_exists'}
    $readyFrame=New-ProbeFrame ([ordered]@{version=1;run_id=$RunId;child_pid=$ChildPid;server_pid=$PID;pipe_name=$PipeName;sequence=$sequence}) 'ready'
     $pendingReady=$readyPath+'.pending'
     $stream=[IO.File]::Open($pendingReady,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
     try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes($readyFrame);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
     [IO.File]::Move($pendingReady,$readyPath)
    $waiting=$pipe.BeginWaitForConnection($null,$null)
    try{while(-not $waiting.AsyncWaitHandle.WaitOne(250)){Assert-BoundProcesses};$pipe.EndWaitForConnection($waiting)}finally{$waiting.AsyncWaitHandle.Dispose()}
    $peer=Get-Process -Id ([Schema6ProbeNative]::ClientPid($pipe))
    try{if($peer.Id -ne $ChildPid -or $peer.Path -ine (Join-Path (($script:LaunchText|ConvertFrom-Json).release) 'runtime\node.exe') -or -not [Schema6OwnedJob]::Contains($RunId,[uint32]$peer.Id)){throw 'offline_probe_client_unbound'}}finally{$peer.Dispose()}
    $frame=[Schema6ProbeNative]::ReadFrame($pipe)|ConvertFrom-Json
    if((($frame.PSObject.Properties.Name|Sort-Object)-join ',') -cne 'authentication,payload' -or $frame.payload -isnot [string] -or $frame.authentication -cnotmatch '\A[a-f0-9]{64}\z' -or
     -not [Schema6ProbeNative]::Equal($frame.authentication,(Get-FrameMac $frame.payload 'request'))){throw 'offline_probe_authentication_failed'}
    $request=$frame.payload|ConvertFrom-Json
    if((($request.PSObject.Properties.Name|Sort-Object)-join ',') -cne 'action,challenge,check_database,child_pid,run_id,sequence,server_pid,version' -or
     $request.version -ne 1 -or $request.run_id -cne $RunId -or $request.child_pid -ne $ChildPid -or $request.server_pid -ne $PID -or
     $request.sequence -ne ($sequence+1) -or ($request.sequence -isnot [int] -and $request.sequence -isnot [long]) -or $request.sequence -gt 9007199254740991 -or
     $request.challenge -cnotmatch '\A[a-f0-9]{64}\z' -or $request.check_database -isnot [bool] -or $request.action -cnotin @('probe','stop') -or
     ($request.action -ceq 'stop' -and $request.check_database)){throw 'offline_probe_request_rejected'}
    Invoke-OfflineCheck ([bool]$request.check_database)
    $sequence=[long]$request.sequence
    $response=[ordered]@{version=1;run_id=$RunId;child_pid=$ChildPid;server_pid=$PID;sequence=$sequence;challenge=$request.challenge;check_database=$request.check_database;action=$request.action;checked=$true}
    [Schema6ProbeNative]::WriteFrame($pipe,(New-ProbeFrame $response 'response'))
    $stopping=$request.action -ceq 'stop'
   }finally{$pipe.Dispose()}
  }
 }
}catch{[Console]::Error.WriteLine('offline_probe_failed');exit 2}
finally{
 $script:ProbeKey=$null
 foreach($process in @($script:BoundParent,$script:BoundGuardian,$script:BoundChild)){if($null -ne $process){$process.Dispose()}}
}
