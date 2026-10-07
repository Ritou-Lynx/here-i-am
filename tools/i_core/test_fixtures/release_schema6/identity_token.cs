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
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr p,uint access,out IntPtr token);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr token,int kind,IntPtr data,int size,out int needed);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool SetTokenInformation(IntPtr token,int kind,IntPtr data,int size);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool CreateRestrictedToken(IntPtr token,uint flags,uint disabled,ref SidAttr sids,uint privileges,IntPtr deleted,uint restricted,IntPtr restrict,out IntPtr result);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateProcessAsUserW(IntPtr token,string app,StringBuilder command,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr environment,string cwd,ref Startup startup,out ProcessInfo process);
 static IntPtr Info(IntPtr token,int kind) {
  int n; GetTokenInformation(token,kind,IntPtr.Zero,0,out n); if(n<1)throw new Win32Exception();
  IntPtr p=Marshal.AllocHGlobal(n); if(!GetTokenInformation(token,kind,p,n,out n)){Marshal.FreeHGlobal(p);throw new Win32Exception();} return p;
 }
 static string Sid(IntPtr token,int kind) {IntPtr p=Info(token,kind);try{return new SecurityIdentifier(Marshal.ReadIntPtr(p)).Value;}finally{Marshal.FreeHGlobal(p);}}
 static int Number(IntPtr token,int kind) {IntPtr p=Info(token,kind);try{return Marshal.ReadInt32(p);}finally{Marshal.FreeHGlobal(p);}}
 public sealed class Evidence {public string sid,owner,integritySid,windowStation,desktop;public bool elevated,administrator;public int elevationType;}
 public static Evidence Current() {
  IntPtr token;if(!OpenProcessToken(GetCurrentProcess(),8,out token))throw new Win32Exception();
  try{return new Evidence{sid=Sid(token,1),owner=Sid(token,4),integritySid=Sid(token,25),elevated=Number(token,20)!=0,elevationType=Number(token,18),administrator=new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator),windowStation=ObjectName(GetProcessWindowStation()),desktop=ObjectName(GetThreadDesktop(GetCurrentThreadId()))};}finally{CloseHandle(token);}
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
  IntPtr token=IntPtr.Zero,limited=IntPtr.Zero,admin=IntPtr.Zero,medium=IntPtr.Zero,user=IntPtr.Zero,buffer=IntPtr.Zero;ProcessInfo pi=new ProcessInfo();PrivateDesktop privateDesktop=null;
  try {
   if(!OpenProcessToken(GetCurrentProcess(),0x008B,out token))throw new Win32Exception();
   admin=SidBytes("S-1-5-32-544");var disabled=new SidAttr{Sid=admin,Attributes=0};
   // DISABLE_MAX_PRIVILEGE | LUA_TOKEN; BA is explicitly deny-only as well.
   if(!CreateRestrictedToken(token,5,1,ref disabled,0,IntPtr.Zero,0,IntPtr.Zero,out limited))throw new Win32Exception();
   medium=SidBytes("S-1-16-8192");buffer=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(SidAttr)));
   Marshal.StructureToPtr(new SidAttr{Sid=medium,Attributes=0x20},buffer,false);
   if(!SetTokenInformation(limited,25,buffer,Marshal.SizeOf(typeof(SidAttr))+new SecurityIdentifier("S-1-16-8192").BinaryLength))throw new Win32Exception();
   user=SidBytes(Sid(token,1));Marshal.WriteIntPtr(buffer,user);
   if(!SetTokenInformation(limited,4,buffer,IntPtr.Size))throw new Win32Exception();
   if(Sid(limited,1)!=Sid(token,1)||Number(limited,20)!=0||Sid(limited,25)!="S-1-16-8192")throw new InvalidOperationException("limited_token_rejected");
   privateDesktop=new PrivateDesktop(Sid(token,1));
   var si=new Startup{cb=Marshal.SizeOf(typeof(Startup)),desktop=privateDesktop.Path};
   if(!CreateProcessAsUserW(limited,application,new StringBuilder("\""+application+"\" "+arguments),IntPtr.Zero,IntPtr.Zero,false,0x08000000,IntPtr.Zero,cwd,ref si,out pi))throw new Win32Exception();
   // Outer CI timeout bounds this process tree; never release its private root on a parent-only timeout.
   if(WaitForSingleObject(pi.process,0xffffffff)!=0)throw new Win32Exception();
   uint code;if(!GetExitCodeProcess(pi.process,out code))throw new Win32Exception();return (int)code;
  } finally {
   foreach(IntPtr h in new[]{pi.thread,pi.process,limited,token})if(h!=IntPtr.Zero)CloseHandle(h);
   foreach(IntPtr p in new[]{admin,medium,user,buffer})if(p!=IntPtr.Zero)Marshal.FreeHGlobal(p);
   if(privateDesktop!=null)privateDesktop.Dispose();
  }
 }
}
