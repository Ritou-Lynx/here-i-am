import { createHash } from 'node:crypto';
import { WorkbenchProductConversationGuardian } from './workbench_product_conversation_guardian.mjs';

const BRAND = new WeakSet();
const RUNTIME = '/p6/r7/product/conversation/experimental/v1/runtime';
const TASK = '/p6/r7/product/task';
const CLOSE = '/p6/r7/product/conversation/close';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HASH = /^[0-9a-f]{64}$/;
const INPUT_PREFIX = 'Complete the following standalone text task using only the supplied '
  + 'text. Return the requested text result. No tools, outside data, product '
  + 'actions, files, shell, network or memory writes are available. '
  + 'If the task needs those, explain the limitation in the text result.\nTask goal:\n';
const PARTIAL_PREFIX = '\nThis is a new execution attempt, not a resumed provider turn. '
  + 'Previously saved partial text follows; produce one complete final result:\n';
const plain = value => value !== null && typeof value === 'object' && !Array.isArray(value)
  && [Object.prototype, null].includes(Object.getPrototypeOf(value));
const exact = (value, keys) => plain(value) && Object.keys(value).every(key => keys.includes(key));
const empty = value => value === undefined || exact(value, []);
const fail = code => { throw Object.assign(new Error(code), { code }); };
const safe = value => {
  const text = JSON.stringify(value);
  return Buffer.byteLength(text) <= 64 * 1024 && !/[^\x20-\x7e]/.test(text) ? value : null;
};
const sha = value => createHash('sha256').update(value, 'utf8').digest('hex');
const requestError = () => ({ handled: true, status: 400, body: { error: 'product_request_rejected' } });
const unavailable = () => ({ handled: true, status: 503, body: { error: 'product_host_closing' } });
const readError = () => fail('product_request_rejected');

/// Decode only the bounded JSON request shape consumed by [handle]. Root must
/// complete connection, token, origin, and shutdown checks before calling it.
export async function readWorkbenchProductRequest(req) {
  if (!req || typeof req.method !== 'string' || !req.method || typeof req[Symbol.asyncIterator] !== 'function'
    || req.aborted === true) readError();
  const chunks = [];
  let length = 0;
  try {
    for await (const value of req) {
      if (req.aborted === true || !(value instanceof Uint8Array)) readError();
      length += value.byteLength;
      if (length > 64 * 1024) readError();
      chunks.push(Buffer.from(value));
    }
  } catch { readError(); }
  if (req.aborted === true) readError();
  if (length === 0) return { method: req.method };
  const contentType = req.headers?.['content-type'];
  if (typeof contentType !== 'string'
    || !/^application\/json(?:\s*;\s*charset=(?:utf-8|utf8))?\s*$/i.test(contentType)) readError();
  let body;
  try {
    body = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks)));
  } catch { readError(); }
  return { method: req.method, body };
}

export const isWorkbenchProductHostBinding = value =>
  value !== null && typeof value === 'object' && BRAND.has(value);

/// Trusted root supplies [transport]. This class owns no listener, socket,
/// endpoint, credentials, process, or provider discovery capability.
export class WorkbenchProductHostBinding {
  #conversationId; #scopeHash; #transport; #guardian; #task = null; #closing = false;
  #close = null;

  constructor({ conversationId, taskScopeHash, dynamicTool, transport }) {
    if (typeof conversationId !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9_-]{0,255}$/.test(conversationId)
      || typeof taskScopeHash !== 'string' || !HASH.test(taskScopeHash)
      || typeof transport !== 'function') fail('product_binding_invalid');
    this.#conversationId = conversationId;
    this.#scopeHash = taskScopeHash;
    this.#transport = transport;
    this.#guardian = new WorkbenchProductConversationGuardian({ conversationId, dynamicTool, transport });
    BRAND.add(this);
  }

  async handle(req, url) {
    const parsed = this.#url(url);
    if (!parsed || !plain(req) || typeof req.method !== 'string'
      || !exact(req, ['method', 'body']) || !this.#bodySize(req.body)) return requestError();
    if (parsed.pathname === TASK) return this.#taskRoute(req, parsed);
    if (parsed.pathname === CLOSE) return this.#closeRoute(req, parsed);
    if (parsed.pathname !== RUNTIME && !parsed.pathname.startsWith(`${RUNTIME}/`)) {
      return { handled: false };
    }
    return this.#runtimeRoute(req, parsed);
  }

  permitsTextSession(manifest) {
    return !this.#closing && this.#task !== null && exact(manifest,
      ['task_id', 'execution_epoch', 'execution_mode'])
      && manifest.task_id === this.#task.id && UUID.test(manifest.execution_epoch)
      && manifest.execution_mode === 'isolated_text_only';
  }

  permitsTextInput(manifest, input) {
    if (!this.permitsTextSession(manifest) || typeof input !== 'string'
      || Buffer.byteLength(input, 'utf8') > 256 * 1024) return false;
    const base = `${INPUT_PREFIX}${this.#task.goal}\n`;
    if (input === base) return true;
    if (!input.startsWith(`${base}${PARTIAL_PREFIX}`)) return false;
    const previous = input.slice((`${base}${PARTIAL_PREFIX}`).length);
    return previous.length >= 1 && previous.length <= 24000 && Buffer.byteLength(previous, 'utf8') <= 96 * 1024;
  }

  closeForHostLifecycle() {
    if (this.#close) return this.#close;
    this.#closing = true;
    this.#close = Promise.resolve(this.#guardian.closeForHostLifecycle());
    return this.#close;
  }

  snapshot() {
    const guardian = safe(this.#guardian.snapshot());
    return Object.freeze({ schema: 'p6_r7_product_host_binding_v1', closing: this.#closing,
      task_id: this.#task?.id ?? null, task_scope_hash: this.#task?.scopeHash ?? null,
      goal_sha256: this.#task?.goalHash ?? null, guardian });
  }

  #url(value) {
    try {
      const parsed = value instanceof URL ? value : new URL(String(value), 'http://localhost');
      if (parsed.username || parsed.password || parsed.hash || parsed.searchParams.size > 1) return null;
      return parsed;
    } catch { return null; }
  }

  #bodySize(value) {
    if (value === undefined) return true;
    try { return Buffer.byteLength(JSON.stringify(value), 'utf8') <= 64 * 1024; }
    catch { return false; }
  }

  #open() { return !this.#closing; }

  #taskRoute(req, url) {
    if (req.method !== 'POST' || url.search || !this.#open() || !exact(req.body, ['task_id', 'scope_hash', 'goal'])) {
      return requestError();
    }
    const body = req.body;
    if (!UUID.test(body.task_id) || body.scope_hash !== this.#scopeHash || typeof body.goal !== 'string'
      || !body.goal.trim() || body.goal.length > 4000) return requestError();
    const candidate = { id: body.task_id, scopeHash: body.scope_hash, goal: body.goal, goalHash: sha(body.goal) };
    if (this.#task && (this.#task.id !== candidate.id || this.#task.scopeHash !== candidate.scopeHash
      || this.#task.goal !== candidate.goal)) return requestError();
    this.#task ??= candidate;
    return { handled: true, status: 200, body: { schema: 'p6_r7_product_task_bound_v1',
      task_id: this.#task.id, scope_hash: this.#task.scopeHash, goal_sha256: this.#task.goalHash } };
  }

  async #closeRoute(req, url) {
    if (req.method !== 'POST' || url.search || !empty(req.body)) return requestError();
    const result = await this.closeForHostLifecycle();
    return result?.status === 'closed'
      ? { handled: true, status: 200, body: result }
      : unavailable();
  }

  async #runtimeRoute(req, url) {
    const suffix = url.pathname.slice(RUNTIME.length);
    if (!suffix || !this.#bodySize(req.body)) return requestError();
    try {
      let body;
      if (suffix === '/sessions' && req.method === 'POST' && !url.search
        && exact(req.body, ['config', 'context_manifest'])) {
        body = await this.#guardian.startSession(req.body.config, req.body.context_manifest);
      } else if ((/^\/sessions\/([A-Za-z0-9_-]{1,256})\/events$/).test(suffix) && req.method === 'GET'
        && empty(req.body) && [...url.searchParams.keys()].every(key => key === 'after')) {
        const after = url.searchParams.get('after') ?? '0';
        if (!/^\d+$/.test(after) || Number(after) > Number.MAX_SAFE_INTEGER) return requestError();
        body = await this.#guardian.readEvents(decodeURIComponent(suffix.split('/')[2]), { afterSequence: Number(after) });
      } else if ((/^\/sessions\/([A-Za-z0-9_-]{1,256})\/turns$/).test(suffix) && req.method === 'POST'
        && !url.search && exact(req.body, ['input'])) {
        body = await this.#guardian.startTurn(decodeURIComponent(suffix.split('/')[2]), req.body.input);
      } else if ((/^\/sessions\/([A-Za-z0-9_-]{1,256})\/turns\/([A-Za-z0-9_-]{1,256})\/interrupt$/).test(suffix)
        && req.method === 'POST' && !url.search && empty(req.body)) {
        const parts = suffix.split('/'); body = await this.#guardian.interruptTurn(decodeURIComponent(parts[2]), decodeURIComponent(parts[4]));
      } else if ((/^\/tool-calls\/([A-Za-z0-9_-]{1,256})$/).test(suffix) && req.method === 'POST'
        && !url.search && exact(req.body, ['success', 'content_items'])) {
        body = await this.#guardian.respondToToolCall(decodeURIComponent(suffix.split('/')[2]), req.body);
      } else if ((/^\/sessions\/([A-Za-z0-9_-]{1,256})$/).test(suffix) && req.method === 'DELETE'
        && !url.search && empty(req.body)) {
        body = await this.#guardian.closeSession(decodeURIComponent(suffix.split('/')[2]));
      } else return requestError();
      return { handled: true, status: 200, body };
    } catch { return this.#closing ? unavailable() : requestError(); }
  }
}
