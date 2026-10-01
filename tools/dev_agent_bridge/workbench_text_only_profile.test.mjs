import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import test from 'node:test';
import { CodexAppServerAdapter } from './codex_app_server_adapter.mjs';
import { WORKBENCH_TEXT_ONLY_PROFILE, requireSupportedRuntimeProfile,
  workbenchTextOnlyAvailability } from './workbench_text_only_profile.mjs';
import { hasCompiledTool, inspectCompiledToolCatalog } from './workbench_text_only_probe_contract.mjs';

test('text-only start/resume reject before contacting any runtime or reusing a persona session', async () => {
  const client = new EventEmitter();
  let starts = 0;
  client.start = () => { starts++; throw new Error('Must not start'); };
  const adapter = new CodexAppServerAdapter({ client });
  adapter.providerSessions.set('persona-thread', 'persona-session');
  adapter.sessions.set('persona-session', { id: 'persona-session', status: 'idle' });
  const config = { runtime_profile: WORKBENCH_TEXT_ONLY_PROFILE,
    cwd: 'ignored', config: { 'features.shell_tool': true }, dynamic_tools: [{ name: 'shell' }],
    execution_profile_receipt: { isolation_verified: true } };
  for (const action of [() => adapter.startSession(config), () => adapter.resumeSession('persona-thread', config)]) {
    await assert.rejects(action, error => {
      assert.equal(error.code, 'unsupported_capability');
      assert.equal(error.retryable, false);
      assert.deepEqual(error.details, workbenchTextOnlyAvailability());
      return true;
    });
  }
  assert.equal(starts, 0);
  assert.equal(adapter.sessions.size, 1);
});

test('unknown, null, and misspelled explicit profiles cannot silently downgrade', () => {
  for (const runtime_profile of ['workbench_text_only_v0', '', null, 1]) {
    assert.throws(() => requireSupportedRuntimeProfile({ runtime_profile }, 'startSession'),
      error => error.code === 'invalid_request' && error.details.fail_closed === true);
  }
  assert.doesNotThrow(() => requireSupportedRuntimeProfile({ model: 'ordinary-model' }, 'startSession'));
});

test('profile availability never supplies a positive execution or stop receipt', () => {
  const first = workbenchTextOnlyAvailability();
  first.available = true;
  assert.equal(workbenchTextOnlyAvailability().available, false);
  assert.equal(Object.hasOwn(first, 'execution_profile_receipt'), false);
  assert.equal(Object.hasOwn(first, 'stop_receipt'), false);
});

test('probe detects tools carried only in input.additional_tools including code-mode namespaces', () => {
  const inspection = inspectCompiledToolCatalog({ model: 'synthetic', input: [
    { type: 'additional_tools', tools: [{ type: 'namespace', name: 'functions', tools: [
      { type: 'custom', name: 'exec', description: 'declare const tools: { synthetic_noop(args: {}): Promise<unknown>; };' },
    ] }] },
  ] });
  assert.equal(inspection.no_tools, false);
  assert.deepEqual(inspection.catalogs.map(catalog => catalog.names), [['functions'], ['exec']]);
  assert.deepEqual(inspection.code_mode_declarations[0].names, ['synthetic_noop']);
});

test('probe accepts explicit empty or absent catalogs only in a recognized request', () => {
  assert.equal(inspectCompiledToolCatalog({ model: 'synthetic', input: [], tools: [] }).no_tools, true);
  assert.equal(inspectCompiledToolCatalog({ model: 'synthetic', input: [] }).no_tools, true);
  assert.equal(inspectCompiledToolCatalog({ model: 'synthetic', input: [], tools: [{ type: 'web_search' }] }).no_tools, false);
  assert.throws(() => inspectCompiledToolCatalog({}), /unrecognized/);
  assert.throws(() => inspectCompiledToolCatalog({ model: 'synthetic', input: [], tools: null }), /Unrecognized/);
});

test('probe positive control must be in a compiled catalog, not ordinary text', () => {
  const textOnly = inspectCompiledToolCatalog({ model: 'synthetic',
    input: [{ type: 'message', content: 'synthetic_noop' }] });
  assert.equal(hasCompiledTool(textOnly, 'synthetic_noop'), false);
  const nested = inspectCompiledToolCatalog({ model: 'synthetic', input: [
    { type: 'additional_tools', tools: [{ name: 'synthetic_noop', type: 'function' }] },
  ] });
  assert.equal(hasCompiledTool(nested, 'synthetic_noop'), true);
  const declaration = inspectCompiledToolCatalog({ model: 'synthetic', input: [
    { type: 'additional_tools', tools: [{ name: 'exec',
      description: 'declare const tools: { synthetic_noop(args: {}): Promise<unknown>; };' }] },
  ] });
  assert.equal(hasCompiledTool(declaration, 'synthetic_noop'), true);
  assert.equal(hasCompiledTool({ no_tools: false, error: 'unrecognized' }, 'synthetic_noop'), false);
});
