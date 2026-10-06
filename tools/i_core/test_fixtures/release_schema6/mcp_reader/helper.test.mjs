import assert from 'node:assert/strict';
import { mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import {
  LEGACY_ENTRY_SHA256, createSyntheticReaderState, startLegacyMcpReader,
  verifyLegacySourceInventory,
} from './helper.mjs';

test('legacy fixture keeps exact production source bytes and six-module closure', () => {
  const inventory = verifyLegacySourceInventory();
  assert.equal(inventory.entry_sha256, LEGACY_ENTRY_SHA256);
  assert.deepEqual(inventory.files.map(item => item.path).sort(), [
    'i_memory/i_memory_read.mjs', 'i_remote_mcp/diagnostics.mjs', 'i_remote_mcp/mcp.mjs',
    'i_remote_mcp/oauth.mjs', 'i_remote_mcp/server.mjs', 'i_remote_mcp/writeback.mjs',
  ]);
});

test('synthetic reader rejects a Core path outside the explicitly supplied root', () => {
  const root = mkdtempSync(join(tmpdir(), 'synthetic-mcp-path-test-'));
  try {
    assert.throws(() => createSyntheticReaderState({ syntheticRoot: root, coreDbPath: join(root, '..', 'outside.sqlite') }), /inside explicit synthetic root/);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('actual legacy CLI authenticates via HTTP OAuth and opens synthetic Core via real tools/call', { timeout: 20000 }, async () => {
  const root = mkdtempSync(join(tmpdir(), 'synthetic-mcp-cli-test-'));
  let ctx;
  try {
    const coreDbPath = join(root, 'synthetic-core.sqlite');
    const db = new DatabaseSync(coreDbPath);
    try {
      db.exec(`CREATE TABLE chat_messages (
        sync_id TEXT PRIMARY KEY, origin_device_id TEXT NOT NULL, origin_sequence INTEGER NOT NULL,
        character_id TEXT NOT NULL, sender TEXT NOT NULL, content TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL, message_type TEXT NOT NULL, asset_refs_json TEXT NOT NULL,
        addenda_json TEXT NOT NULL, canonical_digest TEXT NOT NULL, server_sequence INTEGER NOT NULL UNIQUE
      );
      INSERT INTO chat_messages VALUES ('synthetic-message', 'synthetic-device', 1, 'lin-ai', 'user',
        'synthetic reader fixture', 1790000000000, 'chat', '[]', '[]', 'synthetic-digest', 1);`);
    } finally { db.close(); }
    const state = createSyntheticReaderState({ syntheticRoot: root, coreDbPath });
    ctx = await startLegacyMcpReader({ state });
    assert.equal(ctx.firstRecall.body.result.structuredContent.messages.count, 1);
    assert.equal(ctx.firstRecall.body.result.structuredContent.messages.items[0].content, 'synthetic reader fixture');
    assert.equal(ctx.firstRecall.body.result.structuredContent.memory.count, 1);
    const next = await ctx.recall('reader');
    assert.equal(next.body.result.structuredContent.messages.count, 1);
    assert.equal(verifyLegacySourceInventory().entry_sha256, LEGACY_ENTRY_SHA256);
    await ctx.close();
    assert.ok(ctx.child.exitCode !== null || ctx.child.signalCode !== null);
  } finally {
    if (ctx) await ctx.close();
    rmSync(root, { recursive: true, force: true });
  }
});

test('directory protection runs on empty directories before synthetic state is written', () => {
  const root = mkdtempSync(join(tmpdir(), 'synthetic-mcp-acl-test-'));
  const protectedDirs = [];
  try {
    const state = createSyntheticReaderState({
      syntheticRoot: root, coreDbPath: join(root, 'synthetic-core-not-created.sqlite'),
      protectDirectory(path) { assert.deepEqual(readdirSync(path), []); protectedDirs.push(path); },
    });
    assert.deepEqual(protectedDirs, [state.readerRoot, state.stateDir, state.iHome, state.logDir]);
  } finally { rmSync(root, { recursive: true, force: true }); }
});
