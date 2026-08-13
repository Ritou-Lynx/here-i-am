import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createICoreServer } from './i_core_server.mjs';

async function startCore(t, directory, {
  cleanup = true,
  companionReplyJobsEnabled = false,
} = {}) {
  const core = createICoreServer({
    databasePath: path.join(directory, 'core.sqlite'),
    pairingCode: '654321',
    workerSecret: 'worker-secret',
    companionReplyJobsEnabled,
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

async function workerRequest(baseUrl, pathName, { method = 'POST', body, token = 'worker-secret' } = {}) {
  return jsonRequest(`${baseUrl}/v1/core${pathName}`, {
    method,
    token,
    body,
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

test('worker lease has single holder, renews and releases', async (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), 'i-core-lease-'));
  const { baseUrl } = await startCore(t, directory);
  const acquired = await workerRequest(baseUrl, '/workers/leases', {
    body: { workload: 'dreaming', holder_id: 'worker-a', ttl_ms: 30_000 },
  });
  assert.equal(acquired.status, 200);
  assert.equal(acquired.body.fencing_token, 1);
  assert.ok(acquired.body.lease_token);

  const blocked = await workerRequest(baseUrl, '/workers/leases', {
    body: { workload: 'dreaming', holder_id: 'worker-b' },
  });
  assert.equal(blocked.status, 409);
  assert.equal(blocked.body.error.code, 'lease_held');
  assert.equal(blocked.body.error.retryable, true);

  const renewed = await workerRequest(baseUrl, '/workers/leases/renew', {
    body: {
      workload: 'dreaming',
      holder_id: 'worker-a',
      lease_token: acquired.body.lease_token,
      fencing_token: acquired.body.fencing_token,
      ttl_ms: 60_000,
    },
  });
  assert.equal(renewed.status, 200);
  assert.equal(renewed.body.fencing_token, 1);

  const released = await workerRequest(baseUrl, '/workers/leases/release', {
    body: {
      workload: 'dreaming',
      holder_id: 'worker-a',
      lease_token: acquired.body.lease_token,
      fencing_token: acquired.body.fencing_token,
    },
  });
  assert.equal(released.status, 200);

  const takeover = await workerRequest(baseUrl, '/workers/leases', {
    body: { workload: 'dreaming', holder_id: 'worker-b' },
  });
  assert.equal(takeover.status, 200);
  assert.equal(takeover.body.fencing_token, 2);
});

test('expired lease can be taken over and stale holder is fenced', async (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), 'i-core-lease-expiry-'));
  const { core, baseUrl } = await startCore(t, directory);
  const first = core.store.acquireWorkerLease({
    workload: 'checkin',
    holder_id: 'worker-a',
    ttl_ms: 5_000,
  }, 1_000);
  const second = core.store.acquireWorkerLease({
    workload: 'checkin',
    holder_id: 'worker-b',
    ttl_ms: 5_000,
  }, 6_001);
  assert.equal(second.fencing_token, 2);
  assert.throws(
    () => core.store.renewWorkerLease({
      workload: 'checkin',
      holder_id: 'worker-a',
      lease_token: first.lease_token,
      fencing_token: first.fencing_token,
    }, 6_002),
    (error) => error.code === 'stale_lease',
  );

  const unauthorized = await workerRequest(baseUrl, '/workers/leases', {
    method: 'GET',
    token: 'device-or-wrong-secret',
  });
  assert.equal(unauthorized.status, 401);
  assert.equal(unauthorized.body.error.code, 'worker_unauthorized');
});

test('worker lease survives service restart', async (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), 'i-core-lease-restart-'));
  const first = await startCore(t, directory, { cleanup: false });
  const acquired = await workerRequest(first.baseUrl, '/workers/leases', {
    body: { workload: 'memory_v3', holder_id: 'worker-a', ttl_ms: 300_000 },
  });
  await first.core.close();

  const restarted = createICoreServer({
    databasePath: path.join(directory, 'core.sqlite'),
    pairingCode: 'new-code',
    workerSecret: 'worker-secret',
  });
  const address = await restarted.listen({ port: 0 });
  t.after(async () => {
    await restarted.close();
    rmSync(directory, { recursive: true, force: true });
  });
  const baseUrl = `http://127.0.0.1:${address.port}`;
  const leases = await workerRequest(baseUrl, '/workers/leases', { method: 'GET' });
  assert.equal(leases.status, 200);
  assert.equal(leases.body.leases[0].holder_id, 'worker-a');
  assert.equal(leases.body.leases[0].fencing_token, acquired.body.fencing_token);
  assert.equal(leases.body.leases[0].active, true);
});

test('only the active companion lease can publish companion messages', async (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), 'i-core-companion-publish-'));
  const { baseUrl } = await startCore(t, directory);
  const lease = await workerRequest(baseUrl, '/workers/leases', {
    body: { workload: 'companion_reply', holder_id: 'companion-worker' },
  });
  const companionMessage = {
    sync_id: 'companion-reply-1',
    origin_device_id: 'companion-worker',
    origin_sequence: 1,
    character_id: 'i',
    sender: 'companion',
    content: '欢迎回来。',
    created_at_ms: 1786550401000,
    message_type: 'chat',
    asset_refs: [],
    addenda: [],
  };
  const published = await workerRequest(baseUrl, '/workers/chat/messages', {
    body: {
      workload: 'companion_reply',
      holder_id: 'companion-worker',
      lease_token: lease.body.lease_token,
      fencing_token: lease.body.fencing_token,
      messages: [companionMessage],
    },
  });
  assert.equal(published.status, 200);
  assert.equal(published.body.results[0].status, 'accepted');

  const duplicate = await workerRequest(baseUrl, '/workers/chat/messages', {
    body: {
      workload: 'companion_reply',
      holder_id: 'companion-worker',
      lease_token: lease.body.lease_token,
      fencing_token: lease.body.fencing_token,
      messages: [companionMessage],
    },
  });
  assert.equal(duplicate.status, 200);
  assert.equal(duplicate.body.results[0].status, 'duplicate');

  await workerRequest(baseUrl, '/workers/leases/release', {
    body: {
      workload: 'companion_reply',
      holder_id: 'companion-worker',
      lease_token: lease.body.lease_token,
      fencing_token: lease.body.fencing_token,
    },
  });
  const stale = await workerRequest(baseUrl, '/workers/chat/messages', {
    body: {
      workload: 'companion_reply',
      holder_id: 'companion-worker',
      lease_token: lease.body.lease_token,
      fencing_token: lease.body.fencing_token,
      messages: [{ ...companionMessage, sync_id: 'too-late', origin_sequence: 2 }],
    },
  });
  assert.equal(stale.status, 409);
  assert.equal(stale.body.error.code, 'lease_expired');
});

test('non-companion workload cannot publish and remote device remains user-only', async (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), 'i-core-publish-boundary-'));
  const { baseUrl } = await startCore(t, directory);
  const lease = await workerRequest(baseUrl, '/workers/leases', {
    body: { workload: 'dreaming', holder_id: 'dream-worker' },
  });
  const rejected = await workerRequest(baseUrl, '/workers/chat/messages', {
    body: {
      workload: 'dreaming',
      holder_id: 'dream-worker',
      lease_token: lease.body.lease_token,
      fencing_token: lease.body.fencing_token,
      messages: [],
    },
  });
  assert.equal(rejected.status, 403);
  assert.equal(rejected.body.error.code, 'wrong_workload');

  const phone = await pair(baseUrl, 'phone-a');
  const companion = message('phone-a', 'remote-companion', 1);
  companion.sender = 'companion';
  const remoteRejected = await jsonRequest(`${baseUrl}/v1/core/chat/messages`, {
    method: 'POST',
    token: phone.body.device_token,
    body: { device_id: 'phone-a', messages: [companion] },
  });
  assert.equal(remoteRejected.status, 403);
  assert.equal(remoteRejected.body.error.code, 'sender_not_allowed');
});

test('companion reply jobs are dark until explicitly enabled', async (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), 'i-core-reply-jobs-dark-'));
  const { core, baseUrl } = await startCore(t, directory);
  const phone = await pair(baseUrl, 'phone-a');
  await jsonRequest(`${baseUrl}/v1/core/chat/messages`, {
    method: 'POST',
    token: phone.body.device_token,
    body: {
      device_id: 'phone-a',
      messages: [message('phone-a', 'dark-trigger', 1)],
    },
  });
  assert.equal(
    core.store.db.prepare('SELECT COUNT(*) AS count FROM companion_reply_jobs').get().count,
    0,
  );
  const lease = await workerRequest(baseUrl, '/workers/leases', {
    body: { workload: 'companion_reply', holder_id: 'companion-worker' },
  });
  const disabled = await workerRequest(baseUrl, '/workers/companion-replies/claim', {
    body: {
      workload: 'companion_reply',
      holder_id: 'companion-worker',
      lease_token: lease.body.lease_token,
      fencing_token: lease.body.fencing_token,
    },
  });
  assert.equal(disabled.status, 503);
  assert.equal(disabled.body.error.code, 'feature_disabled');
  const refusedCutover = await jsonRequest(`${baseUrl}/v1/core/chat/messages`, {
    method: 'POST',
    token: phone.body.device_token,
    body: {
      device_id: 'phone-a',
      request_companion_reply: true,
      messages: [message('phone-a', 'not-queued', 2)],
    },
  });
  assert.equal(refusedCutover.status, 503);
  assert.equal(refusedCutover.body.error.retryable, true);
});

test('enabled companion reply jobs coalesce pending turns and complete idempotently', async (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), 'i-core-reply-jobs-'));
  const { core, baseUrl } = await startCore(t, directory, {
    companionReplyJobsEnabled: true,
  });
  const health = await jsonRequest(`${baseUrl}/v1/core/health`, { protocol: false });
  assert.ok(health.body.features.includes('companion_reply_jobs'));
  const phone = await pair(baseUrl, 'phone-a');
  await jsonRequest(`${baseUrl}/v1/core/chat/messages`, {
    method: 'POST',
    token: phone.body.device_token,
    body: {
      device_id: 'phone-a',
      request_companion_reply: true,
      messages: [
        message('phone-a', 'trigger-1', 1, '前一句'),
        message('phone-a', 'trigger-2', 2, '我到家了'),
      ],
    },
  });
  assert.equal(
    core.store.db.prepare('SELECT COUNT(*) AS count FROM companion_reply_jobs').get().count,
    2,
  );
  assert.equal(
    core.store.db.prepare("SELECT COUNT(*) AS count FROM companion_reply_jobs WHERE status = 'pending'").get().count,
    1,
  );
  const lease = await workerRequest(baseUrl, '/workers/leases', {
    body: { workload: 'companion_reply', holder_id: 'companion-worker' },
  });
  const leaseBody = {
    workload: 'companion_reply',
    holder_id: 'companion-worker',
    lease_token: lease.body.lease_token,
    fencing_token: lease.body.fencing_token,
  };
  const firstClaim = await workerRequest(baseUrl, '/workers/companion-replies/claim', {
    body: leaseBody,
  });
  assert.equal(firstClaim.status, 200);
  assert.equal(firstClaim.body.job.trigger_sync_id, 'trigger-2');
  assert.equal(firstClaim.body.job.context.length, 2);
  const sameClaim = await workerRequest(baseUrl, '/workers/companion-replies/claim', {
    body: leaseBody,
  });
  assert.equal(sameClaim.body.job.job_id, firstClaim.body.job.job_id);

  const completed = await workerRequest(baseUrl, '/workers/companion-replies/complete', {
    body: {
      ...leaseBody,
      job_id: firstClaim.body.job.job_id,
      content: '欢迎回来。',
      created_at_ms: 1786550401000,
    },
  });
  assert.equal(completed.status, 200);
  assert.equal(completed.body.publication_status, 'accepted');
  const duplicate = await workerRequest(baseUrl, '/workers/companion-replies/complete', {
    body: {
      ...leaseBody,
      job_id: firstClaim.body.job.job_id,
      content: '欢迎回来。',
      created_at_ms: 1786550401000,
    },
  });
  assert.equal(duplicate.status, 200);
  assert.equal(duplicate.body.publication_status, 'duplicate');

  const nextClaim = await workerRequest(baseUrl, '/workers/companion-replies/claim', {
    body: leaseBody,
  });
  assert.equal(nextClaim.body.job, null);
  assert.equal(
    core.store.db.prepare("SELECT COUNT(*) AS count FROM chat_messages WHERE sender = 'companion'").get().count,
    1,
  );
});

test('new lease fences a stale companion reply job claim', async (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), 'i-core-reply-job-fence-'));
  const { core, baseUrl } = await startCore(t, directory, {
    companionReplyJobsEnabled: true,
  });
  const phone = await pair(baseUrl, 'phone-a');
  await jsonRequest(`${baseUrl}/v1/core/chat/messages`, {
    method: 'POST',
    token: phone.body.device_token,
    body: {
      device_id: 'phone-a',
      request_companion_reply: true,
      messages: [message('phone-a', 'fenced-trigger', 1)],
    },
  });
  const first = core.store.acquireWorkerLease({
    workload: 'companion_reply', holder_id: 'worker-a', ttl_ms: 5_000,
  }, 1_000);
  const firstClaim = core.store.claimCompanionReplyJob({
    workload: 'companion_reply',
    holder_id: 'worker-a',
    lease_token: first.lease_token,
    fencing_token: first.fencing_token,
  }, 1_001);
  const second = core.store.acquireWorkerLease({
    workload: 'companion_reply', holder_id: 'worker-b', ttl_ms: 5_000,
  }, 6_001);
  const secondClaim = core.store.claimCompanionReplyJob({
    workload: 'companion_reply',
    holder_id: 'worker-b',
    lease_token: second.lease_token,
    fencing_token: second.fencing_token,
  }, 6_002);
  assert.equal(secondClaim.job.job_id, firstClaim.job.job_id);
  assert.throws(
    () => core.store.completeCompanionReplyJob({
      workload: 'companion_reply',
      holder_id: 'worker-a',
      lease_token: first.lease_token,
      fencing_token: first.fencing_token,
      job_id: firstClaim.job.job_id,
      content: '迟到回复',
    }, 6_003),
    (error) => error.code === 'stale_lease',
  );
});

test('a newer user message supersedes an in-flight reply job', async (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), 'i-core-reply-job-followup-'));
  const { core, baseUrl } = await startCore(t, directory, {
    companionReplyJobsEnabled: true,
  });
  const phone = await pair(baseUrl, 'phone-a');
  const submit = (item) => jsonRequest(`${baseUrl}/v1/core/chat/messages`, {
    method: 'POST',
    token: phone.body.device_token,
    body: {
      device_id: 'phone-a',
      request_companion_reply: true,
      messages: [item],
    },
  });
  await submit(message('phone-a', 'first-trigger', 1, '我到家了'));
  const lease = await workerRequest(baseUrl, '/workers/leases', {
    body: { workload: 'companion_reply', holder_id: 'companion-worker' },
  });
  const leaseBody = {
    workload: 'companion_reply',
    holder_id: 'companion-worker',
    lease_token: lease.body.lease_token,
    fencing_token: lease.body.fencing_token,
  };
  const firstClaim = await workerRequest(baseUrl, '/workers/companion-replies/claim', {
    body: leaseBody,
  });
  await submit(message('phone-a', 'followup-trigger', 2, '而且今天有点累'));
  const staleCompletion = await workerRequest(baseUrl, '/workers/companion-replies/complete', {
    body: {
      ...leaseBody,
      job_id: firstClaim.body.job.job_id,
      content: '这条已经过时',
    },
  });
  assert.equal(staleCompletion.status, 409);
  assert.equal(staleCompletion.body.error.code, 'stale_job_claim');
  const latestClaim = await workerRequest(baseUrl, '/workers/companion-replies/claim', {
    body: leaseBody,
  });
  assert.equal(latestClaim.body.job.trigger_sync_id, 'followup-trigger');
  assert.deepEqual(
    latestClaim.body.job.context.map((item) => item.content),
    ['我到家了', '而且今天有点累'],
  );
  assert.equal(
    core.store.db.prepare("SELECT COUNT(*) AS count FROM chat_messages WHERE sender = 'companion'").get().count,
    0,
  );
});
