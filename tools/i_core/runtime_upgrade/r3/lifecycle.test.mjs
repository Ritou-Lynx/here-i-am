import assert from 'node:assert/strict';
import { copyFileSync, existsSync, mkdirSync, readFileSync, rmdirSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import net from 'node:net';
import path from 'node:path';
import test from 'node:test';
import { createLab, confirmedReceipt } from '../../test_fixtures/runtime_upgrade/r3/lab.mjs';
import { plainPath, sha256, verifyRelease } from './package.mjs';

test('fixed PS entry defaults verify-only and rejects unknown/runtime flags before database mutation', async t => {
  const lab = await createLab(t), before = sha256(readFileSync(lab.database));
  const sentinel = lab.owned('must-not-exist.sqlite');
  const env = { I_CORE_DATABASE: sentinel, I_CORE_ACTIVITY_ADMIN_SECRET: 'inherited-synthetic-owner', I_CORE_COMPANION_REPLY_JOBS: '1',
    I_CORE_SHORTCUT_MAIL_MANUAL_TEST_ENABLED: '1', I_CORE_WORKER_SECRET: 'synthetic-worker', NODE_OPTIONS: '--require=Z:/no-such-script.cjs', NODE_PATH: 'Z:/untrusted' };
  const verify = await lab.launch({ start: false, env }).wait();
  assert.equal(verify.exit, 0, verify.stderr); assert.match(verify.stdout, /verified_only/);
  for (const args of [['-Restore'], ['-MigrateV4'], ['-StateDirectory', lab.state]]) {
    const result = await lab.launch({ start: false, args, env }).wait();
    assert.notEqual(result.exit, 0, result.stderr);
  }
  assert.equal(sha256(readFileSync(lab.database)), before);
  assert.equal(existsSync(sentinel), false); assert.equal(existsSync(path.join(lab.state, 'r3-lifecycle.json')), false);
});

test('explicit migration preserves eight old tables, dormant HTTP and clean original-path restart; lock prevents second instance', async t => {
  const lab = await createLab(t), oldRows = lab.rows();
  const before = sha256(readFileSync(lab.database));
  const refuse = await lab.launch({ migrate: false }).wait();
  assert.equal(refuse.exit, 1); assert.equal(refuse.child.error_code, 'explicit_v4_migration_required');
  assert.equal(refuse.child.store_construction_attempted, false); assert.equal(sha256(readFileSync(lab.database)), before);
  const env = { I_CORE_ACTIVITY_ADMIN_SECRET: 'inherited-synthetic-owner', I_CORE_COMPANION_REPLY_JOBS: '1', I_CORE_PAIRING_CODE: 'synthetic-inherited-pair',
    I_CORE_SHORTCUT_MAIL_MANUAL_TEST_ENABLED: '1', NODE_OPTIONS: '--require=Z:/absent.cjs' };
  const run = lab.launch({ env }); const ready = await run.ready();
  assert.equal(ready.health.schema_version, 5); assert.equal(ready.health.node_id, lab.identity);
  assert.equal(ready.activity_enabled, false); assert.deepEqual(ready.inherited_core_keys, []);
  assert.equal(ready.health.activity.status, 'owner_principal_unconfigured');
  const base = `http://127.0.0.1:${ready.address.port}`;
  const health = await (await fetch(base + '/v1/core/health')).json(); assert.equal(health.schema_version, 5);
  const chat = await fetch(base + '/v1/core/changes?limit=20', { headers: { Authorization: `Bearer ${lab.paired.device_token}`, 'x-core-protocol': '0.1' } });
  assert.equal(chat.status, 200); assert.match(await chat.text(), /synthetic R3 migration fixture/);
  const second = await lab.launch({ migrate: false }).wait(); assert.equal(second.exit, 2); assert.match(second.stderr, /runtime_lock_busy/);
  await run.stop(); const stopped = await run.wait();
  assert.equal(stopped.exit, 0, JSON.stringify(stopped)); assert.equal(stopped.child.store_close_confirmed, true);
  assert.equal(stopped.receipt.result.job_empty_confirmed, true); assert.equal(stopped.receipt.result.child_exit_code, 0);
  assert.equal(stopped.receipt.child_receipt_confirmed, true);
  assert.deepEqual(lab.rows(), oldRows);
  await assert.rejects(fetch(base + '/v1/core/health', { signal: AbortSignal.timeout(1000) }));
  const again = lab.launch({ migrate: false }); const ready2 = await again.ready();
  assert.equal(ready2.health.node_id, lab.identity); await again.stop(); assert.equal((await again.wait()).exit, 0);
  assert.deepEqual(lab.rows(), oldRows);
  t.diagnostic(JSON.stringify({ manifest_sha256: lab.packageResult.manifest_sha256, node_sha256: ready.node_sha256,
    child_exit_confirmed: stopped.receipt.result.child_exit_confirmed, job_empty_confirmed: true, original_path_restart: true }));
});

test('fingerprint, inventory and canonical/link path rejections precede store construction', async t => {
  const lab = await createLab(t), before = sha256(readFileSync(lab.database));
  assert.throws(() => plainPath(lab.state + '\\..\\state'), /canonical_absolute/);
  const invalid = await lab.launch({ targetState: 'state' }).wait(); assert.equal(invalid.exit, 2);
  for (const targetState of [lab.release, lab.root]) {
    const shared = await lab.launch({ targetState }).wait(); assert.equal(shared.exit, 2); assert.match(shared.stderr, /paths_must_be_separate/);
  }
  const nested = path.join(lab.release, 'state'); mkdirSync(nested);
  const nesting = await lab.launch({ targetState: nested }).wait(); assert.equal(nesting.exit, 2);
  rmdirSync(nested);
  const link = lab.owned('linked-state'); symlinkSync(lab.state, link, 'junction');
  try { const linked = await lab.launch({ targetState: link }).wait(); assert.equal(linked.exit, 2); assert.match(linked.stderr, /linked_path_rejected/); }
  finally { unlinkSync(link); }
  const manifest = path.join(lab.release, 'manifest.json'), original = readFileSync(manifest);
  writeFileSync(manifest, Buffer.concat([original, Buffer.from('\n')]));
  assert.equal((await lab.launch().wait()).exit, 2); writeFileSync(manifest, original);
  const executable = path.join(lab.release, 'runtime/node.exe'); writeFileSync(executable, 'invalid node');
  assert.equal((await lab.launch().wait()).exit, 2); copyFileSync(process.execPath, executable);
  const source = path.join(lab.release, 'tools/i_core/i_core_store.mjs'); writeFileSync(source, '// altered\n', { flag: 'a' });
  assert.equal((await lab.launch().wait()).exit, 2);
  const replaced = JSON.parse(original), entry = replaced.files.find(f => f.path === 'tools/i_core/i_core_store.mjs');
  entry.sha256 = sha256(readFileSync(source)); entry.bytes = readFileSync(source).length;
  const rehashed = Buffer.from(JSON.stringify(replaced)); writeFileSync(manifest, rehashed);
  const rebased = await lab.launch({ manifestHash: sha256(rehashed) }).wait();
  assert.equal(rebased.exit, 2); assert.match(rebased.stderr, /release_content_mismatch|package_verification_failed/);
  assert.equal(sha256(readFileSync(lab.database)), before); assert.equal(existsSync(path.join(lab.state, 'r3-lifecycle.json')), false);
});

test('occupied loopback rejects before migration; absent or forged receipts cannot prove exit', async t => {
  const lab = await createLab(t), before = sha256(readFileSync(lab.database));
  const occupied = net.createServer(); await new Promise(resolve => occupied.listen(0, '127.0.0.1', resolve));
  try {
    const reject = await lab.launch({ port: occupied.address().port }).wait(); assert.equal(reject.exit, 2);
    assert.equal(sha256(readFileSync(lab.database)), before);
  } finally { await new Promise(resolve => occupied.close(resolve)); }
  const launch = { token: 'a', mode: 'start', manifest_sha256: 'hash' };
  assert.equal(confirmedReceipt(null, launch), false);
  assert.equal(confirmedReceipt({ token: 'wrong', mode: 'start', result: { child_exit_confirmed: true, job_empty_confirmed: true } }, launch), false);
  assert.equal(confirmedReceipt({ ...launch, result: { child_started: true, child_exit_confirmed: true, job_empty_confirmed: true } }, launch), false);
});
