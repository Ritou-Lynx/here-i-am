// Fixed host-fault retirement only. Never repairs original close/Job/helper evidence.
// Explicit inspect is read-only; explicit cleanup removes only the four exact owned keys.
using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace HereIAm.R7 {
    internal static class TaskInflightRetiredNative {
        [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]internal struct ProcessEntry {
            internal uint Size,Usage,Pid;internal UIntPtr Heap;internal uint Module,Threads,Parent;internal int Priority;internal uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)]internal string Name;
        }
        [DllImport("kernel32.dll",SetLastError=true)]internal static extern IntPtr CreateToolhelp32Snapshot(uint flags,uint pid);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]internal static extern bool Process32FirstW(IntPtr snapshot,ref ProcessEntry entry);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]internal static extern bool Process32NextW(IntPtr snapshot,ref ProcessEntry entry);
        internal static void Layouts(){TaskInflightRetiredProgram.Need(IntPtr.Size==8&&Marshal.SizeOf(typeof(ProcessEntry))==568&&Marshal.OffsetOf(typeof(ProcessEntry),"Pid").ToInt32()==8&&Marshal.OffsetOf(typeof(ProcessEntry),"Heap").ToInt32()==16&&Marshal.OffsetOf(typeof(ProcessEntry),"Name").ToInt32()==44);InspectionNative.Layouts();}
    }
    internal sealed class TaskInflightRetiredResources {
        internal readonly MatrixHandleLedger Handles;internal IntPtr Engine;internal bool Transaction;internal bool CloseSucceeded=true;internal uint? CloseError;
        readonly Func<IntPtr,uint> abort,closeEngine;
        internal TaskInflightRetiredResources():this(Native.CloseHandle,Native.FwpmTransactionAbort0,Native.FwpmEngineClose0){}
        internal TaskInflightRetiredResources(Func<IntPtr,bool> closeHandle,Func<IntPtr,uint> abortTransaction,Func<IntPtr,uint> close){
            Handles=new MatrixHandleLedger(delegate(IntPtr handle){bool result=closeHandle(handle);if(!result)CloseError=unchecked((uint)Marshal.GetLastWin32Error());return result;});abort=abortTransaction;closeEngine=close;
        }
        internal bool Empty {get{return !Transaction&&Engine==IntPtr.Zero&&Handles.Empty;}}
        internal bool CloseVerified(){
            try{if(Transaction&&Engine!=IntPtr.Zero){uint code=abort(Engine);if(code==0)Transaction=false;else{CloseSucceeded=false;CloseError=code;}}}catch{CloseSucceeded=false;}
            try{if(Engine!=IntPtr.Zero&&!Transaction){uint code=closeEngine(Engine);if(code==0)Engine=IntPtr.Zero;else{CloseSucceeded=false;CloseError=code;}}}catch{CloseSucceeded=false;}
            CloseSucceeded=Handles.CloseAll()&&CloseSucceeded;return CloseSucceeded&&Empty;
        }
    }
    public static class TaskInflightRetiredProgram {
        internal static readonly Guid Attempt=new Guid("6946c568-0440-4574-8fbc-2d069b071c6c");
        internal static readonly Guid Scope=new Guid("b313153a-b5bb-2fe8-cbe1-ba150d3de67c");
        internal const uint OwnerPid=55588,ChildPid=1932,HelperPid=46760;
        internal const ulong OwnerCreation=134336820615821943UL,ChildCreation=134336820767048561UL,HelperCreation=134336820748922570UL;
        internal const int BrokerPort=16045;internal const ushort AssignedWeight=32766;
        internal const string BlobDigest="fb24a2a28b8884e5f91543dd4b718f518e28c243cf22f37075561c914935c59d";
        internal const string PreparedHash="a78ebdb7d7c7e2a6dbbc27cbfdac73480b158d9117f7ab10e56bb00619a85b84";
        internal const string SpawningHash="2a249e8f37a0e0f94525b5d664286ae649aa01ffa931b27f0b475630c5ede0db";
        internal const string BoundHash="220154972111bf14f6a00e4fc23ac129362a69560ae696e3e9a83557a74a6714";
        internal const string InstallHash="b29b0ddb425defaeb2b80d9d541a535e393e4f1f3d3ebda61c9a15da41f427ce";
        internal const string LeaseHash="2e4c52d6301718879c6cd53c07122b32425a12917c784a56492a7144b3aaf637";
        internal const string ImageHash="73cbe6277fd4bf5b92bdc3189e00eee5ce78f208d6037d8d16a14df9bde4bc4e";
        internal const string CliHash="3d6ca7085c932b62ef4ee4877e92f15b050fb94b2eb8e6c10a346a06248c6004";
        internal const string SourceHash="47d3da743598e17f92f2b3b7764226376097d015a7e337c3f27a9e7d8fbd5f92";
        internal const string ActualHash="f697df1bd14f3555b94da90cbfd09b026ece6fa7541f516ad79c58dd140b5f99";
        internal const string ClosedHash="186e914b57cffefc6bb830f5843fd15f5753b37bb78ec898d394acb284c19517";
        internal const string FinalHash="1fef1ee3791b518e6c3dfe74bc71617e4b6f61650f4b49bf31db78776335a559";
        internal const string OriginalImage=@"D:\memex\tmp\p6-r7-helper\windows_text_gate_task_executor.v7.exe";
        internal const string OriginalSource=@"D:\memex\tmp\p6-r7-review\native-task-executor-07.cs";
        internal const string ActualPath=@"D:\memex\tmp\p6-r7-review\inflight-http-interrupt-02.json";
        internal static readonly string DirectoryForAttempt=Path.Combine(@"D:\HereIAm-P6-R7-Task-Executor",Attempt.ToString("N"));
        internal static readonly string CopiedImage=Path.Combine(DirectoryForAttempt,"codex.exe");
        internal static readonly string[] FixedNames=new string[]{"project0","work","prepared.json","spawning.json","bound.json","install-ready.json","install-ack.json","install-receipt.json","closed.json","final-receipt.json","codex.exe"};
        static readonly List<TaskInflightRetiredResources> Retained=new List<TaskInflightRetiredResources>();
        internal static void Need(bool value){Guard.Require(value,"task_inflight_retired_rejected");}
        internal static void Status(uint value){Guard.Win32(value==0,value,"task_inflight_retired_api_failed");}
        internal static void Win(bool value){uint code=unchecked((uint)Marshal.GetLastWin32Error());Guard.Win32(value,code,"task_inflight_retired_api_failed");}
        internal static uint Number(object value){Need(value is int||value is long||value is uint);long n=Convert.ToInt64(value);Need(n>=0&&n<=UInt32.MaxValue);return (uint)n;}
        static void Keys(Dictionary<string,object> value,string keys){string[] names=keys.Split(',');Need(value!=null&&value.Count==names.Length);foreach(string name in names)Need(value.ContainsKey(name));}
        internal static bool Inactive(bool opened,uint error,uint returnedPid,ulong creation,uint wait,uint expectedPid=OwnerPid,ulong expectedCreation=OwnerCreation){return !opened?error==87:returnedPid==expectedPid&&creation>0&&(wait==0||wait==258)&&(creation!=expectedCreation||wait==0);}
        internal static bool PathIdle(bool samePath,uint wait){return (wait==0||wait==258)&&(!samePath||wait==0);}
        // Elevated recovery additionally requires the current SID to own both exact protected directories.
        // It never projects an elevated/linked token as the historical Medium token.
        internal static bool CallerAccepted(MediumIdentity current){return current!=null&&current.Type==1&&current.Integrity==12288&&current.ElevationType==2&&current.Elevated==1&&current.AppContainer==0&&current.Authentication!=0;}
        internal static bool Complete(bool admitted,bool history,bool idleBefore,bool idleAfter,bool postPins,bool absence,bool ended,bool resourcesClosed){return admitted&&history&&idleBefore&&idleAfter&&postPins&&absence&&ended&&resourcesClosed;}
        internal static bool ExactNames(string[] names){if(names==null||names.Length!=FixedNames.Length)return false;HashSet<string> expected=new HashSet<string>(FixedNames,StringComparer.OrdinalIgnoreCase);foreach(string name in names)if(name==null||name!=Path.GetFileName(name)||!expected.Remove(name))return false;return expected.Count==0;}
        static ulong Time(object value){string s=value as string;ulong n;Need(s!=null&&UInt64.TryParse(s,out n));n=UInt64.Parse(s);Need(n>0&&n.ToString(System.Globalization.CultureInfo.InvariantCulture)==s);return n;}
        internal static Dictionary<string,object> History(string prepared,string spawning,string bound,string ready,string ack,string install,string closed,string final){
            string[] texts={prepared,spawning,bound};Dictionary<string,object>[] records=new Dictionary<string,object>[3];
            for(int i=0;i<3;i++){
                var j=TaskJson.Parse(texts[i]);records[i]=j;Keys(j,"schema,attempt_id,scope_id,auth_mode,home_class,nonce,owner_pid,owner_creation,owner_sha256,owner_token_digest,cli_sha256,broker_port,phase,child_pid,child_creation");
                Need(Object.Equals(j["schema"],"p6_r7_task_owned_v2")&&Object.Equals(j["attempt_id"],Attempt.ToString("D"))&&Object.Equals(j["scope_id"],Scope.ToString("D"))&&Object.Equals(j["auth_mode"],"chatgpt")&&Object.Equals(j["home_class"],"dedicated_existing")&&TaskCheck.Hex(j["nonce"])&&TaskCheck.Hex(j["owner_token_digest"]));
                Need(Number(j["owner_pid"])==OwnerPid&&Time(j["owner_creation"])==OwnerCreation&&Object.Equals(j["owner_sha256"],ImageHash)&&Object.Equals(j["cli_sha256"],CliHash)&&Number(j["broker_port"])==BrokerPort);
                Need(Object.Equals(j["phase"],new[]{"prepared","spawning","bound"}[i]));if(i<2)Need(j["child_pid"]==null&&j["child_creation"]==null);else Need(Number(j["child_pid"])==ChildPid&&Time(j["child_creation"])==ChildCreation);
                if(i>0)foreach(string key in new[]{"nonce","owner_token_digest"})Need(Object.Equals(j[key],records[0][key]));
            }
            var lease=TaskJson.Parse(ready);Keys(lease,"schema,attempt_id,scope_id,auth_mode,home_class,nonce,action,helper_pid,helper_creation,helper_sha256,helper_token_digest");Need(TaskCheck.Hex(lease["helper_token_digest"]));
            string expectedLease=TaskJson.Json(TaskRecords.Lease(records[0],"install",HelperPid,HelperCreation,(string)lease["helper_token_digest"]));Need(TaskJson.Json(lease)==expectedLease&&TaskJson.Json(TaskJson.Parse(ack))==expectedLease);
            TaskRecords.VerifyReceipt(install,records[0],"install",HelperPid,HelperCreation,BlobDigest,AssignedWeight);
            var close=TaskJson.Parse(closed);Keys(close,"schema,attempt_id,scope_id,auth_mode,home_class,nonce,owner_pid,owner_creation,owner_sha256,owner_token_digest,cli_sha256,broker_port,phase,child_pid,child_creation");
            foreach(string key in records[0].Keys)if(key!="phase"&&key!="child_pid"&&key!="child_creation")Need(Object.Equals(close[key],records[0][key]));Need(Object.Equals(close["phase"],"closed")&&Number(close["child_pid"])==ChildPid&&Time(close["child_creation"])==ChildCreation);
            var receipt=TaskJson.Parse(final);Keys(receipt,"schema,attempt_id,scope_id,nonce,auth_mode,home_class,owner_pid,owner_creation,owner_sha256,cli_sha256,broker_port,child_pid,child_creation,started,close_command_id,shutdown_trigger,operation_failed,stdout_final_emit_succeeded,receipt,requires_actual_exit_0_or_3,receipt_write_state");
            Need(Object.Equals(receipt["schema"],"p6_r7_task_final_receipt_v1")&&Object.Equals(receipt["attempt_id"],Attempt.ToString("D"))&&Object.Equals(receipt["scope_id"],Scope.ToString("D"))&&Object.Equals(receipt["nonce"],records[0]["nonce"])&&Object.Equals(receipt["auth_mode"],records[0]["auth_mode"])&&Object.Equals(receipt["home_class"],records[0]["home_class"])&&Number(receipt["owner_pid"])==OwnerPid&&Time(receipt["owner_creation"])==OwnerCreation&&Object.Equals(receipt["owner_sha256"],ImageHash)&&Object.Equals(receipt["cli_sha256"],CliHash)&&Number(receipt["broker_port"])==BrokerPort);
            Need(Number(receipt["child_pid"])==ChildPid&&Time(receipt["child_creation"])==ChildCreation&&Object.Equals(receipt["started"],true)&&Number(receipt["close_command_id"])>0&&Object.Equals(receipt["shutdown_trigger"],"close_command")&&Object.Equals(receipt["operation_failed"],false)&&Object.Equals(receipt["stdout_final_emit_succeeded"],true)&&Object.Equals(receipt["requires_actual_exit_0_or_3"],true)&&Object.Equals(receipt["receipt_write_state"],"pending_actual_exit_commit"));
            var closure=receipt["receipt"] as Dictionary<string,object>;Keys(closure,"process_close_observed,job_empty_verified,stdio_eof_verified,rules_absent_verified,handles_closed_verified,helper_exits_verified,cleanup_pending");foreach(string key in new[]{"process_close_observed","job_empty_verified","stdio_eof_verified","handles_closed_verified"})Need(Object.Equals(closure[key],true));foreach(string key in new[]{"rules_absent_verified","helper_exits_verified"})Need(Object.Equals(closure[key],false));Need(Object.Equals(closure["cleanup_pending"],true));return records[0];
        }        internal static void CheckAcl(string directory,string user){
            Need((File.GetAttributes(directory)&FileAttributes.ReparsePoint)==0);DirectorySecurity acl=Directory.GetAccessControl(directory,AccessControlSections.Owner|AccessControlSections.Access);Need(acl.AreAccessRulesProtected&&acl.GetOwner(typeof(SecurityIdentifier)).Value==user);AuthorizationRuleCollection rules=acl.GetAccessRules(true,true,typeof(SecurityIdentifier));Need(rules.Count==3);HashSet<string> required=new HashSet<string>(new string[]{user,"S-1-5-18","S-1-5-32-544"});foreach(FileSystemAccessRule rule in rules)Need(required.Remove(rule.IdentityReference.Value)&&!rule.IsInherited&&rule.AccessControlType==AccessControlType.Allow&&rule.FileSystemRights==FileSystemRights.FullControl&&rule.InheritanceFlags==(InheritanceFlags.ContainerInherit|InheritanceFlags.ObjectInherit)&&rule.PropagationFlags==PropagationFlags.None);Need(required.Count==0);
        }
        sealed class Evidence {
            readonly TaskInflightRetiredResources resources;readonly Dictionary<string,IntPtr> directories=new Dictionary<string,IntPtr>(StringComparer.OrdinalIgnoreCase);readonly List<Tuple<IntPtr,string,string>> files=new List<Tuple<IntPtr,string,string>>();
            internal Evidence(TaskInflightRetiredResources owner){resources=owner;}
            IntPtr Open(string path,bool directory){IntPtr handle=Native.CreateFileW(path,directory?0x80u:0x80000000u,directory?3u:1u,IntPtr.Zero,3,0x00200000u|(directory?0x02000000u:0u),IntPtr.Zero);Win(handle!=IntPtr.Zero&&handle!=new IntPtr(-1));resources.Handles.Own(handle);MatrixNativeApi.VerifyPath(handle,path,directory);return handle;}
            internal void Ancestors(string path){string full=MatrixNativeApi.Canonical(path),root=Path.GetPathRoot(full),current=root;if(!directories.ContainsKey(root))directories.Add(root,Open(root,true));foreach(string part in full.Substring(root.Length).Split('\\')){if(part.Length==0)continue;current=Path.Combine(current,part);if(!directories.ContainsKey(current))directories.Add(current,Open(current,true));}}
            internal IntPtr Pin(string path,string hash){Ancestors(Path.GetDirectoryName(path));IntPtr handle=Open(path,false);files.Add(Tuple.Create(handle,path,hash));Need(MatrixNativeApi.HashHandle(handle)==hash);return handle;}
            internal string Text(IntPtr handle){using(SafeFileHandle wrapper=new SafeFileHandle(handle,false))using(FileStream stream=new FileStream(wrapper,FileAccess.Read)){Need(stream.Length>0&&stream.Length<=16384);stream.Position=0;byte[] bytes=new byte[(int)stream.Length];int done=0;while(done<bytes.Length){int count=stream.Read(bytes,done,bytes.Length-done);Need(count>0);done+=count;}return new UTF8Encoding(false,true).GetString(bytes).TrimEnd('\r','\n');}}
            internal void Verify(string user){foreach(KeyValuePair<string,IntPtr> directory in directories)MatrixNativeApi.VerifyPath(directory.Value,directory.Key,true);foreach(Tuple<IntPtr,string,string> file in files){MatrixNativeApi.VerifyPath(file.Item1,file.Item2,false);Need(MatrixNativeApi.HashHandle(file.Item1)==file.Item3);}CheckAcl(TaskPaths.Root,user);string attempt=DirectoryForAttempt;CheckAcl(attempt,user);string[] entries=Directory.GetFileSystemEntries(attempt);Need(entries.Length==FixedNames.Length);string[] names=new string[entries.Length];for(int i=0;i<entries.Length;i++){names[i]=Path.GetFileName(entries[i]);FileAttributes attr=File.GetAttributes(entries[i]);Need((attr&FileAttributes.ReparsePoint)==0&&((attr&FileAttributes.Directory)!=0)==(names[i]=="project0"||names[i]=="work"));}Need(ExactNames(names));}
        }
        static ulong Creation(IntPtr process){Native.FileTime creation,exit,kernel,user;Win(Native.GetProcessTimes(process,out creation,out exit,out kernel,out user));Need(creation.Ticks>0);return creation.Ticks;}
        static void BoundInactive(TaskInflightRetiredResources resources,uint expectedPid,ulong expectedCreation){IntPtr process=Native.OpenProcess(0x1000|0x100000,false,expectedPid);uint error=unchecked((uint)Marshal.GetLastWin32Error());if(process==IntPtr.Zero){Guard.Win32(Inactive(false,error,0,0,0,expectedPid,expectedCreation),error,"task_inflight_retired_owner_unknown");return;}resources.Handles.Own(process);try{Need(Inactive(true,0,CoordinatorNative.GetProcessId(process),Creation(process),Native.WaitForSingleObject(process,0),expectedPid,expectedCreation));}finally{Need(resources.Handles.Close(process));}}
        static void OwnerInactive(TaskInflightRetiredResources resources){BoundInactive(resources,OwnerPid,OwnerCreation);BoundInactive(resources,ChildPid,ChildCreation);BoundInactive(resources,HelperPid,HelperCreation);}
        static void CandidateIdle(TaskInflightRetiredResources resources,uint pid,string expected){
            IntPtr process=Native.OpenProcess(0x1000|0x100000,false,pid);uint error=unchecked((uint)Marshal.GetLastWin32Error());if(process==IntPtr.Zero){Guard.Win32(error==87,error,"task_inflight_retired_process_unknown");return;}resources.Handles.Own(process);
            try{Need(CoordinatorNative.GetProcessId(process)==pid);ulong created=Creation(process);uint before=Native.WaitForSingleObject(process,0);Need(before==0||before==258);if(before==0)return;StringBuilder image=new StringBuilder(32768);uint size=32768;Win(Native.QueryFullProcessImageNameW(process,0,image,ref size));Need(size>0&&size<32768&&Path.IsPathRooted(image.ToString()));string actual=MatrixNativeApi.Canonical(image.ToString());uint after=Native.WaitForSingleObject(process,0);Need(Creation(process)==created&&CoordinatorNative.GetProcessId(process)==pid&&PathIdle(String.Equals(actual,expected,StringComparison.OrdinalIgnoreCase),after));}finally{Need(resources.Handles.Close(process));}
        }
        static void ImagesInactive(TaskInflightRetiredResources resources){
            string copy=CopiedImage,ownerName=Path.GetFileName(OriginalImage),copyName=Path.GetFileName(copy);IntPtr snapshot=TaskInflightRetiredNative.CreateToolhelp32Snapshot(2,0);Win(snapshot!=IntPtr.Zero&&snapshot!=new IntPtr(-1));resources.Handles.Own(snapshot);
            try{TaskInflightRetiredNative.ProcessEntry entry=new TaskInflightRetiredNative.ProcessEntry{Size=568};bool has=TaskInflightRetiredNative.Process32FirstW(snapshot,ref entry);uint error=unchecked((uint)Marshal.GetLastWin32Error());int count=0;
                while(has){Need(++count<=8192&&entry.Size==568&&!String.IsNullOrEmpty(entry.Name)&&entry.Name.Length<260);if(String.Equals(entry.Name,ownerName,StringComparison.OrdinalIgnoreCase))CandidateIdle(resources,entry.Pid,OriginalImage);else if(String.Equals(entry.Name,copyName,StringComparison.OrdinalIgnoreCase))CandidateIdle(resources,entry.Pid,copy);entry.Size=568;has=TaskInflightRetiredNative.Process32NextW(snapshot,ref entry);error=unchecked((uint)Marshal.GetLastWin32Error());}Guard.Win32(error==18,error,"task_inflight_retired_snapshot_unknown");
            }finally{Need(resources.Handles.Close(snapshot));}
        }
        internal static bool Finish(TaskInflightRetiredResources resources){bool first=resources.CloseVerified();if(!first&&!resources.Empty){lock(Retained){if(!Retained.Contains(resources))Retained.Add(resources);for(int round=0;round<2;round++)for(int i=Retained.Count-1;i>=0;i--){Retained[i].CloseVerified();if(Retained[i].Empty)Retained.RemoveAt(i);}}}return first;}
        internal static Dictionary<string,object> Base(string mode,bool actual){return new Dictionary<string,object>{{"schema","p6_r7_task_inflight_retired_v1"},{"mode",mode},{"attempt_id",Attempt.ToString("D")},{"scope_id",Scope.ToString("D")},{"diagnostic_only",true},{"native_executed",actual},{"cleanup_performed",false},{"cleanup_pending",true},{"historical_cleanup_pending",true},{"historical_http_interrupt_passed",false},{"historical_stop_receipt_verified",false},{"recovery_pending",true},{"inspection_complete",false},{"historical_records_consistent",false},{"current_owner_child_helper_inactive_verified",false},{"current_images_inactive_verified",false},{"files_and_acl_verified",false},{"current_rules_absent_verified",false},{"transaction_ended",false},{"resources_closed",actual?(object)null:true},{"exact_child_closed",null},{"job_active0",null},{"job_current_inspection","not_performed_original_session_unavailable"},{"helper_actual_exit_verified",false},{"filters_deleted_count",0},{"sublayers_deleted_count",0},{"production_isolation_passed",false},{"human_gate_passed",false},{"real_upstream_requests",0},{"model_turns_requested",0},{"failure_stage",0},{"api_status",null}};}
        internal static void CaptureHistory(string actual){
            var a=TaskJson.Parse(actual);Keys(a,"schema,scenario,supervisor_sha256,scope,evidence,actual_native,attempt_id,owner_count,owner_ready,owner_close_calls,config_read,requirements_read,cached_account_read,thread_returned,execution_receipt_verified,turn_binding_verified,stop_receipt_verified,http_create_status,http_turn_status,http_interrupt_status,http_delete_status,http_turn_response_finished,turn_result_held,client_disconnect,request_abort_observed,held_result_released_after_abort,api_abort_close_calls,api_abort_close_binding_verified,api_abort_close_result_verified,api_close_before_abort_observer,deadline_dispatch_fenced,broker_arm_attempts,model_start_attempts,start_dispatched,interrupt_attempts,interrupt_dispatched,interrupt_acknowledged,interrupt_binding_verified,upstream_before_action,exchange_started,exchange_settled,exchange_abort_observed,exchange_inflight_before_action,cancellation_confirmed,local_resources_closed,provider_terminal_status,terminal_before_action,event_terminal_verified,fixed_text_observed,text_empty,text_after_terminal,event_count,host_requests,generic_factory_calls,broker,notifications,exchange_failure,native_failure_present,native_failure_code,native_owner_exit_code,process_close_observed,job_empty_verified,stdio_eof_verified,rules_absent_verified,handles_closed_verified,helper_exits_verified,cleanup_pending,ownership_retained,handler_settled,http_server_closed,host_shutdown_verified,checks_passed,passed,code,failure_stage,production_isolation_passed,human_gate_passed");
            Need(Object.Equals(a["schema"],"p6_r7_http_turn_probe_v1")&&Object.Equals(a["scenario"],"interrupt")&&Object.Equals(a["supervisor_sha256"],ImageHash)&&Object.Equals(a["actual_native"],true)&&Object.Equals(a["attempt_id"],Attempt.ToString("D"))&&Object.Equals(a["native_owner_exit_code"],4)&&Object.Equals(a["failure_stage"],"delete")&&Object.Equals(a["code"],"http_turn_failed"));
            foreach(string key in new[]{"owner_ready","config_read","requirements_read","cached_account_read","thread_returned","execution_receipt_verified","turn_binding_verified","interrupt_acknowledged","interrupt_binding_verified","exchange_abort_observed","event_terminal_verified","process_close_observed","job_empty_verified","stdio_eof_verified","handles_closed_verified","cleanup_pending","ownership_retained","handler_settled","http_server_closed"})Need(Object.Equals(a[key],true));
            foreach(string key in new[]{"stop_receipt_verified","cancellation_confirmed","local_resources_closed","rules_absent_verified","helper_exits_verified","host_shutdown_verified","checks_passed","passed","production_isolation_passed","human_gate_passed"})Need(Object.Equals(a[key],false));
            Need(Object.Equals(a["provider_terminal_status"],"interrupted")&&Object.Equals(a["native_failure_present"],false)&&a["native_failure_code"]==null&&Number(a["owner_count"])==1&&Number(a["start_dispatched"])==1&&Number(a["interrupt_attempts"])==1&&Number(a["interrupt_dispatched"])==1);
        }        // The frozen retired transaction algorithm is reproduced with explicit ownership.
        // Frozen v7 TaskBoundary predicates remain the sole rule ownership checks.
        // This callback proves CURRENT retirement and held evidence, never historical child-close or Job zero.
        internal static int ReadRules(IntPtr engine,Rule[] rules,Guid sublayer,byte[] identifier,ushort weight){
            int found=0;foreach(Rule rule in rules){Guid key=rule.Key;IntPtr pointer=IntPtr.Zero;uint status=InspectionNative.GetFilter(engine,ref key,out pointer);
                try{if(status==0x80320003u){Need(pointer==IntPtr.Zero);continue;}Status(status);Need(pointer!=IntPtr.Zero&&TaskBoundary.ExactFilter((InspectionNative.Filter)Marshal.PtrToStructure(pointer,typeof(InspectionNative.Filter)),rule,sublayer,identifier));found++;}finally{if(pointer!=IntPtr.Zero)Native.FwpmFreeMemory0(ref pointer);}}
            IntPtr sub=IntPtr.Zero;uint code=Native.FwpmSubLayerGetByKey0(engine,ref sublayer,out sub);bool present=code==0;
            try{if(present)Need(sub!=IntPtr.Zero&&TaskBoundary.ExactSublayer((Native.Sublayer)Marshal.PtrToStructure(sub,typeof(Native.Sublayer)),sublayer,weight));else{if(code!=0x80320007u)Status(code);Need(sub==IntPtr.Zero);}}finally{if(sub!=IntPtr.Zero)Native.FwpmFreeMemory0(ref sub);}
            Need(TaskBoundary.ReadbackAllowed(found,present,found>0||present,true));return found;
        }
        internal static bool RemoveFixed(Func<int> read,Action prove,Action begin,Action delete,Action commit,Action abort){
            prove();begin();bool committed=false;
            try{prove();Need(read()==3);delete();prove();commit();committed=true;}finally{if(!committed)abort();}
            prove();Need(read()==0);return true;
        }
        static int Recover(bool apply){
            Dictionary<string,object> report=Base(apply?"apply_cleanup":"inspect",true);report["diagnostic_only"]=!apply;report["caller_check"]="same_directory_owner_elevated_primary_high_non_appcontainer";
            report["historical_failure_verified"]=false;report["transaction_committed"]=false;report["readonly_preflight_complete"]=false;report["rules_before_count"]=null;
            TaskInflightRetiredResources resources=new TaskInflightRetiredResources();int stage=1;bool admitted=false,history=false,idleBefore=false,idleAfter=false,postPins=false,absence=false,ended=false,closed=false,committed=false,transactionStarted=false;uint? error=null;
            try{
                TaskInflightRetiredNative.Layouts();IntPtr token=IntPtr.Zero;Win(Native.OpenProcessToken(Native.GetCurrentProcess(),8,out token));resources.Handles.Own(token);MediumIdentity current=MediumIdentity.Read(token);Need(CallerAccepted(current));
                Evidence evidence=new Evidence(resources);string directory=DirectoryForAttempt;evidence.Ancestors(directory);
                IntPtr prepared=evidence.Pin(Path.Combine(directory,"prepared.json"),PreparedHash),spawning=evidence.Pin(Path.Combine(directory,"spawning.json"),SpawningHash),bound=evidence.Pin(Path.Combine(directory,"bound.json"),BoundHash),ready=evidence.Pin(Path.Combine(directory,"install-ready.json"),LeaseHash),ack=evidence.Pin(Path.Combine(directory,"install-ack.json"),LeaseHash),receipt=evidence.Pin(Path.Combine(directory,"install-receipt.json"),InstallHash),closedJournal=evidence.Pin(Path.Combine(directory,"closed.json"),ClosedHash),final=evidence.Pin(Path.Combine(directory,"final-receipt.json"),FinalHash);
                evidence.Pin(OriginalImage,ImageHash);evidence.Pin(OriginalSource,SourceHash);evidence.Pin(CopiedImage,CliHash);IntPtr actual=evidence.Pin(ActualPath,ActualHash);
                stage=2;History(evidence.Text(prepared),evidence.Text(spawning),evidence.Text(bound),evidence.Text(ready),evidence.Text(ack),evidence.Text(receipt),evidence.Text(closedJournal),evidence.Text(final));CaptureHistory(evidence.Text(actual));report["historical_failure_verified"]=true;history=true;
                ushort weight=AssignedWeight;evidence.Verify(current.User);admitted=true;
                Action prove=delegate{evidence.Verify(current.User);OwnerInactive(resources);ImagesInactive(resources);};stage=3;prove();idleBefore=true;
                IntPtr blob=IntPtr.Zero;byte[] identifier;try{Status(AppIdNative.FwpmGetAppIdFromFileName0(CopiedImage,out blob));identifier=TaskBoundary.CopyBlob(blob);}finally{if(blob!=IntPtr.Zero)Native.FwpmFreeMemory0(ref blob);}
                using(System.Security.Cryptography.SHA256 hash=System.Security.Cryptography.SHA256.Create())Need(BitConverter.ToString(hash.ComputeHash(identifier)).Replace("-","").ToLowerInvariant()==BlobDigest);
                Rule[] rules=TaskBoundary.MakeRules(Scope,BrokerPort);Need(rules.Length==3);Guid sublayer=TaskBoundary.Key(Scope,"sublayer");
                stage=4;Status(Native.FwpmEngineOpen0(null,10,IntPtr.Zero,IntPtr.Zero,out resources.Engine));Need(resources.Engine!=IntPtr.Zero);Func<int> read=delegate{return ReadRules(resources.Engine,rules,sublayer,identifier,weight);};
                stage=5;Status(Native.FwpmTransactionBegin0(resources.Engine,1));resources.Transaction=true;transactionStarted=true;int before=read();prove();uint abortStatus=Native.FwpmTransactionAbort0(resources.Engine);if(abortStatus==0)resources.Transaction=false;else{resources.CloseSucceeded=false;resources.CloseError=abortStatus;}Status(abortStatus);report["readonly_preflight_complete"]=true;report["rules_before_count"]=before;
                if(apply&&before==3){
                    stage=6;RemoveFixed(read,prove,delegate{Status(Native.FwpmTransactionBegin0(resources.Engine,0));resources.Transaction=true;},delegate{
                        foreach(Rule rule in rules){Guid key=rule.Key;Status(Native.FwpmFilterDeleteByKey0(resources.Engine,ref key));}Guid keySub=sublayer;Status(Native.FwpmSubLayerDeleteByKey0(resources.Engine,ref keySub));
                    },delegate{Status(Native.FwpmTransactionCommit0(resources.Engine));resources.Transaction=false;committed=true;report["filters_deleted_count"]=3;report["sublayers_deleted_count"]=1;},delegate{uint status=Native.FwpmTransactionAbort0(resources.Engine);if(status==0)resources.Transaction=false;else{resources.CloseSucceeded=false;resources.CloseError=status;}Status(status);});
                }else Need(before==0||!apply&&before==3);
                stage=7;prove();int after=read();Need(after==0||!apply&&after==3);absence=after==0;ended=!resources.Transaction;prove();idleAfter=true;evidence.Verify(current.User);postPins=true;
            }catch(BoundaryError failure){error=failure.Win32Error;}catch(Win32Exception failure){error=unchecked((uint)failure.NativeErrorCode);}catch(UnauthorizedAccessException){error=5;}catch{}
            finally{
                closed=Finish(resources);ended=transactionStarted&&!resources.Transaction;if(!closed){stage=8;error=resources.CloseError;}
                bool complete=Complete(admitted,history,idleBefore,idleAfter,postPins,true,ended,closed);
                report["failure_stage"]=complete?0:stage;report["api_status"]=error.HasValue?(object)error.Value:null;report["historical_records_consistent"]=history;report["current_owner_child_helper_inactive_verified"]=idleBefore&&idleAfter;report["current_images_inactive_verified"]=idleBefore&&idleAfter;report["files_and_acl_verified"]=admitted&&postPins;report["current_rules_absent_verified"]=absence;report["transaction_ended"]=ended;report["transaction_committed"]=committed;report["cleanup_performed"]=committed;report["resources_closed"]=closed;report["inspection_complete"]=complete;report["recovery_pending"]=!(complete&&absence);
            }
            Console.WriteLine(MatrixRecords.Json(report));return !(bool)report["inspection_complete"]||apply&&(bool)report["recovery_pending"]?2:0;
        }
        internal static int SelfTest(){int assertions=0;TaskInflightRetiredNative.Layouts();assertions++;Need(TaskPaths.Scope(Attempt)==Scope&&TaskBoundary.Key(Scope,"allow4")!=TaskBoundary.Key(Scope,"deny4")&&TaskBoundary.Key(Scope,"deny4")!=TaskBoundary.Key(Scope,"deny6")&&TaskBoundary.Key(Scope,"deny6")!=TaskBoundary.Key(Scope,"sublayer"));assertions++;for(int mask=0;mask<256;mask++){bool[] b=new bool[8];for(int i=0;i<8;i++)b[i]=(mask&(1<<i))!=0;Need(Complete(b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7])==(mask==255));assertions++;}Need(ExactNames((string[])FixedNames.Clone())&&!ExactNames(new string[]{"prepared.json","codex.exe"})&&!ExactNames(null));assertions++;Need(Inactive(false,87,0,0,0)&&!Inactive(false,5,0,0,0)&&!Inactive(true,0,OwnerPid,OwnerCreation,258)&&Inactive(true,0,OwnerPid,OwnerCreation+1,258)&&Inactive(true,0,OwnerPid,OwnerCreation,0)&&!Inactive(true,0,OwnerPid+1,OwnerCreation,0)&&!Inactive(true,0,OwnerPid,OwnerCreation,UInt32.MaxValue));assertions++;Dictionary<string,object> result=Base("self_test",false);result["pure_assertions"]=assertions;Console.WriteLine(MatrixRecords.Json(result));return 0;}
        public static int Main(string[] args){bool actual=false;try{if(args.Length==0||args.Length==1&&args[0]=="--plan"){Console.WriteLine(MatrixRecords.Json(Base("plan",false)));return 0;}if(args.Length==1&&args[0]=="--self-test")return SelfTest();if(args.Length==1&&(args[0]=="--inspect"||args[0]=="--apply-cleanup")){actual=true;return Recover(args[0]=="--apply-cleanup");}}catch{}Dictionary<string,object> rejected=Base("rejected",actual);rejected["failure_stage"]=99;Console.WriteLine(MatrixRecords.Json(rejected));return 2;}
    }
}







