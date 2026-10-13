import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac, randomBytes} from 'node:crypto';
import {existsSync,readFileSync,readdirSync,renameSync,rmdirSync,unlinkSync,writeFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {INVENTORY,sha256} from './package.mjs';
import {createPairingRequestPoller} from './lifecycle/runtime_child.mjs';
import {createICoreServer} from '../i_core_server.mjs';
import {syntheticRoot} from '../test_fixtures/release_schema6/synthetic_paths.mjs';
const baselineInventory=[
 "runtime/node.exe",
 "tools/i_core/activity_control_plane.mjs",
 "tools/i_core/domain_http.mjs",
 "tools/i_core/domain_migrate.mjs",
 "tools/i_core/domain_schema.mjs",
 "tools/i_core/domain_store.mjs",
 "tools/i_core/i_core_server.mjs",
 "tools/i_core/i_core_store.mjs",
 "tools/i_core/inspection_read_only.mjs",
 "tools/i_core/personal_data_domains.mjs",
 "tools/i_core/release_schema6/README.md",
 "tools/i_core/release_schema6/automatic_backup.mjs",
 "tools/i_core/release_schema6/automatic_recovery.mjs",
 "tools/i_core/release_schema6/backup_bundle.mjs",
 "tools/i_core/release_schema6/backup_bundle_schema6.ps1",
 "tools/i_core/release_schema6/backup_key_child.mjs",
 "tools/i_core/release_schema6/cli.mjs",
 "tools/i_core/release_schema6/key_custody.ps1",
 "tools/i_core/release_schema6/lifecycle/common.mjs",
 "tools/i_core/release_schema6/lifecycle/configuration.mjs",
 "tools/i_core/release_schema6/lifecycle/job_guardian.ps1",
 "tools/i_core/release_schema6/lifecycle/login_schema6.ps1",
 "tools/i_core/release_schema6/lifecycle/mcp_configuration.ps1",
 "tools/i_core/release_schema6/lifecycle/offline_lease.mjs",
 "tools/i_core/release_schema6/lifecycle/offline_probe_client.mjs",
 "tools/i_core/release_schema6/lifecycle/owned_job.ps1",
 "tools/i_core/release_schema6/lifecycle/prepare_login_schema6.ps1",
 "tools/i_core/release_schema6/lifecycle/probe_offline.ps1",
 "tools/i_core/release_schema6/lifecycle/protected_paths.ps1",
 "tools/i_core/release_schema6/lifecycle/request_stop.ps1",
 "tools/i_core/release_schema6/lifecycle/runtime_child.mjs",
 "tools/i_core/release_schema6/lifecycle/session_window.ps1",
 "tools/i_core/release_schema6/lifecycle/start_schema6.ps1",
 "tools/i_core/release_schema6/package.mjs",
 "tools/i_core/release_schema6/package_switch.mjs",
 "tools/i_core/release_schema6/portable_backup_schema6.ps1",
 "tools/i_core/release_schema6/portable_key_custody.mjs",
 "tools/i_core/release_schema6/preflight.mjs",
 "tools/i_core/release_schema6/preflight_schema6.ps1",
 "tools/i_core/release_schema6/raw_state_backup.mjs",
 "tools/i_core/release_schema6/readonly_witness.mjs",
 "tools/i_core/release_schema6/recovery_adapter.mjs",
 "tools/i_core/release_schema6/recovery_witness_worker.mjs",
 "tools/i_core/release_schema6/restore_inspection.mjs",
 "tools/i_core/release_schema6/scheduler_once_schema6.ps1",
 "tools/i_core/send_shortcut_mail.ps1",
 "tools/i_core/shortcut_mail_relay.mjs",
 "tools/i_core/strict_smtp_tls_validation.ps1"
];
const here=path.dirname(fileURLToPath(import.meta.url));
const code=()=>randomBytes(32).toString('hex');
function fixture(t,{cleanup=true}={}){
 const root=syntheticRoot('schema6-pairing-unit-');
 const token=code(),manifestSha256=code(),key=code(),receipts=[];
 let time=1700000000000;
 const calls={replace:0,close:0,alive:true,active:false};
 const core={
  replacePairingCode(value){assert.equal(existsSync(path.join(root,'pair.code')),false);assert.equal(existsSync(path.join(root,'pair.request')),false);calls.replace++;calls.active=true;},
  closePairingWindow(){calls.close++;calls.active=false;},
  hasActivePairingCode(){return calls.active;},
 };
 writeFileSync(path.join(root,'stop.key'),key);
 const writeReceipt=(name,value)=>{receipts.push(value);writeFileSync(path.join(root,name),JSON.stringify(value));};
 const poll=createPairingRequestPoller({control:root,token,manifestSha256,core,writeReceipt,now:()=>time});
 function request(value,{expires=time+600000,signToken=token,signManifest=manifestSha256,signCode=value,hmac=null}={}){
  const r={expires_at_ms:expires,hmac:hmac??createHmac('sha256',key).update(signToken+'|'+signManifest+'|pair|'+sha256(Buffer.from(signCode))+'|'+expires).digest('hex')};
  writeFileSync(path.join(root,'pair.code'),value);writeFileSync(path.join(root,'pair.request'),JSON.stringify(r));return r;
 }
 function remove(){for(const name of readdirSync(root))unlinkSync(path.join(root,name));rmdirSync(root);}
 if(cleanup)t.after(remove);
 return {root,token,manifestSha256,key,receipts,calls,core,poll,request,writeReceipt,now:()=>time,advance:ms=>{time+=ms;},remove};
}
test('R1 exact baseline INVENTORY and immutable validators remain unchanged',()=>{
 assert.deepEqual(INVENTORY,baselineInventory);assert.equal(INVENTORY.length,48);
 // Git checkout may use CRLF on Windows; compare the unchanged LF source bytes.
 const sourceHash=name=>sha256(Buffer.from(readFileSync(path.join(here,name),'utf8').replace(/\r\n/g,'\n')));
 assert.equal(sourceHash('package.mjs'),'0acff4e9b9b4425b66c3492749f45c3bab2e58386b14585ab6462ada452d8199');
 assert.equal(sourceHash('package_switch.mjs'),'41f0d5c2c25768e55618ec4a69465c084482a87db245da0d31457f070c358173');
});
test('authenticated request consumes both inputs before opening and never discloses its code',t=>{
 const f=fixture(t),value=code();f.request(value);assert.doesNotThrow(f.poll);assert.equal(f.calls.replace,1);
 assert.equal(f.receipts[0].status,'opened');assert.deepEqual(Object.keys(f.receipts[0]).sort(),['at_ms','code_hash_prefix','status']);
 assert.equal(JSON.stringify(f.receipts).includes(value),false);assert.equal(process.argv.some(a=>a.includes(value)),false);
});
for(const scenario of ['wrong-hmac','expired','future-expiry','hash-mismatch','wrong-token','wrong-manifest','invalid-code']){
 test('pairing rejection stays isolated and a later valid request works: '+scenario,t=>{
  const f=fixture(t),value=code();
  if(scenario==='wrong-hmac')f.request(value,{hmac:'0'.repeat(64)});
  if(scenario==='expired')f.request(value,{expires:f.now()-1});
  if(scenario==='future-expiry')f.request(value,{expires:f.now()+600001});
  if(scenario==='hash-mismatch')f.request(value,{signCode:code()});
  if(scenario==='wrong-token')f.request(value,{signToken:code()});
  if(scenario==='wrong-manifest')f.request(value,{signManifest:code()});
  if(scenario==='invalid-code')f.request('short');
  assert.doesNotThrow(f.poll);assert.equal(f.calls.alive,true);assert.equal(f.calls.replace,0);assert.match(f.receipts.at(-1).status,/^rejected_/);
  assert.equal(existsSync(path.join(f.root,'pair.code')),false);assert.equal(existsSync(path.join(f.root,'pair.request')),false);
  f.request(code());f.poll();assert.equal(f.calls.replace,1);assert.equal(f.calls.alive,true);
 });
}
test('same authenticated request cannot be replayed before expiry',t=>{
 const f=fixture(t),value=code();const r=f.request(value);f.poll();f.request(value,{expires:r.expires_at_ms,hmac:r.hmac});f.poll();
 assert.equal(f.calls.replace,1);assert.equal(f.receipts.at(-1).status,'rejected_replay');assert.equal(f.calls.alive,true);
});
test('orphan code is rejected without stopping Core',t=>{
 const f=fixture(t);writeFileSync(path.join(f.root,'pair.code'),code());f.poll();assert.equal(f.receipts.at(-1).status,'rejected_orphan_code');assert.equal(f.calls.replace,0);assert.equal(f.calls.alive,true);
});
test('publisher reservation prevents a false orphan rejection',t=>{
 const f=fixture(t),value=code();f.request(value);renameSync(path.join(f.root,'pair.request'),path.join(f.root,'pair.request.pending'));
 f.poll();assert.equal(f.receipts.length,0);assert.equal(existsSync(path.join(f.root,'pair.code')),true);
 renameSync(path.join(f.root,'pair.request.pending'),path.join(f.root,'pair.request'));f.poll();assert.equal(f.calls.replace,1);
});
test('window expires at ten minutes',t=>{
 const f=fixture(t);f.request(code());f.poll();f.advance(600000);f.poll();assert.equal(f.calls.close,1);assert.equal(f.calls.active,false);assert.equal(f.receipts.at(-1).status,'closed_expired');
});
test('first successful pairing closes the managed window',t=>{
 const f=fixture(t);f.request(code());f.poll();f.calls.active=false;f.poll();assert.equal(f.calls.close,1);assert.equal(f.receipts.at(-1).status,'closed_paired');
});
test('bad JSON and missing inputs never escape the polling boundary',t=>{
 const f=fixture(t);writeFileSync(path.join(f.root,'pair.request'),'{');f.poll();assert.match(f.receipts.at(-1).status,/^rejected_/);
 f.request(code());writeFileSync(path.join(f.root,'pair.request'),'{');f.poll();assert.equal(f.calls.alive,true);assert.equal(f.calls.replace,0);
});
test('receipt write failure does not become a shutdown or uncaught exception',t=>{
 const f=fixture(t);const poll=createPairingRequestPoller({control:f.root,token:f.token,manifestSha256:f.manifestSha256,core:f.core,now:f.now,writeReceipt(){throw new Error('synthetic_receipt_failure');}});
 f.request(code());assert.doesNotThrow(poll);assert.equal(f.calls.replace,1);f.advance(600000);assert.doesNotThrow(poll);assert.equal(f.calls.close,1);assert.equal(f.calls.alive,true);
});

const linuxRuntime={skip:process.platform==='win32'||process.env.GITHUB_ACTIONS!=='true',timeout:30000};
for(const scenario of ['valid-single-use','expiry','wrong-hmac','expired','hash-mismatch','replay','orphan']){
 test('Linux real Core pairing request: '+scenario,linuxRuntime,async t=>{
  const f=fixture(t,{cleanup:false});
  const core=createICoreServer({databasePath:path.join(f.root,'core.sqlite'),clock:f.now});
  t.after(async()=>{await core.close();f.remove();});
  const address=await core.listen({host:'127.0.0.1',port:0});
  const poll=createPairingRequestPoller({control:f.root,token:f.token,manifestSha256:f.manifestSha256,core,now:f.now,writeReceipt:f.writeReceipt});
  const value=code();
  const pair=()=>fetch('http://127.0.0.1:'+address.port+'/v1/core/devices/pair',{method:'POST',headers:{'content-type':'application/json','x-core-protocol':'0.1'},body:JSON.stringify({pairing_code:value,device_id:'frontend:chatgpt_web',display_name:'Synthetic ChatGPT',platform:'external-frontend',client_version:'1',capabilities:['chat']})});
  if(scenario==='wrong-hmac')f.request(value,{hmac:'0'.repeat(64)});
  else if(scenario==='expired')f.request(value,{expires:f.now()-1});
  else if(scenario==='hash-mismatch')f.request(value,{signCode:code()});
  else if(scenario==='orphan')writeFileSync(path.join(f.root,'pair.code'),value);
  else f.request(value);
  poll();
  if(scenario==='valid-single-use'){
   assert.equal((await pair()).status,200);
   // The API closes immediately, before the next 25ms receipt poll.
   assert.equal((await pair()).status,403);poll();assert.equal(core.hasActivePairingCode(),false);
  }else if(scenario==='expiry'){
   f.advance(600000);assert.equal((await pair()).status,403);poll();
  }else if(scenario==='replay'){
   f.request(value);poll();assert.equal(f.receipts.at(-1).status,'rejected_replay');
   assert.equal((await pair()).status,200);poll();assert.equal((await pair()).status,403);
  }else assert.equal((await pair()).status,403);
  assert.equal((await fetch('http://127.0.0.1:'+address.port+'/v1/core/health')).status,200);
  assert.equal(JSON.stringify(f.receipts).includes(value),false);assert.equal(process.argv.some(arg=>arg.includes(value)),false);
 });
}
test('abandoned publisher reservation expires without stopping Core',t=>{
 const f=fixture(t),value=code();f.request(value);renameSync(path.join(f.root,'pair.request'),path.join(f.root,'pair.request.pending'));
 f.advance(600000);f.poll();assert.equal(f.receipts.at(-1).status,'rejected_abandoned_publish');
 assert.equal(existsSync(path.join(f.root,'pair.request.pending')),false);assert.equal(existsSync(path.join(f.root,'pair.code')),false);
 f.request(code());f.poll();assert.equal(f.calls.replace,1);
});

test('a partial publishing reservation is retained until the publisher completes',t=>{
 const f=fixture(t),value=code();const request=f.request(value);unlinkSync(path.join(f.root,'pair.request'));writeFileSync(path.join(f.root,'pair.request.pending'),'{');
 f.poll();assert.equal(f.receipts.length,0);assert.equal(existsSync(path.join(f.root,'pair.code')),true);
 writeFileSync(path.join(f.root,'pair.request.pending'),JSON.stringify(request));renameSync(path.join(f.root,'pair.request.pending'),path.join(f.root,'pair.request'));
 f.poll();assert.equal(f.calls.replace,1);assert.equal(f.receipts.at(-1).status,'opened');
});
