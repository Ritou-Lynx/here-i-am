// Passive diagnostics for already-rejected bytes. This never authorizes or
// releases a response, performs IO, decodes reasoning, or returns payload values or raw bodies.
const MAX_BYTES = 256 * 1024;
const MAX_FRAMES = 256;
const MAX_ITEMS = 1024;
const MAX_PROTOCOL_KEYS = 16;
const DIAGNOSTICS = new WeakSet();
export function isRejectedTextResponseDiagnostic(value) {
  return value !== null && typeof value === 'object' && DIAGNOSTICS.has(value);
}
function sealDiagnostic(report) {
  // Only our fixed-schema result enters this walk, never parsed provider data.
  const freeze = value => {
    if (value !== null && typeof value === 'object') {
      for (const child of Object.values(value)) freeze(child);
      Object.freeze(value);
    }
  };
  freeze(report);
  DIAGNOSTICS.add(report);
  return report;
}
const EVENTS = new Set([
  'response.created', 'response.in_progress', 'response.completed', 'response.failed', 'response.incomplete',
  'response.output_item.added', 'response.output_item.done',
  'response.content_part.added', 'response.content_part.done',
  'response.output_text.delta', 'response.output_text.done',
  'response.refusal.delta', 'response.refusal.done',
  'response.function_call_arguments.delta', 'response.function_call_arguments.done',
  'response.custom_tool_call_input.delta', 'response.custom_tool_call_input.done',
  'response.reasoning_summary_part.added', 'response.reasoning_summary_part.done',
  'response.reasoning_summary_text.delta', 'response.reasoning_summary_text.done',
  'response.reasoning_text.delta', 'response.reasoning_text.done',
  'response.web_search_call.in_progress', 'response.web_search_call.searching', 'response.web_search_call.completed',
  'response.file_search_call.in_progress', 'response.file_search_call.searching', 'response.file_search_call.completed',
  'error',
]);
const RESPONSE_FIELDS = new Set([
  'id', 'object', 'created_at', 'completed_at', 'status', 'error', 'incomplete_details', 'instructions',
  'max_output_tokens', 'model', 'output', 'parallel_tool_calls', 'previous_response_id', 'reasoning',
  'store', 'temperature', 'text', 'tool_choice', 'tools', 'top_p', 'truncation', 'usage', 'user', 'metadata',
  'frequency_penalty', 'presence_penalty', 'tool_usage', 'access_programs',
  'service_tier', 'background', 'conversation', 'max_tool_calls', 'prompt_cache_key', 'prompt_cache_retention',
  'safety_identifier', 'top_logprobs',
  'prompt', 'moderation', 'prompt_cache_diagnostics', 'prompt_cache_options',
  'usage_metadata', 'end_turn', 'headers',
]);
const ITEM_TYPES = new Set([
  'message', 'reasoning', 'function_call', 'custom_tool_call', 'web_search_call', 'file_search_call',
  'code_interpreter_call', 'image_generation_call', 'computer_call', 'mcp_call', 'mcp_list_tools', 'mcp_approval_request',
]);
const ITEM_FIELDS = new Set([
  'id', 'type', 'role', 'status', 'content', 'summary', 'encrypted_content', 'call_id', 'name', 'arguments',
  'input', 'output', 'action', 'queries', 'results', 'code', 'container_id', 'result', 'server_label',
  'tools', 'error', 'approval_request_id', 'pending_safety_checks',
  'phase',
]);
const USAGE_FIELDS = new Set(['input_tokens', 'output_tokens', 'total_tokens', 'input_tokens_details', 'output_tokens_details',
  'text_tokens', 'image_tokens', 'cached_tokens', 'cache_write_tokens', 'reasoning_tokens',
  'input_tokens_cached', 'input_tokens_cache_write', 'output_tokens_reasoning']);
const INPUT_TOKEN_DETAILS_FIELDS = new Set(['cached_tokens', 'cache_write_tokens', 'text_tokens', 'image_tokens']);
const OUTPUT_TOKEN_DETAILS_FIELDS = new Set(['reasoning_tokens', 'text_tokens', 'image_tokens']);
const NESTED_FIELDS = {
  access_programs: new Set(['cyber']),
  reasoning: new Set(['effort', 'summary', 'generate_summary', 'context', 'mode']),
  text: new Set(['format', 'verbosity']),
  'text.format': new Set(['type', 'name', 'schema', 'strict', 'description']),
  usage: new Set([...USAGE_FIELDS, 'codex_rollout_budget_units', 'attribution']),
  'usage.input_tokens_details': INPUT_TOKEN_DETAILS_FIELDS,
  'usage.output_tokens_details': OUTPUT_TOKEN_DETAILS_FIELDS,
  tool_usage: new Set(['image_gen', 'web_search']),
  'tool_usage.image_gen': USAGE_FIELDS,
  'tool_usage.image_gen.input_tokens_details': INPUT_TOKEN_DETAILS_FIELDS,
  'tool_usage.image_gen.output_tokens_details': OUTPUT_TOKEN_DETAILS_FIELDS,
  'tool_usage.web_search': new Set(),
  'usage.attribution': new Set(['items', 'request_fields']),
  'usage.attribution.items': new Set(),
  'usage.attribution.request_fields': new Set(['instructions']),
  'usage.attribution.request_fields.instructions': USAGE_FIELDS,
  'usage.attribution.request_fields.instructions.input_tokens_details': INPUT_TOKEN_DETAILS_FIELDS,
  'usage.attribution.request_fields.instructions.output_tokens_details': OUTPUT_TOKEN_DETAILS_FIELDS,
  prompt_cache_options: new Set(['mode', 'ttl', 'comparison_response_id']),
  usage_metadata: new Set(['amount', 'metadata']),
  headers: new Set(['openai-model', 'x-openai-model', 'x-request-id']),
};
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const shape = value => value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value;
const SAFE_PROTOCOL_KEY = /^[a-z][a-z_]{0,63}$/;
const SENSITIVE_PROTOCOL_KEY = /auth|token|secret|credential|password|email|account|key|private|session|cookie|bearer|api/;
class DiagnosticError extends Error { constructor(code) { super(code); this.code = code; } }
const requireThat = (condition, code) => { if (!condition) throw new DiagnosticError(code); };
function empty(format = 'unknown', error = null) {
  return { diagnostic_only: true, format, error, frame_count: 0, known_event_counts: {}, unknown_event_count: 0,
    response_count: 0, response_known_fields: [], response_unknown_field_count: 0, response_field_shapes: {},
    output_item_count: 0, unknown_item_type_count: 0, output_items: [], response_nested_fields: {} };
}
function recordFields(value, vocabulary, bucket) {
  for (const key of Object.keys(value)) {
    if (!vocabulary.has(key)) { bucket.unknown++; continue; }
    if (!bucket.fields.has(key)) bucket.fields.set(key, new Set());
    bucket.fields.get(key).add(shape(value[key]));
  }
}
function fieldResult(bucket) {
  const fields = [...bucket.fields.keys()].sort();
  return { known_fields: fields, unknown_field_count: bucket.unknown,
    field_shapes: Object.fromEntries(fields.map(key => [key, [...bucket.fields.get(key)].sort()])) };
}

function protocolKeysResult(bucket) {
  const fields = [...bucket.fields.keys()].sort().map(name => ({
    name,
    types: [...bucket.fields.get(name)].sort(),
  }));
  return {
    fields,
    filtered_field_count: bucket.filtered,
    omitted_field_count: bucket.omitted,
  };
}

function recordProtocolKeys(value, vocabulary, bucket) {
  for (const key of Object.keys(value)) {
    if (vocabulary.has(key)) continue;
    if (!SAFE_PROTOCOL_KEY.test(key) || SENSITIVE_PROTOCOL_KEY.test(key)) {
      bucket.filtered++;
      continue;
    }
    if (!bucket.fields.has(key)) {
      if (bucket.fields.size >= MAX_PROTOCOL_KEYS) {
        bucket.omitted++;
        continue;
      }
      bucket.fields.set(key, new Set());
    }
    bucket.fields.get(key).add(shape(value[key]));
  }
}

function recordFixedUsageFields(value, vocabulary, bucket) {
  for (const key of Object.keys(value)) {
    if (!vocabulary.has(key)) {
      if (SENSITIVE_PROTOCOL_KEY.test(key)) bucket.filtered++;
      else bucket.unknown++;
      continue;
    }
    if (!bucket.fields.has(key)) {
      if (bucket.fields.size >= MAX_PROTOCOL_KEYS) { bucket.omitted++; continue; }
      bucket.fields.set(key, new Set());
    }
    bucket.fields.get(key).add(shape(value[key]));
  }
}

function fixedUsageResult(bucket) {
  return {
    fields: [...bucket.fields.keys()].sort().map(name => ({ name, types: [...bucket.fields.get(name)].sort() })),
    unknown_field_count: bucket.unknown,
    filtered_field_count: bucket.filtered,
    omitted_field_count: bucket.omitted,
  };
}

function createUsageItemsBucket(includeContent = true) {
  return { fields: new Map(), unknown: 0, filtered: 0, omitted: 0,
    direct_object_count: 0, omitted_item_count: 0, non_object_value_shapes: new Set(), inspected_item_count: 0,
    protocol: { fields: new Map(), filtered: 0, omitted: 0 },
    content: includeContent ? createUsageItemsBucket(false) : null };
}

function recordUsageValue(item, bucket) {
  if (bucket.inspected_item_count >= 64) { bucket.omitted_item_count++; return; }
  bucket.inspected_item_count++;
  if (!object(item)) { bucket.non_object_value_shapes.add(shape(item)); return; }
  bucket.direct_object_count++;
  recordFixedUsageFields(item, USAGE_FIELDS, bucket);
  recordProtocolKeys(item, USAGE_FIELDS, bucket.protocol);
  // Exactly one declared content-array level, never arbitrary recursion.
  if (bucket.content && Array.isArray(item.content)) {
    for (const part of item.content) recordUsageValue(part, bucket.content);
  }
}

function aggregateUsageItems(value, bucket) {
  if (!object(value)) return;
  let seen = 0;
  for (const item of Object.values(value)) {
    if (seen++ >= 64 || bucket.inspected_item_count >= 64) { bucket.omitted_item_count++; continue; }
    recordUsageValue(item, bucket);
    // Only fields within a bounded direct value are protocol keys. The parent
    // map key is never inspected or included, even if it looks like a safe name.
  }
}

function usageItemsResult(bucket) {
  return { ...fixedUsageResult(bucket), direct_object_count: bucket.direct_object_count,
    omitted_item_count: bucket.omitted_item_count, non_object_value_shapes: [...bucket.non_object_value_shapes].sort(),
    protocol_fields: protocolKeysResult(bucket.protocol), ...(bucket.content ? { content_counts: usageItemsResult(bucket.content) } : {}) };
}

function fixedObjectAt(root, fixedPath) {
  let value = root;
  // fixedPath comes only from NESTED_FIELDS declarations above. It is not
  // provider-controlled traversal and never enumerates child objects.
  for (const key of fixedPath.split('.')) {
    if (!object(value)) return undefined;
    value = value[key];
  }
  return object(value) ? value : undefined;
}

// Input is bytes only: a missing or untrusted Content-Type is irrelevant to this
// passive sniff. Counts describe parsed structural occurrences, not acceptance.
export function inspectRejectedTextResponse(buffer, { includeProtocolKeys = false } = {}) {
  let format = 'unknown';
  try {
    requireThat(Buffer.isBuffer(buffer), 'invalid_input');
    requireThat(buffer.length <= MAX_BYTES, 'input_limit');
    requireThat(typeof includeProtocolKeys === 'boolean', 'invalid_options');
    let text;
    try { text = new TextDecoder('utf-8', { fatal: true }).decode(buffer).trimStart(); }
    catch { throw new DiagnosticError('invalid_utf8'); }
    requireThat(text.length > 0, 'empty_input');
    const report = empty();
    const responses = { fields: new Map(), unknown: 0 };
    const protocolResponses = { fields: new Map(), filtered: 0, omitted: 0 };
    const protocolUsage = { fields: new Map(), filtered: 0, omitted: 0 };
    const protocolToolUsage = { fields: new Map(), filtered: 0, omitted: 0 };
    const protocolUsageAttribution = { fields: new Map(), filtered: 0, omitted: 0 };
    const protocolToolUsageImageGen = { fields: new Map(), filtered: 0, omitted: 0 };
    const protocolToolUsageWebSearch = { fields: new Map(), filtered: 0, omitted: 0 };
    const protocolUsageAttributionRequestFields = { fields: new Map(), filtered: 0, omitted: 0 };
    const protocolImageGen = { fields: new Map(), unknown: 0, filtered: 0, omitted: 0 };
    const protocolImageGenInputDetails = { fields: new Map(), unknown: 0, filtered: 0, omitted: 0 };
    const protocolImageGenOutputDetails = { fields: new Map(), unknown: 0, filtered: 0, omitted: 0 };
    const protocolInstructions = { fields: new Map(), unknown: 0, filtered: 0, omitted: 0 };
    const protocolInstructionsInputDetails = { fields: new Map(), unknown: 0, filtered: 0, omitted: 0 };
    const protocolInstructionsOutputDetails = { fields: new Map(), unknown: 0, filtered: 0, omitted: 0 };
    const protocolAttributionItems = createUsageItemsBucket();
    const items = new Map();
    const nestedFields = new Map();
    const inspectItem = item => {
      requireThat(object(item), 'invalid_shape');
      requireThat(++report.output_item_count <= MAX_ITEMS, 'item_limit');
      const type = ITEM_TYPES.has(item.type) ? item.type : 'unknown';
      if (type === 'unknown') report.unknown_item_type_count++;
      if (!items.has(type)) items.set(type, { count: 0, fields: new Map(), unknown: 0 });
      const bucket = items.get(type); bucket.count++;
      recordFields(item, ITEM_FIELDS, bucket);
    };
    const inspectResponse = response => {
      requireThat(object(response), 'invalid_shape');
      report.response_count++;
      recordFields(response, RESPONSE_FIELDS, responses);
      if (includeProtocolKeys) {
        recordProtocolKeys(response, RESPONSE_FIELDS, protocolResponses);
        if (object(response.usage)) recordProtocolKeys(response.usage, NESTED_FIELDS.usage, protocolUsage);
        if (object(response.tool_usage)) recordProtocolKeys(response.tool_usage, NESTED_FIELDS.tool_usage, protocolToolUsage);
        if (object(response.usage?.attribution)) recordProtocolKeys(response.usage.attribution, NESTED_FIELDS['usage.attribution'], protocolUsageAttribution);
        const imageGen = fixedObjectAt(response, 'tool_usage.image_gen');
        const webSearch = fixedObjectAt(response, 'tool_usage.web_search');
        const attributionRequestFields = fixedObjectAt(response, 'usage.attribution.request_fields');
        if (imageGen) recordProtocolKeys(imageGen, NESTED_FIELDS['tool_usage.image_gen'], protocolToolUsageImageGen);
        if (webSearch) recordProtocolKeys(webSearch, NESTED_FIELDS['tool_usage.web_search'], protocolToolUsageWebSearch);
        if (attributionRequestFields) recordProtocolKeys(attributionRequestFields, NESTED_FIELDS['usage.attribution.request_fields'], protocolUsageAttributionRequestFields);
        if (imageGen) recordFixedUsageFields(imageGen, USAGE_FIELDS, protocolImageGen);
        const imageGenInputDetails = fixedObjectAt(response, 'tool_usage.image_gen.input_tokens_details');
        const imageGenOutputDetails = fixedObjectAt(response, 'tool_usage.image_gen.output_tokens_details');
        if (imageGenInputDetails) recordFixedUsageFields(imageGenInputDetails, INPUT_TOKEN_DETAILS_FIELDS, protocolImageGenInputDetails);
        if (imageGenOutputDetails) recordFixedUsageFields(imageGenOutputDetails, OUTPUT_TOKEN_DETAILS_FIELDS, protocolImageGenOutputDetails);
        const instructions = fixedObjectAt(response, 'usage.attribution.request_fields.instructions');
        const instructionsInputDetails = fixedObjectAt(response, 'usage.attribution.request_fields.instructions.input_tokens_details');
        const instructionsOutputDetails = fixedObjectAt(response, 'usage.attribution.request_fields.instructions.output_tokens_details');
        if (instructions) recordFixedUsageFields(instructions, USAGE_FIELDS, protocolInstructions);
        if (instructionsInputDetails) recordFixedUsageFields(instructionsInputDetails, INPUT_TOKEN_DETAILS_FIELDS, protocolInstructionsInputDetails);
        if (instructionsOutputDetails) recordFixedUsageFields(instructionsOutputDetails, OUTPUT_TOKEN_DETAILS_FIELDS, protocolInstructionsOutputDetails);
        aggregateUsageItems(fixedObjectAt(response, 'usage.attribution.items'), protocolAttributionItems);
      }
      // Only these fixed paths are inspected; no arbitrary object recursion.
      for (const [fixedPath, vocabulary] of Object.entries(NESTED_FIELDS)) {
        const value = fixedObjectAt(response, fixedPath);
        if (!value) continue;
        if (!nestedFields.has(fixedPath)) nestedFields.set(fixedPath, { fields: new Map(), unknown: 0 });
        recordFields(value, vocabulary, nestedFields.get(fixedPath));
      }
      // No other objects are traversed: errors, metadata, content and
      // encrypted_content remain untouched, even if they resemble events/items.
      if (Array.isArray(response.output)) for (const item of response.output) inspectItem(item);
    };
    const parse = value => {
      try { return JSON.parse(value); } catch { throw new DiagnosticError('invalid_json'); }
    };
    if (/^[{[]/.test(text)) {
      format = 'json';
      inspectResponse(parse(text));
    } else {
      requireThat(/^(?:event:|data:|:)/.test(text), 'unrecognized_format');
      format = 'sse';
      requireThat(!/\r(?!\n)/.test(text), 'invalid_sse');
      text = text.replaceAll('\r\n', '\n');
      requireThat(text.endsWith('\n\n'), 'truncated_sse');
      for (const frame of text.split('\n\n')) {
        if (!frame.trim()) continue;
        requireThat(++report.frame_count <= MAX_FRAMES, 'frame_limit');
        let eventName; const data = [];
        for (const line of frame.split('\n')) {
          if (line.startsWith(':')) continue;
          const match = /^(event|data|id|retry): ?(.*)$/.exec(line);
          requireThat(match !== null, 'invalid_sse');
          if (match[1] === 'event') {
            requireThat(eventName === undefined, 'invalid_sse'); eventName = match[2];
          } else if (match[1] === 'data') data.push(match[2]);
        }
        if (data.length === 0) continue;
        if (data.join('\n') === '[DONE]') continue;
        const event = parse(data.join('\n'));
        requireThat(object(event), 'invalid_shape');
        const type = eventName === undefined ? event.type : eventName;
        if (EVENTS.has(type) && (event.type === undefined || event.type === type))
          report.known_event_counts[type] = (report.known_event_counts[type] || 0) + 1;
        else report.unknown_event_count++;
        if (Object.hasOwn(event, 'response')) inspectResponse(event.response);
        if (Object.hasOwn(event, 'item')) inspectItem(event.item);
      }
    }
    report.format = format;
    const responseFields = fieldResult(responses);
    report.response_known_fields = responseFields.known_fields;
    report.response_unknown_field_count = responseFields.unknown_field_count;
    report.response_field_shapes = responseFields.field_shapes;
    report.output_items = [...items.keys()].sort().map(type => ({ type, count: items.get(type).count, ...fieldResult(items.get(type)) }));
    report.response_nested_fields = Object.fromEntries([...nestedFields.keys()].sort().map(key => [key, fieldResult(nestedFields.get(key))]));
    if (includeProtocolKeys) {
      report.protocol_keys = {
        response: protocolKeysResult(protocolResponses),
        usage: protocolKeysResult(protocolUsage),
        tool_usage: protocolKeysResult(protocolToolUsage),
        usage_attribution: protocolKeysResult(protocolUsageAttribution),
        tool_usage_image_gen: protocolKeysResult(protocolToolUsageImageGen),
        tool_usage_web_search: protocolKeysResult(protocolToolUsageWebSearch),
        usage_attribution_request_fields: protocolKeysResult(protocolUsageAttributionRequestFields),
        image_gen_usage: fixedUsageResult(protocolImageGen),
        image_gen_input_token_details: fixedUsageResult(protocolImageGenInputDetails),
        image_gen_output_token_details: fixedUsageResult(protocolImageGenOutputDetails),
        request_field_instructions: fixedUsageResult(protocolInstructions),
        request_field_instructions_input_token_details: fixedUsageResult(protocolInstructionsInputDetails),
        request_field_instructions_output_token_details: fixedUsageResult(protocolInstructionsOutputDetails),
        attribution_items_usage: usageItemsResult(protocolAttributionItems),
      };
    }
    return sealDiagnostic(report);
  } catch (error) {
    // Discard partial diagnostics and never serialize parse exceptions or values.
    return sealDiagnostic(empty(format, error instanceof DiagnosticError ? error.code : 'diagnostic_failed'));
  }
}
