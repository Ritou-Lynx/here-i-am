import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { activitySchemaStatus } from '../../activity_control_plane.mjs';
import { activityDatabaseBindingDigest } from '../../i_core_store.mjs';

export const LEGACY_COMMIT = 'bbb8025d99fc0acaa846d58b4e5a94cef90f8756';
export const repository = fileURLToPath(new URL('../../../../', import.meta.url));
export const guard = fileURLToPath(new URL('../../runtime_pin/verify_v4_state.mjs', import.meta.url));
export const oldTables = ['core_metadata', 'devices', 'consumed_pairing_codes', 'change_events',
  'chat_messages', 'worker_leases', 'companion_reply_jobs', 'companion_reply_shadow_runs'];
export const suffixes = ['', '-journal', '-wal', '-shm'];
export const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const stable = value => JSON.stringify(value);
export const cleanEnv = () => Object.fromEntries(Object.entries(process.env).filter(([key]) =>
  !key.toUpperCase().startsWith('I_CORE_') && !['NODE_OPTIONS', 'NODE_PATH'].includes(key.toUpperCase())));

export function capture(filename) {
  return suffixes.map(suffix => {
    const name = filename + suffix;
    return { suffix, bytes: existsSync(name) ? readFileSync(name) : null };
  });
}
export const fingerprints = files => files.map(({ suffix, bytes }) => ({ suffix,
  exists: bytes !== null, bytes: bytes?.length ?? 0, sha256: bytes === null ? null : sha(bytes) }));

// Only self-created fixtures enter here. Recover a stable full-view COPY, never
// open/checkpoint the original to classify it. Binding still uses ORIGINAL path.
export function inspect(filename) {
  const files = capture(filename);
  const before = fingerprints(files);
  const root = mkdtempSync(path.join(path.dirname(filename), '.m3-view-'));
  let db;
  try {
    if (!files[0].bytes) throw new Error('missing_main');
    const copy = path.join(root, 'copy.sqlite');
    for (const { suffix, bytes } of files) if (bytes !== null) writeFileSync(copy + suffix, bytes, { flag: 'wx' });
    assert.deepEqual(fingerprints(capture(filename)), before, 'snapshot must be stable');
    db = new DatabaseSync(copy);
    const schema = db.prepare("SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name").all();
    const rows = Object.fromEntries(schema.filter(row => row.type === 'table').map(({ name }) => [name,
      db.prepare(`SELECT * FROM "${name.replaceAll('"', '""')}"`).all()
        .sort((a, b) => stable(a).localeCompare(stable(b)))]));
    const metadata = Object.fromEntries((rows.core_metadata ?? []).map(row => [row.key, row.value]));
    return {
      files: before, schema, rows, metadata,
      integrity: db.prepare('PRAGMA integrity_check').all().map(row => ({ ...row })), foreignKeys: db.prepare('PRAGMA foreign_key_check').all(),
      userVersion: db.prepare('PRAGMA user_version').get().user_version,
      journalMode: db.prepare('PRAGMA journal_mode').get().journal_mode,
      activity: activitySchemaStatus(db, { expectedDatabaseBindingDigest: activityDatabaseBindingDigest(filename) }),
    };
  } finally {
    db?.close();
    assert.equal(path.dirname(root), path.dirname(filename));
    assert.ok(path.basename(root).startsWith('.m3-view-'));
    rmSync(root, { recursive: true });
    assert.deepEqual(fingerprints(capture(filename)), before, 'classification must not mutate original files');
  }
}

export const logicalView = view => ({ schema: view.schema, rows: view.rows, userVersion: view.userVersion });
export function preservedOldRows(view) {
  return Object.fromEntries(oldTables.map(name => [name, (view.rows[name] ?? []).filter(row =>
    name !== 'core_metadata' || (row.key !== 'schema_version' && !row.key.startsWith('activity_')))]));
}
export function describe(view) {
  return {
    files: view.files, schema_version: view.metadata.schema_version, activity_schema_version: view.metadata.activity_schema_version ?? null,
    identity_sha256: sha(stable([view.metadata.node_id, view.metadata.cursor_secret])),
    schema_sha256: sha(stable(view.schema)), logical_sha256: sha(stable(logicalView(view))),
    old_tables: Object.fromEntries(oldTables.map(name => [name, { count: (view.rows[name] ?? []).length,
      sha256: sha(stable(preservedOldRows(view)[name])) }])),
    activity_tables: Object.fromEntries(Object.entries(view.rows).filter(([name]) => name.startsWith('activity_'))
      .map(([name, rows]) => [name, { count: rows.length, sha256: sha(stable(rows)) }])),
    activity_ledger: view.rows.activity_schema_migrations ?? [],
    activity_metadata: view.rows.activity_metadata ?? [], claim: view.rows.activity_runtime_claim ?? [],
    integrity: view.integrity, foreign_keys: view.foreignKeys, activity: view.activity, journal_mode: view.journalMode,
  };
}

export function runV4Guard(filename) {
  const before = fingerprints(capture(filename));
  const result = spawnSync(process.execPath, [guard, filename], {
    env: cleanEnv(), windowsHide: true, encoding: 'utf8', timeout: 10000,
  });
  assert.deepEqual(fingerprints(capture(filename)), before);
  return { status: result.status, passed: result.status === 0,
    source_sqlite_opened: result.status === 0 ? JSON.parse(result.stdout).source_sqlite_opened : null };
}

// Evidence classifier for this test harness, NOT a runtime activation API.
// A stage label/marker cannot authorize migration rollback, restart, or a floor.
export function classify(filename, baseline) {
  try {
    const view = inspect(filename);
    assert.deepEqual(view.integrity, [{ integrity_check: 'ok' }]);
    assert.deepEqual(view.foreignKeys, []);
    assert.deepEqual(preservedOldRows(view), preservedOldRows(baseline));
    if (view.metadata.schema_version === '4') {
      assert.deepEqual(logicalView(view), logicalView(baseline));
      assert.equal(runV4Guard(filename).passed, true);
      return { state: 'uncommitted_v4_verified', action: 'guarded_synthetic_v4_entry', view };
    }
    assert.equal(view.metadata.schema_version, '5');
    assert.equal(view.activity.ready, true);
    return { state: 'committed_v5', action: 'preserve_v5_require_existing_clean_close_conditions', view };
  } catch {
    return { state: 'indeterminate', action: 'refuse_both_entries_preserve_full_view' };
  }
}

export async function createLab(t) {
  const root = realpathSync.native(mkdtempSync(path.join(tmpdir(), 'mda2-m3-')));
  const filename = path.join(root, 'synthetic.sqlite');
  t.after(() => {
    assert.equal(path.dirname(root), realpathSync.native(tmpdir()));
    assert.ok(path.basename(root).startsWith('mda2-m3-'));
    rmSync(root, { recursive: true });
    assert.equal(existsSync(root), false);
  });
  const oldSource = execFileSync('git', ['-C', repository, 'show', `${LEGACY_COMMIT}:tools/i_core/i_core_store.mjs`],
    { windowsHide: true, timeout: 10000, env: cleanEnv() });
  const oldPath = path.join(root, 'old-store.mjs');
  writeFileSync(oldPath, oldSource, { flag: 'wx' });
  const { ICoreStore: OldStore } = await import(pathToFileURL(oldPath));
  const legacy = new OldStore(filename, { companionReplyJobsEnabled: true });
  try {
    legacy.pairDevice({ device_id: 'm3-synthetic', display_name: 'M3 synthetic', platform: 'test', client_version: '1', capabilities: ['chat'] }, 'm3-synthetic-pairing-code');
    legacy.submitMessages('m3-synthetic', { device_id: 'm3-synthetic', request_companion_reply: true, messages: [{
      sync_id: 'm3-message', origin_device_id: 'm3-synthetic', origin_sequence: 1, character_id: 'm3-character',
      sender: 'user', content: 'M3 synthetic migration fixture', created_at_ms: 1000000,
      message_type: 'chat', asset_refs: [], addenda: [],
    }] });
    const lease = legacy.acquireWorkerLease({ workload: 'companion_reply', holder_id: 'm3-worker', ttl_ms: 30000 }, 1000000);
    const { job } = legacy.claimCompanionReplyJob(lease, 1000001);
    legacy.completeCompanionReplyShadow({ ...lease, job_id: job.job_id, model: 'synthetic-no-provider', duration_ms: 1, reply_characters: 3 }, 1000002);
  } finally { legacy.close(); }
  const baseline = inspect(filename);
  assert.equal(baseline.metadata.schema_version, '4');
  assert.deepEqual(baseline.foreignKeys, []);
  for (const name of oldTables) assert.ok(baseline.rows[name].length > 0, `representative data in ${name}`);
  assert.equal(runV4Guard(filename).passed, true);
  return { root, filename, baseline, OldStore, old_source_sha256: sha(oldSource) };
}

export function verifyLegacyEntry(lab) {
  assert.equal(classify(lab.filename, lab.baseline).state, 'uncommitted_v4_verified');
  assert.equal(runV4Guard(lab.filename).passed, true);
  const legacy = new lab.OldStore(lab.filename);
  try {
    assert.equal(legacy.nodeId, lab.baseline.metadata.node_id);
    assert.match(JSON.stringify(legacy.getChanges(legacy.encodeCursor(0))), /M3 synthetic migration fixture/);
    assert.equal(legacy.decodeCursor(legacy.encodeCursor(1)), 1);
  } finally { legacy.close(); }
  assert.deepEqual(logicalView(inspect(lab.filename)), logicalView(lab.baseline));
  return { guard_passed: true, old_constructor_called: true, chat_read: true, cursor_roundtrip: true, logical_view_unchanged: true };
}
