import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { after, before, describe, test } from 'node:test';
import {
  PASSPHRASE,
  PUBLIC_URL,
  REDIRECT_URI,
  authorizeParams,
  initSession,
  mcpPost,
  obtainTokens,
  pkcePair,
  postToken,
  registerClient,
  startTestServer,
  submitPassphrase,
} from './fixtures.mjs';

describe('发现与未授权访问', () => {
  let ctx;
  before(async () => { ctx = await startTestServer(); });
  after(() => ctx.close());

  test('两个 well-known 元数据端点', async () => {
    const pr = await (await fetch(`${ctx.base}/.well-known/oauth-protected-resource`)).json();
    assert.equal(pr.resource, `${PUBLIC_URL}/mcp`);
    assert.deepEqual(pr.authorization_servers, [PUBLIC_URL]);
    const prPath = await (await fetch(`${ctx.base}/.well-known/oauth-protected-resource/mcp`)).json();
    assert.deepEqual(prPath, pr);
    const as = await (await fetch(`${ctx.base}/.well-known/oauth-authorization-server`)).json();
    assert.equal(as.issuer, PUBLIC_URL);
    assert.equal(as.registration_endpoint, `${PUBLIC_URL}/register`);
    assert.deepEqual(as.code_challenge_methods_supported, ['S256']);
    assert.deepEqual(as.grant_types_supported, ['authorization_code', 'refresh_token']);
    assert.ok(as.token_endpoint_auth_methods_supported.includes('none'));
  });

  test('无令牌访问 /mcp 返回 401 与 WWW-Authenticate', async () => {
    const r = await mcpPost(ctx.base, null, { jsonrpc: '2.0', id: 1, method: 'tools/list' });
    assert.equal(r.status, 401);
    const header = r.headers.get('www-authenticate');
    assert.match(header, /^Bearer /);
    assert.match(header, new RegExp(`resource_metadata="${PUBLIC_URL}/.well-known/oauth-protected-resource"`));
    assert.doesNotMatch(r.text, /三花|猫咪/);
  });

  test('伪造令牌返回 401 invalid_token', async () => {
    const r = await mcpPost(ctx.base, 'iat_forged', { jsonrpc: '2.0', id: 1, method: 'tools/list' });
    assert.equal(r.status, 401);
    assert.match(r.headers.get('www-authenticate'), /error="invalid_token"/);
  });

  test('GET/DELETE /mcp 未授权同样 401', async () => {
    assert.equal((await fetch(`${ctx.base}/mcp`)).status, 401);
    assert.equal((await fetch(`${ctx.base}/mcp`, { method: 'DELETE' })).status, 401);
  });
});

describe('完整 OAuth 流程', () => {
  let ctx;
  before(async () => { ctx = await startTestServer(); });
  after(() => ctx.close());

  test('注册 → 口令页 → 授权码 → 令牌 → MCP → 刷新轮换', async () => {
    const reg = await registerClient(ctx.base);
    assert.equal(reg.status, 201);
    assert.equal(reg.body.token_endpoint_auth_method, 'none');
    assert.deepEqual(reg.body.redirect_uris, [REDIRECT_URI]);
    assert.equal(reg.body.client_secret, undefined);

    const { verifier, challenge } = pkcePair();
    const params = authorizeParams({ clientId: reg.body.client_id, challenge });
    const page = await fetch(`${ctx.base}/authorize?${params}`);
    assert.equal(page.status, 200);
    const html = await page.text();
    assert.match(html, /type="password"/);
    assert.match(html, /claude\.ai/);
    assert.equal(page.headers.get('x-frame-options'), 'DENY');

    const res = await submitPassphrase(ctx.base, params);
    assert.equal(res.status, 302);
    const location = new URL(res.headers.get('location'));
    assert.equal(`${location.origin}${location.pathname}`, REDIRECT_URI);
    assert.equal(location.searchParams.get('state'), 'st-123');
    assert.equal(location.searchParams.get('iss'), PUBLIC_URL);
    const code = location.searchParams.get('code');
    assert.ok(code);

    const tok = await postToken(ctx.base, {
      grant_type: 'authorization_code', code, client_id: reg.body.client_id,
      redirect_uri: REDIRECT_URI, code_verifier: verifier, resource: `${PUBLIC_URL}/mcp`,
    });
    assert.equal(tok.status, 200);
    assert.equal(tok.headers.get('cache-control'), 'no-store');
    assert.equal(tok.body.token_type, 'Bearer');
    assert.equal(tok.body.expires_in, 3600);
    assert.ok(tok.body.access_token && tok.body.refresh_token);

    const { init, sessionId } = await initSession(ctx.base, tok.body.access_token);
    assert.equal(init.status, 200);
    assert.ok(sessionId);
    const list = await mcpPost(ctx.base, tok.body.access_token, { jsonrpc: '2.0', id: 2, method: 'tools/list' }, { sessionId });
    assert.equal(list.status, 200);
    assert.deepEqual(list.body.result.tools.map((t) => t.name), ['i_context', 'i_recall']);

    const refreshed = await postToken(ctx.base, {
      grant_type: 'refresh_token', refresh_token: tok.body.refresh_token, client_id: reg.body.client_id,
    });
    assert.equal(refreshed.status, 200);
    assert.notEqual(refreshed.body.refresh_token, tok.body.refresh_token);
    assert.notEqual(refreshed.body.access_token, tok.body.access_token);
    const s2 = await initSession(ctx.base, refreshed.body.access_token);
    assert.equal(s2.init.status, 200);
    // 同一令牌家族内，刷新后的 access token 可以继续使用原会话。
    const ping = await mcpPost(ctx.base, refreshed.body.access_token, { jsonrpc: '2.0', id: 3, method: 'ping' }, { sessionId });
    assert.equal(ping.status, 200);
    assert.deepEqual(ping.body.result, {});
  });

  test('状态文件只存哈希，不含明文令牌、授权码或口令', async () => {
    const t = await obtainTokens(ctx.base);
    const raw = readFileSync(join(ctx.stateDir, 'oauth.json'), 'utf8');
    for (const secret of [t.access_token, t.refresh_token, t.code, PASSPHRASE, t.verifier]) {
      assert.ok(!raw.includes(secret), 'state file leaks a secret');
    }
  });
});

describe('安全失败分支', () => {
  let ctx;
  before(async () => {
    ctx = await startTestServer({ oauthOptions: { maxPassphraseFailures: 3, lockoutMs: 60_000 } });
  });
  after(() => ctx.close());

  async function codeFor(clientId, challenge, redirectUri = REDIRECT_URI) {
    const res = await submitPassphrase(ctx.base, authorizeParams({ clientId, challenge, redirectUri }));
    assert.equal(res.status, 302);
    return new URL(res.headers.get('location')).searchParams.get('code');
  }

  test('错误口令不签发授权码，连续失败后限速（正确口令也被拒）', async () => {
    const { body: client } = await registerClient(ctx.base);
    const { challenge } = pkcePair();
    const params = authorizeParams({ clientId: client.client_id, challenge });
    for (let i = 0; i < 3; i += 1) {
      const res = await submitPassphrase(ctx.base, params, 'wrong passphrase!!');
      assert.equal(res.status, 401);
      assert.equal(res.headers.get('location'), null);
      assert.match(await res.text(), /口令不正确/);
    }
    const locked = await submitPassphrase(ctx.base, params, PASSPHRASE);
    assert.equal(locked.status, 429);
    assert.equal(locked.headers.get('location'), null);
    ctx.clock.t += 60_001;
    const ok = await submitPassphrase(ctx.base, params, PASSPHRASE);
    assert.equal(ok.status, 302);
  });

  test('PKCE：verifier 不匹配被拒；非 S256 不签发', async () => {
    const { body: client } = await registerClient(ctx.base);
    const { challenge } = pkcePair();
    const code = await codeFor(client.client_id, challenge);
    const bad = await postToken(ctx.base, {
      grant_type: 'authorization_code', code, client_id: client.client_id,
      redirect_uri: REDIRECT_URI, code_verifier: pkcePair().verifier,
    });
    assert.equal(bad.status, 400);
    assert.equal(bad.body.error, 'invalid_grant');
    assert.equal(bad.body.access_token, undefined);

    const missing = await postToken(ctx.base, {
      grant_type: 'authorization_code', code, client_id: client.client_id, redirect_uri: REDIRECT_URI,
    });
    assert.equal(missing.body.error, 'invalid_grant');

    const plain = await submitPassphrase(ctx.base, authorizeParams({ clientId: client.client_id, challenge: 'a'.repeat(43), method: 'plain' }));
    assert.equal(plain.status, 302);
    const loc = new URL(plain.headers.get('location'));
    assert.equal(loc.searchParams.get('error'), 'invalid_request');
    assert.equal(loc.searchParams.get('code'), null);
  });

  test('redirect_uri 篡改：授权页与令牌端点都拒绝，注册只收 https', async () => {
    const { body: client } = await registerClient(ctx.base);
    const { verifier, challenge } = pkcePair();
    const evil = 'https://evil.example/cb';
    const page = await fetch(`${ctx.base}/authorize?${authorizeParams({ clientId: client.client_id, challenge, redirectUri: evil })}`, { redirect: 'manual' });
    assert.equal(page.status, 400);
    assert.equal(page.headers.get('location'), null);
    const post = await submitPassphrase(ctx.base, authorizeParams({ clientId: client.client_id, challenge, redirectUri: evil }));
    assert.equal(post.status, 400);
    assert.equal(post.headers.get('location'), null);

    const code = await codeFor(client.client_id, challenge);
    const swapped = await postToken(ctx.base, {
      grant_type: 'authorization_code', code, client_id: client.client_id,
      redirect_uri: 'https://claude.ai/api/mcp/auth_callback2', code_verifier: verifier,
    });
    assert.equal(swapped.body.error, 'invalid_grant');

    for (const uri of ['http://claude.ai/api/mcp/auth_callback', 'javascript:alert(1)', 'not a url']) {
      const reg = await registerClient(ctx.base, [uri]);
      assert.equal(reg.status, 400, uri);
      assert.equal(reg.body.error, 'invalid_redirect_uri');
    }
  });

  test('授权码不能被另一个 client 使用', async () => {
    const { body: a } = await registerClient(ctx.base);
    const { body: b } = await registerClient(ctx.base);
    const { verifier, challenge } = pkcePair();
    const code = await codeFor(a.client_id, challenge);
    const r = await postToken(ctx.base, {
      grant_type: 'authorization_code', code, client_id: b.client_id, redirect_uri: REDIRECT_URI, code_verifier: verifier,
    });
    assert.equal(r.body.error, 'invalid_grant');
  });

  test('授权码重放：第二次被拒，且第一次签发的令牌被吊销', async () => {
    const t = await obtainTokens(ctx.base);
    const replay = await postToken(ctx.base, {
      grant_type: 'authorization_code', code: t.code, client_id: t.client.client_id,
      redirect_uri: REDIRECT_URI, code_verifier: t.verifier,
    });
    assert.equal(replay.body.error, 'invalid_grant');
    const r = await mcpPost(ctx.base, t.access_token, { jsonrpc: '2.0', id: 1, method: 'initialize', params: {} });
    assert.equal(r.status, 401);
  });

  test('过期：access token、授权码、refresh token', async () => {
    const t = await obtainTokens(ctx.base);
    ctx.clock.t += 3600 * 1000;
    const r = await mcpPost(ctx.base, t.access_token, { jsonrpc: '2.0', id: 1, method: 'initialize', params: {} });
    assert.equal(r.status, 401);
    assert.match(r.headers.get('www-authenticate'), /error="invalid_token"/);
    // 过期后仍可用 refresh token 续期。
    const refreshed = await postToken(ctx.base, { grant_type: 'refresh_token', refresh_token: t.refresh_token, client_id: t.client.client_id });
    assert.equal(refreshed.status, 200);

    const { body: client } = await registerClient(ctx.base);
    const { verifier, challenge } = pkcePair();
    const code = await codeFor(client.client_id, challenge);
    ctx.clock.t += 5 * 60 * 1000;
    const expiredCode = await postToken(ctx.base, {
      grant_type: 'authorization_code', code, client_id: client.client_id, redirect_uri: REDIRECT_URI, code_verifier: verifier,
    });
    assert.equal(expiredCode.body.error, 'invalid_grant');

    ctx.clock.t += 30 * 24 * 3600 * 1000;
    const expiredRefresh = await postToken(ctx.base, { grant_type: 'refresh_token', refresh_token: refreshed.body.refresh_token, client_id: t.client.client_id });
    assert.equal(expiredRefresh.status, 400);
    assert.equal(expiredRefresh.body.error, 'invalid_grant');
  });

  test('已轮换的 refresh token 被重放：拒绝并吊销整个令牌家族', async () => {
    const t = await obtainTokens(ctx.base);
    const r1 = await postToken(ctx.base, { grant_type: 'refresh_token', refresh_token: t.refresh_token, client_id: t.client.client_id });
    assert.equal(r1.status, 200);
    const replay = await postToken(ctx.base, { grant_type: 'refresh_token', refresh_token: t.refresh_token, client_id: t.client.client_id });
    assert.equal(replay.status, 400);
    assert.equal(replay.body.error, 'invalid_grant');
    // 合法持有者手里的新令牌也随之失效。
    const r2 = await postToken(ctx.base, { grant_type: 'refresh_token', refresh_token: r1.body.refresh_token, client_id: t.client.client_id });
    assert.equal(r2.body.error, 'invalid_grant');
    const m = await mcpPost(ctx.base, r1.body.access_token, { jsonrpc: '2.0', id: 1, method: 'initialize', params: {} });
    assert.equal(m.status, 401);
  });

  test('其他令牌端点错误：未知 client、未知 grant、错误 resource', async () => {
    const t = await obtainTokens(ctx.base);
    const unknown = await postToken(ctx.base, { grant_type: 'refresh_token', refresh_token: t.refresh_token, client_id: 'client_nope' });
    assert.equal(unknown.status, 401);
    assert.equal(unknown.body.error, 'invalid_client');
    const grant = await postToken(ctx.base, { grant_type: 'client_credentials', client_id: t.client.client_id });
    assert.equal(grant.body.error, 'unsupported_grant_type');
    const { challenge } = pkcePair();
    const params = authorizeParams({ clientId: t.client.client_id, challenge });
    params.set('resource', 'https://other.example/mcp');
    const res = await submitPassphrase(ctx.base, params);
    assert.equal(new URL(res.headers.get('location')).searchParams.get('error'), 'invalid_target');
  });

  test('未知 client_id 的授权请求不重定向', async () => {
    const res = await fetch(`${ctx.base}/authorize?${authorizeParams({ clientId: 'client_nope', challenge: pkcePair().challenge })}`, { redirect: 'manual' });
    assert.equal(res.status, 400);
    assert.equal(res.headers.get('location'), null);
  });
});

describe('MCP 会话与来源校验', () => {
  let ctx;
  let token;
  before(async () => {
    ctx = await startTestServer();
    token = (await obtainTokens(ctx.base)).access_token;
  });
  after(() => ctx.close());

  test('非 initialize 请求缺少会话头 400，未知会话 404', async () => {
    const missing = await mcpPost(ctx.base, token, { jsonrpc: '2.0', id: 1, method: 'tools/list' });
    assert.equal(missing.status, 400);
    const unknown = await mcpPost(ctx.base, token, { jsonrpc: '2.0', id: 1, method: 'tools/list' }, { sessionId: 'nope' });
    assert.equal(unknown.status, 404);
  });

  test('会话绑定令牌家族：另一次授权的令牌不能使用', async () => {
    const { sessionId } = await initSession(ctx.base, token);
    const other = (await obtainTokens(ctx.base)).access_token;
    const r = await mcpPost(ctx.base, other, { jsonrpc: '2.0', id: 1, method: 'tools/list' }, { sessionId });
    assert.equal(r.status, 404);
  });

  test('DELETE 结束会话', async () => {
    const { sessionId } = await initSession(ctx.base, token);
    const del = await fetch(`${ctx.base}/mcp`, { method: 'DELETE', headers: { Authorization: `Bearer ${token}`, 'Mcp-Session-Id': sessionId } });
    assert.equal(del.status, 204);
    const r = await mcpPost(ctx.base, token, { jsonrpc: '2.0', id: 1, method: 'ping' }, { sessionId });
    assert.equal(r.status, 404);
  });

  test('不在白名单的 Origin 被拒', async () => {
    const r = await mcpPost(ctx.base, token, { jsonrpc: '2.0', id: 1, method: 'ping' }, { headers: { Origin: 'https://evil.example' } });
    assert.equal(r.status, 403);
    const ok = await mcpPost(ctx.base, token, { jsonrpc: '2.0', id: 1, method: 'initialize', params: {} }, { headers: { Origin: 'https://claude.ai' } });
    assert.equal(ok.status, 200);
  });

  test('未设置口令时授权页拒绝签发', async () => {
    const bare = await startTestServer({ passphrase: null });
    try {
      const { body: client } = await registerClient(bare.base);
      const res = await submitPassphrase(bare.base, authorizeParams({ clientId: client.client_id, challenge: pkcePair().challenge }), '');
      assert.equal(res.status, 503);
      assert.equal(res.headers.get('location'), null);
    } finally {
      await bare.close();
    }
  });
});
