import assert from 'node:assert/strict';
import http from 'node:http';
import test from 'node:test';
import { createWorkbenchProductGatewayTransport, createWorkbenchProductGatewayTransportForTesting } from './workbench_product_gateway_transport.mjs';

const prefix = '/experimental/v1/runtime';

async function fixture(t, { deadlineMs = null } = {}) {
  const seen = [];
  const closed = new Map();
  const observeClose = (key, socket) => {
    let resolve;
    closed.set(key, new Promise(done => { resolve = done; }));
    socket.once('close', () => resolve());
  };
  const server = http.createServer((req, res) => {
    const chunks = [];
    req.on('data', part => chunks.push(part));
    req.on('end', () => {
      seen.push({ method: req.method, path: req.url, body: Buffer.concat(chunks).toString('utf8') });
      if (req.url === `${prefix}/sessions/bad/events?after=0`) {
        res.writeHead(200, { 'content-type': 'application/json' }); res.end(Buffer.from([0xc3])); return;
      }
      if (req.url === `${prefix}/sessions/socket/events?after=0`) { req.socket.destroy(); return; }
      if (req.url === `${prefix}/sessions/header/events?after=0`) {
        observeClose('header', req.socket); res.writeHead(200, { 'content-type': 'text/plain' }); res.write('held'); return;
      }
      if (req.url === `${prefix}/sessions/hanging/events?after=0`) {
        observeClose('hanging', req.socket); res.writeHead(200, { 'content-type': 'application/json' }); res.write('{'); return;
      }
      res.writeHead(200, { 'content-type': 'application/json; charset=utf-8' }); res.end('{"ok":true}');
    });
  });
  await new Promise(resolve => server.listen(0, HOST, resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const port = server.address().port;
  const requestImpl = (options, listener) => {
    assert.equal(options.hostname, HOST); assert.equal(options.port, 47831); assert.equal(options.protocol, 'http:');
    return http.request({ ...options, port }, listener);
  };
  const transport = deadlineMs === null
    ? createWorkbenchProductGatewayTransport({ requestImpl })
    : createWorkbenchProductGatewayTransportForTesting({ requestImpl, deadlineMs });
  return { transport, seen, closed };
}

const HOST = '127.0.0.1';

test('fixed factory permits only ordinary guardian paths over synthetic local HTTP', async t => {
  const { transport, seen } = await fixture(t);
  assert.deepEqual(await transport({ method: 'POST', path: `${prefix}/sessions`, body: { config: {} } }), { ok: true });
  assert.deepEqual(seen, [{ method: 'POST', path: `${prefix}/sessions`, body: '{"config":{}}' }]);
  await reject(() => transport({ method: 'POST', path: `${prefix}/sessions/resume`, body: {} }));
  await reject(() => transport({ method: 'POST', path: 'http://example.test/anything', body: {} }));
  await reject(() => transport({ method: 'GET', path: `${prefix}/sessions/one/events?after=0&after=0` }));
  await reject(() => transport({ method: 'POST', path: `${prefix}/sessions/../sessions`, body: {} }));
  assert.equal(seen.length, 1);
});

test('rejects invalid response bytes, socket errors, and oversized request before release', async t => {
  const { transport, seen } = await fixture(t);
  await reject(() => transport({ method: 'GET', path: `${prefix}/sessions/bad/events?after=0` }));
  await reject(() => transport({ method: 'GET', path: `${prefix}/sessions/socket/events?after=0` }));
  await reject(() => transport({ method: 'POST', path: `${prefix}/sessions`, body: { input: 'x'.repeat(1024 * 1024) } }));
  assert.equal(seen.length, 2);
});

test('malformed headers and hanging bodies close actual local sockets', async t => {
  const { transport, closed } = await fixture(t, { deadlineMs: 30 });
  await reject(() => transport({ method: 'GET', path: `${prefix}/sessions/header/events?after=0` }));
  await closesSoon(closed.get('header'));
  await reject(() => transport({ method: 'GET', path: `${prefix}/sessions/hanging/events?after=0` }));
  await closesSoon(closed.get('hanging'));
});

async function reject(operation) {
  await assert.rejects(operation, error => ['product_gateway_transport_rejected', 'product_gateway_transport_unavailable'].includes(error?.code));
}

async function closesSoon(promise) {
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('socket_not_closed')), 500);
    promise.then(() => { clearTimeout(timer); resolve(); }, error => { clearTimeout(timer); reject(error); });
  });
}
