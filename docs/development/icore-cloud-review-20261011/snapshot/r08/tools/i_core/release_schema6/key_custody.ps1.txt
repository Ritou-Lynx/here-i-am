[CmdletBinding()]
param(
 [ValidateSet('Library','Create','Read')][string]$Action='Library',
 [string]$KeyDirectory,
 [ValidateSet('backup','recovery')][string]$Purpose='backup'
)
$ErrorActionPreference='Stop'
$env:PSModulePath=Join-Path $PSHOME 'Modules'
# Dot-source only after the enclosing release inventory has been independently verified.
Add-Type -AssemblyName System.Security
function Assert-BackupPlainPath([string]$Path,[switch]$Missing) {
 if(![IO.Path]::IsPathRooted($Path) -or [IO.Path]::GetFullPath($Path) -cne $Path -or $Path.Substring(2).Contains(':')) { throw 'custody_path_invalid' }
 $current=$Path
 while($current) {
  if(Test-Path -LiteralPath $current) { $item=Get-Item -LiteralPath $current -Force; if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'custody_link_rejected'} }
  elseif(!$Missing -or $current -ne $Path) {throw 'custody_path_missing'}
  $parent=[IO.Path]::GetDirectoryName($current);if(!$parent -or $parent -eq $current){break};$current=$parent
 }
}
function Set-BackupPrivateAcl([string]$Path,[bool]$Directory) {
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
 if($Directory){$acl=New-Object Security.AccessControl.DirectorySecurity}else{$acl=New-Object Security.AccessControl.FileSecurity}
 $acl.SetOwner($sid);$acl.SetAccessRuleProtection($true,$false)
 foreach($id in @($sid.Value,'S-1-5-18')) {
  if($Directory){$rule=New-Object Security.AccessControl.FileSystemAccessRule(([Security.Principal.SecurityIdentifier]$id),'FullControl','ContainerInherit,ObjectInherit','None','Allow')}
  else{$rule=New-Object Security.AccessControl.FileSystemAccessRule(([Security.Principal.SecurityIdentifier]$id),'FullControl','Allow')}
  $acl.AddAccessRule($rule)
 }
 Set-Acl -LiteralPath $Path -AclObject $acl
 Assert-BackupPrivateAcl $Path
}
function Assert-BackupPrivateAcl([string]$Path) {
 Assert-BackupPlainPath $Path
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$acl=Get-Acl -LiteralPath $Path
 if(!$acl.AreAccessRulesProtected -or $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $sid){throw 'custody_acl_invalid'}
 $rules=$acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]);$seen=@{}
 foreach($rule in $rules){$id=$rule.IdentityReference.Value;if($id -notin @($sid,'S-1-5-18') -or $rule.AccessControlType -ne 'Allow' -or $rule.FileSystemRights -ne [Security.AccessControl.FileSystemRights]::FullControl){throw 'custody_acl_invalid'};$seen[$id]=$true}
 if(!$seen.ContainsKey($sid) -or !$seen.ContainsKey('S-1-5-18')){throw 'custody_acl_invalid'}
}
# Win32 file identity includes link count. The open handle denies writes/deletes while DPAPI input is read.
if(-not ('RuntimeBackupFileIdentity' -as [type])) {
 Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class RuntimeBackupFileIdentity {
 [StructLayout(LayoutKind.Sequential)] struct Info { public uint attributes; public System.Runtime.InteropServices.ComTypes.FILETIME creation, access, write; public uint volume, sizeHigh, sizeLow, links, indexHigh, indexLow; }
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle handle,out Info info);
 public static void RequireSingleLink(SafeFileHandle handle) { Info i;if(!GetFileInformationByHandle(handle,out i)||i.links!=1)throw new InvalidOperationException("custody_link_rejected"); }
}
"@
}
function Get-RuntimeBackupKey([string]$KeyDirectory,[ValidateSet('backup','recovery')][string]$Purpose='backup',[switch]$Create) {
 $key=$null;$encrypted=$null;$entropy=[Text.Encoding]::UTF8.GetBytes('i-core-runtime-'+$Purpose+'-key-v1:'+$KeyDirectory.ToLowerInvariant());$file=Join-Path $KeyDirectory ('runtime-'+$Purpose+'.dpapi')
 try {
  if($Create){
   Assert-BackupPlainPath $KeyDirectory -Missing
   if(Test-Path -LiteralPath $KeyDirectory){throw 'fresh_key_directory_required'}
   [IO.Directory]::CreateDirectory($KeyDirectory)|Out-Null;Set-BackupPrivateAcl $KeyDirectory $true
   $key=New-Object byte[] 32;$rng=[Security.Cryptography.RandomNumberGenerator]::Create();try{$rng.GetBytes($key)}finally{$rng.Dispose()}
   $encrypted=[Security.Cryptography.ProtectedData]::Protect($key,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
   $stream=New-Object IO.FileStream($file,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
   try{$stream.Write($encrypted,0,$encrypted.Length);$stream.Flush($true)}finally{$stream.Dispose()}
   Set-BackupPrivateAcl $file $false
  }
  Assert-BackupPrivateAcl $KeyDirectory;Assert-BackupPrivateAcl $file
  $stream=New-Object IO.FileStream($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try {
   [RuntimeBackupFileIdentity]::RequireSingleLink($stream.SafeFileHandle)
   if($stream.Length -lt 32 -or $stream.Length -gt 8192){throw 'custody_size_invalid'}
   $encrypted=New-Object byte[] ([int]$stream.Length);$offset=0
   while($offset -lt $encrypted.Length){$n=$stream.Read($encrypted,$offset,$encrypted.Length-$offset);if(!$n){throw 'custody_truncated'};$offset+=$n}
   Assert-BackupPrivateAcl $file
   $decoded=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
   if($decoded.Length -ne 32){[Array]::Clear($decoded,0,$decoded.Length);throw 'custody_key_invalid'}
   return ,$decoded
  } finally {$stream.Dispose()}
 } catch {throw 'runtime_backup_key_custody_rejected'}
 finally {if($key){[Array]::Clear($key,0,$key.Length)};if($encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)};[Array]::Clear($entropy,0,$entropy.Length)}
}

if($Action -ne 'Library') {
 $loaded=$null
 try {
  $loaded=Get-RuntimeBackupKey -KeyDirectory $KeyDirectory -Purpose $Purpose -Create:($Action -eq 'Create')
  if($Action -eq 'Read') { $output=[Console]::OpenStandardOutput();$output.Write($loaded,0,$loaded.Length);$output.Flush() }
  else { [Console]::Out.WriteLine('{"created":true,"scope":"current_user_dpapi"}') }
 } catch { [Console]::Error.WriteLine('runtime_backup_key_custody_rejected');exit 2 }
 finally { if($loaded){[Array]::Clear($loaded,0,$loaded.Length)} }
}