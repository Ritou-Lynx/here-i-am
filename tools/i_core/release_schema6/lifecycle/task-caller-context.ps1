#requires -Version 5.1
# Read-only Windows caller token metadata. No token handle, credential or secret is returned.
function Get-TaskCallerContext {
 if(!('HereIAmTaskCallerContext' -as [type])){
 Add-Type -TypeDefinition @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;
public sealed class HereIAmTaskCallerDto {
 public string UserSid; public int ProcessId; public int SessionId; public bool Is64Bit;
 public bool Elevated; public int ElevationType; public uint IntegrityRid; public bool AdministratorRoleEnabled;
}
public static class HereIAmTaskCallerContext {
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
 [DllImport("user32.dll")]static extern bool IsWindowVisible(IntPtr hwnd);
 [DllImport("user32.dll")]static extern IntPtr GetAncestor(IntPtr hwnd,uint flags);
 public static bool HiddenWindow(int pid,long window,uint thread){uint actual;IntPtr h=new IntPtr(window);return window!=0&&GetWindowThreadProcessId(h,out actual)==thread&&actual==(uint)pid&&GetAncestor(h,2)==h&&!IsWindowVisible(h);}
 [DllImport("advapi32.dll",SetLastError=true)]static extern bool GetTokenInformation(IntPtr token,int kind,IntPtr data,int length,out int returned);
 [DllImport("advapi32.dll")]static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);
 [DllImport("advapi32.dll")]static extern IntPtr GetSidSubAuthority(IntPtr sid,uint index);
 static int Integer(IntPtr token,int kind){
  IntPtr p=Marshal.AllocHGlobal(4);try{int n;if(!GetTokenInformation(token,kind,p,4,out n)||n!=4)throw new InvalidOperationException("caller_metadata_unavailable");return Marshal.ReadInt32(p);}finally{Marshal.FreeHGlobal(p);}
 }
 public static HereIAmTaskCallerDto Read(){
  using(var id=WindowsIdentity.GetCurrent())using(var process=Process.GetCurrentProcess()){
   int n;GetTokenInformation(id.Token,25,IntPtr.Zero,0,out n);
   if(n<=0||n>4096)throw new InvalidOperationException("caller_integrity_unavailable");
   IntPtr p=Marshal.AllocHGlobal(n);
   try{
    int returned;if(!GetTokenInformation(id.Token,25,p,n,out returned))throw new InvalidOperationException("caller_integrity_unavailable");
    IntPtr sid=Marshal.ReadIntPtr(p);byte count=Marshal.ReadByte(GetSidSubAuthorityCount(sid));
    if(count==0)throw new InvalidOperationException("caller_integrity_invalid");
    uint rid=unchecked((uint)Marshal.ReadInt32(GetSidSubAuthority(sid,(uint)(count-1))));
    return new HereIAmTaskCallerDto{UserSid=id.User.Value,ProcessId=process.Id,SessionId=process.SessionId,Is64Bit=Environment.Is64BitProcess,
     Elevated=Integer(id.Token,20)!=0,ElevationType=Integer(id.Token,18),IntegrityRid=rid,AdministratorRoleEnabled=new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator)};
   }finally{Marshal.FreeHGlobal(p);}
  }
 }
}
"@
 }
 return [HereIAmTaskCallerContext]::Read()
}
