// Cross-language migration proof primitives. They do not discover files, grant
// principals, expose keys, or activate migration. A trusted owner calls them
// only after a locally frozen manifest has been checked by Core.
import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import { canonicalJSON } from './domain_store.mjs';

const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const exact = (value, required, optional = []) => object(value)
  && required.every(key => Object.hasOwn(value, key))
  && Object.keys(value).every(key => required.includes(key) || optional.includes(key));
const identifier = value => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$/.test(value);
const keyId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,40}$/.test(value);
const digest = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const iso = value => typeof value === 'string' && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value)
  && Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value;

export function migrationSecretBytes(secret) {
  if (typeof secret !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(secret)) throw new Error('invalid_migration_key');
  const bytes = Buffer.from(secret, 'base64url');
  if (bytes.length !== 32 || bytes.toString('base64url') !== secret) throw new Error('invalid_migration_key');
  return bytes;
}

export const migrationDigest = value => createHash('sha256').update(
  typeof value === 'string' ? value : canonicalJSON(value), 'utf8',
).digest('hex');
const canonicalCompare = (left, right) => {
  const a = canonicalJSON(left), b = canonicalJSON(right);
  return a < b ? -1 : a > b ? 1 : 0;
};

export function migrationRecordsDigest(entries) {
  if (!Array.isArray(entries)) throw new Error('invalid_migration_entries');
  return migrationDigest(entries.map(entry => ({ source_id: entry.source_id,
    source_revision: entry.source_revision, source_digest: entry.source_digest }))
    .sort(canonicalCompare));
}

export function migrationOutputsDigest(entries) {
  if (!Array.isArray(entries)) throw new Error('invalid_migration_entries');
  return migrationDigest(entries.map(entry => ({ target_id: entry.target_id,
    target_revision: entry.target_revision, is_tombstone: entry.is_tombstone,
    output_ids: entry.output_ids, output_digest: entry.output_digest }))
    .sort(canonicalCompare));
}

function validBinding(binding) {
  return exact(binding, ['core_instance_id', 'principal_id', 'credential_generation', 'installation_id'])
    && identifier(binding.core_instance_id) && identifier(binding.principal_id)
    && Number.isSafeInteger(binding.credential_generation) && binding.credential_generation >= 1
    && identifier(binding.installation_id);
}

function validSource(source) {
  return exact(source, ['source_kind', 'source_instance_id', 'source_cursor', 'record_count', 'records_digest', 'outputs_digest'])
    && identifier(source.source_kind) && identifier(source.source_instance_id)
    && typeof source.source_cursor === 'string' && source.source_cursor.length <= 4096
    && Number.isSafeInteger(source.record_count) && source.record_count >= 1
    && digest(source.records_digest) && digest(source.outputs_digest);
}

function validEntry(entry) {
  return exact(entry, ['source_id', 'source_revision', 'source_digest', 'target_id', 'target_revision', 'is_tombstone',
    'adopted_op_id', 'receipt_id', 'receipt_auth', 'adoption_binding_digest', 'output_ids', 'output_digest'])
    && identifier(entry.source_id) && Number.isSafeInteger(entry.source_revision) && entry.source_revision >= 1
    && digest(entry.source_digest) && identifier(entry.target_id)
    && Number.isSafeInteger(entry.target_revision) && entry.target_revision >= 1
    && typeof entry.is_tombstone === 'boolean' && identifier(entry.adopted_op_id)
    && identifier(entry.receipt_id) && typeof entry.receipt_auth === 'string' && entry.receipt_auth.length > 0
    && entry.receipt_auth.length <= 4096 && Array.isArray(entry.output_ids) && entry.output_ids.length <= 5000
    && digest(entry.adoption_binding_digest)
    && entry.output_ids.every(identifier) && new Set(entry.output_ids).size === entry.output_ids.length
    && digest(entry.output_digest);
}

function unsignedProof(proof) {
  const { proof_ref: ignored, ...unsigned } = proof;
  return unsigned;
}

export function validateAdoptionProofShape(proof, { now = Date.now, maxLifetimeMs = 24 * 60 * 60 * 1000 } = {}) {
  if (!exact(proof, ['protocol', 'phase', 'migration_id', 'domain', 'binding', 'source', 'prior_proof_digest',
    'details', 'issued_at', 'expires_at', 'proof_ref'])
    || proof.protocol !== 'i-domain-migration-v1' || proof.phase !== 'adopt'
    || !identifier(proof.migration_id) || !identifier(proof.domain) || !validBinding(proof.binding)
    || !validSource(proof.source) || proof.prior_proof_digest !== null
    || !exact(proof.details, ['batch_id', 'mapping_version', 'entries', 'entries_digest', 'pending_ops', 'conflict_count'])
    || !identifier(proof.details.batch_id) || !identifier(proof.details.mapping_version)
    || !Array.isArray(proof.details.entries) || proof.details.entries.length !== proof.source.record_count
    || proof.details.entries.length > 5000
    || !proof.details.entries.length || !proof.details.entries.every(validEntry)
    || proof.details.entries.some(entry => entry.source_id !== entry.target_id
      || entry.source_revision !== entry.target_revision)
    || new Set(proof.details.entries.map(entry => entry.target_id)).size !== proof.details.entries.length
    || new Set(proof.details.entries.map(entry => entry.source_id)).size !== proof.details.entries.length
    || !digest(proof.details.entries_digest)
    || proof.details.entries_digest !== migrationDigest(proof.details.entries)
    || proof.details.pending_ops !== 0 || proof.details.conflict_count !== 0
    || !iso(proof.issued_at) || !iso(proof.expires_at)
    || Date.parse(proof.issued_at) > now()
    || Date.parse(proof.expires_at) <= Date.parse(proof.issued_at)
    || Date.parse(proof.expires_at) - Date.parse(proof.issued_at) > maxLifetimeMs
    || Date.parse(proof.expires_at) <= now()
    || typeof proof.proof_ref !== 'string') return false;
  return true;
}

export function signAdoptionProof(unsigned, { key_id, secret, now = Date.now }) {
  if (!keyId(key_id) || !exact(unsigned, ['protocol', 'phase', 'migration_id', 'domain', 'binding', 'source',
    'prior_proof_digest', 'details', 'issued_at', 'expires_at'])) throw new Error('invalid_migration_proof');
  if (!validateAdoptionProofShape({ ...structuredClone(unsigned), proof_ref: '' }, { now })) {
    throw new Error('invalid_migration_proof');
  }
  const mac = createHmac('sha256', migrationSecretBytes(secret))
    .update(canonicalJSON(unsigned), 'utf8').digest('base64url');
  return { ...structuredClone(unsigned), proof_ref: `mig1.${key_id}.${mac}` };
}

export function verifyAdoptionProof({ proof, key_id, secret, expected = {}, now = Date.now }) {
  try {
    if (!keyId(key_id) || !object(expected) || !validateAdoptionProofShape(proof, { now })) return false;
    if (Object.keys(expected).some(key => !['migration_id', 'domain', 'binding', 'source', 'expires_at'].includes(key))) return false;
    if (Object.entries(expected).some(([key, value]) => canonicalJSON(proof[key]) !== canonicalJSON(value))) return false;
    const match = /^mig1\.([A-Za-z0-9_-]{1,40})\.([A-Za-z0-9_-]{43})$/.exec(proof.proof_ref);
    if (!match || match[1] !== key_id) return false;
    const expectedMac = createHmac('sha256', migrationSecretBytes(secret))
      .update(canonicalJSON(unsignedProof(proof)), 'utf8').digest();
    const supplied = Buffer.from(match[2], 'base64url');
    return supplied.length === expectedMac.length && supplied.toString('base64url') === match[2]
      && timingSafeEqual(supplied, expectedMac);
  } catch {
    return false;
  }
}
