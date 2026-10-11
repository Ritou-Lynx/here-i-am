import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { closeSync, existsSync, fsyncSync, lstatSync, mkdirSync, mkdtempSync, openSync, readFileSync, realpathSync, readdirSync, rmSync, unlinkSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import { ACTIVITY_RAW_RETENTION_MS, activitySchemaStatus, assertActivityRecoveryFloorForDatabase } from './activity_control_plane.mjs';
import { DOMAIN_SCHEMA_SQL, DOMAIN_TABLE_NAMES, DomainSchemaError, assertDomainSchemaReady, inspectDomainSchema } from './domain_schema.mjs';

const fail = (code) => { throw new DomainSchemaError(code); };
const hash = (bytes) => createHash('sha256').update(bytes).digest('hex');
const quote = (name) => `"${name.replaceAll('"', '""')}"`;
const tableExists = (db, name) => Boolean(db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?").get(name));
const value = (db, key) => db.prepare('SELECT value FROM core_metadata WHERE key=?').get(key)?.value;
const magic = Buffer.from('ICOREDB6');
const BACKUP_RETENTION_MS = 30 * 86400000;
export const DOMAIN_BACKUP_POLICY = 'domain-offline-backup-v1';

// Existing path components must be real directories/files, never symlinks/junctions.
function safePath(input, { directory = false, allowMissing = false } = {}) {
 if (typeof input !== 'string' || !input) fail('unsafe_database_path');
 const absolute = path.resolve(input);
 const root = path.parse(absolute).root;
 let current = root;
 for (const component of absolute.slice(root.length).split(path.sep).filter(Boolean)) {
  current = path.join(current, component);
  let stat;
  try { stat = lstatSync(current); } catch (error) {
   if (allowMissing && error.code === 'ENOENT') continue;
   fail('database_path_missing');
  }
  if (stat.isSymbolicLink()) fail('unsafe_database_path');
  const resolved = path.normalize(realpathSync.native(current));
  const equivalent = process.platform === 'win32' ? resolved.toLowerCase() === current.toLowerCase() : resolved === current;
  if (!equivalent) fail('unsafe_database_path');
  if (current === absolute ? directory ? !stat.isDirectory() : !stat.isFile() || stat.nlink !== 1 : !stat.isDirectory()) fail('unsafe_database_path');
 }
 return absolute;
}
function checkSidecars(databasePath) {
 for (const suffix of ['-wal', '-shm', '-journal']) {
  const file = `${databasePath}${suffix}`;
  if (!existsSync(file)) continue;
  safePath(file);
  // An offline administrator must cleanly close/checkpoint WAL before this entrypoint.
  if (lstatSync(file).size !== 0) fail('sqlite_sidecars_not_quiescent');
 }
}
function checkIntegrity(db) {
 const results = db.prepare('PRAGMA integrity_check').all();
 if (results.length !== 1 || Object.values(results[0])[0] !== 'ok') fail('database_integrity_failed');
 if (db.prepare('PRAGMA foreign_key_check').all().length) fail('database_integrity_failed');
}
function tableDigest(db, name) {
 const statement = db.prepare(`SELECT * FROM ${quote(name)}`);
 statement.setReadBigInts(true);
 const rows = statement.all().filter((row) => name !== 'core_metadata' || !['schema_version', 'domain_backup_role'].includes(row.key));
 const encode = (row) => JSON.stringify(row, (_, item) => typeof item === 'bigint' ? { integer: String(item) } : item instanceof Uint8Array ? { bytes: Buffer.from(item).toString('base64') } : item);
 return hash(rows.map(encode).sort().join('\n'));
}
function legacySnapshot(db) {
 const objects = db.prepare("SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'domain_%' AND name NOT LIKE 'sqlite_autoindex_domain_%' ORDER BY type,name").all();
 const tables = objects.filter((entry) => entry.type === 'table' && entry.name !== 'sqlite_sequence');
 const sequences = tableExists(db, 'sqlite_sequence') ? db.prepare("SELECT name,seq FROM sqlite_sequence WHERE name NOT LIKE 'domain_%' ORDER BY name").all() : [];
 return { objects: objects.filter((entry) => entry.name !== 'sqlite_sequence'), tables: tables.map((entry) => [entry.name, tableDigest(db, entry.name)]), sequences };
}
function unchanged(db, baseline) {
 if (JSON.stringify(legacySnapshot(db)) !== JSON.stringify(baseline)) fail('legacy_content_changed');
}
function preflight(db, databasePath, options, expectedVersion) {
 checkIntegrity(db);
 if (!tableExists(db, 'core_metadata') || value(db, 'schema_version') !== String(expectedVersion)) fail('unsupported_core_schema_version');
 const nodeId = value(db, 'node_id');
 const cursorSecret = value(db, 'cursor_secret');
 if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(nodeId ?? '') || !/^[A-Za-z0-9_-]{43}$/.test(cursorSecret ?? '')) fail('core_metadata_invariant_failed');
 if (value(db, 'domain_backup_role')) fail('backup_activation_unsupported');
 if (!tableExists(db, 'activity_metadata')) fail('activity_schema_not_ready');
 const role = db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get()?.value;
 if (role === 'backup_read_only') fail('backup_activation_unsupported');
 if (role !== 'live') fail('activity_schema_not_ready');
 const binding = hash(`activity-live-path:${path.normalize(realpathSync.native(databasePath))}`);
 const status = activitySchemaStatus(db, { expectedDatabaseBindingDigest: binding });
 if (!status.ready) fail(status.reason === 'database_binding_mismatch' ? 'activity_database_binding_mismatch' : 'activity_schema_not_ready');
 if (!options.activityRecoveryFloor) fail('recovery_lineage_unverified');
 assertActivityRecoveryFloorForDatabase(db, options.activityRecoveryFloor, { nodeId, cursorSecret });
 const now = options.clock();
 const cutoff = now - ACTIVITY_RAW_RETENTION_MS;
 const checks = [
  ['activity_events', 'received_at_ms<=?', cutoff], ['activity_changes', 'occurred_at_ms<=?', cutoff],
  ['activity_event_tombstones', 'expires_at_ms<=?', now], ['activity_audit', 'expires_at_ms<=?', now],
  ['activity_probe_state', 'last_received_at_ms IS NOT NULL AND last_received_at_ms<=?', cutoff],
  ['activity_rate_limits', 'window_start_ms<=?', cutoff],
  ['activity_projections', 'received_at_ms IS NOT NULL AND received_at_ms<=?', cutoff],
 ];
 if (checks.some(([table, predicate, limit]) => tableExists(db, table) && db.prepare(`SELECT 1 FROM ${table} WHERE ${predicate} LIMIT 1`).get(limit))) fail('activity_retention_authority_required');
 return { nodeId, cursorSecret };
}
function checkOffline(options, databasePath, phase) {
 // A trusted local supervisor adapter must perform this check; JSON/CLI assertions are not proof.
 if (typeof options.offlineProof !== 'function') fail('offline_proof_required');
 const evidence = options.offlineProof({ databasePath, phase });
 if (evidence?.then || evidence?.allCoreWritersStopped !== true || evidence.databasePath !== databasePath
  || !Number.isSafeInteger(evidence.checkedAt) || evidence.checkedAt > options.clock() || options.clock() - evidence.checkedAt > 60000) fail('offline_proof_required');
}
function writeExclusive(file, content) {
 const fd = openSync(file, 'wx', 0o600);
 try { writeFileSync(fd, content); fsyncSync(fd); } finally { closeSync(fd); }
}
function backupKey(options) {
 if (!(options.backupKey instanceof Uint8Array) || options.backupKey.length !== 32) fail('backup_key_required');
 return Buffer.from(options.backupKey);
}
function authenticateManifest(manifest, key) {
 return createHmac('sha256', key).update('i-core-domain-backup-manifest-v1\0').update(JSON.stringify(manifest)).digest('hex');
}
function decryptBackup(ciphertext, key) {
 if (ciphertext.length < 36 || !ciphertext.subarray(0, 8).equals(magic)) fail('backup_verification_failed');
 try {
  const decipher = createDecipheriv('aes-256-gcm', key, ciphertext.subarray(8, 20));
  decipher.setAAD(magic); decipher.setAuthTag(ciphertext.subarray(20, 36));
  return Buffer.concat([decipher.update(ciphertext.subarray(36)), decipher.final()]);
 } catch { fail('backup_verification_failed'); }
}
function createVerifiedBackup(databasePath, db, baseline, options, fromVersion, toVersion) {
 const key = backupKey(options);
 const backupDirectory = safePath(options.backupDirectory, { directory: true, allowMissing: true });
 mkdirSync(backupDirectory, { recursive: true, mode: 0o700 });
 safePath(backupDirectory, { directory: true });
 const id = randomUUID();
 const encryptedPath = path.join(backupDirectory, `${id}.sqlite.aes256gcm`);
 const manifestPath = path.join(backupDirectory, `${id}.manifest.json`);
 const stageDirectory = mkdtempSync(path.join(backupDirectory, '.domain-migration-'));
 try {
  const stagingPath = path.join(stageDirectory, 'backup.sqlite');
  writeExclusive(stagingPath, readFileSync(databasePath));
  const stage = new DatabaseSync(stagingPath);
  try {
   checkIntegrity(stage); unchanged(stage, baseline);
   stage.exec('PRAGMA journal_mode=DELETE');
   stage.prepare("UPDATE activity_metadata SET value='backup_read_only' WHERE key='database_role'").run();
   stage.prepare("INSERT INTO core_metadata(key,value) VALUES ('domain_backup_role','backup_read_only') ON CONFLICT(key) DO UPDATE SET value=excluded.value").run();
   checkIntegrity(stage);
   if (!activitySchemaStatus(stage).ready) fail('backup_verification_failed');
  } finally { stage.close(); }
  const plaintext = readFileSync(stagingPath);
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, nonce); cipher.setAAD(magic);
  const payload = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const ciphertext = Buffer.concat([magic, nonce, cipher.getAuthTag(), payload]);
  writeExclusive(encryptedPath, ciphertext);
  const backupNow = options.clock();
  const body = { format: 'i-core-domain-backup-v1', kind: 'domain_schema_offline_backup', policy_version: DOMAIN_BACKUP_POLICY, backup_id: id, role: 'backup_read_only',
   from_version: fromVersion, to_version: toVersion, created_at: new Date(backupNow).toISOString(),
   expires_at: new Date(backupNow + BACKUP_RETENTION_MS).toISOString(),
   encrypted_bytes: ciphertext.length, ciphertext_sha256: hash(ciphertext), plaintext_sha256: hash(plaintext),
   activation_supported: false, retention_cleanup_implemented: true };
  writeExclusive(manifestPath, `${JSON.stringify({ ...body, authentication: authenticateManifest(body, key) }, null, 2)}\n`);
  options.testOnlyHook?.('after_backup_write', { db, encryptedPath, manifestPath });
  const persisted = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const { authentication, ...verifiedBody } = persisted;
  const expectedAuth = authenticateManifest(verifiedBody, key);
  if (typeof authentication !== 'string' || !/^[a-f0-9]{64}$/.test(authentication)
   || !timingSafeEqual(Buffer.from(authentication, 'hex'), Buffer.from(expectedAuth, 'hex'))) fail('backup_verification_failed');
  const savedCiphertext = readFileSync(encryptedPath);
  if (hash(savedCiphertext) !== persisted.ciphertext_sha256) fail('backup_verification_failed');
  const decoded = decryptBackup(savedCiphertext, key);
  if (hash(decoded) !== persisted.plaintext_sha256 || !decoded.equals(plaintext)) fail('backup_verification_failed');
  const verificationPath = path.join(stageDirectory, 'verification.sqlite');
  writeExclusive(verificationPath, decoded);
  const verification = new DatabaseSync(verificationPath, { readOnly: true });
  try {
   checkIntegrity(verification);
   if (value(verification, 'domain_backup_role') !== 'backup_read_only' || !activitySchemaStatus(verification).ready) fail('backup_verification_failed');
  } finally { verification.close(); }
  plaintext.fill(0); decoded.fill(0);
  return { backup_id: id, encrypted_path: encryptedPath, manifest_path: manifestPath, verified: true, activation_supported: false };
 } finally {
  key.fill(0);
  // Only our fresh private staging directory; immutable encrypted backup artifacts are retained on failure.
  const relativeStage = path.relative(backupDirectory, safePath(stageDirectory, { directory: true }));
  if (!relativeStage || relativeStage.startsWith('..') || path.isAbsolute(relativeStage)) fail('unsafe_backup_cleanup_path');
  rmSync(stageDirectory, { recursive: true, force: true });
 }
}
function runOffline(databasePath, input, rollback) {
 const options = { clock: Date.now, ...input };
 if (options.testOnlyHook && options.testOnly !== true) fail('test_hook_forbidden');
 const source = safePath(databasePath);
 checkSidecars(source);
 checkOffline(options, source, 'before_open');
 const stat = lstatSync(source);
 const checkSourceIdentity = () => {
  safePath(source);
  const current = lstatSync(source);
  if (current.ino !== stat.ino || current.dev !== stat.dev) fail('database_path_changed');
 };
 const db = new DatabaseSync(source);
 let transaction = false;
 try {
  db.exec('PRAGMA busy_timeout=0; BEGIN EXCLUSIVE'); transaction = true;
  checkSourceIdentity();
  const fromVersion = rollback ? 6 : 5;
  const toVersion = rollback ? 5 : 6;
  const identity = preflight(db, source, options, fromVersion);
  const encryptionKey = backupKey(options);
  try { if (encryptionKey.equals(Buffer.from(identity.cursorSecret, 'base64url'))) fail('backup_key_not_independent'); }
  finally { encryptionKey.fill(0); }
  if (rollback) {
   assertDomainSchemaReady(db);
   for (const name of DOMAIN_TABLE_NAMES.filter((name) => name !== 'domain_schema_migrations')) {
    if (db.prepare(`SELECT 1 FROM ${quote(name)} LIMIT 1`).get()) fail('domain_rollback_not_empty');
   }
   // Migration history is the sole allowed metadata; never discard arbitrary rows posing as migration history.
   const history = db.prepare('SELECT from_version,to_version,metadata_json FROM domain_schema_migrations').all();
   if (history.length !== 1 || history[0].from_version !== 5 || history[0].to_version !== 6) fail('domain_rollback_not_empty');
   try {
    const metadata = JSON.parse(history[0].metadata_json);
    if (Object.keys(metadata).sort().join(',') !== 'at,backup_id,kind'
     || metadata.kind !== 'offline_domain_schema_migration'
     || typeof metadata.backup_id !== 'string' || !/^[a-f0-9-]{36}$/.test(metadata.backup_id)
     || typeof metadata.at !== 'string' || !Number.isFinite(Date.parse(metadata.at))) fail('domain_rollback_not_empty');
   }
   catch { fail('domain_rollback_not_empty'); }
   if (tableExists(db, 'sqlite_sequence') && db.prepare("SELECT 1 FROM sqlite_sequence WHERE name LIKE 'domain_%' AND seq>0 LIMIT 1").get()) fail('domain_rollback_not_empty');
  } else if (db.prepare("SELECT 1 FROM sqlite_master WHERE name LIKE 'domain_%' LIMIT 1").get()) fail('domain_schema_conflict');
  const baseline = legacySnapshot(db);
  checkOffline(options, source, 'before_backup');
  const result = createVerifiedBackup(source, db, baseline, options, fromVersion, toVersion);
  checkOffline(options, source, 'before_ddl');
  checkSourceIdentity();
  if (rollback) {
   for (const name of [...DOMAIN_TABLE_NAMES].reverse()) db.exec(`DROP TABLE ${quote(name)}`);
  } else {
   db.exec(DOMAIN_SCHEMA_SQL);
   db.prepare('INSERT INTO domain_schema_migrations VALUES (?,?,?,?)').run(randomUUID(), 5, 6,
    JSON.stringify({ kind: 'offline_domain_schema_migration', backup_id: result.backup_id, at: new Date(options.clock()).toISOString() }));
  }
  options.testOnlyHook?.('after_ddl', { db });
  db.prepare("UPDATE core_metadata SET value=? WHERE key='schema_version'").run(String(toVersion));
  checkIntegrity(db); unchanged(db, baseline);
  if (!rollback) assertDomainSchemaReady(db);
  checkOffline(options, source, 'before_commit');
  checkSourceIdentity();
  options.testOnlyHook?.('before_commit', { db });
  checkIntegrity(db); unchanged(db, baseline);
  if (!activitySchemaStatus(db).ready) fail('activity_schema_not_ready');
  db.exec('COMMIT'); transaction = false;
  return { ok: true, schema_version: toVersion, backup: result, legacy_verified: true, activation_supported: false };
 } finally {
  if (transaction) { try { db.exec('ROLLBACK'); } catch { /* Preserve the original failure. */ } }
  db.close();
 }
}
export function migrateDomainSchema(databasePath, options = {}) { return runOffline(databasePath, options, false); }
export function rollbackEmptyDomainSchema(databasePath, options = {}) { return runOffline(databasePath, options, true); }

// A validation capability, not a migration/restore capability. The input artifact is
// read as bytes only; SQLite opens only a newly created disposable scratch copy.
function runDomainMigrationCopy(candidatePath, input = {}) {
 const options = { clock: Date.now, ...input };
 if (options.testOnlyHook && options.testOnly !== true) fail('test_hook_forbidden');
 const candidate = safePath(candidatePath);
 const authorize = (phase) => {
  if (typeof options.ownerAuthorization !== 'function') fail('copy_validation_authorization_required');
  const evidence = options.ownerAuthorization({ action: 'validate_domain_migration_copy', candidatePath: candidate, phase });
  const now = options.clock();
  if (evidence?.then || evidence?.authorized !== true || evidence.action !== 'validate_domain_migration_copy'
   || evidence.candidatePath !== candidate || !Number.isSafeInteger(evidence.checkedAt)
   || evidence.checkedAt > now || now - evidence.checkedAt > 60000) fail('copy_validation_authorization_required');
  const descriptor = evidence.trustedCopyDescriptor;
  if (!descriptor || !/^[a-f0-9]{64}$/.test(descriptor.artifact_sha256)
   || !/^[a-f0-9]{64}$/.test(descriptor.source_database_binding_digest)
   || !descriptor.activity_recovery_floor
   || descriptor.copy_consistency?.method !== 'offline_closed_sqlite'
   || descriptor.copy_consistency?.all_core_writers_stopped !== true
   || descriptor.copy_consistency?.sqlite_sidecars_absent !== true) fail('copy_descriptor_unverified');
  return JSON.parse(JSON.stringify(descriptor));
 };
 const descriptor = authorize('before_read');
 if(hash(`activity-live-path:${path.normalize(realpathSync.native(candidate))}`)===descriptor.source_database_binding_digest)fail('copy_must_be_distinct_from_live_path');
 const originalIdentity = lstatSync(candidate);
 const checkCandidate = () => {
  safePath(candidate);
  const current = lstatSync(candidate);
  if (current.dev !== originalIdentity.dev || current.ino !== originalIdentity.ino) fail('copy_artifact_changed');
  for (const suffix of ['-wal','-shm','-journal']) if (existsSync(`${candidate}${suffix}`)) fail('copy_consistency_unverified');
  if (hash(readFileSync(candidate)) !== descriptor.artifact_sha256) fail('copy_artifact_changed');
 };
 const reauthorize = (phase) => {
  if (JSON.stringify(authorize(phase)) !== JSON.stringify(descriptor)) fail('copy_descriptor_changed');
  checkCandidate();
 };
 checkCandidate();
 const scratchRoot = safePath(options.scratchRoot, { directory: true, allowMissing: true });
 mkdirSync(scratchRoot,{recursive:true,mode:0o700}); safePath(scratchRoot,{directory:true});
 const scratch = mkdtempSync(path.join(scratchRoot,'domain-copy-validation-'));
 const scratchPath = path.join(scratch,'validation.sqlite');
 let db;
 let inTransaction = false;
 let result;
 try {
  const destination = path.resolve(options.backupDirectory ?? '');
  const backupRelative = path.relative(scratch,destination);
  if (!backupRelative || (!backupRelative.startsWith('..') && !path.isAbsolute(backupRelative))) fail('backup_directory_inside_scratch');
  const candidateBytes=readFileSync(candidate);
  try {
   if(hash(candidateBytes)!==descriptor.artifact_sha256)fail('copy_artifact_changed');
   writeExclusive(scratchPath,candidateBytes);
  } finally {candidateBytes.fill(0);}
  checkCandidate();
  db = new DatabaseSync(scratchPath);
  checkIntegrity(db);
  if (!tableExists(db,'core_metadata') || value(db,'schema_version') !== '5') fail('unsupported_core_schema_version');
  if (value(db,'domain_backup_role')) fail('backup_activation_unsupported');
  if (!tableExists(db,'activity_metadata')) fail('activity_schema_not_ready');
  const role = db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get()?.value;
  if (role === 'backup_read_only') fail('backup_activation_unsupported');
  if (role !== 'live') fail('activity_schema_not_ready');
  const binding = db.prepare("SELECT value FROM activity_metadata WHERE key='database_binding_digest'").get()?.value;
  if (binding !== descriptor.source_database_binding_digest) fail('copy_source_binding_mismatch');
  if (!activitySchemaStatus(db,{expectedDatabaseBindingDigest:descriptor.source_database_binding_digest}).ready) fail('activity_schema_not_ready');
  const nodeId = value(db,'node_id'); const cursorSecret = value(db,'cursor_secret');
  assertActivityRecoveryFloorForDatabase(db,descriptor.activity_recovery_floor,{nodeId,cursorSecret});
  if (db.prepare("SELECT 1 FROM sqlite_master WHERE name LIKE 'domain_%' LIMIT 1").get()) fail('domain_schema_conflict');
  const independentKey = backupKey(options);
  try { if (independentKey.equals(Buffer.from(cursorSecret,'base64url'))) fail('backup_key_not_independent'); }
  finally { independentKey.fill(0); }
  // The same retention precondition as the live migration remains mandatory.
  const now=options.clock(), cutoff=now-ACTIVITY_RAW_RETENTION_MS;
  const checks=[['activity_events','received_at_ms<=?',cutoff],['activity_changes','occurred_at_ms<=?',cutoff],
   ['activity_event_tombstones','expires_at_ms<=?',now],['activity_audit','expires_at_ms<=?',now],
   ['activity_probe_state','last_received_at_ms IS NOT NULL AND last_received_at_ms<=?',cutoff],
   ['activity_rate_limits','window_start_ms<=?',cutoff],['activity_projections','received_at_ms IS NOT NULL AND received_at_ms<=?',cutoff]];
  if(checks.some(([table,predicate,limit])=>tableExists(db,table)&&db.prepare(`SELECT 1 FROM ${table} WHERE ${predicate} LIMIT 1`).get(limit))) fail('activity_retention_authority_required');
  const originalBaseline=legacySnapshot(db);
  const priorActivityRows=db.prepare("SELECT key,value FROM activity_metadata WHERE key<>'database_role' ORDER BY key").all();
  db.exec('PRAGMA journal_mode=DELETE; BEGIN EXCLUSIVE'); inTransaction=true;
  db.prepare("UPDATE activity_metadata SET value='backup_read_only' WHERE key='database_role'").run();
  db.prepare("INSERT INTO core_metadata(key,value) VALUES('domain_backup_role','backup_read_only')").run();
  db.exec('COMMIT'); inTransaction=false;
  const baseline=legacySnapshot(db);
  const withoutActivity=(snapshot)=>({...snapshot,tables:snapshot.tables.filter(([name])=>name!=='activity_metadata')});
  if(JSON.stringify(withoutActivity(originalBaseline))!==JSON.stringify(withoutActivity(baseline))
   || JSON.stringify(priorActivityRows)!==JSON.stringify(db.prepare("SELECT key,value FROM activity_metadata WHERE key<>'database_role' ORDER BY key").all())) fail('legacy_content_changed');
  options.testOnlyHook?.('copy_marked_read_only',{scratchPath});
  reauthorize('before_backup');
  db.exec('BEGIN EXCLUSIVE'); inTransaction=true;
  const backup=createVerifiedBackup(scratchPath,db,baseline,{...options,testOnlyHook:undefined},5,6);
  reauthorize('before_ddl');
  db.exec(DOMAIN_SCHEMA_SQL);
  db.prepare('INSERT INTO domain_schema_migrations VALUES(?,?,?,?)').run(randomUUID(),5,6,
   JSON.stringify({kind:'offline_domain_schema_migration',backup_id:backup.backup_id,at:new Date(options.clock()).toISOString()}));
  options.testOnlyHook?.('after_copy_ddl',{db,scratchPath});
  db.prepare("UPDATE core_metadata SET value='6' WHERE key='schema_version'").run();
  checkIntegrity(db); unchanged(db,baseline); assertDomainSchemaReady(db);
  if(!activitySchemaStatus(db).ready) fail('activity_schema_not_ready');
  if(value(db,'domain_backup_role')!=='backup_read_only'
   || db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get()?.value!=='backup_read_only') fail('copy_read_only_marker_changed');
  reauthorize('before_commit');
  db.exec('COMMIT'); inTransaction=false;
  options.testOnlyHook?.('copy_validated',{scratchPath});
  reauthorize('after_validation');
  result={ok:true,validation_only:true,source_schema_version:5,validated_schema_version:6,
   integrity_verified:true,legacy_verified:true,candidate_unchanged:true,source_binding_preserved:true,
   recovery_floor_verified:true,activation_supported:false,domain_table_count:DOMAIN_TABLE_NAMES.length,
   backup:{backup_id:backup.backup_id,verified:true,role:'backup_read_only'},physical_erasure_verified:false};
 } finally {
  if(inTransaction){try{db.exec('ROLLBACK');}catch{}}
  db?.close();
  const relative=path.relative(scratchRoot,safePath(scratch,{directory:true}));
  if(!relative||relative.startsWith('..')||path.isAbsolute(relative))fail('unsafe_backup_cleanup_path');
  rmSync(scratch,{recursive:true,force:true});
 }
 checkCandidate();
 return {...result,scratch_removed:true};
}
export function validateDomainMigrationCopy(candidatePath, input = {}) {
 try { return runDomainMigrationCopy(candidatePath,input); }
 catch(error) {
  if(error instanceof DomainSchemaError)throw error;
  const code=['recovery_lineage_unverified','stale_activity_restore','recovery_history_diverged','activity_schema_not_ready'].includes(error?.code)
   ? error.code : 'copy_validation_failed';
  throw new DomainSchemaError(code);
 }
}
const BACKUP_ID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
function readAuthenticated(file, key) {
 safePath(file);
 if (lstatSync(file).size > 16384) fail('backup_manifest_invalid');
 let parsed;
 try { parsed = JSON.parse(readFileSync(file, 'utf8')); } catch { fail('backup_manifest_invalid'); }
 if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) fail('backup_manifest_invalid');
 const { authentication, ...body } = parsed;
 if (typeof authentication !== 'string' || !/^[a-f0-9]{64}$/.test(authentication)
  || !timingSafeEqual(Buffer.from(authentication, 'hex'), Buffer.from(authenticateManifest(body, key), 'hex'))) fail('backup_authentication_failed');
 return body;
}
function cleanupManifest(file, id, key) {
 const body = readAuthenticated(file, key);
 const fields = ['format','kind','policy_version','backup_id','role','from_version','to_version','created_at','expires_at',
  'encrypted_bytes','ciphertext_sha256','plaintext_sha256','activation_supported','retention_cleanup_implemented'];
 if (Object.keys(body).sort().join(',') !== fields.sort().join(',')
  || body.format !== 'i-core-domain-backup-v1' || body.kind !== 'domain_schema_offline_backup'
  || body.policy_version !== DOMAIN_BACKUP_POLICY || body.backup_id !== id || !BACKUP_ID.test(id)
  || body.role !== 'backup_read_only' || body.activation_supported !== false || body.retention_cleanup_implemented !== true
  || ![5,6].includes(body.from_version) || ![5,6].includes(body.to_version) || body.from_version === body.to_version
  || !Number.isSafeInteger(body.encrypted_bytes) || body.encrypted_bytes <= 36
  || !/^[a-f0-9]{64}$/.test(body.ciphertext_sha256) || !/^[a-f0-9]{64}$/.test(body.plaintext_sha256)
  || !Number.isFinite(Date.parse(body.created_at)) || Date.parse(body.expires_at) - Date.parse(body.created_at) !== BACKUP_RETENTION_MS) fail('backup_manifest_invalid');
 return body;
}

// Local-owner library only. No HTTP route or background activation is provided.
// apply is explicit and requires a fresh trusted owner authorization callback.
// Immutable manifests survive cleanup; append-only authenticated receipts contain no database body, key or source path.
export function cleanupExpiredDomainBackups(backupDirectory, input = {}) {
 const options = { clock: Date.now, apply: false, ...input };
 if (typeof options.apply !== 'boolean') fail('invalid_cleanup_mode');
 if (options.testOnlyHook && options.testOnly !== true) fail('test_hook_forbidden');
 const directory = safePath(backupDirectory, { directory: true });
 const directoryIdentity = lstatSync(directory);
 const key = backupKey(options);
 const checkDirectory = () => {
  safePath(directory, { directory: true });
  const current = lstatSync(directory);
  if (current.dev !== directoryIdentity.dev || current.ino !== directoryIdentity.ino) fail('backup_directory_changed');
 };
 const checkOwner = () => {
  if (!options.apply) return;
  if (typeof options.ownerAuthorization !== 'function') fail('cleanup_owner_authorization_required');
  const now = options.clock();
  const evidence = options.ownerAuthorization({ action: 'cleanup_expired_domain_backups', backupDirectory: directory });
  if (evidence?.then || evidence?.authorized !== true || evidence.action !== 'cleanup_expired_domain_backups'
   || evidence.backupDirectory !== directory || !Number.isSafeInteger(evidence.checkedAt)
   || evidence.checkedAt > now || now - evidence.checkedAt > 60000) fail('cleanup_owner_authorization_required');
 };
 try {
  checkOwner();
  const files = readdirSync(directory);
  const results = [];
  for (const file of files.filter((name) => name.endsWith('.manifest.json'))) {
   const id = file.slice(0, -'.manifest.json'.length);
   if (!BACKUP_ID.test(id)) { results.push({ state: 'skipped', code: 'unrecognized_manifest' }); continue; }
   const manifestPath = path.join(directory, file);
   let manifest;
   try { manifest = cleanupManifest(manifestPath, id, key); }
   catch (error) { results.push({ backup_id: id, state: 'blocked', code: error instanceof DomainSchemaError ? error.code : 'backup_manifest_unreadable' }); continue; }
   const manifestDigest = hash(JSON.stringify(manifest));
   if (options.clock() < Date.parse(manifest.expires_at)) { results.push({ backup_id: id, state: 'retained', code: 'not_expired' }); continue; }
   const encryptedPath = path.join(directory, `${id}.sqlite.aes256gcm`);
   // Receipt discovery is constrained to this exact backup ID and directory.
   const prior = [];
   for (const name of files.filter((name) => name.startsWith(`${id}.cleanup.`) && name.endsWith('.json'))) {
    try {
     const receipt = readAuthenticated(path.join(directory, name), key);
     if (receipt.kind === 'domain_backup_cleanup_receipt' && receipt.policy_version === DOMAIN_BACKUP_POLICY
      && receipt.backup_id === id && receipt.manifest_digest === manifestDigest
      && ['pending','completed','failed'].includes(receipt.state)) prior.push(receipt);
    } catch { /* Unknown or tampered receipts never authorize deletion or recovery. */ }
   }
   const exists = (() => { try { lstatSync(encryptedPath); return true; } catch (error) { if (error.code === 'ENOENT') return false; throw error; } })();
   if (prior.some((receipt) => receipt.state === 'completed')) {
    results.push({ backup_id: id, state: exists ? 'blocked' : 'already_cleaned', code: exists ? 'backup_reappeared' : null }); continue;
   }
   let candidateIdentity;
   try {
    checkDirectory();
    if (exists) {
     safePath(encryptedPath);
     candidateIdentity = lstatSync(encryptedPath);
     if (candidateIdentity.size !== manifest.encrypted_bytes || hash(readFileSync(encryptedPath)) !== manifest.ciphertext_sha256) fail('backup_ciphertext_changed');
    } else if (!prior.some((receipt) => receipt.state === 'pending')) fail('backup_missing_without_cleanup_receipt');
   } catch (error) {
    results.push({ backup_id: id, state: 'blocked', code: error instanceof DomainSchemaError ? error.code : 'backup_unreadable' }); continue;
   }
   if (!options.apply) { results.push({ backup_id: id, state: exists ? 'would_delete' : 'would_recover_receipt', expires_at: manifest.expires_at }); continue; }
   const attemptId = randomUUID();
   const receipt = (state, code = null) => {
    checkDirectory();
    const body = { kind: 'domain_backup_cleanup_receipt', policy_version: DOMAIN_BACKUP_POLICY, backup_id: id,
     attempt_id: attemptId, manifest_digest: manifestDigest, state, code, at: new Date(options.clock()).toISOString(),
     encrypted_bytes_removed: state === 'completed' ? manifest.encrypted_bytes : 0,
     physical_erasure_verified: false };
    const target = path.join(directory, `${id}.cleanup.${attemptId}.${state}.json`);
    writeExclusive(target, `${JSON.stringify({ ...body, authentication: authenticateManifest(body,key) })}\n`);
   };
   try {
    checkOwner(); receipt('pending');
    options.testOnlyHook?.('before_cleanup_unlink', { encryptedPath, manifestPath });
    checkOwner(); checkDirectory();
    if (hash(JSON.stringify(cleanupManifest(manifestPath,id,key))) !== manifestDigest) fail('backup_manifest_changed');
    if (exists) {
     const safeTarget = safePath(encryptedPath);
     if (path.dirname(safeTarget) !== directory || path.basename(safeTarget) !== `${id}.sqlite.aes256gcm`) fail('unsafe_backup_cleanup_path');
     const current = lstatSync(safeTarget);
     if (current.dev !== candidateIdentity.dev || current.ino !== candidateIdentity.ino
      || current.size !== candidateIdentity.size || hash(readFileSync(safeTarget)) !== manifest.ciphertext_sha256) fail('backup_ciphertext_changed');
     unlinkSync(safeTarget);
    }
    options.testOnlyHook?.('after_cleanup_unlink', { encryptedPath, manifestPath });
    receipt('completed');
    results.push({ backup_id: id, state: 'cleaned', attempt_id: attemptId });
   } catch (error) {
    const code = error instanceof DomainSchemaError ? error.code : 'cleanup_io_failed';
    let receiptRecorded = false;
    try { receipt('failed',code); receiptRecorded = true; } catch { /* Prior pending receipt permits crash recovery; never claim completion. */ }
    results.push({ backup_id: id, state: 'failed', code, attempt_id: attemptId, failure_receipt_recorded: receiptRecorded });
   }
  }
  return { ok: !results.some((result) => ['blocked','failed'].includes(result.state)), dry_run: !options.apply,
   policy_version: DOMAIN_BACKUP_POLICY, results };
 } finally { key.fill(0); }
}
// Default CLI is strictly read-only. Applying requires the library's trusted local
// supervisor proof adapter, key, and independently retained recovery floor.
export function inspectDomainDatabase(databasePath) {
 const source = safePath(databasePath); checkSidecars(source);
 const db = new DatabaseSync(source, { readOnly: true });
 try { return { ...inspectDomainSchema(db), dry_run: true, activation_supported: false }; }
 finally { db.close(); }
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
 try {
  const args = process.argv.slice(2);
  if (args.includes('--apply') || args.includes('--rollback')) fail('offline_supervisor_adapter_required');
  if (args[0] === 'cleanup-expired' && args.length === 2) {
   const encodedKey = process.env.I_CORE_DOMAIN_BACKUP_KEY;
   if (!encodedKey || !/^[A-Za-z0-9+/]{43}=$/.test(encodedKey)) fail('backup_key_required');
   process.stdout.write(`${JSON.stringify(cleanupExpiredDomainBackups(args[1], { backupKey: Buffer.from(encodedKey, 'base64') }))}\n`);
  } else {
   if (args.length !== 1 || args[0].startsWith('--')) fail('usage_domain_migrate_database_path');
   process.stdout.write(`${JSON.stringify(inspectDomainDatabase(args[0]))}\n`);
  }
 } catch (error) {
  process.stderr.write(`${JSON.stringify({ ok: false, code: error instanceof DomainSchemaError ? error.code : 'domain_migration_failed' })}\n`);
  process.exitCode = 1;
 }
}
