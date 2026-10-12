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

  test('legacy records without an identity remain compatible as claude_web', async () => {
    const { body: claude } = await registerClient(ctx.base, [REDIRECT_URI]);
    const tokens = await authorize(claude, REDIRECT_URI, 'chatgpt_web');
    delete ctx.oauth.store.state.access_tokens[
      Object.keys(ctx.oauth.store.state.access_tokens).find((key) =>
        ctx.oauth.verifyAccessToken(`Bearer ${tokens.access_token}`).ok
          && ctx.oauth.store.state.access_tokens[key].client_id === claude.client_id,
      )
    ].frontend;
    assert.equal(ctx.oauth.verifyAccessToken(`Bearer ${tokens.access_token}`).frontend, 'claude_web');

    const legacyRefresh = Object.values(ctx.oauth.store.state.refresh_tokens)
      .find((record) => record.client_id === claude.client_id && !record.rotated);
    delete legacyRefresh.frontend;
    const refreshed = await postToken(ctx.base, {
      grant_type: 'refresh_token', refresh_token: tokens.refresh_token, client_id: claude.client_id,
    });
    assert.equal(refreshed.status, 200);
    assert.equal(ctx.oauth.verifyAccessToken(`Bearer ${refreshed.body.access_token}`).frontend, 'claude_web');
  });
});
