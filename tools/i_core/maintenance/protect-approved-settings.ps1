#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProposalPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedProposalSha256,
 [Parameter(Mandatory=$true)][string]$ReceiptDirectory,[switch]$Execute)
# No UAC, privilege enablement, owner writes, deployment defaults or child ACL writes.
# SDDL means Owner/Group/DACL (the complete ordinary Get-Acl view); SACL is never requested or changed.
function Initialize-SettingsAclNative {
 if ('SettingsAclNative' -as [type]) { return }
 Add-Type -TypeDefinition @"
using System;using System.IO;using System.Text;using System.ComponentModel;using System.Runtime.InteropServices;using Microsoft.Win32.SafeHandles;
public static class SettingsAclNative {
 [StructLayout(LayoutKind.Sequential)] struct Info {public uint attr,cLo,cHi,aLo,aHi,wLo,wHi,volume,sizeHi,sizeLo,links,idHi,idLo;}
 [StructLayout(LayoutKind.Sequential)] struct SA {public int length;public IntPtr descriptor;public int inherit;}
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFile(string p,uint a,uint s,IntPtr sa,uint d,uint f,IntPtr t);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info i);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(SafeFileHandle h,StringBuilder b,uint n,uint f);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateDirectory(string p,ref SA a);
 [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
 [DllImport("advapi32.dll")] static extern uint GetSecurityInfo(SafeFileHandle h,int type,uint info,out IntPtr o,out IntPtr g,out IntPtr d,out IntPtr s,out IntPtr sd);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool ConvertSecurityDescriptorToStringSecurityDescriptor(IntPtr sd,uint rev,uint info,out IntPtr s,out uint n);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(string s,uint rev,out IntPtr sd,out uint n);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool SetSecurityDescriptorControl(IntPtr sd,ushort mask,ushort flags);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool SetFileSecurity(string path,uint info,IntPtr sd);
 public static SafeFileHandle Ancestor(string p) {
  var h=CreateFile(p,0x81u,3,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
  if(h.IsInvalid)throw new Win32Exception(Marshal.GetLastWin32Error());
  try{Check(h,p,true);return h;}catch{h.Dispose();throw;}
 }
 public static SafeFileHandle Open(string p,bool directory,bool writeDacl) {
  // READ_CONTROL + attributes, optional WRITE_DAC; files also read data. Never WRITE_OWNER.
  uint access=0x20080u|(writeDacl?0x40000u:0u)|(directory?1u:0x80000000u);
  var h=CreateFile(p,access,directory?3u:1u,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
  if(h.IsInvalid)throw new Win32Exception(Marshal.GetLastWin32Error());
  try{Check(h,p,directory);return h;}catch{h.Dispose();throw;}
 }
 public static string Check(SafeFileHandle h,string p,bool directory) {
  Info i;var b=new StringBuilder(32768);uint n=GetFinalPathNameByHandle(h,b,32768,0);
  if(!GetFileInformationByHandle(h,out i)||n==0||n>=32768)throw new Win32Exception(Marshal.GetLastWin32Error());
  if((i.attr&0x400)!=0||((i.attr&0x10)!=0)!=directory||(!directory&&i.links!=1)||!b.ToString().Equals("\\\\?\\"+p,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("linked_or_aliased_target_rejected");
  // Directory write time changes for unrelated namespace activity; file identity includes size and write time.
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
   // NT consumes AUTO_INHERIT_REQ and retains AUTO_INHERITED; without the request
   // SetFileSecurity clears AI even when it was present in the supplied SD.
   var raw=new System.Security.AccessControl.RawSecurityDescriptor(sddl);
   if((raw.ControlFlags&System.Security.AccessControl.ControlFlags.DiscretionaryAclAutoInherited)!=0)
    if(!SetSecurityDescriptorControl(sd,0x100,0x100))throw new Win32Exception(Marshal.GetLastWin32Error());
   // SetFileSecurity is the legacy FILE API with no child propagation. The complete
   // ancestor chain and target stay pinned against rename/delete until verification.
   var path=new StringBuilder(32768);uint count=GetFinalPathNameByHandle(h,path,32768,0);
   if(count==0||count>=32768)throw new Win32Exception(Marshal.GetLastWin32Error());
   if(!SetFileSecurity(path.ToString(),4u|(protect?0x80000000u:0x20000000u),sd))throw new Win32Exception(Marshal.GetLastWin32Error());
  }finally{LocalFree(sd);}
 }
 public static void FreshDirectory(string p,string sddl) {
  IntPtr sd;uint n;if(!ConvertStringSecurityDescriptorToSecurityDescriptor(sddl,1,out sd,out n))throw new Win32Exception(Marshal.GetLastWin32Error());
  try{var a=new SA{length=Marshal.SizeOf(typeof(SA)),descriptor=sd};if(!CreateDirectory(p,ref a))throw new Win32Exception(Marshal.GetLastWin32Error());}finally{LocalFree(sd);}
 }
}
"@
}
function Get-SettingsHash([byte[]]$Bytes) {
 $s=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($s.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$s.Dispose()}
}
function Assert-SettingsPlain([string]$Path) {
 if($Path -notmatch '^[A-Za-z]:\\' -or $Path.Substring(2).Contains(':') -or $Path.Contains('/') -or [IO.Path]::GetFullPath($Path) -cne $Path){throw 'canonical_path_required'}
 foreach($part in $Path.Substring(3).Split('\')){if(!$part -or $part -match '[. ]$' -or $part -match '[\x00-\x1f*?]'){throw 'plain_path_required'}}
}
function Hold-SettingsPath([string]$Path,[bool]$Directory,[bool]$WriteDacl) {
 Assert-SettingsPlain $Path
 $chain=@();for($q=[IO.Path]::GetDirectoryName($Path);$q;$q=[IO.Path]::GetDirectoryName($q)){$chain=@($q)+$chain}
 foreach($q in $chain){if(!$ancestors.ContainsKey($q)){$h=[SettingsAclNative]::Ancestor($q);$ancestors[$q]=$h;$locks.Add($h)}}
 $h=[SettingsAclNative]::Open($Path,$Directory,$WriteDacl);$locks.Add($h);return $h
}
function Assert-SettingsPrivate($Handle,[bool]$RequireProtected) {
 $a=[Security.AccessControl.RawSecurityDescriptor]::new([SettingsAclNative]::Sddl($Handle))
 if(!$a.Owner -or $a.Owner.Value -cne $owner){throw 'owner_mismatch'}
 if(!$a.DiscretionaryAcl){throw 'non_null_dacl_required'}
 if($RequireProtected -and !( $a.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected)){throw 'protected_directory_required'}
 foreach($ace in $a.DiscretionaryAcl){
  if($ace -isnot [Security.AccessControl.CommonAce] -or $ace.IsCallback){throw 'unsupported_ace'}
  if($ace.AceQualifier -eq [Security.AccessControl.AceQualifier]::AccessAllowed -and $ace.SecurityIdentifier.Value -notin @($owner,'S-1-5-18','S-1-5-32-544')){throw 'private_acl_required'}
 }
}
function Read-SettingsBytes($Stream) {
 $Stream.Position=0;$m=[IO.MemoryStream]::new();try{$Stream.CopyTo($m);return ,$m.ToArray()}finally{$m.Dispose();$Stream.Position=0}
}
function Assert-SettingsFields($Object,[string[]]$Fields) {
 if(@(Compare-Object @($Object.PSObject.Properties.Name|Sort-Object) @($Fields|Sort-Object)).Count){throw 'proposal_fields_invalid'}
}
function Assert-SettingsInventory {
 $actual=@(Get-ChildItem -LiteralPath $proposal.path -Force)
 if($actual.Count -ne 3){throw 'exact_three_files_required'}
 foreach($item in $actual){if($item.PSIsContainer -or !$files.ContainsKey($item.FullName)){throw 'unexpected_settings_item'}}
}
function Assert-SettingsState([bool]$Applied) {
 Assert-SettingsInventory
 foreach($row in $proposal.objects){
  $p=$row.path;$h=$handles[$p]
  if([SettingsAclNative]::Check($h,$p,$row.directory) -cne $identities[$p]){throw 'identity_drift'}
  Assert-SettingsPrivate $h $false
  $expected=if($row.directory -and $Applied){$proposal.expectedSddl}else{$row.originalSddl}
  if([SettingsAclNative]::Sddl($h) -cne $expected){if($row.directory){throw 'directory_sddl_drift'}else{throw 'child_sddl_drift'}}
  if(!$row.directory -and (Get-SettingsHash (Read-SettingsBytes $files[$p])) -cne $row.sha256){throw 'file_hash_drift'}
 }
}
function Write-SettingsReceipt([string]$Name,$Value) {
 Assert-SettingsPrivate $receiptHandle $true
 $p=Join-Path $ReceiptDirectory $Name
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 12))
 $f=[IO.File]::Open($p,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
 return Get-SettingsHash $bytes
}
function Set-SettingsDacl($Handle,[string]$Sddl,[bool]$Protected) { [SettingsAclNative]::DaclOnly($Handle,$Sddl,$Protected) }
function Invoke-SettingsProtection {
 param([string]$ProposalPath,[string]$ExpectedProposalSha256,[string]$ReceiptDirectory,[switch]$Execute)
 Set-StrictMode -Version 2;$ErrorActionPreference='Stop'
 if(!$Execute){throw 'explicit_execute_required'}
 if($ExpectedProposalSha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'proposal_hash_required'}
 Initialize-SettingsAclNative
 $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $locks=[Collections.Generic.List[IDisposable]]::new();$ancestors=@{};$handles=@{};$files=@{};$identities=@{}
 $attempted=$false;$created=$false;$receiptHandle=$null;$proposal=$null
 $result=[ordered]@{format='schema6-production-settings-acl-receipt-v1';proposalSha256=$ExpectedProposalSha256;passed=$false;scope='directory_dacl_only';ownerChanged=$null;childAclsChanged=$null;fileBytesChanged=$null;saclRead=$false;saclChanged=$false;rollbackAttempted=$false;rollbackVerified=$false;startedUtc=[DateTime]::UtcNow.ToString('o')}
 try {
  $ph=Hold-SettingsPath $ProposalPath $false $false;Assert-SettingsPrivate $ph $false
  $ps=[IO.FileStream]::new($ph,[IO.FileAccess]::Read);$locks.Add($ps)
  $bytes=Read-SettingsBytes $ps
  if((Get-SettingsHash $bytes) -cne $ExpectedProposalSha256){throw 'proposal_hash_mismatch'}
  $proposal=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)|ConvertFrom-Json
    Assert-SettingsFields $proposal @('format','requiresNewAuthorization','executed','path','preserveOwnerAndRights','operation','beforeSddlSha256','expectedSddlSha256','expectedSddl','objects','rollback')
  if($proposal.requiresNewAuthorization -isnot [bool] -or !$proposal.requiresNewAuthorization -or $proposal.executed -isnot [bool] -or $proposal.executed -or $proposal.preserveOwnerAndRights -isnot [bool] -or !$proposal.preserveOwnerAndRights -or $proposal.operation -isnot [string] -or [string]::IsNullOrWhiteSpace($proposal.operation) -or $proposal.rollback -isnot [string] -or [string]::IsNullOrWhiteSpace($proposal.rollback)){throw 'proposal_declarations_invalid'}
  if($proposal.format -cne 'schema6-production-settings-acl-proposal-v1' -or $proposal.objects -isnot [array] -or $proposal.objects.Count -ne 4){throw 'proposal_shape_invalid'}
  Assert-SettingsPlain $proposal.path;Assert-SettingsPlain $ReceiptDirectory
  foreach($p in @($ProposalPath,$ReceiptDirectory)){if($p.Equals($proposal.path,[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($proposal.path+'\',[StringComparison]::OrdinalIgnoreCase) -or $proposal.path.StartsWith($p+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'artifact_scope_overlap'}}
  $roots=@($proposal.objects|Where-Object {$_.directory -is [bool] -and $_.directory})
  if($roots.Count -ne 1 -or $roots[0].path -cne $proposal.path){throw 'single_directory_required'}
  foreach($row in $proposal.objects){
   if($row.directory -isnot [bool] -or $row.path -isnot [string] -or $row.originalSddl -isnot [string]){throw 'object_shape_invalid'}
   if($row.directory){Assert-SettingsFields $row @('path','directory','originalSddl')}else{
    Assert-SettingsFields $row @('path','directory','originalSddl','sha256')
    if([IO.Path]::GetDirectoryName($row.path) -cne $proposal.path -or $row.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'direct_file_required'}
   }
   if($handles.ContainsKey($row.path)){throw 'duplicate_object'}
   $h=Hold-SettingsPath $row.path $row.directory $row.directory;$handles[$row.path]=$h
   Assert-SettingsPrivate $h $false
   $identities[$row.path]=[SettingsAclNative]::Check($h,$row.path,$row.directory)
   if(!$row.directory){$stream=[IO.FileStream]::new($h,[IO.FileAccess]::Read);$locks.Add($stream);$files[$row.path]=$stream}
  }
  Assert-SettingsState $false
  $original=$roots[0].originalSddl
  if((Get-SettingsHash ([Text.Encoding]::UTF8.GetBytes($original))) -cne $proposal.beforeSddlSha256){throw 'before_sddl_hash_mismatch'}
  $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetSecurityDescriptorSddlForm($original)
  if($acl.AreAccessRulesProtected){throw 'already_protected'}
  $acl.SetAccessRuleProtection($true,$true)
  $expected=$acl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::All)
  if($expected -cne $proposal.expectedSddl -or (Get-SettingsHash ([Text.Encoding]::UTF8.GetBytes($expected))) -cne $proposal.expectedSddlSha256){throw 'exact_protection_only_required'}
  $parent=[IO.Path]::GetDirectoryName($ReceiptDirectory);$parentHandle=Hold-SettingsPath $parent $true $false;Assert-SettingsPrivate $parentHandle $true
  # Atomic create with a protected DACL; an existing output directory is never reused.
  $private='O:'+$owner+'D:P(A;OICI;FA;;;'+$owner+')(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'
  [SettingsAclNative]::FreshDirectory($ReceiptDirectory,$private);$created=$true
  $receiptHandle=Hold-SettingsPath $ReceiptDirectory $true $false;Assert-SettingsPrivate $receiptHandle $true
  $result.path=$proposal.path;$result.identities=$identities
  $snapshotHash=Write-SettingsReceipt 'original.json' ([ordered]@{format='schema6-production-settings-acl-snapshot-v1';proposalSha256=$ExpectedProposalSha256;objects=$proposal.objects;identities=$identities;expectedSddl=$expected;capturedUtc=[DateTime]::UtcNow.ToString('o')})
  $snapshotHandle=Hold-SettingsPath (Join-Path $ReceiptDirectory 'original.json') $false $false
  Assert-SettingsPrivate $snapshotHandle $false
  $snapshotStream=[IO.FileStream]::new($snapshotHandle,[IO.FileAccess]::Read);$locks.Add($snapshotStream)
  if((Get-SettingsHash (Read-SettingsBytes $snapshotStream)) -cne $snapshotHash){throw 'snapshot_hash_drift'}
  # Recheck after durable recovery material is pinned and immediately before mutation.
  Assert-SettingsState $false
  $attempted=$true
  Set-SettingsDacl $handles[$proposal.path] $expected $true
  Assert-SettingsState $true
  $result.ownerChanged=$false;$result.childAclsChanged=$false;$result.fileBytesChanged=$false
  $result.passed=$true;$result.completedUtc=[DateTime]::UtcNow.ToString('o')
  if((Get-SettingsHash (Read-SettingsBytes $snapshotStream)) -cne $snapshotHash){throw 'snapshot_hash_drift'}
  $null=Write-SettingsReceipt 'result.json' $result
  return [pscustomobject]$result
 }catch {
  $result.ownerChanged=$null;$result.childAclsChanged=$null;$result.fileBytesChanged=$null
  $result.passed=$false;$result.errorCode=if($_.Exception.Message -match '^[a-z_]+$'){$_.Exception.Message}else{'settings_protection_failed'}
  if($attempted){
   $result.rollbackAttempted=$true
   try{
    # Restore through the original pinned root even if inventory/content verification now fails.
    Set-SettingsDacl $handles[$proposal.path] $original $false
    Assert-SettingsState $false;$result.rollbackVerified=$true
    $result.ownerChanged=$false;$result.childAclsChanged=$false;$result.fileBytesChanged=$false
   }catch{$result.rollbackVerified=$false;$result.requiresReviewedRecovery=$true}
  }
  $result.completedUtc=[DateTime]::UtcNow.ToString('o')
  if($created -and $receiptHandle){try{$null=Write-SettingsReceipt 'failure.json' $result}catch{$result.receiptWriteFailed=$true}}
  return [pscustomobject]$result
 }finally {for($j=$locks.Count-1;$j -ge 0;$j--){$locks[$j].Dispose()}}
}
$answer=Invoke-SettingsProtection -ProposalPath $ProposalPath -ExpectedProposalSha256 $ExpectedProposalSha256 -ReceiptDirectory $ReceiptDirectory -Execute:$Execute
$answer|ConvertTo-Json -Depth 12
if(!$answer.passed){exit 2}
