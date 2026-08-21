import { randomUUID } from 'node:crypto';
import { EventEmitter } from 'node:events';

import {
  CodexAppServerClient,
} from './codex_app_server_client.mjs';
import {
  RuntimeAdapter,
  RuntimeAdapterError,
  RuntimeCapability,
  RuntimeErrorCode,
  RuntimeEventKind,
  RuntimeStatus,
  asRuntimeAdapterError,
  createRuntimeEvent,
  normalizeRuntimeTextInput,
} from './runtime_adapter.mjs';

const CODEX_CAPABILITIES = Object.freeze([
  RuntimeCapability.AUTH_STATUS,
  RuntimeCapability.MODEL_DISCOVERY,
  RuntimeCapability.SESSION_START,
  RuntimeCapability.SESSION_RESUME,
  RuntimeCapability.TURN_START,
  RuntimeCapability.TURN_STEER,
  RuntimeCapability.TURN_INTERRUPT,
  RuntimeCapability.APPROVAL_RESPONSE,
  RuntimeCapability.TOOL_CALL_RESPONSE,
  RuntimeCapability.EVENT_STREAM,
  RuntimeCapability.SESSION_CLOSE,
]);

const DEFAULT_ACTIVITY_TIMEOUT_MS = 15_000;
const DEFAULT_CLOSE_TIMEOUT_MS = 15_000;
const MAX_EVENT_HISTORY = 1_000;
const MAX_DYNAMIC_TOOLS = 16;
const MAX_DYNAMIC_TOOL_DESCRIPTION_CHARS = 1_000;
const MAX_DYNAMIC_TOOL_SCHEMA_BYTES = 64 * 1024;
const MAX_TOOL_RESULT_ITEMS = 16;
const MAX_TOOL_RESULT_TEXT_CHARS = 64 * 1024;

function providerThreadId(params) {
  return params?.threadId || params?.thread?.id || null;
}

function providerTurnId(params) {
  return params?.turnId || params?.turn?.id || params?.item?.turnId || null;
}

function modelId(model) {
  return String(model?.id || model?.model || '').trim();
}

function terminalTurnStatus(status) {
  return [
    RuntimeStatus.COMPLETED,
    RuntimeStatus.FAILED,
    RuntimeStatus.INTERRUPTED,
  ].includes(status);
}

function normalizeCompletedStatus(status) {
  switch (String(status || '').toLowerCase()) {
    case 'completed':
      return RuntimeStatus.COMPLETED;
    case 'interrupted':
    case 'cancelled':
    case 'canceled':
      return RuntimeStatus.INTERRUPTED;
    default:
      return RuntimeStatus.FAILED;
  }
}

function isTurnActivity(method) {
  return method.startsWith('item/') && (
    method.endsWith('/started') ||
    method.endsWith('/delta') ||
    method.includes('/delta/')
  );
}

function safeProviderMetadata(method, extra = {}) {
  return {
    provider: 'codex',
    ...(method ? { method } : {}),
    ...extra,
  };
}

function normalizeDynamicTools(value, operation) {
  if (value == null) return null;
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_DYNAMIC_TOOLS) {
    throw new RuntimeAdapterError(`dynamic_tools must contain 1..${MAX_DYNAMIC_TOOLS} tools.`, {
      code: RuntimeErrorCode.INVALID_REQUEST,
      operation,
    });
  }
  const names = new Set();
  return value.map((tool) => {
    if (!tool || typeof tool !== 'object' || Array.isArray(tool)) {
      throw new RuntimeAdapterError('Each dynamic tool must be an object.', {
        code: RuntimeErrorCode.INVALID_REQUEST,
        operation,
      });
    }
    const name = String(tool.name || '').trim();
    const description = String(tool.description || '').trim();
    const inputSchema = tool.input_schema;
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(name) || names.has(name)) {
      throw new RuntimeAdapterError('Dynamic tool names must be unique portable names.', {
        code: RuntimeErrorCode.INVALID_REQUEST,
        operation,
      });
    }
    if (!description || description.length > MAX_DYNAMIC_TOOL_DESCRIPTION_CHARS) {
      throw new RuntimeAdapterError('Dynamic tool descriptions must be non-empty and bounded.', {
        code: RuntimeErrorCode.INVALID_REQUEST,
        operation,
      });
    }
    if (!inputSchema || typeof inputSchema !== 'object' || Array.isArray(inputSchema)) {
      throw new RuntimeAdapterError('Dynamic tools require an object input_schema.', {
        code: RuntimeErrorCode.INVALID_REQUEST,
        operation,
      });
    }
    if (Buffer.byteLength(JSON.stringify(inputSchema)) > MAX_DYNAMIC_TOOL_SCHEMA_BYTES) {
      throw new RuntimeAdapterError('Dynamic tool input_schema is too large.', {
        code: RuntimeErrorCode.INVALID_REQUEST,
        operation,
      });
    }
    names.add(name);
    return {
      type: 'function',
      name,
      description,
      inputSchema,
      deferLoading: tool.defer_loading === true,
    };
  });
}

function normalizeToolCallResult(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new RuntimeAdapterError('Tool call result must be an object.', {
      code: RuntimeErrorCode.INVALID_REQUEST,
      operation: 'respondToToolCall',
    });
  }
  if (typeof value.success !== 'boolean') {
    throw new RuntimeAdapterError('Tool call result requires boolean success.', {
      code: RuntimeErrorCode.INVALID_REQUEST,
      operation: 'respondToToolCall',
    });
  }
  const rawItems = value.content_items;
  if (!Array.isArray(rawItems) || rawItems.length === 0 || rawItems.length > MAX_TOOL_RESULT_ITEMS) {
    throw new RuntimeAdapterError(`content_items must contain 1..${MAX_TOOL_RESULT_ITEMS} items.`, {
      code: RuntimeErrorCode.INVALID_REQUEST,
      operation: 'respondToToolCall',
    });
  }
  const contentItems = rawItems.map((item) => {
    if (!item || item.type !== 'text' || typeof item.text !== 'string') {
      throw new RuntimeAdapterError('Only bounded text tool results are supported.', {
        code: RuntimeErrorCode.INVALID_REQUEST,
        operation: 'respondToToolCall',
      });
    }
    if (!item.text || item.text.length > MAX_TOOL_RESULT_TEXT_CHARS) {
      throw new RuntimeAdapterError('Tool result text must be non-empty and bounded.', {
        code: RuntimeErrorCode.INVALID_REQUEST,
        operation: 'respondToToolCall',
      });
    }
    return { type: 'inputText', text: item.text };
  });
  return { success: value.success, contentItems };
}

export class CodexAppServerAdapter extends RuntimeAdapter {
  constructor({
    client = null,
    clientOptions = {},
    defaultModel = null,
    activityTimeoutMs = DEFAULT_ACTIVITY_TIMEOUT_MS,
    closeTimeoutMs = DEFAULT_CLOSE_TIMEOUT_MS,
    sessionIdFactory = randomUUID,
  } = {}) {
    super();
    this.client = client || new CodexAppServerClient(clientOptions);
    this.defaultModel = defaultModel;
    this.activityTimeoutMs = activityTimeoutMs;
    this.closeTimeoutMs = closeTimeoutMs;
    this.sessionIdFactory = sessionIdFactory;
    this.sessions = new Map();
    this.providerSessions = new Map();
    this.approvals = new Map();
    this.toolCalls = new Map();
    this.events = new EventEmitter();
    this.models = null;
    this.account = null;
    this._readyPromise = null;
    this._attachClient();
  }

  async getAuthStatus() {
    await this._ensureReady('getAuthStatus');
    return {
      authenticated: this.account?.account != null,
      auth_type: this.account?.account?.type || null,
      plan_type: this.account?.account?.planType || null,
      requires_auth: this.account?.requiresOpenaiAuth === true,
      provider_metadata: safeProviderMetadata(null),
    };
  }

  async listCapabilities() {
    await this._ensureReady('listCapabilities');
    return {
      capabilities: [...CODEX_CAPABILITIES],
      provider_metadata: safeProviderMetadata(null, {
        models: this.models.map((model) => ({
          id: modelId(model),
          display_name: model.displayName || model.name || modelId(model),
        })),
      }),
    };
  }

  async startSession(config = {}, contextManifest = {}) {
    await this._ensureReady('startSession');
    const requestedModel = this._validateModel(config.model || this.defaultModel, 'startSession');
    let result;
    try {
      result = await this.client.startThread(this._threadParams(config, requestedModel));
    } catch (error) {
      throw asRuntimeAdapterError(error, { operation: 'startSession', provider: 'codex' });
    }
    return this._registerSession(result, { config, contextManifest, resumed: false });
  }

  async resumeSession(providerSessionId, config = {}) {
    await this._ensureReady('resumeSession');
    const threadId = String(providerSessionId || '').trim();
    if (!threadId) {
      throw new RuntimeAdapterError('providerSessionId is required.', {
        code: RuntimeErrorCode.INVALID_REQUEST,
        operation: 'resumeSession',
      });
    }
    const existingSessionId = this.providerSessions.get(threadId);
    if (existingSessionId) {
      const existing = this.sessions.get(existingSessionId);
      if (existing && ![
        RuntimeStatus.CLOSED,
        RuntimeStatus.UNAVAILABLE,
      ].includes(existing.status)) {
        return this._sessionSnapshot(existing);
      }
      this.providerSessions.delete(threadId);
    }
    const requestedModel = this._validateModel(config.model || this.defaultModel, 'resumeSession');
    let result;
    try {
      result = await this.client.resumeThread(
        threadId,
        this._threadParams(config, requestedModel, { omitEphemeral: true }),
      );
    } catch (error) {
      throw asRuntimeAdapterError(error, { operation: 'resumeSession', provider: 'codex' });
    }
    return this._registerSession(result, {
      config,
      contextManifest: config.context_manifest || {},
      resumed: true,
    });
  }

  async startTurn(sessionId, input, params = {}) {
    const session = this._session(sessionId, 'startTurn');
    const text = normalizeRuntimeTextInput(input, 'startTurn');
    const active = Array.from(session.turns.values()).find((turn) => (
      !terminalTurnStatus(turn.status)
    ));
    if (active) {
      throw new RuntimeAdapterError(`Session already has an active turn: ${active.id}`, {
        code: RuntimeErrorCode.TURN_NOT_ACTIVE,
        operation: 'startTurn',
        details: { active_turn_id: active.id },
      });
    }

    const afterSequence = this.client.notificationSequence;
    let result;
    try {
      result = await this.client.startTurn(session.providerSessionId, text, params);
    } catch (error) {
      throw asRuntimeAdapterError(error, { operation: 'startTurn', provider: 'codex' });
    }
    const turnId = result?.turn?.id;
    if (!turnId) {
      throw new RuntimeAdapterError('Codex turn/start response did not include turn.id.', {
        code: RuntimeErrorCode.PROTOCOL_ERROR,
        operation: 'startTurn',
        providerMetadata: safeProviderMetadata('turn/start'),
      });
    }
    const existing = session.turns.get(turnId) || {};
    if (terminalTurnStatus(existing.status)) {
      // App Server may legally emit turn/completed before the turn/start JSON-RPC
      // response. Never resurrect that terminal turn when the response arrives.
      return this._turnSnapshot(session, turnId);
    }
    session.turns.set(turnId, {
      ...existing,
      id: turnId,
      status: RuntimeStatus.RUNNING,
      activityAfterSequence: afterSequence,
      activitySequence: existing.activitySequence || null,
    });
    session.status = RuntimeStatus.ACTIVE;
    this._addEvent(session, {
      turnId,
      kind: RuntimeEventKind.TURN_STATUS,
      status: RuntimeStatus.RUNNING,
      data: {},
      providerMetadata: safeProviderMetadata('turn/start'),
    });
    return this._turnSnapshot(session, turnId);
  }

  async steerTurn(sessionId, turnId, input, { activityTimeoutMs = null } = {}) {
    const session = this._session(sessionId, 'steerTurn');
    const turn = this._turn(session, turnId, 'steerTurn');
    const text = normalizeRuntimeTextInput(input, 'steerTurn');
    if (terminalTurnStatus(turn.status)) {
      throw new RuntimeAdapterError(`Turn is no longer active: ${turnId}`, {
        code: RuntimeErrorCode.TURN_NOT_ACTIVE,
        operation: 'steerTurn',
      });
    }

    await this._waitForTurnActivity(session, turn, {
      timeoutMs: this._positiveTimeout(
        activityTimeoutMs,
        this.activityTimeoutMs,
        'steerTurn',
      ),
    });
    if (terminalTurnStatus(turn.status)) {
      throw new RuntimeAdapterError(`Turn completed before it could be steered: ${turnId}`, {
        code: RuntimeErrorCode.TURN_NOT_ACTIVE,
        operation: 'steerTurn',
      });
    }
    try {
      await this.client.steerTurn(session.providerSessionId, turnId, text);
    } catch (error) {
      throw asRuntimeAdapterError(error, { operation: 'steerTurn', provider: 'codex' });
    }
    this._addEvent(session, {
      turnId,
      kind: RuntimeEventKind.ACTIVITY,
      status: RuntimeStatus.RUNNING,
      data: { activity: 'steered' },
      providerMetadata: safeProviderMetadata('turn/steer'),
    });
    return this._turnSnapshot(session, turnId);
  }

  async interruptTurn(sessionId, turnId) {
    const session = this._session(sessionId, 'interruptTurn');
    const turn = this._turn(session, turnId, 'interruptTurn');
    if (terminalTurnStatus(turn.status)) return this._turnSnapshot(session, turnId);
    try {
      await this.client.interruptTurn(session.providerSessionId, turnId);
    } catch (error) {
      throw asRuntimeAdapterError(error, { operation: 'interruptTurn', provider: 'codex' });
    }
    return this._turnSnapshot(session, turnId);
  }

  async respondToApproval(requestId, decision) {
    const approval = this.approvals.get(String(requestId));
    if (!approval) {
      throw new RuntimeAdapterError(`Approval request not found: ${requestId}`, {
        code: RuntimeErrorCode.APPROVAL_NOT_FOUND,
        operation: 'respondToApproval',
      });
    }
    const normalized = String(decision || '').toLowerCase();
    const providerDecision = {
      approved: 'accept',
      approve: 'accept',
      approve_once: 'accept',
      denied: 'decline',
      deny: 'decline',
      decline: 'decline',
      cancelled: 'cancel',
      cancel: 'cancel',
    }[normalized];
    if (!providerDecision) {
      throw new RuntimeAdapterError('decision must approve, deny, or cancel the request.', {
        code: RuntimeErrorCode.INVALID_REQUEST,
        operation: 'respondToApproval',
      });
    }
    try {
      approval.respond({ decision: providerDecision });
    } catch (error) {
      throw asRuntimeAdapterError(error, {
        operation: 'respondToApproval',
        provider: 'codex',
      });
    }
    this.approvals.delete(String(requestId));
    const session = this._session(approval.sessionId, 'respondToApproval');
    session.status = RuntimeStatus.ACTIVE;
    this._addEvent(session, {
      turnId: approval.turnId,
      kind: RuntimeEventKind.APPROVAL_RESOLVED,
      status: RuntimeStatus.RUNNING,
      data: { request_id: String(requestId), decision: normalized },
      providerMetadata: safeProviderMetadata(approval.method),
    });
    return { request_id: String(requestId), decision: normalized, accepted: true };
  }

  async respondToToolCall(toolCallId, result) {
    const call = this.toolCalls.get(String(toolCallId));
    if (!call) {
      throw new RuntimeAdapterError(`Tool call not found: ${toolCallId}`, {
        code: RuntimeErrorCode.TOOL_CALL_NOT_FOUND,
        operation: 'respondToToolCall',
      });
    }
    const providerResult = normalizeToolCallResult(result);
    try {
      call.respond(providerResult);
    } catch (error) {
      throw asRuntimeAdapterError(error, {
        operation: 'respondToToolCall',
        provider: 'codex',
      });
    }
    this.toolCalls.delete(String(toolCallId));
    const session = this._session(call.sessionId, 'respondToToolCall');
    this._addEvent(session, {
      turnId: call.turnId,
      kind: RuntimeEventKind.TOOL_RESULT,
      status: RuntimeStatus.RUNNING,
      data: {
        tool_call_id: String(toolCallId),
        tool_name: call.toolName,
        success: providerResult.success,
      },
      providerMetadata: safeProviderMetadata(call.method, {
        item_id: call.itemId,
      }),
    });
    return {
      tool_call_id: String(toolCallId),
      success: providerResult.success,
      accepted: true,
    };
  }

  readEvents(sessionId, { afterSequence = 0 } = {}) {
    const session = this._session(sessionId, 'readEvents', { allowClosed: true });
    const after = Number(afterSequence) || 0;
    return {
      session_id: session.id,
      status: session.status,
      events: session.events.filter((event) => event.sequence > after),
      next_sequence: session.sequence,
    };
  }

  async *streamEvents(sessionId, { afterSequence = 0, signal = null } = {}) {
    let cursor = Number(afterSequence) || 0;
    while (!signal?.aborted) {
      const snapshot = this.readEvents(sessionId, { afterSequence: cursor });
      if (snapshot.events.length) {
        for (const event of snapshot.events) {
          cursor = event.sequence;
          yield event;
        }
        continue;
      }
      if (snapshot.status === RuntimeStatus.CLOSED) return;
      const event = await this._nextEvent(sessionId, cursor, signal);
      if (!event) return;
      cursor = event.sequence;
      yield event;
    }
  }

  async closeSession(sessionId) {
    const session = this._session(sessionId, 'closeSession', { allowClosed: true });
    if (session.status === RuntimeStatus.CLOSED) return this._sessionSnapshot(session);

    const activeTurnIds = Array.from(session.turns.values())
      .filter((turn) => !terminalTurnStatus(turn.status))
      .map((turn) => turn.id);
    const afterSequence = this.client.notificationSequence;
    this._failClosedApprovals(session);
    this._failClosedToolCalls(session);

    if (this.client.isReady) {
      for (const turnId of activeTurnIds) {
        const turn = session.turns.get(turnId);
        if (terminalTurnStatus(turn?.status)) continue;
        try {
          await this.client.interruptTurn(session.providerSessionId, turnId);
        } catch {
          if (!terminalTurnStatus(turn?.status)) {
            // A fail-closed approval response can complete the turn while the
            // interrupt response races ahead of turn/completed. Accept the
            // provider error only if the terminal notification follows.
            await this._waitForTurnTerminal(session, turnId, {
              afterSequence,
              timeoutMs: this.closeTimeoutMs,
            });
          }
        }
      }
      for (const turnId of activeTurnIds) {
        const turn = session.turns.get(turnId);
        if (terminalTurnStatus(turn?.status)) continue;
        await this._waitForTurnTerminal(session, turnId, {
          afterSequence,
          timeoutMs: this.closeTimeoutMs,
        });
      }
    } else {
      for (const turnId of activeTurnIds) {
        const turn = session.turns.get(turnId);
        if (!turn || terminalTurnStatus(turn.status)) continue;
        turn.status = RuntimeStatus.INTERRUPTED;
        this._addEvent(session, {
          turnId,
          kind: RuntimeEventKind.TURN_STATUS,
          status: RuntimeStatus.INTERRUPTED,
          data: { reason: 'runtime_unavailable_during_close' },
          providerMetadata: safeProviderMetadata(null),
        });
      }
    }

    session.status = RuntimeStatus.CLOSED;
    this.providerSessions.delete(session.providerSessionId);
    this._addEvent(session, {
      kind: RuntimeEventKind.SESSION_STATUS,
      status: RuntimeStatus.CLOSED,
      data: {
        active_turn_policy: 'interrupt_and_wait',
        approvals_policy: 'fail_closed',
      },
      providerMetadata: safeProviderMetadata(null),
    });
    return this._sessionSnapshot(session);
  }

  async stop() {
    await this.client.stop();
  }

  async _ensureReady(operation) {
    if (!this._readyPromise) {
      this._readyPromise = (async () => {
        try {
          await this.client.start();
          const [account, models] = await Promise.all([
            this.client.readAccount(),
            this.client.listModels({ limit: 100 }),
          ]);
          this.account = account;
          this.models = Array.isArray(models?.data) ? models.data : [];
          if (account?.requiresOpenaiAuth === true && !account?.account) {
            throw new RuntimeAdapterError('Codex App Server requires authentication.', {
              code: RuntimeErrorCode.AUTHENTICATION_REQUIRED,
              operation,
              providerMetadata: safeProviderMetadata('account/read'),
            });
          }
          if (this.models.length === 0) {
            throw new RuntimeAdapterError('Codex App Server returned no available models.', {
              code: RuntimeErrorCode.RUNTIME_UNAVAILABLE,
              operation,
              providerMetadata: safeProviderMetadata('model/list'),
            });
          }
          if (this.defaultModel) this._validateModel(this.defaultModel, operation);
        } catch (error) {
          this._readyPromise = null;
          throw asRuntimeAdapterError(error, { operation, provider: 'codex' });
        }
      })();
    }
    await this._readyPromise;
  }

  _validateModel(requestedModel, operation) {
    if (!requestedModel) return null;
    const requested = String(requestedModel);
    const available = this.models.map(modelId).filter(Boolean);
    if (!available.includes(requested)) {
      throw new RuntimeAdapterError(
        `Requested model is unavailable in this Codex App Server: ${requested}`,
        {
          code: RuntimeErrorCode.MODEL_UNAVAILABLE,
          operation,
          details: {
            requested_model: requested,
            available_models: available,
            hint: 'Update the local Codex CLI or choose a model returned by model/list.',
          },
          providerMetadata: safeProviderMetadata('model/list'),
        },
      );
    }
    return requested;
  }

  _positiveTimeout(value, fallback, operation) {
    const resolved = value == null ? Number(fallback) : Number(value);
    if (!Number.isFinite(resolved) || resolved <= 0) {
      throw new RuntimeAdapterError('activity timeout must be a finite positive number.', {
        code: RuntimeErrorCode.INVALID_REQUEST,
        operation,
        details: { activity_timeout_ms: value },
      });
    }
    return resolved;
  }

  _threadParams(config, requestedModel, { omitEphemeral = false } = {}) {
    return {
      ...(config.cwd ? { cwd: config.cwd } : {}),
      ...(config.approval_policy ? { approvalPolicy: config.approval_policy } : {}),
      ...(config.approvals_reviewer ? { approvalsReviewer: config.approvals_reviewer } : {}),
      ...(config.sandbox ? { sandbox: config.sandbox } : {}),
      ...(config.personality ? { personality: config.personality } : {}),
      ...(config.service_name ? { serviceName: config.service_name } : {}),
      ...(config.dynamic_tools
        ? { dynamicTools: normalizeDynamicTools(config.dynamic_tools, 'startSession') }
        : {}),
      ...(!omitEphemeral && config.ephemeral != null
        ? { ephemeral: config.ephemeral === true }
        : {}),
      ...(requestedModel ? { model: requestedModel } : {}),
    };
  }

  _registerSession(result, { config, contextManifest, resumed }) {
    const providerSessionId = result?.thread?.id;
    if (!providerSessionId) {
      throw new RuntimeAdapterError('Codex thread response did not include thread.id.', {
        code: RuntimeErrorCode.PROTOCOL_ERROR,
        operation: resumed ? 'resumeSession' : 'startSession',
        providerMetadata: safeProviderMetadata(resumed ? 'thread/resume' : 'thread/start'),
      });
    }
    const session = {
      id: this.sessionIdFactory(),
      providerSessionId,
      status: RuntimeStatus.IDLE,
      sequence: 0,
      events: [],
      turns: new Map(),
      config: { ...config },
      contextManifest: contextManifest && typeof contextManifest === 'object'
        ? contextManifest
        : {},
      model: result.model || config.model || this.defaultModel || null,
    };
    this.sessions.set(session.id, session);
    this.providerSessions.set(providerSessionId, session.id);
    this._addEvent(session, {
      kind: RuntimeEventKind.SESSION_STATUS,
      status: RuntimeStatus.IDLE,
      data: { resumed },
      providerMetadata: safeProviderMetadata(resumed ? 'thread/resume' : 'thread/start'),
    });
    return this._sessionSnapshot(session);
  }

  _session(sessionId, operation, { allowClosed = false } = {}) {
    const session = this.sessions.get(String(sessionId));
    if (!session || (!allowClosed && session.status === RuntimeStatus.CLOSED)) {
      throw new RuntimeAdapterError(`Runtime session not found: ${sessionId}`, {
        code: RuntimeErrorCode.SESSION_NOT_FOUND,
        operation,
      });
    }
    return session;
  }

  _turn(session, turnId, operation) {
    const turn = session.turns.get(String(turnId));
    if (!turn) {
      throw new RuntimeAdapterError(`Runtime turn not found: ${turnId}`, {
        code: RuntimeErrorCode.TURN_NOT_FOUND,
        operation,
      });
    }
    return turn;
  }

  _sessionSnapshot(session) {
    return {
      session_id: session.id,
      status: session.status,
      model: session.model,
      provider_metadata: safeProviderMetadata(null, {
        provider_session_id: session.providerSessionId,
      }),
    };
  }

  _turnSnapshot(session, turnId) {
    const turn = this._turn(session, turnId, 'turnSnapshot');
    return {
      session_id: session.id,
      turn_id: turn.id,
      status: turn.status,
      activity_observed: Number.isInteger(turn.activitySequence),
      provider_metadata: safeProviderMetadata(null, {
        provider_session_id: session.providerSessionId,
      }),
    };
  }

  _addEvent(session, {
    turnId = null,
    kind,
    status = null,
    data = {},
    providerMetadata = null,
  }) {
    const event = createRuntimeEvent({
      sequence: ++session.sequence,
      sessionId: session.id,
      turnId,
      kind,
      status,
      data,
      providerMetadata,
    });
    session.events.push(event);
    if (session.events.length > MAX_EVENT_HISTORY) session.events.shift();
    this.events.emit('runtimeEvent', event);
    return event;
  }

  _attachClient() {
    this.client.on('notification', ({ sequence, message }) => {
      this._translateNotification(sequence, message);
    });
    this.client.on('serverRequest', (request) => this._handleServerRequest(request));
    this.client.on('stopped', (error) => {
      this._readyPromise = null;
      this.account = null;
      this.models = null;
      this.providerSessions.clear();
      for (const [requestId, approval] of this.approvals) {
        this.approvals.delete(requestId);
        const session = this.sessions.get(approval.sessionId);
        if (!session || session.status === RuntimeStatus.CLOSED) continue;
        this._addEvent(session, {
          turnId: approval.turnId,
          kind: RuntimeEventKind.APPROVAL_RESOLVED,
          status: RuntimeStatus.UNAVAILABLE,
          data: {
            request_id: requestId,
            decision: 'unanswered',
            reason: 'runtime_stopped',
            fail_closed: true,
          },
          providerMetadata: safeProviderMetadata(approval.method),
        });
      }
      for (const [toolCallId, call] of this.toolCalls) {
        this.toolCalls.delete(toolCallId);
        const session = this.sessions.get(call.sessionId);
        if (!session || session.status === RuntimeStatus.CLOSED) continue;
        this._addEvent(session, {
          turnId: call.turnId,
          kind: RuntimeEventKind.TOOL_RESULT,
          status: RuntimeStatus.UNAVAILABLE,
          data: {
            tool_call_id: toolCallId,
            tool_name: call.toolName,
            success: false,
            reason: 'runtime_stopped',
            fail_closed: true,
          },
          providerMetadata: safeProviderMetadata(call.method, {
            item_id: call.itemId,
          }),
        });
      }
      for (const session of this.sessions.values()) {
        if ([RuntimeStatus.CLOSED, RuntimeStatus.UNAVAILABLE].includes(session.status)) continue;
        session.status = RuntimeStatus.UNAVAILABLE;
        this._addEvent(session, {
          kind: RuntimeEventKind.ERROR,
          status: RuntimeStatus.UNAVAILABLE,
          data: { code: RuntimeErrorCode.RUNTIME_UNAVAILABLE, message: error.message },
          providerMetadata: safeProviderMetadata(null),
        });
      }
    });
  }

  _translateNotification(providerSequence, message) {
    const method = String(message?.method || '');
    const params = message?.params || {};
    const threadId = providerThreadId(params);
    const sessionId = threadId ? this.providerSessions.get(threadId) : null;
    const session = sessionId ? this.sessions.get(sessionId) : null;
    if (!session) return;
    const turnId = providerTurnId(params);
    let turn = turnId ? session.turns.get(turnId) : null;

    if (method === 'turn/started' && turnId) {
      if (terminalTurnStatus(turn?.status)) return;
      turn = turn || { id: turnId, activityAfterSequence: providerSequence, activitySequence: null };
      turn.status = RuntimeStatus.RUNNING;
      session.turns.set(turnId, turn);
      session.status = RuntimeStatus.ACTIVE;
      this._addEvent(session, {
        turnId,
        kind: RuntimeEventKind.TURN_STATUS,
        status: RuntimeStatus.RUNNING,
        data: {},
        providerMetadata: safeProviderMetadata(method),
      });
      return;
    }

    if (isTurnActivity(method) && turnId) {
      turn = turn || { id: turnId, status: RuntimeStatus.RUNNING, activityAfterSequence: 0 };
      turn.activitySequence = providerSequence;
      session.turns.set(turnId, turn);
      this.events.emit('turnActivity', { sessionId: session.id, turnId, providerSequence });
    }

    if (method === 'turn/completed' && turnId) {
      turn = turn || { id: turnId };
      turn.status = normalizeCompletedStatus(params.turn?.status);
      session.turns.set(turnId, turn);
      session.status = RuntimeStatus.IDLE;
      this._addEvent(session, {
        turnId,
        kind: RuntimeEventKind.TURN_STATUS,
        status: turn.status,
        data: {},
        providerMetadata: safeProviderMetadata(method, {
          provider_status: params.turn?.status || null,
        }),
      });
      this.events.emit('turnTerminal', { sessionId: session.id, turnId });
      return;
    }

    if (method === 'item/agentMessage/delta') {
      this._addEvent(session, {
        turnId,
        kind: RuntimeEventKind.MESSAGE_DELTA,
        status: RuntimeStatus.RUNNING,
        data: { text: String(params.delta || '') },
        providerMetadata: safeProviderMetadata(method, { item_id: params.itemId || null }),
      });
      return;
    }

    if (method === 'error') {
      this._addEvent(session, {
        turnId,
        kind: RuntimeEventKind.ERROR,
        status: RuntimeStatus.FAILED,
        data: {
          code: RuntimeErrorCode.PROVIDER_ERROR,
          message: String(params.error?.message || 'Codex runtime error'),
          retryable: params.willRetry === true,
        },
        providerMetadata: safeProviderMetadata(method),
      });
      return;
    }

    const kind = method === 'warning'
      ? RuntimeEventKind.WARNING
      : (method.includes('token') || method.includes('rateLimit')
          ? RuntimeEventKind.USAGE
          : RuntimeEventKind.ACTIVITY);
    this._addEvent(session, {
      turnId,
      kind,
      status: turn?.status || session.status,
      data: kind === RuntimeEventKind.WARNING
        ? { message: String(params.message || 'Codex warning') }
        : { activity: 'provider_event' },
      providerMetadata: safeProviderMetadata(method),
    });
  }

  _handleServerRequest(request) {
    if (request.method === 'item/tool/call') {
      this._handleDynamicToolCall(request);
      return;
    }
    if (!String(request.method).endsWith('/requestApproval')) {
      request.respondError({
        code: -32_601,
        message: `Unsupported Codex server request: ${request.method}`,
      });
      return;
    }
    const threadId = providerThreadId(request.params);
    const sessionId = threadId ? this.providerSessions.get(threadId) : null;
    const session = sessionId ? this.sessions.get(sessionId) : null;
    if (!session) {
      request.respond({ decision: 'decline' });
      return;
    }
    const requestId = String(request.id);
    const turnId = providerTurnId(request.params);
    this.approvals.set(requestId, {
      requestId,
      sessionId: session.id,
      turnId,
      method: request.method,
      respond: request.respond,
    });
    session.status = RuntimeStatus.WAITING_APPROVAL;
    this._addEvent(session, {
      turnId,
      kind: RuntimeEventKind.APPROVAL_REQUEST,
      status: RuntimeStatus.WAITING_APPROVAL,
      data: {
        request_id: requestId,
        action: String(request.params?.command || request.params?.reason || 'Runtime action'),
        cwd: request.params?.cwd || null,
      },
      providerMetadata: safeProviderMetadata(request.method, {
        item_id: request.params?.itemId || null,
      }),
    });
  }

  _handleDynamicToolCall(request) {
    const threadId = providerThreadId(request.params);
    const sessionId = threadId ? this.providerSessions.get(threadId) : null;
    const session = sessionId ? this.sessions.get(sessionId) : null;
    const toolCallId = String(request.params?.callId || '').trim();
    const toolName = String(request.params?.tool || '').trim();
    const turnId = providerTurnId(request.params);
    const allowedTools = new Set(
      Array.isArray(session?.config?.dynamic_tools)
        ? session.config.dynamic_tools.map((tool) => String(tool?.name || ''))
        : [],
    );
    if (!session || !toolCallId || !toolName || !allowedTools.has(toolName)) {
      request.respond({
        success: false,
        contentItems: [{ type: 'inputText', text: 'Tool call rejected by the product host.' }],
      });
      return;
    }
    if (this.toolCalls.has(toolCallId)) {
      request.respond({
        success: false,
        contentItems: [{ type: 'inputText', text: 'Duplicate tool call id.' }],
      });
      return;
    }
    this.toolCalls.set(toolCallId, {
      toolCallId,
      sessionId: session.id,
      turnId,
      toolName,
      itemId: request.params?.itemId || null,
      method: request.method,
      respond: request.respond,
    });
    this._addEvent(session, {
      turnId,
      kind: RuntimeEventKind.TOOL_CALL,
      status: RuntimeStatus.RUNNING,
      data: {
        tool_call_id: toolCallId,
        tool_name: toolName,
        arguments: request.params?.arguments && typeof request.params.arguments === 'object'
          ? request.params.arguments
          : {},
      },
      providerMetadata: safeProviderMetadata(request.method, {
        item_id: request.params?.itemId || null,
      }),
    });
  }

  _failClosedApprovals(session) {
    for (const [requestId, approval] of this.approvals) {
      if (approval.sessionId !== session.id) continue;
      this.approvals.delete(requestId);
      let providerResponseSent = false;
      try {
        approval.respond({ decision: 'decline' });
        providerResponseSent = true;
      } catch {
        // If the client is already stopped there is no live provider request to
        // release. The local callback is still discarded so it cannot be used
        // after the session closes.
      }
      this._addEvent(session, {
        turnId: approval.turnId,
        kind: RuntimeEventKind.APPROVAL_RESOLVED,
        status: RuntimeStatus.RUNNING,
        data: {
          request_id: requestId,
          decision: 'denied',
          reason: 'session_closed',
          fail_closed: true,
          provider_response_sent: providerResponseSent,
        },
        providerMetadata: safeProviderMetadata(approval.method),
      });
    }
  }

  _failClosedToolCalls(session) {
    for (const [toolCallId, call] of this.toolCalls) {
      if (call.sessionId !== session.id) continue;
      this.toolCalls.delete(toolCallId);
      let providerResponseSent = false;
      try {
        call.respond({
          success: false,
          contentItems: [{ type: 'inputText', text: 'The product session was closed.' }],
        });
        providerResponseSent = true;
      } catch {
        // The provider may already have completed or stopped the request.
      }
      this._addEvent(session, {
        turnId: call.turnId,
        kind: RuntimeEventKind.TOOL_RESULT,
        status: RuntimeStatus.INTERRUPTED,
        data: {
          tool_call_id: toolCallId,
          tool_name: call.toolName,
          success: false,
          reason: 'session_closed',
          fail_closed: true,
          provider_response_sent: providerResponseSent,
        },
        providerMetadata: safeProviderMetadata(call.method, {
          item_id: call.itemId,
        }),
      });
    }
  }

  async _waitForTurnTerminal(session, turnId, { afterSequence, timeoutMs }) {
    try {
      await this.client.waitForNotification(
        'turn/completed',
        (message) => message.params?.threadId === session.providerSessionId &&
          message.params?.turn?.id === turnId,
        { afterSequence, timeoutMs },
      );
    } catch (error) {
      throw asRuntimeAdapterError(error, {
        operation: 'closeSession.waitForTurnTerminal',
        provider: 'codex',
      });
    }
  }

  _waitForTurnActivity(session, turn, { timeoutMs }) {
    if (Number.isInteger(turn.activitySequence) &&
        turn.activitySequence > (turn.activityAfterSequence || 0)) {
      return Promise.resolve();
    }
    return new Promise((resolve, reject) => {
      const cleanup = () => {
        clearTimeout(timer);
        this.events.off('turnActivity', onActivity);
        this.events.off('turnTerminal', onTerminal);
      };
      const onActivity = (event) => {
        if (event.sessionId !== session.id || event.turnId !== turn.id) return;
        if (event.providerSequence <= (turn.activityAfterSequence || 0)) return;
        cleanup();
        resolve();
      };
      const onTerminal = (event) => {
        if (event.sessionId !== session.id || event.turnId !== turn.id) return;
        cleanup();
        reject(new RuntimeAdapterError(
          `Turn completed before activity made steering safe: ${turn.id}`,
          { code: RuntimeErrorCode.TURN_NOT_ACTIVE, operation: 'steerTurn' },
        ));
      };
      const timer = setTimeout(() => {
        cleanup();
        reject(new RuntimeAdapterError(
          `Timed out waiting for turn activity before steering: ${turn.id}`,
          {
            code: RuntimeErrorCode.TIMEOUT,
            retryable: true,
            operation: 'steerTurn',
            details: { activity_timeout_ms: timeoutMs },
          },
        ));
      }, timeoutMs);
      timer.unref?.();
      this.events.on('turnActivity', onActivity);
      this.events.on('turnTerminal', onTerminal);
      // Re-check after subscribing so an activity notification arriving between
      // the optimistic check above and listener installation cannot be lost.
      if (Number.isInteger(turn.activitySequence) &&
          turn.activitySequence > (turn.activityAfterSequence || 0)) {
        cleanup();
        resolve();
      } else if (terminalTurnStatus(turn.status)) {
        onTerminal({ sessionId: session.id, turnId: turn.id });
      }
    });
  }

  _nextEvent(sessionId, afterSequence, signal) {
    return new Promise((resolve) => {
      const cleanup = () => {
        this.events.off('runtimeEvent', onEvent);
        signal?.removeEventListener?.('abort', onAbort);
      };
      const onEvent = (event) => {
        if (event.session_id !== sessionId || event.sequence <= afterSequence) return;
        cleanup();
        resolve(event);
      };
      const onAbort = () => {
        cleanup();
        resolve(null);
      };
      this.events.on('runtimeEvent', onEvent);
      signal?.addEventListener?.('abort', onAbort, { once: true });
      if (signal?.aborted) onAbort();
    });
  }
}
