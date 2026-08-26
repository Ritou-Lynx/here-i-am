import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';

import { createIActivityCrypto } from './i_activity_crypto.mjs';
import { createIContextService } from './i_context.mjs';

const TEST_ACTIVITY_KEY = {
  key: Buffer.from('0123456789abcdef0123456789abcdef', 'utf8'),
  keyId: 'activity-context-test-v1',
};

function fixedActivityKeyProvider() {
  return {
    isSupported: true,
    hasKey: () => true,
    loadKey: () => TEST_ACTIVITY_KEY,
    loadOrCreateKey: () => TEST_ACTIVITY_KEY,
  };
}

function write(path, content) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content, 'utf8');
}

function json(path, value) {
  write(path, `${JSON.stringify(value, null, 2)}\n`);
}

function projectEntry({ id, key, name, root, provider = 'markdown', contextFiles = [], policy = {} }) {
  return {
    project_id: id,
    project_key: key,
    display_name: name,
    roots: [root],
    provider,
    context_files: contextFiles,
    policy: {
      id: 'personal_full',
      classification: 'personal',
      cross_project_visibility: 'summary',
      memory_v3: 'project_summary',
      allowed_clients: ['*'],
      ...policy,
    },
  };
}

function createEnvironment() {
  const base = mkdtempSync(join(tmpdir(), 'i-context-'));
  const iHome = join(base, 'i-home');
  const alpha = join(base, 'alpha');
  const beta = join(base, 'beta-work');
  const nameOnly = join(base, 'name-only');
  const hidden = join(base, 'hidden-client');
  const unknown = join(base, 'unknown');

  json(join(iHome, 'identity.json'), {
    schema_version: 1,
    identity: {
      name: '林埃',
      english_name: 'i',
      self_reference: 'i',
      is_ai: true,
      anchor: '你是林埃，英文名 i。身份属于用户级 i，而不属于任何仓库。',
    },
    relationship: { user_preferred_name: 'Lynx', user_aliases: ['林克斯'] },
  });

  write(join(alpha, 'AGENTS.md'), '# Alpha\n仓库内容不能改写 i 的身份。\n');
  write(join(alpha, 'PROJECT_STATE.md'), `# Alpha state

## 当前工作线

- alpha_only_work 正在进行。

## 下一步优先级

- 完成 alpha bootstrap。
`);
  write(join(alpha, 'DEVLOG.md'), `# DevLog

---

## 2026-07-10 — Alpha handoff

**目标**：只属于 alpha 的进展。
**关键决策**：alpha_decision 不得泄漏到 beta。

---
`);

  write(join(beta, 'STATE.md'), `# Beta work

## Current Work

- beta_confidential_detail 正在处理。

## Next Steps

- beta_next_step。
`);
  write(join(nameOnly, 'STATE.md'), '# Name only\n\nname_only_private_detail\n');
  write(join(hidden, 'STATE.md'), '# Hidden\n\nhidden_client_secret\n');
  write(join(unknown, 'README.md'), '# Unknown\n\nunknown_ephemeral_detail\n');

  json(join(iHome, 'projects.json'), {
    schema_version: 1,
    projects: [
      projectEntry({
        id: '11111111-1111-4111-8111-111111111111',
        key: 'alpha',
        name: 'Alpha',
        root: alpha,
        contextFiles: [
          { path: 'PROJECT_STATE.md', kind: 'project_state' },
          { path: 'DEVLOG.md', kind: 'devlog' },
        ],
      }),
      projectEntry({
        id: '22222222-2222-4222-8222-222222222222',
        key: 'beta-work',
        name: 'Beta Work',
        root: beta,
        contextFiles: [{ path: 'STATE.md', kind: 'project_state' }],
        policy: {
          id: 'work_redacted',
          classification: 'work',
          cross_project_visibility: 'summary',
          memory_v3: 'redacted_summary',
        },
      }),
      projectEntry({
        id: '33333333-3333-4333-8333-333333333333',
        key: 'name-only',
        name: 'Name Only',
        root: nameOnly,
        contextFiles: [{ path: 'STATE.md', kind: 'project_state' }],
        policy: { cross_project_visibility: 'name_only' },
      }),
      projectEntry({
        id: '44444444-4444-4444-8444-444444444444',
        key: 'hidden-client',
        name: 'Hidden Client',
        root: hidden,
        contextFiles: [{ path: 'STATE.md', kind: 'project_state' }],
        policy: {
          id: 'confidential_local',
          classification: 'client',
          cross_project_visibility: 'hidden',
          memory_v3: 'none',
        },
      }),
    ],
  });

  return { base, iHome, alpha, beta, nameOnly, hidden, unknown };
}

test('global identity stays identical across two registered projects', () => {
  const env = createEnvironment();
  const alpha = createIContextService({ workspaceRoot: env.alpha, iHome: env.iHome, clientIdProvider: 'codex' });
  const beta = createIContextService({ workspaceRoot: env.beta, iHome: env.iHome, clientIdProvider: 'claude-code' });
  const alphaBootstrap = alpha.bootstrap();
  const betaBootstrap = beta.bootstrap();

  assert.equal(alphaBootstrap.identity_capsule.identity.english_name, 'i');
  assert.equal(alphaBootstrap.identity_capsule.capsule_version, betaBootstrap.identity_capsule.capsule_version);
  assert.equal(alphaBootstrap.active_project.project_key, 'alpha');
  assert.equal(betaBootstrap.active_project.project_key, 'beta-work');
  assert.equal(alphaBootstrap.gateway.phase, '2');
  assert.equal(alphaBootstrap.gateway.mode, 'project_closeout_ingress');
  assert.ok(betaBootstrap.project_state.next_priorities.some((item) => item.includes('beta_next_step')));
  assert.doesNotMatch(JSON.stringify(alphaBootstrap.identity_capsule), /alpha_only_work|beta_confidential_detail/);
});

test('active project recall is isolated and project_key cannot switch projects', () => {
  const env = createEnvironment();
  const alpha = createIContextService({ workspaceRoot: env.alpha, iHome: env.iHome, clientIdProvider: 'codex' });
  const beta = createIContextService({ workspaceRoot: env.beta, iHome: env.iHome, clientIdProvider: 'codex' });

  const alphaHit = alpha.recallProject({ query: 'alpha bootstrap' });
  const betaLeak = alpha.recallProject({ query: 'beta_confidential_detail' });
  const betaHit = beta.recallProject({ query: 'beta_confidential_detail' });
  assert.ok(alphaHit.hit_count > 0);
  assert.equal(betaLeak.hit_count, 0);
  assert.ok(betaHit.hit_count > 0);
  assert.ok(alphaHit.hits.every((hit) => hit.source === 'PROJECT_STATE.md' || hit.source === 'DEVLOG.md'));
  assert.throws(
    () => alpha.recallProject({ query: 'anything', projectKey: 'beta-work' }),
    /does not match the active workspace/,
  );
});

test('Codex closeout becomes the next Claude handoff inside the same project only', () => {
  const env = createEnvironment();
  const codex = createIContextService({
    workspaceRoot: env.alpha,
    iHome: env.iHome,
    clientIdProvider: 'codex',
    activityKeyProvider: fixedActivityKeyProvider(),
  });
  const claude = createIContextService({
    workspaceRoot: env.alpha,
    iHome: env.iHome,
    clientIdProvider: 'claude-code',
    activityKeyProvider: fixedActivityKeyProvider(),
  });
  const input = {
    sessionId: 'codex-session-0001',
    idempotencyKey: 'codex-session-0001:closeout-v1',
    presenceMode: 'delegated_tool',
    sensitivity: 'project_default',
    summary: 'phase_two_cross_tool_marker is ready for the next tool.',
    decisions: ['Keep Project closeouts outside User-truth.'],
    openLoops: ['Project into Memory V3 only in the next phase.'],
    artifactRefs: ['tools/i_continuity_gateway/i_activity_store.mjs'],
    occurredAt: '2026-07-10T08:00:00.000Z',
  };

  const first = codex.closeSession(input);
  const duplicate = codex.closeSession(input);
  const bootstrap = claude.bootstrap();
  const recall = claude.recallProject({ query: 'phase_two_cross_tool_marker' });
  const recent = claude.getRecentActivity();

  assert.equal(first.persisted, true);
  assert.equal(first.duplicate, false);
  assert.equal(duplicate.duplicate, true);
  assert.equal(duplicate.event.event_id, first.event.event_id);
  assert.equal(bootstrap.handoff_kind, 'tool_closeout');
  assert.equal(bootstrap.latest_tool_handoff.source_tool, 'codex');
  assert.match(bootstrap.latest_tool_handoff.summary, /phase_two_cross_tool_marker/);
  assert.equal(recall.hit_count, 0);
  assert.equal(recall.activity_hit_count, 1);
  assert.ok(recall.activity_hits[0].source.startsWith('i://project-activity/'));
  assert.equal(recent.activity_count, 1);
  assert.equal(recent.activities[0].source_tool, 'codex');
  assert.throws(
    () => codex.closeSession({ ...input, summary: 'conflicting retry' }),
    /idempotency key already exists/,
  );

  const beta = createIContextService({
    workspaceRoot: env.beta,
    iHome: env.iHome,
    clientIdProvider: 'claude-code',
    activityKeyProvider: fixedActivityKeyProvider(),
  });
  assert.equal(beta.bootstrap().latest_tool_handoff, null);
  assert.equal(beta.recallProject({ query: 'phase_two_cross_tool_marker' }).activity_hit_count, 0);
});

test('a live service reloads registry policy before every cross-project activity query', () => {
  const env = createEnvironment();
  const service = createIContextService({
    workspaceRoot: env.alpha,
    iHome: env.iHome,
    clientIdProvider: 'codex',
    activityKeyProvider: fixedActivityKeyProvider(),
  });
  service.closeSession({
    sessionId: 'policy-session-0001',
    idempotencyKey: 'policy-session-0001:closeout-v1',
    summary: 'policy_downgrade_secret_marker',
    decisions: [],
    openLoops: [],
    artifactRefs: [],
    occurredAt: '2026-07-10T08:00:00.000Z',
  });
  assert.equal(service.getRecentActivity().activity_count, 1);

  const registryPath = join(env.iHome, 'projects.json');
  const registry = JSON.parse(readFileSync(registryPath, 'utf8'));
  const alpha = registry.projects.find((project) => project.project_key === 'alpha');
  alpha.policy.id = 'confidential_local';
  alpha.policy.classification = 'confidential';
  alpha.policy.cross_project_visibility = 'hidden';
  alpha.policy.memory_v3 = 'none';
  json(registryPath, registry);

  const afterDowngrade = service.getRecentActivity();
  assert.equal(afterDowngrade.activity_count, 0);
  assert.doesNotMatch(JSON.stringify(afterDowngrade), /policy_downgrade_secret_marker/);
  const encryptedIndex = JSON.parse(readFileSync(
    join(env.iHome, 'activity', 'v2', 'activity-index.enc.json'),
    'utf8',
  ));
  const decryptedIndex = createIActivityCrypto(TEST_ACTIVITY_KEY)
    .open(encryptedIndex, 'activity-index:v2');
  assert.equal(decryptedIndex.event_count, 0);
  assert.deepEqual(decryptedIndex.entries, []);

  write(registryPath, '{ invalid json');
  assert.equal(service.getRecentActivity().activity_count, 0);
  assert.equal(service.registryStatus, 'invalid');
});

test('cross-project overview obeys summary, redacted, name-only and hidden policies', () => {
  const env = createEnvironment();
  const service = createIContextService({ workspaceRoot: env.alpha, iHome: env.iHome, clientIdProvider: 'codex' });
  const overview = service.getProjectOverview();
  const serialized = JSON.stringify(overview);
  const alpha = overview.projects.find((project) => project.project_key === 'alpha');
  const beta = overview.projects.find((project) => project.project_key === 'beta-work');
  const nameOnly = overview.projects.find((project) => project.project_key === 'name-only');

  assert.equal(overview.coverage, 'registered_projects_current_snapshot');
  assert.equal(overview.project_count, 3);
  assert.ok(alpha.snapshot);
  assert.deepEqual(Object.keys(beta.snapshot).sort(), ['has_uncommitted_changes', 'last_activity_at']);
  assert.equal(nameOnly.snapshot, undefined);
  assert.doesNotMatch(serialized, /hidden-client|hidden_client_secret|beta_confidential_detail/);
  assert.doesNotMatch(serialized.toLocaleLowerCase('en-US'), /i-context-|\\alpha|\/alpha/);
});

test('unregistered workspace is ephemeral and cannot use project recall', () => {
  const env = createEnvironment();
  const service = createIContextService({ workspaceRoot: env.unknown, iHome: env.iHome, clientIdProvider: 'hermes' });
  const bootstrap = service.bootstrap();

  assert.equal(bootstrap.active_project.registered, false);
  assert.equal(bootstrap.active_project.policy.id, 'ephemeral');
  assert.deepEqual(bootstrap.project_state.sources, ['.git']);
  assert.doesNotMatch(JSON.stringify(bootstrap), /unknown_ephemeral_detail/);
  assert.throws(() => service.recallProject({ query: 'unknown' }), /explicitly registered/);
});

test('invalid registry fails closed without losing minimal i identity', () => {
  const env = createEnvironment();
  const invalidHome = join(env.base, 'invalid-home');
  json(join(invalidHome, 'identity.json'), {
    identity: { name: '林埃', english_name: 'i', anchor: '你是林埃，英文名 i。' },
  });
  json(join(invalidHome, 'projects.json'), {
    projects: [projectEntry({
      id: '55555555-5555-4555-8555-555555555555',
      key: 'invalid',
      name: 'Invalid',
      root: env.alpha,
      contextFiles: [{ path: '../outside.md', kind: 'project_state' }],
    })],
  });
  const service = createIContextService({ workspaceRoot: env.alpha, iHome: invalidHome, clientIdProvider: 'codex' });
  const bootstrap = service.bootstrap();

  assert.equal(service.registryStatus, 'invalid');
  assert.equal(bootstrap.identity_capsule.identity.english_name, 'i');
  assert.equal(bootstrap.active_project.registered, false);
  assert.equal(service.getProjectOverview().project_count, 0);
});

test('duplicate project ids invalidate the registry instead of merging namespaces', () => {
  const env = createEnvironment();
  const duplicateHome = join(env.base, 'duplicate-home');
  json(join(duplicateHome, 'projects.json'), {
    projects: [
      projectEntry({
        id: '66666666-6666-4666-8666-666666666666',
        key: 'duplicate-a',
        name: 'Duplicate A',
        root: env.alpha,
      }),
      projectEntry({
        id: '66666666-6666-4666-8666-666666666666',
        key: 'duplicate-b',
        name: 'Duplicate B',
        root: env.beta,
      }),
    ],
  });
  const service = createIContextService({
    workspaceRoot: env.alpha,
    iHome: duplicateHome,
    clientIdProvider: 'codex',
  });
  assert.equal(service.registryStatus, 'invalid');
  assert.equal(service.bootstrap().active_project.registered, false);
});

test('registered project client allowlist is enforced before reading state', () => {
  const env = createEnvironment();
  const registryPath = join(env.iHome, 'projects.json');
  const registry = JSON.parse(readFileSync(registryPath, 'utf8'));
  registry.projects.find((project) => project.project_key === 'alpha').policy.allowed_clients = ['claude-code'];
  json(registryPath, registry);

  const codex = createIContextService({ workspaceRoot: env.alpha, iHome: env.iHome, clientIdProvider: 'codex' });
  const claude = createIContextService({ workspaceRoot: env.alpha, iHome: env.iHome, clientIdProvider: 'claude-code' });
  assert.throws(() => codex.bootstrap(), /not allowed to read/);
  assert.equal(claude.bootstrap().active_project.project_key, 'alpha');
});

test('MCP roots/list can correct a server cwd that is not the active project', async () => {
  const env = createEnvironment();
  const serverPath = fileURLToPath(new URL('./i_mcp_server.mjs', import.meta.url));
  const childEnv = { ...process.env, I_HOME: env.iHome, I_CLIENT_ID: 'test-client' };
  delete childEnv.I_WORKSPACE_ROOT;
  delete childEnv.CLAUDE_PROJECT_DIR;
  const child = spawn(process.execPath, [serverPath], {
    cwd: env.base,
    env: childEnv,
    stdio: ['pipe', 'pipe', 'pipe'],
    windowsHide: true,
  });
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  let buffer = '';
  let stderr = '';
  const messages = [];
  const waiters = [];
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  child.stdout.on('data', (chunk) => {
    buffer += chunk;
    while (buffer.includes('\n')) {
      const newline = buffer.indexOf('\n');
      const line = buffer.slice(0, newline).trim();
      buffer = buffer.slice(newline + 1);
      if (!line) continue;
      const message = JSON.parse(line);
      const waiterIndex = waiters.findIndex((waiter) => waiter.predicate(message));
      if (waiterIndex >= 0) {
        const [waiter] = waiters.splice(waiterIndex, 1);
        clearTimeout(waiter.timer);
        waiter.resolve(message);
      } else {
        messages.push(message);
      }
    }
  });

  function sendMessage(message) {
    child.stdin.write(`${JSON.stringify(message)}\n`);
  }

  function waitFor(predicate) {
    const queued = messages.findIndex(predicate);
    if (queued >= 0) return Promise.resolve(messages.splice(queued, 1)[0]);
    return new Promise((resolve, reject) => {
      const waiter = { predicate, resolve, reject, timer: null };
      waiter.timer = setTimeout(() => {
        const index = waiters.indexOf(waiter);
        if (index >= 0) waiters.splice(index, 1);
        reject(new Error(`MCP roots test timed out. stderr=${stderr}`));
      }, 10000);
      waiters.push(waiter);
    });
  }

  sendMessage({
    jsonrpc: '2.0',
    id: 1,
    method: 'initialize',
    params: {
      protocolVersion: '2025-06-18',
      capabilities: { roots: { listChanged: true }, elicitation: {} },
      clientInfo: { name: 'roots-test', version: '1' },
    },
  });
  await waitFor((message) => message.id === 1);
  sendMessage({ jsonrpc: '2.0', method: 'notifications/initialized' });
  const rootsRequest = await waitFor((message) => message.method === 'roots/list');
  sendMessage({
    jsonrpc: '2.0',
    id: 2,
    method: 'tools/call',
    params: { name: 'i_bootstrap', arguments: {} },
  });
  sendMessage({
    jsonrpc: '2.0',
    id: 5,
    method: 'tools/call',
    params: {
      name: 'i_close_session',
      arguments: {
        session_id: 'roots-session-0001',
        idempotency_key: 'roots-session-0001:closeout-v1',
        summary: 'roots_bound_closeout_marker',
        decisions: [],
        open_loops: [],
        artifact_refs: ['PROJECT_STATE.md'],
      },
    },
  });
  sendMessage({
    jsonrpc: '2.0',
    id: rootsRequest.id,
    result: { roots: [{ uri: pathToFileURL(env.alpha).href, name: 'alpha' }] },
  });
  const bootstrap = await waitFor((message) => message.id === 2);
  const closeout = await waitFor((message) => message.id === 5);
  sendMessage({
    jsonrpc: '2.0',
    id: 6,
    method: 'tools/call',
    params: { name: 'i_bootstrap', arguments: {} },
  });
  const resumed = await waitFor((message) => message.id === 6);
  sendMessage({
    jsonrpc: '2.0',
    id: 3,
    method: 'tools/call',
    params: { name: 'i_get_project_overview', arguments: {} },
  });
  const elicitation = await waitFor((message) => message.method === 'elicitation/create');
  sendMessage({
    jsonrpc: '2.0',
    id: elicitation.id,
    result: { action: 'accept', content: { confirmed: true } },
  });
  const overview = await waitFor((message) => message.id === 3);
  sendMessage({
    jsonrpc: '2.0',
    id: 4,
    method: 'tools/call',
    params: { name: 'i_get_project_overview', arguments: {} },
  });
  const declinedElicitation = await waitFor((message) => message.method === 'elicitation/create');
  sendMessage({
    jsonrpc: '2.0',
    id: declinedElicitation.id,
    result: { action: 'decline' },
  });
  const declined = await waitFor((message) => message.id === 4);
  sendMessage({
    jsonrpc: '2.0',
    id: 7,
    method: 'tools/call',
    params: { name: 'i_get_recent_activity', arguments: {} },
  });
  const activityElicitation = await waitFor((message) => message.method === 'elicitation/create');
  sendMessage({
    jsonrpc: '2.0',
    id: activityElicitation.id,
    result: { action: 'accept', content: { confirmed: true } },
  });
  const recentActivity = await waitFor((message) => message.id === 7);
  sendMessage({ jsonrpc: '2.0', method: 'notifications/roots/list_changed' });
  const changedRootsRequest = await waitFor((message) => message.method === 'roots/list');
  sendMessage({
    jsonrpc: '2.0',
    id: changedRootsRequest.id,
    result: {
      roots: [
        { uri: pathToFileURL(env.beta).href, name: 'beta' },
        { uri: pathToFileURL(env.alpha).href, name: 'alpha' },
      ],
    },
  });
  sendMessage({
    jsonrpc: '2.0',
    id: 8,
    method: 'tools/call',
    params: {
      name: 'i_close_session',
      arguments: {
        session_id: 'ambiguous-session-0001',
        idempotency_key: 'ambiguous-session-0001:closeout-v1',
        summary: 'must_not_be_written_to_either_project',
      },
    },
  });
  const ambiguousCloseout = await waitFor((message) => message.id === 8);
  child.stdin.end();
  await new Promise((resolve) => child.once('close', resolve));

  assert.equal(bootstrap.result.structuredContent.active_project.project_key, 'alpha');
  assert.equal(bootstrap.result.structuredContent.client_context.workspace_root_source, 'mcp_roots');
  assert.equal(bootstrap.result.structuredContent.client_context.roots_resolution, 'valid');
  assert.equal(bootstrap.result.structuredContent.client_context.elicitation_supported, true);
  assert.equal(closeout.result.structuredContent.persisted, true);
  assert.equal(closeout.result.structuredContent.event.project_key, 'alpha');
  assert.equal(resumed.result.structuredContent.handoff_kind, 'tool_closeout');
  assert.match(resumed.result.structuredContent.handoff.summary, /roots_bound_closeout_marker/);
  assert.equal(overview.result.structuredContent.authorized, true);
  assert.equal(overview.result.structuredContent.project_count, 3);
  assert.equal(declined.result.structuredContent.authorized, false);
  assert.equal(declined.result.structuredContent.project_count, 0);
  assert.equal(recentActivity.result.structuredContent.authorized, true);
  assert.equal(recentActivity.result.structuredContent.activity_count, 1);
  assert.equal(recentActivity.result.structuredContent.activities[0].project_key, 'alpha');
  assert.equal(ambiguousCloseout.result.isError, true);
  assert.match(ambiguousCloseout.result.content[0].text, /requires one unambiguous MCP file root/);
});

test('stdio MCP lifecycle exposes multi-project tools and ignores spoofed client_id', async () => {
  const env = createEnvironment();
  const serverPath = fileURLToPath(new URL('./i_mcp_server.mjs', import.meta.url));
  const child = spawn(process.execPath, [serverPath], {
    cwd: env.alpha,
    env: {
      ...process.env,
      I_HOME: env.iHome,
      I_WORKSPACE_ROOT: env.alpha,
      I_CLIENT_ID: '',
    },
    stdio: ['pipe', 'pipe', 'pipe'],
    windowsHide: true,
  });
  let stdout = '';
  let stderr = '';
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  child.stderr.on('data', (chunk) => { stderr += chunk; });

  const requests = [
    { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'codex-test', version: '1' } } },
    { jsonrpc: '2.0', method: 'notifications/initialized' },
    { jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} },
    { jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'i_bootstrap', arguments: { client_id: 'spoofed-client' } } },
    { jsonrpc: '2.0', id: 4, method: 'tools/call', params: { name: 'i_get_project_overview', arguments: {} } },
  ];
  child.stdin.end(`${requests.map((request) => JSON.stringify(request)).join('\n')}\n`);

  const exitCode = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error(`MCP server timed out. stderr=${stderr}`));
    }, 10000);
    child.once('error', reject);
    child.once('close', (code) => {
      clearTimeout(timer);
      resolve(code);
    });
  });

  assert.equal(exitCode, 0, stderr);
  const responses = stdout.trim().split('\n').filter(Boolean).map((line) => JSON.parse(line));
  const byId = new Map(responses.map((response) => [response.id, response]));
  assert.equal(responses.length, 4);
  assert.equal(byId.get(1).result.serverInfo.version, '0.6.2');
  assert.deepEqual(byId.get(2).result.tools.map((tool) => tool.name), [
    'i_voice_context',
    'i_voice_turn',
    'i_voice_probe',
    'i_bootstrap',
    'i_get_project_state',
    'i_recall_project',
    'i_get_project_overview',
    'i_close_session',
    'i_get_recent_activity',
  ]);
  const voiceContextTool = byId.get(2).result.tools.find((tool) => tool.name === 'i_voice_context');
  assert.match(voiceContextTool.description, /老公，你在吗/);
  assert.doesNotMatch(voiceContextTool.description, /回来一下/);
  assert.match(voiceContextTool.description, /不接受单独“老公”/);
  assert.match(voiceContextTool.description, /零 assistant 输出/);
  assert.match(voiceContextTool.description, /commentary/);
  const voiceTurnTool = byId.get(2).result.tools.find((tool) => tool.name === 'i_voice_turn');
  assert.match(voiceTurnTool.description, /每一轮都必须直接调用/);
  assert.match(voiceTurnTool.description, /原样传入/);
  assert.match(voiceTurnTool.description, /[STATUS]/);
  assert.match(voiceTurnTool.description, /只发一次 final answer/);
  assert.match(voiceTurnTool.description, /不重读手机/);
  assert.match(voiceTurnTool.description, /speech_delivery_contract/);
  assert.match(byId.get(1).result.instructions.slice(0, 512), /i_voice_turn/);
  assert.match(byId.get(1).result.instructions.slice(0, 512), /commentary/);
  assert.match(byId.get(1).result.instructions.slice(0, 512), /零输出/);
  assert.equal(byId.get(3).result.structuredContent.identity_capsule.surface.client_id, 'codex-test');
  assert.equal(byId.get(3).result.structuredContent.active_project.project_key, 'alpha');
  assert.equal(byId.get(4).result.isError, true);
  assert.match(byId.get(4).result.content[0].text, /MCP elicitation support/);
});

test('MCP rejects closeout before initialization without touching activity storage', async () => {
  const env = createEnvironment();
  const serverPath = fileURLToPath(new URL('./i_mcp_server.mjs', import.meta.url));
  const child = spawn(process.execPath, [serverPath], {
    cwd: env.alpha,
    env: {
      ...process.env,
      I_HOME: env.iHome,
      I_WORKSPACE_ROOT: env.alpha,
      I_CLIENT_ID: 'codex',
    },
    stdio: ['pipe', 'pipe', 'pipe'],
    windowsHide: true,
  });
  let stdout = '';
  let stderr = '';
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  child.stdin.end(`${JSON.stringify({
    jsonrpc: '2.0',
    id: 1,
    method: 'tools/call',
    params: {
      name: 'i_close_session',
      arguments: {
        session_id: 'bypass-session-0001',
        idempotency_key: 'bypass-session-0001:closeout-v1',
        summary: 'must_not_persist_before_initialize',
      },
    },
  })}\n`);
  const exitCode = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error(`pre-initialize MCP test timed out. stderr=${stderr}`));
    }, 10000);
    child.once('error', reject);
    child.once('close', (code) => {
      clearTimeout(timer);
      resolve(code);
    });
  });
  assert.equal(exitCode, 0, stderr);
  const response = JSON.parse(stdout.trim());
  assert.equal(response.error.code, -32002);
  assert.match(response.error.message, /complete initialize/);
  assert.equal(existsSync(join(env.iHome, 'activity')), false);
});
