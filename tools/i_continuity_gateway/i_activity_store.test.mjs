import test from 'node:test';
import assert from 'node:assert/strict';
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { createIActivityCrypto } from './i_activity_crypto.mjs';
import { createIActivityStore } from './i_activity_store.mjs';

const FIXED_NOW = '2026-07-10T08:00:00.000Z';
const FIXED_OCCURRED_AT = '2026-07-10T07:55:00.000Z';
const TEST_KEY_MATERIAL = {
  key: Buffer.from('0123456789abcdef0123456789abcdef', 'utf8'),
  keyId: 'activity-test-key-v1',
};

function fixedKeyProvider() {
  return {
    isSupported: true,
    hasKey: () => true,
    loadKey: () => TEST_KEY_MATERIAL,
    loadOrCreateKey: () => TEST_KEY_MATERIAL,
  };
}

function project({
  id = 'project-personal-0001',
  key = 'personal-project',
  name = 'Personal Project',
  policy = {},
} = {}) {
  return {
    registered: true,
    access_status: 'allowed',
    project_id: id,
    project_key: key,
    display_name: name,
    policy: {
      id: 'personal_full',
      classification: 'personal',
      cross_project_visibility: 'summary',
      memory_v3: 'project_summary',
      ...policy,
    },
  };
}

function closeout(overrides = {}) {
  return {
    session_id: 'session-0001',
    idempotency_key: 'closeout-0001',
    presence_mode: 'delegated_tool',
    summary: 'Implemented the project closeout ledger.',
    decisions: ['Use an append-only JSONL ledger.'],
    open_loops: ['Connect the projection to Memory V3 later.'],
    artifact_refs: ['tools/i_continuity_gateway/i_activity_store.mjs'],
    occurred_at: FIXED_OCCURRED_AT,
    ...overrides,
  };
}

function harness(t) {
  const root = mkdtempSync(join(tmpdir(), 'i-activity-store-'));
  const iHome = join(root, 'i-home');
  let sequence = 0;
  const store = createIActivityStore({
    iHome,
    clock: () => new Date(FIXED_NOW),
    uuid: () => `event-${String(++sequence).padStart(6, '0')}`,
    keyProvider: fixedKeyProvider(),
  });
  t.after(() => rmSync(root, { recursive: true, force: true }));
  return { iHome, store };
}

function readLedgerEvents(iHome) {
  const eventsRoot = join(iHome, 'activity', 'v2', 'events');
  assert.equal(existsSync(eventsRoot), true, 'the project ledger directory should exist');
  const files = readdirSync(eventsRoot).filter((name) => name.endsWith('.jsonl.enc'));
  assert.equal(files.length, 1, 'one project should map to one ledger file');
  const crypto = createIActivityCrypto(TEST_KEY_MATERIAL);
  return readFileSync(join(eventsRoot, files[0]), 'utf8')
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line) => crypto.open(JSON.parse(line), `ledger:${files[0]}`));
}

function recursiveDiskText(path) {
  if (!existsSync(path)) return '';
  return readdirSync(path, { withFileTypes: true })
    .map((entry) => {
      const child = join(path, entry.name);
      return entry.isDirectory()
        ? `${entry.name}\n${recursiveDiskText(child)}`
        : `${entry.name}\n${readFileSync(child, 'utf8')}`;
    })
    .join('\n');
}

function assertDiskDoesNotContain(iHome, values) {
  const diskText = recursiveDiskText(iHome);
  for (const value of values.flat()) {
    assert.equal(diskText.includes(value), false, `${value} leaked to disk in plaintext`);
  }
}

test('personal closeout is appended with server-owned provenance and indexed', (t) => {
  const { iHome, store } = harness(t);
  const activeProject = project();

  const result = store.closeSession({
    project: activeProject,
    clientId: 'Codex',
    input: closeout(),
  });

  assert.equal(result.accepted, true);
  assert.equal(result.persisted, true);
  assert.equal(result.duplicate, false);
  assert.equal(result.index_status, 'ready');
  assert.equal(result.event.source_tool, 'codex');
  assert.equal(result.event.project_id, activeProject.project_id);
  assert.equal(result.event.authority, 'agent_inferred');
  assert.equal(result.event.trust_level, 'trusted_client_unverified_content');

  const events = readLedgerEvents(iHome);
  assert.equal(events.length, 1);
  assert.equal(
    existsSync(join(iHome, 'activity', 'v2', 'activity-index.enc.json')),
    true,
    'the encrypted v2 activity index should exist',
  );
  assert.equal(existsSync(join(iHome, 'activity', 'activity-index.json')), false);
  assert.equal(events[0].event_type, 'session_closeout');
  assert.equal(events[0].project_key, activeProject.project_key);
  assert.match(events[0].source_instance, /^local-[a-f0-9]{12}$/);
  assert.deepEqual(events[0].memory_lanes_allowed, ['project']);
  assert.equal(events[0].policy_snapshot.id, 'personal_full');
  assert.equal(events[0].idempotency_scope, `${activeProject.project_id}:codex:closeout-0001`);

  const storedCloseout = closeout();
  assertDiskDoesNotContain(iHome, [
    activeProject.display_name,
    storedCloseout.summary,
    storedCloseout.decisions,
    storedCloseout.open_loops,
    storedCloseout.artifact_refs,
  ]);

  const recent = store.getRecentActivity({ visibleProjects: [activeProject] });
  assert.equal(recent.activity_count, 1);
  assert.equal(recent.activities[0].project_name, activeProject.display_name);
  assert.equal(recent.activities[0].summary, closeout().summary);
});

test('Memory V3 export includes personal details and redacts work details', (t) => {
  const { store } = harness(t);
  const personal = project();
  const work = project({
    id: 'project-work-0001',
    key: 'work',
    policy: {
      id: 'work_redacted',
      classification: 'work',
      cross_project_visibility: 'summary',
      memory_v3: 'redacted_summary',
    },
  });
  store.closeSession({ project: personal, clientId: 'codex', input: closeout() });
  store.closeSession({
    project: work,
    clientId: 'claude-code',
    input: closeout({
      session_id: 'session-work-0001',
      idempotency_key: 'closeout-work-0001',
      summary: 'Confidential client detail.',
      decisions: ['Secret decision.'],
      open_loops: ['Secret task.'],
      artifact_refs: ['private/plan.md'],
    }),
  });

  const result = store.getMemoryV3Projections({ projects: [personal, work] });
  assert.equal(result.projection_count, 2);
  const personalProjection = result.projections.find((item) => item.project_id === personal.project_id);
  assert.deepEqual(personalProjection.decisions, ['Use an append-only JSONL ledger.']);
  assert.equal(personalProjection.redaction_state, 'policy_summary');
  const workProjection = result.projections.find((item) => item.project_id === work.project_id);
  assert.equal(workProjection.summary, 'claude-code completed a work session.');
  assert.deepEqual(workProjection.decisions, []);
  assert.deepEqual(workProjection.open_loops, []);
  assert.deepEqual(workProjection.artifact_refs, []);
});

test('same idempotency key and content returns the original event without appending', (t) => {
  const { iHome, store } = harness(t);
  const activeProject = project();
  const request = {
    project: activeProject,
    clientId: 'codex',
    input: closeout(),
  };

  const first = store.closeSession(request);
  const second = store.closeSession(request);

  assert.equal(first.duplicate, false);
  assert.equal(second.duplicate, true);
  assert.equal(second.event.event_id, first.event.event_id);
  assert.equal(readLedgerEvents(iHome).length, 1);
  assert.equal(store.getRecentActivity({ visibleProjects: [activeProject] }).activity_count, 1);
});

test('retry without occurred_at stays idempotent after the server clock advances', (t) => {
  const root = mkdtempSync(join(tmpdir(), 'i-activity-store-clock-'));
  const iHome = join(root, 'i-home');
  const clockValues = [
    new Date('2026-07-10T08:00:00.000Z'),
    new Date('2026-07-10T08:05:00.000Z'),
  ];
  let clockIndex = 0;
  const store = createIActivityStore({
    iHome,
    clock: () => clockValues[Math.min(clockIndex++, clockValues.length - 1)],
    uuid: () => 'event-clock-retry',
    keyProvider: fixedKeyProvider(),
  });
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const input = closeout();
  delete input.occurred_at;
  const request = {
    project: project(),
    clientId: 'codex',
    input,
  };

  const first = store.closeSession(request);
  const retry = store.closeSession(request);

  assert.equal(first.duplicate, false);
  assert.equal(retry.duplicate, true);
  assert.equal(retry.event.event_id, first.event.event_id);
  assert.equal(retry.event.occurred_at, first.event.occurred_at);
  assert.equal(readLedgerEvents(iHome).length, 1);
});

test('same idempotency key with different content is rejected as a conflict', (t) => {
  const { iHome, store } = harness(t);
  const activeProject = project();
  store.closeSession({ project: activeProject, clientId: 'codex', input: closeout() });

  assert.throws(
    () => store.closeSession({
      project: activeProject,
      clientId: 'codex',
      input: closeout({ summary: 'Different closeout content.' }),
    }),
    /idempotency key already exists with different closeout content/,
  );
  assert.equal(readLedgerEvents(iHome).length, 1);
});

test('likely secrets and unsafe artifact references are rejected before persistence', async (t) => {
  await t.test('likely credential', (child) => {
    const { iHome, store } = harness(child);
    assert.throws(
      () => store.closeSession({
        project: project(),
        clientId: 'codex',
        input: closeout({ summary: 'Temporary api_key=abcdefghijk123456 must not be saved.' }),
      }),
      /credential or secret/,
    );
    assert.equal(existsSync(join(iHome, 'activity')), false);
  });

  for (const [label, artifact] of [
    ['parent traversal', '../outside.txt'],
    ['absolute path', 'C:/Users/USER'],
    ['URL', 'https://example.invalid/private'],
    ['URL without slashes', 'https:example.com'],
    ['home-relative path', '~/.ssh'],
  ]) {
    await t.test(label, (child) => {
      const { iHome, store } = harness(child);
      assert.throws(
        () => store.closeSession({
          project: project(),
          clientId: 'codex',
          input: closeout({ artifact_refs: [artifact] }),
        }),
        /artifact_refs must/,
      );
      assert.equal(existsSync(join(iHome, 'activity')), false);
    });
  }

  await t.test('punctuated password', (child) => {
    const { iHome, store } = harness(child);
    assert.throws(
      () => store.closeSession({
        project: project(),
        clientId: 'codex',
        input: closeout({ summary: 'Do not persist password=P@ssw0rd! in a closeout.' }),
      }),
      /credential or secret/,
    );
    assert.equal(existsSync(join(iHome, 'activity')), false);
  });
});

test('ephemeral projects and private presence never create a ledger', async (t) => {
  await t.test('ephemeral policy', (child) => {
    const { iHome, store } = harness(child);
    const result = store.closeSession({
      project: project({
        id: 'project-ephemeral-0001',
        key: 'ephemeral-project',
        policy: {
          id: 'ephemeral',
          classification: 'unknown',
          cross_project_visibility: 'hidden',
          memory_v3: 'none',
        },
      }),
      clientId: 'codex',
      input: closeout(),
    });
    assert.deepEqual(
      { accepted: result.accepted, persisted: result.persisted, reason: result.reason },
      { accepted: false, persisted: false, reason: 'ephemeral_project' },
    );
    assert.equal(existsSync(join(iHome, 'activity')), false);
  });

  await t.test('private presence', (child) => {
    const { iHome, store } = harness(child);
    const result = store.closeSession({
      project: project(),
      clientId: 'claude-code',
      input: closeout({ presence_mode: 'private' }),
    });
    assert.deepEqual(
      { accepted: result.accepted, persisted: result.persisted, reason: result.reason },
      { accepted: false, persisted: false, reason: 'private_presence_mode' },
    );
    assert.equal(existsSync(join(iHome, 'activity')), false);
  });
});

test('work_redacted keeps details in its local ledger but never leaks them to the activity index', (t) => {
  const { iHome, store } = harness(t);
  const workProject = project({
    id: 'project-work-000001',
    key: 'client-work',
    name: 'Client Work',
    policy: {
      id: 'work_redacted',
      classification: 'work',
      cross_project_visibility: 'summary',
      memory_v3: 'redacted_summary',
    },
  });
  const sensitiveSummary = 'Acme migration reached the blue-lantern milestone.';
  const sensitiveDecision = 'Use the internal nebula deployment path.';
  const sensitiveOpenLoop = 'Resolve customer-omega approval.';
  const sensitiveArtifact = 'internal/acme-blue-lantern.md';

  const result = store.closeSession({
    project: workProject,
    clientId: 'Hermes',
    input: closeout({
      summary: sensitiveSummary,
      decisions: [sensitiveDecision],
      open_loops: [sensitiveOpenLoop],
      artifact_refs: [sensitiveArtifact],
    }),
  });
  assert.equal(result.index_status, 'ready');
  assert.equal(readLedgerEvents(iHome)[0].summary, sensitiveSummary);

  assertDiskDoesNotContain(iHome, [
    workProject.display_name,
    sensitiveSummary,
    sensitiveDecision,
    sensitiveOpenLoop,
    sensitiveArtifact,
  ]);

  const recent = store.getRecentActivity({ visibleProjects: [workProject] });
  assert.equal(recent.activity_count, 1);
  assert.equal(recent.activities[0].redaction, 'work_redacted');
  assert.notEqual(recent.activities[0].summary, sensitiveSummary);
  assert.equal(recent.activities[0].decision_count, 1);
  assert.equal(recent.activities[0].open_loop_count, 1);
});

test('a formerly personal event reveals nothing when the project is no longer visible', (t) => {
  const { iHome, store } = harness(t);
  const personalProject = project({
    id: 'project-policy-change-0001',
    key: 'policy-change-project',
    name: 'Project Aurora Private Name',
  });
  const personalSummary = 'Aurora personal summary must be hydrated only after authorization.';

  store.closeSession({
    project: personalProject,
    clientId: 'codex',
    input: closeout({ summary: personalSummary }),
  });

  assertDiskDoesNotContain(iHome, [
    personalProject.display_name,
    personalSummary,
    closeout().decisions,
    closeout().open_loops,
    closeout().artifact_refs,
  ]);

  // The current registry policy is confidential/hidden, so the registry supplies no visible project.
  const recentAfterPolicyChange = store.getRecentActivity({ visibleProjects: [] });
  assert.equal(recentAfterPolicyChange.activity_count, 0);
  assert.deepEqual(recentAfterPolicyChange.activities, []);
  assert.equal(JSON.stringify(recentAfterPolicyChange).includes(personalProject.display_name), false);
  assert.equal(JSON.stringify(recentAfterPolicyChange).includes(personalSummary), false);
});

test('name_only returns one project marker without event, time or tool metadata', (t) => {
  const { iHome, store } = harness(t);
  const nameOnlyProject = project({
    id: 'project-name-only-0001',
    key: 'name-only-project',
    name: 'Name Only Project',
    policy: {
      cross_project_visibility: 'name_only',
    },
  });

  store.closeSession({
    project: nameOnlyProject,
    clientId: 'hermes',
    input: closeout({ summary: 'This event detail must not appear in a name-only response.' }),
  });

  const recent = store.getRecentActivity({ visibleProjects: [nameOnlyProject] });
  assert.equal(recent.activity_count, 1);
  assert.deepEqual(recent.activities[0], {
    project_id: nameOnlyProject.project_id,
    project_key: nameOnlyProject.project_key,
    project_name: nameOnlyProject.display_name,
    visibility: 'name_only',
  });
  for (const field of ['event_id', 'event_type', 'occurred_at', 'received_at', 'source_tool']) {
    assert.equal(field in recent.activities[0], false, `${field} must not appear in name_only`);
  }
  assertDiskDoesNotContain(iHome, [
    nameOnlyProject.display_name,
    'This event detail must not appear in a name-only response.',
    closeout().decisions,
    closeout().open_loops,
    closeout().artifact_refs,
  ]);
});

test('local_only sensitivity remains readable in the active project but never enters the index', (t) => {
  const { iHome, store } = harness(t);
  const activeProject = project({
    id: 'project-local-only-0001',
    key: 'local-only-project',
    name: 'Local Only Project',
  });
  const localOnlySummary = 'Local-only atlas marker stays within this project.';

  const result = store.closeSession({
    project: activeProject,
    clientId: 'codex',
    input: closeout({
      sensitivity: 'local_only',
      summary: localOnlySummary,
    }),
  });
  assert.equal(result.persisted, true);
  assert.equal(result.event.sensitivity, 'local_only');

  const handoffs = store.getProjectHandoffs(activeProject);
  assert.equal(handoffs.length, 1);
  assert.equal(handoffs[0].summary, localOnlySummary);
  assert.equal(handoffs[0].sensitivity, 'local_only');
  const searchHits = store.searchProjectActivity(activeProject, 'atlas');
  assert.equal(searchHits.length, 1);
  assert.equal(searchHits[0].summary, localOnlySummary);

  assertDiskDoesNotContain(iHome, [
    activeProject.display_name,
    localOnlySummary,
    closeout().decisions,
    closeout().open_loops,
    closeout().artifact_refs,
  ]);
  const recent = store.getRecentActivity({ visibleProjects: [activeProject] });
  assert.equal(recent.activity_count, 0);
  assert.deepEqual(recent.activities, []);
});

test('confidential_local is readable inside its project but absent from the cross-project index', (t) => {
  const { iHome, store } = harness(t);
  const confidentialProject = project({
    id: 'project-confidential-0001',
    key: 'confidential-project',
    name: 'Confidential Project',
    policy: {
      id: 'confidential_local',
      classification: 'confidential',
      cross_project_visibility: 'hidden',
      memory_v3: 'none',
    },
  });
  const localOnlySummary = 'Local-only confidential handoff.';

  const result = store.closeSession({
    project: confidentialProject,
    clientId: 'claude-code',
    input: closeout({ summary: localOnlySummary }),
  });
  assert.equal(result.persisted, true);
  assert.equal(result.index_status, 'ready');

  const handoffs = store.getProjectHandoffs(confidentialProject);
  assert.equal(handoffs.length, 1);
  assert.equal(handoffs[0].summary, localOnlySummary);

  assertDiskDoesNotContain(iHome, [
    confidentialProject.display_name,
    localOnlySummary,
    closeout().decisions,
    closeout().open_loops,
    closeout().artifact_refs,
  ]);

  const recent = store.getRecentActivity({ visibleProjects: [confidentialProject] });
  assert.equal(recent.activity_count, 0);
  assert.deepEqual(recent.activities, []);
});

test('two consecutive writes replace the activity index successfully on Windows', (t) => {
  const { iHome, store } = harness(t);
  const activeProject = project();

  const first = store.closeSession({
    project: activeProject,
    clientId: 'codex',
    input: closeout(),
  });
  const second = store.closeSession({
    project: activeProject,
    clientId: 'codex',
    input: closeout({
      session_id: 'session-0002',
      idempotency_key: 'closeout-0002',
      summary: 'Added the second activity entry.',
      occurred_at: '2026-07-10T07:58:00.000Z',
    }),
  });

  assert.equal(first.index_status, 'ready');
  assert.equal(second.index_status, 'ready');
  assert.equal(readLedgerEvents(iHome).length, 2);

  const recent = store.getRecentActivity({ visibleProjects: [activeProject] });
  assert.equal(recent.activity_count, 2);
  assert.equal(recent.activities[0].summary, 'Added the second activity entry.');
  assertDiskDoesNotContain(iHome, [
    activeProject.display_name,
    closeout().summary,
    'Added the second activity entry.',
    closeout().decisions,
    closeout().open_loops,
    closeout().artifact_refs,
  ]);
});

test('cross-project activity reads only the safe encrypted index, not the raw project ledger', (t) => {
  const { iHome, store } = harness(t);
  const activeProject = project();
  const summary = 'safe_index_projection_marker';
  store.closeSession({
    project: activeProject,
    clientId: 'codex',
    input: closeout({ summary }),
  });

  const eventsRoot = join(iHome, 'activity', 'v2', 'events');
  const ledgerPath = join(
    eventsRoot,
    readdirSync(eventsRoot).find((name) => name.endsWith('.jsonl.enc')),
  );
  const envelope = JSON.parse(readFileSync(ledgerPath, 'utf8').trim());
  const first = envelope.ciphertext[0];
  envelope.ciphertext = `${first === 'A' ? 'B' : 'A'}${envelope.ciphertext.slice(1)}`;
  writeFileSync(ledgerPath, `${JSON.stringify(envelope)}\n`, 'utf8');

  const recent = store.getRecentActivity({ visibleProjects: [activeProject] });
  assert.equal(recent.activity_count, 1);
  assert.equal(recent.activities[0].summary, summary);
  assert.throws(
    () => store.getProjectHandoffs(activeProject),
    /encrypted activity ledger failed integrity validation/,
  );
});
