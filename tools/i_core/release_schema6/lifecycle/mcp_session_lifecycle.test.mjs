import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {existsSync,readFileSync,readdirSync,statSync,writeFileSync} from 'node:fs';
import path from 'node:path';
import {createServer as createNetServer} from 'node:net';
import test from 'node:test';
import {cleanEnvironment,sha256} from '../package.mjs';
import {createRuntimeLab,until,health,cleanReceipt,ps,repository,json,loginConfig,loginArgs,refreshLogin,configureManagedMcp,host,seedSyntheticChat,connectManaged,processGone,shutdownAndMeasure,mcpStopped} from './mcp-session-test-fixture.mjs';
import {verifyLegacySourceInventory,createSyntheticReaderState,startLegacyMcpReader} from '../../test_fixtures/release_schema6/mcp_reader/helper.mjs';
const options={skip:process.platform!=='win32',timeout:600000};
test('legacy MCP exact source closure matches the audited production entry bytes',()=>{
 const inventory=verifyLegacySourceInventory();assert.equal(inventory.entry_sha256,'adfc88126c6d7ee047fd7fed7eda6b3b536c9e1fe0baffafbedc290b6c5554d6');assert.equal(inventory.files.length,6);
});
test('real unmanaged legacy MCP read model reproduces non-quiescent Core shutdown',options,async t=>{
 const l=await createRuntimeLab(t),c=loginConfig(l),run=await host(l,c),ready=await run.ready();await seedSyntheticChat(l,ready,'unmanaged');
 const state=createSyntheticReaderState({syntheticRoot:l.root,coreDbPath:path.join(l.state,'i-core.sqlite')});
 const reader=await startLegacyMcpReader({state,nodePath:path.join(l.release,'runtime/node.exe'),coreUrl:'http://127.0.0.1:'+ready.address.port});
 t.after(()=>reader.close());
 const begun=performance.now();assert.equal(run.send(17).result,1);await run.wait();const elapsed=Number((performance.now()-begun).toFixed(3));
 assert.notEqual(run.exit,0);assert.notEqual(run.read('session-close.json')?.clean_closed,true);
 assert.equal(run.read('child.json')?.error_code,'offline_probe_failed','Windows rejects the still-open DB handle before the later strict sidecar gate');
 assert.equal(processGone(reader.child.pid),false,'unmanaged real MCP must still hold its model');
 assert.ok(existsSync(state.coreDbPath+'-wal')||existsSync(state.coreDbPath+'-shm'));
 const blocked=l.launch();await blocked.wait();assert.notEqual(blocked.exit,0);assert.equal(blocked.read('child.json')?.error_code,'offline_probe_failed','live external reader also blocks next-start recovery before file replacement');
 await reader.close();
 const recovered=l.launch(),after=await recovered.ready();assert.equal((await health(after)).status,200);recovered.stop();await recovered.wait();cleanReceipt(recovered);l.completed=true;
 t.diagnostic('unmanaged_reader_reproduction=offline_probe_failed_with_remaining_sidecars;close_total_ms='+elapsed);
});
test('managed unchanged MCP starts after Core ready and request-opened reader permits clean shutdown and next login',options,async t=>{
 const l=await createRuntimeLab(t),c=loginConfig(l),mcp=await configureManagedMcp(l,c),run=await host(l,c),ready=await run.ready();
 const seeded=await seedSyntheticChat(l,ready,'managed');const reader=await connectManaged(run,mcp);
 assert.ok(JSON.stringify(reader.firstRecall.body).includes(seeded.syncId));
 const start=run.read('mcp-start.json');assert.equal(start.core_token,ready.token);
 assert.ok(statSync(path.join(run.control,'mcp-start.json')).mtimeMs>=statSync(path.join(run.control,'ready.json')).mtimeMs);
 const elapsed=await shutdownAndMeasure(run);cleanReceipt(run);const stopped=mcpStopped(run),close=run.read('session-close.json');
 assert.equal(close.clean_closed,true);assert.ok(elapsed<30000,'whole MCP + Core shutdown must stay within 30 seconds');
 for(const suffix of ['-wal','-shm','-journal'])assert.equal(existsSync(mcp.state.coreDbPath+suffix),false,suffix);
 const restart=await host(l,c,{initial:false}),newReady=await restart.ready(),newReader=await connectManaged(restart,mcp);
 assert.ok(JSON.stringify(newReader.firstRecall.body).includes(seeded.syncId));assert.notEqual(restart.read('mcp-start.json').pid,start.pid);
 const restartClose=await shutdownAndMeasure(restart);cleanReceipt(restart);mcpStopped(restart);l.completed=true;
 t.diagnostic('managed_normal_close_total_ms='+elapsed+';mcp_stop_ms='+stopped.elapsed_ms+';session_budget_ms='+close.elapsed_ms+';next_login_close_ms='+restartClose+';schema='+newReady.health.schema_version);
});
test('Core crash stops request-opened MCP tree before recovery replacement and restarts MCP against recovered database',options,async t=>{
 const l=await createRuntimeLab(t),c=loginConfig(l),mcp=await configureManagedMcp(l,c),run=await host(l,c),ready=await run.ready();
 const seeded=await seedSyntheticChat(l,ready,'recovery');await connectManaged(run,mcp);const oldControl=run.control,oldStart=run.read('mcp-start.json');
 const recoveryBegin=performance.now();
 const killed=JSON.parse(execFileSync(ps,['-NoProfile','-NonInteractive','-File',path.join(repository,'tools/i_core/test_fixtures/release_schema6/suspend_synthetic_core.ps1'),'-ProcessId',String(ready.pid),'-Executable',path.join(l.release,'runtime/node.exe'),'-RunId',ready.token,'-Action','Kill'],{windowsHide:true,env:cleanEnvironment(),encoding:'utf8'}));
 assert.equal(killed.synthetic_core_killed,true);const recovered=await run.ready(oldControl);await connectManaged(run,mcp);
 const recoveryMs=Number((performance.now()-recoveryBegin).toFixed(3)),oldStop=json(path.join(oldControl,'mcp-stop.json'));
 assert.equal(oldStop.job_empty_confirmed,true);assert.equal(oldStop.process_exit_confirmed,true);assert.equal(oldStop.owned_tree_handles_released_confirmed,true);assert.equal(processGone(oldStart.pid),true);
 assert.ok(statSync(path.join(oldControl,'mcp-stop.json')).mtimeMs<=statSync(path.join(run.control,'ready.json')).mtimeMs);
 assert.notEqual(run.read('mcp-start.json').pid,oldStart.pid);assert.equal(run.read('mcp-start.json').core_token,recovered.token);
 const changes=await fetch('http://127.0.0.1:'+recovered.address.port+'/v1/core/changes',{headers:{'x-core-protocol':'0.1',Authorization:'Bearer '+seeded.paired.device_token},signal:AbortSignal.timeout(5000)});
 assert.equal(changes.status,200);assert.ok(JSON.stringify(await changes.json()).includes(seeded.syncId));
 const elapsed=await shutdownAndMeasure(run);cleanReceipt(run);mcpStopped(run);assert.ok(elapsed<30000);l.completed=true;
 t.diagnostic('request_opened_mcp_crash_recovery_total_ms='+recoveryMs+';recovered_close_total_ms='+elapsed+';old_mcp_stop_ms='+oldStop.elapsed_ms);
});
test('MCP bounded-stop timeout force-terminates owned real CLI before Core close in the shared 30s budget',options,async t=>{
 const l=await createRuntimeLab(t),c=loginConfig(l),mcp=await configureManagedMcp(l,c,{graceMs:2500}),run=await host(l,c),ready=await run.ready();
 await seedSyntheticChat(l,ready,'timeout');await connectManaged(run,mcp);const pid=run.read('mcp-start.json').pid;assert.equal(processGone(pid),false);
 const elapsed=await shutdownAndMeasure(run);cleanReceipt(run);const stopped=mcpStopped(run);
 assert.equal(stopped.forced,true);assert.ok(stopped.elapsed_ms>=2500,'real CLI stays alive throughout its finite no-console grace window');assert.ok(elapsed<30000);
 assert.equal(run.read('session-close.json').clean_closed,true);assert.equal(json(path.join(l.state,'s6-lifecycle.json')).phase,'clean_closed');
 const restarted=await host(l,c,{initial:false});await restarted.ready();await connectManaged(restarted,mcp);const nextElapsed=await shutdownAndMeasure(restarted);cleanReceipt(restarted);mcpStopped(restarted);l.completed=true;
 t.diagnostic('mcp_stop_timeout_forced=true;mcp_stop_ms='+stopped.elapsed_ms+';complete_shutdown_ms='+elapsed+';next_login_close_ms='+nextElapsed);
});
test('managed MCP configuration rejects altered source and forbidden Node environment before launching any Core',options,async t=>{
 const l=await createRuntimeLab(t),c=loginConfig(l),mcp=await configureManagedMcp(l,c);
 const validate=()=>spawnSync(ps,[...loginArgs(l,c),'-ValidateOnly'],{windowsHide:true,env:cleanEnvironment(),encoding:'utf8'});
 assert.equal(validate().status,0);
 const original=readFileSync(mcp.file),secret='synthetic-node-secret-never-echo';
 mcp.configuration.environment.NODE_OPTIONS='--require '+secret;writeFileSync(mcp.file,JSON.stringify(mcp.configuration));c.configuration.mcp_configuration_sha256=sha256(readFileSync(mcp.file));refreshLogin(c);
 const bad=validate();assert.equal(bad.status,2);assert.equal((bad.stdout+bad.stderr).includes(secret),false);assert.equal(readdirSync(c.controlRoot).length,0);
 writeFileSync(mcp.file,original);c.configuration.mcp_configuration_sha256=sha256(original);refreshLogin(c);
 const entry=path.join(mcp.source,mcp.configuration.entrypoint),entryBytes=readFileSync(entry);writeFileSync(entry,Buffer.concat([entryBytes,Buffer.from('\n// synthetic altered source\n')]));
 assert.equal(validate().status,2);writeFileSync(entry,entryBytes);assert.equal(validate().status,0);l.completed=true;
});

test('real legacy MCP startup port conflict stays a failed session even when Core closes cleanly',options,async t=>{
 const l=await createRuntimeLab(t),c=loginConfig(l),mcp=await configureManagedMcp(l,c),listener=createNetServer();
 await new Promise((resolve,reject)=>{listener.once('error',reject);listener.listen(mcp.configuration.listen_port,'127.0.0.1',resolve);});
 t.after(()=>new Promise((resolve,reject)=>listener.close(error=>error?reject(error):resolve())));
 const run=await host(l,c);await until(()=>run.controls().find(p=>existsSync(path.join(p,'ready.json')))||run.closed,240000);
 run.control=run.controls().find(p=>existsSync(path.join(p,'ready.json')));assert.ok(run.control,'Core genuinely reached ready before actual MCP CLI start failure');
 await run.wait();assert.notEqual(run.exit,0);const stop=mcpStopped(run),close=run.read('session-close.json');
 assert.equal(close.clean_closed,false);assert.equal(close.mcp_failure,true);assert.equal(stop.mcp_failure,true);assert.equal(stop.natural_exit_observed,true);assert.notEqual(stop.mcp_exit_code,0);
 assert.equal(json(path.join(l.state,'s6-lifecycle.json')).phase,'clean_closed','data was safely sealed while overall MCP start was rejected');l.completed=true;
 t.diagnostic('actual_legacy_cli_port_conflict_session_rejected=true;core_data_clean_closed=true;stop_ms='+stop.elapsed_ms);
});

test('natural MCP exit is rejected by real StopMcp without relying on a timer Tick',options,async t=>{
 const l=await createRuntimeLab(t);
 const proof=JSON.parse(execFileSync(ps,['-NoProfile','-NonInteractive','-File',path.join(repository,'tools/i_core/test_fixtures/release_schema6/probe_mcp_stop_race.ps1'),'-SessionWindowScript',path.join(l.lifecycle,'session_window.ps1'),'-Directory',l.dir('mcp-stop-race')],{windowsHide:true,env:cleanEnvironment(),encoding:'utf8',timeout:90000}));
 assert.equal(proof.no_tick_invoked,true);assert.equal(proof.cases.length,4);assert.equal(proof.synthetic_root_cleaned,true);
 for(const item of proof.cases){
  for(const field of ['job_empty_confirmed','process_exit_confirmed','file_handle_observed','exclusive_reopen_confirmed'])assert.equal(item[field],true,item.name+':'+field);
  if(item.exit_code===124){assert.equal(item.forced,true);assert.equal(item.mcp_failure,false);}else{assert.equal(item.mcp_failure,true);assert.equal(item.forced,false);}
 }
 assert.deepEqual(proof.cases.map(item=>item.exit_code).sort((a,b)=>a-b),[0,7,9,124]);
 assert.equal(proof.cases.find(item=>item.exit_code===7).exit_triggered_inside_grace,true);
 l.completed=true;t.diagnostic('mcp_natural_exit_race_cases=4;timer_tick_required=false;real_owned_tree_handle_release=true');
});
