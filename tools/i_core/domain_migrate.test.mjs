import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createDecipheriv, randomBytes } from 'node:crypto';
import { copyFileSync, existsSync, linkSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { ICoreStore } from './i_core_store.mjs';
import { activityRecoveryManifestForDatabase, activitySchemaStatus } from './activity_control_plane.mjs';
import { cleanupExpiredDomainBackups, inspectDomainDatabase, migrateDomainSchema, rollbackEmptyDomainSchema } from './domain_migrate.mjs';
import { assertDomainSchemaReady } from './domain_schema.mjs';

const NOW = 1800000000000;
function fixture(t) {
 const directory = mkdtempSync(path.join(tmpdir(), 'domain-migrate-synthetic-'));
 t.after(() => {
  assert.equal(path.dirname(path.resolve(directory)), path.resolve(tmpdir()));
  assert.equal(path.basename(directory).startsWith('domain-migrate-synthetic-'), true);
  rmSync(directory, { recursive: true, force: true });
 });
 const databasePath = path.join(directory, 'core.sqlite');
 const store = new ICoreStore(databasePath, { clock: () => NOW });
 store.db.exec("CREATE TABLE synthetic_legacy(id INTEGER PRIMARY KEY,body TEXT NOT NULL); INSERT INTO synthetic_legacy VALUES(1,'synthetic body retained exactly')");
 const identity = [store.nodeId, store.cursorSecret];
 const activity = store.db.prepare('SELECT * FROM activity_metadata ORDER BY key').all();
 const activityRecoveryFloor = activityRecoveryManifestForDatabase(store.db, { nodeId: store.nodeId, cursorSecret: store.cursorSecret });
 store.close();
 // A cleanly stopped WAL source is normalized by this synthetic fixture only.
 const checkpoint = new DatabaseSync(databasePath);
 checkpoint.exec('PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE'); checkpoint.close();
 const options = { clock: () => NOW, activityRecoveryFloor, backupKey: randomBytes(32), backupDirectory: path.join(directory, 'backups'),
  offlineProof: ({ databasePath: candidate }) => ({ databasePath: candidate, allCoreWritersStopped: true, checkedAt: NOW }) };
 return { directory, databasePath, options, identity, activity };
}
function inspect(f, check) {
 const db = new DatabaseSync(f.databasePath, { readOnly: true });
 try { return check(db); } finally { db.close(); }
}
function version(f) { return inspect(f, (db) => db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get().value); }
function encryptedBackups(f) { return existsSync(f.options.backupDirectory) ? readdirSync(f.options.backupDirectory).filter((name) => name.endsWith('.aes256gcm')) : []; }

test('A23 schema 5 upgrades durably with encrypted verified immutable backup and old identity/tables intact', (t) => {
 const f = fixture(t);
 const first = migrateDomainSchema(f.databasePath, f.options);
 assert.equal(first.schema_version, 6); assert.equal(first.backup.verified, true);
 assert.equal(inspectDomainDatabase(f.databasePath).ready, true);
 inspect(f, (db) => {
  assertDomainSchemaReady(db);
  assert.equal(db.prepare('SELECT body FROM synthetic_legacy').get().body, 'synthetic body retained exactly');
  assert.deepEqual(['node_id','cursor_secret'].map((key) => db.prepare('SELECT value FROM core_metadata WHERE key=?').get(key).value), f.identity);
  assert.deepEqual(db.prepare('SELECT * FROM activity_metadata ORDER BY key').all(), f.activity);
 });
 const cipher = readFileSync(first.backup.encrypted_path);
 assert.equal(cipher.includes(Buffer.from('synthetic body retained exactly')), false);
 const manifest = JSON.parse(readFileSync(first.backup.manifest_path, 'utf8'));
 assert.equal(manifest.role, 'backup_read_only'); assert.equal(manifest.activation_supported, false);
 assert.equal(JSON.stringify(manifest).includes(f.identity[1]), false);
 assert.throws(() => migrateDomainSchema(f.databasePath, f.options), { code: 'unsupported_core_schema_version' });
 assert.deepEqual(readFileSync(first.backup.encrypted_path), cipher);
});

test('A23 missing/stale offline proof, unknown recovery floor, missing key refuse before DDL', (t) => {
 const f = fixture(t);
 for (const override of [{ offlineProof: undefined }, { offlineProof: () => ({ allCoreWritersStopped: true }) },
  { offlineProof: ({ databasePath }) => ({ databasePath, allCoreWritersStopped: true, checkedAt: NOW - 60001 }) },
  { activityRecoveryFloor: undefined }, { backupKey: undefined }]) {
  assert.throws(() => migrateDomainSchema(f.databasePath, { ...f.options, ...override }));
  assert.equal(version(f), '5');
 }
 assert.equal(encryptedBackups(f).length, 0);
});

test('A23 backup write/verification failure never advances marker and retained backup is not deleted', (t) => {
 const f = fixture(t);
 assert.throws(() => migrateDomainSchema(f.databasePath, { ...f.options, testOnly: true,
  testOnlyHook: (phase, details) => { if (phase === 'after_backup_write') writeFileSync(details.encryptedPath, Buffer.from('synthetic corruption')); } }), { code: 'backup_verification_failed' });
 assert.equal(version(f), '5'); assert.equal(encryptedBackups(f).length, 1);
 assert.equal(readdirSync(f.options.backupDirectory).some((name) => name.startsWith('.domain-migration-')), false);
});

test('A23 DDL interruption rolls back all domain tables while preserving encrypted backup', (t) => {
 const f = fixture(t);
 assert.throws(() => migrateDomainSchema(f.databasePath, { ...f.options, testOnly: true,
  testOnlyHook: (phase) => { if (phase === 'after_ddl') throw new Error('synthetic interruption'); } }), /synthetic interruption/);
 assert.equal(version(f), '5'); assert.equal(encryptedBackups(f).length, 1);
 inspect(f, (db) => assert.equal(db.prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE name LIKE 'domain_%'").get().n, 0));
});

test('A23 old table alteration is detected inside transaction and restored', (t) => {
 const f = fixture(t);
 assert.throws(() => migrateDomainSchema(f.databasePath, { ...f.options, testOnly: true,
  testOnlyHook: (phase, { db }) => { if (phase === 'after_ddl') db.exec("UPDATE synthetic_legacy SET body='changed'"); } }), { code: 'legacy_content_changed' });
 assert.equal(version(f), '5');
 inspect(f, (db) => assert.equal(db.prepare('SELECT body FROM synthetic_legacy').get().body, 'synthetic body retained exactly'));
});

test('A23 offline proof must remain valid until commit', (t) => {
 const f = fixture(t);
 assert.throws(() => migrateDomainSchema(f.databasePath, { ...f.options,
  offlineProof: ({ databasePath, phase }) => ({ databasePath, checkedAt: NOW, allCoreWritersStopped: phase !== 'before_commit' }) }), { code: 'offline_proof_required' });
 assert.equal(version(f), '5'); assert.equal(encryptedBackups(f).length, 1);
});

test('A23 controlled empty rollback restores marker while preserving activity and old tables', (t) => {
 const f = fixture(t); migrateDomainSchema(f.databasePath, f.options);
 const result = rollbackEmptyDomainSchema(f.databasePath, f.options);
 assert.equal(result.schema_version, 5); assert.equal(version(f), '5');
 assert.equal(encryptedBackups(f).length, 2);
 inspect(f, (db) => {
  assert.deepEqual(db.prepare('SELECT * FROM activity_metadata ORDER BY key').all(), f.activity);
  assert.equal(activitySchemaStatus(db).ready, true);
  assert.equal(db.prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE name LIKE 'domain_%'").get().n, 0);
 });
});

test('A23 any production, shadow, credential or phone capability prevents rollback', (t) => {
 for (const sql of [
  "INSERT INTO domain_records VALUES('production','example','id',1,'{}','{}')",
  "INSERT INTO domain_records VALUES('shadow','example','id',1,'{}','{}')",
  "INSERT INTO domain_principals VALUES('p','hash',1,'active',NULL,'d','i','{}')",
  "INSERT INTO domain_phone_capabilities VALUES('d','c','hash',1,'2026-10-05T00:00:00.000Z')",
  "INSERT INTO domain_registry VALUES('example','off',NULL,'{}','v1')",
 ]) {
  const f = fixture(t); migrateDomainSchema(f.databasePath, f.options);
  const db = new DatabaseSync(f.databasePath); db.exec(sql); db.close();
  assert.throws(() => rollbackEmptyDomainSchema(f.databasePath, f.options), { code: 'domain_rollback_not_empty' });
  assert.equal(version(f), '6'); assert.equal(encryptedBackups(f).length, 1);
 }
});

test('A24 backup cannot activate and copied live database cannot migrate at a different path', (t) => {
 const f = fixture(t);
 const copy = path.join(f.directory, 'copy.sqlite'); copyFileSync(f.databasePath, copy);
 assert.throws(() => migrateDomainSchema(copy, f.options));
 const result = migrateDomainSchema(f.databasePath, f.options);
 const encrypted = readFileSync(result.backup.encrypted_path);
 const decipher = createDecipheriv('aes-256-gcm', f.options.backupKey, encrypted.subarray(8,20));
 decipher.setAAD(encrypted.subarray(0,8)); decipher.setAuthTag(encrypted.subarray(20,36));
 const candidate = path.join(f.directory, 'decrypted-backup.sqlite');
 writeFileSync(candidate, Buffer.concat([decipher.update(encrypted.subarray(36)), decipher.final()]));
 assert.throws(() => migrateDomainSchema(candidate, f.options), { code: 'backup_activation_unsupported' });
 assert.throws(() => new ICoreStore(candidate), { code: 'backup_activation_unsupported' });
});

test('A23 reject symlink backup directory, non-quiescent sidecars and missing database without creating source', (t) => {
 const f = fixture(t);
 const alias = path.join(f.directory, 'backup-alias');
 symlinkSync(f.directory, alias, process.platform === 'win32' ? 'junction' : 'dir');
 assert.throws(() => migrateDomainSchema(f.databasePath, { ...f.options, backupDirectory: alias }), { code: 'unsafe_database_path' });
 writeFileSync(`${f.databasePath}-wal`, 'synthetic nonempty WAL');
 assert.throws(() => migrateDomainSchema(f.databasePath, f.options), { code: 'sqlite_sidecars_not_quiescent' });
 const missing = path.join(f.directory, 'missing.sqlite');
 assert.throws(() => migrateDomainSchema(missing, f.options), { code: 'database_path_missing' });
 assert.equal(existsSync(missing), false);
});


test('A23 existing writer blocks migration even with an affirmative supervisor callback', (t) => {
 const f = fixture(t);
 const writer = new DatabaseSync(f.databasePath);
 try {
  writer.exec('BEGIN IMMEDIATE');
  assert.throws(() => migrateDomainSchema(f.databasePath, f.options), /locked/);
  assert.equal(encryptedBackups(f).length, 0);
 } finally { writer.exec('ROLLBACK'); writer.close(); }
 assert.equal(version(f), '5');
});

test('A23 filesystem backup destination failure does not modify schema', (t) => {
 const f = fixture(t);
 writeFileSync(f.options.backupDirectory, 'synthetic existing file');
 assert.throws(() => migrateDomainSchema(f.databasePath, f.options), { code: 'unsafe_database_path' });
 assert.equal(version(f), '5');
 assert.equal(readFileSync(f.options.backupDirectory, 'utf8'), 'synthetic existing file');
});

test('A23 abrupt child exit inside migration transaction recovers schema 5 with backup intact', (t) => {
 const f = fixture(t);
 const input = { databasePath: f.databasePath, backupDirectory: f.options.backupDirectory,
  backupKey: f.options.backupKey.toString('base64'), activityRecoveryFloor: f.options.activityRecoveryFloor, now: NOW };
 const script = `
  import { readFileSync } from 'node:fs';
  import { migrateDomainSchema } from ${JSON.stringify(new URL('./domain_migrate.mjs', import.meta.url).href)};
  const f = JSON.parse(readFileSync(0,'utf8'));
  migrateDomainSchema(f.databasePath, { backupDirectory:f.backupDirectory, backupKey:Buffer.from(f.backupKey,'base64'),
   activityRecoveryFloor:f.activityRecoveryFloor, clock:()=>f.now, testOnly:true,
   offlineProof:({databasePath})=>({databasePath,allCoreWritersStopped:true,checkedAt:f.now}),
   testOnlyHook:(phase)=>{ if(phase==='after_ddl') process.exit(71); }
  });
 `;
 const result = spawnSync(process.execPath, ['--input-type=module','-e',script], { input: JSON.stringify(input), encoding:'utf8' });
 assert.equal(result.status, 71, result.stderr);
 const recovered = new DatabaseSync(f.databasePath);
 try {
  assert.equal(recovered.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get().value,'5');
  assert.equal(recovered.prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE name LIKE 'domain_%'").get().n,0);
  assert.equal(recovered.prepare('PRAGMA integrity_check').get().integrity_check,'ok');
 } finally { recovered.close(); }
 assert.equal(encryptedBackups(f).length,1);
});

test('A23 backup encryption key must not reuse Core cursor secret', (t) => {
 const f = fixture(t);
 assert.throws(() => migrateDomainSchema(f.databasePath, { ...f.options, backupKey: Buffer.from(f.identity[1], 'base64url') }), { code: 'backup_key_not_independent' });
 assert.equal(version(f), '5'); assert.equal(encryptedBackups(f).length, 0);
});


test('A23 previously allocated domain change or nonstandard migration metadata forbids empty downgrade', (t) => {
 for (const sql of [
  "INSERT INTO domain_changes(namespace,domain,id,revision,domain_sequence,changed_at) VALUES('production','example','id',1,1,'2026-10-05T00:00:00.000Z'); DELETE FROM domain_changes",
  "UPDATE domain_schema_migrations SET metadata_json=json_set(metadata_json,'$.unexpected_private_body','synthetic-private')",
 ]) {
  const f = fixture(t); migrateDomainSchema(f.databasePath, f.options);
  const db = new DatabaseSync(f.databasePath); db.exec(sql); db.close();
  assert.throws(() => rollbackEmptyDomainSchema(f.databasePath, f.options), { code: 'domain_rollback_not_empty' });
  assert.equal(version(f), '6');
 }
});


const BACKUP_EXPIRY = NOW + 30 * 86400000;
function cleanupOptions(f, now = BACKUP_EXPIRY, extra = {}) {
 return { backupKey: f.options.backupKey, clock: () => now,
  ownerAuthorization: ({ action, backupDirectory }) => ({ action, backupDirectory, authorized: true, checkedAt: now }), ...extra };
}
test('A23 cleanup defaults dry-run, honors exact 30-day expiry, keeps source and immutable manifest, reruns idempotently', (t) => {
 const f = fixture(t); const migrated = migrateDomainSchema(f.databasePath,f.options);
 const sourceBytes = readFileSync(f.databasePath);
 const manifestBytes = readFileSync(migrated.backup.manifest_path);
 const originalFiles = readdirSync(f.options.backupDirectory);
 let result = cleanupExpiredDomainBackups(f.options.backupDirectory,cleanupOptions(f,BACKUP_EXPIRY-1));
 assert.equal(result.results[0].state,'retained');
 result = cleanupExpiredDomainBackups(f.options.backupDirectory,cleanupOptions(f));
 assert.equal(result.dry_run,true); assert.equal(result.results[0].state,'would_delete');
 assert.deepEqual(readdirSync(f.options.backupDirectory),originalFiles);
 result = cleanupExpiredDomainBackups(f.options.backupDirectory,cleanupOptions(f,BACKUP_EXPIRY,{apply:true}));
 assert.equal(result.results[0].state,'cleaned');
 assert.equal(existsSync(migrated.backup.encrypted_path),false);
 assert.deepEqual(readFileSync(migrated.backup.manifest_path),manifestBytes);
 assert.deepEqual(readFileSync(f.databasePath),sourceBytes);
 const after = readdirSync(f.options.backupDirectory);
 result = cleanupExpiredDomainBackups(f.options.backupDirectory,cleanupOptions(f,BACKUP_EXPIRY,{apply:true}));
 assert.equal(result.results[0].state,'already_cleaned');
 assert.deepEqual(readdirSync(f.options.backupDirectory),after);
 const receipt = after.find(name=>name.endsWith('.completed.json'));
 const body = JSON.parse(readFileSync(path.join(f.options.backupDirectory,receipt),'utf8'));
 assert.equal(body.state,'completed'); assert.equal(body.physical_erasure_verified,false);
 assert.equal(JSON.stringify(body).includes(f.identity[1]),false);
});

test('A23 cleanup requires explicit fresh owner authorization and ignores unrelated files', (t) => {
 const f = fixture(t); const migrated = migrateDomainSchema(f.databasePath,f.options);
 const unknown = path.join(f.options.backupDirectory,'unrelated.manifest.json');
 writeFileSync(unknown,JSON.stringify({path:f.databasePath,expires_at:'2000-01-01'}));
 assert.throws(()=>cleanupExpiredDomainBackups(f.options.backupDirectory,cleanupOptions(f,BACKUP_EXPIRY,{apply:true,ownerAuthorization:undefined})),{code:'cleanup_owner_authorization_required'});
 const result = cleanupExpiredDomainBackups(f.options.backupDirectory,cleanupOptions(f));
 assert.equal(result.results.some(item=>item.code==='unrecognized_manifest'),true);
 assert.equal(existsSync(migrated.backup.encrypted_path),true); assert.equal(existsSync(unknown),true);
});

test('A23 tampered manifest path and ciphertext hardlink fail closed without deleting source', (t) => {
 const f = fixture(t); const migrated = migrateDomainSchema(f.databasePath,f.options);
 const original = readFileSync(migrated.backup.manifest_path);
 const manifest = JSON.parse(original); manifest.path=f.databasePath;
 writeFileSync(migrated.backup.manifest_path,JSON.stringify(manifest));
 let result=cleanupExpiredDomainBackups(f.options.backupDirectory,cleanupOptions(f,BACKUP_EXPIRY,{apply:true}));
 assert.equal(result.results[0].state,'blocked'); assert.equal(existsSync(migrated.backup.encrypted_path),true);
 writeFileSync(migrated.backup.manifest_path,original);
 const alias = path.join(f.directory,'ciphertext-hardlink'); linkSync(migrated.backup.encrypted_path,alias);
 result=cleanupExpiredDomainBackups(f.options.backupDirectory,cleanupOptions(f,BACKUP_EXPIRY,{apply:true}));
 assert.equal(result.results[0].code,'unsafe_database_path');
 assert.equal(existsSync(alias),true); assert.equal(version(f),'6');
});

test('A23 cleanup rejects redirected backup directory and symlinked package', (t) => {
 const f = fixture(t); const migrated = migrateDomainSchema(f.databasePath,f.options);
 const alias=path.join(f.directory,'cleanup-alias');
 symlinkSync(f.options.backupDirectory,alias,process.platform==='win32'?'junction':'dir');
 assert.throws(()=>cleanupExpiredDomainBackups(alias,cleanupOptions(f)),{code:'unsafe_database_path'});
 // A directory junction is also rejected as a candidate ciphertext object on Windows.
 unlinkSync(migrated.backup.encrypted_path);
 symlinkSync(f.directory,migrated.backup.encrypted_path,process.platform==='win32'?'junction':'dir');
 const result=cleanupExpiredDomainBackups(f.options.backupDirectory,cleanupOptions(f,BACKUP_EXPIRY,{apply:true}));
 assert.equal(result.results[0].code,'unsafe_database_path'); assert.equal(version(f),'6');
});

test('A23 cleanup failure writes minimal retry metadata and successful retry is idempotent', (t) => {
 const f = fixture(t); const migrated=migrateDomainSchema(f.databasePath,f.options);
 const result=cleanupExpiredDomainBackups(f.options.backupDirectory,cleanupOptions(f,BACKUP_EXPIRY,{apply:true,testOnly:true,
  testOnlyHook:()=>{throw new Error('synthetic private error must not persist');}}));
 assert.equal(result.results[0].state,'failed'); assert.equal(result.results[0].failure_receipt_recorded,true);
 assert.equal(existsSync(migrated.backup.encrypted_path),true);
 const file=readdirSync(f.options.backupDirectory).find(name=>name.endsWith('.failed.json'));
 const receipt=readFileSync(path.join(f.options.backupDirectory,file),'utf8');
 assert.equal(receipt.includes('synthetic private error'),false);
 const retried=cleanupExpiredDomainBackups(f.options.backupDirectory,cleanupOptions(f,BACKUP_EXPIRY,{apply:true}));
 assert.equal(retried.results[0].state,'cleaned');
});

test('A23 cleanup recovers interrupted post-unlink receipt and rejects unexpected missing backup', (t) => {
 const f = fixture(t); const migrated=migrateDomainSchema(f.databasePath,f.options);
 let result=cleanupExpiredDomainBackups(f.options.backupDirectory,cleanupOptions(f,BACKUP_EXPIRY,{apply:true,testOnly:true,
  testOnlyHook:(phase)=>{if(phase==='after_cleanup_unlink')throw new Error('synthetic receipt interruption');}}));
 assert.equal(result.results[0].state,'failed'); assert.equal(existsSync(migrated.backup.encrypted_path),false);
 result=cleanupExpiredDomainBackups(f.options.backupDirectory,cleanupOptions(f,BACKUP_EXPIRY,{apply:true}));
 assert.equal(result.results[0].state,'cleaned');
 const other=fixture(t); const second=migrateDomainSchema(other.databasePath,other.options);
 unlinkSync(second.backup.encrypted_path);
 result=cleanupExpiredDomainBackups(other.options.backupDirectory,cleanupOptions(other,BACKUP_EXPIRY,{apply:true}));
 assert.equal(result.results[0].code,'backup_missing_without_cleanup_receipt');
});

test('A23 cleanup CLI only previews and never exposes backup key or permits apply', (t) => {
 const f=fixture(t); const migrated=migrateDomainSchema(f.databasePath,f.options);
 const script=new URL('./domain_migrate.mjs',import.meta.url);
 const result=spawnSync(process.execPath,[fileURLToPath(script),'cleanup-expired',f.options.backupDirectory],
  {encoding:'utf8',env:{...process.env,I_CORE_DOMAIN_BACKUP_KEY:f.options.backupKey.toString('base64')}});
 assert.equal(result.status,0,result.stderr);
 assert.equal(JSON.parse(result.stdout).dry_run,true);
 assert.equal(result.stdout.includes(f.options.backupKey.toString('base64')),false);
 const apply=spawnSync(process.execPath,[fileURLToPath(script),'cleanup-expired',f.options.backupDirectory,'--apply'],{encoding:'utf8'});
 assert.equal(apply.status,1);
 assert.equal(JSON.parse(apply.stderr.trim().split('\n').find(line=>line.startsWith('{'))).code,'offline_supervisor_adapter_required');
 assert.equal(existsSync(migrated.backup.encrypted_path),true);
});
