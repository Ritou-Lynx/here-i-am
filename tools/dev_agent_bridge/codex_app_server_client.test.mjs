import assert from 'node:assert/strict';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  CodexAppServerClient,
  CodexAppServerError,
} from './codex_app_server_client.mjs';

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
