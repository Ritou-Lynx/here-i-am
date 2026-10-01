import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';

// Called by the pinned launcher while holding the legacy runtime lock.
// Never import ICoreStore: the old constructor unconditionally writes schema 4.
const databasePath = process.argv[2];
if (!databasePath || !path.isAbsolute(databasePath) || !existsSync(databasePath)) {
  throw new Error('An existing schema-v4 database is required; no new database will be created.');
}
let database;
let temporaryDirectory;
const suffixes = ['', '-journal', '-wal', '-shm'];
const capture = () => suffixes.map(suffix => existsSync(databasePath + suffix) ? readFileSync(databasePath + suffix) : null);
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const fingerprint = files => files.map(bytes => bytes === null ? null : sha(bytes)).join('|');
const before = capture();
try {
  // Even SQLite readOnly may maintain WAL/SHM read marks. Open only an owned
  // full-view copy inside the existing state directory, inheriting its ACL.
  // Real-state use is part of the later authorized runtime switch, never build.
  temporaryDirectory = mkdtempSync(path.join(path.dirname(databasePath), '.runtime-preflight-'));
  const candidate = path.join(temporaryDirectory, 'candidate.sqlite');
  before.forEach((bytes, index) => { if (bytes !== null) writeFileSync(candidate + suffixes[index], bytes, { flag: 'wx' }); });
  if (fingerprint(before) !== fingerprint(capture())) throw new Error('State changed during preflight; refusing to start.');
  database = new DatabaseSync(candidate);
  const tables = database.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").all().map(row => row.name);
  const expected = ['core_metadata', 'devices', 'consumed_pairing_codes', 'change_events',
    'chat_messages', 'worker_leases', 'companion_reply_jobs', 'companion_reply_shadow_runs'];
  if (tables.length !== expected.length || expected.some(name => !tables.includes(name))) {
    throw new Error('Existing database does not match the pre-MDA core schema.');
  }
  const shape = {};
  for (const table of tables) {
    shape[table] = database.prepare(`PRAGMA table_info(${table})`).all()
      .map(({ name, type, notnull, dflt_value, pk }) => ({ name, type, notnull, dflt_value, pk }));
  }
  // Derived from a synthetic database created by bbb8025d's exact ICoreStore.
  if (sha(JSON.stringify(shape)) !== '750b78bbeb9a67a3843d94c69481f8801f8b050f76bf9620e662ba01d8177f62') {
    throw new Error('Existing core table columns do not match schema 4.');
  }
  const version = database.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get()?.value;
  const metadataKeys = database.prepare('SELECT key FROM core_metadata').all().map(row => row.key);
  if (version !== '4' || metadataKeys.some(key => /^activity_/i.test(key))) {
    throw new Error('Only existing schema 4 without activity metadata is accepted.');
  }
  const identityCount = database.prepare("SELECT count(*) AS count FROM core_metadata WHERE key IN ('node_id', 'cursor_secret') AND length(value)>0").get().count;
  if (identityCount !== 2) {
    throw new Error('Existing core identity metadata is incomplete.');
  }
  console.log(JSON.stringify({ status: 'schema4_preflight_passed', source_sqlite_opened: false }));
} finally {
  try { database?.close(); } finally {
    if (temporaryDirectory) {
      const parent = path.dirname(path.resolve(databasePath));
      if (path.dirname(temporaryDirectory) !== parent || !path.basename(temporaryDirectory).startsWith('.runtime-preflight-')) {
        throw new Error('Refusing to clean an unowned preflight directory.');
      }
      rmSync(temporaryDirectory, { recursive: true });
    }
    if (fingerprint(before) !== fingerprint(capture())) throw new Error('Source state changed during preflight; refusing to start.');
  }
}
