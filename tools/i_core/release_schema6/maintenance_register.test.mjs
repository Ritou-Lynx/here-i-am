import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,rmSync,mkdirSync} from 'node:fs';
import {syntheticRoot} from '../test_fixtures/release_schema6/synthetic_paths.mjs';
import {createHash} from 'node:crypto';
import {validateFrozenReceipt,validatePreparedReceipt,validatePreparationInputs,taskSecurityBindings} from '../maintenance/prepare-production-login.mjs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..');
test('RegisterOnly has no update/start entry and requires proof validation',()=>{
 const source=readFileSync(path.join(root,'tools/i_core/maintenance/register-approved-login.ps1'),'utf8');
 const helper=readFileSync(path.join(root,'tools/i_core/maintenance/register_task_primitives.ps1'),'utf8');
 assert.match(helper,/RegisterTask\(\$Name,\$Xml,2,/);assert.doesNotMatch(source+helper,/\.Run(?:Ex)?\(/);
 assert.match(source,/--validate-registration/);assert.match(helper,/GetSecurityDescriptor\(7\)/);
 assert.match(source,/Pin-ReleaseInventory \$config\.releaseDirectory \$config\.candidateManifestSha256\s+\$gate=Invoke-VerifiedPrepare/);
 assert.match(source,/finally\{foreach\(\$h in \$locks\)\{\$h\.Dispose\(\)\}\}/);
});
test('real COM: create once, semantic/SDDL readback, existing/difference rejection, bound deletion', {skip:process.platform!=='win32'||process.env.SCHEMA6_SYNTHETIC_TASK_TEST!=='1'},()=>{
 const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
 const extra=process.env.SCHEMA6_SYNTHETIC_TASK_REPORT?['-OutputReport',path.resolve(process.env.SCHEMA6_SYNTHETIC_TASK_REPORT)]:[];
 const stdout=execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(root,'tools/i_core/test_fixtures/release_schema6/maintenance_register_com.ps1'),'-PrimitivesPath',path.join(root,'tools/i_core/maintenance/register_task_primitives.ps1'),...extra],{windowsHide:true,encoding:'utf8',timeout:30000});
 const result=JSON.parse(stdout);for(const k of ['created','readback','existingRejected','xmlDifferenceRejected','deleted','noInstances','disabled','parentStable','securityPolicyVerified'])assert.equal(result[k],true,k);assert.equal(result.triggers,0);assert.ok(Number.isInteger(result.foreignReadOnlyCount)&&result.foreignReadOnlyCount>=0);
});
const H='a'.repeat(64),C='b'.repeat(40);
const digest=b=>createHash('sha256').update(b).digest('hex');
const security=()=>({registrationSddl:'O:SYG:SYD:(A;;FA;;;SY)(A;;FA;;;BA)',expectedRegisteredSddl:'O:SYG:SYD:(A;;FA;;;SY)(A;;FA;;;BA)',parentSddlSha256:H,taskSecurityPolicyVersion:'windows-file-oi-v1',inheritedReadOnlyPrincipals:[]});
function frozenFixture(){
 const createdUtc=new Date(Date.now()-60000).toISOString(),expiresUtc=new Date(Date.now()+60000).toISOString();
 const config={windowId:'synthetic-window',candidateSourceCommit:C,candidateManifestSha256:H,approvedXmlSha256:H,frozenTaskNames:['synthetic-old'],frozenPorts:[40001],rawPaths:['db','wal','shm','journal'],externalFiles:{approvals:['a'],grants:['g']},aclExpected:{notBeforeUtc:createdUtc,notAfterUtc:expiresUtc}};
 const proof={format:'schema6-frozen-legacy-runtime-ready-v2',passed:true,windowId:config.windowId,candidateSourceCommit:C,candidateManifestSha256:H,approvedXmlSha256:H,databaseReplaced:false,aclApplied:false,observationMs:65000,createdUtc,expiresUtc,tasks:[{name:'synthetic-old',taskPath:'\\',originalXmlSha256:H,frozenXmlSha256:H,originalSddl:'O:SYG:SYD:',disabled:true,triggers:0,retries:0,instances:0}],portsFree:[40001],rawAfter:config.rawPaths.map(path=>({path,exists:false})),external:{approvals:{size:1,sha256:H},grants:{size:1,sha256:H}}};return {config,proof};
}
test('freeze binding rejects stale candidate/window, missing rows, expired proof and insufficient observation',()=>{
 const {config,proof}=frozenFixture();assert.equal(validateFrozenReceipt(proof,config),true);
 for(const patch of [{tasks:[{...proof.tasks[0],taskPath:'\\synthetic-old'}]},{candidateSourceCommit:'c'.repeat(40)},{windowId:'another-window'},{rawAfter:proof.rawAfter.slice(1)},{tasks:[{...proof.tasks[0],instances:1}]},{expiresUtc:new Date(0).toISOString()},{observationMs:64999}])assert.throws(()=>validateFrozenReceipt({...proof,...patch},config));
});
test('prepared proof requires exact bytes and every candidate/window/ACL/freeze anchor',()=>{
 const dir=syntheticRoot('maintenance-register-');
 try{const approvedXmlPath=path.join(dir,'approved.xml'),outputXmlPath=path.join(dir,'prepared.xml');writeFileSync(approvedXmlPath,'<Task/>');writeFileSync(outputXmlPath,'<Task/>');
 const c={...security(),windowId:'synthetic-window',candidateSourceCommit:C,candidateManifestSha256:H,frozenReceiptSha256:H,ownerApprovalSha256:H,aclReceiptSha256:H,approvedXmlSha256:digest('<Task/>'),loginConfigurationSha256:H,taskName:'synthetic',approvedXmlPath,outputXmlPath};
 const r={...c,...taskSecurityBindings(c),format:'schema6-production-login-prepare-v3',passed:true,fixed_prepare_validated:true,identical_to_approved_xml:true,registered:false,started:false};assert.equal(validatePreparedReceipt(r,c),true);
 for(const key of ['windowId','candidateSourceCommit','candidateManifestSha256','frozenReceiptSha256','ownerApprovalSha256','aclReceiptSha256','approvedXmlSha256','loginConfigurationSha256','taskName'])assert.throws(()=>validatePreparedReceipt({...r,[key]:'wrong'},c));
 for(const key of Object.keys(taskSecurityBindings(c)))assert.throws(()=>validatePreparedReceipt({...r,[key]:'wrong'},c));
 assert.throws(()=>validatePreparedReceipt({...r,format:'schema6-production-login-prepare-v2'},c));
 writeFileSync(outputXmlPath,'<Task />');assert.throws(()=>validatePreparedReceipt(r,c));
 }finally{rmSync(dir,{recursive:true,force:true});}
});
test('production input does not accept passed-only approvals',async()=>{
 await assert.rejects(validatePreparationInputs({format:'schema6-maintenance-login-config-v2',windowId:'synthetic-window',candidateSourceCommit:C,taskName:'synthetic',frozenTaskNames:[],ownerSid:'S-1-5-18',...security(),ownerApprovalPath:'missing',ownerApprovalSha256:H}));
});
test('preparation consumes complete ACL evidence and refuses omitted readback or old candidate',async()=>{
 const dir=syntheticRoot('maintenance-register-inputs-');
 try{
 const {config:c,proof:f}=frozenFixture();Object.assign(c,{format:'schema6-maintenance-login-config-v2',taskName:'synthetic-new',ownerSid:'S-1-5-18',...security()});
 const windowDirectory=path.join(dir,'windows',c.windowId);mkdirSync(windowDirectory,{recursive:true});c.maintenanceRoot=dir;f.windowDirectory=windowDirectory;
 c.rawPaths=['','-wal','-shm','-journal'].map(s=>path.join(dir,'synthetic-state','db')+s);f.rawAfter=c.rawPaths.map(path=>({path,exists:false}));
 c.externalFiles={approvals:[path.join(dir,'synthetic-state','a')],grants:[path.join(dir,'synthetic-state','g')]};
 c.outputXmlPath=path.join(windowDirectory,'prepared.xml');c.preparedReceiptPath=path.join(windowDirectory,'prepared.json');c.registrationReceiptPath=path.join(windowDirectory,'registered.json');
 const put=(name,obj)=>{const bytes=typeof obj==='string'?obj:JSON.stringify(obj);const file=path.join(windowDirectory,name);writeFileSync(file,bytes);return {path:file,hash:digest(bytes)};};
 let entry=put('review.xml','<Task/>');c.approvedXmlPath=entry.path;c.approvedXmlSha256=entry.hash;f.approvedXmlSha256=entry.hash;
 entry=put('login.json','{}');c.loginConfigurationPath=entry.path;c.loginConfigurationSha256=entry.hash;
 entry=put('frozen.json',f);c.frozenReceiptPath=entry.path;c.frozenReceiptSha256=entry.hash;
 const owner={format:'schema6-owner-gates-approved-v2',windowId:c.windowId,candidateSourceCommit:C,candidateManifestSha256:H,task_name:c.taskName,owner_sid:c.ownerSid,registration_sddl:c.registrationSddl,expected_registered_sddl:c.expectedRegisteredSddl,parent_sddl_sha256:c.parentSddlSha256,task_security_policy_version:c.taskSecurityPolicyVersion,inherited_read_only_principals:c.inheritedReadOnlyPrincipals,xml_review_sha256:c.approvedXmlSha256,login_sha256:c.loginConfigurationSha256,require_fixed_prepare_identical:true};
 entry=put('owner.json',owner);c.ownerApprovalPath=entry.path;c.ownerApprovalSha256=entry.hash;
 Object.assign(c.aclExpected,{windowId:c.windowId,candidateSourceCommit:C,candidateManifestSha256:H,configSha256:H,freezeSha256:c.frozenReceiptSha256,snapshot_sha256:H,paths:[path.join(dir,'synthetic-target')],expectedForeignOwnerCount:0});
 const at=new Date().toISOString();
 const acl={...c.aclExpected,format:'schema6-acl-maintenance-v2',mode:'Apply',passed:true,scope:'owner_and_dacl_only',sacl_restored:false,target_contents_read:false,services_changed:false,tasks_changed:false,rollback_attempted:false,inventory_verified:true,metadata_unchanged:true,freeze_verified:true,expected_count:1,verified_count:1,expected_foreign_owner_count:0,started_utc:at,completed_utc:at,items:['baseline_comparison','apply_owner_dacl','apply_readback'].map(action=>({path:c.aclExpected.paths[0],action,verified:true,code:'',at_utc:at}))};
 entry=put('acl.json',acl);c.aclReceiptPath=entry.path;c.aclReceiptSha256=entry.hash;await validatePreparationInputs(c);
 for(const patch of [{approved_sddl:c.registrationSddl},{registration_sddl:c.registrationSddl+' '},{expected_registered_sddl:c.expectedRegisteredSddl+' '},{parent_sddl_sha256:'c'.repeat(64)},{task_security_policy_version:'unknown'},{inherited_read_only_principals:[{sid:'S-1-5-32-545',flags:16,mask:'00120089'}]}]){
  const changed=put('owner.json',{...owner,...patch});await assert.rejects(validatePreparationInputs({...c,ownerApprovalSha256:changed.hash}));
 }
 entry=put('owner.json',owner);c.ownerApprovalSha256=entry.hash;
 await assert.rejects(validatePreparationInputs({...c,approvedSddl:c.registrationSddl}));
 await assert.rejects(validatePreparationInputs({...c,format:'schema6-maintenance-login-config-v1'}));
 for(const changed of [{...acl,items:acl.items.slice(0,2)},{...acl,candidateSourceCommit:'c'.repeat(40)}]){entry=put('acl.json',changed);c.aclReceiptSha256=entry.hash;await assert.rejects(validatePreparationInputs(c));}
 }finally{rmSync(dir,{recursive:true,force:true});}
});


test('Windows registration pins reject invalid anchors and hold the candidate inventory across processes',{skip:process.platform!=='win32'},()=>{
 const dir=syntheticRoot('maintenance-register-pin-');
 try{
  const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
  const result=JSON.parse(execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(root,'tools/i_core/test_fixtures/release_schema6/maintenance_register_pins.ps1'),'-SourcePath',path.join(root,'tools/i_core/maintenance/register-approved-login.ps1'),'-FixtureParent',dir],{windowsHide:true,encoding:'utf8',timeout:30000}));
  for(const key of ['passed','emptyAndMalformedRejected','correctHashPinned','wrongHashRejected','receiptExceptionExplicit','candidateInventoryPinned','crossProcessWriteRejected','crossProcessReplaceRejected','candidateBytesPreserved','releaseAllowsWrites','candidateHashMismatchRejected','candidateSizeMismatchRejected','candidateShapeRejected','independentInheritanceOracleVerified'])assert.equal(result[key],true);
 }finally{rmSync(dir,{recursive:true,force:true});}
});

test('security disclosure rejects every foreign non-read right and binds exact sorted rows',()=>{
 const c={...security(),ownerSid:'S-1-5-21-1-2-3-1001'};
 assert.deepEqual(taskSecurityBindings(c).inheritedReadOnlyPrincipals,[]);
 const row={sid:'S-1-5-32-545',flags:16,mask:'00120089'};
 assert.deepEqual(taskSecurityBindings({...c,inheritedReadOnlyPrincipals:[row]}).inheritedReadOnlyPrincipals,[row]);
 for(const bit of [0x2,0x4,0x10,0x20,0x40,0x100,0x10000,0x40000,0x80000,0x1000000,0x2000000,0x80000000]){
  const mask=((0x00120089|bit)>>>0).toString(16).toUpperCase().padStart(8,'0');
  assert.throws(()=>taskSecurityBindings({...c,inheritedReadOnlyPrincipals:[{...row,mask}]}));
 }
 for(const rows of [[{...row,flags:0}],[{...row,mask:'0012008a'}],[{...row,unexpected:true}],[row,row],[{...row,sid:'S-1-5-18'}],[{...row,sid:'bad'}],[{...row,sid:'S-1-5-32-546'},row]])assert.throws(()=>taskSecurityBindings({...c,inheritedReadOnlyPrincipals:rows}));
});
