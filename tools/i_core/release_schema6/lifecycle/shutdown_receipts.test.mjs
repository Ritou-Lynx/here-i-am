import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {existsSync,readFileSync,statSync,mkdirSync} from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {cleanEnvironment} from '../package.mjs';
import {syntheticRoot} from '../../test_fixtures/release_schema6/synthetic_paths.mjs';
import {removeOwned,protect,ps,repository} from './test-fixture.mjs';

const fixture=path.join(repository,'tools/i_core/test_fixtures/release_schema6/probe_shutdown_receipts.ps1');
const source=process.env.S6_SHUTDOWN_SOURCE??path.join(repository,'tools/i_core/release_schema6/lifecycle/session_window.ps1');
function read(file){return existsSync(file)&&statSync(file).isFile()?JSON.parse(readFileSync(file,'utf8')):null;}
function entries(call){return Object.values(call.entries_at_return);}
function assertEntry(entry,message,wparam){
 assert.equal(entry.message,message);
 assert.equal(entry.wparam,wparam);
 assert.equal(entry.lparam,0x40000000);
 assert.equal(entry.entry_flushed,true);
 assert.ok(Date.parse(entry.received_utc)>0);
 for(const key of ['message_id','pid','session_id','thread_id','window_station','desktop'])assert.ok(entry[key]!==undefined&&entry[key]!==null,key);
}
function assertExit(receipt,{clean=true,timeout=false}={}){
 assert.ok(receipt,'session-exit.json must survive immediate host termination');
 assert.equal(receipt.clean_closed,clean);
 assert.equal(receipt.forced_timeout,timeout);
 assert.equal(receipt.worker_completion_confirmed,!timeout);
 assert.equal(receipt.publication_before_handler_return,true);
 assert.equal(receipt.message_receipt_failed,false);
 for(const key of ['core_job_empty_confirmed','backup_job_empty_confirmed','mcp_job_empty_confirmed','mcp_owned_tree_handles_released_confirmed'])assert.equal(receipt[key],true,key);
}
test('synthetic real WndProc preserves shutdown receipts before return without OnFormClosed',{skip:process.platform!=='win32',timeout:180000},async t=>{
 for(const scenario of ['query','end','cancel','repeated','entry-failure','entry-failure-cancel-retry','exit-failure','timeout','final-publication-over-budget'])await t.test(scenario,{timeout:60000},()=>{
  const root=syntheticRoot('schema6-shutdown-receipts-');
  let passed=false;
  protect(root);
  for(const name of ['session','control','state']){const dir=path.join(root,name);mkdirSync(dir);protect(dir);}
  try{
   const child=spawnSync(ps,['-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','Bypass','-File',fixture,'-SessionWindowScript',source,'-Directory',root,'-Scenario',scenario],{env:cleanEnvironment(),windowsHide:true,encoding:'utf8',timeout:50000});
   assert.equal(child.error,undefined,String(child.error));
   const proof=read(path.join(root,'handler-return.json'));
   assert.ok(proof,child.stdout+child.stderr);
   assert.notEqual(child.status,0,'fixture must terminate itself, bypassing orderly disposal');
   assert.equal(proof.application_message_loop_started,false);
   assert.equal(proof.on_form_closed_invoked,false);
   const calls=proof.calls,last=calls.at(-1);
   for(const call of calls)assert.equal(call.error,null,'real WndProc must return normally');
   const exit=read(path.join(root,'session','session-exit.json'));
   if(['end','repeated','timeout'].includes(scenario))assert.equal(last.exit_at_return,true,'END must publish exit before returning, without queued Form.Close');
   if(scenario==='final-publication-over-budget'){
    assert.equal(last.exit_at_return,true);
    assert.equal(last.elapsed_ms>=250,true,'final publication delay belongs to handler execution');
    assert.equal(proof.budget_elapsed_at_return>=30000,true);
    assert.equal(proof.clean_at_return,false);
    assert.equal(proof.forced_timeout_at_return,true);
    assert.equal(exit.elapsed_sampled_before_final_flush,true);
    const overBudget=read(path.join(root,'session','session-exit-over-budget.json'));
    assert.ok(overBudget,'late final publication requires a durable failure receipt');
    assert.equal(overBudget.clean_closed,false);
    assert.equal(overBudget.reason,'session_shutdown_timeout');
    assert.equal(overBudget.budget_ms,30000);
    assert.ok(overBudget.elapsed_ms>=30000);
    assert.equal(overBudget.final_publication_completed,true);
    assert.equal(entries(last).length,1);
    assertEntry(entries(last)[0],'WM_ENDSESSION',1);
   }else if(scenario==='entry-failure-cancel-retry'){
    assert.equal(calls[0].result,0);
    assert.equal(entries(calls[0]).length,0);
    assert.equal(calls[1].exit_at_return,false);
    assert.deepEqual(proof.cancellation_snapshot,{budget_reset:true,closing:0,shutdown_requested:false,message_receipt_failed:false});
    assert.equal(proof.retry_budget_fresh,true,'retry must start a fresh monotonic budget');
    assert.equal(calls[2].result,1);
    assert.equal(last.exit_at_return,true);
    for(let i=1;i<calls.length;i++){
     const received=entries(calls[i]);assert.equal(received.length,i);
     const kind=calls[i].message===17?'WM_QUERYENDSESSION':'WM_ENDSESSION';
     assert.ok(received.some(entry=>entry.message===kind&&entry.wparam===calls[i].wparam));
     for(const entry of received)assertEntry(entry,entry.message,entry.wparam);
    }
    assertExit(exit);assert.equal(proof.clean_at_return,true);
   }else if(scenario==='entry-failure'){
    assert.equal(calls[0].result,0,'QUERY cannot approve when its durable entry failed');
    assert.equal(calls[0].exit_at_return,false);
    assert.equal(proof.clean_at_return,false);
   }else{
    for(let i=0;i<calls.length;i++){
     const call=calls[i],receipts=entries(call);
     assert.equal(receipts.length,i+1,'each message entry must be readable before its handler returns');
     const matching=receipts.filter(entry=>entry.message===(call.message===17?'WM_QUERYENDSESSION':'WM_ENDSESSION')&&entry.wparam===call.wparam);
     assert.ok(matching.length);
     assertEntry(matching.at(-1),call.message===17?'WM_QUERYENDSESSION':'WM_ENDSESSION',call.wparam);
     if(call.message===17){assert.equal(call.result,1);assert.ok(call.elapsed_ms<1000,'QUERY acknowledges its durable entry promptly');}
    }
    if(scenario==='query'||scenario==='cancel'){
     assert.equal(last.exit_at_return,false);assert.equal(exit,null);
     if(scenario==='cancel')assert.equal(proof.shutdown_cancelled_at_return,true);
    }else if(scenario==='exit-failure'){
     assert.equal(last.exit_at_return,false);
     assert.equal(proof.clean_at_return,false,'failed final publication cannot claim clean completion');
     assert.equal(proof.reason_at_return,'session_exit_receipt_write_failed');
    }else{
     assert.equal(last.exit_at_return,true,'END must publish exit before returning, without queued Form.Close');
     assertExit(exit,{clean:scenario!=='timeout',timeout:scenario==='timeout'});
     assert.equal(proof.clean_at_return,scenario!=='timeout');
     if(scenario==='timeout'){
      assert.equal(proof.forced_timeout_at_return,true);
      assert.ok(last.elapsed_ms>=28000&&last.elapsed_ms<=33000,'unfinished worker is bounded by the real 30s close budget');
     }
     if(scenario==='repeated'){
      assert.equal(calls[2].exit_at_return,true);
      const ids=entries(last).map(entry=>entry.message_id);
      assert.equal(new Set(ids).size,4,'repeated messages retain unique entries');
     }
    }
   }
   passed=true;
  }finally{
   if(passed)removeOwned(root,'schema6-shutdown-receipts-');
   else t.diagnostic('synthetic_shutdown_artifacts_retained='+root);
  }
 });
});
