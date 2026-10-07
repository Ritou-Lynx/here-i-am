// Local source adapter between the App's frozen capture projection and the
// owner-controlled Core adoption API. It never discovers files, reads a store,
// grants access, or applies a migration while freezing it.
import { canonicalJSON } from './domain_store.mjs';
import { migrationOutputsDigest, migrationRecordsDigest } from './personal_domain_migration.mjs';

export const PHONE_CAPTURE_MAPPING_VERSION = 'personal-import-v1';

const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const exact = (value, keys) => object(value) && Object.keys(value).length === keys.length
  && keys.every(key => Object.hasOwn(value, key));
const identifier = value => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$/.test(value);
const digest = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const fail = () => { throw Object.assign(new Error('invalid_phone_capture_migration'),
  { code: 'invalid_phone_capture_migration' }); };
const clone = value => structuredClone(value);

function expectedProjectionRef(sourceId) {
  const encoded = Buffer.from(sourceId, 'utf8').toString('base64').replaceAll('+', '-').replaceAll('/', '_');
  return `captures:legacy-note:${encoded}`;
}

function validateBinding(binding) {
  return exact(binding, ['core_instance_id', 'principal_id', 'credential_generation', 'installation_id'])
    && identifier(binding.core_instance_id) && identifier(binding.principal_id)
    && Number.isSafeInteger(binding.credential_generation) && binding.credential_generation >= 1
    && identifier(binding.installation_id);
}

function validateSource(source, count) {
  return exact(source, ['source_kind', 'source_instance_id', 'source_cursor', 'record_count',
    'records_digest', 'outputs_digest'])
    && source.source_kind === 'claude_web_note' && identifier(source.source_instance_id)
    && typeof source.source_cursor === 'string' && /^(0|[1-9][0-9]*)$/.test(source.source_cursor)
    && source.source_cursor.length <= 4096 && source.record_count === count
    && digest(source.records_digest) && digest(source.outputs_digest);
}

function validateSlot(slot) {
  return exact(slot, ['id', 'content', 'identity', 'snapshot']) && identifier(slot.id)
    && digest(slot.content) && digest(slot.identity) && digest(slot.snapshot);
}

function validateAppRecord(record) {
  if (!exact(record, ['source_id', 'source_revision', 'target_id', 'target_revision', 'is_tombstone', 'op',
    'source_digest', 'output_ids', 'output_digest', 'slots', 'issues', 'projection_source_ref'])
    || !identifier(record.source_id) || !Number.isSafeInteger(record.source_revision) || record.source_revision < 1
    || record.target_id !== record.source_id || record.target_revision !== record.source_revision
    || record.is_tombstone !== (record.op === 'delete') || !['upsert', 'delete'].includes(record.op)
    || !digest(record.source_digest) || !digest(record.output_digest)
    || !Array.isArray(record.output_ids) || record.output_ids.length > 5000
    || record.output_ids.some(id => !identifier(id)) || new Set(record.output_ids).size !== record.output_ids.length
    || canonicalJSON(record.output_ids) !== canonicalJSON([...record.output_ids].sort())
    || !Array.isArray(record.slots) || record.slots.length > 5000 || !record.slots.every(validateSlot)
    || new Set(record.slots.map(slot => slot.id)).size !== record.slots.length
    || canonicalJSON(record.output_ids) !== canonicalJSON(record.slots.map(slot => slot.id).sort())
    || !Array.isArray(record.issues) || record.issues.length !== 0
    || record.projection_source_ref !== expectedProjectionRef(record.source_id)) fail();

  // The App intentionally does not retain the original receipt card_ids order;
  // deletes also omit their pre-delete IDs. source_digest therefore remains the
  // App-frozen per-record witness. The source aggregate below binds that witness
  // to this exact ID/revision set without inventing missing receipt fields.
}

function validateAppManifest(appManifest) {
  if (!exact(appManifest, ['protocol', 'migration_id', 'domain', 'binding', 'source', 'records'])
    || appManifest.protocol !== 'i-domain-migration-manifest-v1'
    || !identifier(appManifest.migration_id) || appManifest.domain !== 'captures'
    || !validateBinding(appManifest.binding) || !Array.isArray(appManifest.records)
    || appManifest.records.length < 1 || appManifest.records.length > 5000
    || !validateSource(appManifest.source, appManifest.records.length)) fail();
  appManifest.records.forEach(validateAppRecord);
  if (new Set(appManifest.records.map(record => record.source_id)).size !== appManifest.records.length
    || canonicalJSON(appManifest.records.map(record => record.source_id))
      !== canonicalJSON(appManifest.records.map(record => record.source_id).sort())
    || migrationRecordsDigest(appManifest.records) !== appManifest.source.records_digest
    || migrationOutputsDigest(appManifest.records) !== appManifest.source.outputs_digest) fail();
}

function joinedEntries(appManifest, legacyRecords) {
  if (!Array.isArray(legacyRecords) || legacyRecords.length !== appManifest.records.length) fail();
  const byId = new Map();
  for (const record of legacyRecords) {
    if (!object(record) || !identifier(record.id) || byId.has(record.id)) fail();
    byId.set(record.id, record);
  }
  const entries = appManifest.records.map(projected => {
    const record = byId.get(projected.target_id);
    if (!record || record.revision !== projected.target_revision
      || (record.deleted_at !== null) !== projected.is_tombstone
      || (!projected.is_tombstone && record.provenance?.source !== 'i_remember')) fail();
    return { source_id: projected.source_id, source_revision: projected.source_revision,
      source_digest: projected.source_digest, target_id: projected.target_id,
      target_revision: projected.target_revision, is_tombstone: projected.is_tombstone,
      output_ids: clone(projected.output_ids), output_digest: projected.output_digest, record: clone(record) };
  });
  if (byId.size !== entries.length) fail();
  return entries;
}

export function freezePhoneCaptureMigration({ owner, appManifest, legacyRecords, batchId, mappingVersion, expiresAt } = {}) {
  if (!owner || typeof owner.freezeAdoptionManifest !== 'function' || !identifier(batchId)
    || mappingVersion !== PHONE_CAPTURE_MAPPING_VERSION || typeof expiresAt !== 'string') fail();
  validateAppManifest(appManifest);
  const entries = joinedEntries(appManifest, legacyRecords);
  return owner.freezeAdoptionManifest({ migration_id: appManifest.migration_id, domain: appManifest.domain,
    binding: clone(appManifest.binding), source: clone(appManifest.source), batch_id: batchId,
    mapping_version: mappingVersion, expires_at: expiresAt, entries });
}

export function applyPhoneCaptureMigration({ owner, migrationId, adoptionToken, legacyRecords } = {}) {
  if (!owner || typeof owner.applyAdoptionManifest !== 'function' || !identifier(migrationId)
    || typeof adoptionToken !== 'string' || !adoptionToken || !Array.isArray(legacyRecords)) fail();
  return owner.applyAdoptionManifest({ migrationId, adoptionToken, records: clone(legacyRecords) });
}
