import { normalizeTextOnlyRequest, TextOnlyRequestError } from './workbench_request_text_gate.mjs';
import { createTextOnlyResponseGate, ResponseTextGateError, sanitizeTextResponseEventKind,
  sanitizeTextResponseEventTypeClass, sanitizeTextResponseEventPhase, sanitizeTextResponseEventHeaderRelation,
  sanitizeTextResponseEventPayloadShape, sanitizeTextResponseEventControlKind } from './workbench_response_text_gate.mjs';
import { inspectRejectedTextResponse } from './workbench_response_text_diagnostics.mjs';
export { sanitizeTextResponseEventKind, sanitizeTextResponseEventTypeClass,
  sanitizeTextResponseEventPhase, sanitizeTextResponseEventHeaderRelation,
  sanitizeTextResponseEventPayloadShape, sanitizeTextResponseEventControlKind } from './workbench_response_text_gate.mjs';

// These milestones describe only what this transport observed locally.
// Reader EOF does not establish provider completion or successful validation.
export function sanitizeTextTimeoutPhase(value) {
  return typeof value === 'string' && [
    'request_preparation', 'before_response_headers', 'response_headers_before_body_byte',
    'response_body_before_eof', 'after_response_eof',
  ].includes(value) ? value : null;
}

// Local validator categories only. Unknown future codes remain unreported;
// no upstream field name, value or arbitrary error string belongs here.
export function sanitizeTextResponseRejectionPhase(value) {
  return typeof value === 'string' && ['before_eof', 'after_eof'].includes(value) ? value : null;
}

export function sanitizeTextResponseGateCode(value) {
  return typeof value === 'string' && [
    'invalid_shape', 'unknown_field', 'invalid_response_metadata', 'invalid_terminal',
    'invalid_json', 'json_complexity_limit', 'duplicate_json_key', 'unsupported_content',
    'unsupported_item', 'empty_message', 'unsupported_sse', 'truncated_sse',
    'duplicate_sse_event', 'event_limit', 'invalid_done_sentinel', 'event_after_terminal',
    'unsupported_event', 'event_type_conflict', 'sequence_conflict', 'duplicate_created',
    'missing_created', 'response_id_conflict', 'invalid_progress', 'output_conflict',
    'item_order_conflict', 'duplicate_item', 'item_id_conflict', 'text_conflict',
    'part_order_conflict', 'text_order_conflict', 'missing_completed', 'missing_assistant_text',
    'output_limit', 'invalid_options', 'invalid_state', 'invalid_chunk', 'input_limit', 'invalid_utf8',
  ].includes(value) ? value : null;
}

export function sanitizeTextResponseSchemaLocation(value) {
  return typeof value === 'string' && [
    'unclassified', 'text_part', 'message', 'response', 'sse_response',
    'sse_item', 'sse_content_part', 'sse_text_delta', 'sse_text_done',
  ].includes(value) ? value : null;
}

export class TextGateTransportError extends Error {
  constructor(code, { httpStatus, gateCode, timeoutPhase, responseRejectionPhase, responseEventKind,
    responseEventTypeClass, responseEventPhase, responseEventHeaderRelation, responseEventPayloadShape,
    responseEventControlKind } = {}) {
    super(`Text-only transport rejected exchange: ${code}`);
    this.name = 'TextGateTransportError';
    this.code = code;
    if (httpStatus !== undefined) this.httpStatus = httpStatus;
    if (gateCode !== undefined) this.gateCode = gateCode;
    const phase = code === 'timeout' ? sanitizeTextTimeoutPhase(timeoutPhase) : null;
    if (phase !== null) this.timeoutPhase = phase;
    const rejectionPhase = code === 'response_rejected' ? sanitizeTextResponseRejectionPhase(responseRejectionPhase) : null;
    if (rejectionPhase !== null) this.responseRejectionPhase = rejectionPhase;
    const eventKind = code === 'response_rejected' && sanitizeTextResponseGateCode(gateCode) === 'unsupported_event'
      ? sanitizeTextResponseEventKind(responseEventKind) : null;
    if (eventKind !== null) this.responseEventKind = eventKind;
    const typeClass = code === 'response_rejected' && sanitizeTextResponseGateCode(gateCode) === 'unsupported_event'
      ? sanitizeTextResponseEventTypeClass(responseEventTypeClass) : null;
    if (typeClass !== null) this.responseEventTypeClass = typeClass;
    const eventPhase = code === 'response_rejected' && sanitizeTextResponseGateCode(gateCode) === 'unsupported_event'
      ? sanitizeTextResponseEventPhase(responseEventPhase) : null;
    if (eventPhase !== null) this.responseEventPhase = eventPhase;
    const headerRelation = code === 'response_rejected' && sanitizeTextResponseGateCode(gateCode) === 'unsupported_event'
      ? sanitizeTextResponseEventHeaderRelation(responseEventHeaderRelation) : null;
    if (headerRelation !== null) this.responseEventHeaderRelation = headerRelation;
    const payloadShape = code === 'response_rejected' && sanitizeTextResponseGateCode(gateCode) === 'unsupported_event'
      ? sanitizeTextResponseEventPayloadShape(responseEventPayloadShape) : null;
    if (payloadShape !== null) this.responseEventPayloadShape = payloadShape;
    const controlKind = code === 'response_rejected' && sanitizeTextResponseGateCode(gateCode) === 'unsupported_event'
      ? sanitizeTextResponseEventControlKind(responseEventControlKind) : null;
    if (controlKind !== null) this.responseEventControlKind = controlKind;
  }
}

// Diagnostic vocabulary is fixed: no upstream header values or body fragments
// are retained, even when a provider returns an unsupported response format.
export function inspectResponseMetadata(status, contentType) {
  const parts = String(contentType || '').slice(0, 1024).toLowerCase().split(';');
  const media = parts.shift().trim();
  const charsets = parts.filter(part => /^\s*charset\s*=/.test(part))
    .map(part => part.slice(part.indexOf('=') + 1).trim().replace(/^"(.*)"$/, '$1'));
  const knownMedia = ['text/event-stream', 'application/json', 'text/plain', 'text/html', 'application/octet-stream'];
  return { http_status: Number.isInteger(status) && status >= 100 && status <= 599 ? status : null,
    media_type: knownMedia.includes(media) ? media : media === '' ? 'missing' : 'other',
    parameter_count: parts.length,
    charset: charsets.length === 0 ? 'absent' : charsets.length > 1 ? 'ambiguous'
      : ['utf-8', 'utf8'].includes(charsets[0]) ? charsets[0] : 'other' };
}

const reject = (code) => { throw new TextGateTransportError(code); };

export function selectTextResponseFormat(contentType, target, stream) {
  // The fixed ChatGPT endpoint has been observed to return SSE without this
  // header. Select the expected parser only here; this is never acceptance.
  if (contentType === null && target === 'https://chatgpt.com/backend-api/codex/responses' && stream === true) return 'sse';
  if (typeof contentType !== 'string') return null;
  const matched = /^(text\/event-stream|application\/json)(?:\s*;\s*charset=(?:utf-8|"utf-8"))?\s*$/i.exec(contentType);
  return matched ? matched[1].toLowerCase() === 'application/json' ? 'json' : 'sse' : null;
}

function fixedTarget(value) {
  if (typeof value !== 'string') reject('invalid_target');
  if (value === 'https://chatgpt.com/backend-api/codex/responses') return value;
  const loopback = /^http:\/\/127\.0\.0\.1:([1-9][0-9]{0,4})\/v1\/responses$/.exec(value);
  if (!loopback || Number(loopback[1]) > 65535) reject('invalid_target');
  return value;
}

function requestHeaders(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(value))) reject('invalid_headers');
  const result = { 'content-type': 'application/json', accept: 'text/event-stream, application/json' };
  const seen = new Set();
  for (const [rawName, header] of Object.entries(value)) {
    const name = rawName.toLowerCase();
    if (seen.has(name) || !['authorization', 'chatgpt-account-id'].includes(name) ||
        typeof header !== 'string' || header.length > 8192) reject('invalid_headers');
    seen.add(name);
    if (name === 'authorization' && !/^Bearer [A-Za-z0-9._~+/=-]+$/.test(header)) reject('invalid_headers');
    if (name === 'chatgpt-account-id' && !/^[A-Za-z0-9_-]{1,200}$/.test(header)) reject('invalid_headers');
    result[name] = header;
  }
  return result;
}

function bounded(value, maximum = 16 * 1024 * 1024) {
  if (!Number.isSafeInteger(value) || value < 1 || value > maximum) reject('invalid_limits');
  return value;
}

// Candidate transport, not production routing. Only caller configuration can
// choose the exact target; neither the body nor headers can override it.
export async function exchangeTextOnly(body, {
  model, upstreamUrl, headers = {}, signal, timeoutMs = 10_000,
  maxRequestBytes = 1024 * 1024, maxMessages = 128,
  maxInputBytes = 1024 * 1024, maxOutputBytes = 2 * 1024 * 1024, maxEvents = 4096,
  diagnoseRejectedResponse = false,
  diagnoseProtocolKeys = false,
} = {}) {
  const startedAt = performance.now();
  let deadline = Infinity;
  let timer;
  let response;
  let reader;
  let output;
  let externalAbort;
  let timedOut = false;
  let diagnosticChunks = [];
  let diagnosticSize = 0;
  let responseEof = false;
  let timeoutPhase = 'request_preparation';
  let protocolDiagnosisAllowed = false;
  const controller = new AbortController();
  const checkActive = () => {
    if (signal?.aborted) reject('aborted');
    if (timedOut || performance.now() >= deadline) throw new TextGateTransportError('timeout', { timeoutPhase });
  };
  try {
    deadline = startedAt + bounded(timeoutMs, 300_000);
    if (signal !== undefined && !(signal instanceof AbortSignal)) reject('invalid_signal');
    checkActive();
    const target = fixedTarget(upstreamUrl);
    const outgoingHeaders = requestHeaders(headers);
    const limits = {
      maxInputBytes: bounded(maxInputBytes), maxOutputBytes: bounded(maxOutputBytes), maxEvents: bounded(maxEvents),
    };
    if (typeof diagnoseRejectedResponse !== 'boolean' || typeof diagnoseProtocolKeys !== 'boolean') reject('invalid_limits');
    const request = normalizeTextOnlyRequest(body, {
      model, maxBytes: bounded(maxRequestBytes), maxMessages: bounded(maxMessages),
    });
    if (diagnoseProtocolKeys) {
      const only = request.input[0];
      if (!diagnoseRejectedResponse || target !== 'https://chatgpt.com/backend-api/codex/responses'
        || request.model !== 'gpt-5.6-sol'
        || request.instructions !== 'This is a fixed synthetic text probe. Follow the user instruction.'
        || request.input.length !== 1 || only?.role !== 'user' || only.content.length !== 1
        || only.content[0].text !== 'Reply exactly: P6_TEXT_GATE_OK') reject('invalid_diagnostic_scope');
      protocolDiagnosisAllowed = true;
    }
    checkActive();
    externalAbort = () => controller.abort();
    signal?.addEventListener('abort', externalAbort, { once: true });
    timer = setTimeout(() => { timedOut = true; controller.abort(); }, Math.max(1, deadline - performance.now()));
    timeoutPhase = 'before_response_headers';
    response = await fetch(target, {
      method: 'POST', headers: outgoingHeaders, body: JSON.stringify(request),
      redirect: 'manual', signal: controller.signal,
    });
    timeoutPhase = 'response_headers_before_body_byte';
    checkActive();
    if (response.status < 200 || response.status >= 300) {
      throw new TextGateTransportError('http_status', { httpStatus: response.status });
    }
    const contentType = response.headers.get('content-type');
    const format = selectTextResponseFormat(contentType, target, request.stream);
    if (!format) {
      const rejected = new TextGateTransportError('unsupported_content_type');
      // Opt-in probe diagnostics do not select a parser or release any output.
      // Read a small rejected body only to summarize its structure after EOF.
      if (diagnoseRejectedResponse && response.body) {
        reader = response.body.getReader();
        const chunks = []; let size = 0;
        while (true) {
          const chunk = await reader.read();
          if (chunk.done) timeoutPhase = 'after_response_eof';
          else if (chunk.value?.byteLength > 0) timeoutPhase = 'response_body_before_eof';
          checkActive();
          if (chunk.done) break;
          size += chunk.value.byteLength;
          if (size > Math.min(limits.maxInputBytes, 256 * 1024)) reject('diagnostic_input_limit');
          chunks.push(Buffer.from(chunk.value));
        }
        checkActive();
        rejected.responseDiagnostics = inspectRejectedTextResponse(Buffer.concat(chunks));
      }
      throw rejected;
    }
    if (!response.body) reject('missing_body');
    const gate = createTextOnlyResponseGate({
      format, ...limits,
    });
    reader = response.body.getReader();
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) timeoutPhase = 'after_response_eof';
      else if (chunk.value?.byteLength > 0) timeoutPhase = 'response_body_before_eof';
      checkActive();
      if (chunk.done) { responseEof = true; break; }
      if (diagnoseRejectedResponse && diagnosticChunks) {
        diagnosticSize += chunk.value.byteLength;
        if (diagnosticSize <= Math.min(limits.maxInputBytes, 256 * 1024)) diagnosticChunks.push(Buffer.from(chunk.value));
        else diagnosticChunks = null;
      }
      gate.push(chunk.value);
    }
    // Only reader EOF is authoritative. A response.completed event is not EOF,
    // and gate.finish itself can consume part of the remaining time budget.
    checkActive();
    output = gate.finish();
    checkActive();
  } catch (error) {
    // Never expose fetch error messages, URLs, signal reasons, auth, or bodies.
    checkActive();
    const metadata = response ? inspectResponseMetadata(response.status, response.headers.get('content-type')) : null;
    if (error instanceof TextGateTransportError) {
      if (metadata) error.responseMetadata = metadata;
      throw error;
    }
    if (error instanceof TextOnlyRequestError) {
      throw new TextGateTransportError('request_rejected', { gateCode: error.code });
    }
    if (error instanceof ResponseTextGateError) {
      const rejected = new TextGateTransportError('response_rejected', {
        gateCode: sanitizeTextResponseGateCode(error.code),
        responseRejectionPhase: responseEof ? 'after_eof' : 'before_eof',
        responseEventKind: error.code === 'unsupported_event' ? error.eventKind : null,
        responseEventTypeClass: error.code === 'unsupported_event' ? error.eventTypeClass : null,
        responseEventPhase: error.code === 'unsupported_event' ? error.eventPhase : null,
        responseEventHeaderRelation: error.code === 'unsupported_event' ? error.eventHeaderRelation : null,
        responseEventPayloadShape: error.code === 'unsupported_event' ? error.eventPayloadShape : null,
        responseEventControlKind: error.code === 'unsupported_event' ? error.eventControlKind : null,
      });
      const location = error.code === 'unknown_field' ? sanitizeTextResponseSchemaLocation(error.schemaLocation) : null;
      if (location !== null) rejected.schemaLocation = location;
      if (metadata) rejected.responseMetadata = metadata;
      if (diagnoseRejectedResponse && responseEof && diagnosticChunks) {
        rejected.responseDiagnostics = inspectRejectedTextResponse(Buffer.concat(diagnosticChunks), {
          includeProtocolKeys: protocolDiagnosisAllowed && error.code === 'unknown_field',
        });
      }
      throw rejected;
    }
    throw new TextGateTransportError('transport_failed');
  } finally {
    clearTimeout(timer);
    if (externalAbort) signal?.removeEventListener('abort', externalAbort);
    controller.abort();
    if (reader) {
      try { await reader.cancel(); } catch { /* Network errors are already classified. */ }
      try { reader.releaseLock(); } catch { /* No readable stream is retained. */ }
    } else if (response?.body) {
      try { await response.body.cancel(); } catch { /* Discard rejected HTTP bodies. */ }
    }
  }
  checkActive();
  return output;
}
