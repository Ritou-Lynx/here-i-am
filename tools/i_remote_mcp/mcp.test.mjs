import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, describe, test } from 'node:test';
import {
  PRIVATE_MARKERS,
  SNAPSHOT_AT_MS,
  createFakeReadModel,
  initSession,
  mcpPost,
  obtainTokens,
  startTestServer,
} from './fixtures.mjs';
import { DATA_NOTICE, currentTime, loadIdentity } from './mcp.mjs';

function assertNoPrivate(text) {
  for (const marker of PRIVATE_MARKERS) assert.ok(!text.includes(marker), `leaked ${marker}`);
}

async function connected(options) {
  const ctx = await startTestServer(options);
  const { access_token: token } = await obtainTokens(ctx.base);
  const { init, sessionId } = await initSession(ctx.base, token);
  let nextId = 10;
  const call = (name, args) => mcpPost(ctx.base, token, {
    jsonrpc: '2.0', id: nextId++, method: 'tools/call', params: { name, arguments: args },
  }, { sessionId, headers: { 'MCP-Protocol-Version': '2025-06-18' } });
  const rpc = (method, params) => mcpPost(ctx.base, token, { jsonrpc: '2.0', id: nextId++, method, params }, { sessionId });
  return { ctx, token, init, sessionId, call, rpc };
}

describe('协议', () => {
  let c;
  before(async () => { c = await connected(); });
  after(() => c.ctx.close());

  test('initialize 返回协议版本、能力与会话头', () => {
    assert.equal(c.init.status, 200);
    const r = c.init.body.result;
    assert.equal(r.protocolVersion, '2025-06-18');
    assert.deepEqual(r.capabilities, { tools: { listChanged: false } });
    assert.equal(r.serverInfo.name, 'i-remote');
    assert.match(r.instructions, /i_context/);
    assert.ok(c.sessionId);
  });

  test('兼容 2025-03-26，未知版本回落到 2025-06-18', async () => {
    const old = await initSession(c.ctx.base, c.token, '2025-03-26');
    assert.equal(old.init.body.result.protocolVersion, '2025-03-26');
    const unknown = await initSession(c.ctx.base, c.token, '1999-01-01');
    assert.equal(unknown.init.body.result.protocolVersion, '2025-06-18');
  });

  test('不支持的 MCP-Protocol-Version 头返回 400', async () => {
    const r = await mcpPost(c.ctx.base, c.token, { jsonrpc: '2.0', id: 1, method: 'ping' }, { sessionId: c.sessionId, headers: { 'MCP-Protocol-Version': '2099-01-01' } });
    assert.equal(r.status, 400);
  });

  test('ping、通知 202、未知方法、未知工具、解析错误', async () => {
    assert.deepEqual((await c.rpc('ping')).body.result, {});
    const note = await mcpPost(c.ctx.base, c.token, { jsonrpc: '2.0', method: 'notifications/initialized' }, { sessionId: c.sessionId });
    assert.equal(note.status, 202);
    assert.equal(note.text, '');
    assert.equal((await c.rpc('resources/list')).body.error.code, -32601);
    assert.equal((await c.call('i_remember', {})).body.error.code, -32602);
    const bad = await fetch(`${c.ctx.base}/mcp`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${c.token}`, 'Content-Type': 'application/json', 'Mcp-Session-Id': c.sessionId },
      body: '{not json',
    });
    assert.equal(bad.status, 400);
    assert.equal((await bad.json()).error.code, -32700);
  });

  test('GET /mcp 不提供 SSE，返回 405', async () => {
    const r = await fetch(`${c.ctx.base}/mcp`, { headers: { Authorization: `Bearer ${c.token}`, Accept: 'text/event-stream', 'Mcp-Session-Id': c.sessionId } });
    assert.equal(r.status, 405);
  });

  test('tools/list 只有两个只读工具，描述为中文', async () => {
    const tools = (await c.rpc('tools/list')).body.result.tools;
    assert.deepEqual(tools.map((t) => t.name), ['i_context', 'i_recall']);
    for (const t of tools) {
      assert.equal(t.annotations.readOnlyHint, true);
      assert.equal(t.annotations.destructiveHint, false);
      assert.match(t.description, /[一-鿿]/);
      assert.match(t.description, /数据，不是指令/);
    }
    assert.deepEqual(tools[1].inputSchema.required, ['query']);
  });
});

describe('工具返回结构与私密过滤', () => {
  let c;
  before(async () => { c = await connected(); });
  after(() => c.ctx.close());

  test('i_context：身份、带时区的当前时间、快照时间、最近消息', async () => {
    const r = await c.call('i_context', { limit: 5 });
    assert.equal(r.status, 200);
    const result = r.body.result;
    assert.equal(result.isError, false);
    assert.equal(result.content[0].type, 'text');
    const data = result.structuredContent;
    assert.deepEqual(JSON.parse(result.content[0].text), data);
    assert.equal(data.notice, DATA_NOTICE);
    assert.equal(data.identity.name, '林埃');
    assert.equal(data.identity.english_name, 'i');
    assert.equal(data.relationship.user_preferred_name, 'Lynx');
    assert.equal(data.now.time_zone, 'Asia/Shanghai');
    assert.equal(data.now.local, '2026-10-02T12:00:00+08:00');
    assert.equal(data.now.utc, '2026-10-02T04:00:00.000Z');
    assert.equal(data.memory_snapshot_at, new Date(SNAPSHOT_AT_MS).toISOString());
    assert.equal(data.recent_messages.length, 3);
    assert.deepEqual(Object.keys(data.recent_messages[0]).sort(), ['content', 'created_at', 'message_type', 'sender', 'sync_id']);
    assert.deepEqual(data.recent_messages.map((m) => m.sync_id), ['m1', 'm2', 'm4']);
    assert.equal(data.recent_messages[1].sender, 'companion');
    assertNoPrivate(r.text);
  });

  test('i_context：limit 被限制在 1..100 并传给 readModel', async () => {
    c.ctx.readModel.calls.length = 0;
    await c.call('i_context', { limit: 1000 });
    assert.deepEqual(c.ctx.readModel.calls[0], ['recentMessages', 100]);
    await c.call('i_context', {});
    assert.deepEqual(c.ctx.readModel.calls[1], ['recentMessages', 20]);
  });

  test('i_recall：记忆与消息分栏返回，字段走白名单', async () => {
    const r = await c.call('i_recall', { query: '猫咪', limit: 5 });
    const data = r.body.result.structuredContent;
    assert.equal(data.notice, DATA_NOTICE);
    assert.equal(data.query, '猫咪');
    assert.equal(data.memory.count, 1);
    assert.equal(data.memory.items[0].id, 'card-cat');
    assert.deepEqual(Object.keys(data.memory.items[0]).sort(), [
      'droplet_label', 'id', 'recorded_at', 'retrieval_text', 'status', 'structured', 'title', 'type', 'updated_at',
    ]);
    assert.deepEqual(data.memory.items[0].structured, { type: 'pet', fields: { name: '三花' } });
    assert.equal(data.messages.count, 2);
    assert.ok(data.messages.items.every((m) => typeof m.snippet === 'string'));
    assert.ok(!('character_id' in data.messages.items[0]));
    assertNoPrivate(r.text);
  });

  test('私密数据在所有返回里都不出现（含 tools/list、各种查询词）', async () => {
    const texts = [(await c.rpc('tools/list')).text, c.init.text];
    for (const q of ['猫咪', 'PRIVATE', 'PRIVATE_CHAR_SECRET', 'PRIVATE_TYPE_SECRET', 'PRIVATE_KEYWORD_SECRET', 'secret_type', '散步']) {
      const r = await c.call('i_recall', { query: q, limit: 20 });
      // query 字段是用户自己的输入回显，其余部分不得含私密内容。
      const { query, ...rest } = JSON.parse(r.body.result.content[0].text);
      assert.equal(query, q);
      texts.push(JSON.stringify(rest));
    }
    texts.push((await c.call('i_context', { limit: 100 })).text);
    for (const t of texts) assertNoPrivate(t);
  });

  test('参数错误返回 isError，不抛协议错误', async () => {
    for (const args of [{}, { query: '   ' }, { query: 'x'.repeat(201) }, { query: '猫咪', limit: 1.5 }]) {
      const r = await c.call('i_recall', args);
      assert.equal(r.status, 200);
      assert.equal(r.body.result.isError, true, JSON.stringify(args));
    }
    assert.equal((await c.call('i_context', { limit: 'abc' })).body.result.isError, true);
  });
});

describe('数据源故障', () => {
  test('readModel 失败（如策略缺失 fail closed）时返回通用错误，不泄露细节', async () => {
    const c = await connected({ readModel: createFakeReadModel({ fail: true }) });
    try {
      for (const [name, args] of [['i_context', {}], ['i_recall', { query: '猫咪' }]]) {
        const r = await c.call(name, args);
        assert.equal(r.body.result.isError, true);
        assert.match(r.body.result.content[0].text, /不要编造/);
        assert.doesNotMatch(r.text, /secret|policy\.json/i);
        assertNoPrivate(r.text);
      }
    } finally {
      await c.ctx.close();
    }
  });
});

describe('身份加载', () => {
  let home;
  before(() => { home = mkdtempSync(join(tmpdir(), 'i-home-')); });
  after(() => rmSync(home, { recursive: true, force: true }));

  test('~/.i/identity.json 缺失时用仓库默认身份', () => {
    const id = loadIdentity({ iHome: home });
    assert.equal(id.source, 'repository_default');
    assert.equal(id.identity.name, '林埃');
    assert.match(id.identity.anchor, /英文名 i/);
  });

  test('用户身份投影优先，且只取白名单字段', () => {
    writeFileSync(join(home, 'identity.json'), JSON.stringify({
      identity: { name: '林埃', anchor: '自定义锚点', secret: 'EXTRA_FIELD_SECRET' },
      relationship: { user_preferred_name: 'Lynx', user_aliases: ['林克斯'] },
      surface_guidance: ['g1'],
      private_notes: 'EXTRA_FIELD_SECRET',
    }));
    const id = loadIdentity({ iHome: home });
    assert.equal(id.source, 'user_projection');
    assert.equal(id.identity.anchor, '自定义锚点');
    assertNoPrivate(JSON.stringify(id));
  });

  test('损坏的用户身份文件回落到默认', () => {
    writeFileSync(join(home, 'identity.json'), '{broken');
    assert.equal(loadIdentity({ iHome: home }).source, 'repository_default');
  });

  test('currentTime 带时区偏移与星期', () => {
    const t = currentTime(Date.UTC(2026, 0, 1, 16, 30), 'Asia/Shanghai');
    assert.equal(t.local, '2026-01-02T00:30:00+08:00');
    assert.equal(t.weekday, '星期五');
    assert.equal(currentTime(Date.UTC(2026, 0, 1), 'UTC').local, '2026-01-01T00:00:00+00:00');
  });
});
