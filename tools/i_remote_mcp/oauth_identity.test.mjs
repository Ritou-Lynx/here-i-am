import assert from 'node:assert/strict';
import { after, before, describe, test } from 'node:test';
import {
  PUBLIC_URL,
  REDIRECT_URI,
  authorizeParams,
  pkcePair,
  postToken,
  registerClient,
  startTestServer,
  submitPassphrase,
} from './fixtures.mjs';
import { CHATGPT_CALLBACK_URI } from './oauth.mjs';

describe('OAuth frontend identity binding', () => {
  let ctx;

  before(async () => { ctx = await startTestServer({ chatgptEnabled: true }); });
  after(() => ctx.close());

  async function authorize(client, redirectUri, claimedFrontend) {
    const { verifier, challenge } = pkcePair();
    const result = await submitPassphrase(ctx.base, authorizeParams({
      clientId: client.client_id,
      challenge,
      redirectUri,
    }));
    assert.equal(result.status, 302);
    const code = new URL(result.headers.get('location')).searchParams.get('code');
    const token = await postToken(ctx.base, {
      grant_type: 'authorization_code',
      code,
      client_id: client.client_id,
      redirect_uri: redirectUri,
      code_verifier: verifier,
      resource: `${PUBLIC_URL}/mcp`,
      frontend: claimedFrontend,
    });
    assert.equal(token.status, 200);
    return token.body;
  }

  test('derives two client identities only from the exact authorized callback', async () => {
    const { body: claude } = await registerClient(ctx.base, [REDIRECT_URI]);
    const { body: chatgpt } = await registerClient(ctx.base, [CHATGPT_CALLBACK_URI]);
    const claudeTokens = await authorize(claude, REDIRECT_URI, 'chatgpt_web');
    const chatgptTokens = await authorize(chatgpt, CHATGPT_CALLBACK_URI, 'claude_web');

    assert.equal(ctx.oauth.verifyAccessToken(`Bearer ${claudeTokens.access_token}`).frontend, 'claude_web');
    assert.equal(ctx.oauth.verifyAccessToken(`Bearer ${chatgptTokens.access_token}`).frontend, 'chatgpt_web');
  });

  test('refresh retains the bound identity and another client cannot use its refresh token', async () => {
    const { body: chatgpt } = await registerClient(ctx.base, [CHATGPT_CALLBACK_URI]);
    const { body: claude } = await registerClient(ctx.base, [REDIRECT_URI]);
    const original = await authorize(chatgpt, CHATGPT_CALLBACK_URI, 'claude_web');
    const stolen = await postToken(ctx.base, {
      grant_type: 'refresh_token', refresh_token: original.refresh_token, client_id: claude.client_id,
      frontend: 'claude_web',
    });
    assert.equal(stolen.status, 400);
    assert.equal(stolen.body.error, 'invalid_grant');

    const refreshed = await postToken(ctx.base, {
      grant_type: 'refresh_token', refresh_token: original.refresh_token, client_id: chatgpt.client_id,
      frontend: 'claude_web',
    });
    assert.equal(refreshed.status, 200);
    assert.equal(ctx.oauth.verifyAccessToken(`Bearer ${refreshed.body.access_token}`).frontend, 'chatgpt_web');
  });

  test('pre-B records derive their fallback from registered callbacks', async () => {
    const accessRecordFor = (clientId) => Object.values(ctx.oauth.store.state.access_tokens)
      .find((record) => record.client_id === clientId && record.frontend !== undefined);
    const refreshRecordFor = (clientId) => Object.values(ctx.oauth.store.state.refresh_tokens)
      .find((record) => record.client_id === clientId && !record.rotated && record.frontend !== undefined);

    async function assertLegacyFallback(redirectUris, issueRedirectUri, expectedFrontend) {
      const { body: client } = await registerClient(ctx.base, redirectUris);
      const tokens = await authorize(client, issueRedirectUri, 'forged_frontend');
      delete accessRecordFor(client.client_id).frontend;
      delete refreshRecordFor(client.client_id).frontend;

      assert.equal(ctx.oauth.verifyAccessToken(`Bearer ${tokens.access_token}`).frontend, expectedFrontend);
      const refreshed = await postToken(ctx.base, {
        grant_type: 'refresh_token', refresh_token: tokens.refresh_token, client_id: client.client_id,
      });
      assert.equal(refreshed.status, 200);
      assert.equal(ctx.oauth.verifyAccessToken(`Bearer ${refreshed.body.access_token}`).frontend, expectedFrontend);
      assert.ok(Object.values(ctx.oauth.store.state.access_tokens)
        .some((record) => record.client_id === client.client_id && record.frontend === expectedFrontend));
      assert.ok(Object.values(ctx.oauth.store.state.refresh_tokens)
        .some((record) => record.client_id === client.client_id && !record.rotated && record.frontend === expectedFrontend));
    }

    await assertLegacyFallback([CHATGPT_CALLBACK_URI], CHATGPT_CALLBACK_URI, 'chatgpt_web');
    await assertLegacyFallback([REDIRECT_URI], REDIRECT_URI, 'claude_web');
    const rejected = await registerClient(ctx.base, [CHATGPT_CALLBACK_URI, REDIRECT_URI]);
    assert.equal(rejected.status, 400);
    assert.equal(rejected.body.error, 'invalid_redirect_uri');
    const { body: client } = await registerClient(ctx.base, [CHATGPT_CALLBACK_URI]);
    const tokens = await authorize(client, CHATGPT_CALLBACK_URI);
    ctx.oauth.store.state.clients[client.client_id].redirect_uris.push(REDIRECT_URI);
    delete accessRecordFor(client.client_id).frontend;
    delete refreshRecordFor(client.client_id).frontend;
    assert.deepEqual(ctx.oauth.verifyAccessToken(`Bearer ${tokens.access_token}`), { ok: false, error: 'invalid_token' });
    const refreshed = await postToken(ctx.base, {
      grant_type: 'refresh_token', refresh_token: tokens.refresh_token, client_id: client.client_id,
    });
    assert.equal(refreshed.status, 400);
    assert.equal(refreshed.body.error, 'invalid_grant');
  });
});

import { sha256 } from './oauth.mjs';
import { mcpPost, obtainTokens } from './fixtures.mjs';

describe('D1 registry rejects ambiguous and invalid identities', () => {
  let ctx;
  before(async () => { ctx = await startTestServer({ chatgptEnabled: true }); });
  after(() => ctx.close());

  const records = (tokens) => [
    ctx.oauth.store.state.access_tokens[sha256(tokens.access_token)],
    ctx.oauth.store.state.refresh_tokens[sha256(tokens.refresh_token)],
  ];

  async function assertRejected(tokens) {
    assert.deepEqual(ctx.oauth.verifyAccessToken(`Bearer ${tokens.access_token}`), { ok: false, error: 'invalid_token' });
    const rpc = await mcpPost(ctx.base, tokens.access_token, {
      jsonrpc: '2.0', id: 1, method: 'initialize',
      params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'synthetic', version: '1' } },
    });
    assert.equal(rpc.status, 401);
    assert.equal(rpc.body.error, 'invalid_token');
    assert.equal(rpc.headers.get('mcp-session-id'), null);
    assert.deepEqual(ctx.readModel.calls, []);
    const refreshed = await postToken(ctx.base, {
      grant_type: 'refresh_token', refresh_token: tokens.refresh_token, client_id: tokens.client.client_id,
    });
    assert.equal(refreshed.status, 400);
    assert.equal(refreshed.body.error, 'invalid_grant');
    assert.equal(refreshed.body.access_token, undefined);
    assert.equal(records(tokens)[1].rotated, false);
  }

  for (const frontend of ['sesame', '', 'Claude_web', null, 'constructor', '__proto__']) {
    test(`rejects explicit invalid frontend ${JSON.stringify(frontend)} before RPC and refresh`, async () => {
      const tokens = await obtainTokens(ctx.base);
      for (const record of records(tokens)) record.frontend = frontend;
      await assertRejected(tokens);
    });
  }

  for (const redirectUris of [[], ['https://unknown.example/callback'], [REDIRECT_URI, 'https://unknown.example/callback'], [REDIRECT_URI, CHATGPT_CALLBACK_URI]]) {
    test(`legacy records reject ambiguous or unknown callbacks ${JSON.stringify(redirectUris)}`, async () => {
      const tokens = await obtainTokens(ctx.base);
      for (const record of records(tokens)) delete record.frontend;
      ctx.oauth.store.state.clients[tokens.client.client_id].redirect_uris = redirectUris;
      await assertRejected(tokens);
    });
  }

  test('legacy Claude accepts both registered Claude callbacks', async () => {
    const tokens = await obtainTokens(ctx.base);
    for (const record of records(tokens)) delete record.frontend;
    ctx.oauth.store.state.clients[tokens.client.client_id].redirect_uris.push('https://claude.com/api/mcp/auth_callback');
    assert.equal(ctx.oauth.verifyAccessToken(`Bearer ${tokens.access_token}`).frontend, 'claude_web');
    const refreshed = await postToken(ctx.base, {
      grant_type: 'refresh_token', refresh_token: tokens.refresh_token, client_id: tokens.client.client_id,
    });
    assert.equal(refreshed.status, 200);
    assert.equal(ctx.oauth.verifyAccessToken(`Bearer ${refreshed.body.access_token}`).frontend, 'claude_web');
  });

  for (const legacy of [false, true]) {
    test(`ChatGPT identity requires enabled frontend, legacy=${legacy}`, async () => {
      const tokens = await obtainTokens(ctx.base);
      ctx.oauth.store.state.clients[tokens.client.client_id].redirect_uris = [CHATGPT_CALLBACK_URI];
      for (const record of records(tokens)) {
        if (legacy) delete record.frontend;
        else record.frontend = 'chatgpt_web';
      }
      ctx.oauth.chatgptEnabled = false;
      try { await assertRejected(tokens); }
      finally { ctx.oauth.chatgptEnabled = true; }
    });
  }
});
