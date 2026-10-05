import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { performance } from 'node:perf_hooks';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { seedSchema4 } from '../../schema4/synthetic_schema4.mjs';
import { cleanEnvironment, plainPath, prepareRelease, sha256 } from '../../../runtime_upgrade/r3/package.mjs';

export const repository = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../../..');
export const ps = path.join(process.env.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe');
export const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
export async function until(predicate, timeoutMs = 15000) {
  const start = performance.now();
  while (performance.now() - start < timeoutMs) { const value = predicate(); if (value) return value; await sleep(25); }
  throw new Error('fixture_wait_timeout');
}
export function confirmedReceipt(receipt, launch) {
  return Boolean(receipt && launch) && receipt.token === launch.token && receipt.mode === launch.mode
    && receipt.manifest_sha256 === launch.manifest_sha256
    && receipt.result?.child_started === true && receipt.result?.child_exit_confirmed === true
    && receipt.result?.child_exit_code_confirmed === true && receipt.result?.job_empty_confirmed === true;
}
export function protect(directory) {
  const quote = s => "'" + s.replaceAll("'", "''") + "'";
  execFileSync(ps, ['-NoProfile', '-NonInteractive', '-Command', `$ErrorActionPreference='Stop'; . ${quote(path.join(repository, 'tools/i_core/runtime_upgrade/r3/protected_paths.ps1'))}; Protect-NewDirectory ${quote(directory)}`], { windowsHide: true, env: cleanEnvironment(), timeout: 10000 });
}
export async function createLab(t) {
  const parent = realpathSync.native(tmpdir());
  const root = mkdtempSync(path.join(parent, 'mda2-r3-'));
  const owned = name => {
    const result = path.resolve(root, name);
    const relative = path.relative(root, result);
    if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) throw new Error('unowned_fixture_path');
    plainPath(result, { existing: false });
    return result;
  };
  protect(root);
  const runs = [];
  t.after(async () => {
    for (const run of runs) {
      if (!run.closed) { await run.stop('stop'); await run.wait(); }
      if (run.witnessWait) await run.witnessWait();
      assert.equal(run.closed, true, 'retain resources unless supervisor close observed');
      if (run.childStarted) assert.equal(run.confirmed, true, 'retain resources unless exact Job receipt confirms exit');
    }
    const scan = dir => { plainPath(dir); for (const item of readdirSync(dir, { withFileTypes: true })) {
      const target = owned(path.relative(root, path.join(dir, item.name)));
      if (item.isDirectory()) scan(target);
    } };
    scan(root);
    assert.equal(path.dirname(root), parent);
    assert.match(path.basename(root), /^mda2-r3-/);
    rmSync(root, { recursive: true });
    assert.equal(existsSync(root), false);
  });
  const release = owned('release');
  const packageResult = prepareRelease({ repository, output: release });
  const state = owned('state'); mkdirSync(state); protect(state);
  // Public synthetic schema4 rows; no dependency on private historical source.
  const database = path.join(state, 'i-core.sqlite');
  seedSchema4(database);
  // R3 starts with workers/jobs disabled, as its original chat-only v4 input did.
  // M3's representative stale claim must not compete with this scenario's r3-turn.
  const seed = new DatabaseSync(database);
  try { seed.exec('DELETE FROM companion_reply_shadow_runs; DELETE FROM companion_reply_jobs; DELETE FROM worker_leases;'); }
  finally { seed.close(); }
  const paired = { device_token: 'synthetic-token' };
  const identity = 'm3-synthetic-node';
  const inspect = (action, filename = database) => {
    const before = sha256(readFileSync(filename));
    const db = new DatabaseSync(`${pathToFileURL(filename).href}?mode=ro&immutable=1`, { readOnly: true });
    try { return action(db); } finally { db.close(); assert.equal(sha256(readFileSync(filename)), before); }
  };
  const rows = () => inspect(db => Object.fromEntries(['core_metadata', 'devices', 'consumed_pairing_codes', 'change_events', 'chat_messages',
    'worker_leases', 'companion_reply_jobs', 'companion_reply_shadow_runs'].map(table => [table, db.prepare(`SELECT * FROM ${table} ORDER BY rowid`).all()
      .filter(row => table !== 'core_metadata' || (row.key !== 'schema_version' && !row.key.startsWith('activity_')))])));
  const launch = ({ args = [], env = {}, start = true, migrate = true, targetState = state, port = 0, timeout = 20000, configurationFile = null, manifestHash = packageResult.manifest_sha256 } = {}) => {
    const control = owned(`control-${randomBytes(6).toString('hex')}`); mkdirSync(control); protect(control);
    const runtimeArgs = start ? ['-Start', ...(migrate ? ['-MigrateV4'] : []), '-StateDirectory', targetState, '-ControlDirectory', control,
      '-CorePort', String(port), ...(configurationFile ? ['-ConfigurationFile', configurationFile] : [])] : [];
    const child = spawn(ps, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', path.join(release, 'start_schema5.ps1'),
      '-ManifestSha256', manifestHash, ...runtimeArgs, ...args],
    { env: { ...cleanEnvironment(), ...env }, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    const run = { child, control, closed: false, exit: null, stdout: '', stderr: '', confirmed: false, childStarted: false };
    child.stdout.on('data', b => { run.stdout += b; }); child.stderr.on('data', b => { run.stderr += b; });
    child.on('error', error => { run.error = error.message; });
    child.on('close', code => { run.closed = true; run.exit = code; });
    run.read = name => existsSync(path.join(control, name)) ? JSON.parse(readFileSync(path.join(control, name))) : null;
    run.stop = async (name = 'close') => {
      const config = await until(() => run.read('launch.json') || run.closed);
      if (config !== true) {
        const result = execFileSync(ps, ['-NoProfile', '-NonInteractive', '-File', path.join(release, 'request_stop.ps1'),
          '-ControlDirectory', control, '-RunId', config.token, '-ManifestSha256', config.manifest_sha256, '-Action', name],
          { windowsHide: true, env: cleanEnvironment(), timeout: 10000 });
      }
    };
    run.ready = async () => {
      // Includes cold PowerShell/C# startup under the recursive parallel suite.
      // Startup is independent of the short wait budget used by cancellation tests.
      const ready = await until(() => run.read('ready.json') || run.closed, 60000);
      assert.notEqual(ready, true, run.stderr + run.stdout + JSON.stringify(run.read('child.json')));
      return ready;
    };
    run.wait = async () => {
      await until(() => run.closed, timeout + 20000);
      const receipt = run.read('supervisor.json');
      run.childStarted = receipt?.result?.child_started === true;
      run.confirmed = confirmedReceipt(receipt, run.read('launch.json'));
      return { exit: run.exit, receipt, child: run.read('child.json'), stderr: run.stderr, stdout: run.stdout };
    };
    runs.push(run); return run;
  };
  return { root, owned, state, database, release, packageResult, inspect, rows, paired, identity, launch };
}
