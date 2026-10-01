import assert from 'node:assert/strict';
import test from 'node:test';
import { stopReceiptFixture } from './test_fixtures/stop_receipt_child.mjs';

test('stop timeout is unconfirmed until an actual late child close', async (t) => {
  const { child, client, send } = stopReceiptFixture(t);
  let stopped = 0;
  let notifications = 0;
  client.on('stopped', () => stopped++);
  client.on('notification', () => notifications++);
  await assert.rejects(client.stop(), (error) => {
    assert.equal(error.code, 'stop_close_unconfirmed');
    assert.equal(error.data.process_close_observed, false);
    assert.equal(error.data.kill_attempted, true);
    assert.equal(error.data.kill_returned, true);
    return true;
  });
  assert.equal(client.child, child);
  assert.equal(client.state, 'stop_unconfirmed');
  assert.equal(stopped, 0);
  assert.equal(child.listenerCount('close'), 1);
  child.emit('close', null, 'SIGTERM');
  assert.equal(client.state, 'stopped');
  assert.equal(client.child, null);
  assert.equal(stopped, 1);
  assert.equal((await client.stop()).process_close_observed, true);
  send({ method: 'turn/completed', params: { threadId: 'late', turn: { id: 'late', status: 'interrupted' } } });
  child.emit('close', null, 'SIGTERM');
  assert.equal(stopped, 1);
  assert.equal(notifications, 0);
});
