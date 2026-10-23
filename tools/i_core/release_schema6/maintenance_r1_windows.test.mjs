import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import {existsSync,readFileSync,readdirSync,writeFileSync} from 'node:fs';
import path from 'node:path';
import {cleanEnvironment,sha256} from './package.mjs';
import {createRuntimeLab,repository,ps,until,cleanReceipt} from './lifecycle/test-fixture.mjs';
import {loginConfig,loginArgs,configureManagedMcp,host,connectManaged} from './lifecycle/mcp-session-test-fixture.mjs';
import {allocateSyntheticLoopbackPort} from '../test_fixtures/release_schema6/mcp_reader/helper.mjs';
import {r1PackageSwitchLab} from '../test_fixtures/release_schema6/r1_package_switch.mjs';

const windowsCI=process.platform==='win32'&&process.env.GITHUB_ACTIONS==='true';
const options={skip:!windowsCI,timeout:1800000};
const fixture=path.join(repository,'tools/i_core/test_fixtures/release_schema6');
const maintenance=path.join(repository,'tools/i_core/maintenance');
const json=file=>safeJson(readFileSync(file,'utf8'));
const task=(name,l,c,enabled)=>({Name:name,Path:ps,Arguments:loginArgs(l,c).map(value=>'"'+value+'"').join(' '),WorkingDirectory:l.release,Enabled:enabled});
function invoke(script,inputPath,mode,stdin){
 assert.equal(windowsCI,true,'native fixtures only execute in Windows CI');
 // CI identity is explicit after the existing allowlist strips inherited settings.
 return spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(fixture,script),'-InputPath',inputPath,'-MaintenanceDirectory',maintenance,'-Mode',mode],{env:{...cleanEnvironment(),GITHUB_ACTIONS:'true'},windowsHide:true,encoding:'utf8',input:stdin,timeout:540000});
}
function safeJson(raw){try{return JSON.parse(raw);}catch{throw new Error('r1_invalid_redacted_fixture_report');}}
function report(result,format){
 assert.ifError(result.error);assert.equal(result.status,0,'native fixture failed; raw output withheld');
 const rows=result.stdout.trim().split(/\r?\n/).filter(Boolean).map(safeJson);
 const found=rows.findLast(row=>row.format===format);assert.ok(found,'fixture result missing');return found;
}
// Step names and reviewed error codes only; any other detail text is withheld.
function stepCodes(stdout){
 const code=detail=>String(detail??'').split(';').map(part=>part.replace(/:.*$/s,'')).filter(part=>/^[a-z0-9_]{1,64}(=[a-z0-9_]{1,64})?$/.test(part)).join(';')||'unreadable';
 return stdout.trim().split(/\r?\n/).filter(Boolean).map(safeJson).filter(row=>typeof row.step==='string'&&/^[a-z0-9_.]{1,64}$/.test(row.step))
  .map(row=>row.step+':'+(row.ok===true?'ok':code(row.detail))).join(' ');
}
function controlDirectories(root){
 return readdirSync(root,{withFileTypes:true}).filter(e=>e.isDirectory()).flatMap(e=>{
  const session=path.join(root,e.name);
  return readdirSync(session,{withFileTypes:true}).filter(d=>d.isDirectory()&&d.name.startsWith('control-')).map(d=>path.join(session,d.name));
 });
}
function assertCleanControls(root){
 const controls=controlDirectories(root);assert.ok(controls.length>0);
 for(const control of controls){
  assert.equal(json(path.join(control,'child.json')).phase,'clean_closed');
  assert.equal(json(path.join(control,'session-close.json')).clean_closed,true);
  assert.equal(json(path.join(control,'supervisor.json')).result.job_empty_confirmed,true);
  assert.equal(json(path.join(control,'supervisor.json')).lock_released_confirmed,true);
  assert.equal(json(path.join(control,'mcp-stop.json')).job_empty_confirmed,true);
  assert.equal(json(path.join(path.dirname(control),'session-exit.json')).clean_closed,true);
 }
}
function assertNoRecovery(l,before){
 assert.equal(json(path.join(l.state,'s6-lifecycle.json')).phase,'clean_closed');
 for(const name of ['s6-recovery-pending.json','s6-package-switch-pending.json'])assert.equal(existsSync(path.join(l.state,name)),false);
 for(const suffix of ['-wal','-shm','-journal'])assert.equal(existsSync(l.configuration.database_path+suffix),false,suffix);
 assert.deepEqual(readdirSync(l.configuration.recovery_custody_directory).filter(n=>n.endsWith('.recovery.json')).sort(),before);
}
function receiptTexts(root){
 return readdirSync(root,{withFileTypes:true}).flatMap(e=>{
  const file=path.join(root,e.name);
  return e.isDirectory()?receiptTexts(file):[readFileSync(file)];
 });
}

test('R1 real Windows session opens one pairing window, stdin-pairs chatgpt_web, and cleanly stops',options,async t=>{
 const l=await createRuntimeLab(t);
 l.configuration.pairing_secret=null;writeFileSync(l.configPath,JSON.stringify(l.configuration));
 const c=loginConfig(l,await allocateSyntheticLoopbackPort()),mcp=await configureManagedMcp(l,c);
 const run=await host(l,c);const ready=await run.ready();await connectManaged(run,mcp,{requireMessage:false});
 const recoveryBefore=readdirSync(l.configuration.recovery_custody_directory).filter(n=>n.endsWith('.recovery.json')).sort();
 const nonceName='HereIAm-Synthetic-R1-Pairing-'+randomBytes(16).toString('hex');
 const inputPath=path.join(l.root,'r1-pairing-task.json');writeFileSync(inputPath,JSON.stringify({initialPid:run.child.pid,task:task(nonceName,l,c,false)}));
 const endpoint='http://127.0.0.1:'+ready.address.port;
 const pairProbe=()=>fetch(endpoint+'/v1/core/devices/pair',{method:'POST',headers:{'content-type':'application/json','x-core-protocol':'0.1'},body:JSON.stringify({device_id:'frontend:chatgpt_web',display_name:'CI',platform:'external-frontend',client_version:'1',capabilities:['chat'],pairing_code:'0'.repeat(64)}),signal:AbortSignal.timeout(5000)});
 assert.equal((await pairProbe()).status,403);
 let registered=false;
 try{
 const registration=report(invoke('r1_pairing_session.ps1',inputPath,'Register'),'r1-task-register-v1');
 assert.equal(registration.registered,true);assert.equal(registration.disabled,true);assert.equal(registration.neverStarted,true);registered=true;
 // Exercise the real -File CLI parameter binding and the real read-only COM path.
 const opened=spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(maintenance,'open-pairing-window.ps1'),'-TaskName',nonceName],{env:cleanEnvironment(),windowsHide:true,encoding:'utf8',timeout:60000});
 assert.ifError(opened.error);assert.equal(opened.status,0,'window opener failed; raw output withheld');
 assert.equal(opened.stderr.length===0,true,'window opener stderr is empty; raw output withheld');
 const code=opened.stdout.trim();
 assert.equal(/^[a-f0-9]{64}$/.test(code),true,'one valid pairing code on stdout');
 assert.equal(opened.stdout.trim().split(/\r?\n/).length,1,'code printed exactly once');
 await until(()=>readdirSync(run.control).filter(n=>/^pair-receipt-\d+\.json$/.test(n)).some(n=>json(path.join(run.control,n)).status==='opened'),15000);
 assert.equal(existsSync(path.join(run.control,'pair.code')),false);assert.equal(existsSync(path.join(run.control,'pair.request')),false);
 const clientState=l.dir('pair-client');
 const cli=spawn(path.join(l.release,'runtime/node.exe'),[path.join(repository,'tools/i_remote_mcp/server.mjs'),'pair-core','--frontend','chatgpt_web','--core-url',endpoint,'--state-dir',clientState],{env:cleanEnvironment(),windowsHide:true,stdio:['pipe','pipe','pipe']});
 let cliOut='',cliErr='',cliClosed=false;
 cli.stdout.on('data',b=>cliOut+=b);cli.stderr.on('data',b=>cliErr+=b);
 const exited=new Promise((resolve,reject)=>{cli.on('error',reject);cli.on('close',status=>{cliClosed=true;resolve(status);});});
 t.after(()=>{if(!cliClosed)cli.kill();});
 // CLI waits for stdin while CIM reads actual host, Core, MCP and CLI command lines.
 const scan=report(invoke('r1_pairing_session.ps1',inputPath,'Inspect',JSON.stringify({code,pids:[run.child.pid,ready.pid,run.read('mcp-start.json').pid,cli.pid]})),'r1-process-inspection-v1');
 assert.equal(scan.count,4);assert.equal(scan.noPlaintext,true,'actual command lines contain no pairing code');
 cli.stdin.end(code+'\n');
 const deadline=setTimeout(()=>{if(!cliClosed)cli.kill();},30000);
 let cliStatus;try{cliStatus=await exited;}finally{clearTimeout(deadline);}
 assert.equal(cliOut.includes(code)||cliErr.includes(code),false,'pair client logs contain no pairing code');
 assert.equal(cliStatus,0,'pair-core failed; raw output withheld');
 const credential=json(path.join(clientState,'core-frontend-chatgpt_web.json'));
 assert.equal(credential.device_id,'frontend:chatgpt_web');assert.equal(typeof credential.device_token,'string');
 await until(()=>readdirSync(run.control).filter(n=>/^pair-receipt-\d+\.json$/.test(n)).some(n=>json(path.join(run.control,n)).status==='closed_paired'),15000);
 assert.equal((await pairProbe()).status,403);
 const stopped=report(invoke('r1_pairing_session.ps1',inputPath,'Stop'),'r1-stop-v1');assert.equal(stopped.status,'clean_closed');
 await run.wait();
 assert.equal((run.stdout+run.stderr).includes(code),false,'session logs contain no pairing code');
 assert.equal(receiptTexts(c.controlRoot).some(bytes=>bytes.includes(Buffer.from(code))),false,'session logs and receipts contain no pairing code');
 for(const name of readdirSync(run.control).filter(n=>/^pair-receipt-\d+\.json$/.test(n))){
  const receipt=json(path.join(run.control,name));assert.deepEqual(Object.keys(receipt).sort(),['at_ms','code_hash_prefix','status']);
  assert.equal(receipt.code_hash_prefix===sha256(Buffer.from(code)).slice(0,16),true,'receipt contains only the expected hash prefix');
 }
 cleanReceipt(run);assertCleanControls(c.controlRoot);assertNoRecovery(l,recoveryBefore);
 }finally{
  const removed=report(invoke('r1_pairing_session.ps1',inputPath,'Unregister'),'r1-task-unregister-v1');
  assert.equal(removed.deleted,true);assert.equal(removed.neverStarted,true);if(registered)assert.equal(removed.existed,true);
 }
 l.completed=true;
});

test('R1 exact v3-lab baseline package switches offline to candidate then NoRollback starts only the new task',options,async t=>{
 const f=await r1PackageSwitchLab(t),{l,oldLab,oldLogin,nextLogin}=f;
 const run=await host(oldLab,oldLogin);await run.ready();await connectManaged(run,f.managed,{requireMessage:false});
 const before=readdirSync(l.configuration.recovery_custody_directory).filter(n=>n.endsWith('.recovery.json')).sort();
 const inputPath=path.join(l.root,'r1-switch-tasks.json');
 writeFileSync(inputPath,JSON.stringify({from:'R1-Old',to:'R1-New',initialPid:run.child.pid,tasks:[task('R1-Old',oldLab,oldLogin,true),task('R1-New',l,nextLogin,false)]}));
 const stopped=report(invoke('r1_package_switch_session.ps1',inputPath,'Stop'),'r1-switch-session-v1');
 assert.equal(stopped.stopStatus,'clean_closed');assert.deepEqual(stopped.mutations,[]);
 await run.wait();cleanReceipt(run);
 const offline=await f.apply();assert.equal(offline.read('operation.json').event_sha256.length,64);
 const switchRun=invoke('r1_package_switch_session.ps1',inputPath,'Switch'),switched=report(switchRun,'r1-switch-session-v1');
 if(switched.code!==0)t.diagnostic('r1_no_rollback_steps '+stepCodes(switchRun.stdout));
 assert.equal(switched.code,0);assert.equal(switched.ready,true);assert.equal(switched.cleanup,true);
 assert.equal(switched.enabledOld,false);assert.equal(switched.enabledNew,true);
 assert.deepEqual(switched.mutations,['Disable:R1-Old','Enable:R1-New','Start:R1-New']);
 const controls=controlDirectories(nextLogin.controlRoot);
 assert.ok(controls.some(p=>json(path.join(p,'ready.json')).manifest_sha256===f.next.manifestSha256),'candidate native session actually reached ready');
 assert.equal(controls.filter(p=>json(path.join(p,'ready.json')).manifest_sha256===f.old.manifestSha256).length,1,'old native host never restarted');
 assertCleanControls(nextLogin.controlRoot);assertNoRecovery(l,before);l.completed=true;
});
