import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { DomainStore, DOMAIN_POLICY } from './domain_store.mjs';
import { DOMAIN_SCHEMA_SQL } from './domain_schema.mjs';
import {
  FOOD_DOMAINS,
  FOOD_HOOK_VERSION,
  FOOD_SCHEMAS,
  createFoodDomainHooks,
  foodTotals,
  registerFoodDomains,
  validateFoodRecord,
} from './food_domains.mjs';

const now = Date.parse('2026-10-24T12:00:00.000Z');
const iso = new Date(now).toISOString();
const expires = new Date(now + DOMAIN_POLICY.intentTtl).toISOString();
const actions = ['read', 'create', 'patch', 'status', 'delete', 'restore', 'merge', 'purge'];

const item = (overrides = {}) => ({
  name: '合成米饭',
  food_ref: {source: 'model', id: null},
  grams: 150,
  grams_low: 120,
  grams_high: 180,
  kcal: 174.25,
  protein_g: 3.9,
  fat_g: 0.45,
  carb_g: 38.1,
  basis: 'model_guess',
  confidence: 'medium',
  ...overrides,
});

const entry = (overrides = {}) => {
  const items = overrides.items ?? [item()];
  return {
    eaten_at: '2026-10-24T19:05:00+08:00',
    local_date: '2026-10-24',
    meal: 'dinner',
    title: '合成晚餐',
    note: '',
    input_kind: 'text',
    items,
    totals: foodTotals(items),
    user_corrected: false,
    voided: false,
    ...overrides,
  };
};

function fixture(t, {mode = 'authoritative'} = {}) {
  const db = new DatabaseSync(':memory:');
  db.exec("CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT);INSERT INTO core_metadata VALUES('schema_version','6'),('node_id','food-core'),('cursor_secret','synthetic-food-secret');");
  db.exec(DOMAIN_SCHEMA_SQL);
  const store = new DomainStore(db, {
    nodeId: 'food-core',
    cursorSecret: 'synthetic-food-secret',
    clock: () => now,
    domainHooks: createFoodDomainHooks({writerPrincipalIds: ['writer', 'second-writer']}),
    verifyAuthorization: () => false,
  });
  registerFoodDomains(store, {mode});
  const principal = (principalId, actors = ['agent_inferred']) => {
    const issued = store.configurePrincipal({
      principal_id: principalId,
      device_id: `device-${principalId}`,
      installation_id: `install-${principalId}`,
      scopes: actions.map(action => `food_entries:${action}`),
      actors,
      trusted_interactive: actors.some(actor => ['user_direct', 'user_via_agent'].includes(actor)),
    });
    return store.authenticate(issued.token);
  };
  const writer = principal('writer', ['agent_inferred', 'user_direct', 'user_via_agent']);
  const secondWriter = principal('second-writer');
  const outsider = principal('outsider', ['agent_inferred', 'user_direct', 'user_via_agent']);
  const operation = (kind, overrides = {}) => ({
    domain_protocol_version: 1,
    core_instance_id: 'food-core',
    schema_version: 1,
    op_id: randomUUID(),
    kind,
    id: randomUUID(),
    base_revision: kind === 'create' ? 0 : 1,
    created_at: iso,
    expires_at: expires,
    actor: 'agent_inferred',
    ...(kind === 'create' ? {
      data: entry(),
      provenance: {source: 'synthetic_food', source_refs: [], import_batch_id: null},
    } : {}),
    ...overrides,
  });
  t.after(() => db.close());
  return {
    db,
    store,
    writer,
    secondWriter,
    outsider,
    operation,
    submit: (request, principalValue = writer) => store.submit(principalValue, 'food_entries', request),
  };
}

const reason = result => result.body.reason ?? result.body.error?.code;

test('exports schema and registration defaults the food domain off', t => {
  assert.equal(FOOD_HOOK_VERSION, 'food-v1');
  assert.deepEqual(FOOD_DOMAINS, ['food_entries']);
  assert.equal(FOOD_SCHEMAS.food_entries.version, 1);
  const f = fixture(t, {mode: 'off'});
  assert.equal(f.db.prepare("SELECT mode FROM domain_registry WHERE domain='food_entries'").get().mode, 'off');
  assert.equal(reason(f.submit(f.operation('create'))), 'domain_off');
});

test('foodTotals rounds each aggregate to one decimal including fractional carry', () => {
  const items = [
    item({grams: 3, grams_low: 1, grams_high: 4, kcal: 1.25, protein_g: 0.04, fat_g: 0.05, carb_g: 0.06}),
    item({grams: 2, grams_low: 1, grams_high: 3, kcal: 2.25, protein_g: 0.05, fat_g: 0.06, carb_g: 0.07}),
  ];
  assert.deepEqual(foodTotals(items), {
    kcal: 3.5,
    kcal_low: 1.5,
    kcal_high: 5,
    protein_g: 0.1,
    fat_g: 0.1,
    carb_g: 0.1,
  });
});

test('authorized agent_inferred principal creates, patches and voids its own record but cannot delete or use status', t => {
  const f = fixture(t);
  const created = f.submit(f.operation('create'));
  assert.equal(created.status, 201, JSON.stringify(created));
  assert.equal(created.body.record.origin.principal_id, 'writer');
  const id = created.body.record.id;

  const patchedData = entry({title: '修订后的合成晚餐'});
  const patched = f.submit(f.operation('patch', {id, base_revision: 1, patch: patchedData}));
  assert.equal(patched.status, 201, JSON.stringify(patched));
  assert.equal(patched.body.record.data.title, patchedData.title);

  const voided = f.submit(f.operation('patch', {id, base_revision: 2, patch: {voided: true}}));
  assert.equal(voided.status, 201, JSON.stringify(voided));
  assert.equal(voided.body.record.data.voided, true);

  const deletion = f.submit(f.operation('delete', {id, base_revision: 3}));
  assert.equal(deletion.status, 403);
  assert.equal(reason(deletion), 'actor_not_authorized');
  assert.equal(f.submit(f.operation('status', {id, base_revision: 3, patch: {voided: false}})).status, 403);
});

test('hooks reject unlisted principals, other actors and cross-principal patches, including lookup replay', t => {
  const f = fixture(t);
  assert.equal(f.submit(f.operation('create'), f.outsider).status, 403);
  const userViaAgent = f.operation('create', {actor: 'user_via_agent'});
  assert.equal(f.submit(userViaAgent).status, 403);

  const createRequest = f.operation('create');
  const created = f.submit(createRequest);
  assert.equal(created.status, 201, JSON.stringify(created));
  const crossPatch = f.operation('patch', {id: created.body.record.id, base_revision: 1, patch: {voided: true}});
  assert.equal(f.submit(crossPatch, f.secondWriter).status, 403);
  assert.equal(f.store.getOperation(f.writer, 'food_entries', createRequest.op_id, 'food-core').status, 200);
  assert.equal(f.store.getOperation(f.outsider, 'food_entries', createRequest.op_id, 'food-core').status, 404);
});

test('strict record validation rejects totals drift, key drift, invalid ranges, item overflow and unknown enums through DomainStore', t => {
  const f = fixture(t);
  const invalidEntries = [];

  const wrongTotals = entry();
  wrongTotals.totals = {...wrongTotals.totals, kcal: wrongTotals.totals.kcal + 0.1};
  invalidEntries.push(wrongTotals);

  const missingKey = entry();
  delete missingKey.items[0].confidence;
  invalidEntries.push(missingKey);

  const extraKey = entry();
  extraKey.items[0].unexpected = true;
  invalidEntries.push(extraKey);

  const reversedRangeItems = [item({grams: 100, grams_low: 101})];
  invalidEntries.push(entry({items: reversedRangeItems, totals: foodTotals(reversedRangeItems)}));

  const tooManyItems = Array.from({length: 41}, (_, index) => item({name: `合成食物${index}`}));
  invalidEntries.push(entry({items: tooManyItems, totals: foodTotals(tooManyItems)}));

  invalidEntries.push(entry({meal: 'brunch'}));
  invalidEntries.push(entry({items: [item({basis: 'database'})]}));

  for (const data of invalidEntries) {
    const request = f.operation('create', {data});
    const result = f.submit(request);
    assert.equal(result.status, 400, JSON.stringify({data, result}));
    assert.equal(reason(result), 'invalid_request');
  }
});

test('validateFoodRecord accepts only the exact complete active record shape', () => {
  const record = {id: randomUUID(), deleted_at: null, data: entry()};
  assert.equal(validateFoodRecord(record), true);
  assert.equal(validateFoodRecord({...record, data: {...record.data, extra: true}}), false);
  assert.equal(validateFoodRecord({...record, deleted_at: iso}), false);
});


// N2a: HTTP permissions and rollback use a real synthetic Core database.
import {provisionFoodDomain as provisionN2aFood} from './personal_data_domains.mjs';
import {foodHttp, foodOperation} from './test_fixtures/release_schema6/n2a_food.mjs';
import {databaseInspectionFingerprint} from './inspection_read_only.mjs';

test('N2a HTTP food writer, phone reader, device denial and hook-free rollback',async t=>{
 const f=await foodHttp(t);const {issued}=provisionN2aFood(f.core.store.domains);
 const base='/v1/core/domains/food_entries';const binding=f.core.store.nodeId;
 const create=foodOperation(f.core);
 assert.equal((await f.send(base+'/ops',issued.writer,create)).status,201);
 const patch=foodOperation(f.core,'patch',{id:create.id,patch:{note:'synthetic correction'}});
 assert.equal((await f.send(base+'/ops',issued.writer,patch)).status,201);
 const voided=foodOperation(f.core,'patch',{id:create.id,base_revision:2,patch:{voided:true}});
 assert.equal((await f.send(base+'/ops',issued.writer,voided)).status,201);
 const snapshot=await f.send(base+'/snapshot?core_instance_id='+binding,issued.phone);
 assert.equal(snapshot.status,200);assert.equal(snapshot.body.records[0].data.voided,true);
 assert.equal((await f.send(base+'/changes?core_instance_id='+binding+'&cursor='+encodeURIComponent(snapshot.body.manifest.base_cursor),issued.phone)).status,200);
 assert.equal((await f.send(base+'/ops',issued.phone,foodOperation(f.core))).body.error.code,'scope_forbidden');
 const paired=await f.send('/v1/core/devices/pair',null,{pairing_code:'synthetic-pairing-code',device_id:'synthetic-food-device',
  display_name:'Synthetic',platform:'test',client_version:'1',capabilities:['chat']});
 assert.equal(paired.status,200);
 assert.equal((await f.send(base+'/snapshot?core_instance_id='+binding,paired.body.device_token)).body.error.code,'scope_forbidden');
 await f.close();await f.open(false);
 assert.equal((await f.send('/v1/core/health')).status,200);
 const refused=await f.send(base+'/snapshot?core_instance_id='+binding,issued.phone);
 assert.equal(refused.status,503);assert.equal(refused.body.error.code,'schema_not_ready');
 assert.equal((await f.send('/v1/core/chat/transcript-capabilities',paired.body.device_token)).status,200);
 await f.close();const inspection=databaseInspectionFingerprint(f.databasePath);
 assert.equal(inspection.tables.find(row=>row.name==='domain_records').rows,1);
});
