// Phone transcript HTTP + real read model + OAuth MCP; all data is synthetic.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
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

const PHONE = 'synthetic-transcript-phone';
const OTHER = 'synthetic-transcript-other';
const CHARACTER = 'synthetic-transcript-character';
const AT = Date.UTC(2026, 9, 3);
const HISTORY = '咖啡：允许窗口内的手机历史';
const USER = '咖啡：手机用户的新原话';
const COMPANION = '咖啡：手机林埃的新回复';
const PRIVATE = '咖啡：PRIVATE_TRANSCRIPT 隐藏回复';

function message(id, sequence, content, overrides = {}) {
  return {
    sync_id: id, origin_device_id: PHONE, origin_sequence: sequence,
    character_id: CHARACTER, sender: 'user', content, message_type: 'chat',
    created_at_ms: AT + sequence * 1000, ...overrides,
  };
}

async function request(base, path, token, body) {
  const response = await fetch(`${base}${path}`, {
    method: body === undefined ? 'GET' : 'POST',
    headers: {
      'x-core-protocol': '0.1', ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  return { status: response.status, body: await response.json() };
}

function inspect(path, read) {
  const db = new DatabaseSync(path, { readOnly: true });
  try { return read(db); } finally { db.close(); }
}

test('explicit phone transcript grant and outbound history/sender rules preserve both speakers through OAuth MCP', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'i-phone-transcript-e2e-'));
  const cleanup = [];
  let core;
  try {
    const corePath = join(dir, 'core.sqlite');
    const stateDir = join(dir, 'remote-state');
    core = createICoreServer({ databasePath: corePath, pairingCode: 'transcript-initial' });
    cleanup.push(() => core?.close());
    let base = `http://127.0.0.1:${(await core.listen({ port: 0 })).port}`;
    async function pair(deviceId, pairingCode) {
      core.replacePairingCode(pairingCode);
      const result = await request(base, '/v1/core/devices/pair', null, {
        device_id: deviceId, display_name: 'synthetic Android', platform: 'android',
        client_version: 'synthetic-1', capabilities: ['chat'], pairing_code: pairingCode,
      });
      assert.equal(result.status, 200);
      return result.body.device_token;
    }
    const phoneToken = await pair(PHONE, 'transcript-phone');
    const otherToken = await pair(OTHER, 'transcript-other');
    const submit = (rows, token = phoneToken, deviceId = PHONE, extra = {}) =>
      request(base, '/v1/core/chat/transcripts', token, { device_id: deviceId, messages: rows, ...extra });
    const companion = message('synthetic-companion', 5, COMPANION, { sender: 'companion' });
    assert.deepEqual((await request(base, '/v1/core/chat/transcript-capabilities', phoneToken)).body, { enabled: false });
    assert.equal((await submit([companion])).status, 403);
    assert.equal((await request(base, '/v1/core/chat/transcript-capabilities')).status, 401);

    // All three users arrive before the receive-sequence boundary; only the
    // middle one is inside the explicitly approved half-open history window.
    assert.equal((await request(base, '/v1/core/chat/messages', phoneToken, {
      device_id: PHONE, messages: [
        message('synthetic-history-before', 1, '咖啡：窗口前历史', { created_at_ms: AT + 999 }),
        message('synthetic-history-inside', 2, HISTORY, { created_at_ms: AT + 1000 }),
        message('synthetic-history-end', 3, '咖啡：窗口结束边界', { created_at_ms: AT + 2000 }),
      ],
    })).status, 200);
    const boundary = inspect(corePath, db => Number(db.prepare('SELECT MAX(server_sequence) AS n FROM change_events').get().n) + 1);
    await core.close();
    core = null;
    core = createICoreServer({
      databasePath: corePath,
      localTranscriptGrants: { version: 1, grants: [{
        device_id: PHONE, character_id: CHARACTER,
        credential_sha256: createHash('sha256').update(phoneToken).digest('hex'),
        from_created_at_ms: AT + 1000,
      }] },
    });
    base = `http://127.0.0.1:${(await core.listen({ port: 0 })).port}`;
    assert.deepEqual((await request(base, '/v1/core/chat/transcript-capabilities', phoneToken)).body, {
      enabled: true, character_id: CHARACTER, from_created_at_ms: AT + 1000,
    });
    assert.deepEqual((await request(base, '/v1/core/chat/transcript-capabilities', otherToken)).body, { enabled: false });
    const oldRoute = await request(base, '/v1/core/chat/messages', phoneToken, { device_id: PHONE, messages: [companion] });
    assert.equal(oldRoute.status, 403);
    assert.equal(oldRoute.body.error.code, 'sender_not_allowed');

    const accepted = await submit([
      message('synthetic-new-user', 4, USER), companion,
      message('synthetic-private-companion', 6, PRIVATE, { sender: 'companion' }),
    ]);
    assert.equal(accepted.status, 200);
    assert.deepEqual(accepted.body.results.map(row => row.status), ['accepted', 'accepted', 'accepted']);
    const sequence = accepted.body.results.find(row => row.sync_id === companion.sync_id).server_sequence;
    const duplicate = await submit([companion]);
    assert.equal(duplicate.status, 200);
    assert.deepEqual(duplicate.body.results, [{ sync_id: companion.sync_id, status: 'duplicate', server_sequence: sequence }]);

    const forbidden = [
      [await submit([message('synthetic-other-device', 1, '咖啡：未授权设备', { origin_device_id: OTHER })], otherToken, OTHER), 'local_transcript_forbidden'],
      [await submit([message('synthetic-too-early', 7, '咖啡：过早', { created_at_ms: AT + 999 })]), 'local_transcript_scope_mismatch'],
      [await submit([message('synthetic-forged-origin', 8, '咖啡：伪造来源', { origin_device_id: OTHER })]), 'origin_device_mismatch'],
      [await submit([message('synthetic-other-character', 9, '咖啡：另一角色', { character_id: 'synthetic-unapproved-character' })]), 'local_transcript_scope_mismatch'],
      [await submit([message('synthetic-asset', 10, '咖啡：附件', { asset_refs: [{ kind: 'synthetic' }] })]), 'local_transcript_scope_mismatch'],
      [await submit([message('synthetic-addendum', 11, '咖啡：附加信息', { addenda: [{ kind: 'synthetic' }] })]), 'local_transcript_scope_mismatch'],
    ];
    for (const [response, code] of forbidden) {
      assert.equal(response.status, 403);
      assert.equal(response.body.error.code, code);
    }
    assert.equal((await submit([message('synthetic-generation', 12, '咖啡：请求生成')], phoneToken, PHONE, { request_companion_reply: true })).status, 400);
    assert.equal(inspect(corePath, db => db.prepare('SELECT COUNT(*) AS n FROM chat_messages').get().n), 6);

    core.replacePairingCode('transcript-frontend');
    await pairFrontendDevice({ coreUrl: base, pairingCode: 'transcript-frontend', stateDir });
    const credential = loadFrontendCredential(stateDir);
    const ledger = openLedger(join(stateDir, 'writeback.sqlite'));
    cleanup.push(() => ledger.close());
    const writeback = createWriteback({ ledger,
      coreClient: createCoreFrontendClient({ coreUrl: base, deviceToken: credential.device_token }),
    });
    const rule = { device_id: PHONE, from_server_sequence: boundary };
    const both = { ...rule, senders: ['user', 'companion'] };
    const cases = [
      { name: 'legacy-user-only', rule, expected: [[USER, 'user']] },
      { name: 'both-without-history', rule: both, expected: [[USER, 'user'], [COMPANION, 'companion']] },
      { name: 'both-with-history', rule: { ...both, history_window: {
        from_created_at_ms: AT + 1000, to_created_at_ms: AT + 2000,
      } }, expected: [[HISTORY, 'user'], [USER, 'user'], [COMPANION, 'companion']] },
    ];
    for (const scenario of cases) {
      const policyPath = join(dir, `${scenario.name}.json`);
      writeFileSync(policyPath, JSON.stringify({
        schema_version: 1, primary_character_id: CHARACTER,
        messages: {
          default: 'private', shareable_character_ids: [CHARACTER], private_message_types: ['diary'],
          private_keywords: ['PRIVATE_TRANSCRIPT'], private_message_ids: [],
          shareable_message_ids: [], shareable_message_hashes: {},
          auto_share_origins: ['claude_web'], auto_share_devices: [scenario.rule],
        },
        memory: { default: 'private', private_types: [], private_structured_types: [], private_card_ids: [], private_keywords: [] },
      }));
      const model = openReadModel({ coreDbPath: corePath, memoryDbPath: join(dir, 'absent-memory.sqlite'), policyPath });
      let ctx;
      try {
        ctx = await startTestServer({ readModel: model, writeback, stateDir });
        const { access_token: token } = await obtainTokens(ctx.base);
        const { sessionId } = await initSession(ctx.base, token);
        let id = 0;
        async function call(name, args) {
          const result = await mcpPost(ctx.base, token, {
            jsonrpc: '2.0', id: ++id, method: 'tools/call', params: { name, arguments: args },
          }, { sessionId });
          assert.equal(result.status, 200);
          assert.equal(result.body.result.isError, false);
          return result.body.result.structuredContent;
        }
        const context = await call('i_context', {});
        const recall = await call('i_recall', { query: '咖啡' });
        const start = await call('i_chat_turn', { turns: [{ role: 'user', content: `synthetic web start ${scenario.name}` }] });
        assert.equal(start.core_status, 'ok');
        assert.equal(start.recorded.new_turns, 1);
        for (const rows of [context.recent_messages, recall.messages.items, start.recent_messages]) {
          const actual = rows.filter(row => row.source === 'here_i_am').map(row => [row.content, row.sender]);
          assert.deepEqual(actual.sort(), [...scenario.expected].sort(), scenario.name);
          assert.ok(!JSON.stringify(rows).includes('PRIVATE_TRANSCRIPT'));
        }
        assert.deepEqual(recall.memory, { count: 0, items: [] });
        const end = await call('i_chat_turn', {
          phase: 'end', thread_id: start.thread_id,
          turns: [{ role: 'assistant', content: `synthetic web reply ${scenario.name}` }],
        });
        assert.equal(end.core_status, 'ok');
        assert.equal(end.recorded.new_turns, 1);
        assert.equal(end.last_recorded.role, 'assistant');
        assert.equal(end.recent_messages, undefined);
      } finally {
        try {
          if (ctx) await new Promise((done, reject) => ctx.server.close(error => error ? reject(error) : done()));
        } finally { model.close(); }
      }
    }
    inspect(corePath, db => {
      const saved = db.prepare('SELECT sender, content, server_sequence FROM chat_messages WHERE sync_id = ?').get(companion.sync_id);
      assert.deepEqual({ ...saved }, { sender: 'companion', content: COMPANION, server_sequence: sequence });
      assert.equal(db.prepare("SELECT COUNT(*) AS n FROM chat_messages WHERE origin_device_id = 'frontend:claude_web' AND sender = 'companion'").get().n, 3);
      assert.equal(db.prepare('SELECT COUNT(*) AS n FROM chat_messages WHERE sync_id = ?').get(companion.sync_id).n, 1);
    });
  } finally {
    const errors = [];
    for (const close of cleanup.reverse()) {
      try { await close(); } catch (error) { errors.push(error); }
    }
    assert.equal(dirname(resolve(dir)), resolve(tmpdir()));
    assert.ok(basename(dir).startsWith('i-phone-transcript-e2e-'));
    rmSync(dir, { recursive: true, force: true });
    if (errors.length) throw new AggregateError(errors, 'Synthetic transcript cleanup failed');
  }
});
