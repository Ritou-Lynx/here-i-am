import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { randomUUID } from 'node:crypto';
import { DOMAIN_SCHEMA_SQL } from './domain_schema.mjs';
import { DomainStore } from './domain_store.mjs';
import { createPersonalDataHooks, registerPersonalDataDomains } from './personal_data_domains.mjs';
import { createPhoneUiAuthorizationVerifier, signPhoneUiIntent, phoneUiSigningPayload } from './phone_ui_authorization.mjs';

const coreId = 'core-phone-ui-synthetic';
const now = '2026-10-07T00:00:00.000Z';
const secret = Buffer.from(Array.from({length:32}, (_, n) => n)).toString('base64url');
const binding = {core_instance_id:coreId,principal_id:'phone-ui',credential_generation:1,installation_id:'phone-install'};
const grant = {principal_id:binding.principal_id,credential_generation:1,installation_id:binding.installation_id,
  key_id:'synthetic-key',secret,domains:['captures','plan_items']};
const principal = {...binding,generation:1,device_id:'phone-device',trusted_interactive:true,actors:['user_direct']};
function intent(overrides = {}) {
  return {domain_protocol_version:1,core_instance_id:coreId,schema_version:1,op_id:randomUUID(),id:randomUUID(),
    kind:'create',actor:'user_direct',base_revision:0,created_at:now,expires_at:'2026-12-06T00:00:00.000Z',
    data:{text:'合成点击发送 🌧️',source:'phone_quick',recorded_at:now},
    provenance:{source:'phone_quick',source_refs:[],import_batch_id:null},...overrides};
}
const sign = (request, domain = 'captures') => ({...request,
  authorization_ref:signPhoneUiIntent({domain,binding,intent:request,keyId:grant.key_id,secret})});
const verify = createPhoneUiAuthorizationVerifier({coreInstanceId:coreId,grants:[grant]});
const check = (request, overrides = {}) => verify({principal,request,domain:'captures',authorizationRef:request.authorization_ref,...overrides});

test('full intent signature matches a fixed cross-language vector', () => {
  const request=intent({op_id:'00000000-0000-4000-8000-000000000001',id:'00000000-0000-4000-8000-000000000002'});
  const signed=sign(request);
  assert.equal(check(signed),true);
  assert.equal(sign({...signed}).authorization_ref,signed.authorization_ref);
  assert.equal(Object.hasOwn(phoneUiSigningPayload('captures',binding,signed).intent,'authorization_ref'),false);
  // Fixed digest is also asserted by the Dart client fixture.
  assert.equal(signed.authorization_ref,'uia1.synthetic-key.jpAvn1guJxBC_3-rXcOIb1YwMecIm3twHYiGh0t1Cmo');
});

test('every operation identity, base, payload and time change invalidates prior authority', () => {
  const signed=sign(intent());
  const changes=[{op_id:randomUUID()},{id:randomUUID()},{base_revision:1},{created_at:'2026-10-07T00:00:01.000Z'},
    {expires_at:'2026-12-05T00:00:00.000Z'},{data:{...signed.data,text:'篡改'}},
    {provenance:{...signed.provenance,source_refs:['unapproved']}},{epoch:null},
    {actor:'user_via_agent'},{core_instance_id:'other-core'}];
  for(const change of changes)assert.equal(check({...signed,...change}),false,JSON.stringify(change));
  assert.equal(check(signed,{domain:'plan_items'}),false);
});

test('current principal, generation, installation and trusted UI binding are mandatory', () => {
  const signed=sign(intent());
  for(const change of [{principal_id:'other'},{generation:2},{installation_id:'other'},{trusted_interactive:false},{actors:['agent_inferred']}]) {
    assert.equal(check(signed,{principal:{...principal,...change}}),false);
  }
  for(const ref of ['ui:random','synthetic:'+signed.op_id,signed.authorization_ref+'=',signed.authorization_ref.replace('synthetic-key','unknown')]) {
    assert.equal(check(signed,{authorizationRef:ref}),false);
  }
});

test('phone signer cannot authorize inferred tools, web captures or arbitrary plan writes', () => {
  for(const request of [intent({actor:'user_via_agent'}),intent({data:{text:'x',source:'claude_web',recorded_at:now}}),
    intent({kind:'merge'}),intent({kind:'status',patch:{status:'完成',title:'extra'}})]) {
    assert.throws(()=>sign(request),/invalid_phone_ui_action/);
  }
  const status={domain_protocol_version:1,core_instance_id:coreId,schema_version:1,op_id:randomUUID(),id:randomUUID(),
    kind:'status',actor:'user_direct',base_revision:3,created_at:now,expires_at:'2026-12-06T00:00:00.000Z',patch:{status:'放弃'}};
  assert.equal(check(sign(status,'plan_items'),{domain:'plan_items'}),true);
});

test('malformed or duplicated owner key configuration is rejected without leaking key material', () => {
  for(const grants of [[{...grant,secret:'short'}],[grant,grant],[{...grant,domains:['chat']}],
    [{...grant,credential_generation:0}],[{...grant,domains:['captures','captures']}],[{...grant,unexpected:true}]]) {
    assert.throws(()=>createPhoneUiAuthorizationVerifier({coreInstanceId:coreId,grants}),error=>
      /^invalid_phone_ui_(configuration|key)$/.test(error.message)&&!error.message.includes(secret));
  }
});

function fixture(t) {
  const db=new DatabaseSync(':memory:');
  db.exec("CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT);INSERT INTO core_metadata VALUES('schema_version','6'),('node_id','core-phone-ui-synthetic'),('cursor_secret','synthetic-only-key');");
  db.exec(DOMAIN_SCHEMA_SQL);
  const store=new DomainStore(db,{nodeId:coreId,cursorSecret:'synthetic-only-key',clock:()=>Date.parse(now),verifyAuthorization:verify,
    domainHooks:createPersonalDataHooks({captureSourcesByPrincipal:{'phone-ui':['phone_quick']}})});
  registerPersonalDataDomains(store,{mode:'authoritative'});
  const config={principal_id:'phone-ui',device_id:'phone-device',installation_id:'phone-install',
    scopes:['captures:read','captures:create','captures:patch','captures:delete'],actors:['user_direct'],trusted_interactive:true};
  const issued=store.configurePrincipal(config),authenticated=store.authenticate(issued.token);
  t.after(()=>db.close());
  return {db,store,config,authenticated};
}

test('real Core domain acceptance has one durable receipt, rejects forged reuse, and retains no signing secret', t => {
  const f=fixture(t),request=sign(intent());
  const result=f.store.submit(f.authenticated,'captures',request);
  assert.equal(result.status,201,JSON.stringify(result));
  const retry=f.store.submit(f.authenticated,'captures',request);
  assert.deepEqual(retry.body.receipt,result.body.receipt);
  const forged=f.store.submit(f.authenticated,'captures',{...request,op_id:randomUUID(),data:{...request.data,text:'unauthorized'}});
  assert.equal(forged.status,403);
  assert.equal(f.db.prepare('SELECT COUNT(*) n FROM domain_changes').get().n,1);
  for(const table of ['domain_records','domain_ops','domain_receipts','domain_op_payloads']) {
    assert.equal(JSON.stringify(f.db.prepare('SELECT * FROM '+table).all()).includes(secret),false);
  }
});

test('real Core still enforces scopes, expiry and current generation before accepting signed actions', t => {
  const f=fixture(t);
  const expired=sign(intent({created_at:'2026-10-01T00:00:00.000Z',expires_at:now}));
  assert.equal(f.store.submit(f.authenticated,'captures',expired).body.outcome,'expired');
  const rotated=f.store.configurePrincipal({...f.config,scopes:['captures:read']});
  assert.equal(f.store.submit(f.authenticated,'captures',sign(intent())).status,401);
  assert.equal(f.store.submit(f.store.authenticate(rotated.token),'captures',sign(intent())).status,403);
  assert.equal(f.db.prepare('SELECT COUNT(*) n FROM domain_records').get().n,0);
});
