// R7 real-CLI / fake-provider integration. No account or official endpoint.
// Peer verification is deliberately synthetic: no OS-isolation claim is made.
import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { CodexAppServerClient } from './codex_app_server_client.mjs';
import { restrictions, assertIsolation } from './workbench_tool_behavior_probe.mjs';
import { exchangeTextOnly } from './workbench_text_gate_transport.mjs';
import { createTextTaskBroker, TEXT_TASK_MODEL } from './workbench_text_task_broker.mjs';
import { WorkbenchTextTaskSession } from './workbench_text_task_session.mjs';
import { isWorkbenchTextStopReceipt } from './workbench_text_stop_receipt.mjs';
import { assertTextTaskExecutable, TEXT_TASK_CLI_SHA256 } from './workbench_text_task_runtime_pin.mjs';

const INPUT = 'Reply exactly: P6_R7_SYNTHETIC_OK';
const TEXT = 'P6_R7_SYNTHETIC_OK';
const assert = (value, code) => { if (!value) throw Object.assign(new Error(code), { code }); };

function launch(executable, root, baseUrl) {
  const home = path.join(root, 'home'); const cwd = path.join(root, 'work');
  mkdirSync(home); mkdirSync(cwd);
  const args = ['app-server', '--listen', 'stdio://'];
  for (const [key, value] of Object.entries({ ...restrictions(false), 'agents.enabled': false })) {
    args.push('-c', `${key}=${typeof value === 'object' && !Array.isArray(value) ? '{}' : JSON.stringify(value)}`);
  }
  args.push('-c', `model_providers.synthetic_probe={name="Synthetic R7 lifecycle",base_url="${baseUrl}",wire_api="responses",requires_openai_auth=false,env_key="P6_SYNTHETIC_TOKEN",request_max_retries=0,stream_max_retries=0,supports_websockets=false}`);
  const env = Object.fromEntries(['SystemRoot', 'SYSTEMROOT', 'WINDIR', 'COMSPEC', 'PATHEXT', 'PATH']
    .filter(key => process.env[key]).map(key => [key, process.env[key]]));
  Object.assign(env, { CODEX_HOME: home, HOME: home, USERPROFILE: home, APPDATA: home,
    LOCALAPPDATA: home, TEMP: root, TMP: root, P6_SYNTHETIC_TOKEN: 'synthetic-fixture-only' });
  return { commandSpec: { command: executable, args }, cwd, env, experimentalApi: true, requestTimeoutMs: 10000 };
}

async function runCase(executable, root, name) {
  const result = { name, passed: false, synthetic_only: true, os_isolation_verified: false,
    upstream_requests: 0, host_requests: 0, process_close_observed: false };
  let requestSeen;
  const seen = new Promise(resolve => { requestSeen = resolve; });
  const upstream = createServer(async (req, res) => {
    try {
      let bytes = 0; const chunks = [];
      for await (const chunk of req) { bytes += chunk.length; assert(bytes <= 256 * 1024, 'fake_body_limit'); chunks.push(chunk); }
      const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      assert(req.method === 'POST' && req.url === '/v1/responses' && !req.headers.authorization, 'fake_upstream_scope');
      assert(++result.upstream_requests === 1 && body.tools.length === 0 && body.tool_choice === 'none'
        && body.parallel_tool_calls === false && body.input.length === 1
        && body.input[0].content[0].text === INPUT, 'fake_request_boundary');
      requestSeen();
      if (name === 'interrupt') return; // No prefix; a controlled in-flight exchange.
      const item = name === 'tool_rejected'
        ? { type: 'function_call', id: 'item_fixture', call_id: 'call_fixture', name: 'synthetic_echo', arguments: '{}', status: 'completed' }
        : { type: 'message', id: 'msg_fixture', role: 'assistant', status: 'completed',
          content: [{ type: 'output_text', text: TEXT, annotations: [] }] };
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ id: 'resp_fixture', object: 'response', status: 'completed', output: [item] }));
    } catch { result.upstream_error = 'fake_upstream_rejected'; res.writeHead(400); res.end(); }
  });
  await new Promise(resolve => upstream.listen(0, '127.0.0.1', resolve));
  let client; let child; let session;
  const upstreamUrl = `http://127.0.0.1:${upstream.address().port}/v1/responses`;
  const broker = createTextTaskBroker({
    verifyPeer: () => !!child && child.exitCode === null && child.signalCode === null,
    exchange: (body, options) => exchangeTextOnly(body, { ...options, upstreamUrl, headers: {} }),
  });
  try {
    const baseUrl = await broker.listen();
    const spec = launch(executable, root, baseUrl);
    client = new CodexAppServerClient(spec);
    client.on('serverRequest', request => {
      result.host_requests++;
      request.respondError({ code: -32601, message: 'Synthetic text task rejects host requests.' });
    });
    await client.start();
    child = client.child;
    child.once('close', () => { result.process_close_observed = true; });
    const config = await client.request('config/read', { cwd: spec.cwd, includeLayers: true });
    const requirements = await client.request('configRequirements/read', {});
    assertIsolation(config, requirements.requirements, baseUrl);
    assert(config.config.agents?.enabled === false, 'synthetic_config_rejected');
    const started = await client.startThread({ cwd: spec.cwd, model: TEXT_TASK_MODEL, modelProvider: 'synthetic_probe',
      approvalPolicy: 'never', sandbox: 'read-only', ephemeral: true, dynamicTools: [],
      environments: [], runtimeWorkspaceRoots: [], selectedCapabilityRoots: [],
      baseInstructions: 'Synthetic R7 lifecycle fixture.' });
    assert(started.modelProvider === 'synthetic_probe' && started.model === TEXT_TASK_MODEL, 'synthetic_thread_rejected');
    session = new WorkbenchTextTaskSession({ client, broker, executionEpoch: randomUUID(), providerThreadId: started.thread.id,
      closeChild: async () => (await client.stop()).process_close_observed === true && result.process_close_observed });
    result.binding = session.binding;
    if (name !== 'no_turn') {
      const after = client.notificationSequence;
      const turn = await session.startTurn(INPUT);
      result.turn_binding = turn;
      if (name === 'interrupt') {
        let timeout;
        try {
          await Promise.race([seen, new Promise((_, reject) => { timeout = setTimeout(() => reject(new Error('fake_request_missing')), 10000); })]);
        } finally { clearTimeout(timeout); }
        await session.interruptTurn(turn.turn_id);
      }
      const terminal = await client.waitForNotification('turn/completed', event =>
        event.params?.threadId === started.thread.id && event.params?.turn?.id === turn.provider_turn_id,
      { afterSequence: after, timeoutMs: 10000 });
      result.provider_status = terminal.params.turn.status;
      const events = session.readEvents();
      const text = events.events.filter(event => event.kind === 'message_delta').map(event => event.data.text).join('');
      result.fixed_text_observed = text === TEXT;
      result.text_empty = text === '';
      result.provider_terminal_event_observed = events.events.some(event => event.kind === 'turn_status' && event.status === result.provider_status);
    }
    const receipt = await session.close();
    result.branded_receipt = isWorkbenchTextStopReceipt(receipt);
    result.stop_receipt = receipt;
    result.broker = broker.snapshot();
    const expected = name === 'interrupt' ? 'interrupted' : name === 'tool_rejected' ? 'failed' : 'completed';
    result.passed = result.process_close_observed && result.branded_receipt && result.host_requests === 0
      && !result.upstream_error && result.broker.drained
      && (name === 'no_turn'
        ? receipt.outcome === 'closed_without_turn' && receipt.provider_terminal_confirmed === false && result.upstream_requests === 0
        : result.upstream_requests === 1 && result.provider_status === expected && result.provider_terminal_event_observed
          && receipt.provider_terminal_status === expected && receipt.cancellation_confirmed === (name === 'interrupt')
          && (['interrupt', 'tool_rejected'].includes(name) ? result.text_empty && !result.broker.response_released
            : result.fixed_text_observed && result.broker.response_released));
  } catch (error) { result.code = typeof error.code === 'string' && /^[a-z_]{1,80}$/.test(error.code) ? error.code : 'synthetic_case_failed'; }
  finally {
    broker.revoke();
    try { await client?.stop(); } catch { result.code = 'synthetic_close_unconfirmed'; }
    await broker.close();
    upstream.closeAllConnections();
    await new Promise(resolve => upstream.close(resolve));
  }
  return result;
}

export async function main(argv = process.argv.slice(2)) {
  assert(argv.length === 2 && argv[0] === '--synthetic-only', 'explicit_synthetic_required');
  const executable = assertTextTaskExecutable(argv[1]);
  const root = mkdtempSync(path.join(tmpdir(), 'hereiam-r7-lifecycle-'));
  const report = { schema_version: 1, cli_sha256: TEXT_TASK_CLI_SHA256,
    synthetic_only: true, production_isolation_passed: false, human_gate_passed: false, cases: [] };
  for (const name of ['no_turn', 'completed', 'interrupt', 'tool_rejected', 'new_attempt_after_stop']) {
    const caseRoot = path.join(root, name); mkdirSync(caseRoot);
    const result = await runCase(executable, caseRoot, name);
    report.cases.push(result);
    console.log(JSON.stringify({ name, passed: result.passed, code: result.code, provider_status: result.provider_status }));
    if (!result.passed) break;
  }
  assertTextTaskExecutable(executable);
  const bindings = report.cases.map(item => item.binding).filter(Boolean);
  report.fresh_attempt_bindings = ['local_session_id', 'execution_epoch', 'provider_thread_id']
    .every(key => new Set(bindings.map(binding => binding[key])).size === bindings.length);
  report.passed = report.cases.length === 5 && report.cases.every(item => item.passed) && report.fresh_attempt_bindings;
  const reportPath = path.join(root, 'report.json');
  writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, { flag: 'wx' });
  console.log(JSON.stringify({ report_path: reportPath, passed: report.passed, production_isolation_passed: false }));
  process.exitCode = report.passed ? 0 : 2;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) await main();
