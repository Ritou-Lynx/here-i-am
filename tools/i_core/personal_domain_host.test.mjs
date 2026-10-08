import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, randomUUID } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { DOMAIN_SCHEMA_SQL, assertDomainSchemaReady } from './domain_schema.mjs';
import { ICoreStore } from './i_core_store.mjs';
import { createICoreServer } from './i_core_server.mjs';
import { signPhoneUiIntent } from './phone_ui_authorization.mjs';
import { createPersonalDomainAuthorityRegistry, createPersonalDomainOwner } from './personal_domain_owner.mjs';
import { createPersonalDomainHost, transitionPersonalDomainMode } from './personal_domain_host.mjs';
import { migrationDigest, migrationOutputsDigest, migrationRecordsDigest, signAdoptionProof,
  verifyAdoptionProof } from './personal_domain_migration.mjs';
import { approveWebActionChallenge, createTrustedWebAuthorizationVerifier,
  createWebActionChallenge } from './web_action_authorization.mjs';

const now = '2026-10-07T08:00:00.000Z';
const expires = '2026-10-07T20:00:00.000Z';
const fullOwnerScopes = ['captures:read', 'captures:create', 'captures:patch', 'captures:delete', 'captures:ack',
  'captures:adopt', 'captures:owner'];

function memoryStateAdapter() {
  let state = null;
  return { load: () => structuredClone(state), save: value => { state = structuredClone(value); },
    inspectForTest: () => structuredClone(state) };
}

function captureIntent(coreId, text = '合成快速记录') {
  return { domain_protocol_version: 1, core_instance_id: coreId, schema_version: 1, op_id: randomUUID(), id: randomUUID(),
    kind: 'create', actor: 'user_direct', base_revision: 0, created_at: now, expires_at: expires,
    data: { text, source: 'phone_quick', recorded_at: now },
    provenance: { source: 'phone_quick', source_refs: [], import_batch_id: null } };
}

function signCapture(access, request) {
  return { ...request, authorization_ref: signPhoneUiIntent({ domain: 'captures', binding: {
    core_instance_id: access.core_instance_id, principal_id: access.principal_id,
    credential_generation: access.credential_generation, installation_id: access.installation_id,
  }, intent: request, keyId: access.authorization.key_id, secret: access.authorization.secret }) };
}

function createSchema6Database() {
  const directory = mkdtempSync(path.join(tmpdir(), 'personal-host-synthetic-'));
  const databasePath = path.join(directory, 'core.sqlite');
  const initial = new ICoreStore(databasePath, { activityEnabled: false, activityAutoActivate: false });
  const coreId = initial.nodeId; initial.close();
  const fixture = new DatabaseSync(databasePath);
  try {
    fixture.exec('BEGIN IMMEDIATE'); fixture.exec(DOMAIN_SCHEMA_SQL);
    fixture.exec("UPDATE core_metadata SET value='6' WHERE key='schema_version';COMMIT");
    assertDomainSchemaReady(fixture);
  } finally { fixture.close(); }
  return { databasePath, coreId, directory };
}

test('host is inert by default and an explicitly configured schema-5 host fails closed', t => {
  assert.deepEqual(createPersonalDomainHost(), { enabled: false, serverOptions: {} });
  assert.throws(() => createPersonalDomainHost({ enabled: true }), { code: 'invalid_personal_domain_configuration' });
  const directory = mkdtempSync(path.join(tmpdir(), 'personal-host-schema5-'));
  const databasePath = path.join(directory, 'core.sqlite');
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  assert.throws(() => new ICoreStore(databasePath, { domainConfigure: () => {} }), error =>
    error.code === 'schema_not_ready' && error.status === 503);
});

test('async web authorization callbacks fail closed and rejected promises are absorbed', async () => {
  const registry = createPersonalDomainAuthorityRegistry({ coreInstanceId: 'async-core', stateAdapter: memoryStateAdapter() });
  const host = createPersonalDomainHost({ enabled: true, mode: 'off', coreInstanceId: 'async-core',
    authorityRegistry: registry, verifyWebAuthorization: () => Promise.reject(new Error('synthetic private failure')) });
  assert.equal(host.serverOptions.domainVerifyAuthorization({ request: { actor: 'user_via_agent' } }), false);
  await new Promise(resolve => setImmediate(resolve));
});

test('mixed domain modes survive restart and a durable frozen mode is never overwritten', async t => {
  const { databasePath, coreId, directory } = createSchema6Database(), stateAdapter = memoryStateAdapter();
  const registry = createPersonalDomainAuthorityRegistry({ coreInstanceId: coreId, stateAdapter });
  const baseModes = { captures: 'authoritative', plan_items: 'off', plan_weeks: 'off', plan_days: 'off' };
  let core = createICoreServer({ databasePath, ...createPersonalDomainHost({ enabled: true, domainModes: baseModes,
    coreInstanceId: coreId, authorityRegistry: registry }).serverOptions });
  assert.deepEqual(Object.fromEntries(core.store.db.prepare('SELECT domain,mode FROM domain_registry').all()
    .map(row => [row.domain, row.mode])), baseModes);
  assert.equal(transitionPersonalDomainMode(core.store.domains,
    { domain: 'captures', expectedMode: 'authoritative', nextMode: 'frozen' }).mode, 'frozen');
  await core.close(); core = null;
  const frozenModes = { ...baseModes, captures: 'frozen' };
  core = createICoreServer({ databasePath, ...createPersonalDomainHost({ enabled: true, domainModes: frozenModes,
    coreInstanceId: coreId, authorityRegistry: registry }).serverOptions });
  assert.equal(core.store.domains.domain('captures').mode, 'frozen');
  await core.close(); core = null;
  assert.throws(() => createICoreServer({ databasePath, ...createPersonalDomainHost({ enabled: true,
    domainModes: baseModes, coreInstanceId: coreId, authorityRegistry: registry }).serverOptions }),
  { code: 'personal_domain_configuration_mismatch' });
  t.after(async () => { if (core) await core.close(); rmSync(directory, { recursive: true, force: true }); });
});

test('explicit host composition registers validated domains and owner rotation revokes old HTTP authority', async t => {
  const { databasePath, coreId, directory } = createSchema6Database(), stateAdapter = memoryStateAdapter();
  const registry = createPersonalDomainAuthorityRegistry({ coreInstanceId: coreId, stateAdapter,
    now: () => Date.parse(now) });
  const host = createPersonalDomainHost({ enabled: true, mode: 'authoritative', coreInstanceId: coreId,
    authorityRegistry: registry });
  let core = createICoreServer({ databasePath, clock: () => Date.parse(now), ...host.serverOptions });
  t.after(async () => { if (core) await core.close(); assert.equal(path.dirname(path.resolve(directory)), path.resolve(tmpdir()));
    assert.ok(path.basename(directory).startsWith('personal-host-synthetic-')); rmSync(directory, { recursive: true, force: true }); });
  assert.equal(core.store.db.prepare('SELECT COUNT(*) n FROM domain_registry').get().n, 4);
  const owner = createPersonalDomainOwner({ domainStore: core.store.domains, authorityRegistry: registry });
  const existing = core.store.domains.configurePrincipal({ principal_id: 'existing-processor', device_id: 'processor-device',
    installation_id: 'processor-install', scopes: ['captures:read'], actors: ['agent_inferred'], processor: 'organizer' });
  const existingBefore = core.store.db.prepare('SELECT * FROM domain_principals WHERE principal_id=?').get('existing-processor');
  assert.throws(() => owner.grantPhoneAccess({ principalId: 'existing-processor', installationId: 'phone-collision' }),
    { code: 'phone_access_already_exists' });
  assert.deepEqual(core.store.db.prepare('SELECT * FROM domain_principals WHERE principal_id=?').get('existing-processor'),
    existingBefore);
  assert.equal(core.store.domains.authenticate(existing.token).generation, existing.generation);
  const first = owner.grantPhoneAccess({ principalId: 'phone-owner', installationId: 'phone-install' });
  assert.equal(first.authorization.secret.length, 43); assert.notEqual(first.token, first.authorization.secret);
  assert.deepEqual(Object.keys(first).sort(), ['authorization', 'core_instance_id', 'credential_generation', 'installation_id',
    'policy_version', 'principal_id', 'protocol_version', 'schema_version', 'scopes', 'token'].sort());
  const address = await core.listen({ port: 0 }); const origin = `http://127.0.0.1:${address.port}`;
  const send = async (access, body) => { const response = await fetch(`${origin}/v1/core/domains/captures/ops`, {
    method: 'POST', headers: { authorization: `Bearer ${access.token}`, 'content-type': 'application/json',
      'x-i-core-domain-protocol': '1', connection: 'close' }, body: JSON.stringify(body) });
  return { status: response.status, body: await response.json() }; };
  assert.equal((await send(first, signCapture(first, captureIntent(coreId, 'first')))).status, 201);
  const second = owner.rotatePhoneAccess({ principalId: first.principal_id, installationId: first.installation_id });
  assert.equal(second.credential_generation, first.credential_generation + 1);
  assert.notEqual(second.token, first.token); assert.notEqual(second.authorization.secret, first.authorization.secret);
  assert.equal((await send(first, signCapture(first, captureIntent(coreId, 'old-token')))).status, 401);
  const staleSignature = signCapture(first, captureIntent(coreId, 'old-key'));
  assert.equal((await send(second, staleSignature)).status, 403);
  assert.equal((await send(second, signCapture(second, captureIntent(coreId, 'new-key')))).status, 201);
  assert.deepEqual(owner.revokePhoneAccess({ principalId: second.principal_id, installationId: second.installation_id }),
    { principal_id: second.principal_id, installation_id: second.installation_id, revoked: true });
  assert.equal((await send(second, signCapture(second, captureIntent(coreId, 'revoked')))).status, 401);
  const serializedDatabase = JSON.stringify(core.store.db.prepare('SELECT * FROM domain_principals').all());
  assert.equal(serializedDatabase.includes(first.authorization.secret), false);
  assert.equal(serializedDatabase.includes(second.authorization.secret), false);
});

test('web actions are denied by default and accepted only through the injected Ed25519 verifier', async t => {
  const { databasePath, coreId, directory } = createSchema6Database(), stateAdapter = memoryStateAdapter();
  const registry = createPersonalDomainAuthorityRegistry({ coreInstanceId: coreId, stateAdapter });
  const base = { enabled: true, mode: 'authoritative', coreInstanceId: coreId, authorityRegistry: registry,
    captureSourcesByPrincipal: { web: ['claude_web'] } };
  let core = createICoreServer({ databasePath, clock: () => Date.parse(now),
    ...createPersonalDomainHost(base).serverOptions });
  const issued = core.store.domains.configurePrincipal({ principal_id: 'web', device_id: 'web-device',
    installation_id: 'web-install', scopes: ['captures:read', 'captures:create'], actors: ['user_via_agent'] });
  const binding = { core_instance_id: coreId, principal_id: 'web', credential_generation: issued.generation,
    installation_id: 'web-install' };
  const keys = generateKeyPairSync('ed25519'), request = { ...captureIntent(coreId, 'trusted web'),
    actor: 'user_via_agent', data: { text: 'trusted web', source: 'claude_web', recorded_at: now },
    provenance: { source: 'claude_web', source_refs: [], import_batch_id: null } };
  const challenge = createWebActionChallenge({ domain: 'captures', binding, request, keyId: 'trusted-ui',
    now: Date.parse(now) });
  const signed = { ...request, authorization_ref: approveWebActionChallenge({ challenge, domain: 'captures', binding,
    request, privateKey: keys.privateKey, now: Date.parse(now) }) };
  const send = async (origin) => { const response = await fetch(`${origin}/v1/core/domains/captures/ops`, { method: 'POST',
    headers: { authorization: `Bearer ${issued.token}`, 'content-type': 'application/json', connection: 'close' },
    body: JSON.stringify(signed) }); return response.status; };
  let address = await core.listen({ port: 0 });
  assert.equal(await send(`http://127.0.0.1:${address.port}`), 403);
  await core.close(); core = null;
  const verifier = createTrustedWebAuthorizationVerifier({ coreInstanceId: coreId, now: () => Date.parse(now),
    getTrustedKeys: () => [{ key_id: 'trusted-ui', public_key: keys.publicKey, binding, kinds: ['create'] }] });
  core = createICoreServer({ databasePath, clock: () => Date.parse(now),
    ...createPersonalDomainHost({ ...base, verifyWebAuthorization: verifier }).serverOptions });
  address = await core.listen({ port: 0 });
  assert.equal(await send(`http://127.0.0.1:${address.port}`), 201);
  t.after(async () => { if (core) await core.close(); rmSync(directory, { recursive: true, force: true }); });
});

test('private frozen manifest binds every adopted record and signs one complete receipt report', async t => {
  const { databasePath, coreId, directory } = createSchema6Database(), stateAdapter = memoryStateAdapter();
  const registry = createPersonalDomainAuthorityRegistry({ coreInstanceId: coreId, stateAdapter,
    now: () => Date.parse(now) });
  const host = createPersonalDomainHost({ enabled: true, mode: 'authoritative', coreInstanceId: coreId,
    authorityRegistry: registry });
  const core = createICoreServer({ databasePath, clock: () => Date.parse(now), ...host.serverOptions });
  t.after(async () => { await core.close(); rmSync(directory, { recursive: true, force: true }); });
  const owner = createPersonalDomainOwner({ domainStore: core.store.domains, authorityRegistry: registry });
  const access = owner.grantPhoneAccess({ principalId: 'migration-owner', installationId: 'migration-install',
    scopes: fullOwnerScopes, adoptionSources: ['claude_web_note', 'i_remember'],
    adoptionOriginPrincipalIds: ['legacy-web'] });
  const binding = { core_instance_id: coreId, principal_id: access.principal_id,
    credential_generation: access.credential_generation, installation_id: access.installation_id };
  const record = { id: 'legacy-capture-1', revision: 3, deleted_at: null,
    origin: { principal_id: 'legacy-web', device_id: 'legacy-web-install' },
    data: { text: 'legacy synthetic text', source: 'claude_web', recorded_at: now,
      organizer: { status: 'pending', outputs: [], input_revision: 3 },
      planner: { status: 'skipped', outputs: [], input_revision: 3, note: 'legacy_i_remember' } },
    provenance: { source: 'i_remember', source_refs: [], import_batch_id: 'batch-legacy-1' } };
  const manifestEntry = { source_id: record.id, source_revision: 3, source_digest: migrationDigest('legacy-source-bytes'),
    target_id: record.id, target_revision: record.revision, is_tombstone: false, output_ids: [],
    output_digest: migrationDigest('app-local-output-projection'), record };
  const source = { source_kind: 'claude_web_note', source_instance_id: 'legacy-db-synthetic', source_cursor: 'cursor-7',
    record_count: 1, records_digest: migrationRecordsDigest([manifestEntry]),
    outputs_digest: migrationOutputsDigest([manifestEntry]) };
  const frozen = owner.freezeAdoptionManifest({ migration_id: 'migration-1', domain: 'captures', binding, source,
    batch_id: 'batch-legacy-1', mapping_version: 'personal-import-v1', expires_at: expires, entries: [manifestEntry] });
  assert.throws(() => owner.applyAdoptionManifest({ migrationId: 'migration-1', adoptionToken: access.token,
    records: [{ ...record, data: { ...record.data, text: 'tampered' } }] }), { code: 'invalid_adoption_manifest' });
  const applied = owner.applyAdoptionManifest({ migrationId: 'migration-1', adoptionToken: access.token, records: [record] });
  assert.equal(applied.adopted_records, 1);
  const proof = applied.proof;
  assert.equal(owner.verifyAdoptionReport(proof, { migration_id: 'migration-1', domain: 'captures', binding, source,
    expires_at: expires }), true);
  assert.equal(owner.verifyAdoptionReport({ ...proof, details: { ...proof.details,
    entries: [{ ...proof.details.entries[0], output_digest: migrationDigest('tampered') }] } }), false);
  const address = await core.listen({ port: 0 });
  const refetched = await fetch(`http://127.0.0.1:${address.port}/v1/core/domains/captures/ops/${proof.details.entries[0].adopted_op_id}?core_instance_id=${coreId}`, {
    headers: { authorization: `Bearer ${access.token}`, 'x-i-core-domain-protocol': '1', connection: 'close' } });
  const currentClaim = await refetched.json();
  assert.equal(refetched.status, 200, JSON.stringify(currentClaim));
  assert.equal(currentClaim.result.receipt.principal_id, access.principal_id);
  assert.equal(currentClaim.result.receipt.adoption_binding_digest,
    proof.details.entries[0].adoption_binding_digest);
  assert.equal(JSON.stringify(stateAdapter.inspectForTest()).includes(record.data.text), false);
  assert.equal(JSON.stringify(core.store.db.prepare('SELECT * FROM domain_ops').all()).includes(access.authorization.secret), false);
  const stored = core.store.db.prepare("SELECT envelope_json FROM domain_records WHERE namespace='production' AND domain='captures' AND id=?")
    .get(record.id);
  assert.equal(JSON.parse(stored.envelope_json).origin.principal_id, 'legacy-web');
  assert.equal(JSON.parse(stored.envelope_json).origin.device_id, 'legacy-web-install');
  assert.throws(() => owner.signAdoptionReport({ migrationId: 'migration-1', receipts: [{ receipt_id: 'forged' }] }),
    { code: 'invalid_adoption_report' });
  const durableReceipt = core.store.db.prepare("SELECT * FROM domain_receipts WHERE namespace='production' AND domain='captures'").get();
  const forgedReceipt = { ...JSON.parse(durableReceipt.receipt_json), receipt_id: 'forged-receipt' };
  core.store.db.prepare('INSERT INTO domain_receipts(receipt_id,namespace,domain,receipt_json) VALUES(?,?,?,?)')
    .run(forgedReceipt.receipt_id, 'production', 'captures', JSON.stringify(forgedReceipt));
  assert.throws(() => owner.signAdoptionReport({ migrationId: 'migration-1' }), { code: 'adoption_receipt_not_durable' });
  core.store.db.prepare('DELETE FROM domain_receipts WHERE receipt_id=?').run(forgedReceipt.receipt_id);
  const durableOp = core.store.db.prepare("SELECT op_id,op_meta_json FROM domain_ops WHERE namespace='production' AND domain='captures'").get();
  const nonAdoptionMeta = { ...JSON.parse(durableOp.op_meta_json), kind: 'create' };
  core.store.db.prepare('UPDATE domain_ops SET op_meta_json=? WHERE op_id=?').run(JSON.stringify(nonAdoptionMeta), durableOp.op_id);
  assert.throws(() => owner.signAdoptionReport({ migrationId: 'migration-1' }), { code: 'adoption_receipt_not_durable' });
  core.store.db.prepare('UPDATE domain_ops SET op_meta_json=? WHERE op_id=?').run(durableOp.op_meta_json, durableOp.op_id);
  const current = core.store.db.prepare("SELECT envelope_json FROM domain_records WHERE namespace='production' AND domain='captures' AND id=?")
    .get(record.id), changedEnvelope = { ...JSON.parse(current.envelope_json), revision: record.revision + 1 };
  core.store.db.prepare("UPDATE domain_records SET revision=?,envelope_json=? WHERE namespace='production' AND domain='captures' AND id=?")
    .run(changedEnvelope.revision, JSON.stringify(changedEnvelope), record.id);
  assert.throws(() => owner.signAdoptionReport({ migrationId: 'migration-1' }), { code: 'adoption_target_changed' });
  core.store.db.prepare("UPDATE domain_records SET revision=?,envelope_json=? WHERE namespace='production' AND domain='captures' AND id=?")
    .run(record.revision, current.envelope_json, record.id);
  assert.equal(owner.verifyAdoptionReport(owner.signAdoptionReport({ migrationId: 'migration-1' })), true);
  const rotatedOwner = owner.rotatePhoneAccess({ principalId: access.principal_id, installationId: access.installation_id });
  assert.equal(rotatedOwner.credential_generation, access.credential_generation + 1);
  assert.equal(owner.verifyAdoptionReport(proof), false);
});

test('migration proof has a fixed cross-language vector and rejects future or widened shapes', () => {
  const secret = Buffer.from(Array.from({ length: 32 }, (_, index) => index)).toString('base64url');
  const entry = { source_id: 'legacy-1', source_revision: 2, source_digest: '1'.repeat(64), target_id: 'legacy-1',
    target_revision: 2, is_tombstone: false, adopted_op_id: '00000000-0000-4000-8000-000000000001',
    receipt_id: 'receipt-1', receipt_auth: 'receipt-auth-synthetic', adoption_binding_digest: '5'.repeat(64),
    output_ids: [], output_digest: '2'.repeat(64) };
  const unsigned = { protocol: 'i-domain-migration-v1', phase: 'adopt', migration_id: 'migration-fixed', domain: 'captures',
    binding: { core_instance_id: 'core-fixed', principal_id: 'owner-fixed', credential_generation: 4,
      installation_id: 'install-fixed' }, source: { source_kind: 'i_remember', source_instance_id: 'legacy-fixed',
      source_cursor: 'cursor-fixed', record_count: 1, records_digest: '3'.repeat(64), outputs_digest: '4'.repeat(64) },
    prior_proof_digest: null, details: { batch_id: 'batch-fixed', mapping_version: 'mapping-fixed', entries: [entry],
      entries_digest: migrationDigest([entry]), pending_ops: 0, conflict_count: 0 },
    issued_at: now, expires_at: expires };
  const proof = signAdoptionProof(unsigned, { key_id: 'migration-key', secret, now: () => Date.parse(now) });
  assert.equal(proof.proof_ref, 'mig1.migration-key.YhV99dnM_8fcB6CvjdGqX2cY0Dy8hlg_i9vV1zXUy_M');
  assert.equal(verifyAdoptionProof({ proof, key_id: 'migration-key', secret, now: () => Date.parse(now) }), true);
  assert.equal(verifyAdoptionProof({ proof: { ...proof, extra: true }, key_id: 'migration-key', secret,
    now: () => Date.parse(now) }), false);
  assert.throws(() => signAdoptionProof({ ...unsigned, issued_at: expires },
    { key_id: 'migration-key', secret, now: () => Date.parse(now) }), /invalid_migration_proof/);
});
