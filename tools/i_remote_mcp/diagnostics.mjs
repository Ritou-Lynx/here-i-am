// Privacy boundary for operational diagnostics: never pass request/response objects to a sink.
import { appendFileSync, mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';

const PATHS = new Set(['/mcp', '/authorize', '/token', '/register',
  '/.well-known/oauth-protected-resource', '/.well-known/oauth-protected-resource/mcp',
  '/.well-known/oauth-authorization-server']);
const METHODS = new Set(['GET', 'POST', 'DELETE', 'HEAD', 'OPTIONS', 'PUT', 'PATCH']);
const RPC_METHODS = new Set(['initialize', 'ping', 'tools/list', 'tools/call', 'notifications/initialized']);
const TOOL_NAMES = new Set(['i_context', 'i_recall']);
const RPC_CODES = new Set([-32700, -32600, -32601, -32602, -32603, -32001]);
const CALLBACKS = ['https://claude.ai/api/mcp/auth_callback', 'https://claude.com/api/mcp/auth_callback'];

// User agents are self-reported and are not evidence of client identity.
export function userAgentFamily(value) {
  if (typeof value !== 'string' || !value) return 'absent';
  if (/claude|anthropic/i.test(value)) return 'claude';
  if (/Edg\//i.test(value)) return 'edge';
  if (/Firefox\//i.test(value)) return 'firefox';
  if (/Chrome\/|Chromium\//i.test(value)) return 'chromium';
  if (/Safari\//i.test(value)) return 'safari';
  if (/^curl\//i.test(value)) return 'curl';
  if (/^python-httpx\//i.test(value)) return 'python-httpx';
  if (/^python-requests\//i.test(value)) return 'python-requests';
  if (/node|undici/i.test(value)) return 'node';
  return 'other';
}

// Only known endpoints survive. Even an otherwise valid URL may contain secrets
// in its hostname or path; removing query strings alone is not sufficient.
function endpoint(value, known) {
  if (value === null || value === undefined || value === '') return null;
  try {
    const url = new URL(value);
    const clean = `${url.origin}${url.pathname}`;
    return known.includes(clean) ? clean : '[redacted]';
  } catch { return '[redacted]'; }
}

export function createRequestDiagnostics(req, { issuer, resource, diagnostic = () => {}, now = Date.now }) {
  let url;
  try { url = new URL(req.url, issuer); } catch { /* Only fixed labels below. */ }
  const base = {
    method: METHODS.has(req.method) ? req.method : 'OTHER',
    path: PATHS.has(url?.pathname) ? url.pathname : '[redacted]',
    ua_family: userAgentFamily(req.headers['user-agent']),
    origin: endpoint(req.headers.origin, ['https://claude.ai/', 'https://claude.com/', `${issuer}/`]),
  };
  if (base.method === 'GET' && base.path === '/authorize') {
    const query = Object.fromEntries(url.searchParams);
    base.callback = endpoint(query.redirect_uri, CALLBACKS);
    base.resource = endpoint(query.resource, [resource, `${resource}/`]);
  }
  const rpc = [];
  function emit(event, status, fields = {}) {
    try {
      const record = Object.freeze({ timestamp: new Date(now()).toISOString(), event, ...base, status, ...fields });
      // Optional sinks must not affect protocol responses, including rejected promises.
      Promise.resolve(diagnostic(record)).catch(() => {});
    } catch { /* Logging failures cannot change protocol behavior. */ }
  }
  return {
    rpc(message, response, { dataSourceFailed = false } = {}) {
      const method = RPC_METHODS.has(message?.method) ? message.method : 'other';
      const fields = { rpc_method: method };
      if (method === 'tools/call') fields.tool = TOOL_NAMES.has(message?.params?.name) ? message.params.name : 'other';
      fields.outcome = response?.error || response?.result?.isError ? 'error' : response ? 'success' : 'no_response';
      if (response?.error) fields.error_code = RPC_CODES.has(response.error.code) ? response.error.code : 'rpc_error';
      else if (response?.result?.isError) fields.error_code = dataSourceFailed ? 'data_source_unavailable' : 'tool_error';
      rpc.push(fields);
    },
    finish(status, { internalError = false } = {}) {
      emit('http_request', status, internalError ? { error_code: 'internal_error' } : {});
      for (const fields of rpc) emit('mcp_rpc', status, fields);
    },
  };
}

// Receives only the projected records supplied by createApp({ diagnostic }).
// Append is synchronous so shutdown does not discard a pending in-memory buffer.
export function createJsonlDiagnosticWriter({ logDir, onWriteError = () => {} }) {
  const directory = resolve(logDir);
  mkdirSync(directory, { recursive: true });
  return (record) => {
    try {
      if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(record?.timestamp)) throw new Error();
      appendFileSync(join(directory, `${record.timestamp.slice(0, 10)}.jsonl`), `${JSON.stringify(record)}\n`, { encoding: 'utf8', mode: 0o600 });
    } catch {
      // No OS error text or filesystem path can escape through diagnostics.
      try { Promise.resolve(onWriteError('diagnostic_write_failed')).catch(() => {}); } catch { /* best effort */ }
    }
  };
}
