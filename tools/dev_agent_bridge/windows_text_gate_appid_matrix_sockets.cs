// Bounded local-only socket fixtures. Actual calls are available only through an explicit host/runtime entry.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
using System.Text;

namespace HereIAm.R7 {
    public sealed class MatrixSocketFixtures : IDisposable {
        [DllImport("kernel32.dll")]static extern void GetSystemTimePreciseAsFileTime(out ulong value);
        public static ulong NowFileTime(){ulong value;GetSystemTimePreciseAsFileTime(out value);Need(value>0,"matrix_time_unavailable");return value;}
        sealed class Fixture {
            internal string Role, Marker, SetupStatus="unavailable";
            internal IPAddress Address;
            internal int Port;
            internal Socket Listener;
            internal Dictionary<string,object> EventProbe;
            internal readonly MatrixRow Row=new MatrixRow();
        }
        readonly List<Socket> owned=new List<Socket>();
        readonly Fixture[] fixtures=new Fixture[8];
        readonly int brokerPort;
        bool closeOk=true, disposed, completed, protocolOk, finalDrain;
        public bool Ready {get;private set;}
        public bool AllNegativeBlocked {get{return AllBlocked();}}
        public bool ZeroReceivesVerified {get{bool ok=completed&&protocolOk&&closeOk&&finalDrain;foreach(Fixture f in fixtures){MatrixRow r=f.Row;ok=ok&&f.EventProbe!=null&&r.Attempted&&r.FixtureAvailable&&r.LocalAddressVerified&&r.HostPositive&&r.HostDrainComplete&&r.ListenerDrainComplete&&r.AcceptedConnections==0&&r.ReceivedDatagrams==0&&r.ReceivedBytes==0;}return ok;}}
        static void Need(bool value,string code){Guard.Require(value,code);}
        static string Marker(){byte[] bytes=new byte[24];using(RandomNumberGenerator rng=RandomNumberGenerator.Create())rng.GetBytes(bytes);return BitConverter.ToString(bytes).Replace("-","").ToLowerInvariant();}
        static bool MarkerValid(object value){string text=value as string;if(text==null||text.Length!=48)return false;foreach(char c in text)if(!(c>='0'&&c<='9'||c>='a'&&c<='f'))return false;return true;}
        static bool ExactKeys(Dictionary<string,object> value,string keys){if(value==null)return false;string[] expected=keys.Split(',');if(value.Count!=expected.Length)return false;foreach(string key in expected)if(!value.ContainsKey(key))return false;return true;}
        static bool Number(object value,out int result){result=0;if(!(value is int)&&!(value is long))return false;long n=Convert.ToInt64(value);if(n<int.MinValue||n>int.MaxValue)return false;result=(int)n;return true;}
        static bool Pending(SocketException error){return error.ErrorCode==10035||error.ErrorCode==10036||error.ErrorCode==10037;}
        internal static IPAddress[] Inventory(){
            List<IPAddress> values=new List<IPAddress>();
            foreach(NetworkInterface nic in NetworkInterface.GetAllNetworkInterfaces()){
                if(nic.OperationalStatus!=OperationalStatus.Up)continue;
                foreach(UnicastIPAddressInformation info in nic.GetIPProperties().UnicastAddresses){
                    IPAddress ip=info.Address;
                    if(info.DuplicateAddressDetectionState!=DuplicateAddressDetectionState.Preferred||IPAddress.IsLoopback(ip))continue;
                    if(ip.AddressFamily!=AddressFamily.InterNetwork&&ip.AddressFamily!=AddressFamily.InterNetworkV6)continue;
                    bool exists=false;foreach(IPAddress prior in values)if(MatrixContract.SameAddress(ip,prior))exists=true;
                    if(!exists)values.Add(ip);
                    Need(values.Count<=64,"matrix_inventory_limit");
                }
            }
            return values.ToArray();
        }
        static Socket SocketFor(IPAddress address,bool tcp){
            return new Socket(address.AddressFamily,tcp?SocketType.Stream:SocketType.Dgram,tcp?ProtocolType.Tcp:ProtocolType.Udp);
        }
        // The caller owns the socket before any option or bind can fail.
        static void Configure(Socket socket,IPAddress address){socket.ExclusiveAddressUse=true;socket.Blocking=false;if(address.AddressFamily==AddressFamily.InterNetworkV6)socket.SetSocketOption(SocketOptionLevel.IPv6,SocketOptionName.IPv6Only,true);}
        Socket Own(Socket socket){owned.Add(socket);return socket;}
        bool Close(Socket socket){if(socket==null)return true;Need(owned.Contains(socket),"matrix_socket_unowned");try{socket.Close();owned.Remove(socket);return true;}catch{closeOk=false;return false;}}
        static bool IsTcp(string role){return role.EndsWith("_tcp",StringComparison.Ordinal);}
        static void ConnectPositive(Socket socket,IPEndPoint target){
            try{socket.Connect(target);}catch(SocketException error){if(!Pending(error))throw;Need(socket.Poll(1500000,SelectMode.SelectWrite)||socket.Poll(0,SelectMode.SelectError),"matrix_host_connect_timeout");Need((int)socket.GetSocketOption(SocketOptionLevel.Socket,SocketOptionName.Error)==0,"matrix_host_connect_failed");}
            Need(socket.Connected,"matrix_host_not_connected");
        }
        static void SendAll(Socket socket,byte[] bytes){
            int offset=0;Stopwatch time=Stopwatch.StartNew();
            while(offset<bytes.Length){Need(time.ElapsedMilliseconds<1500,"matrix_host_send_timeout");if(!socket.Poll(10000,SelectMode.SelectWrite))continue;int n=socket.Send(bytes,offset,bytes.Length-offset,SocketFlags.None);Need(n>0,"matrix_host_send_empty");offset+=n;}
        }
        static byte[] ReceiveExact(Socket socket,int length){
            byte[] bytes=new byte[length];int offset=0;Stopwatch time=Stopwatch.StartNew();
            while(offset<length){Need(time.ElapsedMilliseconds<1500,"matrix_host_receive_timeout");if(!socket.Poll(10000,SelectMode.SelectRead))continue;int n=socket.Receive(bytes,offset,length-offset,SocketFlags.None);Need(n>0,"matrix_host_receive_eof");offset+=n;}return bytes;
        }
        public MatrixSocketFixtures(int allowedBrokerPort){
            Need(allowedBrokerPort>=1&&allowedBrokerPort<=65535,"matrix_broker_port_rejected");brokerPort=allowedBrokerPort;
            for(int i=0;i<fixtures.Length;i++){fixtures[i]=new Fixture{Role=MatrixContract.Roles[i],Marker=Marker()};fixtures[i].Row.Role=fixtures[i].Role;}
            IPAddress[] inventory;try{inventory=Inventory();}catch{return;}
            for(int i=0;i<fixtures.Length;i++){
                Fixture fixture=fixtures[i];List<IPAddress> candidates=new List<IPAddress>();
                if(i<4)candidates.Add(i<2?IPAddress.Loopback:IPAddress.IPv6Loopback);else foreach(IPAddress ip in inventory)if(MatrixContract.TargetAllowed(fixture.Role,ip,1,inventory,brokerPort))candidates.Add(ip);
                foreach(IPAddress address in candidates){
                    if(!closeOk)break;
                    try{Prepare(fixture,address,inventory);break;}catch{fixture.SetupStatus="host_fixture_failed";fixture.Row.FixtureAvailable=false;fixture.Row.LocalAddressVerified=false;fixture.Row.HostPositive=false;fixture.Row.HostDrainComplete=false;Close(fixture.Listener);fixture.Listener=null;}
                }
            }
            Ready=closeOk;foreach(Fixture fixture in fixtures)Ready=Ready&&fixture.Row.FixtureAvailable&&fixture.Row.LocalAddressVerified&&fixture.Row.HostPositive&&fixture.Row.HostDrainComplete;
        }
        void Prepare(Fixture fixture,IPAddress address,IPAddress[] inventory){
            fixture.Address=address;bool tcp=IsTcp(fixture.Role);fixture.Listener=Own(SocketFor(address,tcp));Configure(fixture.Listener,address);fixture.Listener.Bind(new IPEndPoint(address,0));
            IPEndPoint actual=(IPEndPoint)fixture.Listener.LocalEndPoint;fixture.Port=actual.Port;
            Need(MatrixContract.SameAddress(address,actual.Address)&&MatrixContract.TargetAllowed(fixture.Role,address,actual.Port,inventory,brokerPort),"matrix_fixture_target_rejected");
            if(tcp)fixture.Listener.Listen(4);
            fixture.Row.FixtureAvailable=true;fixture.Row.LocalAddressVerified=true;
            Socket sender=null,accepted=null;bool positive=false;
            try{
                sender=Own(SocketFor(address,tcp));Configure(sender,address);sender.Bind(new IPEndPoint(address,0));byte[] marker=Encoding.ASCII.GetBytes("host:"+fixture.Marker);
                if(tcp){
                    ConnectPositive(sender,actual);SendAll(sender,marker);sender.Shutdown(SocketShutdown.Send);
                    Need(fixture.Listener.Poll(1500000,SelectMode.SelectRead),"matrix_host_accept_timeout");accepted=Own(fixture.Listener.Accept());accepted.Blocking=false;
                    Need(MatrixContract.SameAddress(((IPEndPoint)accepted.LocalEndPoint).Address,address)&&((IPEndPoint)accepted.LocalEndPoint).Port==fixture.Port,"matrix_host_local_tuple");
                    Need(((IPEndPoint)accepted.RemoteEndPoint).Equals(sender.LocalEndPoint),"matrix_host_remote_tuple");
                    byte[] got=ReceiveExact(accepted,marker.Length);Need(CoordinatorBoundary.SameBytes(marker,got),"matrix_host_marker_mismatch");
                    Need(accepted.Poll(1500000,SelectMode.SelectRead)&&accepted.Receive(new byte[1])==0,"matrix_host_eof_unconfirmed");
                }else{
                    Need(sender.SendTo(marker,actual)==marker.Length,"matrix_host_datagram_short");Need(fixture.Listener.Poll(1500000,SelectMode.SelectRead),"matrix_host_datagram_timeout");
                    byte[] bytes=new byte[256];EndPoint from=new IPEndPoint(address,0);int count=fixture.Listener.ReceiveFrom(bytes,ref from);
                    Need(from.Equals(sender.LocalEndPoint)&&count==marker.Length,"matrix_host_datagram_identity");for(int j=0;j<count;j++)Need(bytes[j]==marker[j],"matrix_host_datagram_mismatch");
                }
                positive=true;
            }finally{bool closed=Close(accepted)&Close(sender);positive=positive&&closed;}
            fixture.Row.HostPositive=positive;Need(positive,"matrix_positive_close_failed");
            fixture.Row.HostDrainComplete=Drain(fixture,150,false);Need(fixture.Row.HostDrainComplete,"matrix_host_drain_failed");fixture.SetupStatus="ready";
        }
        // Drain samples only held listener sockets; unknowns or extra traffic never become zero evidence.
        bool Drain(Fixture fixture,int quietMilliseconds,bool record){
            if(fixture.Listener==null)return false;bool complete=true;int accepted=0,datagrams=0,bytes=0;Stopwatch time=Stopwatch.StartNew();
            try{
                while(time.ElapsedMilliseconds<quietMilliseconds){
                    if(!fixture.Listener.Poll(10000,SelectMode.SelectRead))continue;
                    if(IsTcp(fixture.Role)){
                        Socket incoming=Own(fixture.Listener.Accept());accepted++;
                        try{incoming.Blocking=false;byte[] buffer=new byte[256];while(incoming.Poll(0,SelectMode.SelectRead)){int n=incoming.Receive(buffer);if(n==0)break;bytes+=n;if(bytes>65536){complete=false;break;}}}finally{if(!Close(incoming))complete=false;}
                    }else{byte[] buffer=new byte[65536];EndPoint from=new IPEndPoint(fixture.Address,0);bytes+=fixture.Listener.ReceiveFrom(buffer,ref from);datagrams++;}
                    if(accepted+datagrams>32||bytes>65536){complete=false;break;}
                }
            }catch{complete=false;}
            if(record){fixture.Row.AcceptedConnections+=accepted;fixture.Row.ReceivedDatagrams+=datagrams;fixture.Row.ReceivedBytes+=bytes;}
            return complete&&(!record?accepted+datagrams+bytes==0:true);
        }
        public Dictionary<string,object>[] Challenges(){
            Need(Ready&&!disposed&&!completed,"matrix_challenges_unavailable");Dictionary<string,object>[] values=new Dictionary<string,object>[8];
            for(int i=0;i<8;i++){Fixture f=fixtures[i];values[i]=new Dictionary<string,object>{{"role",f.Role},{"address",f.Address.ToString()},{"port",f.Port},{"marker",f.Marker}};}return values;
        }
        internal static bool ValidateOutcome(Dictionary<string,object> value,string role,string marker,out bool complete,out bool success,out int? error){
            complete=false;success=false;error=null;
            if(!ExactKeys(value,"role,marker,operation_completed,operation_succeeded,socket_error,local_address,local_port,remote_address,remote_port,ip_protocol,started_filetime,finished_filetime")||!Object.Equals(value["role"],role)||!Object.Equals(value["marker"],marker)||!(value["operation_completed"] is bool)||!(value["operation_succeeded"] is bool))return false;
            complete=(bool)value["operation_completed"];success=(bool)value["operation_succeeded"];int code;
            if(value["socket_error"]!=null){if(!Number(value["socket_error"],out code)||code<10000||code>11999)return false;error=code;}
            return !(success&&(!complete||error.HasValue))&&(complete?(success||error.HasValue):!success);
        }
        static bool FileTime(object value,out ulong result){result=0;string s=value as string;return s!=null&&UInt64.TryParse(s,out result)&&result>0&&result<=2650467743999999999UL&&result.ToString()==s;}
        internal static bool TryEventProbe(Dictionary<string,object> value,string role,IPAddress target,int port,out Dictionary<string,object> probe){
            probe=null;if(value==null||target==null||Array.IndexOf(MatrixContract.Roles,role)<0||port<1||port>65535)return false;
            foreach(string key in new string[]{"local_address","local_port","remote_address","remote_port","ip_protocol","started_filetime","finished_filetime"})if(!value.ContainsKey(key))return false;
            IPAddress local,remote;int localPort,remotePort,protocol;ulong start,end;string localText=value["local_address"] as string,remoteText=value["remote_address"] as string;
            if(!IPAddress.TryParse(localText,out local)||!IPAddress.TryParse(remoteText,out remote)||local.ToString()!=localText||remote.ToString()!=remoteText||!MatrixContract.SameAddress(local,target)||!MatrixContract.SameAddress(remote,target)||!Number(value["local_port"],out localPort)||localPort<1||localPort>65535||localPort==port||!Number(value["remote_port"],out remotePort)||remotePort!=port||!Number(value["ip_protocol"],out protocol)||protocol!=(IsTcp(role)?6:17)||!FileTime(value["started_filetime"],out start)||!FileTime(value["finished_filetime"],out end)||end<start||end-start>50000000UL)return false;
            probe=new Dictionary<string,object>{{"role",role},{"local_address",localText},{"local_port",localPort},{"remote_address",remoteText},{"remote_port",remotePort},{"ip_protocol",protocol},{"started_filetime",start.ToString()},{"finished_filetime",end.ToString()}};return true;
        }
        // Pure parent-window validation; no inventory/socket/native access. A missing probe never becomes drop evidence.
        public static bool ValidateProbeWindow(Dictionary<string,object> challenge,Dictionary<string,object> outcome,ulong beforeFileTime,ulong afterFileTime){
            if(!ExactKeys(challenge,"role,address,port,marker")||beforeFileTime==0||afterFileTime<beforeFileTime||afterFileTime-beforeFileTime>300000000UL)return false;
            bool complete,success;int? error;string role=challenge["role"] as string,marker=challenge["marker"] as string;int port;IPAddress target;Dictionary<string,object> probe;
            if(Array.IndexOf(MatrixContract.Roles,role)<0||!MarkerValid(marker)||!ValidateOutcome(outcome,role,marker,out complete,out success,out error)||!Number(challenge["port"],out port)||!IPAddress.TryParse(challenge["address"] as string,out target)||target.ToString()!=(challenge["address"] as string)||!TryEventProbe(outcome,role,target,port,out probe))return false;
            ulong start=UInt64.Parse((string)probe["started_filetime"]),end=UInt64.Parse((string)probe["finished_filetime"]);return start>=beforeFileTime&&end<=afterFileTime;
        }
        public Dictionary<string,object>[] EventProbes(){
            Need(completed&&protocolOk&&!disposed,"matrix_event_probes_unavailable");Dictionary<string,object>[] probes=new Dictionary<string,object>[8];for(int i=0;i<8;i++){Need(fixtures[i].EventProbe!=null,"matrix_event_probe_missing");probes[i]=new Dictionary<string,object>(fixtures[i].EventProbe);}return probes;
        }
        public bool Complete(object outcomes){
            Need(Ready&&!disposed&&!completed,"matrix_complete_state_rejected");completed=true;IList values=outcomes as IList;protocolOk=values!=null&&values.Count==8;
            for(int i=0;i<8;i++){
                Fixture f=fixtures[i];bool complete=false,success=false;int? error=null;
                bool valid=values!=null&&values.Count==8&&ValidateOutcome(values[i] as Dictionary<string,object>,f.Role,f.Marker,out complete,out success,out error);protocolOk=protocolOk&&valid;
                Dictionary<string,object> eventProbe=null;if(valid)TryEventProbe(values[i] as Dictionary<string,object>,f.Role,f.Address,f.Port,out eventProbe);f.EventProbe=eventProbe;
                f.Row.Attempted=valid;f.Row.ObservationComplete=valid&&complete;f.Row.SocketError=error.HasValue?error.Value:0;
                f.Row.Observation=success?(IsTcp(f.Role)?MatrixObservation.Connected:MatrixObservation.Sent):error==10013?MatrixObservation.AccessDenied:error==10060?MatrixObservation.Timeout:error==10061?MatrixObservation.Refused:MatrixObservation.OtherError;
                f.Row.ListenerDrainComplete=Drain(f,150,true);
            }
            return AllBlocked();
        }
        bool AllBlocked(){bool result=completed&&protocolOk&&closeOk&&finalDrain;foreach(Fixture f in fixtures)result=result&&MatrixContract.Outcome(f.Row,f.Role)=="blocked";return result;}
        public bool FinalizeNegativeResults(){return DrainVerified()&&AllBlocked();}
        public bool DrainVerified(){
            if(disposed)return finalDrain;bool all=closeOk;
            IPAddress[] inventory;try{inventory=Inventory();}catch{inventory=new IPAddress[0];all=false;}
            foreach(Fixture f in fixtures){bool local=MatrixContract.TargetAllowed(f.Role,f.Address,f.Port,inventory,brokerPort);f.Row.LocalAddressVerified=f.Row.LocalAddressVerified&&local;bool drained=Drain(f,150,true);f.Row.ListenerDrainComplete=f.Row.ListenerDrainComplete&&drained;all=all&&drained&&local;}
            finalDrain=all;return all;
        }
        public Dictionary<string,object>[] Rows(){
            Dictionary<string,object>[] rows=new Dictionary<string,object>[8];for(int i=0;i<8;i++){Fixture f=fixtures[i];MatrixRow r=f.Row;rows[i]=new Dictionary<string,object>{{"role",f.Role},{"fixture_status",f.SetupStatus},{"fixture_available",r.FixtureAvailable},{"local_address_verified",r.LocalAddressVerified},{"host_positive",r.HostPositive},{"host_drain_complete",r.HostDrainComplete},{"operation_completed",r.ObservationComplete},{"socket_error",r.SocketError==0?(object)null:r.SocketError},{"accepted_connections",r.AcceptedConnections},{"received_datagrams",r.ReceivedDatagrams},{"received_bytes",r.ReceivedBytes},{"listener_drain_complete",r.ListenerDrainComplete},{"outcome",MatrixContract.Outcome(r,f.Role)}};}return rows;
        }
        public bool CloseVerified(){disposed=true;for(int i=owned.Count-1;i>=0;i--)Close(owned[i]);return closeOk&&owned.Count==0;}
        public void Dispose(){CloseVerified();}
        public static Dictionary<string,object> Probe(Dictionary<string,object> challenge,int brokerPort){
            Need(ExactKeys(challenge,"role,address,port,marker")&&MarkerValid(challenge["marker"]),"matrix_probe_challenge_rejected");
            string role=challenge["role"] as string,addressText=challenge["address"] as string;int port;IPAddress address;
            Need(Number(challenge["port"],out port)&&IPAddress.TryParse(addressText,out address),"matrix_probe_endpoint_rejected");
            // Parse separately for definite assignment under Framework C# 5.
            address=IPAddress.Parse(addressText);Need(address.ToString()==addressText&&MatrixContract.TargetAllowed(role,address,port,Inventory(),brokerPort),"matrix_probe_nonlocal_target");
            Socket socket=null;bool complete=false,success=false,closed=true;int? error=null;IPEndPoint local=null;ulong start=0,end=0;
            try{
                // Socket setup errors, including a bind's 10013, are NOT evidence about Connect/SendTo.
                socket=SocketFor(address,IsTcp(role));Configure(socket,address);socket.Bind(new IPEndPoint(address,0));
                local=(IPEndPoint)socket.LocalEndPoint;Need(MatrixContract.SameAddress(local.Address,address)&&local.Port>0&&local.Port!=port,"matrix_probe_local_tuple_rejected");start=NowFileTime();
                try{if(IsTcp(role)){socket.Connect(new IPEndPoint(address,port));success=true;}else{byte[] marker=Encoding.ASCII.GetBytes("child:"+(string)challenge["marker"]);success=socket.SendTo(marker,new IPEndPoint(address,port))==marker.Length;}complete=success;}
                catch(SocketException operationError){complete=!Pending(operationError);error=operationError.ErrorCode;}
            }catch{complete=false;success=false;error=null;local=null;start=0;}
            finally{if(socket!=null)try{socket.Close();}catch{closed=false;}if(start>0)try{end=NowFileTime();}catch{closed=false;}}
            if(!closed){complete=false;success=false;error=null;}
            bool metadata=closed&&local!=null&&start>0&&end>=start&&end-start<=50000000UL;
            return new Dictionary<string,object>{{"role",role},{"marker",challenge["marker"]},{"operation_completed",complete},{"operation_succeeded",success},{"socket_error",error.HasValue?(object)error.Value:null},{"local_address",metadata?(object)local.Address.ToString():null},{"local_port",metadata?(object)local.Port:null},{"remote_address",metadata?(object)address.ToString():null},{"remote_port",metadata?(object)port:null},{"ip_protocol",metadata?(object)(IsTcp(role)?6:17):null},{"started_filetime",metadata?(object)start.ToString():null},{"finished_filetime",metadata?(object)end.ToString():null}};
        }
    }
}
