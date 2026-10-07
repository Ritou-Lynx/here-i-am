import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..');
test('pure in-memory task security policy rejects excess rights and binds independent inheritance', {skip:process.platform!=='win32'},()=>{
 const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
 const output=execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(root,'tools/i_core/test_fixtures/release_schema6/maintenance_task_security.ps1'),'-PolicyPath',path.join(root,'tools/i_core/maintenance/task_security_policy.ps1'),'-PrimitivesPath',path.join(root,'tools/i_core/maintenance/register_task_primitives.ps1')],{windowsHide:true,encoding:'utf8',timeout:30000});
 const report=JSON.parse(output);assert.equal(report.passed,true);assert.ok(report.checks>=50);
 for(const key of ['comConnected','registered','started'])assert.equal(report[key],false);
 assert.equal(report.syntheticOnly,true);
});
test('registration binds input separately from expected readback and pins policy helper',()=>{
 const source=readFileSync(path.join(root,'tools/i_core/maintenance/register-approved-login.ps1'),'utf8');
 const policy=readFileSync(path.join(root,'tools/i_core/maintenance/task_security_policy.ps1'),'utf8');
 assert.match(source,/New-ApprovedTask .*\$config\.registrationSddl/);
 assert.match(source,/Assert-RegisteredTask .*\$config\.expectedRegisteredSddl/);
 assert.match(source,/Assert-TaskAllowedRights \(\$actual.GetSecurityDescriptor\(7\)\)/);
 assert.match(source,/!\$expected\.Settings\.UseUnifiedSchedulingEngine/);
 const create=source.indexOf('$registered=New-ApprovedTask');
 const gates=[...source.matchAll(/Assert-TaskSecurityPolicy \$config \(\$folder.GetSecurityDescriptor\(7\)\)/g)].map(m=>m.index);
 assert.equal(gates.length,3);assert.ok(gates[0]<create && gates[1]>create && gates[2]>gates[1]);
 assert.match(source,/foreach\(\$required in @\([^\n]*'task_security_policy\.ps1'/);
 assert.doesNotMatch(policy,/-ComObject|\.RegisterTask\(|\.GetSecurityDescriptor\(|\.Run(?:Ex)?\(/);
 assert.match(source,/\$report\.Remove\('inheritedReadOnlyPrincipals'\)/);
});
