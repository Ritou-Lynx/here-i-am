#requires -Version 5.1
# Import-safe definitions. No deployed paths or default actions. Owner/DACL only; Group/SACL are not restored.
function Initialize-CutoverAclNative {
 if (!("CutoverAclNative" -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class CutoverAclNative {
 [StructLayout(LayoutKind.Sequential)] struct Info {
  public uint attributes,createdLow,createdHigh,accessLow,accessHigh,writeLow,writeHigh,volume,sizeHigh,sizeLow,links,indexHigh,indexLow;
 }
 [StructLayout(LayoutKind.Sequential)] struct Luid {public uint low;public int high;}
 [StructLayout(LayoutKind.Sequential)] struct TokenPrivileges {public uint count;public Luid luid;public uint attributes;}
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFile(string p,uint access,uint share,IntPtr sa,uint disposition,uint flags,IntPtr template);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info i);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(SafeFileHandle h,StringBuilder b,uint n,uint f);
 [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool CloseHandle(IntPtr h);
 [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool LookupPrivilegeValue(string system,string name,out Luid luid);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool AdjustTokenPrivileges(IntPtr token,bool disable,ref TokenPrivileges state,uint length,out TokenPrivileges previous,out uint returned);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(string s,uint revision,out IntPtr sd,out uint size);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetSecurityDescriptorOwner(IntPtr sd,out IntPtr owner,out bool defaulted);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetSecurityDescriptorDacl(IntPtr sd,out bool present,out IntPtr dacl,out bool defaulted);
 [DllImport("advapi32.dll")] static extern uint SetSecurityInfo(SafeFileHandle h,int kind,uint flags,IntPtr owner,IntPtr group,IntPtr dacl,IntPtr sacl);
 public static SafeFileHandle Open(string p,bool write) {
  // Deny rename/delete while reviewing and applying; never request file data access.
  var h=CreateFile(p,write?0x000E0000u:0x00020000u,3,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
  if(h.IsInvalid)throw new Win32Exception(Marshal.GetLastWin32Error());
  try {Info i;if(!GetFileInformationByHandle(h,out i))throw new Win32Exception(Marshal.GetLastWin32Error());
   if((i.attributes&0x400)!=0 || ((i.attributes&0x10)==0 && i.links!=1))throw new InvalidOperationException("linked_target_rejected");
   return h;
  }catch{h.Dispose();throw;}
 }
 // Source ancestors need LIST_DIRECTORY: metadata-only handles do not enforce
 // delete sharing. ACL targets retain the original READ_CONTROL-only Open.
 public static SafeFileHandle OpenSourceDirectory(string p) {
  var h=CreateFile(p,0x00020081u,3,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
  if(h.IsInvalid)throw new Win32Exception(Marshal.GetLastWin32Error());
  try{IdentityAt(h,p,true);return h;}catch{h.Dispose();throw;}
 }
 public static string Identity(SafeFileHandle h) {
  Info i;if(!GetFileInformationByHandle(h,out i))throw new Win32Exception(Marshal.GetLastWin32Error());
  if((i.attributes&0x400)!=0 || ((i.attributes&0x10)==0 && i.links!=1))throw new InvalidOperationException("linked_target_rejected");
  return i.volume+":"+i.indexHigh+":"+i.indexLow+":"+i.sizeHigh+":"+i.sizeLow+":"+i.writeHigh+":"+i.writeLow;
 }
 public static string IdentityAt(SafeFileHandle h,string path,bool directory) {
  Info i;var b=new StringBuilder(32768);uint n=GetFinalPathNameByHandle(h,b,32768,0);
  if(!GetFileInformationByHandle(h,out i)||n==0||n>=32768)throw new Win32Exception(Marshal.GetLastWin32Error());
  if(((i.attributes&0x10)!=0)!=directory||!b.ToString().Equals("\\\\?\\"+path,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("source_path_identity_rejected");
  return Identity(h);
 }
 public static void SetOwnerDacl(SafeFileHandle h,string sddl,bool protect) {
  IntPtr sd=IntPtr.Zero,own,acl;uint size;bool present,def;
  if(!ConvertStringSecurityDescriptorToSecurityDescriptor(sddl,1,out sd,out size))throw new Win32Exception(Marshal.GetLastWin32Error());
  try {
   if(!GetSecurityDescriptorOwner(sd,out own,out def)||own==IntPtr.Zero||
      !GetSecurityDescriptorDacl(sd,out present,out acl,out def)||!present||acl==IntPtr.Zero)throw new InvalidOperationException("owner_dacl_required");
   uint flags=0x00000001u|0x00000004u|(protect?0x80000000u:0x20000000u);
   uint rc=SetSecurityInfo(h,1,flags,own,IntPtr.Zero,acl,IntPtr.Zero);
   if(rc!=0)throw new Win32Exception((int)rc);
  }finally{LocalFree(sd);}
 }
 public sealed class Privilege : IDisposable {
  IntPtr token;TokenPrivileges old;bool changed;
  public Privilege() {
   if(!OpenProcessToken(GetCurrentProcess(),0x28,out token))throw new Win32Exception(Marshal.GetLastWin32Error());
   try {Luid luid;if(!LookupPrivilegeValue(null,"SeRestorePrivilege",out luid))throw new Win32Exception(Marshal.GetLastWin32Error());
    var next=new TokenPrivileges{count=1,luid=luid,attributes=2};uint n;
    bool ok=AdjustTokenPrivileges(token,false,ref next,(uint)Marshal.SizeOf(typeof(TokenPrivileges)),out old,out n);
    int code=Marshal.GetLastWin32Error();if(!ok||code!=0)throw new Win32Exception(code);changed=true;
   }catch{CloseHandle(token);token=IntPtr.Zero;throw;}
  }
  public void Dispose(){if(token!=IntPtr.Zero){try{if(changed){TokenPrivileges unused;uint n;
    bool ok=AdjustTokenPrivileges(token,false,ref old,(uint)Marshal.SizeOf(typeof(TokenPrivileges)),out unused,out n);
    int code=Marshal.GetLastWin32Error();if(!ok||code!=0)throw new Win32Exception(code);
   }}finally{CloseHandle(token);token=IntPtr.Zero;}}}
 }
}
'@
 }
}

function Test-InScope([string]$p) {
 foreach($r in $roots){if($p.Equals($r,[StringComparison]::OrdinalIgnoreCase)-or $p.StartsWith($r+'\',[StringComparison]::OrdinalIgnoreCase)){return $true}}
 return $false
}
function Assert-Plain([string]$p) {
 if($p -notmatch '^[A-Za-z]:\\' -or $p.Substring(2).Contains(':') -or [IO.Path]::GetFullPath($p) -cne $p){throw 'canonical_path_required'}
 for($q=$p;$q;$q=[IO.Path]::GetDirectoryName($q)){
  $item=Get-Item -LiteralPath $q -Force
  if(($item.Attributes-band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'reparse_path_rejected'}
 }
}
function Hold-Path([string]$p,[bool]$write) {
 Assert-Plain $p
 # Pin ancestors too so a path cannot be redirected by an ancestor rename.
 $chain=@();for($q=[IO.Path]::GetDirectoryName($p);$q;$q=[IO.Path]::GetDirectoryName($q)){$chain=@($q)+$chain}
 foreach($q in $chain){if(!$held.ContainsKey($q)){$held[$q]=[CutoverAclNative]::Open($q,$false)}}
 if(!$targetHandles.ContainsKey($p)){$targetHandles[$p]=[CutoverAclNative]::Open($p,$write)}
}
function Owner-Dacl([string]$s) {
 $sd=New-Object Security.AccessControl.RawSecurityDescriptor($s)
 if(!$sd.Owner -or !$sd.DiscretionaryAcl){throw 'snapshot_owner_dacl_required'}
 $protected=($sd.ControlFlags-band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected)-ne 0
 $aces=@(foreach($ace in $sd.DiscretionaryAcl){$bytes=New-Object byte[] $ace.BinaryLength;$ace.GetBinaryForm($bytes,0);[Convert]::ToBase64String($bytes)})
 return ($sd.Owner.Value+'|'+$protected+'|'+($aces-join ';'))
}
function Read-OwnerDacl([string]$p) {
 return (Get-Acl -LiteralPath $p).GetSecurityDescriptorSddlForm($sections)
}
function Assert-PrivateDirectory([string]$p) {
 Assert-Plain $p
 $a=Get-Acl -LiteralPath $p
 if(!$a.AreAccessRulesProtected -or $a.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $owner){throw 'private_directory_required'}
 foreach($r in $a.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
  if($r.AccessControlType -eq 'Allow' -and $r.IdentityReference.Value -notin @($owner,'S-1-5-18','S-1-5-32-544')){throw 'private_directory_required'}
 }
}
function New-PrivateSddl([bool]$directory) {
 if($directory){$a=New-Object Security.AccessControl.DirectorySecurity}else{$a=New-Object Security.AccessControl.FileSecurity}
 $a.SetOwner([Security.Principal.SecurityIdentifier]$owner);$a.SetAccessRuleProtection($true,$false)
 foreach($id in @($owner,'S-1-5-18','S-1-5-32-544')){
  if($directory){$r=New-Object Security.AccessControl.FileSystemAccessRule(([Security.Principal.SecurityIdentifier]$id),'FullControl','ContainerInherit,ObjectInherit','None','Allow')}
  else{$r=New-Object Security.AccessControl.FileSystemAccessRule(([Security.Principal.SecurityIdentifier]$id),'FullControl','Allow')}
  $a.AddAccessRule($r)
 }
 return $a.GetSecurityDescriptorSddlForm($sections)
}
function Inventory {
 $found=@{};$stack=New-Object Collections.Generic.Stack[string]
 foreach($r in $roots){$stack.Push($r)}
 while($stack.Count -gt 0){
  $p=$stack.Pop();Assert-Plain $p;$item=Get-Item -LiteralPath $p -Force
  if(!(Test-InScope $item.FullName)){throw 'inventory_scope_violation'}
  if($found.ContainsKey($item.FullName)){throw 'inventory_duplicate'}
  $found[$item.FullName]=[bool]$item.PSIsContainer
  if($item.PSIsContainer){foreach($child in Get-ChildItem -LiteralPath $p -Force){$stack.Push($child.FullName)}}
 }
 return $found
}
function Assert-Inventory {
 $actual=Inventory
 if($actual.Count -ne $rows.Count){throw 'inventory_drift'}
 foreach($r in $rows){if(!$actual.ContainsKey($r.path)-or $actual[$r.path] -ne $r.directory){throw 'inventory_drift'}}
}
function Assert-Frozen {
 if(!$ConfirmFrozen){throw 'explicit_frozen_confirmation_required'}
 Assert-FreezeReceipt $config
 $frozen=Read-AclAnchoredJson $config.frozenReceiptPath $config.frozenReceiptSha256
 foreach($task in $frozen.tasks){Assert-AclFrozenTaskState $task (Read-AclFrozenTaskState $task)}
 $listeners=@(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object{$_.LocalPort -in $ports})
 if($listeners.Count -ne 0){throw 'runtime_listener_present'}
}
function Read-AclFrozenTaskState($Expected) {
 $service=New-Object -ComObject Schedule.Service;$service.Connect()
 $task=$service.GetFolder([string]$Expected.taskPath).GetTask([string]$Expected.name)
 $definition=$task.Definition
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$xmlHash=([BitConverter]::ToString($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes([string]$task.Xml)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
 return [pscustomobject]@{name=[string]$Expected.name;taskPath=[string]$Expected.taskPath;disabled=($task.Enabled -eq $false);triggers=[int]$definition.Triggers.Count;retries=[int]$definition.Settings.RestartCount;instances=[int]$task.GetInstances(0).Count;frozenXmlSha256=$xmlHash;originalSddl=[string]$task.GetSecurityDescriptor(7)}
}
function Assert-AclFrozenTaskState($Expected,$Actual) {
 foreach($field in @('name','taskPath','frozenXmlSha256','originalSddl')){if($Actual.$field -cne $Expected.$field){throw 'frozen_task_definition_drift'}}
 if($Actual.disabled -isnot [bool] -or !$Actual.disabled -or $Actual.triggers -ne 0 -or $Actual.retries -ne 0 -or $Actual.instances -ne 0){throw 'frozen_task_state_drift'}
}
function Assert-Metadata {
 foreach($r in $rows){if([CutoverAclNative]::Identity($targetHandles[$r.path]) -cne $before[$r.path].identity){throw 'target_metadata_changed'}}
}
function Add-Receipt([string]$p,[string]$action,[bool]$ok,[string]$code='') {
 $receipt.items+=@([ordered]@{path=$p;action=$action;verified=$ok;code=$code;at_utc=[DateTime]::UtcNow.ToString('o')})
}
function Restore-Snapshot {
 $all=$true
 # Restoring a parent's DACL may propagate. Always process and verify EVERY member.
 foreach($r in $rows){
  try{
   $sd=New-Object Security.AccessControl.RawSecurityDescriptor([string]$r.sddl)
   $protected=($sd.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected)-ne 0
   [CutoverAclNative]::SetOwnerDacl($targetHandles[$r.path],[string]$r.sddl,$protected)
   Add-Receipt $r.path 'restore_owner_dacl' $true
  }catch{$all=$false;Add-Receipt $r.path 'restore_owner_dacl' $false 'restore_failed'}
 }
 foreach($r in $rows){
  try{if((Owner-Dacl (Read-OwnerDacl $r.path)) -cne (Owner-Dacl $r.sddl)){throw 'restore_readback_mismatch'};Add-Receipt $r.path 'restore_readback' $true}
  catch{$all=$false;Add-Receipt $r.path 'restore_readback' $false 'restore_readback_mismatch'}
 }
 return $all
}
function Invoke-AclFailureRecovery {
 # Never delete new pending files or widen the approved inventory to enable restore.
 try{
  Assert-Frozen;Assert-Inventory;Assert-Metadata
  $receipt.rollback_attempted=$true;$receipt.rollback_verified=Restore-Snapshot
  if(!$receipt.rollback_verified){throw 'rollback_incomplete'}
  Assert-Inventory;Assert-Metadata;Assert-Frozen
  $receipt.metadata_unchanged_after_rollback=$true
 }catch{
  $receipt.rollback_deferred=$true;$receipt.requires_reviewed_recovery=$true
  $receipt.metadata_unchanged_after_rollback=$false
 }
}
function Read-AclAnchoredJson([string]$Path,[string]$ExpectedHash) {
 if($ExpectedHash -cnotmatch '^[a-f0-9]{64}$'){throw 'sha256_anchor_required'}
 Assert-Plain $Path
 # One open, deny write/delete, hash and parse the SAME bytes.
 $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{
  $memory=[IO.MemoryStream]::new();$stream.CopyTo($memory);$bytes=$memory.ToArray();$memory.Dispose()
  $sha=[Security.Cryptography.SHA256]::Create()
  try{$actual=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
  if($actual -cne $ExpectedHash){throw 'anchored_json_hash_mismatch'}
  return ([Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json)
 }finally{$stream.Dispose()}
}
function Read-AclConfiguration([string]$Path,[string]$ExpectedHash) {
 $c=Read-AclAnchoredJson $Path $ExpectedHash
 $required=@('format','windowId','candidateSourceCommit','candidateManifestSha256','maintenanceRoot','baseDirectory','snapshotPath','snapshotSha256','ownerSid','roots','expectedCount','expectedForeignOwnerCount','taskNames','ports','frozenReceiptPath','frozenReceiptSha256','receiptPath')
 if(@(Compare-Object ($required|Sort-Object) @($c.PSObject.Properties.Name|Sort-Object)).Count){throw 'acl_config_fields_invalid'}
 if($c.format -cne 'schema6-acl-config-v1' -or $c.windowId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]{7,79}$'){throw 'acl_config_invalid'}
 foreach($name in @('candidateManifestSha256','snapshotSha256','frozenReceiptSha256')){if($c.$name -isnot [string] -or $c.$name -cnotmatch '^[a-f0-9]{64}$'){throw 'sha256_anchor_required'}}
 if($c.candidateSourceCommit -isnot [string] -or $c.candidateSourceCommit -cnotmatch '^[a-f0-9]{40}$'){throw 'candidate_commit_required'}
 if($c.expectedCount -isnot [int] -or $c.expectedCount -lt 1 -or $c.expectedForeignOwnerCount -isnot [int] -or $c.expectedForeignOwnerCount -lt 0 -or $c.expectedForeignOwnerCount -gt $c.expectedCount){throw 'acl_expected_count_invalid'}
 $null=[Security.Principal.SecurityIdentifier]::new([string]$c.ownerSid)
 if($c.roots -isnot [array] -or $c.roots.Count -lt 1 -or $c.taskNames -isnot [array] -or $c.taskNames.Count -lt 1 -or $c.ports -isnot [array] -or $c.ports.Count -lt 1){throw 'acl_scope_required'}
 foreach($r in $c.roots){
  Assert-Plain $r
  if(!(Get-Item -LiteralPath $r -Force).PSIsContainer -or $r.TrimEnd('\') -eq [IO.Path]::GetPathRoot($r).TrimEnd('\')){throw 'acl_root_invalid'}
  foreach($other in $c.roots){if($r -cne $other -and ($r.Equals($other,[StringComparison]::OrdinalIgnoreCase) -or $r.StartsWith($other+'\',[StringComparison]::OrdinalIgnoreCase))){throw 'acl_roots_overlap'}}
 }
 if(@($c.roots|Select-Object -Unique).Count -ne $c.roots.Count){throw 'acl_roots_overlap'}
 foreach($name in $c.taskNames){if($name -isnot [string] -or $name -notmatch '^\\[^\r\n]+$' -or $name.EndsWith('\')){throw 'acl_task_invalid'}}
 foreach($port in $c.ports){if($port -isnot [int] -or $port -lt 1 -or $port -gt 65535){throw 'acl_port_invalid'}}
 Assert-Plain $c.baseDirectory
 Assert-Plain $c.maintenanceRoot
 if($c.baseDirectory -cne (Join-Path (Join-Path $c.maintenanceRoot 'windows') $c.windowId)){throw 'acl_window_directory_mismatch'}
 foreach($p in @($Path,$c.maintenanceRoot,$c.baseDirectory,$c.snapshotPath,$c.frozenReceiptPath,$c.receiptPath)){
  foreach($r in $c.roots){if($p.Equals($r,[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($r+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'maintenance_artifact_inside_target'}}
 }
 if([IO.Path]::GetDirectoryName($c.receiptPath) -cne $c.baseDirectory){throw 'receipt_directory_mismatch'}
 return $c
}
function Assert-ReceiptDestination([string]$Path) {
 if([IO.Path]::GetFullPath($Path) -cne $Path -or $Path.Substring(2).Contains(':') -or [IO.Path]::GetDirectoryName($Path) -cne $base){throw 'receipt_destination_invalid'}
 if(Test-Path -LiteralPath $Path){throw 'fresh_receipt_required'}
}
function Assert-FreezeReceipt($Config) {
 $f=Read-AclAnchoredJson $Config.frozenReceiptPath $Config.frozenReceiptSha256
 if($f.format -cne 'schema6-frozen-legacy-runtime-ready-v2' -or $f.passed -isnot [bool] -or !$f.passed -or $f.databaseReplaced -isnot [bool] -or $f.databaseReplaced){throw 'frozen_ready_required'}
 foreach($key in @('windowId','candidateSourceCommit','candidateManifestSha256')){if($f.$key -cne $Config.$key){throw 'freeze_binding_mismatch'}}
 if($f.windowDirectory -cne $Config.baseDirectory){throw 'freeze_window_directory_mismatch'}
 $now=[DateTimeOffset]::UtcNow;$created=[DateTimeOffset]::Parse($f.createdUtc);$expires=[DateTimeOffset]::Parse($f.expiresUtc)
 if($created -gt $now -or $expires -le $now -or $expires -le $created -or ($expires-$created).TotalMinutes -gt 60){throw 'freeze_receipt_expired'}
 if($f.aclApplied -isnot [bool] -or $f.aclApplied -ne $false -or $f.observationMs -lt 65000){throw 'freeze_observation_required'}
 $seen=@{}
 $names=@(foreach($task in $f.tasks){
  if($task.disabled -isnot [bool] -or !$task.disabled -or $task.instances -ne 0 -or $task.triggers -ne 0 -or $task.retries -ne 0){throw 'freeze_task_not_disabled'}
  if($task.frozenXmlSha256 -cnotmatch '^[a-f0-9]{64}$' -or $task.originalSddl -isnot [string] -or !$task.originalSddl){throw 'freeze_task_anchor_required'}
  $name=[string]$task.taskPath+[string]$task.name
  if($seen.ContainsKey($name)){throw 'freeze_task_duplicate'};$seen[$name]=$true;$name
 })
 if(@($f.portsFree|Select-Object -Unique).Count -ne @($f.portsFree).Count){throw 'freeze_ports_duplicate'}
 if(@(Compare-Object @($Config.taskNames|Sort-Object) @($names|Sort-Object)).Count -or @(Compare-Object @($Config.ports|Sort-Object) @($f.portsFree|Sort-Object)).Count){throw 'freeze_scope_mismatch'}
}
function Acquire-AclMaintenanceGuard([string]$Path) {
 # Same byte-preserving lock protocol as maintenance_window.ps1. No second entry.lock.
 Assert-PrivateDirectory $Path
 Hold-Path $Path $false
 $guardPath=Join-Path $Path 'active-window.guard'
 if(Test-Path -LiteralPath $guardPath){Assert-Plain $guardPath}
 $guard=if(Test-Path -LiteralPath $guardPath){[IO.File]::Open($guardPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}else{New-OwnedArtifactFile $guardPath $owner}
 try{$null=[CutoverAclNative]::Identity($guard.SafeFileHandle);$null=[OwnedArtifactNative]::Check($guard.SafeFileHandle,$guardPath,$false);[OwnedArtifactNative]::Private($guard.SafeFileHandle,$owner,$false);return $guard}catch{$guard.Dispose();throw}
}
function Invoke-AclMaintenance {
 [CmdletBinding()]
 param([Parameter(Mandatory=$true)][string]$ConfigPath,[Parameter(Mandatory=$true)][string]$ExpectedConfigSha256,[Parameter(Mandatory=$true)][ValidatePattern("^[a-f0-9]{64}$")][string]$ExpectedOwnedArtifactsSha256,[Parameter(Mandatory=$true)][ValidateSet("Audit","Apply","Rollback")][string]$Mode,[switch]$ConfirmFrozen)
 Set-StrictMode -Version 2
 $ErrorActionPreference="Stop"
 $artifactHelper=Join-Path $PSScriptRoot 'owned_artifacts.ps1'
 Initialize-CutoverAclNative
 $artifactLease=$null;$artifactIdentity=$null;$artifactParents=[Collections.Generic.List[IDisposable]]::new()
 try {
  Assert-Plain $artifactHelper
  $chain=@();for($q=[IO.Path]::GetDirectoryName($artifactHelper);$q;$q=[IO.Path]::GetDirectoryName($q)){$chain=@($q)+$chain}
  foreach($q in $chain){$h=[CutoverAclNative]::OpenSourceDirectory($q);$artifactParents.Add($h);$null=[CutoverAclNative]::IdentityAt($h,$q,$true)}
  $artifactIdentity=[CutoverAclNative]::Open($artifactHelper,$false)
  $artifactLease=[IO.File]::Open($artifactHelper,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  $sourceIdentity=[CutoverAclNative]::IdentityAt($artifactIdentity,$artifactHelper,$false)
  if([CutoverAclNative]::IdentityAt($artifactLease.SafeFileHandle,$artifactHelper,$false)-cne $sourceIdentity){throw 'owned_artifact_source_identity_rejected'}
  $memory=[IO.MemoryStream]::new();try{$artifactLease.CopyTo($memory);$artifactBytes=$memory.ToArray()}finally{$memory.Dispose()}
  $artifactSha=[Security.Cryptography.SHA256]::Create()
  try{$actual=([BitConverter]::ToString($artifactSha.ComputeHash($artifactBytes))).Replace('-','').ToLowerInvariant()}finally{$artifactSha.Dispose()}
  if($actual-cne $ExpectedOwnedArtifactsSha256){throw 'owned_artifact_source_hash_rejected'}
  if([CutoverAclNative]::IdentityAt($artifactLease.SafeFileHandle,$artifactHelper,$false)-cne $sourceIdentity){throw 'owned_artifact_source_identity_rejected'}
  # Execute only the exact bytes hashed above; retain source and ancestor leases.
  . ([scriptblock]::Create([Text.UTF8Encoding]::new($false,$true).GetString($artifactBytes).TrimStart([char]0xfeff)))
  Initialize-OwnedArtifactNative
 $config=Read-AclConfiguration $ConfigPath $ExpectedConfigSha256
 $base=[string]$config.baseDirectory;$snapshot=[string]$config.snapshotPath;$snapshotHash=[string]$config.snapshotSha256;$owner=[string]$config.ownerSid;$roots=@($config.roots);$ports=@($config.ports)
 Initialize-CutoverAclNative
$sections=[Security.AccessControl.AccessControlSections]::Owner -bor [Security.AccessControl.AccessControlSections]::Access
$held=@{};$targetHandles=@{};$before=@{};$rows=@();$privilege=$null;$mutationStarted=$false;$maintenanceGuard=$null
$receipt=[ordered]@{format='schema6-acl-maintenance-v2';mode=$Mode;started_utc=[DateTime]::UtcNow.ToString('o');snapshot_sha256=$snapshotHash;owner=$owner;scope='owner_and_dacl_only';sacl_restored=$false;target_contents_read=$false;raw_external_verified=$false;services_changed=$false;tasks_changed=$false;items=@();passed=$false;rollback_attempted=$false}
$receiptPath=$null;$exitCode=2

$receipt.windowId=$config.windowId;$receipt.candidateSourceCommit=$config.candidateSourceCommit;$receipt.candidateManifestSha256=$config.candidateManifestSha256;$receipt.configSha256=$ExpectedConfigSha256;$receipt.freezeSha256=$config.frozenReceiptSha256;$receipt.expected_count=$config.expectedCount;$receipt.expected_foreign_owner_count=$config.expectedForeignOwnerCount

try {
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $owner){throw 'owner_identity_mismatch'}
 $maintenanceGuard=Acquire-AclMaintenanceGuard $config.maintenanceRoot
 Assert-PrivateDirectory $base
 Hold-Path $base $false
 $receiptPath=[string]$config.receiptPath
 Assert-ReceiptDestination $receiptPath
 Assert-Plain $snapshot
 Hold-Path $snapshot $false
 $rows=@(Read-AclAnchoredJson $snapshot $snapshotHash)
 if($rows.Count -ne $config.expectedCount){throw 'snapshot_count_mismatch'}
 $seen=@{}
 foreach($r in $rows){
  if(@(Compare-Object @('directory','owner','path','sddl') @($r.PSObject.Properties.Name|Sort-Object)).Count){throw 'snapshot_fields_invalid'}
  if($r.path -isnot [string] -or $r.directory -isnot [bool] -or !(Test-InScope $r.path) -or $seen.ContainsKey($r.path)){throw 'snapshot_scope_invalid'}
  Assert-Plain $r.path
  $sd=New-Object Security.AccessControl.RawSecurityDescriptor([string]$r.sddl)
  if($sd.Owner.Value -cne $r.owner){throw 'snapshot_owner_mismatch'};$null=Owner-Dacl $r.sddl
  $seen[$r.path]=$true
 }
 if(@($rows | Where-Object { $_.owner -cne $owner }).Count -ne $config.expectedForeignOwnerCount){throw 'snapshot_foreign_owner_count_mismatch'}
 foreach($r in $roots){if(!$seen.ContainsKey($r)){throw 'snapshot_root_missing'}}
 $rows=@($rows|Sort-Object @{Expression={$_.path.Split('\').Count}},@{Expression={$_.path}})
 Assert-Inventory
 if($Mode -ne 'Audit'){
  if(!(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'elevated_same_user_required'}
  Assert-Frozen
  $privilege=New-Object CutoverAclNative+Privilege
 }
 foreach($r in $rows){
  Hold-Path $r.path ($Mode -ne 'Audit')
  $s=Read-OwnerDacl $r.path
  $before[$r.path]=@{identity=[CutoverAclNative]::Identity($targetHandles[$r.path]);owner_dacl=(Owner-Dacl $s)}
  $match=(Owner-Dacl $s) -ceq (Owner-Dacl $r.sddl)
  Add-Receipt $r.path 'baseline_comparison' $match $(if($match){''}else{'baseline_acl_drift'})
  if($Mode -eq 'Apply' -and !$match){throw 'baseline_acl_drift'}
 }
 Assert-Inventory;Assert-Metadata
 if($Mode -eq 'Audit'){
  $receipt.audit_baseline_matches=@($receipt.items|Where-Object{!$_.verified}).Count -eq 0
  $receipt.passed=$receipt.audit_baseline_matches
  $exitCode=if($receipt.passed){0}else{2}
 } elseif($Mode -eq 'Apply'){
  Assert-Frozen
  # SetSecurityInfo on a parent can affect all unprotected descendants. Rollback covers all rows.
  $mutationStarted=$true
  foreach($r in $rows){
   [CutoverAclNative]::SetOwnerDacl($targetHandles[$r.path],(New-PrivateSddl $r.directory),$true)
   if((Owner-Dacl (Read-OwnerDacl $r.path)) -cne (Owner-Dacl (New-PrivateSddl $r.directory))){throw 'apply_readback_mismatch'}
   Add-Receipt $r.path 'apply_owner_dacl' $true
  }
  Assert-Inventory;Assert-Metadata;Assert-Frozen
  foreach($r in $rows){
   if((Owner-Dacl (Read-OwnerDacl $r.path)) -cne (Owner-Dacl (New-PrivateSddl $r.directory))){throw 'apply_final_readback_mismatch'}
   Add-Receipt $r.path 'apply_readback' $true
  }
  $receipt.inventory_verified=$true;$receipt.metadata_unchanged=$true;$receipt.freeze_verified=$true
  $receipt.verified_count=$rows.Count;$receipt.passed=$true;$exitCode=0
 } else {
  Assert-Frozen;$mutationStarted=$true;$receipt.rollback_attempted=$true
  $receipt.rollback_verified=Restore-Snapshot
  Assert-Inventory;Assert-Metadata;Assert-Frozen
  if(!$receipt.rollback_verified){throw 'rollback_incomplete'}
  $receipt.verified_count=$rows.Count;$receipt.passed=$true;$exitCode=0
 }
}catch{
 $receipt.error_code=if($_.Exception.Message -match '^[a-z][a-z0-9_]+$'){$_.Exception.Message}else{'acl_maintenance_rejected'}
 if($Mode -eq 'Apply' -and $mutationStarted){
  # Inventory drift (including a newly created pending marker) forbids blind rollback.
  Invoke-AclFailureRecovery
 }
 $receipt.passed=$false;$exitCode=2
}finally{
 foreach($h in $targetHandles.Values){$h.Dispose()}
 foreach($h in $held.Values){$h.Dispose()}
 if($privilege){try{$privilege.Dispose()}catch{$receipt.privilege_restore_failed=$true;$receipt.passed=$false;$exitCode=2}}
 $receipt.completed_utc=[DateTime]::UtcNow.ToString('o')
 if($receiptPath){
  try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($receipt|ConvertTo-Json -Depth 10));Write-OwnedArtifactBytes $receiptPath $bytes $owner}
  catch{[Console]::Error.WriteLine('private_receipt_write_failed');$receipt.passed=$false;$exitCode=2}
 }
 if($maintenanceGuard){$maintenanceGuard.Dispose()}
}
return [pscustomobject]@{passed=$receipt.passed;exitCode=$exitCode;receipt=$receiptPath;result=[pscustomobject]$receipt}
 }finally{if($artifactLease){$artifactLease.Dispose()};if($artifactIdentity){$artifactIdentity.Dispose()};foreach($h in $artifactParents){$h.Dispose()}}
}
