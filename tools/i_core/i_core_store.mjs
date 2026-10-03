import { createHash, createHmac, randomBytes, randomUUID } from 'node:crypto';
import { closeSync, fstatSync, lstatSync, openSync, readSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, renameSync, rmSync, unlinkSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { pathToFileURL } from 'node:url';
import { backup, DatabaseSync } from 'node:sqlite';
import {
  ACTIVITY_CONTRACT,
  ACTIVITY_FEATURE_VERSION,
  ACTIVITY_RAW_RETENTION_MS,
  ACTIVITY_INTEGRITY_COMMITMENT_VERSION,
  ActivityControlPlane,
  activityRecoveryManifestForDatabase,
  assertActivityRecoveryFloorForDatabase,
  preflightActivityLegacyMigration,
  rollbackActivitySchema,
} from './activity_control_plane.mjs';

export const CORE_PROTOCOL_VERSION = '0.1';
export const CORE_STORE_SCHEMA_VERSION = 5;
export const MAX_MESSAGE_BATCH = 100;
export const CORE_WORKLOADS = Object.freeze([
  'companion_reply',
  'record_organizer',
  'memory_v3',
  'dreaming',
  'checkin',
]);
// Restricted external-frontend identity (B3 write-back, e.g. claude.ai web).
// It may append both sides of turns that already happened on that frontend,
// but cannot read the change feed or request core-generated replies.
export const EXTERNAL_FRONTEND_PLATFORM = 'external-frontend';
const EXTERNAL_FRONTEND_DEVICE_ID = /^frontend:[a-z][a-z0-9_]{1,31}$/;
export function isExternalFrontendDevice(device) {
  return device?.platform === EXTERNAL_FRONTEND_PLATFORM
    && EXTERNAL_FRONTEND_DEVICE_ID.test(String(device?.device_id ?? ''));
}
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

const HISTORICAL_REPLAY_APPROVALS_KEY = 'historical_replay_approvals_v1';
const HISTORICAL_REPLAY_APPROVALS_MAX_BYTES = 512 * 1024;
const HISTORICAL_REPLAY_APPROVALS_MAX_ENTRIES = 1000;

function invalidHistoricalReplayApprovals() {
  return new CoreStoreError(
    'historical_replay_approvals_invalid',
    'Historical replay approvals are invalid or conflict with durable bindings.',
    { status: 503 },
  );
}

function replaySequenceKey(deviceId, sequence) {
  return JSON.stringify([deviceId, sequence]);
}

function parseHistoricalReplayApprovals(value) {
  try {
    const document = JSON.parse(value);
    if (!document || Array.isArray(document) || document.version !== 1
      || Object.keys(document).sort().join(',') !== 'approved_replays,version'
      || !Array.isArray(document.approved_replays)
      || document.approved_replays.length > HISTORICAL_REPLAY_APPROVALS_MAX_ENTRIES) {
      throw invalidHistoricalReplayApprovals();
    }
    const ids = new Set();
    const sequences = new Set();
    return document.approved_replays.map((record) => {
      if (!record || Array.isArray(record)
        || Object.keys(record).sort().join(',') !== 'device_id,existing_digest,incoming_digest,origin_sequence,sync_id'
        || ![record.sync_id, record.device_id].every((value) =>
          typeof value === 'string' && value.length > 0 && value.trim() === value)
        || !Number.isSafeInteger(record.origin_sequence) || record.origin_sequence < 0
        || ![record.incoming_digest, record.existing_digest].every((value) =>
          typeof value === 'string' && /^[a-fA-F0-9]{64}$/.test(value))) {
        throw invalidHistoricalReplayApprovals();
      }
      const sequence = replaySequenceKey(record.device_id, record.origin_sequence);
      if (ids.has(record.sync_id) || sequences.has(sequence)) throw invalidHistoricalReplayApprovals();
      ids.add(record.sync_id);
      sequences.add(sequence);
      return Object.freeze({
        sync_id: record.sync_id,
        device_id: record.device_id,
        origin_sequence: record.origin_sequence,
        incoming_digest: record.incoming_digest.toLowerCase(),
        existing_digest: record.existing_digest.toLowerCase(),
      });
    });
  } catch {
    throw invalidHistoricalReplayApprovals();
  }
}

function readHistoricalReplayApprovalFile(filePath) {
  let descriptor;
  try {
    // Reject symbolic links and Windows junctions anywhere in the approval path.
    let current = path.resolve(filePath);
    while (true) {
      try {
        if (lstatSync(current).isSymbolicLink()) throw invalidHistoricalReplayApprovals();
      } catch (error) {
        if (error.code !== 'ENOENT') throw error;
      }
      const parent = path.dirname(current);
      if (parent === current) break;
      current = parent;
    }
    descriptor = openSync(filePath, 'r');
  } catch (error) {
    if (error.code === 'ENOENT') return [];
    throw invalidHistoricalReplayApprovals();
  }
  try {
    const opened = fstatSync(descriptor);
    const named = lstatSync(filePath);
    if (!opened.isFile() || named.isSymbolicLink()
      || opened.dev !== named.dev || opened.ino !== named.ino) {
      throw invalidHistoricalReplayApprovals();
    }
    const buffer = Buffer.alloc(HISTORICAL_REPLAY_APPROVALS_MAX_BYTES + 1);
    let length = 0;
    while (length < buffer.length) {
      const count = readSync(descriptor, buffer, length, buffer.length - length, null);
      if (count === 0) break;
      length += count;
    }
    if (length > HISTORICAL_REPLAY_APPROVALS_MAX_BYTES) throw invalidHistoricalReplayApprovals();
    return parseHistoricalReplayApprovals(new TextDecoder('utf-8', { fatal: true }).decode(buffer.subarray(0, length)));
  } catch {
    throw invalidHistoricalReplayApprovals();
  } finally {
    closeSync(descriptor);
  }
}

function readHistoricalReplayLedger(db) {
  if (!db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='core_metadata'").get()) return [];
  const stored = db.prepare('SELECT value FROM core_metadata WHERE key = ?').get(HISTORICAL_REPLAY_APPROVALS_KEY);
  if (!stored) return [];
  if (typeof stored.value !== 'string'
    || Buffer.byteLength(stored.value, 'utf8') > HISTORICAL_REPLAY_APPROVALS_MAX_BYTES) {
    throw invalidHistoricalReplayApprovals();
  }
  return parseHistoricalReplayApprovals(stored.value);
}

function mergeHistoricalReplayApprovals(persisted, incoming) {
  const bySyncId = new Map(persisted.map((record) => [record.sync_id, record]));
  const bySequence = new Map(persisted.map((record) =>
    [replaySequenceKey(record.device_id, record.origin_sequence), record]));
  for (const record of incoming) {
    const existing = bySyncId.get(record.sync_id);
    const sequence = replaySequenceKey(record.device_id, record.origin_sequence);
    const occupied = bySequence.get(sequence);
    if ((existing && canonicalDigest(existing) !== canonicalDigest(record))
      || (occupied && occupied.sync_id !== record.sync_id)) {
      throw invalidHistoricalReplayApprovals();
    }
    bySyncId.set(record.sync_id, record);
    bySequence.set(sequence, record);
  }
  const records = [...bySyncId.values()].sort((left, right) =>
    left.sync_id < right.sync_id ? -1 : left.sync_id > right.sync_id ? 1 : 0);
  const serialized = JSON.stringify({ version: 1, approved_replays: records });
  if (records.length > HISTORICAL_REPLAY_APPROVALS_MAX_ENTRIES
    || Buffer.byteLength(serialized, 'utf8') > HISTORICAL_REPLAY_APPROVALS_MAX_BYTES) {
    throw invalidHistoricalReplayApprovals();
  }
  return { bySyncId, bySequence, records, serialized };
}

function persistHistoricalReplayApprovals(db, incoming) {
  const current = readHistoricalReplayLedger(db);
  if (current.length === 0 && incoming.length === 0) return mergeHistoricalReplayApprovals([], []);
  db.exec('BEGIN IMMEDIATE');
  try {
    // Re-read under the writer lock so concurrent starts cannot discard bindings.
    const merged = mergeHistoricalReplayApprovals(readHistoricalReplayLedger(db), incoming);
    const previous = db.prepare('SELECT value FROM core_metadata WHERE key = ?').get(HISTORICAL_REPLAY_APPROVALS_KEY);
    if (previous?.value !== merged.serialized) {
      db.prepare('INSERT INTO core_metadata(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value')
        .run(HISTORICAL_REPLAY_APPROVALS_KEY, merged.serialized);
    }
    db.exec('COMMIT');
    return merged;
  } catch (error) {
    db.exec('ROLLBACK');
    throw error;
  }
}


const LOCAL_TRANSCRIPT_GRANTS_MAX_BYTES = 32 * 1024;
const LOCAL_TRANSCRIPT_GRANTS_MAX_ENTRIES = 16;
const RESERVED_TRANSCRIPT_ORIGIN = /^(frontend:|v3-history-|core-companion:|core:|worker:)/i;

function invalidLocalTranscriptGrants() {
  return new CoreStoreError('local_transcript_grants_invalid',
    'Local transcript grants are invalid.', { status: 503 });
}

function parseLocalTranscriptGrants(text) {
  try {
    if (Buffer.byteLength(text, 'utf8') > LOCAL_TRANSCRIPT_GRANTS_MAX_BYTES) throw invalidLocalTranscriptGrants();
    const document = JSON.parse(text);
    if (!document || Array.isArray(document)
      || Object.keys(document).sort().join(',') !== 'grants,version'
      || document.version !== 1 || !Array.isArray(document.grants)
      || document.grants.length > LOCAL_TRANSCRIPT_GRANTS_MAX_ENTRIES) throw invalidLocalTranscriptGrants();
    const grants = new Map();
    for (const grant of document.grants) {
      if (!grant || Array.isArray(grant)
        || Object.keys(grant).sort().join(',') !== 'character_id,credential_sha256,device_id,from_created_at_ms'
        || ![grant.device_id, grant.character_id].every((value) =>
          typeof value === 'string' && value.length > 0 && value.length <= 128 && value.trim() === value)
        || RESERVED_TRANSCRIPT_ORIGIN.test(grant.device_id)
        || typeof grant.credential_sha256 !== 'string' || !/^[a-fA-F0-9]{64}$/.test(grant.credential_sha256)
        || !Number.isSafeInteger(grant.from_created_at_ms) || grant.from_created_at_ms <= 0
        || grants.has(grant.device_id)) throw invalidLocalTranscriptGrants();
      grants.set(grant.device_id, Object.freeze({
        device_id: grant.device_id, character_id: grant.character_id,
        credential_sha256: grant.credential_sha256.toLowerCase(),
        from_created_at_ms: grant.from_created_at_ms,
      }));
    }
    return grants;
  } catch {
    throw invalidLocalTranscriptGrants();
  }
}

function readLocalTranscriptGrants(filePath) {
  let descriptor;
  try {
    let current = path.resolve(filePath);
    while (true) {
      try {
        if (lstatSync(current).isSymbolicLink()) throw invalidLocalTranscriptGrants();
      } catch (error) {
        if (error.code !== 'ENOENT') throw error;
      }
      const parent = path.dirname(current);
      if (parent === current) break;
      current = parent;
    }
    descriptor = openSync(filePath, 'r');
  } catch (error) {
    if (error.code === 'ENOENT') return new Map();
    throw invalidLocalTranscriptGrants();
  }
  try {
    const opened = fstatSync(descriptor);
    const named = lstatSync(filePath);
    if (!opened.isFile() || named.isSymbolicLink()
      || opened.dev !== named.dev || opened.ino !== named.ino) throw invalidLocalTranscriptGrants();
    const buffer = Buffer.alloc(LOCAL_TRANSCRIPT_GRANTS_MAX_BYTES + 1);
    let length = 0;
    while (length < buffer.length) {
      const count = readSync(descriptor, buffer, length, buffer.length - length, null);
      if (count === 0) break;
      length += count;
    }
    if (length > LOCAL_TRANSCRIPT_GRANTS_MAX_BYTES) throw invalidLocalTranscriptGrants();
    return parseLocalTranscriptGrants(new TextDecoder('utf-8', { fatal: true }).decode(buffer.subarray(0, length)));
  } catch {
    throw invalidLocalTranscriptGrants();
  } finally {
    closeSync(descriptor);
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

function canonicalDatabasePath(databasePath) {
  const resolved = path.resolve(databasePath);
  let canonical;
  if (existsSync(resolved)) {
    canonical = realpathSync.native(resolved);
  } else {
    const missing = [];
    let ancestor = resolved;
    while (!existsSync(ancestor)) {
      missing.unshift(path.basename(ancestor));
      const parent = path.dirname(ancestor);
      if (parent === ancestor) break;
      ancestor = parent;
    }
    const realAncestor = existsSync(ancestor) ? realpathSync.native(ancestor) : ancestor;
    canonical = path.join(realAncestor, ...missing);
  }
  return path.normalize(canonical);
}

export function activityDatabaseBindingDigest(databasePath) {
  return createHash('sha256')
    .update(`activity-live-path:${canonicalDatabasePath(databasePath)}`)
    .digest('hex');
}

function coreTableExists(db, name) {
  return Boolean(db.prepare("SELECT 1 AS found FROM sqlite_master WHERE type='table' AND name=?").get(name));
}

function activityRetentionDebt(db, now) {
  const cutoff = now - ACTIVITY_RAW_RETENTION_MS;
  const checks = [
    ['activity_events', 'received_at_ms<=?', cutoff],
    ['activity_changes', 'occurred_at_ms<=?', cutoff],
    ['activity_event_tombstones', 'expires_at_ms<=?', now],
    ['activity_audit', 'expires_at_ms<=?', now],
    ['activity_probe_state', 'last_received_at_ms IS NOT NULL AND last_received_at_ms<=?', cutoff],
    ['activity_rate_limits', 'window_start_ms<=?', cutoff],
    ['activity_projections', 'received_at_ms IS NOT NULL AND received_at_ms<=?', cutoff],
  ];
  return checks.filter(([table, predicate, value]) => (
    coreTableExists(db, table)
    && Boolean(db.prepare(`SELECT 1 AS found FROM ${table} WHERE ${predicate} LIMIT 1`).get(value))
  )).map(([table]) => table);
}

function assertConfiguredAuthoritySecretSeparation({
  activityAdminSecret = null,
  workerSecret = null,
  pairingCode = null,
  shortcutMailTokenHash = null,
} = {}) {
  const configured = [activityAdminSecret, workerSecret, pairingCode].filter((value) => typeof value === 'string');
  if (new Set(configured).size !== configured.length) {
    throw new CoreStoreError('authority_secret_conflict', 'Core authority credentials are not domain-separated.', { status: 503 });
  }
  if (shortcutMailTokenHash !== null) {
    if (typeof shortcutMailTokenHash !== 'string' || !/^[a-f0-9]{64}$/i.test(shortcutMailTokenHash)) {
      throw new CoreStoreError('invalid_authority_configuration', 'Core authority credential configuration is invalid.', { status: 503 });
    }
    if (configured.map(tokenDigest).includes(shortcutMailTokenHash.toLowerCase())) {
      throw new CoreStoreError('authority_secret_conflict', 'Core authority credentials are not domain-separated.', { status: 503 });
    }
  }
  return { configured, shortcutMailTokenHash: shortcutMailTokenHash?.toLowerCase() ?? null };
}

export function assertAuthoritySecretSeparationInDatabase(db, {
  activityAdminSecret = null,
  workerSecret = null,
  pairingCode = null,
  shortcutMailTokenHash = null,
  now = Date.now(),
} = {}) {
  const { configured, shortcutMailTokenHash: normalizedMailTokenHash } = assertConfiguredAuthoritySecretSeparation({
    activityAdminSecret,
    workerSecret,
    pairingCode,
    shortcutMailTokenHash,
  });
  const credentialHashes = [];
  if (coreTableExists(db, 'devices')) credentialHashes.push(...db.prepare('SELECT token_hash AS value FROM devices').all().map((row) => row.value));
  if (coreTableExists(db, 'activity_credentials')) credentialHashes.push(...db.prepare('SELECT token_hash AS value FROM activity_credentials').all().map((row) => row.value));
  const consumedPairingHashes = coreTableExists(db, 'consumed_pairing_codes')
    ? db.prepare('SELECT code_hash AS value FROM consumed_pairing_codes').all().map((row) => row.value)
    : [];
  const activeLeaseHashes = coreTableExists(db, 'worker_leases')
    ? db.prepare('SELECT lease_token_hash AS value FROM worker_leases WHERE expires_at_ms>?').all(now).map((row) => row.value)
    : [];
  const universalPersistent = new Set([
    ...credentialHashes,
    ...activeLeaseHashes,
    ...(normalizedMailTokenHash ? [normalizedMailTokenHash] : []),
  ]);
  const adminWorkerDigests = [activityAdminSecret, workerSecret].filter((value) => typeof value === 'string').map(tokenDigest);
  const pairingDigests = [pairingCode].filter((value) => typeof value === 'string').map(tokenDigest);
  const conflict = adminWorkerDigests.some((digest) => universalPersistent.has(digest) || consumedPairingHashes.includes(digest))
    || pairingDigests.some((digest) => universalPersistent.has(digest))
    || (
      normalizedMailTokenHash
      && (
        credentialHashes.includes(normalizedMailTokenHash)
        || consumedPairingHashes.includes(normalizedMailTokenHash)
        || activeLeaseHashes.includes(normalizedMailTokenHash)
      )
    );
  if (conflict) {
    throw new CoreStoreError('authority_secret_conflict', 'Core authority credentials are not domain-separated.', { status: 503 });
  }
  return { ok: true };
}

export function preflightAuthoritySecretSeparation(databasePath, options = {}) {
  assertConfiguredAuthoritySecretSeparation(options);
  if (!existsSync(databasePath)) return { ok: true };
  try {
    const db = new DatabaseSync(databasePath, { readOnly: true });
    try {
      return assertAuthoritySecretSeparationInDatabase(db, options);
    } finally {
      db.close();
    }
  } catch (error) {
    if (error?.code === 'ERR_SQLITE_CANTOPEN') return { ok: true };
    throw error;
  }
}

export function preflightActivityDatabaseRole(databasePath, { allowDormantBackup = false } = {}) {
  if (!existsSync(databasePath)) return { ok: true, role: null };
  try {
    const db = new DatabaseSync(databasePath, { readOnly: true });
    try {
      if (!coreTableExists(db, 'activity_metadata')) return { ok: true, role: null };
      const role = db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get()?.value ?? null;
      if (role === 'backup_read_only') {
        throw new CoreStoreError(
          'backup_activation_unsupported',
          'Activity backup databases are whole-Core read-only verification candidates.',
          { status: 503 },
        );
      }
      if (role !== null && role !== 'live') {
        throw new CoreStoreError('activity_schema_not_ready', 'Activity database role is invalid.', { status: 503 });
      }
      return { ok: true, role };
    } finally {
      db.close();
    }
  } catch (error) {
    if (error?.code === 'ERR_SQLITE_CANTOPEN') return { ok: true, role: null };
    throw error;
  }
}

export function preflightActivityDatabaseBinding(databasePath, expectedDigest) {
  if (typeof expectedDigest !== 'string' || !/^[a-f0-9]{64}$/.test(expectedDigest)) {
    throw new CoreStoreError('activity_database_binding_invalid', 'Activity database path binding is invalid.', { status: 503 });
  }
  if (!existsSync(databasePath)) return { ok: true, legacyUnbound: false };
  const db = new DatabaseSync(databasePath, { readOnly: true });
  try {
    if (!coreTableExists(db, 'activity_metadata')) return { ok: true, legacyUnbound: false };
    const actual = db.prepare("SELECT value FROM activity_metadata WHERE key='database_binding_digest'").get()?.value ?? null;
    if (actual === null) {
      const version = db.prepare("SELECT value FROM core_metadata WHERE key='activity_schema_version'").get()?.value ?? null;
      if (['1', '2', '3'].includes(version)) {
        preflightActivityLegacyMigration(db);
        return { ok: true, legacyUnbound: true };
      }
      throw new CoreStoreError('activity_database_binding_invalid', 'Activity database path binding is missing.', { status: 503 });
    }
    if (!/^[a-f0-9]{64}$/.test(actual)) {
      throw new CoreStoreError('activity_database_binding_invalid', 'Activity database path binding is invalid.', { status: 503 });
    }
    if (actual !== expectedDigest) {
      throw new CoreStoreError(
        'activity_database_binding_mismatch',
        'Activity database is bound to a different canonical live path.',
        { status: 503 },
      );
    }
    preflightActivityLegacyMigration(db, { expectedDatabaseBindingDigest: expectedDigest });
    return { ok: true, legacyUnbound: false };
  } finally {
    db.close();
  }
}

export function preflightCoreIdentity(databasePath) {
  if (!existsSync(databasePath)) return { ok: true, fresh: true };
  const db = new DatabaseSync(databasePath, { readOnly: true });
  try {
    const tables = db.prepare(`SELECT name FROM sqlite_master
      WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name`).all().map((row) => row.name);
    if (!tables.length) return { ok: true, fresh: true };
    if (!tables.includes('core_metadata')) {
      throw new CoreStoreError('core_metadata_invariant_failed', 'Existing Core database identity metadata is invalid.', { status: 503 });
    }
    const metadata = new Map(db.prepare('SELECT key,value FROM core_metadata').all().map((row) => [row.key, row.value]));
    const schemaVersion = metadata.get('schema_version');
    const nodeId = metadata.get('node_id');
    const cursorSecret = metadata.get('cursor_secret');
    if (!/^[45]$/.test(schemaVersion ?? '')) {
      throw new CoreStoreError(
        'unsupported_core_schema_version',
        'Core schema version is not compatible with this binary.',
        { status: 503 },
      );
    }
    if (
      !/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(nodeId ?? '')
      || !/^[A-Za-z0-9_-]{43}$/.test(cursorSecret ?? '')
    ) {
      throw new CoreStoreError('core_metadata_invariant_failed', 'Existing Core database identity metadata is invalid.', { status: 503 });
    }
    return { ok: true, fresh: false, schemaVersion, nodeId, cursorSecret };
  } finally {
    db.close();
  }
}

function withReadOnlyActivitySnapshot(databasePath, inspect, { allowMissing = false } = {}) {
  const suffixes = ['', '-journal', '-wal', '-shm'];
  if (!existsSync(databasePath)) {
    if (suffixes.slice(1).some((suffix) => existsSync(`${databasePath}${suffix}`))) {
      throw new CoreStoreError('core_metadata_invariant_failed', 'Core main database is missing while SQLite sidecar evidence exists.', { status: 503 });
    }
    if (allowMissing) return;
    throw new CoreStoreError('recovery_lineage_unverified', 'Activity recovery candidate has no verifiable authority lineage.', { status: 409 });
  }
  const capture = () => suffixes.map((suffix) => {
    const filename = `${databasePath}${suffix}`;
    return existsSync(filename) ? readFileSync(filename) : null;
  });
  const fingerprint = (files) => files.map((bytes) => bytes == null ? null
    : `${bytes.length}:${createHash('sha256').update(bytes).digest('hex')}`).join('|');
  let temporaryDirectory = null;
  let db;
  const before = capture();
  try {
    if (before.slice(1).some((bytes) => bytes != null)) {
      // Never ask SQLite to open the source WAL/journal: even readOnly=true can
      // create sidecars or update its shared-memory read marks. Recovery and
      // classification happen only in an owned temporary copy of the full view.
      temporaryDirectory = mkdtempSync(path.join(tmpdir(), 'activity-preflight-'));
      const candidate = path.join(temporaryDirectory, 'candidate.sqlite');
      before.forEach((bytes, index) => {
        if (bytes != null) writeFileSync(`${candidate}${suffixes[index]}`, bytes);
      });
      if (fingerprint(before) !== fingerprint(capture())) {
        throw new CoreStoreError('activity_preflight_unstable', 'Activity database changed during read-only preflight.', { status: 503 });
      }
      db = new DatabaseSync(candidate);
    } else {
      // Proven sidecar-free snapshots may use immutable mode, which does not
      // synthesize an empty WAL/SHM for a clean WAL-mode main database.
      db = new DatabaseSync(`${pathToFileURL(path.resolve(databasePath)).href}?mode=ro&immutable=1`, { readOnly: true });
    }
    return inspect(db);
  } finally {
    db?.close();
    if (temporaryDirectory) rmSync(temporaryDirectory, { recursive: true, force: true });
    if (fingerprint(before) !== fingerprint(capture())) {
      throw new CoreStoreError('activity_preflight_unstable', 'Activity database changed during read-only preflight.', { status: 503 });
    }
  }
}

function assertSupportedActivityCommitment(db) {
  if (!coreTableExists(db, 'core_metadata')) return;
  const version = db.prepare("SELECT value FROM core_metadata WHERE key='activity_schema_version'").get()?.value;
  if (version !== '5') return; // New databases and canonical legacy upgrades keep their own preflight.
  const commitment = coreTableExists(db, 'activity_metadata')
    ? db.prepare("SELECT value FROM activity_metadata WHERE key='integrity_commitment_version'").get()?.value : null;
  if (commitment !== String(ACTIVITY_INTEGRITY_COMMITMENT_VERSION)) {
    throw new CoreStoreError('activity_integrity_upgrade_unsupported', 'Existing activity integrity commitment cannot be upgraded automatically.', { status: 503 });
  }
}

export function preflightActivityCommitmentVersion(databasePath) {
  return withReadOnlyActivitySnapshot(databasePath, assertSupportedActivityCommitment, { allowMissing: true });
}

export function verifyActivityRecoveryCandidate(databasePath, floor) {
  return withReadOnlyActivitySnapshot(databasePath, (db) => {
    assertSupportedActivityCommitment(db);
    if (!coreTableExists(db, 'core_metadata')) {
      throw new CoreStoreError('recovery_lineage_unverified', 'Activity recovery candidate has no verifiable authority lineage.', { status: 409 });
    }
    const nodeId = db.prepare("SELECT value FROM core_metadata WHERE key='node_id'").get()?.value;
    const cursorSecret = db.prepare("SELECT value FROM core_metadata WHERE key='cursor_secret'").get()?.value;
    if (!nodeId || !cursorSecret) {
      throw new CoreStoreError('recovery_lineage_unverified', 'Activity recovery candidate has no verifiable authority lineage.', { status: 409 });
    }
    const result = assertActivityRecoveryFloorForDatabase(db, floor, { nodeId, cursorSecret });
    return { ...result, activation_authorized: false };
  });
}

function cleanupSqliteStaging(stagingPath) {
  for (const candidate of [stagingPath, `${stagingPath}-wal`, `${stagingPath}-shm`, `${stagingPath}-journal`]) {
    if (existsSync(candidate)) unlinkSync(candidate);
  }
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
        ? 'Only user or companion messages are accepted here.'
        : 'Remote clients may only submit user messages.',
      { status: 403 },
    );
  }
  return message;
}

export class ICoreStore {
  #localTranscriptGrants;

  constructor(databasePath, {
    companionReplyJobsEnabled = false,
    localTranscriptGrants = undefined,
    localTranscriptGrantsPath = path.join(path.dirname(databasePath), 'local-transcript-grants.json'),
    historicalReplayApprovalsPath = path.join(path.dirname(databasePath), 'historical-replay-approvals.json'),
    clock = Date.now,
    activityRecoveryFloor = null,
    activityRuntimeId = undefined,
    activityRuntimeLeaseMs = undefined,
    activityEnabled = false,
    activityAutoActivate = true,
    eventIdPrefixFactory = undefined,
    testOnlyActivityMigrationHook = undefined,
  } = {}) {
    // Grants are revocable startup configuration, never merged into a durable ledger.
    this.#localTranscriptGrants = localTranscriptGrants === undefined
      ? readLocalTranscriptGrants(localTranscriptGrantsPath)
      : parseLocalTranscriptGrants(JSON.stringify(localTranscriptGrants));
    const replayApprovals = readHistoricalReplayApprovalFile(historicalReplayApprovalsPath);
    preflightActivityCommitmentVersion(databasePath);
    if (activityRecoveryFloor) {
      verifyActivityRecoveryCandidate(databasePath, activityRecoveryFloor);
      throw new CoreStoreError(
        'backup_activation_unsupported',
        'Recovery candidate verification is offline-only; this binary cannot activate a backup.',
        { status: 503 },
      );
    }
    const coreIdentity = preflightCoreIdentity(databasePath);
    const rolePreflight = preflightActivityDatabaseRole(databasePath, { allowDormantBackup: !activityEnabled });
    const databaseBindingDigest = activityDatabaseBindingDigest(databasePath);
    if (rolePreflight.role !== 'backup_read_only') {
      preflightActivityDatabaseBinding(databasePath, databaseBindingDigest);
    }
    mkdirSync(path.dirname(databasePath), { recursive: true });
    this.db = new DatabaseSync(databasePath);
    this.companionReplyJobsEnabled = companionReplyJobsEnabled;
    this.clock = clock;
    try {
      mergeHistoricalReplayApprovals(readHistoricalReplayLedger(this.db), replayApprovals);
      this.db.exec('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;');
      this.#migrate();
      this.nodeId = coreIdentity.fresh
        ? this.#setMetadata('node_id', randomUUID())
        : coreIdentity.nodeId;
      this.cursorSecret = coreIdentity.fresh
        ? this.#setMetadata('cursor_secret', randomBytes(32).toString('base64url'))
        : coreIdentity.cursorSecret;
      this.activity = new ActivityControlPlane(this.db, {
        nodeId: this.nodeId,
        cursorSecret: this.cursorSecret,
        clock,
        ...(activityRuntimeId === undefined ? {} : { runtimeId: activityRuntimeId }),
        ...(activityRuntimeLeaseMs === undefined ? {} : { runtimeLeaseMs: activityRuntimeLeaseMs }),
        databaseBindingDigest,
        active: activityEnabled && activityAutoActivate,
        readOnlyDormant: rolePreflight.role === 'backup_read_only',
        ...(eventIdPrefixFactory === undefined ? {} : { eventIdPrefixFactory }),
        ...(testOnlyActivityMigrationHook === undefined ? {} : { testOnlyMigrationHook: testOnlyActivityMigrationHook }),
      });
      persistHistoricalReplayApprovals(this.db, replayApprovals);
    } catch (error) {
      this.db.close();
      throw error;
    }
  }

  #migrate() {
    const existingMetadata = this.db.prepare("SELECT 1 AS found FROM sqlite_master WHERE type='table' AND name='core_metadata'").get();
    if (existingMetadata) {
      const rawVersion = this.db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get()?.value;
      if (rawVersion != null && !/^[45]$/.test(rawVersion)) {
        throw new CoreStoreError(
          'unsupported_core_schema_version',
          'Core schema version is not compatible with this binary.',
          { status: 503 },
        );
      }
    }
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
    this.db.prepare(`
      INSERT INTO core_metadata(key, value) VALUES ('schema_version', '4')
      ON CONFLICT(key) DO NOTHING
    `).run();
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

  #coreIdentityStatus() {
    try {
      const nodeId = this.#metadata('node_id');
      const cursorSecret = this.#metadata('cursor_secret');
      const schemaVersion = this.#metadata('schema_version');
      const ready = /^[45]$/.test(schemaVersion ?? '')
        && /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(nodeId ?? '')
        && /^[A-Za-z0-9_-]{43}$/.test(cursorSecret ?? '')
        && nodeId === this.nodeId
        && cursorSecret === this.cursorSecret;
      return { ready, reason: ready ? null : 'core_metadata_invariant_failed' };
    } catch {
      return { ready: false, reason: 'core_metadata_invariant_failed' };
    }
  }

  health({ workerLeasesEnabled = false, activityOwnerConfigured = false } = {}) {
    const coreIdentity = this.#coreIdentityStatus();
    // Audit even when Core identity is red so the activity runtime latches the
    // same integrity failure; restoring bytes cannot silently resume authority.
    const activitySchema = this.activity.schemaStatus({ deepAudit: true });
    const activityRuntime = activitySchema.ready
      ? this.activity.runtimeStatus()
      : { ready: false, reason: 'activity_schema_not_ready', takeover_supported: false, backup_activation_supported: false };
    const activityDatabaseRole = activitySchema.ready
      ? this.db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get()?.value ?? null
      : null;
    const permanentlyDisabled = activityDatabaseRole === 'backup_read_only';
    const activityReady = activitySchema.ready && activityRuntime.ready && activityOwnerConfigured && !permanentlyDisabled;
    return {
      ok: coreIdentity.ready,
      node_id: this.nodeId,
      role: 'authority',
      protocol_version: CORE_PROTOCOL_VERSION,
      minimum_protocol_version: CORE_PROTOCOL_VERSION,
      schema_version: Number(this.#metadata('schema_version') ?? 0),
      server_time_ms: Date.now(),
      features: coreIdentity.ready ? [
        'device_pairing',
        'chat_submit',
        'change_feed',
        'cursor_ack',
        ...(workerLeasesEnabled ? ['worker_leases'] : []),
        ...(workerLeasesEnabled && this.companionReplyJobsEnabled
          ? ['companion_reply_jobs']
          : []),
        ...(activityReady ? [ACTIVITY_CONTRACT] : []),
      ] : [],
      activity: {
        contract: ACTIVITY_CONTRACT,
        feature_version: ACTIVITY_FEATURE_VERSION,
        schema_version: activitySchema.schema_version,
        status: !coreIdentity.ready
          ? 'core_metadata_invariant_failed'
          : !activitySchema.ready
            ? 'migration_incomplete'
          : permanentlyDisabled
            ? 'permanently_disabled_after_restore'
          : !activityOwnerConfigured
            ? 'owner_principal_unconfigured'
            : !activityRuntime.ready
              ? 'authority_fenced'
              : 'control_plane_ready',
        control_plane_available: activityReady,
        database_role: activityDatabaseRole,
        runtime_fence: activityRuntime.runtime_fence ?? null,
        takeover_supported: false,
        backup_activation_supported: false,
        clean_close_in_place_only: true,
        crash_recovery_supported: false,
        lease_takeover_supported: false,
        backup_verification_supported: true,
        e2e_available: false,
        collector_available: false,
        summary_client_available: false,
      },
    };
  }

  activateActivity() {
    return this.activity.activate();
  }

  async backupDatabase(destinationPath, {
    includeActivityManifest = this.activity.active,
    failpoint = null,
  } = {}) {
    const backupNow = this.clock();
    if (!this.activity.schemaStatus().ready) {
      throw new CoreStoreError('activity_schema_not_ready', 'Activity schema row integrity audit failed before backup.', { status: 503 });
    }
    if (this.activity.active) {
      this.activity.assertRuntimeAuthority();
      this.activity.runRetention(backupNow);
      if (!this.activity.schemaStatus().ready) {
        throw new CoreStoreError('activity_schema_not_ready', 'Activity schema row integrity audit failed after retention.', { status: 503 });
      }
    }
    const retentionDebt = activityRetentionDebt(this.db, backupNow);
    if (retentionDebt.length) {
      throw new CoreStoreError(
        'activity_retention_authority_required',
        'Activity data due for retention must be cleaned by the active activity authority before backup.',
        { status: 503, details: { tables: retentionDebt } },
      );
    }
    if (includeActivityManifest) this.activity.assertRuntimeAuthority();
    mkdirSync(path.dirname(destinationPath), { recursive: true });
    if (existsSync(destinationPath)) {
      throw new CoreStoreError('backup_destination_exists', 'Backup destination must not already exist.', { status: 409 });
    }
    const stagingPath = path.join(
      path.dirname(destinationPath),
      `.${path.basename(destinationPath)}.${randomUUID()}.activity-backup.tmp`,
    );
    try {
      await backup(this.db, stagingPath);
      if (failpoint === 'after_stage_copy') throw new Error('synthetic backup interruption after stage copy');
      if (includeActivityManifest) this.activity.assertRuntimeAuthority();
      const destination = new DatabaseSync(stagingPath);
      let recoveryManifest;
      try {
        if (coreTableExists(destination, 'activity_metadata')) {
          destination.prepare("UPDATE activity_metadata SET value='backup_read_only' WHERE key='database_role'").run();
        }
        destination.exec('PRAGMA journal_mode=DELETE');
        const verifiedManifest = activityRecoveryManifestForDatabase(destination, {
          nodeId: this.nodeId,
          cursorSecret: this.cursorSecret,
        });
        recoveryManifest = includeActivityManifest ? verifiedManifest : null;
      } finally {
        destination.close();
      }
      if (failpoint === 'after_role_write') throw new Error('synthetic backup interruption after role write');
      renameSync(stagingPath, destinationPath);
      return {
        path: destinationPath,
        activity_schema_version: includeActivityManifest ? this.activity.schemaStatus().schema_version : null,
        retained_watermark: recoveryManifest?.retained_watermark ?? null,
        snapshot_generation: recoveryManifest?.snapshot_generation ?? null,
        recovery_manifest: recoveryManifest,
      };
    } catch (error) {
      cleanupSqliteStaging(stagingPath);
      throw error;
    }
  }

  assertAuthoritySecretSeparation(options = {}) {
    return assertAuthoritySecretSeparationInDatabase(this.db, options);
  }

  rollbackEmptyActivitySchema() {
    this.activity.assertRuntimeAuthority();
    return rollbackActivitySchema(this.db);
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
    const wantsFrontend = platform === EXTERNAL_FRONTEND_PLATFORM;
    if (wantsFrontend !== deviceId.startsWith('frontend:')
      || (wantsFrontend && !EXTERNAL_FRONTEND_DEVICE_ID.test(deviceId))) {
      throw new CoreStoreError(
        'invalid_request',
        'External frontends must pair as frontend:<name> with the external-frontend platform.',
      );
    }
    const token = randomBytes(32).toString('base64url');
    const now = Date.now();
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const previous = this.db.prepare('SELECT platform FROM devices WHERE device_id = ?').get(deviceId);
      if (previous && (previous.platform === EXTERNAL_FRONTEND_PLATFORM) !== wantsFrontend) {
        throw new CoreStoreError(
          'invalid_request',
          'An existing device cannot switch between frontend and ordinary roles.',
          { status: 409 },
        );
      }
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

  #localTranscriptGrant(deviceToken) {
    const device = typeof deviceToken === 'string' && deviceToken
      ? this.db.prepare('SELECT device_id, platform, token_hash FROM devices WHERE token_hash = ?')
        .get(tokenDigest(deviceToken))
      : null;
    if (!device) throw new CoreStoreError('unauthorized', 'A valid device token is required.', { status: 401 });
    const grant = this.#localTranscriptGrants.get(device.device_id);
    if (device.platform !== 'android' || RESERVED_TRANSCRIPT_ORIGIN.test(device.device_id)
      || !grant || grant.credential_sha256 !== device.token_hash) return null;
    return grant;
  }

  localTranscriptCapabilities(deviceToken) {
    const grant = this.#localTranscriptGrant(deviceToken);
    return grant ? {
      enabled: true, character_id: grant.character_id,
      from_created_at_ms: grant.from_created_at_ms,
    } : { enabled: false };
  }

  submitLocalTranscripts(deviceToken, raw) {
    const grant = this.#localTranscriptGrant(deviceToken);
    if (!grant) throw new CoreStoreError('local_transcript_forbidden',
      'This device is not authorized to submit local transcripts.', { status: 403 });
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)
      || Object.keys(raw).some((key) => !['device_id', 'messages', 'request_companion_reply'].includes(key))) {
      throw new CoreStoreError('invalid_request', 'Local transcript body has unsupported fields.');
    }
    if (raw.device_id !== grant.device_id) {
      throw new CoreStoreError('device_mismatch', 'device_id must match the authenticated device.', { status: 403 });
    }
    if (raw.request_companion_reply !== undefined && raw.request_companion_reply !== false) {
      throw new CoreStoreError('invalid_request', 'Local transcripts cannot request a generated reply.');
    }
    if (!Array.isArray(raw.messages) || raw.messages.length === 0 || raw.messages.length > MAX_MESSAGE_BATCH) {
      throw new CoreStoreError('invalid_request', 'Local transcripts require a bounded non-empty message batch.');
    }
    const messages = raw.messages.map((rawMessage) => {
      const message = normalizeMessage(rawMessage, grant.device_id, { allowCompanion: true });
      if (message.character_id !== grant.character_id || message.message_type !== 'chat'
        || message.created_at_ms < grant.from_created_at_ms
        || message.asset_refs.length !== 0 || message.addenda.length !== 0) {
        throw new CoreStoreError('local_transcript_scope_mismatch',
          'The message is outside this local transcript grant.', { status: 403 });
      }
      return message;
    }).sort((left, right) => left.origin_sequence - right.origin_sequence);
    return this.#persistMessages(messages, {
      submitDeviceId: grant.device_id,
      allowApprovedHistoricalReplay: false,
      enqueueCompanionReplies: false,
    });
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
    const device = this.db.prepare(`
      SELECT device_id, platform FROM devices WHERE device_id = ?
    `).get(authenticatedDeviceId);
    const frontend = isExternalFrontendDevice(device);
    if (frontend && raw?.request_companion_reply === true) {
      throw new CoreStoreError(
        'invalid_request',
        'External frontends submit finished turns and cannot request core replies.',
        { status: 403 },
      );
    }
    const messages = raw.messages
      .map((message) => normalizeMessage(message, authenticatedDeviceId, { allowCompanion: frontend }))
      .sort((left, right) => left.origin_sequence - right.origin_sequence);
    return this.#persistMessages(messages, {
      submitDeviceId: authenticatedDeviceId,
      allowApprovedHistoricalReplay: Boolean(device) && !frontend
        && device.platform !== EXTERNAL_FRONTEND_PLATFORM
        && !['local-import', 'core-worker', 'core-authority'].includes(device.platform)
        && !/^(v3-history-|core-companion:)/.test(device.device_id)
        && raw?.request_companion_reply !== true,
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

  completeCompanionReplyShadow(raw, now = Date.now()) {
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
    const model = requiredString(raw?.model, 'model');
    const durationMs = requiredInteger(raw?.duration_ms, 'duration_ms', { minimum: 0 });
    const replyCharacters = requiredInteger(
      raw?.reply_characters,
      'reply_characters',
      { minimum: 0 },
    );
    const job = this.db.prepare(`
      SELECT status, claimed_by, claim_fencing_token
      FROM companion_reply_jobs WHERE job_id = ?
    `).get(jobId);
    if (!job) {
      throw new CoreStoreError(
        'job_not_found',
        'The companion reply job does not exist.',
        { status: 404 },
      );
    }
    const existing = this.db.prepare(`
      SELECT model, duration_ms, reply_characters, completed_at_ms
      FROM companion_reply_shadow_runs WHERE job_id = ?
    `).get(jobId);
    if (job.status === 'completed' && existing) {
      return {
        job_id: jobId,
        status: 'shadow_completed',
        duplicate: true,
        completed_at_ms: Number(existing.completed_at_ms),
      };
    }
    if (
      job.status !== 'claimed' ||
      job.claimed_by !== lease.holderId ||
      Number(job.claim_fencing_token) !== lease.fencingToken
    ) {
      throw new CoreStoreError(
        'stale_job_claim',
        'The companion reply job is no longer claimed by this lease.',
        { status: 409 },
      );
    }
    this.db.exec('BEGIN IMMEDIATE');
    try {
      this.db.prepare(`
        INSERT INTO companion_reply_shadow_runs(
          job_id, holder_id, fencing_token, model, duration_ms,
          reply_characters, completed_at_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      `).run(
        jobId,
        lease.holderId,
        lease.fencingToken,
        model,
        durationMs,
        replyCharacters,
        now,
      );
      this.db.prepare(`
        UPDATE companion_reply_jobs
        SET status = 'completed', completed_at_ms = ?, updated_at_ms = ?
        WHERE job_id = ? AND status = 'claimed'
          AND claimed_by = ? AND claim_fencing_token = ?
      `).run(now, now, jobId, lease.holderId, lease.fencingToken);
      this.db.exec('COMMIT');
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
    return {
      job_id: jobId,
      status: 'shadow_completed',
      duplicate: false,
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
    submitDeviceId = null,
    allowApprovedHistoricalReplay = false,
  } = {}) {
    const results = [];
    this.db.exec('BEGIN IMMEDIATE');
    try {
      // Read on every transaction: another process may have appended bindings.
      const approvals = mergeHistoricalReplayApprovals(readHistoricalReplayLedger(this.db), []);
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
        const approval = approvals.bySyncId.get(message.sync_id);
        const alias = approvals.bySequence.get(replaySequenceKey(message.origin_device_id, message.origin_sequence));
        if (alias && (!submitDeviceId || alias.sync_id !== message.sync_id || alias.incoming_digest !== digest)) {
          throw new CoreStoreError('origin_sequence_conflict', 'origin_sequence is reserved by a historical replay binding.', { status: 409 });
        }
        if (approval && submitDeviceId && (approval.device_id !== submitDeviceId
          || approval.device_id !== message.origin_device_id
          || approval.origin_sequence !== message.origin_sequence || approval.incoming_digest !== digest)) {
          throw new CoreStoreError('immutable_message_conflict', 'Historical replay does not match its immutable approval.', { status: 409 });
        }
        const sequenceCollision = this.db.prepare(`
          SELECT sync_id FROM chat_messages
          WHERE origin_device_id = ? AND origin_sequence = ?
        `).get(message.origin_device_id, message.origin_sequence);
        if (sequenceCollision && sequenceCollision.sync_id !== message.sync_id) {
          throw new CoreStoreError('origin_sequence_conflict', 'origin_sequence already points to another message.', { status: 409 });
        }
        const existing = this.db.prepare(`
          SELECT canonical_digest, server_sequence, character_id, sender,
                 content, created_at_ms, message_type, origin_device_id, origin_sequence,
                 asset_refs_json, addenda_json
          FROM chat_messages WHERE sync_id = ?
        `).get(message.sync_id);
        if (existing) {
          const approvedReplay = allowApprovedHistoricalReplay && approval
            && approval.existing_digest === existing.canonical_digest
            && approval.incoming_digest === digest
            && /^v3-history-[a-f0-9]{20}$/.test(existing.origin_device_id)
            && existing.sender === 'user' && message.sender === 'user'
            && canonicalDigest({
              sync_id: message.sync_id,
              origin_device_id: existing.origin_device_id,
              origin_sequence: Number(existing.origin_sequence),
              character_id: existing.character_id, sender: existing.sender,
              content: existing.content, created_at_ms: Number(existing.created_at_ms),
              message_type: existing.message_type,
              asset_refs: JSON.parse(existing.asset_refs_json),
              addenda: JSON.parse(existing.addenda_json),
            }) === approval.existing_digest;
          const sameSemanticMessage =
            existing.character_id === message.character_id &&
            existing.sender === message.sender &&
            existing.content === message.content &&
            Math.abs(Number(existing.created_at_ms) - message.created_at_ms) < 1000 &&
            existing.message_type === message.message_type;
          if (
            existing.canonical_digest !== digest &&
            !(allowSemanticExisting && sameSemanticMessage) && !approvedReplay
          ) {
            throw new CoreStoreError(
              'immutable_message_conflict',
              'sync_id already exists with different immutable content.',
              { status: 409, details: { sync_id: message.sync_id } },
            );
          }
          results.push({
            sync_id: message.sync_id,
            status: 'duplicate',
            server_sequence: Number(existing.server_sequence),
          });
          continue;
        }
        if (approval && submitDeviceId) {
          throw new CoreStoreError('immutable_message_conflict', 'Historical replay approval cannot create a message.', { status: 409 });
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
    try {
      this.activity?.releaseRuntimeClaim();
    } finally {
      this.db.close();
    }
  }
}
