// No actual verbs are invoked: compile, plan, managed selftest, pure policy reflection only.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,realpathSync,rmSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const local=name=>fileURLToPath(new URL(name,import.meta.url));
const source=local('./windows_text_gate_appid_matrix_runtime.cs'),native=local('./windows_text_gate_appid_matrix_native.cs'),sockets=local('./windows_text_gate_appid_matrix_sockets.cs'),events=local('./windows_text_gate_appid_matrix_events.cs');
const deps=new Map([
 [local('./windows_text_gate_isolation_helper.cs'),'d22017641d9f8df750f6db7db9319b8c1930a726a8575ff1ffabfde0d5ffdcd8'],
 [local('./windows_text_gate_appid_startup_helper.cs'),'c777023495ccdbf3b52663f49683f5d84dcfd03a36b3d280a75c925f37b7a1ea'],
 [local('../../tmp/p6-r7-review/native-appid-coordinator-candidate-15.cs'),'c1f07e9487b8ce25d0acc2d5bbb03b69c975cbb7e448698d288ff6263cff9311'],
 [local('../../tmp/p6-r7-review/native-appid-matrix-contract-01.cs'),'f70ffb86ce5efea2572532e1986f77dde9622893ad4b90a74f9ec40da5ba6774']
]);
const hash=file=>createHash('sha256').update(readFileSync(file)).digest('hex');
const code=readFileSync(source,'utf8'),adapters=readFileSync(native,'utf8');
const section=(text,start,end)=>{const a=text.indexOf(start),b=text.indexOf(end,a+start.length);assert.ok(a>=0&&b>a,`missing source boundary: ${start}`);return text.slice(a,b);};
const initializerKeys=text=>[...text.matchAll(/\{\s*"([a-z_0-9]+)"\s*,/g)].map(m=>m[1]);
const sorted=values=>[...new Set(values)].sort();
// Audit actual production writes, independently of the synthetic report and whitelist.
const productionKeys=text=>{
 const base=section(text,'static Dictionary<string,object> Base(','const string PublicReportKeys');
 const start=section(text,'static Dictionary<string,object> StartReport(','internal static MatrixExpected Expected(');
 const coordinator=section(text,'static int Coordinator(','static Dictionary<string,object> SyntheticPublicReport(');
 assert.doesNotMatch(start+coordinator,/report\[(?!")|report\.(?:Add|Remove|Clear)\(/);
 const writes=[...(start+coordinator).matchAll(/report\["([a-z_0-9]+)"\]\s*=/g)].map(m=>m[1]);
 assert.equal(writes.length,((start+coordinator).match(/report\[/g)||[]).length,'every report index must be a captured literal write');
 return sorted([...initializerKeys(base),...writes]);
};
const whitelist=text=>text.match(/const string PublicReportKeys="([^"]+)"/)[1].split(',').sort();
const frozenV4=local('../../tmp/p6-r7-review/native-appid-matrix-runtime-04.cs');
const frozenV4Hash='333cc344f6deb478cc37fceab2c20e1d18f07cf09dcfba39e6eeb6dcc5c79828';
const pureHarness=String.raw`
using System;using System.IO;using System.Text;using System.Threading;using System.Reflection;using System.Collections.Generic;
namespace HereIAm.R7 {public static class MatrixRuntimeProjectionHarness {
 static int checks;static void Check(bool ok){if(!ok)throw new Exception("projection_or_wait_failed_"+checks);checks++;}
 static void Reject(Action action){bool rejected=false;try{action();}catch{rejected=true;}Check(rejected);}
 static string Read(string file){using(var stream=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.Read))using(var reader=new StreamReader(stream,new UTF8Encoding(false,true))){return reader.ReadToEnd();}}
 public static int Main(string[] args){string target=Path.Combine(args[0],"lease-test.json"),value=null;Exception error=null;
  using(var writer=new FileStream(target,FileMode.CreateNew,FileAccess.Write,FileShare.None))using(var attempted=new ManualResetEvent(false))using(var finished=new ManualResetEvent(false)){
   byte[] first=Encoding.UTF8.GetBytes("{\"ready\":");writer.Write(first,0,first.Length);writer.Flush(true);
   var thread=new Thread(delegate(){try{value=MatrixRuntimeFiles.WaitReadCore(delegate{return !File.Exists(target);},delegate{attempted.Set();return Read(target);},3000);}catch(Exception failure){error=failure;}finally{finished.Set();}});thread.Start();
   try{Check(attempted.WaitOne(1000));Check(!finished.WaitOne(100));byte[] last=Encoding.UTF8.GetBytes("true}");writer.Write(last,0,last.Length);writer.Flush(true);Check(!finished.WaitOne(100));}finally{writer.Dispose();Check(thread.Join(4000));}
   Check(error==null&&value=="{\"ready\":true}");
  }
  using(var writer=new FileStream(target,FileMode.Open,FileAccess.Write,FileShare.None)){Check(MatrixRuntimeFiles.WaitReadCore(delegate{return false;},delegate{return Read(target);},60)==null);}
  Check(MatrixRuntimeFiles.WaitReadCore(delegate{return true;},delegate{throw new Exception("must_not_read_absent");},30)==null);
  foreach(int code in new[]{32,33}){int calls=0;string got=MatrixRuntimeFiles.WaitReadCore(delegate{return false;},delegate{if(calls++==0)throw new IOException("busy",unchecked((int)(0x80070000u+(uint)code)));return "complete";},1000);Check(got=="complete"&&calls==2);}
  foreach(int code in new[]{2,3,5,80,87}){int calls=0;Reject(delegate{MatrixRuntimeFiles.WaitReadCore(delegate{return false;},delegate{calls++;throw new IOException("reject",unchecked((int)(0x80070000u+(uint)code)));},1000);});Check(calls==1);}
  Reject(delegate{MatrixRuntimeFiles.WaitReadCore(delegate{throw new UnauthorizedAccessException();},delegate{return "bad";},1000);});
  Reject(delegate{MatrixRuntimeFiles.WaitReadCore(delegate{return false;},delegate{throw new DecoderFallbackException();},1000);});
  Reject(delegate{MatrixRuntimeFiles.WaitReadCore(delegate{return false;},delegate{return "bad";},0);});
  var make=typeof(MatrixRuntimeProgram).GetMethod("SyntheticPublicReport",BindingFlags.Static|BindingFlags.NonPublic);
  var complete=(Dictionary<string,object>)make.Invoke(null,new object[]{true});var early=(Dictionary<string,object>)make.Invoke(null,new object[]{false});
  var result=new Dictionary<string,object>{{"complete",MatrixRuntimeProgram.PublicMatrixReportJson(complete)},{"early",MatrixRuntimeProgram.PublicMatrixReportJson(early)},{"local_wait_assertions",checks}};Console.WriteLine(MatrixRecords.Json(result));return 0;
 }
}}
`;
test('matrix runtime pure verification never invokes actual native roles',async t=>{
 // Current socket/events are independently owned v2 dependencies; snapshot and verify no mutation during this test.
 assert.equal(hash(native),'f2d3b35a1e6d1763930ba7f9a82ab8dbb595e02d5d720216a0161dbce8a0d0ab');
 const baseline=new Map([...deps,[frozenV4,frozenV4Hash],...[native,sockets,events].map(file=>[file,hash(file)])]);for(const [file,pin] of baseline)assert.equal(hash(file),pin);
 const parent=local('../../tmp/p6-r7-helper/'),tmp=mkdtempSync(path.join(parent,'matrix-runtime-test-')),exe=path.join(tmp,'runtime.exe');
 t.after(()=>{for(const [file,pin] of baseline)assert.equal(hash(file),pin);const canonical=realpathSync(tmp);assert.equal(path.dirname(canonical),realpathSync(parent));assert.match(path.basename(canonical),/^matrix-runtime-test-/);rmSync(canonical,{recursive:true,force:true});});
 const compile=spawnSync(String.raw`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`,['/nologo','/platform:x64','/target:exe','/warnaserror+','/reference:System.Web.Extensions.dll','/main:HereIAm.R7.MatrixRuntimeProgram',`/out:${exe}`,...deps.keys(),native,sockets,events,source],{encoding:'utf8',windowsHide:true,timeout:30000});assert.equal(compile.status,0,compile.stdout+compile.stderr);
 const pureExe=path.join(tmp,'projection.exe'),pureFile=path.join(tmp,'projection.cs');writeFileSync(pureFile,pureHarness);
 const pureCompile=spawnSync(String.raw`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`,['/nologo','/platform:x64','/target:exe','/warnaserror+','/reference:System.Web.Extensions.dll','/main:HereIAm.R7.MatrixRuntimeProjectionHarness',`/out:${pureExe}`,...deps.keys(),native,sockets,events,source,pureFile],{encoding:'utf8',windowsHide:true,timeout:30000});assert.equal(pureCompile.status,0,pureCompile.stdout+pureCompile.stderr);
 const run=arg=>{assert.ok(['--plan','--self-test','--invalid-test-only'].includes(arg));const result=spawnSync(exe,[arg],{encoding:'utf8',windowsHide:true,timeout:15000});assert.equal(result.signal,null);assert.equal(result.stderr,'');const json=JSON.parse(result.stdout);assert.equal(json.schema,'p6_r7_appid_matrix_runtime_v2');for(const field of ['native_executed','matrix_passed','all_own_filter_drops_matched','event_matrix_passed','production_isolation_passed','human_gate_passed'])assert.equal(json[field],false);assert.equal(json.real_upstream_requests,0);assert.equal(json.model_turns_requested,0);assert.doesNotMatch(result.stdout,/[CD]:\\|S-1-/);return {status:result.status,json};};
 await t.test('plan remains read-only; real native actions require exact explicit verbs',()=>{assert.equal(run('--plan').status,0);assert.equal(run('--invalid-test-only').status,2);assert.ok(code.includes('args.Length==1&&args[0]=="--apply-local-appid-matrix"'));assert.ok(code.includes('Guid.TryParseExact(args[1],"D",out id)'));});
 await t.test('selftest covers helper/cleanup/event gates, event envelopes, nullable launch diagnostics, and complete public-report projection',()=>{const result=run('--self-test');assert.equal(result.status,0);assert.equal(result.json.assertions_passed,233);});
 await t.test('frozen v4 production union exposes the omitted field; current whitelist covers all actual writes',()=>{
  const old=readFileSync(frozenV4,'utf8'),actual=productionKeys(old),allowed=whitelist(old);
  assert.equal(actual.length,36);assert.equal(allowed.length,35);
  assert.deepEqual(actual.filter(key=>!allowed.includes(key)),['all_negative_roles_blocked']);
  assert.deepEqual(allowed.filter(key=>!actual.includes(key)),[]);
  assert.deepEqual(productionKeys(code),actual);assert.deepEqual(whitelist(code),actual);
  assert.equal(section(code,'static int Coordinator(','static Dictionary<string,object> SyntheticPublicReport('),section(old,'static int Coordinator(','static Dictionary<string,object> SyntheticPublicReport('),'report fix must not change coordinator cleanup or event gates');
 });
 await t.test('ready/ack use one completed strict read within the original budget; ordinary reads stay strict',()=>{
  const old=readFileSync(frozenV4,'utf8');
  assert.equal(section(code,'internal string Read(string name)','internal static string WaitReadCore('),section(old,'internal string Read(string name)','internal bool Wait('));
  const wait=section(code,'internal static string WaitReadCore(','internal bool CloseVerified()');
  assert.ok(wait.includes('code!=0x80070020u&&code!=0x80070021u'));assert.ok(wait.includes('timeout<=30000'));assert.ok(wait.includes('Stopwatch.StartNew()'));
  assert.ok(code.includes('files.WaitRead(action+"-ack.json",30000)==MatrixRecords.Json(lease)'));
  assert.ok(code.includes('string readyText=files.WaitRead(action+"-ready.json",30000)'));assert.ok(code.includes('readyText==MatrixRecords.Json(lease)'));
  assert.doesNotMatch(code,/files\.Read\(action\+"-(?:ready|ack)\.json"|files\.Wait\(/);
 });
 const literal=v=>`'${v.replaceAll("'","''")}'`;
 const script=`[Reflection.Assembly]::LoadFrom(${literal(exe)})|Out-Null
$closures=@();foreach($mask in 0..127){$closures+=@{mask=$mask;accepted=[HereIAm.R7.MatrixRuntimePolicy]::CleanupComplete(($mask-band 1)-ne 0,($mask-band 2)-ne 0,($mask-band 4)-ne 0,($mask-band 8)-ne 0,($mask-band 16)-ne 0,($mask-band 32)-ne 0,($mask-band 64)-ne 0)}}
$helpers=@();foreach($mask in 0..15){foreach($exit in @(0,1,3,4,259)){ $helpers+=@{mask=$mask;exit=$exit;accepted=[HereIAm.R7.MatrixRuntimePolicy]::HelperAccepted(($mask-band 1)-ne 0,($mask-band 2)-ne 0,[uint32]$exit,($mask-band 4)-ne 0,($mask-band 8)-ne 0)}}}
$events=@();foreach($mask in 0..31){$events+=@{mask=$mask;accepted=[HereIAm.R7.MatrixRuntimePolicy]::EventGate(($mask-band 1)-ne 0,($mask-band 2)-ne 0,($mask-band 4)-ne 0,($mask-band 8)-ne 0,($mask-band 16)-ne 0)}}
@{closures=$closures;helpers=$helpers;events=$events;line=[HereIAm.R7.MatrixRuntimePolicy]::ProtocolLine('{}')}|ConvertTo-Json -Depth 5 -Compress`;
 const reflection=spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',script],{encoding:'utf8',windowsHide:true,timeout:15000});assert.equal(reflection.status,0,reflection.stderr);const facts=JSON.parse(reflection.stdout);
 await t.test('serialized success and pre-fixture failure match production keys at every public level',()=>{
  const result=spawnSync(pureExe,[tmp],{encoding:'utf8',windowsHide:true,timeout:15000});assert.equal(result.status,0,JSON.stringify({error:result.error,stdout:result.stdout,stderr:result.stderr}));
  const raw=JSON.parse(result.stdout),complete=JSON.parse(raw.complete),early=JSON.parse(raw.early);assert.ok(raw.local_wait_assertions>=20);process.stdout.write(`local_wait_assertions=${raw.local_wait_assertions}\n`);
  const helperKeys=sorted(initializerKeys(section(code,'static Dictionary<string,object> HelperDiagnostic(','static void SocketSend(')));
  const eventKeys=sorted(initializerKeys(section(code,'static Dictionary<string,object> EventDiagnostic(','static Dictionary<string,object> HelperDiagnostic(')));
  const rowsCode=section(readFileSync(sockets,'utf8'),'public Dictionary<string,object>[] Rows()','public bool CloseVerified()');
  const rowKeys=sorted(initializerKeys(rowsCode));assert.equal(rowKeys.length,13);
  const summaryCode=readFileSync(events,'utf8').slice(readFileSync(events,'utf8').indexOf('internal static Dictionary<string,object> SafeSummary('));
  const summaryKeys=sorted(initializerKeys(summaryCode.slice(summaryCode.indexOf('return new Dictionary<string,object>'))));
  const roleKeys=sorted(initializerKeys(summaryCode.slice(0,summaryCode.indexOf('return new Dictionary<string,object>'))));
  assert.equal(summaryKeys.length,6);assert.equal(roleKeys.length,3);
  for(const value of [complete,early]){
   assert.deepEqual(Object.keys(value).sort(),productionKeys(code));
   assert.deepEqual(Object.keys(value.install_diagnostic).sort(),helperKeys);assert.deepEqual(Object.keys(value.cleanup_diagnostic).sort(),helperKeys);
   assert.deepEqual(Object.keys(value.event_diagnostic).sort(),eventKeys);
   assert.equal(value.failure_stage,0);assert.equal(value.all_negative_roles_blocked,false);
   assert.equal(value.production_isolation_passed,false);assert.equal(value.human_gate_passed,false);
  }
  assert.equal(complete.event_matrix_passed,true);assert.equal(complete.matrix_passed,true);assert.equal(complete.rows.length,8);
  for(const row of complete.rows)assert.deepEqual(Object.keys(row).sort(),rowKeys);
  const summary=complete.event_diagnostic.capture_summary;assert.deepEqual(Object.keys(summary).sort(),summaryKeys);assert.equal(summary.roles.length,8);
  for(const role of summary.roles)assert.deepEqual(Object.keys(role).sort(),roleKeys);
  assert.equal(early.rows,null);assert.equal(early.fixture_ready,false);assert.equal(early.event_matrix_passed,false);assert.equal(early.event_diagnostic.capture_summary,null);
  assert.equal(early.install_diagnostic.invoked,false);assert.equal(early.cleanup_diagnostic.invoked,false);assert.equal(early.no_job_created,true);
  assert.equal(early.exact_child_closed,null);assert.equal(early.job_active0,null);assert.equal(early.stdio_eof,null);
  assert.ok(Buffer.byteLength(raw.complete,'utf8')<=16384);assert.ok(Buffer.byteLength(raw.early,'utf8')<=16384);
  assert.doesNotMatch(raw.complete+raw.early,/[CD]:\\|S-1-|PRIVATE/);
 });
 await t.test('unknown/active/helper error/partial cleanup cannot become clean',()=>{assert.equal(facts.closures.length,128);for(const row of facts.closures)assert.equal(row.accepted,row.mask===127);assert.equal(facts.helpers.length,80);for(const row of facts.helpers)assert.equal(row.accepted,row.mask===15&&row.exit===0);assert.equal(facts.line,true);});
 await t.test('fresh fixed paths and ACL provenance precede journal, no credentials/config/old CLI',()=>{assert.ok(code.includes('FileMode.CreateNew'));assert.ok(code.includes('acl.AreAccessRulesProtected'));assert.ok(code.includes('rules.Count==3'));assert.ok(code.includes('MatrixNativeApi.VerifyPath(file.SafeFileHandle.DangerousGetHandle(),target,false)'));assert.doesNotMatch(code,/FileMode.Create[,)]|File.Replace|Process.Start|cmd.exe|codex.exe|auth.json|config.toml|SetEnvironmentVariable/);});
 await t.test('helper ready/ack live binding precedes rule mutation and actual exit precedes receipt',()=>{const helper=code.slice(code.indexOf('static int Helper('),code.indexOf('static MatrixHelperRun Invoke('));assert.ok(helper.indexOf('files.WaitRead(action+"-ack.json"')<helper.indexOf('rules.Install('));const invoke=code.slice(code.indexOf('static MatrixHelperRun Invoke('),code.indexOf('static int Coordinator('));assert.ok(invoke.indexOf('TokenProof.Image(shell.Process,files.Source)')<invoke.indexOf('files.Write(action+"-ack.json"'));assert.ok(invoke.indexOf('result.Exited=true')<invoke.indexOf('MatrixRecords.ValidateReceipt'));assert.doesNotMatch(invoke.slice(invoke.indexOf('result.Exited=true')),/TokenProof.Image/);});
 await t.test('fixture readiness is before UAC; results only final after held child closure and drain',()=>{const coordinator=code.slice(code.indexOf('static int Coordinator('),code.indexOf('static int SelfTest('));assert.ok(coordinator.indexOf('MatrixRuntimeCheck.Need(fixtureReady)')<coordinator.indexOf('Invoke(files,expected,"install"'));assert.ok(coordinator.indexOf('child.StopAndObserve()')<coordinator.indexOf('fixtures.DrainVerified()'));assert.ok(coordinator.indexOf('fixtures.DrainVerified()')<coordinator.indexOf('fixtures.AllNegativeBlocked'));assert.doesNotMatch(coordinator,/Need\(fixtures.Complete/);});
 await t.test('atomic detached job, exact three stdio handles, held cleanup and retained close failures',()=>{assert.ok(adapters.includes('new IntPtr(0x2000d)'));assert.ok(adapters.includes('new IntPtr(0x20002)'));assert.ok(adapters.includes('new IntPtr(24)'));assert.ok(adapters.includes('0x0008040c'));assert.ok(adapters.includes('if(success)handles.Remove(handle);else AllCloseCallsSucceeded=false'));assert.ok(adapters.includes('CloseNeverCreated'));assert.ok(adapters.includes('RollbackPrepared'));assert.ok(code.includes('child.CloseAfterVerifiedRulesRemoval(true)'));assert.ok(code.includes('child.CloseNeverCreated(true)'));});
 await t.test('failed creation closes parent writer endpoints before EOF; absent resources have no fabricated proof',()=>{const cleanup=code.slice(code.indexOf('// Every branch reaches real owned cleanup;'));assert.ok(cleanup.indexOf('pipes.CloseChildEndsForCleanup()')<cleanup.indexOf('stdout.Drain('));assert.ok(code.includes('report["exact_child_closed"]=noChild?null:(object)exactChild'));assert.ok(code.includes('report["job_active0"]=child==null?null:(object)job0'));assert.ok(code.includes('report["no_job_created"]=child!=null?(object)false:jobConstructionAttempted?null:(object)true'));assert.ok(code.includes('jobConstructionAttempted=true;child=new MatrixOwnedProbe(pin)'));assert.ok(code.includes('closed=closed&&!MatrixHandleLedger.AnyCloseFailure'));assert.ok(code.includes('if(!failedSockets.Contains(value))failedSockets.Add(value)'));});
 await t.test('eight sequential rows retain one outstanding bounded frame and fixed diagnostics',()=>{assert.ok(code.includes('bytes.Length<=4096'));assert.ok(code.includes('total<=32768'));assert.ok(code.includes('pending.Count<=8192'));assert.ok(code.includes('ReadMessage(stdout,"broker_done"'));assert.ok(code.includes('ReadMessage(stdout,"row_outcome"'));assert.ok(code.includes('for(int index=0;index<8;index++)'));assert.ok(code.includes('MatrixRuntimeCheck.Number(response["index"])==index'));assert.ok(code.includes('Object.Equals(outcome["marker"],challenge["marker"])'));assert.doesNotMatch(code,/ReadMessage\(stdout,"outcomes"|\["challenges"\]/);assert.ok(code.includes('{"error_code",completed?0:1}'));assert.doesNotMatch(code,/Exception\.Message|\.ToString\(\).*Exception|error\.Message/);});
 await t.test('event gate rejects any missing bound helper/window/zero receive/drop proof',()=>{assert.equal(facts.events.length,32);for(const row of facts.events)assert.equal(row.accepted,row.mask===31);assert.ok(code.includes('protocol&&probeWindows'));assert.ok(code.includes('zeroReceives=fixtures.ZeroReceivesVerified'));assert.ok(code.includes('report["all_negative_roles_blocked"]=fixtures.AllNegativeBlocked'));});
 await t.test('parent windows gate private metadata and event reads cannot bypass rule cleanup',()=>{assert.ok(code.includes('ulong before=MatrixSocketFixtures.NowFileTime();MatrixRuntimePump.Send'));assert.ok(code.includes('ulong after=MatrixSocketFixtures.NowFileTime()'));assert.ok(code.includes('probeWindows=MatrixSocketFixtures.ValidateProbeWindow(challenge,outcome,before,after)&&probeWindows'));assert.ok(code.includes('if(probeWindows&&install.EventBinding!=null)'));const helper=code.slice(code.indexOf('static int Helper('),code.indexOf('static MatrixHelperRun Invoke('));assert.ok(helper.indexOf('MatrixNetEvents.Capture(')<helper.indexOf('rules.Cleanup('));assert.ok(helper.includes('catch{eventCapture=null;}'));assert.ok(helper.indexOf('MatrixRecords.Receipt(')<helper.indexOf('files.Write("event-receipt.json"'));});
 await t.test('events remain read-locked and bound to exact install plus cleanup helper receipts',()=>{assert.ok(code.includes('internal string ReadPinned(string name){Pin(PathFor(name),false);return Read(name);}'));assert.ok(code.includes('files.Read("event-binding.json")==bindingText&&files.Read("event-probes.json")==probeText'));assert.ok(code.includes('files.Read("event-binding.json")==eventBinding&&files.Read("event-probes.json")==eventProbes'));const invoke=code.slice(code.indexOf('static MatrixHelperRun Invoke('),code.indexOf('static int Coordinator('));assert.ok(invoke.indexOf('result.Exited=true')<invoke.indexOf('MatrixNetEvents.ValidateCapture('));assert.ok(invoke.indexOf('result.Receipt=true')<invoke.indexOf('MatrixNetEvents.ValidateCapture('));assert.ok(code.includes('cleanup!=null&&cleanup.Accepted&&cleanup.EventMatched'));});
 await t.test('accepted socket setup failures retain ownership and event diagnostics only use validated projection',()=>{assert.ok(code.includes('catch{if(!CloseSocket(socket))MatrixHandleLedger.AnyCloseFailure=true;throw;}'));assert.ok(code.includes('result.EventSummary=MatrixNetEvents.SafeSummary('));assert.ok(code.includes('validated=admitted&&cleanup.EventSummary!=null'));assert.ok(code.includes('{"capture_summary",validated?cleanup.EventSummary:null}'));assert.doesNotMatch(code,/report\["event_diagnostic"\]=capture|report\["event_diagnostic"\]=eventCapture/);});
 await t.test('helper diagnostics capture immediate launch errno and preserve unknown/no-call distinctions without new native calls',()=>{
  const invoke=code.slice(code.indexOf('static MatrixHelperRun Invoke('),code.indexOf('static int Coordinator('));
  assert.ok(invoke.includes('result.LaunchAttempted=true;bool launched=CoordinatorNative.ShellExecuteExW(ref shell);uint error=unchecked((uint)Marshal.GetLastWin32Error());result.LaunchReturned=true;'));
  assert.ok(invoke.includes('result.LaunchError=launched?(uint?)null:error'));
  assert.ok(invoke.includes('result.ReadyWaitAttempted=true;string readyText=files.WaitRead(action+"-ready.json",30000);bool ready=readyText!=null;result.ReadyObserved=ready;MatrixRuntimeCheck.Need(ready)'));
  assert.equal((invoke.match(/ShellExecuteExW\(/g)||[]).length,1);assert.equal((invoke.match(/WaitForSingleObject\(/g)||[]).length,2);assert.equal((invoke.match(/GetExitCodeProcess\(/g)||[]).length,1);
  assert.ok(code.includes('report["install_diagnostic"]=HelperDiagnostic(install)'));assert.ok(code.includes('report["cleanup_diagnostic"]=HelperDiagnostic(cleanup)'));
  const projection=code.slice(code.indexOf('static Dictionary<string,object> HelperDiagnostic('),code.indexOf('static void SocketSend('));
  assert.ok(projection.includes('{"actual_exited",value!=null&&value.Exited?(object)true:null}'));assert.doesNotMatch(projection,/\.EventBinding|\.EventSummary|\.ToString|Pid|Creation|Nonce|Path|User/);
  assert.ok(code.includes('internal bool Accepted {get{return MatrixRuntimePolicy.HelperAccepted(LiveBound,Exited,Exit.HasValue?Exit.Value:UInt32.MaxValue,Receipt,HandlesClosed);}}'));
 });
 await t.test('complete public reports alone use a bounded depth-six serializer',()=>{
  assert.ok(code.includes('new JavaScriptSerializer{MaxJsonLength=16384,RecursionLimit=6}.Serialize(report)'));
  assert.ok(code.includes('MatrixRuntimeCheck.Keys(report,PublicReportKeys)'));
  assert.ok(code.includes('MatrixRecords.Json(complete)'));
  assert.ok(code.includes('legacyRejected'));
  assert.ok(code.includes('static Dictionary<string,object> StartReport()'));
  assert.ok(code.includes('Dictionary<string,object> report=StartReport();Guid id=Guid.NewGuid()'));
  assert.ok(code.includes('report["rows"]=null'));
  assert.ok(code.includes('SyntheticPublicReport(false)'));
  assert.ok(code.includes('incompleteParsed["rows"]==null'));
  assert.ok(code.includes('PublicMatrixReportJson(report)'));
  assert.doesNotMatch(code.slice(code.indexOf('internal static string PublicMatrixReportJson'),code.indexOf('static int Coordinator(')),/MatrixRecords\.Serializer|RecursionLimit=7|MaxJsonLength=32768/);
 });
});
