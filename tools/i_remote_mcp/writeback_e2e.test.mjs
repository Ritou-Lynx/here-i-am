// B3 端到端：真实 i_core 服务与存储 + 真实 i_memory 读取层 + 远程 MCP + OAuth（全部合成数据）。
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { after, before, describe, test } from 'node:test';
import { createICoreServer } from '../i_core/i_core_server.mjs';
import { hashMessageContent, openReadModel } from '../i_memory/i_memory_read.mjs';
import {
  PUBLIC_URL,
  REDIRECT_URI,
  initSession,
  mcpPost,
  obtainTokens,
  pkcePair,
  postToken,
  registerClient,
  startTestServer,
  submitPassphrase,
} from './fixtures.mjs';
import { createPhoneFeedApp } from './server.mjs';
import {
  createCoreFrontendClient,
  createWriteback,
  issuePhoneToken,
  loadFrontendCredential,
  loadPhoneTokenHash,
  openLedger,
  pairFrontendDevice,
} from './writeback.mjs';

const LIN = 'char-lin-e2e';
const PAIRING = '246813';

async function coreJson(base, path, { method = 'GET', token, body } = {}) {
  const res = await fetch(`${base}${path}`, {
    method,
    headers: {
      'x-core-protocol': '0.1',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  return { status: res.status, body: await res.json() };
}

describe('B3 写回端到端', () => {
  let dir;
  let core;
  let coreBase;
  let readModel;
  let writeback;
  let ctx;
  let token;
  let sessionId;
  let phone;
  let phoneBase;
  let phoneToken;
  let phoneDeviceToken;
  const policyPath = () => join(dir, 'policy.json');

  async function call(name, args, id = Math.floor(Math.random() * 1e6)) {
    const r = await mcpPost(ctx.base, token, { jsonrpc: '2.0', id, method: 'tools/call', params: { name, arguments: args } }, { sessionId });
    assert.equal(r.status, 200);
    return r.body.result;
  }

  before(async () => {
    dir = mkdtempSync(join(tmpdir(), 'i-b3-e2e-'));
    const coreDb = join(dir, 'core.sqlite');
    core = createICoreServer({ databasePath: coreDb, pairingCode: PAIRING });
    coreBase = `http://127.0.0.1:${(await core.listen({ port: 0 })).port}`;

    // 手机设备：先配对，提交一条手机端消息（经哈希放行）。
    const phonePair = await coreJson(coreBase, '/v1/core/devices/pair', {
      method: 'POST',
      body: { device_id: 'phone-e2e', display_name: 'phone', platform: 'android', client_version: '1', pairing_code: PAIRING, capabilities: ['chat'] },
    });
    phoneDeviceToken = phonePair.body.device_token;
    await coreJson(coreBase, '/v1/core/chat/messages', {
      method: 'POST', token: phoneDeviceToken,
      body: { device_id: 'phone-e2e', messages: [
        { sync_id: 'phone-1', origin_device_id: 'phone-e2e', origin_sequence: 1, character_id: LIN, sender: 'user', content: '手机上说过团子挑食', created_at_ms: Date.UTC(2026, 9, 1), message_type: 'chat' },
        { sync_id: 'phone-2', origin_device_id: 'phone-e2e', origin_sequence: 2, character_id: LIN, sender: 'user', content: '这句没有放行，不能出站', created_at_ms: Date.UTC(2026, 9, 1, 0, 1), message_type: 'chat' },
      ] },
    });

    // 网页端前端身份：用新的一次性配对码配对，令牌落在 i_remote_mcp 的 .state。
    core.replacePairingCode('135792');
    const stateDir = join(dir, 'remote-state');
    await pairFrontendDevice({ coreUrl: coreBase, pairingCode: '135792', stateDir });
    const credential = loadFrontendCredential(stateDir);

    writeFileSync(policyPath(), JSON.stringify({
      schema_version: 1,
      primary_character_id: LIN,
      messages: {
        default: 'private',
        shareable_character_ids: [LIN],
        private_message_types: [],
        private_keywords: ['悄悄话'],
        shareable_message_ids: ['phone-1'],
        shareable_message_hashes: { 'phone-1': hashMessageContent('手机上说过团子挑食') },
        auto_share_origins: ['claude_web'],
      },
      memory: { default: 'shareable', private_types: [], private_structured_types: [], private_card_ids: [], private_keywords: [] },
    }));
    readModel = openReadModel({ coreDbPath: coreDb, memoryDbPath: join(dir, 'absent.sqlite'), policyPath: policyPath() });
    writeback = createWriteback({
      ledger: openLedger(join(stateDir, 'writeback.sqlite')),
      coreClient: createCoreFrontendClient({ coreUrl: coreBase, deviceToken: credential.device_token }),
    });
    ctx = await startTestServer({ readModel, writeback, stateDir });
    ({ access_token: token } = await obtainTokens(ctx.base));
    ({ sessionId } = await initSession(ctx.base, token));

    phoneToken = issuePhoneToken(stateDir);
    phone = createPhoneFeedApp({ writeback, tokenHash: loadPhoneTokenHash(stateDir) }).server;
    await new Promise((r) => phone.listen(0, '127.0.0.1', r));
    phoneBase = `http://127.0.0.1:${phone.address().port}`;
  });

  after(async () => {
    await new Promise((r) => phone.close(r));
    await new Promise((r) => ctx.server.close(r));
    writeback.close();
    readModel.close();
    await core.close();
    rmSync(dir, { recursive: true, force: true });
  });

  test('OAuth 签发 i.read + i.write，元数据与 tools/list 暴露写工具且注解为非只读', async () => {
    const meta = await (await fetch(`${ctx.base}/.well-known/oauth-protected-resource`)).json();
    assert.deepEqual(meta.scopes_supported, ['i.read', 'i.write']);
    const list = (await mcpPost(ctx.base, token, { jsonrpc: '2.0', id: 2, method: 'tools/list' }, { sessionId })).body.result.tools;
    assert.deepEqual(list.map((t) => t.name), ['i_context', 'i_recall', 'i_chat_turn', 'i_remember']);
    for (const t of list.filter((x) => x.name.startsWith('i_chat') || x.name === 'i_remember')) {
      assert.equal(t.annotations.readOnlyHint, false);
      assert.equal(t.requiredScope, undefined);
    }
  });

  test('三轮对话写进真实 i_core，手机设备能从 change feed 看到并带来源', async () => {
    const first = (await call('i_chat_turn', { turns: [{ role: 'user', content: '网页端：团子今天吃了新猫粮' }] })).structuredContent;
    assert.equal(first.core_status, 'ok');
    assert.equal(first.recorded.new_turns, 1);
    // 返回最新上下文：手机端已放行的那条在，没放行的不在，本线程自己的不重复返回。
    assert.deepEqual(first.recent_messages.map((m) => [m.content, m.source]), [['手机上说过团子挑食', 'here_i_am']]);
    const thread = first.thread_id;
    await call('i_chat_turn', { thread_id: thread, turns: [
      { role: 'assistant', content: '新猫粮它爱吃吗？' },
      { role: 'user', content: '很爱吃，悄悄话：别告诉别人' },
    ] });
    // 漏调了一轮，下一次连同漏掉的一起提交，并且重复带上了已写过的一条。
    const third = (await call('i_chat_turn', { thread_id: thread, turns: [
      { role: 'user', content: '很爱吃，悄悄话：别告诉别人' },
      { role: 'assistant', content: '好，我不说。' },
      { role: 'user', content: '明天带它去体检' },
      { role: 'assistant', content: '记得带上疫苗本。' },
      { role: 'user', content: '好的' },
    ] })).structuredContent;
    assert.deepEqual(third.recorded, { new_turns: 4, backfilled_turns: 3, duplicate_turns_skipped: 1, waiting_for_retry: 0 });
    // 补记的轮次在 i_core 里带标记，本次刚发生的那条不带。
    const marked = (await coreJson(coreBase, '/v1/core/changes', { token: phoneDeviceToken })).body.events
      .map((e) => e.payload).filter((p) => p.origin_device_id === 'frontend:claude_web').slice(-4);
    assert.deepEqual(marked.map((p) => p.addenda.length), [1, 1, 1, 0]);
    // 新流程：回复写完后 phase=end，只回报写入结果。
    const end = (await call('i_chat_turn', { thread_id: thread, phase: 'end', turns: [{ role: 'assistant', content: '好的，晚安。' }] })).structuredContent;
    assert.deepEqual(Object.keys(end).sort(), ['core_status', 'last_recorded', 'next', 'recorded', 'thread_id']);
    assert.equal(end.last_recorded.role, 'assistant');
    assert.equal(end.recorded.backfilled_turns, 0);

    const feed = await coreJson(coreBase, '/v1/core/changes', { token: phoneDeviceToken });
    const web = feed.body.events.map((e) => e.payload).filter((p) => p.origin_device_id === 'frontend:claude_web');
    assert.deepEqual(web.map((p) => `${p.sender}:${p.content}`), [
      'user:网页端：团子今天吃了新猫粮',
      'companion:新猫粮它爱吃吗？',
      'user:很爱吃，悄悄话：别告诉别人',
      'companion:好，我不说。',
      'user:明天带它去体检',
      'companion:记得带上疫苗本。',
      'user:好的',
      'companion:好的，晚安。',
    ]);
    assert.ok(web.every((p) => p.character_id === LIN && p.message_type === 'chat'));

    // 读取层：claude_web 自动出站，但私密关键词仍然拦截；新对话（另一线程）能读到。
    const recall = (await call('i_recall', { query: '团子' })).structuredContent;
    const contents = recall.messages.items.map((m) => m.content);
    assert.ok(contents.includes('网页端：团子今天吃了新猫粮'));
    assert.ok(contents.includes('手机上说过团子挑食'));
    const other = (await call('i_chat_turn', { turns: [{ role: 'user', content: '换了个新对话' }], limit: 20 })).structuredContent;
    const otherContents = other.recent_messages.map((m) => m.content);
    assert.ok(otherContents.includes('记得带上疫苗本。'));
    assert.ok(!otherContents.some((c) => c.includes('悄悄话')));
    assert.ok(!otherContents.includes('这句没有放行，不能出站'));
    assert.ok(!otherContents.includes('换了个新对话'));
    assert.ok(other.recent_messages.filter((m) => m.content === '记得带上疫苗本。').every((m) => m.source === 'claude_web'));
  });

  test('前端令牌不能读 change feed', async () => {
    const credential = loadFrontendCredential(join(dir, 'remote-state'));
    const denied = await coreJson(coreBase, '/v1/core/changes', { token: credential.device_token });
    assert.equal(denied.status, 403);
  });

  test('i_remember → 手机拉取 → 回执；删除后正文从账本和拉取结果消失', async () => {
    const added = (await call('i_remember', { text: '团子对鸡肉过敏' })).structuredContent;
    assert.equal(added.note.phone_status, 'waiting_for_phone');
    const ctxNotes = (await call('i_context', {})).structuredContent.remembered_notes;
    assert.deepEqual(ctxNotes.map((n) => n.text), ['团子对鸡肉过敏']);

    const unauthorized = await fetch(`${phoneBase}/v1/remember/changes`);
    assert.equal(unauthorized.status, 401);
    const auth = { authorization: `Bearer ${phoneToken}` };
    const changes = await (await fetch(`${phoneBase}/v1/remember/changes?after=0`, { headers: auth })).json();
    assert.deepEqual(changes.notes.map((n) => [n.op, n.text, n.source]), [['upsert', '团子对鸡肉过敏', 'claude_web']]);
    const ack = await fetch(`${phoneBase}/v1/remember/ack`, {
      method: 'POST', headers: { ...auth, 'content-type': 'application/json' },
      body: JSON.stringify({ note_id: added.note.note_id, revision: 1, card_id: 'card-from-phone' }),
    });
    assert.equal(ack.status, 200);
    const listed = (await call('i_remember', { action: 'list' })).structuredContent.notes;
    assert.equal(listed[0].phone_status, 'on_phone');

    await call('i_remember', { action: 'delete', note_id: added.note.note_id });
    const after = await (await fetch(`${phoneBase}/v1/remember/changes?after=${changes.next_after}`, { headers: auth })).json();
    assert.deepEqual(after.notes.map((n) => [n.op, n.text]), [['delete', null]]);
    const ledger = new DatabaseSync(join(dir, 'remote-state', 'writeback.sqlite'), { readOnly: true });
    try {
      const dump = JSON.stringify(ledger.prepare('SELECT * FROM notes').all());
      assert.ok(!dump.includes('鸡肉'));
    } finally { ledger.close(); }
  });

  test('只有 i.read 的旧令牌调用写工具会被要求重新授权，读工具照常', async () => {
    // 模拟启用写回之前签发的令牌。
    const { body: client } = await registerClient(ctx.base);
    const { verifier, challenge } = pkcePair();
    const res = await submitPassphrase(ctx.base, new URLSearchParams({
      response_type: 'code', client_id: client.client_id, redirect_uri: REDIRECT_URI,
      code_challenge: challenge, code_challenge_method: 'S256', state: 's', resource: `${PUBLIC_URL}/mcp`,
    }));
    const code = new URL(res.headers.get('location')).searchParams.get('code');
    const issued = await postToken(ctx.base, {
      grant_type: 'authorization_code', code, client_id: client.client_id,
      redirect_uri: REDIRECT_URI, code_verifier: verifier,
    });
    assert.equal(issued.body.scope, 'i.read i.write');
    for (const record of Object.values(ctx.oauth.store.state.access_tokens)) {
      if (record.client_id === client.client_id) record.scope = 'i.read';
    }
    const legacy = issued.body.access_token;
    const { sessionId: legacySession } = await initSession(ctx.base, legacy);
    const write = await mcpPost(ctx.base, legacy, { jsonrpc: '2.0', id: 9, method: 'tools/call', params: { name: 'i_chat_turn', arguments: { turns: [{ role: 'user', content: '不应写入' }] } } }, { sessionId: legacySession });
    assert.equal(write.body.result.isError, true);
    assert.match(write.body.result.content[0].text, /重新授权/);
    const read = await mcpPost(ctx.base, legacy, { jsonrpc: '2.0', id: 10, method: 'tools/call', params: { name: 'i_context', arguments: {} } }, { sessionId: legacySession });
    assert.equal(read.body.result.isError, false);
    const feed = await coreJson(coreBase, '/v1/core/changes', { token: phoneDeviceToken });
    assert.ok(!feed.body.events.some((e) => e.payload.content === '不应写入'));
  });

  test('i_core 停机时本机账本暂存，恢复后下一次调用补交', async () => {
    await core.close();
    const down = (await call('i_chat_turn', { turns: [{ role: 'user', content: '核心停机时说的话' }] })).structuredContent;
    assert.equal(down.core_status, 'unavailable');
    assert.equal(down.recorded.waiting_for_retry, 1);
    assert.match(down.core_hint, /自动补交/);
    core = createICoreServer({ databasePath: join(dir, 'core.sqlite') });
    const port = Number(new URL(coreBase).port);
    await core.listen({ port });
    const up = (await call('i_chat_turn', { thread_id: down.thread_id, turns: [
      { role: 'assistant', content: '我先记在本机了' },
      { role: 'user', content: '核心恢复了' },
    ] })).structuredContent;
    assert.equal(up.core_status, 'ok');
    assert.equal(up.recorded.waiting_for_retry, 0);
    const feed = await coreJson(coreBase, '/v1/core/changes?limit=500', { token: phoneDeviceToken });
    const tail = feed.body.events.map((e) => e.payload.content).slice(-3);
    assert.deepEqual(tail, ['核心停机时说的话', '我先记在本机了', '核心恢复了']);
  });
  test('explicit MCP phases preserve new repeated turns and only deduplicate exact tail retries', async () => {
    const first = (await call('i_chat_turn', { phase: 'start',
      turns: [{ role: 'user', content: 'phase回归：嗯' }] })).structuredContent;
    const thread_id = first.thread_id;
    await call('i_chat_turn', { phase: 'end', thread_id,
      turns: [{ role: 'assistant', content: 'phase回归：我在听' }] });
    const next = (await call('i_chat_turn', { phase: 'start', thread_id,
      turns: [{ role: 'user', content: 'phase回归：嗯' }] })).structuredContent;
    assert.equal(next.recorded.new_turns, 1, 'MCP must forward phase instead of legacy all-history dedup');
    const end = (await call('i_chat_turn', { phase: 'end', thread_id,
      turns: [{ role: 'assistant', content: 'phase回归：我在听' }] })).structuredContent;
    assert.equal(end.recorded.new_turns, 1);
    const repeated = (await call('i_chat_turn', { phase: 'end', thread_id,
      turns: [{ role: 'assistant', content: 'phase回归：我在听' }] })).structuredContent;
    assert.equal(repeated.recorded.new_turns, 0);
    assert.equal(repeated.recent_messages, undefined);
    const feed = await coreJson(coreBase, '/v1/core/changes?limit=500', { token: phoneDeviceToken });
    assert.deepEqual(feed.body.events.map((e) => e.payload.content)
      .filter((content) => content.startsWith('phase回归：')),
    ['phase回归：嗯', 'phase回归：我在听', 'phase回归：嗯', 'phase回归：我在听']);
  });


  test('omitted MCP phase defaults to start when the user repeats after a complete round', async () => {
    const first = (await call('i_chat_turn', {
      turns: [{ role: 'user', content: 'default phase回归：嗯' }] })).structuredContent;
    const thread_id = first.thread_id;
    await call('i_chat_turn', { phase: 'end', thread_id,
      turns: [{ role: 'assistant', content: 'default phase回归：听见了' }] });
    const next = (await call('i_chat_turn', { thread_id,
      turns: [{ role: 'user', content: 'default phase回归：嗯' }] })).structuredContent;
    assert.equal(next.recorded.new_turns, 1);
    assert.equal(next.last_recorded.role, 'user');
    const retry = (await call('i_chat_turn', { thread_id,
      turns: [{ role: 'user', content: 'default phase回归：嗯' }] })).structuredContent;
    assert.equal(retry.recorded.new_turns, 0);
    await call('i_chat_turn', { phase: 'end', thread_id,
      turns: [{ role: 'assistant', content: 'default phase回归：听见了' }] });
    const feed = await coreJson(coreBase, '/v1/core/changes?limit=500', { token: phoneDeviceToken });
    assert.deepEqual(feed.body.events.map((e) => e.payload.content)
      .filter((content) => content.startsWith('default phase回归：')),
    ['default phase回归：嗯', 'default phase回归：听见了', 'default phase回归：嗯', 'default phase回归：听见了']);
  });


});
