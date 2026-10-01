import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { createServer, request } from 'node:http';
import test from 'node:test';
import { createBridgeRuntimeShutdown, registerBridgeShutdownSignals } from './bridge_runtime_shutdown.mjs';

const deferred = () => { let resolve; let reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; };
const tick = () => new Promise(resolve => setImmediate(resolve));

test('shutdown fences new work immediately and waits for runtime ownership before closing HTTP', async () => {
  const gate = deferred(); const calls = [];
  const owner = createBridgeRuntimeShutdown({
    runtimeApi: { stop: options => { calls.push(['runtime', options]); return gate.promise; } },
    server: { close: callback => { calls.push(['http']); callback(); } },
  });
  const first = owner.shutdown();
  assert.equal(owner.isStopping, true);
  assert.strictEqual(owner.shutdown(), first);
  await tick();
  assert.deepEqual(calls, [['runtime', { permanent: true }]]);
  gate.resolve();
  assert.deepEqual(await first, { status: 'closed', runtime_closed: true, http_server_closed: true });
  assert.deepEqual(calls, [['runtime', { permanent: true }], ['http']]);
  assert.strictEqual(owner.shutdown(), first);
});

test('unconfirmed runtime cleanup keeps HTTP alive and retries the same runtime API', async () => {
  let attempts = 0; let httpCloses = 0;
  const runtimeApi = { async stop() { if (++attempts === 1) throw new Error('private-native-detail'); } };
  const owner = createBridgeRuntimeShutdown({ runtimeApi, server: { close: callback => { httpCloses++; callback(); } } });
  await assert.rejects(owner.shutdown());
  assert.equal(owner.isStopping, true);
  assert.equal(httpCloses, 0);
  assert.equal((await owner.shutdown()).status, 'closed');
  assert.equal(attempts, 2);
  assert.equal(httpCloses, 1);
});

test('failed listener close never becomes a successful shutdown summary', async () => {
  const owner = createBridgeRuntimeShutdown({ runtimeApi: { async stop() {} },
    server: { close: callback => callback(new Error('private-server-detail')) } });
  await assert.rejects(owner.shutdown(), error => error.code === 'bridge_http_close_unconfirmed'
    && !error.message.includes('private'));
});

test('an unfinished real HTTP response is closed only after runtime cleanup finishes', async t => {
  const gate = deferred(); let requestSeen;
  const seen = new Promise(resolve => { requestSeen = resolve; });
  const server = createServer((_req, res) => { requestSeen(); res.writeHead(200); res.write('started'); });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const req = request({ hostname: '127.0.0.1', port: server.address().port, path: '/', agent: false });
  req.on('error', () => {});
  req.on('response', res => { res.on('error', () => {}); res.resume(); });
  req.end();
  t.after(() => { req.destroy(); server.closeAllConnections(); if (server.listening) server.close(); });
  await seen;
  const owner = createBridgeRuntimeShutdown({ runtimeApi: { stop: () => gate.promise }, server, httpGraceMs: 20 });
  const closing = owner.shutdown();
  await tick();
  assert.equal(server.listening, true);
  gate.resolve();
  assert.equal((await closing).http_server_closed, true);
  assert.equal(server.listening, false);
});

test('signals share the graceful attempt and do not call exit-success on unknown cleanup', async () => {
  const emitter = new EventEmitter(); const gate = deferred(); let calls = 0; let closed = 0; let unknown = 0;
  const remove = registerBridgeShutdownSignals({ emitter, shutdown: () => { calls++; return gate.promise; },
    onClosed: () => { closed++; }, onUnconfirmed: () => { unknown++; } });
  emitter.emit('SIGINT'); emitter.emit('SIGTERM');
  gate.reject(new Error('unknown'));
  await tick();
  assert.equal(calls, 2); assert.equal(closed, 0); assert.equal(unknown, 1);
  remove();
  assert.equal(emitter.listenerCount('SIGINT'), 0);
  assert.equal(emitter.listenerCount('SIGTERM'), 0);
});
