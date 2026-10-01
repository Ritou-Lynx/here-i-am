// Candidate-only transport for the Medium native owner. No production
// availability or isolation receipt is issued by this module.
import { spawn } from 'node:child_process';
import { EventEmitter } from 'node:events';
import { createHash } from 'node:crypto';
import { lstatSync, readFileSync, realpathSync } from 'node:fs';
import path from 'node:path';
import { TEXT_TASK_CLI_SHA256 } from './workbench_text_task_runtime_pin.mjs';

const MAX_FRAME = 2 * 1024 * 1024;
const MAX_COMMAND = 0x7fffffff;
const MAX_PENDING = 128;
const FAILURE_STAGES = new Set(('preflight files_source_parent files_owner_pin files_root files_attempt '
  + 'files_cli_source files_cli_copy files_work_create files_cli_pin files_work_pin files_dedicated_pin '
  + 'files_dedicated_binding files_cwd_check files_home_check files_ready job_create job_limits job_limits_readback job_empty_readback '
  + 'job_ready journal_prepared boundary_blob install_helper stdio_create child_create child_preflight '
  + 'child_attributes child_job_attribute child_stdio_attribute child_spawn child_creation_time child_binding '
  + 'child_stdio_parent_close child_journal child_resume started_emit runtime unknown '
  + 'helper_preflight helper_shell_execute helper_process_binding helper_ready_wait helper_ready_live '
  + 'helper_image helper_token helper_lease helper_ack helper_exit_wait helper_exit_binding helper_exit_query '
  + 'helper_exit_status helper_receipt_read helper_receipt_validate helper_handle_close').split(' '));
// Diagnostic transport failures are deliberately a closed local vocabulary.
// They describe this Node transport only; they never carry native error text.
const TRANSPORT_FAILURE_CODES = new Set([
  'native_startup_timeout', 'native_frame_utf8', 'native_frame_truncated',
  'native_stdout_error', 'native_unexpected_stderr', 'native_stderr_error',
  'native_stdin_error', 'native_owner_error', 'native_frame_size',
  'native_frame_invalid', 'native_frame_binding', 'native_startup_invalid',
  'native_close_invalid', 'native_error_invalid', 'native_owner_rejected',
  'native_not_started', 'native_rpc_invalid', 'native_command_binding',
  'native_write_invalid', 'native_peer_invalid', 'native_dispatch_callback_failed',
  'native_pending_limit', 'native_control_write_failed', 'native_close_unconfirmed',
  'native_owner_operation_failed', 'native_command_limit', 'native_close_write_failed',
]);
export function sanitizeNativeTransportFailureCode(code) {
  return typeof code === 'string' && TRANSPORT_FAILURE_CODES.has(code) ? code : null;
}
function safeOwnerPid(pid) {
  return Number.isInteger(pid) && pid >= 1 && pid <= 0xffffffff ? pid : null;
}
export function sanitizeNativeFailureCode(code) {
  if (typeof code !== 'string') return null;
  for (const stage of FAILURE_STAGES) {
    const prefix = `task_${stage}_`;
    if (!code.startsWith(prefix)) continue;
    const family = code.slice(prefix.length);
    if (['failed', 'canonical_rejected', 'path_type_rejected', 'rejected', 'access_denied', 'io_failed', 'security_denied'].includes(family)) return code;
    const win32 = /^win32_(0|[1-9][0-9]{0,9})$/.exec(family);
    if (win32 && Number(win32[1]) <= 0xffffffff) return code;
  }
  return null;
}
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const RECEIPT_KEYS = ['process_close_observed', 'job_empty_verified', 'stdio_eof_verified',
  'rules_absent_verified', 'handles_closed_verified', 'helper_exits_verified', 'cleanup_pending'];
const fail = code => Object.assign(new Error(code), { code });
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
function keys(value, expected) {
  return object(value) && Object.keys(value).length === expected.length
    && expected.every(key => Object.hasOwn(value, key));
}
function timeout(value) {
  if (!Number.isSafeInteger(value) || value < 1 || value > 300000) throw fail('native_timeout_invalid');
  return value;
}
function depth(value, level = 0) {
  if (level > 32) throw fail('native_frame_depth');
  if (value && typeof value === 'object') for (const child of Object.values(value)) depth(child, level + 1);
}
function closedReceipt(value) {
  return keys(value, RECEIPT_KEYS) && RECEIPT_KEYS.every(key => typeof value[key] === 'boolean');
}
const successfulClose = value => closedReceipt(value) && !value.cleanup_pending
  && RECEIPT_KEYS.slice(0, -1).every(key => value[key]);

// Path and pin checks are performed before spawn and again after actual owner
// close. The native owner independently validates its own image and child.
export function assertTextTaskSupervisor(executable, sha256) {
  if (typeof executable !== 'string' || !path.isAbsolute(executable)
    || !/^[a-f0-9]{64}$/.test(sha256)) throw fail('native_pin_invalid');
  for (let current = executable; current !== path.dirname(current); current = path.dirname(current)) {
    if (lstatSync(current).isSymbolicLink() || path.relative(current, realpathSync(current)) !== '') {
      throw fail('native_path_redirected');
    }
  }
  if (!lstatSync(executable).isFile()
    || createHash('sha256').update(readFileSync(executable)).digest('hex') !== sha256) {
    throw fail('native_pin_mismatch');
  }
  return realpathSync(executable);
}

// Exported for deterministic IPC tests. A caller-supplied EventEmitter is never
// production provenance; the adapter remains unavailable until actual gates.
export class WorkbenchTextNativeTransport extends EventEmitter {
  #owner; #attempt; #port; #postPin; #requestTimeout; #closeTimeout; #authMode;
  #decoder = new TextDecoder('utf-8', { fatal: true }); #buffer = '';
  #nextOutput = 1; #nextCommand = 1; #pending = new Map();
  #started = null; #ready; #readyResolve; #readyReject; #readyTimer;
  #fault = null; #ownerPid = null; #ownerClosed = false; #ownerExit = null; #nativeFailure = null;
  #closing = false; #closeCommand = null; #closeReceipt = null; #closed = null;
  #closeWaiters = new Set(); #closePromise = null;

  constructor({ owner, attemptId, brokerPort, postPin, authMode = 'no_auth',
    requestTimeoutMs = 10000, startupTimeoutMs = 120000, closeTimeoutMs = 120000 }) {
    super();
    if (!UUID.test(attemptId) || !Number.isInteger(brokerPort) || brokerPort < 1 || brokerPort > 65535
      || typeof owner?.on !== 'function' || typeof owner?.stdin?.write !== 'function'
      || typeof owner?.stdout?.on !== 'function' || typeof owner?.stderr?.on !== 'function'
      || typeof postPin !== 'function' || !['no_auth', 'chatgpt'].includes(authMode)) throw fail('native_transport_binding_invalid');
    this.#owner = owner; this.#attempt = attemptId; this.#port = brokerPort; this.#postPin = postPin;
    // This is only the PID Node retained for its spawned transport owner. It
    // is not an independently verified creation, parentage, image, startup,
    // or cleanup receipt.
    this.#ownerPid = safeOwnerPid(owner.pid);
    this.#authMode = authMode;
    this.#requestTimeout = timeout(requestTimeoutMs); this.#closeTimeout = timeout(closeTimeoutMs);
    this.#ready = new Promise((resolve, reject) => { this.#readyResolve = resolve; this.#readyReject = reject; });
    // Ownership survives a consumer which stops awaiting initialization.
    this.#ready.catch(() => {});
    this.#readyTimer = setTimeout(() => this.#poison('native_startup_timeout'), timeout(startupTimeoutMs));
    owner.stdout.on('data', data => this.#read(data));
    owner.stdout.on('end', () => {
      try { this.#buffer += this.#decoder.decode(); } catch { this.#poison('native_frame_utf8'); }
      if (this.#buffer.length) this.#poison('native_frame_truncated');
    });
    owner.stdout.on('error', () => this.#poison('native_stdout_error'));
    // Never retain or emit diagnostics which could contain account/task data.
    owner.stderr.on('data', () => this.#poison('native_unexpected_stderr'));
    owner.stderr.on('error', () => this.#poison('native_stderr_error'));
    owner.stdin.on('error', () => this.#poison('native_stdin_error'));
    owner.on('error', () => this.#poison('native_owner_error'));
    owner.on('close', code => {
      this.#ownerClosed = true; this.#ownerExit = code;
      clearTimeout(this.#readyTimer);
      if (!this.#started) this.#readyReject(fail('native_startup_unconfirmed'));
      this.#completeClose();
      for (const pending of this.#pending.values()) {
        clearTimeout(pending.timer); pending.reject(fail('native_dispatch_unconfirmed'));
      }
      this.#pending.clear();
    });
  }

  get ready() { return this.#ready; }
  get startup() { return this.#started; }
  get cleanupPending() { return this.#closed === null; }
  get diagnostics() {
    return Object.freeze({ native_owner_pid: this.#ownerPid,
      transport_failure_code: sanitizeNativeTransportFailureCode(this.#fault),
      native_failure_code: this.#nativeFailure,
      native_owner_exit_code: this.#ownerClosed && Number.isInteger(this.#ownerExit)
        && this.#ownerExit >= -0x80000000 && this.#ownerExit <= 0xffffffff ? this.#ownerExit : null,
      native_close_receipt: this.#closeReceipt });
  }

  #poison(code) {
    if (this.#fault) return;
    this.#fault = code; clearTimeout(this.#readyTimer); this.#readyReject(fail(code));
    // 'error' is not 'close'. No transport failure proves CLI/Job/rule cleanup.
    if (this.listenerCount('error')) this.emit('error', fail(code));
    for (const pending of this.#pending.values()) {
      clearTimeout(pending.timer); pending.reject(fail(code));
    }
    // Keep correlations: a timed-out write can still be acknowledged later.
    // Closing the control input asks the native owner to perform owned cleanup.
    this.#closing = true;
    try { this.#owner.stdin.end(); } catch { /* Keep cleanup ownership. */ }
  }

  #read(chunk) {
    try {
      this.#buffer += this.#decoder.decode(chunk, { stream: true });
      let newline;
      while ((newline = this.#buffer.indexOf('\n')) >= 0) {
        const line = this.#buffer.slice(0, newline); this.#buffer = this.#buffer.slice(newline + 1);
        if (!line || Buffer.byteLength(line) > MAX_FRAME || line.endsWith('\r')) throw fail('native_frame_size');
        const frame = JSON.parse(line); depth(frame); this.#frame(frame);
      }
      if (Buffer.byteLength(this.#buffer) > MAX_FRAME) throw fail('native_frame_size');
    } catch (error) { this.#poison(/^native_[a-z_]+$/.test(error.code) ? error.code : 'native_frame_invalid'); }
  }

  #frame(frame) {
    if (!object(frame) || frame.attempt_id !== this.#attempt || frame.seq !== this.#nextOutput
      || !Number.isSafeInteger(frame.seq) || this.#closeReceipt) throw fail('native_frame_binding');
    this.#nextOutput++;
    const base = ['attempt_id', 'seq', 'type'];
    if (frame.type === 'started') {
      if (this.#started || this.#nextOutput !== 2 || !keys(frame, [...base, 'cwd', 'cli_sha256', 'pid',
        'creation_time', 'provider', 'auth_mode', 'network_boundary_verified', 'child_identity_verified', 'job_singleton'])
        || typeof frame.cwd !== 'string' || !path.win32.isAbsolute(frame.cwd) || frame.cwd.length > 512
        || frame.cli_sha256 !== TEXT_TASK_CLI_SHA256 || !Number.isInteger(frame.pid) || frame.pid < 1
        || frame.pid > 0xffffffff || !/^[1-9][0-9]{0,19}$/.test(frame.creation_time)
        || BigInt(frame.creation_time) > 0xffffffffffffffffn || frame.provider !== 'p6_native_startup'
        || frame.auth_mode !== this.#authMode
        || frame.network_boundary_verified !== true || frame.child_identity_verified !== true
        || frame.job_singleton !== true) throw fail('native_startup_invalid');
      this.#started = Object.freeze({ ...frame }); clearTimeout(this.#readyTimer);
      if (!this.#fault && !this.#closing) this.#readyResolve(this.#started);
      return;
    }
    if (frame.type === 'closed') {
      if (!keys(frame, [...base, 'command_id', 'receipt']) || !closedReceipt(frame.receipt)
        || !(frame.command_id === this.#closeCommand || frame.command_id === 0)) throw fail('native_close_invalid');
      this.#closing = true; this.#closeReceipt = Object.freeze({ ...frame.receipt }); return;
    }
    if (frame.type === 'error') {
      if (!keys(frame, [...base, 'command_id', 'code']) || !Number.isInteger(frame.command_id)
        || frame.command_id < 0 || frame.command_id >= this.#nextCommand
        || !/^[a-z][a-z0-9_]{0,79}$/.test(frame.code)) throw fail('native_error_invalid');
      this.#nativeFailure ??= sanitizeNativeFailureCode(frame.code);
      this.#poison('native_owner_rejected'); return;
    }
    if (!this.#started) throw fail('native_not_started');
    if (frame.type === 'rpc') {
      if (!keys(frame, [...base, 'message']) || !object(frame.message)) throw fail('native_rpc_invalid');
      if (!this.#fault) this.emit('message', frame.message);
      return;
    }
    const pending = this.#pending.get(frame.command_id);
    if (!pending || pending.kind !== (frame.type === 'written' ? 'rpc' : frame.type === 'peer' ? 'verify_peer' : null)) {
      throw fail('native_command_binding');
    }
    if (frame.type === 'written') {
      if (!keys(frame, [...base, 'command_id'])) throw fail('native_write_invalid');
      this.#pending.delete(frame.command_id); clearTimeout(pending.timer);
      // This synchronous callback precedes the next native-sequenced RPC frame.
      try { pending.onDispatched?.(); } catch { this.#poison('native_dispatch_callback_failed'); }
      pending.resolve();
    } else {
      if (!keys(frame, [...base, 'command_id', 'verified', 'pid', 'creation_time', 'cli_sha256', 'job_member'])
        || typeof frame.verified !== 'boolean' || typeof frame.job_member !== 'boolean'
        || (frame.verified && (frame.pid !== this.#started.pid || frame.creation_time !== this.#started.creation_time
          || frame.cli_sha256 !== TEXT_TASK_CLI_SHA256 || frame.job_member !== true))
        || (!frame.verified && (frame.pid !== null || frame.creation_time !== null || frame.cli_sha256 !== null || frame.job_member))) {
        throw fail('native_peer_invalid');
      }
      this.#pending.delete(frame.command_id); clearTimeout(pending.timer); pending.resolve(frame.verified && !this.#fault);
    }
  }

  #command(kind, fields, onDispatched = null) {
    if (this.#ownerClosed || this.#nextCommand > MAX_COMMAND) throw fail('native_owner_unavailable');
    if (this.#pending.size >= MAX_PENDING) {
      this.#poison('native_pending_limit'); throw fail('native_pending_limit');
    }
    const id = this.#nextCommand;
    const frame = { attempt_id: this.#attempt, seq: id, command_id: id, type: kind, ...fields };
    depth(frame); const line = JSON.stringify(frame);
    if (Buffer.byteLength(line) > MAX_FRAME) throw fail('native_frame_size');
    this.#nextCommand++;
    return new Promise((resolve, reject) => {
      const pending = { kind, resolve, reject, onDispatched, timer: null };
      pending.timer = setTimeout(() => reject(fail('native_command_timeout')), this.#requestTimeout);
      this.#pending.set(id, pending);
      try { this.#owner.stdin.write(`${line}\n`); }
      catch { this.#poison('native_control_write_failed'); }
    });
  }

  send(message, { onDispatched = null } = {}) {
    if (!this.#started || this.#fault || this.#closing || !object(message)
      || (onDispatched !== null && typeof onDispatched !== 'function')) throw fail('native_send_unavailable');
    return this.#command('rpc', { message }, onDispatched);
  }

  async verifyPeer(socket) {
    if (!this.#started || this.#fault || this.#closing || socket?.destroyed
      || socket?.localAddress !== '127.0.0.1' || socket?.remoteAddress !== '127.0.0.1'
      || socket.localPort !== this.#port || !Number.isInteger(socket.remotePort)
      || socket.remotePort < 1 || socket.remotePort > 65535) return false;
    try {
      return await this.#command('verify_peer', { tuple: { family: 4, protocol: 'tcp',
        local_address: socket.localAddress, local_port: socket.localPort,
        remote_address: socket.remoteAddress, remote_port: socket.remotePort } }) === true
        && !socket.destroyed && !this.#closing && !this.#fault;
    } catch { return false; }
  }

  #completeClose() {
    let pinned = false;
    try { pinned = this.#postPin() === true; } catch { /* No closure attestation. */ }
    // Native exit 3 is an operation failure, not necessarily a cleanup failure.
    // Preserve the error while accepting independently complete close evidence.
    if ([0, 3].includes(this.#ownerExit) && successfulClose(this.#closeReceipt) && pinned) {
      if (this.#ownerExit === 3) this.#poison('native_owner_operation_failed');
      this.#closed = Object.freeze({ ...this.#closeReceipt });
      this.emit('close', this.#closed);
    } else {
      this.#poison('native_close_unconfirmed');
    }
    for (const waiter of this.#closeWaiters) {
      clearTimeout(waiter.timer);
      if (this.#closed) waiter.resolve(this.#closed); else waiter.reject(fail('native_close_unconfirmed'));
    }
    this.#closeWaiters.clear();
  }

  close() {
    if (this.#closed) return Promise.resolve(this.#closed);
    if (this.#ownerClosed) return Promise.reject(fail('native_close_unconfirmed'));
    if (this.#closePromise) return this.#closePromise;
    this.#closing = true;
    const attempt = new Promise((resolve, reject) => {
      const waiter = { resolve, reject, timer: null };
      waiter.timer = setTimeout(() => {
        this.#closeWaiters.delete(waiter); reject(fail('native_close_timeout'));
      }, this.#closeTimeout);
      this.#closeWaiters.add(waiter);
    });
    this.#closePromise = attempt;
    if (this.#closeCommand === null && !this.#fault) {
      if (this.#nextCommand > MAX_COMMAND) this.#poison('native_command_limit');
    }
    if (this.#closeCommand === null && !this.#fault) {
      this.#closeCommand = this.#nextCommand++;
      try { this.#owner.stdin.write(`${JSON.stringify({ attempt_id: this.#attempt,
        seq: this.#closeCommand, command_id: this.#closeCommand, type: 'close' })}\n`); }
      catch { this.#poison('native_close_write_failed'); }
    } else if (this.#fault) {
      try { this.#owner.stdin.end(); } catch { /* Remains owned. */ }
    }
    void attempt.finally(() => { if (this.#closePromise === attempt) this.#closePromise = null; }).catch(() => {});
    return attempt;
  }
}

export function launchWorkbenchTextNativeExecutor({ executable, sha256, attemptId, brokerPort,
  requestTimeoutMs, startupTimeoutMs, closeTimeoutMs, authMode = 'no_auth' }) {
  if (process.platform !== 'win32') throw fail('native_windows_required');
  // Validate all input before acquiring a live process ownership obligation.
  if (!UUID.test(attemptId) || !Number.isInteger(brokerPort) || brokerPort < 1 || brokerPort > 65535
    || !['no_auth', 'chatgpt'].includes(authMode)) {
    throw fail('native_launch_invalid');
  }
  for (const value of [requestTimeoutMs, startupTimeoutMs, closeTimeoutMs]) if (value !== undefined) timeout(value);
  const command = assertTextTaskSupervisor(executable, sha256);
  const env = Object.fromEntries(['SystemRoot', 'SYSTEMROOT', 'WINDIR', 'COMSPEC', 'PATHEXT',
    'PATH', 'USERPROFILE', 'LOCALAPPDATA', 'TEMP', 'TMP'].filter(key => process.env[key]).map(key => [key, process.env[key]]));
  // Node 24.14.1 / libuv 1.51.0 assigns non-detached children to a
  // KILL_ON_JOB_CLOSE Job. Keep this owner alive on host death so three-pipe
  // EOF can drive its verified cleanup; keep it referenced until actual close.
  // https://github.com/nodejs/node/blob/v24.14.1/deps/uv/src/win/process.c
  const owner = spawn(command, [authMode === 'chatgpt' ? '--apply-authenticated-task-executor' : '--apply-task-executor', attemptId, String(brokerPort)], {
    env, cwd: path.dirname(command), windowsHide: true, detached: true, stdio: ['pipe', 'pipe', 'pipe'],
  });
  return new WorkbenchTextNativeTransport({ owner, attemptId, brokerPort,
    postPin: () => assertTextTaskSupervisor(command, sha256) === command,
    requestTimeoutMs, startupTimeoutMs, closeTimeoutMs, authMode });
}
