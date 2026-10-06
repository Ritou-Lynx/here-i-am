import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {cleanEnvironment} from '../../release_schema6/package.mjs';
import {runStage,parseMetrics,productionGate,cleanProbeEnvironment} from './ci_native_probe.mjs';
const here=path.dirname(fileURLToPath(import.meta.url));
const cli=path.join(here,'ci_native_probe.mjs');
const marker='synthetic_private_marker_do_not_emit';
test('probe rejects an inherited extra environment field before preparing any root',()=>{
 const env={...cleanEnvironment(),SYNTHETIC_PRIVATE_MARKER:marker};
 assert.equal(cleanProbeEnvironment(env),false);
 const result=spawnSync(process.execPath,[cli],{env,encoding:'utf8',windowsHide:true});
 assert.equal(result.status,1);const report=JSON.parse(result.stdout);
 assert.deepEqual(report,{format:'schema6-ci-native-probe-v1',passed:false,stages:[]});
 assert.equal(result.stdout.includes(marker),false);
});
test('probe rejects command-line inputs instead of accepting caller-selected paths',()=>{
 const result=spawnSync(process.execPath,[cli,marker],{env:cleanEnvironment(),encoding:'utf8',windowsHide:true});
 assert.equal(result.status,1);assert.deepEqual(JSON.parse(result.stdout).stages,[]);
 assert.equal(result.stdout.includes(marker),false);
});
test('native diagnostics use fresh bounded processes and the exact clean environment',()=>{
 const env=cleanEnvironment();let calls=0;
 const result=runStage('default_acl','fixed-body','fixed-powershell',env,(exe,args,options)=>{
  calls++;assert.equal(exe,'fixed-powershell');assert.deepEqual(args.slice(0,3),['-NoProfile','-NonInteractive','-Command']);
  assert.equal(options.env,env);assert.equal(options.timeout,60000);assert.deepEqual(options.stdio,['ignore','pipe','pipe']);
  return {status:0,stdout:'{"module_directory_count":5,"module_path_count":2,"script_elapsed_ms":11}',stderr:marker};
 });
 assert.equal(calls,1);assert.equal(result.error_code,'none');assert.equal(result.metrics.script_elapsed_ms,11);
 assert.equal(JSON.stringify(result).includes(marker),false);
});
test('native timeout retains only a finite code and never serializes exception output or arguments',()=>{
 const error=Object.assign(new Error(marker),{code:'ETIMEDOUT',spawnargs:[marker]});
 const result=runStage('default_assert','fixed-body','fixed-powershell',{},()=>({status:null,error,stdout:marker,stderr:marker}));
 assert.equal(result.timed_out,true);assert.equal(result.error_code,'timeout');
 assert.equal(JSON.stringify(result).includes(marker),false);
});
test('metric shape, extra fields, nonintegers and negative counts fail closed',()=>{
 for(const text of ['{}','{"module_directory_count":1,"module_path_count":2,"script_elapsed_ms":1,"private":"'+marker+'"}',
 '{"module_directory_count":-1,"module_path_count":2,"script_elapsed_ms":1}','{"module_directory_count":1,"module_path_count":2,"script_elapsed_ms":0.5}']){
  assert.throws(()=>parseMetrics(text));
  const result=runStage('no_op','fixed-body','fixed-powershell',{},()=>({status:0,stdout:text}));
  assert.equal(result.error_code,'operation_failed');assert.equal(JSON.stringify(result).includes(marker),false);
 }
});
test('production gate invokes its supplied implementation exactly once with the Root boundary',async()=>{
 let calls=0;
 const success=await productionGate('synthetic-root',(root,isRoot)=>{calls++;assert.equal(root,'synthetic-root');assert.equal(isRoot,true);});
 assert.equal(calls,1);assert.equal(success.error_code,'none');
});
test('production gate timeout fails without retry or raw diagnostics',async()=>{
 let calls=0;
 const result=await productionGate('synthetic-root',()=>{calls++;throw Object.assign(new Error(marker),{code:'ETIMEDOUT',stderr:marker});});
 assert.equal(calls,1);assert.equal(result.error_code,'timeout');assert.equal(JSON.stringify(result).includes(marker),false);
});
test('actual PowerShell gate never invokes suites on preflight failure; success preserves suite exit status',{skip:process.platform!=='win32'},()=>{
 const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
 const runner=path.join(here,'run_windows_tests.ps1').replaceAll("'","''");
 const script="$ErrorActionPreference='Stop'; $tokens=$null;$errors=$null; "+
  "$ast=[Management.Automation.Language.Parser]::ParseFile('"+runner+"',[ref]$tokens,[ref]$errors); if($errors.Count){throw 'parser_failed'}; "+
  "$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-Schema6GatedSuites'},$true); "+
  ". ([scriptblock]::Create($fn.Extent.Text)); $seen=@{probe=0;suite=0}; "+
  "$failed=Invoke-Schema6GatedSuites -Probe {$seen.probe++;return 7} -Suites {$seen.suite++;return 0}; "+
  "if($failed -ne 7 -or $seen.probe -ne 1 -or $seen.suite -ne 0){throw 'failed_gate_started_suite'}; "+
  "$passed=Invoke-Schema6GatedSuites -Probe {$seen.probe++;return 0} -Suites {$seen.suite++;return 14}; "+
  "if($passed -ne 14 -or $seen.probe -ne 2 -or $seen.suite -ne 1){throw 'suite_exit_changed'}; "+
  "try{Invoke-Schema6GatedSuites -Probe {throw 'synthetic_probe_rejected'} -Suites {$seen.suite++;return 0};throw 'missing_failure'}catch{if($_.Exception.Message -ne 'synthetic_probe_rejected'){throw}}; "+
  "if($seen.suite -ne 1){throw 'exception_started_suite'}; [Console]::Out.Write('gate_passed')";
 const result=spawnSync(ps,['-NoProfile','-NonInteractive','-Command',script],{encoding:'utf8',windowsHide:true,timeout:30000});
 assert.equal(result.status,0);assert.equal(result.stdout,'gate_passed');
});
