import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, writeFileSync, readFileSync, rmSync, linkSync, renameSync } from 'node:fs';
import { syntheticRoot, syntheticFixedNode } from '../test_fixtures/release_schema6/synthetic_paths.mjs';
import path from 'node:path';
import { createHash, randomBytes, createCipheriv } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { BACKUP_ROLES, BACKUP_LIMITS, createRuntimeBackup, verifyRuntimeBackup, verifyInitialRuntimeBackup } from './backup_bundle.mjs';
const sha=b=>createHash('sha256').update(b).digest('hex');
function fixture(t) {
 const root=syntheticRoot('runtime-backup-synthetic-'); t.after(()=>rmSync(root,{recursive:true,force:true}));
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
 const {execFileSync}=await import('node:child_process'); const {INVENTORY,cleanEnvironment,prepareRelease,verifyRelease}=await import('./package.mjs');
 const f=fixture(t),release=path.join(f.root,'candidate'),sourceRepository=path.join(f.root,'synthetic-git');mkdirSync(sourceRepository);
 const gitExecPath=execFileSync('git',['--exec-path'],{encoding:'utf8',windowsHide:true}).trim();
 const gitPath=path.resolve(gitExecPath,'../../../bin/git.exe');
 const runGit=args=>execFileSync(gitPath,args,{encoding:'utf8',windowsHide:true,env:cleanEnvironment()}).trim();
 runGit(['init','-q',sourceRepository]);
 for(const name of INVENTORY.filter(name=>name!=='runtime/node.exe')) {
  const target=path.join(sourceRepository,name);mkdirSync(path.dirname(target),{recursive:true});writeFileSync(target,readFileSync(path.resolve(name)));
 }
 runGit(['-C',sourceRepository,'-c','core.autocrlf=false','add','.']);
 runGit(['-C',sourceRepository,'-c','user.name=Synthetic','-c','user.email=synthetic@example.invalid','-c','commit.gpgsign=false','-c','core.hooksPath='+path.join(f.root,'no-hooks'),'commit','-qm','synthetic full runtime sources']);
 const sourceCommit=runGit(['-C',sourceRepository,'rev-parse','HEAD']);
 const packaged=prepareRelease({repository:sourceRepository,output:release,nodePath:syntheticFixedNode(f.root),gitPath,sourceCommit});
 const manifestHash=packaged.manifest_sha256;assert.equal(packaged.source_commit,sourceCommit);assert.equal(verifyRelease(release,manifestHash).source_commit,sourceCommit);
 const specPath=path.join(f.root,'spec.json'),specBytes=Buffer.from(JSON.stringify(f.spec));writeFileSync(specPath,specBytes);const keys=path.join(f.root,'keys');
 const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
 const wrapper=path.join(release,'tools/i_core/release_schema6/backup_bundle_schema6.ps1');
 const common=['-NoProfile','-NonInteractive','-File',wrapper,'-ReleaseDirectory',release,'-ManifestSha256',manifestHash,'-KeyDirectory',keys];
 const opts={windowsHide:true,stdio:['ignore','pipe','pipe'],env:{...process.env,NODE_OPTIONS:'--require=definitely-missing-inherited.js',HIA_BACKUP_SECRET:'synthetic-environment-marker',HTTPS_PROXY:'http://127.0.0.1:1'}};
 const createArgs=['-Operation','Create','-SpecPath',specPath,'-SpecSha256',sha(specBytes),'-OutputDirectory',f.outputDirectory,'-CreateKey'];
 const result=JSON.parse(execFileSync(ps,[...common,...createArgs],opts));assert.equal(result.verified,true);assert.equal(result.files,11);assert.equal(result.scope,'inventory_only');assert.equal(JSON.stringify(result).includes(f.root),false);assert.equal(JSON.stringify(result).includes('synthetic-environment-marker'),false);
 const artifact=path.join(f.outputDirectory,'runtime.aes256gcm');
 const verified=JSON.parse(execFileSync(ps,[...common,'-Operation','Verify','-ArtifactPath',artifact,'-ArtifactSha256',result.artifactSha256],opts));assert.equal(verified.artifactSha256,result.artifactSha256);
 const restoreArgs=['-Operation','RestoreInspection','-ArtifactPath',artifact,'-ArtifactSha256',result.artifactSha256,'-OutputDirectory',path.join(f.root,'restored-inspection'),'-ExpectedDatabaseFingerprintSha256',result.databaseInspection.dataSha256];
 const restored=JSON.parse(execFileSync(ps,[...common,...restoreArgs],opts));
 assert.equal(restored.restored,true);assert.equal(restored.inspectionOnly,true);assert.equal(restored.coreHealth.mode,'inspection_read_only');assert.equal(restored.databaseBytesUnchanged,true);assert.equal(restored.sidecarsAbsent,true);
 assert.equal(restored.databaseInspection.dataSha256,result.databaseInspection.dataSha256);assert.equal(restored.deniedRoutes.length,5);assert.equal(JSON.stringify(restored).includes(f.root),false);
 rejected(()=>execFileSync(ps,[...common,...restoreArgs],opts));
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

test('Windows PS5.1 production backup child preserves binary frames across console encodings and failed start',{skip:process.platform!=='win32'},async t=> {
 const {execFileSync}=await import('node:child_process');
 const root=syntheticRoot('backup-binary-frame-');t.after(()=>rmSync(root,{recursive:true,force:true}));
 const receiver=path.join(root,'receiver.mjs'),probe=path.join(root,'probe.ps1');
 writeFileSync(receiver,`import {createHash} from 'node:crypto';const chunks=[];for await(const c of process.stdin)chunks.push(c);const b=Buffer.concat(chunks);process.stdout.write(JSON.stringify({bytes:b.length,sha256:createHash('sha256').update(b).digest('hex'),portableHeader:b.subarray(32,36).toString('ascii')==='IPW1',portableLength:b.length>=40&&b.readUInt32BE(36)===48,keyPayload:b.subarray(32).toString('utf8')==='{"synthetic":true}',portablePayload:b.subarray(88).toString('utf8')==='{"synthetic":true}'}));`);
 writeFileSync(probe,String.raw`param([string]$Source,[string]$Node,[string]$Receiver,[string]$MissingNode)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1){throw 'ps51_required'}
$tokens=$null;$issues=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($Source,[ref]$tokens,[ref]$issues)
if($issues.Count){throw 'source_parse_failed'}
$functions=@($ast.FindAll({param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -in @('Quote-Argument','Start-BackupChild')},$true))
if($functions.Count -ne 2){throw 'helper_selection_failed'}
foreach($f in $functions){. ([scriptblock]::Create($f.Extent.Text))}
$before=@{};foreach($name in @('SYSTEMROOT','WINDIR','TEMP','TMP','COMSPEC')){$before[$name]=[Environment]::GetEnvironmentVariable($name)}
$original=[Console]::InputEncoding;$key=New-Object byte[] 32;$password=New-Object byte[] 48;$frame=New-Object byte[] 88
$rng=[Security.Cryptography.RandomNumberGenerator]::Create();try{$rng.GetBytes($key);$rng.GetBytes($password)}finally{$rng.Dispose()}
[Array]::Copy($key,0,$frame,0,32);[Array]::Copy([Text.Encoding]::ASCII.GetBytes('IPW1'),0,$frame,32,4);[Array]::Copy([byte[]]@(0,0,0,48),0,$frame,36,4);[Array]::Copy($password,0,$frame,40,48)
$payload=[Text.Encoding]::UTF8.GetBytes('{"synthetic":true}');$rows=@();$failures=@()
try {
 foreach($case in @(@{name='default';encoding=$original},@{name='utf8_bom';encoding=[Text.UTF8Encoding]::new($true)},@{name='utf16_bom';encoding=[Text.UnicodeEncoding]::new($false,$true)})) {
  [Console]::InputEncoding=$case.encoding
  foreach($kind in @('key','portable')) {
   $secret=if($kind -eq 'key'){$key}else{$frame};$expected=New-Object byte[] ($secret.Length+$payload.Length)
   [Array]::Copy($secret,0,$expected,0,$secret.Length);[Array]::Copy($payload,0,$expected,$secret.Length,$payload.Length)
   $sha=[Security.Cryptography.SHA256]::Create();try{$expectedHash=([BitConverter]::ToString($sha.ComputeHash($expected))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose();[Array]::Clear($expected,0,$expected.Length)}
   $received=Start-BackupChild $Node @($Receiver) $secret $payload
   $rows+=@{encoding=$case.name;kind=$kind;bytes=$received.bytes;expectedBytes=$secret.Length+$payload.Length;exactBytes=($received.sha256 -eq $expectedHash);headerMatches=($kind -eq 'key' -or ($received.portableHeader -and $received.portableLength));payloadMatches=$(if($kind -eq 'key'){$received.keyPayload}else{$received.portablePayload});encodingRestored=([Console]::InputEncoding.CodePage -eq $case.encoding.CodePage -and [Console]::InputEncoding.GetPreamble().Length -eq $case.encoding.GetPreamble().Length)}
  }
  $rejected=$false;try{Start-BackupChild $MissingNode @($Receiver) $key $payload|Out-Null}catch{$rejected=$true}
  $failures+=@{encoding=$case.name;startRejected=$rejected;encodingRestored=([Console]::InputEncoding.CodePage -eq $case.encoding.CodePage -and [Console]::InputEncoding.GetPreamble().Length -eq $case.encoding.GetPreamble().Length)}
 }
 [pscustomobject]@{rows=$rows;failures=$failures}|ConvertTo-Json -Depth 4 -Compress
}finally{[Console]::InputEncoding=$original;foreach($bytes in @($key,$password,$frame,$payload)){[Array]::Clear($bytes,0,$bytes.Length)}}
`);
 const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
 const report=JSON.parse(execFileSync(ps,['-NoProfile','-NonInteractive','-File',probe,'-Source',path.resolve('tools/i_core/release_schema6/backup_bundle_schema6.ps1'),'-Node',syntheticFixedNode(root),'-Receiver',receiver,'-MissingNode',path.join(root,'never-created.exe')],{windowsHide:true,encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:60000,maxBuffer:65536}));
 assert.equal(report.rows.length,6);assert.equal(report.failures.length,3);
 for(const row of report.rows){assert.equal(row.bytes,row.expectedBytes,`${row.encoding}/${row.kind}`);assert.equal(row.exactBytes,true);assert.equal(row.headerMatches,true);assert.equal(row.payloadMatches,true);assert.equal(row.encodingRestored,true);}
 for(const failure of report.failures){assert.equal(failure.startRejected,true);assert.equal(failure.encodingRestored,true);}
});
