#requires -Version 5.1
# Fresh maintenance artifacts only. Existing evidence is never repaired.
function Initialize-OwnedArtifactNative {
 if('OwnedArtifactNative' -as [type]){return}
 Add-Type -TypeDefinition @"
using System;using System.IO;using System.Text;using System.Collections.Generic;using System.ComponentModel;using System.Runtime.InteropServices;using System.Security.AccessControl;using System.Security.Principal;using Microsoft.Win32.SafeHandles;
public static class OwnedArtifactNative {
 [StructLayout(LayoutKind.Sequential)] struct Info {public uint attr,c1,c2,a1,a2,w1,w2,volume,hi,lo,links,idHi,idLo;}
 [StructLayout(LayoutKind.Sequential)] struct SA {public int length;public IntPtr sd;public int inherit;}
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFile(string p,uint a,uint s,IntPtr sa,uint d,uint f,IntPtr t);
 [StructLayout(LayoutKind.Sequential)] struct UnicodeString {public ushort length,maximumLength;public IntPtr buffer;}
 [StructLayout(LayoutKind.Sequential)] struct ObjectAttributes {public int length;public IntPtr root,name;public uint attributes;public IntPtr sd,qos;}
 [StructLayout(LayoutKind.Sequential)] struct IoStatus {public IntPtr status;public UIntPtr information;}
 [DllImport("ntdll.dll")] static extern int NtCreateFile(out SafeFileHandle h,uint access,ref ObjectAttributes attributes,out IoStatus status,IntPtr size,uint fileAttributes,uint share,uint disposition,uint options,IntPtr ea,uint eaLength);
 [DllImport("ntdll.dll")] static extern uint RtlNtStatusToDosError(int status);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info i);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(SafeFileHandle h,StringBuilder b,uint n,uint f);
 [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(string s,uint rev,out IntPtr sd,out uint size);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetSecurityDescriptorOwner(IntPtr sd,out IntPtr owner,out bool def);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetSecurityDescriptorDacl(IntPtr sd,out bool present,out IntPtr acl,out bool def);
 [DllImport("advapi32.dll")] static extern uint SetSecurityInfo(SafeFileHandle h,int type,uint flags,IntPtr owner,IntPtr group,IntPtr dacl,IntPtr sacl);
 [DllImport("advapi32.dll")] static extern uint GetSecurityInfo(SafeFileHandle h,int type,uint flags,out IntPtr owner,out IntPtr group,out IntPtr dacl,out IntPtr sacl,out IntPtr sd);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool ConvertSecurityDescriptorToStringSecurityDescriptor(IntPtr sd,uint rev,uint flags,out IntPtr text,out uint size);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr token,int kind,out int value,int length,out int returned);
 public static void Unelevated(string owner){using(var id=WindowsIdentity.GetCurrent()){int elevated,n;if(!GetTokenInformation(id.Token,20,out elevated,4,out n))throw new Win32Exception(Marshal.GetLastWin32Error());if(n!=4||elevated!=0||id.User==null||id.User.Value!=owner||id.Owner==null||id.Owner.Value!=owner||new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator))throw new IOException("maintenance_unelevated_owner_required");}}
 public static void Plain(string p) {
  if(p.Length<3||!Char.IsLetter(p[0])||p[1]!=':'||p[2]!='\\'||p.Substring(2).Contains(":")||p.Contains("/")||Path.GetFullPath(p)!=p)throw new IOException("artifact_path_rejected");
  foreach(string part in p.Substring(3).Split('\\')){if(part.Length==0 && p.Length==3)continue;if(part.Length==0||part.EndsWith(".")||part.EndsWith(" ")||part.IndexOfAny(Path.GetInvalidFileNameChars())>=0)throw new IOException("artifact_path_rejected");}
 }
 public static string Check(SafeFileHandle h,string p,bool dir) {
  Info i;var b=new StringBuilder(32768);uint n=GetFinalPathNameByHandle(h,b,32768,0);
  if(!GetFileInformationByHandle(h,out i)||n==0||n>=32768)throw new Win32Exception(Marshal.GetLastWin32Error());
  if((i.attr&0x400)!=0||((i.attr&0x10)!=0)!=dir||(!dir&&i.links!=1)||!b.ToString().Equals("\\\\?\\"+p,StringComparison.OrdinalIgnoreCase))throw new IOException("artifact_identity_rejected");
  return i.volume+":"+i.idHi+":"+i.idLo;
 }
 static SafeFileHandle Open(string p,bool dir,bool write,uint share) {
  var h=CreateFile(p,0x20080u|(dir?1u:0x80000000u)|(write?0xC0000u:0u),share,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
  if(h.IsInvalid)throw new Win32Exception(Marshal.GetLastWin32Error());try{Check(h,p,dir);return h;}catch{h.Dispose();throw;}
 }
 static List<SafeFileHandle> Parents(string p){Plain(p);var paths=new List<string>();for(string q=Path.GetDirectoryName(p);!String.IsNullOrEmpty(q);q=Path.GetDirectoryName(q))paths.Insert(0,q);var handles=new List<SafeFileHandle>();try{foreach(string q in paths)handles.Add(Open(q,true,false,3));return handles;}catch{foreach(var h in handles)h.Dispose();throw;}}
 public static string Sddl(SafeFileHandle h){IntPtr o,g,d,s,sd,t=IntPtr.Zero;uint n;uint rc=GetSecurityInfo(h,1,5,out o,out g,out d,out s,out sd);if(rc!=0)throw new Win32Exception((int)rc);try{if(!ConvertSecurityDescriptorToStringSecurityDescriptor(sd,1,5,out t,out n))throw new Win32Exception(Marshal.GetLastWin32Error());return Marshal.PtrToStringUni(t);}finally{if(t!=IntPtr.Zero)LocalFree(t);LocalFree(sd);}}
 public static void Private(SafeFileHandle h,string owner,bool protectedRequired){
  var sd=new RawSecurityDescriptor(Sddl(h));if(sd.Owner==null||sd.Owner.Value!=owner||sd.DiscretionaryAcl==null||(protectedRequired&&(sd.ControlFlags&ControlFlags.DiscretionaryAclProtected)==0))throw new IOException("artifact_owner_or_dacl_rejected");
  bool own=false;foreach(GenericAce ace in sd.DiscretionaryAcl){var a=ace as CommonAce;if(a==null||a.IsCallback)throw new IOException("artifact_ace_rejected");if(a.AceQualifier==AceQualifier.AccessAllowed){if(a.SecurityIdentifier.Value!=owner&&a.SecurityIdentifier.Value!="S-1-5-18"&&a.SecurityIdentifier.Value!="S-1-5-32-544")throw new IOException("artifact_private_acl_rejected");if(a.SecurityIdentifier.Value==owner&&(a.AceFlags&AceFlags.InheritOnly)==0&&(a.AccessMask&0x1F01FF)==0x1F01FF)own=true;}}
  if(!own)throw new IOException("artifact_owner_control_required");
 }
 static string Descriptor(string owner,bool dir){if(new SecurityIdentifier(owner).Value!=WindowsIdentity.GetCurrent().User.Value)throw new IOException("artifact_same_owner_required");string flags=dir?"OICI":"";return "O:"+owner+"D:P(A;"+flags+";FA;;;"+owner+")(A;"+flags+";FA;;;SY)(A;"+flags+";FA;;;BA)";}
 static IntPtr DescriptorPointer(string owner,bool dir){IntPtr sd;uint n;if(!ConvertStringSecurityDescriptorToSecurityDescriptor(Descriptor(owner,dir),1,out sd,out n))throw new Win32Exception(Marshal.GetLastWin32Error());return sd;}
 static void SetPrivate(SafeFileHandle h,IntPtr sd,string owner){IntPtr o,d;bool present,def;if(!GetSecurityDescriptorOwner(sd,out o,out def)||!GetSecurityDescriptorDacl(sd,out present,out d,out def)||!present)throw new IOException("artifact_descriptor_rejected");uint rc=SetSecurityInfo(h,1,0x80000005u,o,IntPtr.Zero,d,IntPtr.Zero);if(rc!=0)throw new Win32Exception((int)rc);Private(h,owner,true);}
 public sealed class OwnedStream:FileStream {
  List<SafeFileHandle> parents;
  public OwnedStream(SafeFileHandle h,List<SafeFileHandle> p):base(h,FileAccess.ReadWrite){parents=p;}
  protected override void Dispose(bool disposing){try{base.Dispose(disposing);}finally{if(parents!=null){foreach(var h in parents)h.Dispose();parents=null;}}}
 }
 public static FileStream FreshFile(string p,string owner){
  var parents=Parents(p);SafeFileHandle h=null;IntPtr sd=IntPtr.Zero,saPtr=IntPtr.Zero;
  try{sd=DescriptorPointer(owner,false);var sa=new SA{length=Marshal.SizeOf(typeof(SA)),sd=sd};saPtr=Marshal.AllocHGlobal(sa.length);Marshal.StructureToPtr(sa,saPtr,false);
   h=CreateFile(p,0xC00E0080u,0,saPtr,1,0x00200000,IntPtr.Zero);if(h.IsInvalid)throw new Win32Exception(Marshal.GetLastWin32Error());
   Check(h,p,false);SetPrivate(h,sd,owner);Check(h,p,false);return new OwnedStream(h,parents);
  }catch{if(h!=null)h.Dispose();foreach(var ph in parents)ph.Dispose();throw;}finally{if(saPtr!=IntPtr.Zero)Marshal.FreeHGlobal(saPtr);if(sd!=IntPtr.Zero)LocalFree(sd);}
 }
 public static void FreshDirectory(string p,string owner){
  var parents=Parents(p);IntPtr sd=IntPtr.Zero,name=IntPtr.Zero,unicode=IntPtr.Zero;SafeFileHandle h=null;
  try{
   if(parents.Count==0)throw new IOException("artifact_parent_required");
   sd=DescriptorPointer(owner,true);string leaf=Path.GetFileName(p);int length=Encoding.Unicode.GetByteCount(leaf);if(length>65532)throw new IOException("artifact_name_too_long");
   name=Marshal.StringToHGlobalUni(leaf);var us=new UnicodeString{length=(ushort)length,maximumLength=(ushort)(length+2),buffer=name};unicode=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(UnicodeString)));Marshal.StructureToPtr(us,unicode,false);
   var oa=new ObjectAttributes{length=Marshal.SizeOf(typeof(ObjectAttributes)),root=parents[parents.Count-1].DangerousGetHandle(),name=unicode,attributes=0x40,sd=sd};IoStatus io;
   // FILE_CREATE returns the new directory handle atomically, never OPEN_IF.
   int status=NtCreateFile(out h,0x001E0081u,ref oa,out io,IntPtr.Zero,0x10,3,2,0x00200021,IntPtr.Zero,0);
   if(status<0)throw new Win32Exception((int)RtlNtStatusToDosError(status));
   if(h==null||h.IsInvalid||io.information.ToUInt64()!=2)throw new IOException("artifact_fresh_directory_required");
   string id=Check(h,p,true);SetPrivate(h,sd,owner);if(Check(h,p,true)!=id)throw new IOException("artifact_identity_changed");
   using(var read=Open(p,true,false,3)){if(Check(read,p,true)!=id)throw new IOException("artifact_identity_changed");Private(read,owner,true);}
   if(Check(h,p,true)!=id)throw new IOException("artifact_identity_changed");Private(h,owner,true);
  }finally{if(h!=null)h.Dispose();if(unicode!=IntPtr.Zero)Marshal.FreeHGlobal(unicode);if(name!=IntPtr.Zero)Marshal.FreeHGlobal(name);if(sd!=IntPtr.Zero)LocalFree(sd);foreach(var ph in parents)ph.Dispose();}
 }
 public static void Assert(string p,string owner,bool dir){var parents=Parents(p);try{using(var h=Open(p,dir,false,1)){Check(h,p,dir);Private(h,owner,false);}}finally{foreach(var h in parents)h.Dispose();}}
 public static void Readback(FileStream stream,string p,string owner,byte[] bytes){Check(stream.SafeFileHandle,p,false);Private(stream.SafeFileHandle,owner,true);if(stream.Length!=bytes.Length)throw new IOException("artifact_bytes_rejected");stream.Position=0;for(int n=0;n<bytes.Length;n++){if(stream.ReadByte()!=bytes[n])throw new IOException("artifact_bytes_rejected");}stream.Position=0;Check(stream.SafeFileHandle,p,false);Private(stream.SafeFileHandle,owner,true);}
 public static void Write(string p,string owner,byte[] bytes){string id;using(var s=FreshFile(p,owner)){id=Check(s.SafeFileHandle,p,false);s.Write(bytes,0,bytes.Length);s.Flush(true);Readback(s,p,owner,bytes);}var parents=Parents(p);try{using(var h=Open(p,false,false,1)){if(Check(h,p,false)!=id)throw new IOException("artifact_identity_changed");using(var s=new FileStream(h,FileAccess.Read)){Readback(s,p,owner,bytes);}}}finally{foreach(var h in parents)h.Dispose();}}
}
"@
}
function New-OwnedArtifactFile([string]$Path,[string]$OwnerSid){$ErrorActionPreference='Stop';Initialize-OwnedArtifactNative;return [OwnedArtifactNative]::FreshFile($Path,$OwnerSid)}
function Write-OwnedArtifactBytes([string]$Path,[byte[]]$Bytes,[string]$OwnerSid){$ErrorActionPreference='Stop';Initialize-OwnedArtifactNative;[OwnedArtifactNative]::Write($Path,$OwnerSid,$Bytes)}
function New-OwnedArtifactDirectory([string]$Path,[string]$OwnerSid){$ErrorActionPreference='Stop';Initialize-OwnedArtifactNative;[OwnedArtifactNative]::FreshDirectory($Path,$OwnerSid)}
function Assert-OwnedArtifact([string]$Path,[string]$OwnerSid,[bool]$Directory=$false){$ErrorActionPreference='Stop';Initialize-OwnedArtifactNative;[OwnedArtifactNative]::Assert($Path,$OwnerSid,$Directory)}
function Assert-OwnedArtifactUnelevatedProcess([string]$OwnerSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
 $ErrorActionPreference='Stop';Initialize-OwnedArtifactNative;[OwnedArtifactNative]::Unelevated($OwnerSid)
}
