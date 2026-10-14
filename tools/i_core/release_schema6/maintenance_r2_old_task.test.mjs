import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,readdirSync,unlinkSync,rmdirSync} from 'node:fs';
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
 for(const args of [['old-task'],['old-task','--task','Old','--xml-out','old.xml'],['old-task','--task','Old','--xml-out','old.xml','--security-out','security.json','--approve'],['old-task','--task','Old','--task','Other','--xml-out','x','--security-out','y']])assert.throws(()=>parseEvidenceArguments(args),{code:'evidence_usage'});
});

test('R2b publishes exact inspector XML and current security without normalization',t=>{
 const {root,options}=outputLab(t),xml='<?xml version="1.0"?>\r\n<Task>原样\r\n</Task>\r\n';let inspected=0;
 const runPowerShell=(source,request)=>{
  if(request.parents)return {private:true};
  assert.equal(source,OLD_TASK_INSPECTOR);assert.equal(request.task,options.task);inspected++;
  return {xml,security};
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

test('R2b production inspector rejects enabled or running synthetic task with zero evidence writes', {skip:process.platform!=='win32'},t=>{
 const {root,options}=outputLab(t);
 const adapter=readFileSync(new URL('../test_fixtures/release_schema6/r2_old_task_adapter.ps1',import.meta.url),'utf8');
 for(const state of [{enabled:true,instanceCount:0},{enabled:false,instanceCount:1}]){
  const runPowerShell=(source,request)=>request.parents?{private:true}:runEvidencePowerShell(adapter+'\n'+source,{...request,...state,xml:'unchanged',sddl:'unused',parentSddl:'unused'});
  assert.throws(()=>generateOldTaskEvidence(options,{runPowerShell}),{code:'evidence_inspection_rejected:old_task_not_stopped'});
  assert.deepEqual(readdirSync(root),[]);
 }
});

test('R2b production inspector derives real policy from an in-memory stopped task and refuses foreign write rights', {skip:process.platform!=='win32'},t=>{
 const {root,options}=outputLab(t);
 const adapter=readFileSync(new URL('../test_fixtures/release_schema6/r2_old_task_adapter.ps1',import.meta.url),'utf8');
 const owner=runEvidencePowerShell('@{sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}|ConvertTo-Json -Compress',{}).sid;
 const sddl='O:'+owner+'G:'+owner+'D:(A;;FA;;;'+owner+')(A;;FA;;;SY)(A;;FA;;;BA)';
 const parentSddl='O:SYG:SYD:(A;OI;FR;;;BU)',xml='<?xml version="1.0"?>\r\n<Task>stopped 原样</Task>\r\n';
 const inspect=currentSddl=>(source,request)=>request.parents?{private:true}:runEvidencePowerShell(adapter+'\n'+source,{...request,enabled:false,instanceCount:0,xml,sddl:currentSddl,parentSddl});
 const result=generateOldTaskEvidence(options,{runPowerShell:inspect(sddl)});
 const actual=JSON.parse(readFileSync(options.securityOut));
 assert.equal(readFileSync(options.xmlOut,'utf8'),xml);
 assert.equal(actual.oldTaskSddl,sddl);assert.equal(actual.registrationSddl,sddl);
 assert.equal(actual.parentSddlSha256,sha256(parentSddl));
 assert.equal(actual.expectedRegisteredSddl,sddl+'(A;ID;FR;;;BU)');
 assert.deepEqual(actual.inheritedReadOnlyPrincipals,[{sid:'S-1-5-32-545',flags:16,mask:'00120089'}]);
 assert.equal(actual.taskSecurityPolicyVersion,'windows-file-oi-v1');
 assert.deepEqual(result.security,actual);
 const before=readdirSync(root).map(name=>[name,sha256(readFileSync(path.join(root,name)))]);
 const rejected={...options,xmlOut:path.join(root,'forbidden.xml'),securityOut:path.join(root,'forbidden.json')};
 assert.throws(()=>generateOldTaskEvidence(rejected,{runPowerShell:inspect(sddl+'(A;;FA;;;BU)')}),{code:'evidence_inspection_rejected:task_policy_foreign_rights_rejected'});
 assert.deepEqual(readdirSync(root).map(name=>[name,sha256(readFileSync(path.join(root,name)))]),before);
});
