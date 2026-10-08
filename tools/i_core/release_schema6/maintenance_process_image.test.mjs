import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, realpathSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const repository = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');

test('process-image module keeps strict data pins separate and loads native interop lazily', () => {
  const source = readFileSync(path.join(repository, 'tools/i_core/maintenance/process_image_binding.ps1'), 'utf8');
  assert.match(source, /function Assert-ProcessImageFile/);
  assert.match(source, /function Get-BoundProcessIdentity/);
  assert.match(source, /GetWindowsDirectory/);
  assert.doesNotMatch(source, /function (?:Pin|FileStamp|PIdentity)\b|FreezeIdentity|Stop-Process|RegisterTask/);
});

test('Windows PS 5.1 process-image policy, hardlinks, leases and actual PID binding', { skip: process.platform !== 'win32', timeout: 60000 }, (context) => {
  const root = realpathSync.native(mkdtempSync(path.join(realpathSync.native(tmpdir()), 'maintenance-process-image-')));
  try {
    const ps = path.join(process.env.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe');
    const raw = execFileSync(ps, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', path.join(repository, 'tools/i_core/test_fixtures/release_schema6/maintenance_process_image.ps1'), '-Repository', repository, '-FixtureRoot', root, '-NodePath', process.execPath], { encoding: 'utf8', windowsHide: true, timeout: 50000 });
    const result = JSON.parse(raw);
    for (const [key, value] of Object.entries(result)) {
      if (!['tasksCreated', 'realSystemHardlinkCount'].includes(key)) assert.equal(value, true, key);
    }
    assert.equal(result.tasksCreated, 0);
    assert.ok(result.realSystemHardlinkCount >= 1);
    assert.ok(Object.keys(result).length >= 30);
    for (const key of ['importSafe', 'systemHardlinkTwoAccepted', 'systemOwnerRejected', 'systemAliasRejected', 'systemHashRejected', 'systemReparseRejected', 'systemCaseCannotBypassOwner', 'systemSeparatorBoundary', 'realSystemImageAccepted', 'nonSystemHardlinkAccepted', 'leaseBlocksWrite', 'leaseBlocksAliasWrite', 'leaseBlocksDelete', 'wrongHashRejected', 'failedPinReleasesLease', 'nativeJunctionRejected', 'realSyntheticProcessBound', 'cimNineTicksAccepted', 'cimPositiveNineTicksAccepted', 'cimTenTicksRejected', 'reusedPidCreationRejected', 'cimPathRejected', 'unapprovedProcessRejected', 'processHashRejected', 'exitedHeldProcessRejected']) assert.equal(result[key], true, key);
    context.diagnostic(JSON.stringify({ assertions: Object.keys(result).filter(key => result[key] === true).length, realSystemHardlinkCount: result.realSystemHardlinkCount, tasksCreated: result.tasksCreated }));
  } finally { rmSync(root, { recursive: true, force: true }); }
});

