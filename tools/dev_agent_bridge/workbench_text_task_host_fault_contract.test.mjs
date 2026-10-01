import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { PassThrough } from 'node:stream';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { hostFaultScope, validateHostFaultReady, validateHostFaultJournals, validateHostFaultFinal, createHostFaultControlReader } from './workbench_text_task_host_fault_contract.mjs';
import { TEXT_TASK_CLI_SHA256 } from './workbench_text_task_runtime_pin.mjs';
function fixture() {
  const attempt='11111111-2222-4333-8444-555555555555',hash='A'.repeat(64);
  const ready={schema:'p6_r7_host_fault_ready_v1',attempt_id:attempt,child_pid:456,child_creation:'1234567891',cli_sha256:TEXT_TASK_CLI_SHA256,
    broker_port:32123,http_created:true,no_model:true,default_three_pipes:true};
  const base={attempt_id:attempt,scope_id:hostFaultScope(attempt),nonce:'B'.repeat(64),auth_mode:'chatgpt',home_class:'dedicated_existing',
    owner_pid:123,owner_creation:'1234567890',owner_sha256:hash,cli_sha256:TEXT_TASK_CLI_SHA256.toUpperCase(),broker_port:32123};
  const prepared={schema:'p6_r7_task_owned_v2',...base,owner_token_digest:'C'.repeat(64),phase:'prepared',child_pid:null,child_creation:null};
  const bound={...prepared,phase:'bound',child_pid:ready.child_pid,child_creation:ready.child_creation};
  const held={held:true,alive:true,pid:123,creation:'1234567890',image_sha256:hash};
  const final={schema:'p6_r7_task_final_receipt_v1',...base,child_pid:ready.child_pid,child_creation:ready.child_creation,
    started:true,close_command_id:0,shutdown_trigger:'input_eof',operation_failed:true,stdout_final_emit_succeeded:false,
    receipt:{process_close_observed:true,job_empty_verified:true,stdio_eof_verified:true,rules_absent_verified:true,
      handles_closed_verified:true,helper_exits_verified:true,cleanup_pending:false},requires_actual_exit_0_or_3:true,
    receipt_write_state:'pending_actual_exit_commit'};
  return {ready,prepared,bound,held,final,hash};
}
test('exact prepared/bound and final identity is structurally valid but pure tests never claim actual evidence',()=>{
  const f=fixture();assert.equal(validateHostFaultReady(f.ready),true);assert.equal(validateHostFaultJournals(f.prepared,f.bound,f.ready,f.held,f.hash),true);
  assert.deepEqual(validateHostFaultFinal(f.final,f.bound,f.held,{nodeKilled:true,nativeExit:3,synthetic:false}),{checks_passed:true,actual_native:false,passed:false});
  for(const value of [f.prepared,f.bound,f.final]){value.owner_sha256=value.owner_sha256.toLowerCase();value.cli_sha256=value.cli_sha256.toLowerCase();}
  assert.equal(validateHostFaultJournals(f.prepared,f.bound,f.ready,f.held,f.hash),true);
  assert.equal(validateHostFaultFinal(f.final,f.bound,f.held,{nodeKilled:true,nativeExit:3}).checks_passed,true);
});
test('wrong binding, reused PID, unheld/dead process, wrong pin and partial journals reject before kill eligibility',()=>{
  for(const mutate of [f=>f.held.creation='1234567892',f=>f.held.pid=999,f=>f.held.held=false,f=>f.held.alive=false,
    f=>f.held.image_sha256='D'.repeat(64),f=>f.bound.nonce='D'.repeat(64),f=>f.bound.child_pid=123,
    f=>f.ready.default_three_pipes=false,f=>delete f.prepared.owner_token_digest,f=>f.prepared.child_pid=456,
    f=>f.bound.scope_id=f.ready.attempt_id,f=>f.bound.auth_mode='no_auth']){
    const f=fixture();mutate(f);assert.throws(()=>validateHostFaultJournals(f.prepared,f.bound,f.ready,f.held,f.hash));
  }
});
test('partial receipt, exit4/0, operation failure trigger, guessed EOF and missing actual kill cannot pass',()=>{
  for(const mutate of [f=>delete f.final.receipt.helper_exits_verified,f=>f.final.receipt.handles_closed_verified=false,
    f=>f.final.receipt.cleanup_pending=true,f=>f.final.shutdown_trigger='operation_failure',f=>f.final.stdout_final_emit_succeeded=true,
    f=>f.final.child_creation='1',f=>f.final.owner_creation='1',f=>f.final.receipt_write_state='complete',
    f=>f.final.extra=true,f=>f.held.creation='1']){
    const f=fixture();mutate(f);assert.throws(()=>validateHostFaultFinal(f.final,f.bound,f.held,{nodeKilled:true,nativeExit:3}));
  }
  for(const nativeExit of [0,4,null,259]){const f=fixture();assert.throws(()=>validateHostFaultFinal(f.final,f.bound,f.held,{nodeKilled:true,nativeExit}));}
  const f=fixture();assert.throws(()=>validateHostFaultFinal(f.final,f.bound,f.held,{nodeKilled:false,nativeExit:3}));
});
test('real LF/CRLF control bytes allow retry after unconfirmed close and never normalize invalid commands',async()=>{
  for(const endings of [['\r\n','\n'],['\n','\r\n']]){
    let attempts=0,confirmed=false;
    const reader=createHostFaultControlReader(()=>{attempts++;confirmed=attempts>=2;});
    const pipe=new PassThrough();pipe.setEncoding('utf8');pipe.on('data',chunk=>reader.push(chunk));
    const write=bytes=>{for(const byte of Buffer.from(bytes))pipe.write(Buffer.from([byte]));};
    write('{"type":"graceful"}'+endings[0]);assert.equal(attempts,1);assert.equal(confirmed,false);
    for(const bad of [' {"type":"graceful"}\n','{"type":"graceful"} \n','{"type":"graceful"}\r\r\n',
      '{"type":"kill"}\n','{"type":"graceful","pid":123}\n','x'.repeat(300)+'\n'])write(bad);
    assert.equal(attempts,1);
    write('{"type":"graceful"}'+endings[1]);assert.equal(attempts,2);assert.equal(confirmed,true);pipe.end();
  }
});
test('standalone witness managed compile and default/self-test remain non-executing', {skip:process.platform!=='win32'},()=>{
  const directory=mkdtempSync(path.join(os.tmpdir(),'p6-host-fault-managed-'));
  try{
    const source=fileURLToPath(new URL('./windows_text_gate_host_fault_witness.cs',import.meta.url));
    const compiler=path.join(process.env.SystemRoot,'Microsoft.NET','Framework64','v4.0.30319','csc.exe');
    const exe=path.join(directory,'witness.exe');
    const compile=spawnSync(compiler,['/nologo','/target:exe','/r:System.Web.Extensions.dll',`/out:${exe}`,source],{encoding:'utf8',windowsHide:true});
    assert.equal(compile.status,0,compile.stdout+compile.stderr);
    for(const args of [[],['--self-test']]){
      const result=spawnSync(exe,args,{encoding:'utf8',windowsHide:true,timeout:10000});
      assert.equal(result.status,0,result.stdout+result.stderr);const report=JSON.parse(result.stdout);assert.equal(report.actual_native,false);
      if(args.length)assert.ok(report.checks>=44);
    }
    assert.ok(readFileSync(source,'utf8').includes('TerminateProcess(nodeHandle,77)'));
  }finally{rmSync(directory,{recursive:true,force:true});}
});
