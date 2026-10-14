import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const here=path.dirname(fileURLToPath(import.meta.url));
const maintenance=path.resolve(here,'../../maintenance');
const script=readFileSync(path.join(maintenance,'switch-login-task.ps1'),'utf8');
const marker="Write-Schema6Step 'switch.stopped_no_rollback' $false 'reverse_package_switch_required:需要反向换包'";

test('R1 NoRollback leaves the legacy switch implementation byte-for-byte intact',()=>{
 const restored=script.replace(/\r?\n/g,'\r\n')
  .replaceAll(',[switch]$NoRollback','')
  .replace(';if($NoRollback){'+marker+'}','')
  .replace(' if($NoRollback){'+marker+';return 2}\r\n','')
  .replace(' -NoRollback:$NoRollback','');
 // Exact BOM + CRLF source at contract baseline 69d9eb0d.
 assert.equal(createHash('sha256').update(restored).digest('hex'),
  'ecffd302a41f423f7109a4b66a0c27d7fd94385690d5d04d3d33aa23c0185510');
 assert.equal(script.match(/\[switch\]\$NoRollback/g)?.length,2,'CLI and function expose the switch');
 assert.match(script,/-DryRun:\$DryRun -NoRollback:\$NoRollback\r?\n/,'CLI forwards the switch');
 assert.ok(script.indexOf('if($NoRollback){'+marker+';return 2}')<script.indexOf("'rollback.stop_new'"));
});

test('R1 NoRollback regression suite is selected by the existing Windows runners',()=>{
 const runner=readFileSync(path.join(here,'run_windows_tests.ps1'),'utf8');
 assert.match(runner,/-Filter 'maintenance_safe_switch\*\.test\.mjs'/);
 assert.ok(path.basename(fileURLToPath(import.meta.url)).startsWith('maintenance_safe_switch'));
});

const windowsCI={skip:process.platform!=='win32'||process.env.CI!=='true',timeout:20000};
function run(scenario,mode='absent',dryRun=false){
 const env=Object.fromEntries(Object.entries(process.env).filter(([name])=>! /^(NODE_|I_CORE_)/i.test(name)));
 const executable=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
 const result=spawnSync(executable,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',
  path.join(here,'r1_no_rollback_com.ps1'),'-MaintenanceDirectory',maintenance,'-Scenario',scenario,'-Mode',mode,
  ...(dryRun?['-DryRun']:[])],{env,windowsHide:true,encoding:'utf8',timeout:15000});
 assert.ifError(result.error);
 assert.equal(result.signal,null,result.stderr);
 assert.equal(result.stderr,'');
 const report=JSON.parse(result.stdout.trim());
 assert.equal(report.format,'schema6-r1-no-rollback-v1');
 assert.equal(result.status,report.code,'real PowerShell exit code matches the switch result');
 report.rows=Buffer.from(report.outputBase64,'base64').toString('utf8').trim().split(/\r?\n/).map(JSON.parse);
 return report;
}
const primaryFailures=['preflight','stop-old','sessions','disable-old','enable-new','start-new','ready-new'];
const forward=['Disable:Synthetic-A','Enable:Synthetic-B','Start:Synthetic-B'];
const rollback=['Disable:Synthetic-B','Enable:Synthetic-A','Start:Synthetic-A'];
function completedForward(scenario){
 return forward.slice(0,({preflight:0,'stop-old':0,sessions:0,'disable-old':0,'enable-new':1,'start-new':2,'ready-new':3})[scenario]??3);
}
function normalized(report){
 const {outputBase64,...rest}=report;
 return rest;
}
for(const scenario of primaryFailures){
 test('R1 NoRollback stops in place with no old-task restart: '+scenario,windowsCI,()=>{
  const report=run(scenario,'true');
  const completed=completedForward(scenario);
  assert.equal(report.code,2);
  assert.deepEqual(report.operations,completed,'no cleanup or rollback mutation is performed');
  assert.equal(report.startedA,0);
  assert.equal(report.enabledA,!completed.includes('Disable:Synthetic-A'));
  assert.equal(report.enabledB,completed.includes('Enable:Synthetic-B'));
  assert.equal(report.startedB,completed.includes('Start:Synthetic-B')?1:0);
  assert.ok(!report.events.some(event=>['Enable:Synthetic-A','Start:Synthetic-A','Stop:Synthetic-B','Closed:Synthetic-B','Ready:Synthetic-A'].includes(event)));
  assert.ok(!report.rows.some(row=>row.step.startsWith('rollback.')));
  assert.deepEqual(report.rows.at(-1),{step:'switch.stopped_no_rollback',ok:false,detail:'reverse_package_switch_required:需要反向换包'});
  assert.ok(report.rows.some(row=>row.ok===false&&row.detail.startsWith('synthetic_')),'original failure remains diagnosable');
 });
 test('R1 omitted and explicit false keep legacy failure behavior: '+scenario,windowsCI,()=>{
  const report=run(scenario);
  assert.deepEqual(normalized(run(scenario,'false')),normalized(report));
  const beforeMutation=['preflight','stop-old'].includes(scenario);
  assert.equal(report.code,beforeMutation?2:1);
  assert.deepEqual(report.operations,beforeMutation?[]:[...completedForward(scenario),...rollback]);
  assert.equal(report.startedA,beforeMutation?0:1);
  assert.equal(report.enabledA,true);
  assert.equal(report.enabledB,false);
  assert.ok(!report.rows.some(row=>row.step==='switch.stopped_no_rollback'));
  if(!beforeMutation)assert.deepEqual(report.rows.at(-1),{step:'switch.result',ok:false,detail:'rolled_back'});
 });
}
for(const dryRun of [false,true]){
 test('R1 NoRollback preserves successful '+(dryRun?'dry-run':'switch')+' output and side effects',windowsCI,()=>{
  const legacy=run('success','absent',dryRun);
  assert.deepEqual(normalized(run('success','false',dryRun)),normalized(legacy));
  assert.deepEqual(normalized(run('success','true',dryRun)),normalized(legacy));
  assert.equal(legacy.code,0);
  assert.deepEqual(legacy.operations,dryRun?[]:forward);
  assert.equal(legacy.startedA,0);
  assert.equal(legacy.startedB,dryRun?0:1);
  assert.deepEqual(legacy.rows.at(-1),{step:'switch.result',ok:true,detail:dryRun?'dry_run_passed':'switched'});
 });
}
for(const scenario of ['rollback-stop','rollback-closed','rollback-ready']){
 test('R1 legacy rollback safety failure stays unchanged: '+scenario,windowsCI,()=>{
  const legacy=run(scenario);
  assert.equal(legacy.code,2);
  assert.deepEqual(normalized(run(scenario,'false')),normalized(legacy));
  assert.deepEqual(legacy.operations,scenario==='rollback-ready'?[...forward,...rollback]:forward);
  assert.equal(legacy.rows.at(-1).step,'rollback.stopped_manual_review');
  assert.equal(legacy.rows.at(-1).ok,false);
  const noRollback=run(scenario,'true');
  assert.equal(noRollback.code,2);
  assert.deepEqual(noRollback.operations,forward);
  assert.equal(noRollback.startedA,0);
  assert.ok(!noRollback.events.includes('Stop:Synthetic-B'));
  assert.equal(noRollback.rows.at(-1).detail,'reverse_package_switch_required:需要反向换包');
 });
}
