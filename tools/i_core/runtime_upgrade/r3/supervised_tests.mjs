// Test-only derivative of R1; no production command input.
import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { performance } from 'node:perf_hooks';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { plainPath, cleanEnvironment } from './package.mjs';
const assertPlainPath = target => plainPath(target, { existing: false });

const supervisor = fileURLToPath(new URL('./owned_test_job.ps1', import.meta.url));
export const RUN_TIMEOUT_MS = 360_000;
const STOP_GRACE_MS = 12_000; // Includes the job's 5 s accounting + 5 s handle waits.
const DIRECT_EXIT_GRACE_MS = 5_000;
const modes = new Set(['suite', 'normal', 'hang', 'descendant-hang', 'residual', 'startup-failure', 'supervisor-start-failure', 'missing-receipt', 'forged-receipt']);

export function confirmedReceipt(receipt, token, mode) {
  return receipt?.token === token && receipt?.mode === mode
    && receipt.result?.job_empty_confirmed === true && receipt.result?.child_exit_confirmed === true;
}

export function runSyntheticTests(options = {}) { return runSyntheticFixture('suite', options); }

// Bounded, fixed synthetic modes for tests; there is no external path/command input.
export async function runSyntheticFixture(mode, { timeoutMs = RUN_TIMEOUT_MS, signal, onReady } = {}) {
  if (!modes.has(mode)) throw new Error('unknown_synthetic_mode');
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 50 || timeoutMs > RUN_TIMEOUT_MS) throw new Error('invalid_timeout');
  if (signal?.aborted) return { exit_code: 1, reason: 'cancelled_before_start', supervisor_exit_confirmed: true,
    child_exit_confirmed: true, job_empty_confirmed: true, cleanup_confirmed: true, child_started: false };
  const parent = realpathSync.native(tmpdir());
  assertPlainPath(parent);
  const root = mkdtempSync(path.join(parent, 'mda2-r3-supervised-'));
  const token = randomBytes(32).toString('hex');
  writeFileSync(path.join(root, 'owner.json'), JSON.stringify({ token, mode }), { flag: 'wx' });
  mkdirSync(path.join(root, 'scratch'));
  const ps = mode === 'supervisor-start-failure' ? path.join(root, 'missing-supervisor.exe')
    : path.join(process.env.SystemRoot ?? 'C:\\Windows', 'System32/WindowsPowerShell/v1.0/powershell.exe');
  let child;
  let exitConfirmed = false;
  let closeConfirmed = false;
  let spawnError;
  let exitCode;
  let stderr = '';
  let stopReason;
  let forceRequested = false;
  let stopWriteFailed = false;
  let readyDelivered = false;
  let onAbort;
  const stop = reason => {
    stopReason ??= reason;
    try {
      assertPlainPath(root);
      assertPlainPath(path.join(root, 'stop'));
      writeFileSync(path.join(root, 'stop'), token);
    } catch { stopWriteFailed = true; }
  };
  try {
    child = spawn(ps, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', supervisor,
      '-RunRoot', root, '-RunToken', token, '-NodePath', process.execPath, '-FixtureMode', mode,
      '-TimeoutMs', String(timeoutMs)], { env: cleanEnvironment(), windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'] });
    // ChildProcess owns the native handle. Fallback kill never searches by name
    // or reacquires a possibly reused PID, and never treats kill() as exit proof.
    child.stderr.on('data', chunk => { if (stderr.length < 8192) stderr += chunk.toString().slice(0, 8192 - stderr.length); });
    child.once('error', error => { spawnError = error.code ?? 'spawn_error'; });
    child.once('exit', code => { exitCode = code; exitConfirmed = true; });
    child.once('close', () => { closeConfirmed = true; });
    onAbort = () => stop('cancelled');
    signal?.addEventListener('abort', onAbort, { once: true });
    if (signal?.aborted) onAbort();
    const started = performance.now();
    let stopAt;
    let forceAt;
    while (!closeConfirmed) {
      const now = performance.now();
      if (!readyDelivered && existsSync(path.join(root, 'ready'))) {
        readyDelivered = true;
        try { onReady?.(); } catch { stop('callback_failed'); }
      }
      if (now - started >= timeoutMs) stop('timeout');
      if (stopReason) stopAt ??= now;
      if (stopAt !== undefined && now - stopAt >= STOP_GRACE_MS && !forceRequested) {
        forceRequested = true;
        forceAt = now;
        if (!exitConfirmed && child.pid !== undefined) {
          try { child.kill('SIGKILL'); } catch { /* Unconfirmed exit is returned below. */ }
        }
      }
      if (forceAt !== undefined && now - forceAt >= DIRECT_EXIT_GRACE_MS) break;
      await new Promise(resolve => setTimeout(resolve, 25));
    }
  } catch (error) {
    spawnError = error.code ?? 'supervisor_setup_error';
  } finally {
    if (onAbort) signal?.removeEventListener('abort', onAbort);
    if (!closeConfirmed && child) {
      // Do not let an unconfirmed process keep the parent's event loop alive.
      // Preserve the run root and return failure, never claim it was reaped.
      child.stderr?.destroy();
      child.unref();
    }
  }
  let receipt;
  let output = '';
  let scratch = [];
  let inspectionFailed = false;
  let descendantReady = false;
  try {
    assertPlainPath(root);
    for (const name of readdirSync(root)) assertPlainPath(path.join(root, name));
    if (existsSync(path.join(root, 'receipt.json'))) receipt = JSON.parse(readFileSync(path.join(root, 'receipt.json')));
    if (existsSync(path.join(root, 'output.log'))) output = readFileSync(path.join(root, 'output.log'), 'utf8');
    descendantReady = existsSync(path.join(root, 'grandchild-ready'))
      && readFileSync(path.join(root, 'grandchild-ready'), 'utf8') === token;
    scratch = readdirSync(path.join(root, 'scratch'));
  } catch { inspectionFailed = true; }
  const neverStarted = child?.pid === undefined && Boolean(spawnError);
  const supervisorConfirmed = neverStarted || (exitConfirmed && closeConfirmed);
  const descendantsConfirmed = neverStarted || confirmedReceipt(receipt, token, mode);
  const result = receipt?.result;
  let cleanupConfirmed = false;
  let cleanupError;
  if (supervisorConfirmed && descendantsConfirmed && !inspectionFailed && scratch.length === 0) {
    try {
      const expected = new Set(['owner.json', 'scratch', 'receipt.json', 'output.log', 'ready', 'grandchild-ready', 'stop']);
      if (readdirSync(root).some(name => !expected.has(name))) throw new Error('unexpected_run_content');
      if (path.dirname(root) !== parent || !path.basename(root).startsWith('mda2-r3-supervised-')) throw new Error('unowned_cleanup_path');
      assertPlainPath(root);
      rmSync(root, { recursive: true });
      cleanupConfirmed = !existsSync(root);
    } catch (error) { cleanupError = error.code ?? error.message; }
  }
  const ok = !stopReason && !spawnError && !forceRequested && !stopWriteFailed && exitCode === 0
    && result?.reason === 'completed' && result.child_exit_code_confirmed === true && result.child_exit_code === 0
    && supervisorConfirmed && descendantsConfirmed && cleanupConfirmed;
  return {
    exit_code: ok ? 0 : 1, reason: spawnError ? (neverStarted ? 'supervisor_start_failed' : 'supervisor_failed') : stopReason
      ?? (!descendantsConfirmed ? 'exit_unconfirmed' : !cleanupConfirmed ? 'temporary_residue'
        : result?.reason === 'completed' && !result.child_exit_code_confirmed ? 'test_exit_code_unconfirmed'
          : result?.reason === 'completed' && result.child_exit_code !== 0 ? 'tests_failed' : result?.reason ?? 'supervisor_failed'),
    supervisor_exit_confirmed: supervisorConfirmed, child_started: result?.child_started ?? (neverStarted ? false : null),
    child_exit_confirmed: descendantsConfirmed, job_empty_confirmed: descendantsConfirmed,
    cleanup_confirmed: cleanupConfirmed, force_requested: forceRequested,
    termination_requested: result?.termination_requested ?? null, total_processes: result?.total_processes ?? (neverStarted ? 0 : null),
    descendant_fixture_ready: descendantReady, stop_request_failed: stopWriteFailed,
    test_exit_code_confirmed: result?.child_exit_code_confirmed ?? neverStarted,
    ...(result?.child_started ? { test_exit_code: result.child_exit_code } : {}),
    ...(cleanupConfirmed ? {} : { retained_root: root, residual_entries: scratch, inspection_failed: inspectionFailed }),
    ...(cleanupError ? { cleanup_error: cleanupError } : {}), ...(spawnError ? { spawn_error: spawnError } : {}),
    ...(stderr ? { supervisor_stderr: stderr } : {}), output,
  };
}
