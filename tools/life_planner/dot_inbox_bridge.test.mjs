import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac, randomUUID, timingSafeEqual } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { canonicalJSON, DOMAIN_POLICY, DomainStore } from '../i_core/domain_store.mjs';
import { DOMAIN_SCHEMA_SQL } from '../i_core/domain_schema.mjs';
import { createPersonalDataHooks, registerPersonalDataDomains } from '../i_core/personal_data_domains.mjs';
import { createPhoneUiAuthorizationVerifier, signPhoneUiIntent } from '../i_core/phone_ui_authorization.mjs';
import { FileTrustedTransferLedger } from './trusted_status_bridge.mjs';
import { DotInboxCaptureBridge, createDotInboxProposal, createTrustedDotCoreTransport } from './dot_inbox_bridge.mjs';

const coreId='dot-bridge-core',now=Date.parse('2026-10-07T02:30:00.000Z');
const binding={core_instance_id:coreId,principal_id:'dot-ui',credential_generation:1,installation_id:'dot-install'};
const receipt=`【规划回执】2026-10-07 10:30 收工
容量：
- 明天 → 下午只有一块
决定：
- Synthetic decision → 先不定 → 无
完成：
- Synthetic task
卡住：
无
改动：
- 用户原话保持不变
捕获：
- SYNTHETIC DOT NOTE`;
const secret=Buffer.from(Array.from({length:32},(_,n)=>n*3%256));

function signingPayload(principal,request){const {authorization_ref:ignored,...intent}=request;return {protocol:'synthetic-dot-ui-v1',
  binding:{core_instance_id:coreId,principal_id:principal.principal_id,credential_generation:principal.generation,
    installation_id:principal.installation_id},domain:'captures',intent};}
function signDotIntent(principal,request){return `dotv1.${createHmac('sha256',secret).update(canonicalJSON(signingPayload(principal,request))).digest('base64url')}`;}
function verifyDot({principal,request,domain,authorizationRef}){
  if(domain!=='captures'||principal.principal_id!=='dot-ui'||principal.generation!==1||principal.installation_id!=='dot-install'
    ||request.actor!=='user_direct'||request.data?.source!=='dot'||request.provenance?.source!=='dot')return false;
  const match=/^dotv1\.([A-Za-z0-9_-]{43})$/.exec(authorizationRef??'');if(!match)return false;
  const expected=createHmac('sha256',secret).update(canonicalJSON(signingPayload(principal,request))).digest();
  const supplied=Buffer.from(match[1],'base64url');return supplied.length===expected.length
    && supplied.toString('base64url')===match[1]&&timingSafeEqual(supplied,expected);
}

function fixture(t){
  const db=new DatabaseSync(':memory:');
  db.exec("CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT);INSERT INTO core_metadata VALUES('schema_version','6'),('node_id','dot-bridge-core'),('cursor_secret','synthetic-dot-secret');");
  db.exec(DOMAIN_SCHEMA_SQL);
  const store=new DomainStore(db,{nodeId:coreId,cursorSecret:'synthetic-dot-secret',clock:()=>now,verifyAuthorization:verifyDot,
    domainHooks:createPersonalDataHooks({captureSourcesByPrincipal:{'dot-ui':['dot']}})});
  registerPersonalDataDomains(store,{mode:'authoritative'});
  const issued=store.configurePrincipal({principal_id:'dot-ui',device_id:'dot-device',installation_id:'dot-install',
    scopes:['captures:read','captures:create'],actors:['user_direct'],trusted_interactive:true});
  const principal=store.authenticate(issued.token),proposal=createDotInboxProposal({receiptName:'2026-10-07-1030.md',text:receipt});
  const intent={domain_protocol_version:1,core_instance_id:coreId,schema_version:1,op_id:randomUUID(),id:randomUUID(),kind:'create',
    base_revision:0,created_at:new Date(now).toISOString(),expires_at:new Date(now+DOMAIN_POLICY.intentTtl).toISOString(),
    actor:'user_direct',data:{...proposal.capture},provenance:{source:'dot',source_refs:[proposal.proposal_id],import_batch_id:null}};
  intent.authorization_ref=signDotIntent(principal,intent);
  const transfer={schema_version:1,transfer_id:intent.op_id,proposal,binding:{...binding},intent};
  const rootPromise=mkdtemp(join(tmpdir(),'dot-inbox-bridge-'));
  let submits=0;
  const transport=createTrustedDotCoreTransport({
    getOperation:async opId=>{const result=store.getOperation(principal,'captures',opId,coreId);
      if(result.status===404&&result.body?.error?.code==='op_not_found')return {state:'not_found'};
      if(result.status!==200)throw new Error('lookup_failed');return {state:'found',response:result};},
    submitOperation:async value=>{submits++;return store.submit(principal,'captures',value);},
  });
  const bridge=async()=>new DotInboxCaptureBridge({binding,transport,ledger:new FileTrustedTransferLedger(await rootPromise),clock:()=>now});
  t.after(async()=>{db.close();await rm(await rootPromise,{recursive:true,force:true});});
  return {db,store,principal,proposal,intent,transfer,transport,bridge,submits:()=>submits};
}

test('strict parser preserves the complete receipt as an approval-required dot proposal only',()=>{
  const proposal=createDotInboxProposal({receiptName:'2026-10-07-1030.md',text:receipt});
  assert.equal(proposal.capture.text,receipt);assert.equal(proposal.capture.source,'dot');
  assert.equal(proposal.capture.recorded_at,'2026-10-07T02:30:00.000Z');assert.equal(proposal.status,'approval_required');
  assert.match(proposal.proposal_id,/^dot:[a-f0-9]{64}$/);assert.equal(Object.hasOwn(proposal,'authorization_ref'),false);
  assert.equal(Object.hasOwn(proposal,'op_id'),false);
});

test('filename/header mismatch, malformed sections, truncation candidates and oversized receipts are rejected',()=>{
  const cases=[{receiptName:'2026-10-07-1031.md',text:receipt},{receiptName:'2026-10-07-1030.md',text:receipt.replace('完成：','完成:')},
    {receiptName:'2026-10-07-1030.md',text:receipt+'\n额外：\n无'},
    {receiptName:'2026-10-07-1030.md',text:receipt.replace('- SYNTHETIC DOT NOTE','')},
    {receiptName:'2026-10-07-1030.md',text:receipt+'x'.repeat(16001)}];
  for(const value of cases)assert.throws(()=>createDotInboxProposal(value));
});

test('a separately signed exact dot intent is accepted by real DomainStore and replay stays one receipt',async t=>{
  const f=fixture(t),bridge=await f.bridge(),first=await bridge.apply(f.transfer);
  assert.equal(first.outcome,'accepted');assert.equal(first.recovered,false);assert.equal(f.submits(),1);
  const record=f.store.getRecord(f.principal,'captures',f.intent.id,coreId).body.record;
  assert.equal(record.data.text,receipt);assert.equal(record.data.source,'dot');
  assert.deepEqual(record.provenance.source_refs,[f.proposal.proposal_id]);
  const replay=await (await f.bridge()).apply(f.transfer);
  assert.equal(replay.recovered,true);assert.equal(replay.receipt.receipt_id,first.receipt.receipt_id);assert.equal(f.submits(),1);
});

test('proposal, binding, source and authorization changes fail closed',async t=>{
  const f=fixture(t);
  const ref=/^(dotv1)\.([A-Za-z0-9_-]{43})$/.exec(f.intent.authorization_ref);assert.ok(ref);
  const changedSignature=Buffer.from(ref[2],'base64url');changedSignature[0]^=1;
  const changedRef=`${ref[1]}.${changedSignature.toString('base64url')}`;
  assert.notEqual(changedRef,f.intent.authorization_ref);
  const changes=[{...f.transfer,proposal:{...f.proposal,receipt_digest:'0'.repeat(64)}},
    {...f.transfer,binding:{...binding,credential_generation:2}},
    {...f.transfer,intent:{...f.intent,data:{...f.intent.data,source:'phone_quick'}}},
    {...f.transfer,intent:{...f.intent,authorization_ref:changedRef}}];
  for(const value of changes)await assert.rejects((await f.bridge()).apply(value));
  assert.equal(f.db.prepare("SELECT COUNT(*) n FROM domain_records WHERE domain='captures'").get().n,0);
});

test('a non-canonical base64url padding alias never authenticates as the same HMAC',async t=>{
  const f=fixture(t),match=/^(dotv1)\.([A-Za-z0-9_-]{43})$/.exec(f.intent.authorization_ref);assert.ok(match);
  const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  const lastIndex=alphabet.indexOf(match[2].at(-1));assert.equal(lastIndex%4,0);
  const aliasSignature=match[2].slice(0,-1)+alphabet[lastIndex+1];
  assert.deepEqual(Buffer.from(aliasSignature,'base64url'),Buffer.from(match[2],'base64url'));
  const aliasRef=`${match[1]}.${aliasSignature}`;assert.notEqual(aliasRef,f.intent.authorization_ref);
  const changed={...f.transfer,intent:{...f.intent,authorization_ref:aliasRef}};
  await assert.rejects((await f.bridge()).apply(changed),error=>error?.code==='invalid_core_capture_result');
  assert.equal(f.db.prepare("SELECT COUNT(*) n FROM domain_records WHERE domain='captures'").get().n,0);
});

test('existing phone UI verifier and uia1 phone_quick proof reject dot source',()=>{
  const phoneSecret=Buffer.from(Array.from({length:32},(_,n)=>255-n)).toString('base64url');
  const phoneBinding={core_instance_id:coreId,principal_id:'phone-ui',credential_generation:1,installation_id:'phone-install'};
  const grant={principal_id:'phone-ui',credential_generation:1,installation_id:'phone-install',key_id:'phone-key',secret:phoneSecret,domains:['captures']};
  const verifier=createPhoneUiAuthorizationVerifier({coreInstanceId:coreId,grants:[grant]});
  const proposal=createDotInboxProposal({receiptName:'2026-10-07-1030.md',text:receipt});
  const phoneIntent={domain_protocol_version:1,core_instance_id:coreId,schema_version:1,op_id:randomUUID(),id:randomUUID(),kind:'create',
    base_revision:0,created_at:new Date(now).toISOString(),expires_at:new Date(now+1000).toISOString(),actor:'user_direct',
    data:{text:'PHONE',source:'phone_quick',recorded_at:new Date(now).toISOString()},provenance:{source:'phone_quick',source_refs:[],import_batch_id:null}};
  const ref=signPhoneUiIntent({domain:'captures',binding:phoneBinding,intent:phoneIntent,keyId:'phone-key',secret:phoneSecret});
  const dotIntent={...phoneIntent,data:proposal.capture,provenance:{source:'dot',source_refs:[proposal.proposal_id],import_batch_id:null},authorization_ref:ref};
  const principal={principal_id:'phone-ui',generation:1,installation_id:'phone-install',trusted_interactive:true,actors:['user_direct']};
  assert.equal(verifier({principal,request:dotIntent,domain:'captures',authorizationRef:ref}),false);
  assert.throws(()=>signPhoneUiIntent({domain:'captures',binding:phoneBinding,intent:dotIntent,keyId:'phone-key',secret:phoneSecret}),/invalid_phone_ui_action/);
});

test('untrusted callback objects cannot act as the Core transport',()=>{
  assert.throws(()=>new DotInboxCaptureBridge({binding,transport:{getOperation(){},submitOperation(){}},
    ledger:new FileTrustedTransferLedger('synthetic')}),/untrusted_core_transport/);
});
