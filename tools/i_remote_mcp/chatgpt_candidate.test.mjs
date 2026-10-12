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

test('fixed six Git blobs produce only three reviewed changes and preserve three exact buffers',()=>{
 const {files,manifest}=constructCandidateSources(input);
 assert.equal(manifest.baseline_commit,BASELINE_COMMIT);
 assert.equal(manifest.status,'not_deployed');
 assert.deepEqual(manifest.chatgpt_flag,{name:'I_REMOTE_MCP_CHATGPT_ENABLED',default:'0'});
 assert.deepEqual(manifest.files.filter(x=>x.changed).map(x=>x.path),['i_remote_mcp/server.mjs','i_remote_mcp/oauth.mjs','i_remote_mcp/mcp.mjs']);
 for(const item of SOURCE_INVENTORY) {
  assert.equal(sha256(input.baselineFiles[item.path]),item.sha256);
  if(!/\/(server|oauth|mcp)\.mjs$/.test(item.path))assert.ok(files[item.path].equals(input.baselineFiles[item.path]));
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
 for(const name of ['server','oauth','mcp']) {
  assert.throws(()=>constructCandidateSources({...input,current:{...input.current,[name]:Buffer.concat([input.current[name],Buffer.from('// unreviewed')])}}),/unexpected current/);
  assert.throws(()=>constructCandidateSources({...input,baselineMain:{...input.baselineMain,[name]:Buffer.from('other baseline')}}),/wrong mainline baseline/);
 }
});

test('LF and CRLF checkouts yield the same pinned candidate without rewriting legacy bytes',()=>{
 const lf={...input,current:Object.fromEntries(Object.entries(input.current).map(([k,v])=>[k,Buffer.from(v.toString().replaceAll('\r\n','\n'))]))};
 const a=constructCandidateSources(input),b=constructCandidateSources(lf);
 for(const item of SOURCE_INVENTORY)assert.ok(a.files[item.path].equals(b.files[item.path]));
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