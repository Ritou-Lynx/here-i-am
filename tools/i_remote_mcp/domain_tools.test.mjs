import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {createICoreServer} from '../i_core/i_core_server.mjs';
import {ICoreStore} from '../i_core/i_core_store.mjs';
import {DOMAIN_SCHEMA_SQL} from '../i_core/domain_schema.mjs';
import {createPersonalDataHooks,registerPersonalDataDomains,personalDedupHooks} from '../i_core/personal_data_domains.mjs';
import {createDomainClient,createDomainTools,createCoreRemember,PLANNER_SCOPES} from './domain_tools.mjs';
import {createPlannerApp} from './planner_server.mjs';
import {createToolHandlers,handleRpcMessage} from './mcp.mjs';
import {importPersonalNotes} from '../i_core/import_personal_notes.mjs';
import {startTestServer,obtainTokens,initSession,mcpPost,registerClient,pkcePair,authorizeParams,submitPassphrase,postToken,REDIRECT_URI,PUBLIC_URL} from './fixtures.mjs';
import {createWebDomainOptions} from './server.mjs';

const now='2026-10-05T12:00:00.000Z';
const item=(extra={})=>({title:'synthetic item',level:'行动',area:'未归类',parent_id:null,depends_on:[],status:'待办',replaced_by:null,
 block_kind:null,blocks:null,scheduled_at:null,planned_date:null,due_date:null,completed_at:null,energy:null,defer_count:0,
 source:'手打',source_url:null,note:'',remind_at:null,...extra});
const capacity=()=>({deep:null,long:null,voice:null});
const week=()=>({week_key:'2026-W41',expected_capacity:capacity(),actual_capacity:capacity(),daily_capacities:[],area_quotas:[],debt:[]});
const day=()=>({date:'2026-10-05',display_version:1,generated_at:now,change_summary:'synthetic',pending_decisions:[],capacity:capacity(),queues:{fixed:[],deep:[],long:[],voice:[],extra:[],errands:[]},noted:[],lights_out_at:null});
function args(extra={}){const value={op_id:randomUUID(),id:randomUUID(),base_revision:0,created_at:now,expires_at:'2026-12-04T12:00:00.000Z',...extra};return value;}
function authorized(extra={}){const value=args(extra);value.authorization_ref='synthetic:'+value.op_id;return value;}
const reason=result=>result.reason??result.error?.code;

async function fixture(t,{mode='authoritative'}={}) {
 const directory=mkdtempSync(path.join(tmpdir(),'w3-domain-synthetic-'));const databasePath=path.join(directory,'core.sqlite');let core;
 t.after(async()=>{if(core)await core.close();assert.equal(path.dirname(path.resolve(directory)),path.resolve(tmpdir()));assert.ok(path.basename(directory).startsWith('w3-domain-synthetic-'));rmSync(directory,{recursive:true,force:true});});
 const initial=new ICoreStore(databasePath,{activityEnabled:false,activityAutoActivate:false});initial.close();
 const db=new DatabaseSync(databasePath);try{db.exec("BEGIN IMMEDIATE");db.exec(DOMAIN_SCHEMA_SQL);db.exec("UPDATE core_metadata SET value='6' WHERE key='schema_version';COMMIT");}finally{db.close();}
 const hooks=createPersonalDataHooks({captureSourcesByPrincipal:{web:['claude_web'],other:['claude_web']},plannerPrincipalIds:['planner'],processorPrincipals:{planner:'planner'},resolveDerivedReferences:({outputs})=>outputs.map(id=>({domain:'plan_items',id}))});
 core=createICoreServer({databasePath,clock:()=>Date.parse(now),domainHooks:hooks,domainDedupHooks:personalDedupHooks(),domainVerifyAuthorization:({request,authorizationRef})=>authorizationRef==='synthetic:'+request.op_id,
 domainVerifyLegacyAdoption:({authorizationRef,record,adoption})=>authorizationRef==='synthetic-import-proof'&&record.origin.principal_id==='web'&&record.origin.device_id==='device-web'&&adoption.sourceKind==='i_remember'});
 registerPersonalDataDomains(core.store.domains,{mode});
 const webScopes=['captures:read','captures:create','captures:patch','captures:delete','plan_weeks:read','plan_days:read'];
 const issue=(name,scopes,extra={})=>core.store.domains.configurePrincipal({principal_id:name,device_id:'device-'+name,installation_id:'install-'+name,scopes,actors:['agent_inferred'],...extra});
 const planner=issue('planner',PLANNER_SCOPES,{processor:'planner'});
 const web=issue('web',webScopes,{actors:['user_via_agent'],origin_device_only:true});
 const other=issue('other',webScopes,{actors:['user_via_agent'],origin_device_only:true});
 const phone=issue('phone',['plan_items:read','plan_items:status'],{actors:['user_direct'],trusted_interactive:true});
 const address=await core.listen({port:0});const coreUrl='http://127.0.0.1:'+address.port;
 const client=(credential,options={})=>createDomainClient({coreUrl,coreInstanceId:core.store.nodeId,token:credential.token,...options});
 const plannerTools=createDomainTools({client:client(planner),scopes:PLANNER_SCOPES});
 const webTools=createDomainTools({client:client(web),scopes:webScopes,surface:'web',captureSource:'claude_web'});
 return {directory,core,coreUrl,client,planner,web,other,phone,webScopes,plannerTools,webTools,remember:createCoreRemember({client:client(web),scopes:webScopes})};
}

test('real schema6 domain tools preserve creation, patch, full week/day editions and exact replay',async t=>{
 const f=await fixture(t);const h=f.plannerTools.handlers;const create=args({data:item()});
 const first=await h.plan_upsert(create);assert.equal(first.outcome,'accepted',JSON.stringify(first));
 const replay=await h.plan_upsert(create);assert.equal(replay.receipt.receipt_id,first.receipt.receipt_id);
 assert.equal(reason(await h.plan_upsert({...create,data:item({title:'changed same operation'})})),'idempotency_conflict');
 const patch=await h.plan_upsert(args({id:create.id,base_revision:1,data:{title:'updated'}}));assert.equal(patch.record.revision,2);
 assert.equal((await h.plan_list({id:create.id})).record.data.title,'updated');
 const w=args({data:week()});assert.equal((await h.week_set(w)).outcome,'accepted');assert.equal((await h.week_get({id:w.id})).record.data.week_key,'2026-W41');
 const d=args({data:day()});d.data.queues.deep=[create.id];assert.equal((await h.day_set(d)).outcome,'accepted');
 const next={...day(),display_version:2,change_summary:'reorder'};delete next.date;
 assert.equal((await h.day_set(args({id:d.id,base_revision:1,data:next}))).record.data.display_version,2);
 assert.equal(reason(await h.day_set(args({id:d.id,base_revision:2,data:{change_summary:'missing edition group'}}))),'incomplete_field_group');
 assert.equal((await h.day_get({id:d.id})).record.data.display_version,2);
 for(let i=0;i<8;i++)assert.equal((await h.plan_list({})).records.length,1); // Completed snapshots do not consume quota indefinitely.
});

test('capture processing binds planner, input revision and outputs; stale ack cannot mark edited content done',async t=>{
 const f=await fixture(t);const add=authorized({text:'synthetic capture',recorded_at:now});
 const created=await f.webTools.handlers.capture_add(add);assert.equal(created.outcome,'accepted',JSON.stringify(created));
 assert.equal(created.record.dispositions.planner.status,'pending');
 const work=args({data:item()});await f.plannerTools.handlers.plan_upsert(work);
 const ack=args({id:add.id,base_revision:1,disposition:{status:'done',outputs:[work.id],input_revision:1,note:'planned'}});
 const accepted=await f.plannerTools.handlers.capture_ack(ack);assert.equal(accepted.outcome,'accepted',JSON.stringify(accepted));
 assert.equal(accepted.record.dispositions.organizer.status,'pending');
 const edited=await f.remember.remember(authorized({action:'update',note_id:add.id,id:add.id,base_revision:2,text:'new input'}));assert.equal(edited.record.revision,3);
 assert.equal(edited.record.dispositions.planner.status,'pending');
 assert.equal(reason(await f.plannerTools.handlers.capture_ack(args({id:add.id,base_revision:3,disposition:ack.disposition}))),'stale_base');
 await assert.rejects(()=>f.plannerTools.handlers.capture_ack({...ack,processor:'organizer'}),/invalid_request/);
});

test('i_remember Core CRUD clears online bodies; deleted retry never resurrects or returns old text',async t=>{
 const f=await fixture(t);const add=authorized({action:'add',text:'synthetic original secret'});
 const first=await f.remember.remember(add);assert.equal(first.note.text,add.text);assert.equal(first.note.dispositions.planner.status,'pending');
 const changed=await f.remember.remember(authorized({action:'update',id:add.id,base_revision:1,text:'synthetic replacement secret'}));assert.equal(changed.note.revision,2);
 assert.equal((await f.remember.remember({action:'list'})).notes.length,1);
 const deletion=authorized({action:'delete',id:add.id,base_revision:2});const gone=await f.remember.remember(deletion);assert.equal(gone.outcome,'accepted');
 const tomb=await f.client(f.web).record('captures',add.id);assert.equal(tomb.tombstone.body_state,'purged');
 assert.equal(reason(await f.remember.remember(add)),'deleted_target');
 assert.equal((await f.remember.remember(deletion)).receipt.receipt_id,gone.receipt.receipt_id);
 assert.deepEqual((await f.remember.remember({action:'list'})).notes,[]);
 const rows=f.core.store.db.prepare('SELECT envelope_json,body_json FROM domain_records').all();assert.ok(!JSON.stringify(rows).includes('synthetic original secret'));assert.ok(!JSON.stringify(rows).includes('synthetic replacement secret'));
 assert.equal(f.core.store.db.prepare('SELECT COUNT(*) n FROM domain_op_payloads').get().n,0);
});

test('authorization, origin ownership, scope and strict fields fail closed without chat lookup',async t=>{
 const f=await fixture(t);const add=authorized({text:'owned',recorded_at:now});
 assert.equal(reason(await f.webTools.handlers.capture_add({...add,authorization_ref:'forged'})),'actor_not_authorized');
 const good=authorized({text:'owned',recorded_at:now});await f.webTools.handlers.capture_add(good);
 assert.equal((await f.client(f.other).record('captures',good.id)).http_status,404);
 const other=createCoreRemember({client:f.client(f.other),scopes:f.webScopes});assert.equal((await other.remember({action:'list'})).notes.length,0);
 assert.equal((await other.remember(authorized({action:'delete',id:good.id,base_revision:1}))).http_status,404);
 assert.equal(f.webTools.handlers.plan_upsert,undefined);assert.equal(f.webTools.handlers.capture_ack,undefined);
 assert.equal(f.plannerTools.handlers.i_context,undefined);assert.equal(f.plannerTools.handlers.capture_add,undefined);
 await assert.rejects(()=>f.webTools.handlers.capture_add({...good,actor:'user_direct'}),/invalid_request/);
 const raw=await fetch(f.coreUrl+'/v1/core/changes',{headers:{authorization:'Bearer '+f.planner.token,'x-core-protocol':'0.1'}});assert.ok([401,403].includes(raw.status),String(raw.status));
 const fakeCeiling=createDomainTools({client:f.client(f.web),scopes:PLANNER_SCOPES});assert.equal((await fakeCeiling.handlers.plan_upsert(args({data:item()}))).http_status,403);
});

test('user status writes derive completion and block AI overwrite; same-base user conflict is explicit',async t=>{
 const f=await fixture(t);const op=args({data:item()});await f.plannerTools.handlers.plan_upsert(op);
 const phone=createDomainTools({client:f.client(f.phone),scopes:['plan_items:read','plan_items:status']});
 const done=authorized({id:op.id,base_revision:1,status:'完成'});const result=await phone.handlers.plan_set_status(done);assert.equal(result.record.data.completed_at,now);
 const conflict=await phone.handlers.plan_set_status(authorized({id:op.id,base_revision:1,status:'放弃'}));assert.equal(conflict.outcome,'needs_resolution');assert.equal(conflict.reason,'user_conflict');
 const locked=await f.plannerTools.handlers.plan_upsert(args({id:op.id,base_revision:2,data:{status:'待办',completed_at:null}}));assert.equal(reason(locked),'user_locked');
 await assert.rejects(()=>phone.handlers.plan_set_status({...done,title:'injected'}),/invalid_request/);
});

test('lost Core response stays transport_unknown and exact retry reuses one durable receipt',async t=>{
 const f=await fixture(t);let drop=true;
 const client=f.client(f.planner,{fetchImpl:async(...params)=>{const response=await fetch(...params);if(drop){drop=false;await response.arrayBuffer();throw new Error('synthetic dropped response');}return response;}});
 const h=createDomainTools({client,scopes:PLANNER_SCOPES}).handlers;const op=args({data:item()});
 assert.equal((await h.plan_upsert(op)).outcome,'transport_unknown');const retry=await h.plan_upsert(op);assert.equal(retry.outcome,'duplicate');
 assert.equal(f.core.store.db.prepare("SELECT COUNT(*) n FROM domain_changes WHERE domain='plan_items'").get().n,1);
});

test('local MCP requires distinct configured scoped bearer, binds loopback and has zero chat tools',async t=>{
 const f=await fixture(t);const app=createPlannerApp({coreUrl:f.coreUrl,coreInstanceId:f.core.store.nodeId,credentials:[{token:f.planner.token,scopes:PLANNER_SCOPES}]});
 t.after(()=>app.close());const address=await app.listen({port:0});assert.equal(address.address,'127.0.0.1');
 const call=async(name,token=f.planner.token,extra={})=>{const response=await fetch(`http://127.0.0.1:${address.port}/mcp`,{method:'POST',headers:{authorization:'Bearer '+token,'content-type':'application/json',...extra},body:JSON.stringify({jsonrpc:'2.0',id:1,method:name==='list'?'tools/list':'tools/call',params:{name,arguments:{}}})});return {status:response.status,body:await response.json()};};
 assert.equal((await call('list','oauth-web-token')).status,401);assert.equal((await call('list',f.planner.token,{origin:'https://claude.ai'})).status,403);
 const list=await call('list');assert.ok(list.body.result.tools.every(tool=>!tool.name.startsWith('i_')));assert.equal(list.body.result.tools.length,8);
 assert.equal((await call('i_context')).body.error.code,-32602);assert.equal((await call('capture_add')).body.error.code,-32602);
 assert.throws(()=>createPlannerApp({coreUrl:f.coreUrl,coreInstanceId:f.core.store.nodeId,credentials:[{token:f.planner.token,scopes:['chat:read']}]}),/scope_ceiling/);
});

test('Core mode never falls back to legacy notes and MCP errors retain structured conflict outcomes',async t=>{
 const f=await fixture(t,{mode:'off'});let legacyReads=0;
 const handlers=createToolHandlers({getReadModel:async()=>({policySummary:()=>({}),recentMessages:()=>[]}),writeback:{activeNotes:()=>{legacyReads++;return [];},remember:()=>{throw new Error('legacy write');},chatTurn:async()=>({thread_id:'synthetic-thread',recorded:{new_turns:1},last_recorded:null,core_status:'ok',excludeSyncIds:new Set()})},coreRemember:f.remember});
 const context=await handlers.i_context({});assert.equal(context.remembered_notes_error.code,'core_notes_unavailable');assert.deepEqual(context.recent_messages,[]);assert.equal(legacyReads,0);
 const chat=await handlers.i_chat_turn({phase:'start',turns:[{role:'user',content:'synthetic'}]});assert.equal(chat.core_status,'ok');assert.equal(chat.recorded.new_turns,1);assert.equal(chat.remembered_notes_error.code,'core_notes_unavailable');assert.equal(legacyReads,0);
 const result=await handleRpcMessage({jsonrpc:'2.0',id:1,method:'tools/call',params:{name:'plan_upsert',arguments:args({data:item()})}},{...f.plannerTools,session:{},scopes:[]});
 assert.equal(result.result.isError,true);assert.equal(result.result.structuredContent.error.code,'domain_off');
});

test('legacy notes dry-run does not mutate; explicit synthetic adoption is skipped for planner and keeps old identity/revision',async t=>{
 const f=await fixture(t);const sourcePath=path.join(f.directory,'legacy-closed.sqlite');const source=new DatabaseSync(sourcePath);
 source.exec('CREATE TABLE notes(note_id TEXT PRIMARY KEY,revision INTEGER,text TEXT,status TEXT,created_at_ms INTEGER,updated_at_ms INTEGER,delivered_revision INTEGER,phone_card_id TEXT)');
 source.prepare('INSERT INTO notes VALUES(?,?,?,?,?,?,?,?)').run('note_synthetic_old',7,'synthetic old note','active',Date.parse(now),Date.parse(now),7,'card-old');source.close();
 const issued=f.core.store.domains.configurePrincipal({principal_id:'importer',device_id:'importer',installation_id:'importer',scopes:['captures:adopt'],actors:['import'],import_sources:['i_remember']});
 const options={sourcePath,sourceId:'synthetic-notes',batchId:'synthetic-batch',targetInstanceId:f.core.store.nodeId,target:f.core.store.domains,principal:f.core.store.domains.authenticate(issued.token),authorizationRef:'synthetic-import-proof',originMapping:()=>({principal_id:'web',device_id:'device-web'})};
 const dry=importPersonalNotes(options);assert.equal(dry.phase,'dry_run');assert.equal(dry.totals.validated,1);assert.equal(f.core.store.db.prepare('SELECT COUNT(*) n FROM domain_records').get().n,0);
 assert.equal(importPersonalNotes({...options,dryRun:false}).totals.accepted,1);
 const listed=(await f.remember.remember({action:'list'})).notes;assert.equal(listed[0].note_id,'note_synthetic_old');assert.equal(listed[0].revision,7);assert.equal(listed[0].dispositions.planner.status,'skipped');assert.equal(listed[0].dispositions.organizer.status,'pending');
 const update=await f.remember.remember(authorized({action:'update',id:'note_synthetic_old',base_revision:7,text:'synthetic edited old note'}));assert.equal(update.note.revision,8);assert.equal(update.note.dispositions.planner.status,'skipped');
 const deletion=await f.remember.remember(authorized({action:'delete',id:'note_synthetic_old',base_revision:8}));assert.equal(deletion.outcome,'accepted');assert.equal((await f.client(f.web).record('captures','note_synthetic_old')).tombstone.body_state,'purged');
});

test('OAuth web entry exposes only web tools, blocks planner calls and requires i.write for captures',async t=>{
 const f=await fixture(t);const app=await startTestServer({coreRemember:f.remember,domainTools:f.webTools});t.after(()=>app.close());
 const readToken=await obtainTokens(app.base);const {sessionId}=await initSession(app.base,readToken.access_token);
 // Simulate a still-valid token issued before writeback activation; new consent grants i.write by existing design.
 app.oauth.store.state.access_tokens[createHash('sha256').update(readToken.access_token).digest('hex')].scope='i.read';
 const call=(name,arguments_,token=readToken.access_token,session=sessionId)=>mcpPost(app.base,token,{jsonrpc:'2.0',id:2,method:'tools/call',params:{name,arguments:arguments_}},{sessionId:session});
 assert.equal((await call('plan_upsert',args({data:item()}))).body.error.code,-32602);
 assert.equal((await call('capture_ack',{})).body.error.code,-32602);
 assert.equal((await call('capture_add',authorized({text:'web capture',recorded_at:now}))).body.result.isError,true);
 const {body:client}=await registerClient(app.base);const {verifier,challenge}=pkcePair();const params=authorizeParams({clientId:client.client_id,challenge});params.set('scope','i.read i.write');
 const consent=await submitPassphrase(app.base,params);const code=new URL(consent.headers.get('location')).searchParams.get('code');
 const token=await postToken(app.base,{grant_type:'authorization_code',code,client_id:client.client_id,redirect_uri:REDIRECT_URI,code_verifier:verifier,resource:PUBLIC_URL+'/mcp'});
 const writerSession=await initSession(app.base,token.body.access_token);
 const add=await call('i_remember',authorized({action:'add',text:'synthetic web remembered'}),token.body.access_token,writerSession.sessionId);
 assert.equal(add.body.result.structuredContent.outcome,'accepted',JSON.stringify(add.body));
 assert.equal((await call('i_context',{},token.body.access_token,writerSession.sessionId)).body.result.structuredContent.remembered_notes.length,1);
});

test('web combines owner-only captures and separately scoped plan reader without widening either token',async t=>{
 const f=await fixture(t);const w=args({data:week()});await f.plannerTools.handlers.week_set(w);
 assert.equal((await f.webTools.handlers.week_get({id:w.id})).http_status,404); // Global owner-only filter is intentionally retained.
 const reader=f.core.store.domains.configurePrincipal({principal_id:'web-plan-reader',device_id:'web-plan-reader',installation_id:'web-plan-reader',scopes:['plan_weeks:read','plan_days:read'],actors:['agent_inferred']});
 const config={enabled:true,remember_backend:'core',core_url:f.coreUrl,core_instance_id:f.core.store.nodeId,token:f.web.token,scopes:f.webScopes.filter(scope=>scope.startsWith('captures:')),plan_reads:{token:reader.token,scopes:['plan_weeks:read','plan_days:read']}};
 const options=createWebDomainOptions(config);
 assert.equal((await options.domainTools.handlers.week_get({id:w.id})).record.data.week_key,'2026-W41');
 assert.equal((await f.client(reader).snapshot('captures',{})).http_status,403);
 assert.throws(()=>createWebDomainOptions({...config,plan_reads:{...config.plan_reads,token:f.web.token}}),/invalid_web_plan/);
 const created=authorized({text:'scoped owner capture',recorded_at:now});assert.equal((await options.domainTools.handlers.capture_add(created)).outcome,'accepted');
 f.core.store.domains.configurePrincipal({principal_id:'web',device_id:'device-web',installation_id:'install-web',scopes:['captures:read'],actors:['user_via_agent'],origin_device_only:true});
 assert.equal((await options.domainTools.handlers.capture_add(authorized({text:'revoked credential',recorded_at:now}))).http_status,401);
});
