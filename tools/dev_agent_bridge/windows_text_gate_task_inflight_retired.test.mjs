import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,rmSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const local=name=>fileURLToPath(new URL(name,import.meta.url));
const source=local('./windows_text_gate_task_inflight_retired.cs');
const report=local('../../tmp/p6-r7-review/inflight-http-interrupt-02.json');
const code=readFileSync(source,'utf8');
const csc=String.raw`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`;
const deps=[
  local('./windows_text_gate_isolation_helper.cs'),
  local('./windows_text_gate_appid_startup_helper.cs'),
  local('../../tmp/p6-r7-review/native-appid-coordinator-candidate-15.cs'),
  local('../../tmp/p6-r7-review/native-appid-matrix-contract-01.cs'),
  local('./windows_text_gate_appid_matrix_native.cs'),
  local('../../tmp/p6-r7-review/native-task-executor-07.cs'),
];
const hashes=['d22017641d9f8df750f6db7db9319b8c1930a726a8575ff1ffabfde0d5ffdcd8','c777023495ccdbf3b52663f49683f5d84dcfd03a36b3d280a75c925f37b7a1ea','c1f07e9487b8ce25d0acc2d5bbb03b69c975cbb7e448698d288ff6263cff9311','f70ffb86ce5efea2572532e1986f77dde9622893ad4b90a74f9ec40da5ba6774','f2d3b35a1e6d1763930ba7f9a82ab8dbb595e02d5d720216a0161dbce8a0d0ab','47d3da743598e17f92f2b3b7764226376097d015a7e337c3f27a9e7d8fbd5f92'];
const hash=file=>createHash('sha256').update(readFileSync(file)).digest('hex');

test('all fixed metadata pins match the independently captured failure inventory',()=>{
  const inventory=JSON.parse(readFileSync(local('../../tmp/p6-r7-review/inflight-interrupt-retired-inputs-01.json'),'utf8'));
  assert.equal(inventory.attempt_id,'6946c568-0440-4574-8fbc-2d069b071c6c');
  const names={'prepared.json':'PreparedHash','spawning.json':'SpawningHash','bound.json':'BoundHash',
    'install-receipt.json':'InstallHash','install-ready.json':'LeaseHash','install-ack.json':'LeaseHash',
    'closed.json':'ClosedHash','final-receipt.json':'FinalHash'};
  assert.equal(inventory.hashes.length,Object.keys(names).length);
  for(const item of inventory.hashes){
    assert.ok(Object.hasOwn(names,item.name));
    const literal=code.match(new RegExp('const string '+names[item.name]+'="([a-f0-9]{64})"'))?.[1];
    assert.equal(literal,item.sha256.toLowerCase(),item.name);
  }
});

test('inflight retirement stays fixed, fail-closed, and non-executing in pure modes',()=>{
  for(let i=0;i<deps.length;i++) assert.equal(hash(deps[i]),hashes[i]);
  assert.equal(hash(report),'f697df1bd14f3555b94da90cbfd09b026ece6fa7541f516ad79c58dd140b5f99');
  for(const text of ['6946c568-0440-4574-8fbc-2d069b071c6c','b313153a-b5bb-2fe8-cbe1-ba150d3de67c','"closed.json"','"final-receipt.json"','"close_command"','"rules_absent_verified","helper_exits_verified"','Object.Equals(a["native_owner_exit_code"],4)']) assert.ok(code.includes(text),text);
  assert.match(code,/args\.Length==1&&\(args\[0\]=="--inspect"\|\|args\[0\]=="--apply-cleanup"\)/);
  assert.doesNotMatch(code,/CreateProcess|TerminateProcess|TerminateJob|OpenJobObject|FwpmFilterAdd|FwpmSubLayerAdd|WriteAll|Process\.Start/);
  const dir=mkdtempSync(path.join(local('../../tmp/p6-r7-helper/'),'inflight-retired-pure-'));
  try {
    const exe=path.join(dir,'candidate.exe');
    const harness=path.join(dir,'harness.cs');
    writeFileSync(harness,`using System;using System.Collections.Generic;namespace HereIAm.R7 { public static class InflightRetiredPure { static void Reject(Action a){bool bad=false;try{a();}catch{bad=true;}if(!bad)throw new Exception("accepted");} static string Json(Dictionary<string,object> x){return TaskJson.Json(x);} public static int Main(string[] args){string raw=System.IO.File.ReadAllText(args[0]);TaskInflightRetiredProgram.CaptureHistory(raw);var p=new Dictionary<string,object>{{"schema","p6_r7_task_owned_v2"},{"attempt_id",TaskInflightRetiredProgram.Attempt.ToString("D")},{"scope_id",TaskInflightRetiredProgram.Scope.ToString("D")},{"auth_mode","chatgpt"},{"home_class","dedicated_existing"},{"nonce",new string('a',64)},{"owner_pid",TaskInflightRetiredProgram.OwnerPid},{"owner_creation",TaskInflightRetiredProgram.OwnerCreation.ToString()},{"owner_sha256",TaskInflightRetiredProgram.ImageHash},{"owner_token_digest",new string('b',64)},{"cli_sha256",TaskInflightRetiredProgram.CliHash},{"broker_port",TaskInflightRetiredProgram.BrokerPort},{"phase","prepared"},{"child_pid",null},{"child_creation",null}};var spawning=new Dictionary<string,object>(p);spawning["phase"]="spawning";var bound=new Dictionary<string,object>(p);bound["phase"]="bound";bound["child_pid"]=TaskInflightRetiredProgram.ChildPid;bound["child_creation"]=TaskInflightRetiredProgram.ChildCreation.ToString();var lease=TaskRecords.Lease(p,"install",TaskInflightRetiredProgram.HelperPid,TaskInflightRetiredProgram.HelperCreation,new string('c',64));var install=TaskRecords.Receipt(p,"install",TaskInflightRetiredProgram.HelperPid,TaskInflightRetiredProgram.HelperCreation,TaskInflightRetiredProgram.BlobDigest,TaskInflightRetiredProgram.AssignedWeight);var closed=new Dictionary<string,object>(bound);closed["phase"]="closed";var receipt=new Dictionary<string,object>{{"process_close_observed",true},{"job_empty_verified",true},{"stdio_eof_verified",true},{"rules_absent_verified",false},{"handles_closed_verified",true},{"helper_exits_verified",false},{"cleanup_pending",true}};var final=new Dictionary<string,object>{{"schema","p6_r7_task_final_receipt_v1"},{"attempt_id",p["attempt_id"]},{"scope_id",p["scope_id"]},{"nonce",p["nonce"]},{"auth_mode",p["auth_mode"]},{"home_class",p["home_class"]},{"owner_pid",p["owner_pid"]},{"owner_creation",p["owner_creation"]},{"owner_sha256",p["owner_sha256"]},{"cli_sha256",p["cli_sha256"]},{"broker_port",p["broker_port"]},{"child_pid",TaskInflightRetiredProgram.ChildPid},{"child_creation",TaskInflightRetiredProgram.ChildCreation.ToString()},{"started",true},{"close_command_id",1},{"shutdown_trigger","close_command"},{"operation_failed",false},{"stdout_final_emit_succeeded",true},{"receipt",receipt},{"requires_actual_exit_0_or_3",true},{"receipt_write_state","pending_actual_exit_commit"}};TaskInflightRetiredProgram.History(Json(p),Json(spawning),Json(bound),Json(lease),Json(lease),Json(install),Json(closed),Json(final));var value=TaskJson.Parse(raw);value["native_owner_exit_code"]=3;Reject(delegate{TaskInflightRetiredProgram.CaptureHistory(TaskJson.Json(value));});value=TaskJson.Parse(raw);value["cleanup_pending"]=false;Reject(delegate{TaskInflightRetiredProgram.CaptureHistory(TaskJson.Json(value));});value=TaskJson.Parse(raw);value.Remove("rules_absent_verified");Reject(delegate{TaskInflightRetiredProgram.CaptureHistory(TaskJson.Json(value));});closed["phase"]="bound";Reject(delegate{TaskInflightRetiredProgram.History(Json(p),Json(spawning),Json(bound),Json(lease),Json(lease),Json(install),Json(closed),Json(final));});closed["phase"]="closed";receipt["cleanup_pending"]=false;Reject(delegate{TaskInflightRetiredProgram.History(Json(p),Json(spawning),Json(bound),Json(lease),Json(lease),Json(install),Json(closed),Json(final));});Console.WriteLine("{\\"pure_assertions\\":7,\\"native_executed\\":false}");return 0;} } }`);
    for(const main of ['HereIAm.R7.TaskInflightRetiredProgram','HereIAm.R7.InflightRetiredPure']) {
      const out=main.endsWith('Pure')?path.join(dir,'pure.exe'):exe;
      const extra=main.endsWith('Pure')?[harness]:[];
      const build=spawnSync(csc,['/nologo','/platform:x64','/warnaserror+','/target:exe','/reference:System.Web.Extensions.dll',`/main:${main}`,`/out:${out}`,...deps,source,...extra],{encoding:'utf8',windowsHide:true,timeout:30_000});
      assert.equal(build.status,0,build.stdout+build.stderr);
    }
    for(const args of [[],['--plan'],['--self-test'],['--inspect','extra'],['--apply-cleanup','extra']]) {
      const run=spawnSync(exe,args,{encoding:'utf8',windowsHide:true,timeout:15_000});
      assert.equal(run.status,args.length===0||args[0]==='--plan'||args[0]==='--self-test'?0:2,run.stdout+run.stderr);
      const output=JSON.parse(run.stdout); assert.equal(output.native_executed,false); assert.equal(output.cleanup_pending,true); assert.equal(output.historical_stop_receipt_verified,false);
    }
    const pure=spawnSync(path.join(dir,'pure.exe'),[report],{encoding:'utf8',windowsHide:true,timeout:15_000});
    assert.equal(pure.status,0,pure.stdout+pure.stderr); assert.deepEqual(JSON.parse(pure.stdout),{pure_assertions:7,native_executed:false});
  } finally { rmSync(dir,{recursive:true,force:true}); }
});



