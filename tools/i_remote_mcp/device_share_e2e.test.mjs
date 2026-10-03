// Real core + read model + OAuth/MCP, using only temporary synthetic data.
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { test } from 'node:test';
import { createICoreServer } from '../i_core/i_core_server.mjs';
import { openReadModel } from '../i_memory/i_memory_read.mjs';
import { initSession, mcpPost, obtainTokens, startTestServer } from './fixtures.mjs';
import {
  createCoreFrontendClient, createWriteback, loadFrontendCredential,
  openLedger, pairFrontendDevice,
} from './writeback.mjs';

const CHARACTER = 'synthetic-device-share-character';
const PHONE = 'synthetic-device-share-phone';
const OTHER = 'synthetic-device-share-other';
const PUBLIC_CONTENT = '咖啡：手机新消息逐字回读';

async function corePost(base, path, body, token) {
  const response = await fetch(`${base}${path}`, {
    method: 'POST',
    headers: {
      'x-core-protocol': '0.1', 'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
  return { status: response.status, body: await response.json() };
}

function message(id, sequence, content, overrides = {}) {
  return {
    sync_id: id, origin_device_id: PHONE, origin_sequence: sequence,
    character_id: CHARACTER, sender: 'user', content,
    created_at_ms: Date.UTC(2026, 9, 3) + sequence * 1000,
    message_type: 'chat', ...overrides,
  };
}

function createMemoryFixture(path) {
  const db = new DatabaseSync(path);
  try {
    db.exec(`
      CREATE TABLE memory_metadata (key TEXT PRIMARY KEY, value TEXT);
      CREATE TABLE memory_cards (
        id TEXT PRIMARY KEY, type TEXT, title TEXT, droplet_label TEXT,
        retrieval_text TEXT, status TEXT, structured_type TEXT,
        fields_json TEXT, recorded_at INTEGER, updated_at INTEGER
      );
      INSERT INTO memory_cards VALUES (
        'synthetic-unapproved-card', 'fact', '咖啡记忆', '咖啡',
        '咖啡：未经批准的记忆卡', 'active', NULL, '{}', 1, 1
      );
    `);
  } finally { db.close(); }
}

test('approved Android receive boundary reaches OAuth MCP without sharing history, private data or another device', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'i-device-share-e2e-'));
  const cleanup = [];
  try {
    const corePath = join(dir, 'core.sqlite');
    const memoryPath = join(dir, 'memory.sqlite');
    const policyPath = join(dir, 'policy.json');
    const stateDir = join(dir, 'remote-state');
    const core = createICoreServer({ databasePath: corePath, pairingCode: 'device-share-first' });
    cleanup.push(() => core.close());
    const base = `http://127.0.0.1:${(await core.listen({ port: 0 })).port}`;
    async function pair(deviceId, pairingCode) {
      core.replacePairingCode(pairingCode);
      const response = await corePost(base, '/v1/core/devices/pair', {
        device_id: deviceId, display_name: 'synthetic phone', platform: 'android',
        client_version: 'synthetic-1', capabilities: ['chat'], pairing_code: pairingCode,
      });
      assert.equal(response.status, 200);
      return response.body.device_token;
    }
    const phoneToken = await pair(PHONE, 'device-share-phone');
    const historical = message('synthetic-history', 1, '咖啡：边界前的历史');
    assert.equal((await corePost(base, '/v1/core/chat/messages', {
      device_id: PHONE, messages: [historical],
    }, phoneToken)).status, 200);

    // The boundary is core receive order, never a client-supplied timestamp.
    const inspect = new DatabaseSync(corePath, { readOnly: true });
    let boundary;
    try {
      boundary = Number(inspect.prepare('SELECT MAX(server_sequence) AS n FROM change_events').get().n) + 1;
    } finally { inspect.close(); }
    assert.ok(Number.isSafeInteger(boundary) && boundary > 1);
    createMemoryFixture(memoryPath);
    const policy = {
      schema_version: 1, primary_character_id: CHARACTER,
      messages: {
        default: 'private', shareable_character_ids: [CHARACTER],
        private_message_types: ['diary'], private_message_ids: ['synthetic-private-id'],
        private_keywords: ['PRIVATE_SYNTHETIC'],
        shareable_message_ids: [], shareable_message_hashes: {},
        auto_share_origins: ['claude_web'],
        auto_share_devices: [{ device_id: PHONE, from_server_sequence: boundary }],
      },
      memory: {
        default: 'shareable', private_types: [], private_structured_types: [],
        private_card_ids: [], private_keywords: [],
        shareable_card_ids: [], shareable_card_hashes: {},
      },
    };
    writeFileSync(policyPath, JSON.stringify(policy));
    const readModel = openReadModel({ coreDbPath: corePath, memoryDbPath: memoryPath, policyPath });
    cleanup.push(() => readModel.close());
    assert.deepEqual(readModel.recentMessages(), []);
    assert.deepEqual(readModel.searchMemory({ query: '咖啡' }), []);

    const fresh = [
      message('synthetic-public', 2, PUBLIC_CONTENT),
      message('synthetic-private-keyword', 3, '咖啡：PRIVATE_SYNTHETIC'),
      message('synthetic-other-character', 4, '咖啡：其他角色', { character_id: 'synthetic-other-character' }),
      message('synthetic-private-id', 5, '咖啡：私密 ID'),
      message('synthetic-private-type', 6, '咖啡：私密类型', { message_type: 'diary' }),
    ];
    assert.equal((await corePost(base, '/v1/core/chat/messages', {
      device_id: PHONE, messages: fresh,
    }, phoneToken)).status, 200);
    const otherToken = await pair(OTHER, 'device-share-other');
    assert.equal((await corePost(base, '/v1/core/chat/messages', {
      device_id: OTHER,
      messages: [message('synthetic-other-device', 1, '咖啡：另一设备', { origin_device_id: OTHER })],
    }, otherToken)).status, 200);
    const impersonation = await corePost(base, '/v1/core/chat/messages', {
      device_id: OTHER, messages: [message('synthetic-forgery', 7, '咖啡：伪造来源')],
    }, otherToken);
    assert.equal(impersonation.status, 403);
    assert.equal(impersonation.body.error.code, 'origin_device_mismatch');

    core.replacePairingCode('device-share-frontend');
    await pairFrontendDevice({ coreUrl: base, pairingCode: 'device-share-frontend', stateDir });
    const credential = loadFrontendCredential(stateDir);
    const ledger = openLedger(join(stateDir, 'writeback.sqlite'));
    cleanup.push(() => ledger.close());
    const writeback = createWriteback({
      ledger, coreClient: createCoreFrontendClient({ coreUrl: base, deviceToken: credential.device_token }),
    });
    const ctx = await startTestServer({ readModel, writeback, stateDir });
    cleanup.push(() => new Promise((resolveClose, reject) => ctx.server.close((error) => error ? reject(error) : resolveClose())));
    const { access_token: accessToken } = await obtainTokens(ctx.base);
    const { sessionId } = await initSession(ctx.base, accessToken);
    let requestId = 0;
    async function call(name, args) {
      const response = await mcpPost(ctx.base, accessToken, {
        jsonrpc: '2.0', id: ++requestId, method: 'tools/call', params: { name, arguments: args },
      }, { sessionId });
      assert.equal(response.status, 200);
      assert.equal(response.body.result.isError, false);
      return response.body.result.structuredContent;
    }
    const context = await call('i_context', {});
    const recall = await call('i_recall', { query: '咖啡' });
    const turn = await call('i_chat_turn', { turns: [{ role: 'user', content: '合成网页端新一轮' }] });
    assert.equal(turn.core_status, 'ok');
    assert.equal(turn.recorded.new_turns, 1);
    for (const messages of [context.recent_messages, recall.messages.items, turn.recent_messages]) {
      assert.deepEqual(messages.map((row) => [row.content, row.source]), [[PUBLIC_CONTENT, 'here_i_am']]);
    }
    assert.deepEqual(recall.memory, { count: 0, items: [] });
    assert.deepEqual(readModel.getMemoryCards({ ids: ['synthetic-unapproved-card'] }), []);
    assert.equal(readModel.stats().memory.shareable, 0);
    const verify = new DatabaseSync(corePath, { readOnly: true });
    try {
      assert.equal(verify.prepare('SELECT server_sequence FROM chat_messages WHERE sync_id = ?').get('synthetic-public').server_sequence, boundary);
      assert.equal(verify.prepare('SELECT COUNT(*) AS n FROM chat_messages WHERE sync_id = ?').get('synthetic-forgery').n, 0);
      assert.equal(verify.prepare("SELECT COUNT(*) AS n FROM chat_messages WHERE origin_device_id = 'frontend:claude_web'").get().n, 1);
    } finally { verify.close(); }
  } finally {
    const errors = [];
    for (const close of cleanup.reverse()) {
      try { await close(); } catch (error) { errors.push(error); }
    }
    // Only the synthetic directory created by this test may be removed.
    assert.equal(dirname(resolve(dir)), resolve(tmpdir()));
    assert.ok(basename(dir).startsWith('i-device-share-e2e-'));
    rmSync(dir, { recursive: true, force: true });
    if (errors.length) throw new AggregateError(errors, 'Synthetic fixture cleanup failed');
  }
});
