import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  buildDevRoomCloseoutInput,
  persistDevRoomCloseout,
  runHasPersistedCloseout,
} from './project_memory_closeout.mjs';

function completedRun(root, overrides = {}) {
  return {
    id: 'run-0001',
    sessionId: 'session-0001',
    agentType: 'codex',
    status: 'done',
    summary: 'Implemented and verified the current paper draft.',
    endedAt: 1783828800,
    project: { rootPath: root },
    ...overrides,
  };
}

test('completed Dev Room run creates a bounded idempotent closeout', () => {
  const input = buildDevRoomCloseoutInput(completedRun('D:/paper'));
  assert.equal(input.idempotency_key, 'dev-room-run-0001:closeout-v1');
  assert.equal(input.presence_mode, 'delegated_tool');
  assert.equal(input.summary, 'Implemented and verified the current paper draft.');
  assert.deepEqual(input.artifact_refs, []);
});

test('failed and empty runs do not create closeouts', () => {
  assert.equal(buildDevRoomCloseoutInput(completedRun('D:/paper', { status: 'failed' })), null);
  assert.equal(buildDevRoomCloseoutInput(completedRun('D:/paper', { summary: '  ' })), null);
});

test('successful agent closeout is detected and not duplicated', () => {
  const run = completedRun('D:/paper', {
    transcript: [
      '{"accepted":true,"persisted":true,"event":{"event_type":"session_closeout"}}',
    ],
  });
  assert.equal(runHasPersistedCloseout(run), true);
  const result = persistDevRoomCloseout({ run });
  assert.equal(result.persisted, true);
  assert.equal(result.duplicate, true);
  assert.equal(result.reason, 'agent_closeout_already_persisted');
});

test('fallback summary is capped at the Gateway limit', () => {
  const input = buildDevRoomCloseoutInput(completedRun('D:/paper', {
    summary: 'x'.repeat(2500),
  }));
  assert.equal(input.summary.length, 2000);
});

test('registered run is resolved by root and passed to the activity store', (t) => {
  const root = mkdtempSync(join(tmpdir(), 'dev-room-closeout-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  let captured;
  const result = persistDevRoomCloseout({
    run: completedRun(root),
    iHome: join(root, 'i-home'),
    loadRegistry: () => ({
      status: 'ready',
      projects: [{
        project_id: 'paper-id',
        project_key: 'paper',
        display_name: 'Paper',
        roots: [root],
        provider: 'markdown',
        context_files: [],
        policy: {
          id: 'personal_full',
          classification: 'personal',
          cross_project_visibility: 'summary',
          memory_v3: 'project_summary',
          allowed_clients: ['*'],
        },
      }],
    }),
    createStore: () => ({
      closeSession(request) {
        captured = request;
        return { persisted: true, accepted: true, duplicate: false };
      },
    }),
  });
  assert.equal(result.persisted, true);
  assert.equal(captured.project.project_key, 'paper');
  assert.equal(captured.clientId, 'codex');
  assert.equal(captured.input.session_id, 'session-0001');
});
