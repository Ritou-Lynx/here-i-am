// One retired v4 Task attempt. Reports current absence separately from unchanged historical failure.
// Never queries a session-local Job: the original session is not available in pinned evidence.
// Joint-compile with pinned v10/v11c/v15/contract01/native; explicit Main below is the only entry.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace HereIAm.R7 {
    internal static class TaskRetiredInspectNative {
        [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]internal struct ProcessEntry {
            internal uint Size,Usage,Pid;internal UIntPtr Heap;internal uint Module,Threads,Parent;internal int Priority;internal uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)]internal string Name;
        }
        [DllImport("kernel32.dll",SetLastError=true)]internal static extern IntPtr CreateToolhelp32Snapshot(uint flags,uint pid);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]internal static extern bool Process32FirstW(IntPtr snapshot,ref ProcessEntry entry);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]internal static extern bool Process32NextW(IntPtr snapshot,ref ProcessEntry entry);
        internal static void Layouts(){TaskRetiredInspectProgram.Need(IntPtr.Size==8&&Marshal.SizeOf(typeof(ProcessEntry))==568&&Marshal.OffsetOf(typeof(ProcessEntry),"Pid").ToInt32()==8&&Marshal.OffsetOf(typeof(ProcessEntry),"Heap").ToInt32()==16&&Marshal.OffsetOf(typeof(ProcessEntry),"Name").ToInt32()==44);InspectionNative.Layouts();}
    }
    internal sealed class TaskRetiredInspectResources {
        internal readonly MatrixHandleLedger Handles;internal IntPtr Engine;internal bool Transaction;internal bool CloseSucceeded=true;internal uint? CloseError;
        readonly Func<IntPtr,uint> abort,closeEngine;
        internal TaskRetiredInspectResources():this(Native.CloseHandle,Native.FwpmTransactionAbort0,Native.FwpmEngineClose0){}
        internal TaskRetiredInspectResources(Func<IntPtr,bool> closeHandle,Func<IntPtr,uint> abortTransaction,Func<IntPtr,uint> close){
            Handles=new MatrixHandleLedger(delegate(IntPtr handle){bool result=closeHandle(handle);if(!result)CloseError=unchecked((uint)Marshal.GetLastWin32Error());return result;});abort=abortTransaction;closeEngine=close;
        }
        internal bool Empty {get{return !Transaction&&Engine==IntPtr.Zero&&Handles.Empty;}}
        internal bool CloseVerified(){
            try{if(Transaction&&Engine!=IntPtr.Zero){uint code=abort(Engine);if(code==0)Transaction=false;else{CloseSucceeded=false;CloseError=code;}}}catch{CloseSucceeded=false;}
            try{if(Engine!=IntPtr.Zero&&!Transaction){uint code=closeEngine(Engine);if(code==0)Engine=IntPtr.Zero;else{CloseSucceeded=false;CloseError=code;}}}catch{CloseSucceeded=false;}
            CloseSucceeded=Handles.CloseAll()&&CloseSucceeded;return CloseSucceeded&&Empty;
        }
    }
    public static class TaskRetiredInspectProgram {
        internal static readonly Guid Attempt=new Guid("9ad201c0-1e9b-4851-873d-0364f52efa53");
        internal const uint OwnerPid=29032;internal const ulong OwnerCreation=134336685056566773UL;internal const int BrokerPort=36836;
        internal const string PreparedHash="800c3922bda6f7a8701fdbff1c2e44d10face7636f034c470fa56eb83c91062c";
        internal const string ReportHash="0768a3bc5cda07568c418347c39d1ac4416d141fc84bc384d0b75842eb60f238";
        internal const string ImageHash="fbe5882461130a93988f7468290c86edeba0e33cfeab8ad3322f1a7a44867f5f";
        internal const string OriginalImage=@"D:\memex\tmp\p6-r7-helper\windows_text_gate_task_executor.v4.exe";
        internal const string OriginalReport=@"D:\memex\tmp\p6-r7-review\native-task-auth-actual-04.json";
        internal const string OriginalSource=@"D:\memex\tmp\p6-r7-review\native-task-executor-04.cs";
        internal const string SourceHash="930b436dd011df2f9299107c063d2a7c7d706a00e974c4bad7e016d0b3a10cb5";
        internal const string CliHash="3d6ca7085c932b62ef4ee4877e92f15b050fb94b2eb8e6c10a346a06248c6004";
        internal const string Root=@"D:\HereIAm-P6-R7-Task-Executor";
        internal static readonly string DirectoryForAttempt=Path.Combine(Root,Attempt.ToString("N"));
        internal static readonly string CopiedImage=Path.Combine(DirectoryForAttempt,"codex.exe");
        internal static readonly Guid Scope=new Guid("da9e8e50-2175-a81c-b7ff-52e2a77773b6");
        static readonly List<TaskRetiredInspectResources> Retained=new List<TaskRetiredInspectResources>();
        internal static void Need(bool value){Guard.Require(value,"task_retired_inspection_rejected");}
        internal static void Status(uint value){Guard.Win32(value==0,value,"task_retired_inspection_api_failed");}
        internal static void Win(bool value){uint code=unchecked((uint)Marshal.GetLastWin32Error());Guard.Win32(value,code,"task_retired_inspection_api_failed");}
        internal static uint Number(object value){Need(value is int||value is long||value is uint);long n=Convert.ToInt64(value);Need(n>=0&&n<=UInt32.MaxValue);return (uint)n;}
        static void Keys(Dictionary<string,object> value,string keys){string[] names=keys.Split(',');Need(value!=null&&value.Count==names.Length);foreach(string name in names)Need(value.ContainsKey(name));}
        internal static bool Inactive(bool opened,uint error,uint returnedPid,ulong creation,uint wait){return !opened?error==87:returnedPid==OwnerPid&&creation>0&&(wait==0||wait==258)&&(creation!=OwnerCreation||wait==0);}
        internal static bool PathIdle(bool samePath,uint wait){return (wait==0||wait==258)&&(!samePath||wait==0);}
        // Read-only elevation additionally requires the current SID to own both exact protected directories.
        // It never projects an elevated/linked token as the historical Medium token.
        internal static bool CallerAccepted(MediumIdentity current){return current!=null&&current.Type==1&&current.Integrity==12288&&current.ElevationType==2&&current.Elevated==1&&current.AppContainer==0&&current.Authentication!=0;}
        internal static bool Complete(bool admitted,bool history,bool idleBefore,bool idleAfter,bool postPins,int queried,int present,bool subQueried,bool subPresent,bool transactionEnded,bool resourcesClosed){return admitted&&history&&idleBefore&&idleAfter&&postPins&&queried==3&&present==0&&subQueried&&!subPresent&&transactionEnded&&resourcesClosed;}
        internal static bool ExactNames(string[] names){if(names==null||names.Length!=4)return false;HashSet<string> expected=new HashSet<string>(new string[]{"prepared.json","codex.exe","work","project0"},StringComparer.OrdinalIgnoreCase);foreach(string name in names)if(name==null||name!=Path.GetFileName(name)||!expected.Remove(name))return false;return expected.Count==0;}
        internal static bool Hex(object value){string s=value as string;if(s==null||s.Length!=64)return false;foreach(char c in s)if(!(c>='0'&&c<='9'||c>='a'&&c<='f'))return false;return true;}
        internal static string History(string prepared,string original){
            Dictionary<string,object> journal=MatrixRecords.Parse(prepared);
            Keys(journal,"schema,attempt_id,scope_id,auth_mode,home_class,nonce,owner_pid,owner_creation,owner_sha256,owner_token_digest,cli_sha256,broker_port,phase,child_pid,child_creation");
            Need(Object.Equals(journal["schema"],"p6_r7_task_owned_v2")&&Object.Equals(journal["attempt_id"],Attempt.ToString("D"))&&Object.Equals(journal["scope_id"],Scope.ToString("D")));
            Need(Object.Equals(journal["auth_mode"],"chatgpt")&&Object.Equals(journal["home_class"],"dedicated_existing")&&Hex(journal["nonce"])&&Hex(journal["owner_token_digest"]));
            Need(Number(journal["owner_pid"])==OwnerPid&&Object.Equals(journal["owner_creation"],OwnerCreation.ToString(System.Globalization.CultureInfo.InvariantCulture))&&Object.Equals(journal["owner_sha256"],ImageHash)&&Object.Equals(journal["cli_sha256"],CliHash)&&Number(journal["broker_port"])==BrokerPort);
            Need(Object.Equals(journal["phase"],"prepared")&&journal["child_pid"]==null&&journal["child_creation"]==null);
            Dictionary<string,object> report=MatrixRecords.Parse(original);
            Keys(report,"schema,attempt_id,scenario,supervisor_sha256,started,config_verified,chatgpt_account_present,thread_verified,turn_started,terminal_status,fixed_text_observed,text_empty,cancellation_confirmed,stop_receipt_verified,process_close_observed,cleanup_pending,host_requests,broker,passed,code,production_isolation_passed,human_gate_passed,native_failure_code,native_owner_exit_code,native_close_receipt");
            Need(Object.Equals(report["schema"],"p6_r7_authenticated_native_probe_v1")&&Object.Equals(report["attempt_id"],Attempt.ToString("D"))&&Object.Equals(report["scenario"],"completed")&&Object.Equals(report["supervisor_sha256"],ImageHash));
            foreach(string key in new[]{"started","config_verified","chatgpt_account_present","thread_verified","turn_started","fixed_text_observed","cancellation_confirmed","stop_receipt_verified","process_close_observed","passed","production_isolation_passed","human_gate_passed"})Need(Object.Equals(report[key],false));
            Need(Object.Equals(report["text_empty"],true)&&Object.Equals(report["cleanup_pending"],true)&&report["terminal_status"]==null&&Number(report["host_requests"])==0&&Number(report["native_owner_exit_code"])==4&&Object.Equals(report["code"],"native_probe_close_unconfirmed")&&Object.Equals(report["native_failure_code"],"task_install_helper_rejected"));
            Dictionary<string,object> receipt=report["native_close_receipt"] as Dictionary<string,object>;
            Keys(receipt,"process_close_observed,job_empty_verified,stdio_eof_verified,rules_absent_verified,handles_closed_verified,helper_exits_verified,cleanup_pending");
            foreach(string key in new[]{"job_empty_verified","handles_closed_verified","cleanup_pending"})Need(Object.Equals(receipt[key],true));
            foreach(string key in new[]{"process_close_observed","stdio_eof_verified","rules_absent_verified","helper_exits_verified"})Need(Object.Equals(receipt[key],false));
            Dictionary<string,object> broker=report["broker"] as Dictionary<string,object>;
            Keys(broker,"admitted_connections,rejected_connections,parsed_requests,metadata_rejections,rejected_requests,upstream_attempts,response_released,drained");
            foreach(string key in new[]{"admitted_connections","rejected_connections","parsed_requests","metadata_rejections","rejected_requests","upstream_attempts"})Need(Number(broker[key])==0);
            Need(Object.Equals(broker["response_released"],false)&&Object.Equals(broker["drained"],true));
            return (string)journal["owner_token_digest"];
        }
        internal static void CheckAcl(string directory,string user){
            Need((File.GetAttributes(directory)&FileAttributes.ReparsePoint)==0);DirectorySecurity acl=Directory.GetAccessControl(directory,AccessControlSections.Owner|AccessControlSections.Access);Need(acl.AreAccessRulesProtected&&acl.GetOwner(typeof(SecurityIdentifier)).Value==user);AuthorizationRuleCollection rules=acl.GetAccessRules(true,true,typeof(SecurityIdentifier));Need(rules.Count==3);HashSet<string> required=new HashSet<string>(new string[]{user,"S-1-5-18","S-1-5-32-544"});foreach(FileSystemAccessRule rule in rules)Need(required.Remove(rule.IdentityReference.Value)&&!rule.IsInherited&&rule.AccessControlType==AccessControlType.Allow&&rule.FileSystemRights==FileSystemRights.FullControl&&rule.InheritanceFlags==(InheritanceFlags.ContainerInherit|InheritanceFlags.ObjectInherit)&&rule.PropagationFlags==PropagationFlags.None);Need(required.Count==0);
        }
        sealed class Evidence {
            readonly TaskRetiredInspectResources resources;readonly Dictionary<string,IntPtr> directories=new Dictionary<string,IntPtr>(StringComparer.OrdinalIgnoreCase);readonly List<Tuple<IntPtr,string,string>> files=new List<Tuple<IntPtr,string,string>>();
            internal Evidence(TaskRetiredInspectResources owner){resources=owner;}
            IntPtr Open(string path,bool directory){IntPtr handle=Native.CreateFileW(path,directory?0x80u:0x80000000u,directory?3u:1u,IntPtr.Zero,3,0x00200000u|(directory?0x02000000u:0u),IntPtr.Zero);Win(handle!=IntPtr.Zero&&handle!=new IntPtr(-1));resources.Handles.Own(handle);MatrixNativeApi.VerifyPath(handle,path,directory);return handle;}
            internal void Ancestors(string path){string full=MatrixNativeApi.Canonical(path),root=Path.GetPathRoot(full),current=root;if(!directories.ContainsKey(root))directories.Add(root,Open(root,true));foreach(string part in full.Substring(root.Length).Split('\\')){if(part.Length==0)continue;current=Path.Combine(current,part);if(!directories.ContainsKey(current))directories.Add(current,Open(current,true));}}
            internal IntPtr Pin(string path,string hash){Ancestors(Path.GetDirectoryName(path));IntPtr handle=Open(path,false);files.Add(Tuple.Create(handle,path,hash));Need(MatrixNativeApi.HashHandle(handle)==hash);return handle;}
            internal string Text(IntPtr handle){using(SafeFileHandle wrapper=new SafeFileHandle(handle,false))using(FileStream stream=new FileStream(wrapper,FileAccess.Read)){Need(stream.Length>0&&stream.Length<=16384);stream.Position=0;byte[] bytes=new byte[(int)stream.Length];int done=0;while(done<bytes.Length){int count=stream.Read(bytes,done,bytes.Length-done);Need(count>0);done+=count;}return new UTF8Encoding(false,true).GetString(bytes).TrimEnd('\r','\n');}}
            internal void Verify(string user){
                foreach(KeyValuePair<string,IntPtr> directory in directories)MatrixNativeApi.VerifyPath(directory.Value,directory.Key,true);
                foreach(Tuple<IntPtr,string,string> file in files){MatrixNativeApi.VerifyPath(file.Item1,file.Item2,false);Need(MatrixNativeApi.HashHandle(file.Item1)==file.Item3);}
                CheckAcl(Root,user);CheckAcl(DirectoryForAttempt,user);
                string[] entries=Directory.GetFileSystemEntries(DirectoryForAttempt);Need(entries.Length==4);string[] names=new string[entries.Length];
                for(int i=0;i<entries.Length;i++){names[i]=Path.GetFileName(entries[i]);FileAttributes attributes=File.GetAttributes(entries[i]);bool directory=String.Equals(names[i],"work",StringComparison.OrdinalIgnoreCase)||String.Equals(names[i],"project0",StringComparison.OrdinalIgnoreCase);Need((attributes&FileAttributes.ReparsePoint)==0&&((attributes&FileAttributes.Directory)!=0)==directory);if(directory){Ancestors(entries[i]);CheckAcl(entries[i],user);}}
                Need(ExactNames(names));
            }
        }
        static ulong Creation(IntPtr process){Native.FileTime creation,exit,kernel,user;Win(Native.GetProcessTimes(process,out creation,out exit,out kernel,out user));Need(creation.Ticks>0);return creation.Ticks;}
        static void OwnerInactive(TaskRetiredInspectResources resources){IntPtr process=Native.OpenProcess(0x1000|0x100000,false,OwnerPid);uint error=unchecked((uint)Marshal.GetLastWin32Error());if(process==IntPtr.Zero){Guard.Win32(Inactive(false,error,0,0,0),error,"task_retired_inspection_owner_unknown");return;}resources.Handles.Own(process);try{Need(Inactive(true,0,CoordinatorNative.GetProcessId(process),Creation(process),Native.WaitForSingleObject(process,0)));}finally{Need(resources.Handles.Close(process));}}
        static void CandidateIdle(TaskRetiredInspectResources resources,uint pid,string expected){
            IntPtr process=Native.OpenProcess(0x1000|0x100000,false,pid);uint error=unchecked((uint)Marshal.GetLastWin32Error());if(process==IntPtr.Zero){Guard.Win32(error==87,error,"task_retired_inspection_process_unknown");return;}resources.Handles.Own(process);
            try{Need(CoordinatorNative.GetProcessId(process)==pid);ulong created=Creation(process);uint before=Native.WaitForSingleObject(process,0);Need(before==0||before==258);if(before==0)return;StringBuilder image=new StringBuilder(32768);uint size=32768;Win(Native.QueryFullProcessImageNameW(process,0,image,ref size));Need(size>0&&size<32768&&Path.IsPathRooted(image.ToString()));string actual=MatrixNativeApi.Canonical(image.ToString());uint after=Native.WaitForSingleObject(process,0);Need(Creation(process)==created&&CoordinatorNative.GetProcessId(process)==pid&&PathIdle(String.Equals(actual,expected,StringComparison.OrdinalIgnoreCase),after));}finally{Need(resources.Handles.Close(process));}
        }
        static void ImagesInactive(TaskRetiredInspectResources resources){
            string copy=CopiedImage,ownerName=Path.GetFileName(OriginalImage),copyName=Path.GetFileName(copy);IntPtr snapshot=TaskRetiredInspectNative.CreateToolhelp32Snapshot(2,0);Win(snapshot!=IntPtr.Zero&&snapshot!=new IntPtr(-1));resources.Handles.Own(snapshot);
            try{TaskRetiredInspectNative.ProcessEntry entry=new TaskRetiredInspectNative.ProcessEntry{Size=568};bool has=TaskRetiredInspectNative.Process32FirstW(snapshot,ref entry);uint error=unchecked((uint)Marshal.GetLastWin32Error());int count=0;
                while(has){Need(++count<=8192&&entry.Size==568&&!String.IsNullOrEmpty(entry.Name)&&entry.Name.Length<260);if(String.Equals(entry.Name,ownerName,StringComparison.OrdinalIgnoreCase))CandidateIdle(resources,entry.Pid,OriginalImage);else if(String.Equals(entry.Name,copyName,StringComparison.OrdinalIgnoreCase))CandidateIdle(resources,entry.Pid,copy);entry.Size=568;has=TaskRetiredInspectNative.Process32NextW(snapshot,ref entry);error=unchecked((uint)Marshal.GetLastWin32Error());}Guard.Win32(error==18,error,"task_retired_inspection_snapshot_unknown");
            }finally{Need(resources.Handles.Close(snapshot));}
        }
        internal static bool Finish(TaskRetiredInspectResources resources){bool first=resources.CloseVerified();if(!first&&!resources.Empty){lock(Retained){if(!Retained.Contains(resources))Retained.Add(resources);for(int round=0;round<2;round++)for(int i=Retained.Count-1;i>=0;i--){Retained[i].CloseVerified();if(Retained[i].Empty)Retained.RemoveAt(i);}}}return first;}

        internal static bool Presence(uint status,IntPtr pointer,bool sublayer){
            uint missing=sublayer?0x80320007u:0x80320003u;
            if(status==missing){Need(pointer==IntPtr.Zero);return false;}
            Status(status);Need(pointer!=IntPtr.Zero);return true;
        }
        internal static Dictionary<string,object> Base(string mode,bool actual){return new Dictionary<string,object>{
            {"schema","p6_r7_task_retired_readonly_inspection_v1"},{"mode",mode},{"attempt_id",Attempt.ToString("D")},{"scope_id",Scope.ToString("D")},
            {"prepared_sha256",PreparedHash},{"historical_report_sha256",ReportHash},{"owner_image_sha256",ImageHash},{"cli_image_sha256",CliHash},
            {"diagnostic_only",true},{"native_executed",actual},{"cleanup_performed",false},{"cleanup_pending",true},{"inspection_complete",false},
            {"historical_evidence_verified",false},{"historical_cleanup_pending",null},{"historical_job_empty_verified",null},{"historical_handles_closed_verified",null},
            {"historical_stop_receipt_verified",null},{"historical_process_close_observed",null},{"historical_stdio_eof_verified",null},{"historical_helper_exits_verified",null},
            {"job_current_inspection","not_performed_original_session_unavailable"},{"job_current_absent_verified",null},{"job_current_empty_verified",null},
            {"current_owner_inactive_verified",false},{"current_images_inactive_verified",false},{"files_and_acl_verified",false},{"current_rules_absent_verified",false},
            {"transaction_ended",false},{"resources_closed",actual?(object)null:true},{"stop_receipt_verified",false},{"filters_deleted_count",0},{"sublayers_deleted_count",0},
            {"production_isolation_passed",false},{"human_gate_passed",false},{"real_upstream_requests",0},{"model_turns_requested",0},{"failure_stage",0},{"api_status",null}};}
        static int Inspect(){
            Dictionary<string,object> report=Base("inspect_retired_fixed_elevated_readonly",true);
            report["caller_check"]="same_directory_owner_elevated_readonly";
            TaskRetiredInspectResources resources=new TaskRetiredInspectResources();
            int stage=1,checkedFilters=0,presentFilters=0;
            bool subChecked=false,subPresent=false,admitted=false,history=false,idleBefore=false,idleAfter=false,postPins=false,ended=false,closed=false;
            uint? error=null;object[] filters=new object[3];string[] roles={"allow4","deny4","deny6"};
            Rule[] rules=CoordinatorBoundary.MakeRules(Scope,BrokerPort);Guid sublayer=CoordinatorBoundary.Key(Scope,"sublayer");
            for(int i=0;i<3;i++)filters[i]=new Dictionary<string,object>{{"role",roles[i]},{"key",rules[i].Key.ToString("D")},{"present",null}};
            try{
                TaskRetiredInspectNative.Layouts();IntPtr token=IntPtr.Zero;bool tokenOpened=Native.OpenProcessToken(Native.GetCurrentProcess(),8,out token);uint tokenError=unchecked((uint)Marshal.GetLastWin32Error());if(token!=IntPtr.Zero)resources.Handles.Own(token);Guard.Win32(tokenOpened,tokenError,"task_retired_inspection_token_failed");Need(token!=IntPtr.Zero);
                MediumIdentity current=MediumIdentity.Read(token);Need(CallerAccepted(current));
                Evidence evidence=new Evidence(resources);evidence.Ancestors(DirectoryForAttempt);
                IntPtr prepared=evidence.Pin(Path.Combine(DirectoryForAttempt,"prepared.json"),PreparedHash),original=evidence.Pin(OriginalReport,ReportHash);
                evidence.Pin(OriginalImage,ImageHash);evidence.Pin(CopiedImage,CliHash);evidence.Pin(OriginalSource,SourceHash);
                stage=2;History(evidence.Text(prepared),evidence.Text(original));history=true;evidence.Verify(current.User);admitted=true;
                stage=3;OwnerInactive(resources);ImagesInactive(resources);idleBefore=true;
                stage=4;Status(Native.FwpmEngineOpen0(null,10,IntPtr.Zero,IntPtr.Zero,out resources.Engine));Need(resources.Engine!=IntPtr.Zero);
                stage=5;Status(Native.FwpmTransactionBegin0(resources.Engine,1));resources.Transaction=true;
                stage=6;
                for(int i=0;i<3;i++){
                    Guid key=rules[i].Key;IntPtr pointer=IntPtr.Zero;uint status=InspectionNative.GetFilter(resources.Engine,ref key,out pointer);
                    try{bool present=Presence(status,pointer,false);checkedFilters++;if(present)presentFilters++;((Dictionary<string,object>)filters[i])["present"]=present;}
                    finally{if(pointer!=IntPtr.Zero)Native.FwpmFreeMemory0(ref pointer);}
                }
                IntPtr sub=IntPtr.Zero;uint subStatus=Native.FwpmSubLayerGetByKey0(resources.Engine,ref sublayer,out sub);
                try{subPresent=Presence(subStatus,sub,true);subChecked=true;}finally{if(sub!=IntPtr.Zero)Native.FwpmFreeMemory0(ref sub);}
                stage=7;evidence.Verify(current.User);OwnerInactive(resources);ImagesInactive(resources);idleAfter=true;
                Status(Native.FwpmTransactionAbort0(resources.Engine));resources.Transaction=false;ended=true;evidence.Verify(current.User);postPins=true;
            }catch(BoundaryError failure){error=failure.Win32Error;}catch(Win32Exception failure){error=unchecked((uint)failure.NativeErrorCode);}catch(UnauthorizedAccessException){error=5;}catch{}
            finally{
                closed=Finish(resources);if(!closed){stage=8;error=resources.CloseError;}
                bool complete=Complete(admitted,history,idleBefore,idleAfter,postPins,checkedFilters,presentFilters,subChecked,subPresent,ended,closed);
                report["failure_stage"]=complete?0:stage;report["api_status"]=error.HasValue?(object)error.Value:null;
                report["filters"]=filters;report["filters_checked_count"]=checkedFilters;report["filters_present_count"]=presentFilters;
                report["sublayer_key"]=sublayer.ToString("D");report["sublayer_present"]=subChecked?(object)subPresent:null;
                SetHistoryAndOutcome(report,history,complete);
                report["current_owner_inactive_verified"]=idleBefore&&idleAfter;report["current_images_inactive_verified"]=idleBefore&&idleAfter;
                report["files_and_acl_verified"]=admitted&&postPins;
                report["transaction_ended"]=ended;report["resources_closed"]=closed;
            }
            Console.WriteLine(MatrixRecords.Json(report));return (bool)report["inspection_complete"]?0:2;
        }
        internal static void SetHistoryAndOutcome(Dictionary<string,object> report,bool history,bool complete){
            // Current absence never repairs the pinned historical failure receipt.
            Need(!complete||history);report["historical_evidence_verified"]=history;
            if(history){report["historical_cleanup_pending"]=true;report["historical_job_empty_verified"]=true;report["historical_handles_closed_verified"]=true;report["historical_stop_receipt_verified"]=false;report["historical_process_close_observed"]=false;report["historical_stdio_eof_verified"]=false;report["historical_helper_exits_verified"]=false;}
            report["inspection_complete"]=complete;report["current_rules_absent_verified"]=complete;report["cleanup_pending"]=true;
        }
        internal static int SelfTest(){
            int assertions=0;TaskRetiredInspectNative.Layouts();assertions++;
            for(int mask=0;mask<1024;mask++){bool[] b=new bool[10];for(int i=0;i<10;i++)b[i]=(mask&(1<<i))!=0;bool actual=Complete(b[0],b[1],b[2],b[3],b[4],b[5]?3:2,b[6]?0:1,b[7],false,b[8],b[9]);Need(actual==(mask==1023));assertions++;}
            Need(ExactNames(new[]{"prepared.json","codex.exe","work","project0"})&&!ExactNames(new[]{"prepared.json","codex.exe","work","bound.json"}));assertions++;
            Need(Inactive(false,87,0,0,0)&&!Inactive(false,5,0,0,0)&&!Inactive(true,0,OwnerPid,OwnerCreation,258)&&Inactive(true,0,OwnerPid,OwnerCreation+1,258)&&Inactive(true,0,OwnerPid,OwnerCreation,0)&&!Inactive(true,0,OwnerPid+1,OwnerCreation,0)&&!Inactive(true,0,OwnerPid,OwnerCreation,UInt32.MaxValue));assertions++;
            Need(CoordinatorBoundary.Key(Scope,"allow4")==new Guid("5b2c4ed6-03e9-484f-263c-2b5b8ba2b518")&&CoordinatorBoundary.Key(Scope,"deny4")==new Guid("491941d9-fa2f-354f-49e7-802660809c7a")&&CoordinatorBoundary.Key(Scope,"deny6")==new Guid("728f8811-9d31-642d-604b-f9d0e6be5ee9")&&CoordinatorBoundary.Key(Scope,"sublayer")==new Guid("c5f670a3-d2fc-3ee6-a660-3f18b9a260ff"));assertions++;
            Dictionary<string,object> result=Base("self_test",false);result["pure_assertions"]=assertions;Console.WriteLine(MatrixRecords.Json(result));return 0;
        }
        public static int Main(string[] args){
            bool actual=false;
            try{
                if(args.Length==0||args.Length==1&&args[0]=="--plan"){Console.WriteLine(MatrixRecords.Json(Base("plan",false)));return 0;}
                if(args.Length==1&&args[0]=="--self-test")return SelfTest();
                if(args.Length==1&&args[0]=="--inspect-retired-fixed-elevated-readonly"){actual=true;return Inspect();}
            }catch{}
            Dictionary<string,object> rejected=Base("rejected",actual);rejected["failure_stage"]=99;Console.WriteLine(MatrixRecords.Json(rejected));return 2;
        }
    }
}
