import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { WorkbenchProductConversationGuardian } from './workbench_product_conversation_guardian.mjs';
import { CodexAppServerAdapter } from './codex_app_server_adapter.mjs';

const P = '/experimental/v1/runtime';
const S = 'session-owned', T = 'turn-owned', PROVIDER = 'provider-owned';
const dynamicTool = Object.freeze({ name: 'manage_long_task_queue', description: 'Candidate queue',
  input_schema: { type: 'object', additionalProperties: false, properties: { action: { type: 'string' } } } });
const metadata = () => ({ provider: 'codex', provider_session_id: PROVIDER });
const session = () => ({ session_id: S, status: 'idle', model: 'existing-model', provider_metadata: metadata() });
const proof = (turnId = T, status = 'interrupted', sequence = 17) => ({ provider_session_id: PROVIDER, turn_id: turnId,
  interrupt_requested: true, interrupt_acknowledged: true, provider_terminal_confirmed: true,
  provider_terminal_status: status, provider_terminal_sequence: sequence, source: 'turn/completed', cancellation_confirmed: status === 'interrupted' });
const turn = (turnId = T) => ({ session_id: S, turn_id: turnId, status: 'running', activity_observed: false,
  stop_evidence: { provider_session_id: PROVIDER, turn_id: turnId, interrupt_requested: false,
    interrupt_acknowledged: false, provider_terminal_confirmed: false, provider_terminal_status: null,
    provider_terminal_sequence: null, source: null, cancellation_confirmed: false }, provider_metadata: metadata() });
const closed = (turnIds = []) => ({ ...session(), status: 'closed', stop_evidence: {
  local_binding_closed: true, provider_terminal_confirmed: turnIds.length > 0, turns: turnIds.map(id => proof(id)) } });
const event = (sequence, kind, data = {}, turnId = undefined, status = undefined) => ({ schema_version: 1,
  event_id: `${S}:${sequence}`, session_id: S, sequence, kind, data,
  ...(turnId ? { turn_id: turnId } : {}), ...(status ? { status } : {}), provider_metadata: { provider: 'codex' } });
const toolEvent = (sequence = 1, call = 'call-owned', turnId = T) => event(sequence, 'tool_call',
  { tool_call_id: call, tool_name: dynamicTool.name, arguments: { action: 'status' } }, turnId, 'running');
const events = list => ({ session_id: S, status: 'active', events: list, next_sequence: list.at(-1)?.sequence ?? 0 });
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
const tick = () => new Promise(resolve => setImmediate(resolve));
const rejects = (fn, code) => assert.rejects(Promise.resolve().then(fn), error => error.code === code);
function fixture(handle = () => undefined, options = {}) {
  const calls = [], ids = [];
  const guardian = new WorkbenchProductConversationGuardian({ conversationId: 'conversation-owned', dynamicTool,
    ...options, transport: async request => {
      calls.push(request);
      const answer = handle(request, { calls, ids });
      if (answer !== undefined) return answer;
      if (request.method === 'POST' && request.path === `${P}/sessions`) return session();
      if (request.path === `${P}/sessions/${S}/turns`) { const next = ids.length ? `turn-${ids.length + 1}` : T; ids.push(next); return turn(next); }
      if (request.method === 'DELETE') return closed(ids);
      if (request.path.endsWith('/interrupt')) return turn(request.path.split('/').at(-2));
      if (request.path.includes('/tool-calls/')) return { tool_call_id: request.path.split('/').at(-1), accepted: true, success: request.body.success };
      throw new Error('Unexpected fake path');
    } });
  return { guardian, calls, ids };
}
async function started(f = fixture()) { await f.guardian.startSession(); await f.guardian.startTurn(S, 'public request'); return f; }

test('host supplies the exact ordinary profile and one dynamic tool; no endpoint/model/auth is accepted', async () => {
  const { guardian, calls } = fixture();
  await guardian.startSession({ ephemeral: false, service_name: 'here_i_am_workbench', dynamic_tools: [structuredClone(dynamicTool)] },
    { conversation_id: 'conversation-owned', profile: 'workbench', scope: 'desktop_chat' });
  assert.deepEqual(calls[0], { method: 'POST', path: `${P}/sessions`, body: { config: {
    ephemeral: false, service_name: 'here_i_am_workbench', dynamic_tools: [dynamicTool] },
  context_manifest: { conversation_id: 'conversation-owned', profile: 'workbench', scope: 'desktop_chat' } } });
  assert.equal(Object.isFrozen(calls[0].body.config), true);
  assert.equal(guardian.snapshot().provider_session_id, PROVIDER);
  await rejects(() => guardian.startSession(), 'conversation_single_session');
  assert.equal((await guardian.closeForHostLifecycle()).status, 'closed');
});

test('different tool, extra tool, zero tools, profile/config/manifest injection all reject before transport', async () => {
  for (const config of [{ dynamic_tools: [] }, { dynamic_tools: [dynamicTool, dynamicTool] },
    { dynamic_tools: [{ ...dynamicTool, name: 'exec' }] }, { dynamic_tools: [{ ...dynamicTool, description: 'modified' }] },
    { model: 'other' }, { runtime_profile: 'workbench_text_only_v1' }, { cwd: 'private' }, { auth: 'secret' },
    { endpoint: 'https://example.invalid' }, { ephemeral: true }, { service_name: 'other' }]) {
    const { guardian, calls } = fixture();
    await rejects(() => guardian.startSession(config), 'conversation_request_rejected'); assert.equal(calls.length, 0);
  }
  for (const manifest of [{ conversation_id: 'foreign' }, { profile: 'text' }, { scope: 'other' }, { token: 'secret' }]) {
    const { guardian, calls } = fixture();
    await rejects(() => guardian.startSession({}, manifest), 'conversation_request_rejected'); assert.equal(calls.length, 0);
  }
  assert.throws(() => fixture(undefined, { dynamicTool: { ...dynamicTool, name: 'exec' } }));
});

test('foreign session/turn/tool IDs never reach transport', async () => {
  const { guardian, calls } = await started(); const before = calls.length;
  for (const fn of [() => guardian.startTurn('foreign', 'x'), () => guardian.readEvents('foreign'),
    () => guardian.interruptTurn('foreign', T), () => guardian.closeSession('foreign')]) {
    await rejects(fn, 'conversation_foreign_session');
  }
  await rejects(() => guardian.interruptTurn(S, 'foreign'), 'conversation_foreign_turn');
  await rejects(() => guardian.respondToToolCall('foreign', { success: true, content_items: [{ type: 'text', text: 'x' }] }), 'conversation_tool_call_rejected');
  assert.equal(calls.length, before); assert.equal((await guardian.closeForHostLifecycle()).status, 'closed');
});

test('EOF during session start joins it, records late ID, deletes exactly once, and never hands late result to App', async () => {
  const response = deferred(); const { guardian, calls } = fixture(r => r.path === `${P}/sessions` ? response.promise : undefined);
  const start = guardian.startSession(); const rejected = rejects(() => start, 'conversation_closing');
  await tick(); const close = guardian.closeForHostLifecycle();
  assert.strictEqual(guardian.closeForHostLifecycle(), close);
  assert.equal(calls.length, 1); response.resolve(session());
  await rejected; assert.equal((await close).status, 'closed');
  assert.deepEqual(calls.map(r => [r.method, r.path]), [['POST', `${P}/sessions`], ['DELETE', `${P}/sessions/${S}`]]);
});

test('lost session start remains sticky unknown; no guessed ID or global enumeration', async () => {
  for (const response of [Promise.reject(new Error('private response')), { status: 'idle' }]) {
    const { guardian, calls } = fixture(r => r.path === `${P}/sessions` ? response : undefined);
    await rejects(() => guardian.startSession(), 'conversation_start_unknown');
    const close = await guardian.closeForHostLifecycle();
    assert.equal(close.status, 'unknown'); assert.equal(close.session_id, null); assert.equal(calls.length, 1);
    assert.deepEqual(await guardian.closeForHostLifecycle(), close);
  }
});

test('malformed start which contains an exact ID still gets DELETE but cannot certify closure', async () => {
  const { guardian, calls } = fixture(r => r.path === `${P}/sessions` ? { ...session(), provider_metadata: {} } : undefined);
  await rejects(() => guardian.startSession(), 'conversation_start_unknown');
  assert.equal((await guardian.closeForHostLifecycle()).status, 'unknown');
  assert.equal(calls.at(-1).path, `${P}/sessions/${S}`); assert.equal(calls.at(-1).method, 'DELETE');
});

test('close timeout retains late session cleanup and never turns sticky unknown into success', async () => {
  const response = deferred(); const { guardian, calls } = fixture(r => r.path === `${P}/sessions` ? response.promise : undefined,
    { closeTimeoutMs: 10 });
  const start = guardian.startSession(); const rejected = rejects(() => start, 'conversation_closing');
  const result = await guardian.closeForHostLifecycle(); assert.equal(result.reason, 'conversation_close_timeout');
  response.resolve(session()); await rejected; await tick();
  assert.equal(calls.filter(r => r.method === 'DELETE').length, 1);
  assert.equal(guardian.snapshot().closed, false); assert.equal((await guardian.closeForHostLifecycle()).status, 'unknown');
});

test('EOF during turn start issues DELETE before waiting and includes late exact turn in receipt validation', async () => {
  const response = deferred(); const { guardian, calls } = fixture(r => {
    if (r.path.endsWith('/turns')) return response.promise;
    if (r.method === 'DELETE') { response.resolve(turn()); return closed([T]); }
  });
  await guardian.startSession(); const start = guardian.startTurn(S, 'public');
  const rejected = rejects(() => start, 'conversation_closing'); await tick();
  const result = await guardian.closeForHostLifecycle(); await rejected;
  assert.equal(result.status, 'closed'); assert.deepEqual(result.turn_ids, [T]);
  assert.equal(calls.filter(r => r.method === 'DELETE').length, 1);
});

test('lost turn start remains unknown even if DELETE reports a terminal unknown turn', async () => {
  const { guardian } = fixture(r => {
    if (r.path.endsWith('/turns')) throw new Error('lost response');
    if (r.method === 'DELETE') return closed([T]);
  });
  await guardian.startSession(); await rejects(() => guardian.startTurn(S, 'public'), 'conversation_turn_start_unknown');
  await rejects(() => guardian.startTurn(S, 'again'), 'conversation_turn_start_unknown');
  assert.equal((await guardian.closeForHostLifecycle()).status, 'unknown'); assert.deepEqual(guardian.snapshot().turn_ids, []);
});

test('multiple queue calls within a real turn are kept; cursor reset does not replay delivered tool calls', async () => {
  const log = [toolEvent()]; const { guardian, calls } = await started(fixture(r => r.method === 'GET' ? events(log) : undefined));
  assert.equal((await guardian.readEvents(S)).events.length, 1);
  await guardian.respondToToolCall('call-owned', { success: true, content_items: [{ type: 'text', text: 'public result' }] });
  await rejects(() => guardian.respondToToolCall('call-owned', { success: true, content_items: [{ type: 'text', text: 'replay' }] }), 'conversation_tool_call_rejected');
  log.push(event(2, 'tool_result', { tool_call_id: 'call-owned', tool_name: dynamicTool.name, success: true }, T), toolEvent(3, 'call-two'));
  const polled = await guardian.readEvents(S);
  assert.deepEqual(polled.events.filter(e => e.kind === 'tool_call').map(e => e.data.tool_call_id), ['call-two']);
  assert.deepEqual(guardian.snapshot().pending_tool_call_ids, ['call-two']);
  await guardian.respondToToolCall('call-two', { success: false, content_items: [{ type: 'text', text: 'denied by original words' }] });
  assert.equal(calls.filter(r => r.path.includes('/tool-calls/')).length, 2);
  assert.equal((await guardian.closeForHostLifecycle()).status, 'closed');
});

test('new turn never clears unresolved pending tool or active turn', async () => {
  const { guardian, calls } = await started(fixture(r => r.method === 'GET' ? events([toolEvent()]) : undefined));
  await guardian.readEvents(S); await rejects(() => guardian.startTurn(S, 'another'), 'conversation_turn_pending');
  assert.deepEqual(guardian.snapshot().pending_tool_call_ids, ['call-owned']);
  assert.equal(calls.filter(r => r.path.endsWith('/turns')).length, 1);
  assert.equal((await guardian.closeForHostLifecycle()).status, 'closed');
});

test('reply transport loss does not permit retry or new turn; exact terminal close can settle its remaining ownership', async () => {
  const { guardian } = await started(fixture(r => {
    if (r.method === 'GET') return events([toolEvent()]);
    if (r.path.includes('/tool-calls/')) throw new Error('response lost');
  }));
  await guardian.readEvents(S);
  await rejects(() => guardian.respondToToolCall('call-owned', { success: true, content_items: [{ type: 'text', text: 'x' }] }), 'conversation_tool_reply_unknown');
  await rejects(() => guardian.respondToToolCall('call-owned', { success: true, content_items: [{ type: 'text', text: 'again' }] }), 'conversation_tool_call_rejected');
  await rejects(() => guardian.startTurn(S, 'again'), 'conversation_turn_pending');
  assert.equal((await guardian.closeForHostLifecycle()).status, 'closed');
});

test('close starts DELETE while tool response is pending, allowing adapter fail-closed callback to unblock it', async () => {
  const reply = deferred(); const { guardian, calls } = await started(fixture(r => {
    if (r.method === 'GET') return events([toolEvent()]);
    if (r.path.includes('/tool-calls/')) return reply.promise;
    if (r.method === 'DELETE') { reply.resolve({ tool_call_id: 'call-owned', success: true, accepted: true }); return closed([T]); }
  }));
  await guardian.readEvents(S);
  const pending = guardian.respondToToolCall('call-owned', { success: true, content_items: [{ type: 'text', text: 'public result' }] });
  const rejected = rejects(() => pending, 'conversation_closing'); await tick();
  assert.equal((await guardian.closeForHostLifecycle()).status, 'closed'); await rejected;
  assert.equal(calls.at(-1).method, 'DELETE');
});

test('an event poll already pending at EOF is joined but its late tool event is never released to App', async () => {
  const poll = deferred(); const { guardian } = await started(fixture(r => {
    if (r.method === 'GET') return poll.promise;
    if (r.method === 'DELETE') { poll.resolve(events([toolEvent()])); return closed([T]); }
  }));
  const reading = guardian.readEvents(S); const rejected = rejects(() => reading, 'conversation_closing');
  await tick(); assert.equal((await guardian.closeForHostLifecycle()).status, 'closed'); await rejected;
  assert.deepEqual(guardian.snapshot().pending_tool_call_ids, []);
});

test('a forged accepted tool response poisons ownership and never permits a resend', async () => {
  const { guardian } = await started(fixture(r => {
    if (r.method === 'GET') return events([toolEvent()]);
    if (r.path.includes('/tool-calls/')) return { accepted: true, success: true, tool_call_id: 'foreign' };
  }));
  await guardian.readEvents(S);
  await rejects(() => guardian.respondToToolCall('call-owned', { success: true, content_items: [{ type: 'text', text: 'x' }] }), 'conversation_tool_reply_rejected');
  assert.equal((await guardian.closeForHostLifecycle()).status, 'unknown');
});

test('close transport failure is sticky and does not retry DELETE against the shared service', async () => {
  const { guardian, calls } = await started(fixture(r => {
    if (r.method === 'DELETE') throw new Error('private upstream diagnostic');
  }));
  const result = await guardian.closeForHostLifecycle();
  assert.equal(result.reason, 'conversation_close_unknown');
  await rejects(() => guardian.closeSession(S), 'conversation_close_unknown');
  assert.equal(calls.filter(r => r.method === 'DELETE').length, 1);
  assert.equal(JSON.stringify(result).includes('private'), false);
});

test('events reject foreign ownership, unlisted tools, duplicate call ID, forged terminal, and missing history', async () => {
  const lists = [
    [{ ...toolEvent(), session_id: 'foreign' }], [toolEvent(1, 'call-owned', 'foreign')],
    [{ ...toolEvent(), data: { ...toolEvent().data, tool_name: 'exec' } }],
    [toolEvent(), toolEvent(2)], [toolEvent(2)],
    [event(1, 'turn_status', { stop_evidence: { ...proof(), source: 'interrupt/ack' } }, T, 'interrupted')],
  ];
  for (const list of lists) {
    const { guardian } = await started(fixture(r => r.method === 'GET' ? events(list) : undefined));
    await rejects(() => guardian.readEvents(S), 'conversation_events_rejected');
    assert.equal((await guardian.closeForHostLifecycle()).status, 'unknown');
  }
});

test('confirmed terminal retires old pending identities and permits the next turn without replay', async () => {
  const list = [toolEvent(), event(2, 'tool_result', { tool_call_id: 'call-owned', tool_name: dynamicTool.name,
    success: false, fail_closed: true, reason: 'turn_terminal', provider_response_sent: false }, T),
  event(3, 'turn_status', { stop_evidence: proof() }, T, 'interrupted')];
  const { guardian } = await started(fixture(r => r.method === 'GET' ? events(list) : undefined));
  await guardian.readEvents(S); await guardian.startTurn(S, 'next public');
  await rejects(() => guardian.respondToToolCall('call-owned', { success: true, content_items: [{ type: 'text', text: 'old' }] }), 'conversation_tool_call_rejected');
  assert.equal((await guardian.closeForHostLifecycle()).status, 'closed');
});

test('close validates exact provider/session/turn terminal evidence, never ACK/offline/local closed only', async () => {
  const corruptions = [
    r => { r.session_id = 'foreign'; }, r => { r.status = 'unavailable'; },
    r => { r.provider_metadata.provider_session_id = 'foreign'; },
    r => { delete r.stop_evidence; }, r => { r.stop_evidence.local_binding_closed = false; },
    r => { r.stop_evidence.provider_terminal_confirmed = false; },
    r => { r.stop_evidence.turns = []; }, r => { r.stop_evidence.turns.push(proof()); },
    r => { r.stop_evidence.turns[0].turn_id = 'foreign'; },
    r => { r.stop_evidence.turns[0].provider_session_id = 'foreign'; },
    r => { r.stop_evidence.turns[0].provider_terminal_confirmed = false; },
    r => { r.stop_evidence.turns[0].provider_terminal_status = 'unavailable'; },
    r => { r.stop_evidence.turns[0].source = null; },
    r => { r.stop_evidence.turns[0].provider_terminal_sequence = null; },
  ];
  for (const corrupt of corruptions) {
    const result = closed([T]); corrupt(result);
    const { guardian } = await started(fixture(r => r.method === 'DELETE' ? result : undefined));
    await rejects(() => guardian.closeSession(S), 'conversation_close_receipt_rejected');
    assert.equal(guardian.snapshot().closed, false);
  }
});

test('provider-completed, failed and interrupted are all terminal; conflicting prior terminal is rejected', async () => {
  for (const status of ['completed', 'failed', 'interrupted']) {
    const result = closed([T]); result.stop_evidence.turns = [proof(T, status)];
    const { guardian } = await started(fixture(r => r.method === 'DELETE' ? result : undefined));
    assert.equal((await guardian.closeSession(S)).status, 'closed');
  }
  const { guardian } = await started(fixture(r => r.method === 'GET'
    ? events([event(1, 'turn_status', { stop_evidence: proof(T, 'completed', 9) }, T, 'completed')]) : undefined));
  await guardian.readEvents(S); assert.equal((await guardian.closeForHostLifecycle()).status, 'unknown');
});

test('parallel close is exact once, and every new ordinary action after closing rejects', async () => {
  const response = deferred(); const { guardian, calls } = await started(fixture(r => r.method === 'DELETE' ? response.promise : undefined));
  const close = guardian.closeForHostLifecycle(); const second = guardian.closeSession(S);
  assert.strictEqual(close, guardian.closeForHostLifecycle());
  for (const fn of [() => guardian.startSession(), () => guardian.startTurn(S, 'x'), () => guardian.readEvents(S),
    () => guardian.interruptTurn(S, T), () => guardian.respondToToolCall('call', {})]) await rejects(fn, 'conversation_closing');
  response.resolve(closed([T])); assert.equal((await close).status, 'closed'); await second;
  assert.equal(calls.filter(r => r.method === 'DELETE').length, 1);
});

test('no ordinary session has no shared-service action; no-turn session requires empty exact evidence', async () => {
  const fresh = fixture(); assert.equal((await fresh.guardian.closeForHostLifecycle()).status, 'closed'); assert.equal(fresh.calls.length, 0);
  const valid = fixture(); await valid.guardian.startSession(); assert.equal((await valid.guardian.closeSession(S)).status, 'closed');
  const bad = fixture(r => r.method === 'DELETE' ? closed([T]) : undefined);
  await bad.guardian.startSession(); assert.equal((await bad.guardian.closeForHostLifecycle()).status, 'unknown');
});

test('interrupt ACK cannot certify terminal or unlock next turn; a foreign response poisons binding', async () => {
  const good = await started(); const response = await good.guardian.interruptTurn(S, T);
  assert.equal(response.stop_evidence.provider_terminal_confirmed, false);
  await rejects(() => good.guardian.startTurn(S, 'again'), 'conversation_turn_pending');
  assert.equal((await good.guardian.closeForHostLifecycle()).status, 'closed');
  const bad = await started(fixture(r => r.path.endsWith('/interrupt') ? { ...turn(), turn_id: 'foreign' } : undefined));
  await rejects(() => bad.guardian.interruptTurn(S, T), 'conversation_interrupt_rejected');
  assert.equal((await bad.guardian.closeForHostLifecycle()).status, 'unknown');
});

// This contract test uses the real Adapter with an in-memory EventEmitter client.
// No child, HTTP listener, account lookup, or provider request is launched.
test('real Adapter DELETE fail-closes dynamic call before matching completion; shared client stop is never called', async () => {
  class Client extends EventEmitter {
    isReady = false; notificationSequence = 0; stopped = 0; callback = null;
    async start() { this.isReady = true; }
    async readAccount() { return { account: { type: 'chatgpt' }, requiresOpenaiAuth: true }; }
    async listModels() { return { data: [{ id: 'existing-model' }] }; }
    async startThread() { return { thread: { id: PROVIDER }, model: 'existing-model' }; }
    async startTurn() { return { turn: { id: T } }; }
    async interruptTurn(threadId, turnId) {
      assert.equal(this.callback?.success, false, 'DELETE must reject pending tool before interrupt');
      this.emit('notification', { sequence: ++this.notificationSequence, message: { method: 'turn/completed',
        params: { threadId, turn: { id: turnId, status: 'interrupted' } } } });
      return {};
    }
    async stop() { this.stopped++; throw new Error('Must not stop shared client'); }
  }
  const client = new Client(), adapter = new CodexAppServerAdapter({ client, sessionIdFactory: () => S });
  const guardian = new WorkbenchProductConversationGuardian({ conversationId: 'conversation-owned', dynamicTool,
    transport: async r => {
      if (r.path === `${P}/sessions`) return adapter.startSession(r.body.config, r.body.context_manifest);
      if (r.path.endsWith('/turns')) return adapter.startTurn(S, r.body.input, r.body.params);
      if (r.method === 'GET') return adapter.readEvents(S, { afterSequence: Number(r.path.split('after=')[1]) });
      if (r.method === 'DELETE') return adapter.closeSession(S);
      throw new Error('Unexpected fake request');
    } });
  await guardian.startSession(); await guardian.startTurn(S, 'public queue request');
  client.emit('serverRequest', { id: 7, method: 'item/tool/call', params: {
    threadId: PROVIDER, turnId: T, callId: 'call-owned', tool: dynamicTool.name, arguments: { action: 'status' } },
  respond: value => { client.callback = value; } });
  const polled = await guardian.readEvents(S); assert.equal(polled.events.filter(e => e.kind === 'tool_call').length, 1);
  const result = await guardian.closeSession(S);
  assert.equal(result.stop_evidence.provider_terminal_confirmed, true);
  assert.equal(result.stop_evidence.turns[0].source, 'turn/completed');
  assert.equal(client.stopped, 0); assert.equal(client.isReady, true);
});
