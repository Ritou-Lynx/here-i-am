/** Domain protocol transport. It owns no grants, records, or production configuration. */
const PREFIX = '/v1/core/domains';
const MAX_BYTES = 262144;
const COMMON = ['domain_protocol_version', 'core_instance_id', 'op_id', 'schema_version', 'kind', 'id', 'base_revision', 'created_at', 'expires_at', 'actor', 'authorization_ref', 'epoch', 'fencing_token'];
const KIND_FIELDS = Object.freeze({create: ['data', 'provenance'], patch: ['patch', 'confirm_fields'], status: ['patch'], ack_capture: ['processor', 'disposition'], delete: ['permanent'], restore: [], purge: [], merge: ['target_id', 'target_base_revision', 'target_data', 'reference_updates']});
const SAFE_ERRORS = new Set(['invalid_request', 'protocol_mismatch', 'unsupported_media_type', 'unsupported_authority_feature', 'unauthenticated', 'credential_expired', 'scope_forbidden', 'core_identity_mismatch', 'actor_not_authorized', 'origin_device_mismatch', 'not_found', 'op_not_found', 'method_not_allowed', 'payload_too_large', 'batch_not_supported', 'schema_not_ready', 'core_not_ready', 'backup_activation_unsupported', 'dedup_unavailable', 'domain_off', 'domain_frozen', 'invalid_base', 'incomplete_field_group', 'idempotency_conflict', 'stale_base', 'user_locked', 'superseded', 'id_exists', 'purge_target_alive', 'user_conflict', 'stale_delete', 'duplicate_restricted', 'reference_conflict', 'merge_too_large', 'resync_required', 'intent_expired', 'deleted_target', 'restore_window_expired', 'merge_restore_unsupported', 'domain_capacity_exceeded']);
function fail(code = 'invalid_request', status = 400) { throw Object.assign(new Error(code), {code, status}); }
function object(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function fields(value, allowed) {
  if (!object(value) || Object.keys(value).some(key => !allowed.includes(key))) fail();
}
function segment(raw) {
  let value;
  try { value = decodeURIComponent(raw); } catch { fail(); }
  // Decode once; a second encoded separator must not become a downstream path.
  if (!value || value === '.' || value === '..' || /[\s\u0000-\u001f\u007f/\\%?#]/u.test(value)) fail();
  return value;
}
function route(url) {
  const rawPath = url.split('?')[0];
  if (rawPath !== PREFIX && !rawPath.startsWith(`${PREFIX}/`)) return null;
  if (url.includes('#') || rawPath.includes('\\')) fail();
  const parts = rawPath.slice(PREFIX.length + 1).split('/').map(segment);
  if (parts.length === 2 && ['ops', 'ack', 'changes', 'snapshot'].includes(parts[1])) {
    return {domain: parts[0], resource: parts[1], method: ['ops', 'ack'].includes(parts[1]) ? 'POST' : 'GET'};
  }
  if (parts.length === 3 && ['ops', 'records'].includes(parts[1])) {
    return {domain: parts[0], resource: parts[1], id: parts[2], method: 'GET'};
  }
  fail('not_found', 404);
}
function singleHeader(request, name) {
  const headers = request.rawHeaders ?? [];
  let count = 0;
  for (let i = 0; i < headers.length; i += 2) if (headers[i].toLowerCase() === name) count++;
  if (count > 1) fail();
  return request.headers[name];
}
function query(url, endpoint) {
  const raw = url.includes('?') ? url.slice(url.indexOf('?') + 1) : '';
  if (/%(?![0-9a-f]{2})/i.test(raw)) fail();
  const params = new URLSearchParams(raw);
  const allowed = endpoint.method === 'POST' ? [] : endpoint.resource === 'changes' ? ['core_instance_id', 'cursor', 'limit'] : endpoint.resource === 'snapshot' ? ['core_instance_id', 'snapshot_token', 'page_token', 'limit'] : ['core_instance_id'];
  const result = {};
  for (const [key, value] of params) {
    if (!allowed.includes(key) || Object.hasOwn(result, key) || !value || /[\u0000-\u001f\u007f\ufffd]/u.test(value)) fail();
    result[key] = value;
  }
  if (endpoint.method === 'GET' && !result.core_instance_id) fail();
  if (endpoint.resource === 'changes' || endpoint.resource === 'snapshot') {
    if (result.limit !== undefined && (!/^[0-9]+$/.test(result.limit) || !Number.isSafeInteger(Number(result.limit)) || Number(result.limit) < 1 || Number(result.limit) > 500)) fail();
    result.limit = result.limit === undefined ? 100 : Number(result.limit);
  }
  return result;
}
function parseStrictJson(text) {
  const value = JSON.parse(text);
  const stack = [];
  // JSON.parse validates grammar; this pass rejects duplicate members at every depth.
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (char === '"') {
      const start = i;
      for (i++; i < text.length; i++) {
        if (text[i] === '\\') i++;
        else if (text[i] === '"') break;
      }
      const top = stack.at(-1);
      if (top?.keys && top.expectKey) {
        const key = JSON.parse(text.slice(start, i + 1));
        if (top.keys.has(key)) fail();
        top.keys.add(key);
        top.expectKey = false;
      }
    } else if (char === '{') stack.push({keys: new Set(), expectKey: true});
    else if (char === '[') stack.push({});
    else if (char === '}' || char === ']') stack.pop();
    else if (char === ',' && stack.at(-1)?.keys) stack.at(-1).expectKey = true;
  }
  return value;
}
async function readBody(request) {
  const length = singleHeader(request, 'content-length');
  if (length !== undefined && (!/^\d+$/.test(length) || Number(length) > MAX_BYTES)) fail('payload_too_large', 413);
  const encoding = singleHeader(request, 'content-encoding');
  if (encoding && encoding !== 'identity') fail('unsupported_media_type', 415);
  const type = singleHeader(request, 'content-type');
  if (typeof type !== 'string' || !/^application\/json(?:\s*;\s*charset=utf-8)?\s*$/i.test(type)) fail('unsupported_media_type', 415);
  // Event listeners avoid destroying the socket on a size rejection, allowing a 413 receipt.
  const buffer = await new Promise((resolve, reject) => {
    const chunks = []; let bytes = 0; let settled = false;
    const rejectOnce = (code, status) => { if (!settled) { settled = true; reject(Object.assign(new Error(code), {code, status})); } };
    request.on('data', chunk => {
      if (settled) return;
      bytes += chunk.length;
      if (bytes > MAX_BYTES) { chunks.length = 0; rejectOnce('payload_too_large', 413); return; }
      chunks.push(chunk);
    });
    request.once('end', () => { if (!settled) { settled = true; resolve(Buffer.concat(chunks)); } });
    request.once('aborted', () => rejectOnce('invalid_request', 400));
    request.once('error', () => rejectOnce('invalid_request', 400));
  });
  let body;
  try { body = parseStrictJson(new TextDecoder('utf-8', {fatal: true}).decode(buffer)); } catch { fail(); }
  if (Array.isArray(body) || (object(body) && (Object.hasOwn(body, 'ops') || Object.hasOwn(body, 'batch')))) fail('batch_not_supported', 413);
  if (!object(body)) fail();
  return body;
}
function validateBody(body, endpoint) {
  if (body.domain_protocol_version !== 1) fail('protocol_mismatch');
  if (typeof body.core_instance_id !== 'string' || !body.core_instance_id || /[\u0000-\u001f\u007f]/u.test(body.core_instance_id)) fail();
  if (endpoint.resource === 'ack') {
    fields(body, ['domain_protocol_version', 'core_instance_id', 'cursor', 'snapshot_id']);
    if (typeof body.cursor !== 'string' || !body.cursor || (body.snapshot_id !== undefined && (typeof body.snapshot_id !== 'string' || !body.snapshot_id))) fail();
  } else {
    if (!Object.hasOwn(KIND_FIELDS, body.kind)) fail();
    fields(body, [...COMMON, ...KIND_FIELDS[body.kind]]);
    if (body.epoch != null || body.fencing_token != null) fail('unsupported_authority_feature');
  }
}
function send(response, status, body, headers = {}) {
  const json = JSON.stringify(body);
  response.writeHead(status, {'content-type': 'application/json; charset=utf-8', 'content-length': Buffer.byteLength(json), 'cache-control': 'no-store', ...headers});
  response.end(json);
}
export function createDomainRequestHandler({getStore, authenticateDevice = () => null}) {
  return async function handleDomainRequest(request, response) {
    let endpoint;
    try {
      endpoint = route(request.url ?? '');
      if (!endpoint) return false;
      if (request.method !== endpoint.method) fail('method_not_allowed', 405);
      const store = getStore();
      if (!store) fail('schema_not_ready', 503);
      const authorization = singleHeader(request, 'authorization');
      if (typeof authorization !== 'string' || !/^Bearer [^\s,]+$/i.test(authorization)) fail('unauthenticated', 401);
      const token = authorization.slice(7);
      const principal = await store.authenticate(token);
      if (!principal) {
        if (await authenticateDevice(token)) fail('scope_forbidden', 403);
        fail('unauthenticated', 401);
      }
      const args = query(request.url, endpoint);
      let result;
      if (endpoint.method === 'POST') {
        const body = await readBody(request);
        validateBody(body, endpoint);
        result = endpoint.resource === 'ops' ? await store.submit(principal, endpoint.domain, body) : await store.acknowledge(principal, endpoint.domain, body);
      } else {
        if (singleHeader(request, 'x-i-core-domain-protocol') !== '1') fail('protocol_mismatch');
        if (endpoint.resource === 'ops') result = await store.getOperation(principal, endpoint.domain, endpoint.id, args.core_instance_id);
        else if (endpoint.resource === 'records') result = await store.getRecord(principal, endpoint.domain, endpoint.id, args.core_instance_id);
        else result = await store[endpoint.resource](principal, endpoint.domain, args);
      }
      if (!result || !Number.isInteger(result.status) || result.status < 200 || result.status > 599 || !object(result.body)) throw new Error('Invalid domain result');
      if (result.body.error !== undefined && result.body.outcome === undefined) {
        const code = typeof result.body.error === 'string' ? result.body.error : result.body.error?.code;
        if (!SAFE_ERRORS.has(code)) throw new Error('Unknown domain error');
        const body = {domain_protocol_version: 1, error: {code, retryable: result.status >= 500 || result.status === 429}};
        if (code === 'resync_required') {
          for (const key of ['reason', 'domain', 'core_instance_id', 'retained_watermark', 'snapshot']) {
            if (result.body[key] !== undefined) body[key] = result.body[key];
          }
        }
        if (code === 'deleted_target' && object(result.body.tombstone)) {
          body.tombstone = {};
          for (const key of ['domain', 'id', 'revision', 'deleted_at', 'merged_into', 'body_state', 'policy_version', 'core_instance_id']) {
            if (result.body.tombstone[key] !== undefined) body.tombstone[key] = result.body.tombstone[key];
          }
        }
        send(response, result.status, body);
      } else send(response, result.status, result.body);
    } catch (error) {
      request.resume();
      const known = SAFE_ERRORS.has(error?.code) && Number.isInteger(error?.status) && error.status >= 400 && error.status <= 599;
      const code = known ? error.code : 'internal_error';
      const status = known ? error.status : 500;
      if (!response.headersSent && !response.destroyed) send(response, status, {domain_protocol_version: 1, error: {code, retryable: status >= 500 || status === 429}}, status === 405 && endpoint ? {allow: endpoint.method} : {});
    }
    return true;
  };
}
