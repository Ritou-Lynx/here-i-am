#!/usr/bin/env node
// Source-only candidate builder. Never loads runtime configuration or manages services.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

export const BASELINE_COMMIT = '3ce7aacc75615faf31aab7d4d902598070ffa898';
export const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const SOURCE_PREFIX = 'tools/i_core/test_fixtures/release_schema6/mcp_reader/legacy/';
export const SOURCE_INVENTORY = Object.freeze([
 ['i_remote_mcp/server.mjs','37f04a68147bd7a004fb97e7809c4a8171b081b9','adfc88126c6d7ee047fd7fed7eda6b3b536c9e1fe0baffafbedc290b6c5554d6',22374],
 ['i_remote_mcp/oauth.mjs','2597ddfe8a724812763595e2d4b43aadd65a5488','53dda48003b8b0b7da27c7a10895f31863398e1c42fe5e5ed017608f129755b5',19860],
 ['i_remote_mcp/diagnostics.mjs','0f78d2bbd75a250aec8ad6b53d6d8cbff90bd31d','b60230926d0fa8cbcf2cbfefa5667656190507d828fc953605837d8f04e5b4f7',5030],
 ['i_remote_mcp/mcp.mjs','6b1e0927ff81b9ae513259a6df0fb101e183586b','4bdd55dd3bd41e4ff0e16cdce08b2c58dce007d6fe6eaee51cc2110cdfc7d09b',20159],
 ['i_remote_mcp/writeback.mjs','3d4236b4b294f77b193e6c9030b96934e9e390f1','f2aac48db1cf61a44a0c9b5b28087b90894f03396cd52830a4428532944bc52a',29165],
 ['i_memory/i_memory_read.mjs','4181efc33dae883b56d1ec88ca3aad05a3a44cfa','cee185180b825a141b645a12ab1f1812a61b9eb7462c347465b7ac4449af4e28',21378],
].map(([path,blob,sha256,bytes])=>Object.freeze({path,blob,sha256,bytes})));
const MAIN_BLOBS = {diagnostics:'ab599709c3e8efe8594637c97c8cb6783adb05be',server:'c598b7329f95517ba9bf30777882d8a1913eb7c0',oauth:'f95e05ced4a5cdc119062c4a1dc7f90cfb85fc40',mcp:'aa60d5ab40da538d8f77a4f19eec0bdf9fac094a',writeback:'3d4236b4b294f77b193e6c9030b96934e9e390f1'};
// Literal reviewed compatibility hunks. No patch is inferred from the caller's working tree.
const PATCHES = {
  "server": [
    [
      "import { OAuthServer, revokeAll, setPassphrase } from './oauth.mjs';\n",
      "import { OAuthServer, chatgptEnabledFromEnv, revokeAll, setPassphrase } from './oauth.mjs';\n"
    ],
    [
      "const DEFAULT_ALLOWED_ORIGINS = ['https://claude.ai', 'https://claude.com'];\n",
      "const DEFAULT_ALLOWED_ORIGINS = ['https://claude.ai', 'https://claude.com'];\nconst CHATGPT_ORIGIN = 'https://chatgpt.com';\nconst CHATGPT_CORS_HEADERS = ['accept', 'authorization', 'content-type', 'mcp-session-id', 'mcp-protocol-version'];\n"
    ],
    [
      "  allowedOrigins = DEFAULT_ALLOWED_ORIGINS,\n",
      "  allowedOrigins = DEFAULT_ALLOWED_ORIGINS,\n  chatgptEnabled = chatgptEnabledFromEnv(),\n"
    ],
    [
      "  const oauth = new OAuthServer({ stateDir, publicUrl, now, options: oauthOptions, writeEnabled });\n",
      "  const oauth = new OAuthServer({ stateDir, publicUrl, now, options: oauthOptions, writeEnabled, chatgptEnabled });\n"
    ],
    [
      "  const origins = new Set([...allowedOrigins, oauth.issuer]);\n",
      "  const origins = new Set([...allowedOrigins, oauth.issuer, ...(chatgptEnabled ? [CHATGPT_ORIGIN] : [])]);\n"
    ],
    [
      "    if (origin && !origins.has(origin)) return sendJson(res, 403, { error: 'forbidden_origin' });\n",
      "    if (origin && !origins.has(origin)) return sendJson(res, 403, { error: 'forbidden_origin' });\n    // Only the explicitly enabled exact ChatGPT origin gets browser CORS.\n    // OPTIONS discloses no data; every actual MCP request still needs OAuth.\n    if (chatgptEnabled && origin === CHATGPT_ORIGIN) {\n      res.setHeader('Access-Control-Allow-Origin', CHATGPT_ORIGIN);\n      res.setHeader('Vary', 'Origin');\n      res.setHeader('Access-Control-Expose-Headers', 'Mcp-Session-Id, WWW-Authenticate');\n      if (req.method === 'OPTIONS') {\n        const method = req.headers['access-control-request-method'];\n        const headers = String(req.headers['access-control-request-headers'] ?? '')\n          .split(',').map((value) => value.trim().toLowerCase()).filter(Boolean);\n        if (!['POST', 'DELETE'].includes(method) || headers.some((value) => !CHATGPT_CORS_HEADERS.includes(value))) {\n          return sendJson(res, 403, { error: 'forbidden_preflight' });\n        }\n        res.setHeader('Access-Control-Allow-Methods', 'POST, DELETE');\n        res.setHeader('Access-Control-Allow-Headers', CHATGPT_CORS_HEADERS.join(', '));\n        return sendEmpty(res, 204);\n      }\n    }\n"
    ],
    [
      "  const publicUrl = args['public-url'] ?? process.env.I_REMOTE_MCP_PUBLIC_URL ?? `http://${host}:${port}`;\n",
      "  const publicUrl = args['public-url'] ?? process.env.I_REMOTE_MCP_PUBLIC_URL ?? `http://${host}:${port}`;\n  const chatgptEnabled = chatgptEnabledFromEnv();\n"
    ],
    [
      "    publicUrl,\n",
      "    publicUrl,\n    chatgptEnabled,\n"
    ]
  ],
  "oauth": [
    [
      "// 单用户最小 OAuth 2.1 授权服务器（claude.ai 自定义 connector 用）。\n",
      "// 单用户最小 OAuth 2.1 授权服务器（Claude 默认，ChatGPT 显式启用）。\n"
    ],
    [
      "export const WRITE_SCOPE = 'i.write';\n",
      "export const WRITE_SCOPE = 'i.write';\nexport const CHATGPT_CALLBACK_URI = 'https://chatgpt.com/connector_platform_oauth_redirect';\n"
    ],
    [
      "// 以后接 ChatGPT 等其他客户端时，用 I_REMOTE_MCP_EXTRA_REDIRECT_URIS（逗号分隔、精确匹配的 https 地址）追加。\n",
      "// ChatGPT 使用独立开关和稳定精确回调；其他客户端仍可显式追加精确 HTTPS 地址。\n"
    ],
    [
      "export function isAllowedRedirectUri(value, extra = extraRedirectUris()) {\n",
      "export function chatgptEnabledFromEnv(env = process.env) {\n  const value = env.I_REMOTE_MCP_CHATGPT_ENABLED;\n  if (value === undefined || value === '0') return false;\n  if (value === '1') return true;\n  throw new Error('invalid_chatgpt_mode');\n}\n\nexport function isAllowedRedirectUri(value, extra = extraRedirectUris(), chatgptEnabled = chatgptEnabledFromEnv()) {\n"
    ],
    [
      "  if (CLAUDE_AI_CALLBACKS.includes(value)) return true;\n",
      "  if (CLAUDE_AI_CALLBACKS.includes(value)) return true;\n  if (chatgptEnabled === true && value === CHATGPT_CALLBACK_URI) return true;\n"
    ],
    [
      "  constructor({ stateDir, publicUrl, now = () => Date.now(), options = {}, writeEnabled = false }) {\n",
      "  constructor({ stateDir, publicUrl, now = () => Date.now(), options = {}, writeEnabled = false, chatgptEnabled = chatgptEnabledFromEnv() }) {\n    if (typeof chatgptEnabled !== 'boolean') throw new Error('invalid_chatgpt_mode');\n    this.chatgptEnabled = chatgptEnabled;\n"
    ],
    [
      "      issuer: this.issuer,\n",
      "      issuer: this.issuer,\n      authorization_response_iss_parameter_supported: true,\n"
    ],
    [
      "    if (!redirectUris.every((uri) => isAllowedRedirectUri(uri))) {\n",
      "    if (!redirectUris.every((uri) => isAllowedRedirectUri(uri, extraRedirectUris(), this.chatgptEnabled))) {\n"
    ],
    [
      "    if (!redirectUri || !client.redirect_uris.includes(redirectUri) || !isAllowedRedirectUri(redirectUri)) {\n",
      "    if (!redirectUri || !client.redirect_uris.includes(redirectUri) || !isAllowedRedirectUri(redirectUri, extraRedirectUris(), this.chatgptEnabled)) {\n"
    ]
  ]
};
PATCHES.mcp = [['在 claude.ai 的 connector 设置里','在当前客户端的连接器设置里']];

// Contract B identity changes are literal, reviewed separately for the mainline
// and frozen legacy runtime. Mainline W3 code never enters the candidate.
const FRONTEND_PATCHES = {
  "mainline": {
    "server": [
      [
        "  createCoreFrontendClient,\n  createWriteback,\n  issuePhoneToken,\n  loadFrontendCredential,\n",
        "  createCoreFrontendClient,\n  createWriteback,\n  frontendDefinition,\n  issuePhoneToken,\n  loadFrontendCredential,\n"
      ],
      [
        "  diagnostic = () => {},\n  writeback = null,\n  coreRemember = null,\n  domainTools = null,\n",
        "  diagnostic = () => {},\n  writeback = null,\n  chatgptWriteback = null,\n  coreRemember = null,\n  domainTools = null,\n"
      ],
      [
        "  if (!publicUrl) throw new Error('publicUrl is required');\n  if (typeof getReadModel !== 'function') throw new Error('getReadModel is required');\n  const writeEnabled = Boolean(writeback || coreRemember);\n  const oauth = new OAuthServer({ stateDir, publicUrl, now, options: oauthOptions, writeEnabled, chatgptEnabled });\n  if(domainTools&&(domainTools.tools.some(tool=>!WEB_DOMAIN_TOOLS.includes(tool.name))||Object.keys(domainTools.handlers).some(name=>!domainTools.tools.some(tool=>tool.name===name))))throw new Error('planner_tools_forbidden_on_web');\n  const handlers = {...createToolHandlers({ getReadModel, identityLoader, now, timeZone, writeback, coreRemember }),...domainTools?.handlers};\n  const tools = [...listTools({ writeEnabled:Boolean(writeback),coreRemember:Boolean(coreRemember) }),...(domainTools?.tools??[]).map(tool=>({...tool,requiredScope:tool.name==='capture_add'?'i.write':'i.read'}))];\n  const origins = new Set([...allowedOrigins, oauth.issuer, ...(chatgptEnabled ? [CHATGPT_ORIGIN] : [])]);\n  const sessions = new Map();\n",
        "  if (!publicUrl) throw new Error('publicUrl is required');\n  if (typeof getReadModel !== 'function') throw new Error('getReadModel is required');\n  const writeEnabled = Boolean(writeback || chatgptWriteback || coreRemember);\n  const oauth = new OAuthServer({ stateDir, publicUrl, now, options: oauthOptions, writeEnabled, chatgptEnabled });\n  if(domainTools&&(domainTools.tools.some(tool=>!WEB_DOMAIN_TOOLS.includes(tool.name))||Object.keys(domainTools.handlers).some(name=>!domainTools.tools.some(tool=>tool.name===name))))throw new Error('planner_tools_forbidden_on_web');\n  const handlers = {...createToolHandlers({ getReadModel, identityLoader, now, timeZone, writeback, coreRemember }),...domainTools?.handlers};\n  const tools = [...listTools({ writeEnabled:Boolean(writeback),coreRemember:Boolean(coreRemember) }),...(domainTools?.tools??[]).map(tool=>({...tool,requiredScope:tool.name==='capture_add'?'i.write':'i.read'}))];\n  // These handlers are selected only from the verified OAuth token, never MCP arguments.\n  const chatgptDomainTools = (domainTools?.tools ?? []).filter(tool => ['week_get', 'day_get'].includes(tool.name));\n  const chatgptHandlers = { ...createToolHandlers({ getReadModel, identityLoader, now, timeZone,\n    writeback: chatgptWriteback,\n    frontend: 'chatgpt_web' }),\n    ...Object.fromEntries(chatgptDomainTools.map(tool => [tool.name, domainTools.handlers[tool.name]])) };\n  if (writeEnabled && !chatgptWriteback) {\n    chatgptHandlers.i_chat_turn = async () => { throw new WritebackInputError('frontend_not_paired:chatgpt_web'); };\n  }\n  const chatgptTools = [...listTools({ writeEnabled, frontend: 'chatgpt_web' }),\n    ...chatgptDomainTools.map(tool => ({ ...tool, requiredScope: 'i.read' }))];\n  const origins = new Set([...allowedOrigins, oauth.issuer, ...(chatgptEnabled ? [CHATGPT_ORIGIN] : [])]);\n  const sessions = new Map();\n"
      ],
      [
        "      let dataSourceFailed = false;\n      const response = await handleRpcMessage(message, {\n        handlers,\n        tools,\n        scopes: auth.scopes,\n        session,\n",
        "      let dataSourceFailed = false;\n      const response = await handleRpcMessage(message, {\n        handlers: auth.frontend === 'chatgpt_web' ? chatgptHandlers : handlers,\n        tools: auth.frontend === 'chatgpt_web' ? chatgptTools : tools,\n        unavailableTools: auth.frontend === 'chatgpt_web' && !chatgptWriteback\n          ? { i_chat_turn: 'frontend_not_paired:chatgpt_web' } : {},\n        scopes: auth.scopes,\n        session,\n"
      ],
      [
        "  const coreUrl = String(args['core-url'] ?? process.env.I_CORE_URL ?? DEFAULTS.coreUrl).replace(/\\/+$/, '');\n  if (command === 'pair-core') {\n    // i_core 需临时以 I_CORE_PAIRING_CODE 启动（打开配对窗口）；这里输入同一个一次性配对码。\n    const code = (await readSecret('i_core 一次性配对码：')).trim();\n    if (!code) throw new Error('配对码为空');\n    const paired = await pairFrontendDevice({ coreUrl, pairingCode: code, stateDir });\n    process.stderr.write(`已配对 ${paired.device_id}；令牌保存在 ${stateDir}/core-frontend.json（勿提交）。\\n`);\n    return;\n  }\n",
        "  const coreUrl = String(args['core-url'] ?? process.env.I_CORE_URL ?? DEFAULTS.coreUrl).replace(/\\/+$/, '');\n  if (command === 'pair-core') {\n    const definition = frontendDefinition(args.frontend);\n    // i_core 需临时以 I_CORE_PAIRING_CODE 启动（打开配对窗口）；这里输入同一个一次性配对码。\n    const code = (await readSecret('i_core 一次性配对码：')).trim();\n    if (!code) throw new Error('配对码为空');\n    const paired = await pairFrontendDevice({ coreUrl, pairingCode: code, stateDir, frontend: definition.name });\n    process.stderr.write(`已配对 ${paired.device_id}；令牌保存在 ${stateDir}/${definition.credentialFile}（勿提交）。\\n`);\n    return;\n  }\n"
      ],
      [
        "    process.stderr.write('写回未启用（未配对 i_core 或 I_REMOTE_MCP_WRITEBACK=0），只开放只读工具。\\n');\n  }\n  const { server, oauth } = createApp({\n    stateDir,\n",
        "    process.stderr.write('写回未启用（未配对 i_core 或 I_REMOTE_MCP_WRITEBACK=0），只开放只读工具。\\n');\n  }\n  let chatgptWriteback = null;\n  if (chatgptEnabled && process.env.I_REMOTE_MCP_WRITEBACK !== '0') {\n    const credential = loadFrontendCredential(stateDir, 'chatgpt_web');\n    if (credential) chatgptWriteback = createWriteback({\n      ledger: openLedger(resolve(stateDir, 'writeback.sqlite')),\n      frontend: 'chatgpt_web',\n      coreClient: createCoreFrontendClient({ coreUrl, deviceToken: credential.device_token, frontend: 'chatgpt_web' }),\n    });\n  }\n  const { server, oauth } = createApp({\n    stateDir,\n"
      ],
      [
        "    diagnostic,\n    writeback,\n    ...loadWebDomainOptions(args['domain-config']),\n  });\n",
        "    diagnostic,\n    writeback,\n    chatgptWriteback,\n    ...loadWebDomainOptions(args['domain-config']),\n  });\n"
      ],
      [
        "    process.stderr.write(`i remote MCP 监听 http://${host}:${port}/mcp ，对外地址 ${oauth.resource}\\n`);\n  });\n  const shutdown = () => { server.close(); phoneServer?.close(); getReadModel.close(); writeback?.close(); };\n  process.on('SIGINT', shutdown);\n  process.on('SIGTERM', shutdown);\n",
        "    process.stderr.write(`i remote MCP 监听 http://${host}:${port}/mcp ，对外地址 ${oauth.resource}\\n`);\n  });\n  const shutdown = () => { server.close(); phoneServer?.close(); getReadModel.close(); writeback?.close(); chatgptWriteback?.close(); };\n  process.on('SIGINT', shutdown);\n  process.on('SIGTERM', shutdown);\n"
      ]
    ],
    "oauth": [
      [
        "  'https://claude.com/api/mcp/auth_callback',\n]);\n\nconst STATE_SCHEMA_VERSION = 1;\n",
        "  'https://claude.com/api/mcp/auth_callback',\n]);\n\nfunction frontendForRedirectUri(redirectUri) {\n  return redirectUri === CHATGPT_CALLBACK_URI ? 'chatgpt_web' : 'claude_web';\n}\n\nfunction frontendForRegisteredClient(client) {\n  return Array.isArray(client?.redirect_uris)\n    && client.redirect_uris.length === 1\n    && client.redirect_uris[0] === CHATGPT_CALLBACK_URI\n    ? 'chatgpt_web'\n    : 'claude_web';\n}\n\nconst STATE_SCHEMA_VERSION = 1;\n"
      ],
      [
        "      client_id: params.client_id,\n      redirect_uri: params.redirect_uri,\n      code_challenge: params.code_challenge,\n      resource: this.resource,\n",
        "      client_id: params.client_id,\n      redirect_uri: params.redirect_uri,\n      frontend: frontendForRedirectUri(params.redirect_uri),\n      code_challenge: params.code_challenge,\n      resource: this.resource,\n"
      ],
      [
        "    record.used = true;\n    record.family_id = familyId;\n    const tokens = this.#issueTokens(client.client_id, familyId, record.scope ?? SCOPE);\n    this.store.save();\n    return { status: 200, body: tokens };\n",
        "    record.used = true;\n    record.family_id = familyId;\n    const tokens = this.#issueTokens(client.client_id, familyId, record.scope ?? SCOPE, record.frontend ?? frontendForRedirectUri(record.redirect_uri));\n    this.store.save();\n    return { status: 200, body: tokens };\n"
      ],
      [
        "    record.rotated = true;\n    // 刷新不扩大权限；旧版本签发的 refresh token 没有 scope 字段，视为只读。\n    const tokens = this.#issueTokens(client.client_id, record.family_id, this.#limitScope(record.scope ?? SCOPE));\n    this.store.save();\n    return { status: 200, body: tokens };\n",
        "    record.rotated = true;\n    // 刷新不扩大权限；旧版本签发的 refresh token 没有 scope 字段，视为只读。\n    const tokens = this.#issueTokens(client.client_id, record.family_id, this.#limitScope(record.scope ?? SCOPE), record.frontend ?? frontendForRegisteredClient(client));\n    this.store.save();\n    return { status: 200, body: tokens };\n"
      ],
      [
        "  }\n\n  #issueTokens(clientId, familyId, scope) {\n    scope = this.#limitScope(scope);\n    const now = this.now();\n",
        "  }\n\n  #issueTokens(clientId, familyId, scope, frontend = 'claude_web') {\n    scope = this.#limitScope(scope);\n    const now = this.now();\n"
      ],
      [
        "      resource: this.resource,\n      scope,\n      expires_at: now + this.options.accessTokenTtlMs,\n    };\n",
        "      resource: this.resource,\n      scope,\n      frontend,\n      expires_at: now + this.options.accessTokenTtlMs,\n    };\n"
      ],
      [
        "      family_id: familyId,\n      scope,\n      expires_at: now + this.options.refreshTokenTtlMs,\n      rotated: false,\n",
        "      family_id: familyId,\n      scope,\n      frontend,\n      expires_at: now + this.options.refreshTokenTtlMs,\n      rotated: false,\n"
      ],
      [
        "    // 服务关闭写回后，旧的写令牌也只按当前支持的 scope 生效。\n    const scopes = String(record.scope ?? SCOPE).split(' ').filter((s) => this.supportedScopes.includes(s));\n    return { ok: true, familyId: record.family_id, clientId: record.client_id, scopes };\n  }\n}\n",
        "    // 服务关闭写回后，旧的写令牌也只按当前支持的 scope 生效。\n    const scopes = String(record.scope ?? SCOPE).split(' ').filter((s) => this.supportedScopes.includes(s));\n    return {\n      ok: true,\n      familyId: record.family_id,\n      clientId: record.client_id,\n      frontend: record.frontend ?? frontendForRegisteredClient(this.store.state.clients[record.client_id]),\n      scopes,\n    };\n  }\n}\n"
      ]
    ],
    "mcp": [
      [
        "]);\n\nexport function listTools({ writeEnabled = false, coreRemember = false } = {}) {\n  return writeEnabled ? [...TOOLS, ...WRITE_TOOLS.map(tool=>coreRemember&&tool.name==='i_remember'?CORE_REMEMBER_TOOL:tool)] : [...TOOLS,...(coreRemember?[CORE_REMEMBER_TOOL]:[])];\n}\n\n",
        "]);\n\nexport function listTools({ writeEnabled = false, coreRemember = false, frontend = 'claude_web' } = {}) {\n  const writes = WRITE_TOOLS.filter(tool => frontend === 'claude_web' || tool.name === 'i_chat_turn')\n    .map(tool => tool.name === 'i_chat_turn'\n      ? { ...tool, description: tool.description.replace('claude_web', frontend) }\n      : coreRemember ? CORE_REMEMBER_TOOL : tool);\n  return writeEnabled ? [...TOOLS, ...writes] : [...TOOLS, ...(coreRemember && frontend === 'claude_web' ? [CORE_REMEMBER_TOOL] : [])];\n}\n\n"
      ],
      [
        "// ---------- 工具实现 ----------\n\nexport function createToolHandlers({ getReadModel, identityLoader = loadIdentity, now = () => Date.now(), timeZone, writeback = null, coreRemember = null }) {\n  const notes = coreRemember ?? writeback;\n  async function readNotes(method,...args) {\n    if(!coreRemember)return {items:await notes[method](...args)};\n",
        "// ---------- 工具实现 ----------\n\nexport function createToolHandlers({ getReadModel, identityLoader = loadIdentity, now = () => Date.now(), timeZone, writeback = null, coreRemember = null, frontend = 'claude_web' }) {\n  const notes = frontend === 'claude_web' ? coreRemember ?? writeback : null;\n  async function readNotes(method,...args) {\n    if(!coreRemember)return {items:await notes[method](...args)};\n"
      ],
      [
        "\n  handlers.i_chat_turn = async (args) => {\n    const phase = args.phase ?? 'start';\n    if (phase !== 'start' && phase !== 'end') throw new ToolInputError('phase 只能是 start 或 end');\n",
        "\n  handlers.i_chat_turn = async (args) => {\n    if (Object.keys(args).some(key => ['frontend', 'source', 'device_id', 'origin_device_id', 'sync_id'].includes(key))) {\n      throw new ToolInputError('invalid_chat_turn_arguments');\n    }\n    const phase = args.phase ?? 'start';\n    if (phase !== 'start' && phase !== 'end') throw new ToolInputError('phase 只能是 start 或 end');\n"
      ],
      [
        "      now: currentTime(now(), timeZone),\n      recent_messages: recent.map(projectMessage),\n      ...await recentNotes(),\n    };\n  };\n",
        "      now: currentTime(now(), timeZone),\n      recent_messages: recent.map(projectMessage),\n      ...(notes ? await recentNotes() : {}),\n    };\n  };\n"
      ],
      [
        "// 处理一条 JSON-RPC 消息；通知/响应返回 null。\nexport async function handleRpcMessage(message, {\n  handlers, session, logError = () => {}, tools = TOOLS, scopes = [READ_SCOPE], instructions = null,\n}) {\n  if (!message || typeof message !== 'object' || message.jsonrpc !== '2.0') {\n",
        "// 处理一条 JSON-RPC 消息；通知/响应返回 null。\nexport async function handleRpcMessage(message, {\n  handlers, session, logError = () => {}, tools = TOOLS, scopes = [READ_SCOPE], instructions = null, unavailableTools = {},\n}) {\n  if (!message || typeof message !== 'object' || message.jsonrpc !== '2.0') {\n"
      ],
      [
        "          version: SERVER_VERSION,\n        },\n        instructions: instructions ?? (tools.length > TOOLS.length ? SERVER_INSTRUCTIONS_WRITE : SERVER_INSTRUCTIONS),\n      });\n    }\n",
        "          version: SERVER_VERSION,\n        },\n        instructions: instructions ?? (tools.some(tool => tool.name === 'i_remember') ? SERVER_INSTRUCTIONS_WRITE\n          : tools.some(tool => tool.name === 'i_chat_turn') ? SERVER_INSTRUCTIONS_WRITE.replace('用户明确说“帮我记一下”时用 i_remember。', '')\n          : SERVER_INSTRUCTIONS),\n      });\n    }\n"
      ],
      [
        "      const tool = tools.find((t) => t.name === name);\n      const handler = tool && Object.hasOwn(handlers, name) ? handlers[name] : null;\n      if (!handler) return rpcError(id, -32602, `Unknown tool: ${String(name).slice(0, 64)}`);\n      if (typeof args !== 'object' || args === null || Array.isArray(args)) return rpcError(id, -32602, 'arguments must be an object');\n      if (tool.requiredScope && !scopes.includes(tool.requiredScope)) {\n",
        "      const tool = tools.find((t) => t.name === name);\n      const handler = tool && Object.hasOwn(handlers, name) ? handlers[name] : null;\n      if (!handler) return Object.hasOwn(unavailableTools, name)\n        ? rpcResult(id, toolError(unavailableTools[name]))\n        : rpcError(id, -32602, `Unknown tool: ${String(name).slice(0, 64)}`);\n      if (typeof args !== 'object' || args === null || Array.isArray(args)) return rpcError(id, -32602, 'arguments must be an object');\n      if (tool.requiredScope && !scopes.includes(tool.requiredScope)) {\n"
      ]
    ],
    "writeback": [
      [
        "import { DatabaseSync } from 'node:sqlite';\n\nexport const FRONTEND_NAME = 'claude_web';\nexport const FRONTEND_DEVICE_ID = `frontend:${FRONTEND_NAME}`;\nexport const FRONTEND_PLATFORM = 'external-frontend';\n",
        "import { DatabaseSync } from 'node:sqlite';\n\nexport const FRONTENDS = Object.freeze({\n  claude_web: Object.freeze({ name: 'claude_web', deviceId: 'frontend:claude_web', displayName: 'claude.ai 网页端', credentialFile: 'core-frontend.json' }),\n  chatgpt_web: Object.freeze({ name: 'chatgpt_web', deviceId: 'frontend:chatgpt_web', displayName: 'ChatGPT 网页端', credentialFile: 'core-frontend-chatgpt_web.json' }),\n});\nexport const FRONTEND_NAME = 'claude_web';\n\nexport function frontendDefinition(frontend = FRONTEND_NAME) {\n  if (!Object.hasOwn(FRONTENDS, frontend)) throw new WritebackInputError('invalid_frontend');\n  return FRONTENDS[frontend];\n}\nexport const FRONTEND_DEVICE_ID = `frontend:${FRONTEND_NAME}`;\nexport const FRONTEND_PLATFORM = 'external-frontend';\n"
      ],
      [
        "    CREATE INDEX IF NOT EXISTS notes_active_idx ON notes(status, updated_at_ms);\n  `);\n  const columns = new Set(db.prepare('PRAGMA table_info(turns)').all().map((c) => c.name));\n  if (!columns.has('sketch')) db.exec('ALTER TABLE turns ADD COLUMN sketch TEXT');\n",
        "    CREATE INDEX IF NOT EXISTS notes_active_idx ON notes(status, updated_at_ms);\n  `);\n  db.exec(\"CREATE TABLE IF NOT EXISTS thread_frontends (thread_id TEXT PRIMARY KEY, frontend TEXT NOT NULL)\");\n  const columns = new Set(db.prepare('PRAGMA table_info(turns)').all().map((c) => c.name));\n  if (!columns.has('sketch')) db.exec('ALTER TABLE turns ADD COLUMN sketch TEXT');\n"
      ],
      [
        "}\n\nexport function loadFrontendCredential(stateDir) {\n  const path = join(stateDir, 'core-frontend.json');\n  if (!existsSync(path)) return null;\n  const parsed = JSON.parse(readFileSync(path, 'utf8'));\n  if (parsed?.device_id !== FRONTEND_DEVICE_ID || typeof parsed.device_token !== 'string') {\n    throw new Error('core-frontend.json is invalid');\n  }\n  return parsed;\n",
        "}\n\nexport function loadFrontendCredential(stateDir, frontend = FRONTEND_NAME) {\n  const definition = frontendDefinition(frontend);\n  const path = join(stateDir, definition.credentialFile);\n  if (!existsSync(path)) return null;\n  const parsed = JSON.parse(readFileSync(path, 'utf8'));\n  if (parsed?.device_id !== definition.deviceId || typeof parsed.device_token !== 'string' || !parsed.device_token) {\n    throw new Error(definition.credentialFile + ' is invalid');\n  }\n  return parsed;\n"
      ],
      [
        "}\n\nexport async function pairFrontendDevice({ coreUrl, pairingCode, stateDir, fetchImpl = fetch }) {\n  const res = await fetchImpl(`${coreUrl}/v1/core/devices/pair`, {\n    method: 'POST',\n    headers: { 'content-type': 'application/json' },\n    body: JSON.stringify({\n      device_id: FRONTEND_DEVICE_ID,\n      display_name: 'claude.ai 网页端',\n      platform: FRONTEND_PLATFORM,\n      client_version: '0.1',\n",
        "}\n\nexport async function pairFrontendDevice({ coreUrl, pairingCode, stateDir, frontend = FRONTEND_NAME, fetchImpl = fetch }) {\n  const definition = frontendDefinition(frontend);\n  const res = await fetchImpl(`${coreUrl}/v1/core/devices/pair`, {\n    method: 'POST',\n    headers: { 'content-type': 'application/json' },\n    body: JSON.stringify({\n      device_id: definition.deviceId,\n      display_name: definition.displayName,\n      platform: FRONTEND_PLATFORM,\n      client_version: '0.1',\n"
      ],
      [
        "    throw new Error(`pairing failed: ${body?.error?.code ?? res.status}`);\n  }\n  saveJsonPrivate(join(stateDir, 'core-frontend.json'), {\n    device_id: FRONTEND_DEVICE_ID,\n    device_token: body.device_token,\n    core_node_id: body.core_node_id ?? null,\n    paired_at: new Date().toISOString(),\n  });\n  return { device_id: FRONTEND_DEVICE_ID, core_node_id: body.core_node_id ?? null };\n}\n\nexport function createCoreFrontendClient({ coreUrl, deviceToken, fetchImpl = fetch, timeoutMs = 10_000 }) {\n  return {\n    async submit(messages) {\n",
        "    throw new Error(`pairing failed: ${body?.error?.code ?? res.status}`);\n  }\n  saveJsonPrivate(join(stateDir, definition.credentialFile), {\n    device_id: definition.deviceId,\n    device_token: body.device_token,\n    core_node_id: body.core_node_id ?? null,\n    paired_at: new Date().toISOString(),\n  });\n  return { device_id: definition.deviceId, core_node_id: body.core_node_id ?? null };\n}\n\nexport function createCoreFrontendClient({ coreUrl, deviceToken, frontend = FRONTEND_NAME, fetchImpl = fetch, timeoutMs = 10_000 }) {\n  const definition = frontendDefinition(frontend);\n  return {\n    async submit(messages) {\n"
      ],
      [
        "            authorization: `Bearer ${deviceToken}`,\n          },\n          body: JSON.stringify({ device_id: FRONTEND_DEVICE_ID, messages }),\n          signal: AbortSignal.timeout(timeoutMs),\n        });\n",
        "            authorization: `Bearer ${deviceToken}`,\n          },\n          body: JSON.stringify({ device_id: definition.deviceId, messages }),\n          signal: AbortSignal.timeout(timeoutMs),\n        });\n"
      ],
      [
        "  ledger,\n  coreClient,\n  now = () => Date.now(),\n  rateLimiter = new RateLimiter(DEFAULT_RATE_LIMITS, now),\n}) {\n  const db = ledger;\n\n  function validateTurns(args) {\n",
        "  ledger,\n  coreClient,\n  frontend = FRONTEND_NAME,\n  now = () => Date.now(),\n  rateLimiter = new RateLimiter(DEFAULT_RATE_LIMITS, now),\n}) {\n  const db = ledger;\n  const definition = frontendDefinition(frontend);\n\n  function validateTurns(args) {\n"
      ],
      [
        "    const t = now();\n    return transaction(db, () => {\n      const thread = db.prepare('SELECT thread_id FROM threads WHERE thread_id = ?').get(threadId);\n      if (thread) db.prepare('UPDATE threads SET last_seen_ms = ? WHERE thread_id = ?').run(t, threadId);\n      else db.prepare('INSERT INTO threads(thread_id, created_at_ms, last_seen_ms) VALUES (?, ?, ?)').run(threadId, t, t);\n      const existingRows = db.prepare(`\n        SELECT role, turn_key, sketch, created_at_ms FROM turns WHERE thread_id = ? ORDER BY seq DESC LIMIT ?\n",
        "    const t = now();\n    return transaction(db, () => {\n      const thread = db.prepare(\"SELECT thread_id, COALESCE(thread_frontends.frontend, 'claude_web') AS frontend FROM threads LEFT JOIN thread_frontends USING (thread_id) WHERE thread_id = ?\").get(threadId);\n      if (thread && thread.frontend !== frontend) throw new WritebackInputError('thread_frontend_mismatch');\n      if (thread) db.prepare('UPDATE threads SET last_seen_ms = ? WHERE thread_id = ?').run(t, threadId);\n      else {\n        db.prepare('INSERT INTO threads(thread_id, created_at_ms, last_seen_ms) VALUES (?, ?, ?)').run(threadId, t, t);\n        db.prepare('INSERT INTO thread_frontends(thread_id, frontend) VALUES (?, ?)').run(threadId, frontend);\n      }\n      const existingRows = db.prepare(`\n        SELECT role, turn_key, sketch, created_at_ms FROM turns WHERE thread_id = ? ORDER BY seq DESC LIMIT ?\n"
      ],
      [
        "      if (!thread || existing.length === 0) {\n        // 新线程（Claude 丢了 thread_id 或新对话）：用最近 24 小时的全局轮次识别重传。\n        for (const row of db.prepare('SELECT turn_key FROM turns WHERE created_at_ms >= ?').all(t - LIMITS.globalDedupWindowMs)) {\n          known.add(row.turn_key);\n        }\n",
        "      if (!thread || existing.length === 0) {\n        // 新线程（Claude 丢了 thread_id 或新对话）：用最近 24 小时的全局轮次识别重传。\n        for (const row of db.prepare(\"SELECT turn_key FROM turns LEFT JOIN thread_frontends USING (thread_id) WHERE COALESCE(frontend, 'claude_web') = ? AND turns.created_at_ms >= ?\").all(frontend, t - LIMITS.globalDedupWindowMs)) {\n          known.add(row.turn_key);\n        }\n"
      ],
      [
        "          created = threadLast + Math.max(1, Math.floor((current - threadLast) * (index + 1) / (backfillCount + 1)));\n        } else created = current - (backfillCount - index);\n        insert.run(threadId, seq, turn.role, keys[start + index], `${FRONTEND_NAME}:${threadId}:${seq}`,\n          nextOriginSequence(db, t), characterId, created, turn.content, sketches[start + index], isCurrent ? 0 : 1);\n      });\n",
        "          created = threadLast + Math.max(1, Math.floor((current - threadLast) * (index + 1) / (backfillCount + 1)));\n        } else created = current - (backfillCount - index);\n        insert.run(threadId, seq, turn.role, keys[start + index], `${frontend}:${threadId}:${seq}`,\n          nextOriginSequence(db, t), characterId, created, turn.content, sketches[start + index], isCurrent ? 0 : 1);\n      });\n"
      ],
      [
        "    return {\n      sync_id: row.sync_id,\n      origin_device_id: FRONTEND_DEVICE_ID,\n      origin_sequence: Number(row.origin_sequence),\n      character_id: row.character_id,\n",
        "    return {\n      sync_id: row.sync_id,\n      origin_device_id: definition.deviceId,\n      origin_sequence: Number(row.origin_sequence),\n      character_id: row.character_id,\n"
      ],
      [
        "  async function flush() {\n    const rows = db.prepare(`\n      SELECT * FROM turns WHERE status = 'pending' ORDER BY origin_sequence LIMIT ?\n    `).all(LIMITS.maxPendingFlush);\n    let rejected = 0;\n    for (let i = 0; i < rows.length; i += LIMITS.coreBatch) {\n",
        "  async function flush() {\n    const rows = db.prepare(`\n      SELECT turns.* FROM turns LEFT JOIN thread_frontends USING (thread_id) WHERE status = 'pending' AND COALESCE(frontend, 'claude_web') = ? ORDER BY origin_sequence LIMIT ?\n    `).all(frontend, LIMITS.maxPendingFlush);\n    let rejected = 0;\n    for (let i = 0; i < rows.length; i += LIMITS.coreBatch) {\n"
      ],
      [
        "\n  return {\n    async chatTurn(args, { characterId }) {\n      const threadId = args.thread_id === undefined || args.thread_id === null || args.thread_id === ''\n        ? newId('t') : args.thread_id;\n",
        "\n  return {\n    frontend,\n    async chatTurn(args, { characterId }) {\n      const identityFields = ['frontend', 'source', 'device_id', 'origin_device_id', 'sync_id'];\n      if (Object.keys(args).some(key => identityFields.includes(key))) throw new WritebackInputError('invalid_chat_turn_arguments');\n      if (!coreClient) throw new WritebackInputError('frontend_not_paired:' + frontend);\n      const threadId = args.thread_id === undefined || args.thread_id === null || args.thread_id === ''\n        ? newId('t') : args.thread_id;\n"
      ],
      [
        "      const plan = planTurns(threadId, turns, characterId, phase);\n      const result = await flush();\n      const pending = Number(db.prepare(\"SELECT COUNT(*) AS n FROM turns WHERE status = 'pending'\").get().n);\n      return {\n        thread_id: threadId,\n",
        "      const plan = planTurns(threadId, turns, characterId, phase);\n      const result = await flush();\n      const pending = Number(db.prepare(\"SELECT COUNT(*) AS n FROM turns LEFT JOIN thread_frontends USING (thread_id) WHERE status = 'pending' AND COALESCE(frontend, 'claude_web') = ?\").get(frontend).n);\n      return {\n        thread_id: threadId,\n"
      ],
      [
        "\n    remember(args) {\n      const action = args.action ?? 'add';\n      if (!['add', 'update', 'delete', 'list'].includes(action)) {\n",
        "\n    remember(args) {\n      if (frontend !== FRONTEND_NAME) throw new WritebackInputError('frontend_forbidden:' + frontend);\n      const action = args.action ?? 'add';\n      if (!['add', 'update', 'delete', 'list'].includes(action)) {\n"
      ]
    ]
  },
  "legacy": {
    "oauth": [
      [
        "  'https://claude.com/api/mcp/auth_callback',\n]);\n\nconst STATE_SCHEMA_VERSION = 1;\n",
        "  'https://claude.com/api/mcp/auth_callback',\n]);\n\nfunction frontendForRedirectUri(redirectUri) {\n  return redirectUri === CHATGPT_CALLBACK_URI ? 'chatgpt_web' : 'claude_web';\n}\n\nfunction frontendForRegisteredClient(client) {\n  return Array.isArray(client?.redirect_uris)\n    && client.redirect_uris.length === 1\n    && client.redirect_uris[0] === CHATGPT_CALLBACK_URI\n    ? 'chatgpt_web'\n    : 'claude_web';\n}\n\nconst STATE_SCHEMA_VERSION = 1;\n"
      ],
      [
        "      client_id: params.client_id,\n      redirect_uri: params.redirect_uri,\n      code_challenge: params.code_challenge,\n      resource: this.resource,\n",
        "      client_id: params.client_id,\n      redirect_uri: params.redirect_uri,\n      frontend: frontendForRedirectUri(params.redirect_uri),\n      code_challenge: params.code_challenge,\n      resource: this.resource,\n"
      ],
      [
        "    record.used = true;\n    record.family_id = familyId;\n    const tokens = this.#issueTokens(client.client_id, familyId, record.scope ?? SCOPE);\n    this.store.save();\n    return { status: 200, body: tokens };\n",
        "    record.used = true;\n    record.family_id = familyId;\n    const tokens = this.#issueTokens(client.client_id, familyId, record.scope ?? SCOPE, record.frontend ?? frontendForRedirectUri(record.redirect_uri));\n    this.store.save();\n    return { status: 200, body: tokens };\n"
      ],
      [
        "    record.rotated = true;\n    // 刷新不扩大权限；旧版本签发的 refresh token 没有 scope 字段，视为只读。\n    const tokens = this.#issueTokens(client.client_id, record.family_id, this.#limitScope(record.scope ?? SCOPE));\n    this.store.save();\n    return { status: 200, body: tokens };\n",
        "    record.rotated = true;\n    // 刷新不扩大权限；旧版本签发的 refresh token 没有 scope 字段，视为只读。\n    const tokens = this.#issueTokens(client.client_id, record.family_id, this.#limitScope(record.scope ?? SCOPE), record.frontend ?? frontendForRegisteredClient(client));\n    this.store.save();\n    return { status: 200, body: tokens };\n"
      ],
      [
        "  }\n\n  #issueTokens(clientId, familyId, scope) {\n    scope = this.#limitScope(scope);\n    const now = this.now();\n",
        "  }\n\n  #issueTokens(clientId, familyId, scope, frontend = 'claude_web') {\n    scope = this.#limitScope(scope);\n    const now = this.now();\n"
      ],
      [
        "      resource: this.resource,\n      scope,\n      expires_at: now + this.options.accessTokenTtlMs,\n    };\n",
        "      resource: this.resource,\n      scope,\n      frontend,\n      expires_at: now + this.options.accessTokenTtlMs,\n    };\n"
      ],
      [
        "      family_id: familyId,\n      scope,\n      expires_at: now + this.options.refreshTokenTtlMs,\n      rotated: false,\n",
        "      family_id: familyId,\n      scope,\n      frontend,\n      expires_at: now + this.options.refreshTokenTtlMs,\n      rotated: false,\n"
      ],
      [
        "    // 服务关闭写回后，旧的写令牌也只按当前支持的 scope 生效。\n    const scopes = String(record.scope ?? SCOPE).split(' ').filter((s) => this.supportedScopes.includes(s));\n    return { ok: true, familyId: record.family_id, clientId: record.client_id, scopes };\n  }\n}\n",
        "    // 服务关闭写回后，旧的写令牌也只按当前支持的 scope 生效。\n    const scopes = String(record.scope ?? SCOPE).split(' ').filter((s) => this.supportedScopes.includes(s));\n    return {\n      ok: true,\n      familyId: record.family_id,\n      clientId: record.client_id,\n      frontend: record.frontend ?? frontendForRegisteredClient(this.store.state.clients[record.client_id]),\n      scopes,\n    };\n  }\n}\n"
      ]
    ],
    "writeback": [
      [
        "import { DatabaseSync } from 'node:sqlite';\n\nexport const FRONTEND_NAME = 'claude_web';\nexport const FRONTEND_DEVICE_ID = `frontend:${FRONTEND_NAME}`;\nexport const FRONTEND_PLATFORM = 'external-frontend';\n",
        "import { DatabaseSync } from 'node:sqlite';\n\nexport const FRONTENDS = Object.freeze({\n  claude_web: Object.freeze({ name: 'claude_web', deviceId: 'frontend:claude_web', displayName: 'claude.ai 网页端', credentialFile: 'core-frontend.json' }),\n  chatgpt_web: Object.freeze({ name: 'chatgpt_web', deviceId: 'frontend:chatgpt_web', displayName: 'ChatGPT 网页端', credentialFile: 'core-frontend-chatgpt_web.json' }),\n});\nexport const FRONTEND_NAME = 'claude_web';\n\nexport function frontendDefinition(frontend = FRONTEND_NAME) {\n  if (!Object.hasOwn(FRONTENDS, frontend)) throw new WritebackInputError('invalid_frontend');\n  return FRONTENDS[frontend];\n}\nexport const FRONTEND_DEVICE_ID = `frontend:${FRONTEND_NAME}`;\nexport const FRONTEND_PLATFORM = 'external-frontend';\n"
      ],
      [
        "    CREATE INDEX IF NOT EXISTS notes_active_idx ON notes(status, updated_at_ms);\n  `);\n  const columns = new Set(db.prepare('PRAGMA table_info(turns)').all().map((c) => c.name));\n  if (!columns.has('sketch')) db.exec('ALTER TABLE turns ADD COLUMN sketch TEXT');\n",
        "    CREATE INDEX IF NOT EXISTS notes_active_idx ON notes(status, updated_at_ms);\n  `);\n  db.exec(\"CREATE TABLE IF NOT EXISTS thread_frontends (thread_id TEXT PRIMARY KEY, frontend TEXT NOT NULL)\");\n  const columns = new Set(db.prepare('PRAGMA table_info(turns)').all().map((c) => c.name));\n  if (!columns.has('sketch')) db.exec('ALTER TABLE turns ADD COLUMN sketch TEXT');\n"
      ],
      [
        "}\n\nexport function loadFrontendCredential(stateDir) {\n  const path = join(stateDir, 'core-frontend.json');\n  if (!existsSync(path)) return null;\n  const parsed = JSON.parse(readFileSync(path, 'utf8'));\n  if (parsed?.device_id !== FRONTEND_DEVICE_ID || typeof parsed.device_token !== 'string') {\n    throw new Error('core-frontend.json is invalid');\n  }\n  return parsed;\n",
        "}\n\nexport function loadFrontendCredential(stateDir, frontend = FRONTEND_NAME) {\n  const definition = frontendDefinition(frontend);\n  const path = join(stateDir, definition.credentialFile);\n  if (!existsSync(path)) return null;\n  const parsed = JSON.parse(readFileSync(path, 'utf8'));\n  if (parsed?.device_id !== definition.deviceId || typeof parsed.device_token !== 'string' || !parsed.device_token) {\n    throw new Error(definition.credentialFile + ' is invalid');\n  }\n  return parsed;\n"
      ],
      [
        "}\n\nexport async function pairFrontendDevice({ coreUrl, pairingCode, stateDir, fetchImpl = fetch }) {\n  const res = await fetchImpl(`${coreUrl}/v1/core/devices/pair`, {\n    method: 'POST',\n    headers: { 'content-type': 'application/json' },\n    body: JSON.stringify({\n      device_id: FRONTEND_DEVICE_ID,\n      display_name: 'claude.ai 网页端',\n      platform: FRONTEND_PLATFORM,\n      client_version: '0.1',\n",
        "}\n\nexport async function pairFrontendDevice({ coreUrl, pairingCode, stateDir, frontend = FRONTEND_NAME, fetchImpl = fetch }) {\n  const definition = frontendDefinition(frontend);\n  const res = await fetchImpl(`${coreUrl}/v1/core/devices/pair`, {\n    method: 'POST',\n    headers: { 'content-type': 'application/json' },\n    body: JSON.stringify({\n      device_id: definition.deviceId,\n      display_name: definition.displayName,\n      platform: FRONTEND_PLATFORM,\n      client_version: '0.1',\n"
      ],
      [
        "    throw new Error(`pairing failed: ${body?.error?.code ?? res.status}`);\n  }\n  saveJsonPrivate(join(stateDir, 'core-frontend.json'), {\n    device_id: FRONTEND_DEVICE_ID,\n    device_token: body.device_token,\n    core_node_id: body.core_node_id ?? null,\n    paired_at: new Date().toISOString(),\n  });\n  return { device_id: FRONTEND_DEVICE_ID, core_node_id: body.core_node_id ?? null };\n}\n\nexport function createCoreFrontendClient({ coreUrl, deviceToken, fetchImpl = fetch, timeoutMs = 10_000 }) {\n  return {\n    async submit(messages) {\n",
        "    throw new Error(`pairing failed: ${body?.error?.code ?? res.status}`);\n  }\n  saveJsonPrivate(join(stateDir, definition.credentialFile), {\n    device_id: definition.deviceId,\n    device_token: body.device_token,\n    core_node_id: body.core_node_id ?? null,\n    paired_at: new Date().toISOString(),\n  });\n  return { device_id: definition.deviceId, core_node_id: body.core_node_id ?? null };\n}\n\nexport function createCoreFrontendClient({ coreUrl, deviceToken, frontend = FRONTEND_NAME, fetchImpl = fetch, timeoutMs = 10_000 }) {\n  const definition = frontendDefinition(frontend);\n  return {\n    async submit(messages) {\n"
      ],
      [
        "            authorization: `Bearer ${deviceToken}`,\n          },\n          body: JSON.stringify({ device_id: FRONTEND_DEVICE_ID, messages }),\n          signal: AbortSignal.timeout(timeoutMs),\n        });\n",
        "            authorization: `Bearer ${deviceToken}`,\n          },\n          body: JSON.stringify({ device_id: definition.deviceId, messages }),\n          signal: AbortSignal.timeout(timeoutMs),\n        });\n"
      ],
      [
        "  ledger,\n  coreClient,\n  now = () => Date.now(),\n  rateLimiter = new RateLimiter(DEFAULT_RATE_LIMITS, now),\n}) {\n  const db = ledger;\n\n  function validateTurns(args) {\n",
        "  ledger,\n  coreClient,\n  frontend = FRONTEND_NAME,\n  now = () => Date.now(),\n  rateLimiter = new RateLimiter(DEFAULT_RATE_LIMITS, now),\n}) {\n  const db = ledger;\n  const definition = frontendDefinition(frontend);\n\n  function validateTurns(args) {\n"
      ],
      [
        "    const t = now();\n    return transaction(db, () => {\n      const thread = db.prepare('SELECT thread_id FROM threads WHERE thread_id = ?').get(threadId);\n      if (thread) db.prepare('UPDATE threads SET last_seen_ms = ? WHERE thread_id = ?').run(t, threadId);\n      else db.prepare('INSERT INTO threads(thread_id, created_at_ms, last_seen_ms) VALUES (?, ?, ?)').run(threadId, t, t);\n      const existingRows = db.prepare(`\n        SELECT role, turn_key, sketch, created_at_ms FROM turns WHERE thread_id = ? ORDER BY seq DESC LIMIT ?\n",
        "    const t = now();\n    return transaction(db, () => {\n      const thread = db.prepare(\"SELECT thread_id, COALESCE(thread_frontends.frontend, 'claude_web') AS frontend FROM threads LEFT JOIN thread_frontends USING (thread_id) WHERE thread_id = ?\").get(threadId);\n      if (thread && thread.frontend !== frontend) throw new WritebackInputError('thread_frontend_mismatch');\n      if (thread) db.prepare('UPDATE threads SET last_seen_ms = ? WHERE thread_id = ?').run(t, threadId);\n      else {\n        db.prepare('INSERT INTO threads(thread_id, created_at_ms, last_seen_ms) VALUES (?, ?, ?)').run(threadId, t, t);\n        db.prepare('INSERT INTO thread_frontends(thread_id, frontend) VALUES (?, ?)').run(threadId, frontend);\n      }\n      const existingRows = db.prepare(`\n        SELECT role, turn_key, sketch, created_at_ms FROM turns WHERE thread_id = ? ORDER BY seq DESC LIMIT ?\n"
      ],
      [
        "      if (!thread || existing.length === 0) {\n        // 新线程（Claude 丢了 thread_id 或新对话）：用最近 24 小时的全局轮次识别重传。\n        for (const row of db.prepare('SELECT turn_key FROM turns WHERE created_at_ms >= ?').all(t - LIMITS.globalDedupWindowMs)) {\n          known.add(row.turn_key);\n        }\n",
        "      if (!thread || existing.length === 0) {\n        // 新线程（Claude 丢了 thread_id 或新对话）：用最近 24 小时的全局轮次识别重传。\n        for (const row of db.prepare(\"SELECT turn_key FROM turns LEFT JOIN thread_frontends USING (thread_id) WHERE COALESCE(frontend, 'claude_web') = ? AND turns.created_at_ms >= ?\").all(frontend, t - LIMITS.globalDedupWindowMs)) {\n          known.add(row.turn_key);\n        }\n"
      ],
      [
        "          created = threadLast + Math.max(1, Math.floor((current - threadLast) * (index + 1) / (backfillCount + 1)));\n        } else created = current - (backfillCount - index);\n        insert.run(threadId, seq, turn.role, keys[start + index], `${FRONTEND_NAME}:${threadId}:${seq}`,\n          nextOriginSequence(db, t), characterId, created, turn.content, sketches[start + index], isCurrent ? 0 : 1);\n      });\n",
        "          created = threadLast + Math.max(1, Math.floor((current - threadLast) * (index + 1) / (backfillCount + 1)));\n        } else created = current - (backfillCount - index);\n        insert.run(threadId, seq, turn.role, keys[start + index], `${frontend}:${threadId}:${seq}`,\n          nextOriginSequence(db, t), characterId, created, turn.content, sketches[start + index], isCurrent ? 0 : 1);\n      });\n"
      ],
      [
        "    return {\n      sync_id: row.sync_id,\n      origin_device_id: FRONTEND_DEVICE_ID,\n      origin_sequence: Number(row.origin_sequence),\n      character_id: row.character_id,\n",
        "    return {\n      sync_id: row.sync_id,\n      origin_device_id: definition.deviceId,\n      origin_sequence: Number(row.origin_sequence),\n      character_id: row.character_id,\n"
      ],
      [
        "  async function flush() {\n    const rows = db.prepare(`\n      SELECT * FROM turns WHERE status = 'pending' ORDER BY origin_sequence LIMIT ?\n    `).all(LIMITS.maxPendingFlush);\n    let rejected = 0;\n    for (let i = 0; i < rows.length; i += LIMITS.coreBatch) {\n",
        "  async function flush() {\n    const rows = db.prepare(`\n      SELECT turns.* FROM turns LEFT JOIN thread_frontends USING (thread_id) WHERE status = 'pending' AND COALESCE(frontend, 'claude_web') = ? ORDER BY origin_sequence LIMIT ?\n    `).all(frontend, LIMITS.maxPendingFlush);\n    let rejected = 0;\n    for (let i = 0; i < rows.length; i += LIMITS.coreBatch) {\n"
      ],
      [
        "\n  return {\n    async chatTurn(args, { characterId }) {\n      const threadId = args.thread_id === undefined || args.thread_id === null || args.thread_id === ''\n        ? newId('t') : args.thread_id;\n",
        "\n  return {\n    frontend,\n    async chatTurn(args, { characterId }) {\n      const identityFields = ['frontend', 'source', 'device_id', 'origin_device_id', 'sync_id'];\n      if (Object.keys(args).some(key => identityFields.includes(key))) throw new WritebackInputError('invalid_chat_turn_arguments');\n      if (!coreClient) throw new WritebackInputError('frontend_not_paired:' + frontend);\n      const threadId = args.thread_id === undefined || args.thread_id === null || args.thread_id === ''\n        ? newId('t') : args.thread_id;\n"
      ],
      [
        "      const plan = planTurns(threadId, turns, characterId, phase);\n      const result = await flush();\n      const pending = Number(db.prepare(\"SELECT COUNT(*) AS n FROM turns WHERE status = 'pending'\").get().n);\n      return {\n        thread_id: threadId,\n",
        "      const plan = planTurns(threadId, turns, characterId, phase);\n      const result = await flush();\n      const pending = Number(db.prepare(\"SELECT COUNT(*) AS n FROM turns LEFT JOIN thread_frontends USING (thread_id) WHERE status = 'pending' AND COALESCE(frontend, 'claude_web') = ?\").get(frontend).n);\n      return {\n        thread_id: threadId,\n"
      ],
      [
        "\n    remember(args) {\n      const action = args.action ?? 'add';\n      if (!['add', 'update', 'delete', 'list'].includes(action)) {\n",
        "\n    remember(args) {\n      if (frontend !== FRONTEND_NAME) throw new WritebackInputError('frontend_forbidden:' + frontend);\n      const action = args.action ?? 'add';\n      if (!['add', 'update', 'delete', 'list'].includes(action)) {\n"
      ]
    ],
    "server": [
      [
        "  createCoreFrontendClient,\n  createWriteback,\n  issuePhoneToken,\n  loadFrontendCredential,\n",
        "  createCoreFrontendClient,\n  createWriteback,\n  frontendDefinition,\n  issuePhoneToken,\n  loadFrontendCredential,\n"
      ],
      [
        "  diagnostic = () => {},\n  writeback = null,\n}) {\n  if (!publicUrl) throw new Error('publicUrl is required');\n  if (typeof getReadModel !== 'function') throw new Error('getReadModel is required');\n  const writeEnabled = Boolean(writeback);\n  const oauth = new OAuthServer({ stateDir, publicUrl, now, options: oauthOptions, writeEnabled, chatgptEnabled });\n  const handlers = createToolHandlers({ getReadModel, identityLoader, now, timeZone, writeback });\n  const tools = listTools({ writeEnabled });\n  const origins = new Set([...allowedOrigins, oauth.issuer, ...(chatgptEnabled ? [CHATGPT_ORIGIN] : [])]);\n  const sessions = new Map();\n",
        "  diagnostic = () => {},\n  writeback = null,\n  chatgptWriteback = null,\n}) {\n  if (!publicUrl) throw new Error('publicUrl is required');\n  if (typeof getReadModel !== 'function') throw new Error('getReadModel is required');\n  const writeEnabled = Boolean(writeback || chatgptWriteback);\n  const oauth = new OAuthServer({ stateDir, publicUrl, now, options: oauthOptions, writeEnabled, chatgptEnabled });\n  const handlers = createToolHandlers({ getReadModel, identityLoader, now, timeZone, writeback });\n  const tools = listTools({ writeEnabled: Boolean(writeback) });\n  // These handlers are selected only from the verified OAuth token, never MCP arguments.\n  const chatgptHandlers = createToolHandlers({ getReadModel, identityLoader, now, timeZone,\n    writeback: chatgptWriteback,\n    frontend: 'chatgpt_web' });\n  if (writeEnabled && !chatgptWriteback) {\n    chatgptHandlers.i_chat_turn = async () => { throw new WritebackInputError('frontend_not_paired:chatgpt_web'); };\n  }\n  const chatgptTools = listTools({ writeEnabled, frontend: 'chatgpt_web' });\n  const origins = new Set([...allowedOrigins, oauth.issuer, ...(chatgptEnabled ? [CHATGPT_ORIGIN] : [])]);\n  const sessions = new Map();\n"
      ],
      [
        "      let dataSourceFailed = false;\n      const response = await handleRpcMessage(message, {\n        handlers,\n        tools,\n        scopes: auth.scopes,\n        session,\n",
        "      let dataSourceFailed = false;\n      const response = await handleRpcMessage(message, {\n        handlers: auth.frontend === 'chatgpt_web' ? chatgptHandlers : handlers,\n        tools: auth.frontend === 'chatgpt_web' ? chatgptTools : tools,\n        unavailableTools: auth.frontend === 'chatgpt_web' && !chatgptWriteback\n          ? { i_chat_turn: 'frontend_not_paired:chatgpt_web' } : {},\n        scopes: auth.scopes,\n        session,\n"
      ],
      [
        "  const coreUrl = String(args['core-url'] ?? process.env.I_CORE_URL ?? DEFAULTS.coreUrl).replace(/\\/+$/, '');\n  if (command === 'pair-core') {\n    // i_core 需临时以 I_CORE_PAIRING_CODE 启动（打开配对窗口）；这里输入同一个一次性配对码。\n    const code = (await readSecret('i_core 一次性配对码：')).trim();\n    if (!code) throw new Error('配对码为空');\n    const paired = await pairFrontendDevice({ coreUrl, pairingCode: code, stateDir });\n    process.stderr.write(`已配对 ${paired.device_id}；令牌保存在 ${stateDir}/core-frontend.json（勿提交）。\\n`);\n    return;\n  }\n",
        "  const coreUrl = String(args['core-url'] ?? process.env.I_CORE_URL ?? DEFAULTS.coreUrl).replace(/\\/+$/, '');\n  if (command === 'pair-core') {\n    const definition = frontendDefinition(args.frontend);\n    // i_core 需临时以 I_CORE_PAIRING_CODE 启动（打开配对窗口）；这里输入同一个一次性配对码。\n    const code = (await readSecret('i_core 一次性配对码：')).trim();\n    if (!code) throw new Error('配对码为空');\n    const paired = await pairFrontendDevice({ coreUrl, pairingCode: code, stateDir, frontend: definition.name });\n    process.stderr.write(`已配对 ${paired.device_id}；令牌保存在 ${stateDir}/${definition.credentialFile}（勿提交）。\\n`);\n    return;\n  }\n"
      ],
      [
        "    process.stderr.write('写回未启用（未配对 i_core 或 I_REMOTE_MCP_WRITEBACK=0），只开放只读工具。\\n');\n  }\n  const { server, oauth } = createApp({\n    stateDir,\n",
        "    process.stderr.write('写回未启用（未配对 i_core 或 I_REMOTE_MCP_WRITEBACK=0），只开放只读工具。\\n');\n  }\n  let chatgptWriteback = null;\n  if (chatgptEnabled && process.env.I_REMOTE_MCP_WRITEBACK !== '0') {\n    const credential = loadFrontendCredential(stateDir, 'chatgpt_web');\n    if (credential) chatgptWriteback = createWriteback({\n      ledger: openLedger(resolve(stateDir, 'writeback.sqlite')),\n      frontend: 'chatgpt_web',\n      coreClient: createCoreFrontendClient({ coreUrl, deviceToken: credential.device_token, frontend: 'chatgpt_web' }),\n    });\n  }\n  const { server, oauth } = createApp({\n    stateDir,\n"
      ],
      [
        "    diagnostic,\n    writeback,\n  });\n  let phoneServer = null;\n",
        "    diagnostic,\n    writeback,\n    chatgptWriteback,\n  });\n  let phoneServer = null;\n"
      ],
      [
        "    process.stderr.write(`i remote MCP 监听 http://${host}:${port}/mcp ，对外地址 ${oauth.resource}\\n`);\n  });\n  const shutdown = () => { server.close(); phoneServer?.close(); getReadModel.close(); writeback?.close(); };\n  process.on('SIGINT', shutdown);\n  process.on('SIGTERM', shutdown);\n",
        "    process.stderr.write(`i remote MCP 监听 http://${host}:${port}/mcp ，对外地址 ${oauth.resource}\\n`);\n  });\n  const shutdown = () => { server.close(); phoneServer?.close(); getReadModel.close(); writeback?.close(); chatgptWriteback?.close(); };\n  process.on('SIGINT', shutdown);\n  process.on('SIGTERM', shutdown);\n"
      ]
    ],
    "mcp": [
      [
        "]);\n\nexport function listTools({ writeEnabled = false } = {}) {\n  return writeEnabled ? [...TOOLS, ...WRITE_TOOLS] : TOOLS;\n}\n\n",
        "]);\n\nexport function listTools({ writeEnabled = false, frontend = 'claude_web' } = {}) {\n  const writes = WRITE_TOOLS.filter(tool => frontend === 'claude_web' || tool.name === 'i_chat_turn')\n    .map(tool => tool.name === 'i_chat_turn'\n      ? { ...tool, description: tool.description.replace('claude_web', frontend) }\n      : tool);\n  return writeEnabled ? [...TOOLS, ...writes] : TOOLS;\n}\n\n"
      ],
      [
        "// ---------- 工具实现 ----------\n\nexport function createToolHandlers({ getReadModel, identityLoader = loadIdentity, now = () => Date.now(), timeZone, writeback = null }) {\n  const handlers = {\n    async i_context(args) {\n",
        "// ---------- 工具实现 ----------\n\nexport function createToolHandlers({ getReadModel, identityLoader = loadIdentity, now = () => Date.now(), timeZone, writeback = null, frontend = 'claude_web' }) {\n  const notes = frontend === 'claude_web' ? writeback : null;\n  const handlers = {\n    async i_context(args) {\n"
      ],
      [
        "        memory_snapshot_at: isoOrNull(summary?.memorySnapshotAtMs),\n        recent_messages: messages.slice(-limit).map(projectMessage),\n        ...(writeback ? { remembered_notes: writeback.activeNotes(10) } : {}),\n      };\n    },\n",
        "        memory_snapshot_at: isoOrNull(summary?.memorySnapshotAtMs),\n        recent_messages: messages.slice(-limit).map(projectMessage),\n        ...(notes ? { remembered_notes: notes.activeNotes(10) } : {}),\n      };\n    },\n"
      ],
      [
        "        memory: { count: memory.length, items: memory },\n        messages: { count: messages.length, items: messages },\n        ...(writeback ? { notes: (() => { const n = writeback.searchNotes(query, limit); return { count: n.length, items: n }; })() } : {}),\n      };\n    },\n",
        "        memory: { count: memory.length, items: memory },\n        messages: { count: messages.length, items: messages },\n        ...(notes ? { notes: (() => { const n = notes.searchNotes(query, limit); return { count: n.length, items: n }; })() } : {}),\n      };\n    },\n"
      ],
      [
        "\n  handlers.i_chat_turn = async (args) => {\n    const phase = args.phase ?? 'start';\n    if (phase !== 'start' && phase !== 'end') throw new ToolInputError('phase 只能是 start 或 end');\n",
        "\n  handlers.i_chat_turn = async (args) => {\n    if (Object.keys(args).some(key => ['frontend', 'source', 'device_id', 'origin_device_id', 'sync_id'].includes(key))) {\n      throw new ToolInputError('invalid_chat_turn_arguments');\n    }\n    const phase = args.phase ?? 'start';\n    if (phase !== 'start' && phase !== 'end') throw new ToolInputError('phase 只能是 start 或 end');\n"
      ],
      [
        "      now: currentTime(now(), timeZone),\n      recent_messages: recent.map(projectMessage),\n      remembered_notes: writeback.activeNotes(10),\n    };\n  };\n",
        "      now: currentTime(now(), timeZone),\n      recent_messages: recent.map(projectMessage),\n      ...(notes ? { remembered_notes: notes.activeNotes(10) } : {}),\n    };\n  };\n"
      ],
      [
        "// 处理一条 JSON-RPC 消息；通知/响应返回 null。\nexport async function handleRpcMessage(message, {\n  handlers, session, logError = () => {}, tools = TOOLS, scopes = [READ_SCOPE],\n}) {\n  if (!message || typeof message !== 'object' || message.jsonrpc !== '2.0') {\n",
        "// 处理一条 JSON-RPC 消息；通知/响应返回 null。\nexport async function handleRpcMessage(message, {\n  handlers, session, logError = () => {}, tools = TOOLS, scopes = [READ_SCOPE], unavailableTools = {},\n}) {\n  if (!message || typeof message !== 'object' || message.jsonrpc !== '2.0') {\n"
      ],
      [
        "          version: SERVER_VERSION,\n        },\n        instructions: tools.length > TOOLS.length ? SERVER_INSTRUCTIONS_WRITE : SERVER_INSTRUCTIONS,\n      });\n    }\n",
        "          version: SERVER_VERSION,\n        },\n        instructions: tools.some(tool => tool.name === 'i_remember') ? SERVER_INSTRUCTIONS_WRITE\n          : tools.some(tool => tool.name === 'i_chat_turn') ? SERVER_INSTRUCTIONS_WRITE.replace('用户明确说“帮我记一下”时用 i_remember。', '')\n          : SERVER_INSTRUCTIONS,\n      });\n    }\n"
      ],
      [
        "      const tool = tools.find((t) => t.name === name);\n      const handler = tool && Object.hasOwn(handlers, name) ? handlers[name] : null;\n      if (!handler) return rpcError(id, -32602, `Unknown tool: ${String(name).slice(0, 64)}`);\n      if (typeof args !== 'object' || args === null || Array.isArray(args)) return rpcError(id, -32602, 'arguments must be an object');\n      if (tool.requiredScope && !scopes.includes(tool.requiredScope)) {\n",
        "      const tool = tools.find((t) => t.name === name);\n      const handler = tool && Object.hasOwn(handlers, name) ? handlers[name] : null;\n      if (!handler) return Object.hasOwn(unavailableTools, name)\n        ? rpcResult(id, toolError(unavailableTools[name]))\n        : rpcError(id, -32602, `Unknown tool: ${String(name).slice(0, 64)}`);\n      if (typeof args !== 'object' || args === null || Array.isArray(args)) return rpcError(id, -32602, 'arguments must be an object');\n      if (tool.requiredScope && !scopes.includes(tool.requiredScope)) {\n"
      ]
    ]
  }
};
// Literal D1 registry patches, independently checked on mainline and legacy bytes.
const REGISTRY_PATCHES = {
  "mainline": {
    "oauth": [
      [
        "  'https://claude.com/api/mcp/auth_callback',\n]);\n\nfunction frontendForRedirectUri(redirectUri) {\n  return redirectUri === CHATGPT_CALLBACK_URI ? 'chatgpt_web' : 'claude_web';\n}\n\nfunction frontendForRegisteredClient(client) {\n  return Array.isArray(client?.redirect_uris)\n    && client.redirect_uris.length === 1\n    && client.redirect_uris[0] === CHATGPT_CALLBACK_URI\n    ? 'chatgpt_web'\n    : 'claude_web';\n}\n\nconst STATE_SCHEMA_VERSION = 1;\n",
        "  'https://claude.com/api/mcp/auth_callback',\n]);\n\nexport const FRONTEND_CALLBACKS = Object.freeze({\n  claude_web: CLAUDE_AI_CALLBACKS,\n  chatgpt_web: Object.freeze([CHATGPT_CALLBACK_URI]),\n});\n\nexport function frontendForRedirectUri(redirectUri) {\n  return Object.keys(FRONTEND_CALLBACKS)\n    .find((frontend) => FRONTEND_CALLBACKS[frontend].includes(redirectUri)) ?? null;\n}\n\nfunction isEnabledFrontend(frontend, chatgptEnabled) {\n  return Object.hasOwn(FRONTEND_CALLBACKS, frontend)\n    && (frontend !== 'chatgpt_web' || chatgptEnabled === true);\n}\n\nfunction frontendForRegisteredClient(client, chatgptEnabled) {\n  const uris = client?.redirect_uris;\n  if (!Array.isArray(uris) || uris.length === 0) return null;\n  const frontend = frontendForRedirectUri(uris[0]);\n  return isEnabledFrontend(frontend, chatgptEnabled)\n    && uris.every((uri) => frontendForRedirectUri(uri) === frontend) ? frontend : null;\n}\n\nfunction frontendForRecord(record, client, chatgptEnabled) {\n  // Only an absent field is legacy; null, empty and unknown values fail closed.\n  const frontend = Object.hasOwn(record, 'frontend')\n    ? record.frontend : frontendForRegisteredClient(client, chatgptEnabled);\n  return isEnabledFrontend(frontend, chatgptEnabled) ? frontend : null;\n}\n\nconst STATE_SCHEMA_VERSION = 1;\n"
      ],
      [
        "}\n\n// 单用户服务：默认只接受 claude.ai 的回调，防止他人注册自己的回调后诱导用户在授权页输入口令。\n// ChatGPT 使用独立开关和稳定精确回调；其他客户端仍可显式追加精确 HTTPS 地址。\nexport function extraRedirectUris(env = process.env) {\n  return String(env.I_REMOTE_MCP_EXTRA_REDIRECT_URIS ?? '')\n    .split(',').map((value) => value.trim()).filter(Boolean);\n}\n\nexport function chatgptEnabledFromEnv(env = process.env) {\n  const value = env.I_REMOTE_MCP_CHATGPT_ENABLED;\n",
        "}\n\n// 单用户服务：默认只接受 claude.ai 的回调，防止他人注册自己的回调后诱导用户在授权页输入口令。\n// ChatGPT 使用独立开关；只接受注册表中的精确回调。\n\nexport function chatgptEnabledFromEnv(env = process.env) {\n  const value = env.I_REMOTE_MCP_CHATGPT_ENABLED;\n"
      ],
      [
        "  throw new Error('invalid_chatgpt_mode');\n}\n\nexport function isAllowedRedirectUri(value, extra = extraRedirectUris(), chatgptEnabled = chatgptEnabledFromEnv()) {\n  if (typeof value !== 'string' || value.length > 2048) return false;\n  if (CLAUDE_AI_CALLBACKS.includes(value)) return true;\n  if (chatgptEnabled === true && value === CHATGPT_CALLBACK_URI) return true;\n  if (!extra.includes(value)) return false;\n  let url;\n  try { url = new URL(value); } catch { return false; }\n  return url.protocol === 'https:' && !url.hash && !url.username && !url.password;\n}\n\nfunction normalizeResource(value) {\n",
        "  throw new Error('invalid_chatgpt_mode');\n}\n\nexport function isAllowedRedirectUri(value, chatgptEnabled = chatgptEnabledFromEnv()) {\n  if (typeof value !== 'string' || value.length > 2048) return false;\n  return isEnabledFrontend(frontendForRedirectUri(value), chatgptEnabled);\n}\n\nfunction normalizeResource(value) {\n"
      ],
      [
        "    if (!Array.isArray(redirectUris) || redirectUris.length === 0 || redirectUris.length > MAX_REDIRECT_URIS) {\n      return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be a non-empty array');\n    }\n    if (!redirectUris.every((uri) => isAllowedRedirectUri(uri, extraRedirectUris(), this.chatgptEnabled))) {\n      return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be an allowed https callback');\n    }\n    const grantTypes = body.grant_types ?? ['authorization_code', 'refresh_token'];\n",
        "    if (!Array.isArray(redirectUris) || redirectUris.length === 0 || redirectUris.length > MAX_REDIRECT_URIS) {\n      return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be a non-empty array');\n    }\n    if (!frontendForRegisteredClient({ redirect_uris: redirectUris }, this.chatgptEnabled)) {\n      return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be an allowed https callback');\n    }\n    const grantTypes = body.grant_types ?? ['authorization_code', 'refresh_token'];\n"
      ],
      [
        "    const client = clientId ? this.store.state.clients[clientId] : undefined;\n    if (!client) return { ok: false, status: 400, error: '未知的 client_id' };\n    const redirectUri = get('redirect_uri') ?? (client.redirect_uris.length === 1 ? client.redirect_uris[0] : undefined);\n    if (!redirectUri || !client.redirect_uris.includes(redirectUri) || !isAllowedRedirectUri(redirectUri, extraRedirectUris(), this.chatgptEnabled)) {\n      return { ok: false, status: 400, error: 'redirect_uri 与注册时不一致' };\n    }\n    const state = get('state');\n",
        "    const client = clientId ? this.store.state.clients[clientId] : undefined;\n    if (!client) return { ok: false, status: 400, error: '未知的 client_id' };\n    const redirectUri = get('redirect_uri') ?? (client.redirect_uris.length === 1 ? client.redirect_uris[0] : undefined);\n    if (!redirectUri || !client.redirect_uris.includes(redirectUri) || !isAllowedRedirectUri(redirectUri, this.chatgptEnabled)) {\n      return { ok: false, status: 400, error: 'redirect_uri 与注册时不一致' };\n    }\n    const state = get('state');\n"
      ],
      [
        "    if (form.redirect_uri !== record.redirect_uri) {\n      return oauthError(400, 'invalid_grant', 'redirect_uri mismatch');\n    }\n    if (form.resource !== undefined && normalizeResource(form.resource) !== this.resource) {\n      return oauthError(400, 'invalid_target', 'unknown resource');\n    }\n",
        "    if (form.redirect_uri !== record.redirect_uri) {\n      return oauthError(400, 'invalid_grant', 'redirect_uri mismatch');\n    }\n    const frontend = frontendForRedirectUri(record.redirect_uri);\n    if (!isAllowedRedirectUri(record.redirect_uri, this.chatgptEnabled)\n      || !client.redirect_uris.includes(record.redirect_uri)\n      || frontendForRecord(record, client, this.chatgptEnabled) !== frontend) {\n      return oauthError(400, 'invalid_grant', 'invalid frontend');\n    }\n    if (form.resource !== undefined && normalizeResource(form.resource) !== this.resource) {\n      return oauthError(400, 'invalid_target', 'unknown resource');\n    }\n"
      ],
      [
        "    const familyId = randomUUID();\n    record.used = true;\n    record.family_id = familyId;\n    const tokens = this.#issueTokens(client.client_id, familyId, record.scope ?? SCOPE, record.frontend ?? frontendForRedirectUri(record.redirect_uri));\n    this.store.save();\n    return { status: 200, body: tokens };\n  }\n",
        "    const familyId = randomUUID();\n    record.used = true;\n    record.family_id = familyId;\n    const tokens = this.#issueTokens(client.client_id, familyId, record.scope ?? SCOPE, frontend);\n    this.store.save();\n    return { status: 200, body: tokens };\n  }\n"
      ],
      [
        "      this.store.save();\n      return oauthError(400, 'invalid_grant', 'refresh_token expired');\n    }\n    record.rotated = true;\n    // 刷新不扩大权限；旧版本签发的 refresh token 没有 scope 字段，视为只读。\n    const tokens = this.#issueTokens(client.client_id, record.family_id, this.#limitScope(record.scope ?? SCOPE), record.frontend ?? frontendForRegisteredClient(client));\n    this.store.save();\n    return { status: 200, body: tokens };\n  }\n",
        "      this.store.save();\n      return oauthError(400, 'invalid_grant', 'refresh_token expired');\n    }\n    const frontend = frontendForRecord(record, client, this.chatgptEnabled);\n    if (!frontend) return oauthError(400, 'invalid_grant', 'invalid frontend');\n    record.rotated = true;\n    // 刷新不扩大权限；旧版本签发的 refresh token 没有 scope 字段，视为只读。\n    const tokens = this.#issueTokens(client.client_id, record.family_id, this.#limitScope(record.scope ?? SCOPE), frontend);\n    this.store.save();\n    return { status: 200, body: tokens };\n  }\n"
      ],
      [
        "    return String(scope).split(' ').filter((s) => this.supportedScopes.includes(s)).join(' ') || SCOPE;\n  }\n\n  #issueTokens(clientId, familyId, scope, frontend = 'claude_web') {\n    scope = this.#limitScope(scope);\n    const now = this.now();\n    const accessToken = newToken('iat');\n",
        "    return String(scope).split(' ').filter((s) => this.supportedScopes.includes(s)).join(' ') || SCOPE;\n  }\n\n  #issueTokens(clientId, familyId, scope, frontend) {\n    scope = this.#limitScope(scope);\n    const now = this.now();\n    const accessToken = newToken('iat');\n"
      ],
      [
        "    if (!record) return { ok: false, error: 'invalid_token' };\n    if (this.now() >= record.expires_at) return { ok: false, error: 'invalid_token' };\n    if (record.resource !== this.resource) return { ok: false, error: 'invalid_token' };\n    // 服务关闭写回后，旧的写令牌也只按当前支持的 scope 生效。\n    const scopes = String(record.scope ?? SCOPE).split(' ').filter((s) => this.supportedScopes.includes(s));\n    return {\n      ok: true,\n      familyId: record.family_id,\n      clientId: record.client_id,\n      frontend: record.frontend ?? frontendForRegisteredClient(this.store.state.clients[record.client_id]),\n      scopes,\n    };\n  }\n",
        "    if (!record) return { ok: false, error: 'invalid_token' };\n    if (this.now() >= record.expires_at) return { ok: false, error: 'invalid_token' };\n    if (record.resource !== this.resource) return { ok: false, error: 'invalid_token' };\n    const frontend = frontendForRecord(record, this.store.state.clients[record.client_id], this.chatgptEnabled);\n    if (!frontend) return { ok: false, error: 'invalid_token' };\n    // 服务关闭写回后，旧的写令牌也只按当前支持的 scope 生效。\n    const scopes = String(record.scope ?? SCOPE).split(' ').filter((s) => this.supportedScopes.includes(s));\n    return {\n      ok: true,\n      familyId: record.family_id,\n      clientId: record.client_id,\n      frontend,\n      scopes,\n    };\n  }\n"
      ]
    ],
    "server": [
      [
        "      return sendJson(res, 401, { error: auth.error ?? 'unauthorized', error_description: 'Bearer token required' });\n    }\n\n    const versionHeader = req.headers['mcp-protocol-version'];\n    if (versionHeader && !SUPPORTED_PROTOCOL_VERSIONS.includes(versionHeader)) {\n      return sendJson(res, 400, rpcErr(null, -32600, `Unsupported MCP-Protocol-Version: ${String(versionHeader).slice(0, 32)}`));\n",
        "      return sendJson(res, 401, { error: auth.error ?? 'unauthorized', error_description: 'Bearer token required' });\n    }\n\n    let frontendHandlers;\n    let frontendTools;\n    if (auth.frontend === 'claude_web') {\n      frontendHandlers = handlers;\n      frontendTools = tools;\n    } else if (auth.frontend === 'chatgpt_web') {\n      frontendHandlers = chatgptHandlers;\n      frontendTools = chatgptTools;\n    } else {\n      res.setHeader('WWW-Authenticate', oauth.wwwAuthenticate('invalid_token'));\n      return sendJson(res, 401, { error: 'invalid_token' });\n    }\n\n    const versionHeader = req.headers['mcp-protocol-version'];\n    if (versionHeader && !SUPPORTED_PROTOCOL_VERSIONS.includes(versionHeader)) {\n      return sendJson(res, 400, rpcErr(null, -32600, `Unsupported MCP-Protocol-Version: ${String(versionHeader).slice(0, 32)}`));\n"
      ],
      [
        "    for (const message of messages) {\n      let dataSourceFailed = false;\n      const response = await handleRpcMessage(message, {\n        handlers: auth.frontend === 'chatgpt_web' ? chatgptHandlers : handlers,\n        tools: auth.frontend === 'chatgpt_web' ? chatgptTools : tools,\n        unavailableTools: auth.frontend === 'chatgpt_web' && !chatgptWriteback\n          ? { i_chat_turn: 'frontend_not_paired:chatgpt_web' } : {},\n        scopes: auth.scopes,\n",
        "    for (const message of messages) {\n      let dataSourceFailed = false;\n      const response = await handleRpcMessage(message, {\n        handlers: frontendHandlers,\n        tools: frontendTools,\n        unavailableTools: auth.frontend === 'chatgpt_web' && !chatgptWriteback\n          ? { i_chat_turn: 'frontend_not_paired:chatgpt_web' } : {},\n        scopes: auth.scopes,\n"
      ]
    ],
    "mcp": [],
    "writeback": []
  },
  "legacy": {
    "oauth": [
      [
        "  'https://claude.com/api/mcp/auth_callback',\n]);\n\nfunction frontendForRedirectUri(redirectUri) {\n  return redirectUri === CHATGPT_CALLBACK_URI ? 'chatgpt_web' : 'claude_web';\n}\n\nfunction frontendForRegisteredClient(client) {\n  return Array.isArray(client?.redirect_uris)\n    && client.redirect_uris.length === 1\n    && client.redirect_uris[0] === CHATGPT_CALLBACK_URI\n    ? 'chatgpt_web'\n    : 'claude_web';\n}\n\nconst STATE_SCHEMA_VERSION = 1;\n",
        "  'https://claude.com/api/mcp/auth_callback',\n]);\n\nexport const FRONTEND_CALLBACKS = Object.freeze({\n  claude_web: CLAUDE_AI_CALLBACKS,\n  chatgpt_web: Object.freeze([CHATGPT_CALLBACK_URI]),\n});\n\nexport function frontendForRedirectUri(redirectUri) {\n  return Object.keys(FRONTEND_CALLBACKS)\n    .find((frontend) => FRONTEND_CALLBACKS[frontend].includes(redirectUri)) ?? null;\n}\n\nfunction isEnabledFrontend(frontend, chatgptEnabled) {\n  return Object.hasOwn(FRONTEND_CALLBACKS, frontend)\n    && (frontend !== 'chatgpt_web' || chatgptEnabled === true);\n}\n\nfunction frontendForRegisteredClient(client, chatgptEnabled) {\n  const uris = client?.redirect_uris;\n  if (!Array.isArray(uris) || uris.length === 0) return null;\n  const frontend = frontendForRedirectUri(uris[0]);\n  return isEnabledFrontend(frontend, chatgptEnabled)\n    && uris.every((uri) => frontendForRedirectUri(uri) === frontend) ? frontend : null;\n}\n\nfunction frontendForRecord(record, client, chatgptEnabled) {\n  // Only an absent field is legacy; null, empty and unknown values fail closed.\n  const frontend = Object.hasOwn(record, 'frontend')\n    ? record.frontend : frontendForRegisteredClient(client, chatgptEnabled);\n  return isEnabledFrontend(frontend, chatgptEnabled) ? frontend : null;\n}\n\nconst STATE_SCHEMA_VERSION = 1;\n"
      ],
      [
        "}\n\n// 单用户服务：默认只接受 claude.ai 的回调，防止他人注册自己的回调后诱导用户在授权页输入口令。\n// ChatGPT 使用独立开关和稳定精确回调；其他客户端仍可显式追加精确 HTTPS 地址。\nexport function extraRedirectUris(env = process.env) {\n  return String(env.I_REMOTE_MCP_EXTRA_REDIRECT_URIS ?? '')\n    .split(',').map((value) => value.trim()).filter(Boolean);\n}\n\nexport function chatgptEnabledFromEnv(env = process.env) {\n  const value = env.I_REMOTE_MCP_CHATGPT_ENABLED;\n",
        "}\n\n// 单用户服务：默认只接受 claude.ai 的回调，防止他人注册自己的回调后诱导用户在授权页输入口令。\n// ChatGPT 使用独立开关；只接受注册表中的精确回调。\n\nexport function chatgptEnabledFromEnv(env = process.env) {\n  const value = env.I_REMOTE_MCP_CHATGPT_ENABLED;\n"
      ],
      [
        "  throw new Error('invalid_chatgpt_mode');\n}\n\nexport function isAllowedRedirectUri(value, extra = extraRedirectUris(), chatgptEnabled = chatgptEnabledFromEnv()) {\n  if (typeof value !== 'string' || value.length > 2048) return false;\n  if (CLAUDE_AI_CALLBACKS.includes(value)) return true;\n  if (chatgptEnabled === true && value === CHATGPT_CALLBACK_URI) return true;\n  if (!extra.includes(value)) return false;\n  let url;\n  try { url = new URL(value); } catch { return false; }\n  return url.protocol === 'https:' && !url.hash && !url.username && !url.password;\n}\n\nfunction normalizeResource(value) {\n",
        "  throw new Error('invalid_chatgpt_mode');\n}\n\nexport function isAllowedRedirectUri(value, chatgptEnabled = chatgptEnabledFromEnv()) {\n  if (typeof value !== 'string' || value.length > 2048) return false;\n  return isEnabledFrontend(frontendForRedirectUri(value), chatgptEnabled);\n}\n\nfunction normalizeResource(value) {\n"
      ],
      [
        "    if (!Array.isArray(redirectUris) || redirectUris.length === 0 || redirectUris.length > MAX_REDIRECT_URIS) {\n      return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be a non-empty array');\n    }\n    if (!redirectUris.every((uri) => isAllowedRedirectUri(uri, extraRedirectUris(), this.chatgptEnabled))) {\n      return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be an allowed https callback');\n    }\n    const grantTypes = body.grant_types ?? ['authorization_code', 'refresh_token'];\n",
        "    if (!Array.isArray(redirectUris) || redirectUris.length === 0 || redirectUris.length > MAX_REDIRECT_URIS) {\n      return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be a non-empty array');\n    }\n    if (!frontendForRegisteredClient({ redirect_uris: redirectUris }, this.chatgptEnabled)) {\n      return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be an allowed https callback');\n    }\n    const grantTypes = body.grant_types ?? ['authorization_code', 'refresh_token'];\n"
      ],
      [
        "    const client = clientId ? this.store.state.clients[clientId] : undefined;\n    if (!client) return { ok: false, status: 400, error: '未知的 client_id' };\n    const redirectUri = get('redirect_uri') ?? (client.redirect_uris.length === 1 ? client.redirect_uris[0] : undefined);\n    if (!redirectUri || !client.redirect_uris.includes(redirectUri) || !isAllowedRedirectUri(redirectUri, extraRedirectUris(), this.chatgptEnabled)) {\n      return { ok: false, status: 400, error: 'redirect_uri 与注册时不一致' };\n    }\n    const state = get('state');\n",
        "    const client = clientId ? this.store.state.clients[clientId] : undefined;\n    if (!client) return { ok: false, status: 400, error: '未知的 client_id' };\n    const redirectUri = get('redirect_uri') ?? (client.redirect_uris.length === 1 ? client.redirect_uris[0] : undefined);\n    if (!redirectUri || !client.redirect_uris.includes(redirectUri) || !isAllowedRedirectUri(redirectUri, this.chatgptEnabled)) {\n      return { ok: false, status: 400, error: 'redirect_uri 与注册时不一致' };\n    }\n    const state = get('state');\n"
      ],
      [
        "    if (form.redirect_uri !== record.redirect_uri) {\n      return oauthError(400, 'invalid_grant', 'redirect_uri mismatch');\n    }\n    if (form.resource !== undefined && normalizeResource(form.resource) !== this.resource) {\n      return oauthError(400, 'invalid_target', 'unknown resource');\n    }\n",
        "    if (form.redirect_uri !== record.redirect_uri) {\n      return oauthError(400, 'invalid_grant', 'redirect_uri mismatch');\n    }\n    const frontend = frontendForRedirectUri(record.redirect_uri);\n    if (!isAllowedRedirectUri(record.redirect_uri, this.chatgptEnabled)\n      || !client.redirect_uris.includes(record.redirect_uri)\n      || frontendForRecord(record, client, this.chatgptEnabled) !== frontend) {\n      return oauthError(400, 'invalid_grant', 'invalid frontend');\n    }\n    if (form.resource !== undefined && normalizeResource(form.resource) !== this.resource) {\n      return oauthError(400, 'invalid_target', 'unknown resource');\n    }\n"
      ],
      [
        "    const familyId = randomUUID();\n    record.used = true;\n    record.family_id = familyId;\n    const tokens = this.#issueTokens(client.client_id, familyId, record.scope ?? SCOPE, record.frontend ?? frontendForRedirectUri(record.redirect_uri));\n    this.store.save();\n    return { status: 200, body: tokens };\n  }\n",
        "    const familyId = randomUUID();\n    record.used = true;\n    record.family_id = familyId;\n    const tokens = this.#issueTokens(client.client_id, familyId, record.scope ?? SCOPE, frontend);\n    this.store.save();\n    return { status: 200, body: tokens };\n  }\n"
      ],
      [
        "      this.store.save();\n      return oauthError(400, 'invalid_grant', 'refresh_token expired');\n    }\n    record.rotated = true;\n    // 刷新不扩大权限；旧版本签发的 refresh token 没有 scope 字段，视为只读。\n    const tokens = this.#issueTokens(client.client_id, record.family_id, this.#limitScope(record.scope ?? SCOPE), record.frontend ?? frontendForRegisteredClient(client));\n    this.store.save();\n    return { status: 200, body: tokens };\n  }\n",
        "      this.store.save();\n      return oauthError(400, 'invalid_grant', 'refresh_token expired');\n    }\n    const frontend = frontendForRecord(record, client, this.chatgptEnabled);\n    if (!frontend) return oauthError(400, 'invalid_grant', 'invalid frontend');\n    record.rotated = true;\n    // 刷新不扩大权限；旧版本签发的 refresh token 没有 scope 字段，视为只读。\n    const tokens = this.#issueTokens(client.client_id, record.family_id, this.#limitScope(record.scope ?? SCOPE), frontend);\n    this.store.save();\n    return { status: 200, body: tokens };\n  }\n"
      ],
      [
        "    return String(scope).split(' ').filter((s) => this.supportedScopes.includes(s)).join(' ') || SCOPE;\n  }\n\n  #issueTokens(clientId, familyId, scope, frontend = 'claude_web') {\n    scope = this.#limitScope(scope);\n    const now = this.now();\n    const accessToken = newToken('iat');\n",
        "    return String(scope).split(' ').filter((s) => this.supportedScopes.includes(s)).join(' ') || SCOPE;\n  }\n\n  #issueTokens(clientId, familyId, scope, frontend) {\n    scope = this.#limitScope(scope);\n    const now = this.now();\n    const accessToken = newToken('iat');\n"
      ],
      [
        "    if (!record) return { ok: false, error: 'invalid_token' };\n    if (this.now() >= record.expires_at) return { ok: false, error: 'invalid_token' };\n    if (record.resource !== this.resource) return { ok: false, error: 'invalid_token' };\n    // 服务关闭写回后，旧的写令牌也只按当前支持的 scope 生效。\n    const scopes = String(record.scope ?? SCOPE).split(' ').filter((s) => this.supportedScopes.includes(s));\n    return {\n      ok: true,\n      familyId: record.family_id,\n      clientId: record.client_id,\n      frontend: record.frontend ?? frontendForRegisteredClient(this.store.state.clients[record.client_id]),\n      scopes,\n    };\n  }\n",
        "    if (!record) return { ok: false, error: 'invalid_token' };\n    if (this.now() >= record.expires_at) return { ok: false, error: 'invalid_token' };\n    if (record.resource !== this.resource) return { ok: false, error: 'invalid_token' };\n    const frontend = frontendForRecord(record, this.store.state.clients[record.client_id], this.chatgptEnabled);\n    if (!frontend) return { ok: false, error: 'invalid_token' };\n    // 服务关闭写回后，旧的写令牌也只按当前支持的 scope 生效。\n    const scopes = String(record.scope ?? SCOPE).split(' ').filter((s) => this.supportedScopes.includes(s));\n    return {\n      ok: true,\n      familyId: record.family_id,\n      clientId: record.client_id,\n      frontend,\n      scopes,\n    };\n  }\n"
      ]
    ],
    "server": [
      [
        "      return sendJson(res, 401, { error: auth.error ?? 'unauthorized', error_description: 'Bearer token required' });\n    }\n\n    const versionHeader = req.headers['mcp-protocol-version'];\n    if (versionHeader && !SUPPORTED_PROTOCOL_VERSIONS.includes(versionHeader)) {\n      return sendJson(res, 400, rpcErr(null, -32600, `Unsupported MCP-Protocol-Version: ${String(versionHeader).slice(0, 32)}`));\n",
        "      return sendJson(res, 401, { error: auth.error ?? 'unauthorized', error_description: 'Bearer token required' });\n    }\n\n    let frontendHandlers;\n    let frontendTools;\n    if (auth.frontend === 'claude_web') {\n      frontendHandlers = handlers;\n      frontendTools = tools;\n    } else if (auth.frontend === 'chatgpt_web') {\n      frontendHandlers = chatgptHandlers;\n      frontendTools = chatgptTools;\n    } else {\n      res.setHeader('WWW-Authenticate', oauth.wwwAuthenticate('invalid_token'));\n      return sendJson(res, 401, { error: 'invalid_token' });\n    }\n\n    const versionHeader = req.headers['mcp-protocol-version'];\n    if (versionHeader && !SUPPORTED_PROTOCOL_VERSIONS.includes(versionHeader)) {\n      return sendJson(res, 400, rpcErr(null, -32600, `Unsupported MCP-Protocol-Version: ${String(versionHeader).slice(0, 32)}`));\n"
      ],
      [
        "    for (const message of messages) {\n      let dataSourceFailed = false;\n      const response = await handleRpcMessage(message, {\n        handlers: auth.frontend === 'chatgpt_web' ? chatgptHandlers : handlers,\n        tools: auth.frontend === 'chatgpt_web' ? chatgptTools : tools,\n        unavailableTools: auth.frontend === 'chatgpt_web' && !chatgptWriteback\n          ? { i_chat_turn: 'frontend_not_paired:chatgpt_web' } : {},\n        scopes: auth.scopes,\n",
        "    for (const message of messages) {\n      let dataSourceFailed = false;\n      const response = await handleRpcMessage(message, {\n        handlers: frontendHandlers,\n        tools: frontendTools,\n        unavailableTools: auth.frontend === 'chatgpt_web' && !chatgptWriteback\n          ? { i_chat_turn: 'frontend_not_paired:chatgpt_web' } : {},\n        scopes: auth.scopes,\n"
      ]
    ],
    "mcp": [],
    "writeback": []
  }
};

// Gemini adds no runtime files; preserve each input file's original line endings.
const GEMINI_PATCHES = {
  "mainline": {
    "server": [
      [
        "import { fileURLToPath, pathToFileURL } from 'node:url';\nimport { OAuthServer, chatgptEnabledFromEnv, revokeAll, setPassphrase } from './oauth.mjs';\nimport { readFileSync } from 'node:fs';\n",
        "import { fileURLToPath, pathToFileURL } from 'node:url';\nimport { OAuthServer, chatgptEnabledFromEnv, geminiEnabledFromEnv, revokeAll, setPassphrase } from './oauth.mjs';\nimport { readFileSync } from 'node:fs';\n"
      ],
      [
        "  chatgptEnabled = chatgptEnabledFromEnv(),\n  log = () => {},\n",
        "  chatgptEnabled = chatgptEnabledFromEnv(),\n  geminiEnabled = geminiEnabledFromEnv(),\n  log = () => {},\n"
      ],
      [
        "  chatgptWriteback = null,\n  coreRemember = null,\n",
        "  chatgptWriteback = null,\n  geminiWriteback = null,\n  coreRemember = null,\n"
      ],
      [
        "  if (typeof getReadModel !== 'function') throw new Error('getReadModel is required');\n  const writeEnabled = Boolean(writeback || chatgptWriteback || coreRemember);\n  const oauth = new OAuthServer({ stateDir, publicUrl, now, options: oauthOptions, writeEnabled, chatgptEnabled });\n  if(domainTools&&(domainTools.tools.some(tool=>!WEB_DOMAIN_TOOLS.includes(tool.name))||Object.keys(domainTools.handlers).some(name=>!domainTools.tools.some(tool=>tool.name===name))))throw new Error('planner_tools_forbidden_on_web');\n",
        "  if (typeof getReadModel !== 'function') throw new Error('getReadModel is required');\n  const writeEnabled = Boolean(writeback || chatgptWriteback || geminiWriteback || coreRemember);\n  const oauth = new OAuthServer({ stateDir, publicUrl, now, options: oauthOptions, writeEnabled, chatgptEnabled, geminiEnabled });\n  if(domainTools&&(domainTools.tools.some(tool=>!WEB_DOMAIN_TOOLS.includes(tool.name))||Object.keys(domainTools.handlers).some(name=>!domainTools.tools.some(tool=>tool.name===name))))throw new Error('planner_tools_forbidden_on_web');\n"
      ],
      [
        "  const chatgptTools = [...listTools({ writeEnabled, frontend: 'chatgpt_web' }),\n    ...chatgptDomainTools.map(tool => ({ ...tool, requiredScope: 'i.read' }))];\n",
        "  const chatgptTools = [...listTools({ writeEnabled, frontend: 'chatgpt_web' }),\n    ...chatgptDomainTools.map(tool => ({ ...tool, requiredScope: 'i.read' }))];\n  const geminiHandlers = { ...createToolHandlers({ getReadModel, identityLoader, now, timeZone,\n    writeback: geminiWriteback,\n    frontend: 'gemini_web' }),\n    ...Object.fromEntries(chatgptDomainTools.map(tool => [tool.name, domainTools.handlers[tool.name]])) };\n  if (writeEnabled && !geminiWriteback) {\n    geminiHandlers.i_chat_turn = async () => { throw new WritebackInputError('frontend_not_paired:gemini_web'); };\n  }\n  const geminiTools = [...listTools({ writeEnabled, frontend: 'gemini_web' }),\n    ...chatgptDomainTools.map(tool => ({ ...tool, requiredScope: 'i.read' }))];\n"
      ],
      [
        "      frontendTools = chatgptTools;\n    } else {\n",
        "      frontendTools = chatgptTools;\n    } else if (auth.frontend === 'gemini_web') {\n      frontendHandlers = geminiHandlers;\n      frontendTools = geminiTools;\n    } else {\n"
      ],
      [
        "        unavailableTools: auth.frontend === 'chatgpt_web' && !chatgptWriteback\n          ? { i_chat_turn: 'frontend_not_paired:chatgpt_web' } : {},\n        scopes: auth.scopes,\n",
        "        unavailableTools: auth.frontend === 'chatgpt_web' && !chatgptWriteback\n          ? { i_chat_turn: 'frontend_not_paired:chatgpt_web' }\n          : auth.frontend === 'gemini_web' && !geminiWriteback\n            ? { i_chat_turn: 'frontend_not_paired:gemini_web' } : {},\n        scopes: auth.scopes,\n"
      ],
      [
        "\n  async function handleAuthorize(req, res, url) {\n    if (req.method === 'GET') {\n      const query = Object.fromEntries(url.searchParams);\n      const v = oauth.validateAuthorizeRequest(query);\n",
        "\n  async function handleAuthorize(req, res, url, diagnostics) {\n    if (req.method === 'GET') {\n      const query = Object.fromEntries(url.searchParams);\n      diagnostics.callbacks(query.redirect_uri);\n      const v = oauth.validateAuthorizeRequest(query);\n"
      ],
      [
        "      }\n      const r = oauth.submitPassphrase(form);\n",
        "      }\n      diagnostics.callbacks(form.redirect_uri);\n      const r = oauth.submitPassphrase(form);\n"
      ],
      [
        "      const r = oauth.register(body);\n      return sendJson(res, r.status, r.body, { 'Cache-Control': 'no-store' });\n    }\n    if (path === '/authorize') return handleAuthorize(req, res, url);\n    if (path === '/token') {\n",
        "      const r = oauth.register(body);\n      diagnostics.registration(body?.redirect_uris, r.status === 201 ? r.body.redirect_uris : []);\n      return sendJson(res, r.status, r.body, { 'Cache-Control': 'no-store' });\n    }\n    if (path === '/authorize') return handleAuthorize(req, res, url, diagnostics);\n    if (path === '/token') {\n"
      ],
      [
        "      }\n      const r = oauth.token(form);\n      return sendJson(res, r.status, r.body, { 'Cache-Control': 'no-store', Pragma: 'no-cache' });\n",
        "      }\n      const r = oauth.token(form, req.headers.authorization);\n      return sendJson(res, r.status, r.body, { 'Cache-Control': 'no-store', Pragma: 'no-cache' });\n"
      ],
      [
        "  const chatgptEnabled = chatgptEnabledFromEnv();\n  if (!publicUrl.startsWith('https://')) {\n",
        "  const chatgptEnabled = chatgptEnabledFromEnv();\n  const geminiEnabled = geminiEnabledFromEnv();\n  if (!publicUrl.startsWith('https://')) {\n"
      ],
      [
        "  }\n  const { server, oauth } = createApp({\n",
        "  }\n  let geminiWriteback = null;\n  if (geminiEnabled && process.env.I_REMOTE_MCP_WRITEBACK !== '0') {\n    const credential = loadFrontendCredential(stateDir, 'gemini_web');\n    if (credential) geminiWriteback = createWriteback({\n      ledger: openLedger(resolve(stateDir, 'writeback.sqlite')),\n      frontend: 'gemini_web',\n      coreClient: createCoreFrontendClient({ coreUrl, deviceToken: credential.device_token, frontend: 'gemini_web' }),\n    });\n  }\n  const { server, oauth } = createApp({\n"
      ],
      [
        "    chatgptEnabled,\n    getReadModel,\n",
        "    chatgptEnabled,\n    geminiEnabled,\n    getReadModel,\n"
      ],
      [
        "    chatgptWriteback,\n    ...loadWebDomainOptions(args['domain-config']),\n",
        "    chatgptWriteback,\n    geminiWriteback,\n    ...loadWebDomainOptions(args['domain-config']),\n"
      ],
      [
        "  });\n  const shutdown = () => { server.close(); phoneServer?.close(); getReadModel.close(); writeback?.close(); chatgptWriteback?.close(); };\n  process.on('SIGINT', shutdown);\n",
        "  });\n  const shutdown = () => { server.close(); phoneServer?.close(); getReadModel.close(); writeback?.close(); chatgptWriteback?.close(); geminiWriteback?.close(); };\n  process.on('SIGINT', shutdown);\n"
      ]
    ],
    "oauth": [
      [
        "\nexport function frontendForRedirectUri(redirectUri) {\n  return Object.keys(FRONTEND_CALLBACKS)\n    .find((frontend) => FRONTEND_CALLBACKS[frontend].includes(redirectUri)) ?? null;\n}\n\nfunction isEnabledFrontend(frontend, chatgptEnabled) {\n  return Object.hasOwn(FRONTEND_CALLBACKS, frontend)\n    && (frontend !== 'chatgpt_web' || chatgptEnabled === true);\n}\n\nfunction frontendForRegisteredClient(client, chatgptEnabled) {\n  const uris = client?.redirect_uris;\n",
        "\n// Exact relay hosts only; canonical spelling also excludes explicit default ports,\n// empty query/fragment delimiters and URL-parser normalization aliases.\nexport const FRONTEND_CALLBACK_PATTERNS = Object.freeze({\n  gemini_web: (value) => {\n    if (typeof value !== 'string' || value.length > 2048) return false;\n    try {\n      const url = new URL(value);\n      return url.protocol === 'https:'\n        && ['oauth-redirect.googleusercontent.com', 'oauth-redirect-sandbox.googleusercontent.com'].includes(url.hostname)\n        && !url.port && !url.username && !url.password && !url.search && !url.hash\n        && /^\\/r\\/user_bound_custom-mcp-[A-Za-z0-9-]{1,200}$/.test(url.pathname)\n        && value === `${url.origin}${url.pathname}`;\n    } catch { return false; }\n  },\n});\n\nexport function frontendForRedirectUri(redirectUri) {\n  return Object.keys(FRONTEND_CALLBACKS)\n    .find((frontend) => FRONTEND_CALLBACKS[frontend].includes(redirectUri))\n    ?? Object.keys(FRONTEND_CALLBACK_PATTERNS)\n      .find((frontend) => FRONTEND_CALLBACK_PATTERNS[frontend](redirectUri)) ?? null;\n}\n\nfunction isEnabledFrontend(frontend, chatgptEnabled, geminiEnabled) {\n  return (Object.hasOwn(FRONTEND_CALLBACKS, frontend) || Object.hasOwn(FRONTEND_CALLBACK_PATTERNS, frontend))\n    && (frontend !== 'chatgpt_web' || chatgptEnabled === true)\n    && (frontend !== 'gemini_web' || geminiEnabled === true);\n}\n\nfunction frontendForRegisteredClient(client, chatgptEnabled, geminiEnabled) {\n  const uris = client?.redirect_uris;\n"
      ],
      [
        "  const frontend = frontendForRedirectUri(uris[0]);\n  return isEnabledFrontend(frontend, chatgptEnabled)\n    && uris.every((uri) => frontendForRedirectUri(uri) === frontend) ? frontend : null;\n",
        "  const frontend = frontendForRedirectUri(uris[0]);\n  return isEnabledFrontend(frontend, chatgptEnabled, geminiEnabled)\n    && uris.every((uri) => frontendForRedirectUri(uri) === frontend) ? frontend : null;\n"
      ],
      [
        "\nfunction frontendForRecord(record, client, chatgptEnabled) {\n  // Only an absent field is legacy; null, empty and unknown values fail closed.\n  const frontend = Object.hasOwn(record, 'frontend')\n    ? record.frontend : frontendForRegisteredClient(client, chatgptEnabled);\n  return isEnabledFrontend(frontend, chatgptEnabled) ? frontend : null;\n}\n",
        "\nfunction frontendForRecord(record, client, chatgptEnabled, geminiEnabled) {\n  // Only an absent field is legacy; null, empty and unknown values fail closed.\n  const frontend = Object.hasOwn(record, 'frontend')\n    ? record.frontend : frontendForRegisteredClient(client, chatgptEnabled, geminiEnabled);\n  return isEnabledFrontend(frontend, chatgptEnabled, geminiEnabled) ? frontend : null;\n}\n"
      ],
      [
        "\nexport function isAllowedRedirectUri(value, chatgptEnabled = chatgptEnabledFromEnv()) {\n  if (typeof value !== 'string' || value.length > 2048) return false;\n  return isEnabledFrontend(frontendForRedirectUri(value), chatgptEnabled);\n}\n",
        "\nexport function geminiEnabledFromEnv(env = process.env) {\n  const value = env.I_REMOTE_MCP_GEMINI_ENABLED;\n  if (value === undefined || value === '1') return true;\n  if (value === '0') return false;\n  throw new Error('invalid_gemini_mode');\n}\n\nexport function isAllowedRedirectUri(value, chatgptEnabled = chatgptEnabledFromEnv(), geminiEnabled = geminiEnabledFromEnv()) {\n  if (typeof value !== 'string' || value.length > 2048) return false;\n  return isEnabledFrontend(frontendForRedirectUri(value), chatgptEnabled, geminiEnabled);\n}\n"
      ],
      [
        "export class OAuthServer {\n  constructor({ stateDir, publicUrl, now = () => Date.now(), options = {}, writeEnabled = false, chatgptEnabled = chatgptEnabledFromEnv() }) {\n    if (typeof chatgptEnabled !== 'boolean') throw new Error('invalid_chatgpt_mode');\n    this.chatgptEnabled = chatgptEnabled;\n    this.store = new OAuthStateStore(stateDir);\n",
        "export class OAuthServer {\n  constructor({ stateDir, publicUrl, now = () => Date.now(), options = {}, writeEnabled = false, chatgptEnabled = chatgptEnabledFromEnv(), geminiEnabled = geminiEnabledFromEnv() }) {\n    if (typeof chatgptEnabled !== 'boolean') throw new Error('invalid_chatgpt_mode');\n    if (typeof geminiEnabled !== 'boolean') throw new Error('invalid_gemini_mode');\n    this.chatgptEnabled = chatgptEnabled;\n    this.geminiEnabled = geminiEnabled;\n    this.store = new OAuthStateStore(stateDir);\n"
      ],
      [
        "    }\n    const redirectUris = body.redirect_uris;\n    if (!Array.isArray(redirectUris) || redirectUris.length === 0 || redirectUris.length > MAX_REDIRECT_URIS) {\n      return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be a non-empty array');\n    }\n    if (!frontendForRegisteredClient({ redirect_uris: redirectUris }, this.chatgptEnabled)) {\n      return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be an allowed https callback');\n",
        "    }\n    let redirectUris = body.redirect_uris;\n    if (!Array.isArray(redirectUris) || redirectUris.length === 0) {\n      return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be a non-empty array');\n    }\n    const frontends = redirectUris.map(frontendForRedirectUri);\n    const exactFrontend = frontends[0];\n    if (Object.hasOwn(FRONTEND_CALLBACKS, exactFrontend) && frontends.every(frontend => frontend === exactFrontend)) {\n      if (redirectUris.length > MAX_REDIRECT_URIS || !isEnabledFrontend(exactFrontend, this.chatgptEnabled, this.geminiEnabled)) {\n        return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be an allowed https callback');\n      }\n    } else if (this.geminiEnabled && redirectUris.length <= 8 && frontends.includes('gemini_web')\n      && !frontends.some(frontend => Object.hasOwn(FRONTEND_CALLBACKS, frontend))) {\n      redirectUris = redirectUris.filter((uri, index) => frontends[index] === 'gemini_web');\n    } else {\n      return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be an allowed https callback');\n"
      ],
      [
        "    const redirectUri = get('redirect_uri') ?? (client.redirect_uris.length === 1 ? client.redirect_uris[0] : undefined);\n    if (!redirectUri || !client.redirect_uris.includes(redirectUri) || !isAllowedRedirectUri(redirectUri, this.chatgptEnabled)) {\n      return { ok: false, status: 400, error: 'redirect_uri 与注册时不一致' };\n",
        "    const redirectUri = get('redirect_uri') ?? (client.redirect_uris.length === 1 ? client.redirect_uris[0] : undefined);\n    if (!redirectUri || !client.redirect_uris.includes(redirectUri) || !isAllowedRedirectUri(redirectUri, this.chatgptEnabled, this.geminiEnabled)) {\n      return { ok: false, status: 400, error: 'redirect_uri 与注册时不一致' };\n"
      ],
      [
        "\n  token(form) {\n    const grantType = form.grant_type;\n",
        "\n  token(form, authorizationHeader) {\n    if (!form.client_id && typeof authorizationHeader === 'string') {\n      const basic = /^Basic\\s+([A-Za-z0-9+/]+={0,2})$/i.exec(authorizationHeader);\n      if (basic) {\n        const decoded = Buffer.from(basic[1], 'base64').toString('utf8');\n        const colon = decoded.indexOf(':');\n        let clientId;\n        try { clientId = colon < 0 ? null : decodeURIComponent(decoded.slice(0, colon)); } catch { /* invalid public identifier */ }\n        const client = this.store.state.clients[clientId];\n        if (frontendForRegisteredClient(client, this.chatgptEnabled, this.geminiEnabled) === 'gemini_web') {\n          form = { ...form, client_id: clientId };\n        }\n      }\n    }\n    const grantType = form.grant_type;\n"
      ],
      [
        "    const frontend = frontendForRedirectUri(record.redirect_uri);\n    if (!isAllowedRedirectUri(record.redirect_uri, this.chatgptEnabled)\n      || !client.redirect_uris.includes(record.redirect_uri)\n      || frontendForRecord(record, client, this.chatgptEnabled) !== frontend) {\n      return oauthError(400, 'invalid_grant', 'invalid frontend');\n",
        "    const frontend = frontendForRedirectUri(record.redirect_uri);\n    if (!isAllowedRedirectUri(record.redirect_uri, this.chatgptEnabled, this.geminiEnabled)\n      || !client.redirect_uris.includes(record.redirect_uri)\n      || frontendForRecord(record, client, this.chatgptEnabled, this.geminiEnabled) !== frontend) {\n      return oauthError(400, 'invalid_grant', 'invalid frontend');\n"
      ],
      [
        "    }\n    const frontend = frontendForRecord(record, client, this.chatgptEnabled);\n    if (!frontend) return oauthError(400, 'invalid_grant', 'invalid frontend');\n",
        "    }\n    const frontend = frontendForRecord(record, client, this.chatgptEnabled, this.geminiEnabled);\n    if (!frontend) return oauthError(400, 'invalid_grant', 'invalid frontend');\n"
      ],
      [
        "    if (record.resource !== this.resource) return { ok: false, error: 'invalid_token' };\n    const frontend = frontendForRecord(record, this.store.state.clients[record.client_id], this.chatgptEnabled);\n    if (!frontend) return { ok: false, error: 'invalid_token' };\n",
        "    if (record.resource !== this.resource) return { ok: false, error: 'invalid_token' };\n    const frontend = frontendForRecord(record, this.store.state.clients[record.client_id], this.chatgptEnabled, this.geminiEnabled);\n    if (!frontend) return { ok: false, error: 'invalid_token' };\n"
      ]
    ],
    "writeback": [
      [
        "  chatgpt_web: Object.freeze({ name: 'chatgpt_web', deviceId: 'frontend:chatgpt_web', displayName: 'ChatGPT 网页端', credentialFile: 'core-frontend-chatgpt_web.json' }),\n});\n",
        "  chatgpt_web: Object.freeze({ name: 'chatgpt_web', deviceId: 'frontend:chatgpt_web', displayName: 'ChatGPT 网页端', credentialFile: 'core-frontend-chatgpt_web.json' }),\n  gemini_web: Object.freeze({ name: 'gemini_web', deviceId: 'frontend:gemini_web', displayName: 'Gemini 网页端', credentialFile: 'core-frontend-gemini_web.json' }),\n});\n"
      ]
    ],
    "diagnostics": [
      [
        "import { join, resolve } from 'node:path';\n\n",
        "import { join, resolve } from 'node:path';\nimport { frontendForRedirectUri } from './oauth.mjs';\n\n"
      ],
      [
        "const CALLBACKS = ['https://claude.ai/api/mcp/auth_callback', 'https://claude.com/api/mcp/auth_callback'];\n\n",
        "const CALLBACKS = ['https://claude.ai/api/mcp/auth_callback', 'https://claude.com/api/mcp/auth_callback'];\n\n// Fixed classifications only: never emit any part of an unrecognized callback.\nexport function callbackClass(value) {\n  if (value === undefined || value === null || value === '') return 'absent';\n  const frontend = frontendForRedirectUri(value);\n  if (frontend === 'claude_web') return 'claude';\n  if (frontend === 'chatgpt_web') return 'chatgpt';\n  if (frontend === 'gemini_web') return 'gemini_pattern';\n  try {\n    const url = new URL(value);\n    if (['oauth-redirect.googleusercontent.com', 'oauth-redirect-sandbox.googleusercontent.com'].includes(url.hostname)) return 'google_relay_other';\n  } catch { /* untrusted input */ }\n  return 'other';\n}\n\n"
      ],
      [
        "  return {\n    rpc(message, response, { dataSourceFailed = false } = {}) {\n",
        "  return {\n    callbacks(value) { base.callback_class = callbackClass(value); },\n    registration(values, kept) {\n      const callbacks = Array.isArray(values) ? values : [];\n      const classes = callbacks.map(callbackClass);\n      base.callback_class = ['gemini_pattern', 'claude', 'chatgpt', 'google_relay_other', 'other', 'absent']\n        .find(value => classes.includes(value)) ?? 'absent';\n      base.callback_count = callbacks.length;\n      base.gemini_kept_count = kept.filter(value => frontendForRedirectUri(value) === 'gemini_web').length;\n    },\n    rpc(message, response, { dataSourceFailed = false } = {}) {\n"
      ]
    ],
    "mcp": []
  },
  "legacy": {
    "server": [
      [
        "import { fileURLToPath, pathToFileURL } from 'node:url';\nimport { OAuthServer, chatgptEnabledFromEnv, revokeAll, setPassphrase } from './oauth.mjs';\n",
        "import { fileURLToPath, pathToFileURL } from 'node:url';\nimport { OAuthServer, chatgptEnabledFromEnv, geminiEnabledFromEnv, revokeAll, setPassphrase } from './oauth.mjs';\n"
      ],
      [
        "  chatgptEnabled = chatgptEnabledFromEnv(),\n  log = () => {},\n",
        "  chatgptEnabled = chatgptEnabledFromEnv(),\n  geminiEnabled = geminiEnabledFromEnv(),\n  log = () => {},\n"
      ],
      [
        "  chatgptWriteback = null,\n",
        "  chatgptWriteback = null,\n  geminiWriteback = null,\n"
      ],
      [
        "  if (typeof getReadModel !== 'function') throw new Error('getReadModel is required');\n  const writeEnabled = Boolean(writeback || chatgptWriteback);\n  const oauth = new OAuthServer({ stateDir, publicUrl, now, options: oauthOptions, writeEnabled, chatgptEnabled });\n",
        "  if (typeof getReadModel !== 'function') throw new Error('getReadModel is required');\n  const writeEnabled = Boolean(writeback || chatgptWriteback || geminiWriteback);\n  const oauth = new OAuthServer({ stateDir, publicUrl, now, options: oauthOptions, writeEnabled, chatgptEnabled, geminiEnabled });\n"
      ],
      [
        "  const chatgptTools = listTools({ writeEnabled, frontend: 'chatgpt_web' });\n",
        "  const chatgptTools = listTools({ writeEnabled, frontend: 'chatgpt_web' });\n  const geminiHandlers = createToolHandlers({ getReadModel, identityLoader, now, timeZone,\n    writeback: geminiWriteback, frontend: 'gemini_web' });\n  if (writeEnabled && !geminiWriteback) {\n    geminiHandlers.i_chat_turn = async () => { throw new WritebackInputError('frontend_not_paired:gemini_web'); };\n  }\n  const geminiTools = listTools({ writeEnabled, frontend: 'gemini_web' });\n"
      ],
      [
        "      frontendTools = chatgptTools;\n    } else {\n",
        "      frontendTools = chatgptTools;\n    } else if (auth.frontend === 'gemini_web') {\n      frontendHandlers = geminiHandlers;\n      frontendTools = geminiTools;\n    } else {\n"
      ],
      [
        "        unavailableTools: auth.frontend === 'chatgpt_web' && !chatgptWriteback\n          ? { i_chat_turn: 'frontend_not_paired:chatgpt_web' } : {},\n        scopes: auth.scopes,\n",
        "        unavailableTools: auth.frontend === 'chatgpt_web' && !chatgptWriteback\n          ? { i_chat_turn: 'frontend_not_paired:chatgpt_web' }\n          : auth.frontend === 'gemini_web' && !geminiWriteback\n            ? { i_chat_turn: 'frontend_not_paired:gemini_web' } : {},\n        scopes: auth.scopes,\n"
      ],
      [
        "\n  async function handleAuthorize(req, res, url) {\n    if (req.method === 'GET') {\n      const query = Object.fromEntries(url.searchParams);\n      const v = oauth.validateAuthorizeRequest(query);\n",
        "\n  async function handleAuthorize(req, res, url, diagnostics) {\n    if (req.method === 'GET') {\n      const query = Object.fromEntries(url.searchParams);\n      diagnostics.callbacks(query.redirect_uri);\n      const v = oauth.validateAuthorizeRequest(query);\n"
      ],
      [
        "      }\n      const r = oauth.submitPassphrase(form);\n",
        "      }\n      diagnostics.callbacks(form.redirect_uri);\n      const r = oauth.submitPassphrase(form);\n"
      ],
      [
        "      const r = oauth.register(body);\n      return sendJson(res, r.status, r.body, { 'Cache-Control': 'no-store' });\n    }\n    if (path === '/authorize') return handleAuthorize(req, res, url);\n    if (path === '/token') {\n",
        "      const r = oauth.register(body);\n      diagnostics.registration(body?.redirect_uris, r.status === 201 ? r.body.redirect_uris : []);\n      return sendJson(res, r.status, r.body, { 'Cache-Control': 'no-store' });\n    }\n    if (path === '/authorize') return handleAuthorize(req, res, url, diagnostics);\n    if (path === '/token') {\n"
      ],
      [
        "      }\n      const r = oauth.token(form);\n      return sendJson(res, r.status, r.body, { 'Cache-Control': 'no-store', Pragma: 'no-cache' });\n",
        "      }\n      const r = oauth.token(form, req.headers.authorization);\n      return sendJson(res, r.status, r.body, { 'Cache-Control': 'no-store', Pragma: 'no-cache' });\n"
      ],
      [
        "  const chatgptEnabled = chatgptEnabledFromEnv();\n  if (!publicUrl.startsWith('https://')) {\n",
        "  const chatgptEnabled = chatgptEnabledFromEnv();\n  const geminiEnabled = geminiEnabledFromEnv();\n  if (!publicUrl.startsWith('https://')) {\n"
      ],
      [
        "  }\n  const { server, oauth } = createApp({\n",
        "  }\n  let geminiWriteback = null;\n  if (geminiEnabled && process.env.I_REMOTE_MCP_WRITEBACK !== '0') {\n    const credential = loadFrontendCredential(stateDir, 'gemini_web');\n    if (credential) geminiWriteback = createWriteback({\n      ledger: openLedger(resolve(stateDir, 'writeback.sqlite')),\n      frontend: 'gemini_web',\n      coreClient: createCoreFrontendClient({ coreUrl, deviceToken: credential.device_token, frontend: 'gemini_web' }),\n    });\n  }\n  const { server, oauth } = createApp({\n"
      ],
      [
        "    chatgptEnabled,\n    getReadModel,\n",
        "    chatgptEnabled,\n    geminiEnabled,\n    getReadModel,\n"
      ],
      [
        "    chatgptWriteback,\n",
        "    chatgptWriteback,\n    geminiWriteback,\n"
      ],
      [
        "  });\n  const shutdown = () => { server.close(); phoneServer?.close(); getReadModel.close(); writeback?.close(); chatgptWriteback?.close(); };\n  process.on('SIGINT', shutdown);\n",
        "  });\n  const shutdown = () => { server.close(); phoneServer?.close(); getReadModel.close(); writeback?.close(); chatgptWriteback?.close(); geminiWriteback?.close(); };\n  process.on('SIGINT', shutdown);\n"
      ]
    ],
    "oauth": [
      [
        "\nexport function frontendForRedirectUri(redirectUri) {\n  return Object.keys(FRONTEND_CALLBACKS)\n    .find((frontend) => FRONTEND_CALLBACKS[frontend].includes(redirectUri)) ?? null;\n}\n\nfunction isEnabledFrontend(frontend, chatgptEnabled) {\n  return Object.hasOwn(FRONTEND_CALLBACKS, frontend)\n    && (frontend !== 'chatgpt_web' || chatgptEnabled === true);\n}\n\nfunction frontendForRegisteredClient(client, chatgptEnabled) {\n  const uris = client?.redirect_uris;\n",
        "\n// Exact relay hosts only; canonical spelling also excludes explicit default ports,\n// empty query/fragment delimiters and URL-parser normalization aliases.\nexport const FRONTEND_CALLBACK_PATTERNS = Object.freeze({\n  gemini_web: (value) => {\n    if (typeof value !== 'string' || value.length > 2048) return false;\n    try {\n      const url = new URL(value);\n      return url.protocol === 'https:'\n        && ['oauth-redirect.googleusercontent.com', 'oauth-redirect-sandbox.googleusercontent.com'].includes(url.hostname)\n        && !url.port && !url.username && !url.password && !url.search && !url.hash\n        && /^\\/r\\/user_bound_custom-mcp-[A-Za-z0-9-]{1,200}$/.test(url.pathname)\n        && value === `${url.origin}${url.pathname}`;\n    } catch { return false; }\n  },\n});\n\nexport function frontendForRedirectUri(redirectUri) {\n  return Object.keys(FRONTEND_CALLBACKS)\n    .find((frontend) => FRONTEND_CALLBACKS[frontend].includes(redirectUri))\n    ?? Object.keys(FRONTEND_CALLBACK_PATTERNS)\n      .find((frontend) => FRONTEND_CALLBACK_PATTERNS[frontend](redirectUri)) ?? null;\n}\n\nfunction isEnabledFrontend(frontend, chatgptEnabled, geminiEnabled) {\n  return (Object.hasOwn(FRONTEND_CALLBACKS, frontend) || Object.hasOwn(FRONTEND_CALLBACK_PATTERNS, frontend))\n    && (frontend !== 'chatgpt_web' || chatgptEnabled === true)\n    && (frontend !== 'gemini_web' || geminiEnabled === true);\n}\n\nfunction frontendForRegisteredClient(client, chatgptEnabled, geminiEnabled) {\n  const uris = client?.redirect_uris;\n"
      ],
      [
        "  const frontend = frontendForRedirectUri(uris[0]);\n  return isEnabledFrontend(frontend, chatgptEnabled)\n    && uris.every((uri) => frontendForRedirectUri(uri) === frontend) ? frontend : null;\n",
        "  const frontend = frontendForRedirectUri(uris[0]);\n  return isEnabledFrontend(frontend, chatgptEnabled, geminiEnabled)\n    && uris.every((uri) => frontendForRedirectUri(uri) === frontend) ? frontend : null;\n"
      ],
      [
        "\nfunction frontendForRecord(record, client, chatgptEnabled) {\n  // Only an absent field is legacy; null, empty and unknown values fail closed.\n  const frontend = Object.hasOwn(record, 'frontend')\n    ? record.frontend : frontendForRegisteredClient(client, chatgptEnabled);\n  return isEnabledFrontend(frontend, chatgptEnabled) ? frontend : null;\n}\n",
        "\nfunction frontendForRecord(record, client, chatgptEnabled, geminiEnabled) {\n  // Only an absent field is legacy; null, empty and unknown values fail closed.\n  const frontend = Object.hasOwn(record, 'frontend')\n    ? record.frontend : frontendForRegisteredClient(client, chatgptEnabled, geminiEnabled);\n  return isEnabledFrontend(frontend, chatgptEnabled, geminiEnabled) ? frontend : null;\n}\n"
      ],
      [
        "\nexport function isAllowedRedirectUri(value, chatgptEnabled = chatgptEnabledFromEnv()) {\n  if (typeof value !== 'string' || value.length > 2048) return false;\n  return isEnabledFrontend(frontendForRedirectUri(value), chatgptEnabled);\n}\n",
        "\nexport function geminiEnabledFromEnv(env = process.env) {\n  const value = env.I_REMOTE_MCP_GEMINI_ENABLED;\n  if (value === undefined || value === '1') return true;\n  if (value === '0') return false;\n  throw new Error('invalid_gemini_mode');\n}\n\nexport function isAllowedRedirectUri(value, chatgptEnabled = chatgptEnabledFromEnv(), geminiEnabled = geminiEnabledFromEnv()) {\n  if (typeof value !== 'string' || value.length > 2048) return false;\n  return isEnabledFrontend(frontendForRedirectUri(value), chatgptEnabled, geminiEnabled);\n}\n"
      ],
      [
        "export class OAuthServer {\n  constructor({ stateDir, publicUrl, now = () => Date.now(), options = {}, writeEnabled = false, chatgptEnabled = chatgptEnabledFromEnv() }) {\n    if (typeof chatgptEnabled !== 'boolean') throw new Error('invalid_chatgpt_mode');\n    this.chatgptEnabled = chatgptEnabled;\n    this.store = new OAuthStateStore(stateDir);\n",
        "export class OAuthServer {\n  constructor({ stateDir, publicUrl, now = () => Date.now(), options = {}, writeEnabled = false, chatgptEnabled = chatgptEnabledFromEnv(), geminiEnabled = geminiEnabledFromEnv() }) {\n    if (typeof chatgptEnabled !== 'boolean') throw new Error('invalid_chatgpt_mode');\n    if (typeof geminiEnabled !== 'boolean') throw new Error('invalid_gemini_mode');\n    this.chatgptEnabled = chatgptEnabled;\n    this.geminiEnabled = geminiEnabled;\n    this.store = new OAuthStateStore(stateDir);\n"
      ],
      [
        "    }\n    const redirectUris = body.redirect_uris;\n    if (!Array.isArray(redirectUris) || redirectUris.length === 0 || redirectUris.length > MAX_REDIRECT_URIS) {\n      return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be a non-empty array');\n    }\n    if (!frontendForRegisteredClient({ redirect_uris: redirectUris }, this.chatgptEnabled)) {\n      return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be an allowed https callback');\n",
        "    }\n    let redirectUris = body.redirect_uris;\n    if (!Array.isArray(redirectUris) || redirectUris.length === 0) {\n      return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be a non-empty array');\n    }\n    const frontends = redirectUris.map(frontendForRedirectUri);\n    const exactFrontend = frontends[0];\n    if (Object.hasOwn(FRONTEND_CALLBACKS, exactFrontend) && frontends.every(frontend => frontend === exactFrontend)) {\n      if (redirectUris.length > MAX_REDIRECT_URIS || !isEnabledFrontend(exactFrontend, this.chatgptEnabled, this.geminiEnabled)) {\n        return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be an allowed https callback');\n      }\n    } else if (this.geminiEnabled && redirectUris.length <= 8 && frontends.includes('gemini_web')\n      && !frontends.some(frontend => Object.hasOwn(FRONTEND_CALLBACKS, frontend))) {\n      redirectUris = redirectUris.filter((uri, index) => frontends[index] === 'gemini_web');\n    } else {\n      return oauthError(400, 'invalid_redirect_uri', 'redirect_uris must be an allowed https callback');\n"
      ],
      [
        "    const redirectUri = get('redirect_uri') ?? (client.redirect_uris.length === 1 ? client.redirect_uris[0] : undefined);\n    if (!redirectUri || !client.redirect_uris.includes(redirectUri) || !isAllowedRedirectUri(redirectUri, this.chatgptEnabled)) {\n      return { ok: false, status: 400, error: 'redirect_uri 与注册时不一致' };\n",
        "    const redirectUri = get('redirect_uri') ?? (client.redirect_uris.length === 1 ? client.redirect_uris[0] : undefined);\n    if (!redirectUri || !client.redirect_uris.includes(redirectUri) || !isAllowedRedirectUri(redirectUri, this.chatgptEnabled, this.geminiEnabled)) {\n      return { ok: false, status: 400, error: 'redirect_uri 与注册时不一致' };\n"
      ],
      [
        "\n  token(form) {\n    const grantType = form.grant_type;\n",
        "\n  token(form, authorizationHeader) {\n    if (!form.client_id && typeof authorizationHeader === 'string') {\n      const basic = /^Basic\\s+([A-Za-z0-9+/]+={0,2})$/i.exec(authorizationHeader);\n      if (basic) {\n        const decoded = Buffer.from(basic[1], 'base64').toString('utf8');\n        const colon = decoded.indexOf(':');\n        let clientId;\n        try { clientId = colon < 0 ? null : decodeURIComponent(decoded.slice(0, colon)); } catch { /* invalid public identifier */ }\n        const client = this.store.state.clients[clientId];\n        if (frontendForRegisteredClient(client, this.chatgptEnabled, this.geminiEnabled) === 'gemini_web') {\n          form = { ...form, client_id: clientId };\n        }\n      }\n    }\n    const grantType = form.grant_type;\n"
      ],
      [
        "    const frontend = frontendForRedirectUri(record.redirect_uri);\n    if (!isAllowedRedirectUri(record.redirect_uri, this.chatgptEnabled)\n      || !client.redirect_uris.includes(record.redirect_uri)\n      || frontendForRecord(record, client, this.chatgptEnabled) !== frontend) {\n      return oauthError(400, 'invalid_grant', 'invalid frontend');\n",
        "    const frontend = frontendForRedirectUri(record.redirect_uri);\n    if (!isAllowedRedirectUri(record.redirect_uri, this.chatgptEnabled, this.geminiEnabled)\n      || !client.redirect_uris.includes(record.redirect_uri)\n      || frontendForRecord(record, client, this.chatgptEnabled, this.geminiEnabled) !== frontend) {\n      return oauthError(400, 'invalid_grant', 'invalid frontend');\n"
      ],
      [
        "    }\n    const frontend = frontendForRecord(record, client, this.chatgptEnabled);\n    if (!frontend) return oauthError(400, 'invalid_grant', 'invalid frontend');\n",
        "    }\n    const frontend = frontendForRecord(record, client, this.chatgptEnabled, this.geminiEnabled);\n    if (!frontend) return oauthError(400, 'invalid_grant', 'invalid frontend');\n"
      ],
      [
        "    if (record.resource !== this.resource) return { ok: false, error: 'invalid_token' };\n    const frontend = frontendForRecord(record, this.store.state.clients[record.client_id], this.chatgptEnabled);\n    if (!frontend) return { ok: false, error: 'invalid_token' };\n",
        "    if (record.resource !== this.resource) return { ok: false, error: 'invalid_token' };\n    const frontend = frontendForRecord(record, this.store.state.clients[record.client_id], this.chatgptEnabled, this.geminiEnabled);\n    if (!frontend) return { ok: false, error: 'invalid_token' };\n"
      ]
    ],
    "writeback": [
      [
        "  chatgpt_web: Object.freeze({ name: 'chatgpt_web', deviceId: 'frontend:chatgpt_web', displayName: 'ChatGPT 网页端', credentialFile: 'core-frontend-chatgpt_web.json' }),\n});\n",
        "  chatgpt_web: Object.freeze({ name: 'chatgpt_web', deviceId: 'frontend:chatgpt_web', displayName: 'ChatGPT 网页端', credentialFile: 'core-frontend-chatgpt_web.json' }),\n  gemini_web: Object.freeze({ name: 'gemini_web', deviceId: 'frontend:gemini_web', displayName: 'Gemini 网页端', credentialFile: 'core-frontend-gemini_web.json' }),\n});\n"
      ]
    ],
    "diagnostics": [
      [
        "import { join, resolve } from 'node:path';\n\n",
        "import { join, resolve } from 'node:path';\nimport { frontendForRedirectUri } from './oauth.mjs';\n\n"
      ],
      [
        "const CALLBACKS = ['https://claude.ai/api/mcp/auth_callback', 'https://claude.com/api/mcp/auth_callback'];\n\n",
        "const CALLBACKS = ['https://claude.ai/api/mcp/auth_callback', 'https://claude.com/api/mcp/auth_callback'];\n\n// Fixed classifications only: never emit any part of an unrecognized callback.\nexport function callbackClass(value) {\n  if (value === undefined || value === null || value === '') return 'absent';\n  const frontend = frontendForRedirectUri(value);\n  if (frontend === 'claude_web') return 'claude';\n  if (frontend === 'chatgpt_web') return 'chatgpt';\n  if (frontend === 'gemini_web') return 'gemini_pattern';\n  try {\n    const url = new URL(value);\n    if (['oauth-redirect.googleusercontent.com', 'oauth-redirect-sandbox.googleusercontent.com'].includes(url.hostname)) return 'google_relay_other';\n  } catch { /* untrusted input */ }\n  return 'other';\n}\n\n"
      ],
      [
        "  return {\n    rpc(message, response, { dataSourceFailed = false } = {}) {\n",
        "  return {\n    callbacks(value) { base.callback_class = callbackClass(value); },\n    registration(values, kept) {\n      const callbacks = Array.isArray(values) ? values : [];\n      const classes = callbacks.map(callbackClass);\n      base.callback_class = ['gemini_pattern', 'claude', 'chatgpt', 'google_relay_other', 'other', 'absent']\n        .find(value => classes.includes(value)) ?? 'absent';\n      base.callback_count = callbacks.length;\n      base.gemini_kept_count = kept.filter(value => frontendForRedirectUri(value) === 'gemini_web').length;\n    },\n    rpc(message, response, { dataSourceFailed = false } = {}) {\n"
      ]
    ],
    "mcp": []
  }
};

PATCHES.writeback = [];
PATCHES.diagnostics = [];
for (const patchSet of [FRONTEND_PATCHES, REGISTRY_PATCHES]) {
 patchSet.mainline.diagnostics = [];
 patchSet.legacy.diagnostics = [];
}
export const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const git = args => execFileSync('git', args, {cwd:REPO_ROOT, windowsHide:true, maxBuffer:1024*1024});

function textFormat(bytes) {
 assert.ok(Buffer.isBuffer(bytes), 'source must be a Buffer');
 const text=bytes.toString('utf8');assert.ok(Buffer.from(text).equals(bytes),'source must be exact UTF-8');
 const eol=text.includes('\r\n')?'\r\n':'\n';
 assert.ok(!text.replaceAll('\r\n','').includes('\r'),'unsupported source CR');
 if(eol==='\r\n')assert.ok(!text.replaceAll('\r\n','').includes('\n'),'mixed source line endings');
 return {text:text.replaceAll('\r\n','\n'),eol};
}
function applyPatches(bytes, name, reverse=false, patchSet=PATCHES) {
 const {text,eol}=textFormat(bytes);let result=text;
 const patches=reverse?[...patchSet[name]].reverse().map(([a,b])=>[b,a]):patchSet[name];
 for(const [before,after] of patches) {
  assert.equal(result.split(before).length,2,'compatibility patch must match exactly once: '+name);
  result=result.replace(before,after);
 }
 return Buffer.from(result.replaceAll('\n',eol));
}

export function readCandidateInputs() {
 const baselineFiles={};
 for(const item of SOURCE_INVENTORY) {
  const ref=BASELINE_COMMIT+':'+SOURCE_PREFIX+item.path;
  assert.equal(git(['rev-parse',ref]).toString().trim(),item.blob,'fixed source blob mismatch');
  baselineFiles[item.path]=git(['cat-file','blob',ref]);
 }
 const baselineMain={}, current={};
 for(const name of ['server','oauth','mcp','writeback','diagnostics']) {
  const path='tools/i_remote_mcp/'+name+'.mjs';
  assert.equal(git(['rev-parse',BASELINE_COMMIT+':'+path]).toString().trim(),MAIN_BLOBS[name]);
  baselineMain[name]=git(['cat-file','blob',BASELINE_COMMIT+':'+path]);
  current[name]=readFileSync(join(REPO_ROOT,path));
 }
 return {baselineCommit:BASELINE_COMMIT,baselineFiles,baselineMain,current,sourceCommit:git(['rev-parse','HEAD']).toString().trim()};
}

export function constructCandidateSources({baselineCommit,baselineFiles,baselineMain,current,sourceCommit}) {
 assert.equal(baselineCommit,BASELINE_COMMIT,'wrong baseline commit');
 assert.deepEqual(Object.keys(baselineFiles).sort(),SOURCE_INVENTORY.map(x=>x.path).sort(),'exact six-file closure required');
 const files={};
 for(const item of SOURCE_INVENTORY) {
  const bytes=baselineFiles[item.path];
  assert.ok(Buffer.isBuffer(bytes)&&bytes.length===item.bytes&&sha256(bytes)===item.sha256,'baseline byte mismatch: '+item.path);
  files[item.path]=Buffer.from(bytes);
 }
 for(const name of ['server','oauth','mcp','writeback','diagnostics']) {
  const base=baselineMain[name];
  const blob=createHash('sha1').update(Buffer.from('blob '+base.length+'\0')).update(base).digest('hex');
  assert.equal(blob,MAIN_BLOBS[name],'wrong mainline baseline blob');
  // Git stores LF while Windows checkouts may use CRLF. Preserve and explicitly
  // account for that representation, then require byte-exact current-source match.
  const format=textFormat(current[name]);
  const represented=Buffer.from(textFormat(base).text.replaceAll('\n',format.eol));
  const compatibleMain = applyPatches(represented,name);
  const frontendMain = applyPatches(compatibleMain,name,false,FRONTEND_PATCHES.mainline);
  const registryMain = applyPatches(frontendMain,name,false,REGISTRY_PATCHES.mainline);
  assert.ok(applyPatches(registryMain,name,false,GEMINI_PATCHES.mainline).equals(current[name]),'unexpected current '+name+' source delta');
  assert.ok(applyPatches(applyPatches(applyPatches(applyPatches(current[name],name,true,GEMINI_PATCHES.mainline),name,true,REGISTRY_PATCHES.mainline),name,true,FRONTEND_PATCHES.mainline),name,true).equals(represented),'reverse mainline patches must restore exact baseline');
  const path='i_remote_mcp/'+name+'.mjs';
  if(name==='oauth'||name==='diagnostics')assert.equal(textFormat(base).text,textFormat(files[path]).text,'shared baseline semantic mismatch: '+name);
  files[path]=applyPatches(applyPatches(applyPatches(applyPatches(files[path],name),name,false,FRONTEND_PATCHES.legacy),name,false,REGISTRY_PATCHES.legacy),name,false,GEMINI_PATCHES.legacy);
  assert.ok(applyPatches(applyPatches(applyPatches(applyPatches(files[path],name,true,GEMINI_PATCHES.legacy),name,true,REGISTRY_PATCHES.legacy),name,true,FRONTEND_PATCHES.legacy),name,true).equals(baselineFiles[path]),'reverse patch must restore exact source bytes');
 }
 for(const bytes of Object.values(files))assert.ok(!/domain_tools|personal_data_domains|coreRemember|domain-config/.test(bytes.toString()),'W3 domain source forbidden');
 const manifest={schema_version:1,status:'not_deployed',baseline_commit:BASELINE_COMMIT,source_commit:sourceCommit,
  source_prefix:SOURCE_PREFIX,chatgpt_flag:{name:'I_REMOTE_MCP_CHATGPT_ENABLED',default:'0'},
  entry:'i_remote_mcp/server.mjs',changed_files:5,unchanged_files:1,
  source_sha256:Object.fromEntries(Object.entries(current).map(([name,bytes])=>[name,sha256(bytes)])),
  files:SOURCE_INVENTORY.map(item=>({path:item.path,source_blob:item.blob,base_sha256:item.sha256,
   result_sha256:sha256(files[item.path]),bytes:files[item.path].length,changed:sha256(files[item.path])!==item.sha256}))};
 assert.equal(manifest.files.filter(x=>x.changed).length,5);
 return {files,manifest};
}

export function validateOutputDirectory(outputDirectory) {
 assert.ok(typeof outputDirectory==='string'&&outputDirectory.length>0,'output directory required');
 const raw=isAbsolute(outputDirectory)?relative(REPO_ROOT,outputDirectory):outputDirectory;
 const parts=raw.split(/[\\/]/);
 assert.ok(parts.length>=2&&parts[0]==='build','output must be a new directory under checkout/build');
 for(const part of parts)assert.ok(/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(part)&&!/[. ]$/.test(part)&&! /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(part),'output path aliases forbidden');
 const root=resolve(REPO_ROOT,...parts);
 if(isAbsolute(outputDirectory))assert.equal(outputDirectory,root,'noncanonical absolute output path');
 assert.equal(realpathSync(REPO_ROOT),REPO_ROOT,'checkout alias forbidden');
 let path=REPO_ROOT;
 for(const part of parts) {
  path=join(path,part);
  if(existsSync(path)) {assert.ok(!lstatSync(path).isSymbolicLink(),'output links forbidden');assert.equal(realpathSync(path),path,'output aliases forbidden');assert.ok(lstatSync(path).isDirectory(),'output parent must be directory');}
  else {try{lstatSync(path);assert.fail('output links forbidden');}catch(error){if(error.code!=='ENOENT')throw error;}}
 }
 assert.ok(!existsSync(root),'output already exists');
 return {outputRoot:root,root:join(root,'runtime'),manifestPath:join(root,'manifest.json')};
}

export function buildChatgptCandidate({outputDirectory}={}) {
 let output=validateOutputDirectory(outputDirectory);
 const {files,manifest}=constructCandidateSources(readCandidateInputs());
 mkdirSync(dirname(output.outputRoot),{recursive:true});
 output=validateOutputDirectory(outputDirectory);
 mkdirSync(output.outputRoot); // Exclusive directory creation; never overwrite a candidate.
 mkdirSync(output.root);
 for(const folder of ['i_remote_mcp','i_memory'])mkdirSync(join(output.root,folder));
 for(const [path,bytes] of Object.entries(files))writeFileSync(join(output.root,path),bytes,{flag:'wx'});
 writeFileSync(output.manifestPath,JSON.stringify(manifest,null,2)+'\n',{flag:'wx'});
 for(const item of manifest.files)assert.equal(sha256(readFileSync(join(output.root,item.path))),item.result_sha256);
 return {...output,entryPath:join(output.root,manifest.entry),manifest};
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 try {
  const args=process.argv.slice(2);if(args[0]==='build')args.shift();
  if(args[0]==='--out')args.shift();
  assert.ok(args.length===1,'usage: node chatgpt_candidate.mjs [build] --out build/<new-name>');
  const result=buildChatgptCandidate({outputDirectory:args[0]});
  process.stdout.write(JSON.stringify({status:'not_deployed',root:result.root,manifest:result.manifestPath})+'\n');
 } catch(error) {process.stderr.write(error.message+'\n');process.exitCode=1;}
}
