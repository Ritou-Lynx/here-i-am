import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, rmSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { syntheticRoot } from '../test_fixtures/release_schema6/synthetic_paths.mjs';
const source = fileURLToPath(new URL('../maintenance/protect-approved-settings.ps1', import.meta.url));
const fixture = fileURLToPath(new URL('../test_fixtures/release_schema6/maintenance_settings_acl.ps1', import.meta.url));
test('settings protection entry has no deployment constants, privilege, owner mutation or production test bypass', () => {
  const text = readFileSync(source, 'utf8');
  assert.doesNotMatch(text, /S-1-5-21-|HereIAmRuntime|Start-Process|AdjustTokenPrivileges|SetOwnerDacl|SetSecurityInfo\(|SetOwner\(|TestMode|SkipValidation|BypassGuard/);
  assert.match(text, /SetFileSecurity\(path.ToString\(\),4u/);
  assert.match(text, /SetAccessRuleProtection\(\$true,\$true\)/);
  assert.match(text, /Flush\(\$true\)/);
});
test('Windows settings ACL synthetic success, guards, exact rollback and lock checks', { skip: process.platform !== 'win32' }, t => {
  const root = syntheticRoot('maintenance-settings-acl-');
  t.after(() => { assert.ok(path.basename(root).startsWith('maintenance-settings-acl-')); rmSync(root, { recursive: true, force: true }); });
  const ps = path.join(process.env.SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
  const result = spawnSync(ps, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', fixture, '-SourcePath', source, '-FixtureParent', root], { encoding: 'utf8', timeout: 60000, windowsHide: true, env: { ...process.env, PSModulePath: path.join(path.dirname(ps), 'Modules') } });
  assert.equal(result.error, undefined); assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  const receipt = JSON.parse(result.stdout.trim());
  assert.equal(receipt.passed, true); assert.equal(receipt.productionPathsTouched, false); assert.equal(receipt.privilegeEnabled, false);
  for (const name of ['protection_success', 'reject_owner_mismatch', 'reject_wrong_proposal', 'reject_wrong_hash', 'reject_hardlink', 'reject_reparse', 'reject_extra_file', 'reject_sddl_drift', 'failure_restores_exact_dacl_and_files', 'write_denied_while_pinned']) assert.ok(receipt.checks.includes(name), name);
  t.diagnostic(`${receipt.checks.length} synthetic assertions; source SHA256 ${receipt.sourceSha256}`);
});
