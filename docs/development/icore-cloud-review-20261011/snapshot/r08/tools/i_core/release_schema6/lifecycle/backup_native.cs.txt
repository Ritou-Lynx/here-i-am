using System;
using System.IO;
using System.Text;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Threading;
using Microsoft.Win32.SafeHandles;

// No business entry point. Loaded only from an inventory/hash-locked release.
public static class BackupStrictJson {
 sealed class Reader {
  readonly string text; int pos; public Reader(byte[] bytes){text=new UTF8Encoding(false,true).GetString(bytes);if(text.Length>0&&text[0]=='\uFEFF')throw new IOException("json_bom");}
  void Space(){while(pos<text.Length&&(text[pos]==' '||text[pos]=='\t'||text[pos]=='\r'||text[pos]=='\n'))pos++;}
  char Next(){if(pos>=text.Length)throw new IOException("json_truncated");return text[pos++];}
  public object Parse(){object v=Value(0);Space();if(pos!=text.Length)throw new IOException("json_trailing");return v;}
  object Value(int depth){
   if(depth>16)throw new IOException("json_depth");Space();char c=Next();
   if(c=='{'){var d=new Dictionary<string,object>(StringComparer.Ordinal);Space();if(pos<text.Length&&text[pos]=='}'){pos++;return d;}while(true){Space();if(Next()!='"')throw new IOException("json_key");string k=String();if(d.ContainsKey(k))throw new IOException("json_duplicate");Space();if(Next()!=':')throw new IOException("json_colon");d.Add(k,Value(depth+1));Space();c=Next();if(c=='}')return d;if(c!=',')throw new IOException("json_separator");}}
   if(c=='['){var a=new List<object>();Space();if(pos<text.Length&&text[pos]==']'){pos++;return a;}while(true){a.Add(Value(depth+1));Space();c=Next();if(c==']')return a;if(c!=',')throw new IOException("json_separator");}}
   if(c=='"')return String();if(c=='t'){Literal("rue");return true;}if(c=='f'){Literal("alse");return false;}if(c=='n'){Literal("ull");return null;}
   int start=pos-1;if(c=='-'){c=Next();}if(c<'0'||c>'9')throw new IOException("json_number");
   if(c=='0'){if(pos<text.Length&&Char.IsDigit(text[pos]))throw new IOException("json_number");}else while(pos<text.Length&&text[pos]>='0'&&text[pos]<='9')pos++;
   if(pos<text.Length&&text[pos]=='.'){pos++;int n=pos;while(pos<text.Length&&text[pos]>='0'&&text[pos]<='9')pos++;if(n==pos)throw new IOException("json_number");}
   if(pos<text.Length&&(text[pos]=='e'||text[pos]=='E')){pos++;if(pos<text.Length&&(text[pos]=='+'||text[pos]=='-'))pos++;int n=pos;while(pos<text.Length&&text[pos]>='0'&&text[pos]<='9')pos++;if(n==pos)throw new IOException("json_number");}
   string number=text.Substring(start,pos-start);long l;if(Int64.TryParse(number,NumberStyles.Integer,CultureInfo.InvariantCulture,out l))return l;double x;if(!Double.TryParse(number,NumberStyles.Float,CultureInfo.InvariantCulture,out x)||Double.IsInfinity(x)||Double.IsNaN(x))throw new IOException("json_number");return x;
  }
  void Literal(string value){foreach(char c in value)if(Next()!=c)throw new IOException("json_literal");}
  string String(){var b=new StringBuilder();while(true){char c=Next();if(c=='"')return b.ToString();if(c<' ')throw new IOException("json_control");if(c=='\\'){c=Next();switch(c){case '"':case '\\':case '/':b.Append(c);break;case 'b':b.Append('\b');break;case 'f':b.Append('\f');break;case 'n':b.Append('\n');break;case 'r':b.Append('\r');break;case 't':b.Append('\t');break;case 'u':int n=0;for(int i=0;i<4;i++){char h=Next();int v=h>='0'&&h<='9'?h-'0':h>='a'&&h<='f'?h-'a'+10:h>='A'&&h<='F'?h-'A'+10:-1;if(v<0)throw new IOException("json_escape");n=n*16+v;}b.Append((char)n);break;default:throw new IOException("json_escape");}}else b.Append(c);}}
 }
 public static Dictionary<string,object> Parse(byte[] bytes,int max){if(bytes==null||bytes.Length==0||bytes.Length>max)throw new IOException("json_size");var d=new Reader(bytes).Parse() as Dictionary<string,object>;if(d==null)throw new IOException("json_object_required");return d;}
 public static string Hash(byte[] bytes){using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();}
 public static void Keys(Dictionary<string,object> d,string required,string optional){var allow=new HashSet<string>((required+" "+optional).Split(new[]{' '},StringSplitOptions.RemoveEmptyEntries),StringComparer.Ordinal);foreach(string k in d.Keys)if(!allow.Contains(k))throw new IOException("schema_unknown_field");foreach(string k in required.Split(new[]{' '},StringSplitOptions.RemoveEmptyEntries))if(!d.ContainsKey(k))throw new IOException("schema_missing_field");}
 public static bool Bool(Dictionary<string,object>d,string k){if(!d.ContainsKey(k)||!(d[k] is bool))throw new IOException("schema_boolean");return (bool)d[k];}
 public static long Count(Dictionary<string,object>d,string k){if(!d.ContainsKey(k)||!(d[k] is long)||(long)d[k]<0||(long)d[k]>9007199254740991L)throw new IOException("schema_count");return (long)d[k];}
 public static string Text(Dictionary<string,object>d,string k){if(!d.ContainsKey(k)||!(d[k] is string))throw new IOException("schema_string");return (string)d[k];}
 public static Dictionary<string,object> Report(byte[] bytes){
  var d=Parse(bytes,65536);
  Keys(d,"reportSchema verified status scope production_completeness_not_attested activation_supported","mirrored mirrorPending mirrorError localBackupCreated nextDueAt pruned retentionDays artifactSha256 files crossComponentAtomic effectEvidence failureCode");
  if(Text(d,"reportSchema")!="i-core-automatic-result-v2"||Text(d,"scope")!="inventory_only"||!Bool(d,"production_completeness_not_attested")||Bool(d,"activation_supported"))throw new IOException("report_schema");
  string status=Text(d,"status");if(status!="not_due"&&status!="mirror_pending"&&status!="backed_up"&&status!="failed")throw new IOException("report_status");
  if(Bool(d,"verified")!=(status!="failed"))throw new IOException("report_verified");
  if(status!="failed"){foreach(string k in new[]{"mirrored","mirrorPending"})Bool(d,k);Count(d,"nextDueAt");if(!d.ContainsKey("effectEvidence"))throw new IOException("report_effects_required");}
  foreach(string k in new[]{"pruned","retentionDays","files"})if(d.ContainsKey(k))Count(d,k);
  if(d.ContainsKey("localBackupCreated")&&!Bool(d,"localBackupCreated"))throw new IOException("report_local_created");
  if(d.ContainsKey("crossComponentAtomic")&&Bool(d,"crossComponentAtomic"))throw new IOException("report_atomic");
  if(d.ContainsKey("artifactSha256")&&!System.Text.RegularExpressions.Regex.IsMatch(Text(d,"artifactSha256"),"^[a-f0-9]{64}$"))throw new IOException("report_hash");
  if(d.ContainsKey("mirrorError")&&Text(d,"mirrorError")!="mirror_copy_unavailable_or_rejected")throw new IOException("report_error");
  if(d.ContainsKey("failureCode")&&Text(d,"failureCode")!="automatic_operation_rejected")throw new IOException("report_error");
  if(status=="failed"){Keys(d,"reportSchema verified status scope production_completeness_not_attested activation_supported failureCode","effectEvidence");}
  else if(d.ContainsKey("failureCode"))throw new IOException("report_unexpected_failure");
  if(d.ContainsKey("mirrorError")&&(!d.ContainsKey("mirrorPending")||!Bool(d,"mirrorPending")))throw new IOException("report_mirror_error_state");
  if(d.ContainsKey("retentionDays")&&(Count(d,"retentionDays")<1||Count(d,"retentionDays")>3650))throw new IOException("report_retention");
  if(status=="not_due"&&(d.ContainsKey("pruned")||d.ContainsKey("localBackupCreated")||Bool(d,"mirrorPending")))throw new IOException("report_not_due");
  if(status=="mirror_pending"&&!Bool(d,"mirrorPending"))throw new IOException("report_pending");
  if(status=="backed_up"&&(!d.ContainsKey("pruned")||!d.ContainsKey("localBackupCreated")||Bool(d,"mirrorPending")))throw new IOException("report_backed_up");
  if(d.ContainsKey("effectEvidence")){
   var e=d["effectEvidence"] as Dictionary<string,object>;if(e==null)throw new IOException("effect_object");
   const string counts="localRemovedBackupSets mirrorRemovedBackupSets deleteOperationsAttempted deleteOperationsCompleted mirrorAttempted mirrorAlreadyPresent mirrorCopied mirrorPending directoryCreateAttempted directoryCreateCompleted fileCopyAttempted fileCopyCompleted receiptWriteAttempted receiptWriteCompleted localValidatedReceipts mirrorValidatedReceipts";
   Keys(e,"format pruneBranchEntered measurementComplete partial failureStage "+counts,"");
   if(Text(e,"format")!="i-core-backup-effects-v1")throw new IOException("effect_schema");
   foreach(string k in counts.Split(' '))Count(e,k);bool prune=Bool(e,"pruneBranchEntered"),complete=Bool(e,"measurementComplete"),partial=Bool(e,"partial");
   if(complete&&partial)throw new IOException("effect_inconsistent");
   if(complete&&(e["failureStage"]!=null||Count(e,"mirrorPending")!=0))throw new IOException("effect_false_completion");
   if(complete)foreach(string kind in new[]{"deleteOperations","directoryCreate","fileCopy","receiptWrite"})if(Count(e,kind+"Attempted")!=Count(e,kind+"Completed"))throw new IOException("effect_false_completion");
   foreach(string kind in new[]{"deleteOperations","directoryCreate","fileCopy","receiptWrite"})if(Count(e,kind+"Completed")>Count(e,kind+"Attempted"))throw new IOException("effect_counts");
   if(Count(e,"mirrorAlreadyPresent")+Count(e,"mirrorCopied")+Count(e,"mirrorPending")!=Count(e,"mirrorAttempted"))throw new IOException("effect_mirror_counts");
   if(Count(e,"mirrorValidatedReceipts")!=Count(e,"mirrorAlreadyPresent")+Count(e,"mirrorCopied"))throw new IOException("effect_mirror_auth");
   if(!prune&&(Count(e,"deleteOperationsAttempted")!=0||Count(e,"localRemovedBackupSets")!=0||Count(e,"mirrorRemovedBackupSets")!=0))throw new IOException("effect_prune");
   if(e["failureStage"]!=null && (!(e["failureStage"] is string)||Array.IndexOf(new[]{"directory","copy","receipt","delete","mirror_validation","automatic"},(string)e["failureStage"])<0))throw new IOException("effect_failure_stage");
   if(partial&&e["failureStage"]==null)throw new IOException("effect_failure_stage");
   if(status=="not_due"&&prune)throw new IOException("effect_not_due_prune");
  }
  return d;
 }
}
public sealed class Schema6BackupJob : IDisposable {
 [StructLayout(LayoutKind.Sequential)] struct SA{public int length;public IntPtr descriptor;public int inherit;}
 [StructLayout(LayoutKind.Sequential)] struct Startup{public uint cb;public IntPtr reserved,desktop,title;public uint x,y,cx,cy,charsX,charsY,fill,flags;public ushort show,reserved2;public IntPtr reservedPtr,input,output,error;}
 [StructLayout(LayoutKind.Sequential)] struct StartupEx{public Startup startup;public IntPtr attributes;}
 [StructLayout(LayoutKind.Sequential)] struct PI{public IntPtr process,thread;public uint pid,tid;}
 [StructLayout(LayoutKind.Sequential)] struct Accounting{public long user,kernel,periodUser,periodKernel;public uint faults,total,active,terminated;}
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool CreatePipe(out IntPtr read,out IntPtr write,ref SA sa,uint size);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetHandleInformation(IntPtr h,uint mask,uint flags);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool InitializeProcThreadAttributeList(IntPtr list,int count,int flags,ref IntPtr size);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool UpdateProcThreadAttribute(IntPtr list,uint flags,IntPtr attribute,IntPtr value,IntPtr size,IntPtr prev,IntPtr returned);
 [DllImport("kernel32.dll")] static extern void DeleteProcThreadAttributeList(IntPtr list);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateProcess(string app,StringBuilder cmd,IntPtr ps,IntPtr ts,bool inherit,uint flags,IntPtr env,string cwd,ref StartupEx startup,out PI info);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr sa,string name);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job,int type,out Accounting a,uint size,IntPtr returned);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetProcessTimes(IntPtr p,out long created,out long exited,out long kernel,out long user);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr p,out uint code);
 [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h,uint ms);
 [DllImport("kernel32.dll",SetLastError=true)] static extern uint ResumeThread(IntPtr t);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool PeekNamedPipe(IntPtr h,IntPtr buffer,uint size,IntPtr read,out uint available,IntPtr left);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool ReadFile(IntPtr h,byte[] b,uint n,out uint read,IntPtr overlapped);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool QueryFullProcessImageName(IntPtr process,uint flags,StringBuilder name,ref uint size);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool ProcessIdToSessionId(uint pid,out uint session);
 public sealed class Capture {
  public volatile bool Done,Eof,Overflow,Cancelled;public long ByteCount;public string Sha256;public byte[] Bytes;public string Failure;
  readonly IntPtr handle;readonly int limit,budget;readonly Stopwatch time=Stopwatch.StartNew();volatile bool stop;
  internal Capture(IntPtr h,int max,int milliseconds){handle=h;limit=max;budget=milliseconds;new Thread(Run){IsBackground=true}.Start();}
  internal void Cancel(){stop=true;}
  void Run(){var memory=new MemoryStream();var hash=SHA256.Create();try{byte[] buffer=new byte[4096];while(true){
   if(stop||time.ElapsedMilliseconds>budget){Cancelled=true;Failure="capture_timeout_or_closed";break;}
   uint available;if(!PeekNamedPipe(handle,IntPtr.Zero,0,IntPtr.Zero,out available,IntPtr.Zero)){int code=Marshal.GetLastWin32Error();if(code==109){Eof=true;break;}Failure="capture_peek";break;}
   if(available==0){Thread.Sleep(5);continue;}
   uint read;if(!ReadFile(handle,buffer,Math.Min((uint)buffer.Length,available),out read,IntPtr.Zero)){if(Marshal.GetLastWin32Error()==109){Eof=true;break;}Failure="capture_read";break;}if(read==0)continue;
   ByteCount+=read;hash.TransformBlock(buffer,0,(int)read,null,0);int keep=Math.Min((int)read,Math.Max(0,limit-(int)memory.Length));if(keep>0)memory.Write(buffer,0,keep);
   if(ByteCount>limit)Overflow=true;
   if(ByteCount>1048576){Failure="capture_drain_limit";break;}
  }hash.TransformFinalBlock(new byte[0],0,0);Sha256=BitConverter.ToString(hash.Hash).Replace("-","").ToLowerInvariant();Bytes=memory.ToArray();
  }catch{Failure="capture_internal";Bytes=new byte[0];}finally{hash.Dispose();memory.Dispose();CloseHandle(handle);Done=true;}}
 }
 IntPtr job,process,thread,inputWrite;public uint Pid{get;private set;}public string StartedTicks{get;private set;}public string OwnerSid{get;private set;}public uint SessionId{get;private set;}public string ImagePath{get;private set;}public volatile bool InputComplete,InputFailed;public bool Assigned{get;private set;}public bool Resumed{get;private set;}public string PrepareFailure{get;private set;}public Capture Stdout{get;private set;}public Capture Stderr{get;private set;}public readonly Stopwatch Elapsed=Stopwatch.StartNew();
 static void Need(bool ok,string code){if(!ok)throw new IOException(code);}
 static string Quote(string s){if(s==null||s.IndexOf('"')>=0||s.IndexOf('\n')>=0||s.IndexOf('\r')>=0||s.EndsWith("\\"))throw new IOException("backup_argument");return "\""+s+"\"";}
 public bool HandlesHeld{get{return job!=IntPtr.Zero||process!=IntPtr.Zero||thread!=IntPtr.Zero||inputWrite!=IntPtr.Zero;}}
 public void Prepare(string executable,string[] args,string cwd){Prepare(executable,args,cwd,120000);}
 public void Prepare(string executable,string[] args,string cwd,int captureBudget){
  if(captureBudget!=120000&&captureBudget!=330000)throw new IOException("backup_capture_budget");
  if(job!=IntPtr.Zero||process!=IntPtr.Zero)throw new IOException("backup_prepare_once");IntPtr outR=IntPtr.Zero,outW=IntPtr.Zero,errR=IntPtr.Zero,errW=IntPtr.Zero,inR=IntPtr.Zero,list=IntPtr.Zero,handles=IntPtr.Zero,environment=IntPtr.Zero;bool listReady=false;
  try{
   job=CreateJobObject(IntPtr.Zero,null);Need(job!=IntPtr.Zero,"backup_job_create");
   // Deliberately no KILL_ON_JOB_CLOSE: active or suspended worker remains unknown.
   var sa=new SA{length=Marshal.SizeOf(typeof(SA)),inherit=1};
   Need(CreatePipe(out outR,out outW,ref sa,0)&&CreatePipe(out errR,out errW,ref sa,0)&&CreatePipe(out inR,out inputWrite,ref sa,0),"backup_pipe_create");
   Need(SetHandleInformation(outR,1,0)&&SetHandleInformation(errR,1,0)&&SetHandleInformation(inputWrite,1,0),"backup_pipe_noninherit");
   IntPtr size=IntPtr.Zero;InitializeProcThreadAttributeList(IntPtr.Zero,1,0,ref size);Need(size!=IntPtr.Zero,"backup_attribute_size");list=Marshal.AllocHGlobal(size);Need(InitializeProcThreadAttributeList(list,1,0,ref size),"backup_attribute_init");listReady=true;
   handles=Marshal.AllocHGlobal(IntPtr.Size*3);Marshal.WriteIntPtr(handles,0,inR);Marshal.WriteIntPtr(handles,IntPtr.Size,outW);Marshal.WriteIntPtr(handles,IntPtr.Size*2,errW);
   Need(UpdateProcThreadAttribute(list,0,new IntPtr(0x20002),handles,new IntPtr(IntPtr.Size*3),IntPtr.Zero,IntPtr.Zero),"backup_handle_whitelist");
   var si=new StartupEx();si.startup.cb=(uint)Marshal.SizeOf(typeof(StartupEx));si.startup.flags=0x100;si.startup.input=inR;si.startup.output=outW;si.startup.error=errW;si.attributes=list;
   var cmd=new StringBuilder(Quote(executable));foreach(string arg in args)cmd.Append(" "+Quote(arg));
   var env=new SortedDictionary<string,string>(StringComparer.OrdinalIgnoreCase);foreach(string name in new[]{"SYSTEMROOT","WINDIR","TEMP","TMP","COMSPEC"}){string v=Environment.GetEnvironmentVariable(name);if(v!=null)env[name]=v;}env["PATHEXT"]=".EXE";var block=new StringBuilder();foreach(var p in env)block.Append(p.Key+"="+p.Value+"\0");block.Append("\0");environment=Marshal.StringToHGlobalUni(block.ToString());
   PI pi;Need(CreateProcess(executable,cmd,IntPtr.Zero,IntPtr.Zero,true,0x08080404,environment,cwd,ref si,out pi),"backup_create_suspended");process=pi.process;thread=pi.thread;Pid=pi.pid;
   Stdout=new Capture(outR,65536,captureBudget);outR=IntPtr.Zero;Stderr=new Capture(errR,4096,captureBudget);errR=IntPtr.Zero;
   long created,exited,kernel,user;Need(GetProcessTimes(process,out created,out exited,out kernel,out user),"backup_identity");StartedTicks=DateTime.FromFileTimeUtc(created).Ticks.ToString(CultureInfo.InvariantCulture);
   IntPtr token;Need(OpenProcessToken(process,8,out token),"backup_owner");try{using(var id=new WindowsIdentity(token))OwnerSid=id.User.Value;}finally{CloseHandle(token);}
   var image=new StringBuilder(32768);uint imageSize=(uint)image.Capacity;Need(QueryFullProcessImageName(process,0,image,ref imageSize),"backup_image");ImagePath=image.ToString();if(!ImagePath.Equals(executable,StringComparison.OrdinalIgnoreCase))throw new IOException("backup_image_mismatch");
   uint session;Need(ProcessIdToSessionId(Pid,out session),"backup_session");SessionId=session;
   Need(AssignProcessToJobObject(job,process),"backup_job_assign");Assigned=true;
  }catch(Exception e){PrepareFailure=e.Message;throw;}
  finally{foreach(IntPtr h in new[]{outR,outW,errR,errW,inR})if(h!=IntPtr.Zero)CloseHandle(h);if(listReady)DeleteProcThreadAttributeList(list);if(list!=IntPtr.Zero)Marshal.FreeHGlobal(list);if(handles!=IntPtr.Zero)Marshal.FreeHGlobal(handles);if(environment!=IntPtr.Zero)Marshal.FreeHGlobal(environment);}
 }
 public void Resume(byte[] input){if(!Assigned||Resumed||thread==IntPtr.Zero)throw new IOException("backup_resume_state");Need(ResumeThread(thread)!=0xffffffff,"backup_resume");Resumed=true;CloseHandle(thread);thread=IntPtr.Zero;IntPtr writer=inputWrite;inputWrite=IntPtr.Zero;new Thread(delegate(){try{using(var stream=new FileStream(new SafeFileHandle(writer,true),FileAccess.Write)){if(input!=null)stream.Write(input,0,input.Length);}}catch{InputFailed=true;}finally{if(input!=null)Array.Clear(input,0,input.Length);InputComplete=true;}}){IsBackground=true}.Start();}
 public bool PreparationEndedWithoutProcess{get{return PrepareFailure!=null&&Pid==0&&process==IntPtr.Zero&&thread==IntPtr.Zero&&(job==IntPtr.Zero||Empty);}}
 public bool Exited{get{return process!=IntPtr.Zero&&WaitForSingleObject(process,0)==0;}}
 public bool Empty{get{Accounting a;if(job==IntPtr.Zero||!QueryInformationJobObject(job,1,out a,(uint)Marshal.SizeOf(typeof(Accounting)),IntPtr.Zero))throw new IOException("backup_job_query");return a.active==0;}}
 public uint ExitCode{get{uint code;if(!Exited||!GetExitCodeProcess(process,out code))throw new IOException("backup_exit_unknown");return code;}}
 public bool CaptureComplete{get{return Stdout!=null&&Stderr!=null&&Stdout.Done&&Stderr.Done;}}
 public bool WaitEmpty(int ms){var t=Stopwatch.StartNew();while(t.ElapsedMilliseconds<ms){if(Exited&&Empty)return true;Thread.Sleep(5);}return Exited&&Empty;}
 public static Dictionary<string,object> GetIdentity(int pid){
 using(var p=Process.GetProcessById(pid)){long c,e,k,u;Need(GetProcessTimes(p.Handle,out c,out e,out k,out u),"identity_times");if(p.HasExited)throw new IOException("identity_exited");var image=new StringBuilder(32768);uint size=(uint)image.Capacity;Need(QueryFullProcessImageName(p.Handle,0,image,ref size),"identity_image");IntPtr token;Need(OpenProcessToken(p.Handle,8,out token),"identity_owner");string owner;try{using(var id=new WindowsIdentity(token))owner=id.User.Value;}finally{CloseHandle(token);}uint session;Need(ProcessIdToSessionId((uint)pid,out session),"identity_session");return new Dictionary<string,object>{{"pid",(long)pid},{"startedTicks",DateTime.FromFileTimeUtc(c).Ticks.ToString(CultureInfo.InvariantCulture)},{"ownerSid",owner},{"sessionId",(long)session},{"imagePath",image.ToString()}};
 }}
 public void CloseCapture(){if(Stdout!=null)Stdout.Cancel();if(Stderr!=null)Stderr.Cancel();}
 public void Dispose(){CloseCapture();foreach(IntPtr h in new[]{inputWrite,thread,process,job})if(h!=IntPtr.Zero)CloseHandle(h);inputWrite=thread=process=job=IntPtr.Zero;}
}

public static class BackupDurable {
 static Type Native {get{foreach(var a in AppDomain.CurrentDomain.GetAssemblies()){var t=a.GetType("OwnedArtifactNative",false);if(t!=null)return t;}throw new IOException("backup_owned_helper_unloaded");}}
 static object Call(string method,params object[] args){try{return Native.GetMethod(method).Invoke(null,args);}catch(System.Reflection.TargetInvocationException e){throw e.InnerException;}}
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFile(string p,uint access,uint share,IntPtr security,uint disposition,uint flags,IntPtr template);

 [StructLayout(LayoutKind.Sequential)] struct PinnedInfo {public uint attributes;public System.Runtime.InteropServices.ComTypes.FILETIME creation,access,write;public uint volume,high,low,links,indexHigh,indexLow;}
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out PinnedInfo info);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(SafeFileHandle h,StringBuilder name,uint length,uint flags);
 static bool SystemImage(string path){return path.Equals(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe"),StringComparison.OrdinalIgnoreCase);}
 static string FileIdentity(SafeFileHandle h,string path,bool privateRequired){
  if(privateRequired||!SystemImage(path))return (string)Call("Check",h,path,false);
  // Windows services this fixed, hash-pinned executable through a WinSxS hardlink.
  // The exception never applies to source, config, receipt, Node or other paths.
  PinnedInfo info;var final=new StringBuilder(32768);uint n=GetFinalPathNameByHandle(h,final,32768,0);
  if(!GetFileInformationByHandle(h,out info)||info.links!=2||(info.attributes&0x410)!=0||n==0||n>=32768||!final.ToString().Equals(@"\\?\"+path,StringComparison.OrdinalIgnoreCase))throw new IOException("backup_system_image_identity");
  return info.volume+":"+info.indexHigh+":"+info.indexLow;
 }

 public sealed class Lease:IDisposable {
  readonly List<SafeFileHandle> parents=new List<SafeFileHandle>();readonly FileStream file;public readonly byte[] Bytes;public readonly string Hash,Identity;public readonly string Pathname;
  public Lease(string path,string expectedHash,int max):this(path,expectedHash,max,true){}
  public Lease(string path,string expectedHash,int max,bool privateRequired){
   Call("Plain",path);Pathname=path;
   try{
    var dirs=new List<string>();for(string q=Path.GetDirectoryName(path);!String.IsNullOrEmpty(q);q=Path.GetDirectoryName(q))dirs.Insert(0,q);
    foreach(string q in dirs){var h=CreateFile(q,0x20080,3,IntPtr.Zero,3,0x02200000,IntPtr.Zero);if(h.IsInvalid)throw new IOException("backup_parent_open");parents.Add(h);Call("Check",h,q,true);}
    var handle=CreateFile(path,0x80020080,1,IntPtr.Zero,3,0x00200000,IntPtr.Zero);if(handle.IsInvalid){int error=Marshal.GetLastWin32Error();handle.Dispose();throw new BackupPublicationOpenException(path,error);}
    try{Identity=FileIdentity(handle,path,privateRequired);if(privateRequired)Call("Private",handle,WindowsIdentity.GetCurrent().User.Value,false);file=new FileStream(handle,FileAccess.Read);}catch{handle.Dispose();throw;}
    if(file.Length>max||file.Length<0)throw new IOException("backup_lease_size");Bytes=new byte[(int)file.Length];int at=0;while(at<Bytes.Length){int read=file.Read(Bytes,at,Bytes.Length-at);if(read==0)throw new IOException("backup_lease_short");at+=read;}
    Hash=BackupStrictJson.Hash(Bytes);if(expectedHash!=null&&Hash!=expectedHash)throw new IOException("backup_lease_hash");
    if(FileIdentity(file.SafeFileHandle,path,privateRequired)!=Identity)throw new IOException("backup_lease_identity");
   }catch{Dispose();throw;}
  }
  public void Dispose(){if(file!=null)file.Dispose();foreach(var p in parents)p.Dispose();parents.Clear();}
 }
 public static Lease Image(string path,string hash){if(SystemImage(path)&&hash!="8bb6fa8c283b4d92120b1ef249a9b311b0f804d4cabbe9981159976c8be76a5e")throw new IOException("backup_system_image_pin");return new Lease(path,hash,134217728,false);}
 public static Lease Read(string path,string hash,int max){return new Lease(path,hash,max);}
 public static string Write(string path,byte[] bytes){
  string owner=WindowsIdentity.GetCurrent().User.Value;
  // Existing helper performs CreateNew with atomic private DACL, Flush(true),
  // byte-for-byte same-handle and same-file-ID pathname readback.
  Call("Write",path,owner,bytes);
  using(var read=Read(path,BackupStrictJson.Hash(bytes),bytes.Length)){return read.Hash;}
 }
 public static Dictionary<string,object> Json(string path,string hash,int max){using(var read=Read(path,hash,max))return BackupStrictJson.Parse(read.Bytes,max);}
 public static string ShaFile(string path){using(var read=Read(path,null,134217728))return read.Hash;}
}

public static class BackupChildDiagnostic {
 const string NodeHash="58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f";
 public static byte[] Warning(uint pid){return new UTF8Encoding(false,true).GetBytes("(node:"+pid.ToString(CultureInfo.InvariantCulture)+") ExperimentalWarning: SQLite is an experimental feature and might change at any time\n(Use "+(char)96+"node --trace-warnings ..."+(char)96+" to show where the warning was created)\n");}
 public static string Classify(byte[] bytes,uint pid){
  if(bytes==null)return "rejected";if(bytes.Length==0)return "empty";var expected=Warning(pid);if(bytes.Length!=expected.Length)return "rejected";
  int diff=0;for(int i=0;i<bytes.Length;i++)diff|=bytes[i]^expected[i];return diff==0?"sqlite_experimental_warning":"rejected";
 }
 public static Dictionary<string,object> Evidence(Schema6BackupJob j,string role,string scriptHash,string node,string script,string release){
  string expectedScript=Path.Combine(release,"tools","i_core","release_schema6",role=="cli-verify"?"cli.mjs":"backup_key_child.mjs");
  if((role!="cli-verify"&&role!="key-child")||!script.Equals(expectedScript,StringComparison.OrdinalIgnoreCase)||!node.Equals(Path.Combine(release,"runtime","node.exe"),StringComparison.OrdinalIgnoreCase)||!j.ImagePath.Equals(node,StringComparison.OrdinalIgnoreCase))throw new IOException("diagnostic_image_or_script");
  using(var stream=File.OpenRead(node))using(var h=SHA256.Create()){if(BitConverter.ToString(h.ComputeHash(stream)).Replace("-","").ToLowerInvariant()!=NodeHash)throw new IOException("diagnostic_node_hash");}
  string diagnostic=Classify(j.Stderr.Bytes,j.Pid);
  return new Dictionary<string,object>{{"role",role},{"pid",(long)j.Pid},{"startedTicks",j.StartedTicks},{"imageSha256",NodeHash},{"scriptSha256",scriptHash},{"exitCode",(long)j.ExitCode},{"jobEmpty",j.Empty},{"stdoutEof",j.Stdout.Eof},{"stderrEof",j.Stderr.Eof},{"inputComplete",j.InputComplete},{"inputFailed",j.InputFailed},{"stdoutByteCount",j.Stdout.ByteCount},{"stdoutSha256",j.Stdout.Sha256},{"stderrByteCount",j.Stderr.ByteCount},{"stderrSha256",j.Stderr.Sha256},{"stderrBase64",diagnostic=="rejected"?null:Convert.ToBase64String(j.Stderr.Bytes)},{"stderrDiagnostic",diagnostic}};
 }
 static void Hash(string s){if(!System.Text.RegularExpressions.Regex.IsMatch(s??"","^[a-f0-9]{64}$"))throw new IOException("capture_hash");}
 public static void Validate(Dictionary<string,object>d,string role,string scriptHash,bool success){
  BackupStrictJson.Keys(d,"role pid startedTicks imageSha256 scriptSha256 exitCode jobEmpty stdoutEof stderrEof inputComplete inputFailed stdoutByteCount stdoutSha256 stderrByteCount stderrSha256 stderrBase64 stderrDiagnostic","");
  if(BackupStrictJson.Text(d,"role")!=role||BackupStrictJson.Text(d,"imageSha256")!=NodeHash||BackupStrictJson.Text(d,"scriptSha256")!=scriptHash)throw new IOException("capture_binding");
  long pid=BackupStrictJson.Count(d,"pid");if(pid<1||pid>UInt32.MaxValue||!System.Text.RegularExpressions.Regex.IsMatch(BackupStrictJson.Text(d,"startedTicks"),"^[0-9]{1,19}$"))throw new IOException("capture_identity");
  Hash(BackupStrictJson.Text(d,"stdoutSha256"));Hash(BackupStrictJson.Text(d,"stderrSha256"));if(BackupStrictJson.Count(d,"stdoutByteCount")>65536||BackupStrictJson.Count(d,"stderrByteCount")>4096)throw new IOException("capture_size");
  foreach(string k in new[]{"jobEmpty","stdoutEof","stderrEof","inputComplete"})if(!BackupStrictJson.Bool(d,k))throw new IOException("capture_completion");if(BackupStrictJson.Bool(d,"inputFailed"))throw new IOException("capture_input");
  string code=BackupStrictJson.Text(d,"stderrDiagnostic");if(code=="rejected"){if(success||d["stderrBase64"]!=null)throw new IOException("capture_rejected_raw");}
  else{
   if(code!="empty"&&code!="sqlite_experimental_warning")throw new IOException("capture_diagnostic");
   byte[] raw=Convert.FromBase64String(BackupStrictJson.Text(d,"stderrBase64"));
   if(Convert.ToBase64String(raw)!=BackupStrictJson.Text(d,"stderrBase64")||raw.LongLength!=BackupStrictJson.Count(d,"stderrByteCount")||BackupStrictJson.Hash(raw)!=BackupStrictJson.Text(d,"stderrSha256")||Classify(raw,(uint)pid)!=code)throw new IOException("capture_raw");
  }
  long exit=BackupStrictJson.Count(d,"exitCode");if(success&&exit!=0)throw new IOException("capture_exit");
 }
}

public static class BackupRawBinding {
 public static Dictionary<string,object> Admit(byte[] bytes,string bindingPath,string expectedApprovalHash){
  if(!System.Text.RegularExpressions.Regex.IsMatch(expectedApprovalHash??"","^[a-f0-9]{64}$"))throw new IOException("backup_approval_pin");
  var binding=BackupStrictJson.Parse(bytes,1048576);
  var policy=binding.ContainsKey("policy")?binding["policy"] as Dictionary<string,object>:null;
  var documents=binding.ContainsKey("documents")?binding["documents"] as Dictionary<string,object>:null;
  var approval=documents!=null&&documents.ContainsKey("approval")?documents["approval"] as Dictionary<string,object>:null;
  if(policy==null||approval==null)throw new IOException("backup_raw_binding");
  foreach(string key in new[]{"approvalSha256","p3ReceiptSha256","runLedgerSha256","identity","bindingSha256"})if(!policy.ContainsKey(key)||policy[key]!=null)throw new IOException("backup_raw_approval_slot");
  if(!approval.ContainsKey("sha256")||approval["sha256"]!=null)throw new IOException("backup_raw_approval_slot");
  if(BackupStrictJson.Text(approval,"path")!=Path.Combine(Path.GetDirectoryName(bindingPath),"approval.json"))throw new IOException("backup_raw_approval_path");
  return binding;
 }
}

public sealed class BackupPublicationOpenException:IOException {public readonly string TargetPath;public readonly int NativeError;public BackupPublicationOpenException(string path,int error):base("backup_lease_open"){TargetPath=path;NativeError=error;}}
