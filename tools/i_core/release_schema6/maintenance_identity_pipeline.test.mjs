import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const fixture = name => readFileSync(new URL(`../test_fixtures/release_schema6/${name}`,import.meta.url),'utf8');
test('identity integration is required on hosted Windows and never inherits owner workaround',()=>{
 const ci=readFileSync(new URL('../../../.github/workflows/ci.yml',import.meta.url),'utf8');
 const job=ci.split('  schema6-identity-pipeline:')[1]?.split('  schema6-cross-user:')[0];
 assert.ok(job);assert.match(job,/runs-on: windows-latest/);assert.match(job,/run_identity_pipeline\.ps1/);
 assert.doesNotMatch(job,/SCHEMA6_SYNTHETIC|continue-on-error|if:.*env/);
 const runner=fixture('run_identity_pipeline.ps1');assert.doesNotMatch(runner,/Schema6SyntheticTokenOwner|run_windows_tests/);
});
test('identity fixture uses real Apply and Prepare, checks both actual tokens and separates safe registration',()=>{
 const pipeline=fixture('identity_pipeline.ps1'),consumer=fixture('identity_consumer.ps1'),native=fixture('identity_token.cs');
 assert.match(pipeline,/Invoke-AclMaintenance .* -Mode Apply -ConfirmFrozen/);
 assert.match(pipeline,/writer\.owner-cne 'S-1-5-32-544'/);
 assert.match(pipeline,/writer\.elevated/);assert.match(pipeline,/writer\.administrator/);
 assert.match(consumer,/identity\.elevated/);assert.match(consumer,/identity\.administrator/);assert.match(consumer,/identity\.sid-cne \$plan\.ownerSid/);
 assert.match(consumer,/S-1-16-8192/);assert.match(consumer,/prepare-production-login\.ps1/);
 assert.match(native,/CreateRestrictedToken\(token,5,1/);assert.match(native,/CreateProcessAsUserW/);
 assert.match(pipeline,/productionRegisterOuterExecuted=\$false/);
 assert.doesNotMatch(pipeline+consumer, /\.Run(?:Ex)?\(|Start-ScheduledTask|RunAs|Start-Process/);
 const oracle=fixture('identity_task_oracle.ps1');assert.match(oracle,/cleanup_binding_rejected/);assert.match(oracle,/DeleteTask\(\$Name,0\);Assert-TaskAbsent/);
 assert.match(oracle,/safe_derivation_extra_change/);
});
test('ordinary child gets a fresh private Medium desktop without changing an existing desktop ACL',()=>{
 const native=fixture('identity_token.cs'),pipeline=fixture('identity_pipeline.ps1');
 assert.match(native,/CreateWindowStationW\(evidence.windowStation,1,/);
 assert.match(native,/desktop=privateDesktop==null\?null:privateDesktop.Path/);
 assert.match(native,/S:\(ML;;NW;;;ME\)/);
 assert.match(native,/CheckPrivateObject\(station/);assert.match(native,/CheckPrivateObject\(desktop/);
 assert.match(native,/SetProcessWindowStation\(original\)/);
 assert.match(native,/CloseDesktop\(desktop\)/);assert.match(native,/CloseWindowStation\(station\)/);
 assert.doesNotMatch(native,/extern bool SwitchDesktop|SetUserObjectSecurity/);
 assert.match(native,/SetThreadDesktop\(originalThreadDesktop\)/);
 assert.match(pipeline,/limited_consumer_result_missing_exit_/);
 assert.match(pipeline,/consumerExit=\$consumerExit/);
});
test('startup matrix preserves actual identity, bounds diagnostics and never selects the fixed candidate',()=>{
 const native=fixture('identity_token.cs'),diagnostic=fixture('identity_startup_diagnostics.ps1');
 assert.match(native,/RunCore\(application,arguments,cwd,true,true,true,false,0xffffffff\)/);
 assert.match(native,/privateTokenObjectDacl,15000\)/);
 assert.match(native,/0x08000004/); // CREATE_NO_WINDOW | CREATE_SUSPENDED
 assert.match(native,/actual\.sid!=Sid\(token,1\).*actual\.owner!=actual\.sid.*actual\.elevated.*actual\.administrator/);
 assert.ok(native.indexOf('actual_child_token_rejected')<native.indexOf('if(ResumeThread'));
 assert.match(native,/TerminateProcess\(pi.process,2\)/);
 assert.match(native,/SetKernelObjectSecurity\(limited,0x80000004,descriptor\)/);
 assert.doesNotMatch(native,/SetKernelObjectSecurity\(token,/);
 for(const key of ['parentTokenDefaultDacl','inheritedTokenDefaultDacl','limitedTokenSecurity','childTokenSecurity','processSecurity','threadSecurity','restrictedSids','terminatedBeforeResume'])assert.ok(native.includes(key),key);
 assert.match(native,/new_kernel_dacl_unprotected/);assert.match(native,/AssertMediumKernelLabel/);
 assert.match(diagnostic,/pipelinePassed=\$false/);assert.match(diagnostic,/cases.Count-eq 18/);
 assert.doesNotMatch(diagnostic,/RunLimited|Invoke-AclMaintenance|prepare-production-login|Set-Acl/);
});
