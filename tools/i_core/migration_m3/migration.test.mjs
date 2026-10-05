import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { DatabaseSync } from 'node:sqlite';
import test, { after } from 'node:test';
import { fileURLToPath } from 'node:url';
import { ActivityControlPlane } from '../activity_control_plane.mjs';
import { ICoreStore, activityDatabaseBindingDigest } from '../i_core_store.mjs';
import {
  capture, classify, cleanEnv, createLab, describe, fingerprints, inspect, logicalView,
  preservedOldRows, runV4Guard, sha, verifyLegacyEntry,
} from '../test_fixtures/migration_m3/lab.mjs';

const evidence = [];
// Evidence belongs to this test process; recursive runners must not overwrite it.
const output = mkdtempSync(path.join(tmpdir(), 'i-core-m3-matrix-'));
after(() => {
  writeFileSync(path.join(output, 'matrix.json'), JSON.stringify({
    format: 'm3-synthetic-migration-evidence-v1', node_version: process.version,
    node_sha256: sha(readFileSync(process.execPath)), platform: process.platform,
    cases: evidence, boundary: 'Synthetic owned files and process termination only; no power-loss, disk-corruption recovery, deployment, or takeover validation.',
  }, null, 2) + '\n');
});
function record(name, lab, detail) {
  evidence.push({ name, passed: true, fixture_source: 'public_synthetic_schema4', fixture_source_sha256: lab.fixture_source_sha256,
    before: describe(lab.baseline), ...detail });
}
const options = { clock: () => 1000000, activityEnabled: true, activityRuntimeId: 'm3-main', activityRuntimeLeaseMs: 1000 };
function assertV5(lab, view) {
  assert.equal(view.metadata.schema_version, '5');
  assert.equal(view.metadata.activity_schema_version, '5');
  assert.equal(view.activity.ready, true);
  assert.deepEqual(preservedOldRows(view), preservedOldRows(lab.baseline));
  assert.equal(view.rows.activity_schema_migrations.length, 1);
  assert.equal(view.rows.activity_schema_migrations[0].version, 5);
  assert.equal(view.rows.activity_schema_migrations[0].state, 'committed');
  assert.equal(runV4Guard(lab.filename).passed, false);
}
async function until(predicate, ms = 5000) {
  const start = performance.now();
  while (!predicate()) {
    if (performance.now() - start > ms) throw new Error('owned_child_wait_timeout');
    await new Promise(resolve => setTimeout(resolve, 10));
  }
}
async function interrupt(lab, stage, chain = 'store') {
  const child = spawn(process.execPath, [fileURLToPath(new URL('../test_fixtures/migration_m3/interrupt_child.mjs', import.meta.url)), lab.filename, stage, chain], {
    env: cleanEnv(), windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stdout = '', stderr = '', closed = false, exitCode, exitSignal, spawnError;
  child.stdout.on('data', chunk => { stdout += chunk; });
  child.stderr.on('data', chunk => { stderr += chunk; });
  child.once('error', error => { spawnError = error; });
  child.once('close', (code, signal) => { closed = true; exitCode = code; exitSignal = signal; });
  const started = performance.now();
  let killRequested = false;
  try {
    await until(() => stdout.includes('\n') || closed || spawnError);
    if (spawnError) throw spawnError;
    assert.equal(closed, false, stderr);
    const barrier = JSON.parse(stdout.trim());
    assert.equal(barrier.pid, child.pid);
    assert.equal(barrier.barrier, stage);
    assert.equal(barrier.chain, chain);
    let whileBlocked, blockedError = null;
    try { whileBlocked = inspect(lab.filename); }
    catch (error) {
      // Windows byte-range locks can deny a full capture while the writer lives.
      // Never replace the missing view with main-file-only or stale evidence.
      assert.equal(error.code, 'EBUSY'); blockedError = error.code;
    }
    // ChildProcess.kill targets this spawn's libuv process handle on Windows;
    // never find a PID by process name or use taskkill. Child has no descendants.
    killRequested = child.kill('SIGKILL');
    assert.equal(killRequested, true);
    await until(() => closed);
    assert.notEqual(exitCode, 0);
    assert.notEqual(exitCode, 92, 'self-budget expiry is not the requested termination');
    const afterExit = inspect(lab.filename);
    return { whileBlocked, blockedError, afterExit, process: { barrier, owned_handle: true, kill_requested: killRequested,
      close_observed: closed, exit_code: exitCode, exit_signal: exitSignal,
      elapsed_ms: Math.round(performance.now() - started), descendants_created: 0, listeners_created: 0 } };
  } finally {
    if (!closed) {
      if (!killRequested) child.kill('SIGKILL');
      await until(() => closed, 15000); // independent 12s child budget remains in force
    }
  }
}

for (const [key, value, errorCode] of [
  ['node_id', '', 'core_metadata_invariant_failed'],
  ['schema_version', '99', 'unsupported_core_schema_version'],
]) test(`constructor preflight rejects ${key} before any migration hook`, async t => {
  const lab = await createLab(t);
  const db = new DatabaseSync(lab.filename);
  db.prepare('UPDATE core_metadata SET value=? WHERE key=?').run(value, key); db.close();
  const before = fingerprints(capture(lab.filename));
  assert.equal(runV4Guard(lab.filename).passed, false);
  assert.deepEqual(fingerprints(capture(lab.filename)), before, 'outer guard is byte preserving');
  const logicalBefore = logicalView(inspect(lab.filename));
  let calls = 0;
  assert.throws(() => new ICoreStore(lab.filename, { ...options, testOnlyActivityMigrationHook: () => { calls++; } }), { code: errorCode });
  assert.equal(calls, 0);
  const after = inspect(lab.filename);
  assert.deepEqual(after.files[0], before[0], 'main bytes unchanged');
  assert.deepEqual(logicalView(after), logicalBefore);
  assert.equal(classify(lab.filename, lab.baseline).state, 'indeterminate');
  record(`preflight-${key}`, lab, { error_code: errorCode, hook_calls: calls, outer_guard_files_unchanged: true,
    main_bytes_unchanged: true, logical_view_unchanged: true, before_constructor_files: before, after_constructor_files: after.files,
    classification: 'indeterminate', note: 'Existing readOnly preflight can synthesize empty WAL/SHM; no zero-byte-mutation claim.' });
});

for (const stage of ['after_ddl', 'before_commit']) test(`formal Store constructor throw at ${stage} rolls back`, async t => {
  const lab = await createLab(t), reached = [];
  assert.throws(() => new ICoreStore(lab.filename, { ...options, testOnlyActivityMigrationHook: actual => {
    reached.push(actual); if (actual === stage) throw new Error('m3-synthetic-throw');
  } }), /m3-synthetic-throw/);
  const view = inspect(lab.filename);
  assert.deepEqual(logicalView(view), logicalView(lab.baseline));
  record(`throw-${stage}`, lab, { reached, classification: classify(lab.filename, lab.baseline).state,
    after: describe(view), legacy_entry: verifyLegacyEntry(lab), process_interruption: false });
});

test('ControlPlane callback stages observe actual uncommitted DDL, metadata and committed transaction', async t => {
  const lab = await createLab(t), reached = [];
  const db = new DatabaseSync(lab.filename);
  try {
    new ActivityControlPlane(db, { nodeId: lab.baseline.metadata.node_id, cursorSecret: lab.baseline.metadata.cursor_secret,
      databaseBindingDigest: activityDatabaseBindingDigest(lab.filename), active: false, clock: () => 1000000,
      testOnlyMigrationHook: stage => {
        const coreVersion = db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get().value;
        const ledger = db.prepare('SELECT * FROM activity_schema_migrations').all();
        const inTransaction = db.isTransaction;
        assert.equal(inTransaction, stage !== 'after_commit');
        assert.equal(coreVersion, stage === 'after_ddl' ? '4' : '5');
        assert.equal(ledger.length, stage === 'after_ddl' ? 0 : 1);
        reached.push({ stage, in_transaction: inTransaction, core_version: coreVersion, ledger_count: ledger.length });
      } });
  } finally { db.close(); }
  assert.deepEqual(reached.map(row => row.stage), ['after_ddl', 'before_commit', 'after_commit']);
  assertV5(lab, inspect(lab.filename));
  record('actual-stage-observation', lab, { reached, after: describe(inspect(lab.filename)), old_constructor_called: false });
});

test('throw after COMMIT stays v5 without attempting ROLLBACK or activation', async t => {
  const lab = await createLab(t);
  assert.throws(() => new ICoreStore(lab.filename, { ...options, testOnlyActivityMigrationHook: stage => {
    if (stage === 'after_commit') throw new Error('m3-post-commit-throw');
  } }), /m3-post-commit-throw/);
  const view = inspect(lab.filename); assertV5(lab, view);
  assert.equal(view.rows.activity_runtime_claim[0].runtime_id, '');
  assert.equal(view.rows.activity_runtime_claim[0].runtime_fence, 0);
  record('throw-after-commit', lab, { after: describe(view), classification: 'committed_v5', old_constructor_called: false,
    runtime_restart_authorized: false, reason: 'no_existing_clean_close_receipt', process_interruption: false });
});

for (const [chain, stage] of [['store', 'after_ddl'], ['store', 'before_commit'], ['store', 'after_commit'],
  ['control-delete', 'before_commit'], ['control-delete', 'after_commit']]) {
  test(`actual owned child interruption: ${chain}/${stage}`, async t => {
    const lab = await createLab(t);
    const result = await interrupt(lab, stage, chain);
    const classification = classify(lab.filename, lab.baseline);
    const committed = stage === 'after_commit';
    assert.equal(classification.state, committed ? 'committed_v5' : 'uncommitted_v4_verified');
    if (committed) {
      assertV5(lab, result.afterExit);
      assert.equal(result.afterExit.rows.activity_runtime_claim[0].runtime_id, '');
      assert.equal(result.afterExit.rows.activity_runtime_claim[0].runtime_fence, 0);
    } else {
      if (result.whileBlocked) assert.deepEqual(logicalView(result.whileBlocked), logicalView(lab.baseline));
      assert.deepEqual(logicalView(result.afterExit), logicalView(lab.baseline));
    }
    if (chain === 'store') assert.ok(result.afterExit.files.find(row => row.suffix === '-wal').exists);
    if (chain === 'control-delete' && !committed) assert.ok(result.afterExit.files.find(row => row.suffix === '-journal').bytes > 512);
    record(`kill-${chain}-${stage}`, lab, {
      process: result.process, while_blocked: result.whileBlocked ? describe(result.whileBlocked)
        : { classification: 'indeterminate', error_code: result.blockedError, action: 'wait_for_owned_child_exit' }, after: describe(result.afterExit),
      classification: classification.state, allowed_action: classification.action,
      legacy_entry: committed ? { old_constructor_called: false } : verifyLegacyEntry(lab),
      runtime_restart_authorized: false, reason: committed ? 'no_existing_clean_close_receipt' : 'runtime_package_revalidation_still_required',
    });
  });
}

test('actual child death after active claim refuses busy and expired takeover', async t => {
  const lab = await createLab(t);
  const result = await interrupt(lab, 'after_claim');
  assertV5(lab, result.afterExit);
  assert.equal(result.afterExit.rows.activity_runtime_claim[0].runtime_id, 'm3-owned-child');
  const failures = [];
  for (const [now, code] of [[1000000, 'activity_authority_busy'], [1002000, 'activity_recovery_required']]) {
    assert.throws(() => new ICoreStore(lab.filename, { ...options, clock: () => now }), { code });
    failures.push(code);
    assert.deepEqual(logicalView(inspect(lab.filename)), logicalView(result.afterExit));
  }
  record('kill-after-claim', lab, { process: result.process, after: describe(result.afterExit), rejected_restarts: failures,
    claim_unchanged: true, old_constructor_called: false, runtime_restart_authorized: false });
});

test('observed clean close permits normal same-canonical-path Core restart', async t => {
  const lab = await createLab(t), reached = [];
  const first = new ICoreStore(lab.filename, { ...options, testOnlyActivityMigrationHook: stage => reached.push(stage) });
  assert.equal(first.activity.runtimeFence, 1); first.close();
  const clean = inspect(lab.filename); assertV5(lab, clean);
  assert.equal(clean.rows.activity_runtime_claim[0].runtime_id, '');
  assert.equal(clean.rows.activity_runtime_claim[0].lease_expires_at_ms, 0);
  const second = new ICoreStore(lab.filename, { ...options, activityRuntimeId: 'm3-restart',
    testOnlyActivityMigrationHook: () => { throw new Error('should not remigrate'); } });
  try { assert.equal(second.activity.runtimeFence, 2); assert.equal(second.health().ok, true); }
  finally { second.close(); }
  const final = inspect(lab.filename); assertV5(lab, final);
  assert.equal(final.rows.activity_runtime_claim[0].runtime_fence, 2);
  record('clean-same-path-restart', lab, { reached, clean: describe(clean), after: describe(final),
    actual_clean_close: true, core_same_path_restart: true, runtime_package_receipt_created: false, old_constructor_called: false });
});

test('damaged ledger is indeterminate and neither entry is permitted', async t => {
  const lab = await createLab(t);
  const store = new ICoreStore(lab.filename); store.close();
  const db = new DatabaseSync(lab.filename); db.exec('DELETE FROM activity_schema_migrations'); db.close();
  const before = fingerprints(capture(lab.filename));
  assert.deepEqual(classify(lab.filename, lab.baseline), { state: 'indeterminate', action: 'refuse_both_entries_preserve_full_view' });
  assert.equal(runV4Guard(lab.filename).passed, false);
  assert.deepEqual(fingerprints(capture(lab.filename)), before);
  record('ledger-unknown', lab, { after: describe(inspect(lab.filename)), classification: 'indeterminate', files_unchanged: true,
    old_constructor_called: false, runtime_restart_authorized: false });
});

test('orphan sidecar without main is indeterminate and preserved', async t => {
  const lab = await createLab(t), missing = path.join(lab.root, 'missing.sqlite');
  writeFileSync(missing + '-wal', 'synthetic orphan sidecar');
  const before = fingerprints(capture(missing));
  assert.equal(classify(missing, lab.baseline).state, 'indeterminate');
  assert.deepEqual(fingerprints(capture(missing)), before);
  record('orphan-sidecar', lab, { classification: 'indeterminate', files_unchanged: true, old_constructor_called: false });
});
