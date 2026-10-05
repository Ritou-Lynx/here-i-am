import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {createICoreServer} from './i_core_server.mjs';
import {ICoreStore} from './i_core_store.mjs';
import {DOMAIN_SCHEMA_SQL,assertDomainSchemaReady} from './domain_schema.mjs';
import {createPersonalDataHooks,registerPersonalDataDomains} from './personal_data_domains.mjs';

const now='2026-10-05T12:00:00.000Z';
const item=()=>({title:'真实宿主合成事项',level:'行动',area:'生活',parent_id:null,depends_on:[],status:'待办',replaced_by:null,
 block_kind:null,blocks:null,scheduled_at:null,planned_date:null,due_date:null,completed_at:null,energy:null,defer_count:0,
 source:'手打',source_url:null,note:'',remind_at:null});

test('real Core host forwards explicit business hooks and local adoption proof; restart fails closed only for configured domains',async t=>{
 const directory=mkdtempSync(path.join(tmpdir(),'w2-host-synthetic-'));
 const databasePath=path.join(directory,'core.sqlite');
 let core;
 t.after(async()=>{if(core)await core.close();assert.equal(path.dirname(path.resolve(directory)),path.resolve(tmpdir()));
  assert.ok(path.basename(directory).startsWith('w2-host-synthetic-'));rmSync(directory,{recursive:true,force:true});});
 // Build test-only schema6 from a fresh synthetic schema5, without activating activity.
 const initial=new ICoreStore(databasePath,{activityEnabled:false,activityAutoActivate:false});
 assert.equal(initial.domains,null);initial.close();
 const fixture=new DatabaseSync(databasePath);
 try{fixture.exec("BEGIN IMMEDIATE");fixture.exec(DOMAIN_SCHEMA_SQL);fixture.exec("UPDATE core_metadata SET value='6' WHERE key='schema_version';COMMIT");
  assertDomainSchemaReady(fixture);}finally{fixture.close();}
 const hooks=createPersonalDataHooks({plannerPrincipalIds:['planner']});
 core=createICoreServer({databasePath,clock:()=>Date.parse(now),domainHooks:hooks,
  domainVerifyAuthorization:({request,authorizationRef})=>authorizationRef==='synthetic:'+request.op_id,
  domainVerifyLegacyAdoption:({authorizationRef,adoption})=>authorizationRef==='synthetic-adoption'
   &&adoption.originMappingVerified===false&&adoption.sourceKind==='wi_local_plan'});
 assert.equal(core.store.db.prepare('SELECT COUNT(*) n FROM domain_registry').get().n,0);
 registerPersonalDataDomains(core.store.domains); // Explicit registration still defaults off.
 assert.deepEqual(core.store.db.prepare('SELECT mode FROM domain_registry').all().map(r=>r.mode),['off','off','off','off']);
 const issue=(name,scopes,actors,extra={})=>core.store.domains.configurePrincipal({principal_id:name,device_id:'device-'+name,
  installation_id:'install-'+name,scopes,actors,...extra});
 const planner=issue('planner',['plan_items:read','plan_items:create'],['agent_inferred']);
 const phone=issue('phone',['plan_items:read','plan_items:status'],['user_direct'],{trusted_interactive:true});
 const migrator=issue('migration',['plan_items:read','plan_items:adopt'],['import'],{import_sources:['wi_local_plan']});
 const binding=core.store.nodeId;
 const make=(kind,overrides={})=>({domain_protocol_version:1,core_instance_id:binding,op_id:randomUUID(),schema_version:1,kind,
  id:randomUUID(),base_revision:kind==='create'?0:1,created_at:now,expires_at:'2026-12-04T12:00:00.000Z',actor:'agent_inferred',...overrides});
 let address=await core.listen({port:0});let origin='http://127.0.0.1:'+address.port;
 const send=async(route,{token,body}={})=>{const response=await fetch(origin+route,{method:body?'POST':'GET',headers:{connection:'close',
  'x-i-core-domain-protocol':'1',...(token?{authorization:'Bearer '+token}:{}),...(body?{'content-type':'application/json'}:{})},
  ...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,body:await response.json()};};
 const base='/v1/core/domains/plan_items';
 const create=make('create',{data:item(),provenance:{source:'codex',source_refs:[],import_batch_id:null}});
 assert.equal((await send(base+'/ops',{token:planner.token,body:create})).body.error.code,'domain_off');
 core.store.domains.setMode('plan_items','authoritative');
 const accepted=await send(base+'/ops',{token:planner.token,body:create});assert.equal(accepted.status,201,JSON.stringify(accepted));
 const status=make('status',{id:create.id,actor:'user_direct',patch:{status:'完成'}});status.authorization_ref='synthetic:'+status.op_id;
 assert.equal((await send(base+'/ops',{token:phone.token,body:{...status,authorization_ref:'forged'}})).status,403);
 const done=await send(base+'/ops',{token:phone.token,body:status});assert.equal(done.status,201,JSON.stringify(done));
 assert.equal(done.body.record.data.completed_at,status.created_at);
 const privateField=make('status',{id:create.id,base_revision:2,actor:'user_direct',patch:{status:'放弃',title:'越权'}});
 privateField.authorization_ref='synthetic:'+privateField.op_id;
 assert.equal((await send(base+'/ops',{token:phone.token,body:privateField})).status,403);
 const adoptionRecord={id:'legacy-item-synthetic',revision:4,deleted_at:null,origin:{principal_id:'planner',device_id:'device-planner'},
  data:item(),provenance:{source:'wi_local_plan',source_refs:[],import_batch_id:'batch-synthetic'}};
 const adoptionOptions={authorizationRef:'synthetic-adoption',sourceKind:'wi_local_plan',sourceRecordId:adoptionRecord.id,
  sourceRevision:4,batchId:'batch-synthetic',mappingVersion:'mapping-synthetic'};
 const adopter=core.store.domains.authenticate(migrator.token);
 assert.equal(core.store.domains.adoptLegacyRecord(adopter,'plan_items',adoptionRecord,adoptionOptions).body.dry_run,true);
 assert.equal(core.store.db.prepare('SELECT COUNT(*) n FROM domain_records').get().n,1);
 const imported=core.store.domains.adoptLegacyRecord(adopter,'plan_items',adoptionRecord,{...adoptionOptions,dryRun:false});
 assert.equal(imported.status,201,JSON.stringify(imported));assert.equal(imported.body.receipt.targets[0].revision,4);
 assert.equal((await send(base+'/ops',{token:migrator.token,body:make('legacy_adopt')})).status,400);
 await core.close();core=null;
 // Versioned hooks are required after restart; default bootstrap supplies none.
 core=createICoreServer({databasePath,clock:()=>Date.parse(now)});
 address=await core.listen({port:0});origin='http://127.0.0.1:'+address.port;
 const refused=await send(base+'/snapshot?core_instance_id='+binding,{token:phone.token});
 assert.equal(refused.status,503);assert.equal(refused.body.error.code,'schema_not_ready');
 assert.equal((await send('/v1/core/health')).status,200);
 assert.equal(core.store.db.prepare('SELECT COUNT(*) n FROM domain_records').get().n,2);
});
