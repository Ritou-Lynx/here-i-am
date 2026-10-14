import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync,existsSync,readdirSync} from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {parseEvidenceArguments,generateRegistrationEvidence} from '../maintenance/generate-package-switch-evidence.mjs';
import {registrationLab} from '../test_fixtures/release_schema6/package_switch_registration.mjs';

const directory=path.dirname(fileURLToPath(import.meta.url));
const maintenance=path.join(directory,'../maintenance');

test('R2 close input CLI preserves explicit approval and rejects ambiguous flags',()=>{
 const plain=parseEvidenceArguments(['close-input','--task','Synthetic','--out','new.json']);
 assert.equal(plain.command,'close-input');assert.equal(plain.options.approve,undefined);
 assert.equal(parseEvidenceArguments(['close-input','--task','Synthetic','--out','new.json','--approve']).options.approve,true);
 for(const args of [[],['close-input'],['close-input','--task','A','--task','B','--out','x'],['close-input','--task','A','--out','x','--approve','false'],['close-input','--task','A','--out','x','--dry-run'],['registration','--out','x']]){
  assert.throws(()=>parseEvidenceArguments(args),{code:'evidence_usage'});
 }
});

test('R2 NoRollback legacy hash is identical for LF and CRLF checkouts',()=>{
 const source=readFileSync(path.join(maintenance,'switch-login-task.ps1'),'utf8');
 const marker="Write-Schema6Step 'switch.stopped_no_rollback' $false 'reverse_package_switch_required:需要反向换包'";
 for(const ending of ['\n','\r\n']){
  const checkout=source.replace(/\r?\n/g,ending);
  const restored=checkout.replace(/\r?\n/g,'\r\n').replaceAll(',[switch]$NoRollback','')
   .replace(';if($NoRollback){'+marker+'}','').replace(' if($NoRollback){'+marker+';return 2}\r\n','').replace(' -NoRollback:$NoRollback','');
  assert.equal(createHash('sha256').update(restored).digest('hex'),'ecffd302a41f423f7109a4b66a0c27d7fd94385690d5d04d3d33aa23c0185510');
 }
});

test('R2 registration fixture uses generators while preserving explicit rejection mutations',()=>{
 const fixture=readFileSync(new URL('../test_fixtures/release_schema6/package_switch_registration.mjs',import.meta.url),'utf8');
 assert.match(fixture,/r2_fixture_ci_only/);
 assert.match(fixture,/generateCloseInput\(/);assert.match(fixture,/generateRegistrationEvidence\(/);
 assert.doesNotMatch(fixture,/const config=\{format:'schema6-package-switch-registration-v1'/);
 assert.doesNotMatch(fixture,/'-Command'/);
 const runner=readFileSync(new URL('../test_fixtures/release_schema6/run_windows_tests.ps1',import.meta.url),'utf8');
 assert.match(runner,/maintenance.*\.test\.mjs/);
});

test('real R2 generated close input and registration reject invalid evidence before publishing',{
 skip:process.platform!=='win32'||process.env.GITHUB_ACTIONS!=='true',timeout:900000
},async t=>{
 const f=await registrationLab(t);
 assert.equal(f.closeEvidence.defaultApproved,false);assert.equal(f.closeEvidence.unapprovedExitCode,2);
 const close=JSON.parse(readFileSync(f.closeEvidence.closeReceipt));
 assert.equal(close.closed,true);assert.equal(close.coreForced,false);assert.equal(close.originalHostExitConfirmed,true);
 assert.equal(f.validate().validated,true);
 assert.equal(f.dryRunSummary.summary.generated,false);assert.equal(f.dryRunSummary.summary.dryRun,true);
 assert.equal(f.dryRunSummary.summary.registrationValidatorPending,true);
 const cases=[
  ['plan',(o,p)=>{const value=JSON.parse(readFileSync(o.switchPlan));value.approved=false;writeFileSync(p,JSON.stringify(value));return {switchPlan:p};}],
  ['close',(o,p)=>{const value=JSON.parse(readFileSync(o.closeReceipt));value.coreForced=true;writeFileSync(p,JSON.stringify(value));return {closeReceipt:p};}],
  ['prepare',(o,p)=>{const value=JSON.parse(readFileSync(o.prepareReceipt));value.started=true;writeFileSync(p,JSON.stringify(value));return {prepareReceipt:p};}],
  ['marker',(o,p)=>{const value=JSON.parse(readFileSync(o.originalMarkerSnapshot));value.phase='opening';writeFileSync(p,JSON.stringify(value));return {originalMarkerSnapshot:p};}]
 ];
 for(const [name,mutate] of cases){
  const options=f.freshOptions(),root=path.dirname(options.out),bad=path.join(root,'invalid-'+name+'.json');
  Object.assign(options,mutate(options,bad));
  const before=readdirSync(root).sort();
  assert.throws(()=>generateRegistrationEvidence(options),undefined,name);
  assert.deepEqual(readdirSync(root).sort(),before,name+' must leave no published or staged output');
  for(const p of [options.out,options.humanApprovalOut,options.registrationXmlOut,options.receipt])assert.equal(existsSync(p),false,name);
 }
 f.l.completed=true;
});
