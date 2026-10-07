import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DomainStore, DOMAIN_POLICY } from './domain_store.mjs';
import { DOMAIN_SCHEMA_SQL } from './domain_schema.mjs';

const now=Date.parse('2026-10-05T12:00:00.000Z');
const schema={version:1,fields:{text:{type:'string',required:true},planner:{type:'object'}},processors:{planner:['planner']},immediateDeleteSources:['legacy']};
const reason=r=>r.body.error?.code??r.body.reason;
function fixture(t,{file=false,mode='authoritative',verifier=()=>true,hook=null,fault=null}={}){
 const root=file?mkdtempSync(path.join(tmpdir(),'i-domain-adoption-synthetic-')):null,name=file?path.join(root,'synthetic.sqlite'):':memory:';
 let db=new DatabaseSync(name);db.exec("CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT);INSERT INTO core_metadata VALUES('schema_version','6'),('node_id','adoption-core'),('cursor_secret','synthetic-adoption-secret');");db.exec(DOMAIN_SCHEMA_SQL);
 const hooks={legacy:{version:'adoption-v1',authorizeOperation:()=>true,validateTransition:({next})=>next.deleted_at?!Object.hasOwn(next,'data')&&!Object.hasOwn(next,'field_meta')&&!Object.hasOwn(next,'provenance'):next.data.text.length>0,...hook}};
 const options={nodeId:'adoption-core',cursorSecret:'synthetic-adoption-secret',clock:()=>now,domainHooks:hooks,verifyLegacyAdoption:verifier,verifyAuthorization:({request,authorizationRef})=>authorizationRef==='bound:'+request.op_id,testOnlyFault:fault};
 let store=new DomainStore(db,options);store.registerDomain('legacy',schema,{mode,requiredHooksVersion:'adoption-v1'});
 const issue=(id,extra={})=>{const issued=store.configurePrincipal({principal_id:id,device_id:'phone-'+id,installation_id:'install-'+id,scopes:['legacy:adopt','legacy:read','legacy:create','legacy:patch','legacy:delete','legacy:restore','legacy:purge'],actors:id==='user'?['user_direct']:['import'],trusted_interactive:id==='user',import_sources:['legacy'],...extra});return {p:store.authenticate(issued.token),...issued};};
 const importer=issue('importer'),user=issue('user');
 const record={id:'note_synthetic_A',revision:7,deleted_at:null,origin:{principal_id:'author',device_id:'phone-author'},data:{text:'PRIVATE synthetic body only',planner:{status:'skipped',outputs:[],input_revision:7}},provenance:{source:'legacy',source_refs:['synthetic-source-ref'],import_batch_id:'batch-one'}};
 const settings={authorizationRef:'host-mapping-proof',sourceKind:'legacy',sourceRecordId:record.id,sourceRevision:record.revision,batchId:'batch-one',mappingVersion:'mapping-v1'};
 t.after(()=>{db.close();if(root)rmSync(root,{recursive:true,force:true});});
 const intent=(kind,id,base,extra={})=>{const op={domain_protocol_version:1,core_instance_id:'adoption-core',schema_version:1,op_id:randomUUID(),kind,id,base_revision:base,created_at:new Date(now).toISOString(),expires_at:new Date(now+DOMAIN_POLICY.intentTtl).toISOString(),actor:'user_direct',...extra};op.authorization_ref='bound:'+op.op_id;return op;};
 return {get db(){return db;},get s(){return store;},record,settings,importer,user,issue,intent,
  adopt:(r=record,o={},p=importer.p)=>store.adoptLegacyRecord(p,'legacy',r,{...settings,...o}),
  counts:()=>['domain_records','domain_ops','domain_receipts','domain_changes','domain_op_payloads'].map(table=>db.prepare(`SELECT COUNT(*) n FROM ${table}`).get().n),
  reopen(overrides={}){db.close();db=new DatabaseSync(name);store=new DomainStore(db,{...options,...overrides});},
 };
}

test('local adoption defaults to dry-run and preserves original non-UUID identity, revision and mapped author',t=>{
 const f=fixture(t);assert.equal(f.adopt().body.dry_run,true);assert.deepEqual(f.counts(),[0,0,0,0,0]);
 const accepted=f.adopt(f.record,{dryRun:false});assert.equal(accepted.status,201,JSON.stringify(accepted));const receipt=accepted.body.receipt;
 assert.deepEqual(receipt.targets,[{id:f.record.id,revision:7}]);const r=f.s.getRecord(f.importer.p,'legacy',f.record.id,'adoption-core').body.record;
 assert.equal(r.id,f.record.id);assert.equal(r.revision,7);assert.equal(r.origin.principal_id,'author');assert.equal(r.origin.device_id,'phone-author');assert.equal(r.field_meta.text.actor,'import');
 const before=f.counts();assert.equal(f.adopt(f.record,{dryRun:false}).body.outcome,'duplicate');assert.deepEqual(f.counts(),before);
 assert.equal(f.s.getOperation(f.importer.p,'legacy',receipt.accepted_op_id,'adoption-core').status,200);
});

test('public create and metadata injection remain unavailable for adopted identities',t=>{
 const f=fixture(t);
 const raw=f.intent('create',f.record.id,0,{data:{text:'public'},provenance:f.record.provenance});
 assert.equal(reason(f.s.submit(f.user.p,'legacy',raw)),'invalid_request');
 raw.id=randomUUID();raw.revision=7;assert.equal(reason(f.s.submit(f.user.p,'legacy',raw)),'invalid_request');
 delete raw.revision;raw.operationOrigin='local_adoption';assert.equal(reason(f.s.submit(f.user.p,'legacy',raw)),'invalid_request');
 assert.deepEqual(f.counts(),[0,0,0,0,0]);
});

test('adoption requires explicit local capability, current source grants and a synchronous host verifier',t=>{
 const f=fixture(t);const noGrant=f.issue('limited',{scopes:['legacy:create','legacy:read']});assert.equal(reason(f.adopt(f.record,{dryRun:false},noGrant.p)),'scope_forbidden');
 const noSource=f.issue('limited-source',{import_sources:[]});assert.equal(reason(f.adopt(f.record,{dryRun:false},noSource.p)),'actor_not_authorized');
 for(const [verifier,expected] of [[null,'schema_not_ready'],[()=>false,'actor_not_authorized'],[()=>Promise.resolve(true),'schema_not_ready'],[()=>({originMappingVerified:true}),'schema_not_ready'],[()=>{throw new Error('private');},'schema_not_ready']]){
  const v=fixture(t,{verifier});assert.equal(reason(v.adopt(v.record,{dryRun:false})),expected);assert.deepEqual(v.counts(),[0,0,0,0,0]);
 }
});

test('adoption callback cannot mutate the supplied identity or origin mapping',t=>{
 const f=fixture(t,{verifier:ctx=>{ctx.record.origin.principal_id='intruder';return true;}});
 assert.equal(reason(f.adopt(f.record,{dryRun:false})),'schema_not_ready');assert.equal(f.record.origin.principal_id,'author');assert.deepEqual(f.counts(),[0,0,0,0,0]);
});

test('deleted legacy records adopt only minimal permanent tombstones and cannot resurrect',t=>{
 const f=fixture(t);const tomb={...f.record,deleted_at:'2026-10-01T00:00:00.000Z'};delete tomb.data;
 assert.equal(f.adopt(tomb,{dryRun:false}).status,201);assert.deepEqual(f.counts(),[1,1,1,1,0]);
 const read=f.s.getRecord(f.importer.p,'legacy',tomb.id,'adoption-core');assert.equal(reason(read),'deleted_target');assert.equal(read.body.tombstone.revision,7);
 const stored=f.db.prepare('SELECT body_json,envelope_json FROM domain_records').get();assert.equal(stored.body_json,null);assert.equal(JSON.stringify(stored).includes('synthetic-source-ref'),false);
 const meta=f.db.prepare('SELECT op_meta_json FROM domain_ops').get().op_meta_json;assert.equal(meta.includes('PRIVATE'),false);assert.equal(meta.includes('synthetic-source-ref'),false);
 assert.equal(reason(f.adopt({...tomb,data:{text:'must not import'}},{dryRun:false})),'invalid_request');
 assert.equal(reason(f.s.submit(f.user.p,'legacy',f.intent('restore',tomb.id,7))),'restore_window_expired');
 assert.equal(reason(f.adopt(f.record,{dryRun:false})),'idempotency_conflict');
});

test('same-version conflicting content and newer source revisions never overwrite Core state',t=>{
 const f=fixture(t);assert.equal(f.adopt(f.record,{dryRun:false}).status,201);const before=f.counts();
 assert.equal(reason(f.adopt({...f.record,data:{...f.record.data,text:'different'}},{dryRun:false})),'idempotency_conflict');
 const higher={...f.record,revision:8};const result=f.adopt(higher,{dryRun:false,sourceRevision:8});assert.equal(result.body.outcome,'needs_resolution');assert.deepEqual(f.counts(),before);
 const lower={...f.record,revision:6};assert.equal(f.adopt(lower,{dryRun:false,sourceRevision:6}).body.outcome,'needs_resolution');
});

test('Core changes and confirmed user locks prevent even exact legacy re-adoption',t=>{
 const f=fixture(t);assert.equal(f.adopt(f.record,{dryRun:false}).status,201);
 const patch=f.intent('patch',f.record.id,7,{patch:{text:'user current truth'},confirm_fields:['text']});assert.equal(f.s.submit(f.user.p,'legacy',patch).status,201);
 const before=f.counts(),replay=f.adopt(f.record,{dryRun:false});assert.equal(replay.body.outcome,'needs_resolution');assert.deepEqual(f.counts(),before);
 assert.equal(f.s.getRecord(f.user.p,'legacy',f.record.id,'adoption-core').body.record.data.text,'user current truth');
});

test('adoption rolls back records, changes and receipts at every precommit fault barrier',t=>{
 for(const at of ['adoption_after_preflight','adoption_after_record','adoption_after_result','before_commit']){
  let enabled=false;const f=fixture(t,{fault:stage=>{if(enabled&&stage===at)throw new Error('synthetic fault');}});enabled=true;
  assert.throws(()=>f.adopt(f.record,{dryRun:false}),/synthetic fault/);assert.deepEqual(f.counts(),[0,0,0,0,0]);
  enabled=false;assert.equal(f.adopt(f.record,{dryRun:false}).status,201);
 }
});

test('adoption durable replay is blocked by missing hooks and narrowed credentials',t=>{
 const f=fixture(t,{file:true});const accepted=f.adopt(f.record,{dryRun:false});assert.equal(accepted.status,201);const before=f.counts();
 f.reopen({domainHooks:{}});assert.equal(reason(f.adopt(f.record,{dryRun:false})),'schema_not_ready');assert.deepEqual(f.counts(),before);
 f.reopen();assert.equal(f.adopt(f.record,{dryRun:false}).body.outcome,'duplicate');
 const narrowed=f.issue('importer',{import_sources:[]});assert.equal(reason(f.adopt(f.record,{dryRun:false},narrowed.p)),'actor_not_authorized');
 assert.equal(reason(f.s.getOperation(narrowed.p,'legacy',accepted.body.receipt.accepted_op_id,'adoption-core')),'actor_not_authorized');
});

test('off dry-run stays non-authoritative, frozen blocks apply, and shadow never emits production receipt',t=>{
 const f=fixture(t,{mode:'off'});assert.equal(f.adopt().body.outcome,'ready');assert.equal(reason(f.adopt(f.record,{dryRun:false})),'domain_off');
 f.s.setMode('legacy','shadow');const stage=f.adopt(f.record,{dryRun:false});assert.equal(stage.status,202);assert.equal(stage.body.transport_state,'shadow_staged');assert.equal(stage.body.receipt,undefined);
 assert.equal(f.adopt(f.record,{dryRun:false}).body.transport_state,'shadow_staged');assert.equal(f.db.prepare('SELECT COUNT(*) n FROM domain_receipts').get().n,0);
 f.s.setMode('legacy','frozen');const fresh={...f.record,id:'note_another'};assert.equal(reason(f.adopt(fresh,{dryRun:false,sourceRecordId:fresh.id})),'domain_frozen');
});

test('adoption never retains raw text or ordinary hashes in permanent operation metadata',t=>{
 const f=fixture(t);assert.equal(f.adopt(f.record,{dryRun:false}).status,201);
 const metadata=f.db.prepare('SELECT op_meta_json,request_digest FROM domain_ops').get();assert.equal(metadata.op_meta_json.includes(f.record.data.text),false);assert.equal(metadata.op_meta_json.includes('text_hash'),false);assert.match(metadata.request_digest,/^[a-f0-9]{64}$/);
 const deletion=f.intent('delete',f.record.id,7,{permanent:true});assert.equal(f.s.submit(f.user.p,'legacy',deletion).status,201);assert.equal(f.db.prepare('SELECT COUNT(*) n FROM domain_op_payloads').get().n,0);
 assert.equal(f.db.prepare('SELECT body_json FROM domain_records').get().body_json,null);
});


test('adoption survives a lost response after commit and returns its one durable receipt after reopen',t=>{
 let lose=false;const f=fixture(t,{file:true,fault:stage=>{if(lose&&stage==='after_commit')throw new Error('synthetic lost response');}});
 lose=true;assert.throws(()=>f.adopt(f.record,{dryRun:false}),/synthetic lost response/);lose=false;assert.deepEqual(f.counts(),[1,1,1,1,1]);
 f.reopen();const recovered=f.adopt(f.record,{dryRun:false});assert.equal(recovered.body.outcome,'duplicate');assert.deepEqual(recovered.body.receipt.targets,[{id:f.record.id,revision:7}]);assert.deepEqual(f.counts(),[1,1,1,1,1]);
});
