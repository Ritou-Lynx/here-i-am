import assert from 'node:assert/strict';
import { after } from 'node:test';
import { randomBytes } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync, realpathSync, copyFileSync, rmSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { spawn, execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { syntheticRoot, syntheticFixedNode } from '../../test_fixtures/release_schema6/synthetic_paths.mjs';
import { INVENTORY, cleanEnvironment, sha256, prepareRelease, plainPath } from '../package.mjs';
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
let committedFixture;
function fixedSources() {
 if(committedFixture)return committedFixture;
 const source=syntheticRoot('schema6-source-');protect(source);
 for(const name of INVENTORY.filter(n=>n!=='runtime/node.exe')) {
  const destination=path.join(source,name);mkdirSync(path.dirname(destination),{recursive:true});writeFileSync(destination,readFileSync(path.join(repository,name)));
 }
 sourceRoot=source;
 const execPath=execFileSync('git',['--exec-path'],{windowsHide:true,encoding:'utf8'}).trim();
 const gitPath=path.resolve(execPath,'../../../bin/git.exe');
 const env={...cleanEnvironment(),GIT_CONFIG_NOSYSTEM:'1',GIT_CONFIG_GLOBAL:'NUL'};
 const git=(...args)=>execFileSync(gitPath,['-c','core.autocrlf=false','-c','user.name=SyntheticLifecycle','-c','user.email=synthetic@example.invalid','-C',source,...args],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});
 git('init','--quiet');git('add','--','.');git('commit','--quiet','-m','Synthetic fixed lifecycle source');
 committedFixture={source,gitPath,fixedNode:syntheticFixedNode(source)};
 return committedFixture;
}
async function createRuntimeLab(t){
 const root=syntheticRoot('schema6-runtime-');protect(root);
 let setupComplete=false;
 t.after(()=>{if(!setupComplete)removeOwned(root,'schema6-runtime-');});
 const dir=name=>{const p=path.join(root,name);mkdirSync(p);protect(p);return p;};
 const release=dir('release'),state=dir('state'),settingsDir=dir('settings'),custody=dir('custody'),backup=dir('backups');
 const {source,gitPath,fixedNode}=fixedSources();
 // Build with the real package API, then copy its exact inventory into an
 // empty root whose ACL was protected before population. No manifest is forged.
 const built=path.join(root,'built-package');
 const prepared=prepareRelease({repository:source,output:built,nodePath:fixedNode,gitPath});const manifestHash=prepared.manifest_sha256;
 for(const name of [...INVENTORY,'manifest.json']){const target=path.join(release,name);mkdirSync(path.dirname(target),{recursive:true});copyFileSync(plainPath(path.join(built,name)),target);}
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
  run.ready=async()=>{await until(()=>run.read('ready.json')||run.closed,180000);assert.equal(run.closed,false,run.stdout+run.stderr+JSON.stringify(run.read('child.json')));return run.read('ready.json');};
  run.stop=(action='close',id=run.read('launch.json')?.token)=>execFileSync(ps,['-NoProfile','-NonInteractive','-File',path.join(lifecycle,'request_stop.ps1'),'-ControlDirectory',control,'-RunId',id,'-ManifestSha256',manifestHash,'-Action',action],{env:cleanEnvironment(),windowsHide:true,stdio:['ignore','pipe','pipe'],timeout:15000});
  runs.push(run);return run;
 }

 const result={root,dir,state,release,lifecycle,configuration,configPath,manifestHash,launch,registerRun:run=>runs.push(run),completed:false};runtimeLabs.push(result);
 t.after(async()=>{
  for(const run of runs)if(!run.closed){try{run.stop('stop');await run.wait();}catch{run.child.kill();await until(()=>run.closed,20000);}}
  const stopped=runs.every(run=>run.closed && (!run.read('launch.json') || run.read('supervisor.json')?.result?.job_empty_confirmed===true || run.read('guardian.json')?.result?.job_empty_confirmed===true));
  if(result.completed && stopped) {removeOwned(root,'schema6-runtime-');t.diagnostic('synthetic_root_cleaned_after_job_empty');}
  else t.diagnostic('synthetic_artifacts_retained='+root);
 });
 setupComplete=true;return result;
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

export { createRuntimeLab, until, api, health, cleanReceipt, ps, repository, protect, removeOwned, quote };
