// Public, synthetic schema-v4 fixture. This is NOT the missing historical runtime.
// DDL is frozen from the eight legacy tables retained in the public ICoreStore.
// The production v4 guard independently verifies its fixed column-shape digest.
import assert from 'node:assert/strict';
import { createHash, createHmac } from 'node:crypto';
import { existsSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';

export function seedSchema4(filename) {
  assert.equal(existsSync(filename), false, 'synthetic seed must never overwrite a database');
  const db = new DatabaseSync(filename);
  try {
    db.exec(`PRAGMA foreign_keys=ON;
      CREATE TABLE IF NOT EXISTS core_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS devices (
        device_id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        platform TEXT NOT NULL,
        client_version TEXT NOT NULL,
        capabilities_json TEXT NOT NULL,
        token_hash TEXT NOT NULL UNIQUE,
        paired_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        last_ack_sequence INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE IF NOT EXISTS consumed_pairing_codes (
        code_hash TEXT PRIMARY KEY,
        consumed_at_ms INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS change_events (
        server_sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        occurred_at_ms INTEGER NOT NULL,
        payload_json TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS change_events_entity_idx
        ON change_events(kind, entity_id);
      CREATE TABLE IF NOT EXISTS chat_messages (
        sync_id TEXT PRIMARY KEY,
        origin_device_id TEXT NOT NULL,
        origin_sequence INTEGER NOT NULL,
        character_id TEXT NOT NULL,
        sender TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        message_type TEXT NOT NULL,
        asset_refs_json TEXT NOT NULL,
        addenda_json TEXT NOT NULL,
        canonical_digest TEXT NOT NULL,
        server_sequence INTEGER NOT NULL UNIQUE,
        FOREIGN KEY(origin_device_id) REFERENCES devices(device_id),
        FOREIGN KEY(server_sequence) REFERENCES change_events(server_sequence),
        UNIQUE(origin_device_id, origin_sequence)
      );
      CREATE TABLE IF NOT EXISTS worker_leases (
        workload TEXT PRIMARY KEY,
        holder_id TEXT NOT NULL,
        lease_token_hash TEXT NOT NULL,
        fencing_token INTEGER NOT NULL,
        acquired_at_ms INTEGER NOT NULL,
        renewed_at_ms INTEGER NOT NULL,
        expires_at_ms INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS companion_reply_jobs (
        job_id TEXT PRIMARY KEY,
        trigger_sync_id TEXT NOT NULL UNIQUE,
        reply_sync_id TEXT NOT NULL UNIQUE,
        character_id TEXT NOT NULL,
        trigger_server_sequence INTEGER NOT NULL UNIQUE,
        status TEXT NOT NULL CHECK(status IN ('pending', 'claimed', 'completed', 'superseded')),
        claimed_by TEXT,
        claim_fencing_token INTEGER,
        claimed_at_ms INTEGER,
        completed_at_ms INTEGER,
        reply_server_sequence INTEGER,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        FOREIGN KEY(trigger_sync_id) REFERENCES chat_messages(sync_id),
        FOREIGN KEY(trigger_server_sequence) REFERENCES change_events(server_sequence),
        FOREIGN KEY(reply_server_sequence) REFERENCES change_events(server_sequence)
      );
      CREATE INDEX IF NOT EXISTS companion_reply_jobs_status_idx
        ON companion_reply_jobs(status, trigger_server_sequence);
      CREATE TABLE IF NOT EXISTS companion_reply_shadow_runs (
        job_id TEXT PRIMARY KEY,
        holder_id TEXT NOT NULL,
        fencing_token INTEGER NOT NULL,
        model TEXT NOT NULL,
        duration_ms INTEGER NOT NULL,
        reply_characters INTEGER NOT NULL,
        completed_at_ms INTEGER NOT NULL,
        FOREIGN KEY(job_id) REFERENCES companion_reply_jobs(job_id)
      );

    `);
    const hash = value => createHash('sha256').update(value).digest('hex');
    const message = { sync_id: 'm3-message', origin_device_id: 'm3-synthetic', origin_sequence: 1,
      character_id: 'm3-character', sender: 'user', content: 'M3 synthetic migration fixture',
      created_at_ms: 1000000, message_type: 'chat', asset_refs: [], addenda: [] };
    const canonical = Object.fromEntries(Object.entries(message).sort(([a], [b]) => a.localeCompare(b)));
    for (const [key, value] of Object.entries({ schema_version: '4', node_id: 'm3-synthetic-node',
      cursor_secret: Buffer.alloc(32, 7).toString('base64url') })) {
      db.prepare('INSERT INTO core_metadata VALUES (?,?)').run(key, value);
    }
    db.prepare('INSERT INTO devices VALUES (?,?,?,?,?,?,?,?,?)').run(
      'm3-synthetic', 'M3 synthetic', 'test', '1', '["chat"]', hash('synthetic-token'), 1000000, 1000000, 0);
    db.prepare('INSERT INTO consumed_pairing_codes VALUES (?,?)').run(hash('m3-synthetic-pairing-code'), 1000000);
    db.prepare('INSERT INTO change_events VALUES (?,?,?,?,?,?)').run(1, 'm3-event', 'chat.message.upsert', 'm3-message', 1000000, JSON.stringify(message));
    db.prepare('INSERT INTO chat_messages VALUES (?,?,?,?,?,?,?,?,?,?,?,?)').run(
      message.sync_id, message.origin_device_id, message.origin_sequence, message.character_id,
      message.sender, message.content, message.created_at_ms, message.message_type, '[]', '[]', hash(JSON.stringify(canonical)), 1);
    db.prepare('INSERT INTO worker_leases VALUES (?,?,?,?,?,?,?)').run(
      'companion_reply', 'm3-worker', hash('synthetic-lease'), 1, 1000000, 1000000, 1030000);
    db.prepare('INSERT INTO companion_reply_jobs VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)').run(
      'm3-job', 'm3-message', 'm3-reply', 'm3-character', 1, 'claimed', 'm3-worker', 1, 1000001, null, null, 1000000, 1000001);
    db.prepare('INSERT INTO companion_reply_shadow_runs VALUES (?,?,?,?,?,?,?)').run(
      'm3-job', 'm3-worker', 1, 'synthetic-no-provider', 1, 3, 1000002);
    assert.deepEqual(db.prepare('PRAGMA foreign_key_check').all(), []);
  } finally { db.close(); }
}

// A minimal fixture reader contract for checking preservation after rollback.
// Opening an existing owned DB permits SQLite hot-journal recovery after a killed writer.
// It cannot seed/migrate state or stand in for old server behavior.
export class Schema4Reader {
  constructor(filename) {
    assert.ok(existsSync(filename), 'fixture reader requires existing state');
    this.db = new DatabaseSync(filename);
    const metadata = Object.fromEntries(this.db.prepare('SELECT key,value FROM core_metadata').all().map(row => [row.key, row.value]));
    assert.equal(metadata.schema_version, '4');
    this.nodeId = metadata.node_id;
    this.cursorSecret = metadata.cursor_secret;
  }
  encodeCursor(sequence) {
    const body = String(sequence);
    return `v1.${body}.${createHmac('sha256', this.cursorSecret).update(body).digest('base64url').slice(0, 22)}`;
  }
  decodeCursor(cursor) {
    const match = /^v1\.(\d+)\.([A-Za-z0-9_-]{22})$/.exec(cursor);
    assert.ok(match);
    const sequence = Number(match[1]);
    assert.ok(Number.isSafeInteger(sequence));
    assert.equal(this.encodeCursor(sequence), cursor);
    return sequence;
  }
  getChanges(cursor) {
    return this.db.prepare('SELECT * FROM change_events WHERE server_sequence > ? ORDER BY server_sequence').all(this.decodeCursor(cursor))
      .map(row => ({ ...row, payload: JSON.parse(row.payload_json) }));
  }
  close() { this.db.close(); }
}
