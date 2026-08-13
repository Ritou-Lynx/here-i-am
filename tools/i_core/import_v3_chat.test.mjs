import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { DatabaseSync } from 'node:sqlite';
import { readV3ChatSnapshot, runImport } from './import_v3_chat.mjs';
import { ICoreStore } from './i_core_store.mjs';

function createV3Fixture(databasePath) {
  const db = new DatabaseSync(databasePath);
  db.exec(`
    PRAGMA user_version = 57;
    CREATE TABLE persona_chat_messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      character_id TEXT NOT NULL,
      is_from_character INTEGER NOT NULL,
      content TEXT NOT NULL,
      fact_id TEXT,
      is_read INTEGER NOT NULL DEFAULT 0,
      timestamp INTEGER NOT NULL,
      message_type TEXT NOT NULL DEFAULT 'chat',
      attachments_json TEXT,
      sync_id TEXT,
      origin_device_id TEXT
    );
  `);
  const insert = db.prepare(`
    INSERT INTO persona_chat_messages(
      id, character_id, is_from_character, content, timestamp, message_type,
      attachments_json, sync_id, origin_device_id
    ) VALUES (?, 'i', ?, ?, ?, ?, ?, ?, ?)
  `);
  insert.run(7, 0, '我到家了', 1786550400, 'chat', null, 'user-7', 'phone-a');
  insert.run(9, 1, '欢迎回来。', 1786550401, 'chat', null, 'companion-9', 'phone-a');
  insert.run(12, 0, '', 1786550402, 'chat', '[{"mimeType":"image/png"}]', 'image-12', 'phone-a');
  db.close();
}

test('V3 snapshot maps both sides and omits attachment-only rows', () => {
  const directory = mkdtempSync(path.join(tmpdir(), 'i-core-v3-read-'));
  try {
    const sourcePath = path.join(directory, 'v3.sqlite');
    createV3Fixture(sourcePath);
    const snapshot = readV3ChatSnapshot(sourcePath);
    assert.equal(snapshot.summary.source_total, 3);
    assert.equal(snapshot.summary.total, 2);
    assert.equal(snapshot.summary.user, 1);
    assert.equal(snapshot.summary.companion, 1);
    assert.equal(snapshot.summary.empty_messages_omitted, 1);
    assert.equal(snapshot.summary.attachments_omitted, 1);
    assert.deepEqual(snapshot.messages.map((item) => item.origin_sequence), [7, 9]);
    assert.deepEqual(snapshot.messages.map((item) => item.sender), ['user', 'companion']);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test('apply creates a safety backup and is idempotent', async () => {
  const directory = mkdtempSync(path.join(tmpdir(), 'i-core-v3-apply-'));
  try {
    const sourcePath = path.join(directory, 'v3.sqlite');
    const corePath = path.join(directory, 'core.sqlite');
    const backupDir = path.join(directory, 'backups');
    createV3Fixture(sourcePath);
    new ICoreStore(corePath).close();

    const first = await runImport({
      source: sourcePath,
      core: corePath,
      backupDir,
      apply: true,
      coreStopped: true,
    });
    assert.equal(first.inserted, 2);
    assert.equal(first.duplicates, 0);
    assert.ok(first.backup && existsSync(first.backup));

    const core = new DatabaseSync(corePath, { readOnly: true });
    const rows = core.prepare(`
      SELECT sync_id, sender, origin_sequence
      FROM chat_messages ORDER BY origin_sequence
    `).all();
    core.close();
    assert.deepEqual(rows.map((row) => row.sync_id), ['user-7', 'companion-9']);
    assert.deepEqual(rows.map((row) => row.sender), ['user', 'companion']);
    assert.deepEqual(rows.map((row) => Number(row.origin_sequence)), [7, 9]);

    const second = await runImport({
      source: sourcePath,
      core: corePath,
      backupDir,
      apply: true,
      coreStopped: true,
    });
    assert.equal(second.inserted, 0);
    assert.equal(second.duplicates, 2);
    assert.equal(readdirSync(backupDir).length, 2);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
