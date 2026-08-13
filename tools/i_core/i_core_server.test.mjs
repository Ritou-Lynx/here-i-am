import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createICoreServer } from './i_core_server.mjs';

async function startCore(t, directory, { cleanup = true } = {}) {
  const core = createICoreServer({
    databasePath: path.join(directory, 'core.sqlite'),
    pairingCode: '654321',
  });
  const address = await core.listen({ port: 0 });
  t.after(async () => {
    await core.close();
    if (cleanup) rmSync(directory, { recursive: true, force: true });
  });
  return { core, baseUrl: `http://127.0.0.1:${address.port}` };
}

async function jsonRequest(url, { method = 'GET', token, body, protocol = true } = {}) {
  const response = await fetch(url, {
    method,
    headers: {
      ...(protocol ? { 'x-core-protocol': '0.1' } : {}),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  return { status: response.status, body: await response.json() };
}

async function pair(baseUrl, deviceId, pairingCode = '654321') {
  return jsonRequest(`${baseUrl}/v1/core/devices/pair`, {
    method: 'POST',
    protocol: false,
    body: {
      device_id: deviceId,
      display_name: deviceId,
      platform: 'test',
      client_version: '0.1',
      pairing_code: pairingCode,
      capabilities: ['chat'],
    },
  });
}

function message(deviceId, syncId, originSequence, content = '我到家了') {
  return {
    sync_id: syncId,
    origin_device_id: deviceId,
    origin_sequence: originSequence,
    character_id: 'lin-ai',
    sender: 'user',
    content,
    created_at_ms: 1786550400000,
    message_type: 'chat',
    asset_refs: [],
    addenda: [],
  };
}

test('health identifies a stable authority node', async (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), 'i-core-health-'));
  const { baseUrl } = await startCore(t, directory);
  const result = await jsonRequest(`${baseUrl}/v1/core/health`, { protocol: false });
  assert.equal(result.status, 200);
  assert.equal(result.body.role, 'authority');
  assert.equal(result.body.protocol_version, '0.1');
  assert.ok(result.body.node_id);
});

test('pairing code remains single-use after restart', async (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), 'i-core-sync-'));
  const first = await startCore(t, directory, { cleanup: false });
  const { baseUrl } = first;
  const phone = await pair(baseUrl, 'phone-a');
  assert.equal(phone.status, 200);
  const secondUse = await pair(baseUrl, 'unexpected-device');
  assert.equal(secondUse.status, 401);
  await first.core.close();

  const restarted = createICoreServer({
    databasePath: path.join(directory, 'core.sqlite'),
    pairingCode: '654321',
  });
  const address = await restarted.listen({ port: 0 });
  t.after(async () => {
    await restarted.close();
    rmSync(directory, { recursive: true, force: true });
  });
  const afterRestart = await pair(`http://127.0.0.1:${address.port}`, 'unexpected-device');
  assert.equal(afterRestart.status, 401);
  assert.throws(
    () => restarted.replacePairingCode('654321'),
    /already been consumed/,
  );
  restarted.replacePairingCode('987654');
  const secondPairing = await pair(
    `http://127.0.0.1:${address.port}`,
    'phone-b',
    '987654',
  );
  assert.equal(secondPairing.status, 200);
  assert.throws(
    () => restarted.replacePairingCode('654321'),
    /already been consumed/,
  );
  assert.throws(
    () => restarted.replacePairingCode('987654'),
    /already been consumed/,
  );
});

test('two devices share one idempotent change feed', async (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), 'i-core-sync-'));
  const { core, baseUrl } = await startCore(t, directory);
  const phone = await pair(baseUrl, 'phone-a');
  core.replacePairingCode('987654');
  const desktop = await pair(baseUrl, 'desktop-b', '987654');
  assert.equal(phone.status, 200);
  assert.equal(desktop.status, 200);

  const submitBody = {
    device_id: 'phone-a',
    messages: [message('phone-a', 'message-1', 1)],
  };
  const accepted = await jsonRequest(`${baseUrl}/v1/core/chat/messages`, {
    method: 'POST',
    token: phone.body.device_token,
    body: submitBody,
  });
  const duplicate = await jsonRequest(`${baseUrl}/v1/core/chat/messages`, {
    method: 'POST',
    token: phone.body.device_token,
    body: submitBody,
  });
  assert.equal(accepted.body.results[0].status, 'accepted');
  assert.equal(duplicate.body.results[0].status, 'duplicate');
  assert.equal(accepted.body.next_cursor, undefined);
  assert.equal(
    accepted.body.results[0].server_sequence,
    duplicate.body.results[0].server_sequence,
  );

  const changes = await jsonRequest(
    `${baseUrl}/v1/core/changes?cursor=${encodeURIComponent(desktop.body.initial_cursor)}`,
    { token: desktop.body.device_token },
  );
  assert.equal(changes.status, 200);
  assert.equal(changes.body.events.length, 1);
  assert.equal(changes.body.events[0].payload.content, '我到家了');

  const ack = await jsonRequest(`${baseUrl}/v1/core/devices/ack`, {
    method: 'POST',
    token: desktop.body.device_token,
    body: { device_id: 'desktop-b', cursor: changes.body.next_cursor },
  });
  assert.equal(ack.status, 200);
  assert.equal(ack.body.cursor, changes.body.next_cursor);
});

test('conflicts are rejected without adding a second change', async (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), 'i-core-conflict-'));
  const { baseUrl } = await startCore(t, directory);
  const phone = await pair(baseUrl, 'phone-a');
  const token = phone.body.device_token;
  const initialCursor = phone.body.initial_cursor;
  const first = { device_id: 'phone-a', messages: [message('phone-a', 'same-id', 1)] };
  const conflict = {
    device_id: 'phone-a',
    messages: [message('phone-a', 'same-id', 1, 'different content')],
  };
  assert.equal((await jsonRequest(`${baseUrl}/v1/core/chat/messages`, {
    method: 'POST', token, body: first,
  })).status, 200);
  const rejected = await jsonRequest(`${baseUrl}/v1/core/chat/messages`, {
    method: 'POST', token, body: conflict,
  });
  assert.equal(rejected.status, 409);
  assert.equal(rejected.body.error.code, 'immutable_message_conflict');
  const changes = await jsonRequest(
    `${baseUrl}/v1/core/changes?cursor=${encodeURIComponent(initialCursor)}`,
    { token },
  );
  assert.equal(changes.body.events.length, 1);
});

test('device identity, sender and protocol boundaries are enforced', async (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), 'i-core-auth-'));
  const { baseUrl } = await startCore(t, directory);
  const phone = await pair(baseUrl, 'phone-a');
  const token = phone.body.device_token;
  const foreign = await jsonRequest(`${baseUrl}/v1/core/chat/messages`, {
    method: 'POST',
    token,
    body: { device_id: 'phone-a', messages: [message('phone-b', 'foreign', 1)] },
  });
  assert.equal(foreign.status, 403);
  assert.equal(foreign.body.error.code, 'origin_device_mismatch');

  const companion = message('phone-a', 'companion', 2);
  companion.sender = 'companion';
  const forbiddenSender = await jsonRequest(`${baseUrl}/v1/core/chat/messages`, {
    method: 'POST', token, body: { device_id: 'phone-a', messages: [companion] },
  });
  assert.equal(forbiddenSender.status, 403);
  assert.equal(forbiddenSender.body.error.code, 'sender_not_allowed');

  const missingProtocol = await jsonRequest(`${baseUrl}/v1/core/changes`, {
    token,
    protocol: false,
  });
  assert.equal(missingProtocol.status, 426);
});

test('change feed and node identity survive service restart', async (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), 'i-core-restart-'));
  const first = await startCore(t, directory, { cleanup: false });
  const phone = await pair(first.baseUrl, 'phone-a');
  const token = phone.body.device_token;
  const initialCursor = phone.body.initial_cursor;
  const nodeId = first.core.store.nodeId;
  await jsonRequest(`${first.baseUrl}/v1/core/chat/messages`, {
    method: 'POST',
    token,
    body: { device_id: 'phone-a', messages: [message('phone-a', 'persisted', 1)] },
  });
  await first.core.close();

  const secondCore = createICoreServer({
    databasePath: path.join(directory, 'core.sqlite'),
    pairingCode: '654321',
  });
  const address = await secondCore.listen({ port: 0 });
  t.after(async () => {
    await secondCore.close();
    rmSync(directory, { recursive: true, force: true });
  });
  const baseUrl = `http://127.0.0.1:${address.port}`;
  assert.equal(secondCore.store.nodeId, nodeId);
  const changes = await jsonRequest(
    `${baseUrl}/v1/core/changes?cursor=${encodeURIComponent(initialCursor)}`,
    { token },
  );
  assert.equal(changes.status, 200);
  assert.equal(changes.body.events[0].entity_id, 'persisted');
});
