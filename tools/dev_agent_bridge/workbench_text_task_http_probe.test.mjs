import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import http from 'node:http';
import path from 'node:path';
import test from 'node:test';
import { runHttpNativeProbe, parseHttpProbeArgs, HTTP_PROBE_FIXED_INPUT } from './workbench_text_task_http_probe.mjs';
import { TEXT_TASK_CLI_SHA256 } from './workbench_text_task_runtime_pin.mjs';
import { TEXT_TASK_MODEL } from './workbench_text_task_broker.mjs';

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
function fake(settings = {}) {
  const seen = { starts: 0, closes: 0, brokerCloses: 0, methods: [], threads: 0, armed: 0 };
  let owner; let drained = false;
  const factories = {
    createBroker() {
      return Object.freeze({ listen: async () => 'http://127.0.0.1:32123/v1',
        arm() { seen.armed++; }, revoke() {}, async close() { seen.brokerCloses++; drained = settings.drain !== false; },
        snapshot: () => ({ admitted_connections: 0, rejected_connections: 0, parsed_requests: 0, metadata_rejections: 0,
          rejected_requests: 0, upstream_attempts: settings.upstream ?? 0, response_released: false, drained, ...settings.broker }) });
    },
    createOwner(args) {
      seen.starts++;
      owner = { cleanupPending: true, diagnostics: { native_failure_code: settings.failureCode ?? null,
        native_owner_exit_code: null, native_close_receipt: null },
      ready: Promise.resolve({ attempt_id: args.attemptId, type: 'started', seq: 1, auth_mode: 'chatgpt',
        provider: 'p6_native_startup', cli_sha256: TEXT_TASK_CLI_SHA256, cwd: 'D:\\fixed\\project0', pid: 42,
        creation_time: '123456789', network_boundary_verified: true, child_identity_verified: true, job_singleton: true }),
      async verifyPeer() { return true; },
      async close() {
        seen.closes++;
        if (settings.failClose) throw new Error('PRIVATE TOKEN CLOSE');
        const value = { ...closed(), ...settings.receipt };
        owner.diagnostics.native_close_receipt = value; owner.diagnostics.native_owner_exit_code = settings.exit ?? 0;
        owner.cleanupPending = settings.cleanupPending ?? false;
        return value;
      } };
      return owner;
    },
    createClient() {
      class Client extends EventEmitter {
        isReady = false; notificationSequence = 0;
        async start() { this.isReady = true; }
        async request(method, params) {
          seen.methods.push(method);
          if (method === 'config/read') { const value = config(); if (settings.badConfig) value.config.features.respect_system_proxy = true; return value; }
          if (method === 'configRequirements/read') return { requirements: null };
          assert.equal(method, 'account/read'); assert.deepEqual(params, { refreshToken: false });
          return { account: { type: settings.account ?? 'chatgpt', email: 'PRIVATE ACCOUNT', token: 'PRIVATE TOKEN' } };
        }
        async startThread(params) {
          seen.threads++;
          if (settings.threadNever) await new Promise(() => {});
          return { thread: { id: 'synthetic-thread' }, cwd: params.cwd, model: TEXT_TASK_MODEL,
            modelProvider: 'p6_native_startup', approvalPolicy: 'never', sandbox: { type: 'readOnly' } };
        }
      }
      return new Client();
    },
  };
  return { factories, seen, timeoutMs: 1000, cleanupTimeoutMs: 100 };
}
function boundedReport(report) {
  const serialized = JSON.stringify(report);
  assert.doesNotMatch(serialized, /PRIVATE|TOKEN|ACCOUNT|fixed\\|synthetic-thread|message|email/);
  assert.ok(serialized.length < 8192);
  assert.equal(report.actual_native, false); assert.equal(report.evidence, 'synthetic');
  assert.equal(report.passed, false); assert.equal(report.production_isolation_passed, false);
  assert.equal(report.human_gate_passed, false);
}
async function run(scenario, settings) {
  const fixture = fake(settings);
  const report = await runHttpNativeProbe(options(scenario), {
    factories: fixture.factories, timeoutMs: fixture.timeoutMs, cleanupTimeoutMs: fixture.cleanupTimeoutMs });
  boundedReport(report); return { report, seen: fixture.seen };
}

test('session-close uses real local HTTP with a strict no-turn v2 receipt and zero model work', async () => {
  const { report, seen } = await run('session-close');
  assert.equal(report.checks_passed, true, JSON.stringify(report)); assert.equal(report.http_create_status, 200);
  assert.equal(report.http_delete_status, 200); assert.equal(report.delete_requests, 1);
  assert.equal(report.execution_receipt_verified, true); assert.equal(report.stop_receipt_verified, true);
  assert.equal(report.request_abort_observed, false); assert.equal(report.cleanup_pending, false);
  assert.equal(report.http_server_closed, true); assert.equal(seen.starts, 1); assert.equal(seen.closes, 1);
  assert.equal(seen.armed, 0); assert.deepEqual(seen.methods, ['config/read', 'configRequirements/read', 'account/read']);
  assert.equal(HTTP_PROBE_FIXED_INPUT, 'Reply exactly: P6_R7_NATIVE_OK');
});

test('probe HTTP uses one private direct-loopback Agent with empty proxyEnv and destroys it', async t => {
  const original = http.request; const agents = new Set(); let destroyed = 0;
  t.mock.method(http, 'request', function(options, ...args) {
    assert.equal(options.host, '127.0.0.1');
    assert.notEqual(options.agent, http.globalAgent); assert.ok(options.agent instanceof http.Agent);
    assert.deepEqual(Object.keys(options.agent.options.proxyEnv), []);
    if (!agents.has(options.agent)) {
      agents.add(options.agent); const originalDestroy = options.agent.destroy;
      t.mock.method(options.agent, 'destroy', function() { destroyed++; return originalDestroy.call(this); });
    }
    return original.call(this, options, ...args);
  });
  const { report } = await run('session-close');
  assert.equal(report.checks_passed, true); assert.equal(agents.size, 1); assert.equal(destroyed, 1);
});

test('create-disconnect holds the returned thread until actual server signal and cannot issue a success receipt', async () => {
  const { report, seen } = await run('create-disconnect');
  assert.equal(report.checks_passed, true); assert.equal(report.client_disconnect, true);
  assert.equal(report.request_abort_observed, true); assert.equal(report.held_thread_released_after_abort, true);
  assert.equal(report.execution_receipt_issued, false); assert.equal(report.stop_receipt_verified, false);
  assert.equal(report.http_create_status, null); assert.equal(report.delete_requests, 0);
  assert.equal(report.handler_settled, true); assert.equal(report.cleanup_pending, false);
  assert.equal(seen.starts, 1); assert.equal(seen.threads, 1); assert.equal(seen.closes, 1);
});

test('host-graceful uses permanent Bridge shutdown and retrieves the existing no-turn tombstone without DELETE', async () => {
  const { report, seen } = await run('host-graceful');
  assert.equal(report.checks_passed, true, JSON.stringify(report)); assert.equal(report.tombstone_verified, true);
  assert.equal(report.host_shutdown_verified, true); assert.equal(report.stop_receipt_verified, true);
  assert.equal(report.delete_requests, 0); assert.equal(report.http_delete_status, null);
  assert.equal(seen.starts, 1); assert.equal(seen.closes, 1);
});

test('configuration/account rejection produces no positive receipt while closing the same owner', async () => {
  for (const settings of [{ badConfig: true }, { account: 'apiKey' }]) {
    const { report, seen } = await run('session-close', settings);
    assert.equal(report.checks_passed, false); assert.equal(report.execution_receipt_issued, false);
    assert.equal(report.stop_receipt_verified, false); assert.equal(report.cleanup_pending, false);
    assert.equal(report.http_create_status, settings.account ? 401 : 503); assert.equal(seen.starts, 1); assert.equal(seen.closes, 1);
  }
});

test('native closure, exit and broker drain failures remain distinct from HTTP completion', async () => {
  for (const settings of [{ receipt: { handles_closed_verified: false } }, { failClose: true },
    { cleanupPending: true }, { drain: false }, { exit: 3 }, { upstream: 1 }]) {
    const { report, seen } = await run('session-close', settings);
    assert.equal(report.checks_passed, false); assert.equal(seen.starts, 1);
    if (settings.failClose) { assert.equal(report.cleanup_pending, true); assert.equal(report.process_close_observed, false); }
    if (settings.drain === false) assert.equal(report.broker.drained, false);
    if (settings.exit) assert.equal(report.native_owner_exit_code, 3);
    if (settings.upstream) assert.equal(report.broker.upstream_attempts, 1);
  }
});

test('finite native diagnostics retain allowed stages and numeric Win32 values only', async () => {
  for (const [value, expected] of [['task_helper_shell_execute_win32_1223', 'task_helper_shell_execute_win32_1223'],
    ['task_files_dedicated_pin_canonical_rejected', 'task_files_dedicated_pin_canonical_rejected'],
    ['task_helper_shell_execute_win32_4294967296', null], ['task_PRIVATE_TOKEN_failed', null], ['PRIVATE PATH', null]]) {
    const { report } = await run('host-graceful', { failureCode: value });
    assert.equal(report.native_failure_code, expected);
  }
});

test('bounded local models metadata 404s are allowed; unexpected or rejected requests cannot pass', async () => {
  for (const n of [2, 8]) {
    const { report } = await run('session-close', { broker: { admitted_connections: n, parsed_requests: n, metadata_rejections: n } });
    assert.equal(report.checks_passed, true); assert.equal(report.broker.upstream_attempts, 0);
    assert.equal(report.broker.response_released, false); assert.equal(report.broker_arm_attempts, 0);
  }
  for (const broker of [{ parsed_requests: 1, admitted_connections: 1 }, { rejected_requests: 1 },
    { rejected_connections: 1 }, { admitted_connections: 1 },
    { admitted_connections: 9, parsed_requests: 9, metadata_rejections: 9 }, { parsed_requests: -1 },
    { admitted_connections: 1, parsed_requests: 2, metadata_rejections: 2 }]) {
    const { report } = await run('session-close', { broker }); assert.equal(report.checks_passed, false);
  }
});

test('deadline closes the held owner and keeps unknown pending creation unconfirmed', async () => {
  const fixture = fake({ threadNever: true });
  const report = await runHttpNativeProbe(options('create-disconnect'), {
    factories: fixture.factories, timeoutMs: 30, cleanupTimeoutMs: 30 });
  boundedReport(report); assert.equal(report.code, 'http_probe_deadline');
  assert.equal(report.checks_passed, false); assert.equal(report.handler_settled, false);
  assert.equal(report.execution_receipt_issued, false); assert.equal(fixture.seen.starts, 1);
  assert.ok(fixture.seen.closes >= 1); assert.equal(report.host_shutdown_verified, false);
});

test('CLI requires an explicit finite scenario and absolute executable/report paths and a lowercase pin', async () => {
  const pin = 'a'.repeat(64); const executable = path.resolve('owner.exe'); const report = path.resolve('report.json');
  assert.deepEqual(parseHttpProbeArgs(['--session-close', executable, pin, report]),
    { options: { scenario: 'session-close', executable, sha256: pin }, reportPath: report });
  for (const args of [[], ['--completed', executable, pin, report], ['--session-close', 'relative.exe', pin, report],
    ['--session-close', executable, pin.toUpperCase(), report], ['--host-graceful', executable, pin, 'relative.json'],
    ['--session-close', executable, pin, report, 'extra']]) assert.throws(() => parseHttpProbeArgs(args));
  const fixture = fake();
  await assert.rejects(runHttpNativeProbe({ ...options('session-close'), arbitrary: true }, { factories: fixture.factories }));
  await assert.rejects(runHttpNativeProbe(options('session-close'), { factories: fixture.factories, actual_native: true }));
  assert.equal(fixture.seen.starts, 0);
});
