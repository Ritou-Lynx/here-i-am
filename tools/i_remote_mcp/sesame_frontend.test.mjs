import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { createApp } from './server.mjs';
import { SESAME_CALLBACKS, CHATGPT_CALLBACK_URI, OAuthServer,
  sesameEnabledFromEnv, frontendForRedirectUri, isAllowedRedirectUri, setPassphrase } from './oauth.mjs';
import { callbackClass } from './diagnostics.mjs';
import { createWriteback, frontendDefinition, loadFrontendCredential, openLedger, pairFrontendDevice } from './writeback.mjs';
import { listenForFetch } from './fetch_test_listener.mjs';
import { authorizeParams, createFakeReadModel, initSession, mcpPost, pkcePair,
  postToken, PUBLIC_URL, REDIRECT_URI, PASSPHRASE, submitPassphrase } from './fixtures.mjs';

const callbacks = ['https://sesameai.app/api/oauth/external-mcp/callback'];
const invalid = [
  'https://www.sesameai.app/api/oauth/external-mcp/callback',
  'https://evil.sesameai.app/api/oauth/external-mcp/callback',
  'http://sesameai.app/api/oauth/external-mcp/callback',
  'https://sesameai.app:8443/api/oauth/external-mcp/callback',
  'https://sesameai.app:443/api/oauth/external-mcp/callback',
  callbacks[0] + '/', callbacks[0] + '?x=1', callbacks[0] + '#f',
  'https://SESAMEAI.app/api/oauth/external-mcp/callback',
  callbacks[0] + '2', 'https://user@sesameai.app/api/oauth/external-mcp/callback',
  'https://sesameai.app/api/oauth/external-mcp/Callback',
  callbacks[0] + '?', callbacks[0] + '#',
];

async function synthetic(t, { paired = false, app: options = {} } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'synthetic-sesame-'));
  const records = [], sent = [], writers = [];
  const writer = frontend => {
    const wb = createWriteback({ frontend, ledger: openLedger(join(dir, 'ledger.sqlite')),
      coreClient: { async submit(messages) {
        sent.push(...messages);
        return messages.map(m => ({ sync_id: m.sync_id, status: 'accepted', server_sequence: sent.length }));
      } } });
    writers.push(wb);
    return wb;
  };
  setPassphrase(dir, PASSPHRASE);
  const app = createApp({ stateDir: dir, publicUrl: PUBLIC_URL,
    getReadModel: async () => createFakeReadModel(), identityLoader: () => ({}),
    chatgptEnabled: true, diagnostic: record => records.push(record),
    writeback: writer('claude_web'), chatgptWriteback: writer('chatgpt_web'),
    geminiWriteback: writer('gemini_web'), antigravityWriteback: writer('antigravity'),
    ...(paired ? { sesameWriteback: writer('sesame') } : {}), ...options });
  t.after(async () => {
    if (app.server.listening) await new Promise(r => app.server.close(r));
    for (const wb of writers) wb.close();
    rmSync(dir, { recursive: true, force: true });
  });
  await listenForFetch(app.server);
  return { ...app, dir, records, sent, base: `http://127.0.0.1:${app.server.address().port}` };
}

async function register(ctx, redirectUris = callbacks) {
  const response = await fetch(ctx.base + '/register', { method: 'POST',
    headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({
      client_name: 'arbitrary synthetic client', redirect_uris: redirectUris, token_endpoint_auth_method: 'none',
      grant_types: ['authorization_code', 'refresh_token'], scope: 'i.read i.write offline_access',
    }) });
  return { status: response.status, body: await response.json() };
}

async function pending(ctx, client, redirectUri = callbacks[0]) {
  const { verifier, challenge } = pkcePair();
  const params = authorizeParams({ clientId: client.client_id, challenge, redirectUri });
  params.set('scope', 'i.read i.write offline_access');
  const response = await submitPassphrase(ctx.base, params);
  assert.equal(response.status, 302);
  const location = new URL(response.headers.get('location'));
  assert.equal(location.origin, new URL(redirectUri).origin);
  assert.equal(location.pathname, '/api/oauth/external-mcp/callback');
  assert.equal(location.searchParams.get('iss'), PUBLIC_URL);
  return { params, fields: { grant_type: 'authorization_code', client_id: client.client_id,
    code: location.searchParams.get('code'), redirect_uri: redirectUri,
    code_verifier: verifier, resource: PUBLIC_URL + '/mcp' } };
}

async function issue(ctx, redirectUri = callbacks[0]) {
  const registered = await register(ctx);
  assert.equal(registered.status, 201);
  assert.deepEqual(registered.body.redirect_uris, callbacks);
  assert.equal(registered.body.client_name, 'arbitrary synthetic client');
  assert.equal(registered.body.token_endpoint_auth_method, 'none');
  assert.deepEqual(registered.body.grant_types, ['authorization_code', 'refresh_token']);
  const authorization = await pending(ctx, registered.body, redirectUri);
  const issued = await postToken(ctx.base, authorization.fields);
  assert.equal(issued.status, 200);
  return { client: registered.body, ...issued.body };
}

const rpc = (ctx, peer, method, params) => mcpPost(ctx.base, peer.access_token,
  { jsonrpc: '2.0', id: 2, method, params }, { sessionId: peer.sessionId });

test('Sesame has exactly one frozen callback with no URL normalization or pattern aliases', () => {
  assert.ok(Object.isFrozen(SESAME_CALLBACKS));
  assert.deepEqual(SESAME_CALLBACKS, callbacks);
  for (const uri of callbacks) {
    assert.equal(frontendForRedirectUri(uri), 'sesame');
    assert.equal(isAllowedRedirectUri(uri, false, false, false, true), true);
    assert.equal(isAllowedRedirectUri(uri, true, true, true, false), false);
  }
  for (const uri of [...invalid, undefined, null, 42, {}, '']) {
    assert.equal(frontendForRedirectUri(uri), null);
    assert.equal(isAllowedRedirectUri(uri, true, true, true, true), false);
  }
});

test('Sesame accepts its single callback and rejects variants and every mixed frontend', async t => {
  const ctx = await synthetic(t);
  for (const uri of callbacks) assert.equal((await register(ctx, [uri])).status, 201);
  const gemini = 'https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-synthetic';
  for (const other of [REDIRECT_URI, CHATGPT_CALLBACK_URI, gemini, 'http://127.0.0.1:32014/oauth/callback']) {
    for (const uris of [[callbacks[0], other], [other, callbacks[0]]]) {
      const rejected = await register(ctx, uris);
      assert.equal(rejected.status, 400);
      assert.equal(rejected.body.error, 'invalid_redirect_uri');
      assert.doesNotMatch(rejected.body.error_description, /https/);
    }
  }
  for (const uri of invalid) {
    assert.equal((await register(ctx, [uri])).status, 400);
    assert.equal((await register(ctx, [callbacks[0], uri])).status, 400);
  }
});

test('Sesame defaults on and rejects invalid environment values and constructor options', async t => {
  assert.equal(sesameEnabledFromEnv({}), true);
  assert.equal(sesameEnabledFromEnv({ I_REMOTE_MCP_SESAME_ENABLED: '1' }), true);
  assert.equal(sesameEnabledFromEnv({ I_REMOTE_MCP_SESAME_ENABLED: '0' }), false);
  for (const value of ['2', 'true', '', 'false', ' 1', 1, null]) {
    assert.throws(() => sesameEnabledFromEnv({ I_REMOTE_MCP_SESAME_ENABLED: value }), /invalid_sesame_mode/);
  }
  const ctx = await synthetic(t);
  for (const value of ['0', 'true', 1, null]) {
    const options = { stateDir: ctx.dir, publicUrl: PUBLIC_URL,
      getReadModel: async () => createFakeReadModel(), sesameEnabled: value };
    assert.throws(() => new OAuthServer(options), /invalid_sesame_mode/);
    assert.throws(() => createApp(options), /invalid_sesame_mode/);
  }
});

for (const redirectUri of callbacks) {
  test(`Sesame public client completes OAuth, isolated RPC and refresh via ${new URL(redirectUri).hostname}`, async t => {
    let captureCalls = 0, noteCalls = 0;
    const domainTools = { tools: ['capture_add', 'week_get', 'day_get'].map(name => ({ name, inputSchema: { type: 'object' } })),
      handlers: { capture_add: async () => { captureCalls++; }, week_get: async () => ({ synthetic: 'week' }),
        day_get: async () => ({ synthetic: 'day' }) } };
    const coreRemember = { activeNotes: async () => { noteCalls++; return []; },
      searchNotes: async () => { noteCalls++; return []; }, remember: async () => { noteCalls++; } };
    const ctx = await synthetic(t, { paired: true, app: { domainTools, coreRemember } });
    const peer = await issue(ctx, redirectUri);
    assert.equal(ctx.oauth.verifyAccessToken('Bearer ' + peer.access_token).frontend, 'sesame');
    assert.equal(peer.scope, 'i.read i.write');
    Object.assign(peer, await initSession(ctx.base, peer.access_token));
    const listed = await rpc(ctx, peer, 'tools/list');
    assert.deepEqual(listed.body.result.tools.map(tool => tool.name), ['i_context', 'i_recall', 'i_chat_turn', 'week_get', 'day_get']);
    for (const name of ['i_context', 'i_recall', 'week_get', 'day_get']) {
      const result = await rpc(ctx, peer, 'tools/call', { name, arguments: name === 'i_recall' ? { query: 'synthetic' } : {} });
      assert.equal(result.body.result.isError, false);
    }
    for (const name of ['capture_add', 'i_remember']) {
      const result = await rpc(ctx, peer, 'tools/call', { name, arguments: {} });
      assert.match(result.body.error.message, /Unknown tool/);
    }
    const result = await rpc(ctx, peer, 'tools/call', { name: 'i_chat_turn',
      arguments: { phase: 'start', turns: [{ role: 'user', content: 'synthetic Sesame turn' }] } });
    assert.equal(result.body.result.isError, false);
    assert.equal(result.body.result.structuredContent.core_status, 'ok');
    assert.deepEqual(ctx.sent.map(m => m.origin_device_id), ['frontend:sesame']);
    assert.match(ctx.sent[0].sync_id, /^sesame:/);
    const refreshed = await postToken(ctx.base, { client_id: peer.client.client_id,
      grant_type: 'refresh_token', refresh_token: peer.refresh_token });
    assert.equal(refreshed.status, 200);
    assert.equal(ctx.oauth.verifyAccessToken('Bearer ' + refreshed.body.access_token).frontend, 'sesame');
    const end = await rpc(ctx, { ...peer, access_token: refreshed.body.access_token }, 'tools/call', { name: 'i_chat_turn',
      arguments: { thread_id: result.body.result.structuredContent.thread_id, phase: 'end',
        turns: [{ role: 'assistant', content: 'synthetic Sesame reply' }] } });
    assert.equal(end.body.result.isError, false);
    assert.deepEqual(ctx.sent.map(m => m.origin_device_id), ['frontend:sesame', 'frontend:sesame']);
    assert.equal(captureCalls, 0);
    assert.equal(noteCalls, 0);
    const originDenied = await mcpPost(ctx.base, refreshed.body.access_token, { jsonrpc: '2.0', id: 3, method: 'ping' },
      { sessionId: peer.sessionId, headers: { Origin: 'https://sesameai.app' } });
    assert.equal(originDenied.status, 403);
  });
}

test('disabled Sesame rejects registration, authorization, pending code, refresh and issued tokens', async t => {
  const ctx = await synthetic(t, { paired: true });
  const peer = await issue(ctx);
  const authorization = await pending(ctx, peer.client);
  const disabled = createApp({ stateDir: ctx.dir, publicUrl: PUBLIC_URL, chatgptEnabled: true,
    sesameEnabled: sesameEnabledFromEnv({ I_REMOTE_MCP_SESAME_ENABLED: '0' }),
    getReadModel: async () => { assert.fail('disabled Sesame must never read data'); } });
  await listenForFetch(disabled.server);
  t.after(() => new Promise(r => disabled.server.close(r)));
  const off = { ...disabled, base: `http://127.0.0.1:${disabled.server.address().port}` };
  for (const uris of [callbacks, ...callbacks.map(uri => [uri])]) assert.equal((await register(off, uris)).status, 400);
  const denied = await fetch(off.base + '/authorize?' + authorization.params, { redirect: 'manual' });
  assert.equal(denied.status, 400);
  assert.equal((await submitPassphrase(off.base, authorization.params)).status, 400);
  for (const fields of [authorization.fields, { client_id: peer.client.client_id,
    grant_type: 'refresh_token', refresh_token: peer.refresh_token }]) {
    const rejected = await postToken(off.base, fields);
    assert.equal(rejected.status, 400);
    assert.equal(rejected.body.error, 'invalid_grant');
    assert.equal(rejected.body.access_token, undefined);
  }
  assert.deepEqual(disabled.oauth.verifyAccessToken('Bearer ' + peer.access_token), { ok: false, error: 'invalid_token' });
  const rpcDenied = await mcpPost(off.base, peer.access_token, { jsonrpc: '2.0', id: 1, method: 'initialize' });
  assert.equal(rpcDenied.status, 401);
  assert.equal(rpcDenied.body.error, 'invalid_token');
});

test('unpaired Sesame never borrows other handlers and pairs into its dedicated credential file', async t => {
  const ctx = await synthetic(t);
  const peer = await issue(ctx);
  Object.assign(peer, await initSession(ctx.base, peer.access_token));
  const result = await rpc(ctx, peer, 'tools/call', { name: 'i_chat_turn',
    arguments: { turns: [{ role: 'user', content: 'synthetic unpaired' }] } });
  assert.equal(result.body.result.isError, true);
  assert.equal(result.body.result.content[0].text, 'frontend_not_paired:sesame');
  assert.deepEqual(ctx.sent, []);
  assert.deepEqual(frontendDefinition('sesame'), { name: 'sesame', deviceId: 'frontend:sesame',
    displayName: 'Sesame', credentialFile: 'core-frontend-sesame.json' });
  const calls = [];
  const fetchImpl = async (_url, options) => {
    calls.push(JSON.parse(options.body));
    return { ok: true, json: async () => ({ device_token: 'synthetic-only-' + calls.length }) };
  };
  for (const frontend of ['claude_web', 'chatgpt_web', 'gemini_web', 'antigravity']) {
    await pairFrontendDevice({ coreUrl: 'https://synthetic.invalid', pairingCode: 'synthetic', stateDir: ctx.dir, frontend, fetchImpl });
    assert.equal(loadFrontendCredential(ctx.dir, 'sesame'), null);
  }
  await pairFrontendDevice({ coreUrl: 'https://synthetic.invalid', pairingCode: 'synthetic',
    stateDir: ctx.dir, frontend: 'sesame', fetchImpl });
  assert.equal(calls[4].device_id, 'frontend:sesame');
  assert.equal(calls[4].display_name, 'Sesame');
  const credential = JSON.parse(readFileSync(join(ctx.dir, 'core-frontend-sesame.json')));
  assert.equal(credential.device_id, 'frontend:sesame');
  assert.equal(loadFrontendCredential(ctx.dir, 'sesame').device_token, 'synthetic-only-5');
  assert.equal(loadFrontendCredential(ctx.dir).device_token, 'synthetic-only-1');
});

test('Sesame diagnostics use a fixed class and never log callback text', async t => {
  const ctx = await synthetic(t);
  for (const uri of callbacks) {
    assert.equal(callbackClass(uri), 'sesame');
    await fetch(ctx.base + '/authorize?redirect_uri=' + encodeURIComponent(uri));
    assert.equal(ctx.records.at(-1).callback_class, 'sesame');
    assert.equal(Object.hasOwn(ctx.records.at(-1), 'callback_shapes'), false);
    assert.equal(ctx.records.at(-1).callback, '[redacted]');
    await register(ctx, [uri]);
    assert.equal(ctx.records.at(-1).callback_class, 'sesame');
    assert.equal(Object.hasOwn(ctx.records.at(-1), 'callback_shapes'), false);
    assert.equal(ctx.records.at(-1).callback_count, 1);
  }
  await register(ctx);
  assert.equal(ctx.records.at(-1).callback_class, 'sesame');
    assert.equal(Object.hasOwn(ctx.records.at(-1), 'callback_shapes'), false);
  assert.equal(ctx.records.at(-1).callback_count, 1);
  assert.equal(Object.hasOwn(ctx.records.at(-1), 'callback_shapes'), false);
  const peer = await issue(ctx);
  await pending(ctx, peer.client);
  const log = JSON.stringify(ctx.records);
  for (const uri of callbacks) assert.ok(!log.includes(uri));
  assert.doesNotMatch(log, /sesameai\.app|external-mcp|arbitrary synthetic client/);
});
