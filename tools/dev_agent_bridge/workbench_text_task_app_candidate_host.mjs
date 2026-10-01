// Explicit, temporary App acceptance host. No production entry imports this file.
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createHash, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { lstatSync, realpathSync, openSync, readFileSync, writeFileSync, fsyncSync, fstatSync, closeSync } from 'node:fs';
import { ExperimentalRuntimeApi, EXPERIMENTAL_RUNTIME_PREFIX } from './experimental_runtime_api.mjs';
import { RuntimeAdapterError } from './runtime_adapter.mjs';
import { WorkbenchTextTaskRuntimeAdapter } from './workbench_text_task_runtime_adapter.mjs';
import { createTextTaskBroker, sanitizeTextTaskExchangeFailureCode,
  sanitizeTextTaskExchangeTimeoutPhase, sanitizeTextTaskResponseRejectionPhase,
  sanitizeTextTaskResponseGateCode, sanitizeTextTaskResponseEventKind,
  sanitizeTextTaskResponseEventTypeClass, sanitizeTextTaskResponseEventPhase,
  sanitizeTextTaskResponseEventHeaderRelation, sanitizeTextTaskResponseEventPayloadShape,
  sanitizeTextTaskResponseEventControlKind,
  sanitizeTextTaskResponseSchemaLocation } from './workbench_text_task_broker.mjs';
import { launchWorkbenchTextNativeExecutor, assertTextTaskSupervisor,
  sanitizeNativeFailureCode, sanitizeNativeTransportFailureCode } from './workbench_text_task_native_executor.mjs';
import { CodexAppServerClient } from './codex_app_server_client.mjs';
import { isWorkbenchTextStopReceipt } from './workbench_text_stop_receipt.mjs';
import { createBridgeRuntimeShutdown, registerBridgeShutdownSignals } from './bridge_runtime_shutdown.mjs';
import { connectOwnedRecoveryNative } from './workbench_owned_recovery_native_binding.mjs';
import { witnessFailureClassification } from './workbench_owned_recovery_witness.mjs';
import { isWorkbenchProductHostBinding, readWorkbenchProductRequest } from './workbench_product_host_binding.mjs';
import { TEXT_TASK_CLI_SHA256 } from './workbench_text_task_runtime_pin.mjs';
import { exchangeTextOnly } from './workbench_text_gate_transport.mjs';
// The fixed product launcher obtains its transport from this pinned closure.
export { createWorkbenchProductGatewayTransport } from './workbench_product_gateway_transport.mjs';

export const APP_CANDIDATE_NATIVE_SHA256 = '674f159148f47c9702a360bfb4d32fd7b37604cd453a3104a3db08dd83fd02fc';
export const APP_CANDIDATE_PROFILE = 'workbench_text_only_v1';
export const APP_CANDIDATE_GOAL = '只输出从 1 到 2000 的整数，每行一个，不使用工具或外部资料。';
// Fixed comparison candidate only; keep the broker and zero-turn preflight defaults.
export const APP_CANDIDATE_EXCHANGE_TIMEOUT_MS = 180000;
export const APP_CANDIDATE_LOCAL_FAILURE_PLAN = 'reject_first_runtime_exchange_once_v1';
// Exact production TaskQueueExecution._input for the fixed goal and EMPTY previousText.
export const APP_CANDIDATE_INPUT = 'Complete the following standalone text task using only the supplied '
  + 'text. Return the requested text result. No tools, outside data, product '
  + 'actions, files, shell, network or memory writes are available. '
  + 'If the task needs those, explain the limitation in the text result.\n'
  + `Task goal:\n${APP_CANDIDATE_GOAL}\n`;
export const APP_CANDIDATE_ATTEST_PATH = '/p6/r7/candidate/attest';
const SELF = fileURLToPath(import.meta.url);
const SHA = /^[a-f0-9]{64}$/;
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const FACTS = ['process_close_observed', 'job_empty_verified', 'stdio_eof_verified',
  'rules_absent_verified', 'handles_closed_verified', 'helper_exits_verified'];
const exact = (v, keys) => v !== null && typeof v === 'object' && !Array.isArray(v)
  && Object.keys(v).length === keys.length && keys.every(k => Object.hasOwn(v, k));
const failure = code => new RuntimeAdapterError('Candidate operation could not be confirmed.', { code });
const check = (ok, code = 'invalid_request') => { if (!ok) throw failure(code); };
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const sameIdentity = (a, b) => a.dev === b.dev && a.ino === b.ino && a.size === b.size;

export function assertCandidatePath(filename, { directory = false } = {}) {
  check(typeof filename === 'string' && path.isAbsolute(filename) && path.resolve(filename) === filename);
  for (let current = filename; ; current = path.dirname(current)) {
    const stat = lstatSync(current);
    check(!stat.isSymbolicLink() && path.relative(current, realpathSync(current)) === '', 'runtime_unavailable');
    check(current === filename ? (directory ? stat.isDirectory() : stat.isFile()) : stat.isDirectory(), 'runtime_unavailable');
    if (path.dirname(current) === current) break;
  }
  return filename;
}
function pinnedBytes(filename, digest, limit) {
  assertCandidatePath(filename); const fd = openSync(filename, 'r');
  try {
    const before = fstatSync(fd); check(before.isFile() && before.size <= limit, 'runtime_unavailable');
    const data = readFileSync(fd);
    check(sameIdentity(before, fstatSync(fd)) && sameIdentity(before, lstatSync(filename))
      && hash(data) === digest, 'runtime_unavailable');
    assertCandidatePath(filename); return data;
  } finally { closeSync(fd); }
}

// The manifest is itself externally pinned. It names precisely this entry's
// static ESM closure; package imports and dynamic imports are not admitted.
export function verifyCandidateClosure(filename, digest) {
  check(SHA.test(digest));
  const manifest = JSON.parse(pinnedBytes(filename, digest, 128 * 1024).toString('utf8'));
  check(exact(manifest, ['schema', 'files']) && manifest.schema === 'p6_r7_app_candidate_closure_v1'
    && Array.isArray(manifest.files) && manifest.files.length > 0 && manifest.files.length <= 64);
  const files = new Map();
  for (const entry of manifest.files) {
    check(exact(entry, ['path', 'sha256']) && typeof entry.path === 'string' && entry.path.endsWith('.mjs')
      && SHA.test(entry.sha256) && !files.has(entry.path));
    files.set(entry.path, entry.sha256);
  }
  const seen = new Set();
  function visit(filename) {
    if (seen.has(filename)) return;
    check(files.has(filename), 'runtime_unavailable'); seen.add(filename);
    const source = pinnedBytes(filename, files.get(filename), 2 * 1024 * 1024).toString('utf8');
    check(!/\bimport\s*\(/.test(source), 'runtime_unavailable');
    for (const match of source.matchAll(/(?:\bfrom\s*|\bimport\s*)['"]([^'"\r\n]+)['"]/g)) {
      if (match[1].startsWith('node:')) continue;
      check(match[1].startsWith('./') && match[1].endsWith('.mjs'), 'runtime_unavailable');
      visit(path.resolve(path.dirname(filename), match[1]));
    }
  }
  for (const entry of ['workbench_text_task_app_candidate_host.mjs', 'workbench_text_task_app_successor_host.mjs']) {
    visit(path.join(path.dirname(SELF), entry));
  }
  check(seen.size === files.size, 'runtime_unavailable');
  return digest;
}

export function verifyCandidateNodeOptions(execArgv = process.execArgv, env = process.env) {
  // --use-env-proxy selects Node's supported fetch proxy path. Native CLI has
  // its own fixed NO_PROXY; this host never changes machine/process proxy values.
  check(execArgv.length === 1 && execArgv[0] === '--use-env-proxy'
    && !env.NODE_OPTIONS && !env.NODE_PATH, 'runtime_unavailable');
}

function noTurnProof(result, session) {
  const r = result?.stop_receipt, s = session?.execution_profile_receipt;
  return exact(result, ['status', 'stop_receipt']) && result.status === 'closed'
    && isWorkbenchTextStopReceipt(r) && r.profile === APP_CANDIDATE_PROFILE && r.version === 2
    && r.local_session_id === session.session_id && r.execution_epoch === s.execution_epoch
    && r.provider_thread_id === s.provider_thread_id && r.outcome === 'closed_without_turn'
    && r.local_turn_id === null && r.turn_id === null && r.interrupt_dispatched === false
    && r.interrupt_dispatch_sequence === null && r.provider_terminal_confirmed === false
    && r.provider_terminal_status === null && r.provider_terminal_sequence === null
    && r.cancellation_confirmed === false && r.local_child_close_observed === true && r.proxy_drained === true;
}
function resourceProof(record, preflight = false) {
  const receipt = record.nativeClose, snap = record.broker?.snapshot();
  return !!record.owner && exact(receipt, [...FACTS, 'cleanup_pending'])
    && FACTS.every(key => receipt[key] === true) && receipt.cleanup_pending === false
    && record.owner.cleanupPending === false && (preflight ? record.owner.diagnostics?.native_owner_exit_code === 0
      : [0, 3].includes(record.owner.diagnostics?.native_owner_exit_code)) && snap?.drained === true
    && (!preflight || (record.arms === 0 && snap.upstream_attempts === 0 && snap.response_released === false
      && snap.rejected_requests === 0 && snap.rejected_connections === 0
      && Number.isInteger(snap.metadata_rejections) && snap.metadata_rejections >= 0 && snap.metadata_rejections <= 8
      && snap.parsed_requests === snap.metadata_rejections && snap.admitted_connections === snap.parsed_requests));
}
function frozenCopy(value) {
  if (value === null || typeof value !== 'object') return value;
  const copy = Array.isArray(value) ? value.map(frozenCopy)
    : Object.fromEntries(Object.entries(value).map(([key, item]) => [key, frozenCopy(item)]));
  return Object.freeze(copy);
}
function facade(target, overrides) {
  return new Proxy(Object.create(null), { get(_target, key) {
    if (Object.hasOwn(overrides, key)) return overrides[key];
    const value = Reflect.get(target, key, target); return typeof value === 'function' ? value.bind(target) : value;
  } });
}
function json(res, status, value) {
  if (res.destroyed) return;
  const bytes = JSON.stringify(value);
  res.writeHead(status, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(bytes),
    'cache-control': 'no-store', connection: 'close' }); res.end(bytes);
}
async function challengeBody(req) {
  const chunks = []; let count = 0;
  for await (const chunk of req) { count += chunk.length; check(count <= 128); chunks.push(chunk); }
  const value = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  check(exact(value, ['challenge']) && SHA.test(value.challenge)); return value.challenge;
}

// Injection is host-owned and available only to pure tests. The CLI never takes
// factories, and a synthetic host cannot publish an actual-ready admission.
export function createAppCandidateHost(options, injected, productBinding = null) {
  check(productBinding === null || isWorkbenchProductHostBinding(productBinding));
  check((exact(options, ['executable', 'sha256', 'closureManifest', 'closureSha256', 'admissionPath'])
    || exact(options, ['executable', 'sha256', 'closureManifest', 'closureSha256', 'admissionPath', 'localFailurePlan'])
      && options.localFailurePlan === APP_CANDIDATE_LOCAL_FAILURE_PLAN)
    && typeof options.executable === 'string' && path.isAbsolute(options.executable)
    && options.sha256 === APP_CANDIDATE_NATIVE_SHA256 && SHA.test(options.closureSha256));
  if (injected !== undefined) check((exact(injected, ['factories']) || exact(injected, ['factories', 'witness']))
    && exact(injected.factories, ['createBroker', 'createOwner', 'createClient'])
    && Object.values(injected.factories).every(fn => typeof fn === 'function')
    && (injected.witness === undefined || (exact(injected.witness, ['preflightBarrier'])
      || exact(injected.witness, ['preflightBarrier', 'ownerRequested', 'ownerBound', 'ownerClosed',
        'admissionReady', 'hostClosed', 'ping', 'appStdinEof', 'captureNative', 'observeNative', 'closeNative', 'close']))
      && Object.values(injected.witness).every(fn => typeof fn === 'function')));
  if (!injected) { verifyCandidateNodeOptions(); assertTextTaskSupervisor(options.executable, options.sha256); }
  const verifyFiles = () => {
    verifyCandidateClosure(options.closureManifest, options.closureSha256);
    if (!injected) assertTextTaskSupervisor(options.executable, options.sha256);
  };
  verifyFiles();
  check(typeof options.admissionPath === 'string' && path.isAbsolute(options.admissionPath)
    && path.resolve(options.admissionPath) === options.admissionPath);
  assertCandidatePath(path.dirname(options.admissionPath), { directory: true });
  let output = openSync(options.admissionPath, 'wx', 0o600);
  try { assertCandidatePath(options.admissionPath); } catch (e) { closeSync(output); throw e; }
  const launch = randomUUID(), token = randomBytes(32).toString('hex');
  const nativeOptions = { executable: options.executable, sha256: options.sha256 };
  const underlying = injected?.factories ?? { createBroker: createTextTaskBroker,
    createOwner: launchWorkbenchTextNativeExecutor, createClient: args => new CodexAppServerClient(args) };
  const records = new Set(), sessions = new Map(), pending = new Set();
  let occupied = null, ready = false, stopping = false, started = false, startPromise, closePromise, count = 0;
  let admission = null, timer = null;
  let startupStage = 'created', startupFailure = null;
  const bindingStage = stage => {
    check(['witness_discovery', 'witness_addon_load', 'node_self_capture', 'witness_connect'].includes(stage));
    startupStage = stage;
  };
  let witness = injected?.witness ?? null, witnessTimer = null, witnessClose = null;
  const localFailurePlan = options.localFailurePlan ?? null;
  let localFailureConsumed = false;
  async function firstRuntimeExchange(...args) {
    // The real broker invokes exchange only after exact body, held peer and arm
    // checks. This opt-in fixed wrapper plan does not inspect or retain args.
    if (!localFailureConsumed) {
      localFailureConsumed = true;
      throw new Error('candidate_local_exchange_rejected');
    }
    return exchangeTextOnly(...args);
  }
  const audited = () => typeof witness?.ownerRequested === 'function';
  const startupAbort = new AbortController();
  const track = promise => { pending.add(promise); void promise.then(() => pending.delete(promise), () => pending.delete(promise)); return promise; };
  const verifyLive = () => {
    try { verifyFiles(); }
    catch {
      // A changed pin fences further dispatch and initiates same-owner cleanup.
      // Cleanup never depends on the integrity check succeeding again.
      stopping = true; ready = false; void shutdown().catch(() => {});
      throw failure('runtime_unavailable');
    }
  };
  function newAdapter(preflight = false) {
    check(!stopping && !witness?.serverQuarantined && (preflight || ready) && !occupied && count < 16, 'runtime_unavailable');
    const r = { adapter: null, broker: null, owner: null, nativeClose: null, arms: 0, session: null,
      startup: null, requestedAttempt: null, requestedPort: null, turnStart: null, stopReceipt: null, preflight, manifest: null,
      index: count, nativeEvidence: null, witnessBound: false, witnessClosed: false, witnessClosePromise: null };
    occupied = r; records.add(r); count++;
    const factories = {
      createBroker(args) {
        check(!r.broker, 'runtime_unavailable');
        r.broker = underlying.createBroker(preflight ? args : {
          ...args, exchangeTimeoutMs: APP_CANDIDATE_EXCHANGE_TIMEOUT_MS,
          ...(localFailurePlan && r.index === 1 ? { exchange: firstRuntimeExchange } : {}),
        });
        return facade(r.broker, { arm(input) {
          check(!preflight && !stopping && !witness?.serverQuarantined && ready
            && (productBinding ? productBinding.permitsTextInput(r.manifest, input) : input === APP_CANDIDATE_INPUT) && r.arms === 0);
          verifyLive(); r.arms++; return r.broker.arm(input);
        } });
      },
      createOwner(args) {
        check(!r.owner && r.requestedAttempt === null && UUID.test(args.attemptId)
          && Number.isInteger(args.brokerPort) && args.brokerPort > 0 && args.brokerPort <= 65535, 'runtime_unavailable');
        // This is the requested local binding, not a native startup attestation.
        // Keep it even if the factory throws or ready never arrives.
        r.requestedAttempt = args.attemptId; r.requestedPort = args.brokerPort;
        if (audited()) {
          let actual = null, closing = false, spawnSettled;
          // Return ownership synchronously. The promise below cannot spawn until
          // the independent witness has acknowledged this exact intent.
          spawnSettled = Promise.resolve().then(async () => {
            await witness.ownerRequested({ attempt_id: args.attemptId, broker_port: args.brokerPort, preflight });
            check(!closing && !stopping && !witness?.serverQuarantined, 'runtime_start_unconfirmed'); verifyLive();
            actual = underlying.createOwner(args);
            void actual.ready.catch(() => {});
            const nativePid = actual.diagnostics?.native_owner_pid;
            check(Number.isInteger(nativePid) && nativePid > 0, 'runtime_start_unconfirmed');
            r.nativeEvidence = await witness.captureNative({ pid: nativePid,
              imagePath: options.executable, imageSha256: options.sha256 });
          });
          const ready = spawnSettled.then(async () => {
            const value = await actual.ready;
            check(value?.attempt_id === args.attemptId && value.cli_sha256 === TEXT_TASK_CLI_SHA256
              && value.auth_mode === 'chatgpt' && value.network_boundary_verified === true
              && value.child_identity_verified === true && value.job_singleton === true
              && Number.isInteger(value.pid) && value.pid > 0 && value.pid <= 0xffffffff
              && typeof value.creation_time === 'string' && /^[1-9][0-9]{0,19}$/.test(value.creation_time), 'runtime_start_unconfirmed');
            r.startup = { attempt_id: value.attempt_id, pid: value.pid, creation_time: value.creation_time,
              network_boundary_verified: true, child_identity_verified: true, job_singleton: true };
            const n = r.nativeEvidence.identity;
            await witness.ownerBound({ owner_index: r.index, attempt_id: args.attemptId,
              native: { pid: n.pid, creation: n.creation, imagePath: n.imagePath, imageSha256: n.imageSha256 },
              // Child identity is the original native transport's checked started
              // frame. It is never substituted for the native owner's creation.
              child: { pid: value.pid, creation: value.creation_time } });
            r.witnessBound = true; return value;
          });
          void ready.catch(() => {});
          const overrides = { ready,
            async close() {
              closing = true;
              try { await spawnSettled; } catch { /* Close any actually acquired owner. */ }
              check(actual, 'runtime_stop_unconfirmed');
              const result = await actual.close(); r.nativeClose = result; return result;
            },
            async verifyPeer(socket) { return actual ? actual.verifyPeer(socket) : false; },
          };
          r.owner = new Proxy(Object.create(null), { get(_target, key) {
            if (Object.hasOwn(overrides, key)) return overrides[key];
            if (!actual) return key === 'cleanupPending' ? true : undefined;
            const value = Reflect.get(actual, key, actual); return typeof value === 'function' ? value.bind(actual) : value;
          } });
          return r.owner;
        }
        r.owner = underlying.createOwner(args);
        const actualReady = r.owner.ready.then(value => {
          // Copy only finite identity fields from the held native transport.
          if (value?.attempt_id === args.attemptId && UUID.test(value.attempt_id)
            && value.auth_mode === 'chatgpt' && value.network_boundary_verified === true
            && value.child_identity_verified === true && value.job_singleton === true
            && Number.isInteger(value.pid) && value.pid > 0 && value.pid <= 0xffffffff
            && typeof value.creation_time === 'string' && /^[1-9][0-9]{0,19}$/.test(value.creation_time)) {
            r.startup = { attempt_id: value.attempt_id, pid: value.pid, creation_time: value.creation_time,
              network_boundary_verified: true, child_identity_verified: true, job_singleton: true };
          }
          return value;
        });
        return facade(r.owner, { ready: actualReady,
          async close() { const result = await r.owner.close(); r.nativeClose = result; return result; } });
      },
      createClient: args => underlying.createClient(args),
    };
    r.adapter = new WorkbenchTextTaskRuntimeAdapter({ nativeOptions, factories });
    const free = () => { if (occupied === r) occupied = null; };
    return facade(r.adapter, {
      async startSession(config, manifest, extra) {
        try {
          check(!stopping && !witness?.serverQuarantined && (preflight || ready), 'runtime_unavailable'); verifyLive();
          check(preflight || !productBinding || productBinding.permitsTextSession(manifest));
          r.manifest = frozenCopy(manifest);
          r.session = await r.adapter.startSession(config, manifest, extra);
          sessions.set(r.session.session_id, r); return r.session;
        } catch (error) {
          // closeAll retains unknown resources and is retryable on this record.
          try { await r.adapter.closeAll(); free(); } catch { /* keep occupied */ }
          throw error;
        }
      },
      startTurn(id, input, params, extra) {
        check(!stopping && !witness?.serverQuarantined && ready && !preflight, 'runtime_unavailable');
        check((productBinding ? productBinding.permitsTextInput(r.manifest, input) : input === APP_CANDIDATE_INPUT)
          && exact(params ?? {}, [])); verifyLive();
        return r.adapter.startTurn(id, input, params, extra).then(result => { r.turnStart = result; return result; });
      },
      async closeSession(id) {
        const result = await r.adapter.closeSession(id);
        if (isWorkbenchTextStopReceipt(result?.stop_receipt)) r.stopReceipt = result.stop_receipt;
        check(isWorkbenchTextStopReceipt(result?.stop_receipt) && result.status === 'closed'
          && result.stop_receipt.local_session_id === id && resourceProof(r, preflight), 'runtime_stop_unconfirmed');
        await witnessOwnerClosed(r);
        free(); return result;
      },
      async closeAll() { const result = await closeRecord(r); free(); return result; },
    });
  }
  function textAdapter() {
    if (!productBinding) return newAdapter();
    let actual = null, closed = false;
    const call = (method, args) => {
      check(actual, 'runtime_unavailable');
      return actual[method](...args);
    };
    return {
      startSession(config, manifest, extra = {}) {
        // Validate before allocating a witnessed owner index. A rejected request
        // has no native intent or resource whose closure could be attested.
        check(!closed && !actual && productBinding.permitsTextSession(manifest));
        check(exact(config, ['runtime_profile']) && config.runtime_profile === APP_CANDIDATE_PROFILE);
        check(extra !== null && typeof extra === 'object' && !Array.isArray(extra)
          && Object.keys(extra).every(key => key === 'signal')
          && (extra.signal === undefined || extra.signal instanceof AbortSignal));
        check(!extra.signal?.aborted, 'runtime_start_unconfirmed');
        actual = newAdapter();
        return actual.startSession(config, manifest, extra);
      },
      startTurn: (...args) => call('startTurn', args),
      readEvents: (...args) => call('readEvents', args),
      interruptTurn: (...args) => call('interruptTurn', args),
      closeSession: (...args) => call('closeSession', args),
      closeAll() { closed = true; return actual ? actual.closeAll() : Promise.resolve(); },
    };
  }
  const api = new ExperimentalRuntimeApi({ enabled: true,
    adapterFactory: () => { throw failure('runtime_unavailable'); }, textAdapterFactory: textAdapter });
  const server = http.createServer({ maxHeaderSize: 8192 }, (req, res) => {
    const work = (async () => {
      try {
        check(!stopping && ready, 'runtime_unavailable');
        check(req.socket.remoteAddress === '127.0.0.1' && req.headers.origin === undefined);
        const port = server.address()?.port;
        check(req.headers.host === `127.0.0.1:${port}` && req.url.length <= 512);
        const raw = req.rawHeaders.map((v, i) => i % 2 === 0 ? v.toLowerCase() : null);
        check(raw.filter(v => v === 'x-p6-candidate-token').length === 1
          && raw.filter(v => v === 'x-p6-candidate-launch').length === 1);
        const supplied = req.headers['x-p6-candidate-token'];
        check(typeof supplied === 'string' && SHA.test(supplied)
          && timingSafeEqual(Buffer.from(supplied), Buffer.from(token))
          && req.headers['x-p6-candidate-launch'] === launch);
        verifyLive();
        const url = new URL(req.url, `http://127.0.0.1:${port}`);
        check(url.origin === `http://127.0.0.1:${port}` && !url.hash);
        if (req.method === 'POST' && url.pathname === APP_CANDIDATE_ATTEST_PATH && !url.search) {
          const challenge = await challengeBody(req); check(!stopping && ready && !witness?.serverQuarantined, 'runtime_unavailable');
          verifyLive();
          json(res, 200, { schema: 'p6_r7_app_candidate_attestation_v1', challenge, launch_id: launch,
            port, profile: APP_CANDIDATE_PROFILE, source_closure_sha256: options.closureSha256,
            native_sha256: options.sha256, no_turn_preflight_verified: !injected, ready: !injected }); return;
        }
        if (productBinding && url.pathname.startsWith('/p6/r7/product/')) {
          const request = await readWorkbenchProductRequest(req);
          check(!stopping && ready && !witness?.serverQuarantined, 'runtime_unavailable');
          verifyLive();
          const result = await productBinding.handle(request, url);
          check(result?.handled === true);
          json(res, result.status, result.body); return;
        }
        const prefix = EXPERIMENTAL_RUNTIME_PREFIX;
        if (req.method === 'POST' && url.pathname === `${prefix}/sessions` && !url.search) {
          check(!occupied && count < 16, 'runtime_unavailable');
        } else {
          const match = /^\/experimental\/v1\/runtime\/sessions\/([a-f0-9-]{36})(?:\/(events|turns)(?:\/([a-f0-9-]{36})\/interrupt)?)?$/.exec(url.pathname);
          check(match && UUID.test(match[1]) && sessions.has(match[1]));
          check((!match[2] && req.method === 'DELETE' && !url.search)
            || (match[2] === 'events' && req.method === 'GET' && /^\?after=(0|[1-9][0-9]{0,9})$/.test(url.search))
            || (match[2] === 'turns' && req.method === 'POST' && !url.search && (!match[3] || UUID.test(match[3]))));
        }
        check(await api.handle(req, res, url), 'runtime_unavailable');
      } catch { json(res, stopping || !ready ? 503 : 403, { error: 'candidate_request_rejected' }); }
    })();
    track(work);
  });
  server.requestTimeout = 15000; server.headersTimeout = 10000; server.keepAliveTimeout = 1;
  server.maxConnections = 16;
  server.on('clientError', (_error, socket) => socket.destroy());
  async function closeRecord(r) {
    const result = await r.adapter.closeAll();
    if (r.session) {
      try {
        const closed = await r.adapter.closeSession(r.session.session_id);
        if (isWorkbenchTextStopReceipt(closed?.stop_receipt)) r.stopReceipt = closed.stop_receipt;
      } catch { /* A resource-only close never manufactures a task receipt. */ }
    }
    await witnessOwnerClosed(r);
    return result;
  }
  async function witnessOwnerClosed(r) {
    if (!audited() || r.witnessClosed) return;
    if (r.witnessClosePromise) return r.witnessClosePromise;
    r.witnessClosePromise = (async () => {
      check(r.witnessBound && r.nativeEvidence && resourceProof(r, r.preflight), 'runtime_stop_unconfirmed');
      const observation = await witness.observeNative(r.nativeEvidence.handle);
      const expected = r.nativeEvidence.identity;
      check(observation?.state === 'exited' && observation.exitCode === r.owner.diagnostics.native_owner_exit_code
        && JSON.stringify(observation.identity) === JSON.stringify(expected), 'runtime_stop_unconfirmed');
      const broker = r.broker.snapshot();
      const proof = { owner_index: r.index, attempt_id: r.requestedAttempt,
        native_exit_code: observation.exitCode, ...r.nativeClose, broker_drained: true,
        native_postpin_verified: true, preflight_upstream_attempts: broker.upstream_attempts,
        preflight_arm_attempts: r.arms };
      await witness.ownerClosed(proof);
      await witness.closeNative(r.nativeEvidence.handle); r.witnessClosed = true;
    })();
    return r.witnessClosePromise;
  }
  const bridge = createBridgeRuntimeShutdown({ runtimeApi: { async stop() {
    const apiClose = api.stop({ permanent: true });
    // Observe all close rejections immediately while startup may still settle.
    const closed = Promise.allSettled([...records].map(r => closeRecord(r)));
    const results = await Promise.allSettled([apiClose, closed.then(values => {
      check(values.every(v => v.status === 'fulfilled'), 'runtime_stop_unconfirmed');
    })]);
    check(results.every(v => v.status === 'fulfilled'), 'runtime_stop_unconfirmed');
    occupied = null;
  } }, server, httpGraceMs: 1000 });
  function shutdown() {
    if (closePromise) return closePromise;
    // A server observation fences dispatch but is not the original stdin EOF
    // fact. Leave the handler able to report that fact before terminal closure.
    if (witness?.serverQuarantined && !witness?.eofReported)
      return Promise.reject(failure('runtime_stop_unconfirmed'));
    stopping = true; ready = false; startupAbort.abort(); clearTimeout(timer); clearInterval(witnessTimer);
    closePromise = (async () => {
      const closures = await Promise.allSettled([
        bridge.shutdown(),
        productBinding ? productBinding.closeForHostLifecycle() : Promise.resolve({ status: 'closed' }),
      ]);
      check(closures.every(result => result.status === 'fulfilled')
        && closures[1].value.status === 'closed', 'runtime_stop_unconfirmed');
      await Promise.allSettled([...pending]); verifyFiles();
      if (output !== null) { closeSync(output); output = null; }
      if (audited() && admission) {
        const encodedSnapshot = JSON.stringify(snapshot());
        check(/^[\x20-\x7e]*$/.test(encodedSnapshot), 'runtime_stop_unconfirmed');
        const hostHash = hash(encodedSnapshot);
        const manifest = await witness.hostClosed({ host_closed_sha256: hostHash });
        witnessClose = Object.freeze({ host_closed_sha256: hostHash, owner_manifest_sha256: manifest });
      }
      if (audited()) await witness.close();
      return Object.freeze({ status: 'closed', runtime_closed: true, http_server_closed: true,
        ...(witnessClose ? { witness_close: witnessClose } : {}) });
    })();
    void closePromise.catch(() => { closePromise = null; }); return closePromise;
  }
  async function appStdinEof() {
    // Invoked only by the pinned launcher's original stdin end handler, and
    // only when its existing explicit `shutdown` line was never observed.
    check(audited() && admission && !stopping, 'runtime_stop_unconfirmed');
    stopping = true; ready = false; startupAbort.abort(); clearInterval(witnessTimer);
    let rejected = false;
    try { await witness.appStdinEof(); } catch { rejected = true; }
    const result = await shutdown();
    check(!rejected, 'runtime_stop_unconfirmed'); return result;
  }
  async function start() {
    check(!started && !stopping, 'runtime_unavailable'); started = true;
    startPromise = (async () => {
      try {
        startupStage = 'http_listen';
        await new Promise((resolve, reject) => { server.once('error', reject); server.listen({ host: '127.0.0.1', port: 0, exclusive: true }, resolve); });
        check(![47831, 47841].includes(server.address().port), 'runtime_unavailable');
        timer = setTimeout(() => { void shutdown().catch(() => {}); }, 30 * 60 * 1000);
        if (!injected) witness = await connectOwnedRecoveryNative({
          sourceClosureSha256: options.closureSha256, nativeSha256: options.sha256, onStage: bindingStage });
        startupStage = 'preflight_barrier';
        if (witness) check(await witness.preflightBarrier() === true, 'runtime_unavailable');
        if (audited()) witnessTimer = setInterval(() => {
          void witness.ping().catch(() => { stopping = true; ready = false; void shutdown().catch(() => {}); });
        }, 30000);
        startupStage = 'preflight_owner';
        const preflight = newAdapter(true);
        const session = await preflight.startSession({ runtime_profile: APP_CANDIDATE_PROFILE },
          { execution_epoch: randomUUID() }, { signal: startupAbort.signal });
        startupStage = 'preflight_close';
        const result = await preflight.closeSession(session.session_id);
        check(noTurnProof(result, session), 'runtime_stop_unconfirmed');
        await preflight.closeAll(); check(!stopping, 'runtime_unavailable'); verifyFiles();
        startupStage = 'admission';
        admission = Object.freeze({ schema: 'p6_r7_app_candidate_admission_v1', launch_id: launch,
          base_uri: `http://127.0.0.1:${server.address().port}`, profile: APP_CANDIDATE_PROFILE,
          source_closure_sha256: options.closureSha256, native_sha256: options.sha256, admission_token: token });
        if (audited()) await witness.admissionReady({ launch_id: launch, admission_sha256: hash(JSON.stringify(admission)) });
        ready = true;
        // Synthetic tests get an in-memory seam, never an actual admission file.
        if (!injected) {
          assertCandidatePath(options.admissionPath); check(sameIdentity(fstatSync(output), lstatSync(options.admissionPath)), 'runtime_unavailable');
          writeFileSync(output, JSON.stringify(admission)); fsyncSync(output);
        }
        closeSync(output); output = null;
        startupStage = 'ready';
        return Object.freeze({ evidence: injected ? 'synthetic' : 'native_candidate', ready: !injected });
      } catch (error) {
        startupFailure = witnessFailureClassification(error);
        try { await shutdown(); } catch {
          // An audited startup never admitted HTTP work. Retain failed owner
          // obligations, but release its unpublished listener independently;
          // this does not manufacture runtime or witness closure evidence.
          if (audited() && server.listening) await new Promise(resolve => server.close(resolve));
        }
        throw failure('runtime_start_unconfirmed');
      }
    })();
    return startPromise;
  }
  function snapshot() {
    const boundedCount = v => Number.isSafeInteger(v) && v >= 0 && v <= 65535 ? v : null;
    const owners = [...records].map((r, index) => {
      const broker = r.broker?.snapshot(), diagnostics = r.owner?.diagnostics;
      const code = diagnostics?.native_owner_exit_code, pid = diagnostics?.native_owner_pid;
      const reported = diagnostics?.native_close_receipt;
      return { index, preflight: r.preflight, attempt_id: r.startup?.attempt_id ?? null,
        requested_attempt_id: r.requestedAttempt, requested_broker_port: r.requestedPort,
        // The launcher must independently verify PID/creation/image/parent.
        native_spawn_pid: Number.isInteger(pid) && pid > 0 && pid <= 0xffffffff ? pid : null,
        native_failure_code: sanitizeNativeFailureCode(diagnostics?.native_failure_code),
        transport_failure_code: sanitizeNativeTransportFailureCode(diagnostics?.transport_failure_code),
        native_reported_close_receipt: exact(reported, [...FACTS, 'cleanup_pending'])
          && [...FACTS, 'cleanup_pending'].every(key => typeof reported[key] === 'boolean') ? reported : null,
        native_startup: r.startup, execution_profile_receipt: r.session?.execution_profile_receipt ?? null,
        turn_start: r.turnStart, stop_receipt: r.stopReceipt,
        native_exit_code: Number.isInteger(code) && code >= -2147483648 && code <= 0xffffffff ? code : null,
        ...Object.fromEntries(FACTS.map(key => [key, typeof r.nativeClose?.[key] === 'boolean' ? r.nativeClose[key] : null])),
        cleanup_pending: r.owner?.cleanupPending !== false || r.nativeClose?.cleanup_pending !== false,
        broker: broker ? { ...Object.fromEntries(['admitted_connections', 'rejected_connections', 'parsed_requests',
          'metadata_rejections', 'rejected_requests', 'upstream_attempts'].map(key => [key, boundedCount(broker[key])])),
        arm_attempts: boundedCount(r.arms), response_released: typeof broker.response_released === 'boolean' ? broker.response_released : null,
        drained: typeof broker.drained === 'boolean' ? broker.drained : null,
        exchange_failure_code: sanitizeTextTaskExchangeFailureCode(broker.exchange_failure_code),
        exchange_timeout_phase: sanitizeTextTaskExchangeTimeoutPhase(
          broker.exchange_failure_code, broker.exchange_timeout_phase),
        response_rejection_phase: sanitizeTextTaskResponseRejectionPhase(
          broker.exchange_failure_code, broker.response_rejection_phase),
        response_gate_code: sanitizeTextTaskResponseGateCode(
          broker.exchange_failure_code, broker.response_gate_code),
        response_event_kind: sanitizeTextTaskResponseEventKind(
          broker.exchange_failure_code, broker.response_gate_code, broker.response_event_kind),
        response_event_type_class: sanitizeTextTaskResponseEventTypeClass(
          broker.exchange_failure_code, broker.response_gate_code, broker.response_event_type_class),
        response_event_phase: sanitizeTextTaskResponseEventPhase(
          broker.exchange_failure_code, broker.response_gate_code, broker.response_event_phase),
        response_event_header_relation: sanitizeTextTaskResponseEventHeaderRelation(
          broker.exchange_failure_code, broker.response_gate_code, broker.response_event_header_relation),
        response_event_payload_shape: sanitizeTextTaskResponseEventPayloadShape(
          broker.exchange_failure_code, broker.response_gate_code, broker.response_event_payload_shape),
        response_event_control_kind: sanitizeTextTaskResponseEventControlKind(
          broker.exchange_failure_code, broker.response_gate_code, broker.response_event_control_kind),
        response_schema_location: sanitizeTextTaskResponseSchemaLocation(
          broker.exchange_failure_code, broker.response_gate_code, broker.response_schema_location) } : null };
    });
    return frozenCopy({ schema: 'p6_r7_app_candidate_host_evidence_v2', synthetic: !!injected,
      launch_id: launch, port: admission ? Number(new URL(admission.base_uri).port) : null,
      profile: APP_CANDIDATE_PROFILE, source_closure_sha256: options.closureSha256, native_sha256: options.sha256,
      ready: ready && !injected && !witness?.serverQuarantined, stopping, owners,
      startup_stage: startupStage, startup_failure: startupFailure,
      ...(productBinding ? { product: productBinding.snapshot() } : {}),
      ...(localFailurePlan ? { local_failure_plan: {
        plan: localFailurePlan, owner_index: 1, consumed: localFailureConsumed,
        local_throw_count: localFailureConsumed ? 1 : 0, injected_upstream_dispatches: 0,
      } } : {}) });
  }
  return Object.freeze({ start, shutdown, appStdinEof, snapshot, get admission() { return admission; },
    get state() { return Object.freeze({ ready: ready && !injected && !witness?.serverQuarantined, synthetic: !!injected, stopping, owner_occupied: !!occupied }); } });
}

function cliOptions(argv) {
  const names = ['--native-executable', '--native-sha256', '--closure-manifest', '--closure-sha256', '--admission'];
  check(argv.length === 11 && argv[0] === '--apply-app-candidate-host'
    && names.every((name, index) => argv[index * 2 + 1] === name));
  return { executable: argv[2], sha256: argv[4], closureManifest: argv[6], closureSha256: argv[8], admissionPath: argv[10] };
}
if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  let host;
  try {
    host = createAppCandidateHost(cliOptions(process.argv.slice(2)));
    registerBridgeShutdownSignals({ shutdown: () => host.shutdown(),
      onClosed: () => { process.exitCode = 0; process.stdin.pause(); },
      onUnconfirmed: () => { process.exitCode = 4; } });
    process.stdin.once('end', () => { void host.shutdown().catch(() => { process.exitCode = 4; }); });
    process.stdin.resume();
    await host.start();
  } catch {
    process.exitCode = 4;
    if (host) { try { await host.shutdown(); process.stdin.pause(); } catch { /* retain, accept signal retry */ } }
  }
}

