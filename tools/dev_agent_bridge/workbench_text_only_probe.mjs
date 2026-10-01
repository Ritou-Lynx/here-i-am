// Manual, synthetic-only capability probe. Never uses the logged-in provider.
import { createServer } from 'node:http';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { CodexAppServerClient } from './codex_app_server_client.mjs';
import { hasCompiledTool, inspectCompiledToolCatalog } from './workbench_text_only_probe_contract.mjs';
import { assertIsolation, EXPECTED_SHA256 } from './workbench_tool_behavior_probe.mjs';

const executable = process.argv[2];
const control = process.argv.includes('--catalog-control');
const variant = process.argv.find(arg => arg.startsWith('--variant='))?.slice('--variant='.length) || 'baseline';
if (!['baseline', 'strict', 'excluded', 'code-mode-excluded', 'agents-disabled'].includes(variant)) throw new Error('Unknown synthetic probe variant.');
if (!executable || !path.isAbsolute(executable)) throw new Error('Pass an absolute Codex executable path.');
const executableSha256 = createHash('sha256').update(readFileSync(executable)).digest('hex');
if (executableSha256 !== EXPECTED_SHA256) throw new Error('Executable fingerprint changed; review before running.');
const probeRoot = mkdtempSync(path.join(tmpdir(), 'hereiam-text-only-probe-'));
const probeHome = path.join(probeRoot, 'home');
const probeCwd = path.join(probeRoot, 'work');
mkdirSync(probeHome); mkdirSync(probeCwd);
const disabledFeatures = [
  'shell_tool', 'shell_snapshot', 'unified_exec', 'apply_patch_freeform',
  'apps', 'plugins', 'remote_plugin', 'multi_agent', 'js_repl', 'js_repl_tools_only',
  'browser_use', 'computer_use', 'image_generation', 'imagegen', 'hooks',
  'memories', 'memory_tool', 'scheduled_tasks', 'workspace_dependencies',
  'skill_mcp_dependency_install', 'skill_env_var_dependency_prompt',
  'enable_request_compression', 'responses_websockets', 'responses_websockets_v2',
];
const overrides = {
  model: 'gpt-5.6-sol', model_provider: 'synthetic_probe',
  approval_policy: 'never', sandbox_mode: 'read-only', web_search: 'disabled',
  project_doc_max_bytes: 0, notify: [], mcp_servers: {}, hooks: {},
  'tools.view_image': false, 'analytics.enabled': false,
  ...Object.fromEntries(disabledFeatures.map(name => [`features.${name}`, false])),
};
if (variant !== 'baseline') {
  for (const name of ['code_mode_host', 'code_mode_only', 'multi_agent_v2',
    'default_mode_request_user_input', 'goals', 'sleep_tool', 'skill_search',
    'tool_suggest', 'request_permissions_tool', 'browser_use_external',
    'browser_use_full_cdp_access', 'view_image']) overrides[`features.${name}`] = false;
  overrides['features.code_mode.enabled'] = false;
  overrides['features.skip_host_skill_discovery'] = true;
}
if (['excluded', 'code-mode-excluded', 'agents-disabled'].includes(variant)) {
  overrides['features.code_mode.excluded_tool_namespaces'] = ['functions', 'collaboration', 'skills', 'clock', 'web'];
}
// This documented setting is distinct from the older feature flags tested in R3.
if (variant === 'agents-disabled') overrides['agents.enabled'] = false;
if (variant === 'code-mode-excluded') {
  overrides['features.code_mode.enabled'] = true;
  overrides['features.code_mode_host'] = true;
}
const report = { schema_version: 1, profile: 'workbench_text_only_v1',
  executable_sha256: executableSha256,
  synthetic_only: true, variant, catalog_control: control, requests: [], server_requests: [], diagnostics: [], passed: false };
const server = createServer(async (req, res) => {
  const buffers = []; for await (const chunk of req) buffers.push(chunk);
  const raw = Buffer.concat(buffers).toString('utf8');
  let body; try { body = JSON.parse(raw); } catch { body = {}; }
  writeFileSync(path.join(probeRoot, 'synthetic-request.json'), JSON.stringify(body, null, 2));
  let inspection;
  try { inspection = inspectCompiledToolCatalog(body); }
  catch (error) { inspection = { no_tools: false, error: error.message }; }
  report.requests.push({ method: req.method, url: req.url,
    encoding: req.headers['content-encoding'] || null,
    ...inspection, synthetic_control_present: hasCompiledTool(inspection, 'synthetic_noop'),
    tools_field_present: Object.hasOwn(body, 'tools'), model: body.model ?? null });
  // A fixed text response cannot induce any tool execution.
  res.writeHead(200, { 'content-type': 'text/event-stream' });
  const item = { id: 'msg_probe', type: 'message', role: 'assistant', status: 'completed',
    content: [{ type: 'output_text', text: 'SYNTHETIC_TEXT_ONLY_OK', annotations: [] }] };
  for (const event of [
    { type: 'response.created', response: { id: 'resp_probe', status: 'in_progress', output: [] } },
    { type: 'response.output_item.added', output_index: 0, item: { ...item, status: 'in_progress', content: [] } },
    { type: 'response.output_text.delta', item_id: item.id, output_index: 0, content_index: 0, delta: 'SYNTHETIC_TEXT_ONLY_OK' },
    { type: 'response.output_item.done', output_index: 0, item },
    { type: 'response.completed', response: { id: 'resp_probe', status: 'completed', output: [item], usage: { input_tokens: 1, output_tokens: 1, total_tokens: 2 } } },
  ]) res.write(`event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`);
  res.end();
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const provider = { name: 'Synthetic loopback only', base_url: `http://127.0.0.1:${server.address().port}/v1`,
  wire_api: 'responses', requires_openai_auth: false, request_max_retries: 0, stream_max_retries: 0 };
// JSON is valid for these TOML scalar/array values; inline provider table is explicit.
const args = ['app-server', '--listen', 'stdio://'];
for (const [key, value] of Object.entries(overrides)) {
  args.push('-c', `${key}=${typeof value === 'object' && !Array.isArray(value) ? '{}' : JSON.stringify(value)}`);
}
args.push('-c', `model_providers.synthetic_probe={name="Synthetic loopback only",base_url="${provider.base_url}",wire_api="responses",requires_openai_auth=false,request_max_retries=0,stream_max_retries=0}`);
// Allow only OS runtime variables. No API tokens, real profile, proxies or Codex session vars.
const childEnv = Object.fromEntries(['SystemRoot', 'SYSTEMROOT', 'WINDIR', 'COMSPEC', 'PATHEXT', 'PATH']
  .filter(key => process.env[key]).map(key => [key, process.env[key]]));
Object.assign(childEnv, { CODEX_HOME: probeHome, HOME: probeHome, USERPROFILE: probeHome,
  APPDATA: probeHome, LOCALAPPDATA: probeHome, TEMP: probeRoot, TMP: probeRoot });
const client = new CodexAppServerClient({ commandSpec: { command: executable, args },
  cwd: probeCwd, env: childEnv, experimentalApi: true, requestTimeoutMs: 15_000 });
client.on('serverRequest', request => {
  report.server_requests.push(request.method);
  request.respondError({ code: -32601, message: 'Synthetic probe rejects all server requests.' });
});
client.on('notification', ({ message }) => {
  if (['error', 'warning'].includes(message.method)) report.diagnostics.push(message);
});
try {
  report.initialize = await client.start();
  const config = await client.request('config/read', { cwd: probeCwd, includeLayers: true });
  report.config = config;
  report.requirements = await client.request('configRequirements/read', {});
  assertIsolation(config, report.requirements.requirements, provider.base_url);
  if (variant === 'agents-disabled' && config.config.agents?.enabled !== false)
    throw new Error('Requested agents.enabled=false was not confirmed; no thread created.');
  const requirements = report.requirements.requirements;
  if (requirements && Object.keys(requirements).length) throw new Error('Managed requirements present; no thread created.');
  for (const layer of config.layers || []) {
    if (layer.name?.type === 'system' && Object.keys(layer.config || {}).length === 0) continue;
    if (!['sessionFlags', 'user'].includes(layer.name?.type)) throw new Error(`Unexpected config layer ${JSON.stringify(layer.name)}; no thread created.`);
  }
  if (Object.keys(config.config.mcp_servers || {}).length || Object.values(config.config.hooks || {}).some(value => !Array.isArray(value) || value.length))
    throw new Error('Unexpected MCP or hooks; no thread created.');
  const started = await client.startThread({ cwd: probeCwd, model: overrides.model,
    modelProvider: 'synthetic_probe', approvalPolicy: 'never', sandbox: 'read-only',
    ephemeral: true, environments: [], runtimeWorkspaceRoots: [], selectedCapabilityRoots: [],
    dynamicTools: control ? [{ type: 'function', name: 'synthetic_noop',
      description: 'Synthetic catalog detection control. Never execute.', inputSchema: { type: 'object', properties: {} } }] : [],
    baseInstructions: 'Produce synthetic text only.' });
  report.thread = { model: started.model, modelProvider: started.modelProvider,
    approvalPolicy: started.approvalPolicy, sandbox: started.sandbox };
  report.turn = await client.runTurn(started.thread.id, 'Return SYNTHETIC_TEXT_ONLY_OK.', { environments: [] }, { timeoutMs: 15_000 });
  report.passed = !control && report.requests.length > 0 && report.requests.every(r => r.no_tools === true)
    && report.server_requests.length === 0 && report.turn.completed.params.turn.status === 'completed';
  report.control_detected = control && report.requests.some(r => r.synthetic_control_present && !r.no_tools);
} catch (error) { report.error = error.message; }
finally {
  await client.stop();
  server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
  report.stderr = client.stderrLines;
  writeFileSync(path.join(probeRoot, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ report_path: path.join(probeRoot, 'report.json'), passed: report.passed,
    variant,
    control_detected: report.control_detected, error: report.error,
    requests: report.requests, diagnostics: report.diagnostics, stderr: report.stderr }, null, 2));
  process.exitCode = report.passed || report.control_detected ? 0 : 2;
}
