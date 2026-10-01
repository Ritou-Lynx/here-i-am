// Compile and synthetic checks only. Never invoke the actual inspection entry.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, realpathSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const local = name => fileURLToPath(new URL(name, import.meta.url));
const source = local('./windows_text_gate_task_retired_inspect.cs');
const hash = file => createHash('sha256').update(readFileSync(file)).digest('hex');
const dependencies = new Map([
  [local('./windows_text_gate_isolation_helper.cs'), 'd22017641d9f8df750f6db7db9319b8c1930a726a8575ff1ffabfde0d5ffdcd8'],
  [local('./windows_text_gate_appid_startup_helper.cs'), 'c777023495ccdbf3b52663f49683f5d84dcfd03a36b3d280a75c925f37b7a1ea'],
  [local('../../tmp/p6-r7-review/native-appid-coordinator-candidate-15.cs'), 'c1f07e9487b8ce25d0acc2d5bbb03b69c975cbb7e448698d288ff6263cff9311'],
  [local('../../tmp/p6-r7-review/native-appid-matrix-contract-01.cs'), 'f70ffb86ce5efea2572532e1986f77dde9622893ad4b90a74f9ec40da5ba6774'],
  [local('./windows_text_gate_appid_matrix_native.cs'), 'f2d3b35a1e6d1763930ba7f9a82ab8dbb595e02d5d720216a0161dbce8a0d0ab'],
]);
const historicalFile = local('../../tmp/p6-r7-review/native-task-auth-actual-04.json');
const evidence = new Map([
  [historicalFile, '0768a3bc5cda07568c418347c39d1ac4416d141fc84bc384d0b75842eb60f238'],
  [local('../../tmp/p6-r7-review/native-task-executor-04.cs'), '930b436dd011df2f9299107c063d2a7c7d706a00e974c4bad7e016d0b3a10cb5'],
  [local('../../tmp/p6-r7-helper/windows_text_gate_task_executor.v4.exe'), 'fbe5882461130a93988f7468290c86edeba0e33cfeab8ad3322f1a7a44867f5f'],
]);
const code = readFileSync(source, 'utf8');
const literal = value => '@"' + value.replaceAll('"', '""') + '"';
const harness = String.raw`
using System;using System.Collections.Generic;
namespace HereIAm.R7 {public static class TaskRetiredInspectPureHarness {
 static int checks;static void Check(bool value){if(!value)throw new Exception("pure_failed_"+checks);checks++;}
 static void Reject(Action action){bool rejected=false;try{action();}catch{rejected=true;}Check(rejected);}
 public static int Main(){
  string original=ORIGINAL;
  var journal=new Dictionary<string,object>{{"schema","p6_r7_task_owned_v2"},{"attempt_id",TaskRetiredInspectProgram.Attempt.ToString("D")},{"scope_id",TaskRetiredInspectProgram.Scope.ToString("D")},{"auth_mode","chatgpt"},{"home_class","dedicated_existing"},{"nonce",new string('a',64)},{"owner_pid",TaskRetiredInspectProgram.OwnerPid},{"owner_creation",TaskRetiredInspectProgram.OwnerCreation.ToString(System.Globalization.CultureInfo.InvariantCulture)},{"owner_sha256",TaskRetiredInspectProgram.ImageHash},{"owner_token_digest",new string('b',64)},{"cli_sha256",TaskRetiredInspectProgram.CliHash},{"broker_port",TaskRetiredInspectProgram.BrokerPort},{"phase","prepared"},{"child_pid",null},{"child_creation",null}};
  string prepared=MatrixRecords.Json(journal);Check(TaskRetiredInspectProgram.History(prepared,original)==new string('b',64));
  foreach(string key in new List<string>(journal.Keys)){
   var missing=new Dictionary<string,object>(journal);missing.Remove(key);Reject(delegate{TaskRetiredInspectProgram.History(MatrixRecords.Json(missing),original);});
   foreach(object badValue in new object[]{"untrusted",0,true,null}){var bad=new Dictionary<string,object>(journal);bad[key]=badValue;if(badValue==null&&(key=="child_pid"||key=="child_creation"))continue;Reject(delegate{TaskRetiredInspectProgram.History(MatrixRecords.Json(bad),original);});}
  }
  Reject(delegate{TaskRetiredInspectProgram.History(prepared+" ",original);});
  Reject(delegate{TaskRetiredInspectProgram.History("{\"schema\":\"bad\","+prepared.Substring(1),original);});
  var extra=new Dictionary<string,object>(journal);extra["session"]=1;Reject(delegate{TaskRetiredInspectProgram.History(MatrixRecords.Json(extra),original);});
  var report=MatrixRecords.Parse(original);
  foreach(string key in new List<string>(report.Keys)){var missing=new Dictionary<string,object>(report);missing.Remove(key);Reject(delegate{TaskRetiredInspectProgram.History(prepared,MatrixRecords.Json(missing));});}
  foreach(string key in new[]{"started","turn_started","passed","stop_receipt_verified","process_close_observed","production_isolation_passed","human_gate_passed"}){var bad=new Dictionary<string,object>(report);bad[key]=true;Reject(delegate{TaskRetiredInspectProgram.History(prepared,MatrixRecords.Json(bad));});}
  foreach(string group in new[]{"broker","native_close_receipt"}){var nested=(Dictionary<string,object>)report[group];foreach(string key in new List<string>(nested.Keys)){var missing=MatrixRecords.Parse(original);((Dictionary<string,object>)missing[group]).Remove(key);Reject(delegate{TaskRetiredInspectProgram.History(prepared,MatrixRecords.Json(missing));});var bad=MatrixRecords.Parse(original);((Dictionary<string,object>)bad[group])[key]=nested[key] is bool?(object)!(bool)nested[key]:1;Reject(delegate{TaskRetiredInspectProgram.History(prepared,MatrixRecords.Json(bad));});}}
  var high=new MediumIdentity{Type=1,Integrity=12288,ElevationType=2,Elevated=1,AppContainer=0,Authentication=2};Check(TaskRetiredInspectProgram.CallerAccepted(high));Check(!TaskRetiredInspectProgram.CallerAccepted(null));
  foreach(string field in new[]{"Type","Integrity","ElevationType","Elevated","AppContainer","Authentication"}){var bad=new MediumIdentity{Type=high.Type,Integrity=high.Integrity,ElevationType=high.ElevationType,Elevated=high.Elevated,AppContainer=high.AppContainer,Authentication=high.Authentication};var info=typeof(MediumIdentity).GetField(field,System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.NonPublic);if(field=="Authentication")info.SetValue(bad,0UL);else info.SetValue(bad,field=="AppContainer"?1u:0u);Check(!TaskRetiredInspectProgram.CallerAccepted(bad));}
  foreach(string name in new[]{"bound.json","spawning.json","closed.json","install-ready.json","install-ack.json","install-receipt.json","cleanup-receipt.json","rollback-receipt.json","..\\prepared.json"})Check(!TaskRetiredInspectProgram.ExactNames(new[]{"prepared.json","codex.exe","work","project0",name}));
  Check(!TaskRetiredInspectProgram.ExactNames(new[]{"prepared.json","prepared.json","work","project0"}));Check(!TaskRetiredInspectProgram.ExactNames(new[]{"..\\prepared.json","codex.exe","work","project0"}));
  foreach(bool sub in new[]{false,true}){
   uint missing=sub?0x80320007u:0x80320003u;
   Check(!TaskRetiredInspectProgram.Presence(missing,IntPtr.Zero,sub));Check(TaskRetiredInspectProgram.Presence(0,new IntPtr(1),sub));
   Reject(delegate{TaskRetiredInspectProgram.Presence(missing,new IntPtr(1),sub);});Reject(delegate{TaskRetiredInspectProgram.Presence(0,IntPtr.Zero,sub);});
   foreach(uint error in new[]{5u,87u,0xffffffffu,sub?0x80320003u:0x80320007u})foreach(IntPtr pointer in new[]{IntPtr.Zero,new IntPtr(1)})Reject(delegate{TaskRetiredInspectProgram.Presence(error,pointer,sub);});
  }
  Check(!TaskRetiredInspectProgram.Complete(true,true,true,true,true,3,0,true,true,true,true));Check(!TaskRetiredInspectProgram.Complete(true,true,true,true,true,4,0,true,false,true,true));
  Check(TaskRetiredInspectProgram.PathIdle(false,258)&&TaskRetiredInspectProgram.PathIdle(true,0)&&!TaskRetiredInspectProgram.PathIdle(true,258)&&!TaskRetiredInspectProgram.PathIdle(false,0xffffffff));
  foreach(uint error in new[]{0u,5u,6u,0xffffffffu})Check(!TaskRetiredInspectProgram.Inactive(false,error,0,0,0));
  Check(!TaskRetiredInspectProgram.Inactive(true,0,TaskRetiredInspectProgram.OwnerPid,0,0));
  foreach(bool completed in new[]{false,true}){var outcome=TaskRetiredInspectProgram.Base("synthetic",false);TaskRetiredInspectProgram.SetHistoryAndOutcome(outcome,true,completed);Check((bool)outcome["cleanup_pending"]&&(bool)outcome["historical_cleanup_pending"]&&(bool)outcome["historical_job_empty_verified"]&&(bool)outcome["historical_handles_closed_verified"]);Check((bool)outcome["current_rules_absent_verified"]==completed&&(bool)outcome["inspection_complete"]==completed);foreach(string key in new[]{"stop_receipt_verified","historical_stop_receipt_verified","historical_process_close_observed","historical_stdio_eof_verified","historical_helper_exits_verified","production_isolation_passed","human_gate_passed"})Check(Object.Equals(outcome[key],false));Check(outcome["job_current_absent_verified"]==null&&outcome["job_current_empty_verified"]==null&&Object.Equals(outcome["job_current_inspection"],"not_performed_original_session_unavailable"));}
  Reject(delegate{TaskRetiredInspectProgram.SetHistoryAndOutcome(TaskRetiredInspectProgram.Base("synthetic",false),false,true);});
  int aborted=0,engineClosed=0;var retry=new TaskRetiredInspectResources(delegate(IntPtr h){return true;},delegate(IntPtr h){aborted++;return aborted==1?5u:0u;},delegate(IntPtr h){engineClosed++;return 0;});retry.Engine=new IntPtr(1);retry.Transaction=true;Check(!TaskRetiredInspectProgram.Finish(retry));Check(retry.Empty&&!retry.CloseSucceeded&&aborted==2&&engineClosed==1&&retry.CloseError==5u);
  int engineTries=0;var engineRetry=new TaskRetiredInspectResources(delegate(IntPtr h){return true;},delegate(IntPtr h){return 0;},delegate(IntPtr h){return ++engineTries==1?6u:0u;});engineRetry.Engine=new IntPtr(1);Check(!TaskRetiredInspectProgram.Finish(engineRetry)&&engineRetry.Empty&&!engineRetry.CloseSucceeded&&engineRetry.CloseError==6u);
  bool canClose=false;var retained=new TaskRetiredInspectResources(delegate(IntPtr h){return canClose;},delegate(IntPtr h){return 0;},delegate(IntPtr h){return 0;});retained.Handles.Own(new IntPtr(2));Check(!TaskRetiredInspectProgram.Finish(retained)&&!retained.Empty&&retained.Handles.Owns(new IntPtr(2)));canClose=true;Check(!TaskRetiredInspectProgram.Finish(retained)&&retained.Empty&&!retained.CloseSucceeded);
  var throwing=new TaskRetiredInspectResources(delegate(IntPtr h){return true;},delegate(IntPtr h){throw new InvalidOperationException("PRIVATE");},delegate(IntPtr h){return 0;});throwing.Engine=new IntPtr(3);throwing.Transaction=true;Check(!TaskRetiredInspectProgram.Finish(throwing)&&!throwing.Empty&&!throwing.CloseSucceeded);
  Console.WriteLine("{\"pure_assertions\":"+checks+",\"native_executed\":false}");return 0;
 }
}}
`.replace('ORIGINAL', literal(readFileSync(historicalFile, 'utf8').trimEnd()));

test('retired Task inspector has one fixed read-only entry and no current Job claim', () => {
  assert.doesNotMatch(code, /FwpmFilterAdd|FwpmFilterDelete|FwpmSubLayerAdd|FwpmSubLayerDelete|FwpmTransactionCommit|FwpmEngineSetOption|FwpmNetEvent|ShellExecute|CreateProcess|TerminateProcess|TerminateJob|OpenJobObject|QueryInformationJobObject|CreateJobObject|CreateDirectory|SetAccessControl|FileMode\.Create|WriteAll|WriteRecord|Process\.Start|DedicatedHome|CODEX_HOME/);
  assert.ok(code.includes('FwpmTransactionBegin0(resources.Engine,1)'));
  assert.ok(code.includes('CoordinatorBoundary.MakeRules(Scope,BrokerPort)'));
  assert.ok(code.includes('CoordinatorBoundary.Key(Scope,"sublayer")'));
  assert.ok(code.includes('count<=8192'));
  assert.ok(code.includes('MatrixNativeApi.VerifyPath'));
  assert.ok(code.includes('evidence.Pin(OriginalSource,SourceHash)'));
  assert.ok(code.includes('"cleanup_pending"]=true'));
  assert.ok(code.includes('800c3922bda6f7a8701fdbff1c2e44d10face7636f034c470fa56eb83c91062c'));
});

test('retired Task inspector compiles and fails closed under synthetic faults only', t => {
  const inputs = new Map([...dependencies, ...evidence, [source, hash(source)]]);
  const verify = () => { for (const [file, pin] of inputs) assert.equal(hash(file), pin); };
  verify();
  const parent = local('../../tmp/p6-r7-helper/');
  const tmp = mkdtempSync(path.join(parent, 'task-retired-inspect-test-'));
  t.after(() => {
    verify();const canonical = realpathSync(tmp);
    assert.equal(path.dirname(canonical), realpathSync(parent));
    assert.match(path.basename(canonical), /^task-retired-inspect-test-/);
    rmSync(canonical, { recursive: true, force: true });
  });
  const compile = (main, output, extra = []) => {
    const run = spawnSync(String.raw`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`,
      ['/nologo', '/platform:x64', '/warnaserror+', '/target:exe', '/reference:System.Web.Extensions.dll', `/main:${main}`, `/out:${output}`, ...dependencies.keys(), source, ...extra],
      { encoding: 'utf8', windowsHide: true, timeout: 30000 });
    assert.equal(run.status, 0, run.stdout + run.stderr);
  };
  const exe = path.join(tmp, 'inspect.exe');compile('HereIAm.R7.TaskRetiredInspectProgram', exe);
  for (const args of [[], ['--plan'], ['--self-test'], ['--inspect-retired-fixed-elevated-readonly', 'unexpected'], ['--apply'], ['--inspect-retired-fixed'], ['--inspect-retired-fixed-elevated-readonly', '9ad201c0-1e9b-4851-873d-0364f52efa53']]) {
    const run = spawnSync(exe, args, { encoding: 'utf8', windowsHide: true, timeout: 15000 });
    assert.equal(run.status, args.length === 0 || args.length === 1 && ['--plan', '--self-test'].includes(args[0]) ? 0 : 2, run.stdout + run.stderr);
    const result = JSON.parse(run.stdout);
    for (const key of ['native_executed', 'inspection_complete', 'current_rules_absent_verified', 'stop_receipt_verified', 'production_isolation_passed', 'human_gate_passed']) assert.equal(result[key], false);
    assert.equal(result.cleanup_pending, true);
    assert.equal(result.historical_job_empty_verified, null);
    assert.equal(result.job_current_inspection, 'not_performed_original_session_unavailable');
    assert.equal(result.job_current_absent_verified, null);
    assert.equal(result.filters_deleted_count, 0);assert.equal(result.sublayers_deleted_count, 0);
    if (args[0] === '--self-test') { assert.equal(result.pure_assertions, 1028);t.diagnostic(`self-test: ${result.pure_assertions} assertions`); }
  }
  const harnessFile = path.join(tmp, 'pure.cs'), pure = path.join(tmp, 'pure.exe');writeFileSync(harnessFile, harness);
  compile('HereIAm.R7.TaskRetiredInspectPureHarness', pure, [harnessFile]);
  const run = spawnSync(pure, [], { encoding: 'utf8', windowsHide: true, timeout: 15000 });
  assert.equal(run.status, 0, run.stdout + run.stderr);
  const result = JSON.parse(run.stdout);assert.equal(result.native_executed, false);assert.ok(result.pure_assertions >= 190);
  t.diagnostic(`managed harness: ${result.pure_assertions} assertions; no actual WFP, CLI, UAC, Job or network execution`);
});
