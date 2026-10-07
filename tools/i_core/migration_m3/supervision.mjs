import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { closeSync, existsSync, mkdirSync, mkdtempSync, openSync, readFileSync, realpathSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { cleanEnv } from '../test_fixtures/migration_m3/lab.mjs';
export async function until(predicate, timeout = 15000) {
  const started = performance.now();
  while (!predicate()) {
    if (performance.now() - started > timeout) throw new Error('supervision_wait_timeout');
    await new Promise(resolve => setTimeout(resolve, 25));
  }
}
export function startSupervised({ mode = 'pin', timeout = 120000, testOnlyParentOverride = {} } = {}) {
  const ps = path.join(process.env.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe');
  // Query OUR live process before creating any launch files. The supervisor
  // later compares exact creation ticks and fixed image after opening its handle.
  const queried = spawnSync(ps, ['-NoProfile', '-NonInteractive', '-File',
    fileURLToPath(new URL('../test_fixtures/migration_m3/parent_identity.ps1', import.meta.url)), '-ProcessId', String(process.pid)], {
    windowsHide: true, env: cleanEnv(), encoding: 'utf8', timeout: 5000,
  });
  assert.equal(queried.status, 0, queried.stderr);
  const identity = JSON.parse(queried.stdout);
  assert.equal(identity.pid, process.pid);
  assert.equal(realpathSync.native(identity.image), realpathSync.native(process.execPath));
  assert.match(identity.created_ticks, /^\d+$/);
  const root = realpathSync.native(mkdtempSync(path.join(tmpdir(), 'mda2-m3-supervised-')));
  const token = randomBytes(32).toString('hex');
  mkdirSync(path.join(root, 'scratch'));
  writeFileSync(path.join(root, 'owner.json'), JSON.stringify({ token, mode, parent_pid: process.pid,
    parent_created_ticks: identity.created_ticks, parent_image: identity.image, ...testOnlyParentOverride }));
  // File-backed standard handles survive test-parent death. A pipe owned only
  // by that parent can tear down PowerShell's host before it persists cleanup.
  const supervisorLog = path.join(root, 'supervisor.log');
  const descriptor = openSync(supervisorLog, 'wx');
  const child = spawn(ps, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File',
    fileURLToPath(new URL('./launch_supervisor.ps1', import.meta.url)), '-RunRoot', root, '-RunToken', token,
    '-NodePath', process.execPath, '-Mode', mode, '-TimeoutMs', String(timeout)], {
    windowsHide: true, env: cleanEnv(), stdio: ['ignore', descriptor, descriptor],
  });
  closeSync(descriptor);
  let closed = false, exitCode, spawnError;
  const output = () => readFileSync(supervisorLog, 'utf8');
  child.once('error', error => { spawnError = error; });
  child.once('close', code => { closed = true; exitCode = code; });
  let stopPublished = false;
  const stop = () => {
    if (stopPublished) return;
    const staged = path.join(root, `stop-${randomBytes(12).toString('hex')}.tmp`);
    try {
      writeFileSync(staged, token, { flag: 'wx' });
      // Publish only after the writer closes: the native reader denies write sharing.
      renameSync(staged, path.join(root, 'stop'));
      stopPublished = true;
    } finally {
      if (existsSync(staged)) rmSync(staged);
    }
  };
  const cancel = () => stop();
  process.once('SIGINT', cancel); process.once('SIGTERM', cancel);
  return { root, token, child, stop,
    supervisorPid: () => Number(readFileSync(path.join(root, 'supervisor-pid'), 'utf8')),
    ready: async () => { await until(() => existsSync(path.join(root, 'descendant-ready')) || closed); assert.equal(closed, false, JSON.stringify({ root, exitCode, spawnError: spawnError?.message, output: output() })); },
    wait: async () => {
      try {
        await until(() => closed, timeout + 30000);
        if (spawnError) throw spawnError;
        assert.equal(exitCode, 0, output());
        const data = JSON.parse(readFileSync(path.join(root, 'receipt.json')));
        assert.equal(data.token, token); assert.equal(data.mode, mode);
        assert.equal(data.result.child_exit_confirmed, true);
        assert.equal(data.result.child_exit_code_confirmed, true);
        assert.equal(data.result.job_empty_confirmed, true);
        const log = existsSync(path.join(root, 'output.log')) ? readFileSync(path.join(root, 'output.log'), 'utf8') : '';
        const suite = existsSync(path.join(root, 'suite.json')) ? JSON.parse(readFileSync(path.join(root, 'suite.json'))) : null;
        removeOwnedRoot(root);
        return { mode, supervisor_exit: exitCode, result: data.result, scratch_removed: true, log, suite };
      } catch (error) {
        stop();
        // The separate supervisor still owns its native deadline and Job.
        // Never kill just the bootstrap and pretend descendants were reclaimed.
        if (!closed) await until(() => closed, 15000);
        throw error;
      } finally {
        process.removeListener('SIGINT', cancel); process.removeListener('SIGTERM', cancel);
      }
    },
  };
}
export function removeOwnedRoot(root) {
  assert.equal(path.dirname(root), realpathSync.native(tmpdir()));
  assert.ok(path.basename(root).startsWith('mda2-m3-supervised-'));
  rmSync(root, { recursive: true }); assert.equal(existsSync(root), false);
}
