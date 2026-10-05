import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { DomainStore, DOMAIN_POLICY } from './domain_store.mjs';
import { DOMAIN_SCHEMA_SQL } from './domain_schema.mjs';
import { PERSONAL_SCHEMAS, PERSONAL_DOMAINS, createPersonalDataHooks, registerPersonalDataDomains,
  personalDedupHooks, validatePersonalRecord, validBusinessDate, validBusinessTime, validWeekKey,
  effectiveDisposition, stableImportId } from './personal_data_domains.mjs';

const now=Date.parse('2026-10-05T12:00:00.000Z');
const iso=new Date(now).toISOString();
const actions=['read','create','patch','delete','restore','purge','merge'];
const item=(overrides={})=>({title:'合成事项',level:'行动',area:'生活',parent_id:null,depends_on:[],status:'待办',replaced_by:null,
  block_kind:null,blocks:null,scheduled_at:null,planned_date:null,due_date:null,completed_at:null,energy:null,
  defer_count:0,source:'手打',source_url:null,note:'',remind_at:null,...overrides});
const capacity=()=>({deep:null,long:null,voice:null});
const week=()=>({week_key:'2026-W41',expected_capacity:capacity(),actual_capacity:capacity(),daily_capacities:[],area_quotas:[],debt:[]});
const day=()=>({date:'2026-10-05',display_version:1,generated_at:iso,change_summary:'',pending_decisions:[],capacity:capacity(),
  queues:{fixed:[],deep:[],long:[],voice:[],extra:[],errands:[]},noted:[],lights_out_at:null});
function fixture(t,{mode='authoritative',resolveDerivedReferences}={}) {
  const db=new DatabaseSync(':memory:');
  db.exec("CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT);INSERT INTO core_metadata VALUES('schema_version','6'),('node_id','synthetic-core'),('cursor_secret','synthetic-secret');");
  db.exec(DOMAIN_SCHEMA_SQL);
  const hooks=createPersonalDataHooks({captureSourcesByPrincipal:{capture:['phone_quick','claude_web'],other:['phone_quick']},
    plannerPrincipalIds:['planner'],processorPrincipals:{planner:'planner',organizer:'organizer'},resolveDerivedReferences});
  const store=new DomainStore(db,{nodeId:'synthetic-core',cursorSecret:'synthetic-secret',clock:()=>now,domainHooks:hooks,dedupHooks:personalDedupHooks(),
    verifyAuthorization:({request,authorizationRef})=>authorizationRef==='synthetic:'+request.op_id});
  registerPersonalDataDomains(store,{mode});
  const principal=(name,scopes,extra={})=>{
    const issued=store.configurePrincipal({principal_id:name,device_id:'device-'+name,installation_id:'install-'+name,scopes,
      actors:['agent_inferred','user_direct','user_via_agent'],trusted_interactive:true,...extra});
    return store.authenticate(issued.token);
  };
  const capture=principal('capture',['captures:read','captures:create','captures:patch','captures:delete'],{origin_device_only:true});
  const other=principal('other',['captures:read','captures:create','captures:patch','captures:delete'],{origin_device_only:true});
  const planner=principal('planner',['captures:read','captures:ack',...['plan_items','plan_weeks','plan_days'].flatMap(d=>actions.map(a=>d+':'+a))],{processor:'planner'});
  const organizer=principal('organizer',['captures:read','captures:ack'],{processor:'organizer'});
  const phone=principal('phone',['plan_items:read','plan_items:status','plan_weeks:read','plan_days:read']);
  function op(kind,extra={}){const value={domain_protocol_version:1,core_instance_id:'synthetic-core',op_id:randomUUID(),schema_version:1,kind,id:randomUUID(),
    base_revision:kind==='create'?0:1,created_at:iso,expires_at:new Date(now+DOMAIN_POLICY.intentTtl).toISOString(),actor:'agent_inferred',...extra};
    if(['user_direct','user_via_agent'].includes(value.actor))value.authorization_ref='synthetic:'+value.op_id;return value;}
  const create=(domain,data,p=planner,actor='agent_inferred',source=domain==='captures'?data.source:'codex')=>{
    const request=op('create',{data,provenance:{source,source_refs:[],import_batch_id:null},actor});
    const result=store.submit(p,domain,request);assert.equal(result.status,201,JSON.stringify(result));return {request,record:result.body.record,result};
  };
  t.after(()=>db.close());
  return {db,store,hooks,principal,capture,other,planner,organizer,phone,op,create,
    get:(domain,id,p=planner)=>store.getRecord(p,domain,id,'synthetic-core'),
    submit:(domain,request,p=planner)=>store.submit(p,domain,request)};
}
const reason=r=>r.body.reason??r.body.error?.code;
test('explicit registration defaults all four domains off and requires versioned hooks',t=>{
  const f=fixture(t,{mode:'off'});assert.deepEqual(f.db.prepare('SELECT domain,mode FROM domain_registry ORDER BY domain').all().map(r=>r.mode),['off','off','off','off']);
  assert.equal(reason(f.submit('plan_items',f.op('create',{data:item(),provenance:{source:'codex',source_refs:[],import_batch_id:null}}))),'domain_off');
  const bare=new DomainStore(f.db,{nodeId:'synthetic-core',cursorSecret:'synthetic-secret'});
  const result=bare.submit(f.planner,'plan_items',f.op('create',{data:item(),provenance:{source:'codex',source_refs:[],import_batch_id:null}}));
  assert.equal(result.status,503);
});
test('strict business dates, timestamps, ISO weeks and all nested shapes reject rollover/unknown fields',()=>{
  assert.equal(validBusinessDate('2026-02-29'),false);assert.equal(validBusinessDate('2024-02-29'),true);
  for(const value of ['2026-10-05T25:00:00Z','2026-02-30T12:00:00Z','2026-10-05T12:00:00+14:01','2026-10-05'])assert.equal(validBusinessTime(value),false);
  assert.equal(validWeekKey('2021-W53'),false);assert.equal(validWeekKey('2020-W53'),true);
  for(const [domain,data] of [['plan_items',item()],['plan_weeks',week()],['plan_days',day()]]){
    assert.equal(validatePersonalRecord(domain,{id:randomUUID(),data}),true);
    assert.equal(validatePersonalRecord(domain,{id:randomUUID(),data:{...data,hidden:true}}),false);
  }
  assert.equal(validatePersonalRecord('plan_items',{id:'x',data:item({blocks:0})}),false);
  assert.equal(validatePersonalRecord('plan_items',{id:'x',data:item({status:'完成'})}),false);
  assert.equal(validatePersonalRecord('plan_items',{id:'x',data:item({completed_at:iso})}),false);
  assert.equal(validatePersonalRecord('plan_items',{id:'x',data:item({blocks:0.5})}),true);
  const w=week();w.daily_capacities=[{date:'2026-10-12',expected:capacity(),actual:capacity()}];
  assert.equal(validatePersonalRecord('plan_weeks',{id:'x',data:w}),false);
  const d=day();d.queues.deep=['absent'];assert.equal(validatePersonalRecord('plan_days',{id:'x',data:d}),false);
});
test('WI references exist, preserve identities and reject each relation cycle',t=>{
  const f=fixture(t),parent=f.create('plan_items',item({title:'目的',level:'目的'})).record;
  const child=f.create('plan_items',item({parent_id:parent.id})).record;
  const cycle=f.op('patch',{id:parent.id,base_revision:1,patch:{parent_id:child.id}});
  assert.equal(f.submit('plan_items',cycle).status,400);
  assert.equal(f.get('plan_items',parent.id).body.record.data.parent_id,null);
  assert.equal(f.submit('plan_items',f.op('patch',{id:child.id,base_revision:1,patch:{depends_on:['absent']}})).status,400);
});
test('capture authors cannot forge source/provenance, processor defaults or edit another device',t=>{
  const f=fixture(t),data={text:'合成原话',source:'phone_quick',recorded_at:iso};
  const created=f.create('captures',data,f.capture,'user_direct');
  assert.equal(created.record.data.planner,undefined);
  assert.equal(effectiveDisposition(created.record,'planner').status,'pending');
  for(const patch of [{source:'claude_web'},{planner:{status:'done',outputs:[],input_revision:1,note:''}}])
    assert.equal(f.submit('captures',f.op('patch',{id:created.record.id,base_revision:1,actor:'user_direct',patch}),f.capture).status,403);
  assert.equal(f.submit('captures',f.op('patch',{id:created.record.id,base_revision:1,actor:'user_direct',patch:{text:'另一个主体'}}),f.other).status,404);
  const forged=f.op('create',{actor:'user_direct',data,provenance:{source:'claude_web',source_refs:[],import_batch_id:null}});
  assert.equal(f.submit('captures',forged,f.capture).status,403);
  forged.data={...data,planner:{status:'pending',outputs:[],input_revision:1,note:''}};forged.provenance.source='phone_quick';
  assert.equal(f.submit('captures',forged,f.capture).status,403);
});
test('two processors independently acknowledge same original version; edits invalidate stale input',t=>{
  const f=fixture(t),r=f.create('captures',{text:'合成混合输入',source:'phone_quick',recorded_at:iso},f.capture,'user_direct').record;
  const ack=(processor,p)=>f.submit('captures',f.op('ack_capture',{id:r.id,base_revision:1,processor,disposition:{[processor]:{
    status:'skipped',outputs:[],input_revision:1,...(processor==='planner'?{note:'合成感想'}:{})}}}),p);
  assert.equal(ack('planner',f.planner).status,201);assert.equal(ack('organizer',f.organizer).status,201);
  const current=f.get('captures',r.id).body.record;assert.equal(current.revision,3);assert.equal(current.data.text,r.data.text);
  assert.equal(effectiveDisposition(current,'planner').status,'skipped');
  assert.equal(f.submit('captures',f.op('patch',{id:r.id,base_revision:3,actor:'user_direct',patch:{text:'已修订合成输入'}}),f.capture).status,201);
  const updated=f.get('captures',r.id).body.record;assert.equal(effectiveDisposition(updated,'planner').status,'pending');
  const stale=f.op('ack_capture',{id:r.id,base_revision:4,processor:'planner',disposition:{planner:{status:'skipped',outputs:[],input_revision:1,note:''}}});
  assert.equal(reason(f.submit('captures',stale)),'stale_base');
  const forbidden={...stale,op_id:randomUUID(),processor:'organizer',disposition:{organizer:{status:'skipped',outputs:[],input_revision:4}}};
  assert.equal(f.submit('captures',forbidden).status,403);
});
test('phone status allows only completion/cancel and derives authorized action timestamp atomically',t=>{
  const f=fixture(t),r=f.create('plan_items',item()).record;
  for(const status of ['想法','待办','进行中','等待','被替代'])
    assert.equal(f.submit('plan_items',f.op('status',{id:r.id,base_revision:1,actor:'user_direct',patch:{status}}),f.phone).status,403);
  for(const patch of [{status:'完成',title:'偷改标题'},{status:'完成',completed_at:iso}])
    assert.equal(f.submit('plan_items',f.op('status',{id:r.id,base_revision:1,actor:'user_direct',patch}),f.phone).status,403);
  const done=f.op('status',{id:r.id,base_revision:1,actor:'user_direct',created_at:'2026-10-04T12:00:00.000Z',expires_at:'2026-12-01T12:00:00.000Z',patch:{status:'完成'}});
  const result=f.submit('plan_items',done,f.phone);assert.equal(result.status,201,JSON.stringify(result));
  assert.equal(result.body.record.data.completed_at,done.created_at);assert.equal(result.body.receipt.accepted_at,iso);
  assert.equal(result.body.record.field_meta.completed_at.actor,'user_direct');
  assert.equal(f.submit('plan_items',done,f.phone).body.outcome,'duplicate');
  assert.equal(f.store.getOperation(f.phone,'plan_items',done.op_id,'synthetic-core').status,200);
  const cancel=f.op('status',{id:r.id,base_revision:2,actor:'user_direct',patch:{status:'放弃'}});
  assert.equal(f.submit('plan_items',cancel,f.phone).body.record.data.completed_at,null);
});
test('planner changes cannot overwrite a phone user lock; scheduling remains a different field',t=>{
  const f=fixture(t),r=f.create('plan_items',item()).record;
  f.submit('plan_items',f.op('status',{id:r.id,base_revision:1,actor:'user_direct',patch:{status:'完成'}}),f.phone);
  assert.equal(reason(f.submit('plan_items',f.op('patch',{id:r.id,base_revision:2,patch:{status:'待办',completed_at:null}}))),'user_locked');
  assert.equal(f.submit('plan_items',f.op('patch',{id:r.id,base_revision:1,patch:{note:'结构外独立备注'}})).status,201);
});
test('separate phone capture/planning credentials keep ownership and planning reads distinct',t=>{
  const f=fixture(t),r=f.create('plan_items',item()).record;
  const constrained=f.principal('capture',['captures:read','captures:patch','plan_items:read'],{origin_device_only:true});
  assert.equal(f.get('plan_items',r.id,constrained).status,404);
  assert.equal(f.get('plan_items',r.id,f.phone).status,200);
  assert.equal(f.submit('plan_items',f.op('patch',{id:r.id,base_revision:1,actor:'user_direct',patch:{title:'手机结构写'}}),f.phone).status,403);
  assert.equal(f.store.auth(f.planner).scopes.some(s=>s.startsWith('chat:')||s.startsWith('ledger:')||s.startsWith('cycle:')),false);
});
test('claude_web author delete scrubs online bodies and registers minimal derived references',t=>{
  let output;
  const f=fixture(t,{resolveDerivedReferences:({outputs})=>outputs.map(id=>({domain:'plan_items',id}))});
  output=f.create('plan_items',item()).record.id;
  const r=f.create('captures',{text:'立即清除的合成原话',source:'claude_web',recorded_at:iso},f.capture,'user_direct').record;
  const ack=f.op('ack_capture',{id:r.id,base_revision:1,processor:'planner',disposition:{planner:{status:'done',outputs:[output],input_revision:1,note:''}}});
  assert.equal(f.submit('captures',ack).status,201);
  const del=f.op('delete',{id:r.id,base_revision:2,actor:'user_direct'});
  const result=f.submit('captures',del,f.capture);assert.equal(result.status,201,JSON.stringify(result));
  assert.equal(f.get('captures',r.id).body.tombstone.body_state,'purged');
  assert.equal(f.db.prepare("SELECT body_json FROM domain_records WHERE domain='captures' AND id=?").get(r.id).body_json,null);
  assert.equal(f.db.prepare("SELECT COUNT(*) n FROM domain_op_payloads WHERE domain='captures'").get().n,0);
  const metadata=f.db.prepare("SELECT op_meta_json FROM domain_ops WHERE domain='captures'").all().map(row=>JSON.parse(row.op_meta_json));
  assert.ok(metadata.some(m=>m.cascade_pending?.some(ref=>ref.domain==='plan_items'&&ref.id===output)));
  assert.equal(f.get('plan_items',output).status,200);assert.deepEqual(result.body.receipt.targets.map(v=>v.id),[r.id]);
});
test('normalized title and a matching deadline deduplicate tools but manual user creates remain explicit',t=>{
  const f=fixture(t),one=f.create('plan_items',item({title:'  ＡＢＣ   合成 ',due_date:'2026-10-09'}));
  const op=f.op('create',{data:item({title:'abc 合成',due_date:'2026-10-09'}),provenance:{source:'codex',source_refs:[],import_batch_id:null}});
  const duplicate=f.submit('plan_items',op);assert.equal(duplicate.body.duplicate_of,one.record.id);
  assert.equal(duplicate.body.receipt.receipt_id,one.result.body.receipt.receipt_id);
  const manual={...op,op_id:randomUUID(),id:randomUUID(),actor:'user_direct'};manual.authorization_ref='synthetic:'+manual.op_id;
  assert.equal(f.submit('plan_items',manual).status,201);
});
test('days maintain explicit display editions and ordered queues; week unknown remains null',t=>{
  const f=fixture(t),task=f.create('plan_items',item()).record;
  const data=day();data.queues.deep=[task.id];
  const r=f.create('plan_days',data).record;
  const changed={...data,change_summary:'合成变更'};
  assert.equal(f.submit('plan_days',f.op('patch',{id:r.id,base_revision:1,patch:changed})).status,400);
  changed.display_version=2;
  assert.equal(f.submit('plan_days',f.op('patch',{id:r.id,base_revision:1,patch:changed})).status,201);
  const w=f.create('plan_weeks',week()).record;assert.equal(w.data.expected_capacity.deep,null);
});
test('feed/cursor carries current business states and independent consumer acknowledgement',t=>{
  const f=fixture(t),base=f.store.snapshot(f.phone,'plan_items',{core_instance_id:'synthetic-core'}).body.manifest.base_cursor;
  const r=f.create('plan_items',item()).record;
  const page=f.store.changes(f.phone,'plan_items',{core_instance_id:'synthetic-core',cursor:base});
  assert.equal(page.body.records[0].id,r.id);
  assert.equal(f.store.acknowledge(f.phone,'plan_items',{domain_protocol_version:1,core_instance_id:'synthetic-core',cursor:page.body.next_cursor}).body.advanced,true);
  assert.equal(f.store.changes(f.phone,'plan_weeks',{core_instance_id:'synthetic-core',cursor:page.body.next_cursor}).status,409);
});
test('stable identity is independent from content, domain separated and UUID format',()=>{
  const first=stableImportId('source-a','plan_days','2026-10-05');
  assert.equal(stableImportId('source-a','plan_days','2026-10-05'),first);
  assert.notEqual(stableImportId('source-b','plan_days','2026-10-05'),first);
  assert.match(first,/^[0-9a-f-]{14}5/);
});
