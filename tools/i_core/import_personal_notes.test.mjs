import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { DatabaseSync } from 'node:sqlite';
import { randomUUID } from 'node:crypto';
import { DomainStore } from './domain_store.mjs';
import { DOMAIN_SCHEMA_SQL } from './domain_schema.mjs';
import { createPersonalDataHooks, registerPersonalDataDomains } from './personal_data_domains.mjs';
import { importPersonalNotes, readPersonalNotes } from './import_personal_notes.mjs';

const at=Date.parse('2026-10-05T00:00:00.000Z');
function fixture(t){
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'w2-notes-synthetic-'));
  const source=path.join(root,'notes.sqlite');
  const db=new DatabaseSync(source);
  db.exec("CREATE TABLE notes(note_id TEXT PRIMARY KEY,revision INTEGER NOT NULL,text TEXT,status TEXT NOT NULL,created_at_ms INTEGER NOT NULL,updated_at_ms INTEGER NOT NULL,delivered_revision INTEGER NOT NULL,phone_card_id TEXT)");
  db.prepare('INSERT INTO notes VALUES(?,?,?,?,?,?,?,?)').run('note_synthetic01',7,'合成旧笔记','active',at,at,7,'card_synthetic');
  db.prepare('INSERT INTO notes VALUES(?,?,?,?,?,?,?,?)').run('note_synthetic02',9,'删除标记下的残留合成文不能迁入','deleted',at,at,8,null);db.close();
  const core=new DatabaseSync(':memory:');core.exec("CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT);INSERT INTO core_metadata VALUES('schema_version','6'),('node_id','core-notes-test'),('cursor_secret','synthetic-only');");core.exec(DOMAIN_SCHEMA_SQL);
  const store=new DomainStore(core,{nodeId:'core-notes-test',cursorSecret:'synthetic-only',clock:()=>at,
    domainHooks:createPersonalDataHooks({captureSourcesByPrincipal:{owner:['claude_web']},processorPrincipals:{planner:'planner'}}),
    verifyAuthorization:({authorizationRef})=>authorizationRef==='owner-action',
    verifyLegacyAdoption:({authorizationRef,record,adoption})=>authorizationRef==='import-owner-proof'&&record.origin.principal_id==='owner'&&record.origin.device_id==='device-owner'&&adoption.sourceKind==='i_remember',
  });registerPersonalDataDomains(store,{mode:'authoritative'});
  const issued=store.configurePrincipal({principal_id:'importer',device_id:'import-device',installation_id:'import-install',scopes:['captures:adopt','captures:read'],actors:['import'],import_sources:['i_remember']});
  const principal=store.authenticate(issued.token);
  const options={sourcePath:source,sourceId:'notes-copy',batchId:'batch-1',mappingVersion:'notes-v1',targetInstanceId:store.nodeId,target:store,principal,
    originMapping:()=>({principal_id:'owner',device_id:'device-owner'}),authorizationRef:'import-owner-proof'};
  t.after(()=>{core.close();assert.equal(path.dirname(root),path.resolve(os.tmpdir()));fs.rmSync(root,{recursive:true,force:true});});
  return {root,source,core,store,principal,options,mutate:(sql,args=[])=>{const d=new DatabaseSync(source);try{d.prepare(sql).run(...args);}finally{d.close();}}};
}
test('notes default dry-run reads closed source without bytes changing or target mutation',t=>{
  const f=fixture(t),before=fs.readFileSync(f.source);
  const result=importPersonalNotes(f.options);
  assert.equal(result.phase,'dry_run');assert.equal(result.totals.validated,2);
  assert.equal(f.core.prepare('SELECT COUNT(*) n FROM domain_records').get().n,0);
  assert.deepEqual(fs.readFileSync(f.source),before);
  assert.equal(readPersonalNotes(f.source)[1].text,null);
});
test('notes retain original IDs/revisions, author mapping and immediate tombstone without text',t=>{
  const f=fixture(t),result=importPersonalNotes({...f.options,dryRun:false});
  assert.equal(result.totals.accepted,2,JSON.stringify(result));
  const live=f.store.load('production','captures','note_synthetic01');
  assert.equal(live.revision,7);assert.equal(live.origin.principal_id,'owner');assert.notEqual(live.origin.principal_id,'importer');
  assert.equal(live.data.planner.status,'skipped');assert.equal(live.data.organizer,undefined);
  const deleted=f.store.load('production','captures','note_synthetic02');assert.equal(deleted.revision,9);
  assert.equal(deleted.body_state,'purged');assert.equal(deleted.data,undefined);
  for(const table of ['domain_records','domain_ops','domain_receipts','domain_op_payloads']){
    assert.ok(!JSON.stringify(f.core.prepare('SELECT * FROM '+table).all()).includes('删除标记下的残留合成文不能迁入'));
  }
  const before=f.core.prepare('SELECT COUNT(*) n FROM domain_changes').get().n;
  assert.equal(importPersonalNotes({...f.options,dryRun:false}).totals.duplicate,2);
  assert.equal(f.core.prepare('SELECT COUNT(*) n FROM domain_changes').get().n,before);
});
test('changed same revision and old/new source revisions cannot silently replace Core state',t=>{
  const f=fixture(t);importPersonalNotes({...f.options,dryRun:false});
  f.mutate('UPDATE notes SET text=? WHERE note_id=?',['同版本冲突','note_synthetic01']);
  assert.equal(importPersonalNotes({...f.options,dryRun:false}).totals.conflict,1);
  assert.equal(f.store.load('production','captures','note_synthetic01').data.text,'合成旧笔记');
  for(const revision of [6,8]){
    f.mutate('UPDATE notes SET revision=?,delivered_revision=0 WHERE note_id=?',[revision,'note_synthetic01']);
    assert.equal(importPersonalNotes({...f.options,dryRun:false}).totals.conflict,1);
  }
});
test('missing or unproved origin mapping blocks apply before any writes',t=>{
  const f=fixture(t);
  const missing=importPersonalNotes({...f.options,originMapping:{},dryRun:false});assert.equal(missing.totals.mapping_required,2);
  const wrong=importPersonalNotes({...f.options,authorizationRef:'forged',dryRun:false});assert.equal(wrong.totals.conflict,1);
  assert.equal(f.core.prepare('SELECT COUNT(*) n FROM domain_records').get().n,0);
});
test('legacy planner cannot classify migrated notes into tasks; author can delete and old replay stays scrubbed',t=>{
  const f=fixture(t);importPersonalNotes({...f.options,dryRun:false});
  const plannerToken=f.store.configurePrincipal({principal_id:'planner',device_id:'p',installation_id:'p',scopes:['captures:read','captures:ack'],actors:['agent_inferred'],processor:'planner'}).token;
  const op={domain_protocol_version:1,core_instance_id:f.store.nodeId,schema_version:1,op_id:randomUUID(),id:'note_synthetic01',base_revision:7,kind:'ack_capture',
    actor:'agent_inferred',created_at:new Date(at).toISOString(),expires_at:new Date(at+86400000).toISOString(),processor:'planner',
    disposition:{planner:{status:'done',outputs:[],input_revision:7,note:''}}};
  assert.equal(f.store.submit(f.store.authenticate(plannerToken),'captures',op).status,400);
  const ownerToken=f.store.configurePrincipal({principal_id:'owner',device_id:'device-owner',installation_id:'owner-install',scopes:['captures:read','captures:delete'],actors:['user_direct'],trusted_interactive:true,origin_device_only:true}).token;
  const deletion={...op,kind:'delete',actor:'user_direct',authorization_ref:'owner-action',op_id:randomUUID()};delete deletion.processor;delete deletion.disposition;
  const result=f.store.submit(f.store.authenticate(ownerToken),'captures',deletion);assert.equal(result.status,201,JSON.stringify(result));
  assert.equal(f.store.load('production','captures','note_synthetic01').body_state,'purged');
  assert.equal(importPersonalNotes({...f.options,dryRun:false}).totals.conflict,1);
  assert.equal(f.store.load('production','captures','note_synthetic01').data,undefined);
});
test('source sidecars, hard links and explicit mismatched target fail closed',t=>{
  const f=fixture(t);fs.writeFileSync(f.source+'-wal','synthetic');
  assert.throws(()=>readPersonalNotes(f.source),/source_must_be_closed_copy/);fs.unlinkSync(f.source+'-wal');
  const linked=path.join(f.root,'hard.sqlite');fs.linkSync(f.source,linked);
  assert.throws(()=>readPersonalNotes(linked),/unsafe_source_path/);fs.unlinkSync(linked);
  assert.throws(()=>importPersonalNotes({...f.options,targetInstanceId:'wrong-core'}),/target_instance_mismatch/);
});
test('CLI is aggregate-only default dry-run and apply cannot discover a host',t=>{
  const f=fixture(t),script=path.join(import.meta.dirname,'import_personal_notes.mjs');
  const args=[script,'--source',f.source,'--source-id','notes-copy','--batch-id','batch-1','--target-instance','synthetic-target'];
  const out=spawnSync(process.execPath,args,{encoding:'utf8'});assert.equal(out.status,2);
  assert.equal(JSON.parse(out.stdout).phase,'dry_run');assert.ok(!out.stdout.includes('合成旧笔记'));assert.ok(!out.stdout.includes('note_synthetic'));
  const apply=spawnSync(process.execPath,[...args,'--apply'],{encoding:'utf8'});assert.equal(apply.status,1);assert.match(apply.stderr,/trusted_host_adapter_required/);
});

test('legacy note edits keep planner skipped and preserve the original identity',t=>{
  const f=fixture(t);importPersonalNotes({...f.options,dryRun:false});
  const token=f.store.configurePrincipal({principal_id:'owner',device_id:'device-owner',installation_id:'owner-edit',scopes:['captures:read','captures:patch'],actors:['user_direct'],trusted_interactive:true}).token;
  const edit={domain_protocol_version:1,core_instance_id:f.store.nodeId,schema_version:1,op_id:randomUUID(),id:'note_synthetic01',base_revision:7,kind:'patch',
    actor:'user_direct',authorization_ref:'owner-action',created_at:new Date(at).toISOString(),expires_at:new Date(at+86400000).toISOString(),patch:{text:'经作者明确修订的合成笔记'}};
  assert.equal(f.store.submit(f.store.authenticate(token),'captures',edit).status,201);
  const record=f.store.load('production','captures','note_synthetic01');
  assert.equal(record.id,'note_synthetic01');assert.equal(record.data.planner.status,'skipped');
  assert.equal(record.data.planner.outputs.length,0);
});
test('shadow import reports staged and never creates production acceptance receipt',t=>{
  const f=fixture(t);f.store.setMode('captures','shadow');
  const result=importPersonalNotes({...f.options,dryRun:false});
  assert.equal(result.totals.shadow_staged,2);
  assert.equal(result.totals.accepted,0);
  assert.ok(result.mappings.every(m=>!m.receipt));
  assert.equal(f.core.prepare('SELECT COUNT(*) n FROM domain_receipts').get().n,0);
  assert.equal(f.core.prepare("SELECT COUNT(*) n FROM domain_records WHERE namespace='production'").get().n,0);
});
