# Import-safe shared live freeze verification. Never creates or changes a task.
function Assert-PreparePrivate([string]$Path){
 if($Path-notmatch '^[A-Za-z]:\\' -or $Path.Substring(2).Contains(':') -or [IO.Path]::GetFullPath($Path)-cne $Path){throw 'prepare_path_rejected'}
 for($q=$Path;$q;$q=[IO.Path]::GetDirectoryName($q)){if(([IO.File]::GetAttributes($q)-band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'prepare_reparse_rejected'}}
 $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$acl=Get-Acl -LiteralPath $Path
 if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value-cne $owner){throw 'prepare_owner_rejected'}
 $own=$false;foreach($r in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){if($r.AccessControlType-eq 'Allow'){
  if($r.IdentityReference.Value-notin @($owner,'S-1-5-18','S-1-5-32-544')){throw 'prepare_acl_rejected'}
  if($r.IdentityReference.Value-eq $owner -and ($r.FileSystemRights-band [Security.AccessControl.FileSystemRights]::FullControl)-eq [Security.AccessControl.FileSystemRights]::FullControl){$own=$true}
 }};if(!$own){throw 'prepare_owner_control_required'}
}
function Open-PreparePin([string]$Path,[string]$Sha256,[long]$Size=-1,[string]$FileId=''){
 if($Sha256-cnotmatch '^[a-f0-9]{64}$'){throw 'prepare_hash_required'}
 Assert-PreparePrivate $Path
 if(-not ('PreparePinIdentity' -as [type])){
 Add-Type -TypeDefinition @'
using System;using System.IO;using System.Text;using System.Runtime.InteropServices;
public static class PreparePinIdentity {
 [StructLayout(LayoutKind.Sequential)] struct Info {public uint a,c1,c2,a1,a2,w1,w2,volume,hi,lo,links,indexHi,indexLo;}
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(Microsoft.Win32.SafeHandles.SafeFileHandle h,out Info i);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(Microsoft.Win32.SafeHandles.SafeFileHandle h,StringBuilder p,uint n,uint f);
 public static string Check(FileStream s,string p){Info i;var b=new StringBuilder(32768);var n=GetFinalPathNameByHandle(s.SafeFileHandle,b,32768,0);if(!GetFileInformationByHandle(s.SafeFileHandle,out i)||i.links!=1||n==0||n>=32768||!b.ToString().Equals("\\\\?\\"+p,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("prepare_pin_identity_rejected");return i.volume.ToString("x8")+":"+i.indexHi.ToString("x8")+i.indexLo.ToString("x8");}
}
'@
 }
 $h=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{$id=[PreparePinIdentity]::Check($h,$Path);if($FileId -and $id-cne $FileId){throw 'prepare_file_identity_changed'}
  if($Size-ge 0 -and $h.Length-ne $Size){throw 'prepare_file_size_changed'}
  $sha=[Security.Cryptography.SHA256]::Create();try{$actual=([BitConverter]::ToString($sha.ComputeHash($h))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
  if($actual-cne $Sha256){throw 'prepare_file_hash_changed'};$h.Position=0;return $h
 }catch{$h.Dispose();throw}
}
function Assert-PrepareLiveFrozen($Config,$Frozen,$Service,$Leases){
 if($Frozen.format-cne 'schema6-frozen-legacy-runtime-ready-v2' -or $Frozen.windowId-cne $Config.windowId -or $Frozen.candidateSourceCommit-cne $Config.candidateSourceCommit -or $Frozen.candidateManifestSha256-cne $Config.candidateManifestSha256 -or $Frozen.passed-ne $true){throw 'prepare_live_binding_rejected'}
 if([DateTime]::UtcNow-lt [DateTime]::Parse($Frozen.createdUtc).ToUniversalTime() -or [DateTime]::UtcNow-ge [DateTime]::Parse($Frozen.expiresUtc).ToUniversalTime()){throw 'prepare_live_window_expired'}
 if((@($Frozen.tasks|ForEach-Object{$_.name}|Sort-Object)-join '|')-cne (@($Config.frozenTaskNames|Sort-Object)-join '|')){throw 'prepare_live_task_inventory_rejected'}
 foreach($t in $Frozen.tasks){
  $task=$Service.GetFolder($t.taskPath).GetTask($t.name)
  if($task.Path-cne ([string]$t.taskPath+[string]$t.name) -or $task.Enabled -or $task.GetInstances(0).Count-ne 0 -or $task.Definition.Triggers.Count-ne 0 -or $task.Definition.Settings.RestartCount-ne 0){throw 'prepare_live_task_not_frozen'}
  if($task.GetSecurityDescriptor(7)-cne $t.originalSddl){throw 'prepare_live_task_sddl_changed'}
  $sha=[Security.Cryptography.SHA256]::Create();try{$hash=([BitConverter]::ToString($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes([string]$task.Xml)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
  if($hash-cne $t.frozenXmlSha256){throw 'prepare_live_task_definition_changed'}
 }
 if((@($Frozen.portsFree|Sort-Object)-join ',')-cne (@($Config.frozenPorts|Sort-Object)-join ',')){throw 'prepare_live_port_inventory_rejected'}
 if(@(Get-NetTCPConnection -State Listen -ErrorAction Stop|Where-Object{$_.LocalPort-in $Config.frozenPorts}).Count){throw 'prepare_live_port_reoccupied'}
 if((@($Frozen.rawAfter|ForEach-Object{$_.path}|Sort-Object)-join '|')-cne (@($Config.rawPaths|Sort-Object)-join '|')){throw 'prepare_live_raw_inventory_rejected'}
 foreach($r in $Frozen.rawAfter){
  if([bool](Test-Path -LiteralPath $r.path)-ne [bool]$r.exists){throw 'prepare_live_raw_presence_changed'}
  if($r.exists){$Leases.Add((Open-PreparePin $r.path $r.sha256 ([long]$r.size) $r.file_id))}
 }
 foreach($key in $Config.externalFiles.PSObject.Properties.Name){$r=$Frozen.external.$key;foreach($p in $Config.externalFiles.$key){$Leases.Add((Open-PreparePin $p $r.sha256 ([long]$r.size)))}}
}
