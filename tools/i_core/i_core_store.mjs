import { createHash, createHmac, randomBytes, randomUUID } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';

export const CORE_PROTOCOL_VERSION = '0.1';
export const CORE_STORE_SCHEMA_VERSION = 1;
export const MAX_MESSAGE_BATCH = 100;

export class CoreStoreError extends Error {
  constructor(code, message, { status = 400, retryable = false, details = {} } = {}) {
    super(message);
    this.name = 'CoreStoreError';
    this.code = code;
    this.status = status;
    this.retryable = retryable;
    this.details = details;
  }
}

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]),
    );
  }
  return value;
}

function canonicalDigest(value) {
  return createHash('sha256')
    .update(JSON.stringify(canonicalize(value)))
    .digest('hex');
}

function tokenDigest(value) {
  return createHash('sha256').update(value).digest('hex');
}

function requiredString(value, field, { allowEmpty = false } = {}) {
  if (typeof value !== 'string' || (!allowEmpty && !value.trim())) {
    throw new CoreStoreError('invalid_request', `${field} must be ${allowEmpty ? 'a' : 'a non-empty'} string.`);
  }
  return value;
}

function requiredInteger(value, field, { minimum = Number.MIN_SAFE_INTEGER } = {}) {
  if (!Number.isSafeInteger(value) || value < minimum) {
    throw new CoreStoreError('invalid_request', `${field} must be an integer >= ${minimum}.`);
  }
  return value;
}

function optionalObjectArray(value, field) {
  if (value == null) return [];
  if (!Array.isArray(value) || value.some((item) => !item || typeof item !== 'object' || Array.isArray(item))) {
    throw new CoreStoreError('invalid_request', `${field} must be an array of objects.`);
  }
  return value;
}

function stringArray(value, field) {
  if (value == null) return [];
  if (!Array.isArray(value) || value.some((item) => typeof item !== 'string')) {
    throw new CoreStoreError('invalid_request', `${field} must be an array of strings.`);
  }
  return value;
}

function normalizeMessage(raw, authenticatedDeviceId) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new CoreStoreError('invalid_request', 'Each message must be an object.');
  }
  const message = {
    sync_id: requiredString(raw.sync_id, 'sync_id'),
    origin_device_id: requiredString(raw.origin_device_id, 'origin_device_id'),
    origin_sequence: requiredInteger(raw.origin_sequence, 'origin_sequence', { minimum: 0 }),
    character_id: requiredString(raw.character_id, 'character_id'),
    sender: requiredString(raw.sender, 'sender'),
    content: requiredString(raw.content, 'content', { allowEmpty: true }),
    created_at_ms: requiredInteger(raw.created_at_ms, 'created_at_ms', { minimum: 0 }),
    message_type: raw.message_type == null
      ? 'chat'
      : requiredString(raw.message_type, 'message_type'),
    asset_refs: optionalObjectArray(raw.asset_refs, 'asset_refs'),
    addenda: optionalObjectArray(raw.addenda, 'addenda'),
  };
  if (message.origin_device_id !== authenticatedDeviceId) {
    throw new CoreStoreError(
      'origin_device_mismatch',
      'origin_device_id must match the authenticated device.',
      { status: 403 },
    );
  }
  if (message.sender !== 'user') {
    throw new CoreStoreError(
      'sender_not_allowed',
      'Remote clients may only submit user messages.',
      { status: 403 },
    );
  }
  return message;
}

export class ICoreStore {
  constructor(databasePath) {
    mkdirSync(path.dirname(databasePath), { recursive: true });
    this.db = new DatabaseSync(databasePath);
    this.db.exec('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;');
    this.#migrate();
    this.nodeId = this.#metadata('node_id') ?? this.#setMetadata('node_id', randomUUID());
    this.cursorSecret = this.#metadata('cursor_secret') ??
      this.#setMetadata('cursor_secret', randomBytes(32).toString('base64url'));
  }

  #migrate() {
    this.db.exec(`
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
    `);
    this.#setMetadata('schema_version', String(CORE_STORE_SCHEMA_VERSION));
  }

  #metadata(key) {
    return this.db.prepare('SELECT value FROM core_metadata WHERE key = ?').get(key)?.value ?? null;
  }

  #setMetadata(key, value) {
    this.db.prepare(`
      INSERT INTO core_metadata(key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    `).run(key, value);
    return value;
  }

  health() {
    return {
      ok: true,
      node_id: this.nodeId,
      role: 'authority',
      protocol_version: CORE_PROTOCOL_VERSION,
      minimum_protocol_version: CORE_PROTOCOL_VERSION,
      schema_version: CORE_STORE_SCHEMA_VERSION,
      server_time_ms: Date.now(),
      features: ['device_pairing', 'chat_submit', 'change_feed', 'cursor_ack'],
    };
  }

  pairDevice(raw, pairingCode) {
    const deviceId = requiredString(raw?.device_id, 'device_id');
    const displayName = requiredString(raw?.display_name, 'display_name');
    const platform = requiredString(raw?.platform, 'platform');
    const clientVersion = requiredString(raw?.client_version, 'client_version');
    const capabilities = stringArray(raw?.capabilities, 'capabilities');
    const token = randomBytes(32).toString('base64url');
    const now = Date.now();
    this.db.exec('BEGIN IMMEDIATE');
    try {
      if (this.isPairingCodeConsumed(pairingCode)) {
        throw new CoreStoreError(
          'invalid_pairing_code',
          'The pairing code has already been consumed.',
          { status: 401 },
        );
      }
      this.db.prepare(`
        INSERT INTO devices(
          device_id, display_name, platform, client_version, capabilities_json,
          token_hash, paired_at_ms, updated_at_ms, last_ack_sequence
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)
        ON CONFLICT(device_id) DO UPDATE SET
          display_name = excluded.display_name,
          platform = excluded.platform,
          client_version = excluded.client_version,
          capabilities_json = excluded.capabilities_json,
          token_hash = excluded.token_hash,
          updated_at_ms = excluded.updated_at_ms
      `).run(
        deviceId,
        displayName,
        platform,
        clientVersion,
        JSON.stringify(capabilities),
        tokenDigest(token),
        now,
        now,
      );
      this.db.prepare(`
        INSERT INTO consumed_pairing_codes(code_hash, consumed_at_ms)
        VALUES (?, ?)
      `).run(tokenDigest(pairingCode), now);
      this.db.exec('COMMIT');
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
    return {
      device_id: deviceId,
      device_token: token,
      initial_cursor: this.encodeCursor(0),
      core_node_id: this.nodeId,
      protocol_version: CORE_PROTOCOL_VERSION,
    };
  }

  isPairingCodeConsumed(pairingCode) {
    return this.db.prepare(`
      SELECT 1 AS found FROM consumed_pairing_codes WHERE code_hash = ?
    `).get(tokenDigest(pairingCode))?.found === 1;
  }

  authenticate(token) {
    if (typeof token !== 'string' || !token) return null;
    return this.db.prepare(`
      SELECT device_id, display_name, platform, client_version
      FROM devices WHERE token_hash = ?
    `).get(tokenDigest(token)) ?? null;
  }

  encodeCursor(sequence) {
    const body = String(sequence);
    const signature = createHmac('sha256', this.cursorSecret)
      .update(body)
      .digest('base64url')
      .slice(0, 22);
    return `v1.${body}.${signature}`;
  }

  decodeCursor(cursor) {
    if (typeof cursor !== 'string') {
      throw new CoreStoreError('invalid_cursor', 'cursor must be an opaque string.');
    }
    const match = /^v1\.(\d+)\.([A-Za-z0-9_-]{22})$/.exec(cursor);
    if (!match) throw new CoreStoreError('invalid_cursor', 'cursor is invalid.');
    const sequence = Number(match[1]);
    if (!Number.isSafeInteger(sequence)) {
      throw new CoreStoreError('invalid_cursor', 'cursor is invalid.');
    }
    if (this.encodeCursor(sequence) !== cursor) {
      throw new CoreStoreError('invalid_cursor', 'cursor signature is invalid.');
    }
    return sequence;
  }

  submitMessages(authenticatedDeviceId, raw) {
    const deviceId = requiredString(raw?.device_id, 'device_id');
    if (deviceId !== authenticatedDeviceId) {
      throw new CoreStoreError(
        'device_mismatch',
        'device_id must match the authenticated device.',
        { status: 403 },
      );
    }
    if (!Array.isArray(raw?.messages) || raw.messages.length === 0) {
      throw new CoreStoreError('invalid_request', 'messages must contain at least one item.');
    }
    if (raw.messages.length > MAX_MESSAGE_BATCH) {
      throw new CoreStoreError(
        'batch_too_large',
        `messages may contain at most ${MAX_MESSAGE_BATCH} items.`,
        { status: 413 },
      );
    }
    const messages = raw.messages
      .map((message) => normalizeMessage(message, authenticatedDeviceId))
      .sort((left, right) => left.origin_sequence - right.origin_sequence);
    const results = [];
    this.db.exec('BEGIN IMMEDIATE');
    try {
      for (const message of messages) {
        const digest = canonicalDigest(message);
        const existing = this.db.prepare(`
          SELECT canonical_digest, server_sequence
          FROM chat_messages WHERE sync_id = ?
        `).get(message.sync_id);
        if (existing) {
          if (existing.canonical_digest !== digest) {
            throw new CoreStoreError(
              'immutable_message_conflict',
              'sync_id already exists with different immutable content.',
              { status: 409, details: { sync_id: message.sync_id } },
            );
          }
          const existingSequence = Number(existing.server_sequence);
          results.push({
            sync_id: message.sync_id,
            status: 'duplicate',
            server_sequence: existingSequence,
          });
          continue;
        }
        const sequenceCollision = this.db.prepare(`
          SELECT sync_id FROM chat_messages
          WHERE origin_device_id = ? AND origin_sequence = ?
        `).get(message.origin_device_id, message.origin_sequence);
        if (sequenceCollision) {
          throw new CoreStoreError(
            'origin_sequence_conflict',
            'origin_sequence already points to another message.',
            {
              status: 409,
              details: {
                origin_sequence: message.origin_sequence,
                existing_sync_id: sequenceCollision.sync_id,
              },
            },
          );
        }
        const occurredAt = Date.now();
        const eventId = randomUUID();
        const eventResult = this.db.prepare(`
          INSERT INTO change_events(event_id, kind, entity_id, occurred_at_ms, payload_json)
          VALUES (?, 'chat.message.upsert', ?, ?, ?)
        `).run(eventId, message.sync_id, occurredAt, JSON.stringify(message));
        const serverSequence = Number(eventResult.lastInsertRowid);
        this.db.prepare(`
          INSERT INTO chat_messages(
            sync_id, origin_device_id, origin_sequence, character_id, sender,
            content, created_at_ms, message_type, asset_refs_json, addenda_json,
            canonical_digest, server_sequence
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `).run(
          message.sync_id,
          message.origin_device_id,
          message.origin_sequence,
          message.character_id,
          message.sender,
          message.content,
          message.created_at_ms,
          message.message_type,
          JSON.stringify(message.asset_refs),
          JSON.stringify(message.addenda),
          digest,
          serverSequence,
        );
        results.push({
          sync_id: message.sync_id,
          status: 'accepted',
          server_sequence: serverSequence,
        });
      }
      this.db.exec('COMMIT');
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
    return { results };
  }

  getChanges(cursor, rawLimit = 100) {
    const sequence = this.decodeCursor(cursor);
    const limit = Math.min(requiredInteger(rawLimit, 'limit', { minimum: 1 }), 500);
    const rows = this.db.prepare(`
      SELECT server_sequence, event_id, kind, entity_id, occurred_at_ms, payload_json
      FROM change_events
      WHERE server_sequence > ?
      ORDER BY server_sequence ASC
      LIMIT ?
    `).all(sequence, limit + 1);
    const hasMore = rows.length > limit;
    const pageRows = hasMore ? rows.slice(0, limit) : rows;
    const nextSequence = pageRows.length
      ? Number(pageRows.at(-1).server_sequence)
      : sequence;
    return {
      events: pageRows.map((row) => ({
        event_id: row.event_id,
        server_sequence: Number(row.server_sequence),
        kind: row.kind,
        entity_id: row.entity_id,
        occurred_at_ms: Number(row.occurred_at_ms),
        payload: JSON.parse(row.payload_json),
      })),
      next_cursor: this.encodeCursor(nextSequence),
      has_more: hasMore,
    };
  }

  acknowledgeCursor(authenticatedDeviceId, raw) {
    const deviceId = requiredString(raw?.device_id, 'device_id');
    if (deviceId !== authenticatedDeviceId) {
      throw new CoreStoreError('device_mismatch', 'device_id must match the authenticated device.', { status: 403 });
    }
    const sequence = this.decodeCursor(raw?.cursor);
    const latest = Number(
      this.db.prepare('SELECT COALESCE(MAX(server_sequence), 0) AS value FROM change_events').get().value,
    );
    if (sequence > latest) {
      throw new CoreStoreError('invalid_cursor', 'cursor points beyond the current change feed.');
    }
    this.db.prepare(`
      UPDATE devices
      SET last_ack_sequence = MAX(last_ack_sequence, ?), updated_at_ms = ?
      WHERE device_id = ?
    `).run(sequence, Date.now(), authenticatedDeviceId);
    return { ok: true, cursor: this.encodeCursor(sequence) };
  }

  close() {
    this.db.close();
  }
}
