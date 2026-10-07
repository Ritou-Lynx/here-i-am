import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { DOMAIN_SCHEMA_SQL } from './domain_schema.mjs';
import { ICoreStore } from './i_core_store.mjs';
import { createICoreServer } from './i_core_server.mjs';
import { migrationDigest, migrationOutputsDigest, migrationRecordsDigest } from './personal_domain_migration.mjs';
import { createConfiguredPersonalDomainRuntime } from './personal_domain_runtime.mjs';
import { runPersonalDomainOwnerCommand, writeProtectedOwnerJson } from './personal_domain_owner_cli.mjs';
import { startPersonalDomainServer } from './personal_domain_server.mjs';
import { createWebUserMessageAuthorizationVerifier } from './web_user_message_authorization.mjs';

const now = '2026-10-07T08:00:00.000Z';
const expires = '2026-10-07T20:00:00.000Z';
const phoneScopes = ['captures:read', 'captures:create', 'captures:patch', 'captures:delete', 'captures:ack',
  'captures:adopt', 'captures:owner'];

function fixture(t) {
  const root = mkdtempSync(path.join(tmpdir(), 'personal-domain-runtime-'));
  const databasePath = path.join(root, 'core.sqlite');
  const initial = new ICoreStore(databasePath, { activityEnabled: false, activityAutoActivate: false });
  const coreId = initial.nodeId;
  initial.pairDevice({ device_id: 'phone-install', display_name: 'synthetic phone', platform: 'test',
    client_version: '0.1', capabilities: ['chat'] }, 'fixture-phone-pairing-code');
  initial.close();
  const db = new DatabaseSync(databasePath);
  try {
    db.exec('BEGIN IMMEDIATE'); db.exec(DOMAIN_SCHEMA_SQL);
    db.exec("UPDATE core_metadata SET value='6' WHERE key='schema_version';COMMIT");
  } finally { db.close(); }
  const configPath = path.join(root, 'personal-runtime.json'), statePath = path.join(root, 'owner.dpapi.json');
  writeFileSync(configPath, JSON.stringify({ format: 'i-core-personal-domain-runtime-v1', enabled: true,
    core_instance_id: coreId, private_state_path: statePath,
    domain_modes: { captures: 'authoritative', plan_items: 'off', plan_weeks: 'off', plan_days: 'off' },
    web_user_message_principals: [{ principal_id: 'web-owner', installation_id: 'web-install',
      origin_device_id: 'frontend:claude_web', character_id: 'i' }] }));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  return { root, databasePath, configPath, statePath, coreId };
}

function memoryAdapters() {
  const states = new Map(), locks = new Set();
  return ({ statePath }) => ({ load: () => structuredClone(states.get(statePath) ?? null),
    save: value => states.set(statePath, structuredClone(value)),
    acquireExclusive() {
      if (locks.has(statePath)) throw Object.assign(new Error('personal_domain_private_state_busy'),
        { code: 'personal_domain_private_state_busy' });
      locks.add(statePath); let released = false;
      return () => { if (!released) { released = true; locks.delete(statePath); } };
    } });
}

function runtimeFactory(stateAdapterFactory) {
  return options => createConfiguredPersonalDomainRuntime({ ...options, createServer: createICoreServer,
    stateAdapterFactory, webAuthorizationVerifierFactory: () => () => false,
    clock: () => Date.parse(now) });
}

function save(filePath, value) { writeFileSync(filePath, `${JSON.stringify(value)}\n`); return filePath; }
function outputWriter(outputPath, value) { save(outputPath, value); }

function projectionRef(id) {
  return `captures:legacy-note:${Buffer.from(id, 'utf8').toString('base64').replaceAll('+', '-').replaceAll('/', '_')}`;
}

function migrationInputs(binding) {
  const record = { id: 'legacy-note-1', revision: 3, deleted_at: null,
    origin: { principal_id: 'legacy-web', device_id: 'legacy-web-install' },
    data: { text: 'synthetic legacy body', source: 'claude_web', recorded_at: now,
      organizer: { status: 'pending', outputs: [], input_revision: 3 },
      planner: { status: 'skipped', outputs: [], input_revision: 3, note: 'legacy_i_remember' } },
    provenance: { source: 'i_remember', source_refs: [], import_batch_id: 'batch-owner-cli' } };
  const slots = [{ id: 'card-1', content: '1'.repeat(64), identity: '2'.repeat(64), snapshot: '3'.repeat(64) }];
  const entry = { source_id: record.id, source_revision: record.revision, target_id: record.id,
    target_revision: record.revision, is_tombstone: false, op: 'upsert', source_digest: '4'.repeat(64),
    output_ids: ['card-1'], output_digest: migrationDigest([{ app_projection: 'synthetic' }]), slots, issues: [],
    projection_source_ref: projectionRef(record.id) };
  const source = { source_kind: 'claude_web_note', source_instance_id: 'claude-web-' + '5'.repeat(32),
    source_cursor: '7', record_count: 1, records_digest: migrationRecordsDigest([entry]),
    outputs_digest: migrationOutputsDigest([entry]) };
  const manifest = { protocol: 'i-domain-migration-manifest-v1', migration_id: 'migration-cli-1',
    domain: 'captures', binding, source, records: [entry] };
  return { record, manifest };
}

async function httpJson(url, token) {
  const response = await fetch(url, { headers: { authorization: `Bearer ${token}`,
    'x-i-core-domain-protocol': '1', connection: 'close' } });
  return { status: response.status, body: await response.json() };
}

async function postJson(url, { token, body, headers = {} }) {
  const response = await fetch(url, { method: 'POST', headers: {
    ...(token ? { authorization: `Bearer ${token}` } : {}),
    'content-type': 'application/json', connection: 'close', ...headers,
  }, body: JSON.stringify(body) });
  return { status: response.status, body: await response.json() };
}

test('formal runtime and owner CLI complete explicit Web grant, phone grant, freeze, apply, rotate and revoke', async t => {
  const f = fixture(t), adapters = memoryAdapters(), createRuntime = runtimeFactory(adapters);
  const command = argv => runPersonalDomainOwnerCommand(argv, { createRuntime, writeOutput: outputWriter });
  const webInput = save(path.join(f.root, 'web-input.json'),
    { format: 'i-core-web-access-grant-request-v1', principal_id: 'web-owner' });
  const webOutput = path.join(f.root, 'web-output.json');
  assert.deepEqual(await command(['grant-web', '--config', f.configPath, '--database', f.databasePath,
    '--input', webInput, '--output', webOutput]), { ok: true, command: 'grant-web', output_written: true });
  const webExport = JSON.parse(readFileSync(webOutput));
  assert.equal(webExport.format, 'i-core-web-domain-access-export-v1');
  assert.deepEqual(webExport.web_domain_access.actors, ['agent_inferred', 'user_via_agent']);

  const grantInput = save(path.join(f.root, 'phone-grant.json'), { format: 'i-core-phone-access-grant-request-v1',
    grant: { principal_id: 'phone-owner', scopes: phoneScopes, capture_sources: ['phone_quick'],
      adoption_sources: ['claude_web_note', 'i_remember'],
      adoption_origin_principal_ids: ['legacy-web'] } });
  const installationBinding = save(path.join(f.root, 'phone-installation-binding.json'), {
    format: 'i-core-phone-installation-binding-v1',
    binding: { core_instance_id: f.coreId, installation_id: 'phone-install', device_id: 'phone-install' },
  });
  const accessPath = path.join(f.root, 'phone-access.json');
  await command(['grant-phone', '--config', f.configPath, '--database', f.databasePath,
    '--binding', installationBinding, '--input', grantInput, '--output', accessPath]);
  const accessExport = JSON.parse(readFileSync(accessPath)), access = accessExport.domain_access;
  assert.equal(accessExport.format, 'i-core-domain-access-export-v1');
  assert.notEqual(access.token, access.authorization.secret);
  const binding = { core_instance_id: f.coreId, principal_id: access.principal_id,
    credential_generation: access.credential_generation, installation_id: access.installation_id };
  const migration = migrationInputs(binding);
  const manifestPath = save(path.join(f.root, 'app-manifest.json'),
    { format: 'i-core-capture-migration-manifest-export-v1', manifest: migration.manifest });
  const recordsPath = save(path.join(f.root, 'legacy-records.json'),
    { format: 'i-core-legacy-capture-records-v1', records: [migration.record] });
  const freezePath = path.join(f.root, 'freeze.json');
  await command(['freeze-captures', '--config', f.configPath, '--database', f.databasePath,
    '--app-manifest', manifestPath, '--legacy-records', recordsPath, '--batch-id', 'batch-owner-cli',
    '--expires-at', expires, '--output', freezePath]);
  const frozen = JSON.parse(readFileSync(freezePath));
  assert.deepEqual(Object.keys(frozen.freeze).sort(), ['expires_at', 'manifest_digest', 'migration_id']);
  const beforeApply = new DatabaseSync(f.databasePath);
  assert.equal(beforeApply.prepare('SELECT COUNT(*) n FROM domain_records').get().n, 0);
  assert.equal(beforeApply.prepare('SELECT COUNT(*) n FROM domain_ops').get().n, 0);
  beforeApply.close();
  const proofPath = path.join(f.root, 'proof.json');
  await command(['apply-captures', '--config', f.configPath, '--database', f.databasePath,
    '--domain-access', accessPath, '--legacy-records', recordsPath, '--migration-id', 'migration-cli-1',
    '--output', proofPath]);
  const proofExport = JSON.parse(readFileSync(proofPath)), entry = proofExport.proof.details.entries[0];
  assert.equal(proofExport.format, 'i-core-capture-migration-proof-v1');
  assert.equal(proofExport.proof.binding.principal_id, 'phone-owner');

  let runtime = await createRuntime({ databasePath: f.databasePath, configPath: f.configPath,
    requireWebPrincipals: true });
  let address = await runtime.core.listen({ port: 0 });
  let base = `http://127.0.0.1:${address.port}/v1/core/domains/captures`;
  assert.equal((await httpJson(`${base}/ops/${entry.adopted_op_id}?core_instance_id=${f.coreId}`, access.token)).status, 200);
  assert.equal((await httpJson(`${base}/records/${migration.record.id}?core_instance_id=${f.coreId}`, access.token)).body.record.origin.principal_id,
    'legacy-web');
  await runtime.core.close(); runtime = null;

  const bindingPath = save(path.join(f.root, 'phone-binding.json'), { format: 'i-core-phone-access-binding-v1',
    binding: { core_instance_id: f.coreId, principal_id: 'phone-owner', installation_id: 'phone-install' } });
  const rotatedPath = path.join(f.root, 'phone-rotated.json');
  await command(['rotate-phone', '--config', f.configPath, '--database', f.databasePath,
    '--input', bindingPath, '--output', rotatedPath]);
  const rotated = JSON.parse(readFileSync(rotatedPath)).domain_access;
  runtime = await createRuntime({ databasePath: f.databasePath, configPath: f.configPath, requireWebPrincipals: true });
  address = await runtime.core.listen({ port: 0 }); base = `http://127.0.0.1:${address.port}/v1/core/domains/captures`;
  assert.equal((await httpJson(`${base}/ops/${entry.adopted_op_id}?core_instance_id=${f.coreId}`, access.token)).status, 401);
  assert.equal((await httpJson(`${base}/ops/${entry.adopted_op_id}?core_instance_id=${f.coreId}`, rotated.token)).status, 200);
  await runtime.core.close(); runtime = null;
  const revokedPath = path.join(f.root, 'phone-revoked.json');
  await command(['revoke-phone', '--config', f.configPath, '--database', f.databasePath,
    '--input', bindingPath, '--output', revokedPath]);
  assert.equal(JSON.parse(readFileSync(revokedPath)).revocation.revoked, true);
  runtime = await createRuntime({ databasePath: f.databasePath, configPath: f.configPath, requireWebPrincipals: true });
  address = await runtime.core.listen({ port: 0 }); base = `http://127.0.0.1:${address.port}/v1/core/domains/captures`;
  assert.equal((await httpJson(`${base}/ops/${entry.adopted_op_id}?core_instance_id=${f.coreId}`, rotated.token)).status, 401);
  await runtime.core.close();
});

test('owner export uses a CurrentUser-only staging directory and rejects overwrite', {
  skip: process.platform !== 'win32',
}, t => {
  const root = mkdtempSync(path.join(tmpdir(), 'personal-owner-output-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const output = path.join(root, 'access.json'), payload = { secret: 'SYNTHETIC-TRANSFER-SECRET' };
  writeProtectedOwnerJson(output, payload);
  assert.deepEqual(JSON.parse(readFileSync(output)), payload);
  assert.throws(() => writeProtectedOwnerJson(output, payload), { code: 'protected_owner_output_rejected' });
});

test('formal runtime binds real chat-message authorization and downgrades a missing anchor', async t => {
  const f = fixture(t), adapters = memoryAdapters(), createRuntime = runtimeFactory(adapters);
  const webInput = save(path.join(f.root, 'web-real-input.json'),
    { format: 'i-core-web-access-grant-request-v1', principal_id: 'web-owner' });
  const webOutput = path.join(f.root, 'web-real-output.json');
  await runPersonalDomainOwnerCommand(['grant-web', '--config', f.configPath, '--database', f.databasePath,
    '--input', webInput, '--output', webOutput], { createRuntime, writeOutput: outputWriter });
  const webAccess = JSON.parse(readFileSync(webOutput)).web_domain_access;
  const persisted = new DatabaseSync(f.databasePath);
  const configured = JSON.parse(persisted.prepare('SELECT config_json FROM domain_principals WHERE principal_id=?')
    .get('web-owner').config_json);
  persisted.close();
  assert.equal(configured.origin_device_only, true);

  const runtime = await startPersonalDomainServer({ environment: {
    I_CORE_PERSONAL_DOMAIN_CONFIG: f.configPath, I_CORE_DATABASE: f.databasePath,
    I_CORE_PAIRING_CODE: '739251', I_CORE_PORT: '0',
  }, createRuntime: options => createConfiguredPersonalDomainRuntime({ ...options,
    stateAdapterFactory: adapters, clock: () => Date.parse(now) }), installShutdown: () => {},
  logger: { log() {}, error() {} } });
  try {
    await assert.rejects(createConfiguredPersonalDomainRuntime({ databasePath: f.databasePath,
      configPath: f.configPath, createServer: createICoreServer, stateAdapterFactory: adapters,
      clock: () => Date.parse(now) }), { code: 'personal_domain_private_state_busy' });
    const address = runtime.core.server.address(), base = `http://127.0.0.1:${address.port}`;
    const paired = await postJson(`${base}/v1/core/devices/pair`, { body: {
    device_id: 'frontend:claude_web', display_name: 'synthetic web', platform: 'external-frontend', client_version: '0.1',
    pairing_code: '739251', capabilities: ['chat'],
  } });
  assert.equal(paired.status, 200, JSON.stringify(paired.body));
  const anchor = 'claude_web:t_fixtureThread:1';
  const submitted = await postJson(`${base}/v1/core/chat/messages`, { token: paired.body.device_token,
    headers: { 'x-core-protocol': '0.1' }, body: { device_id: 'frontend:claude_web', messages: [{
      sync_id: anchor, origin_device_id: 'frontend:claude_web', origin_sequence: 1, character_id: 'i',
      sender: 'user', content: 'synthetic user message', created_at_ms: Date.parse(now),
      message_type: 'chat', asset_refs: [], addenda: [],
    }] } });
  assert.equal(submitted.status, 200, JSON.stringify(submitted.body));
  assert.equal(submitted.body.results[0].status, 'accepted');
  const anchorRow = runtime.core.store.db.prepare('SELECT origin_device_id,character_id,sender,message_type FROM chat_messages WHERE sync_id=?')
    .get(anchor);
  assert.equal(anchorRow.origin_device_id, 'frontend:claude_web');
  assert.equal(anchorRow.character_id, 'i');
  assert.equal(anchorRow.sender, 'user');
  assert.equal(anchorRow.message_type, 'chat');
  assert.equal(runtime.core.store.db.prepare("SELECT value FROM core_metadata WHERE key='node_id'").get()?.value, f.coreId);
  const directVerifier = createWebUserMessageAuthorizationVerifier({ coreInstanceId: f.coreId,
    getDatabase: () => runtime.core.store.db, principals: [{ principal_id: 'web-owner',
      installation_id: 'web-install', origin_device_id: 'frontend:claude_web', character_id: 'i' }] });
  assert.equal(directVerifier({ principal: { principal_id: 'web-owner', installation_id: 'web-install',
    device_id: 'frontend:claude_web' }, request: { actor: 'user_via_agent', core_instance_id: f.coreId,
    trigger_thread_id: 't_fixtureThread', trigger_sync_id: anchor },
  domain: 'captures', authorizationRef: anchor }), true);

  const intent = authorizationRef => ({ domain_protocol_version: 1, core_instance_id: f.coreId,
    schema_version: 1, op_id: randomUUID(), id: randomUUID(), kind: 'create', base_revision: 0,
    actor: 'user_via_agent', created_at: now, expires_at: expires,
    data: { text: 'synthetic web capture', source: 'claude_web', recorded_at: now },
    provenance: { source: 'claude_web', source_refs: [], import_batch_id: null },
    ...(authorizationRef ? { authorization_ref: authorizationRef, trigger_thread_id: 't_fixtureThread',
      trigger_sync_id: authorizationRef } : {}) });
  const anchored = await postJson(`${base}/v1/core/domains/captures/ops`, { token: webAccess.token,
    headers: { 'x-i-core-domain-protocol': '1' }, body: intent(anchor) });
  assert.equal(anchored.status, 201, JSON.stringify(anchored.body));
  assert.equal(anchored.body.record.field_meta.text.actor, 'user_via_agent');
  const inferred = await postJson(`${base}/v1/core/domains/captures/ops`, { token: webAccess.token,
    headers: { 'x-i-core-domain-protocol': '1' }, body: intent(null) });
  assert.equal(inferred.status, 201, JSON.stringify(inferred.body));
  assert.equal(inferred.body.record.field_meta.text.actor, 'agent_inferred');
  const later = await postJson(`${base}/v1/core/chat/messages`, { token: paired.body.device_token,
    headers: { 'x-core-protocol': '0.1' }, body: { device_id: 'frontend:claude_web', messages: [{
      sync_id: 'claude_web:t_fixtureThread:2', origin_device_id: 'frontend:claude_web', origin_sequence: 2,
      character_id: 'i', sender: 'user', content: 'synthetic later user message', created_at_ms: Date.parse(now) + 1,
      message_type: 'chat', asset_refs: [], addenda: [],
    }] } });
  assert.equal(later.status, 200, JSON.stringify(later.body));
  const staleAnchor = await postJson(`${base}/v1/core/domains/captures/ops`, { token: webAccess.token,
    headers: { 'x-i-core-domain-protocol': '1' }, body: intent(anchor) });
  assert.equal(staleAnchor.status, 201, JSON.stringify(staleAnchor.body));
  assert.equal(staleAnchor.body.record.field_meta.text.actor, 'agent_inferred');
  } finally {
    runtime.core.server.closeAllConnections?.();
    await runtime.core.close();
  }
});

test('owner export rejects a publish race without deleting the competing file', t => {
  const root = mkdtempSync(path.join(tmpdir(), 'personal-owner-output-race-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const output = path.join(root, 'access.json'), competing = '{"owned_by":"other"}\n';
  const spawnProvider = () => {
    writeFileSync(output, competing);
    return { status: 0, stdout: Buffer.alloc(0), stderr: Buffer.alloc(0) };
  };
  assert.throws(() => writeProtectedOwnerJson(output, { secret: 'MUST-NOT-REPLACE' }, {
    platform: 'win32', powershellPath: process.execPath, spawnProvider,
  }), { code: 'protected_owner_output_rejected' });
  assert.equal(readFileSync(output, 'utf8'), competing);
});

test('personal-domain server requires explicit opt-in and leaves schema 5 unchanged', async t => {
  await assert.rejects(startPersonalDomainServer({ environment: {} }), /I_CORE_PERSONAL_DOMAIN_CONFIG is required/);
  const root = mkdtempSync(path.join(tmpdir(), 'personal-domain-schema5-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const databasePath = path.join(root, 'core.sqlite'), statePath = path.join(root, 'owner.dpapi.json');
  const initial = new ICoreStore(databasePath, { activityEnabled: false, activityAutoActivate: false });
  const coreId = initial.nodeId;
  initial.close();
  const configPath = save(path.join(root, 'personal-runtime.json'), {
    format: 'i-core-personal-domain-runtime-v1', enabled: true, core_instance_id: coreId,
    private_state_path: statePath,
    domain_modes: { captures: 'authoritative', plan_items: 'off', plan_weeks: 'off', plan_days: 'off' },
    web_user_message_principals: [{ principal_id: 'web-owner', installation_id: 'web-install',
      origin_device_id: 'frontend:claude_web', character_id: 'i' }],
  });
  const adapters = memoryAdapters(), start = () => createConfiguredPersonalDomainRuntime({ databasePath,
    configPath, createServer: createICoreServer, stateAdapterFactory: adapters,
    webAuthorizationVerifierFactory: () => () => false, requireWebPrincipals: false });
  await assert.rejects(start(), { code: 'schema_not_ready' });
  await assert.rejects(start(), { code: 'schema_not_ready' });
  const db = new DatabaseSync(databasePath);
  assert.equal(db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get().value, '5');
  assert.equal(db.prepare("SELECT COUNT(*) n FROM sqlite_master WHERE type='table' AND name='domain_records'").get().n, 0);
  db.close();
});

test('formal server entry starts schema 6 with the default Windows DPAPI adapter and closes cleanly', {
  skip: process.platform !== 'win32',
}, async t => {
  const f = fixture(t);
  const webInput = save(path.join(f.root, 'web-dpapi-input.json'),
    { format: 'i-core-web-access-grant-request-v1', principal_id: 'web-owner' });
  const webOutput = path.join(f.root, 'web-dpapi-output.json');
  await runPersonalDomainOwnerCommand(['grant-web', '--config', f.configPath, '--database', f.databasePath,
    '--input', webInput, '--output', webOutput], { writeOutput: outputWriter });
  let runtime;
  try {
    runtime = await startPersonalDomainServer({ environment: {
      I_CORE_PERSONAL_DOMAIN_CONFIG: f.configPath, I_CORE_DATABASE: f.databasePath, I_CORE_PORT: '0',
    }, installShutdown: () => {}, logger: { log() {}, error() {} } });
    const address = runtime.core.server.address();
    const response = await fetch(`http://127.0.0.1:${address.port}/v1/core/health`, {
      headers: { connection: 'close' },
    });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).role, 'authority');
  } finally {
    runtime?.core.server.closeAllConnections?.();
    await runtime?.core.close();
  }
  assert.equal(existsSync(`${f.statePath}.lock`), false);
});

