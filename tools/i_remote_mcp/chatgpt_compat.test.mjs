// Synthetic ChatGPT connector E2E: real HTTP/OAuth/SQLite/read model, fake core writer.
// No live accounts, deployed endpoints, existing databases, device credentials or phone access.
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { tmpdir } from 'node:os';
import { dirname, join, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import { after, before, describe, test } from 'node:test';
import { openReadModel } from '../i_memory/i_memory_read.mjs';
import { PASSPHRASE, PUBLIC_URL, PRIMARY, REDIRECT_URI, mcpPost, pkcePair } from './fixtures.mjs';
import { listenForFetch } from './fetch_test_listener.mjs';
import { OAuthServer, setPassphrase, sha256 } from './oauth.mjs';
import { createApp } from './server.mjs';
import { createWriteback, openLedger } from './writeback.mjs';

const ORIGIN = 'https://chatgpt.com';
const CALLBACK = `${ORIGIN}/connector_platform_oauth_redirect`;
const RESOURCE = `${PUBLIC_URL}/mcp`;
const VERSION = '2025-06-18';
const PRIVATE = 'SYNTHETIC_PRIVATE_SENTINEL';

const sourceRuntime = { createApp, openReadModel, createWriteback, openLedger, OAuthServer, setPassphrase, sha256 };

async function createFixture(t, runtime, options = { chatgptEnabled: true }) {
  const { createApp, openReadModel, createWriteback, openLedger, OAuthServer, setPassphrase } = runtime;
  const dir = mkdtempSync(join(tmpdir(), 'i-chatgpt-compat-'));
  const db = new DatabaseSync(join(dir, 'synthetic-core.sqlite'));
  db.exec(`CREATE TABLE chat_messages (
    sync_id TEXT PRIMARY KEY, character_id TEXT, sender TEXT, content TEXT,
    created_at_ms INTEGER, message_type TEXT, origin_device_id TEXT,
    server_sequence INTEGER UNIQUE
  )`);
  const insert = db.prepare('INSERT INTO chat_messages VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
  insert.run('hidden-seed', PRIMARY, 'user', PRIVATE, 1, 'chat', 'frontend:claude_web', 1);
  const submitted = [];
  const fakeCore = {
    async submit(messages) {
      return messages.map(m => {
        const prior = db.prepare('SELECT server_sequence FROM chat_messages WHERE sync_id = ?').get(m.sync_id);
        if (prior) return { sync_id: m.sync_id, status: 'duplicate', server_sequence: prior.server_sequence };
        const seq = submitted.length + 2;
        insert.run(m.sync_id, m.character_id, m.sender, m.content, m.created_at_ms,
          m.message_type, m.origin_device_id, seq);
        submitted.push(m);
        return { sync_id: m.sync_id, status: 'accepted', server_sequence: seq };
      });
    },
  };
  const policyPath = join(dir, 'synthetic-policy.json');
  writeFileSync(policyPath, JSON.stringify({
    schema_version: 1, primary_character_id: PRIMARY,
    messages: { default: 'private', shareable_character_ids: [PRIMARY],
      private_message_types: [], private_keywords: [PRIVATE],
      shareable_message_ids: [], shareable_message_hashes: {}, auto_share_origins: ['claude_web'] },
    memory: { default: 'shareable', private_types: [], private_structured_types: [],
      private_card_ids: [], private_keywords: [] },
  }));
  const readModel = openReadModel({ coreDbPath: join(dir, 'synthetic-core.sqlite'),
    memoryDbPath: join(dir, 'absent-memory.sqlite'), policyPath });
  const ledger = openLedger(join(dir, 'synthetic-writeback.sqlite'));
  const writeback = createWriteback({ ledger, coreClient: fakeCore });
  setPassphrase(dir, PASSPHRASE);
  const diagnostics = [];
  const app = createApp({ stateDir: dir, publicUrl: PUBLIC_URL,
    getReadModel: async () => readModel, writeback, diagnostic: r => diagnostics.push(r),
    identityLoader: () => ({ name: 'synthetic i' }), ...options });
  assert.ok(app.oauth instanceof OAuthServer, 'server must use the selected runtime OAuth implementation');
  t.after(async () => {
    if (app.server.listening) await new Promise(r => app.server.close(r));
    writeback.close(); readModel.close(); db.close();
    // Only this test's newly allocated directory is removed.
    rmSync(dir, { recursive: true, force: true });
  });
  await listenForFetch(app.server);
  return { ...app, dir, db, submitted, diagnostics,
    base: `http://127.0.0.1:${app.server.address().port}` };
}

async function json(ctx, path, { origin = ORIGIN, fields, body, method = 'POST' } = {}) {
  const response = await fetch(`${ctx.base}${path}`, { method,
    headers: { Origin: origin, ...(fields ? { 'Content-Type': 'application/x-www-form-urlencoded' }
      : body ? { 'Content-Type': 'application/json' } : {}) },
    ...(fields ? { body: new URLSearchParams(fields) } : body ? { body: JSON.stringify(body) } : {}),
    redirect: 'manual' });
  return { status: response.status, headers: response.headers, body: await response.json() };
}

async function register(ctx, origin = ORIGIN, callback = CALLBACK) {
  const r = await json(ctx, '/register', { origin, body: {
    client_name: origin === ORIGIN ? 'Synthetic ChatGPT' : 'Synthetic Claude',
    redirect_uris: [callback], token_endpoint_auth_method: 'none',
    grant_types: ['authorization_code', 'refresh_token'], response_types: ['code'],
  } });
  assert.equal(r.status, 201, JSON.stringify(r.body));
  assert.equal(r.body.token_endpoint_auth_method, 'none');
  assert.equal(r.body.client_secret, undefined);
  return r.body;
}

async function authorize(ctx, client, { origin = ORIGIN, callback = CALLBACK } = {}) {
  const { verifier, challenge } = pkcePair();
  const params = new URLSearchParams({ response_type: 'code', client_id: client.client_id,
    redirect_uri: callback, code_challenge: challenge, code_challenge_method: 'S256',
    scope: 'i.read i.write offline_access', state: 'synthetic-csrf-state', resource: RESOURCE });
  const page = await fetch(`${ctx.base}/authorize?${params}`, { headers: { Origin: origin } });
  assert.equal(page.status, 200);
  assert.match(await page.text(), /i\.read|读取/);
  params.set('passphrase', PASSPHRASE);
  const response = await fetch(`${ctx.base}/authorize`, { method: 'POST', redirect: 'manual',
    headers: { Origin: PUBLIC_URL, 'Content-Type': 'application/x-www-form-urlencoded' }, body: params });
  assert.equal(response.status, 302);
  const location = new URL(response.headers.get('location'));
  assert.equal(`${location.origin}${location.pathname}`, callback);
  assert.equal(location.searchParams.get('state'), 'synthetic-csrf-state');
  assert.equal(location.searchParams.get('iss'), PUBLIC_URL);
  assert.ok(location.searchParams.get('code'));
  return { verifier, code: location.searchParams.get('code'), params };
}

async function connect(ctx, origin = ORIGIN, callback = CALLBACK) {
  const client = await register(ctx, origin, callback);
  const grant = await authorize(ctx, client, { origin, callback });
  const issued = await json(ctx, '/token', { origin, fields: {
    grant_type: 'authorization_code', client_id: client.client_id, redirect_uri: callback,
    code: grant.code, code_verifier: grant.verifier, resource: RESOURCE,
  } });
  assert.equal(issued.status, 200);
  assert.equal(issued.headers.get('cache-control'), 'no-store');
  assert.equal(issued.body.scope, 'i.read i.write');
  const peer = { client, origin, ...issued.body };
  const init = await rpc(ctx, peer, 'initialize', { protocolVersion: VERSION,
    capabilities: {}, clientInfo: { name: origin === ORIGIN ? 'ChatGPT' : 'Claude', version: 'synthetic' } });
  assert.equal(init.status, 200, init.text);
  assert.equal(init.body.result.protocolVersion, VERSION);
  peer.sessionId = init.headers.get('mcp-session-id');
  assert.ok(peer.sessionId);
  const notified = await mcpPost(ctx.base, peer.access_token, { jsonrpc: '2.0', method: 'notifications/initialized' },
    { sessionId: peer.sessionId, headers: { Origin: origin, 'MCP-Protocol-Version': VERSION } });
  assert.equal(notified.status, 202);
  return peer;
}

function rpc(ctx, peer, method, params = {}) {
  return mcpPost(ctx.base, peer.access_token, { jsonrpc: '2.0', id: 1, method, params },
    { sessionId: peer.sessionId, headers: { Origin: peer.origin, 'MCP-Protocol-Version': VERSION } });
}

async function call(ctx, peer, name, args) {
  const r = await rpc(ctx, peer, 'tools/call', { name, arguments: args });
  assert.equal(r.status, 200, r.text);
  assert.equal(r.body.result.isError, false, r.text);
  for (const marker of [PRIVATE, PASSPHRASE, peer.access_token, peer.refresh_token, ctx.dir, 'private_keywords']) {
    assert.ok(!r.text.includes(marker), `tool output leaked ${marker === PRIVATE ? 'private marker' : 'internal data'}`);
  }
  return r.body.result.structuredContent;
}

function preflight(ctx, origin = ORIGIN, method = 'POST', headers = 'authorization, content-type, accept, mcp-session-id, mcp-protocol-version') {
  return fetch(`${ctx.base}/mcp`, { method: 'OPTIONS', headers: {
    Origin: origin, 'Access-Control-Request-Method': method, 'Access-Control-Request-Headers': headers,
  } });
}

function registerCompatSuite(label, loadRuntime) {
  describe(label, () => {
    let runtime;
    before(async () => { runtime = await loadRuntime(); });
    const fixture = (t, options) => createFixture(t, runtime, options);

    test('ChatGPT discovery, DCR, consent, PKCE, MCP, write/recall and refresh rotation over real HTTP', async t => {
      const ctx = await fixture(t);
      const challenge = await rpc(ctx, { origin: ORIGIN }, 'tools/list');
      assert.equal(challenge.status, 401);
      assert.match(challenge.headers.get('www-authenticate'), /resource_metadata=/);
      assert.equal(challenge.headers.get('access-control-allow-origin'), ORIGIN);
      const resource = await json(ctx, '/.well-known/oauth-protected-resource/mcp', { method: 'GET' });
      assert.equal(resource.status, 200);
      assert.equal(resource.body.resource, RESOURCE);
      assert.deepEqual(resource.body.authorization_servers, [PUBLIC_URL]);
      const meta = await json(ctx, '/.well-known/oauth-authorization-server', { method: 'GET' });
      assert.equal(meta.body.issuer, PUBLIC_URL);
      assert.equal(meta.body.authorization_response_iss_parameter_supported, true);
      assert.deepEqual(meta.body.code_challenge_methods_supported, ['S256']);
      assert.deepEqual(meta.body.token_endpoint_auth_methods_supported, ['none']);
      assert.equal(meta.body.client_id_metadata_document_supported, undefined);
      assert.equal(meta.body.id_token_signing_alg_values_supported, undefined);
      const peer = await connect(ctx);
      const tools = await rpc(ctx, peer, 'tools/list');
      assert.equal(tools.status, 200);
      assert.equal(tools.headers.get('access-control-allow-origin'), ORIGIN);
      assert.match(tools.headers.get('access-control-expose-headers'), /mcp-session-id/i);
      assert.deepEqual(tools.body.result.tools.map(x => x.name), ['i_context', 'i_recall', 'i_chat_turn', 'i_remember']);
      const start = await call(ctx, peer, 'i_chat_turn', { phase: 'start', turns: [{ role: 'user', content: 'Synthetic cat likes rain' }] });
      assert.equal(start.core_status, 'ok');
      assert.equal(start.recorded.new_turns, 1);
      assert.equal(start.recent_messages.length, 0);
      const end = await call(ctx, peer, 'i_chat_turn', { phase: 'end', thread_id: start.thread_id,
        turns: [{ role: 'assistant', content: 'Synthetic cat is watching rain' }] });
      assert.equal(end.recorded.new_turns, 1);
      assert.equal(end.recent_messages, undefined);
      const retry = await call(ctx, peer, 'i_chat_turn', { phase: 'end', thread_id: start.thread_id,
        turns: [{ role: 'assistant', content: 'Synthetic cat is watching rain' }] });
      assert.equal(retry.recorded.new_turns, 0);
      const recall = await call(ctx, peer, 'i_recall', { query: 'Synthetic cat' });
      assert.equal(recall.messages.items.length, 2);
      assert.ok(recall.messages.items.every(x => x.source === 'claude_web'));
      assert.deepEqual(ctx.submitted.map(x => [x.sender, x.content]), [
        ['user', 'Synthetic cat likes rain'], ['companion', 'Synthetic cat is watching rain']]);
      assert.ok(ctx.submitted.every(x => x.origin_device_id === 'frontend:claude_web' && x.character_id === PRIMARY));
      const rotated = await json(ctx, '/token', { fields: { grant_type: 'refresh_token',
        client_id: peer.client.client_id, refresh_token: peer.refresh_token } });
      assert.equal(rotated.status, 200);
      assert.equal(rotated.body.scope, 'i.read i.write');
      assert.notEqual(rotated.body.refresh_token, peer.refresh_token);
      const refreshedPeer = { ...peer, ...rotated.body };
      assert.equal((await rpc(ctx, refreshedPeer, 'tools/list')).status, 200, 'same family retains its MCP session');
      const replay = await json(ctx, '/token', { fields: { grant_type: 'refresh_token',
        client_id: peer.client.client_id, refresh_token: peer.refresh_token } });
      assert.equal(replay.status, 400);
      assert.equal(replay.body.error, 'invalid_grant');
      assert.equal((await rpc(ctx, refreshedPeer, 'tools/list')).status, 401);
      const logs = JSON.stringify(ctx.diagnostics);
      for (const value of [PASSPHRASE, peer.access_token, peer.refresh_token, 'Synthetic cat likes rain', PRIVATE])
        assert.ok(!logs.includes(value), 'diagnostic output must omit secrets and message text');
    });

    test('ChatGPT and Claude preserve identical text in independent client threads and keep sessions family-bound', async t => {
      const ctx = await fixture(t);
      const [chatgpt, claude] = await Promise.all([connect(ctx), connect(ctx, 'https://claude.ai', REDIRECT_URI)]);
      const peers = [chatgpt, claude, chatgpt];
      const starts = await Promise.all(peers.map(peer => call(ctx, peer, 'i_chat_turn', {
        phase: 'start', turns: [{ role: 'user', content: 'same synthetic text' }],
      })));
      assert.equal(new Set(starts.map(x => x.thread_id)).size, 3);
      assert.ok(starts.every(x => x.recorded.new_turns === 1));
      await Promise.all(peers.map((peer, i) => call(ctx, peer, 'i_chat_turn', {
        phase: 'end', thread_id: starts[i].thread_id, turns: [{ role: 'assistant', content: 'same synthetic reply' }],
      })));
      assert.equal(ctx.submitted.length, 6);
      assert.equal(new Set(ctx.submitted.map(x => x.sync_id)).size, 6);
      for (const start of starts) {
        const messages = ctx.submitted.filter(x => x.sync_id.startsWith(`claude_web:${start.thread_id}:`));
        assert.deepEqual(messages.map(x => x.content), ['same synthetic text', 'same synthetic reply']);
      }
      assert.equal((await rpc(ctx, { ...claude, sessionId: chatgpt.sessionId }, 'tools/list')).status, 404);
      assert.equal((await rpc(ctx, { ...chatgpt, sessionId: claude.sessionId }, 'tools/list')).status, 404);
      assert.equal((await rpc(ctx, claude, 'tools/list')).status, 200);
    });

    test('ChatGPT preflight is narrow, unauthenticated, and cannot bypass write authorization', async t => {
      const ctx = await fixture(t);
      for (const method of ['POST', 'DELETE']) {
        const r = await preflight(ctx, ORIGIN, method);
        assert.equal(r.status, 204);
        assert.equal(r.headers.get('access-control-allow-origin'), ORIGIN);
        assert.match(r.headers.get('vary'), /origin/i);
        const allowed = r.headers.get('access-control-allow-headers').toLowerCase();
        for (const name of ['authorization', 'content-type', 'accept', 'mcp-session-id', 'mcp-protocol-version'])
          assert.ok(allowed.includes(name));
        assert.equal(r.headers.get('access-control-allow-credentials'), null);
      }
      for (const origin of ['https://chatgpt.com.evil.test', 'https://chatgpt.com/', 'http://chatgpt.com', 'https://www.chatgpt.com', 'null']) {
        const denied = await preflight(ctx, origin);
        assert.equal(denied.status, 403);
        assert.equal(denied.headers.get('access-control-allow-origin'), null);
      }
      assert.equal((await preflight(ctx, ORIGIN, 'PUT')).status, 403);
      assert.equal((await preflight(ctx, ORIGIN, 'POST', 'x-unapproved-header')).status, 403);
      const peer = await connect(ctx);
      for (const bearer of [undefined, 'invalid-synthetic-token']) {
        assert.equal((await rpc(ctx, { ...peer, access_token: bearer }, 'tools/call', {
          name: 'i_chat_turn', arguments: { turns: [{ role: 'user', content: 'must never be written' }] },
        })).status, 401);
      }
      assert.equal((await rpc(ctx, { ...peer, origin: 'https://evil.test' }, 'tools/call', {
        name: 'i_chat_turn', arguments: { turns: [{ role: 'user', content: 'must never be written' }] },
      })).status, 403);
      assert.equal(ctx.submitted.length, 0);
    });

    test('default-disabled ChatGPT rejects callback, Origin and preflight while Claude remains usable', async t => {
      const prior = process.env.I_REMOTE_MCP_CHATGPT_ENABLED;
      delete process.env.I_REMOTE_MCP_CHATGPT_ENABLED;
      let ctx;
      try { ctx = await fixture(t, {}); }
      finally {
        if (prior === undefined) delete process.env.I_REMOTE_MCP_CHATGPT_ENABLED;
        else process.env.I_REMOTE_MCP_CHATGPT_ENABLED = prior;
      }
      const registration = await json(ctx, '/register', { body: {
        redirect_uris: [CALLBACK], token_endpoint_auth_method: 'none',
      } });
      assert.equal(registration.status, 400);
      assert.equal(registration.body.error, 'invalid_redirect_uri');
      assert.equal((await preflight(ctx)).status, 403);
      const claude = await connect(ctx, 'https://claude.ai', REDIRECT_URI);
      assert.equal((await rpc(ctx, { ...claude, origin: ORIGIN }, 'tools/list')).status, 403);
      assert.equal((await rpc(ctx, claude, 'tools/list')).status, 200);
      const written = await call(ctx, claude, 'i_chat_turn', { phase: 'start', turns: [{ role: 'user', content: 'Claude regression' }] });
      assert.equal(written.recorded.new_turns, 1);
    });

    test('ChatGPT rejects malformed PKCE/resource and exact-callback lookalikes before issuing usable tokens', async t => {
      const ctx = await fixture(t);
      for (const callback of [`${CALLBACK}/`, `${CALLBACK}?x=1`, `${CALLBACK}#fragment`,
        'https://chatgpt.com.evil.test/connector_platform_oauth_redirect']) {
        const denied = await json(ctx, '/register', { body: { redirect_uris: [callback], token_endpoint_auth_method: 'none' } });
        assert.equal(denied.status, 400);
        assert.equal(denied.body.error, 'invalid_redirect_uri');
      }
      const client = await register(ctx);
      const grant = await authorize(ctx, client);
      const fields = { grant_type: 'authorization_code', client_id: client.client_id,
        redirect_uri: CALLBACK, code: grant.code, code_verifier: grant.verifier, resource: RESOURCE };
      for (const [override, error] of [[{ code_verifier: pkcePair().verifier }, 'invalid_grant'],
        [{ code_verifier: '' }, 'invalid_grant'], [{ resource: 'https://evil.test/mcp' }, 'invalid_target']]) {
        const denied = await json(ctx, '/token', { fields: { ...fields, ...override } });
        assert.equal(denied.status, 400);
        assert.equal(denied.body.error, error);
        assert.equal(denied.body.access_token, undefined);
      }
      for (const [key, value, error] of [['code_challenge_method', 'plain', 'invalid_request'],
        ['resource', 'https://evil.test/mcp', 'invalid_target']]) {
        const params = new URLSearchParams(grant.params);
        params.delete('passphrase'); params.set(key, value);
        const denied = await fetch(`${ctx.base}/authorize?${params}`, { redirect: 'manual', headers: { Origin: ORIGIN } });
        assert.equal(denied.status, 302);
        const redirect = new URL(denied.headers.get('location'));
        assert.equal(redirect.searchParams.get('error'), error);
        assert.equal(redirect.searchParams.get('iss'), PUBLIC_URL);
        assert.equal(redirect.searchParams.get('code'), null);
      }
      assert.equal(ctx.submitted.length, 0);
    });

    test('a legacy i.read token can read but cannot write through ChatGPT, including after refresh', async t => {
      const ctx = await fixture(t);
      const peer = await connect(ctx);
      // Synthetic pre-write-enable grant: no production state is loaded or modified.
      ctx.oauth.store.state.access_tokens[runtime.sha256(peer.access_token)].scope = 'i.read';
      ctx.oauth.store.state.refresh_tokens[runtime.sha256(peer.refresh_token)].scope = 'i.read';
      for (const [name, args] of [['i_chat_turn', { phase: 'start', turns: [{ role: 'user', content: 'blocked write' }] }],
        ['i_remember', { text: 'blocked note' }]]) {
        const denied = await rpc(ctx, peer, 'tools/call', { name, arguments: args });
        assert.equal(denied.status, 200);
        assert.equal(denied.body.result.isError, true);
        assert.match(denied.body.result.content[0].text, /重新授权/);
        assert.match(denied.body.result.content[0].text, /当前客户端的连接器设置/);
        assert.doesNotMatch(denied.body.result.content[0].text, /claude\.ai/i);
      }
      await call(ctx, peer, 'i_recall', { query: 'synthetic' });
      const rotated = await json(ctx, '/token', { fields: { grant_type: 'refresh_token',
        client_id: peer.client.client_id, refresh_token: peer.refresh_token, scope: 'i.read i.write' } });
      assert.equal(rotated.status, 200);
      assert.equal(rotated.body.scope, 'i.read');
      const denied = await rpc(ctx, { ...peer, ...rotated.body }, 'tools/call', {
        name: 'i_chat_turn', arguments: { turns: [{ role: 'user', content: 'blocked after refresh' }] },
      });
      assert.equal(denied.body.result.isError, true);
      assert.match(denied.body.result.content[0].text, /当前客户端的连接器设置/);
      assert.doesNotMatch(denied.body.result.content[0].text, /claude\.ai/i);
      assert.equal(ctx.submitted.length, 0);
    });

  });
}

registerCompatSuite('source runtime', async () => sourceRuntime);

// Build the real six-file candidate once, then import every implementation from it.
// HTTP helpers and fixed synthetic values are shared; application modules are not.
const checkout = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const candidateDirectory = join(checkout, 'build', `chatgpt-compat-e2e-${randomUUID()}`);
let builtCandidate;
after(() => {
  if (!builtCandidate) return;
  const expectedParent = resolve(checkout, 'build') + sep;
  assert.ok(resolve(candidateDirectory).startsWith(expectedParent));
  assert.equal(resolve(builtCandidate.outputRoot), resolve(candidateDirectory));
  assert.equal(resolve(builtCandidate.root), resolve(candidateDirectory, 'runtime'));
  assert.equal(resolve(builtCandidate.manifestPath), resolve(candidateDirectory, 'manifest.json'));
  rmSync(candidateDirectory, { recursive: true, force: true });
});

registerCompatSuite('actual six-file candidate runtime', async () => {
  const { buildChatgptCandidate } = await import('./chatgpt_candidate.mjs');
  builtCandidate = await buildChatgptCandidate({ outputDirectory: candidateDirectory });
  assert.equal(resolve(builtCandidate.outputRoot), resolve(candidateDirectory));
  assert.equal(resolve(builtCandidate.root), resolve(candidateDirectory, 'runtime'));
  const relativeModules = [
    'i_remote_mcp/server.mjs', 'i_remote_mcp/oauth.mjs', 'i_remote_mcp/mcp.mjs',
    'i_remote_mcp/diagnostics.mjs', 'i_remote_mcp/writeback.mjs', 'i_memory/i_memory_read.mjs',
  ];
  assert.equal(resolve(builtCandidate.entryPath), resolve(builtCandidate.root, relativeModules[0]));
  const [server, oauth, mcp, diagnostics, writeback, readModel] = await Promise.all(
    relativeModules.map(path => import(pathToFileURL(resolve(builtCandidate.root, path)).href)));
  assert.equal(typeof mcp.createToolHandlers, 'function');
  assert.equal(typeof diagnostics.createRequestDiagnostics, 'function');
  const runtime = { createApp: server.createApp, openReadModel: readModel.openReadModel,
    createWriteback: writeback.createWriteback, openLedger: writeback.openLedger,
    OAuthServer: oauth.OAuthServer, setPassphrase: oauth.setPassphrase, sha256: oauth.sha256 };
  for (const [name, implementation] of Object.entries(runtime)) {
    assert.equal(typeof implementation, 'function', `candidate export ${name}`);
    assert.notEqual(implementation, sourceRuntime[name], `${name} must come from candidate files`);
  }
  return runtime;
});
