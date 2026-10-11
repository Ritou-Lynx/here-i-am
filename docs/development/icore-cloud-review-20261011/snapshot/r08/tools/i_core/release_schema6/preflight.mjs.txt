import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { pathToFileURL } from 'node:url';
import { fail, plainPath, sha256, verifyRelease } from './package.mjs';

const LEDGER = 'historical_replay_approvals_v1';
const HASH = /^[a-f0-9]{64}$/;
const RESERVED = /^(frontend:|v3-history-|core-companion:|core:|worker:)/i;
export function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  return value;
}
export const digest = value => sha256(JSON.stringify(canonical(value)));
const exact = (object, keys) => object && !Array.isArray(object) && typeof object === 'object'
  && Object.keys(object).sort().join(',') === [...keys].sort().join(',');
const nonempty = value => typeof value === 'string' && value.length > 0 && value.trim() === value;
function approvals(text) {
  const document = JSON.parse(text);
  if (!exact(document, ['version', 'approved_replays']) || document.version !== 1
      || !Array.isArray(document.approved_replays) || document.approved_replays.length !== 72) fail('exact_72_bindings_required');
  const ids = new Set(), sequences = new Set();
  const records = document.approved_replays.map(row => {
    if (!exact(row, ['sync_id', 'device_id', 'origin_sequence', 'incoming_digest', 'existing_digest'])
        || !nonempty(row.sync_id) || !nonempty(row.device_id) || RESERVED.test(row.device_id)
        || !Number.isSafeInteger(row.origin_sequence) || row.origin_sequence < 0
        || ![row.incoming_digest, row.existing_digest].every(value => typeof value === 'string' && /^[a-fA-F0-9]{64}$/.test(value))) fail('approval_invalid');
    const sequence = JSON.stringify([row.device_id, row.origin_sequence]);
    if (ids.has(row.sync_id) || sequences.has(sequence)) fail('approval_duplicate_identity');
    ids.add(row.sync_id); sequences.add(sequence);
    return { ...row, incoming_digest: row.incoming_digest.toLowerCase(), existing_digest: row.existing_digest.toLowerCase() };
  });
  return records.sort((a, b) => a.sync_id < b.sync_id ? -1 : a.sync_id > b.sync_id ? 1 : 0);
}
function grants(text) {
  const document = JSON.parse(text);
  if (!exact(document, ['version', 'grants']) || document.version !== 1 || !Array.isArray(document.grants)
      || document.grants.length < 1 || document.grants.length > 16) fail('nonempty_grants_required');
  const ids = new Set(), characters = new Set();
  for (const row of document.grants) {
    if (!exact(row, ['device_id', 'character_id', 'credential_sha256', 'from_created_at_ms'])
        || ![row.device_id, row.character_id].every(value => nonempty(value) && value.length <= 128)
        || RESERVED.test(row.device_id) || !/^[a-fA-F0-9]{64}$/.test(row.credential_sha256)
        || !Number.isSafeInteger(row.from_created_at_ms) || row.from_created_at_ms <= 0 || ids.has(row.device_id)) fail('grant_invalid');
    ids.add(row.device_id); characters.add(row.character_id);
  }
  if (characters.size !== 1) fail('grant_character_mismatch');
  return document.grants;
}
const sidecars = filename => ['-wal', '-shm', '-journal'].some(suffix => existsSync(filename + suffix));
const tableExists = (db, name) => Boolean(db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?").get(name));
function readSnapshot(filename, maxBytes) {
  const bytes = readFileSync(plainPath(filename));
  if (bytes.length > maxBytes) fail('input_size_exceeded');
  return bytes;
}
function validateConfig(config, capture) {
  const fields = ['format', 'mode', 'companion_reply_jobs', 'activity_enabled', 'domain_policy',
    'database_path', 'approvals_path', 'grants_path'];
  if (!capture) fields.push('expected_bindings_sha256', 'expected_identity_sha256', 'expected_grants_sha256', 'expected_domain_authority_sha256');
  if (!exact(config, fields) || config.format !== 'schema6-preflight-v1'
      || config.mode !== 'legacy_b3' || config.companion_reply_jobs !== false || config.activity_enabled !== false
      || config.domain_policy !== 'owner_managed') fail('explicit_safe_config_required');
  for (const key of fields.filter(key => key.startsWith('expected_'))) if (!HASH.test(config[key] ?? '')) fail('external_anchor_required');
  for (const key of ['database_path', 'approvals_path', 'grants_path']) plainPath(config[key]);
  if (new Set([config.database_path, config.approvals_path, config.grants_path].map(p => p.toLowerCase())).size !== 3) fail('input_paths_must_differ');
}

// Read-only preflight only: never import CoreStore, run migrations, repair ledger,
// activate backup_read_only, construct a server, or infer an activity recovery floor.
export async function inspectInputs({ config, capture = false, assertDomainReady }) {
  validateConfig(config, capture);
  if (sidecars(config.database_path)) fail('quiescent_checkpointed_copy_required');
  const paths = [config.database_path, config.approvals_path, config.grants_path];
  const bytes = paths.map((p, i) => readSnapshot(p, i === 0 ? Number.MAX_SAFE_INTEGER : i === 1 ? 512 * 1024 : 32 * 1024));
  const hashes = bytes.map(sha256);
  const external = approvals(bytes[1].toString('utf8'));
  const localGrants = grants(bytes[2].toString('utf8'));
  let db;
  try {
    db = new DatabaseSync(`${pathToFileURL(config.database_path).href}?mode=ro&immutable=1`, { readOnly: true });
    if (db.prepare('PRAGMA integrity_check').get().integrity_check !== 'ok') fail('database_integrity_failed');
    const metadata = new Map(db.prepare('SELECT key,value FROM core_metadata').all().map(row => [row.key, row.value]));
    if (!['5', '6'].includes(metadata.get('schema_version')) || !nonempty(metadata.get('node_id')) || !nonempty(metadata.get('cursor_secret'))) fail('core_identity_or_schema_invalid');
    if (!metadata.has(LEDGER)) fail('durable_ledger_required');
    if (Buffer.byteLength(metadata.get(LEDGER)) > 512 * 1024) fail('ledger_too_large');
    const ledger = approvals(metadata.get(LEDGER));
    const bindingsHash = digest(external);
    if (bindingsHash !== digest(ledger)) fail('approval_ledger_set_mismatch');
    if (!tableExists(db, 'activity_metadata') || !tableExists(db, 'activity_runtime_claim')) fail('activity_role_unverified');
    const role = db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get()?.value;
    if (role === 'backup_read_only') fail('backup_activation_unsupported');
    if (role !== 'live') fail('activity_role_unverified');
    const claim = db.prepare('SELECT runtime_id,lease_expires_at_ms FROM activity_runtime_claim WHERE singleton=1').get();
    if (!claim || claim.runtime_id !== '' || claim.lease_expires_at_ms !== 0) fail('activity_recovery_required');
    const devices = db.prepare('SELECT * FROM devices ORDER BY device_id').all();
    const byDevice = new Map(devices.map(row => [row.device_id, row]));
    for (const grant of localGrants) {
      const device = byDevice.get(grant.device_id);
      if (device?.platform !== 'android' || device.token_hash !== grant.credential_sha256.toLowerCase()) fail('grant_current_credential_mismatch');
      if (metadata.has('domain_primary_character_id') && metadata.get('domain_primary_character_id') !== grant.character_id) fail('grant_primary_character_mismatch');
      if (db.prepare("SELECT 1 FROM companion_reply_jobs WHERE character_id=? AND status IN ('pending','claimed') LIMIT 1").get(grant.character_id)) fail('companion_jobs_conflict');
    }
    for (const binding of ledger) {
      const device = byDevice.get(binding.device_id);
      if (!device || device.platform === 'external-frontend' || RESERVED.test(device.device_id)) fail('replay_device_invalid');
      const row = db.prepare('SELECT * FROM chat_messages WHERE sync_id=?').get(binding.sync_id);
      if (!row || !/^v3-history-[a-f0-9]{20}$/.test(row.origin_device_id) || row.sender !== 'user'
          || !Number.isSafeInteger(row.origin_sequence) || row.origin_sequence < 0 || !Number.isSafeInteger(row.server_sequence) || row.server_sequence < 1
          || !byDevice.has(row.origin_device_id) || row.canonical_digest !== binding.existing_digest) fail('historical_row_invalid');
      const normalized = { sync_id: row.sync_id, origin_device_id: row.origin_device_id,
        origin_sequence: row.origin_sequence, character_id: row.character_id, sender: row.sender,
        content: row.content, created_at_ms: row.created_at_ms, message_type: row.message_type,
        asset_refs: JSON.parse(row.asset_refs_json), addenda: JSON.parse(row.addenda_json) };
      if (digest(normalized) !== binding.existing_digest) fail('historical_digest_mismatch');
      const event = db.prepare('SELECT entity_id,kind FROM change_events WHERE server_sequence=?').get(row.server_sequence);
      if (!event || event.entity_id !== row.sync_id || event.kind !== 'chat.message.upsert') fail('historical_event_identity_mismatch');
      const collision = db.prepare('SELECT sync_id FROM chat_messages WHERE origin_device_id=? AND origin_sequence=?').get(binding.device_id, binding.origin_sequence);
      if (collision && collision.sync_id !== binding.sync_id) fail('reserved_sequence_collision');
    }
    const identity = { node_id: metadata.get('node_id'), cursor_secret: metadata.get('cursor_secret'), devices,
      server_sequence: db.prepare('SELECT MAX(server_sequence) AS value FROM change_events').get().value,
      sequence_watermark: db.prepare("SELECT seq FROM sqlite_sequence WHERE name='change_events'").get()?.seq ?? 0,
      origins: db.prepare('SELECT origin_device_id,MAX(origin_sequence) AS sequence FROM chat_messages GROUP BY origin_device_id ORDER BY origin_device_id').all() };
    let domainAuthority = null;
    if (metadata.get('schema_version') === '6') {
      if (typeof assertDomainReady !== 'function') fail('domain_schema_verifier_required');
      assertDomainReady(db);
      domainAuthority = { primary: metadata.get('domain_primary_character_id') ?? null,
        registry: db.prepare('SELECT * FROM domain_registry ORDER BY domain').all(),
        principals: db.prepare('SELECT * FROM domain_principals ORDER BY principal_id').all(),
        phone_capabilities: db.prepare('SELECT * FROM domain_phone_capabilities ORDER BY device_id,character_id').all() };
    }
    const anchors = { expected_bindings_sha256: bindingsHash, expected_identity_sha256: digest(identity),
      expected_grants_sha256: hashes[2], expected_domain_authority_sha256: digest(domainAuthority) };
    if (!capture) for (const [key, value] of Object.entries(anchors)) if (config[key] !== value) fail('trusted_anchor_mismatch');
    return { package_verified: false, candidate_only: true, deployed: false, activation_supported: false, baseline_capture_only: capture, preflight_passed: !capture,
      database_schema_version: Number(metadata.get('schema_version')), exact_bindings: 72, grants: localGrants.length,
      database_sha256: hashes[0], approvals_sha256: hashes[1], ...anchors,
      input_unchanged: true, services_started: 0, recovery_floor_verified: false, deployment_ready: false };
  } finally {
    db?.close();
    if (sidecars(config.database_path) || paths.some((p, i) => sha256(readFileSync(plainPath(p))) !== hashes[i])) fail('input_changed_during_preflight');
  }
}

// Production entry always verifies the full externally anchored package before
// loading its schema inspector. No CLI flag selects a test verifier or Node hash.
export async function preflight({ release, manifestHash, config, capture = false }) {
  const packageReport = verifyRelease(release, manifestHash);
  const { assertDomainSchemaReady } = await import(pathToFileURL(path.join(release, 'tools/i_core/domain_schema.mjs')).href);
  const report = await inspectInputs({ config, capture, assertDomainReady: assertDomainSchemaReady });
  verifyRelease(release, manifestHash);
  return { ...packageReport, ...report, package_verified: true };
}
