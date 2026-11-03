import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {existsSync, mkdirSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {after, before, test} from 'node:test';
import {buildChatgptCandidate, REPO_ROOT} from './chatgpt_candidate.mjs';
import {STUDY_TOOLS, createStudyTools, loadStudyConfig} from './study_tools.mjs';
import {createStudyDomainTools, DomainToolInputError} from './domain_tools.mjs';
import * as mainServer from './server.mjs';
import * as mainOauth from './oauth.mjs';
import {createFakeReadModel, PASSPHRASE, PUBLIC_URL, pkcePair, registerClient, submitPassphrase, authorizeParams, postToken, initSession, mcpPost} from './fixtures.mjs';
import {listenForFetch} from './fetch_test_listener.mjs';

const root=join(REPO_ROOT,'build','study-tools-test-'+randomUUID());
const NOW=Date.parse('2026-11-03T10:20:30+08:00');
let built, candidate, candidateOauth;
before(async()=>{
  mkdirSync(root,{recursive:true});
  built=buildChatgptCandidate({outputDirectory:join('build','study-tools-test-'+randomUUID())});
  const load=name=>import(pathToFileURL(join(built.root,'i_remote_mcp',name+'.mjs')));
  [candidate,candidateOauth]=await Promise.all([load('server'),load('oauth')]);
});
after(()=>{rmSync(root,{recursive:true,force:true});if(built)rmSync(built.outputRoot,{recursive:true,force:true});});

const TODAY=['# 学习单 2026-11-03 日语 · 英语 · 数据分析','预计：共 105 分钟（日语 25，英语 35，数据分析 45）','',
  '## 日语（25 分钟）','先打开：《动词て形》','### 复习（共 1 个）','1. て形接续','',
  '## 英语（35 分钟）','### 新学（共 1 个）','1. present perfect','',
  '## 数据分析（45 分钟）','### 新学（共 1 个）','1. SQL GROUP BY',''].join('\r\n');
const SOURCES={pulled_at:'2026-11-02T22:30:00.000Z',sources:[
  {title:'动词て形',url:'https://example.feishu.cn/docx/synthetic',document:{content:'て'.repeat(25000)}},
  {title:'SQL 基础',document:{content:'SELECT 1'}},
]};
const row=(fields)=>({record_id:'rec'+randomUUID().slice(0,8),fields,snapshot:{}});
const LEDGER={pulled_at:'2026-11-02T22:30:00.000Z',records:[
  row({知识点:'て形接续',科目:'日语',掌握度:'模糊',错次:3,下次复习:'2026-11-03'}),
  row({知识点:'ない形',科目:'日语',掌握度:'掌握',错次:1,下次复习:'2026-11-09'}),
  row({知识点:'可能形',科目:'日语',掌握度:'未学',错次:0,下次复习:'2026-11-01'}),
  row({知识点:'GROUP BY',科目:'数据分析',掌握度:'未学',错次:0,下次复习:null}),
],practice:[
  row({时间:'2026-11-02T20:00:00+08:00',知识点:'て形接续',科目:'日语',结果:'对'}),
  row({时间:'2026-11-01T20:00:00+08:00',知识点:'て形接续',科目:'日语',结果:'错'}),
  row({时间:'2026-10-28T00:01:00+08:00',知识点:'ない形',科目:'日语',结果:'不会'}),
  row({时间:'2026-10-20T20:00:00+08:00',知识点:'ない形',科目:'日语',结果:'对'}),
]};
const RESULT='【学习结果】2026-11-03 日语\n- 知识点：て形接续 | 结果：对 | 备注：无\n口语：没做 | 备注：无\n纠正：\n无\n新发现的问题：无';

function studyFixture(t,{withConfig=true}={}) {
  const base=join(root,randomUUID()),studyDir=join(base,'study'),stateDir=join(base,'state');
  for(const dir of [join(studyDir,'state'),join(studyDir,'inbox','done'),stateDir])mkdirSync(dir,{recursive:true});
  writeFileSync(join(studyDir,'today.md'),'﻿'+TODAY);
  writeFileSync(join(studyDir,'state','sources.json'),JSON.stringify(SOURCES));
  writeFileSync(join(studyDir,'state','ledger.json'),JSON.stringify(LEDGER));
  writeFileSync(join(studyDir,'state','inbox.json'),'{"secret":"not exposed"}');
  if(withConfig)writeFileSync(join(stateDir,'study.json'),JSON.stringify({format:'study-v1',study_dir:studyDir}));
  t.after(()=>rmSync(base,{recursive:true,force:true}));
  return {base,studyDir,stateDir};
}
const inboxFiles=studyDir=>readdirSync(join(studyDir,'inbox')).filter(name=>name.endsWith('.md'));
function link(target,path,dir) {
  symlinkSync(target,path,dir&&process.platform==='win32'?'junction':dir?'dir':'file');
}

const callbacks={claude_web:'https://claude.ai/api/mcp/auth_callback',chatgpt_web:'https://chatgpt.com/connector_platform_oauth_redirect',
  antigravity:'http://127.0.0.1:32014/oauth/callback',gemini_web:'https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-synthetic-study',
  sesame:'https://sesameai.app/api/oauth/external-mcp/callback'};
async function start(t,{server,oauth,stateDir,frontend}) {
  oauth.setPassphrase(stateDir,PASSPHRASE);
  const app=server.createApp({stateDir,publicUrl:PUBLIC_URL,getReadModel:async()=>createFakeReadModel(),now:()=>NOW,
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
  return {rpc,call:async(name,args)=>(await rpc('tools/call',{name,arguments:args})).result};
}
const names=STUDY_TOOLS.map(tool=>tool.name);

test('ST1 candidate inlines study_tools.mjs verbatim and keeps the frozen dependency closure',()=>{
  const server=readFileSync(join(built.root,'i_remote_mcp','server.mjs'),'utf8').replaceAll('\r\n','\n');
  const source=readFileSync(new URL('./study_tools.mjs',import.meta.url),'utf8').replaceAll('\r\n','\n');
  assert.equal(server.split(source).length,2,'study_tools.mjs must appear exactly once, byte for byte');
  assert.deepEqual(candidate.STUDY_TOOLS,STUDY_TOOLS);
  assert.doesNotMatch(source,/domain_tools|personal_data_domains|coreRemember|domain-config/);
  const imports=[...source.matchAll(/(?:from\s*|import\s*\()(['"])([^'"]+)\1/g)].map(match=>match[2]);
  assert.deepEqual(imports,['node:fs','node:path']);
});

for(const [label,pick] of [['candidate',()=>({server:candidate,oauth:candidateOauth})],['mainline',()=>({server:mainServer,oauth:mainOauth})]]) {
  test(`ST1 ${label}: Claude and ChatGPT get four study tools; Gemini, Antigravity and Sesame get none`,{timeout:60000},async t=>{
    const {studyDir,stateDir}=studyFixture(t);
    for(const frontend of ['claude_web','chatgpt_web']) {
      const app=await start(t,{...pick(),stateDir,frontend});
      const listed=(await app.rpc('tools/list')).result.tools;
      assert.deepEqual(listed.filter(tool=>tool.name.startsWith('study_')).map(tool=>tool.name),names);
      for(const tool of STUDY_TOOLS) {
        const actual=listed.find(item=>item.name===tool.name);
        assert.equal(actual.description,tool.description);assert.deepEqual(actual.inputSchema,tool.inputSchema);
      }
      const today=await app.call('study_today',{subject:'英语'});
      assert.equal(today.isError,false);
      assert.deepEqual({...today.structuredContent,content:undefined,header:undefined},{date:'2026-11-03',today:'2026-11-03',is_today:true,
        subjects:['日语','英语','数据分析'],subject:'英语',content:undefined,header:undefined});
      assert.match(today.structuredContent.content,/^## 英语（35 分钟）\n/);assert.doesNotMatch(today.structuredContent.content,/日语|数据分析/);
      assert.match(today.structuredContent.header,/^# 学习单 2026-11-03/);
      const whole=(await app.call('study_today',{})).structuredContent;
      assert.equal(whole.content,TODAY.replaceAll('\r\n','\n').trimEnd());
      const missing=await app.call('study_today',{subject:'法语'});
      assert.equal(missing.isError,true);assert.equal(missing.structuredContent.error.code,'study_subject_not_found');
      const list=(await app.call('study_source',{})).structuredContent;
      assert.deepEqual(list.sources,[{title:'动词て形',url:'https://example.feishu.cn/docx/synthetic',chars:25000},{title:'SQL 基础',url:null,chars:8}]);
      const first=(await app.call('study_source',{title:'动词て形'})).structuredContent;
      assert.equal([...first.content].length,20000);assert.equal(first.next_offset,20000);assert.equal(first.total_chars,25000);
      const rest=(await app.call('study_source',{title:'动词て形',offset:20000})).structuredContent;
      assert.equal([...rest.content].length,5000);assert.equal(rest.next_offset,null);
      assert.equal((await app.call('study_source',{title:'不存在'})).structuredContent.error.code,'study_source_not_found');
      const progress=(await app.call('study_progress',{})).structuredContent;
      assert.equal(progress.today,'2026-11-03');assert.equal(progress.pulled_at,LEDGER.pulled_at);
      const ja=progress.subjects.find(item=>item.subject==='日语');
      assert.deepEqual(ja,{subject:'日语',total:3,mastery:{掌握:1,模糊:1,未学:1},due_today:2,last_7_days:{answered:3,correct:1,accuracy:0.333},
        weak_points:[{知识点:'て形接续',错次:3,掌握度:'模糊',下次复习:'2026-11-03'},{知识点:'ない形',错次:1,掌握度:'掌握',下次复习:'2026-11-09'}]});
      assert.deepEqual((await app.call('study_progress',{subject:'数据分析'})).structuredContent.subjects.map(item=>item.subject),['数据分析']);
      const before=inboxFiles(studyDir);
      const written=await app.call('study_result',{content:RESULT});
      assert.equal(written.isError,false);
      const short=frontend==='claude_web'?'claude':'chatgpt',name=`2026-11-03-102030-${short}.md`;
      assert.deepEqual(written.structuredContent,{written:true,file:'inbox/'+name,chars:[...RESULT].length});
      assert.deepEqual(inboxFiles(studyDir).sort(),[...before,name].sort());
      assert.equal(readFileSync(join(studyDir,'inbox',name),'utf8'),RESULT+'\n');
      const again=await app.call('study_result',{content:RESULT+'\n改了'});
      assert.equal(again.isError,true);assert.equal(again.structuredContent.error.code,'study_result_exists');
      assert.equal(readFileSync(join(studyDir,'inbox',name),'utf8'),RESULT+'\n','existing result is never overwritten');
      for(const [content,code] of [['今天练了日语','invalid_study_result_header'],['【学习结果】2026-13-03 日语','invalid_study_result_header'],
        ['【学习结果】2026-11-03 日语\n'+'字'.repeat(8000),'study_result_too_long'],['【学习结果】2026-11-03 日语\u0000','invalid_study_result']]) {
        const bad=await app.call('study_result',{content});
        assert.equal(bad.isError,true);assert.equal(bad.structuredContent.error.code,code);
      }
      const extra=await app.call('study_today',{path:'../state/inbox.json'});
      assert.equal(extra.isError,true);assert.equal(extra.structuredContent.error.code,'invalid_request');
    }
    for(const frontend of ['gemini_web','antigravity','sesame']) {
      const app=await start(t,{...pick(),stateDir,frontend});
      assert.equal((await app.rpc('tools/list')).result.tools.some(tool=>tool.name.startsWith('study_')),false);
      for(const name of names)assert.equal((await app.rpc('tools/call',{name,arguments:{}})).error.code,-32602);
    }
    assert.equal(inboxFiles(studyDir).length,2);
  });

  test(`ST1 ${label}: without study.json no study tool is listed`,{timeout:30000},async t=>{
    const {stateDir}=studyFixture(t,{withConfig:false});
    for(const frontend of ['claude_web','chatgpt_web']) {
      const app=await start(t,{...pick(),stateDir,frontend});
      assert.equal((await app.rpc('tools/list')).result.tools.some(tool=>tool.name.startsWith('study_')),false);
      assert.equal((await app.rpc('tools/call',{name:'study_today',arguments:{}})).error.code,-32602);
    }
  });
}

test('ST1 study.json is exact, absolute and canonical; invalid config fails closed',async t=>{
  const {studyDir,stateDir}=studyFixture(t),file=join(stateDir,'study.json');
  assert.deepEqual(loadStudyConfig(stateDir),{format:'study-v1',study_dir:studyDir});
  writeFileSync(file,'﻿'+JSON.stringify({format:'study-v1',study_dir:studyDir}));assert.equal(loadStudyConfig(stateDir).study_dir,studyDir);
  for(const value of [{format:'study-v1',study_dir:studyDir,extra:1},{format:'study-v2',study_dir:studyDir},{format:'study-v1',study_dir:'relative/study'},
    {format:'study-v1',study_dir:studyDir+'/../study'},{format:'study-v1'},null,[],'x']) {
    writeFileSync(file,JSON.stringify(value));
    assert.throws(()=>loadStudyConfig(stateDir),/^Error: study_config_invalid$/);
    assert.throws(()=>candidate.loadStudyConfig(stateDir),/^Error: study_config_invalid$/);
    assert.throws(()=>candidate.createApp({stateDir,publicUrl:PUBLIC_URL,getReadModel:async()=>({})}),/study_config_invalid/);
    assert.throws(()=>mainServer.createApp({stateDir,publicUrl:PUBLIC_URL,getReadModel:async()=>({})}),/study_config_invalid/);
  }
  writeFileSync(file,'{');
  const result=await new Promise((resolve,reject)=>{
    const env=Object.fromEntries(Object.entries(process.env).filter(([key])=>!/^(I_|NODE_OPTIONS$|NODE_PATH$)/i.test(key)));
    const child=spawn(process.execPath,[built.entryPath,'serve','--state-dir',stateDir,'--port','0'],{env,windowsHide:true});
    let stderr='';const timer=setTimeout(()=>{child.kill();reject(new Error('timeout'));},15000);
    child.stderr.on('data',chunk=>stderr+=chunk);child.on('close',code=>{clearTimeout(timer);resolve({code,stderr});});
  });
  assert.equal(result.code,1);assert.match(result.stderr,/study_config_invalid/);
  rmSync(file);assert.equal(loadStudyConfig(stateDir),null);assert.equal(createStudyDomainTools({stateDir}),null);
});

test('ST1 reads only the three fixed files and refuses links, junctions and aliases',async t=>{
  const {base,studyDir}=studyFixture(t);
  const tools=createStudyTools({studyDir,frontend:'claude_web',now:()=>NOW}).handlers;
  const code=async(promise,expected)=>{await assert.rejects(promise,error=>error.message===expected);};
  const outside=join(base,'outside');mkdirSync(join(outside,'state'),{recursive:true});
  writeFileSync(join(outside,'today.md'),'# 学习单 2026-11-03 外部');writeFileSync(join(outside,'state','ledger.json'),JSON.stringify(LEDGER));
  // Symlinked file.
  rmSync(join(studyDir,'today.md'));
  let fileLinks=true;
  try{link(join(outside,'today.md'),join(studyDir,'today.md'),false);}catch(error){if(process.platform!=='win32')throw error;fileLinks=false;}
  if(fileLinks)await code(tools.study_today({}),'study_path_forbidden');
  rmSync(join(studyDir,'today.md'),{force:true});
  await code(tools.study_today({}),'study_file_missing');
  // A directory in place of a file.
  mkdirSync(join(studyDir,'today.md'));await code(tools.study_today({}),'study_path_forbidden');rmSync(join(studyDir,'today.md'),{recursive:true});
  // Symlinked / junction state directory.
  rmSync(join(studyDir,'state'),{recursive:true});link(join(outside,'state'),join(studyDir,'state'),true);
  await code(tools.study_progress({}),'study_path_forbidden');
  await code(tools.study_source({}),'study_path_forbidden');
  rmSync(join(studyDir,'state'),{recursive:true,force:true});mkdirSync(join(studyDir,'state'));
  writeFileSync(join(studyDir,'state','ledger.json'),'not json');await code(tools.study_progress({}),'study_snapshot_invalid');
  writeFileSync(join(studyDir,'state','sources.json'),'x'.repeat(32*1024*1024+1));await code(tools.study_source({}),'study_file_too_large');
  // Inbox: junction rejected, missing inbox is not created.
  rmSync(join(studyDir,'inbox'),{recursive:true});link(outside,join(studyDir,'inbox'),true);
  await code(tools.study_result({content:RESULT}),'study_path_forbidden');
  assert.deepEqual(readdirSync(outside).sort(),['state','today.md'],'nothing written through the link');
  rmSync(join(studyDir,'inbox'),{recursive:true,force:true});
  await code(tools.study_result({content:RESULT}),'study_file_missing');assert.equal(existsSync(join(studyDir,'inbox')),false);
  // The study root itself as a link.
  const alias=join(base,'alias');link(studyDir,alias,true);
  const aliased=createStudyTools({studyDir:alias,frontend:'chatgpt_web',now:()=>NOW}).handlers;
  await code(aliased.study_today({}),'study_path_forbidden');
  await code(createStudyTools({studyDir:join(base,'nope'),frontend:'claude_web'}).handlers.study_today({}),'study_dir_unavailable');
  assert.throws(()=>createStudyTools({studyDir,frontend:'gemini_web'}),/invalid_study_configuration/);
  assert.throws(()=>createStudyTools({studyDir,frontend:'sesame'}),/invalid_study_configuration/);
});

test('ST1 stale study sheet reports its own date and mainline errors are structured',async t=>{
  const {stateDir,studyDir}=studyFixture(t);
  const later=createStudyTools({studyDir,frontend:'claude_web',now:()=>NOW+86400000}).handlers;
  const stale=await later.study_today({subject:'日语'});
  assert.equal(stale.date,'2026-11-03');assert.equal(stale.today,'2026-11-04');assert.equal(stale.is_today,false);
  const wrapped=createStudyDomainTools({stateDir,now:()=>NOW});
  assert.deepEqual(Object.keys(wrapped),['claude_web','chatgpt_web']);
  await assert.rejects(wrapped.chatgpt_web.handlers.study_today({subject:'法语'}),error=>error instanceof DomainToolInputError&&error.message==='study_subject_not_found');
  writeFileSync(join(studyDir,'today.md'),'没有标题');
  const undated=await wrapped.claude_web.handlers.study_today({});
  assert.equal(undated.date,null);assert.equal(undated.is_today,false);
});
