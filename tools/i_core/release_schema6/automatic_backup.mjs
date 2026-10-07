import { createHash, createHmac, randomUUID, timingSafeEqual } from 'node:crypto';
import { existsSync, mkdirSync, openSync, closeSync, writeFileSync, readFileSync, readSync, unlinkSync, rmdirSync, readdirSync, lstatSync, fsyncSync } from 'node:fs';
import { DatabaseSync, backup } from 'node:sqlite';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import { activityRecoveryManifestForDatabase } from '../activity_control_plane.mjs';
import { backupFilePrimitives as f, createRuntimeBackup } from './backup_bundle.mjs';
import { portableEnvelopeSha256, bindPortableArtifact, verifyPortableBinding } from './portable_key_custody.mjs';
const fail=c=>{throw Object.assign(new Error(c),{code:c});};
const sha=b=>createHash('sha256').update(b).digest('hex');
const json=v=>Buffer.from(JSON.stringify(v));
const DAY=86400000;
const inProcessRuns=new Set();
function writeNew(p,b){f.safe(path.dirname(p),true);const fd=openSync(p,'wx',0o600);try{writeFileSync(fd,b);fsyncSync(fd);}finally{closeSync(fd);}f.safe(p);}
function fresh(p){f.safe(path.dirname(p),true);if(existsSync(p))fail('fresh_output_required');mkdirSync(p,{mode:0o700});f.protect(p);f.safe(p,true);}
function inside(root,p){const r=path.relative(root,p);return !r||(!r.startsWith('..'+path.sep)&&r!=='..'&&!path.isAbsolute(r));}
function sqliteHeader(p){f.safe(p);const fd=openSync(p,'r'),bytes=Buffer.alloc(16);try{return readSync(fd,bytes,0,16,0)===16 && bytes.equals(Buffer.from('SQLite format 3\0'));}finally{closeSync(fd);bytes.fill(0);}}
function snapshotPaths(p){f.safe(p);for(const suffix of ['-wal','-shm','-journal'])if(existsSync(p+suffix))f.safe(p+suffix);}
// A read transaction pins a SQLite snapshot. WAL is read by SQLite, never copied
// as separate files. Only the newly created destination can be checkpointed.
export async function captureConsistentSqlite({sourcePath,destinationPath}){
 snapshotPaths(sourcePath);f.safe(path.dirname(destinationPath),true);if(existsSync(destinationPath))fail('fresh_output_required');
 const initial=lstatSync(sourcePath,{bigint:true});const startedAt=Date.now();
 const db=new DatabaseSync(`${pathToFileURL(sourcePath).href}?mode=ro`,{readOnly:true});
 try{db.exec('PRAGMA query_only=ON; PRAGMA trusted_schema=OFF; BEGIN');db.prepare('SELECT count(*) FROM sqlite_master').get();await backup(db,destinationPath);db.exec('ROLLBACK');}finally{db.close();}
 snapshotPaths(sourcePath);const after=lstatSync(sourcePath,{bigint:true});if(initial.dev!==after.dev||initial.ino!==after.ino)fail('online_source_replaced');
 f.safe(destinationPath);const copy=new DatabaseSync(destinationPath);try{copy.exec('PRAGMA journal_mode=DELETE');if(copy.prepare('PRAGMA integrity_check').get().integrity_check!=='ok')fail('online_copy_integrity');}finally{copy.close();}f.sidecars(destinationPath);
 return {startedAt,completedAt:Date.now(),sha256:f.readStable(destinationPath).sha256};
}
export async function captureOnlineRuntimeBackup({specTemplate,sqliteEntryNames=[],outputDirectory,key}){
 const spec=JSON.parse(JSON.stringify(specTemplate));f.validate(spec);f.checkRelease(spec);
 if(!Array.isArray(sqliteEntryNames)||new Set(sqliteEntryNames).size!==sqliteEntryNames.length)fail('sqlite_inventory_invalid');
 const selected=new Set(sqliteEntryNames);selected.add(spec.entries.find(e=>e.role==='database').name);
 for(const n of selected)if(!spec.entries.some(e=>e.name===n&&['database','configuration'].includes(e.role)))fail('sqlite_inventory_invalid');
 for(const e of spec.entries)if(inside(outputDirectory,e.source_path)||inside(path.dirname(e.source_path),outputDirectory))fail('independent_output_required');
 fresh(outputDirectory);const staging=path.join(outputDirectory,'capture');fresh(staging);const created=[];const window={startedAt:Date.now(),completedAt:null,crossComponentAtomic:false,activationAuthority:false,components:[]};
 try{
  const originalDatabase=spec.canonical_database_path;
  for(let i=0;i<spec.entries.length;i++){
   const e=spec.entries[i];if(e.role==='release'){if(f.readStable(e.source_path).sha256!==e.sha256)fail('release_source_changed');continue;}
   const source=e.source_path,target=path.join(staging,String(i)+(selected.has(e.name)?'.sqlite':'.bin'));created.push(target);
   let observation;
   if(selected.has(e.name))observation=await captureConsistentSqlite({sourcePath:source,destinationPath:target});
   else{if(/-(wal|shm|journal)$/.test(source)||sqliteHeader(source))fail('sqlite_source_requires_online_snapshot');const startedAt=Date.now(),before=f.readStable(source);const fd=openSync(target,'wx',0o600);try{const during=f.readStable(source,c=>writeFileSync(fd,c));if(JSON.stringify(before)!==JSON.stringify(during))fail('source_changed');fsyncSync(fd);}finally{closeSync(fd);}if(JSON.stringify(before)!==JSON.stringify(f.readStable(source)))fail('source_changed');observation={startedAt,completedAt:Date.now(),sha256:before.sha256};}
   e.source_path=target;e.sha256=f.readStable(target).sha256;window.components.push({name:e.name,sourcePath:source,...observation});if(e.role==='database')spec.canonical_database_path=target;
   if(e.custody_context)delete e.custody_context;
  }
  // Archive-only context is derived from the frozen copy. Original independent
  // custody remains separate entries, never overwritten or promoted by this API.
  const db=new DatabaseSync(`${pathToFileURL(spec.canonical_database_path).href}?mode=ro&immutable=1`,{readOnly:true});let context;
  try{const secret=db.prepare("SELECT value FROM core_metadata WHERE key='cursor_secret'").get()?.value;
   context={format:'i-core-recovery-custody-v1',mode:spec.source_schema===4?'initial_schema4':'activity_floor',node_id:spec.node_id,database_path:spec.canonical_database_path};
   if(spec.source_schema!==4)context.activity_recovery_floor=activityRecoveryManifestForDatabase(db,{nodeId:spec.node_id,cursorSecret:secret});
  }finally{db.close();}
  const custody=path.join(staging,'archive-inspection-context.json');created.push(custody);writeNew(custody,json(context));
  spec.entries.push({role:'recovery_custody',name:'archive-inspection/context.json',source_path:custody,sha256:f.readStable(custody).sha256,custody_context:true});
  window.completedAt=Date.now();window.originalDatabasePath=originalDatabase;
  const provenance=path.join(staging,'capture-window.json');created.push(provenance);writeNew(provenance,json(window));spec.entries.push({role:'configuration',name:'archive-inspection/capture-window.json',source_path:provenance,sha256:f.readStable(provenance).sha256});
  const report=createRuntimeBackup({spec,key,outputDirectory:path.join(outputDirectory,'artifact')});
  return {...report,captureWindow:{startedAt:window.startedAt,completedAt:window.completedAt,crossComponentAtomic:false},onlineSnapshot:true};
 }finally{
  for(const p of created.reverse()){for(const suffix of ['-wal','-shm','-journal','']){const target=p+suffix;if(existsSync(target)){f.safe(target);unlinkSync(target);}}}
  f.safe(staging,true);rmdirSync(staging);
 }
}
function validatePolicy(p){if(!p||Object.keys(p).some(k=>!['format','outputRoot','retentionDays','mirrorRoot','backupSetId'].includes(k))||p.format!=='i-core-automatic-backup-v1'||!/^[a-f0-9]{64}$/.test(p.backupSetId)||!Number.isInteger(p.retentionDays??30)||(p.retentionDays??30)<1||(p.retentionDays??30)>3650)fail('automatic_policy_invalid');f.safe(p.outputRoot,true);if(p.mirrorRoot){if(typeof p.mirrorRoot!=='string'||!path.isAbsolute(p.mirrorRoot)||path.normalize(p.mirrorRoot)!==p.mirrorRoot||p.mirrorRoot.includes(':',2))fail('mirror_path_invalid');if(inside(p.outputRoot,p.mirrorRoot)||inside(p.mirrorRoot,p.outputRoot))fail('mirror_not_independent');}return p;}
const managed=['artifact/runtime.aes256gcm','portable-key.json','portable-binding.json'];
function mac(key,body){return createHmac('sha256',key).update(json(body)).digest('hex');}
function readReceipt(dir,key,setId){f.safe(dir,true);const r=JSON.parse(f.small(path.join(dir,'receipt.json'),65536));const {mac:signature,...body}=r;if(body.format!=='i-core-automatic-receipt-v1'||body.backupSetId!==setId||!Number.isSafeInteger(body.completedAt)||!/^[a-f0-9]{64}$/.test(signature??'')||!timingSafeEqual(Buffer.from(signature,'hex'),Buffer.from(mac(key,body),'hex'))||JSON.stringify(Object.keys(body.files).sort())!==JSON.stringify([...managed].sort()))fail('automatic_receipt_rejected');return body;}
function checkManaged(dir,body){const rootNames=readdirSync(dir).sort();if(JSON.stringify(rootNames)!==JSON.stringify(['artifact','portable-binding.json','portable-key.json','receipt.json']))fail('automatic_unmanaged_files');f.safe(path.join(dir,'artifact'),true);if(JSON.stringify(readdirSync(path.join(dir,'artifact')))!==JSON.stringify(['runtime.aes256gcm']))fail('automatic_unmanaged_files');for(const n of managed)if(f.readStable(path.join(dir,...n.split('/'))).sha256!==body.files[n])fail('automatic_file_changed');}
function retained(root,key,setId){return readdirSync(root).filter(n=>/^daily-[0-9]{13}-[a-f0-9-]{36}$/.test(n)).flatMap(name=>{try{const dir=path.join(root,name),r=readReceipt(dir,key,setId);return [{name,dir,...r}];}catch{return [];}});}
function prune(root,key,setId,now,days){let count=0;for(const r of retained(root,key,setId)){if(r.completedAt>=now-days*DAY)continue;checkManaged(r.dir,r);for(const n of [...managed,'receipt.json']){const p=path.join(r.dir,...n.split('/'));f.safe(p);unlinkSync(p);}f.safe(path.join(r.dir,'artifact'),true);rmdirSync(path.join(r.dir,'artifact'));f.safe(r.dir,true);rmdirSync(r.dir);count++;}return count;}
function mirror(job,body,root,key,setId){
 if(!root)return {mirrored:false,mirrorPending:false};
 try{
  f.safe(root,true);
  for(const prior of retained(root,key,setId)){if(prior.files['artifact/runtime.aes256gcm']===body.files['artifact/runtime.aes256gcm']){checkManaged(prior.dir,prior);return {mirrored:true,mirrorPending:false};}}
  // Each attempt owns a fresh directory. Interrupted partial copies are never
  // mistaken for complete receipts or overwritten/deleted on a retry.
  const target=path.join(root,`daily-${String(body.completedAt).padStart(13,'0')}-${randomUUID()}`);fresh(target);fresh(path.join(target,'artifact'));
  for(const n of managed){const source=path.join(job,...n.split('/')),destination=path.join(target,...n.split('/'));const before=f.readStable(source);const out=openSync(destination,'wx',0o600);try{const during=f.readStable(source,c=>writeFileSync(out,c));if(JSON.stringify(before)!==JSON.stringify(during))fail('mirror_source_changed');fsyncSync(out);}finally{closeSync(out);}if(f.readStable(destination).sha256!==before.sha256)fail('mirror_verification_failed');}
  writeNew(path.join(target,'receipt.json'),json({...body,mac:mac(key,body)}));checkManaged(target,readReceipt(target,key,setId));return {mirrored:true,mirrorPending:false};
 }catch{return {mirrored:false,mirrorPending:true,mirrorError:'mirror_copy_unavailable_or_rejected'};}
}
export async function runDueAutomaticBackup({policy,specTemplate,sqliteEntryNames=[],key,envelope,nowMs=Date.now()}){
 validatePolicy(policy);if(!Number.isSafeInteger(nowMs)||nowMs<0)fail('automatic_clock_invalid');if(envelope.backupSetId!==policy.backupSetId||envelope.keyId!==sha(key))fail('automatic_key_rotation_requires_setup');portableEnvelopeSha256(envelope);
 // Cross-process ownership is the fixed Automatic PowerShell wrapper's OS
 // FileShare.None lock. This set only serializes direct callers in this process.
 const lock=process.platform==='win32'?policy.outputRoot.toLowerCase():policy.outputRoot;
 if(inProcessRuns.has(lock))fail('automatic_in_process_busy');inProcessRuns.add(lock);let job;
 try{
  const local=retained(policy.outputRoot,key,policy.backupSetId).sort((a,b)=>b.completedAt-a.completedAt),prior=local[0];
  if(prior?.completedAt>nowMs)fail('automatic_clock_rollback');
  let mirrorState={mirrored:false,mirrorPending:false};
  // Retry every still-retained local artifact, including a newly configured or
  // reconnected destination, without recapturing any live database.
  for(const r of local){checkManaged(r.dir,r);const result=mirror(r.dir,readReceipt(r.dir,key,policy.backupSetId),policy.mirrorRoot,key,policy.backupSetId);mirrorState={...result,mirrorPending:mirrorState.mirrorPending||result.mirrorPending};if(result.mirrorPending)break;}
  if(prior){if(prior.completedAt>nowMs)fail('automatic_clock_rollback');if(nowMs-prior.completedAt<DAY)return {verified:true,status:mirrorState.mirrorPending?'mirror_pending':'not_due',...mirrorState,nextDueAt:prior.completedAt+DAY};}
  const name=`daily-${String(nowMs).padStart(13,'0')}-${randomUUID()}`;job=path.join(policy.outputRoot,name);
  const report=await captureOnlineRuntimeBackup({specTemplate,sqliteEntryNames,outputDirectory:job,key});const binding=bindPortableArtifact({key,envelope,report});verifyPortableBinding({key,envelope,binding});
  writeNew(path.join(job,'portable-key.json'),json(envelope));writeNew(path.join(job,'portable-binding.json'),json(binding));
  const body={format:'i-core-automatic-receipt-v1',backupSetId:policy.backupSetId,completedAt:nowMs,files:Object.fromEntries(managed.map(n=>[n,f.readStable(path.join(job,...n.split('/'))).sha256]))};
  writeNew(path.join(job,'receipt.json'),json({...body,mac:mac(key,body)}));checkManaged(job,body);
  const copied=mirror(job,body,policy.mirrorRoot,key,policy.backupSetId);mirrorState={...copied,mirrorPending:mirrorState.mirrorPending||copied.mirrorPending};
  // An offline mirror never causes deletion of the only retained local copy.
  const pruned=mirrorState.mirrorPending?0:prune(policy.outputRoot,key,policy.backupSetId,nowMs,policy.retentionDays??30)+(policy.mirrorRoot?prune(policy.mirrorRoot,key,policy.backupSetId,nowMs,policy.retentionDays??30):0);
  return {verified:true,status:mirrorState.mirrorPending?'mirror_pending':'backed_up',localBackupCreated:true,artifactSha256:report.artifactSha256,files:report.files,...mirrorState,pruned,retentionDays:policy.retentionDays??30,crossComponentAtomic:false,activation_supported:false,nextDueAt:nowMs+DAY};
 }finally{inProcessRuns.delete(lock);}
}
