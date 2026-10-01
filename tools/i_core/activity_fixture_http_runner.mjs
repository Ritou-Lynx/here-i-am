import { randomBytes, createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { request as httpRequest } from 'node:http';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { loadFixtureSet, materializeEvent, materializeAndQueue } from './activity_fixture_contract.mjs';
import { createICoreServer } from './i_core_server.mjs';
import { ACTIVITY_RAW_RETENTION_MS, ACTIVITY_MAX_PAYLOAD_BYTES, ACTIVITY_FUTURE_SKEW_MS } from './activity_control_plane.mjs';
import { installStaleRuntimeEpoch } from './activity_fixture_http_runner.test_support.mjs';

export const DEFAULT_FIXTURE_DIRECTORY = fileURLToPath(new URL('../../docs/development/activity/mda0/fixtures/', import.meta.url));
const ROOT = '/v1/core/activity';
const DEFAULT_TIME = 1760000000000;
const BOUNDARIES = Object.freeze([
  'person_expectations_check_http_non_inference_only',
  'lookup_order_expectations_check_http_non_disclosure_and_non_mutation_only',
  'epoch_and_fence_labels_are_relative_test_setup_not_authority_takeover',
  'no_android_or_human_gate',
]);

// Independent executor allowlist, not imported from the static validator or
// inferred from the candidate fixtures. A field is executable only in its
// declared case/step, including nested HTTP and coverage members.
const ACCEPTED_SHAPE = 'http.result_status http.status outcome';
const REJECTION_SHAPE = 'acceptance_mutated http.error_code http.status outcome';
const CLOCK_SHAPE = 'clock_health concrete_projection_advanced forbidden_states http.result_status http.status outcome projection_state';
const COVERAGE_SHAPE = 'sequence_coverage.contiguous_through sequence_coverage.highest_seen sequence_coverage.missing';
const RUNNER_EXPECTED_SHAPES = new Map([
  ['valid_event', [`device_projection_state ${ACCEPTED_SHAPE} person_projection_state receipt_time_owner`]],
  ['duplicate_same_payload', [ACCEPTED_SHAPE, `${ACCEPTED_SHAPE} receipt_ref`]],
  ['heart_rate_quality_without_inference', [`allowed_payload_fields forbidden_states ${ACCEPTED_SHAPE} person_projection_state`]],
  ['duplicate_different_payload', [ACCEPTED_SHAPE, REJECTION_SHAPE]],
  ['noncanonical_event_id', [REJECTION_SHAPE]],
  ['wrong_event_id_prefix', [REJECTION_SHAPE]],
  ['event_id_sequence_mismatch', [REJECTION_SHAPE]],
  ['credential_rotation_preserves_lineage', ['event_id_prefix_ref http.status outcome', ACCEPTED_SHAPE]],
  ['deleted_lineage_outbox_not_rebound', [null, 'http.status outcome', 'event_id_prefix_must_differ_from http.status outcome',
    'action local_outbox_discarded must_not_submit_with_replacement_prefix old_outbox_bytes_rejected outcome']],
  ['retained_out_retry', [ACCEPTED_SHAPE, null, `${REJECTION_SHAPE} receipt_must_not_be_guessed`]],
  ['illegal_kind', [REJECTION_SHAPE]],
  ['missing_required_field', [`${REJECTION_SHAPE} http.details.field`]],
  ['unknown_field', [`${REJECTION_SHAPE} http.details.field`]],
  ['future_clock', [CLOCK_SHAPE]],
  ['clock_regression', [ACCEPTED_SHAPE, CLOCK_SHAPE]],
  ['sequence_gap_then_out_of_order_fill', [null, null, null,
    `device_projection_state ${ACCEPTED_SHAPE} ${COVERAGE_SHAPE}`,
    `concrete_projection_advanced ${ACCEPTED_SHAPE} projection_state ${COVERAGE_SHAPE} sequence_diagnostics`,
    `clock_health concrete_projection_restored device_projection_state ${ACCEPTED_SHAPE} projection_recomputed_through_origin_sequence ${COVERAGE_SHAPE} sequence_diagnostics`]],
  ['ttl_expired', [REJECTION_SHAPE]],
  ['no_coverage_silence', ['forbidden_states outcome projection_state']],
  ['wrong_scope', [REJECTION_SHAPE]],
  ['write_token_chat_read_denied', ['http.error_code http.status outcome private_data_returned resource_lookup_performed']],
  ['probe_admin_escalation', [`${REJECTION_SHAPE} server_assigned_scopes_unchanged`]],
  ['revoked_replay', [ACCEPTED_SHAPE, 'http.status outcome', `${REJECTION_SHAPE} idempotency_lookup_after_revocation`]],
  ['cross_device_impersonation', [REJECTION_SHAPE]],
  ['oversized_payload', [REJECTION_SHAPE]],
  ['batch_atomic_rejection', ['accepted_items http.error_code http.status outcome rejected_item_reason']],
  ['stale_epoch_or_fencing', [null, REJECTION_SHAPE]],
]);
const TOP_LEVEL_EXPECTATIONS = new Set(['no_coverage_silence', 'wrong_scope', 'write_token_chat_read_denied', 'probe_admin_escalation']);
const EXPECTED_LEAF_TYPES = new Map([
  ...['outcome', 'device_projection_state', 'person_projection_state', 'receipt_time_owner', 'receipt_ref',
    'clock_health', 'projection_state', 'event_id_prefix_ref', 'event_id_prefix_must_differ_from', 'action',
    'rejected_item_reason', 'http.result_status', 'http.error_code', 'http.details.field'].map((name) => [name, 'string']),
  ...['acceptance_mutated', 'concrete_projection_advanced', 'concrete_projection_restored',
    'must_not_submit_with_replacement_prefix', 'old_outbox_bytes_rejected', 'local_outbox_discarded',
    'receipt_must_not_be_guessed', 'idempotency_lookup_after_revocation', 'resource_lookup_performed',
    'private_data_returned', 'server_assigned_scopes_unchanged'].map((name) => [name, 'boolean']),
  ...['projection_recomputed_through_origin_sequence', 'accepted_items', 'http.status',
    'sequence_coverage.highest_seen', 'sequence_coverage.contiguous_through'].map((name) => [name, 'counter']),
  ...['allowed_payload_fields', 'forbidden_states', 'sequence_diagnostics'].map((name) => [name, 'string_array']),
  ['sequence_coverage.missing', 'counter_array'],
]);
const EXPECTED_CONTAINERS = new Set(['http', 'http.details', 'sequence_coverage']);

function checkExpectedLeaf(value, type) {
  const validScalar = (item, kind) => kind === 'string'
    ? typeof item === 'string' && item.length > 0
    : kind === 'boolean' ? typeof item === 'boolean' : kind === 'counter' && Number.isSafeInteger(item) && item >= 0;
  if (type === 'string_array' || type === 'counter_array') {
    check(Array.isArray(value), 'runner_expected_shape');
    check(value.every((item) => validScalar(item, type === 'string_array' ? 'string' : 'counter'))
      && new Set(value).size === value.length, 'runner_expected_shape');
  } else check(validScalar(value, type), 'runner_expected_shape');
}

function expectedLeafShape(value, prefix = '') {
  check(value && typeof value === 'object' && !Array.isArray(value), 'runner_expected_shape');
  return Object.entries(value).flatMap(([key, child]) => {
    check(/^[a-z_]+$/.test(key), 'runner_expected_shape');
    const name = prefix ? `${prefix}.${key}` : key;
    const type = EXPECTED_LEAF_TYPES.get(name);
    if (type) {
      checkExpectedLeaf(child, type);
      return [name];
    }
    check(EXPECTED_CONTAINERS.has(name), 'runner_expected_shape');
    return expectedLeafShape(child, name);
  });
}

/** Pure testable guard; never starts a server, resolves captures, or reads Core. */
export function assertRunnerCaseExpectedShape(caseDoc) {
  const declared = RUNNER_EXPECTED_SHAPES.get(caseDoc?.name);
  check(declared, 'runner_expected_shape');
  const topLevel = TOP_LEVEL_EXPECTATIONS.has(caseDoc.name);
  check(topLevel || !Object.hasOwn(caseDoc, 'expected'), 'runner_expected_shape');
  check(!topLevel || !Object.hasOwn(caseDoc, 'steps'), 'runner_expected_shape');
  const containers = topLevel ? [caseDoc] : caseDoc.steps;
  check(Array.isArray(containers) && containers.length === declared.length, 'runner_expected_shape');
  for (let index = 0; index < declared.length; index += 1) {
    const slot = containers[index];
    check(slot && typeof slot === 'object' && !Array.isArray(slot), 'runner_expected_shape');
    if (declared[index] === null) check(!Object.hasOwn(slot, 'expected'), 'runner_expected_shape');
    else {
      check(Object.hasOwn(slot, 'expected'), 'runner_expected_shape');
      same(expectedLeafShape(slot.expected).sort().join(' '), declared[index].split(' ').sort().join(' '), 'runner_expected_shape');
    }
  }
}

// Never attach actual/expected values, causes, URLs, fixture paths, or stacks.
class CheckFailure extends Error {
  constructor(check) { super('fixture_http_check_failed'); this.check = check; }
}
function check(value, code) { if (!value) throw new CheckFailure(code); }
function same(actual, expected, code) { check(isDeepStrictEqual(actual, expected), code); }
function subset(actual, expected, code) {
  for (const [key, value] of Object.entries(expected)) same(actual?.[key], value, code);
}
function keys(value, allowed) {
  check(value && typeof value === 'object' && !Array.isArray(value), 'field_shape');
  check(Object.keys(value).every((key) => allowed.includes(key)), 'unused_field');
}
function countLeaves(value) {
  if (!value || typeof value !== 'object' || !Object.keys(value).length) return 1;
  return Object.values(value).reduce((total, child) => total + countLeaves(child), 0);
}

function consumptionLedger(value) {
  const pending = new Set();
  function visit(item, at, action) {
    if (!item || typeof item !== 'object' || !Object.keys(item).length) { action(at); return; }
    for (const [key, child] of Object.entries(item)) visit(child, `${at}/${key}`, action);
  }
  visit(value, '', (at) => pending.add(at));
  const total = pending.size;
  return {
    consume(at) {
      const names = [...pending].filter((name) => name === at || name.startsWith(`${at}/`));
      for (const name of names) pending.delete(name);
    },
    finish() { check(pending.size === 0, 'unconsumed_fixture_field'); return total; },
  };
}

// Static validator is always first. This second gate narrows fields which its
// broad expected-value grammar accepts but which this executor cannot consume.
function preflight(set) {
  // Pin the already-validated declarative metadata version. It is not executable
  // input and cannot silently acquire extra instructions or unused nested keys.
  same(createHash('sha256').update(JSON.stringify(set.manifest)).digest('hex'),
    '2c2b7cba5c350715f981656f8b9199c0a356bb8cc900d78fb1aebcc705af1414', 'manifest_metadata_version');
  same(readdirSync(set.directory).filter((name) => /\.json$/i.test(name)).sort(),
    ['manifest.json', ...set.manifest.files.map((entry) => entry.file)].sort(), 'extra_fixture_file');
  const defaults = set.manifest.execution_defaults;
  same(defaults, {
    initial_core_time_rule: 'case.core.received_at_ms or maximum signal_at_ms in the first submit step',
    pairing_route: `${ROOT}/probes/pair`, ingest_route: `${ROOT}/events`,
    protocol_header: 'X-Core-Protocol: 0.1', fixture_values_are_synthetic: true,
  }, 'execution_defaults');
  check(set.manifest.cases_are_isolated === true, 'case_isolation');
  for (const doc of set.documents.values()) {
    same([doc.contract, doc.schema_version, doc.fixture_format_version, doc.proposal_revision],
      ['device.activity.v1', 1, 2, 5], 'file_version');
    for (const c of doc.cases) {
      assertRunnerCaseExpectedShape(c);
      const coreFields = {
        valid_event: ['epoch', 'fencing_token', 'received_at_ms'],
        heart_rate_quality_without_inference: ['epoch', 'fencing_token', 'received_at_ms'],
        future_clock: ['received_at_ms', 'maximum_future_skew_ms'],
        sequence_gap_then_out_of_order_fill: ['retained_origin_floor'],
        ttl_expired: ['received_at_ms'],
        stale_epoch_or_fencing: ['pairing_epoch', 'active_epoch', 'active_fencing_token'],
      };
      same(Object.keys(c.core || {}).sort(), [...(coreFields[c.name] || [])].sort(), 'unused_core_field');
      check(!c.limits || c.name === 'oversized_payload', 'unused_limit');
      if (c.execution) keys(c, ['name', 'execution', 'projection_input', 'expected']);
      if (c.request) keys(c, ['name', 'setup', 'request', 'expected']);
      if (c.core) {
        if (c.core.maximum_future_skew_ms !== undefined) same(c.core.maximum_future_skew_ms, ACTIVITY_FUTURE_SKEW_MS, 'future_limit');
        if (c.core.retained_origin_floor !== undefined) same(c.core.retained_origin_floor, 0, 'initial_floor');
        if (c.core.epoch !== undefined) same([c.core.epoch, c.core.fencing_token], ['epoch-synthetic-9', 18], 'authority_labels');
      }
      if (c.execution) keys(c.projection_input.coverage, ['mode']);
      for (const step of c.steps || []) {
        check(!step.expected || !('details' in step.expected), 'unused_expected_details');
        if (step.expected?.sequence_coverage) same(Object.keys(step.expected.sequence_coverage).sort(), ['contiguous_through', 'highest_seen', 'missing'], 'sequence_coverage_fields');
        if (step.expected?.http?.details) keys(step.expected.http.details, ['field']);
        if (step.payload_materialization) {
          same([step.payload_materialization.mode, step.payload_materialization.field,
            step.payload_materialization.target_encoded_payload_bytes, c.limits?.maximum_payload_bytes],
          ['append_synthetic_padding', 'padding', ACTIVITY_MAX_PAYLOAD_BYTES + 1, ACTIVITY_MAX_PAYLOAD_BYTES], 'payload_limit');
        }
      }
    }
  }
}

function initialTime(c) {
  if (c.core?.received_at_ms !== undefined) return c.core.received_at_ms;
  const first = c.steps?.find((step) => step.operation === 'submit_events');
  const referenced = first?.materialized_event_ref
    ? c.steps.find((step) => step.capture_materialized_event_as === first.materialized_event_ref) : first;
  const templates = referenced?.event_templates || [referenced?.event_template || c.outbox_event_template];
  const times = templates.map((event) => event?.signal_at_ms).filter(Number.isSafeInteger);
  return times.length ? Math.max(...times) : DEFAULT_TIME;
}

async function executeCase(c, onLifecycle) {
  const ledger = consumptionLedger(c);
  ledger.consume('/name');
  const directory = mkdtempSync(path.join(tmpdir(), `mda1-http-case-${process.pid}-`));
  const databasePath = path.join(directory, 'core.sqlite');
  const owner = randomBytes(32).toString('base64url');
  let now = initialTime(c);
  let core; let base; let reader; let stale = false;
  let requests = 0; let expectations = 0; let steps = 0; let submissions = 0; let retries = 0;
  const deliveredBuffers = new Set();
  let wireChecks = 0; let pendingWire = null;
  let fields = 0; let stepIndex = -1;
  const used = (...names) => names.forEach((name) => ledger.consume(`/steps/${stepIndex}/${name}`));
  if (c.core?.received_at_ms !== undefined) ledger.consume('/core/received_at_ms');
  // Fixed policy and symbolic labels were checked before any HTTP request.
  for (const name of ['epoch', 'fencing_token', 'maximum_future_skew_ms', 'retained_origin_floor']) {
    if (c.core?.[name] !== undefined) ledger.consume(`/core/${name}`);
  }
  const pairs = new Map(); const usedCaptures = new Set();
  const captures = new class extends Map {
    get(key) { usedCaptures.add(key); return super.get(key); }
  }();
  const materialized = new Map();
  const outboxBytes = new Map();
  const receipts = new Map(); const consumedReceipts = new Set(); const consumedEvents = new Set();
  let replacement; let firstCursor; let failure = null;
  const start = async () => {
    core = createICoreServer({ databasePath, activityAdminSecret: owner,
      activityRetentionIntervalMs: 2_147_483_647, clock: () => now });
    // Observe actual loopback bytes without persisting or exposing them. This
    // listener cannot change the request, response, or Core's assertions.
    core.server.prependListener('request', (incoming) => {
      const observation = pendingWire;
      const chunks = [];
      incoming.on('data', (chunk) => chunks.push(chunk));
      incoming.once('end', () => {
        if (observation) {
          observation.ok = incoming.headers['x-core-protocol'] === '0.1'
            && incoming.socket.remoteAddress === '127.0.0.1'
            && Buffer.concat(chunks).equals(observation.bytes);
          observation.ended = true;
        }
      });
    });
    const address = await core.listen({ host: '127.0.0.1', port: 0 });
    base = `http://127.0.0.1:${address.port}`;
  };
  const stopListener = async () => {
    core.server.closeIdleConnections();
    await new Promise((resolve, reject) => core.server.close((error) => error ? reject(error) : resolve()));
  };
  const resumeListener = async () => {
    await new Promise((resolve, reject) => {
      const onError = (error) => reject(error);
      core.server.once('error', onError);
      core.server.listen(0, '127.0.0.1', () => { core.server.off('error', onError); resolve(); });
    });
    base = `http://127.0.0.1:${core.server.address().port}`;
  };
  const advanceClock = async (next) => {
    check(Number.isSafeInteger(next) && next >= now, 'test_clock_monotonic');
    await stopListener();
    now = next; // injected test clock only; no public clock-setting route exists
    await resumeListener();
  };
  const request = async (method, route, token, body, bytes) => {
    // Caller-provided hooks receive counters only, never transport material.
    onLifecycle?.({ phase: 'request', case: c.name, request: requests + 1 });
    const requestBytes = bytes || (body !== undefined ? Buffer.from(JSON.stringify(body)) : Buffer.alloc(0));
    const observation = { bytes: requestBytes, ended: false, ok: false };
    pendingWire = observation;
    requests += 1;
    // No shared fetch pool: after stopped-clock setup an OS port can be reused,
    // and stale pooled connections would make this fixture nondeterministic.
    const result = await new Promise((resolve, reject) => {
      const outgoing = httpRequest(`${base}${route}`, { method, agent: false,
        headers: { 'X-Core-Protocol': '0.1', Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json', 'Content-Length': requestBytes.length },
      }, (response) => {
        const chunks = []; let length = 0;
        response.on('data', (chunk) => {
          length += chunk.length;
          if (length > 1024 * 1024) outgoing.destroy(new CheckFailure('http_response_limit'));
          else chunks.push(chunk);
        });
        response.on('error', reject);
        response.once('end', () => {
          try { resolve({ status: response.statusCode, body: JSON.parse(Buffer.concat(chunks).toString('utf8')) }); }
          catch { reject(new CheckFailure('http_response_json')); }
        });
      });
      outgoing.on('error', reject);
      outgoing.setTimeout(30000, () => outgoing.destroy(new CheckFailure('http_timeout')));
      outgoing.end(requestBytes);
    });
    check(observation.ended && observation.ok, 'literal_loopback_wire'); wireChecks += 1;
    if (bytes) {
      if (deliveredBuffers.has(bytes)) retries += 1;
      deliveredBuffers.add(bytes);
    }
    pendingWire = null;
    return result;
  };
  const success = (r) => { same(r.status, 200, 'setup_http_status'); return r.body; };
  const read = async () => success(await request('GET', `${ROOT}/summary`, reader.reader_token));
  const feed = async (cursor = reader.initial_cursor) => request('GET', `${ROOT}/changes?cursor=${encodeURIComponent(cursor)}`, reader.reader_token);
  const view = async () => ({ summary: await read(), feed: success(await feed()) });
  const pair = async (spec) => {
    const { ref, ...body } = spec;
    const value = success(await request('POST', `${ROOT}/probes/pair`, owner, body));
    same(value.scopes, ['activity.write'], 'probe_scopes');
    same([value.device_id, value.probe_id, value.credential_generation], [spec.device_id, spec.probe_id, 1], 'pair_binding');
    check(/^[A-Za-z0-9_-]{22,64}$/.test(value.event_id_prefix), 'pair_prefix_grammar');
    check(typeof value.probe_token === 'string' && value.probe_token.length > 16, 'pair_token');
    pairs.set(ref, value); return value;
  };
  const make = (step) => {
    if (step.wire_event_id_override?.mode === 'different_pairing_prefix_with_canonical_sequence') {
      check(captures.get(step.wire_event_id_override.prefix_ref) !== captures.get('setup.capture.event_id_prefix'), 'distinct_prefix_fixture');
    }
    const templates = step.event_templates || [step.event_template || c.outbox_event_template];
    const events = templates.map((template) => materializeEvent(template, step.event_id_recipe || c.event_id_recipe,
      captures, step.wire_event_id_override));
    if (step.payload_materialization) {
      const m = step.payload_materialization;
      events[0].payload[m.field] = '';
      const needed = m.target_encoded_payload_bytes - Buffer.byteLength(JSON.stringify(events[0].payload));
      check(needed > 0, 'padding_length'); events[0].payload[m.field] = 'x'.repeat(needed);
      same(Buffer.byteLength(JSON.stringify(events[0].payload)), m.target_encoded_payload_bytes, 'payload_bytes');
    }
    const outbox = events.reduce(materializeAndQueue, []);
    // Build envelope from the materializer's literal UTF-8 bytes, never a helper
    // event or reconstructed event ID. Retries reuse this same Buffer instance.
    const bytes = Buffer.concat([Buffer.from('{"events":['),
      ...outbox.flatMap((item, index) => index ? [Buffer.from(','), item.bytes] : [item.bytes]), Buffer.from(']}')]);
    const value = { events, bytes };
    if (step.capture_materialized_event_as) materialized.set(step.capture_materialized_event_as, value);
    if (step.capture_outbox_bytes_as) outboxBytes.set(step.capture_outbox_bytes_as, bytes);
    used('event_template', 'event_templates', 'event_id_recipe', 'wire_event_id_override', 'payload_materialization', 'capture_materialized_event_as');
    used('capture_outbox_bytes_as');
    if (!step.event_template && !step.event_templates) { ledger.consume('/outbox_event_template'); ledger.consume('/event_id_recipe'); }
    if (step.payload_materialization) ledger.consume('/limits');
    return value;
  };
  const observableNoMutation = async (before) => {
    const after = await view(); same(after, before, 'acceptance_unchanged');
  };
  const assertExpected = async (expected, response, context = {}) => {
    const result = response?.body?.results?.[0];
    let summary;
    const summaryOf = async () => summary ||= await read();
    const sourcesOf = async () => (await summaryOf()).devices.flatMap((device) => device.sources);
    for (const [key, value] of Object.entries(expected)) {
      switch (key) {
        case 'outcome':
          // Canonical outcome/HTTP relation was checked by static validation.
          check(typeof value === 'string', 'outcome'); break;
        case 'http':
          same(response.status, value.status, 'expected_http_status');
          if (value.result_status) same(result?.status, value.result_status, 'expected_result_status');
          if (value.error_code) same(response.body.error?.code, value.error_code, 'expected_error_code');
          if (value.details) {
            // The wire error uses a qualified event path; the fixture names the
            // envelope field. Accept only that exact known qualification.
            const actual = response.body.error?.details?.field;
            check(actual === value.details.field || actual === `event.${value.details.field}`, 'error_details');
          }
          break;
        case 'device_projection_state': case 'projection_state':
          check((await summaryOf()).devices.length > 0, 'projection_present');
          check((await summaryOf()).devices.every((device) => device.state === value), 'device_projection'); break;
        case 'person_projection_state': {
          const s = await summaryOf();
          check(!('person_projection_state' in s) && !('person' in s), 'no_person_projection');
          same(s.semantics.sleep_inference, 'not_supported', 'no_person_inference');
          check(['awake_evidence', 'unknown'].includes(value), 'person_expected_vocabulary');
          if (value === 'awake_evidence') check(s.devices.some((device) => device.state === 'active'), 'awake_device_compatibility');
          else check(s.devices.every((device) => device.state === 'unknown'), 'unknown_device_compatibility');
          break;
        }
        case 'forbidden_states': {
          const s = await summaryOf();
          check([...s.devices, ...await sourcesOf()].every((entry) => !value.includes(entry.state)), 'forbidden_projection');
          same(s.semantics.sleep_inference, 'not_supported', 'no_sleep_inference'); break;
        }
        case 'receipt_time_owner': same(value, 'core', 'receipt_owner'); same(result?.received_at_ms, now, 'core_receipt_time'); break;
        case 'receipt_ref': same(result?.receipt_id, receipts.get(value), 'same_receipt'); consumedReceipts.add(value); break;
        case 'clock_health': same(result?.clock_health, value, 'clock_health'); break;
        case 'sequence_coverage': subset(result?.sequence_coverage, value, 'sequence_coverage'); break;
        case 'sequence_diagnostics': same(result?.sequence_diagnostics, value, 'sequence_diagnostics'); break;
        case 'projection_recomputed_through_origin_sequence': same(result?.projection_recomputed_through_origin_sequence, value, 'recomputed_through'); break;
        case 'concrete_projection_advanced':
          same(value, false, 'no_concrete_advance_requirement');
          check((await sourcesOf()).every((source) => source.state === 'unknown'), 'concrete_not_advanced'); break;
        case 'concrete_projection_restored':
          same(value, true, 'restoration_requirement'); check((await sourcesOf()).every((source) => ['active', 'locked'].includes(source.state)), 'concrete_restored'); break;
        case 'acceptance_mutated':
          same(value, false, 'no_mutation_requirement'); await observableNoMutation(context.before); break;
        case 'allowed_payload_fields': {
          const changes = success(await request('GET', `${ROOT}/admin/export`, owner)).events;
          check(changes.length > 0, 'accepted_feed_present');
          for (const item of changes) same(Object.keys(item.payload).sort(), [...value].sort(), 'allowed_payload');
          const readerChanges = success(await feed()).events;
          check(readerChanges.every((item) => !('payload' in item.payload) && !('canonical_digest' in item.payload)), 'reader_no_raw_payload'); break;
        }
        case 'event_id_prefix_ref': same(response.body.event_id_prefix, captures.get(value), 'rotation_lineage'); break;
        case 'event_id_prefix_must_differ_from': check(response.body.event_id_prefix !== captures.get(value), 'new_lineage'); break;
        case 'action': same(value, 'discard_without_rebinding', 'outbox_action'); check(context.discarded, 'outbox_discarded'); break;
        case 'must_not_submit_with_replacement_prefix': same(value, true, 'no_rebind_requirement'); check(context.discarded, 'outbox_not_rebound'); break;
        case 'old_outbox_bytes_rejected': same(value, true, 'outbox_rejection_requirement'); check(context.rejected, 'outbox_bytes_rejected'); break;
        case 'local_outbox_discarded': same(value, true, 'outbox_discard_requirement'); check(context.discarded, 'local_outbox_discard'); break;
        case 'receipt_must_not_be_guessed': same(value, true, 'no_guessed_receipt_requirement'); check(!('results' in response.body) && !JSON.stringify(response.body).includes('receipt'), 'no_guessed_receipt'); break;
        case 'accepted_items':
          same(value, 0, 'zero_accepted_requirement'); await observableNoMutation(context.before); break;
        case 'rejected_item_reason': same(response.body.error?.code, value, 'rejected_reason'); break;
        case 'private_data_returned':
          same(value, false, 'no_private_data_requirement'); same(Object.keys(response.body), ['error'], 'error_only'); break;
        case 'resource_lookup_performed': case 'idempotency_lookup_after_revocation':
          same(value, false, 'lookup_requirement');
          check(context.alternate && isDeepStrictEqual(context.alternate, response), 'observable_uniform_denial');
          await observableNoMutation(context.before); break;
        case 'server_assigned_scopes_unchanged':
          same(value, true, 'fixed_scope_requirement');
          same(pairs.get('primary').scopes, ['activity.write'], 'paired_write_scope');
          same((await request('GET', `${ROOT}/summary`, pairs.get('primary').probe_token)).body.error?.code, 'scope_denied', 'scope_still_denied'); break;
        default: throw new CheckFailure('unused_expectation');
      }
      expectations += countLeaves(value);
    }
    if (stepIndex < 0) ledger.consume('/expected'); else used('expected');
  };
  try {
    await start(); onLifecycle?.({ phase: 'started', case: c.name });
    reader = success(await request('POST', `${ROOT}/readers/pair`, owner,
      { installation_id: 'fixture-reader', display_name: 'fixture-reader', capabilities: [] }));
    same(reader.scopes, ['activity.read_summary'], 'reader_scopes');
    firstCursor = reader.initial_cursor;
    for (const spec of c.setup?.pair_probes || (c.setup?.pair_probe ? [c.setup.pair_probe] : [])) await pair(spec);
    ledger.consume('/setup/pair_probe'); ledger.consume('/setup/pair_probes');
    for (const [key, ref] of Object.entries(c.setup?.capture || {})) {
      const pairRef = ref.includes('sibling') ? 'sibling' : 'primary';
      captures.set(`setup.capture.${key}`, pairs.get(pairRef)[ref.endsWith('.probe_token') ? 'probe_token' : 'event_id_prefix']);
      ledger.consume(`/setup/capture/${key}`);
    }
    if (c.execution) {
      same(c.execution, 'projection_contract', 'projection_execution');
      same(c.projection_input.last_activity_event, null, 'silence_no_event');
      const spec = { ref: 'primary', device_id: 'fixture-silent-device', probe_id: 'fixture-silent-probe',
        display_name: 'fixture-silent-probe', source: 'windows_probe', coverage_mode: c.projection_input.coverage.mode,
        expected_report_interval_ms: 30000, expiry_slo_ms: 300000, allowed_kinds: ['probe.heartbeat'] };
      await pair(spec); const before = await read(); await advanceClock(now + c.projection_input.elapsed_without_event_ms);
      const after = await read();
      same(after.generated_at_ms - before.generated_at_ms, c.projection_input.elapsed_without_event_ms, 'silence_elapsed');
      check(after.devices[0].sources[0].occurred_at_ms === null, 'silence_no_signal');
      await assertExpected(c.expected, { status: 200, body: after }); steps += 1;
      ledger.consume('/execution'); ledger.consume('/projection_input');
    } else if (c.request) {
      const before = await view();
      const response = await request(c.request.method, c.request.path, pairs.get(c.request.credential_ref).probe_token, c.request.body);
      let alternate;
      if (c.expected.resource_lookup_performed === false) {
        alternate = await request('GET', `${c.request.path}?cursor=synthetic-nonexistent`, pairs.get('primary').probe_token);
      }
      await assertExpected(c.expected, response, { before, alternate }); steps += 1;
      ledger.consume('/request');
    } else {
      for (const step of c.steps) {
        stepIndex += 1;
        const primary = pairs.get('primary');
        switch (step.operation) {
          case 'materialize_and_queue_outbox_event': make(step); break;
          case 'submit_events': {
            const value = step.materialized_event_ref ? materialized.get(step.materialized_event_ref) : make(step);
            check(value, 'materialized_reference');
            if (step.materialized_event_ref) consumedEvents.add(step.materialized_event_ref);
            if (step.credential_generation !== undefined) same(primary.credential_generation, step.credential_generation, 'credential_generation');
            const token = step.credential_ref === 'setup.capture.probe_token_ref' ? captures.get(step.credential_ref) : pairs.get(step.credential_ref || 'primary').probe_token;
            const before = stale ? null : await view();
            const response = await request('POST', `${ROOT}/events`, token, undefined, value.bytes); submissions += 1;
            if (step.capture_receipt_as) receipts.set(step.capture_receipt_as, response.body.results?.[0]?.receipt_id);
            used('materialized_event_ref', 'credential_generation', 'credential_ref', 'capture_receipt_as');
            if (response.status === 200) {
              same(response.body.results.length, value.events.length, 'all_submitted_results');
              response.body.results.forEach((r, index) => {
                same(r.event_id, value.events[index].event_id, 'literal_event_id_receipt');
                check(typeof r.receipt_id === 'string' && r.receipt_id.startsWith('activity-receipt:'), 'receipt_present');
              });
            }
            let alternate;
            if (step.expected.idempotency_lookup_after_revocation === false) {
              alternate = await request('POST', `${ROOT}/events`, token, { events: [] });
            }
            if (stale) {
              same(response.status, 409, 'stale_http_status');
              // Restart cleanly to observe durable non-acceptance via HTTP only.
              await core.close(); await start(); stale = false;
              const baseline = await view();
              same(baseline.feed.events.filter((item) => item.kind === 'activity.event.accepted'), [], 'stale_zero_acceptance');
              await assertExpected(step.expected, response, { before: baseline });
            } else await assertExpected(step.expected, response, { before, alternate });
            break;
          }
          case 'rotate_probe_credential': {
            const response = await request('POST', `${ROOT}/principals/${encodeURIComponent(pairs.get(step.principal_ref).principal_id)}/rotate`, owner);
            await assertExpected(step.expected, response);
            const old = primary.probe_token;
            pairs.set('primary', { ...primary, probe_token: response.body.token, credential_generation: response.body.credential_generation });
            same((await request('POST', `${ROOT}/events`, old, { events: [] })).body.error?.code, 'revoked_replay', 'old_generation_denied'); break;
          }
          case 'delete_probe': {
            const response = await request('DELETE', `${ROOT}/probes/${encodeURIComponent(pairs.get(step.principal_ref).probe_id)}`, owner);
            await assertExpected(step.expected, response); same((await read()).devices, [], 'deleted_projection'); used('principal_ref'); break;
          }
          case 'pair_new_lineage': {
            same(step.ref, step.replacement_pair.ref, 'replacement_ref');
            replacement = await pair(step.replacement_pair);
            for (const [key, ref] of Object.entries(step.capture)) {
              const field = ref.endsWith('.probe_token') ? 'probe_token' : 'event_id_prefix';
              captures.set(`replacement.capture.${key}`, replacement[field]);
            }
            used('ref', 'replacement_pair', 'capture');
            await assertExpected(step.expected, { status: 200, body: replacement }); break;
          }
          case 'resolve_deleted_lineage_outbox': {
            const value = materialized.get(step.materialized_event_ref);
            const bytes = outboxBytes.get(step.outbox_bytes_ref);
            check(value && bytes && replacement && value.bytes === bytes, 'deleted_outbox_setup');
            consumedEvents.add(step.materialized_event_ref);
            used('materialized_event_ref', 'outbox_bytes_ref');
            const replacementPrefix = captures.get('replacement.capture.replacement_event_id_prefix');
            const replacementToken = captures.get('replacement.capture.replacement_probe_token_ref');
            check(value.events.every((event) => !event.event_id.startsWith(`${replacementPrefix}.`)), 'original_outbox_prefix');
            const before = await view();
            const denied = await request('POST', `${ROOT}/events`, primary.probe_token, undefined, bytes); submissions += 1;
            same(denied.status, 401, 'deleted_credential_denied');
            // Diagnostic wrong-lineage delivery retains the ORIGINAL bytes.
            const mismatch = await request('POST', `${ROOT}/events`, replacementToken, undefined, bytes); submissions += 1;
            same(mismatch.status, 403, 'replacement_lineage_denied');
            same(mismatch.body.error?.code, 'identity_binding_mismatch', 'deleted_outbox_binding');
            outboxBytes.delete(step.outbox_bytes_ref); materialized.delete(step.materialized_event_ref);
            await observableNoMutation(before);
            await assertExpected(step.expected, null, {
              discarded: !outboxBytes.has(step.outbox_bytes_ref) && !materialized.has(step.materialized_event_ref),
              rejected: true,
            }); break;
          }
          case 'revoke_probe': {
            await advanceClock(step.revoked_at_ms);
            const response = await request('POST', `${ROOT}/probes/${encodeURIComponent(pairs.get(step.principal_ref).probe_id)}/revoke`, owner);
            same(response.body.revoked_at_ms, step.revoked_at_ms, 'revocation_time');
            await assertExpected(step.expected, response); used('principal_ref', 'revoked_at_ms'); break;
          }
          case 'advance_retention_past_event_detail': {
            same(step.retained_origin_floor, 1, 'retention_floor_fixture');
            await advanceClock(now + ACTIVITY_RAW_RETENTION_MS + 1);
            success(await request('POST', `${ROOT}/admin/retention`, owner));
            const old = await feed(firstCursor);
            same([old.status, old.body.error?.code, old.body.error?.details?.reason], [409, 'resync_required', 'retention_gap'], 'old_cursor_resync');
            const snapshot = success(await request('GET', `${ROOT}/snapshot`, reader.reader_token));
            reader.initial_cursor = snapshot.base_cursor;
            check(snapshot.retained_watermark > 0, 'retention_watermark');
            const remaining = success(await feed()); same(remaining.events, [], 'retention_feed_empty'); break;
          }
          case 'advance_core_authority': {
            same([c.core.pairing_epoch, c.core.active_epoch, c.core.active_fencing_token],
              [step.from_epoch, step.to_epoch, step.fencing_token], 'authority_fixture_binding');
            same([step.from_epoch, step.to_epoch, step.fencing_token], ['epoch-synthetic-9', 'epoch-synthetic-10', 19], 'authority_fixture_transition');
            used('from_epoch', 'to_epoch', 'fencing_token');
            ledger.consume('/core/pairing_epoch'); ledger.consume('/core/active_epoch'); ledger.consume('/core/active_fencing_token');
            await stopListener();
            installStaleRuntimeEpoch(core, primary.authority.epoch, 1);
            await resumeListener(); stale = true; break;
          }
          default: throw new CheckFailure('unused_operation');
        }
        if (step.operation === 'rotate_probe_credential') used('principal_ref');
        if (step.operation === 'advance_retention_past_event_detail') used('retained_origin_floor');
        used('operation');
        steps += 1;
      }
    }
    for (const name of materialized.keys()) check(consumedEvents.has(name), 'unused_materialization');
    same(outboxBytes.size, 0, 'unused_outbox_bytes');
    for (const name of receipts.keys()) check(consumedReceipts.has(name), 'unused_receipt_capture');
    for (const name of captures.keys()) check(usedCaptures.has(name), 'unused_capture');
    const expectedCount = (c.expected ? [c.expected] : c.steps.filter((step) => step.expected).map((step) => step.expected))
      .reduce((sum, expected) => sum + Object.values(expected).reduce((n, value) => n + countLeaves(value), 0), 0);
    same(expectations, expectedCount, 'unconsumed_expectation');
    same(steps, c.steps?.length || 1, 'unconsumed_step');
    fields = ledger.finish();
  } catch (error) {
    failure = error instanceof CheckFailure ? error.check : 'execution_error';
  } finally {
    try { await core?.close(); check(!core?.server.listening, 'teardown_listener'); }
    catch { failure = 'teardown_close'; }
    try {
      // Exact system-temp directory created by this invocation; never fixtureDir.
      check(path.dirname(directory) === path.resolve(tmpdir()) && path.basename(directory).startsWith(`mda1-http-case-${process.pid}-`), 'cleanup_target');
      rmSync(directory, { recursive: true, force: true, maxRetries: 3, retryDelay: 50 });
      check(!existsSync(directory), 'teardown_directory');
    } catch { failure = 'teardown_remove'; }
  }
  return { name: c.name, status: failure ? 'failed' : 'passed', requests, wire_checks: wireChecks,
    submissions, exact_retries: retries, steps, expectations, fields,
    ...(failure ? { check: failure } : {}) };
}

export async function runFixtureHttp({ fixturesDir = DEFAULT_FIXTURE_DIRECTORY, onLifecycle } = {}) {
  let set;
  try {
    set = loadFixtureSet(fixturesDir); // privacy lint + validation before captures, temp DBs, and network
    set.directory = fixturesDir; preflight(set);
  } catch {
    return { status: 'rejected_before_http', files: 0, cases: [], requests: 0, check: 'static_or_runner_contract' };
  }
  const cases = [];
  for (const entry of set.manifest.files) {
    for (const name of entry.cases) {
      const c = set.documents.get(entry.file).cases.find((item) => item.name === name);
      try { cases.push(await executeCase(c, onLifecycle)); }
      catch {
        cases.push({ name, status: 'failed', requests: 0, wire_checks: 0,
          submissions: 0, exact_retries: 0, steps: 0, expectations: 0, fields: 0, check: 'case_setup_error' });
      }
    }
  }
  return { status: cases.every((c) => c.status === 'passed') ? 'passed_with_evidence_boundaries' : 'failed',
    files: set.fileCount, case_count: cases.length, passed: cases.filter((c) => c.status === 'passed').length,
    requests: cases.reduce((sum, c) => sum + c.requests, 0), cases, evidence_boundaries: [...BOUNDARIES] };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const report = await runFixtureHttp();
  process.stdout.write(`${JSON.stringify(report)}\n`);
  if (report.status !== 'passed_with_evidence_boundaries') process.exitCode = 1;
}
