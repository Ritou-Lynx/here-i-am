import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, rmSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { syntheticRoot } from '../test_fixtures/release_schema6/synthetic_paths.mjs';
import { validateAclApplyReceipt } from '../maintenance/acl_receipt.mjs';
const source = fileURLToPath(new URL('../maintenance/acl-cutover-maintenance.ps1', import.meta.url));
const fixtures = fileURLToPath(new URL('../test_fixtures/release_schema6/', import.meta.url));
function receiptFixture() {
  const expected = { windowId: 'synthetic-window-01', candidateSourceCommit: 'a'.repeat(40), candidateManifestSha256: 'b'.repeat(64), configSha256: 'c'.repeat(64), freezeSha256: 'd'.repeat(64), snapshot_sha256: 'e'.repeat(64), paths: ['X:\\synthetic\\root', 'X:\\synthetic\\root\\child'], expectedForeignOwnerCount: 1, notBeforeUtc: '2026-01-01T00:00:00Z', notAfterUtc: '2026-01-01T00:10:00Z' };
  const receipt = { ...Object.fromEntries(Object.entries(expected).filter(([k]) => !['paths', 'expectedForeignOwnerCount', 'notBeforeUtc', 'notAfterUtc'].includes(k))), format: 'schema6-acl-maintenance-v2', mode: 'Apply', passed: true, scope: 'owner_and_dacl_only', sacl_restored: false, target_contents_read: false, services_changed: false, tasks_changed: false, rollback_attempted: false, inventory_verified: true, metadata_unchanged: true, freeze_verified: true, expected_count: 2, verified_count: 2, expected_foreign_owner_count: 1, started_utc: '2026-01-01T00:01:00Z', completed_utc: '2026-01-01T00:02:00Z', items: [] };
  for (const action of ['baseline_comparison', 'apply_owner_dacl', 'apply_readback']) for (const p of expected.paths) receipt.items.push({ path: p, action, verified: true, code: '', at_utc: '2026-01-01T00:01:30Z' });
  return { receipt, expected };
}
test('ACL receipt requires exact per-item baseline/apply/final readback and returns no human acceptance', () => {
  const { receipt, expected } = receiptFixture();
  assert.deepEqual(validateAclApplyReceipt(receipt, expected), { passed: true, verifiedCount: 2, windowId: expected.windowId, scope: 'owner_and_dacl_only', humanAcceptance: false });
});
for (const [label, mutate] of [
  ['passed only', r => { for (const key of Object.keys(r)) if (key !== 'passed') delete r[key]; }],
  ['stale window', r => { r.windowId = 'synthetic-window-old'; }],
  ['other candidate', r => { r.candidateSourceCommit = 'f'.repeat(40); }],
  ['other manifest', r => { r.candidateManifestSha256 = 'f'.repeat(64); }],
  ['other freeze', r => { r.freezeSha256 = 'f'.repeat(64); }],
  ['other config', r => { r.configSha256 = 'f'.repeat(64); }],
  ['missing row', r => r.items.pop()],
  ['duplicate row', r => { r.items[5] = structuredClone(r.items[4]); }],
  ['different path', r => { r.items[5].path += '.new'; }],
  ['unverified row', r => { r.items[5].verified = false; }],
  ['old success', r => { r.started_utc = '2025-01-01T00:01:00Z'; }],
  ['future item', r => { r.items[5].at_utc = '2027-01-01T00:01:30Z'; }],
  ['wrong total', r => { r.verified_count = 1; }],
  ['wrong legacy owner count', r => { r.expected_foreign_owner_count = 0; }],
  ['privilege restore failure', r => { r.privilege_restore_failed = true; }],
  ['deferred rollback', r => { r.rollback_deferred = true; }],
  ['string boolean', r => { r.passed = 'true'; }],
]) test(`ACL receipt rejects ${label}`, () => {
  const { receipt, expected } = receiptFixture(); mutate(receipt); assert.throws(() => validateAclApplyReceipt(receipt, expected));
});
test('ACL expected anchors and complete paths are mandatory', () => {
  const { receipt, expected } = receiptFixture(); delete expected.notBeforeUtc; assert.throws(() => validateAclApplyReceipt(receipt, expected));
});
test('migrated maintenance sources contain no deployed paths, private SIDs or implicit execution', () => {
  for (const name of ['acl-cutover-maintenance.ps1', 'owner-apply-runtime-permissions.ps1', 'owner_elevation_probe.ps1']) {
    const text = readFileSync(path.join(path.dirname(source), name), 'utf8');
    assert.doesNotMatch(text, /HereIAmRuntime|cutover-20261007|S-1-5-21-|HereIAm-iCore|47841|47860|47862/);
    assert.doesNotMatch(text, /ReadKey|Start-Process|Stop-Service|Register-ScheduledTask/);
  }
});
for (const [name, script] of [['native owner/DACL/inheritance apply, full restore and pending preservation', 'maintenance_acl_native.ps1'], ['import, hash, forged/stale/expired freeze contracts', 'maintenance_acl_contract.ps1'], ['full audit, byte-preserving guard exclusion and inventory drift', 'maintenance_acl_audit.ps1'], ['foreign owner privilege roundtrip (requires administrator token)', 'maintenance_acl_owner.ps1']]) {
  test(`Windows ACL synthetic ${name}`, { skip: process.platform !== 'win32' }, t => {
    const root = syntheticRoot('maintenance-acl-synthetic-');
    t.after(() => { assert.ok(path.basename(root).startsWith('maintenance-acl-synthetic-')); rmSync(root, { recursive: true, force: true }); });
    const ps = path.join(process.env.SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
    const result = spawnSync(ps, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', path.join(fixtures, script), '-SourcePath', source, '-FixtureParent', root], { encoding: 'utf8', timeout: 60000, windowsHide: true, env: { ...process.env, PSModulePath: path.join(path.dirname(ps), 'Modules') } });
    assert.equal(result.error, undefined); assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    const receipt = JSON.parse(result.stdout.trim());
    if (receipt.skipped === true && script === 'maintenance_acl_owner.ps1') {
      assert.notEqual(process.env.SCHEMA6_SYNTHETIC_OWNER_PROBE, '1', 'CI requires real foreign-owner privilege roundtrip; unavailable token is a failure');
      t.skip(receipt.reason); return;
    }
    assert.equal(receipt.passed, true);
    if (script === 'maintenance_acl_owner.ps1') t.diagnostic(JSON.stringify({ foreignOwnerRoundtripVerified: receipt.foreign_owner_roundtrip_verified, productionPathsTouched: receipt.production_paths_touched, servicesChanged: receipt.services_changed, tasksChanged: receipt.tasks_changed }));
    if (script.includes('native')) { assert.equal(receipt.production_script_executed, false); assert.equal(receipt.privilege_enabled, false); assert.equal(receipt.checks.length, 4); }
  });
}
