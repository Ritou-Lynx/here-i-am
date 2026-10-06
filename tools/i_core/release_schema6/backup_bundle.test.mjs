import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync, linkSync, renameSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createHash, randomBytes, createCipheriv } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { BACKUP_ROLES, BACKUP_LIMITS, createRuntimeBackup, verifyRuntimeBackup, verifyInitialRuntimeBackup } from './backup_bundle.mjs';
const sha=b=>createHash('sha256').update(b).digest('hex');
function fixture(t) {
 const root=mkdtempSync(path.join(tmpdir(),'runtime-backup-synthetic-')); t.after(()=>rmSync(root,{recursive:true,force:true}));
 const sources=path.join(root,'sources'); mkdirSync(sources); const release=path.join(sources,'release'); mkdirSync(release);
 const database=path.join(sources,'core.sqlite'), cursor=randomBytes(32), key=randomBytes(32);
 const db=new DatabaseSync(database); db.exec('CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);');
 const insert=db.prepare('INSERT INTO core_metadata VALUES (?,?)'); insert.run('schema_version','4'); insert.run('node_id','synthetic-node'); insert.run('cursor_secret',cursor.toString('base64url')); db.close();
 const entries=[{role:'database',name:'data/core.sqlite',source_path:database,sha256:sha(readFileSync(database))}];
 for(const [name,content] of [['manifest.json','{"synthetic":true}'],['private-launcher.ps1','synthetic launcher'],['node.exe','synthetic node bytes']]) {
   const p=path.join(release,name); writeFileSync(p,content); entries.push({role:'release',name,source_path:p,sha256:sha(Buffer.from(content))});
 }
 for(const role of BACKUP_ROLES.filter(r=>!['release','database'].includes(r))) {
  const p=path.join(sources,role+'.json'); const content=role==='recovery_custody'?JSON.stringify({format:'i-core-recovery-custody-v1',mode:'initial_schema4',node_id:'synthetic-node',database_path:database}):JSON.stringify({synthetic:true,role});
  writeFileSync(p,content); entries.push({role,name:'inputs/'+role+'.json',source_path:p,sha256:sha(Buffer.from(content))});
 }
 const spec={format:'i-core-runtime-backup-spec-v1',source_schema:4,node_id:'synthetic-node',canonical_database_path:database,old_release_root:release,old_release_manifest_sha256:entries.find(e=>e.name==='manifest.json').sha256,entries};
 const outputDirectory=path.join(root,'backup');
 return {root,sources,release,database,cursor,key,spec,outputDirectory,create:()=>createRuntimeBackup({spec,outputDirectory,key})};
}
function rejected(fn,code) { assert.throws(fn,code?e=>e.code===code:undefined); }
function syntheticArtifact(f,manifest,payload=Buffer.alloc(0)) {
 const nonce=randomBytes(12), magic=Buffer.from('ICRUNB01'), cipher=createCipheriv('aes-256-gcm',f.key,nonce); cipher.setAAD(magic);
 const body=Buffer.from(JSON.stringify(manifest)), size=Buffer.alloc(4); size.writeUInt32BE(body.length);
 const encrypted=Buffer.concat([magic,nonce,cipher.update(Buffer.concat([size,body,payload])),cipher.final(),cipher.getAuthTag()]);
 const artifactPath=path.join(f.root,'malicious.bundle'); writeFileSync(artifactPath,encrypted);
 return {artifactPath,artifactSha256:sha(encrypted),key:f.key};
}
test('complete inventory encrypts and verifies without plaintext outputs; schema4 exact database binding',t=> {
 const f=fixture(t), r=f.create(); assert.equal(r.verified,true); assert.equal(r.files,11); assert.equal(r.scope,'inventory_only'); assert.equal(r.production_completeness_not_attested,true); assert.equal(r.activation_supported,false);
 assert.equal(verifyInitialRuntimeBackup({...r,key:f.key,databasePath:f.database,nodeId:'synthetic-node'}).sourceSchema,4);
 assert.equal(readFileSync(r.artifactPath).includes(Buffer.from('synthetic launcher')),false); assert.equal(f.key.length,32);
});
test('all nine roles are required individually',t=> { const f=fixture(t); for(const role of BACKUP_ROLES) { const spec={...f.spec,entries:f.spec.entries.filter(e=>e.role!==role)}; rejected(()=>createRuntimeBackup({spec,outputDirectory:f.outputDirectory,key:f.key})); } });
test('entire release tree catches private launcher omission and same-count replacement',t=> {
 const f=fixture(t); writeFileSync(path.join(f.release,'forgotten-private.ps1'),'private'); rejected(f.create,'release_inventory_mismatch');
 rmSync(path.join(f.release,'forgotten-private.ps1')); renameSync(path.join(f.release,'private-launcher.ps1'),path.join(f.release,'different.ps1')); rejected(f.create,'release_inventory_mismatch');
});
test('every source has an external digest and distinct path',t=> {
 const f=fixture(t); f.spec.entries.find(e=>e.role==='configuration').sha256='0'.repeat(64); rejected(f.create,'external_file_hash_mismatch');
 const g=fixture(t); g.spec.entries.find(e=>e.role==='credentials').source_path=g.spec.entries.find(e=>e.role==='configuration').source_path; rejected(g.create,'duplicate_inventory_entry');
});
test('fresh output only and independent source root',t=> { const f=fixture(t); f.create(); rejected(f.create,'fresh_output_required');
 const g=fixture(t); rejected(()=>createRuntimeBackup({spec:g.spec,outputDirectory:path.join(g.sources,'backup'),key:g.key}),'independent_output_required'); });
test('all SQLite sidecars reject including zero length',t=> { for(const s of ['-wal','-shm','-journal']) { const f=fixture(t); writeFileSync(f.database+s,''); rejected(f.create,'database_sidecar_rejected'); } });
test('hardlinked source rejected',t=> { const f=fixture(t); linkSync(f.database,path.join(f.root,'hardlink')); rejected(f.create,'unsafe_path'); });
test('wrong key, corrupt ciphertext, missing anchor and truncation reject',t=> {
 const f=fixture(t),r=f.create(); rejected(()=>verifyRuntimeBackup({...r,key:randomBytes(32)})); rejected(()=>verifyRuntimeBackup({...r,artifactSha256:undefined,key:f.key}),'artifact_anchor_required');
 const bytes=readFileSync(r.artifactPath); bytes[bytes.length-1]^=1; writeFileSync(r.artifactPath,bytes); rejected(()=>verifyRuntimeBackup({...r,key:f.key}),'artifact_hash_mismatch');
 rejected(()=>verifyRuntimeBackup({...r,artifactSha256:sha(bytes),key:f.key}));
 writeFileSync(r.artifactPath,bytes.subarray(0,bytes.length-7)); rejected(()=>verifyRuntimeBackup({...r,artifactSha256:sha(bytes.subarray(0,bytes.length-7)),key:f.key}));
});
test('initial backup rejects database mutation, wrong node and schema',t=> {
 const f=fixture(t),r=f.create(); rejected(()=>verifyInitialRuntimeBackup({...r,key:f.key,databasePath:f.database,nodeId:'other'}),'initial_backup_binding_mismatch');
 const db=new DatabaseSync(f.database); db.prepare("UPDATE core_metadata SET value='other' WHERE key='node_id'").run(); db.close();
 rejected(()=>verifyInitialRuntimeBackup({...r,key:f.key,databasePath:f.database,nodeId:'synthetic-node'}),'initial_backup_database_mismatch');
});
test('cannot reuse cursor key, invalid key or lie about schema or node',t=> {
 const f=fixture(t); rejected(()=>createRuntimeBackup({spec:f.spec,outputDirectory:f.outputDirectory,key:f.cursor}),'independent_backup_key_required');
 rejected(()=>createRuntimeBackup({spec:f.spec,outputDirectory:f.outputDirectory,key:Buffer.alloc(31)}),'backup_key_required');
 f.spec.node_id='wrong'; rejected(f.create,'database_metadata_mismatch'); f.spec.node_id='synthetic-node'; f.spec.source_schema=5; rejected(f.create,'database_metadata_mismatch');
});
test('schema5 requires real recovery floor instead of initial or N/A custody',t=> {
 const f=fixture(t); const db=new DatabaseSync(f.database); db.exec("UPDATE core_metadata SET value='5' WHERE key='schema_version'"); db.close(); f.spec.source_schema=5; f.spec.entries[0].sha256=sha(readFileSync(f.database)); rejected(f.create,'activity_floor_required');
});
test('disabled roles need separate controlled evidence',t=> {
 const f=fixture(t),e=f.spec.entries.find(e=>e.role==='task'); e.state='disabled'; rejected(f.create,'disabled_component_evidence_required');
 const content=JSON.stringify({format:'i-core-runtime-component-state-v1',role:'task',enabled:false,configuration_sha256:f.spec.entries.find(e=>e.role==='configuration').sha256}); writeFileSync(e.source_path,content);e.sha256=sha(Buffer.from(content)); assert.equal(f.create().verified,true);
});
test('logical path traversal and unknown inventory fields reject',t=> { const f=fixture(t); f.spec.entries[0].name='../database'; rejected(f.create,'logical_name_invalid'); f.spec.entries[0].name='database'; f.spec.entries[0].trust_me=true; rejected(f.create,'inventory_entry_invalid'); });
test('authenticated but altered manifest entry hash rejects',t=> {
 const f=fixture(t); const entries=f.spec.entries.map(e=>({...e,bytes:readFileSync(e.source_path).length})); entries[0].sha256='0'.repeat(64);
 const m={format:'i-core-runtime-backup-v1',scope:'inventory_only',production_completeness_not_attested:true,activation_supported:false,spec:{...f.spec,entries}};
 const a=syntheticArtifact(f,m,Buffer.concat(f.spec.entries.map(e=>readFileSync(e.source_path)))); rejected(()=>verifyRuntimeBackup(a),'backup_entry_hash_mismatch');
});
test('authenticated oversized entries, traversal, trailing data and incomplete payload reject',t=> {
 for(const kind of ['oversize','traversal','trailing','short']) {
  const f=fixture(t),entries=f.spec.entries.map(e=>({...e,bytes:readFileSync(e.source_path).length}));
  if(kind==='oversize') entries[0].bytes=BACKUP_LIMITS.file+1; if(kind==='traversal') entries[0].name='../escape';
  const payload=Buffer.concat(f.spec.entries.map(e=>readFileSync(e.source_path)));
  const m={format:'i-core-runtime-backup-v1',scope:'inventory_only',production_completeness_not_attested:true,activation_supported:false,spec:{...f.spec,entries}};
  const a=syntheticArtifact(f,m,kind==='trailing'?Buffer.concat([payload,Buffer.from('x')]):kind==='short'?payload.subarray(0,payload.length-1):payload); rejected(()=>verifyRuntimeBackup(a));
 }
});

test('Windows DPAPI purpose/path-bound private key lifecycle, wrong blob and overwrite rejection',{skip:process.platform!=='win32'},async t=> {
 const {execFileSync}=await import('node:child_process'); const f=fixture(t), keyDirectory=path.join(f.root,'keys');
 const helper=path.resolve('tools/i_core/release_schema6/key_custody.ps1');
 const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
 const call=(action,dir=keyDirectory,purpose='backup')=>execFileSync(ps,['-NoProfile','-NonInteractive','-File',helper,'-Action',action,'-KeyDirectory',dir,'-Purpose',purpose],{windowsHide:true,stdio:['ignore','pipe','pipe'],maxBuffer:65536});
 assert.equal(JSON.parse(call('Create')).created,true); const key=call('Read'); assert.equal(key.length,32); assert.deepEqual(call('Read'),key);
 rejected(()=>call('Create')); rejected(()=>call('Read',keyDirectory,'recovery'));
 const blob=path.join(keyDirectory,'runtime-backup.dpapi'); assert.equal(readFileSync(blob).includes(key),false);
 const moved=path.join(f.root,'moved-keys'); renameSync(keyDirectory,moved); rejected(()=>call('Read',moved)); renameSync(moved,keyDirectory);
 writeFileSync(blob,Buffer.alloc(64));rejected(()=>call('Read'));key.fill(0);
});
test('Windows key custody rejects inherited ACL and hardlinks',{skip:process.platform!=='win32'},async t=> {
 const {execFileSync}=await import('node:child_process'); const f=fixture(t),dir=path.join(f.root,'keys'); const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe'),helper=path.resolve('tools/i_core/release_schema6/key_custody.ps1');
 const run=action=>execFileSync(ps,['-NoProfile','-NonInteractive','-File',helper,'-Action',action,'-KeyDirectory',dir,'-Purpose','recovery'],{windowsHide:true,stdio:['ignore','pipe','pipe']});
 run('Create'); const blob=path.join(dir,'runtime-recovery.dpapi'),link=path.join(f.root,'linked.dpapi'); linkSync(blob,link);rejected(()=>run('Read'));rmSync(link);
 execFileSync(path.join(process.env.SystemRoot,'System32/icacls.exe'),[blob,'/inheritance:e'],{windowsHide:true,stdio:'pipe'});rejected(()=>run('Read'));
});
test('multiple recovery custody files require explicit one context and retain every head/floor file',t=> {
 const f=fixture(t),context=f.spec.entries.find(e=>e.role==='recovery_custody'); context.custody_context=true;
 for(const name of ['current-head.json','floor-envelope.json']){const source_path=path.join(f.sources,name);writeFileSync(source_path,'{"synthetic":true}');f.spec.entries.push({role:'recovery_custody',name:'custody/'+name,source_path,sha256:sha(readFileSync(source_path))});}
 assert.equal(f.create().files,13);
 const g=fixture(t);g.spec.entries.push({...g.spec.entries.find(e=>e.role==='recovery_custody'),name:'more'});rejected(g.create);
});

test('Windows fixed release wrapper Create/Verify, environment isolation, mismatch and no-overwrite',{skip:process.platform!=='win32'},async t=> {
 const {execFileSync}=await import('node:child_process'); const {INVENTORY,PINNED_NODE_SHA256,verifyRelease}=await import('./package.mjs');
 const f=fixture(t),release=path.join(f.root,'candidate');mkdirSync(release);
 const files=[];
 for(const name of INVENTORY){const bytes=readFileSync(name==='runtime/node.exe'?process.execPath:path.resolve(name));const target=path.join(release,name);mkdirSync(path.dirname(target),{recursive:true});writeFileSync(target,bytes);files.push({path:name,bytes:bytes.length,sha256:sha(bytes)});}
 const commit='1'.repeat(40),manifest=Buffer.from(JSON.stringify({format:'i-core-schema6-preflight-candidate-v1',source_commit:commit,core_commit:commit,wrapper_commit:commit,core_schema_version:6,runtime_profile:'schema6-owned-lifecycle-v1',pinned_node_sha256:PINNED_NODE_SHA256,node_version:'v24.14.1',files}));
 writeFileSync(path.join(release,'manifest.json'),manifest);const manifestHash=sha(manifest);verifyRelease(release,manifestHash);
 const specPath=path.join(f.root,'spec.json'),specBytes=Buffer.from(JSON.stringify(f.spec));writeFileSync(specPath,specBytes);const keys=path.join(f.root,'keys');
 const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
 const wrapper=path.join(release,'tools/i_core/release_schema6/backup_bundle_schema6.ps1');
 const common=['-NoProfile','-NonInteractive','-File',wrapper,'-ReleaseDirectory',release,'-ManifestSha256',manifestHash,'-KeyDirectory',keys];
 const opts={windowsHide:true,stdio:['ignore','pipe','pipe'],env:{...process.env,NODE_OPTIONS:'--require=definitely-missing-inherited.js',HIA_BACKUP_SECRET:'synthetic-environment-marker',HTTPS_PROXY:'http://127.0.0.1:1'}};
 const createArgs=['-Operation','Create','-SpecPath',specPath,'-SpecSha256',sha(specBytes),'-OutputDirectory',f.outputDirectory,'-CreateKey'];
 const result=JSON.parse(execFileSync(ps,[...common,...createArgs],opts));assert.equal(result.verified,true);assert.equal(result.files,11);assert.equal(result.scope,'inventory_only');assert.equal(JSON.stringify(result).includes(f.root),false);assert.equal(JSON.stringify(result).includes('synthetic-environment-marker'),false);
 const artifact=path.join(f.outputDirectory,'runtime.aes256gcm');
 const verified=JSON.parse(execFileSync(ps,[...common,'-Operation','Verify','-ArtifactPath',artifact,'-ArtifactSha256',result.artifactSha256],opts));assert.equal(verified.artifactSha256,result.artifactSha256);
 rejected(()=>execFileSync(ps,[...common,...createArgs],opts));
 const badArgs=[...createArgs];badArgs[badArgs.indexOf('-SpecSha256')+1]='0'.repeat(64);badArgs[badArgs.indexOf('-OutputDirectory')+1]=path.join(f.root,'backup-wrong');badArgs.splice(badArgs.indexOf('-CreateKey'),1);
 rejected(()=>execFileSync(ps,[...common,...badArgs],opts));
 const changed=path.join(release,'tools/i_core/release_schema6/key_custody.ps1');writeFileSync(changed,'throw "must not execute"');rejected(()=>execFileSync(ps,[...common,'-Operation','Verify','-ArtifactPath',artifact,'-ArtifactSha256',result.artifactSha256],opts));
});

test('concurrent source mutation after inventory snapshot rejects without publishing artifact',async t=> {
 const {Worker}=await import('node:worker_threads');const f=fixture(t),entry=f.spec.entries.find(e=>e.name==='private-launcher.ps1');
 writeFileSync(entry.source_path,Buffer.alloc(8*1024*1024,65));entry.sha256=sha(readFileSync(entry.source_path));
 const shared=new SharedArrayBuffer(4),state=new Int32Array(shared);
 const worker=new Worker(`const {workerData}=require('node:worker_threads');const fs=require('node:fs');const state=new Int32Array(workerData.shared);Atomics.store(state,0,1);Atomics.notify(state,0);while(!fs.existsSync(workerData.output)){};fs.writeFileSync(workerData.source,Buffer.alloc(8*1024*1024,66));`,{eval:true,workerData:{shared,output:f.outputDirectory,source:entry.source_path}});
 try {while(Atomics.load(state,0)!==1) Atomics.wait(state,0,0,1000);rejected(f.create,'source_changed');assert.equal((await import('node:fs')).existsSync(path.join(f.outputDirectory,'runtime.aes256gcm')),false);}
 finally {await worker.terminate();}
});
test('compression containers and oversized manifest header are rejected without decompression',t=> {
 const f=fixture(t),artifactPath=path.join(f.root,'compressed.bundle');const zip=Buffer.from('PK\x03\x04not-an-accepted-format');writeFileSync(artifactPath,zip);rejected(()=>verifyRuntimeBackup({artifactPath,artifactSha256:sha(zip),key:f.key}));
 const magic=Buffer.from('ICRUNB01'),nonce=randomBytes(12),cipher=createCipheriv('aes-256-gcm',f.key,nonce);cipher.setAAD(magic);const length=Buffer.alloc(4);length.writeUInt32BE(BACKUP_LIMITS.manifest+1);
 const bytes=Buffer.concat([magic,nonce,cipher.update(length),cipher.final(),cipher.getAuthTag()]);writeFileSync(artifactPath,bytes);rejected(()=>verifyRuntimeBackup({artifactPath,artifactSha256:sha(bytes),key:f.key}),'manifest_size_exceeded');
});

test('entire release tree also preserves empty release files',t=> {
 const f=fixture(t),source_path=path.join(f.release,'empty.marker');writeFileSync(source_path,'');
 f.spec.entries.push({role:'release',name:'empty.marker',source_path,sha256:sha(Buffer.alloc(0))});
 const r=f.create();assert.equal(r.files,12);assert.equal(verifyRuntimeBackup({...r,key:f.key}).verified,true);
});

test('linked source directory is rejected on every platform',async t=> {
 const {symlinkSync}=await import('node:fs');const f=fixture(t),moved=path.join(f.root,'moved-sources');renameSync(f.sources,moved);symlinkSync(moved,f.sources,'junction');rejected(f.create,'linked_path_rejected');
});
