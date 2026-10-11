// Read-only native metadata. Initialization compiles only; calls require a reviewed lease.
using System;using System.IO;using System.Text;using System.Runtime.InteropServices;using System.Security.Principal;using System.Collections.Generic;using Microsoft.Win32.SafeHandles;
public sealed class ICoreObservedProcess { public int pid,parentPid,sessionId;public string startedTicks,imagePath,ownerSid; }
public sealed class ICoreObservedListener {public string address;public int port,pid;}
public static class ICoreIdentityNative {
 [StructLayout(LayoutKind.Sequential)]struct PBI{public IntPtr r1,peb,r2,r3;public UIntPtr pid,parent;}
 [DllImport("kernel32.dll",SetLastError=true)]static extern SafeProcessHandle OpenProcess(uint access,bool inherit,int pid);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool GetProcessTimes(SafeProcessHandle h,out long c,out long e,out long k,out long u);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool QueryFullProcessImageName(SafeProcessHandle h,uint flags,StringBuilder text,ref uint size);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool ProcessIdToSessionId(int pid,out uint session);
 [DllImport("advapi32.dll",SetLastError=true)]static extern bool OpenProcessToken(SafeProcessHandle h,uint access,out IntPtr token);
 [DllImport("advapi32.dll",SetLastError=true)]static extern bool GetTokenInformation(IntPtr token,int kind,IntPtr data,int size,out int needed);
 [DllImport("kernel32.dll")]static extern bool CloseHandle(IntPtr h);
 [DllImport("ntdll.dll")]static extern int NtQueryInformationProcess(SafeProcessHandle h,int kind,out PBI value,int size,out int returned);
 [DllImport("iphlpapi.dll",SetLastError=true)]static extern uint GetExtendedTcpTable(IntPtr rows,ref int bytes,bool ordered,int af,int kind,uint reserved);
 public static ICoreObservedProcess Process(int pid){
  if(pid<=0)throw new IOException("identity_pid");using(var h=OpenProcess(0x1000,false,pid)){
   if(h.IsInvalid)throw new IOException("identity_process_unavailable");
   long c,e,k,u;if(!GetProcessTimes(h,out c,out e,out k,out u)||e!=0)throw new IOException("identity_process_exited");
   var text=new StringBuilder(32768);uint size=32768,session;PBI info;int returned;
   if(!QueryFullProcessImageName(h,0,text,ref size)||!ProcessIdToSessionId(pid,out session)||NtQueryInformationProcess(h,0,out info,Marshal.SizeOf(typeof(PBI)),out returned)!=0||info.pid.ToUInt64()!=(ulong)pid)throw new IOException("identity_process_metadata");
   IntPtr token;if(!OpenProcessToken(h,8,out token))throw new IOException("identity_owner_unavailable");string owner;
   try{int needed;GetTokenInformation(token,1,IntPtr.Zero,0,out needed);if(needed<8||needed>65536)throw new IOException("identity_owner_size");IntPtr data=Marshal.AllocHGlobal(needed);try{if(!GetTokenInformation(token,1,data,needed,out needed))throw new IOException("identity_owner_unavailable");owner=new SecurityIdentifier(Marshal.ReadIntPtr(data)).Value;}finally{Marshal.FreeHGlobal(data);}}finally{CloseHandle(token);}
   long again;if(!GetProcessTimes(h,out again,out e,out k,out u)||again!=c||e!=0)throw new IOException("identity_process_changed");
   return new ICoreObservedProcess{pid=pid,parentPid=checked((int)info.parent.ToUInt64()),sessionId=checked((int)session),startedTicks=DateTime.FromFileTimeUtc(c).Ticks.ToString(System.Globalization.CultureInfo.InvariantCulture),imagePath=text.ToString(),ownerSid=owner};
  }
 }
 public static ICoreObservedListener[] Listeners(){
  int bytes=0;uint status=GetExtendedTcpTable(IntPtr.Zero,ref bytes,false,2,3,0);
  if(status!=122||bytes<4||bytes>16777216)throw new IOException("identity_tcp_size");IntPtr data=Marshal.AllocHGlobal(bytes);
  try{if(GetExtendedTcpTable(data,ref bytes,false,2,3,0)!=0)throw new IOException("identity_tcp_changed");int count=Marshal.ReadInt32(data);if(count<0||count>(bytes-4)/24)throw new IOException("identity_tcp_count");var rows=new List<ICoreObservedListener>();
   for(int i=0;i<count;i++){IntPtr p=IntPtr.Add(data,4+i*24);int state=Marshal.ReadInt32(p),port=(Marshal.ReadByte(p,8)<<8)|Marshal.ReadByte(p,9);if(port!=47841&&port!=47860&&port!=47862)continue;if(state!=2)throw new IOException("identity_tcp_state");byte[] a=new byte[4];Marshal.Copy(IntPtr.Add(p,4),a,0,4);rows.Add(new ICoreObservedListener{address=new System.Net.IPAddress(a).ToString(),port=port,pid=Marshal.ReadInt32(p,20)});}
   int size6=0;uint first6=GetExtendedTcpTable(IntPtr.Zero,ref size6,false,23,3,0);
   if(first6!=122||size6<4||size6>16777216)throw new IOException("identity_tcp6_size");
   IntPtr table6=Marshal.AllocHGlobal(size6);try{
    if(GetExtendedTcpTable(table6,ref size6,false,23,3,0)!=0)throw new IOException("identity_tcp6_changed");
    int count6=Marshal.ReadInt32(table6);if(count6<0||count6>(size6-4)/56)throw new IOException("identity_tcp6_count");
    for(int i=0;i<count6;i++){IntPtr p=IntPtr.Add(table6,4+i*56);int port=(Marshal.ReadByte(p,20)<<8)|Marshal.ReadByte(p,21);if(port!=47841&&port!=47860&&port!=47862)continue;
     byte[] address=new byte[16];Marshal.Copy(p,address,0,16);rows.Add(new ICoreObservedListener{address=new System.Net.IPAddress(address,unchecked((uint)Marshal.ReadInt32(p,16))).ToString(),port=port,pid=Marshal.ReadInt32(p,52)});}
   }finally{Marshal.FreeHGlobal(table6);}
   return rows.ToArray();
  }finally{Marshal.FreeHGlobal(data);}
 }
}
