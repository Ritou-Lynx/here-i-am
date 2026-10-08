import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync,mkdtempSync,rmSync,realpathSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {INVENTORY,cleanEnvironment} from './package.mjs';
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


test('identity inventory gate executes against the authoritative package paths', {skip:process.platform!=='win32'},t=>{
 const seed=fixture('identity_assemble.mjs');
 assert.match(seed,/import \{ INVENTORY, prepareRelease \}/);
 assert.match(seed,/assert\.equal\(report\.files, INVENTORY\.length\)/);
 assert.match(seed,/inventory:\[\.\.\.INVENTORY\]/);
 const root=realpathSync.native(mkdtempSync(path.join(tmpdir(),'schema6-identity-inventory-')));
 t.after(()=>{assert.match(path.basename(root),/^schema6-identity-inventory-/);rmSync(root,{recursive:true,force:true});});
 const scenarios=[
  ['exact',true,n=>n],
  ['missing',false,n=>n.slice(1)],
  ['same-count-wrong-path',false,n=>['tools/i_core/not-in-inventory.mjs',...n.slice(1)]],
  ['duplicate',false,n=>[n[1],...n.slice(1)]],
  ['wrong-report-count',false,n=>n],
  ['duplicate-source-inventory',false,n=>n],
 ];
 const cases=scenarios.map(([name,accepted,mutate])=>{
  const release=path.join(root,name);mkdirSync(release);
  writeFileSync(path.join(release,'manifest.json'),JSON.stringify({files:mutate([...INVENTORY]).map(path=>({path}))}));
  const inventory=[...INVENTORY];if(name==='duplicate-source-inventory')inventory[0]=inventory[1];
  return {name,accepted,assembly:{root:path.join(root,'schema6-identity-Synthetic123'),release,inventory,files:INVENTORY.length-(name==='wrong-report-count'?1:0)}};
 });
 const inputs=path.join(root,'cases.json');writeFileSync(inputs,JSON.stringify(cases));
 const quote=s=>"'"+s.replaceAll("'","''")+"'";
 const pipeline=new URL('../test_fixtures/release_schema6/identity_pipeline.ps1',import.meta.url);
 const script=`$ErrorActionPreference='Stop';$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile(${quote(fileURLToPath(pipeline))},[ref]$tokens,[ref]$errors);if($errors.Count){throw 'fixture_parse_failed'};$f=$ast.Find({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -ceq 'Assert-IdentityInventory'},$true);if(!$f){throw 'inventory_function_missing'};. ([scriptblock]::Create($f.Extent.Text));$result=@(foreach($case in (Get-Content -LiteralPath ${quote(inputs)} -Raw|ConvertFrom-Json)){$accepted=$true;try{Assert-IdentityInventory $case.assembly}catch{if($_.Exception.Message-cne 'synthetic_root_or_inventory_rejected'){throw};$accepted=$false};@{name=$case.name;accepted=$accepted}});ConvertTo-Json -InputObject $result -Compress`;
 const ps=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');
 const result=spawnSync(ps,['-NoProfile','-NonInteractive','-EncodedCommand',Buffer.from(script,'utf16le').toString('base64')],{env:cleanEnvironment(),windowsHide:true,encoding:'utf8',timeout:30000});
 assert.equal(result.status,0,result.stdout+result.stderr);
 assert.deepEqual(JSON.parse(result.stdout),cases.map(({name,accepted})=>({name,accepted})));
});
