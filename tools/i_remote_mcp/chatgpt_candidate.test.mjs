import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { setTimeout as delay } from 'node:timers/promises';
import test from 'node:test';
import {
 BASELINE_COMMIT, REPO_ROOT, SOURCE_INVENTORY, buildChatgptCandidate,
 constructCandidateSources, readCandidateInputs, sha256, validateOutputDirectory,
} from './chatgpt_candidate.mjs';
import {
 createSyntheticReaderState, legacyReaderEnvironment, legacyReaderCliArgs,
 allocateSyntheticLoopbackPort, syntheticHttpRequest, mcpPost,
} from '../i_core/test_fixtures/release_schema6/mcp_reader/helper.mjs';

const input=readCandidateInputs();
const callback='https://chatgpt.com/connector_platform_oauth_redirect';
const newOutput=()=>join(REPO_ROOT,'build','chatgpt-candidate-test-'+randomUUID());
function candidate(t) {
 const outputDirectory=newOutput();
 const result=buildChatgptCandidate({outputDirectory});
 t.after(()=>rmSync(outputDirectory,{recursive:true,force:true}));
 return result;
}
function allFiles(root,prefix='') {
 return readdirSync(join(root,prefix),{withFileTypes:true}).flatMap(entry=>entry.isDirectory()
  ?allFiles(root,prefix+entry.name+'/'):[prefix+entry.name]).sort();
}

test('fixed six Git blobs produce only five reviewed changes and preserve one exact buffer',()=>{
 const {files,manifest}=constructCandidateSources(input);
 assert.equal(manifest.baseline_commit,BASELINE_COMMIT);
 assert.equal(manifest.status,'not_deployed');
 assert.equal(manifest.changed_files,5);
 assert.equal(manifest.unchanged_files,1);
 assert.deepEqual(manifest.chatgpt_flag,{name:'I_REMOTE_MCP_CHATGPT_ENABLED',default:'0'});
 assert.deepEqual(manifest.files.filter(x=>x.changed).map(x=>x.path),['i_remote_mcp/server.mjs','i_remote_mcp/oauth.mjs','i_remote_mcp/diagnostics.mjs','i_remote_mcp/mcp.mjs','i_remote_mcp/writeback.mjs']);
 for(const item of SOURCE_INVENTORY) {
  assert.equal(sha256(input.baselineFiles[item.path]),item.sha256);
  if(!/\/(server|oauth|diagnostics|mcp|writeback)\.mjs$/.test(item.path))assert.ok(files[item.path].equals(input.baselineFiles[item.path]));
 }
 assert.equal(files['i_remote_mcp/oauth.mjs'].toString().replaceAll('\r\n','\n'),input.current.oauth.toString().replaceAll('\r\n','\n'));
 assert.ok(!files['i_remote_mcp/oauth.mjs'].toString().replaceAll('\r\n','').includes('\n'),'OAuth candidate retains original CRLF');
 assert.match(files['i_remote_mcp/mcp.mjs'].toString(),/在当前客户端的连接器设置里/);
 assert.doesNotMatch(files['i_remote_mcp/mcp.mjs'].toString(),/在 claude.ai 的 connector 设置里|coreRemember|domain_tools/);
 const server=files['i_remote_mcp/server.mjs'].toString();
 assert.doesNotMatch(server,/domain_tools|domain-config|coreRemember|createWebDomainOptions/);
 assert.match(server,/phonePort: 47862/);
 assert.match(server,/const phoneTokenHash = writeback \? loadPhoneTokenHash\(stateDir\) : null/);
});

test('construction fails closed for a wrong baseline, altered blob, extra file or unreviewed delta',()=>{
 assert.throws(()=>constructCandidateSources({...input,baselineCommit:'bad'}),/wrong baseline/);
 const path='i_remote_mcp/mcp.mjs';
 assert.throws(()=>constructCandidateSources({...input,baselineFiles:{...input.baselineFiles,[path]:Buffer.from('tampered')}}),/baseline byte mismatch/);
 assert.throws(()=>constructCandidateSources({...input,baselineFiles:{...input.baselineFiles,'i_remote_mcp/domain_tools.mjs':Buffer.from('extra')}}),/exact six-file/);
 for(const name of ['server','oauth','mcp','writeback']) {
  assert.throws(()=>constructCandidateSources({...input,current:{...input.current,[name]:Buffer.concat([input.current[name],Buffer.from('// unreviewed')])}}),/unexpected current/);
  assert.throws(()=>constructCandidateSources({...input,baselineMain:{...input.baselineMain,[name]:Buffer.from('other baseline')}}),/wrong mainline baseline/);
 }
});

test('registry candidate has six files, five changes and no extra callback or Claude fallback', () => {
 const {files,manifest}=constructCandidateSources(input); // Includes both forward/reverse byte checks.
 assert.equal(Object.keys(files).length,6);
 assert.equal(manifest.changed_files,5);
 for(const bytes of Object.values(files)) {
  assert.doesNotMatch(bytes.toString(),/I_REMOTE_MCP_EXTRA_REDIRECT_URIS|extraRedirectUris/);
  assert.doesNotMatch(bytes.toString(),/return redirectUri === CHATGPT_CALLBACK_URI \? 'chatgpt_web' : 'claude_web'|\? 'chatgpt_web'\s*: 'claude_web'/);
 }
 const oauth=files['i_remote_mcp/oauth.mjs'].toString();
 assert.match(oauth,/export const FRONTEND_CALLBACKS = Object\.freeze/);
 assert.doesNotMatch(oauth,/frontend = 'claude_web'|record\.frontend \?\?/);
 const server=files['i_remote_mcp/server.mjs'].toString();
 assert.doesNotMatch(server,/auth\.frontend === 'chatgpt_web' \? chatgpt(?:Handlers|Tools) :/);
 assert.match(server,/if \(auth\.frontend === 'claude_web'\)/);
 assert.match(server,/else if \(auth\.frontend === 'chatgpt_web'\)/);
 assert.match(server,/return sendJson\(res, 401, \{ error: 'invalid_token' \}\)/);
});

test('LF and CRLF checkouts yield the same pinned candidate without rewriting legacy bytes',()=>{
 const lf={...input,current:Object.fromEntries(Object.entries(input.current).map(([k,v])=>[k,Buffer.from(v.toString().replaceAll('\r\n','\n'))]))};
 const a=constructCandidateSources(input),b=constructCandidateSources(lf);
 for(const item of SOURCE_INVENTORY)assert.ok(a.files[item.path].equals(b.files[item.path]));
});

test('Gemini candidate preserves diagnostics CRLF and guards its current and baseline bytes', () => {
 const { files, manifest } = constructCandidateSources(input);
 const path = 'i_remote_mcp/diagnostics.mjs';
 assert.equal(files[path].toString().replaceAll('\r\n','\n'), input.current.diagnostics.toString().replaceAll('\r\n','\n'));
 assert.ok(!files[path].toString().replaceAll('\r\n','').includes('\n'), 'diagnostics candidate retains original CRLF');
 assert.equal(manifest.source_sha256.diagnostics, sha256(input.current.diagnostics));
 assert.throws(() => constructCandidateSources({ ...input, current: { ...input.current,
  diagnostics: Buffer.concat([input.current.diagnostics, Buffer.from('// unreviewed')]) } }), /unexpected current diagnostics/);
 assert.throws(() => constructCandidateSources({ ...input, baselineMain: { ...input.baselineMain,
  diagnostics: Buffer.from('other baseline') } }), /wrong mainline baseline/);
 assert.throws(() => constructCandidateSources({ ...input, baselineFiles: { ...input.baselineFiles,
  [path]: Buffer.from('tampered diagnostics') } }), /baseline byte mismatch/);
 for (const name of ['server', 'oauth', 'writeback']) assert.match(files[`i_remote_mcp/${name}.mjs`].toString(), /gemini_web/);
 assert.match(files['i_remote_mcp/oauth.mjs'].toString(), /geminiEnabledFromEnv/);
 assert.match(files[path].toString(), /gemini_kept_count/);
});

test('builder separates the six-file runtime closure from manifest and refuses overwrites',t=>{
 const built=candidate(t);
 assert.equal(built.root,join(built.outputRoot,'runtime'));
 assert.equal(built.entryPath,join(built.root,'i_remote_mcp/server.mjs'));
 assert.deepEqual(allFiles(built.root),SOURCE_INVENTORY.map(x=>x.path).sort());
 assert.deepEqual(JSON.parse(readFileSync(built.manifestPath)),built.manifest);
 for(const item of built.manifest.files)assert.equal(sha256(readFileSync(join(built.root,item.path))),item.result_sha256);
 assert.throws(()=>buildChatgptCandidate({outputDirectory:built.outputRoot}),/already exists/);
});

test('output guard rejects traversal, aliases, runtime paths and links before writing',t=>{
 for(const path of [undefined,'','build','tools/candidate','build/../escape','build/foo/../../escape','build/foo.','build/NUL','build//candidate',join(tmpdir(),'candidate'),join(REPO_ROOT,'tools','i_remote_mcp','candidate')]) {
  assert.throws(()=>validateOutputDirectory(path));
 }
 const output=newOutput();mkdirSync(output,{recursive:true});
 t.after(()=>rmSync(output,{recursive:true,force:true}));
 const target=join(output,'target');mkdirSync(target);
 const link=join(output,'link');symlinkSync(target,link,process.platform==='win32'?'junction':'dir');
 assert.throws(()=>validateOutputDirectory(join(link,'candidate')),/links|aliases/);
 const dangling=join(output,'dangling');symlinkSync(join(output,'missing'),dangling,process.platform==='win32'?'junction':'dir');
 assert.throws(()=>validateOutputDirectory(join(dangling,'candidate')),/links|aliases/);
 assert.ok(!existsSync(join(target,'candidate')));
});

function seedCore(path) {
 const db=new DatabaseSync(path);
 try {db.exec(`CREATE TABLE chat_messages (
 sync_id TEXT PRIMARY KEY, origin_device_id TEXT NOT NULL, origin_sequence INTEGER NOT NULL,
 character_id TEXT NOT NULL, sender TEXT NOT NULL, content TEXT NOT NULL, created_at_ms INTEGER NOT NULL,
 message_type TEXT NOT NULL, asset_refs_json TEXT NOT NULL, addenda_json TEXT NOT NULL,
 canonical_digest TEXT NOT NULL, server_sequence INTEGER NOT NULL UNIQUE);
 INSERT INTO chat_messages VALUES ('synthetic-message','synthetic-device',1,'lin-ai','user',
 'synthetic candidate reader',1790000000000,'chat','[]','[]','synthetic-digest',1);`);}finally{db.close();}
}
async function stopOwned(child) {
 if(child.exitCode!==null||child.signalCode!==null)return;
 child.kill('SIGTERM');
 for(let n=0;n<100&&child.exitCode===null&&child.signalCode===null;n++)await delay(25);
 if(child.exitCode===null&&child.signalCode===null)child.kill('SIGKILL');
 for(let n=0;n<100&&child.exitCode===null&&child.signalCode===null;n++)await delay(25);
 assert.ok(child.exitCode!==null||child.signalCode!==null,'owned synthetic MCP must exit');
}
for(const enabled of [false,true])test('actual candidate CLI OAuth, issuer and real i_recall; ChatGPT '+(enabled?'enabled':'default off'),{timeout:25000},async t=>{
 const built=candidate(t);
 const syntheticRoot=mkdtempSync(join(tmpdir(),'synthetic-chatgpt-candidate-'));
 let child;
 try {
  const coreDbPath=join(syntheticRoot,'synthetic-core.sqlite');seedCore(coreDbPath);
  const state=createSyntheticReaderState({syntheticRoot,coreDbPath});
  const port=await allocateSyntheticLoopbackPort();const base='http://127.0.0.1:'+port;
  const env={...process.env};
  for(const key of Object.keys(env))if(/^(I_|NODE_OPTIONS$|NODE_PATH$)/i.test(key))delete env[key];
  Object.assign(env,legacyReaderEnvironment(state));
  if(enabled)env.I_REMOTE_MCP_CHATGPT_ENABLED='1';
  const args=legacyReaderCliArgs({state,port});args[0]=built.entryPath;
  child=spawn(process.execPath,args,{cwd:state.readerRoot,env,stdio:'ignore',windowsHide:true});
  let spawnError;child.on('error',error=>{spawnError=error;});
  let ready;
  for(let n=0;n<100;n++) {
   if(spawnError)throw spawnError;
   assert.equal(child.exitCode,null,'candidate process exited');
   try {ready=await syntheticHttpRequest(base,'/.well-known/oauth-authorization-server');}catch{/* starting */}
   if(ready?.status===200)break;await delay(25);
  }
  assert.equal(ready?.status,200);
  assert.equal(ready.body.issuer,base);
  assert.equal(ready.body.authorization_response_iss_parameter_supported,true);
  const register=uri=>syntheticHttpRequest(base,'/register',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({client_name:'synthetic-candidate',redirect_uris:[uri],token_endpoint_auth_method:'none'})});
  let client=await register(callback);
  assert.equal(client.status,enabled?201:400);
  let redirectUri=callback;
  if(!enabled){assert.equal(client.body.error,'invalid_redirect_uri');redirectUri='https://claude.ai/api/mcp/auth_callback';client=await register(redirectUri);assert.equal(client.status,201);}
  const verifier=randomBytes(32).toString('base64url');
  const auth=await syntheticHttpRequest(base,'/authorize',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
   body:new URLSearchParams({response_type:'code',client_id:client.body.client_id,redirect_uri:redirectUri,code_challenge:createHash('sha256').update(verifier).digest('base64url'),code_challenge_method:'S256',scope:'i.read',resource:base+'/mcp',state:'synthetic',passphrase:state.passphrase})});
  assert.equal(auth.status,302);const location=new URL(auth.headers.get('location'));
  assert.equal(location.origin,new URL(redirectUri).origin);assert.equal(location.searchParams.get('iss'),base);
  const tokenResult=await syntheticHttpRequest(base,'/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'authorization_code',code:location.searchParams.get('code'),client_id:client.body.client_id,redirect_uri:redirectUri,code_verifier:verifier,resource:base+'/mcp'})});
  assert.equal(tokenResult.status,200);const token=tokenResult.body.access_token;
  const init=await mcpPost(base,token,{jsonrpc:'2.0',id:1,method:'initialize',params:{protocolVersion:'2025-06-18',capabilities:{},clientInfo:{name:'synthetic',version:'1'}}});
  assert.equal(init.status,200);const sessionId=init.headers.get('mcp-session-id');assert.ok(sessionId);
  const initialized=await mcpPost(base,token,{jsonrpc:'2.0',method:'notifications/initialized'},{sessionId});assert.equal(initialized.status,202);
  const listed=await mcpPost(base,token,{jsonrpc:'2.0',id:2,method:'tools/list'},{sessionId});
  assert.deepEqual(listed.body.result.tools.map(x=>x.name),['i_context','i_recall']);
  const recalled=await mcpPost(base,token,{jsonrpc:'2.0',id:3,method:'tools/call',params:{name:'i_recall',arguments:{query:'synthetic'}}},{sessionId});
  assert.equal(recalled.body.result.isError,false);
  assert.equal(recalled.body.result.structuredContent.messages.items[0].content,'synthetic candidate reader');
  assert.equal(recalled.body.result.structuredContent.memory.count,1);
  for(const item of built.manifest.files)assert.equal(sha256(readFileSync(join(built.root,item.path))),item.result_sha256);
 } finally {if(child)await stopOwned(child);rmSync(syntheticRoot,{recursive:true,force:true});}
});

test('Antigravity candidate keeps the six-file closure, exact callbacks and dedicated frontend routing', async t => {
 const built=candidate(t);
 assert.equal(allFiles(built.root).length,6);
 assert.equal(built.manifest.changed_files,5);
 const { pathToFileURL } = await import('node:url');
 const oauth = await import(pathToFileURL(join(built.root,'i_remote_mcp/oauth.mjs')));
 const diagnostics = await import(pathToFileURL(join(built.root,'i_remote_mcp/diagnostics.mjs')));
 assert.deepEqual(oauth.ANTIGRAVITY_CALLBACKS, [
  'http://127.0.0.1:32014/oauth/callback', 'http://localhost:32014/oauth/callback',
 ]);
 assert.equal(oauth.antigravityEnabledFromEnv({}),true);
 assert.equal(oauth.antigravityEnabledFromEnv({I_REMOTE_MCP_ANTIGRAVITY_ENABLED:'0'}),false);
 assert.throws(()=>oauth.antigravityEnabledFromEnv({I_REMOTE_MCP_ANTIGRAVITY_ENABLED:'2'}),/invalid_antigravity_mode/);
 for (const uri of oauth.ANTIGRAVITY_CALLBACKS) {
  assert.equal(oauth.frontendForRedirectUri(uri),'antigravity');
  assert.equal(oauth.isAllowedRedirectUri(uri,true,true,false),false);
  assert.equal(diagnostics.callbackClass(uri),'antigravity');
 }
 const server=readFileSync(join(built.root,'i_remote_mcp/server.mjs'),'utf8');
 assert.match(server,/else if \(auth\.frontend === 'antigravity'\)/);
 assert.match(server,/loadFrontendCredential\(stateDir, 'antigravity'\)/);
 assert.match(server,/frontend_not_paired:antigravity/);
 assert.match(server,/antigravityWriteback\?\.close\(\)/);
 const writeback=readFileSync(join(built.root,'i_remote_mcp/writeback.mjs'),'utf8');
 assert.match(writeback,/credentialFile: 'core-frontend-antigravity\.json'/);
 const bytes=readFileSync(join(built.root,'i_remote_mcp/diagnostics.mjs'),'utf8');
 assert.ok(!bytes.replaceAll('\r\n','').includes('\n'),'Antigravity diagnostics retain CRLF');
});

test('N2b food patches change only the server candidate hash and reject source drift', () => {
 const {files,manifest}=constructCandidateSources(input);
 const pinned={
  'i_remote_mcp/server.mjs':'dfad4f7020aa50d1e725bbae0fb6ab7b343387c2e59862a4e682e7672de390f8',
  'i_remote_mcp/oauth.mjs':'7c82a07d7ec10afaea12728b71b45fcf9d80e07141994ca68a6394764d4d56bd',
  'i_remote_mcp/diagnostics.mjs':'2b461c327de8a9a0da97767249ca810c7bd4a6536cc8cf32dd94141d630ffbe0',
  'i_remote_mcp/mcp.mjs':'0ae610bfc8bee8e4dd805e7532d486f678166a4b67d0e6ec80073ccd3f409eef',
  'i_remote_mcp/writeback.mjs':'783e8fd0eabd55b61cff624e2ff4a67025374da361c4136337d3d05ceb1fcc19',
  'i_memory/i_memory_read.mjs':'cee185180b825a141b645a12ab1f1812a61b9eb7462c347465b7ac4449af4e28',
 };
 assert.equal(manifest.changed_files,5);
 assert.deepEqual(Object.keys(files).sort(),Object.keys(pinned).sort());
 for(const [path,hash] of Object.entries(pinned)) {
  assert.equal(sha256(files[path]),hash);
  if(path==='i_remote_mcp/server.mjs') {
   assert.match(files[path].toString(),/food_log/);
   assert.match(files[path].toString(),/food_day/);
   assert.doesNotMatch(files[path].toString(),/createFoodTools/);
  } else assert.doesNotMatch(files[path].toString(),/food_log|food_day|food_entries|createFoodTools/);
 }
 const server=Buffer.from(input.current.server.toString().replace('createFoodTools','unreviewedFoodTools'));
 assert.throws(()=>constructCandidateSources({...input,current:{...input.current,server}}),/unexpected current/);
});

test('N2b inline server keeps the frozen dependency closure and forbidden-source guard',()=>{
 const server=constructCandidateSources(input).files['i_remote_mcp/server.mjs'].toString();
 assert.doesNotMatch(server,/domain_tools|personal_data_domains|coreRemember|domain-config/);
 const imports=[...server.matchAll(/(?:from\s*|import\s*\()(['"])([^'"]+)\1/g)].map(match=>match[2]);
 assert.ok(imports.length>0);
 for(const name of imports)assert.ok(name.startsWith('node:')||['./oauth.mjs','./mcp.mjs','./writeback.mjs','./diagnostics.mjs'].includes(name),name);
 assert.match(server,/import\(pathToFileURL\(resolve\(REPO_TOOLS, 'i_memory\/i_memory_read\.mjs'\)\)\.href\)/);
});
