import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, rmSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { syntheticRoot } from '../test_fixtures/release_schema6/synthetic_paths.mjs';
const source = fileURLToPath(new URL('../maintenance/protect-backup-config-file.ps1', import.meta.url));
const fixture = fileURLToPath(new URL('./fixtures/maintenance_backup_config_acl.ps1', import.meta.url));

test('backup config ACL entry is a parameter-bound single-file maintenance operation', () => {
  const text = readFileSync(source, 'utf8');
  assert.doesNotMatch(text, /S-1-5-21-|HereIAmRuntime|Start-Process|AdjustTokenPrivileges|WRITE_OWNER\s*\||SetOwner\(|SetFileSecurity\(|SetSecurityInfo\(|TestMode|SkipValidation|BypassGuard/);
  assert.match(text, /NtSetSecurityObject\(h,4u/);
  assert.match(text, /ExpectedOriginalDaclSha256/);
  assert.match(text, /ExpectedProposedDaclSha256/);
  assert.match(text, /SetAccessRuleProtection\(\$true,\$false\)/);
  assert.match(text, /Write-OwnedArtifactBytes/);
  assert.match(text, /Assert-BackupConfigFixedAcl/);
});

test('Windows PS5 single-file ACL success, guards, same-handle locking and rollback', { skip: process.platform !== 'win32' }, t => {
  const root = syntheticRoot('maintenance-backup-config-acl-');
  t.after(() => {
    assert.ok(path.basename(root).startsWith('maintenance-backup-config-acl-'));
    rmSync(root, { recursive: true, force: true });
  });
  const ps = path.join(process.env.SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
  const result = spawnSync(ps, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', fixture, '-SourcePath', source, '-FixtureParent', root], {
    encoding: 'utf8', timeout: 60000, windowsHide: true,
    env: { ...process.env, PSModulePath: path.join(path.dirname(ps), 'Modules') },
  });
  assert.equal(result.error, undefined);
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  const receipt = JSON.parse(result.stdout.trim());
  assert.equal(receipt.passed, true);
  assert.equal(receipt.productionPathsTouched, false);
  assert.equal(receipt.privilegeEnabled, false);
  assert.equal(receipt.psMajor, 5);
  for (const check of ['inherited_three_to_protected_two', 'fixed_production_assertion_accepts', 'unchanged_identity_bytes_owner_parent_sibling', 'receipt_owner_readback', 'success_checkpoint_is_nonterminal', 'reject_wrong_content', 'reject_wrong_owner', 'reject_wrong_original_dacl', 'reject_wrong_proposed_dacl', 'reject_hardlink', 'reject_reparse', 'failure_restores_exact_dacl', 'rollback_failure_remains_unknown', 'snapshot_failure_before_mutation', 'result_failure_rolls_back', 'written_result_failure_has_no_terminal_success', 'final_assertion_failure_has_no_terminal_success', 'snapshot_and_target_locked', 'dispatch_success']) {
    assert.ok(receipt.checks.includes(check), check);
  }
  t.diagnostic(`${receipt.checks.length} synthetic assertions; source SHA256 ${receipt.sourceSha256}`);
});
