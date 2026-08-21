import { CodexAppServerAdapter } from './codex_app_server_adapter.mjs';
import {
  RuntimeAdapterError,
  RuntimeErrorCode,
  asRuntimeAdapterError,
} from './runtime_adapter.mjs';

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
      return 503;
    default:
      return 500;
  }
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
    loopbackOnly = true,
  } = {}) {
    this.enabled = enabled;
    this.adapterFactory = adapterFactory;
    this.loopbackOnly = loopbackOnly;
    this.adapter = null;
  }

  get featureEnabled() {
    return this.enabled;
  }

  async handle(req, res, url) {
    const path = url.pathname;
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

    try {
      if (
        req.method === 'POST' &&
        path === `${EXPERIMENTAL_RUNTIME_PREFIX}/host/stop-app-server`
      ) {
        const appServerWasStarted = this.adapter != null;
        await this.stop();
        writeJson(res, 200, {
          experimental: true,
          stopped: appServerWasStarted,
        });
        return true;
      }
      const adapter = this._adapter();
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
        writeJson(res, 200, await adapter.getAuthStatus());
        return true;
      }
      if (req.method === 'GET' && path === `${EXPERIMENTAL_RUNTIME_PREFIX}/capabilities`) {
        writeJson(res, 200, await adapter.listCapabilities());
        return true;
      }
      if (req.method === 'POST' && path === `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions`) {
        const body = await readJson(req);
        writeJson(res, 200, await adapter.startSession(
          body.config || {},
          body.context_manifest || {},
        ));
        return true;
      }
      if (req.method === 'POST' && path === `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions/resume`) {
        const body = await readJson(req);
        writeJson(res, 200, await adapter.resumeSession(
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
        writeJson(res, 200, adapter.readEvents(sessionId, {
          afterSequence: Number(url.searchParams.get('after') || 0),
        }));
        return true;
      }

      const startTurnMatch = path.match(
        /^\/experimental\/v1\/runtime\/sessions\/([^/]+)\/turns$/,
      );
      if (req.method === 'POST' && startTurnMatch) {
        const body = await readJson(req);
        writeJson(res, 200, await adapter.startTurn(
          decodeURIComponent(startTurnMatch[1]),
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
        const result = action === 'steer'
          ? await adapter.steerTurn(sessionId, turnId, body.input, {
              activityTimeoutMs: body.activity_timeout_ms,
            })
          : await adapter.interruptTurn(sessionId, turnId);
        writeJson(res, 200, result);
        return true;
      }

      const closeSessionMatch = path.match(
        /^\/experimental\/v1\/runtime\/sessions\/([^/]+)$/,
      );
      if (req.method === 'DELETE' && closeSessionMatch) {
        writeJson(res, 200, await adapter.closeSession(
          decodeURIComponent(closeSessionMatch[1]),
        ));
        return true;
      }

      const approvalMatch = path.match(
        /^\/experimental\/v1\/runtime\/approvals\/([^/]+)$/,
      );
      if (req.method === 'POST' && approvalMatch) {
        const body = await readJson(req);
        writeJson(res, 200, await adapter.respondToApproval(
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
        writeJson(res, 200, await adapter.respondToToolCall(
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
      const normalized = error instanceof RuntimeAdapterError
        ? error
        : asRuntimeAdapterError(error, { operation: 'experimentalHttpApi' });
      writeJson(res, errorStatus(normalized.code), {
        experimental: true,
        error: normalized.toJSON(),
      });
      return true;
    }
  }

  async stop() {
    if (!this.adapter) return;
    await this.adapter.stop();
    this.adapter = null;
  }

  _adapter() {
    if (!this.adapter) this.adapter = this.adapterFactory();
    return this.adapter;
  }
}
