import assert from 'node:assert/strict';
import test from 'node:test';
import { randomBytes } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync, unlinkSync, readdirSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { syntheticRoot } from '../../test_fixtures/release_schema6/synthetic_paths.mjs';
import { parseConfiguration } from './configuration.mjs';
import { stateDigest } from './common.mjs';
import { assertOfflineLease } from './offline_lease.mjs';
import { createRuntimeLab as lab, until, api, health, cleanReceipt, removeOwned } from './test-fixture.mjs';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const secret=()=>randomBytes(32).toString('hex');
function pureConfig(){return {format:'schema6-config-v1',manifest_sha256:'a'.repeat(64),database_path:'database',node_id:'node',owner_sid:'owner',
 companion_upload_mode:'legacy_b3',companion_reply_jobs:false,activity_enabled:false,domain_policy:'owner_managed',pairing_secret:null,
 grants_path:'grants',grants_sha256:'b'.repeat(64),approvals_path:'approvals',approvals_sha256:'c'.repeat(64),recovery_custody_directory:'custody',recovery_key_path:'key'};}
test('configuration rejects unsafe mode, activity/jobs, fields, missing and swapped bindings without OS dependency',()=>{
 const c=pureConfig(),binding={manifest_sha256:c.manifest_sha256,database_path:c.database_path,node_id:c.node_id,owner_sid:c.owner_sid};
 assert.equal(parseConfiguration(c,binding),c);
 for(const patch of [{companion_upload_mode:'pr10'},{companion_reply_jobs:true},{activity_enabled:true},{domain_policy:'auto'},
 {unknown:true},{manifest_sha256:'d'.repeat(64)},{node_id:'wrong'},{owner_sid:'wrong'},{pairing_secret:'short'},{grants_sha256:null}])assert.throws(()=>parseConfiguration({...c,...patch},binding));
});
test('plain JSON and callback-shaped assertions never become trusted offline leases',()=>{
 for(const value of [{},{allCoreWritersStopped:true},{offlineProof:()=>true}])assert.throws(()=>assertOfflineLease(value,{databasePath:'x',phase:'preflight'}),/trusted_offline_lease_required/);
});
test('state digest binds nested files and directory layout independently of lifecycle marker',()=>{
 const root=syntheticRoot('schema6-tree-');
 writeFileSync(path.join(root,'db'),'first');const first=stateDigest(root);
 writeFileSync(path.join(root,'s6-lifecycle.json'),'receipt');assert.equal(stateDigest(root),first);
 mkdirSync(path.join(root,'extra'));assert.notEqual(stateDigest(root),first);
 writeFileSync(path.join(root,'extra','data'),'modified');const second=stateDigest(root);assert.notEqual(second,first);removeOwned(root,'schema6-tree-');
});
test('Windows fixed production entry: real loopback, credential-free argv, authenticated idempotent close, canonical restart after writes and 125s live', {skip:process.platform!=='win32',timeout:420000},async t=>{
 const l=await lab(t),run=l.launch({initial:true}),ready=await run.ready();
 assert.equal(ready.health.schema_version,6);assert.equal((await health(ready)).status,200);assert.equal(ready.activity_enabled,false);
 assert.equal(ready.companion_upload_mode,'legacy_b3');assert.equal(ready.companion_reply_jobs,false);
 assert.equal(ready.commandline_secret_free,true);assert.deepEqual(ready.inherited_core_keys,[]);
 assert.throws(()=>writeFileSync(l.configPath,'tampered'),/EBUSY|EACCES|EPERM/);
 const paired=await api(ready,'/devices/pair',null,{device_id:'schema6-phone',display_name:'synthetic',platform:'test',client_version:'1',capabilities:['chat'],pairing_code:l.configuration.pairing_secret});
 await api(ready,'/chat/messages',paired.device_token,{device_id:'schema6-phone',messages:[{sync_id:'schema6-user-turn',origin_device_id:'schema6-phone',origin_sequence:1,character_id:'lin-ai',sender:'user',content:'synthetic lifecycle write',created_at_ms:Date.now(),message_type:'chat',asset_refs:[],addenda:[]}]});
 const liveSince=Date.now();while(Date.now()-liveSince<125000){await sleep(Math.min(1000,125000-(Date.now()-liveSince)));assert.equal((await health(ready)).status,200);}
 t.diagnostic('continuous_loopback_ms='+String(Date.now()-liveSince));
 assert.throws(()=>run.stop('close',secret()));
 writeFileSync(path.join(run.control,'close'),'forged');await sleep(150);assert.equal((await health(ready)).status,200);unlinkSync(path.join(run.control,'close'));
 run.stop();run.stop();await run.wait();cleanReceipt(run);await assert.rejects(health(ready));
 const again=l.launch();await again.ready();again.stop();await again.wait();cleanReceipt(again);
 const db=new DatabaseSync(pathToFileURL(path.join(l.state,'i-core.sqlite')).href+'?mode=ro&immutable=1',{readOnly:true});
 try{assert.equal(db.prepare("SELECT COUNT(*) AS n FROM chat_messages WHERE sync_id='schema6-user-turn'").get().n,1);}finally{db.close();}
 writeFileSync(path.join(l.state,'extra.txt'),'unauthorized state');
 const extra=l.launch();await extra.wait();assert.notEqual(extra.exit,0);assert.equal(extra.read('ready.json'),null);
 assert.match(JSON.stringify(extra.read('child.json')),/recovery_required/);l.completed=true;
});
test('Windows entry rejects injected Node config, unbound config, manifest extra file and nonempty initialization', {skip:process.platform!=='win32',timeout:180000},async t=>{
 const l=await lab(t);
 const injected=l.launch({initial:true,env:{NODE_OPTIONS:'--trace-warnings'}});await injected.wait();assert.notEqual(injected.exit,0);assert.equal(injected.read('launch.json'),null);
 const wrong=path.join(path.dirname(l.configPath),'wrong.json');writeFileSync(wrong,JSON.stringify({...l.configuration,manifest_sha256:secret()}));
 const unbound=l.launch({initial:true,config:wrong});await unbound.wait();assert.notEqual(unbound.exit,0);assert.match(JSON.stringify(unbound.read('child.json')),/config_binding_mismatch/);
 // Rejected initialization left its runtime lock file; an occupied state root
 // must never be treated as a fresh genesis on a subsequent attempt.
 const nonempty=l.launch({initial:true});await nonempty.wait();assert.notEqual(nonempty.exit,0);
 assert.match(nonempty.stderr,/initialize_requires_empty_state/);assert.equal(nonempty.read('launch.json'),null);
 writeFileSync(path.join(l.release,'extra.txt'),'extra');
 const extra=l.launch({initial:true});await extra.wait();assert.notEqual(extra.exit,0);assert.equal(extra.read('launch.json'),null);l.completed=true;
});
for(const target of ['guardian','parent','child'])test('Windows '+target+' death preserves raw state and next login automatically recovers without fabricating clean close',{skip:process.platform!=='win32',timeout:360000},async t=>{
 const l=await lab(t),run=l.launch({initial:true}),ready=await run.ready();
 const pid=target==='guardian'?run.read('guardian-ready.json').pid:target==='parent'?run.child.pid:ready.pid;
 process.kill(pid);await run.wait();await until(()=>{try{process.kill(ready.pid,0);return false;}catch{return true;}},20000);
 await assert.rejects(health(ready));
 await until(()=>{try{process.kill(run.read('guardian-ready.json').pid,0);return false;}catch{return true;}},20000);
 const marker=JSON.parse(readFileSync(path.join(l.state,'s6-lifecycle.json')));assert.equal(marker.phase,'recovery_required');
 const restart=l.launch();const recovered=await restart.ready();assert.equal(recovered.health.schema_version,6);
 assert.ok(readdirSync(path.join(l.root,'backups')).some(n=>n.startsWith('raw-')));
 assert.ok(readdirSync(path.join(l.root,'custody')).some(n=>n.endsWith('.recovery.json')));
 restart.stop();await restart.wait();cleanReceipt(restart);l.completed=true;
});


test('Windows canonical offline lease runs real 6-to-5-to-6 transactions and refuses online schema5', {skip:process.platform!=='win32',timeout:360000},async t=>{
 const l=await lab(t),initial=l.launch({initial:true});await initial.ready();initial.stop();await initial.wait();cleanReceipt(initial);
 const rollback=l.launch({args:['-OfflineOperation','rollback']});await rollback.wait();cleanReceipt(rollback);
 assert.equal(rollback.read('operation.json').database_schema_version,5);
 const wrong=l.launch();await wrong.wait();assert.notEqual(wrong.exit,0);assert.match(JSON.stringify(wrong.read('child.json')),/existing_core_identity_or_schema_required/);
 const migrate=l.launch({args:['-OfflineOperation','migrate']});await migrate.wait();cleanReceipt(migrate);
 assert.equal(migrate.read('operation.json').database_schema_version,6);
 const final=l.launch();await final.ready();final.stop();await final.wait();cleanReceipt(final);l.completed=true;
});
test('Windows backup role and unowned schema4 cannot be activated by ordinary restart', {skip:process.platform!=='win32',timeout:220000},async t=>{
 const l=await lab(t),initial=l.launch({initial:true});await initial.ready();initial.stop();await initial.wait();cleanReceipt(initial);
 const filename=path.join(l.state,'i-core.sqlite'),original=readFileSync(filename);
 for(const [sql,expected] of [["UPDATE core_metadata SET value='4' WHERE key='schema_version'",'existing_core_identity_or_schema_required'],["UPDATE activity_metadata SET value='backup_read_only' WHERE key='database_role'",'backup_activation_unsupported']]){
  writeFileSync(filename,original);const db=new DatabaseSync(filename);try{db.exec(sql);}finally{db.close();}
  const run=l.launch();await run.wait();assert.notEqual(run.exit,0);assert.match(JSON.stringify(run.read('child.json')),new RegExp(expected));assert.equal(run.read('ready.json'),null);
 }
 l.completed=true;
});
