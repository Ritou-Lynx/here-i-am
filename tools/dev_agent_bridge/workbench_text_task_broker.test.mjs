import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { once } from 'node:events';
import test from 'node:test';
import { createTextTaskBroker, authorizedTextTaskBody, TEXT_TASK_MODEL } from './workbench_text_task_broker.mjs';
import { exchangeTextOnly, TextGateTransportError } from './workbench_text_gate_transport.mjs';

const auth = { authorization: 'Bearer SYNTHETIC_AUTH', 'chatgpt-account-id': 'synthetic_account' };
const task = 'Write one bounded synthetic sentence.';
const safeSse = Buffer.from('event: response.completed\ndata: {"type":"response.completed","response":{"id":"r","status":"completed","output":[]}}\n\n');
const body = (text = task) => ({
  model: TEXT_TASK_MODEL,
  input: [{ type: 'message', role: 'user', content: [{ type: 'input_text', text }] }],
  stream: true,
});

async function broker(t, options = {}) {
  const value = createTextTaskBroker({ verifyPeer: async () => true, exchange: async () => safeSse, peerTimeoutMs: 100, exchangeTimeoutMs: 500, ...options });
  const base = await value.listen();
  t.after(() => value.close());
  return { value, url: `${base}/responses` };
}

async function post(url, request = body(), signal) {
  return fetch(url, { method: 'POST', headers: { ...auth, 'content-type': 'application/json' }, body: JSON.stringify(request), signal });
}

test('authorized body rebuilds only the host goal and rejects wrong goal, server history, and hidden executable input', () => {
  const withEarlierContext = body();
  withEarlierContext.input.unshift(
    { type: 'message', role: 'developer', content: [{ type: 'input_text', text: 'discard me' }] },
    { type: 'message', role: 'user', content: [{ type: 'input_text', text: 'old user text' }] },
  );
  const rebuilt = authorizedTextTaskBody(withEarlierContext, task);
  assert.deepEqual(rebuilt.input, [{ type: 'message', role: 'user', content: [{ type: 'input_text', text: task }] }]);
  assert.deepEqual(rebuilt.tools, []);
  assert.throws(() => authorizedTextTaskBody(body('wrong goal'), task), /text_task_exchange_rejected/);
  assert.throws(() => authorizedTextTaskBody({ ...body(), previous_response_id: 'old' }, task));
  const hidden = body();
  hidden.input.push({ type: 'function_call', name: 'exec', arguments: '{}' });
  assert.throws(() => authorizedTextTaskBody(hidden, task));
});

test('unadmitted socket never reaches HTTP parsing, auth handling, or exchange', async (t) => {
  let exchanges = 0;
  const { value, url } = await broker(t, { verifyPeer: async () => false, exchange: async () => { exchanges++; return safeSse; } });
  value.arm(task);
  await assert.rejects(post(url));
  await value.close();
  assert.deepEqual(value.snapshot(), {
    admitted_connections: 0, rejected_connections: 1, parsed_requests: 0, metadata_rejections: 0,
    rejected_requests: 0, upstream_attempts: 0, response_released: false, drained: true,
    exchange_failure_code: null, exchange_timeout_phase: null, response_rejection_phase: null,
    response_gate_code: null, response_event_kind: null, response_event_type_class: null, response_event_phase: null,
    response_event_header_relation: null, response_event_payload_shape: null, response_event_control_kind: null,
    response_schema_location: null,
  });
  assert.equal(exchanges, 0);
});

test('one arm permits one concurrent forward only and reconstructs the outgoing body', async (t) => {
  let exchanges = 0;
  let outgoing;
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  const { value, url } = await broker(t, { exchange: async request => { exchanges++; outgoing = request; await gate; return safeSse; } });
  value.arm(task);
  const first = post(url);
  while (exchanges === 0) await new Promise(resolve => setTimeout(resolve, 1));
  const second = await post(url);
  assert.equal(second.status, 422);
  release();
  assert.equal((await first).status, 200);
  assert.equal(exchanges, 1);
  assert.deepEqual(outgoing.input, [{ type: 'message', role: 'user', content: [{ type: 'input_text', text: task }] }]);
  assert.deepEqual(outgoing.tools, []);
  assert.equal(value.snapshot().upstream_attempts, 1);
});

test('peer change after body parsing rejects before exchange and releases no output', async (t) => {
  let verifies = 0;
  let exchanges = 0;
  const { value, url } = await broker(t, {
    verifyPeer: async () => (++verifies < 3),
    exchange: async () => { exchanges++; return safeSse; },
  });
  value.arm(task);
  const response = await post(url);
  assert.equal(response.status, 422);
  assert.equal(exchanges, 0);
  assert.equal(value.snapshot().response_released, false);
  assert.equal(value.snapshot().exchange_failure_code, null);
  assert.equal(value.snapshot().exchange_timeout_phase, null);
});

test('non-Buffer exchange output is rejected without releasing a response body', async (t) => {
  const { value, url } = await broker(t, { exchange: async () => ({ safeSse }) });
  value.arm(task);
  const response = await post(url);
  assert.equal(response.status, 422);
  assert.equal(await response.text(), '{"error":{"type":"text_task_exchange_rejected"}}');
  assert.equal(value.snapshot().upstream_attempts, 1);
  assert.equal(value.snapshot().response_released, false);
  assert.equal(value.snapshot().exchange_failure_code, null);
});

test('explicit revoke clears the arm before HTTP parsing or exchange', async (t) => {
  let exchanges = 0;
  const { value, url } = await broker(t, { exchange: async () => { exchanges++; return safeSse; } });
  value.arm(task);
  value.revoke();
  await assert.rejects(post(url));
  await value.close();
  const state = value.snapshot();
  assert.equal(state.parsed_requests, 0);
  assert.equal(state.upstream_attempts, 0);
  assert.equal(state.response_released, false);
  assert.equal(state.drained, true);
  assert.equal(exchanges, 0);
});

test('actual loopback transport response-gate rejection does not release output', async (t) => {
  const upstream = createServer((_req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.end('event: arbitrary_provider_event\ndata: {"type":"arbitrary_provider_event"}\n\n');
  });
  upstream.listen(0, '127.0.0.1');
  await once(upstream, 'listening');
  t.after(async () => { upstream.closeAllConnections(); upstream.close(); await once(upstream, 'close'); });
  const upstreamUrl = `http://127.0.0.1:${upstream.address().port}/v1/responses`;
  const { value, url } = await broker(t, {
    exchange: (outgoing, options) => exchangeTextOnly(outgoing, { ...options, upstreamUrl }),
  });
  value.arm(task);
  const response = await post(url);
  assert.equal(response.status, 422);
  assert.equal(value.snapshot().upstream_attempts, 1);
  assert.equal(value.snapshot().response_released, false);
  assert.equal(value.snapshot().exchange_failure_code, 'response_rejected');
  assert.equal(value.snapshot().exchange_timeout_phase, null);
  assert.equal(value.snapshot().response_rejection_phase, 'after_eof');
  assert.equal(value.snapshot().response_gate_code, 'unsupported_event');
  assert.equal(value.snapshot().response_event_kind, 'other');
  assert.equal(value.snapshot().response_event_type_class, 'other_namespace');
  assert.equal(value.snapshot().response_event_phase, 'before_created');
  assert.equal(value.snapshot().response_event_header_relation, 'equals_payload_type');
  assert.equal(value.snapshot().response_event_payload_shape, 'type_only');
  assert.equal(value.snapshot().response_event_control_kind, 'other');
  assert.equal(value.snapshot().response_schema_location, null);
  assert.equal(value.snapshot().rejected_requests, 1);
  assert.doesNotMatch(JSON.stringify(value.snapshot()), /arbitrary_provider_event/);
});

test('client disconnect aborts exchange and close waits for bounded drain', async (t) => {
  let entered;
  const enteredPromise = new Promise(resolve => { entered = resolve; });
  let aborted = false;
  const { value, url } = await broker(t, { exchange: async (_request, { signal }) => {
    entered();
    await new Promise(resolve => signal.addEventListener('abort', () => { aborted = true; resolve(); }, { once: true }));
    throw new Error('aborted');
  } });
  value.arm(task);
  const abort = new AbortController();
  const pending = post(url, body(), abort.signal).catch(() => null);
  await enteredPromise;
  abort.abort();
  await pending;
  await value.close();
  assert.equal(aborted, true);
  assert.equal(value.snapshot().drained, true);
  assert.equal(value.snapshot().response_released, false);
});

test('verification timeout closes an unparsed socket and bounded close drains it', async (t) => {
  const { value, url } = await broker(t, { verifyPeer: async () => new Promise(() => {}), peerTimeoutMs: 20 });
  value.arm(task);
  await assert.rejects(post(url));
  await value.close();
  const state = value.snapshot();
  assert.equal(state.admitted_connections, 0);
  assert.equal(state.parsed_requests, 0);
  assert.equal(state.upstream_attempts, 0);
  assert.equal(state.drained, true);
});

test('only reserved exchange transport codes survive; payloads and retry remain rejected', async t => {
  const allowed = ['timeout', 'aborted', 'http_status', 'unsupported_content_type',
    'missing_body', 'request_rejected', 'response_rejected', 'transport_failed'];
  const cases = allowed.map(code => ({ error: new TextGateTransportError(code), expected: code }));
  for (const code of ['PRIVATE_CODE', 'invalid_target', 'invalid_headers', 'diagnostic_input_limit',
    null, 500, { toString() { throw new Error('PRIVATE_COERCION'); } }]) {
    const error = new TextGateTransportError('transport_failed'); error.code = code;
    cases.push({ error, expected: null });
  }
  cases.push({ error: Object.assign(new Error('PRIVATE_MESSAGE'), { code: 'timeout', name: 'TextGateTransportError' }), expected: null });
  for (const { error, expected } of cases) {
    Object.assign(error, { message: 'PRIVATE_MESSAGE', cause: 'PRIVATE_CAUSE', httpStatus: 599,
      gateCode: 'PRIVATE_GATE', schemaLocation: 'PRIVATE_LOCATION', responseMetadata: { body: 'PRIVATE_BODY' },
      responseDiagnostics: { headers: 'PRIVATE_HEADERS', authorization: 'PRIVATE_AUTH' } });
    let exchanges = 0;
    const { value, url } = await broker(t, { exchange: async () => { exchanges++; throw error; } });
    value.arm(task);
    const response = await post(url);
    assert.equal(response.status, 422);
    assert.equal(await response.text(), '{"error":{"type":"text_task_exchange_rejected"}}');
    const first = value.snapshot();
    assert.equal(first.exchange_failure_code, expected);
    assert.equal(first.upstream_attempts, 1); assert.equal(first.rejected_requests, 1);
    assert.equal(first.response_released, false);
    assert.doesNotMatch(JSON.stringify(first), /PRIVATE|SYNTHETIC_AUTH|synthetic_account|httpStatus|gateCode|responseMetadata/);
    assert.throws(() => { first.exchange_failure_code = 'timeout'; }, TypeError);
    assert.equal((await post(url)).status, 422);
    assert.equal(exchanges, 1); assert.equal(value.snapshot().exchange_failure_code, expected);
    await value.close();
    assert.equal(value.snapshot().drained, true);
    assert.equal(value.snapshot().exchange_failure_code, expected);
  }
});


test('response event kind is closed to unsupported-event response failures', async t => {
  const cases = [
    ['response_rejected', 'unsupported_event', 'response.queued', 'response.queued'],
    ['response_rejected', 'unsupported_event', 'PRIVATE_PROVIDER_EVENT', 'other'],
    ['response_rejected', 'invalid_json', 'response.queued', null],
    ['timeout', 'unsupported_event', 'response.queued', null],
  ];
  for (const [code, gateCode, responseEventKind, expected] of cases) {
    const error = Object.assign(new TextGateTransportError(code), { gateCode, responseEventKind,
      message: 'PRIVATE_MESSAGE', responseMetadata: { authorization: 'PRIVATE_AUTH' } });
    const { value, url } = await broker(t, { exchange: async () => { throw error; } });
    value.arm(task);
    assert.equal((await post(url)).status, 422);
    const snapshot = value.snapshot();
    assert.equal(snapshot.response_event_kind, expected);
    assert.doesNotMatch(JSON.stringify(snapshot), /PRIVATE|authorization/);
    await value.close();
  }
});
test('response envelope diagnostics are restricted to unsupported-event response failures', async t => {
  const cases = [
    ['response_rejected', 'unsupported_event', 'absent', 'type_only', 'ping', 'absent', 'type_only', 'ping'],
    ['response_rejected', 'unsupported_event', 'PRIVATE_HEADER', 'PRIVATE_SHAPE', 'PRIVATE_TYPE', null, null, 'other'],
    ['response_rejected', 'invalid_json', 'absent', 'type_only', 'ping', null, null, null],
    ['timeout', 'unsupported_event', 'absent', 'type_only', 'ping', null, null, null],
  ];
  for (const [code, gateCode, relation, shape, control, expectedRelation, expectedShape, expectedControl] of cases) {
    const error = Object.assign(new TextGateTransportError(code), { gateCode, responseEventHeaderRelation: relation,
      responseEventPayloadShape: shape, responseEventControlKind: control, message: 'PRIVATE_MESSAGE' });
    const { value, url } = await broker(t, { exchange: async () => { throw error; } });
    value.arm(task); assert.equal((await post(url)).status, 422);
    const snapshot = value.snapshot();
    assert.equal(snapshot.response_event_header_relation, expectedRelation);
    assert.equal(snapshot.response_event_payload_shape, expectedShape);
    assert.equal(snapshot.response_event_control_kind, expectedControl);
    assert.doesNotMatch(JSON.stringify(snapshot), /PRIVATE/);
    await value.close();
  }
});
test('diagnostics leave default timeout and successful exchange configuration unchanged', async t => {
  let received;
  const value = createTextTaskBroker({ verifyPeer: async () => true,
    exchange: async (_outgoing, options) => { received = options; return safeSse; } });
  t.after(() => value.close());
  const url = `${await value.listen()}/responses`;
  value.arm(task);
  const response = await post(url);
  assert.equal(response.status, 200); assert.deepEqual(Buffer.from(await response.arrayBuffer()), safeSse);
  assert.equal(received.timeoutMs, 60000);
  assert.equal(received.diagnoseRejectedResponse, false); assert.equal(received.diagnoseProtocolKeys, false);
  assert.equal(received.maxInputBytes, 1024 * 1024); assert.equal(received.maxOutputBytes, 1024 * 1024);
  assert.equal(value.snapshot().exchange_failure_code, null);
  assert.equal(value.snapshot().exchange_timeout_phase, null);
});

test('local failures before and after exchange cannot masquerade as transport failures', async t => {
  for (const afterExchange of [false, true]) {
    let verifies = 0, exchanges = 0;
    const { value, url } = await broker(t, {
      verifyPeer: async () => {
        if (++verifies === (afterExchange ? 4 : 3)) throw Object.assign(new TextGateTransportError('timeout'),
          {timeoutPhase: 'before_response_headers'});
        return true;
      },
      exchange: async () => { exchanges++; return safeSse; },
    });
    value.arm(task);
    assert.equal((await post(url)).status, 422);
    assert.equal(exchanges, afterExchange ? 1 : 0);
    assert.equal(value.snapshot().exchange_failure_code, null);
    assert.equal(value.snapshot().exchange_timeout_phase, null);
    assert.equal(value.snapshot().response_released, false);
    await value.close();
  }
});

test('actual stalled loopback exchange records timeout, releases nothing and drains', async t => {
  const upstream = createServer((_req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' }); res.flushHeaders();
  });
  upstream.listen(0, '127.0.0.1'); await once(upstream, 'listening');
  t.after(async () => { const closed = once(upstream, 'close'); upstream.closeAllConnections(); upstream.close(); await closed; });
  const upstreamUrl = `http://127.0.0.1:${upstream.address().port}/v1/responses`;
  const { value, url } = await broker(t, { exchangeTimeoutMs: 200,
    exchange: (outgoing, options) => exchangeTextOnly(outgoing, { ...options, upstreamUrl }) });
  value.arm(task);
  assert.equal((await post(url)).status, 422);
  await value.close();
  assert.equal(value.snapshot().exchange_failure_code, 'timeout');
  assert.equal(value.snapshot().exchange_timeout_phase, 'response_headers_before_body_byte');
  assert.equal(value.snapshot().upstream_attempts, 1);
  assert.equal(value.snapshot().response_released, false); assert.equal(value.snapshot().drained, true);
});

test('timeout phases are a closed vocabulary confined to reserved timeout exchanges', async t => {
  const phases = ['request_preparation', 'before_response_headers', 'response_headers_before_body_byte',
    'response_body_before_eof', 'after_response_eof'];
  const cases = phases.map(phase => ({ error: Object.assign(new TextGateTransportError('timeout'),
    { timeoutPhase: phase }), expected: phase }));
  for (const phase of [undefined, null, 1, false, 'PRIVATE_PHASE', new String('before_response_headers'),
    { toString() { throw Error('PRIVATE_COERCION'); } }]) {
    cases.push({error: Object.assign(new TextGateTransportError('timeout'), {timeoutPhase: phase}), expected: null});
  }
  for (const code of ['aborted', 'http_status', 'response_rejected', 'transport_failed', 'PRIVATE_CODE']) {
    cases.push({error: Object.assign(new TextGateTransportError(code), {timeoutPhase: phases[1]}), expected: null});
  }
  cases.push({error: Object.assign(new Error('PRIVATE_ERROR'), {code:'timeout', timeoutPhase:phases[1]}), expected:null});
  for (const {error, expected} of cases) {
    error.responseMetadata = { authorization: 'PRIVATE_AUTH' };
    let exchanges = 0;
    const {value, url} = await broker(t, {exchange: async () => { exchanges++; throw error; }});
    value.arm(task);
    const response = await post(url);
    assert.equal(response.status, 422);
    assert.equal(await response.text(), '{"error":{"type":"text_task_exchange_rejected"}}');
    const snapshot = value.snapshot();
    assert.equal(snapshot.exchange_timeout_phase, expected);
    if (expected !== null) assert.equal(snapshot.exchange_failure_code, 'timeout');
    assert.equal(snapshot.response_released, false);
    assert.doesNotMatch(JSON.stringify(snapshot), /PRIVATE|responseMetadata|SYNTHETIC_AUTH/);
    assert.throws(() => { snapshot.exchange_timeout_phase = phases[0]; }, TypeError);
    assert.equal((await post(url)).status, 422);
    assert.equal(exchanges, 1);
    await value.close();
    assert.equal(value.snapshot().exchange_timeout_phase, expected);
    assert.equal(value.snapshot().drained, true);
  }
});

test('response rejection diagnostics are closed, response-only, and retain no raw fields', async t => {
  const accepted = [
    { phase: 'before_eof', gate: 'input_limit', location: 'PRIVATE_LOCATION', expectedLocation: null },
    { phase: 'after_eof', gate: 'unknown_field', location: 'response', expectedLocation: 'response' },
    { phase: 'after_eof', gate: 'invalid_json', location: 'response', expectedLocation: null },
  ];
  const rejected = [
    { code: 'response_rejected', phase: 'PRIVATE_PHASE', gate: 'unknown_field', location: 'response' },
    { code: 'response_rejected', phase: 'after_eof', gate: 'PRIVATE_GATE', location: 'response' },
    { code: 'response_rejected', phase: 'after_eof', gate: 'unknown_field', location: 'PRIVATE_LOCATION' },
    { code: 'timeout', phase: 'after_eof', gate: 'unknown_field', location: 'response' },
  ];
  for (const item of accepted.map(value => ({ code: 'response_rejected', ...value })).concat(rejected)) {
    const error = Object.assign(new TextGateTransportError(item.code), {
      responseRejectionPhase: item.phase, gateCode: item.gate, schemaLocation: item.location,
      message: 'PRIVATE_MESSAGE', responseMetadata: { authorization: 'PRIVATE_AUTH' },
    });
    const { value, url } = await broker(t, { exchange: async () => { throw error; } });
    value.arm(task);
    const response = await post(url);
    assert.equal(response.status, 422);
    assert.equal(await response.text(), '{"error":{"type":"text_task_exchange_rejected"}}');
    const snapshot = value.snapshot();
    const responseRejected = item.code === 'response_rejected';
    assert.equal(snapshot.response_rejection_phase,
      responseRejected && ['before_eof', 'after_eof'].includes(item.phase) ? item.phase : null);
    assert.equal(snapshot.response_gate_code,
      responseRejected && ['input_limit', 'unknown_field', 'invalid_json'].includes(item.gate) ? item.gate : null);
    assert.equal(snapshot.response_schema_location,
      responseRejected && item.gate === 'unknown_field' && ['response'].includes(item.location) ? item.location : null);
    assert.equal(snapshot.rejected_requests, 1);
    assert.equal(snapshot.response_released, false);
    assert.doesNotMatch(JSON.stringify(snapshot), /PRIVATE|responseMetadata|authorization/);
    await value.close();
  }
});
