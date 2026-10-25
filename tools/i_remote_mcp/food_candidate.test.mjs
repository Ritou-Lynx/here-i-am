import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {after, before, test} from 'node:test';
import {buildChatgptCandidate, REPO_ROOT} from './chatgpt_candidate.mjs';
import {createDomainClient, createFoodTools, FOOD_TOOLS} from './domain_tools.mjs';
import {foodData, foodHttp, foodNow} from '../i_core/test_fixtures/release_schema6/n2a_food.mjs';
import {provisionFoodDomain} from '../i_core/personal_data_domains.mjs';
import {createFakeReadModel, PASSPHRASE, PUBLIC_URL, pkcePair, registerClient, submitPassphrase, authorizeParams, postToken, initSession, mcpPost} from './fixtures.mjs';
import {listenForFetch} from './fetch_test_listener.mjs';

const outputDirectory=join(REPO_ROOT,'build','food-candidate-test-'+randomUUID());
let built, candidate, oauthModule, rpcModule;
before(async()=>{
  built=buildChatgptCandidate({outputDirectory});
  const load=name=>import(pathToFileURL(join(built.root,'i_remote_mcp',name+'.mjs')));
  [candidate,oauthModule,rpcModule]=await Promise.all([load('server'),load('oauth'),load('mcp')]);
});
after(()=>rmSync(outputDirectory,{recursive:true,force:true}));
function state(t) {
  const path=join(outputDirectory,'synthetic-state-'+randomUUID());mkdirSync(path);
  t.after(()=>rmSync(path,{recursive:true,force:true}));return path;
}
function cleanEnvironment() {
  return Object.fromEntries(Object.entries(process.env).filter(([key])=>!/^(I_|NODE_OPTIONS$|NODE_PATH$)/i.test(key)));
}
function cli(args, input='') {
  return new Promise((resolve,reject)=>{
    const child=spawn(process.execPath,['--disable-warning=ExperimentalWarning',built.entryPath,...args],{env:cleanEnvironment(),windowsHide:true,stdio:['pipe','pipe','pipe']});
    let stdout='',stderr='';
    const timer=setTimeout(()=>{child.kill();reject(new Error('synthetic_cli_timeout'));},15000);
    child.on('error',error=>{clearTimeout(timer);reject(error);});
    child.stdout.on('data',chunk=>stdout+=chunk);child.stderr.on('data',chunk=>stderr+=chunk);
    child.stdin.on('error',()=>{});child.stdin.end(input);
    child.on('close',code=>{clearTimeout(timer);resolve({code,stdout,stderr});});
  });
}
const callbacks={claude_web:'https://claude.ai/api/mcp/auth_callback',chatgpt_web:'https://chatgpt.com/connector_platform_oauth_redirect',
  antigravity:'http://127.0.0.1:32014/oauth/callback',gemini_web:'https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-synthetic-food'};
async function start(t,{stateDir,coreUrl,frontend,writeback=null}={}) {
  oauthModule.setPassphrase(stateDir,PASSPHRASE);
  const app=candidate.createApp({stateDir,coreUrl,publicUrl:PUBLIC_URL,getReadModel:async()=>createFakeReadModel(),now:()=>foodNow,
    chatgptEnabled:true,geminiEnabled:true,antigravityEnabled:true,writeback});
  await listenForFetch(app.server);
  t.after(()=>new Promise(resolve=>app.server.close(resolve)));
  const base='http://127.0.0.1:'+app.server.address().port, redirectUri=callbacks[frontend];
  const registered=await registerClient(base,[redirectUri]);assert.equal(registered.status,201);
  const {verifier,challenge}=pkcePair();
  const auth=await submitPassphrase(base,{...Object.fromEntries(authorizeParams({clientId:registered.body.client_id,challenge})),redirect_uri:redirectUri});
  assert.equal(auth.status,302);
  const token=await postToken(base,{grant_type:'authorization_code',code:new URL(auth.headers.get('location')).searchParams.get('code'),
    client_id:registered.body.client_id,redirect_uri:redirectUri,code_verifier:verifier,resource:PUBLIC_URL+'/mcp'});
  assert.equal(token.status,200);
  const {init,sessionId}=await initSession(base,token.body.access_token);assert.equal(init.status,200);
  let id=2;
  const rpc=async(method,params)=>{
    const response=await mcpPost(base,token.body.access_token,{jsonrpc:'2.0',id:id++,method,params},{sessionId});
    assert.equal(response.status,200);return response.body;
  };
  return {...app,rpc,call:async(name,args)=>(await rpc('tools/call',{name,arguments:args})).result};
}
function entry(overrides={}) {
  const {eaten_at,meal,title,note,input_kind,items}=foodData();
  return {eaten_at,meal,title,note,input_kind,items,...overrides};
}
const scopes=['food_entries:read','food_entries:create','food_entries:patch'];
function mainline(real,token) {
  return createFoodTools({client:createDomainClient({coreUrl:real.coreOrigin,coreInstanceId:real.core.store.nodeId,token}),scopes,now:()=>foodNow});
}
async function core(t) {
  // foodHttp creates a schema-6 synthetic createICoreServer with N2a food hooks.
  const real=await foodHttp(t);
  real.coreOrigin='http://127.0.0.1:'+real.core.server.address().port;
  real.tokens=provisionFoodDomain(real.core.store.domains).issued;
  return real;
}
async function install(stateDir,real) {
  const input=JSON.stringify({status:'provisioned',writer_token:real.tokens.writer,phone_token:real.tokens.phone})+'\n';
  const result=await cli(['set-food-credential','--state-dir',stateDir,'--core-url',real.coreOrigin],input);
  for(const secret of [real.tokens.writer,real.tokens.phone])assert.equal((result.stdout+result.stderr).includes(secret),false);
  assert.equal(result.code,0,result.stderr);assert.equal(result.stdout,'已保存食物写入凭据\n');assert.equal(result.stderr,'');
  const path=join(stateDir,'core-food.json'),credential=JSON.parse(readFileSync(path));
  assert.deepEqual(Object.keys(credential).sort(),['format','principal_id','token','core_instance_id','time_zone'].sort());
  assert.equal(credential.format,'core-food-v1');assert.equal(credential.principal_id,'food-mcp-writer');
  assert.equal(credential.token===real.tokens.writer,true);assert.equal(credential.core_instance_id,real.core.store.nodeId);assert.equal(credential.time_zone,'Asia/Shanghai');
  assert.equal(readFileSync(path,'utf8').includes(real.tokens.phone),false);
  if(process.platform!=='win32')assert.equal(statSync(path).mode&0o777,0o600);
  else assert.ok(statSync(path).isFile(),'Windows uses the same private writer as pair-core');
  return credential;
}

test('N2b provision stdin, three OAuth frontends and real Core add/update/void match mainline', {timeout:60000},async t=>{
  const real=await core(t), reference=await core(t),expected=mainline(reference,reference.tokens.writer);
  assert.deepEqual(candidate.createCandidateFoodTools({client:{},scopes}).tools,FOOD_TOOLS);
  const normalise=value=>JSON.parse(JSON.stringify(value).replaceAll(reference.core.store.nodeId,'synthetic-core').replaceAll(real.core.store.nodeId,'synthetic-core'));
  for(const frontend of ['claude_web','chatgpt_web','antigravity']) {
    const stateDir=state(t);await install(stateDir,real);
    const app=await start(t,{stateDir,coreUrl:real.coreOrigin,frontend});
    const listed=(await app.rpc('tools/list')).result.tools;
    assert.deepEqual(listed.map(tool=>tool.name),['i_context','i_recall','food_log','food_day']);
    for(const tool of FOOD_TOOLS) {
      const actual=listed.find(item=>item.name===tool.name);
      assert.equal(actual.description,tool.description);assert.deepEqual(actual.inputSchema,tool.inputSchema);
    }
    const id=randomUUID(), add={action:'add',op_id:randomUUID(),id,entry:entry({eaten_at:'2026-10-25T03:59:59+08:00'})};
    async function compare(args) {
      const actual=await app.call('food_log',args), wanted=await expected.handlers.food_log(args);
      assert.equal(actual.isError,false);assert.deepEqual(actual.structuredContent,wanted);return actual.structuredContent;
    }
    const added=await compare(add);assert.equal(added.local_date,'2026-10-24');assert.equal(added.totals.kcal,100);
    assert.deepEqual(await compare(add),added,'identical retry preserves timestamps and operation');
    const conflict=await app.call('food_log',{...add,entry:entry({title:'changed intent'})});
    assert.equal(conflict.isError,true);assert.equal(conflict.structuredContent.error.code,'idempotency_conflict');
    for(const bad of [{...add,actor:'user_direct'},{...add,entry:{...add.entry,totals:{}}},{...add,entry:{...add.entry,local_date:'2026-10-25'}}]) {
      const rejected=await app.call('food_log',bad);assert.equal(rejected.isError,true);assert.equal(rejected.structuredContent.error.code,'food_field_not_allowed');
    }
    await compare({action:'update',op_id:randomUUID(),id,base_revision:1,entry:entry({items:entry().items.map(item=>({...item,kcal:123.4}))})});
    for(const date of ['2026-10-24','2026-10-25']) {
      const actual=await app.call('food_day',{date});assert.equal(actual.isError,false);
      assert.deepEqual(normalise(actual.structuredContent),normalise(await expected.handlers.food_day({date})));
    }
    const record=(await real.send('/v1/core/domains/food_entries/records/'+id,real.tokens.writer)).body.record;
    assert.equal(record.data.local_date,'2026-10-25');assert.equal(record.data.totals.kcal,123.4);
    assert.ok(Object.values(record.field_meta).every(field=>field.actor==='agent_inferred'));
    await compare({action:'void',op_id:randomUUID(),id,base_revision:2});
    const day=await app.call('food_day',{});assert.equal(day.structuredContent.entries.length,0);assert.equal(day.structuredContent.day_totals.kcal,0);
    const voided=(await real.send('/v1/core/domains/food_entries/records/'+id,real.tokens.writer)).body.record;
    assert.equal(voided.data.voided,true);assert.equal(voided.data.title,record.data.title);assert.deepEqual(voided.data.items,record.data.items);
  }
  const stateDir=state(t);await install(stateDir,real);
  const gemini=await start(t,{stateDir,coreUrl:real.coreOrigin,frontend:'gemini_web'});
  assert.deepEqual((await gemini.rpc('tools/list')).result.tools.map(tool=>tool.name),['i_context','i_recall']);
  assert.equal((await gemini.rpc('tools/call',{name:'food_log',arguments:{}})).error.code,-32602);
});

test('N2b missing credential preserves four frontend lists including paired writeback', {timeout:30000},async t=>{
  for(const frontend of Object.keys(callbacks))for(const paired of [false,true]) {
    const app=await start(t,{stateDir:state(t),frontend,writeback:paired?{}:null});
    assert.deepEqual((await app.rpc('tools/list')).result.tools,rpcModule.listTools({writeEnabled:paired,...(frontend==='claude_web'?{}:{frontend})}).map(({requiredScope,...tool})=>tool));
  }
});

test('N2b stdin and credential validation fail closed without exposing either token', {timeout:60000},async t=>{
  const real=await core(t), stateDir=state(t),credential=await install(stateDir,real),file=join(stateDir,'core-food.json');
  const original=readFileSync(file);
  const invalidInputs=[['{}','food_writer_token_missing'],[JSON.stringify({phone_token:real.tokens.phone}),'food_writer_token_missing'],
    [JSON.stringify({writer_token:'bad'}),'invalid_food_credential'],['{','invalid_food_credential'],['x'.repeat(8193),'invalid_food_credential'],
    [JSON.stringify({writer_token:real.tokens.writer})+'\n{}','invalid_food_credential']];
  for(const [input,code] of invalidInputs) {
    const result=await cli(['set-food-credential','--state-dir',stateDir,'--core-url',real.coreOrigin],input);
    assert.equal(result.code,1);assert.ok(result.stderr.includes(code));
    if(code==='food_writer_token_missing')assert.ok(result.stderr.includes('-Rotate writer'));
    for(const token of [real.tokens.writer,real.tokens.phone])assert.equal((result.stdout+result.stderr).includes(token),false);
    assert.ok(readFileSync(file).equals(original),'failed provisioning leaves existing credential untouched');
  }
  const unreachable=await cli(['set-food-credential','--state-dir',stateDir,'--core-url','http://127.0.0.1:0'],JSON.stringify({writer_token:real.tokens.writer}));
  assert.equal(unreachable.code,1);assert.match(unreachable.stderr,/food_core_unreachable/);assert.ok(readFileSync(file).equals(original));
  const invalid=[{...credential,extra:true},...Object.keys(credential).map(key=>Object.fromEntries(Object.entries(credential).filter(([name])=>name!==key))),
    {...credential,format:'other'},{...credential,principal_id:'other'},{...credential,token:'bad'},{...credential,core_instance_id:'../bad'},
    {...credential,time_zone:'UTC'},null,[],{...credential,token:44}];
  for(const value of invalid) {
    writeFileSync(file,JSON.stringify(value));
    assert.throws(()=>candidate.createApp({stateDir,publicUrl:PUBLIC_URL,getReadModel:async()=>({})}),/^Error: invalid_food_credential$/);
    const result=await cli(['serve','--state-dir',stateDir,'--port','0']);
    assert.equal(result.code,1);assert.match(result.stderr,/invalid_food_credential/);
    for(const token of [real.tokens.writer,real.tokens.phone])assert.equal((result.stdout+result.stderr).includes(token),false);
  }
  writeFileSync(file,'{');assert.throws(()=>candidate.loadFoodCredential(stateDir),/invalid_food_credential/);
  rmSync(file);assert.equal(candidate.loadFoodCredential(stateDir),null);assert.equal(existsSync(file),false);
});

test('N2b snapshot pagination, 04:00 boundary and restart retry match mainline',async()=>{
  const rows=Array.from({length:103},(_,i)=>({id:String(i),data:{...foodData(),voided:i===1,local_date:i===2?'2026-10-24':'2026-10-25'}}));
  function client() {
    const calls=[];
    return {calls,async snapshot(domain,query) {
      calls.push([domain,query]);return query.page_token?{http_status:200,records:rows.slice(100),manifest:{base_cursor:'end'},snapshot_id:'snapshot'}:
        {http_status:200,records:rows.slice(0,100),next_page_token:'second'};
    },async acknowledge(...args){calls.push(args);}};
  }
  const a=client(),b=client(),stamp=()=>Date.parse('2026-10-25T04:00:00+08:00');
  const actual=candidate.createCandidateFoodTools({client:a,scopes,now:stamp}),expected=createFoodTools({client:b,scopes,now:stamp});
  assert.deepEqual(await actual.handlers.food_day({}),await expected.handlers.food_day({}));assert.deepEqual(a.calls,b.calls);
  assert.equal((await actual.handlers.food_day({})).entries.length,101);
  for(const make of [candidate.createCandidateFoodTools,createFoodTools]) {
    const tools=make({client:{operation:async()=>({http_status:200})},scopes,now:stamp});
    await assert.rejects(tools.handlers.food_log({action:'add',op_id:randomUUID(),id:randomUUID(),entry:entry()}),/food_retry_state_unavailable/);
  }
});
