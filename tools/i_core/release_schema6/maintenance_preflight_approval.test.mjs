import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtempSync, rmSync, realpathSync, readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const repository=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..');
test('online approval: synthetic ACL144 exact inventory, strict source template, memory-only COM and exact XML',{skip:process.platform!=='win32',timeout:120000},()=>{
 const root=realpathSync.native(mkdtempSync(path.join(realpathSync.native(tmpdir()),'schema6-preflight-approval-synthetic-')));
 try {
  const output=execFileSync(path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe'),['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(repository,'tools/i_core/test_fixtures/release_schema6/maintenance_preflight_approval.ps1'),'-Repository',repository,'-FixtureRoot',root],{windowsHide:true,encoding:'utf8',timeout:110000});
  assert.ok(output.trim(),'ordinary fixture must emit its JSON through the captured success stream');
  const r=JSON.parse(output);assert.equal(r.passed,true);assert.equal(r.aclCount,144);assert.ok(r.checks>=14);assert.equal(r.comMemoryRoundtrip,true);
  for(const k of ['productionPrepareInvoked','registered','started']) assert.equal(r[k],false,k);
 } finally {assert.ok(path.basename(root).startsWith('schema6-preflight-approval-synthetic-'));rmSync(root,{recursive:true,force:true});}
});
test('preflight helpers contain no production mutation entry or deployed identity',()=>{
 const s=readFileSync(path.join(repository,'tools/i_core/maintenance/preflight_approval_checks.ps1'),'utf8');
 assert.doesNotMatch(s,/\.RegisterTask\(|Register-ScheduledTask|Set-Acl|SetOwnerDacl|Invoke-AclMaintenance\s+-|S-1-5-21-|HereIAmRuntime/);
 assert.match(s,/productionPrepareInvoked=\$false/);
 assert.match(s,/productionPrepareStillRequiresAclApply=\$true/);
});
