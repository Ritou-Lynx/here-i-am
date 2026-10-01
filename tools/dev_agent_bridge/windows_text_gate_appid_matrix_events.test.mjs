import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,realpathSync,rmSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const local=name=>fileURLToPath(new URL(name,import.meta.url));
const source=local('./windows_text_gate_appid_matrix_events.cs'),code=readFileSync(source,'utf8');
const deps=[local('./windows_text_gate_isolation_helper.cs'),local('./windows_text_gate_appid_startup_helper.cs'),local('../../tmp/p6-r7-review/native-appid-coordinator-candidate-15.cs'),local('../../tmp/p6-r7-review/native-appid-matrix-contract-01.cs'),local('./windows_text_gate_appid_matrix_native.cs')];
const pins=['d22017641d9f8df750f6db7db9319b8c1930a726a8575ff1ffabfde0d5ffdcd8','c777023495ccdbf3b52663f49683f5d84dcfd03a36b3d280a75c925f37b7a1ea','c1f07e9487b8ce25d0acc2d5bbb03b69c975cbb7e448698d288ff6263cff9311','f70ffb86ce5efea2572532e1986f77dde9622893ad4b90a74f9ec40da5ba6774','f2d3b35a1e6d1763930ba7f9a82ab8dbb595e02d5d720216a0161dbce8a0d0ab'];
const hash=file=>createHash('sha256').update(readFileSync(file)).digest('hex');
const csc=String.raw`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`;
const harness=String.raw`
using System;using System.Collections.Generic;using System.Net;using System.Reflection;
namespace HereIAm.R7 {public static class MatrixEventsPureHarness {
 static int checks;static void Check(bool value){if(!value)throw new Exception("pure_assertion_failed_"+checks);checks++;}static void Reject(Action a){bool failed=false;try{a();}catch{failed=true;}Check(failed);}
 static byte[] App=new byte[]{1,2,3};static ulong BaseTime=133000000000000000;
 static MatrixExpected Expected(){return new MatrixExpected{Attempt=new Guid("11111111-2222-4333-8444-555555555555"),Nonce=new string('a',64),ImageHash=new string('b',64),OwnerHash=new string('b',64),OwnerTokenDigest=new string('c',64),BlobDigest=MatrixNetEvents.HashBytes(App),OwnerPid=123,OwnerCreation=BaseTime-1000,BrokerPort=43000};}
 static Dictionary<string,object> Binding(MatrixExpected e){return new Dictionary<string,object>{{"schema",MatrixNetEvents.BindingSchema},{"attempt_id",e.Attempt.ToString("D")},{"scope_id",MatrixContract.Scope(e.Attempt).ToString("D")},{"nonce",e.Nonce},{"image_sha256",e.ImageHash},{"appid_blob_sha256",e.BlobDigest},{"assigned_weight",(ushort)32765},{"deny4_filter_id","1001"},{"deny6_filter_id","1002"},{"deny4_layer_id",(ushort)48},{"deny6_layer_id",(ushort)49}};}
 static Dictionary<string,object>[] ProbeInput(){Dictionary<string,object>[] rows=new Dictionary<string,object>[8];for(int i=0;i<8;i++){bool six=i==2||i==3||i==6||i==7;string addr=i<4?(six?"::1":"127.0.0.1"):(six?"fe80::1234%7":"192.0.2.7");rows[i]=new Dictionary<string,object>{{"role",MatrixContract.Roles[i]},{"local_address",addr},{"local_port",44000+i},{"remote_address",addr},{"remote_port",45000+i},{"ip_protocol",i%2==0?6:17},{"started_filetime",(BaseTime+(ulong)i*1000).ToString()},{"finished_filetime",(BaseTime+(ulong)i*1000+500).ToString()}};}return rows;}
 static byte[] RawAddress(IPAddress addr){byte[] bytes=addr.GetAddressBytes();if(bytes.Length==16)return bytes;uint v=(uint)(bytes[0]<<24|bytes[1]<<16|bytes[2]<<8|bytes[3]);byte[] raw=new byte[16];Array.Copy(BitConverter.GetBytes(v),raw,4);return raw;}
 static MatrixDropObservation Good(MatrixEventProbe p){bool six=p.Local.GetAddressBytes().Length==16;return new MatrixDropObservation{Timestamp=p.Start,Flags=0x1bf,Version=six?1u:0u,Protocol=p.Protocol,Scope=six?(uint)p.Local.ScopeId:0,LocalAddress=RawAddress(p.Local),RemoteAddress=RawAddress(p.Remote),LocalPort=p.LocalPort,RemotePort=p.RemotePort,FilterId=six?1002UL:1001UL,LayerId=six?(ushort)49:(ushort)48,AppId=(byte[])App.Clone()};}
 static Dictionary<string,object> Capture(MatrixExpected e,object probes,Dictionary<string,object> binding){Dictionary<string,object>[] roles=new Dictionary<string,object>[8];for(int i=0;i<8;i++)roles[i]=new Dictionary<string,object>{{"role",MatrixContract.Roles[i]},{"matched",true},{"matched_count",1}};return new Dictionary<string,object>{{"schema",MatrixNetEvents.CaptureSchema},{"attempt_id",e.Attempt.ToString("D")},{"nonce",e.Nonce},{"binding_sha256",MatrixNetEvents.Hash(binding)},{"probes_sha256",MatrixNetEvents.Hash(probes)},{"capture_complete",true},{"all_roles_matched",true},{"collection_enabled",true},{"enumeration_exhausted",true},{"resources_closed",true},{"error_code",0},{"api_status",null},{"roles",roles}};}
 static void Put(byte[] bytes,int offset,byte[] value){Array.Copy(value,0,bytes,offset,value.Length);}
 public static int Main(){MatrixEventNative.Layouts();Check(true);MatrixExpected e=Expected();Dictionary<string,object> b=Binding(e);MatrixNetEvents.ValidateBinding(e,32765,b);Check(true);
  foreach(string key in new List<string>(b.Keys)){Dictionary<string,object> bad=new Dictionary<string,object>(b);bad.Remove(key);Reject(delegate{MatrixNetEvents.ValidateBinding(e,32765,bad);});}
  foreach(string key in new List<string>(b.Keys)){Dictionary<string,object> bad=new Dictionary<string,object>(b);bad[key]="untrusted";Reject(delegate{MatrixNetEvents.ValidateBinding(e,32765,bad);});}
  Dictionary<string,object>[] input=ProbeInput();MatrixEventProbe[] probes=MatrixNetEvents.Probes(e,input);Check(probes.Length==8);foreach(MatrixEventProbe p in probes){MatrixDropObservation good=Good(p);Check(MatrixNetEvents.Matches(good,p,b,App));foreach(uint flag in new uint[]{1,2,4,8,16,32,256}){MatrixDropObservation bad=Good(p);bad.Flags&=~flag;Check(!MatrixNetEvents.Matches(bad,p,b,App));}foreach(string field in new string[]{"Timestamp","FilterId","Flags","Version","Scope","Protocol","LocalPort","RemotePort","LayerId","LocalAddress","RemoteAddress","AppId"}){MatrixDropObservation bad=Good(p);FieldInfo f=typeof(MatrixDropObservation).GetField(field);if(f.FieldType==typeof(byte[]))f.SetValue(bad,new byte[0]);else if(f.FieldType==typeof(ulong))f.SetValue(bad,UInt64.MaxValue);else if(f.FieldType==typeof(uint))f.SetValue(bad,field=="Flags"?0u:UInt32.MaxValue);else if(f.FieldType==typeof(byte))f.SetValue(bad,(byte)255);else f.SetValue(bad,UInt16.MaxValue);Check(!MatrixNetEvents.Matches(bad,p,b,App));}}
  MatrixDropObservation reverse=Good(probes[0]);Array.Reverse(reverse.LocalAddress,0,4);Check(!MatrixNetEvents.Matches(reverse,probes[0],b,App));MatrixDropObservation reversePort=Good(probes[0]);reversePort.RemotePort=(ushort)((reversePort.RemotePort>>8)|(reversePort.RemotePort<<8));Check(!MatrixNetEvents.Matches(reversePort,probes[0],b,App));
  MatrixDropObservation scoped=Good(probes[6]);scoped.Flags&=~0x80u;Check(!MatrixNetEvents.Matches(scoped,probes[6],b,App));
  foreach(string key in new List<string>(input[0].Keys)){Dictionary<string,object>[] bad=ProbeInput();bad[0].Remove(key);Reject(delegate{MatrixNetEvents.Probes(e,bad);});}
  foreach(string key in new List<string>(input[0].Keys)){Dictionary<string,object>[] bad=ProbeInput();bad[0][key]="untrusted";Reject(delegate{MatrixNetEvents.Probes(e,bad);});}
  Reject(delegate{MatrixNetEvents.Probes(e,null);});Reject(delegate{MatrixNetEvents.Probes(e,new object[7]);});Dictionary<string,object>[] interval=ProbeInput();interval[0]["finished_filetime"]=(BaseTime-1).ToString();Reject(delegate{MatrixNetEvents.Probes(e,interval);});
  Dictionary<string,object> c=Capture(e,input,b);Check(MatrixNetEvents.ValidateCapture(e,32765,b,input,c));foreach(string key in new List<string>(c.Keys)){Dictionary<string,object> bad=new Dictionary<string,object>(c);bad.Remove(key);Reject(delegate{MatrixNetEvents.ValidateCapture(e,32765,b,input,bad);});}
  foreach(string key in new string[]{"capture_complete","all_roles_matched","collection_enabled","enumeration_exhausted","resources_closed"}){Dictionary<string,object> bad=Capture(e,input,b);bad[key]=false;Reject(delegate{MatrixNetEvents.ValidateCapture(e,32765,b,input,bad);});}
  Dictionary<string,object> incomplete=Capture(e,input,b);incomplete["capture_complete"]=false;incomplete["all_roles_matched"]=false;incomplete["error_code"]=5;incomplete["enumeration_exhausted"]=false;Check(!MatrixNetEvents.ValidateCapture(e,32765,b,input,incomplete));
  Dictionary<string,object> summary=MatrixNetEvents.SafeSummary(e,32765,b,input,incomplete);Check(summary.Count==6&&Object.Equals(summary["error_stage"],5));Check(!MatrixRecords.Json(summary).Contains(e.Nonce)&&!MatrixRecords.Json(summary).Contains("local_address"));incomplete["api_status"]=0x80320013u;Check(!MatrixNetEvents.ValidateCapture(e,32765,b,input,incomplete));Check(Object.Equals(MatrixNetEvents.SafeSummary(e,32765,b,input,incomplete)["api_status"],0x80320013u));
  foreach(object value in new object[]{0,-1,"0x80320013",UInt64.MaxValue}){Dictionary<string,object> bad=new Dictionary<string,object>(incomplete);bad["api_status"]=value;Reject(delegate{MatrixNetEvents.SafeSummary(e,32765,b,input,bad);});}
  Dictionary<string,object> apiOnSuccess=Capture(e,input,b);apiOnSuccess["api_status"]=1u;Reject(delegate{MatrixNetEvents.ValidateCapture(e,32765,b,input,apiOnSuccess);});
  Dictionary<string,object>[] stale=ProbeInput();stale[0]["started_filetime"]=(e.OwnerCreation-1).ToString();Reject(delegate{MatrixNetEvents.Probes(e,stale);});
  Dictionary<string,object> excessive=Capture(e,input,b);foreach(Dictionary<string,object> row in (Dictionary<string,object>[])excessive["roles"])row["matched_count"]=256;Reject(delegate{MatrixNetEvents.ValidateCapture(e,32765,b,input,excessive);});
  Dictionary<string,object>[] samePort=ProbeInput();samePort[0]["local_port"]=samePort[0]["remote_port"];Reject(delegate{MatrixNetEvents.Probes(e,samePort);});Dictionary<string,object>[] overlaps=ProbeInput();overlaps[1]["started_filetime"]=BaseTime.ToString();Reject(delegate{MatrixNetEvents.Probes(e,overlaps);});Dictionary<string,object>[] slow=ProbeInput();slow[7]["finished_filetime"]=(BaseTime+7000+50000001UL).ToString();Reject(delegate{MatrixNetEvents.Probes(e,slow);});
  int destroyCalls=0,closeCalls=0;MatrixEventSession held=new MatrixEventSession(delegate(IntPtr engine,IntPtr enumeration){destroyCalls++;return destroyCalls==1?5u:0u;},delegate(IntPtr engine){closeCalls++;return 0;});held.Engine=new IntPtr(1);held.Enumeration=new IntPtr(2);Check(!MatrixNetEvents.FinishSession(held));Check(destroyCalls==2&&closeCalls==1&&held.Engine==IntPtr.Zero&&held.Enumeration==IntPtr.Zero&&MatrixNetEvents.PendingSessionCount==0);Check(!held.CloseVerified()&&held.CloseStatus==5u);
  bool allowClose=false;MatrixEventSession retained=new MatrixEventSession(delegate(IntPtr engine,IntPtr enumeration){return allowClose?0u:5u;},delegate(IntPtr engine){return 0;});retained.Engine=new IntPtr(3);retained.Enumeration=new IntPtr(4);Check(!MatrixNetEvents.FinishSession(retained));Check(MatrixNetEvents.PendingSessionCount==1&&retained.Enumeration==new IntPtr(4)&&retained.Engine==new IntPtr(3));allowClose=true;MatrixNetEvents.RetryPendingCloseOnly();Check(MatrixNetEvents.PendingSessionCount==0&&retained.Engine==IntPtr.Zero&&retained.Enumeration==IntPtr.Zero&&!retained.CloseVerified());
  byte[] fixedEvent=new byte[104],drop=new byte[16];Put(fixedEvent,0,BitConverter.GetBytes(BaseTime));Put(fixedEvent,8,BitConverter.GetBytes(0x13fu));fixedEvent[16]=6;Put(fixedEvent,20,RawAddress(IPAddress.Loopback));Put(fixedEvent,36,RawAddress(IPAddress.Loopback));Put(fixedEvent,52,BitConverter.GetBytes((ushort)44000));Put(fixedEvent,54,BitConverter.GetBytes((ushort)45000));Put(fixedEvent,64,BitConverter.GetBytes(3u));Put(fixedEvent,88,BitConverter.GetBytes(3u));Put(drop,0,BitConverter.GetBytes(1001UL));Put(drop,8,BitConverter.GetBytes((ushort)48));MatrixDropObservation decoded=MatrixNetEvents.DecodeFixed(fixedEvent,drop,App);Check(MatrixNetEvents.Matches(decoded,probes[0],b,App));fixedEvent[20]=42;Check(decoded.LocalAddress[0]!=42);byte[] copy=(byte[])App.Clone();MatrixDropObservation detached=MatrixNetEvents.DecodeFixed(fixedEvent,drop,copy);copy[0]=99;Check(detached.AppId[0]==1);
  foreach(int n in new int[]{0,1,52,88,103,105,4096})Reject(delegate{MatrixNetEvents.DecodeFixed(new byte[n],drop,App);});foreach(int n in new int[]{0,8,15,17})Reject(delegate{MatrixNetEvents.DecodeFixed(fixedEvent,new byte[n],App);});Reject(delegate{MatrixNetEvents.DecodeFixed(fixedEvent,drop,new byte[2]);});Reject(delegate{MatrixNetEvents.DecodeFixed(fixedEvent,drop,new byte[65537]);});fixedEvent[88]=4;Reject(delegate{MatrixNetEvents.DecodeFixed(fixedEvent,drop,App);});
  Console.WriteLine("{\"pure_assertions\":"+checks+",\"native_executed\":false}");return 0;
 }
}}
`;
test('bounded own WFP events: pure parsing and native SDK compile-time ABI only',async t=>{
 deps.forEach((f,i)=>assert.equal(hash(f),pins[i]));const parent=local('../../tmp/p6-r7-helper/'),tmp=mkdtempSync(path.join(parent,'matrix-events-test-'));
 t.after(()=>{deps.forEach((f,i)=>assert.equal(hash(f),pins[i]));const canonical=realpathSync(tmp);assert.equal(path.dirname(canonical),realpathSync(parent));assert.match(path.basename(canonical),/^matrix-events-test-/);rmSync(canonical,{recursive:true,force:true});});
 await t.test('no WFP mutation, subscription, global option setters or unfiltered enumeration',()=>{assert.doesNotMatch(code,/FwpmEngineSetOption|FwpmNetEventSubscribe|FwpmFilterAdd|FwpmFilterDelete|FwpmTransactionBegin|netsh|auditpol|ShellExecute|CreateProcess/);assert.ok(code.includes('Count=2,Conditions=arena.Array(conditions)'));assert.ok(code.includes('Field=CoordinatorBoundary.AppId'));assert.ok(code.includes('new Guid("206e9996-490e-40cf-b831-b38641eb6fcb")'));assert.ok(code.includes('page<8'));assert.ok(code.includes('session.Enumeration,32'));});
 const harnessPath=path.join(tmp,'pure.cs'),exe=path.join(tmp,'pure.exe');writeFileSync(harnessPath,harness);
 const compile=spawnSync(csc,['/nologo','/platform:x64','/target:exe','/warnaserror+','/reference:System.Web.Extensions.dll','/main:HereIAm.R7.MatrixEventsPureHarness',`/out:${exe}`,...deps,source,harnessPath],{encoding:'utf8',windowsHide:true,timeout:30000});assert.equal(compile.status,0,compile.stdout+compile.stderr);
 await t.test('fixed-buffer parser, every match field and strict receipt/metadata negatives',()=>{const result=spawnSync(exe,[],{encoding:'utf8',windowsHide:true,timeout:15000});assert.equal(result.status,0,result.stdout+result.stderr);const evidence=JSON.parse(result.stdout);assert.equal(evidence.native_executed,false);assert.ok(evidence.pure_assertions>=230);process.stdout.write(`pure_assertions=${evidence.pure_assertions}\n`);});
 await t.test('SDK 10.0.26100 x64 static_assert proves the real header layouts without running native code',()=>{
  const cpp=String.raw`#include <windows.h>
#include <fwpmtypes.h>
#include <stddef.h>
static_assert(sizeof(void*)==8,"x64");
static_assert(sizeof(FWPM_NET_EVENT_HEADER0)==88,"header");
static_assert(offsetof(FWPM_NET_EVENT_HEADER0,timeStamp)==0,"time");
static_assert(offsetof(FWPM_NET_EVENT_HEADER0,flags)==8,"flags");
static_assert(offsetof(FWPM_NET_EVENT_HEADER0,ipVersion)==12,"version");
static_assert(offsetof(FWPM_NET_EVENT_HEADER0,ipProtocol)==16,"protocol");
static_assert(offsetof(FWPM_NET_EVENT_HEADER0,localAddrV4)==20,"local4");
static_assert(offsetof(FWPM_NET_EVENT_HEADER0,localAddrV6)==20,"local6");
static_assert(offsetof(FWPM_NET_EVENT_HEADER0,remoteAddrV4)==36,"remote4");
static_assert(offsetof(FWPM_NET_EVENT_HEADER0,remoteAddrV6)==36,"remote6");
static_assert(offsetof(FWPM_NET_EVENT_HEADER0,localPort)==52,"localPort");
static_assert(offsetof(FWPM_NET_EVENT_HEADER0,remotePort)==54,"remotePort");
static_assert(offsetof(FWPM_NET_EVENT_HEADER0,scopeId)==56,"scope");
static_assert(offsetof(FWPM_NET_EVENT_HEADER0,appId)==64,"appid");
static_assert(offsetof(FWPM_NET_EVENT_HEADER0,userId)==80,"user");
static_assert(sizeof(FWPM_NET_EVENT0)==104,"event");
static_assert(offsetof(FWPM_NET_EVENT0,type)==88,"type");
static_assert(offsetof(FWPM_NET_EVENT0,classifyDrop)==96,"dropPointer");
static_assert(sizeof(FWPM_NET_EVENT_CLASSIFY_DROP0)==16,"drop");
static_assert(offsetof(FWPM_NET_EVENT_CLASSIFY_DROP0,filterId)==0,"filter");
static_assert(offsetof(FWPM_NET_EVENT_CLASSIFY_DROP0,layerId)==8,"layer");
static_assert(sizeof(FWPM_NET_EVENT_ENUM_TEMPLATE0)==32,"template");
static_assert(offsetof(FWPM_NET_EVENT_ENUM_TEMPLATE0,startTime)==0,"start");
static_assert(offsetof(FWPM_NET_EVENT_ENUM_TEMPLATE0,endTime)==8,"end");
static_assert(offsetof(FWPM_NET_EVENT_ENUM_TEMPLATE0,numFilterConditions)==16,"count");
static_assert(offsetof(FWPM_NET_EVENT_ENUM_TEMPLATE0,filterCondition)==24,"conditions");
static_assert(sizeof(FWPM_LAYER0)==72,"layerSize");
static_assert(offsetof(FWPM_LAYER0,layerId)==64,"layerId");
static_assert(sizeof(FWPM_FILTER0)==200,"filter200");
static_assert(offsetof(FWPM_FILTER0,filterId)==176,"filterId");
static_assert(sizeof(FWP_VALUE0)==16,"value");
static_assert(offsetof(FWP_VALUE0,uint32)==8,"value32");
static_assert(FWPM_NET_EVENT_TYPE_CLASSIFY_DROP==3,"classifyDropValue");
static_assert(FWPM_NET_EVENT_FLAG_IP_VERSION_SET==256,"versionFlag");
static_assert(FWPM_NET_EVENT_FLAG_APP_ID_SET==32,"appidFlag");
static_assert(FWPM_NET_EVENT_FLAG_SCOPE_ID_SET==128,"scopeFlag");
`;
  const cppPath=path.join(tmp,'abi.cpp'),obj=path.join(tmp,'abi.obj');writeFileSync(cppPath,cpp);
  const vc=String.raw`C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\14.50.35717`,sdk=String.raw`C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0`;
  const abi=spawnSync(path.join(vc,'bin','Hostx64','x64','cl.exe'),['/nologo','/c','/TP','/W4','/WX',`/I${path.join(vc,'include')}`,...['ucrt','shared','um'].map(p=>`/I${path.join(sdk,p)}`),`/Fo${obj}`,cppPath],{encoding:'utf8',windowsHide:true,timeout:30000});assert.equal(abi.status,0,abi.stdout+abi.stderr);assert.equal((cpp.match(/static_assert/g)||[]).length,36);
 });
});
