import http from 'node:http';

const HOST = '127.0.0.1';
const PORT = 47831;
const PREFIX = '/experimental/v1/runtime';
const REQUEST_LIMIT = 1024 * 1024;
// Event batches may carry many bounded text deltas; this remains finite while
// allowing the guardian's 1,000-event read window.
const RESPONSE_LIMIT = 4 * 1024 * 1024;
// CodexAppServerClient uses a 30s request deadline; allow its initial CLI
// session creation to return while preserving a finite outer transport bound.
const SESSION_DEADLINE_MS = 35000;
const MUTATION_DEADLINE_MS = 35000;
const EVENTS_DEADLINE_MS = 15000;
const CLOSE_DEADLINE_MS = 20000;
const ID = '[A-Za-z0-9_-]{1,256}';
const plain = value => value !== null && typeof value === 'object' && !Array.isArray(value)
  && [Object.prototype, null].includes(Object.getPrototypeOf(value));

export class WorkbenchProductGatewayTransportError extends Error {
  constructor(code) { super(code); this.code = code; }
}

const rejected = () => new WorkbenchProductGatewayTransportError('product_gateway_transport_rejected');
const unavailable = () => new WorkbenchProductGatewayTransportError('product_gateway_transport_unavailable');

/// Returns the only ordinary-Gateway transport accepted by the product host.
/// Its address is fixed here; optional request injection exists only for local
/// synthetic tests and cannot alter hostname, port, protocol, or path policy.
export function createWorkbenchProductGatewayTransport({ requestImpl = http.request } = {}) {
  return createTransport({ requestImpl });
}

/// Test-only seam: production callers use [createWorkbenchProductGatewayTransport].
/// It retains the same fixed address and path policy.
export function createWorkbenchProductGatewayTransportForTesting({ requestImpl = http.request, deadlineMs } = {}) {
  return createTransport({ requestImpl, deadlineMs });
}

function createTransport({ requestImpl, deadlineMs = null }) {
  if (typeof requestImpl !== 'function' || (deadlineMs !== null && (!Number.isSafeInteger(deadlineMs) || deadlineMs < 1 || deadlineMs > SESSION_DEADLINE_MS))) throw rejected();
  return async ({ method, path, body } = {}) => {
    const policy = allowed(method, path);
    if (!policy || (body !== undefined && !plain(body))) throw rejected();
    let payload;
    try {
      payload = body === undefined ? null : Buffer.from(JSON.stringify(body), 'utf8');
    } catch { throw rejected(); }
    if (payload && payload.byteLength > REQUEST_LIMIT) throw rejected();
    return exchange(requestImpl, policy, payload, deadlineMs ?? policy.deadlineMs);
  };
}

function allowed(method, path) {
  if (typeof method !== 'string' || typeof path !== 'string' || !path.startsWith(`${PREFIX}/`)
    || path.includes('://') || path.includes('#') || path.includes('\\') || path.includes('%')
    || /(?:^|\/)\.{1,2}(?:\/|$)/.test(path)) return null;
  const parse = value => {
    try { return new URL(value, 'http://fixed.invalid'); } catch { return null; }
  };
  const url = parse(path);
  if (!url || url.origin !== 'http://fixed.invalid' || url.hash || url.username || url.password) return null;
  const pathname = url.pathname;
  if (method === 'POST' && pathname === `${PREFIX}/sessions` && !url.search) return { method, path: pathname, deadlineMs: SESSION_DEADLINE_MS };
  if (method === 'GET' && new RegExp(`^${PREFIX}/sessions/${ID}/events$`).test(pathname)
    && [...url.searchParams.keys()].length <= 1 && [...url.searchParams.keys()].every(key => key === 'after')) {
    const after = url.searchParams.get('after') ?? '0';
    return /^\d+$/.test(after) && Number(after) <= Number.MAX_SAFE_INTEGER ? { method, path: `${pathname}?after=${after}`, deadlineMs: EVENTS_DEADLINE_MS } : null;
  }
  if (method === 'POST' && new RegExp(`^${PREFIX}/sessions/${ID}/turns$`).test(pathname) && !url.search) return { method, path: pathname, deadlineMs: MUTATION_DEADLINE_MS };
  if (method === 'POST' && new RegExp(`^${PREFIX}/sessions/${ID}/turns/${ID}/interrupt$`).test(pathname) && !url.search) return { method, path: pathname, deadlineMs: MUTATION_DEADLINE_MS };
  if (method === 'POST' && new RegExp(`^${PREFIX}/tool-calls/${ID}$`).test(pathname) && !url.search) return { method, path: pathname, deadlineMs: MUTATION_DEADLINE_MS };
  if (method === 'DELETE' && new RegExp(`^${PREFIX}/sessions/${ID}$`).test(pathname) && !url.search) return { method, path: pathname, deadlineMs: CLOSE_DEADLINE_MS };
  return null;
}

function exchange(requestImpl, policy, payload, deadlineMs) {
  return new Promise((resolve, reject) => {
    let settled = false;
    let timer;
    let request;
    let response;
    const destroy = () => {
      try { response?.destroy(); } catch {}
      try { request?.destroy(); } catch {}
    };
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      error ? reject(error) : resolve(value);
    };
    const options = Object.freeze({ protocol: 'http:', hostname: HOST, port: PORT, method: policy.method,
      path: policy.path, agent: false, headers: Object.freeze({ accept: 'application/json',
        ...(payload ? { 'content-type': 'application/json; charset=utf-8', 'content-length': String(payload.byteLength) } : {}) }) });
    try {
      request = requestImpl(options, incoming => {
        response = incoming;
        let ended = false;
        const failClosed = error => { destroy(); finish(error); };
        // These observers must exist before header validation. A malformed
        // response can otherwise retain a live socket after Promise rejection.
        response.once('aborted', () => failClosed(unavailable()));
        response.once('error', () => failClosed(unavailable()));
        response.once('close', () => { if (!ended) finish(unavailable()); });
        const contentType = response.headers?.['content-type'];
        if (!Number.isInteger(response.statusCode) || response.statusCode < 200 || response.statusCode >= 300
          || typeof contentType !== 'string' || !/^application\/json(?:\s*;\s*charset=(?:utf-8|utf8))?\s*$/i.test(contentType)) {
          failClosed(rejected()); return;
        }
        const chunks = [];
        let size = 0;
        response.on('data', chunk => {
          if (!(chunk instanceof Uint8Array)) { failClosed(rejected()); return; }
          size += chunk.byteLength;
          if (size > RESPONSE_LIMIT) { failClosed(rejected()); return; }
          chunks.push(Buffer.from(chunk));
        });
        response.once('end', () => {
          ended = true;
          let decoded;
          try { decoded = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks))); }
          catch { failClosed(rejected()); return; }
          if (!plain(decoded)) { failClosed(rejected()); return; }
          finish(null, decoded);
        });
      });
      request.once('error', () => { destroy(); finish(unavailable()); });
      timer = setTimeout(() => { destroy(); finish(unavailable()); }, deadlineMs);
      request.end(payload ?? undefined);
    } catch { finish(unavailable()); }
  });
}
