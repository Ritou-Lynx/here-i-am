// Candidate request half of the P6 text-only boundary. No networking or auth.
// Construct fresh JSON: neither catalogs nor hidden server-side history survive.
export class TextOnlyRequestError extends Error {
  constructor(code) { super(`Text-only request rejected: ${code}`); this.name = 'TextOnlyRequestError'; this.code = code; }
}
const reject = (code) => { throw new TextOnlyRequestError(code); };
const object = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);
const TOP_KEYS = new Set(['model', 'input', 'instructions', 'reasoning', 'store', 'stream', 'include',
  'prompt_cache_key', 'text', 'client_metadata', 'tools', 'tool_choice', 'parallel_tool_calls',
  'max_output_tokens', 'previous_response_id']);
function knownKeys(value, allowed, code) {
  if (!object(value) || Object.keys(value).some(key => !allowed.includes(key))) reject(code);
}
function textPart(part, role) {
  knownKeys(part, ['type', 'text', 'annotations'], 'content_shape');
  if (!['input_text', 'output_text'].includes(part.type) || typeof part.text !== 'string') reject('non_text_content');
  if (part.annotations !== undefined && (!Array.isArray(part.annotations) || part.annotations.length)) reject('annotated_content');
  return { type: role === 'assistant' ? 'output_text' : 'input_text', text: part.text };
}
export function normalizeTextOnlyRequest(body, { model, maxBytes = 1024 * 1024, maxMessages = 128 } = {}) {
  if (!Number.isSafeInteger(maxBytes) || maxBytes < 1 || !Number.isSafeInteger(maxMessages) || maxMessages < 1) reject('invalid_limits');
  if (!object(body) || Object.keys(body).some(key => !TOP_KEYS.has(key))) reject('request_shape');
  if (typeof model !== 'string' || !model.trim() || body.model !== model) reject('model_mismatch');
  let size;
  try { size = Buffer.byteLength(JSON.stringify(body), 'utf8'); } catch { reject('invalid_json'); }
  if (size > maxBytes) reject('request_too_large');
  if (body.previous_response_id !== undefined && body.previous_response_id !== null) reject('server_history');
  if (!Array.isArray(body.input) || body.input.length > maxMessages) reject('input_shape');
  const input = [];
  for (const item of body.input) {
    if (item?.type === 'additional_tools') {
      knownKeys(item, ['type', 'id', 'role', 'tools'], 'catalog_shape');
      if (item.role !== 'developer' || !Array.isArray(item.tools)) reject('catalog_shape');
      continue; // Drop the entire compiled catalog, regardless of tool kind.
    }
    knownKeys(item, ['type', 'id', 'role', 'content', 'status'], 'input_item_shape');
    if (item.type !== 'message' || !['system', 'developer', 'user', 'assistant'].includes(item.role)) reject('non_message_input');
    if (!Array.isArray(item.content) || !item.content.length) reject('content_shape');
    input.push({ type: 'message', role: item.role, content: item.content.map(part => textPart(part, item.role)) });
  }
  if (!input.length) reject('empty_context');
  const request = { model, input, tools: [], tool_choice: 'none', parallel_tool_calls: false, store: false, stream: true };
  if (body.instructions !== undefined) {
    if (typeof body.instructions !== 'string') reject('instructions_shape');
    request.instructions = body.instructions;
  }
  if (body.reasoning !== undefined) {
    knownKeys(body.reasoning, ['effort', 'summary', 'context'], 'reasoning_shape');
    const { effort, summary } = body.reasoning;
    if (effort !== undefined && !['none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max', 'ultra'].includes(effort)) reject('reasoning_effort');
    if (summary !== undefined && !['auto', 'concise', 'detailed'].includes(summary)) reject('reasoning_summary');
    request.reasoning = { ...(effort !== undefined ? { effort } : {}), ...(summary !== undefined ? { summary } : {}) };
  }
  if (body.max_output_tokens !== undefined) {
    if (!Number.isSafeInteger(body.max_output_tokens) || body.max_output_tokens < 1 || body.max_output_tokens > 32768) reject('output_limit');
    request.max_output_tokens = body.max_output_tokens;
  }
  // text/include/cache/client_metadata/tool_choice are intentionally not copied.
  // Reconstructed output is a subset of accepted input, plus fixed small fields.
  if (Buffer.byteLength(JSON.stringify(request), 'utf8') > maxBytes) reject('request_too_large');
  return request;
}
