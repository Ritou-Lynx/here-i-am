import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { DOMAIN_SCHEMA_SQL } from '../i_core/domain_schema.mjs';
import { DOMAIN_POLICY, DomainStore, canonicalJSON } from '../i_core/domain_store.mjs';
import { createPersonalDataHooks, registerPersonalDataDomains } from '../i_core/personal_data_domains.mjs';
import { createPhoneUiAuthorizationVerifier, signPhoneUiIntent } from '../i_core/phone_ui_authorization.mjs';
import { FileTrustedTransferLedger, TrustedPlanStatusBridge, createTrustedPlanCoreTransport,
  pendingDecisionForUnsignedStatus } from './trusted_status_bridge.mjs';

const coreId = 'planner-bridge-core';
const start = Date.parse('2026-10-07T02:00:00.000Z');
const secret = Buffer.from(Array.from({length:32}, (_, n) => 255 - n)).toString('base64url');
const binding = {core_instance_id:coreId,principal_id:'phone-ui',credential_generation:1,installation_id:'phone-install'};
const grant = {...binding,key_id:'planner-key',secret,domains:['captures','plan_items']};
delete grant.core_instance_id;

const item = () => ({title:'Synthetic approved task',level:'行动',area:'生活',parent_id:null,depends_on:[],status:'待办',
  replaced_by:null,block_kind:null,blocks:null,scheduled_at:null,planned_date:null,due_date:null,completed_at:null,
  energy:null,defer_count:0,source:'手打',source_url:null,note:'',remind_at:null});

function fixture(t) {
  let now = start;
  const db = new DatabaseSync(':memory:');
  db.exec("CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT);INSERT INTO core_metadata VALUES('schema_version','6'),('node_id','planner-bridge-core'),('cursor_secret','synthetic-bridge-secret');");
  db.exec(DOMAIN_SCHEMA_SQL);
  const verify = createPhoneUiAuthorizationVerifier({coreInstanceId:coreId,grants:[grant]});
  const store = new DomainStore(db,{nodeId:coreId,cursorSecret:'synthetic-bridge-secret',clock:()=>now,
    verifyAuthorization:verify,domainHooks:createPersonalDataHooks({captureSourcesByPrincipal:{'phone-ui':['phone_quick']},
      plannerPrincipalIds:['planner-maker']})});
  registerPersonalDataDomains(store,{mode:'authoritative'});
  const phoneIssued = store.configurePrincipal({principal_id:'phone-ui',device_id:'phone-device',installation_id:'phone-install',
    scopes:['captures:read','captures:create','plan_items:read','plan_items:status'],actors:['user_direct'],trusted_interactive:true});
  const agentIssued = store.configurePrincipal({principal_id:'planner-maker',device_id:'planner-device',installation_id:'planner-install',
    scopes:['plan_items:read','plan_items:create'],actors:['agent_inferred'],trusted_interactive:false});
  const phone = store.authenticate(phoneIssued.token), agent = store.authenticate(agentIssued.token);
  const makeBase = (kind, id, baseRevision, actor) => ({domain_protocol_version:1,core_instance_id:coreId,schema_version:1,
    op_id:randomUUID(),id,kind,base_revision:baseRevision,created_at:new Date(now).toISOString(),
    expires_at:new Date(now + DOMAIN_POLICY.intentTtl).toISOString(),actor});
  const captureId = randomUUID();
  const captureIntent = makeBase('create',captureId,0,'user_direct');
  Object.assign(captureIntent,{data:{text:'SYNTHETIC DOT RECEIPT',source:'phone_quick',recorded_at:new Date(now).toISOString()},
    provenance:{source:'phone_quick',source_refs:[],import_batch_id:null}});
  captureIntent.authorization_ref = signPhoneUiIntent({domain:'captures',binding,intent:captureIntent,keyId:grant.key_id,secret});
  const captureResult=store.submit(phone,'captures',captureIntent);
  if(captureResult.status!==201)throw new Error(JSON.stringify(captureResult));
  const itemId = randomUUID(), createItem = makeBase('create',itemId,0,'agent_inferred');
  Object.assign(createItem,{data:item(),provenance:{source:'codex',source_refs:[],import_batch_id:null}});
  assert.equal(store.submit(agent,'plan_items',createItem).status,201);
  const statusIntent = (overrides={}) => {
    const intent = {...makeBase('status',itemId,1,'user_direct'),patch:{status:'完成'},...overrides};
    intent.authorization_ref = signPhoneUiIntent({domain:'plan_items',binding,intent,keyId:grant.key_id,secret});
    return intent;
  };
  const envelope = (intent=statusIntent(), overrides={}) => ({schema_version:1,transfer_id:intent.op_id,
    source:{capture_id:captureId,capture_revision:1},binding:{...binding},intent,...overrides});
  const rootPromise = mkdtemp(join(tmpdir(),'trusted-plan-bridge-'));
  let submits = 0, mutateSubmitted = false;
  const transport = createTrustedPlanCoreTransport({
    getCapture: async id => store.getRecord(phone,'captures',id,coreId).body.record,
    getOperation: async opId => {
      const result=store.getOperation(phone,'plan_items',opId,coreId);
      if(result.status===404 && result.body?.error?.code==='op_not_found')return {state:'not_found'};
      if(result.status!==200)throw new Error('lookup_failed');
      return {state:'found',response:result};
    },
    submitOperation: async intent => {
      submits++;
      if(mutateSubmitted) intent.patch.status='放弃';
      return store.submit(phone,'plan_items',intent);
    },
  });
  const bridge = async (other={}) => new TrustedPlanStatusBridge({binding:other.binding??binding,
    transport:other.transport??transport,ledger:other.ledger??new FileTrustedTransferLedger(await rootPromise),
    clock:other.clock??(()=>now)});
  t.after(async()=>{db.close();await rm(await rootPromise,{recursive:true,force:true});});
  return {db,store,phone,agent,captureId,itemId,statusIntent,envelope,rootPromise,transport,bridge,
    setNow:value=>{now=value;},submits:()=>submits,setMutate:value=>{mutateSubmitted=value;}};
}

test('forwards one exact signed plan status intent to real Core and durably replays without a second submit', async t => {
  const f=fixture(t), intent=f.statusIntent(), transfer=f.envelope(intent), bridge=await f.bridge();
  const before=canonicalJSON(transfer.intent), first=await bridge.apply(transfer);
  assert.equal(first.status,'complete');assert.equal(first.outcome,'accepted');assert.equal(first.recovered,false);
  assert.equal(canonicalJSON(transfer.intent),before);assert.equal(f.submits(),1);
  const record=f.store.getRecord(f.phone,'plan_items',f.itemId,coreId).body.record;
  assert.equal(record.data.status,'完成');assert.equal(record.revision,2);
  const replay=await (await f.bridge()).apply(transfer);
  assert.equal(replay.recovered,true);assert.equal(replay.receipt.receipt_id,first.receipt.receipt_id);assert.equal(f.submits(),1);
  const root=await f.rootPromise;
  const files=await Promise.all(['prepared','receipt'].map(s=>readFile(join(root,`${intent.op_id}.${s}.json`),'utf8')));
  assert.equal(files.some(value=>value.includes('SYNTHETIC DOT RECEIPT')),false);
  assert.equal(files.some(value=>value.includes(secret)),false);
});

test('capture authorization cannot be transferred to plan status and Core remains the signature verifier', async t => {
  const f=fixture(t), intent=f.statusIntent();
  const captureAuth={...intent,kind:'create',base_revision:0,id:randomUUID(),
    data:{text:'SYNTHETIC',source:'phone_quick',recorded_at:new Date(start).toISOString()},
    provenance:{source:'phone_quick',source_refs:[],import_batch_id:null}};
  delete captureAuth.patch;
  intent.authorization_ref=signPhoneUiIntent({domain:'captures',binding,intent:captureAuth,keyId:grant.key_id,secret});
  await assert.rejects((await f.bridge()).apply(f.envelope(intent)),error=>error?.code==='invalid_core_status_result');
  assert.equal(f.store.getRecord(f.phone,'plan_items',f.itemId,coreId).body.record.data.status,'待办');
});

test('strict envelope, revision, binding and expiry checks fail closed before status mutation', async t => {
  const cases=[
    f=>({...f.envelope(),extra:true}),
    f=>({...f.envelope(),source:{capture_id:f.captureId,capture_revision:2}}),
    f=>({...f.envelope(),binding:{...binding,credential_generation:2}}),
    f=>{const e=f.envelope();e.intent={...e.intent,patch:{status:'完成',title:'injected'}};return e;},
  ];
  for(const make of cases){const f=fixture(t);await assert.rejects((await f.bridge()).apply(make(f)),error=>
    ['invalid_status_transfer','source_capture_changed','transfer_binding_changed','invalid_plan_status_intent'].includes(error?.code));}
  const f=fixture(t), intent=f.statusIntent({created_at:new Date(start-DOMAIN_POLICY.intentTtl).toISOString(),expires_at:new Date(start-1).toISOString()});
  await assert.rejects((await f.bridge()).apply(f.envelope(intent)),error=>error?.code==='intent_expired');
  assert.equal(f.submits(),0);
});

test('lost submit response is recovered by lookup of the same op even after expiry', async t => {
  const f=fixture(t), intent=f.statusIntent({expires_at:new Date(start+1000).toISOString()}), transfer=f.envelope(intent);
  let lose=true;
  const transport=createTrustedPlanCoreTransport({
    getCapture:id=>f.transport.getCapture(id),getOperation:id=>f.transport.getOperation(id),
    submitOperation:async value=>{const result=await f.transport.submitOperation(value);if(lose){lose=false;throw new Error('lost');}return result;},
  });
  const bridge=await f.bridge({transport});
  await assert.rejects(bridge.apply(transfer),error=>error?.code==='core_submit_unknown'&&error.retryable===true);
  f.setNow(start+2000);
  const recovered=await (await f.bridge({transport})).apply(transfer);
  assert.equal(recovered.recovered,true);assert.equal(recovered.outcome,'accepted');
  assert.equal(f.store.getRecord(f.phone,'plan_items',f.itemId,coreId).body.record.data.status,'完成');
});

test('expired prepared transfer without a Core receipt remains unresolved and never gets a new op', async t => {
  const f=fixture(t), intent=f.statusIntent({expires_at:new Date(start+1000).toISOString()}), transfer=f.envelope(intent);
  const ledger=new FileTrustedTransferLedger(await f.rootPromise);
  f.setNow(start+2000);
  await assert.rejects((await f.bridge({ledger})).apply(transfer),error=>error?.code==='intent_expired');
  assert.equal(f.submits(),0);
  const prepared=JSON.parse(await readFile(join(await f.rootPromise,`${intent.op_id}.prepared.json`),'utf8'));
  assert.equal(prepared.op_id,intent.op_id);
});

test('lookup latency cannot race expiry into submit and an invisible capture stays pending', async t => {
  const f=fixture(t), intent=f.statusIntent({expires_at:new Date(start+1000).toISOString()}), transfer=f.envelope(intent);
  const slow=createTrustedPlanCoreTransport({getCapture:id=>f.transport.getCapture(id),
    getOperation:async id=>{f.setNow(start+2000);return f.transport.getOperation(id);},
    submitOperation:value=>f.transport.submitOperation(value)});
  await assert.rejects((await f.bridge({transport:slow})).apply(transfer),error=>error?.code==='intent_expired');
  assert.equal(f.submits(),0);
  const invisible=createTrustedPlanCoreTransport({getCapture:async()=>{throw new Error('not visible');},
    getOperation:id=>f.transport.getOperation(id),submitOperation:value=>f.transport.submitOperation(value)});
  await assert.rejects((await f.bridge({transport:invisible})).apply(f.envelope()),error=>
    error?.code==='source_capture_unknown'&&error.retryable===true);
  assert.equal(f.store.getRecord(f.phone,'plan_items',f.itemId,coreId).body.record.data.status,'待办');
});

test('a locally corrupted completed receipt is never trusted over current Core lookup', async t => {
  const f=fixture(t), intent=f.statusIntent(), transfer=f.envelope(intent), bridge=await f.bridge();
  await bridge.apply(transfer);
  const path=join(await f.rootPromise,`${intent.op_id}.receipt.json`), cached=JSON.parse(await readFile(path,'utf8'));
  cached.receipt.targets=[{id:f.itemId,revision:999}];
  await writeFile(path,JSON.stringify(cached),'utf8');
  await assert.rejects((await f.bridge()).apply(transfer),error=>error?.code==='transfer_receipt_conflict');
});

test('a cached receipt with the wrong ledger schema or op id fails closed before recovery', async t => {
  for (const corrupt of [
    cached => { cached.schema_version=2; },
    cached => { cached.op_id=randomUUID(); },
  ]) {
    const f=fixture(t), intent=f.statusIntent(), transfer=f.envelope(intent), bridge=await f.bridge();
    await bridge.apply(transfer);
    const path=join(await f.rootPromise,`${intent.op_id}.receipt.json`);
    const cached=JSON.parse(await readFile(path,'utf8'));
    corrupt(cached);
    await writeFile(path,JSON.stringify(cached),'utf8');
    await assert.rejects((await f.bridge()).apply(transfer),error=>error?.code==='transfer_idempotency_conflict');
  }
});

test('ledger readers see only a complete atomic publication and an existing receipt is never overwritten', async t => {
  const f=fixture(t), intent=f.statusIntent(), envelope=f.envelope(intent), root=await f.rootPromise;
  const ledger=new FileTrustedTransferLedger(root), envelopeDigest='a'.repeat(64);
  assert.equal(await ledger.prepare(envelope,envelopeDigest),null);
  const finalPath=join(root,`${intent.op_id}.receipt.json`);
  const abandonedPath=`${finalPath}.tmp-crash-residue`;
  await writeFile(abandonedPath,'abandoned-by-synthetic-crash','utf8');
  const receipt={receipt_id:'atomic-synthetic',padding:'x'.repeat(8*1024*1024)};
  let settled=false;
  const publishing=ledger.complete(envelope,envelopeDigest,{receipt}).finally(()=>{settled=true;});
  while(!settled) {
    try {
      const visible=JSON.parse(await readFile(finalPath,'utf8'));
      assert.equal(visible.schema_version,1);
      assert.equal(visible.op_id,intent.op_id);
      assert.deepEqual(visible.receipt,receipt);
    } catch(error) {
      if(error?.code!=='ENOENT')throw error;
    }
    await new Promise(resolve=>setImmediate(resolve));
  }
  await publishing;
  const winner=await readFile(finalPath,'utf8');
  assert.deepEqual(JSON.parse(winner).receipt,receipt);
  await assert.rejects(ledger.complete(envelope,envelopeDigest,{receipt:{receipt_id:'replacement'}}),
    error=>error?.code==='transfer_receipt_conflict');
  assert.equal(await readFile(finalPath,'utf8'),winner);
  assert.equal(await readFile(abandonedPath,'utf8'),'abandoned-by-synthetic-crash');
  assert.deepEqual((await readdir(root)).filter(name=>name.startsWith(`${intent.op_id}.receipt.json.tmp-`)),
    [`${intent.op_id}.receipt.json.tmp-crash-residue`]);
});

test('a non-finite or backwards clock after Core lookup cannot reach submit', async t => {
  for (const unsafeNow of [Number.NaN, start-1]) {
    const f=fixture(t), intent=f.statusIntent(), transfer=f.envelope(intent);
    let calls=0;
    const clock=()=>++calls===1?start:unsafeNow;
    await assert.rejects((await f.bridge({clock})).apply(transfer),error=>error?.code==='bridge_clock_invalid');
    assert.equal(f.submits(),0);
  }
});

test('same op cannot be rebound to another capture and concurrent ledgers use exclusive immutable claims', async t => {
  const f=fixture(t), intent=f.statusIntent(), transfer=f.envelope(intent);
  const [a,b]=await Promise.all([(await f.bridge()).apply(transfer),(await f.bridge()).apply(transfer)]);
  assert.equal(a.receipt.receipt_id,b.receipt.receipt_id);
  const changed={...transfer,source:{capture_id:randomUUID(),capture_revision:1}};
  const visible=createTrustedPlanCoreTransport({getCapture:async id=>({id,revision:1,core_instance_id:coreId,deleted_at:null}),
    getOperation:id=>f.transport.getOperation(id),submitOperation:value=>f.transport.submitOperation(value)});
  await assert.rejects((await f.bridge({transport:visible})).apply(changed),error=>error?.code==='transfer_idempotency_conflict');
  const last=intent.authorization_ref.at(-1), changedRef={...transfer,intent:{...intent,
    authorization_ref:intent.authorization_ref.slice(0,-1)+(last==='A'?'B':'A')}};
  await assert.rejects((await f.bridge()).apply(changedRef),error=>error?.code==='transfer_idempotency_conflict');
});

test('callback cannot mutate the frozen signed intent and arbitrary callbacks are not accepted as transport', async t => {
  const f=fixture(t);f.setMutate(true);
  await assert.rejects((await f.bridge()).apply(f.envelope()),error=>error?.code==='core_submit_unknown');
  assert.throws(()=>new TrustedPlanStatusBridge({binding,transport:{getCapture(){},getOperation(){},submitOperation(){}},
    ledger:new FileTrustedTransferLedger('synthetic')}),/untrusted_core_transport/);
});

test('unsigned dot outcome produces only a schema-valid pending decision', () => {
  assert.deepEqual(pendingDecisionForUnsignedStatus({itemId:'plan:item-1'}),{item_id:'plan:item-1',
    reason:'缺少受信计划状态授权',suggestion:'请在受信手机界面确认“完成”或“放弃”；确认前保持原状态。'});
});
