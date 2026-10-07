// Test-only helper. All state is newly synthesized; production entry bytes stay intact.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:net';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { setPassphrase } from './legacy/i_remote_mcp/oauth.mjs';

export const FIXTURE_ROOT = dirname(fileURLToPath(import.meta.url));
export const LEGACY_SOURCE_ROOT = join(FIXTURE_ROOT, 'legacy');
export const LEGACY_ENTRY_PATH = join(LEGACY_SOURCE_ROOT, 'i_remote_mcp/server.mjs');
export const LEGACY_ENTRY_SHA256 = 'adfc88126c6d7ee047fd7fed7eda6b3b536c9e1fe0baffafbedc290b6c5554d6';
export const SYNTHETIC_QUERY = 'synthetic';
const REDIRECT_URI = 'https://synthetic.invalid/mcp/callback';
const PROTOCOL = '2025-06-18';

export function verifyLegacySourceInventory() {
  const inventory = JSON.parse(readFileSync(join(FIXTURE_ROOT, 'source-inventory.json'), 'utf8'));
  assert.equal(inventory.entry_sha256, LEGACY_ENTRY_SHA256);
  assert.equal(inventory.files.length, 6);
  for (const item of inventory.files) {
    const bytes = readFileSync(inside(LEGACY_SOURCE_ROOT, join(LEGACY_SOURCE_ROOT, item.path)));
    assert.equal(bytes.length, item.bytes, `legacy byte length: ${item.path}`);
    assert.equal(createHash('sha256').update(bytes).digest('hex'), item.sha256, `legacy SHA: ${item.path}`);
  }
  assert.equal(inventory.files.find(item => item.path === inventory.entry)?.sha256, LEGACY_ENTRY_SHA256);
  return inventory;
}

function inside(root, path) {
  const actual = resolve(path);
  const rel = relative(resolve(root), actual);
  assert.ok(rel && rel !== '..' && !rel.startsWith(`..${sep}`) && !isAbsolute(rel), 'path must be inside explicit synthetic root');
  // Resolve existing ancestors to reject links/junctions escaping the explicit root.
  let ancestor = actual;
  while (!existsSync(ancestor)) ancestor = dirname(ancestor);
  const physical = realpathSync(ancestor);
  const physicalRoot = realpathSync(root);
  const physicalRel = relative(physicalRoot, physical);
  assert.ok(physicalRel !== '..' && !physicalRel.startsWith(`..${sep}`) && !isAbsolute(physicalRel), 'synthetic path escapes through a link');
  return actual;
}

/** The caller creates a fresh syntheticRoot and the synthetic Core candidate DB within it.
 * This helper never opens, creates, starts, or stops Core. It only supplies new MCP state.
 */
export function createSyntheticReaderState({ syntheticRoot, coreDbPath, primaryCharacterId = 'lin-ai', query = SYNTHETIC_QUERY, protectDirectory = () => {} }) {
  verifyLegacySourceInventory();
  assert.ok(syntheticRoot && coreDbPath, 'explicit synthetic root and Core DB required');
  const root = realpathSync(syntheticRoot);
  const core = inside(root, coreDbPath);
  assert.ok(typeof primaryCharacterId === 'string' && primaryCharacterId.trim());
  const readerRoot = mkdtempSync(join(root, 'synthetic-mcp-reader-'));
  protectDirectory(readerRoot);
  const stateDir = join(readerRoot, 'synthetic-oauth-state');
  const iHome = join(readerRoot, 'synthetic-i-home');
  const logDir = join(readerRoot, 'synthetic-logs');
  for (const path of [stateDir, iHome, logDir]) { mkdirSync(path); protectDirectory(path); }
  const memoryDbPath = join(readerRoot, 'synthetic-memory.sqlite');
  const policyPath = join(readerRoot, 'synthetic-policy.json');
  const passphrase = `synthetic-${randomBytes(24).toString('hex')}`;
  setPassphrase(stateDir, passphrase);
  writeFileSync(join(iHome, 'identity.json'), JSON.stringify({
    identity: { name: 'Synthetic i', english_name: 'i', is_ai: true },
    relationship: { user_preferred_name: 'Synthetic user', user_aliases: [] },
  }));
  writeFileSync(policyPath, JSON.stringify({
    schema_version: 1, primary_character_id: primaryCharacterId,
    messages: { default: 'shareable', shareable_character_ids: [primaryCharacterId], private_message_types: [], private_message_ids: [], private_keywords: [] },
    memory: { default: 'shareable', private_types: [], private_structured_types: [], private_card_ids: [], private_keywords: [] },
  }));
  const db = new DatabaseSync(memoryDbPath);
  try {
    db.exec(`
      CREATE TABLE memory_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE memory_cards (
        id TEXT PRIMARY KEY, memory_scope TEXT NOT NULL, type TEXT NOT NULL,
        title TEXT NOT NULL, droplet_label TEXT NOT NULL, retrieval_text TEXT NOT NULL,
        status TEXT, structured_type TEXT, fields_json TEXT,
        recorded_at INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
      );
      CREATE VIRTUAL TABLE memory_cards_fts USING fts5(card_id UNINDEXED, title, droplet_label, retrieval_text, tokenize = 'trigram');
      INSERT INTO memory_metadata VALUES ('schema_version', '1'), ('snapshot_at_ms', '1790000000000');
    `);
    db.prepare(`INSERT INTO memory_cards VALUES ('synthetic-card', 'user_truth', 'fact', ?, 'synthetic', ?, 'active', NULL, NULL, 1790000000000, 1790000000000, 1790000000000)`).run(query, `synthetic fixture ${query}`);
    db.prepare(`INSERT INTO memory_cards_fts VALUES ('synthetic-card', ?, 'synthetic', ?)`).run(query, `synthetic fixture ${query}`);
  } finally { db.close(); }
  return { syntheticRoot: root, readerRoot, stateDir, coreDbPath: core, memoryDbPath, policyPath, iHome, logDir, passphrase, query, primaryCharacterId };
}

export function legacyReaderEnvironment(state) {
  return {
    I_HOME: state.iHome,
    I_REMOTE_MCP_STATE_DIR: state.stateDir,
    I_REMOTE_MCP_LOG_DIR: state.logDir,
    I_REMOTE_MCP_WRITEBACK: '0',
    I_REMOTE_MCP_EXTRA_REDIRECT_URIS: REDIRECT_URI,
    I_CORE_DB: state.coreDbPath,
    I_MEMORY_DB: state.memoryDbPath,
    I_MEMORY_POLICY: state.policyPath,
  };
}

export function legacyReaderCliArgs({ state, port, coreUrl = 'http://127.0.0.1:1' }) {
  assert.ok(Number.isInteger(port) && port > 0 && port < 65536);
  assertLoopbackBase(coreUrl);
  for (const key of ['stateDir', 'coreDbPath', 'memoryDbPath', 'policyPath', 'iHome', 'logDir']) inside(state.syntheticRoot, state[key]);
  return [LEGACY_ENTRY_PATH, 'serve', '--host', '127.0.0.1', '--port', String(port),
    '--public-url', `http://127.0.0.1:${port}`, '--core-db', state.coreDbPath,
    '--memory-db', state.memoryDbPath, '--policy', state.policyPath,
    '--state-dir', state.stateDir, '--log-dir', state.logDir,
    '--core-url', coreUrl, '--phone-host', '127.0.0.1', '--phone-port', '0'];
}

export async function allocateSyntheticLoopbackPort() {
  const server = createServer();
  await new Promise((yes, no) => { server.once('error', no); server.listen(0, '127.0.0.1', yes); });
  const port = server.address().port;
  await new Promise((yes, no) => server.close(error => error ? no(error) : yes()));
  return port;
}

function assertLoopbackBase(base) {
  const url = new URL(base);
  assert.equal(url.protocol, 'http:');
  assert.equal(url.hostname, '127.0.0.1');
  assert.ok(url.port && !url.username && !url.password && !url.search && !url.hash);
  assert.equal(url.pathname, '/');
}

export async function syntheticHttpRequest(base, path, options = {}) {
  assertLoopbackBase(base);
  assert.ok(path.startsWith('/') && !path.startsWith('//'), 'same synthetic endpoint only');
  const response = await fetch(`${base}${path}`, { ...options, redirect: 'manual', signal: options.signal ?? AbortSignal.timeout(5000) });
  const text = await response.text();
  let body = null;
  if (text && response.headers.get('content-type')?.includes('json')) body = JSON.parse(text);
  return { status: response.status, headers: response.headers, text, body };
}

export async function mcpPost(base, token, body, { sessionId } = {}) {
  return syntheticHttpRequest(base, '/mcp', {
    method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream',
      Authorization: `Bearer ${token}`, 'MCP-Protocol-Version': PROTOCOL,
      ...(sessionId ? { 'Mcp-Session-Id': sessionId } : {}) },
    body: JSON.stringify(body),
  });
}

/** Connect to an already-started synthetic CLI process. No Core lifecycle ownership. */
export async function connectLegacyMcpReader({ state, base, requireMessage = true }) {
  assertLoopbackBase(base);
  const client = await syntheticHttpRequest(base, '/register', { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ client_name: 'synthetic-schema6-reader', redirect_uris: [REDIRECT_URI], token_endpoint_auth_method: 'none' }) });
  assert.equal(client.status, 201, 'synthetic OAuth registration');
  const verifier = randomBytes(32).toString('base64url');
  const auth = await syntheticHttpRequest(base, '/authorize', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ response_type: 'code', client_id: client.body.client_id, redirect_uri: REDIRECT_URI,
      code_challenge: createHash('sha256').update(verifier).digest('base64url'), code_challenge_method: 'S256',
      scope: 'i.read', resource: `${base}/mcp`, state: 'synthetic-state', passphrase: state.passphrase }) });
  assert.equal(auth.status, 302, 'synthetic OAuth authorization');
  const location = new URL(auth.headers.get('location'));
  assert.equal(location.origin, 'https://synthetic.invalid');
  assert.ok(location.searchParams.get('code'), 'synthetic OAuth code');
  const tokenResult = await syntheticHttpRequest(base, '/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'authorization_code', code: location.searchParams.get('code'),
      client_id: client.body.client_id, redirect_uri: REDIRECT_URI, code_verifier: verifier, resource: `${base}/mcp` }) });
  assert.equal(tokenResult.status, 200, 'synthetic OAuth token');
  const token = tokenResult.body.access_token;
  assert.ok(token);
  const init = await mcpPost(base, token, { jsonrpc: '2.0', id: 1, method: 'initialize',
    params: { protocolVersion: PROTOCOL, capabilities: {}, clientInfo: { name: 'synthetic-schema6-reader', version: '1' } } });
  assert.equal(init.status, 200);
  assert.ok(init.body?.result, 'real MCP initialize result');
  const sessionId = init.headers.get('mcp-session-id');
  assert.ok(sessionId);
  const initialized = await mcpPost(base, token, { jsonrpc: '2.0', method: 'notifications/initialized' }, { sessionId });
  assert.equal(initialized.status, 202);
  let requestId = 2;
  const recall = async (query = state.query) => {
    const result = await mcpPost(base, token, { jsonrpc: '2.0', id: requestId++, method: 'tools/call',
      params: { name: 'i_recall', arguments: { query } } }, { sessionId });
    assert.equal(result.status, 200);
    assert.equal(result.body?.result?.isError, false, 'real legacy lazy read model must open candidate Core DB');
    return result;
  };
  const firstRecall = await recall();
  assert.ok(firstRecall.body.result.structuredContent.memory.count > 0, 'synthetic memory must be read');
  if (requireMessage) assert.ok(firstRecall.body.result.structuredContent.messages.count > 0, 'synthetic Core message must be read');
  return { base, token, sessionId, firstRecall, recall };
}

export async function startLegacyMcpReader({ state, nodePath = process.execPath, coreUrl, requireMessage = true }) {
  verifyLegacySourceInventory();
  const port = await allocateSyntheticLoopbackPort();
  const base = `http://127.0.0.1:${port}`;
  const cliArgs = legacyReaderCliArgs({ state, port, coreUrl });
  const env = { ...process.env };
  for (const key of Object.keys(env)) if (/^(I_|NODE_OPTIONS$|NODE_PATH$)/i.test(key)) delete env[key];
  Object.assign(env, legacyReaderEnvironment(state));
  const child = spawn(nodePath, cliArgs, { cwd: state.readerRoot, env, stdio: ['ignore', 'ignore', 'pipe'], windowsHide: true });
  let stderr = '';
  child.stderr.on('data', chunk => { stderr = (stderr + chunk.toString()).slice(-16000); });
  let spawnError;
  child.on('error', error => { spawnError = error; });
  const close = async () => {
    if (child.exitCode !== null || child.signalCode !== null) return;
    child.kill('SIGTERM');
    for (let n = 0; n < 100 && child.exitCode === null && child.signalCode === null; n++) await delay(25);
    if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
    for (let n = 0; n < 100 && child.exitCode === null && child.signalCode === null; n++) await delay(25);
    assert.ok(child.exitCode !== null || child.signalCode !== null, 'synthetic MCP child must exit');
  };
  try {
    let ready = false;
    for (let n = 0; n < 100; n++) {
      if (spawnError) throw spawnError;
      assert.equal(child.exitCode, null, 'synthetic MCP exited before ready');
      try { ready = (await syntheticHttpRequest(base, '/.well-known/oauth-authorization-server')).status === 200; } catch { /* starting */ }
      if (ready) break;
      await delay(25);
    }
    assert.ok(ready, 'synthetic MCP readiness timed out');
    const connected = await connectLegacyMcpReader({ state, base, requireMessage });
    return { ...connected, child, cliArgs, env: legacyReaderEnvironment(state), close, syntheticStderr: () => stderr };
  } catch (error) { await close(); throw error; }
}
