// Manual synthetic-only runtime behavior probe. No account/profile/real model use.
import { createServer } from 'node:http';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { CodexAppServerClient } from './codex_app_server_client.mjs';
import { inspectCompiledToolCatalog } from './workbench_text_only_probe_contract.mjs';

export const EXPECTED_SHA256 = 'e5aa76d19c7c94e2e9ef9b707d590206a73ac0e97c8ddc8382181242494bef75';
export const question = { questions: [{ id: 'synthetic_choice', header: 'Probe', question: 'Select the synthetic marker.',
  options: [{ label: 'Alpha (Recommended)', description: 'Return alpha.' }, { label: 'Beta', description: 'Return beta.' }] }] };
export function toolCall(namespace, name, value, id = 'probe_call') {
  return { type: name === 'exec' ? 'custom_tool_call' : 'function_call', id: `item_${id}`, call_id: id,
    ...(namespace ? { namespace } : {}), name,
    ...(name === 'exec' ? { input: value } : { arguments: JSON.stringify(value) }), status: 'completed' };
}
export function outputFor(body, callId) {
  return (body.input || []).filter(item => ['function_call_output', 'custom_tool_call_output'].includes(item.type)
    && item.call_id === callId);
}
export function classifyOutput(outputs) {
  const value = JSON.stringify(outputs);
  if (!outputs.length) return 'insufficient_evidence';
  if (/code.mode host is disabled|Code Mode is unavailable|unavailable in Default mode/i.test(value)) return 'explicit_runtime_rejection';
  if (/SyntaxError|Unexpected token|parse|invalid (?:json|arguments)/i.test(value)) return 'parse_or_argument_error';
  if (/unknown tool|unsupported (?:tool|call)|not found/i.test(value)) return 'dispatch_error';
  return 'observed_output_requires_review';
}
export function classifyCase(report) {
  const first = report.outputs.find(item => item.call_id === 'probe_call');
  if (report.name === 'dynamic_positive' && report.positive_control_dispatched && first?.output === 'SYNTHETIC_ECHO_42') return 'actual_tool_execution';
  if (report.name === 'excluded_list_agents' && typeof first?.output === 'string') {
    try {
      const parsed = JSON.parse(first.output);
      if (Array.isArray(parsed.agents) && parsed.agents.some(a => a.agent_name === '/root' && a.agent_status === 'running')) return 'actual_tool_execution';
    } catch { /* Unrecognized data remains insufficient evidence. */ }
  }
  if (report.name === 'enabled_exec_wait_control' && report.real_cell_id) {
    const waited = report.outputs.find(item => item.call_id === 'probe_wait');
    if (Array.isArray(waited?.output) && waited.output.some(v => v.text === '42')
        && waited.output.some(v => v.text?.startsWith('Script completed'))) return 'actual_tool_execution';
  }
  return classifyOutput(report.outputs);
}
export function restrictions(hostEnabled = false) {
  const disabled = ['shell_tool', 'shell_snapshot', 'unified_exec', 'apply_patch_freeform', 'apps', 'plugins',
    'remote_plugin', 'multi_agent', 'js_repl', 'js_repl_tools_only', 'browser_use', 'computer_use', 'image_generation',
    'imagegen', 'hooks', 'memories', 'memory_tool', 'scheduled_tasks', 'workspace_dependencies',
    'skill_mcp_dependency_install', 'skill_env_var_dependency_prompt', 'enable_request_compression',
    'responses_websockets', 'responses_websockets_v2', 'code_mode_only', 'multi_agent_v2',
    'default_mode_request_user_input', 'goals', 'sleep_tool', 'skill_search', 'tool_suggest',
    'request_permissions_tool', 'browser_use_external', 'browser_use_full_cdp_access', 'view_image'];
  return { model: 'gpt-5.6-sol', model_provider: 'synthetic_probe', approval_policy: 'never', sandbox_mode: 'read-only',
    web_search: 'disabled', project_doc_max_bytes: 0, notify: [], mcp_servers: {}, hooks: {},
    'tools.view_image': false, 'analytics.enabled': false,
    ...Object.fromEntries(disabled.map(name => [`features.${name}`, false])),
    'features.code_mode_host': hostEnabled, 'features.code_mode.enabled': hostEnabled,
    'features.skip_host_skill_discovery': true,
    'features.code_mode.excluded_tool_namespaces': ['functions', 'collaboration', 'skills', 'clock', 'web'] };
}
export function assertIsolation(config, requirements, providerUrl) {
  const url = new URL(providerUrl);
  if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' || !url.port || url.pathname !== '/v1') throw new Error('Non-loopback provider rejected.');
  if (requirements && Object.keys(requirements).length) throw new Error('Managed requirements present.');
  for (const layer of config.layers || []) {
    if (layer.name?.type === 'system' && Object.keys(layer.config || {}).length === 0) continue;
    if (!['sessionFlags', 'user'].includes(layer.name?.type)) throw new Error('Unexpected config layer.');
    if (layer.name?.type === 'user' && Object.keys(layer.config || {}).length) throw new Error('Nonempty user configuration.');
  }
  const c = config.config;
  if (c.model_provider !== 'synthetic_probe' || c.model_providers?.synthetic_probe?.base_url !== providerUrl
      || c.model_providers?.synthetic_probe?.requires_openai_auth !== false) throw new Error('Provider isolation mismatch.');
  if (Object.keys(c.mcp_servers || {}).length || Object.values(c.hooks || {}).some(v => !Array.isArray(v) || v.length)) throw new Error('Unexpected MCP/hooks.');
}
function sendResponse(res, item, index) {
  const response = { id: `resp_${index}`, status: 'completed', output: [item], usage: { input_tokens: 1, output_tokens: 1, total_tokens: 2 } };
  res.writeHead(200, { 'content-type': 'text/event-stream' });
  for (const event of [
    { type: 'response.created', response: { ...response, status: 'in_progress', output: [] } },
    { type: 'response.output_item.added', output_index: 0, item: { ...item, status: 'in_progress' } },
    { type: 'response.output_item.done', output_index: 0, item },
    { type: 'response.completed', response },
  ]) res.write(`event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`);
  res.end();
}
function finalItem() { return { id: 'msg_final', type: 'message', role: 'assistant', status: 'completed',
  content: [{ type: 'output_text', text: 'SYNTHETIC_FINISHED', annotations: [] }] }; }

async function runCase(executable, root, name, { hostEnabled = false, dynamicControl = false, agentsEnabled = true, firstCall, followup } = {}) {
  const caseRoot = path.join(root, name); mkdirSync(caseRoot);
  const probeHome = path.join(caseRoot, 'home'); const probeCwd = path.join(caseRoot, 'work');
  mkdirSync(probeHome); mkdirSync(probeCwd);
  const report = { name, host_enabled: hostEnabled, calls: [], requests: [], server_requests: [], notifications: [], outputs: [],
    production_isolation_passed: false };
  let requestCount = 0;
  const server = createServer(async (req, res) => {
    try {
      const parts = []; let size = 0;
      for await (const chunk of req) { size += chunk.length; if (size > 2_000_000) throw new Error('Request too large.'); parts.push(chunk); }
      if (req.method !== 'POST' || req.url !== '/v1/responses' || req.headers.authorization || req.headers['content-encoding']) throw new Error('Unexpected request or auth header.');
      const body = JSON.parse(Buffer.concat(parts).toString('utf8'));
      if (body.model !== 'gpt-5.6-sol') throw new Error('Unexpected model.');
      if (++requestCount > 5) throw new Error('Request budget exceeded.');
      writeFileSync(path.join(caseRoot, `request-${requestCount}.json`), JSON.stringify(body, null, 2));
      report.requests.push({ index: requestCount, method: req.method, url: req.url, model: body.model, ...inspectCompiledToolCatalog(body) });
      const outputs = (body.input || []).filter(item => ['function_call_output', 'custom_tool_call_output'].includes(item.type));
      report.outputs = outputs;
      let item = finalItem();
      if (requestCount === 1) item = firstCall;
      else if (requestCount === 2 && followup) item = followup(body, report) || item;
      if (item.call_id) report.calls.push(item);
      sendResponse(res, item, requestCount);
    } catch (error) { report.provider_error = error.message; res.writeHead(400); res.end('Synthetic provider rejected request.'); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}/v1`;
  const overrides = restrictions(hostEnabled);
  if (!agentsEnabled) overrides['agents.enabled'] = false;
  const args = ['app-server', '--listen', 'stdio://'];
  for (const [key, value] of Object.entries(overrides)) args.push('-c', `${key}=${typeof value === 'object' && !Array.isArray(value) ? '{}' : JSON.stringify(value)}`);
  args.push('-c', `model_providers.synthetic_probe={name="Synthetic loopback only",base_url="${baseUrl}",wire_api="responses",requires_openai_auth=false,request_max_retries=0,stream_max_retries=0}`);
  const childEnv = Object.fromEntries(['SystemRoot', 'SYSTEMROOT', 'WINDIR', 'COMSPEC', 'PATHEXT', 'PATH']
    .filter(key => process.env[key]).map(key => [key, process.env[key]]));
  Object.assign(childEnv, { CODEX_HOME: probeHome, HOME: probeHome, USERPROFILE: probeHome, APPDATA: probeHome,
    LOCALAPPDATA: probeHome, TEMP: caseRoot, TMP: caseRoot });
  report.child_environment_keys = Object.keys(childEnv); report.overrides = overrides;
  const client = new CodexAppServerClient({ commandSpec: { command: executable, args }, cwd: probeCwd,
    env: childEnv, experimentalApi: true, requestTimeoutMs: 10_000 });
  client.on('notification', ({ message }) => report.notifications.push(message));
  client.on('serverRequest', request => {
    report.server_requests.push({ method: request.method, params: request.params });
    if (dynamicControl && request.method === 'item/tool/call' && request.params.tool === 'synthetic_echo'
        && request.params.arguments?.value === 42) {
      report.positive_control_dispatched = true;
      request.respond({ success: true, contentItems: [{ type: 'inputText', text: 'SYNTHETIC_ECHO_42' }] });
    } else request.respondError({ code: -32601, message: 'Synthetic harness rejects unplanned client requests.' });
  });
  let threadId, turnId, ownedChild;
  try {
    report.initialize = await client.start(); ownedChild = client.child; report.owned_pid = ownedChild.pid;
    report.config = await client.request('config/read', { cwd: probeCwd, includeLayers: true });
    report.requirements = await client.request('configRequirements/read', {});
    assertIsolation(report.config, report.requirements.requirements, baseUrl);
    if (!agentsEnabled && report.config.config.agents?.enabled !== false)
      throw new Error('Requested agents.enabled=false was not confirmed.');
    const started = await client.startThread({ cwd: probeCwd, model: 'gpt-5.6-sol', modelProvider: 'synthetic_probe',
      approvalPolicy: 'never', sandbox: 'read-only', ephemeral: true, environments: [], runtimeWorkspaceRoots: [], selectedCapabilityRoots: [],
      dynamicTools: dynamicControl ? [{ type: 'function', name: 'synthetic_echo', description: 'Return the synthetic integer marker.',
        inputSchema: { type: 'object', properties: { value: { type: 'integer' } }, required: ['value'], additionalProperties: false } }] : [],
      baseInstructions: 'Synthetic harness. Only fixed synthetic tool calls and fixed text are supplied.' });
    if (started.modelProvider !== 'synthetic_probe' || started.model !== 'gpt-5.6-sol') throw new Error('Thread provider mismatch.');
    threadId = started.thread.id; report.thread = started;
    const afterSequence = client.notificationSequence;
    const turn = await client.startTurn(threadId, 'Execute the fixed synthetic probe.', { environments: [] });
    turnId = turn.turn.id;
    const terminal = await client.waitForNotification('turn/completed', m => m.params?.threadId === threadId && m.params?.turn?.id === turnId,
      { afterSequence, timeoutMs: 20_000 });
    report.turn_terminal = terminal.params.turn;
  } catch (error) {
    report.error = error.message;
    if (threadId && turnId) {
      try {
        await client.interruptTurn(threadId, turnId);
        report.interrupt_acknowledged = true;
        const terminal = await client.waitForNotification('turn/completed', m => m.params?.threadId === threadId && m.params?.turn?.id === turnId, { timeoutMs: 5000 });
        report.turn_terminal = terminal.params.turn;
      } catch (stopError) { report.stop_error = stopError.message; }
    }
  } finally {
    await client.stop();
    report.process_exit_confirmed = ownedChild ? ownedChild.exitCode !== null || ownedChild.signalCode !== null : true;
    server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
    report.stderr = client.stderrLines;
    report.classification = classifyCase(report);
    writeFileSync(path.join(caseRoot, 'report.json'), JSON.stringify(report, null, 2));
  }
  return report;
}

export async function main(executable, variant = 'baseline') {
  if (!['baseline', 'agents-disabled'].includes(variant)) throw new Error('Unknown synthetic behavior variant.');
  if (!executable || !path.isAbsolute(executable)) throw new Error('Pass the pinned absolute Codex executable.');
  const fingerprint = createHash('sha256').update(readFileSync(executable)).digest('hex');
  if (fingerprint !== EXPECTED_SHA256) throw new Error('Executable fingerprint changed; review before running.');
  const root = mkdtempSync(path.join(tmpdir(), 'hereiam-tool-behavior-probe-'));
  const cases = variant === 'agents-disabled' ? [
    ['dynamic_positive', { agentsEnabled: false, dynamicControl: true, firstCall: toolCall(null, 'synthetic_echo', { value: 42 }) }],
    ['excluded_exec', { agentsEnabled: false, firstCall: toolCall('functions', 'exec', 'text(6 * 7);') }],
    ['agents_disabled_list_agents', { agentsEnabled: false, firstCall: toolCall('collaboration', 'list_agents', {}) }],
    ['excluded_request_user_input', { agentsEnabled: false, firstCall: toolCall('functions', 'request_user_input', question) }],
  ] : [
    ['dynamic_positive', { dynamicControl: true, firstCall: toolCall(null, 'synthetic_echo', { value: 42 }) }],
    ['excluded_exec', { firstCall: toolCall('functions', 'exec', 'text(6 * 7);') }],
    ['excluded_list_agents', { firstCall: toolCall('collaboration', 'list_agents', {}) }],
    ['excluded_request_user_input', { firstCall: toolCall('functions', 'request_user_input', question) }],
    ['enabled_exec_wait_control', { hostEnabled: true,
      firstCall: toolCall('functions', 'exec', '// @exec: {"yield_time_ms": 1}\nawait new Promise(resolve => setTimeout(resolve, 200)); text(6 * 7);'),
      followup: (body, report) => {
        const match = JSON.stringify(outputFor(body, 'probe_call')).match(/Script running with cell ID ([A-Za-z0-9_-]+)/);
        if (!match) { report.wait_not_attempted = 'No real yielded cell_id; fake IDs are not evidence.'; return null; }
        report.real_cell_id = match[1];
        return toolCall('functions', 'wait', { cell_id: match[1], yield_time_ms: 1000 }, 'probe_wait');
      } }],
    ['enabled_exec_parse_negative', { hostEnabled: true, firstCall: toolCall('functions', 'exec', 'text(;') }],
  ];
  const report = { schema_version: 1, executable_sha256: fingerprint, variant, synthetic_only: true, production_isolation_passed: false, cases: [] };
  for (const [name, options] of cases) {
    const result = await runCase(executable, root, name, options); report.cases.push(result);
    console.log(JSON.stringify({ case: name, classification: result.classification, positive_control_dispatched: result.positive_control_dispatched,
      outputs: result.outputs, error: result.error, terminal: result.turn_terminal?.status, process_exit_confirmed: result.process_exit_confirmed }));
    if (result.error || result.provider_error || !result.process_exit_confirmed) break;
  }
  report.harness_positive_control_passed = report.cases.some(c => c.name === 'dynamic_positive' && c.positive_control_dispatched
    && JSON.stringify(c.outputs).includes('SYNTHETIC_ECHO_42') && c.turn_terminal?.status === 'completed');
  const expected = { dynamic_positive: 'actual_tool_execution', excluded_exec: 'explicit_runtime_rejection',
    excluded_list_agents: 'actual_tool_execution', excluded_request_user_input: 'explicit_runtime_rejection',
    enabled_exec_wait_control: 'actual_tool_execution', enabled_exec_parse_negative: 'parse_or_argument_error' };
  if (variant === 'agents-disabled') expected.agents_disabled_list_agents = 'dispatch_error';
  report.behavior_checks_passed = report.cases.length === cases.length && report.cases.every(c =>
    c.classification === expected[c.name] && c.turn_terminal?.status === 'completed'
    && !c.error && !c.provider_error && c.process_exit_confirmed);
  report.unattempted = ['excluded wait: a valid live cell cannot be fabricated if exec is denied',
    'collaboration spawn/followup/send/interrupt/wait: child inheritance unverified; no synthetic child created'];
  writeFileSync(path.join(root, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ report_path: path.join(root, 'report.json'), harness_positive_control_passed: report.harness_positive_control_passed,
    behavior_checks_passed: report.behavior_checks_passed, production_isolation_passed: false }));
  process.exitCode = report.harness_positive_control_passed && report.behavior_checks_passed ? 0 : 2;
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href)
  await main(process.argv[2], process.argv.find(arg => arg.startsWith('--variant='))?.slice('--variant='.length) || 'baseline');
