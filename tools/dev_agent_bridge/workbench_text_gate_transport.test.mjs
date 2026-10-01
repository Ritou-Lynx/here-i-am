import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { once, getEventListeners } from 'node:events';
import test from 'node:test';
import { exchangeTextOnly, TextGateTransportError, inspectResponseMetadata, selectTextResponseFormat, sanitizeTextTimeoutPhase,
  sanitizeTextResponseRejectionPhase, sanitizeTextResponseGateCode, sanitizeTextResponseSchemaLocation,
  sanitizeTextResponseEventKind, sanitizeTextResponseEventTypeClass, sanitizeTextResponseEventPhase,
  sanitizeTextResponseEventHeaderRelation, sanitizeTextResponseEventPayloadShape,
  sanitizeTextResponseEventControlKind } from './workbench_text_gate_transport.mjs';
import { isRejectedTextResponseDiagnostic } from './workbench_response_text_diagnostics.mjs';

const requestBody = () => ({
  model: 'synthetic-text-model',
  input: [{ type: 'message', role: 'user', content: [{ type: 'input_text', text: 'hello' }] }],
});
test('schema diagnostics identify only the fixed validator location, never the rejected key or value', async (t) => {
  const original = globalThis.fetch;
  t.after(() => { globalThis.fetch = original; });
  globalThis.fetch = async () => new Response(JSON.stringify({ ...completed(), PRIVATE_UNKNOWN: 'PRIVATE_VALUE' }),
    { headers: { 'content-type': 'application/json' } });
  await assert.rejects(exchangeTextOnly(requestBody(), { model: 'synthetic-text-model', upstreamUrl: 'http://127.0.0.1:12345/v1/responses' }), error => {
    assert.equal(error.schemaLocation, 'response');
    assert.equal(error.responseRejectionPhase, 'after_eof');
    assert.equal(JSON.stringify(error).includes('PRIVATE'), false);
    return error.code === 'response_rejected' && error.gateCode === 'unknown_field';
  });
});

test('unsupported event transport diagnostic is fixed and response-only', async (t) => {
  const original = globalThis.fetch;
  t.after(() => { globalThis.fetch = original; });
  for (const [type, expected] of [['response.queued', 'response.queued'], ['PRIVATE_PROVIDER_EVENT', 'other']]) {
    globalThis.fetch = async () => new Response(`event: ${typeof type === 'string' ? type : 'other'}\ndata: ${JSON.stringify({ type })}\n\n`,
      { headers: { 'content-type': 'text/event-stream' } });
    await assert.rejects(exchangeTextOnly(requestBody(), { model: 'synthetic-text-model', upstreamUrl: 'http://127.0.0.1:12345/v1/responses' }), error => {
      assert.equal(error.code, 'response_rejected');
      assert.equal(error.gateCode, 'unsupported_event');
      assert.equal(error.responseEventKind, expected);
      assert.equal(error.responseEventTypeClass, type === 'response.queued' ? 'response_namespace' : 'other_namespace');
      assert.equal(error.responseEventPhase, 'before_created');
      assert.equal(error.responseEventHeaderRelation, 'equals_payload_type');
      assert.equal(error.responseEventPayloadShape, 'type_only');
      assert.equal(error.responseEventControlKind, type === 'response.queued' ? 'other' : 'other');
      assert.equal(JSON.stringify(error).includes('PRIVATE'), false);
      return true;
    });
  }
  for (const value of [null, undefined, 1, { private: 'PRIVATE' }, 'PRIVATE_PROVIDER_EVENT'])
    assert.equal(sanitizeTextResponseEventKind(value), value == null ? null : 'other');
  for (const value of ['non_object', 'missing', 'null', 'nonstring', 'response_namespace', 'codex_namespace', 'responsesapi_namespace', 'other_namespace'])
    assert.equal(sanitizeTextResponseEventTypeClass(value), value);
  for (const value of ['before_created', 'after_created', 'after_output_started', 'after_text'])
    assert.equal(sanitizeTextResponseEventPhase(value), value);
  for (const value of ['absent', 'equals_payload_type', 'differs_from_payload_type'])
    assert.equal(sanitizeTextResponseEventHeaderRelation(value), value);
  for (const value of ['non_object', 'type_only', 'type_plus_response', 'type_plus_item', 'type_plus_other_fields'])
    assert.equal(sanitizeTextResponseEventPayloadShape(value), value);
  for (const value of ['ping', 'stream.done', 'server_ste_metadata', 'other'])
    assert.equal(sanitizeTextResponseEventControlKind(value), value);
  assert.equal(sanitizeTextResponseEventTypeClass('PRIVATE_CLASS'), null);
  assert.equal(sanitizeTextResponseEventPhase('PRIVATE_PHASE'), null);
  for (const sanitize of [sanitizeTextResponseEventHeaderRelation, sanitizeTextResponseEventPayloadShape])
    assert.equal(sanitize('PRIVATE_MARKER'), null);
  assert.equal(sanitizeTextResponseEventControlKind('PRIVATE_MARKER'), 'other');
  assert.equal(new TextGateTransportError('timeout', { gateCode: 'unsupported_event', responseEventKind: 'response.queued' }).responseEventKind, undefined);
  assert.equal(new TextGateTransportError('response_rejected', { gateCode: 'invalid_json', responseEventKind: 'response.queued' }).responseEventKind, undefined);
  assert.equal(new TextGateTransportError('timeout', { gateCode: 'unsupported_event', responseEventHeaderRelation: 'absent' }).responseEventHeaderRelation, undefined);
});
const completed = () => ({
  id: 'resp_synthetic', status: 'completed',
  output: [{ id: 'msg_synthetic', type: 'message', role: 'assistant', status: 'completed',
    content: [{ type: 'output_text', text: 'SYNTHETIC_OK 🌿', annotations: [] }] }],
});
function textStream() {
  const done = completed();
  const events = [
    { type: 'response.created', response: { id: done.id, status: 'in_progress', output: [] } },
    { type: 'response.output_item.added', output_index: 0,
      item: { id: 'msg_synthetic', type: 'message', role: 'assistant', status: 'in_progress', content: [] } },
    { type: 'response.output_text.delta', output_index: 0, content_index: 0, item_id: 'msg_synthetic', delta: 'SYNTHETIC_OK 🌿' },
    { type: 'response.output_item.done', output_index: 0, item: done.output[0] },
    { type: 'response.completed', response: done },
  ];
  return events.map((event) => `event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`).join('');
}
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

test('response rejection diagnostic vocabularies accept only fixed primitive categories', () => {
  const groups = [
    [sanitizeTextResponseRejectionPhase, ['before_eof', 'after_eof']],
    [sanitizeTextResponseGateCode, [
      'invalid_shape', 'unknown_field', 'invalid_response_metadata', 'invalid_terminal',
      'invalid_json', 'json_complexity_limit', 'duplicate_json_key', 'unsupported_content',
      'unsupported_item', 'empty_message', 'unsupported_sse', 'truncated_sse',
      'duplicate_sse_event', 'event_limit', 'invalid_done_sentinel', 'event_after_terminal',
      'unsupported_event', 'event_type_conflict', 'sequence_conflict', 'duplicate_created',
      'missing_created', 'response_id_conflict', 'invalid_progress', 'output_conflict',
      'item_order_conflict', 'duplicate_item', 'item_id_conflict', 'text_conflict',
      'part_order_conflict', 'text_order_conflict', 'missing_completed', 'missing_assistant_text',
      'output_limit', 'invalid_options', 'invalid_state', 'invalid_chunk', 'input_limit', 'invalid_utf8',
    ]],
    [sanitizeTextResponseSchemaLocation, ['unclassified', 'text_part', 'message', 'response',
      'sse_response', 'sse_item', 'sse_content_part', 'sse_text_delta', 'sse_text_done']],
  ];
  for (const [sanitize, values] of groups) {
    for (const value of values) assert.equal(sanitize(value), value);
    for (const value of [undefined, null, 1, true, '', 'PRIVATE_BODY', new String(values[0]), [values[0]],
      { toString() { throw Error('PRIVATE_COERCION'); } }]) assert.equal(sanitize(value), null);
  }
  for (const phase of ['before_eof', 'after_eof']) {
    assert.equal(new TextGateTransportError('response_rejected', {responseRejectionPhase:phase}).responseRejectionPhase, phase);
    for (const code of ['timeout', 'aborted', 'request_rejected', 'transport_failed'])
      assert.equal(Object.hasOwn(new TextGateTransportError(code, {responseRejectionPhase:phase}), 'responseRejectionPhase'), false);
  }
});

test('actual response rejection distinguishes input overflow before EOF from protocol failure after EOF', async t => {
  const cases = [
    { phase:'before_eof', code:'input_limit', options:{maxInputBytes:16}, body:'PRIVATE_BODY'.repeat(20), end:false },
    { phase:'after_eof', code:'unknown_field', options:{}, body:JSON.stringify({...completed(), PRIVATE_KEY:'PRIVATE_VALUE'}), end:true, location:'response' },
    { phase:'after_eof', code:'invalid_json', options:{}, body:'PRIVATE_BODY', end:true },
  ];
  for (const item of cases) await t.test(`${item.phase}:${item.code}`, async t => {
    let requests=0, disconnected;
    const disconnect=new Promise(resolve=>{disconnected=resolve;});
    const url=await loopback(t, (_req,res)=>{
      requests++;res.on('close',disconnected);res.writeHead(200,{'content-type':'application/json'});
      if(item.end)res.end(item.body);else res.write(item.body);
    });
    await assert.rejects(exchange(url,{...item.options,headers:{authorization:'Bearer PRIVATE_AUTH'}}),error=>{
      assert.equal(error.code,'response_rejected');assert.equal(error.gateCode,item.code);
      assert.equal(error.responseRejectionPhase,item.phase);assert.equal(error.schemaLocation,item.location);
      assert.equal(error.timeoutPhase,undefined);assert.equal(error.responseDiagnostics,undefined);
      assert.doesNotMatch(JSON.stringify(error),/PRIVATE/);return true;
    });
    await disconnect;assert.equal(requests,1);
  });
});

function assertTimeoutPhase(error, phase) {
  assert.ok(error instanceof TextGateTransportError);
  assert.equal(error.code, 'timeout');
  assert.equal(error.timeoutPhase, phase);
  assert.equal(error.cause, undefined);
  assert.equal(error.responseDiagnostics, undefined);
  assert.equal(error.responseMetadata, undefined);
  assert.equal(JSON.stringify(error).includes('PRIVATE'), false);
  assert.equal(error.message.includes('PRIVATE'), false);
  return true;
}

test('timeout phase accepts only primitive strings from the closed vocabulary and only on timeout errors', () => {
  const phases = ['request_preparation', 'before_response_headers', 'response_headers_before_body_byte',
    'response_body_before_eof', 'after_response_eof'];
  for (const phase of phases) {
    assert.equal(sanitizeTextTimeoutPhase(phase), phase);
    assert.equal(new TextGateTransportError('timeout', { timeoutPhase: phase }).timeoutPhase, phase);
    for (const code of ['aborted', 'transport_failed', 'response_rejected', 'PRIVATE_CODE'])
      assert.equal(Object.hasOwn(new TextGateTransportError(code, { timeoutPhase: phase }), 'timeoutPhase'), false);
  }
  let coerced = false;
  for (const value of [undefined, null, '', 'PRIVATE_RESPONSE', 'after_response_eof ', 'AFTER_RESPONSE_EOF',
    new String('after_response_eof'), ['after_response_eof'], 0, true,
    { toString() { coerced = true; return 'after_response_eof'; } }]) {
    assert.equal(sanitizeTextTimeoutPhase(value), null);
    const error = new TextGateTransportError('timeout', { timeoutPhase: value });
    assert.equal(Object.hasOwn(error, 'timeoutPhase'), false);
    assert.equal(JSON.stringify(error).includes('PRIVATE'), false);
  }
  assert.equal(coerced, false);
});

test('loopback timeouts classify headers and first body byte for normal and rejected-format readers', async (t) => {
  for (const diagnostic of [false, true]) {
    for (const phase of ['before_response_headers', 'response_headers_before_body_byte', 'response_body_before_eof']) {
      await t.test(`${diagnostic ? 'rejected format' : 'JSON'}: ${phase}`, async (t) => {
        let requests = 0;
        const url = await loopback(t, (_req, res) => {
          requests++;
          if (phase === 'before_response_headers') return;
          res.writeHead(200, { 'content-type': diagnostic ? 'text/plain' : 'application/json' });
          res.flushHeaders();
          if (phase === 'response_body_before_eof') res.write('{"PRIVATE_RESPONSE":');
        });
        await assert.rejects(exchange(url, { timeoutMs: 150, diagnoseRejectedResponse: diagnostic,
          headers: { authorization: 'Bearer PRIVATE_CREDENTIAL' } }), error => assertTimeoutPhase(error, phase));
        assert.equal(requests, 1);
      });
    }
  }
});

test('preparation timeout retains its local stage without making a request', async (t) => {
  let reads = 0;
  t.mock.method(performance, 'now', () => reads++ === 0 ? 0 : 1000);
  const fetchMock = t.mock.method(globalThis, 'fetch', async () => assert.fail('must not fetch'));
  await assert.rejects(exchange('http://127.0.0.1:12345/v1/responses', { timeoutMs: 100 }),
    error => assertTimeoutPhase(error, 'request_preparation'));
  assert.equal(fetchMock.mock.callCount(), 0);
});

test('observed header, chunk and EOF stages precede the existing deadline checks', async (t) => {
  for (const diagnostic of [false, true]) for (const at of ['headers', 'empty_chunk', 'chunk', 'eof']) {
    await t.test(`${diagnostic ? 'rejected format' : 'JSON'}: ${at}`, async (t) => {
      let now = 0; let reads = 0; let cancelled = 0; let released = 0;
      t.mock.method(performance, 'now', () => now);
      const reader = {
        async read() {
          reads++;
          now = 1000;
          if (at === 'eof') return { done: true };
          return { done: false, value: Buffer.from(at === 'empty_chunk' ? '' : 'PRIVATE_RESPONSE') };
        },
        async cancel() { cancelled++; },
        releaseLock() { released++; },
      };
      t.mock.method(globalThis, 'fetch', async () => {
        const response = new Response(null, { headers: { 'content-type': diagnostic ? 'text/plain' : 'application/json' } });
        Object.defineProperty(response, 'body', { value: { getReader: () => reader, async cancel() { cancelled++; } } });
        if (at === 'headers') now = 1000;
        return response;
      });
      const phase = at === 'eof' ? 'after_response_eof' : at === 'chunk'
        ? 'response_body_before_eof' : 'response_headers_before_body_byte';
      await assert.rejects(exchange('http://127.0.0.1:12345/v1/responses', {
        timeoutMs: 100, diagnoseRejectedResponse: diagnostic,
      }), error => assertTimeoutPhase(error, phase));
      assert.equal(reads, at === 'headers' ? 0 : 1);
      assert.equal(cancelled, 1);
      assert.equal(released, at === 'headers' ? 0 : 1);
    });
  }
});

test('deadline consumed by EOF validation or cleanup never releases the buffered result', async (t) => {
  for (const at of ['validation', 'cleanup']) await t.test(at, async (t) => {
    let now = 0; let eof = false; let cancelled = 0; let released = 0; let parsed = 0;
    const payload = JSON.stringify(completed());
    t.mock.method(performance, 'now', () => now);
    const parse = JSON.parse;
    t.mock.method(JSON, 'parse', function (value, ...args) {
      if (value === payload) {
        assert.equal(eof, true);
        parsed++;
        if (at === 'validation') now = 1000;
      }
      return parse.call(this, value, ...args);
    });
    let first = true;
    const reader = {
      async read() {
        if (first) { first = false; return { done: false, value: Buffer.from(payload) }; }
        eof = true; return { done: true };
      },
      async cancel() { cancelled++; if (at === 'cleanup') now = 1000; },
      releaseLock() { released++; },
    };
    t.mock.method(globalThis, 'fetch', async () => ({ status: 200,
      headers: new Headers({ 'content-type': 'application/json' }), body: { getReader: () => reader } }));
    await assert.rejects(exchange('http://127.0.0.1:12345/v1/responses', { timeoutMs: 100 }),
      error => assertTimeoutPhase(error, 'after_response_eof'));
    assert.equal(parsed, 1);
    assert.equal(cancelled, 1);
    assert.equal(released, 1);
  });
});

test('external abort wins over an expired deadline and retains no phase or private reason', async (t) => {
  let now = 0;
  const controller = new AbortController();
  t.mock.method(performance, 'now', () => now);
  t.mock.method(globalThis, 'fetch', async () => {
    now = 1000; controller.abort('PRIVATE_REASON'); throw new Error('PRIVATE_FETCH_ERROR');
  });
  await assert.rejects(exchange('http://127.0.0.1:12345/v1/responses', {
    timeoutMs: 100, signal: controller.signal, headers: { authorization: 'Bearer PRIVATE_CREDENTIAL' },
  }), error => {
    assert.equal(error.code, 'aborted');
    assert.equal(Object.hasOwn(error, 'timeoutPhase'), false);
    assert.equal(error.cause, undefined);
    assert.equal(JSON.stringify(error).includes('PRIVATE'), false);
    assert.equal(error.message.includes('PRIVATE'), false);
    return true;
  });
  assert.equal(getEventListeners(controller.signal, 'abort').length, 0);
});

async function loopback(t, handler) {
  const server = createServer((req, res) => {
    Promise.resolve(handler(req, res)).catch(() => res.destroy());
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    const closed = once(server, 'close');
    server.close();
    server.closeAllConnections();
    await closed;
  });
  return `http://127.0.0.1:${server.address().port}/v1/responses`;
}

function exchange(upstreamUrl, options = {}, body = requestBody()) {
  return exchangeTextOnly(body, { model: 'synthetic-text-model', upstreamUrl, timeoutMs: 1000, ...options });
}

async function rejected(promise, code, gateCode) {
  let returned = false;
  await assert.rejects(promise.then((result) => { returned = true; return result; }), (error) => {
    assert.ok(error instanceof TextGateTransportError);
    assert.equal(error.code, code);
    if (code !== 'timeout') assert.equal(Object.hasOwn(error, 'timeoutPhase'), false);
    if (gateCode) assert.equal(error.gateCode, gateCode);
    if (['diagnostic_input_limit', 'transport_failed', 'timeout', 'aborted'].includes(code)) assert.equal(error.responseDiagnostics, undefined);
    return true;
  });
  assert.equal(returned, false);
}

test('real loopback SSE exchange rebuilds request and returns only normalized text', async (t) => {
  let received;
  let headers;
  const url = await loopback(t, async (req, res) => {
    headers = req.headers;
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    received = JSON.parse(Buffer.concat(chunks).toString());
    res.writeHead(200, { 'content-type': 'text/event-stream; charset=utf-8' });
    res.end(textStream());
  });
  const body = requestBody();
  body.tools = [{ type: 'function', name: 'unwanted' }];
  body.input.unshift({ type: 'additional_tools', role: 'developer', tools: [{ type: 'function', name: 'hidden' }] });
  body.client_metadata = { auth: 'BODY_SECRET', target: 'http://unwanted.invalid' };
  const output = await exchange(url, {
    headers: { Authorization: 'Bearer SYNTHETIC_TOKEN', 'ChatGPT-Account-Id': 'synthetic_account' },
  }, body);
  assert.deepEqual(received.tools, []);
  assert.equal(received.tool_choice, 'none');
  assert.equal(received.parallel_tool_calls, false);
  assert.equal(received.client_metadata, undefined);
  assert.equal(received.input.length, 1);
  assert.equal(headers.authorization, 'Bearer SYNTHETIC_TOKEN');
  assert.equal(headers['chatgpt-account-id'], 'synthetic_account');
  assert.equal(output.includes('SYNTHETIC_OK'), true);
  assert.equal(output.includes('resp_synthetic'), false);
  assert.equal(output.includes('function_call'), false);
});

test('whole JSON response is normalized after actual EOF', async (t) => {
  const url = await loopback(t, (_req, res) => {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify(completed()));
  });
  assert.equal((await exchange(url)).includes('response.completed'), true);
});

test('completed event alone cannot release output before delayed EOF', async (t) => {
  let sendEnd;
  let signalSent;
  const sent = new Promise((resolve) => { signalSent = resolve; });
  const url = await loopback(t, (_req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write(textStream());
    sendEnd = () => res.end();
    signalSent();
  });
  let resolved = false;
  const pending = exchange(url).then((output) => { resolved = true; return output; });
  await sent;
  await pause(30);
  assert.equal(resolved, false);
  sendEnd();
  assert.ok(Buffer.isBuffer(await pending));
});

test('tool frame appended after completed poisons the entire exchange', async (t) => {
  const url = await loopback(t, async (_req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write(textStream());
    await pause(15);
    res.end('event: response.output_item.added\ndata: {"type":"response.output_item.added","item":{"type":"function_call"}}\n\n');
  });
  await rejected(exchange(url), 'response_rejected', 'event_after_terminal');
});

test('socket destruction after completed is transport failure, not normal EOF', async (t) => {
  const url = await loopback(t, async (_req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write(textStream());
    await pause(15);
    res.destroy();
  });
  await rejected(exchange(url), 'transport_failed');
});

test('never-ending stream times out and cancels its own reader', async (t) => {
  let sawClose;
  const closed = new Promise((resolve) => { sawClose = resolve; });
  const url = await loopback(t, (_req, res) => {
    res.on('close', sawClose);
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write(textStream());
  });
  await rejected(exchange(url, { timeoutMs: 50 }), 'timeout');
  await Promise.race([closed, pause(500).then(() => assert.fail('reader was not cancelled'))]);
});

test('external cancellation after completed rejects and removes abort listener', async (t) => {
  const controller = new AbortController();
  const url = await loopback(t, (_req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write(textStream());
    setTimeout(() => controller.abort('PRIVATE_ABORT_REASON'), 15);
  });
  const baseline = getEventListeners(controller.signal, 'abort').length;
  await rejected(exchange(url, { signal: controller.signal }), 'aborted');
  assert.equal(getEventListeners(controller.signal, 'abort').length, baseline);
});

test('already aborted exchange makes zero requests', async (t) => {
  let requests = 0;
  const url = await loopback(t, (_req, res) => { requests++; res.end(); });
  const controller = new AbortController();
  controller.abort();
  await rejected(exchange(url, { signal: controller.signal }), 'aborted');
  assert.equal(requests, 0);
});

test('HTTP error rejects without exposing upstream body or credentials', async (t) => {
  const url = await loopback(t, (_req, res) => {
    res.writeHead(500, { 'content-type': 'application/json' });
    res.end('PRIVATE_PROVIDER_BODY');
  });
  await assert.rejects(exchange(url, { headers: { authorization: 'Bearer PRIVATE_CREDENTIAL' } }), (error) => {
    assert.equal(error.code, 'http_status');
    assert.equal(error.httpStatus, 500);
    assert.equal(JSON.stringify(error).includes('PRIVATE'), false);
    assert.equal(error.message.includes('PRIVATE'), false);
    assert.equal(error.cause, undefined);
    return true;
  });
});

test('302 redirect is rejected without visiting its loopback target', async (t) => {
  let targetRequests = 0;
  const target = await loopback(t, (_req, res) => { targetRequests++; res.end(textStream()); });
  const url = await loopback(t, (_req, res) => { res.writeHead(302, { location: target }); res.end(); });
  await rejected(exchange(url), 'http_status');
  assert.equal(targetRequests, 0);
});

test('unsupported content type and decoded response size limit reject atomically', async (t) => {
  const html = await loopback(t, (_req, res) => { res.writeHead(200, { 'content-type': 'text/html' }); res.end(textStream()); });
  await rejected(exchange(html), 'unsupported_content_type');
  const large = await loopback(t, (_req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' }); res.end(textStream());
  });
  await rejected(exchange(large, { maxInputBytes: 20 }), 'response_rejected', 'input_limit');
});

test('response metadata diagnostics keep only a fixed vocabulary and never relax rejection', async (t) => {
  assert.deepEqual(inspectResponseMetadata(200, 'text/event-stream; charset="utf8"'), {
    http_status: 200, media_type: 'text/event-stream', parameter_count: 1, charset: 'utf8',
  });
  const diagnostic = inspectResponseMetadata(200, 'application/PRIVATE; PRIVATE=TOKEN; charset=PRIVATE');
  assert.deepEqual(diagnostic, { http_status: 200, media_type: 'other', parameter_count: 2, charset: 'other' });
  assert.equal(JSON.stringify(diagnostic).includes('PRIVATE'), false);
  assert.equal(inspectResponseMetadata(200, 'text/event-stream; charset=utf-8; charset=utf8').charset, 'ambiguous');
  const url = await loopback(t, (_req, res) => {
    res.writeHead(200, { 'content-type': 'text/plain; PRIVATE=TOKEN' }); res.end('PRIVATE_PROVIDER_BODY');
  });
  await assert.rejects(exchange(url), error => {
    assert.equal(error.code, 'unsupported_content_type');
    assert.deepEqual(error.responseMetadata, { http_status: 200, media_type: 'text/plain', parameter_count: 1, charset: 'absent' });
    assert.equal(JSON.stringify(error).includes('PRIVATE'), false);
    assert.equal(JSON.stringify(error).includes('TOKEN'), false);
    return true;
  });
});

test('missing Content-Type selects SSE only for the exact fixed streaming target', () => {
  const official = 'https://chatgpt.com/backend-api/codex/responses';
  assert.equal(selectTextResponseFormat(null, official, true), 'sse');
  for (const target of ['http://127.0.0.1:1234/v1/responses', official + '?x=1', official + '#fragment', 'https://example.invalid'])
    assert.equal(selectTextResponseFormat(null, target, true), null);
  for (const stream of [false, undefined, 'true']) assert.equal(selectTextResponseFormat(null, official, stream), null);
  for (const type of ['', ' ', 'text/plain', 'text/html', 'text/event-stream; extra=1', 'application/json; charset=other'])
    assert.equal(selectTextResponseFormat(type, official, true), null);
  assert.equal(selectTextResponseFormat('application/json', official, true), 'json');
});

test('official missing-type path still validates full bytes and rejects poisoned or malformed streams', async (t) => {
  const target = 'https://chatgpt.com/backend-api/codex/responses';
  let payload = textStream();
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    assert.equal(url, target); assert.deepEqual(JSON.parse(options.body).tools, []);
    // Buffer avoids the text/plain header a string body would synthesize.
    return new Response(Buffer.isBuffer(payload) ? payload : Buffer.from(payload), { status: 200 });
  });
  assert.equal((await exchange(target)).includes('SYNTHETIC_OK'), true);
  for (const bad of [JSON.stringify(completed()), textStream().trimEnd(), Buffer.from([0xc3, 0x28]),
    textStream() + 'data: {"type":"PRIVATE_EVENT"}\n\n',
    textStream().replace('"type":"message"', '"type":"function_call"'),
    textStream().replace('"type":"response.output_text.delta"', '"type":"PRIVATE_EVENT"')]) {
    payload = bad; await rejected(exchange(target), 'response_rejected');
  }
  payload = textStream().replace('"type":"message"', '"type":"function_call"');
  await assert.rejects(exchange(target, { diagnoseRejectedResponse: true }), error => {
    assert.equal(error.responseDiagnostics.diagnostic_only, true);
    assert.equal(error.code, 'response_rejected'); assert.equal(JSON.stringify(error).includes('SYNTHETIC_OK'), false);
    return true;
  });
});

test('official missing-type path preserves stream error, cancellation and timeout', async (t) => {
  const target = 'https://chatgpt.com/backend-api/codex/responses';
  let mode = 'disconnect';
  t.mock.method(globalThis, 'fetch', async (_url, options) => new Response(new ReadableStream({
    start(controller) {
      controller.enqueue(Buffer.from(textStream()));
      if (mode === 'disconnect') setTimeout(() => controller.error(new Error('PRIVATE')), 5);
      else options.signal.addEventListener('abort', () => controller.error(new Error('PRIVATE_ABORT')), { once: true });
    },
  }), { status: 200 }));
  await rejected(exchange(target), 'transport_failed');
  mode = 'wait'; await rejected(exchange(target, { timeoutMs: 30 }), 'timeout');
  const controller = new AbortController();
  const pending = exchange(target, { signal: controller.signal }); setTimeout(() => controller.abort(), 5);
  await rejected(pending, 'aborted');
});

test('rejected response diagnostics wait for EOF and never return even valid text', async (t) => {
  let finish; let announce;
  const sent = new Promise(resolve => { announce = resolve; });
  const url = await loopback(t, (_req, res) => {
    res.writeHead(200); res.write(textStream()); finish = () => res.end(); announce();
  });
  let settled = false;
  const result = exchange(url, { diagnoseRejectedResponse: true }).then(() => assert.fail('must reject'), error => {
    settled = true; return error;
  });
  await sent; await pause(25); assert.equal(settled, false); finish();
  const error = await result;
  assert.equal(error.code, 'unsupported_content_type');
  assert.equal(error.responseMetadata.media_type, 'missing');
  assert.equal(error.responseDiagnostics.diagnostic_only, true);
  assert.equal(JSON.stringify(error).includes('SYNTHETIC_OK'), false);
  assert.equal(JSON.stringify(error).includes('resp_synthetic'), false);
});

test('opt-in rejected-body diagnostics retain limits, abort and disconnect failure', async (t) => {
  const large = await loopback(t, (_req, res) => { res.writeHead(200); res.end('x'.repeat(65)); });
  await rejected(exchange(large, { diagnoseRejectedResponse: true, maxInputBytes: 64 }), 'diagnostic_input_limit');
  const hanging = await loopback(t, (_req, res) => { res.writeHead(200); res.write('data: PRIVATE'); });
  await rejected(exchange(hanging, { diagnoseRejectedResponse: true, timeoutMs: 50 }), 'timeout');
  const broken = await loopback(t, async (_req, res) => {
    res.writeHead(200); res.write(textStream()); await pause(15); res.destroy();
  });
  await rejected(exchange(broken, { diagnoseRejectedResponse: true }), 'transport_failed');
});

test('EOF gate failure has no diagnostic by default and only branded frozen diagnostics when opted in', async (t) => {
  const url = await loopback(t, (_req, res) => {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ...completed(), PRIVATE_UNKNOWN_FIELD: 'PRIVATE_VALUE' }));
  });
  for (const enabled of [false, true]) await assert.rejects(exchange(url, { diagnoseRejectedResponse: enabled }), error => {
    assert.equal(error.code, 'response_rejected');
    if (enabled) {
      assert.equal(isRejectedTextResponseDiagnostic(error.responseDiagnostics), true);
      assert.equal(Object.isFrozen(error.responseDiagnostics), true);
    } else assert.equal(error.responseDiagnostics, undefined);
    assert.equal(JSON.stringify(error).includes('PRIVATE'), false);
    return true;
  });
});

test('configured target and host header allowlist cannot be overridden by body or headers', async (t) => {
  let requests = 0;
  const url = await loopback(t, (_req, res) => { requests++; res.end(); });
  for (const badUrl of [url + '?x=1', url + '#fragment', url.replace('127.0.0.1', 'localhost'),
    url.replace('127.0.0.1', 'user@127.0.0.1'), url.replace('/v1/responses', '/elsewhere'),
    'https://chatgpt.com/backend-api/codex/responses?x=1', 'https://example.invalid/v1/responses']) {
    await rejected(exchange(badUrl), 'invalid_target');
  }
  for (const headers of [{ host: 'other' }, { location: url }, { cookie: 'secret' },
    { authorization: 'Bearer ok\r\nhost: other' }, { Authorization: 'Bearer a', authorization: 'Bearer b' }]) {
    await rejected(exchange(url, { headers }), 'invalid_headers');
  }
  await rejected(exchange(url, {}, { ...requestBody(), upstreamUrl: url }), 'request_rejected');
  assert.equal(requests, 0);
});

test('invalid limits and tool input reject before any HTTP request', async (t) => {
  let requests = 0;
  const url = await loopback(t, (_req, res) => { requests++; res.end(); });
  await rejected(exchange(url, { timeoutMs: 0 }), 'invalid_limits');
  await rejected(exchange(url, { maxEvents: Infinity }), 'invalid_limits');
  await rejected(exchange(url, {}, { ...requestBody(), input: [{ type: 'function_call', name: 'bad' }] }), 'request_rejected');
  assert.equal(requests, 0);
});

test('protocol-key diagnosis is limited to the fixed public request and unknown-field failure after EOF', async (t) => {
  const target = 'https://chatgpt.com/backend-api/codex/responses';
  const body = { model: 'gpt-5.6-sol', instructions: 'This is a fixed synthetic text probe. Follow the user instruction.',
    input: [{ type: 'message', role: 'user', content: [{ type: 'input_text', text: 'Reply exactly: P6_TEXT_GATE_OK' }] }] };
  let responseBody = { ...completed(), extension_flag: { nested: 'PRIVATE_VALUE' }, usage: { extension_budget: 'PRIVATE_VALUE' } };
  let contentType = 'application/json'; let mode = 'normal'; let calls = 0;
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    calls++;
    if (mode === 'normal') return new Response(Buffer.from(JSON.stringify(responseBody)), { headers: { 'content-type': contentType } });
    return new Response(new ReadableStream({ start(controller) {
      controller.enqueue(Buffer.from(JSON.stringify(responseBody)));
      if (mode === 'broken') setTimeout(() => controller.error(new Error('PRIVATE')), 5);
      else options.signal.addEventListener('abort', () => controller.error(new Error('PRIVATE')), { once: true });
    } }), { headers: { 'content-type': contentType } });
  });
  const run = (options = {}, payload = body) => exchangeTextOnly(payload, {
    model: 'gpt-5.6-sol', upstreamUrl: target, timeoutMs: 500, diagnoseRejectedResponse: true, ...options,
  });
  for (const enabled of [false, true]) await assert.rejects(run({ diagnoseProtocolKeys: enabled }), error => {
    assert.equal(error.code, 'response_rejected'); assert.equal(error.gateCode, 'unknown_field');
    const diagnostic = JSON.stringify(error.responseDiagnostics);
    assert.equal(diagnostic.includes('extension_flag'), enabled);
    assert.equal(diagnostic.includes('extension_budget'), enabled);
    assert.equal(diagnostic.includes('PRIVATE_VALUE'), false);
    return true;
  });
  const before = calls;
  for (const [options, payload] of [
    [{ upstreamUrl: 'http://127.0.0.1:1234/v1/responses' }, body],
    [{ diagnoseRejectedResponse: false }, body],
    [{}, { ...body, instructions: 'PRIVATE_INSTRUCTIONS' }],
    [{}, { ...body, input: [{ type: 'message', role: 'user', content: [{ type: 'input_text', text: 'different' }] }] }],
  ]) await rejected(run({ diagnoseProtocolKeys: true, ...options }, payload), 'invalid_diagnostic_scope');
  assert.equal(calls, before);
  contentType = 'text/plain';
  await assert.rejects(run({ diagnoseProtocolKeys: true }), error => {
    assert.equal(error.code, 'unsupported_content_type');
    assert.equal(JSON.stringify(error.responseDiagnostics).includes('extension_flag'), false); return true;
  });
  contentType = 'application/json'; mode = 'broken';
  await rejected(run({ diagnoseProtocolKeys: true }), 'transport_failed');
  mode = 'hang'; await rejected(run({ diagnoseProtocolKeys: true, timeoutMs: 30 }), 'timeout');
  mode = 'normal'; responseBody = { ...completed(), output: [{ type: 'function_call' }] };
  await assert.rejects(run({ diagnoseProtocolKeys: true }), error => {
    assert.equal(error.gateCode, 'unsupported_item');
    assert.equal(Object.hasOwn(error.responseDiagnostics, 'protocol_keys'), false); return true;
  });
});
