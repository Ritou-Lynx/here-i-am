import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync,readFileSync,writeFileSync,rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { PassThrough } from 'node:stream';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { INFLIGHT_FIXED_INPUT,validateInflightInitial,validateInflightReady,makeInflightReady,
  observeInflightExchange,createInflightControlReader,validateHostFaultFinal } from './workbench_text_task_inflight_host_fault_contract.mjs';
import { hostFaultScope } from './workbench_text_task_host_fault_contract.mjs';
import { TEXT_TASK_CLI_SHA256 } from './workbench_text_task_runtime_pin.mjs';
const uuid='11111111-2222-4333-8444-555555555555';
const fixture=()=>{
  const initial={schema:'p6_r7_inflight_initial_v1',local_session_id:uuid,execution_epoch:uuid,provider_thread_id:uuid,
    native_ready:{schema:'p6_r7_host_fault_ready_v1',attempt_id:uuid,child_pid:456,child_creation:'1234567891',
      cli_sha256:TEXT_TASK_CLI_SHA256,broker_port:32123,http_created:true,no_model:true,default_three_pipes:true}};
  const turn={local_session_id:uuid,execution_epoch:uuid,provider_thread_id:uuid,local_turn_id:uuid,provider_turn_id:uuid};
  const state={closing:false,turns:1,arms:1,dispatched:true,exchange:{entered:1,settled:false},terminalObserved:false,textObserved:false,
    events:{status:'ready',events:[]},broker:{rejected_connections:0,rejected_requests:0,metadata_rejections:2,parsed_requests:3,
      upstream_attempts:1,response_released:false}};
  return {initial,turn,state};
};
test('ready binds initial HTTP/native session and declares only a non-atomic local exchange observation',()=>{
  const f=fixture();assert.equal(validateInflightInitial(f.initial),true);
  const ready=makeInflightReady(f.initial,f.turn,f.state);assert.equal(validateInflightReady(ready,f.initial),true);
  assert.equal(ready.snapshot_claim,'local_exchange_pending_at_ready');assert.equal(Object.isFrozen(ready),true);
  assert.equal(INFLIGHT_FIXED_INPUT,'Reply exactly: P6_R7_NATIVE_OK');
  for(const field of ['local_session_id','execution_epoch','provider_thread_id']){
    const changed={...f.turn,[field]:'wrong'};assert.throws(()=>makeInflightReady(f.initial,changed,f.state));
  }
  for(const [key,value] of Object.entries({attempt_id:'other',start_command_id:2,exchange_entered:0,exchange_settled:true,
    turn_start_dispatched:false,terminal_observed:true,text_observed:true,response_released:true,upstream_attempts:2,
    default_three_pipes:false,snapshot_claim:'remote_running',provider_turn_id:'identifier\n',extra:true}))
    assert.throws(()=>validateInflightReady({...ready,[key]:value},f.initial));
});
test('actual readiness builder rejects settled/failed/terminal/text/closing and duplicate dispatch or arm',()=>{
  for(const change of [s=>s.closing=true,s=>s.turns=2,s=>s.arms=0,s=>s.dispatched=false,s=>s.exchange.entered=0,
    s=>s.exchange.settled=true,s=>s.terminalObserved=true,s=>s.textObserved=true,s=>s.events.status='failed',
    s=>s.events.events=[{kind:'message_delta'}],s=>s.broker.rejected_connections=1,s=>s.broker.rejected_requests=1,
    s=>s.broker.response_released=true,s=>s.broker.upstream_attempts=2,s=>s.broker.parsed_requests=2,
    s=>s.broker.metadata_rejections=9]){
    const f=fixture();change(f.state);assert.throws(()=>makeInflightReady(f.initial,f.turn,f.state));
  }
});
test('real wrapper forwards argument identity, rejection and AbortSignal; settled results cannot be parked as pending',async()=>{
  const body={},controller=new AbortController(),options={signal:controller.signal};let finish,seen;
  const tracked=observeInflightExchange((...args)=>{seen=args;return new Promise(resolve=>finish=resolve);});
  const pending=tracked.exchange(body,options);assert.equal(seen[0],body);assert.equal(seen[1],options);
  assert.deepEqual(tracked.snapshot(),{entered:1,settled:false});finish('value');assert.equal(await pending,'value');
  assert.deepEqual(tracked.snapshot(),{entered:1,settled:true});await assert.rejects(tracked.exchange(body,options));
  const error=new Error('synthetic');const rejected=observeInflightExchange(()=>Promise.reject(error));
  await assert.rejects(rejected.exchange(body,options),value=>value===error);assert.equal(rejected.snapshot().settled,true);
  const sync=observeInflightExchange(()=>{throw error;});await assert.rejects(sync.exchange());assert.equal(sync.snapshot().settled,true);
  const cancelled=observeInflightExchange((_,{signal})=>new Promise((resolve,reject)=>signal.addEventListener('abort',()=>reject(error))));
  const abort=cancelled.exchange(body,options);controller.abort();await assert.rejects(abort);assert.equal(cancelled.snapshot().settled,true);
  const immediate=observeInflightExchange(()=>Promise.resolve('already done'));await immediate.exchange();
  const f=fixture();f.state.exchange=immediate.snapshot();assert.throws(()=>makeInflightReady(f.initial,f.turn,f.state));
});
test('fragmented LF/CRLF permits only one fixed start and repeatable graceful retry; close permanently fences start',()=>{
  for(const newline of ['\n','\r\n']){
    let starts=0,closes=0;const reader=createInflightControlReader({onStart:()=>starts++,onGraceful:()=>closes++});
    const pipe=new PassThrough();pipe.setEncoding('utf8');pipe.on('data',chunk=>reader.push(chunk));
    const send=value=>{for(const byte of Buffer.from(value))pipe.write(Buffer.from([byte]));};
    for(const invalid of [' {"type":"start_turn"}\n','{"type":"start_turn"}\r\r\n','{"type":"start_turn","input":"other"}\n',
      'x'.repeat(300)+'{"type":"start_turn"}\n','{"type":"kill"}\n'])send(invalid);
    assert.equal(starts,0);send('{"type":"start_turn"}'+newline);send('{"type":"start_turn"}'+newline);assert.equal(starts,1);
    send('{"type":"graceful"}'+newline);send('x'.repeat(300)+'\n');send('{"type":"graceful"}'+newline);assert.equal(closes,2);pipe.end();
  }
  let starts=0;const closed=createInflightControlReader({onStart:()=>starts++,onGraceful:()=>{}});
  closed.push('{"type":"graceful"}\n{"type":"start_turn"}\n');assert.equal(starts,0);
});
test('native durable adoption still requires all six closure facts, exact actual exit3 and original EOF binding',()=>{
  const binding={attempt_id:uuid,scope_id:hostFaultScope(uuid),nonce:'B'.repeat(64),auth_mode:'chatgpt',home_class:'dedicated_existing',
    owner_pid:123,owner_creation:'1234567890',owner_sha256:'A'.repeat(64),cli_sha256:TEXT_TASK_CLI_SHA256,broker_port:32123,
    child_pid:456,child_creation:'1234567891'};
  const facts=['process_close_observed','job_empty_verified','stdio_eof_verified','rules_absent_verified','handles_closed_verified','helper_exits_verified'];
  const receipt=Object.fromEntries(facts.map(key=>[key,true]));receipt.cleanup_pending=false;
  const final={schema:'p6_r7_task_final_receipt_v1',...binding,started:true,close_command_id:0,shutdown_trigger:'input_eof',
    operation_failed:true,stdout_final_emit_succeeded:false,receipt,requires_actual_exit_0_or_3:true,receipt_write_state:'pending_actual_exit_commit'};
  const held={held:true,pid:123,creation:binding.owner_creation,image_sha256:binding.owner_sha256};
  assert.deepEqual(validateHostFaultFinal(final,binding,held,{nodeKilled:true,nativeExit:3}),{checks_passed:true,actual_native:false,passed:false});
  for(const key of facts){receipt[key]=false;assert.throws(()=>validateHostFaultFinal(final,binding,held,{nodeKilled:true,nativeExit:3}));receipt[key]=true;}
  for(const exit of [null,0,4,259])assert.throws(()=>validateHostFaultFinal(final,binding,held,{nodeKilled:true,nativeExit:exit}));
  assert.throws(()=>validateHostFaultFinal(final,binding,{...held,creation:'1'},{nodeKilled:true,nativeExit:3}));
});
test('BOM is allowed exactly once at absolute stream start, never as command whitespace or later-frame normalization',()=>{
  for(const prefix of ['', '\uFEFF']) {
    let starts=0,closes=0;const reader=createInflightControlReader({onStart:()=>starts++,onGraceful:()=>closes++});
    reader.push('');for(const ch of prefix+'{"type":"start_turn"}\r\n{"type":"graceful"}\n')reader.push(ch);
    assert.equal(starts,1);assert.equal(closes,1);
  }
  for(const invalid of ['\uFEFF\uFEFF{"type":"start_turn"}\n',' \uFEFF{"type":"start_turn"}\n',
    '\n\uFEFF{"type":"start_turn"}\n','{"type":"start_\uFEFFturn"}\n','\uFEFF {"type":"start_turn"}\n',
    'x'.repeat(300)+'\n\uFEFF{"type":"start_turn"}\n']) {
    let starts=0;const reader=createInflightControlReader({onStart:()=>starts++,onGraceful:()=>{}});reader.push(invalid);assert.equal(starts,0);
    reader.push('{"type":"start_turn"}\n');assert.equal(starts,1);
  }
  let closes=0;const reader=createInflightControlReader({onStart:()=>{},onGraceful:()=>closes++});
  reader.push('\uFEFF{"type":"start_turn"}\n\uFEFF{"type":"graceful"}\n');assert.equal(closes,0);
  reader.push('{"type":"graceful"}\n');assert.equal(closes,1);
});
test('real Framework redirected UTF8 BOM first write reaches the real Node control reader and starts exactly once',{skip:process.platform!=='win32'},()=>{
  const base=path.resolve(os.tmpdir()),directory=mkdtempSync(path.join(base,'p6-inflight-control-bom-'));
  try {
    const script=path.join(directory,'reader.mjs');
    writeFileSync(script,`import {StringDecoder} from 'node:string_decoder';
import {createInflightControlReader} from ${JSON.stringify(new URL('./workbench_text_task_inflight_host_fault_contract.mjs',import.meta.url).href)};
const decoder=new StringDecoder('utf8');let starts=0,closes=0;const bytes=[];
const reader=createInflightControlReader({onStart:()=>starts++,onGraceful:()=>{closes++;process.stdout.write(JSON.stringify({starts,closes,bytes}),()=>process.exit(0));}});
process.stdin.on('data',chunk=>{bytes.push(...chunk);reader.push(decoder.write(chunk));});
`);
    const source=path.join(directory,'probe.cs'),exe=path.join(directory,'probe.exe');
    writeFileSync(source,`using System;using System.Diagnostics;using System.Text;using System.Reflection;
class Probe { static int Main(string[] args){
// Test-only cache injection avoids changing the parent's Windows console code
// page. Process.Start still constructs its actual StandardInput from the actual
// Console.InputEncoding accessor, as in the confirmed UTF8 production wrapper.
var prior=Console.InputEncoding;var field=typeof(Console).GetField("_inputEncoding",BindingFlags.Static|BindingFlags.NonPublic);
if(field==null)return 2;field.SetValue(null,new UTF8Encoding(true));
try{var info=new ProcessStartInfo{FileName=args[0],Arguments="\\\""+args[1]+"\\\"",UseShellExecute=false,CreateNoWindow=true,RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true};
using(var p=Process.Start(info)){try{var writer=p.StandardInput;if(BitConverter.ToString(writer.Encoding.GetPreamble())!="EF-BB-BF")return 3;
writer.NewLine="\\n";writer.WriteLine("{\\\"type\\\":\\\"start_turn\\\"}");writer.Flush();writer.WriteLine("{\\\"type\\\":\\\"graceful\\\"}");writer.Flush();
if(!p.WaitForExit(5000))return 4;Console.WriteLine(p.StandardOutput.ReadToEnd());return p.ExitCode;
}finally{if(!p.HasExited){p.Kill();p.WaitForExit();}}}}finally{field.SetValue(null,prior);}}
}`);
    const compiler=path.join(process.env.SystemRoot,'Microsoft.NET','Framework64','v4.0.30319','csc.exe');
    const compile=spawnSync(compiler,['/nologo','/warnaserror+','/target:exe',`/out:${exe}`,source],{encoding:'utf8',windowsHide:true});
    assert.equal(compile.status,0,compile.stdout+compile.stderr);
    const result=spawnSync(exe,[process.execPath,script],{encoding:'utf8',windowsHide:true,timeout:15000,
      env:{...process.env,NODE_OPTIONS:'',NODE_PATH:''}});
    assert.equal(result.status,0,result.stdout+result.stderr);const report=JSON.parse(result.stdout);
    assert.equal(report.starts,1);assert.equal(report.closes,1);
    assert.deepEqual(report.bytes,[239,187,191,...Buffer.from('{"type":"start_turn"}\n{"type":"graceful"}\n')]);
  } finally {
    assert.equal(path.dirname(path.resolve(directory)),base);assert.ok(path.basename(directory).startsWith('p6-inflight-control-bom-'));
    rmSync(directory,{recursive:true,force:true});
  }
});
test('standalone witness compiles warning-free; plan and managed self-test cannot start native resources',{skip:process.platform!=='win32'},()=>{
  const base=path.resolve(os.tmpdir()),directory=mkdtempSync(path.join(base,'p6-inflight-host-fault-'));
  try {
    const source=fileURLToPath(new URL('./windows_text_gate_inflight_host_fault_witness.cs',import.meta.url));
    const compiler=path.join(process.env.SystemRoot,'Microsoft.NET','Framework64','v4.0.30319','csc.exe');
    const exe=path.join(directory,'witness.exe');
    const compile=spawnSync(compiler,['/nologo','/warnaserror+','/platform:x64','/target:exe','/r:System.Web.Extensions.dll',`/out:${exe}`,source],{encoding:'utf8',windowsHide:true});
    assert.equal(compile.status,0,compile.stdout+compile.stderr);
    for(const args of [[],['--plan'],['--self-test']]){
      const result=spawnSync(exe,args,{encoding:'utf8',windowsHide:true,timeout:10000});assert.equal(result.status,0,result.stdout+result.stderr);
      const report=JSON.parse(result.stdout);assert.equal(report.actual_native,false);if(args[0]==='--self-test')assert.ok(report.checks>=66);
    }
    const candidate=readFileSync(source,'utf8');assert.equal((candidate.match(/Win.TerminateProcess\(/g)||[]).length,1);
    assert.ok(candidate.includes('Win.TerminateProcess(nodeHandle,77)'));assert.ok(candidate.includes('Check.Inflight(inflight,initial)'));
  } finally {
    assert.equal(path.dirname(path.resolve(directory)),base);assert.ok(path.basename(directory).startsWith('p6-inflight-host-fault-'));
    rmSync(directory,{recursive:true,force:true});
  }
});
