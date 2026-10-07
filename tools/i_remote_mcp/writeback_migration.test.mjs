import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, rmdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { test } from 'node:test';
import { createWriteback, openLedger, RateLimiter } from './writeback.mjs';

const THREAD = 't_fixture01';
const TURN_COLUMNS = 'thread_id,seq,role,turn_key,sync_id,origin_sequence,character_id,created_at_ms,content,status,server_sequence,error_code';

function fixtureV1() {
  const dir = mkdtempSync(join(tmpdir(), 'i-writeback-v1-'));
  const path = join(dir, 'legacy.sqlite');
  const db = new DatabaseSync(path);
  db.exec(`
    PRAGMA journal_mode = WAL;
    CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE threads (thread_id TEXT PRIMARY KEY, created_at_ms INTEGER NOT NULL, last_seen_ms INTEGER NOT NULL);
    CREATE TABLE turns (
      thread_id TEXT NOT NULL, seq INTEGER NOT NULL, role TEXT NOT NULL CHECK(role IN ('user','assistant')),
      turn_key TEXT NOT NULL, sync_id TEXT NOT NULL UNIQUE, origin_sequence INTEGER NOT NULL UNIQUE,
      character_id TEXT NOT NULL, created_at_ms INTEGER NOT NULL, content TEXT,
      status TEXT NOT NULL CHECK(status IN ('pending','committed','rejected')),
      server_sequence INTEGER, error_code TEXT, PRIMARY KEY(thread_id,seq)
    );
    CREATE TABLE notes (
      note_id TEXT PRIMARY KEY, revision INTEGER NOT NULL, text TEXT, text_hash TEXT,
      status TEXT NOT NULL CHECK(status IN ('active','deleted')), created_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL, feed_seq INTEGER NOT NULL UNIQUE,
      delivered_revision INTEGER NOT NULL DEFAULT 0, phone_card_id TEXT
    );
    INSERT INTO meta VALUES ('schema_version','1'),('last_origin_sequence','901'),('last_created_at_ms','1200'),('fixture_marker','preserved');
    INSERT INTO threads VALUES ('t_fixture01',1000,1200);
    INSERT INTO turns VALUES
      ('t_fixture01',1,'user','user:fixture1','frontend:claude_web:t_fixture01:1',899,'char-test',1000,NULL,'committed',11,NULL),
      ('t_fixture01',2,'assistant','assistant:fixture2','frontend:claude_web:t_fixture01:2',900,'char-test',1100,'synthetic rejected reply','rejected',NULL,'fixture_rejection'),
      ('t_fixture01',3,'assistant','assistant:fixture3','frontend:claude_web:t_fixture01:3',901,'char-test',1200,'synthetic pending reply','pending',NULL,NULL);
    INSERT INTO notes VALUES
      ('n_fixture_active',2,'synthetic active note','fixture-note-hash','active',1000,1100,1,2,'card-fixture'),
      ('n_fixture_deleted',3,NULL,NULL,'deleted',1000,1200,2,1,'card-deleted');
  `);
  const before = snapshot(db);
  db.close();
  return {
    path, before,
    cleanup() {
      const absolute = resolve(dir);
      assert.equal(dirname(absolute), resolve(tmpdir()));
      assert.match(basename(absolute), /^i-writeback-v1-/);
      for (const suffix of ['', '-wal', '-shm']) rmSync(join(absolute, `legacy.sqlite${suffix}`), { force: true });
      rmdirSync(absolute);
    },
  };
}

function snapshot(db) {
  return {
    turns: db.prepare(`SELECT ${TURN_COLUMNS} FROM turns ORDER BY seq`).all(),
    notes: db.prepare('SELECT * FROM notes ORDER BY note_id').all(),
    threads: db.prepare('SELECT * FROM threads ORDER BY thread_id').all(),
    otherMeta: db.prepare("SELECT * FROM meta WHERE key != 'schema_version' ORDER BY key").all(),
  };
}

test('real v1 ledger upgrade preserves all existing turns, note revisions, acknowledgements and metadata on reopen', () => {
  const fixture = fixtureV1();
  let ledger;
  try {
    ledger = openLedger(fixture.path);
    assert.equal(ledger.prepare("SELECT value FROM meta WHERE key='schema_version'").get().value, '2');
    assert.deepEqual(snapshot(ledger), fixture.before);
    assert.deepEqual(ledger.prepare('SELECT sketch,backfilled FROM turns ORDER BY seq').all().map(row => [row.sketch,row.backfilled]), [[null,0],[null,0],[null,0]]);
    ledger.close();
    ledger = openLedger(fixture.path);
    assert.deepEqual(snapshot(ledger), fixture.before);
    assert.equal(ledger.prepare('PRAGMA table_info(turns)').all().filter(column => column.name === 'sketch').length, 1);
    assert.equal(ledger.prepare('PRAGMA table_info(turns)').all().filter(column => column.name === 'backfilled').length, 1);
    assert.equal(ledger.prepare('PRAGMA integrity_check').get().integrity_check, 'ok');
  } finally {
    ledger?.close();
    fixture.cleanup();
  }
});

test('upgraded v1 pending turn submits the exact old immutable message without a backfill marker or rejected replay', async () => {
  const fixture = fixtureV1();
  const submitted = [];
  let writeback;
  try {
    const ledger = openLedger(fixture.path);
    writeback = createWriteback({
      ledger, now: () => 2000, rateLimiter: new RateLimiter({}),
      coreClient: { async submit(messages) {
        submitted.push(...messages);
        return messages.map((message,index) => ({sync_id:message.sync_id,status:'accepted',server_sequence:100+index}));
      } },
    });
    const result = await writeback.chatTurn({thread_id:THREAD,phase:'start',turns:[{role:'user',content:'synthetic current user'}]}, {characterId:'char-test'});
    assert.equal(result.core_status, 'ok');
    assert.equal(result.recorded.waiting_for_retry, 0);
    assert.deepEqual(submitted[0], {
      sync_id:'frontend:claude_web:t_fixture01:3', origin_device_id:'frontend:claude_web', origin_sequence:901,
      character_id:'char-test', sender:'companion', content:'synthetic pending reply', created_at_ms:1200,
      message_type:'chat', asset_refs:[], addenda:[],
    });
    assert.equal(submitted.length, 2);
    assert.ok(submitted[1].origin_sequence > 901);
    assert.equal(ledger.prepare("SELECT status,content FROM turns WHERE seq=3").get().status, 'committed');
    assert.equal(ledger.prepare("SELECT status,error_code FROM turns WHERE seq=2").get().status, 'rejected');
    assert.deepEqual(ledger.prepare('SELECT * FROM notes ORDER BY note_id').all(), fixture.before.notes);
  } finally {
    writeback?.close();
    fixture.cleanup();
  }
});
