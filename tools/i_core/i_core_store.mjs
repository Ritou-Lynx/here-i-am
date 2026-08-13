import { createHash, createHmac, randomBytes, randomUUID } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';

export const CORE_PROTOCOL_VERSION = '0.1';
export const CORE_STORE_SCHEMA_VERSION = 3;
export const MAX_MESSAGE_BATCH = 100;
export const CORE_WORKLOADS = Object.freeze([
  'companion_reply',
  'record_organizer',
  'memory_v3',
  'dreaming',
  'checkin',
]);
export const DEFAULT_LEASE_TTL_MS = 30_000;
export const MIN_LEASE_TTL_MS = 5_000;
export const MAX_LEASE_TTL_MS = 300_000;

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

function normalizeWorkload(value) {
  const workload = requiredString(value, 'workload');
  if (!CORE_WORKLOADS.includes(workload)) {
    throw new CoreStoreError(
      'unknown_workload',
      `workload must be one of: ${CORE_WORKLOADS.join(', ')}.`,
    );
  }
  return workload;
}

function normalizeLeaseTtl(value) {
  const ttl = value == null
    ? DEFAULT_LEASE_TTL_MS
    : requiredInteger(value, 'ttl_ms', { minimum: MIN_LEASE_TTL_MS });
  if (ttl > MAX_LEASE_TTL_MS) {
    throw new CoreStoreError(
      'invalid_request',
      `ttl_ms must be <= ${MAX_LEASE_TTL_MS}.`,
    );
  }
  return ttl;
}

function normalizeMessage(raw, authenticatedDeviceId, { allowCompanion = false } = {}) {
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
  const allowedSenders = allowCompanion ? ['user', 'companion'] : ['user'];
  if (!allowedSenders.includes(message.sender)) {
    throw new CoreStoreError(
      'sender_not_allowed',
      allowCompanion
        ? 'Historical imports may only contain user or companion messages.'
        : 'Remote clients may only submit user messages.',
      { status: 403 },
    );
  }
  return message;
}

export class ICoreStore {
  constructor(databasePath, { companionReplyJobsEnabled = false } = {}) {
    mkdirSync(path.dirname(databasePath), { recursive: true });
    this.db = new DatabaseSync(databasePath);
    this.companionReplyJobsEnabled = companionReplyJobsEnabled;
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

  health({ workerLeasesEnabled = false } = {}) {
    return {
      ok: true,
      node_id: this.nodeId,
      role: 'authority',
      protocol_version: CORE_PROTOCOL_VERSION,
      minimum_protocol_version: CORE_PROTOCOL_VERSION,
      schema_version: CORE_STORE_SCHEMA_VERSION,
      server_time_ms: Date.now(),
      features: [
        'device_pairing',
        'chat_submit',
        'change_feed',
        'cursor_ack',
        ...(workerLeasesEnabled ? ['worker_leases'] : []),
        ...(workerLeasesEnabled && this.companionReplyJobsEnabled
          ? ['companion_reply_jobs']
          : []),
      ],
    };
  }

  acquireWorkerLease(raw, now = Date.now()) {
    const workload = normalizeWorkload(raw?.workload);
    const holderId = requiredString(raw?.holder_id, 'holder_id');
    const ttlMs = normalizeLeaseTtl(raw?.ttl_ms);
    const leaseToken = randomBytes(32).toString('base64url');
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const existing = this.db.prepare(`
        SELECT holder_id, fencing_token, expires_at_ms
        FROM worker_leases WHERE workload = ?
      `).get(workload);
      if (existing && Number(existing.expires_at_ms) > now) {
        throw new CoreStoreError(
          'lease_held',
          'The workload already has an active lease.',
          {
            status: 409,
            retryable: true,
            details: {
              workload,
              holder_id: existing.holder_id,
              expires_at_ms: Number(existing.expires_at_ms),
            },
          },
        );
      }
      const fencingToken = existing ? Number(existing.fencing_token) + 1 : 1;
      const expiresAt = now + ttlMs;
      this.db.prepare(`
        INSERT INTO worker_leases(
          workload, holder_id, lease_token_hash, fencing_token,
          acquired_at_ms, renewed_at_ms, expires_at_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(workload) DO UPDATE SET
          holder_id = excluded.holder_id,
          lease_token_hash = excluded.lease_token_hash,
          fencing_token = excluded.fencing_token,
          acquired_at_ms = excluded.acquired_at_ms,
          renewed_at_ms = excluded.renewed_at_ms,
          expires_at_ms = excluded.expires_at_ms
      `).run(
        workload,
        holderId,
        tokenDigest(leaseToken),
        fencingToken,
        now,
        now,
        expiresAt,
      );
      this.db.exec('COMMIT');
      return {
        workload,
        holder_id: holderId,
        lease_token: leaseToken,
        fencing_token: fencingToken,
        acquired_at_ms: now,
        expires_at_ms: expiresAt,
      };
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }

  renewWorkerLease(raw, now = Date.now()) {
    const lease = this.#requireActiveLease(raw, now);
    const ttlMs = normalizeLeaseTtl(raw?.ttl_ms);
    const expiresAt = now + ttlMs;
    this.db.prepare(`
      UPDATE worker_leases
      SET renewed_at_ms = ?, expires_at_ms = ?
      WHERE workload = ?
    `).run(now, expiresAt, lease.workload);
    return {
      workload: lease.workload,
      holder_id: lease.holderId,
      fencing_token: lease.fencingToken,
      renewed_at_ms: now,
      expires_at_ms: expiresAt,
    };
  }

  releaseWorkerLease(raw, now = Date.now()) {
    const lease = this.#requireActiveLease(raw, now);
    this.db.prepare(`
      UPDATE worker_leases
      SET renewed_at_ms = ?, expires_at_ms = ?
      WHERE workload = ?
    `).run(now, now, lease.workload);
    return {
      ok: true,
      workload: lease.workload,
      holder_id: lease.holderId,
      fencing_token: lease.fencingToken,
      released_at_ms: now,
    };
  }

  listWorkerLeases(now = Date.now()) {
    return {
      leases: this.db.prepare(`
        SELECT workload, holder_id, fencing_token, acquired_at_ms,
               renewed_at_ms, expires_at_ms
        FROM worker_leases ORDER BY workload
      `).all().map((row) => ({
        workload: row.workload,
        holder_id: row.holder_id,
        fencing_token: Number(row.fencing_token),
        acquired_at_ms: Number(row.acquired_at_ms),
        renewed_at_ms: Number(row.renewed_at_ms),
        expires_at_ms: Number(row.expires_at_ms),
        active: Number(row.expires_at_ms) > now,
      })),
      server_time_ms: now,
    };
  }

  #requireActiveLease(raw, now) {
    const workload = normalizeWorkload(raw?.workload);
    const holderId = requiredString(raw?.holder_id, 'holder_id');
    const leaseToken = requiredString(raw?.lease_token, 'lease_token');
    const fencingToken = requiredInteger(
      raw?.fencing_token,
      'fencing_token',
      { minimum: 1 },
    );
    const existing = this.db.prepare(`
      SELECT holder_id, lease_token_hash, fencing_token, expires_at_ms
      FROM worker_leases WHERE workload = ?
    `).get(workload);
    if (!existing) {
      throw new CoreStoreError('lease_not_found', 'The workload has no lease.', { status: 404 });
    }
    if (Number(existing.expires_at_ms) <= now) {
      throw new CoreStoreError(
        'lease_expired',
        'The lease has expired and must be acquired again.',
        { status: 409, retryable: true, details: { workload } },
      );
    }
    if (
      existing.holder_id !== holderId ||
      Number(existing.fencing_token) !== fencingToken ||
      existing.lease_token_hash !== tokenDigest(leaseToken)
    ) {
      throw new CoreStoreError(
        'stale_lease',
        'The lease token or fencing token is no longer current.',
        { status: 409, details: { workload } },
      );
    }
    return { workload, holderId, fencingToken };
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
    if (
      raw?.request_companion_reply != null &&
      typeof raw.request_companion_reply !== 'boolean'
    ) {
      throw new CoreStoreError(
        'invalid_request',
        'request_companion_reply must be a boolean when provided.',
      );
    }
    if (raw?.request_companion_reply === true && !this.companionReplyJobsEnabled) {
      throw new CoreStoreError(
        'feature_disabled',
        'This core is not accepting companion reply jobs yet.',
        { status: 503, retryable: true },
      );
    }
    const messages = raw.messages
      .map((message) => normalizeMessage(message, authenticatedDeviceId))
      .sort((left, right) => left.origin_sequence - right.origin_sequence);
    return this.#persistMessages(messages, {
      enqueueCompanionReplies:
        this.companionReplyJobsEnabled && raw?.request_companion_reply === true,
    });
  }

  /// Local maintenance entry point for one-time, trusted history imports.
  /// This is deliberately not exposed by the HTTP server: remote clients
  /// remain unable to submit companion messages or impersonate another
  /// origin device.
  importMessages(importDeviceId, rawMessages) {
    const deviceId = requiredString(importDeviceId, 'import_device_id');
    if (!Array.isArray(rawMessages) || rawMessages.length === 0) {
      throw new CoreStoreError(
        'invalid_request',
        'rawMessages must contain at least one item.',
      );
    }
    const messages = rawMessages
      .map((message) => normalizeMessage(message, deviceId, { allowCompanion: true }))
      .sort((left, right) => left.origin_sequence - right.origin_sequence);
    return this.#persistMessages(messages, {
      localDevice: {
        deviceId,
        displayName: 'V3 historical import',
        platform: 'local-import',
      },
      allowSemanticExisting: true,
    });
  }

  publishCompanionMessages(raw, now = Date.now()) {
    const lease = this.#requireActiveLease(raw, now);
    if (lease.workload !== 'companion_reply') {
      throw new CoreStoreError(
        'wrong_workload',
        'Companion messages require the companion_reply workload lease.',
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
      .map((message) => normalizeMessage(message, lease.holderId, { allowCompanion: true }))
      .sort((left, right) => left.origin_sequence - right.origin_sequence);
    if (messages.some((message) => message.sender !== 'companion')) {
      throw new CoreStoreError(
        'sender_not_allowed',
        'The companion publication endpoint only accepts companion messages.',
        { status: 403 },
      );
    }
    return this.#persistMessages(messages, {
      localDevice: {
        deviceId: lease.holderId,
        displayName: `Core worker: ${lease.holderId}`,
        platform: 'core-worker',
      },
    });
  }

  claimCompanionReplyJob(raw, now = Date.now()) {
    this.#requireCompanionReplyJobsEnabled();
    const lease = this.#requireActiveLease(raw, now);
    if (lease.workload !== 'companion_reply') {
      throw new CoreStoreError(
        'wrong_workload',
        'Companion reply jobs require the companion_reply workload lease.',
        { status: 403 },
      );
    }
    let jobId = null;
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const alreadyClaimed = this.db.prepare(`
        SELECT job_id FROM companion_reply_jobs
        WHERE status = 'claimed' AND claimed_by = ? AND claim_fencing_token = ?
        ORDER BY trigger_server_sequence LIMIT 1
      `).get(lease.holderId, lease.fencingToken);
      const available = alreadyClaimed ?? this.db.prepare(`
        SELECT job_id FROM companion_reply_jobs
        WHERE status = 'pending'
           OR (status = 'claimed' AND claim_fencing_token < ?)
        ORDER BY trigger_server_sequence LIMIT 1
      `).get(lease.fencingToken);
      if (available) {
        jobId = available.job_id;
        this.db.prepare(`
          UPDATE companion_reply_jobs
          SET status = 'claimed', claimed_by = ?, claim_fencing_token = ?,
              claimed_at_ms = ?, updated_at_ms = ?
          WHERE job_id = ?
        `).run(lease.holderId, lease.fencingToken, now, now, jobId);
      }
      this.db.exec('COMMIT');
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
    return {
      job: jobId ? this.#companionReplyJob(jobId) : null,
      server_time_ms: now,
    };
  }

  completeCompanionReplyJob(raw, now = Date.now()) {
    this.#requireCompanionReplyJobsEnabled();
    const lease = this.#requireActiveLease(raw, now);
    if (lease.workload !== 'companion_reply') {
      throw new CoreStoreError(
        'wrong_workload',
        'Companion reply jobs require the companion_reply workload lease.',
        { status: 403 },
      );
    }
    const jobId = requiredString(raw?.job_id, 'job_id');
    const content = requiredString(raw?.content, 'content', { allowEmpty: true });
    const row = this.db.prepare(`
      SELECT * FROM companion_reply_jobs WHERE job_id = ?
    `).get(jobId);
    if (!row) {
      throw new CoreStoreError(
        'job_not_found',
        'The companion reply job does not exist.',
        { status: 404 },
      );
    }
    const existingReply = this.db.prepare(`
      SELECT content, message_type, server_sequence
      FROM chat_messages WHERE sync_id = ?
    `).get(row.reply_sync_id);
    if (row.status === 'completed') {
      if (
        !existingReply ||
        existingReply.content !== content ||
        existingReply.message_type !== (raw?.message_type ?? 'chat')
      ) {
        throw new CoreStoreError(
          'immutable_message_conflict',
          'The completed reply has different immutable content.',
          { status: 409, details: { sync_id: row.reply_sync_id } },
        );
      }
      return {
        job_id: jobId,
        status: 'completed',
        reply_sync_id: row.reply_sync_id,
        reply_server_sequence: Number(existingReply.server_sequence),
        publication_status: 'duplicate',
        completed_at_ms: Number(row.completed_at_ms),
      };
    }
    if (
      row.status !== 'claimed' ||
      row.claimed_by !== lease.holderId ||
      Number(row.claim_fencing_token) !== lease.fencingToken
    ) {
      throw new CoreStoreError(
        'stale_job_claim',
        'The companion reply job is no longer claimed by this lease.',
        { status: 409 },
      );
    }
    let reply;
    if (existingReply) {
      if (
        existingReply.content !== content ||
        existingReply.message_type !== (raw?.message_type ?? 'chat')
      ) {
        throw new CoreStoreError(
          'immutable_message_conflict',
          'The reply already exists with different immutable content.',
          { status: 409, details: { sync_id: row.reply_sync_id } },
        );
      }
      reply = {
        status: 'duplicate',
        server_sequence: Number(existingReply.server_sequence),
      };
    } else {
      const authorityDeviceId = `core-companion:${row.character_id}`;
      const message = normalizeMessage({
          sync_id: row.reply_sync_id,
          origin_device_id: authorityDeviceId,
          origin_sequence: Number(row.trigger_server_sequence),
          character_id: row.character_id,
          sender: 'companion',
          content,
          created_at_ms: raw?.created_at_ms == null
            ? now
            : requiredInteger(raw.created_at_ms, 'created_at_ms', { minimum: 0 }),
          message_type: raw?.message_type == null
            ? 'chat'
            : requiredString(raw.message_type, 'message_type'),
          asset_refs: optionalObjectArray(raw?.asset_refs, 'asset_refs'),
          addenda: optionalObjectArray(raw?.addenda, 'addenda'),
        }, authorityDeviceId, { allowCompanion: true });
      const publication = this.#persistMessages([message], {
        localDevice: {
          deviceId: authorityDeviceId,
          displayName: `Core companion authority: ${row.character_id}`,
          platform: 'core-authority',
        },
      });
      reply = publication.results[0];
    }
    this.db.prepare(`
      UPDATE companion_reply_jobs
      SET status = 'completed', completed_at_ms = ?, updated_at_ms = ?,
          reply_server_sequence = ?
      WHERE job_id = ? AND status = 'claimed'
        AND claimed_by = ? AND claim_fencing_token = ?
    `).run(
      now,
      now,
      reply.server_sequence,
      jobId,
      lease.holderId,
      lease.fencingToken,
    );
    return {
      job_id: jobId,
      status: 'completed',
      reply_sync_id: row.reply_sync_id,
      reply_server_sequence: reply.server_sequence,
      publication_status: reply.status,
      completed_at_ms: now,
    };
  }

  #requireCompanionReplyJobsEnabled() {
    if (!this.companionReplyJobsEnabled) {
      throw new CoreStoreError(
        'feature_disabled',
        'Companion reply jobs are not enabled on this core.',
        { status: 503 },
      );
    }
  }

  #companionReplyJob(jobId) {
    const row = this.db.prepare(`
      SELECT * FROM companion_reply_jobs WHERE job_id = ?
    `).get(jobId);
    if (!row) return null;
    const context = this.db.prepare(`
      SELECT sync_id, origin_device_id, origin_sequence, character_id, sender,
             content, created_at_ms, message_type, asset_refs_json, addenda_json,
             server_sequence
      FROM chat_messages
      WHERE character_id = ? AND server_sequence <= ?
      ORDER BY server_sequence DESC LIMIT 20
    `).all(row.character_id, row.trigger_server_sequence).reverse().map((message) => ({
      sync_id: message.sync_id,
      origin_device_id: message.origin_device_id,
      origin_sequence: Number(message.origin_sequence),
      character_id: message.character_id,
      sender: message.sender,
      content: message.content,
      created_at_ms: Number(message.created_at_ms),
      message_type: message.message_type,
      asset_refs: JSON.parse(message.asset_refs_json),
      addenda: JSON.parse(message.addenda_json),
      server_sequence: Number(message.server_sequence),
    }));
    return {
      job_id: row.job_id,
      trigger_sync_id: row.trigger_sync_id,
      reply_sync_id: row.reply_sync_id,
      character_id: row.character_id,
      trigger_server_sequence: Number(row.trigger_server_sequence),
      status: row.status,
      claimed_by: row.claimed_by,
      claim_fencing_token: Number(row.claim_fencing_token),
      claimed_at_ms: Number(row.claimed_at_ms),
      context,
    };
  }

  #persistMessages(messages, {
    localDevice = null,
    allowSemanticExisting = false,
    enqueueCompanionReplies = false,
  } = {}) {
    const results = [];
    this.db.exec('BEGIN IMMEDIATE');
    try {
      if (localDevice) {
        const now = Date.now();
        this.db.prepare(`
          INSERT INTO devices(
            device_id, display_name, platform, client_version,
            capabilities_json, token_hash, paired_at_ms, updated_at_ms,
            last_ack_sequence
          ) VALUES (?, ?, ?, '0.1', '[]', ?, ?, ?, 0)
          ON CONFLICT(device_id) DO NOTHING
        `).run(
          localDevice.deviceId,
          localDevice.displayName,
          localDevice.platform,
          tokenDigest(`local-device:${localDevice.deviceId}`),
          now,
          now,
        );
      }
      for (const message of messages) {
        const digest = canonicalDigest(message);
        const existing = this.db.prepare(`
          SELECT canonical_digest, server_sequence, character_id, sender,
                 content, created_at_ms, message_type
          FROM chat_messages WHERE sync_id = ?
        `).get(message.sync_id);
        if (existing) {
          const sameSemanticMessage =
            existing.character_id === message.character_id &&
            existing.sender === message.sender &&
            existing.content === message.content &&
            Math.abs(Number(existing.created_at_ms) - message.created_at_ms) < 1000 &&
            existing.message_type === message.message_type;
          if (
            existing.canonical_digest !== digest &&
            !(allowSemanticExisting && sameSemanticMessage)
          ) {
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
        if (enqueueCompanionReplies && message.sender === 'user') {
          this.db.prepare(`
            UPDATE companion_reply_jobs
            SET status = 'superseded', updated_at_ms = ?
            WHERE character_id = ? AND status IN ('pending', 'claimed')
          `).run(occurredAt, message.character_id);
          this.db.prepare(`
            INSERT INTO companion_reply_jobs(
              job_id, trigger_sync_id, reply_sync_id, character_id,
              trigger_server_sequence, status, created_at_ms, updated_at_ms
            ) VALUES (?, ?, ?, ?, ?, 'pending', ?, ?)
          `).run(
            `reply-job:${message.sync_id}`,
            message.sync_id,
            `companion-reply:${message.sync_id}`,
            message.character_id,
            serverSequence,
            occurredAt,
            occurredAt,
          );
        }
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
