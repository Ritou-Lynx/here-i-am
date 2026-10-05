// 测试共用：合成数据的 fake readModel 与真实 HTTP 服务启动器。
import { createHash, randomBytes } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setPassphrase } from './oauth.mjs';
import { createApp } from './server.mjs';

export const PASSPHRASE = 'correct horse battery staple';
export const PUBLIC_URL = 'https://i-test.example.ts.net';
export const REDIRECT_URI = 'https://claude.ai/api/mcp/auth_callback';
export const PRIMARY = 'char-lin-ai';
export const SNAPSHOT_AT_MS = Date.UTC(2026, 8, 30, 12, 0, 0);

// 这些标记出现在任何返回里都算泄露。
export const PRIVATE_MARKERS = Object.freeze([
  'PRIVATE_CHAR_SECRET',
  'char-private-other',
  'PRIVATE_TYPE_SECRET',
  'card-private-type',
  'PRIVATE_KEYWORD_SECRET',
  'card-private-keyword',
  'EXTRA_FIELD_SECRET',
  'shareable_character_ids',
  'private_keywords',
]);

const MESSAGES = [
  { syncId: 'm1', characterId: PRIMARY, sender: 'user', content: '七月我们聊过猫咪三花的事', createdAtMs: Date.UTC(2026, 6, 3), messageType: 'text', originDeviceId: 'phone' },
  { syncId: 'm2', characterId: PRIMARY, sender: 'companion', content: '记得，三花猫咪那天很黏人', createdAtMs: Date.UTC(2026, 6, 3, 0, 1), messageType: 'text', originDeviceId: 'phone' },
  { syncId: 'm3', characterId: 'char-private-other', sender: 'user', content: 'PRIVATE_CHAR_SECRET 猫咪', createdAtMs: Date.UTC(2026, 6, 4), messageType: 'text', originDeviceId: 'phone' },
  { syncId: 'm4', characterId: PRIMARY, sender: 'user', content: '今天去散步了', createdAtMs: Date.UTC(2026, 8, 29), messageType: 'text', originDeviceId: 'phone' },
];

const CARDS = [
  { id: 'card-cat', type: 'pet', title: '三花猫咪', dropletLabel: '猫咪', retrievalText: '用户养了一只三花猫咪', status: 'active', structured: { type: 'pet', fields: { name: '三花' } }, recordedAt: Date.UTC(2026, 6, 3), updatedAt: Date.UTC(2026, 6, 5) },
  { id: 'card-private-type', type: 'secret_type', title: 'PRIVATE_TYPE_SECRET 猫咪', dropletLabel: 'x', retrievalText: '猫咪', status: 'active', structured: null, recordedAt: 1, updatedAt: 1 },
  { id: 'card-private-keyword', type: 'pet', title: '猫咪 PRIVATE_KEYWORD_SECRET', dropletLabel: 'y', retrievalText: '猫咪', status: 'active', structured: null, recordedAt: 1, updatedAt: 1 },
];

// 按约定接口实现，并模拟 policy 过滤；每个返回对象额外带一个不在约定里的字段，用来验证输出白名单。
export function createFakeReadModel({ fail = false } = {}) {
  const shareableMessage = (m) => m.characterId === PRIMARY;
  const shareableCard = (c) => c.type !== 'secret_type' && !`${c.title}${c.retrievalText}`.includes('PRIVATE_KEYWORD_SECRET');
  const withExtra = (o) => ({ ...o, extraField: 'EXTRA_FIELD_SECRET' });
  const guard = () => { if (fail) throw new Error('policy missing at /secret/path/policy.json PRIVATE_CHAR_SECRET'); };
  const calls = [];
  return {
    calls,
    policySummary() { guard(); return { primaryCharacterId: PRIMARY, memorySnapshotAtMs: SNAPSHOT_AT_MS }; },
    recentMessages({ limit = 20, characterId = PRIMARY } = {}) {
      guard(); calls.push(['recentMessages', limit]);
      return MESSAGES.filter(shareableMessage).filter((m) => m.characterId === characterId)
        .sort((a, b) => a.createdAtMs - b.createdAtMs).slice(-Math.min(limit, 100)).map(withExtra);
    },
    searchMessages({ query, limit = 10 } = {}) {
      guard(); calls.push(['searchMessages', query, limit]);
      return MESSAGES.filter(shareableMessage).filter((m) => m.content.includes(query)).slice(0, limit)
        .map((m) => withExtra({ ...m, snippet: m.content.slice(0, 20) }));
    },
    searchMemory({ query, limit = 8 } = {}) {
      guard(); calls.push(['searchMemory', query, limit]);
      return CARDS.filter(shareableCard).filter((c) => `${c.title}${c.dropletLabel}${c.retrievalText}`.includes(query))
        .slice(0, limit).map(withExtra);
    },
    getMemoryCards({ ids }) { guard(); return CARDS.filter(shareableCard).filter((c) => ids.includes(c.id)).map(withExtra); },
    stats() { return { messages: { shareable: 3, private: 1 }, memory: { shareable: 1, private: 2 }, memorySnapshotAtMs: SNAPSHOT_AT_MS }; },
    close() {},
  };
}

export async function startTestServer({ readModel = createFakeReadModel(), oauthOptions, passphrase = PASSPHRASE, identityLoader, timeZone = 'Asia/Shanghai', diagnostic, log, writeback = null, stateDir: givenStateDir } = {}) {
  const stateDir = givenStateDir ?? mkdtempSync(join(tmpdir(), 'i-remote-mcp-'));
  if (passphrase) setPassphrase(stateDir, passphrase);
  const clock = { t: Date.UTC(2026, 9, 2, 4, 0, 0) };
  const extra = identityLoader ? { identityLoader } : {};
  const { server, oauth } = createApp({
    stateDir,
    publicUrl: PUBLIC_URL,
    getReadModel: async () => readModel,
    now: () => clock.t,
    oauthOptions,
    diagnostic,
    log,
    timeZone,
    writeback,
    ...extra,
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  return {
    base, server, oauth, clock, stateDir, readModel,
    async close() {
      await new Promise((r) => server.close(r));
      rmSync(stateDir, { recursive: true, force: true });
    },
  };
}

export function pkcePair() {
  const verifier = randomBytes(32).toString('base64url');
  const challenge = createHash('sha256').update(verifier).digest('base64url');
  return { verifier, challenge };
}

export async function registerClient(base, redirectUris = [REDIRECT_URI]) {
  const res = await fetch(`${base}/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ client_name: 'Claude', redirect_uris: redirectUris, token_endpoint_auth_method: 'none' }),
  });
  return { status: res.status, body: await res.json() };
}

export function authorizeParams({ clientId, challenge, redirectUri = REDIRECT_URI, state = 'st-123', method = 'S256' }) {
  return new URLSearchParams({
    response_type: 'code',
    client_id: clientId,
    redirect_uri: redirectUri,
    code_challenge: challenge,
    code_challenge_method: method,
    state,
    scope: 'i.read',
    resource: `${PUBLIC_URL}/mcp`,
  });
}

export async function submitPassphrase(base, params, passphrase = PASSPHRASE) {
  const body = new URLSearchParams(params);
  body.set('passphrase', passphrase);
  return fetch(`${base}/authorize`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
    redirect: 'manual',
  });
}

export async function postToken(base, fields) {
  const res = await fetch(`${base}/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(fields),
  });
  return { status: res.status, body: await res.json(), headers: res.headers };
}

// 完整授权：注册 → 口令 → 换取令牌。
export async function obtainTokens(base) {
  const { body: client } = await registerClient(base);
  const { verifier, challenge } = pkcePair();
  const res = await submitPassphrase(base, authorizeParams({ clientId: client.client_id, challenge }));
  const location = new URL(res.headers.get('location'));
  const code = location.searchParams.get('code');
  const token = await postToken(base, {
    grant_type: 'authorization_code',
    code,
    client_id: client.client_id,
    redirect_uri: REDIRECT_URI,
    code_verifier: verifier,
    resource: `${PUBLIC_URL}/mcp`,
  });
  return { client, code, verifier, ...token.body };
}

export async function mcpPost(base, token, body, { sessionId, headers = {} } = {}) {
  const res = await fetch(`${base}/mcp`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json, text/event-stream',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(sessionId ? { 'Mcp-Session-Id': sessionId } : {}),
      ...headers,
    },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, headers: res.headers, text, body: text ? JSON.parse(text) : null };
}

export async function initSession(base, token, protocolVersion = '2025-06-18') {
  const init = await mcpPost(base, token, {
    jsonrpc: '2.0', id: 1, method: 'initialize',
    params: { protocolVersion, capabilities: {}, clientInfo: { name: 'test', version: '0' } },
  });
  const sessionId = init.headers.get('mcp-session-id');
  await mcpPost(base, token, { jsonrpc: '2.0', method: 'notifications/initialized' }, { sessionId, headers: { 'MCP-Protocol-Version': protocolVersion } });
  return { init, sessionId };
}
