import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import test from 'node:test';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {sha256,cleanEnvironment} from './package.mjs';
import {ps,repository} from './lifecycle/test-fixture.mjs';
import {registrationLab} from '../test_fixtures/release_schema6/package_switch_registration.mjs';
import {validateSwitchRegistrationEvidence} from '../maintenance/package-switch-registration.mjs';
const H='a'.repeat(64),N='b'.repeat(64),E='c'.repeat(64),F='d'.repeat(64),P='e'.repeat(64),T='f'.repeat(64);
function evidence(){
 const from={manifestSha256:H,configurationSha256:H},to={manifestSha256:N,configurationSha256:N};
 const plan={approved:true,from,to,expectedMarkerSha256:H,expectedHeadSha256:H,artifacts:[{role:'login',sha256:N}]};
 const marker={format:'schema6-lifecycle-v1',phase:'clean_closed',token:T,database_path:'synthetic-db',node_id:'synthetic-node',database_sha256:H,manifest_sha256:N,configuration_sha256:N,package_switch_plan_sha256:P,package_switch_event_sha256:E,custody_sha256:F};
 const head={format:'i-core-custody-head-v1',generation:7,custodySha256:F,receiptId:T,databasePath:marker.database_path,nodeId:marker.node_id,authentication:H};
 const floor={format:'i-core-floor-custody-v1',schemaVersion:6,databasePath:marker.database_path,nodeId:marker.node_id,packageSwitchEventSha256:E,cleanCloseReceiptId:T,databaseSha256:H,authentication:H};
 const event={format:'i-core-package-switch-event-v1',planSha256:P,previousHeadSha256:H,databaseSha256:H,from,to,databasePath:marker.database_path,nodeId:marker.node_id,sourceMarker:{manifest_sha256:H,configuration_sha256:H,token:H,phase:'clean_closed',database_sha256:H},authentication:H};
 const result={job_empty_confirmed:true,child_exit_confirmed:true,child_exit_code_confirmed:true,guardian_exit_confirmed:true,guardian_exit_code_confirmed:true,child_exit_code:0,guardian_exit_code:0,termination_requested:false};
 const offline={child:{token:T,manifest_sha256:N,mode:'offline-package-switch',phase:'clean_closed',reason:'package_switch_completed',store_construction_attempted:false,store_close_confirmed:true,listener_closed_confirmed:true},supervisor:{token:T,manifest_sha256:N,mode:'offline-package-switch',child_receipt_confirmed:true,guardian_receipt_confirmed:true,lock_released_confirmed:true,result},guardian:{run_id:T,result:{job_empty_confirmed:true,parent_exit_observed:false}}};
 return {plan,planSha256:P,marker,head,event,floor,operation:{operation:'offline-package-switch',event_sha256:E,head_sha256:H,target_manifest_sha256:N,custody_generation:7},offline,close:{closed:true,originalHostExitConfirmed:true,wmCloseOnly:true,coreForced:false,databaseExclusiveOpenConfirmed:true,budgetMs:30000,externalCloseElapsedMs:999,manifestSha256:H,configurationSha256:H,receiptSha256:{marker:H}},closeInput:{sha256:H},sourceMarker:event.sourceMarker,originalToken:H,prepare:{prepared:true,registered:false,started:false,manifest_sha256:N,login_configuration_sha256:N},markerSha256:N,headSha256:H,eventSha256:E,floorSha256:F};
}
test('same-schema registration requires the linked close, Native offline, marker/head and fixed Prepare receipts',()=>{
 const good=evidence();assert.equal(validateSwitchRegistrationEvidence(good).validated,true);
 const changes=[x=>x.floor.schemaVersion=4,x=>x.floor.databasePath='wrong',x=>x.event.previousHeadSha256=N,x=>x.event.databaseSha256=N,x=>x.originalToken=N,x=>x.marker.phase='opening',x=>x.marker.manifest_sha256=H,x=>x.marker.package_switch_plan_sha256=H,x=>x.head.receiptId=H,x=>x.operation.head_sha256=N,x=>x.operation.event_sha256=H,x=>x.offline.child.store_construction_attempted=true,x=>x.offline.supervisor.result.termination_requested=true,x=>x.offline.guardian.result.job_empty_confirmed=false,x=>x.close.externalCloseElapsedMs=30000,x=>x.close.manifestSha256=N,x=>x.prepare.login_configuration_sha256=H,x=>x.prepare.started=true,x=>x.plan.artifacts[0].sha256=H];
 for(const mutate of changes){const x=structuredClone(good);mutate(x);assert.throws(()=>validateSwitchRegistrationEvidence(x),/^Error: registration_/);}
});
test('RegisterOnly composes current schema6 gates and never enters the first-cutover chain',()=>{
 const source=readFileSync(new URL('../maintenance/register-package-switch-login.ps1',import.meta.url),'utf8');
 assert.doesNotMatch(source,/freeze-legacy|prepare-production-login|aclReceipt|frozenReceipt|\.Run(?:Ex)?\(|\.DeleteTask\(/);
 assert.match(source,/shortcut-mail-relay\.runtime\.lock/);assert.match(source,/Assert-OldPackageTask/);assert.match(source,/Assert-BackupPrivateAcl/);
 assert.match(source,/New-ApprovedTask .*\$config\.registrationSddl/);assert.match(source,/Assert-RegisteredTask .*\$config\.expectedRegisteredSddl/);
 assert.match(source,/\$registered.Enabled=\$false/);assert.match(source,/Write-OwnedArtifactBytes/);
 assert.ok(source.indexOf('foreach($entry in $config.maintenanceFiles){Pin-Ref $entry}')<source.indexOf('. (Join-Path $PSScriptRoot'));
 assert.ok(source.indexOf('Pin-ReleaseInventory $end.releaseDirectory')<source.indexOf('$gate=Invoke-SwitchRegistrationValidator'));
});

test('real close and single Native forward feed fixed Prepare and same-schema RegisterOnly', {skip:process.platform!=='win32',timeout:900000},async t=>{
 const f=await registrationLab(t),fixture=path.join(repository,'tools/i_core/test_fixtures/release_schema6/package_switch_registration.ps1');let sequence=0;
 const step=mode=>{const output=path.join(path.dirname(f.configurationPath),'com-'+(++sequence)+'.json');execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',fixture,'-ConfigurationPath',f.configurationPath,'-Mode',mode,'-OutputPath',output],{env:cleanEnvironment(),windowsHide:true,encoding:'utf8',timeout:90000});return JSON.parse(readFileSync(output));};
 const prepared=step('Prepare');for(const k of ['registrationXml','expectedRegisteredSddl','parentSddlSha256','inheritedReadOnlyPrincipals'])f.config[k]=prepared[k];f.publish();
 assert.equal(f.validate().nativeOfflineReceiptsBound,true);assert.equal(f.validate().hmacRechecked,false);
 const originalMarker=f.config.targetMarker;f.config.targetMarker={...originalMarker,sha256:'0'.repeat(64)};f.publish();assert.throws(()=>f.validate());f.config.targetMarker=originalMarker;f.publish();
 const p=JSON.parse(readFileSync(f.config.switchPlan.path));const badPlan=path.join(path.dirname(f.configurationPath),'bad-plan.json');p.artifacts[0].sha256='0'.repeat(64);writeFileSync(badPlan,JSON.stringify(p));const originalPlan=f.config.switchPlan;f.config.switchPlan={path:badPlan,sha256:sha256(readFileSync(badPlan))};f.publish();assert.throws(()=>f.validate());f.config.switchPlan=originalPlan;f.publish();
 assert.equal(step('AssertOldReject').activeOldRejected,true);
 if(process.env.SCHEMA6_SYNTHETIC_TASK_TEST!=='1'){
  t.diagnostic('real Native/Prepare/registration validator passed; real COM CREATE gated to SCHEMA6_SYNTHETIC_TASK_TEST=1');f.l.completed=true;return;
 }
 const originalName=f.config.taskName,originalReceipt=f.config.registrationReceiptPath;let oldAttempted=false,completed=false;
 try{
  oldAttempted=true;const old=step('CreateOld');f.config.oldTask=old.oldTask;f.publish();assert.equal(f.validate().validated,true);
  const parent=f.config.parentSddlSha256;f.config.parentSddlSha256='0'.repeat(64);f.publish();const rejected=f.invoke();assert.equal(rejected.status,2,rejected.stdout+rejected.stderr);f.config.parentSddlSha256=parent;
  f.config.registrationReceiptPath=originalReceipt+'.positive';f.publish();const result=f.invoke();assert.equal(result.status,0,result.stdout+result.stderr);assert.equal(step('Check').disabled,true);
  const r=JSON.parse(readFileSync(f.config.registrationReceiptPath));assert.equal(r.createdTaskDisabled,true);assert.equal(r.started,false);assert.equal(r.registrationXmlSha256,f.config.registrationXml.sha256);
  f.config.registrationReceiptPath=originalReceipt+'.existing';f.publish();const existing=f.invoke();assert.equal(existing.status,2,existing.stdout+existing.stderr);assert.equal(step('Check').instancesZero,true);completed=true;
 }finally{
  f.config.taskName=originalName;f.config.registrationReceiptPath=originalReceipt;f.publish();if(oldAttempted){const cleaned=step('Cleanup');if(completed)assert.equal(cleaned.deleted,2);}
 }
 f.l.completed=true;
});
