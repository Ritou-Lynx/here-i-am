import assert from 'node:assert/strict';
import {spawnSync,execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,copyFileSync,mkdirSync} from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {sha256,cleanEnvironment} from '../../release_schema6/package.mjs';
import {backupFilePrimitives as files} from '../../release_schema6/backup_bundle.mjs';
import {removeOwned} from '../../release_schema6/lifecycle/test-fixture.mjs';
import {syntheticRoot} from './synthetic_paths.mjs';
import {registrationLab} from './package_switch_registration.mjs';
import {MCP_REGISTRATION_SOURCES} from '../../maintenance/mcp-config-switch-registration.mjs';

const here=path.dirname(fileURLToPath(import.meta.url)),maintenance=path.resolve(here,'../../maintenance');
const ps=process.platform==='win32'?path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe'):null;
const hash=p=>sha256(readFileSync(p));
const entries=['package-switch','mcp-config-switch'];
function rootFor(t){const root=syntheticRoot('maintenance-error-codes-');t.after(()=>removeOwned(root,'maintenance-error-codes-'));return root;}
function powershell(args){return spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',...args],{env:cleanEnvironment(),encoding:'utf8',windowsHide:true,timeout:60000});}
function boundary(root,kind,input){
 const inputPath=path.join(root,'input.json');writeFileSync(inputPath,JSON.stringify(input));
 return powershell(['-File',path.join(here,'maintenance_error_codes.ps1'),'-Entry',path.join(maintenance,'register-'+kind+'-login.ps1'),'-InputPath',inputPath]);
}
function rejected(result,kind,reason){
 assert.equal(result.status,2,result.stdout+result.stderr);
 const row=JSON.parse(result.stdout);assert.equal(row.code,kind.replaceAll('-','_')+'_registration_rejected');
 assert.equal(row.reason,reason);assert.equal(row.passed??row.validated,false);assert.equal(row.registered,false);assert.equal(row.started,false);return row;
}
function unprotect(p){
 const script="$ErrorActionPreference='Stop';$env:PSModulePath=Join-Path $PSHOME 'Modules';$p=[Console]::In.ReadToEnd();$a=Get-Acl -LiteralPath $p;$a.SetAccessRuleProtection($false,$false);Set-Acl -LiteralPath $p -AclObject $a;if((Get-Acl -LiteralPath $p).AreAccessRulesProtected){throw 'fixture_acl_rejected'}";
 execFileSync(ps,['-NoProfile','-NonInteractive','-Command',script],{input:p,env:cleanEnvironment(),windowsHide:true,timeout:30000});
}

for(const [kind,reason] of [['package-switch','registration_usage'],['mcp-config-switch','mcp_registration_usage']]){
 test(kind+' Node validator exposes a whitelisted reason',()=>{
  const r=spawnSync(process.execPath,[path.join(maintenance,kind+'-registration.mjs')],{env:cleanEnvironment(),encoding:'utf8',windowsHide:true});
  const row=rejected(r,kind,reason);assert.match(row.reason,/^[a-z0-9_]{1,64}$/);
 });
 test(kind+' Node validator redacts malformed JSON containing a private path',t=>{
  const root=rootFor(t),input=path.join(root,'malformed-private-input.json');writeFileSync(input,root);
  const r=spawnSync(process.execPath,[path.join(maintenance,kind+'-registration.mjs'),input,hash(input)],{env:cleanEnvironment(),encoding:'utf8',windowsHide:true});
  rejected(r,kind,'unclassified');assert.equal(r.stdout.includes(root),false);
 });
}

test('close entry reports a known code and redacts an exception containing a path',{skip:process.platform!=='win32',timeout:120000},t=>{
 const root=rootFor(t);files.protect(root);const input=path.join(root,'close-input.json');writeFileSync(input,'{}');
 const entry=path.join(root,'close-schema6-session.ps1');copyFileSync(path.join(maintenance,'close-schema6-session.ps1'),entry);
 const invoke=(p,h)=>powershell(['-File',entry,'-ConfigurationPath',p,'-ConfigurationSha256',h]);
 const known=invoke(input,'0'.repeat(64));assert.equal(known.status,2,known.stdout+known.stderr);assert.equal(known.stdout,'');assert.equal(known.stderr.trim(),'approved_session_close_rejected:session_close_input_changed');
 const missing=invoke(path.join(root,'missing-private-input.json'),'0'.repeat(64));assert.equal(missing.status,2);assert.equal(missing.stdout,'');assert.equal(missing.stderr.trim(),'approved_session_close_rejected:unclassified');assert.equal(missing.stderr.includes(root),false);
});

for(const kind of entries){
 test(kind+' registration ACL/catch/output boundary rejects an unprotected backup',{skip:process.platform!=='win32',timeout:120000},t=>{
  const root=rootFor(t);files.protect(root);const backup=path.join(root,'backup.json'),receipt=path.join(root,'receipt.json');writeFileSync(backup,'{}');unprotect(backup);
  const before=hash(backup),r=boundary(root,kind,{mode:'backup',backup,receipt});
  rejected(r,kind,'backup_acl_rejected');assert.equal(hash(backup),before);
  const report=JSON.parse(readFileSync(receipt));assert.equal(report.reason,'backup_acl_rejected');assert.equal(Object.hasOwn(report,'validatorReason'),false);
 });
 test(kind+' registration forwards validator reason safely and preserves success fields',{skip:process.platform!=='win32',timeout:180000},t=>{
  const root=rootFor(t);files.protect(root);
  for(const [name,output,reason] of [['known',JSON.stringify({reason:'registration_anchor_changed'}),'registration_anchor_changed'],['unsafe',JSON.stringify({reason:root}),'unclassified'],['missing',JSON.stringify({validated:false}),'none'],['malformed','not json','none']]){
   const validator=path.join(root,name+'.mjs'),receipt=path.join(root,name+'-receipt.json');
   writeFileSync(validator,'process.stdout.write('+JSON.stringify(output)+');process.exitCode=2;');
   const row=rejected(boundary(root,kind,{mode:'validator',node:process.execPath,validator,receipt}),kind,'registration_proof_rejected');
   assert.equal(row.validatorReason,reason);const report=JSON.parse(readFileSync(receipt));assert.equal(report.reason,row.reason);assert.equal(report.validatorReason,reason);
  }
  const receipt=path.join(root,'unsafe-exception-receipt.json');rejected(boundary(root,kind,{mode:'throw',message:root,receipt}),kind,'unclassified');
  const successReceipt=path.join(root,'success-receipt.json'),success=boundary(root,kind,{mode:'success',receipt:successReceipt});
  assert.equal(success.status,0,success.stdout+success.stderr);assert.deepEqual(JSON.parse(success.stdout),{passed:true,registered:true,started:false,code:kind.replaceAll('-','_')+'_registered_only'});
  const report=JSON.parse(readFileSync(successReceipt));for(const name of ['reason','validatorReason'])assert.equal(Object.hasOwn(report,name),false);
 });
}

// The real session fixture is explicitly CI-only and opts in to nonce tasks.
// Do not set either opt-in locally to make this test run.
test('both registration entries reject the existing session fixture new-side unprotected backup',{skip:process.platform!=='win32'||process.env.GITHUB_ACTIONS!=='true'||process.env.SCHEMA6_SYNTHETIC_TASK_TEST!=='1',timeout:900000},async t=>{
 const f=await registrationLab(t),plan=JSON.parse(readFileSync(f.config.switchPlan.path));
 const backup=plan.artifacts.find(a=>a.role==='backup').path;unprotect(backup);
 rejected(f.invoke(),'package-switch','backup_acl_rejected');
 // Reuse the actual closure and lock evidence for the other entry. This negative
 // proof deliberately contains only backup artifacts: it must reject at the ACL
 // boundary, before the Node proof validator or Scheduler can be reached.
 const source=f.l.dir('mcp-error-code-source'),repository=path.resolve(maintenance,'../../..');
 const ref=p=>({path:p,sha256:hash(p)});
 const maintenanceFiles=MCP_REGISTRATION_SOURCES.map(relative=>{const p=path.join(source,relative);mkdirSync(path.dirname(p),{recursive:true});copyFileSync(path.join(repository,relative),p);return ref(p);});
 const config={...f.config,format:'schema6-mcp-config-switch-registration-v1',maintenanceFiles,closedMarker:f.config.targetMarker};
 const ci=JSON.parse(readFileSync(config.originalCloseInput.path));
 config.mcpStart=ref(path.join(ci.controlDirectory,'mcp-start.json'));
 const proposal=path.join(source,'proposal.json');
 writeFileSync(proposal,JSON.stringify({core:plan.to,candidate:{manifestPath:config.switchPlan.path,manifestSha256:config.switchPlan.sha256},fromArtifacts:plan.fromArtifacts.filter(a=>a.role==='backup'),toArtifacts:plan.artifacts.filter(a=>a.role==='backup')}));
 config.proposal=ref(proposal);const input=path.join(source,'registration.json');writeFileSync(input,JSON.stringify(config));
 rejected(powershell(['-File',path.join(source,'tools/i_core/maintenance/register-mcp-config-switch-login.ps1'),'-ConfigurationPath',input,'-ExpectedConfigurationSha256',hash(input),'-RegisterOnly']),'mcp-config-switch','backup_acl_rejected');
});
