// Unwired native adapters. Main never calls native operations; every actual verb is rejected.
// Joint-compile pinned v10/v11c/v15 + matrix-contract-01 with /main:HereIAm.R7.MatrixNativeProgram.
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace HereIAm.R7 {
    public enum MatrixNativeStage { Prepared, Installed, Spawning, Bound, Observed, Closed, Removed, Released }
    public sealed class MatrixNativeFacts {
        public bool InstallAccepted {get;set;} public bool ChildCreated {get;set;} public bool PreResumeBinding {get;set;}
        public bool OwnedPeer {get;set;} public bool WrongPeerRejected {get;set;} public bool MarkerRoundTrip {get;set;} public bool RowsComplete {get;set;}
        public bool ChildIdentityClosed {get;set;} public bool JobQueried {get;set;} public uint JobActive {get;set;}
        public bool StdioEof {get;set;} public bool SocketDrain {get;set;} public bool PostPin {get;set;}
        public bool HelperClosed {get;set;} public bool ReceiptVerified {get;set;} public bool RulesDeleted {get;set;} public bool PostAbsent {get;set;} public bool NativeHandlesClosed {get;set;}
    }
    public static class MatrixNativePolicy {
        public static bool Advance(MatrixNativeStage from,MatrixNativeStage to,MatrixNativeFacts facts) {
            if(facts==null) return false;
            if(from==MatrixNativeStage.Prepared && to==MatrixNativeStage.Installed) return facts.InstallAccepted;
            if(from==MatrixNativeStage.Installed && to==MatrixNativeStage.Spawning) return facts.InstallAccepted;
            if(from==MatrixNativeStage.Spawning && to==MatrixNativeStage.Bound) return facts.ChildCreated&&facts.PreResumeBinding;
            if(from==MatrixNativeStage.Bound && to==MatrixNativeStage.Observed) return facts.OwnedPeer&&facts.WrongPeerRejected&&facts.MarkerRoundTrip&&facts.RowsComplete;
            if((from==MatrixNativeStage.Bound||from==MatrixNativeStage.Observed) && to==MatrixNativeStage.Closed) return facts.ChildIdentityClosed&&facts.JobQueried&&facts.JobActive==0&&facts.StdioEof&&facts.SocketDrain&&facts.PostPin;
            if(from==MatrixNativeStage.Closed && to==MatrixNativeStage.Removed) return facts.HelperClosed&&facts.ReceiptVerified&&facts.RulesDeleted&&facts.PostAbsent;
            if(from==MatrixNativeStage.Removed && to==MatrixNativeStage.Released) return facts.NativeHandlesClosed;
            return false;
        }
        public static bool Complete(MatrixNativeFacts f) {
            return f!=null&&Advance(MatrixNativeStage.Prepared,MatrixNativeStage.Installed,f)&&Advance(MatrixNativeStage.Spawning,MatrixNativeStage.Bound,f)&&Advance(MatrixNativeStage.Bound,MatrixNativeStage.Observed,f)&&Advance(MatrixNativeStage.Observed,MatrixNativeStage.Closed,f)&&Advance(MatrixNativeStage.Closed,MatrixNativeStage.Removed,f)&&Advance(MatrixNativeStage.Removed,MatrixNativeStage.Released,f);
        }
        public static uint ProbeFlags {get{return 0x0008040c;}} // DETACHED, SUSPENDED, UNICODE, EXTENDED; no NEW_CONSOLE/NO_WINDOW.
    }
    internal static class MatrixNativeApi {
        [StructLayout(LayoutKind.Sequential)] internal struct FileTime {internal uint Low,High;}
        [StructLayout(LayoutKind.Sequential)] internal struct FileInfo {internal uint Attributes;internal FileTime Creation,Access,Write;internal uint Volume,SizeHigh,SizeLow,Links,IndexHigh,IndexLow;}
        [DllImport("kernel32.dll",SetLastError=true)] internal static extern bool GetFileInformationByHandle(IntPtr file,out FileInfo information);
        internal static void Require(bool value,string code){Guard.Require(value,code);}
        internal static void Win(bool value,string code){uint error=unchecked((uint)Marshal.GetLastWin32Error());Guard.Win32(value,error,code);}
        internal static string Canonical(string path){string full=Path.GetFullPath(path);Require(full.Length>=3&&full[1]==':'&&full[2]=='\\'&&!full.Substring(2).Contains(":"),"matrix_local_path_required");return full.Length==3?full:full.TrimEnd('\\');}
        internal static void VerifyPath(IntPtr file,string path,bool directory){
            FileInfo info;Win(GetFileInformationByHandle(file,out info),"matrix_file_metadata_failed");Require((info.Attributes&0x400)==0&&((info.Attributes&0x10)!=0)==directory&&(directory||info.Links==1),"matrix_path_type_rejected");
            StringBuilder result=new StringBuilder(32768);uint length=Native.GetFinalPathNameByHandleW(file,result,32768,0);Win(length>0&&length<32768,"matrix_final_path_failed");string actual=result.ToString();if(actual.StartsWith(@"\\?\",StringComparison.Ordinal))actual=actual.Substring(4);
            Require(String.Equals(Canonical(actual),Canonical(path),StringComparison.OrdinalIgnoreCase),"matrix_final_path_mismatch");
        }
        internal static string HashHandle(IntPtr handle){using(SafeFileHandle wrapper=new SafeFileHandle(handle,false))using(FileStream stream=new FileStream(wrapper,FileAccess.Read))using(SHA256 sha=SHA256.Create()){stream.Position=0;return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","").ToLowerInvariant();}}
        internal static string JobName(Guid attempt){MatrixContract.Scope(attempt);return MatrixContract.JobPrefix+attempt.ToString("N");}
        internal static string SelfPath {get{return Canonical(typeof(MatrixNativeProgram).Assembly.Location);}}
    }
    // Every CloseHandle return participates in the ledger. A later retry cannot erase a failure.
    internal sealed class MatrixHandleLedger : IDisposable {
        internal static bool AnyCloseFailure;
        readonly List<IntPtr> handles=new List<IntPtr>();readonly Func<IntPtr,bool> close;internal bool AllCloseCallsSucceeded=true;
        internal MatrixHandleLedger():this(Native.CloseHandle){}
        internal MatrixHandleLedger(Func<IntPtr,bool> closer){MatrixNativeApi.Require(closer!=null,"matrix_close_primitive_missing");close=closer;}
        bool AttemptClose(IntPtr handle){bool success;try{success=close(handle);}catch{success=false;}if(!success)AnyCloseFailure=true;return success;}
        internal IntPtr Own(IntPtr handle){MatrixNativeApi.Require(handle!=IntPtr.Zero&&handle!=new IntPtr(-1),"matrix_handle_missing");MatrixNativeApi.Require(!handles.Contains(handle),"matrix_duplicate_handle_owner");handles.Add(handle);return handle;}
        internal bool Close(IntPtr handle){if(handle==IntPtr.Zero)return true;MatrixNativeApi.Require(handles.Contains(handle),"matrix_unowned_handle_close");bool success=AttemptClose(handle);if(success)handles.Remove(handle);else AllCloseCallsSucceeded=false;return success;}
        internal bool CloseAll(){for(int i=handles.Count-1;i>=0;i--){if(AttemptClose(handles[i]))handles.RemoveAt(i);else AllCloseCallsSucceeded=false;}return AllCloseCallsSucceeded&&handles.Count==0;}
        internal bool Empty {get{return handles.Count==0;}}
        internal bool Owns(IntPtr value){return handles.Contains(value);}
        public void Dispose(){CloseAll();}
    }
    // Read-only admission of a future host-created private attempt; this layer does not create directories/journals.
    internal sealed class MatrixPinnedAttempt : IDisposable {
        readonly MatrixHandleLedger files=new MatrixHandleLedger();internal readonly MatrixExpected Expected;internal readonly string Image,Directory;internal readonly IntPtr ImageHandle;internal readonly MediumIdentity Owner;
        bool disposed;
        IntPtr Pin(string path,bool directory){IntPtr file=files.Own(Native.CreateFileW(path,directory?0x80u:0x80000000u,directory?3u:1u,IntPtr.Zero,3,0x00200000u|(directory?0x02000000u:0u),IntPtr.Zero));MatrixNativeApi.VerifyPath(file,path,directory);return file;}
        void Ancestors(string directory){string full=MatrixNativeApi.Canonical(directory),root=Path.GetPathRoot(full),current=root;Pin(root,true);foreach(string part in full.Substring(root.Length).Split('\\')){if(part.Length==0)continue;current=Path.Combine(current,part);Pin(current,true);}}
        internal MatrixPinnedAttempt(MatrixExpected expected,string preparedJournal){
            Expected=expected;Directory=MatrixContract.DirectoryFor(expected.Attempt);Image=MatrixContract.ImageFor(expected.Attempt);
            try{
                Dictionary<string,object> journal=MatrixRecords.ValidateOwned(preparedJournal,expected);MatrixNativeApi.Require(Object.Equals(journal["phase"],"prepared"),"matrix_prepared_required");
                Owner=MediumIdentity.OfProcess(Native.GetCurrentProcess());MatrixNativeApi.Require(Owner.IsMedium&&CoordinatorNative.GetProcessId(Native.GetCurrentProcess())==expected.OwnerPid&&TokenProof.Creation(Native.GetCurrentProcess())==expected.OwnerCreation&&MatrixNativeIdentity.Digest(Owner)==expected.OwnerTokenDigest,"matrix_owner_binding_failed");
                string self=MatrixNativeApi.SelfPath;Ancestors(Path.GetDirectoryName(self));IntPtr original=Pin(self,false);MatrixNativeApi.Require(MatrixNativeApi.HashHandle(original)==expected.OwnerHash&&expected.OwnerHash==expected.ImageHash,"matrix_self_hash_failed");
                Ancestors(Directory);ImageHandle=Pin(Image,false);Verify();
            }catch{files.Dispose();throw;}
        }
        internal void Verify(){MatrixNativeApi.Require(!disposed,"matrix_pin_closed");MatrixNativeApi.VerifyPath(ImageHandle,Image,false);MatrixNativeApi.Require(MatrixNativeApi.HashHandle(ImageHandle)==Expected.ImageHash,"matrix_probe_hash_failed");}
        internal bool CloseVerified(){disposed=true;return files.CloseAll();}
        public void Dispose(){CloseVerified();}
    }
    internal static class MatrixNativeIdentity {
        // Used only in private records; never report raw user/session/authentication values.
        internal static string Digest(MediumIdentity value){
            string canonical=MatrixRecords.Json(new Dictionary<string,object>{{"user",value.User},{"session",value.Session},{"authentication",value.Authentication.ToString("x16")},{"integrity",value.Integrity},{"elevation_type",value.ElevationType},{"elevated",value.Elevated},{"appcontainer",value.AppContainer},{"type",value.Type}});
            using(SHA256 sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(canonical))).Replace("-","").ToLowerInvariant();
        }
    }
    // Exact three pipe inheritance endpoints. No reader pump/row protocol is wired in this package.
    internal sealed class MatrixOwnedPipes : IDisposable {
        readonly MatrixHandleLedger handles=new MatrixHandleLedger();IntPtr inputRead,inputWrite,outputRead,outputWrite,errorRead,errorWrite;bool childEndsClosed,disposed;
        internal MatrixOwnedPipes(){
            try{
                Native.SecurityAttributes security=new Native.SecurityAttributes{Size=Marshal.SizeOf(typeof(Native.SecurityAttributes)),Inherit=1};
                Pipe(out inputRead,out inputWrite,ref security);Pipe(out outputRead,out outputWrite,ref security);Pipe(out errorRead,out errorWrite,ref security);
                foreach(IntPtr parent in new IntPtr[]{inputWrite,outputRead,errorRead})MatrixNativeApi.Win(Native.SetHandleInformation(parent,1,0),"matrix_parent_pipe_inheritance_failed");
            }catch{handles.Dispose();throw;}
        }
        void Pipe(out IntPtr read,out IntPtr write,ref Native.SecurityAttributes security){bool made=Native.CreatePipe(out read,out write,ref security,4096);uint error=unchecked((uint)Marshal.GetLastWin32Error());if(read!=IntPtr.Zero)handles.Own(read);if(write!=IntPtr.Zero)handles.Own(write);Guard.Win32(made,error,"matrix_pipe_create_failed");}
        internal IntPtr[] ChildHandles {get{MatrixNativeApi.Require(!disposed&&!childEndsClosed,"matrix_child_pipe_ends_closed");return new IntPtr[]{inputRead,outputWrite,errorWrite};}}
        internal IntPtr InputWriter {get{MatrixNativeApi.Require(!disposed,"matrix_pipes_disposed");return inputWrite;}} internal IntPtr OutputReader {get{MatrixNativeApi.Require(!disposed,"matrix_pipes_disposed");return outputRead;}} internal IntPtr ErrorReader {get{MatrixNativeApi.Require(!disposed,"matrix_pipes_disposed");return errorRead;}}
        internal void ChildCreated(){MatrixNativeApi.Require(!disposed&&!childEndsClosed,"matrix_pipe_creation_repeated");bool closed=handles.Close(inputRead)&handles.Close(outputWrite)&handles.Close(errorWrite);childEndsClosed=true;MatrixNativeApi.Require(closed,"matrix_child_pipe_close_failed");}
        internal bool CloseChildEndsForCleanup(){MatrixNativeApi.Require(!disposed,"matrix_pipes_disposed");bool closed=true;foreach(IntPtr value in new IntPtr[]{inputRead,outputWrite,errorWrite})if(handles.Owns(value))closed=handles.Close(value)&&closed;childEndsClosed=true;return closed&&handles.AllCloseCallsSucceeded;}
        internal bool CloseVerified(){disposed=true;return handles.CloseAll();}
        // Closing pipes does not prove readers reached EOF; the future stdio pump must supply that evidence.
        public void Dispose(){CloseVerified();}
    }
    internal sealed class MatrixOwnedProbe : IDisposable {
        readonly MatrixHandleLedger handles=new MatrixHandleLedger();readonly MatrixPinnedAttempt pin;readonly RestrictedProcess Binding=new RestrictedProcess();
        Native.ProcessInfo createdInfo;internal bool PreResumeBound,ExitIdentityProven,JobZeroProven,HandlesClosed;bool spawnAttempted,resumed,disposed;
        internal uint? ExitBeforeTermination;internal Native.JobAccounting? LastAccounting;
        internal uint ChildPid {get{return Binding.Pid;}} internal ulong ChildCreation {get{return Binding.Created;}} internal bool ChildCreated {get{return Binding.Started;}}
        internal bool WaitForExit(uint milliseconds){return Binding.Handle!=IntPtr.Zero&&Native.WaitForSingleObject(Binding.Handle,milliseconds)==0;}
        internal MatrixOwnedProbe(MatrixPinnedAttempt pinned){pin=pinned;CoordinatorJobNative.Layouts();
            try{Binding.Job=Native.CreateJobObjectW(IntPtr.Zero,MatrixNativeApi.JobName(pin.Expected.Attempt));uint error=unchecked((uint)Marshal.GetLastWin32Error());handles.Own(Binding.Job);MatrixNativeApi.Require(error!=183,"matrix_job_collision");
                Native.ExtendedLimit limits=new Native.ExtendedLimit();limits.Basic.Flags=0x2008;limits.Basic.ActiveLimit=1;MatrixNativeApi.Win(Native.SetInformationJobObject(Binding.Job,9,ref limits,144),"matrix_job_limit_failed");
                Native.ExtendedLimit read;MatrixNativeApi.Win(CoordinatorJobNative.QueryLimits(Binding.Job,9,out read,144,IntPtr.Zero),"matrix_job_readback_failed");MatrixNativeApi.Require(CoordinatorJobNative.Exact(read),"matrix_job_readback_mismatch");
                Native.JobAccounting accounting=QueryJob();MatrixNativeApi.Require(accounting.Active==0&&accounting.Total==0,"matrix_new_job_not_empty");
            }catch{handles.Dispose();throw;}
        }
        internal Native.JobAccounting QueryJob(){MatrixNativeApi.Require(!disposed&&Binding.Job!=IntPtr.Zero,"matrix_held_job_missing");Native.JobAccounting accounting;MatrixNativeApi.Win(Native.QueryInformationJobObject(Binding.Job,1,out accounting,48,IntPtr.Zero),"matrix_job_query_failed");LastAccounting=accounting;return accounting;}
        internal void CreateSuspended(MatrixOwnedPipes pipes){
            MatrixNativeApi.Require(!spawnAttempted&&!disposed&&pin.Owner.IsMedium,"matrix_spawn_state_rejected");pin.Verify();MatrixNativeApi.Require(pin.Owner.Same(MediumIdentity.OfProcess(Native.GetCurrentProcess())),"matrix_owner_changed");
            IntPtr list=IntPtr.Zero;bool initialized=false;Arena arena=new Arena();
            try{
                IntPtr size=IntPtr.Zero;Native.InitializeProcThreadAttributeList(IntPtr.Zero,2,0,ref size);MatrixNativeApi.Require(size.ToInt64()>0&&size.ToInt64()<=65536,"matrix_attribute_size_failed");list=Marshal.AllocHGlobal(size);MatrixNativeApi.Win(Native.InitializeProcThreadAttributeList(list,2,0,ref size),"matrix_attribute_init_failed");initialized=true;
                MatrixNativeApi.Win(Native.UpdateProcThreadAttribute(list,0,new IntPtr(0x2000d),arena.Struct(Binding.Job),new IntPtr(8),IntPtr.Zero,IntPtr.Zero),"matrix_atomic_job_failed");
                IntPtr[] childHandles=pipes.ChildHandles;MatrixNativeApi.Require(childHandles.Length==3&&childHandles[0]!=childHandles[1]&&childHandles[1]!=childHandles[2]&&childHandles[0]!=childHandles[2],"matrix_stdio_handles_rejected");
                MatrixNativeApi.Win(Native.UpdateProcThreadAttribute(list,0,new IntPtr(0x20002),arena.Array(childHandles),new IntPtr(24),IntPtr.Zero,IntPtr.Zero),"matrix_stdio_allowlist_failed");
                Native.StartupEx startup=new Native.StartupEx();startup.Info.Size=112;startup.Attributes=list;startup.Info.Flags=0x100;startup.Info.Input=childHandles[0];startup.Info.Output=childHandles[1];startup.Info.Error=childHandles[2];
                string windows=Environment.GetFolderPath(Environment.SpecialFolder.Windows);MatrixNativeApi.Require(windows==MatrixNativeApi.Canonical(windows),"matrix_windows_directory_rejected");
                string environment="SystemDrive="+Path.GetPathRoot(windows).TrimEnd('\\')+"\0SystemRoot="+windows+"\0TEMP="+pin.Directory+"\0TMP="+pin.Directory+"\0\0";
                StringBuilder command=new StringBuilder("\""+pin.Image+"\" --matrix-probe "+pin.Expected.Attempt.ToString("D"));spawnAttempted=true;
                bool created=Native.CreateProcessW(pin.Image,command,IntPtr.Zero,IntPtr.Zero,true,MatrixNativePolicy.ProbeFlags,arena.Text(environment),pin.Directory,ref startup,out createdInfo);uint error=unchecked((uint)Marshal.GetLastWin32Error());
                // The caller-owned object captures the actual process handles before any verification can throw.
                Binding.Handle=createdInfo.Process;Binding.ThreadHandle=createdInfo.Thread;Binding.Pid=createdInfo.Pid;Binding.Started=created;
                if(Binding.Handle!=IntPtr.Zero)handles.Own(Binding.Handle);if(Binding.ThreadHandle!=IntPtr.Zero)handles.Own(Binding.ThreadHandle);Guard.Win32(created,error,"matrix_probe_create_failed");
                Binding.Created=TokenProof.Creation(Binding.Handle);VerifyLiveBinding();pipes.ChildCreated();PreResumeBound=true;
            }finally{if(initialized)Native.DeleteProcThreadAttributeList(list);if(list!=IntPtr.Zero)Marshal.FreeHGlobal(list);arena.Dispose();}
        }
        internal void VerifyLiveBinding(){
            MatrixNativeApi.Require(!disposed&&Binding.Started&&Binding.Handle!=IntPtr.Zero&&Binding.Created!=0&&CoordinatorNative.GetProcessId(Binding.Handle)==Binding.Pid&&TokenProof.Creation(Binding.Handle)==Binding.Created&&Native.WaitForSingleObject(Binding.Handle,0)==258,"matrix_probe_identity_failed");
            bool member;MatrixNativeApi.Win(Native.IsProcessInJob(Binding.Handle,Binding.Job,out member),"matrix_membership_query_failed");MatrixNativeApi.Require(member,"matrix_membership_failed");TokenProof.Image(Binding.Handle,pin.Image);pin.Verify();MatrixNativeApi.Require(pin.Owner.Same(MediumIdentity.OfProcess(Binding.Handle)),"matrix_probe_token_failed");
        }
        internal void Resume(){MatrixNativeApi.Require(PreResumeBound&&!resumed&&!disposed,"matrix_resume_state_rejected");VerifyLiveBinding();MatrixNativeApi.Require(Native.ResumeThread(Binding.ThreadHandle)==1,"matrix_resume_failed");resumed=true;}
        internal bool AdmitBrokerPeer(System.Net.Sockets.Socket accepted){VerifyLiveBinding();return AppIdLauncher.Peer(accepted,Binding,pin.Owner,pin.Image);}
        internal bool StopAndObserve(){
            MatrixNativeApi.Require(!disposed,"matrix_probe_disposed");
            ExitIdentityProven=false;JobZeroProven=false;LastAccounting=null;
            if(Binding.Handle!=IntPtr.Zero){
                uint state=Native.WaitForSingleObject(Binding.Handle,0);
                if(state==0){uint code;if(Native.GetExitCodeProcess(Binding.Handle,out code))ExitBeforeTermination=code;}
                if(state!=0){if(Binding.Job!=IntPtr.Zero)Native.TerminateJobObject(Binding.Job,125);if(Native.WaitForSingleObject(Binding.Handle,0)!=0)Native.TerminateProcess(Binding.Handle,125);}
                bool signaled=Native.WaitForSingleObject(Binding.Handle,5000)==0;
                try{ExitIdentityProven=Binding.Created>0&&signaled&&CoordinatorNative.GetProcessId(Binding.Handle)==Binding.Pid&&TokenProof.Creation(Binding.Handle)==Binding.Created;}catch{ExitIdentityProven=false;}
            }
            try{Native.JobAccounting result=QueryJob();JobZeroProven=result.Active==0;}catch{JobZeroProven=false;LastAccounting=null;}
            // No image query after exit; pin and pre-resume identity remain separately necessary.
            return ExitIdentityProven&&JobZeroProven;
        }
        internal bool CloseAfterVerifiedRulesRemoval(bool removed){MatrixNativeApi.Require(!disposed&&removed&&ExitIdentityProven&&JobZeroProven,"matrix_close_before_rule_proof");HandlesClosed=handles.CloseAll();disposed=true;return HandlesClosed;}
        internal bool CloseNeverCreated(bool removed){MatrixNativeApi.Require(!disposed&&removed&&!Binding.Started&&Binding.Handle==IntPtr.Zero&&QueryJob().Active==0&&LastAccounting.Value.Total==0,"matrix_never_created_close_rejected");HandlesClosed=handles.CloseAll();disposed=true;return HandlesClosed;}
        public void Dispose(){if(disposed){HandlesClosed=handles.CloseAll();return;}try{StopAndObserve();}finally{HandlesClosed=handles.CloseAll();disposed=true;}/* A later Dispose only retries retained closes; it never repeats queries on already closed handles. */}
    }
    // Native WFP bridge, not an elevated lifecycle. Caller must keep/prove real owner, Job and helper receipts.
    internal sealed class MatrixRuleAdapter : IDisposable {
        readonly CoordinatorBoundary boundary;readonly MatrixExpected expected;readonly Action proveOwnerAndJob;
        internal bool PostAbsence;internal bool RollbackVerified;
        internal MatrixRuleAdapter(MatrixExpected value,Action actualOwnerAndJobProof){
            MatrixNativeApi.Require(value!=null&&actualOwnerAndJobProof!=null,"matrix_rule_proof_missing");expected=value;proveOwnerAndJob=actualOwnerAndJobProof;
            boundary=new CoordinatorBoundary(MatrixContract.Scope(value.Attempt),value.BrokerPort,MatrixContract.ImageFor(value.Attempt));
            try{MatrixNativeApi.Require(boundary.BlobDigest==value.BlobDigest,"matrix_appid_blob_mismatch");}
            catch{try{boundary.Dispose();}catch{}throw;}
        }
        internal ushort? AssignedWeight {get{return boundary.AssignedWeight;}}
        internal string BlobDigest {get{return boundary.BlobDigest;}}
        void Prove(string journal,string phase){
            Dictionary<string,object> record=MatrixRecords.ValidateOwned(journal,expected);MatrixNativeApi.Require(Object.Equals(record["phase"],phase),"matrix_rule_phase_rejected");
            MediumIdentity current=MediumIdentity.OfProcess(Native.GetCurrentProcess());MatrixNativeApi.Require(current.Type==1&&current.ElevationType==2&&current.Elevated==1&&current.AppContainer==0,"matrix_rule_helper_elevation_required");
            proveOwnerAndJob();
        }
        internal void Install(string preparedJournal){
            Prove(preparedJournal,"prepared");
            try{boundary.Install();Prove(preparedJournal,"prepared");}
            catch{
                if(boundary.InitialEmptyVerified){try{Action prove=delegate{Prove(preparedJournal,"prepared");};InstallFlow.Rollback(prove,delegate{boundary.RemoveAfterZero(prove);},delegate{boundary.OpenAndVerify(true);MatrixNativeApi.Require(!boundary.Installed,"matrix_rollback_absence_failed");});RollbackVerified=true;PostAbsence=true;}catch{RollbackVerified=false;}}
                throw;
            }
        }
        internal void Cleanup(string closedJournal,ushort actualInstalledWeight){Prove(closedJournal,"closed");boundary.AssignedWeight=actualInstalledWeight;boundary.RemoveAfterZero(delegate{Prove(closedJournal,"closed");});PostAbsence=boundary.Verified&&!boundary.Installed;}
        internal void RollbackPrepared(string preparedJournal,ushort? actualInstalledWeight){Prove(preparedJournal,"prepared");boundary.AssignedWeight=actualInstalledWeight;boundary.RemoveAfterZero(delegate{Prove(preparedJournal,"prepared");});PostAbsence=boundary.Verified&&!boundary.Installed;RollbackVerified=PostAbsence;}
        public void Dispose(){boundary.Dispose();/* Helper actual-exit/receipt remains a separate, unimplemented coordinator obligation. */}
    }
    public static class MatrixNativeProgram {
        static int checks;
        static void Check(bool value){if(!value)throw new BoundaryError("matrix_native_selftest_failed");checks++;}
        static void Reject(Action action){bool rejected=false;try{action();}catch{rejected=true;}Check(rejected);}
        static void LedgerSelfTest(){
            int calls=0;MatrixHandleLedger ledger=new MatrixHandleLedger(delegate(IntPtr handle){calls++;return handle.ToInt64()==7||calls>=3;});ledger.Own(new IntPtr(7));ledger.Own(new IntPtr(8));
            Check(ledger.Close(new IntPtr(7))&&calls==1);Check(!ledger.Close(new IntPtr(8))&&!ledger.AllCloseCallsSucceeded&&!ledger.Empty&&calls==2);Reject(delegate{ledger.Own(new IntPtr(8));});Check(ledger.Close(new IntPtr(8))&&ledger.Empty&&!ledger.AllCloseCallsSucceeded&&calls==3);Check(!ledger.CloseAll()&&calls==3);
            Reject(delegate{ledger.Own(IntPtr.Zero);});Reject(delegate{ledger.Own(new IntPtr(-1));});
            List<long> order=new List<long>();MatrixHandleLedger success=new MatrixHandleLedger(delegate(IntPtr handle){order.Add(handle.ToInt64());return true;});success.Own(new IntPtr(1));success.Own(new IntPtr(2));
            Reject(delegate{success.Own(new IntPtr(1));});Reject(delegate{success.Close(new IntPtr(9));});Check(success.Close(IntPtr.Zero)&&order.Count==0);Check(success.CloseAll()&&order.Count==2&&order[0]==2&&order[1]==1);
            int throwingCalls=0;MatrixHandleLedger throwing=new MatrixHandleLedger(delegate(IntPtr handle){throwingCalls++;if(handle.ToInt64()==2&&throwingCalls==1)throw new InvalidOperationException();return true;});throwing.Own(new IntPtr(1));throwing.Own(new IntPtr(2));Check(!throwing.CloseAll()&&throwingCalls==2&&!throwing.Empty);Check(!throwing.CloseAll()&&throwingCalls==3&&throwing.Empty&&!throwing.AllCloseCallsSucceeded);Check(!throwing.CloseAll()&&throwingCalls==3);
        }
        public static MatrixNativeFacts PassingFacts(){return new MatrixNativeFacts{InstallAccepted=true,ChildCreated=true,PreResumeBinding=true,OwnedPeer=true,WrongPeerRejected=true,MarkerRoundTrip=true,RowsComplete=true,ChildIdentityClosed=true,JobQueried=true,JobActive=0,StdioEof=true,SocketDrain=true,PostPin=true,HelperClosed=true,ReceiptVerified=true,RulesDeleted=true,PostAbsent=true,NativeHandlesClosed=true};}
        public static string Report(string mode){
            Dictionary<string,object> report=new Dictionary<string,object>{{"schema","p6_r7_appid_matrix_native_adapters_v1"},{"mode",mode=="self_test"?"self_test":mode=="plan"?"plan":"rejected"},{"runtime_status","adapters_only_not_wired"},{"native_adapters_implemented",true},{"runtime_implemented",false},{"native_executed",false},{"system_mutation_requested",false},{"matrix_passed",false},{"network_enforcement_tested",false},{"single_process_enforcement_tested",false},{"production_isolation_passed",false},{"human_gate_passed",false},{"real_upstream_requests",0},{"model_turns_requested",0},{"assertions_passed",checks}};
            return MatrixRecords.Json(report);
        }
        static int SelfTest(){
            checks=0;InspectionNative.Layouts();CoordinatorJobNative.Layouts();Check(Marshal.SizeOf(typeof(Native.StartupEx))==112&&Marshal.SizeOf(typeof(MatrixNativeApi.FileInfo))==52);
            Check(MatrixNativePolicy.ProbeFlags==0x8040c&&(MatrixNativePolicy.ProbeFlags&(0x08000000u|0x10u))==0);
            Check(MatrixNativePolicy.Complete(PassingFacts()));Check(!MatrixNativePolicy.Complete(null));
            foreach(System.Reflection.PropertyInfo property in typeof(MatrixNativeFacts).GetProperties()){MatrixNativeFacts facts=PassingFacts();property.SetValue(facts,property.PropertyType==typeof(bool)?(object)false:(object)(uint)1,null);Check(!MatrixNativePolicy.Complete(facts));}
            foreach(MatrixNativeStage from in Enum.GetValues(typeof(MatrixNativeStage)))foreach(MatrixNativeStage to in Enum.GetValues(typeof(MatrixNativeStage))){bool expected=(int)to==(int)from+1||from==MatrixNativeStage.Bound&&to==MatrixNativeStage.Closed;Check(MatrixNativePolicy.Advance(from,to,PassingFacts())==expected);Check(!MatrixNativePolicy.Advance(from,to,null));}
            Check(!MatrixNativePolicy.Advance(MatrixNativeStage.Spawning,MatrixNativeStage.Closed,PassingFacts()));
            Guid attempt=new Guid("11111111-2222-4333-8444-555555555555");Rule[] rules=MatrixContract.Rules(attempt,45678);Check(rules.Length==3&&rules[0].Port==45678&&rules[0].Weight==15&&rules[0].Permit&&!rules[1].Permit&&!rules[2].Permit);
            LedgerSelfTest();
            Console.WriteLine(Report("self_test"));return 0;
        }
        [STAThread] public static int Main(string[] args){
            // Do not wire actual verbs until fresh-root ACL/journal, UAC leases, bounded pumps and all eight fixtures are implemented/reviewed.
            try{checks=0;if(args.Length==0||args.Length==1&&args[0]=="--plan"){Console.WriteLine(Report("plan"));return 0;}if(args.Length==1&&args[0]=="--self-test")return SelfTest();}catch{}
            Console.WriteLine(Report("rejected"));return 2;
        }
    }
}
