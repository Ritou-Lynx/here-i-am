import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createLab } from '../../test_fixtures/runtime_upgrade/r3/lab.mjs';
import { sha256, verifyRelease } from './package.mjs';

// This file is copied byte-for-byte into tools/i_core/runtime_upgrade/r3/ before it runs.
// All relative imports intentionally resolve from that R3 directory, not this template directory.
const FROZEN_STORE = '883a35c128ee88f7689b737de2245ef073f0c6b96902385241f30c08eb8f816d';
const FROZEN_ACP = '525295357490814c69fb204358e019f862e916c09efc5f5ff85b99043f83f222';
const SOURCES = [
  ['tools/i_core/i_core_store.mjs', FROZEN_STORE],
  ['tools/i_core/activity_control_plane.mjs', FROZEN_ACP],
];
const SIDECARS = ['', '-journal', '-wal', '-shm'];

function releaseFile(lab, relative) { return path.join(lab.release, relative); }
function releaseStore(lab) {
  return import(pathToFileURL(releaseFile(lab, 'tools/i_core/i_core_store.mjs')).href);
}
function stateFingerprint(filename) {
  return SIDECARS.map(suffix => {
    const name = filename + suffix;
    return { suffix, exists: existsSync(name), sha256: existsSync(name) ? sha256(readFileSync(name)) : null };
  });
}
// Use an owned complete sidecar copy, as M3 does, so no classifier opens or checkpoints the source state.
function inspectCommittedCopy(filename) {
  const before = stateFingerprint(filename);
  const root = mkdtempSync(path.join(path.dirname(filename), '.combination-view-'));
  const copy = path.join(root, 'copy.sqlite');
  let db;
  try {
    for (const suffix of SIDECARS) if (existsSync(filename + suffix)) writeFileSync(copy + suffix, readFileSync(filename + suffix), { flag: 'wx' });
    assert.deepEqual(stateFingerprint(filename), before, 'source sidecar set changed while copying');
    db = new DatabaseSync(copy);
    const schemaVersion = db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get().value;
    const claim = db.prepare('SELECT runtime_id,runtime_fence,lease_expires_at_ms FROM activity_runtime_claim').all().map(row => ({ ...row }));
    return { schemaVersion, claim };
  } finally {
    db?.close();
    rmSync(root, { recursive: true });
    assert.deepEqual(stateFingerprint(filename), before, 'copy inspection must not mutate source state');
  }
}
function rewriteManifest(release) {
  const manifestPath = path.join(release, 'manifest.json');
  const manifest = JSON.parse(readFileSync(manifestPath));
  manifest.files = manifest.files.map(file => {
    const bytes = readFileSync(path.join(release, file.path));
    return { ...file, bytes: bytes.length, sha256: sha256(bytes) };
  });
  const raw = Buffer.from(JSON.stringify(manifest, null, 2) + '\n');
  writeFileSync(manifestPath, raw);
  return sha256(raw);
}

test('combined release binds frozen M3 source bytes and fixed source table rejects a rehashed substituted blob', async t => {
  const lab = await createLab(t);
  const manifest = JSON.parse(readFileSync(path.join(lab.release, 'manifest.json')));
  assert.equal(manifest.candidate_id, 'i-core-r3-sanitized-f605d501');
  assert.equal(manifest.source_mode, 'sanitized-fixed-source-baseline');
  assert.equal(manifest.source_commit, 'f605d5017cbc0a8eb69983e00c25cd1bba08a0eb');
  for (const [relative, expected] of SOURCES) assert.equal(sha256(readFileSync(releaseFile(lab, relative))), expected, relative);
  const { ICoreStore } = await releaseStore(lab);
  assert.equal(typeof ICoreStore, 'function');

  // Each mutation is confined to this lab release and always restores its original bytes and valid manifest.
  for (const [relative] of SOURCES) {
    const target = releaseFile(lab, relative);
    const original = readFileSync(target);
    try {
      writeFileSync(target, Buffer.concat([Buffer.from('// synthetic substituted source blob\n'), original]));
      const tamperedManifest = rewriteManifest(lab.release);
      assert.throws(() => verifyRelease(lab.release, tamperedManifest), /release_content_mismatch/);
    } finally {
      writeFileSync(target, original);
      const restoredManifest = rewriteManifest(lab.release);
      assert.doesNotThrow(() => verifyRelease(lab.release, restoredManifest));
    }
  }
});

test('post-COMMIT M3 hook throw leaves v5 with empty claim but no R3 clean receipt, so R3 refuses restart before Store construction', async t => {
  const lab = await createLab(t);
  const { ICoreStore } = await releaseStore(lab);
  assert.throws(() => new ICoreStore(lab.database, {
    clock: () => 1000000,
    activityEnabled: true,
    activityRuntimeId: 'combination-after-commit',
    activityRuntimeLeaseMs: 1000,
    testOnlyActivityMigrationHook: stage => {
      if (stage === 'after_commit') throw new Error('combination-post-commit-throw');
    },
  }), /combination-post-commit-throw/);

  assert.deepEqual(inspectCommittedCopy(lab.database), {
    schemaVersion: '5', claim: [{ runtime_id: '', runtime_fence: 0, lease_expires_at_ms: 0 }],
  });
  assert.equal(existsSync(path.join(lab.state, 'r3-lifecycle.json')), false, 'a direct hook throw cannot mint a clean R3 receipt');
  const beforeRetry = stateFingerprint(lab.database);
  const retry = await lab.launch({ migrate: false }).wait();
  assert.notEqual(retry.exit, 0, retry.stderr);
  assert.equal(retry.child.error_code, 'lifecycle_receipt_required');
  assert.equal(retry.child.store_construction_attempted, false);
  assert.equal(retry.receipt.result.child_exit_confirmed, true);
  assert.equal(retry.receipt.result.child_exit_code_confirmed, true);
  assert.equal(retry.receipt.result.job_empty_confirmed, true);
  assert.deepEqual(stateFingerprint(lab.database), beforeRetry, 'rejected restart must preserve main and sidecars');
  t.diagnostic(JSON.stringify({ scenario: 'combined_post_commit_throw', manifest_sha256: lab.packageResult.manifest_sha256,
    rejection: retry.child.error_code, store_construction_attempted: retry.child.store_construction_attempted,
    child_exit_confirmed: retry.receipt.result.child_exit_confirmed, child_exit_code: retry.receipt.result.child_exit_code,
    job_empty_confirmed: retry.receipt.result.job_empty_confirmed, full_state_unchanged: true, clean_receipt: false }));
});
