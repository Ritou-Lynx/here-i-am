// Explicit host-owned candidate integration. Importing this module allocates no
// native resources and does not enable any production runtime profile.
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { RuntimeAdapter, RuntimeAdapterError } from './runtime_adapter.mjs';
import { CodexAppServerClient } from './codex_app_server_client.mjs';
import { createTextTaskBroker, TEXT_TASK_MODEL, TEXT_TASK_INSTRUCTIONS } from './workbench_text_task_broker.mjs';
import { launchWorkbenchTextNativeExecutor } from './workbench_text_task_native_executor.mjs';
import { TEXT_TASK_CLI_SHA256 } from './workbench_text_task_runtime_pin.mjs';
import { verifyNativeTaskConfig } from './workbench_text_task_native_probe.mjs';
import { WorkbenchTextTaskSession } from './workbench_text_task_session.mjs';
import { isWorkbenchTextStopReceipt } from './workbench_text_stop_receipt.mjs';

const PROFILE = 'workbench_text_only_v1';
const PROVIDER = 'p6_native_startup';
// The public 1–2000 line acceptance task needs the bounded long-text window
// already used by the isolated P6 candidate; the broker's 60s default is too short.
const EXCHANGE_TIMEOUT_MS = 180000;
const safeErrors = new WeakSet();
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const bounded = value => typeof value === 'string' && value.length > 0 && value.length <= 256;
const exact = (value, keys) => object(value) && Object.keys(value).length === keys.length
  && keys.every(key => Object.hasOwn(value, key));
const empty = value => exact(value, []);
function error(code, operation) {
  const result = new RuntimeAdapterError('Text task operation could not be confirmed.', {
    code, operation, retryable: code === 'runtime_stop_unconfirmed',
  });
  safeErrors.add(result);
  return result;
}
function check(ok, code = 'invalid_request', operation = 'startSession') {
  if (!ok) throw error(code, operation);
}
const sanitize = (value, operation, code = 'provider_error') => safeErrors.has(value)
  ? value : error(code, operation);
function freeze(value) {
  if (object(value) || Array.isArray(value)) {
    for (const item of Object.values(value)) freeze(item);
    Object.freeze(value);
  }
  return value;
}
function closeProof(owner, value) {
  const facts = ['process_close_observed', 'job_empty_verified', 'stdio_eof_verified',
    'rules_absent_verified', 'handles_closed_verified', 'helper_exits_verified'];
  return exact(value, [...facts, 'cleanup_pending']) && facts.every(key => value[key] === true)
    && value.cleanup_pending === false && owner.cleanupPending === false;
}
function startupProof(value, attempt) {
  return value?.attempt_id === attempt && value.type === 'started' && value.seq === 1
    && value.auth_mode === 'chatgpt' && value.provider === PROVIDER
    && value.cli_sha256 === TEXT_TASK_CLI_SHA256 && typeof value.cwd === 'string'
    && value.cwd.length <= 512 && path.win32.isAbsolute(value.cwd)
    && Number.isInteger(value.pid) && value.pid > 0 && value.pid <= 0xffffffff
    && typeof value.creation_time === 'string' && /^[1-9][0-9]{0,19}$/.test(value.creation_time)
    && BigInt(value.creation_time) <= 0xffffffffffffffffn
    && value.network_boundary_verified === true && value.child_identity_verified === true
    && value.job_singleton === true;
}

export class WorkbenchTextTaskRuntimeAdapter extends RuntimeAdapter {
  #factories; #nativeOptions; #nativeCloseObserver; #records = new Map(); #stopping = false; #stopPromise = null;

  // Factories are trusted, synchronous host dependencies, never HTTP fields.
  // They must return ownership before starting asynchronous work (owner.ready,
  // broker.listen, client.start). A throwing acquisition remains unknown.
  constructor({ nativeOptions, factories, nativeCloseObserver } = {}) {
    super();
    if (nativeOptions !== undefined) {
      check(exact(nativeOptions, ['executable', 'sha256']) && typeof nativeOptions.executable === 'string'
        && path.isAbsolute(nativeOptions.executable) && /^[a-f0-9]{64}$/.test(nativeOptions.sha256),
      'invalid_request', 'constructor');
    }
    check(nativeOptions !== undefined || factories !== undefined, 'runtime_unavailable', 'constructor');
    if (factories !== undefined) check(exact(factories, ['createBroker', 'createOwner', 'createClient'])
      && Object.values(factories).every(value => typeof value === 'function'), 'invalid_request', 'constructor');
    if (nativeCloseObserver !== undefined) check(typeof nativeCloseObserver === 'function', 'invalid_request', 'constructor');
    this.#nativeOptions = nativeOptions ? Object.freeze({ ...nativeOptions }) : null;
    this.#nativeCloseObserver = nativeCloseObserver ?? null;
    this.#factories = Object.freeze(factories ? { ...factories } : {
      createBroker: options => createTextTaskBroker(options),
      createOwner: options => launchWorkbenchTextNativeExecutor(options),
      createClient: options => new CodexAppServerClient(options),
    });
  }

  startSession(config, contextManifest, options = {}) {
    check(!this.#stopping, 'runtime_unavailable');
    check(exact(config, ['runtime_profile']) && config.runtime_profile === PROFILE);
    check(object(contextManifest) && bounded(contextManifest.execution_epoch)
      && Object.keys(contextManifest).every(key => ['execution_epoch', 'task_id', 'execution_mode'].includes(key))
      && (!Object.hasOwn(contextManifest, 'task_id') || bounded(contextManifest.task_id))
      && (!Object.hasOwn(contextManifest, 'execution_mode') || contextManifest.execution_mode === 'isolated_text_only'));
    check(object(options) && Object.keys(options).every(key => key === 'signal'));
    const signal = options.signal;
    check(signal === undefined || signal instanceof AbortSignal);
    check(!signal?.aborted, 'runtime_start_unconfirmed');
    check(this.#records.size < 64, 'runtime_unavailable');
    const record = { id: randomUUID(), attempt: randomUUID(), epoch: contextManifest.execution_epoch,
      state: 'creating', published: false, cancelled: false, fault: false,
      brokerAttempted: false, ownerAttempted: false, broker: null, owner: null, client: null,
      task: null, thread: null, ownerClosed: false, nativeClose: null, closing: null,
      creation: null, tombstone: null, detach: null, turnReserved: false };
    // Register before the first resource acquisition or asynchronous suspension.
    this.#records.set(record.id, record);
    const abort = () => this.#cancel(record);
    signal?.addEventListener('abort', abort, { once: true });
    record.creation = Promise.resolve().then(() => this.#create(record)).catch(async failure => {
      record.state = 'failed';
      try { await this.#cleanup(record); } catch { /* Retain the same obligation for closeAll. */ }
      throw sanitize(failure, 'startSession', 'runtime_start_unconfirmed');
    }).finally(() => signal?.removeEventListener('abort', abort));
    return record.creation;
  }

  #continue(record) {
    check(!record.cancelled && !this.#stopping && !record.fault, 'runtime_start_unconfirmed');
  }

  async #create(record) {
    this.#continue(record);
    record.brokerAttempted = true;
    record.broker = this.#factories.createBroker({
      verifyPeer: socket => record.owner?.verifyPeer(socket) ?? false,
      exchangeTimeoutMs: EXCHANGE_TIMEOUT_MS,
    });
    check(record.broker && typeof record.broker.listen === 'function' && typeof record.broker.close === 'function'
      && typeof record.broker.revoke === 'function' && typeof record.broker.snapshot === 'function', 'runtime_start_unconfirmed');
    const baseUrl = await record.broker.listen();
    this.#continue(record);
    check(typeof baseUrl === 'string' && /^http:\/\/127\.0\.0\.1:[1-9][0-9]{0,4}\/v1$/.test(baseUrl)
      && Number(new URL(baseUrl).port) <= 65535, 'runtime_start_unconfirmed');
    record.ownerAttempted = true;
    record.owner = this.#factories.createOwner({ ...this.#nativeOptions, attemptId: record.attempt,
      brokerPort: Number(new URL(baseUrl).port), authMode: 'chatgpt',
      startupTimeoutMs: 120000, closeTimeoutMs: 120000, requestTimeoutMs: 15000 });
    check(record.owner && typeof record.owner.close === 'function'
      && typeof record.owner.verifyPeer === 'function', 'runtime_start_unconfirmed');
    const startup = await record.owner.ready;
    this.#continue(record);
    check(startupProof(startup, record.attempt), 'runtime_start_unconfirmed');
    record.client = this.#factories.createClient({ attachedTransport: record.owner,
      experimentalApi: true, requestTimeoutMs: 15000 });
    const fail = () => this.#fault(record);
    const hostRequest = request => {
      fail();
      // TaskSession owns rejection after its listeners are attached.
      if (!record.task) {
        try { request.respondError({ code: -32601, message: 'Text tasks reject all host requests.' }); } catch { /* Keep fault. */ }
      }
    };
    record.client.on('serverRequest', hostRequest);
    record.client.on('processError', fail);
    record.client.on('protocolError', fail);
    record.detach = () => {
      record.client.off('serverRequest', hostRequest);
      record.client.off('processError', fail);
      record.client.off('protocolError', fail);
    };
    await record.client.start(); this.#continue(record);
    const config = await record.client.request('config/read', { cwd: startup.cwd, includeLayers: true });
    this.#continue(record);
    const requirements = await record.client.request('configRequirements/read', {});
    this.#continue(record);
    verifyNativeTaskConfig(config, requirements, baseUrl, 'chatgpt');
    const account = await record.client.request('account/read', { refreshToken: false });
    this.#continue(record);
    check(account?.account?.type === 'chatgpt', 'authentication_required');
    const thread = await record.client.startThread({ cwd: startup.cwd, model: TEXT_TASK_MODEL,
      modelProvider: startup.provider, approvalPolicy: 'never', sandbox: 'read-only',
      ephemeral: true, dynamicTools: [], environments: [], runtimeWorkspaceRoots: [], selectedCapabilityRoots: [],
      baseInstructions: TEXT_TASK_INSTRUCTIONS });
    this.#continue(record);
    check(bounded(thread?.thread?.id) && thread.model === TEXT_TASK_MODEL && thread.modelProvider === PROVIDER
      && thread.cwd === startup.cwd && thread.approvalPolicy === 'never' && thread.sandbox?.type === 'readOnly',
    'runtime_start_unconfirmed');
    record.thread = thread.thread.id;
    record.task = new WorkbenchTextTaskSession({ client: record.client, broker: record.broker,
      localSessionId: record.id, executionEpoch: record.epoch, providerThreadId: record.thread,
      closeChild: () => this.#closeNative(record), onFault: () => this.#fault(record) });
    this.#continue(record);
    record.published = true; record.state = 'ready';
    return freeze({ session_id: record.id, status: 'idle',
      provider_metadata: { provider: 'codex', provider_session_id: record.thread },
      execution_profile_receipt: { profile: PROFILE, version: 2, local_session_id: record.id,
        execution_epoch: record.epoch, provider_thread_id: record.thread, isolation_verified: true, tools_disabled: true } });
  }

  #cancel(record) {
    record.cancelled = true;
    try { record.broker?.revoke(); } catch { record.fault = true; }
    // Do not wait for startup RPC/ready before asking the already-held owner to close.
    if (record.owner) void this.#closeNative(record).catch(() => {});
  }

  #fault(record) {
    if (record.fault) return;
    record.fault = true;
    this.#cancel(record);
    // During creation, #create's failure path owns the awaited cleanup. Calling
    // #cleanup here could race that path while client/thread setup is still
    // suspended. A published record has no such dependency and must not leave
    // its broker listener open until a remote HTTP client remembers DELETE.
    if (record.state === 'ready') {
      void this.#cleanup(record).catch(() => {});
    }
  }

  #get(id, operation, active = true) {
    check(bounded(id), 'invalid_request', operation);
    const record = this.#records.get(id);
    check(record?.published, 'session_not_found', operation);
    if (active) check(!this.#stopping && record.state === 'ready' && !record.cancelled && !record.fault,
      'runtime_unavailable', operation);
    return record;
  }

  async startTurn(id, input, params = {}) {
    const record = this.#get(id, 'startTurn');
    check(empty(params) && typeof input === 'string' && input.trim().length > 0
      && Buffer.byteLength(input) <= 32 * 1024 && Buffer.from(input).toString('utf8') === input,
    'invalid_request', 'startTurn');
    // Reserve in this owner before TaskSession can suspend. A duplicate POST
    // must not enter TaskSession's not-fresh branch and close a valid turn.
    check(!record.turnReserved, 'turn_not_active', 'startTurn');
    record.turnReserved = true;
    try {
      const turn = await record.task.startTurn(input);
      check(!record.cancelled && record.state === 'ready' && !this.#stopping, 'runtime_start_unconfirmed', 'startTurn');
      return freeze({ local_session_id: record.id, provider_thread_id: record.thread, execution_epoch: record.epoch,
        local_turn_id: turn.local_turn_id, provider_turn_id: turn.provider_turn_id });
    } catch (failure) {
      // Validation above has already completed and task.startTurn synchronously
      // reserved this record. Its error can follow a real but unconfirmed write,
      // so this owner must release the same record before reporting failure.
      // Cleanup failure deliberately does not replace the unknown start error.
      try { await this.#cleanup(record); } catch { /* retained for same-owner retry */ }
      throw sanitize(failure, 'startTurn', 'runtime_start_unconfirmed');
    }
  }

  readEvents(id, options = {}) {
    const record = this.#get(id, 'readEvents', false);
    check(object(options) && Object.keys(options).every(key => key === 'afterSequence'), 'invalid_request', 'readEvents');
    const { afterSequence = 0 } = options;
    check(Number.isSafeInteger(afterSequence) && afterSequence >= 0, 'invalid_request', 'readEvents');
    try {
      const result = record.task.readEvents(afterSequence);
      return freeze({ status: result.status, events: result.events.map(event => ({ sequence: event.sequence,
        turn_id: event.turn_id, kind: event.kind, ...(event.status ? { status: event.status } : {}),
        data: event.kind === 'message_delta' ? { text: event.data.text }
          : event.kind === 'error' ? { code: 'text_task_failed' } : {} })), next_sequence: result.next_sequence });
    } catch (failure) { throw sanitize(failure, 'readEvents'); }
  }

  async interruptTurn(id, turnId) {
    const record = this.#get(id, 'interruptTurn');
    check(bounded(turnId), 'invalid_request', 'interruptTurn');
    try { return await record.task.interruptTurn(turnId); }
    catch (failure) { throw sanitize(failure, 'interruptTurn'); }
  }

  #closeNative(record) {
    if (record.ownerClosed) return Promise.resolve(true);
    if (record.nativeClose) return record.nativeClose;
    const attempt = Promise.resolve().then(async () => {
      check(record.owner && typeof record.owner.close === 'function', 'runtime_stop_unconfirmed', 'closeSession');
      const receipt = await record.owner.close();
      check(closeProof(record.owner, receipt), 'runtime_stop_unconfirmed', 'closeSession');
      if (this.#nativeCloseObserver) {
        const diagnostics = record.owner.diagnostics;
        check(Number.isInteger(diagnostics?.native_owner_pid) && diagnostics.native_owner_pid > 0
          && Number.isInteger(diagnostics?.native_owner_exit_code), 'runtime_stop_unconfirmed', 'closeSession');
        await this.#nativeCloseObserver(Object.freeze({
          schema: 'workbench_text_task_native_close_v1', attempt_id: record.attempt,
          native_sha256: this.#nativeOptions?.sha256 ?? null,
          native_owner_pid: diagnostics.native_owner_pid,
          native_owner_exit_code: diagnostics.native_owner_exit_code,
          ...receipt,
        }));
      }
      record.ownerClosed = true;
      return true;
    });
    record.nativeClose = attempt;
    void attempt.catch(() => { if (record.nativeClose === attempt) record.nativeClose = null; });
    return attempt;
  }

  #cleanup(record) {
    if (record.tombstone) return Promise.resolve(record.tombstone);
    if (record.closing) return record.closing;
    record.state = 'closing';
    const attempt = Promise.resolve().then(async () => {
      let receipt = null;
      try {
        // A live task owns interrupt dispatch/ACK before broker revocation.
        // Revoking here first can turn a valid cancellation into provider failure.
        // Resource-only startup cleanup still revokes immediately; faults and
        // creation cancellation retain their eager #cancel revocation above.
        if (record.task) receipt = await record.task.close();
        else record.broker?.revoke();
      } catch { /* Explicit native and broker closure below still run. */ }
      const resources = await Promise.allSettled([
        record.owner ? this.#closeNative(record) : Promise.resolve(!record.ownerAttempted),
        Promise.resolve().then(async () => {
          if (!record.broker) return !record.brokerAttempted;
          await record.broker.close(); return record.broker.snapshot().drained === true;
        }),
      ]);
      const closed = resources.every(result => result.status === 'fulfilled' && result.value === true);
      if (closed) record.detach?.();
      check(closed, 'runtime_stop_unconfirmed', 'closeSession');
      if (!record.task && !record.published) { this.#records.delete(record.id); return null; }
      check(!record.fault && isWorkbenchTextStopReceipt(receipt)
        && receipt.local_session_id === record.id && receipt.execution_epoch === record.epoch
        && receipt.provider_thread_id === record.thread, 'runtime_stop_unconfirmed', 'closeSession');
      record.state = 'closed';
      record.tombstone = freeze({ status: 'closed', stop_receipt: receipt });
      return record.tombstone;
    }).catch(failure => { throw sanitize(failure, 'closeSession', 'runtime_stop_unconfirmed'); });
    record.closing = attempt;
    void attempt.catch(() => { if (record.closing === attempt) record.closing = null; });
    return attempt;
  }

  closeSession(id) { return this.#cleanup(this.#get(id, 'closeSession', false)); }

  closeAll() {
    this.#stopping = true;
    if (this.#stopPromise) return this.#stopPromise;
    const records = [...this.#records.values()];
    for (const record of records) if (record.state === 'creating') this.#cancel(record);
    const attempt = Promise.resolve().then(async () => {
      // Close ready owners immediately while each incomplete creation settles
      // its own cancellation. One pending startup cannot delay other owners.
      const results = await Promise.allSettled(records.map(async record => {
        try { await record.creation; } catch { /* Cleanup remains required. */ }
        if (this.#records.has(record.id)) return this.#cleanup(record);
        return null; // Failed creation already proved resource-only cleanup.
      }));
      check(results.every(result => result.status === 'fulfilled'), 'runtime_stop_unconfirmed', 'closeAll');
      return freeze({ status: 'closed' });
    });
    this.#stopPromise = attempt;
    void attempt.catch(() => { if (this.#stopPromise === attempt) this.#stopPromise = null; });
    return attempt;
  }

  stop() { return this.closeAll(); }
}
