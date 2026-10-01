import test from 'node:test';
import assert from 'node:assert/strict';
import { inspectRejectedTextResponse, isRejectedTextResponseDiagnostic } from './workbench_response_text_diagnostics.mjs';

const inspect = value => inspectRejectedTextResponse(Buffer.from(value));
test('attribution content diagnostics inspect only one bounded array level and never values', () => {
  const value = { usage: { attribution: { items: { orders: { content: Array.from({ length: 70 }, () => ({
    input_tokens: 12345, content_index: 0, secret: 'PRIVATE', nested: { hidden: 'PRIVATE' },
  })) } } } } };
  const input = Buffer.from(JSON.stringify(value));
  const report = inspectRejectedTextResponse(input, { includeProtocolKeys: true });
  const content = report.protocol_keys.attribution_items_usage.content_counts;
  assert.equal(content.direct_object_count, 64); assert.equal(content.omitted_item_count, 6);
  assert.equal(Object.hasOwn(content, 'content_counts'), false);
  assert.deepEqual(content.protocol_fields.fields.map(f => f.name), ['content_index', 'nested']);
  for (const marker of ['orders', 'PRIVATE', 'hidden', '12345']) assert.equal(JSON.stringify(report).includes(marker), false);
  assert.equal(Object.hasOwn(inspectRejectedTextResponse(input), 'protocol_keys'), false);
});
test('attribution value protocol fields remain bounded and never reveal map identifiers or values', () => {
  const value = { usage: { attribution: { items: { customer_record: { input_tokens_cached: 17,
    output_tokens_reasoning: 19, is_output: true, private_value: 'PRIVATE', nested: { hidden: 'PRIVATE' } } } } } };
  const input = Buffer.from(JSON.stringify(value));
  const report = inspectRejectedTextResponse(input, { includeProtocolKeys: true });
  const aggregate = report.protocol_keys.attribution_items_usage;
  assert.deepEqual(aggregate.protocol_fields.fields, [
    { name: 'is_output', types: ['boolean'] }, { name: 'nested', types: ['object'] },
  ]);
  assert.deepEqual(aggregate.fields.map(field => field.name), ['input_tokens_cached', 'output_tokens_reasoning']);
  for (const marker of ['customer_record', 'PRIVATE', 'hidden', '17', '19']) assert.equal(JSON.stringify(report).includes(marker), false);
  assert.equal(JSON.stringify(inspectRejectedTextResponse(input)).includes('is_output'), false);
});
const frame = event => `event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`;
const response = () => ({
  id: 'PRIVATE_ID', object: 'response', model: 'PRIVATE_MODEL', created_at: 987654321, status: 'PRIVATE_STATUS',
  usage: { PRIVATE_USAGE_KEY: 987654321 }, metadata: { PRIVATE_META_KEY: 'PRIVATE_VALUE' },
  tools: [{ type: 'PRIVATE_TOOL', name: 'PRIVATE_NAME' }], tool_choice: 'PRIVATE_CHOICE', service_tier: 'PRIVATE_TIER',
  output: [{ id: 'PRIVATE_MSG', type: 'message', role: 'PRIVATE_ROLE', status: 'PRIVATE_STATUS',
    content: [{ type: 'output_text', text: 'PRIVATE_TEXT' }] },
  { id: 'PRIVATE_REASONING_ID', type: 'reasoning', summary: [{ type: 'summary_text', text: 'PRIVATE_REASONING' }],
    encrypted_content: 'PRIVATE_CIPHERTEXT' }],
});
function safe(report) {
  const encoded = JSON.stringify(report);
  assert.equal(encoded.includes('PRIVATE'), false);
  assert.equal(encoded.includes('987654321'), false);
  assert.equal(report.diagnostic_only, true);
  for (const key of ['passed', 'accepted', 'released', 'text', 'body']) assert.equal(Object.hasOwn(report, key), false);
}
test('JSON metadata without Content-Type yields only known fields, fixed shapes and counts', () => {
  const report = inspect(JSON.stringify(response())); safe(report);
  assert.equal(report.format, 'json'); assert.equal(report.error, null); assert.equal(report.frame_count, 0);
  assert.equal(report.response_count, 1); assert.equal(report.output_item_count, 2);
  for (const key of ['created_at', 'model', 'usage', 'metadata', 'tools', 'tool_choice', 'service_tier']) assert.ok(report.response_known_fields.includes(key));
  assert.deepEqual(report.response_field_shapes.created_at, ['number']);
  assert.deepEqual(report.response_field_shapes.metadata, ['object']);
  assert.deepEqual(report.output_items.map(item => item.type), ['message', 'reasoning']);
  assert.deepEqual(report.output_items[1].field_shapes.encrypted_content, ['string']);
});
test('SSE counts fixed event vocabulary and metadata while dropping text and encrypted content', () => {
  const data = frame({ type: 'response.created', response: { ...response(), output: [] } })
    + frame({ type: 'response.output_text.delta', item_id: 'PRIVATE_ID', delta: 'PRIVATE_DELTA', sequence_number: 987654321 })
    + frame({ type: 'response.output_item.done', item: response().output[0] })
    + frame({ type: 'response.completed', response: response() }) + 'data: [DONE]\n\n';
  const report = inspect(data.replaceAll('\n', '\r\n')); safe(report);
  assert.equal(report.format, 'sse'); assert.equal(report.error, null); assert.equal(report.frame_count, 5);
  assert.equal(report.known_event_counts['response.completed'], 1);
  assert.equal(report.known_event_counts['response.output_text.delta'], 1);
  assert.equal(report.response_count, 2); assert.equal(report.output_item_count, 3);
});
test('unknown provider field names, event names and item types are counted without disclosure', () => {
  const value = response(); value.PRIVATE_UNKNOWN_FIELD = { PRIVATE_NESTED: 'PRIVATE' };
  value.output.push({ type: 'PRIVATE_TYPE', PRIVATE_ITEM_KEY: 'PRIVATE_VALUE', id: 'PRIVATE_ID' });
  const report = inspect(frame({ type: 'PRIVATE_EVENT', response: value })); safe(report);
  assert.equal(report.unknown_event_count, 1); assert.deepEqual(report.known_event_counts, {});
  assert.equal(report.response_unknown_field_count, 1); assert.equal(report.unknown_item_type_count, 1);
  assert.equal(report.output_items.find(item => item.type === 'unknown').unknown_field_count, 1);
});
test('known fields aggregate only finite schema shape categories', () => {
  const values = [null, 'PRIVATE', 987654321, true, ['PRIVATE'], { PRIVATE_KEY: 'PRIVATE' }];
  const report = inspect(values.map(value => frame({ type: 'response.completed', response: { metadata: value } })).join(''));
  safe(report); assert.equal(report.error, null);
  assert.deepEqual(report.response_field_shapes.metadata, ['array', 'boolean', 'null', 'number', 'object', 'string']);
});

test('fixed nested protocol paths classify fields while masking arbitrary keys and values', () => {
  const report = inspect(JSON.stringify({ reasoning: { effort: 'PRIVATE', PRIVATE_KEY: 'PRIVATE' },
    text: { format: { type: 'PRIVATE', schema: { PRIVATE_KEY: 'PRIVATE' } }, verbosity: 'PRIVATE' },
    usage: { input_tokens: 987654321, input_tokens_details: { cached_tokens: 987654321, cache_write_tokens: 987654321 },
      output_tokens_details: { reasoning_tokens: 987654321 } },
    prompt_cache_options: { mode: 'PRIVATE', comparison_response_id: 'PRIVATE' },
  }));
  safe(report);
  assert.equal(report.response_nested_fields.reasoning.unknown_field_count, 1);
  assert.deepEqual(report.response_nested_fields['text.format'].known_fields, ['schema', 'type']);
  assert.equal(report.response_nested_fields['text.format'].unknown_field_count, 0);
  assert.deepEqual(report.response_nested_fields['usage.input_tokens_details'].known_fields, ['cache_write_tokens', 'cached_tokens']);
});
test('does not traverse nested usage, content, metadata or encrypted content', () => {
  const trap = { type: 'PRIVATE_EVENT', response: { PRIVATE_FIELD: 'PRIVATE' }, item: { type: 'PRIVATE_ITEM' } };
  const report = inspect(JSON.stringify({ usage: trap, metadata: trap,
    output: [{ type: 'reasoning', encrypted_content: JSON.stringify(trap), content: [trap], summary: [trap] }] }));
  safe(report); assert.equal(report.error, null); assert.equal(report.response_count, 1);
  assert.equal(report.output_item_count, 1); assert.equal(report.unknown_event_count, 0);
  assert.equal(report.response_unknown_field_count, 0); assert.equal(report.unknown_item_type_count, 0);
});
test('mismatched event labels never promote arbitrary provider names into vocabulary', () => {
  const report = inspect('event: PRIVATE_EVENT\ndata: {"type":"response.completed"}\n\n'
    + 'event: response.completed\ndata: {"type":"PRIVATE_EVENT"}\n\n');
  safe(report); assert.equal(report.unknown_event_count, 2); assert.deepEqual(report.known_event_counts, {});
});
test('standard SSE data-only frames, comments and multiline JSON stay bounded and private', () => {
  const report = inspect(': PRIVATE_COMMENT\n\ndata: {\ndata: "type":"response.completed",\ndata: "response":{"metadata":{"PRIVATE":"PRIVATE"}}}\n\n');
  safe(report); assert.equal(report.error, null); assert.equal(report.frame_count, 2);
  assert.equal(report.known_event_counts['response.completed'], 1);
});
test('invalid formats, JSON, SSE truncation and invalid UTF-8 return only constant failures', () => {
  for (const [input, error] of [
    ['', 'empty_input'], ['PRIVATE_TEXT', 'unrecognized_format'], ['{"PRIVATE":', 'invalid_json'],
    ['["PRIVATE"]', 'invalid_shape'], ['data: {"type":"PRIVATE"}\n', 'truncated_sse'],
    ['data: PRIVATE\n\n', 'invalid_json'], ['event: PRIVATE\nevent: PRIVATE\ndata: {}\n\n', 'invalid_sse'],
    ['data: []\n\n', 'invalid_shape'], ['data: {}\r\n\r', 'invalid_sse'],
  ]) {
    const report = inspect(input); safe(report); assert.equal(report.error, error);
    assert.equal(report.frame_count, 0); assert.equal(report.response_count, 0); assert.deepEqual(report.output_items, []);
  }
  const malformed = inspectRejectedTextResponse(Buffer.from([0xc3, 0x28])); safe(malformed);
  assert.equal(malformed.error, 'invalid_utf8');
});
test('only Buffer inputs up to 256 KiB and at most 256 frames are inspected', () => {
  for (const input of ['PRIVATE', new Uint8Array([1]), null, { PRIVATE_KEY: 'PRIVATE' }]) {
    const report = inspectRejectedTextResponse(input); safe(report); assert.equal(report.error, 'invalid_input');
  }
  const oversized = inspectRejectedTextResponse(Buffer.alloc(256 * 1024 + 1, 120)); safe(oversized);
  assert.equal(oversized.error, 'input_limit');
  const exact = Buffer.from(JSON.stringify({ metadata: 'x'.repeat(256 * 1024 - 15) }));
  assert.equal(exact.length, 256 * 1024);
  assert.equal(inspectRejectedTextResponse(exact).error, null);
  const event = frame({ type: 'response.output_text.delta', delta: 'PRIVATE' });
  const atLimit = inspect(event.repeat(256)); safe(atLimit); assert.equal(atLimit.frame_count, 256);
  const beyond = inspect(event.repeat(257)); safe(beyond); assert.equal(beyond.error, 'frame_limit');
  assert.equal(beyond.frame_count, 0);
});
test('protocol-key mode discloses only bounded safe unknown root and usage names with types', () => {
  const report = inspectRejectedTextResponse(Buffer.from(JSON.stringify({
    safe_protocol_field: 'PRIVATE_VALUE',
    another_protocol_field: 42,
    usage: { safe_usage_field: null, another_usage_field: ['PRIVATE_VALUE'] },
    metadata: { nested_private_field: 'PRIVATE_VALUE' },
  })), { includeProtocolKeys: true });
  safe(report);
  assert.deepEqual(report.protocol_keys.response.fields, [
    { name: 'another_protocol_field', types: ['number'] },
    { name: 'safe_protocol_field', types: ['string'] },
  ]);
  assert.deepEqual(report.protocol_keys.usage.fields, [
    { name: 'another_usage_field', types: ['array'] },
    { name: 'safe_usage_field', types: ['null'] },
  ]);
  assert.equal(JSON.stringify(report).includes('PRIVATE_VALUE'), false);
  assert.equal(Object.isFrozen(report.protocol_keys), true);
});
test('protocol-key mode filters sensitive names, bounds each layer, and never traverses other nested data', () => {
  const responseFields = Object.fromEntries(Array.from({ length: 17 }, (_, index) => [`field_${String.fromCharCode(97 + index)}`, index]));
  const usageFields = Object.fromEntries(Array.from({ length: 17 }, (_, index) => [`usage_${String.fromCharCode(97 + index)}`, index]));
  const report = inspectRejectedTextResponse(Buffer.from(JSON.stringify({
    ...responseFields,
    auth_marker: 'PRIVATE', session_marker: 'PRIVATE', api_marker: 'PRIVATE',
    metadata: { safe_nested_but_unread: 'PRIVATE' },
    output: [{ type: 'message', content: [{ type: 'output_text', text: 'PRIVATE' }] }],
    usage: { ...usageFields, token_marker: 'PRIVATE', nested: { safe_nested_but_unread: 'PRIVATE' } },
  })), { includeProtocolKeys: true });
  safe(report);
  assert.equal(report.protocol_keys.response.fields.length, 16);
  assert.equal(report.protocol_keys.response.omitted_field_count, 1);
  assert.equal(report.protocol_keys.response.filtered_field_count, 3);
  assert.equal(report.protocol_keys.usage.fields.length, 16);
  assert.equal(report.protocol_keys.usage.omitted_field_count, 2);
  assert.equal(report.protocol_keys.usage.filtered_field_count, 1);
  assert.equal(JSON.stringify(report).includes('safe_nested_but_unread'), false);
  assert.equal(JSON.stringify(report).includes('PRIVATE'), false);
});
test('protocol-key mode is opt-in and rejects invalid options without a partial schema report', () => {
  const source = Buffer.from(JSON.stringify({ safe_protocol_field: 'PRIVATE' }));
  const defaultReport = inspectRejectedTextResponse(source);
  safe(defaultReport); assert.equal(Object.hasOwn(defaultReport, 'protocol_keys'), false);
  const invalid = inspectRejectedTextResponse(source, { includeProtocolKeys: 'true' });
  safe(invalid); assert.equal(invalid.error, 'invalid_options');
  assert.equal(Object.hasOwn(invalid, 'protocol_keys'), false);
});
test('new fixed shallow protocol paths reveal safe unknown names only in opt-in mode', () => {
  const source = Buffer.from(JSON.stringify({
    frequency_penalty: 0.5,
    presence_penalty: -0.5,
    tool_usage: { safe_tool_field: true, token_marker: 'PRIVATE', nested: { private_value: 'PRIVATE' } },
    usage: { attribution: { safe_attribution_field: 1, secret_marker: 'PRIVATE', nested: { private_value: 'PRIVATE' } } },
  }));
  const defaultReport = inspectRejectedTextResponse(source);
  safe(defaultReport);
  assert.equal(Object.hasOwn(defaultReport, 'protocol_keys'), false);
  assert.equal(defaultReport.response_unknown_field_count, 0);
  assert.equal(defaultReport.response_nested_fields.tool_usage.unknown_field_count, 3);
  assert.equal(defaultReport.response_nested_fields['usage.attribution'].unknown_field_count, 3);
  assert.equal(JSON.stringify(defaultReport).includes('safe_tool_field'), false);
  const report = inspectRejectedTextResponse(source, { includeProtocolKeys: true });
  safe(report);
  assert.deepEqual(report.protocol_keys.tool_usage.fields, [
    { name: 'nested', types: ['object'] }, { name: 'safe_tool_field', types: ['boolean'] },
  ]);
  assert.deepEqual(report.protocol_keys.usage_attribution.fields, [
    { name: 'nested', types: ['object'] }, { name: 'safe_attribution_field', types: ['number'] },
  ]);
  assert.equal(report.protocol_keys.tool_usage.filtered_field_count, 1);
  assert.equal(report.protocol_keys.usage_attribution.filtered_field_count, 1);
  assert.equal(JSON.stringify(report).includes('private_value'), false);
  assert.equal(JSON.stringify(report).includes('PRIVATE'), false);
  assert.equal(Object.isFrozen(report.protocol_keys.tool_usage), true);
  assert.equal(isRejectedTextResponseDiagnostic(report), true);
});
test('observed tool and attribution child paths are fixed, shallow, opt-in only, and private', () => {
  const source = Buffer.from(JSON.stringify({
    tool_usage: {
      image_gen: { safe_image_field: 'PRIVATE', token_marker: 'PRIVATE', nested: { private_value: 'PRIVATE' } },
      web_search: { safe_search_field: false, secret_marker: 'PRIVATE', nested: { private_value: 'PRIVATE' } },
    },
    usage: { attribution: {
      items: { customer_record: { input_tokens: 2 }, orders: { output_tokens: 3 } },
      request_fields: { safe_request_field: null, account_marker: 'PRIVATE', nested: { private_value: 'PRIVATE' } },
    } },
  }));
  const defaultReport = inspectRejectedTextResponse(source);
  safe(defaultReport);
  assert.equal(Object.hasOwn(defaultReport, 'protocol_keys'), false);
  for (const path of ['tool_usage', 'tool_usage.image_gen', 'tool_usage.web_search', 'usage.attribution', 'usage.attribution.items', 'usage.attribution.request_fields'])
    assert.ok(Object.hasOwn(defaultReport.response_nested_fields, path));
  assert.equal(JSON.stringify(defaultReport).includes('safe_image_field'), false);
  const report = inspectRejectedTextResponse(source, { includeProtocolKeys: true });
  safe(report);
  for (const [key, name, type] of [
    ['tool_usage_image_gen', 'safe_image_field', 'string'], ['tool_usage_web_search', 'safe_search_field', 'boolean'],
    ['usage_attribution_request_fields', 'safe_request_field', 'null'],
  ]) {
    assert.deepEqual(report.protocol_keys[key].fields, [
      { name: 'nested', types: ['object'] }, { name, types: [type] },
    ]);
    assert.equal(report.protocol_keys[key].filtered_field_count, 1);
  }
  assert.equal(JSON.stringify(report).includes('private_value'), false);
  assert.equal(JSON.stringify(report).includes('PRIVATE'), false);
  assert.equal(JSON.stringify(report).includes('customer_record'), false);
  assert.equal(JSON.stringify(report).includes('orders'), false);
});
test('fixed usage paths disclose only public counters and attribution items aggregate values without map keys', () => {
  const items = Object.fromEntries([
    ['customer_record', { input_tokens: 0, output_tokens: 1, token_marker: 'PRIVATE', nested: { private_value: 'PRIVATE' } }],
    ['orders', 'PRIVATE_NON_OBJECT'],
    ...Array.from({ length: 64 }, (_, index) => [
      `PRIVATE_DYNAMIC_ACCOUNT_${index}`,
      { input_tokens: index, output_tokens: index + 1, token_marker: 'PRIVATE', nested: { private_value: 'PRIVATE' } },
    ]),
  ]);
  const source = Buffer.from(JSON.stringify({
    tool_usage: { image_gen: { input_tokens: 1, image_tokens: 2, input_tokens_details: { cached_tokens: 3, text_tokens: 4, image_tokens: 5 }, output_tokens_details: { text_tokens: 6 } } },
    usage: { attribution: {
      request_fields: { instructions: { total_tokens: 5, input_tokens_details: { cache_write_tokens: 6 }, output_tokens_details: { reasoning_tokens: 7 } } },
      items,
    } },
  }));
  const defaultReport = inspectRejectedTextResponse(source);
  safe(defaultReport); assert.equal(Object.hasOwn(defaultReport, 'protocol_keys'), false);
  const report = inspectRejectedTextResponse(source, { includeProtocolKeys: true });
  safe(report);
  assert.deepEqual(report.protocol_keys.image_gen_usage.fields, [
    { name: 'image_tokens', types: ['number'] }, { name: 'input_tokens', types: ['number'] }, { name: 'input_tokens_details', types: ['object'] }, { name: 'output_tokens_details', types: ['object'] },
  ]);
  assert.deepEqual(report.protocol_keys.image_gen_input_token_details.fields, [
    { name: 'cached_tokens', types: ['number'] }, { name: 'image_tokens', types: ['number'] }, { name: 'text_tokens', types: ['number'] },
  ]);
  assert.deepEqual(report.protocol_keys.image_gen_output_token_details.fields, [{ name: 'text_tokens', types: ['number'] }]);
  assert.deepEqual(report.protocol_keys.request_field_instructions.fields, [
    { name: 'input_tokens_details', types: ['object'] }, { name: 'output_tokens_details', types: ['object'] }, { name: 'total_tokens', types: ['number'] },
  ]);
  assert.deepEqual(report.protocol_keys.request_field_instructions_input_token_details.fields, [{ name: 'cache_write_tokens', types: ['number'] }]);
  assert.deepEqual(report.protocol_keys.request_field_instructions_output_token_details.fields, [{ name: 'reasoning_tokens', types: ['number'] }]);
  const aggregate = report.protocol_keys.attribution_items_usage;
  assert.deepEqual(aggregate.fields, [
    { name: 'input_tokens', types: ['number'] }, { name: 'output_tokens', types: ['number'] },
  ]);
  assert.equal(aggregate.direct_object_count, 63);
  assert.equal(aggregate.omitted_item_count, 2);
  assert.deepEqual(aggregate.non_object_value_shapes, ['string']);
  assert.equal(aggregate.filtered_field_count, 63);
  assert.equal(JSON.stringify(report).includes('PRIVATE_DYNAMIC_ACCOUNT'), false);
  assert.equal(JSON.stringify(report).includes('customer_record'), false);
  assert.equal(JSON.stringify(report).includes('orders'), false);
  assert.equal(JSON.stringify(report).includes('private_value'), false);
  assert.equal(JSON.stringify(report).includes('PRIVATE'), false);
});
test('item count limit and parse failures discard partial diagnostics', () => {
  const many = inspect(JSON.stringify({ output: Array.from({ length: 1025 }, () => ({ type: 'message' })) }));
  safe(many); assert.equal(many.error, 'item_limit'); assert.equal(many.output_item_count, 0);
  const partial = inspect(frame({ type: 'response.completed', response: response() }) + 'data: PRIVATE\n\n');
  safe(partial); assert.equal(partial.error, 'invalid_json'); assert.equal(partial.response_count, 0);
});
test('only module-created deeply frozen success/error diagnostics carry the private marker', () => {
  const report = inspect(JSON.stringify(response()));
  const failed = inspect('PRIVATE_INVALID');
  for (const value of [report, failed]) {
    assert.equal(isRejectedTextResponseDiagnostic(value), true);
    const checkFrozen = current => {
      if (current !== null && typeof current === 'object') {
        assert.equal(Object.isFrozen(current), true);
        for (const child of Object.values(current)) checkFrozen(child);
      }
    };
    checkFrozen(value);
    assert.throws(() => { value.PRIVATE_KEY = 'PRIVATE'; }, TypeError);
  }
  assert.throws(() => report.response_known_fields.push('PRIVATE'), TypeError);
  assert.throws(() => { report.output_items[0].type = 'PRIVATE'; }, TypeError);
  assert.throws(() => report.output_items[0].field_shapes.id.push('PRIVATE'), TypeError);
  for (const forged of [null, 'PRIVATE', {}, { diagnostic_only: true, PRIVATE_KEY: 'PRIVATE' },
    JSON.parse(JSON.stringify(report)), Object.freeze({ ...report }), Object.create(report), new Proxy(report, {})])
    assert.equal(isRejectedTextResponseDiagnostic(forged), false);
  safe(report); safe(failed);
});
