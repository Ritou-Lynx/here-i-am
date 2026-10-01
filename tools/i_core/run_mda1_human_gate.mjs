import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { existsSync, lstatSync, mkdtempSync, realpathSync, rmSync } from 'node:fs';
import { request as httpRequest } from 'node:http';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createICoreServer } from './i_core_server.mjs';

const ROOT = '/v1/core/activity';
const TEMP_PREFIX = 'mda1-human-gate-';
const BOUNDARIES = Object.freeze([
  'synthetic_loopback_only',
  'no_real_device_or_android_gate',
  'no_sleep_inference',
  'human_acceptance_pending',
]);
const CHECKPOINTS = Object.freeze([
  'paired', 'accepted_and_replayed', 'least_privilege_checked', 'revoked_before_restart',
  'restart_gap_checked', 'restored_then_revoked', 'reader_evidence_checked',
]);

class GateCheck extends Error {
  constructor(check) { super(check); this.check = check; }
}

function check(value, name) { if (!value) throw new GateCheck(name); }
function equal(actual, expected, name) { check(actual === expected, name); }
function lexicalBinding(record) {
  return record && path.dirname(record.lexical) === record.parentCanonical
    && path.basename(record.lexical).startsWith(TEMP_PREFIX);
}
/** Pure guard: a later junction/symlink or a different canonical directory is never ours to remove. */
export function isExactOwnedTemporaryDirectory(record, { canonicalize = realpathSync, stat = lstatSync } = {}) {
  if (!lexicalBinding(record)) return false;
  try {
    const currentStat = stat(record.lexical);
    if (currentStat.isSymbolicLink() || currentStat.dev !== record.createdDev || currentStat.ino !== record.createdIno) return false;
    const current = canonicalize(record.lexical);
    return typeof record.canonical === 'string' && current === record.canonical;
  } catch { return false; }
}
export function createOwnedTemporaryDirectory({ onCreated, parentPath = tmpdir, create = mkdtempSync, canonicalize = realpathSync, stat = lstatSync } = {}) {
  const parentCanonical = canonicalize(parentPath());
  const lexical = create(path.join(parentCanonical, TEMP_PREFIX));
  const record = { parentCanonical, lexical, canonical: null, createdDev: null, createdIno: null };
  onCreated?.(record); // Register before lstat/realpath: no post-mkdtemp handle can be lost.
  const created = stat(lexical);
  record.createdDev = created.dev; record.createdIno = created.ino;
  const canonical = canonicalize(lexical);
  check(path.dirname(canonical) === parentCanonical && path.basename(lexical).startsWith(TEMP_PREFIX), 'temp_directory_binding');
  record.canonical = canonical;
  return record;
}
export function removeOwnTempDirectory(record) {
  if (!record) return false;
  // A post-mkdtemp validation failure has no canonical identity yet, but the exact
  // lexical directory came directly from mkdtemp under our canonical parent.
  if (record.canonical === null) {
    if (!lexicalBinding(record)) return false;
    try {
      const current = lstatSync(record.lexical);
      if (current.isSymbolicLink() || current.dev !== record.createdDev || current.ino !== record.createdIno) return false;
      rmSync(record.lexical, { recursive: true, force: false });
      return !existsSync(record.lexical);
    } catch { return false; }
  }
  if (!isExactOwnedTemporaryDirectory(record)) return false;
  try {
    rmSync(record.lexical, { recursive: true, force: false });
    return !existsSync(record.lexical);
  } catch { return false; }
}
function event({ deviceId, probeId, prefix, sequence, kind, source, coverageMode, now }) {
  return {
    contract: 'device.activity.v1', schema_version: 1,
    event_id: `${prefix}.${sequence}`, device_id: deviceId, probe_id: probeId,
    origin_sequence: sequence, kind, signal_at_ms: now, ttl_ms: 60_000,
    confidence: 'high', source,
    coverage: {
      mode: coverageMode, window_start_ms: now - 1_000, window_end_ms: now,
      expected_report_interval_ms: coverageMode === 'continuous' ? 30_000 : 300_000,
    },
    payload: {},
  };
}
export function rawRequest(base, method, route, token, bytes = Buffer.alloc(0)) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const succeed = (value) => { if (!settled) { settled = true; resolve(value); } };
    const fail = (error) => { if (!settled) { settled = true; reject(error); } };
    const outgoing = httpRequest(`${base}${route}`, {
      method, agent: false,
      headers: {
        'X-Core-Protocol': '0.1', Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json', 'Content-Length': bytes.length,
      },
    }, (incoming) => {
      const chunks = []; let length = 0;
      incoming.once('error', fail);
      incoming.once('aborted', () => fail(new GateCheck('response_aborted')));
      incoming.on('data', (chunk) => {
        length += chunk.length;
        if (length > 1024 * 1024) { outgoing.destroy(new GateCheck('response_limit')); return; }
        else chunks.push(chunk);
      });
      incoming.once('end', () => {
        if (settled) return;
        try { succeed({ status: incoming.statusCode, body: JSON.parse(Buffer.concat(chunks).toString('utf8')) }); }
        catch { fail(new GateCheck('response_json')); }
      });
    });
    outgoing.once('error', fail);
    outgoing.setTimeout(30_000, () => outgoing.destroy(new GateCheck('request_timeout')));
    outgoing.end(bytes);
  });
}
function bodyBytes(value) { return Buffer.from(JSON.stringify(value)); }
function errorCode(result, status, code, name) {
  equal(result.status, status, `${name}_status`);
  equal(result.body?.error?.code, code, `${name}_code`);
}
export function assertAcceptedLineage(events, expected, name) {
  check(Array.isArray(events) && events.length === expected.length, `${name}_count`);
  const actual = events.map((item) => ({ device_id: item.device_id, probe_id: item.probe_id,
    event_id: item.event_id, origin_sequence: item.origin_sequence }));
  check(JSON.stringify(actual) === JSON.stringify(expected), `${name}_identity`);
  check(events.every((item) => Number.isSafeInteger(item.server_sequence) && item.server_sequence > 0), `${name}_server_sequence`);
  const p3 = events.filter((item) => item.probe_id === 'synthetic-probe-c').map((item) => item.origin_sequence);
  const expectedP3 = expected.filter((item) => item.probe_id === 'synthetic-probe-c').map((item) => item.origin_sequence);
  check(JSON.stringify(p3) === JSON.stringify(expectedP3), `${name}_p3_continuity`);
}
export function assertReaderChangeLineage(page, expected, name) {
  equal(page?.contract, 'device.activity.v1', `${name}_contract`);
  equal(page?.schema_version, 1, `${name}_schema`);
  equal(page?.has_more, false, `${name}_complete`);
  check(typeof page?.next_cursor === 'string' && page.next_cursor.length > 0, `${name}_next_cursor`);
  const rows = page?.events;
  check(Array.isArray(rows) && rows.every((item, index) => Number.isSafeInteger(item.server_sequence)
    && (index === 0 || item.server_sequence > rows[index - 1].server_sequence)), `${name}_server_sequence`);
  const accepted = rows.filter((item) => item.kind === 'activity.event.accepted');
  const actual = accepted.map((item) => {
    const expectedEvent = expected.find((candidate) => candidate.event_id === item.payload?.event_id);
    return { device_id: item.payload?.device_id, probe_id: item.payload?.probe_id,
      event_id: item.payload?.event_id, origin_sequence: expectedEvent?.origin_sequence ?? null };
  });
  check(JSON.stringify(actual) === JSON.stringify(expected), `${name}_accepted_lineage`);
}
async function assertEmptyChangeTail(base, cursor, token, name) {
  const tail = await rawRequest(base, 'GET', `${ROOT}/changes?cursor=${encodeURIComponent(cursor)}`, token);
  equal(tail.status, 200, `${name}_tail_status`);
  equal(tail.body?.contract, 'device.activity.v1', `${name}_tail_contract`);
  equal(tail.body?.schema_version, 1, `${name}_tail_schema`);
  equal(tail.body?.has_more, false, `${name}_tail_complete`);
  check(Array.isArray(tail.body?.events) && tail.body.events.length === 0, `${name}_tail_empty`);
  equal(tail.body?.next_cursor, cursor, `${name}_tail_cursor`);
  assertNoFalseSleep(`${name}_tail`, { changes: tail });
}
function safeReport({ status, stage, check: failureCheck, close, cleanup, ledger = null }) {
  if (status !== 'passed_awaiting_human_acceptance') {
    return Object.freeze({ status: 'failed', stage, check: failureCheck, close, cleanup, evidence_boundaries: BOUNDARIES });
  }
  return Object.freeze({
    status,
    checkpoints: CHECKPOINTS,
    probes: Object.freeze(ledger.probes.map((probe) => Object.freeze({ ...probe }))),
    counts: Object.freeze({ ...ledger.counts }),
    status_codes: Object.freeze({ accepted: 200, duplicate: 200, forbidden: 403, revoked_replay: 401 }),
    error_codes: Object.freeze({ chat: 'chat_read_forbidden', scope: 'scope_denied', admin: 'admin_escalation_forbidden', identity: 'identity_binding_mismatch', revoked: 'revoked_replay' }),
    states: Object.freeze({ ...ledger.states }),
    close,
    cleanup,
    evidence_boundaries: BOUNDARIES,
  });
}

/** Pure report selection shared by the real finally path and failure-injection tests. */
export function finalizeMda1HumanGate({ stage, failure = null, close = 'confirmed', cleanup = 'confirmed', ledger = null }) {
  if (failure) return safeReport({ status: 'failed', stage, check: failure, close, cleanup });
  if (close !== 'confirmed') return safeReport({ status: 'failed', stage: 'complete', check: 'teardown_close', close, cleanup });
  if (cleanup !== 'confirmed') return safeReport({ status: 'failed', stage: 'complete', check: 'teardown_cleanup', close, cleanup });
  return safeReport({ status: 'passed_awaiting_human_acceptance', stage: 'complete', check: null, close, cleanup, ledger });
}
/** Each Core object is closed at most once; a first failure is permanent. */
export function createCloseAttemptLedger() {
  const attempted = new WeakSet(); let failed = false;
  return Object.freeze({
    async close(candidate) {
      if (!candidate || attempted.has(candidate)) return !failed;
      attempted.add(candidate);
      try { await candidate.close(); return true; }
      catch { failed = true; return false; }
    },
    status() { return failed ? 'failed' : 'confirmed'; },
  });
}
function assertNoFalseSleep(name, { summary = null, changes = null } = {}) {
  if (summary) {
    equal(summary.body?.semantics?.silence_is_unknown, true, `${name}_silence_unknown`);
    equal(summary.body?.semantics?.sleep_inference, 'not_supported', `${name}_sleep_not_supported`);
  }
  check((summary?.body?.devices ?? []).every((device) => ['active', 'locked', 'network_only', 'unknown'].includes(device.state)), `${name}_state_vocabulary`);
  check(!/quiet|asleep/i.test(JSON.stringify({ summary: summary?.body, changes: changes?.body })), `${name}_no_false_sleep`);
}

/** Runs only synthetic local probes. A passing result deliberately still awaits Lynx's acceptance. */
export async function runMda1HumanGate({ onCheckpoint } = {}) {
  let temp; let core; let stage = 'setup'; let cleanup = 'not_started'; let close = 'confirmed';
  let failure = null;
  const closeLedger = createCloseAttemptLedger();
  const ledger = {
    probes: ['probe_1', 'probe_2', 'probe_3'].map((probe) => ({ probe })),
    counts: { probes: 0, reader: 0, accepted_events: 0, duplicate_replays: 0, revoked_replays: 0, access_denials: 0 },
    states: {},
  };
  const closeCore = async (candidate) => {
    const ok = await closeLedger.close(candidate);
    close = closeLedger.status();
    return ok;
  };
  try {
    createOwnedTemporaryDirectory({ onCreated(record) { temp = record; } });
    const databasePath = path.join(temp.canonical, 'core.sqlite');
    const ownerSecret = randomBytes(32).toString('base64url');
    let now = 1_760_000_000_000;
    const start = async (runtimeId) => {
      core = createICoreServer({ databasePath, activityAdminSecret: ownerSecret, activityRuntimeId: runtimeId,
        activityRuntimeLeaseMs: 100, activityRetentionIntervalMs: 2_147_483_647, clock: () => now });
      const address = await core.listen({ host: '127.0.0.1', port: 0 });
      return `http://127.0.0.1:${address.port}`;
    };
    const checkpoint = (name) => { onCheckpoint?.({ checkpoint: name }); };
    let base = await start('synthetic-runtime-a');
    const ownerPost = (route, value) => rawRequest(base, 'POST', route, ownerSecret, bodyBytes(value));
    const readerPair = await ownerPost(`${ROOT}/readers/pair`, {
      installation_id: 'synthetic-reader', display_name: 'synthetic-reader', capabilities: [],
    });
    equal(readerPair.status, 200, 'reader_pair_status');
    ledger.counts.reader += 1;
    check(Array.isArray(readerPair.body?.scopes) && readerPair.body.scopes.length === 1 && readerPair.body.scopes[0] === 'activity.read_summary', 'reader_scope');
    const specs = [
      ['synthetic-device-a', 'synthetic-probe-a', 'windows_wts', 'continuous', 'session.unlocked'],
      ['synthetic-device-b', 'synthetic-probe-b', 'android_screen_state', 'continuous', 'session.locked'],
      ['synthetic-device-c', 'synthetic-probe-c', 'android_tasker', 'discrete_best_effort', 'network.present'],
    ];
    const probes = [];
    for (const [index, [deviceId, probeId, source, coverageMode, kind]] of specs.entries()) {
      const paired = await ownerPost(`${ROOT}/probes/pair`, {
        device_id: deviceId, probe_id: probeId, display_name: probeId, capabilities: ['activity.admin', 'chat.read'],
        source, coverage_mode: coverageMode, expected_report_interval_ms: coverageMode === 'continuous' ? 30_000 : 300_000,
        expiry_slo_ms: 300_000, allowed_kinds: [kind],
      });
      equal(paired.status, 200, 'probe_pair_status');
      check(Array.isArray(paired.body?.scopes) && paired.body.scopes.length === 1 && paired.body.scopes[0] === 'activity.write', 'probe_scope');
      probes.push({ deviceId, probeId, source, coverageMode, kind, token: paired.body.probe_token, prefix: paired.body.event_id_prefix });
      ledger.counts.probes += 1; ledger.probes[index].pair = paired.status;
    }
    const initialLineage = probes.map((probe) => ({ device_id: probe.deviceId, probe_id: probe.probeId,
      event_id: `${probe.prefix}.1`, origin_sequence: 1 }));
    stage = 'paired'; checkpoint('paired');
    const bytes = new Map();
    for (const probe of probes) {
      const raw = bodyBytes({ events: [event({ ...probe, sequence: 1, now })] }); bytes.set(probe.probeId, raw);
      const accepted = await rawRequest(base, 'POST', `${ROOT}/events`, probe.token, raw);
      equal(accepted.status, 200, 'event_accept_status'); equal(accepted.body?.results?.[0]?.status, 'accepted', 'event_accept_result');
      ledger.counts.accepted_events += 1; ledger.probes[probes.indexOf(probe)].write = accepted.body.results[0].status;
      const duplicate = await rawRequest(base, 'POST', `${ROOT}/events`, probe.token, raw);
      equal(duplicate.status, 200, 'event_duplicate_status'); equal(duplicate.body?.results?.[0]?.status, 'duplicate', 'event_duplicate_result');
      ledger.counts.duplicate_replays += 1; ledger.probes[probes.indexOf(probe)].duplicate = duplicate.body.results[0].status;
    }
    const summary = await rawRequest(base, 'GET', `${ROOT}/summary`, readerPair.body.reader_token);
    equal(summary.status, 200, 'summary_status');
    equal(summary.body?.semantics?.silence_is_unknown, true, 'silence_unknown');
    equal(summary.body?.semantics?.sleep_inference, 'not_supported', 'sleep_not_supported');
    check(JSON.stringify(summary.body?.devices?.map((item) => [item.device_id, item.sources?.[0]?.source, item.state]).sort()) === JSON.stringify([
      ['synthetic-device-a', 'windows_wts', 'active'], ['synthetic-device-b', 'android_screen_state', 'locked'], ['synthetic-device-c', 'android_tasker', 'network_only'],
    ]), 'initial_summary_exact');
    ledger.probes[0].initial_state = 'active'; ledger.probes[1].initial_state = 'locked'; ledger.probes[2].initial_state = 'network_only';
    ledger.states.initial = 'active_locked_network_only';
    const initialChanges = await rawRequest(base, 'GET', `${ROOT}/changes?cursor=${encodeURIComponent(readerPair.body.initial_cursor)}`, readerPair.body.reader_token);
    equal(initialChanges.status, 200, 'initial_changes_status');
    assertReaderChangeLineage(initialChanges.body, initialLineage, 'initial_changes');
    await assertEmptyChangeTail(base, initialChanges.body.next_cursor, readerPair.body.reader_token, 'initial');
    const initialExport = await rawRequest(base, 'GET', `${ROOT}/admin/export`, ownerSecret);
    equal(initialExport.status, 200, 'initial_export_status'); equal(initialExport.body?.contract, 'device.activity.v1', 'initial_export_contract'); assertAcceptedLineage(initialExport.body?.events, initialLineage, 'initial_export');
    assertNoFalseSleep('initial', { summary, changes: initialChanges });
    stage = 'accepted_and_replayed'; checkpoint('accepted_and_replayed');
    for (const probe of probes) {
      errorCode(await rawRequest(base, 'GET', '/v1/core/changes', probe.token), 403, 'chat_read_forbidden', 'chat_denied');
      ledger.counts.access_denials += 1; ledger.probes[probes.indexOf(probe)].chat = 403;
      errorCode(await rawRequest(base, 'GET', `${ROOT}/summary`, probe.token), 403, 'scope_denied', 'summary_denied');
      ledger.counts.access_denials += 1;
      errorCode(await rawRequest(base, 'GET', `${ROOT}/admin/export`, probe.token), 403, 'admin_escalation_forbidden', 'admin_denied');
      ledger.counts.access_denials += 1;
    }
    errorCode(await rawRequest(base, 'POST', `${ROOT}/events`, readerPair.body.reader_token, bytes.get(probes[0].probeId)), 403, 'scope_denied', 'reader_write_denied');
    ledger.counts.access_denials += 1;
    errorCode(await rawRequest(base, 'GET', `${ROOT}/admin/export`, readerPair.body.reader_token), 403, 'admin_escalation_forbidden', 'reader_admin_denied');
    ledger.counts.access_denials += 1;
    errorCode(await rawRequest(base, 'POST', `${ROOT}/events`, probes[0].token, bytes.get(probes[1].probeId)), 403, 'identity_binding_mismatch', 'cross_identity_denied');
    ledger.counts.access_denials += 1;
    stage = 'least_privilege_checked'; checkpoint('least_privilege_checked');
    for (const probe of probes.slice(0, 2)) {
      const revoked = await ownerPost(`${ROOT}/probes/${probe.probeId}/revoke`, {}); equal(revoked.status, 200, 'revoke_status');
      ledger.probes[probes.indexOf(probe)].revoke = revoked.status;
      errorCode(await rawRequest(base, 'POST', `${ROOT}/events`, probe.token, bytes.get(probe.probeId)), 401, 'revoked_replay', 'revoked_replay');
      ledger.counts.revoked_replays += 1; ledger.probes[probes.indexOf(probe)].revoked_replay = 401;
    }
    const revokedSummary = await rawRequest(base, 'GET', `${ROOT}/summary`, readerPair.body.reader_token);
    equal(revokedSummary.status, 200, 'revoked_summary_status');
    for (const deviceId of ['synthetic-device-a', 'synthetic-device-b']) {
      const device = revokedSummary.body?.devices?.find((item) => item.device_id === deviceId);
      check(device, 'revoked_summary_device'); equal(device.state, 'unknown', 'revoked_summary_unknown'); equal(device.sources?.[0]?.credential_state, 'revoked', 'revoked_summary_credential');
    }
    assertNoFalseSleep('revoked', { summary: revokedSummary });
    stage = 'revoked_before_restart'; checkpoint('revoked_before_restart');
    if (!await closeCore(core)) throw new GateCheck('teardown_close');
    core = null; now += 101;
    base = await start('synthetic-runtime-b');
    const restartSummary = await rawRequest(base, 'GET', `${ROOT}/summary`, readerPair.body.reader_token);
    equal(restartSummary.status, 200, 'restart_summary_status');
    const p3Restart = restartSummary.body?.devices?.find((item) => item.device_id === 'synthetic-device-c');
    equal(p3Restart?.state, 'unknown', 'restart_gap_state'); equal(p3Restart?.sources?.[0]?.coverage_status, 'core_restart_gap', 'restart_gap_coverage'); equal(p3Restart?.sources?.[0]?.clock_health, 'unknown', 'restart_gap_clock'); equal(p3Restart?.sources?.[0]?.status_reason, 'reachability_only', 'restart_network_reason');
    equal(p3Restart?.sources?.[0]?.freshness?.fresh, true, 'restart_gap_freshness');
    Object.assign(ledger.probes[2], { restart_state: p3Restart.state, restart_coverage_status: p3Restart.sources[0].coverage_status, restart_clock_health: p3Restart.sources[0].clock_health, restart_status_reason: p3Restart.sources[0].status_reason, restart_freshness: p3Restart.sources[0].freshness.fresh, restart_interpretation: 'fresh_not_concrete' });
    ledger.states.restart = 'unknown_core_restart_gap_clock_unknown_fresh_not_concrete'; assertNoFalseSleep('restart', { summary: restartSummary });
    for (const deviceId of ['synthetic-device-a', 'synthetic-device-b']) {
      const device = restartSummary.body?.devices?.find((item) => item.device_id === deviceId);
      check(device, 'restart_revoked_device'); equal(device.sources?.[0]?.credential_state, 'revoked', 'restart_revoked_credential');
    }
    const p3 = probes[2];
    const finalLineage = [...initialLineage, { device_id: p3.deviceId, probe_id: p3.probeId,
      event_id: `${p3.prefix}.2`, origin_sequence: 2 }];
    const preservedChanges = await rawRequest(base, 'GET', `${ROOT}/changes?cursor=${encodeURIComponent(readerPair.body.initial_cursor)}`, readerPair.body.reader_token);
    equal(preservedChanges.status, 200, 'restart_changes_status'); assertReaderChangeLineage(preservedChanges.body, initialLineage, 'restart_changes');
    await assertEmptyChangeTail(base, preservedChanges.body.next_cursor, readerPair.body.reader_token, 'restart');
    assertNoFalseSleep('restart_changes', { changes: preservedChanges });
    const preserved = await rawRequest(base, 'GET', `${ROOT}/admin/export`, ownerSecret);
    equal(preserved.status, 200, 'preserved_export_status'); equal(preserved.body?.contract, 'device.activity.v1', 'preserved_export_contract'); assertAcceptedLineage(preserved.body?.events, initialLineage, 'preserved_export');
    const afterRestartDuplicate = await rawRequest(base, 'POST', `${ROOT}/events`, p3.token, bytes.get(p3.probeId));
    equal(afterRestartDuplicate.status, 200, 'restart_duplicate_status'); equal(afterRestartDuplicate.body?.results?.[0]?.status, 'duplicate', 'restart_duplicate_result');
    ledger.counts.duplicate_replays += 1;
    const duplicateSummary = await rawRequest(base, 'GET', `${ROOT}/summary`, readerPair.body.reader_token);
    const p3Duplicate = duplicateSummary.body?.devices?.find((item) => item.device_id === 'synthetic-device-c');
    equal(p3Duplicate?.state, 'unknown', 'duplicate_keeps_gap'); equal(p3Duplicate?.sources?.[0]?.coverage_status, 'core_restart_gap', 'duplicate_keeps_coverage_gap'); equal(p3Duplicate?.sources?.[0]?.clock_health, 'unknown', 'duplicate_keeps_clock_gap');
    equal(p3Duplicate?.sources?.[0]?.freshness?.fresh, true, 'duplicate_gap_freshness'); assertNoFalseSleep('duplicate', { summary: duplicateSummary });
    stage = 'restart_gap_checked'; checkpoint('restart_gap_checked');
    now += 1;
    const fresh = bodyBytes({ events: [event({ ...p3, sequence: 2, now })] });
    const freshResult = await rawRequest(base, 'POST', `${ROOT}/events`, p3.token, fresh);
    equal(freshResult.status, 200, 'fresh_status'); equal(freshResult.body?.results?.[0]?.status, 'accepted', 'fresh_result');
    ledger.counts.accepted_events += 1;
    const restored = await rawRequest(base, 'GET', `${ROOT}/summary`, readerPair.body.reader_token);
    const p3Restored = restored.body?.devices?.find((item) => item.device_id === 'synthetic-device-c');
    equal(p3Restored?.state, 'network_only', 'restored_network_only'); equal(p3Restored?.sources?.[0]?.clock_health, 'healthy', 'restored_clock'); equal(p3Restored?.sources?.[0]?.coverage_status, 'covered', 'restored_coverage'); equal(p3Restored?.sources?.[0]?.freshness?.fresh, true, 'restored_fresh');
    ledger.probes[2].fresh_restore = 'network_only'; ledger.states.restored = 'network_only_fresh'; assertNoFalseSleep('restored', { summary: restored });
    const finalRevoke = await ownerPost(`${ROOT}/probes/${p3.probeId}/revoke`, {}); equal(finalRevoke.status, 200, 'final_revoke_status');
    ledger.probes[2].revoke = finalRevoke.status;
    errorCode(await rawRequest(base, 'POST', `${ROOT}/events`, p3.token, bytes.get(p3.probeId)), 401, 'revoked_replay', 'final_revoked_replay');
    ledger.counts.revoked_replays += 1; ledger.probes[2].revoked_replay = 401;
    const p3RevokedSummary = await rawRequest(base, 'GET', `${ROOT}/summary`, readerPair.body.reader_token);
    const p3Revoked = p3RevokedSummary.body?.devices?.find((item) => item.device_id === 'synthetic-device-c');
    equal(p3Revoked?.state, 'unknown', 'final_revoked_unknown'); equal(p3Revoked?.sources?.[0]?.credential_state, 'revoked', 'final_revoked_credential');
    assertNoFalseSleep('final_revoked', { summary: p3RevokedSummary });
    stage = 'restored_then_revoked'; checkpoint('restored_then_revoked');
    const changes = await rawRequest(base, 'GET', `${ROOT}/changes?cursor=${encodeURIComponent(readerPair.body.initial_cursor)}`, readerPair.body.reader_token);
    equal(changes.status, 200, 'changes_status'); assertReaderChangeLineage(changes.body, finalLineage, 'final_changes');
    await assertEmptyChangeTail(base, changes.body.next_cursor, readerPair.body.reader_token, 'final');
    const finalSummary = await rawRequest(base, 'GET', `${ROOT}/summary`, readerPair.body.reader_token);
    equal(finalSummary.status, 200, 'final_summary_status');
    assertNoFalseSleep('final', { summary: finalSummary, changes });
    const finalExport = await rawRequest(base, 'GET', `${ROOT}/admin/export`, ownerSecret);
    equal(finalExport.status, 200, 'final_export_status'); equal(finalExport.body?.contract, 'device.activity.v1', 'final_export_contract'); assertAcceptedLineage(finalExport.body?.events, finalLineage, 'final_export');
    stage = 'reader_evidence_checked'; checkpoint('reader_evidence_checked');
    stage = 'complete';
  } catch (error) {
    failure = error instanceof GateCheck ? error.check : 'execution_failed';
  } finally {
    await closeCore(core);
    cleanup = removeOwnTempDirectory(temp) ? 'confirmed' : 'failed';
  }
  return finalizeMda1HumanGate({ stage, failure, close, cleanup, ledger });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const allowed = process.argv.length === 3 && process.argv[2] === '--human-gate';
  const report = allowed ? await runMda1HumanGate() : Object.freeze({ status: 'rejected', stage: 'cli', check: 'human_gate_flag_required', close: 'not_started', cleanup: 'not_started' });
  process.stdout.write(`${JSON.stringify(report)}\n`);
  if (report.status !== 'passed_awaiting_human_acceptance') process.exitCode = 1;
}
