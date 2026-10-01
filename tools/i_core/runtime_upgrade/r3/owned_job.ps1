# R3 derives only the reviewed R1 Job implementation; see PROVENANCE.json.
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Security.Cryptography;

public static class Mda2R3OwnedJob {
  [StructLayout(LayoutKind.Sequential)] struct STARTUPINFO {
    public uint cb; public IntPtr reserved, desktop, title;
    public uint x,y,xsize,ysize,xchars,ychars,fill,flags;
    public ushort show,reserved2; public IntPtr reservedPtr,input,output,error;
  }
  [StructLayout(LayoutKind.Sequential)] struct PROCESS_INFORMATION {
    public IntPtr process,thread; public uint pid,tid;
  }
  [StructLayout(LayoutKind.Sequential)] struct BASIC_LIMIT {
    public long processTime,jobTime; public uint flags;
    public UIntPtr minWorking,maxWorking; public uint activeLimit;
    public UIntPtr affinity; public uint priority,scheduling;
  }
  [StructLayout(LayoutKind.Sequential)] struct IO_COUNTERS {
    public ulong readOps,writeOps,otherOps,readBytes,writeBytes,otherBytes;
  }
  [StructLayout(LayoutKind.Sequential)] struct EXTENDED_LIMIT {
    public BASIC_LIMIT basic; public IO_COUNTERS io;
    public UIntPtr processMemory,jobMemory,peakProcess,peakJob;
  }
  [StructLayout(LayoutKind.Sequential)] struct ACCOUNTING {
    public long user,kernel,periodUser,periodKernel;
    public uint faults,total,active,terminated;
  }
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr security, string name);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int type,ref EXTENDED_LIMIT info,uint size);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job,int type,out ACCOUNTING info,uint size,IntPtr returned);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateProcess(string app,StringBuilder command,IntPtr processSecurity,IntPtr threadSecurity,bool inherit,uint flags,IntPtr environment,string cwd,ref STARTUPINFO startup,out PROCESS_INFORMATION info);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
  [DllImport("kernel32.dll", SetLastError=true)] static extern uint ResumeThread(IntPtr thread);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateJobObject(IntPtr job,uint code);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateProcess(IntPtr process,uint code);
  [DllImport("kernel32.dll", SetLastError=true)] static extern uint WaitForSingleObject(IntPtr handle,uint ms);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr process,out uint code);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenJobObject(uint access,bool inherit,string name);
  [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,uint pid);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetProcessTimes(IntPtr handle,out long created,out long exited,out long kernel,out long user);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool QueryFullProcessImageName(IntPtr process,uint flags,StringBuilder image,ref uint size);
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool DuplicateHandle(IntPtr sourceProcess,IntPtr sourceHandle,IntPtr targetProcess,out IntPtr targetHandle,uint access,bool inherit,uint options);
  [DllImport("kernel32.dll",SetLastError=true)] static extern uint GetFileType(IntPtr handle);
  public class Receipt {
    public string reason = "supervisor_error";
    public bool child_started, child_exit_confirmed, child_exit_code_confirmed, job_empty_confirmed, termination_requested;
    public uint child_pid, child_exit_code, total_processes;
    public bool guardian_started, guardian_exit_confirmed, guardian_exit_code_confirmed;
    public uint guardian_pid, guardian_exit_code;
    public int native_error;
  }
  static ACCOUNTING Accounting(IntPtr job) {
    ACCOUNTING value;
    if (!QueryInformationJobObject(job,1,out value,(uint)Marshal.SizeOf(typeof(ACCOUNTING)),IntPtr.Zero)) throw new Exception("job_query_failed");
    return value;
  }
  static string Quote(string s) {
    if (s.IndexOf('"') >= 0 || s.EndsWith("\\")) throw new Exception("invalid_fixed_argument");
    return "\"" + s + "\"";
  }
  static void WriteAtomic(string target,string value) {
    string pending=target+".pending";
    using(var file=new FileStream(pending,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {
      var bytes=Encoding.UTF8.GetBytes(value);file.Write(bytes,0,bytes.Length);file.Flush(true);
    }
    File.Move(pending,target);
  }
  static string ReadOptionalControl(string target) {
    try { return File.ReadAllText(target); }
    catch (FileNotFoundException) { return null; }
  }
  public static Receipt Run(string node,string entry,string root,string token,string mode,int timeout) {
    return Run(node,entry,root,token,mode,timeout,null,IntPtr.Zero);
  }
  public static Receipt Run(string node,string entry,string root,string token,string mode,int timeout,string guardian,IntPtr runtimeLock) {
    var result = new Receipt();
    var info = new PROCESS_INFORMATION();
    var guard = new PROCESS_INFORMATION();
    IntPtr job = IntPtr.Zero;
    bool assigned = false, owned = false;
    try {
      job = CreateJobObject(IntPtr.Zero,"Local\\MDA2R3-"+token);
      if (job == IntPtr.Zero) throw new Exception("job_create_failed");
      if (Marshal.GetLastWin32Error() == 183) throw new Exception("job_identity_exists");
      owned = true;
      var limits = new EXTENDED_LIMIT();
      limits.basic.flags = 0x2000; // KILL_ON_JOB_CLOSE; no breakaway permission.
      if (!SetInformationJobObject(job,9,ref limits,(uint)Marshal.SizeOf(typeof(EXTENDED_LIMIT)))) throw new Exception("job_limits_failed");
      if (File.Exists(Path.Combine(root,"stop"))) { result.reason = "cancelled_before_start"; return result; }
      var startup = new STARTUPINFO(); startup.cb = (uint)Marshal.SizeOf(typeof(STARTUPINFO));
      var executable = mode == "startup-failure" ? Path.Combine(root,"missing-node.exe") : node;
      var command = new StringBuilder(Quote(executable)+" "+Quote(entry)+" "+Quote(root)+" "+token+" "+mode);
      // Bind the actual process handle to the job before any user code can run.
      if (!CreateProcess(executable,command,IntPtr.Zero,IntPtr.Zero,false,0x08000004,IntPtr.Zero,root,ref startup,out info)) {
        result.native_error = Marshal.GetLastWin32Error(); result.reason = "child_start_failed"; return result;
      }
      result.child_started = true; result.child_pid = info.pid;
      if (!AssignProcessToJobObject(job,info.process)) throw new Exception("job_assign_failed");
      assigned = true;
      if (guardian != null) {
        string ps=Path.Combine(Environment.GetEnvironmentVariable("SystemRoot"),"System32\\WindowsPowerShell\\v1.0\\powershell.exe");
        var guardCommand=new StringBuilder(Quote(ps)+" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "+Quote(guardian)+" -ControlDirectory "+Quote(root)+" -RunId "+token);
        var guardStartup=new STARTUPINFO(); guardStartup.cb=(uint)Marshal.SizeOf(typeof(STARTUPINFO));
        // Guardian starts running immediately. Its bootstrap is bounded and checks
        // the original parent handle even when lock transfer never completes.
        if(!CreateProcess(ps,guardCommand,IntPtr.Zero,IntPtr.Zero,false,0x08000000,IntPtr.Zero,root,ref guardStartup,out guard)) throw new Exception("guardian_start_failed");
        result.guardian_started=true; result.guardian_pid=guard.pid;
#if R3_BARRIER_CREATED
        FixtureBarrier(root,token,"created",info.pid,guard.pid);
#endif
        IntPtr guardLock;
        if(runtimeLock==IntPtr.Zero || !DuplicateHandle(GetCurrentProcess(),runtimeLock,guard.process,out guardLock,0,false,2)) throw new Exception("guardian_lock_duplicate_failed");
#if R3_BARRIER_DUPLICATED
        FixtureBarrier(root,token,"duplicated",info.pid,guard.pid);
#endif
        WriteAtomic(Path.Combine(root,"guardian-lock.id"),guardLock.ToInt64().ToString());
#if R3_BARRIER_PUBLISHED
        FixtureBarrier(root,token,"published",info.pid,guard.pid);
#endif
        var guardClock=Stopwatch.StartNew();
        while(!File.Exists(Path.Combine(root,"guardian-ready.json")) && WaitForSingleObject(guard.process,0)!=0 && guardClock.ElapsedMilliseconds<15000) Thread.Sleep(25);
        if(!File.Exists(Path.Combine(root,"guardian-ready.json")) || WaitForSingleObject(guard.process,0)==0
          || File.ReadAllText(Path.Combine(root,"guardian-ready.json"))!="{\"run_id\":\""+token+"\",\"pid\":"+guard.pid+"}") throw new Exception("guardian_ready_unconfirmed");
      }
      if (ResumeThread(info.thread) == 0xffffffff) throw new Exception("child_resume_failed");
      var clock = Stopwatch.StartNew();
      long stopAt = -1;
      string stopValue = token;
      string closeValue = null;
      if (timeout == 0) {
        string manifest = File.ReadAllText(Path.Combine(root,"manifest.id"));
        using(var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(File.ReadAllText(Path.Combine(root,"stop.key"))))) {
          stopValue = BitConverter.ToString(hmac.ComputeHash(Encoding.UTF8.GetBytes(token+"|"+manifest+"|stop"))).Replace("-","").ToLowerInvariant();
          closeValue = BitConverter.ToString(hmac.ComputeHash(Encoding.UTF8.GetBytes(token+"|"+manifest+"|close"))).Replace("-","").ToLowerInvariant();
        }
      }
      while (true) {
        if(guard.process!=IntPtr.Zero && WaitForSingleObject(guard.process,0)==0 && Accounting(job).active!=0) throw new Exception("guardian_lost");
        if (stopAt < 0 && ReadOptionalControl(Path.Combine(root,"stop")) == stopValue) { result.reason = "cancelled"; stopAt = clock.ElapsedMilliseconds; }
        if (stopAt < 0 && closeValue != null && ReadOptionalControl(Path.Combine(root,"close")) == closeValue) { result.reason = "close_requested"; stopAt = clock.ElapsedMilliseconds; }
        if (WaitForSingleObject(info.process,0) == 0) {
          var descendants = Stopwatch.StartNew();
          while (Accounting(job).active != 0 && descendants.ElapsedMilliseconds < 1000) Thread.Sleep(25);
          if (stopAt < 0 || result.reason == "close_requested") result.reason = Accounting(job).active == 0 ? "completed" : "descendants_remaining";
          break;
        }
        if (timeout > 0 && stopAt < 0 && clock.ElapsedMilliseconds >= timeout) { result.reason = "timeout"; stopAt = clock.ElapsedMilliseconds; File.WriteAllText(Path.Combine(root,"stop"), token); }
        if (stopAt >= 0 && clock.ElapsedMilliseconds - stopAt >= 3000) { if(result.reason == "close_requested") result.reason = "close_timeout"; break; }
        Thread.Sleep(25);
      }
    } catch (Exception ex) { result.reason = ex.Message; result.native_error = Marshal.GetLastWin32Error(); }
    finally {
      try {
        if (info.process != IntPtr.Zero && !assigned && WaitForSingleObject(info.process,0) != 0) {
          result.termination_requested = true; TerminateProcess(info.process,125);
        }
        if (job != IntPtr.Zero && owned) {
          var state = Accounting(job);
          if (state.active != 0) { result.termination_requested = true; TerminateJobObject(job,124); }
          var clock = Stopwatch.StartNew();
          while ((state = Accounting(job)).active != 0 && clock.ElapsedMilliseconds < 5000) Thread.Sleep(25);
          result.job_empty_confirmed = state.active == 0;
          result.total_processes = state.total;
        }
        result.child_exit_confirmed = info.process == IntPtr.Zero || WaitForSingleObject(info.process,5000) == 0;
        uint exitCode;
        result.child_exit_code_confirmed = info.process == IntPtr.Zero;
        if (info.process != IntPtr.Zero && result.child_exit_confirmed && GetExitCodeProcess(info.process,out exitCode)) {
          result.child_exit_code = exitCode; result.child_exit_code_confirmed = true;
        }
        if(guard.process!=IntPtr.Zero) {
          result.guardian_exit_confirmed=WaitForSingleObject(guard.process,10000)==0;
          if(!result.guardian_exit_confirmed) { TerminateProcess(guard.process,125); result.guardian_exit_confirmed=WaitForSingleObject(guard.process,5000)==0; result.termination_requested=true; }
          if(result.guardian_exit_confirmed && GetExitCodeProcess(guard.process,out exitCode)) { result.guardian_exit_code_confirmed=true;result.guardian_exit_code=exitCode; }
        }
      } catch { result.job_empty_confirmed = false; }
      if (info.thread != IntPtr.Zero) CloseHandle(info.thread);
      if (info.process != IntPtr.Zero) CloseHandle(info.process);
      if (job != IntPtr.Zero) CloseHandle(job);
      if (guard.thread != IntPtr.Zero) CloseHandle(guard.thread);
      if (guard.process != IntPtr.Zero) CloseHandle(guard.process);
    }
    return result;
  }
  public class GuardReceipt { public bool parent_exit_observed,job_empty_confirmed; public string reason="guardian_error"; public uint total_processes; }
  public static GuardReceipt Guard(string root,string token,uint parentPid,string parentTicks) {
    var result=new GuardReceipt(); IntPtr job=IntPtr.Zero,parent=IntPtr.Zero,runtimeLock=IntPtr.Zero;
    try {
      job=OpenJobObject(0x001F003F,false,"Local\\MDA2R3-"+token);
      if(job==IntPtr.Zero) throw new Exception("guardian_job_unavailable");
      parent=OpenProcess(0x101000,false,parentPid);
      long created,exited,kernel,user; uint size=4096;var image=new StringBuilder(4096);
      string expected=Path.Combine(Environment.GetEnvironmentVariable("SystemRoot"),"System32\\WindowsPowerShell\\v1.0\\powershell.exe");
      if(parent==IntPtr.Zero || !GetProcessTimes(parent,out created,out exited,out kernel,out user) || DateTime.FromFileTimeUtc(created).Ticks.ToString()!=parentTicks || !QueryFullProcessImageName(parent,0,image,ref size) || !String.Equals(image.ToString(),expected,StringComparison.OrdinalIgnoreCase)) throw new Exception("guardian_parent_identity_mismatch");
      var bootstrap=Stopwatch.StartNew();
      string lockFile=Path.Combine(root,"guardian-lock.id");
      while(!File.Exists(lockFile) && WaitForSingleObject(parent,0)!=0 && bootstrap.ElapsedMilliseconds<15000) Thread.Sleep(25);
      if(!File.Exists(lockFile)) throw new Exception("guardian_lock_transfer_incomplete");
      runtimeLock=new IntPtr(Int64.Parse(File.ReadAllText(lockFile)));
      if(GetFileType(runtimeLock)!=1) throw new Exception("guardian_lock_handle_invalid");
      WriteAtomic(Path.Combine(root,"guardian-ready.json"),"{\"run_id\":\""+token+"\",\"pid\":"+Process.GetCurrentProcess().Id+"}");
      while(WaitForSingleObject(parent,0)!=0 && Accounting(job).active!=0) Thread.Sleep(25);
      result.parent_exit_observed=WaitForSingleObject(parent,0)==0;
      result.reason=result.parent_exit_observed?"parent_exit_reaped":"job_completed";
      if(result.parent_exit_observed && Accounting(job).active!=0) TerminateJobObject(job,137);
      var clock=Stopwatch.StartNew();ACCOUNTING state;
      while((state=Accounting(job)).active!=0 && clock.ElapsedMilliseconds<5000) Thread.Sleep(25);
      result.job_empty_confirmed=state.active==0; result.total_processes=state.total;
    } catch(Exception ex) {
      result.reason=ex.Message;
      result.parent_exit_observed=parent==IntPtr.Zero || WaitForSingleObject(parent,0)==0;
      // A failed bootstrap can only reap this already-bound, randomly named Job.
      // A transferred but unpublished handle is also closed when this process exits.
      if(job!=IntPtr.Zero) {
        TerminateJobObject(job,137);var clock=Stopwatch.StartNew();ACCOUNTING state;
        while((state=Accounting(job)).active!=0 && clock.ElapsedMilliseconds<5000) Thread.Sleep(25);
        result.job_empty_confirmed=state.active==0;result.total_processes=state.total;
      }
    }
    finally { if(runtimeLock!=IntPtr.Zero) CloseHandle(runtimeLock); if(parent!=IntPtr.Zero) CloseHandle(parent); if(job!=IntPtr.Zero) CloseHandle(job); }
    return result;
  }
#if R3_BARRIER_CREATED || R3_BARRIER_DUPLICATED || R3_BARRIER_PUBLISHED
  // Only compiled in explicitly re-manifested synthetic fixture packages.
  static void FixtureBarrier(string root,string token,string stage,uint child,uint guardian) {
    WriteAtomic(Path.Combine(root,"startup-barrier.json"),"{\"token\":\""+token+"\",\"stage\":\""+stage+"\",\"pid\":"+child+",\"guardian_pid\":"+guardian+"}");
    var clock=Stopwatch.StartNew();
    while(clock.ElapsedMilliseconds<15000) Thread.Sleep(25);
    throw new Exception("fixture_barrier_expired");
  }
#endif
}
'@
