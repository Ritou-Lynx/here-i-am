import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import http from 'node:http';
import path from 'node:path';
import test from 'node:test';
import { runHttpNativeTurnProbe, parseHttpTurnProbeArgs, HTTP_TURN_FIXED_INPUT } from './workbench_text_task_http_turn_probe.mjs';
import { TEXT_TASK_CLI_SHA256 } from './workbench_text_task_runtime_pin.mjs';
import { TEXT_TASK_MODEL } from './workbench_text_task_broker.mjs';
import { ExperimentalRuntimeApi } from './experimental_runtime_api.mjs';
const options = scenario => ({ scenario, executable: path.resolve('synthetic-owner.exe'), sha256: 'a'.repeat(64) });
const closed = () => ({ process_close_observed: true, job_empty_verified: true, stdio_eof_verified: true,
 rules_absent_verified: true, handles_closed_verified: true, helper_exits_verified: true, cleanup_pending: false });
function config() {
  const disabled = ('shell_tool shell_snapshot unified_exec apply_patch_freeform apps plugins remote_plugin multi_agent '
    + 'js_repl js_repl_tools_only browser_use computer_use image_generation imagegen hooks memories memory_tool scheduled_tasks '
    + 'workspace_dependencies skill_mcp_dependency_install skill_env_var_dependency_prompt enable_request_compression responses_websockets '
    + 'responses_websockets_v2 code_mode_only multi_agent_v2 default_mode_request_user_input goals sleep_tool skill_search tool_suggest '
    + 'request_permissions_tool browser_use_external browser_use_full_cdp_access view_image code_mode_host respect_system_proxy').split(' ');
  return { config: { model: TEXT_TASK_MODEL, model_provider: 'p6_native_startup', approval_policy: 'never',
    sandbox_mode: 'read-only', web_search: 'disabled', project_doc_max_bytes: 0, agents: { enabled: false },
    mcp_servers: {}, notify: [], hooks: {}, features: { ...Object.fromEntries(disabled.map(key => [key, false])), skip_host_skill_discovery: true },
    model_providers: { p6_native_startup: { base_url: 'http://127.0.0.1:32123/v1', wire_api: 'responses',
      requires_openai_auth: true, request_max_retries: 0, stream_max_retries: 0, supports_websockets: false } } },
  layers: [{ name: { type: 'sessionFlags' }, config: {} }] };
}

function fixture(scenario, settings = {}) {
  let owner, client, broker, exchange, exchangeWork, terminal = null;
  const abort = new AbortController();
  const seen = { starts: 0, arms: 0, turns: 0, interrupts: 0, closes: 0, exchange: 0 };
  const state = { admitted_connections: 0, rejected_connections: 0, parsed_requests: 0, metadata_rejections: 0,
    rejected_requests: 0, upstream_attempts: 0, response_released: false, drained: false };
  function finish(status) {
    if (terminal) return; terminal = status;
    client.notify('turn/completed', { threadId: 'synthetic-thread', turn: { id: settings.wrongTerminal ? 'other-turn' : 'synthetic-turn', status } });
  }
  const factories = {
    async exchange(_outgoing, { signal }) {
      seen.exchange++;
      if (scenario === 'completed' || settings.fastComplete) { await new Promise(resolve => setTimeout(resolve, settings.fastComplete ? 0 : 35)); return Buffer.from('synthetic reconstructed response'); }
      await new Promise((resolve, reject) => {
        const rejected = () => reject(new Error('PRIVATE TOKEN EXCHANGE'));
        signal.addEventListener('abort', rejected, { once: true }); if (signal.aborted) rejected();
      });
    },
    createBroker(args) {
      exchange = args.exchange;
      broker = { listen: async () => 'http://127.0.0.1:32123/v1',
        arm(input) { seen.arms++; assert.equal(input, HTTP_TURN_FIXED_INPUT); },
        revoke() { abort.abort(); if (settings.failedOnRevoke && !terminal && seen.turns) finish('failed'); },
        async close() { broker.revoke(); await exchangeWork; state.drained = settings.drain !== false; },
        snapshot() { return { ...state, ...settings.counters }; } };
      return broker;
    },
    createOwner(args) {
      seen.starts++;
      owner = { cleanupPending: true, diagnostics: { native_owner_exit_code: null, native_close_receipt: null },
        ready: Promise.resolve({ attempt_id: args.attemptId, type: 'started', seq: 1, auth_mode: 'chatgpt',
          provider: 'p6_native_startup', cli_sha256: TEXT_TASK_CLI_SHA256, cwd: 'D:\\fixed\\project0', pid: 42,
          creation_time: '123456789', network_boundary_verified: true, child_identity_verified: true, job_singleton: true }),
        async verifyPeer() { return true; },
        async close() { seen.closes++; if (settings.failClose) throw new Error('PRIVATE TOKEN CLOSE');
          const receipt = { ...closed(), ...settings.receipt }; owner.cleanupPending = false;
          owner.diagnostics.native_close_receipt = receipt; owner.diagnostics.native_owner_exit_code = settings.exit ?? 0; return receipt; } };
      return owner;
    },
    createClient() {
      class Client extends EventEmitter {
        isReady = false; notificationSequence = 0;
        async start() { this.isReady = true; }
        async request(method, params, dispatch) {
          if (method === 'config/read') { const value = config(); if (settings.badConfig) value.config.features.respect_system_proxy = true; return value; }
          if (method === 'configRequirements/read') return { requirements: null };
          if (method === 'account/read') { assert.deepEqual(params, { refreshToken: false }); return { account: { type: 'chatgpt', email: 'PRIVATE ACCOUNT' } }; }
          assert.equal(method, 'turn/start'); assert.equal(params.input[0].text, HTTP_TURN_FIXED_INPUT); seen.turns++;
          if (!settings.noDispatch) dispatch.onDispatched();
          state.admitted_connections = 1; state.parsed_requests = 1; state.upstream_attempts = 1;
          exchangeWork = exchange({}, { signal: abort.signal }).then(() => {
            if (abort.signal.aborted) { state.rejected_requests++; return; }
            state.response_released = true;
            this.notify('item/agentMessage/delta', { threadId: 'synthetic-thread', turnId: 'synthetic-turn', delta: settings.wrongText ? 'PRIVATE WRONG TEXT' : 'P6_R7_NATIVE_OK' });
            finish('completed');
          }, () => { state.rejected_requests++; });
          if (settings.fastComplete) await exchangeWork;
          return { turn: { id: 'synthetic-turn' } };
        }
        async startThread(params) { if (settings.lateThread) await new Promise(resolve => setTimeout(resolve, 90)); return { thread: { id: 'synthetic-thread' }, cwd: params.cwd, model: TEXT_TASK_MODEL,
          modelProvider: 'p6_native_startup', approvalPolicy: 'never', sandbox: { type: 'readOnly' } }; }
        async interruptTurn(threadId, turnId, dispatch) {
          seen.interrupts++; assert.equal(threadId, 'synthetic-thread'); assert.equal(turnId, 'synthetic-turn');
          dispatch.onDispatched(); broker.revoke();
          if (!settings.noTerminal) finish(settings.interruptFailed ? 'failed' : 'interrupted'); return {};
        }
        async waitForNotification(_method, predicate) {
          if (terminal && predicate({ params: { threadId: 'synthetic-thread', turn: { id: 'synthetic-turn', status: terminal } } })) return {};
          throw new Error('PRIVATE MISSING TERMINAL');
        }
        notify(method, params) { this.emit('notification', { sequence: ++this.notificationSequence, message: { method, params } }); }
      }
      client = new Client(); return client;
    },
  };
  return { factories, seen, timeoutMs: settings.lateThread ? 25 : settings.noTerminal || settings.wrongTerminal ? 150 : 1500, cleanupTimeoutMs: 150 };
}
async function run(scenario, settings) {
  const f = fixture(scenario, settings);
  const report = await runHttpNativeTurnProbe(options(scenario), { factories: f.factories, timeoutMs: f.timeoutMs, cleanupTimeoutMs: f.cleanupTimeoutMs });
  assert.equal(report.actual_native, false); assert.equal(report.passed, false); assert.equal(report.evidence, 'synthetic');
  assert.equal(report.production_isolation_passed, false); assert.equal(report.human_gate_passed, false);
  assert.doesNotMatch(JSON.stringify(report), /PRIVATE|synthetic-thread|synthetic-turn|P6_R7_NATIVE_OK|fixed\\/);
  assert.ok(JSON.stringify(report).length < 8192); return { report, seen: f.seen };
}

test('fixed text completes through actual HTTP JSON events and exact closed receipt', async () => {
  const { report, seen } = await run('completed');
  assert.equal(report.checks_passed, true, JSON.stringify(report));
  assert.equal(report.http_create_status, 200); assert.equal(report.http_turn_status, 200); assert.equal(report.http_delete_status, 200);
  assert.equal(report.fixed_text_observed, true); assert.equal(report.event_terminal_verified, true); assert.equal(report.stop_receipt_verified, true);
  assert.equal(report.exchange_started, 1); assert.equal(report.exchange_settled, 1); assert.equal(report.interrupt_dispatched, 0);
  assert.deepEqual(seen, { starts: 1, arms: 1, turns: 1, interrupts: 0, closes: 1, exchange: 1 });
});
test('interrupt dispatch and matching terminal are distinct from ACK and one upstream attempt', async () => {
  const { report } = await run('interrupt'); assert.equal(report.checks_passed, true, JSON.stringify(report));
  assert.equal(report.http_interrupt_status, 200); assert.equal(report.interrupt_dispatched, 1); assert.equal(report.cancellation_confirmed, true);
  assert.equal(report.broker.response_released, false); assert.equal(report.exchange_abort_observed, true); assert.equal(report.provider_terminal_status, 'interrupted');
});
test('unfinished turn HTTP response disconnect observes actual AbortSignal and closes the same owner', async () => {
  const { report, seen } = await run('turn-disconnect'); assert.equal(report.checks_passed, true, JSON.stringify(report));
  assert.equal(report.client_disconnect, true); assert.equal(report.request_abort_observed, true);
  assert.equal(report.held_result_released_after_abort, true); assert.equal(report.http_turn_response_finished, false);
  assert.equal(report.http_turn_status, null); assert.equal(report.http_delete_status, null); assert.equal(report.local_resources_closed, true);
  assert.equal(seen.starts, 1); assert.equal(seen.closes, 1); assert.equal(report.stop_receipt_verified, true);
  assert.equal(report.api_abort_close_calls, 1); assert.equal(report.api_abort_close_binding_verified, true); assert.equal(report.api_abort_close_result_verified, true);
});
test('an observed abort with omitted API cleanup cannot borrow finally shutdown as success', async t => {
  t.mock.method(ExperimentalRuntimeApi.prototype, '_startTextTurn', async function(adapter, id, input, params, _req, res) {
    const controller = new AbortController(); res.once('close', () => { if (!res.writableFinished) controller.abort(); });
    // Deliberately broken API fixture: delivers a real disconnect signal but
    // never asks its owner to close. The production implementation is untouched.
    return adapter.startTurn(id, input, params, { signal: controller.signal });
  });
  const f = fixture('turn-disconnect');
  const report = await runHttpNativeTurnProbe(options('turn-disconnect'), { factories: f.factories, timeoutMs: 100, cleanupTimeoutMs: 150 });
  assert.equal(report.request_abort_observed, true); assert.equal(report.api_abort_close_calls, 0);
  assert.equal(report.api_abort_close_result_verified, false); assert.equal(report.checks_passed, false);
  assert.equal(report.stop_receipt_verified, false); assert.equal(report.deadline_dispatch_fenced, true);
});
test('API close preceding the probe AbortSignal observer is paired with that later real signal', async t => {
  t.mock.method(ExperimentalRuntimeApi.prototype, '_startTextTurn', async function(adapter, id, input, params, _req, res) {
    const controller = new AbortController(); let close;
    res.once('close', () => {
      if (res.writableFinished) return;
      // Force the adverse listener order: the API invokes its owner facade
      // before the probe's signal observer sees the same real socket close.
      close = adapter.closeSession(id); void close.catch(() => {});
      controller.abort();
    });
    const result = await adapter.startTurn(id, input, params, { signal: controller.signal });
    if (controller.signal.aborted) { await close; throw new Error('synthetic disconnected request'); }
    return result;
  });
  const { report, seen } = await run('turn-disconnect');
  assert.equal(report.checks_passed, true, JSON.stringify(report));
  assert.equal(report.api_close_before_abort_observer, true); assert.equal(report.request_abort_observed, true);
  assert.equal(report.api_abort_close_calls, 1); assert.equal(report.api_abort_close_binding_verified, true);
  assert.equal(report.api_abort_close_result_verified, true); assert.equal(report.http_turn_response_finished, false);
  assert.equal(seen.closes, 1);
});
test('late creation after total deadline dispatches no turn socket, arm or model request', async t => {
  const original = http.request; let turnRequests = 0;
  t.mock.method(http, 'request', function(args, ...rest) { if (args.path.endsWith('/turns')) turnRequests++;
    return original.call(this, args, ...rest); });
  const { report, seen } = await run('completed', { lateThread: true });
  assert.equal(report.checks_passed, false); assert.equal(report.deadline_dispatch_fenced, true);
  assert.equal(turnRequests, 0); assert.equal(seen.turns, 0); assert.equal(seen.arms, 0); assert.equal(seen.exchange, 0);
});
test('revocation failure terminal never becomes cancellation even when local resources close', async () => {
  const { report } = await run('turn-disconnect', { failedOnRevoke: true });
  assert.equal(report.checks_passed, false); assert.equal(report.provider_terminal_status, 'failed');
  assert.equal(report.cancellation_confirmed, false); assert.equal(report.stop_receipt_verified, false); assert.equal(report.local_resources_closed, true);
});
test('early completion is not an in-flight interrupt or disconnect and is never delayed by the observer', async () => {
  for (const scenario of ['interrupt', 'turn-disconnect']) {
    const { report } = await run(scenario, { fastComplete: true }); assert.equal(report.checks_passed, false);
    assert.equal(report.terminal_before_action, true); assert.equal(report.interrupt_dispatched, 0);
  }
});
test('missing dispatch, wrong output, unmatched terminal, ACK-only and close failures remain unconfirmed', async () => {
  for (const [scenario, settings] of [['completed', { noDispatch: true }], ['completed', { wrongText: true }],
    ['interrupt', { noTerminal: true }], ['interrupt', { wrongTerminal: true }],
    ['completed', { failClose: true }], ['completed', { receipt: { handles_closed_verified: false } }],
    ['completed', { drain: false }], ['completed', { exit: 4 }], ['completed', { badConfig: true }],
    ['completed', { counters: { upstream_attempts: 2 } }]]) {
    const { report } = await run(scenario, settings); assert.equal(report.checks_passed, false, JSON.stringify({ scenario, settings, report }));
    if (settings.failClose) { assert.equal(report.cleanup_pending, true); assert.equal(report.ownership_retained, true); }
  }
});
test('private local HTTP agent bypasses global proxy without process environment mutation', async t => {
  const original = http.request, agents = new Set();
  t.mock.method(http, 'request', function(args, ...rest) { assert.equal(args.host, '127.0.0.1'); assert.notEqual(args.agent, http.globalAgent);
    assert.deepEqual(Object.keys(args.agent.options.proxyEnv), []); agents.add(args.agent); return original.call(this, args, ...rest); });
  const { report } = await run('completed'); assert.equal(report.checks_passed, true); assert.equal(agents.size, 1);
});
test('CLI rejects implicit modes, extra args, relative paths and alternate input', () => {
  for (const argv of [[], ['--completed'], ['--completed', 'relative', 'a'.repeat(64), path.resolve('r.json')],
    ['--other', path.resolve('o.exe'), 'a'.repeat(64), path.resolve('r.json')],
    ['--completed', path.resolve('o.exe'), 'a'.repeat(64), 'relative'],
    ['--completed', path.resolve('o.exe'), 'a'.repeat(64), path.resolve('r.json'), 'arbitrary-input']]) assert.throws(() => parseHttpTurnProbeArgs(argv));
  assert.equal(parseHttpTurnProbeArgs(['--completed', path.resolve('o.exe'), 'a'.repeat(64), path.resolve('r.json')]).options.scenario, 'completed');
});
