import assert from 'node:assert/strict';
import test from 'node:test';
import { WorkbenchProductHostBinding, isWorkbenchProductHostBinding, readWorkbenchProductRequest } from './workbench_product_host_binding.mjs';

const scope = 'a'.repeat(64);
const task = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
const tool = { name: 'manage_long_task_queue', description: 'bounded queue tool', input_schema: { type: 'object', additionalProperties: false } };
const transport = async ({ method, path }) => {
  if (method === 'POST' && path.endsWith('/sessions')) return { session_id: 'session_one', status: 'idle', provider_metadata: { provider: 'codex', provider_session_id: 'provider_one' } };
  if (method === 'DELETE') return { session_id: 'session_one', status: 'closed', provider_metadata: { provider: 'codex', provider_session_id: 'provider_one' }, stop_evidence: { local_binding_closed: true, provider_terminal_confirmed: false, turns: [] } };
  throw new Error('unexpected_transport');
};
const binding = () => new WorkbenchProductHostBinding({ conversationId: 'conversation_one', taskScopeHash: scope, dynamicTool: tool, transport });
const register = (host, body = { task_id: task, scope_hash: scope, goal: 'finish this bounded task' }) => host.handle({ method: 'POST', body }, '/p6/r7/product/task');
const manifest = () => ({ task_id: task, execution_epoch: '33333333-3333-4333-8333-333333333333', execution_mode: 'isolated_text_only' });
const input = goal => 'Complete the following standalone text task using only the supplied text. Return the requested text result. No tools, outside data, product actions, files, shell, network or memory writes are available. If the task needs those, explain the limitation in the text result.\nTask goal:\n' + goal + '\n';

test('brands only constructed bindings and binds one exact task idempotently', async () => {
  const host = binding(); assert.equal(isWorkbenchProductHostBinding(host), true); assert.equal(isWorkbenchProductHostBinding({}), false);
  const first = await register(host); const repeat = await register(host);
  assert.equal(first.status, 200); assert.deepEqual(repeat.body, first.body); assert.doesNotMatch(JSON.stringify(first.body), /finish this bounded task/);
  assert.equal((await register(host, { task_id: other, scope_hash: scope, goal: 'finish this bounded task' })).status, 400);
  assert.equal((await register(host, { task_id: task, scope_hash: scope, goal: 'changed' })).status, 400);
  assert.equal((await register(host, { task_id: task, scope_hash: 'b'.repeat(64), goal: 'x' })).status, 400);
});

test('rejects foreign tasks and oversized goals without a network call', async () => {
  const host = binding();
  assert.equal((await register(host, { task_id: other, scope_hash: scope, goal: 'x'.repeat(4001) })).status, 400);
  assert.equal(host.permitsTextSession(manifest()), false);
  assert.equal((await register(host, { task_id: 'not-a-uuid', scope_hash: scope, goal: 'x' })).status, 400);
});

test('text permits only fixed formatter input and bounded previous text', async () => {
  const host = binding(); await register(host); const m = manifest(); const goal = 'finish this bounded task';
  assert.equal(host.permitsTextSession(m), true); assert.equal(host.permitsTextSession({ ...m, task_id: other }), false);
  assert.equal(host.permitsTextInput(m, input(goal)), true);
  const partial = input(goal) + '\nThis is a new execution attempt, not a resumed provider turn. Previously saved partial text follows; produce one complete final result:\nprior';
  assert.equal(host.permitsTextInput(m, partial), true);
  assert.equal(host.permitsTextInput(m, input('forged')), false);
  assert.equal(host.permitsTextInput(m, `${input(goal)}forged partial`), false);
  assert.equal(host.permitsTextInput(m, input(goal) + '\nThis is a new execution attempt, not a resumed provider turn. Previously saved partial text follows; produce one complete final result:\n'), false);
});

test('strict request reader preserves only bounded decoded JSON', async () => {
  const request = source({ method: 'POST', headers: { 'content-type': 'application/json; charset=utf-8' },
    chunks: [Buffer.from('{"a"'), Buffer.from(':1}') ] });
  assert.deepEqual(await readWorkbenchProductRequest(request), { method: 'POST', body: { a: 1 } });
  assert.deepEqual(await readWorkbenchProductRequest(source({ method: 'GET', chunks: [] })), { method: 'GET' });
  await rejected(() => readWorkbenchProductRequest(source({ method: 'POST', headers: { 'content-type': 'application/json' }, chunks: [Buffer.alloc(64000), Buffer.alloc(1537)] })));
  await rejected(() => readWorkbenchProductRequest(source({ method: 'POST', headers: { 'content-type': 'application/json' }, chunks: [Buffer.from([0xc3])] })));
  await rejected(() => readWorkbenchProductRequest(source({ method: 'POST', headers: { 'content-type': 'application/json' }, chunks: [Buffer.from('{')] })));
  await rejected(() => readWorkbenchProductRequest(source({ method: 'POST', aborted: true, chunks: [Buffer.from('{}')] })));
  await rejected(() => readWorkbenchProductRequest(abortingSource()));
});

test('route rejects foreign paths, unsupported fields, and body overrun', async () => {
  const host = binding();
  assert.deepEqual(await host.handle({ method: 'GET' }, '/elsewhere'), { handled: false });
  assert.equal((await host.handle({ method: 'POST', body: { task_id: task, scope_hash: scope, goal: 'x', extra: true } }, '/p6/r7/product/task')).status, 400);
  assert.equal((await host.handle({ method: 'POST', body: { config: {}, context_manifest: {}, extra: true } }, '/p6/r7/product/conversation/experimental/v1/runtime/sessions')).status, 400);
  assert.equal((await host.handle({ method: 'POST', body: { task_id: task, scope_hash: scope, goal: 'x'.repeat(70000) } }, '/p6/r7/product/task')).status, 400);
});

test('ordinary route uses guardian wire shape through fake transport only', async () => {
  const host = binding();
  const started = await host.handle({ method: 'POST', body: {
    config: { ephemeral: false, service_name: 'here_i_am_workbench', dynamic_tools: [tool] },
    context_manifest: { conversation_id: 'conversation_one', profile: 'workbench', scope: 'desktop_chat' },
  } }, '/p6/r7/product/conversation/experimental/v1/runtime/sessions');
  assert.equal(started.status, 200); assert.equal(started.body.session_id, 'session_one');
  assert.equal((await host.handle({ method: 'GET' }, '/p6/r7/product/conversation/experimental/v1/runtime/sessions/session_one/events?after=0')).status, 400);
  assert.equal((await host.handle({ method: 'POST', body: {} }, '/p6/r7/product/conversation/experimental/v1/runtime/resume')).status, 400);
});

test('close fences registration and text while allowing exact repeated close', async () => {
  const host = binding(); await register(host); const closed = await host.handle({ method: 'POST', body: {} }, '/p6/r7/product/conversation/close');
  assert.equal(closed.status, 200); assert.equal((await host.handle({ method: 'POST', body: {} }, '/p6/r7/product/conversation/close')).status, 200);
  assert.deepEqual(closed.body, { status: 'closed', conversation_id: 'conversation_one',
    session_id: null, turn_ids: [], reason: null, shared_gateway_stopped: false });
  assert.equal(host.permitsTextSession(manifest()), false);
  assert.equal((await register(host)).status, 400);
  const snapshot = host.snapshot(); assert.equal(snapshot.task_id, task); assert.match(snapshot.goal_sha256, /^[0-9a-f]{64}$/); assert.doesNotMatch(JSON.stringify(snapshot), /finish this bounded task/);
});

function source({ method, headers = {}, chunks, aborted = false }) {
  return { method, headers, aborted, async *[Symbol.asyncIterator]() { yield* chunks; } };
}

function abortingSource() {
  return { method: 'POST', headers: { 'content-type': 'application/json' }, aborted: false,
    async *[Symbol.asyncIterator]() { yield Buffer.from('{}'); this.aborted = true; } };
}

async function rejected(operation) {
  await assert.rejects(operation, error => error?.code === 'product_request_rejected');
}
