// Owns one borrowed ordinary Gateway session, never the shared Gateway process.
// The caller supplies a trusted, bounded JSON transport. No network, provider,
// model, command, authentication, discovery, or process-stop surface lives here.
const PREFIX = '/experimental/v1/runtime';
const TOOL = 'manage_long_task_queue';
const TERMINAL = new Set(['completed', 'failed', 'interrupted']);
const KINDS = new Set(['session_status', 'turn_status', 'activity', 'message_delta',
  'message', 'tool_call', 'tool_result', 'approval_request', 'approval_resolved',
  'usage', 'warning', 'error']);
const id = value => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9_-]{0,255}$/.test(value);
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value)
  && [Object.prototype, null].includes(Object.getPrototypeOf(value));
const fail = code => { throw Object.assign(new Error(code), { code }); };
const need = (value, code = 'conversation_request_rejected') => { if (!value) fail(code); };
const fields = (value, allowed) => object(value) && Object.keys(value).every(key => allowed.includes(key));
function json(value, limit = 256 * 1024) {
  let count = 0;
  const copy = (v, depth) => {
    need(depth <= 32 && ++count <= 20000);
    if (v === null || typeof v === 'string' || typeof v === 'boolean') return v;
    if (typeof v === 'number') { need(Number.isFinite(v)); return v; }
    if (Array.isArray(v)) return Object.freeze(v.map(child => copy(child, depth + 1)));
    need(object(v));
    const result = Object.fromEntries(Object.keys(v).sort().map(key => [key, copy(v[key], depth + 1)]));
    return Object.freeze(result);
  };
  const result = copy(value, 0);
  need(Buffer.byteLength(JSON.stringify(result)) <= limit);
  return result;
}
const equal = (a, b) => JSON.stringify(json(a)) === JSON.stringify(json(b));

export class WorkbenchProductConversationGuardian {
  #conversationId; #tool; #transport; #timeout;
  #session = null; #sessionStart = null; #sessionAttempted = false;
  #turnStart = null; #turns = new Map(); #tools = new Map();
  #events = new Map(); #sequence = 0; #readTail = Promise.resolve();
  #pending = new Set(); #closing = false; #unknown = null;
  #closePromise = null; #closeSnapshot = null; #deleteSent = false; #closed = false;

  constructor({ conversationId, dynamicTool, transport, closeTimeoutMs = 30000 }) {
    need(id(conversationId) && typeof transport === 'function'
      && Number.isSafeInteger(closeTimeoutMs) && closeTimeoutMs >= 1 && closeTimeoutMs <= 180000);
    const tool = json(dynamicTool, 66 * 1024);
    need(fields(tool, ['name', 'description', 'input_schema', 'defer_loading'])
      && tool.name === TOOL && typeof tool.description === 'string'
      && tool.description.trim().length > 0 && tool.description.length <= 1000
      && object(tool.input_schema) && tool.input_schema.type === 'object'
      && tool.input_schema.additionalProperties === false
      && (tool.defer_loading === undefined || tool.defer_loading === false));
    this.#conversationId = conversationId; this.#tool = tool;
    this.#transport = transport; this.#timeout = closeTimeoutMs;
  }

  #open() {
    need(!this.#closing && !this.#unknown, this.#unknown || 'conversation_closing');
  }
  #own(sessionId) {
    need(id(sessionId) && sessionId === this.#session?.id, 'conversation_foreign_session');
  }
  #turn(turnId) {
    need(id(turnId) && this.#turns.has(turnId), 'conversation_foreign_turn');
    return this.#turns.get(turnId);
  }
  #poison(reason) { this.#unknown ??= reason; }
  #track(promise) {
    this.#pending.add(promise);
    void promise.then(() => this.#pending.delete(promise), () => this.#pending.delete(promise));
    return promise;
  }
  #request(method, path, body) {
    const request = Object.freeze({ method, path, ...(body === undefined ? {} : { body: json(body) }) });
    // Never expose remote errors, account fields, or raw response diagnostics.
    return Promise.resolve().then(() => this.#transport(request));
  }
  #metadata(value) {
    return object(value) && value.provider === 'codex'
      && value.provider_session_id === this.#session?.providerId;
  }
  #terminal(value, turnId) {
    return object(value) && value.provider_session_id === this.#session?.providerId
      && value.turn_id === turnId && value.provider_terminal_confirmed === true
      && TERMINAL.has(value.provider_terminal_status) && value.source === 'turn/completed'
      && Number.isSafeInteger(value.provider_terminal_sequence) && value.provider_terminal_sequence > 0;
  }

  startSession(config = {}, contextManifest = {}) {
    this.#open(); need(!this.#sessionAttempted, 'conversation_single_session');
    need(fields(config, ['ephemeral', 'service_name', 'dynamic_tools'])
      && (config.ephemeral === undefined || config.ephemeral === false)
      && (config.service_name === undefined || config.service_name === 'here_i_am_workbench')
      && (config.dynamic_tools === undefined || equal(config.dynamic_tools, [this.#tool])));
    const manifest = { conversation_id: this.#conversationId, profile: 'workbench', scope: 'desktop_chat' };
    need(fields(contextManifest, Object.keys(manifest))
      && Object.entries(contextManifest).every(([key, value]) => value === manifest[key]));
    const body = { config: { ephemeral: false, service_name: 'here_i_am_workbench', dynamic_tools: [this.#tool] },
      context_manifest: manifest };
    this.#sessionAttempted = true;
    const attempt = (async () => {
      let result;
      try { result = await this.#request('POST', `${PREFIX}/sessions`, body); }
      catch { this.#poison('conversation_start_unknown'); fail(this.#unknown); }
      // Retain an exact ID returned by this create request even when the rest of
      // its response is malformed. It still needs a DELETE, but cannot certify close.
      if (id(result?.session_id)) this.#session = { id: result.session_id,
        providerId: id(result?.provider_metadata?.provider_session_id) ? result.provider_metadata.provider_session_id : null };
      if (!this.#session || !this.#session.providerId || !this.#metadata(result.provider_metadata)
        || result.status !== 'idle') {
        this.#poison('conversation_start_unknown'); fail(this.#unknown);
      }
      // Registration is complete before App sees a successful create response.
      if (this.#closing) fail('conversation_closing');
      return result;
    })();
    this.#sessionStart = this.#track(attempt);
    return attempt;
  }

  startTurn(sessionId, input, params = {}) {
    this.#open(); this.#own(sessionId);
    need(typeof input === 'string' && input.trim() && Buffer.byteLength(input) <= 128 * 1024
      && fields(params, []) && !this.#turnStart, 'conversation_turn_rejected');
    need(this.#turns.size < 64 && [...this.#turns.values()].every(turn => turn.terminal)
      && [...this.#tools.values()].every(tool => ['answered', 'retired'].includes(tool.state)),
    'conversation_turn_pending');
    const attempt = (async () => {
      let result;
      try { result = await this.#request('POST', `${PREFIX}/sessions/${encodeURIComponent(sessionId)}/turns`, { input, params: {} }); }
      catch { this.#poison('conversation_turn_start_unknown'); fail(this.#unknown); }
      if (result?.session_id !== sessionId || !id(result?.turn_id) || !this.#metadata(result.provider_metadata)
        || this.#turns.has(result.turn_id)) {
        this.#poison('conversation_turn_start_unknown'); fail(this.#unknown);
      }
      const turn = { id: result.turn_id, terminal: null };
      if (this.#terminal(result.stop_evidence, turn.id)) turn.terminal = this.#terminalIdentity(result.stop_evidence);
      this.#turns.set(turn.id, turn);
      if (this.#closing) fail('conversation_closing');
      return result;
    })();
    this.#turnStart = attempt;
    this.#track(attempt);
    void attempt.then(() => { if (this.#turnStart === attempt) this.#turnStart = null; },
      () => { if (this.#turnStart === attempt) this.#turnStart = null; });
    return attempt;
  }

  #terminalIdentity(evidence) {
    return { status: evidence.provider_terminal_status, sequence: evidence.provider_terminal_sequence };
  }

  readEvents(sessionId, { afterSequence = 0 } = {}) {
    this.#open(); this.#own(sessionId);
    need(Number.isSafeInteger(afterSequence) && afterSequence >= 0 && afterSequence <= this.#sequence);
    const turnStart = this.#turnStart;
    const attempt = this.#readTail.then(async () => {
      if (turnStart) await turnStart.catch(() => {});
      this.#open();
      let result;
      try { result = await this.#request('GET', `${PREFIX}/sessions/${encodeURIComponent(sessionId)}/events?after=${afterSequence}`); }
      catch { fail('conversation_events_unavailable'); }
      try { result = this.#registerEvents(result, afterSequence); }
      catch { this.#poison('conversation_events_rejected'); fail(this.#unknown); }
      // In-flight polls may finish after EOF. Keep identities, never release new
      // tool calls to an App which already surrendered this session.
      if (this.#closing) fail('conversation_closing');
      return result;
    });
    this.#readTail = attempt.catch(() => {});
    return this.#track(attempt);
  }

  #registerEvents(result, after) {
    need(object(result) && result.session_id === this.#session.id && Array.isArray(result.events)
      && result.events.length <= 1000 && Number.isSafeInteger(result.next_sequence)
      && result.next_sequence >= after && result.next_sequence >= this.#sequence);
    let previous = after;
    const visible = [];
    for (const event of result.events) {
      need(object(event) && event.session_id === this.#session.id && event.schema_version === 1
        && Number.isSafeInteger(event.sequence) && event.sequence > previous
        && event.sequence <= result.next_sequence && event.event_id === `${this.#session.id}:${event.sequence}`
        && KINDS.has(event.kind) && object(event.data)
        && (!event.provider_metadata || this.#metadataForEvent(event.provider_metadata)));
      previous = event.sequence;
      if (event.turn_id !== undefined) this.#turn(event.turn_id);
      const toolEvent = event.kind === 'tool_call' || event.kind === 'tool_result';
      if (toolEvent) need(event.turn_id && id(event.data.tool_call_id) && event.data.tool_name === TOOL);
      const identity = JSON.stringify([event.kind, event.turn_id ?? null,
        toolEvent ? event.data.tool_call_id : null, toolEvent ? event.data.tool_name : null]);
      if (this.#events.has(event.sequence)) {
        need(this.#events.get(event.sequence) === identity);
        // A cursor reset must never redispatch an already delivered queue call.
        if (event.kind !== 'tool_call') visible.push(event);
        continue;
      }
      need(event.sequence === this.#sequence + 1 && this.#events.size < 16384);
      if (event.kind === 'approval_request' || event.kind === 'approval_resolved') need(false);
      if (event.kind === 'tool_call') {
        need(!this.#turn(event.turn_id).terminal && !this.#tools.has(event.data.tool_call_id)
          && this.#tools.size < 512 && object(event.data.arguments));
        this.#tools.set(event.data.tool_call_id, { turnId: event.turn_id, state: 'pending' });
      } else if (event.kind === 'tool_result') {
        const tool = this.#tools.get(event.data.tool_call_id);
        need(tool && tool.turnId === event.turn_id && typeof event.data.success === 'boolean');
        const rejectedByHost = event.data.fail_closed === true && event.data.success === false
          && ['turn_terminal', 'session_closed'].includes(event.data.reason);
        need(['responding', 'answered'].includes(tool.state) || rejectedByHost);
        tool.state = rejectedByHost ? 'retired' : 'answered';
      } else if (event.kind === 'turn_status' && TERMINAL.has(event.status)) {
        need(event.turn_id && this.#terminal(event.data.stop_evidence, event.turn_id));
        const turn = this.#turn(event.turn_id), terminal = this.#terminalIdentity(event.data.stop_evidence);
        need(!turn.terminal || equal(turn.terminal, terminal));
        turn.terminal = terminal;
        for (const tool of this.#tools.values()) if (tool.turnId === turn.id) tool.state = 'retired';
      }
      this.#events.set(event.sequence, identity); this.#sequence = event.sequence;
      visible.push(event);
    }
    need(result.next_sequence === this.#sequence);
    return { ...result, events: visible };
  }

  #metadataForEvent(value) {
    // Actual adapter events commonly omit provider_session_id; the envelope
    // session_id plus the registered turn are the local ownership binding.
    return object(value) && value.provider === 'codex'
      && (value.provider_session_id === undefined || value.provider_session_id === this.#session.providerId);
  }

  respondToToolCall(toolCallId, result) {
    this.#open();
    const tool = this.#tools.get(toolCallId);
    need(id(toolCallId) && tool?.state === 'pending' && !this.#turn(tool.turnId).terminal,
      'conversation_tool_call_rejected');
    need(fields(result, ['success', 'content_items']) && typeof result.success === 'boolean'
      && Array.isArray(result.content_items) && result.content_items.length >= 1 && result.content_items.length <= 16
      && result.content_items.every(item => fields(item, ['type', 'text']) && item.type === 'text'
        && typeof item.text === 'string' && item.text.length >= 1 && item.text.length <= 65536));
    const body = json(result);
    tool.state = 'responding';
    const attempt = (async () => {
      let response;
      try { response = await this.#request('POST', `${PREFIX}/tool-calls/${encodeURIComponent(toolCallId)}`, body); }
      catch { if (tool.state === 'responding') tool.state = 'unknown'; fail('conversation_tool_reply_unknown'); }
      if (response?.tool_call_id !== toolCallId || response.accepted !== true || response.success !== body.success) {
        tool.state = 'unknown'; this.#poison('conversation_tool_reply_rejected'); fail(this.#unknown);
      }
      if (tool.state === 'responding') tool.state = 'answered';
      if (this.#closing) fail('conversation_closing');
      return response;
    })();
    return this.#track(attempt);
  }

  interruptTurn(sessionId, turnId) {
    this.#open(); this.#own(sessionId); this.#turn(turnId);
    const attempt = (async () => {
      let response;
      try { response = await this.#request('POST', `${PREFIX}/sessions/${encodeURIComponent(sessionId)}/turns/${encodeURIComponent(turnId)}/interrupt`, {}); }
      catch { fail('conversation_interrupt_unknown'); }
      if (response?.session_id !== sessionId || response?.turn_id !== turnId || !this.#metadata(response.provider_metadata)) {
        this.#poison('conversation_interrupt_rejected'); fail(this.#unknown);
      }
      if (this.#terminal(response.stop_evidence, turnId)) {
        const turn = this.#turn(turnId), terminal = this.#terminalIdentity(response.stop_evidence);
        if (turn.terminal && !equal(turn.terminal, terminal)) {
          this.#poison('conversation_terminal_mismatch'); fail(this.#unknown);
        }
        turn.terminal = terminal;
        for (const tool of this.#tools.values()) if (tool.turnId === turnId) tool.state = 'retired';
      }
      if (this.#closing) fail('conversation_closing');
      return response;
    })();
    return this.#track(attempt);
  }

  async closeSession(sessionId) {
    this.#own(sessionId);
    const result = await this.closeForHostLifecycle();
    if (result.status !== 'closed') fail(result.reason || 'conversation_close_unknown');
    return this.#closeSnapshot;
  }

  closeForHostLifecycle() {
    if (this.#closePromise) return this.#closePromise;
    this.#closing = true;
    // DELETE itself fail-closes provider callbacks before waiting for terminal.
    // Do not wait for a pending model/tool reply before starting that operation.
    const cleanup = (async () => {
      if (this.#sessionStart) await this.#sessionStart.catch(() => {});
      let response;
      if (this.#session && !this.#deleteSent) {
        this.#deleteSent = true;
        try { response = await this.#request('DELETE', `${PREFIX}/sessions/${encodeURIComponent(this.#session.id)}`); }
        catch { this.#poison('conversation_close_unknown'); }
      }
      while (this.#pending.size) await Promise.allSettled([...this.#pending]);
      if (this.#session) {
        try { this.#validateClose(response); }
        catch { this.#poison('conversation_close_receipt_rejected'); }
      } else if (this.#sessionAttempted) this.#poison('conversation_start_unknown');
      if (!this.#unknown) {
        this.#closeSnapshot = response ?? null; this.#closed = true;
        for (const tool of this.#tools.values()) tool.state = 'retired';
      }
    })().catch(() => { this.#poison('conversation_close_unknown'); });
    let timer;
    const timeout = new Promise(resolve => { timer = setTimeout(() => {
      this.#poison('conversation_close_timeout'); resolve();
    }, this.#timeout); });
    // A timed-out cleanup keeps running. A late create ID remains owned and is
    // deleted; timeout is sticky and can never retroactively certify host exit.
    this.#closePromise = Promise.race([cleanup, timeout]).then(() => {
      clearTimeout(timer);
      return Object.freeze({ status: this.#closed && !this.#unknown ? 'closed' : 'unknown',
        conversation_id: this.#conversationId, session_id: this.#session?.id ?? null,
        turn_ids: Object.freeze([...this.#turns.keys()]), reason: this.#unknown,
        shared_gateway_stopped: false });
    });
    return this.#closePromise;
  }

  #validateClose(response) {
    need(response?.session_id === this.#session.id && response.status === 'closed'
      && this.#metadata(response.provider_metadata));
    const evidence = response.stop_evidence;
    need(object(evidence) && evidence.local_binding_closed === true && Array.isArray(evidence.turns)
      && evidence.turns.length === this.#turns.size);
    if (!this.#turns.size) {
      need(evidence.provider_terminal_confirmed === false && this.#tools.size === 0 && !this.#turnStart);
      return;
    }
    need(evidence.provider_terminal_confirmed === true);
    const seen = new Set();
    for (const item of evidence.turns) {
      need(id(item?.turn_id) && !seen.has(item.turn_id) && this.#turns.has(item.turn_id)
        && this.#terminal(item, item.turn_id));
      const known = this.#turns.get(item.turn_id).terminal;
      need(!known || equal(known, this.#terminalIdentity(item)));
      seen.add(item.turn_id);
    }
  }

  snapshot() {
    return Object.freeze({ conversation_id: this.#conversationId, session_id: this.#session?.id ?? null,
      provider_session_id: this.#session?.providerId ?? null, closing: this.#closing,
      closed: this.#closed && !this.#unknown, unknown_reason: this.#unknown,
      session_start_attempted: this.#sessionAttempted, delete_sent: this.#deleteSent,
      pending_requests: this.#pending.size, last_sequence: this.#sequence,
      turn_ids: Object.freeze([...this.#turns.keys()]),
      pending_tool_call_ids: Object.freeze([...this.#tools].filter(([, value]) => !['answered', 'retired'].includes(value.state)).map(([key]) => key)),
      shared_gateway_stopped: false });
  }
}
