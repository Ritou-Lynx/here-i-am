import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { PassThrough, Writable } from 'node:stream';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { runInNewContext } from 'node:vm';
import { WorkbenchTextNativeTransport, sanitizeNativeFailureCode,
  sanitizeNativeTransportFailureCode } from './workbench_text_task_native_executor.mjs';
import { TEXT_TASK_CLI_SHA256 } from './workbench_text_task_runtime_pin.mjs';

const ATTEMPT = '63591d00-d5b5-4aa7-a508-0963dbe6c1b8';

test('fixed launcher detaches only the owner while retaining three pipes and process ownership', () => {
  const source = readFileSync(new URL('./workbench_text_task_native_executor.mjs', import.meta.url), 'utf8');
  const launcher = source.slice(source.indexOf('export function launchWorkbenchTextNativeExecutor('));
  assert.equal(launcher.includes('.unref('), false);
  for (const authMode of ['no_auth', 'chatgpt']) {
    const owner = {}; let spawned;
    const env = { SystemRoot: 'C:\\Windows', PATH: 'fixed-path', LOCALAPPDATA: 'fixed-local',
      NODE_OPTIONS: '--require forbidden', HTTP_PROXY: 'forbidden', UNRELATED: 'forbidden' };
    const command = 'D:\\candidate\\owner.exe';
    const launch = runInNewContext(`(${launcher.replace('export ', '')})`, {
      process: { platform: 'win32', env }, UUID: /^[0-9a-f-]{36}$/,
      fail: code => new Error(code), timeout: value => assert.equal(value, 123), path: path.win32,
      assertTextTaskSupervisor: (exe, pin) => { assert.equal(exe, command); assert.equal(pin, 'fixed-pin'); return exe; },
      spawn: (...args) => { spawned = args; return owner; },
      WorkbenchTextNativeTransport: class { constructor(options) { this.options = options; } },
    });
    const transport = launch({ executable: command, sha256: 'fixed-pin', attemptId: ATTEMPT,
      brokerPort: 30001, authMode, requestTimeoutMs: 123, startupTimeoutMs: 123, closeTimeoutMs: 123 });
    assert.deepEqual(JSON.parse(JSON.stringify(spawned)), [command,
      [authMode === 'chatgpt' ? '--apply-authenticated-task-executor' : '--apply-task-executor', ATTEMPT, '30001'],
      { env: { SystemRoot: env.SystemRoot, PATH: env.PATH, LOCALAPPDATA: env.LOCALAPPDATA },
        cwd: 'D:\\candidate', windowsHide: true, detached: true, stdio: ['pipe', 'pipe', 'pipe'] }]);
    assert.strictEqual(transport.options.owner, owner);
    assert.equal(transport.options.postPin(), true);
    assert.equal(transport.options.authMode, authMode);
  }
});
const closeProof = () => ({ process_close_observed: true, job_empty_verified: true,
  stdio_eof_verified: true, rules_absent_verified: true, handles_closed_verified: true,
  helper_exits_verified: true, cleanup_pending: false });
function fixture({ postPin = () => true, requestTimeoutMs = 100, closeTimeoutMs = 100, authMode = 'no_auth', ownerPid = undefined } = {}) {
  const owner = new EventEmitter(); owner.stdout = new PassThrough(); owner.stderr = new PassThrough();
  if (ownerPid !== undefined) owner.pid = ownerPid;
  const commands = [];
  owner.stdin = new Writable({ write(chunk, _encoding, done) { commands.push(JSON.parse(chunk)); done(); } });
  const transport = new WorkbenchTextNativeTransport({ owner, attemptId: ATTEMPT, brokerPort: 30001,
    postPin, requestTimeoutMs, closeTimeoutMs, startupTimeoutMs: 100, authMode });
  const errors = []; transport.on('error', error => errors.push(error.code));
  let sequence = 0;
  const frame = (type, fields = {}) => owner.stdout.write(`${JSON.stringify({ attempt_id: ATTEMPT,
    seq: ++sequence, type, ...fields })}\n`);
  const start = (actualMode = authMode) => frame('started', { cwd: 'D:\\TaskOwner\\empty-workspace', cli_sha256: TEXT_TASK_CLI_SHA256,
    pid: 123, creation_time: '133712345678901234', provider: 'p6_native_startup', auth_mode: actualMode,
    network_boundary_verified: true, child_identity_verified: true, job_singleton: true });
  const finish = (receipt = closeProof(), code = 0) => {
    frame('closed', { command_id: commands.find(c => c.type === 'close')?.command_id ?? 0, receipt });
    owner.stdout.end(); owner.emit('close', code);
  };
  return { owner, commands, transport, errors, frame, start, finish };
}

test('enqueue does not confirm dispatch; native ACK synchronously precedes the next ordered RPC', async () => {
  const f = fixture(); f.start(); await f.transport.ready;
  const order = []; f.transport.on('message', () => order.push('rpc'));
  const pending = f.transport.send({ id: 1, method: 'initialize', params: {} }, { onDispatched: () => order.push('written') });
  assert.deepEqual(order, []);
  assert.equal(f.commands[0].type, 'rpc');
  f.frame('written', { command_id: 1 }); f.frame('rpc', { message: { id: 1, result: {} } });
  await pending; assert.deepEqual(order, ['written', 'rpc']);
  const close = f.transport.close(); f.finish(); assert.equal((await close).process_close_observed, true);
});

test('a request timeout does not discard a late native write acknowledgement', async () => {
  const f = fixture({ requestTimeoutMs: 5 }); f.start(); await f.transport.ready;
  let writes = 0;
  const pending = f.transport.send({ id: 1, method: 'turn/start' }, { onDispatched: () => writes++ });
  await assert.rejects(pending, /native_command_timeout/); assert.equal(writes, 0);
  f.frame('written', { command_id: 1 }); assert.equal(writes, 1);
  const close = f.transport.close(); f.finish(); await close;
});

test('peer admission binds the accepted tuple to the held child and cannot use a wrong identity', async () => {
  const f = fixture(); f.start(); await f.transport.ready;
  const socket = { localAddress: '127.0.0.1', localPort: 30001, remoteAddress: '127.0.0.1', remotePort: 31000, destroyed: false };
  assert.equal(await f.transport.verifyPeer({ ...socket, localPort: 30002 }), false);
  const admitted = f.transport.verifyPeer(socket);
  assert.deepEqual(f.commands[0].tuple, { family: 4, protocol: 'tcp', local_address: '127.0.0.1', local_port: 30001,
    remote_address: '127.0.0.1', remote_port: 31000 });
  f.frame('peer', { command_id: 1, verified: true, pid: 123, creation_time: '133712345678901234', cli_sha256: TEXT_TASK_CLI_SHA256, job_member: true });
  assert.equal(await admitted, true);
  const wrong = f.transport.verifyPeer(socket);
  f.frame('peer', { command_id: 2, verified: true, pid: 124, creation_time: '133712345678901234', cli_sha256: TEXT_TASK_CLI_SHA256, job_member: true });
  assert.equal(await wrong, false); assert.deepEqual(f.errors, ['native_peer_invalid']);
  const close = f.transport.close(); f.finish(); await close;
});

test('closed frame alone is not owner exit; retry after timeout sends one physical close command', async () => {
  const f = fixture({ closeTimeoutMs: 5 }); f.start(); await f.transport.ready;
  const first = f.transport.close(); assert.strictEqual(f.transport.close(), first);
  f.frame('closed', { command_id: 1, receipt: closeProof() });
  await assert.rejects(first, /native_close_timeout/); assert.equal(f.transport.cleanupPending, true);
  const retry = f.transport.close(); assert.equal(f.commands.filter(c => c.type === 'close').length, 1);
  f.owner.stdout.end(); f.owner.emit('close', 0);
  assert.equal((await retry).process_close_observed, true); assert.equal(f.transport.cleanupPending, false);
});

test('every failed cleanup gate, missing native receipt, wrong owner exit or postpin denies close', async () => {
  for (const key of Object.keys(closeProof())) {
    const f = fixture(); f.start(); await f.transport.ready; const close = f.transport.close();
    const receipt = closeProof(); receipt[key] = key === 'cleanup_pending'; f.finish(receipt);
    await assert.rejects(close, /native_close_unconfirmed/); assert.equal(f.transport.cleanupPending, true);
  }
  for (const scenario of ['missing', 'exit', 'pin']) {
    const f = fixture({ postPin: () => scenario !== 'pin' }); f.start(); await f.transport.ready;
    const close = f.transport.close();
    if (scenario === 'missing') { f.owner.stdout.end(); f.owner.emit('close', 0); }
    else f.finish(closeProof(), scenario === 'exit' ? 2 : 0);
    await assert.rejects(close, /native_close_unconfirmed/);
  }
});

test('wrong attempt, duplicate sequence, extra fields and invalid UTF8 poison transport without claiming close', async () => {
  const cases = [
    f => f.frame('rpc', { attempt_id: '73591d00-d5b5-4aa7-a508-0963dbe6c1b8', message: {} }),
    f => f.frame('rpc', { seq: 1, message: {} }),
    f => f.frame('rpc', { message: {}, extra: 'not allowed' }),
    f => f.owner.stdout.write(Buffer.from([0xc0, 0xaf, 10])),
  ];
  for (const invalid of cases) {
    const f = fixture(); f.start(); await f.transport.ready; let closed = false;
    f.transport.on('close', () => { closed = true; }); invalid(f);
    assert.equal(f.errors.length, 1); assert.equal(closed, false);
    const close = f.transport.close(); f.owner.stdout.end(); f.owner.emit('close', 2);
    await assert.rejects(close, /native_close_unconfirmed/);
  }
});

test('unconfirmed startup is owned until the native close proof and actual exit arrive', async () => {
  const f = fixture(); f.frame('error', { command_id: 0, code: 'startup_rejected' });
  await assert.rejects(f.transport.ready, /native_owner_rejected/);
  const close = f.transport.close(); f.finish(); assert.equal((await close).process_close_observed, true);
});

test('the pending correlation cap rejects before write, retains late acknowledgements and starts cleanup', async () => {
  const f = fixture(); f.start(); await f.transport.ready;
  let acknowledgements = 0;
  const pending = [];
  for (let id = 1; id <= 128; id++) {
    pending.push(f.transport.send({ id, method: 'config/read' }, { onDispatched: () => acknowledgements++ }).catch(error => error.code));
  }
  assert.throws(() => f.transport.send({ id: 129, method: 'config/read' }), /native_pending_limit/);
  assert.equal(f.commands.length, 128);
  assert.equal(f.owner.stdin.writableEnded, true);
  f.frame('written', { command_id: 1 }); assert.equal(acknowledgements, 1);
  assert.deepEqual(new Set(await Promise.all(pending)), new Set(['native_pending_limit']));
  const close = f.transport.close(); f.finish(); await close;
});

test('an owner exit without a close receipt immediately reports transport loss', async () => {
  const f = fixture(); f.start(); await f.transport.ready;
  f.owner.stdout.end(); f.owner.emit('close', 0);
  assert.deepEqual(f.errors, ['native_close_unconfirmed']);
  await assert.rejects(f.transport.close(), /native_close_unconfirmed/);
});

test('operation failure and proven cleanup remain distinct: error is emitted before a verified close', async () => {
  const f = fixture(); f.start(); await f.transport.ready;
  const order = [];
  f.transport.on('error', error => order.push(error.code));
  f.transport.on('close', () => order.push('closed'));
  const close = f.transport.close(); f.finish(closeProof(), 3);
  assert.equal((await close).process_close_observed, true);
  assert.deepEqual(order, ['native_owner_operation_failed', 'closed']);
  assert.equal(f.transport.cleanupPending, false);
});

test('authentication mode is bound to startup; neither candidate mode can silently substitute the other', async () => {
  for (const mode of ['no_auth', 'chatgpt']) {
    const valid = fixture({ authMode: mode }); valid.start();
    assert.equal((await valid.transport.ready).auth_mode, mode);
    const goodClose = valid.transport.close(); valid.finish(); await goodClose;
    const wrong = fixture({ authMode: mode }); wrong.start(mode === 'chatgpt' ? 'no_auth' : 'chatgpt');
    await assert.rejects(wrong.transport.ready, /native_startup_invalid/);
    const cleanup = wrong.transport.close(); wrong.finish(); await cleanup;
  }
});

test('startup diagnostics retain finite native stages and exact Win32 codes without converting failed closure to success', async () => {
  for (const code of ['task_files_dedicated_pin_win32_5', 'task_job_limits_win32_87',
    'task_files_dedicated_binding_rejected',
    'task_helper_shell_execute_win32_1223', 'task_helper_ready_wait_rejected',
    'task_files_dedicated_pin_canonical_rejected', 'task_files_dedicated_pin_path_type_rejected',
    'task_files_dedicated_pin_io_failed', 'task_files_dedicated_pin_access_denied', 'task_runtime_security_denied',
    'task_files_home_check_rejected', 'task_runtime_win32_4294967295',
    'task_files_dedicated_pin_win32_4294967296', 'task_unknown_path_rejected', 'private_account_value']) {
    const f = fixture(); f.frame('error', { command_id: 0, code });
    await assert.rejects(f.transport.ready, /native_owner_rejected/);
    const close = f.transport.close();
    const incomplete = { ...closeProof(), process_close_observed: false, stdio_eof_verified: false, cleanup_pending: true };
    f.finish(incomplete, 4); await assert.rejects(close, /native_close_unconfirmed/);
    assert.equal(f.transport.diagnostics.native_failure_code,
      ['task_files_dedicated_pin_win32_4294967296', 'task_unknown_path_rejected', 'private_account_value'].includes(code) ? null : code);
    assert.equal(f.transport.diagnostics.native_owner_exit_code, 4);
    assert.deepEqual(f.transport.diagnostics.native_close_receipt, incomplete);
    assert.equal(Object.isFrozen(f.transport.diagnostics.native_close_receipt), true);
    assert.equal(f.transport.cleanupPending, true);
  }
});

test('transport diagnostics expose only the held uint owner PID before ready and after close', async () => {
  for (const [ownerPid, expected] of [[4321, 4321], [undefined, null], [0, null], [-1, null], [0x100000000, null], ['4321', null]]) {
    const f = fixture({ ownerPid });
    const before = f.transport.diagnostics;
    assert.equal(before.native_owner_pid, expected);
    assert.equal(before.transport_failure_code, null);
    f.start(); await f.transport.ready;
    const close = f.transport.close(); f.finish(); await close;
    assert.equal(f.transport.diagnostics.native_owner_pid, expected);
  }
});

test('transport diagnostics retain a closed local failure code without leaking raw native errors or changing lifecycle state', async () => {
  const f = fixture({ ownerPid: 4321 });
  const before = f.transport.diagnostics;
  assert.equal(before.native_owner_pid, 4321);
  assert.equal(before.transport_failure_code, null);
  assert.equal(f.transport.startup, null);
  assert.equal(f.transport.cleanupPending, true);
  f.frame('error', { command_id: 0, code: 'private_account_value' });
  await assert.rejects(f.transport.ready, /native_owner_rejected/);
  const after = f.transport.diagnostics;
  assert.equal(after.transport_failure_code, 'native_owner_rejected');
  assert.equal(after.native_failure_code, null);
  assert.equal(JSON.stringify(after).includes('private_account_value'), false);
  assert.equal(f.transport.startup, null);
  assert.equal(f.transport.cleanupPending, true);
  const close = f.transport.close(); f.finish(); await close;
  assert.equal(f.transport.diagnostics.transport_failure_code, 'native_owner_rejected');
  assert.equal(f.transport.diagnostics.native_owner_pid, 4321);
});

test('diagnostic reads do not settle a pending write or change ready and close sequencing', async () => {
  const f = fixture({ ownerPid: 4321 }); f.start();
  const ready = f.transport.ready;
  assert.equal((await ready).pid, 123);
  const pending = f.transport.send({ id: 1, method: 'initialize', params: {} });
  const first = f.transport.diagnostics;
  const second = f.transport.diagnostics;
  assert.notStrictEqual(first, second);
  assert.equal(f.commands.length, 1);
  assert.equal(f.commands[0].type, 'rpc');
  f.frame('written', { command_id: 1 }); await pending;
  const close = f.transport.close();
  assert.equal(f.commands.filter(command => command.type === 'close').length, 1);
  void f.transport.diagnostics;
  assert.equal(f.commands.filter(command => command.type === 'close').length, 1);
  f.finish(); await close;
});

test('diagnostic sanitizers share the executor finite vocabularies and reject non-strings', () => {
  assert.equal(sanitizeNativeFailureCode('task_files_dedicated_pin_win32_5'), 'task_files_dedicated_pin_win32_5');
  assert.equal(sanitizeNativeFailureCode('task_unknown_path_rejected'), null);
  assert.equal(sanitizeNativeFailureCode({ code: 'task_runtime_rejected' }), null);
  assert.equal(sanitizeNativeFailureCode(null), null);
  assert.equal(sanitizeNativeTransportFailureCode('native_owner_rejected'), 'native_owner_rejected');
  assert.equal(sanitizeNativeTransportFailureCode('private_account_value'), null);
  assert.equal(sanitizeNativeTransportFailureCode({ code: 'native_owner_rejected' }), null);
  assert.equal(sanitizeNativeTransportFailureCode(null), null);
});
