import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';

const [candidateArgument, outputArgument] = process.argv.slice(2);
assert.ok(candidateArgument && outputArgument, 'candidate and output are required');
const candidate = fs.realpathSync.native(candidateArgument);
const output = path.resolve(outputArgument);
const sha = (file) => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const brokerFile = path.join(candidate, 'tools/mda2_windows_queue/broker.mjs');
const httpFile = path.join(candidate, 'tools/mda2_windows_collector/http_transport.mjs');
const inputs = { broker: sha(brokerFile), http: sha(httpFile), harness: sha(new URL(import.meta.url)) };
const { WindowsQueueBroker, BOUNDED_ASYNC_TRANSPORT_V1 } = await import(pathToFileURL(brokerFile));
const { createLoopbackActivityTransport, createLoopbackTestAuthority } = await import(pathToFileURL(httpFile));
const evidence = [];
const brokers = [];
const clock = () => ({ sample: async () => ({ age: 1, wall: 1 }), close: async () => {} });
const broker = (options = {}) => {
  const instance = new WindowsQueueBroker({ clock: clock(), maintenanceMs: 2147483647,
    transportExitTimeoutMs: 20, ...options });
  brokers.push(instance); return instance;
};
const owner = { owner: 'unit-owner', lineage: 'unit-lineage', binding: {} };
const attempt = { id: 'unit-attempt', sequence: 1, fence: 1 };
async function scenario(name, run) {
  const details = await run();
  evidence.push({ name, passed: true, ...details });
  process.stdout.write(`PASS ${name}\n`);
}

try {
  await scenario('invalid_async_contract_rejected_before_start', async () => {
    let starts = 0;
    assert.throws(() => broker({ transport: () => { starts++; } }), /transport_contract_rejected/);
    for (const missing of ['cancel', 'exited']) {
      const transport = { kind: BOUNDED_ASYNC_TRANSPORT_V1, prepare() {
        const handle = { start() { starts++; return true; }, cancel() { return true; },
          completion: new Promise(() => {}), exited: new Promise(() => {}) };
        delete handle[missing]; return handle;
      } };
      const b = broker({ transport });
      try {
        assert.throws(() => b.authorityCall(owner, 'deliver', { attempt, bytes: Buffer.from('unit').toString('base64') }),
          /transport_exit_handle_required/);
        assert.equal(b.dispatches.size, 0);
      } finally { await b.close(); }
    }
    assert.equal(starts, 0); return { starts, realOutletCreated: false };
  });

  for (const invalid of ['rejected', 'malformed']) {
    await scenario(`${invalid}_exit_proof_cannot_close_broker`, async () => {
      const b = broker();
      const handle = { start: () => true, cancel: () => true, completion: new Promise(() => {}),
        exited: invalid === 'rejected' ? Promise.reject(new Error('no_exit_proof')) : Promise.resolve({ closed: false }) };
      const ack = b.trackAsyncDispatch(owner, attempt, Buffer.from('unit'), handle, 1000);
      const record = b.dispatches.get(ack.dispatchId);
      const outcome = await record.settlement;
      assert.equal(outcome.code, 'transport_exit_unconfirmed');
      assert.equal(record.transportExited, false);
      await assert.rejects(b.close(), /transport_exit_unconfirmed/);
      return { reportedExited: record.transportExited, closeRejected: true, realOutletCreated: false };
    });
  }

  await scenario('completed_failure_keeps_unclosed_outlet_live', async () => {
    const b = broker(); let exit;
    const exited = new Promise((resolve) => { exit = resolve; });
    const handle = { start: () => true, cancel: () => true, completion: Promise.reject(new Error('synthetic_failure')), exited };
    const ack = b.trackAsyncDispatch(owner, attempt, Buffer.from('unit'), handle, 1000);
    const record = b.dispatches.get(ack.dispatchId);
    await assert.rejects(b.close(), /transport_exit_unconfirmed/);
    assert.notEqual(record.status, 'complete'); assert.equal(record.transportExited, false);
    exit({ closed: true }); await record.actualExit; await record.settlement;
    await b.close();
    return { closeBeforeExitRejected: true, closeAfterExitAccepted: true, realOutletCreated: false };
  });

  await scenario('http_write_failure_waits_for_actual_request_close', async () => {
    const server = http.createServer((_request, response) => response.end('{}'));
    const sockets = new Set();
    server.on('connection', (socket) => { sockets.add(socket); socket.on('close', () => sockets.delete(socket)); });
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const original = http.request; let request, closed = false, closePromise;
    try {
      const port = server.address().port; assert.notEqual(port, 47841);
      http.request = (...args) => {
        request = original(...args);
        closePromise = new Promise((resolve) => request.once('close', () => { closed = true; resolve(); }));
        request.write = () => { throw new Error('synthetic_write_throw'); }; return request;
      };
      const transport = createLoopbackActivityTransport({ baseUrl: `http://127.0.0.1:${port}`,
        probeToken: 'synthetic-local-test-token', testAuthority: createLoopbackTestAuthority(), timeoutMs: 1000 });
      const binding = { device_id: 'unit', probe_id: 'unit', source: 'windows_wts', event_id_prefix: 'unitprefix' };
      const handle = transport.prepare(binding);
      const completion = handle.completion.catch((error) => error.message);
      assert.throws(() => handle.start(Buffer.from(JSON.stringify({ ...binding, event_id: 'unitprefix.1', origin_sequence: 1 }))),
        /synthetic_write_throw/);
      assert.deepEqual(await handle.exited, { closed: true });
      assert.equal(await completion, 'synthetic_write_throw');
      assert.equal(closed, true); assert.equal(request.destroyed, true);
      return { actualRequestClosedAtReceipt: closed, loopbackOnly: true };
    } finally {
      http.request = original;
      if (request) { request.destroy(); await closePromise; }
      for (const socket of sockets) socket.destroy();
      await new Promise((resolve) => server.close(resolve));
    }
  });
  assert.equal(sha(brokerFile), inputs.broker); assert.equal(sha(httpFile), inputs.http);
  fs.writeFileSync(output, JSON.stringify({ passed: evidence.length, failed: 0, inputs, evidence,
    realOsCollection: false, productionEndpointUsed: false }, null, 2) + '\n');
} catch (error) {
  fs.writeFileSync(output, JSON.stringify({ passed: evidence.length, failed: 1, inputs, evidence, error: error.message }, null, 2) + '\n');
  throw error;
} finally {
  await Promise.allSettled(brokers.map((instance) => instance.close()));
}
