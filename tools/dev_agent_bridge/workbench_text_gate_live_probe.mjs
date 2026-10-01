// Explicit, single-exchange candidate. Never production routing or stop receipts.
import { createServer } from 'node:http';
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { CodexAppServerClient } from './codex_app_server_client.mjs';
import { prepareDedicatedHome } from './workbench_text_gate_login.mjs';
import { TEXT_GATE_CLI_SHA256 } from './workbench_text_gate_runtime_pin.mjs';
import { restrictions } from './workbench_tool_behavior_probe.mjs';
import { normalizeTextOnlyRequest, TextOnlyRequestError } from './workbench_request_text_gate.mjs';
import { exchangeTextOnly, TextGateTransportError } from './workbench_text_gate_transport.mjs';
import { isRejectedTextResponseDiagnostic } from './workbench_response_text_diagnostics.mjs';

export const MODEL = 'gpt-5.6-sol';
export const PROMPT = 'Reply exactly: P6_TEXT_GATE_OK';
const INSTRUCTIONS = 'This is a fixed synthetic text probe. Follow the user instruction.';
const TARGET = 'https://chatgpt.com/backend-api/codex/responses';
const PROVIDER = 'p6_live_text_probe';
const MAX_BODY = 64 * 1024;
let liveExchangeUsed = false;
class ProbeError extends Error { constructor(code) { super(code); this.code = code; } }
const requireThat = (condition, code) => { if (!condition) throw new ProbeError(code); };
const emptyMap = value => value == null || (typeof value === 'object' && !Array.isArray(value) && Object.keys(value).length === 0);
const TRANSPORT_CODES = new Set(['http_status', 'request_rejected', 'response_rejected', 'transport_failed',
  'timeout', 'aborted', 'unsupported_content_type', 'missing_body', 'invalid_headers', 'diagnostic_input_limit', 'invalid_diagnostic_scope']);
function safeCode(error) {
  if (error instanceof ProbeError) return error.code;
  if (error instanceof TextGateTransportError && TRANSPORT_CODES.has(error.code)) return error.code;
  return 'probe_failed';
}
export function inspectFixedRequest(body) {
  const vocabulary = new Set(['model', 'input', 'instructions', 'reasoning', 'store', 'stream', 'include',
    'prompt_cache_key', 'text', 'client_metadata', 'tools', 'tool_choice', 'parallel_tool_calls',
    'max_output_tokens', 'previous_response_id', 'service_tier', 'metadata', 'background', 'conversation',
    'context_management', 'prompt_cache_retention', 'max_tool_calls', 'safety_identifier', 'temperature',
    'top_logprobs', 'top_p', 'truncation', 'stream_options', 'user']);
  const keys = body && typeof body === 'object' ? Object.keys(body) : [];
  const result = { known_fields: keys.filter(key => vocabulary.has(key)).sort(),
    unknown_field_count: keys.filter(key => !vocabulary.has(key)).length, normalized: false };
  try {
    const normalized = normalizeTextOnlyRequest(body, { model: MODEL, maxBytes: MAX_BODY, maxMessages: 16 });
    result.normalized = true;
    result.messages = normalized.input.map(item => ({ role: item.role, parts: item.content.length,
      fixed_prompt: item.content.length === 1 && item.content[0].text === PROMPT }));
  } catch (error) {
    const codes = new Set(['invalid_limits', 'request_shape', 'model_mismatch', 'invalid_json', 'request_too_large',
      'server_history', 'input_shape', 'catalog_shape', 'input_item_shape', 'non_message_input', 'content_shape',
      'non_text_content', 'annotated_content', 'empty_context', 'instructions_shape', 'reasoning_shape',
      'reasoning_effort', 'reasoning_summary', 'output_limit']);
    result.code = error instanceof TextOnlyRequestError && codes.has(error.code) ? error.code : 'unclassified';
  }
  return result;
}
export function initialReport() {
  return { status: 'not_started', code: null, chatgpt_login_present: false,
    authorization_present: false, account_header_present: false, requests_received: 0,
    upstream_attempts: 0, rejected_requests: 0, local_metadata_rejections: 0, response_released: false,
    fixed_text_observed: false, server_requests_rejected: 0, turn_completed: false,
    process_close_observed: false, stage: 'not_started', request_observations: [],
    production_isolation_passed: false, human_gate_passed: false };
}

// Validate the CLI envelope, then discard all CLI/system/developer context and
// replace it with public constants. No path, cache key, catalog or metadata exits.
export function fixedProbeBody(body) {
  let normalized;
  try { normalized = normalizeTextOnlyRequest(body, { model: MODEL, maxBytes: MAX_BODY, maxMessages: 16 }); }
  catch { throw new ProbeError('request_scope_rejected'); }
  const users = normalized.input.filter(item => item.role === 'user');
  const isFixedPrompt = item => item.content.length === 1 && item.content[0].text === PROMPT;
  // The CLI prepends its environment as an earlier user message. Every such
  // text-only prefix is discarded; only our last, unique fixed prompt survives.
  requireThat(users.length > 0 && isFixedPrompt(users.at(-1)) && users.filter(isFixedPrompt).length === 1
    && !normalized.input.some(item => item.role === 'assistant'), 'request_scope_rejected');
  return { model: MODEL, instructions: INSTRUCTIONS,
    input: [{ type: 'message', role: 'user', content: [{ type: 'input_text', text: PROMPT }] }],
    tools: [], tool_choice: 'none', parallel_tool_calls: false, store: false, stream: true,
    reasoning: { effort: 'low' } };
}
function authHeaders(req) {
  const headers = {};
  for (let i = 0; i < req.rawHeaders.length; i += 2) {
    const name = req.rawHeaders[i].toLowerCase();
    if (!['authorization', 'chatgpt-account-id'].includes(name)) continue;
    requireThat(!Object.hasOwn(headers, name), 'invalid_auth_headers');
    headers[name] = req.rawHeaders[i + 1];
  }
  requireThat(typeof headers.authorization === 'string' && headers.authorization.length <= 8192
    && /^Bearer [A-Za-z0-9._~+/=-]+$/.test(headers.authorization), 'invalid_auth_headers');
  requireThat(headers['chatgpt-account-id'] === undefined || /^[A-Za-z0-9_-]{1,200}$/.test(headers['chatgpt-account-id']), 'invalid_auth_headers');
  return headers;
}

// Injectable exchange is for in-memory tests only. The command-line entrypoint
// always uses exchangeTextOnly with the module-wide, irreversible live budget.
export function createProbeProxy(report, { exchange = exchangeTextOnly } = {}) {
  let armed = false;
  let attempted = false;
  const controller = new AbortController();
  const pending = new Set();
  const handle = async (req, res) => {
    report.requests_received++;
    if (report.request_observations.length < 8) report.request_observations.push({
      stage: report.stage, armed,
      method: ['GET', 'POST', 'HEAD', 'OPTIONS'].includes(req.method) ? req.method : 'other',
      route: req.url === '/v1/responses' ? 'responses_exact'
        : /^\/v1\/models(?:\?|$)/.test(req.url || '') ? 'models' : 'other',
      json: /^application\/json(?:;\s*charset=utf-8)?$/i.test(req.headers['content-type'] || ''),
      auth_present: typeof req.headers.authorization === 'string',
      account_header_present: typeof req.headers['chatgpt-account-id'] === 'string',
    });
    try {
      // The authenticated CLI asks this endpoint for model metadata at startup.
      // Refuse locally with an error, without inventing a catalog or forwarding
      // credentials. This route can neither arm generation nor consume its budget.
      if (req.method === 'GET' && /^\/v1\/models(?:\?[^\r\n]*)?$/.test(req.url || '')) {
        requireThat(!controller.signal.aborted && report.local_metadata_rejections < 8
          && !req.headers['content-encoding'] && !req.headers['transfer-encoding']
          && (req.headers['content-length'] === undefined || req.headers['content-length'] === '0'), 'metadata_request_rejected');
        report.local_metadata_rejections++;
        req.resume();
        res.writeHead(404, { 'content-type': 'application/json', connection: 'close' });
        res.end('{"error":{"message":"Model catalog unavailable in fixed probe.","type":"metadata_unavailable"}}');
        return;
      }
      requireThat(armed, 'probe_not_armed');
      requireThat(!attempted, 'upstream_budget_exhausted');
      requireThat(req.method === 'POST' && req.url === '/v1/responses', 'invalid_proxy_route');
      requireThat(!req.headers['content-encoding'] && /^application\/json(?:;\s*charset=utf-8)?$/i.test(req.headers['content-type'] || ''), 'invalid_proxy_content_type');
      requireThat(req.headers['content-length'] === undefined || (/^\d+$/.test(req.headers['content-length'])
        && Number(req.headers['content-length']) <= MAX_BODY), 'request_body_limit');
      const chunks = []; let size = 0;
      for await (const chunk of req) {
        size += chunk.length;
        requireThat(size <= MAX_BODY, 'request_body_limit');
        chunks.push(chunk);
      }
      let body;
      try { body = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks))); }
      catch { throw new ProbeError('invalid_request_json'); }
      report.request_shape = inspectFixedRequest(body);
      const fixed = fixedProbeBody(body);
      const headers = authHeaders(req);
      // Recheck after asynchronous body collection to close concurrency races.
      requireThat(armed && !attempted && (exchange !== exchangeTextOnly || !liveExchangeUsed), 'upstream_budget_exhausted');
      attempted = true;
      if (exchange === exchangeTextOnly) liveExchangeUsed = true;
      report.upstream_attempts++;
      report.authorization_present = true;
      report.account_header_present = headers['chatgpt-account-id'] !== undefined;
      const safe = await exchange(fixed, { model: MODEL, upstreamUrl: TARGET, headers, signal: controller.signal,
        timeoutMs: 30000, maxRequestBytes: MAX_BODY, maxMessages: 16, maxInputBytes: 256 * 1024,
        maxOutputBytes: 512 * 1024, maxEvents: 256, diagnoseRejectedResponse: true, diagnoseProtocolKeys: true });
      requireThat(armed && !controller.signal.aborted, 'probe_stopped');
      report.response_released = true;
      res.writeHead(200, { 'content-type': 'text/event-stream' });
      res.end(safe);
    } catch (error) {
      report.rejected_requests++;
      if (!report.code) report.code = safeCode(error);
      if (error instanceof TextGateTransportError && error.code === 'http_status'
        && Number.isInteger(error.httpStatus) && error.httpStatus >= 100 && error.httpStatus <= 599) report.http_status = error.httpStatus;
      if (error instanceof TextGateTransportError && error.responseMetadata) {
        // Rebuild the report from the transport's fixed vocabulary only.
        const m = error.responseMetadata;
        report.response_metadata = {
          http_status: Number.isInteger(m.http_status) && m.http_status >= 100 && m.http_status <= 599 ? m.http_status : null,
          media_type: ['text/event-stream', 'application/json', 'text/plain', 'text/html', 'application/octet-stream', 'missing'].includes(m.media_type) ? m.media_type : 'other',
          parameter_count: Number.isSafeInteger(m.parameter_count) && m.parameter_count >= 0 && m.parameter_count <= 1024 ? m.parameter_count : null,
          charset: ['absent', 'ambiguous', 'utf-8', 'utf8'].includes(m.charset) ? m.charset : 'other',
        };
      }
      if (error instanceof TextGateTransportError && error.code === 'response_rejected') {
        const codes = new Set(['unknown_field', 'invalid_shape', 'invalid_json', 'duplicate_json_key',
          'unsupported_content', 'unsupported_item', 'unknown_event', 'unsupported_event', 'unsupported_sse',
          'truncated_sse', 'invalid_terminal', 'event_after_terminal', 'input_limit', 'json_complexity_limit',
          'invalid_response_metadata', 'text_order_conflict', 'part_order_conflict', 'output_conflict',
          'text_conflict', 'item_order_conflict', 'item_id_conflict', 'response_id_conflict', 'sequence_conflict',
          'duplicate_item', 'duplicate_created', 'missing_created', 'invalid_progress', 'empty_message',
          'event_limit', 'output_limit', 'invalid_done_sentinel', 'event_type_conflict', 'duplicate_sse_event']);
        report.response_gate_code = codes.has(error.gateCode) ? error.gateCode : 'other';
        if (['unclassified', 'text_part', 'message', 'response', 'sse_response', 'sse_item', 'sse_content_part', 'sse_text_delta', 'sse_text_done'].includes(error.schemaLocation))
          report.response_gate_location = error.schemaLocation;
      }
      if (error instanceof TextGateTransportError && isRejectedTextResponseDiagnostic(error.responseDiagnostics)) {
        report.response_diagnostics = error.responseDiagnostics;
      }
      if (!res.destroyed) {
        res.writeHead(422, { 'content-type': 'application/json' });
        res.end('{"error":{"message":"Fixed text probe rejected exchange.","type":"text_gate_rejected"}}');
      }
    }
  };
  const server = createServer((req, res) => {
    const work = handle(req, res); pending.add(work);
    void work.finally(() => pending.delete(work));
  });
  server.requestTimeout = 10000;
  server.headersTimeout = 10000;
  return { server, arm() { requireThat(!controller.signal.aborted, 'probe_stopped'); armed = true; },
    disarm() { armed = false; controller.abort(); },
    async close() {
      armed = false; controller.abort(); server.closeAllConnections();
      if (server.listening) await new Promise(resolve => server.close(resolve));
      await Promise.allSettled([...pending]);
    } };
}

export function buildLaunch(executable, home, cwd, baseUrl, sourceEnv = process.env) {
  requireThat(/^http:\/\/127\.0\.0\.1:[1-9][0-9]{0,4}\/v1$/.test(baseUrl)
    && Number(new URL(baseUrl).port) <= 65535, 'invalid_proxy_target');
  const overrides = { ...restrictions(false), model_provider: PROVIDER, 'agents.enabled': false,
    cli_auth_credentials_store: 'file', 'history.persistence': 'none' };
  const args = ['app-server', '--listen', 'stdio://'];
  for (const [key, value] of Object.entries(overrides)) args.push('-c', `${key}=${typeof value === 'object' && !Array.isArray(value) ? '{}' : JSON.stringify(value)}`);
  args.push('-c', `model_providers.${PROVIDER}={name="Fixed text probe",base_url="${baseUrl}",wire_api="responses",requires_openai_auth=true,request_max_retries=0,stream_max_retries=0,supports_websockets=false}`);
  const env = Object.fromEntries(['SystemRoot', 'SYSTEMROOT', 'WINDIR', 'COMSPEC', 'PATHEXT', 'PATH']
    .filter(key => sourceEnv[key]).map(key => [key, sourceEnv[key]]));
  Object.assign(env, { CODEX_HOME: home, HOME: home, USERPROFILE: home, APPDATA: home, LOCALAPPDATA: home, TEMP: home, TMP: home });
  return { commandSpec: { command: executable, args }, cwd, env, experimentalApi: true, requestTimeoutMs: 10000 };
}
export function inspectProbeConfig(config, requirements, baseUrl) {
  const c = config?.config || {}; const provider = c.model_providers?.[PROVIDER];
  const checks = {
    shape: !!config?.config && Array.isArray(config?.layers),
    requirements_empty: requirements == null || Object.keys(requirements).length === 0,
    layers: Array.isArray(config?.layers) && config.layers.every(layer =>
      (layer.name?.type === 'system' && Object.keys(layer.config || {}).length === 0)
      || (['sessionFlags', 'user'].includes(layer.name?.type)
        && (layer.name.type !== 'user' || Object.keys(layer.config || {}).length === 0))),
    model: c.model === MODEL && c.model_provider === PROVIDER,
    agents_disabled: c.agents?.enabled === false,
    approval: c.approval_policy === 'never', sandbox: c.sandbox_mode === 'read-only',
    web_disabled: c.web_search === 'disabled', project_docs_disabled: c.project_doc_max_bytes === 0,
    notify_disabled: !c.notify?.length, mcp_empty: !Object.keys(c.mcp_servers || {}).length,
    hooks_empty: Object.values(c.hooks || {}).every(value => Array.isArray(value) && value.length === 0),
    provider: provider?.base_url === baseUrl && provider.requires_openai_auth === true
    && provider.wire_api === 'responses' && provider.request_max_retries === 0
    && provider.stream_max_retries === 0 && provider.supports_websockets === false
    && !provider.env_key && !provider.experimental_bearer_token && emptyMap(provider.http_headers)
    && emptyMap(provider.env_http_headers) && emptyMap(provider.query_params),
  };
  for (const [key, value] of Object.entries(restrictions(false))) {
    if (key.startsWith('features.') && typeof value === 'boolean' && !key.startsWith('features.code_mode.'))
      checks[key] = c.features?.[key.slice(9)] === value;
  }
  return checks;
}
export function assertProbeConfig(config, requirements, baseUrl) {
  requireThat(Object.values(inspectProbeConfig(config, requirements, baseUrl)).every(Boolean), 'config_rejected');
}

export async function runProbeSession(client, proxy, report, { cwd, baseUrl, inspectOnly = false }) {
  client.on('serverRequest', request => {
    report.server_requests_rejected++;
    report.code ||= 'server_request_rejected';
    proxy.disarm();
    request.respondError({ code: -32601, message: 'Fixed text probe rejects all host requests.' });
  });
  let text = ''; let activeThread = null;
  client.on('notification', ({ message }) => {
    if (message.method === 'item/agentMessage/delta' && message.params?.threadId === activeThread) {
      const delta = message.params?.delta;
      if (typeof delta !== 'string' || text.length + delta.length > 128) { text = ''; report.code ||= 'text_scope_rejected'; proxy.disarm(); }
      else text += delta;
    }
  });
  try {
    report.stage = 'startup';
    await client.start();
    report.stage = 'account_read';
    const account = await client.readAccount();
    requireThat(account.requiresOpenaiAuth === true && account.account?.type === 'chatgpt', 'chatgpt_login_required');
    report.chatgpt_login_present = true;
    report.stage = 'config_read';
    const config = await client.request('config/read', { cwd, includeLayers: true });
    const requirements = await client.request('configRequirements/read', {});
    report.config_checks = inspectProbeConfig(config, requirements.requirements, baseUrl);
    if (inspectOnly) { report.status = 'inspection_complete'; return report; }
    assertProbeConfig(config, requirements.requirements, baseUrl);
    requireThat(!report.code, 'probe_session_rejected');
    report.stage = 'thread_start';
    const started = await client.startThread({ cwd, model: MODEL, modelProvider: PROVIDER,
      approvalPolicy: 'never', sandbox: 'read-only', ephemeral: true, dynamicTools: [],
      environments: [], runtimeWorkspaceRoots: [], selectedCapabilityRoots: [], baseInstructions: INSTRUCTIONS });
    requireThat(started.modelProvider === PROVIDER && started.model === MODEL
      && typeof started.thread?.id === 'string' && !report.code, 'thread_scope_rejected');
    activeThread = started.thread.id;
    const sequence = client.notificationSequence;
    report.stage = 'turn_start';
    proxy.arm();
    const turn = await client.startTurn(activeThread, PROMPT, { environments: [] });
    requireThat(typeof turn.turn?.id === 'string', 'turn_scope_rejected');
    report.stage = 'turn_wait';
    const terminal = await client.waitForNotification('turn/completed', event => event.params?.threadId === activeThread
      && event.params?.turn?.id === turn.turn.id, { afterSequence: sequence, timeoutMs: 40000 });
    report.turn_completed = terminal.params.turn.status === 'completed';
    report.fixed_text_observed = text === 'P6_TEXT_GATE_OK';
    requireThat(report.turn_completed && report.fixed_text_observed && report.response_released && !report.code, 'fixed_text_not_confirmed');
    report.status = 'fixed_text_confirmed';
  } catch (error) { report.code ||= safeCode(error); report.status = 'failed'; }
  finally {
    proxy.disarm();
    try { report.process_close_observed = (await client.stop()).process_close_observed === true; }
    catch { report.code = 'stop_close_unconfirmed'; }
    await proxy.close();
    if (!report.process_close_observed) report.code = 'stop_close_unconfirmed';
    if (report.code) report.status = 'failed';
  }
  return report;
}

export async function main(argv = process.argv.slice(2)) {
  const report = initialReport();
  let reportPath;
  try {
    requireThat(argv.length === 2 || argv.length === 4, 'explicit_live_required');
    requireThat(['--live', '--inspect'].includes(argv[0]) && path.isAbsolute(argv[1]), 'explicit_live_required');
    if (argv.length === 4) {
      requireThat(argv[2] === '--report' && path.isAbsolute(argv[3]), 'invalid_report_path');
      reportPath = argv[3];
    }
    const executable = argv[1];
    requireThat(createHash('sha256').update(readFileSync(executable)).digest('hex') === TEXT_GATE_CLI_SHA256, 'runtime_pin_mismatch');
    const directories = { localAppData: process.env.LOCALAPPDATA,
      repository: path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..'),
      originalHomes: [process.env.CODEX_HOME, process.env.USERPROFILE ? path.join(process.env.USERPROFILE, '.codex') : null] };
    const { home, cwd } = prepareDedicatedHome(directories);
    requireThat(readdirSync(cwd).length === 0, 'workspace_not_empty');
    const proxy = createProbeProxy(report);
    try {
      await new Promise((resolve, reject) => { proxy.server.once('error', reject); proxy.server.listen(0, '127.0.0.1', resolve); });
      const baseUrl = `http://127.0.0.1:${proxy.server.address().port}/v1`;
      const client = new CodexAppServerClient(buildLaunch(executable, home, cwd, baseUrl));
      prepareDedicatedHome(directories);
      await runProbeSession(client, proxy, report, { cwd, baseUrl, inspectOnly: argv[0] === '--inspect' });
    } finally { await proxy.close(); }
  } catch (error) { report.status = 'failed'; report.code ||= safeCode(error); }
  if (reportPath) {
    // Exclusive creation avoids overwriting any existing user artifact.
    try { writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, { flag: 'wx', mode: 0o600 }); }
    catch { report.status = 'failed'; report.code = 'report_write_failed'; }
  }
  console.log(JSON.stringify(report));
  process.exitCode = ['fixed_text_confirmed', 'inspection_complete'].includes(report.status) ? 0 : 2;
  return report;
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) await main();
