# Derived from frozen R2 owned_job.ps1; see M3 SUPERVISION.md for source hash and changes.
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class Mda2M3OwnedJob {
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
  public class Receipt {
    public string reason = "supervisor_error";
    public bool child_started, child_exit_confirmed, child_exit_code_confirmed, job_empty_confirmed, termination_requested, parent_binding_verified;
    public uint child_pid, child_exit_code, total_processes;
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
  public static Receipt Run(string node,string entry,string root,string token,string mode,int timeout,int parentPid,string parentTicks,string parentImage) {
    var result = new Receipt();
    var info = new PROCESS_INFORMATION();
    IntPtr job = IntPtr.Zero;
    bool assigned = false; Process parent = null; IntPtr parentHandle = IntPtr.Zero;
    try {
      parent = Process.GetProcessById(parentPid); parentHandle = parent.Handle;
      if (parent.StartTime.ToUniversalTime().Ticks.ToString(System.Globalization.CultureInfo.InvariantCulture) != parentTicks
          || !String.Equals(Path.GetFullPath(parent.MainModule.FileName), Path.GetFullPath(parentImage), StringComparison.OrdinalIgnoreCase)
          || !String.Equals(Path.GetFullPath(parentImage), Path.GetFullPath(node), StringComparison.OrdinalIgnoreCase)) throw new Exception("parent_identity_mismatch");
      result.parent_binding_verified = true;
      job = CreateJobObject(IntPtr.Zero,null);
      if (job == IntPtr.Zero) throw new Exception("job_create_failed");
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
      if (ResumeThread(info.thread) == 0xffffffff) throw new Exception("child_resume_failed");
      var clock = Stopwatch.StartNew();
      long stopAt = -1;
      while (true) {
        if (WaitForSingleObject(parentHandle,0) == 0) { result.reason = "parent_exited"; break; }
        if (stopAt < 0 && File.Exists(Path.Combine(root,"stop")) && File.ReadAllText(Path.Combine(root,"stop")) == token) { result.reason = "cancelled"; stopAt = clock.ElapsedMilliseconds; }
        if (WaitForSingleObject(info.process,0) == 0) { if (stopAt < 0) result.reason = Accounting(job).active == 0 ? "completed" : "descendants_remaining"; break; }
        if (stopAt < 0 && clock.ElapsedMilliseconds >= timeout) { result.reason = "timeout"; stopAt = clock.ElapsedMilliseconds; File.WriteAllText(Path.Combine(root,"stop"), token); }
        if (stopAt >= 0 && clock.ElapsedMilliseconds - stopAt >= 3000) break;
        Thread.Sleep(25);
      }
    } catch (Exception ex) { result.reason = ex.Message; result.native_error = Marshal.GetLastWin32Error(); }
    finally {
      try {
        if (info.process != IntPtr.Zero && !assigned && WaitForSingleObject(info.process,0) != 0) {
          result.termination_requested = true; TerminateProcess(info.process,125);
        }
        if (job != IntPtr.Zero) {
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
      } catch { result.job_empty_confirmed = false; }
      if (info.thread != IntPtr.Zero) CloseHandle(info.thread);
      if (info.process != IntPtr.Zero) CloseHandle(info.process);
      if (job != IntPtr.Zero) CloseHandle(job);
      if (parent != null) parent.Dispose();
    }
    return result;
  }
}
'@
