import assert from 'node:assert/strict';
import { copyFileSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { loadFixtureSet } from './activity_fixture_contract.mjs';
import { assertRunnerCaseExpectedShape, DEFAULT_FIXTURE_DIRECTORY, runFixtureHttp } from './activity_fixture_http_runner.mjs';
import { installStaleRuntimeEpoch } from './activity_fixture_http_runner.test_support.mjs';

const set = loadFixtureSet(DEFAULT_FIXTURE_DIRECTORY);
const fileNames = ['manifest.json', ...set.manifest.files.map((entry) => entry.file)];
const allCases = [...set.documents.values()].flatMap((doc) => doc.cases);
let baseline;
function report() { return baseline ||= runFixtureHttp(); }
function liveTempDirectories() {
  return readdirSync(tmpdir()).filter((name) => name.startsWith(`mda1-http-case-${process.pid}-`)).sort();
}
async function mutatedFixtures(file, mutate, run) {
  const directory = mkdtempSync(path.join(tmpdir(), 'mda1-http-input-'));
  try {
    for (const name of fileNames) copyFileSync(path.join(DEFAULT_FIXTURE_DIRECTORY, name), path.join(directory, name));
    const target = path.join(directory, file);
    const doc = JSON.parse(readFileSync(target, 'utf8'));
    mutate(doc);
    writeFileSync(target, JSON.stringify(doc));
    return await run(directory);
  } finally { rmSync(directory, { recursive: true, force: true }); }
}
async function rejectsBeforeNetwork(file, mutate) {
  const before = liveTempDirectories(); let hooks = 0;
  await mutatedFixtures(file, mutate, async (fixturesDir) => {
    const result = await runFixtureHttp({ fixturesDir, onLifecycle() { hooks += 1; } });
    assert.deepEqual(result, { status: 'rejected_before_http', files: 0, cases: [], requests: 0, check: 'static_or_runner_contract' });
  });
  assert.equal(hooks, 0);
  assert.deepEqual(liveTempDirectories(), before);
}

function guardRejects(c) {
  assert.throws(() => assertRunnerCaseExpectedShape(c), (error) =>
    error.message === 'fixture_http_check_failed' && error.check === 'runner_expected_shape');
}

test('independent runner guard matches every R5 expectation slot and rejects every root and nested member deletion', () => {
  let slots = 0; let emptySlots = 0; let roots = 0; let httpMembers = 0; let sequenceMembers = 0; let detailMembers = 0;
  for (const original of allCases) {
    assert.doesNotThrow(() => assertRunnerCaseExpectedShape(original));
    const containers = original.steps || [original];
    for (let index = 0; index < containers.length; index += 1) {
      const slot = containers[index];
      const changed = (mutate) => {
        const copy = structuredClone(original); mutate((copy.steps || [copy])[index]); guardRejects(copy);
      };
      if (!Object.hasOwn(slot, 'expected')) {
        emptySlots += 1;
        changed((target) => { target.expected = { outcome: 'accepted', http: { status: 200 } }; });
        continue;
      }
      slots += 1;
      changed((target) => { delete target.expected; });
      for (const key of Object.keys(slot.expected)) {
        roots += 1; changed((target) => { delete target.expected[key]; });
      }
      for (const field of ['http', 'sequence_coverage']) {
        for (const key of Object.keys(slot.expected[field] || {})) {
          if (field === 'http') httpMembers += 1; else sequenceMembers += 1;
          changed((target) => { delete target.expected[field][key]; });
        }
      }
      for (const key of Object.keys(slot.expected.http?.details || {})) {
        detailMembers += 1; changed((target) => { delete target.expected.http.details[key]; });
      }
    }
  }
  assert.deepEqual({ slots, emptySlots, roots, httpMembers, sequenceMembers, detailMembers },
    { slots: 37, emptySlots: 6, roots: 129, httpMembers: 68, sequenceMembers: 9, detailMembers: 2 });
});

test('pure runner guard rejects side-effect witness transplantation, nested injection and moved expectation locations without static validation', () => {
  const foreign = {
    server_assigned_scopes_unchanged: true, allowed_payload_fields: ['quality'], resource_lookup_performed: false,
    private_data_returned: false, idempotency_lookup_after_revocation: false, acceptance_mutated: false,
    receipt_ref: 'synthetic_receipt', action: 'discard_without_rebinding', must_not_submit_with_replacement_prefix: true,
    old_outbox_bytes_rejected: true, local_outbox_discarded: true, accepted_items: 0,
    rejected_item_reason: 'unsupported_kind', event_id_prefix_ref: 'setup.capture.event_id_prefix',
  };
  for (const [key, value] of Object.entries(foreign)) {
    const c = structuredClone(allCases.find((item) => item.name === 'valid_event'));
    c.steps[0].expected[key] = value; guardRejects(c);
  }
  const details = structuredClone(allCases.find((c) => c.name === 'valid_event'));
  details.steps[0].expected.http.details = { field: 'received_at_ms' }; guardRejects(details);
  const nested = structuredClone(allCases.find((c) => c.name === 'sequence_gap_then_out_of_order_fill'));
  nested.steps[3].expected.sequence_coverage.acceptance_mutated = false; guardRejects(nested);
  const moved = structuredClone(allCases.find((c) => c.name === 'valid_event'));
  moved.expected = moved.steps[0].expected; delete moved.steps[0].expected; guardRejects(moved);
  const top = structuredClone(allCases.find((c) => c.name === 'wrong_scope'));
  top.steps = [{ expected: top.expected }]; guardRejects(top);
  const objectArray = structuredClone(allCases.find((c) => c.name === 'heart_rate_quality_without_inference'));
  objectArray.steps[0].expected.forbidden_states.push({ unused: true }); guardRejects(objectArray);
  const wrongArrayType = structuredClone(allCases.find((c) => c.name === 'sequence_gap_then_out_of_order_fill'));
  wrongArrayType.steps[4].expected.sequence_coverage.missing = ['2']; guardRejects(wrongArrayType);
  const wrongScalarType = structuredClone(allCases.find((c) => c.name === 'valid_event'));
  wrongScalarType.steps[0].expected.receipt_time_owner = []; guardRejects(wrongScalarType);
  const duplicateStrings = structuredClone(allCases.find((c) => c.name === 'heart_rate_quality_without_inference'));
  duplicateStrings.steps[0].expected.forbidden_states.push(duplicateStrings.steps[0].expected.forbidden_states[0]); guardRejects(duplicateStrings);
  const duplicateNumbers = structuredClone(allCases.find((c) => c.name === 'sequence_gap_then_out_of_order_fill'));
  duplicateNumbers.steps[4].expected.sequence_coverage.missing = [2, 2]; guardRejects(duplicateNumbers);
});

test('independent scalar types reject systematic wrong-type substitutions at every actual leaf in all 37 slots', () => {
  const badValues = {
    string: [42, false, null, {}, { unused: true }, [], ['synthetic'], ''],
    boolean: [0, 1, 'false', '', null, {}, [], [false]],
    number: ['1', false, null, {}, [], [1], -1, 1.5, Number.MAX_SAFE_INTEGER + 1, NaN, Infinity],
  };
  const counts = { slots: 0, string: 0, boolean: 0, number: 0, arrays: 0, mutations: 0 };
  function visit(value, at, emit) {
    for (const [key, child] of Object.entries(value)) {
      const leaf = [...at, key];
      if (Array.isArray(child)) counts.arrays += 1;
      else if (child && typeof child === 'object') visit(child, leaf, emit);
      else emit(leaf, child);
    }
  }
  for (const original of allCases) {
    for (const [index, slot] of (original.steps || [original]).entries()) {
      if (!slot.expected) continue;
      counts.slots += 1;
      visit(slot.expected, [], (at, originalValue) => {
        const type = typeof originalValue;
        assert.ok(Object.hasOwn(badValues, type)); counts[type] += 1;
        for (const invalid of badValues[type]) {
          const copy = structuredClone(original);
          let parent = (copy.steps || [copy])[index].expected;
          for (const key of at.slice(0, -1)) parent = parent[key];
          parent[at.at(-1)] = invalid;
          guardRejects(copy); counts.mutations += 1;
        }
      });
    }
  }
  assert.deepEqual(counts, { slots: 37, string: 88, boolean: 27, number: 43, arrays: 10, mutations: 1393 });
});

test('R5 and runner preflight reject transplanted side effects and nested fields before HTTP or lifecycle hooks', async () => {
  await rejectsBeforeNetwork('valid_and_idempotency.json', (doc) => { doc.cases[0].steps[0].expected.server_assigned_scopes_unchanged = true; });
  await rejectsBeforeNetwork('valid_and_idempotency.json', (doc) => { doc.cases[0].steps[0].expected.http.details = { field: 'received_at_ms' }; });
  await rejectsBeforeNetwork('validation_and_clock.json', (doc) => {
    doc.cases.find((c) => c.name === 'sequence_gap_then_out_of_order_fill').steps[3].expected.sequence_coverage.acceptance_mutated = false;
  });
  await rejectsBeforeNetwork('valid_and_idempotency.json', (doc) => {
    doc.cases.find((c) => c.name === 'heart_rate_quality_without_inference').steps[0].expected.forbidden_states.push({ unused: true });
  });
  await rejectsBeforeNetwork('validation_and_clock.json', (doc) => {
    doc.cases.find((c) => c.name === 'sequence_gap_then_out_of_order_fill').steps[4].expected.sequence_coverage.missing = [2, 2];
  });
  await rejectsBeforeNetwork('valid_and_idempotency.json', (doc) => { doc.cases[0].steps[0].expected.receipt_time_owner = 42; });
  await rejectsBeforeNetwork('valid_and_idempotency.json', (doc) => { doc.cases[0].steps[0].expected.http.status = '200'; });
  await rejectsBeforeNetwork('valid_and_idempotency.json', (doc) => { doc.cases[3].steps[1].expected.acceptance_mutated = 'false'; });
  await rejectsBeforeNetwork('validation_and_clock.json', (doc) => {
    doc.cases.find((c) => c.name === 'sequence_gap_then_out_of_order_fill').steps[3].expected.sequence_coverage.highest_seen = null;
  });
});

test('all five fixture documents and 26 unique cases execute once on real loopback HTTP', async () => {
  const before = liveTempDirectories();
  const result = await report();
  assert.equal(result.status, 'passed_with_evidence_boundaries');
  assert.equal(result.files, 5); assert.equal(result.case_count, 26); assert.equal(result.passed, 26);
  assert.deepEqual(result.cases.map((c) => c.name), set.manifest.files.flatMap((entry) => entry.cases));
  assert.equal(new Set(result.cases.map((c) => c.name)).size, 26);
  assert.equal(result.requests, result.cases.reduce((sum, c) => sum + c.requests, 0));
  assert.equal(result.requests, 213);
  assert.deepEqual(result.cases.reduce((totals, c) => Object.fromEntries(
    Object.keys(totals).map((key) => [key, totals[key] + c[key]])),
  { submissions: 0, exact_retries: 0, steps: 0, expectations: 0, fields: 0 }),
  { submissions: 30, exact_retries: 4, steps: 43, expectations: 181, fields: 1057 });
  assert.deepEqual(result.cases.find((c) => c.name === 'deleted_lineage_outbox_not_rebound'), {
    name: 'deleted_lineage_outbox_not_rebound', status: 'passed', requests: 11, wire_checks: 11,
    submissions: 2, exact_retries: 1, steps: 4, expectations: 10, fields: 60,
  });
  for (const c of result.cases) {
    const fixture = [...set.documents.values()].flatMap((doc) => doc.cases).find((item) => item.name === c.name);
    assert.equal(c.steps, fixture.steps?.length || 1);
    assert.equal(c.wire_checks, c.requests); // protocol, loopback peer, literal incoming body
    assert.ok(c.requests >= 5); assert.ok(c.expectations > 0); assert.ok(c.fields > c.expectations);
  }
  assert.deepEqual(liveTempDirectories(), before);
});

test('report is deterministic despite fresh databases, pairing secrets, prefixes, ports and receipts', async () => {
  assert.deepEqual(await runFixtureHttp(), await report());
});

test('report and lifecycle publish only fixed case names, counters and evidence boundaries', async () => {
  const result = await report();
  assert.deepEqual(Object.keys(result).sort(), ['case_count', 'cases', 'evidence_boundaries', 'files', 'passed', 'requests', 'status']);
  for (const item of result.cases) {
    assert.deepEqual(Object.keys(item).sort(), ['exact_retries', 'expectations', 'fields', 'name', 'requests', 'status', 'steps', 'submissions', 'wire_checks']);
    for (const [key, value] of Object.entries(item)) if (!['name', 'status'].includes(key)) assert.equal(typeof value, 'number');
  }
  assert.ok(result.evidence_boundaries.includes('no_android_or_human_gate'));
  assert.ok(result.evidence_boundaries.includes('person_expectations_check_http_non_inference_only'));
  const serialized = JSON.stringify(result);
  assert.doesNotMatch(serialized, /Bearer |"(?:probe_token|reader_token|event_id_prefix|canonical_digest|pairing_code)"\s*:|https?:\/\/|[a-f0-9]{32,}/);
});

test('private keys, literal credentials and malicious field names are rejected before HTTP', async () => {
  for (const key of ['message_body', 'notification_body', 'window_title', 'app_name', 'keystroke', 'contact', 'private_content', 'authorization']) {
    await rejectsBeforeNetwork('valid_and_idempotency.json', (doc) => { doc.cases[0].steps[0].event_template.payload[key] = 'do-not-emit-this-synthetic-private-value'; });
  }
  for (const literal of ['Bearer do-not-emit', 'secret-do-not-emit', 'sk-do-not-emit', 'a'.repeat(48), 'https://synthetic.invalid/private']) {
    await rejectsBeforeNetwork('valid_and_idempotency.json', (doc) => { doc.cases[0].setup.pair_probe.display_name = literal; });
  }
});

test('missing, duplicate and unknown manifest cases cannot be skipped or executed as another case', async () => {
  await rejectsBeforeNetwork('manifest.json', (doc) => { doc.files[0].cases.pop(); });
  await rejectsBeforeNetwork('manifest.json', (doc) => { doc.files[0].cases[1] = doc.files[0].cases[0]; });
  await rejectsBeforeNetwork('valid_and_idempotency.json', (doc) => { doc.cases[0].name = 'synthetic-unknown'; });
});

test('runner rejects inert core, limit, nested expectation and metadata fields accepted by broad static shapes', async () => {
  await rejectsBeforeNetwork('valid_and_idempotency.json', (doc) => { doc.cases[1].core = { fencing_token: 18 }; });
  await rejectsBeforeNetwork('valid_and_idempotency.json', (doc) => { doc.cases[0].limits = { maximum_payload_bytes: 4096 }; });
  await rejectsBeforeNetwork('valid_and_idempotency.json', (doc) => { doc.cases[0].steps[0].expected.details = { ignored: true }; });
  await rejectsBeforeNetwork('validation_and_clock.json', (doc) => { doc.cases.find((c) => c.name === 'sequence_gap_then_out_of_order_fill').steps[3].expected.sequence_coverage.ignored = true; });
  await rejectsBeforeNetwork('manifest.json', (doc) => { doc.dynamic_event_id_contract.ignored = true; });
  await rejectsBeforeNetwork('manifest.json', (doc) => { doc.execution_defaults.protocol_header = 'X-Core-Protocol: 999'; });
});

test('an extra JSON document is rejected before a listener or database is created', async () => {
  await mutatedFixtures('manifest.json', () => {}, async (fixturesDir) => {
    writeFileSync(path.join(fixturesDir, 'unused.json'), '{}');
    let invoked = false;
    const result = await runFixtureHttp({ fixturesDir, onLifecycle() { invoked = true; } });
    assert.equal(result.status, 'rejected_before_http'); assert.equal(result.requests, 0); assert.equal(invoked, false);
  });
});

test('unused otherwise-valid receipt capture fails closed instead of inflating field consumption', async () => {
  await mutatedFixtures('valid_and_idempotency.json', (doc) => {
    doc.cases[0].steps[0].capture_receipt_as = 'unused_synthetic_receipt';
  }, async (fixturesDir) => {
    const result = await runFixtureHttp({ fixturesDir });
    // A stricter static contract may reject this even earlier.
    if (result.status === 'rejected_before_http') { assert.equal(result.requests, 0); return; }
    assert.equal(result.status, 'failed'); assert.equal(result.passed, 25);
    assert.equal(result.cases[0].check, 'unused_receipt_capture');
  });
});

test('wrong HTTP-visible expectation fails its case, while every other manifest case still executes', async () => {
  await mutatedFixtures('valid_and_idempotency.json', (doc) => {
    doc.cases[0].steps[0].expected.device_projection_state = 'locked';
  }, async (fixturesDir) => {
    const result = await runFixtureHttp({ fixturesDir });
    assert.equal(result.status, 'failed'); assert.equal(result.case_count, 26); assert.equal(result.passed, 25);
    assert.equal(result.cases[0].check, 'device_projection');
    assert.doesNotMatch(JSON.stringify(result), /receipt:|Bearer |"(?:event_id_prefix|actual|expected|stack)"\s*:/);
  });
});

test('startup and mid-case exceptions redact error text and clean every isolated database and listener', async () => {
  for (const fault of ['started', 'request']) {
    const before = liveTempDirectories();
    let started = 0;
    const result = await runFixtureHttp({ onLifecycle(event) {
      assert.ok(['started', 'request'].includes(event.phase));
      assert.ok(Object.keys(event).every((key) => ['phase', 'case', 'request'].includes(key)));
      if (event.phase === 'started') started += 1;
      if (event.phase === fault && (fault === 'started' || event.request === 3)) {
        throw new Error('Bearer hidden-token-secret / private_content_do_not_emit');
      }
    } });
    assert.equal(started, 26); assert.equal(result.case_count, 26); assert.equal(result.passed, 0);
    assert.ok(result.cases.every((c) => c.check === 'execution_error'));
    assert.doesNotMatch(JSON.stringify(result), /hidden-token|private_content|Bearer |stack/);
    assert.deepEqual(liveTempDirectories(), before);
  }
});

test('test-only stale epoch setup rejects listening servers and invalid epoch deltas', () => {
  assert.throws(() => installStaleRuntimeEpoch({ server: { listening: true } }, 1, 1), /invalid_stopped_epoch_setup/);
  assert.throws(() => installStaleRuntimeEpoch({ server: { listening: false } }, 1, 2), /invalid_stopped_epoch_setup/);
  const isolated = { server: { listening: false }, store: { activity: {} } };
  installStaleRuntimeEpoch(isolated, 1, 1);
  assert.equal(isolated.store.activity.authorityEpoch, 0);
});
