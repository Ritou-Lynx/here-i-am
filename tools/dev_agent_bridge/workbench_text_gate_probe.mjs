// Synthetic CLI integration for the two text gates. Never uses real auth/model.
import { createServer } from 'node:http';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { CodexAppServerClient } from './codex_app_server_client.mjs';
import { restrictions, assertIsolation, toolCall } from './workbench_tool_behavior_probe.mjs';
import { TEXT_GATE_CLI_SHA256 } from './workbench_text_gate_runtime_pin.mjs';
import { inspectCompiledToolCatalog } from './workbench_text_only_probe_contract.mjs';
import { exchangeTextOnly } from './workbench_text_gate_transport.mjs';

const MODEL = 'gpt-5.6-sol';
const MARKER = 'SYNTHETIC_TEXT_ONLY_42';
const MESSAGE = { id: 'msg_fixture', type: 'message', role: 'assistant', status: 'completed',
  content: [{ type: 'output_text', text: MARKER, annotations: [] }] };
const encode = event => `event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`;
function streamFor(items) {
  const response = { id: 'resp_fixture', object: 'response', status: 'completed', output: items };
  return [
    { type: 'response.created', response: { ...response, status: 'in_progress', output: [] } },
    ...items.flatMap((item, output_index) => [
      { type: 'response.output_item.added', output_index, item: { ...item, status: 'in_progress', ...(item.type === 'message' ? { content: [] } : {}) } },
      ...(item.type === 'message' ? item.content.flatMap((part, content_index) => [
        { type: 'response.content_part.added', output_index, content_index, item_id: item.id, part: { type: 'output_text', text: '', annotations: [] } },
        { type: 'response.output_text.delta', output_index, content_index, item_id: item.id, delta: part.text },
        { type: 'response.output_text.done', output_index, content_index, item_id: item.id, text: part.text },
        { type: 'response.content_part.done', output_index, content_index, item_id: item.id, part },
      ]) : []),
      { type: 'response.output_item.done', output_index, item },
    ]),
    { type: 'response.completed', response },
  ].map(encode).join('');
}
function fixture(name) {
  if (name === 'text_positive' || name === 'dynamic_positive') return streamFor([MESSAGE]);
  if (name === 'custom_call') return streamFor([toolCall('functions', 'exec', 'text(6 * 7);')]);
  if (name === 'dynamic_call') return streamFor([toolCall(null, 'synthetic_echo', { value: 42 })]);
  if (name === 'collaboration_call') return streamFor([toolCall('collaboration', 'list_agents', {})]);
  if (name === 'mixed_text_call') return streamFor([MESSAGE, toolCall('functions', 'exec', 'text(6 * 7);')]);
  if (name === 'hosted_call') return streamFor([{ type: 'web_search_call', id: 'hosted_fixture', status: 'completed', action: { type: 'search', query: 'synthetic' } }]);
  if (name === 'unknown_item') return streamFor([{ type: 'future_tool', id: 'unknown_fixture', status: 'completed' }]);
  if (name === 'unknown_event') return encode({ type: 'response.future_call', payload: {} }) + streamFor([MESSAGE]);
  if (name === 'post_terminal_tool') return streamFor([MESSAGE]) + encode({ type: 'response.output_item.done', output_index: 1, item: toolCall(null, 'synthetic_echo', { value: 42 }) });
  if (name === 'disconnect_after_terminal' || name === 'timeout_after_terminal') return streamFor([MESSAGE]);
  if (name === 'truncated_text') return streamFor([MESSAGE]).split('event: response.completed')[0];
  if (name === 'completed_call_only') return [
    encode({ type: 'response.created', response: { id: 'resp_fixture', status: 'in_progress', output: [] } }),
    encode({ type: 'response.completed', response: { id: 'resp_fixture', status: 'completed', output: [toolCall(null, 'synthetic_echo', { value: 42 })] } }),
  ].join('');
  throw new Error('Unknown fixed synthetic case.');
}

async function runCase(executable, root, name) {
  const directory = path.join(root, name); mkdirSync(directory);
  const home = path.join(directory, 'home'); const cwd = path.join(directory, 'work'); mkdirSync(home); mkdirSync(cwd);
  const control = name === 'dynamic_positive';
  const result = { name, guarded: !control, requests: 0, server_requests: [], upstream_requests: [],
    released_bytes: 0, rejected: false, positive_control_dispatched: false, text: '', terminal: null, process_close_observed: false };
  const upstreamServer = createServer(async (req, res) => {
    try {
      if (req.method !== 'POST' || req.url !== '/v1/responses' || req.headers.authorization) throw new Error('Unexpected synthetic upstream request.');
      const chunks = []; let size = 0;
      for await (const chunk of req) { size += chunk.length; if (size > 1024 * 1024) throw new Error('Upstream request too large.'); chunks.push(chunk); }
      const upstream = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      const inspection = inspectCompiledToolCatalog(upstream);
      if (!inspection.no_tools || upstream.tool_choice !== 'none' || upstream.parallel_tool_calls !== false) throw new Error('Upstream tool boundary failed.');
      result.upstream_requests.push({ tool_choice: upstream.tool_choice, parallel_tool_calls: upstream.parallel_tool_calls,
        store: upstream.store, ...inspection, input_types: upstream.input.map(item => item.type) });
      if (result.upstream_requests.length !== 1) throw new Error('Unexpected upstream retry.');
      res.writeHead(200, { 'content-type': 'text/event-stream' });
      // Deliberately violate tool_choice in negative cases. Even complete text
      // followed by an error or another frame must never reach the CLI.
      const raw = Buffer.from(fixture(name), 'utf8');
      for (let offset = 0; offset < raw.length; offset += 17) res.write(raw.subarray(offset, offset + 17));
      if (name === 'disconnect_after_terminal') setTimeout(() => res.destroy(), 20).unref();
      else if (name !== 'timeout_after_terminal') res.end();
    } catch (error) { result.upstream_error = error.message; if (!res.headersSent) res.writeHead(400); res.end(); }
  });
  await new Promise(resolve => upstreamServer.listen(0, '127.0.0.1', resolve));
  const upstreamUrl = `http://127.0.0.1:${upstreamServer.address().port}/v1/responses`;
  const server = createServer(async (req, res) => {
    try {
      if (req.method !== 'POST' || req.url !== '/v1/responses' || req.headers.authorization || req.headers['content-encoding']) throw new Error('Unexpected request or authentication.');
      const parts = []; let bytes = 0;
      for await (const chunk of req) { bytes += chunk.length; if (bytes > 1024 * 1024) throw new Error('Request too large.'); parts.push(chunk); }
      const body = JSON.parse(Buffer.concat(parts).toString('utf8'));
      if (body.model !== MODEL || ++result.requests > (control ? 2 : 1)) throw new Error('Synthetic request budget/model mismatch.');
      result.received_catalog = inspectCompiledToolCatalog(body);
      if (control) {
        if (result.requests === 2) {
          result.control_output_received = body.input.some(item => item.type === 'function_call_output' && item.call_id === 'probe_call' && item.output === 'SYNTHETIC_ECHO_42');
        }
        res.writeHead(200, { 'content-type': 'text/event-stream' });
        res.end(result.requests === 1 ? streamFor([toolCall(null, 'synthetic_echo', { value: 42 })]) : fixture(name));
        return;
      }
      const safe = await exchangeTextOnly(body, { model: MODEL, upstreamUrl, timeoutMs: name === 'timeout_after_terminal' ? 200 : 5000 });
      result.released_bytes = safe.length;
      res.writeHead(200, { 'content-type': 'text/event-stream' }); res.end(safe);
    } catch (error) {
      result.rejected = true; result.rejection_code = error.code || 'probe_contract';
      result.rejection_message = error.message;
      res.writeHead(422, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: { message: 'Synthetic text gate rejected response.', type: 'text_gate_rejected' } }));
    }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}/v1`;
  const overrides = { ...restrictions(false), 'agents.enabled': false };
  const args = ['app-server', '--listen', 'stdio://'];
  for (const [key, value] of Object.entries(overrides)) args.push('-c', `${key}=${typeof value === 'object' && !Array.isArray(value) ? '{}' : JSON.stringify(value)}`);
  args.push('-c', `model_providers.synthetic_probe={name="Synthetic text gate",base_url="${baseUrl}",wire_api="responses",requires_openai_auth=false,request_max_retries=0,stream_max_retries=0}`);
  const env = Object.fromEntries(['SystemRoot', 'SYSTEMROOT', 'WINDIR', 'COMSPEC', 'PATHEXT', 'PATH'].filter(key => process.env[key]).map(key => [key, process.env[key]]));
  Object.assign(env, { CODEX_HOME: home, HOME: home, USERPROFILE: home, APPDATA: home, LOCALAPPDATA: home, TEMP: directory, TMP: directory });
  const client = new CodexAppServerClient({ commandSpec: { command: executable, args }, cwd, env, experimentalApi: true, requestTimeoutMs: 10000 });
  client.on('notification', ({ message }) => { if (message.method === 'item/agentMessage/delta') result.text += message.params?.delta || ''; });
  client.on('serverRequest', request => {
    result.server_requests.push(request.method);
    if (control && request.method === 'item/tool/call' && request.params.tool === 'synthetic_echo' && request.params.arguments?.value === 42) {
      result.positive_control_dispatched = true;
      request.respond({ success: true, contentItems: [{ type: 'inputText', text: 'SYNTHETIC_ECHO_42' }] });
    } else request.respondError({ code: -32601, message: 'Unexpected synthetic client request rejected.' });
  });
  try {
    await client.start();
    const config = await client.request('config/read', { cwd, includeLayers: true });
    const requirements = await client.request('configRequirements/read', {});
    assertIsolation(config, requirements.requirements, baseUrl);
    if (config.config.agents?.enabled !== false) throw new Error('Agent disabling not effective.');
    const thread = await client.startThread({ cwd, model: MODEL, modelProvider: 'synthetic_probe', approvalPolicy: 'never', sandbox: 'read-only',
      ephemeral: true, environments: [], runtimeWorkspaceRoots: [], selectedCapabilityRoots: [],
      dynamicTools: control ? [{ type: 'function', name: 'synthetic_echo', description: 'Synthetic marker control.', inputSchema: { type: 'object', properties: { value: { type: 'integer' } }, required: ['value'], additionalProperties: false } }] : [],
      baseInstructions: 'Synthetic text gate fixture only.' });
    if (thread.modelProvider !== 'synthetic_probe' || thread.model !== MODEL) throw new Error('Unexpected thread provider.');
    const afterSequence = client.notificationSequence;
    const turn = await client.startTurn(thread.thread.id, 'Return the fixed synthetic fixture.', { environments: [] });
    const terminal = await client.waitForNotification('turn/completed', event => event.params?.threadId === thread.thread.id && event.params?.turn?.id === turn.turn.id,
      { afterSequence, timeoutMs: 10000 });
    result.terminal = terminal.params.turn.status;
  } catch (error) { result.error = error.message; }
  finally {
    try { result.stop_evidence = await client.stop(); result.process_close_observed = result.stop_evidence.process_close_observed === true; }
    catch (error) { result.stop_error = error.code || error.message; }
    server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
    upstreamServer.closeAllConnections(); await new Promise(resolve => upstreamServer.close(resolve));
  }
  const common = !result.error && !result.stop_error && !result.upstream_error && result.process_close_observed;
  result.passed = common && (control
    ? result.terminal === 'completed' && result.positive_control_dispatched && result.control_output_received
    : result.server_requests.length === 0 && result.upstream_requests.length === 1 && (name === 'text_positive'
      ? result.terminal === 'completed' && result.text === MARKER && result.released_bytes > 0 && !result.rejected
      : result.terminal === 'failed' && result.text === '' && result.rejected && result.released_bytes === 0));
  writeFileSync(path.join(directory, 'report.json'), JSON.stringify(result, null, 2));
  return result;
}
export async function main(executable) {
  if (!executable || !path.isAbsolute(executable)) throw new Error('Pass the pinned absolute Codex executable.');
  const hash = createHash('sha256').update(readFileSync(executable)).digest('hex');
  if (hash !== TEXT_GATE_CLI_SHA256) throw new Error('Unexpected CLI fingerprint.');
  const root = mkdtempSync(path.join(tmpdir(), 'hereiam-text-gate-probe-'));
  const report = { schema_version: 1, synthetic_only: true, cli_sha256: hash, production_isolation_passed: false, cases: [] };
  for (const name of ['dynamic_positive', 'text_positive', 'custom_call', 'dynamic_call', 'collaboration_call', 'mixed_text_call', 'hosted_call', 'unknown_item', 'unknown_event', 'truncated_text', 'completed_call_only', 'post_terminal_tool', 'disconnect_after_terminal', 'timeout_after_terminal']) {
    const result = await runCase(executable, root, name); report.cases.push(result);
    console.log(JSON.stringify({ case: name, passed: result.passed, terminal: result.terminal, rejected: result.rejected, rejection_code: result.rejection_code, error: result.error }));
    if (!result.passed) break;
  }
  report.probe_passed = report.cases.length === 14 && report.cases.every(item => item.passed);
  writeFileSync(path.join(root, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ report_path: path.join(root, 'report.json'), probe_passed: report.probe_passed, production_isolation_passed: false }));
  process.exitCode = report.probe_passed ? 0 : 2;
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) await main(process.argv[2]);
