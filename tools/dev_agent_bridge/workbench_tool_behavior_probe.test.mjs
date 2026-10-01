import test from 'node:test';
import assert from 'node:assert/strict';
import { toolCall, outputFor, classifyOutput, classifyCase, restrictions, assertIsolation, question } from './workbench_tool_behavior_probe.mjs';

test('freeform and JSON calls preserve runtime namespace and distinct wire payloads', () => {
  const exec = toolCall('functions', 'exec', 'text(6 * 7);');
  assert.equal(exec.type, 'custom_tool_call'); assert.equal(exec.namespace, 'functions');
  assert.equal(exec.input, 'text(6 * 7);'); assert.equal(exec.arguments, undefined);
  const wait = toolCall('functions', 'wait', { cell_id: 'actual_returned_id' });
  assert.equal(wait.type, 'function_call'); assert.deepEqual(JSON.parse(wait.arguments), { cell_id: 'actual_returned_id' });
  assert.equal(question.questions.length, 1); assert.equal(question.questions[0].options.length, 2);
});
test('an echoed call, ordinary message or different call ID cannot become tool execution evidence', () => {
  const body = { input: [toolCall('functions', 'exec', 'text(42);'),
    { type: 'message', call_id: 'probe_call', output: '42' },
    { type: 'custom_tool_call_output', call_id: 'other', output: '42' }] };
  assert.deepEqual(outputFor(body, 'probe_call'), []);
  assert.equal(classifyOutput([]), 'insufficient_evidence');
});
test('runtime rejection, parser error and successful execution are separate results', () => {
  const output = value => [{ call_id: 'probe_call', output: value }];
  assert.equal(classifyOutput(output('code-mode host is disabled')), 'explicit_runtime_rejection');
  assert.equal(classifyOutput(output('request_user_input is unavailable in Default mode')), 'explicit_runtime_rejection');
  assert.equal(classifyOutput(output('SyntaxError: Unexpected token ;')), 'parse_or_argument_error');
  assert.equal(classifyOutput(output('unknown tool: exec')), 'dispatch_error');
  assert.equal(classifyOutput(output('unsupported call: collaborationlist_agents')), 'dispatch_error');
  assert.equal(classifyCase({ name: 'dynamic_positive', outputs: output('SYNTHETIC_ECHO_42') }), 'observed_output_requires_review');
  assert.equal(classifyCase({ name: 'dynamic_positive', positive_control_dispatched: true, outputs: output('SYNTHETIC_ECHO_42') }), 'actual_tool_execution');
});
test('list and wait success need their actual structured result, not quoted expected text', () => {
  assert.equal(classifyCase({ name: 'excluded_list_agents', outputs: [{ call_id: 'probe_call', output: '{"agents":[{"agent_name":"/root","agent_status":"running"}]}' }] }), 'actual_tool_execution');
  assert.notEqual(classifyCase({ name: 'excluded_list_agents', outputs: [{ call_id: 'probe_call', output: 'expected /root running' }] }), 'actual_tool_execution');
  const report = { name: 'enabled_exec_wait_control', real_cell_id: '1', outputs: [{ call_id: 'probe_wait', output: [{ text: 'Script completed\n' }, { text: '42' }] }] };
  assert.equal(classifyCase(report), 'actual_tool_execution');
  delete report.real_cell_id;
  assert.notEqual(classifyCase(report), 'actual_tool_execution');
});
test('control changes only the two host settings, all excluded restrictions are retained', () => {
  const excluded = restrictions(); const control = restrictions(true);
  assert.deepEqual(Object.keys(control).filter(k => JSON.stringify(control[k]) !== JSON.stringify(excluded[k])), ['features.code_mode_host', 'features.code_mode.enabled']);
  assert.deepEqual(excluded['features.code_mode.excluded_tool_namespaces'], ['functions', 'collaboration', 'skills', 'clock', 'web']);
  assert.equal(excluded['features.multi_agent'], false); assert.equal(excluded['features.shell_tool'], false);
});
function isolatedConfig() {
  return { config: { model_provider: 'synthetic_probe', model_providers: { synthetic_probe: {
    base_url: 'http://127.0.0.1:12345/v1', requires_openai_auth: false } }, mcp_servers: {}, hooks: {} },
  layers: [{ name: { type: 'system' }, config: {} }, { name: { type: 'user' }, config: {} }, { name: { type: 'sessionFlags' }, config: {} }] };
}
test('real provider and authentication requirements are rejected before thread creation', () => {
  const config = isolatedConfig();
  assert.doesNotThrow(() => assertIsolation(config, null, 'http://127.0.0.1:12345/v1'));
  assert.throws(() => assertIsolation(config, null, 'https://api.openai.com/v1'), /Non-loopback/);
  config.config.model_providers.synthetic_probe.requires_openai_auth = true;
  assert.throws(() => assertIsolation(config, null, 'http://127.0.0.1:12345/v1'), /mismatch/);
});
test('nonempty config layers, managed requirements, MCP and hooks fail closed', () => {
  const url = 'http://127.0.0.1:12345/v1';
  assert.throws(() => assertIsolation(isolatedConfig(), { approval: 'external' }, url), /Managed/);
  for (const type of ['system', 'user', 'project', 'unknown']) {
    const config = isolatedConfig(); config.layers = [{ name: { type }, config: { extra: true } }];
    assert.throws(() => assertIsolation(config, null, url));
  }
  const mcp = isolatedConfig(); mcp.config.mcp_servers = { external: {} };
  assert.throws(() => assertIsolation(mcp, null, url), /MCP/);
  const hooks = isolatedConfig(); hooks.config.hooks = { before: ['external'] };
  assert.throws(() => assertIsolation(hooks, null, url), /hooks/);
});
