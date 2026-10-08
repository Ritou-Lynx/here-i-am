# Import-safe process-image binding. This policy is only for executable images;
# data, configuration and release pins must keep their separate strict policy.
function Initialize-ProcessImageBindingNative {
 if ('ProcessImageBindingNative' -as [type]) { return }
 Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Text;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class ProcessImageBindingNative {
 [StructLayout(LayoutKind.Sequential)] struct Info { public uint attributes,c1,c2,a1,a2,w1,w2,volume,sizeHi,sizeLo,links,indexHi,indexLo; }
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info i);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(SafeFileHandle h,StringBuilder p,uint n,uint flags);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetWindowsDirectory(StringBuilder p,uint n);
 [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool CloseHandle(IntPtr h);
 [DllImport("kernel32.dll",SetLastError=true)] static extern uint GetProcessId(IntPtr h);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetProcessTimes(IntPtr h,out long creation,out long exit,out long kernel,out long user);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool QueryFullProcessImageName(IntPtr h,uint flags,StringBuilder p,ref uint n);
 [DllImport("kernel32.dll",SetLastError=true)] static extern uint WaitForSingleObject(IntPtr h,uint ms);
 public sealed class FileEvidence { public string final_path,file_id; public uint hardlink_count; }
 public static FileEvidence Inspect(FileStream s) {
  Info i;var b=new StringBuilder(32768);uint n=GetFinalPathNameByHandle(s.SafeFileHandle,b,32768,0);
  if(n==0||n>=32768||!GetFileInformationByHandle(s.SafeFileHandle,out i))throw new IOException("process_image_file_identity_unavailable");
  return new FileEvidence { final_path=b.ToString(),file_id=i.volume.ToString("x8")+":"+i.indexHi.ToString("x8")+i.indexLo.ToString("x8"),hardlink_count=i.links };
 }
 public static string WindowsDirectory() {
  var b=new StringBuilder(32768);uint n=GetWindowsDirectory(b,32768);
  if(n==0||n>=32768)throw new IOException("process_image_system_root_unavailable");return b.ToString();
 }
 public sealed class ProcessEvidence {public int pid;public long started_ticks;public string path;}
 public sealed class ProcessLease:IDisposable {
  IntPtr handle;
  public ProcessLease(int pid) {handle=OpenProcess(0x00101000,false,pid);if(handle==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error(),"process_image_process_unavailable");}
  public ProcessEvidence Inspect() {
   if(handle==IntPtr.Zero||WaitForSingleObject(handle,0)!=258)throw new InvalidOperationException("process_image_process_exited");
   long creation,exit,kernel,user;uint id=GetProcessId(handle);var b=new StringBuilder(32768);uint n=32768;
   if(id==0||!GetProcessTimes(handle,out creation,out exit,out kernel,out user)||!QueryFullProcessImageName(handle,0,b,ref n))throw new InvalidOperationException("process_image_process_identity_unavailable");
   return new ProcessEvidence {pid=checked((int)id),started_ticks=DateTime.FromFileTimeUtc(creation).Ticks,path=b.ToString()};
  }
  public void Dispose(){if(handle!=IntPtr.Zero){CloseHandle(handle);handle=IntPtr.Zero;}}
 }
 public static ProcessLease Open(int pid){return new ProcessLease(pid);}
}
"@
}
function Assert-ProcessImageCanonicalPath([string]$Path) {
 if ($Path -notmatch '^[A-Za-z]:\\' -or $Path.Substring(2).Contains(':') -or $Path.Contains('/') -or [IO.Path]::GetFullPath($Path) -cne $Path) { throw 'process_image_noncanonical_path' }
 foreach($part in $Path.Substring(3).Split('\')) {
  if(!$part -or $part.EndsWith('.') -or $part.EndsWith(' ')){throw 'process_image_noncanonical_path'}
 }
}
function Assert-ProcessImagePlainPath([string]$Path) {
 Assert-ProcessImageCanonicalPath $Path
 for($part=$Path;$part;$part=[IO.Path]::GetDirectoryName($part)) {
  if(([IO.File]::GetAttributes($part)-band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'process_image_reparse_path'}
 }
}
# Pure policy seam: callers cannot label an image non-system. Its classification
# is derived from the supplied path/root boundary; production obtains root from OS.
function Assert-ProcessImagePolicy {
 param([string]$Path,[string]$FinalPath,[string]$Sha256,[string]$ExpectedSha256,[string]$SystemRoot,[string]$OwnerSid,[long]$HardlinkCount,[bool]$HasReparsePoint=$false)
 Assert-ProcessImageCanonicalPath $Path
 Assert-ProcessImageCanonicalPath $SystemRoot
 if($HasReparsePoint){throw 'process_image_reparse_path'}
 if($FinalPath -ine ('\\?\'+$Path)){throw 'process_image_path_alias'}
 if($ExpectedSha256 -cnotmatch '^[a-f0-9]{64}$' -or $Sha256 -cne $ExpectedSha256){throw 'process_image_hash_mismatch'}
 if($HardlinkCount -lt 1){throw 'process_image_file_identity_unavailable'}
 $isSystem=$Path.StartsWith($SystemRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)
 if($isSystem -and $OwnerSid -cne 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'){throw 'process_image_system_owner_rejected'}
 return $isSystem
}
function Assert-ProcessImageFile {
 param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$ExpectedSha256)
 Initialize-ProcessImageBindingNative
 Assert-ProcessImagePlainPath $Path
 $lease=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try {
  $before=[ProcessImageBindingNative]::Inspect($lease)
  $ownerSid=$lease.GetAccessControl().GetOwner([Security.Principal.SecurityIdentifier]).Value
  $sha=[Security.Cryptography.SHA256]::Create()
  try{$actual=([BitConverter]::ToString($sha.ComputeHash($lease))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
  Assert-ProcessImagePlainPath $Path
  $after=[ProcessImageBindingNative]::Inspect($lease)
  if($before.file_id -cne $after.file_id -or $before.final_path -cne $after.final_path){throw 'process_image_file_identity_changed'}
  $isSystem=Assert-ProcessImagePolicy -Path $Path -FinalPath $after.final_path -Sha256 $actual -ExpectedSha256 $ExpectedSha256 -SystemRoot ([ProcessImageBindingNative]::WindowsDirectory()) -OwnerSid $ownerSid -HardlinkCount $after.hardlink_count
  $lease.Position=0
  return [pscustomobject]@{lease=$lease;path=$Path;sha256=$actual;file_id=$after.file_id;hardlink_count=$after.hardlink_count;owner_sid=$ownerSid;is_system_image=$isSystem}
 }catch{$lease.Dispose();throw}
}
function Get-BoundProcessIdentity {
 param([Parameter(Mandatory=$true)]$Row,[Parameter(Mandatory=$true)][System.Collections.IDictionary]$AllowedImages)
 Initialize-ProcessImageBindingNative
 $processLease=[ProcessImageBindingNative]::Open([int]$Row.ProcessId);$image=$null
 try {
  $actual=$processLease.Inspect()
  if($actual.pid -ne [int]$Row.ProcessId){throw 'process_image_pid_mismatch'}
  # CIM DMTF timestamps carry microseconds; kernel timestamps carry 100ns ticks.
  if($null -eq $Row.CreationDate -or [Math]::Abs([long]$actual.started_ticks-[long]$Row.CreationDate.ToUniversalTime().Ticks) -gt 9){throw 'process_image_cim_creation_mismatch'}
  if(!$Row.ExecutablePath -or $actual.path -ine [string]$Row.ExecutablePath){throw 'process_image_cim_path_mismatch'}
  $key=$actual.path.ToLowerInvariant()
  if(!$AllowedImages.Contains($key)){throw 'process_image_unapproved_image'}
  $image=Assert-ProcessImageFile -Path $actual.path -ExpectedSha256 ([string]$AllowedImages[$key])
  $again=$processLease.Inspect()
  if($again.pid -ne $actual.pid -or $again.started_ticks -ne $actual.started_ticks -or $again.path -ine $actual.path){throw 'process_image_identity_changed'}
  return [pscustomobject]@{pid=$actual.pid;parent_pid=[int]$Row.ParentProcessId;started_ticks=$actual.started_ticks.ToString();path=$actual.path;sha256=$image.sha256}
 }finally{if($image){$image.lease.Dispose()};$processLease.Dispose()}
}
