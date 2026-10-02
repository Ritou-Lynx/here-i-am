// B1 × B2 集成：真实 i_memory 读取层（合成 V3 库 + 合成 i_core 库）接到远程 MCP 上。
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { after, before, describe, test } from 'node:test';
import { runImport } from '../i_memory/import_v3_memory.mjs';
import { openReadModel } from '../i_memory/i_memory_read.mjs';
import { initSession, mcpPost, obtainTokens, startTestServer } from './fixtures.mjs';
import { createLazyReadModel } from './server.mjs';

const LIN = 'char-lin';
const OTHER = 'char-private';
const LEAKS = ['别的角色的悄悄话', '手冲私密', '秘密行程', '书店会员', 'card-secret', 'card-keyword'];

function createV3(file) {
  const db = new DatabaseSync(file);
  db.exec(`
    CREATE TABLE memory_cards (
      id TEXT PRIMARY KEY, memory_scope TEXT NOT NULL DEFAULT 'user_truth', type TEXT NOT NULL,
      title TEXT NOT NULL, droplet_label TEXT NOT NULL, presentation_module TEXT NOT NULL DEFAULT '[]',
      retrieval_text TEXT NOT NULL, valence REAL NOT NULL DEFAULT 0, arousal REAL NOT NULL DEFAULT 0,
      status TEXT, needs_follow_up TEXT, schema_version INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
    );
    CREATE TABLE memory_card_sources (
      card_id TEXT PRIMARY KEY, raw_input TEXT NOT NULL, recorded_at INTEGER NOT NULL,
      recorded_place TEXT, source_ref TEXT, source_sync_id TEXT, source_kind TEXT NOT NULL,
      schema_version INTEGER NOT NULL DEFAULT 1
    );
    CREATE TABLE memory_card_structured_fields (
      card_id TEXT PRIMARY KEY, structured_fields_type TEXT NOT NULL, fields_json TEXT NOT NULL,
      user_corrected INTEGER NOT NULL DEFAULT 0, schema_version INTEGER NOT NULL DEFAULT 1,
      generated_by_version TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
    );
  `);
  const cards = [
    ['card-cat', 'fact', '三花猫咪', '猫咪', '用户养了一只三花猫咪，叫团子。'],
    ['card-secret', 'fact', '书店会员', '书店', '在街角书店办了会员卡。'],
    ['card-keyword', 'fact', '旅行计划', '旅行', '想去海边旅行，这是秘密行程。'],
  ];
  const insert = db.prepare(`INSERT INTO memory_cards (id, type, title, droplet_label, retrieval_text, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)`);
  cards.forEach(([id, type, title, label, text], index) => {
    const at = 1_790_000_000_000 + index * 60_000;
    insert.run(id, type, title, label, text, at, at + 1000);
    db.prepare(`INSERT INTO memory_card_sources (card_id, raw_input, recorded_at, source_kind) VALUES (?, ?, ?, 'record_button')`)
      .run(id, `原始输入 ${id}`, at - 5000);
  });
  db.close();
}

function createCore(file) {
  const db = new DatabaseSync(file);
  db.exec(`
    CREATE TABLE chat_messages (
      sync_id TEXT PRIMARY KEY, origin_device_id TEXT NOT NULL, origin_sequence INTEGER NOT NULL,
      character_id TEXT NOT NULL, sender TEXT NOT NULL, content TEXT NOT NULL,
      created_at_ms INTEGER NOT NULL, message_type TEXT NOT NULL, asset_refs_json TEXT NOT NULL,
      addenda_json TEXT NOT NULL, canonical_digest TEXT NOT NULL, server_sequence INTEGER NOT NULL UNIQUE
    );
  `);
  const rows = [
    [LIN, 'user', '团子今天又把猫咪玩具藏起来了'],
    [LIN, 'companion', '团子真是只聪明的猫咪'],
    [OTHER, 'user', '别的角色的悄悄话，也提到猫咪'],
    [LIN, 'user', '手冲私密的一句话，猫咪也在'],
  ];
  const insert = db.prepare(`INSERT INTO chat_messages VALUES (?, 'phone', ?, ?, ?, ?, ?, 'chat', '[]', '[]', 'd', ?)`);
  rows.forEach(([character, sender, content], index) => {
    insert.run(`msg-${index}`, index, character, sender, content, 1_790_000_000_000 + index * 1000, index + 1);
  });
  db.close();
}

describe('B1 × B2 集成', () => {
  let dir;
  let paths;
  let ctx;
  let token;
  let sessionId;
  let nextId = 100;

  const call = (name, args) => mcpPost(ctx.base, token, {
    jsonrpc: '2.0', id: nextId++, method: 'tools/call', params: { name, arguments: args },
  }, { sessionId, headers: { 'MCP-Protocol-Version': '2025-06-18' } });

  before(async () => {
    dir = mkdtempSync(join(tmpdir(), 'i-b1b2-'));
    paths = {
      v3: join(dir, 'v3.sqlite'),
      coreDbPath: join(dir, 'core.sqlite'),
      memoryDbPath: join(dir, 'i-memory.sqlite'),
      policyPath: join(dir, 'policy.json'),
    };
    createV3(paths.v3);
    createCore(paths.coreDbPath);
    runImport({ source: paths.v3, out: paths.memoryDbPath, apply: true });
    writeFileSync(paths.policyPath, JSON.stringify({
      schema_version: 1,
      primary_character_id: LIN,
      messages: { default: 'private', shareable_character_ids: [LIN], private_message_types: [], private_keywords: ['手冲私密'] },
      memory: {
        default: 'shareable', private_types: [], private_structured_types: [],
        private_card_ids: ['card-secret'], private_keywords: ['秘密'],
      },
    }));
    const readModel = openReadModel(paths);
    ctx = await startTestServer({ readModel });
    ({ access_token: token } = await obtainTokens(ctx.base));
    ({ sessionId } = await initSession(ctx.base, token));
  });

  after(async () => {
    ctx.readModel.close();
    await ctx.close();
    rmSync(dir, { recursive: true, force: true });
  });

  test('i_context 返回真实可分享消息，私密内容不出站', async () => {
    const res = await call('i_context', { limit: 10 });
    assert.equal(res.status, 200);
    const payload = res.body.result.structuredContent;
    assert.deepEqual(payload.recent_messages.map((m) => m.content), [
      '团子今天又把猫咪玩具藏起来了',
      '团子真是只聪明的猫咪',
    ]);
    assert.ok(payload.memory_snapshot_at);
    for (const leak of LEAKS) assert.ok(!res.text.includes(leak), `leaked ${leak}`);
  });

  test('i_recall 同时检索记忆与消息，私密卡与私密消息都不出现', async () => {
    const res = await call('i_recall', { query: '猫咪' });
    assert.equal(res.status, 200);
    const payload = res.body.result.structuredContent;
    assert.deepEqual(payload.memory.items.map((c) => c.title), ['三花猫咪']);
    assert.equal(payload.messages.count, 2);
    for (const leak of LEAKS) assert.ok(!res.text.includes(leak), `leaked ${leak}`);
    const travel = await call('i_recall', { query: '旅行' });
    assert.equal(travel.body.result.structuredContent.memory.count, 0);
  });

  test('createLazyReadModel 能加载真实读取层', async () => {
    const factory = createLazyReadModel(paths);
    try {
      const model = await factory();
      assert.equal(model.policySummary().primaryCharacterId, LIN);
      assert.equal(model.recentMessages().length, 2);
    } finally {
      factory.close();
    }
  });
});
