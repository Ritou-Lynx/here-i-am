import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';

export const MEMORY_SCHEMA_VERSION = 1;

// Drift column names (snake_case) from lib/data/memory_v3/db/tables.dart.
export const REQUIRED_SOURCE_COLUMNS = {
  memory_cards: [
    'id', 'memory_scope', 'type', 'title', 'droplet_label', 'retrieval_text',
    'status', 'created_at', 'updated_at',
  ],
  memory_card_sources: ['card_id', 'recorded_at'],
  memory_card_structured_fields: ['card_id', 'structured_fields_type', 'fields_json'],
};

function parseArgs(argv) {
  const options = { apply: false };
  for (let index = 0; index < argv.length; index++) {
    const argument = argv[index];
    if (argument === '--apply') options.apply = true;
    else if (argument === '--source') options.source = argv[++index];
    else if (argument === '--out') options.out = argv[++index];
    else throw new Error(`Unknown argument: ${argument}`);
  }
  if (!options.source || !options.out) {
    throw new Error('Usage: node import_v3_memory.mjs --source <v3.sqlite> --out <i-memory.sqlite> [--apply]');
  }
  return options;
}

function toMilliseconds(value, label) {
  if (value === null || value === undefined) return null;
  const timestamp = Number(value);
  if (!Number.isSafeInteger(timestamp) || timestamp < 0) {
    throw new Error(`Invalid V3 memory timestamp in ${label}: ${value}`);
  }
  return timestamp < 100_000_000_000 ? timestamp * 1000 : timestamp;
}

export function assertSourceSchema(source) {
  const problems = [];
  for (const [table, required] of Object.entries(REQUIRED_SOURCE_COLUMNS)) {
    const columns = new Set(
      source.prepare(`PRAGMA table_info(${table})`).all().map((row) => row.name),
    );
    if (columns.size === 0) {
      problems.push(`table ${table} is missing`);
      continue;
    }
    const missing = required.filter((column) => !columns.has(column));
    if (missing.length > 0) problems.push(`${table} is missing: ${missing.join(', ')}`);
  }
  if (problems.length > 0) {
    throw new Error(`Source memory schema is incompatible: ${problems.join('; ')}`);
  }
}

export function readV3MemorySnapshot(sourcePath) {
  if (!existsSync(sourcePath)) throw new Error(`Source database does not exist: ${sourcePath}`);
  const sourceSha256 = createHash('sha256').update(readFileSync(sourcePath)).digest('hex');
  const source = new DatabaseSync(sourcePath, { readOnly: true });
  try {
    const integrity = source.prepare('PRAGMA integrity_check').get().integrity_check;
    if (integrity !== 'ok') throw new Error(`Source integrity check failed: ${integrity}`);
    assertSourceSchema(source);

    const rows = source.prepare(`
      SELECT c.id, c.memory_scope, c.type, c.title, c.droplet_label, c.retrieval_text,
             c.status, c.created_at, c.updated_at,
             s.recorded_at,
             f.structured_fields_type, f.fields_json
      FROM memory_cards c
      LEFT JOIN memory_card_sources s ON s.card_id = c.id
      LEFT JOIN memory_card_structured_fields f ON f.card_id = c.id
      ORDER BY c.created_at ASC, c.id ASC
    `).all();

    const seen = new Set();
    const cards = rows.map((row) => {
      if (typeof row.id !== 'string' || !row.id.trim()) {
        throw new Error('Source contains a memory card without id.');
      }
      if (seen.has(row.id)) throw new Error(`Source contains duplicate memory card id: ${row.id}`);
      seen.add(row.id);
      const createdAt = toMilliseconds(row.created_at, `${row.id}.created_at`);
      return {
        id: row.id,
        memory_scope: row.memory_scope ?? 'user_truth',
        type: String(row.type ?? ''),
        title: String(row.title ?? ''),
        droplet_label: String(row.droplet_label ?? ''),
        retrieval_text: String(row.retrieval_text ?? ''),
        status: row.status ?? null,
        structured_type: row.structured_fields_type ?? null,
        fields_json: row.structured_fields_type == null ? null : String(row.fields_json ?? '{}'),
        recorded_at: toMilliseconds(row.recorded_at, `${row.id}.recorded_at`) ?? createdAt,
        created_at: createdAt,
        updated_at: toMilliseconds(row.updated_at, `${row.id}.updated_at`) ?? createdAt,
      };
    });
    return {
      cards,
      summary: {
        source_sha256: sourceSha256,
        source_schema_version: Number(source.prepare('PRAGMA user_version').get().user_version),
        cards: cards.length,
        with_structured: cards.filter((card) => card.structured_type !== null).length,
      },
    };
  } finally {
    source.close();
  }
}

export function ensureMemorySchema(db) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS memory_metadata (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS memory_cards (
      id TEXT PRIMARY KEY,
      memory_scope TEXT NOT NULL,
      type TEXT NOT NULL,
      title TEXT NOT NULL,
      droplet_label TEXT NOT NULL,
      retrieval_text TEXT NOT NULL,
      status TEXT,
      structured_type TEXT,
      fields_json TEXT,
      recorded_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    CREATE VIRTUAL TABLE IF NOT EXISTS memory_cards_fts USING fts5(
      card_id UNINDEXED, title, droplet_label, retrieval_text,
      tokenize = 'trigram'
    );
  `);
}

function existingIds(outPath) {
  if (!existsSync(outPath)) return new Set();
  const db = new DatabaseSync(outPath, { readOnly: true });
  try {
    const table = db.prepare(`
      SELECT 1 AS found FROM sqlite_master WHERE type = 'table' AND name = 'memory_cards'
    `).get();
    if (!table) return new Set();
    return new Set(db.prepare('SELECT id FROM memory_cards').all().map((row) => row.id));
  } finally {
    db.close();
  }
}

export function runImport({ source, out, apply = false, now = Date.now }) {
  const sourcePath = path.resolve(source);
  const outPath = path.resolve(out);
  if (sourcePath === outPath) throw new Error('Source and output database paths must be different.');
  const snapshot = readV3MemorySnapshot(sourcePath);
  const before = existingIds(outPath);
  const incoming = new Set(snapshot.cards.map((card) => card.id));
  const result = {
    mode: apply ? 'apply' : 'dry-run',
    ...snapshot.summary,
    existing: before.size,
    would_add: [...incoming].filter((id) => !before.has(id)).length,
    would_remove: [...before].filter((id) => !incoming.has(id)).length,
  };
  if (!apply) return result;

  mkdirSync(path.dirname(outPath), { recursive: true });
  const snapshotAtMs = now();
  const db = new DatabaseSync(outPath);
  try {
    ensureMemorySchema(db);
    const insertCard = db.prepare(`
      INSERT INTO memory_cards (
        id, memory_scope, type, title, droplet_label, retrieval_text, status,
        structured_type, fields_json, recorded_at, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    const insertFts = db.prepare(`
      INSERT INTO memory_cards_fts (card_id, title, droplet_label, retrieval_text)
      VALUES (?, ?, ?, ?)
    `);
    const setMeta = db.prepare(`
      INSERT INTO memory_metadata (key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    `);
    db.exec('BEGIN IMMEDIATE');
    try {
      db.exec('DELETE FROM memory_cards; DELETE FROM memory_cards_fts;');
      for (const card of snapshot.cards) {
        insertCard.run(
          card.id, card.memory_scope, card.type, card.title, card.droplet_label,
          card.retrieval_text, card.status, card.structured_type, card.fields_json,
          card.recorded_at, card.created_at, card.updated_at,
        );
        insertFts.run(card.id, card.title, card.droplet_label, card.retrieval_text);
      }
      setMeta.run('schema_version', String(MEMORY_SCHEMA_VERSION));
      setMeta.run('snapshot_at_ms', String(snapshotAtMs));
      setMeta.run('source_sha256', snapshot.summary.source_sha256);
      setMeta.run('source_schema_version', String(snapshot.summary.source_schema_version));
      setMeta.run('card_count', String(snapshot.cards.length));
      db.exec('COMMIT');
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    }
  } finally {
    db.close();
  }
  return { ...result, imported: snapshot.cards.length, snapshot_at_ms: snapshotAtMs };
}

const isMain = process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);
if (isMain) {
  try {
    console.log(JSON.stringify(runImport(parseArgs(process.argv.slice(2))), null, 2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
