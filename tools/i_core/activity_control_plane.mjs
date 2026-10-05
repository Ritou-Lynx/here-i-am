import { createHash, createHmac, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';

export const ACTIVITY_CONTRACT = 'device.activity.v1';
export const ACTIVITY_FEATURE_VERSION = 1;
export const ACTIVITY_SCHEMA_VERSION = 5;
export const ACTIVITY_RAW_RETENTION_MS = 24 * 60 * 60 * 1000;
export const ACTIVITY_MAX_TTL_MS = ACTIVITY_RAW_RETENTION_MS;
export const ACTIVITY_MAX_BATCH_ITEMS = 100;
export const ACTIVITY_MAX_PAYLOAD_BYTES = 4096;
export const ACTIVITY_MAX_ENVELOPE_BYTES = 8192;
export const ACTIVITY_MAX_REQUEST_BYTES = 512 * 1024;
export const ACTIVITY_RATE_WINDOW_MS = 60_000;
export const ACTIVITY_RATE_MAX_EVENTS = 120;
export const ACTIVITY_FUTURE_SKEW_MS = 5 * 60 * 1000;
export const ACTIVITY_RUNTIME_LEASE_MS = 30_000;

export const ACTIVITY_SOURCES = Object.freeze([
  'windows_wts',
  'windows_last_input',
  'windows_probe',
  'android_usage_events',
  'android_screen_state',
  'android_tasker',
  'iphone_shortcuts',
  'android_ble_hrs_quality',
]);

export const ACTIVITY_KINDS = Object.freeze([
  'probe.heartbeat',
  'session.locked',
  'session.unlocked',
  'input.activity',
  'input.idle_bucket',
  'screen.interactive',
  'screen.non_interactive',
  'app.category_active',
  'focus.sleep_on',
  'focus.sleep_off',
  'power.charging',
  'power.unplugged',
  'network.present',
  'sensor.heart_rate_quality',
  'probe.permission_changed',
  'probe.error',
]);

export const ACTIVITY_STATUS_REASONS = Object.freeze([
  'unobserved',
  'core_restart_gap',
  'future_skew',
  'clock_regression',
  'coverage_gap',
  'coverage_stale',
  'coverage_missing',
  'coverage_invalid',
  'probe_error',
  'permission_unavailable',
  'reachability_only',
  'insufficient_human_evidence',
  'fresh_signal',
  'credential_revoked',
  'ttl_expired',
  'retention_expired',
]);

const REQUIRED_ACTIVITY_TABLES = Object.freeze([
  'activity_schema_migrations',
  'activity_metadata',
  'activity_principals',
  'activity_credentials',
  'activity_changes',
  'activity_events',
  'activity_event_tombstones',
  'activity_replay_lineage_floors',
  'activity_probe_state',
  'activity_projections',
  'activity_reader_acks',
  'activity_rate_limits',
  'activity_audit',
  'activity_deletion_receipts',
  'activity_runtime_claim',
]);

const REQUIRED_ACTIVITY_COLUMNS = Object.freeze({
  activity_principals: [
    'principal_id', 'principal_type', 'device_id', 'probe_id', 'event_id_prefix',
    'retired_event_prefix_digest', 'retired_floor_digest', 'scopes_json',
    'credential_generation', 'revoked_at_ms', 'deleted_at_ms', 'authority_epoch',
  ],
  activity_credentials: ['principal_id', 'generation', 'token_hash', 'revoked_at_ms'],
  activity_events: [
    'event_id', 'device_id', 'probe_id', 'origin_sequence', 'occurred_at_ms',
    'received_at_ms', 'canonical_digest', 'server_sequence', 'authority_epoch',
  ],
  activity_changes: ['server_sequence', 'kind', 'payload_json'],
  activity_replay_lineage_floors: ['lineage_digest', 'floor_digest'],
  activity_probe_state: ['probe_id', 'max_origin_sequence', 'retained_origin_floor'],
  activity_projections: [
    'device_id', 'probe_id', 'state', 'coverage_status', 'clock_health',
    'credential_state', 'status_reason', 'updated_at_ms',
  ],
  activity_runtime_claim: ['singleton', 'runtime_id', 'runtime_fence', 'lease_expires_at_ms'],
});

export const ACTIVITY_INTEGRITY_COMMITMENT_VERSION = 4;

const REQUIRED_ACTIVITY_METADATA = Object.freeze({
  integrity_commitment_version: ACTIVITY_INTEGRITY_COMMITMENT_VERSION,
  server_time_floor_ms: 0,
  retained_watermark: 0,
  snapshot_generation: 1,
  authority_epoch: 1,
  commit_high_water: 0,
  replay_floor_revision: 0,
  replay_floor_count: 0,
  accepted_event_count: 0,
  retired_event_count: 0,
});

const LEGACY_REQUIRED_ACTIVITY_METADATA = Object.freeze({
  retained_watermark: 0,
  snapshot_generation: 1,
  authority_epoch: 1,
  commit_high_water: 0,
});

const REQUIRED_ACTIVITY_DATABASE_ROLES = Object.freeze(['live', 'backup_read_only']);

const REQUIRED_ACTIVITY_PRIMARY_KEYS = Object.freeze({
  activity_schema_migrations: ['version'],
  activity_metadata: ['key'],
  activity_principals: ['principal_id'],
  activity_credentials: ['credential_id'],
  activity_changes: ['server_sequence'],
  activity_events: ['event_id'],
  activity_event_tombstones: ['event_id'],
  activity_replay_lineage_floors: ['lineage_digest'],
  activity_probe_state: ['probe_id'],
  activity_projections: ['device_id', 'probe_id'],
  activity_reader_acks: ['principal_id'],
  activity_rate_limits: ['probe_id'],
  activity_audit: ['audit_id'],
  activity_deletion_receipts: ['receipt_id'],
  activity_runtime_claim: ['singleton'],
});

const REQUIRED_ACTIVITY_UNIQUE_KEYS = Object.freeze({
  activity_principals: [['probe_id'], ['device_id', 'probe_id']],
  activity_credentials: [['token_hash'], ['principal_id', 'generation']],
  activity_changes: [['change_id']],
  activity_events: [['receipt_id'], ['server_sequence'], ['device_id', 'probe_id', 'origin_sequence']],
  activity_event_tombstones: [['device_id', 'probe_id', 'origin_sequence']],
});

const REQUIRED_ACTIVITY_INDEXES = Object.freeze({
  activity_principals_event_prefix_idx: { table: 'activity_principals', columns: ['event_id_prefix'], unique: true },
  activity_changes_subject_idx: { table: 'activity_changes', columns: ['device_id', 'probe_id', 'server_sequence'] },
  activity_events_received_idx: { table: 'activity_events', columns: ['received_at_ms'] },
  activity_audit_expiry_idx: { table: 'activity_audit', columns: ['expires_at_ms'] },
});

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]));
  }
  return value;
}

export function canonicalActivityDigest(value) {
  return createHash('sha256').update(JSON.stringify(canonicalize(value))).digest('hex');
}

function tokenDigest(value) {
  return createHash('sha256').update(value).digest('hex');
}

function replayPrefixDigest(cursorSecret, eventIdPrefix) {
  return createHmac('sha256', cursorSecret)
    .update(`activity-event-prefix:${eventIdPrefix}`)
    .digest('hex');
}

function replayFloorDigest(cursorSecret, eventIdPrefix, floor) {
  return createHmac('sha256', cursorSecret)
    .update(`activity-retired-floor:${eventIdPrefix}:${floor == null ? 'null' : floor}`)
    .digest('hex');
}

// Version-four databases used per-event barriers. These helpers exist only to
// validate and collapse that unpublished layout during its one supported
// in-place migration; version five never writes per-event durable rows.
function legacyReplayEventIdDigest(cursorSecret, eventId) {
  return createHmac('sha256', cursorSecret)
    .update(`activity-event-id:${eventId}`)
    .digest('hex');
}

function legacyReplayCanonicalDigest(cursorSecret, canonicalDigest) {
  return createHmac('sha256', cursorSecret)
    .update(`activity-event-canonical:${canonicalDigest}`)
    .digest('hex');
}

function replayCommitment(db, cursorSecret) {
  const revisionRaw = db.prepare("SELECT value FROM activity_metadata WHERE key='replay_floor_revision'").get()?.value;
  const revision = canonicalMetadataInteger(revisionRaw, 0);
  if (revision == null) return null;
  let root = createHmac('sha256', cursorSecret)
    .update(`activity-replay-root:v5:integrity-v4:${metadataNumber(db, 'authority_epoch')}:${metadataNumber(db, 'commit_high_water')}:${revision}:${metadataNumber(db, 'accepted_event_count')}:${metadataNumber(db, 'retired_event_count')}:${metadataNumber(db, 'retained_watermark')}:${metadataNumber(db, 'snapshot_generation')}:${metadataNumber(db, 'server_time_floor_ms')}`)
    .digest('hex');
  const active = db.prepare(`SELECT p.principal_id,p.device_id,p.probe_id,p.event_id_prefix,s.retained_origin_floor
    FROM activity_principals p
    LEFT JOIN activity_probe_state s ON s.probe_id=p.probe_id
    WHERE p.principal_type='probe' AND p.deleted_at_ms IS NULL
    ORDER BY p.principal_id`).all();
  for (const probe of active) {
    if (
      typeof probe.event_id_prefix !== 'string' || !/^[A-Za-z0-9_-]{22,64}$/.test(probe.event_id_prefix)
      || (probe.retained_origin_floor != null && (!Number.isSafeInteger(probe.retained_origin_floor) || probe.retained_origin_floor < 0))
    ) return null;
    root = createHmac('sha256', cursorSecret)
      .update(`activity-replay-root:v5:${root}:active:${probe.principal_id}:${probe.device_id}:${probe.probe_id}:${probe.event_id_prefix}:${probe.retained_origin_floor == null ? 'null' : probe.retained_origin_floor}`)
      .digest('hex');
  }
  const retired = db.prepare(`SELECT p.principal_id,p.device_id,p.probe_id,p.deleted_at_ms,
      p.retired_event_prefix_digest AS lineage_digest,p.retired_floor_digest AS floor_digest
    FROM activity_principals p
    WHERE p.principal_type='probe' AND p.deleted_at_ms IS NOT NULL
    ORDER BY p.principal_id`).all();
  for (const floor of retired) {
    if (
      typeof floor.lineage_digest !== 'string' || !/^[a-f0-9]{64}$/.test(floor.lineage_digest)
      || typeof floor.floor_digest !== 'string' || !/^[a-f0-9]{64}$/.test(floor.floor_digest)
    ) return null;
    root = createHmac('sha256', cursorSecret)
      .update(`activity-replay-root:v5:${root}:retired:${floor.principal_id}:${floor.device_id}:${floor.probe_id}:${floor.deleted_at_ms}:${floor.lineage_digest}:${floor.floor_digest}`)
      .digest('hex');
  }
  const authorityRows = {
    principals: db.prepare('SELECT * FROM activity_principals ORDER BY principal_id').all(),
    credentials: db.prepare('SELECT * FROM activity_credentials ORDER BY principal_id,generation').all(),
  };
  root = createHmac('sha256', cursorSecret)
    .update(`activity-replay-root:v5:${root}:authority:${canonicalActivityDigest(authorityRows)}`)
    .digest('hex');
  // Replaceable state remains O(probes); retained event/change rows have
  // individually authenticated receipts and are checked in the deep audit.
  for (const [table, order] of [
    ['activity_probe_state', 'probe_id'],
    ['activity_projections', 'device_id,probe_id'],
    ['activity_deletion_receipts', 'receipt_id'],
  ]) {
    root = createHmac('sha256', cursorSecret)
      .update(`activity-integrity:v1:${root}:${table}:`)
      .update(canonicalActivityDigest(db.prepare(`SELECT * FROM ${table} ORDER BY ${order}`).all()))
      .digest('hex');
  }
  return { count: active.length + retired.length, revision, root };
}

function activityChangeSignature(db, change, cursorSecret) {
  const { integrity_signature: ignored, ...payload } = JSON.parse(change.payload_json);
  const event = change.kind === 'activity.event.accepted'
    ? db.prepare('SELECT * FROM activity_events WHERE server_sequence=?').get(change.server_sequence) ?? null
    : null;
  return createHmac('sha256', cursorSecret)
    .update(`activity-change:integrity-v1:${canonicalActivityDigest({
      ...change, payload_json: undefined, payload, event,
    })}`)
    .digest('hex');
}

function activityChangeAuthenticated(db, change, cursorSecret) {
  try {
    const signature = JSON.parse(change.payload_json).integrity_signature;
    return typeof signature === 'string' && /^[a-f0-9]{64}$/.test(signature)
      && signature === activityChangeSignature(db, change, cursorSecret);
  } catch { return false; }
}

function activityChangePayload(change) {
  const { integrity_signature: ignored, ...payload } = JSON.parse(change.payload_json);
  return payload;
}

function activityReceiptObservationValid(observation) {
  const hasKeys = (value, keys) => value && typeof value === 'object' && !Array.isArray(value)
    && Object.keys(value).sort().join(',') === [...keys].sort().join(',');
  const sequence = (value) => Number.isSafeInteger(value) && value >= 0;
  if (!hasKeys(observation, ['coverage_status', 'sequence_diagnostics', 'sequence_coverage', 'projection_recomputed_through_origin_sequence'])) return false;
  const coverage = observation.sequence_coverage;
  if (!hasKeys(coverage, ['highest_seen', 'contiguous_through', 'missing', 'observed_from', 'retained_origin_floor', 'missing_truncated'])) return false;
  if (!sequence(coverage.highest_seen) || !sequence(coverage.observed_from)
    || coverage.observed_from > coverage.highest_seen
    || (coverage.retained_origin_floor != null && (!sequence(coverage.retained_origin_floor) || coverage.retained_origin_floor >= coverage.observed_from))
    || (coverage.contiguous_through != null && (!sequence(coverage.contiguous_through) || coverage.contiguous_through < coverage.observed_from || coverage.contiguous_through > coverage.highest_seen))
    || typeof coverage.missing_truncated !== 'boolean'
    || !Array.isArray(coverage.missing) || coverage.missing.length > 128
    || coverage.missing.some((value, index) => !sequence(value) || value >= coverage.highest_seen
      || value <= (coverage.retained_origin_floor ?? coverage.observed_from)
      || (index > 0 && value <= coverage.missing[index - 1]))
    || (coverage.missing_truncated && coverage.missing.length !== 128)) return false;
  const diagnostics = observation.sequence_diagnostics;
  if (!Array.isArray(diagnostics)
    || !['', 'sequence_regression', 'sequence_coverage_gap', 'sequence_regression,sequence_coverage_gap'].includes(diagnostics.join(','))
    || diagnostics.includes('sequence_coverage_gap') !== (coverage.missing.length > 0)
    || !['gap', 'stale', 'missing', 'invalid', 'covered'].includes(observation.coverage_status)
    || (observation.coverage_status === 'gap') !== (coverage.missing.length > 0)) return false;
  const through = observation.projection_recomputed_through_origin_sequence;
  return through == null || (sequence(through) && through === coverage.highest_seen && coverage.missing.length === 0);
}

function writeReplayCommitment(db, cursorSecret, { advance = false } = {}) {
  if (advance) {
    setMetadataNumber(db, 'replay_floor_revision', metadataNumber(db, 'replay_floor_revision') + 1);
  }
  const commitment = replayCommitment(db, cursorSecret);
  if (!commitment) fail('activity_schema_not_ready', 'Activity replay floor commitment is invalid.', { status: 503 });
  setMetadataNumber(db, 'replay_floor_count', commitment.count);
  db.prepare(`INSERT INTO activity_metadata(key,value) VALUES ('replay_floor_root',?)
    ON CONFLICT(key) DO UPDATE SET value=excluded.value`).run(commitment.root);
  return commitment;
}

function fail(code, message, { status = 400, details = {}, retryable = false } = {}) {
  const error = new Error(message);
  error.name = 'ActivityControlPlaneError';
  error.code = code;
  error.status = status;
  error.retryable = retryable;
  error.details = details;
  throw error;
}

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    fail('invalid_request', `${field} must be an object.`);
  }
  return value;
}

function exactKeys(value, allowed, field) {
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) fail('unknown_field', `${field}.${key} is not allowed.`, { details: { field: `${field}.${key}` } });
  }
}

function requiredKeys(value, required) {
  for (const key of required) {
    if (!Object.hasOwn(value, key)) {
      fail('missing_required_field', `${key} is required.`, { details: { field: key } });
    }
  }
}

function string(value, field, { max = 256 } = {}) {
  if (typeof value !== 'string' || !value.trim() || value.length > max) {
    fail('invalid_request', `${field} must be a non-empty string no longer than ${max} characters.`);
  }
  return value;
}

function opaqueId(value, field, { max = 128 } = {}) {
  const normalized = string(value, field, { max });
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(normalized) || /(?:bearer|token|secret|password|jwt|https?|url|stack)/i.test(normalized)) {
    fail('invalid_identifier', `${field} must be a privacy-safe ASCII opaque identifier.`);
  }
  return normalized;
}

function eventIdentifier(value, field = 'event_id') {
  const normalized = string(value, field, { max: 85 });
  if (!/^[A-Za-z0-9_-]{22,64}\.(?:0|[1-9]\d*)$/.test(normalized)) {
    fail(
      'invalid_event_id',
      `${field} must be the issued event_id_prefix plus a canonical decimal origin_sequence.`,
    );
  }
  return normalized;
}

function structuredEventIdentityMatches(eventId, prefix, originSequence) {
  if (typeof eventId !== 'string' || typeof prefix !== 'string' || !Number.isSafeInteger(originSequence) || originSequence < 0) {
    return false;
  }
  return eventId === `${prefix}.${originSequence}`
    && /^[A-Za-z0-9_-]{22,64}\.(?:0|[1-9]\d*)$/.test(eventId);
}

function diagnosticToken(value, field, { max = 64 } = {}) {
  const normalized = string(value, field, { max });
  if (!/^[a-z][a-z0-9_]*$/.test(normalized) || /(?:bearer|token|secret|password|jwt|https?|url|stack)/i.test(normalized)) {
    fail('invalid_diagnostic_token', `${field} must be a privacy-safe registered diagnostic token.`);
  }
  return normalized;
}

function registrationCapability(value, field) {
  const normalized = string(value, field, { max: 72 });
  if (['activity.write', 'activity.read_summary', 'activity.admin', 'chat.read'].includes(normalized)) return normalized;
  if (normalized.startsWith('probe_error.')) {
    diagnosticToken(normalized.slice('probe_error.'.length), field, { max: 48 });
    return normalized;
  }
  return diagnosticToken(normalized, field);
}

function capabilityArray(value, field) {
  if (!Array.isArray(value) || value.length > 100) {
    fail('invalid_request', `${field} must be an array with at most 100 items.`);
  }
  return [...new Set(value.map((item, index) => registrationCapability(item, `${field}[${index}]`)))];
}

const SERVER_UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const COVERAGE_MODES = Object.freeze(['continuous', 'discrete_best_effort', 'heartbeat_only', 'none', 'unknown']);

function canonicalPersistedArray(raw, normalize) {
  if (typeof raw !== 'string') return null;
  try {
    const parsed = JSON.parse(raw);
    const normalized = normalize(parsed);
    return JSON.stringify(normalized) === raw ? normalized : null;
  } catch {
    return null;
  }
}

function validatePersistedActivityAuthority(db) {
  const principals = db.prepare('SELECT * FROM activity_principals ORDER BY principal_id').all();
  const credentials = db.prepare('SELECT * FROM activity_credentials ORDER BY principal_id,generation').all();
  const credentialsByPrincipal = new Map();
  for (const credential of credentials) {
    const list = credentialsByPrincipal.get(credential.principal_id) ?? [];
    list.push(credential);
    credentialsByPrincipal.set(credential.principal_id, list);
  }
  for (const principal of principals) {
    const expectedPrefix = principal.principal_type === 'probe' ? 'activity-probe:' : 'activity-reader:';
    const principalUuid = typeof principal.principal_id === 'string' && principal.principal_id.startsWith(expectedPrefix)
      ? principal.principal_id.slice(expectedPrefix.length)
      : '';
    const capabilities = canonicalPersistedArray(
      principal.capabilities_json,
      (value) => capabilityArray(value, 'persisted.capabilities'),
    );
    const scopes = canonicalPersistedArray(
      principal.scopes_json,
      (value) => stringArray(value, 'persisted.scopes', {
        allowed: ['activity.write', 'activity.read_summary'],
        maximum: 1,
      }),
    );
    const allowedKinds = canonicalPersistedArray(
      principal.allowed_kinds_json,
      (value) => stringArray(value, 'persisted.allowed_kinds', { allowed: ACTIVITY_KINDS }),
    );
    const generation = principal.credential_generation;
    const pairedAt = principal.paired_at_ms;
    const revokedAt = principal.revoked_at_ms;
    const deletedAt = principal.deleted_at_ms;
    let commonValid = false;
    try {
      string(principal.display_name, 'persisted.display_name');
      commonValid = SERVER_UUID_RE.test(principalUuid)
        && capabilities != null
        && scopes != null
        && allowedKinds != null
        && Number.isSafeInteger(generation) && generation >= 1
        && Number.isSafeInteger(pairedAt) && pairedAt >= 0
        && (revokedAt == null || (Number.isSafeInteger(revokedAt) && revokedAt >= pairedAt))
        && (deletedAt == null || (Number.isSafeInteger(deletedAt) && deletedAt >= pairedAt && revokedAt != null));
    } catch {
      commonValid = false;
    }
    let shapeValid = false;
    if (commonValid && principal.principal_type === 'probe') {
      try {
        opaqueId(principal.device_id, 'persisted.device_id');
        opaqueId(principal.probe_id, 'persisted.probe_id');
        enumValue(principal.source, 'persisted.source', ACTIVITY_SOURCES);
        enumValue(principal.coverage_mode, 'persisted.coverage_mode', COVERAGE_MODES);
        integer(principal.expected_report_interval_ms, 'persisted.expected_report_interval_ms', { minimum: 1, maximum: ACTIVITY_MAX_TTL_MS });
        integer(principal.expiry_slo_ms, 'persisted.expiry_slo_ms', { minimum: 1, maximum: ACTIVITY_MAX_TTL_MS });
        shapeValid = scopes.length === 1
          && scopes[0] === 'activity.write'
          && allowedKinds.length > 0;
      } catch {
        shapeValid = false;
      }
    } else if (commonValid && principal.principal_type === 'summary_reader') {
      try {
        opaqueId(principal.device_id, 'persisted.installation_id');
        shapeValid = principal.probe_id == null
          && principal.event_id_prefix == null
          && principal.retired_event_prefix_digest == null
          && principal.retired_floor_digest == null
          && principal.source == null
          && principal.coverage_mode == null
          && principal.expected_report_interval_ms == null
          && principal.expiry_slo_ms == null
          && scopes.length === 1
          && scopes[0] === 'activity.read_summary'
          && allowedKinds.length === 0;
      } catch {
        shapeValid = false;
      }
    }
    if (!commonValid || !shapeValid) return { ready: false, reason: 'principal_registration_invariant_failed' };

    const principalCredentials = credentialsByPrincipal.get(principal.principal_id) ?? [];
    if (principalCredentials.length !== generation) return { ready: false, reason: 'credential_invariant_failed' };
    for (let index = 0; index < principalCredentials.length; index += 1) {
      const credential = principalCredentials[index];
      const issuedAt = credential.issued_at_ms;
      const credentialRevokedAt = credential.revoked_at_ms;
      const expectedGeneration = index + 1;
      if (
        !SERVER_UUID_RE.test(credential.credential_id)
        || credential.generation !== expectedGeneration
        || typeof credential.token_hash !== 'string'
        || !/^[a-f0-9]{64}$/.test(credential.token_hash)
        || !Number.isSafeInteger(issuedAt)
        || issuedAt < pairedAt
        || (credentialRevokedAt != null && (!Number.isSafeInteger(credentialRevokedAt) || credentialRevokedAt < issuedAt))
        || (
          expectedGeneration === generation && revokedAt == null
            ? credentialRevokedAt != null
            : credentialRevokedAt == null
        )
      ) {
        return { ready: false, reason: 'credential_invariant_failed' };
      }
    }
    credentialsByPrincipal.delete(principal.principal_id);
  }
  if (credentialsByPrincipal.size !== 0) return { ready: false, reason: 'credential_invariant_failed' };
  return { ready: true };
}

function recoveryDigest(body, cursorSecret) {
  return createHmac('sha256', cursorSecret)
    .update(`activity-recovery:${JSON.stringify(canonicalize(body))}`)
    .digest('base64url');
}

function activityHistoryDigest(db) {
  const tables = {
    activity_schema_migrations: db.prepare('SELECT * FROM activity_schema_migrations ORDER BY version').all(),
    activity_metadata: db.prepare("SELECT * FROM activity_metadata WHERE key<>'database_role' ORDER BY key").all(),
    activity_principals: db.prepare('SELECT * FROM activity_principals ORDER BY principal_id').all(),
    activity_credentials: db.prepare('SELECT * FROM activity_credentials ORDER BY credential_id').all(),
    activity_changes: db.prepare('SELECT * FROM activity_changes ORDER BY server_sequence').all(),
    activity_events: db.prepare('SELECT * FROM activity_events ORDER BY event_id').all(),
    activity_event_tombstones: db.prepare('SELECT * FROM activity_event_tombstones ORDER BY event_id').all(),
    activity_replay_lineage_floors: db.prepare('SELECT * FROM activity_replay_lineage_floors ORDER BY lineage_digest').all(),
    activity_probe_state: db.prepare('SELECT * FROM activity_probe_state ORDER BY probe_id').all(),
    activity_projections: db.prepare('SELECT * FROM activity_projections ORDER BY device_id,probe_id').all(),
    activity_reader_acks: db.prepare('SELECT * FROM activity_reader_acks ORDER BY principal_id').all(),
    activity_rate_limits: db.prepare('SELECT * FROM activity_rate_limits ORDER BY probe_id').all(),
    activity_audit: db.prepare('SELECT * FROM activity_audit ORDER BY audit_id').all(),
    activity_deletion_receipts: db.prepare('SELECT * FROM activity_deletion_receipts ORDER BY receipt_id').all(),
    activity_runtime_claim: db.prepare('SELECT * FROM activity_runtime_claim ORDER BY singleton').all(),
  };
  return canonicalActivityDigest(tables);
}

function recoveryBody(db, { nodeId }) {
  const runtime = db.prepare('SELECT runtime_id,runtime_fence,lease_expires_at_ms FROM activity_runtime_claim WHERE singleton=1').get();
  return {
    contract: ACTIVITY_CONTRACT,
    authority: {
      node_id: nodeId,
      epoch: metadataNumber(db, 'authority_epoch'),
    },
    retained_watermark: metadataNumber(db, 'retained_watermark'),
    snapshot_generation: metadataNumber(db, 'snapshot_generation'),
    commit_high_water: metadataNumber(db, 'commit_high_water'),
    latest_change_sequence: Number(
      db.prepare('SELECT COALESCE(MAX(server_sequence),0) AS value FROM activity_changes').get().value,
    ),
    runtime_fence: Number(runtime.runtime_fence),
    runtime_claim: {
      runtime_id: runtime.runtime_id,
      runtime_fence: Number(runtime.runtime_fence),
      lease_expires_at_ms: Number(runtime.lease_expires_at_ms),
    },
    database_role: db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get()?.value,
    history_digest: activityHistoryDigest(db),
    principals: db.prepare(`SELECT principal_id,credential_generation,revoked_at_ms,deleted_at_ms
      FROM activity_principals ORDER BY principal_id`).all().map((row) => ({
      principal_id: row.principal_id,
      credential_generation: Number(row.credential_generation),
      revoked: row.revoked_at_ms != null,
      deleted: row.deleted_at_ms != null,
    })),
  };
}

function normalizeRecoveryFloor(raw, cursorSecret) {
  const floor = object(raw, 'activityRecoveryFloor');
  exactKeys(floor, [
    'contract', 'authority', 'retained_watermark', 'snapshot_generation',
    'commit_high_water', 'latest_change_sequence', 'principals', 'digest',
    'runtime_fence', 'runtime_claim', 'database_role',
    'history_digest',
  ], 'activityRecoveryFloor');
  if (floor.contract !== ACTIVITY_CONTRACT) fail('recovery_lineage_unverified', 'Activity recovery floor contract is invalid.', { status: 409 });
  const authority = object(floor.authority, 'activityRecoveryFloor.authority');
  exactKeys(authority, ['node_id', 'epoch'], 'activityRecoveryFloor.authority');
  const runtimeClaim = object(floor.runtime_claim, 'activityRecoveryFloor.runtime_claim');
  exactKeys(runtimeClaim, ['runtime_id', 'runtime_fence', 'lease_expires_at_ms'], 'activityRecoveryFloor.runtime_claim');
  if (
    typeof runtimeClaim.runtime_id !== 'string'
    || runtimeClaim.runtime_id.length > 128
    || !/^[A-Za-z0-9_-]*$/.test(runtimeClaim.runtime_id)
  ) {
    fail('recovery_lineage_unverified', 'Activity recovery runtime claim is invalid.', { status: 409 });
  }
  const principals = floor.principals;
  if (!Array.isArray(principals)) fail('recovery_lineage_unverified', 'Activity recovery floor principals are invalid.', { status: 409 });
  const seen = new Set();
  const normalizedPrincipals = principals.map((rawPrincipal, index) => {
    const principal = object(rawPrincipal, `activityRecoveryFloor.principals[${index}]`);
    exactKeys(principal, ['principal_id', 'credential_generation', 'revoked', 'deleted'], `activityRecoveryFloor.principals[${index}]`);
    const principalId = string(principal.principal_id, `activityRecoveryFloor.principals[${index}].principal_id`, { max: 128 });
    if (seen.has(principalId)) fail('recovery_lineage_unverified', 'Activity recovery floor principals must be unique.', { status: 409 });
    seen.add(principalId);
    if (typeof principal.revoked !== 'boolean' || typeof principal.deleted !== 'boolean') {
      fail('recovery_lineage_unverified', 'Activity recovery floor principal states are invalid.', { status: 409 });
    }
    return {
      principal_id: principalId,
      credential_generation: integer(principal.credential_generation, `activityRecoveryFloor.principals[${index}].credential_generation`, { minimum: 1 }),
      revoked: principal.revoked,
      deleted: principal.deleted,
    };
  });
  if (normalizedPrincipals.some((principal, index) => index > 0 && principal.principal_id <= normalizedPrincipals[index - 1].principal_id)) {
    fail('recovery_lineage_unverified', 'Activity recovery floor principals must be canonically ordered.', { status: 409 });
  }
  const body = {
    contract: ACTIVITY_CONTRACT,
    authority: {
      node_id: string(authority.node_id, 'activityRecoveryFloor.authority.node_id', { max: 128 }),
      epoch: integer(authority.epoch, 'activityRecoveryFloor.authority.epoch', { minimum: 1 }),
    },
    retained_watermark: integer(floor.retained_watermark, 'activityRecoveryFloor.retained_watermark', { minimum: 0 }),
    snapshot_generation: integer(floor.snapshot_generation, 'activityRecoveryFloor.snapshot_generation', { minimum: 1 }),
    commit_high_water: integer(floor.commit_high_water, 'activityRecoveryFloor.commit_high_water', { minimum: 0 }),
    latest_change_sequence: integer(floor.latest_change_sequence, 'activityRecoveryFloor.latest_change_sequence', { minimum: 0 }),
    runtime_fence: integer(floor.runtime_fence, 'activityRecoveryFloor.runtime_fence', { minimum: 0 }),
    runtime_claim: {
      runtime_id: runtimeClaim.runtime_id,
      runtime_fence: integer(runtimeClaim.runtime_fence, 'activityRecoveryFloor.runtime_claim.runtime_fence', { minimum: 0 }),
      lease_expires_at_ms: integer(runtimeClaim.lease_expires_at_ms, 'activityRecoveryFloor.runtime_claim.lease_expires_at_ms', { minimum: 0 }),
    },
    database_role: enumValue(floor.database_role, 'activityRecoveryFloor.database_role', REQUIRED_ACTIVITY_DATABASE_ROLES),
    history_digest: string(floor.history_digest, 'activityRecoveryFloor.history_digest', { max: 64 }),
    principals: normalizedPrincipals,
  };
  if (typeof floor.digest !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(floor.digest)) {
    fail('recovery_lineage_unverified', 'Activity recovery floor signature is invalid.', { status: 409 });
  }
  if (!/^[a-f0-9]{64}$/.test(body.history_digest)) {
    fail('recovery_lineage_unverified', 'Activity recovery history digest is invalid.', { status: 409 });
  }
  if (body.runtime_claim.runtime_fence !== body.runtime_fence) {
    fail('recovery_lineage_unverified', 'Activity recovery runtime fence is inconsistent.', { status: 409 });
  }
  const actual = Buffer.from(floor.digest);
  const expected = Buffer.from(recoveryDigest(body, cursorSecret));
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) {
    fail('recovery_lineage_unverified', 'Activity recovery floor signature is invalid.', { status: 409 });
  }
  return body;
}

function integer(value, field, { minimum = Number.MIN_SAFE_INTEGER, maximum = Number.MAX_SAFE_INTEGER } = {}) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    fail('invalid_request', `${field} must be an integer from ${minimum} to ${maximum}.`);
  }
  return value;
}

function safeIntegerSum(left, right) {
  if (!Number.isSafeInteger(left) || !Number.isSafeInteger(right)) return null;
  const sum = left + right;
  return Number.isSafeInteger(sum) ? sum : null;
}

function derivedTimestamp(base, interval, field) {
  const result = safeIntegerSum(base, interval);
  if (result == null || result < 0) {
    fail('invalid_time_range', `${field} exceeds the supported timestamp range.`, {
      details: { field },
    });
  }
  return result;
}

// The baseline is observed evidence, not an assertion that sequence 0 existed.
// A retained floor bounds replay only; continuity below it is no longer known.
function activitySequenceCoverage(sequences, retainedFloor) {
  const ordered = [...new Set(sequences.filter((value) => retainedFloor == null || value > retainedFloor))]
    .sort((a, b) => a - b);
  const observedFrom = ordered[0] ?? null;
  let contiguousThrough = null;
  let previous = retainedFloor;
  const missing = [];
  let missingTruncated = false;
  let gap = false;
  for (const sequence of ordered) {
    if (previous != null && sequence - previous > 1) {
      gap = true;
      const count = sequence - previous - 1;
      const take = Math.min(count, 128 - missing.length);
      for (let offset = 1; offset <= take; offset++) missing.push(previous + offset);
      if (take < count) missingTruncated = true;
    }
    if (!gap) contiguousThrough = sequence;
    previous = sequence;
  }
  return {
    highest_seen: ordered.at(-1) ?? null,
    contiguous_through: contiguousThrough,
    missing,
    observed_from: observedFrom,
    retained_origin_floor: retainedFloor,
    missing_truncated: missingTruncated,
  };
}

function retiredContext(state) {
  const context = JSON.parse(state?.retired_context_json ?? '{}');
  if (Object.keys(context).length === 0 && state?.retained_origin_floor == null) {
    return { max_signal_at_ms: null, permission_status: 'clear', source_health: 'unknown' };
  }
  if (Object.keys(context).sort().join(',') !== 'max_signal_at_ms,permission_status,source_health'
    || (context.max_signal_at_ms !== null && (!Number.isSafeInteger(context.max_signal_at_ms) || context.max_signal_at_ms < 0))
    || !['clear', 'unavailable', 'pending'].includes(context.permission_status)
    || !['unknown', 'healthy', 'clock_regression', 'future_skew', 'probe_error', 'permission_unavailable', 'insufficient_human_evidence'].includes(context.source_health)) {
    throw new Error('Invalid retired prefix context');
  }
  return context;
}

function activityPermissionStatus(events, initial = 'clear', logicalClocks = null) {
  let status = initial;
  for (const row of [...events].sort((a, b) => a.origin_sequence - b.origin_sequence)) {
    const payload = JSON.parse(row.payload_json);
    if (row.kind === 'probe.permission_changed') {
      status = payload.available === false ? 'unavailable' : 'pending';
    } else if (status !== 'unavailable' && ['active', 'locked'].includes(projectionState({
      kind: row.kind, confidence: row.confidence, payload,
    }, {
      clockHealth: logicalClocks?.get(row.event_id) ?? row.clock_health,
      coverageStatus: ['none', 'unknown'].includes(JSON.parse(row.coverage_json).mode) ? 'missing' : 'covered',
    }))) status = 'clear';
  }
  return status;
}

function activityClockHealthMaps(events, { retiredSignal = null, retainedFloor = null, acceptanceAnchors = null } = {}) {
  const coordinates = [...new Set(events.map((event) => Number(event.origin_sequence)))].sort((a, b) => a - b);
  const tree = Array(coordinates.length + 1).fill(null);
  const lowerBound = (value) => {
    let low = 0;
    let high = coordinates.length;
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (coordinates[middle] < value) low = middle + 1;
      else high = middle;
    }
    return low;
  };
  const query = (count) => {
    let result = null;
    for (let index = count; index > 0; index -= index & -index) {
      if (tree[index] != null) result = result == null ? tree[index] : Math.max(result, tree[index]);
    }
    return result;
  };
  const update = (position, value) => {
    for (let index = position; index < tree.length; index += index & -index) {
      tree[index] = tree[index] == null ? value : Math.max(tree[index], value);
    }
  };
  const acceptance = new Map();
  for (const event of [...events].sort((left, right) => Number(left.server_sequence) - Number(right.server_sequence))) {
    const boundary = safeIntegerSum(Number(event.received_at_ms), ACTIVITY_FUTURE_SKEW_MS);
    if (boundary == null) return null;
    const future = Number(event.occurred_at_ms) > boundary;
    const knownPrior = query(lowerBound(Number(event.origin_sequence)));
    let maximumPriorLowerSignal = knownPrior == null ? retiredSignal
      : retiredSignal == null ? knownPrior : Math.max(knownPrior, retiredSignal);
    if (acceptanceAnchors) {
      const anchor = acceptanceAnchors.get(event.event_id);
      if (anchor !== null && (!Number.isSafeInteger(anchor) || anchor < 0)) return null;
      if ((knownPrior != null && (anchor == null || anchor < knownPrior))
        || (retainedFloor == null && anchor !== knownPrior)) return null;
      maximumPriorLowerSignal = anchor;
    }
    acceptance.set(
      event.event_id,
      future
        ? 'future_skew'
        : maximumPriorLowerSignal != null && Number(event.occurred_at_ms) < maximumPriorLowerSignal
          ? 'clock_regression'
          : 'healthy',
    );
    if (!future) update(lowerBound(Number(event.origin_sequence)) + 1, Number(event.occurred_at_ms));
  }
  const logical = new Map();
  let maximumPriorLogicalSignal = retiredSignal;
  for (const event of [...events].sort((left, right) => Number(left.origin_sequence) - Number(right.origin_sequence))) {
    const boundary = safeIntegerSum(Number(event.received_at_ms), ACTIVITY_FUTURE_SKEW_MS);
    if (boundary == null) return null;
    const future = Number(event.occurred_at_ms) > boundary;
    logical.set(
      event.event_id,
      future
        ? 'future_skew'
        : maximumPriorLogicalSignal != null && Number(event.occurred_at_ms) < maximumPriorLogicalSignal
          ? 'clock_regression'
          : 'healthy',
    );
    if (!future) {
      maximumPriorLogicalSignal = maximumPriorLogicalSignal == null
        ? Number(event.occurred_at_ms)
        : Math.max(maximumPriorLogicalSignal, Number(event.occurred_at_ms));
    }
  }
  return { acceptance, logical };
}

function enumValue(value, field, allowed) {
  const normalized = string(value, field);
  if (!allowed.includes(normalized)) fail('invalid_request', `${field} must be one of: ${allowed.join(', ')}.`);
  return normalized;
}

function stringArray(value, field, { allowed = null, maximum = 100 } = {}) {
  if (!Array.isArray(value) || value.length > maximum || value.some((item) => typeof item !== 'string')) {
    fail('invalid_request', `${field} must be an array of strings with at most ${maximum} items.`);
  }
  const unique = [...new Set(value)];
  if (allowed && unique.some((item) => !allowed.includes(item))) {
    fail('unsupported_kind', `${field} contains an unsupported activity kind.`);
  }
  return unique;
}

function normalizeCoverage(raw) {
  const coverage = object(raw, 'coverage');
  exactKeys(coverage, ['mode', 'window_start_ms', 'window_end_ms', 'expected_report_interval_ms'], 'coverage');
  const mode = enumValue(
    coverage.mode,
    'coverage.mode',
    ['continuous', 'discrete_best_effort', 'heartbeat_only', 'none', 'unknown'],
  );
  const windowStart = integer(coverage.window_start_ms, 'coverage.window_start_ms', { minimum: 0 });
  const windowEnd = integer(coverage.window_end_ms, 'coverage.window_end_ms', { minimum: 0 });
  if (windowEnd < windowStart) fail('invalid_coverage', 'coverage.window_end_ms must not precede window_start_ms.');
  return {
    mode,
    window_start_ms: windowStart,
    window_end_ms: windowEnd,
    expected_report_interval_ms: coverage.expected_report_interval_ms == null
      ? null
      : integer(
          coverage.expected_report_interval_ms,
          'coverage.expected_report_interval_ms',
          { minimum: 1, maximum: ACTIVITY_MAX_TTL_MS },
        ),
  };
}

function normalizePayload(kind, raw) {
  const payload = object(raw, 'payload');
  const empty = [
    'probe.heartbeat', 'session.locked', 'session.unlocked', 'screen.interactive',
    'screen.non_interactive', 'focus.sleep_on', 'focus.sleep_off', 'power.charging',
    'power.unplugged', 'network.present',
  ];
  if (empty.includes(kind)) exactKeys(payload, [], 'payload');
  if (kind === 'input.activity') {
    exactKeys(payload, ['class'], 'payload');
    return { class: enumValue(payload.class, 'payload.class', ['input_or_touch']) };
  }
  if (kind === 'input.idle_bucket') {
    exactKeys(payload, ['bucket'], 'payload');
    return { bucket: enumValue(payload.bucket, 'payload.bucket', ['lt_1m', '1_5m', '5_15m', '15m_plus']) };
  }
  if (kind === 'app.category_active') {
    exactKeys(payload, ['category'], 'payload');
    return { category: enumValue(payload.category, 'payload.category', ['chat', 'social', 'video', 'reading', 'work', 'other']) };
  }
  if (kind === 'sensor.heart_rate_quality') {
    exactKeys(payload, ['quality', 'source_age_ms'], 'payload');
    return {
      quality: enumValue(payload.quality, 'payload.quality', ['fresh', 'stale', 'gap', 'unavailable']),
      source_age_ms: integer(payload.source_age_ms, 'payload.source_age_ms', { minimum: 0, maximum: ACTIVITY_RAW_RETENTION_MS }),
    };
  }
  if (kind === 'probe.permission_changed') {
    exactKeys(payload, ['capability', 'available'], 'payload');
    if (typeof payload.available !== 'boolean') fail('invalid_request', 'payload.available must be a boolean.');
    return { capability: diagnosticToken(payload.capability, 'payload.capability'), available: payload.available };
  }
  if (kind === 'probe.error') {
    exactKeys(payload, ['code'], 'payload');
    return { code: diagnosticToken(payload.code, 'payload.code', { max: 48 }) };
  }
  return payload;
}

export function normalizeActivityEvent(raw) {
  const event = object(raw, 'event');
  const eventFields = [
    'contract', 'schema_version', 'event_id', 'device_id', 'probe_id',
    'origin_sequence', 'kind', 'signal_at_ms', 'ttl_ms', 'confidence',
    'source', 'coverage', 'payload',
  ];
  requiredKeys(event, eventFields);
  exactKeys(event, eventFields, 'event');
  if (Buffer.byteLength(JSON.stringify(event.payload), 'utf8') > ACTIVITY_MAX_PAYLOAD_BYTES) {
    fail('payload_too_large', `payload exceeds ${ACTIVITY_MAX_PAYLOAD_BYTES} UTF-8 bytes.`, { status: 413 });
  }
  if (event.contract !== ACTIVITY_CONTRACT || event.schema_version !== ACTIVITY_FEATURE_VERSION) {
    fail('protocol_mismatch', `Activity events must use ${ACTIVITY_CONTRACT} schema version ${ACTIVITY_FEATURE_VERSION}.`, { status: 426 });
  }
  if (typeof event.kind !== 'string' || !ACTIVITY_KINDS.includes(event.kind)) {
    fail('unsupported_kind', 'kind contains an unsupported activity kind.');
  }
  const kind = event.kind;
  const normalized = {
    contract: ACTIVITY_CONTRACT,
    schema_version: ACTIVITY_FEATURE_VERSION,
    event_id: eventIdentifier(event.event_id),
    device_id: opaqueId(event.device_id, 'device_id'),
    probe_id: opaqueId(event.probe_id, 'probe_id'),
    origin_sequence: integer(event.origin_sequence, 'origin_sequence', { minimum: 0 }),
    kind,
    signal_at_ms: integer(event.signal_at_ms, 'signal_at_ms', { minimum: 0 }),
    ttl_ms: integer(event.ttl_ms, 'ttl_ms', { minimum: 1, maximum: ACTIVITY_MAX_TTL_MS }),
    confidence: enumValue(event.confidence, 'confidence', ['high', 'medium', 'low']),
    source: enumValue(event.source, 'source', ACTIVITY_SOURCES),
    coverage: normalizeCoverage(event.coverage),
    payload: normalizePayload(kind, event.payload),
  };
  if (Buffer.byteLength(JSON.stringify(normalized.payload), 'utf8') > ACTIVITY_MAX_PAYLOAD_BYTES) {
    fail('payload_too_large', `payload exceeds ${ACTIVITY_MAX_PAYLOAD_BYTES} UTF-8 bytes.`, { status: 413 });
  }
  if (Buffer.byteLength(JSON.stringify(normalized), 'utf8') > ACTIVITY_MAX_ENVELOPE_BYTES) {
    fail('payload_too_large', `event envelope exceeds ${ACTIVITY_MAX_ENVELOPE_BYTES} UTF-8 bytes.`, { status: 413 });
  }
  return normalized;
}

function activityMigrationSql() {
  return `
    CREATE TABLE activity_schema_migrations (
      version INTEGER PRIMARY KEY,
      state TEXT NOT NULL CHECK(state IN ('committed')),
      checksum TEXT NOT NULL,
      committed_at_ms INTEGER NOT NULL
    );
    CREATE TABLE activity_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE activity_principals (
      principal_id TEXT PRIMARY KEY,
      principal_type TEXT NOT NULL CHECK(principal_type IN ('probe', 'summary_reader')),
      device_id TEXT,
      probe_id TEXT UNIQUE,
      event_id_prefix TEXT,
      retired_event_prefix_digest TEXT,
      retired_floor_digest TEXT,
      display_name TEXT NOT NULL,
      capabilities_json TEXT NOT NULL,
      scopes_json TEXT NOT NULL,
      allowed_kinds_json TEXT NOT NULL,
      source TEXT,
      coverage_mode TEXT,
      expected_report_interval_ms INTEGER,
      expiry_slo_ms INTEGER,
      credential_generation INTEGER NOT NULL,
      paired_at_ms INTEGER NOT NULL,
      revoked_at_ms INTEGER,
      deleted_at_ms INTEGER,
      authority_node_id TEXT NOT NULL,
      authority_epoch INTEGER NOT NULL,
      UNIQUE(device_id, probe_id)
    );
    CREATE UNIQUE INDEX activity_principals_event_prefix_idx ON activity_principals(event_id_prefix);
    CREATE TABLE activity_credentials (
      credential_id TEXT PRIMARY KEY,
      principal_id TEXT NOT NULL,
      generation INTEGER NOT NULL,
      token_hash TEXT NOT NULL UNIQUE,
      issued_at_ms INTEGER NOT NULL,
      revoked_at_ms INTEGER,
      FOREIGN KEY(principal_id) REFERENCES activity_principals(principal_id),
      UNIQUE(principal_id, generation)
    );
    CREATE TABLE activity_changes (
      server_sequence INTEGER PRIMARY KEY AUTOINCREMENT,
      change_id TEXT NOT NULL UNIQUE,
      kind TEXT NOT NULL,
      device_id TEXT,
      probe_id TEXT,
      occurred_at_ms INTEGER NOT NULL,
      payload_json TEXT NOT NULL
    );
    CREATE INDEX activity_changes_subject_idx ON activity_changes(device_id, probe_id, server_sequence);
    CREATE TABLE activity_events (
      event_id TEXT PRIMARY KEY,
      device_id TEXT NOT NULL,
      probe_id TEXT NOT NULL,
      origin_sequence INTEGER NOT NULL,
      kind TEXT NOT NULL,
      occurred_at_ms INTEGER NOT NULL,
      received_at_ms INTEGER NOT NULL,
      ttl_ms INTEGER NOT NULL,
      confidence TEXT NOT NULL,
      source TEXT NOT NULL,
      coverage_json TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      canonical_digest TEXT NOT NULL,
      receipt_id TEXT NOT NULL UNIQUE,
      server_sequence INTEGER NOT NULL UNIQUE,
      clock_health TEXT NOT NULL,
      credential_generation INTEGER NOT NULL,
      authority_node_id TEXT NOT NULL,
      authority_epoch INTEGER NOT NULL,
      FOREIGN KEY(server_sequence) REFERENCES activity_changes(server_sequence),
      UNIQUE(device_id, probe_id, origin_sequence)
    );
    CREATE INDEX activity_events_received_idx ON activity_events(received_at_ms);
    CREATE TABLE activity_event_tombstones (
      event_id TEXT NOT NULL,
      device_id TEXT NOT NULL,
      probe_id TEXT NOT NULL,
      origin_sequence INTEGER NOT NULL,
      canonical_digest TEXT NOT NULL,
      removed_at_ms INTEGER NOT NULL,
      expires_at_ms INTEGER NOT NULL,
      PRIMARY KEY(event_id),
      UNIQUE(device_id, probe_id, origin_sequence)
    );
    CREATE TABLE activity_replay_lineage_floors (
      lineage_digest TEXT PRIMARY KEY,
      floor_digest TEXT NOT NULL,
      CHECK(length(lineage_digest)=64),
      CHECK(length(floor_digest)=64)
    );
    CREATE TABLE activity_probe_state (
      probe_id TEXT PRIMARY KEY,
      max_origin_sequence INTEGER,
      retained_origin_floor INTEGER,
      retired_context_json TEXT NOT NULL DEFAULT '{}',
      max_occurred_at_ms INTEGER,
      last_received_at_ms INTEGER,
      last_clock_health TEXT NOT NULL DEFAULT 'unknown',
      last_coverage_status TEXT NOT NULL DEFAULT 'unknown',
      FOREIGN KEY(probe_id) REFERENCES activity_principals(probe_id)
    );
    CREATE TABLE activity_projections (
      device_id TEXT NOT NULL,
      probe_id TEXT NOT NULL,
      current_event_id TEXT,
      source TEXT NOT NULL,
      state TEXT NOT NULL CHECK(state IN ('active', 'locked', 'network_only', 'unknown')),
      occurred_at_ms INTEGER,
      received_at_ms INTEGER,
      expires_at_ms INTEGER,
      confidence TEXT,
      coverage_json TEXT NOT NULL,
      coverage_status TEXT NOT NULL,
      clock_health TEXT NOT NULL,
      credential_state TEXT NOT NULL,
      status_reason TEXT NOT NULL,
      last_server_sequence INTEGER,
      updated_at_ms INTEGER NOT NULL,
      PRIMARY KEY(device_id, probe_id)
    );
    CREATE TABLE activity_reader_acks (
      principal_id TEXT PRIMARY KEY,
      last_ack_sequence INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      FOREIGN KEY(principal_id) REFERENCES activity_principals(principal_id)
    );
    CREATE TABLE activity_rate_limits (
      probe_id TEXT PRIMARY KEY,
      window_start_ms INTEGER NOT NULL,
      accepted_count INTEGER NOT NULL
    );
    CREATE TABLE activity_audit (
      audit_id TEXT PRIMARY KEY,
      action TEXT NOT NULL,
      principal_id TEXT,
      device_id TEXT,
      probe_id TEXT,
      occurred_at_ms INTEGER NOT NULL,
      expires_at_ms INTEGER NOT NULL,
      details_json TEXT NOT NULL
    );
    CREATE INDEX activity_audit_expiry_idx ON activity_audit(expires_at_ms);
    CREATE TABLE activity_deletion_receipts (
      receipt_id TEXT PRIMARY KEY,
      scope TEXT NOT NULL,
      device_id TEXT,
      probe_id TEXT,
      started_at_ms INTEGER NOT NULL,
      isolated_at_ms INTEGER NOT NULL,
      completed_at_ms INTEGER NOT NULL,
      snapshot_generation INTEGER NOT NULL,
      status_json TEXT NOT NULL
    );
    CREATE TABLE activity_runtime_claim (
      singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
      runtime_id TEXT NOT NULL,
      runtime_fence INTEGER NOT NULL,
      lease_expires_at_ms INTEGER NOT NULL
    );
  `;
}

function activityMigrationV1Sql() {
  return activityMigrationV3Sql().replace(`    CREATE TABLE activity_runtime_claim (
      singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
      runtime_id TEXT NOT NULL,
      runtime_fence INTEGER NOT NULL,
      lease_expires_at_ms INTEGER NOT NULL
    );
`, '');
}

export const ACTIVITY_SCHEMA_V1_CHECKSUM = canonicalActivityDigest(activityMigrationV1Sql());
export const ACTIVITY_SCHEMA_V2_CHECKSUM = '2361737d94ca6ad655cd4921e88c49cf9af4b1c76b49fd713b1462c7661c5ab4';
export const ACTIVITY_SCHEMA_V3_CHECKSUM = '2361737d94ca6ad655cd4921e88c49cf9af4b1c76b49fd713b1462c7661c5ab4';
export const ACTIVITY_SCHEMA_V4_CHECKSUM = canonicalActivityDigest(activityMigrationV4Sql());

function activityMigrationV4Sql() {
  return activityMigrationSql()
    .replace("      retired_context_json TEXT NOT NULL DEFAULT '{}',\n", '')
    .replace('      event_id_prefix TEXT,\n', '')
    .replace('      retired_event_prefix_digest TEXT,\n', '')
    .replace('      retired_floor_digest TEXT,\n', '')
    .replace('    CREATE UNIQUE INDEX activity_principals_event_prefix_idx ON activity_principals(event_id_prefix);\n', '')
    .replace(`    CREATE TABLE activity_replay_lineage_floors (
      lineage_digest TEXT PRIMARY KEY,
      floor_digest TEXT NOT NULL,
      CHECK(length(lineage_digest)=64),
      CHECK(length(floor_digest)=64)
    );
`, `    CREATE TABLE activity_event_replay_barriers (
      event_id_digest TEXT PRIMARY KEY,
      probe_id TEXT NOT NULL,
      origin_sequence INTEGER NOT NULL,
      canonical_digest TEXT NOT NULL,
      retired_at_ms INTEGER NOT NULL,
      UNIQUE(probe_id, origin_sequence)
    );
`);
}

function activityMigrationV3Sql() {
  return activityMigrationV4Sql()
    .replace(`    CREATE TABLE activity_event_replay_barriers (
      event_id_digest TEXT PRIMARY KEY,
      probe_id TEXT NOT NULL,
      origin_sequence INTEGER NOT NULL,
      canonical_digest TEXT NOT NULL,
      retired_at_ms INTEGER NOT NULL,
      UNIQUE(probe_id, origin_sequence)
    );
`, '')
    .replace('      retained_origin_floor INTEGER,\n', '');
}

function activityReplayFloorSql() {
  return `CREATE TABLE activity_replay_lineage_floors (
    lineage_digest TEXT PRIMARY KEY,
    floor_digest TEXT NOT NULL,
    CHECK(length(lineage_digest)=64),
    CHECK(length(floor_digest)=64)
  )`;
}

function upgradePrincipalsForEventPrefix(db, { retiredFloors = new Map() } = {}) {
  db.exec(`ALTER TABLE activity_principals RENAME TO activity_principals_legacy;
    CREATE TABLE activity_principals (
      principal_id TEXT PRIMARY KEY,
      principal_type TEXT NOT NULL CHECK(principal_type IN ('probe', 'summary_reader')),
      device_id TEXT,
      probe_id TEXT UNIQUE,
      event_id_prefix TEXT,
      retired_event_prefix_digest TEXT,
      retired_floor_digest TEXT,
      display_name TEXT NOT NULL,
      capabilities_json TEXT NOT NULL,
      scopes_json TEXT NOT NULL,
      allowed_kinds_json TEXT NOT NULL,
      source TEXT,
      coverage_mode TEXT,
      expected_report_interval_ms INTEGER,
      expiry_slo_ms INTEGER,
      credential_generation INTEGER NOT NULL,
      paired_at_ms INTEGER NOT NULL,
      revoked_at_ms INTEGER,
      deleted_at_ms INTEGER,
      authority_node_id TEXT NOT NULL,
      authority_epoch INTEGER NOT NULL,
      UNIQUE(device_id, probe_id)
    );
    INSERT INTO activity_principals(
      principal_id,principal_type,device_id,probe_id,display_name,capabilities_json,
      scopes_json,allowed_kinds_json,source,coverage_mode,expected_report_interval_ms,
      expiry_slo_ms,credential_generation,paired_at_ms,revoked_at_ms,deleted_at_ms,
      authority_node_id,authority_epoch
    ) SELECT principal_id,principal_type,device_id,probe_id,display_name,capabilities_json,
      scopes_json,allowed_kinds_json,source,coverage_mode,expected_report_interval_ms,
      expiry_slo_ms,credential_generation,paired_at_ms,revoked_at_ms,deleted_at_ms,
      authority_node_id,authority_epoch FROM activity_principals_legacy;
    DROP TABLE activity_principals_legacy;
    CREATE UNIQUE INDEX activity_principals_event_prefix_idx ON activity_principals(event_id_prefix);`);
  const cursorSecret = db.prepare("SELECT value FROM core_metadata WHERE key='cursor_secret'").get()?.value;
  const probes = db.prepare("SELECT principal_id,probe_id,deleted_at_ms FROM activity_principals WHERE principal_type='probe' ORDER BY principal_id").all();
  for (const probe of probes) {
    const prefix = randomBytes(16).toString('base64url');
    if (probe.deleted_at_ms == null) {
      db.prepare('UPDATE activity_principals SET event_id_prefix=? WHERE principal_id=?')
        .run(prefix, probe.principal_id);
      continue;
    }
    const floor = retiredFloors.get(probe.probe_id) ?? null;
    const lineageDigest = replayPrefixDigest(cursorSecret, prefix);
    const floorDigest = replayFloorDigest(cursorSecret, prefix, floor);
    db.prepare('INSERT INTO activity_replay_lineage_floors(lineage_digest,floor_digest) VALUES (?,?)')
      .run(lineageDigest, floorDigest);
    db.prepare(`UPDATE activity_principals SET retired_event_prefix_digest=?,retired_floor_digest=?
      WHERE principal_id=?`).run(lineageDigest, floorDigest, probe.principal_id);
  }
}

function upgradeProbeStateForReplayFloorSql() {
  return `ALTER TABLE activity_probe_state RENAME TO activity_probe_state_v3;
    CREATE TABLE activity_probe_state (
      probe_id TEXT PRIMARY KEY,
      max_origin_sequence INTEGER,
      retained_origin_floor INTEGER,
      retired_context_json TEXT NOT NULL DEFAULT '{}',
      max_occurred_at_ms INTEGER,
      last_received_at_ms INTEGER,
      last_clock_health TEXT NOT NULL DEFAULT 'unknown',
      last_coverage_status TEXT NOT NULL DEFAULT 'unknown',
      FOREIGN KEY(probe_id) REFERENCES activity_principals(probe_id)
    );
    INSERT INTO activity_probe_state(
      probe_id,max_origin_sequence,max_occurred_at_ms,last_received_at_ms,
      last_clock_health,last_coverage_status
    ) SELECT probe_id,max_origin_sequence,max_occurred_at_ms,last_received_at_ms,
      last_clock_health,last_coverage_status FROM activity_probe_state_v3;
    DROP TABLE activity_probe_state_v3;`;
}

function initializeReplayFloorCommitment(db) {
  const cursorSecret = db.prepare("SELECT value FROM core_metadata WHERE key='cursor_secret'").get()?.value;
  if (typeof cursorSecret !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(cursorSecret)) {
    fail('core_metadata_invariant_failed', 'Core cursor secret is required to migrate activity replay floors.', { status: 503 });
  }
  db.prepare(`INSERT INTO activity_metadata(key,value) VALUES
    ('integrity_commitment_version','4'),('server_time_floor_ms','0'),
    ('replay_floor_revision','0'),('replay_floor_count','0'),
    ('accepted_event_count','0'),('retired_event_count','0')`).run();
  writeReplayCommitment(db, cursorSecret);
}

function upgradeEmptyV4ReplayState(db) {
  db.exec(upgradeProbeStateForReplayFloorSql());
  db.exec('DROP TABLE activity_event_replay_barriers');
  db.exec(activityReplayFloorSql());
  upgradePrincipalsForEventPrefix(db);
  initializeReplayFloorCommitment(db);
}

function tableExists(db, name) {
  return Boolean(db.prepare("SELECT 1 AS found FROM sqlite_master WHERE type='table' AND name=?").get(name));
}

function activitySchemaObjectExists(db, name) {
  return Boolean(db.prepare("SELECT 1 AS found FROM sqlite_master WHERE name=? AND type IN ('table','index')").get(name));
}

function sameColumns(actual, expected) {
  return actual.length === expected.length && actual.every((column, index) => column === expected[index]);
}

function tablePrimaryKey(db, table) {
  return db.prepare(`PRAGMA table_info(${table})`).all()
    .filter((row) => Number(row.pk) > 0)
    .sort((left, right) => Number(left.pk) - Number(right.pk))
    .map((row) => row.name);
}

function indexColumns(db, index) {
  return db.prepare('SELECT name FROM pragma_index_info(?) ORDER BY seqno').all(index).map((row) => row.name);
}

function tableUniqueKeys(db, table) {
  return db.prepare(`PRAGMA index_list(${table})`).all()
    .filter((row) => Number(row.unique) === 1)
    .map((row) => indexColumns(db, row.name));
}

function canonicalMetadataInteger(raw, minimum) {
  if (typeof raw !== 'string' || !/^(0|[1-9]\d*)$/.test(raw)) return null;
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value < minimum) return null;
  return value;
}

function normalizedSchemaSql(sql) {
  return typeof sql === 'string' ? sql.replace(/\s+/g, ' ').replace(/;$/, '').trim().toLowerCase() : null;
}

function expectedActivityDdl(sqlSource = activityMigrationSql()) {
  const definitions = new Map();
  for (const statement of sqlSource.split(';')) {
    const sql = statement.trim();
    const match = /^create\s+(?:table|index)\s+(activity_[a-z0-9_]+)/i.exec(sql);
    if (match) definitions.set(match[1], normalizedSchemaSql(sql));
  }
  return definitions;
}

const LEGACY_ACTIVITY_CONTENT_TABLES = Object.freeze([
  'activity_principals',
  'activity_credentials',
  'activity_changes',
  'activity_events',
  'activity_event_tombstones',
  'activity_event_replay_barriers',
  'activity_probe_state',
  'activity_projections',
  'activity_reader_acks',
  'activity_rate_limits',
  'activity_audit',
  'activity_deletion_receipts',
]);

function legacyActivityDomainEmpty(db) {
  return LEGACY_ACTIVITY_CONTENT_TABLES.every((table) => (
    !tableExists(db, table)
    || Number(db.prepare(`SELECT COUNT(*) AS value FROM ${table}`).get().value) === 0
  ));
}

function legacyActivityDomainVirgin(db, version) {
  if (!legacyActivityDomainEmpty(db)) return false;
  const metadata = new Map(db.prepare('SELECT key,value FROM activity_metadata ORDER BY key').all()
    .map((row) => [row.key, row.value]));
  const expectedEntries = [
    ['retained_watermark', '0'],
    ['snapshot_generation', '1'],
    ['authority_epoch', '1'],
  ];
  if (version >= 2) expectedEntries.push(['commit_high_water', '0']);
  if (version >= 3) expectedEntries.push(['database_role', 'live']);
  const expectedMetadata = new Map(expectedEntries);
  const hasBinding = version >= 4;
  if (metadata.size !== expectedMetadata.size + (hasBinding ? 1 : 0)) return false;
  for (const [key, value] of expectedMetadata) {
    if (metadata.get(key) !== value) return false;
  }
  if (hasBinding && !/^[a-f0-9]{64}$/.test(metadata.get('database_binding_digest') ?? '')) return false;
  if (version === 1) return !tableExists(db, 'activity_runtime_claim');
  const runtime = db.prepare('SELECT singleton,runtime_id,runtime_fence,lease_expires_at_ms FROM activity_runtime_claim').all();
  return runtime.length === 1
    && Number(runtime[0].singleton) === 1
    && runtime[0].runtime_id === ''
    && Number(runtime[0].runtime_fence) === 0
    && Number(runtime[0].lease_expires_at_ms) === 0;
}

function legacyActivityV1Ready(db) {
  const definitions = new Map();
  for (const statement of activityMigrationV1Sql().split(';')) {
    const sql = statement.trim();
    const match = /^create\s+(?:table|index)\s+(activity_[a-z0-9_]+)/i.exec(sql);
    if (match) definitions.set(match[1], normalizedSchemaSql(sql));
  }
  if ([...definitions.keys()].some((name) => !activitySchemaObjectExists(db, name)) || tableExists(db, 'activity_runtime_claim')) return false;
  for (const [name, expected] of definitions) {
    const actual = normalizedSchemaSql(db.prepare('SELECT sql FROM sqlite_master WHERE name=?').get(name)?.sql);
    if (actual !== expected) return false;
  }
  const migration = db.prepare('SELECT state,checksum FROM activity_schema_migrations WHERE version=1').get();
  if (!migration || migration.state !== 'committed' || migration.checksum !== ACTIVITY_SCHEMA_V1_CHECKSUM) return false;
  if (db.prepare("SELECT value FROM core_metadata WHERE key='activity_schema_version'").get()?.value !== '1') return false;
  if (db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get()?.value !== '5') return false;
  for (const [key, minimum] of Object.entries({ retained_watermark: 0, snapshot_generation: 1, authority_epoch: 1 })) {
    const raw = db.prepare('SELECT value FROM activity_metadata WHERE key=?').get(key)?.value;
    if (canonicalMetadataInteger(raw, minimum) == null) return false;
  }
  return !db.prepare("SELECT 1 AS found FROM activity_metadata WHERE key='commit_high_water'").get();
}

function legacyActivityV2Ready(db) {
  const definitions = expectedActivityDdl(activityMigrationV3Sql());
  if ([...definitions.keys()].some((name) => !activitySchemaObjectExists(db, name))) return false;
  for (const [name, expected] of definitions) {
    const actual = normalizedSchemaSql(db.prepare('SELECT sql FROM sqlite_master WHERE name=?').get(name)?.sql);
    if (actual !== expected) return false;
  }
  const migration = db.prepare('SELECT state,checksum FROM activity_schema_migrations WHERE version=2').get();
  if (!migration || migration.state !== 'committed' || migration.checksum !== ACTIVITY_SCHEMA_V2_CHECKSUM) return false;
  if (db.prepare("SELECT value FROM core_metadata WHERE key='activity_schema_version'").get()?.value !== '2') return false;
  if (db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get()?.value !== '5') return false;
  for (const [key, minimum] of Object.entries(LEGACY_REQUIRED_ACTIVITY_METADATA)) {
    const raw = db.prepare('SELECT value FROM activity_metadata WHERE key=?').get(key)?.value;
    if (canonicalMetadataInteger(raw, minimum) == null) return false;
  }
  return !db.prepare("SELECT 1 AS found FROM activity_metadata WHERE key='database_role'").get();
}

function legacyActivityV3Ready(db) {
  const definitions = expectedActivityDdl(activityMigrationV3Sql());
  if ([...definitions.keys()].some((name) => !activitySchemaObjectExists(db, name))) return false;
  for (const [name, expected] of definitions) {
    const actual = normalizedSchemaSql(db.prepare('SELECT sql FROM sqlite_master WHERE name=?').get(name)?.sql);
    if (actual !== expected) return false;
  }
  const migration = db.prepare('SELECT state,checksum FROM activity_schema_migrations WHERE version=3').get();
  if (!migration || migration.state !== 'committed' || migration.checksum !== ACTIVITY_SCHEMA_V3_CHECKSUM) return false;
  if (db.prepare("SELECT value FROM core_metadata WHERE key='activity_schema_version'").get()?.value !== '3') return false;
  if (db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get()?.value !== '5') return false;
  for (const [key, minimum] of Object.entries(LEGACY_REQUIRED_ACTIVITY_METADATA)) {
    const raw = db.prepare('SELECT value FROM activity_metadata WHERE key=?').get(key)?.value;
    if (canonicalMetadataInteger(raw, minimum) == null) return false;
  }
  if (!REQUIRED_ACTIVITY_DATABASE_ROLES.includes(db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get()?.value)) return false;
  return !db.prepare("SELECT 1 AS found FROM activity_metadata WHERE key='database_binding_digest'").get();
}

function legacyActivityV4Ready(db, expectedDatabaseBindingDigest = null) {
  const definitions = expectedActivityDdl(activityMigrationV4Sql());
  if ([...definitions.keys()].some((name) => !activitySchemaObjectExists(db, name))) return false;
  for (const [name, expected] of definitions) {
    const actual = normalizedSchemaSql(db.prepare('SELECT sql FROM sqlite_master WHERE name=?').get(name)?.sql);
    if (actual !== expected) return false;
  }
  const migration = db.prepare('SELECT state,checksum FROM activity_schema_migrations WHERE version=4').get();
  if (!migration || migration.state !== 'committed' || migration.checksum !== ACTIVITY_SCHEMA_V4_CHECKSUM) return false;
  if (db.prepare("SELECT value FROM core_metadata WHERE key='activity_schema_version'").get()?.value !== '4') return false;
  if (db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get()?.value !== '5') return false;
  for (const [key, minimum] of Object.entries(LEGACY_REQUIRED_ACTIVITY_METADATA)) {
    const raw = db.prepare('SELECT value FROM activity_metadata WHERE key=?').get(key)?.value;
    if (canonicalMetadataInteger(raw, minimum) == null) return false;
  }
  if (!REQUIRED_ACTIVITY_DATABASE_ROLES.includes(db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get()?.value)) return false;
  const binding = db.prepare("SELECT value FROM activity_metadata WHERE key='database_binding_digest'").get()?.value;
  if (
    typeof binding !== 'string'
    || !/^[a-f0-9]{64}$/.test(binding)
    || (expectedDatabaseBindingDigest !== null && binding !== expectedDatabaseBindingDigest)
  ) return false;
  const cursorSecret = db.prepare("SELECT value FROM core_metadata WHERE key='cursor_secret'").get()?.value;
  if (typeof cursorSecret !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(cursorSecret)) return false;
  const barriers = db.prepare(`SELECT event_id_digest,probe_id,origin_sequence,canonical_digest,retired_at_ms
    FROM activity_event_replay_barriers`).all();
  const barrierSequences = new Set();
  for (const barrier of barriers) {
    if (
      typeof barrier.event_id_digest !== 'string' || !/^[a-f0-9]{64}$/.test(barrier.event_id_digest)
      || typeof barrier.probe_id !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(barrier.probe_id)
      || !Number.isSafeInteger(barrier.origin_sequence) || barrier.origin_sequence < 0
      || typeof barrier.canonical_digest !== 'string' || !/^[a-f0-9]{64}$/.test(barrier.canonical_digest)
      || !Number.isSafeInteger(barrier.retired_at_ms) || barrier.retired_at_ms < 0
    ) return false;
    barrierSequences.add(`${barrier.probe_id}\u0000${barrier.origin_sequence}`);
  }
  const states = db.prepare('SELECT probe_id,max_origin_sequence,retained_origin_floor FROM activity_probe_state').all();
  for (const state of states) {
    if (
      (state.max_origin_sequence != null && (!Number.isSafeInteger(state.max_origin_sequence) || state.max_origin_sequence < 0))
      || (state.retained_origin_floor != null && (
        !Number.isSafeInteger(state.retained_origin_floor)
        || state.retained_origin_floor < 0
        || (state.max_origin_sequence != null && state.max_origin_sequence < state.retained_origin_floor)
        || !barrierSequences.has(`${state.probe_id}\u0000${state.retained_origin_floor}`)
      ))
    ) return false;
  }
  const tombstones = db.prepare('SELECT event_id,probe_id,origin_sequence,canonical_digest FROM activity_event_tombstones').all();
  for (const tombstone of tombstones) {
    const barrier = db.prepare(`SELECT canonical_digest FROM activity_event_replay_barriers
      WHERE event_id_digest=? AND probe_id=? AND origin_sequence=?`).get(
      legacyReplayEventIdDigest(cursorSecret, tombstone.event_id),
      tombstone.probe_id,
      tombstone.origin_sequence,
    );
    if (!barrier || barrier.canonical_digest !== legacyReplayCanonicalDigest(cursorSecret, tombstone.canonical_digest)) return false;
  }
  return true;
}

export function preflightActivityLegacyMigration(db, { expectedDatabaseBindingDigest = null } = {}) {
  const legacyV4 = legacyActivityV4Ready(db, expectedDatabaseBindingDigest);
  const legacyV3 = legacyActivityV3Ready(db);
  const legacyV2 = legacyActivityV2Ready(db);
  const legacyV1 = legacyActivityV1Ready(db);
  if (legacyV4 && !legacyActivityDomainVirgin(db, 4)) {
    fail(
      'activity_legacy_binding_authorization_required',
      'Non-empty activity schema 4 history cannot be migrated into structured event identity safely.',
      { status: 503 },
    );
  }
  const unsafeUnboundLegacy = (legacyV1 && !legacyActivityDomainVirgin(db, 1))
    || (legacyV2 && !legacyActivityDomainVirgin(db, 2))
    || (legacyV3 && !legacyActivityDomainVirgin(db, 3));
  if (unsafeUnboundLegacy) {
    fail(
      'activity_legacy_binding_authorization_required',
      'Non-empty unbound legacy activity history cannot be migrated without an external path and history authorization.',
      { status: 503 },
    );
  }
  return { legacyV1, legacyV2, legacyV3, legacyV4 };
}

export function activitySchemaStatus(db, {
  expectedDatabaseBindingDigest = null,
  deepAudit = true,
} = {}) {
  if (!tableExists(db, 'core_metadata')) {
    return { ready: false, schema_version: 0, reason: 'core_metadata_invariant_failed', missing_tables: [] };
  }
  const missingTables = REQUIRED_ACTIVITY_TABLES.filter((name) => !tableExists(db, name));
  if (missingTables.length) return { ready: false, schema_version: 0, reason: 'missing_tables', missing_tables: missingTables };
  const expectedDdl = expectedActivityDdl();
  for (const [name, expected] of expectedDdl) {
    const actual = normalizedSchemaSql(db.prepare('SELECT sql FROM sqlite_master WHERE name=?').get(name)?.sql);
    if (actual !== expected) {
      return {
        ready: false,
        schema_version: 0,
        reason: 'ddl_invariant_failed',
        missing_tables: [],
        schema_object: name,
      };
    }
  }
  for (const [table, columns] of Object.entries(REQUIRED_ACTIVITY_COLUMNS)) {
    const actual = new Set(db.prepare(`PRAGMA table_info(${table})`).all().map((row) => row.name));
    const missing = columns.filter((column) => !actual.has(column));
    if (missing.length) {
      return {
        ready: false,
        schema_version: 0,
        reason: 'missing_columns',
        missing_tables: [],
        missing_columns: { [table]: missing },
      };
    }
  }
  for (const [table, expected] of Object.entries(REQUIRED_ACTIVITY_PRIMARY_KEYS)) {
    const actual = tablePrimaryKey(db, table);
    if (!sameColumns(actual, expected)) {
      return {
        ready: false,
        schema_version: 0,
        reason: 'primary_key_invariant_failed',
        missing_tables: [],
        constraint: { table, expected, actual },
      };
    }
  }
  for (const [table, expectedKeys] of Object.entries(REQUIRED_ACTIVITY_UNIQUE_KEYS)) {
    const indexList = db.prepare(`PRAGMA index_list(${table})`).all();
    const actualKeys = indexList.filter((row) => Number(row.unique) === 1)
      .map((row) => indexColumns(db, row.name));
    const missing = expectedKeys.filter((expected) => !actualKeys.some((actual) => sameColumns(actual, expected)));
    if (missing.length) {
      return {
        ready: false,
        schema_version: 0,
        reason: 'unique_constraint_invariant_failed',
        missing_tables: [],
        constraint: { table, missing },
      };
    }
  }
  for (const table of REQUIRED_ACTIVITY_TABLES) {
    const allowedConstraintKeys = REQUIRED_ACTIVITY_UNIQUE_KEYS[table] ?? [];
    const unexpectedUnique = db.prepare(`PRAGMA index_list(${table})`).all().find((index) => {
      if (Number(index.unique) !== 1 || index.origin === 'pk') return false;
      if (index.name === 'activity_principals_event_prefix_idx') return false;
      return index.origin === 'c'
        || !allowedConstraintKeys.some((expected) => sameColumns(indexColumns(db, index.name), expected));
    });
    if (unexpectedUnique) {
      return {
        ready: false,
        schema_version: 0,
        reason: 'unexpected_unique_index',
        missing_tables: [],
        index: { name: unexpectedUnique.name, table },
      };
    }
  }
  const unexpectedTrigger = db.prepare(`SELECT name,tbl_name FROM sqlite_master
    WHERE type='trigger' AND tbl_name LIKE 'activity\_%' ESCAPE '\\' ORDER BY name LIMIT 1`).get();
  if (unexpectedTrigger) {
    return {
      ready: false,
      schema_version: 0,
      reason: 'unexpected_activity_trigger',
      missing_tables: [],
      trigger: { name: unexpectedTrigger.name, table: unexpectedTrigger.tbl_name },
    };
  }
  const foreignKeyViolation = deepAudit ? db.prepare('PRAGMA foreign_key_check').get() : null;
  if (foreignKeyViolation) {
    return {
      ready: false,
      schema_version: 0,
      reason: 'foreign_key_invariant_failed',
      missing_tables: [],
      foreign_key: { table: foreignKeyViolation.table, rowid: foreignKeyViolation.rowid },
    };
  }
  for (const [name, expected] of Object.entries(REQUIRED_ACTIVITY_INDEXES)) {
    const index = db.prepare("SELECT tbl_name FROM sqlite_master WHERE type='index' AND name=?").get(name);
    const indexListEntry = index
      ? db.prepare(`PRAGMA index_list(${expected.table})`).all().find((entry) => entry.name === name)
      : null;
    const columns = index ? indexColumns(db, name) : [];
    if (
      !index
      || index.tbl_name !== expected.table
      || !sameColumns(columns, expected.columns)
      || (expected.unique === true && Number(indexListEntry?.unique) !== 1)
    ) {
      return {
        ready: false,
        schema_version: 0,
        reason: 'index_invariant_failed',
        missing_tables: [],
        index: { name, expected, actual: index ? { table: index.tbl_name, columns } : null },
      };
    }
  }
  const migrationRows = db.prepare('SELECT version,state,checksum FROM activity_schema_migrations ORDER BY version').all();
  const expectedMigrationChecksums = new Map([
    [1, ACTIVITY_SCHEMA_V1_CHECKSUM],
    [2, ACTIVITY_SCHEMA_V2_CHECKSUM],
    [3, ACTIVITY_SCHEMA_V3_CHECKSUM],
    [4, ACTIVITY_SCHEMA_V4_CHECKSUM],
    [ACTIVITY_SCHEMA_VERSION, canonicalActivityDigest(activityMigrationSql())],
  ]);
  const migrationVersions = migrationRows.map((row) => Number(row.version));
  const validMigrationTrajectory = migrationVersions.length === 1
    ? migrationVersions[0] === ACTIVITY_SCHEMA_VERSION
    : migrationVersions.length === 2
      ? (
        migrationVersions[1] === ACTIVITY_SCHEMA_VERSION
        && migrationVersions[0] >= 1
        && migrationVersions[0] < ACTIVITY_SCHEMA_VERSION
      )
      : false;
  if (migrationRows.some((row) => (
    !Number.isSafeInteger(row.version)
    || row.version < 1
    || row.version > ACTIVITY_SCHEMA_VERSION
    || row.state !== 'committed'
    || row.checksum !== expectedMigrationChecksums.get(row.version)
  )) || !validMigrationTrajectory) {
    return { ready: false, schema_version: 0, reason: 'migration_ledger_invariant_failed', missing_tables: [] };
  }
  const migration = migrationRows.find((row) => row.version === ACTIVITY_SCHEMA_VERSION);
  const metadataVersionRaw = db.prepare("SELECT value FROM core_metadata WHERE key='activity_schema_version'").get()?.value;
  const metadataVersion = canonicalMetadataInteger(metadataVersionRaw, ACTIVITY_SCHEMA_VERSION);
  const coreSchemaVersion = canonicalMetadataInteger(
    db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get()?.value,
    5,
  );
  const expectedChecksum = canonicalActivityDigest(activityMigrationSql());
  if (
    !migration || migration.state !== 'committed' || migration.checksum !== expectedChecksum
    || metadataVersion !== ACTIVITY_SCHEMA_VERSION || ![5, 6].includes(coreSchemaVersion)
  ) {
    return { ready: false, schema_version: metadataVersion ?? 0, reason: 'migration_invariant_failed', missing_tables: [] };
  }
  const coreNodeId = db.prepare("SELECT value FROM core_metadata WHERE key='node_id'").get()?.value;
  const coreCursorSecret = db.prepare("SELECT value FROM core_metadata WHERE key='cursor_secret'").get()?.value;
  if (
    typeof coreNodeId !== 'string'
    || !/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(coreNodeId)
    || typeof coreCursorSecret !== 'string'
    || !/^[A-Za-z0-9_-]{43}$/.test(coreCursorSecret)
  ) {
    return { ready: false, schema_version: metadataVersion, reason: 'core_metadata_invariant_failed', missing_tables: [] };
  }
  const metadata = new Map(db.prepare('SELECT key,value FROM activity_metadata').all().map((row) => [row.key, row.value]));
  if (metadata.get('integrity_commitment_version') !== String(ACTIVITY_INTEGRITY_COMMITMENT_VERSION)) {
    return { ready: false, schema_version: metadataVersion, reason: 'integrity_commitment_version_unsupported', missing_tables: [] };
  }
  const values = {};
  for (const [key, minimum] of Object.entries(REQUIRED_ACTIVITY_METADATA)) {
    const value = canonicalMetadataInteger(metadata.get(key), minimum);
    if (value == null) {
      return {
        ready: false,
        schema_version: metadataVersion,
        reason: 'metadata_invariant_failed',
        missing_tables: [],
        metadata: { key, minimum, actual: metadata.has(key) ? metadata.get(key) : null },
      };
    }
    values[key] = value;
  }
  if (safeIntegerSum(values.server_time_floor_ms, ACTIVITY_RAW_RETENTION_MS) == null) {
    return { ready: false, schema_version: metadataVersion, reason: 'server_time_floor_invariant_failed', missing_tables: [] };
  }
  if (!REQUIRED_ACTIVITY_DATABASE_ROLES.includes(metadata.get('database_role'))) {
    return {
      ready: false,
      schema_version: metadataVersion,
      reason: 'metadata_invariant_failed',
      missing_tables: [],
      metadata: { key: 'database_role', actual: metadata.get('database_role') ?? null },
    };
  }
  const databaseBindingDigest = metadata.get('database_binding_digest');
  if (
    typeof databaseBindingDigest !== 'string'
    || !/^[a-f0-9]{64}$/.test(databaseBindingDigest)
    || (
      expectedDatabaseBindingDigest !== null
      && databaseBindingDigest !== expectedDatabaseBindingDigest
    )
  ) {
    return {
      ready: false,
      schema_version: metadataVersion,
      reason: 'database_binding_invariant_failed',
      missing_tables: [],
    };
  }
  const principalIdentityMismatch = db.prepare(`SELECT 1 AS found FROM activity_principals
    WHERE authority_node_id<>? OR authority_epoch<>? LIMIT 1`).get(coreNodeId, values.authority_epoch);
  if (principalIdentityMismatch) {
    return { ready: false, schema_version: metadataVersion, reason: 'principal_authority_invariant_failed', missing_tables: [] };
  }
  const persistedAuthority = validatePersistedActivityAuthority(db);
  if (!persistedAuthority.ready) {
    return { ready: false, schema_version: metadataVersion, reason: persistedAuthority.reason, missing_tables: [] };
  }
  const invalidStatusReason = db.prepare(`SELECT 1 AS found FROM activity_projections
    WHERE status_reason NOT IN (${ACTIVITY_STATUS_REASONS.map(() => '?').join(',')}) LIMIT 1`)
    .get(...ACTIVITY_STATUS_REASONS);
  if (invalidStatusReason) {
    return { ready: false, schema_version: metadataVersion, reason: 'projection_vocabulary_invariant_failed', missing_tables: [] };
  }
  const tombstones = deepAudit
    ? db.prepare(`SELECT event_id,device_id,probe_id,origin_sequence,canonical_digest
      FROM activity_event_tombstones ORDER BY event_id`).all()
    : [];
  const invalidProbeStateInteger = db.prepare(`SELECT 1 AS found FROM activity_probe_state
    WHERE (max_origin_sequence IS NOT NULL AND (
      typeof(max_origin_sequence)<>'integer'
      OR max_origin_sequence<0 OR max_origin_sequence>9007199254740991
    )) OR (retained_origin_floor IS NOT NULL AND (
      typeof(retained_origin_floor)<>'integer'
      OR retained_origin_floor<0 OR retained_origin_floor>9007199254740991
    ))
    LIMIT 1`).get();
  if (invalidProbeStateInteger) {
    return { ready: false, schema_version: metadataVersion, reason: 'replay_floor_invariant_failed', missing_tables: [] };
  }
  const replayState = replayCommitment(db, coreCursorSecret);
  if (
    !replayState
    || replayState.count !== values.replay_floor_count
    || typeof metadata.get('replay_floor_root') !== 'string'
    || !/^[a-f0-9]{64}$/.test(metadata.get('replay_floor_root'))
    || replayState.root !== metadata.get('replay_floor_root')
  ) {
    return { ready: false, schema_version: metadataVersion, reason: 'replay_floor_invariant_failed', missing_tables: [] };
  }
  const probeStates = db.prepare('SELECT * FROM activity_probe_state').all();
  for (const state of probeStates) {
    const maxOriginValid = state.max_origin_sequence == null
      || (Number.isSafeInteger(state.max_origin_sequence) && state.max_origin_sequence >= 0);
    const floorValid = state.retained_origin_floor == null
      || (
        Number.isSafeInteger(state.retained_origin_floor)
        && state.retained_origin_floor >= 0
        && (
          state.max_origin_sequence == null
          || state.max_origin_sequence >= state.retained_origin_floor
        )
      );
    let contextValid = true;
    try { retiredContext(state); } catch { contextValid = false; }
    if (!maxOriginValid || !floorValid || !contextValid) {
      return { ready: false, schema_version: metadataVersion, reason: 'replay_floor_invariant_failed', missing_tables: [] };
    }
  }
  const probes = db.prepare(`SELECT principal_id,device_id,probe_id,event_id_prefix,retired_event_prefix_digest,
    retired_floor_digest,revoked_at_ms,deleted_at_ms,expiry_slo_ms,authority_node_id,authority_epoch
    FROM activity_principals WHERE principal_type='probe'`).all();
  const probesById = new Map(probes.map((probe) => [probe.probe_id, probe]));
  const retiredLineages = db.prepare('SELECT lineage_digest,floor_digest FROM activity_replay_lineage_floors').all();
  for (const probe of probes) {
    const state = probeStates.find((candidate) => candidate.probe_id === probe.probe_id);
    if (probe.deleted_at_ms == null) {
      if (
        !state
        || typeof probe.event_id_prefix !== 'string'
        || !/^[A-Za-z0-9_-]{22,64}$/.test(probe.event_id_prefix)
        || probe.retired_event_prefix_digest != null
        || probe.retired_floor_digest != null
      ) {
        return { ready: false, schema_version: metadataVersion, reason: 'replay_floor_invariant_failed', missing_tables: [] };
      }
    } else {
      const retired = typeof probe.retired_event_prefix_digest === 'string'
        ? db.prepare('SELECT floor_digest FROM activity_replay_lineage_floors WHERE lineage_digest=?')
          .get(probe.retired_event_prefix_digest)
        : null;
      if (
        state
        || probe.event_id_prefix != null
        || typeof probe.retired_event_prefix_digest !== 'string'
        || !/^[a-f0-9]{64}$/.test(probe.retired_event_prefix_digest)
        || typeof probe.retired_floor_digest !== 'string'
        || !/^[a-f0-9]{64}$/.test(probe.retired_floor_digest)
        || retired?.floor_digest !== probe.retired_floor_digest
      ) {
        return { ready: false, schema_version: metadataVersion, reason: 'replay_floor_invariant_failed', missing_tables: [] };
      }
    }
  }
  if (
    retiredLineages.length !== probes.filter((probe) => probe.deleted_at_ms != null).length
    || retiredLineages.some((lineage) => probes.filter((probe) => (
      probe.deleted_at_ms != null
      && probe.retired_event_prefix_digest === lineage.lineage_digest
      && probe.retired_floor_digest === lineage.floor_digest
    )).length !== 1)
  ) {
    return { ready: false, schema_version: metadataVersion, reason: 'replay_floor_invariant_failed', missing_tables: [] };
  }
  const events = deepAudit
    ? db.prepare(`SELECT event_id,device_id,probe_id,origin_sequence,kind,occurred_at_ms,
      ttl_ms,confidence,source,coverage_json,payload_json,canonical_digest,received_at_ms,server_sequence,
      clock_health,receipt_id,credential_generation,authority_node_id,authority_epoch FROM activity_events ORDER BY server_sequence`).all()
    : [];
  if (
    deepAudit
    && (
      values.retired_event_count > values.accepted_event_count
      || events.length + values.retired_event_count !== values.accepted_event_count
    )
  ) {
    return { ready: false, schema_version: metadataVersion, reason: 'accepted_history_invariant_failed', missing_tables: [] };
  }
  const eventsById = new Map(events.map((event) => [event.event_id, event]));
  const eventsByServerSequence = new Map(events.map((event) => [event.server_sequence, event]));
  const normalizedEventsById = new Map();
  const issuedCredentials = db.prepare('SELECT principal_id,generation,issued_at_ms,revoked_at_ms FROM activity_credentials').all();
  const latestEventsByProbe = new Map();
  const expectedClockHealthByEventId = new Map();
  const logicalClockHealthByEventId = new Map();
  if (deepAudit) {
    for (const probe of probes.filter((candidate) => candidate.deleted_at_ms == null)) {
      const state = probeStates.find((candidate) => candidate.probe_id === probe.probe_id);
      const probeEvents = events.filter((event) => event.probe_id === probe.probe_id);
      const anchors = new Map();
      try {
        for (const event of probeEvents) {
          const change = db.prepare('SELECT * FROM activity_changes WHERE server_sequence=?').get(event.server_sequence);
          anchors.set(event.event_id, activityChangePayload(change).acceptance_clock_prior_signal_at_ms);
        }
      } catch {
        return { ready: false, schema_version: metadataVersion, reason: 'change_lineage_invariant_failed', missing_tables: [] };
      }
      const health = activityClockHealthMaps(probeEvents, {
        retiredSignal: retiredContext(state).max_signal_at_ms,
        retainedFloor: state?.retained_origin_floor ?? null, acceptanceAnchors: anchors,
      });
      if (!health) {
        return { ready: false, schema_version: metadataVersion, reason: 'event_lineage_invariant_failed', missing_tables: [] };
      }
      for (const [eventId, value] of health.acceptance) expectedClockHealthByEventId.set(eventId, value);
      for (const [eventId, value] of health.logical) logicalClockHealthByEventId.set(eventId, value);
    }
  }
  for (const event of events) {
    const principal = probesById.get(event.probe_id);
    let normalizedDigest = null;
    let normalizedEvent = null;
    try {
      normalizedEvent = normalizeActivityEvent({
        contract: ACTIVITY_CONTRACT,
        schema_version: ACTIVITY_FEATURE_VERSION,
        event_id: event.event_id,
        device_id: event.device_id,
        probe_id: event.probe_id,
        origin_sequence: event.origin_sequence,
        kind: event.kind,
        signal_at_ms: event.occurred_at_ms,
        ttl_ms: event.ttl_ms,
        confidence: event.confidence,
        source: event.source,
        coverage: JSON.parse(event.coverage_json),
        payload: JSON.parse(event.payload_json),
      });
      normalizedDigest = canonicalActivityDigest(normalizedEvent);
    } catch {
      normalizedDigest = null;
    }
    if (
      !principal
      || principal.deleted_at_ms != null
      || principal.device_id !== event.device_id
      || !structuredEventIdentityMatches(event.event_id, principal.event_id_prefix, event.origin_sequence)
      || typeof event.canonical_digest !== 'string'
      || !/^[a-f0-9]{64}$/.test(event.canonical_digest)
      || normalizedDigest !== event.canonical_digest
      || event.clock_health !== expectedClockHealthByEventId.get(event.event_id)
      || event.authority_node_id !== coreNodeId
      || event.authority_epoch !== values.authority_epoch
      || event.received_at_ms > values.server_time_floor_ms
      || !issuedCredentials.some((credential) => (
        credential.principal_id === principal.principal_id
        && credential.generation === event.credential_generation
        && event.received_at_ms >= credential.issued_at_ms
        && (credential.revoked_at_ms == null || event.received_at_ms <= credential.revoked_at_ms)
      ))
    ) {
      return { ready: false, schema_version: metadataVersion, reason: 'event_lineage_invariant_failed', missing_tables: [] };
    }
    normalizedEventsById.set(event.event_id, normalizedEvent);
    const latestForProbe = latestEventsByProbe.get(event.probe_id);
    if (!latestForProbe || Number(event.origin_sequence) > Number(latestForProbe.origin_sequence)) {
      latestEventsByProbe.set(event.probe_id, event);
    }
  }
  const deepSequenceGapByProbe = new Map();
  if (deepAudit) {
    for (const probe of probes.filter((candidate) => candidate.deleted_at_ms == null)) {
      const state = probeStates.find((candidate) => candidate.probe_id === probe.probe_id);
      const sequences = events
        .filter((event) => event.probe_id === probe.probe_id)
        .map((event) => Number(event.origin_sequence));
      const floor = state?.retained_origin_floor == null ? null : Number(state.retained_origin_floor);
      if (floor != null && sequences.some((sequence) => sequence <= floor)) {
        return { ready: false, schema_version: metadataVersion, reason: 'retired_prefix_closure_invariant_failed', missing_tables: [] };
      }
      const expectedGap = activitySequenceCoverage(sequences, floor).missing.length > 0;
      deepSequenceGapByProbe.set(probe.probe_id, expectedGap);
      if (
        (expectedGap && !['gap', 'permission_unavailable', 'permission_recovery_pending'].includes(state?.last_coverage_status))
        || (!expectedGap && state?.last_coverage_status === 'gap')
      ) {
        return { ready: false, schema_version: metadataVersion, reason: 'coverage_gap_invariant_failed', missing_tables: [] };
      }
    }
  }
  for (const tombstone of tombstones) {
    const state = db.prepare('SELECT retained_origin_floor FROM activity_probe_state WHERE probe_id=?').get(tombstone.probe_id);
    const principal = probesById.get(tombstone.probe_id);
    const eventIdMatch = /^[A-Za-z0-9_-]{22,64}\.(?:0|[1-9]\d*)$/.exec(tombstone.event_id);
    const prefix = eventIdMatch ? tombstone.event_id.slice(0, tombstone.event_id.lastIndexOf('.')) : null;
    const structuredIdentityValid = principal?.deleted_at_ms == null
      ? structuredEventIdentityMatches(tombstone.event_id, principal?.event_id_prefix, tombstone.origin_sequence)
      : structuredEventIdentityMatches(tombstone.event_id, prefix, tombstone.origin_sequence)
        && replayPrefixDigest(coreCursorSecret, prefix) === principal?.retired_event_prefix_digest;
    if (
      !principal
      || principal.device_id !== tombstone.device_id
      || !structuredIdentityValid
      || typeof tombstone.canonical_digest !== 'string'
      || !/^[a-f0-9]{64}$/.test(tombstone.canonical_digest)
      || (
        principal.deleted_at_ms == null
        && (
          !state
          || !Number.isSafeInteger(state.retained_origin_floor)
          || state.retained_origin_floor < tombstone.origin_sequence
        )
      )
    ) {
      return { ready: false, schema_version: metadataVersion, reason: 'replay_floor_invariant_failed', missing_tables: [] };
    }
  }
  const projections = deepAudit
    ? db.prepare('SELECT * FROM activity_projections ORDER BY device_id,probe_id').all()
    : [];
  if (deepAudit && probes.some((probe) => probe.deleted_at_ms == null && (
    projections.filter((row) => row.probe_id === probe.probe_id && row.device_id === probe.device_id).length !== 1
    || probeStates.filter((row) => row.probe_id === probe.probe_id).length !== 1
  ))) {
    return { ready: false, schema_version: metadataVersion, reason: 'probe_materialization_invariant_failed', missing_tables: [] };
  }
  for (const projection of projections) {
    const principal = probesById.get(projection.probe_id);
    const currentEvent = projection.current_event_id == null ? null : eventsById.get(projection.current_event_id);
    const normalizedCurrentEvent = projection.current_event_id == null
      ? null
      : normalizedEventsById.get(projection.current_event_id);
    const probeState = probeStates.find((state) => state.probe_id === projection.probe_id);
    const laterEvent = currentEvent == null ? null : latestEventsByProbe.get(projection.probe_id);
    const noCurrentEventCanonical = projection.current_event_id == null
      && projection.state === 'unknown'
      && (
        (projection.coverage_status === 'missing' && projection.status_reason === 'unobserved')
        || (projection.coverage_status === 'revoked' && projection.status_reason === 'credential_revoked')
        || (projection.coverage_status === 'retention_expired' && projection.status_reason === 'retention_expired')
        || (projection.coverage_status === 'core_restart_gap' && projection.status_reason === 'core_restart_gap')
      )
      && ['unknown', 'core_restart_gap'].includes(projection.clock_health);
    const currentEventConsistent = currentEvent
      && currentEvent.device_id === projection.device_id
      && currentEvent.probe_id === projection.probe_id
      && Number(currentEvent.occurred_at_ms) === Number(projection.occurred_at_ms)
      && Number(currentEvent.received_at_ms) === Number(projection.received_at_ms)
      && Number(currentEvent.server_sequence) === Number(projection.last_server_sequence)
      && currentEvent.confidence === projection.confidence
      && currentEvent.coverage_json === projection.coverage_json;
    let derivedProjectionValid = true;
    if (currentEventConsistent && normalizedCurrentEvent) {
      const currentLogicalClockHealth = logicalClockHealthByEventId.get(currentEvent.event_id);
      const laterLogicalClockHealth = laterEvent == null
        ? null
        : logicalClockHealthByEventId.get(laterEvent.event_id);
      const coverage = normalizedCurrentEvent.coverage;
      const coverageExpiry = safeIntegerSum(Number(currentEvent.occurred_at_ms), Number(principal.expiry_slo_ms));
      const projectionExpiry = safeIntegerSum(
        Number(currentEvent.occurred_at_ms),
        Math.min(Number(currentEvent.ttl_ms), Number(principal.expiry_slo_ms)),
      );
      const baseCoverageStatus = coverageExpiry != null && Number(currentEvent.received_at_ms) > coverageExpiry
        ? 'stale'
        : ['none', 'unknown'].includes(coverage.mode)
          ? 'missing'
          : 'covered';
      const baseState = projectionState(normalizedCurrentEvent, {
        clockHealth: currentLogicalClockHealth,
        coverageStatus: baseCoverageStatus,
      });
      let expectedState = baseState;
      let expectedCoverageStatus = baseCoverageStatus;
      let expectedClockHealth = currentLogicalClockHealth;
      let expectedStatusReason = projectionStatusReason(normalizedCurrentEvent, {
        clockHealth: currentLogicalClockHealth,
        coverageStatus: baseCoverageStatus,
        state: baseState,
      });
      let expectedCredentialState = 'active';
      if (principal.revoked_at_ms != null) {
        expectedState = 'unknown';
        expectedCoverageStatus = 'revoked';
        expectedStatusReason = 'credential_revoked';
        expectedCredentialState = 'revoked';
      } else if (projection.coverage_status === 'core_restart_gap') {
        expectedState = 'unknown';
        expectedCoverageStatus = 'core_restart_gap';
        expectedClockHealth = 'unknown';
        expectedStatusReason = 'core_restart_gap';
      } else if (deepSequenceGapByProbe.get(projection.probe_id) === true) {
        expectedState = 'unknown';
        expectedCoverageStatus = 'gap';
        if (laterEvent && ['future_skew', 'clock_regression'].includes(laterLogicalClockHealth)) {
          expectedClockHealth = laterLogicalClockHealth;
        }
        expectedStatusReason = 'coverage_gap';
      } else if (probeState?.last_coverage_status === 'permission_unavailable') {
        expectedState = 'unknown';
        expectedStatusReason = 'permission_unavailable';
        if (laterEvent && laterEvent.origin_sequence > currentEvent.origin_sequence
          && ['future_skew', 'clock_regression'].includes(laterLogicalClockHealth)) expectedClockHealth = laterLogicalClockHealth;
      } else if (probeState?.last_coverage_status === 'permission_recovery_pending') {
        expectedState = 'unknown';
        expectedStatusReason = 'insufficient_human_evidence';
        if (laterEvent && laterEvent.origin_sequence > currentEvent.origin_sequence
          && ['future_skew', 'clock_regression'].includes(laterLogicalClockHealth)) expectedClockHealth = laterLogicalClockHealth;
      } else if (
        laterEvent
        && Number(laterEvent.origin_sequence) > Number(currentEvent.origin_sequence)
        && ['probe.error', 'probe.permission_changed'].includes(laterEvent.kind)
      ) {
        expectedState = 'unknown';
        const laterNormalized = normalizedEventsById.get(laterEvent.event_id);
        expectedStatusReason = laterEvent.kind === 'probe.error'
          ? 'probe_error'
          : laterNormalized?.payload?.available === false
            ? 'permission_unavailable'
            : 'insufficient_human_evidence';
        if (['future_skew', 'clock_regression'].includes(laterLogicalClockHealth)) {
          expectedClockHealth = laterLogicalClockHealth;
        }
      } else if (
        laterEvent
        && Number(laterEvent.origin_sequence) > Number(currentEvent.origin_sequence)
        && ['future_skew', 'clock_regression'].includes(laterLogicalClockHealth)
      ) {
        expectedState = 'unknown';
        expectedClockHealth = laterLogicalClockHealth;
        expectedStatusReason = laterLogicalClockHealth;
      }
      derivedProjectionValid = coverageExpiry != null
        && projectionExpiry != null
        && Number(projection.expires_at_ms) === projectionExpiry
        && projection.state === expectedState
        && projection.coverage_status === expectedCoverageStatus
        && projection.clock_health === expectedClockHealth
        && projection.status_reason === expectedStatusReason
        && projection.credential_state === expectedCredentialState;
    }
    if (
      !principal
      || principal.deleted_at_ms != null
      || principal.device_id !== projection.device_id
      || (projection.current_event_id == null
        ? !noCurrentEventCanonical
        : !currentEventConsistent || !derivedProjectionValid)
    ) {
      return { ready: false, schema_version: metadataVersion, reason: 'projection_lineage_invariant_failed', missing_tables: [] };
    }
  }
  const runtime = db.prepare('SELECT singleton,runtime_id,runtime_fence,lease_expires_at_ms FROM activity_runtime_claim').all();
  if (
    runtime.length !== 1
    || Number(runtime[0].singleton) !== 1
    || typeof runtime[0].runtime_id !== 'string'
    || !Number.isSafeInteger(Number(runtime[0].runtime_fence))
    || Number(runtime[0].runtime_fence) < 0
    || !Number.isSafeInteger(Number(runtime[0].lease_expires_at_ms))
    || Number(runtime[0].lease_expires_at_ms) < 0
  ) {
    return { ready: false, schema_version: metadataVersion, reason: 'runtime_claim_invariant_failed', missing_tables: [] };
  }
  const latestChange = Number(db.prepare('SELECT COALESCE(MAX(server_sequence),0) AS value FROM activity_changes').get().value);
  if (deepAudit) {
    const changes = db.prepare('SELECT * FROM activity_changes ORDER BY server_sequence').all();
    for (const change of changes) {
      let valid = false;
      try {
        const payload = activityChangePayload(change);
        const generationValid = Number.isSafeInteger(payload.snapshot_generation)
          && payload.snapshot_generation >= 1 && payload.snapshot_generation <= values.snapshot_generation;
        let expected;
        if (change.kind === 'activity.event.accepted') {
          const event = eventsByServerSequence.get(change.server_sequence);
          expected = event && {
            event_id: event.event_id, device_id: event.device_id, probe_id: event.probe_id,
            receipt_id: event.receipt_id, occurred_at_ms: event.occurred_at_ms,
            received_at_ms: event.received_at_ms, receipt_observation: payload.receipt_observation,
            acceptance_clock_prior_signal_at_ms: payload.acceptance_clock_prior_signal_at_ms,
          };
          valid = event != null && change.device_id === event.device_id && change.probe_id === event.probe_id
            && change.occurred_at_ms === event.received_at_ms && activityReceiptObservationValid(payload.receipt_observation);
        } else if (change.kind === 'activity.probe.revoked') {
          const probe = probesById.get(change.probe_id);
          expected = { device_id: change.device_id, probe_id: change.probe_id, snapshot_generation: payload.snapshot_generation };
          valid = generationValid && probe?.device_id === change.device_id && probe.revoked_at_ms === change.occurred_at_ms;
        } else if (['activity.probe.deleted', 'activity.device.deleted'].includes(change.kind)) {
          const receipt = db.prepare('SELECT * FROM activity_deletion_receipts WHERE receipt_id=?').get(payload.receipt_id);
          expected = { receipt_id: payload.receipt_id, device_id: change.device_id,
            ...(change.kind === 'activity.probe.deleted' ? { probe_id: change.probe_id } : {}),
            snapshot_generation: payload.snapshot_generation };
          valid = generationValid && receipt != null && receipt.device_id === change.device_id
            && receipt.probe_id === change.probe_id && receipt.completed_at_ms === change.occurred_at_ms
            && receipt.snapshot_generation === payload.snapshot_generation
            && receipt.scope === (change.kind === 'activity.probe.deleted' ? 'probe' : 'device');
        } else if (change.kind === 'activity.core_restart_gap') {
          expected = { runtime_fence: payload.runtime_fence, snapshot_generation: payload.snapshot_generation };
          valid = generationValid && change.device_id == null && change.probe_id == null
            && Number.isSafeInteger(payload.runtime_fence) && payload.runtime_fence >= 2
            && payload.runtime_fence <= Number(runtime[0].runtime_fence);
        } else if (change.kind === 'activity.retention.cleaned') {
          expected = { retained_watermark: payload.retained_watermark, snapshot_generation: payload.snapshot_generation };
          valid = generationValid && change.device_id == null && change.probe_id == null
            && Number.isSafeInteger(payload.retained_watermark) && payload.retained_watermark >= 0
            && payload.retained_watermark <= values.retained_watermark;
        }
        valid = valid && Number.isSafeInteger(change.occurred_at_ms) && change.occurred_at_ms >= 0
          && change.occurred_at_ms <= values.server_time_floor_ms
          && canonicalActivityDigest(payload) === canonicalActivityDigest(expected)
          && activityChangeAuthenticated(db, change, coreCursorSecret);
      } catch { valid = false; }
      if (!valid) return { ready: false, schema_version: metadataVersion, reason: 'change_lineage_invariant_failed', missing_tables: [] };
    }
    const acceptedChangeSequences = new Set(changes.filter((change) => change.kind === 'activity.event.accepted').map((change) => change.server_sequence));
    if (events.some((event) => !acceptedChangeSequences.has(event.server_sequence))) {
      return { ready: false, schema_version: metadataVersion, reason: 'change_lineage_invariant_failed', missing_tables: [] };
    }
    let expectedSequence = values.retained_watermark + 1;
    const retainedChanges = db.prepare(`SELECT server_sequence FROM activity_changes
      WHERE server_sequence>? ORDER BY server_sequence`).all(values.retained_watermark);
    for (const change of retainedChanges) {
      if (Number(change.server_sequence) !== expectedSequence) {
        return { ready: false, schema_version: metadataVersion, reason: 'change_history_invariant_failed', missing_tables: [] };
      }
      expectedSequence += 1;
    }
  }
  if (values.retained_watermark > latestChange) {
    return {
      ready: false,
      schema_version: metadataVersion,
      reason: 'metadata_invariant_failed',
      missing_tables: [],
      metadata: { key: 'retained_watermark', maximum: latestChange, actual: values.retained_watermark },
    };
  }
  return { ready: true, schema_version: metadataVersion, reason: null, missing_tables: [] };
}

export function migrateActivitySchema(db, {
  now = Date.now(),
  failpoint = null,
  databaseBindingDigest = null,
  // Explicit in-process test injection for the pre-activity Core 4 -> 5 path.
  // No runtime configuration/HTTP/ENV entry point; legacy activity upgrades do not use it.
  testOnlyMigrationHook = undefined,
} = {}) {
  const current = activitySchemaStatus(db, { expectedDatabaseBindingDigest: databaseBindingDigest });
  if (current.ready) return { migrated: false, ...current };
  if (current.reason === 'integrity_commitment_version_unsupported') {
    fail('activity_integrity_upgrade_unsupported', 'Unversioned or unknown activity integrity cannot be activated or silently re-signed.', { status: 503 });
  }
  if (typeof databaseBindingDigest !== 'string' || !/^[a-f0-9]{64}$/.test(databaseBindingDigest)) {
    fail('activity_database_binding_invalid', 'Activity database path binding is required for migration.', { status: 503 });
  }
  const { legacyV1, legacyV2, legacyV3, legacyV4 } = preflightActivityLegacyMigration(db, {
    expectedDatabaseBindingDigest: databaseBindingDigest,
  });
  if (legacyV4) {
    db.exec('PRAGMA foreign_keys=OFF; PRAGMA legacy_alter_table=ON; BEGIN IMMEDIATE');
    try {
      upgradeEmptyV4ReplayState(db);
      db.prepare('INSERT INTO activity_schema_migrations(version,state,checksum,committed_at_ms) VALUES (?,?,?,?)')
        .run(ACTIVITY_SCHEMA_VERSION, 'committed', canonicalActivityDigest(activityMigrationSql()), now);
      db.prepare("UPDATE core_metadata SET value=? WHERE key='activity_schema_version'").run(String(ACTIVITY_SCHEMA_VERSION));
      db.exec('COMMIT');
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    } finally {
      db.exec('PRAGMA legacy_alter_table=OFF; PRAGMA foreign_keys=ON');
    }
    return { migrated: true, ...activitySchemaStatus(db, { expectedDatabaseBindingDigest: databaseBindingDigest }) };
  }
  if (legacyV3) {
    db.exec('PRAGMA foreign_keys=OFF; PRAGMA legacy_alter_table=ON; BEGIN IMMEDIATE');
    try {
      db.exec(activityReplayFloorSql());
      upgradePrincipalsForEventPrefix(db);
      db.exec(upgradeProbeStateForReplayFloorSql());
      initializeReplayFloorCommitment(db);
      db.prepare("INSERT INTO activity_metadata(key,value) VALUES ('database_binding_digest',?)").run(databaseBindingDigest);
      db.prepare('INSERT INTO activity_schema_migrations(version,state,checksum,committed_at_ms) VALUES (?,?,?,?)')
        .run(ACTIVITY_SCHEMA_VERSION, 'committed', canonicalActivityDigest(activityMigrationSql()), now);
      db.prepare("UPDATE core_metadata SET value=? WHERE key='activity_schema_version'").run(String(ACTIVITY_SCHEMA_VERSION));
      db.exec('COMMIT');
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    } finally {
      db.exec('PRAGMA legacy_alter_table=OFF; PRAGMA foreign_keys=ON');
    }
    return { migrated: true, ...activitySchemaStatus(db, { expectedDatabaseBindingDigest: databaseBindingDigest }) };
  }
  if (legacyV2) {
    db.exec('PRAGMA foreign_keys=OFF; PRAGMA legacy_alter_table=ON; BEGIN IMMEDIATE');
    try {
      db.exec(activityReplayFloorSql());
      upgradePrincipalsForEventPrefix(db);
      db.exec(upgradeProbeStateForReplayFloorSql());
      initializeReplayFloorCommitment(db);
      db.prepare("INSERT INTO activity_metadata(key,value) VALUES ('database_role','live')").run();
      db.prepare("INSERT INTO activity_metadata(key,value) VALUES ('database_binding_digest',?)").run(databaseBindingDigest);
      db.prepare('INSERT INTO activity_schema_migrations(version,state,checksum,committed_at_ms) VALUES (?,?,?,?)')
        .run(ACTIVITY_SCHEMA_VERSION, 'committed', canonicalActivityDigest(activityMigrationSql()), now);
      db.prepare("UPDATE core_metadata SET value=? WHERE key='activity_schema_version'").run(String(ACTIVITY_SCHEMA_VERSION));
      db.exec('COMMIT');
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    } finally {
      db.exec('PRAGMA legacy_alter_table=OFF; PRAGMA foreign_keys=ON');
    }
    return { migrated: true, ...activitySchemaStatus(db, { expectedDatabaseBindingDigest: databaseBindingDigest }) };
  }
  if (legacyV1) {
    db.exec('PRAGMA foreign_keys=OFF; PRAGMA legacy_alter_table=ON; BEGIN IMMEDIATE');
    try {
      db.exec(activityReplayFloorSql());
      upgradePrincipalsForEventPrefix(db);
      db.exec(upgradeProbeStateForReplayFloorSql());
      db.exec(`CREATE TABLE activity_runtime_claim (
        singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
        runtime_id TEXT NOT NULL,
        runtime_fence INTEGER NOT NULL,
        lease_expires_at_ms INTEGER NOT NULL
      )`);
      db.prepare("INSERT INTO activity_runtime_claim(singleton,runtime_id,runtime_fence,lease_expires_at_ms) VALUES (1,'',0,0)").run();
      const baselineHighWater = Number(
        db.prepare('SELECT COALESCE(MAX(server_sequence),0) AS value FROM activity_changes').get().value,
      );
      db.prepare("INSERT INTO activity_metadata(key,value) VALUES ('commit_high_water',?)").run(String(baselineHighWater));
      initializeReplayFloorCommitment(db);
      db.prepare("INSERT INTO activity_metadata(key,value) VALUES ('database_role','live')").run();
      db.prepare("INSERT INTO activity_metadata(key,value) VALUES ('database_binding_digest',?)").run(databaseBindingDigest);
      db.prepare('INSERT INTO activity_schema_migrations(version,state,checksum,committed_at_ms) VALUES (?,?,?,?)')
        .run(ACTIVITY_SCHEMA_VERSION, 'committed', canonicalActivityDigest(activityMigrationSql()), now);
      db.prepare("UPDATE core_metadata SET value=? WHERE key='activity_schema_version'").run(String(ACTIVITY_SCHEMA_VERSION));
      db.exec('COMMIT');
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    } finally {
      db.exec('PRAGMA legacy_alter_table=OFF; PRAGMA foreign_keys=ON');
    }
    return { migrated: true, ...activitySchemaStatus(db, { expectedDatabaseBindingDigest: databaseBindingDigest }) };
  }
  const anyActivityTable = REQUIRED_ACTIVITY_TABLES.some((name) => tableExists(db, name));
  if (anyActivityTable) {
    fail('activity_migration_incomplete', 'Partial activity schema exists without a committed invariant ledger.', { status: 503 });
  }
  db.exec('BEGIN IMMEDIATE');
  try {
    db.exec(activityMigrationSql());
    testOnlyMigrationHook?.('after_ddl');
    if (failpoint === 'after_ddl') throw new Error('synthetic activity migration interruption');
    const checksum = canonicalActivityDigest(activityMigrationSql());
    db.prepare('INSERT INTO activity_schema_migrations(version, state, checksum, committed_at_ms) VALUES (?, ?, ?, ?)')
      .run(ACTIVITY_SCHEMA_VERSION, 'committed', checksum, now);
    db.prepare("INSERT INTO activity_metadata(key,value) VALUES ('integrity_commitment_version','4'),('server_time_floor_ms','0')").run();
    db.prepare("INSERT INTO activity_metadata(key,value) VALUES ('retained_watermark','0'),('snapshot_generation','1'),('authority_epoch','1'),('commit_high_water','0'),('replay_floor_revision','0'),('replay_floor_count','0'),('accepted_event_count','0'),('retired_event_count','0'),('database_role','live'),('database_binding_digest',?)").run(databaseBindingDigest);
    writeReplayCommitment(db, db.prepare("SELECT value FROM core_metadata WHERE key='cursor_secret'").get().value);
    db.prepare("INSERT INTO activity_runtime_claim(singleton,runtime_id,runtime_fence,lease_expires_at_ms) VALUES (1,'',0,0)").run();
    db.prepare("INSERT INTO core_metadata(key,value) VALUES ('activity_schema_version',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")
      .run(String(ACTIVITY_SCHEMA_VERSION));
    db.prepare("INSERT INTO core_metadata(key,value) VALUES ('schema_version','5') ON CONFLICT(key) DO UPDATE SET value=excluded.value").run();
    testOnlyMigrationHook?.('before_commit');
    if (failpoint === 'before_commit') throw new Error('synthetic activity migration interruption');
    db.exec('COMMIT');
  } catch (error) {
    db.exec('ROLLBACK');
    throw error;
  }
  // Outside the rollback handler: COMMIT has succeeded, but no runtime is claimed.
  testOnlyMigrationHook?.('after_commit');
  return { migrated: true, ...activitySchemaStatus(db, { expectedDatabaseBindingDigest: databaseBindingDigest }) };
}

export function rollbackActivitySchema(db) {
  if (db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get()?.value === '6') {
    fail('domain_schema_present', 'Domain schema must be handled before an activity-only rollback.', { status: 409 });
  }
  const status = activitySchemaStatus(db);
  if (!status.ready) fail('activity_schema_not_ready', 'Activity schema is not in a committed state.', { status: 409 });
  const protectedRows = ['activity_events', 'activity_principals', 'activity_deletion_receipts']
    .reduce((sum, table) => sum + Number(db.prepare(`SELECT COUNT(*) AS value FROM ${table}`).get().value), 0);
  if (protectedRows !== 0) {
    fail('activity_rollback_requires_empty_domain', 'Rollback refuses to discard activity principals, events, or deletion receipts.', { status: 409 });
  }
  db.exec('BEGIN IMMEDIATE');
  try {
    for (const table of [...REQUIRED_ACTIVITY_TABLES].reverse()) db.exec(`DROP TABLE ${table}`);
    db.prepare("DELETE FROM core_metadata WHERE key='activity_schema_version'").run();
    db.prepare("UPDATE core_metadata SET value='4' WHERE key='schema_version'").run();
    db.exec('COMMIT');
  } catch (error) {
    db.exec('ROLLBACK');
    throw error;
  }
  return { rolled_back: true, core_schema_version: 4 };
}

function metadataNumber(db, key) {
  const minimum = REQUIRED_ACTIVITY_METADATA[key];
  const raw = db.prepare('SELECT value FROM activity_metadata WHERE key=?').get(key)?.value;
  const value = canonicalMetadataInteger(raw, minimum ?? 0);
  if (minimum == null || value == null) {
    fail('activity_schema_not_ready', `Activity metadata ${key} is missing or invalid.`, { status: 503 });
  }
  return value;
}

function setMetadataNumber(db, key, value) {
  const minimum = REQUIRED_ACTIVITY_METADATA[key];
  if (minimum == null || !Number.isSafeInteger(value) || value < minimum) {
    fail('activity_schema_not_ready', `Activity metadata ${key} cannot be written with an invalid value.`, { status: 503 });
  }
  db.prepare('INSERT INTO activity_metadata(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value')
    .run(key, String(value));
}

function projectionState(event, { clockHealth, coverageStatus }) {
  if (clockHealth !== 'healthy' || coverageStatus !== 'covered') return 'unknown';
  if (event.kind === 'probe.permission_changed' && event.payload.available === false) return 'unknown';
  if (event.kind === 'probe.error') return 'unknown';
  if (event.kind === 'session.locked') return 'locked';
  if (['session.unlocked', 'input.activity', 'app.category_active'].includes(event.kind) && event.confidence === 'high') return 'active';
  if (['probe.heartbeat', 'network.present'].includes(event.kind)) return 'network_only';
  return 'unknown';
}

function projectionStatusReason(event, { clockHealth, coverageStatus, state }) {
  if (clockHealth !== 'healthy') return clockHealth;
  if (coverageStatus !== 'covered') return `coverage_${coverageStatus}`;
  if (event.kind === 'probe.error') return 'probe_error';
  if (event.kind === 'probe.permission_changed' && event.payload.available === false) return 'permission_unavailable';
  if (state === 'network_only') return 'reachability_only';
  if (state === 'unknown') return 'insufficient_human_evidence';
  return 'fresh_signal';
}

export function activityRecoveryManifestForDatabase(db, { nodeId, cursorSecret }) {
  const status = activitySchemaStatus(db);
  if (!status.ready) fail('activity_schema_not_ready', 'Activity schema invariants are not committed.', { status: 503 });
  const body = recoveryBody(db, { nodeId });
  return { ...body, digest: recoveryDigest(body, cursorSecret) };
}

export function activityDatabaseRole(db) {
  const status = activitySchemaStatus(db);
  if (!status.ready) fail('activity_schema_not_ready', 'Activity schema invariants are not committed.', { status: 503 });
  return db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get().value;
}

export function assertActivityRecoveryFloorForDatabase(db, floor, { nodeId, cursorSecret }) {
  const status = activitySchemaStatus(db);
  if (!status.ready) fail('recovery_lineage_unverified', 'Recovery candidate does not contain a ready activity schema.', { status: 409 });
  let expected;
  try {
    expected = normalizeRecoveryFloor(floor, cursorSecret);
  } catch (error) {
    if (error?.code === 'recovery_lineage_unverified') throw error;
    fail('recovery_lineage_unverified', 'Activity recovery floor is malformed.', { status: 409 });
  }
  const current = recoveryBody(db, { nodeId });
  if (expected.authority.node_id !== current.authority.node_id || expected.authority.epoch !== current.authority.epoch) {
    fail('recovery_lineage_unverified', 'Recovery manifest does not match this activity authority lineage.', { status: 409 });
  }
  if (
    current.retained_watermark < expected.retained_watermark
    || current.snapshot_generation < expected.snapshot_generation
    || current.commit_high_water < expected.commit_high_water
    || current.latest_change_sequence < expected.latest_change_sequence
    || current.runtime_fence < expected.runtime_fence
  ) {
    fail('stale_activity_restore', 'Recovered activity database would move activity history backwards.', { status: 409 });
  }
  if (
    current.database_role !== expected.database_role
    || current.history_digest !== expected.history_digest
    || JSON.stringify(current.runtime_claim) !== JSON.stringify(expected.runtime_claim)
  ) {
    fail('recovery_history_diverged', 'Recovery candidate does not exactly match the trusted activity history.', { status: 409 });
  }
  const currentPrincipals = new Map(current.principals.map((item) => [item.principal_id, item]));
  for (const prior of expected.principals) {
    const candidate = currentPrincipals.get(prior.principal_id);
    if (
      !candidate
      || candidate.credential_generation < prior.credential_generation
      || (prior.revoked && !candidate.revoked)
      || (prior.deleted && !candidate.deleted)
    ) {
      fail('stale_activity_restore', 'Recovered activity database would revive or roll back an activity principal.', { status: 409 });
    }
  }
  return { ok: true, manifest: { ...current, digest: recoveryDigest(current, cursorSecret) } };
}

export class ActivityControlPlane {
  constructor(db, {
    nodeId,
    cursorSecret,
    clock = Date.now,
    runtimeId = randomUUID(),
    runtimeLeaseMs = ACTIVITY_RUNTIME_LEASE_MS,
    databaseBindingDigest = null,
    active = true,
    readOnlyDormant = false,
    eventIdPrefixFactory = () => randomBytes(16).toString('base64url'),
    testOnlyMigrationHook = undefined,
  } = {}) {
    this.db = db;
    this.nodeId = string(nodeId, 'nodeId');
    this.cursorSecret = string(cursorSecret, 'cursorSecret');
    this.clock = clock;
    this.runtimeId = string(runtimeId, 'runtimeId', { max: 128 });
    this.runtimeLeaseMs = integer(runtimeLeaseMs, 'runtimeLeaseMs', { minimum: 1, maximum: 10 * 60 * 1000 });
    this.databaseBindingDigest = string(databaseBindingDigest, 'databaseBindingDigest', { max: 64 });
    if (!/^[a-f0-9]{64}$/.test(this.databaseBindingDigest)) {
      fail('activity_database_binding_invalid', 'Activity database path binding is invalid.', { status: 503 });
    }
    this.readOnlyDormant = readOnlyDormant === true;
    this.eventIdPrefixFactory = eventIdPrefixFactory;
    this.retentionFailure = null;
    this.integrityFailure = null;
    this.active = active === true;
    this.migration = this.readOnlyDormant
      ? { migrated: false, ...activitySchemaStatus(db) }
      : migrateActivitySchema(db, { now: this.clock(), databaseBindingDigest: this.databaseBindingDigest, testOnlyMigrationHook });
    this.authorityEpoch = this.migration.ready ? metadataNumber(db, 'authority_epoch') : null;
    if (this.active) {
      this.activate();
    }
  }

  schemaStatus({ deepAudit = true } = {}) {
    if (this.integrityFailure) return this.integrityFailure;
    const status = this.readOnlyDormant
      ? activitySchemaStatus(this.db, { deepAudit })
      : activitySchemaStatus(this.db, {
          expectedDatabaseBindingDigest: this.databaseBindingDigest,
          deepAudit,
        });
    if (!status.ready) this.integrityFailure = status;
    return status;
  }

  activate(now = this.clock()) {
    if (this.active && this.runtimeFence != null) {
      this.#assertAuthority(now);
      return { ok: true, runtime_fence: this.runtimeFence };
    }
    const databaseRole = activityDatabaseRole(this.db);
    if (this.readOnlyDormant || databaseRole !== 'live') {
      fail('backup_activation_unsupported', 'This database role cannot activate the activity control plane.', { status: 503 });
    }
    this.#claimRuntime(now);
    this.active = true;
    try {
      this.runRetention(now);
      return { ok: true, runtime_fence: this.runtimeFence };
    } catch (error) {
      this.releaseRuntimeClaim();
      this.active = false;
      throw error;
    }
  }

  recoveryManifest() {
    this.#assertAuthority();
    return activityRecoveryManifestForDatabase(this.db, { nodeId: this.nodeId, cursorSecret: this.cursorSecret });
  }

  assertRecoveryFloor(floor) {
    this.#assertAuthority();
    return assertActivityRecoveryFloorForDatabase(this.db, floor, {
      nodeId: this.nodeId,
      cursorSecret: this.cursorSecret,
    });
  }

  #claimRuntime(now) {
    now = this.#normalizeWriteClock(now);
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const status = this.schemaStatus();
      if (!status.ready) fail('activity_schema_not_ready', 'Activity schema invariants are not committed.', { status: 503 });
      now = this.#normalizeWriteClock(now);
      const prior = this.db.prepare('SELECT runtime_id,runtime_fence,lease_expires_at_ms FROM activity_runtime_claim WHERE singleton=1').get();
      if (!prior) fail('activity_schema_not_ready', 'Activity runtime claim metadata is missing.', { status: 503 });
      if (prior.runtime_id) {
        if (Number(prior.lease_expires_at_ms) > now) {
          fail('activity_authority_busy', 'Another activity runtime currently holds the authority lease.', { status: 409, retryable: true });
        }
        fail('activity_recovery_required', 'The prior activity runtime did not close cleanly; automatic takeover is unavailable.', { status: 503 });
      }
      const priorFence = Number(prior.runtime_fence);
      const nextFence = priorFence + 1;
      this.db.prepare(`UPDATE activity_runtime_claim
        SET runtime_id=?,runtime_fence=?,lease_expires_at_ms=? WHERE singleton=1`)
        .run(this.runtimeId, nextFence, derivedTimestamp(now, this.runtimeLeaseMs, 'runtime_clock'));
      this.runtimeFence = nextFence;
      if (priorFence > 0) {
        this.db.prepare(`UPDATE activity_projections SET
          state='unknown',coverage_status='core_restart_gap',clock_health='unknown',
          status_reason='core_restart_gap',updated_at_ms=? WHERE credential_state='active'`).run(now);
        const generation = metadataNumber(this.db, 'snapshot_generation') + 1;
        setMetadataNumber(this.db, 'snapshot_generation', generation);
        const change = this.db.prepare(`INSERT INTO activity_changes(change_id,kind,occurred_at_ms,payload_json)
          VALUES (?,'activity.core_restart_gap',?,?)`).run(
          randomUUID(), now, JSON.stringify({ runtime_fence: nextFence, snapshot_generation: generation }),
        );
        this.#sealChange(Number(change.lastInsertRowid));
        this.#bumpCommitHighWater({ now });
      } else {
        setMetadataNumber(this.db, 'server_time_floor_ms', now);
        writeReplayCommitment(this.db, this.cursorSecret);
      }
      this.db.exec('COMMIT');
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }

  #assertAuthorityPreflight(now = this.clock(), { allowRetentionRecovery = false } = {}) {
    if (!this.active || this.runtimeFence == null) {
      fail('activity_disabled', 'Activity control plane is dormant until an owner credential activates it.', { status: 503 });
    }
    const currentNodeId = this.db.prepare("SELECT value FROM core_metadata WHERE key='node_id'").get()?.value;
    const currentCursorSecret = this.db.prepare("SELECT value FROM core_metadata WHERE key='cursor_secret'").get()?.value;
    const currentDatabaseRole = this.db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get()?.value;
    if (currentNodeId !== this.nodeId || currentCursorSecret !== this.cursorSecret) {
      this.integrityFailure ??= { ready: false, schema_version: ACTIVITY_SCHEMA_VERSION, reason: 'core_metadata_invariant_failed', missing_tables: [] };
      fail('core_metadata_invariant_failed', 'The active activity runtime no longer matches durable Core identity.', { status: 503 });
    }
    if (currentDatabaseRole !== 'live') {
      this.integrityFailure ??= { ready: false, schema_version: ACTIVITY_SCHEMA_VERSION, reason: 'activity_database_role_changed', missing_tables: [] };
      fail('activity_database_role_changed', 'The active activity runtime requires the live database role.', { status: 503 });
    }
    const epoch = metadataNumber(this.db, 'authority_epoch');
    if (epoch !== this.authorityEpoch) {
      this.integrityFailure ??= { ready: false, schema_version: ACTIVITY_SCHEMA_VERSION, reason: 'stale_authority_epoch', missing_tables: [] };
      fail('stale_authority_epoch', 'This Core instance is no longer the active activity authority.', { status: 409 });
    }
    const status = this.schemaStatus({ deepAudit: true });
    if (!status.ready) fail('activity_schema_not_ready', 'Activity schema invariants are not committed.', { status: 503, details: { reason: status.reason } });
    if (this.retentionFailure && !allowRetentionRecovery) {
      fail('activity_retention_failed', 'Activity access is unavailable until retention succeeds.', {
        status: 503,
        details: { failure_code: this.retentionFailure.code },
      });
    }
  }

  #assertAuthority(now = this.clock(), { allowRetentionRecovery = false } = {}) {
    this.#assertAuthorityPreflight(now, { allowRetentionRecovery });
    const ownsTransaction = !this.db.isTransaction;
    if (ownsTransaction) this.db.exec('BEGIN IMMEDIATE');
    try {
      // The second check holds the write lock: an external writer cannot alter
      // evidence between verification and renewal/time-floor advancement.
      if (ownsTransaction) this.#assertAuthorityPreflight(now, { allowRetentionRecovery });
      now = this.#normalizeWriteClock(now);
      const renewed = this.db.prepare(`UPDATE activity_runtime_claim SET lease_expires_at_ms=MAX(lease_expires_at_ms,?)
        WHERE singleton=1 AND runtime_id=? AND runtime_fence=?`).run(
        derivedTimestamp(now, this.runtimeLeaseMs, 'runtime_clock'), this.runtimeId, this.runtimeFence,
      );
      if (Number(renewed.changes) !== 1) {
        fail('stale_activity_runtime', 'This Core instance no longer holds the activity runtime fence.', { status: 409 });
      }
      if (now > metadataNumber(this.db, 'server_time_floor_ms')) {
        setMetadataNumber(this.db, 'server_time_floor_ms', now);
        writeReplayCommitment(this.db, this.cursorSecret);
      }
      if (ownsTransaction) this.db.exec('COMMIT');
      return now;
    } catch (error) {
      if (ownsTransaction) this.db.exec('ROLLBACK');
      throw error;
    }
  }

  runtimeStatus() {
    if (!this.active) {
      return {
        ready: false,
        reason: 'activity_disabled',
        takeover_supported: false,
        backup_activation_supported: false,
        clean_close_in_place_only: true,
        crash_recovery_supported: false,
        lease_takeover_supported: false,
        backup_verification_supported: true,
      };
    }
    if (this.retentionFailure && !this.integrityFailure && this.schemaStatus({ deepAudit: true }).ready) {
      return {
        ready: false,
        reason: 'activity_retention_failed',
        failure_code: this.retentionFailure.code,
        takeover_supported: false,
        backup_activation_supported: false,
        clean_close_in_place_only: true,
        crash_recovery_supported: false,
        lease_takeover_supported: false,
        backup_verification_supported: true,
      };
    }
    try {
      this.#assertAuthority();
      return {
        ready: true,
        runtime_fence: this.runtimeFence,
        takeover_supported: false,
        backup_activation_supported: false,
        clean_close_in_place_only: true,
        crash_recovery_supported: false,
        lease_takeover_supported: false,
        backup_verification_supported: true,
      };
    } catch (error) {
      return {
        ready: false,
        reason: error.code ?? 'activity_runtime_unavailable',
        takeover_supported: false,
        backup_activation_supported: false,
        clean_close_in_place_only: true,
        crash_recovery_supported: false,
        lease_takeover_supported: false,
        backup_verification_supported: true,
      };
    }
  }

  assertRuntimeAuthority() {
    this.#assertAuthority();
    return { ok: true, runtime_fence: this.runtimeFence };
  }

  releaseRuntimeClaim() {
    if (!this.db || this.runtimeFence == null) return;
    if (!tableExists(this.db, 'activity_runtime_claim')) return;
    this.db.prepare(`UPDATE activity_runtime_claim SET runtime_id='',lease_expires_at_ms=0
      WHERE singleton=1 AND runtime_id=? AND runtime_fence=?`).run(this.runtimeId, this.runtimeFence);
  }

  #audit(action, { principalId = null, deviceId = null, probeId = null, details = {}, now = this.clock() } = {}) {
    this.db.prepare(`INSERT INTO activity_audit(
      audit_id, action, principal_id, device_id, probe_id, occurred_at_ms, expires_at_ms, details_json
    ) VALUES (?,?,?,?,?,?,?,?)`).run(
      randomUUID(), action, principalId, deviceId, probeId, now,
      derivedTimestamp(now, ACTIVITY_RAW_RETENTION_MS, 'audit_clock'),
      JSON.stringify(details),
    );
  }

  #bumpCommitHighWater({ replayStateChanged = false, now = this.clock() } = {}) {
    setMetadataNumber(this.db, 'server_time_floor_ms', this.#normalizeWriteClock(now));
    const next = metadataNumber(this.db, 'commit_high_water') + 1;
    setMetadataNumber(this.db, 'commit_high_water', next);
    writeReplayCommitment(this.db, this.cursorSecret, { advance: replayStateChanged });
    return next;
  }

  #normalizeWriteClock(now) {
    integer(now, 'core_now', { minimum: 0 });
    derivedTimestamp(now, Math.max(ACTIVITY_RAW_RETENTION_MS, this.runtimeLeaseMs), 'core_now');
    const floor = canonicalMetadataInteger(this.db.prepare("SELECT value FROM activity_metadata WHERE key='server_time_floor_ms'").get()?.value, 0);
    if (floor == null || safeIntegerSum(floor, ACTIVITY_RAW_RETENTION_MS) == null) {
      this.integrityFailure ??= { ready: false, schema_version: ACTIVITY_SCHEMA_VERSION, reason: 'server_time_floor_invariant_failed', missing_tables: [] };
      fail('activity_schema_not_ready', 'The committed server clock floor is invalid.', { status: 503 });
    }
    const normalized = Math.max(now, floor);
    derivedTimestamp(normalized, Math.max(ACTIVITY_RAW_RETENTION_MS, this.runtimeLeaseMs), 'core_now');
    return normalized;
  }

  #sealChange(serverSequence) {
    const change = this.db.prepare('SELECT * FROM activity_changes WHERE server_sequence=?').get(serverSequence);
    const payload = { ...activityChangePayload(change), integrity_signature: activityChangeSignature(this.db, change, this.cursorSecret) };
    this.db.prepare('UPDATE activity_changes SET payload_json=? WHERE server_sequence=?')
      .run(JSON.stringify(payload), serverSequence);
  }

  #requireChangeIntegrity(change) {
    if (!change || !activityChangeAuthenticated(this.db, change, this.cursorSecret)) {
      fail('activity_schema_not_ready', 'Activity receipt integrity is invalid.', { status: 503 });
    }
  }

  #newCredential(principalId, generation, now) {
    const token = randomBytes(32).toString('base64url');
    this.db.prepare(`INSERT INTO activity_credentials(
      credential_id, principal_id, generation, token_hash, issued_at_ms
    ) VALUES (?,?,?,?,?)`).run(randomUUID(), principalId, generation, tokenDigest(token), now);
    return token;
  }

  #newEventIdPrefix() {
    for (let attempt = 0; attempt < 4; attempt += 1) {
      const prefix = this.eventIdPrefixFactory();
      if (typeof prefix !== 'string' || !/^[A-Za-z0-9_-]{22,64}$/.test(prefix)) {
        fail('event_id_prefix_invalid', 'Generated event ID prefix is not a canonical opaque value.', { status: 503 });
      }
      const activeCollision = this.db.prepare('SELECT 1 AS found FROM activity_principals WHERE event_id_prefix=?').get(prefix);
      const retiredCollision = this.db.prepare('SELECT 1 AS found FROM activity_replay_lineage_floors WHERE lineage_digest=?')
        .get(replayPrefixDigest(this.cursorSecret, prefix));
      if (!activeCollision && !retiredCollision) return prefix;
    }
    fail('event_id_prefix_collision', 'Could not allocate a unique event ID prefix.', { status: 503 });
  }

  pairProbe(raw, now = this.clock()) {
    now = this.#normalizeWriteClock(now);
    now = this.#assertAuthority(now);
    const body = object(raw, 'body');
    exactKeys(body, [
      'device_id', 'probe_id', 'display_name', 'capabilities', 'source',
      'coverage_mode', 'expected_report_interval_ms', 'expiry_slo_ms', 'allowed_kinds',
    ], 'body');
    const deviceId = opaqueId(body.device_id, 'device_id');
    const probeId = opaqueId(body.probe_id, 'probe_id');
    const capabilities = body.capabilities == null ? [] : capabilityArray(body.capabilities, 'capabilities');
    const allowedKinds = stringArray(body.allowed_kinds, 'allowed_kinds', { allowed: ACTIVITY_KINDS });
    if (!allowedKinds.length) fail('invalid_request', 'allowed_kinds must not be empty.');
    const coverageMode = enumValue(body.coverage_mode, 'coverage_mode', ['continuous', 'discrete_best_effort', 'heartbeat_only', 'none', 'unknown']);
    const source = enumValue(body.source, 'source', ACTIVITY_SOURCES);
    const interval = integer(body.expected_report_interval_ms, 'expected_report_interval_ms', { minimum: 1, maximum: ACTIVITY_MAX_TTL_MS });
    const expirySlo = integer(body.expiry_slo_ms, 'expiry_slo_ms', { minimum: 1, maximum: ACTIVITY_MAX_TTL_MS });
    if (this.db.prepare('SELECT 1 AS found FROM activity_principals WHERE device_id=? AND probe_id=?').get(deviceId, probeId)) {
      fail('probe_already_paired', 'Probe identity already exists; use explicit rotation or revoke/delete.', { status: 409 });
    }
    const principalId = `activity-probe:${randomUUID()}`;
    const eventIdPrefix = this.#newEventIdPrefix();
    this.db.exec('BEGIN IMMEDIATE');
    try {
      now = this.#assertAuthority(now);
      this.db.prepare(`INSERT INTO activity_principals(
        principal_id, principal_type, device_id, probe_id, event_id_prefix, display_name,
        capabilities_json, scopes_json, allowed_kinds_json, source, coverage_mode,
        expected_report_interval_ms, expiry_slo_ms, credential_generation,
        paired_at_ms, authority_node_id, authority_epoch
      ) VALUES (?, 'probe', ?, ?, ?, ?, ?, '["activity.write"]', ?, ?, ?, ?, ?, 1, ?, ?, ?)`)
        .run(
          principalId, deviceId, probeId, eventIdPrefix, string(body.display_name, 'display_name'),
          JSON.stringify(capabilities), JSON.stringify(allowedKinds), source, coverageMode,
          interval, expirySlo, now, this.nodeId, this.authorityEpoch,
        );
      const token = this.#newCredential(principalId, 1, now);
      this.db.prepare(`INSERT INTO activity_probe_state(
        probe_id, last_clock_health, last_coverage_status
      ) VALUES (?, 'unknown', 'unknown')`).run(probeId);
      this.db.prepare(`INSERT INTO activity_projections(
        device_id, probe_id, source, state, coverage_json, coverage_status,
        clock_health, credential_state, status_reason, updated_at_ms
      ) VALUES (?, ?, ?, 'unknown', '{}', 'missing', 'unknown', 'active', 'unobserved', ?)`)
        .run(deviceId, probeId, source, now);
      this.#audit('probe.paired', { principalId, deviceId, probeId, details: { scopes: ['activity.write'] }, now });
      this.#bumpCommitHighWater({ replayStateChanged: true, now });
      this.db.exec('COMMIT');
      return {
        principal_id: principalId,
        device_id: deviceId,
        probe_id: probeId,
        event_id_prefix: eventIdPrefix,
        probe_token: token,
        scopes: ['activity.write'],
        credential_generation: 1,
        authority: { node_id: this.nodeId, epoch: this.authorityEpoch },
      };
    } catch (error) {
      try {
        this.db.exec('ROLLBACK');
      } catch {
        // Preserve the first retention failure even if SQLite already ended the transaction.
      }
      throw error;
    }
  }

  pairSummaryReader(raw, now = this.clock()) {
    now = this.#normalizeWriteClock(now);
    now = this.#assertAuthority(now);
    const body = object(raw, 'body');
    exactKeys(body, ['installation_id', 'display_name', 'capabilities'], 'body');
    const installationId = opaqueId(body.installation_id, 'installation_id');
    if (this.db.prepare("SELECT 1 AS found FROM activity_principals WHERE principal_type='summary_reader' AND device_id=? AND deleted_at_ms IS NULL").get(installationId)) {
      fail('reader_already_paired', 'Summary reader already exists; use explicit rotation or revoke.', { status: 409 });
    }
    const principalId = `activity-reader:${randomUUID()}`;
    const capabilities = body.capabilities == null ? [] : capabilityArray(body.capabilities, 'capabilities');
    this.db.exec('BEGIN IMMEDIATE');
    try {
      now = this.#assertAuthority(now);
      this.db.prepare(`INSERT INTO activity_principals(
        principal_id, principal_type, device_id, display_name, capabilities_json,
        scopes_json, allowed_kinds_json, credential_generation, paired_at_ms,
        authority_node_id, authority_epoch
      ) VALUES (?, 'summary_reader', ?, ?, ?, '["activity.read_summary"]', '[]', 1, ?, ?, ?)`)
        .run(principalId, installationId, string(body.display_name, 'display_name'), JSON.stringify(capabilities), now, this.nodeId, this.authorityEpoch);
      const token = this.#newCredential(principalId, 1, now);
      this.db.prepare('INSERT INTO activity_reader_acks(principal_id,last_ack_sequence,updated_at_ms) VALUES (?,0,?)').run(principalId, now);
      this.#audit('reader.paired', { principalId, deviceId: installationId, details: { scopes: ['activity.read_summary'] }, now });
      this.#bumpCommitHighWater({ now });
      this.db.exec('COMMIT');
      return {
        principal_id: principalId,
        reader_token: token,
        scopes: ['activity.read_summary'],
        initial_cursor: this.encodeCursor(metadataNumber(this.db, 'retained_watermark')),
        credential_generation: 1,
      };
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }

  authenticate(token) {
    this.#assertAuthority();
    if (typeof token !== 'string' || !token) return null;
    const row = this.db.prepare(`SELECT
      p.*, c.credential_id, c.generation AS presented_generation,
      c.revoked_at_ms AS credential_revoked_at_ms
      FROM activity_credentials c
      JOIN activity_principals p ON p.principal_id=c.principal_id
      WHERE c.token_hash=?`).get(tokenDigest(token));
    if (!row) return null;
    return this.#principalFromRow(row);
  }

  isActiveCredentialToken(token) {
    if (typeof token !== 'string' || !token) return false;
    return Boolean(this.db.prepare(`SELECT 1 AS found
      FROM activity_credentials c
      JOIN activity_principals p ON p.principal_id=c.principal_id
      WHERE c.token_hash=?
        AND c.revoked_at_ms IS NULL
        AND p.revoked_at_ms IS NULL
        AND p.deleted_at_ms IS NULL
        AND c.generation=p.credential_generation`).get(tokenDigest(token)));
  }

  #principalFromRow(row) {
    return {
      credential_id: row.credential_id,
      principal_id: row.principal_id,
      principal_type: row.principal_type,
      device_id: row.device_id,
      probe_id: row.probe_id,
      event_id_prefix: row.event_id_prefix,
      scopes: JSON.parse(row.scopes_json),
      capabilities: JSON.parse(row.capabilities_json),
      allowed_kinds: JSON.parse(row.allowed_kinds_json),
      source: row.source,
      coverage_mode: row.coverage_mode,
      expected_report_interval_ms: row.expected_report_interval_ms == null ? null : Number(row.expected_report_interval_ms),
      expiry_slo_ms: row.expiry_slo_ms == null ? null : Number(row.expiry_slo_ms),
      credential_generation: Number(row.credential_generation),
      presented_generation: Number(row.presented_generation),
      credential_revoked_at_ms: row.credential_revoked_at_ms == null ? null : Number(row.credential_revoked_at_ms),
      revoked_at_ms: row.revoked_at_ms == null ? null : Number(row.revoked_at_ms),
      deleted_at_ms: row.deleted_at_ms == null ? null : Number(row.deleted_at_ms),
      authority_node_id: row.authority_node_id,
      authority_epoch: Number(row.authority_epoch),
    };
  }

  #requirePrincipal(principal, type, scope, now = this.clock()) {
    this.#assertAuthority(now);
    if (!principal?.credential_id || !principal?.principal_id) {
      fail('scope_denied', `A server-issued ${scope} principal is required.`, { status: 403 });
    }
    const row = this.db.prepare(`SELECT
      p.*, c.credential_id, c.generation AS presented_generation,
      c.revoked_at_ms AS credential_revoked_at_ms
      FROM activity_credentials c
      JOIN activity_principals p ON p.principal_id=c.principal_id
      WHERE c.credential_id=? AND p.principal_id=?`).get(principal.credential_id, principal.principal_id);
    if (!row) fail('scope_denied', `A server-issued ${scope} principal is required.`, { status: 403 });
    const current = this.#principalFromRow(row);
    if (current.principal_type !== type || !current.scopes.includes(scope)) {
      fail('scope_denied', `A server-issued ${scope} principal is required.`, { status: 403 });
    }
    if (
      current.revoked_at_ms != null || current.deleted_at_ms != null ||
      current.credential_revoked_at_ms != null ||
      current.presented_generation !== current.credential_generation
    ) {
      fail('revoked_replay', 'This activity credential has been revoked and cannot be replayed.', { status: 401 });
    }
    if (current.authority_node_id !== this.nodeId || current.authority_epoch !== this.authorityEpoch) {
      fail('stale_authority_epoch', 'Activity credential belongs to a stale Core authority epoch.', { status: 409 });
    }
    return current;
  }

  rotatePrincipal(principalId, now = this.clock()) {
    now = this.#normalizeWriteClock(now);
    now = this.#assertAuthority(now);
    this.db.exec('BEGIN IMMEDIATE');
    try {
      now = this.#assertAuthority(now);
      const principal = this.db.prepare('SELECT * FROM activity_principals WHERE principal_id=?').get(principalId);
      if (!principal || principal.deleted_at_ms != null) fail('principal_not_found', 'Activity principal does not exist.', { status: 404 });
      if (principal.revoked_at_ms != null) fail('principal_revoked', 'A revoked principal cannot be silently revived.', { status: 409 });
      const generation = Number(principal.credential_generation) + 1;
      this.db.prepare('UPDATE activity_credentials SET revoked_at_ms=? WHERE principal_id=? AND revoked_at_ms IS NULL').run(now, principalId);
      this.db.prepare('UPDATE activity_principals SET credential_generation=? WHERE principal_id=?').run(generation, principalId);
      const token = this.#newCredential(principalId, generation, now);
      this.#audit('principal.rotated', { principalId, deviceId: principal.device_id, probeId: principal.probe_id, details: { generation }, now });
      this.#bumpCommitHighWater({ now });
      this.db.exec('COMMIT');
      return {
        principal_id: principalId,
        token,
        credential_generation: generation,
        ...(principal.event_id_prefix ? { event_id_prefix: principal.event_id_prefix } : {}),
      };
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }

  appendEvents(principal, raw, now = this.clock()) {
    now = this.#normalizeWriteClock(now);
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const currentPrincipal = this.#requirePrincipal(principal, 'probe', 'activity.write', now);
      now = this.#normalizeWriteClock(now);
      const body = object(raw, 'body');
      exactKeys(body, ['events'], 'body');
      if (!Array.isArray(body.events) || body.events.length === 0) fail('invalid_request', 'events must contain at least one item.');
      if (body.events.length > ACTIVITY_MAX_BATCH_ITEMS) fail('batch_too_large', `events may contain at most ${ACTIVITY_MAX_BATCH_ITEMS} items.`, { status: 413 });
      const events = body.events.map(normalizeActivityEvent);
      const submitted = events.map((event, index) => ({ event, digest: canonicalActivityDigest(event), index }));
      for (const event of events) {
        if (event.device_id !== currentPrincipal.device_id || event.probe_id !== currentPrincipal.probe_id) {
          fail('identity_binding_mismatch', 'Activity token is bound to a different device/probe.', { status: 403 });
        }
        const expectedEventId = `${currentPrincipal.event_id_prefix}.${event.origin_sequence}`;
        if (event.event_id !== expectedEventId) {
          fail(
            'event_id_binding_mismatch',
            'event_id must bind the issued probe lineage prefix to origin_sequence.',
            { status: 403 },
          );
        }
        if (event.source !== currentPrincipal.source || event.coverage.mode !== currentPrincipal.coverage_mode) {
          fail('source_binding_mismatch', 'Event source and coverage must match the server registration.', { status: 403 });
        }
        if (
          event.coverage.expected_report_interval_ms != null
          && event.coverage.expected_report_interval_ms !== currentPrincipal.expected_report_interval_ms
        ) {
          fail('source_binding_mismatch', 'Coverage report interval must match the server registration.', { status: 403 });
        }
        if (event.coverage.mode === 'continuous' && event.coverage.expected_report_interval_ms == null) {
          fail('invalid_coverage', 'Continuous coverage must declare its registered report interval.');
        }
        if (event.signal_at_ms < event.coverage.window_start_ms || event.signal_at_ms > event.coverage.window_end_ms) {
          fail('invalid_coverage', 'Coverage window must contain the event signal time.');
        }
        if (!currentPrincipal.allowed_kinds.includes(event.kind)) fail('scope_denied', 'Event kind is not allowed for this probe.', { status: 403 });
        if (
          event.kind === 'probe.permission_changed'
          && !currentPrincipal.capabilities.includes(event.payload.capability)
        ) {
          fail('unregistered_diagnostic', 'Permission capability is not registered for this probe.', { status: 403 });
        }
        if (
          event.kind === 'probe.error'
          && !currentPrincipal.capabilities.includes(`probe_error.${event.payload.code}`)
        ) {
          fail('unregistered_diagnostic', 'Error code is not registered for this probe.', { status: 403 });
        }
      }

      const batchKeys = new Map();
      for (const item of submitted) {
        for (const key of [`event:${item.event.event_id}`, `sequence:${item.event.device_id}:${item.event.probe_id}:${item.event.origin_sequence}`]) {
          const prior = batchKeys.get(key);
          if (prior && prior.digest !== item.digest) fail('idempotency_conflict', 'Batch reuses an immutable key with different canonical payload.', { status: 409 });
          batchKeys.set(key, item);
        }
      }

      const plans = [];
      const newBatchEvents = new Set();
      for (const item of submitted) {
        const existingById = this.db.prepare('SELECT * FROM activity_events WHERE event_id=?').get(item.event.event_id);
        const existingBySequence = this.db.prepare('SELECT * FROM activity_events WHERE device_id=? AND probe_id=? AND origin_sequence=?')
          .get(item.event.device_id, item.event.probe_id, item.event.origin_sequence);
        const tombstoneById = this.db.prepare('SELECT * FROM activity_event_tombstones WHERE event_id=?').get(item.event.event_id);
        const tombstoneBySequence = this.db.prepare('SELECT * FROM activity_event_tombstones WHERE device_id=? AND probe_id=? AND origin_sequence=?')
          .get(item.event.device_id, item.event.probe_id, item.event.origin_sequence);
        const candidates = [existingById, existingBySequence, tombstoneById, tombstoneBySequence].filter(Boolean);
        if (candidates.some((row) => row.canonical_digest !== item.digest)) {
          fail('idempotency_conflict', 'An immutable activity key already has different canonical payload.', { status: 409, details: { event_id: item.event.event_id, origin_sequence: item.event.origin_sequence } });
        }
        const existing = existingById ?? existingBySequence;
        if (existing) {
          plans.push({ ...item, status: 'duplicate', existing });
        } else if (tombstoneById || tombstoneBySequence) {
          fail('event_retained_out', 'The immutable event key has been removed by retention or deletion.', { status: 410 });
        } else {
          const batchKey = `${item.event.event_id}:${item.digest}`;
          const status = newBatchEvents.has(batchKey) ? 'batch_duplicate' : 'accepted';
          newBatchEvents.add(batchKey);
          plans.push({ ...item, status });
        }
      }

      const newPlans = plans.filter((plan) => plan.status === 'accepted');
      const state = this.db.prepare('SELECT * FROM activity_probe_state WHERE probe_id=?').get(currentPrincipal.probe_id);
      const prefixContext = retiredContext(state);
      let permissionUnavailable = state?.last_coverage_status === 'permission_unavailable';
      let permissionRecoveryPending = state?.last_coverage_status === 'permission_recovery_pending';
      const retainedOriginFloor = state?.retained_origin_floor == null
        ? null
        : Number(state.retained_origin_floor);
      for (const plan of newPlans) {
        if (retainedOriginFloor !== null && plan.event.origin_sequence <= retainedOriginFloor) {
          fail('event_retained_out', 'origin_sequence is below the durable retention replay floor.', { status: 410 });
        }
        const ttlDeadline = derivedTimestamp(plan.event.signal_at_ms, plan.event.ttl_ms, 'signal_at_ms');
        derivedTimestamp(
          plan.event.signal_at_ms,
          Math.min(plan.event.ttl_ms, currentPrincipal.expiry_slo_ms),
          'signal_at_ms',
        );
        if (now > ttlDeadline) {
          fail('ttl_expired', 'Activity event expired before Core acceptance.', { status: 410 });
        }
      }
      const limit = this.db.prepare('SELECT window_start_ms,accepted_count FROM activity_rate_limits WHERE probe_id=?').get(currentPrincipal.probe_id);
      const freshWindow = !limit || now - Number(limit.window_start_ms) >= ACTIVITY_RATE_WINDOW_MS;
      const windowStart = freshWindow ? now : Number(limit.window_start_ms);
      const acceptedCount = freshWindow ? 0 : Number(limit.accepted_count);
      if (acceptedCount + newPlans.length > ACTIVITY_RATE_MAX_EVENTS) {
        fail('rate_limited', 'Per-probe activity ingress rate limit exceeded.', { status: 429, retryable: true, details: { retry_after_ms: ACTIVITY_RATE_WINDOW_MS - (now - windowStart) } });
      }

      const acceptedSequences = this.db.prepare(`SELECT origin_sequence
        FROM activity_events WHERE device_id=? AND probe_id=? AND origin_sequence>?`).all(
        currentPrincipal.device_id,
        currentPrincipal.probe_id,
        retainedOriginFloor ?? -1,
      ).map((row) => Number(row.origin_sequence));
      const sequenceCoverage = activitySequenceCoverage(
        [...acceptedSequences, ...newPlans.map((plan) => plan.event.origin_sequence)],
        retainedOriginFloor,
      );
      const priorSequenceCoverageGap = activitySequenceCoverage(acceptedSequences, retainedOriginFloor).missing.length > 0;
      const sequenceCoverageGap = sequenceCoverage.missing.length > 0;
      let projectionRecomputedThrough = null;

      const logicalClockHealthByEventId = new Map();
      const acceptanceClockPriorByEventId = new Map();
      const acceptedClockInputs = [];
      for (const plan of newPlans) {
        const item = {
          event_id: plan.event.event_id,
          origin_sequence: plan.event.origin_sequence,
          signal_at_ms: plan.event.signal_at_ms,
          received_at_ms: now,
        };
        const futureBoundary = derivedTimestamp(item.received_at_ms, ACTIVITY_FUTURE_SKEW_MS, 'received_at_ms');
        const future = item.signal_at_ms > futureBoundary;
        const storedPrior = this.db.prepare(`SELECT MAX(occurred_at_ms) AS value FROM activity_events
          WHERE device_id=? AND probe_id=? AND origin_sequence<? AND clock_health<>'future_skew'`).get(
          currentPrincipal.device_id,
          currentPrincipal.probe_id,
          item.origin_sequence,
        ).value;
        let maximumPriorLogicalSignal = storedPrior == null ? null : Number(storedPrior);
        if (prefixContext.max_signal_at_ms != null) maximumPriorLogicalSignal = maximumPriorLogicalSignal == null
          ? prefixContext.max_signal_at_ms : Math.max(maximumPriorLogicalSignal, prefixContext.max_signal_at_ms);
        for (const prior of acceptedClockInputs) {
          if (!prior.future && prior.origin_sequence < item.origin_sequence) {
            maximumPriorLogicalSignal = maximumPriorLogicalSignal == null
              ? prior.signal_at_ms
              : Math.max(maximumPriorLogicalSignal, prior.signal_at_ms);
          }
        }
        const clockHealth = future
          ? 'future_skew'
          : maximumPriorLogicalSignal != null && item.signal_at_ms < maximumPriorLogicalSignal
            ? 'clock_regression'
            : 'healthy';
        logicalClockHealthByEventId.set(item.event_id, clockHealth);
        acceptanceClockPriorByEventId.set(item.event_id, maximumPriorLogicalSignal);
        acceptedClockInputs.push({ ...item, future });
      }

      let maxOrigin = state?.max_origin_sequence == null ? null : Number(state.max_origin_sequence);
      let maxOccurred = state?.max_occurred_at_ms == null ? null : Number(state.max_occurred_at_ms);
      const results = [];
      const acceptedByDigest = new Map();
      for (const plan of plans) {
        if (plan.status === 'duplicate') {
          const change = this.db.prepare('SELECT * FROM activity_changes WHERE server_sequence=?')
            .get(plan.existing.server_sequence);
          this.#requireChangeIntegrity(change);
          const observation = JSON.parse(change.payload_json).receipt_observation;
          results.push({
            index: plan.index,
            event_id: plan.event.event_id,
            status: 'duplicate',
            receipt_id: plan.existing.receipt_id,
            server_sequence: Number(plan.existing.server_sequence),
            occurred_at_ms: Number(plan.existing.occurred_at_ms),
            received_at_ms: Number(plan.existing.received_at_ms),
            clock_health: plan.existing.clock_health,
            ...(observation ?? {
              sequence_diagnostics: null,
              sequence_coverage: null,
              projection_recomputed_through_origin_sequence: null,
            }),
          });
          continue;
        }
        const sameBatch = acceptedByDigest.get(`${plan.event.event_id}:${plan.digest}`);
        if (sameBatch) {
          results.push({ ...sameBatch, index: plan.index, status: 'duplicate' });
          continue;
        }
        const event = plan.event;
        if (event.kind === 'probe.permission_changed') {
          permissionUnavailable = event.payload.available === false;
          permissionRecoveryPending = event.payload.available === true;
        }
        const sequenceRegression = maxOrigin != null && event.origin_sequence < maxOrigin;
        const clockHealth = logicalClockHealthByEventId.get(event.event_id);
        const future = clockHealth === 'future_skew';
        const regression = clockHealth === 'clock_regression';
        const coverageStatus = sequenceCoverageGap
          ? 'gap'
          : now > derivedTimestamp(event.signal_at_ms, currentPrincipal.expiry_slo_ms, 'signal_at_ms')
            ? 'stale'
          : ['none', 'unknown'].includes(event.coverage.mode)
            ? 'missing'
            : event.coverage.window_end_ms < event.coverage.window_start_ms
              ? 'invalid'
              : 'covered';
        const receiptId = `activity-receipt:${randomUUID()}`;
        const changeId = `activity-change:${randomUUID()}`;
        const changePayload = {
          event_id: event.event_id,
          device_id: event.device_id,
          probe_id: event.probe_id,
          receipt_id: receiptId,
          occurred_at_ms: event.signal_at_ms,
          received_at_ms: now,
          acceptance_clock_prior_signal_at_ms: acceptanceClockPriorByEventId.get(event.event_id),
        };
        const change = this.db.prepare(`INSERT INTO activity_changes(
          change_id,kind,device_id,probe_id,occurred_at_ms,payload_json
        ) VALUES (?,'activity.event.accepted',?,?,?,?)`).run(changeId, event.device_id, event.probe_id, now, JSON.stringify(changePayload));
        const serverSequence = Number(change.lastInsertRowid);
        this.db.prepare(`INSERT INTO activity_events(
          event_id,device_id,probe_id,origin_sequence,kind,occurred_at_ms,received_at_ms,
          ttl_ms,confidence,source,coverage_json,payload_json,canonical_digest,receipt_id,
          server_sequence,clock_health,credential_generation,authority_node_id,authority_epoch
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`).run(
          event.event_id, event.device_id, event.probe_id, event.origin_sequence, event.kind,
          event.signal_at_ms, now, event.ttl_ms, event.confidence, event.source,
          JSON.stringify(event.coverage), JSON.stringify(event.payload), plan.digest, receiptId,
          serverSequence, clockHealth, currentPrincipal.presented_generation, this.nodeId, this.authorityEpoch,
        );

        const current = this.db.prepare('SELECT * FROM activity_projections WHERE device_id=? AND probe_id=?').get(event.device_id, event.probe_id);
        const stateValue = projectionState(event, { clockHealth, coverageStatus });
        if (
          !permissionUnavailable
          && ['active', 'locked'].includes(stateValue)
          && clockHealth === 'healthy'
          && coverageStatus === 'covered'
        ) {
          permissionRecoveryPending = false;
        }
        const preserveFreshSpecificEvidence = stateValue === 'network_only'
          && ['active', 'locked'].includes(current?.state)
          && Number(current?.expires_at_ms ?? -1) >= now;
        const recoverFromClockFault = current?.state === 'unknown'
          && ['future_skew', 'clock_regression'].includes(current?.clock_health)
          && ['active', 'locked'].includes(stateValue);
        const canAdvance = !permissionUnavailable
          && (!permissionRecoveryPending || ['active', 'locked'].includes(stateValue))
          && !preserveFreshSpecificEvidence
          && clockHealth === 'healthy'
          && coverageStatus === 'covered'
          && (
            !current?.current_event_id
            || recoverFromClockFault
            || event.signal_at_ms >= Number(current.occurred_at_ms ?? -1)
          );
        const statusReason = projectionStatusReason(event, {
          clockHealth,
          coverageStatus,
          state: stateValue,
        });
        if (canAdvance) {
          this.db.prepare(`UPDATE activity_projections SET
            current_event_id=?, state=?, occurred_at_ms=?, received_at_ms=?, expires_at_ms=?,
            confidence=?, coverage_json=?, coverage_status=?, clock_health=?, credential_state='active',
            status_reason=?,last_server_sequence=?, updated_at_ms=? WHERE device_id=? AND probe_id=?`).run(
            event.event_id, stateValue, event.signal_at_ms, now,
            derivedTimestamp(event.signal_at_ms, Math.min(event.ttl_ms, currentPrincipal.expiry_slo_ms), 'signal_at_ms'),
            event.confidence, JSON.stringify(event.coverage), coverageStatus, clockHealth,
            permissionUnavailable
              ? 'permission_unavailable'
              : permissionRecoveryPending
                ? 'insufficient_human_evidence'
                : statusReason,
            serverSequence, now, event.device_id, event.probe_id,
          );
        } else if (!preserveFreshSpecificEvidence && (
          !current?.current_event_id
          || event.signal_at_ms > Number(current.occurred_at_ms ?? -1)
          || (
            event.signal_at_ms === Number(current.occurred_at_ms ?? -1)
            && !regression
            && !sequenceRegression
          )
        )) {
          this.db.prepare(`UPDATE activity_projections SET
            current_event_id=?,state='unknown',occurred_at_ms=?,received_at_ms=?,expires_at_ms=?,
            confidence=?,coverage_json=?,coverage_status=?,clock_health=?,credential_state='active',
            status_reason=?,last_server_sequence=?,updated_at_ms=? WHERE device_id=? AND probe_id=?`).run(
            event.event_id, event.signal_at_ms, now,
            derivedTimestamp(event.signal_at_ms, Math.min(event.ttl_ms, currentPrincipal.expiry_slo_ms), 'signal_at_ms'),
            event.confidence, JSON.stringify(event.coverage), coverageStatus, clockHealth,
            statusReason, serverSequence, now, event.device_id, event.probe_id,
          );
        }
        const receivedClockFault = ['future_skew', 'clock_regression'].includes(clockHealth);
        const receivedSourceHealth = ['probe.error', 'probe.permission_changed'].includes(event.kind);
        if (receivedClockFault || receivedSourceHealth) {
          const failureReason = receivedSourceHealth
            ? event.kind === 'probe.error'
              ? 'probe_error'
              : event.payload.available === false
                ? 'permission_unavailable'
                : 'insufficient_human_evidence'
            : clockHealth;
          this.db.prepare(`UPDATE activity_projections SET state='unknown',
            clock_health=CASE WHEN ? THEN ? ELSE clock_health END,
            status_reason=?,updated_at_ms=? WHERE device_id=? AND probe_id=?`).run(
            receivedClockFault ? 1 : 0,
            clockHealth,
            failureReason,
            now,
            event.device_id,
            event.probe_id,
          );
        }
        maxOrigin = maxOrigin == null ? event.origin_sequence : Math.max(maxOrigin, event.origin_sequence);
        if (!future) maxOccurred = maxOccurred == null ? event.signal_at_ms : Math.max(maxOccurred, event.signal_at_ms);
        this.db.prepare(`UPDATE activity_probe_state SET
          max_origin_sequence=?, max_occurred_at_ms=?, last_received_at_ms=?,
          last_clock_health=?, last_coverage_status=? WHERE probe_id=?`).run(
          maxOrigin, maxOccurred, now, clockHealth,
          permissionUnavailable
            ? 'permission_unavailable'
            : permissionRecoveryPending
              ? 'permission_recovery_pending'
              : coverageStatus,
          event.probe_id,
        );
        const result = {
          index: plan.index,
          event_id: event.event_id,
          status: 'accepted',
          receipt_id: receiptId,
          server_sequence: serverSequence,
          occurred_at_ms: event.signal_at_ms,
          received_at_ms: now,
          clock_health: clockHealth,
          coverage_status: coverageStatus,
          sequence_diagnostics: [
            ...(sequenceRegression ? ['sequence_regression'] : []),
            ...(sequenceCoverageGap ? ['sequence_coverage_gap'] : []),
          ],
          sequence_coverage: sequenceCoverage,
          projection_recomputed_through_origin_sequence: null,
        };
        acceptedByDigest.set(`${event.event_id}:${plan.digest}`, result);
        results.push(result);
      }
      if (newPlans.length) {
        const logicalPermissionRows = this.db.prepare(`SELECT *
          FROM activity_events WHERE device_id=? AND probe_id=? ORDER BY origin_sequence`).all(
          currentPrincipal.device_id,
          currentPrincipal.probe_id,
        );
        const clocks = activityClockHealthMaps(logicalPermissionRows, { retiredSignal: prefixContext.max_signal_at_ms });
        const permissionStatus = activityPermissionStatus(logicalPermissionRows, prefixContext.permission_status, clocks.logical);
        permissionUnavailable = permissionStatus === 'unavailable';
        permissionRecoveryPending = permissionStatus === 'pending';
      }
      if (newPlans.length && sequenceCoverageGap) {
        // A new accepted event ends the restart override. Gap clock evidence is
        // derived from immutable logical history, never inherited from restart.
        const history = this.db.prepare(`SELECT event_id,origin_sequence,occurred_at_ms,received_at_ms,server_sequence
          FROM activity_events WHERE probe_id=? ORDER BY origin_sequence`).all(currentPrincipal.probe_id);
        const clocks = activityClockHealthMaps(history, { retiredSignal: prefixContext.max_signal_at_ms });
        if (!clocks) fail('activity_schema_not_ready', 'Activity clock history is outside the supported range.', { status: 503 });
        const currentId = this.db.prepare('SELECT current_event_id FROM activity_projections WHERE probe_id=?').get(currentPrincipal.probe_id)?.current_event_id;
        const latestClock = clocks.logical.get(history.at(-1)?.event_id);
        const gapClock = ['future_skew', 'clock_regression'].includes(latestClock)
          ? latestClock : clocks.logical.get(currentId);
        this.db.prepare(`UPDATE activity_projections SET state='unknown',coverage_status='gap',clock_health=?,
          status_reason='coverage_gap',updated_at_ms=? WHERE device_id=? AND probe_id=?`).run(
          gapClock,
          now,
          currentPrincipal.device_id,
          currentPrincipal.probe_id,
        );
      }
      if (
        newPlans.length
        && !sequenceCoverageGap
        && priorSequenceCoverageGap
      ) {
        const current = this.db.prepare(`SELECT p.current_event_id,p.coverage_status,e.*
          FROM activity_projections p
          JOIN activity_events e ON e.event_id=p.current_event_id
          WHERE p.device_id=? AND p.probe_id=?`).get(currentPrincipal.device_id, currentPrincipal.probe_id);
        if (current?.coverage_status === 'gap') {
          const allProbeEvents = this.db.prepare(`SELECT event_id,origin_sequence,occurred_at_ms,received_at_ms,server_sequence
            FROM activity_events WHERE device_id=? AND probe_id=?`).all(
            currentPrincipal.device_id,
            currentPrincipal.probe_id,
          );
          const clockMaps = activityClockHealthMaps(allProbeEvents, { retiredSignal: prefixContext.max_signal_at_ms });
          if (!clockMaps) fail('activity_schema_not_ready', 'Activity clock history is outside the supported range.', { status: 503 });
          const currentLogicalClockHealth = clockMaps.logical.get(current.event_id);
          const currentEvent = {
            kind: current.kind,
            confidence: current.confidence,
            payload: JSON.parse(current.payload_json),
          };
          const coverageStatus = now > Number(current.occurred_at_ms) + currentPrincipal.expiry_slo_ms
            ? 'stale'
            : ['none', 'unknown'].includes(JSON.parse(current.coverage_json).mode)
              ? 'missing'
              : 'covered';
          const stateValue = projectionState(currentEvent, {
            clockHealth: currentLogicalClockHealth,
            coverageStatus,
          });
          const latestLogical = this.db.prepare(`SELECT event_id,kind,origin_sequence,clock_health,payload_json
            FROM activity_events WHERE device_id=? AND probe_id=? ORDER BY origin_sequence DESC LIMIT 1`).get(
            currentPrincipal.device_id,
            currentPrincipal.probe_id,
          );
          let recomputedState = stateValue;
          let recomputedClockHealth = currentLogicalClockHealth;
          let recomputedReason = projectionStatusReason(currentEvent, {
            clockHealth: currentLogicalClockHealth,
            coverageStatus,
            state: stateValue,
          });
          if (permissionUnavailable) {
            recomputedState = 'unknown';
            recomputedReason = 'permission_unavailable';
          } else if (permissionRecoveryPending) {
            recomputedState = 'unknown';
            recomputedReason = 'insufficient_human_evidence';
          } else if (
            Number(latestLogical?.origin_sequence ?? -1) > Number(current.origin_sequence)
            && ['future_skew', 'clock_regression'].includes(clockMaps.logical.get(latestLogical.event_id))
          ) {
            recomputedState = 'unknown';
            recomputedClockHealth = clockMaps.logical.get(latestLogical.event_id);
            recomputedReason = recomputedClockHealth;
          } else if (
            Number(latestLogical?.origin_sequence ?? -1) > Number(current.origin_sequence)
            && latestLogical.kind === 'probe.error'
          ) {
            recomputedState = 'unknown';
            recomputedClockHealth = latestLogical.clock_health;
            recomputedReason = 'probe_error';
          }
          this.db.prepare(`UPDATE activity_projections SET state=?,coverage_status=?,clock_health=?,status_reason=?,updated_at_ms=?
            WHERE device_id=? AND probe_id=?`).run(
            recomputedState,
            coverageStatus,
            recomputedClockHealth,
            recomputedReason,
            now,
            currentPrincipal.device_id,
            currentPrincipal.probe_id,
          );
          projectionRecomputedThrough = Number(latestLogical.origin_sequence);
        }
      }
      if (newPlans.length && !sequenceCoverageGap && (permissionUnavailable || permissionRecoveryPending)) {
        this.db.prepare(`UPDATE activity_projections SET state='unknown',status_reason=?,updated_at_ms=?
          WHERE device_id=? AND probe_id=?`).run(
          permissionUnavailable ? 'permission_unavailable' : 'insufficient_human_evidence',
          now, currentPrincipal.device_id, currentPrincipal.probe_id,
        );
      }
      if (newPlans.length) {
        this.db.prepare('UPDATE activity_probe_state SET last_coverage_status=? WHERE probe_id=?')
          .run(
            permissionUnavailable
              ? 'permission_unavailable'
              : permissionRecoveryPending
                ? 'permission_recovery_pending'
              : sequenceCoverageGap
                ? 'gap'
                : this.db.prepare('SELECT coverage_status FROM activity_projections WHERE probe_id=?').get(currentPrincipal.probe_id)?.coverage_status ?? 'unknown',
            currentPrincipal.probe_id,
          );
      }
      if (newPlans.length) {
        this.#refreshRetainedProjection(currentPrincipal.probe_id, now);
        this.db.prepare(`INSERT INTO activity_rate_limits(probe_id,window_start_ms,accepted_count)
          VALUES (?,?,?) ON CONFLICT(probe_id) DO UPDATE SET window_start_ms=excluded.window_start_ms,accepted_count=excluded.accepted_count`)
          .run(currentPrincipal.probe_id, windowStart, acceptedCount + newPlans.length);
      }
      if (newPlans.length) {
        for (const result of results) {
          if (!acceptedByDigest.has(`${result.event_id}:${plans[result.index].digest}`)) continue;
          result.projection_recomputed_through_origin_sequence = projectionRecomputedThrough;
          if (result.status !== 'accepted') continue;
          const observation = {
            coverage_status: result.coverage_status,
            sequence_diagnostics: result.sequence_diagnostics,
            sequence_coverage: result.sequence_coverage,
            projection_recomputed_through_origin_sequence: projectionRecomputedThrough,
          };
          const change = this.db.prepare('SELECT payload_json FROM activity_changes WHERE server_sequence=?')
            .get(result.server_sequence);
          this.db.prepare('UPDATE activity_changes SET payload_json=? WHERE server_sequence=?')
            .run(JSON.stringify({ ...JSON.parse(change.payload_json), receipt_observation: observation }), result.server_sequence);
          this.#sealChange(result.server_sequence);
        }
        this.#audit('events.accepted', {
          principalId: currentPrincipal.principal_id,
          deviceId: currentPrincipal.device_id,
          probeId: currentPrincipal.probe_id,
          details: { batch_items: events.length, accepted: newPlans.length },
          now,
        });
        setMetadataNumber(
          this.db,
          'accepted_event_count',
          metadataNumber(this.db, 'accepted_event_count') + newPlans.length,
        );
        this.#bumpCommitHighWater({ now });
      }
      this.db.exec('COMMIT');
      return { contract: ACTIVITY_CONTRACT, results: results.sort((a, b) => a.index - b.index).map(({ index, ...item }) => item) };
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }

  #summaryRows(now) {
    const principals = this.db.prepare(`SELECT p.*, pr.*, e.kind AS current_kind,
        ps.last_coverage_status AS probe_coverage_status
      FROM activity_principals p
      LEFT JOIN activity_projections pr ON pr.probe_id=p.probe_id AND pr.device_id=p.device_id
      LEFT JOIN activity_events e ON e.event_id=pr.current_event_id
      LEFT JOIN activity_probe_state ps ON ps.probe_id=p.probe_id
      WHERE p.principal_type='probe' AND p.deleted_at_ms IS NULL
      ORDER BY p.device_id,p.probe_id`).all();
    return principals.map((row) => {
      const revoked = row.revoked_at_ms != null;
      const sequenceGap = row.probe_coverage_status === 'gap';
      const permissionUnavailable = row.probe_coverage_status === 'permission_unavailable';
      const permissionRecoveryPending = row.probe_coverage_status === 'permission_recovery_pending';
      let occurredAt = row.occurred_at_ms == null ? null : Number(row.occurred_at_ms);
      let receivedAt = row.received_at_ms == null ? null : Number(row.received_at_ms);
      let expiresAt = row.expires_at_ms == null ? null : Number(row.expires_at_ms);
      let coverage = row.coverage_json ? JSON.parse(row.coverage_json) : null;
      let coverageStatus = row.coverage_status ?? 'missing';
      let clockHealth = row.clock_health ?? 'unknown';
      let currentKind = row.current_kind;
      let orderingSequence = row.last_server_sequence == null ? -1 : Number(row.last_server_sequence);
      let expired = expiresAt == null || expiresAt < now;
      if (!revoked && !sequenceGap && !permissionUnavailable && !permissionRecoveryPending && expired && ['active', 'locked'].includes(row.state)) {
        const fallback = this.db.prepare(`SELECT event_id,kind,occurred_at_ms,received_at_ms,ttl_ms,
            coverage_json,clock_health,server_sequence
          FROM activity_events
          WHERE probe_id=? AND kind IN ('probe.heartbeat','network.present')
            AND occurred_at_ms>?
          ORDER BY occurred_at_ms DESC,server_sequence DESC`).all(row.probe_id, occurredAt ?? -1)
          .find((candidate) => {
            const candidateCoverage = JSON.parse(candidate.coverage_json);
            const candidateExpiry = Number(candidate.occurred_at_ms)
              + Math.min(Number(candidate.ttl_ms), Number(row.expiry_slo_ms));
            return candidate.clock_health === 'healthy'
              && candidateExpiry >= now
              && !['none', 'unknown'].includes(candidateCoverage.mode)
              && candidateCoverage.window_start_ms <= Number(candidate.occurred_at_ms)
              && candidateCoverage.window_end_ms >= Number(candidate.occurred_at_ms);
          });
        if (fallback) {
          occurredAt = Number(fallback.occurred_at_ms);
          receivedAt = Number(fallback.received_at_ms);
          expiresAt = occurredAt + Math.min(Number(fallback.ttl_ms), Number(row.expiry_slo_ms));
          coverage = JSON.parse(fallback.coverage_json);
          coverageStatus = 'covered';
          clockHealth = 'healthy';
          currentKind = fallback.kind;
          orderingSequence = Number(fallback.server_sequence);
          expired = false;
        }
      }
      const clockHealthy = clockHealth === 'healthy';
      const coverageHealthy = coverageStatus === 'covered';
      const state = revoked || sequenceGap || permissionUnavailable || permissionRecoveryPending || expired || !clockHealthy || !coverageHealthy
        ? 'unknown'
        : ['probe.heartbeat', 'network.present'].includes(currentKind)
          ? 'network_only'
          : row.state;
      return {
        device_id: row.device_id,
        probe_id: row.probe_id,
        source: row.source,
        state,
        credential_state: revoked ? 'revoked' : 'active',
        status_reason: revoked
          ? 'credential_revoked'
          : sequenceGap
            ? 'coverage_gap'
            : permissionUnavailable
              ? 'permission_unavailable'
              : permissionRecoveryPending
                ? 'insufficient_human_evidence'
            : expired
              ? 'ttl_expired'
              : ['probe.heartbeat', 'network.present'].includes(currentKind)
                ? 'reachability_only'
                : row.status_reason,
        occurred_at_ms: occurredAt,
        received_at_ms: receivedAt,
        ttl_ms: occurredAt == null || expiresAt == null ? null : expiresAt - occurredAt,
        freshness: { fresh: !expired && !sequenceGap && !permissionUnavailable && !permissionRecoveryPending, expires_at_ms: expiresAt, server_time_ms: now },
        coverage,
        registered_coverage: {
          mode: row.coverage_mode,
          expected_report_interval_ms: row.expected_report_interval_ms == null
            ? null
            : Number(row.expected_report_interval_ms),
          expiry_slo_ms: row.expiry_slo_ms == null ? null : Number(row.expiry_slo_ms),
        },
        coverage_status: sequenceGap ? 'gap' : coverageStatus,
        clock_health: clockHealth,
        _ordering_sequence: orderingSequence,
        _evidence_class: ['probe.heartbeat', 'network.present'].includes(currentKind)
          ? 'network'
          : currentKind
            ? 'device'
            : 'none',
      };
    });
  }

  summary(principal, now = this.clock()) {
    this.#requirePrincipal(principal, 'summary_reader', 'activity.read_summary', now);
    now = this.#normalizeWriteClock(now);
    const sources = this.#summaryRows(now);
    const byDevice = new Map();
    for (const source of sources) {
      const entry = byDevice.get(source.device_id) ?? {
        device_id: source.device_id,
        state: 'unknown',
        sources: [],
        winner: null,
        winnerRank: -1,
      };
      entry.sources.push(source);
      const winner = entry.winner;
      const sourceValid = source.freshness.fresh
        && source.coverage_status === 'covered'
        && source.clock_health === 'healthy'
        && source.credential_state === 'active';
      const sourceRank = sourceValid && ['active', 'locked'].includes(source.state)
        ? 3
        : sourceValid
          && source._evidence_class === 'device'
          && !['probe_error', 'permission_unavailable'].includes(source.status_reason)
          ? 2
          : sourceValid && source._evidence_class === 'network'
            ? 1
            : 0;
      const sourceOccurred = source.occurred_at_ms ?? -1;
      const winnerOccurred = winner?.occurred_at_ms ?? -1;
      if (
        !winner
        || sourceRank > entry.winnerRank
        || (sourceRank === entry.winnerRank && sourceOccurred > winnerOccurred)
        || (
          sourceRank === entry.winnerRank
          && sourceOccurred === winnerOccurred
          && source._ordering_sequence > winner._ordering_sequence
        )
        || (
          sourceRank === entry.winnerRank
          && sourceOccurred === winnerOccurred
          && source._ordering_sequence === winner._ordering_sequence
          && source.probe_id < winner.probe_id
        )
      ) {
        entry.winner = source;
        entry.winnerRank = sourceRank;
        entry.state = source.state;
      }
      byDevice.set(source.device_id, entry);
    }
    const devices = [...byDevice.values()].map(({ winner, winnerRank, ...device }) => ({
      ...device,
      sources: device.sources.map(({ _ordering_sequence, _evidence_class, ...source }) => source),
    }));
    return {
      contract: ACTIVITY_CONTRACT,
      schema_version: ACTIVITY_FEATURE_VERSION,
      generated_at_ms: now,
      authority: { node_id: this.nodeId, epoch: this.authorityEpoch },
      devices,
      semantics: { silence_is_unknown: true, sleep_inference: 'not_supported' },
    };
  }

  encodeCursor(sequence) {
    this.#assertAuthority();
    return this.#encodeCursorUnchecked(sequence);
  }

  #encodeCursorUnchecked(sequence) {
    const payload = Buffer.from(JSON.stringify({ n: this.nodeId, e: this.authorityEpoch, s: sequence })).toString('base64url');
    const signature = createHmac('sha256', this.cursorSecret).update(`activity:${payload}`).digest('base64url').slice(0, 22);
    return `a1.${payload}.${signature}`;
  }

  decodeCursor(cursor) {
    this.#assertAuthority();
    if (typeof cursor !== 'string') fail('invalid_cursor', 'Activity cursor must be an opaque string.');
    const match = /^a1\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]{22})$/.exec(cursor);
    if (!match) fail('invalid_cursor', 'Activity cursor is invalid.');
    const expected = createHmac('sha256', this.cursorSecret).update(`activity:${match[1]}`).digest('base64url').slice(0, 22);
    if (expected !== match[2]) fail('invalid_cursor', 'Activity cursor signature is invalid.');
    let decoded;
    try { decoded = JSON.parse(Buffer.from(match[1], 'base64url').toString('utf8')); } catch (_) { fail('invalid_cursor', 'Activity cursor payload is invalid.'); }
    if (decoded.n !== this.nodeId || decoded.e !== this.authorityEpoch) {
      fail('resync_required', 'Activity cursor belongs to a stale authority lineage.', { status: 409, details: this.resyncDetails('stale_lineage') });
    }
    return integer(decoded.s, 'cursor.sequence', { minimum: 0 });
  }

  resyncDetails(reason) {
    const watermark = metadataNumber(this.db, 'retained_watermark');
    return {
      domain: 'activity',
      reason,
      retained_watermark: watermark,
      earliest_cursor: this.encodeCursor(watermark),
      snapshot_endpoint: '/v1/core/activity/snapshot',
      snapshot_generation: metadataNumber(this.db, 'snapshot_generation'),
    };
  }

  changes(principal, cursor, rawLimit = 100) {
    this.#requirePrincipal(principal, 'summary_reader', 'activity.read_summary');
    const sequence = this.decodeCursor(cursor);
    const watermark = metadataNumber(this.db, 'retained_watermark');
    if (sequence < watermark) fail('resync_required', 'Activity cursor predates the retained watermark.', { status: 409, details: this.resyncDetails('retention_gap') });
    const latest = Number(this.db.prepare('SELECT COALESCE(MAX(server_sequence),0) AS value FROM activity_changes').get().value);
    if (sequence > latest) fail('resync_required', 'Activity cursor points beyond the current feed.', { status: 409, details: this.resyncDetails('cursor_ahead') });
    const limit = Math.min(integer(rawLimit, 'limit', { minimum: 1 }), 500);
    const rows = this.db.prepare(`SELECT * FROM activity_changes WHERE server_sequence>? ORDER BY server_sequence LIMIT ?`).all(sequence, limit + 1);
    const hasMore = rows.length > limit;
    const page = hasMore ? rows.slice(0, limit) : rows;
    for (const row of page) this.#requireChangeIntegrity(row);
    const next = page.length ? Number(page.at(-1).server_sequence) : sequence;
    return {
      contract: ACTIVITY_CONTRACT,
      schema_version: ACTIVITY_FEATURE_VERSION,
      events: page.map((row) => ({
        change_id: row.change_id,
        server_sequence: Number(row.server_sequence),
        kind: row.kind,
        occurred_at_ms: Number(row.occurred_at_ms),
        payload: (({ acceptance_clock_prior_signal_at_ms: _clockAnchor, ...payload }) => payload)(activityChangePayload(row)),
      })),
      next_cursor: this.encodeCursor(next),
      retained_watermark: watermark,
      earliest_cursor: this.encodeCursor(watermark),
      has_more: hasMore,
    };
  }

  snapshot(principal, now = this.clock()) {
    this.#requirePrincipal(principal, 'summary_reader', 'activity.read_summary', now);
    now = this.#normalizeWriteClock(now);
    const latest = Number(this.db.prepare('SELECT COALESCE(MAX(server_sequence),0) AS value FROM activity_changes').get().value);
    const watermark = metadataNumber(this.db, 'retained_watermark');
    const body = {
      contract: ACTIVITY_CONTRACT,
      schema_version: ACTIVITY_FEATURE_VERSION,
      snapshot_id: `activity-snapshot:${randomUUID()}`,
      snapshot_generation: metadataNumber(this.db, 'snapshot_generation'),
      generated_at_ms: now,
      authority: { node_id: this.nodeId, epoch: this.authorityEpoch },
      retained_watermark: watermark,
      base_cursor: this.encodeCursor(latest),
      summary: this.summary(principal, now),
    };
    return { ...body, digest: createHmac('sha256', this.cursorSecret).update(JSON.stringify(canonicalize(body))).digest('base64url') };
  }

  acknowledge(principal, raw, now = this.clock()) {
    now = this.#normalizeWriteClock(now);
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const currentPrincipal = this.#requirePrincipal(principal, 'summary_reader', 'activity.read_summary', now);
      now = this.#normalizeWriteClock(now);
      const body = object(raw, 'body');
      exactKeys(body, ['cursor'], 'body');
      const sequence = this.decodeCursor(body.cursor);
      const watermark = metadataNumber(this.db, 'retained_watermark');
      const latest = Number(this.db.prepare('SELECT COALESCE(MAX(server_sequence),0) AS value FROM activity_changes').get().value);
      if (sequence < watermark) fail('resync_required', 'Activity ack cursor predates retention.', { status: 409, details: this.resyncDetails('retention_gap') });
      if (sequence > latest) fail('invalid_cursor', 'Activity cursor points beyond the current feed.');
      this.db.prepare(`UPDATE activity_reader_acks SET last_ack_sequence=MAX(last_ack_sequence,?),updated_at_ms=? WHERE principal_id=?`)
        .run(sequence, now, currentPrincipal.principal_id);
      this.#bumpCommitHighWater({ now });
      this.db.exec('COMMIT');
      return { ok: true, cursor: this.encodeCursor(sequence) };
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }

  revokeProbe(probeId, now = this.clock()) {
    now = this.#normalizeWriteClock(now);
    probeId = opaqueId(probeId, 'probe_id');
    now = this.#assertAuthority(now);
    this.db.exec('BEGIN IMMEDIATE');
    try {
      now = this.#assertAuthority(now);
      const principal = this.db.prepare("SELECT * FROM activity_principals WHERE principal_type='probe' AND probe_id=? AND deleted_at_ms IS NULL").get(probeId);
      if (!principal) fail('probe_not_found', 'Probe does not exist.', { status: 404 });
      if (principal.revoked_at_ms != null) {
        this.db.exec('COMMIT');
        return { status: 'duplicate', probe_id: probeId, revoked_at_ms: Number(principal.revoked_at_ms) };
      }
      this.db.prepare('UPDATE activity_principals SET revoked_at_ms=? WHERE principal_id=?').run(now, principal.principal_id);
      this.db.prepare('UPDATE activity_credentials SET revoked_at_ms=? WHERE principal_id=? AND revoked_at_ms IS NULL').run(now, principal.principal_id);
      this.db.prepare("UPDATE activity_projections SET state='unknown',credential_state='revoked',coverage_status='revoked',status_reason='credential_revoked',updated_at_ms=? WHERE probe_id=?").run(now, probeId);
      const generation = metadataNumber(this.db, 'snapshot_generation') + 1;
      setMetadataNumber(this.db, 'snapshot_generation', generation);
      const change = this.db.prepare(`INSERT INTO activity_changes(change_id,kind,device_id,probe_id,occurred_at_ms,payload_json)
        VALUES (?,'activity.probe.revoked',?,?,?,?)`).run(randomUUID(), principal.device_id, probeId, now, JSON.stringify({ device_id: principal.device_id, probe_id: probeId, snapshot_generation: generation }));
      this.#sealChange(Number(change.lastInsertRowid));
      this.#audit('probe.revoked', { principalId: principal.principal_id, deviceId: principal.device_id, probeId, now });
      this.#bumpCommitHighWater({ now });
      this.db.exec('COMMIT');
      return { status: 'revoked', probe_id: probeId, revoked_at_ms: now, snapshot_generation: generation };
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }

  #refreshRetainedProjection(probeId, now) {
    const principal = this.db.prepare("SELECT * FROM activity_principals WHERE probe_id=? AND deleted_at_ms IS NULL").get(probeId);
    if (!principal) return;
    const state = this.db.prepare('SELECT * FROM activity_probe_state WHERE probe_id=?').get(probeId);
    const context = retiredContext(state);
    const history = this.db.prepare('SELECT * FROM activity_events WHERE probe_id=? ORDER BY origin_sequence').all(probeId);
    const clocks = activityClockHealthMaps(history, { retiredSignal: context.max_signal_at_ms });
    if (!clocks) fail('activity_schema_not_ready', 'Activity retained clock context is invalid.', { status: 503 });
    const permission = activityPermissionStatus(history, context.permission_status, clocks.logical);
    const gap = activitySequenceCoverage(history.map((row) => row.origin_sequence), state.retained_origin_floor).missing.length > 0;
    const projection = this.db.prepare('SELECT * FROM activity_projections WHERE probe_id=?').get(probeId);
    let current = history.find((row) => row.event_id === projection?.current_event_id);
    if (!current && history.length) current = history.at(-1);
    if (!current) {
      this.db.prepare('UPDATE activity_probe_state SET last_coverage_status=? WHERE probe_id=?')
        .run(permission === 'unavailable' ? 'permission_unavailable' : permission === 'pending' ? 'permission_recovery_pending' : 'unknown', probeId);
      return;
    }
    const later = history.at(-1);
    let clockHealth = clocks.logical.get(current.event_id);
    let coverage = current.received_at_ms > current.occurred_at_ms + principal.expiry_slo_ms ? 'stale'
      : ['none', 'unknown'].includes(JSON.parse(current.coverage_json).mode) ? 'missing' : 'covered';
    const normalized = { kind: current.kind, confidence: current.confidence, payload: JSON.parse(current.payload_json) };
    let projectedState = projectionState(normalized, { clockHealth, coverageStatus: coverage });
    let reason = projectionStatusReason(normalized, { clockHealth, coverageStatus: coverage, state: projectedState });
    const laterClock = clocks.logical.get(later.event_id);
    const laterFault = ['future_skew', 'clock_regression'].includes(laterClock);
    if (principal.revoked_at_ms != null) {
      projectedState = 'unknown'; coverage = 'revoked'; reason = 'credential_revoked';
    } else if (gap) {
      projectedState = 'unknown'; coverage = 'gap'; reason = 'coverage_gap';
      if (laterFault) clockHealth = laterClock;
    } else if (permission !== 'clear') {
      projectedState = 'unknown'; reason = permission === 'unavailable' ? 'permission_unavailable' : 'insufficient_human_evidence';
      if (later.origin_sequence > current.origin_sequence && laterFault) clockHealth = laterClock;
    } else if (later.origin_sequence > current.origin_sequence && ['probe.error', 'probe.permission_changed'].includes(later.kind)) {
      projectedState = 'unknown'; reason = later.kind === 'probe.error' ? 'probe_error' : 'insufficient_human_evidence';
      if (laterFault) clockHealth = laterClock;
    } else if (later.origin_sequence > current.origin_sequence && laterFault) {
      projectedState = 'unknown'; clockHealth = laterClock; reason = laterClock;
    }
    this.db.prepare(`UPDATE activity_projections SET current_event_id=?,state=?,occurred_at_ms=?,received_at_ms=?,
      expires_at_ms=?,confidence=?,coverage_json=?,coverage_status=?,clock_health=?,credential_state=?,
      status_reason=?,last_server_sequence=?,updated_at_ms=? WHERE probe_id=?`).run(
      current.event_id, projectedState, current.occurred_at_ms, current.received_at_ms,
      derivedTimestamp(current.occurred_at_ms, Math.min(current.ttl_ms, principal.expiry_slo_ms), 'projection_clock'),
      current.confidence, current.coverage_json, coverage, clockHealth, principal.revoked_at_ms == null ? 'active' : 'revoked',
      reason, current.server_sequence, now, probeId,
    );
    this.db.prepare('UPDATE activity_probe_state SET last_coverage_status=? WHERE probe_id=?')
      .run(permission === 'unavailable' ? 'permission_unavailable' : permission === 'pending' ? 'permission_recovery_pending' : gap ? 'gap' : coverage, probeId);
  }

  #tombstoneRows(rows, now) {
    let floorChanged = false;
    for (const row of rows) {
      const expiresAt = derivedTimestamp(
        Number(row.received_at_ms ?? now),
        ACTIVITY_RAW_RETENTION_MS,
        'received_at_ms',
      );
      if (expiresAt > now) {
        this.db.prepare(`INSERT INTO activity_event_tombstones(
          event_id,device_id,probe_id,origin_sequence,canonical_digest,removed_at_ms,expires_at_ms
        ) VALUES (?,?,?,?,?,?,?) ON CONFLICT(event_id) DO NOTHING`).run(
          row.event_id, row.device_id, row.probe_id, row.origin_sequence, row.canonical_digest,
          now, expiresAt,
        );
      }
      const priorFloor = this.db.prepare('SELECT retained_origin_floor FROM activity_probe_state WHERE probe_id=?').get(row.probe_id)?.retained_origin_floor;
      if (priorFloor == null || Number(priorFloor) < Number(row.origin_sequence)) floorChanged = true;
      this.db.prepare(`UPDATE activity_probe_state
        SET retained_origin_floor=CASE
          WHEN retained_origin_floor IS NULL OR retained_origin_floor<? THEN ?
          ELSE retained_origin_floor
        END WHERE probe_id=?`).run(
        row.origin_sequence, row.origin_sequence, row.probe_id,
      );
    }
    if (rows.length) {
      setMetadataNumber(
        this.db,
        'retired_event_count',
        metadataNumber(this.db, 'retired_event_count') + rows.length,
      );
    }
    return floorChanged;
  }

  deleteProbe(probeId, now = this.clock()) {
    now = this.#normalizeWriteClock(now);
    probeId = opaqueId(probeId, 'probe_id');
    now = this.#assertAuthority(now);
    this.db.exec('BEGIN IMMEDIATE');
    try {
      now = this.#assertAuthority(now);
      const principal = this.db.prepare("SELECT * FROM activity_principals WHERE principal_type='probe' AND probe_id=? AND deleted_at_ms IS NULL").get(probeId);
      if (!principal) fail('probe_not_found', 'Probe does not exist.', { status: 404 });
      const rows = this.db.prepare('SELECT event_id,device_id,probe_id,origin_sequence,canonical_digest,received_at_ms,server_sequence FROM activity_events WHERE probe_id=?').all(probeId);
      const maxRemoved = Number(this.db.prepare('SELECT COALESCE(MAX(server_sequence),0) AS value FROM activity_changes WHERE probe_id=?').get(probeId).value);
      this.db.prepare('UPDATE activity_principals SET revoked_at_ms=COALESCE(revoked_at_ms,?),deleted_at_ms=? WHERE principal_id=?').run(now, now, principal.principal_id);
      this.db.prepare('UPDATE activity_credentials SET revoked_at_ms=COALESCE(revoked_at_ms,?) WHERE principal_id=?').run(now, principal.principal_id);
      this.#tombstoneRows(rows, now);
      const retainedFloor = this.db.prepare('SELECT retained_origin_floor FROM activity_probe_state WHERE probe_id=?').get(probeId)?.retained_origin_floor ?? null;
      const retiredPrefixDigest = replayPrefixDigest(this.cursorSecret, principal.event_id_prefix);
      const retiredFloorDigest = replayFloorDigest(this.cursorSecret, principal.event_id_prefix, retainedFloor);
      this.db.prepare(`INSERT INTO activity_replay_lineage_floors(lineage_digest,floor_digest)
        VALUES (?,?)`).run(retiredPrefixDigest, retiredFloorDigest);
      this.db.prepare(`UPDATE activity_principals SET event_id_prefix=NULL,
        retired_event_prefix_digest=?,retired_floor_digest=? WHERE principal_id=?`).run(
        retiredPrefixDigest, retiredFloorDigest, principal.principal_id,
      );
      this.db.prepare('DELETE FROM activity_events WHERE probe_id=?').run(probeId);
      this.db.prepare('DELETE FROM activity_projections WHERE probe_id=?').run(probeId);
      this.db.prepare('DELETE FROM activity_rate_limits WHERE probe_id=?').run(probeId);
      this.db.prepare('DELETE FROM activity_probe_state WHERE probe_id=?').run(probeId);
      this.db.prepare('DELETE FROM activity_changes WHERE probe_id=?').run(probeId);
      if (maxRemoved) setMetadataNumber(this.db, 'retained_watermark', Math.max(metadataNumber(this.db, 'retained_watermark'), maxRemoved));
      const generation = metadataNumber(this.db, 'snapshot_generation') + 1;
      setMetadataNumber(this.db, 'snapshot_generation', generation);
      const receiptId = `activity-delete:${randomUUID()}`;
      const storage = { core_raw: 'complete', core_projection: 'complete', device_spool: 'client_action_required', backup: 'expires_by_policy' };
      this.db.prepare(`INSERT INTO activity_deletion_receipts(
        receipt_id,scope,device_id,probe_id,started_at_ms,isolated_at_ms,completed_at_ms,snapshot_generation,status_json
      ) VALUES (?,'probe',?,?,?,?,?,?,?)`).run(receiptId, principal.device_id, probeId, now, now, now, generation, JSON.stringify(storage));
      const change = this.db.prepare(`INSERT INTO activity_changes(change_id,kind,device_id,probe_id,occurred_at_ms,payload_json)
        VALUES (?,'activity.probe.deleted',?,?,?,?)`).run(
          randomUUID(), principal.device_id, probeId, now,
          JSON.stringify({ receipt_id: receiptId, device_id: principal.device_id, probe_id: probeId, snapshot_generation: generation }),
        );
      this.#sealChange(Number(change.lastInsertRowid));
      this.#audit('probe.deleted', { principalId: principal.principal_id, deviceId: principal.device_id, probeId, details: { receipt_id: receiptId }, now });
      this.#bumpCommitHighWater({ replayStateChanged: true, now });
      this.db.exec('COMMIT');
      return { receipt_id: receiptId, scope: 'probe', device_id: principal.device_id, probe_id: probeId, status: storage, snapshot_generation: generation };
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }

  deleteDevice(deviceId, now = this.clock()) {
    now = this.#normalizeWriteClock(now);
    deviceId = opaqueId(deviceId, 'device_id');
    now = this.#assertAuthority(now);
    this.db.exec('BEGIN IMMEDIATE');
    try {
      now = this.#assertAuthority(now);
      const probes = this.db.prepare("SELECT principal_id,probe_id,event_id_prefix FROM activity_principals WHERE principal_type='probe' AND device_id=? AND deleted_at_ms IS NULL").all(deviceId);
      if (!probes.length) fail('device_not_found', 'Activity device does not exist.', { status: 404 });
      const rows = this.db.prepare('SELECT event_id,device_id,probe_id,origin_sequence,canonical_digest,received_at_ms,server_sequence FROM activity_events WHERE device_id=?').all(deviceId);
      const maxRemoved = Number(this.db.prepare('SELECT COALESCE(MAX(server_sequence),0) AS value FROM activity_changes WHERE device_id=?').get(deviceId).value);
      this.db.prepare("UPDATE activity_principals SET revoked_at_ms=COALESCE(revoked_at_ms,?),deleted_at_ms=? WHERE principal_type='probe' AND device_id=? AND deleted_at_ms IS NULL").run(now, now, deviceId);
      this.db.prepare(`UPDATE activity_credentials SET revoked_at_ms=COALESCE(revoked_at_ms,?)
        WHERE principal_id IN (SELECT principal_id FROM activity_principals WHERE principal_type='probe' AND device_id=?)`).run(now, deviceId);
      this.#tombstoneRows(rows, now);
      this.db.prepare('DELETE FROM activity_events WHERE device_id=?').run(deviceId);
      this.db.prepare('DELETE FROM activity_projections WHERE device_id=?').run(deviceId);
      for (const probe of probes) {
        const retainedFloor = this.db.prepare('SELECT retained_origin_floor FROM activity_probe_state WHERE probe_id=?').get(probe.probe_id)?.retained_origin_floor ?? null;
        const retiredPrefixDigest = replayPrefixDigest(this.cursorSecret, probe.event_id_prefix);
        const retiredFloorDigest = replayFloorDigest(this.cursorSecret, probe.event_id_prefix, retainedFloor);
        this.db.prepare(`INSERT INTO activity_replay_lineage_floors(lineage_digest,floor_digest)
          VALUES (?,?)`).run(retiredPrefixDigest, retiredFloorDigest);
        this.db.prepare(`UPDATE activity_principals SET event_id_prefix=NULL,
          retired_event_prefix_digest=?,retired_floor_digest=? WHERE principal_id=?`).run(
          retiredPrefixDigest, retiredFloorDigest, probe.principal_id,
        );
        this.db.prepare('DELETE FROM activity_rate_limits WHERE probe_id=?').run(probe.probe_id);
        this.db.prepare('DELETE FROM activity_probe_state WHERE probe_id=?').run(probe.probe_id);
      }
      this.db.prepare('DELETE FROM activity_changes WHERE device_id=?').run(deviceId);
      if (maxRemoved) setMetadataNumber(this.db, 'retained_watermark', Math.max(metadataNumber(this.db, 'retained_watermark'), maxRemoved));
      const generation = metadataNumber(this.db, 'snapshot_generation') + 1;
      setMetadataNumber(this.db, 'snapshot_generation', generation);
      const receiptId = `activity-delete:${randomUUID()}`;
      const storage = { core_raw: 'complete', core_projection: 'complete', device_spool: 'client_action_required', backup: 'expires_by_policy' };
      this.db.prepare(`INSERT INTO activity_deletion_receipts(
        receipt_id,scope,device_id,started_at_ms,isolated_at_ms,completed_at_ms,snapshot_generation,status_json
      ) VALUES (?,'device',?,?,?,?,?,?)`).run(receiptId, deviceId, now, now, now, generation, JSON.stringify(storage));
      const change = this.db.prepare(`INSERT INTO activity_changes(change_id,kind,device_id,occurred_at_ms,payload_json)
        VALUES (?,'activity.device.deleted',?,?,?)`).run(
          randomUUID(), deviceId, now,
          JSON.stringify({ receipt_id: receiptId, device_id: deviceId, snapshot_generation: generation }),
        );
      this.#sealChange(Number(change.lastInsertRowid));
      this.#audit('device.deleted', { deviceId, details: { receipt_id: receiptId, probes: probes.length }, now });
      this.#bumpCommitHighWater({ replayStateChanged: true, now });
      this.db.exec('COMMIT');
      return { receipt_id: receiptId, scope: 'device', device_id: deviceId, status: storage, snapshot_generation: generation };
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }

  runRetention(now = this.clock()) {
    try {
      const result = this.#runRetention(now);
      this.retentionFailure = null;
      return result;
    } catch (error) {
      if (!this.integrityFailure) this.retentionFailure = {
        code: error?.code ?? 'activity_retention_error',
        failed_at_ms: Number.isSafeInteger(now) ? now : null,
      };
      throw error;
    }
  }

  #runRetention(now) {
    now = this.#normalizeWriteClock(now);
    now = this.#assertAuthority(now, { allowRetentionRecovery: true });
    this.db.exec('BEGIN IMMEDIATE');
    try {
      now = this.#assertAuthority(now, { allowRetentionRecovery: true });
      const cutoff = now - ACTIVITY_RAW_RETENTION_MS;
      const duePrefixes = this.db.prepare(`SELECT probe_id,MAX(origin_sequence) AS floor FROM activity_events
        WHERE received_at_ms<=? GROUP BY probe_id`).all(cutoff);
      const rows = duePrefixes.flatMap(({ probe_id, floor }) => this.db.prepare(
        'SELECT * FROM activity_events WHERE probe_id=? AND origin_sequence<=? ORDER BY origin_sequence',
      ).all(probe_id, floor));
      for (const { probe_id } of duePrefixes) {
        const state = this.db.prepare('SELECT * FROM activity_probe_state WHERE probe_id=?').get(probe_id);
        const context = retiredContext(state);
        const prefix = rows.filter((row) => row.probe_id === probe_id);
        const clocks = activityClockHealthMaps(prefix, { retiredSignal: context.max_signal_at_ms });
        const permission = activityPermissionStatus(prefix, context.permission_status, clocks.logical);
        for (const row of prefix) {
          if (clocks.logical.get(row.event_id) !== 'future_skew') context.max_signal_at_ms = context.max_signal_at_ms == null
            ? row.occurred_at_ms : Math.max(context.max_signal_at_ms, row.occurred_at_ms);
        }
        const latest = prefix.at(-1);
        const latestClock = clocks.logical.get(latest.event_id);
        context.permission_status = permission;
        context.source_health = permission === 'unavailable' ? 'permission_unavailable'
          : permission === 'pending' ? 'insufficient_human_evidence'
          : latest.kind === 'probe.error' ? 'probe_error' : latestClock;
        this.db.prepare('UPDATE activity_probe_state SET retired_context_json=? WHERE probe_id=?')
          .run(JSON.stringify(context), probe_id);
      }
      const removedSequences = new Set(rows.map((row) => row.server_sequence));
      const oldChanges = this.db.prepare('SELECT server_sequence,occurred_at_ms FROM activity_changes').all()
        .filter((row) => row.occurred_at_ms <= cutoff || removedSequences.has(row.server_sequence));
      const maxRemoved = oldChanges.reduce((max, row) => Math.max(max, Number(row.server_sequence)), 0);
      const floorChanged = this.#tombstoneRows(rows, now);
      let removedEventCount = 0;
      for (const row of rows) removedEventCount += Number(this.db.prepare('DELETE FROM activity_events WHERE event_id=?').run(row.event_id).changes);
      const deletedEvents = { changes: removedEventCount };
      let removedChangeCount = 0;
      for (const row of oldChanges) removedChangeCount += Number(this.db.prepare('DELETE FROM activity_changes WHERE server_sequence=?').run(row.server_sequence).changes);
      const deletedChanges = { changes: removedChangeCount };
      const deletedTombstones = this.db.prepare('DELETE FROM activity_event_tombstones WHERE expires_at_ms<=?').run(now);
      const deletedAudit = this.db.prepare('DELETE FROM activity_audit WHERE expires_at_ms<=?').run(now);
      const clearedState = this.db.prepare(`UPDATE activity_probe_state SET
        max_origin_sequence=NULL,max_occurred_at_ms=NULL,last_received_at_ms=NULL,
        last_clock_health='unknown',last_coverage_status=CASE
          WHEN last_coverage_status IN ('permission_unavailable','permission_recovery_pending') THEN last_coverage_status
          ELSE 'unknown'
        END
        WHERE last_received_at_ms<=?`).run(cutoff);
      const deletedRateLimits = this.db.prepare('DELETE FROM activity_rate_limits WHERE window_start_ms<=?').run(cutoff);
      const expiredProjections = this.db.prepare(`UPDATE activity_projections SET
        current_event_id=NULL,state='unknown',occurred_at_ms=NULL,received_at_ms=NULL,
        expires_at_ms=NULL,confidence=NULL,coverage_json='{}',coverage_status='retention_expired',
        clock_health='unknown',status_reason='retention_expired',last_server_sequence=NULL,updated_at_ms=?
        WHERE received_at_ms<=?`).run(now, cutoff);
      for (const { probe_id } of duePrefixes) {
        const current = this.db.prepare('SELECT current_event_id FROM activity_projections WHERE probe_id=?').get(probe_id);
        if (current?.current_event_id && removedSequences.has(rows.find((row) => row.event_id === current.current_event_id)?.server_sequence)) {
          this.db.prepare(`UPDATE activity_projections SET current_event_id=NULL,state='unknown',occurred_at_ms=NULL,
            received_at_ms=NULL,expires_at_ms=NULL,confidence=NULL,coverage_json='{}',coverage_status='retention_expired',
            clock_health='unknown',status_reason='retention_expired',last_server_sequence=NULL,updated_at_ms=? WHERE probe_id=?`).run(now, probe_id);
        }
        this.#refreshRetainedProjection(probe_id, now);
      }
      const oldWatermark = metadataNumber(this.db, 'retained_watermark');
      const newWatermark = Math.max(oldWatermark, maxRemoved);
      if (newWatermark !== oldWatermark) {
        setMetadataNumber(this.db, 'retained_watermark', newWatermark);
        setMetadataNumber(this.db, 'snapshot_generation', metadataNumber(this.db, 'snapshot_generation') + 1);
      }
      if (rows.length || oldChanges.length) {
        const change = this.db.prepare(`INSERT INTO activity_changes(change_id,kind,occurred_at_ms,payload_json)
          VALUES (?,'activity.retention.cleaned',?,?)`).run(
            randomUUID(), now,
            JSON.stringify({ retained_watermark: newWatermark, snapshot_generation: metadataNumber(this.db, 'snapshot_generation') }),
          );
        this.#sealChange(Number(change.lastInsertRowid));
      }
      const changed = [
        deletedEvents, deletedChanges, deletedTombstones, deletedAudit,
        clearedState, deletedRateLimits, expiredProjections,
      ].some((result) => Number(result.changes) > 0) || newWatermark !== oldWatermark;
      if (rows.length || oldChanges.length) {
        this.#audit('retention.cleaned', { details: { removed_events: rows.length, old_watermark: oldWatermark, new_watermark: newWatermark }, now });
      }
      if (changed || rows.length || oldChanges.length) {
        this.#bumpCommitHighWater({ replayStateChanged: floorChanged, now });
      }
      this.db.exec('COMMIT');
      return { removed_events: rows.length, retained_watermark: newWatermark, earliest_cursor: this.#encodeCursorUnchecked(newWatermark), snapshot_generation: metadataNumber(this.db, 'snapshot_generation') };
    } catch (error) {
      try {
        this.db.exec('ROLLBACK');
      } catch {
        // Preserve the first retention failure even if SQLite already ended the transaction.
      }
      throw error;
    }
  }

  adminExport() {
    this.#assertAuthorityPreflight();
    if (!this.schemaStatus().ready) {
      fail('activity_schema_not_ready', 'Activity schema row integrity audit failed.', { status: 503 });
    }
    this.#assertAuthority();
    this.runRetention(this.clock());
    this.#assertAuthority();
    if (!this.schemaStatus().ready) {
      fail('activity_schema_not_ready', 'Activity schema row integrity audit failed.', { status: 503 });
    }
    return {
      contract: ACTIVITY_CONTRACT,
      events: this.db.prepare(`SELECT event_id,device_id,probe_id,origin_sequence,kind,
        occurred_at_ms,received_at_ms,ttl_ms,confidence,source,coverage_json,payload_json,
        receipt_id,server_sequence,clock_health FROM activity_events ORDER BY server_sequence`).all().map((row) => ({
        ...row,
        origin_sequence: Number(row.origin_sequence), occurred_at_ms: Number(row.occurred_at_ms),
        received_at_ms: Number(row.received_at_ms), ttl_ms: Number(row.ttl_ms),
        server_sequence: Number(row.server_sequence), coverage: JSON.parse(row.coverage_json),
        payload: JSON.parse(row.payload_json), coverage_json: undefined, payload_json: undefined,
      })),
      deletion_receipts: this.db.prepare('SELECT * FROM activity_deletion_receipts ORDER BY started_at_ms').all().map((row) => ({ ...row, status: JSON.parse(row.status_json), status_json: undefined })),
      retained_watermark: metadataNumber(this.db, 'retained_watermark'),
    };
  }

  audit() {
    this.#assertAuthorityPreflight();
    if (!this.schemaStatus().ready) {
      fail('activity_schema_not_ready', 'Activity schema row integrity audit failed.', { status: 503 });
    }
    this.#assertAuthority();
    this.runRetention(this.clock());
    this.#assertAuthority();
    if (!this.schemaStatus().ready) {
      fail('activity_schema_not_ready', 'Activity schema row integrity audit failed.', { status: 503 });
    }
    return this.db.prepare('SELECT * FROM activity_audit ORDER BY occurred_at_ms,audit_id').all().map((row) => ({
      audit_id: row.audit_id,
      action: row.action,
      principal_id: row.principal_id,
      device_id: row.device_id,
      probe_id: row.probe_id,
      occurred_at_ms: Number(row.occurred_at_ms),
      details: JSON.parse(row.details_json),
    }));
  }
}
