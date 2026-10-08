import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, writeFileSync, readFileSync, realpathSync, rmSync, rmdirSync, unlinkSync, linkSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { prepareCustodyBackupInventory, assertUnchanged } from '../maintenance/prepare-custody-backup-inventory.mjs';
import { backupFilePrimitives as f, BACKUP_ROLES } from './backup_bundle.mjs';
import { cleanEnvironment } from './package.mjs';
const cli=fileURLToPath(new URL('../maintenance/prepare-custody-backup-inventory.mjs',import.meta.url));
const hash=b=>createHash('sha256').update(b).digest('hex'), H='a'.repeat(64), secret='SYNTHETIC_SECRET_MUST_NOT_APPEAR';
function fixture(t){
 const parent=realpathSync.native(tmpdir()),root=realpathSync.native(mkdtempSync(path.join(parent,'schema6-custody-inventory-')));
 f.protect(root);
 t.after(()=>{assert.equal(path.dirname(root),parent);assert.ok(path.basename(root).startsWith('schema6-custody-inventory-'));f.safe(root,true);rmSync(root,{recursive:true,force:true});});
 const custody=path.join(root,'custody'),release=path.join(root,'release');mkdirSync(custody,{mode:0o700});f.protect(custody);mkdirSync(release,{mode:0o700});
 const database=path.join(root,'database.sqlite'),node='synthetic-node';
 const put=(filename,value)=>{const bytes=typeof value==='string'?value:JSON.stringify(value)+'\n';writeFileSync(filename,bytes,{mode:0o600});return hash(bytes);};
 const record=(kind,body)=>{const bytes=JSON.stringify({...body,authentication:H})+'\n',digest=hash(bytes);put(path.join(custody,digest+'.'+kind+'.json'),bytes);return digest;};
 const common={databasePath:database,nodeId:node};
 const recovery=record('recovery',{format:'i-core-recovery-event-v1',...common,kind:'automatic_crash_recovery',previousHeadSha256:null,rawManifestSha256:H});
 const floor1=record('floor',{format:'i-core-floor-custody-v1',...common,schemaVersion:6,databaseSha256:H,cleanCloseReceiptId:'r1',recoveryEventSha256:recovery});
 const head1=record('head',{format:'i-core-custody-head-v1',...common,generation:1,previousHeadSha256:null,custodySha256:floor1,receiptId:'r1'});
 const floor2=record('floor',{format:'i-core-floor-custody-v1',...common,schemaVersion:6,databaseSha256:H,cleanCloseReceiptId:'r2'});
 const head2=record('head',{format:'i-core-custody-head-v1',...common,generation:2,previousHeadSha256:head1,custodySha256:floor2,receiptId:'r2'});
 const switched=record('package-switch',{format:'i-core-package-switch-event-v1',...common,planSha256:H,databaseSha256:H,previousHeadSha256:head2,sourceMarker:{node_id:node,custody_sha256:floor2},from:{manifestSha256:H,configurationSha256:H},to:{manifestSha256:'b'.repeat(64),configurationSha256:H},rollbackOf:null});
 const floor3=record('floor',{format:'i-core-floor-custody-v1',...common,schemaVersion:6,databaseSha256:H,cleanCloseReceiptId:'r3',packageSwitchEventSha256:switched});
 const head3=record('head',{format:'i-core-custody-head-v1',...common,generation:3,previousHeadSha256:head2,custodySha256:floor3,receiptId:'r3'});
 const headPath=path.join(custody,'current-head.json');put(headPath,readFileSync(path.join(custody,head3+'.head.json'),'utf8'));
 const contextPath=path.join(root,'inspection-context.json');
 const contextHash=put(contextPath,{format:'i-core-recovery-custody-v1',mode:'activity_floor',node_id:node,database_path:database,activity_recovery_floor:{synthetic:secret}});
 const entries=BACKUP_ROLES.filter(r=>r!=='recovery_custody').map(role=>{
  const source=role==='database'?database:role==='release'?path.join(release,'manifest.json'):path.join(root,role+'.json');
  return {role,name:role==='release'?'manifest.json':role+'.json',source_path:source,sha256:put(source,secret+'-'+role)};
 });
 entries.push({role:'recovery_custody',name:'inspection/context.json',source_path:contextPath,sha256:contextHash,custody_context:true},
  {role:'recovery_custody',name:'custody/current-head.json',source_path:headPath,sha256:head1},
  {role:'recovery_custody',name:'custody/'+floor1+'.floor.json',source_path:path.join(custody,floor1+'.floor.json'),sha256:floor1});
 const spec={format:'i-core-runtime-backup-spec-v1',source_schema:6,node_id:node,canonical_database_path:database,old_release_root:release,old_release_manifest_sha256:entries.find(e=>e.role==='release').sha256,entries};
 const options={specTemplate:spec,custodyDirectory:custody,expectedHeadSha256:head3};
 return {root,custody,common,put,record,spec,options,headPath,head1,head2,head3,floor1,floor2,floor3,recovery,switched,contextPath};
}

test('manual inventory preserves all roles/context, refreshes stale head anchor and includes complete switch history',{timeout:120000},t=>{
 const x=fixture(t),before=JSON.stringify(x.spec),result=prepareCustodyBackupInventory(x.options);
 assert.equal(JSON.stringify(x.spec),before,'input spec must not be mutated');
 assert.equal(result.prepared,true);for(const field of ['approved','deploymentReady','authorityVerified','macAuthenticated','crossComponentAtomic','externalReferenceContentsVerified'])assert.equal(result[field],false,field);
 assert.equal(result.scope,'manual_inventory_preparation_only');f.validate(result.spec);
 assert.equal(result.sourceVector.files.length,9);
 assert.ok(result.spec.entries.some(e=>e.source_path.endsWith(x.switched+'.package-switch.json')));
 assert.deepEqual(result.spec.entries.filter(e=>path.dirname(e.source_path)!==x.custody),x.spec.entries.filter(e=>path.dirname(e.source_path)!==x.custody));
 assert.equal(result.spec.entries.find(e=>e.source_path===x.headPath).sha256,x.head3);
 assert.equal(JSON.stringify(result).includes(secret),false,'output contains metadata, never context or credential content');
 assert.equal(assertUnchanged(result.sourceVector).unchanged,true);
 x.put(path.join(x.custody,'custody.lock'),secret);assert.equal(assertUnchanged(result.sourceVector).unchanged,true);
 x.put(path.join(x.custody,'custody.lock'),'different');assert.equal(assertUnchanged(result.sourceVector).unchanged,true);
 unlinkSync(path.join(x.custody,'custody.lock'));assert.equal(assertUnchanged(result.sourceVector).unchanged,true);
});

test('pending, unknown names, subdirectories, missing references, corrupt hashes and hard links are rejected',{timeout:120000},t=>{
 const x=fixture(t);
 for(const name of ['package-switch-pending.json','current-head-random.pending','unexpected.json']){
  const file=path.join(x.custody,name);x.put(file,secret);assert.throws(()=>prepareCustodyBackupInventory(x.options),/custody_inventory_unknown_entry/);unlinkSync(file);
 }
 const directory=path.join(x.custody,'nested');mkdirSync(directory);assert.throws(()=>prepareCustodyBackupInventory(x.options),/custody_inventory_unknown_entry/);rmdirSync(directory);
 const file=path.join(x.custody,x.floor1+'.floor.json'),bytes=readFileSync(file);unlinkSync(file);
 assert.throws(()=>prepareCustodyBackupInventory(x.options),/custody_inventory_reference_missing/);writeFileSync(file,bytes,{mode:0o600});
 x.put(file,'{"corrupt":true}');assert.throws(()=>prepareCustodyBackupInventory(x.options),/custody_inventory_filename_hash_mismatch/);writeFileSync(file,bytes);
 const alias=path.join(x.root,'hardlink');linkSync(file,alias);assert.throws(()=>prepareCustodyBackupInventory(x.options));unlinkSync(alias);
});

test('capture before/after vector rejects head rollback, appended history and changed inspection context',{timeout:120000},t=>{
 const x=fixture(t),{sourceVector}=prepareCustodyBackupInventory(x.options),head=readFileSync(x.headPath);
 writeFileSync(x.headPath,readFileSync(path.join(x.custody,x.head2+'.head.json')));
 assert.throws(()=>assertUnchanged(sourceVector),/custody_inventory_head_anchor_mismatch/);writeFileSync(x.headPath,head);
 const afterHead=prepareCustodyBackupInventory(x.options).sourceVector;
 const added=x.record('recovery',{format:'i-core-recovery-event-v1',...x.common,kind:'automatic_crash_recovery',previousHeadSha256:x.head3,rawManifestSha256:H});
 assert.throws(()=>assertUnchanged(afterHead),/custody_inventory_source_changed/);unlinkSync(path.join(x.custody,added+'.recovery.json'));
 const afterAddition=prepareCustodyBackupInventory(x.options).sourceVector;
 const context=readFileSync(x.contextPath);writeFileSync(x.contextPath,Buffer.concat([context,Buffer.from(' ')]));
 assert.throws(()=>assertUnchanged(afterAddition),/custody_inventory_source_changed/);
});

test('explicit head, unique anchored scope, context hash and same DB/node bindings are required',{timeout:120000},t=>{
 const x=fixture(t);
 assert.throws(()=>prepareCustodyBackupInventory({...x.options,expectedHeadSha256:x.head1}),/custody_inventory_head_anchor_mismatch/);
 const clone=()=>JSON.parse(JSON.stringify(x.spec));let s=clone();s.node_id='other-node';assert.throws(()=>prepareCustodyBackupInventory({...x.options,specTemplate:s}),/custody_inventory_binding_mismatch/);
 s=clone();s.entries=s.entries.filter(e=>e.source_path!==x.headPath);assert.throws(()=>prepareCustodyBackupInventory({...x.options,specTemplate:s}),/custody_inventory_unique_head_anchor_required/);
 s=clone();s.entries.find(e=>e.custody_context).sha256=H;assert.throws(()=>prepareCustodyBackupInventory({...x.options,specTemplate:s}),/custody_inventory_context_hash_mismatch/);
});

test('CLI writes one fresh preparation, pins its exact digest for checking and leaks no metadata contents',{timeout:120000},t=>{
 const x=fixture(t),specPath=path.join(x.root,'spec.json'),output=path.join(x.root,'prepared.json');x.put(specPath,x.spec);
 const run=args=>spawnSync(process.execPath,[cli,...args],{encoding:'utf8',env:cleanEnvironment(),windowsHide:true,timeout:60000});
 const args=['prepare','--spec',specPath,'--custody-directory',x.custody,'--expected-head-sha256',x.head3,'--output',output];
 const prepared=run(args);assert.equal(prepared.status,0,prepared.stdout+prepared.stderr);
 const report=JSON.parse(prepared.stdout),bytes=readFileSync(output);assert.equal(report.preparedSha256,hash(bytes));
 assert.equal(prepared.stdout.includes(secret),false);assert.equal(bytes.includes(Buffer.from(secret)),false);
 assert.equal(run(args).status,2,'existing output must never be replaced');assert.deepEqual(readFileSync(output),bytes);
 const check=['check','--prepared',output,'--prepared-sha256',report.preparedSha256];
 assert.equal(run(check).status,0);
 writeFileSync(output,Buffer.concat([bytes,Buffer.from(' ')]));const stale=run(check);assert.equal(stale.status,2);assert.equal(stale.stdout.includes(secret),false);
 const unpinned=run(['check','--prepared',output]);assert.equal(unpinned.status,2);
 assert.equal(existsSync(path.join(x.custody,'custody.lock')),false,'preparation never creates or acquires an authority lock');
});
// ACL rejection is independent of content hashes and uses only an owned synthetic directory.
test('non-private custody ACL is rejected without modifying or reading credential contents',{skip:process.platform!=='win32',timeout:60000},t=>{
 const x=fixture(t),ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
 const command="$ErrorActionPreference='Stop'; $p=[Console]::In.ReadToEnd(); $acl=[IO.Directory]::GetAccessControl($p,[Security.AccessControl.AccessControlSections]::Access); $who=[Security.Principal.SecurityIdentifier]::new('S-1-1-0'); $rule=[Security.AccessControl.FileSystemAccessRule]::new($who,'Read','ContainerInherit,ObjectInherit','None','Allow'); $acl.AddAccessRule($rule); [IO.Directory]::SetAccessControl($p,$acl)";
 execFileSync(ps,['-NoProfile','-NonInteractive','-Command',command],{input:x.custody,env:cleanEnvironment(),windowsHide:true,stdio:['pipe','pipe','pipe']});
 assert.throws(()=>prepareCustodyBackupInventory(x.options),/custody_inventory_acl_rejected/);
});


test('preserves unpublished archived heads and legal 1-4 MiB floors without relaxing inspection context limits',{timeout:120000},t=>{
 const x=fixture(t);
 const largeFloor=x.record('floor',{format:'i-core-floor-custody-v1',...x.common,schemaVersion:6,databaseSha256:H,cleanCloseReceiptId:'r4',progressWitness:{syntheticPadding:'x'.repeat(1024*1024+64)}});
 const unpublished=x.record('head',{format:'i-core-custody-head-v1',...x.common,generation:4,previousHeadSha256:x.head3,custodySha256:largeFloor,receiptId:'r4'});
 const result=prepareCustodyBackupInventory(x.options);
 assert.equal(result.sourceVector.unanchoredHeadCount,1);
 assert.ok(result.spec.entries.some(e=>e.source_path.endsWith(unpublished+'.head.json')));
 assert.ok(result.spec.entries.some(e=>e.source_path.endsWith(largeFloor+'.floor.json')));
 assert.equal(result.sourceVector.expectedHeadSha256,x.head3);
 assert.equal(result.authorityVerified,false);
 assert.equal(assertUnchanged(result.sourceVector).unchanged,true);
 const oversized=x.record('floor',{format:'i-core-floor-custody-v1',...x.common,schemaVersion:6,databaseSha256:H,cleanCloseReceiptId:'oversized',progressWitness:{syntheticPadding:'x'.repeat(4*1024*1024)}});
 assert.throws(()=>prepareCustodyBackupInventory(x.options),/input_size_exceeded/);
 unlinkSync(path.join(x.custody,oversized+'.floor.json'));
 x.put(x.contextPath,{format:'i-core-recovery-custody-v1',mode:'activity_floor',node_id:x.common.nodeId,database_path:x.common.databasePath,activity_recovery_floor:{syntheticPadding:'x'.repeat(1024*1024)}});
 assert.throws(()=>prepareCustodyBackupInventory(x.options),/input_size_exceeded/);
});
