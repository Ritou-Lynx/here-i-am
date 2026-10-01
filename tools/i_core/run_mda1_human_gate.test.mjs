import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, lstatSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { assertAcceptedLineage, assertReaderChangeLineage, createCloseAttemptLedger, createOwnedTemporaryDirectory, finalizeMda1HumanGate, isExactOwnedTemporaryDirectory, rawRequest, removeOwnTempDirectory, runMda1HumanGate } from './run_mda1_human_gate.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const runnerPath = path.join(here, 'run_mda1_human_gate.mjs');
function cleanText(value) {
  assert.doesNotMatch(value, /Bearer |(?:probe|reader)[_-]?token|event_id_prefix|receipt|https?:\/\/|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|\b[A-Za-z]:\\|stack|error\.message/i);
}

test('synthetic three-probe review harness completes locally but awaits human acceptance', async () => {
  const checkpoints = [];
  const report = await runMda1HumanGate({ onCheckpoint(value) { checkpoints.push(value.checkpoint); } });
  assert.equal(report.status, 'passed_awaiting_human_acceptance');
  assert.deepEqual(checkpoints, report.checkpoints);
  assert.deepEqual(report.evidence_boundaries, ['synthetic_loopback_only', 'no_real_device_or_android_gate', 'no_sleep_inference', 'human_acceptance_pending']);
  assert.equal(report.close, 'confirmed'); assert.equal(report.cleanup, 'confirmed');
  assert.deepEqual(report.counts, { probes: 3, reader: 1, accepted_events: 4, duplicate_replays: 4, revoked_replays: 3, access_denials: 12 });
  assert.deepEqual(report.probes, [
    { probe: 'probe_1', pair: 200, write: 'accepted', duplicate: 'duplicate', initial_state: 'active', chat: 403, revoke: 200, revoked_replay: 401 },
    { probe: 'probe_2', pair: 200, write: 'accepted', duplicate: 'duplicate', initial_state: 'locked', chat: 403, revoke: 200, revoked_replay: 401 },
    { probe: 'probe_3', pair: 200, write: 'accepted', duplicate: 'duplicate', initial_state: 'network_only', chat: 403, restart_state: 'unknown', restart_coverage_status: 'core_restart_gap', restart_clock_health: 'unknown', restart_status_reason: 'reachability_only', restart_freshness: true, restart_interpretation: 'fresh_not_concrete', fresh_restore: 'network_only', revoke: 200, revoked_replay: 401 },
  ]);
  cleanText(JSON.stringify(report));
});

test('two reports are deterministic despite transient credentials, databases and ports', async () => {
  assert.deepEqual(await runMda1HumanGate(), await runMda1HumanGate());
});

test('checkpoint callback failure is redacted and still removes only its own temporary database', async () => {
  const report = await runMda1HumanGate({ onCheckpoint() { throw new Error('secret should never appear'); } });
  assert.deepEqual(report, {
    status: 'failed', stage: 'paired', check: 'execution_failed', close: 'confirmed', cleanup: 'confirmed',
    evidence_boundaries: ['synthetic_loopback_only', 'no_real_device_or_android_gate', 'no_sleep_inference', 'human_acceptance_pending'],
  });
  cleanText(JSON.stringify(report));
});

test('CLI refuses a missing human-gate flag before any harness side effect and prints one safe JSON line', () => {
  let result;
  try { execFileSync(process.execPath, [runnerPath], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }); }
  catch (error) { result = error; }
  assert.ok(result); const output = result.stdout.trim();
  assert.deepEqual(JSON.parse(output), { status: 'rejected', stage: 'cli', check: 'human_gate_flag_required', close: 'not_started', cleanup: 'not_started' });
  assert.equal(output.split(/\r?\n/).length, 1); cleanText(output);
});

test('CLI success is one safe line and source has no environment, mail, BLE, device or whiteboard access', () => {
  const output = execFileSync(process.execPath, [runnerPath, '--human-gate'], { encoding: 'utf8' }).trim();
  assert.equal(JSON.parse(output).status, 'passed_awaiting_human_acceptance'); assert.equal(output.split(/\r?\n/).length, 1); cleanText(output);
  const source = readFileSync(runnerPath, 'utf8');
  assert.doesNotMatch(source, /process\.env|shortcut_mail|\bmail\b|\bBLE\b|whiteboard|adb|android\.device/i);
  assert.match(source, /host: '127\.0\.0\.1', port: 0/); assert.match(source, /agent: false/);
  assert.equal(existsSync(runnerPath), true);
});

test('pure finalizer fails closed for close or exact-cleanup failure and preserves a business failure', () => {
  assert.deepEqual(finalizeMda1HumanGate({ stage: 'complete', close: 'failed', cleanup: 'confirmed' }), {
    status: 'failed', stage: 'complete', check: 'teardown_close', close: 'failed', cleanup: 'confirmed',
    evidence_boundaries: ['synthetic_loopback_only', 'no_real_device_or_android_gate', 'no_sleep_inference', 'human_acceptance_pending'],
  });
  assert.deepEqual(finalizeMda1HumanGate({ stage: 'complete', close: 'confirmed', cleanup: 'failed' }), {
    status: 'failed', stage: 'complete', check: 'teardown_cleanup', close: 'confirmed', cleanup: 'failed',
    evidence_boundaries: ['synthetic_loopback_only', 'no_real_device_or_android_gate', 'no_sleep_inference', 'human_acceptance_pending'],
  });
  assert.deepEqual(finalizeMda1HumanGate({ stage: 'paired', failure: 'execution_failed', close: 'failed', cleanup: 'failed' }), {
    status: 'failed', stage: 'paired', check: 'execution_failed', close: 'failed', cleanup: 'failed',
    evidence_boundaries: ['synthetic_loopback_only', 'no_real_device_or_android_gate', 'no_sleep_inference', 'human_acceptance_pending'],
  });
});

test('a failed intermediate close cannot be washed clean by a second no-op close attempt', async () => {
  let calls = 0; const core = { async close() { calls += 1; throw new Error('synthetic close failure'); } };
  const ledger = createCloseAttemptLedger();
  assert.equal(await ledger.close(core), false); assert.equal(await ledger.close(core), false);
  assert.equal(calls, 1); assert.equal(ledger.status(), 'failed');
  assert.equal(finalizeMda1HumanGate({ stage: 'revoked_before_restart', failure: 'teardown_close', close: ledger.status(), cleanup: 'confirmed' }).status, 'failed');
});

test('mkdtemp registers its exact handle before lstat or canonical binding can fail', () => {
  const root = mkdtempSync(path.join(tmpdir(), 'mda1-human-gate-test-root-'));
  let lstatRecord; let canonicalRecord;
  try {
    const create = () => mkdtempSync(path.join(root, 'mda1-human-gate-'));
    assert.throws(() => createOwnedTemporaryDirectory({ parentPath: () => root, create, stat() { throw new Error('synthetic lstat failure'); },
      onCreated(record) { lstatRecord = record; } }));
    assert.equal(lstatRecord.canonical, null); assert.equal(removeOwnTempDirectory(lstatRecord), false);
    rmSync(lstatRecord.lexical, { recursive: true, force: true });
    assert.throws(() => createOwnedTemporaryDirectory({ parentPath: () => root, create, stat: lstatSync,
      canonicalize(value) { if (value === root) return realpathSync(root); throw new Error('synthetic realpath failure'); },
      onCreated(record) { canonicalRecord = record; } }));
    assert.equal(canonicalRecord.canonical, null); assert.equal(removeOwnTempDirectory(canonicalRecord), true);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('exact temporary identity rejects a redirected same-prefix target without touching its sentinel', (t) => {
  const root = mkdtempSync(path.join(tmpdir(), 'mda1-human-gate-test-root-'));
  let linked = false; let owned;
  try {
    owned = mkdtempSync(path.join(root, 'mda1-human-gate-'));
    const other = mkdtempSync(path.join(root, 'mda1-human-gate-'));
    const sentinel = path.join(other, 'sentinel.txt'); writeFileSync(sentinel, 'keep');
    const created = lstatSync(owned);
    const record = { parentCanonical: realpathSync(root), lexical: owned, canonical: realpathSync(owned), createdDev: created.dev, createdIno: created.ino };
    assert.equal(isExactOwnedTemporaryDirectory(record), true);
    assert.equal(isExactOwnedTemporaryDirectory(record, { canonicalize() { return realpathSync(other); }, stat: lstatSync }), false);
    rmSync(owned, { recursive: true, force: false });
    try { symlinkSync(other, owned, 'junction'); linked = true; }
    catch { t.skip('junction creation is unavailable on this platform'); return; }
    assert.equal(isExactOwnedTemporaryDirectory(record), false);
    assert.equal(removeOwnTempDirectory(record), false);
    assert.equal(readFileSync(sentinel, 'utf8'), 'keep');
  } finally {
    if (linked) unlinkSync(owned);
    rmSync(root, { recursive: true, force: true });
  }
});

test('raw loopback request settles once when a bounded response is aborted after exceeding the limit', async () => {
  const server = createServer((_, response) => { response.writeHead(200, { 'content-type': 'application/json' }); response.end(Buffer.alloc(1024 * 1024 + 1, 'x')); });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const address = server.address();
    await assert.rejects(rawRequest(`http://127.0.0.1:${address.port}`, 'GET', '/', 'synthetic-token'), (error) =>
      ['response_limit', 'response_aborted'].includes(error?.check));
  } finally { await new Promise((resolve) => server.close(resolve)); }
});

test('lineage guards reject an event ID with a different prefix even when its sequence suffix matches', () => {
  const expected = [{ device_id: 'synthetic-device-a', probe_id: 'synthetic-probe-a', event_id: 'issued-prefix.1', origin_sequence: 1 }];
  const wrong = { device_id: 'synthetic-device-a', probe_id: 'synthetic-probe-a', event_id: 'other-prefix.1', origin_sequence: 1, server_sequence: 1 };
  assert.throws(() => assertAcceptedLineage([wrong], expected, 'owner'), (error) => error?.check === 'owner_identity');
  assert.throws(() => assertReaderChangeLineage({ contract: 'device.activity.v1', schema_version: 1, has_more: false,
    next_cursor: 'opaque', events: [{ kind: 'activity.event.accepted', server_sequence: 1, payload: wrong }] }, expected, 'reader'),
  (error) => error?.check === 'reader_accepted_lineage');
});
