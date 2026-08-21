import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { Readable } from 'node:stream';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { CodexAppServerAdapter } from './codex_app_server_adapter.mjs';
import {
  EXPERIMENTAL_RUNTIME_PREFIX,
  MAX_EXPERIMENTAL_REQUEST_BYTES,
  ExperimentalRuntimeApi,
} from './experimental_runtime_api.mjs';

const fixturePath = fileURLToPath(
  new URL('./test_fixtures/fake_codex_app_server.mjs', import.meta.url),
);

function createAdapter({ clientEnv = process.env } = {}) {
  let nextSession = 1;
  return new CodexAppServerAdapter({
    clientOptions: {
      commandSpec: {
        command: process.execPath,
        args: [fixturePath],
        source: 'test-fixture',
      },
      requestTimeoutMs: 2_000,
      stopTimeoutMs: 500,
      env: clientEnv,
    },
    activityTimeoutMs: 1_000,
    sessionIdFactory: () => `http-session-${nextSession++}`,
  });
}

async function callApi(api, method, path, body = null) {
  const payload = Buffer.isBuffer(body)
    ? body
    : (body == null ? null : Buffer.from(JSON.stringify(body)));
  const req = Readable.from(payload == null ? [] : [payload]);
  req.method = method;
  req.socket = { remoteAddress: '127.0.0.1' };
  let status = null;
  let headers = null;
  let responseBody = '';
  const res = {
    writeHead(nextStatus, nextHeaders) {
      status = nextStatus;
      headers = nextHeaders;
    },
    end(chunk = '') {
      responseBody += chunk;
    },
  };
  const handled = await api.handle(
    req,
    res,
    new URL(path, 'http://127.0.0.1'),
  );
  return {
    handled,
    status,
    headers,
    body: responseBody ? JSON.parse(responseBody) : null,
  };
}

async function waitForApiEvent(api, sessionId, predicate) {
  const deadline = Date.now() + 2_000;
  while (Date.now() < deadline) {
    const response = await callApi(
      api,
      'GET',
      `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions/${sessionId}/events`,
    );
    const found = response.body.events.find(predicate);
    if (found) return found;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error('Timed out waiting for experimental API event.');
}

test('experimental local entry covers session, turn, control, events, approval, and resume', async (t) => {
  const adapter = createAdapter();
  const api = new ExperimentalRuntimeApi({
    enabled: true,
    adapterFactory: () => adapter,
  });
  t.after(() => api.stop());

  const started = await callApi(api, 'POST', `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions`, {
    config: { model: 'fake-model', ephemeral: true },
    context_manifest: { manifest_id: 'test-manifest' },
  });
  assert.equal(started.status, 200, JSON.stringify(started.body));
  assert.equal(started.headers['x-hereiam-experimental'], 'runtime-adapter-v1');
  const sessionId = started.body.session_id;

  const turn = await callApi(
    api,
    'POST',
    `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions/${sessionId}/turns`,
    { input: 'slow' },
  );
  const turnId = turn.body.turn_id;
  const steered = await callApi(
    api,
    'POST',
    `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions/${sessionId}/turns/${turnId}/steer`,
    { input: 'new direction' },
  );
  assert.equal(steered.body.activity_observed, true);

  await callApi(
    api,
    'POST',
    `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions/${sessionId}/turns/${turnId}/interrupt`,
    {},
  );
  const interrupted = await waitForApiEvent(
    api,
    sessionId,
    (event) => event.turn_id === turnId && event.status === 'interrupted',
  );
  assert.equal(interrupted.kind, 'turn_status');

  const approvalSession = await callApi(
    api,
    'POST',
    `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions`,
    { config: { model: 'fake-model' } },
  );
  const approvalSessionId = approvalSession.body.session_id;
  await callApi(
    api,
    'POST',
    `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions/${approvalSessionId}/turns`,
    { input: 'approval' },
  );
  const approval = await waitForApiEvent(
    api,
    approvalSessionId,
    (event) => event.kind === 'approval_request',
  );
  const answered = await callApi(
    api,
    'POST',
    `${EXPERIMENTAL_RUNTIME_PREFIX}/approvals/${approval.data.request_id}`,
    { decision: 'denied' },
  );
  assert.equal(answered.body.accepted, true);

  await callApi(
    api,
    'DELETE',
    `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions/${sessionId}`,
  );
  const resumed = await callApi(
    api,
    'POST',
    `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions/resume`,
    {
      provider_session_id: started.body.provider_metadata.provider_session_id,
      config: { model: 'fake-model' },
    },
  );
  assert.equal(resumed.status, 200);
  assert.notEqual(resumed.body.session_id, sessionId);
});

test('experimental entry relays dynamic tool calls without executing product tools', async (t) => {
  const adapter = createAdapter();
  const api = new ExperimentalRuntimeApi({
    enabled: true,
    adapterFactory: () => adapter,
  });
  t.after(() => api.stop());
  const session = await callApi(api, 'POST', `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions`, {
    config: {
      model: 'fake-model',
      dynamic_tools: [{
        name: 'whiteboard_read_selection',
        description: 'Read selected whiteboard items.',
        input_schema: {
          type: 'object',
          properties: {},
          additionalProperties: false,
        },
      }],
    },
  });
  await callApi(
    api,
    'POST',
    `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions/${session.body.session_id}/turns`,
    { input: 'dynamic-tool' },
  );
  const requested = await waitForApiEvent(
    api,
    session.body.session_id,
    (event) => event.kind === 'tool_call',
  );
  const answered = await callApi(
    api,
    'POST',
    `${EXPERIMENTAL_RUNTIME_PREFIX}/tool-calls/${requested.data.tool_call_id}`,
    {
      success: true,
      content_items: [{ type: 'text', text: '{"cards":2}' }],
    },
  );
  assert.equal(answered.status, 200);
  assert.equal(answered.body.accepted, true);
  const resolved = await waitForApiEvent(
    api,
    session.body.session_id,
    (event) => event.kind === 'tool_result',
  );
  assert.equal(resolved.data.success, true);

  const missing = await callApi(
    api,
    'POST',
    `${EXPERIMENTAL_RUNTIME_PREFIX}/tool-calls/missing-call`,
    { success: false, content_items: [{ type: 'text', text: 'missing' }] },
  );
  assert.equal(missing.status, 404);
  assert.equal(missing.body.error.code, 'tool_call_not_found');
});

test('experimental entry is disabled by default and reports normalized model errors', async (t) => {
  const disabled = new ExperimentalRuntimeApi({ enabled: false });
  const unavailable = await callApi(
    disabled,
    'GET',
    `${EXPERIMENTAL_RUNTIME_PREFIX}/capabilities`,
  );
  assert.equal(unavailable.status, 404);
  assert.equal(unavailable.body.error, 'experimental_runtime_disabled');

  const adapter = createAdapter();
  const enabled = new ExperimentalRuntimeApi({
    enabled: true,
    adapterFactory: () => adapter,
  });
  t.after(() => enabled.stop());
  const failed = await callApi(enabled, 'POST', `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions`, {
    config: { model: 'missing-model' },
  });
  assert.equal(failed.status, 422, JSON.stringify(failed.body));
  assert.equal(failed.body.error.code, 'model_unavailable');
  assert.deepEqual(failed.body.error.details.available_models, ['fake-model']);
});

test('experimental entry bounds JSON bodies and validates steering timeouts', async (t) => {
  const adapter = createAdapter();
  const api = new ExperimentalRuntimeApi({
    enabled: true,
    adapterFactory: () => adapter,
  });
  t.after(() => api.stop());

  const malformed = await callApi(
    api,
    'POST',
    `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions`,
    Buffer.from('{'),
  );
  assert.equal(malformed.status, 400);
  assert.equal(malformed.body.error.code, 'invalid_request');

  const oversized = await callApi(
    api,
    'POST',
    `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions`,
    Buffer.alloc(MAX_EXPERIMENTAL_REQUEST_BYTES + 1, 0x20),
  );
  assert.equal(oversized.status, 400);
  assert.equal(oversized.body.error.code, 'invalid_request');
  assert.equal(
    oversized.body.error.details.max_request_bytes,
    MAX_EXPERIMENTAL_REQUEST_BYTES,
  );

  const session = await callApi(api, 'POST', `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions`, {
    config: { model: 'fake-model' },
  });
  const turn = await callApi(
    api,
    'POST',
    `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions/${session.body.session_id}/turns`,
    { input: 'slow' },
  );
  for (const invalid of [-1, 0, 'Infinity']) {
    const response = await callApi(
      api,
      'POST',
      `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions/${session.body.session_id}/turns/${turn.body.turn_id}/steer`,
      { input: 'direction', activity_timeout_ms: invalid },
    );
    assert.equal(response.status, 400);
    assert.equal(response.body.error.code, 'invalid_request');
  }
  await callApi(
    api,
    'POST',
    `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions/${session.body.session_id}/turns/${turn.body.turn_id}/interrupt`,
    {},
  );
});

test('local cleanup endpoint waits for App Server stdin close and process exit', async (t) => {
  const tempRoot = mkdtempSync(path.join(tmpdir(), 'hereiam-app-server-stop-'));
  const markerPath = path.join(tempRoot, 'app-server-exit.txt');
  const adapter = createAdapter({
    clientEnv: { ...process.env, FAKE_CODEX_EXIT_MARKER: markerPath },
  });
  const api = new ExperimentalRuntimeApi({
    enabled: true,
    adapterFactory: () => adapter,
  });
  t.after(async () => {
    await api.stop();
    rmSync(tempRoot, { recursive: true, force: true });
  });

  await callApi(api, 'POST', `${EXPERIMENTAL_RUNTIME_PREFIX}/sessions`, {
    config: { model: 'fake-model' },
  });
  const stopped = await callApi(
    api,
    'POST',
    `${EXPERIMENTAL_RUNTIME_PREFIX}/host/stop-app-server`,
    {},
  );
  assert.equal(stopped.status, 200);
  assert.equal(stopped.body.stopped, true);
  assert.equal(api.adapter, null);
  assert.equal(existsSync(markerPath), true);
  const marker = readFileSync(markerPath, 'utf8');
  assert.match(marker, /stdin_closed/);
  assert.match(marker, /process_exit/);
});
