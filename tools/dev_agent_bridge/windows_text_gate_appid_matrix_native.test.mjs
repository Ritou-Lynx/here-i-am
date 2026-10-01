// Compiles frozen dependencies; invokes only plan/self-test and public pure policy, never actual adapters.
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, realpathSync, rmSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const local=name=>fileURLToPath(new URL(name,import.meta.url));
const source=local('./windows_text_gate_appid_matrix_native.cs');
const deps=new Map([
  [local('./windows_text_gate_isolation_helper.cs'),'d22017641d9f8df750f6db7db9319b8c1930a726a8575ff1ffabfde0d5ffdcd8'],
  [local('./windows_text_gate_appid_startup_helper.cs'),'c777023495ccdbf3b52663f49683f5d84dcfd03a36b3d280a75c925f37b7a1ea'],
  [local('../../tmp/p6-r7-review/native-appid-coordinator-candidate-15.cs'),'c1f07e9487b8ce25d0acc2d5bbb03b69c975cbb7e448698d288ff6263cff9311'],
  [local('../../tmp/p6-r7-review/native-appid-matrix-contract-01.cs'),'f70ffb86ce5efea2572532e1986f77dde9622893ad4b90a74f9ec40da5ba6774'],
]);
const csc=String.raw`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`;
const artifacts=local('../../tmp/p6-r7-helper/');
const matrixRoot=String.raw`D:\HereIAm-P6-R7-AppId-Matrix`;
const hash=file=>createHash('sha256').update(readFileSync(file)).digest('hex');
const verifyDeps=()=>{for(const [file,expected] of deps)assert.equal(hash(file),expected,file);};
const code=readFileSync(source,'utf8');
const literal=value=>`'${value.replaceAll("'","''")}'`;

test('matrix native adapters compile while actual execution remains unavailable',async t=>{
  assert.equal(process.platform,'win32');assert.ok(existsSync(csc));verifyDeps();
  const rootBefore=existsSync(matrixRoot),tmp=mkdtempSync(path.join(artifacts,'matrix-native-test-')),exe=path.join(tmp,'adapters.exe');
  t.after(()=>{verifyDeps();assert.equal(existsSync(matrixRoot),rootBefore);const canonical=realpathSync(tmp);assert.equal(path.dirname(canonical),realpathSync(artifacts));assert.match(path.basename(canonical),/^matrix-native-test-/);rmSync(canonical,{recursive:true,force:true});});
  const compile=spawnSync(csc,['/nologo','/target:exe','/platform:x64','/warnaserror+','/reference:System.Web.Extensions.dll','/main:HereIAm.R7.MatrixNativeProgram',`/out:${exe}`,...deps.keys(),source],{encoding:'utf8',windowsHide:true,timeout:30_000});
  assert.equal(compile.status,0,compile.stdout);assert.equal(compile.stderr,'');
  const run=args=>{
    assert.ok(args.length===0||['--plan','--self-test','--invalid-mode'].includes(args[0]));
    const result=spawnSync(exe,args,{encoding:'utf8',windowsHide:true,timeout:10_000});assert.equal(result.signal,null);assert.equal(result.stderr,'');
    const report=JSON.parse(result.stdout);assert.equal(report.schema,'p6_r7_appid_matrix_native_adapters_v1');assert.equal(report.runtime_status,'adapters_only_not_wired');
    for(const field of ['runtime_implemented','native_executed','system_mutation_requested','matrix_passed','network_enforcement_tested','single_process_enforcement_tested','production_isolation_passed','human_gate_passed'])assert.equal(report[field],false,field);
    assert.equal(report.real_upstream_requests,0);assert.equal(report.model_turns_requested,0);assert.doesNotMatch(result.stdout,/PRIVATE|S-1-|[CD]:\\/);return {status:result.status,report};
  };
  await t.test('default/plan stay read-only; invalid arguments return real exit 2',()=>{
    const a=run([]),b=run(['--plan']);assert.equal(a.status,0);assert.deepEqual(a,b);assert.equal(a.report.native_adapters_implemented,true);
    assert.equal(run(['--invalid-mode']).status,2);assert.equal(run(['--plan','PRIVATE']).status,2);
  });
  await t.test('managed selftest exercises ABI, 128 transition checks, missing facts and mocked close failures',()=>{
    const result=run(['--self-test']);assert.equal(result.status,0);assert.equal(result.report.assertions_passed,166);
  });
  const script=`
$ErrorActionPreference='Stop'
[Reflection.Assembly]::LoadFrom(${literal(exe)})|Out-Null
$grid=@()
foreach($from in 0..7){foreach($to in 0..7){$facts=[HereIAm.R7.MatrixNativeProgram]::PassingFacts();$grid+=@{from=$from;to=$to;accepted=[HereIAm.R7.MatrixNativePolicy]::Advance($from,$to,$facts)}}}
$missing=@()
foreach($property in [HereIAm.R7.MatrixNativeFacts].GetProperties()){$facts=[HereIAm.R7.MatrixNativeProgram]::PassingFacts();if($property.PropertyType -eq [bool]){$property.SetValue($facts,$false,$null)}else{$property.SetValue($facts,[uint32]1,$null)};$missing+=@{field=$property.Name;complete=[HereIAm.R7.MatrixNativePolicy]::Complete($facts)}}
@{grid=$grid;missing=$missing;flags=[HereIAm.R7.MatrixNativePolicy]::ProbeFlags;complete=[HereIAm.R7.MatrixNativePolicy]::Complete([HereIAm.R7.MatrixNativeProgram]::PassingFacts());null_complete=[HereIAm.R7.MatrixNativePolicy]::Complete($null)}|ConvertTo-Json -Depth 5 -Compress
`;
  const pure=spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',script],{encoding:'utf8',windowsHide:true,timeout:15_000});assert.equal(pure.status,0,pure.stderr);const facts=JSON.parse(pure.stdout);
  await t.test('64 independent phase pairs permit only intended edges and cleanup after an observed failure',()=>{
    assert.equal(facts.grid.length,64);
    const edges=new Set(['0:1','1:2','2:3','3:4','3:5','4:5','5:6','6:7']);
    for(const row of facts.grid)assert.equal(row.accepted,edges.has(`${row.from}:${row.to}`),JSON.stringify(row));
    assert.equal(facts.complete,true);assert.equal(facts.null_complete,false);
  });
  await t.test('each missing real evidence field prevents complete; detached flags exclude other console modes',()=>{
    assert.equal(facts.missing.length,18);for(const row of facts.missing)assert.equal(row.complete,false,row.field);
    assert.equal(facts.flags,0x8040c);assert.equal(facts.flags&(0x08000000|0x10),0);
  });
  await t.test('Main cannot dispatch adapters, probe, UAC, sockets or old CLI entry points',()=>{
    const main=code.slice(code.indexOf('[STAThread] public static int Main'));
    assert.doesNotMatch(main,/--apply|--install|--cleanup|--matrix-probe|new Matrix|Native\.|CoordinatorProgram|AppIdProgram|Socket|CreateProcess|ShellExecute/);
    assert.ok(main.includes('--plan'));assert.ok(main.includes('--self-test'));
    assert.doesNotMatch(code,/CoordinatorProgram\.Main|AppIdProgram\.Main|MatrixProgram\.Main|CliStartupContract|AppIdProgram\.VerifyImage|LinkedMediumToken|CreateProcessAsUser|DuplicateToken|NetworkInterface|Dns\.|new Socket|new Tcp|Directory\.Create|File\.Write/);
  });
  await t.test('correct frozen WFP boundary is scope-derived and constructor validation disposes on failure',()=>{
    assert.ok(code.includes('new CoordinatorBoundary(MatrixContract.Scope(value.Attempt),value.BrokerPort,MatrixContract.ImageFor(value.Attempt))'));
    assert.ok(code.includes('boundary.Install()'));assert.ok(code.includes('boundary.RemoveAfterZero('));assert.ok(code.includes('boundary.AssignedWeight=actualInstalledWeight'));
    assert.ok(code.includes('catch{try{boundary.Dispose();}catch{}throw;}'));
    assert.doesNotMatch(code,/Native\.Filter\b|AppIdBoundary\b|NetworkBoundary\b|FwpmFilterAdd0|assigned.*0x7fff/i);
  });
  await t.test('process handle capture, exact three handles, identity and stopped-query ordering remain explicit',()=>{
    const creation=code.slice(code.indexOf('internal void CreateSuspended('),code.indexOf('internal void VerifyLiveBinding('));
    assert.ok(creation.indexOf('out createdInfo')<creation.indexOf('Binding.Handle=createdInfo.Process'));
    assert.ok(creation.indexOf('Binding.Handle=createdInfo.Process')<creation.indexOf('Binding.Created=TokenProof.Creation'));
    assert.ok(creation.includes('new IntPtr(0x2000d)'));assert.ok(creation.includes('new IntPtr(0x20002)'));assert.ok(creation.includes('new IntPtr(24)'));assert.ok(creation.includes('childHandles.Length==3'));
    assert.ok(creation.includes('if(initialized)Native.DeleteProcThreadAttributeList(list)'));
    const stop=code.slice(code.indexOf('internal bool StopAndObserve('),code.indexOf('internal bool CloseAfterVerifiedRulesRemoval('));
    assert.doesNotMatch(stop,/TokenProof\.Image/);assert.ok(stop.includes('LastAccounting=null'));assert.ok(stop.includes('Binding.Created>0&&signaled'));
    assert.ok(code.includes('return AppIdLauncher.Peer(accepted,Binding,pin.Owner,pin.Image)'));
  });
  await t.test('read-only pins and checked close ledger do not manufacture ACL, EOF or final closure proof',()=>{
    assert.ok(code.includes('MatrixNativeApi.VerifyPath(ImageHandle,Image,false)'));assert.ok(code.includes('MatrixNativeApi.HashHandle(ImageHandle)==Expected.ImageHash'));
    assert.ok(code.includes('if(!success)AnyCloseFailure=true;return success;'));
    assert.ok(code.includes('if(success)handles.Remove(handle);else AllCloseCallsSucceeded=false'));
    assert.ok(code.includes('if(AttemptClose(handles[i]))handles.RemoveAt(i);else AllCloseCallsSucceeded=false'));
    assert.ok(code.includes('internal bool CloseVerified(){disposed=true;return files.CloseAll();}'));
    assert.ok(code.includes('if(disposed){HandlesClosed=handles.CloseAll();return;}'));
    assert.ok(code.includes('removed&&ExitIdentityProven&&JobZeroProven'));
    const adapters=code.slice(0,code.indexOf('public static class MatrixNativeProgram'));
    assert.doesNotMatch(adapters,/StdioEof\s*=\s*(?:handles|pipes)|NativeHandlesClosed\s*=\s*true/);
  });
});
