import assert from 'node:assert/strict';
import {spawn,spawnSync,execFileSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {existsSync,readFileSync,readdirSync,writeFileSync,copyFileSync,mkdirSync} from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import {cleanEnvironment,sha256,INVENTORY,prepareRelease} from '../package.mjs';
import {syntheticFixedNode} from '../../test_fixtures/release_schema6/synthetic_paths.mjs';
import {createRuntimeLab,until,api,health,cleanReceipt,ps,repository} from './test-fixture.mjs';

function json(file){return existsSync(file)?JSON.parse(readFileSync(file,'utf8')):null;}
function loginConfig(l,port=0){
 const controlRoot=l.dir('sessions');
 const configuration={format:'schema6-login-v1',owner_sid:l.configuration.owner_sid,release_directory:l.release,manifest_sha256:l.manifestHash,
 state_directory:l.state,control_root:controlRoot,core_configuration_path:l.configPath,core_configuration_sha256:sha256(readFileSync(l.configPath)),core_port:port,
 backup_configuration_path:null,backup_configuration_sha256:null,backup_key_directory:null,backup_interval_seconds:300};
 const file=path.join(path.dirname(l.configPath),'login.json');writeFileSync(file,JSON.stringify(configuration));
 return {file,controlRoot,configuration,hash:sha256(readFileSync(file))};
}
function loginArgs(l,c){return ['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(l.lifecycle,'login_schema6.ps1'),'-ReleaseDirectory',l.release,'-ManifestSha256',l.manifestHash,'-LoginConfigurationPath',c.file,'-LoginConfigurationSha256',c.hash];}
async function host(l,c,{initial=true,register=true}={}){
 const prior=new Set(readdirSync(c.controlRoot));
 const child=spawn(ps,[...loginArgs(l,c),...(initial?['-InitializeEmpty']:[])],{windowsHide:true,env:cleanEnvironment(),stdio:['ignore','pipe','pipe']});
 const run={child,closed:false,exit:null,stdout:'',stderr:'',control:null};
 child.stdout.on('data',b=>run.stdout+=b);child.stderr.on('data',b=>run.stderr+=b);child.on('close',code=>{run.closed=true;run.exit=code;});
 const session=()=>readdirSync(c.controlRoot).filter(n=>!prior.has(n)).map(n=>path.join(c.controlRoot,n)).find(p=>existsSync(path.join(p,'session-window.json')));
 await until(()=>session()||run.closed,180000);assert.equal(run.closed,false,run.stderr);
 run.session=session();run.window=json(path.join(run.session,'session-window.json'));
 assert.equal(run.window.pid,child.pid);assert.equal(run.window.hook_ready,true);
 run.controls=()=>readdirSync(run.session).filter(n=>n.startsWith('control-')).map(n=>path.join(run.session,n));
 run.read=name=>run.control?json(path.join(run.control,name)):null;
 run.send=(message,wparam=0)=>JSON.parse(execFileSync(ps,['-NoProfile','-NonInteractive','-File',path.join(repository,'tools/i_core/test_fixtures/release_schema6/send_session_message.ps1'),'-Window',String(run.window.hwnd),'-ExpectedPid',String(child.pid),'-Message',String(message),'-WParam',String(wparam)],{windowsHide:true,env:cleanEnvironment(),encoding:'utf8',timeout:50000}));
 run.wait=async()=>{await until(()=>run.closed,60000);return run;};
 run.stop=()=>run.send(16);
 run.ready=async(except=null)=>{await until(()=>run.controls().find(p=>p!==except&&existsSync(path.join(p,'ready.json')))||run.closed,240000);assert.equal(run.closed,false,run.stderr);run.control=run.controls().find(p=>p!==except&&existsSync(path.join(p,'ready.json')));return run.read('ready.json');};
 if(register)l.registerRun(run);return run;
}

function instrumentTransaction(l) {
 const source=l.dir('transaction-synthetic-source'),release=l.dir('transaction-release'),barrier=l.dir('transaction-barrier');
 for(const name of INVENTORY.filter(n=>n!=='runtime/node.exe')){const target=path.join(source,name);mkdirSync(path.dirname(target),{recursive:true});copyFileSync(path.join(l.release,name),target);}
 const store=path.join(source,'tools/i_core/i_core_store.mjs'),original=readFileSync(store,'utf8');
 const needle="    const results = [];\n    this.db.exec('BEGIN IMMEDIATE');\n    try {";
 assert.equal(original.split(needle).length,2);
 const entered=path.join(barrier,'entered'),resume=path.join(barrier,'resume');
 const gate=`\n      if(messages.some(m=>m.sync_id==='session-inflight-write')) { writeFileSync(${JSON.stringify(entered)},'actual transaction open'); const deadline=Date.now()+20000; while(!existsSync(${JSON.stringify(resume)})){ if(Date.now()>deadline)throw new Error('synthetic_transaction_barrier_timeout'); Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,25); } }`;
 writeFileSync(store,original.replace(needle,needle+gate));
 const gitExec=execFileSync('git',['--exec-path'],{encoding:'utf8',windowsHide:true}).trim(),gitPath=path.resolve(gitExec,'../../../bin/git.exe');
 const git=(...args)=>execFileSync(gitPath,['-C',source,'-c','core.autocrlf=false','-c','core.hooksPath='+path.join(source,'no-hooks'),'-c','user.name=Synthetic','-c','user.email=synthetic@example.invalid','-c','commit.gpgsign=false',...args],{windowsHide:true,env:cleanEnvironment(),stdio:'pipe'});
 git('init','-q');git('add','.');git('commit','-qm','Synthetic transaction shutdown barrier');
 const built=path.join(l.root,'transaction-built'),fixedNode=syntheticFixedNode(source);
 const prepared=prepareRelease({repository:source,output:built,nodePath:fixedNode,gitPath});
 for(const name of [...INVENTORY,'manifest.json']){const target=path.join(release,name);mkdirSync(path.dirname(target),{recursive:true});copyFileSync(path.join(built,name),target);}
 l.release=release;l.lifecycle=path.join(release,'tools/i_core/release_schema6/lifecycle');l.manifestHash=prepared.manifest_sha256;l.configuration.manifest_sha256=l.manifestHash;
 writeFileSync(l.configPath,JSON.stringify(l.configuration));
 return {entered,resume};
}

test('Windows hidden session hook: cancel shutdown creates fresh control; shutdown after writes confirms real clean close',{skip:process.platform!=='win32',timeout:600000},async t=>{
 const l=await createRuntimeLab(t),barrier=instrumentTransaction(l),c=loginConfig(l),run=await host(l,c);
 const first=await run.ready();assert.equal((await health(first)).status,200);
 const oldControl=run.control,query=run.send(17);assert.equal(query.result,1);assert.ok(query.elapsed_ms<1000,'WM_QUERYENDSESSION must return before disk close');
 run.send(22,0);
 const second=await run.ready(oldControl);assert.notEqual(run.control,oldControl);assert.equal(json(path.join(oldControl,'session-close.json')).clean_closed,true);
 assert.equal((await health(second)).status,200);
 const paired=await api(second,'/devices/pair',null,{device_id:'session-synthetic-phone',display_name:'Synthetic',platform:'test',client_version:'1',capabilities:['chat'],pairing_code:l.configuration.pairing_secret});
 const write=api(second,'/chat/messages',paired.device_token,{device_id:'session-synthetic-phone',messages:[{sync_id:'session-inflight-write',origin_device_id:'session-synthetic-phone',origin_sequence:1,character_id:'lin-ai',sender:'user',content:'synthetic shutdown write',created_at_ms:1700000000000,message_type:'chat',asset_refs:[],addenda:[]}]});
 const outcome=write.then(value=>({value}),error=>({error}));
 await until(()=>existsSync(barrier.entered),4000);
 assert.equal(run.send(17).result,1);
 await until(()=>existsSync(path.join(run.control,'close')),4000);
 assert.equal(existsSync(barrier.resume),false,'query and authenticated close arrived while Core transaction was open');
 writeFileSync(barrier.resume,'release actual transaction');
 const accepted=await outcome;assert.equal(accepted.error,undefined,String(accepted.error));
 run.send(22,1);await run.wait();
 cleanReceipt(run);assert.equal(run.read('session-close.json').clean_closed,true);await assert.rejects(health(second));
 const db=new DatabaseSync(pathToFileURL(path.join(l.state,'i-core.sqlite')).href+'?mode=ro&immutable=1',{readOnly:true});try{assert.equal(db.prepare("SELECT COUNT(*) AS n FROM chat_messages WHERE sync_id='session-inflight-write'").get().n,1);}finally{db.close();}
 const restart=await host(l,c,{initial:false}),third=await restart.ready();assert.equal((await health(third)).status,200);
 const changes=await fetch('http://127.0.0.1:'+third.address.port+'/v1/core/changes',{headers:{'x-core-protocol':'0.1',Authorization:'Bearer '+paired.device_token}});
 assert.equal(changes.status,200);assert.ok(JSON.stringify(await changes.json()).includes('session-inflight-write'));
 restart.stop();await restart.wait();cleanReceipt(restart);
 t.diagnostic('query_during_open_core_transaction=true;accepted=1;next_start_http_readback=1');
 l.completed=true;
});

test('Windows login preparation is hash-bound, rejects dynamic production port and emits only least-privilege InteractiveToken XML',{skip:process.platform!=='win32',timeout:180000},async t=>{
 const l=await createRuntimeLab(t),c=loginConfig(l),out=path.join(path.dirname(c.file),'login-task.xml');
 const prepare=()=>execFileSync(ps,['-NoProfile','-NonInteractive','-File',path.join(l.lifecycle,'prepare_login_schema6.ps1'),'-ReleaseDirectory',l.release,'-ManifestSha256',l.manifestHash,'-LoginConfigurationPath',c.file,'-LoginConfigurationSha256',c.hash,'-OutputXml',out,'-PrepareOnly'],{windowsHide:true,env:cleanEnvironment(),encoding:'utf8'});
 assert.throws(prepare);assert.equal(existsSync(out),false);
 c.configuration.core_port=47841;writeFileSync(c.file,JSON.stringify(c.configuration));c.hash=sha256(readFileSync(c.file));
 const result=JSON.parse(prepare());assert.equal(result.registered,false);assert.equal(result.started,false);
 const xml=readFileSync(out,'utf8');for(const value of ['InteractiveToken','LeastPrivilege','IgnoreNew','PT0S',c.hash,l.manifestHash])assert.ok(xml.includes(value));assert.equal(xml.includes('RestartOnFailure'),false);assert.throws(prepare);
 const changed=path.join(path.dirname(c.file),'bad-login.json');writeFileSync(changed,readFileSync(c.file,'utf8')+' ');
 assert.throws(()=>execFileSync(ps,[...loginArgs(l,{...c,file:changed}),'-ValidateOnly'],{windowsHide:true,env:cleanEnvironment(),stdio:'pipe'}));
 const coreOriginal=readFileSync(l.configPath),secret='synthetic-secret-'+randomUUID(),malformed='{"secret":"'+secret+'", broken';
 for(const target of ['login','core','backup']) {
  const configuration={...c.configuration};writeFileSync(l.configPath,coreOriginal);
  if(target==='core'){writeFileSync(l.configPath,malformed);configuration.core_configuration_sha256=sha256(readFileSync(l.configPath));}
  if(target==='backup'){
   const backup=path.join(path.dirname(c.file),'malformed-backup.json');writeFileSync(backup,malformed);
   configuration.backup_configuration_path=backup;configuration.backup_configuration_sha256=sha256(readFileSync(backup));configuration.backup_key_directory=l.dir('malformed-backup-key');
  }
  writeFileSync(c.file,target==='login'?malformed:JSON.stringify(configuration));
  const rejected=spawnSync(ps,[...loginArgs(l,{...c,hash:sha256(readFileSync(c.file))}),'-ValidateOnly'],{windowsHide:true,env:cleanEnvironment(),encoding:'utf8'});
  assert.equal(rejected.status,2);const output=rejected.stdout+rejected.stderr;
  assert.equal(output.includes(secret),false);assert.equal(output.includes(c.file),false);assert.match(output,/schema6_login_rejected:configuration_or_release_rejected/);
 }
 writeFileSync(l.configPath,coreOriginal);
 l.completed=true;
});

test('Windows control reader authenticates held bytes during the publisher rename handle and concurrent reads',{skip:process.platform!=='win32',timeout:180000},async t=>{
 const l=await createRuntimeLab(t),directory=l.dir('control-sharing');
 const proof=JSON.parse(execFileSync(ps,['-NoProfile','-NonInteractive','-File',path.join(repository,'tools/i_core/test_fixtures/release_schema6/probe_control_read_sharing.ps1'),'-OwnedJobScript',path.join(l.lifecycle,'owned_job.ps1'),'-Directory',directory],{windowsHide:true,env:cleanEnvironment(),encoding:'utf8'}));
 for(const key of ['old_reader_sharing_violation','authenticated_bytes_accepted','forged_bytes_rejected','concurrent_read_compatible'])assert.equal(proof[key],true,key);
 l.completed=true;
});

test('Windows backup launch and worker failures leave Core online and publish fixed retry status',{skip:process.platform!=='win32',timeout:600000},async t=>{
 for(const mode of ['launch','worker'])await t.test(mode,async t=>{
  const l=await createRuntimeLab(t),c=loginConfig(l),keys=l.dir('backup-keys');
  const backup=path.join(path.dirname(c.file),'backup-invalid-contract.json');writeFileSync(backup,'{}');
  Object.assign(c.configuration,{backup_configuration_path:backup,backup_configuration_sha256:sha256(readFileSync(backup)),backup_key_directory:keys+(mode==='launch'?'\\':''),backup_interval_seconds:300});
  writeFileSync(c.file,JSON.stringify(c.configuration));c.hash=sha256(readFileSync(c.file));
  const run=await host(l,c),ready=await run.ready();
  const statuses=()=>readdirSync(run.session).filter(n=>n.startsWith('backup-status-')&&n.endsWith('.json')).map(n=>json(path.join(run.session,n)));
  await until(()=>statuses().length>0,30000);
  const status=statuses()[0];assert.equal(status.status,mode==='launch'?'backup_launch_failed':'backup_worker_failed');assert.equal(status.success,false);
  assert.deepEqual(Object.keys(status).sort(),['next_attempt_utc','status','success']);assert.ok(Date.parse(status.next_attempt_utc)>Date.now());
  assert.equal(run.closed,false);assert.equal((await health(ready)).status,200);
  run.stop();await run.wait();cleanReceipt(run);l.completed=true;
 });
});

test('Windows shutdown timeout kills only the owned tree and the next login recovers without a forged clean receipt',{skip:process.platform!=='win32',timeout:600000},async t=>{
 const l=await createRuntimeLab(t),c=loginConfig(l),run=await host(l,c,{register:false});
 t.after(async()=>{if(!run.closed){run.child.kill();await run.wait();}});
 const ready=await run.ready();
 const suspended=JSON.parse(execFileSync(ps,['-NoProfile','-NonInteractive','-File',path.join(repository,'tools/i_core/test_fixtures/release_schema6/suspend_synthetic_core.ps1'),'-ProcessId',String(ready.pid),'-Executable',path.join(l.release,'runtime/node.exe'),'-RunId',ready.token],{windowsHide:true,env:cleanEnvironment(),encoding:'utf8'}));
 assert.equal(suspended.synthetic_core_suspended,true);
 assert.equal(run.send(17).result,1);const ended=run.send(22,1);assert.ok(ended.elapsed_ms<=32000);
 await run.wait();assert.notEqual(run.exit,0);await assert.rejects(health(ready));
 const cleanup=json(path.join(run.session,'session-exit.json'));
 assert.equal(cleanup.clean_closed,false);assert.equal(cleanup.core_job_empty_confirmed,true);assert.equal(cleanup.backup_job_empty_confirmed,true);
 assert.notEqual(json(path.join(l.state,'s6-lifecycle.json')).phase,'clean_closed');
 assert.notEqual(run.read('session-close.json')?.clean_closed,true);
 const restart=await host(l,c,{initial:false}),recovered=await restart.ready();assert.equal((await health(recovered)).status,200);
 restart.stop();await restart.wait();cleanReceipt(restart);l.completed=true;
});

test('Windows resident retries one owned Core death in the same login with a fresh control and real data readback',{skip:process.platform!=='win32',timeout:600000},async t=>{
 const l=await createRuntimeLab(t),c=loginConfig(l),run=await host(l,c),first=await run.ready();
 const paired=await api(first,'/devices/pair',null,{device_id:'session-recovery-phone',display_name:'Synthetic',platform:'test',client_version:'1',capabilities:['chat'],pairing_code:l.configuration.pairing_secret});
 await api(first,'/chat/messages',paired.device_token,{device_id:'session-recovery-phone',messages:[{sync_id:'session-recovery-write',origin_device_id:'session-recovery-phone',origin_sequence:1,character_id:'lin-ai',sender:'user',content:'synthetic resident recovery write',created_at_ms:1700000000000,message_type:'chat',asset_refs:[],addenda:[]}]});
 const original=run.control;
 const killed=JSON.parse(execFileSync(ps,['-NoProfile','-NonInteractive','-File',path.join(repository,'tools/i_core/test_fixtures/release_schema6/suspend_synthetic_core.ps1'),'-ProcessId',String(first.pid),'-Executable',path.join(l.release,'runtime/node.exe'),'-RunId',first.token,'-Action','Kill'],{windowsHide:true,env:cleanEnvironment(),encoding:'utf8'}));
 assert.equal(killed.synthetic_core_killed,true);
 const recovered=await run.ready(original);assert.equal(run.closed,false);assert.notEqual(run.control,original);assert.equal((await health(recovered)).status,200);
 const changes=await fetch('http://127.0.0.1:'+recovered.address.port+'/v1/core/changes',{headers:{'x-core-protocol':'0.1',Authorization:'Bearer '+paired.device_token}});
 assert.equal(changes.status,200);assert.ok(JSON.stringify(await changes.json()).includes('session-recovery-write'));
 run.stop();await run.wait();cleanReceipt(run);l.completed=true;
});
