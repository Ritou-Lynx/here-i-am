import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { FixtureContractError, lintRawPrivacy, loadFixtureSet, materializeAndQueue, materializeEvent } from './activity_fixture_contract.mjs';

const fixtureDir = path.resolve('docs/development/activity/mda0/fixtures');
const names = ['valid_and_idempotency.json', 'validation_and_clock.json', 'coverage_scope_and_replay.json', 'limits_and_atomicity.json'];
function throwsCode(fn, code) { assert.throws(fn, (error) => error instanceof FixtureContractError && (error.code === code || error.code === 'canonical_case_shape_mismatch' || error.code === 'canonical_manifest_case_mismatch' || error.code === 'unknown_canonical_case')); }
function copiedFixtures(mutator) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mda1-fixture-'));
  for (const name of ['manifest.json', ...names]) fs.copyFileSync(path.join(fixtureDir, name), path.join(dir, name));
  mutator(dir);
  return dir;
}
function mutate(dir, name, change) { const file = path.join(dir, name); const json = JSON.parse(fs.readFileSync(file, 'utf8')); change(json); fs.writeFileSync(file, JSON.stringify(json)); }
function assertMutation(file, change, code) {
  const dir = copiedFixtures((temp) => mutate(temp, file, change));
  try { throwsCode(() => loadFixtureSet(dir), code); } finally { fs.rmSync(dir, { recursive: true, force: true }); }
}
function assertMultiMutation(change, code) {
  const dir = copiedFixtures(change);
  try { throwsCode(() => loadFixtureSet(dir), code); } finally { fs.rmSync(dir, { recursive: true, force: true }); }
}

test('loads exactly five JSON files and every manifest case exactly once', () => {
  const result = loadFixtureSet(fixtureDir);
  assert.deepEqual({ fileCount: result.fileCount, caseCount: result.caseCount }, { fileCount: 5, caseCount: 26 });
  const actual = [...result.documents.values()].flatMap((doc) => doc.cases.map((item) => item.name));
  assert.equal(new Set(actual).size, 26);
});

test('rejects a manifest case skip', () => {
  const dir = copiedFixtures((temp) => mutate(temp, 'manifest.json', (manifest) => { manifest.files[0].cases.pop(); }));
  throwsCode(() => loadFixtureSet(dir), 'case_count_mismatch');
  fs.rmSync(dir, { recursive: true, force: true });
});

test('rejects unknown and known-but-unused fixture fields', () => {
  for (const [file, change] of [
    ['validation_and_clock.json', (doc) => { doc.cases[0].steps[0].unexpected = true; }],
    ['valid_and_idempotency.json', (doc) => { doc.cases[0].setup.pair_probe.unused_note = 'synthetic'; }],
  ]) { const dir = copiedFixtures((temp) => mutate(temp, file, change)); throwsCode(() => loadFixtureSet(dir), 'unknown_field'); fs.rmSync(dir, { recursive: true, force: true }); }
});

test('privacy lint fails closed before symbolic resolution without exposing captured values', () => {
  const examples = [
    { value: { x: 'Bearer test-value' }, code: 'privacy_literal' },
    { value: { x: 'https://example.invalid/a' }, code: 'privacy_literal' },
    { value: { message_body: 'private text' }, code: 'privacy_private_key' },
    { value: { access_token: 'not-allowlisted' }, code: 'privacy_credential_reference' },
    { value: { replacement_event_id_prefix: 'replacement.capture.replacement_event_id_prefix' }, code: 'privacy_symbolic_reference' },
  ];
  for (const example of examples) { try { lintRawPrivacy(example.value); assert.fail('expected failure'); } catch (error) { assert.equal(error.code, example.code); assert.ok(!error.message.includes('test-value')); assert.ok(!error.message.includes('example.invalid')); assert.ok(!error.message.includes('private text')); } }
  assert.doesNotThrow(() => lintRawPrivacy({ replacement_probe_token_ref: 'replacement_pair.response.probe_token' }));
});

test('rejects missing, cyclic-shaped, and cross-case symbolic refs', () => {
  for (const [ref, code] of [['setup.capture.missing', 'privacy_symbolic_reference'], ['setup.capture.event_id_prefix.loop', 'privacy_symbolic_reference'], ['other_case.capture.event_id_prefix', 'invalid_symbolic_ref']]) {
    const dir = copiedFixtures((temp) => mutate(temp, 'valid_and_idempotency.json', (doc) => { doc.cases[0].steps[0].event_id_recipe.prefix_ref = ref; }));
    throwsCode(() => loadFixtureSet(dir), code); fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('materialization preserves exact bytes in the pure outbox and supports all three override cases', () => {
  const event = { origin_sequence: 7, kind: 'synthetic' };
  const captures = new Map([['setup.capture.event_id_prefix', 'prefixA'], ['setup.capture.sibling_event_id_prefix', 'prefixB']]);
  const recipe = { prefix_ref: 'setup.capture.event_id_prefix', origin_sequence_field: 'origin_sequence' };
  assert.equal(materializeEvent(event, recipe, captures).event_id, 'prefixA.7');
  assert.equal(materializeEvent(event, recipe, captures, { mode: 'captured_prefix_with_literal_suffix', prefix_ref: 'setup.capture.event_id_prefix', literal_suffix: '01' }).event_id, 'prefixA.01');
  assert.equal(materializeEvent(event, recipe, captures, { mode: 'different_pairing_prefix_with_canonical_sequence', prefix_ref: 'setup.capture.sibling_event_id_prefix', origin_sequence_field: 'origin_sequence' }).event_id, 'prefixB.7');
  const queued = materializeAndQueue([], materializeEvent(event, recipe, captures));
  assert.equal(queued.length, 1); assert.deepEqual(queued[0].bytes, Buffer.from(JSON.stringify(queued[0].event), 'utf8'));
});

test('rejects a normal explicit event id, a skipped operation, and an unallowlisted override', () => {
  const dir = copiedFixtures((temp) => mutate(temp, 'valid_and_idempotency.json', (doc) => { doc.cases[0].steps[0].event_template.event_id = 'not-allowed'; }));
  throwsCode(() => loadFixtureSet(dir), 'normal_event_has_event_id'); fs.rmSync(dir, { recursive: true, force: true });
  const missing = copiedFixtures((temp) => mutate(temp, 'validation_and_clock.json', (doc) => { doc.cases[0].steps[0].operation = 'skip'; }));
  throwsCode(() => loadFixtureSet(missing), 'unknown_operation'); fs.rmSync(missing, { recursive: true, force: true });
  const override = copiedFixtures((temp) => mutate(temp, 'valid_and_idempotency.json', (doc) => { doc.cases[0].steps[0].wire_event_id_override = { mode: 'captured_prefix_with_literal_suffix', prefix_ref: 'setup.capture.event_id_prefix', literal_suffix: '1' }; delete doc.cases[0].steps[0].event_id_recipe; }));
  throwsCode(() => loadFixtureSet(override), 'wire_override_not_allowlisted'); fs.rmSync(override, { recursive: true, force: true });
});

test('locks the eight P1 bad fixture mutations with temp-only cleanup', () => {
  assertMutation('valid_and_idempotency.json', (doc) => { doc.cases[0].steps[0].event_template.kind = 'not.in.adr'; }, 'unknown_kind');
  assertMutation('valid_and_idempotency.json', (doc) => { delete doc.cases[0].steps[0].event_template.contract; }, 'missing_required_field');
  assertMutation('valid_and_idempotency.json', (doc) => { doc.cases[0].steps[0].expected.outcome = 'unlisted'; }, 'unknown_outcome');
  assertMutation('valid_and_idempotency.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'credential_rotation_preserves_lineage'); delete item.steps[0].principal_ref; }, 'missing_required_field');
  assertMutation('valid_and_idempotency.json', (doc) => { delete doc.cases[0].setup.capture.event_id_prefix; }, 'missing_setup_capture');
  assertMutation('valid_and_idempotency.json', (doc) => { doc.cases[1].steps[1].materialized_event_ref = 'invented_event'; }, 'missing_materialized_ref');
  assertMutation('valid_and_idempotency.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'noncanonical_event_id'); delete item.steps[0].wire_event_id_override; item.steps[0].event_id_recipe = { mode: 'pairing_prefix_dot_canonical_sequence', prefix_ref: 'setup.capture.event_id_prefix', origin_sequence_field: 'origin_sequence' }; }, 'required_wire_override');
  assertMutation('valid_and_idempotency.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'deleted_lineage_outbox_not_rebound'); item.steps = item.steps.filter((step) => step.operation !== 'materialize_and_queue_outbox_event'); }, 'missing_outbox_materialize');
});

test('rejects operation, coverage, vocabulary, and receipt-reference drift', () => {
  assertMutation('validation_and_clock.json', (doc) => { doc.cases[0].steps[0].event_template.coverage.mode = 'future_mode'; }, 'invalid_coverage');
  assertMutation('validation_and_clock.json', (doc) => { doc.cases[0].steps[0].expected.http.error_code = 'unlisted_error'; }, 'unknown_http_error_code');
  assertMutation('valid_and_idempotency.json', (doc) => { doc.cases[1].steps[1].expected.receipt_ref = 'invented_receipt'; }, 'missing_receipt_ref');
  assertMutation('valid_and_idempotency.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'credential_rotation_preserves_lineage'); item.steps[0].principal_ref = 'sibling'; }, 'invalid_principal_ref');
});

test('locks ADR payload, pair registration, capture type, outbox, and sequence bindings', () => {
  assertMutation('valid_and_idempotency.json', (doc) => { doc.cases[0].steps[0].event_template.payload.extra = 'drift'; }, 'unknown_field');
  assertMutation('valid_and_idempotency.json', (doc) => { doc.cases[0].steps[0].event_template.source = 'android_tasker'; }, 'pair_binding_mismatch');
  assertMutation('valid_and_idempotency.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'wrong_event_id_prefix'); item.setup.capture.sibling_event_id_prefix = 'pair_probes.primary.response.event_id_prefix'; }, 'invalid_capture_type');
  assertMutation('valid_and_idempotency.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'deleted_lineage_outbox_not_rebound'); item.steps[0].event_template = structuredClone(item.outbox_event_template); item.steps[0].event_id_recipe = structuredClone(item.event_id_recipe); }, 'outbox_shadow_binding');
  assertMutation('validation_and_clock.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'sequence_gap_then_out_of_order_fill'); item.steps[0].operation = 'submit_events'; }, 'missing_required_field');
});

test('keeps negative witnesses, sequence semantics, and HTTP mappings self-proving', () => {
  assertMutation('coverage_scope_and_replay.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'cross_device_impersonation'); item.steps[0].event_template.device_id = item.setup.pair_probe.device_id; item.steps[0].event_template.probe_id = item.setup.pair_probe.probe_id; }, 'pair_binding_mismatch');
  assertMutation('validation_and_clock.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'missing_required_field'); item.steps[0].event_template.signal_at_ms = 1760000100000; }, 'invalid_missing_field_witness');
  assertMutation('validation_and_clock.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'unknown_field'); delete item.steps[0].event_template.received_at_ms; }, 'invalid_unknown_field_witness');
  assertMutation('validation_and_clock.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'sequence_gap_then_out_of_order_fill'); item.steps[0].event_template.origin_sequence = 7; }, 'invalid_sequence_gap_recovery');
  assertMutation('validation_and_clock.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'sequence_gap_then_out_of_order_fill'); item.steps[0].event_template.kind = 'session.locked'; }, 'invalid_sequence_gap_recovery');
  assertMutation('valid_and_idempotency.json', (doc) => { doc.cases[0].steps[0].expected.http.status = 599; }, 'invalid_http_semantics');
});

test('locks projection and request witnesses without claiming HTTP execution', () => {
  assertMutation('coverage_scope_and_replay.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'no_coverage_silence'); item.projection_input.coverage.mode = 'continuous'; }, 'invalid_no_coverage_witness');
  assertMutation('coverage_scope_and_replay.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'no_coverage_silence'); item.projection_input.last_activity_event = {}; }, 'invalid_no_coverage_witness');
  assertMutation('coverage_scope_and_replay.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'wrong_scope'); item.request.method = 'POST'; }, 'invalid_request_witness');
  assertMutation('coverage_scope_and_replay.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'write_token_chat_read_denied'); item.request.path = '/v1/core/activity/summary'; }, 'invalid_request_witness');
  assertMutation('coverage_scope_and_replay.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'probe_admin_escalation'); item.request.body.extra = true; }, 'unknown_field');
  assertMutation('coverage_scope_and_replay.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'probe_admin_escalation'); item.expected.server_assigned_scopes_unchanged = false; }, 'invalid_request_witness');
});

test('anchors each request witness to its fixed case name rather than outcome', () => {
  assertMutation('coverage_scope_and_replay.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'wrong_scope'); item.expected.outcome = 'chat_read_forbidden'; item.expected.http = { status: 403, error_code: 'chat_read_forbidden' }; item.request.path = '/v1/core/changes'; item.expected.resource_lookup_performed = false; item.expected.private_data_returned = false; delete item.expected.acceptance_mutated; }, 'invalid_request_witness');
  assertMutation('coverage_scope_and_replay.json', (doc) => { const wrong = doc.cases.find((entry) => entry.name === 'wrong_scope'); const chat = doc.cases.find((entry) => entry.name === 'write_token_chat_read_denied'); [wrong.name, chat.name] = [chat.name, wrong.name]; }, 'invalid_request_witness');
  assertMutation('coverage_scope_and_replay.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'probe_admin_escalation'); item.name = 'unrecognized_request_case'; }, 'invalid_request_witness');
});

test('freezes canonical case identities, high-level runner shapes, and declared results', () => {
  assertMultiMutation((dir) => { mutate(dir, 'valid_and_idempotency.json', (doc) => { doc.cases[0].name = 'renamed_valid'; }); mutate(dir, 'manifest.json', (manifest) => { manifest.files[0].cases[0] = 'renamed_valid'; }); }, 'canonical_manifest_case_mismatch');
  assertMultiMutation((dir) => { mutate(dir, 'coverage_scope_and_replay.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'no_coverage_silence'); item.name = 'renamed_no_coverage'; }); mutate(dir, 'manifest.json', (manifest) => { manifest.files[2].cases[0] = 'renamed_no_coverage'; }); }, 'canonical_manifest_case_mismatch');
  assertMutation('valid_and_idempotency.json', (doc) => { doc.cases[0].steps[0].expected = { outcome: 'duplicate', http: { status: 200, result_status: 'duplicate' } }; }, 'canonical_case_shape_mismatch');
  assertMutation('valid_and_idempotency.json', (doc) => { const valid = doc.cases.find((entry) => entry.name === 'valid_event'); const duplicate = doc.cases.find((entry) => entry.name === 'duplicate_same_payload'); valid.steps = structuredClone(duplicate.steps); }, 'canonical_case_shape_mismatch');
  assertMutation('validation_and_clock.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'clock_regression'); item.steps.reverse(); }, 'canonical_case_shape_mismatch');
});

test('consumes declared Core, limit, credential, retention, revocation, and replacement-lineage witnesses', () => {
  assertMutation('validation_and_clock.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'future_clock'); item.core.maximum_future_skew_ms = 1; }, 'invalid_future_clock_witness');
  assertMutation('limits_and_atomicity.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'oversized_payload'); item.steps[0].payload_materialization.target_encoded_payload_bytes = 2; }, 'invalid_payload_materialization_witness');
  assertMutation('limits_and_atomicity.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'stale_epoch_or_fencing'); item.steps[0].fencing_token = 999; }, 'invalid_authority_witness');
  assertMutation('valid_and_idempotency.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'credential_rotation_preserves_lineage'); item.steps[1].credential_generation = 99; }, 'invalid_credential_generation_witness');
  assertMutation('coverage_scope_and_replay.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'revoked_replay'); item.steps[1].revoked_at_ms = item.steps[0].event_template.signal_at_ms; }, 'invalid_revocation_witness');
  assertMutation('valid_and_idempotency.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'retained_out_retry'); item.steps[1].retained_origin_floor = 0; }, 'invalid_retained_floor_witness');
  assertMutation('valid_and_idempotency.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'deleted_lineage_outbox_not_rebound'); delete item.steps[2].replacement_pair; }, 'invalid_replacement_lineage_witness');
  assertMutation('valid_and_idempotency.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'deleted_lineage_outbox_not_rebound'); item.steps[2].replacement_pair.probe_id = item.setup.pair_probe.probe_id; }, 'invalid_replacement_lineage_witness');
  assertMutation('valid_and_idempotency.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'deleted_lineage_outbox_not_rebound'); item.steps[2].ref = 'runner_synthesized'; }, 'invalid_replacement_lineage_witness');
  assertMutation('valid_and_idempotency.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'deleted_lineage_outbox_not_rebound'); item.steps[2].expected.event_id_prefix_must_differ_from = 'replacement.capture.replacement_event_id_prefix'; }, 'privacy_symbolic_reference');
  assertMutation('validation_and_clock.json', (doc) => { doc.proposal_revision = 2; }, 'fixture_revision_mismatch');
  assertMutation('manifest.json', (doc) => { doc.status = 'proposed_executable_templates_no_http_runner_yet'; }, 'fixture_manifest_identity_mismatch');
  assertMutation('manifest.json', (doc) => { doc.fixture_operation_contract.pair_new_lineage = 'runner may choose a replacement'; }, 'fixture_operation_contract_mismatch');
  assertMutation('manifest.json', (doc) => { doc.privacy_lint_contract.allowed_symbolic_pairing_response_values[0] = 'Bearer test-value'; }, 'privacy_contract_mismatch');
});

test('materialized submissions cannot add delivery credentials, receipts, or payload work', () => {
  const mutateRetry = (change) => assertMutation('valid_and_idempotency.json', (doc) => { change(doc.cases.find((entry) => entry.name === 'duplicate_same_payload').steps[1]); }, 'forbidden_operation_field');
  mutateRetry((step) => { step.credential_generation = 1; });
  mutateRetry((step) => { step.credential_ref = 'primary'; });
  mutateRetry((step) => { step.capture_receipt_as = 'second_receipt'; });
  mutateRetry((step) => { step.payload_materialization = { mode: 'append_synthetic_padding', field: 'padding', target_encoded_payload_bytes: 2 }; });
});

test('deleted-lineage resolve consumes the exact queued-bytes capture', () => {
  assertMutation('valid_and_idempotency.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'deleted_lineage_outbox_not_rebound'); delete item.steps[0].capture_outbox_bytes_as; }, 'missing_outbox_bytes_ref');
  assertMutation('valid_and_idempotency.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'deleted_lineage_outbox_not_rebound'); delete item.steps[3].outbox_bytes_ref; }, 'invalid_deleted_outbox_witness');
  assertMutation('valid_and_idempotency.json', (doc) => { const item = doc.cases.find((entry) => entry.name === 'deleted_lineage_outbox_not_rebound'); item.steps[3].outbox_bytes_ref = 'reconstructed_bytes'; }, 'missing_outbox_bytes_ref');
});

test('R5 freezes every canonical expected slot and rejects cross-case witness transplantation', () => {
  for (const file of names) {
    const source = JSON.parse(fs.readFileSync(path.join(fixtureDir, file), 'utf8'));
    for (const sourceCase of source.cases) {
      const slots = sourceCase.steps ? sourceCase.steps.map((_, index) => index) : ['case'];
      for (const slot of slots) {
        const dir = copiedFixtures((temp) => mutate(temp, file, (doc) => {
          const item = doc.cases.find((entry) => entry.name === sourceCase.name);
          const target = slot === 'case' ? item : item.steps[slot];
          if (target.expected) {
            const key = Object.keys(target.expected).find((name) => name !== 'outcome') || 'outcome';
            delete target.expected[key];
          } else {
            target.expected = { outcome: 'accepted' };
          }
        }));
        try { assert.throws(() => loadFixtureSet(dir), (error) => error instanceof FixtureContractError); } finally { fs.rmSync(dir, { recursive: true, force: true }); }
      }
    }
  }
  const transplant = (file, caseName, slot, field, value) => assertMutation(file, (doc) => {
    const item = doc.cases.find((entry) => entry.name === caseName);
    const expected = slot === 'case' ? item.expected : item.steps[slot].expected;
    expected[field] = value;
  }, 'expected_slot_keys_mismatch');
  transplant('valid_and_idempotency.json', 'valid_event', 0, 'allowed_payload_fields', []);
  transplant('coverage_scope_and_replay.json', 'wrong_scope', 'case', 'server_assigned_scopes_unchanged', true);
  transplant('coverage_scope_and_replay.json', 'wrong_scope', 'case', 'resource_lookup_performed', false);
  transplant('valid_and_idempotency.json', 'valid_event', 0, 'idempotency_lookup_after_revocation', false);
  transplant('valid_and_idempotency.json', 'valid_event', 0, 'receipt_ref', 'accepted_receipt');
  transplant('validation_and_clock.json', 'illegal_kind', 0, 'person_projection_state', 'unknown');
  transplant('validation_and_clock.json', 'illegal_kind', 0, 'projection_state', 'unknown');
  transplant('validation_and_clock.json', 'illegal_kind', 0, 'forbidden_states', []);
  transplant('validation_and_clock.json', 'illegal_kind', 0, 'clock_health', 'healthy');
  transplant('validation_and_clock.json', 'illegal_kind', 0, 'sequence_coverage', { highest_seen: 1, contiguous_through: 1, missing: [] });
  transplant('valid_and_idempotency.json', 'valid_event', 0, 'old_outbox_bytes_rejected', true);
  transplant('valid_and_idempotency.json', 'valid_event', 0, 'receipt_must_not_be_guessed', true);
  transplant('valid_and_idempotency.json', 'valid_event', 0, 'accepted_items', 0);
  transplant('valid_and_idempotency.json', 'valid_event', 0, 'acceptance_mutated', false);
  assertMutation('valid_and_idempotency.json', (doc) => { const expected = doc.cases.find((entry) => entry.name === 'valid_event').steps[0].expected; expected.http.error_code = 'accepted'; }, 'expected_http_keys_mismatch');
  assertMutation('valid_and_idempotency.json', (doc) => { const expected = doc.cases.find((entry) => entry.name === 'valid_event').steps[0].expected; delete expected.http.result_status; }, 'expected_http_keys_mismatch');
  assertMutation('validation_and_clock.json', (doc) => { const expected = doc.cases.find((entry) => entry.name === 'sequence_gap_then_out_of_order_fill').steps[3].expected; expected.sequence_coverage.extra = true; }, 'expected_sequence_coverage_keys_mismatch');
  assertMutation('validation_and_clock.json', (doc) => { const expected = doc.cases.find((entry) => entry.name === 'sequence_gap_then_out_of_order_fill').steps[3].expected; delete expected.sequence_coverage.missing; }, 'invalid_expected_missing_array');
});

test('R5.1 validates every expected leaf type before semantic witness checks', () => {
  const documents = names.map((file) => JSON.parse(fs.readFileSync(path.join(fixtureDir, file), 'utf8')));
  const expectedCount = documents.flatMap((doc) => doc.cases).reduce((count, item) => count + (item.steps ? item.steps.filter((step) => step.expected).length : 1), 0);
  assert.equal(expectedCount, 37);
  assert.equal(loadFixtureSet(fixtureDir).caseCount, 26);
  assertMutation('valid_and_idempotency.json', (doc) => { doc.cases.find((item) => item.name === 'valid_event').steps[0].expected.person_projection_state = {}; }, 'invalid_expected_string');
  assertMutation('valid_and_idempotency.json', (doc) => { doc.cases.find((item) => item.name === 'duplicate_different_payload').steps[1].expected.acceptance_mutated = 'false'; }, 'invalid_expected_boolean');
  assertMutation('valid_and_idempotency.json', (doc) => { doc.cases.find((item) => item.name === 'retained_out_retry').steps[2].expected.receipt_must_not_be_guessed = 'true'; }, 'invalid_expected_boolean');
  assertMutation('limits_and_atomicity.json', (doc) => { doc.cases.find((item) => item.name === 'batch_atomic_rejection').steps[0].expected.accepted_items = []; }, 'invalid_expected_counter');
  assertMutation('validation_and_clock.json', (doc) => { doc.cases.find((item) => item.name === 'sequence_gap_then_out_of_order_fill').steps[5].expected.projection_recomputed_through_origin_sequence = -1; }, 'invalid_expected_counter');
  assertMutation('valid_and_idempotency.json', (doc) => { doc.cases.find((item) => item.name === 'valid_event').steps[0].expected.http.status = -1; }, 'invalid_expected_counter');
  assertMutation('valid_and_idempotency.json', (doc) => { doc.cases.find((item) => item.name === 'valid_event').steps[0].expected.http.result_status = []; }, 'invalid_expected_string');
  assertMutation('validation_and_clock.json', (doc) => { doc.cases.find((item) => item.name === 'illegal_kind').steps[0].expected.http.error_code = {}; }, 'invalid_expected_string');
  assertMutation('validation_and_clock.json', (doc) => { doc.cases.find((item) => item.name === 'missing_required_field').steps[0].expected.http.details.field = []; }, 'invalid_expected_string');
  assertMutation('validation_and_clock.json', (doc) => { doc.cases.find((item) => item.name === 'future_clock').steps[0].expected.forbidden_states.push({ unused: true }); }, 'invalid_expected_string_array');
  assertMutation('valid_and_idempotency.json', (doc) => { doc.cases.find((item) => item.name === 'heart_rate_quality_without_inference').steps[0].expected.allowed_payload_fields.push({ unused: true }); }, 'invalid_expected_string_array');
  assertMutation('validation_and_clock.json', (doc) => { doc.cases.find((item) => item.name === 'sequence_gap_then_out_of_order_fill').steps[4].expected.sequence_diagnostics.push({ unused: true }); }, 'invalid_expected_string_array');
  assertMutation('validation_and_clock.json', (doc) => { doc.cases.find((item) => item.name === 'sequence_gap_then_out_of_order_fill').steps[3].expected.sequence_coverage.missing.push({ unused: true }); }, 'invalid_expected_missing_array');
  assertMutation('validation_and_clock.json', (doc) => { const coverage = doc.cases.find((item) => item.name === 'sequence_gap_then_out_of_order_fill').steps[3].expected.sequence_coverage; coverage.highest_seen = {}; }, 'invalid_expected_counter');
  assertMutation('validation_and_clock.json', (doc) => { const coverage = doc.cases.find((item) => item.name === 'sequence_gap_then_out_of_order_fill').steps[3].expected.sequence_coverage; coverage.contiguous_through = []; }, 'invalid_expected_counter');
});
