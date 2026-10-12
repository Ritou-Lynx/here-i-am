import assert from 'node:assert/strict';
import { createHash, randomBytes } from 'node:crypto';
import { mkdtempSync, rmSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { createICoreServer } from '../i_core/i_core_server.mjs';
import { openReadModel } from '../i_memory/i_memory_read.mjs';
import { createApp } from './server.mjs';
import { CHATGPT_CALLBACK_URI, setPassphrase } from './oauth.mjs';
import { listenForFetch } from './fetch_test_listener.mjs';
import { PUBLIC_URL, REDIRECT_URI, PASSPHRASE, PRIMARY, mcpPost, initSession } from './fixtures.mjs';
import { createWriteback, createCoreFrontendClient, openLedger, pairFrontendDevice, loadFrontendCredential, CoreUnavailableError } from './writeback.mjs';

function tokens(oauth, callback) {
  const client = oauth.register({ redirect_uris: [callback] }).body;
  const verifier = randomBytes(32).toString('base64url');
  const auth = oauth.submitPassphrase({ client_id: client.client_id, redirect_uri: callback,
    response_type: 'code', code_challenge_method: 'S256',
    code_challenge: createHash('sha256').update(verifier).digest('base64url'), passphrase: PASSPHRASE });
  assert.equal(auth.ok, true);
  const issued = oauth.token({ grant_type: 'authorization_code', client_id: client.client_id,
    redirect_uri: callback, code: new URL(auth.redirect).searchParams.get('code'), code_verifier: verifier });
  assert.equal(issued.status, 200);
  return { ...issued.body, client_id: client.client_id };
}

// Real Core storage and real read-policy filtering, using newly allocated synthetic state only.
test('OAuth callers write distinct Core device identities and read both sources; thread and parameter spoofing reject', async t => {
  const dir = mkdtempSync(join(tmpdir(), 'synthetic-frontend-identity-'));
  const corePath = join(dir, 'core.sqlite');
  const core = createICoreServer({ databasePath: corePath, pairingCode: '123456' });
  let app, reader; const writers = [];
  t.after(async () => {
    if (app?.server.listening) await new Promise(r => app.server.close(r));
    for (const wb of writers) wb.close();
    reader?.close(); await core.close(); rmSync(dir, { recursive: true, force: true });
  });
  const coreUrl = `http://127.0.0.1:${(await core.listen({ port: 0 })).port}`;
  const stateDir = join(dir, 'mcp');
  for (const [frontend, code] of [['claude_web', '123456'], ['chatgpt_web', '654321']]) {
    if (frontend === 'chatgpt_web') core.replacePairingCode(code);
    const paired = await pairFrontendDevice({ coreUrl, pairingCode: code, stateDir, frontend });
    assert.equal(paired.device_id, `frontend:${frontend}`);
    const credential = loadFrontendCredential(stateDir, frontend);
    writers.push(createWriteback({ frontend, ledger: openLedger(join(stateDir, 'writeback.sqlite')),
      coreClient: createCoreFrontendClient({ coreUrl, deviceToken: credential.device_token, frontend }) }));
  }
  assert.notEqual(loadFrontendCredential(stateDir).device_token, loadFrontendCredential(stateDir, 'chatgpt_web').device_token);
  const policyPath = join(dir, 'policy.json');
  writeFileSync(policyPath, JSON.stringify({ schema_version: 1, primary_character_id: PRIMARY,
    messages: { default: 'private', shareable_character_ids: [PRIMARY], private_message_types: [], private_keywords: [],
      auto_share_origins: ['claude_web', 'chatgpt_web'], shareable_message_ids: [], shareable_message_hashes: {} },
    memory: { default: 'shareable', private_types: [], private_structured_types: [], private_card_ids: [], private_keywords: [] } }));
  reader = openReadModel({ coreDbPath: corePath, memoryDbPath: join(dir, 'absent.sqlite'), policyPath });
  setPassphrase(stateDir, PASSPHRASE);
  app = createApp({ stateDir, publicUrl: PUBLIC_URL, chatgptEnabled: true, getReadModel: async () => reader,
    writeback: writers[0], chatgptWriteback: writers[1], identityLoader: () => ({ identity: { name: 'synthetic i' } }) });
  await listenForFetch(app.server);
  const base = `http://127.0.0.1:${app.server.address().port}`;
  const peers = [];
  for (const callback of [REDIRECT_URI, CHATGPT_CALLBACK_URI]) {
    const issued = tokens(app.oauth, callback);
    peers.push({ ...issued, ...(await initSession(base, issued.access_token)) });
  }
  async function rpc(peer, method, params) {
    const response = await mcpPost(base, peer.access_token, { jsonrpc: '2.0', id: 2, method, params }, { sessionId: peer.sessionId });
    assert.equal(response.status, 200); return response.body;
  }
  const call = (peer, args) => rpc(peer, 'tools/call', { name: 'i_chat_turn', arguments: args });
  const threads = [];
  for (let i = 0; i < peers.length; i++) {
    const frontend = i ? 'chatgpt_web' : 'claude_web';
    const listed = (await rpc(peers[i], 'tools/list')).result.tools;
    assert.match(listed.find(x => x.name === 'i_chat_turn').description, new RegExp(frontend));
    if (i) assert.ok(!listed.some(x => ['i_remember', 'capture_add', 'week_get', 'day_get'].includes(x.name)));
    const result = (await call(peers[i], { ...(i === 0 ? { unrelated_extra: 'ignored' } : {}), turns: [{ role: 'user', content: 'same synthetic identity message' }] })).result;
    assert.equal(result.isError, false); assert.equal(result.structuredContent.core_status, 'ok');
    threads.push(result.structuredContent.thread_id);
    const end = await call(peers[i], { thread_id: threads[i], phase: 'end', turns: [{ role: 'assistant', content: 'same synthetic identity reply' }] });
    assert.equal(end.result.structuredContent.recorded.new_turns, 1);
  }
  for (let i = 0; i < peers.length; i++) {
    const denied = (await call(peers[i], { thread_id: threads[1 - i], turns: [{ role: 'user', content: 'spoof attempt' }] })).result;
    assert.equal(denied.isError, true); assert.match(denied.content[0].text, /thread_frontend_mismatch/);
  }
  for (const field of ['frontend', 'device_id', 'origin_device_id', 'source', 'sync_id']) {
    const denied = (await call(peers[1], { [field]: field.includes('device') ? 'frontend:claude_web' : 'claude_web',
      turns: [{ role: 'user', content: 'spoof attempt' }] })).result;
    assert.equal(denied.isError, true); assert.match(denied.content[0].text, /invalid_chat_turn_arguments/);
  }
  const refreshed = app.oauth.token({ grant_type: 'refresh_token', client_id: peers[1].client_id,
    refresh_token: peers[1].refresh_token, frontend: 'claude_web', redirect_uri: REDIRECT_URI });
  assert.equal(refreshed.status, 200);
  const refreshedPeer = { ...peers[1], access_token: refreshed.body.access_token };
  const denied = (await call(refreshedPeer, { thread_id: threads[0], turns: [{ role: 'user', content: 'refresh spoof' }] })).result;
  assert.equal(denied.isError, true); assert.match(denied.content[0].text, /thread_frontend_mismatch/);
  const recalled = (await rpc(peers[0], 'tools/call', { name: 'i_recall', arguments: { query: 'synthetic identity' } })).result.structuredContent.messages.items;
  assert.equal(recalled.length, 4);
  assert.deepEqual(new Set(recalled.map(m => m.source)), new Set(['claude_web', 'chatgpt_web']));
  for (const message of recalled) assert.match(message.sync_id, new RegExp(`^${message.source}:`));
  // Exercise the missing-credential path through the real authenticated MCP handler.
  const missing = createApp({ stateDir, publicUrl: PUBLIC_URL, chatgptEnabled: true, getReadModel: async () => reader, writeback: writers[0] });
  await listenForFetch(missing.server);
  try {
    const missingBase = `http://127.0.0.1:${missing.server.address().port}`;
    const peer = tokens(missing.oauth, CHATGPT_CALLBACK_URI);
    const { sessionId } = await initSession(missingBase, peer.access_token);
    const response = await mcpPost(missingBase, peer.access_token, { jsonrpc: '2.0', id: 3, method: 'tools/call',
      params: { name: 'i_chat_turn', arguments: { turns: [{ role: 'user', content: 'unpaired' }] } } }, { sessionId });
    assert.equal(response.body.result.isError, true);
    assert.equal(response.body.result.content[0].text, 'frontend_not_paired:chatgpt_web');
  } finally { await new Promise(r => missing.server.close(r)); }
});

test('shared ledger queues and lost-thread dedup stay frontend-scoped across reopen', async t => {
  const dir = mkdtempSync(join(tmpdir(), 'synthetic-frontend-queue-'));
  const path = join(dir, 'ledger.sqlite');
  let claude, chatgpt; let down = true; const sent = [];
  const client = frontend => ({ async submit(messages) {
    if (frontend === 'claude_web' && down) throw new CoreUnavailableError('synthetic outage');
    sent.push(...messages); return messages.map((m, i) => ({ sync_id: m.sync_id, status: 'accepted', server_sequence: sent.length + i }));
  } });
  const open = frontend => createWriteback({ frontend, ledger: openLedger(path), coreClient: client(frontend) });
  t.after(() => { claude?.close(); chatgpt?.close(); rmSync(dir, { recursive: true, force: true }); });
  claude = open('claude_web'); chatgpt = open('chatgpt_web');
  const turn = (wb, args) => wb.chatTurn(args, { characterId: PRIMARY });
  const first = await turn(claude, { turns: [{ role: 'user', content: 'identical pending text' }] });
  assert.equal(first.recorded.waiting_for_retry, 1);
  const second = await turn(chatgpt, { turns: [{ role: 'user', content: 'identical pending text' }] });
  assert.equal(second.recorded.new_turns, 1); assert.equal(second.recorded.waiting_for_retry, 0);
  assert.deepEqual(sent.map(m => m.origin_device_id), ['frontend:chatgpt_web']);
  chatgpt.close(); chatgpt = open('chatgpt_web');
  await assert.rejects(turn(chatgpt, { thread_id: first.thread_id, turns: [{ role: 'user', content: 'spoof' }] }), /thread_frontend_mismatch/);
  down = false;
  await turn(claude, { thread_id: first.thread_id, turns: [{ role: 'assistant', content: 'synthetic reply' }] });
  assert.deepEqual(sent.map(m => m.origin_device_id), ['frontend:chatgpt_web', 'frontend:claude_web', 'frontend:claude_web']);
  assert.equal(loadFrontendCredential(dir, 'chatgpt_web'), null);
});

test('pairing uses the selected frontend and distinct credential file; missing ChatGPT never reads Claude credential', async t => {
  const dir = mkdtempSync(join(tmpdir(), 'synthetic-frontend-pair-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const calls = [];
  const fetchImpl = async (_url, options) => { calls.push(JSON.parse(options.body)); return { ok: true, json: async () => ({ device_token: 'synthetic-token-' + calls.length }) }; };
  await pairFrontendDevice({ coreUrl: 'https://core.example.invalid', pairingCode: 'synthetic', stateDir: dir, fetchImpl });
  assert.equal(loadFrontendCredential(dir, 'chatgpt_web'), null);
  await pairFrontendDevice({ coreUrl: 'https://core.example.invalid', pairingCode: 'synthetic', stateDir: dir, frontend: 'chatgpt_web', fetchImpl });
  assert.deepEqual(calls.map(c => [c.device_id, c.display_name]), [['frontend:claude_web', 'claude.ai 网页端'], ['frontend:chatgpt_web', 'ChatGPT 网页端']]);
  assert.equal(JSON.parse(readFileSync(join(dir, 'core-frontend-chatgpt_web.json'))).device_id, 'frontend:chatgpt_web');
  assert.throws(() => loadFrontendCredential(dir, '../claude_web'), /invalid_frontend/);
});

test('ChatGPT keeps read-only domain tools while Claude capture and notes stay isolated', async t => {
  const dir = mkdtempSync(join(tmpdir(), 'synthetic-frontend-domains-'));
  let app; let domainCalls = 0, noteCalls = 0;
  const sentinel = 'SYNTHETIC_CLAUDE_NOTE_ONLY';
  const writer = frontend => createWriteback({ frontend, ledger: openLedger(join(dir, 'ledger.sqlite')),
    coreClient: { async submit(messages) { return messages.map(m => ({ sync_id: m.sync_id, status: 'accepted', server_sequence: 1 })); } } });
  const claude = writer('claude_web'), chatgpt = writer('chatgpt_web');
  t.after(async () => { if (app?.server.listening) await new Promise(r => app.server.close(r)); claude.close(); chatgpt.close(); rmSync(dir, { recursive: true, force: true }); });
  const readModel = { policySummary: () => ({ primaryCharacterId: PRIMARY }), recentMessages: () => [], searchMessages: () => [], searchMemory: () => [] };
  const coreRemember = { activeNotes: async () => { noteCalls++; return [{ text: sentinel }]; }, searchNotes: async () => { noteCalls++; return [{ text: sentinel }]; }, remember: async () => { noteCalls++; return { note: { text: sentinel } }; } };
  const names = ['capture_add', 'week_get', 'day_get'];
  const domainTools = { tools: names.map(name => ({ name, inputSchema: { type: 'object' } })),
    handlers: Object.fromEntries(names.map(name => [name, async () => { domainCalls++; return { synthetic: name }; }])) };
  setPassphrase(dir, PASSPHRASE);
  app = createApp({ stateDir: dir, publicUrl: PUBLIC_URL, chatgptEnabled: true, getReadModel: async () => readModel,
    writeback: claude, chatgptWriteback: chatgpt, coreRemember, domainTools, identityLoader: () => ({}) });
  await listenForFetch(app.server);
  const base = `http://127.0.0.1:${app.server.address().port}`;
  const peers = [];
  for (const callback of [REDIRECT_URI, CHATGPT_CALLBACK_URI]) {
    const issued = tokens(app.oauth, callback);
    peers.push({ ...issued, ...(await initSession(base, issued.access_token)) });
  }
  async function rpc(peer, method, params) {
    return (await mcpPost(base, peer.access_token, { jsonrpc: '2.0', id: 4, method, params }, { sessionId: peer.sessionId })).body;
  }
  const listed = (await rpc(peers[0], 'tools/list')).result.tools;
  for (const name of [...names, 'i_remember']) assert.ok(listed.some(tool => tool.name === name));
  await rpc(peers[0], 'tools/call', { name: 'i_context', arguments: {} });
  await rpc(peers[0], 'tools/call', { name: 'capture_add', arguments: {} });
  assert.equal(domainCalls, 1); assert.equal(noteCalls, 1);
  const chatgptTools = (await rpc(peers[1], 'tools/list')).result.tools;
  assert.deepEqual(chatgptTools.map(tool => tool.name), ['i_context', 'i_recall', 'i_chat_turn', 'week_get', 'day_get']);
  for (const name of ['week_get', 'day_get']) {
    const response = await rpc(peers[1], 'tools/call', { name, arguments: {} });
    assert.equal(response.result.isError, false);
    assert.equal(response.result.structuredContent.synthetic, name);
  }
  for (const name of ['capture_add', 'i_remember']) {
    const denied = await rpc(peers[1], 'tools/call', { name, arguments: {} });
    assert.match(denied.error.message, /Unknown tool/);
  }
  for (const [name, args] of [['i_context', {}], ['i_recall', { query: 'synthetic' }], ['i_chat_turn', { turns: [{ role: 'user', content: 'synthetic' }] }]]) {
    const response = await rpc(peers[1], 'tools/call', { name, arguments: args });
    assert.equal(response.result.isError, false);
    assert.doesNotMatch(JSON.stringify(response), /SYNTHETIC_CLAUDE_NOTE_ONLY|remembered_notes/);
  }
  assert.equal(domainCalls, 3); assert.equal(noteCalls, 1);
  const readToken = tokens(app.oauth, CHATGPT_CALLBACK_URI);
  // A synthetic persisted read-only token exercises call-time scope enforcement.
  const readRecord = Object.values(app.oauth.store.state.access_tokens).find(record => record.client_id === readToken.client_id);
  readRecord.scope = 'i.read';
  const readPeer = { ...readToken, ...(await initSession(base, readToken.access_token)) };
  const readTools = (await rpc(readPeer, 'tools/list')).result.tools.map(tool => tool.name);
  assert.deepEqual(readTools, ['i_context', 'i_recall', 'i_chat_turn', 'week_get', 'day_get']);
  for (const name of ['week_get', 'day_get']) {
    const response = await rpc(readPeer, 'tools/call', { name, arguments: {} });
    assert.equal(response.result.isError, false);
    assert.equal(response.result.structuredContent.synthetic, name);
  }
  const writeDenied = await rpc(readPeer, 'tools/call', { name: 'i_chat_turn',
    arguments: { turns: [{ role: 'user', content: 'synthetic scope denial' }] } });
  assert.equal(writeDenied.result.isError, true);
  assert.match(writeDenied.result.content[0].text, /重新授权/);
  assert.equal(domainCalls, 5); assert.equal(noteCalls, 1);
});

test('Claude writeback ignores unrelated arguments and rejects only identity overrides', async t => {
  const dir = mkdtempSync(join(tmpdir(), 'synthetic-frontend-args-'));
  const sent = [];
  const writer = createWriteback({ ledger: openLedger(join(dir, 'ledger.sqlite')),
    coreClient: { async submit(messages) {
      sent.push(...messages);
      return messages.map(m => ({ sync_id: m.sync_id, status: 'accepted', server_sequence: 1 }));
    } } });
  t.after(() => { writer.close(); rmSync(dir, { recursive: true, force: true }); });
  for (const field of ['frontend', 'source', 'device_id', 'origin_device_id', 'sync_id']) {
    await assert.rejects(writer.chatTurn({ [field]: 'forged', turns: [{ role: 'user', content: 'blocked' }] },
      { characterId: PRIMARY }), /invalid_chat_turn_arguments/);
  }
  assert.equal(sent.length, 0);
  const result = await writer.chatTurn({ unrelated_extra: { synthetic: true },
    turns: [{ role: 'user', content: 'synthetic Claude extra argument' }] }, { characterId: PRIMARY });
  assert.equal(result.core_status, 'ok');
  assert.equal(result.recorded.new_turns, 1);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].origin_device_id, 'frontend:claude_web');
  assert.equal(sent[0].unrelated_extra, undefined);
});
