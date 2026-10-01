// Contract-only: compiles immutable dependencies and invokes only plan/self-test/rejected parsing.
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, realpathSync, rmSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const local = name => fileURLToPath(new URL(name, import.meta.url));
const source = local('./windows_text_gate_appid_matrix_helper.cs');
const deps = new Map([
  [local('./windows_text_gate_isolation_helper.cs'), 'd22017641d9f8df750f6db7db9319b8c1930a726a8575ff1ffabfde0d5ffdcd8'],
  [local('./windows_text_gate_appid_startup_helper.cs'), 'c777023495ccdbf3b52663f49683f5d84dcfd03a36b3d280a75c925f37b7a1ea'],
  [local('../../tmp/p6-r7-review/native-appid-coordinator-candidate-15.cs'), 'c1f07e9487b8ce25d0acc2d5bbb03b69c975cbb7e448698d288ff6263cff9311'],
]);
const artifacts = local('../../tmp/p6-r7-helper/');
const csc = String.raw`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`;
const root = String.raw`D:\HereIAm-P6-R7-AppId-Matrix`;
const hash = file => createHash('sha256').update(readFileSync(file)).digest('hex');
const verifyDeps = () => { for (const [file, expected] of deps) assert.equal(hash(file), expected); };
test('matrix contract compiles and remains unable to run any native matrix', { skip: process.platform !== 'win32' || !existsSync(csc) }, async t => {
  verifyDeps(); const rootExisted = existsSync(root);
  const unchanged = new Map(['./windows_text_gate_appid_coordinator_helper.cs', './windows_text_gate_appid_coordinator_helper.test.mjs'].map(f => [local(f), hash(local(f))]));
  const tmp = mkdtempSync(path.join(artifacts, 'matrix-contract-test-')), exe = path.join(tmp, 'contract.exe');
  t.after(() => {
    verifyDeps(); for (const [file, before] of unchanged) assert.equal(hash(file), before);
    assert.equal(existsSync(root), rootExisted);
    const canonical = realpathSync(tmp); assert.equal(path.dirname(canonical), realpathSync(artifacts)); assert.match(path.basename(canonical), /^matrix-contract-test-/);
    rmSync(canonical, { recursive: true, force: true });
  });
  const compiled = spawnSync(csc, ['/nologo', '/target:exe', '/platform:x64', '/optimize+', '/warnaserror+', '/reference:System.Web.Extensions.dll', '/main:HereIAm.R7.MatrixProgram', `/out:${exe}`, ...deps.keys(), source], { encoding: 'utf8', windowsHide: true, timeout: 30_000 });
  assert.equal(compiled.status, 0, compiled.stdout); assert.equal(compiled.stderr, '');
  const run = args => {
    assert.ok(args.length === 0 || ['--plan', '--self-test', '--invalid-mode', 'PRIVATE'].includes(args[0]));
    const result = spawnSync(exe, args, { encoding: 'utf8', windowsHide: true, timeout: 10_000 });
    assert.equal(result.signal, null); assert.equal(result.stderr, '');
    assert.doesNotMatch(result.stdout, /PRIVATE|192\.0\.2|2001:db8|S-1-|D:\\/);
    const report = JSON.parse(result.stdout); assert.equal(report.schema, 'p6_r7_appid_matrix_contract_candidate_v1');
    for (const key of ['runtime_implemented', 'system_mutation_requested', 'matrix_passed', 'network_enforcement_tested', 'single_process_enforcement_tested', 'production_isolation_passed', 'human_gate_passed']) assert.equal(report[key], false);
    assert.equal(report.real_upstream_requests, 0); assert.equal(report.model_turns_requested, 0); return { report, status: result.status };
  };
  await t.test('default and plan contain eight fixed local-only roles, never actual evidence', () => {
    const a = run([]), b = run(['--plan']); assert.equal(a.status, 0); assert.deepEqual(a, b); assert.equal(a.report.runtime_status, 'not_implemented');
    assert.deepEqual(a.report.negative_roles, ['loopback4_tcp','loopback4_udp','loopback6_tcp','loopback6_udp','local4_tcp','local4_udp','local6_tcp','local6_udp']);
  });
  await t.test('302 pure endpoint, scope, ownership, receipt, denial and closure cases pass', () => {
    const result = run(['--self-test']); assert.equal(result.status, 0); assert.equal(result.report.assertions_passed, 302); assert.equal(result.report.native_layouts_passed, true);
  });
  for (const args of [['PRIVATE'], ['--invalid-mode'], ['--plan', 'PRIVATE'], ['--self-test', 'PRIVATE']]) await t.test(`unsupported arguments rejected without runtime dispatch: ${args[0]}`, () => {
    const result = run(args); assert.equal(result.status, 2); assert.equal(result.report.error_code, 'matrix_candidate_rejected');
  });
  const code = readFileSync(source, 'utf8');
  await t.test('Main has no actual verbs and source has no native or socket side effects', () => {
    const main = code.slice(code.indexOf('[STAThread] public static int Main'));
    assert.doesNotMatch(main, /--apply|--install|--cleanup|--probe|--recover|CoordinatorProgram\.Main|AppIdProgram\.Main/);
    assert.doesNotMatch(code, /DllImport|new Socket|new Tcp|new Udp|NetworkInterface\.|Dns\.|Process\.Start|CreateProcess|CreateJob|Fwpm|\.Install\(|RemoveAfterZero|NetworkIsolation|Directory\.Create|File\.Write|MediumIdentity\.OfProcess/);
    assert.match(code, /InspectionNative.Layouts\(\);CoordinatorJobNative.Layouts\(\)/);
  });
  await t.test('scope is derived before using frozen correct rule planning, with separate journal and root', () => {
    assert.match(code, /HereIAm\.P6R7\.AppIdMatrixV1\//);
    assert.match(code, /CoordinatorBoundary.MakeRules\(Scope\(attempt\),brokerPort\)/);
    assert.match(code, /p6_r7_appid_matrix_owned_v1/); assert.match(code, /p6_r7_appid_matrix_receipt_v1/);
    assert.match(code, /D:\\HereIAm-P6-R7-AppId-Matrix/);
    assert.doesNotMatch(code, /Native\.Filter\b|AppIdBoundary\b|NetworkBoundary\b/);
  });
  await t.test('denial requires positive fixture, synchronous 10013 and drained zero receives', () => {
    assert.match(code, /!row.FixtureAvailable\|\|!row.LocalAddressVerified\|\|!row.HostPositive\|\|!row.HostDrainComplete/);
    assert.match(code, /!row.Attempted\|\|!row.ObservationComplete\|\|!row.ListenerDrainComplete/);
    assert.match(code, /row.AcceptedConnections!=0\|\|row.ReceivedDatagrams!=0\|\|row.ReceivedBytes!=0/);
    assert.match(code, /row.Observation==MatrixObservation.AccessDenied&&row.SocketError==10013\?"blocked":"incomplete"/);
    assert.match(code, /inventory.Length>64/); assert.match(code, /SameAddress\(target,local\)/);
  });
  await t.test('records bind every field canonically and do not treat missing weight or helper exit as closure', () => {
    assert.match(code, /text.Length<=16384/); assert.match(code, /Json\(value\)==text/);
    assert.match(code, /action=="install_rollback"\|\|assignedWeight.HasValue/);
    assert.match(code, /value.SameHeldChildSignaled&&value.ExactChildBinding&&value.JobQuerySucceeded&&value.JobActive==0/);
    assert.match(code, /Phase=="prepared"&&OwnerLive&&JobHeld&&JobQuerySucceeded&&Active==0&&Total==0&&OriginalHelperClosed/);
    assert.match(code, /PostAbsence&&RollbackReceiptBound/);
  });
});
