import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {existsSync, mkdirSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {after, before, test} from 'node:test';
import {buildChatgptCandidate, REPO_ROOT} from './chatgpt_candidate.mjs';
import {HEART_RATE_TOOLS, createHeartRateIngestServer, createHeartRateStore, createHeartRateTools, loadHeartRateConfig} from './heart_rate.mjs';
import {createHeartRateDomainTools, DomainToolInputError} from './domain_tools.mjs';
import * as mainServer from './server.mjs';
import * as mainOauth from './oauth.mjs';
import {createFakeReadModel, PASSPHRASE, PUBLIC_URL, pkcePair, registerClient, submitPassphrase, authorizeParams, postToken, initSession, mcpPost} from './fixtures.mjs';
import {listenForFetch} from './fetch_test_listener.mjs';

// All readings below are synthetic.
const root=join(REPO_ROOT,'build','heart-rate-test-'+randomUUID());
const NOW=Date.parse('2026-11-05T21:10:30+08:00');
const LOGIN='owner@example.test';
let built, candidate, candidateOauth;
before(async()=>{
  mkdirSync(root,{recursive:true});
  built=buildChatgptCandidate({outputDirectory:join('build','heart-rate-test-'+randomUUID())});
  const load=name=>import(pathToFileURL(join(built.root,'i_remote_mcp',name+'.mjs')));
  [candidate,candidateOauth]=await Promise.all([load('server'),load('oauth')]);
});
after(()=>{rmSync(root,{recursive:true,force:true});if(built)rmSync(built.outputRoot,{recursive:true,force:true});});

function fixture(t,{withConfig=true}={}) {
  const base=join(root,randomUUID()),stateDir=join(base,'state');
  mkdirSync(stateDir,{recursive:true});
  if(withConfig)writeFileSync(join(stateDir,'heart_rate.json'),JSON.stringify({format:'heart-rate-v1',tailscale_logins:[LOGIN]}));
  t.after(()=>rmSync(base,{recursive:true,force:true}));
  return {base,stateDir,dataDir:join(stateDir,'heart_rate')};
}
const minuteFile=(dataDir,date)=>join(dataDir,`minutes-${date}.jsonl`);
const writeMinutes=(dataDir,date,rows)=>writeFileSync(minuteFile(dataDir,date),rows.map(row=>JSON.stringify(row)).join('\n')+'\n');
const at=iso=>Date.parse(iso);

const callbacks={claude_web:'https://claude.ai/api/mcp/auth_callback',chatgpt_web:'https://chatgpt.com/connector_platform_oauth_redirect',
  antigravity:'http://127.0.0.1:32014/oauth/callback',gemini_web:'https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-synthetic-hr',
  sesame:'https://sesameai.app/api/oauth/external-mcp/callback'};
async function start(t,{server,oauth,stateDir,frontend,now=()=>NOW}) {
  oauth.setPassphrase(stateDir,PASSPHRASE);
  const app=server.createApp({stateDir,publicUrl:PUBLIC_URL,getReadModel:async()=>createFakeReadModel(),now,
    chatgptEnabled:true,geminiEnabled:true,antigravityEnabled:true,sesameEnabled:true});
  await listenForFetch(app.server);
  t.after(()=>new Promise(resolve=>app.server.close(resolve)));
  const base='http://127.0.0.1:'+app.server.address().port, redirectUri=callbacks[frontend];
  const registered=await registerClient(base,[redirectUri]);assert.equal(registered.status,201);
  const {verifier,challenge}=pkcePair();
  const auth=await submitPassphrase(base,{...Object.fromEntries(authorizeParams({clientId:registered.body.client_id,challenge})),redirect_uri:redirectUri,scope:'i.read i.write'});
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
  return {app,rpc,call:async(name,args)=>(await rpc('tools/call',{name,arguments:args})).result};
}
async function ingestServer(t,heartRate) {
  const {server}=createHeartRateIngestServer({store:heartRate.store,config:heartRate.config});
  await listenForFetch(server);
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  const base='http://127.0.0.1:'+server.address().port;
  return async(body,{login=LOGIN,raw,method='POST',path='/v1/heart-rate/samples'}={})=>{
    const headers={'content-type':'application/json'};
    if(login!==null)headers['tailscale-user-login']=login;
    const response=await fetch(base+path,{method,headers,body:method==='GET'?undefined:raw??JSON.stringify(body)});
    return {status:response.status,body:await response.json()};
  };
}
const batch=(samples,extra={})=>({format:'hr-samples-v1',device:'HR31 synthetic',status:'live',samples,...extra});
// 1 Hz samples ending one second before `end`.
const series=(end,seconds,bpm)=>Array.from({length:seconds},(_,i)=>({t:end-(seconds-i)*1000,bpm:typeof bpm==='function'?bpm(i):bpm}));

test('HR1 candidate inlines heart_rate.mjs verbatim and keeps the frozen dependency closure',()=>{
  const server=readFileSync(join(built.root,'i_remote_mcp','server.mjs'),'utf8').replaceAll('\r\n','\n');
  const source=readFileSync(new URL('./heart_rate.mjs',import.meta.url),'utf8').replaceAll('\r\n','\n');
  assert.equal(server.split(source.trimEnd()).length,2,'heart_rate.mjs must appear exactly once, byte for byte');
  assert.deepEqual(candidate.HEART_RATE_TOOLS,HEART_RATE_TOOLS);
  assert.doesNotMatch(source,/domain_tools|personal_data_domains|coreRemember|domain-config/);
  const imports=[...source.matchAll(/(?:from\s*|import\s*\()(['"])([^'"]+)\1/g)].map(match=>match[2]);
  assert.deepEqual(imports,['node:fs','node:path','node:http']);
});

for(const [label,pick] of [['candidate',()=>({server:candidate,oauth:candidateOauth})],['mainline',()=>({server:mainServer,oauth:mainOauth})]]) {
  test(`HR1 ${label}: Claude, ChatGPT, Antigravity and Sesame read live heart rate (G1: Gemini too)`,{timeout:60000},async t=>{
    const {stateDir}=fixture(t);
    for(const frontend of ['claude_web','chatgpt_web','antigravity','sesame','gemini_web']) {
      const {app,rpc,call}=await start(t,{...pick(),stateDir,frontend});
      const listed=(await rpc('tools/list')).result.tools.filter(tool=>tool.name==='heart_rate');
      assert.equal(listed.length,1,frontend);
      assert.equal(listed[0].description,HEART_RATE_TOOLS[0].description);assert.deepEqual(listed[0].inputSchema,HEART_RATE_TOOLS[0].inputSchema);
      const empty=(await call('heart_rate',{})).structuredContent;
      assert.equal(empty.latest,null);assert.equal(empty.live,false);assert.match(empty.note,/还没有收到/);
      const post=await ingestServer(t,app.heartRate);
      const result=await post(batch(series(NOW,90,i=>i<60?70:80)));
      assert.equal(result.status,200);assert.deepEqual(result.body,{accepted:90,duplicates:0,rejected:0,latest_t:NOW-1000});
      const now=await call('heart_rate',{mode:'now'});
      assert.equal(now.isError,false);
      const value=now.structuredContent;
      assert.deepEqual(value.latest,{bpm:80,at:'2026-11-05T21:10:29+08:00',age_seconds:1,live:true});
      assert.equal(value.live,true);assert.equal(value.note,undefined);
      assert.deepEqual(value.phone,{device:'HR31 synthetic',status:'live',received_at:'2026-11-05T21:10:30+08:00'});
      assert.deepEqual(value.windows['1m'],{median:80,min:70,max:80,samples:59});
      assert.deepEqual(value.windows['5m'],{median:70,min:70,max:80,samples:90});
      assert.ok(value.trend_5m.length>=3);assert.equal(value.trend_5m.at(-1).bpm,80);
      assert.equal(value.usual_this_hour,null);
      const bad=await call('heart_rate',{mode:'week'});
      assert.equal(bad.isError,true);assert.equal(bad.structuredContent.error.code,'invalid_heart_rate_mode');
    }
  });

  test(`HR1 ${label}: without heart_rate.json there is no tool and no store`,{timeout:30000},async t=>{
    const {stateDir,dataDir}=fixture(t,{withConfig:false});
    for(const frontend of ['claude_web','sesame']) {
      const {app,rpc}=await start(t,{...pick(),stateDir,frontend});
      assert.equal(app.heartRate??null,null);
      assert.equal((await rpc('tools/list')).result.tools.some(tool=>tool.name==='heart_rate'),false);
      assert.equal((await rpc('tools/call',{name:'heart_rate',arguments:{}})).error.code,-32602);
    }
    assert.equal(existsSync(dataDir),false,'no data directory is created without the config');
  });
}

test('HR1 heart_rate.json is exact; invalid config fails closed',async t=>{
  const {stateDir}=fixture(t),file=join(stateDir,'heart_rate.json');
  assert.deepEqual(loadHeartRateConfig(stateDir),{format:'heart-rate-v1',tailscale_logins:[LOGIN]});
  writeFileSync(file,'﻿'+JSON.stringify({format:'heart-rate-v1',tailscale_logins:['Owner@Example.Test']}));
  assert.deepEqual(loadHeartRateConfig(stateDir).tailscale_logins,['owner@example.test']);
  for(const bad of ['{',JSON.stringify({format:'heart-rate-v2',tailscale_logins:[LOGIN]}),JSON.stringify({format:'heart-rate-v1',tailscale_logins:[]}),
    JSON.stringify({format:'heart-rate-v1',tailscale_logins:['has space']}),JSON.stringify({format:'heart-rate-v1',tailscale_logins:[LOGIN],port:1})]) {
    writeFileSync(file,bad);
    assert.throws(()=>loadHeartRateConfig(stateDir),/heart_rate_config_invalid/);
    assert.throws(()=>mainServer.createApp({stateDir,publicUrl:PUBLIC_URL,getReadModel:async()=>createFakeReadModel()}),/heart_rate_config_invalid/);
  }
});

test('HR1 ingest: only listed Tailscale logins, bounded bodies, strict shape, sane samples',async t=>{
  const {stateDir}=fixture(t);
  let clock=NOW;
  const heartRate=createHeartRateDomainTools({stateDir,now:()=>clock});
  const post=await ingestServer(t,heartRate);
  assert.deepEqual(await post(batch(series(NOW,3,70)),{login:null}),{status:401,body:{error:'unauthorized'}});
  assert.deepEqual(await post(batch(series(NOW,3,70)),{login:'someone@example.test'}),{status:403,body:{error:'forbidden'}});
  assert.deepEqual(await post(null,{method:'GET',path:'/v1/heart-rate/health',login:'OWNER@example.test'}),{status:200,body:{ok:true,format:'hr-samples-v1'}});
  assert.equal((await post(null,{method:'GET'})).status,405);
  assert.equal((await post(batch([]),{path:'/v1/other'})).status,404);
  assert.deepEqual(await post(null,{raw:'{'}),{status:400,body:{error:'invalid_request'}});
  assert.deepEqual(await post(null,{raw:'x'.repeat(17*1024)}),{status:413,body:{error:'too_large'}});
  for(const body of [batch([]),{...batch(series(NOW,1,70)),format:'v0'},{...batch(series(NOW,1,70)),extra:1},batch([{t:NOW-1000,bpm:70.5}]),
    batch([{t:NOW-1000,bpm:70,rr:[0.8]}]),batch(series(NOW,301,70)),batch(series(NOW,1,70),{status:'live now'}),batch(series(NOW,1,70),{device:'a\nb'})]) {
    assert.deepEqual(await post(body),{status:400,body:{error:'invalid_request'}});
  }
  assert.equal(heartRate.store.nowPayload().latest,null,'a rejected batch stores nothing');
  const mixed=await post(batch([{t:NOW-25*3600000,bpm:70},{t:NOW+2*60000,bpm:70},{t:NOW-3000,bpm:29},{t:NOW-3000,bpm:221},
    {t:NOW-3000,bpm:72},{t:NOW-3000,bpm:73},{t:NOW-4000,bpm:74},{t:NOW-2000,bpm:75}]));
  assert.deepEqual(mixed.body,{accepted:2,duplicates:2,rejected:4,latest_t:NOW-2000});
  assert.deepEqual(heartRate.store.nowPayload().windows['1m'],{median:73.5,min:72,max:75,samples:2});
  clock=NOW+60000;
  const stale=await heartRate.handlers.heart_rate({});
  assert.equal(stale.live,false);assert.equal(stale.latest.live,false);assert.equal(stale.latest.age_seconds,62);
  assert.match(stale.note,/没有实时数据/);
  await assert.rejects(heartRate.handlers.heart_rate({mode:'now',start:'x'}),error=>error instanceof DomainToolInputError&&error.message==='invalid_request');
});

test('HR1 minutes are persisted per local day, merged with the open minute and pruned after 14 days',async t=>{
  const {stateDir,dataDir}=fixture(t);
  mkdirSync(dataDir);
  writeMinutes(dataDir,'2026-10-20',[{ms:at('2026-10-20T21:00:00+08:00'),n:60,med:66,min:64,max:70}]);
  writeMinutes(dataDir,'2026-10-22',[{ms:at('2026-10-22T21:00:00+08:00'),n:60,med:66,min:64,max:70}]);
  let clock=at('2026-11-05T23:59:20+08:00');
  const store=createHeartRateStore({stateDir,now:()=>clock});
  assert.equal(existsSync(minuteFile(dataDir,'2026-10-20')),false,'older than 14 days is pruned');
  assert.equal(existsSync(minuteFile(dataDir,'2026-10-22')),true);
  // 23:58:00–23:59:19 then 00:00:00–00:00:09 across local midnight.
  store.ingest(batch(series(at('2026-11-05T23:59:20+08:00'),80,i=>60+(i%5))));
  clock=at('2026-11-06T00:00:10+08:00');
  store.ingest(batch(series(clock,10,90)));
  const today=readFileSync(minuteFile(dataDir,'2026-11-05'),'utf8').trim().split('\n').map(line=>JSON.parse(line));
  assert.deepEqual(today.map(row=>[row.n,row.med,row.min,row.max]),[[60,62,60,64],[20,62,60,64]]);
  assert.equal(existsSync(minuteFile(dataDir,'2026-11-06')),false,'open minute is not written yet');
  const range=store.rangePayload({start:'2026-11-05T23:58:00+08:00',end:'2026-11-06T00:01:00+08:00'});
  assert.equal(range.covered_minutes,3);
  assert.deepEqual(range.minutes.map(row=>[row.at,row.samples,row.median,row.partial??false]),
    [['2026-11-05T23:58:00+08:00',60,62,false],['2026-11-05T23:59:00+08:00',20,62,false],['2026-11-06T00:00:00+08:00',10,90,true]]);
  clock+=80000;store.tick();
  assert.equal(readFileSync(minuteFile(dataDir,'2026-11-06'),'utf8'),JSON.stringify({ms:at('2026-11-06T00:00:00+08:00'),n:10,med:90,min:90,max:90})+'\n');
  // After a restart the same minute may be written twice; the larger row wins.
  writeFileSync(minuteFile(dataDir,'2026-11-06'),readFileSync(minuteFile(dataDir,'2026-11-06'),'utf8')+JSON.stringify({ms:at('2026-11-06T00:00:00+08:00'),n:3,med:50,min:50,max:50})+'\nnot json\n');
  assert.deepEqual(store.rangePayload({start:'2026-11-06T00:00:00+08:00',end:'2026-11-06T00:01:00+08:00'}).minutes,
    [{at:'2026-11-06T00:00:00+08:00',median:90,min:90,max:90,samples:10}]);
  for(const args of [{start:'2026-11-06T00:00:00'},{start:'2026-11-06T01:00:00+08:00',end:'2026-11-06T00:00:00+08:00'},
    {start:'2026-11-05T00:00:00+08:00',end:'2026-11-05T12:00:01+08:00'},{start:'2026-11-07T00:00:00+08:00',end:'2026-11-07T01:00:00+08:00'}]) {
    assert.throws(()=>store.rangePayload(args),/invalid_heart_rate_range/);
  }
});

test('HR1 night summary covers 18:00–12:00 in 5-minute blocks with the lowest 30 minutes; usual level uses the past 7 days',t=>{
  const {stateDir,dataDir}=fixture(t);
  mkdirSync(dataDir);
  const rows=(date,from,count,med)=>Array.from({length:count},(_,i)=>({ms:at(`${date}T${from}:00+08:00`)+i*60000,n:60,med:typeof med==='function'?med(i):med,min:50,max:99}));
  writeMinutes(dataDir,'2026-11-03',[...rows('2026-11-03','17:50',5,90),...rows('2026-11-03','23:00',60,72)]);
  writeMinutes(dataDir,'2026-11-04',[...rows('2026-11-04','03:00',60,i=>i<30?64:68),...rows('2026-11-04','12:00',5,88),...rows('2026-11-04','21:00',30,75)]);
  const store=createHeartRateStore({stateDir,now:()=>NOW});
  const night=store.nightPayload({night:'2026-11-03'});
  assert.equal(night.window_start,'2026-11-03T18:00:00+08:00');assert.equal(night.window_end,'2026-11-04T12:00:00+08:00');
  assert.equal(night.covered_minutes,120);
  assert.equal(night.first_minute,'2026-11-03T23:00:00+08:00');assert.equal(night.last_minute,'2026-11-04T03:59:00+08:00');
  assert.equal(night.blocks_5m.length,24);
  assert.deepEqual(night.blocks_5m[0],{at:'2026-11-03T23:00:00+08:00',median:72,min:50,max:99,minutes:5});
  assert.deepEqual(night.lowest_30m,{start:'2026-11-04T03:00:00+08:00',mean:64,minutes:30});
  assert.deepEqual(store.nightPayload({night:'2026-10-01'}),{night:'2026-10-01',window_start:'2026-10-01T18:00:00+08:00',
    window_end:'2026-10-02T12:00:00+08:00',covered_minutes:0,first_minute:null,last_minute:null,blocks_5m:[],lowest_30m:null});
  assert.throws(()=>store.nightPayload({night:'2026-02-30'}),/invalid_heart_rate_night/);
  // NOW is 21:10 on 11-05: the 21:00 hour on 11-04 has 30 minutes at 75.
  assert.deepEqual(store.nowPayload().usual_this_hour,{median:75,days:1,minutes:30});
  const {handlers}=createHeartRateTools({store});
  return Promise.all([
    assert.rejects(handlers.heart_rate({mode:'night'}),/invalid_heart_rate_night/),
    assert.rejects(handlers.heart_rate({mode:'night',night:'2026-11-03',start:'x'}),/invalid_request/),
    assert.rejects(handlers.heart_rate([]),/invalid_request/),
  ]);
});

test('HR1 never follows links for the data directory or minute files',{skip:process.platform==='win32'&&'symlink privileges vary on Windows'},t=>{
  const {base,stateDir,dataDir}=fixture(t);
  const outside=join(base,'outside');mkdirSync(outside);
  symlinkSync(outside,dataDir,'dir');
  assert.throws(()=>createHeartRateStore({stateDir,now:()=>NOW}),/heart_rate_dir_invalid/);
  rmSync(dataDir);mkdirSync(dataDir);
  const target=join(outside,'target.jsonl');writeFileSync(target,'');
  symlinkSync(target,minuteFile(dataDir,'2026-11-05'));
  const store=createHeartRateStore({stateDir,now:()=>NOW});
  store.ingest(batch(series(NOW-60000,30,70)));
  store.ingest(batch(series(NOW,5,71)));
  assert.equal(readFileSync(target,'utf8'),'','a linked minute file is never written');
  assert.equal(store.rangePayload({start:'2026-11-05T21:00:00+08:00',end:'2026-11-05T21:12:00+08:00'}).minutes.length,1,'only the open minute is visible');
  assert.deepEqual(readdirSync(dataDir),['minutes-2026-11-05.jsonl']);
});
