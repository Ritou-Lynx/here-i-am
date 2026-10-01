// Fixed retired attempt recovery. Historical records do not prove child close or Job zero.
// The only mutation is exact owned three-filter and one-sublayer removal; no process actions.
// Joint-compile with pinned v10/v11c/v15/contract01/native; explicit Main below is the only entry.
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
    internal static class MatrixRetiredCleanupNative {
        [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]internal struct ProcessEntry {
            internal uint Size,Usage,Pid;internal UIntPtr Heap;internal uint Module,Threads,Parent;internal int Priority;internal uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)]internal string Name;
        }
        [DllImport("kernel32.dll",SetLastError=true)]internal static extern IntPtr CreateToolhelp32Snapshot(uint flags,uint pid);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]internal static extern bool Process32FirstW(IntPtr snapshot,ref ProcessEntry entry);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]internal static extern bool Process32NextW(IntPtr snapshot,ref ProcessEntry entry);
        internal static void Layouts(){MatrixRetiredCleanupProgram.Need(IntPtr.Size==8&&Marshal.SizeOf(typeof(ProcessEntry))==568&&Marshal.OffsetOf(typeof(ProcessEntry),"Pid").ToInt32()==8&&Marshal.OffsetOf(typeof(ProcessEntry),"Heap").ToInt32()==16&&Marshal.OffsetOf(typeof(ProcessEntry),"Name").ToInt32()==44);InspectionNative.Layouts();}
    }
    internal sealed class MatrixRetiredCleanupResources {
        internal readonly MatrixHandleLedger Handles;internal IntPtr Engine;internal bool Transaction;internal bool CloseSucceeded=true;internal uint? CloseError;
        readonly Func<IntPtr,uint> abort,closeEngine;
        internal MatrixRetiredCleanupResources():this(Native.CloseHandle,Native.FwpmTransactionAbort0,Native.FwpmEngineClose0){}
        internal MatrixRetiredCleanupResources(Func<IntPtr,bool> closeHandle,Func<IntPtr,uint> abortTransaction,Func<IntPtr,uint> close){
            Handles=new MatrixHandleLedger(delegate(IntPtr handle){bool result=closeHandle(handle);if(!result)CloseError=unchecked((uint)Marshal.GetLastWin32Error());return result;});abort=abortTransaction;closeEngine=close;
        }
        internal bool Empty {get{return !Transaction&&Engine==IntPtr.Zero&&Handles.Empty;}}
        internal bool CloseVerified(){
            try{if(Transaction&&Engine!=IntPtr.Zero){uint code=abort(Engine);if(code==0)Transaction=false;else{CloseSucceeded=false;CloseError=code;}}}catch{CloseSucceeded=false;}
            try{if(Engine!=IntPtr.Zero&&!Transaction){uint code=closeEngine(Engine);if(code==0)Engine=IntPtr.Zero;else{CloseSucceeded=false;CloseError=code;}}}catch{CloseSucceeded=false;}
            CloseSucceeded=Handles.CloseAll()&&CloseSucceeded;return CloseSucceeded&&Empty;
        }
    }
    public static class MatrixRetiredCleanupProgram {
        internal static readonly Guid Attempt=new Guid("28e6b32b-9ad0-4be3-b04b-b1c22767d943");
        internal const uint OwnerPid=52468;internal const ulong OwnerCreation=134336616095270930UL;internal const int BrokerPort=59675;
        internal const string PreparedHash="73f7a5990914be21032028cc88a6692e03cdd6f343858508218dba6bf45f0de6";
        internal const string ImageHash="06b0e49b125d9b8c6f596bc0c21bbd9600557c2988c5eccf667190165687e099";
        internal const string OriginalImage=@"D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_matrix_runtime.v4.exe";
        internal const string BoundHash="d076c12c324f5f15b30309eb12ae8a7c3ac09ac74addb2059920f4edfa2bf2d1";
        internal const string ClosedHash="77a547c3844846172e0aa90636264cfde6421ab3c7b11aa5ba6e6e19bf41cbe7";
        internal const string InstallHash="f891c10462003a99aa175783402d7d13a3d3da39328733fae611cc97b93ddf8e";
        internal const string ActualHash="7cb66b95999238dd71df395778fe566da6fda3cba3f5e4499145aa35404560f6";
        internal const string CaptureHash="b0b9b0d7d211407a7a62252ede236fcbc120c25cd974d8e800eaf63f951122ab";
        internal const string ActualPath=@"D:\memex\tmp\p6-r7-review\native-appid-matrix-runtime-actual-04.json";
        internal const string CapturePath=@"D:\memex\tmp\p6-r7-review\native-appid-matrix-runtime-capture-04.json";
        internal static readonly string[] FixedNames=new string[]{"prepared.json","spawning.json","bound.json","closed.json","install-ready.json","install-ack.json","install-receipt.json","install-report.json","cleanup-ready.json","cleanup-ack.json","cleanup-report.json","event-binding.json","event-probes.json","probe-report.json","matrix-probe.exe"};
        static readonly List<MatrixRetiredCleanupResources> Retained=new List<MatrixRetiredCleanupResources>();
        internal static void Need(bool value){Guard.Require(value,"matrix_fixed_retired_cleanup_rejected");}
        internal static void Status(uint value){Guard.Win32(value==0,value,"matrix_fixed_retired_cleanup_api_failed");}
        internal static void Win(bool value){uint code=unchecked((uint)Marshal.GetLastWin32Error());Guard.Win32(value,code,"matrix_fixed_retired_cleanup_api_failed");}
        internal static uint Number(object value){Need(value is int||value is long||value is uint);long n=Convert.ToInt64(value);Need(n>=0&&n<=UInt32.MaxValue);return (uint)n;}
        static void Keys(Dictionary<string,object> value,string keys){string[] names=keys.Split(',');Need(value!=null&&value.Count==names.Length);foreach(string name in names)Need(value.ContainsKey(name));}
        internal static bool Inactive(bool opened,uint error,uint returnedPid,ulong creation,uint wait){return !opened?error==87:returnedPid==OwnerPid&&creation>0&&(wait==0||wait==258)&&(creation!=OwnerCreation||wait==0);}
        internal static bool PathIdle(bool samePath,uint wait){return (wait==0||wait==258)&&(!samePath||wait==0);}
        // Elevated recovery additionally requires the current SID to own both exact protected directories.
        // It never projects an elevated/linked token as the historical Medium token.
        internal static bool CallerAccepted(MediumIdentity current){return current!=null&&current.Type==1&&current.Integrity==12288&&current.ElevationType==2&&current.Elevated==1&&current.AppContainer==0&&current.Authentication!=0;}
        internal static bool Complete(bool admitted,bool history,bool idleBefore,bool idleAfter,bool postPins,bool absence,bool ended,bool resourcesClosed){return admitted&&history&&idleBefore&&idleAfter&&postPins&&absence&&ended&&resourcesClosed;}
        internal static bool ExactNames(string[] names){if(names==null||names.Length!=FixedNames.Length)return false;HashSet<string> expected=new HashSet<string>(FixedNames,StringComparer.OrdinalIgnoreCase);foreach(string name in names)if(name==null||name!=Path.GetFileName(name)||!expected.Remove(name))return false;return expected.Count==0;}
        static ulong Time(object value){string s=value as string;ulong n;Need(s!=null&&UInt64.TryParse(s,out n));n=UInt64.Parse(s);Need(n>0&&n.ToString(System.Globalization.CultureInfo.InvariantCulture)==s);return n;}
        internal static MatrixExpected History(string prepared,string bound,string closed,string install){
            Dictionary<string,object> journal=MatrixRecords.Parse(prepared),receipt=MatrixRecords.Parse(install);
            Keys(journal,"schema,attempt_id,scope_id,nonce,image_sha256,coordinator_sha256,coordinator_pid,coordinator_creation,coordinator_token_digest,broker_port,phase,child_pid,child_creation,child_token_digest");
            MatrixExpected expected=new MatrixExpected{Attempt=Attempt,Nonce=journal["nonce"] as string,ImageHash=ImageHash,OwnerHash=ImageHash,OwnerTokenDigest=journal["coordinator_token_digest"] as string,OwnerPid=OwnerPid,OwnerCreation=OwnerCreation,BrokerPort=BrokerPort,BlobDigest=receipt["appid_blob_digest"] as string};
            MatrixRecords.ValidateOwned(prepared,expected);Need(Object.Equals(journal["phase"],"prepared"));
            Dictionary<string,object> b=MatrixRecords.ValidateOwned(bound,expected),c=MatrixRecords.ValidateOwned(closed,expected);
            Need(Object.Equals(b["phase"],"bound")&&Object.Equals(c["phase"],"closed"));
            foreach(string field in new string[]{"child_pid","child_creation","child_token_digest"})Need(Object.Equals(b[field],c[field]));
            uint weight=Number(receipt["assigned_sublayer_weight"]);Need(weight>0&&weight<UInt16.MaxValue);
            MatrixRecords.ValidateReceipt(install,expected,journal,"install",Number(receipt["helper_pid"]),Time(receipt["helper_creation"]),(ushort)weight);
            return expected;
        }        internal static void CheckAcl(string directory,string user){
            Need((File.GetAttributes(directory)&FileAttributes.ReparsePoint)==0);DirectorySecurity acl=Directory.GetAccessControl(directory,AccessControlSections.Owner|AccessControlSections.Access);Need(acl.AreAccessRulesProtected&&acl.GetOwner(typeof(SecurityIdentifier)).Value==user);AuthorizationRuleCollection rules=acl.GetAccessRules(true,true,typeof(SecurityIdentifier));Need(rules.Count==3);HashSet<string> required=new HashSet<string>(new string[]{user,"S-1-5-18","S-1-5-32-544"});foreach(FileSystemAccessRule rule in rules)Need(required.Remove(rule.IdentityReference.Value)&&!rule.IsInherited&&rule.AccessControlType==AccessControlType.Allow&&rule.FileSystemRights==FileSystemRights.FullControl&&rule.InheritanceFlags==(InheritanceFlags.ContainerInherit|InheritanceFlags.ObjectInherit)&&rule.PropagationFlags==PropagationFlags.None);Need(required.Count==0);
        }
        sealed class Evidence {
            readonly MatrixRetiredCleanupResources resources;readonly Dictionary<string,IntPtr> directories=new Dictionary<string,IntPtr>(StringComparer.OrdinalIgnoreCase);readonly List<Tuple<IntPtr,string,string>> files=new List<Tuple<IntPtr,string,string>>();
            internal Evidence(MatrixRetiredCleanupResources owner){resources=owner;}
            IntPtr Open(string path,bool directory){IntPtr handle=Native.CreateFileW(path,directory?0x80u:0x80000000u,directory?3u:1u,IntPtr.Zero,3,0x00200000u|(directory?0x02000000u:0u),IntPtr.Zero);Win(handle!=IntPtr.Zero&&handle!=new IntPtr(-1));resources.Handles.Own(handle);MatrixNativeApi.VerifyPath(handle,path,directory);return handle;}
            internal void Ancestors(string path){string full=MatrixNativeApi.Canonical(path),root=Path.GetPathRoot(full),current=root;if(!directories.ContainsKey(root))directories.Add(root,Open(root,true));foreach(string part in full.Substring(root.Length).Split('\\')){if(part.Length==0)continue;current=Path.Combine(current,part);if(!directories.ContainsKey(current))directories.Add(current,Open(current,true));}}
            internal IntPtr Pin(string path,string hash){Ancestors(Path.GetDirectoryName(path));IntPtr handle=Open(path,false);files.Add(Tuple.Create(handle,path,hash));Need(MatrixNativeApi.HashHandle(handle)==hash);return handle;}
            internal string Text(IntPtr handle){using(SafeFileHandle wrapper=new SafeFileHandle(handle,false))using(FileStream stream=new FileStream(wrapper,FileAccess.Read)){Need(stream.Length>0&&stream.Length<=16384);stream.Position=0;byte[] bytes=new byte[(int)stream.Length];int done=0;while(done<bytes.Length){int count=stream.Read(bytes,done,bytes.Length-done);Need(count>0);done+=count;}return new UTF8Encoding(false,true).GetString(bytes).TrimEnd('\r','\n');}}
            internal void Verify(string user){foreach(KeyValuePair<string,IntPtr> directory in directories)MatrixNativeApi.VerifyPath(directory.Value,directory.Key,true);foreach(Tuple<IntPtr,string,string> file in files){MatrixNativeApi.VerifyPath(file.Item1,file.Item2,false);Need(MatrixNativeApi.HashHandle(file.Item1)==file.Item3);}CheckAcl(MatrixContract.Root,user);string attempt=MatrixContract.DirectoryFor(Attempt);CheckAcl(attempt,user);string[] entries=Directory.GetFileSystemEntries(attempt);Need(entries.Length==FixedNames.Length);string[] names=new string[entries.Length];for(int i=0;i<entries.Length;i++){Need((File.GetAttributes(entries[i])&(FileAttributes.Directory|FileAttributes.ReparsePoint))==0);names[i]=Path.GetFileName(entries[i]);}Need(ExactNames(names));}
        }
        static ulong Creation(IntPtr process){Native.FileTime creation,exit,kernel,user;Win(Native.GetProcessTimes(process,out creation,out exit,out kernel,out user));Need(creation.Ticks>0);return creation.Ticks;}
        static void OwnerInactive(MatrixRetiredCleanupResources resources){IntPtr process=Native.OpenProcess(0x1000|0x100000,false,OwnerPid);uint error=unchecked((uint)Marshal.GetLastWin32Error());if(process==IntPtr.Zero){Guard.Win32(Inactive(false,error,0,0,0),error,"matrix_fixed_retired_cleanup_owner_unknown");return;}resources.Handles.Own(process);try{Need(Inactive(true,0,CoordinatorNative.GetProcessId(process),Creation(process),Native.WaitForSingleObject(process,0)));}finally{Need(resources.Handles.Close(process));}}
        static void CandidateIdle(MatrixRetiredCleanupResources resources,uint pid,string expected){
            IntPtr process=Native.OpenProcess(0x1000|0x100000,false,pid);uint error=unchecked((uint)Marshal.GetLastWin32Error());if(process==IntPtr.Zero){Guard.Win32(error==87,error,"matrix_fixed_retired_cleanup_process_unknown");return;}resources.Handles.Own(process);
            try{Need(CoordinatorNative.GetProcessId(process)==pid);ulong created=Creation(process);uint before=Native.WaitForSingleObject(process,0);Need(before==0||before==258);if(before==0)return;StringBuilder image=new StringBuilder(32768);uint size=32768;Win(Native.QueryFullProcessImageNameW(process,0,image,ref size));Need(size>0&&size<32768&&Path.IsPathRooted(image.ToString()));string actual=MatrixNativeApi.Canonical(image.ToString());uint after=Native.WaitForSingleObject(process,0);Need(Creation(process)==created&&CoordinatorNative.GetProcessId(process)==pid&&PathIdle(String.Equals(actual,expected,StringComparison.OrdinalIgnoreCase),after));}finally{Need(resources.Handles.Close(process));}
        }
        static void ImagesInactive(MatrixRetiredCleanupResources resources){
            string copy=MatrixContract.ImageFor(Attempt),ownerName=Path.GetFileName(OriginalImage),copyName=Path.GetFileName(copy);IntPtr snapshot=MatrixRetiredCleanupNative.CreateToolhelp32Snapshot(2,0);Win(snapshot!=IntPtr.Zero&&snapshot!=new IntPtr(-1));resources.Handles.Own(snapshot);
            try{MatrixRetiredCleanupNative.ProcessEntry entry=new MatrixRetiredCleanupNative.ProcessEntry{Size=568};bool has=MatrixRetiredCleanupNative.Process32FirstW(snapshot,ref entry);uint error=unchecked((uint)Marshal.GetLastWin32Error());int count=0;
                while(has){Need(++count<=8192&&entry.Size==568&&!String.IsNullOrEmpty(entry.Name)&&entry.Name.Length<260);if(String.Equals(entry.Name,ownerName,StringComparison.OrdinalIgnoreCase))CandidateIdle(resources,entry.Pid,OriginalImage);else if(String.Equals(entry.Name,copyName,StringComparison.OrdinalIgnoreCase))CandidateIdle(resources,entry.Pid,copy);entry.Size=568;has=MatrixRetiredCleanupNative.Process32NextW(snapshot,ref entry);error=unchecked((uint)Marshal.GetLastWin32Error());}Guard.Win32(error==18,error,"matrix_fixed_retired_cleanup_snapshot_unknown");
            }finally{Need(resources.Handles.Close(snapshot));}
        }
        internal static bool Finish(MatrixRetiredCleanupResources resources){bool first=resources.CloseVerified();if(!first&&!resources.Empty){lock(Retained){if(!Retained.Contains(resources))Retained.Add(resources);for(int round=0;round<2;round++)for(int i=Retained.Count-1;i>=0;i--){Retained[i].CloseVerified();if(Retained[i].Empty)Retained.RemoveAt(i);}}}return first;}
        internal static Dictionary<string,object> Base(string mode,bool actual){return new Dictionary<string,object>{{"schema","p6_r7_matrix_fixed_retired_cleanup_v1"},{"mode",mode},{"attempt_id",Attempt.ToString("D")},{"diagnostic_only",true},{"native_executed",actual},{"cleanup_performed",false},{"cleanup_pending",true},{"inspection_complete",false},{"historical_records_consistent",false},{"current_owner_inactive_verified",false},{"current_images_inactive_verified",false},{"files_and_acl_verified",false},{"all_owned_rules_absent_verified",false},{"transaction_ended",false},{"resources_closed",actual?(object)null:true},{"exact_child_closed",null},{"job_active0",null},{"helper_launch_error_known",false},{"helper_actual_exit_verified",false},{"filters_deleted_count",0},{"sublayers_deleted_count",0},{"matrix_passed",false},{"production_isolation_passed",false},{"human_gate_passed",false},{"real_upstream_requests",0},{"model_turns_requested",0},{"failure_stage",0},{"api_status",null}};}
        internal static void CaptureHistory(string actual,string capture){
            Dictionary<string,object> a=MatrixRecords.Parse(actual),c=MatrixRecords.Parse(capture);
            Keys(a,"schema,mode,runtime_implemented,native_executed,cleanup_pending,matrix_passed,all_own_filter_drops_matched,event_matrix_passed,production_isolation_passed,human_gate_passed,real_upstream_requests,model_turns_requested,failure_stage,attempt_id");
            Need(Object.Equals(a["schema"],"p6_r7_appid_matrix_runtime_v2")&&Object.Equals(a["mode"],"rejected")&&Object.Equals(a["attempt_id"],Attempt.ToString("D"))&&Number(a["failure_stage"])==99);
            foreach(string key in new string[]{"runtime_implemented","native_executed","cleanup_pending"})Need(Object.Equals(a[key],true));
            foreach(string key in new string[]{"matrix_passed","all_own_filter_drops_matched","event_matrix_passed","production_isolation_passed","human_gate_passed"})Need(Object.Equals(a[key],false));
            Need(Number(a["real_upstream_requests"])==0&&Number(a["model_turns_requested"])==0);
            Keys(c,"schema,candidate_sha256,native_actual_exit_code,stdout_preserved,stdout_sha256,parsed_expected_report,attempt_id,candidate_post_pin");
            Need(Object.Equals(c["schema"],"p6_r7_matrix_stdout_capture_v1")&&Object.Equals(c["candidate_sha256"],ImageHash.ToUpperInvariant())&&Number(c["native_actual_exit_code"])==2&&Object.Equals(c["stdout_preserved"],true)&&Object.Equals(c["stdout_sha256"],ActualHash.ToUpperInvariant())&&Object.Equals(c["parsed_expected_report"],false)&&Object.Equals(c["attempt_id"],Attempt.ToString("D"))&&Object.Equals(c["candidate_post_pin"],true));
        }
        // The frozen v15 RemoveAfterZero algorithm is reproduced with explicit engine/transaction ownership.
        // Its ExactFilter, ExactSublayer and ReadbackAllowed predicates remain the sole ownership rules.
        // This callback proves CURRENT retirement and held evidence, never historical child-close or Job zero.
        internal static int ReadRules(IntPtr engine,Rule[] rules,Guid sublayer,byte[] identifier,ushort weight){
            int found=0;foreach(Rule rule in rules){Guid key=rule.Key;IntPtr pointer=IntPtr.Zero;uint status=InspectionNative.GetFilter(engine,ref key,out pointer);
                try{if(status==0x80320003u){Need(pointer==IntPtr.Zero);continue;}Status(status);Need(pointer!=IntPtr.Zero&&CoordinatorBoundary.ExactFilter((InspectionNative.Filter)Marshal.PtrToStructure(pointer,typeof(InspectionNative.Filter)),rule,sublayer,identifier));found++;}finally{if(pointer!=IntPtr.Zero)Native.FwpmFreeMemory0(ref pointer);}}
            IntPtr sub=IntPtr.Zero;uint code=Native.FwpmSubLayerGetByKey0(engine,ref sublayer,out sub);bool present=code==0;
            try{if(present)Need(sub!=IntPtr.Zero&&CoordinatorBoundary.ExactSublayer((Native.Sublayer)Marshal.PtrToStructure(sub,typeof(Native.Sublayer)),sublayer,weight));else{if(code!=0x80320007u)Status(code);Need(sub==IntPtr.Zero);}}finally{if(sub!=IntPtr.Zero)Native.FwpmFreeMemory0(ref sub);}
            Need(CoordinatorBoundary.ReadbackAllowed(found,present,found>0||present,true));return found;
        }
        internal static bool RemoveFixed(Func<int> read,Action prove,Action begin,Action delete,Action commit,Action abort){
            prove();begin();bool committed=false;
            try{prove();Need(read()==3);delete();prove();commit();committed=true;}finally{if(!committed)abort();}
            prove();Need(read()==0);return true;
        }
        static int Cleanup(){
            Dictionary<string,object> report=Base("cleanup_fixed_retired_matrix_attempt",true);report["diagnostic_only"]=false;report["caller_check"]="same_directory_owner_elevated_primary_high_non_appcontainer";
            report["retired_actual_exit2_capture_verified"]=false;report["transaction_committed"]=false;report["readonly_preflight_complete"]=false;report["rules_before_count"]=null;
            MatrixRetiredCleanupResources resources=new MatrixRetiredCleanupResources();int stage=1;bool admitted=false,history=false,idleBefore=false,idleAfter=false,postPins=false,absence=false,ended=false,closed=false,committed=false,transactionStarted=false;uint? error=null;
            try{
                MatrixRetiredCleanupNative.Layouts();IntPtr token=IntPtr.Zero;Win(Native.OpenProcessToken(Native.GetCurrentProcess(),8,out token));resources.Handles.Own(token);MediumIdentity current=MediumIdentity.Read(token);Need(CallerAccepted(current));
                Evidence evidence=new Evidence(resources);string directory=MatrixContract.DirectoryFor(Attempt);evidence.Ancestors(directory);
                IntPtr prepared=evidence.Pin(Path.Combine(directory,"prepared.json"),PreparedHash),bound=evidence.Pin(Path.Combine(directory,"bound.json"),BoundHash),done=evidence.Pin(Path.Combine(directory,"closed.json"),ClosedHash),receipt=evidence.Pin(Path.Combine(directory,"install-receipt.json"),InstallHash);
                evidence.Pin(OriginalImage,ImageHash);evidence.Pin(MatrixContract.ImageFor(Attempt),ImageHash);IntPtr actual=evidence.Pin(ActualPath,ActualHash),capture=evidence.Pin(CapturePath,CaptureHash);
                stage=2;MatrixExpected expected=History(evidence.Text(prepared),evidence.Text(bound),evidence.Text(done),evidence.Text(receipt));CaptureHistory(evidence.Text(actual),evidence.Text(capture));report["retired_actual_exit2_capture_verified"]=true;history=true;
                ushort weight=(ushort)Number(MatrixRecords.Parse(evidence.Text(receipt))["assigned_sublayer_weight"]);evidence.Verify(current.User);admitted=true;
                Action prove=delegate{evidence.Verify(current.User);OwnerInactive(resources);ImagesInactive(resources);};stage=3;prove();idleBefore=true;
                IntPtr blob=IntPtr.Zero;byte[] identifier;try{Status(AppIdNative.FwpmGetAppIdFromFileName0(MatrixContract.ImageFor(Attempt),out blob));identifier=CoordinatorBoundary.CopyBlob(blob);}finally{if(blob!=IntPtr.Zero)Native.FwpmFreeMemory0(ref blob);}
                using(System.Security.Cryptography.SHA256 hash=System.Security.Cryptography.SHA256.Create())Need(BitConverter.ToString(hash.ComputeHash(identifier)).Replace("-","").ToLowerInvariant()==expected.BlobDigest);
                Rule[] rules=MatrixContract.Rules(Attempt,BrokerPort);Need(rules.Length==3);Guid sublayer=CoordinatorBoundary.Key(MatrixContract.Scope(Attempt),"sublayer");
                stage=4;Status(Native.FwpmEngineOpen0(null,10,IntPtr.Zero,IntPtr.Zero,out resources.Engine));Need(resources.Engine!=IntPtr.Zero);Func<int> read=delegate{return ReadRules(resources.Engine,rules,sublayer,identifier,weight);};
                stage=5;Status(Native.FwpmTransactionBegin0(resources.Engine,1));resources.Transaction=true;transactionStarted=true;int before=read();prove();uint abortStatus=Native.FwpmTransactionAbort0(resources.Engine);if(abortStatus==0)resources.Transaction=false;else{resources.CloseSucceeded=false;resources.CloseError=abortStatus;}Status(abortStatus);report["readonly_preflight_complete"]=true;report["rules_before_count"]=before;
                if(before==3){
                    stage=6;RemoveFixed(read,prove,delegate{Status(Native.FwpmTransactionBegin0(resources.Engine,0));resources.Transaction=true;},delegate{
                        foreach(Rule rule in rules){Guid key=rule.Key;Status(Native.FwpmFilterDeleteByKey0(resources.Engine,ref key));}Guid keySub=sublayer;Status(Native.FwpmSubLayerDeleteByKey0(resources.Engine,ref keySub));
                    },delegate{Status(Native.FwpmTransactionCommit0(resources.Engine));resources.Transaction=false;committed=true;report["filters_deleted_count"]=3;report["sublayers_deleted_count"]=1;},delegate{uint status=Native.FwpmTransactionAbort0(resources.Engine);if(status==0)resources.Transaction=false;else{resources.CloseSucceeded=false;resources.CloseError=status;}Status(status);});
                }else Need(before==0);
                stage=7;prove();Need(read()==0);absence=true;ended=!resources.Transaction;prove();idleAfter=true;evidence.Verify(current.User);postPins=true;
            }catch(BoundaryError failure){error=failure.Win32Error;}catch(Win32Exception failure){error=unchecked((uint)failure.NativeErrorCode);}catch(UnauthorizedAccessException){error=5;}catch{}
            finally{
                closed=Finish(resources);ended=transactionStarted&&!resources.Transaction;if(!closed){stage=8;error=resources.CloseError;}
                bool complete=Complete(admitted,history,idleBefore,idleAfter,postPins,absence,ended,closed);
                report["failure_stage"]=complete?0:stage;report["api_status"]=error.HasValue?(object)error.Value:null;report["historical_records_consistent"]=history;report["current_owner_inactive_verified"]=idleBefore&&idleAfter;report["current_images_inactive_verified"]=idleBefore&&idleAfter;report["files_and_acl_verified"]=admitted&&postPins;report["all_owned_rules_absent_verified"]=absence;report["transaction_ended"]=ended;report["transaction_committed"]=committed;report["cleanup_performed"]=committed;report["resources_closed"]=closed;report["inspection_complete"]=complete;report["cleanup_pending"]=!complete;
            }
            Console.WriteLine(MatrixRecords.Json(report));return (bool)report["cleanup_pending"]?2:0;
        }
        internal static int SelfTest(){int assertions=0;MatrixRetiredCleanupNative.Layouts();assertions++;for(int mask=0;mask<256;mask++){bool[] b=new bool[8];for(int i=0;i<8;i++)b[i]=(mask&(1<<i))!=0;Need(Complete(b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7])==(mask==255));assertions++;}Need(ExactNames((string[])FixedNames.Clone())&&!ExactNames(new string[]{"prepared.json","matrix-probe.exe"})&&!ExactNames(null));assertions++;Need(Inactive(false,87,0,0,0)&&!Inactive(false,5,0,0,0)&&!Inactive(true,0,OwnerPid,OwnerCreation,258)&&Inactive(true,0,OwnerPid,OwnerCreation+1,258)&&Inactive(true,0,OwnerPid,OwnerCreation,0)&&!Inactive(true,0,OwnerPid+1,OwnerCreation,0)&&!Inactive(true,0,OwnerPid,OwnerCreation,UInt32.MaxValue));assertions++;Dictionary<string,object> result=Base("self_test",false);result["pure_assertions"]=assertions;Console.WriteLine(MatrixRecords.Json(result));return 0;}
        public static int Main(string[] args){bool actual=false;try{if(args.Length==0||args.Length==1&&args[0]=="--plan"){Console.WriteLine(MatrixRecords.Json(Base("plan",false)));return 0;}if(args.Length==1&&args[0]=="--self-test")return SelfTest();if(args.Length==1&&args[0]=="--cleanup-fixed-retired-matrix-attempt"){actual=true;return Cleanup();}}catch{}Dictionary<string,object> rejected=Base("rejected",actual);rejected["failure_stage"]=99;Console.WriteLine(MatrixRecords.Json(rejected));return 2;}
    }
}
