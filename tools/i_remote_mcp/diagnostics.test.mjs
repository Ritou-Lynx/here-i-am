import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { createJsonlDiagnosticWriter, createRequestDiagnostics, userAgentFamily } from './diagnostics.mjs';
import { authorizeParams, createFakeReadModel, initSession, mcpPost, obtainTokens, pkcePair,
  PUBLIC_URL, REDIRECT_URI, registerClient, startTestServer } from './fixtures.mjs';

const identityLoader = () => ({ identity: { name: 'SYNTHETIC_RESULT_SECRET' } });
const synthetic = (options = {}) => startTestServer({ identityLoader, ...options });
const request = (options = {}) => ({ method: 'GET', url: '/authorize', headers: {}, ...options });
const config = (diagnostic, options = {}) => ({ issuer: PUBLIC_URL, resource: `${PUBLIC_URL}/mcp`, diagnostic,
  now: () => Date.UTC(2026, 9, 3), ...options });

test('UA classifier returns only fixed families and never raw tokens', () => {
  const cases = [[undefined, 'absent'], ['', 'absent'], ['Claude-User/1.0', 'claude'],
    ['Anthropic/1.2', 'claude'], ['Mozilla Chrome/1 Safari/1 Edg/1', 'edge'],
    ['Firefox/1', 'firefox'], ['Chrome/1', 'chromium'], ['Safari/1', 'safari'],
    ['curl/8.0', 'curl'], ['node', 'node'], ['undici', 'node'],
    ['python-httpx/0.28.1', 'python-httpx'], ['python-requests/2.32.0', 'python-requests'],
    ['python-httpx/0.28.1 TOKEN_SECRET', 'python-httpx'], ['python-requests/2.32.0 TOKEN_SECRET', 'python-requests'],
    ['Bearer eyJhbGciOiJIUzI1NiJ9.SECRET.token', 'other'], ['TOKEN_SECRET Chrome/999', 'chromium']];
  for (const [ua, expected] of cases) assert.equal(userAgentFamily(ua), expected);
});

test('request projection strips query, credentials, fragments, headers and unknown URL/method fields', () => {
  const records = [];
  const params = new URLSearchParams({ redirect_uri: 'https://USER_SECRET:PASS_SECRET@claude.ai/api/mcp/auth_callback?code=CODE_SECRET#FRAGMENT_SECRET',
    resource: `${PUBLIC_URL}/mcp/?token=RESOURCE_SECRET`, state: 'STATE_SECRET', client_id: 'CLIENT_SECRET' });
  createRequestDiagnostics(request({ url: `/authorize?${params}`, headers: { origin: 'https://claude.ai',
    authorization: 'Bearer HEADER_SECRET', cookie: 'COOKIE_SECRET', 'user-agent': 'UA_TOKEN_SECRET Chrome/1' } }), config((r) => records.push(r))).finish(200);
  assert.deepEqual(records[0], { timestamp: '2026-10-03T00:00:00.000Z', event: 'http_request', method: 'GET',
    path: '/authorize', ua_family: 'chromium', origin: 'https://claude.ai/', status: 200,
    callback: REDIRECT_URI, resource: `${PUBLIC_URL}/mcp/` });
  createRequestDiagnostics(request({ method: 'SECRET_METHOD', url: '/PATH_SECRET?QUERY_SECRET',
    headers: { origin: 'https://ORIGIN_SECRET.invalid' } }), config((r) => records.push(r))).finish(404);
  createRequestDiagnostics(request({ url: '/authorize?redirect_uri=https://HOST_SECRET.invalid/PATH_SECRET&resource=INVALID_SECRET',
    headers: { origin: 'null' } }), config((r) => records.push(r))).finish(400);
  assert.equal(records[1].method, 'OTHER');
  assert.equal(records[1].path, '[redacted]');
  assert.equal(records[1].origin, '[redacted]');
  assert.equal(records[2].callback, '[redacted]');
  assert.equal(records[2].resource, '[redacted]');
  assert.doesNotMatch(JSON.stringify(records), /SECRET/);
});

test('duplicate authorize parameters project the last value used by the server', () => {
  const records = [];
  const cases = [
    [['https://SECRET.invalid/callback', REDIRECT_URI], ['RESOURCE_SECRET', `${PUBLIC_URL}/mcp`], REDIRECT_URI, `${PUBLIC_URL}/mcp`],
    [[REDIRECT_URI, 'https://SECRET.invalid/callback'], [`${PUBLIC_URL}/mcp`, 'RESOURCE_SECRET'], '[redacted]', '[redacted]'],
    [[REDIRECT_URI, 'https://claude.com/api/mcp/auth_callback'], [`${PUBLIC_URL}/mcp`, `${PUBLIC_URL}/mcp/`], 'https://claude.com/api/mcp/auth_callback', `${PUBLIC_URL}/mcp/`],
  ];
  for (const [callbacks, resources, expectedCallback, expectedResource] of cases) {
    const params = new URLSearchParams();
    for (const value of callbacks) params.append('redirect_uri', value);
    for (const value of resources) params.append('resource', value);
    createRequestDiagnostics(request({ url: `/authorize?${params}` }), config((r) => records.push(r))).finish(200);
    assert.equal(records.at(-1).callback, expectedCallback);
    assert.equal(records.at(-1).resource, expectedResource);
  }
  assert.doesNotMatch(JSON.stringify(records), /SECRET/);
});
test('daily JSONL has UTC on every line, rotates by UTC date and reports only fixed write errors', () => {
  const directory = mkdtempSync(join(tmpdir(), 'i-diagnostics-synthetic-'));
  try {
    const errors = [];
    const writer = createJsonlDiagnosticWriter({ logDir: directory, onWriteError: (e) => errors.push(e) });
    let clock = Date.UTC(2026, 9, 3, 23, 59, 59);
    const diagnostic = () => createRequestDiagnostics(request({ url: '/mcp' }), config(writer, { now: () => clock })).finish(401);
    diagnostic(); clock += 2000; diagnostic();
    assert.deepEqual(readdirSync(directory).sort(), ['2026-10-03.jsonl', '2026-10-04.jsonl']);
    for (const file of readdirSync(directory)) {
      const lines = readFileSync(join(directory, file), 'utf8').trim().split('\n');
      assert.equal(lines.length, 1);
      const record = JSON.parse(lines[0]);
      assert.match(record.timestamp, /^2026-10-0[34]T.*Z$/);
      assert.equal(record.ua_family, 'absent');
    }
    writer({ timestamp: '../../PATH_SECRET' });
    assert.deepEqual(errors, ['diagnostic_write_failed']);
    assert.equal(readdirSync(directory).length, 2);
    const failureDirectory = join(directory, 'removed');
    const failing = createJsonlDiagnosticWriter({ logDir: failureDirectory, onWriteError: (e) => errors.push(e) });
    rmSync(failureDirectory, { recursive: true });
    writeFileSync(failureDirectory, 'synthetic blocker');
    createRequestDiagnostics(request(), config(failing)).finish(200);
    assert.deepEqual(errors, ['diagnostic_write_failed', 'diagnostic_write_failed']);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test('real HTTP OAuth and tools diagnostics keep protocol metadata and redact body/results/errors', async () => {
  const records = [];
  const legacy = [];
  const model = createFakeReadModel();
  const ctx = await synthetic({ diagnostic: (r) => records.push(r), log: (r) => legacy.push(r), readModel: model });
  const control = await synthetic();
  try {
    for (const path of ['/.well-known/oauth-authorization-server', '/.well-known/oauth-protected-resource', '/.well-known/oauth-protected-resource/mcp']) {
      const observed = await fetch(`${ctx.base}${path}`);
      const original = await fetch(`${control.base}${path}`);
      assert.equal(observed.status, original.status);
      assert.deepEqual(await observed.json(), await original.json());
    }
    const client = await registerClient(ctx.base);
    const { challenge } = pkcePair();
    const params = authorizeParams({ clientId: client.body.client_id, challenge, state: 'STATE_SECRET' });
    const authPage = await fetch(`${ctx.base}/authorize?${params}`, { headers: { 'User-Agent': 'Claude-User/1 TOKEN_SECRET', Origin: 'https://claude.ai' } });
    assert.equal(authPage.status, 200);
    await authPage.text();
    const token = await obtainTokens(ctx.base);
    const { sessionId, init } = await initSession(ctx.base, token.access_token);
    const controlToken = await obtainTokens(control.base);
    const controlInit = await initSession(control.base, controlToken.access_token);
    assert.deepEqual(init.body, controlInit.init.body);
    const list = await mcpPost(ctx.base, token.access_token, { jsonrpc: '2.0', id: 3, method: 'tools/list' }, { sessionId });
    const controlList = await mcpPost(control.base, controlToken.access_token, { jsonrpc: '2.0', id: 3, method: 'tools/list' }, { sessionId: controlInit.sessionId });
    assert.deepEqual(list.body, controlList.body);
    const invoke = (name, args) => mcpPost(ctx.base, token.access_token, {
      jsonrpc: '2.0', id: 'RPC_ID_SECRET', method: 'tools/call', params: { name, arguments: args },
    }, { sessionId, headers: { 'User-Agent': 'TOKEN_SECRET', Cookie: 'COOKIE_SECRET' } });
    const success = await invoke('i_context', {});
    assert.equal(success.body.result.isError, false);
    assert.match(JSON.stringify(success.body), /SYNTHETIC_RESULT_SECRET/);
    assert.equal((await invoke('i_recall', { query: 'QUERY_SECRET' })).body.result.isError, false);
    assert.equal((await invoke('i_recall', { query: '' })).body.result.isError, true);
    assert.equal((await invoke('UNKNOWN_TOOL_SECRET', { secret: 'ARGUMENT_SECRET' })).body.error.code, -32602);
    model.policySummary = () => { throw new Error('RAW_ERROR_SECRET /private/path token=ERROR_TOKEN_SECRET'); };
    assert.equal((await invoke('i_context', {})).body.result.isError, true);
    await mcpPost(ctx.base, token.access_token, { jsonrpc: '2.0', id: 1, method: 'METHOD_SECRET' }, { sessionId });
    await fetch(`${ctx.base}/PATH_SECRET?code=CODE_SECRET`);
    const authorizations = records.filter((r) => r.path === '/authorize');
    assert.ok(authorizations.some((r) => r.method === 'GET' && r.status === 200 && r.callback === REDIRECT_URI && r.resource === `${PUBLIC_URL}/mcp` && r.ua_family === 'claude'));
    assert.ok(authorizations.some((r) => r.method === 'POST' && r.status === 302));
    assert.ok(records.some((r) => r.path === '/token' && r.method === 'POST' && r.status === 200));
    const calls = records.filter((r) => r.event === 'mcp_rpc' && r.rpc_method === 'tools/call');
    assert.deepEqual(calls.map((r) => [r.tool, r.outcome, r.error_code]), [
      ['i_context', 'success', undefined], ['i_recall', 'success', undefined],
      ['i_recall', 'error', 'tool_error'], ['other', 'error', -32602],
      ['i_context', 'error', 'data_source_unavailable'],
    ]);
    for (const record of records) {
      assert.match(record.timestamp, /^2026-10-02T04:00:00\.000Z$/);
      assert.equal(typeof record.ua_family, 'string');
      assert.equal(typeof record.status, 'number');
    }
    const serialized = JSON.stringify({ records, legacy });
    assert.doesNotMatch(serialized, /SECRET|三花|char-lin|private\/path|passphrase|"authorization"|arguments|structuredContent|client_id/);
    for (const secret of [token.access_token, token.refresh_token, token.code, token.verifier, sessionId]) assert.ok(!serialized.includes(secret));
  } finally { await ctx.close(); await control.close(); }
});

test('throwing and rejecting diagnostic or legacy sinks cannot alter successful protocol responses', async () => {
  for (const sink of [() => { throw new Error('SINK_SECRET'); }, () => Promise.reject(new Error('SINK_SECRET'))]) {
    const ctx = await synthetic({ diagnostic: sink, log: sink });
    try {
      const token = await obtainTokens(ctx.base);
      const { sessionId } = await initSession(ctx.base, token.access_token);
      const result = await mcpPost(ctx.base, token.access_token, { jsonrpc: '2.0', id: 2,
        method: 'tools/call', params: { name: 'i_context' } }, { sessionId });
      assert.equal(result.status, 200);
      assert.equal(result.body.result.isError, false);
    } finally { await ctx.close(); }
  }
});
