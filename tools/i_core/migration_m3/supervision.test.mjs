import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { tmpdir } from 'node:os';
import test, { after } from 'node:test';
import { fileURLToPath } from 'node:url';
import { cleanEnv, repository } from '../test_fixtures/migration_m3/lab.mjs';
import { removeOwnedRoot, startSupervised, until } from './supervision.mjs';
const receipts = [];
after(() => {
  const output = mkdtempSync(path.join(tmpdir(), 'i-core-m3-supervision-'));
  writeFileSync(path.join(output, 'supervision.json'), JSON.stringify({ cases: receipts }, null, 2) + '\n');
});
test('normal supervised root closes with actual zero-process Job accounting', async () => {
  const result = await startSupervised({ mode: 'normal', timeout: 5000 }).wait();
  assert.equal(result.result.reason, 'completed'); assert.equal(result.result.child_exit_code, 0);
  assert.equal(result.result.parent_binding_verified, true);
  assert.equal(result.result.termination_requested, false); receipts.push(result);
});
for (const mode of ['timeout', 'cancel']) test(`${mode} reclaims actual root and descendant`, async () => {
  const run = startSupervised({ mode: 'descendants', timeout: mode === 'timeout' ? 1500 : 10000 });
  await run.ready();
  if (mode === 'cancel') run.stop();
  const result = await run.wait();
  assert.equal(result.result.reason, mode === 'cancel' ? 'cancelled' : 'timeout');
  assert.equal(result.result.termination_requested, true);
  assert.equal(result.result.parent_binding_verified, true);
  assert.ok(result.result.total_processes >= 2);
  assert.equal(result.result.child_exit_code, 124);
  receipts.push({ fault: mode, ...result });
});

for (const termination of ['exit', 'kill']) test(`actual test-parent ${termination} is observed by held parent handle and reclaims descendant Job`, async () => {
  const parent = spawn(process.execPath, [fileURLToPath(new URL('../test_fixtures/migration_m3/supervisor_parent.mjs', import.meta.url))], {
    env: cleanEnv(), windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stdout = '', stderr = '', parentClosed = false, parentExitCode, parentExitSignal;
  parent.stdout.on('data', b => { stdout += b; }); parent.stderr.on('data', b => { stderr += b; });
  parent.once('close', (code, signal) => { parentClosed = true; parentExitCode = code; parentExitSignal = signal; });
  let root, observer, observerClosed = false, observerCode, observed = '', observerError = '';
  try {
    await until(() => stdout.includes('\n') || parentClosed); assert.equal(parentClosed, false, stderr);
    const data = JSON.parse(stdout.trim()); root = data.root;
    observer = spawn(path.join(process.env.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe'), ['-NoProfile', '-NonInteractive', '-File',
      fileURLToPath(new URL('../test_fixtures/migration_m3/observe_exit.ps1', import.meta.url)), '-ProcessId', String(data.supervisor_pid)], {
      env: cleanEnv(), windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
    });
    observer.stdout.on('data', b => { observed += b; }); observer.stderr.on('data', b => { observerError += b; });
    observer.once('close', code => { observerClosed = true; observerCode = code; });
    await until(() => observed.includes('handle-bound') || observerClosed); assert.equal(observerClosed, false, observerError);
    if (termination === 'exit') writeFileSync(path.join(root, 'parent-exit'), data.token);
    else assert.equal(parent.kill('SIGKILL'), true);
    await until(() => parentClosed && observerClosed, 15000);
    if (termination === 'exit') assert.equal(parentExitCode, 91);
    else assert.equal(parentExitSignal, 'SIGKILL');
    assert.equal(observerCode, 0, observerError);
    const exit = JSON.parse(observed.trim().split(/\r?\n/).at(-1));
    assert.equal(exit.exit_confirmed, true); assert.equal(exit.exit_code, 0);
    assert.equal(existsSync(path.join(root, 'receipt.json')), true, root + ': ' + readFileSync(path.join(root, 'supervisor.log'), 'utf8'));
    const receipt = JSON.parse(readFileSync(path.join(root, 'receipt.json')));
    assert.equal(receipt.token, data.token);
    assert.equal(receipt.result.reason, 'parent_exited');
    assert.equal(receipt.result.parent_binding_verified, true);
    assert.equal(receipt.result.job_empty_confirmed, true);
    assert.equal(receipt.result.child_exit_confirmed, true);
    assert.equal(receipt.result.child_exit_code_confirmed, true);
    assert.ok(receipt.result.total_processes >= 2);
    removeOwnedRoot(root);
    receipts.push({ fault: `parent_${termination}`, parent_close_observed: true, parent_exit_code: parentExitCode,
      parent_exit_signal: parentExitSignal, supervisor_exit: exit,
      result: receipt.result, scratch_removed: !existsSync(root) });
  } finally {
    if (!parentClosed) { parent.kill('SIGKILL'); await until(() => parentClosed, 5000); }
    if (observer && !observerClosed) await until(() => observerClosed, 30000);
  }
});

for (const field of ['parent_created_ticks', 'parent_image']) test(`wrong ${field} rejects before child launch`, async () => {
  const run = startSupervised({ mode: 'normal', timeout: 1000, testOnlyParentOverride: {
    [field]: field === 'parent_created_ticks' ? '0' : path.join(repository, 'synthetic-wrong-image.exe'),
  } });
  await assert.rejects(run.wait());
  const receipt = JSON.parse(readFileSync(path.join(run.root, 'receipt.json')));
  assert.equal(receipt.result.reason, 'parent_identity_mismatch');
  assert.equal(receipt.result.child_started, false);
  assert.equal(receipt.result.parent_binding_verified, false);
  removeOwnedRoot(run.root);
  receipts.push({ fault: field, result: receipt.result, rejection_before_child: true, scratch_removed: true });
});
