import { CodexAppServerAdapter } from './codex_app_server_adapter.mjs';
import {
  RuntimeAdapterError,
  RuntimeErrorCode,
  asRuntimeAdapterError,
} from './runtime_adapter.mjs';
import {
  WORKBENCH_TEXT_ONLY_PROFILE,
  requireSupportedRuntimeProfile,
} from './workbench_text_only_profile.mjs';

export const EXPERIMENTAL_RUNTIME_PREFIX = '/experimental/v1/runtime';
export const MAX_EXPERIMENTAL_REQUEST_BYTES = 256 * 1024;

function isLoopback(address) {
  const value = String(address || '').toLowerCase();
  return value === '127.0.0.1' || value === '::1' || value === '::ffff:127.0.0.1';
}

function writeJson(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'x-hereiam-experimental': 'runtime-adapter-v1',
  });
  res.end(body);
}

async function readJson(req, { maxBytes = MAX_EXPERIMENTAL_REQUEST_BYTES } = {}) {
  const chunks = [];
  let receivedBytes = 0;
  for await (const chunk of req) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    receivedBytes += buffer.length;
    if (receivedBytes > maxBytes) {
      throw new RuntimeAdapterError('Experimental runtime request body is too large.', {
        code: RuntimeErrorCode.INVALID_REQUEST,
        operation: 'readJson',
        details: { max_request_bytes: maxBytes },
      });
    }
    chunks.push(buffer);
  }
  if (chunks.length === 0) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch (error) {
    throw new RuntimeAdapterError('Request body must be valid JSON.', {
      code: RuntimeErrorCode.INVALID_REQUEST,
      operation: 'readJson',
      cause: error,
    });
  }
}

function errorStatus(code) {
  switch (code) {
    case RuntimeErrorCode.UNSUPPORTED_CAPABILITY:
      return 501;
    case RuntimeErrorCode.AUTHENTICATION_REQUIRED:
      return 401;
    case RuntimeErrorCode.INVALID_REQUEST:
      return 400;
    case RuntimeErrorCode.SESSION_NOT_FOUND:
    case RuntimeErrorCode.TURN_NOT_FOUND:
    case RuntimeErrorCode.APPROVAL_NOT_FOUND:
    case RuntimeErrorCode.TOOL_CALL_NOT_FOUND:
      return 404;
    case RuntimeErrorCode.TURN_NOT_ACTIVE:
      return 409;
    case RuntimeErrorCode.MODEL_UNAVAILABLE:
      return 422;
    case RuntimeErrorCode.TIMEOUT:
      return 504;
    case RuntimeErrorCode.RUNTIME_UNAVAILABLE:
    case 'runtime_start_unconfirmed':
    case 'runtime_stop_unconfirmed':
      return 503;
    default:
      return 500;
  }
}

function isTextOnlyConfig(config) {
  return config?.runtime_profile === WORKBENCH_TEXT_ONLY_PROFILE;
}

function projectTextOnlyCapability(capabilities, textAdapterFactory) {
  // Capability discovery must remain side-effect free for the isolated text
  // host. A configured factory proves only that a host is wired, never that it
  // has started or that a provider execution can be confirmed.
  if (typeof textAdapterFactory !== 'function') return capabilities;
  const configuredProfile = (profile = {}) => ({
    ...profile,
    profile: WORKBENCH_TEXT_ONLY_PROFILE,
    available: false,
    fail_closed: true,
    configured: true,
    reason: 'text_only_host_configured_not_started',
  });
  const sourceProfiles = Array.isArray(capabilities?.runtime_profiles)
    ? capabilities.runtime_profiles
    : [];
  let foundTextProfile = false;
  const runtimeProfiles = sourceProfiles.map((profile) => {
    if (profile?.profile !== WORKBENCH_TEXT_ONLY_PROFILE) return profile;
    foundTextProfile = true;
    return configuredProfile(profile);
  });
  if (!foundTextProfile) runtimeProfiles.push(configuredProfile());
  return { ...capabilities, runtime_profiles: runtimeProfiles };
}

const trustedProfileErrors = new WeakSet();
function rejectUnavailableTextProfile(operation) {
  try { requireSupportedRuntimeProfile({ runtime_profile: WORKBENCH_TEXT_ONLY_PROFILE }, operation); }
  catch (error) { trustedProfileErrors.add(error); throw error; }
}

// The native candidate deliberately uses a fixed public error surface.  Do not
// pass an arbitrary Error through asRuntimeAdapterError: its message can carry
// paths, transport details, or account information.
function textRequestError(error, operation = 'textRuntime') {
  if (trustedProfileErrors.has(error)) {
    // This is the existing fixed profile availability response, not a native
    // error. Preserve it exactly while keeping every other text failure fixed.
    return error;
  }
  const code = new Set([
    RuntimeErrorCode.INVALID_REQUEST,
    RuntimeErrorCode.UNSUPPORTED_CAPABILITY,
    RuntimeErrorCode.AUTHENTICATION_REQUIRED,
    RuntimeErrorCode.SESSION_NOT_FOUND,
    RuntimeErrorCode.TURN_NOT_FOUND,
    RuntimeErrorCode.TURN_NOT_ACTIVE,
    RuntimeErrorCode.TIMEOUT,
    RuntimeErrorCode.RUNTIME_UNAVAILABLE,
    'runtime_start_unconfirmed',
    'runtime_stop_unconfirmed',
  ]).has(error?.code) ? error.code : RuntimeErrorCode.RUNTIME_UNAVAILABLE;
  return new RuntimeAdapterError('Text task request could not be confirmed.', {
    code,
    operation,
    retryable: code === RuntimeErrorCode.TIMEOUT || code === 'runtime_stop_unconfirmed',
  });
}

function requestAbort(req, res, onAbort) {
  const controller = new AbortController();
  const notifyAbort = () => { onAbort(); };
  const dispose = () => {
    req.off?.('aborted', abort);
    res.off?.('close', onClose);
    res.off?.('finish', dispose);
    controller.signal.removeEventListener('abort', notifyAbort);
  };
  const abort = () => { controller.abort(); dispose(); };
  const onClose = () => {
    // A response may close normally after writeJson().  GET disconnects do not
    // own a native task; only a non-finished mutation response can cancel one.
    if (res.writableFinished !== true) abort();
    dispose();
  };
  controller.signal.addEventListener('abort', notifyAbort, { once: true });
  req.once?.('aborted', abort);
  res.once?.('close', onClose);
  res.once?.('finish', dispose);
  // Installation can occur after body reading already observed a disconnect.
  if (res.writableFinished === true) dispose();
  else if (req.aborted === true || res.destroyed === true) abort();
  return { signal: controller.signal };
}

function commandSpecFromEnvironment(env) {
  const command = String(env.DEV_AGENT_EXPERIMENTAL_APP_SERVER_COMMAND || '').trim();
  if (!command) return null;
  let args = [];
  if (env.DEV_AGENT_EXPERIMENTAL_APP_SERVER_ARGS_JSON) {
    const parsed = JSON.parse(env.DEV_AGENT_EXPERIMENTAL_APP_SERVER_ARGS_JSON);
    if (!Array.isArray(parsed) || parsed.some((item) => typeof item !== 'string')) {
      throw new Error('DEV_AGENT_EXPERIMENTAL_APP_SERVER_ARGS_JSON must be a JSON string array.');
    }
    args = parsed;
  }
  return { command, args, source: 'experimental-env' };
}

export function createExperimentalRuntimeAdapter({ env = process.env } = {}) {
  const commandSpec = commandSpecFromEnvironment(env);
  return new CodexAppServerAdapter({
    defaultModel: env.DEV_AGENT_EXPERIMENTAL_CODEX_MODEL || null,
    clientOptions: {
      cwd: env.DEV_AGENT_EXPERIMENTAL_CODEX_CWD || process.cwd(),
      experimentalApi: true,
      ...(commandSpec ? { commandSpec } : {}),
    },
  });
}

export class ExperimentalRuntimeApi {
  constructor({
    enabled = process.env.DEV_AGENT_EXPERIMENTAL_RUNTIME_ADAPTER === '1',
    adapterFactory = () => createExperimentalRuntimeAdapter(),
    textAdapterFactory = null,
    loopbackOnly = true,
  } = {}) {
    this.enabled = enabled;
    this.adapterFactory = adapterFactory;
    this.textAdapterFactory = textAdapterFactory;
    this.loopbackOnly = loopbackOnly;
    this.adapter = null;
    this.textOwners = new Map();
    this.textAdapters = new Set();
    this.pendingText = new Set();
    this.textStopping = false;
    this.textPermanent = false;
    this.textStopPromise = null;
    this.lifecycleEpoch = 0;
  }

  get featureEnabled() {
    return this.enabled;
  }

  _textOwner(sessionId) {
    return this.textOwners.get(sessionId) || null;
  }

  _newTextAdapter(requestEpoch = this.lifecycleEpoch) {
    if (this.textPermanent || this.textStopping || requestEpoch !== this.lifecycleEpoch) {
      throw textRequestError({ code: RuntimeErrorCode.RUNTIME_UNAVAILABLE }, 'startSession');
    }
    if (typeof this.textAdapterFactory !== 'function') {
      // Keep the profile's existing precise 501 availability proof and avoid
      // constructing the ordinary App Server adapter.
      rejectUnavailableTextProfile('startSession');
    }
    const adapter = this.textAdapterFactory();
    if (!adapter || typeof adapter.startSession !== 'function' ||
        typeof adapter.startTurn !== 'function' || typeof adapter.readEvents !== 'function' ||
        typeof adapter.interruptTurn !== 'function' || typeof adapter.closeSession !== 'function' ||
        typeof adapter.closeAll !== 'function') {
      throw textRequestError({ code: RuntimeErrorCode.RUNTIME_UNAVAILABLE }, 'startSession');
    }
    this.textAdapters.add(adapter);
    return adapter;
  }

  _trackText(promise) {
    this.pendingText.add(promise);
    promise.then(() => {}, () => {}).finally(() => this.pendingText.delete(promise));
    return promise;
  }

  async _startTextSession(config, manifest, req, res, requestEpoch = this.lifecycleEpoch) {
    let adapter = null; let id = null; let abortClose = null;
    const closeOnAbort = () => {
      if (adapter && id && !abortClose) {
        abortClose = this._trackText(Promise.resolve().then(() => adapter.closeSession(id)));
      }
      return abortClose;
    };
    const abort = requestAbort(req, res, closeOnAbort);
    if (abort.signal.aborted) throw textRequestError({ code: 'runtime_start_unconfirmed' }, 'startSession');
    adapter = this._newTextAdapter(requestEpoch);
    const pending = Promise.resolve().then(() => {
      if (abort.signal.aborted || this.textStopping || this.textPermanent || requestEpoch !== this.lifecycleEpoch) {
        throw textRequestError({ code: 'runtime_start_unconfirmed' }, 'startSession');
      }
      return adapter.startSession(config, manifest, { signal: abort.signal });
    }).then(async started => {
      const startedId = started?.session_id;
      if (typeof startedId !== 'string' || !startedId) {
        throw textRequestError({ code: RuntimeErrorCode.RUNTIME_UNAVAILABLE }, 'startSession');
      }
      id = startedId;
      const existing = this._textOwner(id);
      if (existing && existing !== adapter) {
        // The just-created native resource remains this adapter's cleanup duty.
        try { await adapter.closeSession(id); } catch { /* retained by adapter */ }
        throw textRequestError({ code: RuntimeErrorCode.RUNTIME_UNAVAILABLE }, 'startSession');
      }
      this.textOwners.set(id, adapter);
      if (abort.signal.aborted || this.textStopping || this.textPermanent || requestEpoch !== this.lifecycleEpoch) {
        try { await closeOnAbort(); } catch { /* retain owner/tombstone */ }
        throw textRequestError({ code: 'runtime_stop_unconfirmed' }, 'startSession');
      }
      return started;
    }).catch(error => { throw textRequestError(error, 'startSession'); });
    return this._trackText(pending);
  }

  async _startTextTurn(adapter, sessionId, input, params, req, res, requestEpoch = this.lifecycleEpoch) {
    if (this.textStopping || this.textPermanent || requestEpoch !== this.lifecycleEpoch) {
      throw textRequestError({ code: RuntimeErrorCode.RUNTIME_UNAVAILABLE }, 'startTurn');
    }
    // The session id is already bound before turn/start returns.  Release the
    // exact native owner as soon as this HTTP mutation disconnects; waiting for
    // the turn response would leave a late provider dispatch alive.
    let abortClose = null; let entered = false;
    const closeOnAbort = () => {
      if (!entered) return null;
      if (!abortClose) abortClose = this._trackText(Promise.resolve().then(() => adapter.closeSession(sessionId)));
      return abortClose;
    };
    const abort = requestAbort(req, res, closeOnAbort);
    if (abort.signal.aborted) throw textRequestError({ code: 'runtime_start_unconfirmed' }, 'startTurn');
    const pending = Promise.resolve().then(() => {
      if (abort.signal.aborted || this.textStopping || this.textPermanent || requestEpoch !== this.lifecycleEpoch) {
        throw textRequestError({ code: 'runtime_start_unconfirmed' }, 'startTurn');
      }
      entered = true;
      return adapter.startTurn(sessionId, input, params, { signal: abort.signal });
    }).then(async turn => {
      if (abort.signal.aborted || this.textStopping || this.textPermanent || requestEpoch !== this.lifecycleEpoch) {
        try { await closeOnAbort(); } catch { /* retained owner */ }
        throw textRequestError({ code: 'runtime_stop_unconfirmed' }, 'startTurn');
      }
      return turn;
    }).catch(error => {
      // An attempted start with unknown outcome owns cleanup even when HTTP
      // remains connected. Input/state rejection leaves a fresh session usable.
      if (error instanceof RuntimeAdapterError && ['invalid_request', 'turn_not_active', 'session_not_found',
        'turn_not_found', 'unsupported_capability'].includes(error.code)) entered = false;
      if (['runtime_start_unconfirmed', 'provider_error', 'runtime_unavailable', 'timeout'].includes(error?.code)
          || !(error instanceof RuntimeAdapterError)) closeOnAbort();
      throw textRequestError(error, 'startTurn');
    });
    return this._trackText(pending);
  }

  async handle(req, res, url) {
    const path = url.pathname;
    let textOperation = null;
    if (!path.startsWith(EXPERIMENTAL_RUNTIME_PREFIX)) return false;
    if (!this.enabled) {
      writeJson(res, 404, {
        experimental: true,
        error: 'experimental_runtime_disabled',
        message: 'Set DEV_AGENT_EXPERIMENTAL_RUNTIME_ADAPTER=1 to enable this local API.',
      });
      return true;
    }
    if (this.loopbackOnly && !isLoopback(req.socket?.remoteAddress)) {
      writeJson(res, 403, {
        experimental: true,
        error: 'loopback_only',
        message: 'The experimental RuntimeAdapter API is available only on this machine.',
      });
      return true;
    }

    const requestEpoch = this.lifecycleEpoch;
    try {
      if (
        req.method === 'POST' &&
        path === `${EXPERIMENTAL_RUNTIME_PREFIX}/host/stop-app-server`
      ) {
        const appServerWasStarted = this.adapter != null || this.textAdapters.size !== 0;
        await this.stop();
        writeJson(res, 200, {
          experimental: true,
          stopped: appServerWasStarted,
        });
        return true;
      }
      const adapter = () => this._adapter(requestEpoch);
      if (req.method === 'GET' && path === EXPERIMENTAL_RUNTIME_PREFIX) {
        writeJson(res, 200, {
          experimental: true,
          schema_version: 1,
          provider: 'codex',
          warning: 'This local API may change before Flutter product integration.',
        });
        return true;
      }
      if (req.method === 'GET' && path === `${EXPERIMENTAL_RUNTIME_PREFIX}/auth`) {
        writeJson(res, 200, await adapter().getAuthStatus());
        return true;
      }
      if (req.method === 'GET' && path === `${EXPERIMENTAL_RUNTIME_PREFIX}/capabilities`) {
        const capabilities = await adapter().listCapabilities();
        writeJson(res, 200, projectTextOnlyCapability(capabilities, this.textAdapterFactory));
        return true;
      }
      if (req.method === 'POST' && path === `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions`) {
        const body = await readJson(req);
        if (isTextOnlyConfig(body.config)) {
          textOperation = 'startSession';
          writeJson(res, 200, await this._startTextSession(
            body.config || {}, body.context_manifest || {}, req, res, requestEpoch,
          ));
          return true;
        }
        writeJson(res, 200, await adapter().startSession(
          body.config || {},
          body.context_manifest || {},
        ));
        return true;
      }
      if (req.method === 'POST' && path === `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions/resume`) {
        const body = await readJson(req);
        if (isTextOnlyConfig(body.config)) {
          textOperation = 'resumeSession';
          // A text adapter has no resume surface.  Do not allow its profile to
          // fall through into the ordinary adapter.
          if (typeof this.textAdapterFactory !== 'function') {
            rejectUnavailableTextProfile(textOperation);
          }
          throw textRequestError({ code: RuntimeErrorCode.UNSUPPORTED_CAPABILITY }, textOperation);
        }
        writeJson(res, 200, await adapter().resumeSession(
          body.provider_session_id,
          body.config || {},
        ));
        return true;
      }

      const eventsMatch = path.match(
        /^\/experimental\/v1\/runtime\/sessions\/([^/]+)\/events$/,
      );
      if (req.method === 'GET' && eventsMatch) {
        const sessionId = decodeURIComponent(eventsMatch[1]);
        const textOwner = this._textOwner(sessionId);
        if (textOwner) {
          textOperation = 'readEvents';
          writeJson(res, 200, await Promise.resolve(textOwner.readEvents(sessionId, {
            afterSequence: Number(url.searchParams.get('after') || 0),
          })).catch(error => { throw textRequestError(error, textOperation); }));
          return true;
        }
        writeJson(res, 200, adapter().readEvents(sessionId, {
          afterSequence: Number(url.searchParams.get('after') || 0),
        }));
        return true;
      }

      const startTurnMatch = path.match(
        /^\/experimental\/v1\/runtime\/sessions\/([^/]+)\/turns$/,
      );
      if (req.method === 'POST' && startTurnMatch) {
        const body = await readJson(req);
        const sessionId = decodeURIComponent(startTurnMatch[1]);
        const textOwner = this._textOwner(sessionId);
        if (textOwner) {
          textOperation = 'startTurn';
          writeJson(res, 200, await this._startTextTurn(
            textOwner, sessionId, body.input, body.params || {}, req, res, requestEpoch,
          ));
          return true;
        }
        writeJson(res, 200, await adapter().startTurn(
          sessionId,
          body.input,
          body.params || {},
        ));
        return true;
      }

      const turnActionMatch = path.match(
        /^\/experimental\/v1\/runtime\/sessions\/([^/]+)\/turns\/([^/]+)\/(steer|interrupt)$/,
      );
      if (req.method === 'POST' && turnActionMatch) {
        const sessionId = decodeURIComponent(turnActionMatch[1]);
        const turnId = decodeURIComponent(turnActionMatch[2]);
        const action = turnActionMatch[3];
        const body = await readJson(req);
        const textOwner = this._textOwner(sessionId);
        if (textOwner) {
          textOperation = action === 'interrupt' ? 'interruptTurn' : 'steerTurn';
          if (action !== 'interrupt') {
            throw textRequestError({ code: RuntimeErrorCode.UNSUPPORTED_CAPABILITY }, textOperation);
          }
          writeJson(res, 200, await Promise.resolve(textOwner.interruptTurn(sessionId, turnId))
            .catch(error => { throw textRequestError(error, textOperation); }));
          return true;
        }
        const result = action === 'steer'
          ? await adapter().steerTurn(sessionId, turnId, body.input, {
              activityTimeoutMs: body.activity_timeout_ms,
            })
          : await adapter().interruptTurn(sessionId, turnId);
        writeJson(res, 200, result);
        return true;
      }

      const closeSessionMatch = path.match(
        /^\/experimental\/v1\/runtime\/sessions\/([^/]+)$/,
      );
      if (req.method === 'DELETE' && closeSessionMatch) {
        const sessionId = decodeURIComponent(closeSessionMatch[1]);
        const textOwner = this._textOwner(sessionId);
        if (textOwner) {
          textOperation = 'closeSession';
          writeJson(res, 200, await Promise.resolve(textOwner.closeSession(sessionId))
            .catch(error => { throw textRequestError(error, textOperation); }));
          return true;
        }
        writeJson(res, 200, await adapter().closeSession(
          sessionId,
        ));
        return true;
      }

      const approvalMatch = path.match(
        /^\/experimental\/v1\/runtime\/approvals\/([^/]+)$/,
      );
      if (req.method === 'POST' && approvalMatch) {
        const body = await readJson(req);
        writeJson(res, 200, await adapter().respondToApproval(
          decodeURIComponent(approvalMatch[1]),
          body.decision,
        ));
        return true;
      }

      const toolCallMatch = path.match(
        /^\/experimental\/v1\/runtime\/tool-calls\/([^/]+)$/,
      );
      if (req.method === 'POST' && toolCallMatch) {
        const body = await readJson(req);
        writeJson(res, 200, await adapter().respondToToolCall(
          decodeURIComponent(toolCallMatch[1]),
          {
            success: body.success,
            content_items: body.content_items,
          },
        ));
        return true;
      }

      writeJson(res, 404, { experimental: true, error: 'not_found' });
      return true;
    } catch (error) {
      const normalized = textOperation
        ? textRequestError(error, textOperation)
        : error instanceof RuntimeAdapterError
        ? error
        : asRuntimeAdapterError(error, { operation: 'experimentalHttpApi' });
      writeJson(res, errorStatus(normalized.code), {
        experimental: true,
        error: normalized.toJSON(),
      });
      return true;
    }
  }

  stop({ permanent = false } = {}) {
    this.lifecycleEpoch++;
    if (permanent) this.textPermanent = true;
    this.textStopping = true;
    if (this.textStopPromise) return this.textStopPromise;
    const attempt = Promise.resolve().then(async () => {
      // Acquired text adapters own their native child even while their create
      // response is pending. Start closeAll before awaiting those responses.
      const adapters = [...this.textAdapters];
      const closes = adapters.map(adapter => Promise.resolve().then(() => adapter.closeAll()));
      const observedCloses = Promise.allSettled(closes);
      while (this.pendingText.size) await Promise.allSettled([...this.pendingText]);
      const results = await observedCloses;
      if (results.some(result => result.status !== 'fulfilled')) {
        throw textRequestError({ code: 'runtime_stop_unconfirmed' }, 'stop');
      }
      if (this.adapter) {
        await this.adapter.stop();
        this.adapter = null;
      }
      if (!this.textPermanent) this.textStopping = false;
      return { status: 'closed' };
    });
    this.textStopPromise = attempt;
    void attempt.catch(() => {
      // Keep textStopping and all owner/tombstone mappings so a caller retries
      // against the same native obligations instead of making a replacement.
    }).finally(() => {
      if (this.textStopPromise === attempt) this.textStopPromise = null;
    });
    return attempt;
  }

  _adapter(requestEpoch = this.lifecycleEpoch) {
    if (this.textPermanent || this.textStopping || requestEpoch !== this.lifecycleEpoch) {
      throw new RuntimeAdapterError('Runtime is stopping or stopped.', {
        code: RuntimeErrorCode.RUNTIME_UNAVAILABLE, operation: 'experimentalHttpApi',
      });
    }
    if (!this.adapter) this.adapter = this.adapterFactory();
    return this.adapter;
  }
}
