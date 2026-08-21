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
  constructor({
    commandSpec = null,
    cwd = process.cwd(),
    env = process.env,
    requestTimeoutMs = DEFAULT_REQUEST_TIMEOUT_MS,
    stopTimeoutMs = DEFAULT_STOP_TIMEOUT_MS,
    experimentalApi = false,
    clientInfo = {
      name: 'here_i_am_bridge',
      title: 'Here I am Dev Agent Bridge',
      version: '0.1.0',
    },
    spawnImpl = nodeSpawn,
  } = {}) {
    super();
    this.commandSpec = commandSpec;
    this.cwd = cwd;
    this.env = env;
    this.requestTimeoutMs = requestTimeoutMs;
    this.stopTimeoutMs = stopTimeoutMs;
    this.experimentalApi = experimentalApi;
    this.clientInfo = clientInfo;
    this.spawnImpl = spawnImpl;

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
  }

  get isReady() {
    return this.state === 'ready' && this.child != null;
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
    const spec = this.commandSpec || resolveCodexAppServerCommand({ env: this.env });
    this.emit('lifecycle', { state: this.state, commandSource: spec.source || 'custom' });

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
      await this.stop();
      throw error;
    }
  }

  async stop() {
    const child = this.child;
    if (!child) {
      this.state = 'stopped';
      return;
    }
    if (this.state === 'stopping' && this._closePromise) {
      await this._closePromise;
      return;
    }

    this.state = 'stopping';
    this.emit('lifecycle', { state: this.state });

    this._closePromise = new Promise((resolve) => {
      let settled = false;
      const finish = () => {
        if (settled) return;
        settled = true;
        resolve();
      };
      child.once('close', finish);
      const timer = setTimeout(() => {
        if (!settled) child.kill();
        finish();
      }, this.stopTimeoutMs);
      timer.unref?.();
      try {
        child.stdin.end();
      } catch {
        child.kill();
      }
    });

    await this._closePromise;
    this._closePromise = null;
    this._finalizeStopped(new CodexAppServerError('Codex app-server stopped.'));
  }

  request(method, params = {}, {
    timeoutMs = this.requestTimeoutMs,
    allowWhileStarting = false,
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
      this._pending.set(id, { method, resolve, reject, timer });
      try {
        this._write({ method, id, params });
      } catch (error) {
        clearTimeout(timer);
        this._pending.delete(id);
        reject(error);
      }
    });
  }

  notify(method, params = {}) {
    this._assertWritable({ allowWhileStarting: method === 'initialized' });
    this._write({ method, params });
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

  interruptTurn(threadId, turnId) {
    return this.request('turn/interrupt', { threadId, turnId });
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
    if (!this.child || !this.child.stdin || this.child.stdin.destroyed) {
      throw new CodexAppServerError('Codex app-server is not running.');
    }
    if (this.state !== 'ready' && !(allowWhileStarting && this.state === 'starting')) {
      throw new CodexAppServerError(`Codex app-server is not ready (state=${this.state}).`);
    }
  }

  _write(message) {
    this.child.stdin.write(`${JSON.stringify(message)}\n`, 'utf8');
  }

  _attachChild(child) {
    child.stdout.on('data', (chunk) => {
      this._stdoutBuffer = this._consumeLines(
        this._stdoutBuffer,
        chunk,
        (line) => this._handleLine(line),
      );
    });
    child.stderr.on('data', (chunk) => {
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
      this.emit('processError', error);
      this._finalizeStopped(new CodexAppServerError(
        `Codex app-server process error: ${error.message}`,
        { cause: error },
      ));
    });
    child.on('close', (code, signal) => {
      this._flushBuffers();
      if (this.state !== 'stopping') {
        this._finalizeStopped(new CodexAppServerError(
          `Codex app-server exited unexpectedly (code=${code ?? 'unknown'}, signal=${signal ?? 'none'}).`,
        ));
      }
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
    if (message.error) {
      pending.reject(new CodexAppServerError(
        `${pending.method} failed: ${message.error.message || 'unknown error'}`,
        { code: message.error.code, data: message.error.data },
      ));
    } else {
      pending.resolve(message.result);
    }
  }

  _finalizeStopped(error) {
    if (this.state === 'stopped' && this.child == null) return;
    const pending = Array.from(this._pending.values());
    this._pending.clear();
    for (const item of pending) {
      clearTimeout(item.timer);
      item.reject(error);
    }
    this.child = null;
    this.state = 'stopped';
    this.emit('lifecycle', { state: this.state });
    this.emit('stopped', error);
  }
}
