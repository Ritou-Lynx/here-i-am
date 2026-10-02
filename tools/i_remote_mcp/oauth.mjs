// 单用户最小 OAuth 2.1 授权服务器（claude.ai 自定义 connector 用）。
// 只用 Node 内置模块；所有令牌、授权码和口令都只以哈希保存。
import {
  createHash,
  randomBytes,
  randomUUID,
  scryptSync,
  timingSafeEqual,
} from 'node:crypto';
import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from 'node:fs';
import { join } from 'node:path';

export const SCOPE = 'i.read';
export const CLAUDE_AI_CALLBACKS = Object.freeze([
  'https://claude.ai/api/mcp/auth_callback',
  'https://claude.com/api/mcp/auth_callback',
]);

const STATE_SCHEMA_VERSION = 1;
const SCRYPT = { N: 16384, r: 8, p: 1, keylen: 32 };
const MIN_PASSPHRASE_LENGTH = 12;
const MAX_CLIENTS = 50;
const MAX_REDIRECT_URIS = 5;

export const DEFAULT_OAUTH_OPTIONS = Object.freeze({
  accessTokenTtlMs: 60 * 60 * 1000,
  refreshTokenTtlMs: 30 * 24 * 60 * 60 * 1000,
  authCodeTtlMs: 5 * 60 * 1000,
  maxPassphraseFailures: 5,
  failureWindowMs: 15 * 60 * 1000,
  lockoutMs: 15 * 60 * 1000,
});

export function sha256(value) {
  return createHash('sha256').update(String(value), 'utf8').digest('hex');
}

function newToken(prefix) {
  return `${prefix}_${randomBytes(32).toString('base64url')}`;
}

function hashPassphrase(passphrase, salt = randomBytes(16)) {
  const hash = scryptSync(String(passphrase).normalize('NFC'), salt, SCRYPT.keylen, {
    N: SCRYPT.N, r: SCRYPT.r, p: SCRYPT.p,
  });
  return {
    algorithm: 'scrypt',
    params: { N: SCRYPT.N, r: SCRYPT.r, p: SCRYPT.p },
    salt: salt.toString('base64'),
    hash: hash.toString('base64'),
  };
}

function verifyPassphrase(passphrase, record) {
  if (!record || record.algorithm !== 'scrypt') return false;
  const expected = Buffer.from(record.hash, 'base64');
  const actual = scryptSync(String(passphrase).normalize('NFC'), Buffer.from(record.salt, 'base64'), expected.length, {
    N: record.params.N, r: record.params.r, p: record.params.p,
  });
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

function emptyState() {
  return {
    schema_version: STATE_SCHEMA_VERSION,
    passphrase: null,
    clients: {},
    codes: {},
    access_tokens: {},
    refresh_tokens: {},
  };
}

// 持久化状态：.state/oauth.json，权限 0600，原子写入。
export class OAuthStateStore {
  constructor(stateDir) {
    this.stateDir = stateDir;
    this.path = join(stateDir, 'oauth.json');
    this.state = this.#load();
  }

  #load() {
    if (!existsSync(this.path)) return emptyState();
    const parsed = JSON.parse(readFileSync(this.path, 'utf8'));
    if (parsed?.schema_version !== STATE_SCHEMA_VERSION) {
      throw new Error(`unsupported oauth state schema in ${this.path}`);
    }
    return { ...emptyState(), ...parsed };
  }

  save() {
    mkdirSync(this.stateDir, { recursive: true, mode: 0o700 });
    const tmp = `${this.path}.${process.pid}.tmp`;
    writeFileSync(tmp, `${JSON.stringify(this.state, null, 2)}\n`, { mode: 0o600 });
    renameSync(tmp, this.path);
    try { chmodSync(this.path, 0o600); } catch { /* Windows */ }
  }
}

export function setPassphrase(stateDir, passphrase) {
  const value = String(passphrase ?? '');
  if ([...value].length < MIN_PASSPHRASE_LENGTH) {
    throw new Error(`口令至少 ${MIN_PASSPHRASE_LENGTH} 个字符`);
  }
  const store = new OAuthStateStore(stateDir);
  store.state.passphrase = hashPassphrase(value);
  // 改口令即吊销所有既有令牌与授权码。
  store.state.codes = {};
  store.state.access_tokens = {};
  store.state.refresh_tokens = {};
  store.save();
}

export function revokeAll(stateDir) {
  const store = new OAuthStateStore(stateDir);
  store.state.codes = {};
  store.state.access_tokens = {};
  store.state.refresh_tokens = {};
  store.save();
}

export function isAllowedRedirectUri(value) {
  if (typeof value !== 'string' || value.length > 2048) return false;
  if (CLAUDE_AI_CALLBACKS.includes(value)) return true;
  let url;
  try { url = new URL(value); } catch { return false; }
  return url.protocol === 'https:' && !url.hash && !url.username && !url.password;
}

function normalizeResource(value) {
  return String(value).replace(/\/+$/, '');
}

export class OAuthServer {
  constructor({ stateDir, publicUrl, now = () => Date.now(), options = {} }) {
    this.store = new OAuthStateStore(stateDir);
    this.now = now;
    this.options = { ...DEFAULT_OAUTH_OPTIONS, ...options };
    this.issuer = new URL(publicUrl).origin;
    this.resource = `${this.issuer}/mcp`;
    this.failures = [];
    this.lockedUntil = 0;
  }

  // ---------- 元数据 ----------

  protectedResourceMetadataUrl() {
    return `${this.issuer}/.well-known/oauth-protected-resource`;
  }

  protectedResourceMetadata() {
    return {
      resource: this.resource,
      authorization_servers: [this.issuer],
      scopes_supported: [SCOPE],
      bearer_methods_supported: ['header'],
      resource_name: 'i (林埃) 只读连续性',
    };
  }

  authorizationServerMetadata() {
    return {
      issuer: this.issuer,
      authorization_endpoint: `${this.issuer}/authorize`,
      token_endpoint: `${this.issuer}/token`,
      registration_endpoint: `${this.issuer}/register`,
      response_types_supported: ['code'],
      grant_types_supported: ['authorization_code', 'refresh_token'],
      code_challenge_methods_supported: ['S256'],
      token_endpoint_auth_methods_supported: ['none'],
      scopes_supported: [SCOPE, 'offline_access'],
    };
  }

  wwwAuthenticate(error) {
    const parts = [`resource_metadata="${this.protectedResourceMetadataUrl()}"`, `scope="${SCOPE}"`];
    if (error) parts.unshift(`error="${error}"`);
    return `Bearer ${parts.join(', ')}`;
  }

  hasPassphrase() {
    return Boolean(this.store.state.passphrase);
  }

  // ---------- 动态客户端注册 (RFC 7591) ----------

  register(body) {
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      return oauthError(400, 'invalid_client_metadata', 'JSON object required');
    }
    const redirectUris = body.redirect_uris;
    if (!Array.isArray(redirectUris) || redirectUris.length === 0 || redirectUris.length > MAX_REDIRECT_URIS) {
      return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be a non-empty array');
    }
    if (!redirectUris.every(isAllowedRedirectUri)) {
      return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be https');
    }
    const grantTypes = body.grant_types ?? ['authorization_code', 'refresh_token'];
    if (!Array.isArray(grantTypes) || grantTypes.some((g) => !['authorization_code', 'refresh_token'].includes(g))) {
      return oauthError(400, 'invalid_client_metadata', 'unsupported grant_types');
    }
    const responseTypes = body.response_types ?? ['code'];
    if (!Array.isArray(responseTypes) || responseTypes.some((r) => r !== 'code')) {
      return oauthError(400, 'invalid_client_metadata', 'unsupported response_types');
    }
    const clientId = `client_${randomUUID()}`;
    const issuedAt = Math.floor(this.now() / 1000);
    const client = {
      client_id: clientId,
      client_id_issued_at: issuedAt,
      client_name: typeof body.client_name === 'string' ? body.client_name.slice(0, 100) : undefined,
      redirect_uris: [...redirectUris],
      grant_types: grantTypes,
      response_types: ['code'],
      token_endpoint_auth_method: 'none',
      scope: SCOPE,
    };
    const clients = this.store.state.clients;
    clients[clientId] = client;
    const ids = Object.keys(clients);
    if (ids.length > MAX_CLIENTS) {
      ids.sort((a, b) => clients[a].client_id_issued_at - clients[b].client_id_issued_at);
      for (const id of ids.slice(0, ids.length - MAX_CLIENTS)) delete clients[id];
    }
    this.store.save();
    return { status: 201, body: client };
  }

  // ---------- /authorize ----------

  // 校验授权请求。返回 { ok, params } 或 { ok:false, redirect?, status, error }。
  // client_id / redirect_uri 不可信时不重定向，直接显示错误页。
  validateAuthorizeRequest(query) {
    const get = (k) => (typeof query[k] === 'string' ? query[k] : undefined);
    const clientId = get('client_id');
    const client = clientId ? this.store.state.clients[clientId] : undefined;
    if (!client) return { ok: false, status: 400, error: '未知的 client_id' };
    const redirectUri = get('redirect_uri') ?? (client.redirect_uris.length === 1 ? client.redirect_uris[0] : undefined);
    if (!redirectUri || !client.redirect_uris.includes(redirectUri) || !isAllowedRedirectUri(redirectUri)) {
      return { ok: false, status: 400, error: 'redirect_uri 与注册时不一致' };
    }
    const state = get('state');
    const fail = (error, description) => ({
      ok: false,
      redirect: buildRedirect(redirectUri, { error, error_description: description, state, iss: this.issuer }),
    });
    if (get('response_type') !== 'code') return fail('unsupported_response_type', 'response_type must be code');
    const challenge = get('code_challenge');
    if (get('code_challenge_method') !== 'S256' || !challenge || !/^[A-Za-z0-9_-]{43,128}$/.test(challenge)) {
      return fail('invalid_request', 'PKCE S256 code_challenge required');
    }
    const resource = get('resource');
    if (resource !== undefined && normalizeResource(resource) !== this.resource) {
      return fail('invalid_target', 'unknown resource');
    }
    return {
      ok: true,
      params: {
        client_id: clientId,
        client_name: client.client_name,
        redirect_uri: redirectUri,
        state,
        code_challenge: challenge,
        code_challenge_method: 'S256',
        scope: get('scope'),
        resource,
        response_type: 'code',
      },
    };
  }

  #rateLimited() {
    const now = this.now();
    if (now < this.lockedUntil) return true;
    this.failures = this.failures.filter((t) => now - t < this.options.failureWindowMs);
    return false;
  }

  #recordFailure() {
    const now = this.now();
    this.failures.push(now);
    if (this.failures.length >= this.options.maxPassphraseFailures) {
      this.lockedUntil = now + this.options.lockoutMs;
      this.failures = [];
    }
  }

  // 口令提交。返回 { status, redirect? , error? , params? }。
  submitPassphrase(form) {
    const validation = this.validateAuthorizeRequest(form);
    if (!validation.ok) return validation;
    const { params } = validation;
    if (!this.hasPassphrase()) {
      return { ok: false, status: 503, error: '尚未设置口令，请先在本机运行 set-passphrase', params };
    }
    if (this.#rateLimited()) {
      return { ok: false, status: 429, error: '口令错误次数过多，请稍后再试', params };
    }
    if (!verifyPassphrase(form.passphrase ?? '', this.store.state.passphrase)) {
      this.#recordFailure();
      return { ok: false, status: 401, error: '口令不正确', params };
    }
    this.failures = [];
    const code = newToken('code');
    this.store.state.codes[sha256(code)] = {
      client_id: params.client_id,
      redirect_uri: params.redirect_uri,
      code_challenge: params.code_challenge,
      resource: this.resource,
      scope: SCOPE,
      expires_at: this.now() + this.options.authCodeTtlMs,
      used: false,
    };
    this.#purgeExpired();
    this.store.save();
    return {
      ok: true,
      redirect: buildRedirect(params.redirect_uri, { code, state: params.state, iss: this.issuer }),
    };
  }

  // ---------- /token ----------

  token(form) {
    const grantType = form.grant_type;
    if (grantType === 'authorization_code') return this.#exchangeCode(form);
    if (grantType === 'refresh_token') return this.#refresh(form);
    return oauthError(400, 'unsupported_grant_type', 'unsupported grant_type');
  }

  #exchangeCode(form) {
    const client = this.store.state.clients[form.client_id];
    if (!client) return oauthError(401, 'invalid_client', 'unknown client');
    if (typeof form.code !== 'string') return oauthError(400, 'invalid_request', 'code required');
    const key = sha256(form.code);
    const record = this.store.state.codes[key];
    if (!record || record.client_id !== client.client_id) {
      return oauthError(400, 'invalid_grant', 'invalid code');
    }
    if (record.used) {
      // 授权码重放：吊销由它签发的整条令牌链。
      this.#revokeFamily(record.family_id);
      delete this.store.state.codes[key];
      this.store.save();
      return oauthError(400, 'invalid_grant', 'code already used');
    }
    if (this.now() >= record.expires_at) {
      delete this.store.state.codes[key];
      this.store.save();
      return oauthError(400, 'invalid_grant', 'code expired');
    }
    if (form.redirect_uri !== record.redirect_uri) {
      return oauthError(400, 'invalid_grant', 'redirect_uri mismatch');
    }
    if (form.resource !== undefined && normalizeResource(form.resource) !== this.resource) {
      return oauthError(400, 'invalid_target', 'unknown resource');
    }
    const verifier = form.code_verifier;
    if (typeof verifier !== 'string' || !/^[A-Za-z0-9._~-]{43,128}$/.test(verifier)) {
      return oauthError(400, 'invalid_grant', 'code_verifier required');
    }
    const challenge = createHash('sha256').update(verifier, 'ascii').digest('base64url');
    if (!safeEqual(challenge, record.code_challenge)) {
      return oauthError(400, 'invalid_grant', 'PKCE verification failed');
    }
    const familyId = randomUUID();
    record.used = true;
    record.family_id = familyId;
    const tokens = this.#issueTokens(client.client_id, familyId);
    this.store.save();
    return { status: 200, body: tokens };
  }

  #refresh(form) {
    const client = this.store.state.clients[form.client_id];
    if (!client) return oauthError(401, 'invalid_client', 'unknown client');
    if (typeof form.refresh_token !== 'string') return oauthError(400, 'invalid_request', 'refresh_token required');
    const key = sha256(form.refresh_token);
    const record = this.store.state.refresh_tokens[key];
    if (!record || record.client_id !== client.client_id) {
      return oauthError(400, 'invalid_grant', 'invalid refresh_token');
    }
    if (record.rotated) {
      // 已轮换的 refresh token 被重放：视为泄露，吊销整个家族。
      this.#revokeFamily(record.family_id);
      this.store.save();
      return oauthError(400, 'invalid_grant', 'refresh_token reused');
    }
    if (this.now() >= record.expires_at) {
      delete this.store.state.refresh_tokens[key];
      this.store.save();
      return oauthError(400, 'invalid_grant', 'refresh_token expired');
    }
    record.rotated = true;
    const tokens = this.#issueTokens(client.client_id, record.family_id);
    this.store.save();
    return { status: 200, body: tokens };
  }

  #issueTokens(clientId, familyId) {
    const now = this.now();
    const accessToken = newToken('iat');
    const refreshToken = newToken('irt');
    this.store.state.access_tokens[sha256(accessToken)] = {
      client_id: clientId,
      family_id: familyId,
      resource: this.resource,
      scope: SCOPE,
      expires_at: now + this.options.accessTokenTtlMs,
    };
    this.store.state.refresh_tokens[sha256(refreshToken)] = {
      client_id: clientId,
      family_id: familyId,
      expires_at: now + this.options.refreshTokenTtlMs,
      rotated: false,
    };
    this.#purgeExpired();
    return {
      access_token: accessToken,
      token_type: 'Bearer',
      expires_in: Math.floor(this.options.accessTokenTtlMs / 1000),
      refresh_token: refreshToken,
      scope: SCOPE,
    };
  }

  #revokeFamily(familyId) {
    if (!familyId) return;
    for (const table of [this.store.state.access_tokens, this.store.state.refresh_tokens]) {
      for (const [key, value] of Object.entries(table)) {
        if (value.family_id === familyId) delete table[key];
      }
    }
  }

  #purgeExpired() {
    const now = this.now();
    for (const table of [this.store.state.codes, this.store.state.access_tokens]) {
      for (const [key, value] of Object.entries(table)) {
        if (now >= value.expires_at) delete table[key];
      }
    }
    // 已轮换的 refresh token 保留到过期，以便识别重放。
    for (const [key, value] of Object.entries(this.store.state.refresh_tokens)) {
      if (now >= value.expires_at) delete this.store.state.refresh_tokens[key];
    }
  }

  // ---------- 资源服务器校验 ----------

  // 返回 { ok: true, familyId } 或 { ok: false, error }。
  verifyAccessToken(authorizationHeader) {
    const match = /^Bearer\s+([A-Za-z0-9._~+/=-]+)\s*$/i.exec(String(authorizationHeader ?? ''));
    if (!match) return { ok: false, error: null };
    const record = this.store.state.access_tokens[sha256(match[1])];
    if (!record) return { ok: false, error: 'invalid_token' };
    if (this.now() >= record.expires_at) return { ok: false, error: 'invalid_token' };
    if (record.resource !== this.resource) return { ok: false, error: 'invalid_token' };
    return { ok: true, familyId: record.family_id, clientId: record.client_id };
  }
}

function safeEqual(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && timingSafeEqual(x, y);
}

function oauthError(status, error, description) {
  return { status, body: { error, error_description: description } };
}

function buildRedirect(redirectUri, params) {
  const url = new URL(redirectUri);
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== null) url.searchParams.set(k, v);
  }
  return url.toString();
}
