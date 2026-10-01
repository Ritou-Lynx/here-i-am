import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import test from 'node:test';
import { WorkbenchTextTaskSession } from './workbench_text_task_session.mjs';
import { isWorkbenchTextStopReceipt } from './workbench_text_stop_receipt.mjs';

const wait = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

class FakeClient extends EventEmitter {
  constructor({ request = null, interrupt = null } = {}) {
    super();
    this.isReady = true;
    this.notificationSequence = 0;
    this.requests = 0;
    this.interrupts = 0;
    this.#request = request;
    this.#interrupt = interrupt;
  }
  #request; #interrupt;
  async request(method, params, options) {
    this.requests++;
    assert.equal(method, 'turn/start');
    assert.deepEqual(params.environments, []);
    return this.#request ? this.#request(params, options, this) : (options.onDispatched(), { turn: { id: 'provider-turn' } });
  }
  async interruptTurn(threadId, turnId, options) {
    this.interrupts++;
    assert.equal(threadId, 'provider-thread'); assert.equal(turnId, 'provider-turn');
    return this.#interrupt ? this.#interrupt(options, this) : (options.onDispatched(), {});
  }
  emitNotification(message) {
    this.notificationSequence++;
    this.emit('notification', { sequence: this.notificationSequence, message });
  }
  waitForNotification(_method, predicate, { timeoutMs }) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.off('notification', receive); reject(new Error('timeout')); }, timeoutMs);
      const receive = entry => {
        if (!predicate(entry.message)) return;
        clearTimeout(timer); this.off('notification', receive); resolve(entry.message);
      };
      this.on('notification', receive);
    });
  }
}

function fakeBroker({ close = async () => {}, snapshot = () => ({ drained: true }) } = {}) {
  return { armed: [], revoked: 0, arm(input) { this.armed.push(input); }, revoke() { this.revoked++; }, close, snapshot };
}

function session(client, broker, closeChild = async () => true, extra = {}) {
  return new WorkbenchTextTaskSession({ client, broker, closeChild,
    providerThreadId: 'provider-thread', localSessionId: 'local-session', executionEpoch: '3c59a405-023e-447d-8ad2-8ce6fa995821', terminalTimeoutMs: 20, ...extra });
}

function terminal(client, status = 'completed', threadId = 'provider-thread', turnId = 'provider-turn') {
  client.emitNotification({ method: 'turn/completed', params: { threadId, turn: { id: turnId, status } } });
}

function delta(client, text = 'text', turnId = 'provider-turn') {
  client.emitNotification({ method: 'item/agentMessage/delta', params: { threadId: 'provider-thread', turnId, delta: text } });
}

function noListeners(client) {
  assert.equal(client.listenerCount('notification'), 0);
  assert.equal(client.listenerCount('serverRequest'), 0);
  assert.equal(client.listenerCount('protocolError'), 0);
  assert.equal(client.listenerCount('processError'), 0);
}

test('close before start issues only a no-turn receipt after actual child close and broker drain', async () => {
  const client = new FakeClient(); const broker = fakeBroker(); let closes = 0;
  const value = session(client, broker, async () => (++closes, true));
  const receipt = await value.close();
  assert.equal(receipt.outcome, 'closed_without_turn');
  assert.equal(receipt.local_turn_id, null); assert.equal(receipt.turn_id, null);
  assert.equal(closes, 1); assert.equal(broker.armed.length, 0); noListeners(client);
});

test('normal completed turn produces a branded non-cancellation receipt and retained text event', async () => {
  const client = new FakeClient(); const broker = fakeBroker(); const value = session(client, broker);
  const started = await value.startTurn('task');
  terminal(client, 'completed');
  const receipt = await value.close();
  assert.equal(receipt.local_turn_id, started.turn_id);
  assert.equal(receipt.turn_id, started.provider_turn_id);
  assert.equal(receipt.provider_terminal_status, 'completed');
  assert.equal(receipt.cancellation_confirmed, false);
  assert.equal(isWorkbenchTextStopReceipt(receipt), true);
  assert.deepEqual(value.readEvents().events.map(event => event.kind), ['turn_status']);
  noListeners(client);
});

test('matching interrupted terminal emitted before interrupt ACK confirms cancellation', async () => {
  const client = new FakeClient({ interrupt: async (options, instance) => {
    options.onDispatched(); terminal(instance, 'interrupted'); return {};
  } });
  const value = session(client, fakeBroker());
  await value.startTurn('task');
  const receipt = await value.close();
  assert.equal(receipt.provider_terminal_status, 'interrupted');
  assert.equal(receipt.cancellation_confirmed, true);
  assert.equal(client.interrupts, 1); noListeners(client);
});

test('ACK-only interrupt, wrong thread/turn, and prior completed terminal never create cancellation success', async () => {
  const ackOnlyClient = new FakeClient(); const ackOnly = session(ackOnlyClient, fakeBroker());
  const started = await ackOnly.startTurn('task');
  await ackOnly.interruptTurn(started.turn_id);
  await assert.rejects(ackOnly.close(), /provider_terminal_unconfirmed/);
  noListeners(ackOnlyClient);

  const wrongClient = new FakeClient(); const wrong = session(wrongClient, fakeBroker());
  await wrong.startTurn('task'); terminal(wrongClient, 'interrupted', 'other-thread'); terminal(wrongClient, 'interrupted', 'provider-thread', 'other-turn');
  await assert.rejects(wrong.close(), /provider_terminal_unconfirmed/);
  noListeners(wrongClient);

  const completeClient = new FakeClient(); const complete = session(completeClient, fakeBroker());
  const completeStart = await complete.startTurn('task'); terminal(completeClient, 'completed');
  assert.deepEqual(await complete.interruptTurn(completeStart.turn_id), { interrupt_dispatched: false });
  assert.equal((await complete.close()).cancellation_confirmed, false);
  noListeners(completeClient);
});

test('unknown start response and false native child close fail closed while listeners are cleaned', async () => {
  const unknownClient = new FakeClient({ request: async (_params, options) => { options.onDispatched(); return {}; } });
  const unknown = session(unknownClient, fakeBroker());
  await assert.rejects(unknown.startTurn('task'), /text_turn_start_unknown/);
  await assert.rejects(unknown.close(), /text_turn_start_unknown/);
  noListeners(unknownClient);

  const falseClient = new FakeClient(); const falseClose = session(falseClient, fakeBroker(), async () => false);
  await falseClose.startTurn('task'); terminal(falseClient, 'completed');
  await assert.rejects(falseClose.close(), /local_close_unconfirmed/);
  assert.equal(falseClient.listenerCount('notification'), 1);
});

test('concurrent start is fenced, close waits for start result, and host requests fail closed', async () => {
  let resolveStart;
  const deferred = new Promise(resolve => { resolveStart = resolve; });
  const client = new FakeClient({ request: async (_params, options) => { options.onDispatched(); return deferred; }, interrupt: async (options, instance) => { options.onDispatched(); terminal(instance, 'interrupted'); } });
  const broker = fakeBroker(); const value = session(client, broker);
  const first = value.startTurn('task');
  assert.throws(() => value.startTurn('task'), /text_session_not_fresh/);
  let replied;
  client.emit('serverRequest', { respondError(value) { replied = value; } });
  assert.deepEqual(replied, { code: -32601, message: 'Text tasks reject all host requests.' });
  resolveStart({ turn: { id: 'provider-turn' } });
  await assert.rejects(first, /text_turn_start_unknown/);
  await assert.rejects(value.close(), /text_session_host_request_rejected/);
  assert.equal(client.requests, 1); assert.ok(broker.revoked > 0); noListeners(client);
});

test('text after terminal poisons the attempt and cannot be released as a normal result', async () => {
  const client = new FakeClient(); const value = session(client, fakeBroker());
  await value.startTurn('task'); terminal(client, 'completed'); delta(client, 'late text');
  await assert.rejects(value.close(), /text_session_text_after_terminal/);
  const events = value.readEvents().events;
  assert.deepEqual(events.map(event => event.kind), ['turn_status', 'error']);
  noListeners(client);
});

test('optional fault observer reports notification faults once without changing receipt rules', async () => {
  const client = new FakeClient(); const faults = [];
  const value = session(client, fakeBroker(), async () => true, { onFault: code => faults.push(code) });
  await value.startTurn('task'); delta(client, 'x'.repeat(24001));
  assert.deepEqual(faults, ['text_session_output_limit']);
  await assert.rejects(value.close(), /text_session_output_limit/);
  noListeners(client);
});

test('broker close failure still removes every client listener in finally cleanup', async () => {
  const client = new FakeClient();
  const value = session(client, fakeBroker({ close: async () => { throw new Error('broker close failed'); } }));
  await value.startTurn('task'); terminal(client, 'completed');
  await assert.rejects(value.close());
  noListeners(client);
});

test('binding rejects a broker that cannot revoke and report drain state', () => {
  const client = new FakeClient();
  assert.throws(() => new WorkbenchTextTaskSession({
    client,
    broker: { arm() {}, close: async () => {} },
    closeChild: async () => true,
    providerThreadId: 'provider-thread',
  }), /text_session_binding_invalid/);
  noListeners(client);
});

test('late native dispatch after request timeout is retained as unknown without throwing or issuing a no-turn receipt', async () => {
  let acknowledge;
  const client = new FakeClient({ request: async (_params, options) => {
    acknowledge = options.onDispatched;
    throw new Error('request timed out before native ACK');
  } });
  const value = session(client, fakeBroker());
  await assert.rejects(value.startTurn('task'), /text_turn_start_unknown/);
  await assert.rejects(value.close(), /text_turn_start_unknown/);
  assert.doesNotThrow(acknowledge);
  assert.doesNotThrow(acknowledge); // Native duplicates cannot mutate twice.
  await assert.rejects(value.close(), /text_turn_start_unknown/);
  noListeners(client);
});

test('unconfirmed native close retains event intake and retry observes the same owner until exact closure', async () => {
  const client = new FakeClient(); let confirmed = false; let waits = 0;
  const value = session(client, fakeBroker(), async () => { waits++; return confirmed; });
  await value.startTurn('task');
  const first = value.close();
  assert.strictEqual(value.close(), first);
  await assert.rejects(first, /local_close_unconfirmed/);
  assert.equal(client.listenerCount('notification'), 1);
  terminal(client, 'interrupted'); confirmed = true;
  const receipt = await value.close();
  assert.equal(waits, 2);
  assert.equal(client.interrupts, 1);
  assert.equal(receipt.cancellation_confirmed, true);
  assert.strictEqual(await value.close(), receipt);
  noListeners(client);
});

test('IPC/process error poisons a completed session even when cleanup is later proven', async () => {
  const client = new FakeClient(); const value = session(client, fakeBroker());
  await value.startTurn('task'); terminal(client, 'completed');
  client.emit('processError', new Error('transport lost'));
  await assert.rejects(value.close(), /text_session_protocol_error/);
  noListeners(client);
});
