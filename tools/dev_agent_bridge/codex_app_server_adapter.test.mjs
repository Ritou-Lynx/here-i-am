import assert from 'node:assert/strict';
import { once } from 'node:events';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { CodexAppServerAdapter } from './codex_app_server_adapter.mjs';
import { stopReceiptFixture } from './test_fixtures/stop_receipt_child.mjs';
import {
  RuntimeAdapterError,
  RuntimeErrorCode,
  RuntimeEventKind,
  RuntimeStatus,
  createRuntimeEvent,
} from './runtime_adapter.mjs';

const fixturePath = fileURLToPath(
  new URL('./test_fixtures/fake_codex_app_server.mjs', import.meta.url),
);

let nextSession = 1;

function createAdapter(options = {}) {
  return new CodexAppServerAdapter({
    clientOptions: {
      commandSpec: {
        command: process.execPath,
        args: [fixturePath],
        source: 'test-fixture',
      },
      requestTimeoutMs: 2_000,
      stopTimeoutMs: 500,
    },
    activityTimeoutMs: 1_000,
    sessionIdFactory: () => `runtime-session-${nextSession++}`,
    ...options,
  });
}

async function waitForEvent(adapter, sessionId, predicate, timeoutMs = 2_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const found = adapter.readEvents(sessionId).events.find(predicate);
    if (found) return found;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error('Timed out waiting for runtime event.');
}

const dynamicTools = [{
  name: 'whiteboard_read_selection',
  description: 'Read the selected whiteboard items.',
  input_schema: {
    type: 'object',
    properties: {},
    additionalProperties: false,
  },
}];

test('freezes serializable provider-neutral event and error shapes', () => {
  const event = createRuntimeEvent({
    sequence: 1,
    sessionId: 'session-1',
    turnId: 'turn-1',
    kind: RuntimeEventKind.TURN_STATUS,
    status: RuntimeStatus.RUNNING,
    data: { reason: 'accepted' },
    providerMetadata: { provider: 'fixture' },
    occurredAt: '2026-08-21T00:00:00.000Z',
  });
  const error = new RuntimeAdapterError('No model', {
    code: RuntimeErrorCode.MODEL_UNAVAILABLE,
    operation: 'startSession',
    details: { requested_model: 'missing' },
  });

  assert.deepEqual(event, {
    schema_version: 1,
    event_id: 'session-1:1',
    sequence: 1,
    occurred_at: '2026-08-21T00:00:00.000Z',
    session_id: 'session-1',
    turn_id: 'turn-1',
    kind: 'turn_status',
    status: 'running',
    data: { reason: 'accepted' },
    provider_metadata: { provider: 'fixture' },
  });
  assert.deepEqual(error.toJSON(), {
    schema_version: 1,
    code: 'model_unavailable',
    message: 'No model',
    retryable: false,
    operation: 'startSession',
    details: { requested_model: 'missing' },
  });
});

test('discovers auth, capabilities, and models before starting a session', async (t) => {
  const adapter = createAdapter({ defaultModel: 'fake-model' });
  t.after(() => adapter.stop());

  const auth = await adapter.getAuthStatus();
  const capabilities = await adapter.listCapabilities();
  const session = await adapter.startSession(
    { model: 'fake-model', sandbox: 'read-only', ephemeral: true },
    { manifest_id: 'manifest-1' },
  );

  assert.equal(auth.auth_type, 'chatgpt');
  assert.ok(capabilities.capabilities.includes('turn_steer'));
  assert.deepEqual(
    capabilities.provider_metadata.models.map((model) => model.id),
    ['fake-model'],
  );
  assert.equal(session.status, 'idle');
  assert.equal(session.model, 'fake-model');
  assert.match(session.provider_metadata.provider_session_id, /^fake-thread-/);
});

test('fails fast when model/list does not contain the requested model', async (t) => {
  const adapter = createAdapter();
  t.after(() => adapter.stop());

  await assert.rejects(
    adapter.startSession({ model: 'not-installed-model' }),
    (error) => {
      assert.equal(error.code, RuntimeErrorCode.MODEL_UNAVAILABLE);
      assert.deepEqual(error.details.available_models, ['fake-model']);
      return true;
    },
  );
  assert.equal(adapter.sessions.size, 0);
});

test('normalizes turn events and supports cursor-based event reads', async (t) => {
  const adapter = createAdapter();
  t.after(() => adapter.stop());
  const session = await adapter.startSession({ model: 'fake-model' });
  const beforeTurn = adapter.readEvents(session.session_id).next_sequence;

  const turn = await adapter.startTurn(session.session_id, 'reply');
  const completed = await waitForEvent(
    adapter,
    session.session_id,
    (event) => event.turn_id === turn.turn_id && event.status === RuntimeStatus.COMPLETED,
  );
  const after = adapter.readEvents(session.session_id, { afterSequence: beforeTurn });

  assert.equal(completed.kind, RuntimeEventKind.TURN_STATUS);
  assert.ok(after.events.every((event) => event.sequence > beforeTurn));
  assert.ok(after.events.some((event) => (
    event.kind === RuntimeEventKind.MESSAGE_DELTA && event.data.text === 'FAKE_OK'
  )));
  assert.equal(after.status, RuntimeStatus.IDLE);
});

test('waits for real turn activity before steering, then interrupts', async (t) => {
  const adapter = createAdapter();
  t.after(() => adapter.stop());
  const session = await adapter.startSession({ model: 'fake-model' });
  const turn = await adapter.startTurn(session.session_id, 'slow');

  const steered = await adapter.steerTurn(
    session.session_id,
    turn.turn_id,
    'new direction',
  );
  assert.equal(steered.activity_observed, true);

  await adapter.interruptTurn(session.session_id, turn.turn_id);
  const interrupted = await waitForEvent(
    adapter,
    session.session_id,
    (event) => event.turn_id === turn.turn_id && event.status === RuntimeStatus.INTERRUPTED,
  );
  assert.equal(interrupted.kind, RuntimeEventKind.TURN_STATUS);
});

test('projects approval requests and sends an explicit answer', async (t) => {
  const adapter = createAdapter();
  t.after(() => adapter.stop());
  const session = await adapter.startSession({ model: 'fake-model' });
  const turn = await adapter.startTurn(session.session_id, 'approval');
  const requested = await waitForEvent(
    adapter,
    session.session_id,
    (event) => event.kind === RuntimeEventKind.APPROVAL_REQUEST,
  );

  const answer = await adapter.respondToApproval(requested.data.request_id, 'denied');
  const resolved = await waitForEvent(
    adapter,
    session.session_id,
    (event) => event.kind === RuntimeEventKind.APPROVAL_RESOLVED,
  );
  const terminal = await waitForEvent(
    adapter,
    session.session_id,
    (event) => event.turn_id === turn.turn_id && event.status === RuntimeStatus.FAILED,
  );

  assert.equal(answer.accepted, true);
  assert.equal(resolved.data.decision, 'denied');
  assert.equal(terminal.provider_metadata.provider_status, 'declined');
});

test('projects client-executed dynamic tools and returns bounded results', async (t) => {
  const adapter = createAdapter();
  t.after(() => adapter.stop());
  const session = await adapter.startSession({
    model: 'fake-model',
    dynamic_tools: dynamicTools,
  });
  const turn = await adapter.startTurn(session.session_id, 'dynamic-tool');
  const requested = await waitForEvent(
    adapter,
    session.session_id,
    (event) => event.kind === RuntimeEventKind.TOOL_CALL,
  );

  assert.equal(requested.turn_id, turn.turn_id);
  assert.equal(requested.data.tool_name, 'whiteboard_read_selection');
  assert.deepEqual(requested.data.arguments.selected_item_ids, ['item-1', 'item-2']);
  const answer = await adapter.respondToToolCall(requested.data.tool_call_id, {
    success: true,
    content_items: [{ type: 'text', text: '{"cards":2}' }],
  });
  const resolved = await waitForEvent(
    adapter,
    session.session_id,
    (event) => event.kind === RuntimeEventKind.TOOL_RESULT,
  );
  const terminal = await waitForEvent(
    adapter,
    session.session_id,
    (event) => event.turn_id === turn.turn_id && event.status === RuntimeStatus.COMPLETED,
  );

  assert.equal(answer.accepted, true);
  assert.equal(answer.success, true);
  assert.equal(resolved.data.tool_call_id, requested.data.tool_call_id);
  assert.equal(resolved.data.success, true);
  assert.equal(terminal.kind, RuntimeEventKind.TURN_STATUS);
  await assert.rejects(
    adapter.respondToToolCall(requested.data.tool_call_id, {
      success: true,
      content_items: [{ type: 'text', text: 'duplicate' }],
    }),
    (error) => error.code === RuntimeErrorCode.TOOL_CALL_NOT_FOUND,
  );
});

test('closing a session fail-closes pending dynamic tool calls', async (t) => {
  const adapter = createAdapter();
  t.after(() => adapter.stop());
  const session = await adapter.startSession({
    model: 'fake-model',
    dynamic_tools: dynamicTools,
  });
  await adapter.startTurn(session.session_id, 'dynamic-tool');
  const requested = await waitForEvent(
    adapter,
    session.session_id,
    (event) => event.kind === RuntimeEventKind.TOOL_CALL,
  );

  const closed = await adapter.closeSession(session.session_id);
  const history = adapter.readEvents(session.session_id).events;
  assert.equal(closed.status, RuntimeStatus.CLOSED);
  assert.equal(adapter.toolCalls.size, 0);
  assert.ok(history.some((event) => (
    event.kind === RuntimeEventKind.TOOL_RESULT &&
    event.data.tool_call_id === requested.data.tool_call_id &&
    event.data.reason === 'session_closed' &&
    event.data.fail_closed === true
  )));
});

test('rejects malformed dynamic tools and tool results before provider response', async (t) => {
  const adapter = createAdapter();
  t.after(() => adapter.stop());
  await assert.rejects(
    adapter.startSession({
      model: 'fake-model',
      dynamic_tools: [{ ...dynamicTools[0], name: 'bad tool name' }],
    }),
    (error) => error.code === RuntimeErrorCode.INVALID_REQUEST,
  );
  const session = await adapter.startSession({
    model: 'fake-model',
    dynamic_tools: dynamicTools,
  });
  await adapter.startTurn(session.session_id, 'dynamic-tool');
  const requested = await waitForEvent(
    adapter,
    session.session_id,
    (event) => event.kind === RuntimeEventKind.TOOL_CALL,
  );
  await assert.rejects(
    adapter.respondToToolCall(requested.data.tool_call_id, {
      success: true,
      content_items: [],
    }),
    (error) => error.code === RuntimeErrorCode.INVALID_REQUEST,
  );
  assert.equal(adapter.toolCalls.has(requested.data.tool_call_id), true);
  await adapter.closeSession(session.session_id);
});

test('resumes a provider session after replacing the local adapter', async (t) => {
  const first = createAdapter();
  const started = await first.startSession({ model: 'fake-model' });
  const providerSessionId = started.provider_metadata.provider_session_id;
  await first.stop();

  const second = createAdapter();
  t.after(() => second.stop());
  const resumed = await second.resumeSession(providerSessionId, { model: 'fake-model' });

  assert.notEqual(resumed.session_id, started.session_id);
  assert.equal(resumed.provider_metadata.provider_session_id, providerSessionId);
  assert.equal(resumed.status, RuntimeStatus.IDLE);
});

test('reinitializes the same adapter after client exit and resumes the provider session', async (t) => {
  const adapter = createAdapter();
  t.after(() => adapter.stop());
  const started = await adapter.startSession({ model: 'fake-model' });
  const providerSessionId = started.provider_metadata.provider_session_id;
  const stopped = once(adapter.client, 'stopped');

  await adapter.client.request('test/exit');
  await stopped;
  assert.equal(adapter._readyPromise, null);
  assert.equal(adapter.account, null);
  assert.equal(adapter.models, null);
  assert.equal(adapter.readEvents(started.session_id).status, RuntimeStatus.UNAVAILABLE);

  const auth = await adapter.getAuthStatus();
  const resumed = await adapter.resumeSession(providerSessionId, { model: 'fake-model' });
  assert.equal(auth.auth_type, 'chatgpt');
  assert.notEqual(resumed.session_id, started.session_id);
  assert.equal(resumed.provider_metadata.provider_session_id, providerSessionId);
  assert.equal(adapter.client.isReady, true);
});

test('close fail-closes pending approvals and leaves no callable approval callback', async (t) => {
  const adapter = createAdapter();
  t.after(() => adapter.stop());
  const session = await adapter.startSession({ model: 'fake-model' });
  await adapter.startTurn(session.session_id, 'approval');
  const requested = await waitForEvent(
    adapter,
    session.session_id,
    (event) => event.kind === RuntimeEventKind.APPROVAL_REQUEST,
  );

  const closed = await adapter.closeSession(session.session_id);
  const history = adapter.readEvents(session.session_id).events;

  assert.equal(closed.status, RuntimeStatus.CLOSED);
  assert.equal(adapter.approvals.size, 0);
  assert.ok(history.some((event) => (
    event.kind === RuntimeEventKind.APPROVAL_RESOLVED &&
    event.data.request_id === requested.data.request_id &&
    event.data.reason === 'session_closed' &&
    event.data.fail_closed === true
  )));
  await assert.rejects(
    adapter.respondToApproval(requested.data.request_id, 'approved'),
    (error) => error.code === RuntimeErrorCode.APPROVAL_NOT_FOUND,
  );
});

test('close interrupts and waits for an active turn before closing the binding', async (t) => {
  const adapter = createAdapter();
  t.after(() => adapter.stop());
  const session = await adapter.startSession({ model: 'fake-model' });
  const turn = await adapter.startTurn(session.session_id, 'slow');

  const closed = await adapter.closeSession(session.session_id);
  const history = adapter.readEvents(session.session_id).events;
  const turnTerminal = history.find((event) => (
    event.turn_id === turn.turn_id && event.status === RuntimeStatus.INTERRUPTED
  ));
  const sessionClosed = history.find((event) => (
    event.kind === RuntimeEventKind.SESSION_STATUS &&
    event.status === RuntimeStatus.CLOSED
  ));

  assert.equal(closed.status, RuntimeStatus.CLOSED);
  assert.ok(turnTerminal);
  assert.equal(sessionClosed.data.active_turn_policy, 'interrupt_and_wait');
  assert.equal(sessionClosed.data.approvals_policy, 'fail_closed');
});

test('does not resurrect a turn completed before the turn/start response', async (t) => {
  const adapter = createAdapter();
  t.after(() => adapter.stop());
  const session = await adapter.startSession({ model: 'fake-model' });

  const turn = await adapter.startTurn(session.session_id, 'complete-before-response');
  const snapshot = adapter.readEvents(session.session_id);
  const statuses = snapshot.events
    .filter((event) => event.turn_id === turn.turn_id && event.kind === RuntimeEventKind.TURN_STATUS)
    .map((event) => event.status);

  assert.equal(turn.status, RuntimeStatus.COMPLETED);
  assert.equal(snapshot.status, RuntimeStatus.IDLE);
  assert.equal(statuses.at(-1), RuntimeStatus.COMPLETED);
  assert.equal(statuses.filter((status) => status === RuntimeStatus.RUNNING).length, 1);

  const next = await adapter.startTurn(session.session_id, 'reply');
  await waitForEvent(
    adapter,
    session.session_id,
    (event) => event.turn_id === next.turn_id && event.status === RuntimeStatus.COMPLETED,
  );
});

test('rejects non-positive and non-finite steering timeouts', async (t) => {
  const adapter = createAdapter();
  t.after(() => adapter.stop());
  const session = await adapter.startSession({ model: 'fake-model' });
  const turn = await adapter.startTurn(session.session_id, 'slow');

  for (const invalid of [-1, 0, Number.POSITIVE_INFINITY]) {
    await assert.rejects(
      adapter.steerTurn(session.session_id, turn.turn_id, 'direction', {
        activityTimeoutMs: invalid,
      }),
      (error) => error.code === RuntimeErrorCode.INVALID_REQUEST,
    );
  }
  await adapter.interruptTurn(session.session_id, turn.turn_id);
});

function receiptAdapter(t) {
  const fixture = stopReceiptFixture(t);
  const adapter = createAdapter({ client: fixture.client, closeTimeoutMs: 25 });
  const snapshot = adapter._registerSession({ thread: { id: 'receipt-thread' } }, {
    config: {}, contextManifest: {}, resumed: false,
  });
  const sessionId = snapshot.session_id;
  const turnId = 'receipt-turn';
  const notify = (method, params) => fixture.send({ method, params });
  const terminal = (status = 'interrupted', threadId = 'receipt-thread', id = turnId) => {
    notify('turn/completed', { threadId, turn: { id, status } });
  };
  notify('turn/started', { threadId: 'receipt-thread', turn: { id: turnId } });
  let interrupts = 0;
  fixture.client.interruptTurn = async (_threadId, _turnId, { onDispatched } = {}) => {
    interrupts++;
    onDispatched?.();
    return {};
  };
  return {
    ...fixture, adapter, sessionId, turnId, notify, terminal,
    interruptCount: () => interrupts,
  };
}

test('interrupt ACK is explicitly unconfirmed and repeated interrupts share it', async (t) => {
  const f = receiptAdapter(t);
  const [first, second] = await Promise.all([
    f.adapter.interruptTurn(f.sessionId, f.turnId),
    f.adapter.interruptTurn(f.sessionId, f.turnId),
  ]);
  assert.deepEqual(first, second);
  assert.equal(f.interruptCount(), 1);
  assert.equal(first.status, RuntimeStatus.RUNNING);
  assert.equal(first.stop_evidence.interrupt_acknowledged, true);
  assert.equal(first.stop_evidence.provider_terminal_confirmed, false);
  assert.equal(first.stop_evidence.cancellation_confirmed, false);
  assert.equal(first.stop_receipt, undefined);
  assert.equal(first.stop_evidence.profile, undefined);
  await f.adapter.interruptTurn(f.sessionId, f.turnId);
  assert.equal(f.interruptCount(), 1);
  await assert.rejects(f.adapter.waitForTurnTerminal(f.sessionId, f.turnId), (error) => {
    assert.equal(error.details.stop_evidence.provider_terminal_confirmed, false);
    return true;
  });
  assert.equal(f.client.listenerCount('notification'), 1);
  assert.equal(f.client.listenerCount('stopped'), 1);
});

for (const status of ['interrupted', 'completed', 'failed']) {
  test(`matching ${status} terminal is distinct from interrupt ACK`, async (t) => {
    const f = receiptAdapter(t);
    await f.adapter.interruptTurn(f.sessionId, f.turnId);
    const waiting = f.adapter.waitForTurnTerminal(f.sessionId, f.turnId);
    f.terminal(status);
    const result = await waiting;
    assert.equal(result.status, status);
    assert.equal(result.stop_evidence.provider_session_id, 'receipt-thread');
    assert.equal(result.stop_evidence.turn_id, f.turnId);
    assert.equal(result.stop_evidence.source, 'turn/completed');
    assert.equal(result.stop_evidence.provider_terminal_confirmed, true);
    assert.equal(result.stop_evidence.provider_terminal_status, status);
    assert.equal(result.stop_evidence.cancellation_confirmed, status === 'interrupted');
    assert.ok(result.stop_evidence.provider_terminal_sequence > 1);
    const sequence = f.adapter.readEvents(f.sessionId).next_sequence;
    f.notify('item/agentMessage/delta', {
      threadId: 'receipt-thread', turnId: f.turnId, delta: 'LATE_TEXT',
    });
    f.terminal('completed');
    assert.equal(f.adapter.readEvents(f.sessionId).next_sequence, sequence);
  });
}

test('terminal before ACK is retained without inventing acknowledgement', async (t) => {
  const f = receiptAdapter(t);
  let acknowledge;
  f.client.interruptTurn = (_threadId, _turnId, { onDispatched }) => {
    onDispatched();
    return new Promise((resolve) => { acknowledge = resolve; });
  };
  const interrupting = f.adapter.interruptTurn(f.sessionId, f.turnId);
  await Promise.resolve();
  f.terminal();
  const result = await f.adapter.waitForTurnTerminal(f.sessionId, f.turnId);
  assert.equal(result.stop_evidence.provider_terminal_confirmed, true);
  assert.equal(result.stop_evidence.interrupt_acknowledged, false);
  acknowledge({});
  assert.equal((await interrupting).stop_evidence.interrupt_acknowledged, true);
});

test('wrong thread, wrong turn and error notifications never certify target stop', async (t) => {
  const f = receiptAdapter(t);
  await f.adapter.interruptTurn(f.sessionId, f.turnId);
  const rejected = assert.rejects(f.adapter.waitForTurnTerminal(f.sessionId, f.turnId), (error) => {
    assert.equal(error.details.stop_evidence.provider_terminal_confirmed, false);
    assert.equal(error.details.stop_evidence.turn_id, f.turnId);
    return true;
  });
  f.terminal('interrupted', 'wrong-thread');
  f.terminal('interrupted', 'receipt-thread', 'wrong-turn');
  f.notify('error', { threadId: 'receipt-thread', turnId: f.turnId, error: { message: 'lost stream' } });
  await rejected;
});

test('invalid terminal status fails receipt validation', async (t) => {
  const f = receiptAdapter(t);
  await f.adapter.interruptTurn(f.sessionId, f.turnId);
  const rejected = assert.rejects(f.adapter.waitForTurnTerminal(f.sessionId, f.turnId), (error) => {
    assert.equal(error.code, RuntimeErrorCode.PROTOCOL_ERROR);
    assert.equal(error.details.stop_evidence.provider_terminal_confirmed, false);
    assert.equal(error.details.stop_evidence.cancellation_confirmed, false);
    return true;
  });
  f.terminal('inProgress');
  await rejected;
});

test('unavailable close only closes local binding and cannot backfill a late receipt', async (t) => {
  const f = receiptAdapter(t);
  f.client.state = 'unavailable';
  const closed = await f.adapter.closeSession(f.sessionId);
  assert.equal(closed.status, RuntimeStatus.CLOSED);
  assert.equal(closed.stop_evidence.local_binding_closed, true);
  assert.equal(closed.stop_evidence.provider_terminal_confirmed, false);
  assert.equal(closed.stop_evidence.turns[0].cancellation_confirmed, false);
  assert.equal(f.interruptCount(), 0);
  const before = f.adapter.readEvents(f.sessionId);
  assert.equal(before.events.some((event) => event.status === RuntimeStatus.INTERRUPTED), false);
  assert.ok(before.events.some((event) => event.kind === RuntimeEventKind.TURN_STATUS &&
    event.status === RuntimeStatus.UNAVAILABLE));
  f.terminal();
  assert.deepEqual(f.adapter.readEvents(f.sessionId), before);
  assert.deepEqual(await f.adapter.closeSession(f.sessionId), closed);
});

test('ACK-only close times out without closing and retries after a late terminal', async (t) => {
  const f = receiptAdapter(t);
  const results = await Promise.allSettled([
    f.adapter.closeSession(f.sessionId), f.adapter.closeSession(f.sessionId),
  ]);
  for (const result of results) {
    assert.equal(result.status, 'rejected');
    assert.equal(result.reason.details.stop_evidence.provider_terminal_confirmed, false);
  }
  assert.equal(f.interruptCount(), 1);
  assert.notEqual(f.adapter.readEvents(f.sessionId).status, RuntimeStatus.CLOSED);
  assert.equal(f.client.listenerCount('notification'), 1);
  f.terminal();
  const closed = await f.adapter.closeSession(f.sessionId);
  assert.equal(closed.stop_evidence.provider_terminal_confirmed, true);
  assert.equal(closed.stop_evidence.turns[0].cancellation_confirmed, true);
});

test('client disconnect during terminal wait yields unconfirmed failure', async (t) => {
  const f = receiptAdapter(t);
  await f.adapter.interruptTurn(f.sessionId, f.turnId);
  const rejected = assert.rejects(f.adapter.waitForTurnTerminal(f.sessionId, f.turnId), (error) => {
    assert.equal(error.details.stop_evidence.provider_terminal_confirmed, false);
    return true;
  });
  f.child.emit('close', 1, null);
  await rejected;
  assert.equal(f.adapter.readEvents(f.sessionId).status, RuntimeStatus.UNAVAILABLE);
  const closed = await f.adapter.closeSession(f.sessionId);
  assert.equal(closed.stop_evidence.provider_terminal_confirmed, false);
});

test('adapter stop propagates unobserved child close as an error', async (t) => {
  const f = receiptAdapter(t);
  await assert.rejects(f.adapter.stop(), (error) => {
    assert.equal(error.code, 'stop_close_unconfirmed');
    assert.equal(error.data.process_close_observed, false);
    return true;
  });
  assert.equal(f.client.child, f.child);
});

test('close waits for in-flight start and blocks new start and steer work', async (t) => {
  const f = receiptAdapter(t);
  f.terminal('completed');
  let releaseStart;
  f.client.startTurn = () => new Promise((resolve) => { releaseStart = resolve; });
  const starting = f.adapter.startTurn(f.sessionId, 'delayed start');
  const closing = f.adapter.closeSession(f.sessionId);
  await assert.rejects(f.adapter.startTurn(f.sessionId, 'another start'), /close is in progress/);
  await assert.rejects(f.adapter.steerTurn(f.sessionId, f.turnId, 'steer'), /close is in progress/);
  assert.notEqual(f.adapter.readEvents(f.sessionId).status, RuntimeStatus.CLOSED);
  f.client.interruptTurn = async (threadId, turnId, { onDispatched }) => {
    onDispatched();
    assert.equal(turnId, 'delayed-turn');
    f.terminal('interrupted', threadId, turnId);
    return {};
  };
  releaseStart({ turn: { id: 'delayed-turn' } });
  assert.equal((await starting).turn_id, 'delayed-turn');
  const closed = await closing;
  assert.equal(closed.status, RuntimeStatus.CLOSED);
  assert.equal(closed.stop_evidence.provider_terminal_confirmed, true);
  assert.equal(closed.stop_evidence.turns.find((turn) => turn.turn_id === 'delayed-turn').cancellation_confirmed, true);
});

test('pending start close timeout retains binding and tracks its eventual turn', async (t) => {
  const f = receiptAdapter(t);
  f.terminal('completed');
  let releaseStart;
  f.client.startTurn = () => new Promise((resolve) => { releaseStart = resolve; });
  const starting = f.adapter.startTurn(f.sessionId, 'delayed start');
  await assert.rejects(f.adapter.closeSession(f.sessionId), (error) => {
    assert.equal(error.code, RuntimeErrorCode.TIMEOUT);
    assert.equal(error.details.stop_evidence.pending_start, true);
    assert.equal(error.details.stop_evidence.provider_terminal_confirmed, false);
    return true;
  });
  assert.notEqual(f.adapter.readEvents(f.sessionId).status, RuntimeStatus.CLOSED);
  await assert.rejects(f.adapter.startTurn(f.sessionId, 'duplicate'), /pending or unconfirmed/);
  releaseStart({ turn: { id: 'eventual-turn' } });
  assert.equal((await starting).status, RuntimeStatus.RUNNING);
  f.client.interruptTurn = async (threadId, turnId, { onDispatched }) => {
    onDispatched();
    f.terminal('interrupted', threadId, turnId);
    return {};
  };
  assert.equal((await f.adapter.closeSession(f.sessionId)).stop_evidence.provider_terminal_confirmed, true);
});

test('failed start with unknown provider outcome cannot close as an empty session', async (t) => {
  const f = receiptAdapter(t);
  f.terminal('completed');
  f.client.startTurn = async () => { throw new Error('synthetic start response lost'); };
  await assert.rejects(f.adapter.startTurn(f.sessionId, 'start'), /response lost/);
  await assert.rejects(f.adapter.closeSession(f.sessionId), (error) => {
    assert.equal(error.details.stop_evidence.pending_start, true);
    assert.equal(error.details.stop_evidence.provider_terminal_confirmed, false);
    return true;
  });
  assert.notEqual(f.adapter.readEvents(f.sessionId).status, RuntimeStatus.CLOSED);
});

test('conflicting completion turn identifiers cannot certify either target', async (t) => {
  const f = receiptAdapter(t);
  await f.adapter.interruptTurn(f.sessionId, f.turnId);
  const waiting = assert.rejects(f.adapter.waitForTurnTerminal(f.sessionId, f.turnId), (error) => {
    assert.equal(error.details.stop_evidence.provider_terminal_confirmed, false);
    return true;
  });
  f.notify('turn/completed', {
    threadId: 'receipt-thread', turnId: 'conflicting-turn',
    turn: { id: f.turnId, status: 'interrupted' },
  });
  await waiting;
});

test('terminal before interrupt dispatch does not claim this request cancelled it', async (t) => {
  const f = receiptAdapter(t);
  const interrupting = f.adapter.interruptTurn(f.sessionId, f.turnId);
  f.terminal();
  const result = await interrupting;
  assert.equal(result.stop_evidence.provider_terminal_confirmed, true);
  assert.equal(result.stop_evidence.interrupt_requested, false);
  assert.equal(result.stop_evidence.interrupt_acknowledged, false);
  assert.equal(result.stop_evidence.cancellation_confirmed, false);
  assert.equal(f.interruptCount(), 0);
});

function callbackRequests(f, suffix, responses) {
  f.adapter.sessions.get(f.sessionId).config.dynamic_tools = dynamicTools;
  const approvalId = `approval-${suffix}`;
  const toolCallId = `tool-${suffix}`;
  f.client.emit('serverRequest', {
    id: approvalId, method: 'item/commandExecution/requestApproval',
    params: { threadId: 'receipt-thread', turnId: f.turnId },
    respond: (result) => responses.push({ id: approvalId, result }),
  });
  f.client.emit('serverRequest', {
    id: toolCallId, method: 'item/tool/call',
    params: {
      threadId: 'receipt-thread', turnId: f.turnId,
      callId: toolCallId, tool: dynamicTools[0].name, arguments: {},
    },
    respond: (result) => responses.push({ id: toolCallId, result }),
  });
  return { approvalId, toolCallId };
}

test('closing rejects late approval and tool requests before ACK and terminal', async (t) => {
  const f = receiptAdapter(t);
  const responses = [];
  const initial = callbackRequests(f, 'initial', responses);
  const staleApproval = f.adapter.approvals.get(initial.approvalId);
  const staleTool = f.adapter.toolCalls.get(initial.toolCallId);
  let acknowledge;
  f.client.interruptTurn = (_threadId, _turnId, { onDispatched }) => {
    onDispatched();
    return new Promise((resolve) => { acknowledge = resolve; });
  };
  const closing = f.adapter.closeSession(f.sessionId);
  await Promise.resolve();
  await Promise.resolve();
  const cursor = f.adapter.readEvents(f.sessionId).next_sequence;
  const beforeAck = callbackRequests(f, 'before-ack', responses);
  acknowledge({});
  await Promise.resolve();
  const beforeTerminal = callbackRequests(f, 'before-terminal', responses);
  f.terminal();
  await closing;
  callbackRequests(f, 'closed', responses);
  assert.equal(f.adapter.readEvents(f.sessionId, { afterSequence: cursor }).events.some((event) =>
    [RuntimeEventKind.APPROVAL_REQUEST, RuntimeEventKind.TOOL_CALL].includes(event.kind)), false);
  assert.equal(f.adapter.approvals.size, 0);
  assert.equal(f.adapter.toolCalls.size, 0);
  for (const result of responses) {
    assert.ok(result.result.decision === 'decline' || result.result.success === false);
  }
  assert.equal(responses.length, 8);
  // Simulate stale callback retention: the public response entry must still
  // validate ownership before invoking a stored provider callback.
  f.adapter.approvals.set(initial.approvalId, staleApproval);
  f.adapter.toolCalls.set(initial.toolCallId, staleTool);
  for (const ids of [initial, beforeAck, beforeTerminal]) {
    await assert.rejects(f.adapter.respondToApproval(ids.approvalId, 'approved'),
      (error) => error.code === RuntimeErrorCode.APPROVAL_NOT_FOUND);
    await assert.rejects(f.adapter.respondToToolCall(ids.toolCallId, {
      success: true, content_items: [{ type: 'text', text: 'forbidden late result' }],
    }), (error) => error.code === RuntimeErrorCode.TOOL_CALL_NOT_FOUND);
  }
  assert.equal(responses.length, 8);
});

test('terminal discards pending callbacks and rejects subsequent inbound requests', async (t) => {
  const f = receiptAdapter(t);
  const responses = [];
  const pending = callbackRequests(f, 'pending', responses);
  f.terminal('completed');
  assert.equal(f.adapter.approvals.size, 0);
  assert.equal(f.adapter.toolCalls.size, 0);
  assert.equal(responses.length, 0);
  await assert.rejects(f.adapter.respondToApproval(pending.approvalId, 'approved'));
  await assert.rejects(f.adapter.respondToToolCall(pending.toolCallId, {
    success: true, content_items: [{ type: 'text', text: 'late result' }],
  }));
  const cursor = f.adapter.readEvents(f.sessionId).next_sequence;
  callbackRequests(f, 'after-terminal', responses);
  assert.equal(responses.length, 2);
  assert.equal(responses[0].result.decision, 'decline');
  assert.equal(responses[1].result.success, false);
  assert.equal(f.adapter.readEvents(f.sessionId).next_sequence, cursor);
});

for (const kind of ['approval', 'tool']) {
  test(`close retains ${kind} callback until its required negative provider reply`, async (t) => {
    const f = receiptAdapter(t);
    const responses = [];
    const id = `close-race-${kind}`;
    f.adapter.sessions.get(f.sessionId).config.dynamic_tools = dynamicTools;
    f.client.emit('serverRequest', {
      id,
      method: kind === 'approval' ? 'item/commandExecution/requestApproval' : 'item/tool/call',
      params: {
        threadId: 'receipt-thread', turnId: f.turnId,
        ...(kind === 'tool' ? { callId: id, tool: dynamicTools[0].name, arguments: {} } : {}),
      },
      respond: (result) => {
        responses.push(result);
        // The fake provider releases its turn only after the adapter supplies
        // this callback's negative answer. Interrupt ACK alone cannot do so.
        if (result.decision === 'decline' || result.success === false) f.terminal();
      },
    });
    const closing = f.adapter.closeSession(f.sessionId);
    const rejected = kind === 'approval'
      ? assert.rejects(f.adapter.respondToApproval(id, 'approved'),
        (error) => error.code === RuntimeErrorCode.APPROVAL_NOT_FOUND)
      : assert.rejects(f.adapter.respondToToolCall(id, {
        success: true, content_items: [{ type: 'text', text: 'forbidden late result' }],
      }), (error) => error.code === RuntimeErrorCode.TOOL_CALL_NOT_FOUND);
    assert.equal(responses.length, 0);
    assert.equal((kind === 'approval' ? f.adapter.approvals : f.adapter.toolCalls).has(id), true);
    const [closed] = await Promise.all([closing, rejected]);
    assert.equal(responses.length, 1);
    assert.ok(kind === 'approval' ? responses[0].decision === 'decline' : responses[0].success === false);
    assert.equal(closed.status, RuntimeStatus.CLOSED);
    assert.equal(closed.stop_evidence.provider_terminal_confirmed, true);
    assert.equal(f.adapter.approvals.size, 0);
    assert.equal(f.adapter.toolCalls.size, 0);
  });
}

for (const failure of ['unavailable', 'write-throws']) {
  test(`undispatched interrupt ${failure} cannot claim cancellation`, async (t) => {
    const f = receiptAdapter(t);
    f.client.interruptTurn = Object.getPrototypeOf(f.client).interruptTurn.bind(f.client);
    if (failure === 'unavailable') f.client.state = 'stopping';
    else f.child.stdin.write = () => { throw new Error('synthetic write failed'); };
    await assert.rejects(f.adapter.interruptTurn(f.sessionId, f.turnId), (error) => {
      assert.equal(error.details.stop_evidence.interrupt_requested, false);
      return true;
    });
    f.terminal();
    const terminal = await f.adapter.waitForTurnTerminal(f.sessionId, f.turnId);
    assert.equal(terminal.stop_evidence.provider_terminal_confirmed, true);
    assert.equal(terminal.stop_evidence.interrupt_requested, false);
    assert.equal(terminal.stop_evidence.cancellation_confirmed, false);
  });
}

test('dispatched interrupt keeps dispatch evidence after ACK timeout', async (t) => {
  const f = receiptAdapter(t);
  f.client.interruptTurn = Object.getPrototypeOf(f.client).interruptTurn.bind(f.client);
  await assert.rejects(f.adapter.interruptTurn(f.sessionId, f.turnId), (error) => {
    assert.equal(error.details.stop_evidence.interrupt_requested, true);
    assert.equal(error.details.stop_evidence.interrupt_acknowledged, false);
    return true;
  });
  f.terminal();
  const terminal = await f.adapter.waitForTurnTerminal(f.sessionId, f.turnId);
  assert.equal(terminal.stop_evidence.provider_terminal_confirmed, true);
  assert.equal(terminal.stop_evidence.interrupt_requested, true);
  assert.equal(terminal.stop_evidence.interrupt_acknowledged, false);
  assert.equal(terminal.stop_evidence.cancellation_confirmed, true);
});
