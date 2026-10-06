import assert from 'node:assert/strict';
import test from 'node:test';
import { Worker, MessageChannel } from 'node:worker_threads';
import { once } from 'node:events';
import { spawnSync } from 'node:child_process';
import { copyFileSync, linkSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { readRecoveryWitnessComponent } from './recovery_adapter.mjs';
import { cleanEnvironment, sha256 } from './package.mjs';
import { scaleFixture, seedScale, raw } from '../test_fixtures/release_schema6/recovery/scale_fixture.mjs';

const entry=new URL('./recovery_witness_worker.mjs',import.meta.url);
function sealedFloor(f){const head=JSON.parse(readFileSync(path.join(f.o.custodyDirectory,'current-head.json')));return JSON.parse(readFileSync(path.join(f.o.custodyDirectory,head.custodySha256+'.floor.json')));}
function priorWitness(f){return sealedFloor(f).progressWitness;}
function launch(filename,component,prior=null,extra={},workerEntry=entry){
 const {port1,port2}=new MessageChannel(),signalBuffer=new SharedArrayBuffer(4);
 const worker=new Worker(workerEntry,{workerData:{kind:'schema6-readonly-witness-v1',component,databasePath:filename,priorWitness:prior,context:null,resultPort:port2,signalBuffer,...extra},transferList:[port2]});
 return {worker,port:port1,signal:new Int32Array(signalBuffer)};
}
async function resultOf(run){
 const exit=once(run.worker,'exit');
 try{
  const [message]=await Promise.race([once(run.port,'message'),exit.then(()=>{throw new Error('worker_exited_without_result');})]);
  await exit;return message;
 }finally{run.port.close();await run.worker.terminate();}
}

test('read-only worker transports the three full component witnesses without row bodies or secrets',{timeout:120000},async t=>{
 const f=scaleFixture(t);seedScale(f,{messages:20,records:20});f.seal();const prior=priorWitness(f),before=raw.rawFileHash(f.o.databasePath);
 const secret=f.mutate(db=>db.prepare("SELECT value FROM core_metadata WHERE key='cursor_secret'").get().value);
 for(const component of ['change_events','chat_messages','domain']){
  const expected=f.mutate(db=>readRecoveryWitnessComponent(db,component,prior));
  const run=launch(f.o.databasePath,component,prior),message=await resultOf(run);
  assert.equal(message.kind,'schema6-readonly-witness-result-v1');assert.equal(message.component,component);assert.equal(message.ok,true);
  assert.deepEqual(message.result,expected);assert.equal(Atomics.load(run.signal,0),1);
  const encoded=JSON.stringify(message);assert.equal(encoded.includes(secret),false);assert.equal(encoded.includes('scale-record-1'),false);assert.equal(encoded.includes('scale-message-1'),false);
  assert.equal(raw.rawFileHash(f.o.databasePath),before);
 }
});

test('activity worker preserves full floor checks and canonical binding for an immutable copy',{timeout:120000},async t=>{
 const f=scaleFixture(t);seedScale(f,{messages:20,records:20});f.seal();
 const floor=sealedFloor(f),copy=path.join(f.state,'activity-readonly-copy.sqlite');copyFileSync(f.o.databasePath,copy);
 const before=raw.rawFileHash(copy),secret=f.mutate(db=>db.prepare("SELECT value FROM core_metadata WHERE key='cursor_secret'").get().value);
 for(const floorMode of ['none','progress','exact']){
  const context={canonicalDatabasePath:f.o.databasePath,priorActivityFloor:floorMode==='none'?null:floor.activityRecoveryFloor,floorMode};
  const expected=f.mutate(db=>readRecoveryWitnessComponent(db,'activity',floor.progressWitness,context));
  const message=await resultOf(launch(copy,'activity',floor.progressWitness,{context}));
  assert.equal(message.ok,true);assert.deepEqual(message.result,expected);
  assert.deepEqual(Object.keys(message.result).sort(),['activityFloor','bindingDigest','floorMode','nodeId','schemaVersion']);
  assert.equal(message.result.schemaVersion,6);assert.equal(message.result.nodeId,f.nodeId);assert.equal(message.result.floorMode,floorMode);
  assert.equal(message.result.bindingDigest,sha256('activity-live-path:'+path.normalize(realpathSync.native(f.o.databasePath))));
  assert.deepEqual(message.result.activityFloor,floor.activityRecoveryFloor);assert.equal(JSON.stringify(message).includes(secret),false);
  assert.equal(raw.rawFileHash(copy),before);
 }
 const wrongBinding={canonicalDatabasePath:copy,priorActivityFloor:null,floorMode:'none'};
 let message=await resultOf(launch(copy,'activity',null,{context:wrongBinding}));
 assert.equal(message.ok,false);assert.equal(message.errorCode,'activity_database_binding_mismatch');
 for(const floorMode of ['progress','exact']){
  const context={canonicalDatabasePath:f.o.databasePath,priorActivityFloor:{...floor.activityRecoveryFloor,digest:'0'.repeat(64)},floorMode};
  message=await resultOf(launch(copy,'activity',null,{context}));
  assert.equal(message.ok,false);assert.equal(message.errorCode,'recovery_lineage_unverified');
 }
});

test('activity context is exact and cannot give other components additional authority',{timeout:120000},async t=>{
 const f=scaleFixture(t),valid={canonicalDatabasePath:f.o.databasePath,priorActivityFloor:null,floorMode:'none'};
 for(const context of [null,{},[],{...valid,unexpected:true},{...valid,canonicalDatabasePath:''},{...valid,canonicalDatabasePath:1},{...valid,floorMode:'other'},{...valid,priorActivityFloor:{}},{...valid,floorMode:'progress'},{...valid,floorMode:'exact',priorActivityFloor:[]}]){
  const message=await resultOf(launch(f.o.databasePath,'activity',null,{context}));
  assert.equal(message.ok,false);assert.equal(message.errorCode,'invalid_internal_arguments');
 }
 for(const component of ['change_events','chat_messages','domain']){
  const message=await resultOf(launch(f.o.databasePath,component,null,{context:valid}));
  assert.equal(message.ok,false);assert.equal(message.errorCode,'invalid_internal_arguments');
 }
});

test('activity worker rejects real orphaned chat-device foreign keys',{timeout:120000},async t=>{
 const f=scaleFixture(t);seedScale(f,{messages:20,records:20});f.seal();const floor=sealedFloor(f);
 f.mutate(db=>{
  assert.equal(db.prepare('SELECT device_id FROM devices WHERE device_id=?').get('scale-device').device_id,'scale-device');
  db.exec('PRAGMA foreign_keys=OFF');
  assert.equal(db.prepare('DELETE FROM devices WHERE device_id=?').run('scale-device').changes,1);
  const violations=db.prepare('PRAGMA foreign_key_check').all();
  assert.equal(violations.length,20);assert.ok(violations.every(row=>row.table==='chat_messages'&&row.parent==='devices'));
 });
 const before=raw.rawFileHash(f.o.databasePath);
 for(const floorMode of ['none','progress','exact']){
  const context={canonicalDatabasePath:f.o.databasePath,priorActivityFloor:floorMode==='none'?null:floor.activityRecoveryFloor,floorMode};
  const message=await resultOf(launch(f.o.databasePath,'activity',floor.progressWitness,{context}));
  assert.equal(message.ok,false);assert.equal(message.errorCode,'database_integrity_failed');
  assert.equal(raw.rawFileHash(f.o.databasePath),before);
 }
});

test('worker rejects sidecars, linked database, and non-exact capability contracts',{timeout:120000},async t=>{
 const f=scaleFixture(t);
 for(const extra of [{unexpected:true},{kind:'arbitrary'},{component:'custody'},{priorWitness:[]}]){
  const run=launch(f.o.databasePath,'domain',null,extra),message=await resultOf(run);
  assert.equal(message.ok,false);assert.equal(message.errorCode,'invalid_internal_arguments');
 }
 for(const suffix of ['-wal','-shm','-journal']){
  const filename=path.join(f.state,'sidecar-'+suffix.slice(1)+'.sqlite');copyFileSync(f.o.databasePath,filename);writeFileSync(filename+suffix,'');
  const message=await resultOf(launch(filename,'domain'));assert.equal(message.ok,false);assert.equal(message.errorCode,'state_sidecars_require_review');
 }
 const linked=path.join(f.state,'linked.sqlite');linkSync(f.o.databasePath,linked);
 const message=await resultOf(launch(linked,'domain'));assert.equal(message.ok,false);assert.equal(message.errorCode,'linked_path_rejected');
 const invalid=path.join(f.state,'invalid.sqlite');writeFileSync(invalid,'synthetic-private-error-marker');
 const rejected=await resultOf(launch(invalid,'domain'));
 assert.equal(rejected.ok,false);assert.equal(rejected.errorCode,'runtime_operation_failed');
 assert.equal(JSON.stringify(rejected).includes('synthetic-private-error-marker'),false);
 assert.deepEqual(Object.keys(rejected).sort(),['component','errorCode','kind','ok']);
});

test('worker propagates bounded history and materialization rejection codes',{timeout:120000},async t=>{
 const f=scaleFixture(t);seedScale(f,{messages:20,records:20});f.seal();const prior=priorWitness(f);
 f.mutate(db=>db.exec("UPDATE change_events SET payload_json='{}' WHERE server_sequence=1"));
 let message=await resultOf(launch(f.o.databasePath,'change_events',prior));assert.equal(message.ok,false);assert.equal(message.errorCode,'recovery_history_diverged');
 f.mutate(db=>db.prepare('UPDATE domain_records SET body_json=? WHERE id=?').run('{"tampered":true}','scale-record-1'));
 message=await resultOf(launch(f.o.databasePath,'domain',prior));assert.equal(message.ok,false);assert.match(message.errorCode,/^domain_record_(rollback_rejected|result_mismatch)$/);
 assert.deepEqual(Object.keys(message).sort(),['component','errorCode','kind','ok']);
});

test('cancelled or immediately terminated worker cannot publish a usable success',{timeout:120000},async t=>{
 const f=scaleFixture(t),cancelledBuffer=new SharedArrayBuffer(4);Atomics.store(new Int32Array(cancelledBuffer),0,2);
 const cancelled=launch(f.o.databasePath,'domain',null,{signalBuffer:cancelledBuffer}),message=await resultOf(cancelled);
 assert.equal(message.ok,false);assert.equal(Atomics.load(new Int32Array(cancelledBuffer),0),2);
 const run=launch(f.o.databasePath,'domain'),messages=[];run.port.on('message',value=>messages.push(value));
 await run.worker.terminate();run.port.close();assert.equal(messages.some(value=>value.ok===true),false);assert.equal(Atomics.load(run.signal,0),0);
});

test('main thread invocation has no recovery or floor authority',{timeout:30000},()=>{
 const result=spawnSync(process.execPath,[fileURLToPath(entry)],{env:cleanEnvironment(),windowsHide:true,encoding:'utf8'});
 assert.equal(result.status,1);assert.equal(result.stdout,'');assert.equal(result.stderr.includes('Error:'),false);
});

test('adapter initialization failure is a finite private result before database open',{timeout:30000},async t=>{
 const f=scaleFixture(t),before=raw.rawFileHash(f.o.databasePath);
 const failure='data:text/javascript;base64,'+Buffer.from("throw Object.assign(new Error('synthetic-private-loader-text'),{code:'domain_operation_authentication_failed'});").toString('base64');
 // Test-local module substitution only; the production import is a fixed
 // literal package dependency and exposes no verifier or path parameter.
 const source=readFileSync(entry,'utf8')
  .replace("await import('./recovery_adapter.mjs')",`await import('${failure}')`)
  .replace(/from '([^']+)'/g,(all,dependency)=>dependency.startsWith('.')?`from '${new URL(dependency,entry).href}'`:all);
 const workerEntry=new URL('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
 // A nonexistent database would produce a path error if the code touched it
 // before resolving the reader. The loader failure must win instead.
 const run=launch(path.join(f.state,'must-never-open.sqlite'),'domain',null,{},workerEntry),message=await resultOf(run);
 assert.equal(message.ok,false);assert.equal(message.errorCode,'domain_operation_authentication_failed');assert.equal(Atomics.load(run.signal,0),1);
 assert.equal(JSON.stringify(message).includes('synthetic-private-loader-text'),false);
 assert.equal(raw.rawFileHash(f.o.databasePath),before);
});

test('private publication failure wakes the parent with failure, never success',{timeout:30000},async t=>{
 const f=scaleFixture(t);
 const source=readFileSync(entry,'utf8')
  .replace('port.postMessage(message);',"throw new Error('synthetic-publication-failure');")
  .replace("await import('./recovery_adapter.mjs')",`await import('${new URL('./recovery_adapter.mjs',entry).href}')`)
  .replace(/from '([^']+)'/g,(all,dependency)=>dependency.startsWith('.')?`from '${new URL(dependency,entry).href}'`:all);
 const workerEntry=new URL('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
 for(const initialSignal of [0,3]){
  const signalBuffer=new SharedArrayBuffer(4);Atomics.store(new Int32Array(signalBuffer),0,initialSignal);
  const run=launch(f.o.databasePath,'domain',null,{signalBuffer},workerEntry),messages=[];run.port.on('message',value=>messages.push(value));
  const [exitCode]=await once(run.worker,'exit');run.port.close();
  assert.equal(exitCode,1);assert.deepEqual(messages,[]);
  assert.equal(Atomics.load(new Int32Array(signalBuffer),0),initialSignal===0?2:initialSignal);
 }
});
