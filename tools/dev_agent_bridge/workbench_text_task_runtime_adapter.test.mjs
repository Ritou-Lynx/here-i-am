import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import test from 'node:test';
import { WorkbenchTextTaskRuntimeAdapter } from './workbench_text_task_runtime_adapter.mjs';
import { RuntimeAdapterError } from './runtime_adapter.mjs';
import { TEXT_TASK_CLI_SHA256 } from './workbench_text_task_runtime_pin.mjs';
import { TEXT_TASK_MODEL, TEXT_TASK_INSTRUCTIONS } from './workbench_text_task_broker.mjs';
import { isWorkbenchTextStopReceipt } from './workbench_text_stop_receipt.mjs';

const PROFILE = 'workbench_text_only_v1';
const config = { runtime_profile: PROFILE };
const context = { execution_epoch: 'epoch-one' };
const deferred = () => { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; };
const flush = () => new Promise(resolve => setImmediate(resolve));
const secretError = () => Object.assign(new Error('PRIVATE_PATH TOKEN ACCOUNT'), { code: 'PRIVATE_CODE' });
const nativeReceipt = () => ({ process_close_observed: true, job_empty_verified: true, stdio_eof_verified: true,
  rules_absent_verified: true, handles_closed_verified: true, helper_exits_verified: true, cleanup_pending: false });
function nativeConfig() {
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
function fixture(options = {}) {
  const records = []; const stages = []; let next;
  const factories = {
    createBroker(args) {
      const r = { brokerArgs: args, arm: [], revoked: 0, ownerCloses: 0, brokerCloses: 0, requests: [], drained: false };
      records.push(r); next = r;
      return r.broker = {
        async listen() { stages.push('listen'); if (options.listen) await options.listen.promise; return 'http://127.0.0.1:32123/v1'; },
        arm(input) { r.arm.push(input); }, revoke() { r.revoked++; },
        async close() { r.brokerCloses++; if (options.brokerClose) await options.brokerClose(r); r.drained = !options.notDrained; },
        snapshot() { return { drained: r.drained }; },
      };
    },
    createOwner(args) {
      stages.push('owner'); const r = next; r.ownerArgs = args;
      if (options.ownerThrows) throw secretError();
      r.startup = { attempt_id: args.attemptId, type: 'started', seq: 1, cwd: 'D:\\fixed\\project0',
        auth_mode: 'chatgpt', provider: 'p6_native_startup', cli_sha256: TEXT_TASK_CLI_SHA256,
        pid: 123, creation_time: '123456', network_boundary_verified: true, child_identity_verified: true, job_singleton: true,
        ...options.startup };
      return r.owner = { ready: options.ready ? options.ready.promise.then(() => r.startup) : Promise.resolve(r.startup),
        cleanupPending: true, diagnostics: { native_owner_pid: 321, native_owner_exit_code: 0 },
        async verifyPeer() { return true; },
        async close() { r.ownerCloses++; if (options.ownerClose) await options.ownerClose(r);
          const receipt = { ...nativeReceipt(), ...options.receipt }; this.cleanupPending = false; return receipt; } };
    },
    createClient(args) {
      stages.push('client'); const r = next; r.clientArgs = args;
      class Client extends EventEmitter {
        isReady = false; notificationSequence = 0;
        async start() { stages.push('clientStart'); if (options.clientStart) await options.clientStart(r); this.isReady = true; }
        async request(method, params, dispatch) {
          r.requests.push({ method, params });
          if (options.request) await options.request(method, params, r);
          if (method === 'config/read') { const c = nativeConfig(); options.config?.(c); return c; }
          if (method === 'configRequirements/read') return { requirements: null };
          if (method === 'account/read') return { account: { type: options.accountType ?? 'chatgpt', email: 'PRIVATE_ACCOUNT' } };
          assert.equal(method, 'turn/start');
          if (options.turn) return options.turn(dispatch, r);
          dispatch.onDispatched(); return { turn: { id: 'provider-turn' } };
        }
        async startThread(params) { r.threadArgs = params; stages.push('thread');
          if (options.thread) await options.thread.promise;
          return { thread: { id: 'provider-thread' }, cwd: r.startup.cwd, model: TEXT_TASK_MODEL,
            modelProvider: 'p6_native_startup', approvalPolicy: 'never', sandbox: { type: 'readOnly' }, ...options.threadResponse }; }
        async interruptTurn(threadId, turnId, dispatch) { dispatch.onDispatched(); r.interrupt = { threadId, turnId }; return {}; }
        async waitForNotification() { throw secretError(); }
        notify(method, params) { this.emit('notification', { sequence: ++this.notificationSequence, message: { method, params } }); }
      }
      return r.client = new Client();
    },
  };
  const adapter = new WorkbenchTextTaskRuntimeAdapter({ factories,
    ...(options.nativeCloseObserver ? { nativeCloseObserver: options.nativeCloseObserver } : {}) });
  return { adapter, factories, records, stages, get r() { return records[0]; } };
}
function terminal(r, status = 'completed', turnId = 'provider-turn') {
  r.client.notify('turn/completed', { threadId: 'provider-thread', turn: { id: turnId, status } });
}
async function rejected(promise, code) {
  await assert.rejects(Promise.resolve().then(() => typeof promise === 'function' ? promise() : promise), failure => {
    assert.ok(failure instanceof RuntimeAdapterError);
    if (code) assert.equal(failure.code, code);
    assert.doesNotMatch(JSON.stringify(failure.toJSON()), /PRIVATE|TOKEN|ACCOUNT/);
    assert.equal(failure.cause, undefined); return true;
  });
}

test('candidate requires explicit host ownership; unsupported and caller overrides allocate nothing', async () => {
  assert.throws(() => new WorkbenchTextTaskRuntimeAdapter(), RuntimeAdapterError);
  assert.throws(() => new WorkbenchTextTaskRuntimeAdapter({ factories: {} }), RuntimeAdapterError);
  const f = fixture();
  for (const bad of [{}, { runtime_profile: 'ordinary' }, { ...config, executable: 'evil.exe' },
    { ...config, model: 'other' }, { ...config, dynamic_tools: [] }, { ...config, home: 'private' }]) {
    await rejected(() => f.adapter.startSession(bad, context), 'invalid_request');
  }
  for (const bad of [{}, { execution_epoch: '' }, { ...context, extra: true }, { ...context, task_id: '' },
    { ...context, execution_mode: 'tools' }]) await rejected(() => f.adapter.startSession(config, bad), 'invalid_request');
  for (const operation of ['resumeSession', 'steerTurn', 'respondToApproval', 'respondToToolCall']) {
    await rejected(() => f.adapter[operation]('ignored'), 'unsupported_capability');
  }
  assert.equal(f.records.length, 0);
});

test('startup validates mode, configuration, account and thread before issuing exact Dart v2 receipt', async () => {
  const f = fixture(); const session = await f.adapter.startSession(config, { ...context, task_id: 'task-one', execution_mode: 'isolated_text_only' });
  assert.deepEqual(session, { session_id: session.session_id, status: 'idle',
    provider_metadata: { provider: 'codex', provider_session_id: 'provider-thread' },
    execution_profile_receipt: { profile: PROFILE, version: 2, local_session_id: session.session_id,
      execution_epoch: context.execution_epoch, provider_thread_id: 'provider-thread', isolation_verified: true, tools_disabled: true } });
  assert.deepEqual(f.stages, ['listen', 'owner', 'client', 'clientStart', 'thread']);
  assert.equal(f.r.brokerArgs.exchangeTimeoutMs, 180000);
  assert.deepEqual(f.r.requests.map(x => x.method), ['config/read', 'configRequirements/read', 'account/read']);
  assert.deepEqual(f.r.requests.at(-1).params, { refreshToken: false });
  assert.equal(f.r.clientArgs.attachedTransport, f.r.owner);
  assert.equal(f.r.ownerArgs.authMode, 'chatgpt'); assert.equal(f.r.arm.length, 0);
  assert.deepEqual(f.r.threadArgs, { cwd: f.r.startup.cwd, model: TEXT_TASK_MODEL, modelProvider: 'p6_native_startup',
    approvalPolicy: 'never', sandbox: 'read-only', ephemeral: true, dynamicTools: [], environments: [],
    runtimeWorkspaceRoots: [], selectedCapabilityRoots: [], baseInstructions: TEXT_TASK_INSTRUCTIONS });
  assert.doesNotMatch(JSON.stringify(session), /PRIVATE|task-one|isolated_text_only|fixed/);
  const closed = await f.adapter.closeSession(session.session_id);
  assert.equal(closed.status, 'closed'); assert.ok(isWorkbenchTextStopReceipt(closed.stop_receipt));
  assert.equal(closed.stop_receipt.outcome, 'closed_without_turn');
  assert.equal(closed.stop_receipt.local_turn_id, null); assert.equal(closed.stop_receipt.turn_id, null);
  assert.equal(closed.stop_receipt.provider_terminal_confirmed, false);
  assert.equal(await f.adapter.closeSession(session.session_id), closed);
  await f.adapter.closeAll(); assert.equal(f.r.ownerCloses, 1);
});

test('optional native close observer receives only verified facts once and never accepts incomplete cleanup', async () => {
  const observed = [];
  const f = fixture({ nativeCloseObserver: value => observed.push(value) });
  const session = await f.adapter.startSession(config, context);
  await f.adapter.closeSession(session.session_id);
  await f.adapter.closeSession(session.session_id);
  assert.equal(observed.length, 1);
  assert.equal(observed[0].attempt_id, f.r.ownerArgs.attemptId);
  assert.equal(observed[0].native_owner_pid, 321);
  assert.equal(observed[0].process_close_observed, true);
  assert.equal(observed[0].cleanup_pending, false);
  assert.doesNotMatch(JSON.stringify(observed[0]), /PRIVATE|ACCOUNT|TOKEN/);

  const rejectedObservations = [];
  const bad = fixture({ receipt: { helper_exits_verified: false },
    nativeCloseObserver: value => rejectedObservations.push(value) });
  await assert.rejects(bad.adapter.startSession(config, context).then(async created =>
    bad.adapter.closeSession(created.session_id)));
  assert.deepEqual(rejectedObservations, []);
});

test('normal input is passed once, events retain top-level status and close binds the actual terminal', async () => {
  const f = fixture(); const session = await f.adapter.startSession(config, context); const id = session.session_id;
  const turn = await f.adapter.startTurn(id, 'User authorized text');
  assert.deepEqual(Object.keys(turn).sort(), ['execution_epoch', 'local_session_id', 'local_turn_id', 'provider_thread_id', 'provider_turn_id']);
  assert.equal(turn.local_session_id, id); assert.equal(turn.provider_thread_id, 'provider-thread');
  assert.deepEqual(f.r.arm, ['User authorized text']);
  f.r.client.notify('item/agentMessage/delta', { threadId: 'provider-thread', turnId: 'other-turn', delta: 'PRIVATE' });
  f.r.client.notify('item/agentMessage/delta', { threadId: 'provider-thread', turnId: 'provider-turn', delta: 'Answer' });
  terminal(f.r);
  const events = f.adapter.readEvents(id, { afterSequence: 0 });
  assert.equal(events.events.length, 2); assert.equal(events.events[0].data.text, 'Answer');
  assert.equal(events.events[1].status, 'completed'); assert.deepEqual(events.events[1].data, {});
  assert.equal(f.adapter.readEvents(id, { afterSequence: 1 }).events.length, 1);
  await rejected(() => f.adapter.startTurn(id, 'second'), 'turn_not_active');
  assert.equal(f.r.ownerCloses, 0); assert.equal(f.r.brokerCloses, 0);
  const closed = await f.adapter.closeSession(id);
  assert.equal(closed.stop_receipt.local_turn_id, turn.local_turn_id);
  assert.equal(closed.stop_receipt.turn_id, turn.provider_turn_id);
  assert.equal(closed.stop_receipt.provider_terminal_status, 'completed');
  assert.equal(closed.stop_receipt.cancellation_confirmed, false);
});

test('concurrent turn starts reject only the duplicate and preserve the first owner', async () => {
  const gate = deferred();
  const f = fixture({ turn: async dispatch => {
    await gate.promise;
    dispatch.onDispatched();
    return { turn: { id: 'provider-turn' } };
  } });
  const { session_id: id } = await f.adapter.startSession(config, context);
  const first = f.adapter.startTurn(id, 'first');
  await flush();
  await rejected(() => f.adapter.startTurn(id, 'duplicate'), 'turn_not_active');
  assert.equal(f.r.ownerCloses, 0); assert.equal(f.r.brokerCloses, 0); assert.equal(f.r.interrupt, undefined);
  gate.resolve();
  const turn = await first;
  terminal(f.r, 'completed', turn.provider_turn_id);
  const closed = await f.adapter.closeSession(id);
  assert.equal(closed.stop_receipt.turn_id, turn.provider_turn_id);
  assert.equal(closed.stop_receipt.provider_terminal_status, 'completed');
});

test('invalid text, params and cursors cannot change the fresh session', async () => {
  const f = fixture(); const { session_id: id } = await f.adapter.startSession(config, context);
  for (const input of ['', ' ', [], { content: [] }, '\ud800', 'x'.repeat(32769)]) await rejected(() => f.adapter.startTurn(id, input), 'invalid_request');
  await rejected(() => f.adapter.startTurn(id, 'x', { model: 'other' }), 'invalid_request');
  await rejected(() => f.adapter.readEvents(id, { afterSequence: -1 }), 'invalid_request');
  await rejected(() => f.adapter.readEvents(id, { extra: true }), 'invalid_request');
  for (const options of [null, [], 'private', 1]) await rejected(() => f.adapter.readEvents(id, options), 'invalid_request');
  assert.equal(f.r.arm.length, 0); assert.equal(f.r.ownerCloses, 0); assert.equal(f.r.drained, false);
  await f.adapter.closeAll();
});

test('startup evidence/config/account/thread mismatches never issue a receipt and close the same owner', async () => {
  for (const options of [{ startup: { auth_mode: 'no_auth' } }, { startup: { job_singleton: false } },
    { startup: { cli_sha256: '0'.repeat(64) } }, { config: c => { c.config.features.respect_system_proxy = true; } },
    { accountType: 'apiKey' }, { threadResponse: { modelProvider: 'other' } },
    { threadResponse: { sandbox: { type: 'dangerFullAccess' } } }, { clientStart: () => { throw secretError(); } }]) {
    const f = fixture(options); await rejected(f.adapter.startSession(config, context));
    assert.equal(f.r.ownerCloses, 1); assert.equal(f.r.drained, true); assert.equal(f.r.arm.length, 0);
    assert.deepEqual(await f.adapter.closeAll(), { status: 'closed' });
  }
});

test('creation failure retains unknown ownership and retries cleanup through closeAll', async () => {
  let canClose = false;
  const f = fixture({ clientStart: () => { throw secretError(); }, ownerClose: () => { if (!canClose) throw secretError(); } });
  await rejected(f.adapter.startSession(config, context));
  await rejected(f.adapter.closeAll(), 'runtime_stop_unconfirmed');
  canClose = true; await f.adapter.closeAll();
  assert.equal(f.records.length, 1); assert.equal(f.r.ownerCloses, 3);
});

test('throwing acquisition remains unknown rather than reporting child close or dropping obligation', async () => {
  const f = fixture({ ownerThrows: true });
  await rejected(f.adapter.startSession(config, context));
  await rejected(f.adapter.closeAll(), 'runtime_stop_unconfirmed');
  assert.equal(f.r.ownerCloses, 0); assert.equal(f.r.drained, true);
});

test('abort before acquisition allocates nothing; abort during listen prevents later owner creation', async () => {
  const f = fixture(); const aborted = new AbortController(); aborted.abort();
  await rejected(() => f.adapter.startSession(config, context, { signal: aborted.signal }), 'runtime_start_unconfirmed');
  assert.equal(f.records.length, 0);
  const gate = deferred(); const delayed = fixture({ listen: gate }); const controller = new AbortController();
  const pending = delayed.adapter.startSession(config, context, { signal: controller.signal });
  await flush(); controller.abort(); gate.resolve(); await rejected(pending, 'runtime_start_unconfirmed');
  assert.equal(delayed.r.owner, undefined); assert.equal(delayed.r.drained, true); await delayed.adapter.closeAll();
});

test('abort while owner is starting closes immediately and awaits pending creation before shutdown', async () => {
  const gate = deferred(); const f = fixture({ ready: gate }); const controller = new AbortController();
  const pending = f.adapter.startSession(config, context, { signal: controller.signal });
  await flush(); controller.abort(); await flush(); assert.equal(f.r.ownerCloses, 1);
  let settled = false; const shutdown = f.adapter.closeAll().then(() => { settled = true; });
  await flush(); assert.equal(settled, false); gate.resolve(); await rejected(pending, 'runtime_start_unconfirmed');
  await shutdown; assert.equal(f.r.ownerCloses, 1); assert.equal(f.r.drained, true);
});

test('abort before delayed thread response cannot publish a session; completed creation releases its signal', async () => {
  const gate = deferred(); const f = fixture({ thread: gate }); const controller = new AbortController();
  const pending = f.adapter.startSession(config, context, { signal: controller.signal });
  await flush(); controller.abort(); gate.resolve(); await rejected(pending, 'runtime_start_unconfirmed'); await f.adapter.closeAll();
  const normal = fixture(); const done = new AbortController(); const session = await normal.adapter.startSession(config, context, { signal: done.signal });
  done.abort(); await flush(); assert.equal(normal.r.ownerCloses, 0); await normal.adapter.closeSession(session.session_id);
});

test('a fault during creation lets creation cleanup close the held owner without a cleanup race', async () => {
  const f = fixture({ clientStart: r => { r.client.emit('processError', secretError()); } });
  await rejected(f.adapter.startSession(config, context), 'runtime_start_unconfirmed');
  assert.equal(f.r.ownerCloses, 1); assert.equal(f.r.drained, true);
  assert.deepEqual(await f.adapter.closeAll(), { status: 'closed' });
});

test('shutdown closes an already ready owner while another creation is pending', async () => {
  const options = {}; const f = fixture(options);
  const ready = await f.adapter.startSession(config, context);
  options.ready = deferred();
  const pending = f.adapter.startSession(config, { execution_epoch: 'epoch-two' });
  await flush();
  let finished = false;
  const shutdown = f.adapter.closeAll().then(() => { finished = true; });
  await flush(); await flush();
  assert.equal(f.records[0].ownerCloses, 1);
  assert.equal(f.records[0].drained, true);
  assert.equal(f.records[1].ownerCloses, 1);
  assert.equal(finished, false);
  await rejected(() => f.adapter.startTurn(ready.session_id, 'cannot dispatch'), 'runtime_unavailable');
  options.ready.resolve(); await rejected(pending, 'runtime_start_unconfirmed');
  await shutdown;
  assert.equal((await f.adapter.closeSession(ready.session_id)).stop_receipt.outcome, 'closed_without_turn');
});

test('concurrent close and shutdown share the native close; failed proof is retryable against same owner', async () => {
  const gate = deferred(); let allow = false;
  const f = fixture({ ownerClose: async () => { await gate.promise; if (!allow) throw secretError(); } });
  const session = await f.adapter.startSession(config, context);
  const first = f.adapter.closeSession(session.session_id); const second = f.adapter.closeSession(session.session_id);
  assert.equal(first, second); const shutdown = f.adapter.closeAll();
  gate.resolve(); await rejected(first, 'runtime_stop_unconfirmed'); await rejected(second, 'runtime_stop_unconfirmed');
  await rejected(shutdown, 'runtime_stop_unconfirmed'); const previous = f.r.ownerCloses;
  allow = true; const receipt = await f.adapter.closeSession(session.session_id); await f.adapter.stop();
  assert.equal(receipt.stop_receipt.outcome, 'closed_without_turn'); assert.equal(f.r.ownerCloses, previous + 1);
  await rejected(() => f.adapter.startSession(config, context), 'runtime_unavailable');
});

test('invalid native close proof and non-drained broker cannot yield a stop receipt', async () => {
  for (const options of [{ receipt: { handles_closed_verified: false } }, { notDrained: true }]) {
    const f = fixture(options); const session = await f.adapter.startSession(config, context);
    await rejected(f.adapter.closeSession(session.session_id), 'runtime_stop_unconfirmed');
    await rejected(f.adapter.closeAll(), 'runtime_stop_unconfirmed');
  }
});

test('unknown turn start automatically closes its same owner without a caller DELETE', async () => {
  let dispatch; const f = fixture({ turn: options => { dispatch = options.onDispatched; throw secretError(); } });
  const session = await f.adapter.startSession(config, context);
  await rejected(f.adapter.startTurn(session.session_id, 'User text'), 'runtime_start_unconfirmed');
  dispatch();
  assert.equal(f.r.ownerCloses, 1); assert.equal(f.r.drained, true);
  await rejected(f.adapter.closeSession(session.session_id), 'runtime_stop_unconfirmed');
  await rejected(f.adapter.closeAll(), 'runtime_stop_unconfirmed');
});

test('interrupt ACK is not terminal; matching later terminal supports cancellation receipt', async () => {
  const f = fixture(); const { session_id: id } = await f.adapter.startSession(config, context);
  const turn = await f.adapter.startTurn(id, 'User text');
  assert.deepEqual(await f.adapter.interruptTurn(id, turn.local_turn_id), { interrupt_dispatched: true });
  await rejected(f.adapter.closeSession(id), 'runtime_stop_unconfirmed');
  // Once actual child is closed, the task detaches; a late synthetic terminal cannot repair proof.
  terminal(f.r, 'interrupted'); await rejected(f.adapter.closeSession(id), 'runtime_stop_unconfirmed');
  const success = fixture(); const s = await success.adapter.startSession(config, context);
  const t = await success.adapter.startTurn(s.session_id, 'User text'); await success.adapter.interruptTurn(s.session_id, t.local_turn_id);
  terminal(success.r, 'interrupted'); const closed = await success.adapter.closeSession(s.session_id);
  assert.equal(closed.stop_receipt.cancellation_confirmed, true);
});

test('task cleanup waits for interrupt ACK before revoke can fail a still-running provider', async () => {
  for (const prematureRevoke of [false, true]) {
    const order = [], ack = deferred(); let ended = false;
    const f = fixture({ ownerClose: () => { order.push('native-close'); } });
    const { session_id: id } = await f.adapter.startSession(config, context);
    const turn = await f.adapter.startTurn(id, 'User text');
    const originalRevoke = f.r.broker.revoke;
    f.r.broker.revoke = () => {
      order.push('revoke'); originalRevoke();
      // Model the observed provider: revoking its pending exchange before the
      // interrupt RPC completes produces a failed terminal, never cancellation.
      if (!ended) { ended = true; order.push('terminal-failed'); terminal(f.r, 'failed'); }
    };
    f.r.client.interruptTurn = async (thread, providerTurn, dispatch) => {
      assert.equal(thread, 'provider-thread'); assert.equal(providerTurn, turn.provider_turn_id);
      order.push('interrupt-dispatch'); dispatch.onDispatched(); await ack.promise;
      order.push('interrupt-ack');
      if (!ended) { ended = true; order.push('terminal-interrupted'); terminal(f.r, 'interrupted'); }
      return {};
    };
    if (prematureRevoke) f.r.broker.revoke();
    const closing = f.adapter.closeSession(id); await flush();
    if (!prematureRevoke) {
      assert.deepEqual(order, ['interrupt-dispatch']);
      assert.equal(f.r.ownerCloses, 0); assert.equal(f.r.revoked, 0);
    }
    ack.resolve(); const result = await closing;
    assert.equal(result.stop_receipt.local_turn_id, turn.local_turn_id);
    assert.equal(result.stop_receipt.turn_id, turn.provider_turn_id);
    assert.equal(result.stop_receipt.provider_terminal_status, prematureRevoke ? 'failed' : 'interrupted');
    assert.equal(result.stop_receipt.cancellation_confirmed, !prematureRevoke);
    assert.equal(result.stop_receipt.local_child_close_observed, true); assert.equal(result.stop_receipt.proxy_drained, true);
    if (!prematureRevoke) {
      assert.ok(order.indexOf('revoke') > order.indexOf('interrupt-ack'));
      assert.ok(order.indexOf('native-close') > order.indexOf('revoke'));
      assert.ok(result.stop_receipt.provider_terminal_sequence > result.stop_receipt.interrupt_dispatch_sequence);
    }
  }
});

test('resource-only startup failure revokes before native fallback without a TaskSession', async () => {
  const order = [];
  const f = fixture({ request: (method, _params, record) => {
    if (method !== 'config/read') return;
    const revoke = record.broker.revoke;
    record.broker.revoke = () => { order.push('revoke'); revoke(); };
    throw secretError();
  }, ownerClose: () => { order.push('native-close'); } });
  await rejected(f.adapter.startSession(config, context), 'runtime_start_unconfirmed');
  assert.equal(order[0], 'revoke'); assert.ok(order.indexOf('native-close') > 0);
  assert.equal(f.r.ownerCloses, 1); assert.equal(f.r.drained, true);
  await f.adapter.closeAll();
});

test('host request and process/protocol fault closes published resources without a caller DELETE', async () => {
  for (const kind of ['serverRequest', 'processError', 'protocolError']) {
    const f = fixture(); const session = await f.adapter.startSession(config, context); let replies = 0;
    f.r.client.emit(kind, { message: 'PRIVATE TOKEN', respondError: value => { replies++; assert.equal(value.code, -32601); } });
    assert.ok(f.r.revoked > 0); // Fault revocation is synchronous, not deferred behind TaskSession close.
    for (let pending = 0; pending < 20 && f.r.ownerCloses === 0; pending++) await flush();
    if (kind === 'serverRequest') assert.equal(replies, 1);
    assert.equal(f.r.ownerCloses, 1); assert.equal(f.r.drained, true);
    await rejected(f.adapter.closeSession(session.session_id), 'runtime_stop_unconfirmed');
    assert.doesNotMatch(JSON.stringify(f.adapter.readEvents(session.session_id)), /PRIVATE|TOKEN/);
  }
});

test('malformed published turn notification closes owner without DELETE and never issues a receipt', async () => {
  const f = fixture(); const { session_id: id } = await f.adapter.startSession(config, context);
  await f.adapter.startTurn(id, 'User text');
  terminal(f.r, 'not-a-terminal-status');
  for (let pending = 0; pending < 20 && f.r.ownerCloses === 0; pending++) await flush();
  assert.equal(f.r.ownerCloses, 1); assert.equal(f.r.drained, true);
  const events = f.adapter.readEvents(id);
  assert.equal(events.status, 'failed'); assert.deepEqual(events.events.map(event => event.kind), ['error']);
  await rejected(f.adapter.closeSession(id), 'runtime_stop_unconfirmed');
});
