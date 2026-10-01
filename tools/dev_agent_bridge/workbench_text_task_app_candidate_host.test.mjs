import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { EventEmitter } from 'node:events';
import { createHash, randomUUID } from 'node:crypto';
import { mkdtempSync, readFileSync, writeFileSync, symlinkSync, realpathSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { APP_CANDIDATE_NATIVE_SHA256, APP_CANDIDATE_GOAL, APP_CANDIDATE_INPUT, APP_CANDIDATE_PROFILE,
  APP_CANDIDATE_EXCHANGE_TIMEOUT_MS,
  APP_CANDIDATE_LOCAL_FAILURE_PLAN,
  APP_CANDIDATE_ATTEST_PATH, createAppCandidateHost, verifyCandidateClosure, verifyCandidateNodeOptions,
  assertCandidatePath } from './workbench_text_task_app_candidate_host.mjs';
import { TEXT_TASK_CLI_SHA256 } from './workbench_text_task_runtime_pin.mjs';
import { TEXT_TASK_MODEL } from './workbench_text_task_broker.mjs';
import { createOwnedRecoveryWitness } from './workbench_owned_recovery_witness.mjs';
import { verifyCandidateClosure as verifySuccessorClosure,
  createAppCandidateHost as createAppSuccessorHost } from './workbench_text_task_app_successor_host.mjs';
import { WorkbenchProductHostBinding } from './workbench_product_host_binding.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const entry = path.join(here, 'workbench_text_task_app_candidate_host.mjs');
const successorEntry = path.join(here, 'workbench_text_task_app_successor_host.mjs');
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const prefix = '/experimental/v1/runtime';
const pause = () => new Promise(resolve => setImmediate(resolve));
const receipt = () => ({ process_close_observed: true, job_empty_verified: true, stdio_eof_verified: true,
  rules_absent_verified: true, handles_closed_verified: true, helper_exits_verified: true, cleanup_pending: false });
function filesForEntry(filename = entry, seen = new Map()) {
  if (seen.has(filename)) return seen;
  const data = readFileSync(filename); seen.set(filename, { path: filename, sha256: sha(data) });
  for (const match of data.toString().matchAll(/(?:\bfrom\s*|\bimport\s*)['"]([^'"\r\n]+)['"]/g)) {
    if (match[1].startsWith('./')) filesForEntry(path.resolve(path.dirname(filename), match[1]), seen);
  }
  return seen;
}
function files(t) {
  const dir = mkdtempSync(path.join(tmpdir(), 'p6-app-host-pure-'));
  t.after(() => {
    const canonical = realpathSync(dir);
    assert.equal(path.dirname(canonical), realpathSync(tmpdir()));
    assert.match(path.basename(canonical), /^p6-app-host-pure-/);
    rmSync(canonical, { recursive: true, force: true });
  });
  const manifest = path.join(dir, 'closure.json');
  const closureFiles = filesForEntry(); filesForEntry(successorEntry, closureFiles);
  writeFileSync(manifest, JSON.stringify({ schema: 'p6_r7_app_candidate_closure_v1', files: [...closureFiles.values()] }));
  return { dir, options: { executable: path.join(dir, 'unused-native.exe'), sha256: APP_CANDIDATE_NATIVE_SHA256,
    closureManifest: manifest, closureSha256: sha(readFileSync(manifest)), admissionPath: path.join(dir, 'admission.json') } };
}
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
  const records = []; let current;
  const factories = {
    createBroker(args) {
      const r = { brokerOptions: args, closeCalls: 0, armCalls: 0, revoked: 0, requests: [], drained: false, exchangeAttempts: 0 };
      current = r; records.push(r);
      return r.broker = {
        async listen() { return 'http://127.0.0.1:32123/v1'; },
        arm(input) { assert.equal(input, options.expectedInput ?? APP_CANDIDATE_INPUT); r.armInput = input; r.armCalls++; },
        revoke() { r.revoked++; }, async close() { r.drained = true; },
        snapshot() { return { admitted_connections: 2, rejected_connections: 0, parsed_requests: 2, metadata_rejections: 2,
          rejected_requests: 0, upstream_attempts: r.exchangeAttempts, response_released: false, drained: r.drained, ...options.snapshot }; },
      };
    },
    createOwner(args) {
      const r = current;
      r.requested = { attemptId: args.attemptId, brokerPort: args.brokerPort };
      r.startup = { attempt_id: args.attemptId, type: 'started', seq: 1, cwd: 'D:\\fixed\\project0', auth_mode: 'chatgpt',
        provider: 'p6_native_startup', cli_sha256: TEXT_TASK_CLI_SHA256, pid: 123, creation_time: '123456',
        network_boundary_verified: true, child_identity_verified: true, job_singleton: true };
      return r.owner = { ready: options.ownerReady ? options.ownerReady(r, args) : Promise.resolve(r.startup), cleanupPending: true,
        diagnostics: { native_owner_exit_code: null, native_owner_pid: 456, ...options.diagnostics }, async verifyPeer() { return true; },
        async close() { r.closeCalls++;
          if (options.closeFailure?.(r)) throw new Error('PRIVATE_DETAIL');
          this.cleanupPending = false; this.diagnostics.native_owner_exit_code = options.exitCode ?? 0;
          return { ...receipt(), ...options.receipt }; },
      };
    },
    createClient() {
      const r = current;
      class Client extends EventEmitter {
        isReady = false; notificationSequence = 0;
        async start() { this.isReady = true; }
        async request(method, _params, dispatch) {
          r.requests.push(method);
          if (method === 'config/read') return nativeConfig();
          if (method === 'configRequirements/read') return { requirements: null };
          if (method === 'account/read') return { account: { type: 'chatgpt', email: 'PRIVATE_ACCOUNT' } };
          assert.equal(method, 'turn/start'); dispatch.onDispatched();
          let terminalStatus = 'completed';
          if (options.exchangeOnTurn) {
            r.exchangeAttempts++;
            if (r.brokerOptions.exchange) {
              try { await r.brokerOptions.exchange(); }
              catch (error) { assert.equal(error.constructor, Error); terminalStatus = 'failed'; }
            } else r.originalExchangeSelected = true;
          }
          queueMicrotask(() => this.notify('turn/completed', { threadId: 'thread', turn: { id: 'turn', status: terminalStatus } }));
          return { turn: { id: 'turn' } };
        }
        async startThread() {
          if (options.thread) await options.thread(records.length);
          return { thread: { id: 'thread' }, cwd: r.startup.cwd, model: TEXT_TASK_MODEL,
            modelProvider: 'p6_native_startup', approvalPolicy: 'never', sandbox: { type: 'readOnly' } };
        }
        async interruptTurn(_thread, _turn, dispatch) { dispatch.onDispatched(); return {}; }
        async waitForNotification() { throw new Error('PRIVATE_DETAIL'); }
        notify(method, params) { this.emit('notification', { sequence: ++this.notificationSequence, message: { method, params } }); }
      }
      return r.client = new Client();
    },
  };
  return { factories, records };
}
function client(t, host) {
  const agent = new http.Agent({ keepAlive: false, proxyEnv: Object.freeze(Object.create(null)) });
  t.after(() => agent.destroy());
  return function request(method, route, value, overrides = {}) {
    const a = host.admission; const body = value === undefined ? null : JSON.stringify(value);
    return new Promise((resolve, reject) => {
      const req = http.request(`${a.base_uri}${route}`, { method, agent, headers: {
        'x-p6-candidate-token': a.admission_token, 'x-p6-candidate-launch': a.launch_id,
        ...(body ? { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) } : {}), ...overrides,
      } }, res => {
        const chunks = []; res.on('data', x => chunks.push(x)); res.on('end', () => {
          resolve({ status: res.statusCode, body: JSON.parse(Buffer.concat(chunks).toString()) });
        });
      }); req.on('error', reject); req.end(body);
    });
  };
}
const createBody = () => ({ config: { runtime_profile: APP_CANDIDATE_PROFILE },
  context_manifest: { execution_epoch: randomUUID(), task_id: 'fixed-task', execution_mode: 'isolated_text_only' } });
async function started(t, settings) {
  let host; t.after(() => host?.shutdown());
  const f = fixture(settings), { options } = files(t);
  host = createAppCandidateHost(options, { factories: f.factories });
  await host.start();
  return { f, options, host, request: client(t, host) };
}

function auditedFixture(f, settings = {}) {
  const commands = [], order = [], natives = new Map(); let state = 'live';
  const protocol = createOwnedRecoveryWitness({ epoch: 'a'.repeat(64),
    sourceClosureSha256: settings.closureSha256, nativeSha256: APP_CANDIDATE_NATIVE_SHA256,
    adapter: { authenticated: true, async exchange(raw) {
      const c = JSON.parse(raw); commands.push(c); order.push(c.type);
      if (c.type === 'owner_requested') {
        if (settings.requestGate) await settings.requestGate;
        if (settings.rejectRequest) return '{}';
      }
      if (c.type === 'app_stdin_eof') state = 'app_quarantined';
      if (c.type === 'host_closed' && state !== 'app_quarantined') state = 'awaiting_app_close';
      return JSON.stringify({ schema: 'p6_r7_owned_recovery_reply_v1', epoch: c.epoch, sequence: c.sequence,
        type: { preflight_barrier: 'preflight_permitted', owner_requested: 'owner_registered', owner_bound: 'owner_binding_recorded',
          owner_closed: 'owner_close_recorded', admission_ready: 'admission_recorded', host_closed: 'host_close_recorded',
          app_stdin_eof: 'app_eof_recorded', ping: 'alive' }[c.type], state });
    } } });
  const witness = Object.fromEntries(['preflightBarrier','ownerRequested','ownerBound','ownerClosed','admissionReady',
    'hostClosed','ping','appStdinEof'].map(k => [k, protocol[k]]));
  Object.assign(witness, {
    async captureNative(pins) {
      order.push('captureNative');
      if (settings.rejectCapture) throw Error('synthetic_capture_rejected');
      const handle = {}, record = f.records.at(-1);
      assert.equal(pins.pid, record.owner.diagnostics.native_owner_pid);
      const identity = { pid: pins.pid, creation: '123455', parentPid: process.pid,
        imagePath: pins.imagePath, imageSha256: pins.imageSha256 };
      natives.set(handle, { record, identity }); return { handle, identity };
    },
    async observeNative(handle) {
      order.push('observeNative'); const n = natives.get(handle); assert(n);
      return { identity: n.identity, state: settings.nativeAlive ? 'alive' : 'exited',
        exitCode: n.record.owner.diagnostics.native_owner_exit_code };
    },
    async closeNative(handle) { assert(natives.delete(handle)); order.push('closeNative'); },
    async close() { order.push('channelClose'); },
  });
  const liveWitness = new Proxy(witness, { get(target, key) {
    return ['failed', 'ownerCount', 'serverQuarantined', 'eofReported'].includes(key) ? protocol[key] : Reflect.get(target, key);
  } });
  return { witness: liveWitness, commands, order, setServerState(value) { state = value; }, factories: { ...f.factories,
    createOwner(args) { order.push('nativeSpawn'); return f.factories.createOwner(args); } } };
}

test('audited owner intent ACK strictly precedes native spawn and full normal closure hashes actual snapshot', async t => {
  const f = fixture(), { options } = files(t); let release;
  const audit = auditedFixture(f, { closureSha256: options.closureSha256,
    requestGate: new Promise(resolve => { release = resolve; }) });
  const host = createAppCandidateHost(options, { factories: audit.factories, witness: audit.witness });
  t.after(() => host.shutdown().catch(() => {}));
  const start = host.start();
  while (!audit.commands.some(c => c.type === 'owner_requested')) await pause();
  assert(!audit.order.includes('nativeSpawn')); assert.equal(host.state.ready, false);
  release(); await start;
  assert.deepEqual(audit.order.slice(0, 5), ['preflight_barrier', 'owner_requested', 'nativeSpawn', 'captureNative', 'owner_bound']);
  const bound = audit.commands.find(c => c.type === 'owner_bound');
  assert.equal(bound.native_creation, '123455'); assert.equal(bound.child_creation, '123456');
  const result = await host.shutdown();
  assert.equal(result.runtime_closed, true); assert.equal(result.http_server_closed, true);
  assert.equal(result.witness_close.host_closed_sha256, sha(JSON.stringify(host.snapshot())));
  assert.match(result.witness_close.owner_manifest_sha256, /^[a-f0-9]{64}$/);
  assert.deepEqual(audit.commands.map(c => c.type), ['preflight_barrier', 'owner_requested', 'owner_bound', 'owner_closed', 'admission_ready', 'host_closed']);
  assert.equal(audit.commands.find(c => c.type === 'admission_ready').admission_sha256, sha(JSON.stringify(host.admission)));
});

test('owner intent rejection cannot spawn and native capture failure retains closed actual resource without witness success', async t => {
  for (const field of ['rejectRequest', 'rejectCapture', 'nativeAlive']) {
    const f = fixture(), { options } = files(t);
    const audit = auditedFixture(f, { closureSha256: options.closureSha256, [field]: true });
    const host = createAppCandidateHost(options, { factories: audit.factories, witness: audit.witness });
    await assert.rejects(host.start()); await assert.rejects(host.shutdown());
    assert(!audit.commands.some(c => ['admission_ready', 'host_closed'].includes(c.type)));
    assert.equal(audit.order.includes('nativeSpawn'), field !== 'rejectRequest');
    if (field !== 'rejectRequest') assert(f.records[0].closeCalls > 0);
    assert.equal(host.state.ready, false);
  }
});

test('unexpected original App stdin EOF fences new work and changes only the independently witnessed closure path', async t => {
  const f = fixture(), { options } = files(t);
  const audit = auditedFixture(f, { closureSha256: options.closureSha256 });
  const host = createAppCandidateHost(options, { factories: audit.factories, witness: audit.witness });
  t.after(() => host.shutdown().catch(() => {})); await host.start();
  const result = await host.appStdinEof();
  assert.equal(result.witness_close.host_closed_sha256, sha(JSON.stringify(host.snapshot())));
  const eof = audit.commands.find(c => c.type === 'app_stdin_eof');
  assert.deepEqual(Object.keys(eof), ['schema','epoch','sequence','type','stdin_eof_observed','stdin_end_handler_settled']);
  assert.equal(eof.stdin_eof_observed, true); assert.equal(eof.stdin_end_handler_settled, true);
  assert.equal(audit.commands.at(-1).type, 'host_closed'); assert.equal(host.state.stopping, true);
});

test('server quarantine fences new owners and turns without replacing actual stdin EOF or premature shutdown', async t => {
  const f = fixture(), { options } = files(t);
  const audit = auditedFixture(f, { closureSha256: options.closureSha256 });
  const host = createAppCandidateHost(options, { factories: audit.factories, witness: audit.witness });
  t.after(() => host.shutdown().catch(() => {})); await host.start();
  const request = client(t, host);
  const session = await request('POST', `${prefix}/sessions`, createBody());
  assert.equal(session.status, 200);
  assert.equal(audit.witness.ownerCount, 2);
  audit.setServerState('app_quarantined'); await audit.witness.ping();
  assert.equal(audit.witness.serverQuarantined, true); assert.equal(audit.witness.eofReported, false);
  assert.equal(host.state.stopping, false);
  await assert.rejects(host.shutdown()); assert.equal(host.state.stopping, false);
  assert.notEqual((await request('POST', `${prefix}/sessions/${session.body.session_id}/turns`, { input: APP_CANDIDATE_INPUT })).status, 200);
  assert.equal(f.records[1].armCalls, 0);
  assert.equal((await request('DELETE', `${prefix}/sessions/${session.body.session_id}`)).status, 200);
  assert.notEqual((await request('POST', `${prefix}/sessions`, createBody())).status, 200);
  assert.equal(f.records.length, 2); assert.equal(audit.witness.eofReported, false);
  const closed = await host.appStdinEof();
  assert.equal(audit.witness.eofReported, true); assert.equal(audit.witness.failed, false);
  assert.equal(audit.commands.filter(c => c.type === 'app_stdin_eof').length, 1);
  assert.equal(closed.witness_close.host_closed_sha256, sha(JSON.stringify(host.snapshot())));
});

test('HTTP attestation rejects after server quarantine without reporting stale readiness or manufacturing EOF', async t => {
  const f = fixture(), { options } = files(t);
  const audit = auditedFixture(f, { closureSha256: options.closureSha256 });
  const host = createAppCandidateHost(options, { factories: audit.factories, witness: audit.witness });
  t.after(() => host.shutdown().catch(() => {})); await host.start();
  const request = client(t, host), challenge = 'a'.repeat(64);
  assert.equal((await request('POST', APP_CANDIDATE_ATTEST_PATH, { challenge })).status, 200);
  audit.setServerState('app_quarantined'); await audit.witness.ping();
  const res = await request('POST', APP_CANDIDATE_ATTEST_PATH, { challenge });
  assert.equal(res.status, 403); assert.deepEqual(res.body, { error: 'candidate_request_rejected' });
  assert.equal(host.state.ready, false); assert.equal(host.snapshot().ready, false);
  assert.equal(host.state.stopping, false); assert.equal(audit.witness.eofReported, false);
  assert.equal(f.records.length, 1);
  const result = await host.appStdinEof();
  assert.equal(result.witness_close.host_closed_sha256, sha(JSON.stringify(host.snapshot())));
});

test('startup diagnostics classify only the fixed addon deadline and preserve failure before any owner', async t => {
  for (const [error, expected] of [[new Error('deadline_exceeded'), 'timeout'],
    [new Error('PRIVATE_PATH_ENV_CAPABILITY'), 'unknown'], [Object.assign(new Error('other'), { code: 'timeout' }), 'unknown']]) {
    const f = fixture(), { options } = files(t);
    const host = createAppCandidateHost(options, { factories: f.factories,
      witness: { async preflightBarrier() { throw error; } } });
    assert.equal(host.snapshot().startup_stage, 'created'); assert.equal(host.snapshot().startup_failure, null);
    await assert.rejects(host.start());
    assert.equal(f.records.length, 0); assert.equal(host.snapshot().startup_stage, 'preflight_barrier');
    assert.equal(host.snapshot().startup_failure, expected); assert.equal(host.state.ready, false);
    assert.doesNotMatch(JSON.stringify(host.snapshot()), /PRIVATE_PATH_ENV_CAPABILITY|deadline_exceeded/);
    await host.shutdown(); assert.equal(host.snapshot().startup_failure, expected);
  }
});

test('test-only witness barrier runs before any preflight native owner and rejects closed', async t => {
  const f = fixture(), { options } = files(t); let host;
  t.after(() => host?.shutdown());
  const order = [];
  const factories = { ...f.factories, createOwner(args) { order.push('owner'); return f.factories.createOwner(args); } };
  host = createAppCandidateHost(options, { factories, witness: { async preflightBarrier() { order.push('barrier'); return true; } } });
  await host.start();
  assert.deepEqual(order, ['barrier', 'owner']);
  await host.shutdown();

  const rejected = fixture(), next = files(t); let closed;
  t.after(() => closed?.shutdown());
  closed = createAppCandidateHost(next.options, { factories: rejected.factories,
    witness: { async preflightBarrier() { return false; } } });
  await assert.rejects(closed.start());
  assert.equal(rejected.records.length, 0);
});
test('both explicit entrypoints accept exactly one shared closure and reject unrelated extra or missing entry pins', t => {
  const { options } = files(t);
  assert.equal(verifyCandidateClosure(options.closureManifest, options.closureSha256), options.closureSha256);
  assert.equal(verifySuccessorClosure(options.closureManifest, options.closureSha256), options.closureSha256);
  const good = JSON.parse(readFileSync(options.closureManifest));
  for (const files of [good.files.filter(f => f.path !== successorEntry),
    [...good.files, { path: path.join(here, 'unrelated-review-only.mjs'), sha256: 'a'.repeat(64) }]]) {
    const raw = JSON.stringify({ ...good, files }); writeFileSync(options.closureManifest, raw);
    assert.throws(() => verifyCandidateClosure(options.closureManifest, sha(raw)));
    assert.throws(() => verifySuccessorClosure(options.closureManifest, sha(raw)));
  }
});

test('fixed local failure plan skips preflight, rejects exactly the first runtime exchange and leaves retry on original transport', async t => {
  const f = fixture({ exchangeOnTurn: true }), { options } = files(t);
  const audit = auditedFixture(f, { closureSha256: options.closureSha256 });
  const host = createAppCandidateHost({ ...options, localFailurePlan: APP_CANDIDATE_LOCAL_FAILURE_PLAN },
    { factories: audit.factories, witness: audit.witness });
  t.after(() => host.shutdown().catch(() => {})); await host.start();
  const request = client(t, host);
  assert.equal(f.records[0].brokerOptions.exchange, undefined);
  assert.equal(host.snapshot().local_failure_plan.consumed, false);
  for (const expected of ['failed', 'completed']) {
    const session = await request('POST', `${prefix}/sessions`, createBody()); assert.equal(session.status, 200);
    const id = session.body.session_id;
    const turn = await request('POST', `${prefix}/sessions/${id}/turns`, { input: APP_CANDIDATE_INPUT });
    assert.equal(turn.status, 200);
    const events = await request('GET', `${prefix}/sessions/${id}/events?after=0`);
    assert(events.body.events.some(e => e.status === expected));
    assert.equal((await request('DELETE', `${prefix}/sessions/${id}`)).status, 200);
  }
  assert.equal(typeof f.records[1].brokerOptions.exchange, 'function');
  assert.equal(f.records[2].brokerOptions.exchange, undefined);
  assert.equal(f.records[2].originalExchangeSelected, true);
  assert.equal(f.records[1].exchangeAttempts, 1); assert.equal(f.records[2].exchangeAttempts, 1);
  assert.deepEqual(host.snapshot().local_failure_plan, { plan: APP_CANDIDATE_LOCAL_FAILURE_PLAN,
    owner_index: 1, consumed: true, local_throw_count: 1, injected_upstream_dispatches: 0 });
  const closed = await host.shutdown();
  assert.equal(closed.witness_close.host_closed_sha256, sha(JSON.stringify(host.snapshot())));
});

test('default has no fault hook or diagnostic and unknown startup plans reject before ownership', async t => {
  const { f, host, request } = await started(t);
  assert.equal(Object.hasOwn(host.snapshot(), 'local_failure_plan'), false);
  assert.equal(f.records[0].brokerOptions.exchange, undefined);
  assert.equal((await request('POST', `${prefix}/sessions`, createBody())).status, 200);
  assert.equal(f.records[1].brokerOptions.exchange, undefined);
  for (const plan of [undefined, null, true, '', 'reject_all_exchanges', { enabled: true }]) {
    const { options } = files(t), untouched = fixture();
    assert.throws(() => createAppCandidateHost({ ...options, localFailurePlan: plan }, { factories: untouched.factories }));
    assert.equal(untouched.records.length, 0);
  }
});

test('fixed input matches production formatter with empty previousText, including final newline', () => {
  const dart = readFileSync(path.resolve(here, '../../lib/data/workbench_ai/task_queue/workbench_task_queue_execution.dart'), 'utf8');
  const formatter = dart.slice(dart.indexOf('String _input('), dart.indexOf('Future<void> _monitor'));
  const literals = [...formatter.slice(0, formatter.indexOf("'${lease.previousText")).matchAll(/'([^']*)'/g)]
    .map(match => match[1].replaceAll('\\n', '\n').replace('${lease.goal}', APP_CANDIDATE_GOAL)).join('');
  assert.equal(APP_CANDIDATE_INPUT, literals);
  assert.notEqual(APP_CANDIDATE_INPUT, APP_CANDIDATE_GOAL);
});

test('Node startup accepts only explicit proxy flag and rejects environment preload or extra flags', () => {
  verifyCandidateNodeOptions(['--use-env-proxy'], {});
  for (const [args, env] of [[[], {}], [['--use-env-proxy', '--import=x'], {}],
    [['--use-env-proxy'], { NODE_OPTIONS: '--import=private' }], [['--use-env-proxy'], { NODE_PATH: 'private' }]]) {
    assert.throws(() => verifyCandidateNodeOptions(args, env));
  }
});

test('exact closure rejects changed manifest, missing/extra pins and reparse ancestors; outputs are create-new', t => {
  const f = files(t); assert.equal(verifyCandidateClosure(f.options.closureManifest, f.options.closureSha256), f.options.closureSha256);
  const doc = JSON.parse(readFileSync(f.options.closureManifest)); doc.files.pop();
  writeFileSync(f.options.closureManifest, JSON.stringify(doc));
  assert.throws(() => verifyCandidateClosure(f.options.closureManifest, f.options.closureSha256));
  assert.throws(() => verifyCandidateClosure(f.options.closureManifest, sha(readFileSync(f.options.closureManifest))));
  const link = path.join(f.dir, 'linked'); symlinkSync(here, link, 'junction');
  assert.throws(() => assertCandidatePath(path.join(link, path.basename(entry))));
  const g = files(t); writeFileSync(g.options.admissionPath, 'existing');
  assert.throws(() => createAppCandidateHost(g.options, { factories: fixture().factories }));
  assert.equal(readFileSync(g.options.admissionPath, 'utf8'), 'existing');
});

test('real adapter preflight closes with zero turns; synthetic cannot publish actual admission or ready proof', async t => {
  const { f, host, options, request } = await started(t);
  assert.equal(f.records.length, 1); assert.equal(f.records[0].armCalls, 0);
  assert.equal(f.records[0].owner.cleanupPending, false);
  assert.equal(readFileSync(options.admissionPath, 'utf8'), '');
  assert.deepEqual(f.records[0].requests, ['config/read', 'configRequirements/read', 'account/read']);
  const challenge = 'a'.repeat(64);
  const res = await request('POST', APP_CANDIDATE_ATTEST_PATH, { challenge });
  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { schema: 'p6_r7_app_candidate_attestation_v1', challenge,
    launch_id: host.admission.launch_id, port: Number(new URL(host.admission.base_uri).port), profile: APP_CANDIDATE_PROFILE,
    source_closure_sha256: options.closureSha256, native_sha256: APP_CANDIDATE_NATIVE_SHA256,
    no_turn_preflight_verified: false, ready: false });
  assert.equal(Object.keys(host.admission).length, 7);
  assert.doesNotMatch(JSON.stringify(res.body), /PRIVATE|admission_token/);
});

test('capability, origin, challenge, unknown session and excluded API routes fail before allocating owners', async t => {
  const { f, request } = await started(t);
  const routes = [['GET', `${prefix}/auth`], ['GET', `${prefix}/capabilities`], ['POST', `${prefix}/sessions/resume`],
    ['POST', `${prefix}/host/stop-app-server`], ['DELETE', `${prefix}/sessions/${randomUUID()}`]];
  for (const [method, route] of routes) assert.equal((await request(method, route, {})).status, 403);
  assert.equal((await request('POST', APP_CANDIDATE_ATTEST_PATH, { challenge: 'a'.repeat(64), extra: true })).status, 403);
  assert.equal((await request('POST', `${prefix}/sessions`, createBody(), { 'x-p6-candidate-token': '0'.repeat(64) })).status, 403);
  assert.equal((await request('POST', `${prefix}/sessions`, createBody(), { origin: 'http://untrusted' })).status, 403);
  assert.equal(f.records.length, 1);
  assert.equal((await request('POST', `${prefix}/sessions`, { config: {} })).status, 503);
  assert.equal(f.records.length, 1);
});

test('single owner, exact public input, terminal and idempotent DELETE travel through real loopback JSON API', async t => {
  const { f, request } = await started(t);
  assert.equal(APP_CANDIDATE_EXCHANGE_TIMEOUT_MS, 180000);
  assert.equal(f.records[0].brokerOptions.exchangeTimeoutMs, 180000);
  const a = await request('POST', `${prefix}/sessions`, createBody()); assert.equal(a.status, 200);
  assert.equal(f.records[1].brokerOptions.exchangeTimeoutMs, 180000);
  assert.equal(typeof f.records[1].brokerOptions.verifyPeer, 'function');
  const id = a.body.session_id;
  assert.equal((await request('POST', `${prefix}/sessions`, createBody())).status, 403);
  for (const input of [APP_CANDIDATE_GOAL, `${APP_CANDIDATE_INPUT}\nprevious text`, 'arbitrary']) {
    assert.equal((await request('POST', `${prefix}/sessions/${id}/turns`, { input })).status, 400);
  }
  assert.equal(f.records[1].armCalls, 0);
  const turn = await request('POST', `${prefix}/sessions/${id}/turns`, { input: APP_CANDIDATE_INPUT });
  assert.equal(turn.status, 200); assert.equal(f.records[1].armCalls, 1);
  const events = await request('GET', `${prefix}/sessions/${id}/events?after=0`);
  assert.ok(events.body.events.some(event => event.status === 'completed'));
  const closed = await request('DELETE', `${prefix}/sessions/${id}`);
  assert.equal(closed.status, 200); assert.equal(closed.body.stop_receipt.outcome, 'closed');
  assert.deepEqual(await request('DELETE', `${prefix}/sessions/${id}`), closed);
  assert.equal((await request('POST', `${prefix}/sessions`, createBody())).status, 200);
  assert.equal(f.records.length, 3);
  assert.equal(f.records[2].brokerOptions.exchangeTimeoutMs, 180000);
});

test('failed preflight never publishes ready and keeps same resources available for close retry', async t => {
  let failing = true;
  const f = fixture({ closeFailure: () => failing }), { options } = files(t);
  const host = createAppCandidateHost(options, { factories: f.factories });
  const pending = host.start();
  await assert.rejects(pending, error => error.code === 'runtime_start_unconfirmed');
  assert.equal(host.admission, null); assert.equal(host.state.ready, false);
  assert.equal(f.records.length, 1); assert.equal(f.records[0].owner.cleanupPending, true);
  assert.equal(host.snapshot().owners[0].cleanup_pending, true);
  assert.equal(host.snapshot().owners[0].stop_receipt, null);
  assert.equal(readFileSync(options.admissionPath, 'utf8'), '');
  failing = false; assert.equal((await host.shutdown()).status, 'closed');
  assert.equal(f.records.length, 1); assert.equal(f.records[0].owner.cleanupPending, false);
});

test('shutdown while an HTTP create is pending closes that same owner and never admits a later creation', async t => {
  let release; const held = new Promise(resolve => { release = resolve; });
  const { f, host, request } = await started(t, { thread: count => count === 2 ? held : undefined });
  const creating = request('POST', `${prefix}/sessions`, createBody());
  while (f.records.length < 2 || !f.records[1].client) await pause();
  const closing = host.shutdown(); release();
  assert.equal((await creating).status, 503); assert.equal((await closing).status, 'closed');
  assert.equal(f.records.length, 2); assert.equal(f.records[1].owner.cleanupPending, false);
  await assert.rejects(request('POST', `${prefix}/sessions`, createBody()));
});

test('real request disconnect during creation closes the unpublished same owner before another can start', async t => {
  let release; const held = new Promise(resolve => { release = resolve; });
  const { f, host, request } = await started(t, { thread: count => count === 2 ? held : undefined });
  const a = host.admission, body = JSON.stringify(createBody());
  const agent = new http.Agent({ keepAlive: false, proxyEnv: Object.freeze(Object.create(null)) });
  t.after(() => agent.destroy());
  const req = http.request(`${a.base_uri}${prefix}/sessions`, { method: 'POST', agent, headers: {
    'x-p6-candidate-token': a.admission_token, 'x-p6-candidate-launch': a.launch_id,
    'content-length': Buffer.byteLength(body), 'content-type': 'application/json',
  } });
  req.on('error', () => {}); req.end(body);
  while (f.records.length < 2 || !f.records[1].client) await pause();
  req.destroy();
  for (let i = 0; i < 100 && !f.records[1].closeCalls; i++) await pause();
  assert.ok(f.records[1].closeCalls > 0, 'real abort reaches the already-held owner before thread release');
  assert.equal(f.records.length, 2); release();
  for (let i = 0; i < 100 && host.state.owner_occupied; i++) await pause();
  assert.equal(host.state.owner_occupied, false);
  assert.equal((await request('POST', `${prefix}/sessions`, createBody())).status, 200);
  assert.equal(f.records.length, 3);
});

test('HTTP close failure keeps the slot reserved and same DELETE can retry without creating another native owner', async t => {
  let failClose = false;
  const { f, request } = await started(t, { closeFailure: () => failClose });
  const made = await request('POST', `${prefix}/sessions`, createBody()); const id = made.body.session_id;
  failClose = true;
  assert.equal((await request('DELETE', `${prefix}/sessions/${id}`)).status, 503);
  assert.equal((await request('POST', `${prefix}/sessions`, createBody())).status, 403);
  assert.equal(f.records.length, 2); assert.equal(f.records[1].owner.cleanupPending, true);
  failClose = false;
  const closed = await request('DELETE', `${prefix}/sessions/${id}`);
  assert.equal(closed.status, 200); assert.equal(closed.body.stop_receipt.outcome, 'closed_without_turn');
  assert.equal(f.records.length, 2);
  assert.equal((await request('POST', `${prefix}/sessions`, createBody())).status, 200);
});

test('preflight rejects native exit4 and metadata-only broker violations without model dispatch', async t => {
  for (const settings of [{ exitCode: 4 }, { snapshot: { upstream_attempts: 1 } }, { snapshot: { rejected_requests: 1 } }]) {
    const f = fixture(settings), { options } = files(t);
    const host = createAppCandidateHost(options, { factories: f.factories });
    await assert.rejects(host.start()); assert.equal(host.admission, null);
    assert.equal(f.records[0].armCalls, 0); await host.shutdown();
  }
});

test('closure drift fences dispatch and initiates same-owner cleanup even while post-pin remains invalid', async t => {
  const { f, options, host, request } = await started(t);
  const made = await request('POST', `${prefix}/sessions`, createBody());
  const original = readFileSync(options.closureManifest);
  try {
    writeFileSync(options.closureManifest, '{}');
    const rejected = await request('POST', `${prefix}/sessions/${made.body.session_id}/turns`, { input: APP_CANDIDATE_INPUT });
    assert.equal(rejected.status, 503); assert.equal(host.state.stopping, true);
    await assert.rejects(host.shutdown());
    assert.equal(f.records[1].owner.cleanupPending, false);
    assert.equal(f.records[1].armCalls, 0); assert.equal(f.records.length, 2);
  } finally { writeFileSync(options.closureManifest, original); }
  assert.equal((await host.shutdown()).status, 'closed');
});

test('snapshot captures actual facade results and shutdown tombstones using a bounded secret-free synthetic schema', async t => {
  const { host, request } = await started(t);
  const initial = host.snapshot();
  assert.equal(initial.schema, 'p6_r7_app_candidate_host_evidence_v2');
  assert.equal(initial.synthetic, true); assert.equal(initial.ready, false);
  assert.equal(initial.owners[0].preflight, true);
  assert.equal(initial.owners[0].stop_receipt.outcome, 'closed_without_turn');
  assert.equal(initial.owners[0].cleanup_pending, false);
  assert.deepEqual(Object.keys(initial).sort(), ['schema', 'synthetic', 'launch_id', 'port', 'profile',
    'source_closure_sha256', 'native_sha256', 'ready', 'stopping', 'owners', 'startup_stage', 'startup_failure'].sort());
  assert.equal(initial.startup_stage, 'ready'); assert.equal(initial.startup_failure, null);
  const session = await request('POST', `${prefix}/sessions`, createBody());
  const turn = await request('POST', `${prefix}/sessions/${session.body.session_id}/turns`, { input: APP_CANDIDATE_INPUT });
  const live = host.snapshot();
  assert.deepEqual(live.owners[1].turn_start, turn.body);
  assert.deepEqual(live.owners[1].execution_profile_receipt, session.body.execution_profile_receipt);
  assert.equal(live.owners[1].stop_receipt, null); assert.equal(live.owners[1].cleanup_pending, true);
  await host.shutdown(); // No DELETE: closeAll must read the same adapter's tombstone.
  const closed = host.snapshot();
  assert.equal(closed.owners[1].stop_receipt.outcome, 'closed');
  assert.equal(closed.owners[1].stop_receipt.local_session_id, session.body.session_id);
  for (const r of closed.owners) {
    assert.match(r.attempt_id, /^[0-9a-f-]{36}$/);
    assert.equal(r.attempt_id, r.native_startup.attempt_id);
    assert.equal(r.requested_attempt_id, r.attempt_id);
    assert.equal(r.requested_broker_port, 32123); assert.equal(r.native_spawn_pid, 456);
    assert.equal(r.native_exit_code, 0); assert.equal(r.cleanup_pending, false); assert.equal(r.broker.drained, true);
    for (const key of Object.keys(receipt()).filter(key => key !== 'cleanup_pending')) assert.equal(r[key], true);
  }
  const serialized = JSON.stringify(closed);
  assert.doesNotMatch(serialized, /PRIVATE|ACCOUNT|TOKEN|email|admission_token|cwd|stderr|commandline/);
  assert.ok(!serialized.includes(host.admission.admission_token)); assert.ok(!serialized.includes(APP_CANDIDATE_INPUT));
  assert.throws(() => { closed.owners[0].preflight = false; }, TypeError);
});

test('pre-ready failure preserves requested attempt and safe diagnostics without manufacturing startup or cleanup proof', async t => {
  let release, rejectReady, failedClose = true;
  const ready = new Promise((resolve, reject) => { release = resolve; rejectReady = reject; });
  const f = fixture({ ownerReady: () => ready, closeFailure: () => failedClose,
    diagnostics: { native_failure_code: 'task_helper_ready_wait_win32_1460',
      transport_failure_code: 'native_startup_timeout', native_close_receipt: { ...receipt(),
        rules_absent_verified: false, helper_exits_verified: false, cleanup_pending: true } } });
  const { options } = files(t), host = createAppCandidateHost(options, { factories: f.factories });
  t.after(async () => { failedClose = false; release?.(f.records[0].startup); await host.shutdown(); });
  const starting = assert.rejects(host.start(), error => error.code === 'runtime_start_unconfirmed');
  while (!f.records[0]?.owner) await pause();
  const before = host.snapshot().owners[0];
  assert.equal(before.requested_attempt_id, f.records[0].requested.attemptId);
  assert.equal(before.requested_broker_port, f.records[0].requested.brokerPort);
  assert.equal(before.native_spawn_pid, 456);
  assert.equal(before.attempt_id, null); assert.equal(before.native_startup, null);
  assert.equal(before.execution_profile_receipt, null); assert.equal(before.stop_receipt, null);
  assert.equal(before.native_failure_code, 'task_helper_ready_wait_win32_1460');
  assert.equal(before.transport_failure_code, 'native_startup_timeout');
  assert.equal(before.native_reported_close_receipt.rules_absent_verified, false);
  assert.equal(before.rules_absent_verified, null); assert.equal(before.cleanup_pending, true);
  rejectReady(new Error('PRIVATE_STARTUP_DETAIL'));
  await starting;
  const after = host.snapshot();
  assert.equal(after.owners.length, 1); assert.equal(after.owners[0].requested_attempt_id, before.requested_attempt_id);
  assert.equal(after.owners[0].cleanup_pending, true); assert.equal(host.admission, null);
  assert.doesNotMatch(JSON.stringify(after), /PRIVATE|cwd|admission_token/);
  failedClose = false; await host.shutdown();
});

test('injected malformed diagnostic fields stay null and snapshots are detached immutable copies', async t => {
  const { host, f } = await started(t, { diagnostics: {
    native_owner_pid: 'PRIVATE_PID', native_failure_code: 'task_PRIVATE_failed',
    transport_failure_code: 'native_PRIVATE', native_close_receipt: { ...receipt(), raw: 'PRIVATE_DETAIL' } } });
  const first = host.snapshot().owners[0];
  for (const key of ['native_spawn_pid', 'native_failure_code', 'transport_failure_code', 'native_reported_close_receipt']) {
    assert.equal(first[key], null);
  }
  f.records[0].owner.diagnostics.native_close_receipt = receipt();
  const second = host.snapshot().owners[0];
  f.records[0].owner.diagnostics.native_close_receipt.cleanup_pending = true;
  assert.equal(second.native_reported_close_receipt.cleanup_pending, false);
  assert.throws(() => { second.native_reported_close_receipt.cleanup_pending = true; }, TypeError);
  assert.doesNotMatch(JSON.stringify(first), /PRIVATE/);
});

test('host projects only the exchange code vocabulary and preserves an immutable secret-free snapshot', async t => {
  const extra = { exchange_failure_code: null, raw: 'PRIVATE_BODY', httpStatus: 599,
    responseMetadata: { authorization: 'PRIVATE_AUTH' } };
  const { host } = await started(t, { snapshot: extra });
  const before = host.snapshot();
  assert.equal(before.owners[0].broker.exchange_failure_code, null);
  for (const code of ['timeout', 'aborted', 'http_status', 'unsupported_content_type',
    'missing_body', 'request_rejected', 'response_rejected', 'transport_failed']) {
    extra.exchange_failure_code = code;
    const observed = host.snapshot();
    assert.equal(observed.owners[0].broker.exchange_failure_code, code);
    assert.equal(observed.owners[0].stop_receipt.outcome, 'closed_without_turn');
    assert.equal(observed.owners[0].broker.upstream_attempts, 0);
    assert.equal(observed.owners[0].cleanup_pending, false);
    assert.doesNotMatch(JSON.stringify(observed), /PRIVATE|httpStatus|responseMetadata/);
    assert.throws(() => { observed.owners[0].broker.exchange_failure_code = null; }, TypeError);
  }
  for (const code of [undefined, null, false, 500, 'PRIVATE_CODE', 'invalid_target',
    new String('timeout'), { toString() { throw new Error('PRIVATE_COERCION'); } }]) {
    extra.exchange_failure_code = code;
    assert.equal(host.snapshot().owners[0].broker.exchange_failure_code, null);
  }
  assert.equal(before.owners[0].broker.exchange_failure_code, null);
});

test('host rechecks timeout phases and rejects non-timeout or coerced metadata', async t => {
  const extra = { exchange_failure_code: 'timeout', exchange_timeout_phase: null,
    raw: 'PRIVATE_RESPONSE', authorization: 'PRIVATE_AUTH' };
  const { host } = await started(t, {snapshot:extra});
  const before = host.snapshot();
  const phases = ['request_preparation', 'before_response_headers', 'response_headers_before_body_byte',
    'response_body_before_eof', 'after_response_eof'];
  for (const phase of phases) {
    extra.exchange_timeout_phase = phase;
    const snapshot = host.snapshot();
    assert.equal(snapshot.owners[0].broker.exchange_timeout_phase, phase);
    assert.equal(snapshot.owners[0].stop_receipt.outcome, 'closed_without_turn');
    assert.equal(snapshot.owners[0].cleanup_pending, false);
    assert.doesNotMatch(JSON.stringify(snapshot), /PRIVATE|authorization/);
    assert.throws(() => { snapshot.owners[0].broker.exchange_timeout_phase = null; }, TypeError);
  }
  for (const phase of [undefined, null, 1, false, 'PRIVATE_PHASE', new String(phases[0]),
    { toString() { throw Error('PRIVATE_COERCION'); } }]) {
    extra.exchange_timeout_phase = phase;
    assert.equal(host.snapshot().owners[0].broker.exchange_timeout_phase, null);
  }
  extra.exchange_timeout_phase = phases[1];
  for (const code of ['aborted', 'http_status', 'response_rejected', 'transport_failed', null,
    'PRIVATE_CODE', new String('timeout'), {toString(){throw Error('PRIVATE_COERCION');}}]) {
    extra.exchange_failure_code = code;
    assert.equal(host.snapshot().owners[0].broker.exchange_timeout_phase, null);
  }
  assert.equal(before.owners[0].broker.exchange_timeout_phase, null);
});

test('host rechecks response rejection diagnostics and keeps raw broker fields out', async t => {
  const extra = { exchange_failure_code: 'response_rejected', response_rejection_phase: 'after_eof',
    response_gate_code: 'unknown_field', response_event_kind: 'PRIVATE_PROVIDER_EVENT',
    response_event_type_class: 'PRIVATE_CLASS', response_event_phase: 'PRIVATE_PHASE', response_schema_location: 'response',
    response_event_header_relation: 'PRIVATE_HEADER', response_event_payload_shape: 'PRIVATE_SHAPE',
    response_event_control_kind: 'PRIVATE_CONTROL',
    raw: 'PRIVATE_RESPONSE', responseMetadata: { authorization: 'PRIVATE_AUTH' } };
  const { host } = await started(t, { snapshot: extra });
  let broker = host.snapshot().owners[0].broker;
  assert.equal(broker.response_rejection_phase, 'after_eof');
  assert.equal(broker.response_gate_code, 'unknown_field');
  assert.equal(broker.response_event_kind, null);
  assert.equal(broker.response_event_type_class, null);
  assert.equal(broker.response_event_phase, null);
  assert.equal(broker.response_event_header_relation, null);
  assert.equal(broker.response_event_payload_shape, null);
  assert.equal(broker.response_event_control_kind, null);
  assert.equal(broker.response_schema_location, 'response');
  assert.doesNotMatch(JSON.stringify(broker), /PRIVATE|responseMetadata|authorization/);
  for (const [phase, gate, eventKind, typeClass, eventPhase, location, relation, shape, control] of [
    ['before_eof', 'input_limit', 'response.queued', 'response_namespace', 'after_text', 'response', 'absent', 'type_only', 'ping'],
    ['after_eof', 'invalid_json', 'response.queued', 'response_namespace', 'after_text', 'response', 'absent', 'type_only', 'ping'],
    ['after_eof', 'unknown_field', 'response.queued', 'response_namespace', 'after_text', 'sse_item', 'absent', 'type_only', 'ping'],
    ['after_eof', 'unsupported_event', 'response.queued', 'response_namespace', 'after_text', 'response', 'absent', 'type_only', 'ping'],
    ['after_eof', 'unsupported_event', 'PRIVATE_PROVIDER_EVENT', 'PRIVATE_CLASS', 'PRIVATE_PHASE', 'response', 'PRIVATE_HEADER', 'PRIVATE_SHAPE', 'PRIVATE_CONTROL'],
    ['PRIVATE_PHASE', 'unsupported_event', 'response.queued', 'response_namespace', 'after_text', 'response', 'absent', 'type_only', 'ping'],
    ['after_eof', 'PRIVATE_GATE', 'response.queued', 'response_namespace', 'after_text', 'response', 'absent', 'type_only', 'ping'],
    ['after_eof', 'unknown_field', 'response.queued', 'response_namespace', 'after_text', 'PRIVATE_LOCATION', 'absent', 'type_only', 'ping'],
  ]) {
    extra.response_rejection_phase = phase;
    extra.response_gate_code = gate;
    extra.response_event_kind = eventKind;
    extra.response_event_type_class = typeClass;
    extra.response_event_phase = eventPhase;
    extra.response_event_header_relation = relation;
    extra.response_event_payload_shape = shape;
    extra.response_event_control_kind = control;
    extra.response_schema_location = location;
    broker = host.snapshot().owners[0].broker;
    const responseRejected = extra.exchange_failure_code === 'response_rejected';
    assert.equal(broker.response_rejection_phase,
      responseRejected && ['before_eof', 'after_eof'].includes(phase) ? phase : null);
    assert.equal(broker.response_gate_code,
      responseRejected && ['input_limit', 'invalid_json', 'unknown_field', 'unsupported_event'].includes(gate) ? gate : null);
    assert.equal(broker.response_event_kind,
      responseRejected && gate === 'unsupported_event' ? (eventKind === 'response.queued' ? eventKind : 'other') : null);
    assert.equal(broker.response_event_type_class,
      responseRejected && gate === 'unsupported_event' && typeClass === 'response_namespace' ? typeClass : null);
    assert.equal(broker.response_event_phase,
      responseRejected && gate === 'unsupported_event' && eventPhase === 'after_text' ? eventPhase : null);
    assert.equal(broker.response_event_header_relation,
      responseRejected && gate === 'unsupported_event' && relation === 'absent' ? relation : null);
    assert.equal(broker.response_event_payload_shape,
      responseRejected && gate === 'unsupported_event' && shape === 'type_only' ? shape : null);
    assert.equal(broker.response_event_control_kind,
      responseRejected && gate === 'unsupported_event' ? (control === 'ping' ? control : 'other') : null);
    assert.equal(broker.response_schema_location,
      responseRejected && gate === 'unknown_field' && ['response', 'sse_item'].includes(location) ? location : null);
    assert.doesNotMatch(JSON.stringify(broker), /PRIVATE|responseMetadata|authorization/);
  }
  extra.exchange_failure_code = 'timeout';
  extra.response_rejection_phase = 'after_eof';
  extra.response_gate_code = 'unknown_field';
  extra.response_event_kind = 'response.queued';
  extra.response_event_type_class = 'response_namespace';
  extra.response_event_phase = 'after_text';
  extra.response_event_header_relation = 'absent';
  extra.response_event_payload_shape = 'type_only';
  extra.response_event_control_kind = 'ping';
  extra.response_schema_location = 'response';
  broker = host.snapshot().owners[0].broker;
  assert.equal(broker.response_rejection_phase, null);
  assert.equal(broker.response_gate_code, null);
  assert.equal(broker.response_event_kind, null);
  assert.equal(broker.response_event_type_class, null);
  assert.equal(broker.response_event_phase, null);
  assert.equal(broker.response_event_header_relation, null);
  assert.equal(broker.response_event_payload_shape, null);
  assert.equal(broker.response_event_control_kind, null);
  assert.equal(broker.response_schema_location, null);
});

// Product composition tests use a newly allocated private loopback listener and
// an in-memory ordinary transport. They never call the existing Gateway/native.
const productRuntime = '/p6/r7/product/conversation' + prefix;
const productTask = '/p6/r7/product/task';
const productClose = '/p6/r7/product/conversation/close';
const ordinarySession = 'ordinary-owned', ordinaryProvider = 'ordinary-provider', ordinaryTurn = 'ordinary-turn';
const productGoal = 'Write the public word READY once.';
const productInput = APP_CANDIDATE_INPUT.replace(APP_CANDIDATE_GOAL, productGoal);
const productTool = { name: 'manage_long_task_queue', description: 'Candidate queue tool',
  input_schema: { type: 'object', additionalProperties: false, properties: { action: { type: 'string' } } } };
function ordinaryFixture(settings = {}) {
  const calls = [], turnIds = [];
  const metadata = () => ({ provider: 'codex', provider_session_id: ordinaryProvider });
  const session = () => ({ session_id: ordinarySession, status: 'idle', model: 'existing-approved-model', provider_metadata: metadata() });
  const evidence = turnId => ({ provider_session_id: ordinaryProvider, turn_id: turnId,
    provider_terminal_confirmed: !settings.closeUnknown, provider_terminal_status: settings.closeUnknown ? null : 'interrupted',
    provider_terminal_sequence: settings.closeUnknown ? null : 31, source: settings.closeUnknown ? null : 'turn/completed',
    interrupt_requested: true, interrupt_acknowledged: true, cancellation_confirmed: !settings.closeUnknown });
  const transport = async r => {
    calls.push(r);
    if (r.path === `${prefix}/sessions`) {
      if (settings.startGate) await settings.startGate;
      return session();
    }
    if (r.path === `${prefix}/sessions/${ordinarySession}/turns`) {
      turnIds.push(ordinaryTurn);
      return { ...session(), status: 'running', turn_id: ordinaryTurn, stop_evidence: {
        provider_session_id: ordinaryProvider, turn_id: ordinaryTurn, provider_terminal_confirmed: false } };
    }
    if (r.path === `${prefix}/sessions/${ordinarySession}/events?after=0`) return {
      session_id: ordinarySession, status: 'active', next_sequence: 1, events: [{ schema_version: 1,
        event_id: `${ordinarySession}:1`, session_id: ordinarySession, turn_id: ordinaryTurn, sequence: 1,
        kind: 'tool_call', status: 'running', data: { tool_call_id: 'ordinary-call', tool_name: productTool.name,
          arguments: { action: 'status', request_id: 'public-request' } }, provider_metadata: { provider: 'codex' } }] };
    if (r.path === `${prefix}/tool-calls/ordinary-call`) return {
      tool_call_id: 'ordinary-call', accepted: true, success: r.body.success };
    if (r.method === 'DELETE' && r.path === `${prefix}/sessions/${ordinarySession}`) {
      settings.onDelete?.();
      if (settings.closeGate) await settings.closeGate;
      return { ...session(), status: 'closed', stop_evidence: { local_binding_closed: true,
        provider_terminal_confirmed: turnIds.length > 0 && !settings.closeUnknown, turns: turnIds.map(evidence) } };
    }
    throw new Error('unexpected ordinary fake request');
  };
  const taskId = randomUUID(), scope = 'a'.repeat(64);
  const binding = new WorkbenchProductHostBinding({ conversationId: 'product-conversation', taskScopeHash: scope,
    dynamicTool: productTool, transport });
  return { binding, calls, taskId, scope, turnIds,
    bind: { task_id: taskId, scope_hash: scope, goal: productGoal },
    text: () => ({ config: { runtime_profile: APP_CANDIDATE_PROFILE }, context_manifest: {
      task_id: taskId, execution_epoch: randomUUID(), execution_mode: 'isolated_text_only' } }) };
}
async function productStarted(t, create, settings = {}, audited = false) {
  const f = fixture({ expectedInput: productInput }), { options } = files(t), ordinary = ordinaryFixture(settings);
  const audit = audited ? auditedFixture(f, { closureSha256: options.closureSha256 }) : null;
  const host = create(options, audit ? { factories: audit.factories, witness: audit.witness } : { factories: f.factories }, ordinary.binding);
  t.after(() => host.shutdown().catch(() => {})); await host.start();
  return { host, f, options, ordinary, audit, request: client(t, host) };
}
async function until(predicate) {
  const deadline = Date.now() + 2000;
  while (!predicate()) { assert(Date.now() < deadline, 'bounded synthetic condition timed out'); await pause(); }
}

for (const [label, create] of [['first', createAppCandidateHost], ['successor', createAppSuccessorHost]]) {
  test(`product ${label}: real IncomingMessage routes require valid capability and preserve ordinary tool round trip`, async t => {
    const { host, f, ordinary, request } = await productStarted(t, create);
    for (const headers of [{ 'x-p6-candidate-token': '0'.repeat(64) },
      { 'x-p6-candidate-launch': randomUUID() }, { origin: 'http://untrusted.invalid' },
      { 'content-type': 'text/plain' }]) {
      assert.equal((await request('POST', `${productRuntime}/sessions`, {}, headers)).status, 403);
      assert.equal(ordinary.calls.length, 0);
    }
    assert.equal((await request('POST', `${productRuntime}/sessions`, { config: {
      dynamic_tools: [{ ...productTool, name: 'exec' }] } })).status, 400);
    assert.equal(ordinary.calls.length, 0);
    const created = await request('POST', `${productRuntime}/sessions`, {});
    assert.equal(created.status, 200); assert.equal(created.body.session_id, ordinarySession);
    assert.equal(ordinary.calls[0].path, `${prefix}/sessions`);
    assert.deepEqual(ordinary.calls[0].body.config.dynamic_tools, [productTool]);
    assert.equal((await request('POST', `${productRuntime}/sessions/${ordinarySession}/turns`, { input: 'Public queue status request.' })).status, 200);
    const polled = await request('GET', `${productRuntime}/sessions/${ordinarySession}/events?after=0`);
    assert.equal(polled.status, 200); assert.equal(polled.body.events[0].data.tool_name, productTool.name);
    const reply = { success: true, content_items: [{ type: 'text', text: 'Public candidate queue status.' }] };
    assert.equal((await request('POST', `${productRuntime}/tool-calls/ordinary-call`, reply)).status, 200);
    assert.equal((await request('POST', `${productRuntime}/tool-calls/ordinary-call`, reply)).status, 400);
    const closedConversation = await request('POST', productClose, {});
    assert.equal(closedConversation.status, 200);
    assert.deepEqual(closedConversation.body, { status: 'closed', conversation_id: 'product-conversation',
      session_id: ordinarySession, turn_ids: ordinary.turnIds, reason: null, shared_gateway_stopped: false });
    assert.equal(ordinary.calls.filter(r => r.method === 'DELETE').length, 1);
    assert.equal(ordinary.calls.at(-1).path, `${prefix}/sessions/${ordinarySession}`);
    assert.equal(f.records.length, 1); assert.equal(f.records[0].armCalls, 0);
    assert.equal((await host.shutdown()).status, 'closed');
    assert.equal(host.snapshot().product.guardian.closed, true);
    assert.equal(host.snapshot().product.guardian.shared_gateway_stopped, false);
  });

  test(`product ${label}: task scope plus exact dynamic goal reaches text arm, wrong input creates no owner or arm`, async t => {
    const { host, f, ordinary, request } = await productStarted(t, create);
    assert.equal((await request('POST', productTask, { ...ordinary.bind, scope_hash: 'b'.repeat(64) })).status, 400);
    assert.equal(f.records.length, 1); assert.equal(host.snapshot().product.task_id, null);
    const bound = await request('POST', productTask, ordinary.bind); assert.equal(bound.status, 200);
    assert.equal(bound.body.goal_sha256, sha(productGoal));
    assert.equal((await request('POST', productTask, { ...ordinary.bind, task_id: randomUUID() })).status, 400);
    const session = await request('POST', `${prefix}/sessions`, ordinary.text()); assert.equal(session.status, 200);
    const id = session.body.session_id;
    for (const input of [APP_CANDIDATE_INPUT, productGoal, `${productInput}tampered`]) {
      assert.notEqual((await request('POST', `${prefix}/sessions/${id}/turns`, { input })).status, 200);
      assert.equal(f.records[1].armCalls, 0); assert.equal(f.records.length, 2);
    }
    assert.equal((await request('POST', `${prefix}/sessions/${id}/turns`, { input: productInput })).status, 200);
    assert.equal(f.records[1].armInput, productInput); assert.equal(f.records[1].armCalls, 1);
    assert.equal((await request('DELETE', `${prefix}/sessions/${id}`)).status, 200);
    assert.equal((await host.shutdown()).status, 'closed');
    const snapshot = host.snapshot(); assert.equal(snapshot.product.task_id, ordinary.taskId);
    assert.equal(snapshot.product.goal_sha256, sha(productGoal));
    assert.equal(snapshot.product.guardian.session_start_attempted, false);
    assert.doesNotMatch(JSON.stringify(snapshot), /Write the public word READY/);
    assert.equal(ordinary.calls.length, 0);
  });

  test(`product ${label}: ordinary unknown refuses overall success while native cleanup still completes`, async t => {
    const { host, f, ordinary, audit, request } = await productStarted(t, create, { closeUnknown: true }, label === 'first');
    assert.equal((await request('POST', productTask, ordinary.bind)).status, 200);
    assert.equal((await request('POST', `${prefix}/sessions`, ordinary.text())).status, 200);
    assert.equal((await request('POST', `${productRuntime}/sessions`, {})).status, 200);
    assert.equal((await request('POST', `${productRuntime}/sessions/${ordinarySession}/turns`, { input: 'Public short chat.' })).status, 200);
    await assert.rejects(host.shutdown(), error => error.code === 'runtime_stop_unconfirmed');
    assert(f.records[1].closeCalls > 0); assert.equal(f.records[1].owner.cleanupPending, false);
    assert.equal(f.records[1].drained, true);
    assert.equal(ordinary.calls.filter(r => r.method === 'DELETE').length, 1);
    assert.equal(host.snapshot().product.guardian.closed, false);
    assert.equal(host.snapshot().product.guardian.unknown_reason, 'conversation_close_receipt_rejected');
    if (audit) {
      assert.equal(audit.commands.filter(c => c.type === 'owner_closed').length, 2);
      assert(!audit.commands.some(c => c.type === 'host_closed'));
    }
  });

  test(`product ${label}: HTTP start still pending during shutdown is registered late and exact-closed`, async t => {
    let release; const startGate = new Promise(resolve => { release = resolve; });
    const { host, f, ordinary, request } = await productStarted(t, create, { startGate });
    const pending = request('POST', `${productRuntime}/sessions`, {});
    await until(() => ordinary.calls.length === 1);
    const shutting = host.shutdown();
    await until(() => host.state.stopping);
    assert.equal(ordinary.calls.filter(r => r.method === 'DELETE').length, 0);
    release(); const result = await pending;
    assert.equal(result.status, 503); assert.equal((await shutting).status, 'closed');
    assert.equal(ordinary.calls.filter(r => r.method === 'DELETE').length, 1);
    assert.equal(host.snapshot().product.guardian.closed, true);
    assert.equal(f.records[0].owner.cleanupPending, false);
  });

  test(`product ${label}: structural lookalike binding is rejected before allocation`, t => {
    const f = fixture(), { options } = files(t);
    assert.throws(() => create(options, { factories: f.factories }, {
      permitsTextSession: () => true, permitsTextInput: () => true,
      handle: async () => ({ handled: true, status: 200, body: {} }),
      closeForHostLifecycle: async () => ({ status: 'closed' }), snapshot: () => ({}),
    }));
    assert.equal(f.records.length, 0);
  });
}

test('product first: original App EOF awaits ordinary exact close and text witness owner closure before host_closed', async t => {
  let release; const closeGate = new Promise(resolve => { release = resolve; });
  const { host, f, ordinary, audit, request } = await productStarted(t, createAppCandidateHost, { closeGate }, true);
  assert.equal((await request('POST', productTask, ordinary.bind)).status, 200);
  assert.equal((await request('POST', `${prefix}/sessions`, ordinary.text())).status, 200);
  assert.equal((await request('POST', `${productRuntime}/sessions`, {})).status, 200);
  const closing = host.appStdinEof();
  await until(() => ordinary.calls.some(r => r.method === 'DELETE') && f.records[1].owner.cleanupPending === false);
  assert.equal(audit.commands.filter(c => c.type === 'app_stdin_eof').length, 1);
  assert(!audit.commands.some(c => c.type === 'host_closed'));
  release(); const result = await closing;
  assert.equal(result.status, 'closed'); assert.equal(audit.commands.at(-1).type, 'host_closed');
  assert.equal(result.witness_close.host_closed_sha256, sha(JSON.stringify(host.snapshot())));
  assert.equal(host.snapshot().product.guardian.closed, true);
  assert.equal(ordinary.calls.at(-1).path, `${prefix}/sessions/${ordinarySession}`);
});

test('product first regression: denied manifest without native intent must not poison audited shutdown', async t => {
  const { host, f, ordinary, audit, request } = await productStarted(t, createAppCandidateHost, {}, true);
  assert.equal((await request('POST', productTask, ordinary.bind)).status, 200);
  const wrong = ordinary.text(); wrong.context_manifest.task_id = randomUUID();
  assert.notEqual((await request('POST', `${prefix}/sessions`, wrong)).status, 200);
  assert.equal(f.records.length, 1); assert.equal(audit.witness.ownerCount, 1);
  // No resource was ever requested for this rejected manifest. The original
  // preflight owner still has its complete receipt; no synthetic receipt is added.
  const result = await host.shutdown();
  assert.equal(result.status, 'closed');
  assert.equal(audit.commands.filter(c => c.type === 'owner_closed').length, 1);
  assert.equal(audit.commands.filter(c => c.type === 'host_closed').length, 1);
});

test('product first regression: denied manifest must not consume the next witnessed owner index', async t => {
  const { host, f, ordinary, audit, request } = await productStarted(t, createAppCandidateHost, {}, true);
  assert.equal((await request('POST', productTask, ordinary.bind)).status, 200);
  const wrong = ordinary.text(); wrong.context_manifest.execution_mode = 'wrong';
  assert.notEqual((await request('POST', `${prefix}/sessions`, wrong)).status, 200);
  const valid = await request('POST', `${prefix}/sessions`, ordinary.text());
  assert.equal(valid.status, 200);
  const bindings = audit.commands.filter(c => c.type === 'owner_bound');
  assert.deepEqual(bindings.map(c => c.owner_index), [0, 1]);
  assert.equal(f.records.length, 2);
  assert.equal((await request('DELETE', `${prefix}/sessions/${valid.body.session_id}`)).status, 200);
  assert.equal((await host.shutdown()).status, 'closed');
});

test('product first regression: denied text config with valid manifest must not leave an unwitnessed record', async t => {
  const { host, f, ordinary, audit, request } = await productStarted(t, createAppCandidateHost, {}, true);
  assert.equal((await request('POST', productTask, ordinary.bind)).status, 200);
  const wrong = ordinary.text(); wrong.config.tools = [];
  assert.notEqual((await request('POST', `${prefix}/sessions`, wrong)).status, 200);
  assert.equal(f.records.length, 1); assert.equal(audit.witness.ownerCount, 1);
  const result = await host.shutdown();
  assert.equal(result.status, 'closed');
  assert.equal(audit.commands.filter(c => c.type === 'owner_closed').length, 1);
});
