import fs from 'node:fs';
import path from 'node:path';

const CASE_FILES = [
  'valid_and_idempotency.json', 'validation_and_clock.json',
  'coverage_scope_and_replay.json', 'limits_and_atomicity.json',
];
const OVERRIDE_CASES = new Set(['noncanonical_event_id', 'wrong_event_id_prefix', 'event_id_sequence_mismatch']);
const OPERATIONS = new Set(['submit_events', 'materialize_and_queue_outbox_event', 'rotate_probe_credential', 'delete_probe', 'pair_new_lineage', 'resolve_deleted_lineage_outbox', 'advance_retention_past_event_detail', 'revoke_probe', 'advance_core_authority']);
const PRIVATE_KEY = /(message_body|notification_body|window_title|app_name|keystroke|contact|chat_content|private_content)/i;
const CREDENTIAL_KEY = /(authorization|bearer|credential|token|secret|password|api[_-]?key)/i;
const LITERAL_FORBIDDEN = [
  /^bearer[ \t]+\S+$/i, /^(token|secret|password|api[-_]?key)[-_:].+$/i,
  /^sk-[A-Za-z0-9_-]+$/, /^[A-Fa-f0-9]{32,}$/, /^[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}$/, /^[a-z][a-z0-9+.-]*:\/\//i,
];
const SYMBOLIC_VALUE = /^(pair_probe|pair_probes\.(primary|sibling)|replacement_pair)\.response\.(event_id_prefix|probe_token)$|^setup\.capture\.(event_id_prefix|sibling_event_id_prefix|probe_token_ref)$|^primary$/;
const SYMBOLIC_REF_LIKE = /^(pair_probe|pair_probes\.(primary|sibling)|replacement_pair|setup\.capture|replacement\.capture)\./;
const EXPECTED_KEYS = new Set(['outcome', 'http', 'device_projection_state', 'person_projection_state', 'receipt_time_owner', 'receipt_ref', 'acceptance_mutated', 'clock_health', 'projection_state', 'concrete_projection_advanced', 'forbidden_states', 'allowed_payload_fields', 'sequence_coverage', 'sequence_diagnostics', 'projection_recomputed_through_origin_sequence', 'concrete_projection_restored', 'details', 'event_id_prefix_ref', 'event_id_prefix_must_differ_from', 'action', 'must_not_submit_with_replacement_prefix', 'old_outbox_bytes_rejected', 'local_outbox_discarded', 'receipt_must_not_be_guessed', 'idempotency_lookup_after_revocation', 'accepted_items', 'rejected_item_reason', 'resource_lookup_performed', 'private_data_returned', 'server_assigned_scopes_unchanged']);
const EVENT_KEYS = new Set(['contract', 'schema_version', 'device_id', 'probe_id', 'origin_sequence', 'kind', 'signal_at_ms', 'received_at_ms', 'ttl_ms', 'confidence', 'source', 'coverage', 'payload']);
const COVERAGE_KEYS = new Set(['mode', 'window_start_ms', 'window_end_ms', 'expected_report_interval_ms']);
// Frozen from DEVICE_ACTIVITY_V1_ADR.md section 3; kept local so this gate has no shared-runtime dependency.
const ADR_KINDS = new Set(['probe.heartbeat', 'session.locked', 'session.unlocked', 'input.activity', 'input.idle_bucket', 'screen.interactive', 'screen.non_interactive', 'app.category_active', 'focus.sleep_on', 'focus.sleep_off', 'power.charging', 'power.unplugged', 'network.present', 'sensor.heart_rate_quality', 'probe.permission_changed', 'probe.error']);
const COVERAGE_MODES = new Set(['continuous', 'discrete_best_effort', 'heartbeat_only', 'none', 'unknown']);
const OVERRIDE_MODE_BY_CASE = new Map([
  ['noncanonical_event_id', 'captured_prefix_with_literal_suffix'],
  ['wrong_event_id_prefix', 'different_pairing_prefix_with_canonical_sequence'],
  ['event_id_sequence_mismatch', 'captured_prefix_with_literal_suffix'],
]);
const PAYLOAD_SCHEMA = new Map([
  ['probe.heartbeat', {}], ['session.locked', {}], ['session.unlocked', {}], ['screen.interactive', {}], ['screen.non_interactive', {}], ['focus.sleep_on', {}], ['focus.sleep_off', {}], ['power.charging', {}], ['power.unplugged', {}], ['network.present', {}],
  ['input.activity', { class: ['input_or_touch'] }], ['input.idle_bucket', { bucket: ['lt_1m', '1_5m', '5_15m', '15m_plus'] }], ['app.category_active', { category: ['chat', 'social', 'video', 'reading', 'work', 'other'] }],
  ['sensor.heart_rate_quality', { quality: ['fresh', 'stale', 'gap', 'unavailable'], source_age_ms: 'integer' }], ['probe.permission_changed', { capability: 'token', available: 'boolean' }], ['probe.error', { code: 'token' }],
]);
const HTTP_SEMANTICS = new Map([
  ['accepted', [200, 'accepted']], ['accepted_with_conservative_unknown', [200, 'accepted']], ['duplicate', [200, 'duplicate']], ['idempotency_conflict', [409, 'idempotency_conflict']], ['invalid_event_id', [400, 'invalid_event_id']], ['event_id_binding_mismatch', [403, 'event_id_binding_mismatch']], ['event_retained_out', [410, 'event_retained_out']], ['unsupported_kind', [400, 'unsupported_kind']], ['missing_required_field', [400, 'missing_required_field']], ['unknown_field', [400, 'unknown_field']], ['ttl_expired', [410, 'ttl_expired']], ['forbidden_scope', [403, 'scope_denied']], ['chat_read_forbidden', [403, 'chat_read_forbidden']], ['admin_escalation_forbidden', [403, 'admin_escalation_forbidden']], ['credential_revoked', [401, 'revoked_replay']], ['origin_mismatch', [403, 'identity_binding_mismatch']], ['payload_too_large', [413, 'payload_too_large']], ['batch_rejected_atomically', [400, 'unsupported_kind']], ['stale_epoch_or_fencing', [409, 'stale_authority_epoch']],
]);
// Canonical scenario identity: case name, high-level runner shape, and declared primary results only.
const CANONICAL_CASES = new Map([
  ['valid_event',['submit_events','accepted/200/accepted']],['duplicate_same_payload',['submit_events,submit_events','accepted/200/accepted|duplicate/200/duplicate']],['heart_rate_quality_without_inference',['submit_events','accepted/200/accepted']],['duplicate_different_payload',['submit_events,submit_events','accepted/200/accepted|idempotency_conflict/409/idempotency_conflict']],['noncanonical_event_id',['submit_events','invalid_event_id/400/invalid_event_id']],['wrong_event_id_prefix',['submit_events','event_id_binding_mismatch/403/event_id_binding_mismatch']],['event_id_sequence_mismatch',['submit_events','event_id_binding_mismatch/403/event_id_binding_mismatch']],['credential_rotation_preserves_lineage',['rotate_probe_credential,submit_events','accepted/200/|accepted/200/accepted']],['deleted_lineage_outbox_not_rebound',['materialize_and_queue_outbox_event,delete_probe,pair_new_lineage,resolve_deleted_lineage_outbox','|accepted/200/|accepted/200/|client_action_required//']],['retained_out_retry',['submit_events,advance_retention_past_event_detail,submit_events','accepted/200/accepted||event_retained_out/410/event_retained_out']],
  ['illegal_kind',['submit_events','unsupported_kind/400/unsupported_kind']],['missing_required_field',['submit_events','missing_required_field/400/missing_required_field']],['unknown_field',['submit_events','unknown_field/400/unknown_field']],['future_clock',['submit_events','accepted_with_conservative_unknown/200/accepted']],['clock_regression',['submit_events,submit_events','accepted/200/accepted|accepted_with_conservative_unknown/200/accepted']],['sequence_gap_then_out_of_order_fill',['materialize_and_queue_outbox_event,materialize_and_queue_outbox_event,materialize_and_queue_outbox_event,submit_events,submit_events,submit_events','|||accepted/200/accepted|accepted_with_conservative_unknown/200/accepted|accepted/200/accepted']],['ttl_expired',['submit_events','ttl_expired/410/ttl_expired']],
  ['no_coverage_silence',['execution:projection_contract','unknown_no_coverage//']],['wrong_scope',['request','forbidden_scope/403/scope_denied']],['write_token_chat_read_denied',['request','chat_read_forbidden/403/chat_read_forbidden']],['probe_admin_escalation',['request','admin_escalation_forbidden/403/admin_escalation_forbidden']],['revoked_replay',['submit_events,revoke_probe,submit_events','accepted/200/accepted|accepted/200/|credential_revoked/401/revoked_replay']],['cross_device_impersonation',['submit_events','origin_mismatch/403/identity_binding_mismatch']],['oversized_payload',['submit_events','payload_too_large/413/payload_too_large']],['batch_atomic_rejection',['submit_events','batch_rejected_atomically/400/unsupported_kind']],['stale_epoch_or_fencing',['advance_core_authority,submit_events','|stale_epoch_or_fencing/409/stale_authority_epoch']],
]);
// Frozen R5 expected-witness schema. This deliberately does not derive truth from a
// fixture under validation: each case/step may expose only this exact root shape.
const EXPECTED_SLOT_CONTRACTS = new Map([
  ['valid_event#0', [['device_projection_state', 'http', 'outcome', 'person_projection_state', 'receipt_time_owner'], ['result_status', 'status']]],
  ['duplicate_same_payload#0', [['http', 'outcome'], ['result_status', 'status']]], ['duplicate_same_payload#1', [['http', 'outcome', 'receipt_ref'], ['result_status', 'status']]],
  ['heart_rate_quality_without_inference#0', [['allowed_payload_fields', 'forbidden_states', 'http', 'outcome', 'person_projection_state'], ['result_status', 'status']]],
  ['duplicate_different_payload#0', [['http', 'outcome'], ['result_status', 'status']]], ['duplicate_different_payload#1', [['acceptance_mutated', 'http', 'outcome'], ['error_code', 'status']]],
  ['noncanonical_event_id#0', [['acceptance_mutated', 'http', 'outcome'], ['error_code', 'status']]], ['wrong_event_id_prefix#0', [['acceptance_mutated', 'http', 'outcome'], ['error_code', 'status']]], ['event_id_sequence_mismatch#0', [['acceptance_mutated', 'http', 'outcome'], ['error_code', 'status']]],
  ['credential_rotation_preserves_lineage#0', [['event_id_prefix_ref', 'http', 'outcome'], ['status']]], ['credential_rotation_preserves_lineage#1', [['http', 'outcome'], ['result_status', 'status']]],
  ['deleted_lineage_outbox_not_rebound#0', [[], []]], ['deleted_lineage_outbox_not_rebound#1', [['http', 'outcome'], ['status']]], ['deleted_lineage_outbox_not_rebound#2', [['event_id_prefix_must_differ_from', 'http', 'outcome'], ['status']]], ['deleted_lineage_outbox_not_rebound#3', [['action', 'local_outbox_discarded', 'must_not_submit_with_replacement_prefix', 'old_outbox_bytes_rejected', 'outcome'], []]],
  ['retained_out_retry#0', [['http', 'outcome'], ['result_status', 'status']]], ['retained_out_retry#1', [[], []]], ['retained_out_retry#2', [['acceptance_mutated', 'http', 'outcome', 'receipt_must_not_be_guessed'], ['error_code', 'status']]],
  ['illegal_kind#0', [['acceptance_mutated', 'http', 'outcome'], ['error_code', 'status']]], ['missing_required_field#0', [['acceptance_mutated', 'http', 'outcome'], ['details', 'error_code', 'status']]], ['unknown_field#0', [['acceptance_mutated', 'http', 'outcome'], ['details', 'error_code', 'status']]],
  ['future_clock#0', [['clock_health', 'concrete_projection_advanced', 'forbidden_states', 'http', 'outcome', 'projection_state'], ['result_status', 'status']]], ['clock_regression#0', [['http', 'outcome'], ['result_status', 'status']]], ['clock_regression#1', [['clock_health', 'concrete_projection_advanced', 'forbidden_states', 'http', 'outcome', 'projection_state'], ['result_status', 'status']]],
  ['sequence_gap_then_out_of_order_fill#0', [[], []]], ['sequence_gap_then_out_of_order_fill#1', [[], []]], ['sequence_gap_then_out_of_order_fill#2', [[], []]], ['sequence_gap_then_out_of_order_fill#3', [['device_projection_state', 'http', 'outcome', 'sequence_coverage'], ['result_status', 'status']]], ['sequence_gap_then_out_of_order_fill#4', [['concrete_projection_advanced', 'http', 'outcome', 'projection_state', 'sequence_coverage', 'sequence_diagnostics'], ['result_status', 'status']]], ['sequence_gap_then_out_of_order_fill#5', [['clock_health', 'concrete_projection_restored', 'device_projection_state', 'http', 'outcome', 'projection_recomputed_through_origin_sequence', 'sequence_coverage', 'sequence_diagnostics'], ['result_status', 'status']]],
  ['ttl_expired#0', [['acceptance_mutated', 'http', 'outcome'], ['error_code', 'status']]],
  ['no_coverage_silence#case', [['forbidden_states', 'outcome', 'projection_state'], []]], ['wrong_scope#case', [['acceptance_mutated', 'http', 'outcome'], ['error_code', 'status']]], ['write_token_chat_read_denied#case', [['http', 'outcome', 'private_data_returned', 'resource_lookup_performed'], ['error_code', 'status']]], ['probe_admin_escalation#case', [['acceptance_mutated', 'http', 'outcome', 'server_assigned_scopes_unchanged'], ['error_code', 'status']]],
  ['revoked_replay#0', [['http', 'outcome'], ['result_status', 'status']]], ['revoked_replay#1', [['http', 'outcome'], ['status']]], ['revoked_replay#2', [['acceptance_mutated', 'http', 'idempotency_lookup_after_revocation', 'outcome'], ['error_code', 'status']]], ['cross_device_impersonation#0', [['acceptance_mutated', 'http', 'outcome'], ['error_code', 'status']]],
  ['oversized_payload#0', [['acceptance_mutated', 'http', 'outcome'], ['error_code', 'status']]], ['batch_atomic_rejection#0', [['accepted_items', 'http', 'outcome', 'rejected_item_reason'], ['error_code', 'status']]], ['stale_epoch_or_fencing#0', [[], []]], ['stale_epoch_or_fencing#1', [['acceptance_mutated', 'http', 'outcome'], ['error_code', 'status']]],
]);

export class FixtureContractError extends Error {
  constructor(code, pathName = '') { super(pathName ? `${code}:${pathName}` : code); this.name = 'FixtureContractError'; this.code = code; }
}

function fail(code, p) { throw new FixtureContractError(code, p); }
function object(value, p) { if (!value || Array.isArray(value) || typeof value !== 'object') fail('invalid_object', p); return value; }
function keysOnly(value, allowed, p) { for (const key of Object.keys(object(value, p))) if (!allowed.has(key)) fail('unknown_field', `${p}.${key}`); }
function required(value, names, p) { for (const name of names) if (!(name in value)) fail('missing_required_field', `${p}.${name}`); }
function string(value, p) { if (typeof value !== 'string' || !value) fail('invalid_string', p); }
function integer(value, p) { if (!Number.isInteger(value)) fail('invalid_integer', p); }
function sameKeys(actual, expected) { return actual.length === expected.length && actual.every((key, index) => key === expected[index]); }
function assertExpectedSlot(caseName, slot, expected, p) {
  const contract = EXPECTED_SLOT_CONTRACTS.get(`${caseName}#${slot}`);
  if (!contract) fail('unknown_expected_slot', p);
  const [rootKeys, httpKeys] = contract;
  const actualRoot = expected ? Object.keys(expected).sort() : [];
  if (!sameKeys(actualRoot, rootKeys)) fail('expected_slot_keys_mismatch', p);
  if (!expected) return;
  const actualHttp = expected.http ? Object.keys(expected.http).sort() : [];
  if (!sameKeys(actualHttp, httpKeys)) fail('expected_http_keys_mismatch', `${p}.http`);
  if (expected.http?.details && !sameKeys(Object.keys(expected.http.details).sort(), ['field'])) fail('expected_http_details_keys_mismatch', `${p}.http.details`);
  if (expected.sequence_coverage && !sameKeys(Object.keys(expected.sequence_coverage).sort(), ['contiguous_through', 'highest_seen', 'missing'])) fail('expected_sequence_coverage_keys_mismatch', `${p}.sequence_coverage`);
}
function expectedString(value, p) { if (typeof value !== 'string' || !value) fail('invalid_expected_string', p); }
function expectedBoolean(value, p) { if (typeof value !== 'boolean') fail('invalid_expected_boolean', p); }
function expectedCounter(value, p) { if (!Number.isSafeInteger(value) || value < 0) fail('invalid_expected_counter', p); }
function expectedStringArray(value, p) {
  if (!Array.isArray(value) || value.some((item) => typeof item !== 'string' || !item) || new Set(value).size !== value.length) fail('invalid_expected_string_array', p);
}
function expectedMissingArray(value, p) {
  if (!Array.isArray(value) || value.some((item) => !Number.isSafeInteger(item) || item < 0) || new Set(value).size !== value.length) fail('invalid_expected_missing_array', p);
}
function validateExpectedLeaves(expected, p) {
  const strings = ['outcome', 'device_projection_state', 'person_projection_state', 'receipt_time_owner', 'receipt_ref', 'clock_health', 'projection_state', 'event_id_prefix_ref', 'event_id_prefix_must_differ_from', 'action', 'rejected_item_reason'];
  const booleans = ['acceptance_mutated', 'concrete_projection_advanced', 'concrete_projection_restored', 'must_not_submit_with_replacement_prefix', 'old_outbox_bytes_rejected', 'local_outbox_discarded', 'receipt_must_not_be_guessed', 'idempotency_lookup_after_revocation', 'resource_lookup_performed', 'private_data_returned', 'server_assigned_scopes_unchanged'];
  const counters = ['projection_recomputed_through_origin_sequence', 'accepted_items'];
  const stringArrays = ['forbidden_states', 'allowed_payload_fields', 'sequence_diagnostics'];
  for (const key of strings) if (key in expected) expectedString(expected[key], `${p}.${key}`);
  for (const key of booleans) if (key in expected) expectedBoolean(expected[key], `${p}.${key}`);
  for (const key of counters) if (key in expected) expectedCounter(expected[key], `${p}.${key}`);
  for (const key of stringArrays) if (key in expected) expectedStringArray(expected[key], `${p}.${key}`);
  if (expected.http !== undefined) {
    object(expected.http, `${p}.http`);
    expectedCounter(expected.http.status, `${p}.http.status`);
    for (const key of ['result_status', 'error_code']) if (key in expected.http) expectedString(expected.http[key], `${p}.http.${key}`);
    if (expected.http.details !== undefined) { object(expected.http.details, `${p}.http.details`); expectedString(expected.http.details.field, `${p}.http.details.field`); }
  }
  if (expected.sequence_coverage !== undefined) {
    object(expected.sequence_coverage, `${p}.sequence_coverage`);
    expectedCounter(expected.sequence_coverage.highest_seen, `${p}.sequence_coverage.highest_seen`);
    expectedCounter(expected.sequence_coverage.contiguous_through, `${p}.sequence_coverage.contiguous_through`);
    expectedMissingArray(expected.sequence_coverage.missing, `${p}.sequence_coverage.missing`);
  }
}

/** Scans parsed raw JSON before any symbolic reference is interpreted. */
export function lintRawPrivacy(value, p = '$') {
  if (Array.isArray(value)) return value.forEach((item, index) => lintRawPrivacy(item, `${p}[${index}]`));
  if (!value || typeof value !== 'object') return;
  for (const [key, child] of Object.entries(value)) {
    const childPath = `${p}.${key}`;
    if (PRIVATE_KEY.test(key)) fail('privacy_private_key', childPath);
    if (CREDENTIAL_KEY.test(key)) {
      const permitted = (
        (key === 'probe_token_ref' && child === 'pair_probe.response.probe_token')
        || (key === 'replacement_probe_token_ref' && child === 'replacement_pair.response.probe_token')
      ) || (
        key === 'credential_ref' && (child === 'primary' || child === 'setup.capture.probe_token_ref')
      ) || (
        ['credential_generation', 'fencing_token', 'active_fencing_token'].includes(key) && Number.isInteger(child) && child >= 0
      );
      if (!permitted) fail('privacy_credential_reference', childPath);
    }
    if (typeof child === 'string' && SYMBOLIC_REF_LIKE.test(child) && !SYMBOLIC_VALUE.test(child)) fail('privacy_symbolic_reference', childPath);
    if (typeof child === 'string' && !SYMBOLIC_VALUE.test(child) && LITERAL_FORBIDDEN.some((pattern) => pattern.test(child))) fail('privacy_literal', childPath);
    lintRawPrivacy(child, childPath);
  }
}

function validateEvent(event, p) {
  if ('event_id' in event) fail('normal_event_has_event_id', p);
  keysOnly(event, EVENT_KEYS, p);
  if (event.coverage !== undefined) { object(event.coverage, `${p}.coverage`); keysOnly(event.coverage, COVERAGE_KEYS, `${p}.coverage`); }
  if (event.payload !== undefined) object(event.payload, `${p}.payload`);
}
function validateRecipe(recipe, p) {
  keysOnly(recipe, new Set(['mode', 'prefix_ref', 'origin_sequence_field']), p); required(recipe, ['mode', 'prefix_ref', 'origin_sequence_field'], p);
  if (recipe.mode !== 'pairing_prefix_dot_canonical_sequence' || recipe.origin_sequence_field !== 'origin_sequence') fail('invalid_event_id_recipe', p);
  assertSymbolicRef(recipe.prefix_ref, p);
}
function validateOverride(override, caseName, p) {
  if (!OVERRIDE_CASES.has(caseName)) fail('wire_override_not_allowlisted', p);
  const modes = new Map([
    ['captured_prefix_with_literal_suffix', new Set(['mode', 'prefix_ref', 'literal_suffix'])],
    ['different_pairing_prefix_with_canonical_sequence', new Set(['mode', 'prefix_ref', 'origin_sequence_field'])],
  ]);
  object(override, p); const allowed = modes.get(override.mode); if (!allowed) fail('invalid_wire_override', p);
  keysOnly(override, allowed, p); required(override, [...allowed], p); assertSymbolicRef(override.prefix_ref, p);
  if (override.mode === 'different_pairing_prefix_with_canonical_sequence' && override.origin_sequence_field !== 'origin_sequence') fail('invalid_wire_override', p);
}
function assertSymbolicRef(ref, p) {
  string(ref, p);
  if (!/^(setup\.capture\.(event_id_prefix|sibling_event_id_prefix|probe_token_ref)|primary)$/.test(ref)) fail('invalid_symbolic_ref', p);
}
function validateExpected(expected, p) {
  keysOnly(expected, EXPECTED_KEYS, p); required(expected, ['outcome'], p); string(expected.outcome, `${p}.outcome`);
  if (expected.http !== undefined) { keysOnly(expected.http, new Set(['status', 'result_status', 'error_code', 'details']), `${p}.http`); required(expected.http, ['status'], `${p}.http`); integer(expected.http.status, `${p}.http.status`); }
  validateExpectedLeaves(expected, p);
}
function validatePair(pair, p) {
  keysOnly(pair, new Set(['ref', 'device_id', 'probe_id', 'display_name', 'source', 'coverage_mode', 'expected_report_interval_ms', 'expiry_slo_ms', 'allowed_kinds', 'capabilities']), p);
  required(pair, ['ref', 'device_id', 'probe_id', 'display_name', 'source', 'coverage_mode', 'expected_report_interval_ms', 'expiry_slo_ms', 'allowed_kinds'], p);
  for (const key of ['ref', 'device_id', 'probe_id', 'display_name', 'source']) string(pair[key], `${p}.${key}`);
  if (!COVERAGE_MODES.has(pair.coverage_mode)) fail('invalid_coverage', `${p}.coverage_mode`);
  for (const key of ['expected_report_interval_ms', 'expiry_slo_ms']) { integer(pair[key], `${p}.${key}`); if (pair[key] <= 0) fail('invalid_integer', `${p}.${key}`); }
  if (!Array.isArray(pair.allowed_kinds) || !pair.allowed_kinds.length || pair.allowed_kinds.some((kind) => !ADR_KINDS.has(kind))) fail('invalid_pair_allowed_kinds', `${p}.allowed_kinds`);
  if (pair.capabilities !== undefined && (!Array.isArray(pair.capabilities) || pair.capabilities.some((item) => typeof item !== 'string' || !/^[a-z][a-z0-9_.]{0,63}$/.test(item)))) fail('invalid_capabilities', `${p}.capabilities`);
}
function validateSetup(setup, p) {
  keysOnly(setup, new Set(['pair_probe', 'pair_probes', 'capture']), p);
  if (!!setup.pair_probe === !!setup.pair_probes) fail('invalid_pairing_setup', p);
  const pairs = setup.pair_probe ? [setup.pair_probe] : setup.pair_probes;
  if (!Array.isArray(pairs) || !pairs.length) fail('invalid_pairing_setup', `${p}.pair_probes`);
  for (const pair of pairs) validatePair(pair, `${p}.pair`);
  if (setup.capture !== undefined) { object(setup.capture, `${p}.capture`); for (const [key, ref] of Object.entries(setup.capture)) { if (!['event_id_prefix', 'sibling_event_id_prefix', 'probe_token_ref'].includes(key)) fail('unknown_field', `${p}.capture.${key}`); const expectedResponse = key === 'probe_token_ref' ? 'probe_token' : 'event_id_prefix'; const expectedPair = key === 'sibling_event_id_prefix' ? 'pair_probes.sibling' : '(pair_probe|pair_probes.primary)'; if (typeof ref !== 'string' || !(new RegExp(`^${expectedPair}\\.response\\.${expectedResponse}$`)).test(ref)) fail('invalid_capture_type', `${p}.capture.${key}`); } }
}
function validateStep(step, caseName, p, captured, capturedOutboxBytes) {
  const common = new Set(['operation', 'expected', 'event_template', 'event_templates', 'event_id_recipe', 'wire_event_id_override', 'payload_materialization', 'materialized_event_ref', 'capture_materialized_event_as', 'capture_outbox_bytes_as', 'outbox_bytes_ref', 'capture_receipt_as', 'credential_ref', 'credential_generation', 'principal_ref', 'retained_origin_floor', 'ref', 'revoked_at_ms', 'from_epoch', 'to_epoch', 'fencing_token', 'replacement_pair', 'capture']);
  keysOnly(step, common, p); required(step, ['operation'], p); if (!OPERATIONS.has(step.operation)) fail('unknown_operation', `${p}.operation`);
  if (step.expected) validateExpected(step.expected, `${p}.expected`);
  if (step.payload_materialization) { keysOnly(step.payload_materialization, new Set(['mode', 'field', 'target_encoded_payload_bytes']), `${p}.payload_materialization`); required(step.payload_materialization, ['mode', 'field', 'target_encoded_payload_bytes'], `${p}.payload_materialization`); if (step.payload_materialization.mode !== 'append_synthetic_padding' || typeof step.payload_materialization.field !== 'string' || !/^[a-z][a-z0-9_]{0,63}$/.test(step.payload_materialization.field) || !Number.isSafeInteger(step.payload_materialization.target_encoded_payload_bytes) || step.payload_materialization.target_encoded_payload_bytes <= 0) fail('invalid_payload_materialization', `${p}.payload_materialization`); }
  if (step.replacement_pair) validatePair(step.replacement_pair, `${p}.replacement_pair`);
  if (step.capture) { keysOnly(step.capture, new Set(['replacement_event_id_prefix', 'replacement_probe_token_ref']), `${p}.capture`); required(step.capture, ['replacement_event_id_prefix', 'replacement_probe_token_ref'], `${p}.capture`); if (step.capture.replacement_event_id_prefix !== 'replacement_pair.response.event_id_prefix' || step.capture.replacement_probe_token_ref !== 'replacement_pair.response.probe_token') fail('invalid_replacement_capture', `${p}.capture`); }
  if (step.capture_outbox_bytes_as) { string(step.capture_outbox_bytes_as, `${p}.capture_outbox_bytes_as`); if (capturedOutboxBytes.has(step.capture_outbox_bytes_as)) fail('duplicate_outbox_bytes_capture', `${p}.capture_outbox_bytes_as`); capturedOutboxBytes.add(step.capture_outbox_bytes_as); }
  if (step.outbox_bytes_ref) { string(step.outbox_bytes_ref, `${p}.outbox_bytes_ref`); if (!capturedOutboxBytes.has(step.outbox_bytes_ref)) fail('missing_outbox_bytes_ref', `${p}.outbox_bytes_ref`); }
  const materializing = step.operation === 'submit_events' || step.operation === 'materialize_and_queue_outbox_event';
  if (materializing && !step.materialized_event_ref) {
    if (step.operation === 'materialize_and_queue_outbox_event' && !step.event_template && !step.event_templates) {
      if (step.capture_materialized_event_as) { string(step.capture_materialized_event_as, `${p}.capture_materialized_event_as`); if (captured.has(step.capture_materialized_event_as)) fail('duplicate_capture', `${p}.capture_materialized_event_as`); captured.add(step.capture_materialized_event_as); }
      return;
    }
    if (!!step.event_template === !!step.event_templates) fail('invalid_event_template', p);
    if (step.event_template) validateEvent(step.event_template, `${p}.event_template`);
    else { if (!Array.isArray(step.event_templates) || !step.event_templates.length) fail('invalid_event_template', `${p}.event_templates`); step.event_templates.forEach((event, index) => validateEvent(event, `${p}.event_templates[${index}]`)); }
    if (step.wire_event_id_override) validateOverride(step.wire_event_id_override, caseName, `${p}.wire_event_id_override`); else { required(step, ['event_id_recipe'], p); validateRecipe(step.event_id_recipe, `${p}.event_id_recipe`); }
  }
  if (step.materialized_event_ref) { string(step.materialized_event_ref, `${p}.materialized_event_ref`); if (!captured.has(step.materialized_event_ref)) fail('missing_materialized_ref', `${p}.materialized_event_ref`); }
  if (step.capture_materialized_event_as) { string(step.capture_materialized_event_as, `${p}.capture_materialized_event_as`); if (captured.has(step.capture_materialized_event_as)) fail('duplicate_capture', `${p}.capture_materialized_event_as`); captured.add(step.capture_materialized_event_as); }
}
function validateCase(caseDoc, p) {
  keysOnly(caseDoc, new Set(['name', 'setup', 'core', 'steps', 'outbox_event_template', 'event_id_recipe', 'execution', 'projection_input', 'request', 'expected', 'limits']), p); required(caseDoc, ['name'], p); string(caseDoc.name, `${p}.name`);
  if (caseDoc.limits !== undefined) { keysOnly(caseDoc.limits, new Set(['maximum_payload_bytes']), `${p}.limits`); required(caseDoc.limits, ['maximum_payload_bytes'], `${p}.limits`); if (!Number.isSafeInteger(caseDoc.limits.maximum_payload_bytes) || caseDoc.limits.maximum_payload_bytes <= 0) fail('invalid_payload_limit', `${p}.limits.maximum_payload_bytes`); }
  if (caseDoc.execution !== undefined) { if (caseDoc.execution !== 'projection_contract') fail('unknown_execution', `${p}.execution`); required(caseDoc, ['projection_input', 'expected'], p); keysOnly(caseDoc.projection_input, new Set(['coverage', 'last_activity_event', 'elapsed_without_event_ms']), `${p}.projection_input`); validateExpected(caseDoc.expected, `${p}.expected`); return; }
  if (caseDoc.setup) validateSetup(caseDoc.setup, `${p}.setup`);
  if (caseDoc.request) { keysOnly(caseDoc.request, new Set(['method', 'path', 'credential_ref', 'body']), `${p}.request`); required(caseDoc.request, ['method', 'path', 'credential_ref'], `${p}.request`); validateExpected(caseDoc.expected, `${p}.expected`); return; }
  required(caseDoc, ['setup', 'steps'], p);
  if (caseDoc.core !== undefined) { keysOnly(caseDoc.core, new Set(['epoch', 'fencing_token', 'received_at_ms', 'maximum_future_skew_ms', 'retained_origin_floor', 'pairing_epoch', 'active_epoch', 'active_fencing_token']), `${p}.core`); for (const key of ['epoch', 'pairing_epoch', 'active_epoch']) if (key in caseDoc.core) string(caseDoc.core[key], `${p}.core.${key}`); for (const key of ['fencing_token', 'received_at_ms', 'maximum_future_skew_ms', 'retained_origin_floor', 'active_fencing_token']) if (key in caseDoc.core && (!Number.isSafeInteger(caseDoc.core[key]) || caseDoc.core[key] < 0)) fail('invalid_core_value', `${p}.core.${key}`); }
  if (caseDoc.outbox_event_template) { validateEvent(caseDoc.outbox_event_template, `${p}.outbox_event_template`); validateRecipe(caseDoc.event_id_recipe, `${p}.event_id_recipe`); }
  if (!Array.isArray(caseDoc.steps) || !caseDoc.steps.length) fail('invalid_steps', `${p}.steps`);
  if (caseDoc.outbox_event_template && caseDoc.steps.filter((step) => step.operation === 'materialize_and_queue_outbox_event').length !== 1) fail('missing_outbox_materialize', `${p}.steps`);
  const captured = new Set(); const capturedOutboxBytes = new Set(); for (let index = 0; index < caseDoc.steps.length; index += 1) validateStep(object(caseDoc.steps[index], `${p}.steps[${index}]`), caseDoc.name, `${p}.steps[${index}]`, captured, capturedOutboxBytes);
}

function requiredEventFields(event, p, allowMissingSignal, allowKnownInvalidField) {
  const fields = ['contract', 'schema_version', 'device_id', 'probe_id', 'origin_sequence', 'kind', 'ttl_ms', 'confidence', 'source', 'coverage', 'payload'];
  if (!allowMissingSignal) fields.push('signal_at_ms');
  required(event, fields, p);
  if (event.contract !== 'device.activity.v1') fail('invalid_contract', p);
  if (event.schema_version !== 1) fail('invalid_schema_version', p);
  for (const name of ['device_id', 'probe_id', 'kind', 'confidence', 'source']) string(event[name], `${p}.${name}`);
  for (const name of ['origin_sequence', 'ttl_ms']) { integer(event[name], `${p}.${name}`); if (event[name] < 0) fail('invalid_integer', `${p}.${name}`); }
  if (!allowMissingSignal) integer(event.signal_at_ms, `${p}.signal_at_ms`);
  if (!['high', 'medium', 'low'].includes(event.confidence)) fail('invalid_confidence', `${p}.confidence`);
  if (event.received_at_ms !== undefined && !allowKnownInvalidField) fail('invalid_event_field', `${p}.received_at_ms`);
  const coverage = event.coverage; required(coverage, ['mode', 'window_start_ms', 'window_end_ms'], `${p}.coverage`);
  if (!COVERAGE_MODES.has(coverage.mode)) fail('invalid_coverage', `${p}.coverage.mode`);
  integer(coverage.window_start_ms, `${p}.coverage.window_start_ms`); integer(coverage.window_end_ms, `${p}.coverage.window_end_ms`);
  if (coverage.mode === 'continuous') required(coverage, ['expected_report_interval_ms'], `${p}.coverage`);
}
function expectedVocabulary(expected, manifest, p) {
  if (!manifest.expected_outcome_vocabulary.includes(expected.outcome)) fail('unknown_outcome', `${p}.outcome`);
  if (expected.http?.error_code && !manifest.expected_http_error_code_vocabulary.includes(expected.http.error_code)) fail('unknown_http_error_code', `${p}.http.error_code`);
  if (expected.http?.result_status && !['accepted', 'duplicate'].includes(expected.http.result_status)) fail('unknown_http_result_status', `${p}.http.result_status`);
  if (expected.clock_health && !manifest.clock_health_vocabulary.includes(expected.clock_health)) fail('unknown_clock_health', `${p}.clock_health`);
  if (expected.sequence_diagnostics) for (const item of expected.sequence_diagnostics) if (!manifest.sequence_diagnostic_vocabulary.includes(item)) fail('unknown_sequence_diagnostic', `${p}.sequence_diagnostics`);
  if (expected.http) { const semantic = HTTP_SEMANTICS.get(expected.outcome); if (!semantic || expected.http.status !== semantic[0] || (expected.http.error_code && expected.http.error_code !== semantic[1]) || (expected.http.result_status && expected.http.result_status !== semantic[1])) fail('invalid_http_semantics', `${p}.http`); }
}
function captureNames(setup) { return new Set(Object.keys(setup.capture || {}).map((key) => `setup.capture.${key}`)); }
function requireCapture(ref, captures, p) { if (!captures.has(ref)) fail('unresolved_capture_ref', p); }
function semanticPayload(event, p) {
  const schema = PAYLOAD_SCHEMA.get(event.kind); if (!schema) return;
  keysOnly(event.payload, new Set(Object.keys(schema)), `${p}.payload`); required(event.payload, Object.keys(schema), `${p}.payload`);
  for (const [key, rule] of Object.entries(schema)) {
    const value = event.payload[key];
    if (rule === 'integer' && (!Number.isInteger(value) || value < 0)) fail('invalid_payload_type', `${p}.payload.${key}`);
    else if (rule === 'boolean' && typeof value !== 'boolean') fail('invalid_payload_type', `${p}.payload.${key}`);
    else if (rule === 'token' && (typeof value !== 'string' || !/^[a-z][a-z0-9_]{0,63}$/.test(value))) fail('invalid_payload_type', `${p}.payload.${key}`);
    else if (Array.isArray(rule) && !rule.includes(value)) fail('invalid_payload_value', `${p}.payload.${key}`);
  }
}
function semanticEvent(event, expected, p, pair) {
  const missingSignal = expected?.outcome === 'missing_required_field';
  requiredEventFields(event, p, missingSignal, expected?.outcome === 'unknown_field');
  const expectsUnknownKind = expected?.outcome === 'unsupported_kind' || expected?.http?.error_code === 'unsupported_kind';
  if (!ADR_KINDS.has(event.kind) && !expectsUnknownKind) fail('unknown_kind', `${p}.kind`);
  if (ADR_KINDS.has(event.kind) && expectsUnknownKind && expected?.outcome === 'unsupported_kind') fail('invalid_expected_kind_pair', `${p}.kind`);
  if (expected?.outcome === 'missing_required_field') {
    const field = expected.http?.details?.field; if (field !== 'signal_at_ms' || 'signal_at_ms' in event) fail('invalid_missing_field_witness', p);
  }
  if (expected?.outcome === 'unknown_field') {
    const field = expected.http?.details?.field; if (field !== 'received_at_ms' || !('received_at_ms' in event)) fail('invalid_unknown_field_witness', p);
  }
  if (pair) {
    const identityMismatch = event.device_id !== pair.device_id || event.probe_id !== pair.probe_id;
    if (expected?.outcome === 'origin_mismatch' ? !identityMismatch : identityMismatch || event.source !== pair.source) fail('pair_binding_mismatch', p);
    if (expected?.outcome !== 'origin_mismatch' && event.source !== pair.source) fail('pair_binding_mismatch', p);
    if (expected?.outcome !== 'origin_mismatch') {
    if (event.coverage.mode !== pair.coverage_mode) fail('coverage_registration_mismatch', `${p}.coverage.mode`);
    if (event.coverage.expected_report_interval_ms !== undefined && event.coverage.expected_report_interval_ms !== pair.expected_report_interval_ms) fail('coverage_registration_mismatch', `${p}.coverage.expected_report_interval_ms`);
    if (event.coverage.mode === 'continuous' && event.coverage.expected_report_interval_ms !== pair.expected_report_interval_ms) fail('coverage_registration_mismatch', `${p}.coverage.expected_report_interval_ms`);
    if (ADR_KINDS.has(event.kind) && !pair.allowed_kinds.includes(event.kind) && !expectsUnknownKind) fail('pair_kind_mismatch', `${p}.kind`);
    } else if (ADR_KINDS.has(event.kind) && !pair.allowed_kinds.includes(event.kind)) fail('pair_kind_mismatch', `${p}.kind`);
  }
  if (ADR_KINDS.has(event.kind)) semanticPayload(event, p);
}
function semanticOperation(step, caseDoc, manifest, state, index, p) {
  const op = step.operation; const expected = step.expected;
  assertExpectedSlot(caseDoc.name, index, expected, `${p}.expected`);
  if (expected) expectedVocabulary(expected, manifest, `${p}.expected`);
  const operationFields = {
    submit_events: new Set(['operation', 'expected', 'event_template', 'event_templates', 'event_id_recipe', 'wire_event_id_override', 'payload_materialization', 'materialized_event_ref', 'capture_materialized_event_as', 'capture_receipt_as', 'credential_ref', 'credential_generation']),
    materialize_and_queue_outbox_event: new Set(['operation', 'event_template', 'event_templates', 'event_id_recipe', 'capture_materialized_event_as', 'capture_outbox_bytes_as']),
    rotate_probe_credential: new Set(['operation', 'principal_ref', 'expected']), delete_probe: new Set(['operation', 'principal_ref', 'expected']),
    pair_new_lineage: new Set(['operation', 'ref', 'replacement_pair', 'capture', 'expected']), resolve_deleted_lineage_outbox: new Set(['operation', 'materialized_event_ref', 'outbox_bytes_ref', 'expected']),
    advance_retention_past_event_detail: new Set(['operation', 'retained_origin_floor']), revoke_probe: new Set(['operation', 'principal_ref', 'revoked_at_ms', 'expected']),
    advance_core_authority: new Set(['operation', 'from_epoch', 'to_epoch', 'fencing_token']),
  };
  for (const key of Object.keys(step)) if (!operationFields[op].has(key)) fail('forbidden_operation_field', `${p}.${key}`);
  const forbid = (names) => { for (const name of names) if (name in step) fail('forbidden_operation_field', `${p}.${name}`); };
  if (op === 'submit_events') {
    required(step, ['expected'], p);
    let events;
    if (step.materialized_event_ref) {
      forbid(['event_template', 'event_templates', 'event_id_recipe', 'wire_event_id_override', 'capture_materialized_event_as', 'credential_generation', 'credential_ref', 'capture_receipt_as', 'payload_materialization']);
      if (!state.events.has(step.materialized_event_ref)) fail('missing_materialized_ref', `${p}.materialized_event_ref`);
      const prior = state.eventFacts.get(step.materialized_event_ref);
      if (state.revokedAtMs !== undefined && (expected.outcome !== 'credential_revoked' || state.revokedAtMs <= prior.signal_at_ms)) fail('invalid_revocation_replay_witness', p);
      if (state.retainedOriginFloor !== undefined && (expected.outcome !== 'event_retained_out' || prior.origin_sequence > state.retainedOriginFloor || expected.receipt_must_not_be_guessed !== true)) fail('invalid_retained_replay_witness', p);
    }
    else {
      events = step.event_template ? [step.event_template] : step.event_templates;
      if (!events) fail('missing_required_field', `${p}.event_template`);
      const credentialPair = step.credential_ref === 'setup.capture.probe_token_ref' ? 'primary' : (step.credential_ref || 'primary');
      const pair = state.pairs.get(credentialPair); if (!pair) fail('invalid_principal_ref', `${p}.credential_ref`);
      if (step.credential_generation !== undefined && step.credential_generation !== state.credentialGenerations.get(credentialPair)) fail('invalid_credential_generation_witness', `${p}.credential_generation`);
      for (let n = 0; n < events.length; n += 1) semanticEvent(events[n], expected, `${p}.event[${n}]`, pair);
      const override = step.wire_event_id_override;
      if (OVERRIDE_MODE_BY_CASE.has(caseDoc.name)) { if (!override || override.mode !== OVERRIDE_MODE_BY_CASE.get(caseDoc.name)) fail('required_wire_override', p); forbid(['event_id_recipe']); requireCapture(override.prefix_ref, state.captures, `${p}.wire_event_id_override.prefix_ref`); }
      else { if (override) fail('wire_override_not_allowlisted', `${p}.wire_event_id_override`); required(step, ['event_id_recipe'], p); requireCapture(step.event_id_recipe.prefix_ref, state.captures, `${p}.event_id_recipe.prefix_ref`); }
      if (step.capture_materialized_event_as) { state.events.add(step.capture_materialized_event_as); state.eventFacts.set(step.capture_materialized_event_as, events[0]); }
    }
    if (step.capture_receipt_as) state.receipts.add(step.capture_receipt_as);
    if (step.payload_materialization) {
      const limit = caseDoc.limits?.maximum_payload_bytes;
      const materialization = step.payload_materialization;
      if (caseDoc.name !== 'oversized_payload' || !limit || events.length !== 1 || expected.outcome !== 'payload_too_large' || materialization.target_encoded_payload_bytes !== limit + 1 || materialization.target_encoded_payload_bytes <= Buffer.byteLength(JSON.stringify(events[0].payload), 'utf8')) fail('invalid_payload_materialization_witness', `${p}.payload_materialization`);
    }
    if (expected.receipt_ref && !state.receipts.has(expected.receipt_ref)) fail('missing_receipt_ref', `${p}.expected.receipt_ref`);
    return;
  }
  if (op === 'materialize_and_queue_outbox_event') {
    forbid(['expected', 'wire_event_id_override', 'materialized_event_ref']);
    if (caseDoc.outbox_event_template && (step.event_template || step.event_templates || step.event_id_recipe)) fail('outbox_shadow_binding', p);
    const event = step.event_template || caseDoc.outbox_event_template; const recipe = step.event_id_recipe || caseDoc.event_id_recipe;
    if (!event || !recipe) fail('missing_outbox_binding', p); semanticEvent(event, { outcome: 'accepted' }, `${p}.event_template`, state.pairs.get('primary')); requireCapture(recipe.prefix_ref, state.captures, `${p}.event_id_recipe.prefix_ref`);
    if (!caseDoc.outbox_event_template) required(step, ['capture_materialized_event_as'], p);
    if (caseDoc.name === 'deleted_lineage_outbox_not_rebound' && step.capture_outbox_bytes_as !== 'deleted_lineage_outbox_bytes') fail('invalid_outbox_bytes_capture', `${p}.capture_outbox_bytes_as`);
    if (caseDoc.name !== 'deleted_lineage_outbox_not_rebound' && step.capture_outbox_bytes_as !== undefined) fail('invalid_outbox_bytes_capture', `${p}.capture_outbox_bytes_as`);
    if (step.capture_materialized_event_as) { state.events.add(step.capture_materialized_event_as); state.eventFacts.set(step.capture_materialized_event_as, event); }
    if (step.capture_outbox_bytes_as) state.outboxBytes.add(step.capture_outbox_bytes_as);
    return;
  }
  const requiredByOperation = {
    rotate_probe_credential: ['principal_ref', 'expected'], delete_probe: ['principal_ref', 'expected'], pair_new_lineage: ['ref', 'expected'],
    resolve_deleted_lineage_outbox: ['expected'], advance_retention_past_event_detail: ['retained_origin_floor'], revoke_probe: ['principal_ref', 'revoked_at_ms', 'expected'],
    advance_core_authority: ['from_epoch', 'to_epoch', 'fencing_token'],
  };
  required(step, requiredByOperation[op] || [], p);
  if (['rotate_probe_credential', 'delete_probe', 'revoke_probe'].includes(op) && step.principal_ref !== 'primary') fail('invalid_principal_ref', `${p}.principal_ref`);
  if (op === 'rotate_probe_credential') {
    if (expected.event_id_prefix_ref !== 'setup.capture.event_id_prefix') fail('invalid_rotation_witness', `${p}.expected.event_id_prefix_ref`);
    state.credentialGenerations.set('primary', state.credentialGenerations.get('primary') + 1);
  }
  if (op === 'advance_retention_past_event_detail') {
    if (!Number.isSafeInteger(step.retained_origin_floor) || step.retained_origin_floor < 0 || caseDoc.name !== 'retained_out_retry' || step.retained_origin_floor !== state.eventFacts.get('accepted_event')?.origin_sequence) fail('invalid_retained_floor_witness', `${p}.retained_origin_floor`);
    state.retainedOriginFloor = step.retained_origin_floor;
  }
  if (op === 'revoke_probe') {
    if (!Number.isSafeInteger(step.revoked_at_ms) || step.revoked_at_ms <= state.eventFacts.get('accepted_event')?.signal_at_ms || caseDoc.name !== 'revoked_replay') fail('invalid_revocation_witness', `${p}.revoked_at_ms`);
    state.revokedAtMs = step.revoked_at_ms;
  }
  if (op === 'advance_core_authority') {
    const core = caseDoc.core || {};
    if (caseDoc.name !== 'stale_epoch_or_fencing' || step.from_epoch !== core.pairing_epoch || step.to_epoch !== core.active_epoch || step.from_epoch === step.to_epoch || step.fencing_token !== core.active_fencing_token) fail('invalid_authority_witness', p);
  }
  if (op === 'pair_new_lineage') {
    const primary = state.pairs.get('primary'); const replacement = step.replacement_pair;
    if (caseDoc.name !== 'deleted_lineage_outbox_not_rebound' || !replacement || replacement.ref !== step.ref || replacement.device_id !== primary.device_id || replacement.probe_id === primary.probe_id || !Array.isArray(replacement.capabilities) || !step.capture || expected.event_id_prefix_must_differ_from !== 'setup.capture.event_id_prefix') fail('invalid_replacement_lineage_witness', p);
    state.pairs.set(replacement.ref, replacement);
    state.captures.add('replacement.capture.replacement_event_id_prefix');
    state.captures.add('replacement.capture.replacement_probe_token_ref');
  }
  if (op === 'resolve_deleted_lineage_outbox') {
    if (caseDoc.name !== 'deleted_lineage_outbox_not_rebound' || step.materialized_event_ref !== 'deleted_lineage_outbox_event' || step.outbox_bytes_ref !== 'deleted_lineage_outbox_bytes' || !state.events.has(step.materialized_event_ref) || !state.outboxBytes.has(step.outbox_bytes_ref) || expected.action !== 'discard_without_rebinding' || expected.must_not_submit_with_replacement_prefix !== true || expected.old_outbox_bytes_rejected !== true || expected.local_outbox_discarded !== true || !state.pairs.has('replacement')) fail('invalid_deleted_outbox_witness', p);
  }
}
function semanticCase(caseDoc, manifest, p) {
  const canonical = CANONICAL_CASES.get(caseDoc.name); if (!canonical) fail('unknown_canonical_case', `${p}.name`);
  const steps = caseDoc.steps || [];
  const shape = caseDoc.execution ? `execution:${caseDoc.execution}` : caseDoc.request ? 'request' : steps.map((step) => step.operation).join(',');
  const result = (expected) => expected ? `${expected.outcome}/${expected.http?.status || ''}/${expected.http?.result_status || expected.http?.error_code || ''}` : '';
  const results = caseDoc.expected ? result(caseDoc.expected) : steps.map((step) => result(step.expected)).join('|');
  if (shape !== canonical[0] || results !== canonical[1]) fail('canonical_case_shape_mismatch', p);
  if (caseDoc.execution) {
    assertExpectedSlot(caseDoc.name, 'case', caseDoc.expected, `${p}.expected`);
    expectedVocabulary(caseDoc.expected, manifest, `${p}.expected`);
    const input = caseDoc.projection_input;
    if (input.coverage?.mode !== 'unknown' || input.last_activity_event !== null || input.elapsed_without_event_ms !== 28800000 || caseDoc.expected.outcome !== 'unknown_no_coverage' || caseDoc.expected.projection_state !== 'unknown' || !Array.isArray(caseDoc.expected.forbidden_states) || !['quiet_observed', 'resting_candidate', 'sleep_candidate'].every((state) => caseDoc.expected.forbidden_states.includes(state))) fail('invalid_no_coverage_witness', p);
    return;
  }
  if (caseDoc.request) {
    assertExpectedSlot(caseDoc.name, 'case', caseDoc.expected, `${p}.expected`);
    expectedVocabulary(caseDoc.expected, manifest, `${p}.expected`); if (caseDoc.request.credential_ref !== 'primary') fail('invalid_principal_ref', `${p}.request.credential_ref`);
    const requestRules = {
      wrong_scope: { outcome: 'forbidden_scope', method: 'GET', path: '/v1/core/activity/summary', body: false },
      write_token_chat_read_denied: { outcome: 'chat_read_forbidden', method: 'GET', path: '/v1/core/changes', body: false },
      probe_admin_escalation: { outcome: 'admin_escalation_forbidden', method: 'POST', path: '/v1/core/activity/readers/pair', body: true },
    };
    const rule = requestRules[caseDoc.name]; if (!rule || caseDoc.expected.outcome !== rule.outcome || caseDoc.request.method !== rule.method || caseDoc.request.path !== rule.path || (caseDoc.request.body !== undefined) !== rule.body) fail('invalid_request_witness', `${p}.request`);
    if (caseDoc.name === 'wrong_scope') { if (caseDoc.expected.acceptance_mutated !== false) fail('invalid_request_witness', p); }
    if (caseDoc.name === 'write_token_chat_read_denied') { if (caseDoc.expected.resource_lookup_performed !== false || caseDoc.expected.private_data_returned !== false) fail('invalid_request_witness', p); }
    if (caseDoc.name === 'probe_admin_escalation') { const body = caseDoc.request.body; keysOnly(body, new Set(['installation_id', 'display_name', 'capabilities']), `${p}.request.body`); required(body, ['installation_id', 'display_name', 'capabilities'], `${p}.request.body`); if (typeof body.installation_id !== 'string' || typeof body.display_name !== 'string' || !Array.isArray(body.capabilities) || body.capabilities.length || caseDoc.expected.server_assigned_scopes_unchanged !== true || caseDoc.expected.acceptance_mutated !== false) fail('invalid_request_witness', p); }
    return;
  }
  const pairs = new Map(); for (const pair of (caseDoc.setup.pair_probe ? [caseDoc.setup.pair_probe] : caseDoc.setup.pair_probes)) pairs.set(pair.ref, pair);
  const state = { captures: captureNames(caseDoc.setup), events: new Set(), eventFacts: new Map(), outboxBytes: new Set(), receipts: new Set(), pairs, credentialGenerations: new Map([['primary', 1]]) };
  if (!state.captures.has('setup.capture.event_id_prefix')) fail('missing_setup_capture', `${p}.setup.capture`);
  const core = caseDoc.core || {};
  if ('maximum_future_skew_ms' in core) {
    const first = caseDoc.steps[0]?.event_template;
    if (caseDoc.name !== 'future_clock' || !first || core.maximum_future_skew_ms !== caseDoc.setup.pair_probe.expected_report_interval_ms || first.signal_at_ms - core.received_at_ms <= core.maximum_future_skew_ms || caseDoc.steps[0].expected.clock_health !== 'future_skew') fail('invalid_future_clock_witness', `${p}.core`);
  }
  if ('received_at_ms' in core && caseDoc.name === 'ttl_expired') {
    const event = caseDoc.steps[0]?.event_template;
    if (!event || core.received_at_ms - event.signal_at_ms <= event.ttl_ms || caseDoc.steps[0].expected.outcome !== 'ttl_expired') fail('invalid_ttl_witness', `${p}.core.received_at_ms`);
  }
  if ('retained_origin_floor' in core) {
    const events = caseDoc.steps.filter((step) => step.event_template).map((step) => step.event_template);
    if (caseDoc.name !== 'sequence_gap_then_out_of_order_fill' || !events.length || events.some((event) => event.origin_sequence <= core.retained_origin_floor)) fail('invalid_retained_floor_witness', `${p}.core.retained_origin_floor`);
  }
  if ('epoch' in core || 'fencing_token' in core) {
    const event = caseDoc.steps[0]?.event_template;
    if (!event || !('epoch' in core) || !('fencing_token' in core) || !('received_at_ms' in core) || core.received_at_ms < event.signal_at_ms || core.received_at_ms > event.signal_at_ms + event.ttl_ms) fail('invalid_core_receipt_witness', `${p}.core`);
  }
  let outboxSteps = 0;
  caseDoc.steps.forEach((step, index) => { if (step.operation === 'materialize_and_queue_outbox_event') outboxSteps += 1; semanticOperation(step, caseDoc, manifest, state, index, `${p}.steps[${index}]`); });
  if (caseDoc.outbox_event_template && outboxSteps !== 1) fail('missing_outbox_materialize', `${p}.steps`);
  if (!caseDoc.outbox_event_template && outboxSteps && caseDoc.name !== 'sequence_gap_then_out_of_order_fill') fail('unexpected_outbox_materialize', `${p}.steps`);
  if (caseDoc.name === 'sequence_gap_then_out_of_order_fill') {
    const made = caseDoc.steps.slice(0, 3).map((step) => step.capture_materialized_event_as).join(',');
    const delivered = caseDoc.steps.slice(3).map((step) => step.materialized_event_ref).join(',');
    const templates = caseDoc.steps.slice(0, 3).map((step) => step.event_template);
    if (made !== 'sequence_1,sequence_2,sequence_3' || delivered !== 'sequence_1,sequence_3,sequence_2' || !caseDoc.steps.slice(0, 3).every((step) => step.operation === 'materialize_and_queue_outbox_event' && step.event_template && step.event_id_recipe && step.event_id_recipe.origin_sequence_field === 'origin_sequence') || !caseDoc.steps.slice(3).every((step) => step.operation === 'submit_events' && step.materialized_event_ref && !step.event_template && !step.event_id_recipe) || templates.map((event) => event.origin_sequence).join(',') !== '1,2,3' || templates.map((event) => event.kind).join(',') !== 'session.unlocked,session.unlocked,session.locked' || !(templates[0].signal_at_ms < templates[1].signal_at_ms && templates[1].signal_at_ms < templates[2].signal_at_ms) || !(templates[0].coverage.window_end_ms === templates[1].coverage.window_start_ms && templates[1].coverage.window_end_ms === templates[2].coverage.window_start_ms)) fail('invalid_sequence_gap_recovery', `${p}.steps`);
    const [one, three, two] = caseDoc.steps.slice(3).map((step) => step.expected);
    if (one.outcome !== 'accepted' || three.outcome !== 'accepted_with_conservative_unknown' || two.outcome !== 'accepted' || three.projection_state !== 'unknown' || three.concrete_projection_advanced !== false || three.sequence_coverage?.missing?.join(',') !== '2' || three.sequence_diagnostics?.join(',') !== 'sequence_coverage_gap' || two.projection_recomputed_through_origin_sequence !== 3 || two.concrete_projection_restored !== true || two.device_projection_state !== 'locked') fail('invalid_sequence_gap_recovery', `${p}.steps`);
  }
}

export function validateFixtureSet(manifest, documents) {
  keysOnly(manifest, new Set(['fixture_set', 'status', 'fixture_format_version', 'proposal_revision', 'cases_are_isolated', 'contract', 'schema_version', 'dynamic_event_id_contract', 'origin_sequence_contract', 'fixture_operation_contract', 'execution_defaults', 'privacy_lint_contract', 'expected_outcome_vocabulary', 'clock_health_vocabulary', 'sequence_diagnostic_vocabulary', 'expected_http_error_code_vocabulary', 'files', 'mechanical_checks']), '$manifest');
  required(manifest, ['files', 'privacy_lint_contract'], '$manifest');
  if (manifest.fixture_set !== 'device.activity.v1-proposed' || manifest.status !== 'proposed_executable_templates' || manifest.fixture_format_version !== 2 || manifest.contract !== 'device.activity.v1' || manifest.schema_version !== 1 || manifest.proposal_revision !== 5) fail('fixture_manifest_identity_mismatch', '$manifest');
  const operations = manifest.fixture_operation_contract;
  if (!operations || operations.materialize_and_queue_outbox_event !== 'materialize event_template with event_id_recipe in fixture step order without HTTP delivery, capture it by capture_materialized_event_as, and capture the exact queued bytes by capture_outbox_bytes_as' || operations.pair_new_lineage !== 'owner HTTP pairing creates the explicit replacement_pair as a new lineage, captures its issued event_id_prefix and probe token references, and never lets a runner synthesize either identity' || operations.resolve_deleted_lineage_outbox !== 'after deletion and replacement pairing, resolve the exact queued bytes selected by outbox_bytes_ref, reject and discard them locally, and never rewrite them with a replacement prefix or replacement identity') fail('fixture_operation_contract_mismatch', '$manifest.fixture_operation_contract');
  const credentialKeys = manifest.privacy_lint_contract.allowed_credential_shaped_keys;
  if (!credentialKeys || credentialKeys.replacement_probe_token_ref?.value_kind !== 'symbolic_pairing_response_reference' || credentialKeys.replacement_probe_token_ref?.allowed_values?.length !== 1 || credentialKeys.replacement_probe_token_ref.allowed_values[0] !== 'replacement_pair.response.probe_token') fail('privacy_contract_mismatch', '$manifest.privacy_lint_contract');
  const symbolicValues = manifest.privacy_lint_contract.allowed_symbolic_pairing_response_values;
  const expectedSymbolicValues = ['pair_probe.response.event_id_prefix', 'pair_probe.response.probe_token', 'pair_probes.primary.response.event_id_prefix', 'pair_probes.sibling.response.event_id_prefix', 'replacement_pair.response.event_id_prefix', 'replacement_pair.response.probe_token'];
  if (!Array.isArray(symbolicValues) || symbolicValues.length !== expectedSymbolicValues.length || symbolicValues.some((value, index) => value !== expectedSymbolicValues[index])) fail('privacy_contract_mismatch', '$manifest.privacy_lint_contract.allowed_symbolic_pairing_response_values');
  if (!Array.isArray(manifest.files) || manifest.files.length !== 4) fail('invalid_manifest_files', '$manifest.files');
  const listedFiles = manifest.files.map((item) => item.file); if (new Set(listedFiles).size !== 4 || CASE_FILES.some((file) => !listedFiles.includes(file))) fail('manifest_file_mismatch');
  const manifestNames = manifest.files.flatMap((entry) => entry.cases || []);
  if (manifestNames.length !== CANONICAL_CASES.size || new Set(manifestNames).size !== CANONICAL_CASES.size || manifestNames.some((name) => !CANONICAL_CASES.has(name))) fail('canonical_manifest_case_mismatch');
  const caseNames = new Set(); let count = 0;
  for (const entry of manifest.files) {
    keysOnly(entry, new Set(['file', 'cases']), '$manifest.files'); if (!Array.isArray(entry.cases)) fail('invalid_manifest_cases');
    const document = documents.get(entry.file); if (!document) fail('missing_case_file');
    keysOnly(document, new Set(['contract', 'schema_version', 'fixture_format_version', 'proposal_revision', 'cases']), '$case_file'); required(document, ['cases'], '$case_file');
    if (document.contract !== manifest.contract || document.schema_version !== manifest.schema_version || document.fixture_format_version !== manifest.fixture_format_version || document.proposal_revision !== manifest.proposal_revision) fail('fixture_revision_mismatch', '$case_file');
    if (!Array.isArray(document.cases) || document.cases.length !== entry.cases.length) fail('case_count_mismatch');
    for (const caseDoc of document.cases) { validateCase(caseDoc, '$case'); semanticCase(caseDoc, manifest, '$case'); if (!entry.cases.includes(caseDoc.name) || caseNames.has(caseDoc.name)) fail('manifest_case_mismatch'); caseNames.add(caseDoc.name); count += 1; }
  }
  if (count !== 26) fail('case_count_mismatch');
  return { fileCount: 5, caseCount: count };
}

export function loadFixtureSet(fixturesDir) {
  const readJson = (name) => JSON.parse(fs.readFileSync(path.join(fixturesDir, name), 'utf8'));
  const manifest = readJson('manifest.json');
  const documents = new Map(); for (const name of CASE_FILES) { const doc = readJson(name); lintRawPrivacy(doc, '$case'); documents.set(name, doc); }
  return { manifest, documents, ...validateFixtureSet(manifest, documents) };
}

export function materializeEvent(template, recipe, captures, override) {
  const prefix = captures.get((override || recipe).prefix_ref); if (typeof prefix !== 'string') fail('missing_capture');
  const event = structuredClone(template);
  if (override?.mode === 'captured_prefix_with_literal_suffix') event.event_id = `${prefix}.${override.literal_suffix}`;
  else if (override?.mode === 'different_pairing_prefix_with_canonical_sequence') event.event_id = `${prefix}.${event[override.origin_sequence_field]}`;
  else event.event_id = `${prefix}.${event[recipe.origin_sequence_field]}`;
  return event;
}

/** Pure outbox transition: appends the exact materialized bytes, with no transport. */
export function materializeAndQueue(outbox, event) {
  const bytes = Buffer.from(JSON.stringify(event), 'utf8');
  return [...outbox, { event, bytes }];
}
