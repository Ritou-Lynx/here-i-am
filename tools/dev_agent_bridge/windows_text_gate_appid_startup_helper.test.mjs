// Compiles the candidate with frozen v10 primitives; never runs apply, recovery, CLI, or network.
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const source = fileURLToPath(new URL('./windows_text_gate_appid_startup_helper.cs', import.meta.url));
const core = fileURLToPath(new URL('./windows_text_gate_isolation_helper.cs', import.meta.url));
const coreTest = fileURLToPath(new URL('./windows_text_gate_isolation_helper.test.mjs', import.meta.url));
const artifacts = fileURLToPath(new URL('../../tmp/p6-r7-helper/', import.meta.url));
const isolationRoot = String.raw`D:\memex\tmp\p6-r7-appid-isolation`;
const csc = String.raw`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`;
const supported = process.platform === 'win32' && existsSync(csc);
const sha = file => createHash('sha256').update(readFileSync(file)).digest('hex');
const coreHash = 'd22017641d9f8df750f6db7db9319b8c1930a726a8575ff1ffabfde0d5ffdcd8';
const coreTestHash = '3b30a568278284378bb75fb7024f3ed175fe289583b32aaa76c4e4fdde261d0f';
const rootState = () => existsSync(isolationRoot) ? readdirSync(isolationRoot).sort() : null;

test('AppId candidate compiles and all exercised entrypoints remain read-only', { skip: !supported }, async t => {
  assert.equal(sha(core), coreHash); assert.equal(sha(coreTest), coreTestHash);
  const initialRoot = rootState();
  const root = mkdtempSync(path.join(artifacts, 'appid-test-'));
  const exe = path.join(root, 'candidate.exe');
  t.after(() => {
    assert.equal(sha(core), coreHash); assert.equal(sha(coreTest), coreTestHash);
    assert.deepEqual(rootState(), initialRoot);
    const canonical = realpathSync(root);
    assert.equal(path.dirname(canonical), realpathSync(artifacts));
    assert.match(path.basename(canonical), /^appid-test-/);
    rmSync(canonical, { recursive: true, force: true });
  });
  const compilation = spawnSync(csc, ['/nologo', '/target:exe', '/platform:x64', '/optimize+',
    '/reference:System.Web.Extensions.dll', '/main:HereIAm.R7.AppIdProgram', `/out:${exe}`, core, source],
  { encoding: 'utf8', windowsHide: true, timeout: 30_000 });
  assert.equal(compilation.status, 0, 'Framework joint compilation failed');
  assert.equal(compilation.stderr, '');

  function run(args) {
    // Any apply/recovery verb is forbidden even with invalid arguments: no test can drift into execution.
    assert.ok(!args.some(a => /^--(?:apply|recover(?!y-plan)|synthetic-worker|synthetic-leaf)/.test(a)));
    const result = spawnSync(exe, args, { encoding: 'utf8', windowsHide: true, timeout: 10_000 });
    assert.equal(result.signal, null); assert.equal(result.stderr, '');
    assert.ok(!result.stdout.includes('PRIVATE'));
    const report = JSON.parse(result.stdout);
    assert.equal(report.schema, 'p6_r7_cli_appid_startup_candidate_v1');
    for (const key of ['system_mutation_requested', 'appid_startup_passed', 'appcontainer_isolation_passed',
      'production_isolation_passed', 'human_gate_passed', 'network_enforcement_tested']) assert.equal(report[key], false);
    for (const key of ['real_upstream_requests', 'model_turns_requested', 'profile_operations', 'loopback_config_operations']) assert.equal(report[key], 0);
    return { status: result.status, report };
  }

  await t.test('default and explicit plan agree without token, WFP, or process operations', () => {
    const a = run([]), b = run(['--plan']);
    assert.equal(a.status, 0); assert.deepEqual(a, b);
    assert.equal(a.report.network_identity, 'copied_image_path_appid');
    assert.equal(a.report.path_appid_is_instance_or_hash_identity, false);
    assert.equal(a.report.requires_verified_linked_medium_token, true);
    assert.equal(a.report.elevated_fallback_allowed, false);
    assert.equal(a.report.job_active_process_limit, 1);
    assert.equal(a.report.atomic_job_list, true);
    assert.equal(a.report.inherited_handle_count, 3);
    assert.equal(a.report.wfp_filter_count, 3);
    assert.equal(a.report.journal_schema, 'p6_r7_owned_appid_startup_v1');
    assert.equal(a.report.missing_binding_is_not_closure, true);
  });
  await t.test('74 managed ABI, token diagnostics, journal, namespace, and closure assertions pass', () => {
    const r = run(['--self-test']); assert.equal(r.status, 0);
    assert.equal(r.report.assertions_passed, 74);
    assert.equal(r.report.native_layouts_passed, true);
    assert.equal(r.report.token_policy_checks_passed, true);
    assert.equal(r.report.journal_rejection_checks_passed, true);
    assert.equal(r.report.token_diagnostic_schema_checks_passed, true);
    assert.equal(r.report.primary_conversion_checks_passed, true);
  });
  await t.test('recovery plan derives a separate stable AppId GUID without journal reads', () => {
    const id = '00000000-0000-0000-0000-000000000001';
    const a = run(['--recovery-plan', id]), b = run(['--recovery-plan', id]);
    assert.equal(a.status, 0); assert.deepEqual(a, b);
    const bytes = createHash('sha256').update('HereIAm.P6R7.AppIdV11/00000000000000000000000000000001/sublayer').digest().subarray(0, 16);
    const guid = `${bytes.readUInt32LE(0).toString(16).padStart(8, '0')}-${bytes.readUInt16LE(4).toString(16).padStart(4, '0')}-${bytes.readUInt16LE(6).toString(16).padStart(4, '0')}-${bytes.subarray(8, 10).toString('hex')}-${bytes.subarray(10).toString('hex')}`;
    assert.equal(a.report.sublayer_key, guid);
    assert.equal(a.report.profile_name, undefined);
  });
  for (const id of ['PRIVATE', '../PRIVATE', '00000000-0000-0000-0000-000000000000',
    '{00000000-0000-0000-0000-000000000001}', '00000000000000000000000000000001', 'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA']) {
    await t.test(`noncanonical attempt rejected: ${id}`, () => {
      const r = run(['--recovery-plan', id]);
      assert.equal(r.status, 2); assert.equal(r.report.error_code, 'invalid_attempt_id');
    });
  }
  for (const args of [['PRIVATE'], ['--plan', 'PRIVATE'], ['--self-test', 'PRIVATE'], ['--recovery-plan'], ['--validate-port', '443']]) {
    await t.test(`unknown or surplus arguments rejected: ${args[0]}`, () => {
      const r = run(args); assert.equal(r.status, 2); assert.equal(r.report.error_code, 'invalid_arguments');
    });
  }
  await t.test('new entrypoint exposes only the new narrow modes', () => {
    const code = readFileSync(source, 'utf8').slice(readFileSync(source, 'utf8').indexOf('public static int Main'));
    assert.match(code, /--apply-cli-appid-startup-synthetic/);
    assert.match(code, /--recover-cli-appid-startup-synthetic/);
    assert.doesNotMatch(code, /--apply-synthetic|--apply-cli-startup-synthetic|--recover-synthetic|--synthetic-worker/);
  });
  await t.test('new source has no credentials, profile, exemption, or alternate token path', () => {
    const code = readFileSync(source, 'utf8');
    assert.doesNotMatch(code, /auth\.json|backend-api|api\.openai\.com|Bearer\s|HttpClient|WebRequest/);
    assert.doesNotMatch(code, /Environment\.GetEnvironmentVariables?\s*\(/);
    assert.doesNotMatch(code, /CreateAppContainerProfile|DeleteAppContainerProfile|NetworkIsolation|ChangeExemption|LogonUser|CreateProcessWithLogon|Impersonate/);
    assert.doesNotMatch(code, /Native\.CreateProcessW\s*\(|\.CreateSuspended\s*\(|Directory\.Delete\s*\(/);
    assert.match(code, /AppIdNative\.CreateProcessAsUserW\(token\.Handle/);
    assert.match(code, /finally \{ if\(memory!=IntPtr.Zero\) Native\.FwpmFreeMemory0\(ref memory\); \}/);
    assert.doesNotMatch(code, /StderrExcerpt|StartupExcerpt/);
  });
  await t.test('v11c accepts only validated source conversion and retains strict primary boundaries', () => {
    const code = readFileSync(source, 'utf8');
    assert.ok(code.includes('return Type==1 && Integrity==8192 && ElevationType==3 && Elevated==0 && AppContainer==0 && Authentication!=0;'));
    assert.ok(code.includes('return full!=null&&linked!=null&&full.Type==1&&full.ElevationType==2&&full.Elevated==1&&full.AppContainer==0&&linked.IsMediumSource&&linked.User==full.User&&linked.Session==full.Session;'));
    const validation = code.slice(code.indexOf('internal static void ValidateLinked'), code.indexOf('internal static LinkedMediumToken Select'));
    assert.ok(validation.indexOf('report["linked_token_diagnostic"]=Diagnostic(full,selected)') < validation.indexOf('Guard.Require(MediumIdentity.AcceptLinked(full,selected)'));
    const diagnosticCode = code.slice(code.indexOf('static object Attributes'), code.indexOf('internal static void ValidateLinked'));
    assert.doesNotMatch(diagnosticCode, /\{\s*"[^"]+"\s*,\s*(?:identity|full|selected)\.(?:User|Session|Authentication)\s*\}/);
    assert.match(diagnosticCode, /"authentication_id_nonzero",identity\.Authentication!=0/);
    assert.match(code, /DuplicateTokenEx\(linked,1\|2\|8,IntPtr.Zero,2,1,out copy\)/);
    assert.match(code, /source\.IsMediumSource && duplicate\.IsMedium/);
    assert.match(code, /AppIdNative\.CreateProcessAsUserW\(token.Handle/);
    assert.match(code, /Identity=duplicate/);
    assert.match(code, /AppContainer==other.AppContainer && Type==other.Type/);
    const r = run(['--plan']); assert.equal(r.report.linked_token_diagnostic, undefined);
  });
});
