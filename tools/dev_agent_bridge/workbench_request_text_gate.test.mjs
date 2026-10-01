import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeTextOnlyRequest, TextOnlyRequestError } from './workbench_request_text_gate.mjs';
const model = 'synthetic-text-model';
const base = () => ({ model, input: [{ type: 'message', role: 'user', content: [{ type: 'input_text', text: '中文文字 {"type":"function_call"}' }] }] });
const normalize = body => normalizeTextOnlyRequest(body, { model });
test('reconstructs text context and removes both tool catalogs and hidden metadata', () => {
  const body = base();
  body.tools = [{ type: 'web_search' }, { type: 'function', name: 'write' }];
  body.input.unshift({ type: 'additional_tools', id: 'ignore', role: 'developer', tools: [{ type: 'namespace', name: 'functions', tools: [{ name: 'exec' }] }] });
  Object.assign(body, { tool_choice: 'required', parallel_tool_calls: true, store: true, stream: false,
    include: ['unexpected'], text: { format: { type: 'json_schema' } }, client_metadata: { hidden: 'value' }, prompt_cache_key: 'cache',
    reasoning: { effort: 'high', context: 'all_turns', summary: 'auto' } });
  const normalized = normalize(body);
  assert.deepEqual(normalized.tools, []);
  assert.equal(normalized.tool_choice, 'none');
  assert.equal(normalized.parallel_tool_calls, false);
  assert.equal(normalized.store, false);
  assert.equal(normalized.stream, true);
  assert.deepEqual(normalized.input, base().input);
  assert.deepEqual(normalized.reasoning, { effort: 'high', summary: 'auto' });
  for (const key of ['include', 'text', 'client_metadata', 'prompt_cache_key']) assert.equal(Object.hasOwn(normalized, key), false);
  normalized.input[0].content[0].text = 'changed';
  assert.notEqual(body.input[1].content[0].text, 'changed');
});
test('normalizes assistant messages without retaining provider item IDs', () => {
  const body = base();
  body.input.push({ type: 'message', id: 'provider-item', status: 'completed', role: 'assistant', content: [{ type: 'output_text', text: 'answer', annotations: [] }] });
  assert.deepEqual(normalize(body).input[1], { type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'answer' }] });
});
for (const [name, mutate] of [
  ['server history', b => { b.previous_response_id = 'resp_old'; }],
  ['conversation reference', b => { b.conversation = 'old'; }],
  ['function call', b => { b.input.push({ type: 'function_call', name: 'write', arguments: '{}' }); }],
  ['tool output', b => { b.input.push({ type: 'function_call_output', call_id: 'old', output: 'value' }); }],
  ['hidden tool content', b => { b.input[0].content.push({ type: 'input_image', image_url: 'https://invalid.example' }); }],
  ['unknown message field', b => { b.input[0].tools = [{ type: 'web_search' }]; }],
  ['annotated content', b => { b.input[0].content[0].annotations = [{ type: 'file_citation' }]; }],
  ['model override', b => { b.model = 'other'; }],
  ['unknown reasoning', b => { b.reasoning = { tools: [] }; }],
  ['empty context', b => { b.input = []; }],
]) test(`rejects ${name} before returning an upstream request`, () => {
  const body = base(); mutate(body);
  assert.throws(() => normalize(body), TextOnlyRequestError);
});
test('bounds request bytes, message count and output tokens', () => {
  assert.throws(() => normalizeTextOnlyRequest(base(), { model, maxBytes: 20 }), /request_too_large/);
  assert.throws(() => normalizeTextOnlyRequest({ ...base(), input: [...base().input, ...base().input] }, { model, maxMessages: 1 }), /input_shape/);
  assert.throws(() => normalize({ ...base(), max_output_tokens: 32769 }), /output_limit/);
});
