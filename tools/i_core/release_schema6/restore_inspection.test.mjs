import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync,readFileSync,writeFileSync,rmSync,existsSync,linkSync,symlinkSync } from 'node:fs';
import { syntheticRoot } from '../test_fixtures/release_schema6/synthetic_paths.mjs';
import path from 'node:path';
import { createHash,createCipheriv,randomBytes } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { Worker } from 'node:worker_threads';
import { createRuntimeBackup,BACKUP_ROLES } from './backup_bundle.mjs';
import { restoreRuntimeBackupForInspection } from './restore_inspection.mjs';
import { createICoreServer } from '../i_core_server.mjs';
import { databaseInspectionFingerprint,openInspectionDatabase } from '../inspection_read_only.mjs';

const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
function fixture(t) {
  const root=syntheticRoot('core-restore-synthetic-');t.after(()=>rmSync(root,{recursive:true,force:true}));
  const sources=path.join(root,'sources'),release=path.join(sources,'release');mkdirSync(release,{recursive:true});
  const database=path.join(sources,'core.sqlite'),key=randomBytes(32),db=new DatabaseSync(database);
  db.exec('CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT); CREATE TABLE devices(device_id TEXT PRIMARY KEY,token_hash TEXT,last_seen INTEGER); CREATE TABLE no_pk(payload BLOB,body TEXT,n INTEGER,optional TEXT);');
  const metadata=db.prepare('INSERT INTO core_metadata VALUES (?,?)');
  for(const [k,v] of [['schema_version','4'],['node_id','synthetic-node-id'],['cursor_secret',randomBytes(32).toString('base64url')]])metadata.run(k,v);
  db.prepare('INSERT INTO devices VALUES (?,?,?)').run('synthetic-device-1','private-token-hash',9);
  const row=db.prepare('INSERT INTO no_pk VALUES (?,?,?,?)');row.run(Buffer.from([0,255]),'private-body',9007199254740993n,null);row.run(Buffer.from('b'),'another-body',-3n,'');row.run(Buffer.from('b'),'another-body',-3n,'');db.close();
  const entries=[{role:'database',name:'data/core.sqlite',source_path:database,sha256:sha(readFileSync(database))}];
  const manifest=path.join(release,'manifest.json');writeFileSync(manifest,'{"synthetic":true}');entries.push({role:'release',name:'manifest.json',source_path:manifest,sha256:sha(readFileSync(manifest))});
  for(const role of BACKUP_ROLES.filter(r=>!['database','release'].includes(r))){
    const source_path=path.join(sources,role+'.json');
    writeFileSync(source_path,JSON.stringify(role==='recovery_custody'?{format:'i-core-recovery-custody-v1',mode:'initial_schema4',node_id:'synthetic-node-id',database_path:database}:{synthetic:true,role}));
    entries.push({role,name:'inputs/'+role+'.json',source_path,sha256:sha(readFileSync(source_path))});
  }
  const spec={format:'i-core-runtime-backup-spec-v1',source_schema:4,node_id:'synthetic-node-id',canonical_database_path:database,old_release_root:release,old_release_manifest_sha256:entries[1].sha256,entries};
  const outputDirectory=path.join(root,'restored');
  const create=()=>createRuntimeBackup({spec,key,outputDirectory:path.join(root,'backup')});
  const restore=(r,extra={})=>restoreRuntimeBackupForInspection({artifactPath:r.artifactPath,artifactSha256:r.artifactSha256,key,outputDirectory,expectedDatabaseFingerprintSha256:r.databaseInspection.dataSha256,...extra});
  return {root,sources,release,database,key,spec,outputDirectory,create,restore};
}
function malicious(f,mutate) {
  const entries=f.spec.entries.map(e=>({...e,bytes:readFileSync(e.source_path).length}));
  mutate(entries);const manifest={format:'i-core-runtime-backup-v1',scope:'inventory_only',production_completeness_not_attested:true,activation_supported:false,spec:{...f.spec,entries}};
  const body=Buffer.from(JSON.stringify(manifest)),size=Buffer.alloc(4);size.writeUInt32BE(body.length);
  const magic=Buffer.from('ICRUNB01'),nonce=randomBytes(12),cipher=createCipheriv('aes-256-gcm',f.key,nonce);cipher.setAAD(magic);
  const bytes=Buffer.concat([magic,nonce,cipher.update(Buffer.concat([size,body,...f.spec.entries.map(e=>readFileSync(e.source_path))])),cipher.final(),cipher.getAuthTag()]);
  const artifactPath=path.join(f.root,'malicious.bundle');writeFileSync(artifactPath,bytes);
  return {artifactPath,artifactSha256:sha(bytes),databaseInspection:databaseInspectionFingerprint(f.database)};
}

test('actual encrypted restore starts immutable Core listener; all rows/devices match; no live activation or source changes',async t=>{
  const f=fixture(t),before=readFileSync(f.database),r=f.create(),report=await f.restore(r);
  assert.equal(report.restored,true);assert.equal(report.inspectionOnly,true);assert.equal(report.activation_supported,false);
  assert.deepEqual(report.databaseInspection,r.databaseInspection);assert.equal(report.databaseInspection.devices.count,1);
  assert.equal(report.databaseInspection.tables.find(t=>t.name==='no_pk').rows,3);
  assert.equal(report.coreHealth.mode,'inspection_read_only');assert.equal(report.coreHealth.immutable,true);assert.equal(report.deniedRoutes.length,5);
  assert.equal(report.databaseBytesUnchanged,true);assert.equal(report.sidecarsAbsent,true);
  const restored=path.join(f.outputDirectory,'database/data/core.sqlite');
  assert.deepEqual(readFileSync(restored),before);assert.deepEqual(readFileSync(f.database),before);
  assert.equal(existsSync(path.join(f.outputDirectory,'.inspection-ready.json')),true);
  assert.throws(()=>createICoreServer({databasePath:restored}),e=>e.code==='backup_activation_unsupported');
  for(const suffix of ['-wal','-shm','-journal']){assert.equal(existsSync(restored+suffix),false);assert.equal(existsSync(f.database+suffix),false);}
  const serialized=JSON.stringify(report);for(const secret of ['private-body','private-token-hash','synthetic-device-1','synthetic-node-id',f.root])assert.equal(serialized.includes(secret),false);
});

test('SQLite query_only and readOnly prevent SQL writes even after query_only is disabled; schema6 readonly does not migrate',async t=>{
  const f=fixture(t),rw=new DatabaseSync(f.database);rw.exec("UPDATE core_metadata SET value='6' WHERE key='schema_version'");rw.close();
  const before=readFileSync(f.database),db=openInspectionDatabase(f.database);
  assert.equal(db.prepare('PRAGMA query_only').get().query_only,1);
  assert.throws(()=>db.exec("UPDATE core_metadata SET value='changed' WHERE key='node_id'"));db.exec('PRAGMA query_only=OFF');
  assert.throws(()=>db.exec('CREATE TABLE forbidden(x)'));db.close();
  const core=createICoreServer({databasePath:f.database,mode:'inspection_read_only'});t.after(()=>core.close());
  assert.equal(core.inspection().schemaVersion,6);await assert.rejects(core.listen({host:'0.0.0.0'}),e=>e.code==='inspection_loopback_required');
  const address=await core.listen();assert.equal(address.address,'127.0.0.1');assert.throws(()=>core.enablePairing('x'),e=>e.code==='inspection_read_only');
  for(const method of ['POST','PUT','DELETE','PATCH','GET']){const response=await fetch(`http://127.0.0.1:${address.port}/v1/core/pair`,{method});assert.equal(response.status,403);await response.text();}
  await core.close();assert.deepEqual(readFileSync(f.database),before);
  assert.throws(()=>createICoreServer({databasePath:f.database,mode:'inspection_read_only',workerSecret:'forbidden'}),e=>e.code==='inspection_configuration_rejected');
});

test('typed row fingerprints retain bigint/blob/null/duplicates and ignore physical row order',t=>{
  const f=fixture(t),first=databaseInspectionFingerprint(f.database),db=new DatabaseSync(f.database);
  db.exec('CREATE TEMP TABLE tmp AS SELECT * FROM no_pk; DELETE FROM no_pk; INSERT INTO no_pk SELECT * FROM tmp ORDER BY n; DROP TABLE tmp;');db.close();
  assert.deepEqual(databaseInspectionFingerprint(f.database),first);
  const second=new DatabaseSync(f.database);second.exec('UPDATE no_pk SET optional=\'\' WHERE optional IS NULL');second.close();
  assert.notEqual(databaseInspectionFingerprint(f.database).dataSha256,first.dataSha256);
  const third=new DatabaseSync(f.database);third.exec("CREATE TABLE sqliteCustom(value TEXT); INSERT INTO sqliteCustom VALUES ('all user tables');");third.close();
  assert.equal(databaseInspectionFingerprint(f.database).tables.find(table=>table.name==='sqliteCustom').rows,1);
});

test('wrong key, ciphertext corruption, external anchor and baseline mismatch leave no ready restore',async t=>{
  for(const kind of ['key','cipher','anchor','baseline','missing-baseline']){
    const f=fixture(t),r=f.create(),extra={};
    if(kind==='key')extra.key=randomBytes(32);if(kind==='anchor')extra.artifactSha256='0'.repeat(64);
    if(kind==='cipher'){const bytes=readFileSync(r.artifactPath);bytes[bytes.length-1]^=1;writeFileSync(r.artifactPath,bytes);extra.artifactSha256=sha(bytes);}
    if(kind==='baseline')extra.expectedDatabaseFingerprintSha256='0'.repeat(64);if(kind==='missing-baseline')extra.expectedDatabaseFingerprintSha256=undefined;
    await assert.rejects(f.restore(r,extra));assert.equal(existsSync(path.join(f.outputDirectory,'.inspection-ready.json')),false);
    assert.equal(existsSync(f.outputDirectory),false);
  }
});

test('existing output, source-directory placement, hardlinked artifact and linked parent reject',async t=>{
  const f=fixture(t),r=f.create();mkdirSync(f.outputDirectory);writeFileSync(path.join(f.outputDirectory,'keep'),'keep');
  await assert.rejects(f.restore(r),e=>e.code==='fresh_output_required');assert.equal(readFileSync(path.join(f.outputDirectory,'keep'),'utf8'),'keep');
  await assert.rejects(f.restore(r,{outputDirectory:path.join(f.sources,'restore')}),e=>e.code==='independent_output_required');
  const link=path.join(f.root,'hardlink');linkSync(r.artifactPath,link);await assert.rejects(f.restore(r));rmSync(link);
  const actual=path.join(f.root,'actual-parent'),alias=path.join(f.root,'alias-parent');mkdirSync(actual);symlinkSync(actual,alias,'junction');
  await assert.rejects(f.restore(r,{outputDirectory:path.join(alias,'restore')}),e=>e.code==='linked_path_rejected');
});

test('authenticated traversal, Windows aliases and file/directory collisions reject before output creation',async t=>{
  for(const name of ['../escape','/absolute','a\\b','foo:stream','foo.','foo ','CON','nul.txt','x/../y']){
    const f=fixture(t),r=malicious(f,entries=>entries[0].name=name);await assert.rejects(f.restore(r));assert.equal(existsSync(f.outputDirectory),false);
  }
  const f=fixture(t);const entry=f.spec.entries.find(e=>e.role==='configuration');
  const source_path=path.join(f.sources,'config2');writeFileSync(source_path,'second');f.spec.entries.push({role:'configuration',name:entry.name+'/child',source_path,sha256:sha(readFileSync(source_path))});
  const r=f.create();await assert.rejects(f.restore(r),e=>e.code==='inspection_path_collision');assert.equal(existsSync(f.outputDirectory),false);
});

test('ciphertext changes during second extraction pass do not publish restore',async t=>{
  const f=fixture(t),entry=f.spec.entries.find(e=>e.role==='configuration');writeFileSync(entry.source_path,Buffer.alloc(24*1024*1024,65));entry.sha256=sha(readFileSync(entry.source_path));
  const r=f.create(),shared=new SharedArrayBuffer(4),state=new Int32Array(shared);
  const worker=new Worker(`const {workerData}=require('node:worker_threads');const fs=require('node:fs');const state=new Int32Array(workerData.shared);Atomics.store(state,0,1);Atomics.notify(state,0);while(!fs.existsSync(workerData.output)){};const fd=fs.openSync(workerData.artifact,'r+');const size=fs.fstatSync(fd).size;const byte=Buffer.alloc(1);fs.readSync(fd,byte,0,1,size-1);byte[0]^=1;fs.writeSync(fd,byte,0,1,size-1);fs.closeSync(fd);Atomics.store(state,0,2);`,{eval:true,workerData:{shared,output:f.outputDirectory,artifact:r.artifactPath}});
  try {while(Atomics.load(state,0)!==1)Atomics.wait(state,0,0,1000);await assert.rejects(f.restore(r));assert.equal(Atomics.load(state,0),2);assert.equal(existsSync(path.join(f.outputDirectory,'.inspection-ready.json')),false);}
  finally{await worker.terminate();}
});

test('failed final release validation cleans extracted output and never publishes valid receipt',async t=>{
  const f=fixture(t),r=f.create();await assert.rejects(f.restore(r,{beforePublish:()=>{throw new Error('synthetic changed release');}}));
  assert.equal(existsSync(f.outputDirectory),false);
});
