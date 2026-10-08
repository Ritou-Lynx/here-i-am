// Disposable hosted-runner fixture. Never requests elevation or changes the parent token.
// https://learn.microsoft.com/windows/win32/secauthz/restricted-tokens
using System;
using System.ComponentModel;
using System.Security.AccessControl;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
public static class Schema6IdentityToken {
 [StructLayout(LayoutKind.Sequential)] struct SidAttr { public IntPtr Sid; public uint Attributes; }
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct Startup {
  public int cb; public string reserved, desktop, title; public uint x,y,xs,ys,xc,yc,fill,flags; public short show,reserved2; public IntPtr reserved3,input,output,error;
 }
 [StructLayout(LayoutKind.Sequential)] struct ProcessInfo { public IntPtr process,thread; public uint pid,tid; }
 [StructLayout(LayoutKind.Sequential)] struct SecurityAttributes { public int length; public IntPtr descriptor; public int inherit; }
 [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
 [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
 [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool ConvertStringSecurityDescriptorToSecurityDescriptorW(string s,uint revision,out IntPtr sd,out uint size);
 [DllImport("user32.dll",SetLastError=true)] static extern IntPtr GetProcessWindowStation();
 [DllImport("user32.dll",SetLastError=true)] static extern IntPtr GetThreadDesktop(uint thread);
 [DllImport("user32.dll",SetLastError=true)] static extern bool SetProcessWindowStation(IntPtr station);
 [DllImport("user32.dll",SetLastError=true)] static extern bool SetThreadDesktop(IntPtr desktop);
 [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateWindowStationW(string name,uint flags,uint access,ref SecurityAttributes attributes);
 [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateDesktopW(string name,IntPtr device,IntPtr mode,uint flags,uint access,ref SecurityAttributes attributes);
 [DllImport("user32.dll",SetLastError=true)] static extern bool CloseWindowStation(IntPtr station);
 [DllImport("user32.dll",SetLastError=true)] static extern bool CloseDesktop(IntPtr desktop);
 [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool GetUserObjectInformationW(IntPtr handle,int kind,StringBuilder data,uint size,out uint needed);
 [DllImport("user32.dll",SetLastError=true)] static extern bool GetUserObjectSecurity(IntPtr handle,ref uint flags,IntPtr data,uint size,out uint needed);
 [DllImport("kernel32.dll",SetLastError=true)] static extern uint WaitForSingleObject(IntPtr h,uint ms);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr h,out uint code);
 [DllImport("kernel32.dll",SetLastError=true)] static extern uint ResumeThread(IntPtr h);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool TerminateProcess(IntPtr h,uint code);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr p,uint access,out IntPtr token);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr token,int kind,IntPtr data,int size,out int needed);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool SetTokenInformation(IntPtr token,int kind,IntPtr data,int size);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool DuplicateToken(IntPtr token,int level,out IntPtr duplicate);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool CheckTokenMembership(IntPtr token,IntPtr sid,out bool member);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetSecurityDescriptorDacl(IntPtr sd,out bool present,out IntPtr acl,out bool defaulted);
 [DllImport("advapi32.dll")] static extern uint GetSecurityDescriptorLength(IntPtr sd);
 [DllImport("advapi32.dll",SetLastError=true)] static extern uint GetSecurityInfo(IntPtr handle,int kind,uint flags,out IntPtr owner,out IntPtr group,out IntPtr dacl,out IntPtr sacl,out IntPtr sd);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool SetKernelObjectSecurity(IntPtr handle,uint flags,IntPtr descriptor);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool CreateRestrictedToken(IntPtr token,uint flags,uint disabled,ref SidAttr sids,uint privileges,IntPtr deleted,uint restricted,IntPtr restrict,out IntPtr result);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateProcessAsUserW(IntPtr token,string app,StringBuilder command,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr environment,string cwd,ref Startup startup,out ProcessInfo process);
 static IntPtr Info(IntPtr token,int kind) {
  int n; GetTokenInformation(token,kind,IntPtr.Zero,0,out n); if(n<1)throw new Win32Exception();
  IntPtr p=Marshal.AllocHGlobal(n); if(!GetTokenInformation(token,kind,p,n,out n)){Marshal.FreeHGlobal(p);throw new Win32Exception();} return p;
 }
 static string Sid(IntPtr token,int kind) {IntPtr p=Info(token,kind);try{return new SecurityIdentifier(Marshal.ReadIntPtr(p)).Value;}finally{Marshal.FreeHGlobal(p);}}
 static int Number(IntPtr token,int kind) {IntPtr p=Info(token,kind);try{return Marshal.ReadInt32(p);}finally{Marshal.FreeHGlobal(p);}}
 public sealed class GroupEvidence {public string sid,attributes;public bool enabled,denyOnly;}
 public sealed class Evidence {public string sid,owner,integritySid,windowStation,desktop,defaultDacl;public GroupEvidence[] groups,restrictedSids;public bool elevated,administrator;public int elevationType;}
 public static Evidence Current() {
  IntPtr token;if(!OpenProcessToken(GetCurrentProcess(),8,out token))throw new Win32Exception();
  try{return new Evidence{sid=Sid(token,1),owner=Sid(token,4),integritySid=Sid(token,25),elevated=Number(token,20)!=0,elevationType=Number(token,18),administrator=new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator),defaultDacl=DefaultDacl(token),groups=Groups(token,2),restrictedSids=Groups(token,11),windowStation=ObjectName(GetProcessWindowStation()),desktop=ObjectName(GetThreadDesktop(GetCurrentThreadId()))};}finally{CloseHandle(token);}
 }
 static GroupEvidence[] Groups(IntPtr token,int kind) {
  IntPtr p=Info(token,kind);try{int n=Marshal.ReadInt32(p);var result=new GroupEvidence[n];
   for(int i=0;i<n;i++){var entry=(SidAttr)Marshal.PtrToStructure(IntPtr.Add(p,IntPtr.Size+i*Marshal.SizeOf(typeof(SidAttr))),typeof(SidAttr));result[i]=new GroupEvidence{sid=new SecurityIdentifier(entry.Sid).Value,attributes="0x"+entry.Attributes.ToString("X8"),enabled=(entry.Attributes&4)!=0,denyOnly=(entry.Attributes&16)!=0};}return result;
  }finally{Marshal.FreeHGlobal(p);}
 }
 static string DefaultDacl(IntPtr token) {
  IntPtr p=Info(token,6);try{IntPtr acl=Marshal.ReadIntPtr(p);if(acl==IntPtr.Zero)return "NULL";
   int n=(ushort)Marshal.ReadInt16(acl,2);byte[] b=new byte[n];Marshal.Copy(acl,b,0,n);
   return new RawSecurityDescriptor(ControlFlags.DiscretionaryAclPresent,null,null,null,new RawAcl(b,0)).GetSddlForm(AccessControlSections.Access);
  }finally{Marshal.FreeHGlobal(p);}
 }
 static bool AdminMembership(IntPtr token) {
  IntPtr copy=IntPtr.Zero,sid=SidBytes("S-1-5-32-544");
  try{if(!DuplicateToken(token,1,out copy))throw new Win32Exception();bool member;if(!CheckTokenMembership(copy,sid,out member))throw new Win32Exception();return member;}
  finally{if(copy!=IntPtr.Zero)CloseHandle(copy);Marshal.FreeHGlobal(sid);}
 }
 static Evidence TokenEvidence(IntPtr token) {return new Evidence{sid=Sid(token,1),owner=Sid(token,4),integritySid=Sid(token,25),elevated=Number(token,20)!=0,elevationType=Number(token,18),administrator=AdminMembership(token),defaultDacl=DefaultDacl(token),groups=Groups(token,2),restrictedSids=Groups(token,11)};}
 static string KernelSecurity(IntPtr handle) {
  IntPtr o,g,d,s,sd;uint rc=GetSecurityInfo(handle,6,0x15,out o,out g,out d,out s,out sd);if(rc!=0)throw new Win32Exception((int)rc);
  try{var b=new byte[GetSecurityDescriptorLength(sd)];Marshal.Copy(sd,b,0,b.Length);return new RawSecurityDescriptor(b,0).GetSddlForm(AccessControlSections.Owner|AccessControlSections.Access|AccessControlSections.Audit);}finally{LocalFree(sd);}
 }
 static IntPtr PrivateDescriptor(string owner) {IntPtr sd;uint size;if(!ConvertStringSecurityDescriptorToSecurityDescriptorW("O:"+owner+"D:P(A;;GA;;;"+owner+")(A;;GA;;;SY)(A;;GA;;;BA)S:(ML;;NW;;;ME)",1,out sd,out size))throw new Win32Exception();return sd;}
 static void SetPrivateDefaultDacl(IntPtr token,IntPtr descriptor) {
  bool present,defaulted;IntPtr acl;if(!GetSecurityDescriptorDacl(descriptor,out present,out acl,out defaulted)||!present||acl==IntPtr.Zero)throw new InvalidOperationException("private_default_dacl_required");
  IntPtr p=Marshal.AllocHGlobal(IntPtr.Size);try{Marshal.WriteIntPtr(p,acl);if(!SetTokenInformation(token,6,p,IntPtr.Size))throw new Win32Exception();}finally{Marshal.FreeHGlobal(p);}
 }
 public sealed class LaunchEvidence {
  public bool privateDesktop,explicitKernelSecurity,privateTokenDefaultDacl,privateTokenObjectDacl,identityCheckedBeforeResume,terminatedBeforeResume,timedOut,terminatedAfterTimeout,tokenDaclVerified,kernelDaclVerified;
  public bool childCreated,childExitConfirmed,terminatedAfterFailure;
  public string stage,processIntegrity,threadIntegrity;
  public string parentTokenDefaultDacl,inheritedTokenDefaultDacl,limitedTokenDefaultDacl,limitedTokenSecurity,limitedTokenSecurityAfter,processSecurity,threadSecurity,childTokenSecurity;
  public Evidence limitedToken,childToken;public int exitCode;
 }
 public static LaunchEvidence LastLaunch {get;private set;}
 static void AssertPrivateDacl(string text,string owner,bool requireOwner) {
  var sd=new RawSecurityDescriptor(text);if(requireOwner&&(sd.Owner==null||sd.Owner.Value!=owner))throw new InvalidOperationException("new_kernel_owner_rejected");
  if(requireOwner&&(sd.ControlFlags&ControlFlags.DiscretionaryAclProtected)==0)throw new InvalidOperationException("new_kernel_dacl_unprotected");
  if(sd.DiscretionaryAcl==null||sd.DiscretionaryAcl.Count!=3)throw new InvalidOperationException("new_object_dacl_rejected");
  var expected=new System.Collections.Generic.HashSet<string>(new[]{owner,"S-1-5-18","S-1-5-32-544"});
  foreach(GenericAce raw in sd.DiscretionaryAcl){var ace=raw as CommonAce;if(ace==null||ace.IsCallback||ace.AceQualifier!=AceQualifier.AccessAllowed||ace.AceFlags!=AceFlags.None||!expected.Remove(ace.SecurityIdentifier.Value)||(ace.AccessMask!=0x10000000&&ace.AccessMask!=0x1fffff))throw new InvalidOperationException("new_object_dacl_rejected");}
  if(expected.Count!=0)throw new InvalidOperationException("new_object_dacl_rejected");
 }
 static string AssertMediumKernelLabel(string text) {
  var sd=new RawSecurityDescriptor(text);
  // Windows treats an unlabeled object as Medium (mandatory-integrity-control).
  if(sd.SystemAcl==null||sd.SystemAcl.Count==0)return "implicit-medium";
  if(sd.SystemAcl.Count!=1)throw new InvalidOperationException("new_kernel_label_rejected");
  var b=new byte[sd.SystemAcl[0].BinaryLength];sd.SystemAcl[0].GetBinaryForm(b,0);
  if(b.Length<20||b[0]!=17||b[1]!=0||BitConverter.ToUInt32(b,4)!=1||new SecurityIdentifier(b,8).Value!="S-1-16-8192")throw new InvalidOperationException("new_kernel_label_rejected");
  return "explicit-medium-no-write-up";
 }
 static void AssertPrivateTokenObjectDacl(string text,string owner) {
  var sd=new RawSecurityDescriptor(text);
  if(sd.DiscretionaryAcl==null||sd.DiscretionaryAcl.Count!=3||(sd.ControlFlags&ControlFlags.DiscretionaryAclProtected)==0)throw new InvalidOperationException("new_token_object_dacl_rejected");
  var expected=new System.Collections.Generic.HashSet<string>(new[]{owner,"S-1-5-18","S-1-5-32-544"});
  foreach(GenericAce raw in sd.DiscretionaryAcl){var ace=raw as CommonAce;if(ace==null||ace.IsCallback||ace.AceQualifier!=AceQualifier.AccessAllowed||ace.AceFlags!=AceFlags.None||!expected.Remove(ace.SecurityIdentifier.Value)||(ace.AccessMask!=0x10000000&&ace.AccessMask!=0xF01FF))throw new InvalidOperationException("new_token_object_dacl_rejected");}
 }
 static string ObjectName(IntPtr handle) {
  var name=new StringBuilder(512);uint needed;
  if(handle==IntPtr.Zero||!GetUserObjectInformationW(handle,2,name,1024,out needed))throw new Win32Exception();return name.ToString();
 }
 public sealed class DesktopEvidence {
  public string windowStation,desktop,owner,integritySid;
  public bool stationSecurityVerified,desktopSecurityVerified,parentStationRestored,parentThreadDesktopRestored,desktopClosed,stationClosed;
 }
 public static DesktopEvidence LastDesktop {get;private set;}
 static void CheckPrivateObject(IntPtr handle,string name,string owner,uint fullAccess) {
  if(ObjectName(handle)!=name)throw new InvalidOperationException("private_desktop_name_rejected");
  uint flags=0x15,needed;GetUserObjectSecurity(handle,ref flags,IntPtr.Zero,0,out needed);
  if(needed==0)throw new Win32Exception();IntPtr p=Marshal.AllocHGlobal((int)needed);
  try {
   if(!GetUserObjectSecurity(handle,ref flags,p,needed,out needed))throw new Win32Exception();
   var bytes=new byte[needed];Marshal.Copy(p,bytes,0,bytes.Length);var sd=new RawSecurityDescriptor(bytes,0);
   if(sd.Owner==null||sd.Owner.Value!=owner||sd.DiscretionaryAcl==null||sd.DiscretionaryAcl.Count!=3||(sd.ControlFlags&ControlFlags.DiscretionaryAclProtected)==0)throw new InvalidOperationException("private_desktop_security_rejected");
   var expected=new System.Collections.Generic.HashSet<string>(new[]{owner,"S-1-5-18","S-1-5-32-544"});
   foreach(GenericAce raw in sd.DiscretionaryAcl){var ace=raw as CommonAce;if(ace==null||ace.IsCallback||ace.AceQualifier!=AceQualifier.AccessAllowed||ace.AceFlags!=AceFlags.None||!expected.Remove(ace.SecurityIdentifier.Value)||(unchecked((uint)ace.AccessMask)!=fullAccess&&ace.AccessMask!=0x10000000))throw new InvalidOperationException("private_desktop_acl_rejected");}
   if(expected.Count!=0||sd.SystemAcl==null||sd.SystemAcl.Count!=1)throw new InvalidOperationException("private_desktop_label_rejected");
   var label=new byte[sd.SystemAcl[0].BinaryLength];sd.SystemAcl[0].GetBinaryForm(label,0);
   if(label.Length<20||label[0]!=17||label[1]!=0||BitConverter.ToUInt32(label,4)!=1||new SecurityIdentifier(label,8).Value!="S-1-16-8192")throw new InvalidOperationException("private_desktop_label_rejected");
  } finally {Marshal.FreeHGlobal(p);}
 }
 sealed class PrivateDesktop:IDisposable {
  IntPtr station,desktop;public readonly DesktopEvidence evidence;
  public string Path {get{return evidence.windowStation+"\\"+evidence.desktop;}}
  public PrivateDesktop(string owner) {
   evidence=new DesktopEvidence{windowStation="Schema6Identity-"+Guid.NewGuid().ToString("N"),desktop="Consumer-"+Guid.NewGuid().ToString("N"),owner=owner,integritySid="S-1-16-8192"};LastDesktop=evidence;
   IntPtr original=GetProcessWindowStation(),originalThreadDesktop=GetThreadDesktop(GetCurrentThreadId()),sd=IntPtr.Zero;uint size;
   if(original==IntPtr.Zero||originalThreadDesktop==IntPtr.Zero)throw new Win32Exception();
   try {
    string sddl="O:"+owner+"D:P(A;;GA;;;"+owner+")(A;;GA;;;SY)(A;;GA;;;BA)S:(ML;;NW;;;ME)";
    if(!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl,1,out sd,out size))throw new Win32Exception();
    var sa=new SecurityAttributes{length=Marshal.SizeOf(typeof(SecurityAttributes)),descriptor=sd,inherit=0};
    try {
     // CWF_CREATE_ONLY: never open or modify an existing station. No UI switch.
     station=CreateWindowStationW(evidence.windowStation,1,0xF037F,ref sa);if(station==IntPtr.Zero)throw new Win32Exception();
     CheckPrivateObject(station,evidence.windowStation,owner,0xF037F);evidence.stationSecurityVerified=true;
     if(!SetProcessWindowStation(station))throw new Win32Exception();
     desktop=CreateDesktopW(evidence.desktop,IntPtr.Zero,IntPtr.Zero,0,0xF01FF,ref sa);if(desktop==IntPtr.Zero)throw new Win32Exception();
     CheckPrivateObject(desktop,evidence.desktop,owner,0xF01FF);evidence.desktopSecurityVerified=true;
    } finally {
     if(!SetProcessWindowStation(original)||GetProcessWindowStation()!=original)throw new InvalidOperationException("parent_window_station_restore_failed");
     evidence.parentStationRestored=true;
     // Restore only this fixture thread if USER assigned the newly created
     // desktop. This never changes the visible/input desktop (no SwitchDesktop).
     if(GetThreadDesktop(GetCurrentThreadId())!=originalThreadDesktop&&!SetThreadDesktop(originalThreadDesktop))throw new InvalidOperationException("parent_thread_desktop_restore_failed");
     if(GetThreadDesktop(GetCurrentThreadId())!=originalThreadDesktop)throw new InvalidOperationException("parent_thread_desktop_restore_failed");
     evidence.parentThreadDesktopRestored=true;
    }
   } catch {Dispose();throw;} finally {if(sd!=IntPtr.Zero)LocalFree(sd);}
  }
  public void Dispose() {
   int failure=0;
   if(desktop!=IntPtr.Zero){if(CloseDesktop(desktop)){desktop=IntPtr.Zero;evidence.desktopClosed=true;}else failure=Marshal.GetLastWin32Error();}
   if(station!=IntPtr.Zero){if(CloseWindowStation(station)){station=IntPtr.Zero;evidence.stationClosed=true;}else if(failure==0)failure=Marshal.GetLastWin32Error();}
   if(failure!=0)throw new Win32Exception(failure,"private_desktop_cleanup_failed");
  }
 }
 static IntPtr SidBytes(string value) {var s=new SecurityIdentifier(value);var b=new byte[s.BinaryLength];s.GetBinaryForm(b,0);var p=Marshal.AllocHGlobal(b.Length);Marshal.Copy(b,0,p,b.Length);return p;}
 public static int RunLimited(string application,string arguments,string cwd) {
  // Fixed candidate, never select a passing diagnostic variant dynamically.
  return RunCore(application,arguments,cwd,true,true,true,false,0xffffffff);
 }
 // Diagnostics only: callers still get the exact same mandatory ordinary token
 // assertions. Variants change only newly created fixture objects, never a guard.
 public static int RunVariant(string application,string arguments,string cwd,bool usePrivateDesktop,bool explicitKernelSecurity,bool privateTokenDefaultDacl,bool privateTokenObjectDacl) {
  return RunCore(application,arguments,cwd,usePrivateDesktop,explicitKernelSecurity,privateTokenDefaultDacl,privateTokenObjectDacl,15000);
 }
 static int RunCore(string application,string arguments,string cwd,bool usePrivateDesktop,bool explicitKernelSecurity,bool privateTokenDefaultDacl,bool privateTokenObjectDacl,uint timeout) {
  IntPtr token=IntPtr.Zero,limited=IntPtr.Zero,admin=IntPtr.Zero,medium=IntPtr.Zero,user=IntPtr.Zero,buffer=IntPtr.Zero,descriptor=IntPtr.Zero,attributes=IntPtr.Zero,childToken=IntPtr.Zero;ProcessInfo pi=new ProcessInfo();PrivateDesktop privateDesktop=null;bool resumed=false;
  LastDesktop=null;LastLaunch=new LaunchEvidence{privateDesktop=usePrivateDesktop,explicitKernelSecurity=explicitKernelSecurity,privateTokenDefaultDacl=privateTokenDefaultDacl,privateTokenObjectDacl=privateTokenObjectDacl};
  try {
   LastLaunch.stage="restrict-token";
   if(!OpenProcessToken(GetCurrentProcess(),privateTokenObjectDacl?0x6008Bu:0x2008Bu,out token))throw new Win32Exception();
   LastLaunch.parentTokenDefaultDacl=DefaultDacl(token);
   admin=SidBytes("S-1-5-32-544");var disabled=new SidAttr{Sid=admin,Attributes=0};
   // DISABLE_MAX_PRIVILEGE | LUA_TOKEN; BA is explicitly deny-only as well.
   if(!CreateRestrictedToken(token,5,1,ref disabled,0,IntPtr.Zero,0,IntPtr.Zero,out limited))throw new Win32Exception();
   LastLaunch.inheritedTokenDefaultDacl=DefaultDacl(limited);
   medium=SidBytes("S-1-16-8192");buffer=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(SidAttr)));
   Marshal.StructureToPtr(new SidAttr{Sid=medium,Attributes=0x20},buffer,false);
   if(!SetTokenInformation(limited,25,buffer,Marshal.SizeOf(typeof(SidAttr))+new SecurityIdentifier("S-1-16-8192").BinaryLength))throw new Win32Exception();
   user=SidBytes(Sid(token,1));Marshal.WriteIntPtr(buffer,user);
   if(!SetTokenInformation(limited,4,buffer,IntPtr.Size))throw new Win32Exception();
   descriptor=PrivateDescriptor(Sid(token,1));
   if(privateTokenDefaultDacl)SetPrivateDefaultDacl(limited,descriptor);
   LastLaunch.limitedTokenDefaultDacl=DefaultDacl(limited);
   if(privateTokenDefaultDacl){AssertPrivateDacl(LastLaunch.limitedTokenDefaultDacl,Sid(token,1),false);LastLaunch.tokenDaclVerified=true;}
   LastLaunch.stage="inspect-limited-token";LastLaunch.limitedToken=TokenEvidence(limited);LastLaunch.limitedTokenSecurity=KernelSecurity(limited);
   // Diagnostic sixth variant only: the newly returned restricted token object.
   // Do not change the parent token, its default DACL, or any existing object.
   if(privateTokenObjectDacl){if(!SetKernelObjectSecurity(limited,0x80000004,descriptor))throw new Win32Exception();LastLaunch.limitedTokenSecurityAfter=KernelSecurity(limited);AssertPrivateTokenObjectDacl(LastLaunch.limitedTokenSecurityAfter,Sid(token,1));}
   if(Sid(limited,1)!=Sid(token,1)||Number(limited,20)!=0||Sid(limited,25)!="S-1-16-8192")throw new InvalidOperationException("limited_token_rejected");
   LastLaunch.stage="create-private-desktop";if(usePrivateDesktop)privateDesktop=new PrivateDesktop(Sid(token,1));
   if(explicitKernelSecurity){var sa=new SecurityAttributes{length=Marshal.SizeOf(typeof(SecurityAttributes)),descriptor=descriptor};attributes=Marshal.AllocHGlobal(sa.length);Marshal.StructureToPtr(sa,attributes,false);}
   var si=new Startup{cb=Marshal.SizeOf(typeof(Startup)),desktop=privateDesktop==null?null:privateDesktop.Path};
   LastLaunch.stage="create-suspended-child";
   if(!CreateProcessAsUserW(limited,application,new StringBuilder("\""+application+"\" "+arguments),attributes,attributes,false,0x08000004,IntPtr.Zero,cwd,ref si,out pi))throw new Win32Exception();
   LastLaunch.childCreated=true;
   LastLaunch.stage="inspect-actual-child";
   if(!OpenProcessToken(pi.process,0x2000A,out childToken))throw new Win32Exception();
   LastLaunch.childToken=TokenEvidence(childToken);var actual=LastLaunch.childToken;
   LastLaunch.childTokenSecurity=KernelSecurity(childToken);
   if(actual.sid!=Sid(token,1)||actual.owner!=actual.sid||actual.elevated||actual.administrator||actual.integritySid!="S-1-16-8192")throw new InvalidOperationException("actual_child_token_rejected");
   LastLaunch.processSecurity=KernelSecurity(pi.process);LastLaunch.threadSecurity=KernelSecurity(pi.thread);LastLaunch.identityCheckedBeforeResume=true;
   if(explicitKernelSecurity){AssertPrivateDacl(LastLaunch.processSecurity,actual.sid,true);AssertPrivateDacl(LastLaunch.threadSecurity,actual.sid,true);LastLaunch.processIntegrity=AssertMediumKernelLabel(LastLaunch.processSecurity);LastLaunch.threadIntegrity=AssertMediumKernelLabel(LastLaunch.threadSecurity);LastLaunch.kernelDaclVerified=true;}
   LastLaunch.stage="resume-child";
   if(ResumeThread(pi.thread)==0xffffffff)throw new Win32Exception();resumed=true;
   // Outer CI timeout bounds this process tree; never release its private root on a parent-only timeout.
   LastLaunch.stage="wait-child";uint wait=WaitForSingleObject(pi.process,timeout);
   if(wait==258){LastLaunch.timedOut=true;if(!TerminateProcess(pi.process,258)||WaitForSingleObject(pi.process,15000)!=0)throw new InvalidOperationException("diagnostic_child_cleanup_failed");LastLaunch.childExitConfirmed=true;LastLaunch.terminatedAfterTimeout=true;LastLaunch.exitCode=258;throw new InvalidOperationException("diagnostic_child_timeout");}
   if(wait!=0)throw new Win32Exception();
   LastLaunch.childExitConfirmed=true;
   uint code;if(!GetExitCodeProcess(pi.process,out code))throw new Win32Exception();LastLaunch.exitCode=(int)code;LastLaunch.stage="exited";return (int)code;
  } finally {
   try{if(pi.process!=IntPtr.Zero&&!LastLaunch.childExitConfirmed){
    // Covers every failure after creation, including an unexpected wait result
    // after resume. Never release a live child merely because launch validation failed.
    if(WaitForSingleObject(pi.process,0)!=0){if(!TerminateProcess(pi.process,2)||WaitForSingleObject(pi.process,15000)!=0)throw new InvalidOperationException("child_cleanup_failed");if(resumed)LastLaunch.terminatedAfterFailure=true;else LastLaunch.terminatedBeforeResume=true;}
    LastLaunch.childExitConfirmed=true;
   }}
   finally{
    foreach(IntPtr h in new[]{childToken,pi.thread,pi.process,limited,token})if(h!=IntPtr.Zero)CloseHandle(h);
    foreach(IntPtr p in new[]{admin,medium,user,buffer,attributes})if(p!=IntPtr.Zero)Marshal.FreeHGlobal(p);
    if(descriptor!=IntPtr.Zero)LocalFree(descriptor);
    if(privateDesktop!=null)privateDesktop.Dispose();
   }
  }
 }
}
