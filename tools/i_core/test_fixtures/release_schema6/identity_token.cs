// Disposable hosted-runner fixture. Never requests elevation or changes the parent token.
// https://learn.microsoft.com/windows/win32/secauthz/restricted-tokens
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
public static class Schema6IdentityToken {
 [StructLayout(LayoutKind.Sequential)] struct SidAttr { public IntPtr Sid; public uint Attributes; }
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct Startup {
  public int cb; public string reserved, desktop, title; public uint x,y,xs,ys,xc,yc,fill,flags; public short show,reserved2; public IntPtr reserved3,input,output,error;
 }
 [StructLayout(LayoutKind.Sequential)] struct ProcessInfo { public IntPtr process,thread; public uint pid,tid; }
 [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
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
 public sealed class Evidence {public string sid,owner,integritySid;public bool elevated,administrator;public int elevationType;}
 public static Evidence Current() {
  IntPtr token;if(!OpenProcessToken(GetCurrentProcess(),8,out token))throw new Win32Exception();
  try{return new Evidence{sid=Sid(token,1),owner=Sid(token,4),integritySid=Sid(token,25),elevated=Number(token,20)!=0,elevationType=Number(token,18),administrator=new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator)};}finally{CloseHandle(token);}
 }
 static IntPtr SidBytes(string value) {var s=new SecurityIdentifier(value);var b=new byte[s.BinaryLength];s.GetBinaryForm(b,0);var p=Marshal.AllocHGlobal(b.Length);Marshal.Copy(b,0,p,b.Length);return p;}
 public static int RunLimited(string application,string arguments,string cwd) {
  IntPtr token=IntPtr.Zero,limited=IntPtr.Zero,admin=IntPtr.Zero,medium=IntPtr.Zero,user=IntPtr.Zero,buffer=IntPtr.Zero;ProcessInfo pi=new ProcessInfo();
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
   var si=new Startup{cb=Marshal.SizeOf(typeof(Startup))};
   if(!CreateProcessAsUserW(limited,application,new StringBuilder("\""+application+"\" "+arguments),IntPtr.Zero,IntPtr.Zero,false,0x08000000,IntPtr.Zero,cwd,ref si,out pi))throw new Win32Exception();
   // Outer CI timeout bounds this process tree; never release its private root on a parent-only timeout.
   if(WaitForSingleObject(pi.process,0xffffffff)!=0)throw new Win32Exception();
   uint code;if(!GetExitCodeProcess(pi.process,out code))throw new Win32Exception();return (int)code;
  } finally {
   foreach(IntPtr h in new[]{pi.thread,pi.process,limited,token})if(h!=IntPtr.Zero)CloseHandle(h);
   foreach(IntPtr p in new[]{admin,medium,user,buffer})if(p!=IntPtr.Zero)Marshal.FreeHGlobal(p);
  }
 }
}
