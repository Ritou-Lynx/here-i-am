import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,readdirSync,unlinkSync,rmdirSync,watch,existsSync,lstatSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import test from 'node:test';
import {sha256} from './package.mjs';
import {syntheticRoot} from '../test_fixtures/release_schema6/synthetic_paths.mjs';
import {OLD_TASK_INSPECTOR,parseEvidenceArguments,generateOldTaskEvidence,runEvidencePowerShell,evidenceInspectionError} from '../maintenance/generate-package-switch-evidence.mjs';

function outputLab(t){
 const root=syntheticRoot('schema6-r2-old-task-');
 t.after(()=>{for(const name of readdirSync(root))unlinkSync(path.join(root,name));rmdirSync(root);});
 return {root,options:{task:'HereIAm-Synthetic-Old-Task',xmlOut:path.join(root,'old.xml'),securityOut:path.join(root,'security.json')}};
}
const security={oldTaskSddl:'O:SYG:SYD:(A;;FA;;;SY)',registrationSddl:'O:SYG:SYD:(A;;FA;;;SY)',expectedRegisteredSddl:'O:SYG:SYD:(A;;FA;;;SY)',parentSddlSha256:'a'.repeat(64),inheritedReadOnlyPrincipals:[],taskSecurityPolicyVersion:'windows-file-oi-v1'};

test('R2b old-task CLI requires exact task and two distinct output flags',()=>{
 assert.deepEqual(parseEvidenceArguments(['old-task','--task','Old','--xml-out','old.xml','--security-out','security.json']),{command:'old-task',options:{task:'Old',xmlOut:'old.xml',securityOut:'security.json'}});
 assert.deepEqual(parseEvidenceArguments(['old-task','--task','Old','--preview']),{command:'old-task',options:{task:'Old',preview:true}});
 assert.deepEqual(parseEvidenceArguments(['old-task','--task','Old','--preview','--xml-out','unused.xml','--security-out','unused.json']),{command:'old-task',options:{task:'Old',preview:true,xmlOut:'unused.xml',securityOut:'unused.json'}});
 for(const args of [['old-task'],['old-task','--task','Old','--xml-out','old.xml'],['old-task','--task','Old','--xml-out','old.xml','--security-out','security.json','--approve'],['old-task','--task','Old','--task','Other','--xml-out','x','--security-out','y']])assert.throws(()=>parseEvidenceArguments(args),{code:'evidence_usage'});
});

test('R2b publishes exact inspector XML and current security without normalization',t=>{
 const {root,options}=outputLab(t),xml='<?xml version="1.0"?>\r\n<Task>原样\r\n</Task>\r\n';let inspected=0;
 const runPowerShell=(source,request)=>{
  if(request.parents)return {private:true};
  assert.equal(source,OLD_TASK_INSPECTOR);assert.equal(request.task,options.task);inspected++;
  return {xml,security,oldTaskStopped:true};
 };
 const result=generateOldTaskEvidence(options,{runPowerShell});
 assert.equal(inspected,1);assert.equal(readFileSync(options.xmlOut,'utf8'),xml);
 assert.deepEqual(JSON.parse(readFileSync(options.securityOut)),security);
 assert.equal(result.summary.xmlSha256,sha256(Buffer.from(xml)));
 assert.equal(result.summary.oldTasksChanged,false);assert.equal(result.summary.started,false);
 const before=readdirSync(root).map(name=>[name,sha256(readFileSync(path.join(root,name)))]);
 assert.throws(()=>generateOldTaskEvidence(options,{runPowerShell}),{code:'evidence_output_exists'});
 assert.deepEqual(readdirSync(root).map(name=>[name,sha256(readFileSync(path.join(root,name)))]),before);
});

test('R2b existing second output and colliding paths are rejected before inspection',t=>{
 const {options}=outputLab(t);writeFileSync(options.securityOut,'existing');
 const runPowerShell=()=>assert.fail('occupied output must reject before inspection');
 assert.throws(()=>generateOldTaskEvidence(options,{runPowerShell}),{code:'evidence_output_exists'});
 assert.equal(readFileSync(options.securityOut,'utf8'),'existing');
 assert.throws(()=>generateOldTaskEvidence({...options,securityOut:options.xmlOut},{runPowerShell}),{code:'evidence_output_collision'});
});

test('R2b inspection diagnostics expose only a bounded internal error code',()=>{
 assert.equal(evidenceInspectionError({stderr:Buffer.from('old_task_not_stopped\r\n')}).code,'evidence_inspection_rejected:old_task_not_stopped');
 for(const stderr of ['C:\\private\\secret.json','bad\nsecond_line','A'.repeat(65),'code with value'])assert.equal(evidenceInspectionError({stderr}).message,'evidence_inspection_rejected:evidence_inspection_rejected');
});

test('R2b real PS 5.1 catch forwards safe errors and redacts unsafe messages without COM', {skip:process.platform!=='win32'},()=>{
 assert.throws(()=>runEvidencePowerShell("throw 'old_task_not_stopped'",{}),{code:'evidence_inspection_rejected:old_task_not_stopped'});
 assert.throws(()=>runEvidencePowerShell("throw 'private path and values'",{}),{code:'evidence_inspection_rejected:evidence_inspection_rejected'});
});

function directorySnapshot(root){
 const result=[];
 const visit=(directory,relative='')=>{
  for(const name of readdirSync(directory).sort()){
   const absolute=path.join(directory,name),key=path.join(relative,name),stat=lstatSync(absolute);
   assert.equal(stat.isSymbolicLink(),false,'snapshot never follows linked paths');
   if(stat.isDirectory()){result.push([key,'directory']);visit(absolute,key);}
   else{assert.equal(stat.isFile(),true);result.push([key,sha256(readFileSync(absolute))]);}
  }
 };
 visit(root);return result;
}
test('R2b preview preserves UTF-8, environment and evidence; only completed host policy probes may touch TEMP', {skip:process.platform!=='win32'},async t=>{
 const {root,options}=outputLab(t),events=[];
 const temporaryRoot=tmpdir();
 const maintenance=fileURLToPath(new URL('../maintenance/',import.meta.url));
 const fixture=policyFixture();
 // Do not redirect TEMP/TMP or modify host policy to avoid its normal probes.
 const environment={TEMP:process.env.TEMP,TMP:process.env.TMP};
 const before={temporaryNames:readdirSync(temporaryRoot).sort(),output:directorySnapshot(root),maintenance:directorySnapshot(maintenance)};
 const observer=watch(temporaryRoot,(eventType,name)=>events.push({eventType,name:String(name)}));
 try{
  const xml='原样 XML — 中文 ✓\r\n';
  const result=runEvidencePowerShell('@{xml=$request.xml;temp=$env:TEMP;tmp=$env:TMP}|ConvertTo-Json -Compress',{xml},{readOnly:true});
  assert.equal(result.xml,xml);
  assert.equal(result.temp,environment.TEMP);assert.equal(result.tmp,environment.TMP);
  assert.throws(()=>runEvidencePowerShell("throw 'old_task_not_stopped'",{},{readOnly:true}),{code:'evidence_inspection_rejected:old_task_not_stopped'});
  assert.throws(()=>runEvidencePowerShell("throw 'private path and values'",{},{readOnly:true}),{code:'evidence_inspection_rejected:evidence_inspection_rejected'});
  const preview=generateOldTaskEvidence({...options,preview:true},{runPowerShell:inspectFixture({...fixture,enabled:true})});
  assert.equal(preview.summary.oldTaskStopped,false);
  // Let Windows deliver watcher events, including short-lived create/delete.
  await new Promise(resolve=>setTimeout(resolve,50));
  const eventEvidence=[...new Map(events.map(event=>[event.eventType+'\0'+event.name,event])).values()].map(event=>({...event,existedBefore:before.temporaryNames.includes(event.name),existsAtEnd:existsSync(path.join(temporaryRoot,event.name))}));
  t.diagnostic(JSON.stringify({temporaryEvents:eventEvidence,outputUnchanged:JSON.stringify(directorySnapshot(root))===JSON.stringify(before.output),maintenanceUnchanged:JSON.stringify(directorySnapshot(maintenance))===JSON.stringify(before.maintenance),environmentUnchanged:process.env.TEMP===environment.TEMP&&process.env.TMP===environment.TMP,newResidualNames:readdirSync(temporaryRoot).filter(name=>!before.temporaryNames.includes(name))}));
  const unexpected=[...new Set(events.map(event=>event.name))].filter(name=>{
   const allowed=/^__PSScriptPolicyTest_[A-Za-z0-9_.-]+\.(?:ps1|psm1)$/.test(name)&&path.basename(name)===name;
   return !allowed||existsSync(path.join(temporaryRoot,name));
  });
  assert.deepEqual(unexpected,[],'only vanished, specifically named host policy probes are exempt');
  assert.deepEqual(readdirSync(temporaryRoot).sort(),before.temporaryNames,'no new TEMP residue or removed pre-existing entries');
  assert.deepEqual(directorySnapshot(root),before.output,'output paths and their parent remain unchanged');
  assert.deepEqual(directorySnapshot(maintenance),before.maintenance,'maintenance sources remain unchanged');
  assert.deepEqual({TEMP:process.env.TEMP,TMP:process.env.TMP},environment);
 }finally{
  observer.close();
 }
});

test('R2b production inspector rejects enabled or running synthetic task with zero evidence writes', {skip:process.platform!=='win32'},t=>{
 const {root,options}=outputLab(t);
 const adapter=readFileSync(new URL('../test_fixtures/release_schema6/r2_old_task_adapter.ps1',import.meta.url),'utf8');
 for(const state of [{enabled:true,instanceCount:0},{enabled:false,instanceCount:1}]){
  const runPowerShell=(source,request)=>request.parents?{private:true}:runEvidencePowerShell(adapter+'\n'+source,{...request,...state,xml:'unchanged',sddl:'unused',parentSddl:'unused'});
  assert.throws(()=>generateOldTaskEvidence(options,{runPowerShell}),{code:'evidence_inspection_rejected:old_task_not_stopped'});
  assert.deepEqual(readdirSync(root),[]);
 }
});

let cachedOwner;
function policyFixture(){
 cachedOwner??=runEvidencePowerShell('@{sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}|ConvertTo-Json -Compress',{}).sid;
 const owner=cachedOwner;
 // Different group plus a deliberately non-default explicit order prove that
 // extraction preserves the old descriptor instead of replacing it with a preset.
 const explicit='O:'+owner+'G:BAD:(A;;FA;;;BA)(A;;FA;;;'+owner+')(A;;FA;;;SY)';
 const inherited='(A;ID;FR;;;BU)(A;ID;FR;;;SY)';
 const parentSddl='O:SYG:SYD:(A;OI;FR;;;BU)(A;OI;FR;;;SY)';
 return {enabled:false,instanceCount:0,xml:'<?xml version="1.0"?>\r\n<Task>stopped 原样</Task>\r\n',sddl:explicit+inherited,parentSddl,explicit,inherited};
}
const adapter=readFileSync(new URL('../test_fixtures/release_schema6/r2_old_task_adapter.ps1',import.meta.url),'utf8');
function inspectFixture(fixture,{onRun=()=>{}}={}){
 return (source,request,execution)=>{
  onRun(source,request,execution);
  if(request.parents)return {private:true};
  return runEvidencePowerShell(adapter+'\n'+source+'\nAssert-SyntheticTaskFolderUnchanged',{...request,...fixture},execution);
 };
}
test('R2b inherited old task round-trips through the real policy while preserving owner, group and explicit ACE order', {skip:process.platform!=='win32'},t=>{
 const {root,options}=outputLab(t);
 const fixture=policyFixture();
 const result=generateOldTaskEvidence(options,{runPowerShell:inspectFixture(fixture)});
 const actual=JSON.parse(readFileSync(options.securityOut));
 assert.equal(readFileSync(options.xmlOut,'utf8'),fixture.xml);
 assert.equal(actual.oldTaskSddl,fixture.sddl);
 assert.equal(actual.registrationSddl,fixture.explicit);
 assert.equal(actual.parentSddlSha256,sha256(fixture.parentSddl));
 assert.equal(actual.expectedRegisteredSddl,fixture.sddl);
 assert.deepEqual(actual.inheritedReadOnlyPrincipals,[{sid:'S-1-5-32-545',flags:16,mask:'00120089'}]);
 assert.equal(actual.taskSecurityPolicyVersion,'windows-file-oi-v1');
 assert.deepEqual(result.security,actual);
 assert.equal(readdirSync(root).length,2);
});

test('R2b refuses explicit foreign read or write ACEs and other explicit flags instead of filtering them', {skip:process.platform!=='win32'},t=>{
 const {root,options}=outputLab(t),fixture=policyFixture();
 for(const ace of ['(A;;FR;;;BU)','(A;;FA;;;BU)','(A;OI;FR;;;SY)','(A;CI;FR;;;BA)']){
  const invalid={...fixture,sddl:fixture.explicit+ace+fixture.inherited};
  assert.throws(()=>generateOldTaskEvidence(options,{runPowerShell:inspectFixture(invalid)}),{code:'evidence_inspection_rejected:task_policy_explicit_principal_rejected'});
  assert.deepEqual(readdirSync(root),[]);
 }
});

test('R2b refuses an old descriptor that cannot be derived from the current parent', {skip:process.platform!=='win32'},t=>{
 const {root,options}=outputLab(t),fixture=policyFixture();
 // The old inherited BU read right is absent from the present parent. Both SDs
 // individually pass allowed-rights checks; only the round-trip detects drift.
 const changed={...fixture,parentSddl:'O:SYG:SYD:(A;OI;FR;;;SY)'};
 assert.throws(()=>generateOldTaskEvidence(options,{runPowerShell:inspectFixture(changed)}),{code:'evidence_inspection_rejected:old_task_security_not_derivable'});
 assert.deepEqual(readdirSync(root),[]);
});

test('R2b extraction does not hide forbidden inherited write rights from full old-task validation', {skip:process.platform!=='win32'},t=>{
 const {root,options}=outputLab(t),fixture=policyFixture();
 const unsafe={...fixture,sddl:fixture.explicit+'(A;ID;FA;;;BU)(A;ID;FR;;;SY)'};
 assert.throws(()=>generateOldTaskEvidence(options,{runPowerShell:inspectFixture(unsafe)}),{code:'evidence_inspection_rejected:task_policy_foreign_rights_rejected'});
 assert.throws(()=>generateOldTaskEvidence({task:options.task,preview:true},{runPowerShell:inspectFixture({...unsafe,enabled:true})}),{code:'evidence_inspection_rejected:task_policy_foreign_rights_rejected'});
 assert.deepEqual(readdirSync(root),[]);
});

test('R2b refuses a parent that changes after the initial snapshot', {skip:process.platform!=='win32'},t=>{
 const {root,options}=outputLab(t),fixture=policyFixture();
 const changed={...fixture,parentSddlAfter:'O:SYG:SYD:(A;OI;FR;;;SY)'};
 assert.throws(()=>generateOldTaskEvidence(options,{runPowerShell:inspectFixture(changed)}),error=>['evidence_inspection_rejected:old_task_security_not_derivable','evidence_inspection_rejected:old_task_snapshot_changed'].includes(error.code));
 assert.deepEqual(readdirSync(root),[]);
});

test('R2b preview asks for read-only execution and exposes only hashes and status without output paths',t=>{
 const {root,options}=outputLab(t);let calls=0;
 // Existing output paths must be ignored by a preview, and never replaced.
 writeFileSync(options.xmlOut,'keep xml');writeFileSync(options.securityOut,'keep security');
 const before=readdirSync(root).map(name=>[name,sha256(readFileSync(path.join(root,name)))]);
 const runPowerShell=(source,request,execution)=>{
  assert.equal(source,OLD_TASK_INSPECTOR);assert.equal(request.preview,true);
  assert.equal(execution?.readOnly,true);calls++;
  return {xml:'private task XML',security,oldTaskStopped:false};
 };
 const result=generateOldTaskEvidence({...options,preview:true},{runPowerShell});
 assert.equal(calls,1);assert.deepEqual(Object.keys(result),['summary']);
 assert.equal(result.summary.oldTaskStopped,false);assert.equal(result.summary.xmlSha256,sha256('private task XML'));
 assert.deepEqual(Object.keys(result.summary).sort(),['xmlSha256','securitySha256','oldTaskSddlSha256','registrationSddlSha256','expectedRegisteredSddlSha256','parentSddlSha256','inheritedReadOnlyPrincipalsSha256','oldTaskStopped'].sort());
 for(const [name,value] of Object.entries(result.summary)){if(name!=='oldTaskStopped')assert.match(value,/^[a-f0-9]{64}$/);}
 assert.doesNotMatch(JSON.stringify(result),/private task XML|O:SYG:SY|old\.xml|security\.json/);
 assert.deepEqual(readdirSync(root).map(name=>[name,sha256(readFileSync(path.join(root,name)))]),before);
});

test('R2b preview skips only stopped checks and still validates current inheritance and unsafe explicit ACEs', {skip:process.platform!=='win32'},t=>{
 const {root,options}=outputLab(t),fixture=policyFixture();
 for(const state of [{enabled:true,instanceCount:0},{enabled:false,instanceCount:1},{enabled:true,instanceCount:1},{enabled:false,instanceCount:0}]){
  const current={...fixture,...state};
  const runPowerShell=inspectFixture(current,{onRun:(_source,request,execution)=>{assert.equal(request.parents,undefined);assert.equal(execution?.readOnly,true);}});
  const {summary}=generateOldTaskEvidence({task:options.task,preview:true},{runPowerShell});
  assert.equal(summary.oldTaskStopped,!state.enabled&&state.instanceCount===0);
  assert.equal(summary.xmlSha256,sha256(fixture.xml));
  assert.deepEqual(readdirSync(root),[]);
 }
 const errors=[
  [{...fixture,enabled:true,parentSddl:'O:SYG:SYD:(A;OI;FR;;;SY)'},'old_task_security_not_derivable'],
  [{...fixture,enabled:true,sddl:fixture.explicit+'(A;;FR;;;BU)'+fixture.inherited},'task_policy_explicit_principal_rejected'],
  [{...fixture,instanceCount:1,parentSddlAfter:'O:SYG:SYD:(A;OI;FR;;;SY)'},'old_task_snapshot_changed'],
 ];
 for(const [current,code] of errors){
  assert.throws(()=>generateOldTaskEvidence({task:options.task,preview:true},{runPowerShell:inspectFixture(current)}),{code:'evidence_inspection_rejected:'+code});
  assert.deepEqual(readdirSync(root),[]);
 }
});
