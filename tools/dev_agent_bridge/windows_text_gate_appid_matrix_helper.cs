// Contract-only candidate. No runtime matrix, native lifecycle, sockets or WFP mutations are wired.
// Joint compile immutable v10/v11c/v15 sources with /main:HereIAm.R7.MatrixProgram.
using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using System.Net;
using System.Net.Sockets;
using System.IO;
using System.Web.Script.Serialization;

namespace HereIAm.R7 {
    internal enum MatrixObservation { Unknown, AccessDenied, Connected, Sent, Timeout, Refused, OtherError }
    internal sealed class MatrixRow {
        internal string Role;
        internal bool FixtureAvailable, LocalAddressVerified, HostPositive, HostDrainComplete;
        internal bool Attempted, ObservationComplete, ListenerDrainComplete;
        internal MatrixObservation Observation;
        internal int SocketError, AcceptedConnections, ReceivedDatagrams, ReceivedBytes;
    }
    internal sealed class MatrixClosure {
        internal bool PreResumeBinding, PostProbePin, SameHeldChildSignaled, ExactChildBinding;
        internal bool JobQuerySucceeded, StdioEof, BrokerDrained, HelperActuallyClosed;
        internal bool ReceiptVerified, ExactRulesDeleted, PostCommitAbsent;
        internal uint JobActive;
    }
    internal static class MatrixContract {
        internal const string Root = @"D:\HereIAm-P6-R7-AppId-Matrix";
        internal const string Domain = "HereIAm.P6R7.AppIdMatrixV1/";
        internal const string JobPrefix = @"Local\HereIAm.P6R7.AppIdMatrixV1.";
        internal const string JournalSchema = "p6_r7_appid_matrix_owned_v1";
        internal const string ReceiptSchema = "p6_r7_appid_matrix_receipt_v1";
        internal static readonly string[] Roles = new string[]{"loopback4_tcp", "loopback4_udp", "loopback6_tcp", "loopback6_udp", "local4_tcp", "local4_udp", "local6_tcp", "local6_udp"};
        internal static Guid Scope(Guid attempt) {
            Guard.Require(attempt!=Guid.Empty,"matrix_attempt_rejected");
            using(SHA256 hash=SHA256.Create()) {
                byte[] bytes=hash.ComputeHash(Encoding.ASCII.GetBytes(Domain+attempt.ToString("N")));
                byte[] key=new byte[16];Array.Copy(bytes,key,16);Guid scope=new Guid(key);
                Guard.Require(scope!=Guid.Empty&&scope!=attempt,"matrix_scope_rejected");return scope;
            }
        }
        // A future native adapter must supply Scope(attempt), never attempt, to CoordinatorBoundary.
        internal static Rule[] Rules(Guid attempt,int brokerPort) { return CoordinatorBoundary.MakeRules(Scope(attempt),brokerPort); }
        internal static string DirectoryFor(Guid attempt) {Scope(attempt);return Path.Combine(Root,attempt.ToString("N"));}
        internal static string ImageFor(Guid attempt) {return Path.Combine(DirectoryFor(attempt),"matrix-probe.exe");}
        internal static bool SameAddress(IPAddress a,IPAddress b) {
            if(a==null||b==null||a.AddressFamily!=b.AddressFamily)return false;
            if(a.AddressFamily==AddressFamily.InterNetworkV6&&a.ScopeId!=b.ScopeId)return false;
            return CoordinatorBoundary.SameBytes(a.GetAddressBytes(),b.GetAddressBytes());
        }
        // Inventory is a bounded snapshot of local unicast interface addresses supplied by the future host.
        // This pure function neither resolves names nor obtains interfaces nor opens a socket.
        internal static bool TargetAllowed(string role,IPAddress target,int port,IPAddress[] inventory,int brokerPort) {
            int index=Array.IndexOf(Roles,role);if(index<0||target==null||port<1||port>65535||brokerPort<1||brokerPort>65535)return false;
            bool ipv6=index==2||index==3||index==6||index==7;
            if(target.AddressFamily!=(ipv6?AddressFamily.InterNetworkV6:AddressFamily.InterNetwork))return false;
            if(index<4)return SameAddress(target,ipv6?IPAddress.IPv6Loopback:IPAddress.Loopback)&&!(index==0&&port==brokerPort);
            if(inventory==null||inventory.Length==0||inventory.Length>64||IPAddress.IsLoopback(target))return false;
            byte[] bytes=target.GetAddressBytes();
            if(ipv6){if(target.IsIPv4MappedToIPv6||target.IsIPv6Multicast||SameAddress(target,IPAddress.IPv6Any)||target.IsIPv6LinkLocal&&target.ScopeId==0)return false;}
            else if(bytes[0]==0||bytes[0]>=224)return false;
            foreach(IPAddress local in inventory)if(SameAddress(target,local))return true;return false;
        }
        internal static string Outcome(MatrixRow row,string role) {
            if(Array.IndexOf(Roles,role)<0||row==null||row.Role!=role)return "invalid";
            if(!row.FixtureAvailable||!row.LocalAddressVerified||!row.HostPositive||!row.HostDrainComplete)return "incomplete";
            if(!row.Attempted||!row.ObservationComplete||!row.ListenerDrainComplete)return "incomplete";
            if(row.AcceptedConnections<0||row.ReceivedDatagrams<0||row.ReceivedBytes<0)return "invalid";
            if(row.AcceptedConnections!=0||row.ReceivedDatagrams!=0||row.ReceivedBytes!=0)return "not_blocked";
            if(row.Observation==MatrixObservation.Connected||row.Observation==MatrixObservation.Sent)return "not_blocked";
            // Only the synchronous socket operation's WSAEACCES is a narrow denial witness.
            // Timeouts, refusals, listener silence and arbitrary errors are never denial evidence.
            return row.Observation==MatrixObservation.AccessDenied&&row.SocketError==10013?"blocked":"incomplete";
        }
        internal static bool Closure(MatrixClosure value) {
            return value!=null&&value.PreResumeBinding&&value.PostProbePin&&value.SameHeldChildSignaled&&value.ExactChildBinding&&value.JobQuerySucceeded&&value.JobActive==0&&value.StdioEof&&value.BrokerDrained&&value.HelperActuallyClosed&&value.ReceiptVerified&&value.ExactRulesDeleted&&value.PostCommitAbsent;
        }
        internal static Dictionary<string,object> Summarize(MatrixRow[] rows,bool ownedPeerAdmitted,bool wrongPeerRejected,bool markerRoundTrip,MatrixClosure closure) {
            Dictionary<string,object> states=new Dictionary<string,object>();bool all=rows!=null&&rows.Length==Roles.Length;
            for(int i=0;i<Roles.Length;i++){string state=Outcome(rows!=null&&i<rows.Length?rows[i]:null,Roles[i]);states[Roles[i]]=state;all=all&&state=="blocked";}
            bool closed=Closure(closure);
            return new Dictionary<string,object>{{"diagnostic_only",true},{"role_outcomes",states},{"all_negative_roles_blocked",all},{"owned_peer_admitted",ownedPeerAdmitted},{"wrong_peer_rejected",wrongPeerRejected},{"fixed_marker_round_trip",markerRoundTrip},{"closure_evidence_complete",closed},{"evidence_contract_satisfied",all&&ownedPeerAdmitted&&wrongPeerRejected&&markerRoundTrip&&closed}};
        }
    }
    internal sealed class MatrixExpected {
        internal Guid Attempt;internal string Nonce,ImageHash,OwnerHash,OwnerTokenDigest,BlobDigest;
        internal uint OwnerPid;internal ulong OwnerCreation;internal int BrokerPort;
    }
    internal sealed class MatrixInstallFacts {
        internal bool OwnerLive,JobHeld,JobQuerySucceeded,InitialAbsence,TransactionExact,Committed,PostCommitExact,HelperClosed,ReceiptBound;
        internal int HelperExit;internal uint Active,Total;
        internal bool Accepted {get{return OwnerLive&&JobHeld&&JobQuerySucceeded&&Active==0&&Total==0&&InitialAbsence&&TransactionExact&&Committed&&PostCommitExact&&HelperClosed&&HelperExit==0&&ReceiptBound;}}
    }
    internal sealed class MatrixRollbackFacts {
        internal bool OwnerLive,JobHeld,JobQuerySucceeded,OriginalHelperClosed,NoChildBinding,ExactOwnedOrAbsent,PostAbsence,RollbackReceiptBound;
        internal string Phase;internal uint Active,Total;
        internal bool Clean {get{return Phase=="prepared"&&OwnerLive&&JobHeld&&JobQuerySucceeded&&Active==0&&Total==0&&OriginalHelperClosed&&NoChildBinding&&ExactOwnedOrAbsent&&PostAbsence&&RollbackReceiptBound;}}
    }
    internal static class MatrixRecords {
        static JavaScriptSerializer Serializer(){return new JavaScriptSerializer{MaxJsonLength=16384,RecursionLimit=5};}
        internal static string Json(object value){return Serializer().Serialize(value);}
        internal static Dictionary<string,object> Parse(string text){
            Guard.Require(text!=null&&text.Length<=16384,"matrix_record_size");
            Dictionary<string,object> value=Serializer().DeserializeObject(text) as Dictionary<string,object>;
            Guard.Require(value!=null&&Json(value)==text,"matrix_record_encoding");return value;
        }
        static void Require(bool value){Guard.Require(value,"matrix_record_rejected");}
        static void Keys(Dictionary<string,object> value,string list){string[] keys=list.Split(',');Require(value!=null&&value.Count==keys.Length);foreach(string key in keys)Require(value.ContainsKey(key));}
        static bool Hex(string value){if(value==null||value.Length!=64)return false;foreach(char c in value)if(!(c>='0'&&c<='9'||c>='a'&&c<='f'))return false;return true;}
        static uint Number(object value){Require(value is int||value is long);long n=Convert.ToInt64(value);Require(n>=0&&n<=UInt32.MaxValue);return (uint)n;}
        static ulong Time(object value){string text=value as string;ulong n;Require(text!=null&&UInt64.TryParse(text,out n));n=UInt64.Parse(text);Require(n>0&&n.ToString(System.Globalization.CultureInfo.InvariantCulture)==text);return n;}
        static void Expected(MatrixExpected expected){Require(expected!=null&&expected.Attempt!=Guid.Empty&&Hex(expected.Nonce)&&Hex(expected.ImageHash)&&Hex(expected.OwnerHash)&&expected.ImageHash==expected.OwnerHash&&Hex(expected.OwnerTokenDigest)&&Hex(expected.BlobDigest)&&expected.OwnerPid>0&&expected.OwnerCreation>0&&expected.BrokerPort>0&&expected.BrokerPort<=65535);}
        internal static Dictionary<string,object> Owned(MatrixExpected expected,string phase,uint? childPid,ulong? childCreated){
            Expected(expected);return new Dictionary<string,object>{{"schema",MatrixContract.JournalSchema},{"attempt_id",expected.Attempt.ToString("D")},{"scope_id",MatrixContract.Scope(expected.Attempt).ToString("D")},{"nonce",expected.Nonce},{"image_sha256",expected.ImageHash},{"coordinator_sha256",expected.OwnerHash},{"coordinator_pid",expected.OwnerPid},{"coordinator_creation",expected.OwnerCreation.ToString(System.Globalization.CultureInfo.InvariantCulture)},{"coordinator_token_digest",expected.OwnerTokenDigest},{"broker_port",expected.BrokerPort},{"phase",phase},{"child_pid",childPid.HasValue?(object)childPid.Value:null},{"child_creation",childCreated.HasValue?(object)childCreated.Value.ToString(System.Globalization.CultureInfo.InvariantCulture):null},{"child_token_digest",childPid.HasValue?(object)expected.OwnerTokenDigest:null}};
        }
        internal static Dictionary<string,object> ValidateOwned(string text,MatrixExpected expected){
            Expected(expected);Dictionary<string,object> v=Parse(text);Keys(v,"schema,attempt_id,scope_id,nonce,image_sha256,coordinator_sha256,coordinator_pid,coordinator_creation,coordinator_token_digest,broker_port,phase,child_pid,child_creation,child_token_digest");
            Require(Object.Equals(v["schema"],MatrixContract.JournalSchema)&&Object.Equals(v["attempt_id"],expected.Attempt.ToString("D"))&&Object.Equals(v["scope_id"],MatrixContract.Scope(expected.Attempt).ToString("D"))&&Object.Equals(v["nonce"],expected.Nonce)&&Object.Equals(v["image_sha256"],expected.ImageHash)&&Object.Equals(v["coordinator_sha256"],expected.OwnerHash)&&Number(v["coordinator_pid"])==expected.OwnerPid&&Time(v["coordinator_creation"])==expected.OwnerCreation&&Object.Equals(v["coordinator_token_digest"],expected.OwnerTokenDigest)&&Number(v["broker_port"])==expected.BrokerPort);
            string phase=v["phase"] as string;Require(phase=="prepared"||phase=="spawning"||phase=="bound"||phase=="closed");
            if(phase=="prepared"||phase=="spawning")Require(v["child_pid"]==null&&v["child_creation"]==null&&v["child_token_digest"]==null);
            else Require(v["child_pid"]!=null&&Number(v["child_pid"])>0&&Number(v["child_pid"])!=expected.OwnerPid&&Time(v["child_creation"])>0&&Object.Equals(v["child_token_digest"],expected.OwnerTokenDigest));return v;
        }
        internal static Dictionary<string,object> Receipt(MatrixExpected expected,Dictionary<string,object> journal,string action,uint helperPid,ulong helperCreation,ushort? assignedWeight){
            return new Dictionary<string,object>{{"schema",MatrixContract.ReceiptSchema},{"attempt_id",expected.Attempt.ToString("D")},{"scope_id",MatrixContract.Scope(expected.Attempt).ToString("D")},{"nonce",expected.Nonce},{"action",action},{"coordinator_pid",expected.OwnerPid},{"coordinator_creation",expected.OwnerCreation.ToString(System.Globalization.CultureInfo.InvariantCulture)},{"coordinator_sha256",expected.OwnerHash},{"coordinator_token_digest",expected.OwnerTokenDigest},{"image_sha256",expected.ImageHash},{"appid_blob_digest",expected.BlobDigest},{"helper_pid",helperPid},{"helper_creation",helperCreation.ToString(System.Globalization.CultureInfo.InvariantCulture)},{"helper_sha256",expected.OwnerHash},{"assigned_sublayer_weight",assignedWeight.HasValue?(object)assignedWeight.Value:null},{"phase",journal["phase"]},{"child_pid",journal["child_pid"]},{"child_creation",journal["child_creation"]},{"child_token_digest",journal["child_token_digest"]}};
        }
        internal static void ValidateReceipt(string text,MatrixExpected expected,Dictionary<string,object> journal,string action,uint helperPid,ulong helperCreation,ushort? assignedWeight){
            Expected(expected);ValidateOwned(Json(journal),expected);Require(helperPid>0&&helperPid!=expected.OwnerPid&&helperCreation>0);
            Require(action=="install"||action=="cleanup"||action=="install_rollback");
            Require(action=="cleanup"?Object.Equals(journal["phase"],"closed"):Object.Equals(journal["phase"],"prepared"));
            Require(action=="install_rollback"||assignedWeight.HasValue);
            Dictionary<string,object> value=Parse(text),want=Receipt(expected,journal,action,helperPid,helperCreation,assignedWeight);
            Keys(value,"schema,attempt_id,scope_id,nonce,action,coordinator_pid,coordinator_creation,coordinator_sha256,coordinator_token_digest,image_sha256,appid_blob_digest,helper_pid,helper_creation,helper_sha256,assigned_sublayer_weight,phase,child_pid,child_creation,child_token_digest");
            // Canonical serialization compares types and every fixed binding; a missing/null old weight is never accepted.
            Require(Json(value)==Json(want));
        }
    }
    public static class MatrixProgram {
        static Dictionary<string,object> Report(string mode) {
            return new Dictionary<string,object>{{"schema","p6_r7_appid_matrix_contract_candidate_v1"},{"mode",mode},{"runtime_implemented",false},{"system_mutation_requested",false},{"matrix_passed",false},{"network_enforcement_tested",false},{"single_process_enforcement_tested",false},{"production_isolation_passed",false},{"human_gate_passed",false},{"real_upstream_requests",0},{"model_turns_requested",0}};
        }
        static int count;
        static void Check(bool value){if(!value)throw new BoundaryError("matrix_self_test_failed");count++;}
        static void Reject(Action action){bool rejected=false;try{action();}catch{rejected=true;}Check(rejected);}
        static MatrixRow Good(string role) {return new MatrixRow{Role=role,FixtureAvailable=true,LocalAddressVerified=true,HostPositive=true,HostDrainComplete=true,Attempted=true,ObservationComplete=true,ListenerDrainComplete=true,Observation=MatrixObservation.AccessDenied,SocketError=10013,AcceptedConnections=0,ReceivedDatagrams=0,ReceivedBytes=0};}
        static MatrixClosure Closed(){return new MatrixClosure{PreResumeBinding=true,PostProbePin=true,SameHeldChildSignaled=true,ExactChildBinding=true,JobQuerySucceeded=true,StdioEof=true,BrokerDrained=true,HelperActuallyClosed=true,ReceiptVerified=true,ExactRulesDeleted=true,PostCommitAbsent=true};}
        static Dictionary<string,object> SelfTest() {
            count=0;Guid id=new Guid("6a0c0e4e-2f9d-4efd-93d0-54971cfc0af3"),other=new Guid("4c7a426c-f5ed-43eb-8520-d9dc8361dc21");
            Check(MatrixContract.Scope(id)==MatrixContract.Scope(id));Check(MatrixContract.Scope(id)!=id);Check(MatrixContract.Scope(id)!=MatrixContract.Scope(other));
            bool rejected=false;try{MatrixContract.Scope(Guid.Empty);}catch(BoundaryError){rejected=true;}Check(rejected);
            Rule[] rules=MatrixContract.Rules(id,45678),normal=CoordinatorBoundary.MakeRules(id,45678);
            Check(rules.Length==3&&rules[0].Permit&&rules[0].Port==45678&&rules[0].Weight==15&&!rules[1].Permit&&!rules[2].Permit);
            foreach(Rule rule in rules)foreach(Rule original in normal)Check(rule.Key!=original.Key);
            foreach(int invalid in new int[]{-1,0,65536}){rejected=false;try{MatrixContract.Rules(id,invalid);}catch(BoundaryError){rejected=true;}Check(rejected);}
            InspectionNative.Layouts();CoordinatorJobNative.Layouts();Check(true);
            MatrixRow[] rows=new MatrixRow[MatrixContract.Roles.Length];for(int i=0;i<rows.Length;i++){rows[i]=Good(MatrixContract.Roles[i]);Check(MatrixContract.Outcome(rows[i],MatrixContract.Roles[i])=="blocked");}
            Check((bool)MatrixContract.Summarize(rows,true,true,true,Closed())["evidence_contract_satisfied"]);
            foreach(MatrixObservation observation in new MatrixObservation[]{MatrixObservation.Unknown,MatrixObservation.Timeout,MatrixObservation.Refused,MatrixObservation.OtherError,MatrixObservation.Connected,MatrixObservation.Sent}){MatrixRow row=Good("loopback4_tcp");row.Observation=observation;Check(MatrixContract.Outcome(row,row.Role)!="blocked");}
            foreach(int error in new int[]{0,5,10060,10061,-1,10014}){MatrixRow row=Good("loopback4_tcp");row.SocketError=error;Check(MatrixContract.Outcome(row,row.Role)=="incomplete");}
            foreach(string field in new string[]{"FixtureAvailable","LocalAddressVerified","HostPositive","HostDrainComplete","Attempted","ObservationComplete","ListenerDrainComplete"}){MatrixRow row=Good("loopback4_tcp");typeof(MatrixRow).GetField(field,System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.NonPublic).SetValue(row,false);Check(MatrixContract.Outcome(row,row.Role)!="blocked");}
            foreach(string field in new string[]{"AcceptedConnections","ReceivedDatagrams","ReceivedBytes"})foreach(int value in new int[]{-1,1}){MatrixRow row=Good("loopback4_tcp");typeof(MatrixRow).GetField(field,System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.NonPublic).SetValue(row,value);Check(MatrixContract.Outcome(row,row.Role)!="blocked");}
            Check(MatrixContract.Outcome(Good("PRIVATE"),"loopback4_tcp")=="invalid");Check(MatrixContract.Outcome(null,"loopback4_tcp")=="invalid");
            MatrixRow[] duplicate=(MatrixRow[])rows.Clone();duplicate[7]=Good(MatrixContract.Roles[0]);Check(!(bool)MatrixContract.Summarize(duplicate,true,true,true,Closed())["evidence_contract_satisfied"]);
            Check(!(bool)MatrixContract.Summarize(null,true,true,true,Closed())["evidence_contract_satisfied"]);
            foreach(string field in new string[]{"PreResumeBinding","PostProbePin","SameHeldChildSignaled","ExactChildBinding","JobQuerySucceeded","StdioEof","BrokerDrained","HelperActuallyClosed","ReceiptVerified","ExactRulesDeleted","PostCommitAbsent"}){MatrixClosure closure=Closed();typeof(MatrixClosure).GetField(field,System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.NonPublic).SetValue(closure,false);Check(!MatrixContract.Closure(closure));}
            MatrixClosure active=Closed();active.JobActive=1;Check(!MatrixContract.Closure(active));Check(!MatrixContract.Closure(null));
            Check(!(bool)MatrixContract.Summarize(rows,false,true,true,Closed())["evidence_contract_satisfied"]);Check(!(bool)MatrixContract.Summarize(rows,true,false,true,Closed())["evidence_contract_satisfied"]);Check(!(bool)MatrixContract.Summarize(rows,true,true,false,Closed())["evidence_contract_satisfied"]);
            string json=AppIdProgram.Json(MatrixContract.Summarize(new MatrixRow[]{Good("PRIVATE")},false,false,false,null));Check(!json.Contains("PRIVATE"));
            Check(MatrixContract.ImageFor(id)==MatrixContract.Root+"\\"+id.ToString("N")+"\\matrix-probe.exe");
            IPAddress local4=IPAddress.Parse("192.0.2.10"),local6=IPAddress.Parse("2001:db8::10");IPAddress[] inventory=new IPAddress[]{local4,local6};
            foreach(string role in MatrixContract.Roles){bool ipv6=role.Contains("6");IPAddress target=role.StartsWith("loopback")?(ipv6?IPAddress.IPv6Loopback:IPAddress.Loopback):(ipv6?local6:local4);Check(MatrixContract.TargetAllowed(role,target,45679,inventory,45678));Check(!MatrixContract.TargetAllowed(role,target,0,inventory,45678));Check(!MatrixContract.TargetAllowed(role,ipv6?local4:local6,45679,inventory,45678));}
            Check(!MatrixContract.TargetAllowed("loopback4_tcp",IPAddress.Loopback,45678,inventory,45678));Check(MatrixContract.TargetAllowed("loopback4_udp",IPAddress.Loopback,45678,inventory,45678));
            foreach(string role in new string[]{"local4_tcp","local4_udp"})foreach(string address in new string[]{"203.0.113.10","0.0.0.0","224.0.0.1","255.255.255.255","127.0.0.1"})Check(!MatrixContract.TargetAllowed(role,IPAddress.Parse(address),45679,inventory,45678));
            foreach(string address in new string[]{"::","ff02::1","::ffff:192.0.2.10","fe80::1","2001:db8::99"})Check(!MatrixContract.TargetAllowed("local6_tcp",IPAddress.Parse(address),45679,inventory,45678));
            Check(!MatrixContract.TargetAllowed("local4_tcp",local4,45679,null,45678));Check(!MatrixContract.TargetAllowed("local4_tcp",local4,45679,new IPAddress[65],45678));Check(!MatrixContract.TargetAllowed("PRIVATE",local4,45679,inventory,45678));
            IPAddress linkA=IPAddress.Parse("fe80::1%7"),linkB=IPAddress.Parse("fe80::1%8");Check(MatrixContract.TargetAllowed("local6_udp",linkA,45679,new IPAddress[]{linkA},45678));Check(!MatrixContract.TargetAllowed("local6_udp",linkA,45679,new IPAddress[]{linkB},45678));
            MatrixExpected expected=new MatrixExpected{Attempt=id,Nonce=new string('a',64),ImageHash=new string('b',64),OwnerHash=new string('b',64),OwnerTokenDigest=new string('c',64),BlobDigest=new string('d',64),OwnerPid=101,OwnerCreation=202,BrokerPort=45678};
            Dictionary<string,object> prepared=MatrixRecords.ValidateOwned(MatrixRecords.Json(MatrixRecords.Owned(expected,"prepared",null,null)),expected);
            Dictionary<string,object> bound=MatrixRecords.ValidateOwned(MatrixRecords.Json(MatrixRecords.Owned(expected,"bound",303,404)),expected);
            Dictionary<string,object> closed=MatrixRecords.ValidateOwned(MatrixRecords.Json(MatrixRecords.Owned(expected,"closed",303,404)),expected);Check(true);
            foreach(string phase in new string[]{"prepared","spawning"})Reject(delegate{MatrixRecords.ValidateOwned(MatrixRecords.Json(MatrixRecords.Owned(expected,phase,303,404)),expected);});
            foreach(string phase in new string[]{"bound","closed","PRIVATE"})Reject(delegate{MatrixRecords.ValidateOwned(MatrixRecords.Json(MatrixRecords.Owned(expected,phase,null,null)),expected);});
            foreach(string key in new List<string>(prepared.Keys)){Dictionary<string,object> bad=new Dictionary<string,object>(prepared);bad.Remove(key);Reject(delegate{MatrixRecords.ValidateOwned(MatrixRecords.Json(bad),expected);});}
            foreach(string key in new string[]{"schema","attempt_id","scope_id","nonce","image_sha256","coordinator_sha256","coordinator_pid","coordinator_creation","coordinator_token_digest","broker_port","phase"}){Dictionary<string,object> bad=new Dictionary<string,object>(prepared);bad[key]="PRIVATE";Reject(delegate{MatrixRecords.ValidateOwned(MatrixRecords.Json(bad),expected);});}
            Dictionary<string,object> extraKey=new Dictionary<string,object>(prepared);extraKey["PRIVATE"]=true;Reject(delegate{MatrixRecords.ValidateOwned(MatrixRecords.Json(extraKey),expected);});
            string canonical=MatrixRecords.Json(prepared);Reject(delegate{MatrixRecords.ValidateOwned(canonical+" ",expected);});Reject(delegate{MatrixRecords.ValidateOwned("{\"schema\":\"PRIVATE\","+canonical.Substring(1),expected);});Reject(delegate{MatrixRecords.ValidateOwned(new string('x',16385),expected);});
            foreach(string action in new string[]{"install","cleanup","install_rollback"}){Dictionary<string,object> journal=action=="cleanup"?closed:prepared;ushort? weight=action=="install_rollback"?(ushort?)null:(ushort)32766;string receipt=MatrixRecords.Json(MatrixRecords.Receipt(expected,journal,action,505,606,weight));MatrixRecords.ValidateReceipt(receipt,expected,journal,action,505,606,weight);Check(true);
                Dictionary<string,object> parsed=MatrixRecords.Parse(receipt);foreach(string key in new List<string>(parsed.Keys)){Dictionary<string,object> bad=new Dictionary<string,object>(parsed);bad.Remove(key);Reject(delegate{MatrixRecords.ValidateReceipt(MatrixRecords.Json(bad),expected,journal,action,505,606,weight);});}
                foreach(string key in new List<string>(parsed.Keys)){Dictionary<string,object> bad=new Dictionary<string,object>(parsed);bad[key]="PRIVATE";Reject(delegate{MatrixRecords.ValidateReceipt(MatrixRecords.Json(bad),expected,journal,action,505,606,weight);});}
            }
            string installed=MatrixRecords.Json(MatrixRecords.Receipt(expected,prepared,"install",505,606,32766));
            Reject(delegate{MatrixRecords.ValidateReceipt(installed,expected,prepared,"install",505,606,32767);});Reject(delegate{MatrixRecords.ValidateReceipt(installed,expected,prepared,"install",505,606,null);});Reject(delegate{MatrixRecords.ValidateReceipt(installed,expected,prepared,"install",101,606,32766);});Reject(delegate{MatrixRecords.ValidateReceipt(installed,expected,bound,"cleanup",505,606,32766);});Reject(delegate{MatrixRecords.ValidateReceipt(installed,expected,prepared,"cleanup",505,606,32766);});
            MatrixInstallFacts ready=new MatrixInstallFacts{OwnerLive=true,JobHeld=true,JobQuerySucceeded=true,InitialAbsence=true,TransactionExact=true,Committed=true,PostCommitExact=true,HelperClosed=true,ReceiptBound=true,HelperExit=0,Active=0,Total=0};Check(ready.Accepted);
            foreach(System.Reflection.FieldInfo field in typeof(MatrixInstallFacts).GetFields(System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.NonPublic)){object previous=field.GetValue(ready);field.SetValue(ready,field.FieldType==typeof(bool)?(object)false:field.FieldType==typeof(uint)?(object)(uint)1:(object)1);Check(!ready.Accepted);field.SetValue(ready,previous);}
            MatrixRollbackFacts rollback=new MatrixRollbackFacts{Phase="prepared",OwnerLive=true,JobHeld=true,JobQuerySucceeded=true,OriginalHelperClosed=true,NoChildBinding=true,ExactOwnedOrAbsent=true,PostAbsence=true,RollbackReceiptBound=true,Active=0,Total=0};Check(rollback.Clean);
            foreach(System.Reflection.FieldInfo field in typeof(MatrixRollbackFacts).GetFields(System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.NonPublic)){object previous=field.GetValue(rollback);field.SetValue(rollback,field.FieldType==typeof(bool)?(object)false:field.FieldType==typeof(string)?(object)"spawning":(object)(uint)1);Check(!rollback.Clean);field.SetValue(rollback,previous);}
            Dictionary<string,object> report=Report("self_test");report["assertions_passed"]=count;report["native_layouts_passed"]=true;return report;
        }
        [STAThread] public static int Main(string[] args) {
            try{
                if(args.Length==0||args.Length==1&&args[0]=="--plan"){Dictionary<string,object> plan=Report("plan");plan["negative_roles"]=MatrixContract.Roles;plan["runtime_status"]="not_implemented";Console.WriteLine(AppIdProgram.Json(plan));return 0;}
                if(args.Length==1&&args[0]=="--self-test"){Console.WriteLine(AppIdProgram.Json(SelfTest()));return 0;}
                throw new BoundaryError("matrix_runtime_not_implemented");
            }catch(Exception){Dictionary<string,object> report=Report("rejected");report["error_code"]="matrix_candidate_rejected";Console.WriteLine(AppIdProgram.Json(report));return 2;}
        }
    }
}
