// Pure parser/decision tests; actual local sockets require a separate explicit host fixture run.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, realpathSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const local=n=>fileURLToPath(new URL(n,import.meta.url));
const deps=new Map([
 [local('./windows_text_gate_isolation_helper.cs'),'d22017641d9f8df750f6db7db9319b8c1930a726a8575ff1ffabfde0d5ffdcd8'],
 [local('./windows_text_gate_appid_startup_helper.cs'),'c777023495ccdbf3b52663f49683f5d84dcfd03a36b3d280a75c925f37b7a1ea'],
 [local('../../tmp/p6-r7-review/native-appid-coordinator-candidate-15.cs'),'c1f07e9487b8ce25d0acc2d5bbb03b69c975cbb7e448698d288ff6263cff9311'],
 [local('../../tmp/p6-r7-review/native-appid-matrix-contract-01.cs'),'f70ffb86ce5efea2572532e1986f77dde9622893ad4b90a74f9ec40da5ba6774'],
]);
const source=local('./windows_text_gate_appid_matrix_sockets.cs');
const artifacts=local('../../tmp/p6-r7-helper/');
const hash=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const csc=String.raw`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`;
const harness=`using System;using System.Collections.Generic;using HereIAm.R7;
public static class SocketPureHarness {
 static int count;static void Check(bool b){if(!b)throw new Exception("pure_check_failed");count++;}
 static Dictionary<string,object> Meta(Dictionary<string,object> row){foreach(string key in new[]{"local_address","local_port","remote_address","remote_port","ip_protocol","started_filetime","finished_filetime"})row[key]=null;return row;}
 public static int Main(string[] args){if(args.Length!=0)return 2;
  string marker=new string('a',48);bool complete,success;int? code;
  foreach(object error in new object[]{null,10013,10035,10060,10061,0,-1,12000,"10013",true,10013L})
  foreach(bool done in new[]{false,true})foreach(bool passed in new[]{false,true}){
   var value=Meta(new Dictionary<string,object>{{"role","loopback4_tcp"},{"marker",marker},{"operation_completed",done},{"operation_succeeded",passed},{"socket_error",error}});
   bool valid=MatrixSocketFixtures.ValidateOutcome(value,"loopback4_tcp",marker,out complete,out success,out code);
   bool errorValid=error==null||error is int&&(int)error>=10000&&(int)error<=11999||error is long&&(long)error>=10000&&(long)error<=11999;
   bool expected=errorValid&&!(passed&&(!done||error!=null))&&(done?(passed||error!=null):!passed);Check(valid==expected);
  }
  var good=Meta(new Dictionary<string,object>{{"role","loopback4_tcp"},{"marker",marker},{"operation_completed",true},{"operation_succeeded",false},{"socket_error",10013}});
  Check(MatrixSocketFixtures.ValidateOutcome(good,"loopback4_tcp",marker,out complete,out success,out code)&&complete&&!success&&code==10013);
  Check(!MatrixSocketFixtures.ValidateOutcome(good,"local4_tcp",marker,out complete,out success,out code));Check(!MatrixSocketFixtures.ValidateOutcome(good,"loopback4_tcp",new string('b',48),out complete,out success,out code));
  foreach(string key in new List<string>(good.Keys)){var missing=new Dictionary<string,object>(good);missing.Remove(key);Check(!MatrixSocketFixtures.ValidateOutcome(missing,"loopback4_tcp",marker,out complete,out success,out code));}
  good["extra"]=true;Check(!MatrixSocketFixtures.ValidateOutcome(good,"loopback4_tcp",marker,out complete,out success,out code));
  good.Remove("extra");var challenge=new Dictionary<string,object>{{"role","loopback4_tcp"},{"address","127.0.0.1"},{"port",45678},{"marker",marker}};
  Check(!MatrixSocketFixtures.ValidateProbeWindow(challenge,good,1000,2000));
  good["local_address"]="127.0.0.1";good["local_port"]=45679;good["remote_address"]="127.0.0.1";good["remote_port"]=45678;good["ip_protocol"]=6;good["started_filetime"]="1200";good["finished_filetime"]="1800";
  Check(MatrixSocketFixtures.ValidateProbeWindow(challenge,good,1000,2000));
  Check(!MatrixSocketFixtures.ValidateProbeWindow(challenge,good,1201,2000));Check(!MatrixSocketFixtures.ValidateProbeWindow(challenge,good,1000,1799));Check(!MatrixSocketFixtures.ValidateProbeWindow(challenge,good,0,2000));Check(!MatrixSocketFixtures.ValidateProbeWindow(challenge,good,2001,2000));Check(!MatrixSocketFixtures.ValidateProbeWindow(challenge,good,1000,300001001));
  foreach(string key in new[]{"local_address","local_port","remote_address","remote_port","ip_protocol","started_filetime","finished_filetime"}){var bad=new Dictionary<string,object>(good);bad[key]=null;Check(!MatrixSocketFixtures.ValidateProbeWindow(challenge,bad,1000,2000));}
  foreach(var pair in new[]{new KeyValuePair<string,object>("local_address","127.0.0.2"),new KeyValuePair<string,object>("remote_address","127.0.0.2"),new KeyValuePair<string,object>("local_port",0),new KeyValuePair<string,object>("local_port",65536),new KeyValuePair<string,object>("local_port",45678),new KeyValuePair<string,object>("remote_port",45679),new KeyValuePair<string,object>("ip_protocol",17),new KeyValuePair<string,object>("started_filetime","01200"),new KeyValuePair<string,object>("started_filetime","1900"),new KeyValuePair<string,object>("finished_filetime","2650467744000000000")}){var bad=new Dictionary<string,object>(good);bad[pair.Key]=pair.Value;Check(!MatrixSocketFixtures.ValidateProbeWindow(challenge,bad,1000,2000));}
  challenge["role"]="local6_udp";challenge["address"]="fe80::1%4";good["role"]="local6_udp";good["local_address"]="fe80::1%4";good["remote_address"]="fe80::1%4";good["ip_protocol"]=17;Check(MatrixSocketFixtures.ValidateProbeWindow(challenge,good,1000,2000));challenge["address"]="FE80::1%4";Check(!MatrixSocketFixtures.ValidateProbeWindow(challenge,good,1000,2000));challenge["address"]="fe80::1%4";good["local_address"]="fe80::1%5";Check(!MatrixSocketFixtures.ValidateProbeWindow(challenge,good,1000,2000));
  Console.WriteLine("{\\"assertions\\":"+count+",\\"native_executed\\":false}");return 0;
 }
}`;
test('socket result parser rejects cross-row, stale marker, ambiguous values without native calls',()=>{
 for(const [file,pin] of deps)assert.equal(hash(file),pin);
 const tmp=mkdtempSync(path.join(artifacts,'matrix-sockets-pure-'));
 assert.equal(path.dirname(realpathSync(tmp)),realpathSync(artifacts));
 const cs=path.join(tmp,'pure.cs'),exe=path.join(tmp,'pure.exe');writeFileSync(cs,harness);
 const built=spawnSync(csc,['/nologo','/target:exe','/platform:x64','/warnaserror+','/reference:System.Web.Extensions.dll','/main:SocketPureHarness',`/out:${exe}`,...deps.keys(),source,cs],{windowsHide:true,encoding:'utf8',timeout:30000});
 assert.equal(built.status,0,built.stdout+built.stderr);
 const run=spawnSync(exe,[],{windowsHide:true,encoding:'utf8',timeout:10000});assert.equal(run.status,0,run.stdout+run.stderr);
 const result=JSON.parse(run.stdout);assert.equal(result.assertions,87);assert.equal(result.native_executed,false);
 for(const [file,pin] of deps)assert.equal(hash(file),pin);
});
