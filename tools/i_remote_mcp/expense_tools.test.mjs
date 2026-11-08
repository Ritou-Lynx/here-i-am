import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {DatabaseSync} from 'node:sqlite';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {after, before, test} from 'node:test';
import {buildChatgptCandidate, REPO_ROOT} from './chatgpt_candidate.mjs';
import {EXPENSE_TOOLS, createExpenseTools, loadExpenseConfig} from './expense_tools.mjs';
import {DOMAIN_SCHEMA_SQL} from '../i_core/domain_schema.mjs';
import {ICoreStore} from '../i_core/i_core_store.mjs';
import {createICoreServer} from '../i_core/i_core_server.mjs';
import {FOOD_WRITER_PRINCIPAL_ID, createRuntimeDomainHooks, provisionExpenseDomain, provisionFoodDomain} from '../i_core/personal_data_domains.mjs';
import {createFakeReadModel, PASSPHRASE, PUBLIC_URL, pkcePair, registerClient, submitPassphrase, authorizeParams, postToken, initSession, mcpPost} from './fixtures.mjs';
import {listenForFetch} from './fetch_test_listener.mjs';

const NOW = Date.parse('2026-11-07T12:30:45.678+08:00');
const root = join(REPO_ROOT, 'build', 'expense-test-' + randomUUID());
let built, candidate, candidateOauth;
before(async () => {
  mkdirSync(root, {recursive: true});
  built = buildChatgptCandidate({outputDirectory: join('build', 'expense-candidate-' + randomUUID())});
  const load = name => import(pathToFileURL(join(built.root, 'i_remote_mcp', name + '.mjs')));
  [candidate, candidateOauth] = await Promise.all([load('server'), load('oauth')]);
});
after(() => { rmSync(root, {recursive: true, force: true}); if (built) rmSync(built.outputRoot, {recursive: true, force: true}); });

async function core(t, {expense = true} = {}) {
  const dir = join(root, randomUUID()), databasePath = join(dir, 'core.sqlite');
  mkdirSync(dir, {recursive: true});
  let server;
  t.after(async () => { if (server) await server.close(); });
  new ICoreStore(databasePath, {activityEnabled: false, activityAutoActivate: false}).close();
  const db = new DatabaseSync(databasePath);
  try { db.exec('BEGIN IMMEDIATE'); db.exec(DOMAIN_SCHEMA_SQL); db.exec("UPDATE core_metadata SET value='6' WHERE key='schema_version';COMMIT"); } finally { db.close(); }
  server = createICoreServer({databasePath, clock: () => NOW, pairingCode: 'synthetic-pairing-code',
    domainHooks: createRuntimeDomainHooks({writerPrincipalIds: [FOOD_WRITER_PRINCIPAL_ID]})});
  const {port} = await server.listen({host: '127.0.0.1', port: 0});
  const tokens = provisionFoodDomain(server.store.domains).issued;
  if (expense) provisionExpenseDomain(server.store.domains);
  const origin = 'http://127.0.0.1:' + port;
  return {server, origin, tokens, nodeId: server.store.domains.nodeId,
    async record(id) {
      const response = await fetch(`${origin}/v1/core/domains/expense_entries/records/${id}?core_instance_id=${encodeURIComponent(server.store.domains.nodeId)}`,
        {headers: {authorization: 'Bearer ' + tokens.phone, 'x-i-core-domain-protocol': '1', connection: 'close'}});
      return (await response.json()).record;
    }};
}

function stateDir(t, real, {expenseConfig = {format: 'expense-v1'}} = {}) {
  const path = join(root, 'state-' + randomUUID());
  mkdirSync(path, {recursive: true});
  t.after(() => rmSync(path, {recursive: true, force: true}));
  if (real) writeFileSync(join(path, 'core-food.json'), JSON.stringify({format: 'core-food-v1', principal_id: 'food-mcp-writer',
    token: real.tokens.writer, core_instance_id: real.nodeId, time_zone: 'Asia/Shanghai'}));
  if (expenseConfig) writeFileSync(join(path, 'expense.json'), JSON.stringify(expenseConfig));
  return path;
}

const callbacks = {claude_web: 'https://claude.ai/api/mcp/auth_callback', chatgpt_web: 'https://chatgpt.com/connector_platform_oauth_redirect',
  antigravity: 'http://127.0.0.1:32014/oauth/callback', gemini_web: 'https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-synthetic-expense',
  sesame: 'https://sesameai.app/api/oauth/external-mcp/callback'};
async function start(t, {state, coreUrl, frontend}) {
  candidateOauth.setPassphrase(state, PASSPHRASE);
  const app = candidate.createApp({stateDir: state, coreUrl, publicUrl: PUBLIC_URL, getReadModel: async () => createFakeReadModel(), now: () => NOW,
    chatgptEnabled: true, geminiEnabled: true, antigravityEnabled: true, sesameEnabled: true});
  await listenForFetch(app.server);
  t.after(() => new Promise(resolve => app.server.close(resolve)));
  const base = 'http://127.0.0.1:' + app.server.address().port, redirectUri = callbacks[frontend];
  const registered = await registerClient(base, [redirectUri]); assert.equal(registered.status, 201);
  const {verifier, challenge} = pkcePair();
  const auth = await submitPassphrase(base, {...Object.fromEntries(authorizeParams({clientId: registered.body.client_id, challenge})), redirect_uri: redirectUri, scope: 'i.read i.write'});
  assert.equal(auth.status, 302);
  const token = await postToken(base, {grant_type: 'authorization_code', code: new URL(auth.headers.get('location')).searchParams.get('code'),
    client_id: registered.body.client_id, redirect_uri: redirectUri, code_verifier: verifier, resource: PUBLIC_URL + '/mcp'});
  assert.equal(token.status, 200);
  const {init, sessionId} = await initSession(base, token.body.access_token); assert.equal(init.status, 200);
  let id = 2;
  const rpc = async (method, params) => {
    const response = await mcpPost(base, token.body.access_token, {jsonrpc: '2.0', id: id++, method, params}, {sessionId});
    assert.equal(response.status, 200); return response.body;
  };
  return {rpc, call: async (name, args) => (await rpc('tools/call', {name, arguments: args})).result};
}

test('E1 candidate inlines expense_tools.mjs verbatim with node-only imports', () => {
  const server = readFileSync(join(built.root, 'i_remote_mcp', 'server.mjs'), 'utf8').replaceAll('\r\n', '\n');
  const source = readFileSync(new URL('./expense_tools.mjs', import.meta.url), 'utf8').replaceAll('\r\n', '\n');
  assert.equal(server.split(source.trimEnd()).length, 2, 'expense_tools.mjs must appear exactly once, byte for byte');
  assert.deepEqual(candidate.EXPENSE_TOOLS, EXPENSE_TOOLS);
  assert.doesNotMatch(source, /domain_tools|personal_data_domains|coreRemember|domain-config/);
  const imports = [...source.matchAll(/(?:from\s*|import\s*\()(['"])([^'"]+)\1/g)].map(match => match[2]);
  assert.deepEqual(imports, ['node:fs', 'node:path']);
});

test('E1 four frontends add, retry, update, void and read expenses against a real Core; Sesame gets none', {timeout: 90000}, async t => {
  const real = await core(t);
  const state = stateDir(t, real);
  for (const frontend of ['claude_web', 'chatgpt_web', 'gemini_web', 'antigravity']) {
    const app = await start(t, {state, coreUrl: real.origin, frontend});
    const listed = (await app.rpc('tools/list')).result.tools;
    for (const tool of EXPENSE_TOOLS) {
      const actual = listed.find(item => item.name === tool.name);
      assert.ok(actual, frontend + ' lists ' + tool.name);
      assert.equal(actual.description, tool.description); assert.deepEqual(actual.inputSchema, tool.inputSchema);
    }
    assert.ok(listed.some(tool => tool.name === 'food_log'), 'food stays listed');
    const id = randomUUID();
    const add = {action: 'add', op_id: randomUUID(), id, entry: {amount_cny: 25.5, item: '午饭 黄焖鸡', category: 'food'}};
    const added = await app.call('expense_log', add);
    assert.equal(added.isError, false, JSON.stringify(added.structuredContent));
    assert.equal(added.structuredContent.revision, 1);
    assert.equal(added.structuredContent.local_date, '2026-11-07');
    assert.equal(added.structuredContent.ai_amount_cny, 0);
    assert.deepEqual((await app.call('expense_log', add)).structuredContent, added.structuredContent, 'identical retry is idempotent');
    const conflict = await app.call('expense_log', {...add, entry: {...add.entry, amount_cny: 30}});
    assert.equal(conflict.isError, true); assert.equal(conflict.structuredContent.error.code, 'idempotency_conflict');
    let record = await real.record(id);
    assert.equal(record.data.spent_at, '2026-11-07T12:30:45+08:00');
    assert.equal(record.data.source_frontend, frontend);
    assert.ok(Object.values(record.field_meta).every(field => field.actor === 'agent_inferred'));

    const updated = await app.call('expense_log', {action: 'update', op_id: randomUUID(), id, base_revision: 1,
      entry: {amount_cny: 28, ai_amount_cny: 10, item: '午饭 黄焖鸡加饭', category: 'food', note: '林埃请一半'}});
    assert.equal(updated.isError, false, JSON.stringify(updated.structuredContent));
    record = await real.record(id);
    assert.equal(record.data.spent_at, '2026-11-07T12:30:45+08:00', 'update without spent_at keeps the original time');
    assert.equal(record.data.ai_amount_cny, 10); assert.equal(record.data.source_frontend, frontend);

    const moved = await app.call('expense_log', {action: 'update', op_id: randomUUID(), id, base_revision: 2,
      entry: {amount_cny: 28, ai_amount_cny: 10, item: '午饭 黄焖鸡加饭', category: 'food', spent_at: '2026-11-06T00:30:00+08:00'}});
    assert.equal(moved.structuredContent.local_date, '2026-11-06', 'plain local day, no 04:00 shift');

    const day = await app.call('expense_day', {date: '2026-11-06'});
    assert.equal(day.isError, false);
    assert.ok(day.structuredContent.entries.some(row => row.id === id && row.amount_cny === 28 && row.source_frontend === frontend));
    const voided = await app.call('expense_log', {action: 'void', op_id: randomUUID(), id, base_revision: 3});
    assert.equal(voided.isError, false); assert.equal(voided.structuredContent.voided, true);
    assert.equal((await app.call('expense_day', {date: '2026-11-06'})).structuredContent.entries.some(row => row.id === id), false);
    assert.equal((await real.record(id)).data.item, '午饭 黄焖鸡加饭', 'void keeps the record content');

    const tooMuchAi = await app.call('expense_log', {action: 'add', op_id: randomUUID(), id: randomUUID(), entry: {amount_cny: 5, ai_amount_cny: 6, item: '奶茶', category: 'food'}});
    assert.equal(tooMuchAi.isError, true); assert.equal(tooMuchAi.structuredContent.error.code, 'invalid_expense_ai_amount');
    const forged = await app.call('expense_log', {...add, op_id: randomUUID(), id: randomUUID(), entry: {...add.entry, source_frontend: 'sesame'}});
    assert.equal(forged.isError, true); assert.equal(forged.structuredContent.error.code, 'expense_field_not_allowed');
  }
  const sesame = await start(t, {state, coreUrl: real.origin, frontend: 'sesame'});
  assert.equal((await sesame.rpc('tools/list')).result.tools.some(tool => tool.name.startsWith('expense_')), false);
  assert.equal((await sesame.rpc('tools/call', {name: 'expense_log', arguments: {}})).error.code, -32602);
});

test('E1 tools need both expense.json and the food credential; expense.json is exact', {timeout: 60000}, async t => {
  const real = await core(t);
  for (const state of [stateDir(t, real, {expenseConfig: null}), stateDir(t, null)]) {
    const app = await start(t, {state, coreUrl: real.origin, frontend: 'claude_web'});
    assert.equal((await app.rpc('tools/list')).result.tools.some(tool => tool.name.startsWith('expense_')), false);
  }
  for (const value of [{format: 'expense-v2'}, {format: 'expense-v1', extra: true}, [], 'expense-v1']) {
    const state = stateDir(t, real, {expenseConfig: value});
    assert.throws(() => candidate.createApp({stateDir: state, publicUrl: PUBLIC_URL, getReadModel: async () => ({})}), /^Error: expense_config_invalid$/);
    assert.throws(() => loadExpenseConfig(state), /expense_config_invalid/);
  }
  const bom = stateDir(t, real, {expenseConfig: null});
  writeFileSync(join(bom, 'expense.json'), '﻿{"format":"expense-v1"}');
  assert.deepEqual(loadExpenseConfig(bom), {format: 'expense-v1'});
});

test('E1 Core without the expense domain returns a clear error instead of a false success', {timeout: 30000}, async t => {
  const real = await core(t, {expense: false});
  const app = await start(t, {state: stateDir(t, real), coreUrl: real.origin, frontend: 'chatgpt_web'});
  const result = await app.call('expense_log', {action: 'add', op_id: randomUUID(), id: randomUUID(), entry: {amount_cny: 3, item: '地铁', category: 'transport'}});
  assert.equal(result.isError, true);
  assert.notEqual(result.structuredContent.outcome, 'accepted');
});

test('E1 handler validation and timestamps without a Core', async () => {
  const submitted = [];
  const client = {
    operation: async () => ({http_status: 404}),
    submit: async intent => { submitted.push(intent); return {outcome: 'accepted', record: {id: intent.id, revision: 1, data: intent.data}}; },
    snapshot: async () => ({http_status: 200, records: [], manifest: {base_cursor: 'c'}, snapshot_id: 's'}),
    acknowledge: async () => ({}),
  };
  const {handlers} = createExpenseTools({client, frontend: 'gemini_web', now: () => Date.parse('2026-11-06T16:10:00Z')});
  const ok = await handlers.expense_log({action: 'add', op_id: randomUUID(), id: randomUUID(), entry: {amount_cny: 12.345, item: ' 早餐 ', category: 'food'}});
  assert.equal(ok.local_date, '2026-11-07');
  assert.equal(submitted[0].data.spent_at, '2026-11-07T00:10:00+08:00');
  assert.equal(submitted[0].data.amount_cny, 12.35);
  assert.equal(submitted[0].data.item, '早餐');
  assert.equal(submitted[0].data.source_frontend, 'gemini_web');
  assert.equal(submitted[0].provenance.source, 'expense_log');
  const bad = async (args, code) => assert.rejects(handlers.expense_log(args), error => error.message === code);
  const base = {action: 'add', op_id: randomUUID(), id: randomUUID(), entry: {amount_cny: 1, item: 'x', category: 'food'}};
  await bad({...base, action: 'remove'}, 'invalid_action');
  await bad({...base, id: base.op_id}, 'invalid_id');
  await bad({...base, base_revision: 1}, 'invalid_base');
  await bad({...base, action: 'update'}, 'invalid_base');
  await bad({...base, action: 'void', base_revision: 1}, 'invalid_request');
  await bad({...base, entry: {...base.entry, category: 'luxury'}}, 'invalid_expense_category');
  await bad({...base, entry: {...base.entry, amount_cny: 0}}, 'invalid_expense_amount');
  await bad({...base, entry: {...base.entry, spent_at: '2026-11-07'}}, 'invalid_expense_time');
  await bad({...base, entry: {...base.entry, item: '  '}}, 'invalid_expense_item');
  await bad({...base, extra: 1}, 'expense_field_not_allowed');
  await assert.rejects(handlers.expense_day({date: '2026-02-30'}), error => error.message === 'invalid_expense_date');
  assert.deepEqual(await handlers.expense_day({}), {date: '2026-11-07', entries: [], count: 0, total_cny: 0, ai_total_cny: 0});
  assert.throws(() => createExpenseTools({client, frontend: 'sesame'}), /invalid_expense_configuration/);
});
