// Explicit synthetic-only measurement; never reads deployment config or real data.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync,statSync} from 'node:fs';
import path from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {cleanEnvironment,sha256} from '../../../release_schema6/package.mjs';
import {createRuntimeLab,host,loginConfig,configureManagedMcp,connectManaged,shutdownAndMeasure,mcpStopped,cleanReceipt,json,ps,repository} from '../../../release_schema6/lifecycle/mcp-session-test-fixture.mjs';
import {seedScale,SCALE_CASES} from '../recovery/scale_fixture.mjs';
assert.equal(process.platform,'win32');
assert.ok(process.argv.includes('--synthetic-mcp-only'),'explicit synthetic acknowledgement required');
const names=process.argv.filter(n=>n==='ten'||n==='fifty');assert.ok(names.length);
for(const name of names){
 const callbacks=[],t={after:fn=>callbacks.push(fn),diagnostic:value=>console.log(JSON.stringify({syntheticDiagnostic:value}))},l=await createRuntimeLab(t);
 try{
  const c=loginConfig(l),mcp=await configureManagedMcp(l,c,{graceMs:3000}),run=await host(l,c),first=await run.ready(),file=path.join(l.state,'i-core.sqlite');
  const mutate=fn=>{const db=new DatabaseSync(file);try{return fn(db);}finally{db.close();}};
  const nodeId=mutate(db=>db.prepare("SELECT value FROM core_metadata WHERE key='node_id'").get().value);
  const f={root:l.root,state:l.state,release:l.release,nodeId,mutate,o:{databasePath:file}};
  const counts=seedScale(f,SCALE_CASES[name]);const sample=mutate(db=>db.prepare('SELECT content FROM chat_messages LIMIT 1').get().content.slice(0,12));const reader=await connectManaged(run,mcp,{requireMessage:false});assert.ok((await reader.recall(sample)).body.result.structuredContent.messages.count>0,'real MCP must read the seeded random synthetic messages');
  const totalMs=await shutdownAndMeasure(run);cleanReceipt(run);const stop=mcpStopped(run),close=run.read('session-close.json');
  assert.equal(close.clean_closed,true);assert.equal(close.database_exclusive_open_confirmed,true);assert.ok(totalMs<30000);assert.ok(close.elapsed_ms<=30000);
  console.log(JSON.stringify({phase:'mcp_and_core_shutdown',name,counts,manifestSha256:l.manifestHash,sourceSha256:sha256(readFileSync(path.join(l.release,'tools/i_core/release_schema6/lifecycle/session_window.ps1'))),databaseBytes:statSync(file).size,externalTotalMs:totalMs,sessionTotalMs:close.elapsed_ms,mcpStopMs:stop.elapsed_ms,coreCloseMs:close.core_close_elapsed_ms,backupStopMs:close.backup_stop_elapsed_ms,mcpForced:stop.forced,coreForced:close.core_forced,cleanClosed:true,realMcpRequestOpened:true}));
  const next=await host(l,c,{initial:false}),beforeCrash=await next.ready();await connectManaged(next,mcp,{requireMessage:false});const oldControl=next.control;
  const begin=performance.now();
  const killed=JSON.parse(execFileSync(ps,['-NoProfile','-NonInteractive','-File',path.join(repository,'tools/i_core/test_fixtures/release_schema6/suspend_synthetic_core.ps1'),'-ProcessId',String(beforeCrash.pid),'-Executable',path.join(l.release,'runtime/node.exe'),'-RunId',beforeCrash.token,'-Action','Kill'],{windowsHide:true,env:cleanEnvironment(),encoding:'utf8'}));assert.equal(killed.synthetic_core_killed,true);
  const recovered=await next.ready(oldControl);await connectManaged(next,mcp,{requireMessage:false});
  const recoveryMs=Number((performance.now()-begin).toFixed(3)),oldStop=json(path.join(oldControl,'mcp-stop.json'));
  assert.equal(oldStop.job_empty_confirmed,true);assert.equal(oldStop.owned_tree_handles_released_confirmed,true);
  const afterRecoveryCloseMs=await shutdownAndMeasure(next);cleanReceipt(next);mcpStopped(next);assert.ok(afterRecoveryCloseMs<30000);l.completed=true;
  console.log(JSON.stringify({phase:'mcp_and_core_crash_recovery',name,counts,recoveryAndMcpReadyMs:recoveryMs,priorMcpStopMs:oldStop.elapsed_ms,afterRecoveryCloseMs,schema:recovered.health.schema_version,cleanClosed:true,allOwnedJobsExited:true}));
 }finally{for(const callback of callbacks.reverse())await callback();}
}
