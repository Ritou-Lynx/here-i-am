import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { randomBytes, createHmac } from 'node:crypto';
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, unlinkSync, writeFileSync } from 'node:fs';
import { realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { syntheticRoot } from '../test_fixtures/release_schema6/synthetic_paths.mjs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { ICoreStore } from '../i_core_store.mjs';
import { createICoreServer } from '../i_core_server.mjs';
import { activityRecoveryManifestForDatabase, rollbackActivitySchema } from '../activity_control_plane.mjs';
import { sha256 } from './package.mjs';
import { createRuntimeBackup, BACKUP_ROLES } from './backup_bundle.mjs';
import { digest, inspectInputs } from './preflight.mjs';
import { assertDomainSchemaReady } from '../domain_schema.mjs';
import { syntheticLease } from '../test_fixtures/release_schema6/recovery/synthetic_lease.mjs';

// Real adapter and real migration/crypto code; only OS capability is substituted
// in an unmistakably synthetic module instance. Production has no injection API.
const sourceUrl = new URL('./recovery_adapter.mjs',import.meta.url);
let source = readFileSync(sourceUrl,'utf8');
source = source.replaceAll("'./lifecycle/offline_lease.mjs'", "'../test_fixtures/release_schema6/recovery/synthetic_lease.mjs'");
source = source.replace(/from '([^']+)'/g,(all,name) => name.startsWith('.') ? `from '${new URL(name,sourceUrl).href}'` : all);
source += '\n//# sourceURL=schema6-recovery-adapter-synthetic.mjs\n';
const adapter = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
function closedHash(databasePath) { return sha256(readFileSync(databasePath)); }
function fixture(t,{version=5,history=false}={}) {
 const root=syntheticRoot('recovery-adapter-synthetic-');
 t.after(() => { assert.equal(path.dirname(root),realpathSync.native(tmpdir())); assert.ok(path.basename(root).startsWith('recovery-adapter-synthetic-')); rmSync(root,{recursive:true,force:true}); });
 const state=path.join(root,'state'); mkdirSync(state);
 const databasePath=path.join(state,'i-core.sqlite');
 const options={databasePath,custodyDirectory:path.join(root,'custody'),custodyKey:randomBytes(32),backupKey:randomBytes(32),backupDirectory:path.join(root,'backups')};
 let store=new ICoreStore(databasePath,{activityEnabled:false,companionUploadMode:'legacy_b3'});
 let seedCustody=null;
 if(version!==4){
  const nodeId=store.nodeId;store.close();
  const normal=new DatabaseSync(databasePath);normal.exec('PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE');normal.close();
  options.supervisorLease=syntheticLease({databasePath,origin:'empty_provision',cleanCloseReceipt:{receiptId:'synthetic-clean-close',databasePath,nodeId,databaseSha256:closedHash(databasePath),custodySha256:null}});
  seedCustody=adapter.sealClosedRecovery(options);
  store=new ICoreStore(databasePath,{activityEnabled:history,companionUploadMode:'legacy_b3'});
 }

 const token=store.pairDevice({device_id:'phone-one',display_name:'Synthetic',platform:'android',client_version:'test',capabilities:[]},'synthetic-code').device_token;
 const records=[], messages=Array.from({length:72},(_,index) => {
  const incoming={sync_id:`synthetic-${index}`,origin_device_id:'phone-one',origin_sequence:index,character_id:'i',sender:'user',content:`synthetic body ${index}`,created_at_ms:1700000000000+index,message_type:'chat',asset_refs:[],addenda:[]};
  const existing={...incoming,origin_device_id:'v3-history-0123456789abcdef0123',origin_sequence:index+1,created_at_ms:incoming.created_at_ms+123,addenda:[{kind:'historical_import',source:'hereiam_v3'}]};
  records.push({sync_id:incoming.sync_id,device_id:incoming.origin_device_id,origin_sequence:incoming.origin_sequence,incoming_digest:digest(incoming),existing_digest:digest(existing)}); return existing;
 });
 store.importMessages('v3-history-0123456789abcdef0123',messages);
 const approvalDocument={version:1,approved_replays:records};
 store.db.prepare('INSERT INTO core_metadata(key,value) VALUES(?,?)').run('historical_replay_approvals_v1',JSON.stringify(approvalDocument));
 if(history) store.activity.pairSummaryReader({installation_id:'synthetic-reader',display_name:'Synthetic reader',capabilities:['activity.admin','chat.read']});
 const nodeId=store.nodeId,cursorSecret=store.cursorSecret;
 store.close();
 const db=new DatabaseSync(databasePath); db.exec('PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE'); if(version===4) rollbackActivitySchema(db); db.close();
 const approvals=path.join(state,'historical-replay-approvals.json'), grants=path.join(state,'local-transcript-grants.json');
 writeFileSync(approvals,JSON.stringify(approvalDocument));
 writeFileSync(grants,JSON.stringify({version:1,grants:[{device_id:'phone-one',character_id:'i',credential_sha256:sha256(token),from_created_at_ms:1700000000000}]}));

 let receipt={receiptId:'synthetic-clean-close',databasePath,nodeId,databaseSha256:closedHash(databasePath),custodySha256:seedCustody?.custodySha256??null};
 const f={root,state,options,approvals,grants,nodeId,cursorSecret,
  setLease(hook=()=>{}){options.supervisorLease=syntheticLease({databasePath,origin:'canonical_restart',cleanCloseReceipt:{...receipt}},hook);},
  pin(result){receipt={...receipt,databaseSha256:result.databaseSha256,custodySha256:result.custodySha256};this.setLease();},
  refreshReceipt(){receipt={...receipt,databaseSha256:closedHash(databasePath)};this.setLease();},
  inspect(fn){const d=new DatabaseSync(databasePath,{readOnly:true});try{return fn(d);}finally{d.close();}},
  mutate(sql){const d=new DatabaseSync(databasePath);try{d.exec(sql);}finally{d.close();}},
  version(){return this.inspect(d=>Number(d.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get().value));},
  config:{format:'schema6-preflight-v1',mode:'legacy_b3',companion_reply_jobs:false,activity_enabled:false,domain_policy:'owner_managed',database_path:databasePath,approvals_path:approvals,grants_path:grants},
 };
 f.setLease(); if(version!==4)f.pin(adapter.sealClosedRecovery(options)); return f;
}
const rejects=(fn,code)=>assert.throws(fn,e=>e.code===code,code);
function rewriteCustody(f,modify) {
 const filename=readdirSync(f.options.custodyDirectory).filter(n=>n.endsWith('.floor.json')).map(n=>path.join(f.options.custodyDirectory,n)).at(-1);
 const body=JSON.parse(readFileSync(filename));delete body.authentication;modify(body);
 const authentication=createHmac('sha256',f.options.custodyKey).update('i-core-floor-custody-v1\0').update(JSON.stringify(body)).digest('hex');
 const raw=Buffer.from(JSON.stringify({...body,authentication})+'\n'), custodySha256=sha256(raw);
 const custodyPath=path.join(f.options.custodyDirectory,`${custodySha256}.floor.json`);writeFileSync(custodyPath,raw);
 // Forge an independently authenticated synthetic head as well, so these
 // tests reach the inner floor validation rather than stopping at the head pin.
 const headPath=path.join(f.options.custodyDirectory,'current-head.json');
 const head=JSON.parse(readFileSync(headPath));delete head.authentication;head.custodySha256=custodySha256;
 const auth=createHmac('sha256',f.options.custodyKey).update('i-core-floor-custody-v1\0').update(JSON.stringify(head)).digest('hex');
 const headRaw=Buffer.from(JSON.stringify({...head,authentication:auth})+'\n');
 writeFileSync(headPath,headRaw);writeFileSync(path.join(f.options.custodyDirectory,sha256(headRaw)+'.head.json'),headRaw);
 f.pin({custodySha256,databaseSha256:closedHash(f.options.databasePath)});return custodyPath;
}
test('existing schema5 activity history migrates and preserves exact72/grant/authority, real server closes and reopens canonical live path',async t=>{
 const f=fixture(t,{history:true});
 const baseline=await inspectInputs({config:f.config,capture:true,assertDomainReady:assertDomainSchemaReady});
 const external=[f.approvals,f.grants].map(p=>closedHash(p));
 const result=adapter.migrateToSchema6(f.options);f.pin(result);
 assert.equal(result.schemaVersion,6);assert.equal(result.backup.verified,true);assert.equal(result.legacyDigestVerified,true);
 const after=await inspectInputs({config:f.config,capture:true,assertDomainReady:assertDomainSchemaReady});
 for(const key of ['expected_bindings_sha256','expected_identity_sha256','expected_grants_sha256'])assert.equal(after[key],baseline[key]);
 assert.deepEqual([f.approvals,f.grants].map(p=>closedHash(p)),external);
 assert.equal(f.inspect(db=>db.prepare('SELECT COUNT(*) AS n FROM activity_principals').get().n),1);
 assert.equal(adapter.verifyCanonicalRestart(f.options).recoveryFloorVerified,true);
 for(let pass=0;pass<2;pass++) {
  const core=createICoreServer({databasePath:f.options.databasePath,companionUploadMode:'legacy_b3',companionReplyJobsEnabled:false,activityEnabled:false});
  const address=await core.listen({host:'127.0.0.1',port:0});assert.ok(address.port>0);assert.equal(core.store.nodeId,f.nodeId);
  assert.equal(core.store.db.prepare('SELECT COUNT(*) AS n FROM domain_principals').get().n,0);
  await core.close();assert.equal(core.server.listening,false);assert.equal(core.store.db.isOpen,false);
  f.refreshReceipt();f.pin(adapter.sealClosedRecovery(f.options));assert.equal(adapter.verifyCanonicalRestart(f.options).schemaVersion,6);
 }
});
test('JSON stopped proof and arbitrary callback are not capabilities',t=>{
 const f=fixture(t);const before=closedHash(f.options.databasePath);
 rejects(()=>adapter.migrateToSchema6({...f.options,supervisorLease:{allCoreWritersStopped:true,offlineProof:()=>true}}),'synthetic_capability_rejected');
 assert.equal(closedHash(f.options.databasePath),before);
});
test('missing or tampered independent custody rejects before any migration',t=>{
 const f=fixture(t);const file=path.join(f.options.custodyDirectory,JSON.parse(readFileSync(path.join(f.options.custodyDirectory,'current-head.json'))).custodySha256+'.floor.json');const raw=readFileSync(file);
 unlinkSync(file);assert.throws(()=>adapter.migrateToSchema6(f.options));writeFileSync(file,Buffer.concat([raw,Buffer.from(' ')]));
 rejects(()=>adapter.migrateToSchema6(f.options),'custody_digest_mismatch');assert.equal(f.version(),5);
});
for(const [name,modify] of [['wrong node',b=>b.nodeId='another-node'],['wrong path',b=>b.databasePath+='other'],['wrong secret',b=>b.activityRecoveryFloor.digest='0'.repeat(64)],['wrong history',b=>b.activityRecoveryFloor.history_digest='0'.repeat(64)]])test(`authenticated custody ${name} rejected`,t=>{
 const f=fixture(t);rewriteCustody(f,modify);assert.throws(()=>adapter.migrateToSchema6(f.options));assert.equal(f.version(),5);
});
test('active runtime claim rejects even if lifecycle database hash updated',t=>{
 const f=fixture(t);f.mutate("UPDATE activity_runtime_claim SET runtime_id='synthetic-live',lease_expires_at_ms=9999999999999");f.refreshReceipt();assert.throws(()=>adapter.migrateToSchema6(f.options));assert.equal(f.version(),5);
});
test('backup role and sidecars fail closed',t=>{
 for(const suffix of ['-wal','-shm','-journal']){const f=fixture(t);writeFileSync(f.options.databasePath+suffix,'');rejects(()=>adapter.migrateToSchema6(f.options),'sqlite_sidecars_not_quiescent');unlinkSync(f.options.databasePath+suffix);}
 const f=fixture(t);f.mutate("UPDATE activity_metadata SET value='backup_read_only' WHERE key='database_role'");f.refreshReceipt();rejects(()=>adapter.migrateToSchema6(f.options),'backup_activation_unsupported');
});
test('another live path with exact copied bytes cannot migrate',t=>{
 const f=fixture(t);const other=path.join(f.state,'other.sqlite');copyFileSync(f.options.databasePath,other);assert.throws(()=>adapter.migrateToSchema6({...f.options,databasePath:other}));assert.equal(f.version(),5);
});
test('lease lost immediately before domain commit rolls back DDL',t=>{
 const f=fixture(t);f.setLease(phase=>{if(phase==='domain_before_commit')throw Object.assign(new Error('synthetic_lease_lost'),{code:'synthetic_lease_lost'});});
 rejects(()=>adapter.migrateToSchema6(f.options),'synthetic_lease_lost');assert.equal(f.version(),5);
 assert.equal(f.inspect(db=>db.prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE name LIKE 'domain_%'").get().n),0);
});
test('backup interruption retains encrypted artifact but no DDL or cleartext content',t=>{
 const f=fixture(t);f.setLease(phase=>{if(phase==='domain_before_ddl')throw Object.assign(new Error('synthetic_interrupted'),{code:'synthetic_interrupted'});});
 rejects(()=>adapter.migrateToSchema6(f.options),'synthetic_interrupted');assert.equal(f.version(),5);
 const files=readdirSync(f.options.backupDirectory);assert.equal(files.filter(n=>n.endsWith('.aes256gcm')).length,1);
 for(const file of files)assert.equal(readFileSync(path.join(f.options.backupDirectory,file)).includes(Buffer.from('synthetic body')),false);
});
test('authenticated old floor cannot authorize newer activity history',t=>{
 const f=fixture(t);const oldHash=readdirSync(f.options.custodyDirectory)[0].split('.')[0];
 const store=new ICoreStore(f.options.databasePath,{activityEnabled:true});store.activity.pairSummaryReader({installation_id:'new-reader',display_name:'new reader',capabilities:[]});store.close();
 f.refreshReceipt();f.pin(adapter.sealClosedRecovery(f.options));
 // A stale external pin deliberately injected by the synthetic supervisor still
 // cannot match the current database digest/history.
 f.pin({custodySha256:oldHash,databaseSha256:closedHash(f.options.databasePath)});
 rejects(()=>adapter.migrateToSchema6(f.options),'custody_head_rollback_rejected');
});
test('empty domain rollback allowed only in place; any new domain write prevents destructive rollback',t=>{
 const f=fixture(t);f.pin(adapter.migrateToSchema6(f.options));const result=adapter.rollbackEmptySchema6(f.options);assert.equal(result.schemaVersion,5);
 const g=fixture(t);g.pin(adapter.migrateToSchema6(g.options));g.mutate("INSERT INTO domain_records VALUES('production','example','id',1,'{}','{}')");g.refreshReceipt();g.pin(adapter.sealClosedRecovery(g.options));
 rejects(()=>adapter.rollbackEmptySchema6(g.options),'domain_rollback_not_empty');assert.equal(g.version(),6);
});
test('custody/key must be independent and unsupported backup activation remains rejected',t=>{
 const f=fixture(t);rejects(()=>adapter.migrateToSchema6({...f.options,custodyDirectory:f.state}),'custody_must_be_independent');
 rejects(()=>adapter.migrateToSchema6({...f.options,custodyKey:Buffer.from(f.cursorSecret,'base64url')}),'custody_key_not_independent');
 f.pin(adapter.migrateToSchema6(f.options));const floor=f.inspect(db=>activityRecoveryManifestForDatabase(db,{nodeId:f.nodeId,cursorSecret:f.cursorSecret}));
 rejects(()=>createICoreServer({databasePath:f.options.databasePath,activityRecoveryFloor:floor}),'backup_activation_unsupported');
});

function initialBundle(f) {
 const oldRelease=path.join(f.root,'old-release'),inputs=path.join(f.root,'backup-inputs');mkdirSync(oldRelease);mkdirSync(inputs);
 const manifest=path.join(oldRelease,'manifest.json');writeFileSync(manifest,JSON.stringify({synthetic:true,version:4}));
 const files=new Map([['database',f.options.databasePath],['release',manifest],['transcript_grants',f.grants],['replay_approvals',f.approvals]]);
 for(const role of BACKUP_ROLES.filter(r=>!files.has(r))){
  const filename=path.join(inputs,role+'.json');
  writeFileSync(filename,JSON.stringify(role==='recovery_custody'?{format:'i-core-recovery-custody-v1',mode:'initial_schema4',node_id:f.nodeId,database_path:f.options.databasePath}:{synthetic:true,role}));
  files.set(role,filename);
 }
 const spec={format:'i-core-runtime-backup-spec-v1',source_schema:4,node_id:f.nodeId,canonical_database_path:f.options.databasePath,
  old_release_root:oldRelease,old_release_manifest_sha256:closedHash(manifest),entries:[...files].map(([role,source_path])=>({role,name:role==='release'?'manifest.json':role+'.json',source_path,sha256:closedHash(source_path)}))};
 return createRuntimeBackup({spec,outputDirectory:path.join(f.root,'initial-encrypted-bundle'),key:f.options.backupKey});
}
test('schema4 real encrypted nine-role bundle -> activity genesis -> schema6 preserves72 and original path restart',async t=>{
 const f=fixture(t,{version:4});
 const business=()=>f.inspect(db=>JSON.stringify({rows:db.prepare('SELECT * FROM chat_messages ORDER BY sync_id').all(),devices:db.prepare('SELECT * FROM devices ORDER BY device_id').all(),events:db.prepare('SELECT * FROM change_events ORDER BY server_sequence').all(),metadata:db.prepare("SELECT * FROM core_metadata WHERE key NOT IN ('schema_version','activity_schema_version') ORDER BY key").all()}));
 const before=business(),files=[f.approvals,f.grants].map(p=>closedHash(p));
 const initial=initialBundle(f);assert.equal(initial.verified,true);f.options.initialBackup=initial;
 const result=adapter.migrateToSchema6(f.options);f.pin(result);assert.equal(result.schemaVersion,6);assert.equal(result.custodyGeneration,2);
 const after=await inspectInputs({config:f.config,capture:true,assertDomainReady:assertDomainSchemaReady});
 assert.equal(business(),before);assert.deepEqual([f.approvals,f.grants].map(p=>closedHash(p)),files);assert.equal(after.exact_bindings,72);
 const floorFiles=readdirSync(f.options.custodyDirectory).filter(n=>n.endsWith('.floor.json'));assert.equal(floorFiles.length,2);
 assert.ok(floorFiles.some(n=>JSON.parse(readFileSync(path.join(f.options.custodyDirectory,n))).origin==='verified_schema4_genesis'));
 assert.equal(adapter.verifyCanonicalRestart(f.options).schemaVersion,6);
 const core=createICoreServer({databasePath:f.options.databasePath,companionUploadMode:'legacy_b3',activityEnabled:false});
 try{await core.listen({host:'127.0.0.1',port:0});assert.equal(core.store.nodeId,f.nodeId);assert.equal(core.store.db.prepare('SELECT COUNT(*) AS n FROM chat_messages').get().n,72);}finally{await core.close();}
 f.refreshReceipt();f.pin(adapter.sealClosedRecovery(f.options));assert.equal(adapter.verifyCanonicalRestart(f.options).schemaVersion,6);
});
test('schema4 missing or corrupt bundle never creates an activity genesis',t=>{
 const f=fixture(t,{version:4});assert.throws(()=>adapter.migrateToSchema6(f.options));assert.equal(f.version(),4);
 const initial=initialBundle(f);const raw=readFileSync(initial.artifactPath);raw[raw.length-1]^=1;writeFileSync(initial.artifactPath,raw);f.options.initialBackup=initial;
 assert.throws(()=>adapter.migrateToSchema6(f.options));assert.equal(f.version(),4);
 assert.equal(readdirSync(f.options.custodyDirectory).length,0);
});
test('schema4 loss before activity commit rolls back; loss after activity commit fails closed at schema5',t=>{
 for(const phase of ['activity_before_commit','activity_after_commit']){
  const f=fixture(t,{version:4});f.options.initialBackup=initialBundle(f);
  f.setLease(p=>{if(p===phase)throw Object.assign(new Error('synthetic_lost'),{code:'synthetic_lost'});});
  rejects(()=>adapter.migrateToSchema6(f.options),'synthetic_lost');assert.equal(f.version(),phase==='activity_before_commit'?4:5);
  assert.equal(readdirSync(f.options.custodyDirectory).length,0);
 }
});
test('old database + old lifecycle receipt + old floor together cannot rewind independent current head',t=>{
 const f=fixture(t);const oldDatabase=readFileSync(f.options.databasePath);
 const oldHead=JSON.parse(readFileSync(path.join(f.options.custodyDirectory,'current-head.json')));
 const store=new ICoreStore(f.options.databasePath,{activityEnabled:true});store.activity.pairSummaryReader({installation_id:'newer-reader',display_name:'newer',capabilities:[]});store.close();
 f.refreshReceipt();const newer=adapter.sealClosedRecovery(f.options);f.pin(newer);assert.ok(newer.custodyGeneration>oldHead.generation);
 writeFileSync(f.options.databasePath,oldDatabase);f.pin({databaseSha256:sha256(oldDatabase),custodySha256:oldHead.custodySha256});
 rejects(()=>adapter.migrateToSchema6(f.options),'custody_head_rollback_rejected');
 rejects(()=>adapter.sealClosedRecovery(f.options),'custody_head_rollback_rejected');
});
test('missing or tampered independent head cannot be recreated from an existing history',t=>{
 for(const tamper of [false,true]){
  const f=fixture(t),head=path.join(f.options.custodyDirectory,'current-head.json');
  if(tamper){const raw=readFileSync(head);raw[20]^=1;writeFileSync(head,raw);}else unlinkSync(head);
  assert.throws(()=>adapter.migrateToSchema6(f.options));assert.throws(()=>adapter.sealClosedRecovery(f.options));assert.equal(f.version(),5);
 }
});
test('a second process holding custody lock excludes all migration writes',async t=>{
 const f=fixture(t),filename=path.join(f.options.custodyDirectory,'custody.lock'),before=closedHash(f.options.databasePath);
 const child=spawn(process.execPath,['--input-type=module','-e',"import fs from 'node:fs';const p=process.argv[1];const fd=fs.openSync(p,'wx');process.send('held');process.on('message',()=>{fs.closeSync(fd);fs.unlinkSync(p);process.exit(0)});",filename],{stdio:['ignore','ignore','pipe','ipc'],windowsHide:true});
 try{await once(child,'message');rejects(()=>adapter.migrateToSchema6(f.options),'custody_concurrent_operation');assert.equal(closedHash(f.options.databasePath),before);}
 finally{const exited=once(child,'exit');child.send('release');await exited;}
});

test('unmodified production adapter rejects JSON and synthetic capability before OS probing',async t=>{
 const production=await import('./recovery_adapter.mjs');const f=fixture(t);
 rejects(()=>production.migrateToSchema6({...f.options,supervisorLease:{allCoreWritersStopped:true}}),'trusted_offline_lease_required');
 rejects(()=>production.migrateToSchema6(f.options),'trusted_offline_lease_required');
 assert.equal(f.version(),5);
});
test('wrong independent custody key and forged clean receipt identity both reject',t=>{
 const f=fixture(t);rejects(()=>adapter.migrateToSchema6({...f.options,custodyKey:randomBytes(32)}),'custody_authentication_failed');
 const receipt={receiptId:'synthetic-clean-close',databasePath:f.options.databasePath,nodeId:'wrong-node',databaseSha256:closedHash(f.options.databasePath),custodySha256:null};
 rejects(()=>adapter.migrateToSchema6({...f.options,supervisorLease:syntheticLease({databasePath:f.options.databasePath,cleanCloseReceipt:receipt})}),'clean_close_identity_mismatch');
});
