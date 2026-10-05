import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { ICoreStore } from './i_core_store.mjs';
import { DOMAIN_SCHEMA_SQL } from './domain_schema.mjs';
import { rollbackActivitySchema } from './activity_control_plane.mjs';

function fixture(t, { migrated = true } = {}) {
  const directory = mkdtempSync(path.join(tmpdir(), 'w1-phone-'));
  const databasePath = path.join(directory, 'core.sqlite');
  let store = new ICoreStore(databasePath);
  if (migrated) {
    store.close();
    const db = new DatabaseSync(databasePath);
    db.exec(DOMAIN_SCHEMA_SQL);
    db.prepare("UPDATE core_metadata SET value='6' WHERE key='schema_version'").run();
    db.close();
    store = new ICoreStore(databasePath);
  }
  t.after(() => {
    store.close();
    assert.ok(path.resolve(directory).startsWith(path.resolve(tmpdir()) + path.sep));
    rmSync(directory, { recursive: true, force: true });
  });
  return { store, databasePath, replace(value) { store = value; } };
}
function pair(store, deviceId = 'phone-fixture', platform = 'android', code = 'pair-code-fixture') {
  return store.pairDevice({ device_id: deviceId, display_name: 'synthetic device',
    platform, client_version: '0.1', capabilities: ['chat:append_companion'] }, code);
}
function message(overrides = {}) {
  return { sync_id: 'synthetic-companion', origin_device_id: 'phone-fixture', origin_sequence: 1,
    character_id: 'main-i', sender: 'companion', content: 'synthetic reply', created_at_ms: 1_000,
    ...overrides };
}
function submit(store, item = message(), extra = {}) {
  return store.submitMessages('phone-fixture', { device_id: 'phone-fixture', messages: [item], ...extra });
}
function grant(store) { return store.configurePhoneCompanion({device_id:'phone-fixture',character_id:'main-i'}); }
function count(store) { return Number(store.db.prepare('SELECT COUNT(*) AS n FROM chat_messages').get().n); }

test('schema 5 chat bootstrap never creates domain tables or grants companion from pairing claims', (t) => {
  const { store } = fixture(t, { migrated: false });
  pair(store);
  assert.equal(store.health().schema_version, 5);
  assert.equal(store.domains, null);
  assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE name LIKE 'domain_%'").get().n, 0);
  assert.throws(() => submit(store), { code: 'sender_not_allowed' });
  assert.throws(() => grant(store), { code: 'schema_not_ready' });
  assert.equal(count(store), 0);
});

test('schema 6 reopens unchanged identity/activity and explicit phone capability persists once', (t) => {
  const f = fixture(t); const {store}=f;
  const p=pair(store); const node=store.nodeId;
  assert.equal(store.health().ok,true);
  assert.equal(store.health().schema_version,6);
  assert.equal(store.activity.schemaStatus().ready,true);
  assert.equal(store.activity.schemaStatus().schema_version,5);
  assert.throws(() => submit(store), { code:'sender_not_allowed' });
  grant(store);
  assert.equal(submit(store).results[0].status,'accepted');
  assert.equal(submit(store).results[0].status,'duplicate');
  assert.equal(count(store),1);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS n FROM companion_reply_jobs').get().n,0);
  store.close(); const reopened=new ICoreStore(f.databasePath);f.replace(reopened);
  assert.equal(reopened.nodeId,node);
  assert.equal(reopened.authenticate(p.device_token).device_id,'phone-fixture');
  assert.equal(submit(reopened).results[0].status,'duplicate');
  assert.equal(count(reopened),1);
});

test('phone companion is bound to own origin, primary character and no reply field even false', (t) => {
  const {store}=fixture(t);pair(store);grant(store);
  assert.throws(()=>submit(store,message({origin_device_id:'another-phone'})),{code:'origin_device_mismatch'});
  assert.throws(()=>submit(store,message({character_id:'another-character'})),{code:'primary_character_mismatch'});
  for(const flag of [false,true,null]) assert.throws(()=>submit(store,message(),{request_companion_reply:flag}),{code:'phone_reply_request_forbidden'});
  assert.throws(()=>submit(store,message({sender:'user'}),{request_companion_reply:true}),{code:'phone_reply_request_forbidden'});
  assert.equal(count(store),0);
});

test('mixed invalid phone batch is rejected without accepting its valid first message', (t) => {
  const {store}=fixture(t);pair(store);grant(store);
  assert.throws(()=>store.submitMessages('phone-fixture',{device_id:'phone-fixture',messages:[message(),message({sync_id:'bad',origin_sequence:2,character_id:'other'})]}),{code:'primary_character_mismatch'});
  assert.equal(count(store),0);
});

test('capability requires enrolled Android and cannot move to a second primary character', (t) => {
  const {store}=fixture(t);pair(store);pair(store,'desktop-fixture','windows','pair-desktop');
  assert.throws(()=>store.configurePhoneCompanion({device_id:'desktop-fixture',character_id:'main-i'}),{code:'phone_device_required'});
  grant(store);
  assert.throws(()=>store.configurePhoneCompanion({device_id:'phone-fixture',character_id:'other'}),{code:'primary_character_mismatch'});
  store.configurePhoneCompanion({device_id:'phone-fixture',character_id:'main-i',enabled:false});
  assert.throws(()=>submit(store),{code:'sender_not_allowed'});
});

test('device token rotation invalidates an old phone grant until explicit re-enrollment', (t) => {
  const {store}=fixture(t);const old=pair(store);grant(store);
  const fresh=pair(store,'phone-fixture','android','pair-phone-rotate');
  assert.equal(store.authenticate(old.device_token),null);
  assert.equal(store.authenticate(fresh.device_token).device_id,'phone-fixture');
  assert.throws(()=>submit(store),{code:'sender_not_allowed'});
  grant(store);assert.equal(submit(store).results[0].status,'accepted');
});

test('phone ownership blocks worker production while allowing existing worker shadow leases', (t) => {
  const {store}=fixture(t);pair(store);grant(store);
  const lease=store.acquireWorkerLease({workload:'companion_reply',holder_id:'worker-fixture',ttl_ms:30_000},1_000);
  assert.throws(()=>store.publishCompanionMessages({...lease,messages:[message({origin_device_id:'worker-fixture'})]},1_001),{code:'companion_publish_shadow_only'});
  assert.equal(count(store),0);
});

test('restart cannot turn Core reply production on for an enrolled phone-owned character', (t) => {
  const f=fixture(t);pair(f.store);grant(f.store);f.store.close();
  assert.throws(()=>new ICoreStore(f.databasePath,{companionReplyJobsEnabled:true}),{code:'companion_executor_conflict'});
  f.replace(new ICoreStore(f.databasePath));
});

test('schema 6 forbids activity-only rollback from dropping the newer core schema marker', (t) => {
  const {store}=fixture(t);
  assert.throws(()=>rollbackActivitySchema(store.db),{code:'domain_schema_present'});
  assert.equal(store.health().schema_version,6);
  assert.equal(store.activity.schemaStatus().ready,true);
});

test('phone capability fails closed after domain schema or role changes without accepting messages', (t) => {
  for (const change of ['schema', 'role']) {
    const f=fixture(t); const store=f.store; pair(store);
    grant(store);
    if (change==='schema') store.db.prepare("UPDATE core_metadata SET value='5' WHERE key='schema_version'").run();
    else store.db.prepare("UPDATE activity_metadata SET value='backup_read_only' WHERE key='database_role'").run();
    const op={device_id:'phone-fixture',messages:[message()]};
    assert.throws(()=>store.submitMessages('phone-fixture',op), error=>error.status===503);
    assert.equal(count(store),0);
    if (change==='schema') store.db.prepare("UPDATE core_metadata SET value='6' WHERE key='schema_version'").run();
    else store.db.prepare("UPDATE activity_metadata SET value='live' WHERE key='database_role'").run();
    assert.throws(()=>store.submitMessages('phone-fixture',op), error=>error.code==='core_not_ready');
    assert.equal(count(store),0);
  }
});