import { createHash } from 'node:crypto';
import { closeSync, fstatSync, lstatSync, openSync, readSync } from 'node:fs';
import path from 'node:path';
import { plainPath } from '../release_schema6/package.mjs';

export const ONLINE_INPUT_POLICY = 'online-db-wal-bytes-identity-journal-existence-shm-existence-size-v1';
const suffixes = ['', '-wal', '-shm', '-journal'];
const fail = code => { throw Object.assign(new Error(code), { code }); };
const identity = s => [s.dev, s.ino].map(String).join(':');
const changed = () => fail('raw_input_changed_during_capture');
function statOrAbsent(filename) {
  try { return lstatSync(filename, { bigint: true }); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
// Hashes for SHM/journal are diagnostic and retained for later frozen-byte checks.
// The ONLINE comparator below ignores those hashes. Never open SQLite here.
export function observeOnlinePreflightInputs(databasePath) {
  plainPath(databasePath);
  return suffixes.map(suffix => {
    const filename = databasePath + suffix, stat = statOrAbsent(filename);
    if (!stat) return { path: filename, exists: false };
    plainPath(filename);
    if (!stat.isFile() || stat.nlink !== 1n || stat.size > BigInt(Number.MAX_SAFE_INTEGER)) fail('online_input_invalid');
    const entry = { path: filename, exists: true, size: Number(stat.size) };
    const fd = openSync(filename, 'r'), hash = createHash('sha256'), buffer = Buffer.alloc(1024 * 1024);
    try {
      const opened = fstatSync(fd, { bigint: true }); let total = 0;
      const persistent = suffix === '' || suffix === '-wal';
      if (persistent && (identity(stat) !== identity(opened) || stat.size !== opened.size)) changed();
      for (;;) { const n = readSync(fd, buffer, 0, buffer.length, null); if (!n) break; total += n; hash.update(buffer.subarray(0, n)); }
      plainPath(filename);
      const after = fstatSync(fd, { bigint: true }), pathname = lstatSync(filename, { bigint: true });
      if (persistent && (BigInt(total) !== stat.size || after.size !== stat.size || pathname.size !== stat.size
          || identity(after) !== identity(stat) || identity(pathname) !== identity(stat)
          || after.mtimeNs !== opened.mtimeNs || after.ctimeNs !== opened.ctimeNs)) changed();
      return { ...entry, size: Number(pathname.size), file_id: identity(pathname), sha256: hash.digest('hex') };
    } finally { buffer.fill(0); closeSync(fd); }
  });
}
function validate(observation) {
  if (!Array.isArray(observation) || observation.length !== 4) fail('online_input_observation_invalid');
  const databasePath = observation[0]?.path;
  if (typeof databasePath !== 'string' || !path.isAbsolute(databasePath) || path.normalize(databasePath) !== databasePath) fail('online_input_observation_invalid');
  for (let i = 0; i < suffixes.length; i++) {
    const e = observation[i];
    if (!e || e.path !== databasePath + suffixes[i] || typeof e.exists !== 'boolean'
        || (e.exists && (!Number.isSafeInteger(e.size) || e.size < 0))
        || (e.exists && i < 2 && (!/^\d+:\d+$/.test(e.file_id ?? '') || !/^[a-f0-9]{64}$/.test(e.sha256 ?? '')))) fail('online_input_observation_invalid');
  }
  if (!observation[0].exists) fail('online_input_observation_invalid');
}
// ONLINE PREFLIGHT ONLY. A read-only WAL client can write aReadMark in SHM,
// which is a reconstructible wal-index rather than persistent database content.
// https://www.sqlite.org/walformat.html#the_wal_index_or_shm_file
// https://www.sqlite.org/walformat.html#how_the_various_locks_are_used
// Never use this policy for offline raw encryption, frozen-file verification,
// strictClosedPath, recovery custody or NativeLease. Those retain exact bytes.
export function assertOnlinePreflightInputsUnchanged(before, after) {
  validate(before); validate(after);
  for (let i = 0; i < suffixes.length; i++) {
    const a = before[i], b = after[i];
    if (a.path !== b.path || a.exists !== b.exists) changed();
    if (!a.exists || i === 3) continue; // journal: existence only.
    if (a.size !== b.size) changed();
    if (i < 2 && (a.file_id !== b.file_id || a.sha256 !== b.sha256)) changed();
    // SHM: existence and size only; no content or read-mark comparison.
  }
  return true;
}
export async function captureWithOnlinePreflightGuard({ sourcePath, destinationPath, captureConsistentSqlite }) {
  if (typeof captureConsistentSqlite !== 'function') fail('online_capture_function_required');
  const rawBefore = observeOnlinePreflightInputs(sourcePath);
  const capture = await captureConsistentSqlite({ sourcePath, destinationPath });
  const rawAfter = observeOnlinePreflightInputs(sourcePath);
  const observation = { capture, rawBefore, rawAfter, rawStable: false, comparison_policy: ONLINE_INPUT_POLICY };
  try { assertOnlinePreflightInputsUnchanged(rawBefore, rawAfter); }
  catch (error) { error.onlineObservation = observation; throw error; }
  return { ...observation, rawStable: true };
}
