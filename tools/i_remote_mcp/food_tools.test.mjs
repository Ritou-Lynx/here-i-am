import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {foodTotals} from '../i_core/food_domains.mjs';
import {createFoodTools,createDomainClient,FOOD_TOOLS} from './domain_tools.mjs';
import {createWebDomainOptions} from './server.mjs';
import {startTestServer,initSession,mcpPost} from './fixtures.mjs';

const scopes=['food_entries:read','food_entries:create','food_entries:patch'];
const food=(extra={})=>({name:'合成食物',food_ref:{source:'model',id:null},grams:100,grams_low:80,grams_high:120,kcal:123.45,protein_g:4.05,fat_g:2.04,carb_g:20.16,basis:'photo',confidence:'low',...extra});
const entry=(extra={})=>({eaten_at:'2026-10-24T12:00:00+08:00',meal:'lunch',title:'合成午餐',input_kind:'photo',items:[food()],...extra});
function fixture({timeZone='Asia/Shanghai',rows=[]}={}) {
  const calls=[],records=new Map(rows.map(row=>[row.id,row])),operations=new Map();let clock=Date.parse('2026-10-24T04:00:00Z');
  const client={
    operation:async()=>({http_status:404}),
    async submit(domain,intent) {
      calls.push({domain,intent:structuredClone(intent)});
      if(operations.has(intent.op_id))return operations.get(intent.op_id);
      const old=records.get(intent.id);
      assert.equal(intent.base_revision,old?.revision??0);
      const record={id:intent.id,revision:(old?.revision??0)+1,data:intent.data??{...old.data,...intent.patch}};
      records.set(record.id,record);const result={http_status:201,outcome:'accepted',record};operations.set(intent.op_id,result);return result;
    },
    snapshot:async()=>({http_status:200,records:[...records.values()],manifest:{base_cursor:'synthetic-cursor'},snapshot_id:'synthetic-snapshot'}),
    acknowledge:async()=>({http_status:200}),
  };
  const adapter=createFoodTools({client,scopes,timeZone,now:()=>clock});
  return {...adapter,client,calls,records,advance:()=>{clock+=60000;}};
}

test('food add → update → void preserves exact intent shape and generated retry timestamps',async()=>{
  const f=fixture(),id=randomUUID();
  const add={action:'add',op_id:randomUUID(),id,entry:entry()};
  const first=await f.handlers.food_log(add);
  assert.deepEqual(first,{id,revision:1,local_date:'2026-10-24',totals:foodTotals(add.entry.items),day_totals:foodTotals(add.entry.items)});
  assert.deepEqual(f.calls[0].intent,{op_id:add.op_id,id,base_revision:0,kind:'create',actor:'agent_inferred',
    created_at:'2026-10-24T04:00:00.000Z',expires_at:'2026-12-23T04:00:00.000Z',
    data:{...add.entry,note:'',local_date:'2026-10-24',totals:foodTotals(add.entry.items),user_corrected:false,voided:false},
    provenance:{source:'food_log',source_refs:[],import_batch_id:null}});
  f.advance();await f.handlers.food_log(add);assert.deepEqual(f.calls[1],f.calls[0]);
  await assert.rejects(()=>f.handlers.food_log({...add,entry:entry({title:'changed'})}),/idempotency_conflict/);
  const update={action:'update',op_id:randomUUID(),id,base_revision:1,entry:entry({items:[food({kcal:200})]})};
  const updated=await f.handlers.food_log(update);
  assert.equal(updated.totals.kcal,200);
  const intent=f.calls[2].intent;
  assert.equal(intent.kind,'patch');assert.equal(intent.actor,'agent_inferred');assert.equal(intent.base_revision,1);assert.equal(intent.op_id,update.op_id);
  assert.deepEqual(intent.patch,{...update.entry,note:'',local_date:'2026-10-24',totals:foodTotals(update.entry.items),user_corrected:false,voided:false});
  assert.equal(Object.hasOwn(intent,'data'),false);assert.equal(Object.hasOwn(intent,'authorization_ref'),false);
  const voidArgs={action:'void',op_id:randomUUID(),id,base_revision:2};
  const voided=await f.handlers.food_log(voidArgs);
  assert.deepEqual(f.calls[3].intent.patch,{voided:true});assert.equal(f.calls[3].intent.kind,'patch');
  assert.equal(f.calls[3].intent.actor,'agent_inferred');assert.equal(f.calls[3].intent.base_revision,2);assert.equal(f.calls[3].intent.op_id,voidArgs.op_id);
  assert.equal(voided.day_totals.kcal,0);assert.deepEqual((await f.handlers.food_day({})).entries,[]);
});

test('food local day uses configured timezone and 04:00 including DST',async()=>{
  for(const [timeZone,eaten_at,date] of [
    ['Asia/Shanghai','2026-10-24T03:59:00+08:00','2026-10-23'],['Asia/Shanghai','2026-10-24T04:00:00+08:00','2026-10-24'],
    ['America/New_York','2026-11-01T03:59:00-05:00','2026-10-31'],['America/New_York','2026-11-01T04:00:00-05:00','2026-11-01'],
  ]) {
    const f=fixture({timeZone});const result=await f.handlers.food_log({action:'add',op_id:randomUUID(),id:randomUUID(),entry:entry({eaten_at})});
    assert.equal(result.local_date,date);
  }
  assert.equal((await fixture().handlers.food_day()).date,'2026-10-24');
});

test('MCP independently computes decimal food totals matching Core',async()=>{
  const items=[food(),food({grams:75,grams_low:55,grams_high:150,kcal:101.17,protein_g:3.99})];
  const f=fixture();await f.handlers.food_log({action:'add',op_id:randomUUID(),id:randomUUID(),entry:entry({items})});
  assert.deepEqual(f.calls[0].intent.data.totals,foodTotals(items));
  assert.equal(f.calls[0].intent.data.totals.kcal,224.6);
});

test('food rejects caller computed fields, actor overrides, invalid entries and bases before any write',async()=>{
  const f=fixture(),args={action:'add',op_id:randomUUID(),id:randomUUID(),entry:entry()};
  for(const key of ['totals','local_date','actor']) {
    await assert.rejects(()=>f.handlers.food_log({...args,[key]:'untrusted'}),/food_field_not_allowed/);
    await assert.rejects(()=>f.handlers.food_log({...args,entry:{...args.entry,[key]:'untrusted'}}),/food_field_not_allowed/);
  }
  for(const patch of [{op_id:'bad'},{base_revision:0},{action:'delete'},{entry:entry({eaten_at:'2026-02-30T00:00:00Z'})},
    {entry:entry({items:[food({grams_low:101})]})},{entry:entry({items:Array.from({length:41},()=>food())})},
    {entry:entry({items:[food({basis:'unknown'})]})},{entry:entry({items:[food({kcal:NaN})]})},
    {action:'update'},{action:'void',base_revision:1},
  ])await assert.rejects(()=>f.handlers.food_log({...args,...patch}));
  await assert.rejects(()=>f.handlers.food_day({date:'2026-02-30'}),/invalid_food_date/);
  assert.equal(f.calls.length,0);
});

test('food day follows snapshot pages, filters deletion/void/date, sorts business time and sums rounded totals',async()=>{
  const row=(id,eaten_at,extra={})=>({id,data:{...entry({eaten_at}),local_date:'2026-10-24',voided:false,totals:foodTotals([food()])},...extra});
  const early=row('early','2026-10-24T08:00:00+08:00'),late=row('late','2026-10-24T14:00:00+08:00');
  const voided=row('voided','2026-10-24T09:00:00+08:00');voided.data.voided=true;
  const other=row('other','2026-10-23T09:00:00+08:00');other.data.local_date='2026-10-23';
  const queries=[],acks=[];
  const client={snapshot:async(domain,query)=>{assert.equal(domain,'food_entries');queries.push(query);return query.page_token?
    {http_status:200,records:[early,other],manifest:{base_cursor:'end'},snapshot_id:'snapshot'}:
    {http_status:200,records:[late,voided,row('deleted','2026-10-24T07:00:00+08:00',{deleted_at:'synthetic'})],next_page_token:'next'};},
    acknowledge:async(...args)=>acks.push(args)};
  const h=createFoodTools({client,scopes}).handlers;
  const result=await h.food_day({date:'2026-10-24'});
  assert.deepEqual(result.entries.map(row=>row.id),['early','late']);
  assert.equal(result.day_totals.kcal,247);assert.equal(result.day_totals.kcal_low,197.6);
  assert.deepEqual(queries,[{limit:100},{limit:100,page_token:'next'}]);assert.deepEqual(acks,[['food_entries','end','snapshot']]);
});

const config=()=>({enabled:true,remember_backend:'core',core_url:'http://127.0.0.1:1',core_instance_id:'synthetic-core',token:'synthetic-captures',scopes:[],
  plan_reads:{token:'synthetic-plan',scopes:['plan_days:read']},food:{token:'synthetic-food',scopes}});
test('food configuration is independent, opt-in and restricted to food read/create/patch',()=>{
  const base=config();delete base.food;
  assert.deepEqual(createWebDomainOptions(base).domainTools.tools.map(tool=>tool.name),['day_get']);
  const enabled=createWebDomainOptions(config()).domainTools;
  assert.deepEqual(enabled.tools.map(tool=>tool.name),['day_get','food_log','food_day']);
  assert.equal(enabled.tools.find(tool=>tool.name==='food_log').requiredScope,'i.write');
  for(const food of [null,false,[],{}, {token:'synthetic-captures',scopes},{token:'synthetic-plan',scopes},{token:'',scopes},{token:'with space',scopes},
    {token:'synthetic-food',scopes:['food_entries:delete']},{token:'synthetic-food',scopes:['captures:read']},{token:'synthetic-food',scopes:'bad'},
    {token:'synthetic-food',scopes,time_zone:'Not/AZone'},{token:'synthetic-food',scopes,extra:true},
  ])assert.throws(()=>createWebDomainOptions({...config(),food}),/invalid_web_food_configuration/);
  assert.deepEqual(createWebDomainOptions({...config(),food:{token:'synthetic-food',scopes:[]}}).domainTools.tools.map(tool=>tool.name),['day_get']);
});

test('three food frontends expose declared write scope while Gemini never receives tools or handlers',async t=>{
  const f=fixture(),app=await startTestServer({domainTools:f});t.after(()=>app.close());
  for(const frontend of ['claude_web','chatgpt_web','antigravity','gemini_web']) {
    app.oauth.verifyAccessToken=()=>({ok:true,frontend,familyId:frontend,scopes:['i.read','i.write']});
    const session=await initSession(app.base,'synthetic');
    const result=await mcpPost(app.base,'synthetic',{jsonrpc:'2.0',id:2,method:'tools/list'},{sessionId:session.sessionId});
    const names=result.body.result.tools.map(tool=>tool.name);
    assert.equal(names.includes('food_log'),frontend!=='gemini_web');assert.equal(names.includes('food_day'),frontend!=='gemini_web');
    app.oauth.verifyAccessToken=()=>({ok:true,frontend,familyId:frontend,scopes:['i.read']});
    const readOnly=await mcpPost(app.base,'synthetic',{jsonrpc:'2.0',id:3,method:'tools/list'},{sessionId:session.sessionId});
    // Existing MCP lists tools independently of token scopes; calls enforce scopes.
    assert.equal(readOnly.body.result.tools.some(tool=>tool.name==='food_log'),frontend!=='gemini_web');
    const denied=await mcpPost(app.base,'synthetic',{jsonrpc:'2.0',id:4,method:'tools/call',params:{name:'food_log',arguments:{}}},{sessionId:session.sessionId});
    assert.ok(denied.body.error||denied.body.result?.isError);
  }
  assert.equal(f.calls.length,0);
  assert.equal(FOOD_TOOLS.find(tool=>tool.name==='food_log').requiredScope,'i.write');
});

test('food HTTP client accepts only its added domain and uses the independent bearer credential',async()=>{
  const calls=[];const client=createDomainClient({coreUrl:'http://127.0.0.1:1',coreInstanceId:'synthetic-core',token:'synthetic-food',fetchImpl:async(url,options)=>{
    calls.push({url:String(url),options});return {status:200,json:async()=>({records:[]})};
  }});
  await client.snapshot('food_entries',{limit:100});
  assert.match(calls[0].url,/\/food_entries\/snapshot/);assert.equal(calls[0].options.headers.authorization,'Bearer synthetic-food');
  await assert.rejects(()=>client.snapshot('unregistered',{}),/domain_forbidden/);
});

test('food recovery never reconstructs an existing operation after losing generated timestamps',async()=>{
  const f=fixture();f.client.operation=async()=>({http_status:200,found:true});
  await assert.rejects(()=>f.handlers.food_log({action:'add',op_id:randomUUID(),id:randomUUID(),entry:entry()}),/food_retry_state_unavailable/);
  assert.equal(f.calls.length,0);
});
