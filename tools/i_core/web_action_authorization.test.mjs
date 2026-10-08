import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, randomUUID } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { DOMAIN_SCHEMA_SQL } from './domain_schema.mjs';
import { DomainStore } from './domain_store.mjs';
import { createPersonalDataHooks, registerPersonalDataDomains } from './personal_data_domains.mjs';
import { createWebActionChallenge, approveWebActionChallenge, createTrustedWebAuthorizationVerifier } from './web_action_authorization.mjs';

const instant = Date.parse('2026-10-07T00:00:00Z');
const binding = {core_instance_id:'synthetic-web-core',principal_id:'web',credential_generation:1,installation_id:'web-install'};
const principal = {principal_id:'web',generation:1,installation_id:'web-install',actors:['user_via_agent']};
function request() {
  return {domain_protocol_version:1,core_instance_id:binding.core_instance_id,schema_version:1,
    op_id:randomUUID(),id:randomUUID(),kind:'create',actor:'user_via_agent',base_revision:0,
    created_at:new Date(instant).toISOString(),expires_at:new Date(instant+3600000).toISOString(),
    data:{text:'synthetic approved capture',source:'claude_web',recorded_at:new Date(instant).toISOString()},
    provenance:{source:'claude_web',source_refs:[],import_batch_id:null}};
}
function fixture() {
  const keys = generateKeyPairSync('ed25519');
  const state = {now:instant,grants:[{key_id:'trusted-ui',public_key:keys.publicKey,binding,kinds:['create','patch','delete']}]};
  const verifier = createTrustedWebAuthorizationVerifier({coreInstanceId:binding.core_instance_id,getTrustedKeys:()=>state.grants,now:()=>state.now});
  function approve(r) {
    const challenge=createWebActionChallenge({domain:'captures',binding,request:r,keyId:'trusted-ui',now:state.now});
    return {...r,authorization_ref:approveWebActionChallenge({challenge,domain:'captures',binding,request:r,privateKey:keys.privateKey,now:state.now})};
  }
  const check = (r, overrides={}) => verifier({principal,request:r,domain:'captures',authorizationRef:r.authorization_ref,...overrides});
  return {keys,state,verifier,approve,check};
}

test('proposal and OAuth/chat/random identifiers confer no authority; trusted exact intent does', () => {
  const f=fixture(),r=request();
  for (const ref of ['oauth-token','human-said-yes',randomUUID(),JSON.stringify(createWebActionChallenge({domain:'captures',binding,request:r,keyId:'trusted-ui',now:instant}))]) {
    assert.equal(f.check({...r,authorization_ref:ref}),false);
  }
  assert.equal(f.check(f.approve(r)),true);
  assert.equal(createTrustedWebAuthorizationVerifier({coreInstanceId:binding.core_instance_id})({
    principal,request:f.approve(r),domain:'captures',authorizationRef:f.approve(r).authorization_ref}),false);
});

test('signature binds complete payload, identity, base revision and operation ID', () => {
  const f=fixture(),r=f.approve(request());
  for (const patch of [{op_id:randomUUID()},{id:randomUUID()},{base_revision:2},{kind:'delete'},
    {data:{...r.data,text:'changed'}},{provenance:{...r.provenance,source_refs:['unreviewed']}},
    {created_at:new Date(instant+1).toISOString()},{expires_at:new Date(instant+9999).toISOString()},
    {actor:'user_direct'},{core_instance_id:'another'},{epoch:null}]) assert.equal(f.check({...r,...patch}),false);
  assert.equal(f.check(r,{domain:'plan_items'}),false);
  for (const patch of [{generation:2},{principal_id:'other'},{installation_id:'other'},{actors:['agent_inferred']}]) {
    assert.equal(f.check(r,{principal:{...principal,...patch}}),false);
  }
});

test('approval requires matching rendered proposal, bounded validity and Ed25519 private key', () => {
  const f=fixture(),r=request(),challenge=createWebActionChallenge({domain:'captures',binding,request:r,keyId:'trusted-ui',now:instant});
  assert.throws(()=>approveWebActionChallenge({challenge,domain:'captures',binding,request:{...r,data:{...r.data,text:'different'}},privateKey:f.keys.privateKey,now:instant}),/invalid_web_action/);
  assert.throws(()=>createWebActionChallenge({domain:'captures',binding,request:r,keyId:'trusted-ui',now:instant,validityMs:300001}),/invalid_web_action/);
  assert.throws(()=>approveWebActionChallenge({challenge,domain:'captures',binding,request:r,privateKey:f.keys.publicKey,now:instant}),/invalid_web_signing_key/);
  assert.throws(()=>createWebActionChallenge({domain:'captures',binding,request:{...r,actor:'agent_inferred'},keyId:'trusted-ui',now:instant}),/invalid_web_action/);
});

test('expiry, future timestamps, key revocation, replacement and action narrowing deny outstanding proofs', () => {
  const f=fixture(),r=f.approve(request()),original=f.state.grants;
  f.state.now=instant-1;assert.equal(f.check(r),false);
  f.state.now=instant+300000;assert.equal(f.check(r),false);
  f.state.now=instant;
  f.state.grants=[];assert.equal(f.check(r),false);
  f.state.grants=[{...original[0],public_key:generateKeyPairSync('ed25519').publicKey}];assert.equal(f.check(r),false);
  f.state.grants=[{...original[0],kinds:['delete']}];assert.equal(f.check(r),false);
  f.state.grants=[original[0],original[0]];assert.equal(f.check(r),false);
  f.state.grants=Promise.resolve(original);assert.equal(f.check(r),false);
  f.state.grants=original;assert.equal(f.check(r),true);
});

test('malformed proofs and configuration fail closed without propagating input or key errors', () => {
  const f=fixture(),r=f.approve(request());
  for(const ref of [r.authorization_ref+'=',r.authorization_ref.replace('wua1.','wua1x'), 'wua1.e30.'+'a'.repeat(86),'x'.repeat(4097)]) {
    assert.equal(f.check({...r,authorization_ref:ref}),false);
  }
  f.state.grants=[{...f.state.grants[0],public_key:'sensitive-invalid-material'}];assert.equal(f.check(r),false);
  const v=createTrustedWebAuthorizationVerifier({coreInstanceId:binding.core_instance_id,getTrustedKeys:()=>{throw Error('private failure');},now:()=>instant});
  assert.equal(v({principal,request:r,domain:'captures',authorizationRef:r.authorization_ref}),false);
});

test('an asynchronous rejected key source denies without an unhandled rejection', async () => {
  const f=fixture(),r=f.approve(request());
  const v=createTrustedWebAuthorizationVerifier({coreInstanceId:binding.core_instance_id,
    getTrustedKeys:()=>Promise.reject(new Error('synthetic private adapter error')),now:()=>instant});
  assert.equal(v({principal,request:r,domain:'captures',authorizationRef:r.authorization_ref}),false);
  await new Promise(resolve=>setImmediate(resolve));
});

test('the verification registry rejects private keys and accepts only public key material', () => {
  const f=fixture(),r=f.approve(request()),grant=f.state.grants[0];
  const privatePem=f.keys.privateKey.export({type:'pkcs8',format:'pem'});
  for (const key of [f.keys.privateKey,privatePem,Buffer.from(privatePem),
    {key:privatePem,format:'pem'},f.keys.privateKey.export({format:'jwk'})]) {
    f.state.grants=[{...grant,public_key:key}];assert.equal(f.check(r),false);
  }
  const publicPem=f.keys.publicKey.export({type:'spki',format:'pem'});
  for (const key of [f.keys.publicKey,publicPem,Buffer.from(publicPem)]) {
    f.state.grants=[{...grant,public_key:key}];assert.equal(f.check(r),true);
  }
});

test('real DomainStore rejects forged and revoked authority; exact retry has a single durable effect', t => {
  const f=fixture(),db=new DatabaseSync(':memory:');t.after(()=>db.close());
  db.exec("CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT);INSERT INTO core_metadata VALUES('schema_version','6'),('node_id','synthetic-web-core'),('cursor_secret','synthetic-only');");
  db.exec(DOMAIN_SCHEMA_SQL);
  const store=new DomainStore(db,{nodeId:binding.core_instance_id,cursorSecret:'synthetic-only',clock:()=>f.state.now,
    verifyAuthorization:f.verifier,domainHooks:createPersonalDataHooks({captureSourcesByPrincipal:{web:['claude_web']}})});
  registerPersonalDataDomains(store,{mode:'authoritative'});
  const issued=store.configurePrincipal({principal_id:'web',device_id:'web-device',installation_id:'web-install',
    scopes:['captures:read','captures:create','captures:patch','captures:delete'],actors:['user_via_agent']});
  const p=store.authenticate(issued.token),r=f.approve(request());
  const accepted=store.submit(p,'captures',r);assert.equal(accepted.status,201,JSON.stringify(accepted));
  assert.equal(store.submit(p,'captures',r).body.receipt.receipt_id,accepted.body.receipt.receipt_id);
  assert.equal(store.submit(p,'captures',{...r,op_id:randomUUID()}).status,403);
  const outstanding=f.approve(request());f.state.grants=[];
  assert.equal(store.submit(p,'captures',outstanding).status,403);
  assert.equal(db.prepare('SELECT COUNT(*) n FROM domain_changes').get().n,1);
});
