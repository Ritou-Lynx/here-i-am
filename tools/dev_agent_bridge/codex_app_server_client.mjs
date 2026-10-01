import { spawn as nodeSpawn } from 'node:child_process';
import { EventEmitter } from 'node:events';
import { existsSync } from 'node:fs';

const DEFAULT_REQUEST_TIMEOUT_MS = 30_000;
const DEFAULT_STOP_TIMEOUT_MS = 3_000;
const MAX_NOTIFICATION_HISTORY = 500;

export class CodexAppServerError extends Error {
  constructor(message, { code = null, data = null, cause = null } = {}) {
    super(message, cause ? { cause } : undefined);
    this.name = 'CodexAppServerError';
    this.code = code;
    this.data = data;
  }
}

export function resolveCodexAppServerCommand({
  env = process.env,
  platform = process.platform,
  nodeExecutable = process.execPath,
} = {}) {
  if (platform === 'win32' && env.APPDATA) {
    const codexJs = `${env.APPDATA}\\npm\\node_modules\\@openai\\codex\\bin\\codex.js`;
    if (existsSync(codexJs)) {
      return {
        command: nodeExecutable,
        args: [codexJs, 'app-server', '--stdio'],
        source: 'npm-js-entrypoint',
      };
    }
  }
  return {
    command: 'codex',
    args: ['app-server', '--stdio'],
    source: 'path',
  };
}

export class CodexAppServerClient extends EventEmitter {
  constructor(options = {}) {
    const {
    commandSpec = null,
    cwd = process.cwd(),
    env = process.env,
    requestTimeoutMs = DEFAULT_REQUEST_TIMEOUT_MS,
    stopTimeoutMs = DEFAULT_STOP_TIMEOUT_MS,
    killTimeoutMs = stopTimeoutMs,
    experimentalApi = false,
    clientInfo = {
      name: 'here_i_am_bridge',
      title: 'Here I am Dev Agent Bridge',
      version: '0.1.0',
    },
    spawnImpl = nodeSpawn,
    attachedTransport = null,
  } = options;
    super();
    if (attachedTransport != null) {
      if (commandSpec != null || Object.hasOwn(options, 'spawnImpl')) {
        throw new TypeError('attachedTransport cannot be combined with commandSpec or spawnImpl.');
      }
      if (typeof attachedTransport.on !== 'function'
        || typeof attachedTransport.send !== 'function'
        || typeof attachedTransport.close !== 'function') {
        throw new TypeError('attachedTransport must provide EventEmitter on(), send(), and close().');
      }
    }
    this.commandSpec = commandSpec;
    this.cwd = cwd;
    this.env = env;
    this.requestTimeoutMs = requestTimeoutMs;
    this.stopTimeoutMs = stopTimeoutMs;
    this.killTimeoutMs = killTimeoutMs;
    for (const timeout of [stopTimeoutMs, killTimeoutMs]) {
      if (!Number.isFinite(timeout) || timeout <= 0 || timeout > 2_147_483_647) {
        throw new TypeError('Stop timeouts must be finite positive timer durations.');
      }
    }
    this.experimentalApi = experimentalApi;
    this.clientInfo = clientInfo;
    this.spawnImpl = spawnImpl;
    this.attachedTransport = attachedTransport;

    this.state = 'stopped';
    this.child = null;
    this.initializeResult = null;
    this.stderrLines = [];

    this._nextRequestId = 1;
    this._pending = new Map();
    this._stdoutBuffer = '';
    this._stderrBuffer = '';
    this._notificationSequence = 0;
    this._notificationHistory = [];
    this._closePromise = null;
    this.lastStopEvidence = null;
  }

  get isReady() {
    return this.state === 'ready' && (this.child != null || this.attachedTransport != null);
  }

  get notificationSequence() {
    return this._notificationSequence;
  }

  async start() {
    if (this.isReady) return this.initializeResult;
    if (this.state !== 'stopped') {
      throw new CodexAppServerError(`Cannot start app-server while state=${this.state}`);
    }

    this.state = 'starting';
    const transport = this.attachedTransport;
    const spec = transport ? null : (this.commandSpec || resolveCodexAppServerCommand({ env: this.env }));
    this.emit('lifecycle', { state: this.state, commandSource: transport ? 'attached-transport' : (spec.source || 'custom') });

    if (transport) {
      this.lastStopEvidence = null;
      this._notificationHistory = [];
      this._attachTransport(transport);
      try {
        this.initializeResult = await this.request('initialize', {
          clientInfo: this.clientInfo,
          capabilities: { experimentalApi: this.experimentalApi },
        }, { allowWhileStarting: true });
        await this.notify('initialized', {});
        this.state = 'ready';
        this.emit('lifecycle', { state: this.state });
        return this.initializeResult;
      } catch (error) {
        // A failed handshake does not establish process termination.  Keep the
        // attached owner until its close receipt proves otherwise.
        try { await this.stop(); } catch { /* preserve the handshake failure */ }
        throw error;
      }
    }

    let child;
    try {
      child = this.spawnImpl(spec.command, spec.args || [], {
        cwd: this.cwd,
        env: this.env,
        stdio: ['pipe', 'pipe', 'pipe'],
        windowsHide: true,
      });
    } catch (error) {
      this.state = 'stopped';
      throw new CodexAppServerError(`Failed to start Codex app-server: ${error.message}`, {
        cause: error,
      });
    }

    this.child = child;
    this.lastStopEvidence = null;
    this._notificationHistory = [];
    this._attachChild(child);

    try {
      this.initializeResult = await this.request('initialize', {
        clientInfo: this.clientInfo,
        capabilities: {
          experimentalApi: this.experimentalApi,
        },
      }, { allowWhileStarting: true });
      this.notify('initialized', {});
      this.state = 'ready';
      this.emit('lifecycle', { state: this.state });
      return this.initializeResult;
    } catch (error) {
      try { await this.stop(); } catch { /* preserve the initialize failure */ }
      throw error;
    }
  }

  async stop() {
    if (this._closePromise) return this._closePromise;
    const child = this.child;
    const transport = this.attachedTransport;
    if (!child && !transport) {
      return this.lastStopEvidence || { process_close_observed: false, reason: 'no_child' };
    }

    // Publish the shared attempt before emitting lifecycle events or touching
    // stdin: either can synchronously re-enter stop() in an embedding host.
    const attempt = Promise.resolve().then(() => transport
      ? this._stopAttachedTransport(transport)
      : this._stopChild(child));
    this._closePromise = attempt;
    this.state = 'stopping';
    this.emit('lifecycle', { state: this.state });
    try {
      return await attempt;
    } finally {
      if (this._closePromise === attempt) this._closePromise = null;
    }
  }

  async _stopAttachedTransport(transport) {
    if (this.attachedTransport !== transport) return this.lastStopEvidence;
    let receipt;
    try {
      receipt = await transport.close();
    } catch (error) {
      this.state = 'stop_unconfirmed';
      this.lastStopEvidence = { process_close_observed: false, close_error: String(error?.message || error) };
      this.emit('lifecycle', { state: this.state });
      throw new CodexAppServerError('Attached app-server close was not observed.', {
        code: 'stop_close_unconfirmed', data: this.lastStopEvidence, cause: error,
      });
    }
    if (receipt?.process_close_observed === true) {
      this.lastStopEvidence = { ...receipt, process_close_observed: true };
      this._finalizeStopped(new CodexAppServerError('Attached Codex app-server closed.'));
      return this.lastStopEvidence;
    }
    this.state = 'stop_unconfirmed';
    this.lastStopEvidence = { ...(receipt || {}), process_close_observed: false };
    this.emit('lifecycle', { state: this.state });
    throw new CodexAppServerError('Attached app-server close was not observed.', {
      code: 'stop_close_unconfirmed', data: this.lastStopEvidence,
    });
  }

  _stopChild(child) {
    if (this.child !== child) return this.lastStopEvidence;
    return new Promise((resolve, reject) => {
      let settled = false;
      let timer;
      const evidence = {
        process_close_observed: false,
        kill_attempted: false,
        kill_returned: null,
        kill_error: null,
      };
      const cleanup = () => {
        clearTimeout(timer);
        child.off('close', finish);
      };
      const finish = () => {
        if (settled) return;
        settled = true;
        cleanup();
        this.lastStopEvidence = { ...evidence, ...this.lastStopEvidence };
        resolve(this.lastStopEvidence);
      };
      const kill = () => {
        if (settled || evidence.kill_attempted) return;
        clearTimeout(timer);
        evidence.kill_attempted = true;
        // A successful kill() only means a signal was sent, not that close ran.
        timer = setTimeout(() => {
          if (settled) return;
          settled = true;
          cleanup();
          this.state = 'stop_unconfirmed';
          this.lastStopEvidence = { ...evidence };
          this.emit('lifecycle', { state: this.state });
          reject(new CodexAppServerError('App-server close was not observed after stop.', {
            code: 'stop_close_unconfirmed', data: { ...evidence },
          }));
        }, this.killTimeoutMs);
        try {
          evidence.kill_returned = child.kill();
        } catch (error) {
          evidence.kill_error = String(error?.message || error);
        }
      };
      child.once('close', finish);
      timer = setTimeout(kill, this.stopTimeoutMs);
      try {
        child.stdin.end();
      } catch {
        kill();
      }
    });
  }

  request(method, params = {}, {
    timeoutMs = this.requestTimeoutMs,
    allowWhileStarting = false,
    onDispatched = null,
  } = {}) {
    this._assertWritable({ allowWhileStarting });
    const id = this._nextRequestId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this._pending.delete(id);
        reject(new CodexAppServerError(`App-server request timed out: ${method}`, {
          code: 'request_timeout',
        }));
      }, timeoutMs);
      timer.unref?.();
      const pending = { method, resolve, reject, timer, dispatched: false };
      this._pending.set(id, pending);
      const dispatched = () => {
        // Preserve a late native-write ACK even when the request itself has
        // timed out: it records a real side effect for the owner.
        pending.dispatched = true;
        onDispatched?.();
      };
      try {
        const sent = this._write({ method, id, params }, dispatched);
        Promise.resolve(sent).catch((error) => {
          if (this._pending.get(id) !== pending) return;
          clearTimeout(timer);
          this._pending.delete(id);
          reject(error);
        });
      } catch (error) {
        clearTimeout(timer);
        this._pending.delete(id);
        reject(error);
      }
    });
  }

  notify(method, params = {}) {
    this._assertWritable({ allowWhileStarting: method === 'initialized' });
    return this._write({ method, params });
  }

  respond(requestId, result) {
    this._assertWritable();
    this._write({ id: requestId, result });
  }

  respondError(requestId, { code = -32_000, message, data = null }) {
    this._assertWritable();
    this._write({
      id: requestId,
      error: {
        code,
        message: String(message || 'Client rejected request.'),
        ...(data == null ? {} : { data }),
      },
    });
  }

  waitForNotification(method, predicate = () => true, {
    afterSequence = 0,
    timeoutMs = this.requestTimeoutMs,
  } = {}) {
    const existing = this._notificationHistory.find((entry) => (
      entry.sequence > afterSequence &&
      entry.message.method === method &&
      predicate(entry.message)
    ));
    if (existing) return Promise.resolve(existing.message);
    if (!this.child && !this.attachedTransport) {
      return Promise.reject(new CodexAppServerError('Codex app-server is not running.'));
    }

    return new Promise((resolve, reject) => {
      const onNotification = (entry) => {
        if (
          entry.sequence > afterSequence &&
          entry.message.method === method &&
          predicate(entry.message)
        ) {
          cleanup();
          resolve(entry.message);
        }
      };
      const onStopped = () => {
        cleanup();
        reject(new CodexAppServerError(
          `App-server stopped while waiting for notification: ${method}`,
        ));
      };
      const timer = setTimeout(() => {
        cleanup();
        reject(new CodexAppServerError(`Notification timed out: ${method}`, {
          code: 'notification_timeout',
        }));
      }, timeoutMs);
      timer.unref?.();
      const cleanup = () => {
        clearTimeout(timer);
        this.off('notification', onNotification);
        this.off('stopped', onStopped);
      };
      this.on('notification', onNotification);
      this.on('stopped', onStopped);
    });
  }

  readAccount({ refreshToken = false } = {}) {
    return this.request('account/read', { refreshToken });
  }

  listModels(params = {}) {
    return this.request('model/list', params);
  }

  startThread(params = {}) {
    return this.request('thread/start', params);
  }

  resumeThread(threadId, params = {}) {
    return this.request('thread/resume', { ...params, threadId });
  }

  forkThread(threadId, params = {}) {
    return this.request('thread/fork', { ...params, threadId });
  }

  readThread(threadId, { includeTurns = true } = {}) {
    return this.request('thread/read', { threadId, includeTurns });
  }

  listThreads(params = {}) {
    return this.request('thread/list', params);
  }

  setThreadName(threadId, name) {
    return this.request('thread/name/set', { threadId, name });
  }

  archiveThread(threadId) {
    return this.request('thread/archive', { threadId });
  }

  startTurn(threadId, text, params = {}) {
    return this.request('turn/start', {
      ...params,
      threadId,
      input: [{ type: 'text', text }],
    });
  }

  steerTurn(threadId, turnId, text, params = {}) {
    return this.request('turn/steer', {
      ...params,
      threadId,
      expectedTurnId: turnId,
      input: [{ type: 'text', text }],
    });
  }

  interruptTurn(threadId, turnId, { onDispatched = null } = {}) {
    return this.request('turn/interrupt', { threadId, turnId }, { onDispatched });
  }

  async runTurn(threadId, text, params = {}, {
    timeoutMs = 120_000,
  } = {}) {
    const afterSequence = this.notificationSequence;
    const started = await this.startTurn(threadId, text, params);
    const turnId = started?.turn?.id;
    if (!turnId) {
      throw new CodexAppServerError('turn/start response did not include turn.id');
    }
    const completed = await this.waitForNotification(
      'turn/completed',
      (message) => message.params?.threadId === threadId &&
        message.params?.turn?.id === turnId,
      { afterSequence, timeoutMs },
    );
    return { started, completed };
  }

  _assertWritable({ allowWhileStarting = false } = {}) {
    if (!this.attachedTransport && (!this.child || !this.child.stdin || this.child.stdin.destroyed)) {
      throw new CodexAppServerError('Codex app-server is not running.');
    }
    if (this.state !== 'ready' && !(allowWhileStarting && this.state === 'starting')) {
      throw new CodexAppServerError(`Codex app-server is not ready (state=${this.state}).`);
    }
  }

  _write(message, onDispatched = null) {
    if (this.attachedTransport) {
      return this.attachedTransport.send(message, { onDispatched });
    }
    this.child.stdin.write(`${JSON.stringify(message)}\n`, 'utf8');
    onDispatched?.();
  }

  _attachChild(child) {
    child.stdout.on('data', (chunk) => {
      if (this.child !== child) return;
      this._stdoutBuffer = this._consumeLines(
        this._stdoutBuffer,
        chunk,
        (line) => this._handleLine(line),
      );
    });
    child.stderr.on('data', (chunk) => {
      if (this.child !== child) return;
      this._stderrBuffer = this._consumeLines(
        this._stderrBuffer,
        chunk,
        (line) => {
          this.stderrLines.push(line);
          this.emit('stderr', line);
        },
      );
    });
    child.on('error', (error) => {
      if (this.child !== child) return;
      this.emit('processError', error);
      // Node also emits error for failed kill/send; only close releases ownership.
      this._rejectPending(new CodexAppServerError(
        `Codex app-server process error: ${error.message}`,
        { cause: error },
      ));
      if (this.state !== 'stopping') {
        this.state = 'unavailable';
        this.emit('lifecycle', { state: this.state });
      }
    });
    child.on('close', (code, signal) => {
      if (this.child !== child) return;
      this._flushBuffers();
      this.lastStopEvidence = {
        process_close_observed: true, exit_code: code ?? null, signal: signal ?? null,
      };
      this._finalizeStopped(new CodexAppServerError(
        `Codex app-server closed (code=${code ?? 'unknown'}, signal=${signal ?? 'none'}).`,
      ));
    });
  }

  _attachTransport(transport) {
    const transportLost = (error) => {
      if (this.attachedTransport !== transport) return;
      this.emit('processError', error);
      this._rejectPending(new CodexAppServerError(
        `Attached Codex app-server transport error: ${error?.message || error}`,
        { cause: error },
      ));
      // Transport loss is never evidence that the owned native process closed.
      if (this.state !== 'stopping' && this.state !== 'stop_unconfirmed') {
        this.state = 'unavailable';
        this.emit('lifecycle', { state: this.state });
      }
    };
    transport.on('message', (message) => {
      if (this.attachedTransport !== transport) return;
      if (!message || typeof message !== 'object' || Array.isArray(message)) {
        this.emit('protocolError', new CodexAppServerError('Attached transport emitted an invalid RPC message.'));
        return;
      }
      this._handleMessage(message);
    });
    transport.on('error', transportLost);
    transport.on('close', (receipt) => {
      if (this.attachedTransport !== transport) return;
      if (receipt?.process_close_observed !== true) {
        transportLost(new CodexAppServerError('Attached transport closed without process-close proof.'));
        return;
      }
      this.lastStopEvidence = { ...receipt, process_close_observed: true };
      this._finalizeStopped(new CodexAppServerError('Attached Codex app-server closed.'));
    });
  }

  _consumeLines(buffer, chunk, onLine) {
    const lines = `${buffer}${chunk.toString('utf8')}`.split(/\r?\n/);
    const remainder = lines.pop() || '';
    for (const line of lines) {
      if (line.trim()) onLine(line);
    }
    return remainder;
  }

  _flushBuffers() {
    if (this._stdoutBuffer.trim()) this._handleLine(this._stdoutBuffer);
    if (this._stderrBuffer.trim()) {
      this.stderrLines.push(this._stderrBuffer);
      this.emit('stderr', this._stderrBuffer);
    }
    this._stdoutBuffer = '';
    this._stderrBuffer = '';
  }

  _handleLine(line) {
    let message;
    try {
      message = JSON.parse(line);
    } catch (error) {
      this.emit('protocolError', new CodexAppServerError(
        `Invalid JSON from Codex app-server: ${line.slice(0, 200)}`,
        { cause: error },
      ));
      return;
    }

    this._handleMessage(message);
  }

  _handleMessage(message) {
    if (message.method) {
      if (Object.hasOwn(message, 'id')) {
        this.emit('serverRequest', {
          id: message.id,
          method: message.method,
          params: message.params || {},
          respond: (result) => this.respond(message.id, result),
          respondError: (error) => this.respondError(message.id, error),
        });
      } else {
        const entry = {
          sequence: ++this._notificationSequence,
          message,
        };
        this._notificationHistory.push(entry);
        if (this._notificationHistory.length > MAX_NOTIFICATION_HISTORY) {
          this._notificationHistory.shift();
        }
        this.emit('notification', entry);
      }
      return;
    }

    if (!Object.hasOwn(message, 'id')) {
      this.emit('protocolError', new CodexAppServerError(
        'App-server response is missing id and method.',
      ));
      return;
    }

    const pending = this._pending.get(message.id);
    if (!pending) {
      this.emit('orphanResponse', message);
      return;
    }
    this._pending.delete(message.id);
    clearTimeout(pending.timer);
    if (this.attachedTransport && !pending.dispatched) {
      const error = new CodexAppServerError(
        `${pending.method} response arrived before native dispatch acknowledgement.`,
        { code: 'response_before_dispatch' },
      );
      pending.reject(error);
      this.emit('protocolError', error);
      if (this.state !== 'stopping' && this.state !== 'stop_unconfirmed') {
        this.state = 'unavailable';
        this.emit('lifecycle', { state: this.state });
      }
      return;
    }
    if (message.error) {
      pending.reject(new CodexAppServerError(
        `${pending.method} failed: ${message.error.message || 'unknown error'}`,
        { code: message.error.code, data: message.error.data },
      ));
    } else {
      pending.resolve(message.result);
    }
  }

  _rejectPending(error) {
    const pending = Array.from(this._pending.values());
    this._pending.clear();
    for (const item of pending) {
      clearTimeout(item.timer);
      item.reject(error);
    }
  }

  _finalizeStopped(error) {
    if (this.state === 'stopped' && this.child == null && this.attachedTransport == null) return;
    this._rejectPending(error);
    this.child = null;
    this.attachedTransport = null;
    this.state = 'stopped';
    this.emit('lifecycle', { state: this.state });
    this.emit('stopped', error);
  }
}
