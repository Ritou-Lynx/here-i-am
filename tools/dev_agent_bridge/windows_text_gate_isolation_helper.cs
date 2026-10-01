// R7 candidate. Default commands are read-only. Explicit apply/recovery mutate owned OS state.
// Trust boundary: trusted host and pinned CLI; not protection against a compromised user/kernel.
// Compile x64 with the installed .NET Framework csc; no SDK, NuGet package or driver required.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using Microsoft.Win32.SafeHandles;

namespace HereIAm.R7 {
    public sealed class BoundaryError : Exception {
        public readonly string Code;
        public readonly uint? Win32Error;
        public BoundaryError(string code) : base(code) { Code = code; }
        public BoundaryError(string code,uint error) : base(code) { Code=code; Win32Error=error; }
    }

    public static class Guard {
        public static void Require(bool value, string code) { if (!value) throw new BoundaryError(code); }
        public static void Win(bool value, string code) { Require(value, code); }
        public static void Win32(bool value,uint error,string code) { if(!value) throw new BoundaryError(code,error); }
        public static void Status(uint value, string code) { Require(value == 0, code); }
        public static void HResult(int value, string code) { Require(value >= 0, code); }
        public static int Port(string value) {
            int port;
            Require(value != null && value.Length <= 5 && Int32.TryParse(value, out port), "invalid_port");
            port = Int32.Parse(value);
            Require(port >= 1 && port <= 65535 && port.ToString() == value, "invalid_port");
            return port;
        }
        public static Guid Attempt(string value) { Guid id; Require(Guid.TryParseExact(value,"D",out id) && id!=Guid.Empty && id.ToString("D")==value,"invalid_attempt_id"); return id; }
        public static void CanonicalDirectory(string path) {
            string full = Path.GetFullPath(path);
            Guard.Require(!full.StartsWith(@"\\", StringComparison.Ordinal), "unc_path_rejected");
            for (DirectoryInfo d = new DirectoryInfo(full); d != null; d = d.Parent)
                if (d.Exists) Guard.Require((d.Attributes & FileAttributes.ReparsePoint) == 0, "reparse_path_rejected");
        }
    }

    // These pure policy descriptions are also consumed by the native installer.
    public sealed class Rule {
        public Guid Key, Layer;
        public bool Permit;
        public byte Weight;
        public int Port;
        public string Tag;
    }
    public static class Policy {
        public static readonly Guid Connect4 = new Guid("c38d57d1-05a7-4c33-904f-7fbceee60e82");
        public static readonly Guid Connect6 = new Guid("4a72393b-319f-44bc-84c3-ba54dcb3b6b4");
        public static readonly Guid Package = new Guid("71bc78fa-f17c-4997-a602-6abb261f351c");
        public static readonly Guid Protocol = new Guid("3971ef2b-623e-4f9a-8cb1-6e79b806b9a7");
        public static readonly Guid RemoteAddress = new Guid("b235ae9a-1d64-49b8-a44c-5ff3d9095045");
        public static readonly Guid RemotePort = new Guid("c35a604d-d22b-4e1a-91b4-68f674ee674b");
        public static Guid Key(Guid attempt, string tag) {
            using (SHA256 h = SHA256.Create()) {
                byte[] hash = h.ComputeHash(Encoding.ASCII.GetBytes("HereIAm.P6R7/" + attempt.ToString("N") + "/" + tag));
                byte[] key = new byte[16]; Array.Copy(hash, key, 16); return new Guid(key);
            }
        }
        public static Rule[] Rules(Guid attempt, int port) {
            Guard.Require(attempt != Guid.Empty && port > 0 && port <= 65535, "invalid_policy");
            return new Rule[] {
                new Rule { Key=Key(attempt,"allow4"), Layer=Connect4, Permit=true, Weight=15, Port=port, Tag="allow_loopback_tcp" },
                new Rule { Key=Key(attempt,"deny4"), Layer=Connect4, Permit=false, Weight=0, Tag="deny_other_ipv4" },
                new Rule { Key=Key(attempt,"deny6"), Layer=Connect6, Permit=false, Weight=0, Tag="deny_all_ipv6" }
            };
        }
        public static bool Allows(bool samePackage, AddressFamily family, ProtocolType protocol, IPAddress address, int port, int brokerPort) {
            return samePackage && family == AddressFamily.InterNetwork && protocol == ProtocolType.Tcp &&
                IPAddress.Loopback.Equals(address) && port == brokerPort;
        }
        public static bool MayRemoveBoundary(bool childCreated, bool processExitObserved, bool jobQuerySucceeded, uint active) {
            return !childCreated || (processExitObserved && jobQuerySucceeded && active == 0);
        }
        public static bool CliStartupPassed(bool config,bool readers,bool zero,bool clean,bool eofExit,bool error) {
            return config && readers && zero && clean && eofExit && !error;
        }
        public static bool OwnedImage(string schema,string image,string hash,string runningHelperHash) {
            if(schema=="p6_r7_owned_cli_startup_v1") return image=="codex.exe" && hash==CliStartupContract.Pin;
            if(schema!="p6_r7_owned_resources_v2" || image!="synthetic-worker.exe") return false;
            return hash==runningHelperHash || hash=="0aa780f653b98d7993d9a317ec688131b9002db6808a07097837d0f315a2b992" ||
                hash=="4986dc62dadf78cb6d9091069234c8fcb776219fed4a1d7356874952de380a85" ||
                hash=="7009c3a65df9a5302a59db686f359d1b9e11f9c4c09a8d702a47e10a2f09c9f7";
        }
    }

    // Native layouts are explicitly checked by --self-test before any apply operation.
    public static class Native {
        [StructLayout(LayoutKind.Sequential)] public struct Display { public IntPtr Name, Description; }
        [StructLayout(LayoutKind.Sequential)] public struct Blob { public uint Size; public IntPtr Data; }
        [StructLayout(LayoutKind.Explicit, Size=16)] public struct Value {
            [FieldOffset(0)] public uint Type;
            [FieldOffset(8)] public ulong Number;
            [FieldOffset(8)] public IntPtr Pointer;
        }
        [StructLayout(LayoutKind.Sequential)] public struct Condition { public Guid Field; public uint Match; public Value Value; }
        [StructLayout(LayoutKind.Sequential)] public struct Action { public uint Type; public Guid Key; }
        [StructLayout(LayoutKind.Sequential)] public struct Filter {
            public Guid Key; public Display Display; public uint Flags; public IntPtr Provider;
            public Blob ProviderData; public Guid Layer, Sublayer; public Value Weight;
            public uint Count; public IntPtr Conditions; public Action Action; public ulong Context;
            public IntPtr Reserved; public ulong Id; public Value EffectiveWeight;
        }
        [StructLayout(LayoutKind.Sequential)] public struct Sublayer {
            public Guid Key; public Display Display; public uint Flags; public IntPtr Provider; public Blob Data; public ushort Weight;
        }
        [StructLayout(LayoutKind.Sequential)] public struct SidAttributes { public IntPtr Sid; public uint Attributes; }
        [StructLayout(LayoutKind.Sequential)] public struct Capabilities { public IntPtr Sid, Caps; public uint Count, Reserved; }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct Startup {
            public uint Size; public IntPtr Reserved, Desktop, Title; public uint X,Y,XSize,YSize,XChars,YChars,Fill,Flags;
            public ushort Show, ReservedSize; public IntPtr ReservedBytes, Input, Output, Error;
        }
        [StructLayout(LayoutKind.Sequential)] public struct StartupEx { public Startup Info; public IntPtr Attributes; }
        [StructLayout(LayoutKind.Sequential)] public struct ProcessInfo { public IntPtr Process, Thread; public uint Pid, Tid; }
        [StructLayout(LayoutKind.Sequential)] public struct BasicLimit {
            public long ProcessTime, JobTime; public uint Flags; public UIntPtr MinWorking, MaxWorking; public uint ActiveLimit;
            public UIntPtr Affinity; public uint Priority, Scheduling;
        }
        [StructLayout(LayoutKind.Sequential)] public struct IoCounters { public ulong R1,R2,R3,R4,R5,R6; }
        [StructLayout(LayoutKind.Sequential)] public struct ExtendedLimit {
            public BasicLimit Basic; public IoCounters Io; public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
        }
        [StructLayout(LayoutKind.Sequential)] public struct JobAccounting {
            public long User, Kernel, PeriodUser, PeriodKernel; public uint Faults, Total, Active, Terminated;
        }
        [StructLayout(LayoutKind.Sequential)] public struct TcpRow { public uint State, LocalAddress, LocalPort, RemoteAddress, RemotePort, Pid; }
        [StructLayout(LayoutKind.Sequential)] public struct TcpTable { public uint Count; public TcpRow First; }
        [StructLayout(LayoutKind.Sequential)] public struct FileTime { public uint Low, High; public ulong Ticks { get { return ((ulong)High << 32) | Low; } } }
        [StructLayout(LayoutKind.Sequential)] public struct SecurityAttributes { public int Size; public IntPtr Descriptor; public int Inherit; }
        [DllImport("kernel32.dll",SetLastError=true)] public static extern bool CreatePipe(out IntPtr read,out IntPtr write,ref SecurityAttributes attributes,uint size);
        [DllImport("kernel32.dll",SetLastError=true)] public static extern bool SetHandleInformation(IntPtr handle,uint mask,uint flags);
        [DllImport("userenv.dll", CharSet=CharSet.Unicode)] public static extern int CreateAppContainerProfile(string name,string display,string description,IntPtr caps,uint count,out IntPtr sid);
        [DllImport("userenv.dll", CharSet=CharSet.Unicode)] public static extern int DeleteAppContainerProfile(string name);
        [DllImport("userenv.dll", CharSet=CharSet.Unicode)] public static extern int GetAppContainerFolderPath(string sid,out IntPtr path);
        [DllImport("userenv.dll", CharSet=CharSet.Unicode)] public static extern int DeriveAppContainerSidFromAppContainerName(string name,out IntPtr sid);
        [DllImport("advapi32.dll")] public static extern IntPtr FreeSid(IntPtr sid);
        [DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
        [DllImport("advapi32.dll", SetLastError=true)] public static extern bool GetTokenInformation(IntPtr token,int cls,IntPtr value,uint size,out uint needed);
        [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
        [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(uint access,bool inherit,uint pid);
        [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr CreateFileW(string path,uint access,uint share,IntPtr security,uint disposition,uint flags,IntPtr template);
        [DllImport("kernel32.dll", SetLastError=true)] public static extern bool WriteFile(IntPtr file,byte[] bytes,uint length,out uint written,IntPtr overlapped);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool DeleteFileW(string path);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern uint GetFinalPathNameByHandleW(IntPtr file,StringBuilder path,uint length,uint flags);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr CreateJobObjectW(IntPtr attributes,string name);
        [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetInformationJobObject(IntPtr job,int cls,ref ExtendedLimit value,uint size);
        [DllImport("kernel32.dll", SetLastError=true)] public static extern bool QueryInformationJobObject(IntPtr job,int cls,out JobAccounting value,uint size,IntPtr length);
        [DllImport("kernel32.dll", SetLastError=true)] public static extern bool IsProcessInJob(IntPtr process,IntPtr job,out bool member);
        [DllImport("kernel32.dll", SetLastError=true)] public static extern bool TerminateJobObject(IntPtr job,uint exitCode);
        [DllImport("kernel32.dll", SetLastError=true)] public static extern bool TerminateProcess(IntPtr process,uint exitCode);
        [DllImport("kernel32.dll", SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
        [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr process,out uint code);
        [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetProcessTimes(IntPtr process,out FileTime create,out FileTime exit,out FileTime kernel,out FileTime user);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool QueryFullProcessImageNameW(IntPtr process,uint flags,StringBuilder path,ref uint size);
        [DllImport("kernel32.dll", SetLastError=true)] public static extern bool InitializeProcThreadAttributeList(IntPtr list,int count,uint flags,ref IntPtr size);
        [DllImport("kernel32.dll", SetLastError=true)] public static extern bool UpdateProcThreadAttribute(IntPtr list,uint flags,IntPtr attribute,IntPtr value,IntPtr size,IntPtr previous,IntPtr returned);
        [DllImport("kernel32.dll")] public static extern void DeleteProcThreadAttributeList(IntPtr list);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool CreateProcessW(string app,StringBuilder command,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr env,string cwd,ref StartupEx startup,out ProcessInfo info);
        [DllImport("kernel32.dll", SetLastError=true)] public static extern uint ResumeThread(IntPtr thread);
        [DllImport("fwpuclnt.dll", CharSet=CharSet.Unicode)] public static extern uint FwpmEngineOpen0(string server,uint auth,IntPtr identity,IntPtr session,out IntPtr engine);
        [DllImport("fwpuclnt.dll")] public static extern uint FwpmEngineClose0(IntPtr engine);
        [DllImport("fwpuclnt.dll")] public static extern uint FwpmTransactionBegin0(IntPtr engine,uint flags);
        [DllImport("fwpuclnt.dll")] public static extern uint FwpmTransactionCommit0(IntPtr engine);
        [DllImport("fwpuclnt.dll")] public static extern uint FwpmTransactionAbort0(IntPtr engine);
        [DllImport("fwpuclnt.dll")] public static extern uint FwpmSubLayerAdd0(IntPtr engine,ref Sublayer layer,IntPtr security);
        [DllImport("fwpuclnt.dll")] public static extern uint FwpmSubLayerDeleteByKey0(IntPtr engine,ref Guid key);
        [DllImport("fwpuclnt.dll")] public static extern uint FwpmFilterAdd0(IntPtr engine,ref Filter filter,IntPtr security,out ulong id);
        [DllImport("fwpuclnt.dll")] public static extern uint FwpmFilterDeleteByKey0(IntPtr engine,ref Guid key);
        [DllImport("fwpuclnt.dll")] public static extern uint FwpmFilterGetByKey0(IntPtr engine,ref Guid key,out IntPtr filter);
        [DllImport("fwpuclnt.dll")] public static extern uint FwpmSubLayerGetByKey0(IntPtr engine,ref Guid key,out IntPtr sublayer);
        [DllImport("fwpuclnt.dll")] public static extern void FwpmFreeMemory0(ref IntPtr pointer);
        [DllImport("firewallapi.dll")] public static extern uint NetworkIsolationGetAppContainerConfig(out uint count,out IntPtr sids);
        [DllImport("firewallapi.dll")] public static extern uint NetworkIsolationSetAppContainerConfig(uint count,IntPtr sids);
        [DllImport("kernel32.dll")] public static extern IntPtr GetProcessHeap();
        [DllImport("kernel32.dll")] public static extern bool HeapFree(IntPtr heap,uint flags,IntPtr pointer);
        [DllImport("iphlpapi.dll")] public static extern uint GetExtendedTcpTable(IntPtr table,ref uint size,bool order,uint family,int tableClass,uint reserved);
    }

    public sealed class Arena : IDisposable {
        readonly List<IntPtr> allocations = new List<IntPtr>();
        public IntPtr Bytes(byte[] bytes) { IntPtr p=Marshal.AllocHGlobal(bytes.Length); allocations.Add(p); Marshal.Copy(bytes,0,p,bytes.Length); return p; }
        public IntPtr Text(string text) { IntPtr p=Marshal.StringToHGlobalUni(text); allocations.Add(p); return p; }
        public IntPtr Struct<T>(T value) { IntPtr p=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(T))); allocations.Add(p); Marshal.StructureToPtr(value,p,false); return p; }
        public IntPtr Array<T>(T[] values) {
            int stride=Marshal.SizeOf(typeof(T)); IntPtr p=Marshal.AllocHGlobal(stride*values.Length); allocations.Add(p);
            for(int i=0;i<values.Length;i++) Marshal.StructureToPtr(values[i],IntPtr.Add(p,stride*i),false); return p;
        }
        public void Dispose() { foreach(IntPtr p in allocations) Marshal.FreeHGlobal(p); allocations.Clear(); }
    }

    public static class TokenProof {
        public static void NoCapabilities(IntPtr process) {
            IntPtr token; Guard.Win(Native.OpenProcessToken(process,8,out token),"token_open_failed");
            try {
                uint need; Native.GetTokenInformation(token,30,IntPtr.Zero,0,out need);
                Guard.Require(need>=4 && need<=65536,"token_capability_size_failed");
                using(Arena a=new Arena()) { IntPtr info=a.Bytes(new byte[need]); Guard.Win(Native.GetTokenInformation(token,30,info,need,out need),"token_capability_query_failed"); Guard.Require(Marshal.ReadInt32(info)==0,"unexpected_token_capability"); }
            } finally { Native.CloseHandle(token); }
        }
        public static string Hash(string executable) {
            using(FileStream stream=new FileStream(executable,FileMode.Open,FileAccess.Read,FileShare.Read))
            using(SHA256 hash=SHA256.Create()) return BitConverter.ToString(hash.ComputeHash(stream)).Replace("-","").ToLowerInvariant();
        }
        public static void Image(IntPtr process,string executable) {
            uint size=32768; StringBuilder path=new StringBuilder((int)size);
            Guard.Win(Native.QueryFullProcessImageNameW(process,0,path,ref size),"process_image_query_failed");
            Guard.Require(String.Equals(Path.GetFullPath(path.ToString()),Path.GetFullPath(executable),StringComparison.OrdinalIgnoreCase),"process_image_mismatch");
        }
        public static string AppContainerSid(IntPtr process) {
            IntPtr token; Guard.Win(Native.OpenProcessToken(process,8,out token),"token_open_failed");
            try {
                uint need; using(Arena a=new Arena()) {
                    IntPtr flag=a.Struct<int>(0);
                    Guard.Win(Native.GetTokenInformation(token,29,flag,4,out need),"token_query_failed");
                    Guard.Require(Marshal.ReadInt32(flag)==1,"not_appcontainer");
                    Native.GetTokenInformation(token,31,IntPtr.Zero,0,out need);
                    Guard.Require(need>=IntPtr.Size && need<=65536,"token_sid_size_failed");
                    IntPtr info=a.Bytes(new byte[need]);
                    Guard.Win(Native.GetTokenInformation(token,31,info,need,out need),"token_sid_failed");
                    return new SecurityIdentifier(Marshal.ReadIntPtr(info)).Value;
                }
            } finally { Native.CloseHandle(token); }
        }
        public static ulong Creation(IntPtr process) {
            Native.FileTime c,e,k,u; Guard.Win(Native.GetProcessTimes(process,out c,out e,out k,out u),"process_time_failed"); return c.Ticks;
        }
    }

    public sealed class NetworkBoundary : IDisposable {
        public readonly Guid Attempt, SublayerKey;
        public readonly string Sid;
        public readonly Rule[] Rules;
        IntPtr engine;
        bool installed, exemption;
        public bool LoopbackConflict;
        public bool RecoveryStateVerified;
        public int LoopbackWriteAttempts, LoopbackWritesSucceeded;
        public NetworkBoundary(Guid attempt,string sid,int port) { Attempt=attempt; Sid=sid; SublayerKey=Policy.Key(attempt,"sublayer"); Rules=Policy.Rules(attempt,port); }
        public bool Installed { get { return installed; } }
        public void OpenForRecovery() {
            Guard.Status(Native.FwpmEngineOpen0(null,10,IntPtr.Zero,IntPtr.Zero,out engine),"wfp_open_denied");
            bool any=false;
            foreach(Rule rule in Rules) {
                Guid key=rule.Key; IntPtr buffer; uint code=Native.FwpmFilterGetByKey0(engine,ref key,out buffer);
                if(code==0x80320003u) continue;
                Guard.Status(code,"recovery_filter_read_failed");
                try {
                    Native.Filter f=(Native.Filter)Marshal.PtrToStructure(buffer,typeof(Native.Filter));
                    Guard.Require(f.Key==rule.Key && f.Sublayer==SublayerKey && f.Layer==rule.Layer && f.Action.Type==(rule.Permit?0x1002u:0x1001u) && f.Flags==0 && f.Count==(rule.Permit?4u:1u),"recovery_filter_scope_mismatch");
                    HashSet<Guid> seen=new HashSet<Guid>(); int stride=Marshal.SizeOf(typeof(Native.Condition));
                    for(int i=0;i<f.Count;i++) {
                        Native.Condition c=(Native.Condition)Marshal.PtrToStructure(IntPtr.Add(f.Conditions,i*stride),typeof(Native.Condition));
                        Guard.Require(c.Match==0 && seen.Add(c.Field),"recovery_condition_mismatch");
                        bool valid=c.Field==Policy.Package && c.Value.Type==13 && c.Value.Pointer!=IntPtr.Zero && new SecurityIdentifier(c.Value.Pointer).Value==Sid;
                        if(rule.Permit) valid=valid || (c.Field==Policy.Protocol && c.Value.Type==1 && (byte)c.Value.Number==6) || (c.Field==Policy.RemoteAddress && c.Value.Type==3 && (uint)c.Value.Number==0x7f000001) || (c.Field==Policy.RemotePort && c.Value.Type==2 && (ushort)c.Value.Number==(ushort)rule.Port);
                        Guard.Require(valid,"recovery_condition_mismatch");
                    }
                    Guard.Require(seen.Contains(Policy.Package),"recovery_package_missing"); any=true;
                } finally { Native.FwpmFreeMemory0(ref buffer); }
            }
            Guid sub=SublayerKey; IntPtr subBuffer; uint subCode=Native.FwpmSubLayerGetByKey0(engine,ref sub,out subBuffer);
            if(subCode==0) {
                try { Native.Sublayer value=(Native.Sublayer)Marshal.PtrToStructure(subBuffer,typeof(Native.Sublayer)); Guard.Require(value.Key==SublayerKey && value.Flags==0 && value.Weight==0x7fff,"recovery_sublayer_scope_mismatch"); any=true; }
                finally { Native.FwpmFreeMemory0(ref subBuffer); }
            } else Guard.Require(subCode==0x80320007u && !any,"recovery_sublayer_read_failed");
            installed=any; exemption=true; RecoveryStateVerified=true;
        }
        public void Install() {
            // Non-dynamic session: a crashed helper must not automatically erase deny rules.
            Guard.Status(Native.FwpmEngineOpen0(null,10,IntPtr.Zero,IntPtr.Zero,out engine),"wfp_open_denied");
            Guard.Status(Native.FwpmTransactionBegin0(engine,0),"wfp_transaction_failed");
            bool committed=false;
            try { using(Arena a=new Arena()) {
                Native.Display display=new Native.Display { Name=a.Text("HereIAm R7 synthetic attempt"), Description=a.Text("Attempt-scoped AppContainer network boundary") };
                Native.Sublayer sub=new Native.Sublayer { Key=SublayerKey, Display=display, Weight=0x7fff };
                Guard.Status(Native.FwpmSubLayerAdd0(engine,ref sub,IntPtr.Zero),"wfp_sublayer_failed");
                byte[] sidBytes=new byte[new SecurityIdentifier(Sid).BinaryLength]; new SecurityIdentifier(Sid).GetBinaryForm(sidBytes,0); IntPtr sid=a.Bytes(sidBytes);
                foreach(Rule rule in Rules) {
                    List<Native.Condition> conditions=new List<Native.Condition>();
                    conditions.Add(new Native.Condition { Field=Policy.Package,Value=new Native.Value { Type=13,Pointer=sid } });
                    if(rule.Permit) {
                        conditions.Add(new Native.Condition { Field=Policy.Protocol,Value=new Native.Value { Type=1,Number=6 } });
                        conditions.Add(new Native.Condition { Field=Policy.RemoteAddress,Value=new Native.Value { Type=3,Number=0x7f000001 } });
                        conditions.Add(new Native.Condition { Field=Policy.RemotePort,Value=new Native.Value { Type=2,Number=(ulong)rule.Port } });
                    }
                    Native.Filter filter=new Native.Filter { Key=rule.Key,Display=display,Layer=rule.Layer,Sublayer=SublayerKey,
                        Weight=new Native.Value { Type=1,Number=rule.Weight },Count=(uint)conditions.Count,Conditions=a.Array(conditions.ToArray()),
                        Action=new Native.Action { Type=rule.Permit ? 0x1002u : 0x1001u } };
                    ulong id; Guard.Status(Native.FwpmFilterAdd0(engine,ref filter,IntPtr.Zero,out id),"wfp_filter_failed");
                }
                Guard.Status(Native.FwpmTransactionCommit0(engine),"wfp_commit_failed"); committed=true; installed=true;
            } } finally { if(!committed) Native.FwpmTransactionAbort0(engine); }
        }
        sealed class SidEntry { public string Sid; public uint Attributes; }
        static string Snapshot(List<SidEntry> entries) {
            List<string> rows=new List<string>();
            foreach(SidEntry entry in entries) rows.Add(entry.Sid+":"+entry.Attributes.ToString());
            rows.Sort(StringComparer.Ordinal); return String.Join("\n",rows.ToArray());
        }
        static List<SidEntry> ReadExemptions() {
            uint count; IntPtr buffer; Guard.Status(Native.NetworkIsolationGetAppContainerConfig(out count,out buffer),"loopback_read_failed");
            try {
                Guard.Require(count<=65536,"loopback_list_limit"); List<SidEntry> list=new List<SidEntry>(); int stride=Marshal.SizeOf(typeof(Native.SidAttributes));
                for(int i=0;i<count;i++) { Native.SidAttributes x=(Native.SidAttributes)Marshal.PtrToStructure(IntPtr.Add(buffer,i*stride),typeof(Native.SidAttributes)); list.Add(new SidEntry { Sid=new SecurityIdentifier(x.Sid).Value,Attributes=x.Attributes }); }
                return list;
            } finally {
                if(buffer!=IntPtr.Zero) {
                    int stride=Marshal.SizeOf(typeof(Native.SidAttributes));
                    for(int i=0;i<count;i++) { Native.SidAttributes entry=(Native.SidAttributes)Marshal.PtrToStructure(IntPtr.Add(buffer,i*stride),typeof(Native.SidAttributes)); if(entry.Sid!=IntPtr.Zero) Native.HeapFree(Native.GetProcessHeap(),0,entry.Sid); }
                    Native.HeapFree(Native.GetProcessHeap(),0,buffer);
                }
            }
        }
        void ChangeExemption(bool add) {
            // Read/modify the current list, never restore an old whole-machine snapshot.
            // This mutex serializes our own helpers; external administrators must coordinate.
            using(Mutex mutex=new Mutex(false,@"Global\HereIAm.P6R7.LoopbackConfig")) {
                bool held=false;
                try {
                    try { held=mutex.WaitOne(5000); } catch(AbandonedMutexException) { held=true; }
                    Guard.Require(held,"loopback_lock_timeout");
                    List<SidEntry> list=ReadExemptions(); string before=Snapshot(list);
                    bool found=list.Exists(delegate(SidEntry x){ return x.Sid==Sid; });
                    if(add) { Guard.Require(!found,"loopback_sid_already_present"); list.Add(new SidEntry { Sid=Sid }); }
                    else { if(!found) return; list.RemoveAll(delegate(SidEntry x){ return x.Sid==Sid; }); }
                    string expected=Snapshot(list);
                    using(Arena a=new Arena()) {
                        List<Native.SidAttributes> native=new List<Native.SidAttributes>();
                        foreach(SidEntry entry in list) { SecurityIdentifier id=new SecurityIdentifier(entry.Sid); byte[] bytes=new byte[id.BinaryLength]; id.GetBinaryForm(bytes,0); native.Add(new Native.SidAttributes { Sid=a.Bytes(bytes),Attributes=entry.Attributes }); }
                        // Detection only, NOT compare-and-swap. A concurrent external write in the
                        // last-read/set window can still be lost. Apply requires an exclusive config window.
                        Guard.Require(Snapshot(ReadExemptions())==before,"loopback_concurrent_change");
                        LoopbackWriteAttempts++;
                        Guard.Status(Native.NetworkIsolationSetAppContainerConfig((uint)native.Count,native.Count==0?IntPtr.Zero:a.Array(native.ToArray())),"loopback_write_denied");
                        LoopbackWritesSucceeded++;
                    }
                    Guard.Require(Snapshot(ReadExemptions())==expected,"loopback_postwrite_mismatch");
                } catch(BoundaryError e) {
                    if(e.Code=="loopback_concurrent_change" || e.Code=="loopback_postwrite_mismatch") LoopbackConflict=true;
                    throw;
                } finally { if(held) mutex.ReleaseMutex(); }
            }
        }
        public void EnableLoopback() { Guard.Require(installed,"wfp_not_installed"); exemption=true; ChangeExemption(true); }
        public void RemoveAfterZero(bool zeroProven) {
            Guard.Require(zeroProven,"cleanup_requires_job_zero");
            Guard.Require(!LoopbackConflict,"loopback_conflict_manual_cleanup");
            // Remove the broad exemption first; keep every deny if this fails.
            if(exemption) { ChangeExemption(false); exemption=false; }
            if(installed) {
                Guard.Status(Native.FwpmTransactionBegin0(engine,0),"cleanup_transaction_failed"); bool committed=false;
                try {
                    foreach(Rule rule in Rules) { Guid key=rule.Key; uint code=Native.FwpmFilterDeleteByKey0(engine,ref key); Guard.Require(code==0 || code==0x80320003u,"cleanup_filter_failed"); }
                    Guid sub=SublayerKey; uint subCode=Native.FwpmSubLayerDeleteByKey0(engine,ref sub); Guard.Require(subCode==0 || subCode==0x80320007u,"cleanup_sublayer_failed");
                    Guard.Status(Native.FwpmTransactionCommit0(engine),"cleanup_commit_failed"); committed=true; installed=false;
                } finally { if(!committed) Native.FwpmTransactionAbort0(engine); }
            }
        }
        public void Dispose() { if(engine!=IntPtr.Zero) { Native.FwpmEngineClose0(engine); engine=IntPtr.Zero; } }
    }

    public static class MinimalEnvironment {
        // AppContainer creation requires LOCALAPPDATA and TEMP/TMP. All writable
        // locations use the already-authorized synthetic workspace, never the user environment.
        public static string Build(string system,string workspace) {
            foreach(string path in new string[]{system,workspace})
                Guard.Require(path!=null && path.Length<=4096 && path.IndexOf('\0')<0 &&
                    System.Text.RegularExpressions.Regex.IsMatch(path,@"\A[A-Za-z]:\\"),"invalid_environment_path");
            return "LOCALAPPDATA="+workspace+"\0PATH="+Path.Combine(system,"System32")+"\0SystemRoot="+system+
                "\0TEMP="+workspace+"\0TMP="+workspace+"\0WINDIR="+system+"\0\0";
        }
    }

    // A fixed vocabulary only. No provider keys, paths, config values or raw text escape.
    internal static class OwnedProfileLayout {
        internal static string ProfileRoot(string hostLocal,string name) {
            Guard.Require(name!=null && System.Text.RegularExpressions.Regex.IsMatch(name,@"\AHereIAm\.P6R7\.[0-9a-f]{32}\z"),"profile_name_rejected");
            Guard.Require(hostLocal!=null && System.Text.RegularExpressions.Regex.IsMatch(hostLocal,@"\A[A-Za-z]:\\") && Path.GetFullPath(hostLocal)==hostLocal && !hostLocal.EndsWith("\\"),"host_local_path_rejected");
            return Path.Combine(hostLocal,"Packages",name);
        }
        internal static bool Matches(string folder,string hostLocal,string name) {
            return folder!=null && String.Equals(folder,Path.Combine(ProfileRoot(hostLocal,name),"AC"),StringComparison.OrdinalIgnoreCase);
        }
        internal static string CreateEmptyCliDirectories(string sid,string name) {
            string hostLocal=Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string expected=Path.Combine(ProfileRoot(hostLocal,name),"AC");
            IntPtr memory=IntPtr.Zero; string folder;
            try {
                Guard.HResult(Native.GetAppContainerFolderPath(sid,out memory),"profile_folder_query_failed");
                Guard.Require(memory!=IntPtr.Zero,"profile_folder_query_empty"); folder=Marshal.PtrToStringUni(memory);
            } finally { if(memory!=IntPtr.Zero) Marshal.FreeCoTaskMem(memory); }
            Guard.Require(Matches(folder,hostLocal,name),"profile_folder_scope_rejected");
            Guard.CanonicalDirectory(expected); Guard.Require(Directory.Exists(expected),"profile_folder_missing");
            foreach(string child in new string[]{"empty-home","empty-workspace","Roaming"}) {
                string path=Path.Combine(folder,child); Guard.Require(!Directory.Exists(path) && !File.Exists(path),"profile_child_not_empty");
                Directory.CreateDirectory(path); Guard.CanonicalDirectory(path);
            }
            string temp=Path.Combine(folder,"Temp"); Guard.CanonicalDirectory(temp); Directory.CreateDirectory(temp); Guard.CanonicalDirectory(temp);
            return folder;
        }
        internal static void DeleteAndVerify(string name) {
            // Derive only from the owned attempt name, never from a journal-supplied path.
            string root=ProfileRoot(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),name);
            Guard.HResult(Native.DeleteAppContainerProfile(name),"profile_delete_failed");
            Guard.CanonicalDirectory(Path.GetDirectoryName(root));
            try { File.GetAttributes(root); }
            catch(FileNotFoundException) { return; }
            catch(DirectoryNotFoundException) { return; }
            throw new BoundaryError("profile_storage_remains");
        }
    }

    public static class StartupStderrDiagnostic {
        // Fixed literal hints only: a matching role is not a root-cause or permission verdict.
        static readonly string[][] TargetVocabulary=new string[][] {
            new string[]{"pipe","failed to create a pipe"},
            new string[]{"socketpair","failed to create a socketpair"},
            new string[]{"socket","failed to create a socket"},
            new string[]{"initial_log_file","failed to create initial log file"},
            new string[]{"log_directory","failed to create log directory"},
            new string[]{"plugin_data_directory","failed to create agent plugins data directory"},
            new string[]{"private_app_server_socket_directory","failed to create private app-server socket directory"},
            new string[]{"arg0_alias_warning","warning: proceeding, even though we could not create path aliases"},
            new string[]{"arg0_temp_root_refused","refusing to create helper binaries under temporary dir"}
        };
        public static Dictionary<string,object> Inspect(byte[] bytes) {
            Dictionary<string,object> result=new Dictionary<string,object>{{"diagnostic_only",true},{"status","unclassified"},{"categories",new string[0]},{"os_error_codes",new uint[0]},{"has_unknown_os_error",false}};
            Dictionary<string,object> roles=new Dictionary<string,object>();
            foreach(string[] role in TargetVocabulary) roles.Add(role[0],false);
            result["target_roles"]=roles;
            if(bytes==null || bytes.Length>262144) { result["status"]="input_limit"; return result; }
            if(bytes.Length==0) { result["status"]="empty"; return result; }
            string value;
            try { value=new UTF8Encoding(false,true).GetString(bytes).ToLowerInvariant(); }
            catch(DecoderFallbackException) { result["status"]="invalid_utf8"; return result; }
            foreach(string[] role in TargetVocabulary)
                roles[role[0]]=System.Text.RegularExpressions.Regex.IsMatch(value,System.Text.RegularExpressions.Regex.Escape(role[1])+@"(?![a-z0-9_])");
            List<string> categories=new List<string>();
            string[][] vocabulary=new string[][] {
                new string[]{"access_denied","access is denied","access denied","permission denied"},
                new string[]{"invalid_config","invalid config","error loading config","error parsing config","failed to load config","toml parse error","invalid type:","unknown variant","missing field"},
                new string[]{"config_related","config","toml"},
                new string[]{"parse_failure","error parsing","failed to parse","parse error"},
                new string[]{"invalid_arguments","unexpected argument","unrecognized option","unrecognized subcommand","usage:"},
                new string[]{"path_not_found","no such file or directory","system cannot find the path","system cannot find the file"},
                new string[]{"initialization_failed","failed to initialize","initialization failed"},
                new string[]{"create_failed","failed to create","could not create"},
                new string[]{"read_failed","failed to read","could not read"},
                new string[]{"open_failed","failed to open","could not open"},
                new string[]{"write_failed","failed to write","could not write"}
            };
            foreach(string[] category in vocabulary) for(int i=1;i<category.Length;i++) if(value.Contains(category[i])) { categories.Add(category[0]); break; }
            SortedSet<uint> known=new SortedSet<uint>(); bool unknown=false;
            foreach(System.Text.RegularExpressions.Match match in System.Text.RegularExpressions.Regex.Matches(value,@"\b(?:os error|win32 error)\s*:?\s*([0-9]{1,10})(?![0-9])")) {
                uint code;
                if(UInt32.TryParse(match.Groups[1].Value,out code) && Array.IndexOf(new uint[]{2,3,5,13,32,50,87,203,740,1314},code)>=0) known.Add(code); else unknown=true;
            }
            if(known.Contains(5) && !categories.Contains("access_denied")) categories.Add("access_denied");
            if((known.Contains(2) || known.Contains(3)) && !categories.Contains("path_not_found")) categories.Add("path_not_found");
            uint[] codes=new uint[known.Count]; known.CopyTo(codes);
            result["categories"]=categories.ToArray(); result["os_error_codes"]=codes; result["has_unknown_os_error"]=unknown;
            if(categories.Count>0 || known.Count>0) result["status"]="classified";
            return result;
        }
    }

    // Authorized only for the empty-home, no-auth native CLI startup fixture.
    internal static class SyntheticStartupStderrExcerpt {
        internal static Dictionary<string,object> Inspect(byte[] bytes,string attemptDirectory) {
            Dictionary<string,object> result=new Dictionary<string,object>{{"diagnostic_only",true},{"status","rejected"},{"text",""},{"truncated",false},{"sensitive_lines_removed",false}};
            if(attemptDirectory==null || !System.Text.RegularExpressions.Regex.IsMatch(attemptDirectory,@"\AD:\\memex\\tmp\\p6-r7-isolation\\[0-9a-f]{32}\z") || bytes==null || bytes.Length>262144) return result;
            string value;
            try { value=new UTF8Encoding(false,true).GetString(bytes); }
            catch(DecoderFallbackException) { result["status"]="invalid_utf8"; return result; }
            value=System.Text.RegularExpressions.Regex.Replace(value,@"\x1b\[[0-?]*[ -/]*[@-~]","");
            value=value.Replace("\r\n","\n").Replace('\r','\n'); StringBuilder clean=new StringBuilder();
            foreach(char ch in value) if(ch=='\n' || (!Char.IsControl(ch) && Char.GetUnicodeCategory(ch)!=System.Globalization.UnicodeCategory.Format)) clean.Append(ch);
            StringBuilder safe=new StringBuilder(); bool keptLine=false;
            foreach(string line in clean.ToString().Split('\n')) {
                // Drop the whole line before truncation/redaction, never retain a suspected value.
                if(System.Text.RegularExpressions.Regex.IsMatch(line,@"(?i)\b(?:authorization|proxy-authorization|bearer|cookie|set-cookie|credential\w*|password|passwd|secret\w*|(?:api|access|refresh|id)[_-]?(?:key|token)|token\w*|chatgpt-account-id)\b|\b(?:key|headers?|x-[a-z0-9_-]+|[a-z0-9_]*(?:key|token|secret|password)[a-z0-9_]*)\b[""']?\s*[:=]|\bsk-[a-z0-9_-]+|\beyJ[a-z0-9_-]+\.[a-z0-9_-]+")) { result["sensitive_lines_removed"]=true; continue; }
                string redacted=line;
                foreach(string root in new string[]{attemptDirectory.Replace("\\","\\\\"),attemptDirectory,attemptDirectory.Replace('\\','/')})
                    redacted=System.Text.RegularExpressions.Regex.Replace(redacted,System.Text.RegularExpressions.Regex.Escape(root),"<ATTEMPT>",System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                redacted=System.Text.RegularExpressions.Regex.Replace(redacted,@"(?i)\b[a-z]:[\\/]+(?:users|documents and settings)[\\/]+[^\n""'<>|:]*","<WINDOWS_USER_PATH>");
                if(keptLine) safe.Append('\n'); safe.Append(redacted); keptLine=true;
            }
            char[] chars=safe.ToString().ToCharArray(); byte[] capped=new byte[4096]; int charsUsed,bytesUsed; bool complete;
            new UTF8Encoding(false,true).GetEncoder().Convert(chars,0,chars.Length,capped,0,capped.Length,true,out charsUsed,out bytesUsed,out complete);
            result["text"]=Encoding.UTF8.GetString(capped,0,bytesUsed); result["truncated"]=!complete; result["status"]=bytesUsed==0?"empty":"available";
            return result;
        }
    }

    // Exactly three inherited handles. Parent ends, Job and supervisor resources never inherit.
    public sealed class RedirectedStdio : IDisposable {
        IntPtr inputRead,inputWrite,outputRead,outputWrite,errorRead,errorWrite;
        FileStream input,output,error;
        Thread outputThread,errorThread;
        readonly object sync=new object(),writeSync=new object(); readonly Queue<string> lines=new Queue<string>();
        string failure; bool outputDone,errorDone;
        Dictionary<string,object> stderrDiagnostic,stderrExcerpt; readonly string syntheticAttemptDirectory;
        public long OutputBytes,ErrorBytes; public int Notifications,RejectedServerRequests;
        public IntPtr[] ChildHandles { get { return new IntPtr[]{inputRead,outputWrite,errorWrite}; } }
        public RedirectedStdio(string attemptDirectory) {
            syntheticAttemptDirectory=attemptDirectory;
            try {
                Native.SecurityAttributes sa=new Native.SecurityAttributes {Size=Marshal.SizeOf(typeof(Native.SecurityAttributes)),Inherit=1};
                Guard.Win(Native.CreatePipe(out inputRead,out inputWrite,ref sa,4096),"stdin_pipe_failed");
                Guard.Win(Native.CreatePipe(out outputRead,out outputWrite,ref sa,4096),"stdout_pipe_failed");
                Guard.Win(Native.CreatePipe(out errorRead,out errorWrite,ref sa,4096),"stderr_pipe_failed");
                foreach(IntPtr h in new IntPtr[]{inputWrite,outputRead,errorRead}) Guard.Win(Native.SetHandleInformation(h,1,0),"pipe_inheritance_failed");
                input=new FileStream(new SafeFileHandle(inputWrite,false),FileAccess.Write,4096,false);
                output=new FileStream(new SafeFileHandle(outputRead,false),FileAccess.Read,4096,false);
                error=new FileStream(new SafeFileHandle(errorRead,false),FileAccess.Read,4096,false);
            } catch { Dispose(); throw; }
        }
        static void Close(ref IntPtr h) { if(h!=IntPtr.Zero) Native.CloseHandle(h); h=IntPtr.Zero; }
        public void ChildCreated() {
            Close(ref inputRead); Close(ref outputWrite); Close(ref errorWrite);
            outputThread=new Thread(delegate(){Pump(output,true);}); outputThread.IsBackground=true; outputThread.Start();
            errorThread=new Thread(delegate(){Pump(error,false);}); errorThread.IsBackground=true; errorThread.Start();
        }
        void Pump(Stream stream,bool stdout) {
            List<byte> stderrBytes=stdout?null:new List<byte>();
            try {
                byte[] buffer=new byte[4096]; List<byte> line=new List<byte>(); int read;
                while((read=stream.Read(buffer,0,buffer.Length))>0) {
                    lock(sync) { if(stdout) OutputBytes+=read; else ErrorBytes+=read; Guard.Require(OutputBytes<=1048576 && ErrorBytes<=262144,"stdio_byte_limit"); }
                    if(!stdout) { for(int i=0;i<read;i++) stderrBytes.Add(buffer[i]); continue; }
                    for(int i=0;i<read;i++) {
                        if(buffer[i]==10) {
                            string value=new UTF8Encoding(false,true).GetString(line.ToArray()); line.Clear();
                            if(value.Trim().Length>0) {
                                JavaScriptSerializer parser=new JavaScriptSerializer {MaxJsonLength=131072,RecursionLimit=64};
                                Dictionary<string,object> envelope=parser.DeserializeObject(value) as Dictionary<string,object>;
                                Guard.Require(envelope!=null,"invalid_rpc_message");
                                if(envelope.ContainsKey("method") && envelope.ContainsKey("id")) {
                                    Interlocked.Increment(ref RejectedServerRequests); object requestId=envelope["id"];
                                    Guard.Require(requestId is int || requestId is long || requestId is string && ((string)requestId).Length<=128,"invalid_server_request_id");
                                    try { WriteLine(parser.Serialize(new Dictionary<string,object>{{"id",requestId},{"error",new Dictionary<string,object>{{"code",-32601},{"message","Startup probe rejects host requests."}}}})); } catch { }
                                    throw new BoundaryError("server_request_rejected");
                                }
                            }
                            lock(sync) { Guard.Require(lines.Count<256,"stdio_line_limit"); if(value.Trim().Length>0) lines.Enqueue(value); Monitor.PulseAll(sync); }
                        } else { Guard.Require(line.Count<131072,"stdio_line_limit"); line.Add(buffer[i]); }
                    }
                }
                Guard.Require(!stdout || line.Count==0,"stdout_truncated_line");
                if(!stdout) { byte[] bytes=stderrBytes.ToArray(); try { lock(sync) { stderrDiagnostic=StartupStderrDiagnostic.Inspect(bytes); stderrExcerpt=SyntheticStartupStderrExcerpt.Inspect(bytes,syntheticAttemptDirectory); } } finally { Array.Clear(bytes,0,bytes.Length); } }
            } catch(Exception e) { lock(sync) failure=e is BoundaryError?((BoundaryError)e).Code:"stdio_read_failed"; }
            finally { if(stderrBytes!=null) { for(int i=0;i<stderrBytes.Count;i++) stderrBytes[i]=0; stderrBytes.Clear(); } lock(sync) { if(stdout) outputDone=true; else errorDone=true; Monitor.PulseAll(sync); } }
        }
        public Dictionary<string,object> StderrDiagnostic { get { lock(sync) return stderrDiagnostic; } }
        public Dictionary<string,object> StderrExcerpt { get { lock(sync) return stderrExcerpt; } }
        public void WriteLine(string json) {
            byte[] bytes=Encoding.UTF8.GetBytes(json+"\n"); Guard.Require(bytes.Length<=4096,"stdin_message_limit");
            Check(); lock(writeSync) { Guard.Require(input!=null,"stdin_closed"); input.Write(bytes,0,bytes.Length); input.Flush(); }
        }
        public void EndInput() { lock(writeSync) { if(input!=null) { input.Dispose(); input=null; } Close(ref inputWrite); } }
        public void Check() { lock(sync) Guard.Require(failure==null,failure??"stdio_read_failed"); }
        public Dictionary<string,object> Reply(int id,int timeoutMs) {
            Stopwatch wait=Stopwatch.StartNew();
            while(wait.ElapsedMilliseconds<timeoutMs) {
                string line=null;
                lock(sync) { Check(); if(lines.Count>0) line=lines.Dequeue(); else { Guard.Require(!outputDone,"stdout_closed_before_reply"); Monitor.Wait(sync,50); } }
                if(line==null) continue;
                JavaScriptSerializer parser=new JavaScriptSerializer {MaxJsonLength=131072,RecursionLimit=64};
                Dictionary<string,object> message=parser.DeserializeObject(line) as Dictionary<string,object>; Guard.Require(message!=null,"invalid_rpc_message");
                if(message.ContainsKey("method")) {
                    if(message.ContainsKey("id")) {
                        RejectedServerRequests++; object requestId=message["id"];
                        Guard.Require(requestId is int || requestId is long || requestId is string && ((string)requestId).Length<=128,"invalid_server_request_id");
                        WriteLine(parser.Serialize(new Dictionary<string,object>{{"id",requestId},{"error",new Dictionary<string,object>{{"code",-32601},{"message","Startup probe rejects host requests."}}}}));
                        throw new BoundaryError("server_request_rejected");
                    }
                    Notifications++; Guard.Require(Notifications<=256,"notification_limit"); continue;
                }
                object responseId; Guard.Require(message.TryGetValue("id",out responseId) && responseId is int && (int)responseId==id,"unexpected_rpc_reply");
                Guard.Require(!message.ContainsKey("error") && message.ContainsKey("result"),"rpc_error");
                Dictionary<string,object> result=message["result"] as Dictionary<string,object>; Guard.Require(result!=null,"invalid_rpc_result"); return result;
            }
            throw new BoundaryError("rpc_timeout");
        }
        public bool ReadersEnded() {
            if(outputThread!=null) outputThread.Join(3000); if(errorThread!=null) errorThread.Join(3000);
            lock(sync) return outputDone && errorDone && failure==null;
        }
        public void Dispose() {
            EndInput(); if(output!=null) output.Dispose(); if(error!=null) error.Dispose();
            Close(ref inputRead); Close(ref outputWrite); Close(ref errorWrite); Close(ref outputRead); Close(ref errorRead);
        }
    }

    // Reusable lifecycle primitive; public apply modes remain fixed no-auth probes.
    public sealed class RestrictedProcess : IDisposable {
        public IntPtr Job, Handle, ThreadHandle;
        public uint Pid;
        public ulong Created;
        public bool Started, ExitObserved;
        public uint? ExitCodeBeforeTermination;
        public bool ExitCodeQueryFailed;
        public string Sid;
        public void CreateSuspended(string executable,string expectedHash,string arguments,string cwd,IntPtr sid,string expectedSid,RedirectedStdio stdio=null,string environment=null) {
            Guard.Require(!Started && Handle==IntPtr.Zero,"process_already_created"); Guard.CanonicalDirectory(cwd);
            Guard.CanonicalDirectory(Path.GetDirectoryName(executable));
            Guard.Require((File.GetAttributes(executable)&FileAttributes.ReparsePoint)==0,"reparse_executable_rejected");
            Guard.Require(expectedHash!=null && expectedHash.Length==64 && TokenProof.Hash(executable)==expectedHash,"executable_hash_mismatch");
            Job=Native.CreateJobObjectW(IntPtr.Zero,null); Guard.Win(Job!=IntPtr.Zero,"job_create_failed");
            Native.ExtendedLimit limit=new Native.ExtendedLimit(); limit.Basic.Flags=0x2000|0x8; limit.Basic.ActiveLimit=1;
            Guard.Win(Native.SetInformationJobObject(Job,9,ref limit,(uint)Marshal.SizeOf(typeof(Native.ExtendedLimit))),"job_limit_failed");
            int attributeCount=stdio==null?2:3;
            IntPtr size=IntPtr.Zero; Native.InitializeProcThreadAttributeList(IntPtr.Zero,attributeCount,0,ref size);
            Guard.Require(size.ToInt64()>0 && size.ToInt64()<65536,"attribute_size_failed"); IntPtr list=Marshal.AllocHGlobal(size); bool initialized=false;
            Arena a=new Arena();
            try {
                Guard.Win(Native.InitializeProcThreadAttributeList(list,attributeCount,0,ref size),"attribute_init_failed"); initialized=true;
                Native.Capabilities caps=new Native.Capabilities { Sid=sid,Count=0 };
                Guard.Win(Native.UpdateProcThreadAttribute(list,0,new IntPtr(0x20009),a.Struct(caps),new IntPtr(Marshal.SizeOf(typeof(Native.Capabilities))),IntPtr.Zero,IntPtr.Zero),"appcontainer_attribute_failed");
                // WinBase.h: ProcThreadAttributeJobList=13, INPUT=0x20000.
                // Atomic association avoids an uncontained suspended child if the helper crashes.
                Guard.Win(Native.UpdateProcThreadAttribute(list,0,new IntPtr(0x2000d),a.Struct(Job),new IntPtr(IntPtr.Size),IntPtr.Zero,IntPtr.Zero),"job_list_attribute_failed");
                Native.StartupEx startup=new Native.StartupEx(); startup.Info.Size=(uint)Marshal.SizeOf(typeof(Native.StartupEx)); startup.Attributes=list;
                if(stdio!=null) {
                    IntPtr[] handles=stdio.ChildHandles;
                    Guard.Win(Native.UpdateProcThreadAttribute(list,0,new IntPtr(0x20002),a.Array(handles),new IntPtr(3*IntPtr.Size),IntPtr.Zero,IntPtr.Zero),"stdio_handle_list_failed");
                    startup.Info.Flags=0x100; startup.Info.Input=handles[0]; startup.Info.Output=handles[1]; startup.Info.Error=handles[2];
                }
                string system=Environment.GetFolderPath(Environment.SpecialFolder.Windows);
                string env=environment??MinimalEnvironment.Build(system,cwd);
                Native.ProcessInfo process;
                bool created=Native.CreateProcessW(executable,new StringBuilder("\""+executable+"\" "+arguments),IntPtr.Zero,IntPtr.Zero,stdio!=null,
                    0x80000|0x400|0x4|0x08000000,a.Text(env),cwd,ref startup,out process);
                // Capture before another native call or cleanup can replace the cached error.
                uint createError=unchecked((uint)Marshal.GetLastWin32Error());
                Guard.Win32(created,createError,"appcontainer_spawn_failed");
                Handle=process.Process; ThreadHandle=process.Thread; Pid=process.Pid; Started=true;
                if(stdio!=null) stdio.ChildCreated();
                bool member; Guard.Win(Native.IsProcessInJob(Handle,Job,out member),"job_membership_query_failed"); Guard.Require(member,"job_membership_failed");
                Sid=TokenProof.AppContainerSid(Handle); Guard.Require(Sid==expectedSid,"appcontainer_sid_mismatch");
                TokenProof.NoCapabilities(Handle); TokenProof.Image(Handle,executable);
                Guard.Require(TokenProof.Hash(executable)==expectedHash,"executable_changed_after_spawn"); Created=TokenProof.Creation(Handle);
            } finally {
                // Attribute values must remain allocated until the attribute list is destroyed.
                if(initialized) Native.DeleteProcThreadAttributeList(list);
                a.Dispose(); Marshal.FreeHGlobal(list);
            }
        }
        public void Resume() { Guard.Require(Handle!=IntPtr.Zero && Created!=0,"process_not_verified"); Guard.Require(Native.ResumeThread(ThreadHandle)!=UInt32.MaxValue,"resume_failed"); }
        public bool Alive() { return Handle!=IntPtr.Zero && Native.WaitForSingleObject(Handle,0)==258 && TokenProof.Creation(Handle)==Created; }
        public bool StopAndProveZero() {
            if(!Started) return true;
            uint state=Native.WaitForSingleObject(Handle,0);
            if(state==0) { uint code; if(Native.GetExitCodeProcess(Handle,out code)) ExitCodeBeforeTermination=code; else ExitCodeQueryFailed=true; }
            if(state!=0) {
                // Terminate the owned singleton job, with a direct owned-handle fallback.
                if(Job!=IntPtr.Zero) Native.TerminateJobObject(Job,125);
                Native.TerminateProcess(Handle,125);
            }
            ExitObserved=Native.WaitForSingleObject(Handle,5000)==0;
            Native.JobAccounting info=new Native.JobAccounting(); bool query=Job!=IntPtr.Zero && Native.QueryInformationJobObject(Job,1,out info,(uint)Marshal.SizeOf(typeof(Native.JobAccounting)),IntPtr.Zero);
            return Policy.MayRemoveBoundary(true,ExitObserved,query,info.Active);
        }
        public void Dispose() {
            if(ThreadHandle!=IntPtr.Zero) Native.CloseHandle(ThreadHandle);
            if(Handle!=IntPtr.Zero) Native.CloseHandle(Handle);
            if(Job!=IntPtr.Zero) Native.CloseHandle(Job);
            ThreadHandle=Handle=Job=IntPtr.Zero;
        }
    }

    public static class PeerAdmission {
        public static readonly int HeaderSize=Marshal.OffsetOf(typeof(Native.TcpTable),"First").ToInt32();
        static ushort Port(uint n) { return (ushort)(((n&255)<<8)|((n>>8)&255)); }
        static uint Address(IPAddress address) { return BitConverter.ToUInt32(address.GetAddressBytes(),0); }
        public static bool Matches(Native.TcpRow row,IPEndPoint client,IPEndPoint broker,uint pid) {
            return row.State==5 && row.Pid==pid && row.LocalAddress==Address(client.Address) && Port(row.LocalPort)==client.Port &&
                row.RemoteAddress==Address(broker.Address) && Port(row.RemotePort)==broker.Port;
        }
        public static bool Accept(Socket socket,RestrictedProcess child) {
            // This operates on the accepted socket before reading any payload; no cached PID/port decision.
            try {
                if(!child.Alive() || socket.AddressFamily!=AddressFamily.InterNetwork) return false;
                IPEndPoint client=(IPEndPoint)socket.RemoteEndPoint, broker=(IPEndPoint)socket.LocalEndPoint;
                if(!IPAddress.Loopback.Equals(client.Address)||!IPAddress.Loopback.Equals(broker.Address)) return false;
                uint size=0; uint code=Native.GetExtendedTcpTable(IntPtr.Zero,ref size,false,2,5,0);
                if(code!=122 || size<HeaderSize || size>16*1024*1024) return false;
                for(int attempt=0;attempt<3;attempt++) {
                    IntPtr table=Marshal.AllocHGlobal((int)size);
                    try {
                        uint capacity=size; code=Native.GetExtendedTcpTable(table,ref size,false,2,5,0);
                        if(code==122) { if(size>16*1024*1024) return false; continue; }
                        if(code!=0) return false;
                        uint count=(uint)Marshal.ReadInt32(table); int stride=Marshal.SizeOf(typeof(Native.TcpRow));
                        if(capacity<HeaderSize || count>(capacity-HeaderSize)/stride) return false; int matches=0;
                        for(int i=0;i<count;i++) {
                            Native.TcpRow row=(Native.TcpRow)Marshal.PtrToStructure(IntPtr.Add(table,HeaderSize+i*stride),typeof(Native.TcpRow));
                            if(Matches(row,client,broker,child.Pid)) matches++;
                        }
                        bool closing=socket.Poll(0,SelectMode.SelectRead) && socket.Available==0;
                        return matches==1 && !closing && child.Alive() && TokenProof.AppContainerSid(child.Handle)==child.Sid && !socket.Poll(0,SelectMode.SelectError);
                    } finally { Marshal.FreeHGlobal(table); }
                }
            } catch { return false; }
            return false;
        }
    }

    public static class CliStartupContract {
        public const string Pin="3d6ca7085c932b62ef4ee4877e92f15b050fb94b2eb8e6c10a346a06248c6004";
        public const string Provider="p6_native_startup";
        static readonly string[] Disabled=("shell_tool shell_snapshot unified_exec apply_patch_freeform apps plugins remote_plugin multi_agent js_repl js_repl_tools_only browser_use computer_use image_generation imagegen hooks memories memory_tool scheduled_tasks workspace_dependencies skill_mcp_dependency_install skill_env_var_dependency_prompt enable_request_compression responses_websockets responses_websockets_v2 code_mode_only multi_agent_v2 default_mode_request_user_input goals sleep_tool skill_search tool_suggest request_permissions_tool browser_use_external browser_use_full_cdp_access view_image code_mode_host").Split(' ');
        public static string Arguments(int port) {
            Guard.Port(port.ToString());
            List<string> values=new List<string>(new string[]{"model=\"gpt-5.6-sol\"","model_provider=\""+Provider+"\"","approval_policy=\"never\"","sandbox_mode=\"read-only\"","web_search=\"disabled\"","project_doc_max_bytes=0","notify=[]","mcp_servers={}","hooks={}","tools.view_image=false","analytics.enabled=false","agents.enabled=false","cli_auth_credentials_store=\"file\"","history.persistence=\"none\"","features.code_mode.enabled=false","features.skip_host_skill_discovery=true","features.code_mode.excluded_tool_namespaces=[\"functions\",\"collaboration\",\"skills\",\"clock\",\"web\"]"});
            foreach(string name in Disabled) values.Add("features."+name+"=false");
            values.Add("model_providers."+Provider+"={name=\"No-auth native startup\",base_url=\"http://127.0.0.1:"+port+"/v1\",wire_api=\"responses\",requires_openai_auth=false,request_max_retries=0,stream_max_retries=0,supports_websockets=false}");
            StringBuilder result=new StringBuilder("app-server --listen stdio://");
            foreach(string value in values) result.Append(" -c \"").Append(value.Replace("\"","\\\"")).Append('"');
            return result.ToString();
        }
        public static string EnvironmentBlock(string system,string profileFolder) {
            string basis=MinimalEnvironment.Build(system,profileFolder); SortedDictionary<string,string> entries=new SortedDictionary<string,string>(StringComparer.OrdinalIgnoreCase);
            foreach(string entry in basis.Split(new char[]{'\0'},StringSplitOptions.RemoveEmptyEntries)) { int separator=entry.IndexOf('='); entries.Add(entry.Substring(0,separator),entry.Substring(separator+1)); }
            entries["TEMP"]=Path.Combine(profileFolder,"Temp"); entries["TMP"]=entries["TEMP"];
            entries.Add("APPDATA",Path.Combine(profileFolder,"Roaming")); entries.Add("CODEX_HOME",Path.Combine(profileFolder,"empty-home"));
            entries.Add("HOME",profileFolder); entries.Add("USERPROFILE",profileFolder);
            List<string> lines=new List<string>(); foreach(KeyValuePair<string,string> entry in entries) lines.Add(entry.Key+"="+entry.Value);
            return String.Join("\0",lines.ToArray())+"\0\0";
        }
        static Dictionary<string,object> Map(object value) { return value as Dictionary<string,object>; }
        static object Get(Dictionary<string,object> map,string key) { object value; return map!=null && map.TryGetValue(key,out value)?value:null; }
        static bool Empty(object value) { Dictionary<string,object> map=Map(value); return value==null || map!=null && map.Count==0; }
        public static bool ConfigMatches(Dictionary<string,object> result,int port) {
            Dictionary<string,object> config=Map(Get(result,"config"));
            Dictionary<string,object> providers=Map(Get(config,"model_providers")), provider=Map(Get(providers,Provider));
            if(!Object.Equals(Get(config,"model"),"gpt-5.6-sol") || !Object.Equals(Get(config,"model_provider"),Provider) ||
                !Object.Equals(Get(config,"approval_policy"),"never") || !Object.Equals(Get(config,"sandbox_mode"),"read-only") ||
                !Object.Equals(Get(config,"web_search"),"disabled") || !Object.Equals(Get(config,"project_doc_max_bytes"),0) ||
                !Object.Equals(Get(Map(Get(config,"agents")),"enabled"),false) || !Empty(Get(config,"mcp_servers"))) return false;
            object[] notify=Get(config,"notify") as object[]; if(notify!=null && notify.Length!=0) return false;
            Dictionary<string,object> hooks=Map(Get(config,"hooks")); if(hooks!=null) foreach(object hook in hooks.Values) { object[] list=hook as object[]; if(list==null || list.Length!=0) return false; }
            if(!Object.Equals(Get(provider,"base_url"),"http://127.0.0.1:"+port+"/v1") || !Object.Equals(Get(provider,"wire_api"),"responses") ||
                !Object.Equals(Get(provider,"requires_openai_auth"),false) || !Object.Equals(Get(provider,"request_max_retries"),0) ||
                !Object.Equals(Get(provider,"stream_max_retries"),0) || !Object.Equals(Get(provider,"supports_websockets"),false) ||
                Get(provider,"env_key")!=null || Get(provider,"experimental_bearer_token")!=null || !Empty(Get(provider,"http_headers")) ||
                !Empty(Get(provider,"env_http_headers")) || !Empty(Get(provider,"query_params"))) return false;
            // Match the existing R6 conservative feature echo policy; missing echoes fail closed.
            Dictionary<string,object> features=Map(Get(config,"features")); foreach(string name in Disabled) if(!Object.Equals(Get(features,name),false)) return false;
            if(!Object.Equals(Get(features,"skip_host_skill_discovery"),true)) return false;
            object[] layers=Get(result,"layers") as object[]; if(layers==null) return false;
            foreach(object raw in layers) {
                Dictionary<string,object> layer=Map(raw); string type=Get(Map(Get(layer,"name")),"type") as string;
                if(type!="system" && type!="sessionFlags" && type!="user") return false;
                if(type!="sessionFlags" && !Empty(Get(layer,"config"))) return false;
            }
            return true;
        }
        public static int PureChecks() {
            int count=0; Dictionary<string,object> flags=new Dictionary<string,object>(); foreach(string key in Disabled) flags.Add(key,false); flags.Add("skip_host_skill_discovery",true);
            Dictionary<string,object> provider=new Dictionary<string,object>{{"base_url","http://127.0.0.1:32123/v1"},{"wire_api","responses"},{"requires_openai_auth",false},{"request_max_retries",0},{"stream_max_retries",0},{"supports_websockets",false}};
            Dictionary<string,object> config=new Dictionary<string,object>{{"model","gpt-5.6-sol"},{"model_provider",Provider},{"approval_policy","never"},{"sandbox_mode","read-only"},{"web_search","disabled"},{"project_doc_max_bytes",0},{"agents",new Dictionary<string,object>{{"enabled",false}}},{"features",flags},{"model_providers",new Dictionary<string,object>{{Provider,provider}}}};
            Dictionary<string,object> result=new Dictionary<string,object>{{"config",config},{"layers",new object[0]}};
            Guard.Require(ConfigMatches(result,32123),"startup_config_positive_failed"); count++;
            provider["requires_openai_auth"]=true; Guard.Require(!ConfigMatches(result,32123),"startup_auth_rejection_failed"); count++; provider["requires_openai_auth"]=false;
            provider["env_key"]="PRIVATE"; Guard.Require(!ConfigMatches(result,32123),"startup_env_rejection_failed"); count++; provider.Remove("env_key");
            provider["base_url"]="http://127.0.0.1:32124/v1"; Guard.Require(!ConfigMatches(result,32123),"startup_target_rejection_failed"); count++; provider["base_url"]="http://127.0.0.1:32123/v1";
            flags["shell_tool"]=true; Guard.Require(!ConfigMatches(result,32123),"startup_feature_rejection_failed"); count++;
            string environment=EnvironmentBlock(@"C:\Windows",@"D:\R7 Synthetic\AC");
            string[] entries=environment.Split(new char[]{'\0'}); Guard.Require(entries.Length==12 && entries[10]=="" && entries[11]=="" && entries[1]==@"CODEX_HOME=D:\R7 Synthetic\AC\empty-home" && entries[8]==@"USERPROFILE=D:\R7 Synthetic\AC" && entries[3]==@"LOCALAPPDATA=D:\R7 Synthetic\AC" && entries[6]==@"TEMP=D:\R7 Synthetic\AC\Temp" && entries[7]==@"TMP=D:\R7 Synthetic\AC\Temp" && entries[0]==@"APPDATA=D:\R7 Synthetic\AC\Roaming","startup_environment_failed"); count++;
            string arguments=Arguments(32123); Guard.Require(arguments.StartsWith("app-server --listen stdio://") && arguments.Contains("requires_openai_auth=false") && !arguments.Contains("requires_openai_auth=true") && arguments.Contains("agents.enabled=false"),"startup_arguments_failed"); count++;
            return count;
        }
    }

    public static class Program {
        const string Root=@"D:\memex\tmp\p6-r7-isolation";
        static string Json(object value) { return new JavaScriptSerializer().Serialize(value); }
        static Dictionary<string,object> Result(string mode) { return new Dictionary<string,object> {
            {"schema","p6_r7_windows_isolation_candidate_v1"},{"mode",mode},{"production_isolation_passed",false},{"human_gate_passed",false},{"real_upstream_requests",0} }; }
        static void Print(object value) { Console.Out.WriteLine(Json(value)); }
        static void ErrorFields(Dictionary<string,object> report,Exception error,string fallback) {
            BoundaryError boundary=error as BoundaryError;
            report["error_code"]=boundary==null?fallback:boundary.Code;
            if(boundary!=null && boundary.Win32Error.HasValue) report["win32_error"]=boundary.Win32Error.Value;
        }
        static void SecondaryFailure(Dictionary<string,object> report,string field,string code) {
            report[field]=code; if(!report.ContainsKey("error_code")) report["error_code"]=code;
        }
        public static int Main(string[] args) {
            try {
                if(args.Length==0 || (args.Length==1 && args[0]=="--plan")) { Print(Plan(49321)); return 0; }
                if(args.Length==2 && args[0]=="--validate-port") { Print(Plan(Guard.Port(args[1]))); return 0; }
                if(args.Length==2 && args[0]=="--recovery-plan") { Print(RecoveryPlan(Guard.Attempt(args[1]))); return 0; }
                if(args.Length==1 && args[0]=="--self-test") { Print(SelfTest()); return 0; }
                if(args.Length==1 && args[0]=="--apply-synthetic") return ApplySynthetic();
                if(args.Length==2 && args[0]=="--apply-cli-startup-synthetic") return ApplySynthetic(args[1]);
                if(args.Length==2 && args[0]=="--recover-synthetic") return RecoverSynthetic(Guard.Attempt(args[1]));
                if(args.Length==6 && args[0]=="--synthetic-worker") {
                    TokenProof.AppContainerSid(Native.GetCurrentProcess()); int[] ports=new int[5]; for(int i=0;i<5;i++) ports[i]=Guard.Port(args[i+1]); return Worker(ports);
                }
                if(args.Length==1 && args[0]=="--synthetic-leaf") { TokenProof.AppContainerSid(Native.GetCurrentProcess()); return 0; }
                throw new BoundaryError("invalid_arguments");
            } catch(Exception e) {
                Dictionary<string,object> r=Result("rejected"); r["error_code"]=e is BoundaryError?((BoundaryError)e).Code:"native_operation_failed"; r["system_mutation_requested"]=false; Print(r); return 2;
            }
        }
        static Dictionary<string,object> Plan(int port) {
            Dictionary<string,object> r=Result("plan"); r["system_mutation_requested"]=false; r["apply_requires_explicit_flag"]=true;
            r["requires_elevated_wfp_and_loopback_rights"]=true; r["network_capabilities"]=0; r["job_active_process_limit"]=1;
            r["job_association_at_process_creation"]=true;
            r["requires_exclusive_loopback_config_window"]=true; r["loopback_config_atomic_update"]=false;
            r["broker_ipv4_loopback_only"]=true; r["broker_port"]=port; r["wfp_filter_count"]=3; r["wfp_dynamic_session"]=false; r["wfp_persistent_filters"]=false;
            r["peer_admission"]="synchronous_established_full_tuple_pid_handle_creation_sid";
            r["cleanup_order"]=new string[]{"close_broker","terminate_owned_job","prove_process_exit_and_job_zero","remove_own_loopback_sid","remove_own_wfp_keys","delete_own_appcontainer_profile"};
            r["unverified"]=new string[]{"native_apply","new_cli_compatibility","nonloopback_network_behavior","native_crash_recovery","all_tools_preexecution","human_acceptance"}; return r;
        }
        static Dictionary<string,object> RecoveryPlan(Guid attempt) {
            Dictionary<string,object> r=Result("recovery_plan"); r["system_mutation_requested"]=false;
            r["attempt_id"]=attempt.ToString("D"); r["profile_name"]="HereIAm.P6R7."+attempt.ToString("N");
            r["sublayer"]=Policy.Key(attempt,"sublayer").ToString("D");
            r["filter_keys"]=new string[]{Policy.Key(attempt,"allow4").ToString("D"),Policy.Key(attempt,"deny4").ToString("D"),Policy.Key(attempt,"deny6").ToString("D")};
            r["missing_binding_is_not_job_zero"]=true; r["requires_exclusive_loopback_config_window"]=true; return r;
        }
        static void WriteJournal(string directory,Dictionary<string,object> journal) {
            Guard.CanonicalDirectory(directory);
            string next=Path.Combine(directory,"ownership.next.json"), target=Path.Combine(directory,"ownership.json");
            foreach(string p in new string[]{next,target}) if(File.Exists(p)) Guard.Require((File.GetAttributes(p)&FileAttributes.ReparsePoint)==0,"reparse_journal_rejected");
            byte[] bytes=Encoding.UTF8.GetBytes(Json(journal));
            using(FileStream stream=new FileStream(next,FileMode.Create,FileAccess.Write,FileShare.None,4096,FileOptions.WriteThrough)) { stream.Write(bytes,0,bytes.Length); stream.Flush(true); }
            if(File.Exists(target)) File.Replace(next,target,null); else File.Move(next,target);
        }
        static Dictionary<string,object> ReadJournal(string directory,Guid attempt) {
            Guard.CanonicalDirectory(directory); string file=Path.Combine(directory,"ownership.json");
            Guard.Require(File.Exists(file) && (File.GetAttributes(file)&FileAttributes.ReparsePoint)==0 && new FileInfo(file).Length<=16384,"recovery_journal_unavailable");
            JavaScriptSerializer serializer=new JavaScriptSerializer(); serializer.MaxJsonLength=16384; serializer.RecursionLimit=4;
            string raw=File.ReadAllText(file);
            Dictionary<string,object> data=serializer.DeserializeObject(raw) as Dictionary<string,object>;
            Guard.Require(data!=null,"recovery_journal_invalid");
            // Accept only our exact canonical serialization; duplicate/escaped keys and extra
            // whitespace are rejected instead of trusting a lossy dictionary parse.
            Guard.Require(Json(data)==raw,"recovery_journal_noncanonical");
            string[] keys=new string[]{"schema","attempt_id","profile_name","atomic_job","creation_started","worker_image","worker_sha256","broker_port","child_pid","child_creation","owner_pid","owner_creation"};
            Guard.Require(data.Count==keys.Length,"recovery_journal_invalid"); foreach(string key in keys) Guard.Require(data.ContainsKey(key),"recovery_journal_invalid");
            Guard.Require((data["attempt_id"] as string)==attempt.ToString("D") &&
                (data["profile_name"] as string)=="HereIAm.P6R7."+attempt.ToString("N") && data["atomic_job"] is bool && (bool)data["atomic_job"] &&
                data["creation_started"] is bool,"recovery_journal_invalid");
            string hash=data["worker_sha256"] as string;
            Guard.Require(hash!=null && hash.Length==64 && System.Text.RegularExpressions.Regex.IsMatch(hash,"\\A[0-9a-f]{64}\\z"),"recovery_journal_invalid");
            Guard.Require(Policy.OwnedImage(data["schema"] as string,data["worker_image"] as string,hash,TokenProof.Hash(Process.GetCurrentProcess().MainModule.FileName)),"recovery_image_scope_rejected");
            uint owner=JournalPid(data["owner_pid"]); ulong ownerTime=JournalTime(data["owner_creation"]);
            Guard.Require(owner>0 && ownerTime>0,"recovery_journal_invalid");
            Guard.Require(data["broker_port"] is int && (int)data["broker_port"]>=0 && (int)data["broker_port"]<=65535,"recovery_journal_invalid");
            Guard.Require((data["child_pid"]==null)==(data["child_creation"]==null),"recovery_journal_invalid");
            if(data["child_pid"]!=null) { JournalPid(data["child_pid"]); JournalTime(data["child_creation"]); Guard.Require((bool)data["creation_started"],"recovery_journal_invalid"); }
            return data;
        }
        static uint JournalPid(object value) {
            Guard.Require(value is int || value is long,"recovery_pid_invalid"); long pid=Convert.ToInt64(value);
            Guard.Require(pid>0 && pid<=UInt32.MaxValue,"recovery_pid_invalid"); return (uint)pid;
        }
        static ulong JournalTime(object value) {
            string text=value as string; ulong result;
            Guard.Require(text!=null && UInt64.TryParse(text,out result) && result>0,"recovery_time_invalid");
            result=UInt64.Parse(text); Guard.Require(result.ToString()==text,"recovery_time_invalid"); return result;
        }
        static bool SameLiveProcess(uint pid,ulong created) {
            IntPtr handle=Native.OpenProcess(0x1000|0x100000,false,pid);
            if(handle==IntPtr.Zero) { Guard.Require(Marshal.GetLastWin32Error()==87,"recovery_owner_query_failed"); return false; }
            try { return TokenProof.Creation(handle)==created && Native.WaitForSingleObject(handle,0)==258; }
            finally { Native.CloseHandle(handle); }
        }
        static string CloseRecoveredChild(Dictionary<string,object> journal,string directory,string sid) {
            if(!(bool)journal["creation_started"]) return "creation_not_started";
            Guard.Require(journal["child_pid"]!=null,"recovery_binding_missing");
            uint pid=JournalPid(journal["child_pid"]); ulong created=JournalTime(journal["child_creation"]);
            IntPtr handle=Native.OpenProcess(0x1000|0x100000|1,false,pid);
            if(handle==IntPtr.Zero) { Guard.Require(Marshal.GetLastWin32Error()==87,"recovery_child_query_failed"); return "bound_pid_absent"; }
            try {
                if(TokenProof.Creation(handle)!=created) return "bound_pid_reused"; // Never touch the replacement process.
                if(Native.WaitForSingleObject(handle,0)==0) return "bound_process_signaled";
                string executable=Path.Combine(directory,(string)journal["worker_image"]);
                TokenProof.Image(handle,executable); Guard.Require(TokenProof.AppContainerSid(handle)==sid,"recovery_child_sid_mismatch");
                Guard.Require(TokenProof.Hash(executable)==(string)journal["worker_sha256"],"recovery_image_hash_mismatch");
                Guard.Win(Native.TerminateProcess(handle,125),"recovery_terminate_failed");
                Guard.Require(Native.WaitForSingleObject(handle,5000)==0,"recovery_child_exit_unconfirmed"); return "bound_process_exit_observed";
            } finally { Native.CloseHandle(handle); }
        }
        static int RecoverSynthetic(Guid attempt) {
            SelfTest(); Guard.Require(new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator),"elevation_required");
            string directory=Path.Combine(Root,attempt.ToString("N")), name="HereIAm.P6R7."+attempt.ToString("N");
            Dictionary<string,object> report=Result("recover_synthetic"); report["attempt_id"]=attempt.ToString("D"); report["cleanup_pending"]=true; report["system_mutation_requested"]=true;
            IntPtr sid=IntPtr.Zero; NetworkBoundary network=null;
            try {
                Dictionary<string,object> journal=ReadJournal(directory,attempt);
                Guard.Require(!SameLiveProcess(JournalPid(journal["owner_pid"]),JournalTime(journal["owner_creation"])),"attempt_owner_active");
                // An observed loopback RMW conflict requires manual reconciliation, never old-snapshot restoration.
                foreach(string reportName in new string[]{"report.json","recovery-report.json"}) {
                    string oldReport=Path.Combine(directory,reportName);
                    if(!File.Exists(oldReport)) continue;
                    Guard.Require((File.GetAttributes(oldReport)&FileAttributes.ReparsePoint)==0 && new FileInfo(oldReport).Length<=16384,"recovery_report_invalid");
                    Dictionary<string,object> prior=new JavaScriptSerializer().DeserializeObject(File.ReadAllText(oldReport)) as Dictionary<string,object>;
                    Guard.Require(prior!=null,"recovery_report_invalid"); object conflict;
                    if(prior.TryGetValue("loopback_conflict_detected",out conflict)) Guard.Require(conflict is bool && !(bool)conflict,"loopback_conflict_manual_cleanup");
                }
                Guard.HResult(Native.DeriveAppContainerSidFromAppContainerName(name,out sid),"recovery_sid_failed"); string sidText=new SecurityIdentifier(sid).Value;
                int port=(int)journal["broker_port"]; network=new NetworkBoundary(attempt,sidText,port==0?49321:port); network.OpenForRecovery();
                string basis=CloseRecoveredChild(journal,directory,sidText); report["process_closure_basis"]=basis;
                // A successful atomic singleton Job creation plus the bound process closure proves no descendant remains.
                report["singleton_job_closure_proven"]=(bool)journal["creation_started"];
                report["cleanup_no_child_created"]=!(bool)journal["creation_started"];
                network.RemoveAfterZero(true); OwnedProfileLayout.DeleteAndVerify(name); report["profile_storage_absent_verified"]=true;
                report["cleanup_pending"]=false;
            } catch(Exception e) { report["error_code"]=e is BoundaryError?((BoundaryError)e).Code:"recovery_failed"; }
            finally {
                report["deny_rules_state"]=network==null || !network.RecoveryStateVerified?"unverified":network.Installed?"retained":"absent";
                report["loopback_conflict_detected"]=network!=null && network.LoopbackConflict;
                report["loopback_write_attempts"]=network==null?0:network.LoopbackWriteAttempts;
                report["loopback_writes_succeeded"]=network==null?0:network.LoopbackWritesSucceeded;
                if(network!=null) network.Dispose(); if(sid!=IntPtr.Zero) Native.FreeSid(sid);
                try {
                    Guard.CanonicalDirectory(directory); string path=Path.Combine(directory,"recovery-report.json");
                    if(File.Exists(path)) Guard.Require((File.GetAttributes(path)&FileAttributes.ReparsePoint)==0,"reparse_report_rejected");
                    if(Directory.Exists(directory)) File.WriteAllText(path,Json(report));
                } catch { report["report_file_written"]=false; }
                Print(report);
            }
            return (bool)report["cleanup_pending"]?3:0;
        }
        static Dictionary<string,object> SelfTest() {
            Guard.Require(IntPtr.Size==8,"x64_required");
            Guard.Require(Marshal.SizeOf(typeof(Native.Value))==16 && Marshal.SizeOf(typeof(Native.Condition))==40 && Marshal.SizeOf(typeof(Native.Filter))==192 && Marshal.SizeOf(typeof(Native.Sublayer))==72,"wfp_layout_mismatch");
            Guard.Require(Marshal.OffsetOf(typeof(Native.Filter),"Action").ToInt32()==128 && Marshal.OffsetOf(typeof(Native.Filter),"Context").ToInt32()==152,"wfp_offset_mismatch");
            Guard.Require(Marshal.SizeOf(typeof(Native.StartupEx))==112 && Marshal.SizeOf(typeof(Native.ExtendedLimit))==144 && Marshal.SizeOf(typeof(Native.TcpRow))==24,"process_layout_mismatch");
            Guard.Require(PeerAdmission.HeaderSize==4 && Marshal.SizeOf(typeof(Native.TcpTable))==28 && Marshal.OffsetOf(typeof(Native.TcpRow),"Pid").ToInt32()==20,"tcp_table_layout_mismatch");
            int n=0; Guid id=new Guid("00000000-0000-0000-0000-000000000001"); Rule[] rules=Policy.Rules(id,32123);
            Guard.Require(rules.Length==3 && rules[0].Key!=rules[1].Key && rules[1].Key!=rules[2].Key,"policy_keys_failed"); n++;
            Guard.Require(Policy.Allows(true,AddressFamily.InterNetwork,ProtocolType.Tcp,IPAddress.Loopback,32123,32123),"allow_rule_failed"); n++;
            foreach(bool same in new bool[]{true,false}) foreach(AddressFamily family in new AddressFamily[]{AddressFamily.InterNetwork,AddressFamily.InterNetworkV6})
                foreach(ProtocolType proto in new ProtocolType[]{ProtocolType.Tcp,ProtocolType.Udp}) foreach(int port in new int[]{32123,32124}) {
                    bool expected=same && family==AddressFamily.InterNetwork && proto==ProtocolType.Tcp && port==32123;
                    Guard.Require(Policy.Allows(same,family,proto,IPAddress.Loopback,port,32123)==expected,"deny_matrix_failed"); n++;
                }
            Guard.Require(!Policy.Allows(true,AddressFamily.InterNetwork,ProtocolType.Tcp,IPAddress.Parse("192.0.2.1"),32123,32123),"remote_rule_failed"); n++;
            Guard.Require(!Policy.MayRemoveBoundary(true,false,true,0) && !Policy.MayRemoveBoundary(true,true,false,0) && !Policy.MayRemoveBoundary(true,true,true,1) && Policy.MayRemoveBoundary(true,true,true,0),"cleanup_gate_failed"); n++;
            Native.TcpRow row=new Native.TcpRow {State=5,Pid=123,LocalAddress=0x0100007f,LocalPort=0x3075,RemoteAddress=0x0100007f,RemotePort=0x3076};
            IPEndPoint c=new IPEndPoint(IPAddress.Loopback,30000),b=new IPEndPoint(IPAddress.Loopback,30256);
            Guard.Require(PeerAdmission.Matches(row,c,b,123) && !PeerAdmission.Matches(row,c,b,124),"peer_tuple_failed"); n++;
            row.State=11; Guard.Require(!PeerAdmission.Matches(row,c,b,123),"peer_state_failed"); n++;
            row.State=5; row.LocalPort++; Guard.Require(!PeerAdmission.Matches(row,c,b,123),"peer_client_port_failed"); n++;
            row.LocalPort--; row.RemotePort++; Guard.Require(!PeerAdmission.Matches(row,c,b,123),"peer_broker_port_failed"); n++;
            row.RemotePort--; row.LocalAddress++; Guard.Require(!PeerAdmission.Matches(row,c,b,123),"peer_client_address_failed"); n++;
            row.LocalAddress--; row.RemoteAddress++; Guard.Require(!PeerAdmission.Matches(row,c,b,123),"peer_broker_address_failed"); n++;
            Guard.Win32(true,999,"appcontainer_spawn_failed"); n++;
            try { Guard.Win32(false,5,"appcontainer_spawn_failed"); throw new BoundaryError("native_error_test_failed"); }
            catch(BoundaryError error) {
                Dictionary<string,object> diagnostic=new Dictionary<string,object>(); ErrorFields(diagnostic,error,"unexpected_error");
                Guard.Require(Json(diagnostic)=="{\"error_code\":\"appcontainer_spawn_failed\",\"win32_error\":5}","native_error_test_failed"); n++;
            }
            Dictionary<string,object> redacted=new Dictionary<string,object>(); ErrorFields(redacted,new Exception("PRIVATE"),"native_operation_failed");
            Guard.Require(Json(redacted)=="{\"error_code\":\"native_operation_failed\"}","native_error_redaction_failed"); n++;
            string environment=MinimalEnvironment.Build(@"C:\Windows",@"D:\R7 Synthetic\work");
            string[] entries=environment.Split(new char[]{'\0'});
            Guard.Require(entries.Length==8 && entries[6]=="" && entries[7]=="","environment_terminator_failed"); n++;
            Guard.Require(String.Join("|",entries)==@"LOCALAPPDATA=D:\R7 Synthetic\work|PATH=C:\Windows\System32|SystemRoot=C:\Windows|TEMP=D:\R7 Synthetic\work|TMP=D:\R7 Synthetic\work|WINDIR=C:\Windows||","environment_allowlist_failed"); n++;
            foreach(string invalid in new string[]{"relative", "D:\\R7\0PRIVATE=value"}) {
                try { MinimalEnvironment.Build(@"C:\Windows",invalid); throw new BoundaryError("environment_rejection_failed"); }
                catch(BoundaryError error) { Guard.Require(error.Code=="invalid_environment_path","environment_rejection_failed"); n++; }
            }
            n+=CliStartupContract.PureChecks();
            Guard.Require(Marshal.SizeOf(typeof(Native.SecurityAttributes))==24 && Marshal.SizeOf(typeof(Native.Capabilities))==24,"stdio_layout_failed");
            Guard.Require(Policy.OwnedImage("p6_r7_owned_cli_startup_v1","codex.exe",CliStartupContract.Pin,"other"),"owned_cli_pin_failed"); n++;
            Guard.Require(!Policy.OwnedImage("p6_r7_owned_cli_startup_v1","codex.exe",new string('0',64),new string('0',64)) && !Policy.OwnedImage("p6_r7_owned_cli_startup_v1","../codex.exe",CliStartupContract.Pin,"other") && !Policy.OwnedImage("p6_r7_owned_resources_v2","codex.exe",CliStartupContract.Pin,CliStartupContract.Pin),"owned_image_scope_failed"); n++;
            Guard.Require(Policy.CliStartupPassed(true,true,true,true,true,false),"startup_pass_positive_failed"); n++;
            Guard.Require(!Policy.CliStartupPassed(true,true,true,true,false,false),"startup_forced_cleanup_is_not_pass"); n++;
            Dictionary<string,object> stderr=StartupStderrDiagnostic.Inspect(Encoding.UTF8.GetBytes(@"PRIVATE C:\Users\PRIVATE\config.toml failed to read: Access is denied (os error 5); win32 error 999999"));
            string summary=Json(stderr);
            Guard.Require(summary.Contains("access_denied") && summary.Contains("read_failed") && summary.Contains("config_related") && summary.Contains("[5]") && (bool)stderr["has_unknown_os_error"] && !summary.Contains("PRIVATE") && !summary.Contains("999999") && !summary.Contains("Users"),"stderr_redaction_failed"); n++;
            summary=Json(StartupStderrDiagnostic.Inspect(Encoding.UTF8.GetBytes("PRIVATE TOML parse error: invalid type: PRIVATE")));
            Guard.Require(summary.Contains("invalid_config") && summary.Contains("parse_failure") && !summary.Contains("PRIVATE"),"stderr_config_classification_failed"); n++;
            summary=Json(StartupStderrDiagnostic.Inspect(Encoding.UTF8.GetBytes("failed to create PRIVATE (os error 3)")));
            Guard.Require(summary.Contains("create_failed") && summary.Contains("path_not_found") && !summary.Contains("read_failed"),"stderr_operation_classification_failed"); n++;
            Guard.Require((string)StartupStderrDiagnostic.Inspect(new byte[0])["status"]=="empty","stderr_empty_failed"); n++;
            Guard.Require((string)StartupStderrDiagnostic.Inspect(new byte[]{0xff})["status"]=="invalid_utf8","stderr_utf8_failed"); n++;
            Guard.Require((string)StartupStderrDiagnostic.Inspect(new byte[262145])["status"]=="input_limit","stderr_limit_failed"); n++;
            stderr=StartupStderrDiagnostic.Inspect(Encoding.UTF8.GetBytes("PRIVATE user@example.invalid 123456789"));
            Guard.Require((string)stderr["status"]=="unclassified" && !Json(stderr).Contains("PRIVATE") && !Json(stderr).Contains("123456789"),"stderr_unknown_failed"); n++;
            string[][] roleFixtures=new string[][] {
                new string[]{"pipe","failed to create a pipe"},new string[]{"socketpair","failed to create a socketpair"},
                new string[]{"socket","failed to create a socket"},new string[]{"initial_log_file","failed to create initial log file"},
                new string[]{"log_directory","failed to create log directory"},new string[]{"plugin_data_directory","failed to create Agent Plugins data directory"},
                new string[]{"private_app_server_socket_directory","failed to create private app-server socket directory"},
                new string[]{"arg0_alias_warning","WARNING: proceeding, even though we could not create PATH aliases"},
                new string[]{"arg0_temp_root_refused","Refusing to create helper binaries under temporary dir"}
            };
            foreach(string[] fixture in roleFixtures) {
                stderr=StartupStderrDiagnostic.Inspect(Encoding.UTF8.GetBytes(fixture[1]+@": PRIVATE C:\Users\PRIVATE\secret (os error 5)"));
                Dictionary<string,object> roles=(Dictionary<string,object>)stderr["target_roles"];
                Guard.Require(roles.Count==9 && !Json(stderr).Contains("PRIVATE") && !Json(stderr).Contains("Users"),"stderr_role_redaction_failed");
                foreach(KeyValuePair<string,object> role in roles) Guard.Require(role.Value is bool && (bool)role.Value==(role.Key==fixture[0]),"stderr_role_isolation_failed"); n++;
            }
            foreach(byte[] fixture in new byte[][]{Encoding.UTF8.GetBytes("failed to create a socketPRIVATE; failed to create PRIVATE; os error 5"),new byte[]{0xff}}) {
                Dictionary<string,object> roles=(Dictionary<string,object>)StartupStderrDiagnostic.Inspect(fixture)["target_roles"];
                Guard.Require(roles.Count==9,"stderr_role_schema_failed");
                foreach(object role in roles.Values) Guard.Require(role is bool && !(bool)role,"stderr_role_guess_failed"); n++;
            }
            Dictionary<string,object> preserved=new Dictionary<string,object>{{"error_code","stdout_closed_before_reply"}};
            SecondaryFailure(preserved,"stdio_error_code","stdio_reader_failed");
            Guard.Require((string)preserved["error_code"]=="stdout_closed_before_reply" && (string)preserved["stdio_error_code"]=="stdio_reader_failed","primary_error_preservation_failed"); n++;
            Guard.Require(WorkerExitValid(256) && WorkerFilePassed(256) && !WorkerExitValid(0) && !WorkerExitValid(3) && !WorkerExitValid(1280),"worker_completion_marker_failed"); n++;
            foreach(uint failure in new uint[]{16,32,64,128,512}) { Guard.Require(WorkerExitValid(256|failure) && !WorkerFilePassed(256|failure),"worker_file_failure_failed"); n++; }
            string excerptRoot=Root+@"\00000000000000000000000000000001";
            Dictionary<string,object> excerpt=SyntheticStartupStderrExcerpt.Inspect(Encoding.UTF8.GetBytes("Error: canonicalize '"+excerptRoot+@"\work\empty-home' failed"+"\n"+@"at 'C:\Users\PRIVATE\build\source.rs'"),excerptRoot);
            summary=(string)excerpt["text"];
            Guard.Require(summary.Contains(@"<ATTEMPT>\work\empty-home") && summary.Contains("<WINDOWS_USER_PATH>") && !summary.Contains("PRIVATE") && !summary.Contains(excerptRoot),"excerpt_paths_failed"); n++;
            excerpt=SyntheticStartupStderrExcerpt.Inspect(Encoding.UTF8.GetBytes("Error: access denied\nAuthorization: "+"Bearer"+" PRIVATE\nclient_key=PRIVATE\nX-Debug: PRIVATE\n{\"api_key\":\"PRIVATE\"}\nCaused by: os error 5"),excerptRoot);
            Guard.Require((bool)excerpt["sensitive_lines_removed"] && !Json(excerpt).Contains("PRIVATE") && ((string)excerpt["text"]).Contains("Caused by: os error 5"),"excerpt_sensitive_lines_failed"); n++;
            excerpt=SyntheticStartupStderrExcerpt.Inspect(Encoding.UTF8.GetBytes("\x1b[31mError:\x1b[0m\0\t\u202e\r\n"+new string('\u4e2d',2000)),excerptRoot);
            summary=(string)excerpt["text"];
            Guard.Require((bool)excerpt["truncated"] && Encoding.UTF8.GetByteCount(summary)<=4096 && summary.StartsWith("Error:\n") && !summary.Contains("\ufffd") && !summary.Contains("\u202e"),"excerpt_bound_controls_failed"); n++;
            Guard.Require((string)SyntheticStartupStderrExcerpt.Inspect(new byte[]{0xff},excerptRoot)["status"]=="invalid_utf8","excerpt_utf8_failed"); n++;
            Guard.Require((string)SyntheticStartupStderrExcerpt.Inspect(new byte[262145],excerptRoot)["text"]=="","excerpt_input_bound_failed"); n++;
            Guard.Require((string)SyntheticStartupStderrExcerpt.Inspect(Encoding.UTF8.GetBytes("PRIVATE"),@"C:\Users\PRIVATE")["text"]=="","excerpt_scope_failed"); n++;
            Guard.Require((string)SyntheticStartupStderrExcerpt.Inspect(Encoding.UTF8.GetBytes("Error: Access is denied. (os error 5)"),excerptRoot)["text"]=="Error: Access is denied. (os error 5)","excerpt_plain_chain_failed"); n++;
            excerpt=SyntheticStartupStderrExcerpt.Inspect(Encoding.UTF8.GetBytes(excerptRoot.Replace("\\","\\\\")+"\n"+excerptRoot.Replace('\\','/')),excerptRoot);
            Guard.Require((string)excerpt["text"]=="<ATTEMPT>\n<ATTEMPT>","excerpt_path_variants_failed"); n++;
            string profileName="HereIAm.P6R7.00000000000000000000000000000001",hostLocal=@"D:\SyntheticHost\Local";
            string profileFolder=Path.Combine(hostLocal,"Packages",profileName,"AC");
            Guard.Require(OwnedProfileLayout.Matches(profileFolder,hostLocal,profileName),"profile_scope_positive_failed"); n++;
            foreach(string folder in new string[]{profileFolder+"2",profileFolder+@"\Temp",Path.GetDirectoryName(profileFolder),profileFolder.Replace("00000000000000000000000000000001","00000000000000000000000000000002"),@"C:\Users\PRIVATE\AC",profileFolder+@"\..\AC"}) {
                Guard.Require(!OwnedProfileLayout.Matches(folder,hostLocal,profileName),"profile_scope_negative_failed"); n++;
            }
            foreach(string name in new string[]{"PRIVATE",profileName+@"\..",profileName+"0"}) {
                try { OwnedProfileLayout.ProfileRoot(hostLocal,name); throw new Exception("profile_name_accepted"); }
                catch(BoundaryError e) { Guard.Require(e.Code=="profile_name_rejected","profile_name_error_failed"); n++; }
            }
            uint[] canonicalWords=new uint[]{0x50365237,1,1,1,0,2,5,1,0,1,0,1,0}; byte[] canonicalBytes=new byte[52];
            Buffer.BlockCopy(canonicalWords,0,canonicalBytes,0,52); Dictionary<string,object> canonical=DecodeCanonicalProbe(canonicalBytes);
            Guard.Require((string)canonical["status"]=="available" && (uint)((Dictionary<string,object>)canonical["normalized_dos"])["win32_error"]==5 && (string)((Dictionary<string,object>)canonical["normalized_nt"])["status"]=="ok","canonical_result_positive_failed"); n++;
            foreach(uint[] change in new uint[][]{new uint[]{0,0},new uint[]{1,2},new uint[]{2,2},new uint[]{3,3},new uint[]{7,4},new uint[]{8,5},new uint[]{3,0},new uint[]{5,0}}) {
                uint[] invalid=(uint[])canonicalWords.Clone(); invalid[change[0]]=change[1]; Buffer.BlockCopy(invalid,0,canonicalBytes,0,52);
                Guard.Require((string)DecodeCanonicalProbe(canonicalBytes)["status"]=="rejected","canonical_result_schema_failed"); n++;
            }
            foreach(byte[] invalid in new byte[][]{null,new byte[51],new byte[53]}) { Guard.Require((string)DecodeCanonicalProbe(invalid)["status"]=="rejected","canonical_result_bound_failed"); n++; }
            canonicalWords=new uint[13]; canonicalWords[0]=0x50365237; canonicalWords[1]=1; Buffer.BlockCopy(canonicalWords,0,canonicalBytes,0,52);
            Guard.Require((string)DecodeCanonicalProbe(canonicalBytes)["status"]=="incomplete","canonical_incomplete_is_unknown_failed"); n++;
            Dictionary<string,object> r=Result("self_test"); r["system_mutation_requested"]=false; r["assertions_passed"]=n; r["native_layouts_passed"]=true; r["environment_contract_passed"]=true; return r;
        }
        static void SetAttemptAcl(string directory,string sid,bool writable) {
            DirectorySecurity acl=new DirectorySecurity(); acl.SetAccessRuleProtection(true,false);
            InheritanceFlags inherit=InheritanceFlags.ContainerInherit|InheritanceFlags.ObjectInherit;
            foreach(SecurityIdentifier id in new SecurityIdentifier[]{WindowsIdentity.GetCurrent().User,new SecurityIdentifier(WellKnownSidType.LocalSystemSid,null),new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid,null)})
                acl.AddAccessRule(new FileSystemAccessRule(id,FileSystemRights.FullControl,inherit,PropagationFlags.None,AccessControlType.Allow));
            acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(sid),writable?FileSystemRights.Modify:FileSystemRights.ReadAndExecute,inherit,PropagationFlags.None,AccessControlType.Allow));
            Directory.SetAccessControl(directory,acl);
        }
        static TcpListener Listen(IPAddress ip) { TcpListener t=new TcpListener(ip,0); t.ExclusiveAddressUse=true; t.Start(); return t; }
        static void PositiveTcp(TcpListener listener,IPAddress ip) {
            Guard.Require(Connect(ip,((IPEndPoint)listener.LocalEndpoint).Port,false),"tcp_positive_control_failed");
            Guard.Require(listener.Pending(),"tcp_positive_accept_failed"); using(Socket accepted=listener.AcceptSocket()) { }
            Guard.Require(!listener.Pending(),"tcp_positive_drain_failed");
        }
        static void PositiveUdp(Socket receiver,IPAddress ip) {
            receiver.ReceiveTimeout=1500;
            using(Socket sender=new Socket(ip.AddressFamily,SocketType.Dgram,ProtocolType.Udp)) sender.SendTo(new byte[]{42},receiver.LocalEndPoint);
            byte[] bytes=new byte[8]; EndPoint source=new IPEndPoint(ip,0);
            Guard.Require(receiver.ReceiveFrom(bytes,ref source)==1 && bytes[0]==42 && receiver.Available==0,"udp_positive_control_failed");
        }
        static bool Connect(IPAddress ip,int port,bool marker) {
            using(Socket s=new Socket(ip.AddressFamily,SocketType.Stream,ProtocolType.Tcp)) {
                try {
                    IAsyncResult ar=s.BeginConnect(new IPEndPoint(ip,port),null,null);
                    using(ar.AsyncWaitHandle) if(!ar.AsyncWaitHandle.WaitOne(1500)) return false;
                    s.EndConnect(ar);
                    if(marker) { s.SendTimeout=1500; s.ReceiveTimeout=1500; s.Send(Encoding.ASCII.GetBytes("P6_R7_SOCKET_OK")); byte[] ack=new byte[1]; return s.Receive(ack)==1 && ack[0]==1; }
                    return true;
                } catch(SocketException) { return false; }
            }
        }
        static bool WorkerExitValid(uint code) { return (code&256)!=0 && (code&~1023U)==0; }
        static bool WorkerFilePassed(uint code) { return WorkerExitValid(code) && (code&752)==0; }
        static string WorkerProbeDirectory() {
            string attemptDirectory=Path.GetDirectoryName(Process.GetCurrentProcess().MainModule.FileName); Guid attempt;
            Guard.Require(String.Equals(Path.GetDirectoryName(attemptDirectory),Root,StringComparison.OrdinalIgnoreCase) && Guid.TryParseExact(Path.GetFileName(attemptDirectory),"N",out attempt),"probe_scope_failed");
            string work=Path.Combine(attemptDirectory,"work");
            Guard.Require(String.Equals(Directory.GetCurrentDirectory(),work,StringComparison.OrdinalIgnoreCase),"probe_cwd_failed");
            string directory=Path.Combine(work,"empty-write-probe"); Guard.CanonicalDirectory(directory);
            Guard.Require(Directory.Exists(directory),"probe_directory_missing"); return directory;
        }
        static int WorkerFileProbe() {
            int code=0; IntPtr file=new IntPtr(-1); bool created=false,closed=false; string target=null;
            try {
                string directory=WorkerProbeDirectory();
                target=Path.Combine(directory,"p6-r7-fixed-write.tmp");
                // CREATE_NEW never opens or overwrites an existing target; no caller-supplied path.
                file=Native.CreateFileW(target,0x40000000,0,IntPtr.Zero,1,0x80,IntPtr.Zero);
                if(file==new IntPtr(-1)) return 16;
                created=true; byte[] bytes=Encoding.ASCII.GetBytes("P6_R7_FILE_OK"); uint written;
                if(!Native.WriteFile(file,bytes,(uint)bytes.Length,out written,IntPtr.Zero) || written!=bytes.Length) code|=32;
            } catch { code|=512; }
            finally {
                if(created) {
                    closed=Native.CloseHandle(file); if(!closed) code|=64;
                    if(closed && !Native.DeleteFileW(target)) code|=128;
                }
            }
            return code;
        }
        static void CanonicalStep(uint[] words,int index,bool success,uint error) { words[index]=success?1U:2U; words[index+1]=success?0:error; }
        static Dictionary<string,object> CanonicalUnknown(string status) { return new Dictionary<string,object>{{"diagnostic_only",true},{"status",status}}; }
        static Dictionary<string,object> DecodeCanonicalProbe(byte[] bytes) {
            if(bytes==null || bytes.Length!=52) return CanonicalUnknown("rejected");
            uint[] words=new uint[13]; for(int i=0;i<words.Length;i++) words[i]=BitConverter.ToUInt32(bytes,i*4);
            if(words[0]!=0x50365237 || words[1]!=1 || words[2]>1) return CanonicalUnknown("rejected");
            for(int i=3;i<13;i+=2) if(words[i]>3 || (words[i]!=2 && words[i+1]!=0) || ((i==3 || i==11) && words[i]==3)) return CanonicalUnknown("rejected");
            if(words[3]!=1) { for(int i=5;i<13;i+=2) if(words[i]!=0) return CanonicalUnknown("rejected"); }
            if(words[2]==1 && (words[3]==0 || words[3]==1 && (words[5]==0 || words[7]==0 || words[9]==0 || words[11]==0))) return CanonicalUnknown("rejected");
            Dictionary<string,object> result=CanonicalUnknown(words[2]==1?"available":"incomplete");
            string[] names=new string[]{"directory_open","normalized_dos","normalized_nt","opened_dos","handle_close"};
            string[] states=new string[]{"not_attempted","ok","win32_error","buffer_limit"};
            for(int i=0;i<names.Length;i++) { int at=3+i*2; result[names[i]]=new Dictionary<string,object>{{"status",states[words[at]]},{"win32_error",words[at]==2?(object)words[at+1]:null}}; }
            return result;
        }
        static void WorkerCanonicalProbe() {
            uint[] words=new uint[13]; words[0]=0x50365237; words[1]=1; string directory=null; IntPtr handle=new IntPtr(-1);
            try {
                directory=WorkerProbeDirectory();
                handle=Native.CreateFileW(directory,0,7,IntPtr.Zero,3,0x02000000,IntPtr.Zero); uint error=unchecked((uint)Marshal.GetLastWin32Error());
                CanonicalStep(words,3,handle!=new IntPtr(-1),error);
                if(handle!=new IntPtr(-1)) {
                    uint[] flags=new uint[]{0,2,8};
                    for(int i=0;i<flags.Length;i++) {
                        StringBuilder buffer=new StringBuilder(32768);
                        uint length=Native.GetFinalPathNameByHandleW(handle,buffer,32768,flags[i]); error=unchecked((uint)Marshal.GetLastWin32Error());
                        int at=5+i*2; if(length>=32768) words[at]=3; else CanonicalStep(words,at,length!=0,error);
                        buffer.Clear(); // Returned paths are never serialized or printed.
                    }
                }
                words[2]=1;
            } catch { words[2]=0; }
            finally {
                if(handle!=new IntPtr(-1)) { bool closed=Native.CloseHandle(handle); uint error=unchecked((uint)Marshal.GetLastWin32Error()); CanonicalStep(words,11,closed,error); }
            }
            if(directory==null) return;
            try {
                // Fixed 52-byte little-endian schema, wx, containing no path/string payload.
                using(FileStream stream=new FileStream(Path.Combine(directory,"canonicalize-result.bin"),FileMode.CreateNew,FileAccess.Write,FileShare.None))
                using(BinaryWriter writer=new BinaryWriter(stream)) { foreach(uint word in words) writer.Write(word); writer.Flush(); stream.Flush(true); }
            } catch { } // Parent reports missing/unreadable/partial as unknown, never pass.
        }
        static Dictionary<string,object> ReadCanonicalProbe(string work) {
            try {
                string directory=Path.Combine(work,"empty-write-probe"); Guard.CanonicalDirectory(directory);
                string file=Path.Combine(directory,"canonicalize-result.bin");
                Guard.Require((File.GetAttributes(file)&FileAttributes.ReparsePoint)==0,"canonical_probe_reparse");
                using(FileStream stream=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.Read)) {
                    if(stream.Length!=52) return CanonicalUnknown("rejected");
                    byte[] bytes=new byte[52]; int total=0; while(total<52) { int count=stream.Read(bytes,total,52-total); if(count==0) return CanonicalUnknown("rejected"); total+=count; }
                    if(stream.ReadByte()!=-1) return CanonicalUnknown("rejected"); return DecodeCanonicalProbe(bytes);
                }
            } catch(FileNotFoundException) { return CanonicalUnknown("missing"); }
            catch(DirectoryNotFoundException) { return CanonicalUnknown("missing"); }
            catch { return CanonicalUnknown("unreadable"); }
        }
        static int Worker(int[] ports) {
            int code=256|WorkerFileProbe();
            WorkerCanonicalProbe();
            if(!Connect(IPAddress.Loopback,ports[0],true)) code|=1;
            if(Connect(IPAddress.Loopback,ports[1],false)) code|=2;
            if(Connect(IPAddress.IPv6Loopback,ports[2],false)) code|=4;
            foreach(int index in new int[]{3,4}) using(Socket s=new Socket(index==3?AddressFamily.InterNetwork:AddressFamily.InterNetworkV6,SocketType.Dgram,ProtocolType.Udp))
                try { s.SendTo(new byte[]{42},new IPEndPoint(index==3?IPAddress.Loopback:IPAddress.IPv6Loopback,ports[index])); } catch(SocketException) { }
            try {
                ProcessStartInfo psi=new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName,"--synthetic-leaf"); psi.UseShellExecute=false; psi.CreateNoWindow=true;
                using(Process p=Process.Start(psi)) { if(p!=null) { code|=8; if(!p.WaitForExit(1000)) p.Kill(); } }
            } catch(System.ComponentModel.Win32Exception) { }
            return code;
        }
        static int ApplySynthetic(string cliExecutable=null) {
            SelfTest(); Guard.Require(new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator),"elevation_required");
            bool cli=cliExecutable!=null;
            if(cli) {
                Guard.Require(Path.IsPathRooted(cliExecutable) && String.Equals(Path.GetFileName(cliExecutable),"codex.exe",StringComparison.OrdinalIgnoreCase),"cli_path_rejected");
                Guard.CanonicalDirectory(Path.GetDirectoryName(cliExecutable));
                Guard.Require((File.GetAttributes(cliExecutable)&FileAttributes.ReparsePoint)==0 && TokenProof.Hash(cliExecutable)==CliStartupContract.Pin,"cli_pin_mismatch");
            }
            Guid attempt=Guid.NewGuid(); string name="HereIAm.P6R7."+attempt.ToString("N"), directory=Path.Combine(Root,attempt.ToString("N"));
            Dictionary<string,object> report=Result(cli?"apply_cli_startup_synthetic":"apply_synthetic"); report["attempt_id"]=attempt.ToString("D"); report["profile_name"]=name;
            if(cli) { report["schema"]="p6_r7_cli_startup_candidate_v1"; report["cli_startup_passed"]=false; report["thread_start_tested"]=false; report["model_turns_requested"]=0; }
            else report["worker_canonicalize_probe"]=CanonicalUnknown("not_observed");
            report["system_mutation_requested"]=true; report["synthetic_passed"]=false; report["cleanup_pending"]=true;
            report["requires_exclusive_loopback_config_window"]=true; report["loopback_config_atomic_update"]=false;
            report["global_mutation_scope"]=new string[]{"one_random_appcontainer_profile","one_attempt_wfp_sublayer","three_attempt_package_sid_filters","loopback_exemption_list_rmw_for_own_sid","acl_on_new_synthetic_attempt_directories_only"};
            if(cli) report["cli_storage_scope"]="new_owned_profile_subdirectories_only";
            IntPtr sid=IntPtr.Zero; bool profile=false,zero=false; NetworkBoundary network=null; RestrictedProcess child=new RestrictedProcess();
            TcpListener broker=null,deny4=null,deny6=null; Socket udp4=null,udp6=null; string stage="prepare";
            Dictionary<string,object> journal=null;
            RedirectedStdio stdio=null; Thread rejectThread=null; int rejectStop=0,peerAttempts=0; string brokerFailure=null;
            try {
                Guard.CanonicalDirectory(Root); Guard.Require(!Directory.Exists(directory),"attempt_exists"); Directory.CreateDirectory(directory); Guard.CanonicalDirectory(directory);
                string sourceExecutable=cli?cliExecutable:Process.GetCurrentProcess().MainModule.FileName, expectedHash=cli?CliStartupContract.Pin:TokenProof.Hash(sourceExecutable);
                string workerImage=cli?"codex.exe":"synthetic-worker.exe";
                journal=new Dictionary<string,object> { {"schema",cli?"p6_r7_owned_cli_startup_v1":"p6_r7_owned_resources_v2"},{"attempt_id",attempt.ToString("D")},{"profile_name",name},
                    {"atomic_job",true},{"creation_started",false},{"worker_image",workerImage},{"worker_sha256",expectedHash},{"broker_port",0},
                    {"child_pid",null},{"child_creation",null},{"owner_pid",Process.GetCurrentProcess().Id},{"owner_creation",TokenProof.Creation(Native.GetCurrentProcess()).ToString()} };
                WriteJournal(directory,journal);
                stage="profile"; Guard.HResult(Native.CreateAppContainerProfile(name,name,"No-auth R7 synthetic isolation",IntPtr.Zero,0,out sid),"profile_create_failed"); profile=true; report["appcontainer_profile_created"]=true;
                string sidText=new SecurityIdentifier(sid).Value; report["appcontainer_sid"]=sidText; SetAttemptAcl(directory,sidText,false);
                string work=Path.Combine(directory,"work"); Directory.CreateDirectory(work); SetAttemptAcl(work,sidText,true);
                string executable=Path.Combine(directory,workerImage); File.Copy(sourceExecutable,executable,false);
                string cliProfileFolder=null,launchCwd=work;
                if(cli) { stage="profile_layout"; cliProfileFolder=OwnedProfileLayout.CreateEmptyCliDirectories(sidText,name); launchCwd=Path.Combine(cliProfileFolder,"empty-workspace"); report["profile_folder_scope_verified"]=true; }
                else Directory.CreateDirectory(Path.Combine(work,"empty-write-probe"));
                // All destinations below are loopback listeners owned by this test; no provider/auth code exists here.
                broker=Listen(IPAddress.Loopback); deny4=Listen(IPAddress.Loopback); deny6=Listen(IPAddress.IPv6Loopback);
                udp4=new Socket(AddressFamily.InterNetwork,SocketType.Dgram,ProtocolType.Udp); udp4.Bind(new IPEndPoint(IPAddress.Loopback,0));
                udp6=new Socket(AddressFamily.InterNetworkV6,SocketType.Dgram,ProtocolType.Udp); udp6.Bind(new IPEndPoint(IPAddress.IPv6Loopback,0));
                int[] ports=new int[]{((IPEndPoint)broker.LocalEndpoint).Port,((IPEndPoint)deny4.LocalEndpoint).Port,((IPEndPoint)deny6.LocalEndpoint).Port,((IPEndPoint)udp4.LocalEndPoint).Port,((IPEndPoint)udp6.LocalEndPoint).Port};
                stage="positive_controls"; PositiveTcp(deny4,IPAddress.Loopback); report["tcp4_positive_control_passed"]=true;
                PositiveTcp(deny6,IPAddress.IPv6Loopback); report["tcp6_positive_control_passed"]=true;
                PositiveUdp(udp4,IPAddress.Loopback); report["udp4_positive_control_passed"]=true;
                PositiveUdp(udp6,IPAddress.IPv6Loopback); report["udp6_positive_control_passed"]=true;
                journal["broker_port"]=ports[0]; WriteJournal(directory,journal);
                stage="wfp"; network=new NetworkBoundary(attempt,sidText,ports[0]); network.Install(); report["wfp_transaction_committed"]=true;
                stage="loopback"; network.EnableLoopback();
                stage="launch"; journal["creation_started"]=true; WriteJournal(directory,journal);
                if(cli) stdio=new RedirectedStdio(directory);
                string arguments=cli?CliStartupContract.Arguments(ports[0]):"--synthetic-worker "+String.Join(" ",Array.ConvertAll(ports,delegate(int p){return p.ToString();}));
                child.CreateSuspended(executable,expectedHash,arguments,launchCwd,sid,sidText,stdio,cli?CliStartupContract.EnvironmentBlock(Environment.GetFolderPath(Environment.SpecialFolder.Windows),cliProfileFolder):null);
                journal["child_pid"]=child.Pid; journal["child_creation"]=child.Created.ToString(); WriteJournal(directory,journal);
                report["token_appcontainer_verified"]=true; report["token_capabilities_empty"]=true; report["process_image_hash_verified"]=true; report["job_assigned"]=true;
                // Wrong local peer tested before reading its bytes; the owned child is still suspended.
                using(TcpClient outsider=new TcpClient()) { outsider.Connect(IPAddress.Loopback,ports[0]); using(Socket s=broker.AcceptSocket()) report["wrong_peer_rejected"]=!PeerAdmission.Accept(s,child); }
                if(cli) {
                    stage="cli_initialize";
                    rejectThread=new Thread(delegate(){
                        try { while(Interlocked.CompareExchange(ref rejectStop,0,0)==0) {
                            if(!broker.Pending()) { Thread.Sleep(10); continue; }
                            using(Socket socket=broker.AcceptSocket()) { if(PeerAdmission.Accept(socket,child)) { Interlocked.Increment(ref peerAttempts); socket.SendTimeout=1000; socket.Send(Encoding.ASCII.GetBytes("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")); } }
                        } } catch { if(Interlocked.CompareExchange(ref rejectStop,0,0)==0) brokerFailure="startup_broker_failed"; }
                    }); rejectThread.IsBackground=true; rejectThread.Start();
                    child.Resume();
                    stdio.WriteLine("{\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"p6_native_startup\",\"version\":\"1\"},\"capabilities\":{\"experimentalApi\":true}}}");
                    stdio.Reply(1,10000); report["initialize_replied"]=true;
                    stdio.WriteLine("{\"method\":\"initialized\",\"params\":{}}"); stage="cli_config_read";
                    stdio.WriteLine(Json(new Dictionary<string,object>{{"id",2},{"method","config/read"},{"params",new Dictionary<string,object>{{"cwd",launchCwd},{"includeLayers",true}}}}));
                    Dictionary<string,object> config=stdio.Reply(2,10000); report["config_read_replied"]=true;
                    Guard.Require(CliStartupContract.ConfigMatches(config,ports[0]),"startup_config_rejected"); report["config_checks_passed"]=true;
                    stdio.Check(); stdio.EndInput(); report["stdin_eof_sent"]=true;
                    report["stdin_eof_exit_observed"]=Native.WaitForSingleObject(child.Handle,5000)==0;
                } else {
                stage="synthetic_exchange"; child.Resume(); Stopwatch wait=Stopwatch.StartNew();
                while(!broker.Pending() && wait.ElapsedMilliseconds<8000 && child.Alive()) Thread.Sleep(10);
                Guard.Require(broker.Pending(),"allowed_loopback_unavailable");
                using(Socket s=broker.AcceptSocket()) {
                    Guard.Require(PeerAdmission.Accept(s,child),"owned_peer_rejected"); report["owned_peer_admitted"]=true;
                    s.ReceiveTimeout=1500; s.SendTimeout=1500; byte[] bytes=new byte[15]; int read=0;
                    while(read<bytes.Length) { int n=s.Receive(bytes,read,bytes.Length-read,SocketFlags.None); Guard.Require(n>0,"synthetic_truncated"); read+=n; }
                    Guard.Require(Encoding.ASCII.GetString(bytes)=="P6_R7_SOCKET_OK","synthetic_marker_mismatch"); s.Send(new byte[]{1});
                }
                Guard.Require(Native.WaitForSingleObject(child.Handle,12000)==0,"worker_timeout"); uint exit; Guard.Win(Native.GetExitCodeProcess(child.Handle,out exit),"worker_exit_unavailable");
                report["worker_canonicalize_probe"]=ReadCanonicalProbe(work);
                // Bounded observation for queued local UDP delivery; this is synthetic evidence only.
                Stopwatch udpWindow=Stopwatch.StartNew(); while(udpWindow.ElapsedMilliseconds<250 && udp4.Available==0 && udp6.Available==0) Thread.Sleep(10);
                bool workerCompleted=WorkerExitValid(exit); report["worker_completion_confirmed"]=workerCompleted;
                report["worker_file_probe_passed"]=WorkerFilePassed(exit);
                report["worker_file_probe_create_failed"]=workerCompleted && (exit&16)!=0; report["worker_file_probe_write_failed"]=workerCompleted && (exit&32)!=0;
                report["worker_file_probe_close_failed"]=workerCompleted && (exit&64)!=0; report["worker_file_probe_delete_failed"]=workerCompleted && (exit&128)!=0;
                report["worker_file_probe_scope_or_native_exception"]=workerCompleted && (exit&512)!=0;
                report["allowed_exchange_completed"]=workerCompleted && (exit&1)==0; report["forbidden_tcp4_rejected"]=workerCompleted && (exit&2)==0 && !deny4.Pending();
                report["forbidden_tcp6_rejected"]=workerCompleted && (exit&4)==0 && !deny6.Pending(); report["child_spawn_rejected"]=workerCompleted && (exit&8)==0;
                report["udp4_received_count"]=udp4.Available>0?1:0; report["udp6_received_count"]=udp6.Available>0?1:0;
                report["synthetic_passed"]=exit==256 && !deny4.Pending() && !deny6.Pending() && udp4.Available==0 && udp6.Available==0 && (bool)report["wrong_peer_rejected"];
                if(!(bool)report["synthetic_passed"]) report["error_code"]="synthetic_boundary_failed";
                }
                stage="finished";
            } catch(Exception e) { ErrorFields(report,e,"native_operation_failed"); }
            finally {
                report["stage"]=stage;
                Interlocked.Exchange(ref rejectStop,1); if(rejectThread!=null && !rejectThread.Join(2000)) brokerFailure="startup_broker_close_unconfirmed";
                if(broker!=null) broker.Stop(); if(deny4!=null) deny4.Stop(); if(deny6!=null) deny6.Stop(); if(udp4!=null) udp4.Dispose(); if(udp6!=null) udp6.Dispose();
                if(stdio!=null) try { stdio.EndInput(); } catch { SecondaryFailure(report,"stdin_error_code","stdin_close_failed"); }
                try { zero=child.StopAndProveZero(); } catch { zero=false; }
                report["owned_child_created"]=child.Started; report["cleanup_no_child_created"]=!child.Started;
                report["process_exit_observed"]=child.ExitObserved; report["job_zero_proven"]=child.Started && zero;
                if(cli) {
                    report["exit_code_before_termination_observed"]=child.ExitCodeBeforeTermination.HasValue;
                    if(child.ExitCodeBeforeTermination.HasValue) report["child_exit_code_before_termination"]=child.ExitCodeBeforeTermination.Value;
                    report["exit_code_query_failed"]=child.ExitCodeQueryFailed;
                }
                bool clean=false;
                if(zero) try {
                    if(network!=null) network.RemoveAfterZero(true);
                    if(profile) { OwnedProfileLayout.DeleteAndVerify(name); profile=false; report["profile_storage_absent_verified"]=true; }
                    clean=true;
                } catch(Exception e) { report["cleanup_error_code"]=e is BoundaryError?((BoundaryError)e).Code:"cleanup_failed"; }
                report["cleanup_pending"]=!clean; report["deny_rules_retained"]=network!=null && network.Installed;
                report["loopback_conflict_detected"]=network!=null && network.LoopbackConflict;
                report["loopback_write_attempts"]=network==null?0:network.LoopbackWriteAttempts;
                report["loopback_writes_succeeded"]=network==null?0:network.LoopbackWritesSucceeded;
                report["appcontainer_profile_remaining"]=profile;
                if(cli) {
                    bool readers=stdio!=null && stdio.ReadersEnded(); report["stdio_readers_eof_confirmed"]=readers;
                    report["stdout_byte_count"]=stdio==null?0:stdio.OutputBytes; report["stderr_byte_count"]=stdio==null?0:stdio.ErrorBytes;
                    if(stdio!=null && stdio.StderrDiagnostic!=null) report["stderr_diagnostic"]=stdio.StderrDiagnostic;
                    if(stdio!=null && stdio.StderrExcerpt!=null) report["synthetic_startup_stderr_excerpt"]=stdio.StderrExcerpt;
                    report["server_requests_rejected"]=stdio==null?0:stdio.RejectedServerRequests; report["local_http_attempt_count"]=peerAttempts;
                    if(!readers && stdio!=null && child.Started) SecondaryFailure(report,"stdio_error_code","stdio_reader_failed");
                    if(brokerFailure!=null) SecondaryFailure(report,"broker_error_code",brokerFailure);
                    if(peerAttempts!=0) SecondaryFailure(report,"http_error_code","startup_http_attempted");
                    bool eofExit=report.ContainsKey("stdin_eof_exit_observed") && (bool)report["stdin_eof_exit_observed"];
                    report["cli_startup_passed"]=Policy.CliStartupPassed(report.ContainsKey("config_checks_passed"),readers,zero,clean,eofExit,report.ContainsKey("error_code"));
                }
                // Do not synchronously dispose a stream still held by an unconfirmed reader.
                // This one-shot helper exits with background readers; the OS closes these
                // handles. Unknown process/Job closure still retains the network boundary.
                if(stdio!=null && (!child.Started || (bool)report["stdio_readers_eof_confirmed"])) stdio.Dispose();
                child.Dispose(); if(network!=null) network.Dispose(); if(sid!=IntPtr.Zero) Native.FreeSid(sid);
                try { if(Directory.Exists(directory)) File.WriteAllText(Path.Combine(directory,"report.json"),Json(report)); } catch { report["report_file_written"]=false; }
                Print(report);
            }
            return (bool)report[cli?"cli_startup_passed":"synthetic_passed"] && !(bool)report["cleanup_pending"]?0:3;
        }
    }
}
