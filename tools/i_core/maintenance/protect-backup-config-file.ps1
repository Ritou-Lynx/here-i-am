#requires -Version 5.1
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$Path,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedContentSha256,
 [Parameter(Mandatory=$true)][string]$ExpectedOwnerSid,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedOriginalDaclSha256,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedProposedDaclSha256,
 [Parameter(Mandatory=$true)][string]$ReceiptDirectory,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedOwnedArtifactsSha256,
 [switch]$Execute)
# Reviewed single-file maintenance only. DACL hashes are Access SDDL encoded as UTF-8.
# No configuration parsing, privilege enablement, target owner writes or release changes.
function Initialize-BackupConfigAclNative {
 if('BackupConfigAclNative' -as [type]){return}
 Add-Type -TypeDefinition @"
using System;using System.IO;using System.Text;using System.ComponentModel;using System.Runtime.InteropServices;using Microsoft.Win32.SafeHandles;
public static class BackupConfigAclNative {
 [StructLayout(LayoutKind.Sequential)] struct Info {public uint attr,cLo,cHi,aLo,aHi,wLo,wHi,volume,sizeHi,sizeLo,links,idHi,idLo;}
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFile(string p,uint a,uint s,IntPtr sa,uint d,uint f,IntPtr t);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info i);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(SafeFileHandle h,StringBuilder b,uint n,uint f);
 [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
 [DllImport("advapi32.dll")] static extern uint GetSecurityInfo(SafeFileHandle h,int type,uint info,out IntPtr o,out IntPtr g,out IntPtr d,out IntPtr s,out IntPtr sd);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool ConvertSecurityDescriptorToStringSecurityDescriptor(IntPtr sd,uint rev,uint info,out IntPtr s,out uint n);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(string s,uint rev,out IntPtr sd,out uint n);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool SetSecurityDescriptorControl(IntPtr sd,ushort mask,ushort flags);
 [DllImport("ntdll.dll")] static extern int NtSetSecurityObject(SafeFileHandle h,uint info,IntPtr sd);
 [DllImport("ntdll.dll")] static extern uint RtlNtStatusToDosError(int status);
 public static SafeFileHandle Ancestor(string p) {
  var h=CreateFile(p,0x81u,3,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
  if(h.IsInvalid)throw new Win32Exception(Marshal.GetLastWin32Error());
  try{Check(h,p,true);return h;}catch{h.Dispose();throw;}
 }
 public static SafeFileHandle Open(string p,bool directory,bool writeDacl) {
  // READ_CONTROL, read attributes/data, optional WRITE_DAC. Never WRITE_OWNER.
  var h=CreateFile(p,0x20080u|(writeDacl?0x40000u:0u)|(directory?1u:0x80000000u),directory?3u:1u,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
  if(h.IsInvalid)throw new Win32Exception(Marshal.GetLastWin32Error());
  try{Check(h,p,directory);return h;}catch{h.Dispose();throw;}
 }
 public static string Check(SafeFileHandle h,string p,bool directory) {
  Info i;var b=new StringBuilder(32768);uint n=GetFinalPathNameByHandle(h,b,32768,0);
  if(!GetFileInformationByHandle(h,out i)||n==0||n>=32768)throw new Win32Exception(Marshal.GetLastWin32Error());
  if((i.attr&0x400)!=0||((i.attr&0x10)!=0)!=directory||(!directory&&i.links!=1)||!b.ToString().Equals("\\\\?\\"+p,StringComparison.OrdinalIgnoreCase))throw new IOException("linked_or_aliased_target_rejected");
  return i.volume+":"+i.idHi+":"+i.idLo+(directory?"":":"+i.sizeHi+":"+i.sizeLo+":"+i.wHi+":"+i.wLo);
 }
 public static string Sddl(SafeFileHandle h) {
  IntPtr o,g,d,s,sd,text=IntPtr.Zero;uint n;uint code=GetSecurityInfo(h,1,7,out o,out g,out d,out s,out sd);
  if(code!=0)throw new Win32Exception((int)code);
  try{if(!ConvertSecurityDescriptorToStringSecurityDescriptor(sd,1,7,out text,out n))throw new Win32Exception(Marshal.GetLastWin32Error());return Marshal.PtrToStringUni(text);}finally{if(text!=IntPtr.Zero)LocalFree(text);LocalFree(sd);}
 }
 public static void DaclOnly(SafeFileHandle h,string sddl,bool protect) {
  IntPtr sd;uint n;if(!ConvertStringSecurityDescriptorToSecurityDescriptor(sddl,1,out sd,out n))throw new Win32Exception(Marshal.GetLastWin32Error());
  try{
   // Keep inherited ACE/control bits when restoring the exact original DACL.
   var raw=new System.Security.AccessControl.RawSecurityDescriptor(sddl);
   if((raw.ControlFlags&System.Security.AccessControl.ControlFlags.DiscretionaryAclAutoInherited)!=0)
    if(!SetSecurityDescriptorControl(sd,0x100,0x100))throw new Win32Exception(Marshal.GetLastWin32Error());
   // Native same-handle DACL-only update; no path reopen or child propagation.
   int status=NtSetSecurityObject(h,4u|(protect?0x80000000u:0x20000000u),sd);
   if(status<0)throw new Win32Exception((int)RtlNtStatusToDosError(status));
  }finally{LocalFree(sd);}
 }
}
"@
}
function Get-BackupConfigHash([byte[]]$Bytes) {
 $hash=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($hash.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()}
}
function Read-BackupConfigBytes($Stream) {
 $Stream.Position=0;$memory=[IO.MemoryStream]::new();try{$Stream.CopyTo($memory);return ,$memory.ToArray()}finally{$memory.Dispose();$Stream.Position=0}
}
function Hold-BackupConfigPath([string]$FilePath,[bool]$Directory,[bool]$WriteDacl) {
 if($FilePath -notmatch '^[A-Za-z]:\\' -or $FilePath.Substring(2).Contains(':') -or $FilePath.Contains('/') -or [IO.Path]::GetFullPath($FilePath) -cne $FilePath){throw 'canonical_path_required'}
 foreach($part in $FilePath.Substring(3).Split('\')){if(!$part -or $part -match '[. ]$' -or $part.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0){throw 'plain_path_required'}}
 $chain=@();for($q=[IO.Path]::GetDirectoryName($FilePath);$q;$q=[IO.Path]::GetDirectoryName($q)){$chain=@($q)+$chain}
 foreach($q in $chain){if(!$ancestors.ContainsKey($q)){$h=[BackupConfigAclNative]::Ancestor($q);$ancestors[$q]=$h;$locks.Add($h)}}
 $h=[BackupConfigAclNative]::Open($FilePath,$Directory,$WriteDacl);$locks.Add($h);return $h
}
function Get-BackupConfigDacl([string]$Sddl) {
 return [Security.AccessControl.RawSecurityDescriptor]::new($Sddl).GetSddlForm([Security.AccessControl.AccessControlSections]::Access)
}
function Get-BackupConfigProposedDacl([string]$OwnerSid) {
 $acl=[Security.AccessControl.FileSecurity]::new();$acl.SetAccessRuleProtection($true,$false)
 foreach($sid in @($OwnerSid,'S-1-5-18')){$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','Allow'))}
 return $acl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Access)
}
function Assert-BackupConfigFixedAcl($Handle,[string]$OwnerSid) {
 # Same file requirements as fixed key_custody.ps1 Assert-BackupPrivateAcl.
 $acl=[Security.AccessControl.FileSecurity]::new();$acl.SetSecurityDescriptorSddlForm([BackupConfigAclNative]::Sddl($Handle))
 if(!$acl.AreAccessRulesProtected -or $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne $OwnerSid){throw 'custody_acl_invalid'}
 $seen=@{};foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
  $sid=$rule.IdentityReference.Value
  if($sid -notin @($OwnerSid,'S-1-5-18') -or $rule.AccessControlType -ne 'Allow' -or $rule.FileSystemRights -ne [Security.AccessControl.FileSystemRights]::FullControl){throw 'custody_acl_invalid'}
  $seen[$sid]=$true
 }
 if(!$seen.ContainsKey($OwnerSid) -or !$seen.ContainsKey('S-1-5-18')){throw 'custody_acl_invalid'}
}
function Assert-BackupConfigState([bool]$Applied) {
 if([BackupConfigAclNative]::Check($targetHandle,$Path,$false) -cne $identity -or $targetStream.Length -ne $size){throw 'target_identity_drift'}
 $sddl=[BackupConfigAclNative]::Sddl($targetHandle);$raw=[Security.AccessControl.RawSecurityDescriptor]::new($sddl)
 if($raw.Owner.Value -cne $ExpectedOwnerSid -or $raw.GetSddlForm([Security.AccessControl.AccessControlSections]'Owner,Group') -cne $ownerGroup){throw 'owner_or_group_drift'}
 $expected=if($Applied){$proposed}else{$original}
 if((Get-BackupConfigDacl $sddl) -cne $expected){throw 'target_dacl_drift'}
 $bytes=Read-BackupConfigBytes $targetStream
 if((Get-BackupConfigHash $bytes) -cne $ExpectedContentSha256 -or $bytes.Length -ne $originalBytes.Length){throw 'target_bytes_drift'}
 for($i=0;$i -lt $bytes.Length;$i++){if($bytes[$i] -ne $originalBytes[$i]){throw 'target_bytes_drift'}}
 if($Applied){Assert-BackupConfigFixedAcl $targetHandle $ExpectedOwnerSid}
}
function Set-BackupConfigDacl($Handle,[string]$Sddl,[bool]$Protected) { [BackupConfigAclNative]::DaclOnly($Handle,$Sddl,$Protected) }
function Write-BackupConfigReceipt([string]$Name,$Value) {
 [OwnedArtifactNative]::Private($receiptHandle,$ExpectedOwnerSid,$true)
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 8))
 Write-OwnedArtifactBytes (Join-Path $ReceiptDirectory $Name) $bytes $ExpectedOwnerSid
 return Get-BackupConfigHash $bytes
}
function Invoke-BackupConfigProtection {
 param([string]$Path,[string]$ExpectedContentSha256,[string]$ExpectedOwnerSid,[string]$ExpectedOriginalDaclSha256,[string]$ExpectedProposedDaclSha256,[string]$ReceiptDirectory,[string]$ExpectedOwnedArtifactsSha256,[switch]$Execute)
 Set-StrictMode -Version 2;$ErrorActionPreference='Stop'
 if(!$Execute){throw 'explicit_execute_required'}
 foreach($hash in @($ExpectedContentSha256,$ExpectedOriginalDaclSha256,$ExpectedProposedDaclSha256,$ExpectedOwnedArtifactsSha256)){if($hash -cnotmatch '^[a-f0-9]{64}$'){throw 'sha256_required'}}
 Initialize-BackupConfigAclNative
 $locks=[Collections.Generic.List[IDisposable]]::new();$ancestors=@{};$targetHandle=$null;$receiptHandle=$null;$attempted=$false;$created=$false
 $result=[ordered]@{format='schema6-backup-config-acl-receipt-v1';passed=$false;scope='single_file_dacl_only';ownerChanged=$null;fileBytesChanged=$null;saclRead=$false;saclChanged=$false;rollbackAttempted=$false;rollbackVerified=$false;startedUtc=[DateTime]::UtcNow.ToString('o')}
 try{
  if($ExpectedOwnerSid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'current_owner_required'}
  $helperPath=Join-Path $PSScriptRoot 'owned_artifacts.ps1'
  if($Path.Equals($helperPath,[StringComparison]::OrdinalIgnoreCase) -or $Path.Equals($ReceiptDirectory,[StringComparison]::OrdinalIgnoreCase) -or $Path.StartsWith($ReceiptDirectory+'\',[StringComparison]::OrdinalIgnoreCase) -or $ReceiptDirectory.StartsWith($Path+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'artifact_scope_overlap'}
  $helperHandle=Hold-BackupConfigPath $helperPath $false $false
  $helperStream=[IO.FileStream]::new($helperHandle,[IO.FileAccess]::Read);$locks.Add($helperStream)
  if((Get-BackupConfigHash (Read-BackupConfigBytes $helperStream)) -cne $ExpectedOwnedArtifactsSha256){throw 'owned_artifact_source_hash_rejected'}
  . $helperPath
  $targetHandle=Hold-BackupConfigPath $Path $false $true
  $identity=[BackupConfigAclNative]::Check($targetHandle,$Path,$false)
  $targetStream=[IO.FileStream]::new($targetHandle,[IO.FileAccess]::Read);$locks.Add($targetStream);$size=$targetStream.Length
  $before=[BackupConfigAclNative]::Sddl($targetHandle);$raw=[Security.AccessControl.RawSecurityDescriptor]::new($before)
  if(!$raw.Owner -or $raw.Owner.Value -cne $ExpectedOwnerSid){throw 'owner_mismatch'}
  $ownerGroup=$raw.GetSddlForm([Security.AccessControl.AccessControlSections]'Owner,Group')
  $original=Get-BackupConfigDacl $before;$protectedBefore=[bool]($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected)
  if((Get-BackupConfigHash ([Text.Encoding]::UTF8.GetBytes($original))) -cne $ExpectedOriginalDaclSha256){throw 'original_dacl_hash_mismatch'}
  $originalBytes=Read-BackupConfigBytes $targetStream
  if((Get-BackupConfigHash $originalBytes) -cne $ExpectedContentSha256){throw 'content_hash_mismatch'}
  $proposed=Get-BackupConfigProposedDacl $ExpectedOwnerSid
  if((Get-BackupConfigHash ([Text.Encoding]::UTF8.GetBytes($proposed))) -cne $ExpectedProposedDaclSha256){throw 'proposed_dacl_hash_mismatch'}
  Assert-BackupConfigState $false
  $parentHandle=Hold-BackupConfigPath ([IO.Path]::GetDirectoryName($ReceiptDirectory)) $true $false
  Initialize-OwnedArtifactNative;[OwnedArtifactNative]::Private($parentHandle,$ExpectedOwnerSid,$true)
  New-OwnedArtifactDirectory $ReceiptDirectory $ExpectedOwnerSid;$created=$true
  $receiptHandle=Hold-BackupConfigPath $ReceiptDirectory $true $false
  $result.path=$Path;$result.identity=$identity;$result.size=$size;$result.contentSha256=$ExpectedContentSha256;$result.ownerSid=$ExpectedOwnerSid
  $result.originalDaclSha256=$ExpectedOriginalDaclSha256;$result.proposedDaclSha256=$ExpectedProposedDaclSha256
  $snapshotHash=Write-BackupConfigReceipt 'original.json' ([ordered]@{format='schema6-backup-config-acl-snapshot-v1';path=$Path;identity=$identity;size=$size;contentSha256=$ExpectedContentSha256;ownerSid=$ExpectedOwnerSid;originalDacl=$original;originalDaclSha256=$ExpectedOriginalDaclSha256;proposedDacl=$proposed;proposedDaclSha256=$ExpectedProposedDaclSha256})
  $snapshotHandle=Hold-BackupConfigPath (Join-Path $ReceiptDirectory 'original.json') $false $false
  [OwnedArtifactNative]::Private($snapshotHandle,$ExpectedOwnerSid,$true)
  $snapshotStream=[IO.FileStream]::new($snapshotHandle,[IO.FileAccess]::Read);$locks.Add($snapshotStream)
  if((Get-BackupConfigHash (Read-BackupConfigBytes $snapshotStream)) -cne $snapshotHash){throw 'snapshot_hash_drift'}
  Assert-BackupConfigState $false
  $attempted=$true;Set-BackupConfigDacl $targetHandle $proposed $true
  Assert-BackupConfigState $true
  # Independent read-only handle while the original remains pinned.
  $readback=Hold-BackupConfigPath $Path $false $false
  if([BackupConfigAclNative]::Check($readback,$Path,$false) -cne $identity -or [BackupConfigAclNative]::Sddl($readback) -cne [BackupConfigAclNative]::Sddl($targetHandle)){throw 'readback_mismatch'}
  Assert-BackupConfigFixedAcl $readback $ExpectedOwnerSid
  if((Get-BackupConfigHash (Read-BackupConfigBytes $snapshotStream)) -cne $snapshotHash){throw 'snapshot_hash_drift'}
  # This durable checkpoint precedes the final assertion and is never a terminal success.
  # Only the caller's captured process result plus exit 0 can establish completion.
  $result.passed=$null;$result.terminal=$false;$result.phase='validated_requires_successful_exit'
  $result.ownerChanged=$false;$result.fileBytesChanged=$false;$result.validatedUtc=[DateTime]::UtcNow.ToString('o')
  $null=Write-BackupConfigReceipt 'result.json' $result
  Assert-BackupConfigState $true
  $result.passed=$true;$result.terminal=$true;$result.phase='completed';$result.completedUtc=[DateTime]::UtcNow.ToString('o')
  return [pscustomobject]$result
 }catch{
  $result.passed=$false;$result.terminal=$true;$result.phase='failed';$result.ownerChanged=$null;$result.fileBytesChanged=$null
  $result.errorCode=if($_.Exception.Message -cmatch '^[a-z_]+$'){$_.Exception.Message}else{'backup_config_protection_failed'}
  if($attempted){
   $result.rollbackAttempted=$true
   try{Set-BackupConfigDacl $targetHandle $original $protectedBefore;Assert-BackupConfigState $false;$result.rollbackVerified=$true;$result.ownerChanged=$false;$result.fileBytesChanged=$false}
   catch{$result.rollbackVerified=$false;$result.requiresReviewedRecovery=$true}
  }
  $result.completedUtc=[DateTime]::UtcNow.ToString('o')
  if($created -and $receiptHandle){try{$null=Write-BackupConfigReceipt 'failure.json' $result}catch{$result.receiptWriteFailed=$true}}
  return [pscustomobject]$result
 }finally{for($j=$locks.Count-1;$j -ge 0;$j--){$locks[$j].Dispose()}}
}
$answer=Invoke-BackupConfigProtection @PSBoundParameters
$answer|ConvertTo-Json -Depth 8
if(!$answer.passed){exit 2}
