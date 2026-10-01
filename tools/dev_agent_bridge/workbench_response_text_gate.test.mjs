import assert from 'node:assert/strict';
import test from 'node:test';
import { createTextOnlyResponseGate, ResponseTextGateError } from './workbench_response_text_gate.mjs';

const clone = (value) => JSON.parse(JSON.stringify(value));

function withHeartbeat(position, extra = {}) {
  const events = eventsFor('P6_TEXT_GATE_OK');
  events.splice(position, 0, { type: 'keepalive', ...extra });
  return events.map((event, sequence_number) => ({ ...event, sequence_number }));
}

test('exact ordered keepalive is inert before creation and between response events', () => {
  const baseline = createTextOnlyResponseTextGateForTest(eventsFor('P6_TEXT_GATE_OK')).finish();
  for (let position = 0; position < eventsFor().length; position++) {
    const gate = createTextOnlyResponseGate();
    const events = withHeartbeat(position);
    for (const event of events) assert.equal(gate.push(sse([event])), undefined);
    assert.deepEqual(gate.finish(), baseline);
  }
});

test('keepalive neither completes a response nor bypasses snapshot consistency', () => {
  const noTerminal = withHeartbeat(7); noTerminal.pop();
  rejectsWithoutOutput(sse(noTerminal));
  const conflict = withHeartbeat(7);
  conflict.at(-1).response.output.at(-1).content[0].text = 'DIFFERENT';
  rejectsWithoutOutput(sse(conflict), 'output_conflict');
  rejectsWithoutOutput(sse([{ type: 'keepalive', sequence_number: 0 }]));
});

test('keepalive cannot carry output, tools, arbitrary metadata or unknown fields', () => {
  for (const extra of [
    { delta: 'PRIVATE_TEXT' }, { text: 'PRIVATE_TEXT' },
    { item: { type: 'function_call', arguments: 'PRIVATE_TOOL' } },
    { response: response([message('PRIVATE_TEXT')]) },
    { metadata: { token: 'PRIVATE_TOKEN' } }, { timestamp: 1 },
    { tool_calls: [] }, { arguments: null },
  ]) rejectsWithoutOutput(sse(withHeartbeat(7, extra)), 'unknown_field');
});

test('keepalive retains header identity and exact monotonic sequence requirements', () => {
  const original = withHeartbeat(7);
  for (const value of [undefined, null, '7', 7.1, -1, 6, 8, Number.MAX_SAFE_INTEGER + 1]) {
    const events = clone(original);
    if (value === undefined) delete events[7].sequence_number;
    else events[7].sequence_number = value;
    rejectsWithoutOutput(sse(events));
  }
  const conflict = sse(original).toString().replace('event: keepalive', 'event: response.completed');
  rejectsWithoutOutput(Buffer.from(conflict), 'event_type_conflict');
  for (const type of ['KEEPALIVE', 'keepalive.extra', 'PRIVATE_UNKNOWN']) {
    const events = clone(original); events[7].type = type;
    rejectsWithoutOutput(sse(events), 'unsupported_event');
  }
});

test('keepalive counts toward finite event budget and remains forbidden after terminal', () => {
  const events = withHeartbeat(7);
  rejectsWithoutOutput(sse(events), 'event_limit', { maxEvents: events.length - 1 });
  const afterTerminal = eventsFor('P6_TEXT_GATE_OK');
  afterTerminal.push({ type: 'keepalive', sequence_number: afterTerminal.length });
  rejectsWithoutOutput(sse(afterTerminal), 'event_after_terminal');
  const afterDone = Buffer.concat([sse(eventsFor()), Buffer.from('data: [DONE]\n\n'), sse([{ type: 'keepalive', sequence_number: 12 }])]);
  rejectsWithoutOutput(afterDone, 'event_after_terminal');
});

test('keepalive malformed duplicate keys still fail the strict JSON grammar', () => {
  const valid = sse(withHeartbeat(7)).toString();
  rejectsWithoutOutput(Buffer.from(valid.replace('"type":"keepalive"', '"type":"keepalive","type":"keepalive"')));
  rejectsWithoutOutput(Buffer.from(valid.replace('"type":"keepalive"', '"type":"keepalive","\\u0074ype":"keepalive"')));
});

test('SSE empty terminal output reuses only already validated complete items', () => {
  for (const includeReasoning of [false, true]) {
    const full = eventsFor('P6_TEXT_GATE_OK', { includeReasoning });
    const empty = clone(full); empty.at(-1).response.output = [];
    assert.deepEqual(createTextOnlyResponseTextGateForTest(empty).finish(), createTextOnlyResponseTextGateForTest(full).finish());
    const unfinished = clone(empty); unfinished.splice(unfinished.findIndex(event => event.type === 'response.output_item.done' && event.item.type === 'message'), 1);
    rejectsWithoutOutput(sse(unfinished), 'output_conflict');
    const mismatch = clone(empty); mismatch.find(event => event.type === 'response.output_text.done').text = 'OTHER';
    rejectsWithoutOutput(sse(mismatch), 'text_conflict');
    const missing = clone(empty); missing.pop(); rejectsWithoutOutput(sse(missing));
    const extra = clone(empty); extra.push({ type: 'response.function_call_arguments.delta', delta: 'PRIVATE' });
    rejectsWithoutOutput(sse(extra), 'event_after_terminal');
    const tool = clone(empty); tool.find(event => event.type === 'response.output_item.done').item = { type: 'function_call' };
    rejectsWithoutOutput(sse(tool), 'unsupported_item');
  }
  const nonemptyConflict = eventsFor('P6_TEXT_GATE_OK'); nonemptyConflict.at(-1).response.output[1].content[0].text = 'OTHER';
  rejectsWithoutOutput(sse(nonemptyConflict), 'output_conflict');
  rejectsWithoutOutput(Buffer.from(JSON.stringify(response([]))), undefined, { format: 'json' });
});
test('documented delta obfuscation is bounded inert padding and never part of text', () => {
  const events = eventsFor('P6_TEXT_GATE_OK');
  events.find(event => event.type === 'response.output_text.delta').obfuscation = 'PRIVATE_RANDOM_PADDING';
  const output = createTextOnlyResponseTextGateForTest(events).finish();
  assert.deepEqual(output, createTextOnlyResponseTextGateForTest(eventsFor('P6_TEXT_GATE_OK')).finish());
  assert.equal(output.includes('PRIVATE'), false);
  for (const invalid of [null, 1, { type: 'function_call' }, 'x'.repeat(8193)]) {
    const changed = clone(events);
    changed.find(event => event.type === 'response.output_text.delta').obfuscation = invalid;
    rejectsWithoutOutput(sse(changed));
  }
  const changed = clone(events);
  changed.find(event => event.type === 'response.output_text.done').obfuscation = 'PRIVATE';
  const gate = createTextOnlyResponseGate(); gate.push(sse(changed));
  assert.throws(() => gate.finish(), error => error.code === 'unknown_field' && error.schemaLocation === 'sse_text_done');
});
const part = (text) => ({ type: 'output_text', text, annotations: [] });
const message = (text = '纯文本 🌿', status = 'completed') => ({
  id: 'msg_provider_1', type: 'message', role: 'assistant', status,
  content: status === 'in_progress' ? [] : [part(text)],
});
const reasoning = (status = 'completed') => ({
  id: 'rs_provider_1', type: 'reasoning', status,
  summary: status === 'completed' ? [{ type: 'summary_text', text: 'PRIVATE_SUMMARY' }] : [],
  content: [{ type: 'reasoning_text', text: 'PRIVATE_REASONING' }],
  encrypted_content: 'PRIVATE_CIPHERTEXT',
});
const response = (output, status = 'completed') => ({
  id: 'resp_provider_1', object: 'response', status, output,
  error: null, incomplete_details: null,
});

function eventsFor(text = '纯文本 🌿', { includeReasoning = true } = {}) {
  const outputIndex = includeReasoning ? 1 : 0;
  const location = { item_id: 'msg_provider_1', output_index: outputIndex, content_index: 0 };
  const events = [
    { type: 'response.created', response: response([], 'in_progress') },
    { type: 'response.in_progress', response: response([], 'in_progress') },
    ...(includeReasoning ? [
      { type: 'response.output_item.added', output_index: 0, item: reasoning('in_progress') },
      { type: 'response.output_item.done', output_index: 0, item: reasoning() },
    ] : []),
    { type: 'response.output_item.added', output_index: outputIndex, item: message(text, 'in_progress') },
    { type: 'response.content_part.added', ...location, part: part('') },
    { type: 'response.output_text.delta', ...location, delta: text },
    { type: 'response.output_text.done', ...location, text },
    { type: 'response.content_part.done', ...location, part: part(text) },
    { type: 'response.output_item.done', output_index: outputIndex, item: message(text) },
    { type: 'response.completed', response: response([...(includeReasoning ? [reasoning()] : []), message(text)]) },
  ];
  return events.map((event, i) => ({ ...event, sequence_number: i }));
}

function reasoningStreamEvents(text = '纯文本 🌿') {
  const events = eventsFor(text);
  events.find(event => event.type === 'response.output_item.added' && event.item.type === 'reasoning').item.content = [];
  const doneIndex = events.findIndex(event => event.type === 'response.output_item.done' && event.item.type === 'reasoning');
  const summaryText = 'PRIVATE_SUMMARY';
  const reasoningText = 'PRIVATE_REASONING';
  events.splice(doneIndex, 0,
    { type: 'response.reasoning_summary_part.added', output_index: 0, item_id: 'rs_provider_1', summary_index: 0,
      part: { type: 'summary_text', text: '' } },
    { type: 'response.reasoning_summary_text.delta', output_index: 0, item_id: 'rs_provider_1', summary_index: 0,
      delta: summaryText, obfuscation: 'PRIVATE_PADDING' },
    { type: 'response.reasoning_summary_text.done', output_index: 0, item_id: 'rs_provider_1', summary_index: 0,
      text: summaryText },
    { type: 'response.reasoning_summary_part.done', output_index: 0, item_id: 'rs_provider_1', summary_index: 0,
      part: { type: 'summary_text', text: summaryText } },
    { type: 'response.reasoning_text.delta', output_index: 0, item_id: 'rs_provider_1', content_index: 0,
      delta: reasoningText, obfuscation: 'PRIVATE_PADDING' },
    { type: 'response.reasoning_text.done', output_index: 0, item_id: 'rs_provider_1', content_index: 0,
      text: reasoningText },
  );
  return events.map((event, sequence_number) => ({ ...event, sequence_number }));
}

function sse(events, { crlf = false } = {}) {
  const text = events.map((event) => `event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`).join('');
  return Buffer.from(crlf ? text.replaceAll('\n', '\r\n') : text);
}

function decodeSse(buffer) {
  return buffer.toString('utf8').trim().split('\n\n').map((frame) =>
    JSON.parse(frame.split('\n').find((line) => line.startsWith('data: ')).slice(6)));
}

function rejectsWithoutOutput(bytes, code, options = {}) {
  const gate = createTextOnlyResponseGate(options);
  const downstream = [];
  assert.throws(() => {
    assert.equal(gate.push(bytes), undefined);
    downstream.push(gate.finish());
  }, (error) => error instanceof ResponseTextGateError && (!code || error.code === code));
  assert.equal(downstream.length, 0);
  assert.equal(gate.state, 'failed');
  assert.throws(() => gate.finish(), (error) => error.code === 'invalid_state');
  assert.throws(() => gate.push(Buffer.alloc(0)), (error) => error.code === 'invalid_state');
}

test('valid text plus reasoning emits only fresh message frames after finish', () => {
  const gate = createTextOnlyResponseGate();
  const input = sse(eventsFor());
  assert.equal(gate.push(input), undefined);
  assert.equal(gate.state, 'collecting');
  const output = gate.finish();
  const events = decodeSse(output);
  assert.equal(events[0].type, 'response.created');
  assert.equal(events.at(-1).type, 'response.completed');
  assert.equal(events.at(-1).response.output.length, 1);
  assert.equal(events.at(-1).response.output[0].content[0].text, '纯文本 🌿');
  assert.ok(events.every((event, i) => event.sequence_number === i));
  for (const forbidden of ['PRIVATE_', 'encrypted_content', 'reasoning', 'resp_provider_1', 'msg_provider_1']) {
    assert.equal(output.includes(forbidden), false);
  }
  assert.equal(gate.state, 'finished');
  assert.throws(() => gate.finish(), (error) => error.code === 'invalid_state');
});

test('official reasoning summary and content stream events validate then disappear from safe output', () => {
  const events = reasoningStreamEvents();
  const output = createTextOnlyResponseTextGateForTest(events).finish();
  assert.deepEqual(output, createTextOnlyResponseTextGateForTest(eventsFor('纯文本 🌿', { includeReasoning: false })).finish());
  for (const forbidden of ['PRIVATE_', 'reasoning', 'summary_text', 'encrypted_content', 'rs_provider_1'])
    assert.equal(output.includes(forbidden), false);
  assert.deepEqual(decodeSse(output).at(-1).response.output.map(item => item.content[0].text), ['纯文本 🌿']);
});

test('reasoning stream snapshots compare part type and text without depending on key order', () => {
  const events = reasoningStreamEvents();
  const reasoningDone = events.find(event => event.type === 'response.output_item.done' && event.item.type === 'reasoning');
  reasoningDone.item.summary = [{ text: 'PRIVATE_SUMMARY', type: 'summary_text' }];
  reasoningDone.item.content = [{ text: 'PRIVATE_REASONING', type: 'reasoning_text' }];
  events.at(-1).response.output[0].summary = [{ text: 'PRIVATE_SUMMARY', type: 'summary_text' }];
  events.at(-1).response.output[0].content = [{ text: 'PRIVATE_REASONING', type: 'reasoning_text' }];
  const output = createTextOnlyResponseTextGateForTest(events).finish();
  assert.deepEqual(output, createTextOnlyResponseTextGateForTest(eventsFor('纯文本 🌿', { includeReasoning: false })).finish());
});

test('reasoning stream identity, order, completeness, and terminal failures reject whole output', () => {
  const cases = [
    ['unknown field', events => { events.find(event => event.type === 'response.reasoning_text.delta').private = 'PRIVATE'; }, 'unknown_field'],
    ['wrong item', events => { events.find(event => event.type === 'response.reasoning_text.delta').item_id = 'msg_provider_1'; }, 'item_id_conflict'],
    ['wrong output index', events => { events.find(event => event.type === 'response.reasoning_text.delta').output_index = 1; }, 'item_order_conflict'],
    ['out of range summary index', events => { events.find(event => event.type === 'response.reasoning_summary_part.added').summary_index = 64; }, 'part_order_conflict'],
    ['stream ignores added reasoning summary', events => { events.find(event => event.type === 'response.output_item.added' && event.item.type === 'reasoning').item.summary = [{ type: 'summary_text', text: 'PRIVATE' }]; }, 'part_order_conflict'],
    ['stream ignores added reasoning content', events => { events.find(event => event.type === 'response.output_item.added' && event.item.type === 'reasoning').item.content = [{ type: 'reasoning_text', text: 'PRIVATE' }]; }, 'part_order_conflict'],
    ['summary done mismatch', events => { events.find(event => event.type === 'response.reasoning_summary_text.done').text = 'OTHER'; }, 'text_conflict'],
    ['reasoning done mismatch', events => { events.find(event => event.type === 'response.reasoning_text.done').text = 'OTHER'; }, 'text_conflict'],
    ['incomplete summary terminal', events => { events.find(event => event.type === 'response.reasoning_summary_part.done').status = 'incomplete'; }, 'unknown_field'],
    ['undocumented completed summary status', events => { events.find(event => event.type === 'response.reasoning_summary_part.done').status = 'completed'; }, 'unknown_field'],
    ['duplicate text done', events => { const at = events.findIndex(event => event.type === 'response.reasoning_text.done'); events.splice(at + 1, 0, clone(events[at])); }, 'text_order_conflict'],
    ['completed snapshot mismatch', events => { events.at(-1).response.output[0].summary[0].text = 'OTHER'; }, 'output_conflict'],
    ['append after completion', events => { events.push({ type: 'response.reasoning_text.delta', output_index: 0, item_id: 'rs_provider_1', content_index: 0, delta: 'PRIVATE' }); }, 'event_after_terminal'],
    ['tool shaped event', events => { events.splice(-1, 0, { type: 'response.function_call_arguments.delta', output_index: 0, item_id: 'rs_provider_1', delta: 'PRIVATE' }); }, 'unsupported_event'],
  ];
  for (const [_name, mutate, code] of cases) {
    const events = reasoningStreamEvents(); mutate(events);
    events.forEach((event, sequence_number) => { event.sequence_number = sequence_number; });
    rejectsWithoutOutput(sse(events), code);
  }
});

test('byte-by-byte CRLF UTF-8 fragments preserve multilingual output', () => {
  const gate = createTextOnlyResponseGate();
  const input = sse(eventsFor('林埃 🌿 café'), { crlf: true });
  for (const byte of input) assert.equal(gate.push(Uint8Array.of(byte)), undefined);
  assert.equal(decodeSse(gate.finish()).at(-1).response.output[0].content[0].text, '林埃 🌿 café');
});

test('push copies caller memory and accepts whole completed JSON through the same schema', () => {
  const gate = createTextOnlyResponseGate({ format: 'json' });
  const input = Buffer.from(JSON.stringify(response([reasoning(), message()])));
  gate.push(input);
  input.fill(0);
  const events = decodeSse(gate.finish());
  assert.equal(events.at(-1).response.output[0].content[0].text, '纯文本 🌿');
});

test('tool-shaped strings and SSE injection strings remain inert output_text', () => {
  const text = '{"type":"function_call","name":"danger"}\n\nevent: tool\ndata: bad';
  const gate = createTextOnlyResponseGate();
  gate.push(sse(eventsFor(text, { includeReasoning: false })));
  const events = decodeSse(gate.finish());
  assert.equal(events.length, 8);
  assert.equal(events.at(-1).response.output[0].content[0].text, text);
  assert.ok(events.every((event) => event.type.startsWith('response.')));
});

test('optional content/text done events may be omitted in the documented minimal subset', () => {
  const events = eventsFor('minimal', { includeReasoning: false }).filter((event) =>
    !['response.in_progress', 'response.content_part.added', 'response.content_part.done', 'response.output_text.done'].includes(event.type));
  const gate = createTextOnlyResponseTextGateForTest(events);
  assert.equal(decodeSse(gate.finish()).at(-1).response.output[0].content[0].text, 'minimal');
});

function createTextOnlyResponseTextGateForTest(events) {
  const gate = createTextOnlyResponseGate();
  gate.push(sse(events));
  return gate;
}

for (const type of ['function_call', 'custom_tool_call', 'web_search_call', 'file_search_call',
  'computer_call', 'local_shell_call', 'shell_call', 'image_generation_call', 'mcp_call', 'unknown_item']) {
  for (const location of ['added', 'done', 'completed']) {
    test(`${type} hidden in ${location} rejects all output`, () => {
      const events = eventsFor('safe prefix');
      const tool = { id: 'call_hidden', type, name: 'danger', arguments: '{}' };
      if (location === 'completed') events.at(-1).response.output.push(tool);
      else events.find((event) => event.type === `response.output_item.${location}`).item = tool;
      rejectsWithoutOutput(sse(events), 'unsupported_item');
    });
  }
}

for (const type of ['response.function_call_arguments.delta', 'response.custom_tool_call_input.delta',
  'response.reasoning_summary_tool_call.delta', 'response.reasoning_opaque.delta', 'response.failed',
  'response.incomplete', 'error', 'response.unknown']) {
  test(`unknown or unsupported event ${type} rejects even after a safe prefix`, () => {
    const events = eventsFor();
    events.splice(-1, 0, { type });
    rejectsWithoutOutput(sse(events), 'unsupported_event');
  });
}


test('unsupported SSE events retain only a fixed public kind or other', () => {
  for (const [type, expected] of [
    ['response.queued', 'response.queued'],
    ['codex.rate_limits', 'codex.rate_limits'],
    ['codex.response.metadata', 'codex.response.metadata'],
    ['response.metadata', 'response.metadata'],
    ['responsesapi.websocket_timing', 'responsesapi.websocket_timing'],
    ['response.refusal.delta', 'response.refusal.delta'],
    ['response.function_call_arguments.delta', 'response.function_call_arguments.delta'],
    ['response.web_search_call.completed', 'response.web_search_call.completed'],
    ['response.audio.delta', 'response.audio.delta'],
    ['response.audio.transcript.done', 'response.audio.transcript.done'],
    ['response.mcp_call_arguments.delta', 'response.mcp_call_arguments.delta'],
    ['response.mcp_list_tools.in_progress', 'response.mcp_list_tools.in_progress'],
    ['response.shell_call_command.added', 'response.shell_call_command.added'],
    ['response.output_audio.delta', 'other'],
    ['response.mcp_call.arguments.delta', 'other'],
    ['PRIVATE_PROVIDER_EVENT', 'other'],
    [null, 'other'],
    [{ private: 'PRIVATE_VALUE' }, 'other'],
  ]) {
    const events = eventsFor();
    events.splice(-1, 0, { type });
    events.forEach((event, sequence_number) => { event.sequence_number = sequence_number; });
    const gate = createTextOnlyResponseGate();
    assert.throws(() => { gate.push(sse(events)); gate.finish(); }, error => {
      assert.equal(error.code, 'unsupported_event');
      assert.equal(error.eventKind, expected);
      assert.equal(JSON.stringify(error).includes('PRIVATE'), false);
      return true;
    });
    assert.equal(gate.state, 'failed');
  }
});

test('unsupported event type class and verified phase are closed diagnostics', () => {
  const frame = value => Buffer.from(`data: ${JSON.stringify(value)}\n\n`);
  const cases = [
    [null, 'non_object', 'before_created', 0], [[], 'non_object', 'before_created', 0],
    [{}, 'missing', 'before_created', 0], [{ type: null }, 'null', 'before_created', 0],
    [{ type: 1 }, 'nonstring', 'before_created', 0], [{ type: 'response.private' }, 'response_namespace', 'before_created', 0],
    [{ type: 'codex.private' }, 'codex_namespace', 'after_created', 1],
    [{ type: 'responsesapi.private' }, 'responsesapi_namespace', 'after_output_started', 4],
    [{ type: 'private.namespace' }, 'other_namespace', 'after_text', 7],
  ];
  for (const [value, typeClass, phase, prefixCount] of cases) {
    const gate = createTextOnlyResponseGate();
    const prefix = eventsFor().slice(0, prefixCount);
    assert.throws(() => { gate.push(Buffer.concat([sse(prefix), frame(value)])); gate.finish(); }, error => {
      assert.equal(error.code, 'unsupported_event');
      assert.equal(error.eventTypeClass, typeClass);
      assert.equal(error.eventPhase, phase);
      assert.equal(JSON.stringify(error).includes('private'), false);
      return true;
    });
    assert.equal(gate.state, 'failed');
  }
});
test('unsupported envelope diagnostics are fixed, non-releasing classifications', () => {
  const frame = (eventName, value) => Buffer.from(`${eventName === null ? '' : `event: ${eventName}\n`}data: ${JSON.stringify(value)}\n\n`);
  for (const [eventName, value, relation, shape, control] of [
    [null, { type: 'ping' }, 'absent', 'type_only', 'ping'],
    ['ping', { type: 'ping' }, 'equals_payload_type', 'type_only', 'ping'],
    ['PRIVATE_HEADER', { type: 'ping', response: { private: 'PRIVATE_VALUE' } }, 'differs_from_payload_type', 'type_plus_response', 'ping'],
    [null, { type: 'pong', item: { private: 'PRIVATE_VALUE' } }, 'absent', 'type_plus_item', 'pong'],
    [null, { type: 'PRIVATE_TYPE', private: 'PRIVATE_VALUE' }, 'absent', 'type_plus_other_fields', 'other'],
    [null, null, 'absent', 'non_object', 'other'],
  ]) {
    const gate = createTextOnlyResponseGate();
    assert.throws(() => { gate.push(frame(eventName, value)); gate.finish(); }, error => {
      assert.equal(error.code, 'unsupported_event');
      assert.equal(error.eventHeaderRelation, relation);
      assert.equal(error.eventPayloadShape, shape);
      assert.equal(error.eventControlKind, control);
      assert.equal(JSON.stringify(error).includes('PRIVATE'), false);
      return true;
    });
    assert.equal(gate.state, 'failed');
  }
});
test('mixed assistant text and tool in whole JSON is rejected', () => {
  rejectsWithoutOutput(Buffer.from(JSON.stringify(response([message(), { type: 'function_call' }]))),
    'unsupported_item', { format: 'json' });
});

for (const [label, mutate, code] of [
  ['missing terminal', (events) => events.pop(), 'missing_completed'],
  ['duplicate terminal', (events) => events.push(clone(events.at(-1))), 'event_after_terminal'],
  ['post-terminal tool', (events) => events.push({ type: 'response.output_item.added', item: { type: 'function_call' } }), 'event_after_terminal'],
  ['conflicting response id', (events) => { events.at(-1).response.id = 'wrong'; }, 'response_id_conflict'],
  ['conflicting item id', (events) => { events.find((event) => event.type === 'response.output_text.delta').item_id = 'wrong'; }, 'item_id_conflict'],
  ['conflicting final text', (events) => { events.at(-1).response.output.at(-1).content[0].text = 'different'; }, 'output_conflict'],
  ['conflicting reasoning snapshot', (events) => { events.at(-1).response.output[0].encrypted_content = 'DIFFERENT'; }, 'output_conflict'],
  ['duplicate item done', (events) => events.splice(4, 0, clone(events[3])), 'sequence_conflict'],
  ['nonempty error', (events) => { events.at(-1).response.error = { code: 'bad' }; }, 'invalid_terminal'],
  ['incomplete status', (events) => { events.at(-1).response.status = 'incomplete'; }, 'invalid_terminal'],
  ['unknown metadata', (events) => { events.at(-1).response.hidden = { type: 'function_call' }; }, 'unknown_field'],
  ['non-assistant role', (events) => { events.at(-1).response.output.at(-1).role = 'tool'; }, 'invalid_shape'],
  ['missing content', (events) => { delete events.at(-1).response.output.at(-1).content; }, 'invalid_shape'],
]) {
  test(label, () => { const events = eventsFor(); mutate(events); rejectsWithoutOutput(sse(events), code); });
}

test('duplicate JSON keys including escaped aliases fail before schema validation', () => {
  const payload = '{"id":"r","status":"completed","output":[],"\\u006futput":[{"type":"function_call"}]}';
  rejectsWithoutOutput(Buffer.from(payload), 'duplicate_json_key', { format: 'json' });
});

test('invalid JSON and invalid UTF-8 never release bytes', () => {
  rejectsWithoutOutput(Buffer.from('event: response.created\ndata: {broken}\n\n'), 'invalid_json');
  rejectsWithoutOutput(Buffer.from([0xc3, 0x28]), 'invalid_utf8');
  rejectsWithoutOutput(Buffer.from([0xf0, 0x9f]), 'invalid_utf8');
  rejectsWithoutOutput(Buffer.from('"\\ud800"'), 'invalid_shape', { format: 'json' });
});

test('truncated SSE frame, conflicting event header and premature DONE reject', () => {
  const input = sse(eventsFor());
  rejectsWithoutOutput(input.subarray(0, input.length - 1), 'truncated_sse');
  rejectsWithoutOutput(Buffer.from(input.toString().replace('event: response.created', 'event: response.completed')),
    'event_type_conflict');
  rejectsWithoutOutput(Buffer.from('data: [DONE]\n\n'), 'invalid_done_sentinel');
});

test('one optional DONE sentinel after completion is accepted; duplicates rejected', () => {
  const input = Buffer.concat([sse(eventsFor()), Buffer.from('data: [DONE]\n\n')]);
  const gate = createTextOnlyResponseGate();
  gate.push(input);
  assert.ok(Buffer.isBuffer(gate.finish()));
  rejectsWithoutOutput(Buffer.concat([input, Buffer.from('data: [DONE]\n\n')]), 'invalid_done_sentinel');
});

test('input, output, event and JSON complexity limits fail atomically', () => {
  const input = sse(eventsFor());
  rejectsWithoutOutput(input, 'input_limit', { maxInputBytes: 10 });
  rejectsWithoutOutput(input, 'output_limit', { maxOutputBytes: 20 });
  rejectsWithoutOutput(input, 'event_limit', { maxEvents: 2 });
  rejectsWithoutOutput(Buffer.from('['.repeat(34) + '0' + ']'.repeat(34)), 'json_complexity_limit', { format: 'json' });
});

test('invalid options and non-byte chunks fail closed', () => {
  for (const options of [{ format: 'auto' }, { maxInputBytes: Infinity }, { maxEvents: 0 }]) {
    assert.throws(() => createTextOnlyResponseGate(options), (error) => error.code === 'invalid_options');
  }
  const gate = createTextOnlyResponseGate();
  assert.throws(() => gate.push('not bytes'), (error) => error.code === 'invalid_chunk');
  assert.equal(gate.state, 'failed');
});

test('multiple messages and content parts are normalized and the generated stream validates again', () => {
  const first = message('one');
  first.content.push(part('二'));
  const second = { ...message('three'), id: 'msg_provider_2' };
  const gate = createTextOnlyResponseGate({ format: 'json' });
  gate.push(Buffer.from(JSON.stringify(response([first, reasoning(), second]))));
  const output = gate.finish();
  const again = createTextOnlyResponseGate();
  again.push(output);
  const final = decodeSse(again.finish()).at(-1).response;
  assert.deepEqual(final.output.map((entry) => entry.content.map((content) => content.text)), [['one', '二'], ['three']]);
});

test('duplicate item events reject even when the provider has no sequence numbers', () => {
  const events = eventsFor().map(({ sequence_number, ...event }) => event);
  events.splice(4, 0, clone(events[3]));
  rejectsWithoutOutput(sse(events), 'item_order_conflict');
});

test('missing assistant text and malformed or excessive item content reject whole JSON', () => {
  for (const output of [[], [reasoning()]]) {
    rejectsWithoutOutput(Buffer.from(JSON.stringify(response(output))), 'missing_assistant_text', { format: 'json' });
  }
  const malformed = reasoning();
  malformed.encrypted_content = { type: 'function_call' };
  rejectsWithoutOutput(Buffer.from(JSON.stringify(response([malformed, message()]))), 'invalid_shape', { format: 'json' });
  const excessive = message();
  excessive.content = Array.from({ length: 65 }, () => part('x'));
  rejectsWithoutOutput(Buffer.from(JSON.stringify(response([excessive]))), 'invalid_shape', { format: 'json' });
});

const commonMetadata = () => ({
  created_at: 1234.5, completed_at: 1235.5, model: 'SYNTHETIC_PRIVATE_MODEL',
  instructions: 'SYNTHETIC_PRIVATE_INSTRUCTIONS',
  usage: { input_tokens: 10, input_tokens_details: { cached_tokens: 2, cache_write_tokens: 1 },
    output_tokens: 5, output_tokens_details: { reasoning_tokens: 1 }, total_tokens: 15 },
  metadata: {}, tools: [], tool_choice: 'none', parallel_tool_calls: false, store: false, background: false,
  previous_response_id: null, conversation: null, prompt: null, moderation: null,
  prompt_cache_diagnostics: null, prompt_cache_options: null, prompt_cache_key: 'SYNTHETIC_PRIVATE_CACHE',
  prompt_cache_retention: '24h', reasoning: { effort: 'low', summary: null, generate_summary: null },
  text: { format: { type: 'text' }, verbosity: 'medium' }, max_output_tokens: null, max_tool_calls: null,
  temperature: 1, top_p: 1, top_logprobs: 0, truncation: 'disabled', service_tier: 'default',
  safety_identifier: 'SYNTHETIC_PRIVATE_IDENTIFIER', user: null,
});
function eventsWithMetadata() {
  const events = eventsFor('P6_TEXT_GATE_OK', { includeReasoning: false });
  for (const event of events) {
    if (event.response) Object.assign(event.response, commonMetadata(), event.response.status === 'in_progress'
      ? { completed_at: null, usage: null } : {});
    if (event.item?.type === 'message') event.item.phase = event.type.endsWith('.added') ? null : 'final_answer';
    for (const item of event.response?.output || []) if (item.type === 'message') item.phase = 'final_answer';
  }
  return events;
}
test('complete common SSE metadata and optional phase validate but rebuild identical text-only bytes', () => {
  const gate = createTextOnlyResponseGate();
  const bytes = sse(eventsWithMetadata());
  for (let offset = 0; offset < bytes.length; offset += 31) assert.equal(gate.push(bytes.subarray(offset, offset + 31)), undefined);
  const output = gate.finish();
  assert.deepEqual(output, createTextOnlyResponseTextGateForTest(eventsFor('P6_TEXT_GATE_OK', { includeReasoning: false })).finish());
  assert.equal(output.includes('SYNTHETIC_PRIVATE'), false);
  const final = decodeSse(output).at(-1).response;
  assert.deepEqual(Object.keys(final).sort(), ['id', 'object', 'output', 'status']);
  assert.equal(Object.hasOwn(final.output[0], 'phase'), false);
});
test('observed access-program label is validated then discarded without widening text output', () => {
  const events = eventsWithMetadata();
  for (const event of events) if (event.response) {
    event.response.access_programs = { cyber: 'SYNTHETIC_PRIVATE_ACCESS' };
  }
  const output = createTextOnlyResponseTextGateForTest(events).finish();
  assert.deepEqual(output,
    createTextOnlyResponseTextGateForTest(eventsFor('P6_TEXT_GATE_OK', { includeReasoning: false })).finish());
  assert.equal(output.includes('SYNTHETIC_PRIVATE_ACCESS'), false);
  for (const access of [null, [], {}, { cyber: null }, { cyber: 1 }, { cyber: '' },
    { cyber: 'x'.repeat(129) }, { cyber: 'ok', function_call: { arguments: 'PRIVATE' } }]) {
    for (const stage of ['response.created', 'response.in_progress', 'response.completed']) {
      const malformed = eventsWithMetadata();
      malformed.find(event => event.type === stage).response.access_programs = access;
      rejectsWithoutOutput(sse(malformed));
    }
  }
  const duplicate = JSON.stringify({ ...response([message('P6_TEXT_GATE_OK')]),
    access_programs: { cyber: 'one' } }).replace('"cyber":"one"', '"cyber":"one","cyber":"two"');
  rejectsWithoutOutput(Buffer.from(duplicate), 'duplicate_json_key', { format: 'json' });
});
test('whole JSON accepts known metadata with null options and discards every option', () => {
  const value = { ...response([{ ...message('P6_TEXT_GATE_OK'), phase: 'commentary' }]), ...commonMetadata() };
  for (const key of ['completed_at', 'instructions', 'usage', 'metadata', 'store', 'background', 'prompt_cache_key',
    'prompt_cache_retention', 'reasoning', 'text', 'max_output_tokens', 'max_tool_calls', 'temperature', 'top_p',
    'top_logprobs', 'truncation', 'service_tier', 'safety_identifier', 'user']) value[key] = null;
  const gate = createTextOnlyResponseGate({ format: 'json' }); gate.push(Buffer.from(JSON.stringify(value)));
  const final = decodeSse(gate.finish()).at(-1).response;
  assert.deepEqual(Object.keys(final).sort(), ['id', 'object', 'output', 'status']);
  assert.equal(Object.hasOwn(final.output[0], 'phase'), false);
});
test('tool, persistence, history and template settings fail even when only text is emitted', () => {
  for (const patch of [
    { tools: [{ type: 'function' }] }, { tools: null }, { tool_choice: 'auto' }, { tool_choice: null },
    { tool_choice: { type: 'function', name: 'hidden' } }, { parallel_tool_calls: true }, { parallel_tool_calls: null },
    { store: true }, { background: true }, { previous_response_id: 'history' }, { conversation: {} }, { prompt: {} },
    { moderation: {} }, { prompt_cache_diagnostics: {} }, { prompt_cache_options: {} },
  ]) {
    const events = eventsWithMetadata(); Object.assign(events.at(-1).response, patch);
    rejectsWithoutOutput(sse(events), 'invalid_response_metadata');
  }
});
test('unknown nested response metadata, usage, reasoning and text fields remain rejected', () => {
  for (const patch of [
    { metadata: { hidden: 'PRIVATE' } }, { metadata: { hidden: { type: 'function_call' } } },
    { reasoning: { effort: 'low', unknown_context: 'auto' } }, { reasoning: { unknown_mode: 'standard' } },
    { text: { format: { type: 'text', hidden: 'PRIVATE' } } }, { text: { hidden: 'PRIVATE' } },
    { usage: { ...commonMetadata().usage, hidden: 1 } },
    { usage: { ...commonMetadata().usage, input_tokens_details: { cached_tokens: 0, hidden: 1 } } },
    { usage: { ...commonMetadata().usage, output_tokens_details: { reasoning_tokens: 0, hidden: 1 } } },
    { truly_unknown_response_field: { type: 'function_call' } },
  ]) {
    const events = eventsWithMetadata(); Object.assign(events.at(-1).response, patch);
    rejectsWithoutOutput(sse(events), 'unknown_field');
  }
});
test('usage requires known nonnegative safe integer counters and required detail objects', () => {
  const invalidUsages = [];
  for (const key of ['input_tokens', 'output_tokens', 'total_tokens']) {
    for (const value of [-1, 0.5, '1', true, null, Number.MAX_SAFE_INTEGER + 1]) invalidUsages.push({ ...commonMetadata().usage, [key]: value });
    const missing = commonMetadata().usage; delete missing[key]; invalidUsages.push(missing);
  }
  invalidUsages.push({ ...commonMetadata().usage, input_tokens_details: { cached_tokens: -1 } },
    { ...commonMetadata().usage, input_tokens_details: { cached_tokens: 0, cache_write_tokens: 0.5 } },
    { ...commonMetadata().usage, input_tokens_details: {} },
    { ...commonMetadata().usage, output_tokens_details: { reasoning_tokens: null } },
    { ...commonMetadata().usage, output_tokens_details: {} });
  for (const usage of invalidUsages) {
    const value = { ...response([message()]), ...commonMetadata(), usage };
    rejectsWithoutOutput(Buffer.from(JSON.stringify(value)), 'invalid_response_metadata', { format: 'json' });
  }
  for (const usage of [{}, { ...commonMetadata().usage, input_tokens_details: null }, { ...commonMetadata().usage, output_tokens_details: [] }])
    rejectsWithoutOutput(Buffer.from(JSON.stringify({ ...response([message()]), usage })), undefined, { format: 'json' });
  const previousUsage = commonMetadata().usage; delete previousUsage.input_tokens_details.cache_write_tokens;
  const gate = createTextOnlyResponseGate({ format: 'json' });
  gate.push(Buffer.from(JSON.stringify({ ...response([message()]), usage: previousUsage })));
  assert.ok(Buffer.isBuffer(gate.finish()));
});
test('metadata scalar types, numerical bounds and fixed enums reject unsupported values', () => {
  for (const patch of [
    { created_at: null }, { created_at: -1 }, { completed_at: 'now' }, { created_at: 1e13 },
    { model: '' }, { model: null }, { model: 'x'.repeat(201) }, { instructions: [] }, { instructions: 'x'.repeat(65537) },
    { prompt_cache_key: {} }, { safety_identifier: 'x'.repeat(65) }, { user: 1 },
    { temperature: 2.1 }, { top_p: -1 }, { top_logprobs: 21 }, { top_logprobs: 0.5 },
    { max_output_tokens: 0 }, { max_tool_calls: -1 }, { max_output_tokens: 1000001 },
    { prompt_cache_retention: 'forever' }, { service_tier: 'unknown' }, { truncation: true },
    { reasoning: { effort: 'unknown' } }, { reasoning: { summary: true } }, { reasoning: { generate_summary: 'unknown' } },
    { text: { format: { type: 'json_schema' } } }, { text: { verbosity: 'ultra' } },
  ]) {
    const events = eventsWithMetadata(); Object.assign(events.at(-1).response, patch);
    rejectsWithoutOutput(sse(events));
  }
});
test('optional phase only permits null commentary or final_answer at every message location', () => {
  for (const phase of [null, 'commentary', 'final_answer']) {
    const events = eventsWithMetadata();
    for (const event of events) {
      if (event.item?.type === 'message') event.item.phase = phase;
      for (const item of event.response?.output || []) item.phase = phase;
    }
    assert.ok(Buffer.isBuffer(createTextOnlyResponseTextGateForTest(events).finish()));
  }
  for (const phase of ['analysis', {}, true, 0]) {
    for (const location of ['added', 'done', 'completed']) {
      const events = eventsWithMetadata();
      if (location === 'completed') events.at(-1).response.output[0].phase = phase;
      else events.find(event => event.type === `response.output_item.${location}`).item.phase = phase;
      rejectsWithoutOutput(sse(events), 'invalid_response_metadata');
    }
  }
});
test('new metadata keeps duplicate-key rejection and unknown reasoning events fail closed', () => {
  const json = JSON.stringify({ ...response([message()]), ...commonMetadata() });
  rejectsWithoutOutput(Buffer.from(json.replace('"cached_tokens":2', '"cached_tokens":2,"cached_tokens":3')),
    'duplicate_json_key', { format: 'json' });
  const events = eventsWithMetadata(); events.splice(-1, 0, { type: 'response.reasoning_summary_tool_call.delta', delta: 'PRIVATE' });
  rejectsWithoutOutput(sse(events), 'unsupported_event');
});

test('official Codex usage and model-header metadata stay inert while retaining terminal checks', () => {
  const events = eventsWithMetadata();
  for (const event of events) if (event.response) {
    Object.assign(event.response, {
      headers: { 'openai-model': ['PRIVATE_MODEL'], 'x-request-id': 'PRIVATE_ID' },
      usage_metadata: { amount: 'PRIVATE_AMOUNT', metadata: { private: 'PRIVATE', type: 'function_call', arguments: { command: 'PRIVATE' } } },
      end_turn: event.response.status === 'completed',
      reasoning: { effort: 'low', context: 'auto', mode: 'standard', summary: null },
    });
    if (event.response.usage) event.response.usage.codex_rollout_budget_units = 2.5;
  }
  const output = createTextOnlyResponseTextGateForTest(events).finish();
  assert.equal(output.includes('PRIVATE'), false); assert.equal(output.includes('function_call'), false);
  assert.deepEqual(output, createTextOnlyResponseTextGateForTest(eventsFor('P6_TEXT_GATE_OK', { includeReasoning: false })).finish());
  const incompleteTurn = clone(events); incompleteTurn.at(-1).response.end_turn = false;
  rejectsWithoutOutput(sse(incompleteTurn), 'invalid_terminal');
});

test('Codex extension types, nested protocol fields and bounded header maps reject malformed input', () => {
  for (const patch of [
    { headers: [] }, { headers: { 'openai-model': {} } }, { headers: { 'openai-model': [1] } },
    { headers: { 'bad header': 'PRIVATE' } }, { headers: { 'openai-model': 'x'.repeat(8193) } },
    { headers: Object.fromEntries(Array.from({ length: 65 }, (_, i) => [`h-${i}`, 'v'])) },
    { usage_metadata: [] }, { usage_metadata: { amount: 1 } }, { usage_metadata: { unknown_field: 'PRIVATE' } },
    { end_turn: 'true' }, { reasoning: { context: 'unknown' } }, { reasoning: { mode: 'unknown' } },
    { usage: { ...commonMetadata().usage, codex_rollout_budget_units: '2.5' } },
    { usage: { ...commonMetadata().usage, codex_rollout_budget_units: -1 } },
  ]) {
    const events = eventsWithMetadata(); Object.assign(events.at(-1).response, patch);
    rejectsWithoutOutput(sse(events));
  }
  const json = JSON.stringify({ ...response([message()]), usage_metadata: { metadata: { repeated: 1 } } });
  rejectsWithoutOutput(Buffer.from(json.replace('"repeated":1', '"repeated":1,"repeated":2')), 'duplicate_json_key', { format: 'json' });
});

test('fixed-probe penalty and empty usage extensions are checked then completely discarded', () => {
  const events = eventsWithMetadata();
  for (const event of events) if (event.response) {
    Object.assign(event.response, { frequency_penalty: 0, presence_penalty: -2, tool_usage: {} });
    if (event.response.usage) event.response.usage.attribution = {};
  }
  assert.deepEqual(createTextOnlyResponseTextGateForTest(events).finish(),
    createTextOnlyResponseTextGateForTest(eventsFor('P6_TEXT_GATE_OK', { includeReasoning: false })).finish());
  for (const value of [-2, 2]) {
    const changed = clone(events);
    Object.assign(changed.at(-1).response, { frequency_penalty: value, presence_penalty: value });
    assert.ok(Buffer.isBuffer(createTextOnlyResponseTextGateForTest(changed).finish()));
  }
});

test('nonempty usage attribution or tool usage and malformed penalties never release text', () => {
  for (const patch of [
    { frequency_penalty: -2.01 }, { frequency_penalty: '0' }, { frequency_penalty: null },
    { presence_penalty: 2.01 }, { presence_penalty: true }, { presence_penalty: {} },
    { tool_usage: null }, { tool_usage: [] }, { tool_usage: { function_call: 0 } },
    { tool_usage: { hidden: { type: 'function_call', arguments: 'PRIVATE' } } },
    { usage: { ...commonMetadata().usage, attribution: null } },
    { usage: { ...commonMetadata().usage, attribution: [] } },
    { usage: { ...commonMetadata().usage, attribution: { input_tokens: 0 } } },
    { usage: { ...commonMetadata().usage, attribution: { hidden: 'PRIVATE' } } },
  ]) {
    for (const stage of ['response.created', 'response.in_progress', 'response.completed']) {
      const events = eventsWithMetadata();
      Object.assign(events.find(event => event.type === stage).response, patch);
      rejectsWithoutOutput(sse(events));
    }
  }
});

test('closed zero tool counters and inert per-item attribution are stripped from every snapshot', () => {
  const events = eventsWithMetadata();
  for (const event of events) if (event.response) {
    event.response.tool_usage = { image_gen: { input_tokens: 0, output_tokens: 0, total_tokens: 0,
      input_tokens_details: { text_tokens: 0, image_tokens: 0 }, output_tokens_details: { image_tokens: 0 } },
    web_search: { num_requests: 0 } };
    if (event.response.usage) event.response.usage.attribution = {
      items: { PRIVATE_ID: { input_tokens: 13, cached_tokens: 2, cache_write_tokens: 0,
        input_tokens_details: { cached_tokens: 2 }, content: [{ input_tokens: 13, cached_tokens: 2 }] } },
      request_fields: { instructions: { input_tokens: 3, cached_tokens: 0, cache_write_tokens: 0 } },
    };
  }
  const output = createTextOnlyResponseTextGateForTest(events).finish();
  assert.equal(output.includes('PRIVATE'), false);
  assert.deepEqual(output, createTextOnlyResponseTextGateForTest(eventsFor('P6_TEXT_GATE_OK', { includeReasoning: false })).finish());
});

test('nonzero tool usage, arbitrary attribution content and malformed or excessive maps fail closed', () => {
  const patches = [
    { tool_usage: { image_gen: { input_tokens: 1 } } }, { tool_usage: { image_gen: { total_tokens: -1 } } },
    { tool_usage: { image_gen: { output_tokens_details: { image_tokens: 1 } } } },
    { tool_usage: { web_search: { num_requests: 1 } } }, { tool_usage: { web_search: { num_requests: '0' } } },
    { tool_usage: { image_gen: { unknown: 0 } } }, { tool_usage: { computer: {} } },
  ];
  for (const attribution of [
    { items: [] }, { items: null }, { items: { '../path': {} } }, { items: { item: { input_tokens: 'PRIVATE' } } },
    { items: { item: { type: 'function_call', arguments: 'PRIVATE' } } },
    { items: { item: { input_tokens_details: { hidden: 0 } } } },
    { items: { item: { input_tokens_details: null } } },
    { items: { item: { output_tokens: 0.5 } } }, { request_fields: { tools: {} } },
    { items: { item: { cached_tokens: 'PRIVATE' } } }, { items: { item: { cache_write_tokens: -1 } } },
    { items: { item: { content: 'PRIVATE' } } }, { items: { item: { content: [{ text: 'PRIVATE' }] } } },
    { items: { item: { content: [{ type: 'function_call', arguments: 'PRIVATE' }] } } },
    { items: { item: { content: [{ content: [] }] } } },
    { items: { item: { content: Array.from({ length: 65 }, () => ({ input_tokens: 0 })) } } },
    { request_fields: { instructions: { input_tokens: -1 } } },
    { items: Object.fromEntries(Array.from({ length: 65 }, (_, i) => [`item_${i}`, {}])) },
  ]) patches.push({ usage: { ...commonMetadata().usage, attribution } });
  for (const patch of patches) {
    const events = eventsWithMetadata(); Object.assign(events.at(-1).response, patch);
    rejectsWithoutOutput(sse(events));
  }
});
