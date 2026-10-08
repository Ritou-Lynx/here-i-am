import { createHmac, timingSafeEqual, randomUUID, createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync, lstatSync, realpathSync, readdirSync, openSync, closeSync, fsyncSync, renameSync, unlinkSync, copyFileSync, rmSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import { activityRecoveryManifestForDatabase, assertActivityRecoveryFloorForDatabase, assertActivityRecoveryProgressForDatabase, activitySchemaStatus, migrateActivitySchema } from '../activity_control_plane.mjs';
import { migrateDomainSchema, rollbackEmptyDomainSchema } from '../domain_migrate.mjs';
import { assertDomainSchemaReady, DOMAIN_SCHEMA_SQL } from '../domain_schema.mjs';
import { canonicalJSON } from '../domain_store.mjs';
import { publicLifecycleErrorCode, validatePrevious, closedStateSnapshot, MARKER } from './lifecycle/common.mjs';
import { readSwitchPlan, verifySwitchConfigurations, packageBusinessWitness, SWITCH_PENDING } from './package_switch.mjs';
import { plainPath, sha256, fail } from './package.mjs';
import { assertOfflineLease, withOfflineCustodyLock } from './lifecycle/offline_lease.mjs';
import { verifyInitialRuntimeBackup } from './backup_bundle.mjs';
import { preserveRawState, verifyRawState, assertRawUnchanged, rawFileHash, RAW_SUFFIXES } from './raw_state_backup.mjs';
import { isInspectionDatabasePath } from '../inspection_read_only.mjs';
import { startReadonlyWitness, collectReadonlyWitness, closeReadonlyWitness } from './readonly_witness.mjs';

// No CLI, boolean proof, injectable verifier, ENV switch, or synthetic lease export.
// Only the fixed supervisor module can recognize a live offline capability.
const HEX = /^[a-f0-9]{64}$/;
const encode = value => JSON.stringify(value, (_, v) => typeof v === 'bigint' ? { integer: String(v) } : v instanceof Uint8Array ? { bytes: Buffer.from(v).toString('base64') } : v);
// SQLite rows are flat primitives. This preserves the v1 byte encoding while
// avoiding a recursive JSON replacer for every field of every historical row.
function encodeRecoveryRow(row){
 const normalized=Object.create(null);
 for(const key of Object.keys(row)){
  const value=row[key];
  normalized[key]=typeof value==='bigint'?{integer:String(value)}:value instanceof Uint8Array?{bytes:Buffer.from(value).toString('base64')}:value;
 }
 return JSON.stringify(normalized);
}
// Persisted DomainStore JSON is already canonical. Validate that fact rather
// than allocating and sorting another complete nested copy on each MAC. The
// original canonicalJSON remains the exact fallback for any other key order.
function canonicalRecoveryJSON(value){
 const ordered=v=>{
  if(Array.isArray(v))return v.every(ordered);
  if(v&&typeof v==='object'&&Object.getPrototypeOf(v)===Object.prototype){
   const keys=Object.keys(v);
   return keys.every((k,i)=>!i||keys[i-1]<=k)&&keys.every(k=>ordered(v[k]));
  }
  return true;
 };
 return ordered(value)?JSON.stringify(value):canonicalJSON(value);
}
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
 if(options.recovering===true) return evidence;
 if (!receipt || typeof receipt.receiptId !== 'string' || !receipt.receiptId || receipt.databasePath !== options.databasePath
   || typeof receipt.nodeId !== 'string' || !HEX.test(receipt.databaseSha256 ?? '')) fail('clean_close_receipt_required');
 return evidence;
}
function configured(input) {
 const options = { ...input };
 if(isInspectionDatabasePath(options.databasePath))fail('inspection_activation_unsupported');
 plainPath(options.databasePath);
 plainPath(options.custodyDirectory, { missing: true });
 separated(path.dirname(options.databasePath), options.custodyDirectory);
 if (options.backupDirectory) { plainPath(options.backupDirectory, { missing: true }); separated(options.backupDirectory, options.custodyDirectory); separated(options.backupDirectory,path.dirname(options.databasePath)); }
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
 return withOfflineCustodyLock(options.supervisorLease,{databasePath:options.databasePath,custodyDirectory:options.custodyDirectory},()=>work(options));
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
 const pending=path.join(options.custodyDirectory,'current-head-'+randomUUID()+'.pending');writeFileSync(pending,raw,{flag:'wx',mode:0o600,flush:true});
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
function inspect(options, callback, plan=null) {
 const physical=options.inspectionPath??options.databasePath;
 strictClosedPath(physical);
 const before = plan?.closedHash??rawFileHash(physical);
 let readers,value,complete=false;
 const db = new DatabaseSync(`${pathToFileURL(physical).href}?mode=ro&immutable=1`, { readOnly: true });
 try {
  // A bounded per-inspection cache accelerates full SQLite b-tree/index
  // verification. It is transient memory, not a saved proof or partial audit.
  db.exec('PRAGMA cache_size=-65536');
  if(plan?.witness&&Number(meta(db,'schema_version'))===6){
   const rows=['change_events','chat_messages','domain_records'].reduce((n,t)=>n+Number(db.prepare('SELECT COALESCE(MAX(rowid),0) AS n FROM '+quote(t)).get().n),0);
   if(rows>=100000)readers=startReadonlyWitness(physical,plan.priorWitness??null,plan.activity??{canonicalDatabasePath:options.databasePath,priorActivityFloor:null,floorMode:'none'});
  }
  if (db.prepare('PRAGMA integrity_check').all().some(row => Object.values(row)[0] !== 'ok')
    // The activity worker performs the same full-database foreign-key check
    // inside activitySchemaStatus(deepAudit=true). Never omit it without that
    // actual private worker; every unsuccessful schema status is rejected.
    || (!readers&&db.prepare('PRAGMA foreign_key_check').all().length)) fail('database_integrity_failed');
  const version = Number(meta(db,'schema_version')), nodeId = meta(db,'node_id'), cursorSecret = meta(db,'cursor_secret');
  if (![4,5,6].includes(version) || !/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(nodeId ?? '') || !/^[A-Za-z0-9_-]{43}$/.test(cursorSecret ?? '')) fail('core_identity_invalid');
  if (meta(db,'domain_backup_role')) fail('backup_activation_unsupported');
  if (Buffer.from(options.custodyKey).equals(Buffer.from(cursorSecret,'base64url'))) fail('custody_key_not_independent');
  const parts=readers?collectReadonlyWitness(readers):null;
  if (version === 4) {
   if (db.prepare("SELECT 1 FROM sqlite_master WHERE name LIKE 'activity_%' OR name LIKE 'domain_%' LIMIT 1").get()
      || db.prepare("SELECT 1 FROM core_metadata WHERE key LIKE 'activity_%' OR key LIKE 'domain_%' LIMIT 1").get()) fail('schema4_genesis_not_empty');
  } else {
   const role = db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get()?.value;
   if (role !== 'live') fail('backup_activation_unsupported');
   const bindingDigest=sha256('activity-live-path:'+path.normalize(realpathSync.native(options.databasePath)));
   if(parts?.activity){
    if(parts.activity.schemaVersion!==6||parts.activity.nodeId!==nodeId||parts.activity.bindingDigest!==bindingDigest
      ||parts.activity.floorMode!==(plan?.activity?.floorMode??'none'))fail('invalid_internal_arguments');
   }else{
    const status=activitySchemaStatus(db,{expectedDatabaseBindingDigest:bindingDigest});
    if(!status.ready)fail(status.reason==='foreign_key_invariant_failed'?'database_integrity_failed':status.reason==='database_binding_invariant_failed'?'activity_database_binding_mismatch':'activity_schema_not_ready');
   }
   const claim = db.prepare('SELECT runtime_id,lease_expires_at_ms FROM activity_runtime_claim WHERE singleton=1').get();
   if (!claim || claim.runtime_id !== '' || claim.lease_expires_at_ms !== 0) fail('active_runtime_claim');
   if (version === 6) assertDomainSchemaReady(db);
  }
  value=callback(db, { version, nodeId, cursorSecret, databaseSha256: before },parts);complete=true;return value;
 } finally {
  closeReadonlyWitness(readers);db.close();
  // This private floor-only finalizer runs after all SQLite readers closed.
  // The last complete SHA then covers inspection and floor persistence before
  // head commit, replacing two scans around writes to the independent floor.
  if(complete)plan?.afterClosed?.(value);
  if (rawFileHash(physical) !== before) fail('database_changed_during_inspection'); strictClosedPath(physical);
 }
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
// Fixed-size witnesses retain exact immutable prefix boundaries. Each pass
// computes the current digest and checks the previously sealed cut together.
function prefix(db,table,cut=null,prior=null,visit=null){
 const boundary=cut??Number(db.prepare('SELECT COALESCE(MAX(rowid),0) AS n FROM '+quote(table)).get().n);
 if(!Number.isSafeInteger(boundary)||boundary<0)fail('progress_sequence_invalid');
 if(prior&&(!Number.isSafeInteger(prior.cut)||prior.cut<0||prior.cut>boundary))fail('recovery_history_diverged');
 const statement=db.prepare('SELECT rowid AS _rowid_,* FROM '+quote(table)+' WHERE rowid<=? ORDER BY rowid');statement.setReadBigInts(true);
 const digest=createHash('sha256'),old=prior?createHash('sha256'):null;let count=0,oldCount=0;
 for(const row of statement.iterate(boundary)){
  const encoded=encodeRecoveryRow(row)+'\n';digest.update(encoded);count++;
  if(prior&&row._rowid_<=BigInt(prior.cut)){old.update(encoded);oldCount++;}
  visit?.(row);
 }
 if(prior&&(oldCount!==prior.count||old.digest('hex')!==prior.sha256))fail('recovery_history_diverged');
 return {table,cut:boundary,count,sha256:digest.digest('hex')};
}
const recordKey=r=>JSON.stringify([r.namespace,r.domain,r.id]);
function recordSummary(records){
 const digest=createHash('sha256');let maxRevision=0;
 // Sort identities rather than bodies. JSON identity encoding is identical for
 // reconstructed commitments and current rows, including non-ASCII IDs.
 for(const key of [...records.keys()].sort()){
  const r=records.get(key);maxRevision=Math.max(maxRevision,r.revision);
  digest.update(encode([key,r.revision,r.rowAuth??null])).update('\n');
 }
 return {format:'i-core-domain-record-witness-v2',count:records.size,maxRevision,sha256:digest.digest('hex')};
}
function domainRecordWitness(db,domainMac,legacy=false){
 const records=new Map(),nodeId=meta(db,'node_id');
 if(!db.prepare("SELECT 1 FROM sqlite_master WHERE name='domain_records'").get())return records;
 const statement=db.prepare('SELECT * FROM domain_records');
 for(const r of statement.iterate()){
  if(!Number.isSafeInteger(r.revision)||r.revision<1)fail('domain_record_revision_invalid');
  let envelope;try{envelope=JSON.parse(r.envelope_json);}catch{fail('domain_record_envelope_invalid');}
  if(envelope.id!==r.id||envelope.domain!==r.domain||envelope.revision!==r.revision||envelope.core_instance_id!==nodeId||!['present','recoverable','purged'].includes(envelope.body_state)
    ||(envelope.body_state==='present'&&envelope.deleted_at!==null)||(envelope.body_state!=='present'&&!envelope.deleted_at)||(envelope.body_state==='purged'&&r.body_json!==null))fail('domain_record_envelope_invalid');
  records.set(recordKey(r),{revision:r.revision,rowAuth:domainMac({body_json:r.body_json,domain:r.domain,envelope_json:r.envelope_json,format:'domain-record-result-v1',id:r.id,namespace:r.namespace,revision:r.revision}),...(legacy?{rowSha256:sha256(encode(r))}:{})});
 }
 return records;
}
function domainAcceptedTargets(db,cut=null,oldPrefixes=new Map()){
 const targets=new Map(),secret=meta(db,'cursor_secret'),nodeId=meta(db,'node_id');
 const domainMac=value=>createHmac('sha256',secret).update(canonicalRecoveryJSON(value)).digest('hex');
 let priorTargets=null;
 if(!db.prepare("SELECT 1 FROM sqlite_master WHERE name='domain_records'").get())return {targets,priorTargets:new Map(),domainMac,prefixes:[]};
 const receipts=new Map();
 const receiptPrefix=prefix(db,'domain_receipts',null,oldPrefixes.get('domain_receipts'),row=>{
  let parsed;try{parsed=JSON.parse(row.receipt_json);}catch{fail('domain_receipt_authentication_failed');}
  const {receipt_auth,...receipt}=parsed;
  if(receipt_auth!==domainMac(receipt)||receipt.receipt_id!==row.receipt_id||receipt.domain!==row.domain||receipt.core_instance_id!==nodeId)fail('domain_receipt_authentication_failed');
  receipts.set(JSON.stringify([row.namespace,row.domain,receipt.principal_id,receipt.accepted_op_id]),receipt);
 });
 const operationPrefix=prefix(db,'domain_ops',null,oldPrefixes.get('domain_ops'),row=>{
  if(cut!==null&&priorTargets===null&&row._rowid_>cut)priorTargets=new Map(targets);
  let parsed,result;try{parsed=JSON.parse(row.op_meta_json);result=JSON.parse(row.result_json);}catch{fail('domain_operation_authentication_failed');}
  const {recovery_auth,...metadata}=parsed;
  const authenticated=typeof recovery_auth==='string'&&recovery_auth===domainMac({domain:row.domain,format:'domain-operation-recovery-v1',metadata,namespace:row.namespace,op_id:row.op_id,principal_id:row.principal_id,request_digest:row.request_digest,result});
  if(recovery_auth&&!authenticated)fail('domain_operation_authentication_failed');
  const receipt=receipts.get(JSON.stringify([row.namespace,row.domain,row.principal_id,row.op_id]));
  const accepted=row.namespace==='production'?!!receipt:metadata.outcome==='shadow_staged'||metadata.kind==='retention_purge'&&metadata.outcome==='accepted';
  if(!accepted)return;
  const items=receipt?.targets??metadata.targets??[];
  if(authenticated&&canonicalJSON(items)!==canonicalJSON(metadata.targets))fail('domain_accepted_target_invalid');
  for(const item of items){
   if(typeof item.id!=='string'||!Number.isSafeInteger(item.revision)||item.revision<1)fail('domain_accepted_target_invalid');
   const commitment=metadata.recovery_rows?.find(r=>r.id===item.id&&r.revision===item.revision),key=recordKey({...row,id:item.id});
   const next={revision:item.revision,authenticated,rowAuth:commitment?.row_auth},old=targets.get(key);
   if(old&&old.revision===next.revision&&old.authenticated&&next.authenticated&&old.rowAuth!==next.rowAuth)fail('domain_record_materialization_mismatch');
   if(!old||old.revision<next.revision)targets.set(key,next);
  }
 });
 if(cut!==null&&priorTargets===null)priorTargets=new Map(targets);
 return {targets,priorTargets,domainMac,prefixes:[operationPrefix,receiptPrefix]};
}
function assertDomainRecords(prior,current,accepted){
 const legacy=Array.isArray(prior),before=legacy?new Map(prior.map(r=>[recordKey(r),r])):accepted.priorTargets;
 if(prior&&!legacy){
  if(prior.format!=='i-core-domain-record-witness-v2'||JSON.stringify(recordSummary(before??new Map()))!==JSON.stringify(prior))fail('domain_record_rollback_rejected');
 }
 if(legacy)for(const [key,old] of before){
  const next=current.get(key);if(!next||next.revision<old.revision||(next.revision===old.revision&&next.rowSha256!==old.rowSha256))fail('domain_record_rollback_rejected');
 }
 for(const [key,next] of current){
  const old=before?.get(key),target=accepted.targets.get(key);
  if(!target||!target.authenticated||!HEX.test(target.rowAuth??'')){
   if(legacy&&old&&old.revision===next.revision&&old.rowSha256===next.rowSha256)fail('old_domain_witness_unverifiable');
   fail('domain_record_advance_unproven');
  }
  if(target.revision!==next.revision)fail(next.revision<target.revision?'domain_record_rollback_rejected':'domain_record_materialization_mismatch');
  if(target.rowAuth!==next.rowAuth)fail(old?.revision===next.revision?'domain_record_rollback_rejected':'domain_record_result_mismatch');
 }
 for(const [key] of accepted.targets)if(!current.has(key))fail('domain_record_materialization_mismatch');
}
// Pure read-only components used by the fixed worker entry. An already
// authenticated activity manifest is data; no custody key, lease or authority
// is accepted or returned here.
export function readRecoveryWitnessComponent(db,component,priorWitness=null,context=null){
 if(component==='activity'){
  if(!context||Object.getPrototypeOf(context)!==Object.prototype
    ||Object.keys(context).sort().join(',')!=='canonicalDatabasePath,floorMode,priorActivityFloor'
    ||!['none','progress','exact'].includes(context.floorMode)
    ||(context.floorMode==='none'?context.priorActivityFloor!==null:!context.priorActivityFloor||Object.getPrototypeOf(context.priorActivityFloor)!==Object.prototype))fail('invalid_internal_arguments');
  const canonical=plainPath(context.canonicalDatabasePath),bindingDigest=sha256('activity-live-path:'+path.normalize(realpathSync.native(canonical)));
  const info={version:Number(meta(db,'schema_version')),nodeId:meta(db,'node_id'),cursorSecret:meta(db,'cursor_secret')};
  if(info.version!==6)fail('schema6_required');
  if(db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get()?.value!=='live')fail('backup_activation_unsupported');
  const status=activitySchemaStatus(db,{expectedDatabaseBindingDigest:bindingDigest});
  if(!status.ready)fail(status.reason==='foreign_key_invariant_failed'?'database_integrity_failed':status.reason==='database_binding_invariant_failed'?'activity_database_binding_mismatch':'activity_schema_not_ready');
  const claim=db.prepare('SELECT runtime_id,lease_expires_at_ms FROM activity_runtime_claim WHERE singleton=1').get();
  if(!claim||claim.runtime_id!==''||claim.lease_expires_at_ms!==0)fail('active_runtime_claim');
  let activityFloor;
  if(context.floorMode==='progress')activityFloor=assertActivityRecoveryProgressForDatabase(db,context.priorActivityFloor,info).manifest;
  else{
   if(context.floorMode==='exact')assertActivityRecoveryFloorForDatabase(db,context.priorActivityFloor,info);
   activityFloor=activityRecoveryManifestForDatabase(db,info);
  }
  return {schemaVersion:6,nodeId:info.nodeId,bindingDigest,floorMode:context.floorMode,activityFloor};
 }
 if(context!==null)fail('invalid_internal_arguments');
 const oldPrefixes=new Map((priorWitness?.prefixes??[]).map(p=>[p.table,p]));
 if(component==='change_events'||component==='chat_messages')return prefix(db,component,null,oldPrefixes.get(component));
 if(component!=='domain')fail('invalid_internal_arguments');
 const accepted=domainAcceptedTargets(db,priorWitness?oldPrefixes.get('domain_ops')?.cut??0:null,oldPrefixes);
 const records=domainRecordWitness(db,accepted.domainMac,Array.isArray(priorWitness?.domainRecords));
 assertDomainRecords(priorWitness?.domainRecords,records,accepted);
 return {prefixes:accepted.prefixes,domainRecords:recordSummary(records)};
}
function captureProgressWitness(db,prior=null,parts=null){
 const has=name=>!!db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?").get(name);
 const tables=['change_events','chat_messages','domain_ops','domain_receipts','domain_schema_migrations','activity_schema_migrations','activity_changes'].filter(has);
 const oldPrefixes=new Map((prior?.prefixes??[]).map(p=>[p.table,p]));
 for(const table of oldPrefixes.keys())if(!tables.includes(table))fail('recovery_history_diverged');
 const otherPrefixes=new Map(tables.filter(t=>!['domain_ops','domain_receipts'].includes(t)).map(t=>[t,parts?.[t]??prefix(db,t,null,oldPrefixes.get(t))]));
 const domain=parts?.domain??readRecoveryWitnessComponent(db,'domain',prior);
 for(const value of domain.prefixes)otherPrefixes.set(value.table,value);
 const prefixes=tables.map(t=>otherPrefixes.get(t));
 return {format:'i-core-progress-witness-v2',
  identity:sha256(encode(db.prepare("SELECT key,value FROM core_metadata WHERE key IN ('node_id','cursor_secret') ORDER BY key").all())),prefixes,
  sequences:has('sqlite_sequence')?db.prepare('SELECT name,seq FROM sqlite_sequence ORDER BY name').all():[],
  devices:db.prepare('SELECT device_id,paired_at_ms,last_ack_sequence FROM devices ORDER BY device_id').all(),
  domainPrincipals:has('domain_principals')?db.prepare('SELECT principal_id,generation,status FROM domain_principals ORDER BY principal_id').all():[],domainRecords:domain.domainRecords,
  domainProgress:has('domain_registry')?db.prepare('SELECT domain,schema_json FROM domain_registry ORDER BY domain').all().map(r=>{
   const runtime=JSON.parse(r.schema_json).runtime??{};
   return {domain:r.domain,watermarks:runtime.watermarks??{},highwaters:runtime.highwaters??{}};
  }):[]};
}
function assertProgressWitness(db,witness,parts=null){
 if(!['i-core-progress-witness-v1','i-core-progress-witness-v2'].includes(witness?.format)||!Array.isArray(witness.prefixes))fail('progress_witness_required');
 const current=captureProgressWitness(db,witness,parts);
 if(current.identity!==witness.identity)fail('core_identity_rollback_rejected');
 const sequences=new Map(current.sequences.map(r=>[r.name,r.seq]));
 for(const old of witness.sequences)if(!sequences.has(old.name)||sequences.get(old.name)<old.seq)fail('core_sequence_rollback_rejected');
 const devices=new Map(current.devices.map(r=>[r.device_id,r]));
 for(const old of witness.devices){const next=devices.get(old.device_id);if(!next||next.paired_at_ms!==old.paired_at_ms||next.last_ack_sequence<old.last_ack_sequence)fail('core_device_rollback_rejected');}
 const principals=new Map(current.domainPrincipals.map(r=>[r.principal_id,r]));
 for(const old of witness.domainPrincipals){const next=principals.get(old.principal_id);if(!next||next.generation<old.generation||(old.status==='revoked'&&next.status!=='revoked'&&next.generation===old.generation))fail('domain_principal_rollback_rejected');}
 const domainProgress=new Map(current.domainProgress.map(r=>[r.domain,r]));
 for(const old of witness.domainProgress??[]){const next=domainProgress.get(old.domain);if(!next)fail('domain_progress_rollback_rejected');
  for(const key of ['watermarks','highwaters'])for(const [ns,value] of Object.entries(old[key]))if(!Number.isSafeInteger(value)||!Number.isSafeInteger(next[key][ns]??0)||(next[key][ns]??0)<value)fail('domain_progress_rollback_rejected');
 }
 return current;
}
function floorAtHead(options,head){
 const raw=readFileSync(plainPath(path.join(options.custodyDirectory,head.custodySha256+'.floor.json')));
 if(raw.length>4*1024*1024||sha256(raw)!==head.custodySha256)fail('custody_digest_mismatch');
 const body=authenticated(raw,options.custodyKey,'i-core-floor-custody-v1');
 if(body.databasePath!==options.databasePath||body.nodeId!==head.nodeId||body.cleanCloseReceiptId!==head.receiptId)fail('custody_identity_mismatch');
 return body;
}
function assertProgress(db,body,info,parts=null){
 if(body.schemaVersion!==info.version||body.nodeId!==info.nodeId)fail('custody_identity_mismatch');
 if(body.progressWitness){const witness=assertProgressWitness(db,body.progressWitness,parts),activityFloor=parts?.activity?.floorMode==='progress'?parts.activity.activityFloor:assertActivityRecoveryProgressForDatabase(db,body.activityRecoveryFloor,info).manifest;return {witness,activityFloor};}
 else {
  // An old activity-only floor cannot prove that Core history advanced rather
  // than rolled back while the dormant activity tables stayed identical.
  if(info.databaseSha256!==body.databaseSha256)fail('old_custody_progress_unverifiable');
  assertActivityRecoveryFloorForDatabase(db,body.activityRecoveryFloor,info);
 }
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
function saveCustody(options, receipt, origin, expectedFloor = null, closedPrior = undefined) {
 proof(options, 'before_custody_capture');
 const previous = readHead(options,{allowMissing:origin==='verified_schema4_genesis'||origin==='empty_provision'});
 if (!previous && !['verified_schema4_genesis','empty_provision'].includes(origin)) fail('independent_custody_head_required');
 const priorBody=closedPrior?floorAtHead(options,closedPrior):null;
 let custodySha256,custodyPath;
 const persist=body=>{
  proof(options, 'before_custody_write');
  mkdirSync(options.custodyDirectory,{recursive:true,mode:0o700}); plainPath(options.custodyDirectory);
  const raw = Buffer.from(JSON.stringify({...body,authentication:mac(body,options.custodyKey)})+'\n');
  if(raw.length>4*1024*1024)fail('custody_too_large');
  custodySha256=sha256(raw);custodyPath=path.join(options.custodyDirectory,custodySha256+'.floor.json');
  if (existsSync(custodyPath)) { if (!readFileSync(plainPath(custodyPath)).equals(raw)) fail('custody_collision'); }
  else writeFileSync(custodyPath,raw,{flag:'wx',mode:0o600,flush:true});
  proof(options, 'after_custody_write');
  if (!readFileSync(plainPath(custodyPath)).equals(raw)) fail('custody_write_unverified');
  strictClosedPath(options.databasePath);
 };
 const body = inspect(options, (db, info, parts) => {
  if (info.version === 4) fail('activity_floor_not_created');
  if (expectedFloor&&parts?.activity?.floorMode!=='exact') assertActivityRecoveryFloorForDatabase(db, expectedFloor, info);
  let progress;
  if(closedPrior!==undefined){receiptMatches(receipt,info);if(closedPrior){headMatches(closedPrior,receipt,info,{newClose:true});progress=assertProgress(db,priorBody,info,parts);}else emptyGenesis(db);}
  return { format:'i-core-floor-custody-v1', databasePath:options.databasePath, nodeId:info.nodeId,
   schemaVersion:info.version, databaseSha256:info.databaseSha256, cleanCloseReceiptId:receipt.receiptId,
   origin, activityRecoveryFloor:progress?.activityFloor??parts?.activity?.activityFloor??activityRecoveryManifestForDatabase(db, info),progressWitness:progress?.witness??captureProgressWitness(db,null,parts) };
 },{witness:true,priorWitness:priorBody?.progressWitness??null,afterClosed:persist,activity:{canonicalDatabasePath:options.databasePath,priorActivityFloor:priorBody?.progressWitness?priorBody.activityRecoveryFloor:expectedFloor,floorMode:priorBody?.progressWitness?'progress':expectedFloor?'exact':'none'},...(closedPrior!==undefined?{closedHash:receipt.databaseSha256}:{})});
 const head = writeHead(options,{custodySha256,receiptId:receipt.receiptId,nodeId:body.nodeId},previous);
 return { custodyPath,custodySha256,databaseSha256:body.databaseSha256,nodeId:body.nodeId,schemaVersion:body.schemaVersion,...head };
}
// This is ONLY called by the supervisor after an actual clean close. The resulting
// hash must be pinned in its independent durable lifecycle receipt before restart.
export function sealClosedRecovery(input) {
 return withCustodyLock(input,options=>{
  const evidence=proof(options,'seal_clean_close'),receipt=evidence.cleanCloseReceipt;
  const prior=readHead(options,{allowMissing:evidence.origin==='empty_provision'});
  return saveCustody(options,receipt,prior?'supervisor_clean_close':'empty_provision',null,prior);
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

export const RECOVERY_PENDING='s6-recovery-pending.json';
// Copy-only preparation under the native offline lease. No SQLite handle ever
// touches the original until all raw bytes have been encrypted and verified.
// The one durable pending receipt is an interruption latch, not a resumable
// stage machine. Its presence stops the next login for owner review.
export function recoverCanonicalState(input){
 if(isInspectionDatabasePath(input.databasePath))fail('inspection_activation_unsupported');
 return withCustodyLock({...input,recovering:true},options=>{
  const pending=path.join(path.dirname(options.databasePath),RECOVERY_PENDING);
  plainPath(pending,{missing:true});if(existsSync(pending))fail('recovery_interrupted_review_required');
  if(!/^[a-f0-9]{64}$/.test(options.configurationHash??'')||!/^[a-f0-9]{64}$/.test(options.manifestSha256??''))fail('recovery_configuration_binding_required');
  if(Buffer.from(options.backupKey??[]).equals(Buffer.from(options.custodyKey)))fail('backup_key_not_independent');
  const recoveryId=randomUUID(),stageDirectory=path.join(path.dirname(options.databasePath),'s6-copy-'+recoveryId),stage=path.join(stageDirectory,'i-core.sqlite');
  const previous=readHead(options,{allowMissing:options.legacy===true});
  if(options.legacy?previous!==null:previous?.custodySha256!==options.previousCustodySha256)fail('custody_head_rollback_rejected');
  const latch={format:'i-core-recovery-pending-v1',recoveryId,databasePath:options.databasePath,kind:options.legacy?'schema4_copy_adoption':'automatic_crash_recovery',
   previousHeadSha256:previous?.headSha256??null,configurationHash:options.configurationHash,manifestSha256:options.manifestSha256,commitStarted:false,startedAtMs:Date.now()};
  writeFileSync(pending,JSON.stringify(latch)+'\n',{flag:'wx',mode:0o600,flush:true});
  const updateLatch=()=>{const temporary=pending+'.tmp';plainPath(temporary,{missing:true});writeFileSync(temporary,JSON.stringify(latch)+'\n',{flag:'wx',mode:0o600,flush:true});renameSync(temporary,pending);};
  let committed=false;
  try{
   const archive=preserveRawState(options),raw=verifyRawState({...options,...archive});
   mkdirSync(stageDirectory,{mode:0o700});plainPath(stageDirectory);
   for(const file of raw.files){if(!file.present)continue;copyFileSync(plainPath(options.databasePath+file.suffix),stage+file.suffix,1);if(rawFileHash(stage+file.suffix)!==file.sha256)fail('raw_copy_mismatch');}
   assertRawUnchanged(options,raw);proof(options,'copy_before_open');
   const db=new DatabaseSync(stage);let transaction=false,info,legacyBefore;
   try{
    if(db.prepare('PRAGMA integrity_check').all().some(row=>Object.values(row)[0]!=='ok')||db.prepare('PRAGMA foreign_key_check').all().length)fail('database_integrity_failed');
    info={version:Number(meta(db,'schema_version')),nodeId:meta(db,'node_id'),cursorSecret:meta(db,'cursor_secret')};
    if(![4,5,6].includes(info.version)||info.nodeId!==options.expectedNodeId||!HEX.test(sha256(info.cursorSecret??''))||!/^[A-Za-z0-9_-]{43}$/.test(info.cursorSecret??''))fail('core_identity_invalid');
    if(meta(db,'domain_backup_role'))fail('backup_activation_unsupported');
    if(Buffer.from(options.backupKey).equals(Buffer.from(info.cursorSecret,'base64url'))||Buffer.from(options.custodyKey).equals(Buffer.from(info.cursorSecret,'base64url')))fail('backup_key_not_independent');
    if(options.legacy){
     if(info.version!==4||db.prepare("SELECT 1 FROM sqlite_master WHERE name LIKE 'activity_%' OR name LIKE 'domain_%' LIMIT 1").get()||db.prepare("SELECT 1 FROM core_metadata WHERE key LIKE 'activity_%' OR key LIKE 'domain_%' LIMIT 1").get())fail('legacy_schema4_required');
    }else{
     if(info.version!==6)fail('interrupted_migration_review_required');
     if(db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get()?.value!=='live')fail('backup_activation_unsupported');
     if(!activitySchemaStatus(db,{expectedDatabaseBindingDigest:sha256(`activity-live-path:${path.normalize(realpathSync.native(options.databasePath))}`)}).ready)fail('activity_database_binding_mismatch');
     assertDomainSchemaReady(db);
     // This checkpoint is solely on the preserved disposable copy. It makes
     // the exact-byte compatibility test meaningful for old custody formats.
     db.exec('PRAGMA wal_checkpoint(TRUNCATE)');info.databaseSha256=rawFileHash(stage);
     assertProgress(db,floorAtHead(options,previous),info);
    }
    legacyBefore=options.legacy?legacyDigest(db):null;
    if(options.legacy){
     proof(options,'copy_before_activity_migration');
     migrateActivitySchema(db,{databaseBindingDigest:sha256(`activity-live-path:${path.normalize(realpathSync.native(options.databasePath))}`),testOnlyMigrationHook:phase=>proof(options,'copy_activity_'+phase)});
     db.exec('BEGIN IMMEDIATE');transaction=true;
     db.exec(DOMAIN_SCHEMA_SQL);
     db.prepare('INSERT INTO domain_schema_migrations VALUES (?,?,?,?)').run(randomUUID(),5,6,JSON.stringify({kind:'offline_domain_schema_migration',backup_id:raw.id.slice(4),at:new Date().toISOString()}));
     db.prepare("UPDATE core_metadata SET value='6' WHERE key='schema_version'").run();
     assertDomainSchemaReady(db);
     if(legacyDigest(db)!==legacyBefore)fail('legacy_content_changed');
     proof(options,'copy_migration_before_commit');db.exec('COMMIT');transaction=false;
    }
    // The native lease proved the old process tree is gone. Preserve the fence
    // and release only its dead claim on this disposable verified copy.
    db.prepare("UPDATE activity_runtime_claim SET runtime_id='',lease_expires_at_ms=0 WHERE singleton=1").run();
    if(db.prepare('PRAGMA integrity_check').all().some(row=>Object.values(row)[0]!=='ok'))fail('database_integrity_failed');
    db.exec('PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE');
   }finally{if(transaction)db.exec('ROLLBACK');db.close();}
   const receiptId=options.receiptId??recoveryId;
   const event={format:'i-core-recovery-event-v1',recoveryId,receiptId,kind:options.legacy?'schema4_copy_adoption':'automatic_crash_recovery',recoveredAtMs:Date.now(),
    databasePath:options.databasePath,nodeId:info.nodeId,previousHeadSha256:previous?.headSha256??null,rawManifestSha256:archive.manifestSha256,
    configurationHash:options.configurationHash,manifestSha256:options.manifestSha256};
   const eventRaw=Buffer.from(JSON.stringify({...event,authentication:mac(event,options.custodyKey)})+'\n');
   const eventSha256=sha256(eventRaw);
   const body=inspect({...options,inspectionPath:stage},(verifiedDb,verified,parts)=>({format:'i-core-floor-custody-v1',databasePath:options.databasePath,nodeId:verified.nodeId,
    schemaVersion:6,databaseSha256:verified.databaseSha256,cleanCloseReceiptId:receiptId,origin:event.kind,recoveryEventSha256:eventSha256,
    activityRecoveryFloor:parts?.activity?.activityFloor??activityRecoveryManifestForDatabase(verifiedDb,verified),progressWitness:captureProgressWitness(verifiedDb,null,parts)}),{witness:true});
   const floorRaw=Buffer.from(JSON.stringify({...body,authentication:mac(body,options.custodyKey)})+'\n'),custodySha256=sha256(floorRaw);
   if(floorRaw.length>4*1024*1024)fail('custody_too_large');
   writeFileSync(path.join(options.custodyDirectory,eventSha256+'.recovery.json'),eventRaw,{flag:'wx',mode:0o600,flush:true});
   writeFileSync(path.join(options.custodyDirectory,custodySha256+'.floor.json'),floorRaw,{flag:'wx',mode:0o600,flush:true});
   assertRawUnchanged(options,raw);proof(options,'copy_before_replace');
   latch.commitStarted=true;updateLatch();
   // Sidecars must not be applied to the new consolidated DB. Their raw bytes
   // are already verified in the archive. Pending latch covers every gap here.
   for(const suffix of RAW_SUFFIXES.slice(1))if(existsSync(options.databasePath+suffix))renameSync(options.databasePath+suffix,path.join(stageDirectory,'original'+suffix));
   renameSync(stage,options.databasePath);committed=true;
   proof(options,'copy_after_replace');
   if(rawFileHash(options.databasePath)!==body.databaseSha256)fail('copy_replace_unverified');
   const head=writeHead(options,{custodySha256,receiptId,nodeId:info.nodeId},previous);
   proof(options,'copy_after_head_commit');
   // Delete only the exact generated private stage after successful commit.
   plainPath(stageDirectory);for(const name of readdirSync(stageDirectory))plainPath(path.join(stageDirectory,name));rmSync(stageDirectory,{recursive:true});
   unlinkSync(plainPath(pending));
   return {ok:true,schemaVersion:6,nodeId:info.nodeId,databaseSha256:body.databaseSha256,custodySha256,receiptId,...head,archiveManifestSha256:archive.manifestSha256,
    recoveryEventSha256:eventSha256,canonicalPathPreserved:true,legacyDigestVerified:true};
  }catch(error){
   // Before replacement even a failed migration leaves the original raw state
   // byte-for-byte intact. After replacement the external head/pending latch
   // prevent any blind restart or fallback to a stale floor.
   latch.failureCode=publicLifecycleErrorCode(error);latch.failedAtMs=Date.now();
   try{updateLatch();}catch{/* The original durable latch still prohibits restart. */}
   if(!committed&&!latch.commitStarted&&existsSync(stageDirectory)){plainPath(stageDirectory);for(const name of readdirSync(stageDirectory))plainPath(path.join(stageDirectory,name));rmSync(stageDirectory,{recursive:true});}
   throw error;
  }
 });
}


// Same-schema package rebinding never writes or replaces SQLite. Its durable
// sentinel makes historical releases' state-tree check fail before head commit.
export function switchClosedPackage(input) {
 return withCustodyLock({...input,recovering:true},options=>{
  const plan=readSwitchPlan(options.planPath,options.planSha256);
  const [fromSettings,toSettings]=verifySwitchConfigurations(plan);
  if(fromSettings.database_path!==options.databasePath||fromSettings.recovery_custody_directory!==options.custodyDirectory
    ||toSettings.node_id!==fromSettings.node_id)fail('switch_configuration_scope_changed');
  if(!(/^[a-f0-9]{64}$/).test(options.receiptId??''))fail('switch_receipt_required');
  const state=path.dirname(options.databasePath),markerPath=path.join(state,MARKER),sentinelPath=path.join(state,SWITCH_PENDING);
  const pendingPath=path.join(options.custodyDirectory,'package-switch-pending.json');
  const evidence=proof({...options,recovering:true},'package_switch_begin');
  let previous=readHead(options),event,eventSha256,sourceFloor;
  const loadEvent=digest=>{
   if(!HEX.test(digest??''))fail('switch_event_changed');
   const raw=readFileSync(plainPath(path.join(options.custodyDirectory,digest+'.package-switch.json')));
   if(sha256(raw)!==digest)fail('switch_event_changed');
   return authenticated(raw,options.custodyKey,'i-core-package-switch-event-v1');
  };
  const sentinelRaw=digest=>Buffer.from(JSON.stringify({format:'schema6-package-switch-pending-v1',planSha256:plan.planSha256,eventSha256:digest})+'\n');
  const immutable=(filename,raw)=>{
   plainPath(filename,{missing:true});
   if(existsSync(filename)){if(!readFileSync(filename).equals(raw))fail('switch_artifact_changed');}
   else writeFileSync(filename,raw,{flag:'wx',mode:0o600,flush:true});
  };
  const authenticatedBytes=body=>Buffer.from(JSON.stringify({...body,authentication:mac(body,options.custodyKey)})+'\n');
  if(existsSync(sentinelPath)&&!existsSync(pendingPath)){
   const orphan=JSON.parse(readFileSync(plainPath(sentinelPath)));
   const candidate=loadEvent(orphan.eventSha256);
   const markerRaw=readFileSync(plainPath(markerPath)),marker=JSON.parse(markerRaw);
   const beforeCommit=previous.headSha256===plan.expectedHeadSha256&&sha256(markerRaw)===plan.expectedMarkerSha256;
   const afterCommit=floorAtHead(options,previous).packageSwitchEventSha256===orphan.eventSha256
    &&marker.phase==='clean_closed'&&marker.package_switch_plan_sha256===plan.planSha256
    &&marker.package_switch_event_sha256===orphan.eventSha256&&marker.custody_sha256===previous.custodySha256
    &&marker.manifest_sha256===plan.to.manifestSha256&&marker.configuration_sha256===plan.to.configurationSha256;
   if(orphan.planSha256!==plan.planSha256||candidate.planSha256!==plan.planSha256||(!beforeCommit&&!afterCommit)
     ||!readFileSync(sentinelPath).equals(sentinelRaw(orphan.eventSha256)))fail('switch_orphan_sentinel');
   immutable(pendingPath,authenticatedBytes({format:'i-core-package-switch-pending-v1',planSha256:plan.planSha256,eventSha256:orphan.eventSha256}));
  }
  if(existsSync(pendingPath)){
   const pending=authenticated(readFileSync(plainPath(pendingPath)),options.custodyKey,'i-core-package-switch-pending-v1');
   if(pending.planSha256!==plan.planSha256)fail('switch_pending_other_operation');
   eventSha256=pending.eventSha256;event=loadEvent(eventSha256);
   if(event.planSha256!==plan.planSha256||event.databasePath!==options.databasePath||event.nodeId!==event.sourceMarker.node_id)fail('switch_event_changed');
   const current=floorAtHead(options,previous);
   if(previous.headSha256!==plan.expectedHeadSha256&&current.packageSwitchEventSha256!==eventSha256)fail('switch_resume_head_changed');
   sourceFloor=current;
   // A completed supervisor may have removed the sentinel before it died. Only
   // recreate it if the target marker is still exact and DB is still unchanged.
   if(!existsSync(sentinelPath)){
    const marker=JSON.parse(readFileSync(plainPath(markerPath)));
    if(marker.package_switch_plan_sha256!==plan.planSha256||marker.phase!=='clean_closed'
      ||marker.manifest_sha256!==plan.to.manifestSha256||marker.custody_sha256!==previous.custodySha256)fail('switch_resume_marker_changed');
    immutable(sentinelPath,sentinelRaw(eventSha256));
   }else if(!readFileSync(plainPath(sentinelPath)).equals(sentinelRaw(eventSha256)))fail('switch_sentinel_changed');
  }else{
   if(existsSync(sentinelPath))fail('switch_orphan_sentinel');
   if(previous.headSha256!==plan.expectedHeadSha256)fail('switch_head_changed');
   const markerRaw=readFileSync(plainPath(markerPath));
   if(sha256(markerRaw)!==plan.expectedMarkerSha256)fail('switch_marker_changed');
   const marker=JSON.parse(markerRaw);
   const before=inspect(options,(db,info)=>{
    if(info.version!==6)fail('schema6_required');
    validatePrevious(marker,{state,manifest_sha256:plan.from.manifestSha256}, {database_sha256:info.databaseSha256,nodeId:info.nodeId},plan.from.configurationSha256);
    const receipt={receiptId:marker.token,databasePath:options.databasePath,nodeId:info.nodeId,databaseSha256:info.databaseSha256,custodySha256:marker.custody_sha256};
    sourceFloor=readCustody(options,info,receipt);
    assertActivityRecoveryFloorForDatabase(db,sourceFloor.activityRecoveryFloor,info);
    return {info,witness:packageBusinessWitness(db)};
   });
   // Reconstruct committed package history from the authenticated head chain.
   // A caller cannot turn a reverse into an upgrade by omitting rollbackOf.
   const events=[],seen=new Set();let cursor=previous;
   for(let n=0;cursor&&n<100000;n++){
    const body=floorAtHead(options,cursor),digest=body.packageSwitchEventSha256;
    if(digest&&!seen.has(digest)){seen.add(digest);events.push({digest,value:loadEvent(digest)});}
    if(!cursor.previousHeadSha256){cursor=null;break;}
    const raw=readFileSync(plainPath(path.join(options.custodyDirectory,cursor.previousHeadSha256+'.head.json')));
    if(sha256(raw)!==cursor.previousHeadSha256)fail('custody_head_chain_invalid');
    const prior=authenticated(raw,options.custodyKey,'i-core-custody-head-v1');
    if(prior.generation!==cursor.generation-1||prior.databasePath!==options.databasePath||prior.nodeId!==before.info.nodeId)fail('custody_head_chain_invalid');
    cursor={...prior,headSha256:cursor.previousHeadSha256};
   }
   if(cursor)fail('switch_history_limit');
   const stack=[],known=new Set(),same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
   let base=null,active=null;
   for(const record of events.reverse()){
    const e=record.value;
    if(e.databasePath!==options.databasePath||e.nodeId!==before.info.nodeId)fail('switch_history_invalid');
    if(!base){base=e.from;active=base;}
    if(!same(active,e.from))fail('switch_history_invalid');
    known.add(e.from.manifestSha256);known.add(e.to.manifestSha256);
    if(e.rollbackOf){
     const top=stack.at(-1);
     if(!top||top.digest!==e.rollbackOf||!same(top.value.from,e.to)||!same(top.value.to,e.from))fail('switch_history_invalid');
     stack.pop();
    }else stack.push(record);
    active=e.to;
   }
   if(active&&!same(active,plan.from))fail('switch_history_binding_mismatch');
   const ancestors=stack.map(r=>r.value.from.manifestSha256);
   const returning=ancestors.includes(plan.to.manifestSha256);
   if(returning){
    const top=stack.at(-1);
    if(!plan.rollbackOf||!top||plan.rollbackOf!==top.digest||!same(top.value.from,plan.to)||!same(top.value.to,plan.from))fail('switch_reverse_proof_required');
    if(top.value.businessWitness.sha256!==before.witness.sha256)fail('switch_business_changed');
   }else{
    if(plan.rollbackOf)fail('switch_reverse_proof_required');
    // Previously undone forward edges may be applied again. Arbitrary historical
    // cross-edges/multi-hop returns remain rejected.
    if(known.has(plan.to.manifestSha256)&&!events.some(r=>!r.value.rollbackOf&&same(r.value.from,plan.from)&&same(r.value.to,plan.to)))fail('switch_reverse_proof_required');
   }
   event={format:'i-core-package-switch-event-v1',operationId:plan.operationId,planSha256:plan.planSha256,
    databasePath:options.databasePath,nodeId:before.info.nodeId,databaseSha256:before.info.databaseSha256,
    previousHeadSha256:previous.headSha256,sourceMarker:marker,from:plan.from,to:plan.to,rollbackOf:plan.rollbackOf??null,businessWitness:before.witness};
   const raw=authenticatedBytes(event);eventSha256=sha256(raw);
   immutable(path.join(options.custodyDirectory,eventSha256+'.package-switch.json'),raw);
   proof({...options,recovering:true},'package_switch_before_pending');
   // State sentinel first: an interrupted pending write still blocks both old
   // and new normal entrypoints and requires explicit reviewed repair.
   immutable(sentinelPath,sentinelRaw(eventSha256));
   immutable(pendingPath,authenticatedBytes({format:'i-core-package-switch-pending-v1',planSha256:plan.planSha256,eventSha256}));
   proof({...options,recovering:true},'package_switch_after_pending');
  }
  // No clean marker is replaced by the child. Old binaries remain blocked by
  // the sentinel until the native supervisor proves child/guardian exit.
  if(!readFileSync(plainPath(sentinelPath)).equals(sentinelRaw(eventSha256)))fail('switch_sentinel_changed');
  if(closedStateSnapshot(state,{packageSwitchPending:true}).stateTreeSha256!==event.sourceMarker.state_tree_sha256)fail('switch_state_changed');
  const currentMarkerRaw=readFileSync(plainPath(markerPath)),currentMarker=JSON.parse(currentMarkerRaw);
  if(sha256(currentMarkerRaw)!==plan.expectedMarkerSha256
    && !(currentMarker.phase==='clean_closed'&&currentMarker.package_switch_plan_sha256===plan.planSha256
      &&currentMarker.package_switch_event_sha256===eventSha256&&currentMarker.custody_sha256===previous.custodySha256
      &&currentMarker.manifest_sha256===plan.to.manifestSha256&&currentMarker.configuration_sha256===plan.to.configurationSha256))fail('switch_resume_marker_changed');
  const current=inspect(options,(db,info)=>{
   if(info.version!==6||info.nodeId!==event.nodeId||info.databaseSha256!==event.databaseSha256
      ||packageBusinessWitness(db).sha256!==event.businessWitness.sha256)fail('switch_business_changed');
   assertActivityRecoveryFloorForDatabase(db,sourceFloor.activityRecoveryFloor,info);return info;
  });
  proof({...options,recovering:true},'package_switch_before_floor');
  const body={...sourceFloor,cleanCloseReceiptId:options.receiptId,origin:plan.rollbackOf?'same_schema_package_reverse':'same_schema_package_switch',
   packageSwitchEventSha256:eventSha256,databaseSha256:current.databaseSha256};
  const raw=authenticatedBytes(body),custodySha256=sha256(raw);
  immutable(path.join(options.custodyDirectory,custodySha256+'.floor.json'),raw);
  proof({...options,recovering:true},'package_switch_before_head');
  const head=writeHead({...options,recovering:true},{custodySha256,receiptId:options.receiptId,nodeId:current.nodeId},previous);
  proof({...options,recovering:true},'package_switch_after_head');
  return {eventSha256,...head,custodySha256,databaseSha256:current.databaseSha256,
   marker:{...event.sourceMarker,token:options.receiptId,phase:'close_prepared',
    manifest_sha256:plan.to.manifestSha256,configuration_sha256:plan.to.configurationSha256,custody_sha256:custodySha256,
    package_switch_plan_sha256:plan.planSha256,package_switch_event_sha256:eventSha256}};
 });
}
