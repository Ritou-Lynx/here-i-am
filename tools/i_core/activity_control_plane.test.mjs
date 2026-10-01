import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { EventEmitter } from 'node:events';
import {
  copyFileSync,
  existsSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { request as httpRequest } from 'node:http';
import { createServer as createNetServer } from 'node:net';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { backup, DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import {
  ACTIVITY_CONTRACT,
  ACTIVITY_KINDS,
  ACTIVITY_RAW_RETENTION_MS,
  ACTIVITY_STATUS_REASONS,
  ACTIVITY_SCHEMA_V1_CHECKSUM,
  ACTIVITY_SCHEMA_V2_CHECKSUM,
  ACTIVITY_SCHEMA_V3_CHECKSUM,
  ACTIVITY_SCHEMA_V4_CHECKSUM,
  ActivityControlPlane,
  activityRecoveryManifestForDatabase,
  activitySchemaStatus,
  canonicalActivityDigest,
  migrateActivitySchema,
  normalizeActivityEvent,
} from './activity_control_plane.mjs';
import { ICoreStore, verifyActivityRecoveryCandidate } from './i_core_store.mjs';
import { createICoreServer, installICoreGracefulShutdown } from './i_core_server.mjs';

const OWNER_SECRET = 'synthetic-owner-secret-123456';
const TEST_DATABASE_BINDING = 'b'.repeat(64);
const SUMMARY_FIXTURE = JSON.parse(readFileSync(
  new URL('./activity_summary_v1.fixture.json', import.meta.url),
  'utf8',
));
const MDA0_LIMITS_FIXTURE = JSON.parse(readFileSync(
  new URL('../../docs/development/activity/mda0/fixtures/limits_and_atomicity.json', import.meta.url),
  'utf8',
));
const EVENT_PREFIXES = new Map();

function eventPrefixKey(deviceId, probeId) {
  return `${deviceId}\u0000${probeId}`;
}

function tempDir(name) {
  return mkdtempSync(path.join(tmpdir(), `${name}-`));
}

function event({
  wireEventId = undefined,
  deviceId = 'device-a',
  probeId = 'probe-a',
  originSequence = 1,
  kind = 'session.unlocked',
  signalAt = 1_000_000,
  ttl = 300_000,
  confidence = 'high',
  source = 'windows_wts',
  coverageMode = 'continuous',
  coverageStart = signalAt - 30_000,
  coverageEnd = signalAt,
  coverageInterval = 30_000,
  payload = {},
} = {}) {
  const prefix = EVENT_PREFIXES.get(eventPrefixKey(deviceId, probeId)) ?? 'A'.repeat(22);
  return {
    contract: ACTIVITY_CONTRACT,
    schema_version: 1,
    event_id: wireEventId ?? `${prefix}.${originSequence}`,
    device_id: deviceId,
    probe_id: probeId,
    origin_sequence: originSequence,
    kind,
    signal_at_ms: signalAt,
    ttl_ms: ttl,
    confidence,
    source,
    coverage: {
      mode: coverageMode,
      window_start_ms: coverageStart,
      window_end_ms: coverageEnd,
      expected_report_interval_ms: coverageInterval,
    },
    payload,
  };
}

function pairProbe(store, {
  deviceId = 'device-a',
  probeId = 'probe-a',
  source = 'windows_wts',
  coverageMode = 'continuous',
  allowedKinds = ACTIVITY_KINDS,
  capabilities = [
    'activity.write', 'activity.read_summary', 'activity.admin', 'chat.read',
    'usage_events', 'probe_error.collection_failed',
  ],
  expectedReportInterval = 30_000,
  expirySlo = 300_000,
  now = store.activity.clock(),
} = {}) {
  const paired = store.activity.pairProbe({
    device_id: deviceId,
    probe_id: probeId,
    display_name: probeId,
    capabilities,
    source,
    coverage_mode: coverageMode,
    expected_report_interval_ms: expectedReportInterval,
    expiry_slo_ms: expirySlo,
    allowed_kinds: allowedKinds,
  }, now);
  EVENT_PREFIXES.set(eventPrefixKey(deviceId, probeId), paired.event_id_prefix);
  return paired;
}

function pairReader(store, installationId = 'reader-a', now = store.activity.clock()) {
  return store.activity.pairSummaryReader({
    installation_id: installationId,
    display_name: installationId,
    capabilities: ['activity.admin', 'chat.read'],
  }, now);
}

function openStore(directory, nowRef = { value: 1_000_000 }) {
  return new ICoreStore(path.join(directory, 'core.sqlite'), { clock: () => nowRef.value, activityEnabled: true });
}

function downgradeToActivitySchemaFour(databasePath) {
  const legacy = new DatabaseSync(databasePath);
  legacy.exec(`
    DROP TABLE activity_replay_lineage_floors;
    DROP INDEX activity_principals_event_prefix_idx;
    ALTER TABLE activity_principals DROP COLUMN event_id_prefix;
    ALTER TABLE activity_principals DROP COLUMN retired_event_prefix_digest;
    ALTER TABLE activity_principals DROP COLUMN retired_floor_digest;
    ALTER TABLE activity_probe_state DROP COLUMN retired_context_json;
    CREATE TABLE activity_event_replay_barriers (
      event_id_digest TEXT PRIMARY KEY,
      probe_id TEXT NOT NULL,
      origin_sequence INTEGER NOT NULL,
      canonical_digest TEXT NOT NULL,
      retired_at_ms INTEGER NOT NULL,
      UNIQUE(probe_id, origin_sequence)
    );
    DELETE FROM activity_metadata WHERE key IN ('integrity_commitment_version','server_time_floor_ms','replay_floor_revision','replay_floor_count','replay_floor_root','accepted_event_count','retired_event_count');
    DELETE FROM activity_schema_migrations WHERE version=5;
    UPDATE core_metadata SET value='4' WHERE key='activity_schema_version';
  `);
  legacy.prepare("INSERT INTO activity_schema_migrations(version,state,checksum,committed_at_ms) VALUES (4,'committed',?,1)")
    .run(ACTIVITY_SCHEMA_V4_CHECKSUM);
  legacy.close();
}

function assertActivityError(action, code) {
  assert.throws(action, (error) => error?.code === code);
}

async function jsonRequest(url, { method = 'GET', token, body, protocol = true, headers = {} } = {}) {
  const response = await fetch(url, {
    method,
    headers: {
      ...(protocol ? { 'x-core-protocol': '0.1' } : {}),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'content-type': 'application/json' } : {}),
      ...headers,
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  return { status: response.status, body: await response.json() };
}

function partialJsonRequest(url, { method = 'POST', token } = {}) {
  let request;
  const response = new Promise((resolve, reject) => {
    request = httpRequest(url, {
      method,
      headers: {
        'x-core-protocol': '0.1',
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
      },
    }, (incoming) => {
      const chunks = [];
      incoming.on('data', (chunk) => chunks.push(chunk));
      incoming.on('end', () => resolve({
        status: incoming.statusCode,
        body: JSON.parse(Buffer.concat(chunks).toString('utf8')),
      }));
    });
    request.on('error', reject);
  });
  return { request, response };
}

async function startServer(t, directory, { activity = true, nowRef = { value: 1_000_000 } } = {}) {
  const core = createICoreServer({
    databasePath: path.join(directory, 'core.sqlite'),
    pairingCode: 'device-pairing-code',
    workerSecret: 'independent-worker-secret',
    activityAdminSecret: activity ? OWNER_SECRET : null,
    clock: () => nowRef.value,
  });
  const address = await core.listen({ port: 0 });
  t.after(async () => {
    await core.close();
    rmSync(directory, { recursive: true, force: true });
  });
  return { core, baseUrl: `http://127.0.0.1:${address.port}` };
}

async function pairProbeHttp(baseUrl, overrides = {}) {
  const response = await jsonRequest(`${baseUrl}/v1/core/activity/probes/pair`, {
    method: 'POST',
    token: OWNER_SECRET,
    body: {
      device_id: 'device-a',
      probe_id: 'probe-a',
      display_name: 'synthetic probe',
      capabilities: ['activity.admin', 'activity.read_summary', 'chat.read'],
      source: 'windows_wts',
      coverage_mode: 'continuous',
      expected_report_interval_ms: 30_000,
      expiry_slo_ms: 300_000,
      allowed_kinds: ACTIVITY_KINDS,
      ...overrides,
    },
  });
  if (response.status === 200 && response.body?.event_id_prefix) {
    EVENT_PREFIXES.set(
      eventPrefixKey(overrides.device_id ?? 'device-a', overrides.probe_id ?? 'probe-a'),
      response.body.event_id_prefix,
    );
  }
  return response;
}

test('new Core schema 4 database initializes activity schema 5 and repeated startup is idempotent', () => {
  const directory = tempDir('activity-migration');
  const databasePath = path.join(directory, 'core.sqlite');
  const legacy = new DatabaseSync(databasePath);
  legacy.exec(`CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
    INSERT INTO core_metadata VALUES
      ('schema_version','4'),
      ('node_id','legacy-node'),
      ('cursor_secret','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');`);
  legacy.close();
  const first = new ICoreStore(databasePath, { clock: () => 1234 });
  assert.deepEqual(first.activity.schemaStatus(), { ready: true, schema_version: 5, reason: null, missing_tables: [] });
  assert.equal(first.health().schema_version, 5);
  assert.equal(first.db.prepare('SELECT COUNT(*) AS value FROM activity_schema_migrations').get().value, 1);
  first.close();
  const second = new ICoreStore(databasePath, { clock: () => 5678 });
  assert.equal(second.activity.migration.migrated, false);
  assert.equal(second.db.prepare('SELECT COUNT(*) AS value FROM activity_schema_migrations').get().value, 1);
  second.close();
  rmSync(directory, { recursive: true, force: true });
});

test('empty path-bound activity schema 4 migrates atomically to structured schema 5', () => {
  const directory = tempDir('activity-schema-four-empty-upgrade');
  const databasePath = path.join(directory, 'core.sqlite');
  let store = new ICoreStore(databasePath);
  store.close();
  downgradeToActivitySchemaFour(databasePath);

  store = new ICoreStore(databasePath, { activityEnabled: true, clock: () => 1_000_000 });
  assert.equal(store.activity.schemaStatus().ready, true);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 0);
  assert.equal(store.db.prepare("SELECT COUNT(*) AS value FROM sqlite_master WHERE name='activity_event_replay_barriers'").get().value, 0);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('nonempty or historically advanced activity schema 4 refuses migration with zero file mutation', () => {
  const scenarios = [
    {
      name: 'raw-and-credential-history',
      prepare(store) {
        const paired = pairProbe(store);
        store.activity.appendEvents(store.activity.authenticate(paired.probe_token), { events: [event()] });
      },
      corrupt() {},
    },
    {
      name: 'rolled-back-replay-barrier',
      prepare(store) {
        pairProbe(store);
      },
      corrupt(db) {
        db.prepare(`INSERT INTO activity_event_replay_barriers(
          event_id_digest,probe_id,origin_sequence,canonical_digest,retired_at_ms
        ) VALUES (?,?,?,?,?),(?,?,?,?,?)`).run(
          'a'.repeat(64), 'probe-a', 0, 'c'.repeat(64), 1,
          'b'.repeat(64), 'probe-a', 1, 'd'.repeat(64), 2,
        );
        db.prepare("UPDATE activity_probe_state SET retained_origin_floor=1 WHERE probe_id='probe-a'").run();
        assert.equal(db.prepare('SELECT COUNT(*) AS value FROM activity_event_replay_barriers').get().value, 2);
        db.prepare("DELETE FROM activity_event_replay_barriers WHERE probe_id='probe-a' AND origin_sequence=1").run();
        db.prepare("UPDATE activity_probe_state SET retained_origin_floor=0 WHERE probe_id='probe-a'").run();
      },
    },
    {
      name: 'metadata-history',
      prepare() {},
      corrupt(db) {
        db.prepare("UPDATE activity_metadata SET value='1' WHERE key='commit_high_water'").run();
      },
    },
  ];
  for (const scenario of scenarios) {
    const directory = tempDir(`activity-schema-four-refusal-${scenario.name}`);
    const databasePath = path.join(directory, 'core.sqlite');
    const store = scenario.name === 'metadata-history'
      ? new ICoreStore(databasePath)
      : openStore(directory);
    scenario.prepare(store);
    store.close();
    downgradeToActivitySchemaFour(databasePath);
    const legacy = new DatabaseSync(databasePath);
    scenario.corrupt(legacy);
    const before = {
      claim: legacy.prepare('SELECT * FROM activity_runtime_claim').get(),
      changes: legacy.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
      highWater: legacy.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
    };
    legacy.close();
    const digestBefore = createHash('sha256').update(readFileSync(databasePath)).digest('hex');
    assertActivityError(
      () => new ICoreStore(databasePath, { activityEnabled: true, clock: () => 1_000_000 }),
      'activity_legacy_binding_authorization_required',
    );
    assert.equal(createHash('sha256').update(readFileSync(databasePath)).digest('hex'), digestBefore, scenario.name);
    const after = new DatabaseSync(databasePath, { readOnly: true });
    assert.deepEqual(after.prepare('SELECT * FROM activity_runtime_claim').get(), before.claim, scenario.name);
    assert.equal(after.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value, before.changes, scenario.name);
    assert.equal(after.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value, before.highWater, scenario.name);
    after.close();
    rmSync(directory, { recursive: true, force: true });
  }
});

test('empty activity storage schema 1 upgrades to path-bound schema 5', () => {
  const directory = tempDir('activity-schema-one-upgrade');
  const databasePath = path.join(directory, 'core.sqlite');
  let store = new ICoreStore(databasePath);
  store.close();
  const legacy = new DatabaseSync(databasePath);
  legacy.exec(`
    DROP TABLE activity_runtime_claim;
    DROP TABLE activity_replay_lineage_floors;
    DROP INDEX activity_principals_event_prefix_idx;
    ALTER TABLE activity_principals DROP COLUMN event_id_prefix;
    ALTER TABLE activity_principals DROP COLUMN retired_event_prefix_digest;
    ALTER TABLE activity_principals DROP COLUMN retired_floor_digest;
    ALTER TABLE activity_probe_state DROP COLUMN retained_origin_floor;
    ALTER TABLE activity_probe_state DROP COLUMN retired_context_json;
    DELETE FROM activity_metadata WHERE key='commit_high_water';
    DELETE FROM activity_metadata WHERE key='database_role';
    DELETE FROM activity_metadata WHERE key='database_binding_digest';
    DELETE FROM activity_metadata WHERE key IN ('integrity_commitment_version','server_time_floor_ms','replay_floor_revision','replay_floor_count','replay_floor_root','accepted_event_count','retired_event_count');
    DELETE FROM activity_schema_migrations WHERE version=5;
    UPDATE core_metadata SET value='1' WHERE key='activity_schema_version';
  `);
  legacy.prepare("INSERT INTO activity_schema_migrations(version,state,checksum,committed_at_ms) VALUES (1,'committed',?,1)")
    .run(ACTIVITY_SCHEMA_V1_CHECKSUM);
  legacy.close();

  const historicalPath = path.join(directory, 'historical-v1.sqlite');
  copyFileSync(databasePath, historicalPath);
  const historical = new DatabaseSync(historicalPath);
  historical.prepare("UPDATE activity_metadata SET value='2' WHERE key='snapshot_generation'").run();
  historical.close();
  const historicalDigest = createHash('sha256').update(readFileSync(historicalPath)).digest('hex');
  assertActivityError(
    () => new ICoreStore(historicalPath, { activityEnabled: true }),
    'activity_legacy_binding_authorization_required',
  );
  assert.equal(createHash('sha256').update(readFileSync(historicalPath)).digest('hex'), historicalDigest);

  store = new ICoreStore(databasePath, { clock: () => 1_100_000, activityEnabled: true });
  assert.equal(store.activity.schemaStatus().schema_version, 5);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 0);
  assert.equal(pairProbe(store).scopes[0], 'activity.write');
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('empty activity storage schema 2 adds the canonical live role and path binding', () => {
  const directory = tempDir('activity-schema-two-upgrade');
  const databasePath = path.join(directory, 'core.sqlite');
  let store = new ICoreStore(databasePath);
  store.close();
  const legacy = new DatabaseSync(databasePath);
  legacy.exec(`
    DROP TABLE activity_replay_lineage_floors;
    DROP INDEX activity_principals_event_prefix_idx;
    ALTER TABLE activity_principals DROP COLUMN event_id_prefix;
    ALTER TABLE activity_principals DROP COLUMN retired_event_prefix_digest;
    ALTER TABLE activity_principals DROP COLUMN retired_floor_digest;
    ALTER TABLE activity_probe_state DROP COLUMN retained_origin_floor;
    ALTER TABLE activity_probe_state DROP COLUMN retired_context_json;
    DELETE FROM activity_metadata WHERE key='database_role';
    DELETE FROM activity_metadata WHERE key='database_binding_digest';
    DELETE FROM activity_metadata WHERE key IN ('integrity_commitment_version','server_time_floor_ms','replay_floor_revision','replay_floor_count','replay_floor_root','accepted_event_count','retired_event_count');
    DELETE FROM activity_schema_migrations WHERE version=5;
    UPDATE core_metadata SET value='2' WHERE key='activity_schema_version';
  `);
  legacy.prepare("INSERT INTO activity_schema_migrations(version,state,checksum,committed_at_ms) VALUES (2,'committed',?,2)")
    .run(ACTIVITY_SCHEMA_V2_CHECKSUM);
  legacy.close();
  const historicalPath = path.join(directory, 'historical-v2.sqlite');
  copyFileSync(databasePath, historicalPath);
  const historical = new DatabaseSync(historicalPath);
  historical.prepare("UPDATE activity_metadata SET value='1' WHERE key='commit_high_water'").run();
  historical.close();
  const historicalDigest = createHash('sha256').update(readFileSync(historicalPath)).digest('hex');
  assertActivityError(
    () => new ICoreStore(historicalPath, { activityEnabled: true }),
    'activity_legacy_binding_authorization_required',
  );
  assert.equal(createHash('sha256').update(readFileSync(historicalPath)).digest('hex'), historicalDigest);
  store = new ICoreStore(databasePath, { clock: () => 1_100_000, activityEnabled: true });
  assert.equal(store.activity.schemaStatus().schema_version, 5);
  assert.equal(store.db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get().value, 'live');
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 0);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('empty activity storage schema 3 binds the live database path atomically', () => {
  const directory = tempDir('activity-schema-three-upgrade');
  const databasePath = path.join(directory, 'core.sqlite');
  let store = new ICoreStore(databasePath);
  store.close();
  const legacy = new DatabaseSync(databasePath);
  legacy.exec(`
    DROP TABLE activity_replay_lineage_floors;
    DROP INDEX activity_principals_event_prefix_idx;
    ALTER TABLE activity_principals DROP COLUMN event_id_prefix;
    ALTER TABLE activity_principals DROP COLUMN retired_event_prefix_digest;
    ALTER TABLE activity_principals DROP COLUMN retired_floor_digest;
    ALTER TABLE activity_probe_state DROP COLUMN retained_origin_floor;
    ALTER TABLE activity_probe_state DROP COLUMN retired_context_json;
    DELETE FROM activity_metadata WHERE key='database_binding_digest';
    DELETE FROM activity_metadata WHERE key IN ('integrity_commitment_version','server_time_floor_ms','replay_floor_revision','replay_floor_count','replay_floor_root','accepted_event_count','retired_event_count');
    DELETE FROM activity_schema_migrations WHERE version=5;
    UPDATE core_metadata SET value='3' WHERE key='activity_schema_version';
  `);
  legacy.prepare("INSERT INTO activity_schema_migrations(version,state,checksum,committed_at_ms) VALUES (3,'committed',?,1)")
    .run(ACTIVITY_SCHEMA_V3_CHECKSUM);
  legacy.close();
  const historicalPath = path.join(directory, 'historical-v3.sqlite');
  copyFileSync(databasePath, historicalPath);
  const historical = new DatabaseSync(historicalPath);
  historical.prepare("UPDATE activity_runtime_claim SET runtime_fence=1").run();
  historical.close();
  const historicalDigest = createHash('sha256').update(readFileSync(historicalPath)).digest('hex');
  assertActivityError(
    () => new ICoreStore(historicalPath, { activityEnabled: true }),
    'activity_legacy_binding_authorization_required',
  );
  assert.equal(createHash('sha256').update(readFileSync(historicalPath)).digest('hex'), historicalDigest);
  store = new ICoreStore(databasePath, { activityEnabled: true });
  assert.equal(store.activity.schemaStatus().schema_version, 5);
  assert.match(store.db.prepare("SELECT value FROM activity_metadata WHERE key='database_binding_digest'").get().value, /^[a-f0-9]{64}$/);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('missing or noncanonical activity metadata disables health, signing and restart', () => {
  const corruptions = [
    ['missing authority epoch', "DELETE FROM activity_metadata WHERE key='authority_epoch'"],
    ['missing retained watermark', "DELETE FROM activity_metadata WHERE key='retained_watermark'"],
    ['missing snapshot generation', "DELETE FROM activity_metadata WHERE key='snapshot_generation'"],
    ['missing commit high water', "DELETE FROM activity_metadata WHERE key='commit_high_water'"],
    ['missing accepted event count', "DELETE FROM activity_metadata WHERE key='accepted_event_count'"],
    ['missing retired event count', "DELETE FROM activity_metadata WHERE key='retired_event_count'"],
    ['missing database role', "DELETE FROM activity_metadata WHERE key='database_role'"],
    ['nonnumeric authority epoch', "UPDATE activity_metadata SET value='junk' WHERE key='authority_epoch'"],
    ['zero authority epoch', "UPDATE activity_metadata SET value='0' WHERE key='authority_epoch'"],
    ['negative retained watermark', "UPDATE activity_metadata SET value='-1' WHERE key='retained_watermark'"],
    ['zero snapshot generation', "UPDATE activity_metadata SET value='0' WHERE key='snapshot_generation'"],
    ['fractional snapshot generation', "UPDATE activity_metadata SET value='1.5' WHERE key='snapshot_generation'"],
    ['noncanonical retained watermark', "UPDATE activity_metadata SET value='00' WHERE key='retained_watermark'"],
    ['noncanonical commit high water', "UPDATE activity_metadata SET value='01' WHERE key='commit_high_water'"],
    ['negative retired event count', "UPDATE activity_metadata SET value='-1' WHERE key='retired_event_count'"],
    ['invalid database role', "UPDATE activity_metadata SET value='restored_live' WHERE key='database_role'"],
  ];
  for (const [name, sql] of corruptions) {
    const directory = tempDir(`activity-metadata-${name.replaceAll(' ', '-')}`);
    const databasePath = path.join(directory, 'core.sqlite');
    const store = openStore(directory);
    store.db.exec(sql);
    const status = store.activity.schemaStatus();
    assert.equal(status.ready, false, name);
    assert.equal(status.reason, 'metadata_invariant_failed', name);
    const health = store.health({ activityOwnerConfigured: true });
    assert.equal(health.activity.control_plane_available, false, name);
    assert.equal(health.features.includes(ACTIVITY_CONTRACT), false, name);
    assertActivityError(
      () => pairReader(store),
      name.includes('database role') ? 'activity_database_role_changed' : 'activity_schema_not_ready',
    );
    assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_principals').get().value, 0);
    store.close();
    assert.throws(
      () => new ICoreStore(databasePath),
      (error) => error?.code === (name === 'invalid database role' ? 'activity_schema_not_ready' : 'activity_migration_incomplete'),
      name,
    );
    rmSync(directory, { recursive: true, force: true });
  }
});

test('persisted principal and credential authority rows fail closed before restart mutation', () => {
  const malformed = [
    ['malformed allowed kinds json', "UPDATE activity_principals SET allowed_kinds_json='{' WHERE probe_id='probe-a'", 'principal_registration_invariant_failed'],
    ['malformed scopes json', "UPDATE activity_principals SET scopes_json='{' WHERE probe_id='probe-a'", 'principal_registration_invariant_failed'],
    ['malformed capabilities json', "UPDATE activity_principals SET capabilities_json='{' WHERE probe_id='probe-a'", 'principal_registration_invariant_failed'],
    ['probe scope escalation', "UPDATE activity_principals SET scopes_json='[\"activity.read_summary\"]' WHERE probe_id='probe-a'", 'principal_registration_invariant_failed'],
    ['probe type changed to reader', "UPDATE activity_principals SET principal_type='summary_reader' WHERE probe_id='probe-a'", 'principal_registration_invariant_failed'],
    ['probe source outside closed set', "UPDATE activity_principals SET source='private_source' WHERE probe_id='probe-a'", 'principal_registration_invariant_failed'],
    ['probe coverage outside closed set', "UPDATE activity_principals SET coverage_mode='always' WHERE probe_id='probe-a'", 'principal_registration_invariant_failed'],
    ['probe interval zero', "UPDATE activity_principals SET expected_report_interval_ms=0 WHERE probe_id='probe-a'", 'principal_registration_invariant_failed'],
    ['probe expiry overflow', `UPDATE activity_principals SET expiry_slo_ms=${Number.MAX_SAFE_INTEGER} WHERE probe_id='probe-a'`, 'principal_registration_invariant_failed'],
    ['reader acquires probe shape', "UPDATE activity_principals SET probe_id='reader-probe' WHERE principal_type='summary_reader'", 'principal_registration_invariant_failed'],
    ['principal generation skips credential', "UPDATE activity_principals SET credential_generation=2 WHERE probe_id='probe-a'", 'credential_invariant_failed'],
    ['credential generation skips sequence', "UPDATE activity_credentials SET generation=2 WHERE principal_id=(SELECT principal_id FROM activity_principals WHERE probe_id='probe-a')", 'credential_invariant_failed'],
    ['credential hash malformed', "UPDATE activity_credentials SET token_hash='abc' WHERE principal_id=(SELECT principal_id FROM activity_principals WHERE probe_id='probe-a')", 'credential_invariant_failed'],
    ['active credential marked revoked', "UPDATE activity_credentials SET revoked_at_ms=1000000 WHERE principal_id=(SELECT principal_id FROM activity_principals WHERE probe_id='probe-a')", 'credential_invariant_failed'],
    ['credential issued before pairing', "UPDATE activity_credentials SET issued_at_ms=999999 WHERE principal_id=(SELECT principal_id FROM activity_principals WHERE probe_id='probe-a')", 'credential_invariant_failed'],
  ];
  const authenticatedMutations = [
    ['allowed source changed', "UPDATE activity_principals SET source='windows_probe' WHERE probe_id='probe-a'"],
    ['allowed kinds narrowed', "UPDATE activity_principals SET allowed_kinds_json='[\"session.locked\"]' WHERE probe_id='probe-a'"],
    ['expiry changed', "UPDATE activity_principals SET expiry_slo_ms=299999 WHERE probe_id='probe-a'"],
    ['capabilities changed', "UPDATE activity_principals SET capabilities_json='[]' WHERE probe_id='probe-a'"],
    ['credential hash replaced', `UPDATE activity_credentials SET token_hash='${'a'.repeat(64)}' WHERE principal_id=(SELECT principal_id FROM activity_principals WHERE probe_id='probe-a')`],
  ].map(([name, sql]) => [name, sql, 'replay_floor_invariant_failed']);

  for (const [name, sql, expectedReason] of [...malformed, ...authenticatedMutations]) {
    const directory = tempDir(`activity-authority-row-${name.replaceAll(' ', '-')}`);
    const databasePath = path.join(directory, 'core.sqlite');
    const store = openStore(directory);
    pairProbe(store);
    pairReader(store);
    store.close();
    const corrupt = new DatabaseSync(databasePath);
    corrupt.exec(sql);
    assert.equal(activitySchemaStatus(corrupt).reason, expectedReason, name);
    const before = {
      claim: corrupt.prepare('SELECT * FROM activity_runtime_claim').get(),
      changes: corrupt.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
      highWater: corrupt.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
      replayRoot: corrupt.prepare("SELECT value FROM activity_metadata WHERE key='replay_floor_root'").get().value,
    };
    corrupt.close();
    assertActivityError(
      () => new ICoreStore(databasePath, { activityEnabled: true, clock: () => 1_000_000 }),
      'activity_migration_incomplete',
    );
    const after = new DatabaseSync(databasePath, { readOnly: true });
    assert.deepEqual({
      claim: after.prepare('SELECT * FROM activity_runtime_claim').get(),
      changes: after.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
      highWater: after.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
      replayRoot: after.prepare("SELECT value FROM activity_metadata WHERE key='replay_floor_root'").get().value,
    }, before, name);
    after.close();
    rmSync(directory, { recursive: true, force: true });
  }
});

test('canonical active, rotated and revoked authority rows survive a clean restart', () => {
  const directory = tempDir('activity-authority-row-positive');
  const databasePath = path.join(directory, 'core.sqlite');
  let store = openStore(directory);
  const active = pairProbe(store, { probeId: 'probe-active' });
  pairProbe(store, { probeId: 'probe-revoked' });
  const reader = pairReader(store);
  store.activity.rotatePrincipal(active.principal_id, 1_000_001);
  store.activity.rotatePrincipal(reader.principal_id, 1_000_001);
  store.activity.revokeProbe('probe-revoked', 1_000_002);
  assert.equal(store.activity.schemaStatus().ready, true);
  store.close();
  store = new ICoreStore(databasePath, { activityEnabled: true, clock: () => 1_000_003 });
  assert.equal(store.activity.schemaStatus().ready, true);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('every migration-owned explicit index is a fail-closed readiness invariant', () => {
  for (const index of ['activity_changes_subject_idx', 'activity_events_received_idx', 'activity_audit_expiry_idx']) {
    const directory = tempDir(`activity-index-${index}`);
    const databasePath = path.join(directory, 'core.sqlite');
    const store = openStore(directory);
    store.db.exec(`DROP INDEX ${index}`);
    assert.equal(store.activity.schemaStatus().ready, false, index);
    assert.equal(store.health({ activityOwnerConfigured: true }).features.includes(ACTIVITY_CONTRACT), false, index);
    assertActivityError(() => pairReader(store), 'activity_schema_not_ready');
    store.close();
    assert.throws(() => new ICoreStore(databasePath), (error) => error?.code === 'activity_migration_incomplete', index);
    rmSync(directory, { recursive: true, force: true });
  }
});

test('migration-owned primary and unique table DDL is a fail-closed readiness invariant', () => {
  const directory = tempDir('activity-constraint-invariant');
  const databasePath = path.join(directory, 'core.sqlite');
  const store = openStore(directory);
  store.db.exec(`
    ALTER TABLE activity_credentials RENAME TO activity_credentials_original;
    CREATE TABLE activity_credentials (
      credential_id TEXT PRIMARY KEY,
      principal_id TEXT NOT NULL,
      generation INTEGER NOT NULL,
      token_hash TEXT NOT NULL,
      issued_at_ms INTEGER NOT NULL,
      revoked_at_ms INTEGER,
      FOREIGN KEY(principal_id) REFERENCES activity_principals(principal_id),
      UNIQUE(principal_id, generation)
    );
    DROP TABLE activity_credentials_original;
  `);
  assert.equal(store.activity.schemaStatus().ready, false);
  assert.equal(store.health({ activityOwnerConfigured: true }).features.includes(ACTIVITY_CONTRACT), false);
  assertActivityError(() => pairReader(store), 'activity_schema_not_ready');
  store.close();
  assert.throws(() => new ICoreStore(databasePath), (error) => error?.code === 'activity_migration_incomplete');
  rmSync(directory, { recursive: true, force: true });
});

test('unknown activity triggers and extra unique indexes fail health and data plane closed', () => {
  for (const [name, sql, expectedReason] of [
    ['trigger', `CREATE TRIGGER unexpected_activity_trigger AFTER INSERT ON activity_events
      BEGIN UPDATE activity_metadata SET value=value WHERE key='commit_high_water'; END`, 'unexpected_activity_trigger'],
    ['unique-index', 'CREATE UNIQUE INDEX unexpected_probe_unique ON activity_events(probe_id)', 'unexpected_unique_index'],
  ]) {
    const directory = tempDir(`activity-unexpected-schema-${name}`);
    const store = openStore(directory);
    const probe = pairProbe(store);
    const principal = store.activity.authenticate(probe.probe_token);
    store.db.exec(sql);
    const before = {
      events: store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value,
      changes: store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
      highWater: store.db.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
    };
    assert.equal(store.activity.schemaStatus().reason, expectedReason, name);
    assert.equal(store.health({ activityOwnerConfigured: true }).features.includes(ACTIVITY_CONTRACT), false, name);
    assertActivityError(() => store.activity.appendEvents(principal, { events: [event()] }), 'activity_schema_not_ready');
    assert.deepEqual({
      events: store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value,
      changes: store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
      highWater: store.db.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
    }, before, name);
    store.close();
    rmSync(directory, { recursive: true, force: true });
  }
});

test('event canonical bytes, projection evidence and activity foreign keys are readiness invariants', () => {
  const scenarios = [
    {
      name: 'event-payload-digest-mismatch',
      prepare(store) {
        const probe = pairProbe(store);
        store.activity.appendEvents(store.activity.authenticate(probe.probe_token), { events: [event()] });
        store.db.prepare("UPDATE activity_events SET payload_json='{" + '"class":"input_or_touch"' + "}'").run();
      },
      reason: 'event_lineage_invariant_failed',
    },
    {
      name: 'projection-without-current-evidence',
      prepare(store) {
        pairProbe(store);
        store.db.prepare(`UPDATE activity_projections SET state='active',coverage_status='covered',
          clock_health='healthy',status_reason='fresh_signal',expires_at_ms=999999999
          WHERE probe_id='probe-a'`).run();
      },
      reason: 'replay_floor_invariant_failed',
      shallowReady: false,
    },
    {
      name: 'dangling-credential-principal',
      prepare(store) {
        pairProbe(store);
        store.db.exec('PRAGMA foreign_keys=OFF');
        store.db.prepare("UPDATE activity_credentials SET principal_id='missing-principal'").run();
        store.db.exec('PRAGMA foreign_keys=ON');
      },
      reason: 'foreign_key_invariant_failed',
      shallowReady: false,
    },
    {
      name: 'future-clock-derived-columns-tampered-together',
      prepare(store) {
        const probe = pairProbe(store);
        store.activity.appendEvents(store.activity.authenticate(probe.probe_token), {
          events: [event({ signalAt: 1_600_001 })],
        });
        store.db.prepare("UPDATE activity_events SET clock_health='healthy'").run();
        store.db.prepare(`UPDATE activity_projections SET state='active',coverage_status='covered',
          clock_health='healthy',status_reason='fresh_signal' WHERE probe_id='probe-a'`).run();
      },
      reason: 'replay_floor_invariant_failed',
      shallowReady: false,
    },
    {
      name: 'coverage-gap-derived-columns-tampered-together',
      prepare(store) {
        const probe = pairProbe(store);
        const principal = store.activity.authenticate(probe.probe_token);
        store.activity.appendEvents(principal, { events: [event({ originSequence: 1 })] });
        store.activity.appendEvents(principal, {
          events: [event({ originSequence: 3, signalAt: 1_000_100 })],
        });
        store.db.prepare("UPDATE activity_probe_state SET last_coverage_status='covered' WHERE probe_id='probe-a'").run();
        store.db.prepare(`UPDATE activity_projections SET state='active',coverage_status='covered',
          clock_health='healthy',status_reason='fresh_signal' WHERE probe_id='probe-a'`).run();
      },
      reason: 'replay_floor_invariant_failed',
      shallowReady: false,
    },
  ];
  for (const scenario of scenarios) {
    const directory = tempDir(`activity-row-integrity-${scenario.name}`);
    const store = openStore(directory);
    scenario.prepare(store);
    const before = {
      changes: store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
      highWater: store.db.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
    };
    assert.equal(store.activity.schemaStatus().reason, scenario.reason, scenario.name);
    assert.equal(
      store.health({ activityOwnerConfigured: true }).activity.control_plane_available,
      false,
      'public health performs deep integrity verification before advertising activity',
    );
    assertActivityError(() => store.activity.adminExport(), 'activity_schema_not_ready');
    assert.deepEqual({
      changes: store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
      highWater: store.db.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
    }, before, scenario.name);
    store.close();
    assertActivityError(
      () => new ICoreStore(path.join(directory, 'core.sqlite'), { activityEnabled: true }),
      'activity_migration_incomplete',
    );
    rmSync(directory, { recursive: true, force: true });
  }
});

test('projection derived fields are recomputed from current event and explicit override state', () => {
  const directory = tempDir('activity-projection-derived-integrity');
  const databasePath = path.join(directory, 'core.sqlite');
  const store = openStore(directory);
  const probe = pairProbe(store);
  store.activity.appendEvents(store.activity.authenticate(probe.probe_token), { events: [event()] });
  const original = store.db.prepare("SELECT * FROM activity_projections WHERE probe_id='probe-a'").get();
  for (const [field, value] of [
    ['expires_at_ms', Number(original.expires_at_ms) + 1],
    ['state', 'locked'],
    ['coverage_status', 'missing'],
    ['clock_health', 'future_skew'],
    ['status_reason', 'ttl_expired'],
  ]) {
    store.db.prepare(`UPDATE activity_projections SET ${field}=? WHERE probe_id='probe-a'`).run(value);
    assert.equal(store.activity.schemaStatus().reason, 'replay_floor_invariant_failed', field);
    assertActivityError(() => store.activity.adminExport(), 'activity_schema_not_ready');
    store.db.prepare(`UPDATE activity_projections SET ${field}=? WHERE probe_id='probe-a'`).run(original[field]);
    assert.equal(activitySchemaStatus(store.db).ready, true, field);
  }
  store.close();
  const corrupt = new DatabaseSync(databasePath);
  corrupt.prepare("UPDATE activity_projections SET state='locked' WHERE probe_id='probe-a'").run();
  const before = {
    claim: corrupt.prepare('SELECT * FROM activity_runtime_claim').get(),
    changes: corrupt.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
    highWater: corrupt.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
  };
  corrupt.close();
  assertActivityError(() => new ICoreStore(databasePath, { activityEnabled: true }), 'activity_migration_incomplete');
  const after = new DatabaseSync(databasePath, { readOnly: true });
  assert.deepEqual(after.prepare('SELECT * FROM activity_runtime_claim').get(), before.claim);
  assert.equal(after.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value, before.changes);
  assert.equal(after.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value, before.highWater);
  after.close();
  rmSync(directory, { recursive: true, force: true });
});

test('future or malformed activity migration ledger evidence fails closed without mutation', () => {
  for (const [name, sql] of [
    ['future-version', `INSERT INTO activity_schema_migrations(version,state,checksum,committed_at_ms)
      VALUES (6,'committed','${'a'.repeat(64)}',1)`],
    ['malformed-checksum', "UPDATE activity_schema_migrations SET checksum='BAD' WHERE version=5"],
    ['forged-past-checksum', `INSERT INTO activity_schema_migrations(version,state,checksum,committed_at_ms)
      VALUES (1,'committed','${'b'.repeat(64)}',1)`],
  ]) {
    const directory = tempDir(`activity-ledger-${name}`);
    const databasePath = path.join(directory, 'core.sqlite');
    const store = openStore(directory);
    store.close();
    const db = new DatabaseSync(databasePath);
    db.exec(sql);
    const before = {
      claim: db.prepare('SELECT * FROM activity_runtime_claim').get(),
      changes: db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
      highWater: db.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
    };
    db.close();
    assertActivityError(
      () => new ICoreStore(databasePath, { activityEnabled: true }),
      'activity_migration_incomplete',
    );
    const after = new DatabaseSync(databasePath, { readOnly: true });
    assert.deepEqual(after.prepare('SELECT * FROM activity_runtime_claim').get(), before.claim, name);
    assert.equal(after.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value, before.changes, name);
    assert.equal(after.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value, before.highWater, name);
    after.close();
    rmSync(directory, { recursive: true, force: true });
  }
});

test('unknown future Core schema is never rewritten or migrated down to schema 5', () => {
  const directory = tempDir('activity-future-core-schema');
  const databasePath = path.join(directory, 'core.sqlite');
  const db = new DatabaseSync(databasePath);
  db.exec("CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL); INSERT INTO core_metadata VALUES ('schema_version','999');");
  db.close();
  assert.throws(() => new ICoreStore(databasePath), (error) => error?.code === 'unsupported_core_schema_version');
  const unchanged = new DatabaseSync(databasePath);
  assert.equal(unchanged.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get().value, '999');
  assert.equal(unchanged.prepare("SELECT COUNT(*) AS value FROM sqlite_master WHERE name LIKE 'activity_%'").get().value, 0);
  unchanged.close();
  rmSync(directory, { recursive: true, force: true });
});

test('old binary schema write-back to 4 makes an existing activity schema fail closed', () => {
  const directory = tempDir('activity-old-binary-writeback');
  const databasePath = path.join(directory, 'core.sqlite');
  const store = openStore(directory);
  store.db.prepare("UPDATE core_metadata SET value='4' WHERE key='schema_version'").run();
  assert.equal(store.activity.schemaStatus().ready, false);
  assert.equal(store.health({ activityOwnerConfigured: true }).features.includes(ACTIVITY_CONTRACT), false);
  assertActivityError(() => pairReader(store), 'activity_schema_not_ready');
  store.close();
  assert.throws(() => new ICoreStore(databasePath), (error) => error?.code === 'activity_migration_incomplete');
  const unchanged = new DatabaseSync(databasePath);
  assert.equal(unchanged.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get().value, '4');
  unchanged.close();
  rmSync(directory, { recursive: true, force: true });
});

test('table presence without the committed invariant ledger cannot advertise the activity feature', () => {
  const directory = tempDir('activity-health-invariant');
  const store = openStore(directory);
  store.db.prepare('DELETE FROM activity_schema_migrations').run();
  const health = store.health({ activityOwnerConfigured: true });
  assert.equal(health.activity.status, 'migration_incomplete');
  assert.equal(health.activity.control_plane_available, false);
  assert.equal(health.features.includes(ACTIVITY_CONTRACT), false);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('interrupted migration rolls back every activity table and incomplete ledger fails health closed', () => {
  const db = new DatabaseSync(':memory:');
  db.exec(`CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
    INSERT INTO core_metadata VALUES
      ('schema_version','4'),
      ('node_id','node-a'),
      ('cursor_secret','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');`);
  assert.throws(() => migrateActivitySchema(db, { now: 1, failpoint: 'after_ddl', databaseBindingDigest: TEST_DATABASE_BINDING }), /synthetic/);
  assert.equal(activitySchemaStatus(db).ready, false);
  assert.equal(db.prepare("SELECT COUNT(*) AS value FROM sqlite_master WHERE name LIKE 'activity_%'").get().value, 0);
  migrateActivitySchema(db, { now: 2, databaseBindingDigest: TEST_DATABASE_BINDING });
  const plane = new ActivityControlPlane(db, {
    nodeId: 'node-a',
    cursorSecret: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    databaseBindingDigest: TEST_DATABASE_BINDING,
    clock: () => 3,
  });
  db.prepare('DELETE FROM activity_schema_migrations').run();
  assert.equal(plane.schemaStatus().ready, false);
  db.close();
});

test('health exposes activity ready only when migration invariants and independent owner bootstrap both hold', async (t) => {
  const disabledDir = tempDir('activity-health-disabled');
  const disabled = await startServer(t, disabledDir, { activity: false });
  const disabledHealth = await jsonRequest(`${disabled.baseUrl}/v1/core/health`, { protocol: false });
  assert.equal(disabledHealth.body.activity.status, 'owner_principal_unconfigured');
  assert.equal(disabledHealth.body.activity.e2e_available, false);
  assert.equal(disabledHealth.body.activity.control_plane_available, false);
  assert.equal(disabledHealth.body.features.includes(ACTIVITY_CONTRACT), false);

  const enabledDir = tempDir('activity-health-enabled');
  const enabled = await startServer(t, enabledDir);
  const enabledHealth = await jsonRequest(`${enabled.baseUrl}/v1/core/health`, { protocol: false });
  assert.equal(enabledHealth.body.activity.status, 'control_plane_ready');
  assert.equal(enabledHealth.body.activity.control_plane_available, true);
  assert.equal(enabledHealth.body.activity.e2e_available, false);
  assert.equal(enabledHealth.body.activity.collector_available, false);
  assert.equal(enabledHealth.body.activity.summary_client_available, false);
  assert.equal(enabledHealth.body.features.includes(ACTIVITY_CONTRACT), true);
});

test('activity remains dormant on live Core while every formal backup is a whole-Core verification-only artifact', async () => {
  const directory = tempDir('activity-dormant');
  const databasePath = path.join(directory, 'core.sqlite');
  const backupPath = path.join(directory, 'ordinary-backup.sqlite');
  let core = createICoreServer({ databasePath, pairingCode: null, activityAdminSecret: null });
  const pairedDevice = core.store.pairDevice({
    device_id: 'legacy-device',
    display_name: 'legacy device',
    platform: 'test',
    client_version: '1',
    capabilities: ['chat'],
  }, 'synthetic-chat-pairing-code');
  const before = {
    claim: core.store.db.prepare('SELECT * FROM activity_runtime_claim').get(),
    changes: core.store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
    highWater: core.store.db.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
  };
  assert.equal(core.store.health().activity.control_plane_available, false);
  assert.equal(core.store.health().activity.status, 'owner_principal_unconfigured');
  const device = core.store.authenticate(pairedDevice.device_token);
  core.store.submitMessages(device.device_id, {
    device_id: device.device_id,
    messages: [{
      sync_id: 'live-chat-1', origin_device_id: device.device_id, origin_sequence: 1,
      character_id: 'lin-ai', sender: 'user', content: 'synthetic live chat',
      created_at_ms: 1_000_000, message_type: 'chat', asset_refs: [], addenda: [],
    }],
  });
  const livePage = core.store.getChanges(pairedDevice.initial_cursor);
  assert.equal(livePage.events.some((item) => item.entity_id === 'live-chat-1'), true);
  assert.equal(core.store.acknowledgeCursor(device.device_id, {
    device_id: device.device_id,
    cursor: livePage.next_cursor,
  }).ok, true);
  const ordinaryBackup = await core.store.backupDatabase(backupPath);
  assert.equal(ordinaryBackup.recovery_manifest, null);
  const backupDb = new DatabaseSync(backupPath, { readOnly: true });
  assert.equal(backupDb.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get().value, 'backup_read_only');
  backupDb.close();
  const backupDigestBefore = createHash('sha256').update(readFileSync(backupPath)).digest('hex');
  assert.throws(() => new ICoreStore(backupPath), (error) => error?.code === 'backup_activation_unsupported');
  assert.throws(
    () => createICoreServer({ databasePath: backupPath, activityAdminSecret: null }),
    (error) => error?.code === 'backup_activation_unsupported',
  );
  assert.throws(
    () => createICoreServer({ databasePath: backupPath, activityAdminSecret: OWNER_SECRET }),
    (error) => error?.code === 'backup_activation_unsupported',
  );
  assert.equal(createHash('sha256').update(readFileSync(backupPath)).digest('hex'), backupDigestBefore);
  await core.close();

  core = createICoreServer({ databasePath, pairingCode: null, activityAdminSecret: null });
  assert.deepEqual(core.store.db.prepare('SELECT * FROM activity_runtime_claim').get(), before.claim);
  assert.equal(core.store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value, before.changes);
  assert.equal(core.store.db.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value, before.highWater);
  await core.close();
  rmSync(directory, { recursive: true, force: true });
});

test('backup publication never exposes an unmarked final file when staging is interrupted', async () => {
  const directory = tempDir('activity-backup-atomic-publish');
  const store = openStore(directory);
  for (const failpoint of ['after_stage_copy', 'after_role_write']) {
    const destination = path.join(directory, `${failpoint}.sqlite`);
    await assert.rejects(store.backupDatabase(destination, { failpoint }), /synthetic backup interruption/);
    assert.equal(existsSync(destination), false);
    assert.equal(readdirSync(directory).some((name) => name.includes(`${failpoint}.sqlite.`)), false);
  }
  const destination = path.join(directory, 'complete.sqlite');
  await store.backupDatabase(destination);
  const backupDb = new DatabaseSync(destination, { readOnly: true });
  assert.equal(backupDb.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get().value, 'backup_read_only');
  backupDb.close();
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('canonical live-path binding prevents a clean database clone from becoming a second authority', async () => {
  const directory = tempDir('activity-path-binding-clone');
  const livePath = path.join(directory, 'live.sqlite');
  const clonePath = path.join(directory, 'clone.sqlite');
  let live = createICoreServer({ databasePath: livePath, activityAdminSecret: OWNER_SECRET });
  await live.listen({ port: 0 });
  assert.equal(live.store.health({ activityOwnerConfigured: true }).activity.control_plane_available, true);
  await live.close();
  copyFileSync(livePath, clonePath);
  const cloneBefore = new DatabaseSync(clonePath, { readOnly: true });
  const before = {
    claim: cloneBefore.prepare('SELECT * FROM activity_runtime_claim').get(),
    changes: cloneBefore.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
    highWater: cloneBefore.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
  };
  cloneBefore.close();
  assertActivityError(
    () => createICoreServer({ databasePath: clonePath, activityAdminSecret: OWNER_SECRET }),
    'activity_database_binding_mismatch',
  );
  const cloneAfter = new DatabaseSync(clonePath, { readOnly: true });
  assert.deepEqual(cloneAfter.prepare('SELECT * FROM activity_runtime_claim').get(), before.claim);
  assert.equal(cloneAfter.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value, before.changes);
  assert.equal(cloneAfter.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value, before.highWater);
  cloneAfter.close();
  live = createICoreServer({ databasePath: livePath, activityAdminSecret: OWNER_SECRET });
  await live.listen({ port: 0 });
  assert.equal(live.store.health({ activityOwnerConfigured: true }).activity.control_plane_available, true);
  await live.close();
  rmSync(directory, { recursive: true, force: true });
});

test('case-distinct live paths never collapse when the filesystem supports distinct names', (t) => {
  const directory = tempDir('activity-path-case');
  const lowerMarker = path.join(directory, 'case-probe');
  const upperMarker = path.join(directory, 'CASE-PROBE');
  writeFileSync(lowerMarker, 'lower', { flag: 'wx' });
  try {
    writeFileSync(upperMarker, 'upper', { flag: 'wx' });
  } catch (error) {
    if (error?.code === 'EEXIST') {
      rmSync(directory, { recursive: true, force: true });
      t.skip('the test directory is case-insensitive and cannot represent two distinct file identities');
      return;
    }
    throw error;
  }
  const names = new Set(readdirSync(directory));
  if (!names.has('case-probe') || !names.has('CASE-PROBE')) {
    rmSync(directory, { recursive: true, force: true });
    t.skip('the filesystem does not expose case-distinct directory entries');
    return;
  }
  rmSync(lowerMarker, { force: true });
  rmSync(upperMarker, { force: true });
  const lowerPath = path.join(directory, 'core.sqlite');
  const upperPath = path.join(directory, 'CORE.sqlite');
  let live = new ICoreStore(lowerPath, { activityEnabled: true });
  live.close();
  copyFileSync(lowerPath, upperPath);
  assertActivityError(
    () => new ICoreStore(upperPath, { activityEnabled: true }),
    'activity_database_binding_mismatch',
  );
  live = new ICoreStore(lowerPath, { activityEnabled: true });
  assert.equal(live.activity.schemaStatus().ready, true);
  live.close();
  rmSync(directory, { recursive: true, force: true });
});

test('missing or malformed live-path binding fails before activity mutation', async () => {
  for (const [name, mutation] of [
    ['missing', "DELETE FROM activity_metadata WHERE key='database_binding_digest'"],
    ['malformed', "UPDATE activity_metadata SET value='not-a-digest' WHERE key='database_binding_digest'"],
  ]) {
    const directory = tempDir(`activity-path-binding-${name}`);
    const databasePath = path.join(directory, 'core.sqlite');
    const core = createICoreServer({ databasePath, activityAdminSecret: OWNER_SECRET });
    await core.close();
    const corrupt = new DatabaseSync(databasePath);
    corrupt.exec(mutation);
    const before = {
      claim: corrupt.prepare('SELECT * FROM activity_runtime_claim').get(),
      changes: corrupt.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
      highWater: corrupt.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
    };
    corrupt.close();
    assertActivityError(
      () => createICoreServer({ databasePath, activityAdminSecret: OWNER_SECRET }),
      'activity_database_binding_invalid',
    );
    const after = new DatabaseSync(databasePath, { readOnly: true });
    assert.deepEqual(after.prepare('SELECT * FROM activity_runtime_claim').get(), before.claim);
    assert.equal(after.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value, before.changes);
    assert.equal(after.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value, before.highWater);
    after.close();
    rmSync(directory, { recursive: true, force: true });
  }
});

test('invalid TLS material and an occupied port release startup resources without creating a false activity gap', async () => {
  const directory = tempDir('activity-startup-cleanup');
  const tlsDatabasePath = path.join(directory, 'tls.sqlite');
  const certPath = path.join(directory, 'invalid-cert.pem');
  const keyPath = path.join(directory, 'invalid-key.pem');
  writeFileSync(certPath, 'not a certificate');
  writeFileSync(keyPath, 'not a private key');
  assert.throws(() => createICoreServer({
    databasePath: tlsDatabasePath,
    certPath,
    keyPath,
    activityAdminSecret: OWNER_SECRET,
    shortcutMailRelay: {
      tokenHash: createHash('sha256').update('startup-relay-token').digest('hex'),
      close() { throw new Error('synthetic relay close failure'); },
    },
    ownsShortcutMailRelay: true,
  }));
  let recovered = createICoreServer({ databasePath: tlsDatabasePath, activityAdminSecret: OWNER_SECRET });
  await recovered.listen({ port: 0 });
  assert.equal(recovered.store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value, 0);
  assert.equal(recovered.store.db.prepare('SELECT runtime_id FROM activity_runtime_claim').get().runtime_id.length > 0, true);
  await recovered.close();

  const portDatabasePath = path.join(directory, 'port.sqlite');
  const blocker = createNetServer();
  await new Promise((resolve) => blocker.listen(0, '127.0.0.1', resolve));
  const occupiedPort = blocker.address().port;
  const blocked = createICoreServer({ databasePath: portDatabasePath, activityAdminSecret: OWNER_SECRET });
  await assert.rejects(blocked.listen({ port: occupiedPort }), (error) => error?.code === 'EADDRINUSE');
  const afterBlocked = new DatabaseSync(portDatabasePath, { readOnly: true });
  assert.equal(afterBlocked.prepare('SELECT runtime_id FROM activity_runtime_claim').get().runtime_id, '');
  assert.equal(afterBlocked.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value, 0);
  afterBlocked.close();
  await new Promise((resolve, reject) => blocker.close((error) => error ? reject(error) : resolve()));
  recovered = createICoreServer({ databasePath: portDatabasePath, activityAdminSecret: OWNER_SECRET });
  await recovered.listen({ port: 0 });
  assert.equal(recovered.store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value, 0);
  await recovered.close();
  rmSync(directory, { recursive: true, force: true });
});

test('close attempts server, owned relay and activity store cleanup even when earlier cleanup fails', async () => {
  const directory = tempDir('activity-close-finally');
  const databasePath = path.join(directory, 'core.sqlite');
  const relay = {
    tokenHash: createHash('sha256').update('close-relay-token').digest('hex'),
    close() { throw new Error('synthetic relay close failure'); },
  };
  const core = createICoreServer({
    databasePath,
    activityAdminSecret: OWNER_SECRET,
    shortcutMailRelay: relay,
    ownsShortcutMailRelay: true,
  });
  await core.listen({ port: 0 });
  const realClose = core.server.close.bind(core.server);
  core.server.close = (callback) => realClose(() => callback(new Error('synthetic server close failure')));
  await assert.rejects(core.close(), /synthetic server close failure/);
  const claim = new DatabaseSync(databasePath, { readOnly: true });
  assert.equal(claim.prepare('SELECT runtime_id FROM activity_runtime_claim').get().runtime_id, '');
  claim.close();
  const reopened = createICoreServer({ databasePath, activityAdminSecret: OWNER_SECRET });
  await reopened.listen({ port: 0 });
  await reopened.close();
  let externalRelayCloses = 0;
  const external = createICoreServer({
    databasePath: path.join(directory, 'external-relay.sqlite'),
    shortcutMailRelay: {
      tokenHash: createHash('sha256').update('external-relay-token').digest('hex'),
      close() { externalRelayCloses += 1; },
    },
    ownsShortcutMailRelay: false,
  });
  await external.listen({ port: 0 });
  await external.close();
  assert.equal(externalRelayCloses, 0);
  rmSync(directory, { recursive: true, force: true });
});

test('production signal shutdown is idempotent and permits a clean same-path restart', async () => {
  const directory = tempDir('activity-graceful-signal');
  const databasePath = path.join(directory, 'core.sqlite');
  const core = createICoreServer({ databasePath, activityAdminSecret: OWNER_SECRET });
  await core.listen({ port: 0 });
  const processObject = new EventEmitter();
  processObject.exitCode = 0;
  const lifecycle = installICoreGracefulShutdown(core, { processObject, onError: () => {} });
  processObject.emit('SIGTERM');
  const first = lifecycle.shutdown();
  const second = lifecycle.shutdown();
  assert.equal(first, second);
  await first;
  assert.equal(processObject.listenerCount('SIGINT'), 0);
  assert.equal(processObject.listenerCount('SIGTERM'), 0);
  const claim = new DatabaseSync(databasePath, { readOnly: true });
  assert.equal(claim.prepare('SELECT runtime_id FROM activity_runtime_claim').get().runtime_id, '');
  claim.close();

  const restarted = createICoreServer({ databasePath, activityAdminSecret: OWNER_SECRET });
  await restarted.listen({ port: 0 });
  assert.equal(restarted.store.health({ activityOwnerConfigured: true }).activity.control_plane_available, true);
  await restarted.close();
  rmSync(directory, { recursive: true, force: true });
});

test('owner bootstrap refuses reuse of worker secret or device pairing code', () => {
  const directory = tempDir('activity-owner-separation');
  assertActivityError(() => createICoreServer({
    databasePath: path.join(directory, 'a.sqlite'),
    workerSecret: OWNER_SECRET,
    activityAdminSecret: OWNER_SECRET,
  }), 'authority_secret_conflict');
  assertActivityError(() => createICoreServer({
    databasePath: path.join(directory, 'b.sqlite'),
    pairingCode: OWNER_SECRET,
    activityAdminSecret: OWNER_SECRET,
  }), 'authority_secret_conflict');
  assert.equal(existsSync(path.join(directory, 'a.sqlite')), false);
  assert.equal(existsSync(path.join(directory, 'b.sqlite')), false);
  rmSync(directory, { recursive: true, force: true });
});

test('activity principals are physically separate from device, worker and admin authority', async (t) => {
  const directory = tempDir('activity-auth');
  const { baseUrl } = await startServer(t, directory);
  const probe = await pairProbeHttp(baseUrl);
  assert.equal(probe.status, 200);
  assert.deepEqual(probe.body.scopes, ['activity.write']);
  const probeToken = probe.body.probe_token;
  const reader = await jsonRequest(`${baseUrl}/v1/core/activity/readers/pair`, {
    method: 'POST', token: OWNER_SECRET,
    body: { installation_id: 'reader-a', display_name: 'reader', capabilities: ['activity.admin', 'chat.read'] },
  });
  assert.deepEqual(reader.body.scopes, ['activity.read_summary']);
  const device = await jsonRequest(`${baseUrl}/v1/core/devices/pair`, {
    method: 'POST', protocol: false,
    body: {
      device_id: 'full-client', display_name: 'full client', platform: 'test', client_version: '0.1',
      pairing_code: 'device-pairing-code', capabilities: ['activity.write', 'activity.admin'],
    },
  });
  assert.equal(device.status, 200);

  const chatRead = await jsonRequest(`${baseUrl}/v1/core/changes`, { token: probeToken });
  assert.equal(chatRead.status, 403);
  assert.equal(chatRead.body.error.code, 'chat_read_forbidden');
  const chatSubmit = await jsonRequest(`${baseUrl}/v1/core/chat/messages`, { method: 'POST', token: probeToken, body: {} });
  assert.equal(chatSubmit.status, 403);
  assert.equal(chatSubmit.body.error.code, 'chat_read_forbidden');
  const chatAck = await jsonRequest(`${baseUrl}/v1/core/devices/ack`, { method: 'POST', token: probeToken, body: {} });
  assert.equal(chatAck.status, 403);
  assert.equal(chatAck.body.error.code, 'chat_read_forbidden');
  assert.equal((await jsonRequest(`${baseUrl}/v1/core/workers/leases`, { method: 'POST', token: probeToken, body: {} })).status, 401);
  assert.equal((await jsonRequest(`${baseUrl}/v1/core/activity/summary`, { token: probeToken })).status, 403);
  const adminExport = await jsonRequest(`${baseUrl}/v1/core/activity/admin/export`, { token: probeToken });
  assert.equal(adminExport.status, 403);
  assert.equal(adminExport.body.error.code, 'admin_escalation_forbidden');
  assert.equal((await jsonRequest(`${baseUrl}/v1/core/activity/summary`, { token: device.body.device_token })).status, 401);
  assert.equal((await jsonRequest(`${baseUrl}/v1/core/activity/summary`)).status, 401);
  assert.equal((await jsonRequest(`${baseUrl}/v1/core/activity/summary`, { token: 'wrong-activity-token' })).status, 401);
  assert.equal((await jsonRequest(`${baseUrl}/v1/core/activity/events`, { method: 'POST', token: reader.body.reader_token, body: { events: [] } })).status, 403);
  const adminRevoke = await pairProbeHttp(baseUrl, { probe_id: 'probe-b' })
    .then(() => jsonRequest(`${baseUrl}/v1/core/activity/probes/probe-a/revoke`, { method: 'POST', token: probeToken }));
  assert.equal(adminRevoke.status, 403);
  assert.equal(adminRevoke.body.error.code, 'admin_escalation_forbidden');
});

test('issued event prefixes bind canonical decimal sequences across rotation, deletion and collisions', () => {
  const directory = tempDir('activity-event-prefix');
  const fixedPrefix = 'P'.repeat(22);
  const store = new ICoreStore(path.join(directory, 'core.sqlite'), {
    activityEnabled: true,
    clock: () => 1_000_000,
    eventIdPrefixFactory: () => fixedPrefix,
  });
  const paired = pairProbe(store);
  assert.equal(paired.event_id_prefix, fixedPrefix);
  assert.equal(store.activity.authenticate(fixedPrefix), null);
  const principal = store.activity.authenticate(paired.probe_token);
  assert.equal(store.activity.appendEvents(principal, { events: [event({ originSequence: 0 })] }).results[0].status, 'accepted');
  for (const wireEventId of [
    `${fixedPrefix}.00`, `${fixedPrefix}.+1`, `${fixedPrefix}.01`, `${'S'.repeat(22)}.1`, `${fixedPrefix}.2`,
  ]) {
    const expected = wireEventId === `${fixedPrefix}.2` || wireEventId.startsWith('S')
      ? 'event_id_binding_mismatch'
      : 'invalid_event_id';
    assertActivityError(() => store.activity.appendEvents(principal, {
      events: [event({ wireEventId, originSequence: 1 })],
    }), expected);
  }
  store.db.prepare("UPDATE activity_rate_limits SET accepted_count=120 WHERE probe_id='probe-a'").run();
  assertActivityError(() => store.activity.appendEvents(principal, {
    events: [event({
      wireEventId: `${'S'.repeat(22)}.1`, originSequence: 1, signalAt: 0, ttl: 1,
      coverageStart: 0, coverageEnd: 0,
    })],
  }), 'event_id_binding_mismatch');
  const beforeCollision = {
    principals: store.db.prepare('SELECT COUNT(*) AS value FROM activity_principals').get().value,
    changes: store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
    highWater: store.db.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
  };
  assertActivityError(() => pairProbe(store, { deviceId: 'device-b', probeId: 'probe-b' }), 'event_id_prefix_collision');
  assert.deepEqual({
    principals: store.db.prepare('SELECT COUNT(*) AS value FROM activity_principals').get().value,
    changes: store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
    highWater: store.db.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
  }, beforeCollision);
  const rotated = store.activity.rotatePrincipal(paired.principal_id);
  assert.equal(rotated.event_id_prefix, fixedPrefix);
  store.activity.deleteProbe('probe-a');
  assertActivityError(() => pairProbe(store), 'probe_already_paired');
  assertActivityError(() => pairProbe(store, { deviceId: 'device-c', probeId: 'probe-c' }), 'event_id_prefix_collision');
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_replay_lineage_floors').get().value, 1);
  const retired = store.db.prepare('SELECT * FROM activity_replay_lineage_floors').get();
  store.db.prepare('DELETE FROM activity_replay_lineage_floors').run();
  assert.equal(store.activity.schemaStatus().ready, false);
  store.db.prepare('INSERT INTO activity_replay_lineage_floors(lineage_digest,floor_digest) VALUES (?,?)')
    .run(retired.lineage_digest, retired.floor_digest);
  assert.equal(activitySchemaStatus(store.db).ready, true);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('HTTP activity vertical slice pairs, ingests, summarizes and rejects identical replay after revoke', async (t) => {
  const directory = tempDir('activity-http-slice');
  const nowRef = { value: 1_000_000 };
  const { core, baseUrl } = await startServer(t, directory, { nowRef });
  const probe = await pairProbeHttp(baseUrl);
  const reader = await jsonRequest(`${baseUrl}/v1/core/activity/readers/pair`, {
    method: 'POST', token: OWNER_SECRET,
    body: { installation_id: 'reader-a', display_name: 'reader', capabilities: [] },
  });
  const accepted = await jsonRequest(`${baseUrl}/v1/core/activity/events`, {
    method: 'POST', token: probe.body.probe_token, body: { events: [event()] },
  });
  assert.equal(accepted.status, 200);
  assert.equal(accepted.body.results[0].received_at_ms, nowRef.value);
  const summary = await jsonRequest(`${baseUrl}/v1/core/activity/summary`, { token: reader.body.reader_token });
  assert.equal(summary.body.devices[0].state, 'active');
  assert.equal(core.store.db.prepare('SELECT COUNT(*) AS value FROM change_events').get().value, 0);
  const revoked = await jsonRequest(`${baseUrl}/v1/core/activity/probes/probe-a/revoke`, {
    method: 'POST', token: OWNER_SECRET,
  });
  assert.equal(revoked.status, 200);
  const replay = await jsonRequest(`${baseUrl}/v1/core/activity/events`, {
    method: 'POST', token: probe.body.probe_token, body: { events: [event()] },
  });
  assert.equal(replay.status, 401);
  assert.equal(replay.body.error.code, 'revoked_replay');
  const after = await jsonRequest(`${baseUrl}/v1/core/activity/summary`, { token: reader.body.reader_token });
  assert.equal(after.body.devices[0].state, 'unknown');
  assert.equal(after.body.devices[0].sources[0].credential_state, 'revoked');
});

test('append stamps received time, is double-key idempotent and never touches chat data or cursor', () => {
  const directory = tempDir('activity-idempotency');
  const nowRef = { value: 1_000_000 };
  const store = openStore(directory, nowRef);
  const paired = pairProbe(store);
  const principal = store.activity.authenticate(paired.probe_token);
  const chatCursorBefore = store.encodeCursor(0);
  const countsBefore = {
    changes: store.db.prepare('SELECT COUNT(*) AS value FROM change_events').get().value,
    chat: store.db.prepare('SELECT COUNT(*) AS value FROM chat_messages').get().value,
    jobs: store.db.prepare('SELECT COUNT(*) AS value FROM companion_reply_jobs').get().value,
  };
  const payload = event();
  const accepted = store.activity.appendEvents(principal, { events: [payload] });
  const duplicate = store.activity.appendEvents(principal, { events: [{ ...payload, payload: { ...payload.payload } }] });
  assert.equal(accepted.results[0].status, 'accepted');
  assert.equal(accepted.results[0].occurred_at_ms, payload.signal_at_ms);
  assert.equal(accepted.results[0].received_at_ms, nowRef.value);
  assert.equal(duplicate.results[0].status, 'duplicate');
  assert.equal(duplicate.results[0].receipt_id, accepted.results[0].receipt_id);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 1);
  assert.deepEqual({
    changes: store.db.prepare('SELECT COUNT(*) AS value FROM change_events').get().value,
    chat: store.db.prepare('SELECT COUNT(*) AS value FROM chat_messages').get().value,
    jobs: store.db.prepare('SELECT COUNT(*) AS value FROM companion_reply_jobs').get().value,
  }, countsBefore);
  assert.equal(store.encodeCursor(0), chatCursorBefore);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('either immutable key conflicts and a mixed invalid batch has zero partial acceptance or audit', () => {
  const directory = tempDir('activity-atomic');
  const store = openStore(directory);
  const paired = pairProbe(store);
  const principal = store.activity.authenticate(paired.probe_token);
  store.activity.appendEvents(principal, { events: [event()] });
  assertActivityError(() => store.activity.appendEvents(principal, { events: [event({ payload: { unexpected: true } })] }), 'unknown_field');
  assertActivityError(() => store.activity.appendEvents(principal, { events: [event({ kind: 'session.locked' })] }), 'idempotency_conflict');
  assertActivityError(() => store.activity.appendEvents(principal, { events: [event({ kind: 'session.locked' })] }), 'idempotency_conflict');
  const eventCount = store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value;
  const auditCount = store.db.prepare("SELECT COUNT(*) AS value FROM activity_audit WHERE action='events.accepted'").get().value;
  assertActivityError(() => store.activity.appendEvents(principal, {
    events: [
      event({ originSequence: 2 }),
      event({ originSequence: 3, signalAt: 50_000, ttl: 1 }),
    ],
  }), 'ttl_expired');
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, eventCount);
  assert.equal(store.db.prepare("SELECT COUNT(*) AS value FROM activity_audit WHERE action='events.accepted'").get().value, auditCount);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('cross-device, source, coverage, capability and server-received-time spoofing fail before data lookup', () => {
  const directory = tempDir('activity-binding');
  const store = openStore(directory);
  const paired = pairProbe(store, { allowedKinds: ['session.unlocked'] });
  const principal = store.activity.authenticate(paired.probe_token);
  assertActivityError(() => store.activity.appendEvents(principal, { events: [event({ deviceId: 'device-b' })] }), 'identity_binding_mismatch');
  assertActivityError(() => store.activity.appendEvents(principal, { events: [event({ probeId: 'probe-b' })] }), 'identity_binding_mismatch');
  assertActivityError(() => store.activity.appendEvents(principal, { events: [event({ source: 'claimed-admin' })] }), 'invalid_request');
  assertActivityError(() => store.activity.appendEvents(principal, { events: [event({ coverageMode: 'heartbeat_only' })] }), 'source_binding_mismatch');
  assertActivityError(() => store.activity.appendEvents(principal, { events: [event({ kind: 'session.locked' })] }), 'scope_denied');
  assertActivityError(() => store.activity.appendEvents(principal, { events: [{ ...event(), received_at_ms: 1 }] }), 'unknown_field');
  assertActivityError(() => store.activity.appendEvents(principal, { events: [{ ...event(), activity_admin: true }] }), 'unknown_field');
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 0);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('coverage interval registration and signal-window containment fail closed atomically', () => {
  const directory = tempDir('activity-coverage-binding');
  const store = openStore(directory);
  const paired = pairProbe(store);
  const principal = store.activity.authenticate(paired.probe_token);
  const auditBefore = store.db.prepare('SELECT COUNT(*) AS value FROM activity_audit').get().value;
  assertActivityError(
    () => store.activity.appendEvents(principal, { events: [event({ coverageInterval: 60_000 })] }),
    'source_binding_mismatch',
  );
  assertActivityError(
    () => store.activity.appendEvents(principal, {
      events: [
        event({ originSequence: 1 }),
        event({ originSequence: 2, coverageStart: 900_000, coverageEnd: 950_000 }),
      ],
    }),
    'invalid_coverage',
  );
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 0);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value, 0);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_audit').get().value, auditBefore);

  const mda0Case = MDA0_LIMITS_FIXTURE.cases.find((item) => item.name === 'batch_atomic_rejection');
  const mda0Event = mda0Case.batch?.[0] ?? mda0Case.steps[0].event_templates[0];
  const discrete = pairProbe(store, {
    deviceId: mda0Event.device_id,
    probeId: mda0Event.probe_id,
    source: mda0Event.source,
    coverageMode: 'discrete_best_effort',
  });
  const discreteResult = store.activity.appendEvents(
    store.activity.authenticate(discrete.probe_token),
    { events: [{ ...mda0Event, event_id: `${discrete.event_id_prefix}.${mda0Event.origin_sequence}` }] },
    mda0Event.signal_at_ms,
  );
  assert.equal(discreteResult.results[0].status, 'accepted');

  const longTtl = pairProbe(store, {
    deviceId: 'device-long-ttl',
    probeId: 'probe-long-ttl',
    source: 'windows_last_input',
    expirySlo: 60_000,
  });
  const longTtlEvent = event({
    deviceId: 'device-long-ttl',
    probeId: 'probe-long-ttl',
    source: 'windows_last_input',
    signalAt: mda0Event.signal_at_ms,
    ttl: ACTIVITY_RAW_RETENTION_MS,
  });
  const longTtlResult = store.activity.appendEvents(
    store.activity.authenticate(longTtl.probe_token),
    { events: [longTtlEvent] },
    mda0Event.signal_at_ms + 120_000,
  );
  assert.equal(longTtlResult.results[0].status, 'accepted');
  assert.equal(longTtlResult.results[0].coverage_status, 'stale');
  const reader = pairReader(store);
  const summary = store.activity.summary(store.activity.authenticate(reader.reader_token), 1_120_000);
  const longTtlSummary = summary.devices.find((item) => item.device_id === 'device-long-ttl');
  assert.equal(longTtlSummary.state, 'unknown');
  assert.equal(longTtlSummary.sources[0].freshness.fresh, false);
  assert.equal(longTtlSummary.sources[0].ttl_ms, 60_000);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('closed payload vocabulary and batch/envelope limits reject private or oversized data atomically', () => {
  const directory = tempDir('activity-limits');
  const store = openStore(directory);
  const paired = pairProbe(store);
  const principal = store.activity.authenticate(paired.probe_token);
  assertActivityError(() => store.activity.appendEvents(principal, {
    events: [event({ kind: 'app.category_active', payload: { category: 'chat', app_name: 'private.app' } })],
  }), 'unknown_field');
  assertActivityError(() => store.activity.appendEvents(principal, {
    events: [event({ kind: 'probe.error', payload: { code: 'x'.repeat(5000) } })],
  }), 'payload_too_large');
  assertActivityError(() => store.activity.appendEvents(principal, {
    events: Array.from({ length: 101 }, (_, index) => event({ originSequence: index })),
  }), 'batch_too_large');
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 0);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('HTTP activity ingress enforces a bounded request body before JSON reaches the store', async (t) => {
  const directory = tempDir('activity-http-limit');
  const { baseUrl } = await startServer(t, directory);
  const probe = await pairProbeHttp(baseUrl);
  const oversized = await jsonRequest(`${baseUrl}/v1/core/activity/events`, {
    method: 'POST',
    token: probe.body.probe_token,
    body: { padding: 'x'.repeat(600 * 1024) },
  });
  assert.equal(oversized.status, 413);
  assert.equal(oversized.body.error.code, 'request_too_large');
});

test('HTTP activity validation preserves unsupported, missing-field and payload-limit errors', async (t) => {
  const directory = tempDir('activity-http-validation');
  const { core, baseUrl } = await startServer(t, directory);
  const probe = await pairProbeHttp(baseUrl);

  const unsupported = await jsonRequest(`${baseUrl}/v1/core/activity/events`, {
    method: 'POST', token: probe.body.probe_token,
    body: { events: [event({ kind: 'window.title' })] },
  });
  assert.equal(unsupported.status, 400);
  assert.equal(unsupported.body.error.code, 'unsupported_kind');

  const missingSignal = event({ originSequence: 2 });
  delete missingSignal.signal_at_ms;
  const missing = await jsonRequest(`${baseUrl}/v1/core/activity/events`, {
    method: 'POST', token: probe.body.probe_token, body: { events: [missingSignal] },
  });
  assert.equal(missing.status, 400);
  assert.equal(missing.body.error.code, 'missing_required_field');
  assert.deepEqual(missing.body.error.details, { field: 'signal_at_ms' });

  const emptyPayloadBytes = Buffer.byteLength(JSON.stringify({ class: 'input_or_touch', padding: '' }), 'utf8');
  const oversizedPayload = {
    class: 'input_or_touch',
    padding: 'x'.repeat(4097 - emptyPayloadBytes),
  };
  assert.equal(Buffer.byteLength(JSON.stringify(oversizedPayload), 'utf8'), 4097);
  const payloadLimit = await jsonRequest(`${baseUrl}/v1/core/activity/events`, {
    method: 'POST', token: probe.body.probe_token,
    body: { events: [event({ originSequence: 3, kind: 'input.activity', payload: oversizedPayload })] },
  });
  assert.equal(payloadLimit.status, 413);
  assert.equal(payloadLimit.body.error.code, 'payload_too_large');
  assert.equal(core.store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 0);
});

test('24-hour backfill is accepted, expired TTL is rejected, and future/regressed/out-of-order events stay honest', () => {
  const directory = tempDir('activity-clock');
  const nowRef = { value: 100_000_000 };
  const store = openStore(directory, nowRef);
  const paired = pairProbe(store);
  const principal = store.activity.authenticate(paired.probe_token);
  const backfill = event({ originSequence: 42, signalAt: nowRef.value - ACTIVITY_RAW_RETENTION_MS, ttl: ACTIVITY_RAW_RETENTION_MS });
  assert.equal(store.activity.appendEvents(principal, { events: [backfill] }).results[0].status, 'accepted');
  assertActivityError(() => store.activity.appendEvents(principal, { events: [event({ originSequence: 43, signalAt: nowRef.value - 1001, ttl: 1000 })] }), 'ttl_expired');
  const future = store.activity.appendEvents(principal, { events: [event({ originSequence: 44, signalAt: nowRef.value + 600_000 })] }).results[0];
  assert.equal(future.clock_health, 'future_skew');
  const regression = store.activity.appendEvents(principal, { events: [event({ originSequence: 41, signalAt: nowRef.value - 1000 })] }).results[0];
  assert.equal(regression.clock_health, 'healthy');
  assert.deepEqual(regression.sequence_diagnostics, ['sequence_regression', 'sequence_coverage_gap']);
  const reader = pairReader(store);
  const summary = store.activity.summary(store.activity.authenticate(reader.reader_token), nowRef.value);
  const source = summary.devices[0].sources[0];
  assert.equal(source.state, 'unknown');
  assert.notEqual(source.occurred_at_ms, regression.occurred_at_ms);
  assert.equal(JSON.stringify(summary).includes('asleep'), false);
  assert.equal(JSON.stringify(summary).includes('sleep_candidate'), false);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('derived timestamp overflow rejects the entire batch before SQLite mutation', () => {
  const directory = tempDir('activity-derived-time-overflow');
  const store = openStore(directory);
  const probe = pairProbe(store);
  const principal = store.activity.authenticate(probe.probe_token);
  const valid = event({ originSequence: 1 });
  const overflow = event({
    originSequence: Number.MAX_SAFE_INTEGER,
    signalAt: Number.MAX_SAFE_INTEGER,
    coverageStart: Number.MAX_SAFE_INTEGER,
    coverageEnd: Number.MAX_SAFE_INTEGER,
  });
  assertActivityError(
    () => store.activity.appendEvents(principal, { events: [valid, overflow] }),
    'invalid_time_range',
  );
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 0);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value, 0);
  assert.equal(store.activity.schemaStatus().ready, true);
  store.close();
  const reopened = new ICoreStore(path.join(directory, 'core.sqlite'), {
    activityEnabled: true,
    clock: () => 1_000_000,
  });
  assert.equal(reopened.activity.schemaStatus().ready, true);
  reopened.close();
  rmSync(directory, { recursive: true, force: true });
});

test('out-of-order delivery is a separate receipt diagnostic and does not masquerade as a clock fault', () => {
  const directory = tempDir('activity-out-of-order-projection');
  const nowRef = { value: 2_000_000 };
  const store = openStore(directory, nowRef);
  const probe = pairProbe(store);
  const principal = store.activity.authenticate(probe.probe_token);
  store.activity.appendEvents(principal, { events: [event({ originSequence: 10, signalAt: nowRef.value })] });
  const before = store.db.prepare(`SELECT current_event_id,state,occurred_at_ms,received_at_ms,
    expires_at_ms,coverage_status,clock_health,status_reason,last_server_sequence
    FROM activity_projections WHERE probe_id='probe-a'`).get();
  const outOfOrder = store.activity.appendEvents(principal, {
    events: [event({ originSequence: 9, signalAt: nowRef.value - 1_000 })],
  }, nowRef.value + 1).results[0];
  const after = store.db.prepare(`SELECT current_event_id,state,occurred_at_ms,received_at_ms,
    expires_at_ms,coverage_status,clock_health,status_reason,last_server_sequence
    FROM activity_projections WHERE probe_id='probe-a'`).get();
  assert.equal(after.current_event_id, before.current_event_id);
  assert.equal(after.occurred_at_ms, before.occurred_at_ms);
  assert.equal(after.last_server_sequence, before.last_server_sequence);
  assert.equal(after.state, 'active');
  assert.equal(after.clock_health, 'healthy');
  assert.equal(after.status_reason, 'fresh_signal');
  assert.equal(outOfOrder.clock_health, 'healthy');
  assert.deepEqual(outOfOrder.sequence_diagnostics, ['sequence_regression']);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 2);
  store.activity.appendEvents(principal, {
    events: [event({ originSequence: 11, signalAt: nowRef.value - 2_000 })],
  }, nowRef.value + 2);
  const fault = store.db.prepare("SELECT state,clock_health,status_reason FROM activity_projections WHERE probe_id='probe-a'").get();
  assert.deepEqual({ ...fault }, { state: 'unknown', clock_health: 'clock_regression', status_reason: 'clock_regression' });
  store.activity.appendEvents(principal, {
    events: [event({ originSequence: 12, signalAt: nowRef.value + 1 })],
  }, nowRef.value + 2);
  assert.equal(store.db.prepare("SELECT state FROM activity_projections WHERE probe_id='probe-a'").get().state, 'active');
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('coverage gaps, missing permission, network-only evidence and TTL expiry never become quiet or sleep', () => {
  const directory = tempDir('activity-coverage');
  const nowRef = { value: 2_000_000 };
  const store = openStore(directory, nowRef);
  const paired = pairProbe(store);
  const principal = store.activity.authenticate(paired.probe_token);
  store.activity.appendEvents(principal, { events: [event({ originSequence: 1, kind: 'network.present', signalAt: nowRef.value })] });
  const reader = pairReader(store);
  const readerPrincipal = store.activity.authenticate(reader.reader_token);
  assert.equal(store.activity.summary(readerPrincipal).devices[0].state, 'network_only');
  store.activity.appendEvents(principal, { events: [event({ originSequence: 3, signalAt: nowRef.value + 1 })] });
  assert.equal(store.activity.summary(readerPrincipal).devices[0].state, 'unknown');
  store.activity.appendEvents(principal, { events: [event({ originSequence: 4, kind: 'probe.permission_changed', signalAt: nowRef.value + 2, payload: { capability: 'usage_events', available: false } })] });
  assert.equal(store.activity.summary(readerPrincipal).devices[0].state, 'unknown');
  nowRef.value += 400_000;
  const serialized = JSON.stringify(store.activity.summary(readerPrincipal));
  assert.equal(serialized.includes('quiet'), false);
  assert.equal(serialized.includes('asleep'), false);
  assert.equal(JSON.parse(serialized).devices[0].state, 'unknown');
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('gap fill reports sequence regression and recomputes the latest projection in logical order', () => {
  const directory = tempDir('activity-persistent-gap');
  const nowRef = { value: 1_000_000 };
  const store = openStore(directory, nowRef);
  const probe = pairProbe(store);
  const reader = pairReader(store);
  const principal = store.activity.authenticate(probe.probe_token);
  const readerPrincipal = store.activity.authenticate(reader.reader_token);
  store.activity.appendEvents(principal, { events: [event({ originSequence: 1 })] });
  store.activity.appendEvents(principal, {
    events: [event({ originSequence: 3, signalAt: 1_000_003, kind: 'session.locked' })],
  });
  let source = store.activity.summary(readerPrincipal).devices[0].sources[0];
  assert.equal(source.state, 'unknown');
  assert.equal(source.coverage_status, 'gap');
  assert.equal(source.status_reason, 'coverage_gap');
  assert.equal(source.occurred_at_ms, 1_000_003);

  const fill = store.activity.appendEvents(principal, {
    events: [event({ originSequence: 2, signalAt: 1_000_002 })],
  }).results[0];
  assert.equal(fill.clock_health, 'healthy');
  assert.deepEqual(fill.sequence_diagnostics, ['sequence_regression']);
  source = store.activity.summary(readerPrincipal).devices[0].sources[0];
  assert.equal(source.state, 'locked');
  assert.equal(source.coverage_status, 'covered');
  assert.equal(source.status_reason, 'fresh_signal');
  assert.equal(source.occurred_at_ms, 1_000_003);
  assert.equal(source.received_at_ms, 1_000_000);
  assert.equal(store.activity.schemaStatus().ready, true);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('HTTP receipts expose 1-3-2 coverage and retain the original observations on retries', async (t) => {
  const directory = tempDir('activity-http-gap-receipts');
  const { baseUrl } = await startServer(t, directory);
  const probe = await pairProbeHttp(baseUrl);
  const reader = await jsonRequest(`${baseUrl}/v1/core/activity/readers/pair`, {
    method: 'POST', token: OWNER_SECRET,
    body: { installation_id: 'reader-a', display_name: 'reader', capabilities: [] },
  });
  const inputs = [event(), event({ originSequence: 3, signalAt: 1_000_003, kind: 'session.locked' }),
    event({ originSequence: 2, signalAt: 1_000_002 })];
  const receipts = [];
  for (const input of inputs) {
    const response = await jsonRequest(`${baseUrl}/v1/core/activity/events`, {
      method: 'POST', token: probe.body.probe_token, body: { events: [input] },
    });
    assert.equal(response.status, 200);
    receipts.push(response.body.results[0]);
  }
  assert.deepEqual(receipts.map((row) => row.sequence_diagnostics), [[], ['sequence_coverage_gap'], ['sequence_regression']]);
  assert.deepEqual(receipts.map((row) => row.sequence_coverage), [
    { highest_seen: 1, contiguous_through: 1, missing: [], observed_from: 1, retained_origin_floor: null, missing_truncated: false },
    { highest_seen: 3, contiguous_through: 1, missing: [2], observed_from: 1, retained_origin_floor: null, missing_truncated: false },
    { highest_seen: 3, contiguous_through: 3, missing: [], observed_from: 1, retained_origin_floor: null, missing_truncated: false },
  ]);
  assert.equal(receipts[2].clock_health, 'healthy');
  assert.equal(receipts[2].projection_recomputed_through_origin_sequence, 3);
  const summary = await jsonRequest(`${baseUrl}/v1/core/activity/summary`, { token: reader.body.reader_token });
  assert.equal(summary.body.devices[0].state, 'locked');
  for (let index = 0; index < inputs.length; index++) {
    const retry = await jsonRequest(`${baseUrl}/v1/core/activity/events`, {
      method: 'POST', token: probe.body.probe_token, body: { events: [inputs[index]] },
    });
    assert.deepEqual(retry.body.results[0], { ...receipts[index], status: 'duplicate' });
  }
  const observations = receipts.map(({ sequence_diagnostics, sequence_coverage, projection_recomputed_through_origin_sequence }) => (
    { sequence_diagnostics, sequence_coverage, projection_recomputed_through_origin_sequence }
  ));
  const serialized = JSON.stringify(observations);
  assert.equal(serialized.includes(probe.body.probe_token), false);
  assert.equal(serialized.includes(probe.body.event_id_prefix), false);
  assert.equal(/integrity_signature|payload|device_id|probe_id|Bearer/.test(serialized), false);
});

test('receipt coverage is atomic, bounded at safe integer gaps, and honest about zero and retention', () => {
  const directory = tempDir('activity-receipt-boundaries');
  const nowRef = { value: 1_000_000 };
  let store = openStore(directory, nowRef);
  const probe = pairProbe(store);
  let principal = store.activity.authenticate(probe.probe_token);
  const zero = event({ originSequence: 0 });
  assert.equal(store.activity.appendEvents(principal, { events: [zero] }).results[0].sequence_coverage.contiguous_through, 0);
  nowRef.value += ACTIVITY_RAW_RETENTION_MS;
  store.activity.runRetention();
  const second = event({ originSequence: 2, signalAt: nowRef.value });
  const gap = store.activity.appendEvents(principal, { events: [second, second] }).results;
  assert.deepEqual(gap[1], { ...gap[0], status: 'duplicate' });
  assert.deepEqual(gap[0].sequence_coverage, {
    highest_seen: 2, contiguous_through: null, missing: [1], observed_from: 2, retained_origin_floor: 0, missing_truncated: false,
  });
  assertActivityError(() => store.activity.appendEvents(principal, { events: [zero] }), 'event_retained_out');
  const first = event({ originSequence: 1, signalAt: nowRef.value });
  const fill = store.activity.appendEvents(principal, { events: [first, first] }).results;
  assert.deepEqual(fill[1], { ...fill[0], status: 'duplicate' });
  assert.deepEqual(fill[0].sequence_diagnostics, ['sequence_regression']);
  assert.equal(fill[0].sequence_coverage.contiguous_through, 2);
  store.close();
  store = openStore(directory, nowRef);
  principal = store.activity.authenticate(probe.probe_token);
  assert.deepEqual(store.activity.appendEvents(principal, { events: [second] }).results[0], { ...gap[0], status: 'duplicate' });
  const huge = store.activity.appendEvents(principal, { events: [event({ originSequence: Number.MAX_SAFE_INTEGER, signalAt: nowRef.value })] }).results[0];
  assert.equal(huge.sequence_coverage.highest_seen, Number.MAX_SAFE_INTEGER);
  assert.equal(huge.sequence_coverage.contiguous_through, 2);
  assert.deepEqual(huge.sequence_coverage.missing, Array.from({ length: 128 }, (_, index) => index + 3));
  assert.equal(huge.sequence_coverage.missing_truncated, true);
  assert.equal(store.activity.schemaStatus().ready, true, JSON.stringify(store.activity.schemaStatus()));
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('retention of earlier receipts cannot rewrite a still-retained gap observation', () => {
  const directory = tempDir('activity-receipt-partial-retention');
  const nowRef = { value: 1_000_000 };
  const store = openStore(directory, nowRef);
  const probe = pairProbe(store);
  const principal = store.activity.authenticate(probe.probe_token);
  store.activity.appendEvents(principal, { events: [event()] });
  nowRef.value += 10;
  const input = event({ originSequence: 3, signalAt: nowRef.value });
  const receipt = store.activity.appendEvents(principal, { events: [input] }).results[0];
  nowRef.value = 1_000_000 + ACTIVITY_RAW_RETENTION_MS;
  assert.equal(store.activity.runRetention().removed_events, 1);
  assert.deepEqual(store.activity.appendEvents(principal, { events: [input] }).results[0], { ...receipt, status: 'duplicate' });
  assert.equal(store.activity.schemaStatus().ready, true);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('integrity v1 rejects change, raw and materialization corruption before restart or feed disclosure', () => {
  const scenarios = [
    ['accepted-tail-kind', "UPDATE activity_changes SET kind='chat.message',payload_json='{}' WHERE server_sequence=2"],
    ['accepted-middle-kind', "UPDATE activity_changes SET kind='chat.message',payload_json='{}' WHERE server_sequence=1"],
    ['accepted-device', "UPDATE activity_changes SET device_id='other-device' WHERE server_sequence=1"],
    ['accepted-time', 'UPDATE activity_changes SET occurred_at_ms=1000001 WHERE server_sequence=1'],
    ['receipt-observation', "UPDATE activity_changes SET payload_json=json_set(payload_json,'$.receipt_observation.sequence_coverage.highest_seen',999) WHERE server_sequence=1"],
    ['receipt-unknown-field', "UPDATE activity_changes SET payload_json=json_set(payload_json,'$.private_note','never-export') WHERE server_sequence=1"],
    ['lifecycle-kind', "UPDATE activity_changes SET kind='chat.message' WHERE kind='activity.probe.revoked'"],
    ['lifecycle-payload', "UPDATE activity_changes SET payload_json=json_set(payload_json,'$.snapshot_generation',1) WHERE kind='activity.probe.revoked'"],
    ['projection-missing', "DELETE FROM activity_projections WHERE probe_id='probe-a'"],
    ['credential-unissued', 'UPDATE activity_events SET credential_generation=999 WHERE server_sequence=1'],
    ['projection-false-retention', "UPDATE activity_projections SET current_event_id=NULL,state='unknown',coverage_status='retention_expired',clock_health='unknown',status_reason='retention_expired'"],
    ['projection-false-restart', "UPDATE activity_projections SET state='unknown',coverage_status='core_restart_gap',clock_health='unknown',status_reason='core_restart_gap'"],
  ];
  for (const [name, sql] of scenarios) {
    const directory = tempDir(`activity-integrity-${name}`);
    const store = openStore(directory);
    const probe = pairProbe(store);
    const reader = pairReader(store);
    const principal = store.activity.authenticate(probe.probe_token);
    const readerPrincipal = store.activity.authenticate(reader.reader_token);
    store.activity.appendEvents(principal, { events: [event(), event({ originSequence: 2 })] });
    if (name.startsWith('lifecycle')) store.activity.revokeProbe('probe-a');
    store.db.exec(sql);
    assert.equal(store.activity.schemaStatus().ready, false, name);
    assert.equal(store.health({ activityOwnerConfigured: true }).activity.control_plane_available, false, name);
    assertActivityError(() => store.activity.adminExport(), 'activity_schema_not_ready');
    assertActivityError(() => store.activity.changes(readerPrincipal, reader.initial_cursor), 'activity_schema_not_ready');
    store.close();
    const databasePath = path.join(directory, 'core.sqlite');
    const digest = createHash('sha256').update(readFileSync(databasePath)).digest('hex');
    assertActivityError(() => openStore(directory), 'activity_migration_incomplete');
    assert.equal(createHash('sha256').update(readFileSync(databasePath)).digest('hex'), digest, name);
    rmSync(directory, { recursive: true, force: true });
  }
});

test('unversioned, rejected v1 or v2 and unknown integrity v5 candidates never auto-sign even an empty domain', () => {
  for (const mode of ['empty', 'nonempty', 'rejected-v1', 'rejected-v2', 'unknown']) {
    const directory = tempDir('activity-integrity-version');
    const store = openStore(directory);
    if (mode !== 'empty') {
      const probe = pairProbe(store);
      store.activity.appendEvents(store.activity.authenticate(probe.probe_token), { events: [event()] });
    }
    store.close();
    const databasePath = path.join(directory, 'core.sqlite');
    const db = new DatabaseSync(databasePath);
    if (mode === 'unknown') db.exec("UPDATE activity_metadata SET value='3' WHERE key='integrity_commitment_version'");
    else if (mode === 'rejected-v1') db.exec("UPDATE activity_metadata SET value='1' WHERE key='integrity_commitment_version'");
    else if (mode === 'rejected-v2') db.exec("UPDATE activity_metadata SET value='2' WHERE key='integrity_commitment_version'");
    else db.exec("DELETE FROM activity_metadata WHERE key='integrity_commitment_version'");
    assert.equal(activitySchemaStatus(db).reason, 'integrity_commitment_version_unsupported');
    db.close();
    const before = createHash('sha256').update(readFileSync(databasePath)).digest('hex');
    assertActivityError(() => openStore(directory), 'activity_integrity_upgrade_unsupported');
    assert.equal(createHash('sha256').update(readFileSync(databasePath)).digest('hex'), before);
    rmSync(directory, { recursive: true, force: true });
  }
});

test('Core clock rollback normalizes rotate, revoke and delete without invalid authority or restart', () => {
  for (const action of ['rotate', 'revoke', 'delete']) {
    const directory = tempDir(`activity-clock-rollback-${action}`);
    const nowRef = { value: 1_000_000 };
    let store = openStore(directory, nowRef);
    const probe = pairProbe(store);
    nowRef.value--;
    if (action === 'rotate') store.activity.rotatePrincipal(probe.principal_id);
    if (action === 'revoke') store.activity.revokeProbe('probe-a');
    if (action === 'delete') store.activity.deleteProbe('probe-a');
    assert.equal(store.activity.schemaStatus().ready, true, action);
    for (const row of store.db.prepare('SELECT issued_at_ms,revoked_at_ms FROM activity_credentials').all()) {
      assert.ok(row.issued_at_ms >= 1_000_000);
      assert.ok(row.revoked_at_ms == null || row.revoked_at_ms >= row.issued_at_ms);
    }
    store.close();
    store = openStore(directory, nowRef);
    assert.equal(store.activity.schemaStatus().ready, true, action);
    store.close();
    rmSync(directory, { recursive: true, force: true });
  }
});

test('committed event server time survives rollback across all lifecycle writes and clean restart', () => {
  for (const action of ['rotate', 'revoke', 'delete-probe', 'delete-device']) {
    const directory = tempDir(`activity-event-clock-rollback-${action}`);
    const nowRef = { value: 1_000_000 };
    let store = openStore(directory, nowRef);
    const probe = pairProbe(store);
    pairReader(store);
    const principal = store.activity.authenticate(probe.probe_token);
    nowRef.value += 100;
    store.activity.appendEvents(principal, { events: [event({ signalAt: nowRef.value })] });
    const committedTime = nowRef.value;
    assert.equal(Number(store.db.prepare("SELECT value FROM activity_metadata WHERE key='server_time_floor_ms'").get().value), committedTime);
    nowRef.value--;
    if (action === 'rotate') store.activity.rotatePrincipal(probe.principal_id);
    if (action === 'revoke') store.activity.revokeProbe('probe-a');
    if (action === 'delete-probe') store.activity.deleteProbe('probe-a');
    if (action === 'delete-device') store.activity.deleteDevice('device-a');
    assert.equal(store.activity.schemaStatus().ready, true, action);
    for (const row of store.db.prepare('SELECT issued_at_ms,revoked_at_ms FROM activity_credentials').all()) {
      assert.ok(row.revoked_at_ms == null || row.revoked_at_ms >= committedTime, action);
      assert.ok(row.revoked_at_ms == null || row.revoked_at_ms >= row.issued_at_ms, action);
    }
    for (const row of store.db.prepare('SELECT occurred_at_ms FROM activity_changes').all()) {
      assert.ok(row.occurred_at_ms >= committedTime, action);
    }
    const lease = store.db.prepare('SELECT lease_expires_at_ms FROM activity_runtime_claim').get().lease_expires_at_ms;
    assert.ok(lease > committedTime, action);
    store.close();
    store = openStore(directory, nowRef);
    assert.equal(store.activity.schemaStatus().ready, true, action);
    assert.equal(Number(store.db.prepare("SELECT value FROM activity_metadata WHERE key='server_time_floor_ms'").get().value), committedTime);
    store.close();
    rmSync(directory, { recursive: true, force: true });
  }
});

test('late gap evidence after clean restart derives a healthy clock and heals in logical order', () => {
  for (const initial of [[3], [1, 4]]) {
    const directory = tempDir('activity-restart-late-gap');
    const nowRef = { value: 1_100_000 };
    let store = openStore(directory, nowRef);
    const paired = pairProbe(store);
    const pairedReader = pairReader(store);
    const input = (sequence) => event({ originSequence: sequence, signalAt: 1_000_000 + sequence * 1_000,
      kind: sequence === 4 ? 'session.locked' : 'session.unlocked' });
    let principal = store.activity.authenticate(paired.probe_token);
    for (const sequence of initial) store.activity.appendEvents(principal, { events: [input(sequence)] });
    store.close();
    store = openStore(directory, nowRef);
    principal = store.activity.authenticate(paired.probe_token);
    const lateSequence = initial.length === 1 ? 1 : 2;
    const receipt = store.activity.appendEvents(principal, { events: [input(lateSequence)] }).results[0];
    assert.equal(receipt.status, 'accepted');
    assert.equal(receipt.clock_health, 'healthy');
    assert.deepEqual(receipt.sequence_coverage.missing, [lateSequence + 1]);
    const projection = store.db.prepare('SELECT state,coverage_status,clock_health,status_reason FROM activity_projections').get();
    assert.deepEqual({ ...projection }, { state: 'unknown', coverage_status: 'gap', clock_health: 'healthy', status_reason: 'coverage_gap' });
    assert.equal(store.activity.schemaStatus().ready, true);
    store.activity.appendEvents(principal, { events: [input(lateSequence + 1)] });
    assert.equal(store.activity.schemaStatus().ready, true);
    assert.equal(store.activity.summary(store.activity.authenticate(pairedReader.reader_token)).devices[0].state, initial.length === 1 ? 'active' : 'locked');
    store.close();
    store = openStore(directory, nowRef);
    assert.equal(store.activity.schemaStatus().ready, true);
    store.close();
    rmSync(directory, { recursive: true, force: true });
  }
});

test('unsupported v5 commitment preflight leaves DELETE and WAL database files untouched', () => {
  for (const journal of ['DELETE', 'WAL']) {
    for (const version of ['1', '2', '3', null]) {
      const directory = tempDir('activity-journal-version-preflight');
      const store = openStore(directory);
      pairProbe(store);
      store.close();
      const databasePath = path.join(directory, 'core.sqlite');
      const db = new DatabaseSync(databasePath);
      db.exec(`PRAGMA journal_mode=${journal}`);
      if (version == null) db.exec("DELETE FROM activity_metadata WHERE key='integrity_commitment_version'");
      else db.prepare("UPDATE activity_metadata SET value=? WHERE key='integrity_commitment_version'").run(version);
      db.close();
      const files = () => ['', '-journal', '-wal', '-shm'].map((suffix) => {
        const filename = `${databasePath}${suffix}`;
        return existsSync(filename) ? createHash('sha256').update(readFileSync(filename)).digest('hex') : null;
      });
      const before = files();
      assertActivityError(() => openStore(directory), 'activity_integrity_upgrade_unsupported');
      assert.deepEqual(files(), before, `${journal}:${version}`);
      rmSync(directory, { recursive: true, force: true });
    }
  }
});

test('missing main with any orphan SQLite sidecar never creates a fresh store or server authority', () => {
  const suffixes = ['-wal', '-shm', '-journal'];
  for (let mask = 1; mask < 8; mask++) {
    for (const content of ['', 'orphan']) {
      const directory = tempDir('activity-orphan-sidecars');
      const databasePath = path.join(directory, 'core.sqlite');
      suffixes.forEach((suffix, index) => {
        if (mask & (1 << index)) writeFileSync(`${databasePath}${suffix}`, content);
      });
      const files = () => ['', ...suffixes].map((suffix) => existsSync(`${databasePath}${suffix}`)
        ? readFileSync(`${databasePath}${suffix}`).toString('hex') : null);
      const before = files();
      assertActivityError(() => verifyActivityRecoveryCandidate(databasePath, {}), 'core_metadata_invariant_failed');
      assert.deepEqual(files(), before, `direct recovery:${mask}:${content}`);
      for (const activityEnabled of [false, true]) {
        for (const recovery of [false, true]) {
          const options = { activityEnabled, ...(recovery ? { activityRecoveryFloor: {} } : {}) };
          assertActivityError(() => new ICoreStore(databasePath, options), 'core_metadata_invariant_failed');
          assert.deepEqual(files(), before, `store:${mask}:${content}:${activityEnabled}:${recovery}`);
          assertActivityError(() => createICoreServer({ databasePath,
            activityAdminSecret: activityEnabled ? OWNER_SECRET : null,
            ...(recovery ? { activityRecoveryFloor: {} } : {}),
          }), 'core_metadata_invariant_failed');
          assert.deepEqual(files(), before, `server:${mask}:${content}:${activityEnabled}:${recovery}`);
        }
      }
      assert.equal(existsSync(databasePath), false);
      rmSync(directory, { recursive: true, force: true });
    }
  }
});

test('server and recovery startup reject five unsupported commitments before any source SQLite open', () => {
  for (const mode of ['DELETE', 'clean-WAL', 'real-WAL', 'missing-SHM', 'hot-journal']) {
    for (const commitment of ['1', '2', '3', '999', null]) {
      const directory = tempDir(`activity-server-preflight-${mode}`);
      let databasePath = path.join(directory, 'core.sqlite');
      const store = openStore(directory);
      pairProbe(store);
      store.close();
      const db = new DatabaseSync(databasePath);
      db.exec('PRAGMA journal_mode=DELETE');
      if (['real-WAL', 'missing-SHM'].includes(mode)) db.exec('PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0');
      if (commitment == null) db.exec("DELETE FROM activity_metadata WHERE key='integrity_commitment_version'");
      else db.prepare("UPDATE activity_metadata SET value=? WHERE key='integrity_commitment_version'").run(commitment);
      if (mode === 'clean-WAL') db.exec('PRAGMA journal_mode=WAL');
      if (mode === 'missing-SHM') {
        const detached = path.join(directory, 'without-shm.sqlite');
        copyFileSync(databasePath, detached);
        copyFileSync(`${databasePath}-wal`, `${detached}-wal`);
        databasePath = detached;
      }
      const sourceConnectionOpen = ['real-WAL', 'missing-SHM'].includes(mode);
      if (!sourceConnectionOpen) db.close();
      if (mode === 'hot-journal') {
        const child = spawnSync(process.execPath, ['-e', `const {DatabaseSync}=require('node:sqlite');
          const db=new DatabaseSync(process.argv[1]); db.exec("PRAGMA cache_size=1; BEGIN IMMEDIATE; INSERT OR REPLACE INTO activity_metadata(key,value) VALUES('integrity_commitment_version','4'); CREATE TABLE synthetic_journal_pages(data BLOB); INSERT INTO synthetic_journal_pages VALUES(zeroblob(200000));"); process.exit(0);`, databasePath]);
        assert.equal(child.status, 0, child.stderr.toString());
        assert.equal(existsSync(`${databasePath}-journal`), true);
      }
      const files = () => ['', '-journal', '-wal', '-shm'].map((suffix) => {
        if (!existsSync(`${databasePath}${suffix}`)) return null;
        const bytes = readFileSync(`${databasePath}${suffix}`);
        return { size: bytes.length, digest: createHash('sha256').update(bytes).digest('hex') };
      });
      const before = files();
      for (const active of [false, true]) {
        for (const recovery of [false, true]) {
          assertActivityError(() => createICoreServer({ databasePath,
            activityAdminSecret: active ? OWNER_SECRET : null,
            ...(recovery ? { activityRecoveryFloor: {} } : {}),
          }), 'activity_integrity_upgrade_unsupported');
          assert.deepEqual(files(), before, `server:${mode}:${commitment}:${active}:${recovery}`);
          assertActivityError(() => new ICoreStore(databasePath, { activityEnabled: active,
            ...(recovery ? { activityRecoveryFloor: {} } : {}),
          }), 'activity_integrity_upgrade_unsupported');
          assert.deepEqual(files(), before, `store:${mode}:${commitment}:${active}:${recovery}`);
        }
      }
      if (sourceConnectionOpen) db.close();
      rmSync(directory, { recursive: true, force: true });
    }
  }
});

test('direct recovery verification uses an isolated committed view for every accepted and rejected outcome', () => {
  for (const mode of ['DELETE', 'clean-WAL', 'real-WAL', 'missing-SHM', 'hot-journal']) {
    for (const outcome of ['valid', 'invalid-floor', 'stale-floor', 'tampered-floor', 'tampered-candidate', 'unsupported-1', 'unsupported-2', 'unsupported-3', 'unsupported-999', 'unsupported-missing']) {
      const directory = tempDir(`activity-direct-recovery-${mode}`);
      let databasePath = path.join(directory, 'core.sqlite');
      const store = openStore(directory);
      const probe = pairProbe(store);
      store.activity.appendEvents(store.activity.authenticate(probe.probe_token), { events: [event()] });
      const validFloor = store.activity.recoveryManifest();
      store.db.exec('PRAGMA wal_checkpoint(TRUNCATE)');
      const oldMain = readFileSync(databasePath);
      pairReader(store, 'later-reader');
      const laterFloor = store.activity.recoveryManifest();
      store.close();
      // Restore an exact synthetic earlier candidate, while retaining its
      // genuinely signed later floor for the stale-history rejection case.
      writeFileSync(databasePath, oldMain);
      const db = new DatabaseSync(databasePath);
      db.exec('PRAGMA journal_mode=DELETE');
      if (['real-WAL', 'missing-SHM'].includes(mode)) {
        db.exec('PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE synthetic_wal_touch(x); DROP TABLE synthetic_wal_touch;');
      }
      if (outcome.startsWith('unsupported-')) {
        const version = outcome.slice('unsupported-'.length);
        if (version === 'missing') db.exec("DELETE FROM activity_metadata WHERE key='integrity_commitment_version'");
        else db.prepare("UPDATE activity_metadata SET value=? WHERE key='integrity_commitment_version'").run(version);
      }
      if (outcome === 'tampered-candidate') db.exec("UPDATE activity_changes SET kind='chat.message' WHERE kind='activity.event.accepted'");
      if (mode === 'clean-WAL') db.exec('PRAGMA journal_mode=WAL');
      if (mode === 'missing-SHM') {
        const detached = path.join(directory, 'without-shm.sqlite');
        copyFileSync(databasePath, detached); copyFileSync(`${databasePath}-wal`, `${detached}-wal`);
        databasePath = detached;
      }
      const sourceConnectionOpen = ['real-WAL', 'missing-SHM'].includes(mode);
      if (!sourceConnectionOpen) db.close();
      if (mode === 'hot-journal') {
        const child = spawnSync(process.execPath, ['-e', `const {DatabaseSync}=require('node:sqlite');
          const db=new DatabaseSync(process.argv[1]); db.exec("PRAGMA cache_size=1; BEGIN IMMEDIATE; INSERT OR REPLACE INTO activity_metadata(key,value) VALUES('integrity_commitment_version','9999'); CREATE TABLE synthetic_journal_pages(data BLOB); INSERT INTO synthetic_journal_pages VALUES(zeroblob(200000));"); process.exit(0);`, databasePath]);
        assert.equal(child.status, 0, child.stderr.toString());
        assert.equal(existsSync(`${databasePath}-journal`), true);
      }
      const floor = outcome === 'invalid-floor' ? {} : outcome === 'stale-floor' ? laterFloor
        : outcome === 'tampered-floor' ? { ...validFloor, digest: `${validFloor.digest.slice(0, -1)}x` } : validFloor;
      const files = () => ['', '-journal', '-wal', '-shm'].map((suffix) => {
        if (!existsSync(`${databasePath}${suffix}`)) return null;
        const bytes = readFileSync(`${databasePath}${suffix}`);
        return { size: bytes.length, bytes: bytes.toString('hex') };
      });
      const before = files();
      const temporarySnapshotsBefore = new Set(readdirSync(tmpdir()).filter((name) => name.startsWith('activity-preflight-')));
      if (outcome === 'valid') {
        const verified = verifyActivityRecoveryCandidate(databasePath, floor);
        assert.equal(verified.ok, true);
        assert.equal(verified.activation_authorized, false);
      } else {
        const expectedCode = outcome.startsWith('unsupported-') ? 'activity_integrity_upgrade_unsupported'
          : outcome === 'stale-floor' ? 'stale_activity_restore' : 'recovery_lineage_unverified';
        assertActivityError(() => verifyActivityRecoveryCandidate(databasePath, floor), expectedCode);
      }
      assert.deepEqual(files(), before, `${mode}:${outcome}`);
      assert.deepEqual(readdirSync(tmpdir()).filter((name) => name.startsWith('activity-preflight-') && !temporarySnapshotsBefore.has(name)), [], `${mode}:${outcome}: temporary snapshot cleaned`);
      if (sourceConnectionOpen) db.close();
      rmSync(directory, { recursive: true, force: true });
    }
  }
  const directory = tempDir('activity-recovery-no-main-or-sidecars');
  const databasePath = path.join(directory, 'missing.sqlite');
  assertActivityError(() => verifyActivityRecoveryCandidate(databasePath, {}), 'recovery_lineage_unverified');
  assert.deepEqual(readdirSync(directory), []);
  rmSync(directory, { recursive: true, force: true });
});

test('prefix retirement preserves signed acceptance clock and logical permission or error context', () => {
  for (const mode of ['regression', 'permission', 'error', 'late-predecessor']) {
    const directory = tempDir(`activity-prefix-context-${mode}`);
    const nowRef = { value: 1_000_000 };
    let store = openStore(directory, nowRef);
    const paired = pairProbe(store);
    const pairedReader = pairReader(store);
    let principal = store.activity.authenticate(paired.probe_token);
    let retainedInput;
    if (mode === 'late-predecessor') {
      store.activity.appendEvents(principal, { events: [event({ originSequence: 2, ttl: ACTIVITY_RAW_RETENTION_MS })] });
      nowRef.value += 10;
      retainedInput = event({ originSequence: 4, signalAt: 1_000_100, ttl: ACTIVITY_RAW_RETENTION_MS });
    } else {
      store.activity.appendEvents(principal, { events: [event({
        kind: mode === 'permission' ? 'probe.permission_changed' : mode === 'error' ? 'probe.error' : 'session.unlocked',
        payload: mode === 'permission' ? { capability: 'usage_events', available: false } : mode === 'error' ? { code: 'collection_failed' } : {},
        ttl: ACTIVITY_RAW_RETENTION_MS,
      })] });
      nowRef.value += 10;
      retainedInput = event({ originSequence: 2, signalAt: mode === 'regression' ? 999_999 : 1_000_010,
        kind: mode === 'error' ? 'network.present' : 'session.unlocked', ttl: ACTIVITY_RAW_RETENTION_MS });
    }
    const receipt = store.activity.appendEvents(principal, { events: [retainedInput] }).results[0];
    const originalRaw = store.db.prepare('SELECT * FROM activity_events WHERE event_id=?').get(retainedInput.event_id);
    const originalChange = store.db.prepare('SELECT * FROM activity_changes WHERE server_sequence=?').get(receipt.server_sequence);
    if (mode === 'late-predecessor') {
      nowRef.value += 10;
      store.activity.appendEvents(principal, { events: [event({ originSequence: 1, signalAt: 1_000_200, ttl: ACTIVITY_RAW_RETENTION_MS })] });
    }
    nowRef.value = 1_000_000 + ACTIVITY_RAW_RETENTION_MS;
    const cleanup = store.activity.runRetention();
    assert.equal(cleanup.removed_events, mode === 'late-predecessor' ? 2 : 1, mode);
    assert.deepEqual(store.db.prepare('SELECT * FROM activity_events WHERE event_id=?').get(retainedInput.event_id), originalRaw);
    assert.deepEqual(store.db.prepare('SELECT * FROM activity_changes WHERE server_sequence=?').get(receipt.server_sequence), originalChange);
    assert.deepEqual(store.activity.appendEvents(principal, { events: [retainedInput] }).results[0], { ...receipt, status: 'duplicate' });
    assert.equal(store.activity.schemaStatus().ready, true, mode);
    if (mode === 'regression') assert.equal(originalRaw.clock_health, 'clock_regression');
    if (mode === 'permission') assert.equal(store.activity.summary(store.activity.authenticate(pairedReader.reader_token)).devices[0].sources[0].status_reason, 'permission_unavailable');
    if (mode === 'late-predecessor') {
      assert.equal(originalRaw.clock_health, 'healthy');
      assert.equal(store.db.prepare('SELECT clock_health FROM activity_projections').get().clock_health, 'clock_regression');
    }
    store.close();
    store = openStore(directory, nowRef);
    assert.equal(store.activity.schemaStatus().ready, true, mode);
    principal = store.activity.authenticate(paired.probe_token);
    if (mode === 'permission') {
      store.activity.appendEvents(principal, { events: [event({ originSequence: 3, signalAt: nowRef.value,
        kind: 'probe.permission_changed', payload: { capability: 'usage_events', available: true } })] });
      store.activity.appendEvents(principal, { events: [event({ originSequence: 4, signalAt: nowRef.value })] });
      assert.equal(store.activity.summary(store.activity.authenticate(pairedReader.reader_token)).devices[0].state, 'active');
    }
    store.close();
    rmSync(directory, { recursive: true, force: true });
  }
});

test('higher sequence expiry retires its entire accepted prefix early and makes the replay boundary terminal', () => {
  const directory = tempDir('activity-retirement-closure');
  const nowRef = { value: 1_000_000 };
  let store = openStore(directory, nowRef);
  const paired = pairProbe(store);
  let principal = store.activity.authenticate(paired.probe_token);
  store.activity.appendEvents(principal, { events: [event({ originSequence: 10, ttl: ACTIVITY_RAW_RETENTION_MS })] });
  nowRef.value += 10;
  const low = event({ originSequence: 5, signalAt: nowRef.value, ttl: ACTIVITY_RAW_RETENTION_MS });
  store.activity.appendEvents(principal, { events: [low] });
  nowRef.value = 1_000_000 + ACTIVITY_RAW_RETENTION_MS;
  assert.equal(store.activity.runRetention().removed_events, 2);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS n FROM activity_events').get().n, 0);
  assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM activity_changes WHERE kind='activity.event.accepted'").get().n, 0);
  assert.equal(store.db.prepare('SELECT retained_origin_floor FROM activity_probe_state').get().retained_origin_floor, 10);
  assertActivityError(() => store.activity.appendEvents(principal, { events: [event({ originSequence: 6, signalAt: nowRef.value })] }), 'event_retained_out');
  assertActivityError(() => store.activity.appendEvents(principal, { events: [low] }), 'event_retained_out');
  assert.equal(store.activity.appendEvents(principal, { events: [event({ originSequence: 11, signalAt: nowRef.value })] }).results[0].status, 'accepted');
  assert.equal(store.activity.schemaStatus().ready, true);
  store.close();
  store = openStore(directory, nowRef);
  principal = store.activity.authenticate(paired.probe_token);
  assert.equal(store.activity.schemaStatus().ready, true);
  assertActivityError(() => store.activity.appendEvents(principal, { events: [event({ originSequence: 6, signalAt: nowRef.value })] }), 'event_retained_out');
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('deterministic shuffled sequences survive repeated restart and partial prefix retirement', () => {
  for (let seed = 1; seed <= 12; seed++) {
    let random = seed;
    const next = () => (random = (Math.imul(random, 1664525) + 1013904223) >>> 0);
    const order = [1, 2, 3, 4, 5, 6];
    for (let index = order.length - 1; index > 0; index--) {
      const other = next() % (index + 1);
      [order[index], order[other]] = [order[other], order[index]];
    }
    const directory = tempDir(`activity-shuffled-prefix-${seed}`);
    const nowRef = { value: 1_000_000 };
    let store = openStore(directory, nowRef);
    const paired = pairProbe(store);
    const reader = pairReader(store);
    const restart = () => {
      store.close(); store = openStore(directory, nowRef);
      assert.equal(store.activity.schemaStatus().ready, true, `seed ${seed}: restart`);
    };
    for (const [index, sequence] of order.entries()) {
      nowRef.value = 1_000_000 + index * 10;
      const permission = seed % 2 === 0 && [2, 4].includes(sequence);
      const error = seed % 3 === 0 && sequence === 5;
      const signalAt = seed % 3 === 1 && sequence === 3 ? 999_999 : 1_000_000 + sequence * 100;
      store.activity.appendEvents(store.activity.authenticate(paired.probe_token), { events: [event({
        originSequence: sequence, signalAt, ttl: ACTIVITY_RAW_RETENTION_MS,
        kind: permission ? 'probe.permission_changed' : error ? 'probe.error' : sequence === 6 ? 'session.locked' : 'session.unlocked',
        payload: permission ? { capability: 'usage_events', available: sequence === 4 } : error ? { code: 'collection_failed' } : {},
      })] });
      assert.equal(store.activity.schemaStatus().ready, true, `seed ${seed}: append ${sequence}`);
      if (index % 2 === 0) restart();
    }
    nowRef.value = 1_000_000 + ACTIVITY_RAW_RETENTION_MS;
    assert.equal(store.activity.runRetention().removed_events, order.filter((sequence) => sequence <= order[0]).length);
    const floor = store.db.prepare('SELECT retained_origin_floor FROM activity_probe_state').get().retained_origin_floor;
    assert.equal(floor, order[0]);
    assert.equal(store.db.prepare('SELECT COUNT(*) AS n FROM activity_events WHERE origin_sequence<=?').get(floor).n, 0);
    assert.equal(store.activity.schemaStatus().ready, true, `seed ${seed}: partial retention`);
    restart();
    const secondStart = nowRef.value + 10;
    for (const sequence of [8, 7]) {
      nowRef.value += 10;
      store.activity.appendEvents(store.activity.authenticate(paired.probe_token), { events: [event({
        originSequence: sequence, signalAt: secondStart, ttl: ACTIVITY_RAW_RETENTION_MS,
      })] });
      assert.equal(store.activity.schemaStatus().ready, true, `seed ${seed}: above-floor gap fill`);
    }
    store.activity.snapshot(store.activity.authenticate(reader.reader_token));
    nowRef.value = secondStart + ACTIVITY_RAW_RETENTION_MS;
    store.activity.runRetention();
    assert.equal(store.db.prepare('SELECT COUNT(*) AS n FROM activity_events').get().n, 0);
    assert.equal(store.db.prepare('SELECT retained_origin_floor FROM activity_probe_state').get().retained_origin_floor, 8);
    assert.ok(store.db.prepare('SELECT retired_context_json FROM activity_probe_state').get().retired_context_json.length < 256);
    restart();
    store.close();
    rmSync(directory, { recursive: true, force: true });
  }
});

test('retired prefix and acceptance predecessor anchors are authenticated and never silently repaired', () => {
  for (const corruption of ['prefix', 'anchor']) {
    const directory = tempDir(`activity-prefix-anchor-tamper-${corruption}`);
    const nowRef = { value: 1_000_000 };
    const store = openStore(directory, nowRef);
    const paired = pairProbe(store);
    const principal = store.activity.authenticate(paired.probe_token);
    store.activity.appendEvents(principal, { events: [event({ ttl: ACTIVITY_RAW_RETENTION_MS })] });
    nowRef.value += 10;
    store.activity.appendEvents(principal, { events: [event({ originSequence: 2, signalAt: 999_999, ttl: ACTIVITY_RAW_RETENTION_MS })] });
    nowRef.value = 1_000_000 + ACTIVITY_RAW_RETENTION_MS;
    store.activity.runRetention();
    if (corruption === 'prefix') store.db.exec("UPDATE activity_probe_state SET retired_context_json=json_set(retired_context_json,'$.max_signal_at_ms',1)");
    else store.db.exec("UPDATE activity_changes SET payload_json=json_set(payload_json,'$.acceptance_clock_prior_signal_at_ms',999999) WHERE kind='activity.event.accepted'");
    const before = integrityDatabaseEvidence(store, directory);
    assertActivityError(() => store.activity.appendEvents(principal, { events: [event({ originSequence: 3, signalAt: nowRef.value })] }), 'activity_schema_not_ready');
    assertActivityError(() => store.activity.runRetention(), 'activity_schema_not_ready');
    assert.deepEqual(integrityDatabaseEvidence(store, directory), before);
    store.close();
    assertActivityError(() => openStore(directory, nowRef), 'activity_migration_incomplete');
    rmSync(directory, { recursive: true, force: true });
  }
});

test('read-only commitment classification consumes WAL view including missing SHM and hot journal without source writes', () => {
  const hashFiles = (databasePath) => ['', '-journal', '-wal', '-shm'].map((suffix) => existsSync(`${databasePath}${suffix}`)
    ? createHash('sha256').update(readFileSync(`${databasePath}${suffix}`)).digest('hex') : null);
  for (const direction of ['main-valid-wal-invalid', 'main-invalid-wal-valid', 'missing-shm']) {
    const directory = tempDir(`activity-preflight-wal-${direction}`);
    let store = openStore(directory);
    pairProbe(store);
    store.close();
    const databasePath = path.join(directory, 'core.sqlite');
    const db = new DatabaseSync(databasePath);
    db.exec('PRAGMA journal_mode=DELETE');
    db.prepare("UPDATE activity_metadata SET value=? WHERE key='integrity_commitment_version'").run(direction === 'main-invalid-wal-valid' ? '1' : '4');
    db.exec('PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0');
    db.prepare("UPDATE activity_metadata SET value=? WHERE key='integrity_commitment_version'").run(direction === 'main-invalid-wal-valid' ? '4' : '1');
    if (direction === 'missing-shm') {
      // Copy a committed WAL view into a new synthetic path without its SHM.
      const detached = path.join(directory, 'without-shm.sqlite');
      copyFileSync(databasePath, detached); copyFileSync(`${databasePath}-wal`, `${detached}-wal`);
      const before = hashFiles(detached);
      assertActivityError(() => new ICoreStore(detached, { activityEnabled: true }), 'activity_integrity_upgrade_unsupported');
      assert.deepEqual(hashFiles(detached), before);
    } else if (direction === 'main-valid-wal-invalid') {
      const before = hashFiles(databasePath);
      assertActivityError(() => openStore(directory), 'activity_integrity_upgrade_unsupported');
      assert.deepEqual(hashFiles(databasePath), before);
    } else {
      store = openStore(directory);
      assert.equal(store.activity.schemaStatus().ready, true);
      store.close();
    }
    db.close();
    rmSync(directory, { recursive: true, force: true });
  }
  const directory = tempDir('activity-preflight-hot-journal');
  const databasePath = path.join(directory, 'core.sqlite');
  const store = openStore(directory); pairProbe(store); store.close();
  const db = new DatabaseSync(databasePath);
  db.exec("PRAGMA journal_mode=DELETE; UPDATE activity_metadata SET value='1' WHERE key='integrity_commitment_version'");
  db.close();
  const child = spawnSync(process.execPath, ['-e', `const {DatabaseSync}=require('node:sqlite');
    const db=new DatabaseSync(process.argv[1]); db.exec("PRAGMA cache_size=1; BEGIN IMMEDIATE; UPDATE activity_metadata SET value='4' WHERE key='integrity_commitment_version'; CREATE TABLE synthetic_journal_pages(data BLOB); INSERT INTO synthetic_journal_pages VALUES(zeroblob(200000));"); process.exit(0);`, databasePath]);
  assert.equal(child.status, 0, child.stderr.toString());
  assert.equal(existsSync(`${databasePath}-journal`), true);
  const before = hashFiles(databasePath);
  assertActivityError(() => openStore(directory), 'activity_integrity_upgrade_unsupported');
  assert.deepEqual(hashFiles(databasePath), before);
  rmSync(directory, { recursive: true, force: true });
});

function integrityDatabaseEvidence(store, directory) {
  const tables = store.db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND (name LIKE 'activity_%' OR name='core_metadata') ORDER BY name").all();
  return {
    files: ['', '-wal'].map((suffix) => {
      const filename = path.join(directory, `core.sqlite${suffix}`);
      return existsSync(filename) ? createHash('sha256').update(readFileSync(filename)).digest('hex') : null;
    }),
    rows: tables.map(({ name }) => [name, store.db.prepare(`SELECT * FROM ${name} ORDER BY rowid`).all()]),
    lease: store.db.prepare('SELECT * FROM activity_runtime_claim').get(),
  };
}

test('each authority entry independently rejects same and external connection corruption with zero writes and no retention wash', () => {
  const corruptions = [
    ['change-kind', 'activity_changes', 'kind', 'chat.message'],
    ['change-signature', 'activity_changes', 'payload_json', null],
    ['event-kind', 'activity_events', 'kind', 'session.locked'],
    ['event-generation', 'activity_events', 'credential_generation', 999],
  ];
  const surfaces = {
    health: ({ store }) => assert.equal(store.health({ activityOwnerConfigured: true }).activity.control_plane_available, false),
    summary: ({ store, reader }) => store.activity.summary(reader),
    snapshot: ({ store, reader }) => store.activity.snapshot(reader),
    append: ({ store, principal }) => store.activity.appendEvents(principal, { events: [event({ originSequence: 2 })] }),
    changes: ({ store, reader, cursor }) => store.activity.changes(reader, cursor),
    recovery: ({ store }) => store.activity.recoveryManifest(),
    recoveryFloor: ({ store, floor }) => store.activity.assertRecoveryFloor(floor),
    export: ({ store }) => store.activity.adminExport(),
    retention: ({ store }) => store.activity.runRetention(),
    rotate: ({ store, principal }) => store.activity.rotatePrincipal(principal.principal_id),
    revoke: ({ store }) => store.activity.revokeProbe('probe-a'),
    delete: ({ store }) => store.activity.deleteProbe('probe-a'),
    deviceDelete: ({ store }) => store.activity.deleteDevice('device-a'),
    pair: ({ store }) => pairReader(store, 'another-reader'),
    authenticate: ({ store, token }) => store.activity.authenticate(token),
  };
  for (const external of [false, true]) {
    for (const [corruption, table, field, replacement] of corruptions) {
      for (const [surface, invoke] of Object.entries(surfaces)) {
        const label = `${external ? 'external' : 'same'}-${corruption}-${surface}`;
        const directory = tempDir(`activity-fail-closed-${label}`);
        const nowRef = { value: 1_000_000 };
        let store = openStore(directory, nowRef);
        const paired = pairProbe(store);
        const pairedReader = pairReader(store);
        const principal = store.activity.authenticate(paired.probe_token);
        const reader = store.activity.authenticate(pairedReader.reader_token);
        store.activity.appendEvents(principal, { events: [event()] });
        const floor = store.activity.recoveryManifest();
        const args = { store, principal, reader, token: paired.probe_token, cursor: pairedReader.initial_cursor, floor };
        const db = external ? new DatabaseSync(path.join(directory, 'core.sqlite')) : store.db;
        const original = db.prepare(`SELECT ${field} AS value FROM ${table} WHERE server_sequence=1`).get().value;
        const value = corruption === 'change-signature'
          ? JSON.stringify({ ...JSON.parse(original), integrity_signature: 'A'.repeat(43) }) : replacement;
        db.prepare(`UPDATE ${table} SET ${field}=? WHERE server_sequence=1`).run(value);
        if (external) db.close();
        const before = integrityDatabaseEvidence(store, directory);
        nowRef.value += 100;
        // No health or schema call precedes this entry: each entry must discover the damage itself.
        if (surface === 'health') invoke(args);
        else assertActivityError(() => invoke(args), 'activity_schema_not_ready');
        assert.deepEqual(integrityDatabaseEvidence(store, directory), before, label);
        nowRef.value += ACTIVITY_RAW_RETENTION_MS + 1;
        assertActivityError(() => store.activity.runRetention(), 'activity_schema_not_ready');
        assert.deepEqual(integrityDatabaseEvidence(store, directory), before, `${label}: retention cannot wash evidence`);
        assert.equal(store.activity.retentionFailure, null, 'integrity failure is never recategorized as recoverable retention failure');
        store.db.prepare(`UPDATE ${table} SET ${field}=? WHERE server_sequence=1`).run(original);
        assert.equal(activitySchemaStatus(store.db).ready, true, label);
        const restored = integrityDatabaseEvidence(store, directory);
        assertActivityError(() => store.activity.summary(reader), 'activity_schema_not_ready');
        assertActivityError(() => store.activity.runRetention(), 'activity_schema_not_ready');
        assert.deepEqual(integrityDatabaseEvidence(store, directory), restored, `${label}: restored bytes do not clear runtime latch`);
        store.close();
        // Only a fresh runtime over actually canonical evidence may recover.
        nowRef.value = 1_000_100;
        store = openStore(directory, nowRef);
        assert.equal(store.activity.schemaStatus().ready, true, label);
        store.close();
        rmSync(directory, { recursive: true, force: true });
      }
    }
  }
});

test('server clock floor is commit-bound, retained after expiry and safe at integer overflow', () => {
  const directory = tempDir('activity-server-clock-boundary');
  const nowRef = { value: 1_000_000 };
  let store = openStore(directory, nowRef);
  const probe = pairProbe(store);
  const pairedReader = pairReader(store);
  const principal = store.activity.authenticate(probe.probe_token);
  const reader = store.activity.authenticate(pairedReader.reader_token);
  nowRef.value += 100;
  store.activity.appendEvents(principal, { events: [event({ signalAt: nowRef.value })] });
  nowRef.value += ACTIVITY_RAW_RETENTION_MS;
  store.activity.runRetention();
  assert.equal(store.db.prepare('SELECT COUNT(*) AS n FROM activity_events').get().n, 0);
  const retainedFloor = nowRef.value;
  nowRef.value = 1_000_000;
  const next = pairReader(store, 'post-retention-reader');
  assert.equal(store.db.prepare('SELECT paired_at_ms FROM activity_principals WHERE principal_id=?').get(next.principal_id).paired_at_ms, retainedFloor);
  store.close();
  store = openStore(directory, nowRef);
  assert.equal(Number(store.db.prepare("SELECT value FROM activity_metadata WHERE key='server_time_floor_ms'").get().value), retainedFloor);
  const before = integrityDatabaseEvidence(store, directory);
  nowRef.value = Number.MAX_SAFE_INTEGER;
  for (const action of [
    () => store.activity.rotatePrincipal(probe.principal_id),
    () => store.activity.revokeProbe('probe-a'),
    () => store.activity.deleteProbe('probe-a'),
    () => store.activity.deleteDevice('device-a'),
    () => store.activity.appendEvents(principal, { events: [event({ originSequence: 2 })] }),
    () => store.activity.summary(reader),
    () => store.activity.snapshot(reader),
  ]) {
    assertActivityError(action, 'invalid_time_range');
    assert.deepEqual(integrityDatabaseEvidence(store, directory), before);
  }
  nowRef.value = retainedFloor;
  assert.equal(store.activity.schemaStatus().ready, true);
  store.close();
  const databasePath = path.join(directory, 'core.sqlite');
  for (const floor of ['0', String(Number.MAX_SAFE_INTEGER), 'not-an-integer']) {
    const db = new DatabaseSync(databasePath);
    db.prepare("UPDATE activity_metadata SET value=? WHERE key='server_time_floor_ms'").run(floor);
    db.close();
    const hash = createHash('sha256').update(readFileSync(databasePath)).digest('hex');
    assertActivityError(() => openStore(directory, nowRef), 'activity_migration_incomplete');
    assert.equal(createHash('sha256').update(readFileSync(databasePath)).digest('hex'), hash);
  }
  rmSync(directory, { recursive: true, force: true });
});

test('root and change seal helpers are bounded independently of the required full preflight audit', () => {
  const source = readFileSync(new URL('./activity_control_plane.mjs', import.meta.url), 'utf8');
  const root = source.slice(source.indexOf('function replayCommitment('), source.indexOf('function activityChangeSignature('));
  assert.doesNotMatch(root, /\['activity_(?:events|changes|event_tombstones)'/);
  const signer = source.slice(source.indexOf('function activityChangeSignature('), source.indexOf('function activityChangeAuthenticated('));
  assert.match(signer, /FROM activity_events WHERE server_sequence=\?/);
  const seal = source.slice(source.indexOf('  #sealChange('), source.indexOf('  #requireChangeIntegrity('));
  assert.match(seal, /FROM activity_changes WHERE server_sequence=\?/);
  assert.doesNotMatch(seal, /\.all\(/);
});

test('gap heal preserves permission state from logical sequence order rather than delivery order', () => {
  const directory = tempDir('activity-gap-permission-order');
  const store = openStore(directory);
  const probe = pairProbe(store);
  const reader = pairReader(store);
  const principal = store.activity.authenticate(probe.probe_token);
  const readerPrincipal = store.activity.authenticate(reader.reader_token);
  store.activity.appendEvents(principal, { events: [event({ originSequence: 1 })] });
  store.activity.appendEvents(principal, {
    events: [event({
      originSequence: 3,
      signalAt: 1_000_003,
      kind: 'probe.permission_changed',
      payload: { capability: 'usage_events', available: false },
    })],
  });
  const fill = store.activity.appendEvents(principal, {
    events: [event({
      originSequence: 2,
      signalAt: 1_000_002,
      kind: 'probe.permission_changed',
      payload: { capability: 'usage_events', available: true },
    })],
  }).results[0];
  assert.equal(fill.clock_health, 'healthy');
  assert.deepEqual(fill.sequence_diagnostics, ['sequence_regression']);
  let source = store.activity.summary(readerPrincipal).devices[0].sources[0];
  assert.equal(source.state, 'unknown');
  assert.equal(source.status_reason, 'permission_unavailable');
  assert.equal(store.db.prepare("SELECT last_coverage_status FROM activity_probe_state WHERE probe_id='probe-a'").get().last_coverage_status, 'permission_unavailable');

  store.activity.appendEvents(principal, {
    events: [event({ originSequence: 4, signalAt: 1_000_004 })],
  });
  source = store.activity.summary(readerPrincipal).devices[0].sources[0];
  assert.equal(source.status_reason, 'permission_unavailable');
  store.activity.appendEvents(principal, {
    events: [event({
      originSequence: 5,
      signalAt: 1_000_005,
      kind: 'probe.permission_changed',
      payload: { capability: 'usage_events', available: true },
    })],
  });
  source = store.activity.summary(readerPrincipal).devices[0].sources[0];
  assert.equal(source.state, 'unknown');
  assert.equal(source.status_reason, 'insufficient_human_evidence');
  store.activity.appendEvents(principal, {
    events: [event({ originSequence: 6, signalAt: 1_000_006 })],
  });
  source = store.activity.summary(readerPrincipal).devices[0].sources[0];
  assert.equal(source.state, 'active');
  assert.equal(store.activity.schemaStatus().ready, true);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('an older-clock sequence gap invalidates current evidence until the missing sequence heals it', () => {
  const directory = tempDir('activity-older-clock-gap');
  const nowRef = { value: 1_000_300 };
  const store = openStore(directory, nowRef);
  const probe = pairProbe(store, { now: 1_000_000 });
  const reader = pairReader(store, 'gap-reader', 1_000_000);
  const principal = store.activity.authenticate(probe.probe_token);
  const readerPrincipal = store.activity.authenticate(reader.reader_token);
  store.activity.appendEvents(principal, {
    events: [event({ originSequence: 3, signalAt: 1_000_300 })],
  }, nowRef.value);
  store.activity.appendEvents(principal, {
    events: [event({ originSequence: 5, signalAt: 1_000_100 })],
  }, nowRef.value);
  let source = store.activity.summary(readerPrincipal).devices[0].sources[0];
  assert.equal(source.state, 'unknown');
  assert.equal(source.coverage_status, 'gap');
  assert.equal(source.status_reason, 'coverage_gap');
  assert.equal(source.occurred_at_ms, 1_000_300);
  store.activity.appendEvents(principal, {
    events: [event({ originSequence: 4, signalAt: 1_000_200 })],
  }, nowRef.value);
  source = store.activity.summary(readerPrincipal).devices[0].sources[0];
  assert.equal(source.state, 'unknown');
  assert.equal(source.coverage_status, 'covered');
  assert.equal(source.clock_health, 'clock_regression');
  assert.equal(source.status_reason, 'clock_regression');
  store.activity.appendEvents(principal, {
    events: [event({ originSequence: 6, signalAt: 1_000_400 })],
  }, nowRef.value);
  source = store.activity.summary(readerPrincipal).devices[0].sources[0];
  assert.equal(source.state, 'active');
  assert.equal(source.coverage_status, 'covered');
  assert.equal(source.occurred_at_ms, 1_000_400);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('same-probe network evidence cannot replace fresh active or locked evidence but becomes expiry fallback', () => {
  const directory = tempDir('activity-same-probe-evidence-rank');
  const nowRef = { value: 1_000_000 };
  const store = openStore(directory, nowRef);
  const reader = pairReader(store, 'same-probe-reader', nowRef.value);
  const readerPrincipal = store.activity.authenticate(reader.reader_token);
  for (const [index, kind, expected] of [
    [0, 'session.unlocked', 'active'],
    [1, 'session.locked', 'locked'],
  ]) {
    const scenarioStart = nowRef.value;
    const deviceId = `same-probe-device-${index}`;
    const probeId = `same-probe-${index}`;
    const probe = pairProbe(store, {
      deviceId,
      probeId,
      expirySlo: 1_000,
      now: nowRef.value,
    });
    const principal = store.activity.authenticate(probe.probe_token);
    store.activity.appendEvents(principal, {
      events: [event({ deviceId, probeId, originSequence: 1, kind, signalAt: scenarioStart, ttl: 1_000 })],
    }, nowRef.value);
    store.activity.appendEvents(principal, {
      events: [event({ deviceId, probeId, originSequence: 2, kind: 'network.present', signalAt: scenarioStart + 100, ttl: 1_000 })],
    }, nowRef.value);
    let device = store.activity.summary(readerPrincipal).devices.find((item) => item.device_id === deviceId);
    assert.equal(device.state, expected);
    assert.equal(device.sources[0].occurred_at_ms, scenarioStart);
    nowRef.value = scenarioStart + 1_001;
    device = store.activity.summary(readerPrincipal).devices.find((item) => item.device_id === deviceId);
    assert.equal(device.state, 'network_only');
    assert.equal(device.sources[0].occurred_at_ms, scenarioStart + 100);
  }
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('newly received clock, permission and probe faults invalidate same-probe concrete evidence until recovery', () => {
  const directory = tempDir('activity-same-probe-faults');
  const nowRef = { value: 1_000_000 };
  const store = openStore(directory, nowRef);
  const reader = pairReader(store, 'fault-reader', nowRef.value);
  const readerPrincipal = store.activity.authenticate(reader.reader_token);
  const cases = [
    {
      probeId: 'clock-regression-probe',
      initialKind: 'session.unlocked',
      fault: { originSequence: 2, signalAt: 999_900 },
      reason: 'clock_regression',
      recoveryKind: 'session.unlocked',
    },
    {
      probeId: 'future-clock-probe',
      initialKind: 'session.locked',
      fault: { originSequence: 2, signalAt: 1_600_001 },
      reason: 'future_skew',
      recoveryKind: 'session.locked',
    },
    {
      probeId: 'permission-probe',
      initialKind: 'session.locked',
      fault: {
        originSequence: 2,
        signalAt: 999_900,
        kind: 'probe.permission_changed',
        payload: { capability: 'usage_events', available: false },
      },
      reason: 'permission_unavailable',
      recoveryKind: 'session.locked',
      permissionRecovery: true,
    },
    {
      probeId: 'error-probe',
      initialKind: 'session.unlocked',
      fault: {
        originSequence: 2,
        signalAt: 999_900,
        kind: 'probe.error',
        payload: { code: 'collection_failed' },
      },
      reason: 'probe_error',
      recoveryKind: 'session.unlocked',
    },
  ];
  for (const [index, item] of cases.entries()) {
    const deviceId = `fault-device-${index}`;
    const probe = pairProbe(store, { deviceId, probeId: item.probeId, now: nowRef.value });
    const principal = store.activity.authenticate(probe.probe_token);
    store.activity.appendEvents(principal, {
      events: [event({ deviceId, probeId: item.probeId, originSequence: 1, kind: item.initialKind, signalAt: 1_000_000 })],
    });
    store.activity.appendEvents(principal, {
      events: [event({ deviceId, probeId: item.probeId, ...item.fault })],
    });
    let source = store.activity.summary(readerPrincipal).devices
      .find((device) => device.device_id === deviceId).sources[0];
    assert.equal(source.state, 'unknown', item.probeId);
    assert.equal(source.status_reason, item.reason, item.probeId);
    if (item.permissionRecovery) {
      store.activity.appendEvents(principal, {
        events: [event({
          deviceId,
          probeId: item.probeId,
          originSequence: 3,
          signalAt: 1_000_010,
          kind: 'network.present',
        })],
      });
      source = store.activity.summary(readerPrincipal).devices
        .find((device) => device.device_id === deviceId).sources[0];
      assert.equal(source.state, 'unknown');
      assert.equal(source.status_reason, 'permission_unavailable');
      store.activity.appendEvents(principal, {
        events: [event({
          deviceId,
          probeId: item.probeId,
          originSequence: 4,
          signalAt: 1_000_020,
          kind: 'input.activity',
          payload: { class: 'input_or_touch' },
        })],
      });
      source = store.activity.summary(readerPrincipal).devices
        .find((device) => device.device_id === deviceId).sources[0];
      assert.equal(source.state, 'unknown');
      assert.equal(source.status_reason, 'permission_unavailable');
      store.activity.appendEvents(principal, {
        events: [event({
          deviceId,
          probeId: item.probeId,
          originSequence: 5,
          signalAt: 1_000_030,
          kind: 'probe.permission_changed',
          payload: { capability: 'usage_events', available: true },
        })],
      });
      source = store.activity.summary(readerPrincipal).devices
        .find((device) => device.device_id === deviceId).sources[0];
      assert.equal(source.state, 'unknown');
    }
    const recoverySequence = item.permissionRecovery ? 6 : 3;
    store.activity.appendEvents(principal, {
      events: [event({
        deviceId,
        probeId: item.probeId,
        originSequence: recoverySequence,
        signalAt: 1_000_100,
        kind: item.recoveryKind,
      })],
    });
    source = store.activity.summary(readerPrincipal).devices
      .find((device) => device.device_id === deviceId).sources[0];
    assert.equal(source.state, item.recoveryKind === 'session.locked' ? 'locked' : 'active', item.probeId);
  }
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('a newer healthy probe error supersedes clock fault health but remains unknown', () => {
  const directory = tempDir('activity-clock-error-transition');
  const databasePath = path.join(directory, 'core.sqlite');
  let store = openStore(directory);
  const probe = pairProbe(store);
  const reader = pairReader(store);
  const principal = store.activity.authenticate(probe.probe_token);
  const readerPrincipal = store.activity.authenticate(reader.reader_token);
  store.activity.appendEvents(principal, { events: [event({ originSequence: 1, signalAt: 1_000_000 })] });
  store.activity.appendEvents(principal, { events: [event({ originSequence: 2, signalAt: 999_900 })] });
  store.activity.appendEvents(principal, {
    events: [event({
      originSequence: 3,
      signalAt: 1_000_100,
      kind: 'probe.error',
      payload: { code: 'collection_failed' },
    })],
  });
  const source = store.activity.summary(readerPrincipal).devices[0].sources[0];
  assert.equal(source.state, 'unknown');
  assert.equal(source.clock_health, 'healthy');
  assert.equal(source.status_reason, 'probe_error');
  assert.equal(store.activity.schemaStatus().ready, true);
  store.close();
  store = new ICoreStore(databasePath, { activityEnabled: true, clock: () => 1_000_000 });
  assert.equal(store.activity.schemaStatus().ready, true);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('device summary applies evidence-class priority before recency and deterministic ties', () => {
  const directory = tempDir('activity-multi-probe-order');
  const nowRef = { value: 1_000_000 };
  const store = openStore(directory, nowRef);
  const probeA = pairProbe(store, { probeId: 'probe-a', source: 'windows_wts' });
  const probeB = pairProbe(store, { probeId: 'probe-b', source: 'windows_last_input' });
  const reader = pairReader(store);
  const readerPrincipal = store.activity.authenticate(reader.reader_token);
  store.activity.appendEvents(store.activity.authenticate(probeA.probe_token), {
    events: [event({ probeId: 'probe-a', signalAt: 1_000_001 })],
  });
  store.activity.appendEvents(store.activity.authenticate(probeB.probe_token), {
    events: [event({ probeId: 'probe-b', source: 'windows_last_input', kind: 'session.locked', signalAt: 1_000_002 })],
  });
  assert.equal(store.activity.summary(readerPrincipal).devices[0].state, 'locked');

  store.activity.appendEvents(store.activity.authenticate(probeA.probe_token), {
    events: [event({ probeId: 'probe-a', originSequence: 2, signalAt: 1_000_003 })],
  });
  assert.equal(store.activity.summary(readerPrincipal).devices[0].state, 'active');

  store.activity.appendEvents(store.activity.authenticate(probeB.probe_token), {
    events: [event({
      probeId: 'probe-b',
      source: 'windows_last_input',
      originSequence: 2,
      signalAt: 1_000_004 + 5 * 60 * 1000 + 1,
      coverageStart: 1_000_004,
      coverageEnd: 1_000_004 + 5 * 60 * 1000 + 1,
    })],
  });
  assert.equal(store.activity.summary(readerPrincipal).devices[0].state, 'active');

  const networkProbe = pairProbe(store, { probeId: 'probe-network', source: 'windows_probe' });
  store.activity.appendEvents(store.activity.authenticate(networkProbe.probe_token), {
    events: [event({
      probeId: 'probe-network',
      source: 'windows_probe',
      kind: 'network.present',
      signalAt: 1_000_005,
    })],
  });
  assert.equal(store.activity.summary(readerPrincipal).devices[0].state, 'active');

  const tieStore = pairProbe(store, { deviceId: 'device-tie', probeId: 'probe-tie-a', source: 'windows_wts' });
  const tieStoreB = pairProbe(store, { deviceId: 'device-tie', probeId: 'probe-tie-b', source: 'windows_last_input' });
  store.activity.appendEvents(store.activity.authenticate(tieStore.probe_token), {
    events: [event({ deviceId: 'device-tie', probeId: 'probe-tie-a', signalAt: 1_000_010 })],
  });
  store.activity.appendEvents(store.activity.authenticate(tieStoreB.probe_token), {
    events: [event({ deviceId: 'device-tie', probeId: 'probe-tie-b', source: 'windows_last_input', kind: 'session.locked', signalAt: 1_000_010 })],
  });
  assert.equal(store.activity.summary(readerPrincipal).devices.find((item) => item.device_id === 'device-tie').state, 'locked');

  const quietProbe = pairProbe(store, { deviceId: 'device-evidence', probeId: 'probe-quiet', source: 'windows_last_input' });
  const quietNetwork = pairProbe(store, { deviceId: 'device-evidence', probeId: 'probe-quiet-network', source: 'windows_probe' });
  store.activity.appendEvents(store.activity.authenticate(quietProbe.probe_token), {
    events: [event({
      deviceId: 'device-evidence',
      probeId: 'probe-quiet',
      source: 'windows_last_input',
      kind: 'input.idle_bucket',
      signalAt: 1_000_020,
      payload: { bucket: '15m_plus' },
    })],
  });
  store.activity.appendEvents(store.activity.authenticate(quietNetwork.probe_token), {
    events: [event({
      deviceId: 'device-evidence',
      probeId: 'probe-quiet-network',
      source: 'windows_probe',
      kind: 'network.present',
      signalAt: 1_000_021,
    })],
  });
  assert.equal(store.activity.summary(readerPrincipal).devices.find((item) => item.device_id === 'device-evidence').state, 'unknown');

  const healthyProbe = pairProbe(store, { deviceId: 'device-fault-isolation', probeId: 'probe-healthy', source: 'windows_wts' });
  const errorProbe = pairProbe(store, { deviceId: 'device-fault-isolation', probeId: 'probe-error', source: 'windows_probe' });
  const permissionProbe = pairProbe(store, { deviceId: 'device-fault-isolation', probeId: 'probe-permission', source: 'windows_last_input' });
  store.activity.appendEvents(store.activity.authenticate(healthyProbe.probe_token), {
    events: [event({
      deviceId: 'device-fault-isolation',
      probeId: 'probe-healthy',
      kind: 'session.locked',
      signalAt: 1_000_030,
    })],
  });
  store.activity.appendEvents(store.activity.authenticate(errorProbe.probe_token), {
    events: [event({
      deviceId: 'device-fault-isolation',
      probeId: 'probe-error',
      source: 'windows_probe',
      kind: 'probe.error',
      signalAt: 1_000_031,
      payload: { code: 'collection_failed' },
    })],
  });
  assert.equal(store.activity.summary(readerPrincipal).devices.find((item) => item.device_id === 'device-fault-isolation').state, 'locked');
  store.activity.appendEvents(store.activity.authenticate(permissionProbe.probe_token), {
    events: [event({
      deviceId: 'device-fault-isolation',
      probeId: 'probe-permission',
      source: 'windows_last_input',
      kind: 'probe.permission_changed',
      signalAt: 1_000_032,
      payload: { capability: 'usage_events', available: false },
    })],
  });
  assert.equal(store.activity.summary(readerPrincipal).devices.find((item) => item.device_id === 'device-fault-isolation').state, 'locked');

  nowRef.value = 1_400_000;
  store.activity.appendEvents(store.activity.authenticate(networkProbe.probe_token), {
    events: [event({
      probeId: 'probe-network',
      source: 'windows_probe',
      kind: 'network.present',
      originSequence: 2,
      signalAt: nowRef.value,
      coverageStart: nowRef.value,
      coverageEnd: nowRef.value,
    })],
  });
  assert.equal(store.activity.summary(readerPrincipal).devices[0].state, 'network_only');
  assert.equal(store.activity.summary(readerPrincipal, nowRef.value + 400_000).devices[0].state, 'unknown');

  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('opaque identifiers and registered diagnostics reject URL, secret, stack, JWT, control and non-ASCII values atomically', () => {
  const directory = tempDir('activity-data-minimization');
  const store = openStore(directory);
  const probe = pairProbe(store);
  const principal = store.activity.authenticate(probe.probe_token);
  const unsafeIdentifiers = [
    'https://private.example/x',
    'Bearer secret-value',
    'eyj.header.signature',
    'line\nbreak',
    '设备-a',
    'token-value',
  ];
  for (const [index, value] of unsafeIdentifiers.entries()) {
    assertActivityError(() => store.activity.appendEvents(principal, {
      events: [event({ originSequence: 100 + index }), event({ wireEventId: value, originSequence: 200 + index })],
    }), 'invalid_event_id');
  }
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 0);
  assertActivityError(() => pairProbe(store, { deviceId: 'https://private.example/device', probeId: 'safe-probe' }), 'invalid_identifier');
  assertActivityError(() => pairProbe(store, { deviceId: 'safe-device', probeId: 'safe-probe', source: 'private_source' }), 'invalid_request');
  assertActivityError(() => pairProbe(store, { deviceId: 'safe-device', probeId: 'safe-probe', capabilities: ['Bearer secret'] }), 'invalid_diagnostic_token');

  for (const capability of ['https_url', 'Bearer', 'stack_trace', '未授权']) {
    assertActivityError(() => store.activity.appendEvents(principal, {
      events: [event({ originSequence: 300 + capability.length, kind: 'probe.permission_changed', payload: { capability, available: false } })],
    }), 'invalid_diagnostic_token');
  }
  assertActivityError(() => store.activity.appendEvents(principal, {
    events: [event({ originSequence: 400, kind: 'probe.permission_changed', payload: { capability: 'screen_state', available: false } })],
  }), 'unregistered_diagnostic');
  assertActivityError(() => store.activity.appendEvents(principal, {
    events: [event({ originSequence: 401, kind: 'probe.error', payload: { code: 'source_unavailable' } })],
  }), 'unregistered_diagnostic');
  const accepted = store.activity.appendEvents(principal, {
    events: [event({ originSequence: 1, kind: 'probe.error', payload: { code: 'collection_failed' } })],
  });
  assert.equal(accepted.results[0].status, 'accepted');
  const serialized = JSON.stringify({ export: store.activity.adminExport(), audit: store.activity.audit() });
  for (const value of unsafeIdentifiers) assert.equal(serialized.includes(value), false);
  assert.equal(/Bearer|https:\/\/|line\\nbreak|设备|eyj\.header\.signature/.test(serialized), false);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('frozen summary fixture matches the implemented v1 field surface and conservative state vocabulary', () => {
  const directory = tempDir('activity-summary-fixture');
  const store = openStore(directory);
  const probe = pairProbe(store);
  const reader = pairReader(store);
  store.activity.appendEvents(store.activity.authenticate(probe.probe_token), { events: [event()] });
  const actual = store.activity.summary(store.activity.authenticate(reader.reader_token));
  assert.deepEqual(Object.keys(SUMMARY_FIXTURE).sort(), [
    'authority', 'contract', 'devices', 'generated_at_ms', 'schema_version', 'semantics',
  ].sort());
  assert.deepEqual(Object.keys(SUMMARY_FIXTURE.devices[0]).sort(), ['device_id', 'sources', 'state'].sort());
  assert.deepEqual(Object.keys(SUMMARY_FIXTURE.devices[0].sources[0]).sort(), [
    'clock_health', 'coverage', 'coverage_status', 'credential_state', 'device_id',
    'freshness', 'occurred_at_ms', 'probe_id', 'received_at_ms', 'registered_coverage',
    'source', 'state', 'status_reason', 'ttl_ms',
  ].sort());
  assert.deepEqual(Object.keys(actual).sort(), Object.keys(SUMMARY_FIXTURE).sort());
  assert.deepEqual(Object.keys(actual.devices[0]).sort(), Object.keys(SUMMARY_FIXTURE.devices[0]).sort());
  assert.deepEqual(Object.keys(actual.devices[0].sources[0]).sort(), Object.keys(SUMMARY_FIXTURE.devices[0].sources[0]).sort());
  assert.equal(['active', 'locked', 'network_only', 'unknown'].includes(SUMMARY_FIXTURE.devices[0].state), true);
  assert.equal(ACTIVITY_STATUS_REASONS.includes(actual.devices[0].sources[0].status_reason), true);
  assert.equal(ACTIVITY_STATUS_REASONS.every((reason) => /^[a-z][a-z0-9_]*$/.test(reason)), true);
  assert.equal(JSON.stringify(SUMMARY_FIXTURE).includes('quiet_observed'), false);
  assert.equal(JSON.stringify(SUMMARY_FIXTURE).includes('asleep'), false);
  store.db.prepare("UPDATE activity_projections SET status_reason='Bearer_secret' WHERE probe_id='probe-a'").run();
  assert.equal(store.activity.schemaStatus().reason, 'projection_vocabulary_invariant_failed');
  assertActivityError(() => store.activity.summary(store.activity.authenticate(reader.reader_token)), 'activity_schema_not_ready');
  store.db.prepare("UPDATE activity_projections SET status_reason='fresh_signal' WHERE probe_id='probe-a'").run();
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('per-probe rate limiting is atomic and does not consume event identities on rejection', () => {
  const directory = tempDir('activity-rate');
  const nowRef = { value: 3_000_000 };
  const store = openStore(directory, nowRef);
  const paired = pairProbe(store);
  const principal = store.activity.authenticate(paired.probe_token);
  const batch = Array.from({ length: 100 }, (_, index) => event({ originSequence: index, signalAt: nowRef.value }));
  store.activity.appendEvents(principal, { events: batch });
  const overflow = Array.from({ length: 21 }, (_, index) => event({ originSequence: 100 + index, signalAt: nowRef.value }));
  assertActivityError(() => store.activity.appendEvents(principal, { events: overflow }), 'rate_limited');
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 100);
  nowRef.value += 60_000;
  assert.equal(store.activity.appendEvents(principal, { events: [overflow[0]] }).results[0].status, 'accepted');
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('an active exact retry returns its durable receipt after event TTL expiry', () => {
  const directory = tempDir('activity-retry-after-ttl');
  const nowRef = { value: 1_000_000 };
  const store = openStore(directory, nowRef);
  const probe = pairProbe(store);
  const principal = store.activity.authenticate(probe.probe_token);
  const shortLived = event({ ttl: 1_000 });
  const accepted = store.activity.appendEvents(principal, { events: [shortLived] });
  nowRef.value += 2_000;
  const duplicate = store.activity.appendEvents(principal, { events: [shortLived] });
  assert.equal(duplicate.results[0].status, 'duplicate');
  assert.equal(duplicate.results[0].receipt_id, accepted.results[0].receipt_id);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 1);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('an active exact retry returns its durable receipt at a full rate window', () => {
  const directory = tempDir('activity-retry-at-rate-limit');
  const nowRef = { value: 3_000_000 };
  const store = openStore(directory, nowRef);
  const probe = pairProbe(store);
  const principal = store.activity.authenticate(probe.probe_token);
  const firstBatch = Array.from({ length: 100 }, (_, index) => event({ originSequence: index, signalAt: nowRef.value }));
  const secondBatch = Array.from({ length: 20 }, (_, index) => event({ originSequence: 100 + index, signalAt: nowRef.value }));
  const firstReceipt = store.activity.appendEvents(principal, { events: firstBatch }).results[0].receipt_id;
  store.activity.appendEvents(principal, { events: secondBatch });
  const duplicate = store.activity.appendEvents(principal, { events: [firstBatch[0]] });
  assert.equal(duplicate.results[0].status, 'duplicate');
  assert.equal(duplicate.results[0].receipt_id, firstReceipt);
  assert.equal(store.db.prepare("SELECT accepted_count FROM activity_rate_limits WHERE probe_id='probe-a'").get().accepted_count, 120);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('same-batch exact duplicates consume one new-event rate slot', () => {
  const directory = tempDir('activity-same-batch-rate');
  const store = openStore(directory);
  const probe = pairProbe(store);
  const principal = store.activity.authenticate(probe.probe_token);
  const same = event();
  const result = store.activity.appendEvents(principal, { events: [same, same] });
  assert.deepEqual(result.results.map((item) => item.status), ['accepted', 'duplicate']);
  assert.equal(result.results[0].receipt_id, result.results[1].receipt_id);
  assert.equal(store.db.prepare("SELECT accepted_count FROM activity_rate_limits WHERE probe_id='probe-a'").get().accepted_count, 1);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 1);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('origin sequence zero is accepted before any durable retention floor exists', () => {
  const directory = tempDir('activity-sequence-zero');
  const store = openStore(directory);
  const probe = pairProbe(store);
  const result = store.activity.appendEvents(store.activity.authenticate(probe.probe_token), {
    events: [event({ originSequence: 0 })],
  });
  assert.equal(result.results[0].status, 'accepted');
  assert.equal(store.db.prepare("SELECT retained_origin_floor FROM activity_probe_state WHERE probe_id='probe-a'").get().retained_origin_floor, null);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('revoke is checked before idempotency and atomically invalidates projection and snapshot generation', () => {
  const directory = tempDir('activity-revoke');
  const store = openStore(directory);
  const paired = pairProbe(store);
  const principal = store.activity.authenticate(paired.probe_token);
  const accepted = event();
  store.activity.appendEvents(principal, { events: [accepted] });
  const generationBefore = Number(store.db.prepare("SELECT value FROM activity_metadata WHERE key='snapshot_generation'").get().value);
  store.activity.revokeProbe('probe-a', 1_000_001);
  assertActivityError(() => store.activity.appendEvents(store.activity.authenticate(paired.probe_token), { events: [accepted] }, 1_000_002), 'revoked_replay');
  const projection = store.db.prepare("SELECT state,credential_state FROM activity_projections WHERE probe_id='probe-a'").get();
  assert.deepEqual({ ...projection }, { state: 'unknown', credential_state: 'revoked' });
  assert.equal(Number(store.db.prepare("SELECT value FROM activity_metadata WHERE key='snapshot_generation'").get().value), generationBefore + 1);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 1);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('stale pre-auth snapshots fail closed after revoke, rotation and deletion on every store operation', () => {
  const directory = tempDir('activity-stale-principal');
  const store = openStore(directory);

  const revoked = pairProbe(store, { probeId: 'probe-revoked' });
  const staleRevoked = store.activity.authenticate(revoked.probe_token);
  store.activity.revokeProbe('probe-revoked', 1_000_001);
  assertActivityError(() => store.activity.appendEvents(staleRevoked, { events: [event({ probeId: 'probe-revoked' })] }), 'revoked_replay');

  const rotated = pairProbe(store, { probeId: 'probe-rotated', source: 'windows_last_input' });
  const staleRotated = store.activity.authenticate(rotated.probe_token);
  store.activity.rotatePrincipal(rotated.principal_id, 1_000_002);
  assertActivityError(() => store.activity.appendEvents(staleRotated, { events: [event({ probeId: 'probe-rotated', source: 'windows_last_input' })] }), 'revoked_replay');

  const deleted = pairProbe(store, { probeId: 'probe-deleted', source: 'android_screen_state' });
  const staleDeleted = store.activity.authenticate(deleted.probe_token);
  store.activity.deleteProbe('probe-deleted', 1_000_003);
  assertActivityError(() => store.activity.appendEvents(staleDeleted, { events: [event({ probeId: 'probe-deleted', source: 'android_screen_state' })] }), 'revoked_replay');

  const reader = pairReader(store);
  const staleReader = store.activity.authenticate(reader.reader_token);
  store.activity.rotatePrincipal(reader.principal_id, 1_000_004);
  assertActivityError(() => store.activity.summary(staleReader), 'revoked_replay');
  assertActivityError(() => store.activity.changes(staleReader, reader.initial_cursor), 'revoked_replay');
  assertActivityError(() => store.activity.snapshot(staleReader), 'revoked_replay');
  assertActivityError(() => store.activity.acknowledge(staleReader, { cursor: reader.initial_cursor }), 'revoked_replay');
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 0);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('delayed HTTP event and ack bodies cannot cross revoke or rotation linearization', async (t) => {
  const directory = tempDir('activity-http-linearization');
  const { core, baseUrl } = await startServer(t, directory);
  const paired = await pairProbeHttp(baseUrl);
  assert.equal(paired.status, 200);
  const reader = pairReader(core.store);
  const authenticate = core.store.activity.authenticate.bind(core.store.activity);
  let observedAuthentication = null;
  core.store.activity.authenticate = (token) => {
    const result = authenticate(token);
    observedAuthentication?.();
    observedAuthentication = null;
    return result;
  };

  const eventAuthenticated = new Promise((resolve) => { observedAuthentication = resolve; });
  const delayedEvent = partialJsonRequest(`${baseUrl}/v1/core/activity/events`, { token: paired.body.probe_token });
  delayedEvent.request.flushHeaders();
  delayedEvent.request.write('{"events":');
  await eventAuthenticated;
  core.store.activity.revokeProbe('probe-a', 1_000_001);
  delayedEvent.request.end(`${JSON.stringify([event()])}}`);
  const eventResponse = await delayedEvent.response;
  assert.equal(eventResponse.status, 401);
  assert.equal(eventResponse.body.error.code, 'revoked_replay');

  const ackAuthenticated = new Promise((resolve) => { observedAuthentication = resolve; });
  const delayedAck = partialJsonRequest(`${baseUrl}/v1/core/activity/ack`, { token: reader.reader_token });
  delayedAck.request.flushHeaders();
  delayedAck.request.write('{"cursor":');
  await ackAuthenticated;
  core.store.activity.rotatePrincipal(reader.principal_id, 1_000_002);
  delayedAck.request.end(`${JSON.stringify(reader.initial_cursor)}}`);
  const ackResponse = await delayedAck.response;
  assert.equal(ackResponse.status, 401);
  assert.equal(ackResponse.body.error.code, 'revoked_replay');
});

test('explicit credential rotation advances generation and never silently revives or re-pairs a probe', () => {
  const directory = tempDir('activity-rotation');
  const store = openStore(directory);
  const probe = pairProbe(store);
  assertActivityError(() => pairProbe(store), 'probe_already_paired');
  const rotated = store.activity.rotatePrincipal(probe.principal_id, 1_000_001);
  assert.equal(rotated.credential_generation, 2);
  assertActivityError(
    () => store.activity.appendEvents(store.activity.authenticate(probe.probe_token), { events: [event()] }, 1_000_002),
    'revoked_replay',
  );
  const accepted = store.activity.appendEvents(store.activity.authenticate(rotated.token), { events: [event()] }, 1_000_002);
  assert.equal(accepted.results[0].status, 'accepted');
  store.activity.revokeProbe('probe-a', 1_000_003);
  assertActivityError(() => store.activity.rotatePrincipal(probe.principal_id, 1_000_004), 'principal_revoked');
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('single-probe deletion isolates raw, projection, export and spool directive without harming sibling probe', () => {
  const directory = tempDir('activity-delete');
  const store = openStore(directory);
  const first = pairProbe(store, { probeId: 'probe-a' });
  const second = pairProbe(store, { probeId: 'probe-b', source: 'windows_last_input' });
  store.activity.appendEvents(store.activity.authenticate(first.probe_token), { events: [event()] });
  store.activity.appendEvents(store.activity.authenticate(second.probe_token), { events: [event({ probeId: 'probe-b', source: 'windows_last_input' })] });
  const deletion = store.activity.deleteProbe('probe-a', 1_000_010);
  assert.equal(deletion.status.device_spool, 'client_action_required');
  assert.equal(deletion.status.backup, 'expires_by_policy');
  assertActivityError(() => store.activity.appendEvents(store.activity.authenticate(first.probe_token), { events: [event()] }, 1_000_011), 'revoked_replay');
  assert.equal(store.activity.adminExport().events.some((item) => item.probe_id === 'probe-a'), false);
  assert.equal(store.activity.adminExport().events.some((item) => item.probe_id === 'probe-b'), true);
  assert.equal(store.db.prepare("SELECT COUNT(*) AS value FROM activity_events WHERE probe_id='probe-b'").get().value, 1);
  const reader = pairReader(store);
  const summary = store.activity.summary(store.activity.authenticate(reader.reader_token), 1_000_012);
  assert.deepEqual(summary.devices[0].sources.map((item) => item.probe_id), ['probe-b']);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('device deletion revokes every bound probe while leaving another device intact', () => {
  const directory = tempDir('activity-device-delete');
  const store = openStore(directory);
  const first = pairProbe(store, { probeId: 'probe-a' });
  const second = pairProbe(store, { probeId: 'probe-b', source: 'windows_last_input' });
  const other = pairProbe(store, { deviceId: 'device-c', probeId: 'probe-c', source: 'android_screen_state' });
  store.activity.appendEvents(store.activity.authenticate(first.probe_token), { events: [event()] });
  store.activity.appendEvents(store.activity.authenticate(second.probe_token), { events: [event({ probeId: 'probe-b', source: 'windows_last_input' })] });
  store.activity.appendEvents(store.activity.authenticate(other.probe_token), { events: [event({ deviceId: 'device-c', probeId: 'probe-c', source: 'android_screen_state' })] });
  const deletion = store.activity.deleteDevice('device-a', 1_000_010);
  assert.equal(deletion.scope, 'device');
  assertActivityError(() => store.activity.appendEvents(store.activity.authenticate(first.probe_token), { events: [event()] }, 1_000_011), 'revoked_replay');
  assertActivityError(() => store.activity.appendEvents(store.activity.authenticate(second.probe_token), { events: [event({ probeId: 'probe-b', source: 'windows_last_input' })] }, 1_000_011), 'revoked_replay');
  assert.equal(store.db.prepare("SELECT COUNT(*) AS value FROM activity_events WHERE device_id='device-a'").get().value, 0);
  assert.equal(store.db.prepare("SELECT COUNT(*) AS value FROM activity_events WHERE device_id='device-c'").get().value, 1);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('stale Core epoch fails closed before idempotency, projection or receipt lookup', () => {
  const directory = tempDir('activity-epoch');
  const store = openStore(directory);
  const probe = pairProbe(store);
  const principal = store.activity.authenticate(probe.probe_token);
  const reader = pairReader(store);
  const readerPrincipal = store.activity.authenticate(reader.reader_token);
  store.activity.appendEvents(principal, { events: [event()] });
  const counts = {
    events: store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value,
    changes: store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
  };
  store.db.prepare("UPDATE activity_metadata SET value='2' WHERE key='authority_epoch'").run();
  assertActivityError(() => store.activity.appendEvents(principal, { events: [event()] }), 'stale_authority_epoch');
  assertActivityError(() => store.activity.summary(readerPrincipal), 'stale_authority_epoch');
  assertActivityError(() => store.activity.changes(readerPrincipal, reader.initial_cursor), 'stale_authority_epoch');
  assertActivityError(() => store.activity.snapshot(readerPrincipal), 'stale_authority_epoch');
  assertActivityError(() => store.activity.acknowledge(readerPrincipal, { cursor: reader.initial_cursor }), 'stale_authority_epoch');
  assert.deepEqual({
    events: store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value,
    changes: store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
  }, counts);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('startup, periodic timer, export and backup enforce the exact 24-hour retention boundary', async () => {
  const directory = tempDir('activity-automatic-retention');
  const databasePath = path.join(directory, 'core.sqlite');
  const backupPath = path.join(directory, 'retained-backup.sqlite');
  const nowRef = { value: 1_000_000 };
  let store = openStore(directory, nowRef);
  const probe = pairProbe(store, { now: nowRef.value });
  let principal = store.activity.authenticate(probe.probe_token);
  store.activity.appendEvents(principal, { events: [event({ originSequence: 1, signalAt: nowRef.value })] });
  store.close();

  nowRef.value += ACTIVITY_RAW_RETENTION_MS;
  store = openStore(directory, nowRef);
  principal = store.activity.authenticate(probe.probe_token);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 0);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_event_tombstones').get().value, 0);
  store.activity.appendEvents(principal, { events: [event({ originSequence: 2, signalAt: nowRef.value })] });
  nowRef.value += ACTIVITY_RAW_RETENTION_MS;
  assert.equal(store.activity.adminExport().events.length, 0);
  store.activity.appendEvents(principal, { events: [event({ originSequence: 3, signalAt: nowRef.value })] });
  nowRef.value += ACTIVITY_RAW_RETENTION_MS;
  await store.backupDatabase(backupPath);
  const backupDb = new DatabaseSync(backupPath, { readOnly: true });
  assert.equal(backupDb.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 0);
  assert.equal(backupDb.prepare('SELECT COUNT(*) AS value FROM activity_event_tombstones').get().value, 0);
  backupDb.close();
  store.close();

  const dormantPath = path.join(directory, 'dormant-expired.sqlite');
  const dormantBackupPath = path.join(directory, 'dormant-expired-backup.sqlite');
  nowRef.value = 5_000_000;
  let dormant = new ICoreStore(dormantPath, { activityEnabled: true, clock: () => nowRef.value });
  const dormantProbe = pairProbe(dormant, { deviceId: 'dormant-device', probeId: 'dormant-probe', now: nowRef.value });
  dormant.activity.appendEvents(dormant.activity.authenticate(dormantProbe.probe_token), {
    events: [event({ deviceId: 'dormant-device', probeId: 'dormant-probe', signalAt: nowRef.value })],
  });
  dormant.close();
  nowRef.value += ACTIVITY_RAW_RETENTION_MS;
  dormant = new ICoreStore(dormantPath, { activityEnabled: false, clock: () => nowRef.value });
  await assert.rejects(
    dormant.backupDatabase(dormantBackupPath),
    (error) => error?.code === 'activity_retention_authority_required',
  );
  assert.equal(existsSync(dormantBackupPath), false);
  dormant.close();

  const timerPath = path.join(directory, 'timer.sqlite');
  nowRef.value = 10_000_000;
  const core = createICoreServer({
    databasePath: timerPath,
    activityAdminSecret: OWNER_SECRET,
    activityRetentionIntervalMs: 5,
    clock: () => nowRef.value,
  });
  await core.listen({ port: 0 });
  const timerProbe = pairProbe(core.store, { deviceId: 'timer-device', probeId: 'timer-probe', now: nowRef.value });
  const timerReader = pairReader(core.store, 'timer-reader', nowRef.value);
  core.store.activity.appendEvents(core.store.activity.authenticate(timerProbe.probe_token), {
    events: [event({ deviceId: 'timer-device', probeId: 'timer-probe', originSequence: 1, signalAt: nowRef.value })],
  });
  nowRef.value += ACTIVITY_RAW_RETENTION_MS;
  await new Promise((resolve) => setTimeout(resolve, 40));
  assert.equal(core.store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 0);
  assert.equal(core.store.activity.summary(core.store.activity.authenticate(timerReader.reader_token)).devices[0].state, 'unknown');
  await core.close();
  const afterClose = new DatabaseSync(timerPath, { readOnly: true });
  const highWater = afterClose.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value;
  afterClose.close();
  await new Promise((resolve) => setTimeout(resolve, 20));
  const afterWait = new DatabaseSync(timerPath, { readOnly: true });
  assert.equal(afterWait.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value, highWater);
  assert.equal(afterWait.prepare('SELECT runtime_id FROM activity_runtime_claim').get().runtime_id, '');
  afterWait.close();
  rmSync(directory, { recursive: true, force: true });
});

test('dormant formal backup rejects every row that a retention sweep would remove or rewrite', async () => {
  const rawDirectory = tempDir('activity-backup-debt-raw-derived');
  const rawDatabasePath = path.join(rawDirectory, 'core.sqlite');
  const rawBackupPath = path.join(rawDirectory, 'backup.sqlite');
  const rawNowRef = { value: 2 * ACTIVITY_RAW_RETENTION_MS };
  let rawStore = openStore(rawDirectory, rawNowRef);
  const rawProbe = pairProbe(rawStore, { now: rawNowRef.value });
  rawStore.activity.appendEvents(rawStore.activity.authenticate(rawProbe.probe_token), {
    events: [event({ signalAt: rawNowRef.value })],
  });
  rawStore.close();
  rawNowRef.value += ACTIVITY_RAW_RETENTION_MS;
  rawStore = new ICoreStore(rawDatabasePath, { activityEnabled: false, clock: () => rawNowRef.value });
  await assert.rejects(rawStore.backupDatabase(rawBackupPath), (error) => (
    error?.code === 'activity_retention_authority_required'
    && ['activity_events', 'activity_changes', 'activity_probe_state', 'activity_rate_limits', 'activity_projections']
      .every((table) => error?.details?.tables?.includes(table))
  ));
  assert.equal(existsSync(rawBackupPath), false);
  rawStore.close();
  rmSync(rawDirectory, { recursive: true, force: true });

  for (const table of ['activity_event_tombstones', 'activity_audit']) {
    const directory = tempDir(`activity-backup-debt-${table}`);
    const databasePath = path.join(directory, 'core.sqlite');
    const backupPath = path.join(directory, 'backup.sqlite');
    const nowRef = { value: 2 * ACTIVITY_RAW_RETENTION_MS };
    let store = openStore(directory, nowRef);
    const probe = pairProbe(store, { now: nowRef.value });
    store.activity.appendEvents(store.activity.authenticate(probe.probe_token), {
      events: [event({ signalAt: nowRef.value })],
    });
    store.activity.deleteProbe('probe-a', nowRef.value);
    assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 0);
    store.close();
    nowRef.value += ACTIVITY_RAW_RETENTION_MS;
    store = new ICoreStore(databasePath, { activityEnabled: false, clock: () => nowRef.value });
    await assert.rejects(store.backupDatabase(backupPath), (error) => (
      error?.code === 'activity_retention_authority_required'
      && error?.details?.tables?.includes(table)
    ), table);
    assert.equal(existsSync(backupPath), false, table);
    store.close();
    rmSync(directory, { recursive: true, force: true });
  }
});

test('deletion tombstones expire at the original event retention boundary, not a second day later', () => {
  const directory = tempDir('activity-tombstone-original-boundary');
  const nowRef = { value: 2 * ACTIVITY_RAW_RETENTION_MS };
  const store = openStore(directory, nowRef);
  const probe = pairProbe(store, { now: nowRef.value });
  store.activity.appendEvents(store.activity.authenticate(probe.probe_token), {
    events: [event({ signalAt: nowRef.value })],
  });
  const receivedAt = nowRef.value;
  nowRef.value += 6 * 60 * 60 * 1000;
  store.activity.deleteProbe('probe-a', nowRef.value);
  const tombstone = store.db.prepare('SELECT expires_at_ms FROM activity_event_tombstones').get();
  assert.equal(Number(tombstone.expires_at_ms), receivedAt + ACTIVITY_RAW_RETENTION_MS);
  nowRef.value = receivedAt + ACTIVITY_RAW_RETENTION_MS;
  store.activity.runRetention(nowRef.value);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_event_tombstones').get().value, 0);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('retention failure latches health and all ordinary activity access until a successful cleanup', () => {
  const directory = tempDir('activity-retention-latch');
  const store = openStore(directory);
  const probe = pairProbe(store);
  const reader = pairReader(store);
  const principal = store.activity.authenticate(probe.probe_token);
  const readerPrincipal = store.activity.authenticate(reader.reader_token);
  const originalPrepare = store.db.prepare.bind(store.db);
  store.db.prepare = (sql, ...args) => {
    if (sql.startsWith('SELECT probe_id,MAX(origin_sequence)')) throw Object.assign(new Error('synthetic retention execution failure'), { code: 'synthetic_retention_failure' });
    return originalPrepare(sql, ...args);
  };
  assertActivityError(() => store.activity.runRetention(), 'synthetic_retention_failure');
  store.db.prepare = originalPrepare;
  assert.equal(store.activity.schemaStatus().ready, true);
  assert.equal(store.health({ activityOwnerConfigured: true }).activity.control_plane_available, false);
  const before = {
    events: store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value,
    changes: store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
    highWater: store.db.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
  };
  for (const action of [
    () => store.activity.appendEvents(principal, { events: [event()] }),
    () => store.activity.summary(readerPrincipal),
    () => store.activity.adminExport(),
  ]) assertActivityError(action, 'activity_retention_failed');
  assert.deepEqual({
    events: store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value,
    changes: store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
    highWater: store.db.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
  }, before);
  store.activity.runRetention();
  assert.equal(store.health({ activityOwnerConfigured: true }).activity.control_plane_available, true);
  assert.equal(store.activity.appendEvents(principal, { events: [event()] }).results[0].status, 'accepted');
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('retention advances an off-by-one-safe watermark and forces stale cursor snapshot resync', () => {
  const directory = tempDir('activity-retention');
  const nowRef = { value: 10 * ACTIVITY_RAW_RETENTION_MS };
  const store = openStore(directory, nowRef);
  const probe = pairProbe(store, { now: nowRef.value - ACTIVITY_RAW_RETENTION_MS + 1 });
  const reader = pairReader(store, 'reader-a', nowRef.value - ACTIVITY_RAW_RETENTION_MS + 1);
  const probePrincipal = store.activity.authenticate(probe.probe_token);
  const readerPrincipal = store.activity.authenticate(reader.reader_token);
  const oldTime = nowRef.value;
  store.activity.appendEvents(probePrincipal, { events: [event({ signalAt: oldTime, ttl: ACTIVITY_RAW_RETENTION_MS })] }, oldTime);
  const before = store.activity.changes(readerPrincipal, reader.initial_cursor);
  const cursorAtAccepted = before.next_cursor;
  nowRef.value = oldTime + ACTIVITY_RAW_RETENTION_MS + 1;
  const cleanup = store.activity.runRetention(nowRef.value);
  assert.equal(cleanup.removed_events, 1);
  assertActivityError(() => store.activity.changes(readerPrincipal, reader.initial_cursor), 'resync_required');
  const boundary = store.activity.changes(readerPrincipal, cleanup.earliest_cursor);
  assert.equal(boundary.events.some((item) => item.kind === 'activity.retention.cleaned'), true);
  assert.equal(store.activity.decodeCursor(cursorAtAccepted), cleanup.retained_watermark);
  const snapshot = store.activity.snapshot(readerPrincipal, nowRef.value);
  assert.equal(snapshot.retained_watermark, cleanup.retained_watermark);
  assert.equal(snapshot.summary.devices[0].state, 'unknown');
  assert.equal(store.activity.acknowledge(readerPrincipal, { cursor: snapshot.base_cursor }).ok, true);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('structured event IDs and an O(probes) retention floor survive restart without permanent event rows', async () => {
  const directory = tempDir('activity-retention-replay-floor');
  const databasePath = path.join(directory, 'core.sqlite');
  const nowRef = { value: 10 * ACTIVITY_RAW_RETENTION_MS };
  let store = openStore(directory, nowRef);
  const probe = pairProbe(store, { now: nowRef.value - ACTIVITY_RAW_RETENTION_MS + 1 });
  let principal = store.activity.authenticate(probe.probe_token);
  const acceptedAt = nowRef.value;
  const original = event({ originSequence: 1, signalAt: acceptedAt, ttl: ACTIVITY_RAW_RETENTION_MS });
  store.activity.appendEvents(principal, { events: [original] }, acceptedAt);
  nowRef.value = acceptedAt + ACTIVITY_RAW_RETENTION_MS;
  store.activity.runRetention(nowRef.value);
  assert.equal(store.db.prepare("SELECT value FROM activity_metadata WHERE key='accepted_event_count'").get().value, '1');
  assert.equal(store.db.prepare("SELECT value FROM activity_metadata WHERE key='retired_event_count'").get().value, '1');
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 0);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_event_tombstones').get().value, 0);
  assert.equal(store.db.prepare("SELECT COUNT(*) AS value FROM sqlite_master WHERE name='activity_event_replay_barriers'").get().value, 0);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_replay_lineage_floors').get().value, 0);
  assert.equal(store.db.prepare("SELECT retained_origin_floor FROM activity_probe_state WHERE probe_id='probe-a'").get().retained_origin_floor, 1);
  assert.equal(store.db.prepare("SELECT max_origin_sequence FROM activity_probe_state WHERE probe_id='probe-a'").get().max_origin_sequence, null);
  assert.equal(store.activity.schemaStatus().ready, true);
  store.close();
  store = new ICoreStore(databasePath, { clock: () => nowRef.value, activityEnabled: true });
  principal = store.activity.authenticate(probe.probe_token);
  assert.equal(store.activity.schemaStatus().ready, true);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_replay_lineage_floors').get().value, 0);
  assert.equal(store.activity.adminExport().events.length, 0);
  const before = {
    events: store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value,
    changes: store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
    audit: store.db.prepare('SELECT COUNT(*) AS value FROM activity_audit').get().value,
    highWater: store.db.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
  };
  for (const replay of [original, event({ originSequence: 1, kind: 'session.locked', signalAt: nowRef.value })]) {
    assertActivityError(() => store.activity.appendEvents(principal, { events: [replay] }, nowRef.value), 'event_retained_out');
    assert.deepEqual({
      events: store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value,
      changes: store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
      audit: store.db.prepare('SELECT COUNT(*) AS value FROM activity_audit').get().value,
      highWater: store.db.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
    }, before);
  }
  assertActivityError(() => store.activity.appendEvents(principal, {
    events: [event({ wireEventId: original.event_id, originSequence: 2, signalAt: nowRef.value })],
  }, nowRef.value), 'event_id_binding_mismatch');
  assertActivityError(() => store.activity.appendEvents(principal, {
    events: [event({ wireEventId: `${'Z'.repeat(22)}.2`, originSequence: 2, signalAt: nowRef.value })],
  }, nowRef.value), 'event_id_binding_mismatch');
  assert.equal(store.activity.appendEvents(principal, {
    events: [event({ originSequence: 2, signalAt: nowRef.value })],
  }, nowRef.value).results[0].status, 'accepted');
  const backupPath = path.join(directory, 'floor-backup.sqlite');
  const backupResult = await store.backupDatabase(backupPath);
  const tamperedPath = path.join(directory, 'floor-tampered.sqlite');
  copyFileSync(backupPath, tamperedPath);
  const tampered = new DatabaseSync(tamperedPath);
  tampered.prepare("UPDATE activity_probe_state SET retained_origin_floor=0 WHERE probe_id='probe-a'").run();
  tampered.close();
  assertActivityError(
    () => verifyActivityRecoveryCandidate(tamperedPath, backupResult.recovery_manifest),
    'recovery_lineage_unverified',
  );
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('accepted-history commitment detects coordinated deletion of non-current raw and change rows', () => {
  const directory = tempDir('activity-accepted-history-deletion');
  const databasePath = path.join(directory, 'core.sqlite');
  let store = openStore(directory);
  const probe = pairProbe(store);
  const principal = store.activity.authenticate(probe.probe_token);
  store.activity.appendEvents(principal, { events: [event({ originSequence: 1 })] });
  store.activity.appendEvents(principal, {
    events: [event({ originSequence: 2, signalAt: 1_000_100 })],
  });
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 2);
  assert.equal(store.db.prepare("SELECT value FROM activity_metadata WHERE key='accepted_event_count'").get().value, '2');
  store.close();

  const corrupt = new DatabaseSync(databasePath);
  const removed = corrupt.prepare("SELECT event_id,server_sequence FROM activity_events WHERE origin_sequence=1").get();
  corrupt.prepare('DELETE FROM activity_events WHERE event_id=?').run(removed.event_id);
  corrupt.prepare('DELETE FROM activity_changes WHERE server_sequence=?').run(removed.server_sequence);
  assert.equal(activitySchemaStatus(corrupt).reason, 'accepted_history_invariant_failed');
  const before = {
    claim: corrupt.prepare('SELECT * FROM activity_runtime_claim').get(),
    events: corrupt.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value,
    changes: corrupt.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
    highWater: corrupt.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
    accepted: corrupt.prepare("SELECT value FROM activity_metadata WHERE key='accepted_event_count'").get().value,
    retired: corrupt.prepare("SELECT value FROM activity_metadata WHERE key='retired_event_count'").get().value,
  };
  corrupt.close();
  assertActivityError(
    () => new ICoreStore(databasePath, { activityEnabled: true, clock: () => 1_000_000 }),
    'activity_migration_incomplete',
  );
  const after = new DatabaseSync(databasePath, { readOnly: true });
  assert.deepEqual({
    claim: after.prepare('SELECT * FROM activity_runtime_claim').get(),
    events: after.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value,
    changes: after.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
    highWater: after.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
    accepted: after.prepare("SELECT value FROM activity_metadata WHERE key='accepted_event_count'").get().value,
    retired: after.prepare("SELECT value FROM activity_metadata WHERE key='retired_event_count'").get().value,
  }, before);
  after.close();
  rmSync(directory, { recursive: true, force: true });
});

test('O(probes) replay commitment detects floor, prefix and row rollback before authority mutation', () => {
  const directory = tempDir('activity-replay-state-corruption');
  const databasePath = path.join(directory, 'core.sqlite');
  const nowRef = { value: 10 * ACTIVITY_RAW_RETENTION_MS };
  let store = openStore(directory, nowRef);
  const probe = pairProbe(store, { now: nowRef.value - ACTIVITY_RAW_RETENTION_MS });
  const principal = store.activity.authenticate(probe.probe_token);
  const acceptedAt = nowRef.value;
  store.activity.appendEvents(principal, { events: [event({ originSequence: 1, signalAt: acceptedAt, ttl: ACTIVITY_RAW_RETENTION_MS })] }, acceptedAt);
  nowRef.value = acceptedAt + ACTIVITY_RAW_RETENTION_MS;
  store.activity.runRetention(nowRef.value);
  assert.equal(store.activity.schemaStatus().ready, true);
  const originalState = store.db.prepare("SELECT * FROM activity_probe_state WHERE probe_id='probe-a'").get();
  const originalPrefix = store.db.prepare("SELECT event_id_prefix FROM activity_principals WHERE probe_id='probe-a'").get().event_id_prefix;
  const originalMetadata = Object.fromEntries(store.db.prepare(`SELECT key,value FROM activity_metadata
    WHERE key IN ('replay_floor_revision','replay_floor_count','replay_floor_root')`).all().map((row) => [row.key, row.value]));
  const restoreReplayState = () => {
    store.db.prepare(`INSERT OR REPLACE INTO activity_probe_state(
      probe_id,max_origin_sequence,retained_origin_floor,retired_context_json,max_occurred_at_ms,last_received_at_ms,
      last_clock_health,last_coverage_status) VALUES (?,?,?,?,?,?,?,?)`).run(...Object.values(originalState));
    store.db.prepare("UPDATE activity_principals SET event_id_prefix=? WHERE probe_id='probe-a'").run(originalPrefix);
    for (const [key, value] of Object.entries(originalMetadata)) {
      store.db.prepare('UPDATE activity_metadata SET value=? WHERE key=?').run(value, key);
    }
  };
  const securityState = () => ({
    claim: store.db.prepare('SELECT * FROM activity_runtime_claim').get(),
    events: store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value,
    changes: store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
    principals: store.db.prepare('SELECT COUNT(*) AS value FROM activity_principals').get().value,
    audit: store.db.prepare('SELECT COUNT(*) AS value FROM activity_audit').get().value,
    highWater: store.db.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
  });
  const corruptions = [
    ['negative retained floor', "UPDATE activity_probe_state SET retained_origin_floor=-1 WHERE probe_id='probe-a'"],
    ['text retained floor', "UPDATE activity_probe_state SET retained_origin_floor='junk' WHERE probe_id='probe-a'"],
    ['unsafe retained floor', "UPDATE activity_probe_state SET retained_origin_floor=9007199254740992 WHERE probe_id='probe-a'"],
    ['lowered retained floor', "UPDATE activity_probe_state SET retained_origin_floor=0 WHERE probe_id='probe-a'"],
    ['changed event prefix', `UPDATE activity_principals SET event_id_prefix='${'Z'.repeat(22)}' WHERE probe_id='probe-a'`],
    ['deleted probe state', "DELETE FROM activity_probe_state WHERE probe_id='probe-a'"],
    ['malformed replay root', "UPDATE activity_metadata SET value='bad' WHERE key='replay_floor_root'"],
    ['noncanonical replay count', "UPDATE activity_metadata SET value='01' WHERE key='replay_floor_count'"],
    ['negative replay revision', "UPDATE activity_metadata SET value='-1' WHERE key='replay_floor_revision'"],
  ];
  for (const [name, sql] of corruptions) {
    store.db.exec(sql);
    const before = securityState();
    const status = activitySchemaStatus(store.db);
    assert.equal(status.ready, false, name);
    assert.equal(
      status.reason,
      name.includes('replay count') || name.includes('replay revision')
        ? 'metadata_invariant_failed'
        : 'replay_floor_invariant_failed',
      name,
    );
    const health = store.health({ activityOwnerConfigured: true });
    assert.equal(health.activity.control_plane_available, false, name);
    assert.equal(health.features.includes(ACTIVITY_CONTRACT), false, name);
    assertActivityError(() => store.activity.activate(nowRef.value), 'activity_schema_not_ready');
    assertActivityError(() => pairReader(store, `reader-${name.replaceAll(' ', '-')}`, nowRef.value), 'activity_schema_not_ready');
    assertActivityError(() => store.activity.appendEvents(principal, {
      events: [event({ originSequence: 2, signalAt: nowRef.value })],
    }, nowRef.value), 'activity_schema_not_ready');
    assert.deepEqual(securityState(), before, name);
    restoreReplayState();
    assert.equal(activitySchemaStatus(store.db).ready, true, name);
  }
  store.close();

  const corrupt = new DatabaseSync(databasePath);
  corrupt.prepare("UPDATE activity_probe_state SET retained_origin_floor='junk' WHERE probe_id='probe-a'").run();
  const beforeRestart = {
    claim: corrupt.prepare('SELECT * FROM activity_runtime_claim').get(),
    changes: corrupt.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
    highWater: corrupt.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
  };
  corrupt.close();
  assert.throws(
    () => new ICoreStore(databasePath, { clock: () => nowRef.value, activityEnabled: true }),
    (error) => error?.code === 'activity_migration_incomplete',
  );
  const afterRestart = new DatabaseSync(databasePath);
  assert.deepEqual({
    claim: afterRestart.prepare('SELECT * FROM activity_runtime_claim').get(),
    changes: afterRestart.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
    highWater: afterRestart.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
  }, beforeRestart);
  afterRestart.prepare("UPDATE activity_probe_state SET retained_origin_floor=1 WHERE probe_id='probe-a'").run();
  afterRestart.close();
  store = new ICoreStore(databasePath, { clock: () => nowRef.value, activityEnabled: true });
  assert.equal(store.activity.schemaStatus().ready, true);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('replay floor tuple cannot be coordinated back to an older commit high-water', () => {
  const directory = tempDir('activity-replay-coordinated-rollback');
  const databasePath = path.join(directory, 'core.sqlite');
  const nowRef = { value: 10 * ACTIVITY_RAW_RETENTION_MS };
  let store = openStore(directory, nowRef);
  const probe = pairProbe(store, { now: nowRef.value - ACTIVITY_RAW_RETENTION_MS + 1 });
  let principal = store.activity.authenticate(probe.probe_token);
  const oldTime = nowRef.value;
  store.activity.appendEvents(principal, {
    events: [event({ originSequence: 1, signalAt: oldTime, ttl: ACTIVITY_RAW_RETENTION_MS })],
  }, oldTime);
  nowRef.value = oldTime + ACTIVITY_RAW_RETENTION_MS;
  store.activity.runRetention(nowRef.value);
  const oldTuple = Object.fromEntries(store.db.prepare(`SELECT key,value FROM activity_metadata
    WHERE key IN ('replay_floor_revision','replay_floor_count','replay_floor_root')`).all()
    .map((row) => [row.key, row.value]));
  store.activity.appendEvents(principal, {
    events: [event({ originSequence: 2, signalAt: nowRef.value })],
  }, nowRef.value);
  store.close();

  const corrupt = new DatabaseSync(databasePath);
  for (const [key, value] of Object.entries(oldTuple)) {
    corrupt.prepare('UPDATE activity_metadata SET value=? WHERE key=?').run(value, key);
  }
  const before = {
    claim: corrupt.prepare('SELECT * FROM activity_runtime_claim').get(),
    events: corrupt.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value,
    changes: corrupt.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
    highWater: corrupt.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
  };
  corrupt.close();
  assertActivityError(
    () => new ICoreStore(databasePath, { activityEnabled: true, clock: () => nowRef.value }),
    'activity_migration_incomplete',
  );
  const after = new DatabaseSync(databasePath, { readOnly: true });
  assert.deepEqual(after.prepare('SELECT * FROM activity_runtime_claim').get(), before.claim);
  assert.equal(after.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, before.events);
  assert.equal(after.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value, before.changes);
  assert.equal(after.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value, before.highWater);
  after.close();
  rmSync(directory, { recursive: true, force: true });
});

test('nonempty unbound legacy schemas 1, 2 and 3 plus clean clones fail before migration or binding', () => {
  const directory = tempDir('activity-legacy-nonempty-migration');
  const databasePath = path.join(directory, 'core.sqlite');
  const nowRef = { value: 10 * ACTIVITY_RAW_RETENTION_MS };
  let store = openStore(directory, nowRef);
  const probe = pairProbe(store, { now: nowRef.value - ACTIVITY_RAW_RETENTION_MS + 1 });
  const principal = store.activity.authenticate(probe.probe_token);
  const acceptedAt = nowRef.value;
  const original = event({ originSequence: 1, signalAt: acceptedAt, ttl: ACTIVITY_RAW_RETENTION_MS });
  store.activity.appendEvents(principal, { events: [original] }, acceptedAt);
  nowRef.value = acceptedAt + ACTIVITY_RAW_RETENTION_MS;
  store.activity.runRetention(nowRef.value);
  store.close();

  const legacy = new DatabaseSync(databasePath);
  legacy.exec(`
    DROP TABLE activity_replay_lineage_floors;
    DROP INDEX activity_principals_event_prefix_idx;
    ALTER TABLE activity_principals DROP COLUMN event_id_prefix;
    ALTER TABLE activity_principals DROP COLUMN retired_event_prefix_digest;
    ALTER TABLE activity_principals DROP COLUMN retired_floor_digest;
    ALTER TABLE activity_probe_state DROP COLUMN retained_origin_floor;
    ALTER TABLE activity_probe_state DROP COLUMN retired_context_json;
    DELETE FROM activity_metadata WHERE key='database_binding_digest';
    DELETE FROM activity_metadata WHERE key IN ('replay_floor_revision','replay_floor_count','replay_floor_root','accepted_event_count','retired_event_count');
    DELETE FROM activity_schema_migrations WHERE version=5;
    UPDATE core_metadata SET value='3' WHERE key='activity_schema_version';
  `);
  legacy.prepare("INSERT INTO activity_schema_migrations(version,state,checksum,committed_at_ms) VALUES (3,'committed',?,1)")
    .run(ACTIVITY_SCHEMA_V3_CHECKSUM);
  legacy.close();
  const clonePath = path.join(directory, 'legacy-v3-clone.sqlite');
  const legacyV2Path = path.join(directory, 'legacy-v2.sqlite');
  const legacyV1Path = path.join(directory, 'legacy-v1.sqlite');
  copyFileSync(databasePath, clonePath);
  copyFileSync(databasePath, legacyV2Path);
  copyFileSync(databasePath, legacyV1Path);
  const legacyV2 = new DatabaseSync(legacyV2Path);
  legacyV2.prepare("DELETE FROM activity_metadata WHERE key='database_role'").run();
  legacyV2.prepare('DELETE FROM activity_schema_migrations WHERE version=3').run();
  legacyV2.prepare("INSERT INTO activity_schema_migrations(version,state,checksum,committed_at_ms) VALUES (2,'committed',?,1)")
    .run(ACTIVITY_SCHEMA_V2_CHECKSUM);
  legacyV2.prepare("UPDATE core_metadata SET value='2' WHERE key='activity_schema_version'").run();
  legacyV2.close();
  const legacyV1 = new DatabaseSync(legacyV1Path);
  legacyV1.exec(`DROP TABLE activity_runtime_claim;
    DELETE FROM activity_metadata WHERE key IN ('database_role','commit_high_water');
    DELETE FROM activity_schema_migrations WHERE version=3;
    UPDATE core_metadata SET value='1' WHERE key='activity_schema_version';`);
  legacyV1.prepare("INSERT INTO activity_schema_migrations(version,state,checksum,committed_at_ms) VALUES (1,'committed',?,1)")
    .run(ACTIVITY_SCHEMA_V1_CHECKSUM);
  legacyV1.close();
  const candidates = [databasePath, clonePath, legacyV2Path, legacyV1Path];
  const before = new Map(candidates.map((candidate) => [
    candidate,
    createHash('sha256').update(readFileSync(candidate)).digest('hex'),
  ]));
  for (const candidate of candidates) {
    assert.throws(
      () => new ICoreStore(candidate, { clock: () => nowRef.value, activityEnabled: true }),
      (error) => error?.code === 'activity_legacy_binding_authorization_required',
    );
    assert.equal(createHash('sha256').update(readFileSync(candidate)).digest('hex'), before.get(candidate));
  }
  rmSync(directory, { recursive: true, force: true });
});

test('delete invalidates stale cursors while boundary cursor, snapshot retry and ack remain deterministic across restart', () => {
  const directory = tempDir('activity-delete-cursor');
  const databasePath = path.join(directory, 'core.sqlite');
  const nowRef = { value: 1_000_000 };
  let store = new ICoreStore(databasePath, { clock: () => nowRef.value, activityEnabled: true });
  const probe = pairProbe(store);
  const reader = pairReader(store);
  const readerPrincipal = store.activity.authenticate(reader.reader_token);
  store.activity.appendEvents(store.activity.authenticate(probe.probe_token), { events: [event()] });
  const acceptedPage = store.activity.changes(readerPrincipal, reader.initial_cursor);
  const acceptedCursor = acceptedPage.next_cursor;
  store.activity.revokeProbe('probe-a', nowRef.value + 1);
  const revokePage = store.activity.changes(readerPrincipal, acceptedCursor);
  const cursorAtRevoke = revokePage.next_cursor;
  store.activity.deleteProbe('probe-a', nowRef.value + 2);
  assertActivityError(() => store.activity.changes(readerPrincipal, reader.initial_cursor), 'resync_required');
  assertActivityError(() => store.activity.changes(readerPrincipal, acceptedCursor), 'resync_required');
  assert.equal(Number(store.db.prepare("SELECT value FROM activity_metadata WHERE key='retained_watermark'").get().value), store.activity.decodeCursor(cursorAtRevoke));
  const deletionPage = store.activity.changes(readerPrincipal, cursorAtRevoke);
  assert.deepEqual(deletionPage.events.map((item) => item.kind), ['activity.probe.deleted']);
  const firstSnapshot = store.activity.snapshot(readerPrincipal, nowRef.value + 3);
  const retrySnapshot = store.activity.snapshot(readerPrincipal, nowRef.value + 3);
  assert.deepEqual(firstSnapshot.summary, retrySnapshot.summary);
  assert.equal(firstSnapshot.base_cursor, retrySnapshot.base_cursor);
  assert.equal(store.activity.acknowledge(readerPrincipal, { cursor: firstSnapshot.base_cursor }, nowRef.value + 3).ok, true);
  assert.equal(store.activity.acknowledge(readerPrincipal, { cursor: firstSnapshot.base_cursor }, nowRef.value + 3).ok, true);
  const ackSequence = store.db.prepare('SELECT last_ack_sequence FROM activity_reader_acks WHERE principal_id=?').get(reader.principal_id).last_ack_sequence;
  store.close();

  store = new ICoreStore(databasePath, { clock: () => nowRef.value + 3, activityEnabled: true });
  assert.equal(store.db.prepare('SELECT last_ack_sequence FROM activity_reader_acks WHERE principal_id=?').get(reader.principal_id).last_ack_sequence, ackSequence);
  assert.deepEqual(store.activity.snapshot(store.activity.authenticate(reader.reader_token), nowRef.value + 3).summary.devices, []);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('device deletion advances watermark from lifecycle changes even when no raw event exists', () => {
  const directory = tempDir('activity-device-delete-cursor');
  const store = openStore(directory);
  pairProbe(store);
  const reader = pairReader(store);
  const readerPrincipal = store.activity.authenticate(reader.reader_token);
  store.activity.revokeProbe('probe-a', 1_000_001);
  const revokePage = store.activity.changes(readerPrincipal, reader.initial_cursor);
  const cursorAtRevoke = revokePage.next_cursor;
  const removedSequence = store.activity.decodeCursor(cursorAtRevoke);
  store.activity.deleteDevice('device-a', 1_000_002);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 0);
  assert.equal(Number(store.db.prepare("SELECT value FROM activity_metadata WHERE key='retained_watermark'").get().value), removedSequence);
  assertActivityError(() => store.activity.changes(readerPrincipal, reader.initial_cursor), 'resync_required');
  const boundary = store.activity.changes(readerPrincipal, cursorAtRevoke);
  assert.deepEqual(boundary.events.map((item) => item.kind), ['activity.device.deleted']);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('retention watermark follows the actual lifecycle change set it deletes', () => {
  const directory = tempDir('activity-retention-lifecycle-cursor');
  const nowRef = { value: 10 * ACTIVITY_RAW_RETENTION_MS };
  const store = openStore(directory, nowRef);
  pairProbe(store, { now: nowRef.value });
  const reader = pairReader(store, 'reader-a', nowRef.value);
  const readerPrincipal = store.activity.authenticate(reader.reader_token);
  store.activity.revokeProbe('probe-a', nowRef.value);
  const revokePage = store.activity.changes(readerPrincipal, reader.initial_cursor);
  const cursorAtRevoke = revokePage.next_cursor;
  nowRef.value += ACTIVITY_RAW_RETENTION_MS + 1;
  const cleanup = store.activity.runRetention(nowRef.value);
  assert.equal(cleanup.removed_events, 0);
  assert.equal(cleanup.retained_watermark, store.activity.decodeCursor(cursorAtRevoke));
  assertActivityError(() => store.activity.changes(readerPrincipal, reader.initial_cursor), 'resync_required');
  const boundary = store.activity.changes(readerPrincipal, cleanup.earliest_cursor);
  assert.deepEqual(boundary.events.map((item) => item.kind), ['activity.retention.cleaned']);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('restart, backup and restore preserve accepted events, revocation and watermark without chat contamination', async () => {
  const directory = tempDir('activity-recovery');
  const databasePath = path.join(directory, 'core.sqlite');
  const backupPath = path.join(directory, 'backup.sqlite');
  const staleBackupPath = path.join(directory, 'stale-backup.sqlite');
  const nowRef = { value: 1_000_000 };
  let store = new ICoreStore(databasePath, { clock: () => nowRef.value, activityEnabled: true });
  const probe = pairProbe(store);
  const reader = pairReader(store);
  store.activity.appendEvents(store.activity.authenticate(probe.probe_token), { events: [event()] });
  await store.backupDatabase(staleBackupPath);
  store.activity.revokeProbe('probe-a', nowRef.value + 1);
  const recoveryFloor = store.activity.recoveryManifest();
  const snapshotGeneration = Number(store.db.prepare("SELECT value FROM activity_metadata WHERE key='snapshot_generation'").get().value);
  const backupManifest = await store.backupDatabase(backupPath);
  assert.equal(backupManifest.snapshot_generation, snapshotGeneration);
  const nodeId = store.nodeId;
  store.close();

  store = new ICoreStore(databasePath, { clock: () => nowRef.value + 2, activityEnabled: true });
  assert.equal(store.nodeId, nodeId);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 1);
  assertActivityError(() => store.activity.appendEvents(store.activity.authenticate(probe.probe_token), { events: [event()] }, nowRef.value + 2), 'revoked_replay');
  store.close();

  const restoredPath = path.join(directory, 'restored.sqlite');
  const backupDb = new DatabaseSync(backupPath);
  await backup(backupDb, restoredPath);
  backupDb.close();
  const offlineVerification = verifyActivityRecoveryCandidate(restoredPath, backupManifest.recovery_manifest);
  assert.equal(offlineVerification.ok, true);
  assert.equal(offlineVerification.activation_authorized, false);
  const restoredReadOnly = new DatabaseSync(restoredPath, { readOnly: true });
  assert.equal(restoredReadOnly.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value, 1);
  assert.notEqual(restoredReadOnly.prepare("SELECT revoked_at_ms FROM activity_principals WHERE probe_id='probe-a'").get().revoked_at_ms, null);
  restoredReadOnly.close();
  assertActivityError(() => new ICoreStore(restoredPath, {
    clock: () => nowRef.value + 60_000,
    activityEnabled: true,
  }), 'backup_activation_unsupported');
  assertActivityError(() => new ICoreStore(restoredPath, { activityRecoveryFloor: backupManifest.recovery_manifest }), 'backup_activation_unsupported');
  assertActivityError(() => verifyActivityRecoveryCandidate(staleBackupPath, recoveryFloor), 'stale_activity_restore');
  rmSync(directory, { recursive: true, force: true });
});

test('safe rollback is empty-domain only and legacy chat remains compatible across migration', () => {
  const directory = tempDir('activity-rollback');
  const empty = openStore(directory);
  const rollback = empty.rollbackEmptyActivitySchema();
  assert.equal(rollback.core_schema_version, 4);
  assert.equal(empty.db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get().value, '4');
  assert.equal(empty.db.prepare("SELECT COUNT(*) AS value FROM sqlite_master WHERE name='chat_messages'").get().value, 1);
  empty.close();

  const remigrated = openStore(directory);
  pairProbe(remigrated);
  assertActivityError(() => remigrated.rollbackEmptyActivitySchema(), 'activity_rollback_requires_empty_domain');
  assert.equal(remigrated.db.prepare("SELECT COUNT(*) AS value FROM sqlite_master WHERE name='chat_messages'").get().value, 1);
  remigrated.close();
  rmSync(directory, { recursive: true, force: true });
});

test('runtime claim permits only clean restart and leaves an unclean or expired claim untouched', () => {
  const directory = tempDir('activity-runtime-fence');
  const databasePath = path.join(directory, 'core.sqlite');
  const nowRef = { value: 1_000_000 };
  const first = new ICoreStore(databasePath, {
    clock: () => nowRef.value,
    activityRuntimeId: 'runtime-a',
    activityRuntimeLeaseMs: 100,
    activityEnabled: true,
  });
  const probe = pairProbe(first);
  const reader = pairReader(first);
  const staleProbe = first.activity.authenticate(probe.probe_token);
  const staleReader = first.activity.authenticate(reader.reader_token);
  first.activity.appendEvents(staleProbe, { events: [event()] });
  const cursorAtEvent = first.activity.changes(staleReader, reader.initial_cursor).next_cursor;
  const before = {
    claim: first.db.prepare('SELECT * FROM activity_runtime_claim').get(),
    changes: first.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
    highWater: first.db.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
  };
  for (const [attemptedAt, runtimeId, code] of [
    [nowRef.value + 1, 'runtime-a', 'activity_authority_busy'],
    [nowRef.value + 1, 'runtime-b', 'activity_authority_busy'],
    [nowRef.value + 101, 'runtime-a', 'activity_recovery_required'],
    [nowRef.value + 101, 'runtime-b', 'activity_recovery_required'],
  ]) {
    assertActivityError(() => new ICoreStore(databasePath, {
      clock: () => attemptedAt,
      activityRuntimeId: runtimeId,
      activityRuntimeLeaseMs: 100,
      activityEnabled: true,
    }), code);
  }
  assert.deepEqual(first.db.prepare('SELECT * FROM activity_runtime_claim').get(), before.claim);
  assert.equal(first.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value, before.changes);
  assert.equal(first.db.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value, before.highWater);
  assert.doesNotThrow(() => first.activity.summary(staleReader));
  first.close();

  nowRef.value += 101;
  const second = new ICoreStore(databasePath, {
    clock: () => nowRef.value,
    activityRuntimeId: 'runtime-b',
    activityRuntimeLeaseMs: 100,
    activityEnabled: true,
  });
  const secondProbe = second.activity.authenticate(probe.probe_token);
  const secondReader = second.activity.authenticate(reader.reader_token);
  const runtimeHealth = second.health({ activityOwnerConfigured: true }).activity;
  assert.equal(runtimeHealth.control_plane_available, true);
  assert.equal(runtimeHealth.takeover_supported, false);
  assert.equal(runtimeHealth.backup_activation_supported, false);
  assert.equal(second.activity.summary(secondReader).devices[0].state, 'unknown');
  assert.equal(second.activity.summary(secondReader).devices[0].sources[0].status_reason, 'core_restart_gap');
  assert.equal(second.activity.appendEvents(secondProbe, { events: [event()] }).results[0].status, 'duplicate');
  assert.equal(second.activity.summary(secondReader).devices[0].state, 'unknown');
  second.activity.appendEvents(secondProbe, { events: [event({ originSequence: 2, signalAt: nowRef.value })] });
  assert.equal(second.activity.summary(secondReader).devices[0].state, 'active');
  assert.doesNotThrow(() => second.activity.changes(secondReader, cursorAtEvent));

  assert.equal(second.activity.runtimeStatus().ready, true);
  second.close();
  rmSync(directory, { recursive: true, force: true });
});

test('trusted recovery floor is closed, signed, high-water aware and checked before candidate mutation', async () => {
  const directory = tempDir('activity-recovery-floor');
  const livePath = path.join(directory, 'live.sqlite');
  const stalePath = path.join(directory, 'stale.sqlite');
  const nowRef = { value: 1_000_000 };
  const live = new ICoreStore(livePath, { clock: () => nowRef.value, activityEnabled: true });
  const probe = pairProbe(live);
  pairReader(live);
  await live.backupDatabase(stalePath);
  live.activity.appendEvents(live.activity.authenticate(probe.probe_token), { events: [event()] });
  const floor = live.activity.recoveryManifest();
  assert.equal(floor.latest_change_sequence, 1);
  assert.ok(floor.commit_high_water >= 3);
  live.close();

  const staleBefore = new DatabaseSync(stalePath, { readOnly: true });
  const claimBefore = staleBefore.prepare('SELECT * FROM activity_runtime_claim').get();
  const highWaterBefore = staleBefore.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value;
  staleBefore.close();
  assertActivityError(
    () => verifyActivityRecoveryCandidate(stalePath, floor),
    'stale_activity_restore',
  );
  const staleAfter = new DatabaseSync(stalePath, { readOnly: true });
  assert.deepEqual(staleAfter.prepare('SELECT * FROM activity_runtime_claim').get(), claimBefore);
  assert.equal(staleAfter.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value, highWaterBefore);
  staleAfter.close();

  for (const invalidFloor of [
    { ...floor, digest: `${floor.digest.slice(0, -1)}x` },
    { ...floor, extra: true },
    { ...floor, commit_high_water: '3' },
    { ...floor, principals: [...floor.principals].reverse() },
  ]) {
    assertActivityError(
      () => verifyActivityRecoveryCandidate(livePath, invalidFloor),
      'recovery_lineage_unverified',
    );
  }
  assertActivityError(
    () => createICoreServer({ databasePath: livePath, activityAdminSecret: OWNER_SECRET, requireActivityRecoveryFloor: true }),
    'recovery_floor_required',
  );
  assertActivityError(() => createICoreServer({
    databasePath: livePath,
    activityAdminSecret: OWNER_SECRET,
    activityRecoveryFloor: floor,
    requireActivityRecoveryFloor: true,
  }), 'recovery_history_diverged');
  rmSync(directory, { recursive: true, force: true });
});

test('offline recovery manifest protects the complete runtime crash marker', async () => {
  const directory = tempDir('activity-recovery-runtime-claim');
  const livePath = path.join(directory, 'live.sqlite');
  const candidatePath = path.join(directory, 'candidate.sqlite');
  const live = new ICoreStore(livePath, { activityEnabled: true, activityRuntimeId: 'runtime-live' });
  const result = await live.backupDatabase(candidatePath);
  const candidate = new DatabaseSync(candidatePath);
  const original = candidate.prepare('SELECT * FROM activity_runtime_claim').get();
  const highWater = candidate.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value;
  for (const [name, sql] of [
    ['runtime-id', "UPDATE activity_runtime_claim SET runtime_id='tampered-runtime'"],
    ['lease-expiry', 'UPDATE activity_runtime_claim SET lease_expires_at_ms=lease_expires_at_ms+1'],
    ['crash-marker-erasure', "UPDATE activity_runtime_claim SET runtime_id='',lease_expires_at_ms=0"],
  ]) {
    candidate.exec(sql);
    assertActivityError(
      () => verifyActivityRecoveryCandidate(candidatePath, result.recovery_manifest),
      'recovery_history_diverged',
    );
    assert.equal(candidate.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value, highWater, name);
    candidate.prepare(`UPDATE activity_runtime_claim SET runtime_id=?,runtime_fence=?,lease_expires_at_ms=? WHERE singleton=1`)
      .run(original.runtime_id, original.runtime_fence, original.lease_expires_at_ms);
  }
  candidate.close();
  live.close();
  rmSync(directory, { recursive: true, force: true });
});

test('offline recovery rejects coordinated same-height raw and projection tampering before manifest signing', async () => {
  const directory = tempDir('activity-recovery-divergence');
  const seedPath = path.join(directory, 'seed.sqlite');
  const candidatePath = path.join(directory, 'candidate.sqlite');
  const branchAPath = path.join(directory, 'branch-a.sqlite');
  const branchBPath = path.join(directory, 'branch-b.sqlite');
  const nowRef = { value: 1_000_000 };
  const seed = new ICoreStore(seedPath, { clock: () => nowRef.value, activityEnabled: true });
  const probe = pairProbe(seed);
  seed.activity.appendEvents(seed.activity.authenticate(probe.probe_token), { events: [event()] });
  await seed.backupDatabase(candidatePath);
  seed.close();
  copyFileSync(candidatePath, branchAPath);
  copyFileSync(candidatePath, branchBPath);
  for (const [branchPath, kind, state, statusReason] of [
    [branchAPath, 'session.locked', 'locked', 'fresh_signal'],
    [branchBPath, 'network.present', 'network_only', 'reachability_only'],
  ]) {
    const branch = new DatabaseSync(branchPath);
    const row = branch.prepare('SELECT * FROM activity_events').get();
    const digest = canonicalActivityDigest(normalizeActivityEvent({
      contract: ACTIVITY_CONTRACT,
      schema_version: 1,
      event_id: row.event_id,
      device_id: row.device_id,
      probe_id: row.probe_id,
      origin_sequence: Number(row.origin_sequence),
      kind,
      signal_at_ms: Number(row.occurred_at_ms),
      ttl_ms: Number(row.ttl_ms),
      confidence: row.confidence,
      source: row.source,
      coverage: JSON.parse(row.coverage_json),
      payload: {},
    }));
    branch.prepare("UPDATE activity_events SET kind=?,payload_json='{}',canonical_digest=? WHERE event_id=?")
      .run(kind, digest, row.event_id);
    branch.prepare('UPDATE activity_projections SET state=?,status_reason=? WHERE current_event_id=?')
      .run(state, statusReason, row.event_id);
    branch.close();
  }
  const manifestFor = (branchPath) => {
    const branch = new DatabaseSync(branchPath, { readOnly: true });
    try {
      return activityRecoveryManifestForDatabase(branch, {
        nodeId: branch.prepare("SELECT value FROM core_metadata WHERE key='node_id'").get().value,
        cursorSecret: branch.prepare("SELECT value FROM core_metadata WHERE key='cursor_secret'").get().value,
      });
    } finally {
      branch.close();
    }
  };
  assertActivityError(() => manifestFor(branchAPath), 'activity_schema_not_ready');
  assertActivityError(() => manifestFor(branchBPath), 'activity_schema_not_ready');
  rmSync(directory, { recursive: true, force: true });
});

test('active activity data plane fails closed when durable cursor identity or database role changes', () => {
  const directory = tempDir('activity-runtime-durable-identity');
  const store = openStore(directory);
  const probe = pairProbe(store);
  const reader = pairReader(store);
  const probePrincipal = store.activity.authenticate(probe.probe_token);
  const readerPrincipal = store.activity.authenticate(reader.reader_token);
  store.activity.appendEvents(probePrincipal, { events: [event()] });
  const originalSecret = store.cursorSecret;
  const state = () => ({
    claim: store.db.prepare('SELECT * FROM activity_runtime_claim').get(),
    changes: store.db.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
    events: store.db.prepare('SELECT COUNT(*) AS value FROM activity_events').get().value,
    highWater: store.db.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
  });
  const actions = [
    () => store.activity.appendEvents(probePrincipal, { events: [event({ originSequence: 2 })] }),
    () => store.activity.summary(readerPrincipal),
    () => store.activity.changes(readerPrincipal, reader.initial_cursor),
    () => store.activity.acknowledge(readerPrincipal, { cursor: reader.initial_cursor }),
    () => pairProbe(store, { deviceId: 'other-device', probeId: 'other-probe' }),
    () => store.activity.revokeProbe('probe-a'),
    () => store.activity.deleteProbe('probe-a'),
    () => store.activity.runRetention(),
    () => store.activity.adminExport(),
  ];
  store.db.prepare("UPDATE core_metadata SET value=? WHERE key='cursor_secret'").run('Q'.repeat(43));
  assert.equal(store.health({ activityOwnerConfigured: true }).activity.control_plane_available, false);
  for (const action of actions) {
    const before = state();
    assertActivityError(action, 'core_metadata_invariant_failed');
    assert.deepEqual(state(), before);
  }
  store.db.prepare("UPDATE core_metadata SET value=? WHERE key='cursor_secret'").run(originalSecret);
  assertActivityError(() => store.activity.runRetention(), 'activity_schema_not_ready');
  assert.equal(activitySchemaStatus(store.db).ready, true);
  store.db.prepare("UPDATE activity_metadata SET value='backup_read_only' WHERE key='database_role'").run();
  assert.equal(store.health({ activityOwnerConfigured: true }).activity.control_plane_available, false);
  for (const action of actions) {
    const before = state();
    assertActivityError(action, 'activity_database_role_changed');
    assert.deepEqual(state(), before);
  }
  store.db.prepare("UPDATE activity_metadata SET value='live' WHERE key='database_role'").run();
  assert.equal(activitySchemaStatus(store.db).ready, true);
  assert.equal(store.activity.schemaStatus().ready, false);
  store.close();
  rmSync(directory, { recursive: true, force: true });
});

test('existing Core identity metadata never regenerates and activity health validates principal lineage', async () => {
  const directory = tempDir('activity-core-identity');
  const sourcePath = path.join(directory, 'source.sqlite');
  const source = new ICoreStore(sourcePath, { activityEnabled: true });
  const probe = pairProbe(source);
  const reader = pairReader(source);
  source.close();

  for (const [index, mutation] of [
    [0, "DELETE FROM core_metadata WHERE key='node_id'"],
    [1, "DELETE FROM core_metadata WHERE key='cursor_secret'"],
    [2, "UPDATE core_metadata SET value='bad node id' WHERE key='node_id'"],
    [3, "UPDATE core_metadata SET value='short' WHERE key='cursor_secret'"],
  ]) {
    const candidatePath = path.join(directory, `candidate-${index}.sqlite`);
    const sourceDb = new DatabaseSync(sourcePath, { readOnly: true });
    await backup(sourceDb, candidatePath);
    sourceDb.close();
    const candidate = new DatabaseSync(candidatePath);
    candidate.exec(mutation);
    const before = {
      claim: candidate.prepare('SELECT * FROM activity_runtime_claim').get(),
      changes: candidate.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
      highWater: candidate.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
      nodeId: candidate.prepare("SELECT value FROM core_metadata WHERE key='node_id'").get()?.value ?? null,
      cursorSecret: candidate.prepare("SELECT value FROM core_metadata WHERE key='cursor_secret'").get()?.value ?? null,
    };
    candidate.close();
    assertActivityError(() => new ICoreStore(candidatePath, { activityEnabled: true }), 'core_metadata_invariant_failed');
    const after = new DatabaseSync(candidatePath, { readOnly: true });
    assert.deepEqual(after.prepare('SELECT * FROM activity_runtime_claim').get(), before.claim);
    assert.equal(after.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value, before.changes);
    assert.equal(after.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value, before.highWater);
    assert.equal(after.prepare("SELECT value FROM core_metadata WHERE key='node_id'").get()?.value ?? null, before.nodeId);
    assert.equal(after.prepare("SELECT value FROM core_metadata WHERE key='cursor_secret'").get()?.value ?? null, before.cursorSecret);
    after.close();
  }

  const live = new ICoreStore(sourcePath, { activityEnabled: true });
  const readerPrincipal = live.activity.authenticate(reader.reader_token);
  live.db.prepare("UPDATE activity_principals SET authority_node_id='wrong-node' WHERE probe_id='probe-a'").run();
  let health = live.health({ activityOwnerConfigured: true });
  assert.equal(health.activity.control_plane_available, false);
  assert.equal(health.features.includes(ACTIVITY_CONTRACT), false);
  assertActivityError(() => live.activity.summary(readerPrincipal), 'activity_schema_not_ready');
  live.db.prepare('UPDATE activity_principals SET authority_node_id=? WHERE probe_id=?').run(live.nodeId, 'probe-a');
  live.db.prepare("UPDATE core_metadata SET value='wrong-node' WHERE key='node_id'").run();
  health = live.health({ activityOwnerConfigured: true });
  assert.equal(health.ok, false);
  assert.deepEqual(health.features, []);
  assert.equal(health.activity.status, 'core_metadata_invariant_failed');
  assertActivityError(() => live.activity.summary(readerPrincipal), 'core_metadata_invariant_failed');
  live.close();
  rmSync(directory, { recursive: true, force: true });
});

test('activity cursor rejects a future lineage position and an expired backup remains non-activatable', async () => {
  const directory = tempDir('activity-future-cursor');
  const databasePath = path.join(directory, 'core.sqlite');
  const backupPath = path.join(directory, 'before-event.sqlite');
  const nowRef = { value: 1_000_000 };
  const live = new ICoreStore(databasePath, { clock: () => nowRef.value, activityRuntimeLeaseMs: 100, activityEnabled: true });
  const probe = pairProbe(live);
  const reader = pairReader(live);
  await live.backupDatabase(backupPath);
  live.activity.appendEvents(live.activity.authenticate(probe.probe_token), { events: [event()] });
  live.activity.appendEvents(live.activity.authenticate(probe.probe_token), {
    events: [event({ originSequence: 2, signalAt: nowRef.value + 1 })],
  });
  const liveReader = live.activity.authenticate(reader.reader_token);
  const latestCursor = live.activity.changes(liveReader, reader.initial_cursor).next_cursor;
  assert.deepEqual(live.activity.changes(liveReader, latestCursor).events, []);
  const futureCursor = live.activity.encodeCursor(live.activity.decodeCursor(latestCursor) + 1);
  assertActivityError(() => live.activity.changes(liveReader, futureCursor), 'resync_required');
  live.close();

  nowRef.value += 101;
  assertActivityError(() => new ICoreStore(backupPath, {
    clock: () => nowRef.value,
    activityRuntimeLeaseMs: 100,
    activityEnabled: true,
  }), 'backup_activation_unsupported');
  rmSync(directory, { recursive: true, force: true });
});

test('persisted device, activity and consumed pairing secrets cannot cross authority domains on restart', async () => {
  const directory = tempDir('activity-secret-domains');
  const databasePath = path.join(directory, 'core.sqlite');
  const devicePairingCode = 'pairing-code-long-enough';
  let core = createICoreServer({
    databasePath,
    pairingCode: devicePairingCode,
    workerSecret: 'worker-secret-long-enough',
    activityAdminSecret: OWNER_SECRET,
  });
  const address = await core.listen({ port: 0 });
  const baseUrl = `http://127.0.0.1:${address.port}`;
  const pairedDevice = await jsonRequest(`${baseUrl}/v1/core/devices/pair`, {
    method: 'POST',
    body: {
      pairing_code: devicePairingCode,
      device_id: 'legacy-device',
      display_name: 'legacy device',
      platform: 'test',
      client_version: '1',
      capabilities: [],
    },
  });
  const pairedProbe = await pairProbeHttp(baseUrl);
  await core.close();

  const leaseStore = new ICoreStore(databasePath);
  const activeLease = leaseStore.acquireWorkerLease({
    workload: 'memory_v3',
    holder_id: 'secret-domain-test',
    ttl_ms: 300_000,
  });
  leaseStore.close();
  const mailSecret = 'mail-relay-secret-long-enough';
  const relay = {
    tokenHash: createHash('sha256').update(mailSecret).digest('hex'),
    close() {},
  };
  const activityTokenRelay = {
    tokenHash: createHash('sha256').update(pairedProbe.body.probe_token).digest('hex'),
    close() {},
  };
  const before = new DatabaseSync(databasePath, { readOnly: true });
  const beforeState = {
    claim: before.prepare('SELECT * FROM activity_runtime_claim').get(),
    changes: before.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value,
    highWater: before.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value,
  };
  before.close();

  for (const options of [
    { activityAdminSecret: pairedDevice.body.device_token, workerSecret: 'fresh-worker-secret' },
    { activityAdminSecret: OWNER_SECRET, workerSecret: pairedProbe.body.probe_token },
    { activityAdminSecret: OWNER_SECRET, workerSecret: 'fresh-worker-secret', pairingCode: pairedProbe.body.probe_token },
    { activityAdminSecret: devicePairingCode, workerSecret: 'fresh-worker-secret' },
    { activityAdminSecret: activeLease.lease_token, workerSecret: 'fresh-worker-secret' },
    { activityAdminSecret: OWNER_SECRET, workerSecret: activeLease.lease_token },
    { activityAdminSecret: OWNER_SECRET, workerSecret: 'fresh-worker-secret', pairingCode: activeLease.lease_token },
    { activityAdminSecret: mailSecret, workerSecret: 'fresh-worker-secret', shortcutMailRelay: relay },
    { activityAdminSecret: OWNER_SECRET, workerSecret: 'fresh-worker-secret', shortcutMailRelay: activityTokenRelay },
  ]) {
    assert.throws(
      () => createICoreServer({ databasePath, ...options }),
      (error) => error?.code === 'authority_secret_conflict' && !/device|activity|pairing/i.test(error.message.replace('authority credentials', '')),
    );
  }
  const after = new DatabaseSync(databasePath, { readOnly: true });
  assert.deepEqual(after.prepare('SELECT * FROM activity_runtime_claim').get(), beforeState.claim);
  assert.equal(after.prepare('SELECT COUNT(*) AS value FROM activity_changes').get().value, beforeState.changes);
  assert.equal(after.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value, beforeState.highWater);
  after.close();
  core = createICoreServer({
    databasePath,
    pairingCode: devicePairingCode,
    workerSecret: 'fresh-worker-secret',
    activityAdminSecret: OWNER_SECRET,
    shortcutMailRelay: relay,
  });
  assert.equal(core.store.isPairingCodeConsumed(devicePairingCode), true);
  const replaceBefore = core.store.db.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value;
  for (const secret of [pairedProbe.body.probe_token, pairedDevice.body.device_token, mailSecret]) {
    assertActivityError(() => core.replacePairingCode(secret), 'authority_secret_conflict');
  }
  assert.equal(core.store.db.prepare("SELECT value FROM activity_metadata WHERE key='commit_high_water'").get().value, replaceBefore);
  await core.close();
  rmSync(directory, { recursive: true, force: true });
});

test('configured authority collisions and malformed mail hashes fail before creating a new database', () => {
  const directory = tempDir('activity-new-database-secret-preflight');
  const databasePath = path.join(directory, 'core.sqlite');
  const shared = 'shared-authority-secret-long-enough';
  assertActivityError(() => createICoreServer({
    databasePath,
    activityAdminSecret: shared,
    workerSecret: shared,
  }), 'authority_secret_conflict');
  assert.equal(existsSync(databasePath), false);
  assertActivityError(() => createICoreServer({
    databasePath,
    activityAdminSecret: OWNER_SECRET,
    workerSecret: 'fresh-worker-secret',
    shortcutMailRelay: { tokenHash: 'not-a-sha256-hash', close() {} },
  }), 'invalid_authority_configuration');
  assert.equal(existsSync(databasePath), false);
  rmSync(directory, { recursive: true, force: true });
});
