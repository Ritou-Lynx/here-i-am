# CI fixture only. Dot-sourcing defines functions without reading or changing machine state.
function Assert-Schema6ModuleScopeHost([switch]$GuardOnly) {
 if($GuardOnly -or [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
    $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
    $env:RUNNER_OS -cne 'Windows' -or $PSVersionTable.PSVersion.Major -ne 5 -or
    -not [Environment]::Is64BitProcess){throw 'module_scope_host_rejected'}
}

# This state machine has no machine APIs. Tests supply memory-only operations.
function Invoke-Schema6ModuleScopeState([hashtable]$Operations,[scriptblock]$Body) {
 $state=@{registryAttempt=@($false,$false);moveAttempt=$false;createAttempt=$false;emptyIdentity=$null}
 $safe=[ordered]@{format='schema6-ci-module-scope-v1';phase='snapshot';body_invoked=$false;body_exit=$null;
  directory_restored=$true;machine_value_restored=$true;user_value_restored=$true;restored=$false;exit_code=1}
 $snapshot=$null
 try {
  $snapshot=& $Operations.Snapshot
  for($index=0;$index -lt 2;$index++){
   $safe.phase='registry_prepare';$state.registryAttempt[$index]=$true
   & $Operations.SetRegistry $snapshot $index
  }
  if($snapshot.directoryExisted){
   $safe.phase='directory_move';$state.moveAttempt=$true
   & $Operations.MoveDirectory $snapshot $state
   $safe.phase='directory_prepare';$state.createAttempt=$true
   & $Operations.CreateEmpty $snapshot $state
  }
  $safe.phase='verify_search_scope'
  & $Operations.Verify $snapshot $state
  $safe.phase='body';$safe.body_invoked=$true
  $safe.body_exit=[int](& $Body);$safe.exit_code=$safe.body_exit
 } catch {
  # Do not emit exception text, paths, registry contents, or callback output.
  $safe.exit_code=1
 } finally {
  if($null -ne $snapshot){
   if($state.moveAttempt -or -not $snapshot.directoryExisted){
    try{& $Operations.RestoreDirectory $snapshot $state}catch{$safe.directory_restored=$false}
   }
   for($index=0;$index -lt 2;$index++){
    if($state.registryAttempt[$index]){
     try{& $Operations.RestoreRegistry $snapshot $index}
     catch{if($index -eq 0){$safe.machine_value_restored=$false}else{$safe.user_value_restored=$false}}
    }
   }
  }
  $safe.restored=$safe.directory_restored -and $safe.machine_value_restored -and $safe.user_value_restored
  if(-not $safe.restored){$safe.exit_code=1}
 }
 return [pscustomobject]$safe
}


# Restore decisions are exercised using an in-memory directory model in tests.
function Restore-Schema6ModuleDirectoryState($Snapshot,$State,[hashtable]$Directory) {
 if((& $Directory.Identity $Snapshot.parent) -cne $Snapshot.parentIdentity){throw 'module_parent_changed'}
 $original=& $Directory.Identity $Snapshot.directory
 $saved=& $Directory.Identity $Snapshot.quarantine
 if(-not $Snapshot.directoryExisted){
  if($null -ne $original -or $null -ne $saved){throw 'module_absent_changed'}
  return
 }
 if($null -ne $saved){
  if($saved -cne $Snapshot.directoryIdentity){throw 'module_quarantine_changed'}
  if($null -ne $original){
   if($null -eq $State.emptyIdentity -or $original -cne $State.emptyIdentity -or
      -not (& $Directory.Empty $Snapshot.directory)){throw 'module_empty_changed'}
   & $Directory.DeleteEmpty $Snapshot.directory
  }
  & $Directory.Move $Snapshot.quarantine $Snapshot.directory
 }
 if((& $Directory.Identity $Snapshot.directory) -cne $Snapshot.directoryIdentity -or
    $null -ne (& $Directory.Identity $Snapshot.quarantine)){throw 'module_directory_restore_failed'}
}

function Initialize-Schema6ModuleDirectoryNative {
 if('Schema6CiModuleDirectory' -as [type]){return}
 Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class Schema6CiModuleDirectory {
 [StructLayout(LayoutKind.Sequential)] struct Info {
  public uint Attr; public System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
  public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
 }
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
 static extern SafeFileHandle CreateFileW(string p,uint a,uint s,IntPtr sa,uint c,uint f,IntPtr t);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info i);
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
 static extern uint GetFinalPathNameByHandleW(SafeFileHandle h,System.Text.StringBuilder b,uint n,uint f);
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateDirectoryW(string p,IntPtr sa);
 public static string Identity(string path) {
  string full=Path.GetFullPath(path).TrimEnd('\\');
  using(var h=CreateFileW(path,0,7,IntPtr.Zero,3,0x02200000,IntPtr.Zero)) {
   Info i;
   if(h.IsInvalid || !GetFileInformationByHandle(h,out i) || (i.Attr&0x400)!=0 || (i.Attr&0x10)==0)
    throw new IOException("module_directory_rejected");
   var b=new System.Text.StringBuilder(32768);
   uint n=GetFinalPathNameByHandleW(h,b,(uint)b.Capacity,0);
   string resolved=b.ToString();
   if(resolved.StartsWith(@"\\?\"))resolved=resolved.Substring(4);
   if(n==0 || n>=b.Capacity || !String.Equals(full,resolved.TrimEnd('\\'),StringComparison.OrdinalIgnoreCase))
    throw new IOException("module_directory_not_canonical");
   return i.Volume.ToString("X8")+":"+i.IndexHigh.ToString("X8")+":"+i.IndexLow.ToString("X8");
  }
 }
 public static void CreateExclusive(string path) {
  if(!CreateDirectoryW(path,IntPtr.Zero))throw new IOException("module_empty_create_failed");
 }
}
'@
}
function Assert-Schema6ModuleDirectory([string]$Path) {
 $item=[IO.DirectoryInfo]::new($Path)
 while($null -ne $item){[void][Schema6CiModuleDirectory]::Identity($item.FullName);$item=$item.Parent}
 return [Schema6CiModuleDirectory]::Identity($Path)
}
function Get-Schema6FreshModuleRoots {
 $info=[Diagnostics.ProcessStartInfo]::new()
 $info.FileName=Join-Path $PSHOME 'powershell.exe'
 $info.Arguments='-NoProfile -NonInteractive -Command "[Console]::Out.Write($env:PSModulePath)"'
 $info.UseShellExecute=$false;$info.CreateNoWindow=$true
 $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $info.EnvironmentVariables.Clear()
 foreach($name in @('SystemRoot','WINDIR','TEMP','TMP','COMSPEC')){
  $value=[Environment]::GetEnvironmentVariable($name)
  if($null -ne $value){$info.EnvironmentVariables[$name]=$value}
 }
 $info.EnvironmentVariables['PATHEXT']='.EXE'
 $process=[Diagnostics.Process]::new();$process.StartInfo=$info
 try{
  if(-not $process.Start()){throw 'module_roots_start_failed'}
  $output=$process.StandardOutput.ReadToEndAsync();$errors=$process.StandardError.ReadToEndAsync()
  if(-not $process.WaitForExit(15000)){
   $process.Kill();$process.WaitForExit();throw 'module_roots_timeout'
  }
  $text=$output.GetAwaiter().GetResult();$null=$errors.GetAwaiter().GetResult()
  if($process.ExitCode -ne 0 -or $text.Length -gt 16384 -or [string]::IsNullOrWhiteSpace($text)){throw 'module_roots_invalid'}
  $roots=@()
  foreach($value in $text.Split(';')){
   if([string]::IsNullOrWhiteSpace($value)){continue}
   if(-not [IO.Path]::IsPathRooted($value)){throw 'module_roots_invalid'}
   $path=[IO.Path]::GetFullPath($value).TrimEnd('\')
   # Reject aliases/reparse ancestry even when the final search root is absent.
   $item=[IO.DirectoryInfo]::new($path)
   while($null -ne $item -and -not $item.Exists){$item=$item.Parent}
   if($null -eq $item){throw 'module_roots_invalid'}
   [void](Assert-Schema6ModuleDirectory $item.FullName)
   $roots+=$path
  }
  return ,$roots
 }finally{$process.Dispose()}
}
function Assert-Schema6QuarantineOutsideRoots([string]$Quarantine,[string[]]$Roots) {
 foreach($root in $Roots){
  if($Quarantine.Equals($root,[StringComparison]::OrdinalIgnoreCase) -or
     $Quarantine.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){
   throw 'module_quarantine_in_search_root'
  }
 }
}
function Open-Schema6ModuleEnvironmentKey([int]$Index,[bool]$Writable) {
 if($Index -eq 0){return [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment',$Writable)}
 return [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment',$Writable)
}
function Read-Schema6ModuleRegistry([int]$Index) {
 $key=Open-Schema6ModuleEnvironmentKey $Index $false
 if($null -eq $key){throw 'module_environment_key_missing'}
 try{
  $exists=$key.GetValueNames() -contains 'PSModulePath'
  $kind=$null;$raw=$null
  if($exists){
   $kind=$key.GetValueKind('PSModulePath')
   $raw=$key.GetValue('PSModulePath',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
   if($kind -notin @([Microsoft.Win32.RegistryValueKind]::String,[Microsoft.Win32.RegistryValueKind]::ExpandString)){throw 'module_registry_kind_rejected'}
  }
  return @{exists=$exists;kind=$kind;raw=$raw}
 }finally{$key.Dispose()}
}
function New-Schema6NativeModuleOperations {
 Assert-Schema6ModuleScopeHost
 Initialize-Schema6ModuleDirectoryNative
 return @{
  Snapshot={
   # Both raw values/kinds/absence are captured before the first mutation.
   $registry=@((Read-Schema6ModuleRegistry 0),(Read-Schema6ModuleRegistry 1))
   $system=Join-Path $PSHOME 'Modules'
   [void](Assert-Schema6ModuleDirectory $system)
   $directory=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)) 'WindowsPowerShell\Modules'
   $parent=[IO.Path]::GetDirectoryName($directory)
   [void](Assert-Schema6ModuleDirectory $parent)
   $existed=[IO.Directory]::Exists($directory)
   if([IO.File]::Exists($directory)){throw 'module_directory_conflict'}
   $identity=$null
   if($existed){$identity=Assert-Schema6ModuleDirectory $directory}
   $roots=Get-Schema6FreshModuleRoots
   # The CI parent can still carry its original inherited search path.
   foreach($value in $env:PSModulePath.Split(';')){
    if([string]::IsNullOrWhiteSpace($value)){continue}
    if(-not [IO.Path]::IsPathRooted($value)){throw 'module_roots_invalid'}
    $candidate=[IO.Path]::GetFullPath($value).TrimEnd('\')
    $item=[IO.DirectoryInfo]::new($candidate)
    while($null -ne $item -and -not $item.Exists){$item=$item.Parent}
    if($null -eq $item){throw 'module_roots_invalid'}
    [void](Assert-Schema6ModuleDirectory $item.FullName)
    $roots+=$candidate
   }
   $quarantine=Join-Path $parent ('.schema6-ci-modules-'+[Guid]::NewGuid().ToString('N'))
   Assert-Schema6QuarantineOutsideRoots $quarantine ($roots+@($system,$directory))
   if([IO.Directory]::Exists($quarantine) -or [IO.File]::Exists($quarantine)){throw 'module_quarantine_conflict'}
   return @{registry=$registry;system=$system;directory=$directory;parent=$parent;quarantine=$quarantine;
    directoryExisted=$existed;directoryIdentity=$identity;parentIdentity=(Assert-Schema6ModuleDirectory $parent)}
  }
  SetRegistry={
   param($snapshot,$index)
   $key=Open-Schema6ModuleEnvironmentKey $index $true
   if($null -eq $key){throw 'module_environment_key_missing'}
   try{$key.SetValue('PSModulePath',$snapshot.system,[Microsoft.Win32.RegistryValueKind]::String)}finally{$key.Dispose()}
  }
  MoveDirectory={
   param($snapshot,$state)
   if((Assert-Schema6ModuleDirectory $snapshot.parent) -cne $snapshot.parentIdentity -or
      (Assert-Schema6ModuleDirectory $snapshot.directory) -cne $snapshot.directoryIdentity){throw 'module_directory_changed'}
   [IO.Directory]::Move($snapshot.directory,$snapshot.quarantine)
  }
  CreateEmpty={
   param($snapshot,$state)
   if((Assert-Schema6ModuleDirectory $snapshot.parent) -cne $snapshot.parentIdentity){throw 'module_parent_changed'}
   [Schema6CiModuleDirectory]::CreateExclusive($snapshot.directory)
   $state.emptyIdentity=Assert-Schema6ModuleDirectory $snapshot.directory
  }
  Verify={
   param($snapshot,$state)
   $roots=Get-Schema6FreshModuleRoots
   Assert-Schema6QuarantineOutsideRoots $snapshot.quarantine $roots
   if($roots.Count -eq 0 -or $snapshot.system -notin $roots){throw 'module_scope_roots_rejected'}
   foreach($root in $roots){if($root -ine $snapshot.system -and $root -ine $snapshot.directory){throw 'module_scope_roots_rejected'}}
   if($snapshot.directoryExisted){
    if((Assert-Schema6ModuleDirectory $snapshot.directory) -cne $state.emptyIdentity -or
       [IO.Directory]::GetFileSystemEntries($snapshot.directory).Length -ne 0){throw 'module_empty_changed'}
   }elseif([IO.Directory]::Exists($snapshot.directory) -or [IO.File]::Exists($snapshot.directory)){throw 'module_absent_changed'}
  }
  RestoreDirectory={
   param($snapshot,$state)
   Restore-Schema6ModuleDirectoryState $snapshot $state @{
    Identity={
     param($path)
     if([IO.Directory]::Exists($path)){return Assert-Schema6ModuleDirectory $path}
     if([IO.File]::Exists($path)){throw 'module_directory_conflict'}
     return $null
    }
    Empty={param($path) return [IO.Directory]::GetFileSystemEntries($path).Length -eq 0}
    DeleteEmpty={
     param($path)
     # Recheck immediately before a nonrecursive delete; never delete module content.
     if((Assert-Schema6ModuleDirectory $path) -cne $state.emptyIdentity){throw 'module_empty_changed'}
     [IO.Directory]::Delete($path,$false)
    }
    Move={param($from,$to) [IO.Directory]::Move($from,$to)}
   }
  }
  RestoreRegistry={
   param($snapshot,$index)
   $original=$snapshot.registry[$index]
   $key=Open-Schema6ModuleEnvironmentKey $index $true
   if($null -eq $key){throw 'module_environment_key_missing'}
   try{
    if($original.exists){$key.SetValue('PSModulePath',$original.raw,$original.kind)}
    else{$key.DeleteValue('PSModulePath',$false)}
   }finally{$key.Dispose()}
   $actual=Read-Schema6ModuleRegistry $index
   if($actual.exists -ne $original.exists -or $actual.kind -ne $original.kind -or $actual.raw -cne $original.raw){throw 'module_registry_restore_failed'}
  }
 }
}
function Invoke-Schema6HostedModuleScope([scriptblock]$Body) {
 Assert-Schema6ModuleScopeHost
 try{
  $operations=New-Schema6NativeModuleOperations
  $result=Invoke-Schema6ModuleScopeState $operations $Body
 }catch{
  $result=[pscustomobject]@{format='schema6-ci-module-scope-v1';phase='adapter_prepare';exit_code=1}
 }
 $json=$result|ConvertTo-Json -Compress
 [Console]::Out.WriteLine($json)
 try{
  [IO.File]::WriteAllText((Join-Path (Get-Location) 'build/ci/schema6-module-scope.json'),$json,[Text.UTF8Encoding]::new($false))
 }catch{return 1}
 return [int]$result.exit_code
}
