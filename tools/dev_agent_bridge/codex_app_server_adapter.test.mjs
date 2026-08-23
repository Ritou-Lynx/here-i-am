import assert from 'node:assert/strict';
import { once } from 'node:events';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { CodexAppServerAdapter } from './codex_app_server_adapter.mjs';
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
