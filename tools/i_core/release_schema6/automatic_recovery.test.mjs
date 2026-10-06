import assert from 'node:assert/strict';
import { randomBytes, createHmac } from 'node:crypto';
import { spawn, execFileSync } from 'node:child_process';
import { once } from 'node:events';
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { ICoreStore } from '../i_core_store.mjs';
import { createICoreServer } from '../i_core_server.mjs';
import { rollbackActivitySchema } from '../activity_control_plane.mjs';
import { syntheticLease } from '../test_fixtures/release_schema6/recovery/synthetic_lease.mjs';
import { syntheticRoot } from '../test_fixtures/release_schema6/synthetic_paths.mjs';
import { sha256, cleanEnvironment } from './package.mjs';

// Substitute only the OS lease import in independent synthetic module instances.
// Production never accepts this capability and contains no test injection switch.
function sourceModule(name,replacements={}){
 const url=new URL(name,import.meta.url);let source=readFileSync(url,'utf8');
 source=source.replace(/from '([^']+)'/g,(all,dep)=>{
  if(dep==='./lifecycle/offline_lease.mjs')return `from '${new URL('../test_fixtures/release_schema6/recovery/synthetic_lease.mjs',import.meta.url).href}'`;
  if(replacements[dep])return `from '${replacements[dep]}'`;
  return dep.startsWith('.')?`from '${new URL(dep,url).href}'`:all;
 });
 return 'data:text/javascript;base64,'+Buffer.from(source).toString('base64');
}
const rawUrl=sourceModule('./raw_state_backup.mjs');
const adapterUrl=sourceModule('./recovery_adapter.mjs',{'./raw_state_backup.mjs':rawUrl});
const raw=await import(rawUrl),adapter=await import(adapterUrl);
const automatic=await import(sourceModule('./automatic_recovery.mjs',{'./recovery_adapter.mjs':adapterUrl,'./raw_state_backup.mjs':rawUrl}));
function fixture(t,{legacy=false}={}){
 const root=syntheticRoot('schema6-auto-synthetic-');
 t.after(()=>{assert.equal(path.dirname(root),realpathSync.native(tmpdir()));assert.ok(path.basename(root).startsWith('schema6-auto-synthetic-'));rmSync(root,{recursive:true,force:true});});
 const state=path.join(root,'state'),backupDirectory=path.join(root,'backup');mkdirSync(state);mkdirSync(backupDirectory);
 const databasePath=path.join(state,'i-core.sqlite');const store=new ICoreStore(databasePath,{activityEnabled:false,companionUploadMode:'legacy_b3'});const nodeId=store.nodeId;store.close();
 const o={databasePath,custodyDirectory:path.join(root,'custody'),custodyKey:randomBytes(32),backupKey:randomBytes(32),backupDirectory,
  configurationHash:sha256('synthetic-config'),manifestSha256:sha256('synthetic-release'),expectedNodeId:nodeId,receiptId:'synthetic-next-login',legacy};
 let custody=null;
 const setLease=(hook=()=>{})=>{o.supervisorLease=syntheticLease({databasePath,origin:custody?'canonical_restart':'empty_provision',cleanCloseReceipt:{receiptId:'synthetic-original',databasePath,nodeId,databaseSha256:raw.rawFileHash(databasePath),custodySha256:custody?.custodySha256??null}},hook);};
 if(legacy){const db=new DatabaseSync(databasePath);rollbackActivitySchema(db);db.close();setLease();}
 else {setLease();custody=adapter.sealClosedRecovery(o);setLease();custody=adapter.migrateToSchema6(o);setLease();o.previousCustodySha256=custody.custodySha256;}
 return {root,state,o,nodeId,setLease,read(fn){const db=new DatabaseSync(databasePath,{readOnly:true});try{return fn(db);}finally{db.close();}},
  mutate(fn){const db=new DatabaseSync(databasePath);try{return fn(db);}finally{db.close();}}};
}
function sourceHashes(f){return raw.RAW_SUFFIXES.map(s=>existsSync(f.o.databasePath+s)?raw.rawFileHash(f.o.databasePath+s):null);}
async function killWriter(f,uncommitted=false){
 const code=`import {DatabaseSync} from 'node:sqlite';const db=new DatabaseSync(process.argv[1]);db.exec('PRAGMA journal_mode=WAL;PRAGMA wal_autocheckpoint=0');db.prepare("INSERT INTO core_metadata(key,value) VALUES('synthetic_committed','yes')").run();${uncommitted?`db.exec('BEGIN IMMEDIATE');db.prepare("INSERT INTO core_metadata(key,value) VALUES('synthetic_uncommitted','no')").run();`:''}process.stdout.write('ready\\n');setInterval(()=>{},1000);`;
 const child=spawn(process.execPath,['--input-type=module','-e',code,f.o.databasePath],{stdio:['ignore','pipe','pipe'],windowsHide:true});
 const exited=once(child,'exit');await once(child.stdout,'data');child.kill('SIGKILL');await exited;
 assert.equal(existsSync(f.o.databasePath+'-wal'),true);
}
function pinRecovery(f,result){f.o.supervisorLease=syntheticLease({databasePath:f.o.databasePath,origin:'canonical_restart',cleanCloseReceipt:{receiptId:result.receiptId,databasePath:f.o.databasePath,nodeId:f.nodeId,databaseSha256:result.databaseSha256,custodySha256:result.custodySha256}});}

test('production rejects arbitrary JSON lease before any raw copy',async t=>{
 const f=fixture(t);const production=await import('./recovery_adapter.mjs');const before=sourceHashes(f);
 assert.throws(()=>production.recoverCanonicalState({...f.o,supervisorLease:{allCoreWritersStopped:true}}),/trusted_offline_lease_required/);assert.deepEqual(sourceHashes(f),before);
});
test('raw DB WAL SHM journal backup streams and verifies exact pre-open bytes',t=>{
 const f=fixture(t);for(const suffix of ['-wal','-shm','-journal'])writeFileSync(f.o.databasePath+suffix,randomBytes(1048593));
 const before=sourceHashes(f),bundle=raw.preserveRawState(f.o),manifest=raw.verifyRawState({...f.o,...bundle});
 assert.deepEqual(manifest.files.map(x=>x.sha256??null),before);assert.deepEqual(sourceHashes(f),before);
 const encrypted=path.join(bundle.directory,manifest.files[0].encrypted_file);const bytes=readFileSync(encrypted);bytes[30]^=1;writeFileSync(encrypted,bytes);
 assert.throws(()=>raw.verifyRawState({...f.o,...bundle}),/raw_ciphertext_changed/);
});
test('inspection restore authenticates all four files before publishing exact bytes; tamper publishes nothing',t=>{
 const f=fixture(t,{legacy:true}),parent=path.join(f.root,'inspection');mkdirSync(parent,{mode:0o700});
 if(process.platform==='win32'){
  const quote=x=>"'"+x.replaceAll("'","''")+"'";
  execFileSync(path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe'),['-NoProfile','-NonInteractive','-Command',
   '. '+quote(fileURLToPath(new URL('./lifecycle/protected_paths.ps1',import.meta.url)))+'; Protect-NewDirectory '+quote(parent)],{env:cleanEnvironment(),windowsHide:true,stdio:['ignore','pipe','pipe']});
 }
 for(const suffix of ['-wal','-shm','-journal'])writeFileSync(f.o.databasePath+suffix,randomBytes(8193));
 const before=sourceHashes(f),bundle=raw.preserveRawState(f.o),outputDirectory=path.join(parent,'restored');
 const result=raw.restoreRawStateForInspection({...f.o,...bundle,outputDirectory});assert.equal(result.activationSupported,false);
 assert.equal(JSON.parse(readFileSync(path.join(outputDirectory,'.i-core-inspection.json'))).inspectionOnly,true);
 assert.deepEqual(raw.RAW_SUFFIXES.map(s=>raw.rawFileHash(path.join(outputDirectory,'i-core.sqlite'+s))),before);assert.deepEqual(sourceHashes(f),before);
 const inspectionPath=path.join(outputDirectory,'i-core.sqlite'),newCustody=path.join(f.root,'new-custody');let probed=false;
 const inspectionLease=syntheticLease({databasePath:inspectionPath},()=>{probed=true;});
 assert.throws(()=>adapter.recoverCanonicalState({...f.o,databasePath:inspectionPath,custodyDirectory:newCustody,supervisorLease:inspectionLease,legacy:true}),/inspection_activation_unsupported/);
 assert.equal(probed,false);assert.equal(existsSync(newCustody),false);assert.equal(existsSync(path.join(outputDirectory,adapter.RECOVERY_PENDING)),false);
 assert.deepEqual(raw.RAW_SUFFIXES.map(s=>raw.rawFileHash(inspectionPath+s)),before);
 assert.throws(()=>raw.restoreRawStateForInspection({...f.o,...bundle,outputDirectory}),/fresh_inspection_directory_required/);
 assert.throws(()=>raw.restoreRawStateForInspection({...f.o,...bundle,outputDirectory:path.join(f.state,'bad-restore')}),/inspection_must_be_separate/);
 const last=path.join(bundle.directory,'database-journal.aes256gcm');const damaged=readFileSync(last);damaged[25]^=1;writeFileSync(last,damaged);
 const rejected=path.join(parent,'rejected');assert.throws(()=>raw.restoreRawStateForInspection({...f.o,...bundle,outputDirectory:rejected}),/raw_ciphertext_changed/);
 assert.equal(existsSync(rejected),false);assert.deepEqual(readdirSync(parent),['restored']);
});
for(const uncommitted of [false,true])test(`killed Node: committed WAL replay; uncommitted=${uncommitted}; next login opens schema6`,async t=>{
 const f=fixture(t);await killWriter(f,uncommitted);const before=sourceHashes(f);let opened=false;
 f.setLease(phase=>{if(phase==='copy_before_open'){opened=true;assert.deepEqual(sourceHashes(f),before);const bundles=readdirSync(f.o.backupDirectory).filter(x=>x.startsWith('raw-'));assert.equal(bundles.length,1);}});
 const result=adapter.recoverCanonicalState(f.o);assert.equal(opened,true);assert.equal(result.schemaVersion,6);pinRecovery(f,result);
 assert.equal(adapter.verifyCanonicalRestart(f.o).ok,true);
 assert.equal(f.read(db=>db.prepare("SELECT value FROM core_metadata WHERE key='synthetic_committed'").get().value),'yes');
 assert.equal(f.read(db=>db.prepare("SELECT value FROM core_metadata WHERE key='synthetic_uncommitted'").get()),undefined);
 const core=createICoreServer({databasePath:f.o.databasePath,activityEnabled:false,companionUploadMode:'legacy_b3',companionReplyJobsEnabled:false});await core.listen({host:'127.0.0.1',port:0});await core.close();
 assert.equal(existsSync(path.join(f.state,adapter.RECOVERY_PENDING)),false);
});
test('legacy schema4 dirty WAL migration happens only on copy, preserves identity, and starts schema6',async t=>{
 const f=fixture(t,{legacy:true});await killWriter(f,true);const before=sourceHashes(f);let checked=false;
 f.setLease(phase=>{if(phase==='copy_migration_before_commit'){checked=true;assert.deepEqual(sourceHashes(f),before);}});
 const result=adapter.recoverCanonicalState(f.o);assert.equal(checked,true);pinRecovery(f,result);assert.equal(adapter.verifyCanonicalRestart(f.o).ok,true);
 assert.equal(f.read(db=>db.prepare("SELECT value FROM core_metadata WHERE key='node_id'").get().value),f.nodeId);
});
test('interrupted copy migration preserves all original files and next login stops',async t=>{
 const f=fixture(t,{legacy:true});await killWriter(f);const before=sourceHashes(f);
 f.setLease(phase=>{if(phase==='copy_migration_before_commit')throw new Error('synthetic_migration_interruption');});
 assert.throws(()=>adapter.recoverCanonicalState(f.o),/synthetic_migration_interruption/);assert.deepEqual(sourceHashes(f),before);
 assert.throws(()=>automatic.needsStartupRecovery(f.o.databasePath,null),/recovery_interrupted_review_required/);
});
test('corrupt original is archived, rejected on copy integrity, and left intact',t=>{
 const f=fixture(t);writeFileSync(f.o.databasePath,randomBytes(4096));const before=sourceHashes(f);
 assert.throws(()=>adapter.recoverCanonicalState(f.o));assert.deepEqual(sourceHashes(f),before);assert.ok(readdirSync(f.o.backupDirectory).some(n=>n.startsWith('raw-')));
 assert.throws(()=>automatic.needsStartupRecovery(f.o.databasePath,{phase:'listening'}),/recovery_interrupted_review_required/);
});
test('external head rejects old floor even with old complete database',t=>{
 const f=fixture(t);const old=readFileSync(f.o.databasePath),oldPin=f.o.previousCustodySha256;
 f.setLease();const newer=adapter.sealClosedRecovery(f.o);assert.notEqual(newer.custodySha256,oldPin);
 writeFileSync(f.o.databasePath,old);assert.throws(()=>adapter.recoverCanonicalState(f.o),/custody_head_rollback_rejected/);
});
for(const changed of [false,true])test(`old activity-only custody requires exact closed Core bytes; changed=${changed}`,t=>{
 const f=fixture(t),headPath=path.join(f.o.custodyDirectory,'current-head.json');
 const head=JSON.parse(readFileSync(headPath));delete head.authentication;
 const body=JSON.parse(readFileSync(path.join(f.o.custodyDirectory,head.custodySha256+'.floor.json')));delete body.authentication;delete body.progressWitness;
 const sign=value=>Buffer.from(JSON.stringify({...value,authentication:createHmac('sha256',f.o.custodyKey).update('i-core-floor-custody-v1\0').update(JSON.stringify(value)).digest('hex')})+'\n');
 const floor=sign(body);head.custodySha256=sha256(floor);writeFileSync(path.join(f.o.custodyDirectory,head.custodySha256+'.floor.json'),floor);
 const headRaw=sign(head);writeFileSync(headPath,headRaw);writeFileSync(path.join(f.o.custodyDirectory,sha256(headRaw)+'.head.json'),headRaw);f.o.previousCustodySha256=head.custodySha256;
 if(changed)f.mutate(db=>db.prepare("INSERT INTO core_metadata(key,value) VALUES('unwitnessed_core_change','synthetic')").run());
 if(changed)assert.throws(()=>adapter.recoverCanonicalState(f.o),/old_custody_progress_unverifiable/);
 else assert.equal(adapter.recoverCanonicalState(f.o).ok,true);
});
test('different canonical path cannot activate an exact live database copy',t=>{
 const f=fixture(t);const other=path.join(f.state,'other.sqlite');copyFileSync(f.o.databasePath,other);
 assert.throws(()=>adapter.recoverCanonicalState({...f.o,databasePath:other}));
});
test('backup role never becomes live through automatic recovery',t=>{
 const f=fixture(t);f.mutate(db=>db.prepare("UPDATE activity_metadata SET value='backup_read_only' WHERE key='database_role'").run());const before=sourceHashes(f);
 assert.throws(()=>adapter.recoverCanonicalState(f.o),/backup_activation_unsupported/);assert.deepEqual(sourceHashes(f),before);
});
test('mutable domain record edits may advance without rollback of immutable operation prefix',t=>{
 const f=fixture(t);f.mutate(db=>{db.prepare('INSERT INTO domain_records VALUES(?,?,?,?,?,?)').run('production','notes','item',1,'{}','first');db.prepare('INSERT INTO domain_ops VALUES(?,?,?,?,?,?,?)').run('production','p','notes','op1','digest1','{}','{}');});
 f.setLease();const pinned=adapter.sealClosedRecovery(f.o);f.o.previousCustodySha256=pinned.custodySha256;
 f.mutate(db=>{db.prepare("UPDATE domain_records SET revision=2,body_json='edited' WHERE id='item'").run();db.prepare('INSERT INTO domain_ops VALUES(?,?,?,?,?,?,?)').run('production','p','notes','op2','digest2','{}','{}');});
 const result=adapter.recoverCanonicalState(f.o);assert.equal(result.ok,true);
 assert.equal(f.read(db=>db.prepare("SELECT revision FROM domain_records WHERE id='item'").get().revision),2);
});
test('larger new maximum cannot hide mutation of an old immutable operation',t=>{
 const f=fixture(t);f.mutate(db=>db.prepare('INSERT INTO domain_ops VALUES(?,?,?,?,?,?,?)').run('production','p','notes','op1','digest1','{}','{}'));
 f.setLease();const pinned=adapter.sealClosedRecovery(f.o);f.o.previousCustodySha256=pinned.custodySha256;
 f.mutate(db=>{db.prepare("UPDATE domain_ops SET request_digest='changed' WHERE op_id='op1'").run();db.prepare('INSERT INTO domain_ops VALUES(?,?,?,?,?,?,?)').run('production','p','notes','op2','digest2','{}','{}');});
 assert.throws(()=>adapter.recoverCanonicalState(f.o),/recovery_history_diverged/);
});
test('CoreStore same-device re-pair is legitimate progress at clean seal and crash recovery',t=>{
 const f=fixture(t);
 const pair=()=>{const store=new ICoreStore(f.o.databasePath,{activityEnabled:false,companionUploadMode:'legacy_b3'});try{return store.pairDevice({device_id:'same-device',display_name:'Synthetic',platform:'test',client_version:'1',capabilities:[]},randomBytes(32).toString('hex')).device_token;}finally{store.close();}};
 const first=pair();f.setLease();const closed=adapter.sealClosedRecovery(f.o);f.o.previousCustodySha256=closed.custodySha256;
 assert.notEqual(pair(),first);
 f.o.supervisorLease=syntheticLease({databasePath:f.o.databasePath,origin:'canonical_restart',cleanCloseReceipt:{receiptId:'synthetic-original',databasePath:f.o.databasePath,nodeId:f.nodeId,databaseSha256:raw.rawFileHash(f.o.databasePath),custodySha256:closed.custodySha256}});
 const rePaired=adapter.sealClosedRecovery(f.o);f.o.previousCustodySha256=rePaired.custodySha256;
 pair();const recovered=adapter.recoverCanonicalState(f.o);assert.equal(recovered.ok,true);
});
test('interruption after atomic DB replace blocks next login; external head cannot silently rewind',t=>{
 const f=fixture(t);const head=readFileSync(path.join(f.o.custodyDirectory,'current-head.json'));
 f.setLease(phase=>{if(phase==='copy_after_replace')throw new Error('synthetic_replace_interruption');});
 assert.throws(()=>adapter.recoverCanonicalState(f.o),/synthetic_replace_interruption/);
 assert.deepEqual(readFileSync(path.join(f.o.custodyDirectory,'current-head.json')),head);
 assert.throws(()=>automatic.needsStartupRecovery(f.o.databasePath,{phase:'listening'}),/recovery_interrupted_review_required/);
});
