#!/usr/bin/env node
// i 远程 MCP：Streamable HTTP（/mcp）+ 单用户 OAuth 2.1；B3 写回与本机手机拉取通道可选。
// 用法见同目录 README.md。
import { randomUUID } from 'node:crypto';
import { createServer } from 'node:http';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { OAuthServer, revokeAll, setPassphrase } from './oauth.mjs';
import { readFileSync } from 'node:fs';
import { createDomainClient, createDomainTools, createCoreRemember, WEB_DOMAIN_TOOLS } from './domain_tools.mjs';
import { createRequestDiagnostics, createJsonlDiagnosticWriter } from './diagnostics.mjs';
import {
  SUPPORTED_PROTOCOL_VERSIONS,
  createToolHandlers,
  handleRpcMessage,
  listTools,
  loadIdentity,
} from './mcp.mjs';
import {
  WritebackInputError,
  createCoreFrontendClient,
  createWriteback,
  issuePhoneToken,
  loadFrontendCredential,
  loadPhoneTokenHash,
  openLedger,
  pairFrontendDevice,
  verifyPhoneToken,
} from './writeback.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_TOOLS = resolve(HERE, '..');

export const DEFAULTS = Object.freeze({
  host: '127.0.0.1',
  port: 47860,
  stateDir: resolve(HERE, '.state'),
  coreDbPath: resolve(REPO_TOOLS, 'i_core/.state/i-core.sqlite'),
  memoryDbPath: resolve(REPO_TOOLS, 'i_memory/.state/i-memory.sqlite'),
  policyPath: resolve(REPO_TOOLS, 'i_memory/.state/policy.json'),
  coreUrl: 'http://127.0.0.1:47841',
  phoneHost: '127.0.0.1',
  phonePort: 47862,
});

// i_chat_turn 一次最多 6 万字（中文约 180KB），留出 JSON 转义余量。
const MAX_BODY_BYTES = 256 * 1024;
const MAX_PHONE_BODY_BYTES = 4 * 1024;
const MAX_SESSIONS = 100;
const SESSION_IDLE_MS = 24 * 60 * 60 * 1000;
const DEFAULT_ALLOWED_ORIGINS = ['https://claude.ai', 'https://claude.com'];

// 生产用读取层：动态加载 tools/i_memory/i_memory_read.mjs 的 openReadModel。
export function createLazyReadModel({ coreDbPath, memoryDbPath, policyPath }) {
  let cached = null;
  const factory = async () => {
    if (cached) return cached;
    const mod = await import(pathToFileURL(resolve(REPO_TOOLS, 'i_memory/i_memory_read.mjs')).href);
    cached = mod.openReadModel({ coreDbPath, memoryDbPath, policyPath });
    return cached;
  };
  factory.close = () => { cached?.close?.(); cached = null; };
  return factory;
}

export function createApp({
  stateDir = DEFAULTS.stateDir,
  publicUrl,
  getReadModel,
  now = () => Date.now(),
  oauthOptions = {},
  identityLoader = loadIdentity,
  timeZone = process.env.I_REMOTE_MCP_TIMEZONE,
  allowedOrigins = DEFAULT_ALLOWED_ORIGINS,
  log = () => {},
  diagnostic = () => {},
  writeback = null,
  coreRemember = null,
  domainTools = null,
}) {
  if (!publicUrl) throw new Error('publicUrl is required');
  if (typeof getReadModel !== 'function') throw new Error('getReadModel is required');
  const writeEnabled = Boolean(writeback || coreRemember);
  const oauth = new OAuthServer({ stateDir, publicUrl, now, options: oauthOptions, writeEnabled });
  if(domainTools&&(domainTools.tools.some(tool=>!WEB_DOMAIN_TOOLS.includes(tool.name))||Object.keys(domainTools.handlers).some(name=>!domainTools.tools.some(tool=>tool.name===name))))throw new Error('planner_tools_forbidden_on_web');
  const handlers = {...createToolHandlers({ getReadModel, identityLoader, now, timeZone, writeback, coreRemember }),...domainTools?.handlers};
  const tools = [...listTools({ writeEnabled:Boolean(writeback),coreRemember:Boolean(coreRemember) }),...(domainTools?.tools??[]).map(tool=>({...tool,requiredScope:tool.name==='capture_add'?'i.write':'i.read'}))];
  const origins = new Set([...allowedOrigins, oauth.issuer]);
  const sessions = new Map();

  function pruneSessions() {
    const t = now();
    for (const [id, s] of sessions) if (t - s.lastSeen > SESSION_IDLE_MS) sessions.delete(id);
    while (sessions.size > MAX_SESSIONS) sessions.delete(sessions.keys().next().value);
  }

  async function handleMcp(req, res, diagnostics) {
    const origin = req.headers.origin;
    if (origin && !origins.has(origin)) return sendJson(res, 403, { error: 'forbidden_origin' });

    const auth = oauth.verifyAccessToken(req.headers.authorization);
    if (!auth.ok) {
      res.setHeader('WWW-Authenticate', oauth.wwwAuthenticate(auth.error));
      return sendJson(res, 401, { error: auth.error ?? 'unauthorized', error_description: 'Bearer token required' });
    }

    const versionHeader = req.headers['mcp-protocol-version'];
    if (versionHeader && !SUPPORTED_PROTOCOL_VERSIONS.includes(versionHeader)) {
      return sendJson(res, 400, rpcErr(null, -32600, `Unsupported MCP-Protocol-Version: ${String(versionHeader).slice(0, 32)}`));
    }

    const sessionId = req.headers['mcp-session-id'];
    if (req.method === 'GET') {
      res.setHeader('Allow', 'POST, DELETE');
      return sendJson(res, 405, { error: 'method_not_allowed', error_description: '本服务不提供 SSE 流' });
    }
    if (req.method === 'DELETE') {
      const s = sessionId && sessions.get(sessionId);
      if (!s || s.familyId !== auth.familyId) return sendJson(res, 404, { error: 'session_not_found' });
      sessions.delete(sessionId);
      return sendEmpty(res, 204);
    }
    if (req.method !== 'POST') {
      res.setHeader('Allow', 'POST, DELETE');
      return sendJson(res, 405, { error: 'method_not_allowed' });
    }

    let payload;
    try {
      payload = JSON.parse(await readBody(req));
    } catch (error) {
      if (error instanceof BodyTooLargeError) return sendJson(res, 413, rpcErr(null, -32600, 'Request too large'));
      return sendJson(res, 400, rpcErr(null, -32700, 'Parse error'));
    }

    const messages = Array.isArray(payload) ? payload : [payload];
    if (messages.length === 0) return sendJson(res, 400, rpcErr(null, -32600, 'Empty batch'));
    const isInitialize = messages.some((m) => m?.method === 'initialize');

    let session;
    if (isInitialize) {
      if (messages.length !== 1) return sendJson(res, 400, rpcErr(null, -32600, 'initialize must not be batched'));
      pruneSessions();
      const id = randomUUID();
      session = { id, familyId: auth.familyId, lastSeen: now(), initialized: false };
      sessions.set(id, session);
      res.setHeader('Mcp-Session-Id', id);
    } else {
      if (!sessionId) return sendJson(res, 400, rpcErr(null, -32600, 'Mcp-Session-Id header required'));
      session = sessions.get(sessionId);
      if (!session || session.familyId !== auth.familyId) {
        return sendJson(res, 404, rpcErr(null, -32001, 'Session not found; re-initialize'));
      }
      session.lastSeen = now();
    }

    const responses = [];
    for (const message of messages) {
      let dataSourceFailed = false;
      const response = await handleRpcMessage(message, {
        handlers,
        tools,
        scopes: auth.scopes,
        session,
        logError: () => { dataSourceFailed = true; },
      });
      diagnostics.rpc(message, response, { dataSourceFailed });
      if (response) responses.push(response);
    }
    if (responses.length === 0) return sendEmpty(res, 202);
    return sendJson(res, 200, Array.isArray(payload) ? responses : responses[0]);
  }

  async function handleAuthorize(req, res, url) {
    if (req.method === 'GET') {
      const query = Object.fromEntries(url.searchParams);
      const v = oauth.validateAuthorizeRequest(query);
      if (!v.ok) return v.redirect ? redirect(res, v.redirect) : sendHtml(res, v.status, errorPage(v.error));
      return sendHtml(res, 200, authorizePage(v.params, oauth.hasPassphrase() ? null : '尚未设置口令，请先在本机运行 set-passphrase。'));
    }
    if (req.method === 'POST') {
      let form;
      try {
        form = Object.fromEntries(new URLSearchParams(await readBody(req)));
      } catch {
        return sendHtml(res, 400, errorPage('请求无效'));
      }
      const r = oauth.submitPassphrase(form);
      if (r.redirect) return redirect(res, r.redirect);
      if (r.params) return sendHtml(res, r.status, authorizePage(r.params, r.error));
      return sendHtml(res, r.status, errorPage(r.error));
    }
    res.setHeader('Allow', 'GET, POST');
    return sendHtml(res, 405, errorPage('不支持的方法'));
  }

  async function route(req, res, diagnostics) {
    const url = new URL(req.url, oauth.issuer);
    const path = url.pathname;
    if (path === '/mcp') return handleMcp(req, res, diagnostics);
    if (path === '/.well-known/oauth-protected-resource' || path === '/.well-known/oauth-protected-resource/mcp') {
      return sendJson(res, 200, oauth.protectedResourceMetadata());
    }
    if (path === '/.well-known/oauth-authorization-server') {
      return sendJson(res, 200, oauth.authorizationServerMetadata());
    }
    if (path === '/register') {
      if (req.method !== 'POST') return sendJson(res, 405, { error: 'method_not_allowed' });
      let body;
      try { body = JSON.parse(await readBody(req)); } catch {
        return sendJson(res, 400, { error: 'invalid_client_metadata', error_description: 'invalid JSON' });
      }
      const r = oauth.register(body);
      return sendJson(res, r.status, r.body, { 'Cache-Control': 'no-store' });
    }
    if (path === '/authorize') return handleAuthorize(req, res, url);
    if (path === '/token') {
      if (req.method !== 'POST') return sendJson(res, 405, { error: 'method_not_allowed' });
      let form;
      try {
        form = Object.fromEntries(new URLSearchParams(await readBody(req)));
      } catch {
        return sendJson(res, 400, { error: 'invalid_request' });
      }
      const r = oauth.token(form);
      return sendJson(res, r.status, r.body, { 'Cache-Control': 'no-store', Pragma: 'no-cache' });
    }
    return sendJson(res, 404, { error: 'not_found' });
  }

  const server = createServer((req, res) => {
    let internalError = false;
    const diagnostics = createRequestDiagnostics(req, {
      issuer: oauth.issuer, resource: oauth.resource, now,
      diagnostic: (record) => {
        if (record.event === 'http_request') {
          try { Promise.resolve(log(`${record.method} ${record.path} ${record.status}`)).catch(() => {}); } catch { /* optional legacy sink */ }
        }
        return diagnostic(record);
      },
    });
    res.once('finish', () => diagnostics.finish(res.statusCode, { internalError }));
    route(req, res, diagnostics).catch(() => {
      internalError = true;
      if (!res.headersSent) sendJson(res, 500, { error: 'server_error' });
      else res.end();
    });
  });
  return { server, oauth, sessions };
}

// ---------- 手机拉取通道（只监听本机，不经公网隧道） ----------

// 手机 App 经 Tailscale Serve 访问；只读 i_remember 账本的变更并回执。
export function createPhoneFeedApp({ writeback, tokenHash }) {
  if (!writeback) throw new Error('writeback is required');
  const server = createServer((req, res) => {
    (async () => {
      if (!verifyPhoneToken(req.headers.authorization, tokenHash)) {
        return sendJson(res, 401, { error: 'unauthorized' });
      }
      const url = new URL(req.url, 'http://phone.local');
      if (req.method === 'GET' && url.pathname === '/v1/remember/changes') {
        const after = Number(url.searchParams.get('after') ?? '0');
        const limit = Number(url.searchParams.get('limit') ?? '100');
        if (!Number.isSafeInteger(after) || after < 0 || !Number.isSafeInteger(limit) || limit < 1) {
          return sendJson(res, 400, { error: 'invalid_request' });
        }
        return sendJson(res, 200, writeback.noteChanges({ after, limit: Math.min(limit, 200) }));
      }
      if (req.method === 'POST' && url.pathname === '/v1/remember/ack') {
        let body;
        try { body = JSON.parse(await readBody(req, MAX_PHONE_BODY_BYTES)); } catch {
          return sendJson(res, 400, { error: 'invalid_request' });
        }
        try {
          return sendJson(res, 200, writeback.ackNote(body ?? {}));
        } catch (error) {
          if (error instanceof WritebackInputError) return sendJson(res, 400, { error: 'invalid_request' });
          throw error;
        }
      }
      return sendJson(res, 404, { error: 'not_found' });
    })().catch(() => {
      if (!res.headersSent) sendJson(res, 500, { error: 'server_error' });
      else res.end();
    });
  });
  return { server };
}

// ---------- HTTP 工具 ----------

class BodyTooLargeError extends Error {}

function readBody(req, maxBytes = MAX_BODY_BYTES) {
  return new Promise((resolveBody, reject) => {
    const chunks = [];
    let size = 0;
    let tooLarge = false;
    req.on('data', (chunk) => {
      if (tooLarge) return;
      size += chunk.length;
      if (size > maxBytes) {
        tooLarge = true;
        chunks.length = 0;
        reject(new BodyTooLargeError());
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => { if (!tooLarge) resolveBody(Buffer.concat(chunks).toString('utf8')); });
    req.on('error', reject);
  });
}

function rpcErr(id, code, message) {
  return { jsonrpc: '2.0', id, error: { code, message } };
}

function sendJson(res, status, body, headers = {}) {
  const text = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(text),
    'X-Content-Type-Options': 'nosniff',
    ...headers,
  });
  res.end(text);
}

function sendEmpty(res, status) {
  res.writeHead(status);
  res.end();
}

function sendHtml(res, status, html) {
  res.writeHead(status, {
    'Content-Type': 'text/html; charset=utf-8',
    'Content-Length': Buffer.byteLength(html),
    'Cache-Control': 'no-store',
    'X-Frame-Options': 'DENY',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
    'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'",
  });
  res.end(html);
}

function redirect(res, location) {
  res.writeHead(302, { Location: location, 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer' });
  res.end();
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[c]);
}

const PAGE_STYLE = 'body{font-family:system-ui,sans-serif;max-width:26rem;margin:3rem auto;padding:0 1rem;color:#222}'
  + 'input[type=password]{width:100%;padding:.6rem;font-size:1rem;box-sizing:border-box}'
  + 'button{margin-top:1rem;padding:.6rem 1.2rem;font-size:1rem}.err{color:#b00020}.meta{color:#555;font-size:.9rem}';

function authorizePage(params, error) {
  const host = new URL(params.redirect_uri).host;
  const hidden = ['client_id', 'redirect_uri', 'state', 'code_challenge', 'code_challenge_method', 'scope', 'resource', 'response_type']
    .filter((k) => params[k] !== undefined && params[k] !== null)
    .map((k) => `<input type="hidden" name="${k}" value="${escapeHtml(params[k])}">`).join('');
  return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>授权 i 访问</title><style>${PAGE_STYLE}</style></head><body>
<h1>授权 i 访问</h1>
<p class="meta">应用：${escapeHtml(params.client_name || params.client_id)}<br>授权后将返回：<strong>${escapeHtml(host)}</strong></p>
<p>授权后，该应用可以只读地查看林埃的身份、最近可分享的聊天和记忆检索结果。</p>
${String(params.granted_scope ?? '').split(' ').includes('i.write')
    ? '<p><strong>同时允许写回</strong>：把这个应用里的聊天轮次写进 Here I Am 时间线，并按你的要求写入记录。</p>'
    : ''}
${error ? `<p class="err">${escapeHtml(error)}</p>` : ''}
<form method="post" action="/authorize">${hidden}
<label>口令<br><input type="password" name="passphrase" autocomplete="current-password" required autofocus></label>
<button type="submit">授权</button></form></body></html>`;
}

function errorPage(message) {
  return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>授权失败</title><style>${PAGE_STYLE}</style></head>
<body><h1>授权失败</h1><p class="err">${escapeHtml(message)}</p></body></html>`;
}

// ---------- CLI ----------

// Explicit owner configuration only. No grant issuance or automatic legacy migration.
export function loadWebDomainOptions(configPath) {
  if(!configPath)return {};
  return createWebDomainOptions(JSON.parse(readFileSync(configPath,'utf8')));
}
export function createWebDomainOptions(config) {
  const allowed=['captures:read','captures:create','captures:patch','captures:delete'];
  if(config.enabled!==true||config.remember_backend!=='core'||!Array.isArray(config.scopes)||config.scopes.some(scope=>!allowed.includes(scope)))throw new Error('invalid_web_domain_configuration');
  const client=createDomainClient({coreUrl:config.core_url,token:config.token,coreInstanceId:config.core_instance_id});
  const domainTools=createDomainTools({client,scopes:config.scopes,surface:'web',captureSource:'claude_web'});
  if(config.plan_reads){
    const plan=config.plan_reads;
    if(plan.token===config.token||!Array.isArray(plan.scopes)||plan.scopes.some(scope=>!['plan_weeks:read','plan_days:read'].includes(scope)))throw new Error('invalid_web_plan_configuration');
    const planTools=createDomainTools({client:createDomainClient({coreUrl:config.core_url,coreInstanceId:config.core_instance_id,token:plan.token}),scopes:plan.scopes,surface:'web',captureSource:'claude_web'});
    domainTools.tools.push(...planTools.tools);Object.assign(domainTools.handlers,planTools.handlers);
  }
  return {coreRemember:createCoreRemember({client,scopes:config.scopes}),domainTools};
}

function parseArgs(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const [k, inline] = a.slice(2).split('=', 2);
      out[k] = inline ?? argv[++i];
    } else {
      out._.push(a);
    }
  }
  return out;
}

async function readSecret(prompt) {
  const { stdin, stderr } = process;
  if (!stdin.isTTY) {
    const chunks = [];
    for await (const c of stdin) chunks.push(c);
    return Buffer.concat(chunks).toString('utf8').split(/\r?\n/)[0];
  }
  stderr.write(prompt);
  stdin.setRawMode(true);
  stdin.resume();
  stdin.setEncoding('utf8');
  return new Promise((resolveSecret, reject) => {
    let value = '';
    const onData = (ch) => {
      for (const c of ch) {
        if (c === '\r' || c === '\n') {
          stdin.setRawMode(false); stdin.pause(); stdin.off('data', onData);
          stderr.write('\n');
          return resolveSecret(value);
        }
        if (c === '\u0003') { stdin.setRawMode(false); return reject(new Error('cancelled')); }
        if (c === '\u007f' || c === '\b') value = value.slice(0, -1);
        else value += c;
      }
      return undefined;
    };
    stdin.on('data', onData);
  });
}

async function main(argv) {
  const args = parseArgs(argv);
  const command = args._[0] ?? 'serve';
  const stateDir = resolve(args['state-dir'] ?? process.env.I_REMOTE_MCP_STATE_DIR ?? DEFAULTS.stateDir);

  if (command === 'set-passphrase') {
    const first = await readSecret('新口令（至少 12 个字符）：');
    if (process.stdin.isTTY) {
      const second = await readSecret('再输入一次：');
      if (first !== second) throw new Error('两次输入不一致');
    }
    setPassphrase(stateDir, first);
    process.stderr.write(`已保存口令哈希到 ${stateDir}；既有令牌已全部吊销。\n`);
    return;
  }
  if (command === 'revoke-all') {
    revokeAll(stateDir);
    process.stderr.write('已吊销所有令牌与授权码。\n');
    return;
  }
  const coreUrl = String(args['core-url'] ?? process.env.I_CORE_URL ?? DEFAULTS.coreUrl).replace(/\/+$/, '');
  if (command === 'pair-core') {
    // i_core 需临时以 I_CORE_PAIRING_CODE 启动（打开配对窗口）；这里输入同一个一次性配对码。
    const code = (await readSecret('i_core 一次性配对码：')).trim();
    if (!code) throw new Error('配对码为空');
    const paired = await pairFrontendDevice({ coreUrl, pairingCode: code, stateDir });
    process.stderr.write(`已配对 ${paired.device_id}；令牌保存在 ${stateDir}/core-frontend.json（勿提交）。\n`);
    return;
  }
  if (command === 'issue-phone-token') {
    const token = issuePhoneToken(stateDir);
    process.stderr.write('手机拉取令牌（只显示这一次，旧令牌已失效）：\n');
    process.stdout.write(`${token}\n`);
    return;
  }
  if (command !== 'serve') {
    throw new Error(`未知子命令：${command}（可用：serve、set-passphrase、revoke-all、pair-core、issue-phone-token）`);
  }

  const host = args.host ?? process.env.I_REMOTE_MCP_HOST ?? DEFAULTS.host;
  const port = Number(args.port ?? process.env.I_REMOTE_MCP_PORT ?? DEFAULTS.port);
  const publicUrl = args['public-url'] ?? process.env.I_REMOTE_MCP_PUBLIC_URL ?? `http://${host}:${port}`;
  if (!publicUrl.startsWith('https://')) {
    process.stderr.write(`警告：public URL 不是 https（${publicUrl}），claude.ai 无法接入，仅适合本机调试。\n`);
  }
  const getReadModel = createLazyReadModel({
    coreDbPath: resolve(args['core-db'] ?? process.env.I_CORE_DB ?? DEFAULTS.coreDbPath),
    memoryDbPath: resolve(args['memory-db'] ?? process.env.I_MEMORY_DB ?? DEFAULTS.memoryDbPath),
    policyPath: resolve(args.policy ?? process.env.I_MEMORY_POLICY ?? DEFAULTS.policyPath),
  });
  const logDir = args['log-dir'] ?? process.env.I_REMOTE_MCP_LOG_DIR;
  const diagnostic = logDir
    ? createJsonlDiagnosticWriter({ logDir, onWriteError: (code) => process.stderr.write(`${code}\n`) })
    : (record) => process.stderr.write(`${JSON.stringify(record)}\n`);
  let writeback = null;
  const credential = process.env.I_REMOTE_MCP_WRITEBACK === '0' ? null : loadFrontendCredential(stateDir);
  if (credential) {
    writeback = createWriteback({
      ledger: openLedger(resolve(stateDir, 'writeback.sqlite')),
      coreClient: createCoreFrontendClient({ coreUrl, deviceToken: credential.device_token }),
    });
    process.stderr.write(`写回已启用：i_core ${coreUrl}\n`);
  } else {
    process.stderr.write('写回未启用（未配对 i_core 或 I_REMOTE_MCP_WRITEBACK=0），只开放只读工具。\n');
  }
  const { server, oauth } = createApp({
    stateDir,
    publicUrl,
    getReadModel,
    diagnostic,
    writeback,
    ...loadWebDomainOptions(args['domain-config']),
  });
  let phoneServer = null;
  const phoneTokenHash = writeback && !args['domain-config'] ? loadPhoneTokenHash(stateDir) : null;
  if (phoneTokenHash) {
    const phoneHost = args['phone-host'] ?? process.env.I_REMOTE_MCP_PHONE_HOST ?? DEFAULTS.phoneHost;
    const phonePort = Number(args['phone-port'] ?? process.env.I_REMOTE_MCP_PHONE_PORT ?? DEFAULTS.phonePort);
    phoneServer = createPhoneFeedApp({ writeback, tokenHash: phoneTokenHash }).server;
    phoneServer.listen(phonePort, phoneHost, () => {
      process.stderr.write(`手机拉取通道监听 http://${phoneHost}:${phonePort}/v1/remember/changes（不要接到公网隧道上）\n`);
    });
  }
  if (!oauth.hasPassphrase()) process.stderr.write('警告：尚未设置口令，授权页会拒绝所有请求。先运行 set-passphrase。\n');
  server.listen(port, host, () => {
    process.stderr.write(`i remote MCP 监听 http://${host}:${port}/mcp ，对外地址 ${oauth.resource}\n`);
  });
  const shutdown = () => { server.close(); phoneServer?.close(); getReadModel.close(); writeback?.close(); };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch(() => {
    process.stderr.write('启动或管理操作失败；请检查参数、权限与本机配置。\n');
    process.exitCode = 1;
  });
}
