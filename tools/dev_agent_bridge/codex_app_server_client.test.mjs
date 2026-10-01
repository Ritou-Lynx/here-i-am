import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { stopReceiptFixture } from './test_fixtures/stop_receipt_child.mjs';

import {
  CodexAppServerClient,
  CodexAppServerError,
} from './codex_app_server_client.mjs';
import { WorkbenchTextTaskSession } from './workbench_text_task_session.mjs';

const fixturePath = fileURLToPath(
  new URL('./test_fixtures/fake_codex_app_server.mjs', import.meta.url),
);
function createClient(options = {}) {
  return new CodexAppServerClient({
    commandSpec: {
      command: process.execPath,
      args: [fixturePath],
      source: 'test-fixture',
    },
    requestTimeoutMs: 2_000,
    stopTimeoutMs: 500,
    ...options,
  });
}

test('starts with initialize handshake and reads sanitized auth source fields', async (t) => {
  const client = createClient();
  t.after(() => client.stop());

  const initialized = await client.start();
  const account = await client.readAccount();

  assert.equal(initialized.userAgent, 'fake-codex-app-server/1.0');
  assert.equal(client.state, 'ready');
  assert.equal(account.account.type, 'chatgpt');
  assert.equal(account.account.planType, 'pro');
});

test('attached transport initializes without spawning', async (t) => {
  const transport = new AttachedTransportFixture();
  const client = createAttachedClient(transport);
  t.after(() => client.stop().catch(() => {}));
  await client.start();
  assert.equal(client.child, null);
  assert.equal(client.isReady, true);
  assert.deepEqual(transport.sent.map(message => message.method), ['initialize', 'initialized']);
});

test('attached transport rejects spawn configuration', () => {
  const transport = new AttachedTransportFixture();
  assert.throws(() => new CodexAppServerClient({
    attachedTransport: transport,
    commandSpec: { command: 'must-not-run' },
  }), /cannot be combined/);
  assert.throws(() => new CodexAppServerClient({
    attachedTransport: transport,
    spawnImpl: () => { throw new Error('must-not-run'); },
  }), /cannot be combined/);
});

test('attached request retains a late real dispatch acknowledgement after timeout', async (t) => {
  const transport = new AttachedTransportFixture();
  const client = createAttachedClient(transport);
  t.after(() => client.stop().catch(() => {}));
  await client.start();
  let dispatched = 0;
  transport.onSend = (message, onDispatched) => {
    if (message.method === 'turn/interrupt') setTimeout(() => onDispatched(), 30);
    else onDispatched?.();
    return Promise.resolve();
  };
  await assert.rejects(client.request('turn/interrupt', {}, {
    timeoutMs: 5, onDispatched: () => dispatched++,
  }), error => error.code === 'request_timeout');
  await new Promise(resolve => setTimeout(resolve, 50));
  assert.equal(dispatched, 1);
});

test('attached timeout without an ACK does not defer or retain later notifications', async (t) => {
  const transport = new AttachedTransportFixture();
  const client = createAttachedClient(transport);
  t.after(() => client.stop().catch(() => {}));
  await client.start();
  transport.onSend = () => Promise.resolve();
  await assert.rejects(client.request('turn/interrupt', {}, { timeoutMs: 5 }), /timed out/);
  for (let index = 0; index < 501; index++) {
    transport.emit('message', { method: 'item/agentMessage/delta', params: { index } });
  }
  assert.equal(client.notificationSequence, 501);
  assert.equal(client._notificationHistory.length, 500);
});

test('attached response before dispatch acknowledgement fails closed', async (t) => {
  const transport = new AttachedTransportFixture();
  const client = createAttachedClient(transport);
  t.after(() => client.stop().catch(() => {}));
  await client.start();
  transport.onSend = (message, onDispatched) => {
    if (message.method === 'thread/start') {
      transport.emit('message', { id: message.id, result: { thread: { id: 'too-early' } } });
      setTimeout(() => onDispatched(), 10);
      return Promise.resolve();
    }
    onDispatched?.();
    return Promise.resolve();
  };
  await assert.rejects(client.startThread(), error => error.code === 'response_before_dispatch');
  assert.equal(client.state, 'unavailable');
});

async function attachedSessionReceipt(t, terminalBeforeInterruptAck) {
  const transport = new AttachedTransportFixture();
  const client = createAttachedClient(transport);
  t.after(() => client.stop().catch(() => {}));
  await client.start();
  const broker = {
    arm() {}, revoke() {}, async close() {}, snapshot() { return { drained: true }; },
  };
  const session = new WorkbenchTextTaskSession({
    client, broker, closeChild: async () => true,
    localSessionId: `attached-${terminalBeforeInterruptAck ? 'before' : 'after'}`,
    executionEpoch: 'f2a4dd55-d0e5-434f-8316-49ab22c54145',
    providerThreadId: 'provider-thread', terminalTimeoutMs: 100,
  });
  transport.onSend = (message, onDispatched) => {
    if (message.method === 'turn/start') {
      onDispatched();
      queueMicrotask(() => transport.emit('message', {
        id: message.id, result: { turn: { id: 'provider-turn' } },
      }));
      return Promise.resolve();
    }
    if (message.method === 'turn/interrupt') {
      const terminal = () => transport.emit('message', {
        method: 'turn/completed',
        params: { threadId: 'provider-thread', turn: { id: 'provider-turn', status: 'interrupted' } },
      });
      if (terminalBeforeInterruptAck) terminal();
      setTimeout(() => {
        onDispatched();
        if (!terminalBeforeInterruptAck) terminal();
        transport.emit('message', { id: message.id, result: {} });
      }, 5);
      return Promise.resolve();
    }
    onDispatched?.();
    return Promise.resolve();
  };
  await session.startTurn('task');
  return session.close();
}

test('attached client preserves terminal-before-interrupt-ACK ordering for session receipts', async (t) => {
  const receipt = await attachedSessionReceipt(t, true);
  assert.equal(receipt.provider_terminal_status, 'interrupted');
  assert.equal(receipt.provider_terminal_sequence, 1);
  assert.equal(receipt.interrupt_dispatch_sequence, 1);
  assert.equal(receipt.cancellation_confirmed, false);
});

test('attached client confirms interruption only when terminal follows interrupt ACK', async (t) => {
  const receipt = await attachedSessionReceipt(t, false);
  assert.equal(receipt.interrupt_dispatch_sequence, 0);
  assert.equal(receipt.provider_terminal_sequence, 1);
  assert.equal(receipt.cancellation_confirmed, true);
});

test('attached transport loss is not process-close proof and remains cleanup-owned', async () => {
  const transport = new AttachedTransportFixture();
  const client = createAttachedClient(transport);
  await client.start();
  transport.emit('close', { process_close_observed: false, reason: 'ipc_lost' });
  assert.equal(client.state, 'unavailable');
  assert.equal(client.attachedTransport, transport);
  transport.closeReceipt = { process_close_observed: false, reason: 'ipc_lost' };
  await assert.rejects(client.stop(), error => error.code === 'stop_close_unconfirmed');
  assert.equal(client.state, 'stop_unconfirmed');
  assert.equal(client.attachedTransport, transport);
  transport.emit('close', { process_close_observed: true, exit_code: 0 });
  assert.equal(client.state, 'stopped');
  assert.equal(client.attachedTransport, null);
});

test('late attached messages are ignored after a proven close finalizes ownership', async () => {
  const transport = new AttachedTransportFixture();
  const client = createAttachedClient(transport);
  await client.start();
  await client.stop();
  transport.emit('message', { method: 'turn/completed', params: {} });
  assert.equal(client.state, 'stopped');
  assert.equal(client.notificationSequence, 0);
});

test('attached initialization failure retains cleanup ownership when close is unconfirmed', async () => {
  const transport = new AttachedTransportFixture();
  transport.onSend = (message) => message.method === 'initialize'
    ? Promise.reject(new Error('synthetic attach failure')) : Promise.resolve();
  transport.closeReceipt = { process_close_observed: false, reason: 'helper_exit_only' };
  const client = createAttachedClient(transport);
  await assert.rejects(client.start(), /synthetic attach failure/);
  assert.equal(transport.closeCalls, 1);
  assert.equal(client.state, 'stop_unconfirmed');
  assert.equal(client.attachedTransport, transport);
});

test('creates, names, runs, reads, lists, forks, and resumes a thread', async (t) => {
  const client = createClient();
  t.after(() => client.stop());
  await client.start();

  const created = await client.startThread({ cwd: process.cwd(), sandbox: 'read-only' });
  const threadId = created.thread.id;
  await client.setThreadName(threadId, 'Phase A fixture');

  const deltas = [];
  client.on('notification', ({ message }) => {
    if (message.method === 'item/agentMessage/delta') {
      deltas.push(message.params.delta);
    }
  });
  const turn = await client.runTurn(threadId, 'reply');
  const read = await client.readThread(threadId);
  const listed = await client.listThreads();
  const forked = await client.forkThread(threadId);
  const resumed = await client.resumeThread(threadId);

  assert.equal(turn.completed.params.turn.status, 'completed');
  assert.deepEqual(deltas, ['FAKE_OK']);
  assert.equal(read.thread.name, 'Phase A fixture');
  assert.ok(listed.data.some((thread) => thread.id === threadId));
  assert.notEqual(forked.thread.id, threadId);
  assert.equal(resumed.thread.id, threadId);
});

test('surfaces server approval requests and accepts a typed response', async (t) => {
  const client = createClient();
  t.after(() => client.stop());
  await client.start();
  const created = await client.startThread();

  client.once('serverRequest', (request) => {
    assert.equal(request.method, 'item/commandExecution/requestApproval');
    request.respond({ decision: 'decline' });
  });

  const turn = await client.runTurn(created.thread.id, 'approval', {}, { timeoutMs: 2_000 });
  assert.equal(turn.completed.params.turn.status, 'declined');
});

test('steers and interrupts an active turn', async (t) => {
  const client = createClient();
  t.after(() => client.stop());
  await client.start();
  const created = await client.startThread();
  const threadId = created.thread.id;

  const afterSequence = client.notificationSequence;
  const started = await client.startTurn(threadId, 'slow');
  const turnId = started.turn.id;
  await client.waitForNotification(
    'item/agentMessage/delta',
    (message) => message.params.turnId === turnId,
    { afterSequence, timeoutMs: 2_000 },
  );
  const steered = await client.steerTurn(threadId, turnId, 'new direction');
  await client.interruptTurn(threadId, turnId);
  const completed = await client.waitForNotification(
    'turn/completed',
    (message) => message.params.turn.id === turnId,
    { afterSequence, timeoutMs: 2_000 },
  );

  assert.equal(steered.turnId, turnId);
  assert.equal(completed.params.turn.status, 'interrupted');
});

test('rejects pending requests when the process stops', async () => {
  const client = createClient({ requestTimeoutMs: 10_000 });
  await client.start();
  const pending = client.request('test/hang');
  await client.stop();
  await assert.rejects(pending, CodexAppServerError);
});

test('stop waits for close after kill and shares a concurrent attempt', async (t) => {
  const { client, child } = stopReceiptFixture(t);
  let kills = 0;
  let closeObserved = false;
  child.kill = () => {
    kills++;
    setTimeout(() => {
      closeObserved = true;
      child.emit('close', null, 'SIGTERM');
    }, 10);
    return true;
  };
  const [first, second] = await Promise.all([client.stop(), client.stop()]);
  assert.equal(closeObserved, true);
  assert.equal(kills, 1);
  assert.deepEqual(first, second);
  assert.equal(first.process_close_observed, true);
  assert.equal(first.kill_attempted, true);
  assert.equal(client.child, null);
  assert.equal(client.state, 'stopped');
  assert.equal(child.listenerCount('close'), 1);
});

for (const behavior of ['false', 'throw', 'error-event']) {
  test(`stop retains cleanup ownership when kill returns ${behavior}`, async (t) => {
    const { client, child } = stopReceiptFixture(t);
    let kills = 0;
    let stopped = 0;
    client.on('stopped', () => stopped++);
    child.kill = () => {
      kills++;
      if (behavior === 'throw') throw new Error('synthetic kill failure');
      if (behavior === 'error-event') child.emit('error', new Error('synthetic kill failure'));
      return false;
    };
    const results = await Promise.allSettled([client.stop(), client.stop()]);
    for (const result of results) {
      assert.equal(result.status, 'rejected');
      assert.equal(result.reason.code, 'stop_close_unconfirmed');
      assert.equal(result.reason.data.process_close_observed, false);
    }
    assert.equal(stopped, 0);
    assert.equal(kills, 1);
    assert.equal(client.child, child);
    assert.equal(client.state, 'stop_unconfirmed');
    assert.equal(client._closePromise, null);
    assert.equal(child.listenerCount('close'), 1);
    await assert.rejects(client.start(), /stop_unconfirmed/);
    child.kill = () => { child.emit('close', 0, null); return true; };
    assert.equal((await client.stop()).process_close_observed, true);
    assert.equal(stopped, 1);
    assert.equal(client.child, null);
  });
}

class AttachedTransportFixture extends EventEmitter {
  constructor() {
    super();
    this.sent = [];
    this.closeReceipt = { process_close_observed: true, exit_code: 0 };
    this.closeCalls = 0;
    this.onSend = null;
  }

  send(message, { onDispatched } = {}) {
    this.sent.push(message);
    if (this.onSend) return this.onSend(message, onDispatched);
    onDispatched?.();
    if (message.method === 'initialize') {
      queueMicrotask(() => this.emit('message', { id: message.id, result: { userAgent: 'attached-fixture' } }));
    }
    return Promise.resolve();
  }

  async close() { this.closeCalls++; return this.closeReceipt; }
}

function createAttachedClient(transport, options = {}) {
  return new CodexAppServerClient({ attachedTransport: transport, requestTimeoutMs: 100, ...options });
}

test('stdin failure and synchronous close during kill settle without timer leaks', async (t) => {
  const { client, child } = stopReceiptFixture(t);
  child.stdin.end = () => { throw new Error('closed stdin'); };
  child.kill = () => { child.emit('close', null, 'SIGTERM'); return true; };
  const evidence = await client.stop();
  assert.equal(evidence.process_close_observed, true);
  assert.equal(child.listenerCount('close'), 1);
  assert.equal(client.state, 'stopped');
});

test('start and stop race never publishes ready after shutdown starts', async (t) => {
  const { client, child, send } = stopReceiptFixture(t, { ready: false });
  const states = [];
  client.on('lifecycle', ({ state }) => states.push(state));
  const starting = client.start();
  const rejectedStart = assert.rejects(starting, /not ready|closed|not running/);
  const stopping = client.stop();
  await Promise.resolve();
  send({ id: 1, result: { userAgent: 'synthetic' } });
  child.emit('close', 0, null);
  assert.equal((await stopping).process_close_observed, true);
  await rejectedStart;
  assert.equal(states.includes('ready'), false);
  assert.equal(client.state, 'stopped');
});

test('stop synchronously rejects new work and supports lifecycle reentrancy', async (t) => {
  const { client, child } = stopReceiptFixture(t);
  let reentrant;
  client.on('lifecycle', ({ state }) => {
    if (state === 'stopping') reentrant = client.stop();
  });
  const stopping = client.stop();
  assert.equal(client.isReady, false);
  assert.throws(() => client.request('test/new-work'), /not ready/);
  await assert.rejects(client.start(), /stopping/);
  child.emit('close', 0, null);
  assert.deepEqual(await stopping, await reentrant);
});
