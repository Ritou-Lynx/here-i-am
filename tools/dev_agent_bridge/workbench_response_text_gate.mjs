import { createHash } from 'node:crypto';

// Fixed public event names used only to classify rejected SSE frames. This table
// never expands the accepted response gate surface.
const PUBLIC_RESPONSE_EVENT_KINDS = new Set([
  'response.queued', 'response.failed', 'response.incomplete',
  'codex.rate_limits', 'codex.response.metadata', 'response.metadata', 'responsesapi.websocket_timing',
  'response.refusal.delta', 'response.refusal.done', 'response.output_text.annotation.added',
  'response.function_call_arguments.delta', 'response.function_call_arguments.done',
  'response.custom_tool_call_input.delta', 'response.custom_tool_call_input.done',
  'response.web_search_call.in_progress', 'response.web_search_call.searching', 'response.web_search_call.completed',
  'response.file_search_call.in_progress', 'response.file_search_call.searching', 'response.file_search_call.completed',
  'response.code_interpreter_call.in_progress', 'response.code_interpreter_call.interpreting', 'response.code_interpreter_call.completed',
  'response.mcp_call.in_progress', 'response.mcp_call_arguments.delta', 'response.mcp_call_arguments.done',
  'response.mcp_call.completed', 'response.mcp_call.failed',
  'response.mcp_list_tools.in_progress', 'response.mcp_list_tools.completed', 'response.mcp_list_tools.failed',
  'response.code_interpreter_call_code.delta', 'response.code_interpreter_call_code.done',
  'response.image_generation_call.in_progress', 'response.image_generation_call.generating',
  'response.image_generation_call.partial_image', 'response.image_generation_call.completed',
  'response.audio.delta', 'response.audio.done',
  'response.audio.transcript.delta', 'response.audio.transcript.done',
  'response.shell_call_command.added', 'response.shell_call_command.delta', 'response.shell_call_command.done',
  'response.shell_call_output_content.delta', 'response.shell_call_output_content.done',
  'error',
]);

export function classifyUnsupportedResponseEventKind(value) {
  return typeof value === 'string' && PUBLIC_RESPONSE_EVENT_KINDS.has(value) ? value : 'other';
}

// Null means no rejected-event diagnostic was supplied. Every supplied value
// outside the static table is collapsed to `other`, with no coercion.
export function sanitizeTextResponseEventKind(value) {
  if (value === null || value === undefined) return null;
  return typeof value === 'string' && (value === 'other' || PUBLIC_RESPONSE_EVENT_KINDS.has(value)) ? value : 'other';
}

const RESPONSE_EVENT_TYPE_CLASSES = new Set([
  'non_object', 'missing', 'null', 'nonstring', 'response_namespace',
  'codex_namespace', 'responsesapi_namespace', 'other_namespace',
]);
const RESPONSE_EVENT_PHASES = new Set([
  'before_created', 'after_created', 'after_output_started', 'after_text',
]);
const RESPONSE_EVENT_HEADER_RELATIONS = new Set([
  'absent', 'equals_payload_type', 'differs_from_payload_type',
]);
const RESPONSE_EVENT_PAYLOAD_SHAPES = new Set([
  'non_object', 'type_only', 'type_plus_response', 'type_plus_item', 'type_plus_other_fields',
]);
// Hypotheses only: this static list classifies an already rejected frame. It
// does not expand EVENTS or authorize any response.
const RESPONSE_EVENT_CONTROL_KINDS = new Set([
  'ping', 'pong', 'keepalive', 'heartbeat', 'done', 'message', 'message_start', 'message_stop',
  'content_block_start', 'content_block_delta', 'content_block_stop', 'message_delta', 'completion',
  'usage', 'rate_limits', 'rate_limits.updated', 'metadata', 'warning', 'server_error',
  'invalid_request_error', 'stream_end', 'stream_complete', 'stream.completed', 'stream.done', 'delta',
  'final', 'session.created', 'session.updated', 'thread.started', 'turn.started', 'turn.completed',
  'item.started', 'item.completed', 'title_generation', 'conversation_detail_metadata',
  'message_stream_complete', 'resume_conversation_token', 'server_ste_metadata',
]);

export function classifyUnsupportedResponseEventTypeClass(event) {
  if (event === null || typeof event !== 'object' || Array.isArray(event)) return 'non_object';
  if (!Object.hasOwn(event, 'type')) return 'missing';
  if (event.type === null) return 'null';
  if (typeof event.type !== 'string') return 'nonstring';
  if (event.type.startsWith('response.')) return 'response_namespace';
  if (event.type.startsWith('codex.')) return 'codex_namespace';
  if (event.type.startsWith('responsesapi.')) return 'responsesapi_namespace';
  return 'other_namespace';
}

export function sanitizeTextResponseEventTypeClass(value) {
  return typeof value === 'string' && RESPONSE_EVENT_TYPE_CLASSES.has(value) ? value : null;
}

export function sanitizeTextResponseEventPhase(value) {
  return typeof value === 'string' && RESPONSE_EVENT_PHASES.has(value) ? value : null;
}

export function sanitizeTextResponseEventHeaderRelation(value) {
  return typeof value === 'string' && RESPONSE_EVENT_HEADER_RELATIONS.has(value) ? value : null;
}

export function sanitizeTextResponseEventPayloadShape(value) {
  return typeof value === 'string' && RESPONSE_EVENT_PAYLOAD_SHAPES.has(value) ? value : null;
}

export function classifyUnsupportedResponseEventControlKind(value) {
  return typeof value === 'string' && RESPONSE_EVENT_CONTROL_KINDS.has(value) ? value : 'other';
}

export function sanitizeTextResponseEventControlKind(value) {
  if (value === null || value === undefined) return null;
  return typeof value === 'string' && (value === 'other' || RESPONSE_EVENT_CONTROL_KINDS.has(value)) ? value : 'other';
}

function responseEventHeaderRelation(eventName, event) {
  if (eventName === null) return 'absent';
  return eventName === event?.type ? 'equals_payload_type' : 'differs_from_payload_type';
}

function responseEventPayloadShape(event) {
  if (event === null || typeof event !== 'object' || Array.isArray(event)) return 'non_object';
  const keys = Object.keys(event);
  if (keys.length === 1 && keys[0] === 'type') return 'type_only';
  if (Object.hasOwn(event, 'response')) return 'type_plus_response';
  if (Object.hasOwn(event, 'item')) return 'type_plus_item';
  return 'type_plus_other_fields';
}

function responseEventPhase(created, items) {
  if (items.some(entry => entry.added.type === 'message'
    && entry.parts.some(part => typeof part.text === 'string' && part.text.length > 0))) return 'after_text';
  if (items.length > 0) return 'after_output_started';
  return created !== null ? 'after_created' : 'before_created';
}// Candidate strict subset; see P6_R6_RESPONSE_GATE_HANDOFF.md. No network/auth IO.
const DEFAULT_INPUT_BYTES = 1024 * 1024;
const DEFAULT_OUTPUT_BYTES = 2 * 1024 * 1024;
const MAX_ITEMS = 64;
const MAX_PARTS = 64;
const MAX_JSON_DEPTH = 32;
const MAX_JSON_NODES = 65_536;
const EVENTS = new Set([
  'keepalive',
  'response.created', 'response.in_progress', 'response.completed',
  'response.output_item.added', 'response.output_item.done',
  'response.content_part.added', 'response.content_part.done',
  'response.output_text.delta', 'response.output_text.done',
  'response.reasoning_summary_part.added', 'response.reasoning_summary_part.done',
  'response.reasoning_summary_text.delta', 'response.reasoning_summary_text.done',
  'response.reasoning_text.delta', 'response.reasoning_text.done',
]);
// Finite response metadata subset, checked against the public OpenAI Python SDK
// on 2026-09-11. These fields are validated and discarded, never forwarded.
const RESPONSE_METADATA_KEYS = [
  'created_at', 'completed_at', 'model', 'instructions', 'usage', 'metadata',
  'tools', 'tool_choice', 'parallel_tool_calls', 'store', 'background',
  'previous_response_id', 'conversation', 'prompt', 'moderation',
  'prompt_cache_diagnostics', 'prompt_cache_options', 'prompt_cache_key', 'prompt_cache_retention',
  'reasoning', 'text', 'max_output_tokens', 'max_tool_calls', 'temperature', 'top_p',
  'top_logprobs', 'truncation', 'service_tier', 'safety_identifier', 'user',
  'usage_metadata', 'end_turn', 'headers',
  'frequency_penalty', 'presence_penalty', 'tool_usage', 'access_programs',
];

export class ResponseTextGateError extends Error {
  constructor(code) {
    super(`Response text gate rejected input: ${code}`);
    this.name = 'ResponseTextGateError';
    this.code = code;
  }
}

function requireThat(condition, code = 'invalid_shape') {
  if (!condition) throw new ResponseTextGateError(code);
}

function shape(value, keys, location = 'unclassified') {
  requireThat(value !== null && typeof value === 'object' && !Array.isArray(value));
  if (!Object.keys(value).every((key) => keys.includes(key))) {
    const error = new ResponseTextGateError('unknown_field');
    error.schemaLocation = location;
    throw error;
  }
}

function string(value, { nonempty = false } = {}) {
  requireThat(typeof value === 'string' && value.isWellFormed());
  requireThat(!nonempty || value.length > 0);
}

function id(value) {
  string(value, { nonempty: true });
  requireThat(value.length <= 200 && /^[A-Za-z0-9_-]+$/.test(value));
}

function index(value) {
  requireThat(Number.isSafeInteger(value) && value >= 0);
}

function finiteNumber(value, minimum, maximum, integer = false) {
  requireThat(typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum
    && (!integer || Number.isSafeInteger(value)), 'invalid_response_metadata');
}
function boundedString(value, maximum, nonempty = false) {
  string(value, { nonempty });
  requireThat(value.length <= maximum, 'invalid_response_metadata');
}
function enumValue(value, choices) {
  requireThat(choices.includes(value), 'invalid_response_metadata');
}
// Local closed subset for inert per-source counters. This is not a claim of
// complete provider-schema support. No string, call, or unknown field survives.
function counterMetadata(value, zeroOnly = false, allowContent = false) {
  const counters = ['input_tokens', 'output_tokens', 'total_tokens', ...(!zeroOnly ? ['cached_tokens', 'cache_write_tokens'] : [])];
  const details = ['cached_tokens', 'cache_write_tokens', 'reasoning_tokens', 'text_tokens', 'image_tokens'];
  const check = v => finiteNumber(v, 0, zeroOnly ? 0 : Number.MAX_SAFE_INTEGER, true);
  shape(value, [...counters, 'input_tokens_details', 'output_tokens_details', ...(allowContent ? ['content'] : [])]);
  for (const key of counters) if (Object.hasOwn(value, key)) check(value[key]);
  for (const key of ['input_tokens_details', 'output_tokens_details']) if (Object.hasOwn(value, key)) {
    shape(value[key], details);
    for (const count of Object.values(value[key])) check(count);
  }
  if (allowContent && Object.hasOwn(value, 'content')) {
    requireThat(Array.isArray(value.content) && value.content.length <= MAX_PARTS, 'invalid_response_metadata');
    for (const part of value.content) counterMetadata(part);
  }
}
function toolUsageMetadata(value) {
  shape(value, ['image_gen', 'web_search']);
  if (Object.hasOwn(value, 'image_gen')) counterMetadata(value.image_gen, true);
  if (Object.hasOwn(value, 'web_search')) {
    shape(value.web_search, ['num_requests']);
    if (Object.hasOwn(value.web_search, 'num_requests')) finiteNumber(value.web_search.num_requests, 0, 0, true);
  }
}
function attributionMetadata(value) {
  shape(value, ['items', 'request_fields']);
  if (Object.hasOwn(value, 'items')) {
    shape(value.items, Object.keys(value.items ?? {}));
    requireThat(Object.keys(value.items).length <= MAX_ITEMS, 'invalid_response_metadata');
    for (const [key, counters] of Object.entries(value.items)) { id(key); counterMetadata(counters, false, true); }
  }
  if (Object.hasOwn(value, 'request_fields')) {
    shape(value.request_fields, ['instructions']);
    if (Object.hasOwn(value.request_fields, 'instructions')) counterMetadata(value.request_fields.instructions);
  }
}
function usageMetadata(value) {
  shape(value, ['input_tokens', 'input_tokens_details', 'output_tokens', 'output_tokens_details', 'total_tokens', 'codex_rollout_budget_units', 'attribution']);
  for (const key of ['input_tokens', 'output_tokens', 'total_tokens']) finiteNumber(value[key], 0, Number.MAX_SAFE_INTEGER, true);
  shape(value.input_tokens_details, ['cached_tokens', 'cache_write_tokens']);
  finiteNumber(value.input_tokens_details.cached_tokens, 0, Number.MAX_SAFE_INTEGER, true);
  // cache_write_tokens is newer SDK metadata; older responses may omit it.
  if (Object.hasOwn(value.input_tokens_details, 'cache_write_tokens'))
    finiteNumber(value.input_tokens_details.cache_write_tokens, 0, Number.MAX_SAFE_INTEGER, true);
  shape(value.output_tokens_details, ['reasoning_tokens']);
  finiteNumber(value.output_tokens_details.reasoning_tokens, 0, Number.MAX_SAFE_INTEGER, true);
  if (value.codex_rollout_budget_units != null) finiteNumber(value.codex_rollout_budget_units, 0, Number.MAX_SAFE_INTEGER);
  if (Object.hasOwn(value, 'attribution')) attributionMetadata(value.attribution);
}
function responseMetadata(value) {
  const present = (key, check, nullable = false) => {
    if (Object.hasOwn(value, key) && !(nullable && value[key] === null)) check(value[key]);
  };
  present('created_at', v => finiteNumber(v, 0, 1e12));
  present('completed_at', v => finiteNumber(v, 0, 1e12), true);
  present('model', v => boundedString(v, 200, true));
  present('instructions', v => boundedString(v, 65536), true);
  present('usage', usageMetadata, true);
  // Codex's public SSE consumer defines these additional transport metadata
  // fields. They are validated and discarded; no header or usage value exits.
  present('usage_metadata', v => {
    shape(v, ['amount', 'metadata']);
    if (v.amount != null) boundedString(v.amount, 1024);
    // metadata is explicitly an opaque JSON Value in the official protocol.
    // strictJson has already enforced UTF-8, duplicate keys, depth and nodes.
  }, true);
  present('headers', v => {
    shape(v, Object.keys(v));
    const entries = Object.entries(v);
    requireThat(entries.length <= 64, 'invalid_response_metadata');
    for (const [name, header] of entries) {
      requireThat(/^[A-Za-z0-9-]{1,128}$/.test(name), 'invalid_response_metadata');
      if (typeof header === 'string') boundedString(header, 8192);
      else {
        requireThat(Array.isArray(header) && header.length <= 16, 'invalid_response_metadata');
        for (const entry of header) boundedString(entry, 8192);
      }
    }
  }, true);
  present('end_turn', v => {
    requireThat(typeof v === 'boolean', 'invalid_response_metadata');
    if (value.status === 'completed') requireThat(v, 'invalid_terminal');
  }, true);
  present('metadata', v => shape(v, []), true);
  // These extension keys were identified by the fixed public live probe.
  // Reported tool counters must all be zero; they are not execution receipts.
  present('tool_usage', toolUsageMetadata);
  // This response-level access label is inert metadata. Only the observed
  // closed shape is accepted, and neither its key nor value is forwarded.
  present('access_programs', v => {
    shape(v, ['cyber']);
    requireThat(Object.hasOwn(v, 'cyber'), 'invalid_response_metadata');
    boundedString(v.cyber, 128, true);
  });
  for (const key of ['frequency_penalty', 'presence_penalty']) present(key, v => finiteNumber(v, -2, 2));
  present('tools', v => requireThat(Array.isArray(v) && v.length === 0, 'invalid_response_metadata'));
  present('tool_choice', v => enumValue(v, ['none']));
  present('parallel_tool_calls', v => enumValue(v, [false]));
  for (const key of ['store', 'background']) present(key, v => enumValue(v, [false]), true);
  for (const key of ['previous_response_id', 'conversation', 'prompt', 'moderation', 'prompt_cache_diagnostics', 'prompt_cache_options'])
    present(key, v => enumValue(v, [null]));
  for (const key of ['prompt_cache_key', 'user']) present(key, v => boundedString(v, 1024), true);
  present('safety_identifier', v => boundedString(v, 64), true);
  present('prompt_cache_retention', v => enumValue(v, ['in_memory', '24h']), true);
  present('reasoning', v => {
    shape(v, ['effort', 'summary', 'generate_summary', 'context', 'mode']);
    if (v.effort != null) enumValue(v.effort, ['none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max', 'ultra']);
    for (const key of ['summary', 'generate_summary']) if (v[key] != null) enumValue(v[key], ['auto', 'concise', 'detailed']);
    if (v.context != null) enumValue(v.context, ['auto', 'current_turn', 'all_turns']);
    if (v.mode != null) enumValue(v.mode, ['standard', 'pro']);
  }, true);
  present('text', v => {
    shape(v, ['format', 'verbosity']);
    if (v.format != null) { shape(v.format, ['type']); enumValue(v.format.type, ['text']); }
    if (v.verbosity != null) enumValue(v.verbosity, ['low', 'medium', 'high']);
  }, true);
  present('max_output_tokens', v => finiteNumber(v, 1, 1_000_000, true), true);
  present('max_tool_calls', v => finiteNumber(v, 0, 1_000_000, true), true);
  present('temperature', v => finiteNumber(v, 0, 2), true);
  present('top_p', v => finiteNumber(v, 0, 1), true);
  present('top_logprobs', v => finiteNumber(v, 0, 20, true), true);
  present('truncation', v => enumValue(v, ['auto', 'disabled']), true);
  present('service_tier', v => enumValue(v, ['auto', 'default', 'flex', 'scale', 'priority', 'fast', 'ultrafast']), true);
}

// JSON.parse validates grammar; this bounded second pass rejects duplicate keys
// (including differently escaped spellings) before any schema is trusted.
function strictJson(text) {
  let result;
  try { result = JSON.parse(text); } catch { throw new ResponseTextGateError('invalid_json'); }
  let at = 0;
  let nodes = 0;
  const whitespace = () => { while (/\s/.test(text[at] || '') && at < text.length) at++; };
  const readString = () => {
    const start = at++;
    while (at < text.length) {
      if (text[at] === '\\') at += 2;
      else if (text[at++] === '"') break;
    }
    const value = JSON.parse(text.slice(start, at));
    string(value);
    return value;
  };
  const walk = (depth) => {
    requireThat(depth <= MAX_JSON_DEPTH && ++nodes <= MAX_JSON_NODES, 'json_complexity_limit');
    whitespace();
    const char = text[at];
    if (char === '"') { readString(); return; }
    if (char === '{') {
      at++;
      const keys = new Set();
      whitespace();
      while (text[at] !== '}') {
        const key = readString();
        requireThat(!keys.has(key), 'duplicate_json_key');
        keys.add(key);
        whitespace();
        at++; // colon; grammar was already checked
        walk(depth + 1);
        whitespace();
        if (text[at] !== ',') break;
        at++;
        whitespace();
      }
      at++;
    } else if (char === '[') {
      at++;
      whitespace();
      while (text[at] !== ']') {
        walk(depth + 1);
        whitespace();
        if (text[at] !== ',') break;
        at++;
      }
      at++;
    } else {
      while (at < text.length && !/[\s,}\]]/.test(text[at])) at++;
    }
  };
  walk(0);
  return result;
}

function textPart(part) {
  shape(part, ['type', 'text', 'annotations', 'logprobs'], 'text_part');
  requireThat(part.type === 'output_text', 'unsupported_content');
  string(part.text);
  for (const key of ['annotations', 'logprobs']) {
    if (Object.hasOwn(part, key)) requireThat(Array.isArray(part[key]) && part[key].length === 0);
  }
  return { type: 'output_text', text: part.text, annotations: [] };
}

function reasoningTextPart(part, type, location) {
  shape(part, ['type', 'text'], location);
  requireThat(part.type === type, 'unsupported_content');
  string(part.text);
  return part.text;
}

function sameReasoningParts(actual, expected, type) {
  return Array.isArray(actual) && actual.length === expected.length
    && actual.every((part, index) => part.type === type && part.text === expected[index].text);
}

function item(value, status) {
  requireThat(['message', 'reasoning'].includes(value?.type), 'unsupported_item');
  if (value.type === 'message') {
    shape(value, ['id', 'type', 'role', 'status', 'content', 'phase'], 'message');
    if (Object.hasOwn(value, 'phase')) enumValue(value.phase, [null, 'commentary', 'final_answer']);
    id(value.id);
    requireThat(value.role === 'assistant' && value.status === status);
    requireThat(Array.isArray(value.content) && value.content.length <= MAX_PARTS);
    const content = value.content.map(textPart);
    requireThat(status !== 'completed' || content.length > 0, 'empty_message');
    return { id: value.id, type: 'message', role: 'assistant', status, content };
  }
  shape(value, ['id', 'type', 'status', 'summary', 'content', 'encrypted_content']);
  id(value.id);
  requireThat(value.status === undefined || value.status === status);
  requireThat(Array.isArray(value.summary) && value.summary.length <= MAX_PARTS);
  for (const part of value.summary) {
    shape(part, ['type', 'text']);
    requireThat(part.type === 'summary_text');
    string(part.text);
  }
  if (value.content !== undefined) {
    requireThat(Array.isArray(value.content) && value.content.length <= MAX_PARTS);
    for (const part of value.content) {
      shape(part, ['type', 'text']);
      requireThat(part.type === 'reasoning_text');
      string(part.text);
    }
  }
  if (value.encrypted_content != null) string(value.encrypted_content);
  // Compare completed reasoning snapshots without retaining opaque payloads in
  // the normalized representation. Neither reasoning nor this digest is emitted.
  const fingerprint = createHash('sha256').update(JSON.stringify({
    summary: value.summary, content: value.content ?? [], encrypted: value.encrypted_content ?? null,
  })).digest('hex');
  return { id: value.id, type: 'reasoning', status, fingerprint };
}

function response(value, status) {
  shape(value, ['id', 'object', 'status', 'output', 'error', 'incomplete_details', ...RESPONSE_METADATA_KEYS], 'response');
  responseMetadata(value);
  id(value.id);
  requireThat(value.object === undefined || value.object === 'response');
  requireThat(value.status === status && value.error == null && value.incomplete_details == null,
    'invalid_terminal');
  requireThat(Array.isArray(value.output) && value.output.length <= MAX_ITEMS);
  const output = value.output.map((entry) => item(entry, status));
  requireThat(new Set(output.map((entry) => entry.id)).size === output.length, 'duplicate_item');
  if (status === 'in_progress') requireThat(output.length === 0);
  return { id: value.id, status, output };
}

function parseSse(text, maxEvents) {
  requireThat(!/\r(?!\n)/.test(text), 'unsupported_sse');
  const normalized = text.replace(/\r\n/g, '\n');
  const frames = normalized.split('\n\n');
  requireThat(frames.pop().trim() === '', 'truncated_sse');
  const items = [];
  let created = null;
  let completed = null;
  let progress = false;
  let doneSentinel = false;
  let sequenceMode = null;
  let lastSequence = -1;
  let count = 0;
  for (const frame of frames) {
    if (!frame.trim()) continue;
    let eventName = null;
    const data = [];
    for (const line of frame.split('\n')) {
      if (line.startsWith(':')) continue;
      const match = /^(event|data): ?(.*)$/.exec(line);
      requireThat(match !== null, 'unsupported_sse');
      if (match[1] === 'event') {
        requireThat(eventName === null, 'duplicate_sse_event');
        eventName = match[2];
      } else data.push(match[2]);
    }
    if (!data.length && eventName === null) continue;
    requireThat(++count <= maxEvents, 'event_limit');
    const payload = data.join('\n');
    if (payload === '[DONE]') {
      requireThat(completed !== null && !doneSentinel && eventName === null, 'invalid_done_sentinel');
      doneSentinel = true;
      continue;
    }
    requireThat(completed === null && !doneSentinel, 'event_after_terminal');
    const event = strictJson(payload);
    if (!EVENTS.has(event?.type)) {
      const error = new ResponseTextGateError('unsupported_event');
      error.eventKind = classifyUnsupportedResponseEventKind(event?.type);
      error.eventTypeClass = classifyUnsupportedResponseEventTypeClass(event);
      error.eventPhase = responseEventPhase(created, items);
      error.eventHeaderRelation = responseEventHeaderRelation(eventName, event);
      error.eventPayloadShape = responseEventPayloadShape(event);
      error.eventControlKind = classifyUnsupportedResponseEventControlKind(event?.type);
      throw error;
    }
    requireThat(eventName === null || eventName === event.type, 'event_type_conflict');
    const hasSequence = Object.hasOwn(event, 'sequence_number');
    if (sequenceMode === null) sequenceMode = hasSequence;
    requireThat(hasSequence === sequenceMode, 'sequence_conflict');
    if (hasSequence) {
      index(event.sequence_number);
      requireThat(event.sequence_number > lastSequence, 'sequence_conflict');
      lastSequence = event.sequence_number;
    }
    const base = ['type', 'sequence_number'];
    if (event.type === 'keepalive') {
      // Transport heartbeat, as handled by openai-node#1965/openai-java#776.
      // This candidate accepts only the inert two-field form. It consumes the
      // same sequence/event budget but never advances response state or output.
      shape(event, base, 'sse_response');
      requireThat(hasSequence, 'sequence_conflict');
      continue;
    }
    if (['response.created', 'response.in_progress', 'response.completed'].includes(event.type)) {
      shape(event, [...base, 'response'], 'sse_response');
      if (event.type === 'response.created') {
        requireThat(created === null, 'duplicate_created');
        created = response(event.response, 'in_progress');
      } else {
        requireThat(created !== null, 'missing_created');
        const current = response(event.response, event.type === 'response.completed' ? 'completed' : 'in_progress');
        requireThat(current.id === created.id, 'response_id_conflict');
        if (event.type === 'response.in_progress') {
          requireThat(!progress && items.length === 0, 'invalid_progress');
          progress = true;
        } else {
          // The fixed Codex SSE endpoint can finish with output: [] after
          // output_item.done already supplied the text. Only fully validated
          // done items may fill this streaming-only omission. A nonempty
          // terminal snapshot must still match every item exactly.
          if (current.output.length === 0 && items.length > 0) {
            requireThat(items.every(entry => entry.done !== null), 'output_conflict');
            current.output = items.map(entry => entry.done);
          } else {
            requireThat(current.output.length === items.length, 'output_conflict');
            current.output.forEach((entry, i) => {
              requireThat(items[i].done && JSON.stringify(entry) === JSON.stringify(items[i].done), 'output_conflict');
            });
          }
          completed = current;
        }
      }
      continue;
    }
    requireThat(created !== null, 'missing_created');
    index(event.output_index);
    if (event.type === 'response.output_item.added') {
      shape(event, [...base, 'output_index', 'item'], 'sse_item');
      requireThat(event.output_index === items.length && items.length < MAX_ITEMS, 'item_order_conflict');
      const added = item(event.item, 'in_progress');
      requireThat(!items.some((entry) => entry.added.id === added.id), 'duplicate_item');
      requireThat(added.type !== 'message' || added.content.length === 0);
      items.push({ added, parts: [], done: null, reasoning: added.type === 'reasoning'
        ? { summary: [], content: [], summaryStreamed: false, contentStreamed: false,
          initialSummaryParts: event.item.summary.length, initialContentParts: event.item.content?.length ?? 0 } : null });
      continue;
    }
    const current = items[event.output_index];
    requireThat(current && !current.done, 'item_order_conflict');
    if (event.type === 'response.output_item.done') {
      shape(event, [...base, 'output_index', 'item'], 'sse_item');
      const done = item(event.item, 'completed');
      requireThat(done.id === current.added.id && done.type === current.added.type, 'item_id_conflict');
      if (done.type === 'message') {
        requireThat(done.content.length === current.parts.length, 'text_conflict');
        done.content.forEach((part, i) => requireThat(part.text === current.parts[i].text, 'text_conflict'));
      } else if (current.reasoning) {
        const summary = current.reasoning.summary.map(part => ({ type: 'summary_text', text: part.text }));
        const content = current.reasoning.content.map(part => ({ type: 'reasoning_text', text: part.text }));
        if (current.reasoning.summaryStreamed) {
          requireThat(current.reasoning.summary.every(part => part.textDone && part.partDone), 'text_order_conflict');
          requireThat(sameReasoningParts(event.item.summary, summary, 'summary_text'), 'text_conflict');
        }
        if (current.reasoning.contentStreamed) {
          requireThat(current.reasoning.content.every(part => part.textDone), 'text_order_conflict');
          requireThat(sameReasoningParts(event.item.content ?? [], content, 'reasoning_text'), 'text_conflict');
        }
      }
      current.done = done;
      continue;
    }
    if (event.type.startsWith('response.reasoning_')) {
      requireThat(current.added.type === 'reasoning' && current.reasoning !== null, 'unsupported_content');
      requireThat(event.item_id === current.added.id, 'item_id_conflict');
      const summary = event.type.startsWith('response.reasoning_summary_');
      const partEvent = event.type.includes('_part.');
      const delta = event.type.endsWith('.delta');
      const done = event.type.endsWith('.done');
      const parts = summary ? current.reasoning.summary : current.reasoning.content;
      const partType = summary ? 'summary_text' : 'reasoning_text';
      const indexKey = summary ? 'summary_index' : 'content_index';
      if (summary && !current.reasoning.summaryStreamed)
        requireThat(current.reasoning.initialSummaryParts === 0, 'part_order_conflict');
      if (!summary && !current.reasoning.contentStreamed)
        requireThat(current.reasoning.initialContentParts === 0, 'part_order_conflict');
      index(event[indexKey]);
      requireThat(event[indexKey] < MAX_PARTS, 'part_order_conflict');
      const partIndex = event[indexKey];
      if (partEvent) {
        shape(event, [...base, 'item_id', 'output_index', 'summary_index', 'part'], 'sse_item');
        requireThat(summary, 'unsupported_event');
        const partText = reasoningTextPart(event.part, partType, 'sse_item');
        if (!done) {
          requireThat(partIndex === parts.length, 'part_order_conflict');
          requireThat(partText === '', 'part_order_conflict');
          parts.push({ text: '', added: true, textDone: false, partDone: false });
        } else {
          const part = parts[partIndex];
          requireThat(part?.added && part.textDone && !part.partDone && part.text === partText, 'text_conflict');
          part.partDone = true;
        }
        current.reasoning.summaryStreamed = true;
        continue;
      }
      shape(event, [...base, 'item_id', 'output_index', indexKey, delta ? 'delta' : 'text',
        ...(delta ? ['obfuscation'] : [])],
        delta ? 'sse_text_delta' : 'sse_text_done');
      if (delta && Object.hasOwn(event, 'obfuscation')) boundedString(event.obfuscation, 8192);
      requireThat(partIndex <= parts.length, 'part_order_conflict');
      let part = parts[partIndex];
      if (!part) {
        requireThat(!summary, 'part_order_conflict');
        part = { text: '', added: true, textDone: false, partDone: false };
        parts.push(part);
      }
      requireThat(part.added && !part.textDone && !part.partDone, 'text_order_conflict');
      string(delta ? event.delta : event.text);
      if (delta) part.text += event.delta;
      else { requireThat(event.text === part.text, 'text_conflict'); part.textDone = true; }
      if (summary) current.reasoning.summaryStreamed = true;
      else current.reasoning.contentStreamed = true;
      continue;
    }
    requireThat(current.added.type === 'message', 'unsupported_content');
    requireThat(event.item_id === current.added.id, 'item_id_conflict');
    index(event.content_index);
    requireThat(event.content_index <= current.parts.length && event.content_index < MAX_PARTS, 'part_order_conflict');
    let part = current.parts[event.content_index];
    if (!part) { part = { text: '', added: false, textDone: false, partDone: false }; current.parts.push(part); }
    if (event.type.startsWith('response.content_part.')) {
      shape(event, [...base, 'output_index', 'item_id', 'content_index', 'part'], 'sse_content_part');
      const content = textPart(event.part);
      if (event.type === 'response.content_part.added') {
        requireThat(!part.added && !part.text && !part.textDone && !part.partDone && content.text === '', 'part_order_conflict');
        part.added = true;
      } else {
        requireThat(!part.partDone && content.text === part.text, 'text_conflict');
        part.partDone = true;
      }
    } else {
      const delta = event.type === 'response.output_text.delta';
      shape(event, [...base, 'output_index', 'item_id', 'content_index', delta ? 'delta' : 'text', 'logprobs',
        ...(delta ? ['obfuscation'] : [])], delta ? 'sse_text_delta' : 'sse_text_done');
      // Official Responses StreamOptions documents random padding on delta
      // events. It is bounded and discarded, never concatenated into output.
      if (delta && Object.hasOwn(event, 'obfuscation')) boundedString(event.obfuscation, 8192);
      if (event.logprobs !== undefined) requireThat(Array.isArray(event.logprobs) && !event.logprobs.length);
      requireThat(!part.textDone && !part.partDone, 'text_order_conflict');
      string(delta ? event.delta : event.text);
      if (delta) part.text += event.delta;
      else { requireThat(event.text === part.text, 'text_conflict'); part.textDone = true; }
    }
  }
  requireThat(completed !== null, 'missing_completed');
  return completed;
}

function safeSse(validated, maxOutputBytes) {
  const messages = validated.output.filter((entry) => entry.type === 'message');
  requireThat(messages.length > 0, 'missing_assistant_text');
  const digest = createHash('sha256').update(validated.id).digest('hex').slice(0, 24);
  const responseId = `resp_text_gate_${digest}`;
  const frames = [];
  let bytes = 0;
  let sequence = 0;
  const emit = (type, payload) => {
    const frame = `event: ${type}\ndata: ${JSON.stringify({ type, sequence_number: sequence++, ...payload })}\n\n`;
    bytes += Buffer.byteLength(frame);
    requireThat(bytes <= maxOutputBytes, 'output_limit');
    frames.push(frame);
  };
  const safeResponse = { id: responseId, object: 'response', status: 'in_progress', output: [] };
  emit('response.created', { response: safeResponse });
  const output = messages.map((message, outputIndex) => {
    const itemId = `msg_text_gate_${digest}_${outputIndex}`;
    const added = { id: itemId, type: 'message', role: 'assistant', status: 'in_progress', content: [] };
    emit('response.output_item.added', { output_index: outputIndex, item: added });
    const content = message.content.map((part, contentIndex) => {
      const location = { item_id: itemId, output_index: outputIndex, content_index: contentIndex };
      emit('response.content_part.added', { ...location, part: { type: 'output_text', text: '', annotations: [] } });
      emit('response.output_text.delta', { ...location, delta: part.text });
      emit('response.output_text.done', { ...location, text: part.text });
      const safePart = { type: 'output_text', text: part.text, annotations: [] };
      emit('response.content_part.done', { ...location, part: safePart });
      return safePart;
    });
    const done = { ...added, status: 'completed', content };
    emit('response.output_item.done', { output_index: outputIndex, item: done });
    return done;
  });
  emit('response.completed', { response: { ...safeResponse, status: 'completed', output } });
  return Buffer.from(frames.join(''));
}

export class WorkbenchResponseTextGate {
  #input;
  #size = 0;
  #state = 'collecting';
  #format;
  #limits;

  constructor({ format = 'sse', maxInputBytes = DEFAULT_INPUT_BYTES, maxOutputBytes = DEFAULT_OUTPUT_BYTES, maxEvents = 4096 } = {}) {
    requireThat(['sse', 'json'].includes(format), 'invalid_options');
    for (const limit of [maxInputBytes, maxOutputBytes, maxEvents]) {
      requireThat(Number.isSafeInteger(limit) && limit > 0 && limit <= 16 * 1024 * 1024, 'invalid_options');
    }
    this.#format = format;
    this.#limits = { maxInputBytes, maxOutputBytes, maxEvents };
    this.#input = Buffer.alloc(maxInputBytes);
  }

  get state() { return this.#state; }

  push(chunk) {
    requireThat(this.#state === 'collecting', 'invalid_state');
    try {
      requireThat(chunk instanceof Uint8Array, 'invalid_chunk');
      requireThat(chunk.byteLength <= this.#limits.maxInputBytes - this.#size, 'input_limit');
      this.#input.set(chunk, this.#size);
      this.#size += chunk.byteLength;
      // Deliberately no frames, callbacks or partial return value.
    } catch (error) {
      this.#state = 'failed'; this.#input = null;
      throw error;
    }
  }

  finish() {
    requireThat(this.#state === 'collecting', 'invalid_state');
    try {
      let text;
      try { text = new TextDecoder('utf-8', { fatal: true }).decode(this.#input.subarray(0, this.#size)); }
      catch { throw new ResponseTextGateError('invalid_utf8'); }
      const validated = this.#format === 'sse'
        ? parseSse(text, this.#limits.maxEvents)
        : response(strictJson(text), 'completed');
      const output = safeSse(validated, this.#limits.maxOutputBytes);
      this.#state = 'finished';
      return output;
    } catch (error) {
      this.#state = 'failed';
      throw error;
    } finally { this.#input = null; }
  }
}

export function createTextOnlyResponseGate(options = {}) {
  return new WorkbenchResponseTextGate(options);
}
