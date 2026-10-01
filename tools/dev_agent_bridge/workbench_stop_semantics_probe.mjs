// Synthetic-only App Server stop-semantics probe. It never reads real auth or
// contacts a model provider. Reports distinguish JSON-RPC acknowledgement,
// matching provider terminal event, stream socket close, and local process close.
import { createServer } from 'node:http';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { CodexAppServerClient } from './codex_app_server_client.mjs';

const executable = process.argv[2];
if (!executable || !path.isAbsolute(executable)) throw new Error('Pass an absolute Codex executable path.');
const EXPECTED_CLI_SHA256 = 'e5aa76d19c7c94e2e9ef9b707d590206a73ac0e97c8ddc8382181242494bef75';
const executableSha256 = createHash('sha256').update(readFileSync(executable)).digest('hex');
if (executableSha256 !== EXPECTED_CLI_SHA256) throw new Error('Unexpected Codex executable SHA-256; synthetic probe refused to start.');
const root = mkdtempSync(path.join(tmpdir(), 'hereiam-stop-semantics-'));
const home = path.join(root, 'home');
const cwd = path.join(root, 'cwd');
mkdirSync(home); mkdirSync(cwd);
const now = () => Date.now();
const report = {
  schema_version: 1, synthetic_only: true,
  executable_sha256: executableSha256,
  phases: {}, notifications: [], provider: { requests: [], connections: [] },
  process: { close_observed_at: null, stopped_at: null },
};
const streams = new Map();
const markerFrom = (body) => JSON.stringify(body).match(/STOP_PROBE_(INTERRUPT|NORMAL|DISCONNECT)/)?.[0] || 'UNKNOWN';
const emit = (res, type, payload) => res.write(`event: ${type}\ndata: ${JSON.stringify({ type, ...payload })}\n\n`);
const completedItem = (text) => ({ id: `msg_${text}`, type: 'message', role: 'assistant', status: 'completed', content: [{ type: 'output_text', text, annotations: [] }] });

const server = createServer(async (req, res) => {
  const chunks = []; for await (const chunk of req) chunks.push(chunk);
  const marker = markerFrom(Buffer.concat(chunks).toString('utf8'));
  const record = { marker, opened_at: now(), request_aborted_at: null, response_closed_at: null, response_ended_at: null, writes_after_close: 0 };
  report.provider.requests.push(record);
  req.on('aborted', () => { record.request_aborted_at = now(); });
  res.on('close', () => { record.response_closed_at = now(); streams.delete(marker); });
  res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache' });
  const start = { id: `resp_${marker}`, status: 'in_progress', output: [] };
  const item = { id: `msg_${marker}`, type: 'message', role: 'assistant', status: 'in_progress', content: [] };
  emit(res, 'response.created', { response: start });
  emit(res, 'response.output_item.added', { output_index: 0, item });
  emit(res, 'response.output_text.delta', { item_id: item.id, output_index: 0, content_index: 0, delta: 'SYNTHETIC_BEGIN ' });
  if (marker === 'STOP_PROBE_NORMAL') {
    const done = completedItem('SYNTHETIC_BEGIN NORMAL_DONE');
    emit(res, 'response.output_text.delta', { item_id: done.id, output_index: 0, content_index: 0, delta: 'NORMAL_DONE' });
    emit(res, 'response.output_item.done', { output_index: 0, item: done });
    emit(res, 'response.completed', { response: { ...start, status: 'completed', output: [done], usage: { input_tokens: 1, output_tokens: 2, total_tokens: 3 } } });
    record.response_ended_at = now(); res.end(); return;
  }
  if (marker === 'STOP_PROBE_DISCONNECT') {
    setTimeout(() => res.destroy(new Error('synthetic provider disconnect')), 80).unref();
    return;
  }
  // Long response stays open until App Server cancels it or the probe cleanup closes it.
  const interval = setInterval(() => {
    if (res.destroyed || res.writableEnded) { record.writes_after_close += 1; clearInterval(interval); return; }
    emit(res, 'response.output_text.delta', { item_id: item.id, output_index: 0, content_index: 0, delta: 'tick ' });
  }, 80);
  streams.set(marker, { res, interval });
});
server.on('connection', (socket) => {
  const entry = { opened_at: now(), closed_at: null };
  report.provider.connections.push(entry);
  socket.on('close', () => { entry.closed_at = now(); });
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const providerUrl = `http://127.0.0.1:${server.address().port}/v1`;
const env = Object.fromEntries(['SystemRoot', 'SYSTEMROOT', 'WINDIR', 'COMSPEC', 'PATHEXT', 'PATH']
  .filter((key) => process.env[key]).map((key) => [key, process.env[key]]));
Object.assign(env, { CODEX_HOME: home, HOME: home, USERPROFILE: home, APPDATA: home, LOCALAPPDATA: home, TEMP: root, TMP: root });
const disabledFeatures = [
  'shell_tool', 'shell_snapshot', 'unified_exec', 'apply_patch_freeform', 'apps', 'plugins', 'remote_plugin',
  'multi_agent', 'js_repl', 'js_repl_tools_only', 'browser_use', 'computer_use', 'image_generation', 'imagegen',
  'hooks', 'memories', 'memory_tool', 'scheduled_tasks', 'workspace_dependencies', 'skill_mcp_dependency_install',
  'skill_env_var_dependency_prompt', 'enable_request_compression', 'responses_websockets', 'responses_websockets_v2',
  'code_mode_host', 'code_mode_only', 'multi_agent_v2', 'default_mode_request_user_input', 'goals', 'sleep_tool',
  'skill_search', 'tool_suggest', 'request_permissions_tool', 'browser_use_external', 'browser_use_full_cdp_access', 'view_image',
];
const args = ['app-server', '--listen', 'stdio://',
  '-c', 'model="gpt-5.6-sol"', '-c', 'model_provider="synthetic_stop_probe"',
  '-c', 'approval_policy="never"', '-c', 'sandbox_mode="read-only"', '-c', 'web_search="disabled"',
  '-c', 'project_doc_max_bytes=0', '-c', 'notify=[]', '-c', 'mcp_servers={}', '-c', 'hooks={}',
  '-c', 'tools.view_image=false', '-c', 'analytics.enabled=false', '-c', 'features.code_mode.enabled=false', '-c', 'features.skip_host_skill_discovery=true',
  '-c', `model_providers.synthetic_stop_probe={name="Synthetic stop probe",base_url="${providerUrl}",wire_api="responses",requires_openai_auth=false,request_max_retries=0,stream_max_retries=0}`,
];
for (const feature of disabledFeatures) args.push('-c', `features.${feature}=false`);
const client = new CodexAppServerClient({ commandSpec: { command: executable, args }, cwd, env, experimentalApi: true, requestTimeoutMs: 12_000, stopTimeoutMs: 4_000 });
client.on('notification', ({ sequence, message }) => report.notifications.push({ sequence, at: now(), method: message.method, thread_id: message.params?.threadId || null, turn_id: message.params?.turn?.id || message.params?.turnId || null, status: message.params?.turn?.status || null, error: message.params?.error?.message || null }));
client.on('stopped', () => { report.process.stopped_at = now(); });
client.on('serverRequest', (request) => request.respondError({ code: -32601, message: 'Synthetic stop probe rejects server requests.' }));

async function waitTerminal(threadId, turnId, afterSequence) {
  return client.waitForNotification('turn/completed', (message) => message.params?.threadId === threadId && message.params?.turn?.id === turnId, { afterSequence, timeoutMs: 8_000 });
}
async function waitProviderRequest(marker) {
  const deadline = now() + 3_000;
  while (!report.provider.requests.some((request) => request.marker === marker)) {
    if (now() >= deadline) throw new Error(`Provider request did not open for ${marker}.`);
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
}
async function phase(marker, action) {
  const thread = await client.startThread({ cwd, model: 'gpt-5.6-sol', modelProvider: 'synthetic_stop_probe', approvalPolicy: 'never', sandbox: 'read-only', ephemeral: true, environments: [], runtimeWorkspaceRoots: [], selectedCapabilityRoots: [], dynamicTools: [] });
  const afterSequence = client.notificationSequence;
  const started = await client.startTurn(thread.thread.id, marker, { environments: [] });
  const turnId = started.turn.id;
  const result = { thread_id: thread.thread.id, turn_id: turnId, started_at: now(), ack_at: null, terminal: null, error: null };
  report.phases[marker] = result;
  try { await action({ threadId: thread.thread.id, turnId, afterSequence, result }); }
  catch (error) { result.error = error.message; }
}

try {
  report.initialize = await client.start();
  client.child?.once('close', () => { report.process.close_observed_at = now(); });
  report.account = await client.readAccount();
  if (report.account.requiresOpenaiAuth !== false) throw new Error('Synthetic provider unexpectedly requires OpenAI auth.');
  const config = await client.request('config/read', { cwd, includeLayers: true });
  report.config_layers = (config.layers || []).map((layer) => ({ name: layer.name, config_keys: Object.keys(layer.config || {}) }));
  const configuredProvider = config.config?.model_provider;
  const configuredProviderDefinition = config.config?.model_providers?.synthetic_stop_probe;
  report.synthetic_provider_config = {
    model_provider: configuredProvider ?? null,
    base_url: configuredProviderDefinition?.base_url ?? null,
    requires_openai_auth: configuredProviderDefinition?.requires_openai_auth ?? null,
  };
  if (configuredProvider !== 'synthetic_stop_probe' || configuredProviderDefinition?.base_url !== providerUrl || configuredProviderDefinition?.requires_openai_auth !== false) {
    throw new Error('Synthetic provider configuration did not match the loopback-only contract.');
  }
  const requirements = await client.request('configRequirements/read', {});
  report.requirements_present = Boolean(requirements.requirements && Object.keys(requirements.requirements).length);
  if (report.requirements_present) throw new Error('Managed requirements present; no thread created.');
  for (const layer of config.layers || []) {
    if (layer.name?.type === 'system' && Object.keys(layer.config || {}).length === 0) continue;
    if (layer.name?.type === 'user' && Object.keys(layer.config || {}).length !== 0) throw new Error('Non-empty user config layer; no thread created.');
    if (!['sessionFlags', 'user'].includes(layer.name?.type)) throw new Error(`Unexpected config layer ${JSON.stringify(layer.name)}; no thread created.`);
  }
  if (Object.keys(config.config?.mcp_servers || {}).length || Object.values(config.config?.hooks || {}).some((value) => !Array.isArray(value) || value.length)) {
    throw new Error('Unexpected MCP or hooks; no thread created.');
  }
  await phase('STOP_PROBE_INTERRUPT', async ({ threadId, turnId, afterSequence, result }) => {
    await waitProviderRequest('STOP_PROBE_INTERRUPT');
    await client.waitForNotification('item/agentMessage/delta', (message) => message.params?.turnId === turnId, { afterSequence, timeoutMs: 8_000 });
    result.pre_interrupt_text_count = report.notifications.filter((entry) => entry.turn_id === turnId && entry.method === 'item/agentMessage/delta' && entry.sequence > afterSequence).length;
    if (result.pre_interrupt_text_count < 1) throw new Error('No matching text delta observed before interrupt.');
    await client.interruptTurn(threadId, turnId, {
      onDispatched: () => {
        result.dispatched_at = now();
        result.dispatch_notification_sequence = client.notificationSequence;
      },
    });
    if (result.dispatched_at == null) throw new Error('Interrupt dispatch was not observed.');
    result.ack_at = now();
    result.ack_notification_sequence = client.notificationSequence;
    const terminal = await waitTerminal(threadId, turnId, afterSequence);
    const event = report.notifications.findLast((entry) => entry.method === 'turn/completed' && entry.turn_id === turnId);
    result.terminal = { at: now(), status: terminal.params.turn.status, sequence: event?.sequence ?? client.notificationSequence };
    await new Promise((resolve) => setTimeout(resolve, 300));
    result.late_text_notifications = report.notifications.filter((entry) => entry.turn_id === turnId && entry.method === 'item/agentMessage/delta' && entry.sequence > result.terminal.sequence).length;
    const providerRequest = report.provider.requests.find((request) => request.marker === 'STOP_PROBE_INTERRUPT');
    result.provider_stream = providerRequest ? {
      response_closed_at: providerRequest.response_closed_at,
      request_aborted_at: providerRequest.request_aborted_at,
      response_ended_at: providerRequest.response_ended_at,
    } : null;
  });
  await phase('STOP_PROBE_NORMAL', async ({ threadId, turnId, afterSequence, result }) => {
    const terminal = await waitTerminal(threadId, turnId, afterSequence);
    result.terminal = { at: now(), status: terminal.params.turn.status, sequence: client.notificationSequence };
  });
  await phase('STOP_PROBE_DISCONNECT', async ({ threadId, turnId, afterSequence, result }) => {
    const terminal = await waitTerminal(threadId, turnId, afterSequence);
    result.terminal = { at: now(), status: terminal.params.turn.status, sequence: client.notificationSequence };
  });
} catch (error) { report.error = error.message; }
finally {
  for (const { res, interval } of streams.values()) { clearInterval(interval); res.destroy(); }
  const beforeStop = now();
  try {
    report.process.stop_evidence = await client.stop();
  } catch (error) {
    report.process.stop_error = { code: error.code || null, message: error.message };
  }
  report.process.stop_returned_at = now();
  report.process.stop_duration_ms = report.process.stop_returned_at - beforeStop;
  server.closeAllConnections(); await new Promise((resolve) => server.close(resolve));
  report.stderr = client.stderrLines;
  report.probe_passed = !report.error && Object.values(report.phases).every((phaseResult) => !phaseResult.error)
    && report.phases.STOP_PROBE_INTERRUPT?.pre_interrupt_text_count >= 1
    && report.phases.STOP_PROBE_INTERRUPT?.dispatched_at != null
    && report.phases.STOP_PROBE_INTERRUPT?.terminal?.status === 'interrupted'
    && report.phases.STOP_PROBE_INTERRUPT.terminal.sequence > report.phases.STOP_PROBE_INTERRUPT.dispatch_notification_sequence
    && report.phases.STOP_PROBE_INTERRUPT.late_text_notifications === 0
    && !report.process.stop_error
    && report.process.stop_evidence?.process_close_observed === true
    && report.process.close_observed_at != null
    && report.process.close_observed_at <= report.process.stop_returned_at
    && report.phases.STOP_PROBE_NORMAL?.terminal?.status === 'completed'
    && report.phases.STOP_PROBE_DISCONNECT?.terminal?.status === 'failed';
  writeFileSync(path.join(root, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ report_path: path.join(root, 'report.json'), executable_sha256: report.executable_sha256, probe_passed: report.probe_passed, phases: report.phases, process: report.process, provider: report.provider, error: report.error || null }, null, 2));
  process.exitCode = report.probe_passed ? 0 : 2;
}
