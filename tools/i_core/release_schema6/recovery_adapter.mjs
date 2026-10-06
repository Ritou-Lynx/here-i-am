import { createHmac, timingSafeEqual } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync, lstatSync, realpathSync, readdirSync, openSync, closeSync, fsyncSync, renameSync, unlinkSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import { activityRecoveryManifestForDatabase, assertActivityRecoveryFloorForDatabase, activitySchemaStatus, migrateActivitySchema } from '../activity_control_plane.mjs';
import { migrateDomainSchema, rollbackEmptyDomainSchema } from '../domain_migrate.mjs';
import { assertDomainSchemaReady } from '../domain_schema.mjs';
import { plainPath, sha256, fail } from './package.mjs';
import { assertOfflineLease } from './lifecycle/offline_lease.mjs';
import { verifyInitialRuntimeBackup } from './backup_bundle.mjs';

// No CLI, boolean proof, injectable verifier, ENV switch, or synthetic lease export.
// Only the fixed supervisor module can recognize a live offline capability.
const HEX = /^[a-f0-9]{64}$/;
const encode = value => JSON.stringify(value, (_, v) => typeof v === 'bigint' ? { integer: String(v) } : v instanceof Uint8Array ? { bytes: Buffer.from(v).toString('base64') } : v);
const meta = (db, key) => db.prepare('SELECT value FROM core_metadata WHERE key=?').get(key)?.value;
const quote = name => `"${name.replaceAll('"', '""')}"`;
const mac = (body, key) => createHmac('sha256', key).update('i-core-floor-custody-v1\0').update(JSON.stringify(body)).digest('hex');
function key32(key) { if (!(key instanceof Uint8Array) || key.length !== 32) fail('independent_custody_key_required'); return Buffer.from(key); }
function separated(a, b) {
 for (const [first, second] of [[a,b],[b,a]]) {
  const relative = path.relative(first, second);
  if (!relative || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative))) fail('custody_must_be_independent');
 }
}
function strictClosedPath(filename) {
 plainPath(filename);
 for (const suffix of ['-wal','-shm','-journal']) if (existsSync(filename + suffix)) fail('sqlite_sidecars_not_quiescent');
 return filename;
}
function proof(options, phase) {
 if (options.custodyLock) {
  const current = lstatSync(plainPath(options.custodyLock.path));
  if (current.ino !== options.custodyLock.ino || current.dev !== options.custodyLock.dev) fail('custody_lock_lost');
 }
 const evidence = assertOfflineLease(options.supervisorLease, { databasePath: options.databasePath, phase });
 const now = Date.now();
 if (!evidence || evidence.then || evidence.allCoreWritersStopped !== true || evidence.databasePath !== options.databasePath
   || !Number.isSafeInteger(evidence.checkedAt) || evidence.checkedAt > now || now - evidence.checkedAt > 60000) fail('offline_supervisor_capability_required');
 const receipt = evidence.cleanCloseReceipt;
 if (!receipt || typeof receipt.receiptId !== 'string' || !receipt.receiptId || receipt.databasePath !== options.databasePath
   || typeof receipt.nodeId !== 'string' || !HEX.test(receipt.databaseSha256 ?? '')) fail('clean_close_receipt_required');
 return evidence;
}
function configured(input) {
 const options = { ...input };
 plainPath(options.databasePath);
 plainPath(options.custodyDirectory, { missing: true });
 separated(path.dirname(options.databasePath), options.custodyDirectory);
 if (options.backupDirectory) { plainPath(options.backupDirectory, { missing: true }); separated(options.backupDirectory, options.custodyDirectory); }
 key32(options.custodyKey).fill(0);
 return options;
}
// Independent anti-rollback authority lives outside the database/state and its
// restore inventory. Neither old DB+old receipt nor old floor can rewind this head.
function authenticated(raw, key, kind) {
 let envelope; try { envelope=JSON.parse(raw); } catch { fail('custody_invalid'); }
 const {authentication,...body}=envelope;
 if (!HEX.test(authentication??'') || !timingSafeEqual(Buffer.from(authentication,'hex'),Buffer.from(mac(body,key),'hex')) || body.format!==kind) fail('custody_authentication_failed');
 return body;
}
function readHead(options, {allowMissing=false}={}) {
 const filename=path.join(options.custodyDirectory,'current-head.json');
 if (!existsSync(filename)) {
  const leftovers=existsSync(options.custodyDirectory) ? readdirSync(options.custodyDirectory).filter(n=>n!=='custody.lock') : [];
  if (allowMissing && leftovers.length===0) return null;
  fail('independent_custody_head_required');
 }
 const raw=readFileSync(plainPath(filename));
 if(raw.length>16384)fail('custody_head_invalid');
 const head=authenticated(raw,options.custodyKey,'i-core-custody-head-v1');
 if(head.databasePath!==options.databasePath || !HEX.test(head.custodySha256??'') || !Number.isSafeInteger(head.generation) || head.generation<1)fail('custody_head_invalid');
 // The immutable immediate predecessor makes a truncated/replaced head chain
 // detectable. The externally protected current head is the anti-rollback root.
 if(head.generation===1 ? head.previousHeadSha256!==null : !HEX.test(head.previousHeadSha256??''))fail('custody_head_invalid');
 if(head.generation>1){
  const priorRaw=readFileSync(plainPath(path.join(options.custodyDirectory,head.previousHeadSha256+'.head.json')));
  if(sha256(priorRaw)!==head.previousHeadSha256)fail('custody_head_chain_invalid');
  const prior=authenticated(priorRaw,options.custodyKey,'i-core-custody-head-v1');
  if(prior.generation!==head.generation-1 || prior.databasePath!==head.databasePath || prior.nodeId!==head.nodeId)fail('custody_head_chain_invalid');
 }
 const own=readFileSync(plainPath(path.join(options.custodyDirectory,sha256(raw)+'.head.json')));
 if(!raw.equals(own))fail('custody_head_chain_invalid');
 return {...head,headSha256:sha256(raw)};
}
function headMatches(head, receipt, info, {newClose=false}={}) {
 if(!head || head.custodySha256!==receipt.custodySha256 || head.nodeId!==info.nodeId
   || (!newClose && head.receiptId!==receipt.receiptId))fail('custody_head_rollback_rejected');
}
function withCustodyLock(input, work) {
 const options=configured(input);
 proof(options,'before_custody_lock');
 mkdirSync(options.custodyDirectory,{recursive:true,mode:0o700});plainPath(options.custodyDirectory);
 const lockPath=path.join(options.custodyDirectory,'custody.lock');
 let fd;try{fd=openSync(lockPath,'wx',0o600);}catch{fail('custody_concurrent_operation');}
 const stat=lstatSync(lockPath);options.custodyLock={path:lockPath,ino:stat.ino,dev:stat.dev};
 try{writeFileSync(fd,'i-core-custody-lock-v1\n');fsyncSync(fd);return work(options);}
 finally{closeSync(fd);const current=lstatSync(plainPath(lockPath));if(current.ino!==stat.ino||current.dev!==stat.dev)fail('custody_lock_lost');unlinkSync(lockPath);}
}
function writeHead(options, body, previous) {
 proof(options,'before_custody_head_commit');
 const headFile=path.join(options.custodyDirectory,'current-head.json');
 const current=previous||existsSync(headFile)?readHead(options):null;
 if(current?.headSha256!==previous?.headSha256)fail('custody_head_changed');
 const head={format:'i-core-custody-head-v1',generation:(previous?.generation??0)+1,previousHeadSha256:previous?.headSha256??null,
  custodySha256:body.custodySha256,receiptId:body.receiptId,nodeId:body.nodeId,databasePath:options.databasePath};
 const raw=Buffer.from(JSON.stringify({...head,authentication:mac(head,options.custodyKey)})+'\n'),headSha256=sha256(raw);
 writeFileSync(path.join(options.custodyDirectory,headSha256+'.head.json'),raw,{flag:'wx',mode:0o600,flush:true});
 const pending=path.join(options.custodyDirectory,'current-head.pending');writeFileSync(pending,raw,{flag:'wx',mode:0o600,flush:true});
 renameSync(pending,path.join(options.custodyDirectory,'current-head.json'));
 const checked=readHead(options);if(checked.headSha256!==headSha256)fail('custody_head_write_unverified');
 proof(options,'after_custody_head_commit');
 return {custodyGeneration:head.generation,headSha256};
}
function emptyGenesis(db) {
 const objects=db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").all();
 const allowed=new Set(['core_metadata','activity_metadata','activity_schema_migrations','activity_runtime_claim','domain_schema_migrations']);
 for(const {name} of objects)if(!allowed.has(name)&&db.prepare('SELECT 1 FROM '+quote(name)+' LIMIT 1').get())fail('custody_genesis_not_empty');
 const claim=db.prepare('SELECT runtime_fence FROM activity_runtime_claim WHERE singleton=1').get();
 if(claim.runtime_fence!==0)fail('custody_genesis_not_empty');
}
function inspect(options, callback) {
 strictClosedPath(options.databasePath);
 const before = sha256(readFileSync(options.databasePath));
 const db = new DatabaseSync(`${pathToFileURL(options.databasePath).href}?mode=ro&immutable=1`, { readOnly: true });
 try {
  if (db.prepare('PRAGMA integrity_check').all().some(row => Object.values(row)[0] !== 'ok') || db.prepare('PRAGMA foreign_key_check').all().length) fail('database_integrity_failed');
  const version = Number(meta(db,'schema_version')), nodeId = meta(db,'node_id'), cursorSecret = meta(db,'cursor_secret');
  if (![4,5,6].includes(version) || !/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(nodeId ?? '') || !/^[A-Za-z0-9_-]{43}$/.test(cursorSecret ?? '')) fail('core_identity_invalid');
  if (meta(db,'domain_backup_role')) fail('backup_activation_unsupported');
  if (Buffer.from(options.custodyKey).equals(Buffer.from(cursorSecret,'base64url'))) fail('custody_key_not_independent');
  if (version === 4) {
   if (db.prepare("SELECT 1 FROM sqlite_master WHERE name LIKE 'activity_%' OR name LIKE 'domain_%' LIMIT 1").get()
      || db.prepare("SELECT 1 FROM core_metadata WHERE key LIKE 'activity_%' OR key LIKE 'domain_%' LIMIT 1").get()) fail('schema4_genesis_not_empty');
  } else {
   const role = db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get()?.value;
   if (role !== 'live') fail('backup_activation_unsupported');
   const status = activitySchemaStatus(db, { expectedDatabaseBindingDigest: sha256(`activity-live-path:${path.normalize(realpathSync.native(options.databasePath))}`) });
   if (!status.ready) fail(status.reason === 'database_binding_mismatch' ? 'activity_database_binding_mismatch' : 'activity_schema_not_ready');
   const claim = db.prepare('SELECT runtime_id,lease_expires_at_ms FROM activity_runtime_claim WHERE singleton=1').get();
   if (!claim || claim.runtime_id !== '' || claim.lease_expires_at_ms !== 0) fail('active_runtime_claim');
   if (version === 6) assertDomainSchemaReady(db);
  }
  return callback(db, { version, nodeId, cursorSecret, databaseSha256: before });
 } finally { db.close(); if (sha256(readFileSync(options.databasePath)) !== before) fail('database_changed_during_inspection'); strictClosedPath(options.databasePath); }
}
function legacyDigest(db) {
 const objects = db.prepare("SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'activity_%' AND name NOT LIKE 'domain_%' AND tbl_name NOT LIKE 'activity_%' AND tbl_name NOT LIKE 'domain_%' ORDER BY type,name").all();
 const rows = objects.filter(x => x.type === 'table').map(x => {
  const stmt = db.prepare(`SELECT * FROM ${quote(x.name)}`); stmt.setReadBigInts(true);
  const data = stmt.all().filter(row => x.name !== 'core_metadata' || !['schema_version','activity_schema_version'].includes(row.key))
   .filter(row => x.name !== 'sqlite_sequence' || !/^(activity_|domain_)/.test(row.name));
  return [x.name, data.map(encode).sort()];
 });
 return sha256(encode({ objects, rows }));
}
function receiptMatches(receipt, info) {
 if (receipt.nodeId !== info.nodeId || receipt.databaseSha256 !== info.databaseSha256) fail('clean_close_identity_mismatch');
}
function readCustody(options, info, receipt) {
 headMatches(readHead(options),receipt,info);
 if (!HEX.test(receipt.custodySha256 ?? '')) fail('independent_recovery_floor_required');
 const filename = plainPath(path.join(options.custodyDirectory, `${receipt.custodySha256}.floor.json`));
 if (lstatSync(filename).size > 4 * 1024 * 1024) fail('custody_too_large');
 const raw = readFileSync(filename);
 if (sha256(raw) !== receipt.custodySha256) fail('custody_digest_mismatch');
 let envelope; try { envelope = JSON.parse(raw); } catch { fail('custody_invalid'); }
 const { authentication, ...body } = envelope;
 const expected = mac(body, options.custodyKey);
 if (!HEX.test(authentication ?? '') || !timingSafeEqual(Buffer.from(authentication,'hex'), Buffer.from(expected,'hex'))) fail('custody_authentication_failed');
 if (body.format !== 'i-core-floor-custody-v1' || body.databasePath !== options.databasePath || body.nodeId !== info.nodeId
   || body.databaseSha256 !== info.databaseSha256 || body.schemaVersion !== info.version || body.cleanCloseReceiptId !== receipt.receiptId) fail('custody_identity_mismatch');
 return body;
}
function saveCustody(options, receipt, origin, expectedFloor = null) {
 proof(options, 'before_custody_capture');
 const previous = readHead(options,{allowMissing:origin==='verified_schema4_genesis'||origin==='empty_provision'});
 if (!previous && !['verified_schema4_genesis','empty_provision'].includes(origin)) fail('independent_custody_head_required');
 const body = inspect(options, (db, info) => {
  if (info.version === 4) fail('activity_floor_not_created');
  if (expectedFloor) assertActivityRecoveryFloorForDatabase(db, expectedFloor, info);
  return { format:'i-core-floor-custody-v1', databasePath:options.databasePath, nodeId:info.nodeId,
   schemaVersion:info.version, databaseSha256:info.databaseSha256, cleanCloseReceiptId:receipt.receiptId,
   origin, activityRecoveryFloor:activityRecoveryManifestForDatabase(db, info) };
 });
 proof(options, 'before_custody_write');
 mkdirSync(options.custodyDirectory,{recursive:true,mode:0o700}); plainPath(options.custodyDirectory);
 const raw = Buffer.from(JSON.stringify({...body,authentication:mac(body,options.custodyKey)})+'\n');
 const custodySha256 = sha256(raw), custodyPath = path.join(options.custodyDirectory,`${custodySha256}.floor.json`);
 if (existsSync(custodyPath)) { if (!readFileSync(plainPath(custodyPath)).equals(raw)) fail('custody_collision'); }
 else writeFileSync(custodyPath,raw,{flag:'wx',mode:0o600,flush:true});
 proof(options, 'after_custody_write');
 if (!readFileSync(plainPath(custodyPath)).equals(raw)) fail('custody_write_unverified');
 strictClosedPath(options.databasePath);
 if(sha256(readFileSync(options.databasePath))!==body.databaseSha256)fail('database_changed_before_custody_commit');
 const head = writeHead(options,{custodySha256,receiptId:receipt.receiptId,nodeId:body.nodeId},previous);
 return { custodyPath,custodySha256,databaseSha256:body.databaseSha256,nodeId:body.nodeId,schemaVersion:body.schemaVersion,...head };
}
// This is ONLY called by the supervisor after an actual clean close. The resulting
// hash must be pinned in its independent durable lifecycle receipt before restart.
export function sealClosedRecovery(input) {
 return withCustodyLock(input,options=>{
  const evidence=proof(options,'seal_clean_close'),receipt=evidence.cleanCloseReceipt;
  const prior=readHead(options,{allowMissing:evidence.origin==='empty_provision'});
  inspect(options,(db,info)=>{receiptMatches(receipt,info);if(prior)headMatches(prior,receipt,info,{newClose:true});else emptyGenesis(db);});
  return saveCustody(options,receipt,prior?'supervisor_clean_close':'empty_provision');
 });
}
export function verifyCanonicalRestart(input) {
 return withCustodyLock(input,options=>{
 const receipt = proof(options,'verify_restart').cleanCloseReceipt;
 const result = inspect(options,(db,info) => {
  receiptMatches(receipt,info);
  if (info.version !== 6) fail('schema6_required');
  const body = readCustody(options,info,receipt);
  assertActivityRecoveryFloorForDatabase(db,body.activityRecoveryFloor,info);
  return { ok:true,databasePath:options.databasePath,nodeId:info.nodeId,schemaVersion:6,databaseSha256:info.databaseSha256,custodySha256:receipt.custodySha256,recoveryFloorVerified:true,activationSupported:false };
 });
 proof(options,'after_verify_restart');
 // Do not forward an activityRecoveryFloor to createICoreServer: the Core correctly
 // rejects that as unsupported backup activation. Start only this same live path.
 return result;
 });
}
function transition(options, rollback) {
 const receipt = proof(options,'before_transition').cleanCloseReceipt;
 const initial = inspect(options,(db,info) => {
  receiptMatches(receipt,info);
  if(info.version===4 && readHead(options,{allowMissing:true}))fail('schema4_custody_history_exists');
  const custody = info.version === 4 ? null : readCustody(options,info,receipt);
  if (custody) assertActivityRecoveryFloorForDatabase(db,custody.activityRecoveryFloor,info);
  return {...info,legacyDigest:legacyDigest(db),floor:custody?.activityRecoveryFloor};
 });
 if (rollback ? initial.version !== 6 : ![4,5].includes(initial.version)) fail('unsupported_transition');
 if (Buffer.from(options.backupKey ?? []).equals(Buffer.from(options.custodyKey))) fail('backup_key_not_independent');
 if (!(options.backupKey instanceof Uint8Array) || options.backupKey.length !== 32) fail('backup_key_required');
 if (Buffer.from(options.backupKey).equals(Buffer.from(initial.cursorSecret,'base64url'))) fail('backup_key_not_independent');
 let floor = initial.floor;
 if (initial.version === 4) {
  proof(options,'before_initial_backup_verification');
  const verified=verifyInitialRuntimeBackup({ ...options.initialBackup,key:options.backupKey,databasePath:options.databasePath,nodeId:initial.nodeId });
  if(verified?.then || verified.sourceSchema!==4 || verified.nodeId!==initial.nodeId || verified.databasePath!==options.databasePath || verified.databaseSha256!==initial.databaseSha256 || verified.artifactSha256!==options.initialBackup.artifactSha256)fail('initial_backup_binding_mismatch');
  proof(options,'after_initial_backup_verification');
  inspect(options,(_db,info) => receiptMatches(receipt,info));
  strictClosedPath(options.databasePath);
  const db = new DatabaseSync(options.databasePath);
  try {
   migrateActivitySchema(db,{databaseBindingDigest:sha256(`activity-live-path:${path.normalize(realpathSync.native(options.databasePath))}`),
    testOnlyMigrationHook:phase => { proof(options,`activity_${phase}`); if (phase === 'before_commit' && legacyDigest(db) !== initial.legacyDigest) fail('legacy_content_changed'); }});
  } finally { db.close(); }
  // This floor is genesis of a previously nonexistent domain, created only after
  // verified clean shutdown + independently authenticated encrypted backup. It
  // does not authorize an existing schema5/6 history to vouch for itself.
  saveCustody(options,receipt,'verified_schema4_genesis');
  floor = inspect(options,(db,info) => activityRecoveryManifestForDatabase(db,info));
 }
 proof(options,'before_domain_transition');
 const result = (rollback ? rollbackEmptyDomainSchema : migrateDomainSchema)(options.databasePath,{
  activityRecoveryFloor:floor,backupKey:options.backupKey,backupDirectory:options.backupDirectory,
  offlineProof:({phase}) => proof(options,`domain_${phase}`),
 });
 inspect(options,(db) => { if (legacyDigest(db) !== initial.legacyDigest) fail('legacy_content_changed'); });
 const custody = saveCustody(options,receipt,rollback ? 'empty_domain_rollback' : 'offline_schema6_migration',floor);
 return {...result,...custody,canonicalPathPreserved:true,legacyDigestVerified:true,wholeDatabaseRestoreSupported:false};
}
export const migrateToSchema6 = input => withCustodyLock(input,options=>transition(options,false));
export const rollbackEmptySchema6 = input => withCustodyLock(input,options=>transition(options,true));
