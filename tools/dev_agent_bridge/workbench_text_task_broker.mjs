// Host-owned candidate broker. No production adapter imports this module yet.
// The verifier must check the accepted socket against the isolated child held
// by the native supervisor; it is never supplied by an HTTP/RPC caller.
import { createServer as createNetServer } from 'node:net';
import { createServer as createHttpServer } from 'node:http';
import { normalizeTextOnlyRequest } from './workbench_request_text_gate.mjs';
import { exchangeTextOnly, TextGateTransportError, sanitizeTextTimeoutPhase,
  sanitizeTextResponseRejectionPhase, sanitizeTextResponseGateCode,
  sanitizeTextResponseSchemaLocation, sanitizeTextResponseEventKind,
  sanitizeTextResponseEventTypeClass, sanitizeTextResponseEventPhase, sanitizeTextResponseEventHeaderRelation,
  sanitizeTextResponseEventPayloadShape, sanitizeTextResponseEventControlKind } from './workbench_text_gate_transport.mjs';

export const TEXT_TASK_MODEL = 'gpt-5.6-sol';
export const TEXT_TASK_INSTRUCTIONS = 'Complete the authorized standalone text task. Return only text. Do not call tools or take external actions.';
const TARGET = 'https://chatgpt.com/backend-api/codex/responses';
const MAX_BODY = 256 * 1024;
const MAX_TASK = 32 * 1024;
const fail = () => { throw new Error('text_task_exchange_rejected'); };
const EXCHANGE_FAILURE_CODES = new Set(['timeout', 'aborted', 'http_status',
  'unsupported_content_type', 'missing_body', 'request_rejected', 'response_rejected', 'transport_failed']);

export function sanitizeTextTaskExchangeFailureCode(value) {
  return typeof value === 'string' && EXCHANGE_FAILURE_CODES.has(value) ? value : null;
}

export function sanitizeTextTaskExchangeTimeoutPhase(code, value) {
  return code === 'timeout' ? sanitizeTextTimeoutPhase(value) : null;
}

export function sanitizeTextTaskResponseRejectionPhase(code, value) {
  return code === 'response_rejected' ? sanitizeTextResponseRejectionPhase(value) : null;
}

export function sanitizeTextTaskResponseGateCode(code, value) {
  return code === 'response_rejected' ? sanitizeTextResponseGateCode(value) : null;
}

export function sanitizeTextTaskResponseEventKind(code, gateCode, value) {
  return code === 'response_rejected' && sanitizeTextTaskResponseGateCode(code, gateCode) === 'unsupported_event'
    ? sanitizeTextResponseEventKind(value) : null;
}

export function sanitizeTextTaskResponseEventTypeClass(code, gateCode, value) {
  return code === 'response_rejected' && sanitizeTextTaskResponseGateCode(code, gateCode) === 'unsupported_event'
    ? sanitizeTextResponseEventTypeClass(value) : null;
}

export function sanitizeTextTaskResponseEventPhase(code, gateCode, value) {
  return code === 'response_rejected' && sanitizeTextTaskResponseGateCode(code, gateCode) === 'unsupported_event'
    ? sanitizeTextResponseEventPhase(value) : null;
}

export function sanitizeTextTaskResponseEventHeaderRelation(code, gateCode, value) {
  return code === 'response_rejected' && sanitizeTextTaskResponseGateCode(code, gateCode) === 'unsupported_event'
    ? sanitizeTextResponseEventHeaderRelation(value) : null;
}

export function sanitizeTextTaskResponseEventPayloadShape(code, gateCode, value) {
  return code === 'response_rejected' && sanitizeTextTaskResponseGateCode(code, gateCode) === 'unsupported_event'
    ? sanitizeTextResponseEventPayloadShape(value) : null;
}

export function sanitizeTextTaskResponseEventControlKind(code, gateCode, value) {
  return code === 'response_rejected' && sanitizeTextTaskResponseGateCode(code, gateCode) === 'unsupported_event'
    ? sanitizeTextResponseEventControlKind(value) : null;
}

export function sanitizeTextTaskResponseSchemaLocation(code, gateCode, value) {
  return code === 'response_rejected' && sanitizeTextTaskResponseGateCode(code, gateCode) === 'unknown_field'
    ? sanitizeTextResponseSchemaLocation(value) : null;
}

function taskText(value) {
  if (typeof value !== 'string' || !value.trim() || Buffer.byteLength(value) > MAX_TASK
    || Buffer.from(value).toString('utf8') !== value) fail();
  return value;
}

export function authorizedTextTaskBody(body, authorizedInput) {
  const input = taskText(authorizedInput);
  const normalized = normalizeTextOnlyRequest(body, {
    model: TEXT_TASK_MODEL, maxBytes: MAX_BODY, maxMessages: 32,
  });
  const users = normalized.input.filter(item => item.role === 'user');
  const matches = item => item.content.length === 1 && item.content[0].text === input;
  if (!users.length || !matches(users.at(-1)) || users.filter(matches).length !== 1
    || normalized.input.some(item => item.role === 'assistant')) fail();
  // CLI environment, instructions, catalogs and history are not authorization.
  // Rebuild from the task input supplied by the host before arming this broker.
  return {
    model: TEXT_TASK_MODEL, instructions: TEXT_TASK_INSTRUCTIONS,
    input: [{ type: 'message', role: 'user', content: [{ type: 'input_text', text: input }] }],
    tools: [], tool_choice: 'none', parallel_tool_calls: false, store: false,
    stream: true, reasoning: { effort: 'low' },
  };
}

function readAuth(req) {
  const headers = {};
  for (let index = 0; index < req.rawHeaders.length; index += 2) {
    const key = req.rawHeaders[index].toLowerCase();
    if (!['authorization', 'chatgpt-account-id'].includes(key)) continue;
    if (Object.hasOwn(headers, key)) fail();
    headers[key] = req.rawHeaders[index + 1];
  }
  if (typeof headers.authorization !== 'string' || headers.authorization.length > 8192
    || !/^Bearer [A-Za-z0-9._~+/=-]+$/.test(headers.authorization)) fail();
  if (headers['chatgpt-account-id'] !== undefined
    && !/^[A-Za-z0-9_-]{1,200}$/.test(headers['chatgpt-account-id'])) fail();
  return headers;
}

function boundedVerification(verifyPeer, socket, milliseconds) {
  let timer;
  return Promise.race([
    Promise.resolve().then(() => verifyPeer(socket)),
    new Promise(resolve => { timer = setTimeout(() => resolve(false), milliseconds); }),
  ]).finally(() => clearTimeout(timer));
}

// Exchange injection exists for synthetic tests. Production wiring must use the
// default transport and a native process/connection verifier, with the pinned
// executable and network policy established before releasing the child.
export function createTextTaskBroker({ verifyPeer, exchange = exchangeTextOnly,
  peerTimeoutMs = 3000, exchangeTimeoutMs = 60000 } = {}) {
  if (typeof verifyPeer !== 'function' || typeof exchange !== 'function'
    || !Number.isSafeInteger(peerTimeoutMs) || peerTimeoutMs < 1 || peerTimeoutMs > 10000
    || !Number.isSafeInteger(exchangeTimeoutMs) || exchangeTimeoutMs < 1 || exchangeTimeoutMs > 300000) fail();
  let armedInput = null;
  let used = false;
  let stopped = false;
  let closePromise = null;
  const controller = new AbortController();
  const sockets = new Set();
  const pending = new Set();
  const observations = { admitted_connections: 0, rejected_connections: 0,
    parsed_requests: 0, metadata_rejections: 0, rejected_requests: 0,
    upstream_attempts: 0, response_released: false, drained: false,
    exchange_failure_code: null, exchange_timeout_phase: null,
    response_rejection_phase: null, response_gate_code: null, response_event_kind: null,
    response_event_type_class: null, response_event_phase: null, response_event_header_relation: null,
    response_event_payload_shape: null, response_event_control_kind: null, response_schema_location: null };
  const active = socket => !stopped && !socket.destroyed && !controller.signal.aborted;
  const verified = async socket => active(socket)
    && await boundedVerification(verifyPeer, socket, peerTimeoutMs) === true && active(socket);
  const track = promise => {
    pending.add(promise);
    void promise.then(() => pending.delete(promise), () => pending.delete(promise));
  };
  const revoke = () => {
    stopped = true;
    armedInput = null;
    controller.abort();
    for (const socket of sockets) socket.destroy();
  };
  const http = createHttpServer({ maxHeaderSize: 16 * 1024 }, (req, res) => {
    const work = (async () => {
      observations.parsed_requests++;
      let disconnected;
      try {
        if (!await verified(req.socket)) fail();
        if (req.method === 'GET' && /^\/v1\/models(?:\?[^\r\n]*)?$/.test(req.url || '')) {
          if (observations.metadata_rejections >= 8 || req.headers['content-encoding']
            || req.headers['transfer-encoding'] || ![undefined, '0'].includes(req.headers['content-length'])) fail();
          observations.metadata_rejections++;
          req.resume();
          res.writeHead(404, { 'content-type': 'application/json', connection: 'close' });
          res.end('{"error":{"type":"metadata_unavailable"}}');
          return;
        }
        if (!armedInput || used || req.method !== 'POST' || req.url !== '/v1/responses'
          || req.headers['content-encoding']
          || !/^application\/json(?:;\s*charset=utf-8)?$/i.test(req.headers['content-type'] || '')
          || (req.headers['content-length'] !== undefined
            && (!/^\d+$/.test(req.headers['content-length']) || Number(req.headers['content-length']) > MAX_BODY))) fail();
        const chunks = [];
        let size = 0;
        for await (const chunk of req) {
          if (!active(req.socket)) fail();
          size += chunk.length;
          if (size > MAX_BODY) fail();
          chunks.push(chunk);
        }
        const body = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks)));
        const outgoing = authorizedTextTaskBody(body, armedInput);
        if (!await verified(req.socket) || used) fail();
        const headers = readAuth(req);
        used = true; // Reserve before any asynchronous upstream operation.
        observations.upstream_attempts++;
        disconnected = () => { if (!res.writableFinished) revoke(); };
        res.once('close', disconnected);
        let result;
        try {
          result = await exchange(outgoing, {
            model: TEXT_TASK_MODEL, upstreamUrl: TARGET, headers, signal: controller.signal,
            timeoutMs: exchangeTimeoutMs, maxRequestBytes: MAX_BODY,
            maxInputBytes: 1024 * 1024, maxOutputBytes: 1024 * 1024,
            diagnoseRejectedResponse: false, diagnoseProtocolKeys: false,
          });
        } catch (error) {
          // Only the reserved exchange can supply this closed vocabulary. Local
          // request/peer/output failures and raw error details are never copied.
          if (error instanceof TextGateTransportError) {
            observations.exchange_failure_code = sanitizeTextTaskExchangeFailureCode(error.code);
            observations.exchange_timeout_phase = sanitizeTextTaskExchangeTimeoutPhase(
              observations.exchange_failure_code, error.timeoutPhase);
            observations.response_rejection_phase = sanitizeTextTaskResponseRejectionPhase(
              observations.exchange_failure_code, error.responseRejectionPhase);
            observations.response_gate_code = sanitizeTextTaskResponseGateCode(
              observations.exchange_failure_code, error.gateCode);
            observations.response_event_kind = sanitizeTextTaskResponseEventKind(
              observations.exchange_failure_code, observations.response_gate_code, error.responseEventKind);
            observations.response_event_type_class = sanitizeTextTaskResponseEventTypeClass(
              observations.exchange_failure_code, observations.response_gate_code, error.responseEventTypeClass);
            observations.response_event_phase = sanitizeTextTaskResponseEventPhase(
              observations.exchange_failure_code, observations.response_gate_code, error.responseEventPhase);
            observations.response_event_header_relation = sanitizeTextTaskResponseEventHeaderRelation(
              observations.exchange_failure_code, observations.response_gate_code, error.responseEventHeaderRelation);
            observations.response_event_payload_shape = sanitizeTextTaskResponseEventPayloadShape(
              observations.exchange_failure_code, observations.response_gate_code, error.responseEventPayloadShape);
            observations.response_event_control_kind = sanitizeTextTaskResponseEventControlKind(
              observations.exchange_failure_code, observations.response_gate_code, error.responseEventControlKind);
            observations.response_schema_location = sanitizeTextTaskResponseSchemaLocation(
              observations.exchange_failure_code, observations.response_gate_code, error.schemaLocation);
          }
          throw error;
        }
        if (!await verified(req.socket) || !Buffer.isBuffer(result)) fail();
        res.writeHead(200, { 'content-type': 'text/event-stream; charset=utf-8', connection: 'close' });
        res.end(result);
        observations.response_released = true;
      } catch {
        observations.rejected_requests++;
        // Never include the request, credentials, provider payload or raw error
        // in telemetry. A rejected attempt may not be retried through this broker.
        if (!res.destroyed && !res.headersSent) {
          res.writeHead(422, { 'content-type': 'application/json', connection: 'close' });
          res.end('{"error":{"type":"text_task_exchange_rejected"}}');
        } else if (!res.writableFinished) res.destroy();
      } finally {
        if (disconnected) res.removeListener('close', disconnected);
      }
    })();
    track(work);
  });
  http.requestTimeout = 10000;
  http.headersTimeout = 10000;
  http.maxRequestsPerSocket = 1;
  http.on('clientError', (_error, socket) => socket.destroy());
  // Parse no HTTP bytes until the OS-backed verifier admits this exact socket.
  const server = createNetServer({ pauseOnConnect: true }, socket => {
    sockets.add(socket);
    socket.once('close', () => sockets.delete(socket));
    socket.on('error', () => {});
    socket.setTimeout(Math.max(10000, exchangeTimeoutMs + 10000), () => socket.destroy());
    if (sockets.size > 8 || stopped) {
      observations.rejected_connections++;
      socket.destroy();
      return;
    }
    const admission = (async () => {
      try {
        if (!await verified(socket)) fail();
        observations.admitted_connections++;
        http.emit('connection', socket);
        socket.resume();
      } catch {
        observations.rejected_connections++;
        socket.destroy();
      }
    })();
    track(admission);
  });
  return Object.freeze({
    async listen() {
      if (server.listening || stopped) fail();
      await new Promise((resolve, reject) => {
        server.once('error', reject);
        server.listen(0, '127.0.0.1', () => { server.removeListener('error', reject); resolve(); });
      });
      return `http://127.0.0.1:${server.address().port}/v1`;
    },
    arm(input) {
      if (armedInput !== null || stopped || used || !server.listening) fail();
      armedInput = taskText(input);
    },
    revoke,
    snapshot() { return Object.freeze({ ...observations }); },
    close() {
      if (!closePromise) closePromise = (async () => {
        revoke();
        if (server.listening) await new Promise(resolve => server.close(resolve));
        while (pending.size) await Promise.allSettled([...pending]);
        observations.drained = true;
      })();
      return closePromise;
    },
  });
}
