using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

// Current-user synthetic ping/EOF fixture. No product resources or process
// control. Its own finite deadline prevents an abandoned fixture process.
internal static class WitnessClientSmoke {
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern bool GetNamedPipeClientProcessId(IntPtr pipe, out uint pid);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern bool GetProcessTimes(IntPtr process, out ulong creation,
      out ulong exit, out ulong kernel, out ulong user);
  static byte[] Read(PipeStream pipe, int count) {
    var bytes = new byte[count]; int offset = 0;
    while(offset < count) { int n=pipe.Read(bytes,offset,count-offset); if(n<=0)throw new Exception(); offset+=n; }
    return bytes;
  }
  static void Command(PipeStream pipe, string epoch, int sequence) {
    uint length=BitConverter.ToUInt32(Read(pipe,4),0);
    if(length<1||length>16384)throw new Exception();
    var json = new JavaScriptSerializer();
    var value=json.Deserialize<Dictionary<string,object>>(new UTF8Encoding(false,true).GetString(Read(pipe,(int)length)));
    if(value.Count!=4 || (string)value["schema"]!="p6_r7_owned_recovery_command_v1" ||
       (string)value["epoch"]!=epoch || (string)value["type"]!="ping" ||
       !(value["sequence"] is int) || (int)value["sequence"]!=sequence)throw new Exception();
  }
  static int Main(string[] args) {
    string phase="arguments";
    using(var deadline=new Timer(_=>Environment.Exit(4),null,25000,Timeout.Infinite)) {
      try {
        if(args.Length!=2 || args[0].Length!=64) return 4;
        uint expected=uint.Parse(args[1]); string epoch=args[0];
        var sid=WindowsIdentity.GetCurrent().User;
        var security=new PipeSecurity(); security.SetAccessRuleProtection(true,false); security.SetOwner(sid);
        security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.NetworkSid,null),PipeAccessRights.FullControl,AccessControlType.Deny));
        security.AddAccessRule(new PipeAccessRule(sid,PipeAccessRights.FullControl,AccessControlType.Allow));
        using(var pipe=new NamedPipeServerStream("p6-r7-recovery-"+epoch+"-app",PipeDirection.InOut,1,PipeTransmissionMode.Byte,PipeOptions.Asynchronous,16384,16384,security)) {
          using(var self=Process.GetCurrentProcess()) {
            ulong creation,exit,kernel,user;
            if(!GetProcessTimes(self.Handle,out creation,out exit,out kernel,out user))return 4;
            Console.WriteLine("{\"pid\":"+self.Id+",\"creation\":\""+creation+"\"}"); Console.Out.Flush();
          }
          phase="accept"; var pending=pipe.BeginWaitForConnection(null,null);
          if(!pending.AsyncWaitHandle.WaitOne(10000))return 4;
          pipe.EndWaitForConnection(pending); pending.AsyncWaitHandle.Close();
          uint actual;
          if(!GetNamedPipeClientProcessId(pipe.SafePipeHandle.DangerousGetHandle(),out actual)||actual!=expected)return 4;
          phase="command_one"; Command(pipe,epoch,1);
          var body=Encoding.UTF8.GetBytes("{\"schema\":\"p6_r7_owned_recovery_reply_v1\",\"epoch\":\""+epoch+"\",\"type\":\"alive\",\"state\":\"live\",\"sequence\":1}");
          phase="reply_one"; foreach(byte b in BitConverter.GetBytes(body.Length)){pipe.WriteByte(b);pipe.Flush();Thread.Sleep(2);}
          foreach(byte b in body){pipe.WriteByte(b);pipe.Flush();Thread.Sleep(1);}
          phase="command_two"; Command(pipe,epoch,2);
        }
        Thread.Sleep(500);
        Console.WriteLine("{\"client_pid_verified\":true,\"partial_frame_written\":true,\"eof_emitted\":true}");
        return 0;
      } catch { Console.WriteLine("{\"fixture_failed\":true,\"phase\":\""+phase+"\"}");return 4; }
    }
  }
}
