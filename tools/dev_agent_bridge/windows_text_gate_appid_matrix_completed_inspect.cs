// Fixed completed-journal attempt: historical files cannot recover lost actual stdout/exit evidence.
// Read-only current policy inspection. No start, stop, policy mutation, directory creation, or report rewrite.
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
    internal static class MatrixCompletedInspectNative {
        [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]internal struct ProcessEntry {
            internal uint Size,Usage,Pid;internal UIntPtr Heap;internal uint Module,Threads,Parent;internal int Priority;internal uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)]internal string Name;
        }
        [DllImport("kernel32.dll",SetLastError=true)]internal static extern IntPtr CreateToolhelp32Snapshot(uint flags,uint pid);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]internal static extern bool Process32FirstW(IntPtr snapshot,ref ProcessEntry entry);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]internal static extern bool Process32NextW(IntPtr snapshot,ref ProcessEntry entry);
        internal static void Layouts(){MatrixCompletedInspectProgram.Need(IntPtr.Size==8&&Marshal.SizeOf(typeof(ProcessEntry))==568&&Marshal.OffsetOf(typeof(ProcessEntry),"Pid").ToInt32()==8&&Marshal.OffsetOf(typeof(ProcessEntry),"Heap").ToInt32()==16&&Marshal.OffsetOf(typeof(ProcessEntry),"Name").ToInt32()==44);InspectionNative.Layouts();}
    }
    internal sealed class MatrixCompletedInspectResources {
        internal readonly MatrixHandleLedger Handles;internal IntPtr Engine;internal bool Transaction;internal bool CloseSucceeded=true;internal uint? CloseError;
        readonly Func<IntPtr,uint> abort,closeEngine;
        internal MatrixCompletedInspectResources():this(Native.CloseHandle,Native.FwpmTransactionAbort0,Native.FwpmEngineClose0){}
        internal MatrixCompletedInspectResources(Func<IntPtr,bool> closeHandle,Func<IntPtr,uint> abortTransaction,Func<IntPtr,uint> close){
            Handles=new MatrixHandleLedger(delegate(IntPtr handle){bool result=closeHandle(handle);if(!result)CloseError=unchecked((uint)Marshal.GetLastWin32Error());return result;});abort=abortTransaction;closeEngine=close;
        }
        internal bool Empty {get{return !Transaction&&Engine==IntPtr.Zero&&Handles.Empty;}}
        internal bool CloseVerified(){
            try{if(Transaction&&Engine!=IntPtr.Zero){uint code=abort(Engine);if(code==0)Transaction=false;else{CloseSucceeded=false;CloseError=code;}}}catch{CloseSucceeded=false;}
            try{if(Engine!=IntPtr.Zero&&!Transaction){uint code=closeEngine(Engine);if(code==0)Engine=IntPtr.Zero;else{CloseSucceeded=false;CloseError=code;}}}catch{CloseSucceeded=false;}
            CloseSucceeded=Handles.CloseAll()&&CloseSucceeded;return CloseSucceeded&&Empty;
        }
    }
    public static class MatrixCompletedInspectProgram {
        internal static readonly Guid Attempt=new Guid("70ea3573-f6cf-4c5c-b680-8a21288ea5fb");
        internal const uint OwnerPid=44532;internal const ulong OwnerCreation=134336608542776034UL;internal const int BrokerPort=45541;
        internal const string PreparedHash="0f93f5dcaeffef802be3084ae434768fbb1c2d58783a1147daab58d765616e23";
        internal const string ImageHash="07fa499c4922b80d531c09fa23f053c7982ad28718f9ba6089297ecba34b77f3";
        internal const string OriginalImage=@"D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_matrix_runtime.v3.exe";
        internal const string BoundHash="bdcfeaa09202984d9257011cfaaeff9ecb92549e9614b5135d4f2a8760b3d625";
        internal const string ClosedHash="705d143e3410426bf506dd757e8bc373f1a760a675a50ab1742c23dd5baa8073";
        internal const string CleanupHash="d412a74b166770ab9f62d6f302bb625ce8cbec20705e82585515af2ef8c5f47b";
        internal static readonly string[] FixedNames=new string[]{"prepared.json","spawning.json","bound.json","closed.json","install-ready.json","install-ack.json","install-receipt.json","install-report.json","cleanup-ready.json","cleanup-ack.json","cleanup-receipt.json","cleanup-report.json","event-binding.json","event-probes.json","event-receipt.json","probe-report.json","matrix-probe.exe"};
        static readonly List<MatrixCompletedInspectResources> Retained=new List<MatrixCompletedInspectResources>();
        internal static void Need(bool value){Guard.Require(value,"matrix_fixed_inspection_rejected");}
        internal static void Status(uint value){Guard.Win32(value==0,value,"matrix_fixed_inspection_api_failed");}
        internal static void Win(bool value){uint code=unchecked((uint)Marshal.GetLastWin32Error());Guard.Win32(value,code,"matrix_fixed_inspection_api_failed");}
        internal static uint Number(object value){Need(value is int||value is long||value is uint);long n=Convert.ToInt64(value);Need(n>=0&&n<=UInt32.MaxValue);return (uint)n;}
        static void Keys(Dictionary<string,object> value,string keys){string[] names=keys.Split(',');Need(value!=null&&value.Count==names.Length);foreach(string name in names)Need(value.ContainsKey(name));}
        internal static bool Inactive(bool opened,uint error,uint returnedPid,ulong creation,uint wait){return !opened?error==87:returnedPid==OwnerPid&&creation>0&&(wait==0||wait==258)&&(creation!=OwnerCreation||wait==0);}
        internal static bool PathIdle(bool samePath,uint wait){return (wait==0||wait==258)&&(!samePath||wait==0);}
        // Elevated mode is read-only and additionally requires the current SID to own both exact protected directories.
        // It never projects an elevated/linked token as the historical Medium token.
        internal static bool CallerAccepted(MediumIdentity current){return current!=null&&current.Type==1&&current.Integrity==12288&&current.ElevationType==2&&current.Elevated==1&&current.AppContainer==0&&current.Authentication!=0;}
        internal static bool Complete(bool admitted,bool history,bool idleBefore,bool idleAfter,bool postPins,int queried,int present,bool subQueried,bool subPresent,bool transactionEnded,bool resourcesClosed){return admitted&&history&&idleBefore&&idleAfter&&postPins&&queried==3&&present==0&&subQueried&&!subPresent&&transactionEnded&&resourcesClosed;}
        internal static bool ExactNames(string[] names){if(names==null||names.Length!=FixedNames.Length)return false;HashSet<string> expected=new HashSet<string>(FixedNames,StringComparer.OrdinalIgnoreCase);foreach(string name in names)if(name==null||name!=Path.GetFileName(name)||!expected.Remove(name))return false;return expected.Count==0;}
        static ulong Time(object value){string s=value as string;ulong n;Need(s!=null&&UInt64.TryParse(s,out n));n=UInt64.Parse(s);Need(n>0&&n.ToString(System.Globalization.CultureInfo.InvariantCulture)==s);return n;}
        internal static MatrixExpected History(string prepared,string bound,string closed,string cleanup){
            Dictionary<string,object> journal=MatrixRecords.Parse(prepared),receipt=MatrixRecords.Parse(cleanup);
            Keys(journal,"schema,attempt_id,scope_id,nonce,image_sha256,coordinator_sha256,coordinator_pid,coordinator_creation,coordinator_token_digest,broker_port,phase,child_pid,child_creation,child_token_digest");
            MatrixExpected expected=new MatrixExpected{Attempt=Attempt,Nonce=journal["nonce"] as string,ImageHash=ImageHash,OwnerHash=ImageHash,OwnerTokenDigest=journal["coordinator_token_digest"] as string,OwnerPid=OwnerPid,OwnerCreation=OwnerCreation,BrokerPort=BrokerPort,BlobDigest=receipt["appid_blob_digest"] as string};
            MatrixRecords.ValidateOwned(prepared,expected);Need(Object.Equals(journal["phase"],"prepared"));
            Dictionary<string,object> b=MatrixRecords.ValidateOwned(bound,expected),c=MatrixRecords.ValidateOwned(closed,expected);
            Need(Object.Equals(b["phase"],"bound")&&Object.Equals(c["phase"],"closed"));
            foreach(string field in new string[]{"child_pid","child_creation","child_token_digest"})Need(Object.Equals(b[field],c[field]));
            uint weight=Number(receipt["assigned_sublayer_weight"]);Need(weight>0&&weight<UInt16.MaxValue);
            MatrixRecords.ValidateReceipt(cleanup,expected,c,"cleanup",Number(receipt["helper_pid"]),Time(receipt["helper_creation"]),(ushort)weight);
            return expected;
        }        internal static void CheckAcl(string directory,string user){
            Need((File.GetAttributes(directory)&FileAttributes.ReparsePoint)==0);DirectorySecurity acl=Directory.GetAccessControl(directory,AccessControlSections.Owner|AccessControlSections.Access);Need(acl.AreAccessRulesProtected&&acl.GetOwner(typeof(SecurityIdentifier)).Value==user);AuthorizationRuleCollection rules=acl.GetAccessRules(true,true,typeof(SecurityIdentifier));Need(rules.Count==3);HashSet<string> required=new HashSet<string>(new string[]{user,"S-1-5-18","S-1-5-32-544"});foreach(FileSystemAccessRule rule in rules)Need(required.Remove(rule.IdentityReference.Value)&&!rule.IsInherited&&rule.AccessControlType==AccessControlType.Allow&&rule.FileSystemRights==FileSystemRights.FullControl&&rule.InheritanceFlags==(InheritanceFlags.ContainerInherit|InheritanceFlags.ObjectInherit)&&rule.PropagationFlags==PropagationFlags.None);Need(required.Count==0);
        }
        sealed class Evidence {
            readonly MatrixCompletedInspectResources resources;readonly Dictionary<string,IntPtr> directories=new Dictionary<string,IntPtr>(StringComparer.OrdinalIgnoreCase);readonly List<Tuple<IntPtr,string,string>> files=new List<Tuple<IntPtr,string,string>>();
            internal Evidence(MatrixCompletedInspectResources owner){resources=owner;}
            IntPtr Open(string path,bool directory){IntPtr handle=Native.CreateFileW(path,directory?0x80u:0x80000000u,directory?3u:1u,IntPtr.Zero,3,0x00200000u|(directory?0x02000000u:0u),IntPtr.Zero);Win(handle!=IntPtr.Zero&&handle!=new IntPtr(-1));resources.Handles.Own(handle);MatrixNativeApi.VerifyPath(handle,path,directory);return handle;}
            internal void Ancestors(string path){string full=MatrixNativeApi.Canonical(path),root=Path.GetPathRoot(full),current=root;if(!directories.ContainsKey(root))directories.Add(root,Open(root,true));foreach(string part in full.Substring(root.Length).Split('\\')){if(part.Length==0)continue;current=Path.Combine(current,part);if(!directories.ContainsKey(current))directories.Add(current,Open(current,true));}}
            internal IntPtr Pin(string path,string hash){Ancestors(Path.GetDirectoryName(path));IntPtr handle=Open(path,false);files.Add(Tuple.Create(handle,path,hash));Need(MatrixNativeApi.HashHandle(handle)==hash);return handle;}
            internal string Text(IntPtr handle){using(SafeFileHandle wrapper=new SafeFileHandle(handle,false))using(FileStream stream=new FileStream(wrapper,FileAccess.Read)){Need(stream.Length>0&&stream.Length<=16384);stream.Position=0;byte[] bytes=new byte[(int)stream.Length];int done=0;while(done<bytes.Length){int count=stream.Read(bytes,done,bytes.Length-done);Need(count>0);done+=count;}return new UTF8Encoding(false,true).GetString(bytes).TrimEnd('\r','\n');}}
            internal void Verify(string user){foreach(KeyValuePair<string,IntPtr> directory in directories)MatrixNativeApi.VerifyPath(directory.Value,directory.Key,true);foreach(Tuple<IntPtr,string,string> file in files){MatrixNativeApi.VerifyPath(file.Item1,file.Item2,false);Need(MatrixNativeApi.HashHandle(file.Item1)==file.Item3);}CheckAcl(MatrixContract.Root,user);string attempt=MatrixContract.DirectoryFor(Attempt);CheckAcl(attempt,user);string[] entries=Directory.GetFileSystemEntries(attempt);Need(entries.Length==FixedNames.Length);string[] names=new string[entries.Length];for(int i=0;i<entries.Length;i++){Need((File.GetAttributes(entries[i])&(FileAttributes.Directory|FileAttributes.ReparsePoint))==0);names[i]=Path.GetFileName(entries[i]);}Need(ExactNames(names));}
        }
        static ulong Creation(IntPtr process){Native.FileTime creation,exit,kernel,user;Win(Native.GetProcessTimes(process,out creation,out exit,out kernel,out user));Need(creation.Ticks>0);return creation.Ticks;}
        static void OwnerInactive(MatrixCompletedInspectResources resources){IntPtr process=Native.OpenProcess(0x1000|0x100000,false,OwnerPid);uint error=unchecked((uint)Marshal.GetLastWin32Error());if(process==IntPtr.Zero){Guard.Win32(Inactive(false,error,0,0,0),error,"matrix_fixed_inspection_owner_unknown");return;}resources.Handles.Own(process);try{Need(Inactive(true,0,CoordinatorNative.GetProcessId(process),Creation(process),Native.WaitForSingleObject(process,0)));}finally{Need(resources.Handles.Close(process));}}
        static void CandidateIdle(MatrixCompletedInspectResources resources,uint pid,string expected){
            IntPtr process=Native.OpenProcess(0x1000|0x100000,false,pid);uint error=unchecked((uint)Marshal.GetLastWin32Error());if(process==IntPtr.Zero){Guard.Win32(error==87,error,"matrix_fixed_inspection_process_unknown");return;}resources.Handles.Own(process);
            try{Need(CoordinatorNative.GetProcessId(process)==pid);ulong created=Creation(process);uint before=Native.WaitForSingleObject(process,0);Need(before==0||before==258);if(before==0)return;StringBuilder image=new StringBuilder(32768);uint size=32768;Win(Native.QueryFullProcessImageNameW(process,0,image,ref size));Need(size>0&&size<32768&&Path.IsPathRooted(image.ToString()));string actual=MatrixNativeApi.Canonical(image.ToString());uint after=Native.WaitForSingleObject(process,0);Need(Creation(process)==created&&CoordinatorNative.GetProcessId(process)==pid&&PathIdle(String.Equals(actual,expected,StringComparison.OrdinalIgnoreCase),after));}finally{Need(resources.Handles.Close(process));}
        }
        static void ImagesInactive(MatrixCompletedInspectResources resources){
            string copy=MatrixContract.ImageFor(Attempt),ownerName=Path.GetFileName(OriginalImage),copyName=Path.GetFileName(copy);IntPtr snapshot=MatrixCompletedInspectNative.CreateToolhelp32Snapshot(2,0);Win(snapshot!=IntPtr.Zero&&snapshot!=new IntPtr(-1));resources.Handles.Own(snapshot);
            try{MatrixCompletedInspectNative.ProcessEntry entry=new MatrixCompletedInspectNative.ProcessEntry{Size=568};bool has=MatrixCompletedInspectNative.Process32FirstW(snapshot,ref entry);uint error=unchecked((uint)Marshal.GetLastWin32Error());int count=0;
                while(has){Need(++count<=8192&&entry.Size==568&&!String.IsNullOrEmpty(entry.Name)&&entry.Name.Length<260);if(String.Equals(entry.Name,ownerName,StringComparison.OrdinalIgnoreCase))CandidateIdle(resources,entry.Pid,OriginalImage);else if(String.Equals(entry.Name,copyName,StringComparison.OrdinalIgnoreCase))CandidateIdle(resources,entry.Pid,copy);entry.Size=568;has=MatrixCompletedInspectNative.Process32NextW(snapshot,ref entry);error=unchecked((uint)Marshal.GetLastWin32Error());}Guard.Win32(error==18,error,"matrix_fixed_inspection_snapshot_unknown");
            }finally{Need(resources.Handles.Close(snapshot));}
        }
        internal static bool Finish(MatrixCompletedInspectResources resources){bool first=resources.CloseVerified();if(!first&&!resources.Empty){lock(Retained){if(!Retained.Contains(resources))Retained.Add(resources);for(int round=0;round<2;round++)for(int i=Retained.Count-1;i>=0;i--){Retained[i].CloseVerified();if(Retained[i].Empty)Retained.RemoveAt(i);}}}return first;}
        internal static Dictionary<string,object> Base(string mode,bool actual){return new Dictionary<string,object>{{"schema","p6_r7_matrix_fixed_completed_inspection_v1"},{"mode",mode},{"attempt_id",Attempt.ToString("D")},{"diagnostic_only",true},{"native_executed",actual},{"cleanup_performed",false},{"cleanup_pending",true},{"inspection_complete",false},{"historical_records_consistent",false},{"current_owner_inactive_verified",false},{"current_images_inactive_verified",false},{"files_and_acl_verified",false},{"all_owned_rules_absent_verified",false},{"transaction_ended",false},{"resources_closed",actual?(object)null:true},{"exact_child_closed",null},{"job_active0",null},{"helper_launch_error_known",false},{"helper_actual_exit_verified",false},{"filters_deleted_count",0},{"sublayers_deleted_count",0},{"matrix_passed",false},{"production_isolation_passed",false},{"human_gate_passed",false},{"real_upstream_requests",0},{"model_turns_requested",0},{"failure_stage",0},{"api_status",null}};}
        static int Inspect(){Dictionary<string,object> report=Base("inspect_completed_fixed_elevated_readonly",true);report["caller_check"]="same_directory_owner_elevated_readonly";MatrixCompletedInspectResources resources=new MatrixCompletedInspectResources();int stage=1,checkedFilters=0,presentFilters=0;bool subChecked=false,subPresent=false,admitted=false,history=false,idleBefore=false,idleAfter=false,postPins=false,ended=false,closed=false;uint? error=null;object[] filters=new object[3];string[] roles=new string[]{"allow4","deny4","deny6"};for(int i=0;i<3;i++)filters[i]=new Dictionary<string,object>{{"role",roles[i]},{"present",null}};
            try{MatrixCompletedInspectNative.Layouts();IntPtr token=IntPtr.Zero;Win(Native.OpenProcessToken(Native.GetCurrentProcess(),8,out token));resources.Handles.Own(token);MediumIdentity current=MediumIdentity.Read(token);Need(CallerAccepted(current));Evidence evidence=new Evidence(resources);string directory=MatrixContract.DirectoryFor(Attempt);evidence.Ancestors(directory);IntPtr prepared=evidence.Pin(Path.Combine(directory,"prepared.json"),PreparedHash),bound=evidence.Pin(Path.Combine(directory,"bound.json"),BoundHash),done=evidence.Pin(Path.Combine(directory,"closed.json"),ClosedHash),receipt=evidence.Pin(Path.Combine(directory,"cleanup-receipt.json"),CleanupHash);evidence.Pin(OriginalImage,ImageHash);evidence.Pin(MatrixContract.ImageFor(Attempt),ImageHash);stage=2;History(evidence.Text(prepared),evidence.Text(bound),evidence.Text(done),evidence.Text(receipt));history=true;evidence.Verify(current.User);admitted=true;stage=3;OwnerInactive(resources);ImagesInactive(resources);idleBefore=true;
                Rule[] rules=MatrixContract.Rules(Attempt,BrokerPort);Need(rules.Length==3);Guid sublayer=CoordinatorBoundary.Key(MatrixContract.Scope(Attempt),"sublayer");stage=4;Status(Native.FwpmEngineOpen0(null,10,IntPtr.Zero,IntPtr.Zero,out resources.Engine));Need(resources.Engine!=IntPtr.Zero);stage=5;Status(Native.FwpmTransactionBegin0(resources.Engine,1));resources.Transaction=true;stage=6;
                for(int i=0;i<3;i++){Guid key=rules[i].Key;IntPtr pointer=IntPtr.Zero;uint status=InspectionNative.GetFilter(resources.Engine,ref key,out pointer);try{bool present;if(status==0x80320003u){Need(pointer==IntPtr.Zero);present=false;}else{Status(status);Need(pointer!=IntPtr.Zero);present=true;}checkedFilters++;if(present)presentFilters++;((Dictionary<string,object>)filters[i])["present"]=present;}finally{if(pointer!=IntPtr.Zero)Native.FwpmFreeMemory0(ref pointer);}}
                IntPtr sub=IntPtr.Zero;uint subStatus=Native.FwpmSubLayerGetByKey0(resources.Engine,ref sublayer,out sub);try{if(subStatus==0x80320007u){Need(sub==IntPtr.Zero);subPresent=false;}else{Status(subStatus);Need(sub!=IntPtr.Zero);subPresent=true;}subChecked=true;}finally{if(sub!=IntPtr.Zero)Native.FwpmFreeMemory0(ref sub);}
                stage=7;evidence.Verify(current.User);OwnerInactive(resources);ImagesInactive(resources);idleAfter=true;Status(Native.FwpmTransactionAbort0(resources.Engine));resources.Transaction=false;ended=true;evidence.Verify(current.User);postPins=true;
            }catch(BoundaryError failure){error=failure.Win32Error;}catch(Win32Exception failure){error=unchecked((uint)failure.NativeErrorCode);}catch(UnauthorizedAccessException){error=5;}catch{}
            finally{closed=Finish(resources);if(!closed){stage=8;error=resources.CloseError;}report["failure_stage"]=Complete(admitted,history,idleBefore,idleAfter,postPins,checkedFilters,presentFilters,subChecked,subPresent,ended,closed)?0:stage;report["api_status"]=error.HasValue?(object)error.Value:null;report["filters"]=filters;report["filters_checked_count"]=checkedFilters;report["filters_present_count"]=presentFilters;report["sublayer_present"]=subChecked?(object)subPresent:null;report["historical_records_consistent"]=history;report["current_owner_inactive_verified"]=idleBefore&&idleAfter;report["current_images_inactive_verified"]=idleBefore&&idleAfter;report["files_and_acl_verified"]=admitted&&postPins;report["all_owned_rules_absent_verified"]=checkedFilters==3&&presentFilters==0&&subChecked&&!subPresent;report["transaction_ended"]=ended;report["resources_closed"]=closed;bool complete=Complete(admitted,history,idleBefore,idleAfter,postPins,checkedFilters,presentFilters,subChecked,subPresent,ended,closed);report["inspection_complete"]=complete;report["cleanup_pending"]=!complete;}
            Console.WriteLine(MatrixRecords.Json(report));return (bool)report["cleanup_pending"]?2:0;
        }
        internal static int SelfTest(){int assertions=0;MatrixCompletedInspectNative.Layouts();assertions++;for(int mask=0;mask<1024;mask++){bool[] b=new bool[10];for(int i=0;i<10;i++)b[i]=(mask&(1<<i))!=0;bool actual=Complete(b[0],b[1],b[2],b[3],b[4],b[5]?3:2,b[6]?0:1,b[7],false,b[8],b[9]);Need(actual==(mask==1023));assertions++;}Need(ExactNames((string[])FixedNames.Clone())&&!ExactNames(new string[]{"prepared.json","matrix-probe.exe"})&&!ExactNames(null));assertions++;Need(Inactive(false,87,0,0,0)&&!Inactive(false,5,0,0,0)&&!Inactive(true,0,OwnerPid,OwnerCreation,258)&&Inactive(true,0,OwnerPid,OwnerCreation+1,258)&&Inactive(true,0,OwnerPid,OwnerCreation,0)&&!Inactive(true,0,OwnerPid+1,OwnerCreation,0)&&!Inactive(true,0,OwnerPid,OwnerCreation,UInt32.MaxValue));assertions++;Dictionary<string,object> result=Base("self_test",false);result["pure_assertions"]=assertions;Console.WriteLine(MatrixRecords.Json(result));return 0;}
        public static int Main(string[] args){bool actual=false;try{if(args.Length==0||args.Length==1&&args[0]=="--plan"){Console.WriteLine(MatrixRecords.Json(Base("plan",false)));return 0;}if(args.Length==1&&args[0]=="--self-test")return SelfTest();if(args.Length==1&&args[0]=="--inspect-completed-fixed-elevated-readonly"){actual=true;return Inspect();}}catch{}Dictionary<string,object> rejected=Base("rejected",actual);rejected["failure_stage"]=99;Console.WriteLine(MatrixRecords.Json(rejected));return 2;}
    }
}
