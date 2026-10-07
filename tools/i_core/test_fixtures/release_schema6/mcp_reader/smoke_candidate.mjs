// Exact committed candidate smoke; explicit synthetic inputs only.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import path from 'node:path';
import {verifyRelease,sha256,PINNED_NODE_SHA256} from '../../../release_schema6/package.mjs';
import {createRuntimeLab,host,loginConfig,configureManagedMcp,connectManaged,seedSyntheticChat,shutdownAndMeasure,mcpStopped,cleanReceipt,json} from '../../../release_schema6/lifecycle/mcp-session-test-fixture.mjs';
const [release,anchor,ack,...extra]=process.argv.slice(2);
assert.equal(process.platform,'win32');assert.equal(ack,'--synthetic-mcp-only');assert.equal(extra.length,0);
assert.equal(sha256(readFileSync(process.execPath)),PINNED_NODE_SHA256);
const verified=verifyRelease(release,anchor),begun=performance.now(),callbacks=[];
const t={after:fn=>callbacks.push(fn),diagnostic:()=>{}},l=await createRuntimeLab(t);
try{
 // Keep the lab's fresh state/keys/custody; run the independently built, verified release.
 l.release=release;l.lifecycle=path.join(release,'tools/i_core/release_schema6/lifecycle');l.manifestHash=anchor;
 l.configuration.manifest_sha256=anchor;writeFileSync(l.configPath,JSON.stringify(l.configuration));
 const c=loginConfig(l),mcp=await configureManagedMcp(l,c,{graceMs:3000}),run=await host(l,c),ready=await run.ready();
 const seeded=await seedSyntheticChat(l,ready,'committed-candidate'),reader=await connectManaged(run,mcp);
 assert.ok(JSON.stringify(reader.firstRecall.body).includes(seeded.syncId));
 const firstPid=run.read('mcp-start.json').pid,closeMs=await shutdownAndMeasure(run);cleanReceipt(run);
 const stopped=mcpStopped(run);assert.equal(stopped.forced,true);assert.ok(closeMs<30000);
 assert.equal(json(path.join(l.state,'s6-lifecycle.json')).phase,'clean_closed');
 const next=await host(l,c,{initial:false}),after=await next.ready(),afterReader=await connectManaged(next,mcp);
 assert.equal(after.health.schema_version,6);assert.notEqual(next.read('mcp-start.json').pid,firstPid);
 assert.ok(JSON.stringify(afterReader.firstRecall.body).includes(seeded.syncId));
 const nextCloseMs=await shutdownAndMeasure(next);cleanReceipt(next);mcpStopped(next);assert.ok(nextCloseMs<30000);
 verifyRelease(release,anchor);l.completed=true;
 console.log(JSON.stringify({...verified,exact_committed_managed_candidate_smoke:true,real_legacy_mcp_request:true,old_mcp_entry_sha256:'adfc88126c6d7ee047fd7fed7eda6b3b536c9e1fe0baffafbedc290b6c5554d6',clean_closed:true,native_owned_jobs_empty:true,exclusive_database_reopen:true,next_login_mcp_readback:true,mcp_forced:true,mcp_stop_ms:stopped.elapsed_ms,complete_shutdown_ms:closeMs,next_login_shutdown_ms:nextCloseMs,elapsed_ms:Number((performance.now()-begun).toFixed(3))}));
}finally{for(const callback of callbacks.reverse())await callback();}
