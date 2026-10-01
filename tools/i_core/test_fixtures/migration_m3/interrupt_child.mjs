import { existsSync, realpathSync, writeSync } from 'node:fs';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { DatabaseSync } from 'node:sqlite';
import { ActivityControlPlane } from '../../activity_control_plane.mjs';
import { ICoreStore, activityDatabaseBindingDigest } from '../../i_core_store.mjs';

// No descendants, listener, real activity, external configuration, or async jobs.
// Finite Atomics wait also retires this child if its test parent disappears.
const [filename, stage, chain, ...extra] = process.argv.slice(2);
if (extra.length || !existsSync(filename) || realpathSync.native(filename) !== filename
  || path.dirname(path.dirname(filename)) !== realpathSync.native(tmpdir())
  || !path.basename(path.dirname(filename)).startsWith('mda2-m3-')
  || path.basename(filename) !== 'synthetic.sqlite'
  || !['after_ddl', 'before_commit', 'after_commit', 'after_claim'].includes(stage)
  || !['store', 'control-delete'].includes(chain)) throw new Error('owned_synthetic_fixture_required');
function barrier(actual) {
  if (actual !== stage) return;
  writeSync(1, JSON.stringify({ barrier: actual, pid: process.pid, chain, max_wait_ms: 12000 }) + '\n');
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 12000);
  process.exit(92); // Budget expiry must fail the parent, never masquerade as a kill.
}
if (chain === 'store') {
  new ICoreStore(filename, { clock: () => 1000000, activityEnabled: true,
    activityRuntimeId: 'm3-owned-child', activityRuntimeLeaseMs: 1000, testOnlyActivityMigrationHook: barrier });
  barrier('after_claim');
} else {
  const db = new DatabaseSync(filename);
  db.exec('PRAGMA journal_mode=DELETE; PRAGMA foreign_keys=ON; PRAGMA cache_size=1; PRAGMA cache_spill=ON');
  const metadata = Object.fromEntries(db.prepare('SELECT key,value FROM core_metadata').all().map(row => [row.key, row.value]));
  new ActivityControlPlane(db, { nodeId: metadata.node_id, cursorSecret: metadata.cursor_secret,
    databaseBindingDigest: activityDatabaseBindingDigest(filename), clock: () => 1000000,
    testOnlyMigrationHook: barrier, active: false });
}
throw new Error('requested_barrier_not_reached');
