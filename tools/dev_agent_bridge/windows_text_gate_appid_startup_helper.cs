// No-auth AppId startup candidate. Compile with the immutable v10 primitives and /main:HereIAm.R7.AppIdProgram.
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

namespace HereIAm.R7 {
    internal static class AppIdNative {
        [StructLayout(LayoutKind.Sequential)] internal struct Statistics {
            internal ulong TokenId,AuthenticationId; internal long Expiration;
            internal uint Type,Impersonation,Charged,Available,Groups,Privileges; internal ulong Modified;
        }
        [DllImport("advapi32.dll",SetLastError=true)] internal static extern bool DuplicateTokenEx(IntPtr existing,uint access,IntPtr attributes,int level,int type,out IntPtr token);
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] internal static extern bool CreateProcessAsUserW(IntPtr token,string app,StringBuilder command,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr env,string cwd,ref Native.StartupEx startup,out Native.ProcessInfo process);
        [DllImport("fwpuclnt.dll",CharSet=CharSet.Unicode)] internal static extern uint FwpmGetAppIdFromFileName0(string filename,out IntPtr appId);
        internal static void Win(bool ok,string code) { uint error=unchecked((uint)Marshal.GetLastWin32Error()); if(!ok) throw new BoundaryError(code,error); }
    }

    internal sealed class MediumIdentity {
        internal string User; internal uint Session,Integrity,ElevationType,Elevated,AppContainer,Type; internal ulong Authentication; internal uint? ImpersonationLevel;
        internal bool IsMedium { get { return Type==1 && Integrity==8192 && ElevationType==3 && Elevated==0 && AppContainer==0 && Authentication!=0; } }
        internal bool IsMediumSource { get { return (Type==1 || Type==2) && Integrity==8192 && ElevationType==3 && Elevated==0 && AppContainer==0 && Authentication!=0; } }
        internal static bool AcceptLinked(MediumIdentity full,MediumIdentity linked) { return full!=null&&linked!=null&&full.Type==1&&full.ElevationType==2&&full.Elevated==1&&full.AppContainer==0&&linked.IsMediumSource&&linked.User==full.User&&linked.Session==full.Session; }
        internal bool Same(MediumIdentity other) { return other!=null && User==other.User && Session==other.Session && Authentication==other.Authentication && Integrity==other.Integrity && ElevationType==other.ElevationType && Elevated==other.Elevated && AppContainer==other.AppContainer && Type==other.Type; }
        internal static bool PrimaryDuplicateMatches(MediumIdentity source,MediumIdentity duplicate) { return source!=null && duplicate!=null && source.IsMediumSource && duplicate.IsMedium && source.User==duplicate.User && source.Session==duplicate.Session && source.Authentication==duplicate.Authentication && source.Integrity==duplicate.Integrity && source.ElevationType==duplicate.ElevationType && source.Elevated==duplicate.Elevated && source.AppContainer==duplicate.AppContainer; }
        internal static T Query<T>(IntPtr token,int cls,Func<IntPtr,uint,T> read) {
            uint need; Native.GetTokenInformation(token,cls,IntPtr.Zero,0,out need);
            Guard.Require(need>=4 && need<=65536,"token_query_size_rejected");
            IntPtr buffer=Marshal.AllocHGlobal((int)need);
            try { uint capacity=need; AppIdNative.Win(Native.GetTokenInformation(token,cls,buffer,capacity,out need),"token_query_failed"); Guard.Require(need<=capacity,"token_query_changed"); return read(buffer,need); }
            finally { Marshal.FreeHGlobal(buffer); }
        }
        static uint Dword(IntPtr token,int cls) { return Query<uint>(token,cls,delegate(IntPtr p,uint n){Guard.Require(n==4,"token_dword_size");return unchecked((uint)Marshal.ReadInt32(p));}); }
        static string Sid(IntPtr token,int cls) { return Query<string>(token,cls,delegate(IntPtr p,uint n){Guard.Require(n>=IntPtr.Size,"token_sid_size");return new SecurityIdentifier(Marshal.ReadIntPtr(p)).Value;}); }
        internal static MediumIdentity Read(IntPtr token) {
            MediumIdentity value=new MediumIdentity(); value.User=Sid(token,1); value.Session=Dword(token,12); value.Type=Dword(token,8);
            value.ElevationType=Dword(token,18); value.Elevated=Dword(token,20); value.AppContainer=Dword(token,29);
            string[] integrity=Sid(token,25).Split('-'); value.Integrity=UInt32.Parse(integrity[integrity.Length-1]);
            AppIdNative.Statistics statistics=Query<AppIdNative.Statistics>(token,10,delegate(IntPtr p,uint n){Guard.Require(n==56,"token_statistics_size");return (AppIdNative.Statistics)Marshal.PtrToStructure(p,typeof(AppIdNative.Statistics));});
            value.Authentication=statistics.AuthenticationId;
            if(value.Type==2){Guard.Require(statistics.Impersonation<=3,"token_impersonation_level_invalid");value.ImpersonationLevel=statistics.Impersonation;}
            return value;
        }
        internal static MediumIdentity OfProcess(IntPtr process) {
            IntPtr token; AppIdNative.Win(Native.OpenProcessToken(process,8,out token),"process_token_open_failed");
            try { return Read(token); } finally { Native.CloseHandle(token); }
        }
    }
    internal sealed class LinkedMediumToken : IDisposable {
        internal IntPtr Handle; internal MediumIdentity Identity;
        static object Attributes(MediumIdentity identity) {
            if(identity==null)return null;
            return new Dictionary<string,object>{{"type",identity.Type},{"integrity_rid",identity.Integrity},{"elevation_type",identity.ElevationType},{"elevated",identity.Elevated},{"appcontainer",identity.AppContainer},{"authentication_id_nonzero",identity.Authentication!=0},{"impersonation_level",identity.Type==2?(object)identity.ImpersonationLevel:null}};
        }
        internal static Dictionary<string,object> Diagnostic(MediumIdentity full,MediumIdentity selected) {
            bool available=full!=null&&selected!=null;
            return new Dictionary<string,object>{{"schema","p6_r7_linked_token_diagnostic_v1"},{"diagnostic_only",true},{"parent",Attributes(full)},{"selected",Attributes(selected)},{"same_user",available?(object)(full.User==selected.User):null},{"same_session",available?(object)(full.Session==selected.Session):null}};
        }
        internal static void ValidateLinked(MediumIdentity full,MediumIdentity selected,Dictionary<string,object> report) {
            // Record only reconstructed fixed attributes before rejection; never serialize an identity object.
            report["linked_token_diagnostic"]=Diagnostic(full,selected);
            Guard.Require(MediumIdentity.AcceptLinked(full,selected),"linked_token_rejected");
        }
        internal static Dictionary<string,object> DuplicateDiagnostic(MediumIdentity source,MediumIdentity duplicate) {
            return new Dictionary<string,object>{{"schema","p6_r7_linked_duplicate_diagnostic_v1"},{"diagnostic_only",true},{"duplicate",Attributes(duplicate)},{"primary_identity_matches_source",source!=null&&duplicate!=null?(object)MediumIdentity.PrimaryDuplicateMatches(source,duplicate):null}};
        }
        internal static void ValidateDuplicate(MediumIdentity source,MediumIdentity duplicate,Dictionary<string,object> report) {
            report["linked_duplicate_diagnostic"]=DuplicateDiagnostic(source,duplicate);
            Guard.Require(MediumIdentity.PrimaryDuplicateMatches(source,duplicate),"linked_duplicate_mismatch");
        }
        internal static LinkedMediumToken Select(Dictionary<string,object> report) {
            IntPtr parent=IntPtr.Zero,linked=IntPtr.Zero,copy=IntPtr.Zero;
            report["linked_token_diagnostic"]=Diagnostic(null,null);
            try {
                AppIdNative.Win(Native.OpenProcessToken(Native.GetCurrentProcess(),8,out parent),"helper_token_open_failed");
                MediumIdentity full=MediumIdentity.Read(parent);
                report["linked_token_diagnostic"]=Diagnostic(full,null);
                Guard.Require(full.Type==1 && full.ElevationType==2 && full.Elevated==1 && full.AppContainer==0,"helper_full_elevated_required");
                linked=MediumIdentity.Query<IntPtr>(parent,19,delegate(IntPtr p,uint n){Guard.Require(n==IntPtr.Size,"linked_token_size");return Marshal.ReadIntPtr(p);});
                Guard.Require(linked!=IntPtr.Zero,"linked_token_missing"); MediumIdentity selected=MediumIdentity.Read(linked);
                ValidateLinked(full,selected,report);
                report["linked_duplicate_diagnostic"]=DuplicateDiagnostic(selected,null);
                AppIdNative.Win(AppIdNative.DuplicateTokenEx(linked,1|2|8,IntPtr.Zero,2,1,out copy),"linked_token_duplicate_failed");
                MediumIdentity duplicate=MediumIdentity.Read(copy); ValidateDuplicate(selected,duplicate,report);
                // AuthenticationId belongs to the selected linked token; do not compare it with the elevated parent.
                LinkedMediumToken result=new LinkedMediumToken {Handle=copy,Identity=duplicate}; copy=IntPtr.Zero; return result;
            } finally { if(copy!=IntPtr.Zero) Native.CloseHandle(copy); if(linked!=IntPtr.Zero) Native.CloseHandle(linked); if(parent!=IntPtr.Zero) Native.CloseHandle(parent); }
        }
        public void Dispose() { if(Handle!=IntPtr.Zero) Native.CloseHandle(Handle); Handle=IntPtr.Zero; }
    }

    internal sealed class AppIdBoundary : IDisposable {
        internal static readonly Guid AppId=new Guid("d78e1e87-8644-4ea5-9437-d809ecefc971");
        internal readonly Guid Sublayer; internal readonly Rule[] Rules; readonly byte[] identifier;
        IntPtr engine; internal bool Installed,Verified;
        internal static Guid Key(Guid attempt,string tag) {
            using(SHA256 hash=SHA256.Create()) { byte[] digest=hash.ComputeHash(Encoding.ASCII.GetBytes("HereIAm.P6R7.AppIdV11/"+attempt.ToString("N")+"/"+tag)); byte[] key=new byte[16]; Array.Copy(digest,key,16); return new Guid(key); }
        }
        internal static Rule[] MakeRules(Guid attempt,int port) {
            Guard.Require(attempt!=Guid.Empty && port>0 && port<=65535,"appid_policy_rejected");
            return new Rule[]{new Rule{Key=Key(attempt,"allow4"),Layer=Policy.Connect4,Permit=true,Weight=15,Port=port},new Rule{Key=Key(attempt,"deny4"),Layer=Policy.Connect4},new Rule{Key=Key(attempt,"deny6"),Layer=Policy.Connect6}};
        }
        internal static byte[] CopyBlob(IntPtr pointer) {
            Guard.Require(pointer!=IntPtr.Zero,"appid_blob_missing"); Native.Blob blob=(Native.Blob)Marshal.PtrToStructure(pointer,typeof(Native.Blob));
            Guard.Require(blob.Size>0 && blob.Size<=65536 && blob.Data!=IntPtr.Zero,"appid_blob_rejected"); byte[] bytes=new byte[blob.Size]; Marshal.Copy(blob.Data,bytes,0,bytes.Length); return bytes;
        }
        internal static bool SameBytes(byte[] a,byte[] b) { if(a==null||b==null||a.Length!=b.Length) return false; for(int i=0;i<a.Length;i++) if(a[i]!=b[i]) return false; return true; }
        internal AppIdBoundary(Guid attempt,int port,string executable) {
            Rules=MakeRules(attempt,port); Sublayer=Key(attempt,"sublayer"); IntPtr memory=IntPtr.Zero;
            try { Guard.Status(AppIdNative.FwpmGetAppIdFromFileName0(executable,out memory),"appid_query_failed"); identifier=CopyBlob(memory); }
            finally { if(memory!=IntPtr.Zero) Native.FwpmFreeMemory0(ref memory); }
        }
        void Open() { if(engine==IntPtr.Zero) Guard.Status(Native.FwpmEngineOpen0(null,10,IntPtr.Zero,IntPtr.Zero,out engine),"appid_wfp_open_failed"); }
        internal void Install() {
            Open(); Guard.Status(Native.FwpmTransactionBegin0(engine,0),"appid_transaction_failed"); bool committed=false;
            try { using(Arena a=new Arena()) {
                Native.Display display=new Native.Display{Name=a.Text("HereIAm R7 AppId no-auth candidate"),Description=a.Text("One copied image path, not an instance or hash boundary")};
                Native.Sublayer sub=new Native.Sublayer{Key=Sublayer,Display=display,Weight=0x7fff}; Guard.Status(Native.FwpmSubLayerAdd0(engine,ref sub,IntPtr.Zero),"appid_sublayer_failed");
                IntPtr blob=a.Struct(new Native.Blob{Size=(uint)identifier.Length,Data=a.Bytes(identifier)});
                foreach(Rule rule in Rules) {
                    List<Native.Condition> conditions=new List<Native.Condition>(); conditions.Add(new Native.Condition{Field=AppId,Value=new Native.Value{Type=12,Pointer=blob}});
                    if(rule.Permit) { conditions.Add(new Native.Condition{Field=Policy.Protocol,Value=new Native.Value{Type=1,Number=6}}); conditions.Add(new Native.Condition{Field=Policy.RemoteAddress,Value=new Native.Value{Type=3,Number=0x7f000001}}); conditions.Add(new Native.Condition{Field=Policy.RemotePort,Value=new Native.Value{Type=2,Number=(uint)rule.Port}}); }
                    Native.Filter filter=new Native.Filter{Key=rule.Key,Display=display,Layer=rule.Layer,Sublayer=Sublayer,Weight=new Native.Value{Type=1,Number=rule.Weight},Count=(uint)conditions.Count,Conditions=a.Array(conditions.ToArray()),Action=new Native.Action{Type=rule.Permit?0x1002U:0x1001U}};
                    ulong id; Guard.Status(Native.FwpmFilterAdd0(engine,ref filter,IntPtr.Zero,out id),"appid_filter_failed");
                }
                Guard.Status(Native.FwpmTransactionCommit0(engine),"appid_commit_failed"); committed=true; Installed=true; Verified=true;
            } } finally { if(!committed) Native.FwpmTransactionAbort0(engine); }
        }
        internal void OpenAndVerify() {
            Open(); bool any=false;
            foreach(Rule rule in Rules) {
                Guid key=rule.Key; IntPtr pointer; uint status=Native.FwpmFilterGetByKey0(engine,ref key,out pointer); if(status==0x80320003U) continue;
                Guard.Status(status,"appid_recovery_filter_read_failed");
                try {
                    Native.Filter f=(Native.Filter)Marshal.PtrToStructure(pointer,typeof(Native.Filter));
                    Guard.Require(f.Key==rule.Key && f.Sublayer==Sublayer && f.Layer==rule.Layer && f.Action.Type==(rule.Permit?0x1002U:0x1001U) && f.Flags==0 && f.Provider==IntPtr.Zero && f.Weight.Type==1 && (byte)f.Weight.Number==rule.Weight && f.Count==(rule.Permit?4U:1U) && f.Conditions!=IntPtr.Zero,"appid_recovery_filter_mismatch");
                    HashSet<Guid> seen=new HashSet<Guid>(); int stride=Marshal.SizeOf(typeof(Native.Condition));
                    for(int i=0;i<f.Count;i++) {
                        Native.Condition c=(Native.Condition)Marshal.PtrToStructure(IntPtr.Add(f.Conditions,i*stride),typeof(Native.Condition)); Guard.Require(c.Match==0 && seen.Add(c.Field),"appid_recovery_condition_mismatch");
                        bool valid=c.Field==AppId && c.Value.Type==12 && SameBytes(identifier,CopyBlob(c.Value.Pointer));
                        if(rule.Permit) valid=valid || c.Field==Policy.Protocol && c.Value.Type==1 && (byte)c.Value.Number==6 || c.Field==Policy.RemoteAddress && c.Value.Type==3 && (uint)c.Value.Number==0x7f000001 || c.Field==Policy.RemotePort && c.Value.Type==2 && (ushort)c.Value.Number==rule.Port;
                        Guard.Require(valid,"appid_recovery_condition_mismatch");
                    }
                    Guard.Require(seen.Contains(AppId),"appid_recovery_appid_missing"); any=true;
                } finally { Native.FwpmFreeMemory0(ref pointer); }
            }
            Guid sub=Sublayer; IntPtr subPointer; uint subStatus=Native.FwpmSubLayerGetByKey0(engine,ref sub,out subPointer);
            if(subStatus==0) { try { Native.Sublayer s=(Native.Sublayer)Marshal.PtrToStructure(subPointer,typeof(Native.Sublayer)); Guard.Require(s.Key==Sublayer && s.Flags==0 && s.Weight==0x7fff && s.Provider==IntPtr.Zero,"appid_recovery_sublayer_mismatch"); any=true; } finally { Native.FwpmFreeMemory0(ref subPointer); } }
            else Guard.Require(subStatus==0x80320007U && !any,"appid_recovery_sublayer_unavailable");
            Installed=any; Verified=true;
        }
        internal void RemoveAfterZero(bool zero) {
            Guard.Require(zero,"appid_cleanup_requires_closure"); if(!Installed) return;
            Guard.Status(Native.FwpmTransactionBegin0(engine,0),"appid_cleanup_transaction_failed"); bool committed=false;
            try {
                foreach(Rule rule in Rules) { Guid key=rule.Key; uint result=Native.FwpmFilterDeleteByKey0(engine,ref key); Guard.Require(result==0||result==0x80320003U,"appid_cleanup_filter_failed"); }
                Guid sub=Sublayer; uint s=Native.FwpmSubLayerDeleteByKey0(engine,ref sub); Guard.Require(s==0||s==0x80320007U,"appid_cleanup_sublayer_failed");
                Guard.Status(Native.FwpmTransactionCommit0(engine),"appid_cleanup_commit_failed"); committed=true; Installed=false;
            } finally { if(!committed) Native.FwpmTransactionAbort0(engine); }
        }
        public void Dispose() { if(engine!=IntPtr.Zero) Native.FwpmEngineClose0(engine); engine=IntPtr.Zero; }
    }
    internal static class AppIdLauncher {
        internal static void Create(RestrictedProcess child,LinkedMediumToken token,string executable,string cwd,string environment,RedirectedStdio stdio,int port) {
            Guard.Require(!child.Started && token.Identity.IsMedium,"launch_precondition_failed"); AppIdProgram.VerifyImage(executable);
            child.Job=Native.CreateJobObjectW(IntPtr.Zero,null); AppIdNative.Win(child.Job!=IntPtr.Zero,"job_create_failed");
            Native.ExtendedLimit limit=new Native.ExtendedLimit(); limit.Basic.Flags=0x2000|0x8; limit.Basic.ActiveLimit=1;
            AppIdNative.Win(Native.SetInformationJobObject(child.Job,9,ref limit,(uint)Marshal.SizeOf(typeof(Native.ExtendedLimit))),"job_limit_failed");
            IntPtr size=IntPtr.Zero; Native.InitializeProcThreadAttributeList(IntPtr.Zero,2,0,ref size); Guard.Require(size.ToInt64()>0 && size.ToInt64()<65536,"attribute_size_failed");
            IntPtr list=Marshal.AllocHGlobal(size); bool initialized=false;Arena a=new Arena();
            try {
                AppIdNative.Win(Native.InitializeProcThreadAttributeList(list,2,0,ref size),"attribute_init_failed"); initialized=true;
                AppIdNative.Win(Native.UpdateProcThreadAttribute(list,0,new IntPtr(0x2000d),a.Struct(child.Job),new IntPtr(IntPtr.Size),IntPtr.Zero,IntPtr.Zero),"atomic_job_attribute_failed");
                IntPtr[] handles=stdio.ChildHandles; AppIdNative.Win(Native.UpdateProcThreadAttribute(list,0,new IntPtr(0x20002),a.Array(handles),new IntPtr(3*IntPtr.Size),IntPtr.Zero,IntPtr.Zero),"stdio_allowlist_failed");
                Native.StartupEx startup=new Native.StartupEx(); startup.Info.Size=(uint)Marshal.SizeOf(typeof(Native.StartupEx)); startup.Attributes=list;
                startup.Info.Flags=0x100; startup.Info.Input=handles[0]; startup.Info.Output=handles[1]; startup.Info.Error=handles[2];
                Native.ProcessInfo process;
                bool created=AppIdNative.CreateProcessAsUserW(token.Handle,executable,new StringBuilder("\""+executable+"\" "+CliStartupContract.Arguments(port)),IntPtr.Zero,IntPtr.Zero,true,0x80000|0x400|4|0x08000000,a.Text(environment),cwd,ref startup,out process);
                uint error=unchecked((uint)Marshal.GetLastWin32Error()); Guard.Win32(created,error,"medium_process_spawn_failed");
                child.Handle=process.Process; child.ThreadHandle=process.Thread; child.Pid=process.Pid; child.Started=true; child.Created=TokenProof.Creation(child.Handle);
                stdio.ChildCreated(); bool member; AppIdNative.Win(Native.IsProcessInJob(child.Handle,child.Job,out member),"job_membership_query_failed"); Guard.Require(member,"job_membership_failed");
                TokenProof.Image(child.Handle,executable); AppIdProgram.VerifyImage(executable);
                Guard.Require(token.Identity.Same(MediumIdentity.OfProcess(child.Handle)),"postspawn_identity_mismatch");
            } finally { if(initialized) Native.DeleteProcThreadAttributeList(list);a.Dispose();Marshal.FreeHGlobal(list); }
        }
        internal static bool Peer(Socket socket,RestrictedProcess child,MediumIdentity expected,string executable) {
            try {
                if(!child.Alive() || socket.AddressFamily!=AddressFamily.InterNetwork) return false;
                IPEndPoint client=(IPEndPoint)socket.RemoteEndPoint,broker=(IPEndPoint)socket.LocalEndPoint;
                if(!IPAddress.Loopback.Equals(client.Address)||!IPAddress.Loopback.Equals(broker.Address)) return false;
                uint size=0; uint code=Native.GetExtendedTcpTable(IntPtr.Zero,ref size,false,2,5,0);
                if(code!=122 || size<PeerAdmission.HeaderSize || size>16777216) return false;
                for(int retry=0;retry<3;retry++) {
                    IntPtr table=Marshal.AllocHGlobal((int)size);
                    try {
                        uint capacity=size; code=Native.GetExtendedTcpTable(table,ref size,false,2,5,0); if(code==122) {if(size<PeerAdmission.HeaderSize||size>16777216)return false;continue;} if(code!=0)return false;
                        uint count=unchecked((uint)Marshal.ReadInt32(table)); int stride=Marshal.SizeOf(typeof(Native.TcpRow)); if(count>(capacity-PeerAdmission.HeaderSize)/stride)return false; int matches=0;
                        for(int i=0;i<count;i++) if(PeerAdmission.Matches((Native.TcpRow)Marshal.PtrToStructure(IntPtr.Add(table,PeerAdmission.HeaderSize+i*stride),typeof(Native.TcpRow)),client,broker,child.Pid)) matches++;
                        if(matches!=1 || !child.Alive() || socket.Poll(0,SelectMode.SelectRead)&&socket.Available==0 || socket.Poll(0,SelectMode.SelectError)) return false;
                        TokenProof.Image(child.Handle,executable); return expected.Same(MediumIdentity.OfProcess(child.Handle));
                    } finally { Marshal.FreeHGlobal(table); }
                }
            } catch { } return false;
        }
    }

    public static class AppIdProgram {
        internal const string Root=@"D:\memex\tmp\p6-r7-appid-isolation";
        const string JournalSchema="p6_r7_owned_appid_startup_v1";
        internal static string Json(object value) { return new JavaScriptSerializer().Serialize(value); }
        static Dictionary<string,object> Result(string mode) { return new Dictionary<string,object>{{"schema","p6_r7_cli_appid_startup_candidate_v1"},{"mode",mode},{"system_mutation_requested",false},{"appid_startup_passed",false},{"appcontainer_isolation_passed",false},{"production_isolation_passed",false},{"human_gate_passed",false},{"real_upstream_requests",0},{"model_turns_requested",0},{"network_enforcement_tested",false},{"profile_operations",0},{"loopback_config_operations",0}}; }
        static void Error(Dictionary<string,object> report,Exception error,string fallback) { BoundaryError b=error as BoundaryError; if(!report.ContainsKey("error_code"))report["error_code"]=b==null?fallback:b.Code; if(b!=null&&b.Win32Error.HasValue)report["win32_error"]=b.Win32Error.Value; }
        static void Secondary(Dictionary<string,object> report,string field,string value) {report[field]=value;if(!report.ContainsKey("error_code"))report["error_code"]=value;}
        internal static void VerifyImage(string image) {
            Guard.Require(image!=null && Path.IsPathRooted(image) && Path.GetFullPath(image)==image && String.Equals(Path.GetFileName(image),"codex.exe",StringComparison.OrdinalIgnoreCase),"cli_path_rejected");
            Guard.CanonicalDirectory(Path.GetDirectoryName(image)); Guard.Require((File.GetAttributes(image)&FileAttributes.ReparsePoint)==0 && TokenProof.Hash(image)==CliStartupContract.Pin,"cli_pin_rejected");
        }
        static void Acl(string directory,string user,bool writable) {
            DirectorySecurity acl=new DirectorySecurity(); acl.SetAccessRuleProtection(true,false); InheritanceFlags flags=InheritanceFlags.ContainerInherit|InheritanceFlags.ObjectInherit;
            foreach(SecurityIdentifier id in new SecurityIdentifier[]{new SecurityIdentifier(WellKnownSidType.LocalSystemSid,null),new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid,null)}) acl.AddAccessRule(new FileSystemAccessRule(id,FileSystemRights.FullControl,flags,PropagationFlags.None,AccessControlType.Allow));
            acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(user),writable?FileSystemRights.Modify:FileSystemRights.ReadAndExecute,flags,PropagationFlags.None,AccessControlType.Allow)); Directory.SetAccessControl(directory,acl);
        }
        static void WriteJournal(string directory,Dictionary<string,object> value) {
            Guard.CanonicalDirectory(directory); string next=Path.Combine(directory,"ownership.next.json"),target=Path.Combine(directory,"ownership.json");
            foreach(string path in new string[]{next,target}) if(File.Exists(path))Guard.Require((File.GetAttributes(path)&FileAttributes.ReparsePoint)==0,"journal_reparse");
            byte[] bytes=Encoding.UTF8.GetBytes(Json(value)); Guard.Require(bytes.Length<=16384,"journal_limit");
            using(FileStream stream=new FileStream(next,FileMode.Create,FileAccess.Write,FileShare.None)) {stream.Write(bytes,0,bytes.Length);stream.Flush(true);}
            if(File.Exists(target)) File.Replace(next,target,null); else File.Move(next,target);
        }
        static Dictionary<string,object> NewJournal(Guid attempt,int port,MediumIdentity identity,uint ownerPid,ulong ownerCreation) {
            return new Dictionary<string,object>{{"schema",JournalSchema},{"mode","apply_cli_appid_startup_synthetic"},{"attempt_id",attempt.ToString("D")},{"atomic_job",true},{"creation_started",false},{"image","codex.exe"},{"image_sha256",CliStartupContract.Pin},{"broker_port",port},{"owner_pid",ownerPid},{"owner_creation",ownerCreation.ToString()},{"child_pid",null},{"child_creation",null},{"selected_user_sid",identity.User},{"selected_session_id",identity.Session},{"selected_authentication_id",identity.Authentication.ToString("x16")},{"selected_integrity",identity.Integrity},{"selected_elevation_type",identity.ElevationType},{"selected_elevated",identity.Elevated},{"selected_appcontainer",identity.AppContainer},{"selected_token_type",identity.Type}};
        }
        static uint Number(object value) { Guard.Require(value is int || value is long || value is uint,"journal_number_invalid"); long number=Convert.ToInt64(value); Guard.Require(number>=0&&number<=UInt32.MaxValue,"journal_number_invalid");return (uint)number; }
        static ulong TimeValue(object value) { string text=value as string; ulong number; Guard.Require(text!=null&&UInt64.TryParse(text,out number)&&number>0,"journal_time_invalid"); number=UInt64.Parse(text);Guard.Require(number.ToString()==text,"journal_time_invalid");return number; }
        static MediumIdentity JournalIdentity(Dictionary<string,object> data) {
            string user=data["selected_user_sid"] as string,auth=data["selected_authentication_id"] as string;
            Guard.Require(user!=null && user.Length<184 && new SecurityIdentifier(user).Value==user && auth!=null && System.Text.RegularExpressions.Regex.IsMatch(auth,"\\A[0-9a-f]{16}\\z"),"journal_identity_invalid");
            MediumIdentity id=new MediumIdentity{User=user,Session=Number(data["selected_session_id"]),Authentication=UInt64.Parse(auth,System.Globalization.NumberStyles.HexNumber),Integrity=Number(data["selected_integrity"]),ElevationType=Number(data["selected_elevation_type"]),Elevated=Number(data["selected_elevated"]),AppContainer=Number(data["selected_appcontainer"]),Type=Number(data["selected_token_type"])};
            Guard.Require(id.IsMedium && id.Authentication!=0,"journal_identity_invalid"); return id;
        }
        internal static Dictionary<string,object> ParseJournal(string raw,Guid attempt) {
            Guard.Require(raw!=null&&Encoding.UTF8.GetByteCount(raw)<=16384,"journal_limit"); JavaScriptSerializer parser=new JavaScriptSerializer{MaxJsonLength=16384,RecursionLimit=4};
            Dictionary<string,object> data=parser.DeserializeObject(raw) as Dictionary<string,object>; Guard.Require(data!=null && Json(data)==raw,"journal_noncanonical");
            string[] keys=new string[]{"schema","mode","attempt_id","atomic_job","creation_started","image","image_sha256","broker_port","owner_pid","owner_creation","child_pid","child_creation","selected_user_sid","selected_session_id","selected_authentication_id","selected_integrity","selected_elevation_type","selected_elevated","selected_appcontainer","selected_token_type"};
            Guard.Require(data.Count==keys.Length,"journal_schema_rejected");foreach(string key in keys)Guard.Require(data.ContainsKey(key),"journal_schema_rejected");
            Guard.Require((string)data["schema"]==JournalSchema&&(string)data["mode"]=="apply_cli_appid_startup_synthetic"&&(string)data["attempt_id"]==attempt.ToString("D")&&(string)data["image"]=="codex.exe"&&(string)data["image_sha256"]==CliStartupContract.Pin&&data["atomic_job"] is bool&&(bool)data["atomic_job"]&&data["creation_started"] is bool,"journal_scope_rejected");
            uint port=Number(data["broker_port"]);Guard.Require(port>0&&port<=65535&&Number(data["owner_pid"])>0,"journal_binding_invalid");TimeValue(data["owner_creation"]);JournalIdentity(data);
            Guard.Require((data["child_pid"]==null)==(data["child_creation"]==null),"journal_binding_invalid");
            if(data["child_pid"]!=null) {Guard.Require((bool)data["creation_started"]&&Number(data["child_pid"])>0,"journal_binding_invalid");TimeValue(data["child_creation"]);}
            return data;
        }
        static bool OwnerAlive(uint pid,ulong creation) {
            IntPtr process=Native.OpenProcess(0x1000|0x100000,false,pid); if(process==IntPtr.Zero){Guard.Require(Marshal.GetLastWin32Error()==87,"owner_query_failed");return false;}
            try{uint state=Native.WaitForSingleObject(process,0);Guard.Require(state==0||state==258,"owner_wait_failed");return TokenProof.Creation(process)==creation&&state==258;}finally{Native.CloseHandle(process);}
        }
        static string RecoverChild(Dictionary<string,object> journal,string image,MediumIdentity expected) {
            if(!(bool)journal["creation_started"])return "creation_not_started"; Guard.Require(journal["child_pid"]!=null,"recovery_binding_missing");
            IntPtr process=Native.OpenProcess(0x1000|0x100000|1,false,Number(journal["child_pid"]));
            if(process==IntPtr.Zero){Guard.Require(Marshal.GetLastWin32Error()==87,"recovery_child_query_failed");return "bound_pid_absent";}
            try {
                if(TokenProof.Creation(process)!=TimeValue(journal["child_creation"]))return "bound_pid_reused";
                if(Native.WaitForSingleObject(process,0)==0)return "bound_process_signaled";
                TokenProof.Image(process,image);VerifyImage(image);Guard.Require(expected.Same(MediumIdentity.OfProcess(process)),"recovery_child_identity_mismatch");
                AppIdNative.Win(Native.TerminateProcess(process,125),"recovery_terminate_failed");Guard.Require(Native.WaitForSingleObject(process,5000)==0,"recovery_exit_unconfirmed");return "bound_process_exit_observed";
            }finally{Native.CloseHandle(process);}
        }
        static int Recover(Guid attempt) {
            ValidateLayouts();
            Dictionary<string,object> report=Result("recover_cli_appid_startup_synthetic");report["system_mutation_requested"]=true;report["cleanup_pending"]=true;report["attempt_id"]=attempt.ToString("D"); AppIdBoundary boundary=null;
            string directory=Path.Combine(Root,attempt.ToString("N"));
            try {
                MediumIdentity host=MediumIdentity.OfProcess(Native.GetCurrentProcess());Guard.Require(host.ElevationType==2&&host.Elevated==1&&host.AppContainer==0,"recovery_elevation_required");
                Guard.CanonicalDirectory(directory);string path=Path.Combine(directory,"ownership.json");Guard.Require((File.GetAttributes(path)&FileAttributes.ReparsePoint)==0&&new FileInfo(path).Length<=16384,"recovery_journal_unavailable");
                Dictionary<string,object> journal=ParseJournal(File.ReadAllText(path,new UTF8Encoding(false,true)),attempt);MediumIdentity selected=JournalIdentity(journal);Guard.Require(selected.User==host.User,"recovery_user_mismatch");
                Guard.Require(!OwnerAlive(Number(journal["owner_pid"]),TimeValue(journal["owner_creation"])),"attempt_owner_active");
                string image=Path.Combine(directory,"codex.exe");VerifyImage(image);boundary=new AppIdBoundary(attempt,(int)Number(journal["broker_port"]),image);boundary.OpenAndVerify();
                report["process_closure_basis"]=RecoverChild(journal,image,selected);report["singleton_closure_proven"]=(bool)journal["creation_started"];report["cleanup_no_child_created"]=!(bool)journal["creation_started"];
                boundary.RemoveAfterZero(true);report["cleanup_pending"]=false;
            }catch(Exception e){Error(report,e,"appid_recovery_failed");}
            finally {
                report["deny_rules_state"]=boundary==null||!boundary.Verified?"unverified":boundary.Installed?"retained":"absent";if(boundary!=null)boundary.Dispose();
                try{Guard.CanonicalDirectory(directory);string path=Path.Combine(directory,"recovery-report.json");Guard.Require(!File.Exists(path)||((File.GetAttributes(path)&FileAttributes.ReparsePoint)==0),"report_reparse");File.WriteAllText(path,Json(report));}catch{report["report_file_written"]=false;}
                Console.WriteLine(Json(report));
            }return (bool)report["cleanup_pending"]?3:0;
        }
        static int Apply(string source) {
            ValidateLayouts();
            Dictionary<string,object> report=Result("apply_cli_appid_startup_synthetic");report["system_mutation_requested"]=true;report["cleanup_pending"]=true;
            Guid attempt=Guid.NewGuid();string directory=Path.Combine(Root,attempt.ToString("N"));report["attempt_id"]=attempt.ToString("D");
            RestrictedProcess child=new RestrictedProcess();LinkedMediumToken selected=null;AppIdBoundary boundary=null;RedirectedStdio stdio=null;TcpListener broker=null;Thread listener=null;int stop=0,http=0;string brokerError=null,stage="preflight";bool zero=false,clean=false;
            try {
                Guard.CanonicalDirectory(Root);Guard.Require(!Directory.Exists(directory)&&!File.Exists(directory),"attempt_exists");Directory.CreateDirectory(directory);Acl(directory,WindowsIdentity.GetCurrent().User.Value,false);Guard.CanonicalDirectory(directory);
                VerifyImage(source);stage="linked_token_selection";selected=LinkedMediumToken.Select(report);report["linked_medium_token_verified"]=true;
                string image=Path.Combine(directory,"codex.exe");File.Copy(source,image,false);VerifyImage(image);
                string work=Path.Combine(directory,"work");Directory.CreateDirectory(work);Acl(work,selected.Identity.User,true);
                foreach(string name in new string[]{"empty-home","empty-workspace","Roaming","Temp"}){string path=Path.Combine(work,name);Directory.CreateDirectory(path);Guard.CanonicalDirectory(path);}
                string cwd=Path.Combine(work,"empty-workspace"),environment=CliStartupContract.EnvironmentBlock(Environment.GetFolderPath(Environment.SpecialFolder.Windows),work);
                broker=new TcpListener(IPAddress.Loopback,0);broker.ExclusiveAddressUse=true;broker.Start();int port=((IPEndPoint)broker.LocalEndpoint).Port;
                Dictionary<string,object> journal=NewJournal(attempt,port,selected.Identity,(uint)Process.GetCurrentProcess().Id,TokenProof.Creation(Native.GetCurrentProcess()));WriteJournal(directory,journal);
                stage="appid_wfp";boundary=new AppIdBoundary(attempt,port,image);boundary.Install();report["appid_filters_installed"]=true;
                stdio=new RedirectedStdio(directory);stage="launch";journal["creation_started"]=true;WriteJournal(directory,journal);
                AppIdLauncher.Create(child,selected,image,cwd,environment,stdio,port);journal["child_pid"]=child.Pid;journal["child_creation"]=child.Created.ToString();WriteJournal(directory,journal);
                report["postspawn_token_verified"]=true;report["job_membership_verified"]=true;report["image_pin_verified"]=true;
                using(TcpClient outsider=new TcpClient()){outsider.Connect(IPAddress.Loopback,port);using(Socket socket=broker.AcceptSocket())report["wrong_peer_rejected"]=!AppIdLauncher.Peer(socket,child,selected.Identity,image);}
                Guard.Require((bool)report["wrong_peer_rejected"],"wrong_peer_admitted");
                listener=new Thread(delegate(){try{while(Interlocked.CompareExchange(ref stop,0,0)==0){if(!broker.Pending()){Thread.Sleep(10);continue;}using(Socket socket=broker.AcceptSocket()){if(AppIdLauncher.Peer(socket,child,selected.Identity,image)){Interlocked.Increment(ref http);socket.SendTimeout=1000;socket.Send(Encoding.ASCII.GetBytes("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"));}}}}catch{if(Interlocked.CompareExchange(ref stop,0,0)==0)brokerError="broker_failed";}});listener.IsBackground=true;listener.Start();
                stage="cli_initialize";child.Resume();stdio.WriteLine("{\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"p6_appid_startup\",\"version\":\"1\"},\"capabilities\":{\"experimentalApi\":true}}}");stdio.Reply(1,10000);report["initialize_replied"]=true;
                stdio.WriteLine("{\"method\":\"initialized\",\"params\":{}}");stage="cli_config_read";stdio.WriteLine(Json(new Dictionary<string,object>{{"id",2},{"method","config/read"},{"params",new Dictionary<string,object>{{"cwd",cwd},{"includeLayers",true}}}}));
                Guard.Require(CliStartupContract.ConfigMatches(stdio.Reply(2,10000),port),"startup_config_rejected");report["config_checks_passed"]=true;stdio.Check();stdio.EndInput();report["stdin_eof_exit_observed"]=Native.WaitForSingleObject(child.Handle,5000)==0;stage="finished";
            }catch(Exception e){Error(report,e,"appid_startup_failed");}
            finally {
                report["stage"]=stage;Interlocked.Exchange(ref stop,1);if(listener!=null&&!listener.Join(2000))brokerError="broker_exit_unconfirmed";if(broker!=null)broker.Stop();
                if(stdio!=null)try{stdio.EndInput();}catch{Secondary(report,"stdin_error_code","stdin_close_failed");}
                try{zero=child.StopAndProveZero();}catch{zero=false;}
                report["owned_child_created"]=child.Started;report["cleanup_no_child_created"]=!child.Started;report["process_exit_observed"]=child.ExitObserved;report["job_zero_proven"]=child.Started&&zero;
                report["exit_code_before_termination_observed"]=child.ExitCodeBeforeTermination.HasValue;if(child.ExitCodeBeforeTermination.HasValue)report["child_exit_code_before_termination"]=child.ExitCodeBeforeTermination.Value;report["exit_code_query_failed"]=child.ExitCodeQueryFailed;
                if(zero)try{if(boundary!=null)boundary.RemoveAfterZero(true);clean=true;}catch(Exception e){Secondary(report,"cleanup_error_code",e is BoundaryError?((BoundaryError)e).Code:"cleanup_failed");}
                report["cleanup_pending"]=!clean;report["deny_rules_state"]=boundary==null?"not_created":!boundary.Verified?"unverified":boundary.Installed?"retained":"absent";
                bool readers=stdio!=null&&stdio.ReadersEnded();report["stdio_readers_eof_confirmed"]=readers;report["stdout_byte_count"]=stdio==null?0:stdio.OutputBytes;report["stderr_byte_count"]=stdio==null?0:stdio.ErrorBytes;
                if(stdio!=null&&stdio.StderrDiagnostic!=null)report["stderr_diagnostic"]=stdio.StderrDiagnostic;
                report["server_requests_rejected"]=stdio==null?0:stdio.RejectedServerRequests;report["local_http_attempt_count"]=http;
                if(!readers&&child.Started)Secondary(report,"stdio_error_code","stdio_reader_failed");if(brokerError!=null)Secondary(report,"broker_error_code",brokerError);if(http!=0)Secondary(report,"http_error_code","startup_http_attempted");
                bool eof=report.ContainsKey("stdin_eof_exit_observed")&&(bool)report["stdin_eof_exit_observed"];report["normal_exit_code_zero"]=child.ExitCodeBeforeTermination.HasValue&&child.ExitCodeBeforeTermination.Value==0&&!child.ExitCodeQueryFailed;
                report["appid_startup_passed"]=Policy.CliStartupPassed(report.ContainsKey("config_checks_passed"),readers,zero,clean,eof,report.ContainsKey("error_code"))&&(bool)report["normal_exit_code_zero"];
                if(stdio!=null&&(!child.Started||readers))try{stdio.Dispose();}catch{Secondary(report,"stdio_error_code","stdio_dispose_failed");report["appid_startup_passed"]=false;}
                child.Dispose();if(selected!=null)selected.Dispose();if(boundary!=null)boundary.Dispose();
                try{if(Directory.Exists(directory)){Guard.CanonicalDirectory(directory);string path=Path.Combine(directory,"report.json");Guard.Require(!File.Exists(path)||((File.GetAttributes(path)&FileAttributes.ReparsePoint)==0),"report_reparse");File.WriteAllText(path,Json(report));}}catch{report["report_file_written"]=false;report["appid_startup_passed"]=false;}
                Console.WriteLine(Json(report));
            }return (bool)report["appid_startup_passed"]&&clean?0:3;
        }
        static Dictionary<string,object> Plan(Guid? recovery) {
            Dictionary<string,object> report=Result(recovery.HasValue?"recovery_plan":"plan");report["network_identity"]="copied_image_path_appid";report["path_appid_is_instance_or_hash_identity"]=false;report["requires_verified_linked_medium_token"]=true;report["elevated_fallback_allowed"]=false;report["job_active_process_limit"]=1;report["atomic_job_list"]=true;report["inherited_handle_count"]=3;report["wfp_filter_count"]=3;report["wfp_dynamic_session"]=false;report["wfp_persistent_filters"]=false;report["journal_schema"]=JournalSchema;report["missing_binding_is_not_closure"]=true;
            if(recovery.HasValue){report["attempt_id"]=recovery.Value.ToString("D");report["sublayer_key"]=AppIdBoundary.Key(recovery.Value,"sublayer").ToString();}return report;
        }
        static void ValidateLayouts() {
            Guard.Require(IntPtr.Size==8 && Marshal.SizeOf(typeof(AppIdNative.Statistics))==56 && Marshal.OffsetOf(typeof(AppIdNative.Statistics),"AuthenticationId").ToInt32()==8 && Marshal.SizeOf(typeof(Native.StartupEx))==112 && Marshal.SizeOf(typeof(Native.Condition))==40 && Marshal.SizeOf(typeof(Native.Blob))==16 && Marshal.SizeOf(typeof(Native.TcpRow))==24 && PeerAdmission.HeaderSize==4,"appid_abi_failed");
        }
        static void Reject(Action action) { bool rejected=false;try{action();}catch(BoundaryError){rejected=true;}catch(ArgumentException){rejected=true;}catch(InvalidOperationException){rejected=true;}Guard.Require(rejected,"self_test_rejection_failed"); }
        static MediumIdentity FakeMedium() { return new MediumIdentity{User="S-1-5-21-1-2-3-1000",Session=1,Authentication=42,Integrity=8192,ElevationType=3,Type=1}; }
        static Dictionary<string,object> SelfTest() {
            int count=0;ValidateLayouts();count++;
            Guid id=new Guid("00000000-0000-0000-0000-000000000001");Rule[] rules=AppIdBoundary.MakeRules(id,32123);
            Guard.Require(rules.Length==3&&rules[0].Permit&&!rules[1].Permit&&!rules[2].Permit&&rules[0].Port==32123&&rules[0].Key!=Policy.Key(id,"allow4")&&rules[1].Layer==Policy.Connect4&&rules[2].Layer==Policy.Connect6,"appid_policy_failed");count++;
            Guard.Require(AppIdBoundary.Key(id,"allow4")!=AppIdBoundary.Key(id,"deny4")&&AppIdBoundary.Key(id,"allow4")!=AppIdBoundary.Key(new Guid("00000000-0000-0000-0000-000000000002"),"allow4"),"appid_namespace_failed");count++;
            foreach(int port in new int[]{0,-1,65536}){Reject(delegate{AppIdBoundary.MakeRules(id,port);});count++;}
            Reject(delegate{AppIdBoundary.MakeRules(Guid.Empty,32123);});count++;
            Guard.Require(AppIdBoundary.SameBytes(new byte[]{0,1,255},new byte[]{0,1,255})&&!AppIdBoundary.SameBytes(new byte[]{0,1},new byte[]{0,2})&&!AppIdBoundary.SameBytes(new byte[]{0},new byte[]{0,1})&&!AppIdBoundary.SameBytes(null,new byte[]{0}),"appid_blob_compare_failed");count++;
            MediumIdentity medium=FakeMedium(),full=FakeMedium();full.ElevationType=2;full.Elevated=1;full.Integrity=12288;full.Authentication=99;
            Guard.Require(medium.IsMedium&&medium.Same(FakeMedium())&&MediumIdentity.AcceptLinked(full,medium),"medium_positive_failed");count++;
            Guard.Require(!MediumIdentity.AcceptLinked(full,full)&&!MediumIdentity.AcceptLinked(medium,medium)&&!MediumIdentity.AcceptLinked(null,medium),"no_elevated_fallback_failed");count++;
            foreach(Action<MediumIdentity> mutate in new Action<MediumIdentity>[] {
                delegate(MediumIdentity m){m.ElevationType=2;},delegate(MediumIdentity m){m.Elevated=1;},delegate(MediumIdentity m){m.Integrity=12288;},delegate(MediumIdentity m){m.AppContainer=1;},delegate(MediumIdentity m){m.Type=3;},delegate(MediumIdentity m){m.Authentication=0;}
            }) {MediumIdentity bad=FakeMedium();mutate(bad);Guard.Require(!bad.IsMedium&&!MediumIdentity.AcceptLinked(full,bad)&&!medium.Same(bad),"medium_negative_failed");count++;}
            MediumIdentity wrong=FakeMedium();wrong.User="S-1-5-21-1-2-3-1001";Guard.Require(!MediumIdentity.AcceptLinked(full,wrong)&&!medium.Same(wrong),"wrong_user_failed");count++;
            wrong=FakeMedium();wrong.Session=2;Guard.Require(!MediumIdentity.AcceptLinked(full,wrong)&&!medium.Same(wrong),"wrong_session_failed");count++;
            wrong=FakeMedium();wrong.Authentication=43;Guard.Require(MediumIdentity.AcceptLinked(full,wrong)&&!medium.Same(wrong),"selected_auth_binding_failed");count++;
            Dictionary<string,object> journal=NewJournal(id,32123,medium,123,456);string raw=Json(journal);Guard.Require(ParseJournal(raw,id)!=null,"journal_positive_failed");count++;
            foreach(string key in new string[]{"schema","image","image_sha256","mode","attempt_id"}){Dictionary<string,object> bad=new Dictionary<string,object>(journal);bad[key]="PRIVATE";Reject(delegate{ParseJournal(Json(bad),id);});count++;}
            foreach(string schema in new string[]{"p6_r7_owned_resources_v2","p6_r7_owned_cli_startup_v1"}){Dictionary<string,object> bad=new Dictionary<string,object>(journal);bad["schema"]=schema;Reject(delegate{ParseJournal(Json(bad),id);});count++;}
            foreach(KeyValuePair<string,object> change in new Dictionary<string,object>{{"atomic_job",false},{"creation_started","PRIVATE"},{"broker_port",0},{"owner_pid",0},{"owner_creation","0456"},{"child_pid",123},{"child_creation","456"},{"selected_integrity",12288},{"selected_elevation_type",2},{"selected_elevated",1},{"selected_appcontainer",1},{"selected_token_type",2},{"selected_authentication_id","0000000000000000"},{"selected_session_id",-1}}){Dictionary<string,object> bad=new Dictionary<string,object>(journal);bad[change.Key]=change.Value;Reject(delegate{ParseJournal(Json(bad),id);});count++;}
            Dictionary<string,object> extra=new Dictionary<string,object>(journal);extra["PRIVATE"]=1;Reject(delegate{ParseJournal(Json(extra),id);});count++;
            Reject(delegate{ParseJournal(raw.Insert(1,"\"schema\":\"PRIVATE\","),id);});count++;
            Reject(delegate{ParseJournal(raw+" ",id);});count++;
            Reject(delegate{ParseJournal(new string('x',16385),id);});count++;
            Reject(delegate{ParseJournal(raw.Substring(0,raw.Length-1),id);});count++;
            Dictionary<string,object> missing=new Dictionary<string,object>(journal);missing["creation_started"]=true;ParseJournal(Json(missing),id);Reject(delegate{RecoverChild(missing,"unused",medium);});count++;
            Dictionary<string,object> bound=new Dictionary<string,object>(missing);bound["child_pid"]=321;bound["child_creation"]="654";Guard.Require(ParseJournal(Json(bound),id)!=null,"bound_journal_failed");count++;
            Guard.Require(RecoverChild(journal,"unused",medium)=="creation_not_started","no_child_closure_failed");count++;
            Guard.Require(Policy.CliStartupPassed(true,true,true,true,true,false)&&!Policy.CliStartupPassed(true,true,true,true,false,false)&&!Policy.CliStartupPassed(true,true,true,true,true,true),"startup_pass_boundary_failed");count++;
            Dictionary<string,object> diagnostic=Result("self_test");Error(diagnostic,new BoundaryError("fixed_first",1314),"unused");Secondary(diagnostic,"cleanup_error_code","fixed_second");Guard.Require((string)diagnostic["error_code"]=="fixed_first"&&(uint)diagnostic["win32_error"]==1314&&!Json(diagnostic).Contains("PRIVATE"),"stable_diagnostic_failed");count++;
            Dictionary<string,object> unavailable=LinkedMediumToken.Diagnostic(null,null);
            Guard.Require(unavailable.Count==6&&(string)unavailable["schema"]=="p6_r7_linked_token_diagnostic_v1"&&(bool)unavailable["diagnostic_only"]&&unavailable["parent"]==null&&unavailable["selected"]==null&&unavailable["same_user"]==null&&unavailable["same_session"]==null,"token_diagnostic_missing_failed");count++;
            Dictionary<string,object> parentOnly=LinkedMediumToken.Diagnostic(full,null);
            Guard.Require(parentOnly["parent"] is Dictionary<string,object>&&parentOnly["selected"]==null&&parentOnly["same_user"]==null&&parentOnly["same_session"]==null,"token_diagnostic_parent_only_failed");count++;
            Dictionary<string,object> tokens=LinkedMediumToken.Diagnostic(full,medium),attributes=(Dictionary<string,object>)tokens["selected"];
            Guard.Require(tokens.Count==6&&attributes.Count==7&&(uint)attributes["type"]==1&&(uint)attributes["integrity_rid"]==8192&&(uint)attributes["elevation_type"]==3&&(uint)attributes["elevated"]==0&&(uint)attributes["appcontainer"]==0&&(bool)attributes["authentication_id_nonzero"]&&attributes["impersonation_level"]==null&&(bool)tokens["same_user"]&&(bool)tokens["same_session"],"token_diagnostic_schema_failed");count++;
            MediumIdentity privateIdentity=FakeMedium();privateIdentity.User="PRIVATE_SID";privateIdentity.Session=2345678901;privateIdentity.Authentication=1234567890123456789;
            Dictionary<string,object> privateDiagnostic=LinkedMediumToken.Diagnostic(full,privateIdentity);string safeJson=Json(privateDiagnostic);
            Guard.Require(!safeJson.Contains("PRIVATE")&&!safeJson.Contains(full.User)&&!safeJson.Contains("2345678901")&&!safeJson.Contains("1234567890123456789")&&!(bool)privateDiagnostic["same_user"]&&!(bool)privateDiagnostic["same_session"],"token_diagnostic_redaction_failed");count++;
            foreach(KeyValuePair<string,object> attribute in attributes)Guard.Require(attribute.Key=="authentication_id_nonzero"?attribute.Value is bool:attribute.Key=="impersonation_level"?attribute.Value==null||attribute.Value is uint&&(uint)attribute.Value<=3:attribute.Value is uint,"token_diagnostic_value_type_failed");count++;
            MediumIdentity rejected=FakeMedium();rejected.Integrity=8448;Dictionary<string,object> rejection=Result("self_test");
            try{LinkedMediumToken.ValidateLinked(full,rejected,rejection);}catch(BoundaryError e){Error(rejection,e,"unused");}Secondary(rejection,"cleanup_error_code","fixed_cleanup_failure");
            Dictionary<string,object> retained=(Dictionary<string,object>)rejection["linked_token_diagnostic"];
            Guard.Require((string)rejection["error_code"]=="linked_token_rejected"&&(uint)((Dictionary<string,object>)retained["selected"])["integrity_rid"]==8448&&!(bool)rejection["appid_startup_passed"]&&!MediumIdentity.AcceptLinked(full,rejected),"token_diagnostic_rejection_preserved_failed");count++;
            rejected.Authentication=0;Dictionary<string,object> zeroDiagnostic=LinkedMediumToken.Diagnostic(full,rejected);
            Guard.Require(!(bool)((Dictionary<string,object>)zeroDiagnostic["selected"])["authentication_id_nonzero"]&&!MediumIdentity.AcceptLinked(full,rejected),"token_diagnostic_zero_auth_failed");count++;
            Dictionary<string,object> accepted=Result("self_test");LinkedMediumToken.ValidateLinked(full,medium,accepted);
            Guard.Require(accepted.ContainsKey("linked_token_diagnostic")&&!accepted.ContainsKey("linked_medium_token_verified")&&!(bool)accepted["appid_startup_passed"],"token_diagnostic_is_not_acceptance_failed");count++;
            MediumIdentity impersonation=FakeMedium();impersonation.Type=2;impersonation.ImpersonationLevel=2;
            Guard.Require(MediumIdentity.AcceptLinked(full,impersonation)&&!impersonation.IsMedium&&!impersonation.Same(medium)&&MediumIdentity.PrimaryDuplicateMatches(impersonation,medium)&&MediumIdentity.PrimaryDuplicateMatches(medium,FakeMedium()),"source_conversion_positive_failed");count++;
            foreach(uint unknownType in new uint[]{0,3,UInt32.MaxValue}){MediumIdentity unknown=FakeMedium();unknown.Type=unknownType;Guard.Require(!MediumIdentity.AcceptLinked(full,unknown)&&!MediumIdentity.PrimaryDuplicateMatches(unknown,medium),"source_unknown_type_failed");count++;}
            foreach(Action<MediumIdentity> mutate in new Action<MediumIdentity>[] {
                delegate(MediumIdentity m){m.User="PRIVATE";},delegate(MediumIdentity m){m.Session=2;},delegate(MediumIdentity m){m.Authentication=43;},delegate(MediumIdentity m){m.Integrity=8448;},delegate(MediumIdentity m){m.ElevationType=2;},delegate(MediumIdentity m){m.Elevated=1;},delegate(MediumIdentity m){m.AppContainer=1;},delegate(MediumIdentity m){m.Type=2;}
            }){MediumIdentity changed=FakeMedium();mutate(changed);Dictionary<string,object> failedCopy=Result("self_test");Reject(delegate{LinkedMediumToken.ValidateDuplicate(impersonation,changed,failedCopy);});Guard.Require(!(bool)((Dictionary<string,object>)failedCopy["linked_duplicate_diagnostic"])["primary_identity_matches_source"],"duplicate_change_diagnostic_failed");count++;}
            Dictionary<string,object> copyReport=Result("self_test");LinkedMediumToken.ValidateLinked(full,impersonation,copyReport);LinkedMediumToken.ValidateDuplicate(impersonation,medium,copyReport);
            Dictionary<string,object> copied=(Dictionary<string,object>)copyReport["linked_duplicate_diagnostic"];
            Guard.Require(copied.Count==4&&(bool)copied["diagnostic_only"]&&(string)copied["schema"]=="p6_r7_linked_duplicate_diagnostic_v1"&&(bool)copied["primary_identity_matches_source"]&&(uint)((Dictionary<string,object>)copied["duplicate"])["type"]==1&&((Dictionary<string,object>)copied["duplicate"])["impersonation_level"]==null&&(uint)((Dictionary<string,object>)((Dictionary<string,object>)copyReport["linked_token_diagnostic"])["selected"])["type"]==2&&(uint)((Dictionary<string,object>)((Dictionary<string,object>)copyReport["linked_token_diagnostic"])["selected"])["impersonation_level"]==2&&!Json(copyReport).Contains(medium.User)&&!(bool)copyReport["appid_startup_passed"],"duplicate_schema_failed");count++;
            Dictionary<string,object> unqueriedCopy=LinkedMediumToken.DuplicateDiagnostic(impersonation,null);Guard.Require(unqueriedCopy["duplicate"]==null&&unqueriedCopy["primary_identity_matches_source"]==null,"duplicate_missing_failed");count++;
            Dictionary<string,object> conversionError=Result("self_test");conversionError["linked_duplicate_diagnostic"]=unqueriedCopy;Error(conversionError,new BoundaryError("linked_token_duplicate_failed",1314),"unused");Guard.Require((uint)conversionError["win32_error"]==1314&&conversionError.ContainsKey("linked_duplicate_diagnostic"),"duplicate_win32_preserved_failed");count++;
            Dictionary<string,object> result=Result("self_test");result["assertions_passed"]=count;result["native_layouts_passed"]=true;result["token_policy_checks_passed"]=true;result["journal_rejection_checks_passed"]=true;result["token_diagnostic_schema_checks_passed"]=true;result["primary_conversion_checks_passed"]=true;return result;
        }
        public static int Main(string[] args) {
            try {
                if(args.Length==0||args.Length==1&&args[0]=="--plan"){Console.WriteLine(Json(Plan(null)));return 0;}
                if(args.Length==1&&args[0]=="--self-test"){Console.WriteLine(Json(SelfTest()));return 0;}
                if(args.Length==2&&args[0]=="--recovery-plan"){Console.WriteLine(Json(Plan(Guard.Attempt(args[1]))));return 0;}
                if(args.Length==2&&args[0]=="--apply-cli-appid-startup-synthetic")return Apply(args[1]);
                if(args.Length==2&&args[0]=="--recover-cli-appid-startup-synthetic")return Recover(Guard.Attempt(args[1]));
                throw new BoundaryError("invalid_arguments");
            }catch(Exception e){Dictionary<string,object> report=Result("rejected");Error(report,e,"candidate_failed");Console.WriteLine(Json(report));return 2;}
        }
    }
}
