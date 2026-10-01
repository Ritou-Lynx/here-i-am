// Standalone synthetic Job-limit experiment. Plan/selftest never enter native code.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Threading;
using Microsoft.Win32.SafeHandles;

namespace HereIAm.R7 {
    public static class JobLimitProbe {
        const uint RequiredFlags = 0x2008, ErrorNotEnoughQuota = 1816;
        const uint WaitObject0 = 0, WaitTimeout = 258;
        const int JobObjectExtendedLimitInformation = 9, JobObjectBasicAccountingInformation = 1;
        const int JobObjectBasicProcessIdList = 3, ProcessListCapacity = 16, ProcessListBufferBytes = 8+8*ProcessListCapacity;
        const int ProcThreadAttributeJobList = 0x0002000d;
        const uint CreateSuspended = 4, ExtendedStartupInfoPresent = 0x80000;
        const uint CreateUnicodeEnvironment = 0x400, CreateNoWindow = 0x8000000, DetachedProcess = 0x8;
        const string BaseRoot = @"D:\memex\tmp\p6-r7-job-limit";

        [StructLayout(LayoutKind.Sequential)] public struct BasicLimit {
            public long PerProcessUserTimeLimit, PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass, SchedulingClass;
        }
        [StructLayout(LayoutKind.Sequential)] public struct IoCounters { public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount, ReadTransferCount, WriteTransferCount, OtherTransferCount; }
        [StructLayout(LayoutKind.Sequential)] public struct ExtendedLimit { public BasicLimit BasicLimitInformation; public IoCounters IoInfo; public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed; }
        [StructLayout(LayoutKind.Sequential)] public struct JobAccounting { public long TotalUserTime, TotalKernelTime, ThisPeriodTotalUserTime, ThisPeriodTotalKernelTime; public uint TotalPageFaultCount, TotalProcesses, ActiveProcesses, TotalTerminatedProcesses; }
        [StructLayout(LayoutKind.Sequential)] struct BasicProcessIdListLayout { public uint Assigned, Count; public UIntPtr FirstId; }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct StartupInfo { public uint cb; public IntPtr reserved, desktop, title; public uint x,y,xSize,ySize,xChars,yChars,fill,flags; public ushort showWindow, reserved2; public IntPtr reservedBytes, stdin, stdout, stderr; }
        [StructLayout(LayoutKind.Sequential)] struct StartupInfoEx { public StartupInfo StartupInfo; public IntPtr AttributeList; }
        [StructLayout(LayoutKind.Sequential)] struct ProcessInformation { public IntPtr Process, Thread; public uint ProcessId, ThreadId; }
        [StructLayout(LayoutKind.Sequential)] struct FileTime { public uint Low, High; public ulong Value { get { return ((ulong)High<<32)|Low; } } }
        [StructLayout(LayoutKind.Sequential)] struct FileInformation { public uint Attributes; public FileTime Creation, Access, Write; public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow; }
        [StructLayout(LayoutKind.Sequential)] struct SecurityAttributes { public uint Length; public IntPtr Descriptor; [MarshalAs(UnmanagedType.Bool)] public bool Inherit; }
        sealed class ProbeError : Exception { internal readonly string Code; internal ProbeError(string code) { Code=code; } }
        sealed class Creation { internal ProcessInformation Info; internal bool Attempted, Created; internal uint Error; internal ulong CreationTime; }

        static class Native {
            [DllImport("kernel32.dll")] internal static extern IntPtr GetCurrentProcess();
            [DllImport("advapi32.dll", SetLastError=true)] internal static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
            [DllImport("advapi32.dll", SetLastError=true)] internal static extern bool GetTokenInformation(IntPtr token, int informationClass, IntPtr buffer, uint length, out uint needed);
            [DllImport("advapi32.dll")] internal static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);
            [DllImport("advapi32.dll")] internal static extern IntPtr GetSidSubAuthority(IntPtr sid, uint number);
            [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] internal static extern bool ConvertStringSecurityDescriptorToSecurityDescriptorW(string text, uint revision, out IntPtr descriptor, out uint size);
            [DllImport("advapi32.dll")] internal static extern uint GetSecurityInfo(IntPtr handle, int type, uint requested, out IntPtr owner, out IntPtr group, out IntPtr dacl, out IntPtr sacl, out IntPtr descriptor);
            [DllImport("advapi32.dll")] internal static extern uint GetSecurityDescriptorLength(IntPtr descriptor);
            [DllImport("kernel32.dll")] internal static extern IntPtr LocalFree(IntPtr memory);
            [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] internal static extern bool CreateDirectoryW(string path, ref SecurityAttributes attributes);
            [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] internal static extern IntPtr CreateFileW(string path, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
            [DllImport("kernel32.dll", SetLastError=true)] internal static extern bool GetFileInformationByHandle(IntPtr handle, out FileInformation information);
            [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] internal static extern uint GetFinalPathNameByHandleW(IntPtr handle, StringBuilder path, uint length, uint flags);
            [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] internal static extern IntPtr CreateJobObjectW(IntPtr attributes, string name);
            [DllImport("kernel32.dll", SetLastError=true)] internal static extern bool SetInformationJobObject(IntPtr job, int informationClass, ref ExtendedLimit information, uint length);
            [DllImport("kernel32.dll", SetLastError=true)] internal static extern bool QueryInformationJobObject(IntPtr job, int informationClass, out ExtendedLimit information, uint length, IntPtr returnLength);
            [DllImport("kernel32.dll", SetLastError=true)] internal static extern bool QueryInformationJobObject(IntPtr job, int informationClass, out JobAccounting information, uint length, IntPtr returnLength);
            [DllImport("kernel32.dll", SetLastError=true)] internal static extern bool QueryInformationJobObject(IntPtr job, int informationClass, IntPtr information, uint length, out uint returnLength);
            [DllImport("kernel32.dll", SetLastError=true)] internal static extern IntPtr OpenProcess(uint access, bool inherit, uint processId);
            [DllImport("kernel32.dll", SetLastError=true)] internal static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, int flags, ref IntPtr size);
            [DllImport("kernel32.dll", SetLastError=true)] internal static extern bool UpdateProcThreadAttribute(IntPtr list, uint flags, IntPtr attribute, IntPtr value, IntPtr size, IntPtr previous, IntPtr returnSize);
            [DllImport("kernel32.dll")] internal static extern void DeleteProcThreadAttributeList(IntPtr list);
            [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] internal static extern bool CreateProcessW(string app, StringBuilder command, IntPtr processAttributes, IntPtr threadAttributes, bool inheritHandles, uint creationFlags, IntPtr environment, string currentDirectory, ref StartupInfoEx startupInfo, out ProcessInformation processInformation);
            [DllImport("kernel32.dll", SetLastError=true)] internal static extern uint ResumeThread(IntPtr thread);
            [DllImport("kernel32.dll", SetLastError=true)] internal static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
            [DllImport("kernel32.dll", SetLastError=true)] internal static extern bool TerminateProcess(IntPtr process, uint exitCode);
            [DllImport("kernel32.dll", SetLastError=true)] internal static extern bool CloseHandle(IntPtr handle);
            [DllImport("kernel32.dll", SetLastError=true)] internal static extern uint GetProcessId(IntPtr process);
            [DllImport("kernel32.dll", SetLastError=true)] internal static extern bool GetExitCodeProcess(IntPtr process, out uint code);
            [DllImport("kernel32.dll", SetLastError=true)] internal static extern bool IsProcessInJob(IntPtr process, IntPtr job, out bool result);
            [DllImport("kernel32.dll", SetLastError=true)] internal static extern bool GetProcessTimes(IntPtr process, out FileTime creation, out FileTime exit, out FileTime kernel, out FileTime user);
            [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] internal static extern bool QueryFullProcessImageNameW(IntPtr process, uint flags, StringBuilder path, ref uint length);
            [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] internal static extern IntPtr CreateEventW(IntPtr attributes, bool manualReset, bool initialState, string name);
            [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] internal static extern IntPtr OpenEventW(uint access, bool inherit, string name);
            [DllImport("kernel32.dll", SetLastError=true)] internal static extern bool SetEvent(IntPtr handle);
        }

        public enum ListStatus { Unqueried, QueryFailed, BufferRejected, LengthRejected, CountLimit, CountMismatch, Truncated, InvalidId, DuplicateId, Parsed }
        public enum ImageClass { QueryFailed, ExpectedProbe, System32Conhost, System32OpenConsole, Other }
        public enum MemberStatus { Unqueried, OpenFailed, IdentityFailed, MembershipFailed, WaitFailed, SignaledBeforeImage, ImageFailed, Observed, CloseFailed }
        public enum WaitState { Unknown, Timeout, Signaled }
        public sealed class ParsedProcessList {
            public ListStatus Status;
            public uint? Assigned, Count;
            internal uint[] Ids=new uint[0]; // Never serialized; never sourced from system-wide enumeration.
        }
        public sealed class MemberObservation {
            public MemberStatus Status;
            public ImageClass Image;
            public WaitState BeforeWait, AfterWait;
            public bool Opened, IdentityConfirmed, CreationObserved, CreationPrecedesList, OwnJobMember, MatchesFirst, HandleClosed;
            public uint? Error;
        }
        public sealed class MemberSnapshot {
            public ParsedProcessList List=new ParsedProcessList();
            public JobAccounting? AccountingBefore, AccountingAfter;
            public uint? QueryError, ReturnedBytes, QueryMilliseconds, SnapshotMilliseconds;
            public bool CountsConsistent, Complete;
            public List<MemberObservation> Members=new List<MemberObservation>();
        }
        // Pure parser: only complete, bounded x64 ULONG_PTR lists can be used to open handles.
        public static ParsedProcessList ParseProcessList(byte[] bytes, uint returnedBytes, bool querySucceeded) {
            ParsedProcessList result=new ParsedProcessList();
            if(!querySucceeded) { result.Status=ListStatus.QueryFailed; return result; }
            if(bytes==null || bytes.Length!=ProcessListBufferBytes) { result.Status=ListStatus.BufferRejected; return result; }
            if(returnedBytes<8 || returnedBytes>bytes.Length || returnedBytes%8!=0) { result.Status=ListStatus.LengthRejected; return result; }
            uint assigned=BitConverter.ToUInt32(bytes,0), count=BitConverter.ToUInt32(bytes,4); result.Assigned=assigned; result.Count=count;
            if(assigned>ProcessListCapacity || count>ProcessListCapacity) { result.Status=ListStatus.CountLimit; return result; }
            if(assigned!=count) { result.Status=ListStatus.CountMismatch; return result; }
            if(returnedBytes<8+count*8) { result.Status=ListStatus.Truncated; return result; }
            uint[] ids=new uint[count]; HashSet<uint> seen=new HashSet<uint>();
            for(int index=0;index<count;index++) {
                ulong id=BitConverter.ToUInt64(bytes,8+index*8);
                if(id==0 || id>UInt32.MaxValue) { result.Status=ListStatus.InvalidId; return result; }
                if(!seen.Add((uint)id)) { result.Status=ListStatus.DuplicateId; return result; } ids[index]=(uint)id;
            }
            result.Ids=ids; result.Status=ListStatus.Parsed; return result;
        }
        static string ListCode(ListStatus status) {
            switch(status) { case ListStatus.QueryFailed:return "query-failed"; case ListStatus.BufferRejected:return "buffer-rejected"; case ListStatus.LengthRejected:return "length-rejected"; case ListStatus.CountLimit:return "count-limit"; case ListStatus.CountMismatch:return "count-mismatch"; case ListStatus.Truncated:return "truncated"; case ListStatus.InvalidId:return "invalid-id"; case ListStatus.DuplicateId:return "duplicate-id"; case ListStatus.Parsed:return "parsed"; default:return "unqueried"; }
        }
        static string ImageCode(ImageClass image) {
            switch(image) { case ImageClass.ExpectedProbe:return "expected-probe"; case ImageClass.System32Conhost:return "system32-conhost"; case ImageClass.System32OpenConsole:return "system32-openconsole"; case ImageClass.Other:return "other"; default:return "query-failed"; }
        }
        static string MemberCode(MemberStatus status) {
            switch(status) { case MemberStatus.OpenFailed:return "open-failed"; case MemberStatus.IdentityFailed:return "identity-failed"; case MemberStatus.MembershipFailed:return "membership-failed"; case MemberStatus.WaitFailed:return "wait-failed"; case MemberStatus.SignaledBeforeImage:return "signaled-before-image"; case MemberStatus.ImageFailed:return "image-query-failed"; case MemberStatus.Observed:return "observed"; case MemberStatus.CloseFailed:return "close-failed"; default:return "unqueried"; }
        }
        static string WaitCode(WaitState state) { return state==WaitState.Signaled?"signaled":state==WaitState.Timeout?"timeout":"query-failed"; }
        public static ImageClass ClassifyImage(string found, string expectedImage, string systemDirectory) {
            try {
                string actual=Canonical(found), expected=Canonical(expectedImage), system=Canonical(systemDirectory);
                if(String.Equals(actual,expected,StringComparison.OrdinalIgnoreCase)) return ImageClass.ExpectedProbe;
                if(String.Equals(actual,Path.Combine(system,"conhost.exe"),StringComparison.OrdinalIgnoreCase)) return ImageClass.System32Conhost;
                if(String.Equals(actual,Path.Combine(system,"OpenConsole.exe"),StringComparison.OrdinalIgnoreCase)) return ImageClass.System32OpenConsole;
                return ImageClass.Other;
            } catch { return ImageClass.QueryFailed; }
        }
        public static bool SnapshotAccepted(MemberSnapshot snapshot) {
            if(snapshot==null || !snapshot.Complete || !snapshot.CountsConsistent || snapshot.List.Status!=ListStatus.Parsed || !snapshot.List.Count.HasValue || snapshot.List.Count!=snapshot.List.Assigned || snapshot.List.Count>ProcessListCapacity || snapshot.Members.Count!=snapshot.List.Count || !snapshot.AccountingBefore.HasValue || !snapshot.AccountingAfter.HasValue || snapshot.AccountingBefore.Value.ActiveProcesses!=snapshot.List.Count || snapshot.AccountingAfter.Value.ActiveProcesses!=snapshot.List.Count || snapshot.AccountingBefore.Value.TotalProcesses!=snapshot.AccountingAfter.Value.TotalProcesses) return false;
            foreach(MemberObservation member in snapshot.Members) if(member.Status!=MemberStatus.Observed || member.Image<ImageClass.ExpectedProbe || member.Image>ImageClass.Other || !member.IdentityConfirmed || !member.CreationObserved || !member.CreationPrecedesList || !member.OwnJobMember || !member.HandleClosed || member.BeforeWait!=WaitState.Timeout || member.AfterWait!=WaitState.Timeout) return false;
            return true;
        }
        public static string ParsedListJson(ParsedProcessList result) { return "{\"status\":\""+ListCode(result.Status)+"\",\"assigned\":"+Number(result.Assigned)+",\"listed\":"+Number(result.Count)+"}"; }
        public static string SnapshotJson(MemberSnapshot snapshot) {
            if(snapshot==null) return "null";
            StringBuilder members=new StringBuilder("[");
            foreach(MemberObservation member in snapshot.Members) {
                if(members.Length>1) members.Append(',');
                members.Append("{\"status\":\"").Append(MemberCode(member.Status)).Append("\",\"image_class\":\"").Append(ImageCode(member.Image)).Append("\",\"wait_before\":\"").Append(WaitCode(member.BeforeWait)).Append("\",\"wait_after\":\"").Append(WaitCode(member.AfterWait)).Append("\",\"opened\":").Append(Bool(member.Opened)).Append(",\"identity_confirmed\":").Append(Bool(member.IdentityConfirmed)).Append(",\"creation_observed\":").Append(Bool(member.CreationObserved)).Append(",\"creation_precedes_list\":").Append(Bool(member.CreationPrecedesList)).Append(",\"own_job_member\":").Append(Bool(member.OwnJobMember)).Append(",\"matches_first_identity\":").Append(Bool(member.MatchesFirst)).Append(",\"handle_closed\":").Append(Bool(member.HandleClosed)).Append(",\"error\":").Append(Number(member.Error)).Append('}');
            }
            members.Append(']');
            return "{\"atomic_snapshot\":false,\"member_capacity\":16,\"list\":"+ParsedListJson(snapshot.List)+",\"query_error\":"+Number(snapshot.QueryError)+",\"returned_bytes\":"+Number(snapshot.ReturnedBytes)+",\"query_ms\":"+Number(snapshot.QueryMilliseconds)+",\"snapshot_ms\":"+Number(snapshot.SnapshotMilliseconds)+Counts("accounting_before",snapshot.AccountingBefore)+Counts("accounting_after",snapshot.AccountingAfter)+",\"counts_consistent\":"+Bool(snapshot.CountsConsistent)+",\"complete\":"+Bool(snapshot.Complete)+",\"members\":"+members+"}";
        }

        // Pure, public evidence policy used by managed tests and the actual report.
        public sealed class Evidence {
            public uint FailureStage;
            public bool Detached;
            public MemberSnapshot AfterCreate, AfterReady, BeforeCleanup;
            public bool OperationComplete, FirstPreResumeIdentity, FirstReadyAlive, FirstBeforeSecondAlive, FirstAfterSecondAlive;
            public bool? SecondCreated, SecondEntryObserved;
            public uint? SecondCreateError, LimitFlags, ActiveProcessLimit, FirstExitCode;
            public bool FirstExactExit, ChildrenClosed, AllHandlesClosed;
            public JobAccounting? Before, During, After;
        }
        public static bool CleanupPending(Evidence e) { return !(e.ChildrenClosed && e.AllHandlesClosed && e.After.HasValue && e.After.Value.ActiveProcesses==0); }
        public static bool Passed(Evidence e) {
            return e.OperationComplete && SnapshotAccepted(e.AfterCreate) && SnapshotAccepted(e.AfterReady) && SnapshotAccepted(e.BeforeCleanup) && e.LimitFlags==RequiredFlags && e.ActiveProcessLimit==1 &&
                e.FirstPreResumeIdentity && e.FirstReadyAlive && e.FirstBeforeSecondAlive && e.FirstAfterSecondAlive &&
                e.Before.HasValue && e.Before.Value.ActiveProcesses==1 && e.Before.Value.TotalProcesses==1 &&
                e.During.HasValue && e.SecondCreated==false && e.SecondCreateError==ErrorNotEnoughQuota &&
                e.SecondEntryObserved==false && e.FirstExactExit && e.FirstExitCode==0 && !CleanupPending(e);
        }
        static string Bool(bool value) { return value?"true":"false"; }
        static string NullableBool(bool? value) { return value.HasValue?Bool(value.Value):"null"; }
        static string Number(uint? value) { return value.HasValue?value.Value.ToString(System.Globalization.CultureInfo.InvariantCulture):"null"; }
        static string Counts(string prefix, JobAccounting? value) {
            return ",\""+prefix+"_active\":"+Number(value.HasValue?(uint?)value.Value.ActiveProcesses:null)+
                ",\""+prefix+"_total\":"+Number(value.HasValue?(uint?)value.Value.TotalProcesses:null)+
                ",\""+prefix+"_terminated\":"+Number(value.HasValue?(uint?)value.Value.TotalTerminatedProcesses:null);
        }
        public static string Report(Evidence e) {
            // Only fixed strings and typed numeric/boolean evidence can reach JSON.
            string code=Passed(e)?"limit_rejected_second":e.SecondCreated==true?"second_child_created":
                e.SecondCreateError.HasValue && e.SecondCreateError!=ErrorNotEnoughQuota?"second_create_unknown_error":"evidence_incomplete";
            return "{\"schema\":\"p6_r7_job_limit_probe_v4\",\"mode\":\""+(e.Detached?"apply_job_limit_synthetic_detached":"apply_job_limit_synthetic")+"\",\"passed\":"+Bool(Passed(e))+",\"code\":\""+code+"\""+
                ",\"requested_creation_flags\":"+Number(CreationFlags(e.Detached))+
                ",\"failure_stage\":"+e.FailureStage.ToString(System.Globalization.CultureInfo.InvariantCulture)+
                ",\"limit_flags\":"+Number(e.LimitFlags)+",\"active_process_limit\":"+Number(e.ActiveProcessLimit)+
                ",\"first_pre_resume_identity\":"+Bool(e.FirstPreResumeIdentity)+",\"first_ready_alive\":"+Bool(e.FirstReadyAlive)+
                ",\"first_before_second_alive\":"+Bool(e.FirstBeforeSecondAlive)+",\"first_after_second_alive\":"+Bool(e.FirstAfterSecondAlive)+
                ",\"second_created\":"+NullableBool(e.SecondCreated)+",\"second_create_error\":"+Number(e.SecondCreateError)+
                ",\"second_entry_observed\":"+NullableBool(e.SecondEntryObserved)+",\"first_exact_exit\":"+Bool(e.FirstExactExit)+
                ",\"first_exit_code\":"+Number(e.FirstExitCode)+",\"child_handles_closed\":"+Bool(e.ChildrenClosed)+
                ",\"all_owned_handles_closed\":"+Bool(e.AllHandlesClosed)+Counts("before",e.Before)+Counts("during",e.During)+Counts("after",e.After)+
                ",\"cleanup_query_success\":"+Bool(e.After.HasValue)+",\"cleanup_pending\":"+Bool(CleanupPending(e))+
                ",\"after_create_members\":"+SnapshotJson(e.AfterCreate)+",\"after_ready_members\":"+SnapshotJson(e.AfterReady)+",\"before_cleanup_members\":"+SnapshotJson(e.BeforeCleanup)+
                ",\"network_used\":false,\"external_requests\":0,\"model_turns_requested\":0}";
        }
        static void Require(bool value, string code) { if(!value) throw new ProbeError(code); }
        sealed class Handles {
            readonly List<IntPtr> held=new List<IntPtr>(); internal bool Clean=true;
            internal IntPtr Own(IntPtr handle) { Require(handle!=IntPtr.Zero && handle!=new IntPtr(-1),"handle_open_failed"); held.Add(handle); return handle; }
            internal bool Close(IntPtr handle) {
                if(handle==IntPtr.Zero) return true;
                bool result=Native.CloseHandle(handle); if(result) held.Remove(handle); else Clean=false; return result;
            }
            internal bool CloseAll() { for(int i=held.Count-1;i>=0;i--) { if(Native.CloseHandle(held[i])) held.RemoveAt(i); else Clean=false; } return Clean && held.Count==0; }
        }
        static uint TokenUInt(IntPtr token, int kind) {
            uint size; Native.GetTokenInformation(token,kind,IntPtr.Zero,0,out size); Require(size>=4 && size<=65536,"token_size_failed");
            IntPtr buffer=Marshal.AllocHGlobal((int)size);
            try { Require(Native.GetTokenInformation(token,kind,buffer,size,out size),"token_query_failed"); return unchecked((uint)Marshal.ReadInt32(buffer)); }
            finally { Marshal.FreeHGlobal(buffer); }
        }
        static void RequireMediumProcess(IntPtr process, Handles handles) {
            IntPtr token; Require(Native.OpenProcessToken(process,8,out token),"token_open_failed"); handles.Own(token);
            try {
                uint size; Native.GetTokenInformation(token,25,IntPtr.Zero,0,out size); Require(size>=IntPtr.Size && size<=65536,"integrity_size_failed");
                IntPtr buffer=Marshal.AllocHGlobal((int)size);
                try {
                    Require(Native.GetTokenInformation(token,25,buffer,size,out size),"integrity_query_failed");
                    IntPtr sid=Marshal.ReadIntPtr(buffer); Require(sid!=IntPtr.Zero,"integrity_sid_failed"); IntPtr countPointer=Native.GetSidSubAuthorityCount(sid);
                    Require(countPointer!=IntPtr.Zero,"integrity_sid_failed"); uint count=Marshal.ReadByte(countPointer); Require(count>0,"integrity_rid_missing");
                    IntPtr ridPointer=Native.GetSidSubAuthority(sid,count-1); Require(ridPointer!=IntPtr.Zero,"integrity_rid_missing");
                    uint rid=unchecked((uint)Marshal.ReadInt32(ridPointer)); Require(rid==0x2000 && TokenUInt(token,20)==0 && TokenUInt(token,29)==0,"normal_medium_required");
                } finally { Marshal.FreeHGlobal(buffer); }
            } finally { Require(handles.Close(token),"token_close_failed"); }
        }
        static string OwnSid(Handles handles) {
            IntPtr token; Require(Native.OpenProcessToken(Native.GetCurrentProcess(),8,out token),"own_token_open_failed"); handles.Own(token);
            try {
                uint size; Native.GetTokenInformation(token,1,IntPtr.Zero,0,out size); Require(size>=IntPtr.Size && size<=65536,"own_token_size_failed");
                IntPtr buffer=Marshal.AllocHGlobal((int)size);
                try { Require(Native.GetTokenInformation(token,1,buffer,size,out size),"own_token_query_failed"); IntPtr sid=Marshal.ReadIntPtr(buffer); Require(sid!=IntPtr.Zero,"own_sid_missing"); return new SecurityIdentifier(sid).Value; }
                finally { Marshal.FreeHGlobal(buffer); }
            } finally { Require(handles.Close(token),"own_token_close_failed"); }
        }
        static void CheckLayouts() {
            Require(IntPtr.Size==8,"x64_required");
            Require(BitConverter.IsLittleEndian && Marshal.SizeOf(typeof(BasicProcessIdListLayout))==16 && Marshal.OffsetOf(typeof(BasicProcessIdListLayout),"Assigned").ToInt32()==0 && Marshal.OffsetOf(typeof(BasicProcessIdListLayout),"Count").ToInt32()==4 && Marshal.OffsetOf(typeof(BasicProcessIdListLayout),"FirstId").ToInt32()==8,"process_list_abi_failed");
            Require(Marshal.SizeOf(typeof(BasicLimit))==64 && Marshal.SizeOf(typeof(IoCounters))==48 && Marshal.SizeOf(typeof(ExtendedLimit))==144 && Marshal.SizeOf(typeof(JobAccounting))==48,"job_abi_failed");
            Require(Marshal.OffsetOf(typeof(BasicLimit),"LimitFlags").ToInt32()==16 && Marshal.OffsetOf(typeof(BasicLimit),"ActiveProcessLimit").ToInt32()==40 && Marshal.OffsetOf(typeof(ExtendedLimit),"IoInfo").ToInt32()==64 && Marshal.OffsetOf(typeof(JobAccounting),"ActiveProcesses").ToInt32()==40,"job_offsets_failed");
        }
        static string Canonical(string path) {
            string full=Path.GetFullPath(path); Require(full.Length>=3 && full[1]==':' && full[2]=='\\' && !full.Substring(2).Contains(":"),"local_path_required");
            return full.Length==3?full:full.TrimEnd('\\');
        }
        static void VerifyPath(IntPtr handle, string expected, bool directory) {
            FileInformation info; Require(Native.GetFileInformationByHandle(handle,out info),"path_metadata_failed");
            Require((info.Attributes&0x400)==0 && ((info.Attributes&0x10)!=0)==directory && (directory || info.Links==1),"path_type_rejected");
            StringBuilder found=new StringBuilder(32768); uint length=Native.GetFinalPathNameByHandleW(handle,found,32768,0);
            Require(length>0 && length<32768,"final_path_query_failed"); string actual=found.ToString(); if(actual.StartsWith(@"\\?\",StringComparison.Ordinal)) actual=actual.Substring(4);
            Require(String.Equals(Canonical(actual),Canonical(expected),StringComparison.OrdinalIgnoreCase),"final_path_mismatch");
        }
        static IntPtr PinPath(string path, bool directory, Handles handles) {
            // OPEN_REPARSE_POINT observes the node itself; no FILE_SHARE_DELETE pins its name.
            uint access=directory?0x20080u:0x80020000u;
            IntPtr handle=handles.Own(Native.CreateFileW(path,access,directory?3u:1u,IntPtr.Zero,3,0x00200000u|(directory?0x02000000u:0u),IntPtr.Zero));
            VerifyPath(handle,path,directory); return handle;
        }
        static void PinAncestors(string path, Handles handles) {
            string full=Canonical(path), root=Path.GetPathRoot(full); PinPath(root,true,handles);
            string current=root; string relative=full.Substring(root.Length);
            if(relative.Length==0) return;
            foreach(string part in relative.Split('\\')) { Require(part.Length>0 && part!="." && part!="..","path_component_rejected"); current=Path.Combine(current,part); PinPath(current,true,handles); }
        }
        static void VerifyOwnAcl(IntPtr handle, string ownSid, bool directory) {
            IntPtr owner,group,dacl,sacl,descriptor; uint error=Native.GetSecurityInfo(handle,1,5,out owner,out group,out dacl,out sacl,out descriptor);
            Require(error==0 && descriptor!=IntPtr.Zero,"acl_query_failed");
            try {
                uint size=Native.GetSecurityDescriptorLength(descriptor); Require(size>0 && size<=65536 && owner!=IntPtr.Zero && dacl!=IntPtr.Zero,"acl_metadata_failed");
                byte[] bytes=new byte[size]; Marshal.Copy(descriptor,bytes,0,(int)size);
                FileSystemSecurity security=directory?(FileSystemSecurity)new DirectorySecurity():new FileSecurity(); security.SetSecurityDescriptorBinaryForm(bytes);
                Require(security.AreAccessRulesProtected && security.GetOwner(typeof(SecurityIdentifier)).Value==ownSid,"acl_owner_or_protection_failed");
                AuthorizationRuleCollection rules=security.GetAccessRules(true,true,typeof(SecurityIdentifier)); Require(rules.Count==1,"acl_rules_rejected");
                FileSystemAccessRule rule=(FileSystemAccessRule)rules[0];
                Require(rule.IdentityReference.Value==ownSid && rule.AccessControlType==AccessControlType.Allow && rule.FileSystemRights==FileSystemRights.FullControl && !rule.IsInherited && rule.PropagationFlags==PropagationFlags.None && rule.InheritanceFlags==(directory?(InheritanceFlags.ContainerInherit|InheritanceFlags.ObjectInherit):InheritanceFlags.None),"acl_rule_rejected");
            } finally { Native.LocalFree(descriptor); }
        }
        static IntPtr OwnDescriptor(string ownSid, bool directory) {
            IntPtr descriptor; uint size; Require(Native.ConvertStringSecurityDescriptorToSecurityDescriptorW("O:"+ownSid+"D:P(A;"+(directory?"OICI":"")+";FA;;;"+ownSid+")",1,out descriptor,out size),"acl_descriptor_failed"); return descriptor;
        }
        static IntPtr NewDirectory(string path, string ownSid, bool allowExisting, Handles handles) {
            IntPtr descriptor=OwnDescriptor(ownSid,true);
            try {
                SecurityAttributes attributes=new SecurityAttributes(); attributes.Length=(uint)Marshal.SizeOf(typeof(SecurityAttributes)); attributes.Descriptor=descriptor;
                bool created=Native.CreateDirectoryW(path,ref attributes); int error=Marshal.GetLastWin32Error();
                Require(created || allowExisting && error==183,"directory_create_or_collision_failed");
                IntPtr handle=PinPath(path,true,handles); VerifyOwnAcl(handle,ownSid,true); return handle;
            } finally { Native.LocalFree(descriptor); }
        }
        static string CreateAttemptDirectory(string attempt, string ownSid, Handles handles) {
            PinAncestors(Path.GetDirectoryName(BaseRoot),handles);
            // Existing parents are never changed. An existing private root must already pass its ACL.
            NewDirectory(BaseRoot,ownSid,true,handles); string path=Path.Combine(BaseRoot,attempt); NewDirectory(path,ownSid,false,handles); return path;
        }
        static string HashHandle(IntPtr handle) {
            using(SafeFileHandle wrapper=new SafeFileHandle(handle,false)) using(FileStream stream=new FileStream(wrapper,FileAccess.Read)) using(SHA256 sha=SHA256.Create()) {
                stream.Position=0; return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","");
            }
        }
        static IntPtr CopyImage(string source, string target, string ownSid, Handles handles, out string hash) {
            PinAncestors(Path.GetDirectoryName(source),handles); IntPtr sourceHandle=PinPath(source,false,handles); hash=HashHandle(sourceHandle);
            IntPtr descriptor=OwnDescriptor(ownSid,false), attributesMemory=IntPtr.Zero; IntPtr destination=IntPtr.Zero;
            try {
                SecurityAttributes attributes=new SecurityAttributes(); attributes.Length=(uint)Marshal.SizeOf(typeof(SecurityAttributes)); attributes.Descriptor=descriptor;
                attributesMemory=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(SecurityAttributes))); Marshal.StructureToPtr(attributes,attributesMemory,false);
                destination=handles.Own(Native.CreateFileW(target,0xC0020000,1,attributesMemory,1,0x00200000,IntPtr.Zero));
                VerifyPath(destination,target,false); VerifyOwnAcl(destination,ownSid,false);
                using(SafeFileHandle input=new SafeFileHandle(sourceHandle,false)) using(SafeFileHandle output=new SafeFileHandle(destination,false))
                using(FileStream from=new FileStream(input,FileAccess.Read)) using(FileStream to=new FileStream(output,FileAccess.ReadWrite)) { from.Position=0; from.CopyTo(to); to.Flush(true); }
                VerifyPath(sourceHandle,source,false); VerifyPath(destination,target,false); Require(HashHandle(destination)==hash,"image_copy_hash_failed");
                Require(handles.Close(destination),"image_write_handle_close_failed"); destination=PinPath(target,false,handles); VerifyOwnAcl(destination,ownSid,false); Require(HashHandle(destination)==hash,"image_pinned_hash_failed"); return destination;
            } finally { if(attributesMemory!=IntPtr.Zero) Marshal.FreeHGlobal(attributesMemory); Native.LocalFree(descriptor); }
        }
        static IntPtr CreateJob(string attempt, Handles handles, Evidence evidence) {
            IntPtr job=Native.CreateJobObjectW(IntPtr.Zero,"Local\\HereIAm.P6R7.JobLimit."+attempt); int error=Marshal.GetLastWin32Error(); handles.Own(job);
            // Collision check must precede any change to the returned object.
            Require(error!=183,"job_collision"); ExtendedLimit limits=new ExtendedLimit(); limits.BasicLimitInformation.LimitFlags=RequiredFlags; limits.BasicLimitInformation.ActiveProcessLimit=1;
            Require(Native.SetInformationJobObject(job,JobObjectExtendedLimitInformation,ref limits,144),"job_limit_set_failed");
            Require(Native.QueryInformationJobObject(job,JobObjectExtendedLimitInformation,out limits,144,IntPtr.Zero),"job_limit_readback_failed");
            evidence.LimitFlags=limits.BasicLimitInformation.LimitFlags; evidence.ActiveProcessLimit=limits.BasicLimitInformation.ActiveProcessLimit;
            Require(evidence.LimitFlags==RequiredFlags && evidence.ActiveProcessLimit==1,"job_limit_readback_mismatch"); return job;
        }
        static JobAccounting ReadAccounting(IntPtr job) { JobAccounting result; Require(Native.QueryInformationJobObject(job,JobObjectBasicAccountingInformation,out result,48,IntPtr.Zero),"job_accounting_failed"); return result; }
        static JobAccounting? TryAccounting(IntPtr job) { JobAccounting result; return Native.QueryInformationJobObject(job,JobObjectBasicAccountingInformation,out result,48,IntPtr.Zero)?(JobAccounting?)result:null; }
        static WaitState ObserveWait(IntPtr process) { uint state=Native.WaitForSingleObject(process,0); return state==WaitObject0?WaitState.Signaled:state==WaitTimeout?WaitState.Timeout:WaitState.Unknown; }
        static MemberObservation InspectMember(uint listedId, IntPtr job, Creation first, string expectedImage, string systemDirectory, ulong listStarted, Handles handles) {
            MemberObservation result=new MemberObservation(); IntPtr process=IntPtr.Zero;
            try {
                // The only OpenProcess caller receives IDs from the bounded own-Job list.
                process=Native.OpenProcess(0x00101000,false,listedId);
                if(process==IntPtr.Zero) { result.Status=MemberStatus.OpenFailed; result.Error=unchecked((uint)Marshal.GetLastWin32Error()); return result; }
                handles.Own(process); result.Opened=true;
                uint actualId=Native.GetProcessId(process); ulong creation=CreationTime(process); result.CreationObserved=true; result.CreationPrecedesList=creation<=listStarted;
                if(actualId!=listedId || !result.CreationPrecedesList) { result.Status=MemberStatus.IdentityFailed; return result; }
                bool member; bool queried=Native.IsProcessInJob(process,job,out member);
                if(!queried || !member) { result.Status=MemberStatus.MembershipFailed; if(!queried) result.Error=unchecked((uint)Marshal.GetLastWin32Error()); return result; }
                result.OwnJobMember=true;
                if(listedId==first.Info.ProcessId) {
                    result.MatchesFirst=first.Info.Process!=IntPtr.Zero && Native.GetProcessId(first.Info.Process)==actualId && CreationTime(first.Info.Process)==creation && (first.CreationTime==0 || first.CreationTime==creation);
                    if(!result.MatchesFirst) { result.Status=MemberStatus.IdentityFailed; return result; }
                }
                result.IdentityConfirmed=true; result.BeforeWait=ObserveWait(process);
                if(result.BeforeWait!=WaitState.Timeout) { result.Status=result.BeforeWait==WaitState.Signaled?MemberStatus.SignaledBeforeImage:MemberStatus.WaitFailed; return result; }
                uint length=32768; StringBuilder path=new StringBuilder((int)length);
                if(!Native.QueryFullProcessImageNameW(process,0,path,ref length) || length==0 || length>=32768) { result.Status=MemberStatus.ImageFailed; result.Error=unchecked((uint)Marshal.GetLastWin32Error()); return result; }
                result.Image=ClassifyImage(path.ToString(),expectedImage,systemDirectory);
                if(result.Image==ImageClass.QueryFailed) { result.Status=MemberStatus.ImageFailed; return result; }
                if(Native.GetProcessId(process)!=actualId || CreationTime(process)!=creation) { result.Status=MemberStatus.IdentityFailed; result.IdentityConfirmed=false; return result; }
                result.AfterWait=ObserveWait(process); result.Status=result.AfterWait==WaitState.Unknown?MemberStatus.WaitFailed:MemberStatus.Observed;
            } catch { result.Status=MemberStatus.IdentityFailed; }
            finally { if(process!=IntPtr.Zero) { result.HandleClosed=handles.Close(process); if(!result.HandleClosed) result.Status=MemberStatus.CloseFailed; } }
            return result;
        }
        static MemberSnapshot CaptureMembers(IntPtr job, Creation first, string expectedImage, Handles handles) {
            MemberSnapshot result=new MemberSnapshot(); Stopwatch entire=Stopwatch.StartNew(); IntPtr buffer=IntPtr.Zero;
            try {
                Require(job!=IntPtr.Zero,"own_job_required"); result.AccountingBefore=TryAccounting(job);
                byte[] bytes=new byte[ProcessListBufferBytes]; buffer=Marshal.AllocHGlobal(ProcessListBufferBytes); Marshal.Copy(bytes,0,buffer,bytes.Length);
                ulong listStarted=unchecked((ulong)DateTime.UtcNow.ToFileTimeUtc()); Stopwatch queryTime=Stopwatch.StartNew(); uint returned;
                bool queried=Native.QueryInformationJobObject(job,JobObjectBasicProcessIdList,buffer,ProcessListBufferBytes,out returned); uint error=queried?0:unchecked((uint)Marshal.GetLastWin32Error()); queryTime.Stop();
                result.QueryError=error; result.ReturnedBytes=queried?(uint?)returned:null; result.QueryMilliseconds=(uint)Math.Min(queryTime.ElapsedMilliseconds,UInt32.MaxValue);
                if(queried) Marshal.Copy(buffer,bytes,0,bytes.Length);
                result.List=ParseProcessList(bytes,returned,queried);
                if(result.List.Status==ListStatus.Parsed) {
                    string systemDirectory=Canonical(Environment.SystemDirectory);
                    foreach(uint id in result.List.Ids) result.Members.Add(InspectMember(id,job,first,expectedImage,systemDirectory,listStarted,handles));
                }
                result.AccountingAfter=TryAccounting(job);
                result.CountsConsistent=result.List.Status==ListStatus.Parsed && result.AccountingBefore.HasValue && result.AccountingAfter.HasValue && result.AccountingBefore.Value.ActiveProcesses==result.List.Count && result.AccountingAfter.Value.ActiveProcesses==result.List.Count && result.AccountingBefore.Value.TotalProcesses==result.AccountingAfter.Value.TotalProcesses;
                result.Complete=true; result.Complete=SnapshotAccepted(result);
            } catch { result.Complete=false; }
            finally { if(buffer!=IntPtr.Zero) Marshal.FreeHGlobal(buffer); entire.Stop(); result.SnapshotMilliseconds=(uint)Math.Min(entire.ElapsedMilliseconds,UInt32.MaxValue); }
            return result;
        }
        static string EventName(string part, string attempt) { return "Local\\HereIAm.P6R7.JobLimit."+part+"."+attempt; }
        static IntPtr NewEvent(string part, string attempt, Handles handles) { IntPtr result=Native.CreateEventW(IntPtr.Zero,true,false,EventName(part,attempt)); int error=Marshal.GetLastWin32Error(); handles.Own(result); Require(error!=183,"event_collision"); return result; }
        static IntPtr MinimalEnvironment(string root) {
            string windows=Environment.GetFolderPath(Environment.SpecialFolder.Windows); Require(windows==Canonical(windows),"system_root_rejected");
            return Marshal.StringToHGlobalUni("SystemDrive="+Path.GetPathRoot(windows).TrimEnd('\\')+"\0SystemRoot="+windows+"\0TEMP="+root+"\0TMP="+root+"\0\0");
        }
        public static uint CreationFlags(bool detached) { return CreateSuspended|ExtendedStartupInfoPresent|CreateUnicodeEnvironment|(detached?DetachedProcess:CreateNoWindow); }
        static void CreateSuspendedInJob(Creation result, string image, string attempt, string role, IntPtr job, string root, bool detached) {
            IntPtr bytes=IntPtr.Zero,list=IntPtr.Zero,environment=IntPtr.Zero; bool initialized=false;
            try {
                IntPtr size=IntPtr.Zero; Native.InitializeProcThreadAttributeList(IntPtr.Zero,1,0,ref size); Require(size.ToInt64()>0 && size.ToInt64()<=65536,"attribute_size_failed");
                list=Marshal.AllocHGlobal(size); Require(Native.InitializeProcThreadAttributeList(list,1,0,ref size),"attribute_init_failed"); initialized=true;
                bytes=Marshal.AllocHGlobal(IntPtr.Size); Marshal.WriteIntPtr(bytes,job); Require(Native.UpdateProcThreadAttribute(list,0,new IntPtr(ProcThreadAttributeJobList),bytes,new IntPtr(IntPtr.Size),IntPtr.Zero,IntPtr.Zero),"job_attribute_failed");
                environment=MinimalEnvironment(root); StartupInfoEx startup=new StartupInfoEx(); startup.StartupInfo.cb=(uint)Marshal.SizeOf(typeof(StartupInfoEx)); startup.AttributeList=list;
                result.Attempted=true;
                // Caller owns the Creation object before this call: no post-create exception can lose handles.
                StringBuilder command=new StringBuilder("\""+image+"\" --sentinel "+attempt+" "+role);
                result.Created=Native.CreateProcessW(image,command,IntPtr.Zero,IntPtr.Zero,false,CreationFlags(detached),environment,root,ref startup,out result.Info);
                result.Error=result.Created?0:unchecked((uint)Marshal.GetLastWin32Error());
            } finally { if(initialized) Native.DeleteProcThreadAttributeList(list); if(list!=IntPtr.Zero) Marshal.FreeHGlobal(list); if(bytes!=IntPtr.Zero) Marshal.FreeHGlobal(bytes); if(environment!=IntPtr.Zero) Marshal.FreeHGlobal(environment); }
        }
        static ulong CreationTime(IntPtr process) { FileTime creation,exit,kernel,user; Require(Native.GetProcessTimes(process,out creation,out exit,out kernel,out user),"process_time_failed"); Require(creation.Value!=0,"process_time_missing"); return creation.Value; }
        static bool Alive(Creation child) { return child.Created && child.Info.Process!=IntPtr.Zero && Native.WaitForSingleObject(child.Info.Process,0)==WaitTimeout; }
        static void VerifyBinding(Creation child, IntPtr job, string image, IntPtr imageHandle, string hash, Handles handles) {
            Require(Alive(child) && Native.GetProcessId(child.Info.Process)==child.Info.ProcessId && child.Info.ProcessId!=0,"process_identity_failed");
            ulong creation=CreationTime(child.Info.Process); if(child.CreationTime==0) child.CreationTime=creation; Require(child.CreationTime==creation,"process_creation_changed");
            bool member; Require(Native.IsProcessInJob(child.Info.Process,job,out member) && member,"job_membership_failed");
            uint size=32768; StringBuilder found=new StringBuilder((int)size); Require(Native.QueryFullProcessImageNameW(child.Info.Process,0,found,ref size),"process_image_failed");
            Require(String.Equals(Canonical(found.ToString()),Canonical(image),StringComparison.OrdinalIgnoreCase),"process_image_mismatch");
            VerifyPath(imageHandle,image,false); Require(HashHandle(imageHandle)==hash,"process_image_hash_mismatch"); RequireMediumProcess(child.Info.Process,handles);
        }
        static bool CloseExact(Creation child) {
            bool closed=true;
            if(child.Info.Process!=IntPtr.Zero) {
                uint state=Native.WaitForSingleObject(child.Info.Process,0);
                if(state!=WaitObject0) { bool terminated=Native.TerminateProcess(child.Info.Process,91); state=Native.WaitForSingleObject(child.Info.Process,5000); closed=terminated && state==WaitObject0; }
                bool handleClosed=Native.CloseHandle(child.Info.Process); closed=handleClosed && closed; if(handleClosed) child.Info.Process=IntPtr.Zero;
            }
            if(child.Info.Thread!=IntPtr.Zero) { bool handleClosed=Native.CloseHandle(child.Info.Thread); closed=handleClosed && closed; if(handleClosed) child.Info.Thread=IntPtr.Zero; }
            return closed;
        }
        static int Sentinel(string[] args) {
            Require(args.Length==3 && (args[2]=="First" || args[2]=="Second"),"sentinel_arguments_rejected"); Guid attempt; Require(Guid.TryParseExact(args[1],"D",out attempt),"sentinel_attempt_rejected");
            Handles handles=new Handles(); int result=2;
            try {
                IntPtr ready=handles.Own(Native.OpenEventW(2,false,EventName("Ready",args[1]))), release=handles.Own(Native.OpenEventW(0x100000,false,EventName("Release",args[1]))), marker=handles.Own(Native.OpenEventW(2,false,EventName(args[2],args[1])));
                Require(Native.SetEvent(marker) && Native.SetEvent(ready),"sentinel_signal_failed"); result=Native.WaitForSingleObject(release,30000)==WaitObject0?0:3;
            } finally { if(!handles.CloseAll()) result=2; }
            return result;
        }
        static int Apply(bool detached) {
            Evidence evidence=new Evidence(); Handles handles=new Handles(); Creation first=new Creation(),second=new Creation(); IntPtr job=IntPtr.Zero,secondEvent=IntPtr.Zero; string diagnosticImage=null;
            evidence.Detached=detached;
            try {
                evidence.FailureStage=1; CheckLayouts(); RequireMediumProcess(Native.GetCurrentProcess(),handles);
                string ownSid=OwnSid(handles), source=Canonical(System.Reflection.Assembly.GetExecutingAssembly().Location);
                evidence.FailureStage=2; PinAncestors(Path.GetDirectoryName(source),handles); PinPath(source,false,handles);
                string attempt=Guid.NewGuid().ToString("D"), root=CreateAttemptDirectory(attempt,ownSid,handles);
                string image=Path.Combine(root,"probe.exe"), hash;
                diagnosticImage=image;
                evidence.FailureStage=3;
                IntPtr imageHandle=CopyImage(source,image,ownSid,handles,out hash);
                evidence.FailureStage=4;
                IntPtr ready=NewEvent("Ready",attempt,handles),release=NewEvent("Release",attempt,handles),firstEvent=NewEvent("First",attempt,handles); secondEvent=NewEvent("Second",attempt,handles);
                evidence.FailureStage=5;
                job=CreateJob(attempt,handles,evidence);
                evidence.FailureStage=6;
                CreateSuspendedInJob(first,image,attempt,"First",job,root,detached); Require(first.Created,"first_create_failed");
                evidence.AfterCreate=CaptureMembers(job,first,image,handles);
                VerifyBinding(first,job,image,imageHandle,hash,handles); evidence.FirstPreResumeIdentity=true;
                evidence.FailureStage=7;
                Require(Native.ResumeThread(first.Info.Thread)==1,"first_resume_failed");
                Require(Native.WaitForSingleObject(ready,5000)==WaitObject0 && Native.WaitForSingleObject(firstEvent,0)==WaitObject0 && Alive(first),"first_ready_failed"); evidence.FirstReadyAlive=true;
                evidence.AfterReady=CaptureMembers(job,first,image,handles);
                evidence.Before=ReadAccounting(job); Require(evidence.Before.Value.ActiveProcesses==1 && evidence.Before.Value.TotalProcesses==1,"first_accounting_failed");
                Require(SnapshotAccepted(evidence.AfterCreate) && SnapshotAccepted(evidence.AfterReady),"member_diagnostics_incomplete");
                VerifyBinding(first,job,image,imageHandle,hash,handles); evidence.FirstBeforeSecondAlive=Alive(first); Require(evidence.FirstBeforeSecondAlive,"first_before_second_failed");
                // Exactly one atomic second create. It is never resumed, even if unexpectedly created.
                evidence.FailureStage=8;
                CreateSuspendedInJob(second,image,attempt,"Second",job,root,detached); evidence.SecondCreated=second.Created; evidence.SecondCreateError=second.Error;
                evidence.FirstAfterSecondAlive=Alive(first); Require(evidence.FirstAfterSecondAlive,"first_after_second_failed");
                evidence.During=ReadAccounting(job); uint secondState=Native.WaitForSingleObject(secondEvent,0); Require(secondState==WaitObject0 || secondState==WaitTimeout,"second_event_query_failed"); evidence.SecondEntryObserved=secondState==WaitObject0;
                Require(!second.Created && second.Error==ErrorNotEnoughQuota && evidence.SecondEntryObserved==false,"second_rejection_unconfirmed");
                evidence.FailureStage=9;
                VerifyBinding(first,job,image,imageHandle,hash,handles); Require(Native.SetEvent(release),"first_release_failed");
                evidence.FirstExactExit=Native.WaitForSingleObject(first.Info.Process,5000)==WaitObject0; Require(evidence.FirstExactExit,"first_exit_unconfirmed");
                uint exitCode; Require(Native.GetExitCodeProcess(first.Info.Process,out exitCode),"first_exit_code_failed"); evidence.FirstExitCode=exitCode; Require(exitCode==0,"first_exit_nonzero"); evidence.OperationComplete=true; evidence.FailureStage=0;
            } catch { /* Report only typed evidence, never exception text, paths or identity. */ }
            finally {
                // No prior success survives a failed cleanup. Query while this exact Job is still held.
                if(job!=IntPtr.Zero && diagnosticImage!=null) evidence.BeforeCleanup=CaptureMembers(job,first,diagnosticImage,handles);
                evidence.ChildrenClosed=CloseExact(second) & CloseExact(first);
                if(second.Attempted) { evidence.SecondCreated=second.Created; evidence.SecondCreateError=second.Error; }
                if(secondEvent!=IntPtr.Zero) { uint state=Native.WaitForSingleObject(secondEvent,0); if(state==WaitObject0) evidence.SecondEntryObserved=true; else if(state==WaitTimeout && evidence.SecondEntryObserved!=true) evidence.SecondEntryObserved=false; else if(state!=WaitTimeout) evidence.SecondEntryObserved=null; }
                evidence.After=null;
                if(job!=IntPtr.Zero) {
                    for(int i=0;i<100;i++) {
                        JobAccounting result; bool known=Native.QueryInformationJobObject(job,JobObjectBasicAccountingInformation,out result,48,IntPtr.Zero); evidence.After=known?(JobAccounting?)result:null;
                        if(!known || result.ActiveProcesses==0) break; Thread.Sleep(10);
                    }
                }
                evidence.AllHandlesClosed=handles.CloseAll();
            }
            Console.WriteLine(Report(evidence)); return Passed(evidence)?0:2;
        }
        public static MemberSnapshot SnapshotFixture() {
            MemberSnapshot result=new MemberSnapshot(); result.List.Status=ListStatus.Parsed; result.List.Assigned=result.List.Count=1;
            JobAccounting accounting=new JobAccounting(); accounting.ActiveProcesses=accounting.TotalProcesses=1; result.AccountingBefore=result.AccountingAfter=accounting;
            result.QueryError=0; result.ReturnedBytes=16; result.QueryMilliseconds=result.SnapshotMilliseconds=0; result.Complete=result.CountsConsistent=true;
            MemberObservation member=new MemberObservation(); member.Status=MemberStatus.Observed; member.Image=ImageClass.ExpectedProbe; member.BeforeWait=member.AfterWait=WaitState.Timeout;
            member.Opened=member.IdentityConfirmed=member.CreationObserved=member.CreationPrecedesList=member.OwnJobMember=member.MatchesFirst=member.HandleClosed=true; result.Members.Add(member); return result;
        }
        static byte[] ListFixture(uint assigned, uint count, ulong first, ulong second) {
            byte[] result=new byte[ProcessListBufferBytes]; Buffer.BlockCopy(BitConverter.GetBytes(assigned),0,result,0,4); Buffer.BlockCopy(BitConverter.GetBytes(count),0,result,4,4);
            Buffer.BlockCopy(BitConverter.GetBytes(first),0,result,8,8); Buffer.BlockCopy(BitConverter.GetBytes(second),0,result,16,8); return result;
        }
        static void ParserSelfTest() {
            Require(ParseProcessList(ListFixture(0,0,0,0),8,true).Status==ListStatus.Parsed,"parser_empty_failed");
            Require(ParseProcessList(ListFixture(1,1,123,0),16,true).Status==ListStatus.Parsed,"parser_one_failed");
            byte[] full=ListFixture(16,16,0,0); for(int i=0;i<16;i++) Buffer.BlockCopy(BitConverter.GetBytes((ulong)(i+1)),0,full,8+8*i,8);
            Require(ParseProcessList(full,136,true).Status==ListStatus.Parsed,"parser_capacity_failed");
            Require(ParseProcessList(full,136,false).Status==ListStatus.QueryFailed,"parser_query_failed");
            Require(ParseProcessList(null,0,true).Status==ListStatus.BufferRejected,"parser_null_failed");
            Require(ParseProcessList(new byte[135],135,true).Status==ListStatus.BufferRejected,"parser_buffer_failed");
            Require(ParseProcessList(full,0,true).Status==ListStatus.LengthRejected,"parser_zero_length_failed");
            Require(ParseProcessList(full,137,true).Status==ListStatus.LengthRejected,"parser_long_length_failed");
            Require(ParseProcessList(ListFixture(17,17,1,2),136,true).Status==ListStatus.CountLimit,"parser_limit_failed");
            Require(ParseProcessList(ListFixture(UInt32.MaxValue,UInt32.MaxValue,1,2),136,true).Status==ListStatus.CountLimit,"parser_overflow_failed");
            Require(ParseProcessList(ListFixture(2,1,1,2),136,true).Status==ListStatus.CountMismatch,"parser_count_failed");
            Require(ParseProcessList(ListFixture(1,1,1,2),8,true).Status==ListStatus.Truncated,"parser_truncated_failed");
            Require(ParseProcessList(ListFixture(1,1,0,0),16,true).Status==ListStatus.InvalidId,"parser_zero_id_failed");
            Require(ParseProcessList(ListFixture(1,1,0x100000000,0),16,true).Status==ListStatus.InvalidId,"parser_wide_id_failed");
            Require(ParseProcessList(ListFixture(2,2,1,1),24,true).Status==ListStatus.DuplicateId,"parser_duplicate_failed");
            Require(ParseProcessList(ListFixture(0,0,0,0),16,true).Status==ListStatus.Parsed,"parser_padding_failed");
        }
        public static Evidence PassingFixture() {
            Evidence e=new Evidence(); e.OperationComplete=e.FirstPreResumeIdentity=e.FirstReadyAlive=e.FirstBeforeSecondAlive=e.FirstAfterSecondAlive=e.FirstExactExit=e.ChildrenClosed=e.AllHandlesClosed=true;
            e.AfterCreate=SnapshotFixture(); e.AfterReady=SnapshotFixture(); e.BeforeCleanup=SnapshotFixture();
            e.SecondCreated=e.SecondEntryObserved=false; e.SecondCreateError=1816; e.LimitFlags=0x2008; e.ActiveProcessLimit=1; e.FirstExitCode=0;
            JobAccounting before=new JobAccounting(); before.ActiveProcesses=before.TotalProcesses=1; e.Before=before; e.During=before; e.After=new JobAccounting(); return e;
        }
        static int SelfTest() {
            CheckLayouts(); Require(Passed(PassingFixture()),"passing_policy_failed");
            Require(CreationFlags(false)==0x08080404 && CreationFlags(true)==0x0008040C && (CreationFlags(true)&(0x08000000u|0x10u))==0,"creation_flags_failed");
            Action<Evidence>[] failures={e=>e.OperationComplete=false,e=>e.LimitFlags=null,e=>e.LimitFlags=8,e=>e.ActiveProcessLimit=2,e=>e.FirstPreResumeIdentity=false,e=>e.FirstReadyAlive=false,e=>e.FirstBeforeSecondAlive=false,e=>e.FirstAfterSecondAlive=false,e=>e.Before=null,e=>e.Before=new JobAccounting(),e=>e.During=null,e=>e.SecondCreated=true,e=>e.SecondCreated=null,e=>e.SecondCreateError=5,e=>e.SecondCreateError=null,e=>e.SecondEntryObserved=true,e=>e.SecondEntryObserved=null,e=>e.FirstExactExit=false,e=>e.FirstExitCode=91,e=>e.FirstExitCode=null,e=>e.ChildrenClosed=false,e=>e.AllHandlesClosed=false,e=>e.After=null,e=>{JobAccounting a=new JobAccounting();a.ActiveProcesses=1;e.After=a;},e=>e.AfterCreate=null,e=>e.AfterReady.Complete=false,e=>e.BeforeCleanup.CountsConsistent=false};
            foreach(Action<Evidence> change in failures) { Evidence e=PassingFixture(); change(e); Require(!Passed(e),"negative_policy_failed"); }
            Evidence unknown=new Evidence(); Require(CleanupPending(unknown) && Report(unknown).Contains("\"after_active\":null"),"unknown_policy_failed");
            ParserSelfTest();
            Console.WriteLine("{\"schema\":\"p6_r7_job_limit_probe_v4\",\"mode\":\"selftest\",\"passed\":true,\"native_executed\":false,\"policy_cases\":29,\"negative_cases\":27,\"parser_cases\":16,\"launch_flag_cases\":2,\"abi_checked\":true}"); return 0;
        }
        public static int Main(string[] args) {
            try {
                if(args.Length==0 || args.Length==1 && args[0]=="--plan") { Console.WriteLine("{\"schema\":\"p6_r7_job_limit_probe_v4\",\"mode\":\"plan\",\"passed\":false,\"code\":\"apply_required\",\"native_executed\":false}"); return 0; }
                if(args.Length==1 && args[0]=="--selftest") return SelfTest();
                if(args.Length==1 && args[0]=="--apply-job-limit-synthetic") return Apply(false);
                if(args.Length==1 && args[0]=="--apply-job-limit-synthetic-detached") return Apply(true);
                if(args.Length>0 && args[0]=="--sentinel") return Sentinel(args);
            } catch { }
            Console.WriteLine("{\"schema\":\"p6_r7_job_limit_probe_v4\",\"mode\":\"rejected\",\"passed\":false,\"code\":\"probe_rejected\"}"); return 2;
        }
    }
}
