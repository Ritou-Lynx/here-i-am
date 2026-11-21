import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { APP_CALLBACKS, CHATGPT_CALLBACK_URI, OAuthServer, appEnabledFromEnv,
  frontendForRedirectUri, isAllowedRedirectUri, setPassphrase } from './oauth.mjs';
import { callbackClass, createRequestDiagnostics } from './diagnostics.mjs';
import { PASSPHRASE, PUBLIC_URL, pkcePair, authorizeParams, submitPassphrase, postToken,
  initSession, mcpPost, createFakeReadModel } from './fixtures.mjs';
import { createApp } from './server.mjs';
import { listenForFetch } from './fetch_test_listener.mjs';

const callback = 'http://127.0.0.1:47859/hereiam/i-mcp/callback';
const invalid = ['http://localhost:47859/hereiam/i-mcp/callback',
  'http://127.0.0.1:47860/hereiam/i-mcp/callback', 'https://127.0.0.1:47859/hereiam/i-mcp/callback',
  callback + '/', callback + '?x=1', callback + '#x', 'http://127.0.0.1:47859/hereiam/i-mcp/Callback',
  'http://user@127.0.0.1:47859/hereiam/i-mcp/callback', callback + '?', callback + '#'];

test('App callback is an exact frozen entry and configuration fails closed', () => {
  assert.ok(Object.isFrozen(APP_CALLBACKS));
  assert.deepEqual(APP_CALLBACKS, [callback]);
  assert.equal(frontendForRedirectUri(callback), 'here_i_am_app');
  for (const uri of invalid) assert.equal(frontendForRedirectUri(uri), null);
  assert.equal(isAllowedRedirectUri(callback, true, true, true, true, false), false);
  assert.equal(appEnabledFromEnv({}), true);
  assert.equal(appEnabledFromEnv({ I_REMOTE_MCP_APP_ENABLED: '1' }), true);
  assert.equal(appEnabledFromEnv({ I_REMOTE_MCP_APP_ENABLED: '0' }), false);
  for (const value of ['2', 'true', '', 1, null])
    assert.throws(() => appEnabledFromEnv({ I_REMOTE_MCP_APP_ENABLED: value }), /invalid_app_mode/);
});

test('App authorization and refresh remain read-only and disabling rejects all stages', t => {
  const dir = mkdtempSync(join(tmpdir(), 'app-oauth-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  setPassphrase(dir, PASSPHRASE);
  const config = { stateDir: dir, publicUrl: PUBLIC_URL, writeEnabled: true };
  assert.throws(() => new OAuthServer({ ...config, appEnabled: '1' }), /invalid_app_mode/);
  const oauth = new OAuthServer(config);
  const register = uris => oauth.register({ redirect_uris: uris, scope: 'i.read i.write' });
  for (const uri of invalid) assert.equal(register([uri]).status, 400);
  for (const uris of [[callback, CHATGPT_CALLBACK_URI], [CHATGPT_CALLBACK_URI, callback]])
    assert.equal(register(uris).status, 400);
  const client = register([callback]).body;
  assert.equal(client.scope, 'i.read');
  const { verifier, challenge } = pkcePair();
  const params = { client_id: client.client_id, redirect_uri: callback, response_type: 'code',
    code_challenge: challenge, code_challenge_method: 'S256', scope: 'i.read i.write', passphrase: PASSPHRASE };
  assert.equal(oauth.validateAuthorizeRequest(params).params.granted_scope, 'i.read');
  const code = new URL(oauth.submitPassphrase(params).redirect).searchParams.get('code');
  const pending = new URL(oauth.submitPassphrase(params).redirect).searchParams.get('code');
  const fields = { grant_type: 'authorization_code', client_id: client.client_id,
    redirect_uri: callback, code_verifier: verifier, code };
  const issued = oauth.token(fields);
  assert.equal(issued.status, 200);
  assert.equal(issued.body.scope, 'i.read');
  assert.deepEqual(oauth.verifyAccessToken('Bearer ' + issued.body.access_token).scopes, ['i.read']);
  const refresh = { grant_type: 'refresh_token', client_id: client.client_id, refresh_token: issued.body.refresh_token };
  const off = new OAuthServer({ ...config, appEnabled: false });
  assert.equal(off.register({ redirect_uris: [callback] }).status, 400);
  assert.equal(off.validateAuthorizeRequest(params).ok, false);
  assert.equal(off.submitPassphrase(params).ok, false);
  assert.equal(off.token({ ...fields, code: pending }).body.error, 'invalid_grant');
  assert.equal(off.token(refresh).body.error, 'invalid_grant');
  assert.equal(off.verifyAccessToken('Bearer ' + issued.body.access_token).error, 'invalid_token');
  const refreshed = oauth.token(refresh);
  assert.equal(refreshed.status, 200);
  assert.equal(refreshed.body.scope, 'i.read');
  assert.deepEqual(oauth.verifyAccessToken('Bearer ' + refreshed.body.access_token).scopes, ['i.read']);
});

test('App diagnostics classify callback without exposing its shape or text', () => {
  const records = [];
  assert.equal(callbackClass(callback), 'here_i_am_app');
  const diagnostic = createRequestDiagnostics({ method: 'POST', url: '/register', headers: {} },
    { issuer: PUBLIC_URL, resource: PUBLIC_URL + '/mcp', diagnostic: record => records.push(record) });
  diagnostic.registration([callback], [callback]);
  diagnostic.finish(201);
  assert.equal(records[0].callback_class, 'here_i_am_app');
  assert.equal(Object.hasOwn(records[0], 'callback_shapes'), false);
  assert.ok(!JSON.stringify(records).includes(callback));
});

test('App HTTP OAuth routes only enabled read tools and refreshes', async t => {
  const dir = mkdtempSync(join(tmpdir(), 'app-http-'));
  setPassphrase(dir, PASSPHRASE);
  const records = [];
  const domainTools = { tools: ['food_day', 'food_log', 'week_get'].map(name => ({ name, inputSchema: { type: 'object' } })),
    handlers: { food_day: async () => ({ synthetic: 'food' }), food_log: async () => assert.fail('write handler'),
      week_get: async () => assert.fail('unrelated handler') } };
  const app = createApp({ stateDir: dir, publicUrl: PUBLIC_URL, domainTools,
    getReadModel: async () => createFakeReadModel(), diagnostic: record => records.push(record) });
  await listenForFetch(app.server);
  t.after(async () => { await new Promise(resolve => app.server.close(resolve)); rmSync(dir, { recursive: true, force: true }); });
  const base = `http://127.0.0.1:${app.server.address().port}`;
  const register = async uris => fetch(base + '/register', { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ redirect_uris: uris, scope: 'i.read i.write' }) });
  assert.equal((await register([callback, CHATGPT_CALLBACK_URI])).status, 400);
  const response = await register([callback]);
  assert.equal(response.status, 201);
  const client = await response.json();
  const { verifier, challenge } = pkcePair();
  const params = authorizeParams({ clientId: client.client_id, challenge, redirectUri: callback });
  params.set('scope', 'i.read i.write');
  const authorization = await submitPassphrase(base, params);
  assert.equal(authorization.status, 302);
  const code = new URL(authorization.headers.get('location')).searchParams.get('code');
  const token = await postToken(base, { grant_type: 'authorization_code', client_id: client.client_id,
    redirect_uri: callback, code, code_verifier: verifier, resource: PUBLIC_URL + '/mcp' });
  assert.equal(token.status, 200);
  assert.equal(token.body.scope, 'i.read');
  const session = await initSession(base, token.body.access_token);
  const rpc = (method, params) => mcpPost(base, token.body.access_token,
    { jsonrpc: '2.0', id: 2, method, params }, { sessionId: session.sessionId });
  const listed = await rpc('tools/list');
  assert.deepEqual(listed.body.result.tools.map(tool => tool.name), ['food_day']);
  assert.equal((await rpc('tools/call', { name: 'food_day', arguments: {} })).body.result.isError, false);
  for (const name of ['i_context', 'i_recall', 'i_chat_turn', 'i_remember', 'capture_add', 'week_get',
    'day_get', 'food_log', 'expense_log', 'life_todo', 'study_result']) {
    assert.match((await rpc('tools/call', { name, arguments: {} })).body.error.message, /Unknown tool/);
  }
  const refreshed = await postToken(base, { grant_type: 'refresh_token', client_id: client.client_id, refresh_token: token.body.refresh_token });
  assert.equal(refreshed.status, 200);
  assert.equal(refreshed.body.scope, 'i.read');
  assert.ok(records.some(record => record.callback_class === 'here_i_am_app'));
  assert.ok(records.filter(record => record.callback_class === 'here_i_am_app').every(record => !Object.hasOwn(record, 'callback_shapes')));
  assert.ok(!JSON.stringify(records).includes(callback));
});
