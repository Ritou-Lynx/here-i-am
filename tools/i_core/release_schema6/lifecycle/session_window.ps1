# Loaded only after login_schema6.ps1 verifies the fixed release and ACL tree.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Web.Extensions
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing,System.Web.Extensions -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

public sealed class Schema6SessionJob : IDisposable {
  [StructLayout(LayoutKind.Sequential)] struct Startup { public uint cb; public IntPtr reserved,desktop,title; public uint x,y,cx,cy,charsX,charsY,fill,flags; public ushort show,reserved2; public IntPtr reservedPtr,input,output,error; }
  [StructLayout(LayoutKind.Sequential)] struct ProcessInfo { public IntPtr process,thread; public uint pid,tid; }
  [StructLayout(LayoutKind.Sequential)] struct BasicLimit { public long processTime,jobTime; public uint flags; public UIntPtr min,max; public uint activeLimit; public UIntPtr affinity; public uint priority,scheduling; }
  [StructLayout(LayoutKind.Sequential)] struct Io { public ulong readOps,writeOps,otherOps,readBytes,writeBytes,otherBytes; }
  [StructLayout(LayoutKind.Sequential)] struct Limits { public BasicLimit basic; public Io io; public UIntPtr processMemory,jobMemory,peakProcess,peakJob; }
  [StructLayout(LayoutKind.Sequential)] struct Accounting { public long user,kernel,periodUser,periodKernel; public uint faults,total,active,terminated; }
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr security,string name);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int type,ref Limits info,uint length);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job,int type,out Accounting info,uint length,IntPtr returned);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateProcess(string app,StringBuilder cmd,IntPtr ps,IntPtr ts,bool inherit,uint flags,IntPtr env,string cwd,ref Startup startup,out ProcessInfo info);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
  [DllImport("kernel32.dll",SetLastError=true)] static extern uint ResumeThread(IntPtr thread);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool TerminateProcess(IntPtr process,uint code);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool TerminateJobObject(IntPtr job,uint code);
  [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr handle,uint ms);
  [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr handle,out uint code);
  [DllImport("kernel32.dll")] static extern bool GetProcessTimes(IntPtr handle,out long created,out long exited,out long kernel,out long user);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  IntPtr job,process; public readonly uint Pid; public readonly string StartedTicks;
  public static string Quote(string value) {
    if(value == null || value.IndexOf('"') >= 0 || value.IndexOf('\r') >= 0 || value.IndexOf('\n') >= 0 || value.EndsWith("\\")) throw new InvalidOperationException("session_argument_rejected");
    return "\""+value+"\"";
  }
  public Schema6SessionJob(string executable,string[] args,string cwd) {
    ProcessInfo info=new ProcessInfo(); bool assigned=false;
    try {
      job=CreateJobObject(IntPtr.Zero,null); if(job==IntPtr.Zero)throw new InvalidOperationException("session_job_create_failed");
      Limits limits=new Limits();limits.basic.flags=0x2000;
      if(!SetInformationJobObject(job,9,ref limits,(uint)Marshal.SizeOf(typeof(Limits))))throw new InvalidOperationException("session_job_limit_failed");
      StringBuilder command=new StringBuilder(Quote(executable));foreach(string arg in args)command.Append(" "+Quote(arg));
      Startup startup=new Startup();startup.cb=(uint)Marshal.SizeOf(typeof(Startup));
      if(!CreateProcess(executable,command,IntPtr.Zero,IntPtr.Zero,false,0x08000004,IntPtr.Zero,cwd,ref startup,out info))throw new InvalidOperationException("session_child_create_failed");
      process=info.process;Pid=info.pid;
      long created,exited,kernel,user;
      if(!GetProcessTimes(process,out created,out exited,out kernel,out user))throw new InvalidOperationException("session_child_identity_failed");
      StartedTicks=DateTime.FromFileTimeUtc(created).Ticks.ToString();
      if(!AssignProcessToJobObject(job,process))throw new InvalidOperationException("session_job_assign_failed");
      assigned=true;
      if(ResumeThread(info.thread)==0xffffffff)throw new InvalidOperationException("session_child_resume_failed");
    } catch {
      if(info.process!=IntPtr.Zero && !assigned)TerminateProcess(info.process,125);
      Dispose();throw;
    } finally {if(info.thread!=IntPtr.Zero)CloseHandle(info.thread);}
  }
  public bool Exited {get {return process!=IntPtr.Zero && WaitForSingleObject(process,0)==0;}}
  public bool Empty {get {Accounting a;if(job==IntPtr.Zero || !QueryInformationJobObject(job,1,out a,(uint)Marshal.SizeOf(typeof(Accounting)),IntPtr.Zero))throw new InvalidOperationException("session_job_query_failed");return a.active==0;}}
  public uint ExitCode {get {uint value;if(!Exited || !GetExitCodeProcess(process,out value))throw new InvalidOperationException("session_exit_unconfirmed");return value;}}
  public bool WaitEmpty(int milliseconds) {Stopwatch watch=Stopwatch.StartNew();do{if(Exited&&Empty)return true;Thread.Sleep(25);}while(watch.ElapsedMilliseconds<milliseconds);return Exited&&Empty;}
  public bool TerminateAndWait(int milliseconds) {if(job==IntPtr.Zero)return false;if(!TerminateJobObject(job,124))throw new InvalidOperationException("session_job_terminate_failed");return WaitEmpty(milliseconds);}
  public void Dispose() {
    if(job!=IntPtr.Zero){TerminateJobObject(job,124);CloseHandle(job);job=IntPtr.Zero;}
    if(process!=IntPtr.Zero){WaitForSingleObject(process,5000);CloseHandle(process);process=IntPtr.Zero;}
  }
}

public sealed class Schema6SessionWindow : Form {
  [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool ShutdownBlockReasonCreate(IntPtr window,string reason);
  [DllImport("user32.dll",SetLastError=true)] static extern bool ShutdownBlockReasonDestroy(IntPtr window);
  readonly string ps,release,manifest,state,session,configuration;
  string control;
  readonly string[] backupArgs;
  readonly int backupSeconds;
  bool initialize;
  readonly int corePort;
  readonly ManualResetEvent finished=new ManualResetEvent(false);
  readonly object gate=new object();
  Schema6SessionJob core,backup;
  System.Windows.Forms.Timer timer;
  DateTime nextBackup=DateTime.MinValue;
  int closing; bool started,clean,shutdownRequested,shutdownCancelled,exitRequested,forcedTimeout;
  bool currentReady,recoveryPending,recoveryAttempted;
  DateTime readySince,restartAfter;
  string reason="running";
  static readonly JavaScriptSerializer json=new JavaScriptSerializer();
  public Schema6SessionWindow(string powerShell,string releaseRoot,string manifestHash,string stateRoot,string controlRoot,string sessionRoot,string config,bool initializeEmpty,string[] schedulerArgs,int interval,int port) {
    ps=powerShell;release=releaseRoot;manifest=manifestHash;state=stateRoot;control=controlRoot;session=sessionRoot;configuration=config;initialize=initializeEmpty;backupArgs=schedulerArgs;backupSeconds=interval;corePort=port;
    ShowInTaskbar=false;FormBorderStyle=FormBorderStyle.None;Text="Here I am session lifecycle";
  }
  protected override void SetVisibleCore(bool value) {if(!IsHandleCreated)CreateHandle();base.SetVisibleCore(false);}
  [StructLayout(LayoutKind.Sequential)] struct FileInfo {public uint attributes; public System.Runtime.InteropServices.ComTypes.FILETIME creation,access,write;public uint volume,high,low,links,indexHigh,indexLow;}
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(Microsoft.Win32.SafeHandles.SafeFileHandle handle,out FileInfo info);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(Microsoft.Win32.SafeHandles.SafeFileHandle handle,StringBuilder path,uint length,uint flags);
  static void Protected(string filename,bool root) {
    if(Path.GetFullPath(filename)!=filename || filename.Substring(2).Contains(":"))throw new InvalidOperationException("session_canonical_path_required");
    for(string current=filename;current!=null;current=Path.GetDirectoryName(current))if((File.GetAttributes(current)&FileAttributes.ReparsePoint)!=0)throw new InvalidOperationException("session_linked_path_rejected");
    bool directory=Directory.Exists(filename);FileSystemSecurity acl=directory?(FileSystemSecurity)Directory.GetAccessControl(filename):File.GetAccessControl(filename);
    string owner=WindowsIdentity.GetCurrent().User.Value;
    if(acl.GetOwner(typeof(SecurityIdentifier)).Value!=owner || (root&&!acl.AreAccessRulesProtected))throw new InvalidOperationException("session_protected_owner_required");
    bool own=false;
    foreach(FileSystemAccessRule rule in acl.GetAccessRules(true,true,typeof(SecurityIdentifier)))if(rule.AccessControlType==AccessControlType.Allow){string id=rule.IdentityReference.Value;if(id!=owner&&id!="S-1-5-18"&&id!="S-1-5-32-544")throw new InvalidOperationException("session_protected_acl_required");if(id==owner&&(rule.FileSystemRights&FileSystemRights.FullControl)==FileSystemRights.FullControl)own=true;}
    if(!own)throw new InvalidOperationException("session_user_control_required");
  }
  static string ReadProtected(string filename) {
    Protected(filename,false);
    using(FileStream file=new FileStream(filename,FileMode.Open,FileAccess.Read,FileShare.Read)) {
      FileInfo info;if(!GetFileInformationByHandle(file.SafeFileHandle,out info)||info.links!=1)throw new InvalidOperationException("session_file_link_rejected");
      StringBuilder canonical=new StringBuilder(32768);uint size=GetFinalPathNameByHandle(file.SafeFileHandle,canonical,32768,0);
      if(size==0||size>=32768||!canonical.ToString().Equals("\\\\?\\"+filename,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("session_file_alias_rejected");
      if(file.Length>1024*1024)throw new InvalidOperationException("session_input_size_rejected");
      using(StreamReader reader=new StreamReader(file,Encoding.UTF8))return reader.ReadToEnd();
    }
  }
  static Dictionary<string,object> Read(string filename) {string text=ReadProtected(filename);lock(json)return json.Deserialize<Dictionary<string,object>>(text);}
  static bool Flag(Dictionary<string,object> value,string name){return value.ContainsKey(name)&&value[name] is bool&&(bool)value[name];}
  static bool Equal(Dictionary<string,object> value,string name,string expected){return value.ContainsKey(name)&&Convert.ToString(value[name])==expected;}
  static void WriteNew(string filename,object value) {
    string text;lock(json)text=json.Serialize(value);
    string pending=filename+"."+Guid.NewGuid().ToString("N")+".pending";
    try{using(FileStream file=new FileStream(pending,FileMode.CreateNew,FileAccess.Write,FileShare.None)){byte[] data=Encoding.UTF8.GetBytes(text);file.Write(data,0,data.Length);file.Flush(true);}File.Move(pending,filename);}
    finally{if(File.Exists(pending))File.Delete(pending);}
  }
  protected override void OnHandleCreated(EventArgs e) {
    base.OnHandleCreated(e);
    if(!ShutdownBlockReasonCreate(Handle,"Here I am is closing its local data safely."))throw new InvalidOperationException("shutdown_block_reason_failed");
    // The hidden top-level HWND and shutdown hook exist before any Core writer.
    WriteNew(Path.Combine(session,"session-window.json"),new {pid=Process.GetCurrentProcess().Id,hwnd=Handle.ToInt64(),manifest_sha256=manifest,hook_ready=true});
    timer=new System.Windows.Forms.Timer();timer.Interval=100;timer.Tick+=Tick;timer.Start();
  }
  void Tick(object sender,EventArgs args) {
    try {
      lock(gate) {
        if(finished.WaitOne(0)) {
          if((shutdownCancelled || recoveryPending) && !exitRequested) {
            if(DateTime.UtcNow<restartAfter)return;
            if(core!=null){core.Dispose();core=null;}if(backup!=null){backup.Dispose();backup=null;}
            control=Path.Combine(session,"control-"+Guid.NewGuid().ToString("N"));
            var acl=Directory.GetAccessControl(session);acl.SetAccessRuleProtection(true,true);
            Directory.CreateDirectory(control,acl);
            finished.Reset();Interlocked.Exchange(ref closing,0);started=false;clean=false;shutdownRequested=false;shutdownCancelled=false;initialize=false;currentReady=false;recoveryPending=false;nextBackup=DateTime.MinValue;
          } else if(exitRequested){Close();return;} else return;
        }
        if(Volatile.Read(ref closing)!=0)return;
        if(!started) {
          started=true;
          List<string> arguments=new List<string>(new string[]{"-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",Path.Combine(release,"tools/i_core/release_schema6/lifecycle/start_schema6.ps1"),"-ManifestSha256",manifest,"-Start","-StateDirectory",state,"-ControlDirectory",control,"-ConfigurationFile",configuration,"-CorePort",corePort.ToString()});
          if(initialize)arguments.Add("-InitializeEmpty");
          core=new Schema6SessionJob(ps,arguments.ToArray(),session);
        }
        if(!currentReady && File.Exists(Path.Combine(control,"ready.json"))) {
          Dictionary<string,object> ready=Read(Path.Combine(control,"ready.json")),launch=Read(Path.Combine(control,"launch.json"));
          if(!LaunchBound(launch,core)||!Equal(ready,"token",Convert.ToString(launch["token"]))||!Equal(ready,"manifest_sha256",manifest))throw new InvalidOperationException("session_ready_binding_mismatch");
          currentReady=true;readySince=DateTime.UtcNow;
        }
        if(currentReady && !core.Exited && DateTime.UtcNow-readySince>TimeSpan.FromSeconds(30))recoveryAttempted=false;
        if(core.Exited){
          if(!core.Empty)return;
          if(currentReady&&!recoveryAttempted&&!shutdownRequested){recoveryAttempted=true;recoveryPending=true;restartAfter=DateTime.UtcNow.AddSeconds(1);reason="owned_core_exit_recovery_pending";}
          else{reason=currentReady?"session_recovery_retry_exhausted":"session_start_gate_failed";exitRequested=true;}
          BeginClose();return;
        }
        if(backup!=null && backup.Exited && backup.Empty){
          uint code=backup.ExitCode;backup.Dispose();backup=null;nextBackup=DateTime.UtcNow.AddSeconds(backupSeconds);
          BackupStatus(code==0?"backup_completed":"backup_worker_failed",code==0);
        }
        if(backup==null && backupArgs.Length>0 && DateTime.UtcNow>=nextBackup && currentReady) {
          try{backup=new Schema6SessionJob(ps,backupArgs,session);}
          catch{if(backup!=null){backup.Dispose();backup=null;}nextBackup=DateTime.UtcNow.AddSeconds(backupSeconds);BackupStatus("backup_launch_failed",false);}
        }
      }
    } catch {reason="session_start_or_worker_failed";exitRequested=true;BeginClose();}
  }
  void BackupStatus(string status,bool success) {
    try{WriteNew(Path.Combine(session,"backup-status-"+Guid.NewGuid().ToString("N")+".json"),new {status=status,success=success,next_attempt_utc=nextBackup.ToString("o")});}catch{}
  }
  static string CloseFailure(Exception error) {
    switch(error.Message) {
      case "backup_job_empty_unconfirmed":case "core_close_timeout":case "core_close_failed":
      case "session_clean_receipt_unconfirmed":case "session_clean_marker_unconfirmed":
      case "session_launch_binding_mismatch":case "session_stop_binding_invalid":case "session_existing_close_mismatch":return error.Message;
      default:return "session_close_internal_rejected";
    }
  }
  void BeginClose() {
    if(Interlocked.Exchange(ref closing,1)!=0)return;
    ThreadPool.QueueUserWorkItem(delegate {
      Stopwatch budget=Stopwatch.StartNew();
      try {
        Schema6SessionJob currentCore,currentBackup;
        lock(gate){currentCore=core;currentBackup=backup;}
        // Stop dispatch first; any backup descendants must finish before Core close.
        if(currentBackup!=null && !currentBackup.WaitEmpty(5000) && !currentBackup.TerminateAndWait(1000))throw new InvalidOperationException("backup_job_empty_unconfirmed");
        if(currentCore==null){clean=true;reason="closed_before_start";return;}
        Dictionary<string,object> launch=null;
        while(budget.ElapsedMilliseconds<30000) {
          try {launch=Read(Path.Combine(control,"launch.json"));break;}catch(IOException){Thread.Sleep(25);}
          if(currentCore.Exited)break;
        }
        if(launch!=null && !currentCore.Exited)RequestClose(launch,currentCore);
        if(!currentCore.WaitEmpty(Remaining(budget)))throw new InvalidOperationException("core_close_timeout");
        if(currentCore.ExitCode!=0)throw new InvalidOperationException("core_close_failed");
        Dictionary<string,object> receipt=Read(Path.Combine(control,"supervisor.json"));
        Dictionary<string,object> result=(Dictionary<string,object>)receipt["result"];
        if(launch==null || !LaunchBound(launch,currentCore) || !Equal(receipt,"token",Convert.ToString(launch["token"])) || !Equal(receipt,"manifest_sha256",manifest) || !Flag(receipt,"lock_released_confirmed") || !Flag(receipt,"child_receipt_confirmed") || !Flag(receipt,"guardian_receipt_confirmed") || !Flag(result,"job_empty_confirmed") || !Flag(result,"child_exit_confirmed") || !Flag(result,"child_exit_code_confirmed") || !Flag(result,"guardian_exit_confirmed") || !Flag(result,"guardian_exit_code_confirmed") || Convert.ToInt32(result["child_exit_code"])!=0 || Convert.ToInt32(result["guardian_exit_code"])!=0 || Flag(result,"termination_requested"))throw new InvalidOperationException("session_clean_receipt_unconfirmed");
        Dictionary<string,object> marker=Read(Path.Combine(state,"s6-lifecycle.json"));
        if(!Equal(marker,"phase","clean_closed")||!Equal(marker,"token",Convert.ToString(launch["token"]))||!Equal(marker,"manifest_sha256",manifest))throw new InvalidOperationException("session_clean_marker_unconfirmed");
        Protected(Path.Combine(state,"shortcut-mail-relay.runtime.lock"),false);
        using(FileStream probe=new FileStream(Path.Combine(state,"shortcut-mail-relay.runtime.lock"),FileMode.Open,FileAccess.ReadWrite,FileShare.None)){}
        clean=!forcedTimeout;reason=forcedTimeout?"session_shutdown_timeout":"clean_closed";
      } catch(Exception error) {if(reason!="session_start_gate_failed"&&reason!="session_recovery_retry_exhausted")reason=forcedTimeout?"session_shutdown_timeout":CloseFailure(error);clean=false;}
      finally {
        try{WriteNew(Path.Combine(control,"session-close.json"),new {clean_closed=clean,reason=reason,manifest_sha256=manifest,completion_confirmed=clean});}
        catch{clean=false;reason="session_receipt_write_failed";}
        finally{finished.Set();}
      }
    });
  }
  static int Remaining(Stopwatch budget){return Math.Max(0,30000-(int)budget.ElapsedMilliseconds);}
  bool LaunchBound(Dictionary<string,object> launch,Schema6SessionJob currentCore){return Equal(launch,"manifest_sha256",manifest)&&Equal(launch,"state",state)&&Equal(launch,"release",release)&&Equal(launch,"parent_pid",currentCore.Pid.ToString())&&Equal(launch,"parent_started_ticks",currentCore.StartedTicks);}
  void RequestClose(Dictionary<string,object> launch,Schema6SessionJob currentCore) {
    Protected(control,true);
    if(!LaunchBound(launch,currentCore))throw new InvalidOperationException("session_launch_binding_mismatch");
    string token=Convert.ToString(launch["token"]),key=ReadProtected(Path.Combine(control,"stop.key"));
    if(!System.Text.RegularExpressions.Regex.IsMatch(token,"^[a-f0-9]{64}$")||!System.Text.RegularExpressions.Regex.IsMatch(key,"^[a-f0-9]{64}$"))throw new InvalidOperationException("session_stop_binding_invalid");
    string mac;using(HMACSHA256 hmac=new HMACSHA256(Encoding.UTF8.GetBytes(key)))mac=BitConverter.ToString(hmac.ComputeHash(Encoding.UTF8.GetBytes(token+"|"+manifest+"|close"))).Replace("-","").ToLowerInvariant();
    string target=Path.Combine(control,"close");
    if(File.Exists(target)){if(ReadProtected(target)!=mac)throw new InvalidOperationException("session_existing_close_mismatch");return;}
    string temporary=Path.Combine(control,"session-close-"+Guid.NewGuid().ToString("N")+".tmp");
    using(FileStream file=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None)){byte[] data=Encoding.UTF8.GetBytes(mac);file.Write(data,0,data.Length);file.Flush(true);}File.Move(temporary,target);
  }
  protected override void WndProc(ref Message message) {
    if(message.Msg==0x0011){shutdownRequested=true;BeginClose();message.Result=new IntPtr(1);return;}
    if(message.Msg==0x0016){
      if(message.WParam!=IntPtr.Zero){exitRequested=true;BeginClose();if(!finished.WaitOne(30000)){forcedTimeout=true;clean=false;reason="session_shutdown_timeout";}BeginInvoke((Action)delegate{Close();});}
      else if(shutdownRequested){shutdownCancelled=true;}
      message.Result=IntPtr.Zero;return;
    }
    if(message.Msg==0x0010 && !finished.WaitOne(0) && !forcedTimeout){exitRequested=true;BeginClose();message.Result=IntPtr.Zero;return;}
    base.WndProc(ref message);
  }
  protected override void OnFormClosed(FormClosedEventArgs e) {
    if(timer!=null)timer.Dispose();
    bool coreEmpty=core==null,backupEmpty=backup==null;
    lock(gate){
      if(backup!=null){try{backupEmpty=backup.TerminateAndWait(5000);}finally{backup.Dispose();}}
      if(core!=null){try{coreEmpty=core.TerminateAndWait(5000);}finally{core.Dispose();}}
    }
    try{WriteNew(Path.Combine(session,"session-exit.json"),new {clean_closed=clean&&!forcedTimeout,core_job_empty_confirmed=coreEmpty,backup_job_empty_confirmed=backupEmpty,forced_timeout=forcedTimeout,termination_requested=!clean,reason=reason});}catch{clean=false;}
    ShutdownBlockReasonDestroy(Handle);base.OnFormClosed(e);
  }
  public static int Run(string powerShell,string release,string manifest,string state,string control,string session,string configuration,bool initialize,string[] backupArguments,int interval,int port) {
    using(Schema6SessionWindow window=new Schema6SessionWindow(powerShell,release,manifest,state,control,session,configuration,initialize,backupArguments,interval,port)) {Application.Run(window);return window.clean?0:1;}
  }
}
'@
