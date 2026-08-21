export const RUNTIME_ADAPTER_SCHEMA_VERSION = 1;

export const RuntimeCapability = Object.freeze({
  AUTH_STATUS: 'auth_status',
  MODEL_DISCOVERY: 'model_discovery',
  SESSION_START: 'session_start',
  SESSION_RESUME: 'session_resume',
  TURN_START: 'turn_start',
  TURN_STEER: 'turn_steer',
  TURN_INTERRUPT: 'turn_interrupt',
  APPROVAL_RESPONSE: 'approval_response',
  TOOL_CALL_RESPONSE: 'tool_call_response',
  EVENT_STREAM: 'event_stream',
  SESSION_CLOSE: 'session_close',
});

export const RuntimeEventKind = Object.freeze({
  SESSION_STATUS: 'session_status',
  TURN_STATUS: 'turn_status',
  ACTIVITY: 'activity',
  MESSAGE_DELTA: 'message_delta',
  MESSAGE: 'message',
  TOOL_CALL: 'tool_call',
  TOOL_RESULT: 'tool_result',
  APPROVAL_REQUEST: 'approval_request',
  APPROVAL_RESOLVED: 'approval_resolved',
  USAGE: 'usage',
  WARNING: 'warning',
  ERROR: 'error',
});

export const RuntimeStatus = Object.freeze({
  STARTING: 'starting',
  ACTIVE: 'active',
  IDLE: 'idle',
  RUNNING: 'running',
  WAITING_APPROVAL: 'waiting_approval',
  COMPLETED: 'completed',
  FAILED: 'failed',
  INTERRUPTED: 'interrupted',
  CLOSED: 'closed',
  UNAVAILABLE: 'unavailable',
});

export const RuntimeErrorCode = Object.freeze({
  RUNTIME_UNAVAILABLE: 'runtime_unavailable',
  AUTHENTICATION_REQUIRED: 'authentication_required',
  UNSUPPORTED_CAPABILITY: 'unsupported_capability',
  INVALID_REQUEST: 'invalid_request',
  SESSION_NOT_FOUND: 'session_not_found',
  TURN_NOT_FOUND: 'turn_not_found',
  TURN_NOT_ACTIVE: 'turn_not_active',
  APPROVAL_NOT_FOUND: 'approval_not_found',
  TOOL_CALL_NOT_FOUND: 'tool_call_not_found',
  MODEL_UNAVAILABLE: 'model_unavailable',
  TIMEOUT: 'timeout',
  PROVIDER_ERROR: 'provider_error',
  PROTOCOL_ERROR: 'protocol_error',
});

export class RuntimeAdapterError extends Error {
  constructor(message, {
    code = RuntimeErrorCode.PROVIDER_ERROR,
    retryable = false,
    operation = null,
    details = null,
    providerMetadata = null,
    cause = null,
  } = {}) {
    super(String(message), cause ? { cause } : undefined);
    this.name = 'RuntimeAdapterError';
    this.code = code;
    this.retryable = retryable === true;
    this.operation = operation;
    this.details = details;
    this.providerMetadata = providerMetadata;
  }

  toJSON() {
    return {
      schema_version: RUNTIME_ADAPTER_SCHEMA_VERSION,
      code: this.code,
      message: this.message,
      retryable: this.retryable,
      ...(this.operation ? { operation: this.operation } : {}),
      ...(this.details == null ? {} : { details: this.details }),
      ...(this.providerMetadata == null
        ? {}
        : { provider_metadata: this.providerMetadata }),
    };
  }
}

export class RuntimeAdapter {
  getAuthStatus() {
    return this._unsupported('getAuthStatus');
  }

  listCapabilities() {
    return this._unsupported('listCapabilities');
  }

  startSession(_config, _contextManifest) {
    return this._unsupported('startSession');
  }

  resumeSession(_providerSessionId, _config) {
    return this._unsupported('resumeSession');
  }

  startTurn(_sessionId, _input) {
    return this._unsupported('startTurn');
  }

  steerTurn(_sessionId, _turnId, _input) {
    return this._unsupported('steerTurn');
  }

  interruptTurn(_sessionId, _turnId) {
    return this._unsupported('interruptTurn');
  }

  respondToApproval(_requestId, _decision) {
    return this._unsupported('respondToApproval');
  }

  respondToToolCall(_toolCallId, _result) {
    return this._unsupported('respondToToolCall');
  }

  streamEvents(_sessionId) {
    return this._unsupported('streamEvents');
  }

  closeSession(_sessionId) {
    return this._unsupported('closeSession');
  }

  _unsupported(operation) {
    throw new RuntimeAdapterError(`Runtime capability is not implemented: ${operation}`, {
      code: RuntimeErrorCode.UNSUPPORTED_CAPABILITY,
      operation,
    });
  }
}

export function createRuntimeEvent({
  sequence,
  sessionId,
  turnId = null,
  kind,
  status = null,
  data = {},
  providerMetadata = null,
  occurredAt = new Date().toISOString(),
}) {
  if (!Number.isInteger(sequence) || sequence < 1) {
    throw new RuntimeAdapterError('Runtime event sequence must be a positive integer.', {
      code: RuntimeErrorCode.PROTOCOL_ERROR,
      operation: 'createRuntimeEvent',
    });
  }
  if (!sessionId || !Object.values(RuntimeEventKind).includes(kind)) {
    throw new RuntimeAdapterError('Runtime event requires a session and known kind.', {
      code: RuntimeErrorCode.PROTOCOL_ERROR,
      operation: 'createRuntimeEvent',
    });
  }
  return {
    schema_version: RUNTIME_ADAPTER_SCHEMA_VERSION,
    event_id: `${sessionId}:${sequence}`,
    sequence,
    occurred_at: occurredAt,
    session_id: sessionId,
    ...(turnId ? { turn_id: turnId } : {}),
    kind,
    ...(status ? { status } : {}),
    data: data && typeof data === 'object' ? data : {},
    ...(providerMetadata == null ? {} : { provider_metadata: providerMetadata }),
  };
}

export function normalizeRuntimeTextInput(input, operation = 'startTurn') {
  if (typeof input === 'string' && input.trim()) return input;
  const blocks = Array.isArray(input) ? input : input?.content;
  if (Array.isArray(blocks)) {
    const text = blocks
      .filter((block) => block?.type === 'text' && typeof block.text === 'string')
      .map((block) => block.text)
      .join('\n')
      .trim();
    if (text) return text;
  }
  throw new RuntimeAdapterError('Runtime input must contain non-empty text.', {
    code: RuntimeErrorCode.INVALID_REQUEST,
    operation,
  });
}

export function asRuntimeAdapterError(error, {
  operation = null,
  provider = null,
  code = null,
} = {}) {
  if (error instanceof RuntimeAdapterError) return error;
  const providerCode = error?.code ?? null;
  const text = error instanceof Error ? error.message : String(error);
  const timeout = String(providerCode || '').includes('timeout') || /timed out/i.test(text);
  return new RuntimeAdapterError(text, {
    code: code || (timeout ? RuntimeErrorCode.TIMEOUT : RuntimeErrorCode.PROVIDER_ERROR),
    retryable: timeout,
    operation,
    providerMetadata: provider
      ? { provider, provider_error_code: providerCode }
      : null,
    cause: error instanceof Error ? error : null,
  });
}
