import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { copyFileSync, existsSync, mkdirSync, readFileSync, rmSync, unlinkSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { DatabaseSync } from 'node:sqlite';
import { ICoreStore } from '../i_core_store.mjs';
import { syntheticRoot } from '../test_fixtures/release_schema6/synthetic_paths.mjs';
import { syntheticLease } from '../test_fixtures/release_schema6/recovery/synthetic_lease.mjs';
import { sha256, INVENTORY, PINNED_NODE_SHA256 } from './package.mjs';
import { packageBusinessWitness, verifySwitchRelease, LEGACY_SWITCH_INVENTORY, SWITCH_PENDING } from './package_switch.mjs';
import { stateDigest, validatePrevious, publicLifecycleErrorCode } from './lifecycle/common.mjs';
const url=new URL('./recovery_adapter.mjs',import.meta.url);
let source=readFileSync(url,'utf8').replaceAll("'./lifecycle/offline_lease.mjs'","'../test_fixtures/release_schema6/recovery/synthetic_lease.mjs'");
source=source.replace(/from '([^']+)'/g,(all,n)=>n.startsWith('.')?`from '${new URL(n,url).href}'`:all);
const adapter=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
const hashFile=p=>sha256(readFileSync(p));
const put=(p,v)=>writeFileSync(p,JSON.stringify(v));
function packageFixture(root,name,names){
 const release=path.join(root,name);mkdirSync(release);
 for(const n of names){const p=path.join(release,n);mkdirSync(path.dirname(p),{recursive:true});if(n==='runtime/node.exe')copyFileSync(process.execPath,p);else writeFileSync(p,'synthetic '+name+' '+n);}
 const manifest={format:'i-core-schema6-preflight-candidate-v1',source_commit:'a'.repeat(40),core_commit:'a'.repeat(40),wrapper_commit:'a'.repeat(40),core_schema_version:6,runtime_profile:'schema6-owned-lifecycle-v1',activation_supported:false,node_version:'v24.14.1',pinned_node_sha256:PINNED_NODE_SHA256,
 policy:{activity_enabled:false,companion_reply_jobs:false,companion_upload_mode:'legacy_b3',domain_policy:'owner_managed'},
 files:names.map(p=>({path:p,bytes:readFileSync(path.join(release,p)).length,sha256:hashFile(path.join(release,p))}))};
 put(path.join(release,'manifest.json'),manifest);return {releaseDirectory:release,manifestSha256:hashFile(path.join(release,'manifest.json'))};
}
function fixture(t){
 const root=syntheticRoot('package-switch-unit-');t.after(()=>{assert.ok(path.basename(root).startsWith('package-switch-unit-'));rmSync(root,{recursive:true,force:true});});
 const state=path.join(root,'state');mkdirSync(state);const databasePath=path.join(state,'i-core.sqlite');
 const store=new ICoreStore(databasePath,{activityEnabled:false,companionUploadMode:'legacy_b3'}),nodeId=store.nodeId;store.close();
 const o={databasePath,custodyDirectory:path.join(root,'custody'),custodyKey:randomBytes(32),backupKey:randomBytes(32),backupDirectory:path.join(root,'backups')};
 let receipt={receiptId:'a'.repeat(64),databasePath,nodeId,databaseSha256:hashFile(databasePath),custodySha256:null};
 const lease=(hook=()=>{})=>o.supervisorLease=syntheticLease({databasePath,origin:receipt.custodySha256?'canonical_restart':'empty_provision',cleanCloseReceipt:receipt},hook);
 lease();let sealed=adapter.sealClosedRecovery(o);receipt.custodySha256=sealed.custodySha256;lease();sealed=adapter.migrateToSchema6(o);receipt={...receipt,databaseSha256:hashFile(databasePath),custodySha256:sealed.custodySha256};lease();
 const old=packageFixture(root,'old',LEGACY_SWITCH_INVENTORY),next=packageFixture(root,'next',INVENTORY);
 for(const [index,end] of [old,next].entries()){
  end.configurationPath=path.join(root,'config'+index+'.json');put(end.configurationPath,{format:'schema6-config-v1',manifest_sha256:end.manifestSha256,database_path:databasePath,node_id:nodeId,recovery_custody_directory:o.custodyDirectory});
  end.configurationSha256=hashFile(end.configurationPath);
 }
 const markerPath=path.join(state,'s6-lifecycle.json');
 put(markerPath,{format:'schema6-lifecycle-v1',phase:'clean_closed',token:receipt.receiptId,database_path:databasePath,node_id:nodeId,database_sha256:hashFile(databasePath),state_tree_sha256:stateDigest(state),manifest_sha256:old.manifestSha256,configuration_sha256:old.configurationSha256,custody_sha256:sealed.custodySha256,
 supervisor:{job_empty_confirmed:true,child_exit_code:0,guardian_exit_code:0,termination_requested:false}});
 const artifacts=['backup','login','mcp','task'].map(role=>{const p=path.join(root,role+'.json');put(p,{synthetic:true,role});return {role,path:p,sha256:hashFile(p)};});
 const plan=(from=old,to=next,rollbackOf=null)=>{
  const value={format:'schema6-package-switch-approved-v1',approved:true,operationId:'synthetic-'+randomBytes(5).toString('hex'),from,to,rollbackOf,expectedHeadSha256:hashFile(path.join(o.custodyDirectory,'current-head.json')),expectedMarkerSha256:hashFile(markerPath),artifacts,fromArtifacts:artifacts};
  const p=path.join(root,value.operationId+'.json');put(p,value);return {planPath:p,planSha256:hashFile(p),value};
 };
 const finish=result=>{put(markerPath,{...result.marker,phase:'clean_closed',supervisor:{job_empty_confirmed:true,child_exit_code:0,guardian_exit_code:0,termination_requested:false}});
  unlinkSync(path.join(state,SWITCH_PENDING));unlinkSync(path.join(o.custodyDirectory,'package-switch-pending.json'));
  receipt={receiptId:result.marker.token,databasePath,nodeId,databaseSha256:hashFile(databasePath),custodySha256:result.custodySha256};lease();};
 return {root,state,o,old,next,markerPath,plan,finish,lease,run:p=>adapter.switchClosedPackage({...o,...p,receiptId:randomBytes(32).toString('hex')})};
}
test('separate reviewed old/new inventories and every byte are verified',{skip:process.platform!=='win32'},t=>{
 const f=fixture(t);assert.equal(LEGACY_SWITCH_INVENTORY.length,47);verifySwitchRelease(f.old.releaseDirectory,f.old.manifestSha256);verifySwitchRelease(f.next.releaseDirectory,f.next.manifestSha256);
 writeFileSync(path.join(f.old.releaseDirectory,LEGACY_SWITCH_INVENTORY[0]),'changed');assert.throws(()=>verifySwitchRelease(f.old.releaseDirectory,f.old.manifestSha256),/release_file_changed/);
});
test('offline forward and no-business reverse preserve DB and advance authenticated head',{skip:process.platform!=='win32'},t=>{
 const f=fixture(t),before=hashFile(f.o.databasePath),first=f.run(f.plan());f.finish(first);
 assert.equal(hashFile(f.o.databasePath),before);const reverse=f.run(f.plan(f.next,f.old,first.eventSha256));f.finish(reverse);
 assert.ok(reverse.custodyGeneration>first.custodyGeneration);assert.equal(hashFile(f.o.databasePath),before);
 const m=JSON.parse(readFileSync(f.markerPath));validatePrevious(m,{state:f.state,manifest_sha256:f.old.manifestSha256},{database_sha256:before,nodeId:m.node_id},f.old.configurationSha256);
});
test('unapproved, unclean and forged lease reject without DB/head mutation',{skip:process.platform!=='win32'},t=>{
 const f=fixture(t),p=f.plan(),before=hashFile(path.join(f.o.custodyDirectory,'current-head.json'));
 put(p.planPath,{...p.value,approved:false});assert.throws(()=>f.run({...p,planSha256:hashFile(p.planPath)}),/switch_plan_invalid/);
 const good=f.plan();assert.throws(()=>adapter.switchClosedPackage({...f.o,...good,supervisorLease:{},receiptId:'b'.repeat(64)}),/synthetic_capability_rejected/);
 const m=JSON.parse(readFileSync(f.markerPath));put(f.markerPath,{...m,phase:'recovery_required'});assert.throws(()=>f.run(f.plan()),/recovery_required/);
 assert.equal(hashFile(path.join(f.o.custodyDirectory,'current-head.json')),before);
});
for(const phase of ['package_switch_before_pending','package_switch_after_pending','package_switch_before_floor','package_switch_before_head','package_switch_after_head'])test('interruption '+phase+' resumes exact approval without rewinding head',{skip:process.platform!=='win32'},t=>{
 const f=fixture(t),p=f.plan();let hit=false;
 f.lease(at=>{if(at===phase){hit=true;throw new Error('synthetic interruption');}});
 assert.throws(()=>f.run(p),/synthetic interruption/);assert.ok(hit);
 if(existsSync(path.join(f.state,SWITCH_PENDING))){
  const m=JSON.parse(readFileSync(f.markerPath));assert.throws(()=>validatePrevious(m,{state:f.state,manifest_sha256:f.old.manifestSha256},{database_sha256:hashFile(f.o.databasePath),nodeId:m.node_id},f.old.configurationSha256),/recovery_required/);
 }
 f.lease();const result=f.run(p);f.finish(result);assert.equal(JSON.parse(readFileSync(f.markerPath)).manifest_sha256,f.next.manifestSha256);
});
test('all business tables, schema and transcript/replay metadata are committed',()=>{
 const db=new DatabaseSync(':memory:');try{
 db.exec('CREATE TABLE chat_messages(id INTEGER,body TEXT);CREATE TABLE domain_ops(id INTEGER,body TEXT);CREATE TABLE other_table(id INTEGER,body BLOB);CREATE TABLE core_metadata(key TEXT,value TEXT)');
 const baseline=packageBusinessWitness(db).sha256;
 for(const sql of ["INSERT INTO chat_messages VALUES(1,'a')","INSERT INTO domain_ops VALUES(1,'a')","INSERT INTO other_table VALUES(1,X'00')","INSERT INTO core_metadata VALUES('historical_replay_approvals_v1','a')","INSERT INTO core_metadata VALUES('local_transcript_grants_v1','a')"]){
  db.exec('SAVEPOINT test');db.exec(sql);assert.notEqual(packageBusinessWitness(db).sha256,baseline);db.exec('ROLLBACK TO test; RELEASE test');
 }
 db.exec('CREATE TABLE unknown_business(x TEXT)');assert.notEqual(packageBusinessWitness(db).sha256,baseline);
 }finally{db.close();}
});
test('business mutation with unchanged chat sequence refuses reverse',{skip:process.platform!=='win32'},t=>{
 const f=fixture(t),forward=f.run(f.plan());f.finish(forward);
 const db=new DatabaseSync(f.o.databasePath);db.prepare("INSERT INTO core_metadata(key,value) VALUES('new_replay_fact','changed')").run();db.close();
 // Produce the normal clean custody after a legitimate new-package close.
 const marker=JSON.parse(readFileSync(f.markerPath));const receipt={receiptId:marker.token,databasePath:f.o.databasePath,nodeId:marker.node_id,databaseSha256:hashFile(f.o.databasePath),custodySha256:marker.custody_sha256};
 f.o.supervisorLease=syntheticLease({databasePath:f.o.databasePath,origin:'canonical_restart',cleanCloseReceipt:receipt});
 const sealed=adapter.sealClosedRecovery(f.o);
 put(f.markerPath,{...marker,database_sha256:hashFile(f.o.databasePath),state_tree_sha256:stateDigest(f.state),custody_sha256:sealed.custodySha256});
 assert.throws(()=>f.run(f.plan(f.next,f.old,forward.eventSha256)),/switch_business_changed/);
});

test('rollbackOf null cannot classify a historical return as a forward switch',{skip:process.platform!=='win32'},t=>{
 const f=fixture(t),forward=f.run(f.plan());f.finish(forward);
 assert.throws(()=>f.run(f.plan(f.next,f.old,null)),/switch_reverse_proof_required/);
 const db=new DatabaseSync(f.o.databasePath);db.prepare("INSERT INTO core_metadata(key,value) VALUES('another_replay_fact','changed')").run();db.close();
 const marker=JSON.parse(readFileSync(f.markerPath)),receipt={receiptId:marker.token,databasePath:f.o.databasePath,nodeId:marker.node_id,databaseSha256:hashFile(f.o.databasePath),custodySha256:marker.custody_sha256};
 f.o.supervisorLease=syntheticLease({databasePath:f.o.databasePath,origin:'canonical_restart',cleanCloseReceipt:receipt});
 const sealed=adapter.sealClosedRecovery(f.o);put(f.markerPath,{...marker,database_sha256:hashFile(f.o.databasePath),state_tree_sha256:stateDigest(f.state),custody_sha256:sealed.custodySha256});
 assert.throws(()=>f.run(f.plan(f.next,f.old,null)),/switch_reverse_proof_required/);
});
for(const reverse of [false,true])for(const checkpoint of ['target_marker_committed','custody_pending_deleted'])test('finalization '+checkpoint+' '+(reverse?'reverse':'forward')+' resumes with sentinel retained',{skip:process.platform!=='win32'},t=>{
 const f=fixture(t);let forward;
 if(reverse){forward=f.run(f.plan());f.finish(forward);}
 const p=reverse?f.plan(f.next,f.old,forward.eventSha256):f.plan(),result=f.run(p);
 put(f.markerPath,{...result.marker,phase:'clean_closed',supervisor:{job_empty_confirmed:true,child_exit_code:0,guardian_exit_code:0,termination_requested:false}});
 if(checkpoint==='custody_pending_deleted')unlinkSync(path.join(f.o.custodyDirectory,'package-switch-pending.json'));
 const m=JSON.parse(readFileSync(f.markerPath));assert.throws(()=>validatePrevious(m,{state:f.state,manifest_sha256:p.value.to.manifestSha256},{database_sha256:hashFile(f.o.databasePath),nodeId:m.node_id},p.value.to.configurationSha256),/recovery_required/);
 const resumed=f.run(p);assert.ok(resumed.custodyGeneration>result.custodyGeneration);f.finish(resumed);
 assert.equal(JSON.parse(readFileSync(f.markerPath)).manifest_sha256,p.value.to.manifestSha256);
});
test('native supervisor removes custody pending before the final state sentinel',()=>{
 const source=readFileSync(new URL('./lifecycle/start_schema6.ps1',import.meta.url),'utf8');
 assert.ok(source.indexOf('[IO.File]::Delete($pending)')<source.indexOf('[IO.File]::Delete($sentinel)'));
});

test('switch rejection receipts preserve reviewed codes without exposing arbitrary exception details',()=>{
 for(const code of ['switch_history_binding_mismatch','switch_orphan_sentinel','switch_resume_head_changed','switch_resume_marker_changed','switch_pending_other_operation','switch_artifact_changed'])assert.equal(publicLifecycleErrorCode({code}),code);
 assert.equal(publicLifecycleErrorCode(new Error('secret-path-and-value')),'runtime_operation_failed');
 assert.equal(publicLifecycleErrorCode({code:'switch_unreviewed_secret_value'}),'runtime_operation_failed');
});

test('implicit rowid is committed; without-rowid tables work and unenumerable schemas fail closed',()=>{
 const db=new DatabaseSync(':memory:');try{
  db.exec("CREATE TABLE future_business(value TEXT);INSERT INTO future_business VALUES('same')");
  const before=packageBusinessWitness(db).sha256;db.exec('UPDATE future_business SET rowid=99');assert.notEqual(packageBusinessWitness(db).sha256,before);
  db.exec('CREATE TABLE without_rowid(key TEXT PRIMARY KEY,value TEXT) WITHOUT ROWID');assert.ok(packageBusinessWitness(db).sha256);
  db.exec('CREATE TABLE shadowed(rowid TEXT,_rowid_ TEXT,oid TEXT)');assert.throws(()=>packageBusinessWitness(db),/switch_business_schema_unverifiable/);
  db.exec('DROP TABLE shadowed;CREATE VIRTUAL TABLE virtual_business USING fts5(value)');assert.throws(()=>packageBusinessWitness(db),/switch_business_schema_unverifiable/);
 }finally{db.close();}
});
test('rowid-only business mutation refuses authenticated reverse',{skip:process.platform!=='win32'},t=>{
 const f=fixture(t),forward=f.run(f.plan());f.finish(forward);
 const db=new DatabaseSync(f.o.databasePath);const before=db.prepare('SELECT key,value FROM core_metadata ORDER BY key').all();
 db.exec('UPDATE core_metadata SET rowid=rowid+1000000');assert.deepEqual(db.prepare('SELECT key,value FROM core_metadata ORDER BY key').all(),before);db.close();
 const marker=JSON.parse(readFileSync(f.markerPath)),receipt={receiptId:marker.token,databasePath:f.o.databasePath,nodeId:marker.node_id,databaseSha256:hashFile(f.o.databasePath),custodySha256:marker.custody_sha256};
 f.o.supervisorLease=syntheticLease({databasePath:f.o.databasePath,origin:'canonical_restart',cleanCloseReceipt:receipt});
 const sealed=adapter.sealClosedRecovery(f.o);put(f.markerPath,{...marker,database_sha256:hashFile(f.o.databasePath),state_tree_sha256:stateDigest(f.state),custody_sha256:sealed.custodySha256});
 assert.throws(()=>f.run(f.plan(f.next,f.old,forward.eventSha256)),/switch_business_changed/);
});

test('SQLite infinite real values cannot collide with NULL in the business witness',()=>{
 const db=new DatabaseSync(':memory:');try{
  db.exec('CREATE TABLE future_real(value REAL)');const insert=db.prepare('INSERT INTO future_real VALUES(?)');insert.run(Infinity);
  const positive=packageBusinessWitness(db).sha256;db.exec('UPDATE future_real SET value=NULL');const empty=packageBusinessWitness(db).sha256;
  assert.notEqual(positive,empty);db.prepare('UPDATE future_real SET value=?').run(-Infinity);assert.notEqual(packageBusinessWitness(db).sha256,empty);assert.notEqual(packageBusinessWitness(db).sha256,positive);
 }finally{db.close();}
});
