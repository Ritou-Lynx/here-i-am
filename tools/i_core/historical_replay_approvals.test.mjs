import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { ICoreStore } from './i_core_store.mjs';

const ledgerKey = 'historical_replay_approvals_v1';
const historyId = 'v3-history-0123456789abcdef0123';
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(
    Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  return value;
}
function digest(value) {
  return createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');
}
function message(overrides = {}) {
  return { sync_id: 'historical-one', origin_device_id: 'phone-one', origin_sequence: 72,
    character_id: 'i', sender: 'user', content: 'synthetic content',
    created_at_ms: 1700000000000, message_type: 'chat', asset_refs: [], addenda: [], ...overrides };
}
function fixture(t, { deviceId = 'phone-one', platform = 'android', seed = true } = {}) {
  const directory = mkdtempSync(path.join(tmpdir(), 'historical-replay-test-'));
  const databasePath = path.join(directory, 'core.sqlite');
  const approvalsPath = path.join(directory, 'historical-replay-approvals.json');
  let store = new ICoreStore(databasePath, { companionReplyJobsEnabled: true });
  t.after(() => { store?.close(); rmSync(directory, { recursive: true, force: true }); });
  store.pairDevice({ device_id: deviceId, display_name: 'Synthetic', platform,
    client_version: 'test', capabilities: [] }, 'synthetic-pair-code');
  const incoming = message({ origin_device_id: deviceId });
  const old = message({ origin_device_id: historyId, origin_sequence: 1,
    created_at_ms: incoming.created_at_ms + 987,
    addenda: [{ kind: 'historical_import', source: 'hereiam_v3', source_origin_device_id: deviceId,
      attachment_count_omitted: 0 }] });
  if (seed) store.importMessages(historyId, [old]);
  const approval = { sync_id: incoming.sync_id, device_id: deviceId, origin_sequence: incoming.origin_sequence,
    incoming_digest: digest(incoming), existing_digest: digest(old) };
  return {
    directory, databasePath, approvalsPath, incoming, old, approval,
    get store() { return store; },
    write(records = [approval]) { writeFileSync(approvalsPath, JSON.stringify({ version: 1, approved_replays: records })); },
    reopen() { store?.close(); store = null; store = new ICoreStore(databasePath, { companionReplyJobsEnabled: true }); },
    close() { store?.close(); store = null; },
    submit(messages = [incoming], extra = {}) {
      return store.submitMessages(deviceId, { device_id: deviceId, messages, ...extra });
    },
  };
}
const rejects = (fn, code) => assert.throws(fn, (error) => error.code === code);
function snapshot(store) {
  return {
    messages: store.db.prepare('SELECT * FROM chat_messages ORDER BY sync_id').all(),
    events: store.db.prepare('SELECT * FROM change_events ORDER BY server_sequence').all(),
    jobs: store.db.prepare('SELECT * FROM companion_reply_jobs ORDER BY job_id').all(),
  };
}

test('exact approved historical replay and restart preserve messages, events, and jobs', (t) => {
  const f = fixture(t);
  const before = snapshot(f.store);
  rejects(() => f.submit(), 'immutable_message_conflict');
  f.write(); f.reopen();
  assert.equal(f.submit().results[0].status, 'duplicate');
  assert.deepEqual(snapshot(f.store), before);
  f.reopen();
  assert.equal(f.submit(undefined, { request_companion_reply: false }).results[0].status, 'duplicate');
  assert.deepEqual(snapshot(f.store), before);
});

test('deleted or cropped approval file cannot release durable aliases', (t) => {
  const f = fixture(t); f.write(); f.reopen();
  unlinkSync(f.approvalsPath); f.reopen();
  assert.equal(f.submit().results[0].status, 'duplicate');
  rejects(() => f.submit([message({ sync_id: 'other-id' })]), 'origin_sequence_conflict');
  f.write([]); f.reopen();
  rejects(() => f.submit([message({ sync_id: 'other-id' })]), 'origin_sequence_conflict');
  assert.equal(JSON.parse(f.store.db.prepare('SELECT value FROM core_metadata WHERE key=?').get(ledgerKey).value).approved_replays.length, 1);
});

test('ledger permits append, rejects conflicting updates atomically', (t) => {
  const f = fixture(t); f.write(); f.reopen();
  const second = { ...f.approval, sync_id: 'second', origin_sequence: 73 };
  f.write([second]); f.reopen();
  const original = f.store.db.prepare('SELECT value FROM core_metadata WHERE key=?').get(ledgerKey).value;
  f.write([{ ...second, sync_id: 'third', origin_sequence: 74 },
    { ...f.approval, existing_digest: 'f'.repeat(64) }]);
  rejects(() => f.reopen(), 'historical_replay_approvals_invalid');
  f.write([]); f.reopen();
  assert.equal(f.store.db.prepare('SELECT value FROM core_metadata WHERE key=?').get(ledgerKey).value, original);
});

test('every normalized incoming digest field remains immutable', (t) => {
  const f = fixture(t); f.write(); f.reopen();
  for (const patch of [
    { content: 'changed' }, { character_id: 'other' }, { created_at_ms: 1700000000001 },
    { message_type: 'other' }, { asset_refs: [{ id: 'asset' }] }, { addenda: [{ kind: 'other' }] },
  ]) rejects(() => f.submit([{ ...f.incoming, ...patch }]), 'origin_sequence_conflict');
  rejects(() => f.submit([{ ...f.incoming, origin_sequence: 73 }]), 'immutable_message_conflict');
  rejects(() => f.store.submitMessages('other-phone', { device_id: 'other-phone',
    messages: [{ ...f.incoming, origin_device_id: 'other-phone' }] }), 'immutable_message_conflict');
  rejects(() => f.submit([{ ...f.incoming, sender: 'companion' }]), 'sender_not_allowed');
});

test('existing digest drift or stored content drift remains rejected', (t) => {
  const f = fixture(t); f.write(); f.reopen();
  f.store.db.prepare('UPDATE chat_messages SET canonical_digest=? WHERE sync_id=?').run('f'.repeat(64), f.incoming.sync_id);
  rejects(() => f.submit(), 'immutable_message_conflict');
  f.store.db.prepare('UPDATE chat_messages SET canonical_digest=?, content=? WHERE sync_id=?')
    .run(f.approval.existing_digest, 'changed despite stale digest', f.incoming.sync_id);
  rejects(() => f.submit(), 'immutable_message_conflict');
});

test('frontend and reply-request submissions cannot use the exception', (t) => {
  const f = fixture(t); f.write(); f.reopen();
  rejects(() => f.submit(undefined, { request_companion_reply: true }), 'immutable_message_conflict');
  assert.equal(f.store.db.prepare('SELECT COUNT(*) AS n FROM companion_reply_jobs').get().n, 0);
  const frontend = fixture(t, { deviceId: 'frontend:web', platform: 'external-frontend' });
  frontend.write(); frontend.reopen();
  rejects(() => frontend.submit(), 'immutable_message_conflict');
});

test('approval cannot create a missing historical row', (t) => {
  const f = fixture(t, { seed: false }); f.write(); f.reopen();
  const before = snapshot(f.store);
  rejects(() => f.submit(), 'immutable_message_conflict');
  assert.deepEqual(snapshot(f.store), before);
});

test('nonhistorical or companion existing rows cannot use approved exception', (t) => {
  for (const patch of [{ origin_device_id: 'v3-history-not-a-valid-hash' }, { sender: 'companion' }]) {
    const f = fixture(t, { seed: false });
    const old = { ...f.old, ...patch };
    f.store.importMessages(old.origin_device_id, [old]);
    f.write([{ ...f.approval, existing_digest: digest(old) }]); f.reopen();
    rejects(() => f.submit(), 'immutable_message_conflict');
  }
});

test('SQL sequence occupancy is checked before approved or strict duplicates', (t) => {
  const f = fixture(t);
  f.submit([message({ sync_id: 'occupying-row' })]);
  f.write(); f.reopen();
  rejects(() => f.submit(), 'origin_sequence_conflict');
  // Ordinary exact replay still succeeds at its own SQL position.
  const normal = message({ sync_id: 'normal', origin_sequence: 80 });
  assert.equal(f.submit([normal]).results[0].status, 'accepted');
  assert.equal(f.submit([normal]).results[0].status, 'duplicate');
});

test('mixed batch conflict rolls back earlier inserts and job writes', (t) => {
  const f = fixture(t); f.write(); f.reopen();
  const before = snapshot(f.store);
  rejects(() => f.submit([message({ sync_id: 'new-valid', origin_sequence: 2 }),
    message({ sync_id: 'alias-conflict' })]), 'origin_sequence_conflict');
  assert.deepEqual(snapshot(f.store), before);
  rejects(() => f.submit([message({ sync_id: 'new-job', origin_sequence: 2 }),
    message({ sync_id: 'alias-conflict' })], { request_companion_reply: true }), 'origin_sequence_conflict');
  assert.deepEqual(snapshot(f.store), before);
});

test('local imports cannot consume aliases, including duplicate early returns', (t) => {
  const f = fixture(t); f.write(); f.reopen();
  const before = snapshot(f.store);
  rejects(() => f.store.importMessages('phone-one', [f.incoming]), 'origin_sequence_conflict');
  rejects(() => f.store.importMessages('phone-one', [message({ sync_id: 'new-alias' })]), 'origin_sequence_conflict');
  assert.equal(f.store.importMessages(historyId, [f.old]).results[0].status, 'duplicate');
  assert.deepEqual(snapshot(f.store), before);
});

test('invalid files fail before database creation or initialization writes', (t) => {
  const f = fixture(t); f.close();
  const before = readFileSync(f.databasePath);
  const valid = f.approval;
  const invalidDocuments = [
    '{', JSON.stringify({ version: 2, approved_replays: [] }),
    JSON.stringify({ version: 1, approved_replays: [valid, valid] }),
    JSON.stringify({ version: 1, approved_replays: [valid, { ...valid, sync_id: 'other' }] }),
    JSON.stringify({ version: 1, approved_replays: [{ ...valid, incoming_digest: 'bad' }] }),
    JSON.stringify({ version: 1, approved_replays: [{ ...valid, origin_sequence: -1 }] }),
    JSON.stringify({ version: 1, approved_replays: [{ ...valid, extra: true }] }),
    JSON.stringify({ version: 1, approved_replays: Array.from({ length: 1001 }, (_, i) =>
      ({ ...valid, sync_id: 'id-' + i, origin_sequence: i })) }),
    ' '.repeat(512 * 1024 + 1),
    Buffer.from([0xff, 0xfe]),
  ];
  for (const invalid of invalidDocuments) {
    writeFileSync(f.approvalsPath, invalid);
    rejects(() => new ICoreStore(f.databasePath), 'historical_replay_approvals_invalid');
    assert.deepEqual(readFileSync(f.databasePath), before);
    const fresh = path.join(f.directory, 'fresh.sqlite');
    rejects(() => new ICoreStore(fresh), 'historical_replay_approvals_invalid');
    assert.equal(existsSync(fresh), false);
  }
});

test('junction approval path is rejected without opening target DB', (t) => {
  const f = fixture(t); f.write(); f.close();
  const link = path.join(f.directory, 'linked');
  symlinkSync(f.directory, link, 'junction');
  rejects(() => new ICoreStore(path.join(f.directory, 'fresh.sqlite'), {
    historicalReplayApprovalsPath: path.join(link, 'historical-replay-approvals.json'),
  }), 'historical_replay_approvals_invalid');
  assert.equal(existsSync(path.join(f.directory, 'fresh.sqlite')), false);
});

test('no approval file preserves normal strict digest behavior and creates no ledger', (t) => {
  const f = fixture(t);
  assert.equal(f.store.db.prepare('SELECT value FROM core_metadata WHERE key=?').get(ledgerKey), undefined);
  const normal = message({ sync_id: 'ordinary', origin_sequence: 10 });
  assert.equal(f.submit([normal]).results[0].status, 'accepted');
  assert.equal(f.submit([normal]).results[0].status, 'duplicate');
  rejects(() => f.submit([{ ...normal, content: 'changed' }]), 'immutable_message_conflict');
  rejects(() => f.submit(), 'immutable_message_conflict');
});


test('worker publication cannot consume an approved device sequence', (t) => {
  const f = fixture(t); f.write(); f.reopen();
  const lease = f.store.acquireWorkerLease({ workload: 'companion_reply', holder_id: 'phone-one' });
  const before = snapshot(f.store);
  rejects(() => f.store.publishCompanionMessages({ ...lease,
    messages: [message({ sync_id: 'worker-collision', sender: 'companion' })],
  }), 'origin_sequence_conflict');
  assert.deepEqual(snapshot(f.store), before);
});

test('an already-running store observes aliases appended by another store', (t) => {
  const f = fixture(t);
  f.write();
  const second = new ICoreStore(f.databasePath);
  second.close();
  rejects(() => f.submit([message({ sync_id: 'other' })]), 'origin_sequence_conflict');
  assert.equal(f.submit().results[0].status, 'duplicate');
});

test('explicit approval path supports UTF-8 BOM without accepting mutable bindings', (t) => {
  const f = fixture(t); f.close();
  const custom = path.join(f.directory, 'custom-approvals.json');
  writeFileSync(custom, '\ufeff' + JSON.stringify({ version: 1, approved_replays: [f.approval] }));
  const store = new ICoreStore(f.databasePath, { historicalReplayApprovalsPath: custom });
  assert.equal(store.submitMessages('phone-one', { device_id: 'phone-one', messages: [f.incoming] })
    .results[0].status, 'duplicate');
  store.close();
});

test('reserved internal identities cannot use approved replay', (t) => {
  for (const platform of ['local-import', 'core-worker', 'core-authority']) {
    const f = fixture(t, { platform }); f.write(); f.reopen();
    rejects(() => f.submit(), 'immutable_message_conflict');
  }
});

test('malformed durable ledger blocks opening and cannot silently release aliases', (t) => {
  const f = fixture(t); f.write(); f.reopen();
  f.store.db.prepare('UPDATE core_metadata SET value=? WHERE key=?').run('{', ledgerKey);
  f.close();
  unlinkSync(f.approvalsPath);
  const before = readFileSync(f.databasePath);
  rejects(() => new ICoreStore(f.databasePath), 'historical_replay_approvals_invalid');
  assert.deepEqual(readFileSync(f.databasePath), before);
});
