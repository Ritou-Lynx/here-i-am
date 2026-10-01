import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import {
  ActivityControlPlane, ACTIVITY_KINDS, normalizeActivityEvent,
} from '../../../../../tools/i_core/activity_control_plane.mjs';

// Purely in-memory Core implementation exercise; no HTTP/server/socket, files
// containing a database, OS source, real state, or real credentials are used.
const dartExe = process.argv[2];
assert.ok(dartExe, 'Pass the path to an already installed Dart executable.');
assert.ok(process.argv.slice(3).every((arg) => arg === '--write-fixture'));
const fixtureUrl = new URL('./fixtures/synthetic_events.json', import.meta.url);
const db = new DatabaseSync(':memory:');
db.exec('CREATE TABLE core_metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
db.prepare('INSERT INTO core_metadata(key,value) VALUES (?,?)').run('cursor_secret', 'S'.repeat(43));
db.prepare('INSERT INTO core_metadata(key,value) VALUES (?,?)').run('node_id', 'synthetic-node');
let now = 2000000;
let prefixIndex = 0;
const plane = new ActivityControlPlane(db, {
  nodeId: 'synthetic-node', cursorSecret: 'S'.repeat(43),
  databaseBindingDigest: 'a'.repeat(64), clock: () => now,
  eventIdPrefixFactory: () => (prefixIndex++ === 0 ? 'A' : 'B').repeat(22),
});
try {
  const principals = new Map();
  const registrations = ['android_usage_events', 'android_screen_state'].map((source) => {
    const allowed = source === 'android_usage_events'
      ? ['app.category_active', 'probe.permission_changed', 'probe.error', 'probe.heartbeat']
      : ['screen.interactive', 'screen.non_interactive', 'session.unlocked', 'probe.error', 'probe.heartbeat'];
    const profile = {
      device_id: 'synthetic-android', probe_id: source === 'android_usage_events' ? 'synthetic-usage' : 'synthetic-screen',
      display_name: 'Synthetic Android probe', source,
      coverage_mode: 'discrete_best_effort', expected_report_interval_ms: 30000, expiry_slo_ms: 300000,
      allowed_kinds: allowed,
      capabilities: source === 'android_usage_events' ? ['usage_events', 'probe_error.collection_failed'] : ['probe_error.collection_failed'],
    };
    assert.ok(allowed.every((kind) => ACTIVITY_KINDS.includes(kind)));
    const issued = plane.pairProbe(profile);
    // Synthetic credential exists only in this local memory, never in fixtures.
    principals.set(profile.probe_id, plane.authenticate(issued.probe_token));
    return { ...profile, event_id_prefix: issued.event_id_prefix };
  });
  const generation = spawnSync(dartExe, [fileURLToPath(new URL('./generate_synthetic_events.dart', import.meta.url))], {
    input: JSON.stringify(registrations), encoding: 'utf8', shell: false,
  });
  assert.equal(generation.status, 0, generation.stderr);
  const generated = JSON.parse(generation.stdout);
  assert.equal(generated.events.length, 20);
  if (process.argv.includes('--write-fixture')) writeFileSync(fixtureUrl, generation.stdout, 'utf8');
  assert.deepEqual(generated, JSON.parse(readFileSync(fixtureUrl, 'utf8')), 'checked-in sample drifted from actual Dart output');
  now += 1000;
  const reader = plane.pairSummaryReader({ installation_id: 'synthetic-reader', display_name: 'Synthetic reader' });
  const readerPrincipal = plane.authenticate(reader.reader_token);
  const sequences = new Map();
  let diagnosticUnknown = 0;
  for (const event of generated.events) {
    assert.deepEqual(normalizeActivityEvent(event), event);
    assert.equal(event.origin_sequence, (sequences.get(event.probe_id) ?? 0) + 1);
    sequences.set(event.probe_id, event.origin_sequence);
    const response = plane.appendEvents(principals.get(event.probe_id), { events: [event] });
    assert.equal(response.results[0].status, 'accepted');
    const source = plane.summary(readerPrincipal).devices.flatMap((device) => device.sources).find((source) => source.probe_id === event.probe_id);
    assert.ok(!['quiet_observed', 'resting_candidate', 'sleep_candidate'].includes(source.state));
    if (['probe.permission_changed', 'probe.error'].includes(event.kind)) {
      assert.equal(source.state, 'unknown');
      diagnosticUnknown++;
    }
  }
  // Accepted same bytes are duplicate, including after their TTL deadline.
  const first = generated.events[0];
  assert.equal(plane.appendEvents(principals.get(first.probe_id), { events: [first] }).results[0].status, 'duplicate');
  // The authority lease is renewed at the synthetic clock before advancing.
  // Test TTL at the same time by making the never-accepted sample older.
  const last = generated.events.at(-1);
  const expired = { ...last, origin_sequence: last.origin_sequence + 1,
    event_id: `${registrations[1].event_id_prefix}.${last.origin_sequence + 1}`,
    signal_at_ms: now - 300001,
    coverage: { ...last.coverage, window_start_ms: now - 300001, window_end_ms: now - 300001 } };
  assert.throws(() => plane.appendEvents(principals.get(last.probe_id), { events: [expired] }), (e) => e.code === 'ttl_expired');
  const ttlBoundary = { ...expired, signal_at_ms: now - 300000,
    coverage: { ...expired.coverage, window_start_ms: now - 300000, window_end_ms: now - 300000 } };
  assert.equal(plane.appendEvents(principals.get(last.probe_id), { events: [ttlBoundary] }).results[0].status, 'accepted');
  now++;
  assert.equal(plane.appendEvents(principals.get(last.probe_id), { events: [ttlBoundary] }).results[0].status, 'duplicate');
  let negativeCases = 0;
  for (const field of ['package_name', 'app_name', 'message_body', 'location', 'ble_raw_packet', 'heart_rate']) {
    assert.throws(() => normalizeActivityEvent({ ...first, payload: { ...first.payload, [field]: 'SYNTHETIC_PRIVATE' } }), (e) => e.code === 'unknown_field');
    negativeCases++;
  }
  assert.throws(() => normalizeActivityEvent({ ...first, received_at_ms: now }), (e) => e.code === 'unknown_field');
  negativeCases++;
  console.log(JSON.stringify({
    synthetic_only: true, fixture_events: generated.events.length,
    existing_validator_passed: generated.events.length,
    in_memory_core_accepted: generated.events.length,
    diagnostic_unknown_assertions: diagnosticUnknown,
    privacy_negative_cases: negativeCases,
    duplicate_and_ttl_boundary_checks: 'passed',
    no_network_or_device: true,
  }));
} finally {
  plane.releaseRuntimeClaim();
  db.close();
}
