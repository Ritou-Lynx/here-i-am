$ErrorActionPreference='Stop'
$script:CrossUserNodeDiagnostic=$null
function Assert-CrossUserCI([switch]$Parent) {
 if($env:OS -ne 'Windows_NT' -or $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or $env:RUNNER_OS -cne 'Windows'){throw 'hosted_windows_ci_required'}
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 if($Parent){
  if(($identity.Name.Split('\')[-1]) -ine 'runneradmin' -or -not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'hosted_runneradmin_required'}
 } elseif(($identity.Name.Split('\')[-1]) -notmatch '^s6cu_[a-f0-9]{12}$'){throw 'temporary_ci_identity_required'}
}
function Set-CrossUserDirectoryAcl([string]$Path,[string]$Owner,[string]$ReadSid='') {
 $acl=New-Object Security.AccessControl.DirectorySecurity
 $acl.SetOwner([Security.Principal.SecurityIdentifier]::new($Owner));$acl.SetAccessRuleProtection($true,$false)
 foreach($sid in @($Owner,'S-1-5-18')){$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))}
 if($ReadSid){$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($ReadSid),'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow'))}
 Set-Acl -LiteralPath $Path -AclObject $acl
}
function Get-CrossUserHash([string]$Text) {
 $h=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
}
function ConvertTo-CrossUserSafeErrorId([string]$id) {
 # Explicit error-token allowlist: PowerShell also uses thrown message as FQID.
 $id=$id.Split(',')[0]
 if($id -cnotin @('AccessDenied','PermissionDenied','MemberExists','MemberNotFound','PrincipalNotFound','UserNotFound','GroupNotFound','InvalidOperation','InvalidOperationException','System.InvalidOperationException','System.ArgumentException','System.UnauthorizedAccessException','System.Management.Automation.ParameterBindingException','ParameterArgumentTransformationError','ParameterBindingFailed','CouldNotStartService','CouldNotStopService','ServiceCommandException','SetAcl_AclObject','UnauthorizedAccessException')){$id='redacted'}
 return $id
}
function ConvertTo-CrossUserSafeExceptionType([string]$Type) {
 if($Type -cin @('System.Exception','System.ArgumentException','System.ArgumentNullException','System.InvalidOperationException','System.UnauthorizedAccessException','System.IO.IOException','System.IO.EndOfStreamException','System.IO.FileNotFoundException','System.IO.DirectoryNotFoundException','System.TimeoutException','System.AggregateException','System.ObjectDisposedException','System.ComponentModel.Win32Exception','System.Security.SecurityException','System.Management.Automation.RuntimeException','System.Management.Automation.MethodInvocationException','System.Management.Automation.ParameterBindingException','System.Management.Automation.ParameterBindingArgumentTransformationException','System.Management.Automation.CmdletInvocationException','System.Management.Automation.ActionPreferenceStopException','System.Management.Automation.PSInvalidCastException')){return $Type}
 return 'redacted'
}
function Get-CrossUserSafeError([Management.Automation.ErrorRecord]$Record) {
 # Never serialize ErrorRecord, Message, TargetObject, stack, or arbitrary throw text.
 $type=ConvertTo-CrossUserSafeExceptionType $Record.Exception.GetType().FullName
 $native=$null;$inner=$Record.Exception
 for($depth=0;$inner -and $depth -lt 5;$depth++){
  if($inner.GetType() -eq [ComponentModel.Win32Exception]){$native=[int]$inner.NativeErrorCode;break};$inner=$inner.InnerException
 }
 return @{exceptionType=$type;hResult=[int]$Record.Exception.HResult;nativeErrorCode=$native;fullyQualifiedErrorId=(ConvertTo-CrossUserSafeErrorId ([string]$Record.FullyQualifiedErrorId))}
}
function ConvertTo-CrossUserSafeNodeDiagnostic($Value) {
 if((@($Value.PSObject.Properties.Name|Sort-Object) -join ',') -cne 'errorCodeSha256,phase'){return $null}
 if($Value.phase -isnot [string] -or $Value.phase -cnotin @('input','module_load','factory_runtime','factory_source','factory_archive','factory_copy','restore')){return $null}
 if($Value.errorCodeSha256 -isnot [string] -or $Value.errorCodeSha256 -cnotmatch '\A[a-f0-9]{64}\z'){return $null}
 return @{phase=[string]$Value.phase;errorCodeSha256=[string]$Value.errorCodeSha256}
}
function Read-CrossUserSafeNodeDiagnostic([string]$Text) {
 if(-not $Text -or $Text.Length -gt 8192){return $null}
 $lines=@($Text -split "`n");if($lines.Count -gt 16){return $null}
 foreach($line in $lines){
  if($line.Length -gt 2048){continue}
  try{
   $value=$line|ConvertFrom-Json -ErrorAction Stop
   if((@($value.PSObject.Properties.Name|Sort-Object) -join ',') -cne 'errorCodeSha256,fixtureRejected,phase' -or $value.fixtureRejected -isnot [bool] -or $value.fixtureRejected -ne $true){continue}
   $safe=ConvertTo-CrossUserSafeNodeDiagnostic ([pscustomobject]@{phase=$value.phase;errorCodeSha256=$value.errorCodeSha256})
   if($safe){return $safe}
  }catch{}
 }
 return $null
}
function Read-CrossUserSafeChildDiagnostic([string]$Text) {
 # No raw stderr survives this boundary, including JSON with extra fields.
 if(-not $Text -or $Text.Length -gt 8192){return $null}
 $lines=@($Text -split "`n");if($lines.Count -gt 16){return $null}
 $phases=@('child_hosted_guard','child_identity','child_standard_token','child_workspace_create','child_workspace_owner','child_workspace_acl','child_pipe_connect','child_secret_frame','child_native_initialize','child_pipe_server_identity','child_transport_anchor','child_copy','child_copied_owner','child_restore_inspection','child_report_frame')
 foreach($line in $lines){
  if($line.Length -gt 2048){continue}
  try {
   $value=$line|ConvertFrom-Json -ErrorAction Stop
   if((@($value.PSObject.Properties.Name|Sort-Object) -join ',') -cne 'childRejected,failureDiagnostic,failurePhase,nodeDiagnostic' -or $value.childRejected -isnot [bool] -or $value.childRejected -ne $true -or $value.failurePhase -isnot [string] -or $value.failurePhase -cnotin $phases){continue}
   $d=$value.failureDiagnostic
   if((@($d.PSObject.Properties.Name|Sort-Object) -join ',') -cne 'exceptionType,fullyQualifiedErrorId,hResult,nativeErrorCode'){continue}
   if($d.exceptionType -isnot [string] -or (ConvertTo-CrossUserSafeExceptionType $d.exceptionType) -cne $d.exceptionType){continue}
   if($d.fullyQualifiedErrorId -isnot [string] -or (ConvertTo-CrossUserSafeErrorId $d.fullyQualifiedErrorId) -cne $d.fullyQualifiedErrorId){continue}
   if(($d.hResult -isnot [int] -and $d.hResult -isnot [long]) -or $d.hResult -lt [int]::MinValue -or $d.hResult -gt [int]::MaxValue){continue}
   if($null -ne $d.nativeErrorCode -and (($d.nativeErrorCode -isnot [int] -and $d.nativeErrorCode -isnot [long]) -or $d.nativeErrorCode -lt [int]::MinValue -or $d.nativeErrorCode -gt [int]::MaxValue)){continue}
   $node=$null
   if($null -ne $value.nodeDiagnostic){
    if($value.failurePhase -cne 'child_restore_inspection'){continue}
    $node=ConvertTo-CrossUserSafeNodeDiagnostic $value.nodeDiagnostic
    if(-not $node){continue}
   }
   return @{childRejected=$true;failurePhase=[string]$value.failurePhase;nodeDiagnostic=$node;failureDiagnostic=@{exceptionType=[string]$d.exceptionType;hResult=[int]$d.hResult;nativeErrorCode=$d.nativeErrorCode;fullyQualifiedErrorId=[string]$d.fullyQualifiedErrorId}}
  } catch { }
 }
 return $null
}
function Initialize-CrossUserNative {
 Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;
public static class CrossUserSecondaryLogon {
 [StructLayout(LayoutKind.Sequential)] struct Status {public uint type,state,accepted,exitCode,specificExitCode,checkpoint,waitHint;}
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenSCManager(string machine,string database,uint access);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenService(IntPtr manager,string name,uint access);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool ControlService(IntPtr service,uint control,out Status status);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool CloseServiceHandle(IntPtr handle);
 // Fixed service only; no dependency traversal, process termination, or FORCE.
 public static int Stop() {
  IntPtr manager=IntPtr.Zero,service=IntPtr.Zero;int error=0;
  try {
   manager=OpenSCManager(null,null,1);
   if(manager==IntPtr.Zero)error=Marshal.GetLastWin32Error();
   else {
    service=OpenService(manager,"seclogon",0x20);
    if(service==IntPtr.Zero)error=Marshal.GetLastWin32Error();
    else {Status status;if(!ControlService(service,1,out status))error=Marshal.GetLastWin32Error();}
   }
  } finally {
   if(service!=IntPtr.Zero&&!CloseServiceHandle(service)&&error==0)error=Marshal.GetLastWin32Error();
   if(manager!=IntPtr.Zero&&!CloseServiceHandle(manager)&&error==0)error=Marshal.GetLastWin32Error();
  }
  return error;
 }
}
public static class CrossUserTokenOwner {
 [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr p);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr p,uint access,out IntPtr token);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr token,int info,IntPtr data,int size,out int needed);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool SetTokenInformation(IntPtr token,int info,IntPtr data,int size);
 public static string Set(string owner){
  IntPtr token;if(!OpenProcessToken(GetCurrentProcess(),0x0088,out token))throw new Exception("ci_token_open_failed");
  IntPtr previous=IntPtr.Zero,sidBuffer=IntPtr.Zero,ownerBuffer=IntPtr.Zero;
  try{int length;GetTokenInformation(token,4,IntPtr.Zero,0,out length);previous=Marshal.AllocHGlobal(length);
   if(!GetTokenInformation(token,4,previous,length,out length))throw new Exception("ci_token_read_failed");
   string old=new SecurityIdentifier(Marshal.ReadIntPtr(previous)).Value;if(old==owner)return old;
   var sid=new SecurityIdentifier(owner);byte[] bytes=new byte[sid.BinaryLength];sid.GetBinaryForm(bytes,0);
   sidBuffer=Marshal.AllocHGlobal(bytes.Length);Marshal.Copy(bytes,0,sidBuffer,bytes.Length);ownerBuffer=Marshal.AllocHGlobal(IntPtr.Size);Marshal.WriteIntPtr(ownerBuffer,sidBuffer);
   if(!SetTokenInformation(token,4,ownerBuffer,IntPtr.Size))throw new Exception("ci_token_owner_failed");return old;
  }finally{if(previous!=IntPtr.Zero)Marshal.FreeHGlobal(previous);if(sidBuffer!=IntPtr.Zero)Marshal.FreeHGlobal(sidBuffer);if(ownerBuffer!=IntPtr.Zero)Marshal.FreeHGlobal(ownerBuffer);CloseHandle(token);}
 }
}
public sealed class CrossUserJob:IDisposable {
 [StructLayout(LayoutKind.Sequential)] struct Basic {public long a,b;public uint flags;public UIntPtr c,d;public uint e;public UIntPtr f;public uint g,h;}
 [StructLayout(LayoutKind.Sequential)] struct Io {public ulong a,b,c,d,e,f;}
 [StructLayout(LayoutKind.Sequential)] struct Limits {public Basic basic;public Io io;public UIntPtr a,b,c,d;}
 [StructLayout(LayoutKind.Sequential)] struct Accounting {public long a,b,c,d;public uint faults,total,active,terminated;}
 [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr p,string n);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr j,int c,ref Limits l,uint s);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr j,IntPtr p);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr j,int c,out Accounting a,uint s,IntPtr r);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool TerminateJobObject(IntPtr j,uint c);
 [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr p,uint c);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool CloseHandle(IntPtr h);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool GetNamedPipeClientProcessId(Microsoft.Win32.SafeHandles.SafePipeHandle h,out uint id);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool GetNamedPipeServerProcessId(Microsoft.Win32.SafeHandles.SafePipeHandle h,out uint id);
 IntPtr job;
 public CrossUserJob(){job=CreateJobObject(IntPtr.Zero,null);Limits l=new Limits();l.basic.flags=0x2000;if(job==IntPtr.Zero||!SetInformationJobObject(job,9,ref l,(uint)Marshal.SizeOf(typeof(Limits))))throw new Exception("ci_job_failed");}
 public void Add(Process p){if(!AssignProcessToJobObject(job,p.Handle))throw new Exception("ci_job_assignment_failed");}
 public static bool StopUnassigned(Process p){if(!p.HasExited&&!TerminateProcess(p.Handle,125))return false;return p.WaitForExit(15000);}
 public bool Empty(){Accounting a;if(!QueryInformationJobObject(job,1,out a,(uint)Marshal.SizeOf(typeof(Accounting)),IntPtr.Zero))throw new Exception("ci_job_query_failed");return a.active==0;}
 public bool Stop(){if(!TerminateJobObject(job,125))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(),"ci_job_terminate_failed");var clock=Stopwatch.StartNew();while(!Empty()&&clock.ElapsedMilliseconds<15000)System.Threading.Thread.Sleep(25);return Empty();}
 public void Dispose(){if(job!=IntPtr.Zero){bool terminated=TerminateJobObject(job,125);int error=terminated?0:Marshal.GetLastWin32Error();bool closed=CloseHandle(job);if(!closed&&terminated)error=Marshal.GetLastWin32Error();if(closed)job=IntPtr.Zero;if(!terminated||!closed)throw new System.ComponentModel.Win32Exception(error,"ci_job_dispose_failed");}}
}
'@
}
# This state machine is test-only and accepts pure callbacks for deterministic
# simulations. Native adapters below remain guarded and fixed to seclogon.
function New-CrossUserServiceEvidence {
 return @{initialState=0;lastState=0;canStop=$false;beforeStopState=0;beforeStopCanStop=$false;afterStopState=0;afterStopCanStop=$false;startedByFixture=$false;stopAttempts=0;nativeErrorCode=0;startElapsedMilliseconds=0;restoreElapsedMilliseconds=0;timedOut=$false}
}
function Invoke-CrossUserServiceTransition {
 param([ValidateSet('Start','Restore')][string]$Mode,[hashtable]$Evidence,
       [scriptblock]$Query,[scriptblock]$Start,[scriptblock]$Stop,
       [scriptblock]$Elapsed,[scriptblock]$Delay,[int]$TimeoutMilliseconds=60000)
 if($TimeoutMilliseconds -le 0){throw 'ci_service_budget_invalid'}
 # ServiceControllerStatus: 1 Stopped, 2 StartPending, 3 StopPending, 4 Running,
 # 5 ContinuePending, 6 PausePending, 7 Paused. Only fresh observations count.
 $stopAttempted=$false;$startAttempted=$false
 try {
  while($true) {
   $snapshot=& $Query
   $state=[int]$snapshot.State
   if($state -lt 1 -or $state -gt 7 -or $snapshot.CanStop -isnot [bool]){throw 'ci_service_state_invalid'}
   if($Mode -eq 'Start' -and $Evidence.initialState -eq 0){$Evidence.initialState=$state}
   $Evidence.lastState=$state;$Evidence.canStop=$snapshot.CanStop
   if($Mode -eq 'Restore' -and $stopAttempted -and $Evidence.afterStopState -eq 0){$Evidence.afterStopState=$state;$Evidence.afterStopCanStop=$snapshot.CanStop}
   if($Mode -eq 'Restore' -and $state -eq 1){return}
   if($Mode -eq 'Start' -and $state -eq 4){return}
   if((& $Elapsed) -ge $TimeoutMilliseconds){$Evidence.timedOut=$true;throw 'ci_service_transition_timeout'}
   if($Mode -eq 'Start') {
    if($state -eq 1) {
     if($startAttempted){throw 'ci_service_start_returned_stopped'}
     $startAttempted=$true
     $errorCode=[int](& $Start)
     $Evidence.nativeErrorCode=$errorCode
     if($errorCode -eq 0){$Evidence.startedByFixture=$true}
     elseif($errorCode -ne 1056){throw 'ci_service_start_rejected'}
     # 1056 is a concurrent start: do not claim ownership or stop it later.
    } elseif($state -eq 7){throw 'ci_service_initial_paused'}
   } else {
    if(-not $Evidence.startedByFixture){throw 'ci_service_restore_not_owned'}
    if($state -eq 4 -and $snapshot.CanStop -and -not $stopAttempted) {
     $stopAttempted=$true;$Evidence.stopAttempts++;$Evidence.beforeStopState=$state;$Evidence.beforeStopCanStop=$snapshot.CanStop
     $errorCode=[int](& $Stop);$Evidence.nativeErrorCode=$errorCode
     if($errorCode -notin @(0,1052,1061,1062)){throw 'ci_service_stop_rejected'}
     # Re-query even after 1052/1061/1062. Never count an error as Stopped,
     # and never resend STOP blindly. Accepted STOP is sent at most once.
    }
   }
   & $Delay
  }
 } finally {
  $elapsedMs=[long](& $Elapsed)
  if($Mode -eq 'Start'){$Evidence.startElapsedMilliseconds=$elapsedMs}else{$Evidence.restoreElapsedMilliseconds=$elapsedMs}
 }
}
function Invoke-CrossUserSecondaryLogon([ValidateSet('Start','Restore')][string]$Mode,[hashtable]$Evidence) {
 Assert-CrossUserCI -Parent
 $controller=[ServiceProcess.ServiceController]::new('seclogon')
 $clock=[Diagnostics.Stopwatch]::StartNew()
 try {
  Invoke-CrossUserServiceTransition -Mode $Mode -Evidence $Evidence -Query {
   $controller.Refresh()
   [pscustomobject]@{State=[int]$controller.Status;CanStop=[bool]$controller.CanStop}
  } -Start {
   try{$controller.Start();return 0}catch{
    $safeError=Get-CrossUserSafeError $_
    if($null -eq $safeError.nativeErrorCode){throw}
    return [int]$safeError.nativeErrorCode
   }
  } -Stop { [CrossUserSecondaryLogon]::Stop() } -Elapsed { $clock.ElapsedMilliseconds } -Delay { Start-Sleep -Milliseconds 250 }
 } finally {$controller.Dispose()}
}
function Invoke-CrossUserNode([string]$Node,[string]$Script,[string]$Mode,[string]$ProductionRoot,[string]$Workspace,[byte[]]$Secret) {
 $script:CrossUserNodeDiagnostic=$null
 $info=New-Object Diagnostics.ProcessStartInfo
 $info.FileName=$Node;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
 $arguments=@($Script,$Mode,$ProductionRoot,$Workspace)
 $info.Arguments=($arguments|ForEach-Object{if($_.Contains('"') -or $_.Contains("`n") -or $_.EndsWith('\')){throw 'ci_argument_rejected'};'"'+$_+'"'}) -join ' '
 $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $info.EnvironmentVariables.Clear()
 foreach($name in @('SystemRoot','WINDIR','TEMP','TMP')){$info.EnvironmentVariables[$name]=[Environment]::GetEnvironmentVariable($name)}
 $p=New-Object Diagnostics.Process;$p.StartInfo=$info;$job=New-Object CrossUserJob;$started=$false;$assigned=$false
 try {
  # .NET Framework creates the redirected stdin StreamWriter during Start and
  # AutoFlush can emit Console.InputEncoding's BOM before any BaseStream write.
  $previousInputEncoding=[Console]::InputEncoding
  try{[Console]::InputEncoding=[Text.UTF8Encoding]::new($false);$null=$p.Start();$started=$true}finally{[Console]::InputEncoding=$previousInputEncoding}
  $job.Add($p);$assigned=$true
  $output=$p.StandardOutput.ReadToEndAsync();$errors=$p.StandardError.ReadToEndAsync()
  $p.StandardInput.BaseStream.Write($Secret,0,$Secret.Length);$p.StandardInput.Close()
  if(-not $p.WaitForExit(180000)){throw 'ci_node_timeout'}
  $text=$output.GetAwaiter().GetResult();$errorText=$errors.GetAwaiter().GetResult()
  if($p.ExitCode -ne 0 -or $text.Length -gt 65536 -or -not $job.Empty()){
   $script:CrossUserNodeDiagnostic=Read-CrossUserSafeNodeDiagnostic $errorText
   throw 'ci_node_rejected'
  }
  return ($text|ConvertFrom-Json)
 } finally {
  $closed=$true
  try{if($started -and -not $assigned){$closed=[CrossUserJob]::StopUnassigned($p)};if(-not $job.Stop()){$closed=$false}}finally{try{$job.Dispose()}finally{$p.Dispose()}}
  if(-not $closed){throw 'ci_node_cleanup_unconfirmed'}
 }
}
