import { createHmac } from 'node:crypto';
import { readConfiguration, noEgressRelay, protectedPath } from './configuration.mjs';
import { spawnSync } from 'node:child_process';
import { closeSync, existsSync, openSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { assertNode, cleanEnvironment, plainPath, separatePaths, sha256, verifyRelease } from './package.mjs';

// Internal child of the lock-owning Windows Job launcher. No standalone start API.
const [control, token, mode, ...extra] = process.argv.slice(2);
let core, config, poll, lifecycle, stateMarker, report;
let serviceOptions;
let startedConstruction = false, closed = false;
function writeControl(name, value) {
  const target = path.join(control, name), pending = target + '.pending';
  plainPath(target, { existing: false }); plainPath(pending, { existing: false });
  if (existsSync(target)) throw new Error('control_receipt_exists');
  writeFileSync(pending, JSON.stringify(value) + '\n', { flag: 'wx', flush: true });
  renameSync(pending, target);
}
function saveMarker(value) {
  const temporary = path.join(config.state, `r3-lifecycle-${token}.tmp`);
  plainPath(stateMarker, { existing: false }); plainPath(temporary, { existing: false });
  writeFileSync(temporary, JSON.stringify(value) + '\n', { flag: 'wx', flush: true });
  renameSync(temporary, stateMarker);
}
function optionalControlValue(target) {
  try {
    plainPath(target);
    return readFileSync(target, 'utf8');
  } catch (error) {
    if (error?.code === 'ENOENT') return null;
    throw error;
  }
}
function inspectExisting(filename) {
  plainPath(filename);
  for (const suffix of ['-wal', '-shm', '-journal']) {
    plainPath(filename + suffix, { existing: false });
    if (existsSync(filename + suffix)) throw new Error('state_sidecars_require_review');
  }
  const before = sha256(readFileSync(filename));
  const db = new DatabaseSync(`${pathToFileURL(filename).href}?mode=ro&immutable=1`, { readOnly: true });
  try {
    const metadata = new Map(db.prepare('SELECT key,value FROM core_metadata').all().map(row => [row.key, row.value]));
    const version = metadata.get('schema_version');
    if (!['4', '5'].includes(version) || !metadata.get('node_id') || !metadata.get('cursor_secret')) throw new Error('existing_core_identity_required');
    if (db.prepare('PRAGMA quick_check').get().quick_check !== 'ok') throw new Error('integrity_check_failed');
    if (version === '5') {
      const role = db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get()?.value;
      if (role !== 'live') throw new Error('backup_activation_unsupported');
      const claim = db.prepare('SELECT runtime_id,lease_expires_at_ms FROM activity_runtime_claim WHERE singleton=1').get();
      if (!claim || claim.runtime_id !== '' || claim.lease_expires_at_ms !== 0) throw new Error('activity_recovery_required');
    }
    return { version, nodeId: metadata.get('node_id'), database_sha256: before };
  } finally {
    db.close();
    if (sha256(readFileSync(filename)) !== before) throw new Error('state_changed_during_preflight');
  }
}
async function shutdown(reason, failure = null) {
  if (closed) return;
  closed = true;
  clearInterval(poll);
  let clean = false;
  try {
    if (core) {
      await core.close();
      clean = core.server.listening === false && core.store.db.isOpen === false;
      if (!clean) throw new Error('resource_close_unconfirmed');
      const final = inspectExisting(path.join(config.state, 'i-core.sqlite'));
      if (final.version !== '5' || final.nodeId !== lifecycle.node_id) throw new Error('closed_identity_mismatch');
      saveMarker({ ...lifecycle, phase: 'close_prepared', database_sha256: final.database_sha256 });
    }
  } catch (error) { failure ??= error; clean = false; }
  report = { token, mode, manifest_sha256: config.manifest_sha256, phase: clean ? 'clean_closed' : startedConstruction ? 'recovery_required' : 'rejected_before_store',
    reason, store_construction_attempted: startedConstruction, store_close_confirmed: clean,
    listener_closed_confirmed: core ? core.server.listening === false : true,
    ...(failure ? { error_code: failure.code ?? failure.message } : {}) };
  try { writeControl('child.json', report); } catch { process.exitCode = 1; }
  if (failure || !clean) process.exitCode = 1;
}
try {
  if (extra.length || !['start', 'migrate-v4'].includes(mode) || !/^[a-f0-9]{64}$/.test(token ?? '')) throw new Error('invalid_internal_arguments');
  plainPath(control); plainPath(path.join(control, 'launch.json'));
  config = JSON.parse(readFileSync(path.join(control, 'launch.json')));
  if (config.token !== token || config.mode !== mode || !Number.isInteger(config.port) || config.port < 0 || config.port > 65535) throw new Error('launch_identity_mismatch');
  if (fileURLToPath(new URL('.', import.meta.url)).replace(/[\\/]+$/, '').toLowerCase() !== config.release.toLowerCase()) throw new Error('release_location_mismatch');
  separatePaths(config.release, config.state, control);
  assertNode();
  verifyRelease(config.release, config.manifest_sha256);
  // Defense in depth; the supported PS entry already cleaned before Node started.
  const cleanEnv = cleanEnvironment();
  for (const name of Object.keys(process.env)) if (!(name in cleanEnv)) delete process.env[name];
  protectedPath(control, true); protectedPath(path.join(control, 'launch.json')); protectedPath(path.join(control, 'stop.key'));
  const filename = path.join(config.state, 'i-core.sqlite');
  const lockPath = path.join(config.state, 'shortcut-mail-relay.runtime.lock');
  plainPath(lockPath);
  let lockHeld = false;
  try { const descriptor = openSync(lockPath, 'r+'); closeSync(descriptor); }
  catch (error) { if (['EBUSY', 'EACCES', 'EPERM'].includes(error.code)) lockHeld = true; else throw error; }
  if (!lockHeld) throw new Error('supervisor_lock_required');
  stateMarker = path.join(config.state, 'r3-lifecycle.json');
  plainPath(stateMarker, { existing: false });
  const before = inspectExisting(filename);
  if (existsSync(stateMarker)) {
    const previous = JSON.parse(readFileSync(stateMarker));
    if (previous.phase !== 'clean_closed' || previous.database_sha256 !== before.database_sha256
        || previous.database_path !== filename || previous.manifest_sha256 !== config.manifest_sha256) throw new Error('prior_shutdown_unconfirmed');
  } else if (before.version === '5') throw new Error('lifecycle_receipt_required');
  if (before.version === '4' && mode !== 'migrate-v4') throw new Error('explicit_v4_migration_required');
  if (before.version === '5' && mode !== 'start') throw new Error('migration_requires_schema4');
  if (before.version === '4') {
    const check = spawnSync(process.execPath, [path.join(config.release, 'verify_v4_state.mjs'), filename],
      { env: cleanEnvironment(), windowsHide: true, encoding: 'utf8', timeout: 20000 });
    if (check.status !== 0) throw new Error('schema4_preflight_rejected');
  }
  serviceOptions = readConfiguration(config.configuration_file, { manifest_sha256: config.manifest_sha256,
    database_path: filename, node_id: before.nodeId, owner_sid: config.owner_sid });
  const privateValues = Object.values(serviceOptions).filter(value => typeof value === 'string');
  privateValues.push(readFileSync(path.join(control, 'stop.key'), 'utf8'));
  const commandlineSecretFree = privateValues.every(value => !process.argv.join('\0').includes(value)
    && ![config.configuration_file,config.state,config.release,control].some(target => target?.includes(value)));
  if (!commandlineSecretFree) throw new Error('secret_in_argument_path_rejected');
  if (existsSync(path.join(control, 'stop'))) throw new Error('cancelled_before_store');
  const { createICoreServer } = await import(pathToFileURL(path.join(config.release, 'tools/i_core/i_core_server.mjs')));
  const { assertAuthoritySecretSeparationInDatabase } = await import(pathToFileURL(path.join(config.release, 'tools/i_core/i_core_store.mjs')));
  const { relay, ...options } = serviceOptions;
  const testRelay = relay ? await noEgressRelay(relay) : null;
  // The public database-level check runs on the already-qualified immutable view:
  // the path-level preflight opens normal SQLite and may create WAL/SHM even read-only.
  const credentialView = new DatabaseSync(`${pathToFileURL(filename).href}?mode=ro&immutable=1`, { readOnly: true });
  try { assertAuthoritySecretSeparationInDatabase(credentialView, { ...options, shortcutMailTokenHash: testRelay?.tokenHash ?? null }); }
  finally { credentialView.close(); }
  if (inspectExisting(filename).database_sha256 !== before.database_sha256) throw new Error('state_changed_during_preflight');
  lifecycle = { format: 'r3-lifecycle-v1', token, database_path: filename, node_id: before.nodeId,
    manifest_sha256: config.manifest_sha256, phase: 'opening', input_schema: Number(before.version) };
  saveMarker(lifecycle);
  startedConstruction = true;
  core = createICoreServer({ databasePath: filename, ...options, shortcutMailRelay: testRelay });
  if (core.store.nodeId !== before.nodeId || core.store.health().schema_version !== 5) throw new Error('migrated_identity_mismatch');
  lifecycle.phase = 'store_created'; saveMarker(lifecycle);
  const address = await core.listen({ host: '127.0.0.1', port: config.port });
  lifecycle.phase = 'listening'; saveMarker(lifecycle);
  writeControl('ready.json', { token, manifest_sha256: config.manifest_sha256, node_sha256: sha256(readFileSync(process.execPath)),
    configuration: { pairing: Boolean(serviceOptions.pairingCode), activity_owner: Boolean(serviceOptions.activityAdminSecret), worker: Boolean(serviceOptions.workerSecret), jobs: serviceOptions.companionReplyJobsEnabled, relay: serviceOptions.relay ? 'no-egress-test' : 'disabled' },
    commandline_secret_free: commandlineSecretFree, pid: process.pid, address, health: core.store.health(), activity_enabled: core.store.activity.active,
    inherited_core_keys: Object.keys(process.env).filter(key => key.toUpperCase().startsWith('I_CORE_')) });
  poll = setInterval(() => {
    try {
      for (const name of ['close', 'stop']) {
        const stop = path.join(control, name);
        const key = readFileSync(path.join(control, 'stop.key'), 'utf8');
        const expected = createHmac('sha256', key).update(`${token}|${config.manifest_sha256}|${name}`).digest('hex');
        const value = optionalControlValue(stop);
        if (value !== null && value === expected) void shutdown(name === 'close' ? 'close_requested' : 'stop_requested');
      }
    } catch (error) { void shutdown('control_failed', error); }
  }, 25);
  process.once('SIGINT', () => { void shutdown('signal'); });
  process.once('SIGTERM', () => { void shutdown('signal'); });
} catch (error) {
  if (config) await shutdown('startup_failed', error);
  else { process.exitCode = 2; }
}
