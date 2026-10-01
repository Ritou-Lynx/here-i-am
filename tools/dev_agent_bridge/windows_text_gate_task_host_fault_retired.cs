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
    internal static class TaskHostFaultRetiredNative {
        [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]internal struct ProcessEntry {
            internal uint Size,Usage,Pid;internal UIntPtr Heap;internal uint Module,Threads,Parent;internal int Priority;internal uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)]internal string Name;
        }
        [DllImport("kernel32.dll",SetLastError=true)]internal static extern IntPtr CreateToolhelp32Snapshot(uint flags,uint pid);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]internal static extern bool Process32FirstW(IntPtr snapshot,ref ProcessEntry entry);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]internal static extern bool Process32NextW(IntPtr snapshot,ref ProcessEntry entry);
        internal static void Layouts(){TaskHostFaultRetiredProgram.Need(IntPtr.Size==8&&Marshal.SizeOf(typeof(ProcessEntry))==568&&Marshal.OffsetOf(typeof(ProcessEntry),"Pid").ToInt32()==8&&Marshal.OffsetOf(typeof(ProcessEntry),"Heap").ToInt32()==16&&Marshal.OffsetOf(typeof(ProcessEntry),"Name").ToInt32()==44);InspectionNative.Layouts();}
    }
    internal sealed class TaskHostFaultRetiredResources {
        internal readonly MatrixHandleLedger Handles;internal IntPtr Engine;internal bool Transaction;internal bool CloseSucceeded=true;internal uint? CloseError;
        readonly Func<IntPtr,uint> abort,closeEngine;
        internal TaskHostFaultRetiredResources():this(Native.CloseHandle,Native.FwpmTransactionAbort0,Native.FwpmEngineClose0){}
        internal TaskHostFaultRetiredResources(Func<IntPtr,bool> closeHandle,Func<IntPtr,uint> abortTransaction,Func<IntPtr,uint> close){
            Handles=new MatrixHandleLedger(delegate(IntPtr handle){bool result=closeHandle(handle);if(!result)CloseError=unchecked((uint)Marshal.GetLastWin32Error());return result;});abort=abortTransaction;closeEngine=close;
        }
        internal bool Empty {get{return !Transaction&&Engine==IntPtr.Zero&&Handles.Empty;}}
        internal bool CloseVerified(){
            try{if(Transaction&&Engine!=IntPtr.Zero){uint code=abort(Engine);if(code==0)Transaction=false;else{CloseSucceeded=false;CloseError=code;}}}catch{CloseSucceeded=false;}
            try{if(Engine!=IntPtr.Zero&&!Transaction){uint code=closeEngine(Engine);if(code==0)Engine=IntPtr.Zero;else{CloseSucceeded=false;CloseError=code;}}}catch{CloseSucceeded=false;}
            CloseSucceeded=Handles.CloseAll()&&CloseSucceeded;return CloseSucceeded&&Empty;
        }
    }
    public static class TaskHostFaultRetiredProgram {
        internal static readonly Guid Attempt=new Guid("796e21fa-e29f-45c6-a856-bae0b8e6e6c3");
        internal static readonly Guid Scope=new Guid("fe8b92a0-0b63-b62f-ce9f-75b96a7b6883");
        internal const uint OwnerPid=56908,ChildPid=38784,HelperPid=47304;
        internal const ulong OwnerCreation=134336784614518281UL,ChildCreation=134336784695544734UL,HelperCreation=134336784674193355UL;
        internal const int BrokerPort=59838;internal const ushort AssignedWeight=32766;
        internal const string BlobDigest="b5449e34dd6fed323c777bd2ccf27cb6b9c5cf18a9268ba44c2fdcbbda314a07";
        internal const string PreparedHash="baae829e3d686c3d87179e90d7373c7114b5577cc6ee6ae1c2a52ed46ed47bae";
        internal const string SpawningHash="57495f112ccfe51e6801332aae3bb57854eae4efb19c89180819318381356d9c";
        internal const string BoundHash="b2620356467f8180033b7cc13e1cfe0ee1c2c74894df63964e50a8e88fc72dfc";
        internal const string InstallHash="011b949564d5b965bb8c622c9ea43cfa7b2730e060e6dfb4bfd386748bbc161b";
        internal const string LeaseHash="b7d2d4eb29df52664f44246347a67b115ec3101850a1f733ff683688418d69b7";
        internal const string ImageHash="73cbe6277fd4bf5b92bdc3189e00eee5ce78f208d6037d8d16a14df9bde4bc4e";
        internal const string CliHash="3d6ca7085c932b62ef4ee4877e92f15b050fb94b2eb8e6c10a346a06248c6004";
        internal const string SourceHash="47d3da743598e17f92f2b3b7764226376097d015a7e337c3f27a9e7d8fbd5f92";
        internal const string ActualHash="42498f1032a8803212ec7dc52d15243ec0daeac3e57660fba8902846c1961bbe";
        internal const string OriginalImage=@"D:\memex\tmp\p6-r7-helper\windows_text_gate_task_executor.v7.exe";
        internal const string OriginalSource=@"D:\memex\tmp\p6-r7-review\native-task-executor-07.cs";
        internal const string ActualPath=@"D:\memex\tmp\p6-r7-review\native-host-fault-actual-02.json";
        internal static readonly string DirectoryForAttempt=Path.Combine(@"D:\HereIAm-P6-R7-Task-Executor",Attempt.ToString("N"));
        internal static readonly string CopiedImage=Path.Combine(DirectoryForAttempt,"codex.exe");
        internal static readonly string[] FixedNames=new string[]{"project0","work","bound.json","codex.exe","install-ack.json","install-ready.json","install-receipt.json","prepared.json","spawning.json"};
        static readonly List<TaskHostFaultRetiredResources> Retained=new List<TaskHostFaultRetiredResources>();
        internal static void Need(bool value){Guard.Require(value,"task_host_fault_retired_rejected");}
        internal static void Status(uint value){Guard.Win32(value==0,value,"task_host_fault_retired_api_failed");}
        internal static void Win(bool value){uint code=unchecked((uint)Marshal.GetLastWin32Error());Guard.Win32(value,code,"task_host_fault_retired_api_failed");}
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
        internal static Dictionary<string,object> History(string prepared,string spawning,string bound,string install,string ready,string ack){
            string[] texts={prepared,spawning,bound};Dictionary<string,object>[] records=new Dictionary<string,object>[3];
            for(int i=0;i<3;i++){
                var j=TaskJson.Parse(texts[i]);records[i]=j;Keys(j,"schema,attempt_id,scope_id,auth_mode,home_class,nonce,owner_pid,owner_creation,owner_sha256,owner_token_digest,cli_sha256,broker_port,phase,child_pid,child_creation");
                Need(Object.Equals(j["schema"],"p6_r7_task_owned_v2")&&Object.Equals(j["attempt_id"],Attempt.ToString("D"))&&Object.Equals(j["scope_id"],Scope.ToString("D"))&&Object.Equals(j["auth_mode"],"chatgpt")&&Object.Equals(j["home_class"],"dedicated_existing")&&TaskCheck.Hex(j["nonce"])&&TaskCheck.Hex(j["owner_token_digest"]));
                Need(Number(j["owner_pid"])==OwnerPid&&Time(j["owner_creation"])==OwnerCreation&&Object.Equals(j["owner_sha256"],ImageHash)&&Object.Equals(j["cli_sha256"],CliHash)&&Number(j["broker_port"])==BrokerPort);
                Need(Object.Equals(j["phase"],new[]{"prepared","spawning","bound"}[i]));
                if(i<2)Need(j["child_pid"]==null&&j["child_creation"]==null);else Need(Number(j["child_pid"])==ChildPid&&Time(j["child_creation"])==ChildCreation);
                if(i>0)foreach(string key in new[]{"nonce","owner_token_digest"})Need(Object.Equals(j[key],records[0][key]));
            }
            var lease=TaskJson.Parse(ready);Keys(lease,"schema,attempt_id,scope_id,auth_mode,home_class,nonce,action,helper_pid,helper_creation,helper_sha256,helper_token_digest");Need(TaskCheck.Hex(lease["helper_token_digest"]));
            string expectedLease=TaskJson.Json(TaskRecords.Lease(records[0],"install",HelperPid,HelperCreation,(string)lease["helper_token_digest"]));
            Need(TaskJson.Json(lease)==expectedLease&&TaskJson.Json(TaskJson.Parse(ack))==expectedLease);
            TaskRecords.VerifyReceipt(install,records[0],"install",HelperPid,HelperCreation,BlobDigest,AssignedWeight);return records[0];
        }
        internal static void CheckAcl(string directory,string user){
            Need((File.GetAttributes(directory)&FileAttributes.ReparsePoint)==0);DirectorySecurity acl=Directory.GetAccessControl(directory,AccessControlSections.Owner|AccessControlSections.Access);Need(acl.AreAccessRulesProtected&&acl.GetOwner(typeof(SecurityIdentifier)).Value==user);AuthorizationRuleCollection rules=acl.GetAccessRules(true,true,typeof(SecurityIdentifier));Need(rules.Count==3);HashSet<string> required=new HashSet<string>(new string[]{user,"S-1-5-18","S-1-5-32-544"});foreach(FileSystemAccessRule rule in rules)Need(required.Remove(rule.IdentityReference.Value)&&!rule.IsInherited&&rule.AccessControlType==AccessControlType.Allow&&rule.FileSystemRights==FileSystemRights.FullControl&&rule.InheritanceFlags==(InheritanceFlags.ContainerInherit|InheritanceFlags.ObjectInherit)&&rule.PropagationFlags==PropagationFlags.None);Need(required.Count==0);
        }
        sealed class Evidence {
            readonly TaskHostFaultRetiredResources resources;readonly Dictionary<string,IntPtr> directories=new Dictionary<string,IntPtr>(StringComparer.OrdinalIgnoreCase);readonly List<Tuple<IntPtr,string,string>> files=new List<Tuple<IntPtr,string,string>>();
            internal Evidence(TaskHostFaultRetiredResources owner){resources=owner;}
            IntPtr Open(string path,bool directory){IntPtr handle=Native.CreateFileW(path,directory?0x80u:0x80000000u,directory?3u:1u,IntPtr.Zero,3,0x00200000u|(directory?0x02000000u:0u),IntPtr.Zero);Win(handle!=IntPtr.Zero&&handle!=new IntPtr(-1));resources.Handles.Own(handle);MatrixNativeApi.VerifyPath(handle,path,directory);return handle;}
            internal void Ancestors(string path){string full=MatrixNativeApi.Canonical(path),root=Path.GetPathRoot(full),current=root;if(!directories.ContainsKey(root))directories.Add(root,Open(root,true));foreach(string part in full.Substring(root.Length).Split('\\')){if(part.Length==0)continue;current=Path.Combine(current,part);if(!directories.ContainsKey(current))directories.Add(current,Open(current,true));}}
            internal IntPtr Pin(string path,string hash){Ancestors(Path.GetDirectoryName(path));IntPtr handle=Open(path,false);files.Add(Tuple.Create(handle,path,hash));Need(MatrixNativeApi.HashHandle(handle)==hash);return handle;}
            internal string Text(IntPtr handle){using(SafeFileHandle wrapper=new SafeFileHandle(handle,false))using(FileStream stream=new FileStream(wrapper,FileAccess.Read)){Need(stream.Length>0&&stream.Length<=16384);stream.Position=0;byte[] bytes=new byte[(int)stream.Length];int done=0;while(done<bytes.Length){int count=stream.Read(bytes,done,bytes.Length-done);Need(count>0);done+=count;}return new UTF8Encoding(false,true).GetString(bytes).TrimEnd('\r','\n');}}
            internal void Verify(string user){foreach(KeyValuePair<string,IntPtr> directory in directories)MatrixNativeApi.VerifyPath(directory.Value,directory.Key,true);foreach(Tuple<IntPtr,string,string> file in files){MatrixNativeApi.VerifyPath(file.Item1,file.Item2,false);Need(MatrixNativeApi.HashHandle(file.Item1)==file.Item3);}CheckAcl(TaskPaths.Root,user);string attempt=DirectoryForAttempt;CheckAcl(attempt,user);string[] entries=Directory.GetFileSystemEntries(attempt);Need(entries.Length==FixedNames.Length);string[] names=new string[entries.Length];for(int i=0;i<entries.Length;i++){names[i]=Path.GetFileName(entries[i]);FileAttributes attr=File.GetAttributes(entries[i]);Need((attr&FileAttributes.ReparsePoint)==0&&((attr&FileAttributes.Directory)!=0)==(names[i]=="project0"||names[i]=="work"));}Need(ExactNames(names));}
        }
        static ulong Creation(IntPtr process){Native.FileTime creation,exit,kernel,user;Win(Native.GetProcessTimes(process,out creation,out exit,out kernel,out user));Need(creation.Ticks>0);return creation.Ticks;}
        static void BoundInactive(TaskHostFaultRetiredResources resources,uint expectedPid,ulong expectedCreation){IntPtr process=Native.OpenProcess(0x1000|0x100000,false,expectedPid);uint error=unchecked((uint)Marshal.GetLastWin32Error());if(process==IntPtr.Zero){Guard.Win32(Inactive(false,error,0,0,0,expectedPid,expectedCreation),error,"task_host_fault_retired_owner_unknown");return;}resources.Handles.Own(process);try{Need(Inactive(true,0,CoordinatorNative.GetProcessId(process),Creation(process),Native.WaitForSingleObject(process,0),expectedPid,expectedCreation));}finally{Need(resources.Handles.Close(process));}}
        static void OwnerInactive(TaskHostFaultRetiredResources resources){BoundInactive(resources,OwnerPid,OwnerCreation);BoundInactive(resources,ChildPid,ChildCreation);BoundInactive(resources,HelperPid,HelperCreation);}
        static void CandidateIdle(TaskHostFaultRetiredResources resources,uint pid,string expected){
            IntPtr process=Native.OpenProcess(0x1000|0x100000,false,pid);uint error=unchecked((uint)Marshal.GetLastWin32Error());if(process==IntPtr.Zero){Guard.Win32(error==87,error,"task_host_fault_retired_process_unknown");return;}resources.Handles.Own(process);
            try{Need(CoordinatorNative.GetProcessId(process)==pid);ulong created=Creation(process);uint before=Native.WaitForSingleObject(process,0);Need(before==0||before==258);if(before==0)return;StringBuilder image=new StringBuilder(32768);uint size=32768;Win(Native.QueryFullProcessImageNameW(process,0,image,ref size));Need(size>0&&size<32768&&Path.IsPathRooted(image.ToString()));string actual=MatrixNativeApi.Canonical(image.ToString());uint after=Native.WaitForSingleObject(process,0);Need(Creation(process)==created&&CoordinatorNative.GetProcessId(process)==pid&&PathIdle(String.Equals(actual,expected,StringComparison.OrdinalIgnoreCase),after));}finally{Need(resources.Handles.Close(process));}
        }
        static void ImagesInactive(TaskHostFaultRetiredResources resources){
            string copy=CopiedImage,ownerName=Path.GetFileName(OriginalImage),copyName=Path.GetFileName(copy);IntPtr snapshot=TaskHostFaultRetiredNative.CreateToolhelp32Snapshot(2,0);Win(snapshot!=IntPtr.Zero&&snapshot!=new IntPtr(-1));resources.Handles.Own(snapshot);
            try{TaskHostFaultRetiredNative.ProcessEntry entry=new TaskHostFaultRetiredNative.ProcessEntry{Size=568};bool has=TaskHostFaultRetiredNative.Process32FirstW(snapshot,ref entry);uint error=unchecked((uint)Marshal.GetLastWin32Error());int count=0;
                while(has){Need(++count<=8192&&entry.Size==568&&!String.IsNullOrEmpty(entry.Name)&&entry.Name.Length<260);if(String.Equals(entry.Name,ownerName,StringComparison.OrdinalIgnoreCase))CandidateIdle(resources,entry.Pid,OriginalImage);else if(String.Equals(entry.Name,copyName,StringComparison.OrdinalIgnoreCase))CandidateIdle(resources,entry.Pid,copy);entry.Size=568;has=TaskHostFaultRetiredNative.Process32NextW(snapshot,ref entry);error=unchecked((uint)Marshal.GetLastWin32Error());}Guard.Win32(error==18,error,"task_host_fault_retired_snapshot_unknown");
            }finally{Need(resources.Handles.Close(snapshot));}
        }
        internal static bool Finish(TaskHostFaultRetiredResources resources){bool first=resources.CloseVerified();if(!first&&!resources.Empty){lock(Retained){if(!Retained.Contains(resources))Retained.Add(resources);for(int round=0;round<2;round++)for(int i=Retained.Count-1;i>=0;i--){Retained[i].CloseVerified();if(Retained[i].Empty)Retained.RemoveAt(i);}}}return first;}
        internal static Dictionary<string,object> Base(string mode,bool actual){return new Dictionary<string,object>{{"schema","p6_r7_task_host_fault_retired_v1"},{"mode",mode},{"attempt_id",Attempt.ToString("D")},{"scope_id",Scope.ToString("D")},{"diagnostic_only",true},{"native_executed",actual},{"cleanup_performed",false},{"cleanup_pending",true},{"historical_cleanup_pending",true},{"historical_host_fault_passed",false},{"historical_stop_receipt_verified",false},{"recovery_pending",true},{"inspection_complete",false},{"historical_records_consistent",false},{"current_owner_child_helper_inactive_verified",false},{"current_images_inactive_verified",false},{"files_and_acl_verified",false},{"current_rules_absent_verified",false},{"transaction_ended",false},{"resources_closed",actual?(object)null:true},{"exact_child_closed",null},{"job_active0",null},{"job_current_inspection","not_performed_original_session_unavailable"},{"helper_actual_exit_verified",false},{"filters_deleted_count",0},{"sublayers_deleted_count",0},{"production_isolation_passed",false},{"human_gate_passed",false},{"real_upstream_requests",0},{"model_turns_requested",0},{"failure_stage",0},{"api_status",null}};}
        internal static void CaptureHistory(string actual){
            var a=TaskJson.Parse(actual);Keys(a,"schema,actual_native,passed,requires_actual_witness_exit_0,receipt_write_state,node_binding_verified,native_binding_verified,node_killed,native_exit_code,final_binding_verified,input_eof_observed,stdout_final_failed,cleanup_pending,native_cleanup_pending,graceful_fallback_confirmed,witness_handles_closed,held_process_handles_closed,file_handles_closed,reader_tasks_joined,managed_streams_disposed,code,production_isolation_passed,human_gate_passed,native_receipt,native_shutdown_trigger,failure_stage,node_pid,node_creation,attempt_id,native_pid,native_creation");
            Need(Object.Equals(a["schema"],"p6_r7_host_fault_witness_v1")&&Object.Equals(a["attempt_id"],Attempt.ToString("D"))&&Object.Equals(a["failure_stage"],"native_exit")&&Object.Equals(a["code"],"host_fault_unconfirmed")&&Object.Equals(a["receipt_write_state"],"pending_actual_witness_exit_commit"));
            foreach(string k in new[]{"actual_native","requires_actual_witness_exit_0","node_binding_verified","native_binding_verified","node_killed","cleanup_pending","native_cleanup_pending","witness_handles_closed","held_process_handles_closed","file_handles_closed","reader_tasks_joined","managed_streams_disposed"})Need(Object.Equals(a[k],true));
            foreach(string k in new[]{"passed","final_binding_verified","input_eof_observed","stdout_final_failed","graceful_fallback_confirmed","production_isolation_passed","human_gate_passed"})Need(Object.Equals(a[k],false));
            Need(a["native_receipt"]==null&&a["native_shutdown_trigger"]==null&&Number(a["native_exit_code"])==0&&Number(a["native_pid"])==OwnerPid&&Time(a["native_creation"])==OwnerCreation&&Number(a["node_pid"])==6400&&Time(a["node_creation"])==134336784613592845UL);
        }
        // The frozen retired transaction algorithm is reproduced with explicit ownership.
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
            TaskHostFaultRetiredResources resources=new TaskHostFaultRetiredResources();int stage=1;bool admitted=false,history=false,idleBefore=false,idleAfter=false,postPins=false,absence=false,ended=false,closed=false,committed=false,transactionStarted=false;uint? error=null;
            try{
                TaskHostFaultRetiredNative.Layouts();IntPtr token=IntPtr.Zero;Win(Native.OpenProcessToken(Native.GetCurrentProcess(),8,out token));resources.Handles.Own(token);MediumIdentity current=MediumIdentity.Read(token);Need(CallerAccepted(current));
                Evidence evidence=new Evidence(resources);string directory=DirectoryForAttempt;evidence.Ancestors(directory);
                IntPtr prepared=evidence.Pin(Path.Combine(directory,"prepared.json"),PreparedHash),spawning=evidence.Pin(Path.Combine(directory,"spawning.json"),SpawningHash),bound=evidence.Pin(Path.Combine(directory,"bound.json"),BoundHash),receipt=evidence.Pin(Path.Combine(directory,"install-receipt.json"),InstallHash),ready=evidence.Pin(Path.Combine(directory,"install-ready.json"),LeaseHash),ack=evidence.Pin(Path.Combine(directory,"install-ack.json"),LeaseHash);
                evidence.Pin(OriginalImage,ImageHash);evidence.Pin(OriginalSource,SourceHash);evidence.Pin(CopiedImage,CliHash);IntPtr actual=evidence.Pin(ActualPath,ActualHash);
                stage=2;History(evidence.Text(prepared),evidence.Text(spawning),evidence.Text(bound),evidence.Text(receipt),evidence.Text(ready),evidence.Text(ack));CaptureHistory(evidence.Text(actual));report["historical_failure_verified"]=true;history=true;
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
        internal static int SelfTest(){int assertions=0;TaskHostFaultRetiredNative.Layouts();assertions++;Need(TaskPaths.Scope(Attempt)==Scope&&TaskBoundary.Key(Scope,"allow4")==new Guid("9ccb9dd2-7bba-7442-0bf0-a3afc24cee47")&&TaskBoundary.Key(Scope,"deny4")==new Guid("ddb0f120-5398-fd2a-baf8-bb96210566cc")&&TaskBoundary.Key(Scope,"deny6")==new Guid("6724fd21-54ae-0db6-f548-40539f366c69")&&TaskBoundary.Key(Scope,"sublayer")==new Guid("81b233d6-f77d-0f63-bc3d-ac3f5f8cdaf9"));assertions++;for(int mask=0;mask<256;mask++){bool[] b=new bool[8];for(int i=0;i<8;i++)b[i]=(mask&(1<<i))!=0;Need(Complete(b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7])==(mask==255));assertions++;}Need(ExactNames((string[])FixedNames.Clone())&&!ExactNames(new string[]{"prepared.json","codex.exe"})&&!ExactNames(null));assertions++;Need(Inactive(false,87,0,0,0)&&!Inactive(false,5,0,0,0)&&!Inactive(true,0,OwnerPid,OwnerCreation,258)&&Inactive(true,0,OwnerPid,OwnerCreation+1,258)&&Inactive(true,0,OwnerPid,OwnerCreation,0)&&!Inactive(true,0,OwnerPid+1,OwnerCreation,0)&&!Inactive(true,0,OwnerPid,OwnerCreation,UInt32.MaxValue));assertions++;Dictionary<string,object> result=Base("self_test",false);result["pure_assertions"]=assertions;Console.WriteLine(MatrixRecords.Json(result));return 0;}
        public static int Main(string[] args){bool actual=false;try{if(args.Length==0||args.Length==1&&args[0]=="--plan"){Console.WriteLine(MatrixRecords.Json(Base("plan",false)));return 0;}if(args.Length==1&&args[0]=="--self-test")return SelfTest();if(args.Length==1&&(args[0]=="--inspect"||args[0]=="--apply-cleanup")){actual=true;return Recover(args[0]=="--apply-cleanup");}}catch{}Dictionary<string,object> rejected=Base("rejected",actual);rejected["failure_stage"]=99;Console.WriteLine(MatrixRecords.Json(rejected));return 2;}
    }
}
