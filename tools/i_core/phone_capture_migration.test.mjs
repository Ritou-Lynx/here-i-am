import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { DOMAIN_SCHEMA_SQL } from './domain_schema.mjs';
import { ICoreStore } from './i_core_store.mjs';
import { createICoreServer } from './i_core_server.mjs';
import { createPersonalDomainHost } from './personal_domain_host.mjs';
import { createPersonalDomainAuthorityRegistry, createPersonalDomainOwner } from './personal_domain_owner.mjs';
import { migrationDigest, migrationOutputsDigest, migrationRecordsDigest } from './personal_domain_migration.mjs';
import { applyPhoneCaptureMigration, freezePhoneCaptureMigration,
  PHONE_CAPTURE_MAPPING_VERSION } from './phone_capture_migration.mjs';

const now = '2026-10-07T08:00:00.000Z';
const expires = '2026-10-07T20:00:00.000Z';
const ownerScopes = ['captures:read', 'captures:create', 'captures:patch', 'captures:delete', 'captures:ack',
  'captures:adopt', 'captures:owner'];
const clone = value => structuredClone(value);

function memoryStateAdapter() {
  let state = null;
  return { load: () => clone(state), save: value => { state = clone(value); } };
}

function schema6Database() {
  const directory = mkdtempSync(path.join(tmpdir(), 'phone-capture-migration-'));
  const databasePath = path.join(directory, 'core.sqlite');
  const initial = new ICoreStore(databasePath, { activityEnabled: false, activityAutoActivate: false });
  const coreId = initial.nodeId; initial.close();
  const db = new DatabaseSync(databasePath);
  try {
    db.exec('BEGIN IMMEDIATE'); db.exec(DOMAIN_SCHEMA_SQL);
    db.exec("UPDATE core_metadata SET value='6' WHERE key='schema_version';COMMIT");
  } finally { db.close(); }
  return { directory, databasePath, coreId };
}

function projectionRef(id) {
  const encoded = Buffer.from(id, 'utf8').toString('base64').replaceAll('+', '-').replaceAll('/', '_');
  return `captures:legacy-note:${encoded}`;
}

function appManifest(binding) {
  // The App preserves receipt card_ids in source_digest, but exposes sorted
  // output_ids. The adapter must not pretend it can reconstruct the first list.
  const slots = [
    { id: 'card-b', content: '1'.repeat(64), identity: '2'.repeat(64), snapshot: '3'.repeat(64) },
    { id: 'card-a', content: '4'.repeat(64), identity: '5'.repeat(64), snapshot: '6'.repeat(64) },
  ];
  const record = { source_id: 'legacy-note-1', source_revision: 3, target_id: 'legacy-note-1', target_revision: 3,
    is_tombstone: false, op: 'upsert', output_ids: ['card-a', 'card-b'],
    output_digest: migrationDigest([{ app_local_projection: 'different-from-core-record' }]), slots, issues: [],
    projection_source_ref: projectionRef('legacy-note-1') };
  record.source_digest = migrationDigest({ note_id: record.source_id, revision: record.source_revision, op: record.op,
    card_ids: ['card-b', 'card-a'], slots: record.slots, issues: record.issues,
    projection_source_ref: record.projection_source_ref });
  const source = { source_kind: 'claude_web_note', source_instance_id: 'app-db-synthetic', source_cursor: '7',
    record_count: 1, records_digest: migrationRecordsDigest([record]), outputs_digest: migrationOutputsDigest([record]) };
  return { protocol: 'i-domain-migration-manifest-v1', migration_id: 'migration-phone-1', domain: 'captures',
    binding: clone(binding), source, records: [record] };
}

function legacyRecord() {
  return { id: 'legacy-note-1', revision: 3, deleted_at: null,
    origin: { principal_id: 'legacy-web', device_id: 'legacy-web-install' },
    data: { text: 'synthetic legacy text', source: 'claude_web', recorded_at: now,
      organizer: { status: 'pending', outputs: [], input_revision: 3 },
      planner: { status: 'skipped', outputs: [], input_revision: 3, note: 'legacy_i_remember' } },
    provenance: { source: 'i_remember', source_refs: [], import_batch_id: 'batch-phone-1' } };
}

test('App frozen projection joins exact legacy records then adopts with the same phone principal', async t => {
  const { directory, databasePath, coreId } = schema6Database(), stateAdapter = memoryStateAdapter();
  const registry = createPersonalDomainAuthorityRegistry({ coreInstanceId: coreId, stateAdapter,
    now: () => Date.parse(now) });
  const host = createPersonalDomainHost({ enabled: true, mode: 'authoritative', coreInstanceId: coreId,
    authorityRegistry: registry });
  const core = createICoreServer({ databasePath, clock: () => Date.parse(now), ...host.serverOptions });
  t.after(async () => { await core.close(); rmSync(directory, { recursive: true, force: true }); });
  const owner = createPersonalDomainOwner({ domainStore: core.store.domains, authorityRegistry: registry });
  const access = owner.grantPhoneAccess({ principalId: 'phone-owner', installationId: 'phone-install',
    scopes: ownerScopes, adoptionSources: ['claude_web_note', 'i_remember'],
    adoptionOriginPrincipalIds: ['legacy-web'] });
  const binding = { core_instance_id: coreId, principal_id: access.principal_id,
    credential_generation: access.credential_generation, installation_id: access.installation_id };
  const manifest = appManifest(binding), record = legacyRecord();

  assert.throws(() => freezePhoneCaptureMigration({ owner, appManifest: manifest,
    legacyRecords: [{ ...record, id: 'other-note' }], batchId: 'batch-phone-1',
    mappingVersion: PHONE_CAPTURE_MAPPING_VERSION, expiresAt: expires }), { code: 'invalid_phone_capture_migration' });
  assert.throws(() => freezePhoneCaptureMigration({ owner, appManifest: manifest,
    legacyRecords: [{ ...record, revision: 4 }], batchId: 'batch-phone-1',
    mappingVersion: PHONE_CAPTURE_MAPPING_VERSION, expiresAt: expires }), { code: 'invalid_phone_capture_migration' });
  assert.throws(() => freezePhoneCaptureMigration({ owner, appManifest: manifest, legacyRecords: [record],
    batchId: 'batch-phone-1', mappingVersion: 'wrong-mapping', expiresAt: expires }),
  { code: 'invalid_phone_capture_migration' });
  const badSummary = clone(manifest); badSummary.source.outputs_digest = '0'.repeat(64);
  assert.throws(() => freezePhoneCaptureMigration({ owner, appManifest: badSummary, legacyRecords: [record],
    batchId: 'batch-phone-1', mappingVersion: PHONE_CAPTURE_MAPPING_VERSION, expiresAt: expires }),
  { code: 'invalid_phone_capture_migration' });

  const frozen = freezePhoneCaptureMigration({ owner, appManifest: manifest, legacyRecords: [record],
    batchId: 'batch-phone-1', mappingVersion: PHONE_CAPTURE_MAPPING_VERSION, expiresAt: expires });
  assert.equal(frozen.migration_id, manifest.migration_id);
  assert.equal(core.store.db.prepare('SELECT COUNT(*) n FROM domain_records').get().n, 0);
  assert.equal(core.store.db.prepare('SELECT COUNT(*) n FROM domain_ops').get().n, 0);
  const applied = applyPhoneCaptureMigration({ owner, migrationId: manifest.migration_id,
    adoptionToken: access.token, legacyRecords: [record] });
  const entry = applied.proof.details.entries[0];
  assert.equal(entry.output_digest, manifest.records[0].output_digest);
  assert.notEqual(entry.output_digest, migrationDigest(record));
  assert.equal(applied.proof.source.source_kind, 'claude_web_note');
  assert.equal(applied.proof.binding.principal_id, access.principal_id);

  const address = await core.listen({ port: 0 });
  const headers = { authorization: `Bearer ${access.token}`, 'x-i-core-domain-protocol': '1', connection: 'close' };
  const operationResponse = await fetch(`http://127.0.0.1:${address.port}/v1/core/domains/captures/ops/${entry.adopted_op_id}?core_instance_id=${coreId}`, { headers });
  const operation = await operationResponse.json();
  assert.equal(operationResponse.status, 200, JSON.stringify(operation));
  assert.equal(operation.result.receipt.principal_id, access.principal_id);
  assert.equal(operation.result.receipt.receipt_auth, entry.receipt_auth);
  assert.equal(operation.result.receipt.adoption_binding_digest, entry.adoption_binding_digest);
  const currentResponse = await fetch(`http://127.0.0.1:${address.port}/v1/core/domains/captures/records/${record.id}?core_instance_id=${coreId}`, { headers });
  const current = await currentResponse.json();
  assert.equal(currentResponse.status, 200, JSON.stringify(current));
  assert.equal(current.record.revision, record.revision);
  assert.equal(current.record.origin.principal_id, 'legacy-web');
  assert.equal(current.record.provenance.source, 'i_remember');
});

