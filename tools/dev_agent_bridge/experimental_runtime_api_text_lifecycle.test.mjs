import assert from 'node:assert/strict';
import http from 'node:http';
import test from 'node:test';
import { EventEmitter, once } from 'node:events';

import { EXPERIMENTAL_RUNTIME_PREFIX, ExperimentalRuntimeApi } from './experimental_runtime_api.mjs';
import { RuntimeAdapterError } from './runtime_adapter.mjs';

const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

class FakeTextAdapter {
  constructor(id, { startGate = null, turnGate = null } = {}) {
    this.id = id;
    this.startGate = startGate;
    this.turnGate = turnGate;
    this.starts = 0;
    this.turns = 0;
    this.closes = [];
    this.closeAllCalls = 0;
  }
  async startSession(_config, manifest, { signal } = {}) {
    this.starts++;
    await this.startGate?.promise;
    return { session_id: this.id, execution_profile_receipt: { execution_epoch: manifest.execution_epoch }, signal_aborted: signal?.aborted === true };
  }
  async startTurn(_id, input, _params, { signal } = {}) {
    this.turns++;
    await this.turnGate?.promise;
    return { local_turn_id: `local-${input}`, signal_aborted: signal?.aborted === true };
  }
  readEvents() { return { status: 'ready', events: [], next_sequence: 0 }; }
  async interruptTurn() { return { accepted: true }; }
  async closeSession(id) { this.closes.push(id); return { status: 'closed', stop_receipt: { fixed: true } }; }
  async closeAll() { this.closeAllCalls++; return { status: 'closed' }; }
}

async function withServer(api, fn) {
  const server = http.createServer((req, res) => {
    void api.handle(req, res, new URL(req.url, 'http://127.0.0.1')).catch(() => {
      if (!res.writableEnded) res.destroy();
    });
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  try { await fn(`http://127.0.0.1:${server.address().port}`); }
  finally { server.closeAllConnections(); server.close(); await once(server, 'close'); }
}

function request(base, method, path, body, { abort = false } = {}) {
  const target = new URL(path, base);
  const payload = body == null ? null : Buffer.from(JSON.stringify(body));
  const req = http.request(target, { method, headers: payload ? { 'content-type': 'application/json', 'content-length': payload.length } : {} });
  if (abort) {
    req.on('error', () => {});
    req.end(payload);
    // Let the local server enter the deliberately gated mutation before the
    // client closes its real TCP socket.
    setTimeout(() => req.destroy(), 15);
    return Promise.resolve(null);
  }
  return new Promise((resolve, reject) => {
    req.on('error', reject);
    req.on('response', res => {
      const chunks = [];
      res.on('data', chunk => chunks.push(chunk));
      res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(Buffer.concat(chunks)) }));
    });
    req.end(payload);
  });
}

function openMutation(base, path, body) {
  const target = new URL(path, base);
  const payload = Buffer.from(JSON.stringify(body));
  const req = http.request(target, { method: 'POST', headers: {
    'content-type': 'application/json', 'content-length': payload.length,
  } });
  req.on('error', () => {});
  req.end(payload);
  return req;
}

const textBody = epoch => ({ config: { runtime_profile: 'workbench_text_only_v1' }, context_manifest: { execution_epoch: epoch } });

// A response whose end() has accepted the body but has not emitted finish yet
// models the exact success-to-wire gap without relying on socket buffer timing.
function exchange(api, method, suffix, body, { finished = false, aborted = false, destroyed = false, readGate } = {}) {
  const req = new EventEmitter();
  Object.assign(req, { method, socket: { remoteAddress: '127.0.0.1' }, aborted });
  req[Symbol.asyncIterator] = async function* () { if (readGate) await readGate.promise; yield Buffer.from(JSON.stringify(body ?? {})); };
  const res = new EventEmitter();
  Object.assign(res, { writableFinished: false, destroyed,
    writeHead(status) { this.statusCode = status; },
    end(value) { this.body = JSON.parse(value); if (finished) { this.writableFinished = true; this.emit('finish'); } } });
  const handled = api.handle(req, res, new URL(`${EXPERIMENTAL_RUNTIME_PREFIX}${suffix}`, 'http://127.0.0.1'));
  return { req, res, handled };
}

const flush = () => new Promise(resolve => setImmediate(resolve));

test('text sessions are isolated from the lazy ordinary adapter and retain their owner tombstone', async () => {
  let ordinary = 0;
  const adapters = [];
  const api = new ExperimentalRuntimeApi({ enabled: true, adapterFactory: () => { ordinary++; throw new Error('ordinary'); },
    textAdapterFactory: () => { const adapter = new FakeTextAdapter(`s${adapters.length + 1}`); adapters.push(adapter); return adapter; } });
  await withServer(api, async base => {
    const first = await request(base, 'POST', `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions`, textBody('epoch-1'));
    const second = await request(base, 'POST', `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions`, textBody('epoch-2'));
    assert.equal(first.status, 200); assert.equal(second.status, 200); assert.equal(ordinary, 0);
    await request(base, 'POST', `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions/s1/turns`, { input: 'a' });
    assert.equal(adapters[0].turns, 1); assert.equal(adapters[1].turns, 0);
    await request(base, 'DELETE', `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions/s1`);
    await request(base, 'DELETE', `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions/s1`);
    assert.deepEqual(adapters[0].closes, ['s1', 's1']);
  });
});

test('real HTTP mutation disconnects close the owned text attempt, while normal and GET closes do not', async () => {
  let adapter;
  const startGate = Promise.withResolvers();
  const turnGate = Promise.withResolvers();
  const api = new ExperimentalRuntimeApi({ enabled: true, textAdapterFactory: () => (adapter = new FakeTextAdapter('s1', { startGate, turnGate })) });
  await withServer(api, async base => {
    const createRequest = openMutation(base, `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions`, textBody('epoch-1'));
    while (!adapter?.starts) await delay(1);
    createRequest.destroy();
    await delay(5);
    startGate.resolve();
    await delay(30);
    assert.deepEqual(adapter.closes, ['s1']);

    // A new adapter has a completed response; neither its normal response
    // finish nor an events GET disconnect owns cancellation.
    const normal = new FakeTextAdapter('s2');
    api.textAdapterFactory = () => normal;
    const started = await request(base, 'POST', `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions`, textBody('epoch-2'));
    assert.equal(started.status, 200); assert.deepEqual(normal.closes, []);
    await request(base, 'GET', `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions/s2/events`, null, { abort: true });
    await delay(10); assert.deepEqual(normal.closes, []);

    const turnAdapter = new FakeTextAdapter('s3', { turnGate });
    api.textAdapterFactory = () => turnAdapter;
    await request(base, 'POST', `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions`, textBody('epoch-3'));
    const turnRequest = openMutation(base, `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions/s3/turns`, { input: 'pending' });
    while (!turnAdapter.turns) await delay(1);
    turnRequest.destroy();
    await delay(5);
    turnGate.resolve(); await delay(30);
    assert.deepEqual(turnAdapter.closes, ['s3']);
  });
});

test('stop blocks new text work, starts closeAll before pending create settles, and permanent stop stays closed', async () => {
  const gate = Promise.withResolvers();
  const adapter = new FakeTextAdapter('s1', { startGate: gate });
  const api = new ExperimentalRuntimeApi({ enabled: true, textAdapterFactory: () => adapter });
  await withServer(api, async base => {
    void request(base, 'POST', `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions`, textBody('epoch-1'));
    await delay(10);
    const stopping = api.stop({ permanent: true });
    await delay(10); assert.equal(adapter.closeAllCalls, 1);
    gate.resolve(); await stopping;
    const rejected = await request(base, 'POST', `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions`, textBody('epoch-2'));
    assert.equal(rejected.status, 503); assert.equal(rejected.body.error.code, 'runtime_unavailable');
  });
});

test('successful create and turn remain cancellable until response finish; normal finish detaches', async () => {
  const adapter = new FakeTextAdapter('s1');
  const api = new ExperimentalRuntimeApi({ enabled: true, textAdapterFactory: () => adapter });
  const created = exchange(api, 'POST', '/sessions', textBody('e1'));
  await created.handled;
  assert.equal(created.res.statusCode, 200); assert.equal(created.res.writableFinished, false);
  assert.equal(created.res.listenerCount('close'), 1);
  created.res.emit('close'); await flush();
  assert.deepEqual(adapter.closes, ['s1']);
  assert.equal(created.res.listenerCount('finish'), 0);

  const turn = exchange(api, 'POST', '/sessions/s1/turns', { input: 'accepted' });
  await turn.handled; assert.equal(turn.res.statusCode, 200);
  turn.res.emit('close'); await flush();
  assert.deepEqual(adapter.closes, ['s1', 's1']);

  const normal = exchange(api, 'POST', '/sessions/s1/turns', { input: 'finished' }, { finished: true });
  await normal.handled;
  assert.equal(normal.res.listenerCount('close'), 0);
  assert.equal(normal.req.listenerCount('aborted'), 0);
  normal.res.emit('close'); normal.req.emit('aborted'); await flush();
  assert.equal(adapter.closes.length, 2);
});

test('disconnect already observed before listener installation never starts or closes an existing owner', async () => {
  for (const state of [{ aborted: true }, { destroyed: true }]) {
    let made = 0;
    const adapter = new FakeTextAdapter('s1');
    const api = new ExperimentalRuntimeApi({ enabled: true, textAdapterFactory: () => { made++; return adapter; } });
    const create = exchange(api, 'POST', '/sessions', textBody('e1'), state);
    await create.handled; assert.equal(create.res.statusCode, 503); assert.equal(made, 0);
    api.textOwners.set('s1', adapter); api.textAdapters.add(adapter);
    const turn = exchange(api, 'POST', '/sessions/s1/turns', { input: 'not sent' }, state);
    await turn.handled; await flush();
    assert.equal(adapter.turns, 0); assert.deepEqual(adapter.closes, []);
  }
});

test('synchronous close throw on disconnect is observed and retains the exact owner for retry', async () => {
  const adapter = new FakeTextAdapter('s1'); let fail = true;
  adapter.closeSession = id => { adapter.closes.push(id); if (fail) throw new Error('PRIVATE TOKEN'); return { status: 'closed' }; };
  const api = new ExperimentalRuntimeApi({ enabled: true, textAdapterFactory: () => adapter });
  const create = exchange(api, 'POST', '/sessions', textBody('e1'));
  await create.handled;
  assert.doesNotThrow(() => create.res.emit('close')); await flush();
  assert.equal(api.textOwners.get('s1'), adapter);
  fail = false;
  const retry = exchange(api, 'DELETE', '/sessions/s1', {}, { finished: true });
  await retry.handled; assert.equal(retry.res.statusCode, 200); assert.deepEqual(adapter.closes, ['s1', 's1']);
});

test('fast close rejection is observed while stop still waits for pending creation', async () => {
  const gate = Promise.withResolvers();
  const adapter = new FakeTextAdapter('s1', { startGate: gate });
  adapter.closeAll = async () => { adapter.closeAllCalls++; throw new Error('PRIVATE CLOSE'); };
  const api = new ExperimentalRuntimeApi({ enabled: true, textAdapterFactory: () => adapter });
  const create = exchange(api, 'POST', '/sessions', textBody('e1'), { finished: true });
  await flush();
  let settled = false;
  const stop = api.stop().then(() => { assert.fail('unknown close cannot succeed'); }, error => {
    settled = true; assert.equal(error.code, 'runtime_stop_unconfirmed');
  });
  await flush(); await flush();
  assert.equal(adapter.closeAllCalls, 1); assert.equal(settled, false);
  gate.resolve(); await create.handled; await stop;
  assert.equal(create.res.statusCode, 503);
  assert.deepEqual(adapter.closes, ['s1']);
  adapter.closeAll = async () => { adapter.closeAllCalls++; return { status: 'closed' }; };
  await api.stop(); assert.equal(adapter.closeAllCalls, 2);
  assert.equal(api.textOwners.get('s1'), adapter);
});

test('generic entry is fenced during/permanent stop and old request bodies cannot cross a restart', async () => {
  let made = 0; let starts = 0;
  const api = new ExperimentalRuntimeApi({ enabled: true, adapterFactory: () => {
    made++; return { startSession: async () => { starts++; return { session_id: 'ordinary' }; }, stop: async () => {} };
  } });
  const gate = Promise.withResolvers();
  const stale = exchange(api, 'POST', '/sessions', { config: {} }, { readGate: gate, finished: true });
  const stopping = api.stop();
  assert.throws(() => api._adapter(), error => error.code === 'runtime_unavailable');
  await stopping; gate.resolve(); await stale.handled;
  assert.equal(stale.res.statusCode, 503); assert.equal(made, 0);
  const fresh = exchange(api, 'POST', '/sessions', { config: {} }, { finished: true });
  await fresh.handled; assert.equal(fresh.res.statusCode, 200); assert.equal(starts, 1);
  await api.stop({ permanent: true });
  const after = exchange(api, 'POST', '/sessions', { config: {} }, { finished: true });
  await after.handled; assert.equal(after.res.statusCode, 503); assert.equal(made, 1);
});

test('unconfirmed turn errors trigger tracked same-owner cleanup while input rejection preserves the session', async () => {
  for (const code of ['runtime_start_unconfirmed', 'provider_error', 'runtime_unavailable', 'invalid_request', 'turn_not_active']) {
    const gate = Promise.withResolvers();
    const adapter = new FakeTextAdapter('s1');
    adapter.startTurn = async () => { adapter.turns++; throw new RuntimeAdapterError('PRIVATE TOKEN', { code }); };
    adapter.closeSession = async id => { adapter.closes.push(id); await gate.promise; throw new Error('PRIVATE CLOSE'); };
    const api = new ExperimentalRuntimeApi({ enabled: true, textAdapterFactory: () => adapter });
    const create = exchange(api, 'POST', '/sessions', textBody('e1'), { finished: true }); await create.handled;
    const turn = exchange(api, 'POST', '/sessions/s1/turns', { input: 'attempt' }, { finished: true }); await turn.handled;
    assert.doesNotMatch(JSON.stringify(turn.res.body), /PRIVATE|TOKEN/);
    const unknown = !['invalid_request', 'turn_not_active'].includes(code);
    assert.equal(adapter.closes.length, unknown ? 1 : 0);
    assert.equal(api.pendingText.size > 0, unknown);
    let stopped = false; const stop = api.stop().then(() => { stopped = true; });
    await flush(); assert.equal(stopped, !unknown);
    gate.resolve(); await stop;
    assert.equal(api.textOwners.get('s1'), adapter);
  }
});

test('known input/state rejection disables later response abort cleanup for the original session', async () => {
  for (const code of ['invalid_request', 'turn_not_active']) {
    const adapter = new FakeTextAdapter('s1');
    adapter.startTurn = async () => { adapter.turns++; throw new RuntimeAdapterError('Rejected', { code }); };
    const api = new ExperimentalRuntimeApi({ enabled: true, textAdapterFactory: () => adapter });
    const create = exchange(api, 'POST', '/sessions', textBody('e1'), { finished: true }); await create.handled;
    const turn = exchange(api, 'POST', '/sessions/s1/turns', { input: 'rejected' }); await turn.handled;
    assert.equal(turn.res.body.error.code, code);
    turn.res.emit('close'); turn.req.emit('aborted'); await flush();
    assert.equal(adapter.turns, 1); assert.deepEqual(adapter.closes, []);
  }
});

test('abort after listener setup but before invoking start does not close or dispatch', async () => {
  const adapter = new FakeTextAdapter('s1');
  const api = new ExperimentalRuntimeApi({ enabled: true, textAdapterFactory: () => adapter });
  const req = new EventEmitter(); const res = new EventEmitter(); res.writableFinished = false;
  const pending = api._startTextTurn(adapter, 's1', 'not entered', {}, req, res);
  req.emit('aborted');
  await assert.rejects(pending, error => error.code === 'runtime_start_unconfirmed'); await flush();
  assert.equal(adapter.turns, 0); assert.deepEqual(adapter.closes, []);
});

test('stop fences mutations reserved before their asynchronous adapter invocation', async () => {
  for (const operation of ['create', 'turn']) {
    const adapter = new FakeTextAdapter('s1');
    const api = new ExperimentalRuntimeApi({ enabled: true, textAdapterFactory: () => adapter });
    api.textAdapters.add(adapter);
    const req = new EventEmitter(); const res = new EventEmitter(); res.writableFinished = false;
    const pending = operation === 'create'
      ? api._startTextSession(textBody('e1').config, { execution_epoch: 'e1' }, req, res)
      : api._startTextTurn(adapter, 's1', 'not entered', {}, req, res);
    const stopping = api.stop();
    await assert.rejects(pending, error => error.code === 'runtime_start_unconfirmed');
    await stopping;
    assert.equal(adapter.starts, 0); assert.equal(adapter.turns, 0); assert.deepEqual(adapter.closes, []);
    res.writableFinished = true; res.emit('finish');
  }
});

test('only locally issued unavailable-profile errors preserve profile details; forged errors are sanitized', async () => {
  let ordinary = 0;
  const defaultApi = new ExperimentalRuntimeApi({ enabled: true, adapterFactory: () => { ordinary++; throw new Error('ordinary'); } });
  const unavailable = exchange(defaultApi, 'POST', '/sessions', textBody('e1'), { finished: true });
  await unavailable.handled;
  assert.equal(unavailable.res.statusCode, 501); assert.equal(ordinary, 0);
  assert.equal(unavailable.res.body.error.details.profile, 'workbench_text_only_v1');
  const forged = new ExperimentalRuntimeApi({ enabled: true, textAdapterFactory: () => {
    throw new RuntimeAdapterError('PRIVATE TOKEN', { code: 'unsupported_capability',
      details: { profile: 'workbench_text_only_v1', secret: 'PRIVATE' } });
  } });
  const result = exchange(forged, 'POST', '/sessions', textBody('e1'), { finished: true });
  await result.handled; assert.equal(result.res.statusCode, 501);
  assert.doesNotMatch(JSON.stringify(result.res.body), /PRIVATE|TOKEN/);
  assert.equal(result.res.body.error.details, undefined);
});
