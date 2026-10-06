import assert from 'node:assert/strict';
import { createHash, randomBytes } from 'node:crypto';
import { mkdtempSync, rmSync, writeFileSync, readFileSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { ICoreStore } from './i_core_store.mjs';
import { activityRecoveryManifestForDatabase, rollbackActivitySchema } from './activity_control_plane.mjs';
import { migrateDomainSchema } from './domain_migrate.mjs';
const NOW = 1800000000000;
const HISTORY = 'v3-history-0123456789abcdef0123';
const KEY = 'historical_replay_approvals_v1';
const hash = text => createHash('sha256').update(text).digest('hex');
const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object'
  ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
const digest = value => hash(JSON.stringify(canonical(value)));
const message = (patch = {}) => ({ sync_id: 'synthetic-turn', origin_device_id: 'phone-one', origin_sequence: 1,
  character_id: 'i', sender: 'companion', content: 'synthetic reply', created_at_ms: NOW - 1000,
  message_type: 'chat', asset_refs: [], addenda: [], ...patch });
function pair(store, id = 'phone-one', platform = 'android') {
 return store.pairDevice({ device_id: id, display_name: 'synthetic', platform, client_version: 'test', capabilities: [] }, 'pair-' + id).device_token;
}
function fixture(t) {
 const directory = mkdtempSync(path.join(tmpdir(), 'transcript-compat-'));
 const databasePath = path.join(directory, 'core.sqlite');
 let store = new ICoreStore(databasePath, { clock: () => NOW });
 t.after(() => { store?.close(); assert.equal(path.dirname(directory), tmpdir()); rmSync(directory, { recursive: true, force: true }); });
 return { directory, databasePath, get store() { return store; },
  close() { store?.close(); store = null; },
  open(options = {}) { this.close(); store = new ICoreStore(databasePath, { clock: () => NOW, ...options }); return store; },
  grants(token) { writeFileSync(path.join(directory, 'local-transcript-grants.json'), JSON.stringify({ version: 1, grants: [{
   device_id: 'phone-one', character_id: 'i', credential_sha256: hash(token), from_created_at_ms: NOW - 2000,
  }] })); },
  migrate() {
   const floor = activityRecoveryManifestForDatabase(store.db, { nodeId: store.nodeId, cursorSecret: store.cursorSecret });
   this.close();
   const db = new DatabaseSync(databasePath); db.exec('PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE'); db.close();
   return migrateDomainSchema(databasePath, { clock: () => NOW, activityRecoveryFloor: floor,
    backupDirectory: path.join(directory, 'backups'), backupKey: randomBytes(32),
    offlineProof: ({ databasePath: candidate }) => ({ databasePath: candidate, allCoreWritersStopped: true, checkedAt: NOW }) });
  },
 };
}
const submit = (store, msg = message()) => store.submitMessages('phone-one', { device_id: 'phone-one', messages: [msg] });
const transcript = (store, token, msg = message()) => store.submitLocalTranscripts(token, { device_id: 'phone-one', messages: [msg] });
const counts = store => ['chat_messages', 'change_events', 'companion_reply_jobs'].map(name => store.db.prepare(`SELECT COUNT(*) AS n FROM ${name}`).get().n);

test('schema 6 mode switches select one companion path and preserve cross-route identity, sequence, and normal callers', t => {
 const f = fixture(t); const token = pair(f.store); pair(f.store, 'frontend:web', 'external-frontend');
 const node = f.store.nodeId; const cursor = f.store.encodeCursor(0);
 f.grants(token); f.migrate(); let store = f.open({ companionUploadMode: 'legacy_b3' });
 assert.deepEqual(store.localTranscriptCapabilities(token), { enabled: true, companion_upload_mode: 'legacy_b3', character_id: 'i', from_created_at_ms: NOW - 2000 });
 assert.throws(() => store.configurePhoneCompanion({ device_id: 'phone-one', character_id: 'i' }), { code: 'companion_upload_mode_conflict' });
 assert.throws(() => submit(store), { code: 'sender_not_allowed' });
 assert.equal(transcript(store, token).results[0].status, 'accepted');
 const user = message({ sync_id: 'synthetic-user', origin_sequence: 2, sender: 'user' });
 assert.equal(submit(store, user).results[0].status, 'accepted');
 assert.equal(transcript(store, token, user).results[0].status, 'duplicate');
 assert.throws(() => transcript(store, token, { ...user, content: 'different' }), { code: 'immutable_message_conflict' });
 store = f.open(); // explicit default is PR10; grant is still required.
 assert.deepEqual(store.localTranscriptCapabilities(token), { enabled: false, companion_upload_mode: 'pr10' });
 assert.throws(() => submit(store), { code: 'sender_not_allowed' });
 store.configurePhoneCompanion({ device_id: 'phone-one', character_id: 'i' });
 assert.equal(submit(store).results[0].status, 'duplicate');
 assert.throws(() => transcript(store, token), { code: 'local_transcript_forbidden' });
 assert.throws(() => submit(store, message({ content: 'changed' })), { code: 'immutable_message_conflict' });
 assert.throws(() => submit(store, message({ origin_sequence: 99 })), { code: 'immutable_message_conflict' });
 assert.throws(() => submit(store, message({ sync_id: 'alias' })), { code: 'origin_sequence_conflict' });
 assert.equal(submit(store, message({ sync_id: 'new-companion', origin_sequence: 3 })).results[0].status, 'accepted');
 store = f.open({ companionUploadMode: 'legacy_b3' }); // persisted PR10 grant cannot open the other path.
 assert.throws(() => submit(store), { code: 'sender_not_allowed' });
 assert.equal(transcript(store, token, message({ sync_id: 'new-companion', origin_sequence: 3 })).results[0].status, 'duplicate');
 const before = counts(store);
 store = f.open({ companionUploadMode: 'disabled' });
 assert.equal(store.localTranscriptCapabilities(token).enabled, false);
 assert.throws(() => transcript(store, token), { code: 'local_transcript_forbidden' });
 assert.throws(() => submit(store), { code: 'sender_not_allowed' });
 assert.equal(submit(store, user).results[0].status, 'duplicate');
 assert.deepEqual(counts(store), before);
 const web = message({ sync_id: 'web-turn', origin_device_id: 'frontend:web' });
 assert.equal(store.submitMessages('frontend:web', { device_id: 'frontend:web', messages: [web] }).results[0].status, 'accepted');
 assert.equal(store.nodeId, node); assert.equal(store.encodeCursor(0), cursor);
 assert.equal(store.authenticate(token).device_id, 'phone-one'); assert.equal(counts(store)[2], 0);
});

test('legacy grant cannot coexist with Core reply production, pending work or another primary character', t => {
 const f = fixture(t); const token = pair(f.store); f.grants(token);
 assert.throws(() => f.open({ companionUploadMode: 'legacy_b3', companionReplyJobsEnabled: true }), { code: 'companion_executor_conflict' });
 f.open(); f.migrate(); const store = f.open();
 assert.throws(() => store.configurePhoneCompanion({ device_id: 'phone-one', character_id: 'other' }), { code: 'local_transcript_grants_invalid' });
 store.configurePhoneCompanion({ device_id: 'phone-one', character_id: 'i' });
 const lease = store.acquireWorkerLease({ workload: 'companion_reply', holder_id: 'synthetic-worker', ttl_ms: 30000 }, NOW);
 f.open({ companionUploadMode: 'legacy_b3' });
 assert.throws(() => f.store.publishCompanionMessages({ ...lease, messages: [message({ origin_device_id: 'synthetic-worker' })] }, NOW + 1), { code: 'companion_publish_shadow_only' });
 assert.throws(() => f.open({ companionUploadMode: 'both' }), { code: 'invalid_companion_upload_mode' });
});

test('72 synthetic immutable bindings survive schema 4 to 5 to 6, restart, same-path restore and external ledger recovery', t => {
 const f = fixture(t); const token = pair(f.store); const node = f.store.nodeId; const cursor = f.store.encodeCursor(0);
 const incoming = Array.from({ length: 72 }, (_, i) => message({ sync_id: `history-${String(i).padStart(3, '0')}`, origin_sequence: 100 + i, sender: 'user', content: `synthetic history ${i}` }));
 const old = incoming.map((item, i) => ({ ...item, origin_device_id: HISTORY, origin_sequence: i + 1, created_at_ms: item.created_at_ms + 987, addenda: [{ kind: 'historical_import' }] }));
 f.store.importMessages(HISTORY, old);
 const document = { version: 1, approved_replays: incoming.map((item, i) => ({ sync_id: item.sync_id, device_id: item.origin_device_id, origin_sequence: item.origin_sequence, incoming_digest: digest(item), existing_digest: digest(old[i]) })) };
 const serialized = JSON.stringify(document); const approvalPath = path.join(f.directory, 'historical-replay-approvals.json');
 f.store.db.prepare('INSERT INTO core_metadata(key,value) VALUES (?,?)').run(KEY, serialized);
 const before = counts(f.store); f.close();
 let db = new DatabaseSync(f.databasePath); rollbackActivitySchema(db); assert.equal(db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get().value, '4'); db.close();
 let store = f.open(); assert.equal(store.health().schema_version, 5);
 assert.equal(store.db.prepare('SELECT value FROM core_metadata WHERE key=?').get(KEY).value, serialized);
 for (const item of incoming) assert.equal(submit(store, item).results[0].status, 'duplicate');
 const migration = f.migrate(); assert.equal(migration.backup.verified, true);
 store = f.open(); assert.equal(store.health().schema_version, 6);
 assert.equal(store.db.prepare('SELECT value FROM core_metadata WHERE key=?').get(KEY).value, serialized);
 assert.deepEqual(counts(store), before); assert.equal(store.nodeId, node); assert.equal(store.encodeCursor(0), cursor);
 f.close(); const snapshot = readFileSync(f.databasePath);
 writeFileSync(approvalPath, serialized); store = f.open();
 assert.equal(submit(store, incoming[71]).results[0].status, 'duplicate');
 assert.throws(() => submit(store, { ...incoming[0], sync_id: 'alias' }), { code: 'origin_sequence_conflict' });
 f.close(); writeFileSync(f.databasePath, snapshot); unlinkSync(approvalPath); store = f.open();
 for (const item of incoming) assert.equal(submit(store, item).results[0].status, 'duplicate');
 assert.equal(store.authenticate(token).device_id, 'phone-one'); assert.deepEqual(counts(store), before);
 // Restored source missing the durable ledger is repaired only from the preserved approved file.
 store.db.prepare('DELETE FROM core_metadata WHERE key=?').run(KEY); writeFileSync(approvalPath, serialized); store = f.open();
 assert.equal(JSON.parse(store.db.prepare('SELECT value FROM core_metadata WHERE key=?').get(KEY).value).approved_replays.length, 72);
 assert.throws(() => submit(store, { ...incoming[71], content: 'changed' }), { code: 'origin_sequence_conflict' });
 const bad = structuredClone(document); bad.approved_replays[0].origin_sequence = 9000;
 writeFileSync(approvalPath, JSON.stringify(bad)); assert.throws(() => f.open(), { code: 'historical_replay_approvals_invalid' });
 writeFileSync(approvalPath, serialized); store = f.open();
 assert.equal(submit(store, incoming[0]).results[0].status, 'duplicate'); assert.deepEqual(counts(store), before);
});


test('pending Core reply work prevents legacy transcript activation even when reply jobs are switched off', t => {
 const f = fixture(t); const token = pair(f.store);
 let store = f.open({ companionReplyJobsEnabled: true });
 store.submitMessages('phone-one', { device_id: 'phone-one', request_companion_reply: true,
  messages: [message({ sender: 'user' })] });
 assert.equal(counts(store)[2], 1);
 f.grants(token);
 assert.throws(() => f.open({ companionUploadMode: 'legacy_b3' }), { code: 'companion_executor_conflict' });
});

test('schema 6 legacy transcript access fails closed after schema or database role changes', t => {
 for (const change of ['schema', 'role']) {
  const f = fixture(t); const token = pair(f.store); f.grants(token); f.migrate();
  const store = f.open({ companionUploadMode: 'legacy_b3' });
  if (change === 'schema') store.db.prepare("UPDATE core_metadata SET value='5' WHERE key='schema_version'").run();
  else store.db.prepare("UPDATE activity_metadata SET value='backup_read_only' WHERE key='database_role'").run();
  assert.throws(() => transcript(store, token), error => error.status === 503);
  assert.throws(() => store.localTranscriptCapabilities(token), error => error.status === 503);
  assert.deepEqual(counts(store), [0, 0, 0]);
 }
});
