// Versioned form of the field copy validator. Not part of the fixed runtime.
// This source is reviewed before producing a separately pinned maintenance copy.
// It neither freezes tasks nor starts, migrates or replaces the original Core.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFileSync, constants, existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { plainPath, verifyRelease, PINNED_NODE_SHA256, cleanEnvironment } from '../release_schema6/package.mjs';
import { backupFilePrimitives as files } from '../release_schema6/backup_bundle.mjs';
import { captureWithOnlinePreflightGuard } from './online_preflight_input_guard.mjs';
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const encode = v => JSON.stringify(v, (_, x) => typeof x === 'bigint' ? { integer: String(x) } : x instanceof Uint8Array ? { bytes: Buffer.from(x).toString('base64') } : x);
const quote = s => '"' + s.replaceAll('"', '""') + '"';
function legacyDigest(db) {
  const objects = db.prepare("SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'activity_%' AND name NOT LIKE 'domain_%' AND tbl_name NOT LIKE 'activity_%' AND tbl_name NOT LIKE 'domain_%' ORDER BY type,name").all();
  const rows = objects.filter(x => x.type === 'table').map(x => {
    const st = db.prepare('SELECT * FROM ' + quote(x.name)); st.setReadBigInts(true);
    const data = st.all().filter(r => x.name !== 'core_metadata' || !['schema_version', 'activity_schema_version'].includes(r.key)).filter(r => x.name !== 'sqlite_sequence' || !/^(activity_|domain_)/.test(r.name));
    return [x.name, data.map(encode).sort()];
  });
  return sha(encode({ objects, rows }));
}
const fileHash = filename => { const r = files.readStable(filename); return { size: r.bytes, sha256: r.sha256 }; };
function independent(a, b) {
  const rel = path.relative(a, b); return rel !== '' && (rel === '..' || rel.startsWith('..' + path.sep) || path.isAbsolute(rel));
}
export async function validatePrecutoverCopy(config) {
  const expected = ['releaseDirectory', 'manifestSha256', 'databasePath', 'approvalsPath', 'grantsPath', 'outputDirectory'];
  assert.deepEqual(Object.keys(config).sort(), expected.sort());
  const { releaseDirectory: release, manifestSha256: manifest, databasePath: original, approvalsPath, grantsPath, outputDirectory: out } = config;
  assert.equal(sha(readFileSync(process.execPath)), PINNED_NODE_SHA256);
  const verified = verifyRelease(release, manifest);
  for (const p of [original, approvalsPath, grantsPath]) plainPath(p);
  files.safe(out, true); assert.equal(readdirSync(out).length, 0);
  for (const p of [path.dirname(original), approvalsPath, grantsPath, release]) assert.equal(independent(out, p) && independent(p, out), true);
  // Source ACLs are not changed by preflight. Copies must inherit a private,
  // already prepared root; this is an assertion from the verified fixed release.
  assert.equal(process.platform, 'win32');
  const psQuote = value => "'" + value.replaceAll("'", "''") + "'";
  // Match the fixed lifecycle's trusted OS entry, never PATH lookup. Windows
  // system binaries can be hardlinked by component servicing; plainPath applies
  // unchanged to data/release paths, not to this OS-provided executable.
  const ps = path.join(process.env.SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
  assert.equal(path.isAbsolute(ps) && path.normalize(ps) === ps, true);
  execFileSync(ps, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command',
    '. ' + psQuote(path.join(release, 'tools/i_core/release_schema6/lifecycle/protected_paths.ps1')) + '; Assert-ProtectedPath ' + psQuote(out) + ' -Root'],
    { env: cleanEnvironment(), windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'], timeout: 30000 });
  const load = rel => import(pathToFileURL(path.join(release, rel)).href);
  const { captureConsistentSqlite } = await load('tools/i_core/release_schema6/automatic_backup.mjs');
  const { migrateActivitySchema, activitySchemaStatus } = await load('tools/i_core/activity_control_plane.mjs');
  const { preflight } = await load('tools/i_core/release_schema6/preflight.mjs');
  const A = path.join(out, 'source-schema4.sqlite'), B = path.join(out, 'preflight-schema5.sqlite');
  const approvals = path.join(out, 'approvals.json'), grants = path.join(out, 'grants.json');
  const report = { format: 'schema6-cutover-copy-validation-v1', startedAt: Date.now(), sourceCommit: verified.source_commit, originalSqliteReadOnly: true, deployed: false };
  let phase = 'online_readonly_capture';
  try {
    // This is the sole online input comparison. The capture is loaded from the
    // verified fixed release, unchanged; only the caller's comparison is scoped.
    Object.assign(report, await captureWithOnlinePreflightGuard({ sourcePath: original, destinationPath: A, captureConsistentSqlite }));
    for (const [source, target] of [[approvalsPath, approvals], [grantsPath, grants]]) copyFileSync(source, target, constants.COPYFILE_EXCL);
    report.external = { approvals: fileHash(approvals), grants: fileHash(grants) };
    phase = 'copy_only_migration';
    copyFileSync(A, B, constants.COPYFILE_EXCL); const aHash = fileHash(A);
    const db = new DatabaseSync(B);
    try {
      db.exec('PRAGMA foreign_keys=ON');
      assert.equal(db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get()?.value, '4');
      assert.equal(db.prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE name LIKE 'activity_%' OR name LIKE 'domain_%'").get().n, 0);
      const before = legacyDigest(db), binding = sha('activity-live-path:' + path.normalize(plainPath(B)));
      migrateActivitySchema(db, { databaseBindingDigest: binding });
      assert.equal(legacyDigest(db), before);
      assert.equal(activitySchemaStatus(db, { expectedDatabaseBindingDigest: binding }).ready, true);
      db.exec('PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE');
      report.legacyDigestVerified = true; report.legacyDigestSha256 = before;
    } finally { db.close(); }
    for (const suffix of ['-wal', '-shm', '-journal']) assert.equal(existsSync(B + suffix), false);
    assert.deepEqual(fileHash(A), aHash); report.sourceCopyUnchanged = true;
    const captureConfig = { format: 'schema6-preflight-v1', mode: 'legacy_b3', companion_reply_jobs: false, activity_enabled: false, domain_policy: 'owner_managed', database_path: B, approvals_path: approvals, grants_path: grants };
    phase = 'capture_baseline';
    const baseline = await preflight({ release, manifestHash: manifest, config: captureConfig, capture: true });
    writeFileSync(path.join(out, 'capture-baseline.json'), JSON.stringify(baseline) + '\n', { flag: 'wx' });
    const anchored = { ...captureConfig, ...Object.fromEntries(Object.entries(baseline).filter(([k]) => k.startsWith('expected_'))) };
    writeFileSync(path.join(out, 'anchored-preflight-config.json'), JSON.stringify(anchored) + '\n', { flag: 'wx' });
    phase = 'anchored_preflight';
    report.preflight = await preflight({ release, manifestHash: manifest, config: anchored });
    assert.equal(report.preflight.preflight_passed, true); assert.equal(report.preflight.exact_bindings, 72);
    assert.deepEqual(fileHash(A), aHash); verifyRelease(release, manifest);
    report.externalSourcesUnchanged = JSON.stringify(fileHash(approvalsPath)) === JSON.stringify(report.external.approvals) && JSON.stringify(fileHash(grantsPath)) === JSON.stringify(report.external.grants);
    assert.equal(report.externalSourcesUnchanged, true); report.passed = true; report.completedAt = Date.now();
    writeFileSync(path.join(out, 'precutover-validation-receipt.json'), JSON.stringify(report) + '\n', { flag: 'wx' });
    return report;
  } catch (error) {
    if (error.onlineObservation) Object.assign(report, error.onlineObservation);
    report.passed = false; report.phase = phase;
    report.code = /^[a-z][a-z0-9_]+$/.test(error.code ?? '') ? error.code : 'copy_validation_rejected';
    report.completedAt = Date.now();
    writeFileSync(path.join(out, 'precutover-validation-rejected.json'), JSON.stringify(report) + '\n', { flag: 'wx' });
    throw Object.assign(new Error(report.code), { code: report.code });
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    assert.equal(process.argv.length, 4); assert.equal(process.argv[2], '--config');
    const raw = files.small(plainPath(path.resolve(process.argv[3])), 64 * 1024);
    const report = await validatePrecutoverCopy(JSON.parse(raw));
    process.stdout.write(JSON.stringify({ passed: true, comparison_policy: report.comparison_policy, exact_bindings: report.preflight.exact_bindings, grants: report.preflight.grants, deployed: false }) + '\n');
  } catch (error) {
    const code = /^[a-z][a-z0-9_]+$/.test(error.code ?? '') ? error.code : 'copy_validation_rejected';
    process.stderr.write(JSON.stringify({ passed: false, code, deployed: false }) + '\n'); process.exitCode = 2;
  }
}
