import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {existsSync,readFileSync,readdirSync,writeFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {sha256,cleanEnvironment} from '../../release_schema6/package.mjs';
import {createRuntimeLab,repository,ps,cleanReceipt} from '../../release_schema6/lifecycle/test-fixture.mjs';
import {loginConfig,loginArgs,configureManagedMcp,host,connectManaged} from '../../release_schema6/lifecycle/mcp-session-test-fixture.mjs';
import {allocateSyntheticLoopbackPort} from './mcp_reader/helper.mjs';
import {stepCodes,readySnapshot} from './safe_switch_diagnostics.mjs';
const here=path.dirname(fileURLToPath(import.meta.url));
const maintenance=path.join(repository,'tools/i_core/maintenance');
const options={skip:process.platform!=='win32',timeout:720000};
const json=p=>JSON.parse(readFileSync(p,'utf8'));
const hash=p=>sha256(readFileSync(p));
const quote=value=>'"'+value+'"';
function sessions(root){
 return readdirSync(root,{withFileTypes:true}).filter(e=>e.isDirectory()).map(e=>path.join(root,e.name));
}
function controls(root){
 return sessions(root).flatMap(s=>readdirSync(s,{withFileTypes:true}).filter(e=>e.isDirectory()&&e.name.startsWith('control-')).map(e=>path.join(s,e.name)));
}
function assertCleanControls(root){
 for(const control of controls(root)){
  const read=n=>json(path.join(control,n));
  assert.equal(read('child.json').phase,'clean_closed');
  assert.equal(read('session-close.json').clean_closed,true);
  const supervisor=read('supervisor.json');
  assert.equal(supervisor.lock_released_confirmed,true);
  assert.equal(supervisor.result.job_empty_confirmed,true);
  assert.equal(supervisor.result.termination_requested,false);
  assert.equal(read('mcp-stop.json').job_empty_confirmed,true);
  const exit=json(path.join(path.dirname(control),'session-exit.json'));
  assert.equal(exit.clean_closed,true);
  assert.equal(exit.worker_completion_confirmed,true);
 }
}
for(const scenario of ['stop','success','bad-pin','drift','dry-run']){
 test('safe switch real synthetic session: '+scenario,options,async t=>{
  const l=await createRuntimeLab(t);
  const a=loginConfig(l,await allocateSyntheticLoopbackPort());
  const mcp=await configureManagedMcp(l,a);
  const b={file:path.join(path.dirname(a.file),'login-b.json'),controlRoot:l.dir('sessions-b'),
   configuration:{...a.configuration}};
  b.configuration.control_root=b.controlRoot;
  writeFileSync(b.file,JSON.stringify(b.configuration));b.hash=hash(b.file);
  const run=await host(l,a);await run.ready();await connectManaged(run,mcp,{requireMessage:false});
  // A real legacy reader opened the synthetic SQLite database, exercising the
  // MCP-first normal stop needed to remove Windows SQLite sidecars.
  assert.equal(existsSync(l.configuration.database_path+'-wal'),true);
  assert.equal(existsSync(l.configuration.database_path+'-shm'),true);
  const recoveryBefore=readdirSync(l.configuration.recovery_custody_directory).filter(n=>n.endsWith('.recovery.json'));
  const makeTask=(name,c,enabled)=>({Name:name,Path:ps,Arguments:loginArgs(l,c).map(quote).join(' '),
   WorkingDirectory:l.release,Enabled:enabled,ConfigurationSha256:c.hash,ControlRoot:c.controlRoot});
  const input={scenario,from:'Synthetic-A',to:'Synthetic-B',initialPid:run.child.pid,
   tasks:[makeTask('Synthetic-A',a,true),makeTask('Synthetic-B',b,false)]};
  const inputPath=path.join(l.root,'safe-switch-input.json');writeFileSync(inputPath,JSON.stringify(input));
  const invoked=spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',
   path.join(here,'safe_switch_session.ps1'),'-InputPath',inputPath,'-MaintenanceDirectory',maintenance],
   {env:cleanEnvironment(),windowsHide:true,encoding:'utf8',timeout:540000});
  assert.equal(invoked.status,0,invoked.stdout+invoked.stderr);
  const lines=invoked.stdout.trim().split(/\r?\n/).filter(Boolean).map(line=>JSON.parse(line));
  const result=lines.findLast(v=>v.format==='schema6-safe-switch-test-v1');
  assert.ok(result);assert.equal(result.error,null);assert.equal(result.cleanup,true);
  const steps=lines.filter(v=>Object.hasOwn(v,'step'));
  assert.ok(steps.length>0,'native stop/switch emits machine-readable steps');
  for(const step of steps){assert.equal(typeof step.ok,'boolean');assert.ok(Object.hasOwn(step,'detail'));}
  // Step names and reviewed error codes only; any other detail text is withheld.
  if(result.code!==({stop:0,success:0,'bad-pin':2,drift:1,'dry-run':0})[scenario]){
   t.diagnostic('safe_switch_steps '+scenario+' '+stepCodes(steps));
   t.diagnostic('safe_switch_ready_snapshot '+scenario+' '+readySnapshot(lines));
  }
  if(scenario==='stop'){
   assert.equal(result.code,0);assert.equal(result.stopStatus,'clean_closed');assert.equal(result.secondStopStatus,'already_stopped');
   assert.deepEqual(result.active,[]);assert.equal(sessions(b.controlRoot).length,0);
  }else if(scenario==='success'){
   assert.equal(result.code,0);assert.equal(result.enabledA,false);assert.equal(result.enabledB,true);
   assert.deepEqual(result.active,['Synthetic-B']);assert.equal(sessions(b.controlRoot).length,1);
   assert.ok(result.mutations.includes('Start:Synthetic-B'));
  }else if(scenario==='bad-pin'||scenario==='dry-run'){
   assert.equal(result.code,scenario==='bad-pin'?2:0);assert.deepEqual(result.mutations,[]);
   assert.equal(result.enabledA,true);assert.equal(result.enabledB,false);assert.equal(result.originalAlive,true);
   assert.equal(sessions(a.controlRoot).length,1);assert.equal(sessions(b.controlRoot).length,0);
  }else{
   assert.equal(result.code,1);assert.equal(result.enabledA,true);assert.equal(result.enabledB,false);
   assert.deepEqual(result.active,['Synthetic-A']);assert.equal(sessions(a.controlRoot).length,2);
   assert.equal(sessions(b.controlRoot).length,1);
   assert.ok(result.mutations.indexOf('Start:Synthetic-B')<result.mutations.indexOf('Start:Synthetic-A'));
   assert.ok(controls(b.controlRoot).every(p=>existsSync(path.join(p,'ready.json'))),'B really reached ready before pin drift');
  }
  await run.wait();cleanReceipt(run);
  assertCleanControls(a.controlRoot);assertCleanControls(b.controlRoot);
  assert.equal(json(path.join(l.state,'s6-lifecycle.json')).phase,'clean_closed');
  assert.equal(existsSync(path.join(l.state,'s6-recovery-pending.json')),false);
  for(const suffix of ['-wal','-shm','-journal'])assert.equal(existsSync(l.configuration.database_path+suffix),false,suffix);
  // A recovery attempt publishes an authenticated *.recovery.json event before
  // replacing data. No new event + every child cleanly closed proves this path
  // did not silently repair a broken shutdown during B or A restart.
  assert.deepEqual(readdirSync(l.configuration.recovery_custody_directory).filter(n=>n.endsWith('.recovery.json')).sort(),recoveryBefore.sort());
  l.completed=true;
 });
}
test('safe switch real COM adapter: harmless nonce task lifecycle',{
 skip:process.platform!=='win32'||process.env.CI!=='true'||process.env.SCHEMA6_SYNTHETIC_TASK_TEST!=='1',timeout:90000
},t=>{
 const invoked=spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',
  path.join(here,'safe_switch_com.ps1'),'-StopScript',path.join(maintenance,'stop-schema6-session.ps1')],
  {windowsHide:true,encoding:'utf8',timeout:80000});
 assert.equal(invoked.status,0,invoked.stdout+invoked.stderr);
 const report=JSON.parse(invoked.stdout.trim().split(/\r?\n/).findLast(line=>line.includes('"schema6-safe-switch-com-v1"')));
 t.diagnostic(JSON.stringify(report));
 for(const key of ['created','read','enabled','disabled','started','deleted'])assert.equal(report[key],true,key);
});


for(const failure of ['close-fails','recovery-lock']){
 test('safe switch pure rollback refuses old start: '+failure,{skip:process.platform!=='win32'},()=>{
  const invoked=spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',
   path.join(here,'safe_switch_session.ps1'),'-MaintenanceDirectory',maintenance,'-MockFailure',failure],
   {env:cleanEnvironment(),windowsHide:true,encoding:'utf8',timeout:15000});
  assert.equal(invoked.status,0,invoked.stdout+invoked.stderr);
  const rows=invoked.stdout.trim().split(/\r?\n/).filter(Boolean).map(line=>JSON.parse(line));
  const result=rows.findLast(row=>row.format==='schema6-safe-switch-mock-v1');
  assert.equal(result.code,2);
  assert.deepEqual(result.mutations,['Disable:Synthetic-A','Enable:Synthetic-B','Start:Synthetic-B']);
  assert.ok(rows.some(row=>row.step==='rollback.stopped_manual_review'&&row.ok===false&&row.detail===(failure==='close-fails'?'synthetic_close_failed':'synthetic_recovery_lock')));
 });
}

