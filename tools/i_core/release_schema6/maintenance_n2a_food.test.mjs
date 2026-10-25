import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac,randomBytes,randomUUID} from 'node:crypto';
import {existsSync,readFileSync,readdirSync,writeFileSync,rmSync,mkdirSync,symlinkSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import path from 'node:path';
import {createFoodProvisionPoller} from './lifecycle/runtime_child.mjs';
import {foodMemory,foodHttp,foodOperation} from '../test_fixtures/release_schema6/n2a_food.mjs';
import {syntheticRoot} from '../test_fixtures/release_schema6/synthetic_paths.mjs';
import {FOOD_SCHEMAS,provisionFoodDomain} from '../personal_data_domains.mjs';
import {INVENTORY,sha256,cleanEnvironment} from './package.mjs';
import {createRuntimeLab,repository,ps,cleanReceipt} from './lifecycle/test-fixture.mjs';
import {loginConfig,loginArgs,host} from './lifecycle/mcp-session-test-fixture.mjs';
import {allocateSyntheticLoopbackPort} from '../test_fixtures/release_schema6/mcp_reader/helper.mjs';

function fixture(t,{core,writeReceipt}={}) {
 const control=syntheticRoot('n2a-food-poll-');t.after(()=>rmSync(control,{recursive:true,force:true}));
 const token=randomBytes(32).toString('hex'),manifestSha256=randomBytes(32).toString('hex'),key=randomBytes(32).toString('hex');
 const {domains}=foodMemory(t);const receipts=[];let time=1700000000000;
 writeFileSync(path.join(control,'stop.key'),key);
 const poll=createFoodProvisionPoller({control,token,manifestSha256,core:core??{store:{domains}},now:()=>time,
  writeReceipt:writeReceipt??((name,value)=>{receipts.push(value);writeFileSync(path.join(control,name),JSON.stringify(value));})});
 const sign=(request,{signToken=token,signManifest=manifestSha256}={})=>({...request,hmac:createHmac('sha256',key)
  .update(signToken+'|'+signManifest+'|food|'+request.request_id+'|'+[...request.rotate].sort().join(',')+'|'+request.expires_at_ms).digest('hex')});
 const publish=request=>writeFileSync(path.join(control,'food.request'),JSON.stringify(request));
 const request=(overrides={},auth={})=>{const value=sign({request_id:randomUUID(),rotate:[],expires_at_ms:time+600000,...overrides},auth);publish(value);return value;};
 return {control,poll,request,publish,receipts,domains,advance:ms=>time+=ms};
}
const tokenFiles=f=>readdirSync(f.control).filter(name=>name.startsWith('food-tokens-'));
function assertPrivate(f) {
 for(const name of tokenFiles(f)){
  const tokens=JSON.parse(readFileSync(path.join(f.control,name)));
  for(const value of [tokens.writer_token,tokens.phone_token].filter(Boolean)){
   assert.equal(JSON.stringify(f.receipts).includes(value),false,'receipts contain no token');
   assert.equal(process.argv.some(arg=>arg.includes(value)),false,'argv contains no token');
   for(const file of readdirSync(f.control).filter(n=>n!==name&&n.startsWith('food-receipt-')))
    assert.equal(readFileSync(path.join(f.control,file),'utf8').includes(value),false);
  }
 }
}
test('N2a exact inventory and package validators retain the R1 hashes',()=>{
 assert.equal(INVENTORY.length,48);
 for(const [name,expected] of [['package.mjs','0acff4e9b9b4425b66c3492749f45c3bab2e58386b14585ab6462ada452d8199'],
  ['package_switch.mjs','41f0d5c2c25768e55618ec4a69465c084482a87db245da0d31457f070c358173']])
  assert.equal(sha256(Buffer.from(readFileSync(new URL(name,import.meta.url),'utf8').replace(/\r\n/g,'\n'))),expected);
});
test('N2a authenticated provisioning consumes input first and emits only separate tokens',t=>{
 const f=fixture(t);const original=f.domains.configurePrincipal;
 f.domains.configurePrincipal=function(...args){assert.equal(existsSync(path.join(f.control,'food.request')),false);return original.apply(this,args);};
 const request=f.request();assert.doesNotThrow(f.poll);
 assert.deepEqual(f.receipts[0],{status:'provisioned',request_id:request.request_id,registered:true,issued:['writer','phone'],hooks_version:'food-v1',at_ms:1700000000000});
 const tokens=JSON.parse(readFileSync(path.join(f.control,tokenFiles(f)[0])));assert.equal(tokens.format,'food-tokens-v1');
 assert.ok(f.domains.authenticate(tokens.writer_token));assert.ok(f.domains.authenticate(tokens.phone_token));assertPrivate(f);
 f.request();f.poll();assert.deepEqual(f.receipts.at(-1).issued,[]);assert.equal(tokenFiles(f).length,1);
 f.request({rotate:['writer','phone']});f.poll();assert.deepEqual(f.receipts.at(-1).issued,['writer','phone']);assertPrivate(f);
});
for(const scenario of ['wrong-hmac','wrong-token','wrong-manifest','expired','future-expiry','oversized','bad-json','extra-key','invalid-rotate','duplicate-rotate','invalid-uuid','replay']){
 test('N2a isolated rejection and later valid request: '+scenario,t=>{
  const f=fixture(t);let request;
  if(scenario==='expired')request=f.request({expires_at_ms:1699999999999});
  else if(scenario==='future-expiry')request=f.request({expires_at_ms:1700000600001});
  else if(scenario==='wrong-token')request=f.request({}, {signToken:'wrong'});
  else if(scenario==='wrong-manifest')request=f.request({}, {signManifest:'wrong'});
  else if(scenario==='invalid-rotate')request=f.request({rotate:['admin']});
  else if(scenario==='duplicate-rotate')request=f.request({rotate:['phone','phone']});
  else if(scenario==='invalid-uuid')request=f.request({request_id:'../escape'});
  else request=f.request();
  if(scenario==='wrong-hmac')f.publish({...request,hmac:'0'.repeat(64)});
  if(scenario==='extra-key')f.publish({...request,extra:true});
  if(scenario==='bad-json')writeFileSync(path.join(f.control,'food.request'),'{');
  if(scenario==='oversized')writeFileSync(path.join(f.control,'food.request'),' '.repeat(1025));
  if(scenario==='replay'){f.poll();f.publish({...request,rotate:['writer']});const r=f.request({request_id:request.request_id,rotate:['writer']});assert.equal(r.request_id,request.request_id);}
  const issuedBefore=tokenFiles(f).length;assert.doesNotThrow(f.poll);
  assert.match(f.receipts.at(-1).status,/^rejected_/);assert.equal(tokenFiles(f).length,issuedBefore);
  assert.equal(existsSync(path.join(f.control,'food.request')),false);
  f.request();assert.doesNotThrow(f.poll);assert.equal(f.receipts.at(-1).status,'provisioned');assertPrivate(f);
 });
}
test('N2a non-regular requests and symlinks are refused without following inputs',t=>{
 const f=fixture(t),requestPath=path.join(f.control,'food.request');mkdirSync(requestPath);
 assert.doesNotThrow(f.poll);assert.match(f.receipts.at(-1).status,/^rejected_/);assert.equal(tokenFiles(f).length,0);rmSync(requestPath,{recursive:true});
 // Windows symlink creation needs a privilege; the directory case runs everywhere.
 if(process.platform!=='win32'){
  const target=path.join(f.control,'untouched');writeFileSync(target,'synthetic');symlinkSync(target,requestPath);
  assert.doesNotThrow(f.poll);assert.equal(readFileSync(target,'utf8'),'synthetic');assert.equal(existsSync(requestPath),false);
 }
 f.request();f.poll();assert.equal(f.receipts.at(-1).status,'provisioned');
});
test('N2a conflicts and internal errors are redacted and isolated',t=>{
 const f=fixture(t);f.domains.registerDomain('food_entries',FOOD_SCHEMAS.food_entries,{mode:'off',requiredHooksVersion:'food-v1'});
 f.request();assert.doesNotThrow(f.poll);assert.equal(f.receipts.at(-1).status,'rejected_food_domain_conflict');assert.equal(tokenFiles(f).length,0);
 const broken=fixture(t,{core:{get store(){throw new Error('synthetic-secret-must-not-escape');}}});
 broken.request();assert.doesNotThrow(broken.poll);assert.equal(JSON.stringify(broken.receipts).includes('synthetic-secret-must-not-escape'),false);
});
test('N2a receipt write failure cannot escape or stop Core',t=>{
 const f=fixture(t,{writeReceipt(){throw new Error('synthetic_receipt_failure');}});
 f.request();assert.doesNotThrow(f.poll);assert.equal(tokenFiles(f).length,1);assertPrivate(f);
});
test('N2a token file collision fails closed without overwriting another output',t=>{
 const f=fixture(t),r=f.request(),file=path.join(f.control,'food-tokens-'+r.request_id+'.json');
 writeFileSync(file,'synthetic existing output');assert.doesNotThrow(f.poll);
 assert.equal(readFileSync(file,'utf8'),'synthetic existing output');assert.equal(f.receipts.at(-1).status,'rejected_provision_failed');
});
test('N2a Linux real Core provisions over the control channel and accepts HTTP writes',
 {skip:process.platform==='win32',timeout:30000},async t=>{
 const real=await foodHttp(t),f=fixture(t,{core:real.core});f.request();f.poll();assert.equal(f.receipts[0].status,'provisioned');
 const tokens=JSON.parse(readFileSync(path.join(f.control,tokenFiles(f)[0])));
 assert.equal((await real.send('/v1/core/domains/food_entries/ops',tokens.writer_token,foodOperation(real.core))).status,201);
 assert.equal((await real.send('/v1/core/health')).status,200);assertPrivate(f);
});

const windowsCI=process.platform==='win32'&&process.env.GITHUB_ACTIONS==='true';
test('N2a Windows synthetic script emits one JSON, deletes tokens, rotates only phone and refuses pending requests',
 {skip:!windowsCI,timeout:900000},async t=>{
 const l=await createRuntimeLab(t),c=loginConfig(l,await allocateSyntheticLoopbackPort()),run=await host(l,c);
 await run.ready();const inputPath=path.join(l.root,'n2a-task.json');
 writeFileSync(inputPath,JSON.stringify({Name:'Synthetic-N2a-Food',Path:ps,Arguments:loginArgs(l,c).map(v=>'"'+v+'"').join(' '),WorkingDirectory:l.release,Enabled:true,State:4}));
 const invoke=(rotate=[])=>{
  const result=spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',
   path.join(repository,'tools/i_core/test_fixtures/release_schema6/n2a_food_session.ps1'),'-InputPath',inputPath,
   '-MaintenanceDirectory',path.join(repository,'tools/i_core/maintenance'),...(rotate.length?['-Rotate',...rotate]:[])],
   {env:{...cleanEnvironment(),GITHUB_ACTIONS:'true'},windowsHide:true,encoding:'utf8',timeout:90000});
  assert.ifError(result.error);assert.equal(result.stdout.trim().split(/\r?\n/).length,1,'exactly one output line; raw stdout withheld');
  let value;try{value=JSON.parse(result.stdout);}catch{assert.fail('invalid redacted CLI output');}
  assert.equal(result.stderr.length,0,'stderr empty; raw stderr withheld');return {status:result.status,value};
 };
 const first=invoke();assert.equal(first.status,0);assert.equal(first.value.status,'provisioned');
 assert.equal(typeof first.value.writer_token,'string');assert.equal(typeof first.value.phone_token,'string');
 assert.equal(readdirSync(run.control).some(n=>n.startsWith('food-tokens-')),false);
 const second=invoke();assert.equal(second.status,0);assert.deepEqual(second.value.issued,[]);assert.equal(Object.hasOwn(second.value,'writer_token'),false);
 const rotated=invoke(['phone']);assert.equal(rotated.status,0);assert.deepEqual(rotated.value.issued,['phone']);
 assert.equal(Object.hasOwn(rotated.value,'writer_token'),false);assert.equal(rotated.value.phone_token===first.value.phone_token,false);
 assert.equal(readdirSync(run.control).some(n=>n.startsWith('food-tokens-')),false);
 // A reservation is also an unhandled publication; no scheduler operations occur.
 writeFileSync(path.join(run.control,'food.request.pending'),'synthetic outstanding reservation');
 const pending=invoke();assert.equal(pending.status,2);assert.equal(pending.value.status,'rejected_food_unhandled_request_exists');
 rmSync(path.join(run.control,'food.request.pending'));
 for(const secret of [first.value.writer_token,first.value.phone_token,rotated.value.phone_token]){
  assert.equal((run.stdout+run.stderr).includes(secret),false);
  for(const name of readdirSync(run.control).filter(n=>n.startsWith('food-receipt-')))
   assert.equal(readFileSync(path.join(run.control,name),'utf8').includes(secret),false);
 }
 run.stop();await run.wait();cleanReceipt(run);l.completed=true;
});
