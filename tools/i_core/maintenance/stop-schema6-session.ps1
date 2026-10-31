[CmdletBinding()]
param([string]$TaskName)

# Import-safe maintenance functions. No approval input, release pin, or task is
# touched on import. The only close signal is WM_CLOSE to a held host identity.
function Write-Schema6Step([string]$Step,[bool]$Ok,[string]$Detail) {
 [Console]::Out.WriteLine((@{step=$Step;ok=$Ok;detail=$Detail}|ConvertTo-Json -Compress))
}
function Invoke-Schema6Step([string]$Step,[scriptblock]$Body) {
 try {$value=& $Body;Write-Schema6Step $Step $true 'completed';return $value}
 catch {Write-Schema6Step $Step $false $_.Exception.Message;throw}
}

# This is the sole Task Scheduler boundary. Synthetic tests replace the callback
# in their own process; command-line callers cannot select an alternate adapter.
function Invoke-Schema6TaskOperation {
 param([ValidateSet('Read','Enable','Disable','Start','State')][string]$Operation,[string]$TaskName)
 if([string]::IsNullOrWhiteSpace($TaskName)){throw 'task_name_required'}
 $adapter=Get-Variable -Name Schema6TaskAdapter -Scope Script -ErrorAction SilentlyContinue
 if($adapter -and $adapter.Value){return (& $adapter.Value $Operation $TaskName)}
 $service=New-Object -ComObject 'Schedule.Service';$service.Connect()
 $qualified='\'+$TaskName.TrimStart('\');$separator=$qualified.LastIndexOf('\')
 $folderName=if($separator -eq 0){'\'}else{$qualified.Substring(0,$separator)}
 $task=$service.GetFolder($folderName).GetTask($qualified.Substring($separator+1))
 switch($Operation){
  'Read' {
   $actions=$task.Definition.Actions
   if($actions.Count -ne 1 -or $actions.Item(1).Type -ne 0){throw 'single_exec_login_action_required'}
   $action=$actions.Item(1)
   return [pscustomobject]@{Name=$TaskName;Path=[string]$action.Path;Arguments=[string]$action.Arguments;WorkingDirectory=[string]$action.WorkingDirectory;Enabled=[bool]$task.Enabled;State=[int]$task.State}
  }
  'Enable' {$task.Enabled=$true;if(-not $task.Enabled){throw 'task_enable_readback_failed'}}
  'Disable' {$task.Enabled=$false;if($task.Enabled){throw 'task_disable_readback_failed'}}
  'Start' {if(-not $task.Enabled){throw 'task_disabled'};$instance=$task.Run($null);if($null -eq $instance){throw 'task_start_unconfirmed'}}
  'State' {return [int]$task.State}
 }
}
function Assert-Schema6PlainPath([string]$Path) {
 if([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path) -or $Path -notmatch '^[A-Za-z]:[\\/]' -or $Path.Substring(2).Contains(':')){throw 'absolute_plain_path_required'}
 $full=[IO.Path]::GetFullPath($Path)
 if(-not $full.Equals($Path.Replace('/','\'),[StringComparison]::OrdinalIgnoreCase)){throw 'canonical_path_required'}
 $current=$full
 while($current){
  if(Test-Path -LiteralPath $current){if(([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'linked_path_rejected'}}
  $parent=[IO.Directory]::GetParent($current);$current=if($parent){$parent.FullName}else{$null}
 }
 return $full
}
function Read-Schema6Json([string]$Path,[string]$Sha256) {
 $plain=Assert-Schema6PlainPath $Path
 $stream=[IO.File]::Open($plain,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try {
  if($stream.Length -gt 8MB){throw 'json_input_too_large'}
  $memory=[IO.MemoryStream]::new();try{$stream.CopyTo($memory);$bytes=$memory.ToArray()}finally{$memory.Dispose()}
  if($Sha256){
   if($Sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'configuration_sha256_invalid'}
   $digest=[Security.Cryptography.SHA256]::Create()
   try{$actual=([BitConverter]::ToString($digest.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$digest.Dispose()}
   if($actual -cne $Sha256.ToLowerInvariant()){throw 'login_configuration_hash_mismatch'}
  }
  return ([Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xfeff)|ConvertFrom-Json -ErrorAction Stop)
 }finally{$stream.Dispose()}
}
function Initialize-Schema6MaintenanceNative {
 if('Schema6MaintenanceHost' -as [type]){return}
 Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
public sealed class Schema6MaintenanceHost:IDisposable {
 IntPtr process; int pid; long window; uint thread;
 [DllImport("kernel32.dll",SetLastError=true)]static extern IntPtr OpenProcess(uint access,bool inherit,int id);
 [DllImport("kernel32.dll")]static extern bool CloseHandle(IntPtr handle);
 [DllImport("kernel32.dll")]static extern uint WaitForSingleObject(IntPtr handle,uint timeout);
 [DllImport("kernel32.dll")]static extern bool GetExitCodeProcess(IntPtr handle,out uint code);
 [DllImport("kernel32.dll")]static extern bool GetProcessTimes(IntPtr handle,out long created,out long exit,out long kernel,out long user);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)]static extern bool QueryFullProcessImageName(IntPtr handle,uint flags,StringBuilder value,ref uint size);
 [DllImport("kernel32.dll")]static extern bool ProcessIdToSessionId(uint pid,out uint session);
 [DllImport("advapi32.dll",SetLastError=true)]static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
 [DllImport("user32.dll")]static extern IntPtr GetAncestor(IntPtr hwnd,uint flags);
 [DllImport("user32.dll")]static extern bool IsWindowVisible(IntPtr hwnd);
 [DllImport("user32.dll",SetLastError=true)]static extern IntPtr SendMessageTimeout(IntPtr hwnd,uint message,IntPtr wp,IntPtr lp,uint flags,uint timeout,out IntPtr result);
 [DllImport("shell32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern IntPtr CommandLineToArgvW(string value,out int count);
 [DllImport("kernel32.dll")]static extern IntPtr LocalFree(IntPtr memory);
 public static string[] Arguments(string value){
  int count;IntPtr memory=CommandLineToArgvW("maintenance.exe "+value,out count);
  if(memory==IntPtr.Zero)throw new Win32Exception();
  try{string[] result=new string[count-1];for(int i=1;i<count;i++)result[i-1]=Marshal.PtrToStringUni(Marshal.ReadIntPtr(memory,i*IntPtr.Size));return result;}finally{LocalFree(memory);}
 }
 // A stale record whose PID now belongs to a process in another logon session
 // (for example a session-0 service) cannot be our host; access to it is denied.
 // Session ids come from the process snapshot, which needs no process handle.
 static bool RecycledIntoOtherSession(int id){
  try{using(var p=System.Diagnostics.Process.GetProcessById(id))using(var self=System.Diagnostics.Process.GetCurrentProcess())return p.SessionId!=self.SessionId;}
  catch(ArgumentException){return true;}
 }
 public static Schema6MaintenanceHost Open(int id,long hwnd,long recordedTicks,string image,string owner,int session,uint tid){
  IntPtr handle=OpenProcess(0x00101000,false,id);
  if(handle==IntPtr.Zero){int error=Marshal.GetLastWin32Error();if(error==87||error==5&&RecycledIntoOtherSession(id))return null;throw new Win32Exception(error);}
  var lease=new Schema6MaintenanceHost();lease.process=handle;lease.pid=id;lease.window=hwnd;
  try{
   if(WaitForSingleObject(handle,0)!=258){lease.Dispose();return null;}
   long c,e,k,u;if(!GetProcessTimes(handle,out c,out e,out k,out u))throw new Win32Exception();
   // A recycled PID cannot make a historical window record live again.
   if(DateTime.FromFileTimeUtc(c).Ticks>recordedTicks){lease.Dispose();return null;}
   uint size=32768;var name=new StringBuilder(32768);
   if(!QueryFullProcessImageName(handle,0,name,ref size)||!String.Equals(name.ToString(),image,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("session_host_image_mismatch");
   IntPtr token;if(!OpenProcessToken(handle,8,out token))throw new Win32Exception();
   try{using(var identity=new WindowsIdentity(token)){if(identity.User.Value!=owner)throw new InvalidOperationException("session_host_owner_mismatch");}}finally{CloseHandle(token);}
   uint actualSession;if(!ProcessIdToSessionId((uint)id,out actualSession)||actualSession!=(uint)System.Diagnostics.Process.GetCurrentProcess().SessionId||(session>=0&&actualSession!=(uint)session))throw new InvalidOperationException("session_host_session_mismatch");
   uint actual;lease.thread=GetWindowThreadProcessId(new IntPtr(hwnd),out actual);
   if(lease.thread==0){
    if(WaitForSingleObject(handle,10000)==0){lease.Dispose();return null;}
    throw new InvalidOperationException("session_host_window_mismatch");
   }
   if(actual!=(uint)id||(tid!=0&&tid!=lease.thread)||GetAncestor(new IntPtr(hwnd),2)!=new IntPtr(hwnd)||IsWindowVisible(new IntPtr(hwnd)))throw new InvalidOperationException("session_host_window_mismatch");
   return lease;
  }catch{lease.Dispose();throw;}
 }
 public void CloseWindow(uint timeout){
  uint actual;if(WaitForSingleObject(process,0)!=258||GetWindowThreadProcessId(new IntPtr(window),out actual)!=thread||actual!=(uint)pid)throw new InvalidOperationException("session_host_changed");
  IntPtr result;if(SendMessageTimeout(new IntPtr(window),0x0010,IntPtr.Zero,IntPtr.Zero,2,timeout,out result)==IntPtr.Zero)throw new InvalidOperationException("session_close_message_timeout");
 }
 public uint WaitClosed(uint timeout){
  if(WaitForSingleObject(process,timeout)!=0)throw new InvalidOperationException("session_close_exit_timeout");
  uint code;if(!GetExitCodeProcess(process,out code))throw new Win32Exception();return code;
 }
 public void Dispose(){if(process!=IntPtr.Zero){CloseHandle(process);process=IntPtr.Zero;}}
}
"@
}
function Get-Schema6LoginBinding([string]$TaskName) {
 $task=Invoke-Schema6TaskOperation -Operation Read -TaskName $TaskName
 Initialize-Schema6MaintenanceNative
 $arguments=[Schema6MaintenanceHost]::Arguments([string]$task.Arguments)
 $values=@{}
 for($i=0;$i -lt $arguments.Count;$i++){
  $key=switch -Regex ($arguments[$i]){'^-(Login)?ConfigurationPath$' {'path'};'^-(Login)?ConfigurationSha256$' {'hash'};default {$null}}
  if($key){if($values.ContainsKey($key) -or $i+1 -ge $arguments.Count){throw 'login_task_arguments_ambiguous'};$i++;$values[$key]=$arguments[$i]}
 }
 if(-not $values.path -or -not $values.hash){throw 'login_task_configuration_arguments_required'}
 $login=Read-Schema6Json $values.path $values.hash
 if($login.format -cne 'schema6-login-v1' -or $login.owner_sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'login_configuration_owner_or_format_mismatch'}
 foreach($p in @($login.state_directory,$login.control_root)){$plain=Assert-Schema6PlainPath $p;if(-not [IO.Directory]::Exists($plain)){throw 'login_directory_missing'}}
 $state=[IO.Path]::GetFullPath($login.state_directory);$control=[IO.Path]::GetFullPath($login.control_root)
 if($state.Equals($control,[StringComparison]::OrdinalIgnoreCase) -or $state.StartsWith($control+'\',[StringComparison]::OrdinalIgnoreCase) -or $control.StartsWith($state+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'login_separate_control_required'}
 if($login.core_port -isnot [int] -or $login.core_port -lt 1 -or $login.core_port -gt 65535){throw 'login_core_port_invalid'}
 $mcpPort=$null
 if(($login.PSObject.Properties.Name -contains 'mcp_configuration_path') -and $login.mcp_configuration_path){
  if(-not $login.mcp_configuration_sha256){throw 'mcp_configuration_hash_required'}
  $mcp=Read-Schema6Json $login.mcp_configuration_path $login.mcp_configuration_sha256
  if($mcp.format -cne 'schema6-mcp-v1' -or $mcp.owner_sid -cne $login.owner_sid -or $mcp.listen_host -cne '127.0.0.1' -or $mcp.database_path -ine (Join-Path $state 'i-core.sqlite')){throw 'mcp_configuration_binding_mismatch'}
  if($mcp.listen_port -isnot [int] -or $mcp.listen_port -lt 1 -or $mcp.listen_port -gt 65535 -or $mcp.listen_port -eq $login.core_port){throw 'mcp_listen_port_invalid'}
  $mcpPort=$mcp.listen_port
 }
 return [pscustomobject]@{Task=$task;Login=$login;ConfigurationPath=$values.path;ConfigurationSha256=$values.hash.ToLowerInvariant();CorePort=$login.core_port;McpPort=$mcpPort}
}
function Assert-Schema6NoRecovery($Binding) {
 if(Test-Path -LiteralPath (Join-Path $Binding.Login.state_directory 's6-recovery-pending.json')){throw 'recovery_pending_manual_review_required'}
}
function Assert-Schema6ClosedFiles($Binding) {
 Assert-Schema6NoRecovery $Binding
 $sidecars=@(Get-ChildItem -LiteralPath $Binding.Login.state_directory -File -Force -ErrorAction Stop|Where-Object {$_.Name -match '-(wal|shm|journal)$'})
 if(@($sidecars|Where-Object {$_.Name -match '^i-core\.sqlite-(wal|shm|journal)$'}).Count -gt 0){throw 'database_sidecars_present'}
 if($sidecars.Count -gt 0){
  [string[]]$names=@($sidecars|ForEach-Object {$_.Name})
  [Array]::Sort($names,[StringComparer]::Ordinal)
  Write-Schema6Step 'stop.closed_files_other_sidecars' $true ($names -join ',')
 }
 $lockPath=Join-Path $Binding.Login.state_directory 'shortcut-mail-relay.runtime.lock'
 if(Test-Path -LiteralPath $lockPath){
  $null=Assert-Schema6PlainPath $lockPath
  try {$probe=[IO.File]::Open($lockPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)}
  catch [IO.IOException] {throw 'relay_lock_held'}
  $probe.Dispose()
 }
}
function Get-Schema6LiveSessions($Binding) {
 Initialize-Schema6MaintenanceNative
 $result=@();$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $image=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 try {
  foreach($directory in @(Get-ChildItem -LiteralPath $Binding.Login.control_root -Directory -Filter 'session-*' -ErrorAction Stop|Sort-Object LastWriteTimeUtc -Descending)){
   $file=Join-Path $directory.FullName 'session-window.json';if(-not (Test-Path -LiteralPath $file)){continue}
   $window=Read-Schema6Json $file
   if($window.pid -le 0 -or $window.hwnd -le 0 -or $window.hook_ready -ne $true){throw 'session_window_record_invalid'}
   $sessionId=if($window.PSObject.Properties.Name -contains 'session_id'){[int]$window.session_id}else{-1}
   $tid=if($window.PSObject.Properties.Name -contains 'thread_id'){[uint32]$window.thread_id}else{0}
   $lease=[Schema6MaintenanceHost]::Open([int]$window.pid,[long]$window.hwnd,(Get-Item -LiteralPath $file).LastWriteTimeUtc.Ticks,$image,$owner,$sessionId,$tid)
   if($lease){$result += [pscustomobject]@{Directory=$directory.FullName;Window=$window;Lease=$lease}}
  }
  return $result
 }catch{foreach($s in $result){$s.Lease.Dispose()};throw}
}
function Assert-Schema6CloseReceipts($Binding,$Session) {
 $exit=Read-Schema6Json (Join-Path $Session.Directory 'session-exit.json')
 foreach($key in @('clean_closed','core_job_empty_confirmed','backup_job_empty_confirmed','mcp_job_empty_confirmed','mcp_owned_tree_handles_released_confirmed')){if($exit.$key -ne $true){throw ('session_exit_unconfirmed:'+ $key)}}
 if($exit.forced_timeout -ne $false -or $exit.termination_requested -ne $false -or $exit.mcp_failure -ne $false -or (Test-Path -LiteralPath (Join-Path $Session.Directory 'session-exit-over-budget.json'))){throw 'session_exit_not_clean'}
 $controls=@(Get-ChildItem -LiteralPath $Session.Directory -Directory -Filter 'control-*'|Sort-Object LastWriteTimeUtc -Descending)
 if($controls.Count -eq 0){throw 'session_control_missing'}
 $current=$controls[0].FullName
 $launch=Read-Schema6Json (Join-Path $current 'launch.json')
 $child=Read-Schema6Json (Join-Path $current 'child.json')
 $close=Read-Schema6Json (Join-Path $current 'session-close.json')
 $marker=Read-Schema6Json (Join-Path $Binding.Login.state_directory 's6-lifecycle.json')
 foreach($r in @($child,$marker)){
  if($r.phase -cne 'clean_closed' -or $r.token -cne $launch.token -or $r.manifest_sha256 -cne $Session.Window.manifest_sha256){throw 'lifecycle_not_clean_closed'}
 }
 if($child.store_close_confirmed -ne $true -or $child.listener_closed_confirmed -ne $true -or $marker.configuration_sha256 -cne $Binding.Login.core_configuration_sha256){throw 'core_close_unconfirmed'}
 if($close.clean_closed -ne $true -or $close.completion_confirmed -ne $true -or $close.core_forced -ne $false -or $close.database_exclusive_open_confirmed -ne $true){throw 'window_close_unconfirmed'}
 $supervisor=Read-Schema6Json (Join-Path $current 'supervisor.json');$guardian=Read-Schema6Json (Join-Path $current 'guardian.json')
 foreach($key in @('child_receipt_confirmed','guardian_receipt_confirmed','lock_released_confirmed')){if($supervisor.$key -ne $true){throw 'supervisor_close_unconfirmed'}}
 foreach($key in @('job_empty_confirmed','child_exit_confirmed','child_exit_code_confirmed','guardian_exit_confirmed','guardian_exit_code_confirmed')){if($supervisor.result.$key -ne $true){throw 'supervisor_close_unconfirmed'}}
 if($supervisor.token -cne $launch.token -or $supervisor.result.child_exit_code -ne 0 -or $supervisor.result.guardian_exit_code -ne 0 -or $supervisor.result.termination_requested -ne $false -or $guardian.run_id -cne $launch.token -or $guardian.result.job_empty_confirmed -ne $true -or $guardian.result.parent_exit_observed -ne $false){throw 'supervisor_exit_unconfirmed'}
 foreach($d in $controls){
  $startPath=Join-Path $d.FullName 'mcp-start.json';$stopPath=Join-Path $d.FullName 'mcp-stop.json'
  $hasStart=Test-Path -LiteralPath $startPath;$hasStop=Test-Path -LiteralPath $stopPath
  if($hasStart -ne $hasStop -or ($d.FullName -eq $current -and $Binding.McpPort -and -not $hasStart)){throw 'mcp_receipts_not_paired'}
  if($hasStart){
   $start=Read-Schema6Json $startPath;$stop=Read-Schema6Json $stopPath;$generation=Read-Schema6Json (Join-Path $d.FullName 'launch.json')
   if($start.core_token -cne $generation.token -or $start.pid -ne $stop.pid -or $start.started_ticks -cne $stop.started_ticks -or $stop.scope -cne 'owned_mcp_job_only' -or $stop.mcp_failure -ne $false){throw 'mcp_receipt_binding_mismatch'}
   foreach($key in @('job_empty_confirmed','process_exit_confirmed','owned_tree_handles_released_confirmed')){if($stop.$key -ne $true){throw 'mcp_stop_unconfirmed'}}
  }
 }
}
function Invoke-Schema6StopBinding {
 param($Binding,[string[]]$PreviousSessions=@(),[switch]$RequireCleanNewSessions)
 $watch=[Diagnostics.Stopwatch]::StartNew();$sessions=@()
 try {
  do {
   $sessions=@(Invoke-Schema6Step 'stop.locate_session' {Get-Schema6LiveSessions $Binding})
   $taskState=Invoke-Schema6TaskOperation -Operation State -TaskName $Binding.Task.Name
   if($sessions.Count -gt 0 -or $taskState -notin @(2,4)){break}
   if($watch.ElapsedMilliseconds -ge 35000){throw 'task_running_without_close_window'}
   Start-Sleep -Milliseconds 100
  }while($true)
  if($sessions.Count -eq 0){
   if($RequireCleanNewSessions){
    Invoke-Schema6Step 'stop.new_session_receipts' {
     foreach($d in @(Get-ChildItem -LiteralPath $Binding.Login.control_root -Directory -Filter 'session-*')){
      if($PreviousSessions -contains $d.FullName){continue}
      $windowPath=Join-Path $d.FullName 'session-window.json'
      if(Test-Path -LiteralPath $windowPath){Assert-Schema6CloseReceipts $Binding ([pscustomobject]@{Directory=$d.FullName;Window=(Read-Schema6Json $windowPath)})}
     }
    }
   }
   Invoke-Schema6Step 'stop.closed_files' {Assert-Schema6ClosedFiles $Binding}
   Write-Schema6Step 'stop.result' $true 'already_stopped'
   return [pscustomobject]@{status='already_stopped';login=$Binding}
  }
  if($sessions.Count -ne 1){throw 'multiple_live_sessions_manual_review_required'}
  $session=$sessions[0]
  Invoke-Schema6Step 'stop.wm_close' {
   $remaining=35000-$watch.ElapsedMilliseconds
   if($remaining -le 0){throw 'session_close_exit_timeout'}
   $session.Lease.CloseWindow([uint32][Math]::Min(5000,$remaining))
  }
  Invoke-Schema6Step 'stop.host_exit' {
   $remaining=35000-$watch.ElapsedMilliseconds
   if($remaining -le 0 -or $session.Lease.WaitClosed([uint32]$remaining) -ne 0){throw 'session_host_exit_not_zero'}
   while((Invoke-Schema6TaskOperation -Operation State -TaskName $Binding.Task.Name) -in @(2,4)){
    if($watch.ElapsedMilliseconds -ge 35000){throw 'task_exit_unconfirmed'}
    Start-Sleep -Milliseconds 100
   }
  }
  Invoke-Schema6Step 'stop.receipts' {Assert-Schema6CloseReceipts $Binding $session}
  Invoke-Schema6Step 'stop.closed_files' {Assert-Schema6ClosedFiles $Binding}
  Write-Schema6Step 'stop.result' $true 'clean_closed'
  return [pscustomobject]@{status='clean_closed';login=$Binding}
 }finally{foreach($s in $sessions){$s.Lease.Dispose()}}
}
function Invoke-Schema6SessionStop([string]$TaskName) {
 if($PSVersionTable.PSVersion.Major-ne 5 -or $PSVersionTable.PSEdition-ne 'Desktop'){throw 'windows_powershell_51_required'}
 $binding=Invoke-Schema6Step 'stop.login_configuration' {Get-Schema6LoginBinding $TaskName}
 return (Invoke-Schema6StopBinding $binding)
}
if($MyInvocation.InvocationName -ne '.') {
 $ErrorActionPreference='Stop'
 try {$null=Invoke-Schema6SessionStop -TaskName $TaskName;exit 0}
 catch {Write-Schema6Step 'stop.failed' $false $_.Exception.Message;exit 2}
}
