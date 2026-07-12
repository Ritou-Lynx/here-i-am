import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { createIActivityStore } from './i_activity_store.mjs';
import { exportSyncPackage, importSyncPackages } from './i_device_sync.mjs';
import { loadProjectRegistry } from './i_project_registry.mjs';

const passphrase = 'correct horse battery staple for i sync';
const environment = { ...process.env, I_SYNC_PASSPHRASE: passphrase };

function setupHome(root, projectId, extraProject = false, identitySchemaVersion = 2) {
  const home = join(root, `home-${projectId}`);
  const projectRoot = join(root, `project-${projectId}`);
  mkdirSync(home, { recursive: true });
  mkdirSync(projectRoot, { recursive: true });
  const identity = {
    schema_version: identitySchemaVersion,
    identity: { name: '林埃', english_name: 'i', self_reference: 'i', is_ai: true, anchor: 'AI is 林埃.' },
    relationship: { user_preferred_name: 'Lynx', user_aliases: ['林克斯'], scope: 'workbench_minimal' },
  };
  writeFileSync(join(home, 'identity.json'), JSON.stringify(identity));
  const projects = [{
    registered: true,
    access_status: 'allowed',
    project_id: projectId,
    project_key: 'here-i-am',
    display_name: 'Here I am',
    roots: [projectRoot],
    provider: 'here_i_am',
    context_files: [],
    policy: {
      id: 'personal_full', classification: 'personal', cross_project_visibility: 'summary',
      memory_v3: 'project_summary', allowed_clients: ['codex', 'claude-code'],
    },
  }];
  if (extraProject) projects.push({
    registered: true, access_status: 'allowed',
    project_id: '33333333-3333-4333-8333-333333333333', project_key: 'only-on-source', display_name: 'Only on source',
    roots: [join(root, 'only-on-source')], provider: 'markdown', context_files: [],
    policy: {
      id: 'personal_full', classification: 'personal', cross_project_visibility: 'summary',
      memory_v3: 'project_summary', allowed_clients: ['codex'],
    },
  });
  if (extraProject) mkdirSync(join(root, 'only-on-source'), { recursive: true });
  writeFileSync(join(home, 'projects.json'), JSON.stringify({ schema_version: 1, projects }));
  return { home, projects };
}

test('encrypted packages sync registered projects across devices without duplicating or registering unknown projects', { skip: process.platform !== 'win32' }, () => {
  const root = mkdtempSync(join(tmpdir(), 'i-device-sync-'));
  const syncRoot = join(root, 'transport');
  const source = setupHome(root, '11111111-1111-4111-8111-111111111111', true, 1);
  const target = setupHome(root, '22222222-2222-4222-8222-222222222222');
  assert.equal(loadProjectRegistry({ iHome: source.home }).status, 'ready');
  const sourceStore = createIActivityStore({ iHome: source.home, registryProjectsProvider: () => source.projects });
  for (const project of source.projects) {
    sourceStore.closeSession({
      project, clientId: 'codex',
      input: {
        session_id: `session-${project.project_key}`, idempotency_key: `session-${project.project_key}:closeout-v1`,
        summary: `Finished ${project.project_key}.`, decisions: [], open_loops: [], artifact_refs: [],
      },
    });
  }
  const exported = exportSyncPackage({ iHome: source.home, syncRoot, environment });
  assert.equal(exported.closeout_count, 2);
  const first = importSyncPackages({ iHome: target.home, syncRoot, environment });
  assert.equal(first.imported, 1);
  assert.equal(first.skipped_unknown_project, 1);
  const targetStore = createIActivityStore({ iHome: target.home, registryProjectsProvider: () => target.projects });
  assert.equal(targetStore.getProjectHandoffs(target.projects[0]).length, 1);
  const second = importSyncPackages({ iHome: target.home, syncRoot, environment });
  assert.equal(second.packages, 1);
  assert.equal(second.duplicates, 0);
  assert.equal(second.skipped_unknown_project, 1);
  assert.equal(targetStore.getProjectHandoffs(target.projects[0]).length, 1);
});
