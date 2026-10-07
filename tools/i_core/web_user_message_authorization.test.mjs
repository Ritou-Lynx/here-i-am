import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {DomainStore} from './domain_store.mjs';
import {DOMAIN_SCHEMA_SQL} from './domain_schema.mjs';
import {createPersonalDataHooks,registerPersonalDataDomains} from './personal_data_domains.mjs';
import {createWebUserMessageAuthorizationVerifier} from './web_user_message_authorization.mjs';
import {createCoreRemember,createDomainTools} from '../i_remote_mcp/domain_tools.mjs';
import {createToolHandlers,handleRpcMessage,listTools} from '../i_remote_mcp/mcp.mjs';

const now='2026-10-07T08:00:00.000Z';
const sync=name=>`claude_web:t_${name.padEnd(8,'x')}:1`;
function fixture(t) {
  const db=new DatabaseSync(':memory:');t.after(()=>db.close());
  db.exec("CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT);INSERT INTO core_metadata VALUES('schema_version','6'),('node_id','core'),('cursor_secret','secret');");
  db.exec('CREATE TABLE chat_messages(sync_id TEXT PRIMARY KEY,origin_device_id TEXT,character_id TEXT,sender TEXT,message_type TEXT);');
  db.exec(DOMAIN_SCHEMA_SQL);
  const binding={principal_id:'web',installation_id:'install',origin_device_id:'frontend:claude_web',character_id:'character'};
  const verify=createWebUserMessageAuthorizationVerifier({coreInstanceId:'core',getDatabase:()=>db,principals:[binding]});
  const hooks=createPersonalDataHooks({captureSourcesByPrincipal:{web:['claude_web'],other:['phone_quick']},webPrincipalIds:['web'],verifyWebAuthorization:verify});
  const store=new DomainStore(db,{nodeId:'core',cursorSecret:'secret',clock:()=>Date.parse(now),domainHooks:hooks,verifyAuthorization:verify});
  registerPersonalDataDomains(store,{mode:'authoritative'});
  const scopes=['captures:read','captures:create','captures:patch','captures:delete'];
  const issued=store.configurePrincipal({principal_id:'web',device_id:binding.origin_device_id,installation_id:'install',scopes,actors:['user_via_agent','agent_inferred'],origin_device_only:true});
  const principal=store.authenticate(issued.token);
  const message=(name='trigger',extra={})=>{const id=name.startsWith('claude_web:')?name:sync(name),row={...binding,sender:'user',message_type:'chat',...extra};db.prepare('INSERT INTO chat_messages VALUES(?,?,?,?,?)').run(id,row.origin_device_id,row.character_id,row.sender,row.message_type);return id;};
  const intent=(extra={})=>({domain_protocol_version:1,core_instance_id:'core',schema_version:1,op_id:randomUUID(),id:randomUUID(),kind:'create',base_revision:0,actor:'user_via_agent',created_at:now,expires_at:'2026-10-07T09:00:00.000Z',data:{text:'synthetic',source:'claude_web',recorded_at:now},provenance:{source:'claude_web',source_refs:[],import_batch_id:null},trigger_thread_id:extra.authorization_ref?.split(':')[1]??'t_triggerx',trigger_sync_id:extra.authorization_ref,...extra});
  const submit=raw=>store.submit(principal,'captures',raw);
  return {db,store,verify,message,intent,principal,submit,scopes};
}
test('only exact configured Core user chat anchors grant user_via_agent; missing/wrong anchors downgrade',t=>{
  const f=fixture(t);f.message();
  for(const [sync,extra] of [['assistant',{sender:'companion'}],['other-origin',{origin_device_id:'phone'}],['other-character',{character_id:'elsewhere'}],['non-chat',{message_type:'system'}]])f.message(sync,extra);
  for(const ref of ['trigger','assistant','other-origin','other-character','non-chat','missing',undefined]){
    const r=f.submit(f.intent(ref?{authorization_ref:sync(ref)}:{}));
    assert.equal(r.status,201,JSON.stringify(r));
    assert.equal(r.body.record.field_meta.text.actor,ref==='trigger'?'user_via_agent':'agent_inferred');
  }
  const request=f.intent({authorization_ref:sync('trigger')}),context={principal:{...f.principal,device_id:'frontend:claude_web'},request,domain:'captures',authorizationRef:sync('trigger')};
  assert.equal(f.verify(context),true);
  assert.equal(f.verify({...context,principal:{...context.principal,installation_id:'new-install'}}),false);
  assert.equal(f.verify({...context,request:{...request,core_instance_id:'other-core'}}),false);
});
test('identical retries preserve inferred authority after late chat arrival and preserve anchored receipts after anchor loss',t=>{
  const f=fixture(t),request=f.intent({authorization_ref:sync('late')}),first=f.submit(request);
  assert.equal(first.status,201);f.message('late');
  const retry=f.submit(request);assert.equal(retry.body.outcome,'duplicate');
  assert.equal(retry.body.receipt.receipt_id,first.body.receipt.receipt_id);
  assert.equal(f.store.load('production','captures',request.id).field_meta.text.actor,'agent_inferred');
  assert.equal(f.submit({...request,data:{...request.data,text:'changed'}}).status,409);
  const anchored=f.intent({authorization_ref:sync('late')}),accepted=f.submit(anchored);assert.equal(accepted.status,201);
  f.db.prepare('DELETE FROM chat_messages').run();
  assert.equal(f.submit(anchored).body.receipt.receipt_id,accepted.body.receipt.receipt_id);
  f.store.revokePrincipal('web');assert.equal(f.submit(request).status,401);
});
test('inferred fallback cannot overwrite user fields; web deletion protects user edits and other sources',t=>{
  const f=fixture(t);f.message();
  const original=f.intent({authorization_ref:sync('trigger')});assert.equal(f.submit(original).status,201);
  const patch={...f.intent(),id:original.id,kind:'patch',base_revision:1,patch:{text:'inferred change'}};delete patch.data;delete patch.provenance;
  assert.equal(f.submit(patch).body.reason,'user_locked');
  assert.equal(f.submit({...patch,op_id:randomUUID(),authorization_ref:sync('trigger'),trigger_sync_id:sync('trigger')}).status,201);
  const del={...patch,op_id:randomUUID(),kind:'delete',base_revision:2,permanent:true};delete del.patch;
  assert.equal(f.submit(del).status,403);
  const untouched=f.intent();assert.equal(f.submit(untouched).status,201);
  const deleteUntouched={...del,id:untouched.id,op_id:randomUUID(),base_revision:1};
  assert.equal(f.submit(deleteUntouched).status,201);
  assert.equal(f.submit(deleteUntouched).body.outcome,'duplicate');
  assert.equal(f.store.load('production','captures',untouched.id).body_state,'purged');
  const wrong=f.intent({data:{text:'other',source:'phone_quick',recorded_at:now},provenance:{source:'phone_quick',source_refs:[],import_batch_id:null}});
  assert.equal(f.submit(wrong).status,403);
});
test('a closed or superseded same-thread user anchor cannot authorize a new operation',t=>{
  const f=fixture(t),first=f.message();
  const acceptedRequest=f.intent({authorization_ref:first});assert.equal(f.submit(acceptedRequest).status,201);
  f.message('claude_web:t_triggerx:2',{sender:'companion'});
  const closed=f.submit(f.intent({authorization_ref:first}));assert.equal(closed.body.record.field_meta.text.actor,'agent_inferred');
  const current=f.message('claude_web:t_triggerx:3');
  assert.equal(f.submit(f.intent({authorization_ref:current})).body.record.field_meta.text.actor,'user_via_agent');
  assert.equal(f.submit(f.intent({authorization_ref:first})).body.record.field_meta.text.actor,'agent_inferred');
  assert.equal(f.submit(acceptedRequest).body.outcome,'duplicate');
  const other=f.message('separate');assert.equal(f.submit(f.intent({authorization_ref:other})).body.record.field_meta.text.actor,'user_via_agent');
});
test('both web tool adapters accept absent anchors and Core remains the authority',async t=>{
  const f=fixture(t),client={submit:async(_,intent)=>{const r=f.submit({domain_protocol_version:1,core_instance_id:'core',schema_version:1,...intent});return {http_status:r.status,...r.body};}};
  const remember=createCoreRemember({client,scopes:f.scopes}),tools=createDomainTools({client,scopes:f.scopes,surface:'web',captureSource:'claude_web'});
  const base=()=>({op_id:randomUUID(),id:randomUUID(),base_revision:0,created_at:now,expires_at:'2026-10-07T09:00:00.000Z',text:'synthetic web'});
  const a=await remember.remember({action:'add',...base()});assert.equal(a.http_status,201);assert.equal(a.record.field_meta.text.actor,'agent_inferred');
  assert.ok(!tools.tools.find(t=>t.name==='capture_add').inputSchema.required.includes('authorization_ref'));
  const b=await tools.handlers.capture_add({...base(),recorded_at:now});assert.equal(b.http_status,201);assert.equal(b.record.field_meta.text.actor,'agent_inferred');
});

test('MCP sessions bind their own conversation and cannot reuse another thread anchor or inject host context',async t=>{
  const f=fixture(t),a=f.message('thread-a'),b=f.message('thread-b'),writes=[];
  const client={submit:async(_,intent)=>{writes.push(intent);const r=f.submit({domain_protocol_version:1,core_instance_id:'core',schema_version:1,...intent});return {http_status:r.status,...r.body};},snapshot:async()=>({http_status:200,records:[]})};
  const remember=createCoreRemember({client,scopes:f.scopes});
  let chatCalls=0,chatPending=false;
  const handlers=createToolHandlers({coreRemember:remember,getReadModel:async()=>({policySummary:()=>({primaryCharacterId:'character'}),recentMessages:()=>[]}),writeback:{async chatTurn(args){chatCalls++;return {thread_id:args.thread_id,core_status:chatPending?'waiting_for_retry':'ok',recorded:{new_turns:1},excludeSyncIds:new Set(),user_message_anchor:chatPending?null:{sync_id:args.thread_id==='t_thread-a'?a:b}};}}});
  const tools=listTools({writeEnabled:true,coreRemember:true}),sessionA={},sessionB={};
  const call=(session,name,args)=>handleRpcMessage({jsonrpc:'2.0',id:1,method:'tools/call',params:{name,arguments:args}},{handlers,session,tools,scopes:['i.read','i.write']});
  const args=()=>({action:'add',op_id:randomUUID(),id:randomUUID(),base_revision:0,created_at:now,expires_at:'2026-10-07T09:00:00.000Z',text:'synthetic'});
  await call(sessionA,'i_chat_turn',{thread_id:'t_thread-a',phase:'start',turns:[{role:'user',content:'a'}]});
  await call(sessionB,'i_chat_turn',{thread_id:'t_thread-b',phase:'start',turns:[{role:'user',content:'b'}]});
  const wrong=await call(sessionB,'i_remember',{...args(),authorization_ref:a});
  assert.equal(wrong.result.structuredContent.record.field_meta.text.actor,'agent_inferred');
  const own=await call(sessionB,'i_remember',{...args(),authorization_ref:b});
  assert.equal(own.result.structuredContent.record.field_meta.text.actor,'user_via_agent');
  assert.equal(writes.at(-1).trigger_thread_id,'t_thread-b');
  const forged=await call(sessionB,'i_remember',{...args(),authorization_ref:a,trigger_thread_id:'t_thread-a'});
  assert.equal(forged.result.isError,true);
  const switched=await call(sessionB,'i_chat_turn',{thread_id:'t_thread-a',phase:'start',turns:[{role:'user',content:'a'}]});
  assert.equal(switched.result.isError,true);assert.equal(chatCalls,2);
  chatPending=true;
  await call(sessionB,'i_chat_turn',{thread_id:'t_thread-b',phase:'start',turns:[{role:'user',content:'pending new trigger'}]});
  const pending=await call(sessionB,'i_remember',{...args(),authorization_ref:b});
  assert.equal(pending.result.structuredContent.record.field_meta.text.actor,'agent_inferred');
  assert.equal(writes.at(-1).trigger_sync_id,undefined);
  assert.equal(f.submit(f.intent({trigger_thread_id:{unexpected:true}})).status,400);
});
