import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import net from 'node:net';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { createLab, ps, until, protect } from '../../test_fixtures/runtime_upgrade/r3/lab.mjs';
import { cleanEnvironment, plainPath, sha256 } from './package.mjs';
import { runSyntheticFixture, confirmedReceipt } from './supervised_tests.mjs';

test('invalid v4 shape rejects without starting migration; open sidecar and missing DB reject without constructor', async t => {
  const lab = await createLab(t);
  const db = new DatabaseSync(lab.database); db.exec('ALTER TABLE devices ADD COLUMN synthetic_extra TEXT'); db.close();
  const before = sha256(readFileSync(lab.database));
  const rejected = await lab.launch().wait();
  assert.equal(rejected.exit, 1); assert.equal(rejected.child.error_code, 'schema4_preflight_rejected');
  assert.equal(rejected.child.store_construction_attempted, false); assert.equal(sha256(readFileSync(lab.database)), before);
  writeFileSync(lab.database + '-wal', 'synthetic invalid sidecar');
  const sidecar = await lab.launch().wait(); assert.equal(sidecar.child.error_code, 'state_sidecars_require_review');
  assert.equal(readFileSync(lab.database + '-wal','utf8'), 'synthetic invalid sidecar');
  const empty = lab.owned('empty-state'); mkdirSync(empty); protect(empty);
  const missing = await lab.launch({ targetState: empty }).wait();
  assert.equal(missing.child.store_construction_attempted, false); assert.equal(missing.exit, 1);
  assert.equal(existsSync(path.join(empty, 'i-core.sqlite')), false);
});

test('crash after schema5 listener creates real missing-close evidence and refuses automatic original-path restart', async t => {
  const lab = await createLab(t);
  const run = lab.launch(); const ready = await run.ready();
  const crash = spawnSync(ps, ['-NoProfile', '-NonInteractive', '-File',
    fileURLToPath(new URL('../../test_fixtures/runtime_upgrade/r3/crash_owned_child.ps1', import.meta.url)),
    '-ChildId', String(ready.pid), '-ExpectedExecutable', path.join(lab.release, 'runtime/node.exe')],
  { env: cleanEnvironment(), windowsHide: true, encoding: 'utf8', timeout: 10000 });
  assert.equal(crash.status, 0, crash.stderr);
  const result = await run.wait(); assert.equal(result.exit, 1);
  assert.equal(result.receipt.result.child_exit_code, 137); assert.equal(result.receipt.result.job_empty_confirmed, true);
  assert.equal(result.child, null); assert.equal(run.confirmed, true);
  assert.equal(JSON.parse(readFileSync(path.join(lab.state, 'r3-lifecycle.json'))).phase, 'listening');
  await assert.rejects(fetch(`http://127.0.0.1:${ready.address.port}/v1/core/health`, { signal: AbortSignal.timeout(1000) }));
  const before = ['','-wal','-shm'].map(s => existsSync(lab.database+s) ? sha256(readFileSync(lab.database+s)) : null);
  const retry = await lab.launch({ migrate: false }).wait(); assert.equal(retry.exit, 1);
  assert.match(retry.child.error_code, /state_sidecars_require_review|prior_shutdown_unconfirmed/);
  assert.equal(retry.child.store_construction_attempted, false);
  assert.deepEqual(['','-wal','-shm'].map(s => existsSync(lab.database+s) ? sha256(readFileSync(lab.database+s)) : null), before);
});

test('accepted migration followed by listen failure closes the same store and supports normal original-path restart', async t => {
  const lab = await createLab(t);
  // Bind immediately after launch.json: the lock owner has completed its early port probe,
  // while its C# compiler has not yet started Node. This is a real late bind race.
  const reserve = net.createServer(); await new Promise(resolve => reserve.listen(0, '127.0.0.1', resolve));
  const port = reserve.address().port; await new Promise(resolve => reserve.close(resolve));
  const run = lab.launch({ port });
  await until(() => run.read('launch.json') || run.closed);
  const conflict = net.createServer(); await new Promise(resolve => conflict.listen(port,'127.0.0.1',resolve));
  try {
    const result = await run.wait(); assert.equal(result.exit, 1);
    assert.equal(result.child.error_code, 'EADDRINUSE'); assert.equal(result.child.store_construction_attempted, true);
    assert.equal(result.child.store_close_confirmed, true); assert.equal(result.child.phase, 'clean_closed');
    assert.equal(lab.inspect(db => db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get().value), '5');
  } finally { await new Promise(resolve => conflict.close(resolve)); }
  const again = lab.launch({ migrate: false }); await again.ready(); await again.stop(); assert.equal((await again.wait()).exit, 0);
});

test('cancel with a live incomplete HTTP request forces actual child exit and keeps shutdown unconfirmed', async t => {
  const lab = await createLab(t), run = lab.launch({ timeout: 4500 }); const ready = await run.ready();
  const socket = net.connect(ready.address.port, '127.0.0.1');
  socket.on('error', () => {}); t.after(() => socket.destroy());
  await new Promise(resolve => socket.once('connect', resolve));
  socket.write('POST /v1/core/devices/pair HTTP/1.1\r\nHost: localhost\r\nContent-Length: 9999\r\n');
  await run.stop('stop');
  const result = await run.wait();
  assert.equal(result.exit, 1); assert.equal(result.receipt.result.reason, 'cancelled');
  assert.equal(result.receipt.result.termination_requested, true); assert.equal(result.receipt.result.job_empty_confirmed, true);
  assert.equal(result.receipt.result.child_exit_confirmed, true); assert.equal(result.child, null);
});

test('R3 Job supervision confirms timeout descendants, parent cancellation and startup failures', async () => {
  const hang = await runSyntheticFixture('descendant-hang', { timeoutMs: 3000 });
  assert.equal(hang.exit_code, 1); assert.equal(hang.reason, 'timeout');
  assert.equal(hang.descendant_fixture_ready, true); assert.ok(hang.total_processes >= 2);
  assert.equal(hang.termination_requested, true); assert.equal(hang.job_empty_confirmed, true); assert.equal(hang.cleanup_confirmed, true);
  const cancel = new AbortController();
  const stopped = await runSyntheticFixture('hang', { timeoutMs: 15000, signal: cancel.signal, onReady: () => cancel.abort() });
  assert.equal(stopped.reason, 'cancelled'); assert.equal(stopped.child_exit_confirmed, true); assert.equal(stopped.job_empty_confirmed, true);
  assert.equal(stopped.cleanup_confirmed, true);
  for (const mode of ['startup-failure', 'supervisor-start-failure']) {
    const result = await runSyntheticFixture(mode); assert.equal(result.exit_code, 1); assert.equal(result.child_started, false);
    assert.equal(result.job_empty_confirmed, true); assert.equal(result.cleanup_confirmed, true);
  }
  for (const value of [null, {}, { token: 'wrong', mode: 'hang', result: { child_exit_confirmed: true, job_empty_confirmed: true } }]) {
    assert.equal(confirmedReceipt(value, 'token', 'hang'), false);
  }
});

test('actual missing/forged Job receipt retains resources despite an independently confirmed exited child', async () => {
  for (const mode of ['missing-receipt', 'forged-receipt']) {
    const result = await runSyntheticFixture(mode);
    assert.equal(result.exit_code, 1); assert.equal(result.reason, 'exit_unconfirmed');
    assert.equal(result.supervisor_exit_confirmed, true); assert.equal(result.job_empty_confirmed, false);
    assert.equal(result.cleanup_confirmed, false);
    const root = result.retained_root;
    plainPath(root); assert.equal(path.dirname(root), realpathSync.native(tmpdir()));
    assert.match(path.basename(root), /^mda2-r3-supervised-/);
    const witness = JSON.parse(readFileSync(path.join(root, 'witness.json')));
    const owner = JSON.parse(readFileSync(path.join(root, 'owner.json')));
    assert.equal(witness.token, owner.token); assert.equal(witness.mode, mode);
    assert.equal(witness.result.job_empty_confirmed, true); assert.equal(witness.result.child_exit_confirmed, true);
    assert.equal(witness.result.child_exit_code_confirmed, true); assert.equal(witness.result.child_exit_code, 0);
    // Only the negative-test owner, after checking the independent handle evidence,
    // removes this intentionally retained fixture. The supervisor reported failure.
    rmSync(root, { recursive: true }); assert.equal(existsSync(root), false);
  }
});
