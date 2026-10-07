import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, linkSync, readFileSync, renameSync, rmSync, unlinkSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { syntheticRoot } from '../test_fixtures/release_schema6/synthetic_paths.mjs';
import { observeOnlinePreflightInputs as observe, assertOnlinePreflightInputsUnchanged as unchanged, captureWithOnlinePreflightGuard, ONLINE_INPUT_POLICY } from '../maintenance/online_preflight_input_guard.mjs';
function fixture(t) {
  const root = syntheticRoot('online-input-synthetic-');
  t.after(() => { assert.ok(path.basename(root).startsWith('online-input-synthetic-')); rmSync(root, { recursive: true, force: true }); });
  const db = path.join(root, 'synthetic.sqlite');
  writeFileSync(db, Buffer.alloc(4096, 1)); writeFileSync(db + '-wal', Buffer.alloc(128, 2)); writeFileSync(db + '-shm', Buffer.alloc(32768, 3));
  return { root, db, before: observe(db) };
}
const rejects = (before, after) => assert.throws(() => unchanged(before, after), e => e.code === 'raw_input_changed_during_capture');
test('online observation unchanged passes; SHM-only byte changes pass while retaining diagnostic hashes', t => {
  const f = fixture(t), beforeHash = createHash('sha256').update(readFileSync(f.db + '-shm')).digest('hex');
  assert.equal(unchanged(f.before, observe(f.db)), true);
  const bytes = readFileSync(f.db + '-shm'); bytes[104] ^= 1; writeFileSync(f.db + '-shm', bytes);
  assert.notEqual(createHash('sha256').update(readFileSync(f.db + '-shm')).digest('hex'), beforeHash);
  const after = observe(f.db); assert.equal(unchanged(f.before, after), true);
  assert.notEqual(after[2].sha256, f.before[2].sha256);
});
for (const suffix of ['', '-wal']) {
  test('online guard rejects one changed byte in ' + (suffix || 'DB') + ' with stable size and identity', t => {
    const f = fixture(t), bytes = readFileSync(f.db + suffix); bytes[0] ^= 1; writeFileSync(f.db + suffix, bytes);
    const after = observe(f.db); assert.equal(after[suffix ? 1 : 0].file_id, f.before[suffix ? 1 : 0].file_id);
    assert.equal(after[suffix ? 1 : 0].size, f.before[suffix ? 1 : 0].size); rejects(f.before, after);
  });
  test('online guard rejects changed size in ' + (suffix || 'DB'), t => {
    const f = fixture(t); writeFileSync(f.db + suffix, Buffer.alloc(8192)); rejects(f.before, observe(f.db));
  });
  test('online guard rejects same-byte replacement identity in ' + (suffix || 'DB'), t => {
    const f = fixture(t), bytes = readFileSync(f.db + suffix); renameSync(f.db + suffix, f.db + suffix + '.retained');
    writeFileSync(f.db + suffix, bytes); const after = observe(f.db);
    assert.equal(after[suffix ? 1 : 0].sha256, f.before[suffix ? 1 : 0].sha256); rejects(f.before, after);
  });
}
test('journal appearance or disappearance rejects; stable existence alone is the online policy', t => {
  const f = fixture(t); writeFileSync(f.db + '-journal', 'synthetic journal'); const withJournal = observe(f.db);
  rejects(f.before, withJournal); unlinkSync(f.db + '-journal'); rejects(withJournal, observe(f.db));
});
test('SHM existence and size changes reject even though its content is excluded', t => {
  const f = fixture(t); writeFileSync(f.db + '-shm', Buffer.alloc(65536)); rejects(f.before, observe(f.db));
  unlinkSync(f.db + '-shm'); rejects(f.before, observe(f.db));
});
test('WAL appearance or disappearance rejects', t => {
  const f = fixture(t); unlinkSync(f.db + '-wal'); const withoutWal = observe(f.db); rejects(f.before, withoutWal);
  writeFileSync(f.db + '-wal', Buffer.alloc(128, 2)); rejects(withoutWal, observe(f.db));
});
test('guard wrapper accepts only its scoped SHM mutation and rejects a changed DB before returning success', async t => {
  const f = fixture(t), destinationPath = path.join(f.root, 'copy.sqlite');
  const result = await captureWithOnlinePreflightGuard({ sourcePath: f.db, destinationPath, captureConsistentSqlite: async () => {
    const b = readFileSync(f.db + '-shm'); b[104] ^= 1; writeFileSync(f.db + '-shm', b); return { synthetic: true };
  }});
  assert.equal(result.rawStable, true); assert.equal(result.comparison_policy, ONLINE_INPUT_POLICY);
  await assert.rejects(captureWithOnlinePreflightGuard({ sourcePath: f.db, destinationPath, captureConsistentSqlite: async () => {
    const b = readFileSync(f.db); b[42] ^= 1; writeFileSync(f.db, b); return {};
  }}), e => e.code === 'raw_input_changed_during_capture' && e.onlineObservation.rawStable === false
    && e.onlineObservation.rawBefore[0].sha256 !== e.onlineObservation.rawAfter[0].sha256);
  assert.equal(existsSync(destinationPath), false);
});
test('malformed or incomplete observations never pass', t => {
  const f = fixture(t); assert.throws(() => unchanged(f.before.slice(0, 3), f.before));
  const missingIdentity = structuredClone(f.before); delete missingIdentity[0].file_id; assert.throws(() => unchanged(missingIdentity, f.before));
  const movedPath = structuredClone(f.before); movedPath[1].path += '.other'; assert.throws(() => unchanged(f.before, movedPath));
});

test('journal content and size do not become an offline byte-policy exception', t => {
  const f = fixture(t); writeFileSync(f.db + '-journal', 'initial synthetic journal'); const before = observe(f.db);
  writeFileSync(f.db + '-journal', 'different longer synthetic journal'); const after = observe(f.db);
  assert.notEqual(before[3].sha256, after[3].sha256);
  assert.equal(unchanged(before, after), true);
});
for (const suffix of ['', '-wal', '-shm', '-journal']) {
  test('online observation still rejects hardlinks for ' + (suffix || 'DB'), t => {
    const f = fixture(t); if (suffix === '-journal') writeFileSync(f.db + suffix, 'synthetic');
    linkSync(f.db + suffix, f.db + suffix + '.linked');
    assert.throws(() => observe(f.db), e => e.code === 'linked_path_rejected');
  });
}
