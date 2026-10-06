import assert from 'node:assert/strict';
import test, { after } from 'node:test';
import { randomBytes } from 'node:crypto';
import { existsSync, mkdtempSync, mkdirSync, readFileSync, writeFileSync, realpathSync, unlinkSync, copyFileSync, rmSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { spawn, execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { INVENTORY, cleanEnvironment, sha256, readCommittedSources, plainPath } from '../package.mjs';
import { parseConfiguration } from './configuration.mjs';
import { stateDigest, validatePrevious } from './common.mjs';
import { assertOfflineLease } from './offline_lease.mjs';
const repository=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../../..');
const ps=process.platform==='win32'?path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe'):null;
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn,timeout=60000) {const start=Date.now();while(Date.now()-start<timeout){const v=fn();if(v)return v;await sleep(50);}throw new Error('test_timeout');}
const quote=s=>"'"+s.replaceAll("'","''")+"'";
function protect(root){execFileSync(ps,['-NoProfile','-Command',". "+quote(path.join(repository,'tools/i_core/release_schema6/lifecycle/protected_paths.ps1'))+"; Protect-NewDirectory "+quote(root)],{windowsHide:true,env:cleanEnvironment()});}
const secret=()=>randomBytes(32).toString('hex');
function removeOwned(root,prefix) {
 const parent=realpathSync.native(tmpdir());plainPath(root);
 if(path.dirname(root)!==parent || !path.basename(root).startsWith(prefix))throw new Error('unsafe_test_cleanup_target');
 const inspect=dir=>{plainPath(dir);for(const item of readdirSync(dir,{withFileTypes:true})){const target=plainPath(path.join(dir,item.name));if(item.isDirectory())inspect(target);}};
 inspect(root);rmSync(root,{recursive:true});assert.equal(existsSync(root),false);
}
let sourceRoot;const runtimeLabs=[];
after(()=>{if(sourceRoot && runtimeLabs.every(l=>l.completed))removeOwned(sourceRoot,'schema6-source-');});

function pureConfig(){return {format:'schema6-config-v1',manifest_sha256:'a'.repeat(64),database_path:'database',node_id:'node',owner_sid:'owner',
 companion_upload_mode:'legacy_b3',companion_reply_jobs:false,activity_enabled:false,domain_policy:'owner_managed',pairing_secret:null,
 grants_path:'grants',grants_sha256:'b'.repeat(64),approvals_path:'approvals',approvals_sha256:'c'.repeat(64),recovery_custody_directory:'custody',recovery_key_path:'key'};}
test('configuration rejects unsafe mode, activity/jobs, fields, missing and swapped bindings without OS dependency',()=>{
 const c=pureConfig(),binding={manifest_sha256:c.manifest_sha256,database_path:c.database_path,node_id:c.node_id,owner_sid:c.owner_sid};
 assert.equal(parseConfiguration(c,binding),c);
 for(const patch of [{companion_upload_mode:'pr10'},{companion_reply_jobs:true},{activity_enabled:true},{domain_policy:'auto'},
 {unknown:true},{manifest_sha256:'d'.repeat(64)},{node_id:'wrong'},{owner_sid:'wrong'},{pairing_secret:'short'},{grants_sha256:null}])assert.throws(()=>parseConfiguration({...c,...patch},binding));
});
test('plain JSON and callback-shaped assertions never become trusted offline leases',()=>{
 for(const value of [{},{allCoreWritersStopped:true},{offlineProof:()=>true}])assert.throws(()=>assertOfflineLease(value,{databasePath:'x',phase:'preflight'}),/trusted_offline_lease_required/);
});
test('state digest binds nested files and directory layout independently of lifecycle marker',()=>{
 const root=realpathSync.native(mkdtempSync(path.join(tmpdir(),'schema6-tree-')));
 writeFileSync(path.join(root,'db'),'first');const first=stateDigest(root);
 writeFileSync(path.join(root,'s6-lifecycle.json'),'receipt');assert.equal(stateDigest(root),first);
 mkdirSync(path.join(root,'extra'));assert.notEqual(stateDigest(root),first);
 writeFileSync(path.join(root,'extra','data'),'modified');const second=stateDigest(root);assert.notEqual(second,first);removeOwned(root,'schema6-tree-');
});
let committedFixture;
function fixedSources() {
 if(committedFixture)return committedFixture;
 const source=realpathSync.native(mkdtempSync(path.join(tmpdir(),'schema6-source-')));protect(source);
 for(const name of INVENTORY.filter(n=>n!=='runtime/node.exe')) {
  const destination=path.join(source,name);mkdirSync(path.dirname(destination),{recursive:true});writeFileSync(destination,readFileSync(path.join(repository,name)));
 }
 sourceRoot=source;
 const execPath=execFileSync('git',['--exec-path'],{windowsHide:true,encoding:'utf8'}).trim();
 const gitPath=path.resolve(execPath,'../../../bin/git.exe');
 const env={...cleanEnvironment(),GIT_CONFIG_NOSYSTEM:'1',GIT_CONFIG_GLOBAL:'NUL'};
 const git=(...args)=>execFileSync(gitPath,['-c','core.autocrlf=false','-c','user.name=SyntheticLifecycle','-c','user.email=synthetic@example.invalid','-C',source,...args],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});
 git('init','--quiet');git('add','--','.');git('commit','--quiet','-m','Synthetic fixed lifecycle source');
 committedFixture=readCommittedSources({repository:source,gitPath});
 return committedFixture;
}
async function lab(t){
 const root=realpathSync.native(mkdtempSync(path.join(tmpdir(),'schema6-runtime-')));protect(root);
 const dir=name=>{const p=path.join(root,name);mkdirSync(p);protect(p);return p;};
 const release=dir('release'),state=dir('state'),settingsDir=dir('settings'),custody=dir('custody'),backup=dir('backups');
 const {resolvedCommit,content:committed}=fixedSources();
 const content=INVENTORY.map(name=>[name,name==='runtime/node.exe'?readFileSync(process.execPath):committed.get(name)]);
 const manifest={format:'i-core-schema6-preflight-candidate-v1',source_commit:resolvedCommit,core_commit:resolvedCommit,wrapper_commit:resolvedCommit,
 core_schema_version:6,runtime_profile:'schema6-owned-lifecycle-v1',pinned_node_sha256:sha256(readFileSync(process.execPath)),node_version:process.version,
 policy:{companion_upload_mode:'legacy_b3',companion_reply_jobs:false,activity_enabled:false,domain_policy:'owner_managed'},
 activation_supported:false,files:content.map(([name,bytes])=>({path:name,bytes:bytes.length,sha256:sha256(bytes)}))};
 for(const [name,bytes] of content){mkdirSync(path.dirname(path.join(release,name)),{recursive:true});writeFileSync(path.join(release,name),bytes);}
 const raw=JSON.stringify(manifest,null,2)+'\n';writeFileSync(path.join(release,'manifest.json'),raw);const manifestHash=sha256(raw);
 const grants=path.join(settingsDir,'grants.json'),approvals=path.join(settingsDir,'approvals.json'),key=path.join(root,'recovery-key','runtime-recovery.dpapi'),backupKey=path.join(root,'backup-key','runtime-backup.dpapi');
 writeFileSync(grants,JSON.stringify({version:1,grants:[]}));writeFileSync(approvals,JSON.stringify({version:1,approved_replays:[]}));for(const [purpose,filename] of [['recovery',key],['backup',backupKey]])execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',
  path.join(release,'tools/i_core/release_schema6/key_custody.ps1'),'-Action','Create','-KeyDirectory',path.dirname(filename),'-Purpose',purpose],{env:cleanEnvironment(),windowsHide:true,stdio:['ignore','pipe','pipe']});
 const owner=execFileSync(ps,['-NoProfile','-Command','[Security.Principal.WindowsIdentity]::GetCurrent().User.Value'],{env:cleanEnvironment(),windowsHide:true,encoding:'utf8'}).trim();
 const configuration={...pureConfig(),manifest_sha256:manifestHash,database_path:path.join(state,'i-core.sqlite'),node_id:'new',owner_sid:owner,pairing_secret:secret(),
 grants_path:grants,grants_sha256:sha256(readFileSync(grants)),approvals_path:approvals,approvals_sha256:sha256(readFileSync(approvals)),recovery_custody_directory:custody,recovery_key_path:key,backup_directory:backup,backup_key_path:backupKey};
 const configPath=path.join(settingsDir,'runtime.json');writeFileSync(configPath,JSON.stringify(configuration));
 const lifecycle=path.join(release,'tools/i_core/release_schema6/lifecycle'),runs=[];
 function launch({initial=false,env={},args=[],config=configPath,targetState=state}={}){
  const control=dir('control-'+randomBytes(5).toString('hex'));
  const child=spawn(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(lifecycle,'start_schema6.ps1'),'-ManifestSha256',manifestHash,'-Start','-StateDirectory',targetState,'-ControlDirectory',control,'-ConfigurationFile',config,...(initial?['-InitializeEmpty']:[]),...args],{env:{...cleanEnvironment(),...env},windowsHide:true,stdio:['ignore','pipe','pipe']});
  const run={child,control,closed:false,exit:null,stdout:'',stderr:''};
  child.stdout.on('data',x=>run.stdout+=x);child.stderr.on('data',x=>run.stderr+=x);child.on('close',code=>{run.closed=true;run.exit=code;});
  run.read=name=>existsSync(path.join(control,name))?JSON.parse(readFileSync(path.join(control,name))):null;
  run.wait=async()=>{await until(()=>run.closed,90000);return run;};
  run.ready=async()=>{await until(()=>run.read('ready.json')||run.closed,90000);assert.equal(run.closed,false,run.stdout+run.stderr+JSON.stringify(run.read('child.json')));return run.read('ready.json');};
  run.stop=(action='close',id=run.read('launch.json')?.token)=>execFileSync(ps,['-NoProfile','-NonInteractive','-File',path.join(lifecycle,'request_stop.ps1'),'-ControlDirectory',control,'-RunId',id,'-ManifestSha256',manifestHash,'-Action',action],{env:cleanEnvironment(),windowsHide:true,stdio:['ignore','pipe','pipe'],timeout:15000});
  runs.push(run);return run;
 }

 const result={root,dir,state,release,lifecycle,configuration,configPath,manifestHash,launch,completed:false};runtimeLabs.push(result);
 t.after(async()=>{
  for(const run of runs)if(!run.closed){try{run.stop('stop');await run.wait();}catch{run.child.kill();await until(()=>run.closed,20000);}}
  const stopped=runs.every(run=>run.closed && (!run.read('launch.json') || run.read('supervisor.json')?.result?.job_empty_confirmed===true || run.read('guardian.json')?.result?.job_empty_confirmed===true));
  if(result.completed && stopped) {removeOwned(root,'schema6-runtime-');t.diagnostic('synthetic_root_cleaned_after_job_empty');}
  else t.diagnostic('synthetic_artifacts_retained='+root);
 });
 return result;
}
async function api(ready,route,token,body) {
 const response=await fetch('http://127.0.0.1:'+ready.address.port+'/v1/core'+route,{method:'POST',signal:AbortSignal.timeout(5000),
 headers:{'x-core-protocol':'0.1','content-type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body)});
 const data=await response.json();assert.equal(response.status,200,JSON.stringify(data));return data;
}
async function health(ready){return fetch('http://127.0.0.1:'+ready.address.port+'/v1/core/health',{signal:AbortSignal.timeout(3000)});}
function cleanReceipt(run){
 assert.equal(run.exit,0,run.stdout+run.stderr+JSON.stringify(run.read('child.json')));
 const receipt=run.read('supervisor.json');assert.equal(receipt.child_receipt_confirmed,true);assert.equal(receipt.guardian_receipt_confirmed,true);
 assert.equal(receipt.lock_released_confirmed,true);assert.equal(receipt.result.job_empty_confirmed,true);assert.equal(receipt.result.termination_requested,false);
}
test('Windows fixed production entry: real loopback, credential-free argv, authenticated idempotent close, canonical restart after writes and 125s live', {skip:process.platform!=='win32',timeout:420000},async t=>{
 const l=await lab(t),run=l.launch({initial:true}),ready=await run.ready();
 assert.equal(ready.health.schema_version,6);assert.equal((await health(ready)).status,200);assert.equal(ready.activity_enabled,false);
 assert.equal(ready.companion_upload_mode,'legacy_b3');assert.equal(ready.companion_reply_jobs,false);
 assert.equal(ready.commandline_secret_free,true);assert.deepEqual(ready.inherited_core_keys,[]);
 assert.throws(()=>writeFileSync(l.configPath,'tampered'),/EBUSY|EACCES|EPERM/);
 const paired=await api(ready,'/devices/pair',null,{device_id:'schema6-phone',display_name:'synthetic',platform:'test',client_version:'1',capabilities:['chat'],pairing_code:l.configuration.pairing_secret});
 await api(ready,'/chat/messages',paired.device_token,{device_id:'schema6-phone',messages:[{sync_id:'schema6-user-turn',origin_device_id:'schema6-phone',origin_sequence:1,character_id:'lin-ai',sender:'user',content:'synthetic lifecycle write',created_at_ms:Date.now(),message_type:'chat',asset_refs:[],addenda:[]}]});
 const liveSince=Date.now();while(Date.now()-liveSince<125000){await sleep(Math.min(1000,125000-(Date.now()-liveSince)));assert.equal((await health(ready)).status,200);}
 t.diagnostic('continuous_loopback_ms='+String(Date.now()-liveSince));
 assert.throws(()=>run.stop('close',secret()));
 writeFileSync(path.join(run.control,'close'),'forged');await sleep(150);assert.equal((await health(ready)).status,200);unlinkSync(path.join(run.control,'close'));
 run.stop();run.stop();await run.wait();cleanReceipt(run);await assert.rejects(health(ready));
 const again=l.launch();await again.ready();again.stop();await again.wait();cleanReceipt(again);
 const db=new DatabaseSync(pathToFileURL(path.join(l.state,'i-core.sqlite')).href+'?mode=ro&immutable=1',{readOnly:true});
 try{assert.equal(db.prepare("SELECT COUNT(*) AS n FROM chat_messages WHERE sync_id='schema6-user-turn'").get().n,1);}finally{db.close();}
 writeFileSync(path.join(l.state,'extra.txt'),'unauthorized state');
 const extra=l.launch();await extra.wait();assert.notEqual(extra.exit,0);assert.equal(extra.read('ready.json'),null);
 assert.match(JSON.stringify(extra.read('child.json')),/recovery_required/);l.completed=true;
});
test('Windows entry rejects injected Node config, unbound config, manifest extra file and nonempty initialization', {skip:process.platform!=='win32',timeout:180000},async t=>{
 const l=await lab(t);
 const injected=l.launch({initial:true,env:{NODE_OPTIONS:'--trace-warnings'}});await injected.wait();assert.notEqual(injected.exit,0);assert.equal(injected.read('launch.json'),null);
 const wrong=path.join(path.dirname(l.configPath),'wrong.json');writeFileSync(wrong,JSON.stringify({...l.configuration,manifest_sha256:secret()}));
 const unbound=l.launch({initial:true,config:wrong});await unbound.wait();assert.notEqual(unbound.exit,0);assert.match(JSON.stringify(unbound.read('child.json')),/config_binding_mismatch/);
 // Rejected initialization left its runtime lock file; an occupied state root
 // must never be treated as a fresh genesis on a subsequent attempt.
 const nonempty=l.launch({initial:true});await nonempty.wait();assert.notEqual(nonempty.exit,0);
 assert.match(nonempty.stderr,/initialize_requires_empty_state/);assert.equal(nonempty.read('launch.json'),null);
 writeFileSync(path.join(l.release,'extra.txt'),'extra');
 const extra=l.launch({initial:true});await extra.wait();assert.notEqual(extra.exit,0);assert.equal(extra.read('launch.json'),null);l.completed=true;
});
for(const target of ['guardian','parent','child'])test('Windows '+target+' death never authorizes restart or fabricates clean close',{skip:process.platform!=='win32',timeout:180000},async t=>{
 const l=await lab(t),run=l.launch({initial:true}),ready=await run.ready();
 const pid=target==='guardian'?run.read('guardian-ready.json').pid:target==='parent'?run.child.pid:ready.pid;
 process.kill(pid);await run.wait();await until(()=>{try{process.kill(ready.pid,0);return false;}catch{return true;}},20000);
 await assert.rejects(health(ready));
 await until(()=>{try{process.kill(run.read('guardian-ready.json').pid,0);return false;}catch{return true;}},20000);
 const marker=JSON.parse(readFileSync(path.join(l.state,'s6-lifecycle.json')));assert.equal(marker.phase,'recovery_required');
 const restart=l.launch();await restart.wait();assert.notEqual(restart.exit,0);assert.equal(restart.read('ready.json'),null);l.completed=true;
});


test('Windows canonical offline lease runs real 6-to-5-to-6 transactions and refuses online schema5', {skip:process.platform!=='win32',timeout:360000},async t=>{
 const l=await lab(t),initial=l.launch({initial:true});await initial.ready();initial.stop();await initial.wait();cleanReceipt(initial);
 const rollback=l.launch({args:['-OfflineOperation','rollback']});await rollback.wait();cleanReceipt(rollback);
 assert.equal(rollback.read('operation.json').database_schema_version,5);
 const wrong=l.launch();await wrong.wait();assert.notEqual(wrong.exit,0);assert.match(JSON.stringify(wrong.read('child.json')),/existing_core_identity_or_schema_required/);
 const migrate=l.launch({args:['-OfflineOperation','migrate']});await migrate.wait();cleanReceipt(migrate);
 assert.equal(migrate.read('operation.json').database_schema_version,6);
 const final=l.launch();await final.ready();final.stop();await final.wait();cleanReceipt(final);l.completed=true;
});
test('Windows backup role and unowned schema4 cannot be activated by ordinary restart', {skip:process.platform!=='win32',timeout:220000},async t=>{
 const l=await lab(t),initial=l.launch({initial:true});await initial.ready();initial.stop();await initial.wait();cleanReceipt(initial);
 const filename=path.join(l.state,'i-core.sqlite'),original=readFileSync(filename);
 for(const [sql,expected] of [["UPDATE core_metadata SET value='4' WHERE key='schema_version'",'existing_core_identity_or_schema_required'],["UPDATE activity_metadata SET value='backup_read_only' WHERE key='database_role'",'backup_activation_unsupported']]){
  writeFileSync(filename,original);const db=new DatabaseSync(filename);try{db.exec(sql);}finally{db.close();}
  const run=l.launch();await run.wait();assert.notEqual(run.exit,0);assert.match(JSON.stringify(run.read('child.json')),new RegExp(expected));assert.equal(run.read('ready.json'),null);
 }
 l.completed=true;
});
