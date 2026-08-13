import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  CompanionReplyWorker,
  ICoreWorkerClient,
  OpenAICompatibleCompanionModel,
} from './companion_worker.mjs';
import { createICoreServer } from './i_core_server.mjs';

function lease() {
  return {
    workload: 'companion_reply',
    holder_id: 'worker-a',
    lease_token: 'secret-token',
    fencing_token: 1,
  };
}

function job() {
  return {
    job_id: 'reply-job:user-1',
    context: [
      { sender: 'user', content: '我到家了' },
      { sender: 'user', content: '而且今天有点累' },
    ],
  };
}

test('OpenAI-compatible model maps core history to chat roles', async () => {
  let requestBody;
  const model = new OpenAICompatibleCompanionModel({
    baseUrl: 'https://model.example/v1/',
    apiKey: 'model-secret',
    model: 'test-model',
    systemPrompt: '你是林埃。',
    fetchImpl: async (url, options) => {
      assert.equal(url, 'https://model.example/v1/chat/completions');
      assert.equal(options.headers.authorization, 'Bearer model-secret');
      requestBody = JSON.parse(options.body);
      return new Response(JSON.stringify({
        choices: [{ message: { content: '回来就先歇一下吧。' } }],
      }), { status: 200, headers: { 'content-type': 'application/json' } });
    },
  });
  const output = await model.generate([
    { sender: 'user', content: '我到家了' },
    { sender: 'companion', content: '欢迎回来。' },
  ]);
  assert.equal(output, '回来就先歇一下吧。');
  assert.deepEqual(requestBody.messages, [
    { role: 'system', content: '你是林埃。' },
    { role: 'user', content: '我到家了' },
    { role: 'assistant', content: '欢迎回来。' },
  ]);
  assert.equal(requestBody.stream, false);
});

test('shadow mode validates generation without publishing or exposing content', async () => {
  const calls = [];
  const coreClient = {
    async acquireLease() { calls.push('acquire'); return lease(); },
    async claimReply() { calls.push('claim'); return { job: job() }; },
    async completeReply() { calls.push('complete'); throw new Error('must not publish'); },
    async completeShadow(_, completion) { calls.push(['shadow', completion]); },
    async releaseLease() { calls.push('release'); return { ok: true }; },
    async renewLease() { calls.push('renew'); return { ok: true }; },
  };
  const worker = new CompanionReplyWorker({
    coreClient,
    model: { async generate() { return '先喝点水，我们慢慢来。'; } },
    holderId: 'worker-a',
    mode: 'shadow',
    now: () => 10_000,
  });
  const result = await worker.runOnce();
  assert.equal(calls[0], 'acquire');
  assert.equal(calls[1], 'claim');
  assert.equal(calls[2][0], 'shadow');
  assert.equal(calls[2][1].replyCharacters, 11);
  assert.equal(calls[3], 'release');
  assert.equal(result.status, 'shadow_generated');
  assert.equal(result.reply_characters, 11);
  assert.equal('content' in result, false);
});

test('live mode completes the claimed job and releases the lease', async () => {
  const calls = [];
  const coreClient = {
    async acquireLease() { calls.push('acquire'); return lease(); },
    async claimReply() { calls.push('claim'); return { job: job() }; },
    async completeReply(_, completion) {
      calls.push(['complete', completion]);
      return { reply_sync_id: 'reply-1', reply_server_sequence: 42 };
    },
    async releaseLease() { calls.push('release'); return { ok: true }; },
    async renewLease() { calls.push('renew'); return { ok: true }; },
  };
  let tick = 10_000;
  const worker = new CompanionReplyWorker({
    coreClient,
    model: { async generate(context) {
      assert.equal(context.at(-1).content, '而且今天有点累');
      return '那今晚别把计划排得太满。';
    } },
    holderId: 'worker-a',
    mode: 'live',
    now: () => tick += 5,
  });
  const result = await worker.runOnce();
  assert.equal(result.status, 'completed');
  assert.equal(result.reply_server_sequence, 42);
  assert.equal(calls[2][0], 'complete');
  assert.equal(calls[2][1].jobId, 'reply-job:user-1');
  assert.equal(calls[2][1].content, '那今晚别把计划排得太满。');
  assert.equal(calls.at(-1), 'release');
});

test('idle and lease-held states do not invoke the model', async () => {
  let generated = 0;
  const idleWorker = new CompanionReplyWorker({
    coreClient: {
      async acquireLease() { return lease(); },
      async claimReply() { return { job: null }; },
      async releaseLease() {},
    },
    model: { async generate() { generated += 1; } },
    holderId: 'worker-a',
  });
  assert.equal((await idleWorker.runOnce()).status, 'idle');

  const heldWorker = new CompanionReplyWorker({
    coreClient: {
      async acquireLease() {
        const error = new Error('held');
        error.code = 'lease_held';
        throw error;
      },
    },
    model: { async generate() { generated += 1; } },
    holderId: 'worker-b',
  });
  assert.equal((await heldWorker.runOnce()).status, 'lease_held');
  assert.equal(generated, 0);
});

test('lease is released when model generation fails', async () => {
  let released = false;
  const worker = new CompanionReplyWorker({
    coreClient: {
      async acquireLease() { return lease(); },
      async claimReply() { return { job: job() }; },
      async releaseLease() { released = true; },
    },
    model: { async generate() { throw new Error('model unavailable'); } },
    holderId: 'worker-a',
  });
  await assert.rejects(() => worker.runOnce(), /model unavailable/);
  assert.equal(released, true);
});

test('shadow worker runs end to end against a real core without publishing', async (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), 'i-companion-worker-e2e-'));
  const core = createICoreServer({
    databasePath: path.join(directory, 'core.sqlite'),
    pairingCode: 'pair-once',
    workerSecret: 'worker-secret',
    companionReplyJobsEnabled: true,
  });
  const address = await core.listen({ port: 0 });
  const baseUrl = `http://127.0.0.1:${address.port}`;
  t.after(async () => {
    await core.close();
    rmSync(directory, { recursive: true, force: true });
  });
  const pairedResponse = await fetch(`${baseUrl}/v1/core/devices/pair`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      device_id: 'phone-a',
      display_name: 'Phone A',
      platform: 'test',
      client_version: '0.1',
      pairing_code: 'pair-once',
      capabilities: ['chat'],
    }),
  });
  const paired = await pairedResponse.json();
  const submitted = await fetch(`${baseUrl}/v1/core/chat/messages`, {
    method: 'POST',
    headers: {
      'x-core-protocol': '0.1',
      authorization: `Bearer ${paired.device_token}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      device_id: 'phone-a',
      request_companion_reply: true,
      messages: [{
        sync_id: 'worker-e2e-trigger',
        origin_device_id: 'phone-a',
        origin_sequence: 1,
        character_id: 'i',
        sender: 'user',
        content: '我到家了。',
        created_at_ms: 1786550400000,
        message_type: 'chat',
        asset_refs: [],
        addenda: [],
      }],
    }),
  });
  assert.equal(submitted.status, 200);

  const worker = new CompanionReplyWorker({
    coreClient: new ICoreWorkerClient({ baseUrl, workerSecret: 'worker-secret' }),
    model: {
      model: 'shadow-test',
      async generate(context) {
        assert.equal(context.at(-1).content, '我到家了。');
        return '欢迎回来。';
      },
    },
    holderId: 'shadow-worker',
    mode: 'shadow',
  });
  const result = await worker.runOnce();
  assert.equal(result.status, 'shadow_generated');
  assert.equal(
    core.store.db.prepare('SELECT COUNT(*) AS count FROM companion_reply_shadow_runs').get().count,
    1,
  );
  assert.equal(
    core.store.db.prepare("SELECT COUNT(*) AS count FROM chat_messages WHERE sender = 'companion'").get().count,
    0,
  );
});
