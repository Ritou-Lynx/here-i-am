import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {rmSync} from 'node:fs';
import path from 'node:path';
import {DOMAIN_SCHEMA_SQL} from './domain_schema.mjs';
import {ICoreStore} from './i_core_store.mjs';
import {createICoreServer} from './i_core_server.mjs';
import {
  EXPENSE_DOMAIN,
  EXPENSE_HOOK_VERSION,
  EXPENSE_SCHEMA,
  FOOD_PHONE_PRINCIPAL_ID,
  FOOD_WRITER_PRINCIPAL_ID,
  claimFoodPhoneCredential,
  createRuntimeDomainHooks,
  foodPrincipalConfigs,
  ledgerPrincipalConfigs,
  provisionExpenseDomain,
  provisionFoodDomain,
  validateExpenseRecord,
} from './personal_data_domains.mjs';
import {enableExpenseLedger} from './release_schema6/lifecycle/runtime_child.mjs';
import {foodMemory, foodNow, foodOperation} from './test_fixtures/release_schema6/n2a_food.mjs';
import {syntheticRoot} from './test_fixtures/release_schema6/synthetic_paths.mjs';

const expense = (overrides = {}) => ({
  spent_at: '2026-10-25T12:30:00+08:00',
  local_date: '2026-10-25',
  amount_cny: 32.5,
  ai_amount_cny: 0,
  item: '合成午饭',
  category: 'food',
  note: '',
  source_frontend: 'claude_web',
  voided: false,
  ...overrides,
});

const expenseOperation = (nodeId, kind = 'create', overrides = {}) => ({
  domain_protocol_version: 1, core_instance_id: nodeId, schema_version: 1, op_id: randomUUID(), kind,
  id: randomUUID(), base_revision: kind === 'create' ? 0 : 1, created_at: new Date(foodNow).toISOString(),
  expires_at: new Date(foodNow + 86400000).toISOString(), actor: 'agent_inferred',
  ...(kind === 'create' ? {data: expense(), provenance: {source: 'synthetic_expense', source_refs: [], import_batch_id: null}} : {}),
  ...overrides,
});

const memory = t => foodMemory(t, {domainHooks: createRuntimeDomainHooks({writerPrincipalIds: [FOOD_WRITER_PRINCIPAL_ID]})});
const storedConfig = (domains, id) => JSON.parse(domains.db.prepare('SELECT config_json FROM domain_principals WHERE principal_id=?').get(id).config_json);

test('validateExpenseRecord accepts exact records and rejects drift', () => {
  const id = randomUUID();
  assert.equal(validateExpenseRecord({id, data: expense()}), true);
  assert.equal(validateExpenseRecord({id, data: expense({ai_amount_cny: 32.5})}), true);
  for (const data of [
    expense({amount_cny: 0}),
    expense({amount_cny: 1.234}),
    expense({amount_cny: 1000000.01}),
    expense({ai_amount_cny: 40}),
    expense({ai_amount_cny: -1}),
    expense({item: '   '}),
    expense({item: 'x'.repeat(201)}),
    expense({category: 'luxury'}),
    expense({source_frontend: 'sesame'}),
    expense({local_date: '2026-02-30'}),
    expense({spent_at: '2026-10-25'}),
    expense({voided: 'no'}),
    {...expense(), extra: true},
  ]) assert.equal(validateExpenseRecord({id, data}), false, JSON.stringify(data));
  const missing = expense();
  delete missing.note;
  assert.equal(validateExpenseRecord({id, data: missing}), false);
});

test('provisionExpenseDomain waits for food, then registers and widens scopes once without rotating tokens', t => {
  const {domains} = memory(t);
  assert.deepEqual(provisionExpenseDomain(domains), {status: 'not_food_provisioned', registered: false, upgraded: []});
  assert.equal(domains.db.prepare('SELECT 1 FROM domain_registry WHERE domain=?').get(EXPENSE_DOMAIN), undefined);

  const issued = provisionFoodDomain(domains).issued;
  const generations = () => domains.db.prepare('SELECT principal_id,generation FROM domain_principals ORDER BY principal_id').all()
    .map(row => ({...row}));
  const before = generations();
  assert.deepEqual(provisionExpenseDomain(domains), {status: 'provisioned', registered: true, upgraded: ['writer', 'phone']});
  assert.deepEqual(generations(), before);
  const current = domains.domain(EXPENSE_DOMAIN);
  assert.equal(current.mode, 'authoritative');
  assert.equal(current.requiredHooksVersion, EXPENSE_HOOK_VERSION);
  assert.deepEqual(current.schema, EXPENSE_SCHEMA);
  const ledger = ledgerPrincipalConfigs();
  assert.deepEqual(storedConfig(domains, FOOD_WRITER_PRINCIPAL_ID).scopes, ledger.writer.scopes);
  assert.deepEqual(storedConfig(domains, FOOD_PHONE_PRINCIPAL_ID).scopes, ledger.phone.scopes);
  assert.deepEqual(provisionExpenseDomain(domains), {status: 'provisioned', registered: false, upgraded: []});

  const writer = domains.authenticate(issued.writer);
  const phone = domains.authenticate(issued.phone);
  const created = domains.submit(writer, EXPENSE_DOMAIN, expenseOperation(domains.nodeId));
  assert.equal(created.status, 201, JSON.stringify(created));
  assert.equal(domains.getRecord(phone, EXPENSE_DOMAIN, created.body.record.id, domains.nodeId).status, 200);
  assert.equal(domains.submit(phone, EXPENSE_DOMAIN, expenseOperation(domains.nodeId)).status, 403);
  assert.equal(domains.submit(writer, 'food_entries', {...foodOperation({store: {nodeId: domains.nodeId}})}).status, 201);
});

test('food re-provision and phone claims keep the widened ledger scopes', t => {
  const {domains} = memory(t);
  provisionFoodDomain(domains);
  provisionExpenseDomain(domains);
  const rotated = provisionFoodDomain(domains, {rotate: ['writer']}).issued;
  assert.deepEqual(storedConfig(domains, FOOD_WRITER_PRINCIPAL_ID), ledgerPrincipalConfigs().writer);
  const claim = claimFoodPhoneCredential(domains);
  assert.deepEqual(storedConfig(domains, FOOD_PHONE_PRINCIPAL_ID), ledgerPrincipalConfigs().phone);
  const created = domains.submit(domains.authenticate(rotated.writer), EXPENSE_DOMAIN, expenseOperation(domains.nodeId));
  assert.equal(created.status, 201, JSON.stringify(created));
  assert.equal(domains.getRecord(domains.authenticate(claim.token), EXPENSE_DOMAIN, created.body.record.id, domains.nodeId).status, 200);
});

test('provisionExpenseDomain refuses foreign principal configs and conflicting registrations atomically', t => {
  const {domains} = memory(t);
  provisionFoodDomain(domains);
  domains.db.prepare('UPDATE domain_principals SET config_json=? WHERE principal_id=?')
    .run(JSON.stringify({...foodPrincipalConfigs().phone, scopes: ['food_entries:read', 'captures:read']}), FOOD_PHONE_PRINCIPAL_ID);
  assert.throws(() => provisionExpenseDomain(domains), {code: 'expense_principal_conflict'});
  assert.equal(domains.db.prepare('SELECT 1 FROM domain_registry WHERE domain=?').get(EXPENSE_DOMAIN), undefined);
  assert.deepEqual(storedConfig(domains, FOOD_WRITER_PRINCIPAL_ID), foodPrincipalConfigs().writer);

  const other = memory(t).domains;
  provisionFoodDomain(other);
  other.registerDomain(EXPENSE_DOMAIN, structuredClone(EXPENSE_SCHEMA), {mode: 'off', requiredHooksVersion: EXPENSE_HOOK_VERSION});
  assert.throws(() => provisionExpenseDomain(other), {code: 'expense_domain_conflict'});
});

test('expense hooks allow writer create/patch/void of its own records only', t => {
  const {domains} = memory(t);
  const issued = provisionFoodDomain(domains).issued;
  provisionExpenseDomain(domains);
  const writer = domains.authenticate(issued.writer);
  const created = domains.submit(writer, EXPENSE_DOMAIN, expenseOperation(domains.nodeId));
  const id = created.body.record.id;
  const patched = domains.submit(writer, EXPENSE_DOMAIN, expenseOperation(domains.nodeId, 'patch', {id, patch: {amount_cny: 30, item: '改过的午饭'}}));
  assert.equal(patched.status, 201, JSON.stringify(patched));
  const voided = domains.submit(writer, EXPENSE_DOMAIN, expenseOperation(domains.nodeId, 'patch', {id, base_revision: 2, patch: {voided: true}}));
  assert.equal(voided.status, 201);
  assert.equal(voided.body.record.data.voided, true);
  assert.equal(domains.submit(writer, EXPENSE_DOMAIN, expenseOperation(domains.nodeId, 'delete', {id, base_revision: 3})).status, 403);
  assert.equal(domains.submit(writer, EXPENSE_DOMAIN, expenseOperation(domains.nodeId, 'create', {actor: 'user_via_agent'})).status, 403);
  const invalid = domains.submit(writer, EXPENSE_DOMAIN, expenseOperation(domains.nodeId, 'patch', {id, base_revision: 3, patch: {ai_amount_cny: 99}}));
  assert.equal(invalid.status, 400);
});

test('enableExpenseLedger writes numbered receipts and reports conflicts without throwing', t => {
  const {domains} = memory(t);
  const receipts = [];
  const core = {store: {domains}};
  const writeReceipt = (name, value) => receipts.push([name, value]);
  enableExpenseLedger({core, writeReceipt, now: () => foodNow});
  provisionFoodDomain(domains);
  enableExpenseLedger({core, writeReceipt, now: () => foodNow});
  enableExpenseLedger({core, writeReceipt: () => { throw new Error('exists'); }, now: () => foodNow});
  assert.equal(receipts.length, 2);
  assert.notEqual(receipts[0][0], receipts[1][0]);
  assert.match(receipts[0][0], /^expense-receipt-\d+\.json$/);
  assert.equal(receipts[0][1].status, 'not_food_provisioned');
  assert.equal(receipts[1][1].status, 'provisioned');
  assert.deepEqual(receipts[1][1].upgraded, ['writer', 'phone']);
  assert.equal(receipts[1][1].hooks_version, EXPENSE_HOOK_VERSION);
  assert.equal(JSON.stringify(receipts).includes('token'), false);

  const conflicted = memory(t).domains;
  provisionFoodDomain(conflicted);
  conflicted.registerDomain(EXPENSE_DOMAIN, structuredClone(EXPENSE_SCHEMA), {mode: 'off', requiredHooksVersion: EXPENSE_HOOK_VERSION});
  const out = [];
  enableExpenseLedger({core: {store: {domains: conflicted}}, writeReceipt: (name, value) => out.push(value), now: () => foodNow});
  assert.equal(out[0].status, 'rejected_expense_domain_conflict');
});

test('HTTP: one writer token and one claimed phone token cover food and ledger', async t => {
  const root = syntheticRoot('expense-http-'), databasePath = path.join(root, 'core.sqlite');
  let core;
  t.after(async () => { if (core) await core.close(); rmSync(root, {recursive: true, force: true}); });
  new ICoreStore(databasePath, {activityEnabled: false, activityAutoActivate: false}).close();
  const db = new DatabaseSync(databasePath);
  try { db.exec('BEGIN IMMEDIATE'); db.exec(DOMAIN_SCHEMA_SQL); db.exec("UPDATE core_metadata SET value='6' WHERE key='schema_version';COMMIT"); } finally { db.close(); }
  core = createICoreServer({databasePath, clock: () => foodNow, pairingCode: 'synthetic-pairing-code',
    domainHooks: createRuntimeDomainHooks({writerPrincipalIds: [FOOD_WRITER_PRINCIPAL_ID]})});
  const {port} = await core.listen({host: '127.0.0.1', port: 0});
  const send = async (route, token, body) => {
    const response = await fetch(`http://127.0.0.1:${port}${route}`, {method: body ? 'POST' : 'GET', signal: AbortSignal.timeout(5000),
      headers: {connection: 'close', 'x-i-core-domain-protocol': '1', 'x-core-protocol': '0.1', authorization: `Bearer ${token}`,
        ...(body ? {'content-type': 'application/json'} : {})}, ...(body ? {body: JSON.stringify(body)} : {})});
    return {status: response.status, body: await response.json()};
  };
  const domains = core.store.domains;
  const issued = provisionFoodDomain(domains).issued;
  provisionExpenseDomain(domains);
  const nodeId = domains.nodeId;
  const base = `/v1/core/domains/${EXPENSE_DOMAIN}`;
  const created = await send(`${base}/ops`, issued.writer, expenseOperation(nodeId));
  assert.equal(created.status, 201, JSON.stringify(created.body));
  const id = created.body.record.id;
  assert.equal((await send(`${base}/ops`, issued.writer, expenseOperation(nodeId, 'patch', {id, patch: {voided: true}}))).status, 201);
  const snapshot = await send(`${base}/snapshot?core_instance_id=${nodeId}`, issued.phone);
  assert.equal(snapshot.status, 200, JSON.stringify(snapshot.body));
  assert.equal((await send(`${base}/ops`, issued.phone, expenseOperation(nodeId))).status, 403);
  assert.equal((await send('/v1/core/domains/food_entries/ops', issued.writer, foodOperation(core))).status, 201);
});
