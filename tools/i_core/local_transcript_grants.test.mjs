import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { ICoreStore, CORE_LEGACY_CHAT_SCHEMA_VERSION } from './i_core_store.mjs';
import { createICoreServer } from './i_core_server.mjs';

const cutoff = 1700000000000;
const hash = (text) => createHash('sha256').update(text).digest('hex');
const document = (grants) => ({ version: 1, grants });
const message = (patch = {}) => ({
  sync_id: 'synthetic-reply', origin_device_id: 'phone-one', origin_sequence: 1,
  character_id: 'i', sender: 'companion', content: 'Synthetic local reply',
  created_at_ms: cutoff, message_type: 'chat', asset_refs: [], addenda: [], ...patch,
});
function pair(store, deviceId = 'phone-one', platform = 'android', code = 'synthetic-first-code') {
  return store.pairDevice({ device_id: deviceId, display_name: 'Synthetic device',
    platform, client_version: 'test', capabilities: [] }, code).device_token;
}
function grantFor(token, patch = {}) {
  return { device_id: 'phone-one', character_id: 'i', credential_sha256: hash(token),
    from_created_at_ms: cutoff, ...patch };
}
function fixture(t, { platform = 'android', authorized = true } = {}) {
  const directory = mkdtempSync(path.join(tmpdir(), 'local-transcript-test-'));
  const databasePath = path.join(directory, 'core.sqlite');
  const grantsPath = path.join(directory, 'local-transcript-grants.json');
  let store = new ICoreStore(databasePath, { companionReplyJobsEnabled: false, companionUploadMode: 'legacy_b3' });
  const token = pair(store, 'phone-one', platform);
  const grant = grantFor(token);
  if (authorized) {
    writeFileSync(grantsPath, JSON.stringify(document([grant])));
    store.close();
    store = new ICoreStore(databasePath, { companionReplyJobsEnabled: false, companionUploadMode: 'legacy_b3' });
  }
  t.after(() => { store?.close(); rmSync(directory, { recursive: true, force: true }); });
  return {
    directory, databasePath, grantsPath, token, grant,
    get store() { return store; },
    write(grants) { writeFileSync(grantsPath, JSON.stringify(document(grants))); },
    reopen(options = {}) {
      store?.close(); store = null;
      store = new ICoreStore(databasePath, { companionReplyJobsEnabled: false, companionUploadMode: 'legacy_b3', ...options });
    },
    close() { store?.close(); store = null; },
    submit(messages = [message()], extra = {}, deviceToken = token) {
      return store.submitLocalTranscripts(deviceToken, { device_id: 'phone-one', messages, ...extra });
    },
  };
}
const rejects = (fn, code) => assert.throws(fn, (error) => error.code === code);
const snapshot = (store) => ({
  messages: store.db.prepare('SELECT * FROM chat_messages ORDER BY sync_id').all(),
  events: store.db.prepare('SELECT * FROM change_events ORDER BY server_sequence').all(),
  jobs: store.db.prepare('SELECT * FROM companion_reply_jobs ORDER BY job_id').all(),
});

test('missing or empty configuration is disabled and creates no grant file or metadata', (t) => {
  const f = fixture(t, { authorized: false });
  assert.deepEqual(f.store.localTranscriptCapabilities(f.token), { enabled: false, companion_upload_mode: 'legacy_b3' });
  assert.equal(existsSync(f.grantsPath), false);
  rejects(() => f.submit(), 'local_transcript_forbidden');
  assert.equal(f.store.db.prepare("SELECT count(*) AS n FROM core_metadata WHERE key LIKE '%transcript%'").get().n, 0);
  f.write([]); f.reopen();
  assert.deepEqual(f.store.localTranscriptCapabilities(f.token), { enabled: false, companion_upload_mode: 'legacy_b3' });
});

test('exact grant preserves both senders and cutoff boundary without jobs or schema changes', (t) => {
  const f = fixture(t);
  assert.deepEqual(f.store.localTranscriptCapabilities(f.token), {
    enabled: true, companion_upload_mode: 'legacy_b3', character_id: 'i', from_created_at_ms: cutoff,
  });
  const first = message({ sync_id: 'synthetic-user', origin_sequence: 0, sender: 'user' });
  assert.deepEqual(f.submit([message(), first]).results.map((r) => r.status), ['accepted', 'accepted']);
  const rows = f.store.db.prepare('SELECT sender, origin_device_id FROM chat_messages ORDER BY server_sequence').all();
  assert.deepEqual(rows.map((r) => r.sender), ['user', 'companion']);
  assert.ok(rows.every((r) => r.origin_device_id === 'phone-one'));
  assert.equal(snapshot(f.store).jobs.length, 0);
  assert.equal(f.store.db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get().value,
    String(CORE_LEGACY_CHAT_SCHEMA_VERSION));
  assert.deepEqual(f.store.db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%transcript%'").all(), []);
});

test('scope rejects wrong origin, role, character, time, type, assets, addenda and reply flags atomically', (t) => {
  const f = fixture(t);
  const before = snapshot(f.store);
  for (const [patch, code] of [
    [{ origin_device_id: 'other-phone' }, 'origin_device_mismatch'],
    [{ origin_device_id: 'frontend:claude_web' }, 'origin_device_mismatch'],
    [{ sender: 'system' }, 'sender_not_allowed'],
    [{ character_id: 'private-other-character' }, 'local_transcript_scope_mismatch'],
    [{ created_at_ms: cutoff - 1 }, 'local_transcript_scope_mismatch'],
    [{ message_type: 'action' }, 'local_transcript_scope_mismatch'],
    [{ asset_refs: [{ id: 'asset' }] }, 'local_transcript_scope_mismatch'],
    [{ addenda: [{ type: 'historical_import' }] }, 'local_transcript_scope_mismatch'],
  ]) {
    rejects(() => f.submit([message({ sync_id: 'first-valid', origin_sequence: 0 }),
      message(patch)]), code);
    assert.deepEqual(snapshot(f.store), before);
  }
  for (const flag of [true, null, 'false', 0]) {
    rejects(() => f.submit(undefined, { request_companion_reply: flag }), 'invalid_request');
  }
  rejects(() => f.submit(undefined, { device_id: 'other-phone' }), 'device_mismatch');
  rejects(() => f.submit(undefined, { allow_companion: true }), 'invalid_request');
  rejects(() => f.submit([]), 'invalid_request');
  rejects(() => f.submit(Array.from({ length: 101 }, () => message())), 'invalid_request');
  assert.deepEqual(snapshot(f.store), before);
});

test('replay is strictly idempotent after restart and conflict batches roll back', (t) => {
  const f = fixture(t);
  const accepted = f.submit().results[0];
  const before = snapshot(f.store);
  f.reopen();
  assert.deepEqual(f.submit(undefined, { request_companion_reply: false }).results[0],
    { ...accepted, status: 'duplicate' });
  for (const patch of [{ content: 'Changed' }, { sender: 'user' },
    { created_at_ms: cutoff + 1 }, { origin_sequence: 2 }]) {
    rejects(() => f.submit([message({ sync_id: 'earlier-valid', origin_sequence: 0 }),
      message(patch)]), 'immutable_message_conflict');
    assert.deepEqual(snapshot(f.store), before);
  }
  rejects(() => f.submit([message({ sync_id: 'different-id' })]), 'origin_sequence_conflict');
  assert.deepEqual(snapshot(f.store), before);
});

test('an Android grant cannot be used by another paired device or non-Android platform', (t) => {
  const f = fixture(t);
  const other = pair(f.store, 'phone-two', 'android', 'synthetic-other-code');
  assert.deepEqual(f.store.localTranscriptCapabilities(other), { enabled: false, companion_upload_mode: 'legacy_b3' });
  rejects(() => f.submit(undefined, {}, other), 'local_transcript_forbidden');
  rejects(() => f.store.localTranscriptCapabilities('not-a-token'), 'unauthorized');
  for (const platform of ['ios', 'windows', 'local-import', 'core-worker', 'core-authority']) {
    const blocked = fixture(t, { platform });
    assert.deepEqual(blocked.store.localTranscriptCapabilities(blocked.token), { enabled: false, companion_upload_mode: 'legacy_b3' });
    rejects(() => blocked.submit(), 'local_transcript_forbidden');
  }
  const frontend = pair(f.store, 'frontend:web', 'external-frontend', 'synthetic-frontend-code');
  assert.deepEqual(f.store.localTranscriptCapabilities(frontend), { enabled: false, companion_upload_mode: 'legacy_b3' });
  rejects(() => f.submit(undefined, {}, frontend), 'local_transcript_forbidden');
});

test('re-pairing invalidates old token and does not transfer its grant to a new token', (t) => {
  const f = fixture(t);
  const newToken = pair(f.store, 'phone-one', 'android', 'synthetic-rotation-code');
  rejects(() => f.store.localTranscriptCapabilities(f.token), 'unauthorized');
  rejects(() => f.submit(), 'unauthorized');
  assert.deepEqual(f.store.localTranscriptCapabilities(newToken), { enabled: false, companion_upload_mode: 'legacy_b3' });
  rejects(() => f.submit(undefined, {}, newToken), 'local_transcript_forbidden');
  f.reopen();
  assert.deepEqual(f.store.localTranscriptCapabilities(newToken), { enabled: false, companion_upload_mode: 'legacy_b3' });
});

test('grant snapshot is immutable for the run and file revocation takes effect on restart', (t) => {
  const f = fixture(t);
  f.write([]);
  assert.equal(f.store.localTranscriptCapabilities(f.token).enabled, true);
  f.reopen();
  assert.deepEqual(f.store.localTranscriptCapabilities(f.token), { enabled: false, companion_upload_mode: 'legacy_b3' });
  f.write([f.grant]); f.reopen();
  assert.equal(f.store.localTranscriptCapabilities(f.token).enabled, true);
  unlinkSync(f.grantsPath); f.reopen();
  assert.deepEqual(f.store.localTranscriptCapabilities(f.token), { enabled: false, companion_upload_mode: 'legacy_b3' });
});

test('injected synthetic grants are parsed and detached from mutable input', (t) => {
  const f = fixture(t, { authorized: false });
  const config = document([f.grant]);
  f.reopen({ localTranscriptGrants: config });
  config.grants[0].character_id = 'other';
  config.grants.length = 0;
  assert.deepEqual(f.store.localTranscriptCapabilities(f.token),
    { enabled: true, companion_upload_mode: 'legacy_b3', character_id: 'i', from_created_at_ms: cutoff });
});

test('malformed grants fail closed before any fresh or existing database initialization', (t) => {
  const f = fixture(t); f.close();
  const before = readFileSync(f.databasePath);
  const g = f.grant;
  const invalid = [
    '{', document([g, g]), { version: 2, grants: [] }, { version: 1, grants: [], extra: true },
    document([{ ...g, extra: true }]), document([{ ...g, device_id: '' }]),
    document([{ ...g, character_id: ' ' }]), document([{ ...g, credential_sha256: 'bad' }]),
    ...[0, -1, 1.5, Number.MAX_SAFE_INTEGER + 1].map((value) => document([{ ...g, from_created_at_ms: value }])),
    ...['frontend:web', 'v3-history-abcd', 'core-companion:i', 'core:i', 'worker:i']
      .map((device_id) => document([{ ...g, device_id }])),
    document(Array.from({ length: 17 }, (_, i) => ({ ...g, device_id: 'phone-' + i }))),
    ' '.repeat(32 * 1024 + 1), Buffer.from([0xff, 0xfe]),
  ];
  for (const value of invalid) {
    writeFileSync(f.grantsPath, typeof value === 'string' || Buffer.isBuffer(value) ? value : JSON.stringify(value));
    rejects(() => new ICoreStore(f.databasePath), 'local_transcript_grants_invalid');
    assert.deepEqual(readFileSync(f.databasePath), before);
    const fresh = path.join(f.directory, 'fresh.sqlite');
    rejects(() => new ICoreStore(fresh), 'local_transcript_grants_invalid');
    assert.equal(existsSync(fresh), false);
  }
});

test('grants reject junction traversal and directories and support UTF-8 BOM', (t) => {
  const f = fixture(t); f.close();
  const link = path.join(f.directory, 'linked');
  symlinkSync(f.directory, link, 'junction');
  rejects(() => new ICoreStore(f.databasePath, {
    localTranscriptGrantsPath: path.join(link, 'local-transcript-grants.json'),
  }), 'local_transcript_grants_invalid');
  rejects(() => new ICoreStore(f.databasePath, {
    localTranscriptGrantsPath: f.directory,
  }), 'local_transcript_grants_invalid');
  writeFileSync(f.grantsPath, '\ufeff' + JSON.stringify(document([f.grant])));
  f.reopen();
  assert.equal(f.store.localTranscriptCapabilities(f.token).enabled, true);
});

test('ordinary chat permission and durable replay aliases are unchanged', (t) => {
  const f = fixture(t);
  rejects(() => f.store.submitMessages('phone-one', {
    device_id: 'phone-one', messages: [message()],
  }), 'sender_not_allowed');
  f.store.db.prepare('INSERT INTO core_metadata(key,value) VALUES (?,?)')
    .run('historical_replay_approvals_v1', JSON.stringify({ version: 1, approved_replays: [{
      sync_id: 'reserved-historical', device_id: 'phone-one', origin_sequence: 1,
      incoming_digest: 'a'.repeat(64), existing_digest: 'b'.repeat(64),
    }] }));
  rejects(() => f.submit(), 'origin_sequence_conflict');
  assert.equal(snapshot(f.store).messages.length, 0);
  assert.equal(f.store.submitMessages('phone-one', {
    device_id: 'phone-one', messages: [message({ sender: 'user', origin_sequence: 2 })],
  }).results[0].status, 'accepted');
});

test('HTTP capabilities and transcript routes require device auth and preserve ordinary-route denial', async (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), 'local-transcript-http-test-'));
  const databasePath = path.join(directory, 'core.sqlite');
  let core = createICoreServer({ databasePath, companionUploadMode: 'legacy_b3' });
  t.after(async () => { await core.close(); rmSync(directory, { recursive: true, force: true }); });
  const token = pair(core.store);
  const other = pair(core.store, 'phone-two', 'android', 'http-other-code');
  writeFileSync(path.join(directory, 'local-transcript-grants.json'), JSON.stringify(document([grantFor(token)])));
  await core.close();
  core = createICoreServer({ databasePath, companionUploadMode: 'legacy_b3' });
  const address = await core.listen({ port: 0 });
  const base = 'http://127.0.0.1:' + address.port + '/v1/core/chat/';
  async function request(route, { auth = token, body, protocol = true } = {}) {
    const response = await fetch(base + route, {
      method: body === undefined ? 'GET' : 'POST',
      headers: { ...(auth ? { authorization: 'Bearer ' + auth } : {}),
        ...(protocol ? { 'x-core-protocol': '0.1' } : {}),
        ...(body === undefined ? {} : { 'content-type': 'application/json' }) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    return { status: response.status, body: await response.json() };
  }
  const cap = await request('transcript-capabilities');
  assert.equal(cap.status, 200);
  assert.deepEqual(cap.body, { enabled: true, companion_upload_mode: 'legacy_b3', character_id: 'i', from_created_at_ms: cutoff });
  assert.deepEqual((await request('transcript-capabilities', { auth: other })).body, { enabled: false, companion_upload_mode: 'legacy_b3' });
  assert.equal((await request('transcript-capabilities', { auth: null })).status, 401);
  assert.equal((await request('transcript-capabilities', { protocol: false })).status, 426);
  const body = { device_id: 'phone-one', messages: [message()] };
  assert.equal((await request('transcripts', { auth: null, body })).status, 401);
  assert.equal((await request('transcripts', { auth: other, body })).status, 403);
  assert.equal((await request('messages', { body })).status, 403);
  const accepted = await request('transcripts', { body });
  assert.equal(accepted.status, 200);
  assert.equal(accepted.body.results[0].status, 'accepted');
  assert.equal((await request('transcripts', { body })).body.results[0].status, 'duplicate');
  assert.equal(snapshot(core.store).jobs.length, 0);
  assert.ok(!JSON.stringify(cap.body).includes(hash(token)));
});

test('the transcript route cannot consume the historical semantic replay exception', (t) => {
  const f = fixture(t);
  const incoming = message({ sender: 'user' });
  const imported = message({
    sender: 'user', origin_device_id: 'v3-history-0123456789abcdef0123',
    origin_sequence: 50, created_at_ms: cutoff + 987,
    addenda: [{ type: 'synthetic_history' }],
  });
  f.store.importMessages(imported.origin_device_id, [imported]);
  const existingDigest = f.store.db.prepare('SELECT canonical_digest FROM chat_messages WHERE sync_id=?')
    .get(incoming.sync_id).canonical_digest;
  const incomingDigest = hash(JSON.stringify(Object.fromEntries(
    Object.keys(incoming).sort().map((key) => [key, incoming[key]]))));
  f.store.db.prepare('INSERT INTO core_metadata(key,value) VALUES (?,?)')
    .run('historical_replay_approvals_v1', JSON.stringify({ version: 1, approved_replays: [{
      sync_id: incoming.sync_id, device_id: incoming.origin_device_id, origin_sequence: incoming.origin_sequence,
      incoming_digest: incomingDigest, existing_digest: existingDigest,
    }] }));
  const before = snapshot(f.store);
  rejects(() => f.submit([incoming]), 'immutable_message_conflict');
  assert.equal(f.store.submitMessages('phone-one', {
    device_id: 'phone-one', messages: [incoming],
  }).results[0].status, 'duplicate');
  assert.deepEqual(snapshot(f.store), before);
});
