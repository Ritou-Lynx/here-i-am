import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {taskSecurityBindings} from '../maintenance/prepare-production-login.mjs';
const repository=fileURLToPath(new URL('../../../',import.meta.url));
test('actual PS5 pipeline disclosure expression survives JSON with zero, one and two external principals',{skip:process.platform!=='win32',timeout:30000},()=>{
 const raw=execFileSync(path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe'),['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(repository,'tools/i_core/test_fixtures/release_schema6/identity_disclosure_roundtrip.ps1'),'-Repository',repository],{encoding:'utf8',windowsHide:true,timeout:25000});
 const r=JSON.parse(raw);assert.equal(r.passed,true);assert.match(r.psVersion,/^5\.1\./);
 const disclosures=[[],[{sid:'S-1-5-32-545',flags:16,mask:'00120089'}],[{sid:'S-1-5-11',flags:16,mask:'00120089'},{sid:'S-1-5-32-545',flags:16,mask:'00120089'}]];
 assert.equal(r.cases.length,disclosures.length);
 r.cases.forEach((row,i)=>{
  assert.deepEqual(row.config.inheritedReadOnlyPrincipals,disclosures[i]);
  assert.deepEqual(taskSecurityBindings(row.config).inheritedReadOnlyPrincipals,disclosures[i]);
  assert.deepEqual(row.oldWrapped,[disclosures[i]]);
  assert.throws(()=>taskSecurityBindings({...row.config,inheritedReadOnlyPrincipals:row.oldWrapped}));
 });
});
