import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { createApp } from './server.mjs';
import { OAuthServer, FRONTEND_CALLBACKS, FRONTEND_CALLBACK_PATTERNS, CHATGPT_CALLBACK_URI,
  frontendForRedirectUri, geminiEnabledFromEnv, isAllowedRedirectUri, setPassphrase } from './oauth.mjs';
import { callbackClass } from './diagnostics.mjs';
import { createWriteback, openLedger, pairFrontendDevice, loadFrontendCredential } from './writeback.mjs';
import { listenForFetch } from './fetch_test_listener.mjs';
import { authorizeParams, createFakeReadModel, initSession, mcpPost, pkcePair,
  PUBLIC_URL, REDIRECT_URI, PASSPHRASE, submitPassphrase } from './fixtures.mjs';

const hosts = ['oauth-redirect.googleusercontent.com', 'oauth-redirect-sandbox.googleusercontent.com'];
const callback = (id = 'synthetic-123', host = hosts[0]) => `https://${host}/r/user_bound_custom-mcp-${id}`;
const valid = [callback('A'), callback('b-2'), callback('C', hosts[1]), callback('D', hosts[1])];
// Google 把 MCP 主机名中的点换成下划线拼在编号后面（10-23 真人验收实测形状，编号为合成值）。
const observed = callback('100000000000000000001-i_example_test');
const invalid = [
  callback('A', `evil-${hosts[0]}`), callback('A', `${hosts[0]}.evil.example`),
  callback().replace('https:', 'http:'), callback().replace(hosts[0], `${hosts[0]}:443`),
  callback().replace(hosts[0], `${hosts[0]}:8443`), callback() + '?q=1', callback() + '#frag',
  callback() + '?', callback() + '#', callback().replace('/r/', '/R/'),
  callback().replace('user_bound_custom-mcp-', 'User_bound_custom-mcp-'),
  `https://${hosts[0]}/r/other-project`, callback(''), callback('a'.repeat(201)),
  callback().replace(hosts[0], `user:password@${hosts[0]}`),
  callback('%41'), callback().replace('/r/', '/other/../r/'),
];

async function synthetic(t, options = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'synthetic-gemini-'));
  const records = [], sent = [], writers = [];
  const writer = frontend => {
    const wb = createWriteback({ frontend, ledger: openLedger(join(dir, 'ledger.sqlite')),
      coreClient: { async submit(messages) {
        sent.push(...messages);
        return messages.map(m => ({ sync_id: m.sync_id, status: 'accepted', server_sequence: sent.length }));
      } } });
    writers.push(wb); return wb;
  };
  setPassphrase(dir, PASSPHRASE);
  const app = createApp({ stateDir: dir, publicUrl: PUBLIC_URL,
    getReadModel: async () => createFakeReadModel(), identityLoader: () => ({}),
    chatgptEnabled: true, diagnostic: record => records.push(record),
    writeback: writer('claude_web'),
    ...(options.paired ? { geminiWriteback: writer('gemini_web') } : {}),
    ...options.app });
  t.after(async () => {
    if (app.server.listening) await new Promise(r => app.server.close(r));
    for (const wb of writers) wb.close();
    rmSync(dir, { recursive: true, force: true });
  });
  await listenForFetch(app.server);
  return { ...app, dir, records, sent, base: `http://127.0.0.1:${app.server.address().port}` };
}

async function register(ctx, redirectUris = [callback()], authMethod = 'client_secret_basic') {
  const response = await fetch(ctx.base + '/register', { method: 'POST',
    headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({
      redirect_uris: redirectUris, token_endpoint_auth_method: authMethod, scope: 'i.read i.write offline_access',
    }) });
  return { status: response.status, body: await response.json() };
}

async function pending(ctx, client, redirectUri = callback()) {
  const { verifier, challenge } = pkcePair();
  const params = authorizeParams({ clientId: client.client_id, challenge, redirectUri });
  params.set('scope', 'i.read i.write offline_access');
  const response = await submitPassphrase(ctx.base, params);
  assert.equal(response.status, 302);
  const location = new URL(response.headers.get('location'));
  assert.equal(location.origin, new URL(redirectUri).origin);
  assert.equal(location.searchParams.get('iss'), PUBLIC_URL);
  return { params, fields: { grant_type: 'authorization_code', code: location.searchParams.get('code'),
    redirect_uri: redirectUri, code_verifier: verifier, resource: PUBLIC_URL + '/mcp' } };
}

async function token(ctx, client, fields, method = 'client_secret_basic') {
  const response = await fetch(ctx.base + '/token', { method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', ...(method === 'client_secret_basic'
      ? { Authorization: 'Basic ' + Buffer.from(client.client_id + ':synthetic-secret').toString('base64') } : {}) },
    body: new URLSearchParams({ ...fields, ...(method === 'client_secret_post'
      ? { client_id: client.client_id, client_secret: 'synthetic-secret' } : {}) }) });
  return { status: response.status, body: await response.json() };
}

async function issue(ctx, method = 'client_secret_basic') {
  const registered = await register(ctx, [callback()], method);
  assert.equal(registered.status, 201);
  assert.equal(registered.body.token_endpoint_auth_method, 'none');
  const authorization = await pending(ctx, registered.body);
  const issued = await token(ctx, registered.body, authorization.fields, method);
  assert.equal(issued.status, 200);
  return { client: registered.body, ...issued.body };
}

const rpc = (ctx, peer, method, params) => mcpPost(ctx.base, peer.access_token,
  { jsonrpc: '2.0', id: 2, method, params }, { sessionId: peer.sessionId });

test('Gemini callback patterns accept only canonical HTTPS relays and never overlap exact callbacks', () => {
  for (const uri of [...valid, observed, callback('a'.repeat(200))]) {
    assert.equal(frontendForRedirectUri(uri), 'gemini_web', uri);
    assert.equal(isAllowedRedirectUri(uri, false, true), true);
    assert.equal(isAllowedRedirectUri(uri, true, false), false);
  }
  for (const uri of [...invalid, null, undefined, 42, {}, '']) {
    assert.equal(frontendForRedirectUri(uri), null, String(uri));
    assert.equal(isAllowedRedirectUri(uri, true, true), false);
  }
  for (const uri of [...valid, ...invalid, ...Object.values(FRONTEND_CALLBACKS).flat()]) {
    const matches = Object.values(FRONTEND_CALLBACKS).filter(uris => uris.includes(uri)).length
      + Object.values(FRONTEND_CALLBACK_PATTERNS).filter(match => match(uri)).length;
    assert.ok(matches <= 1, uri);
  }
});

test('Gemini registers the observed underscore host-slug callback', async t => {
  const ctx = await synthetic(t);
  const registered = await register(ctx, [observed]);
  assert.equal(registered.status, 201);
  assert.deepEqual(registered.body.redirect_uris, [observed]);
});

test('Gemini registers six callbacks by keeping only four valid entries; exact frontend rules stay strict', async t => {
  const ctx = await synthetic(t);
  const registered = await register(ctx, [invalid[0], valid[0], valid[1], invalid[1], valid[2], valid[3]]);
  assert.equal(registered.status, 201);
  assert.deepEqual(registered.body.redirect_uris, valid);
  assert.deepEqual(ctx.oauth.store.state.clients[registered.body.client_id].redirect_uris, valid);
  const persisted = JSON.parse(readFileSync(join(ctx.dir, 'oauth.json')));
  assert.deepEqual(persisted.clients[registered.body.client_id].redirect_uris, valid);
  assert.equal((await register(ctx, Array.from({ length: 8 }, (_, i) => callback('id-' + i)))).status, 201);
  for (const uris of [invalid.slice(0, 2), invalid, [], [valid[0], REDIRECT_URI], [CHATGPT_CALLBACK_URI, valid[0]],
    [REDIRECT_URI, valid[0]], [valid[0], CHATGPT_CALLBACK_URI],
    Array(9).fill(valid[0]), Array(6).fill(REDIRECT_URI), Array(6).fill(CHATGPT_CALLBACK_URI),
    [REDIRECT_URI, invalid[0]], [CHATGPT_CALLBACK_URI, invalid[0]]]) {
    const rejected = await register(ctx, uris);
    assert.equal(rejected.status, 400);
    assert.equal(rejected.body.error, 'invalid_redirect_uri');
  }
  for (const uri of [REDIRECT_URI, CHATGPT_CALLBACK_URI]) assert.equal((await register(ctx, Array(5).fill(uri))).status, 201);
  const rejectedAuthorization = await fetch(ctx.base + '/authorize?' + authorizeParams({
    clientId: registered.body.client_id, challenge: pkcePair().challenge, redirectUri: invalid[0],
  }), { redirect: 'manual' });
  assert.equal(rejectedAuthorization.status, 400);
});

test('Gemini mode defaults on, accepts only 0/1, and rejects invalid startup options', async t => {
  assert.equal(geminiEnabledFromEnv({}), true);
  assert.equal(geminiEnabledFromEnv({ I_REMOTE_MCP_GEMINI_ENABLED: '1' }), true);
  assert.equal(geminiEnabledFromEnv({ I_REMOTE_MCP_GEMINI_ENABLED: '0' }), false);
  for (const value of ['2', 'true', '', 'false', ' 1', 1, null]) {
    assert.throws(() => geminiEnabledFromEnv({ I_REMOTE_MCP_GEMINI_ENABLED: value }), /invalid_gemini_mode/);
  }
  const ctx = await synthetic(t);
  for (const value of ['0', 'true', 1, null]) {
    assert.throws(() => new OAuthServer({ stateDir: ctx.dir, publicUrl: PUBLIC_URL,
      geminiEnabled: value }), /invalid_gemini_mode/);
    assert.throws(() => createApp({ stateDir: ctx.dir, publicUrl: PUBLIC_URL,
      getReadModel: async () => createFakeReadModel(), geminiEnabled: value }), /invalid_gemini_mode/);
  }
});

for (const method of ['client_secret_basic', 'client_secret_post']) {
  test(`Gemini ${method} and offline_access complete OAuth, dedicated RPC writeback and refresh`, async t => {
    let captureCalls = 0, noteCalls = 0;
    const domainTools = { tools: ['capture_add', 'week_get', 'day_get'].map(name => ({ name, inputSchema: { type: 'object' } })),
      handlers: { capture_add: async () => { captureCalls++; }, week_get: async () => ({ synthetic: 'week' }),
        day_get: async () => ({ synthetic: 'day' }) } };
    const coreRemember = { activeNotes: async () => { noteCalls++; return []; },
      searchNotes: async () => { noteCalls++; return []; }, remember: async () => { noteCalls++; } };
    const ctx = await synthetic(t, { paired: true, app: { domainTools, coreRemember } });
    const peer = await issue(ctx, method);
    assert.equal(ctx.oauth.verifyAccessToken('Bearer ' + peer.access_token).frontend, 'gemini_web');
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
      arguments: { phase: 'start', turns: [{ role: 'user', content: 'synthetic Gemini turn' }] } });
    assert.equal(result.body.result.isError, false);
    assert.equal(result.body.result.structuredContent.core_status, 'ok');
    assert.deepEqual(ctx.sent.map(m => m.origin_device_id), ['frontend:gemini_web']);
    assert.match(ctx.sent[0].sync_id, /^gemini_web:/);
    assert.equal(captureCalls, 0); assert.equal(noteCalls, 0);
    const refreshed = await token(ctx, peer.client, { grant_type: 'refresh_token', refresh_token: peer.refresh_token }, method);
    assert.equal(refreshed.status, 200);
    assert.equal(ctx.oauth.verifyAccessToken('Bearer ' + refreshed.body.access_token).frontend, 'gemini_web');
    const end = await rpc(ctx, { ...peer, access_token: refreshed.body.access_token }, 'tools/call', { name: 'i_chat_turn',
      arguments: { thread_id: result.body.result.structuredContent.thread_id, phase: 'end',
        turns: [{ role: 'assistant', content: 'synthetic Gemini reply' }] } });
    assert.equal(end.body.result.isError, false);
    assert.deepEqual(ctx.sent.map(m => m.origin_device_id), ['frontend:gemini_web', 'frontend:gemini_web']);
    assert.equal(captureCalls, 0); assert.equal(noteCalls, 0);
    const originDenied = await mcpPost(ctx.base, refreshed.body.access_token, { jsonrpc: '2.0', id: 3, method: 'ping' },
      { sessionId: peer.sessionId, headers: { Origin: 'https://gemini.google.com' } });
    assert.equal(originDenied.status, 403);
  });
}

test('Gemini disabled rejects registration, authorization, pending exchange, refresh and previously issued access tokens', async t => {
  const ctx = await synthetic(t, { paired: true });
  const peer = await issue(ctx);
  const authorization = await pending(ctx, peer.client);
  // Reopen the same synthetic OAuth state with the switch off, as at service restart.
  const disabled = createApp({ stateDir: ctx.dir, publicUrl: PUBLIC_URL, chatgptEnabled: true,
    geminiEnabled: geminiEnabledFromEnv({ I_REMOTE_MCP_GEMINI_ENABLED: '0' }),
    getReadModel: async () => { assert.fail('disabled Gemini must never read data'); } });
  await listenForFetch(disabled.server);
  t.after(() => new Promise(r => disabled.server.close(r)));
  const off = { ...disabled, base: `http://127.0.0.1:${disabled.server.address().port}` };
  assert.equal((await register(off)).status, 400);
  const denied = await fetch(off.base + '/authorize?' + authorization.params, { redirect: 'manual' });
  assert.equal(denied.status, 400);
  assert.equal((await submitPassphrase(off.base, authorization.params)).status, 400);
  for (const fields of [authorization.fields, { grant_type: 'refresh_token', refresh_token: peer.refresh_token }]) {
    const rejected = await token(off, peer.client, fields, 'client_secret_post');
    assert.equal(rejected.status, 400);
    assert.equal(rejected.body.access_token, undefined);
  }
  const basicRejected = await token(off, peer.client, authorization.fields);
  assert.equal(basicRejected.status, 401); // Disabled public client cannot be recovered from a Basic header.
  assert.deepEqual(disabled.oauth.verifyAccessToken('Bearer ' + peer.access_token), { ok: false, error: 'invalid_token' });
  const rpcDenied = await mcpPost(off.base, peer.access_token, { jsonrpc: '2.0', id: 1, method: 'initialize' });
  assert.equal(rpcDenied.status, 401);
  assert.equal(rpcDenied.body.error, 'invalid_token');
});

test('unpaired Gemini never borrows Claude credentials or its writeback handler', async t => {
  const ctx = await synthetic(t);
  const peer = await issue(ctx);
  Object.assign(peer, await initSession(ctx.base, peer.access_token));
  const result = await rpc(ctx, peer, 'tools/call', { name: 'i_chat_turn',
    arguments: { turns: [{ role: 'user', content: 'synthetic unpaired' }] } });
  assert.equal(result.body.result.isError, true);
  assert.equal(result.body.result.content[0].text, 'frontend_not_paired:gemini_web');
  assert.deepEqual(ctx.sent, []);
  const calls = [];
  const fetchImpl = async (_url, options) => {
    calls.push(JSON.parse(options.body));
    return { ok: true, json: async () => ({ device_token: 'synthetic-only-' + calls.length }) };
  };
  await pairFrontendDevice({ coreUrl: 'https://synthetic.invalid', pairingCode: 'synthetic', stateDir: ctx.dir, fetchImpl });
  assert.equal(loadFrontendCredential(ctx.dir, 'gemini_web'), null);
  await pairFrontendDevice({ coreUrl: 'https://synthetic.invalid', pairingCode: 'synthetic',
    stateDir: ctx.dir, frontend: 'gemini_web', fetchImpl });
  assert.equal(calls[1].device_id, 'frontend:gemini_web');
  assert.equal(calls[1].display_name, 'Gemini 网页端');
  const credential = JSON.parse(readFileSync(join(ctx.dir, 'core-frontend-gemini_web.json')));
  assert.equal(credential.device_id, 'frontend:gemini_web');
  assert.equal(loadFrontendCredential(ctx.dir, 'gemini_web').device_token, 'synthetic-only-2');
  assert.equal(loadFrontendCredential(ctx.dir).device_token, 'synthetic-only-1');
});

test('Gemini diagnostics classify callbacks and counts without exposing relay paths or identifiers', async t => {
  const ctx = await synthetic(t);
  const cases = [[REDIRECT_URI, 'claude'], [CHATGPT_CALLBACK_URI, 'chatgpt'],
    [callback(), 'gemini_pattern'], [`https://${hosts[1]}/r/other-secret`, 'google_relay_other'],
    ['https://unknown.invalid/private-path', 'other'], [undefined, 'absent']];
  for (const [uri, expected] of cases) {
    assert.equal(callbackClass(uri), expected);
    const query = uri === undefined ? '' : '?redirect_uri=' + encodeURIComponent(uri);
    await fetch(ctx.base + '/authorize' + query);
    assert.equal(ctx.records.at(-1).callback_class, expected);
    if (expected === 'gemini_pattern') assert.equal(ctx.records.at(-1).callback, '[redacted]');
    await register(ctx, uri === undefined ? [] : [uri]);
    assert.equal(ctx.records.at(-1).callback_class, expected);
    assert.equal(ctx.records.at(-1).callback_count, uri === undefined ? 0 : 1);
    assert.equal(ctx.records.at(-1).gemini_kept_count, expected === 'gemini_pattern' ? 1 : 0);
  }
  await register(ctx, [invalid[0], ...valid, invalid[1]]);
  assert.equal(ctx.records.at(-1).callback_class, 'gemini_pattern');
  assert.equal(ctx.records.at(-1).callback_count, 6);
  assert.equal(ctx.records.at(-1).gemini_kept_count, 4);
  await register(ctx, [valid[0], REDIRECT_URI]);
  assert.equal(ctx.records.at(-1).gemini_kept_count, 0);
  const log = JSON.stringify(ctx.records);
  assert.doesNotMatch(log, /user_bound_custom-mcp|synthetic-123|other-secret|private-path|unknown\.invalid/);
  for (const host of hosts) assert.ok(!log.includes(host));
});
