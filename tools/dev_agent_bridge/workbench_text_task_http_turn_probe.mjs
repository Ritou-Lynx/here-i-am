// Explicit candidate HTTP turn acceptance. Never imported by production routes.
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
import { createNativeProbeExchange, createNativeProbeNotificationSummary } from './workbench_text_task_authenticated_probe.mjs';
import { exchangeTextOnly } from './workbench_text_gate_transport.mjs';

export const HTTP_TURN_FIXED_INPUT = 'Reply exactly: P6_R7_NATIVE_OK';
const SCENARIOS = ['completed', 'interrupt', 'turn-disconnect'];
// Failed cleanup retains the original resource objects for this process lifetime.
// An attempt never becomes cleanup proof merely because its deadline expired.
const retained = new Map();
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
function within(promise, milliseconds, onTimeout = null) {
  let timer;
  return Promise.race([promise, new Promise((_, reject) => {
    timer = setTimeout(() => { onTimeout?.(); reject(fail('http_probe_deadline')); }, milliseconds);
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

function turnBinding(value, binding) {
  check(exact(value, ['local_session_id', 'provider_thread_id', 'execution_epoch', 'local_turn_id', 'provider_turn_id'])
    && value.local_session_id === binding.id && value.execution_epoch === binding.epoch
    && value.provider_thread_id === binding.thread && typeof value.local_turn_id === 'string'
    && /^[a-f0-9-]{36}$/.test(value.local_turn_id) && typeof value.provider_turn_id === 'string'
    && value.provider_turn_id.length > 0 && value.provider_turn_id.length <= 256, 'http_turn_binding_invalid');
  return { local: value.local_turn_id, provider: value.provider_turn_id };
}
function stopReceipt(value, binding, turn, expected) {
  const r = value?.stop_receipt;
  return exact(value, ['status', 'stop_receipt']) && value.status === 'closed'
    && exact(r, ['profile', 'version', 'local_session_id', 'execution_epoch', 'provider_thread_id', 'local_turn_id', 'turn_id', 'outcome',
      'interrupt_dispatched', 'interrupt_dispatch_sequence', 'provider_terminal_confirmed', 'provider_terminal_status',
      'provider_terminal_sequence', 'cancellation_confirmed', 'local_child_close_observed', 'proxy_drained'])
    && r.profile === PROFILE && r.version === 2 && Number.isSafeInteger(r.provider_terminal_sequence) && r.provider_terminal_sequence >= 0
    && r.local_session_id === binding.id && r.execution_epoch === binding.epoch && r.provider_thread_id === binding.thread
    && r.local_turn_id === turn.local && r.turn_id === turn.provider && r.provider_terminal_confirmed === true
    && r.provider_terminal_status === expected && r.local_child_close_observed === true && r.proxy_drained === true
    && r.outcome === 'closed'
    && (expected === 'interrupted' ? r.interrupt_dispatched === true && Number.isSafeInteger(r.interrupt_dispatch_sequence) && r.interrupt_dispatch_sequence >= 0
      && r.cancellation_confirmed === true && r.provider_terminal_sequence > r.interrupt_dispatch_sequence
      : r.interrupt_dispatched === false && r.interrupt_dispatch_sequence === null && r.cancellation_confirmed === false);
}
function validateOptions(options) {
  check(exact(options, ['executable', 'sha256', 'scenario']) && typeof options.executable === 'string'
    && path.isAbsolute(options.executable) && /^[a-f0-9]{64}$/.test(options.sha256)
    && SCENARIOS.includes(options.scenario), 'http_turn_options_invalid');
}

export async function runHttpNativeTurnProbe(options, injected) {
  validateOptions(options);
  if (injected !== undefined) check(exact(injected, ['factories', 'timeoutMs', 'cleanupTimeoutMs'])
    && exact(injected.factories, ['createBroker', 'createOwner', 'createClient', 'exchange'])
    && Object.values(injected.factories).every(value => typeof value === 'function'), 'http_turn_injection_invalid');
  const timeoutMs = injected?.timeoutMs ?? 210000, cleanupTimeoutMs = injected?.cleanupTimeoutMs ?? 150000;
  check([timeoutMs, cleanupTimeoutMs].every(value => Number.isSafeInteger(value) && value >= 20 && value <= 300000), 'http_turn_deadline_invalid');
  const { executable, sha256, scenario } = options;
  const report = { schema: 'p6_r7_http_turn_probe_v1', scenario, supervisor_sha256: sha256,
    scope: 'candidate_http_one_fixed_text_turn', evidence: injected ? 'synthetic' : 'native_candidate', actual_native: false,
    attempt_id: null, owner_count: 0, owner_ready: false, owner_close_calls: 0,
    config_read: false, requirements_read: false, cached_account_read: false, thread_returned: false,
    execution_receipt_verified: false, turn_binding_verified: false, stop_receipt_verified: false,
    http_create_status: null, http_turn_status: null, http_interrupt_status: null, http_delete_status: null,
    http_turn_response_finished: false, turn_result_held: false, client_disconnect: false,
    request_abort_observed: false, held_result_released_after_abort: false,
    api_abort_close_calls: 0, api_abort_close_binding_verified: false, api_abort_close_result_verified: false,
    api_close_before_abort_observer: false,
    deadline_dispatch_fenced: false,
    broker_arm_attempts: 0, model_start_attempts: 0, start_dispatched: 0, interrupt_attempts: 0,
    interrupt_dispatched: 0, interrupt_acknowledged: false, interrupt_binding_verified: false, upstream_before_action: null,
    exchange_started: 0, exchange_settled: 0, exchange_abort_observed: false, exchange_inflight_before_action: false,
    cancellation_confirmed: false, local_resources_closed: false,
    provider_terminal_status: null, terminal_before_action: false, event_terminal_verified: false,
    fixed_text_observed: false, text_empty: true, text_after_terminal: false, event_count: 0,
    host_requests: 0, generic_factory_calls: 0, broker: null, notifications: null, exchange_failure: null,
    native_failure_present: false, native_failure_code: null, native_owner_exit_code: null,
    ...Object.fromEntries(FACTS.map(key => [key, false])), cleanup_pending: true, ownership_retained: false,
    handler_settled: false, http_server_closed: false, host_shutdown_verified: false,
    checks_passed: false, passed: false, code: null, failure_stage: null,
    production_isolation_passed: false, human_gate_passed: false };
  const underlying = injected?.factories ?? { createBroker: createTextTaskBroker, exchange: exchangeTextOnly,
    createOwner: launchWorkbenchTextNativeExecutor, createClient: args => new CodexAppServerClient(args) };
  const exchange = createNativeProbeExchange(report, { exchange: underlying.exchange });
  const epoch = randomUUID(), held = deferred(), release = deferred(), aborted = deferred(), apiAbortClose = deferred();
  const notifications = createNativeProbeNotificationSummary();
  const terminals = [];
  let owner, broker, adapter, binding, turn, client, nativeClosed = false, stopping = false, stage = 'listen';
  const deadline = Date.now() + timeoutMs;
  const fenceDeadline = () => { stopping = true; report.deadline_dispatch_fenced = true; };
  const dispatchOpen = () => { if (Date.now() >= deadline) fenceDeadline(); return !stopping; };
  const handlers = new Set(), requests = new Set(), sockets = new Set();
  const localAgent = new http.Agent({ keepAlive: false, proxyEnv: Object.freeze(Object.create(null)) });
  const factories = {
    createBroker(args) {
      check(!broker, 'http_turn_multiple_resources'); broker = underlying.createBroker({ ...args, exchange: async (outgoing, options) => {
        bump(report, 'exchange_started'); check(report.exchange_started === 1, 'http_turn_multiple_exchanges');
        const observe = () => { report.exchange_abort_observed = true; };
        options.signal.addEventListener('abort', observe, { once: true });
        if (options.signal.aborted) observe();
        try { return await exchange(outgoing, options); }
        finally { bump(report, 'exchange_settled'); options.signal.removeEventListener('abort', observe); }
      } });
      return wrap(broker, { arm(input) {
        bump(report, 'broker_arm_attempts');
        check(report.broker_arm_attempts === 1 && input === HTTP_TURN_FIXED_INPUT, 'http_turn_input_rejected');
        return broker.arm(input);
      } });
    },
    createOwner(args) {
      bump(report, 'owner_count'); check(report.owner_count === 1, 'http_turn_multiple_resources');
      report.attempt_id = args.attemptId; owner = underlying.createOwner(args);
      const ready = owner.ready.then(value => { report.owner_ready = true; return value; }); void ready.catch(() => {});
      return wrap(owner, { ready, close: async () => {
        bump(report, 'owner_close_calls'); const receipt = await owner.close();
        nativeClosed = FACTS.every(key => receipt?.[key] === true) && receipt.cleanup_pending === false && owner.cleanupPending === false;
        return receipt;
      } });
    },
    createClient(args) {
      client = underlying.createClient(args); client.on('serverRequest', () => bump(report, 'host_requests'));
      client.on('notification', entry => {
        notifications.observe(entry);
        const p = entry?.message?.params;
        if (entry?.message?.method === 'item/agentMessage/delta' && typeof p?.delta === 'string' && p.delta.length) report.text_empty = false;
        if (entry?.message?.method === 'turn/completed' && terminals.length < 32
          && typeof p?.threadId === 'string' && p.threadId.length <= 256 && typeof p?.turn?.id === 'string' && p.turn.id.length <= 256
          && ['completed', 'interrupted', 'failed'].includes(p.turn.status)) terminals.push({ thread: p.threadId, id: p.turn.id, status: p.turn.status });
        if (entry?.message?.method === 'turn/completed' && binding && turn
          && p?.threadId === binding.thread && p?.turn?.id === turn.provider
          && ['completed', 'interrupted', 'failed'].includes(p.turn.status)) report.provider_terminal_status = p.turn.status;
      });
      return wrap(client, {
        request: async (method, params, dispatch) => {
          if (method === 'turn/start') {
            check(dispatchOpen(), 'http_turn_stopping');
            bump(report, 'model_start_attempts'); check(report.model_start_attempts === 1, 'http_turn_multiple_turns');
            return client.request(method, params, { ...dispatch, onDispatched: () => {
              bump(report, 'start_dispatched'); dispatch?.onDispatched?.();
            } });
          }
          const result = await client.request(method, params, dispatch);
          if (method === 'config/read') report.config_read = true;
          if (method === 'configRequirements/read') report.requirements_read = true;
          if (method === 'account/read') report.cached_account_read = params?.refreshToken === false && result?.account?.type === 'chatgpt';
          return result;
        },
        startThread: async params => { const value = await client.startThread(params); report.thread_returned = true; return value; },
        interruptTurn: async (threadId, turnId, dispatch) => {
          bump(report, 'interrupt_attempts');
          // Observation must not prevent the task's own cleanup if HTTP start
          // failed before this probe received its local turn binding.
          report.interrupt_binding_verified = !!(binding && turn && threadId === binding.thread && turnId === turn.provider);
          const value = await client.interruptTurn(threadId, turnId, { ...dispatch, onDispatched: () => {
            bump(report, 'interrupt_dispatched'); dispatch?.onDispatched?.();
          } });
          report.interrupt_acknowledged = true; return value;
        },
      });
    },
  };
  const api = new ExperimentalRuntimeApi({ enabled: true,
    adapterFactory: () => { bump(report, 'generic_factory_calls'); throw fail('http_turn_generic_forbidden'); },
    textAdapterFactory: () => {
      check(!adapter, 'http_turn_multiple_resources');
      adapter = new WorkbenchTextTaskRuntimeAdapter({ nativeOptions: { executable, sha256 }, factories });
      return wrap(adapter, { closeSession: id => {
        // Only the real API calls this facade. Flow/finally use shutdown or the
        // native resource directly, and cannot manufacture abort-origin proof.
        // The API's abort listener can call close before the signal observer
        // installed below runs. Capture this API-origin call independently;
        // flow still requires the real AbortSignal before adopting its proof.
        const candidateApiClose = scenario === 'turn-disconnect' && !stopping;
        if (candidateApiClose) {
          bump(report, 'api_abort_close_calls'); report.api_abort_close_binding_verified = id === binding?.id;
          if (!report.request_abort_observed) report.api_close_before_abort_observer = true;
        }
        const promise = Promise.resolve().then(() => adapter.closeSession(id)); void promise.catch(() => {});
        if (candidateApiClose && report.api_abort_close_calls === 1) apiAbortClose.resolve({ id, promise });
        return promise;
      }, startTurn: async (id, input, params, requestOptions) => {
        const observe = () => { report.request_abort_observed = true; aborted.resolve(); };
        requestOptions.signal.addEventListener('abort', observe, { once: true });
        try {
          const result = await adapter.startTurn(id, input, params); turn = turnBinding(result, binding);
          report.provider_terminal_status = terminals.find(value => value.thread === binding.thread && value.id === turn.provider)?.status ?? null;
          report.turn_binding_verified = true;
          if (scenario === 'turn-disconnect') { report.turn_result_held = true; held.resolve(); await release.promise; }
          return result;
        } finally { requestOptions.signal.removeEventListener('abort', observe); }
      } });
    } });
  const server = http.createServer((req, res) => {
    if (req.method === 'POST' && req.url.endsWith('/turns')) res.once('finish', () => { report.http_turn_response_finished = true; });
    const operation = Promise.resolve().then(() => api.handle(req, res, new URL(req.url, 'http://127.0.0.1')));
    handlers.add(operation); void operation.then(() => {}, () => {}).finally(() => handlers.delete(operation));
  });
  server.on('connection', socket => { sockets.add(socket); socket.once('close', () => sockets.delete(socket)); });
  const shutdown = createBridgeRuntimeShutdown({ runtimeApi: api, server, httpGraceMs: 1000 });
  function request(method, suffix, body) {
    check(dispatchOpen(), 'http_turn_stopping');
    const payload = body === undefined ? null : Buffer.from(JSON.stringify(body));
    const req = http.request({ host: '127.0.0.1', port: server.address().port, agent: localAgent,
      path: `${EXPERIMENTAL_RUNTIME_PREFIX}${suffix}`, method,
      headers: payload ? { 'content-type': 'application/json', 'content-length': payload.length } : {} });
    requests.add(req); req.once('close', () => requests.delete(req));
    const promise = new Promise((resolve, reject) => {
      req.once('error', () => reject(fail('http_turn_request_failed')));
      req.once('response', res => {
        const chunks = []; let size = 0;
        res.on('data', chunk => { size += chunk.length; if (size > 128 * 1024) { req.destroy(); reject(fail('http_turn_response_limit')); } else chunks.push(chunk); });
        res.once('aborted', () => reject(fail('http_turn_request_failed'))); res.once('error', () => reject(fail('http_turn_request_failed')));
        res.once('end', () => { try { resolve({ status: res.statusCode, body: JSON.parse(Buffer.concat(chunks).toString('utf8')) }); }
          catch { reject(fail('http_turn_response_invalid')); } });
      });
    }); void promise.catch(() => {}); req.end(payload); return { req, promise };
  }
  async function waitFor(test, limit) {
    const until = Date.now() + limit;
    while (!test()) { check(dispatchOpen() && Date.now() < until, 'http_turn_wait_failed'); await new Promise(resolve => setTimeout(resolve, 20)); }
  }
  async function readTerminal() {
    let after = 0, text = '', terminal = null;
    for (let polls = 0; polls < 750; polls++) {
      const response = await request('GET', `/sessions/${binding.id}/events?after=${after}`).promise;
      const batch = response.body;
      check(response.status === 200 && exact(batch, ['status', 'events', 'next_sequence']) && Array.isArray(batch.events)
        && batch.status === 'ready' && Number.isSafeInteger(batch.next_sequence) && batch.next_sequence >= after && batch.next_sequence <= 4096, 'http_turn_events_invalid');
      for (const event of batch.events) {
        check(event.sequence === after + 1 && event.turn_id === turn.local && ['turn_status', 'message_delta'].includes(event.kind), 'http_turn_events_invalid');
        after = event.sequence; bump(report, 'event_count');
        if (event.kind === 'message_delta') {
          check(exact(event, ['sequence', 'turn_id', 'kind', 'data']) && exact(event.data, ['text']), 'http_turn_events_invalid');
          if (terminal) report.text_after_terminal = true;
          check(typeof event.data?.text === 'string' && text.length + event.data.text.length <= 24000, 'http_turn_events_invalid'); text += event.data.text;
        } else { check(exact(event, ['sequence', 'turn_id', 'kind', 'status', 'data']) && exact(event.data, [])
          && ['completed', 'interrupted', 'failed'].includes(event.status) && !terminal, 'http_turn_events_invalid'); terminal = event.status; }
      }
      check(after === batch.next_sequence, 'http_turn_events_invalid');
      if (terminal) { report.provider_terminal_status = terminal; report.event_terminal_verified = true;
        report.fixed_text_observed = text === 'P6_R7_NATIVE_OK'; report.text_empty = text === ''; return terminal; }
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    throw fail('http_turn_terminal_missing');
  }
  const flow = (async () => {
    await new Promise((resolve, reject) => { server.once('error', () => reject(fail('http_turn_listen_failed'))); server.listen(0, '127.0.0.1', resolve); });
    stage = 'create'; const created = await request('POST', '/sessions', { config: { runtime_profile: PROFILE }, context_manifest: { execution_epoch: epoch } }).promise;
    report.http_create_status = created.status; binding = sessionBinding(created.body, epoch);
    check(created.status === 200 && binding, 'http_turn_session_invalid'); report.execution_receipt_verified = true;
    stage = 'turn_start'; const start = request('POST', `/sessions/${binding.id}/turns`, { input: HTTP_TURN_FIXED_INPUT });
    if (scenario === 'turn-disconnect') await Promise.race([held.promise, start.promise.then(() => { throw fail('http_turn_hold_missing'); })]);
    else { const result = await start.promise; report.http_turn_status = result.status; check(result.status === 200, 'http_turn_start_failed');
      turn = turnBinding(result.body, binding); report.turn_binding_verified = true; }
    check(report.start_dispatched === 1, 'http_turn_dispatch_unconfirmed');
    if (scenario !== 'completed') {
      stage = 'upstream_wait'; await waitFor(() => broker.snapshot().upstream_attempts > 0, 15000);
      report.upstream_before_action = count(broker.snapshot().upstream_attempts);
      report.terminal_before_action = report.provider_terminal_status !== null;
      report.exchange_inflight_before_action = report.exchange_started === 1 && report.exchange_settled === 0;
      check(report.upstream_before_action === 1 && !report.terminal_before_action && report.exchange_inflight_before_action, 'http_turn_not_active');
      if (scenario === 'turn-disconnect') {
        stage = 'disconnect'; check(!report.http_turn_response_finished, 'http_turn_response_already_finished');
        start.req.destroy(); report.client_disconnect = true; await aborted.promise;
        report.held_result_released_after_abort = true; release.resolve();
        await Promise.allSettled([...handlers]); report.handler_settled = true;
        check(!report.http_turn_response_finished, 'http_turn_response_already_finished');
        stage = 'disconnect_close'; const origin = await apiAbortClose.promise;
        check(origin.id === binding.id && report.api_abort_close_calls === 1, 'http_turn_abort_close_missing');
        const tombstone = await origin.promise;
        report.cancellation_confirmed = tombstone?.stop_receipt?.cancellation_confirmed === true;
        report.stop_receipt_verified = stopReceipt(tombstone, binding, turn, 'interrupted');
        report.api_abort_close_result_verified = report.stop_receipt_verified;
      } else {
        stage = 'interrupt'; const interrupted = await request('POST', `/sessions/${binding.id}/turns/${turn.local}/interrupt`, {}).promise;
        report.http_interrupt_status = interrupted.status;
        check(interrupted.status === 200 && exact(interrupted.body, ['interrupt_dispatched']) && interrupted.body.interrupt_dispatched === true, 'http_turn_interrupt_unconfirmed');
      }
    }
    if (scenario !== 'turn-disconnect') {
      stage = 'events'; check(await readTerminal() === (scenario === 'completed' ? 'completed' : 'interrupted'), 'http_turn_terminal_mismatch');
      stage = 'delete'; const deleted = await request('DELETE', `/sessions/${binding.id}`).promise; report.http_delete_status = deleted.status;
      report.cancellation_confirmed = deleted.body?.stop_receipt?.cancellation_confirmed === true;
      report.stop_receipt_verified = deleted.status === 200 && stopReceipt(deleted.body, binding, turn, scenario === 'completed' ? 'completed' : 'interrupted');
    }
    check(report.stop_receipt_verified, 'http_turn_stop_unconfirmed');
  })(); void flow.catch(() => {});
  try { await within(flow, Math.max(1, deadline - Date.now()), fenceDeadline); }
  catch { report.code = 'http_turn_failed'; report.failure_stage = stage; }
  finally {
    stopping = true; for (const req of requests) req.destroy(); localAgent.destroy(); release.resolve();
    try { const result = await within(shutdown.shutdown(), cleanupTimeoutMs); report.host_shutdown_verified = result.runtime_closed === true && result.http_server_closed === true; }
    catch { report.code ??= 'http_turn_cleanup_unconfirmed'; }
    if (owner && !nativeClosed) try { bump(report, 'owner_close_calls'); const r = await within(owner.close(), cleanupTimeoutMs);
      nativeClosed = FACTS.every(key => r?.[key] === true) && r.cleanup_pending === false && owner.cleanupPending === false;
    } catch { /* Retain the same owner below. */ }
    if (broker) try { broker.revoke(); await within(broker.close(), cleanupTimeoutMs); } catch { /* Not drain proof. */ }
    if (server.listening) { for (const socket of sockets) socket.destroy(); server.close(); }
    try { await within(Promise.allSettled([flow, ...handlers]), cleanupTimeoutMs); report.handler_settled = true; } catch { report.code ??= 'http_turn_cleanup_unconfirmed'; }
    try { await within(new Promise(resolve => { if (!sockets.size) resolve(); else { let remaining = sockets.size;
      for (const socket of sockets) socket.once('close', () => { if (--remaining === 0) resolve(); }); } }), 1000); } catch { /* Closed event remains mandatory. */ }
    report.http_server_closed = !server.listening && sockets.size === 0;
    const d = owner?.diagnostics, snapshot = broker?.snapshot();
    report.native_failure_present = d?.native_failure_code != null; report.native_failure_code = safeNativeCode(d?.native_failure_code);
    report.native_owner_exit_code = Number.isInteger(d?.native_owner_exit_code) && d.native_owner_exit_code >= -0x80000000 && d.native_owner_exit_code <= 0xffffffff ? d.native_owner_exit_code : null;
    for (const key of FACTS) report[key] = d?.native_close_receipt?.[key] === true;
    report.broker = { ...Object.fromEntries(COUNTERS.map(key => [key, count(snapshot?.[key])])), response_released: snapshot?.response_released === true, drained: snapshot?.drained === true };
    report.notifications = notifications.snapshot();
    report.cleanup_pending = !nativeClosed || owner?.cleanupPending !== false || !report.broker.drained || !report.handler_settled || !report.http_server_closed;
    report.local_resources_closed = !report.cleanup_pending && FACTS.every(key => report[key]);
    if (report.cleanup_pending) { retained.set(report.attempt_id ?? epoch, { owner, broker, adapter, api, shutdown, flow }); report.ownership_retained = true; }
    report.actual_native = !injected && report.owner_ready;
    const network = COUNTERS.every(key => report.broker[key] !== null) && report.broker.upstream_attempts === 1
      && report.broker.rejected_connections === 0 && report.broker.metadata_rejections <= 8
      && report.broker.parsed_requests === report.broker.metadata_rejections + 1
      && report.broker.admitted_connections === report.broker.parsed_requests
      && report.broker.rejected_requests === (scenario === 'completed' ? 0 : 1);
    report.checks_passed = report.code === null && report.owner_count === 1 && report.owner_ready
      && report.config_read && report.requirements_read && report.cached_account_read && report.thread_returned
      && report.execution_receipt_verified && report.turn_binding_verified && report.broker_arm_attempts === 1
      && report.model_start_attempts === 1 && report.start_dispatched === 1 && report.stop_receipt_verified
      && report.exchange_started === 1 && report.exchange_settled === 1
      && network && report.host_requests === 0 && report.generic_factory_calls === 0
      && FACTS.every(key => report[key]) && report.native_owner_exit_code === 0 && !report.native_failure_present
      && !report.cleanup_pending && report.host_shutdown_verified && !report.text_after_terminal
      && (scenario === 'completed' ? report.fixed_text_observed && report.broker.response_released && report.interrupt_dispatched === 0
        : !report.broker.response_released && report.interrupt_attempts === 1 && report.interrupt_dispatched === 1
          && report.interrupt_acknowledged && report.interrupt_binding_verified && report.upstream_before_action === 1 && !report.terminal_before_action
          && report.exchange_inflight_before_action && report.exchange_abort_observed
          && report.provider_terminal_status === 'interrupted' && report.text_empty)
      && (scenario === 'turn-disconnect' ? report.client_disconnect && report.request_abort_observed
        && report.held_result_released_after_abort && !report.http_turn_response_finished && report.http_turn_status === null
        && report.api_abort_close_calls === 1 && report.api_abort_close_binding_verified && report.api_abort_close_result_verified
        : report.http_turn_response_finished && report.http_turn_status === 200 && report.event_terminal_verified && report.http_delete_status === 200);
    report.passed = !injected && report.checks_passed;
  }
  return JSON.parse(JSON.stringify(report));
}

export function parseHttpTurnProbeArgs(argv) {
  check(Array.isArray(argv) && argv.length === 4 && SCENARIOS.map(value => `--${value}`).includes(argv[0])
    && typeof argv[3] === 'string' && path.isAbsolute(argv[3]), 'http_turn_explicit_mode_required');
  const options = { executable: argv[1], sha256: argv[2], scenario: argv[0].slice(2) };
  validateOptions(options); return { options, reportPath: argv[3] };
}
export async function main(argv = process.argv.slice(2)) {
  const { options, reportPath } = parseHttpTurnProbeArgs(argv); const descriptor = openSync(reportPath, 'wx');
  try { const report = await runHttpNativeTurnProbe(options); const raw = `${JSON.stringify(report)}\n`;
    writeFileSync(descriptor, raw); process.stdout.write(raw); process.exitCode = report.passed ? 0 : 2;
  } finally { closeSync(descriptor); }
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) await main();
