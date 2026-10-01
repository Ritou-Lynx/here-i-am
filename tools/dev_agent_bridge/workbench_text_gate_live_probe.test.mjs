import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { request as httpRequest } from 'node:http';
import { createProbeProxy, initialReport, fixedProbeBody, buildLaunch, assertProbeConfig,
  runProbeSession, main, MODEL, PROMPT, inspectFixedRequest } from './workbench_text_gate_live_probe.mjs';
import { restrictions } from './workbench_tool_behavior_probe.mjs';
import { TextGateTransportError } from './workbench_text_gate_transport.mjs';

const rawBody = () => ({ model: MODEL, input: [
  { type: 'message', role: 'developer', content: [{ type: 'input_text', text: 'SYNTHETIC_LOCAL_PATH_SECRET' }] },
  { type: 'message', role: 'user', content: [{ type: 'input_text', text: PROMPT }] },
  { type: 'additional_tools', role: 'developer', tools: [{ type: 'function', name: 'synthetic_tool' }] },
], instructions: 'SYNTHETIC_INSTRUCTION_SECRET', tools: [{ type: 'web_search' }], tool_choice: 'auto',
client_metadata: { synthetic: 'SYNTHETIC_METADATA_SECRET' } });
const headers = { 'content-type': 'application/json', authorization: 'Bearer SYNTHETIC_ONLY', 'chatgpt-account-id': 'synthetic_account' };
async function localProxy(exchange) {
  const report = initialReport(); const proxy = createProbeProxy(report, { exchange });
  await new Promise(resolve => proxy.server.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${proxy.server.address().port}/v1/responses`;
  return { report, proxy, url, send: (body = rawBody(), options = {}) => fetch(url, {
    method: 'POST', headers, body: JSON.stringify(body), ...options,
  }) };
}
test('request reconstruction fixes model, prompt, instructions and erases local context/catalogs', () => {
  const fixed = fixedProbeBody(rawBody());
  assert.equal(fixed.model, MODEL); assert.equal(fixed.input.length, 1);
  assert.equal(fixed.input[0].content[0].text, PROMPT);
  assert.deepEqual(fixed.tools, []); assert.equal(fixed.tool_choice, 'none');
  assert.equal(fixed.parallel_tool_calls, false); assert.equal(fixed.store, false);
  assert.equal(JSON.stringify(fixed).includes('SECRET'), false);
  for (const patch of [{ model: 'other' }, { upstreamUrl: 'https://example.invalid' }, { headers: { authorization: 'Bearer OTHER' } },
    { previous_response_id: 'history' }, { input: [] }, { input: [{ type: 'function_call_output' }] },
    { input: [{ type: 'message', role: 'user', content: [{ type: 'input_text', text: 'Other prompt' }] }] }])
    assert.throws(() => fixedProbeBody({ ...rawBody(), ...patch }), /request_scope_rejected/);
});

test('request diagnostics expose only known field names, counts and fixed-prompt booleans', () => {
  const normal = inspectFixedRequest(rawBody());
  assert.equal(normal.normalized, true); assert.equal(normal.messages.filter(item => item.fixed_prompt).length, 1);
  assert.equal(JSON.stringify(normal).includes('SECRET'), false);
  const invalid = inspectFixedRequest({ ...rawBody(), service_tier: 'PRIVATE_VALUE', PRIVATE_KEY: 'PRIVATE_VALUE' });
  assert.equal(invalid.normalized, false); assert.equal(invalid.code, 'request_shape');
  assert.equal(invalid.unknown_field_count, 1); assert.ok(invalid.known_fields.includes('service_tier'));
  assert.equal(JSON.stringify(invalid).includes('PRIVATE'), false);
});

test('CLI environment user prefix is discarded while the last unique prompt remains exact', () => {
  const prefix = { type: 'message', role: 'user', content: [{ type: 'input_text', text: '<environment_context>PRIVATE_PATH</environment_context>' }] };
  const body = rawBody(); body.input.unshift(prefix);
  const fixed = fixedProbeBody(body);
  assert.equal(fixed.input.length, 1); assert.equal(fixed.input[0].content[0].text, PROMPT);
  assert.equal(JSON.stringify(fixed).includes('PRIVATE_PATH'), false);
  assert.throws(() => fixedProbeBody({ ...body, input: [...body.input, prefix] }), /request_scope_rejected/);
  assert.throws(() => fixedProbeBody({ ...body, input: [...body.input, { ...prefix, content: [{ type: 'input_text', text: PROMPT }] }] }), /request_scope_rejected/);
  assert.throws(() => fixedProbeBody({ ...body, previous_response_id: 'PRIVATE_HISTORY' }), /request_scope_rejected/);
});
test('multiple early user prefixes and developer/system suffixes leave only the constant upstream body', async () => {
  let calls = 0; let captured;
  const p = await localProxy(async body => { calls++; captured = body; return Buffer.from('synthetic'); });
  try {
    const message = (role, text) => ({ type: 'message', role, content: [{ type: 'input_text', text }] });
    const body = rawBody();
    body.input.unshift(message('user', 'PRIVATE_PREFIX_ONE'), message('user', 'PRIVATE_PREFIX_TWO'));
    body.input.push(message('developer', 'PRIVATE_DEVELOPER_SUFFIX'), message('system', 'PRIVATE_SYSTEM_SUFFIX'));
    p.proxy.arm();
    assert.equal((await p.send(body)).status, 200);
    assert.equal(calls, 1); assert.equal(p.report.upstream_attempts, 1);
    assert.deepEqual(captured, {
      model: MODEL, instructions: 'This is a fixed synthetic text probe. Follow the user instruction.',
      input: [{ type: 'message', role: 'user', content: [{ type: 'input_text', text: PROMPT }] }],
      tools: [], tool_choice: 'none', parallel_tool_calls: false, store: false, stream: true,
      reasoning: { effort: 'low' },
    });
    assert.equal(JSON.stringify(p.report).includes('PRIVATE'), false);
  } finally { await p.proxy.close(); }
});
test('assistant messages before or after the fixed prompt are rejected before upstream', async () => {
  let calls = 0; const p = await localProxy(async () => { calls++; return Buffer.from('synthetic'); });
  try {
    p.proxy.arm();
    const assistant = { type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'PRIVATE_ASSISTANT' }] };
    for (const position of ['before', 'after']) {
      const body = rawBody();
      if (position === 'before') body.input.unshift(assistant); else body.input.push(assistant);
      assert.equal((await p.send(body)).status, 422);
      assert.equal(calls, 0); assert.equal(p.report.upstream_attempts, 0);
    }
    assert.equal(p.report.code, 'request_scope_rejected');
    assert.equal(JSON.stringify(p.report).includes('PRIVATE'), false);
  } finally { await p.proxy.close(); }
});
test('unarmed, invalid route, body and missing auth never dispatch upstream', async () => {
  let calls = 0; const p = await localProxy(async () => { calls++; return Buffer.from('synthetic'); });
  try {
    assert.equal((await p.send()).status, 422);
    p.proxy.arm();
    assert.equal((await fetch(`${p.url}?target=other`, { method: 'POST', headers, body: JSON.stringify(rawBody()) })).status, 422);
    assert.equal((await p.send(rawBody(), { headers: { 'content-type': 'application/json' } })).status, 422);
    assert.equal((await p.send({ ...rawBody(), model: 'other' })).status, 422);
    assert.equal((await p.send(rawBody(), { headers: { ...headers, 'content-encoding': 'gzip' } })).status, 422);
    assert.equal((await p.send(rawBody(), { body: '{bad' })).status, 422);
    assert.equal((await p.send(rawBody(), { body: 'x'.repeat(65537) })).status, 422);
    assert.equal(calls, 0); assert.equal(p.report.upstream_attempts, 0);
  } finally { await p.proxy.close(); }
});
test('concurrent requests share one irreversible budget and fixed target/header allowlist', async () => {
  let calls = 0; let captured;
  const p = await localProxy(async (body, options) => {
    calls++; captured = { body, options }; await new Promise(resolve => setTimeout(resolve, 20));
    return Buffer.from('synthetic text gate output');
  });
  try {
    p.proxy.arm();
    const replies = await Promise.all(Array.from({ length: 5 }, () => p.send(rawBody(), { headers: { ...headers, 'x-synthetic-secret': 'drop_me' } })));
    assert.equal(replies.filter(reply => reply.status === 200).length, 1);
    assert.equal(calls, 1); assert.equal(p.report.upstream_attempts, 1);
    assert.equal(captured.options.upstreamUrl, 'https://chatgpt.com/backend-api/codex/responses');
    assert.equal(captured.options.model, MODEL); assert.deepEqual(captured.options.headers, headersWithoutContent());
    assert.equal(JSON.stringify(captured.body).includes('SECRET'), false);
    assert.equal((await p.send()).status, 422); assert.equal(calls, 1);
    const saved = JSON.stringify(p.report);
    for (const secret of ['SYNTHETIC_ONLY', 'synthetic_account', 'drop_me', 'SECRET']) assert.equal(saved.includes(secret), false);
  } finally { await p.proxy.close(); }
});
function headersWithoutContent() { return { authorization: headers.authorization, 'chatgpt-account-id': headers['chatgpt-account-id'] }; }
test('upstream errors never echo arbitrary error code/message and cannot retry', async () => {
  for (const error of [Object.assign(new Error('PRIVATE_BODY https://secret.invalid?token=PRIVATE'), { code: 'PRIVATE_CODE' }),
    new TextGateTransportError('response_rejected', { gateCode: 'PRIVATE_CODE' }),
    new TextGateTransportError('http_status', { httpStatus: 401 })]) {
    let calls = 0; const p = await localProxy(async () => { calls++; throw error; });
    try {
      p.proxy.arm(); const response = await p.send(); const reply = await response.text();
      assert.equal(response.status, 422); assert.equal(reply.includes('PRIVATE'), false);
      assert.equal(JSON.stringify(p.report).includes('PRIVATE'), false);
      assert.equal(p.report.response_released, false);
      assert.equal((await p.send()).status, 422); assert.equal(calls, 1);
      if (error.httpStatus) assert.equal(p.report.http_status, 401);
    } finally { await p.proxy.close(); }
  }
});

test('response diagnostics rebuild supplied error metadata and redact unknown gate codes', async () => {
  const error = new TextGateTransportError('response_rejected', { gateCode: 'PRIVATE_CODE' });
  error.responseMetadata = { http_status: 200, media_type: 'PRIVATE_TYPE', parameter_count: 2,
    charset: 'PRIVATE_CHARSET', token: 'PRIVATE_TOKEN' };
  error.responseDiagnostics = { diagnostic_only: true, text: 'PRIVATE_PAYLOAD' };
  const p = await localProxy(async () => { throw error; });
  try {
    p.proxy.arm(); assert.equal((await p.send()).status, 422);
    assert.deepEqual(p.report.response_metadata, { http_status: 200, media_type: 'other', parameter_count: 2, charset: 'other' });
    assert.equal(p.report.response_gate_code, 'other');
    assert.equal(p.report.response_diagnostics, undefined);
    assert.equal(p.report.response_released, false);
    assert.equal(JSON.stringify(p.report).includes('PRIVATE'), false);
  } finally { await p.proxy.close(); }
});
test('launch excludes ambient token/proxy variables and pins restrictive provider options', () => {
  const result = buildLaunch('synthetic.exe', 'synthetic-home', 'synthetic-cwd', 'http://127.0.0.1:1234/v1', {
    PATH: 'synthetic-path', OPENAI_API_KEY: 'PRIVATE', CODEX_HOME: 'PRIVATE', HTTP_PROXY: 'PRIVATE',
  });
  assert.deepEqual(Object.keys(result.env).sort(), ['APPDATA', 'CODEX_HOME', 'HOME', 'LOCALAPPDATA', 'PATH', 'TEMP', 'TMP', 'USERPROFILE'].sort());
  assert.equal(JSON.stringify(result).includes('PRIVATE'), false);
  const args = result.commandSpec.args.join(' ');
  for (const value of ['requires_openai_auth=true', 'request_max_retries=0', 'stream_max_retries=0', 'supports_websockets=false', 'agents.enabled=false', 'features.enable_request_compression=false']) assert.ok(args.includes(value));
  assert.throws(() => buildLaunch('x', 'y', 'z', 'https://example.invalid/v1'), /invalid_proxy_target/);
});
const baseUrl = 'http://127.0.0.1:1234/v1';
function config() {
  return { layers: [{ name: { type: 'sessionFlags' }, config: {} }], config: {
    model: MODEL, model_provider: 'p6_live_text_probe', agents: { enabled: false }, approval_policy: 'never', sandbox_mode: 'read-only',
    web_search: 'disabled', project_doc_max_bytes: 0, notify: [], mcp_servers: {}, hooks: {},
    features: Object.fromEntries(Object.entries(restrictions(false)).filter(([key, value]) => key.startsWith('features.') && typeof value === 'boolean').map(([key, value]) => [key.slice(9), value])),
    model_providers: { p6_live_text_probe: { base_url: baseUrl, requires_openai_auth: true, wire_api: 'responses',
      request_max_retries: 0, stream_max_retries: 0, supports_websockets: false } },
  } };
}
test('effective config rejects credentials, external URLs, retries, tools and inherited user config', () => {
  assert.doesNotThrow(() => assertProbeConfig(config(), null, baseUrl));
  const semanticEmpty = config(); semanticEmpty.config.hooks = { onStart: [] };
  Object.assign(semanticEmpty.config.model_providers.p6_live_text_probe, { http_headers: {}, env_http_headers: {}, query_params: {} });
  assert.doesNotThrow(() => assertProbeConfig(semanticEmpty, null, baseUrl));
  for (const mutate of [c => { c.layers.push({ name: { type: 'user' }, config: { x: 1 } }); },
    c => { c.config.agents.enabled = true; }, c => { c.config.features.shell_tool = true; },
    c => { c.config.model_providers.p6_live_text_probe.env_key = 'PRIVATE'; },
    c => { c.config.model_providers.p6_live_text_probe.base_url = 'https://example.invalid'; },
    c => { c.config.model_providers.p6_live_text_probe.request_max_retries = 1; }]) {
    const value = config(); mutate(value); assert.throws(() => assertProbeConfig(value, null, baseUrl), /config_rejected/);
  }
});
class FakeClient extends EventEmitter {
  constructor(account = null) { super(); this.account = account; this.threadStarts = 0; this.turnStarts = 0; this.stops = 0; this.notificationSequence = 0; }
  async start() {}
  async readAccount() { return { requiresOpenaiAuth: true, account: this.account }; }
  async request(method) { return method === 'config/read' ? config() : { requirements: null }; }
  async startThread(params) { this.threadStarts++; this.threadParams = params; return { model: MODEL, modelProvider: 'p6_live_text_probe', thread: { id: 'synthetic_thread' } }; }
  async startTurn(id, text, params) { this.turnStarts++; this.turnParams = { id, text, params }; return { turn: { id: 'synthetic_turn' } }; }
  async waitForNotification() { return { params: { turn: { status: 'failed', error: 'PRIVATE' } } }; }
  async stop() { this.stops++; return { process_close_observed: true }; }
}
test('missing ChatGPT login cannot arm, start thread/turn or request upstream; stop still required', async () => {
  const report = initialReport(); const client = new FakeClient(); let armed = 0; let closed = 0;
  const proxy = { arm() { armed++; }, disarm() {}, async close() { closed++; } };
  await runProbeSession(client, proxy, report, { cwd: 'synthetic-cwd', baseUrl });
  assert.equal(armed, 0); assert.equal(client.threadStarts, 0); assert.equal(client.turnStarts, 0);
  assert.equal(client.stops, 1); assert.equal(closed, 1); assert.equal(report.code, 'chatgpt_login_required');
  assert.equal(report.upstream_attempts, 0); assert.equal(report.process_close_observed, true);
});
test('one ephemeral synthetic turn with no dynamic tools or roots, failed terminal remains failed', async () => {
  const report = initialReport(); const client = new FakeClient({ type: 'chatgpt', email: 'PRIVATE' });
  const proxy = { arm() {}, disarm() {}, async close() {} };
  await runProbeSession(client, proxy, report, { cwd: 'synthetic-cwd', baseUrl });
  assert.equal(client.threadStarts, 1); assert.equal(client.turnStarts, 1); assert.equal(client.stops, 1);
  assert.equal(client.threadParams.ephemeral, true); assert.equal(client.threadParams.approvalPolicy, 'never');
  assert.equal(client.threadParams.sandbox, 'read-only');
  for (const key of ['dynamicTools', 'environments', 'runtimeWorkspaceRoots', 'selectedCapabilityRoots']) assert.deepEqual(client.threadParams[key], []);
  assert.equal(client.turnParams.text, PROMPT); assert.equal(JSON.stringify(report).includes('PRIVATE'), false);
  assert.equal(report.status, 'failed'); assert.equal(report.production_isolation_passed, false); assert.equal(report.human_gate_passed, false);
});
test('unexpected serverRequest is rejected, disarms and prevents thread creation', async () => {
  const report = initialReport(); const client = new FakeClient({ type: 'chatgpt' }); let rejected = false; let disarmed = 0;
  client.start = async () => client.emit('serverRequest', { method: 'PRIVATE', params: { secret: 'PRIVATE' }, respondError: () => { rejected = true; } });
  const proxy = { arm() { assert.fail('must remain closed'); }, disarm() { disarmed++; }, async close() {} };
  await runProbeSession(client, proxy, report, { cwd: 'synthetic-cwd', baseUrl });
  assert.equal(rejected, true); assert.ok(disarmed > 0); assert.equal(client.threadStarts, 0); assert.equal(client.stops, 1);
  assert.equal(report.server_requests_rejected, 1); assert.equal(JSON.stringify(report).includes('PRIVATE'), false);
});
test('stop failure cannot become success or expose process error detail', async () => {
  const report = initialReport(); const client = new FakeClient(); let closed = false;
  client.stop = async () => { throw new Error('PRIVATE_PROCESS_DETAIL'); };
  await runProbeSession(client, { arm() {}, disarm() {}, async close() { closed = true; } }, report, { cwd: 'synthetic-cwd', baseUrl });
  assert.equal(closed, true); assert.equal(report.code, 'stop_close_unconfirmed');
  assert.equal(report.process_close_observed, false); assert.equal(report.status, 'failed');
  assert.equal(JSON.stringify(report).includes('PRIVATE'), false);
});
test('command entrypoint without explicit --live rejects before file or client work', async () => {
  const savedLog = console.log; const savedExit = process.exitCode; let output;
  try {
    console.log = value => { output = value; };
    const report = await main([]);
    assert.equal(report.code, 'explicit_live_required'); assert.equal(report.upstream_attempts, 0);
    assert.equal(report.status, 'failed'); assert.equal(JSON.parse(output).code, 'explicit_live_required');
  } finally { console.log = savedLog; process.exitCode = savedExit; }
});

test('inspect mode reads account and config but never arms or starts a thread', async () => {
  const report = initialReport(); const client = new FakeClient({ type: 'chatgpt', email: 'PRIVATE' });
  await runProbeSession(client, { arm() { assert.fail('inspect must not arm'); }, disarm() {}, async close() {} }, report,
    { cwd: 'synthetic-cwd', baseUrl, inspectOnly: true });
  assert.equal(report.status, 'inspection_complete'); assert.equal(client.threadStarts, 0); assert.equal(client.turnStarts, 0);
  assert.equal(report.upstream_attempts, 0); assert.equal(client.stops, 1); assert.equal(report.process_close_observed, true);
  assert.ok(Object.values(report.config_checks).every(Boolean)); assert.equal(JSON.stringify(report).includes('PRIVATE'), false);
});

test('pre-arm diagnostics retain only bounded classifications, never URL or header values', async () => {
  let calls = 0; const p = await localProxy(async () => { calls++; });
  try {
    p.report.stage = 'startup';
    for (let i = 0; i < 10; i++) await fetch(p.url.replace('/responses', '/models?token=PRIVATE'), { headers: { authorization: 'Bearer PRIVATE' } });
    assert.equal(calls, 0); assert.equal(p.report.request_observations.length, 8);
    assert.deepEqual(p.report.request_observations[0], { stage: 'startup', armed: false, method: 'GET', route: 'models', json: false, auth_present: true, account_header_present: false });
    assert.equal(JSON.stringify(p.report).includes('PRIVATE'), false);
  } finally { await p.proxy.close(); }
});

test('exact model discovery GET is a local error and cannot arm or consume generation budget', async () => {
  let calls = 0; const p = await localProxy(async () => { calls++; return Buffer.from('synthetic'); });
  try {
    const catalog = p.url.replace('/responses', '/models');
    for (const url of [`${catalog}?client_version=PRIVATE&token=PRIVATE`]) {
      const result = await fetch(url, { headers: { authorization: 'Bearer PRIVATE' } });
      assert.equal(result.status, 404); assert.equal((await result.text()).includes('PRIVATE'), false);
    }
    assert.equal(p.report.local_metadata_rejections, 1); assert.equal(p.report.code, null);
    assert.equal(calls, 0); assert.equal(p.report.upstream_attempts, 0);
    assert.equal((await fetch(catalog)).status, 404); // Still a local refusal, never an upstream retry.
    assert.equal((await p.send()).status, 422); // Discovery did not arm the proxy.
    for (const url of [`${catalog}/extra`, p.url.replace('/responses', '/models-other')]) assert.equal((await fetch(url)).status, 422);
    assert.equal((await fetch(catalog, { method: 'POST' })).status, 422);
    p.proxy.arm(); assert.equal((await p.send()).status, 200); assert.equal(calls, 1);
    assert.equal((await fetch(catalog)).status, 404);
    for (let i = p.report.local_metadata_rejections; i < 8; i++) assert.equal((await fetch(catalog)).status, 404);
    assert.equal((await fetch(catalog)).status, 422);
    assert.equal(JSON.stringify(p.report).includes('PRIVATE'), false);
  } finally { await p.proxy.close(); }
});

test('exact model discovery GET rejects body framing and encoding locally without upstream', async () => {
  let calls = 0; const p = await localProxy(async () => { calls++; return Buffer.from('synthetic'); });
  try {
    const catalog = p.url.replace('/responses', '/models');
    for (const [requestHeaders, body] of [
      [{ 'content-length': '1' }, 'x'],
      [{ 'transfer-encoding': 'chunked' }, 'x'],
      [{ 'content-encoding': 'gzip' }, undefined],
    ]) {
      const status = await new Promise((resolve, reject) => {
        const request = httpRequest(catalog, { method: 'GET', headers: requestHeaders, agent: false }, response => {
          response.resume();
          response.on('end', () => resolve(response.statusCode));
          response.on('error', reject);
        });
        request.on('error', reject);
        request.setTimeout(5000, () => request.destroy(new Error('Synthetic GET test timed out.')));
        request.end(body);
      });
      assert.equal(status, 422);
      assert.equal(calls, 0); assert.equal(p.report.upstream_attempts, 0);
      assert.equal(p.report.local_metadata_rejections, 0);
      assert.equal(p.report.code, 'metadata_request_rejected');
    }
    assert.equal(p.report.rejected_requests, 3);
  } finally { await p.proxy.close(); }
});
