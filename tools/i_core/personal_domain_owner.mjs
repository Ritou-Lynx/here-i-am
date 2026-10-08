// Explicit local owner boundary for personal-domain credentials and migration.
// No HTTP route, pairing hook, environment discovery, or automatic grant exists here.
import { createHmac, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { canonicalJSON, DOMAIN_POLICY } from './domain_store.mjs';
import { createPhoneUiAuthorizationVerifier } from './phone_ui_authorization.mjs';
import {
  migrationDigest,
  migrationOutputsDigest,
  migrationRecordsDigest,
  migrationSecretBytes,
  signAdoptionProof,
  verifyAdoptionProof,
} from './personal_domain_migration.mjs';

export const PHONE_DOMAIN_SCOPES = Object.freeze([
  'captures:read', 'captures:create', 'captures:patch', 'captures:delete', 'captures:ack',
  'captures:adopt', 'captures:owner',
  'plan_items:read', 'plan_items:status', 'plan_items:ack',
  'plan_days:read', 'plan_days:ack', 'plan_weeks:read', 'plan_weeks:ack',
]);
export const DEFAULT_PHONE_DOMAIN_SCOPES = Object.freeze([
  'captures:read', 'captures:create', 'captures:patch', 'captures:delete', 'captures:ack',
  'plan_items:read', 'plan_items:status', 'plan_items:ack',
  'plan_days:read', 'plan_days:ack', 'plan_weeks:read', 'plan_weeks:ack',
]);

const privateRegistries = new WeakMap();
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const exact = (value, required, optional = []) => object(value)
  && required.every(key => Object.hasOwn(value, key))
  && Object.keys(value).every(key => required.includes(key) || optional.includes(key));
const identifier = value => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$/.test(value);
const keyId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,40}$/.test(value);
const hexDigest = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const iso = value => typeof value === 'string' && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value)
  && Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value;
const clone = value => structuredClone(value);
const fail = code => { throw Object.assign(new Error(code), { code }); };

function validateScopes(scopes) {
  if (!Array.isArray(scopes) || !scopes.length || scopes.length > PHONE_DOMAIN_SCOPES.length
    || scopes.some(scope => !PHONE_DOMAIN_SCOPES.includes(scope))
    || new Set(scopes).size !== scopes.length) fail('invalid_phone_access');
}

function validateStringList(values, { allowed = null, maximum = 32 } = {}) {
  return Array.isArray(values) && values.length <= maximum && values.every(identifier)
    && new Set(values).size === values.length && (!allowed || values.every(value => allowed.includes(value)));
}

function validateGrant(grant) {
  if (!exact(grant, ['principal_id', 'credential_generation', 'installation_id', 'device_id', 'key_id', 'secret',
    'scopes', 'domains', 'capture_sources', 'import_sources', 'origin_principals'])
    || !identifier(grant.principal_id) || !identifier(grant.installation_id) || !identifier(grant.device_id)
    || !Number.isSafeInteger(grant.credential_generation) || grant.credential_generation < 1
    || !keyId(grant.key_id) || !validateStringList(grant.domains, { allowed: ['captures', 'plan_items'] })
    || !validateStringList(grant.capture_sources, { allowed: ['phone_quick'] })
    || !validateStringList(grant.import_sources) || !validateStringList(grant.origin_principals)
    || !grant.domains.length) fail('invalid_personal_domain_state');
  validateScopes(grant.scopes);
  try { migrationSecretBytes(grant.secret); } catch { fail('invalid_personal_domain_state'); }
}

function validateManifestEntry(entry) {
  if (!exact(entry, ['source_id', 'source_revision', 'source_digest', 'target_id', 'target_revision', 'is_tombstone',
    'output_ids', 'output_digest', 'record_digest'])
    || !identifier(entry.source_id) || !Number.isSafeInteger(entry.source_revision) || entry.source_revision < 1
    || !hexDigest(entry.source_digest) || !identifier(entry.target_id)
    || !Number.isSafeInteger(entry.target_revision) || entry.target_revision < 1
    || typeof entry.is_tombstone !== 'boolean' || !validateStringList(entry.output_ids, { maximum: 5000 })
    || !hexDigest(entry.output_digest) || !hexDigest(entry.record_digest)) fail('invalid_personal_domain_state');
}

function validateManifest(manifest) {
  if (!exact(manifest, ['migration_id', 'domain', 'binding', 'source', 'batch_id', 'mapping_version', 'issued_at',
    'expires_at', 'key_id', 'entries']) || !identifier(manifest.migration_id) || !identifier(manifest.domain)
    || !exact(manifest.binding, ['core_instance_id', 'principal_id', 'credential_generation', 'installation_id'])
    || !identifier(manifest.binding.core_instance_id) || !identifier(manifest.binding.principal_id)
    || !Number.isSafeInteger(manifest.binding.credential_generation) || manifest.binding.credential_generation < 1
    || !identifier(manifest.binding.installation_id) || !keyId(manifest.key_id)
    || !identifier(manifest.batch_id) || !identifier(manifest.mapping_version)
    || !iso(manifest.issued_at) || !iso(manifest.expires_at)
    || !exact(manifest.source, ['source_kind', 'source_instance_id', 'source_cursor', 'record_count', 'records_digest', 'outputs_digest'])
    || !identifier(manifest.source.source_kind) || !identifier(manifest.source.source_instance_id)
    || typeof manifest.source.source_cursor !== 'string' || manifest.source.source_cursor.length > 4096
    || !Number.isSafeInteger(manifest.source.record_count) || manifest.source.record_count < 1
    || !hexDigest(manifest.source.records_digest) || !hexDigest(manifest.source.outputs_digest)
    || !Array.isArray(manifest.entries) || manifest.entries.length !== manifest.source.record_count
    || manifest.entries.length > 5000
    || !manifest.entries.length) fail('invalid_personal_domain_state');
  manifest.entries.forEach(validateManifestEntry);
  if (new Set(manifest.entries.map(entry => entry.target_id)).size !== manifest.entries.length) fail('invalid_personal_domain_state');
}

function validateState(raw) {
  if (raw === null || raw === undefined) return { version: 1, phone_grants: [], adoption_manifests: [] };
  if (!exact(raw, ['version', 'phone_grants', 'adoption_manifests']) || raw.version !== 1
    || !Array.isArray(raw.phone_grants) || raw.phone_grants.length > 32
    || !Array.isArray(raw.adoption_manifests) || raw.adoption_manifests.length > 128) fail('invalid_personal_domain_state');
  raw.phone_grants.forEach(validateGrant);
  raw.adoption_manifests.forEach(validateManifest);
  for (const key of ['principal_id', 'installation_id', 'key_id']) {
    if (new Set(raw.phone_grants.map(grant => grant[key])).size !== raw.phone_grants.length) fail('invalid_personal_domain_state');
  }
  if (new Set(raw.adoption_manifests.map(manifest => manifest.migration_id)).size !== raw.adoption_manifests.length) {
    fail('invalid_personal_domain_state');
  }
  return clone(raw);
}

function commitState(internal, candidate) {
  const output = validateState(candidate);
  const result = internal.adapter.save(output);
  if (result && typeof result.then === 'function') {
    Promise.resolve(result).catch(() => {});
    fail('invalid_personal_domain_state_adapter');
  }
  internal.state = clone(output);
  for (const principalId of Object.keys(internal.captureSourcesByPrincipal)) delete internal.captureSourcesByPrincipal[principalId];
  for (const grant of internal.state.phone_grants) {
    internal.captureSourcesByPrincipal[grant.principal_id] = [...grant.capture_sources];
  }
}

function bindingForGrant(coreInstanceId, grant) {
  return { core_instance_id: coreInstanceId, principal_id: grant.principal_id,
    credential_generation: grant.credential_generation, installation_id: grant.installation_id };
}

function accessBlock(coreInstanceId, grant, token) {
  return { protocol_version: 1, core_instance_id: coreInstanceId, principal_id: grant.principal_id,
    credential_generation: grant.credential_generation, installation_id: grant.installation_id,
    policy_version: DOMAIN_POLICY.version, schema_version: 1, token, scopes: [...grant.scopes],
    authorization: { scheme: 'hmac-sha256-v1', key_id: grant.key_id, secret: grant.secret } };
}

function manifestMac(manifest, grant) {
  return createHmac('sha256', migrationSecretBytes(grant.secret))
    .update(canonicalJSON({ protocol: 'i-domain-adoption-authorization-v1', manifest }), 'utf8').digest();
}

export function createPersonalDomainAuthorityRegistry({ coreInstanceId, stateAdapter, now = Date.now } = {}) {
  if (!identifier(coreInstanceId) || !object(stateAdapter) || typeof stateAdapter.load !== 'function'
    || typeof stateAdapter.save !== 'function' || typeof now !== 'function') fail('invalid_personal_domain_configuration');
  const loaded = stateAdapter.load();
  if (loaded && typeof loaded.then === 'function') fail('invalid_personal_domain_state_adapter');
  const internal = { coreInstanceId, adapter: stateAdapter, now, state: validateState(loaded), captureSourcesByPrincipal: {} };
  for (const grant of internal.state.phone_grants) internal.captureSourcesByPrincipal[grant.principal_id] = [...grant.capture_sources];

  const authorityRegistry = Object.freeze({
    coreInstanceId,
    captureSourcesForPrincipal(principalId) {
      const sources = internal.captureSourcesByPrincipal[principalId];
      return sources ? [...sources] : null;
    },
    verifyPhoneAuthorization(context) {
      try {
        const grants = internal.state.phone_grants.map(grant => ({ principal_id: grant.principal_id,
          credential_generation: grant.credential_generation, installation_id: grant.installation_id,
          key_id: grant.key_id, secret: grant.secret, domains: grant.domains }));
        return createPhoneUiAuthorizationVerifier({ coreInstanceId, grants })(context);
      } catch { return false; }
    },
    verifyLegacyAdoption(context) {
      try {
        if (!object(context) || typeof context.authorizationRef !== 'string') return false;
        const match = /^ada1\.([A-Za-z0-9_-]{1,40})\.([A-Za-z0-9][A-Za-z0-9_.:-]{0,199})\.([A-Za-z0-9_-]{43})$/.exec(context.authorizationRef);
        if (!match) return false;
        const grant = internal.state.phone_grants.find(item => item.key_id === match[1]);
        const manifest = internal.state.adoption_manifests.find(item => item.migration_id === match[2]);
        if (!grant || !manifest || manifest.key_id !== grant.key_id || Date.parse(manifest.expires_at) <= internal.now()) return false;
        const expectedMac = manifestMac(manifest, grant), supplied = Buffer.from(match[3], 'base64url');
        if (supplied.length !== expectedMac.length || supplied.toString('base64url') !== match[3]
          || !timingSafeEqual(supplied, expectedMac)) return false;
        const binding = bindingForGrant(coreInstanceId, grant);
        if (canonicalJSON(manifest.binding) !== canonicalJSON(binding)
          || context.core_instance_id !== coreInstanceId || context.domain !== manifest.domain
          || context.principal?.principal_id !== binding.principal_id
          || context.principal?.generation !== binding.credential_generation
          || context.principal?.installation_id !== binding.installation_id
          || context.adoption?.sourceKind !== manifest.source.source_kind
          || context.adoption?.batchId !== manifest.batch_id
          || context.adoption?.mappingVersion !== manifest.mapping_version) return false;
        const entry = manifest.entries.find(item => item.target_id === context.record?.id);
        const projectionProof = { manifest_version: 1, manifest_digest: migrationDigest(manifest),
          consumer_binding_digest: migrationDigest(manifest.binding) };
        return !!entry && canonicalJSON(context.adoption?.projectionProof) === canonicalJSON(projectionProof)
          && entry.target_revision === context.record.revision
          && entry.is_tombstone === (context.record.deleted_at !== null)
          && entry.record_digest === migrationDigest(context.record);
      } catch { return false; }
    },
    describe() {
      return { enabled: true, core_instance_id: coreInstanceId, phone_grants: internal.state.phone_grants.length,
        adoption_manifests: internal.state.adoption_manifests.length };
    },
  });
  privateRegistries.set(authorityRegistry, internal);
  return authorityRegistry;
}

export function createPersonalDomainOwner({ domainStore, authorityRegistry } = {}) {
  const internal = privateRegistries.get(authorityRegistry);
  if (!internal || !domainStore || domainStore.nodeId !== internal.coreInstanceId
    || typeof domainStore.configurePrincipal !== 'function') fail('invalid_personal_domain_configuration');

  function grantInput(input, { current = null } = {}) {
    if (!exact(input, ['principalId', 'installationId'], ['deviceId', 'scopes', 'captureSources', 'adoptionSources',
      'adoptionOriginPrincipalIds'])) {
      fail('invalid_phone_access');
    }
    const scopes = input.scopes ?? [...DEFAULT_PHONE_DOMAIN_SCOPES];
    const captureSources = input.captureSources ?? ['phone_quick'];
    const adoptionSources = input.adoptionSources ?? [];
    const adoptionOrigins = input.adoptionOriginPrincipalIds ?? [];
    if (!identifier(input.principalId) || !identifier(input.installationId)
      || !identifier(input.deviceId ?? input.installationId)
      || !validateStringList(captureSources, { allowed: ['phone_quick'] })
      || !validateStringList(adoptionSources) || !validateStringList(adoptionOrigins)) fail('invalid_phone_access');
    validateScopes(scopes);
    if (adoptionSources.length && (!scopes.includes('captures:owner') || !scopes.includes('captures:adopt'))) {
      fail('invalid_phone_access');
    }
    if ((adoptionSources.length === 0) !== (adoptionOrigins.length === 0)) fail('invalid_phone_access');
    if (current && (current.principal_id !== input.principalId || current.installation_id !== input.installationId)) {
      fail('phone_access_binding_mismatch');
    }
    return { scopes: [...scopes], captureSources: [...captureSources], adoptionSources: [...adoptionSources],
      adoptionOrigins: adoptionSources.length ? [...new Set([input.principalId, ...adoptionOrigins])] : [],
      deviceId: input.deviceId ?? input.installationId };
  }

  function persistGrant(grant, previous = null, { removeManifestKey = null } = {}) {
    const next = internal.state.phone_grants.filter(item => item !== previous && item.principal_id !== grant.principal_id);
    next.push(grant);
    commitState(internal, { ...internal.state, phone_grants: next,
      adoption_manifests: removeManifestKey === null ? internal.state.adoption_manifests
        : internal.state.adoption_manifests.filter(item => item.key_id !== removeManifestKey) });
  }

  function manifestAuthority(migrationId) {
    const manifest = internal.state.adoption_manifests.find(item => item.migration_id === migrationId);
    const grant = manifest && internal.state.phone_grants.find(item => item.key_id === manifest.key_id);
    if (!manifest || !grant || Date.parse(manifest.expires_at) <= internal.now()) fail('invalid_adoption_report');
    const principal = domainStore.db.prepare('SELECT * FROM domain_principals WHERE principal_id=?').get(grant.principal_id);
    if (!principal || principal.status !== 'active' || principal.generation !== grant.credential_generation
      || principal.installation_id !== grant.installation_id) fail('adoption_authority_stale');
    return { manifest, grant };
  }

  function projectionProof(manifest) {
    return { manifest_version: 1, manifest_digest: migrationDigest(manifest),
      consumer_binding_digest: migrationDigest(manifest.binding) };
  }

  function authorizationRef(manifest, grant) {
    return `ada1.${grant.key_id}.${manifest.migration_id}.${manifestMac(manifest, grant).toString('base64url')}`;
  }

  function durableAdoptionEntries(manifest, grant) {
    const projection = projectionProof(manifest), entries = [];
    for (const entry of manifest.entries) {
      const opRows = domainStore.db.prepare('SELECT * FROM domain_ops WHERE namespace=? AND principal_id=? AND domain=?')
        .all('production', grant.principal_id, manifest.domain).filter(row => {
          const metadata = JSON.parse(row.op_meta_json);
          return metadata.kind === 'legacy_adopt' && metadata.id === entry.target_id;
        });
      if (opRows.length !== 1) fail('adoption_receipt_not_durable');
      const op = opRows[0], metadata = JSON.parse(op.op_meta_json);
      const expectedAdoption = { sourceKind: manifest.source.source_kind, sourceRecordId: entry.source_id,
        sourceRevision: entry.source_revision, batchId: manifest.batch_id, mappingVersion: manifest.mapping_version,
        isTombstone: entry.is_tombstone, originMappingVerified: true, userCorrectionMappingVerified: false,
        projectionProof: projection };
      const recordAuth = domainStore.mac({ format: 'domain-adoption-record-v1', record_digest: entry.record_digest });
      const bindingDigest = domainStore.mac({ format: 'domain-adoption-binding-v1', domain: manifest.domain,
        record_digest: entry.record_digest, adoption: expectedAdoption });
      if (metadata.outcome !== 'accepted' || metadata.operation_origin !== 'local_adoption'
        || canonicalJSON(metadata.adoption) !== canonicalJSON(expectedAdoption)
        || metadata.adoption_record_auth !== recordAuth
        || metadata.adoption_binding_digest !== bindingDigest) fail('adoption_receipt_not_durable');
      const receiptRows = domainStore.db.prepare('SELECT * FROM domain_receipts WHERE namespace=? AND domain=?').all('production', manifest.domain)
        .filter(row => JSON.parse(row.receipt_json).accepted_op_id === op.op_id);
      if (receiptRows.length !== 1) fail('adoption_receipt_not_durable');
      const receipt = JSON.parse(receiptRows[0].receipt_json);
      if (receiptRows[0].receipt_json !== canonicalJSON(receipt)
        || !exact(receipt, ['receipt_id', 'core_instance_id', 'authority_mode', 'epoch', 'domain', 'accepted_op_id',
          'principal_id', 'accepted_at', 'policy_version', 'targets', 'change_sequences', 'adoption_binding_digest', 'receipt_auth'])
        || receipt.core_instance_id !== internal.coreInstanceId || receipt.domain !== manifest.domain
        || receipt.principal_id !== grant.principal_id || receipt.accepted_op_id !== op.op_id
        || receipt.adoption_binding_digest !== bindingDigest || !Array.isArray(receipt.targets) || receipt.targets.length !== 1
        || receipt.targets[0].id !== entry.target_id || receipt.targets[0].revision !== entry.target_revision) {
        fail('adoption_receipt_not_durable');
      }
      const { receipt_auth: receiptAuth, ...unsignedReceipt } = receipt;
      if (receiptAuth !== domainStore.mac(unsignedReceipt)) fail('adoption_receipt_not_durable');
      const currentRow = domainStore.db.prepare('SELECT envelope_json,body_json FROM domain_records WHERE namespace=? AND domain=? AND id=?')
        .get('production', manifest.domain, entry.target_id);
      if (!currentRow) fail('adoption_target_changed');
      const current = { ...JSON.parse(currentRow.envelope_json), ...(currentRow.body_json ? JSON.parse(currentRow.body_json) : {}) };
      if (current.revision !== entry.target_revision || (current.deleted_at !== null) !== entry.is_tombstone) {
        fail('adoption_target_changed');
      }
      const payload = domainStore.db.prepare('SELECT payload_json FROM domain_op_payloads WHERE namespace=? AND principal_id=? AND domain=? AND op_id=?')
        .get('production', grant.principal_id, manifest.domain, op.op_id);
      if (entry.is_tombstone ? payload !== undefined : !payload || migrationDigest(JSON.parse(payload.payload_json)) !== entry.record_digest) {
        fail('adoption_receipt_not_durable');
      }
      entries.push({ source_id: entry.source_id, source_revision: entry.source_revision, source_digest: entry.source_digest,
        target_id: entry.target_id, target_revision: entry.target_revision, is_tombstone: entry.is_tombstone,
        adopted_op_id: receipt.accepted_op_id, receipt_id: receipt.receipt_id, receipt_auth: receipt.receipt_auth,
        adoption_binding_digest: receipt.adoption_binding_digest,
        output_ids: [...entry.output_ids], output_digest: entry.output_digest });
    }
    return entries;
  }

  return Object.freeze({
    grantPhoneAccess(input) {
      const parsed = grantInput(input);
      if (internal.state.phone_grants.some(grant => grant.principal_id === input.principalId
        || grant.installation_id === input.installationId)
        || domainStore.db.prepare('SELECT 1 FROM domain_principals WHERE principal_id=?').get(input.principalId)) {
        fail('phone_access_already_exists');
      }
      const secret = randomBytes(32).toString('base64url'), newKeyId = `pd_${randomBytes(12).toString('hex')}`;
      const issued = domainStore.configurePrincipal({ principal_id: input.principalId, device_id: parsed.deviceId,
        installation_id: input.installationId, scopes: parsed.scopes,
        actors: parsed.adoptionSources.length ? ['user_direct', 'import'] : ['user_direct'], trusted_interactive: true,
        ...(parsed.adoptionSources.length ? { import_sources: parsed.adoptionSources, origins: parsed.adoptionOrigins }
          : { origin_device_only: true }) });
      const grant = { principal_id: input.principalId, credential_generation: issued.generation,
        installation_id: input.installationId, device_id: parsed.deviceId, key_id: newKeyId, secret,
        scopes: parsed.scopes, domains: ['captures', 'plan_items'], capture_sources: parsed.captureSources,
        import_sources: parsed.adoptionSources, origin_principals: parsed.adoptionOrigins };
      persistGrant(grant);
      return accessBlock(internal.coreInstanceId, grant, issued.token);
    },
    rotatePhoneAccess(input) {
      if (!exact(input, ['principalId', 'installationId'])) fail('invalid_phone_access');
      const previous = internal.state.phone_grants.find(grant => grant.principal_id === input.principalId);
      if (!previous || previous.installation_id !== input.installationId) fail('phone_access_not_found');
      const issued = domainStore.rotatePrincipal(input.principalId);
      const grant = { ...previous, credential_generation: issued.generation,
        key_id: `pd_${randomBytes(12).toString('hex')}`, secret: randomBytes(32).toString('base64url') };
      persistGrant(grant, previous, { removeManifestKey: previous.key_id });
      return accessBlock(internal.coreInstanceId, grant, issued.token);
    },
    revokePhoneAccess(input) {
      if (!exact(input, ['principalId', 'installationId'])) fail('invalid_phone_access');
      const grant = internal.state.phone_grants.find(item => item.principal_id === input.principalId);
      if (!grant || grant.installation_id !== input.installationId) fail('phone_access_not_found');
      domainStore.revokePrincipal(input.principalId);
      commitState(internal, { ...internal.state,
        phone_grants: internal.state.phone_grants.filter(item => item !== grant),
        adoption_manifests: internal.state.adoption_manifests.filter(item => item.key_id !== grant.key_id) });
      return { principal_id: input.principalId, installation_id: input.installationId, revoked: true };
    },
    freezeAdoptionManifest(input) {
      if (!exact(input, ['migration_id', 'domain', 'binding', 'source', 'batch_id', 'mapping_version', 'expires_at', 'entries'])
        || !Array.isArray(input.entries) || !input.entries.length) fail('invalid_adoption_manifest');
      const grant = internal.state.phone_grants.find(item => item.principal_id === input.binding?.principal_id
        && item.credential_generation === input.binding?.credential_generation
        && item.installation_id === input.binding?.installation_id);
      if (!grant || input.binding.core_instance_id !== internal.coreInstanceId
        || !grant.scopes.includes(`${input.domain}:owner`) || !grant.scopes.includes(`${input.domain}:adopt`)
        || !grant.import_sources.includes(input.source?.source_kind)) fail('adoption_not_authorized');
      if (!iso(input.expires_at) || Date.parse(input.expires_at) <= internal.now()
        || Date.parse(input.expires_at) - internal.now() > 24 * 60 * 60 * 1000) fail('invalid_adoption_manifest');
      const entries = input.entries.map(entry => {
        if (!exact(entry, ['source_id', 'source_revision', 'source_digest', 'target_id', 'target_revision',
          'is_tombstone', 'output_ids', 'output_digest', 'record']) || !object(entry.record)
          || entry.source_id !== entry.target_id || entry.source_revision !== entry.target_revision
          || entry.target_id !== entry.record.id || entry.target_revision !== entry.record.revision
          || entry.is_tombstone !== (entry.record.deleted_at !== null)) fail('invalid_adoption_manifest');
        const recordDigest = migrationDigest(entry.record);
        return { source_id: entry.source_id, source_revision: entry.source_revision, source_digest: entry.source_digest,
          target_id: entry.target_id, target_revision: entry.target_revision, is_tombstone: entry.is_tombstone,
          output_ids: [...entry.output_ids], output_digest: entry.output_digest, record_digest: recordDigest };
      });
      const manifest = { migration_id: input.migration_id, domain: input.domain, binding: clone(input.binding),
        source: clone(input.source), batch_id: input.batch_id, mapping_version: input.mapping_version,
        issued_at: new Date(internal.now()).toISOString(), expires_at: input.expires_at, key_id: grant.key_id, entries };
      validateManifest(manifest);
      if (manifest.source.records_digest !== migrationRecordsDigest(entries)
        || manifest.source.outputs_digest !== migrationOutputsDigest(entries)) fail('invalid_adoption_manifest');
      if (internal.state.adoption_manifests.some(item => item.migration_id === manifest.migration_id)) {
        fail('adoption_manifest_exists');
      }
      commitState(internal, { ...internal.state, adoption_manifests: [...internal.state.adoption_manifests, manifest] });
      const mac = manifestMac(manifest, grant).toString('base64url');
      return { migration_id: manifest.migration_id, authorization_ref: `ada1.${grant.key_id}.${manifest.migration_id}.${mac}`,
        manifest_digest: migrationDigest(manifest), expires_at: manifest.expires_at };
    },
    applyAdoptionManifest(input) {
      if (!exact(input, ['migrationId', 'adoptionToken', 'records']) || !identifier(input.migrationId)
        || typeof input.adoptionToken !== 'string' || !Array.isArray(input.records)) fail('invalid_adoption_manifest');
      const { migrationId, adoptionToken, records } = input;
      const { manifest, grant } = manifestAuthority(migrationId);
      if (records.length !== manifest.entries.length) fail('invalid_adoption_manifest');
      const principal = domainStore.authenticate(adoptionToken);
      if (!principal || principal.principal_id !== manifest.binding.principal_id
        || principal.generation !== manifest.binding.credential_generation
        || principal.installation_id !== manifest.binding.installation_id) fail('adoption_authority_stale');
      const byId = new Map(records.map(record => [record?.id, record]));
      if (byId.size !== records.length) fail('invalid_adoption_manifest');
      const common = { authorizationRef: authorizationRef(manifest, grant), sourceKind: manifest.source.source_kind,
        batchId: manifest.batch_id, mappingVersion: manifest.mapping_version, projectionProof: projectionProof(manifest) };
      for (const entry of manifest.entries) {
        const record = byId.get(entry.target_id);
        if (!record || migrationDigest(record) !== entry.record_digest) fail('invalid_adoption_manifest');
        const result = domainStore.adoptLegacyRecord(principal, manifest.domain, record, { ...common, dryRun: true,
          sourceRecordId: entry.source_id, sourceRevision: entry.source_revision });
        if (result.status !== 200 || !['ready', 'duplicate'].includes(result.body.outcome)) fail('adoption_preflight_failed');
      }
      for (const entry of manifest.entries) {
        const record = byId.get(entry.target_id);
        const result = domainStore.adoptLegacyRecord(principal, manifest.domain, record, { ...common, dryRun: false,
          sourceRecordId: entry.source_id, sourceRevision: entry.source_revision });
        if (![200, 201].includes(result.status) || !result.body.receipt) fail('adoption_apply_incomplete');
      }
      return { migration_id: migrationId, adopted_records: manifest.entries.length,
        proof: this.signAdoptionReport({ migrationId }) };
    },
    signAdoptionReport(input) {
      if (!exact(input, ['migrationId']) || !identifier(input.migrationId)) fail('invalid_adoption_report');
      const { migrationId } = input;
      const { manifest, grant } = manifestAuthority(migrationId);
      const entries = durableAdoptionEntries(manifest, grant);
      const unsigned = { protocol: 'i-domain-migration-v1', phase: 'adopt', migration_id: manifest.migration_id,
        domain: manifest.domain, binding: clone(manifest.binding), source: clone(manifest.source), prior_proof_digest: null,
        details: { batch_id: manifest.batch_id, mapping_version: manifest.mapping_version, entries,
          entries_digest: migrationDigest(entries), pending_ops: 0, conflict_count: 0 },
        issued_at: new Date(internal.now()).toISOString(), expires_at: manifest.expires_at };
      return signAdoptionProof(unsigned, { key_id: grant.key_id, secret: grant.secret, now: internal.now });
    },
    verifyAdoptionReport(proof, expected = {}) {
      const match = /^mig1\.([A-Za-z0-9_-]{1,40})\./.exec(proof?.proof_ref ?? '');
      const grant = match && internal.state.phone_grants.find(item => item.key_id === match[1]);
      return !!grant && verifyAdoptionProof({ proof, key_id: grant.key_id, secret: grant.secret,
        expected, now: internal.now });
    },
  });
}
