// Explicit candidate HTTP lifecycle acceptance. These scenarios never start a
// model turn; injected resources produce synthetic evidence only.
import http from 'node:http';
import { randomUUID } from 'node:crypto';
import { openSync, writeFileSync, closeSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { ExperimentalRuntimeApi, EXPERIMENTAL_RUNTIME_PREFIX } from './experimental_runtime_api.mjs';
import { WorkbenchTextTaskRuntimeAdapter } from './workbench_text_task_runtime_adapter.mjs';
import { createBridgeRuntimeShutdown } from './bridge_runtime_shutdown.mjs';
import { createTextTaskBroker } from './workbench_text_task_broker.mjs';
import { launchWorkbenchTextNativeExecutor } from './workbench_text_task_native_executor.mjs';
import { CodexAppServerClient } from './codex_app_server_client.mjs';

export const HTTP_PROBE_FIXED_INPUT = 'Reply exactly: P6_R7_NATIVE_OK';
const SCENARIOS = ['session-close', 'create-disconnect', 'host-graceful'];
const PROFILE = 'workbench_text_only_v1';
const FACTS = ['process_close_observed', 'job_empty_verified', 'stdio_eof_verified',
  'rules_absent_verified', 'handles_closed_verified', 'helper_exits_verified'];
const COUNTERS = ['admitted_connections', 'rejected_connections', 'parsed_requests',
  'metadata_rejections', 'rejected_requests', 'upstream_attempts'];
const STAGES = new Set(('preflight files_source_parent files_owner_pin files_root files_attempt files_cli_source files_cli_copy '
  + 'files_work_create files_cli_pin files_work_pin files_dedicated_pin files_dedicated_binding files_cwd_check files_home_check '
  + 'files_ready job_create job_limits job_limits_readback job_empty_readback job_ready journal_prepared boundary_blob '
  + 'install_helper stdio_create child_create child_preflight child_attributes child_job_attribute child_stdio_attribute '
  + 'child_spawn child_creation_time child_binding child_stdio_parent_close child_journal child_resume started_emit runtime unknown '
  + 'helper_preflight helper_shell_execute helper_process_binding helper_ready_wait helper_ready_live helper_image helper_token '
  + 'helper_lease helper_ack helper_exit_wait helper_exit_binding helper_exit_query helper_exit_status helper_receipt_read '
  + 'helper_receipt_validate helper_handle_close').split(' '));
const fail = code => Object.assign(new Error(code), { code });
const check = (condition, code) => { if (!condition) throw fail(code); };
const exact = (value, keys) => value !== null && typeof value === 'object' && !Array.isArray(value)
  && Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
const count = value => Number.isSafeInteger(value) && value >= 0 && value <= 65535 ? value : null;
function bump(report, key) { report[key] = Math.min(65535, report[key] + 1); }
const deferred = () => Promise.withResolvers();
function within(promise, milliseconds) {
  let timer;
  return Promise.race([promise, new Promise((_, reject) => {
    timer = setTimeout(() => reject(fail('http_probe_deadline')), milliseconds);
  })]).finally(() => clearTimeout(timer));
}
function wrap(target, methods) {
  // Use a facade so frozen broker method properties remain unmodified.
  return new Proxy(Object.create(null), { get(_facade, key) {
    if (Object.hasOwn(methods, key)) return methods[key];
    const value = Reflect.get(target, key, target);
    return typeof value === 'function' ? value.bind(target) : value;
  } });
}
function safeNativeCode(value) {
  if (typeof value !== 'string' || value.length > 80) return null;
  for (const stage of STAGES) {
    const prefix = `task_${stage}_`; if (!value.startsWith(prefix)) continue;
    const family = value.slice(prefix.length);
    if (['failed', 'canonical_rejected', 'path_type_rejected', 'rejected', 'access_denied', 'io_failed', 'security_denied'].includes(family)) return value;
    const number = /^win32_(0|[1-9][0-9]{0,9})$/.exec(family);
    if (number && Number(number[1]) <= 0xffffffff) return value;
  }
  return null;
}
function sessionBinding(value, epoch) {
  if (!exact(value, ['session_id', 'status', 'provider_metadata', 'execution_profile_receipt'])) return null;
  const receipt = value.execution_profile_receipt;
  if (typeof value.session_id !== 'string' || !/^[a-f0-9-]{36}$/.test(value.session_id)
      || value.status !== 'idle' || !exact(value.provider_metadata, ['provider', 'provider_session_id'])
      || value.provider_metadata.provider !== 'codex'
      || !exact(receipt, ['profile', 'version', 'local_session_id', 'execution_epoch', 'provider_thread_id', 'isolation_verified', 'tools_disabled'])
      || receipt.profile !== PROFILE || receipt.version !== 2 || receipt.local_session_id !== value.session_id
      || receipt.execution_epoch !== epoch || typeof receipt.provider_thread_id !== 'string'
      || !receipt.provider_thread_id || receipt.provider_thread_id.length > 256
      || receipt.provider_thread_id !== value.provider_metadata.provider_session_id
      || receipt.isolation_verified !== true || receipt.tools_disabled !== true) return null;
  return { id: value.session_id, epoch, thread: receipt.provider_thread_id };
}
function noTurnReceipt(value, binding) {
  if (!binding || !exact(value, ['status', 'stop_receipt']) || value.status !== 'closed') return false;
  const expected = { profile: PROFILE, version: 2, local_session_id: binding.id, execution_epoch: binding.epoch,
    provider_thread_id: binding.thread, local_turn_id: null, turn_id: null, outcome: 'closed_without_turn',
    interrupt_dispatched: false, interrupt_dispatch_sequence: null, provider_terminal_confirmed: false,
    provider_terminal_status: null, provider_terminal_sequence: null, cancellation_confirmed: false,
    local_child_close_observed: true, proxy_drained: true };
  return exact(value.stop_receipt, Object.keys(expected))
    && Object.entries(expected).every(([key, item]) => value.stop_receipt[key] === item);
}
function validateOptions(options) {
  check(exact(options, ['executable', 'sha256', 'scenario']) && typeof options.executable === 'string'
    && path.isAbsolute(options.executable) && /^[a-f0-9]{64}$/.test(options.sha256)
    && SCENARIOS.includes(options.scenario), 'http_probe_options_invalid');
}

export async function runHttpNativeProbe(options, injected) {
  validateOptions(options);
  const { executable, sha256, scenario } = options;
  if (injected !== undefined) check(injected && typeof injected === 'object'
    && Object.keys(injected).every(key => ['factories', 'timeoutMs', 'cleanupTimeoutMs'].includes(key))
    && exact(injected.factories, ['createBroker', 'createOwner', 'createClient'])
    && Object.values(injected.factories).every(value => typeof value === 'function'), 'http_probe_injection_invalid');
  const timeoutMs = injected?.timeoutMs ?? 180000;
  const cleanupTimeoutMs = injected?.cleanupTimeoutMs ?? 150000;
  check([timeoutMs, cleanupTimeoutMs].every(value => Number.isSafeInteger(value) && value >= 20 && value <= 300000), 'http_probe_deadline_invalid');
  const underlying = injected?.factories ?? { createBroker: createTextTaskBroker,
    createOwner: launchWorkbenchTextNativeExecutor, createClient: options => new CodexAppServerClient(options) };
  const report = { schema: 'p6_r7_http_native_probe_v1', scenario, supervisor_sha256: sha256,
    scope: 'candidate_http_no_model_only', evidence: injected ? 'synthetic' : 'native_candidate', actual_native: false,
    attempt_id: null, owner_count: 0, owner_ready: false, owner_close_calls: 0, client_started: false,
    config_read: false, requirements_read: false, cached_account_read: false, thread_returned: false,
    execution_receipt_issued: false, execution_receipt_verified: false, stop_receipt_verified: false,
    http_create_status: null, http_delete_status: null, delete_requests: 0, client_disconnect: false,
    request_abort_observed: false, held_thread_released_after_abort: false, handler_settled: false,
    host_shutdown_verified: false, http_server_closed: false, tombstone_verified: false,
    model_start_attempts: 0, broker_arm_attempts: 0, host_requests: 0, generic_factory_calls: 0,
    broker: null, native_failure_present: false, native_failure_code: null, native_owner_exit_code: null,
    ...Object.fromEntries(FACTS.map(key => [key, false])), cleanup_pending: true,
    checks_passed: false, passed: false, code: null, failure_stage: null,
    production_isolation_passed: false, human_gate_passed: false };
  const epoch = randomUUID(); const held = deferred(); const release = deferred(); const aborted = deferred();
  let owner; let broker; let adapter; let binding; let nativeClosed = false; let stage = 'http_listen';
  const handlers = new Set(); const requests = new Set(); const sockets = new Map();
  // Node 24's explicit proxyEnv is read only from this private Agent. An empty
  // map gives it no proxy, independently of --use-env-proxy/globalAgent.
  const localAgent = new http.Agent({ keepAlive: false, proxyEnv: Object.freeze(Object.create(null)) });
  const factories = {
    createBroker(args) {
      check(!broker, 'http_probe_multiple_resources'); broker = underlying.createBroker(args);
      return wrap(broker, { arm() { bump(report, 'broker_arm_attempts'); throw fail('http_probe_model_forbidden'); } });
    },
    createOwner(args) {
      bump(report, 'owner_count'); check(report.owner_count === 1, 'http_probe_multiple_resources');
      report.attempt_id = args.attemptId; owner = underlying.createOwner(args);
      const ready = owner.ready.then(value => { report.owner_ready = true; return value; });
      void ready.catch(() => {});
      return wrap(owner, { ready, close: async () => {
        bump(report, 'owner_close_calls'); const receipt = await owner.close();
        nativeClosed = FACTS.every(key => receipt?.[key] === true) && receipt.cleanup_pending === false && owner.cleanupPending === false;
        return receipt;
      } });
    },
    createClient(args) {
      const client = underlying.createClient(args);
      client.on('serverRequest', () => bump(report, 'host_requests'));
      return wrap(client, {
        start: async () => { const result = await client.start(); report.client_started = true; return result; },
        request: async (method, params, ...rest) => {
          if (method === 'turn/start') { bump(report, 'model_start_attempts'); throw fail('http_probe_model_forbidden'); }
          const result = await client.request(method, params, ...rest);
          if (method === 'config/read') report.config_read = true;
          if (method === 'configRequirements/read') report.requirements_read = true;
          if (method === 'account/read') report.cached_account_read = params?.refreshToken === false;
          return result;
        },
        startThread: async params => {
          const result = await client.startThread(params); report.thread_returned = true;
          if (scenario === 'create-disconnect') { held.resolve(); await release.promise; }
          return result;
        },
      });
    },
  };
  const api = new ExperimentalRuntimeApi({ enabled: true, adapterFactory: () => {
    bump(report, 'generic_factory_calls'); throw fail('http_probe_generic_forbidden');
  }, textAdapterFactory: () => {
    check(!adapter, 'http_probe_multiple_resources');
    adapter = new WorkbenchTextTaskRuntimeAdapter({ nativeOptions: { executable, sha256 }, factories });
    return wrap(adapter, { startSession: async (config, manifest, options) => {
      const observe = () => { report.request_abort_observed = true; aborted.resolve(); };
      options.signal.addEventListener('abort', observe, { once: true });
      try {
        const result = await adapter.startSession(config, manifest, options);
        report.execution_receipt_issued = true; return result;
      } finally { options.signal.removeEventListener('abort', observe); }
    } });
  } });
  const server = http.createServer((req, res) => {
    const operation = Promise.resolve().then(() => api.handle(req, res, new URL(req.url, 'http://127.0.0.1')));
    handlers.add(operation);
    void operation.then(() => {}, () => {}).finally(() => handlers.delete(operation));
  });
  server.on('connection', socket => {
    const closed = deferred(); sockets.set(socket, closed.promise);
    socket.once('close', () => { sockets.delete(socket); closed.resolve(); });
  });
  const shutdown = createBridgeRuntimeShutdown({ runtimeApi: api, server, httpGraceMs: 1000 });
  function request(method, suffix, body) {
    const payload = body === undefined ? null : Buffer.from(JSON.stringify(body));
    const req = http.request({ host: '127.0.0.1', port: server.address().port,
      path: `${EXPERIMENTAL_RUNTIME_PREFIX}${suffix}`, method, agent: localAgent,
      headers: payload ? { 'content-type': 'application/json', 'content-length': payload.length } : {} });
    requests.add(req); req.once('close', () => requests.delete(req));
    const promise = new Promise((resolve, reject) => {
      req.once('error', () => reject(fail('http_probe_request_failed')));
      req.once('response', res => {
        const chunks = []; let size = 0;
        res.on('data', chunk => {
          size += chunk.length;
          if (size > 16384) { req.destroy(); reject(fail('http_probe_response_limit')); }
          else chunks.push(chunk);
        });
        res.once('aborted', () => reject(fail('http_probe_response_aborted')));
        res.once('error', () => reject(fail('http_probe_request_failed')));
        res.once('end', () => {
          try { resolve({ status: res.statusCode, body: JSON.parse(Buffer.concat(chunks).toString('utf8')) }); }
          catch { reject(fail('http_probe_response_invalid')); }
        });
      });
    });
    void promise.catch(() => {}); req.end(payload); return { req, promise };
  }
  const flow = (async () => {
    await new Promise((resolve, reject) => { server.once('error', () => reject(fail('http_probe_listen_failed'))); server.listen(0, '127.0.0.1', resolve); });
    stage = 'http_create';
    const create = request('POST', '/sessions', { config: { runtime_profile: PROFILE },
      context_manifest: { execution_epoch: epoch } });
    if (scenario === 'create-disconnect') {
      stage = 'thread_hold'; await Promise.race([held.promise, create.promise.then(() => { throw fail('http_probe_create_ended_before_hold'); })]);
      create.req.destroy(); report.client_disconnect = true;
      stage = 'abort_observation'; await aborted.promise;
      report.held_thread_released_after_abort = true; release.resolve();
      await Promise.allSettled([...handlers]); report.handler_settled = true;
      check(!report.execution_receipt_issued, 'http_probe_receipt_unexpected');
    } else {
      const created = await create.promise; report.http_create_status = created.status;
      binding = sessionBinding(created.body, epoch);
      report.execution_receipt_verified = created.status === 200 && binding !== null;
      check(report.execution_receipt_verified, 'http_probe_execution_receipt_invalid');
      if (scenario === 'session-close') {
        stage = 'http_delete'; report.delete_requests++;
        const deleted = await request('DELETE', `/sessions/${binding.id}`).promise;
        report.http_delete_status = deleted.status;
        report.stop_receipt_verified = deleted.status === 200 && noTurnReceipt(deleted.body, binding);
        check(report.stop_receipt_verified, 'http_probe_stop_receipt_invalid');
      } else {
        stage = 'host_shutdown'; const closed = await shutdown.shutdown();
        report.host_shutdown_verified = closed.runtime_closed === true && closed.http_server_closed === true;
        const tombstone = await adapter.closeSession(binding.id);
        report.tombstone_verified = noTurnReceipt(tombstone, binding);
        report.stop_receipt_verified = report.tombstone_verified;
        check(report.host_shutdown_verified && report.tombstone_verified, 'http_probe_stop_receipt_invalid');
      }
    }
  })();
  void flow.catch(() => {});
  try { await within(flow, timeoutMs); }
  catch (error) {
    report.failure_stage = stage;
    report.code = ['http_probe_deadline', 'http_probe_execution_receipt_invalid', 'http_probe_stop_receipt_invalid',
      'http_probe_receipt_unexpected'].includes(error?.code) ? error.code : 'http_probe_failed';
  } finally {
    for (const req of requests) req.destroy();
    localAgent.destroy();
    release.resolve();
    // Permanent stop fences late creation before its continuation can acquire
    // another resource. Never turn a deadline into native close evidence.
    try {
      const closed = await within(shutdown.shutdown(), cleanupTimeoutMs);
      report.host_shutdown_verified = closed.runtime_closed === true && closed.http_server_closed === true;
    } catch { if (!report.code) report.code = 'http_probe_cleanup_unconfirmed'; }
    if (owner && !nativeClosed) {
      try {
        bump(report, 'owner_close_calls');
        const receipt = await within(owner.close(), cleanupTimeoutMs);
        nativeClosed = FACTS.every(key => receipt?.[key] === true) && receipt.cleanup_pending === false && owner.cleanupPending === false;
      } catch { /* Same owner remains unconfirmed. */ }
    }
    if (broker) {
      try { broker.revoke(); await within(broker.close(), cleanupTimeoutMs); } catch { /* Report drain false. */ }
    }
    if (server.listening) { for (const socket of sockets.keys()) socket.destroy(); server.close(); }
    try { await within(Promise.allSettled([flow, ...handlers]), cleanupTimeoutMs); report.handler_settled = true; }
    catch { if (!report.code) report.code = 'http_probe_cleanup_unconfirmed'; }
    try { await within(Promise.all([...sockets.values()]), 1000); } catch { /* A close request is not a close event. */ }
    report.http_server_closed = !server.listening && sockets.size === 0;
    const diagnostics = owner?.diagnostics;
    report.native_failure_present = diagnostics?.native_failure_code != null;
    report.native_failure_code = safeNativeCode(diagnostics?.native_failure_code);
    const exit = diagnostics?.native_owner_exit_code;
    report.native_owner_exit_code = Number.isInteger(exit) && exit >= -0x80000000 && exit <= 0xffffffff ? exit : null;
    for (const key of FACTS) report[key] = diagnostics?.native_close_receipt?.[key] === true;
    report.cleanup_pending = !owner || owner.cleanupPending !== false || !nativeClosed;
    const snapshot = broker?.snapshot();
    report.broker = { ...Object.fromEntries(COUNTERS.map(key => [key, count(snapshot?.[key])])),
      response_released: snapshot?.response_released === true, drained: snapshot?.drained === true };
    report.actual_native = !injected && report.owner_ready;
    const noModel = report.model_start_attempts === 0 && report.broker_arm_attempts === 0
      && COUNTERS.every(key => report.broker[key] !== null) && !report.broker.response_released
      && report.broker.upstream_attempts === 0 && report.broker.rejected_connections === 0
      && report.broker.rejected_requests === 0 && report.broker.metadata_rejections <= 8
      && report.broker.parsed_requests === report.broker.metadata_rejections
      // The existing broker permits one request per admitted connection and
      // answers its sole allowed metadata GET locally with 404.
      && report.broker.admitted_connections === report.broker.metadata_rejections;
    report.checks_passed = report.code === null && report.owner_count === 1 && report.owner_ready
      && report.client_started && report.config_read && report.requirements_read && report.cached_account_read && report.thread_returned
      && FACTS.every(key => report[key]) && report.native_owner_exit_code === 0 && !report.native_failure_present
      && !report.cleanup_pending && report.broker.drained
      && noModel && report.host_requests === 0 && report.generic_factory_calls === 0
      && report.http_server_closed && report.handler_settled && report.host_shutdown_verified
      && (scenario === 'create-disconnect'
        ? report.client_disconnect && report.request_abort_observed && report.held_thread_released_after_abort
          && !report.execution_receipt_issued && !report.execution_receipt_verified && !report.stop_receipt_verified && report.delete_requests === 0
        : report.execution_receipt_issued && report.execution_receipt_verified && report.stop_receipt_verified
          && (scenario === 'host-graceful' ? report.tombstone_verified && report.delete_requests === 0 : report.http_delete_status === 200));
    report.passed = !injected && report.checks_passed;
  }
  return JSON.parse(JSON.stringify(report));
}

export function parseHttpProbeArgs(argv) {
  check(Array.isArray(argv) && argv.length === 4 && SCENARIOS.map(value => `--${value}`).includes(argv[0])
    && typeof argv[3] === 'string' && path.isAbsolute(argv[3]), 'http_probe_explicit_mode_required');
  const options = { executable: argv[1], sha256: argv[2], scenario: argv[0].slice(2) };
  validateOptions(options); return { options, reportPath: argv[3] };
}
export async function main(argv = process.argv.slice(2)) {
  const { options, reportPath } = parseHttpProbeArgs(argv);
  // Reserve the exclusive report before acquiring any native resources.
  const descriptor = openSync(reportPath, 'wx');
  try {
    const report = await runHttpNativeProbe(options);
    const raw = `${JSON.stringify(report)}\n`; writeFileSync(descriptor, raw); process.stdout.write(raw);
    process.exitCode = report.passed ? 0 : 2;
  } finally { closeSync(descriptor); }
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) await main();
