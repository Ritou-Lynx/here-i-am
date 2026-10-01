// Compiles and runs ONLY pure/read-only entrypoints. Never executes apply or recovery.
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, rmSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const source = fileURLToPath(new URL('./windows_text_gate_isolation_helper.cs', import.meta.url));
const csc = String.raw`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`;
const supported = process.platform === 'win32' && existsSync(csc);

test('native helper compiles with installed Framework and keeps all non-apply paths inert', { skip: !supported }, async t => {
  const root = mkdtempSync(path.join(tmpdir(), 'hereiam-r7-helper-test-'));
  const executable = path.join(root, 'helper.exe');
  t.after(() => {
    const canonical = realpathSync(root);
    assert.equal(path.dirname(canonical), realpathSync(tmpdir()));
    assert.match(path.basename(canonical), /^hereiam-r7-helper-test-/);
    rmSync(canonical, { recursive: true, force: true });
  });
  const compile = spawnSync(csc, ['/nologo', '/target:exe', '/platform:x64', '/optimize+',
    '/reference:System.Web.Extensions.dll', `/out:${executable}`, source], { encoding: 'utf8', windowsHide: true, timeout: 30_000 });
  assert.equal(compile.status, 0, 'Framework x64 compilation failed');
  assert.equal(compile.stderr, '');

  function run(args) {
    assert.ok(!args.includes('--apply-synthetic') || args.length > 1, 'Tests must never select the apply entrypoint');
    assert.ok(!args.includes('--recover-synthetic') || args.length !== 2, 'Tests must never select the recovery entrypoint');
    assert.ok(!args.includes('--apply-cli-startup-synthetic') || args.length !== 2, 'Tests must never select CLI startup');
    assert.ok(!args.includes('--synthetic-worker') && !args.includes('--synthetic-leaf'));
    const result = spawnSync(executable, args, { encoding: 'utf8', windowsHide: true, timeout: 10_000 });
    assert.equal(result.signal, null);
    assert.equal(result.stderr, '');
    assert.ok(!result.stdout.includes('PRIVATE'));
    const report = JSON.parse(result.stdout);
    assert.equal(report.system_mutation_requested, false);
    assert.equal(report.real_upstream_requests, 0);
    assert.equal(report.production_isolation_passed, false);
    assert.equal(report.human_gate_passed, false);
    return { status: result.status, report };
  }

  await t.test('default and explicit plan agree and report unverified native enforcement', () => {
    const a = run([]), b = run(['--plan']);
    assert.equal(a.status, 0); assert.deepEqual(a, b);
    assert.equal(a.report.network_capabilities, 0);
    assert.equal(a.report.job_active_process_limit, 1);
    assert.equal(a.report.job_association_at_process_creation, true);
    assert.equal(a.report.wfp_filter_count, 3);
    assert.equal(a.report.wfp_dynamic_session, false);
    assert.equal(a.report.wfp_persistent_filters, false);
    assert.equal(a.report.broker_ipv4_loopback_only, true);
    assert.equal(a.report.requires_exclusive_loopback_config_window, true);
    assert.equal(a.report.loopback_config_atomic_update, false);
    assert.ok(a.report.unverified.includes('native_apply'));
    assert.ok(a.report.cleanup_order.indexOf('prove_process_exit_and_job_zero') < a.report.cleanup_order.indexOf('remove_own_wfp_keys'));
  });
  await t.test('pure ABI/policy/peer tuple/cleanup checks pass without creating a container', () => {
    const r = run(['--self-test']);
    assert.equal(r.status, 0); assert.equal(r.report.native_layouts_passed, true);
    assert.equal(r.report.assertions_passed, 100);
    assert.equal(r.report.environment_contract_passed, true);
  });
  await t.test('recovery plan derives only fixed attempt-owned resource names', () => {
    const id = '00000000-0000-0000-0000-000000000001';
    const a = run(['--recovery-plan', id]), b = run(['--recovery-plan', id]);
    assert.equal(a.status, 0); assert.deepEqual(a, b);
    assert.equal(a.report.mode, 'recovery_plan');
    assert.equal(a.report.attempt_id, id);
    assert.equal(a.report.profile_name, 'HereIAm.P6R7.00000000000000000000000000000001');
    assert.equal(a.report.missing_binding_is_not_job_zero, true);
  });
  for (const id of ['PRIVATE', '../PRIVATE', '00000000-0000-0000-0000-000000000000',
    '{00000000-0000-0000-0000-000000000001}', '00000000000000000000000000000001', 'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA'])
    await t.test(`noncanonical recovery identifier rejected (${id})`, () => {
      const r = run(['--recovery-plan', id]);
      assert.equal(r.status, 2); assert.equal(r.report.error_code, 'invalid_attempt_id');
    });
  for (const port of ['1', '443', '65535']) await t.test(`canonical port ${port} accepted`, () => {
    const r = run(['--validate-port', port]); assert.equal(r.status, 0); assert.equal(r.report.broker_port, Number(port));
  });
  for (const port of ['0', '65536', '-1', '01', '+1', ' 1', '1 ', '1.0', '1e3', 'PRIVATE'])
    await t.test(`invalid port rejected (${JSON.stringify(port)})`, () => {
      const r = run(['--validate-port', port]); assert.equal(r.status, 2); assert.equal(r.report.error_code, 'invalid_port');
    });
  for (const args of [['--apply'], ['--apply-synthetic', '--PRIVATE'], ['--recover-synthetic'],
    ['--recover-synthetic', 'PRIVATE', 'PRIVATE'], ['--apply-cli-startup-synthetic'],
    ['--apply-cli-startup-synthetic', 'PRIVATE', 'PRIVATE'], ['--plan', '--PRIVATE'], ['--validate-port'], ['PRIVATE']])
    await t.test(`unknown or surplus arguments cannot select a mutating path (${args[0]})`, () => {
      const r = run(args); assert.equal(r.status, 2); assert.equal(r.report.error_code, 'invalid_arguments');
    });
  await t.test('candidate contains no credential or provider integration', () => {
    const code = readFileSync(source, 'utf8');
    assert.doesNotMatch(code, /auth\.json|backend-api|api\.openai\.com|Bearer\s|HttpClient|WebRequest/);
    assert.doesNotMatch(code, /Environment\.GetEnvironmentVariables?\s*\(/);
  });
});
