import assert from 'node:assert/strict';
import { createHash, randomBytes } from 'node:crypto';
import { copyFileSync, existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { ICoreStore } from './i_core_store.mjs';
import { DomainStore } from './domain_store.mjs';
import { activityRecoveryManifestForDatabase } from './activity_control_plane.mjs';
import { validateDomainMigrationCopy } from './domain_migrate.mjs';
const NOW=1800000000000;
const digest=(bytes)=>createHash('sha256').update(bytes).digest('hex');
function fixture(t) {
 const root=mkdtempSync(path.join(tmpdir(),'domain-copy-synthetic-'));
 t.after(()=>{assert.equal(path.dirname(path.resolve(root)),path.resolve(tmpdir()));assert.ok(path.basename(root).startsWith('domain-copy-synthetic-'));rmSync(root,{recursive:true,force:true});});
 const original=path.join(root,'synthetic-origin.sqlite');
 const store=new ICoreStore(original,{clock:()=>NOW});
 store.db.exec("CREATE TABLE synthetic_legacy(id INTEGER PRIMARY KEY,body TEXT);INSERT INTO synthetic_legacy VALUES(1,'synthetic preserved private body')");
 const floor=activityRecoveryManifestForDatabase(store.db,{nodeId:store.nodeId,cursorSecret:store.cursorSecret});
 const binding=store.db.prepare("SELECT value FROM activity_metadata WHERE key='database_binding_digest'").get().value;
 store.close();
 const normalized=new DatabaseSync(original);normalized.exec('PRAGMA wal_checkpoint(TRUNCATE);PRAGMA journal_mode=DELETE');normalized.close();
 const candidate=path.join(root,'specified-copy.sqlite');copyFileSync(original,candidate);
 const sourceBytes=readFileSync(candidate);
 const descriptor={artifact_sha256:digest(sourceBytes),source_database_binding_digest:binding,activity_recovery_floor:floor,
  copy_consistency:{method:'offline_closed_sqlite',all_core_writers_stopped:true,sqlite_sidecars_absent:true}};
 const options={clock:()=>NOW,scratchRoot:path.join(root,'scratch'),backupDirectory:path.join(root,'backups'),backupKey:randomBytes(32),
  ownerAuthorization:({action,candidatePath})=>({action,candidatePath,authorized:true,checkedAt:NOW,trustedCopyDescriptor:descriptor})};
 return {root,candidate,sourceBytes,descriptor,options};
}
function assertUnchanged(f){assert.deepEqual(readFileSync(f.candidate),f.sourceBytes);if(existsSync(f.options.scratchRoot))assert.deepEqual(readdirSync(f.options.scratchRoot),[]);}

test('R01 synthetic copy validates schema6 and backup while input stays unchanged and scratch cannot activate',t=>{
 const f=fixture(t);let probed=0;
 const result=validateDomainMigrationCopy(f.candidate,{...f.options,testOnly:true,testOnlyHook:(phase,{scratchPath})=>{
  if(!['copy_marked_read_only','copy_validated'].includes(phase))return;
  assert.throws(()=>new ICoreStore(scratchPath),{code:'backup_activation_unsupported'});
  const db=new DatabaseSync(scratchPath,{readOnly:true});
  try{
   assert.equal(db.prepare("SELECT value FROM activity_metadata WHERE key='database_binding_digest'").get().value,f.descriptor.source_database_binding_digest);
   assert.equal(db.prepare("SELECT value FROM core_metadata WHERE key='domain_backup_role'").get().value,'backup_read_only');
   if(phase==='copy_validated')assert.throws(()=>new DomainStore(db,{nodeId:db.prepare("SELECT value FROM core_metadata WHERE key='node_id'").get().value,cursorSecret:db.prepare("SELECT value FROM core_metadata WHERE key='cursor_secret'").get().value}),{code:'backup_activation_unsupported'});
  }finally{db.close();}
  probed++;
 }});
 assert.equal(probed,2);assert.equal(result.validated_schema_version,6);assert.equal(result.backup.verified,true);
 assert.equal(result.activation_supported,false);assert.equal(result.scratch_removed,true);
 assert.equal(result.domain_table_count,12);
 assert.equal(JSON.stringify(result).includes(f.root),false);
 assert.equal(JSON.stringify(result).includes('synthetic preserved private body'),false);
 assert.equal(readdirSync(f.options.backupDirectory).filter(name=>name.endsWith('.aes256gcm')).length,1);
 assertUnchanged(f);
});

test('R01 missing auth, untrusted consistency, wrong hash/binding/floor fail closed with unchanged input',t=>{
 const f=fixture(t);
 assert.throws(()=>validateDomainMigrationCopy(f.candidate,{...f.options,ownerAuthorization:undefined}),{code:'copy_validation_authorization_required'});
 assert.throws(()=>validateDomainMigrationCopy(path.join(f.root,'synthetic-origin.sqlite'),f.options),{code:'copy_must_be_distinct_from_live_path'});
 for(const [mutate,code] of [
  [d=>{d.artifact_sha256='a'.repeat(64);},'copy_artifact_changed'],
  [d=>{d.source_database_binding_digest='b'.repeat(64);},'copy_source_binding_mismatch'],
  [d=>{d.activity_recovery_floor={};},'recovery_lineage_unverified'],
  [d=>{d.copy_consistency.all_core_writers_stopped=false;},'copy_descriptor_unverified'],
 ]){
  const descriptor=structuredClone(f.descriptor);mutate(descriptor);
  assert.throws(()=>validateDomainMigrationCopy(f.candidate,{...f.options,ownerAuthorization:({action,candidatePath})=>({action,candidatePath,authorized:true,checkedAt:NOW,trustedCopyDescriptor:descriptor})}),{code});
  assertUnchanged(f);
 }
});

test('R01 already-marked backup input is refused, never treated as a live source',t=>{
 const f=fixture(t);
 const db=new DatabaseSync(f.candidate);db.prepare("UPDATE activity_metadata SET value='backup_read_only' WHERE key='database_role'").run();db.close();
 f.sourceBytes=readFileSync(f.candidate);f.descriptor.artifact_sha256=digest(f.sourceBytes);
 assert.throws(()=>validateDomainMigrationCopy(f.candidate,f.options),{code:'backup_activation_unsupported'});
 assertUnchanged(f);
});

test('R01 DDL interruption retains verified encrypted backup, removes scratch, and never changes candidate',t=>{
 const f=fixture(t);
 assert.throws(()=>validateDomainMigrationCopy(f.candidate,{...f.options,testOnly:true,testOnlyHook:(phase)=>{
  if(phase==='after_copy_ddl')throw new Error('synthetic private failure body');
 }}),{code:'copy_validation_failed'});
 assertUnchanged(f);
 assert.equal(readdirSync(f.options.backupDirectory).filter(name=>name.endsWith('.aes256gcm')).length,1);
});

test('R01 changed artifact or withdrawn authorization during rehearsal cannot produce success',t=>{
 const f=fixture(t);
 assert.throws(()=>validateDomainMigrationCopy(f.candidate,{...f.options,ownerAuthorization:({action,candidatePath,phase})=>({action,candidatePath,
  authorized:phase!=='before_commit',checkedAt:NOW,trustedCopyDescriptor:f.descriptor})}),{code:'copy_validation_authorization_required'});
 assertUnchanged(f);
 const altered=fixture(t);
 assert.throws(()=>validateDomainMigrationCopy(altered.candidate,{...altered.options,testOnly:true,testOnlyHook:(phase)=>{
  if(phase==='copy_marked_read_only')writeFileSync(altered.candidate,Buffer.from('synthetic changed bytes'));
 }}),{code:'copy_artifact_changed'});
 assert.deepEqual(readdirSync(altered.options.scratchRoot),[]);
});
