import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { existsSync, mkdirSync, readFileSync, readdirSync, realpathSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { ICoreStore } from '../../../i_core_store.mjs';
import { createICoreServer } from '../../../i_core_server.mjs';
import { DomainStore, DOMAIN_POLICY, canonicalJSON } from '../../../domain_store.mjs';
import { BACKUP_ROLES, backupFilePrimitives, createRuntimeBackup, verifyRuntimeBackup } from '../../../release_schema6/backup_bundle.mjs';
import { runDueAutomaticBackup } from '../../../release_schema6/automatic_backup.mjs';
import { wrapBackupKey, verifyPortableBinding } from '../../../release_schema6/portable_key_custody.mjs';
import { sha256, plainPath } from '../../../release_schema6/package.mjs';
import { syntheticRoot, syntheticFixedNode } from '../synthetic_paths.mjs';
import { syntheticLease } from './synthetic_lease.mjs';

// Only the OS lease is substituted. Every production recovery, integrity,
// raw preservation, encryption and inspection operation still executes.
function sourceModule(name,replacements={}) {
 const url=new URL('../../../release_schema6/'+name,import.meta.url);
 let source=readFileSync(url,'utf8');
 source=source.replace(/from '([^']+)'/g,(all,dep)=>{
  if(dep==='./lifecycle/offline_lease.mjs')return `from '${new URL('./synthetic_lease.mjs',import.meta.url).href}'`;
  if(replacements[dep])return `from '${replacements[dep]}'`;
  return dep.startsWith('.')?`from '${new URL(dep,url).href}'`:all;
 });
 return 'data:text/javascript;base64,'+Buffer.from(source).toString('base64');
}
const rawUrl=sourceModule('raw_state_backup.mjs');
export const raw=await import(rawUrl);
export const adapter=await import(sourceModule('recovery_adapter.mjs',{'./raw_state_backup.mjs':rawUrl}));
export const SCALE_CASES=Object.freeze({ten:{messages:70000,records:20000},fifty:{messages:350000,records:100000},capacity:{messages:100,records:200000}});
export const seconds=start=>Number(((performance.now()-start)/1000).toFixed(3));

export function scaleFixture(t) {
 const root=syntheticRoot('schema6-scale-synthetic-');
 const cleanup=()=>{assert.equal(path.dirname(root),realpathSync.native(tmpdir()));assert.ok(path.basename(root).startsWith('schema6-scale-synthetic-'));if(!existsSync(root))return;plainPath(root);rmSync(root,{recursive:true,force:true});};
 t?.after(cleanup);
 const state=path.join(root,'state'),backupDirectory=path.join(root,'raw-backups');mkdirSync(state);mkdirSync(backupDirectory);
 const databasePath=path.join(state,'i-core.sqlite');
 const store=new ICoreStore(databasePath,{activityEnabled:false,companionUploadMode:'legacy_b3'}),nodeId=store.nodeId;store.close();
 const o={databasePath,custodyDirectory:path.join(root,'custody'),custodyKey:randomBytes(32),backupKey:randomBytes(32),backupDirectory,
  configurationHash:sha256('synthetic-scale-config'),manifestSha256:sha256('synthetic-scale-release'),expectedNodeId:nodeId,receiptId:'synthetic-scale-close'};
 let custody=null;
 const setLease=()=>{o.supervisorLease=syntheticLease({databasePath,origin:custody?'canonical_restart':'empty_provision',cleanCloseReceipt:{receiptId:o.receiptId,databasePath,nodeId,databaseSha256:raw.rawFileHash(databasePath),custodySha256:custody?.custodySha256??null}});};
 const pin=result=>{custody=result;o.previousCustodySha256=result.custodySha256;setLease();return result;};
 const mutate=fn=>{const db=new DatabaseSync(databasePath);try{return fn(db);}finally{db.close();}};
 try{setLease();pin(adapter.sealClosedRecovery(o));setLease();pin(adapter.migrateToSchema6(o));}catch(error){cleanup();throw error;}
 return {root,state,o,nodeId,cleanup,mutate,pin,setLease,seal(){setLease();return pin(adapter.sealClosedRecovery(o));},recover(){setLease();return pin(adapter.recoverCanonicalState(o));},floorBytes(){return statSync(path.join(o.custodyDirectory,custody.custodySha256+'.floor.json')).size;}};
}

// Bulk fixture writes preserve real schema and one accepted op + receipt per
// record. Cryptographic witnesses are produced by DomainStore itself, never
// by a test-local authentication implementation. Setup is excluded from timing.
export function seedScale(f,{messages,records}) {
 const started=performance.now();const body=randomBytes(192).toString('base64');
 f.mutate(db=>{
  const secret=db.prepare("SELECT value FROM core_metadata WHERE key='cursor_secret'").get().value;
  const domain=new DomainStore(db,{nodeId:f.nodeId,cursorSecret:secret});
  domain.registerDomain('scale',{version:1,fields:{title:{type:'string',required:true}}},{mode:'authoritative'});
  domain.configurePrincipal({principal_id:'synthetic-scale',device_id:'scale-device',installation_id:'scale-install',actors:['user_direct'],trusted_interactive:true,scopes:['read','create','patch','delete','restore','purge'].map(v=>'scale:'+v)});
  const stamp=Date.now(),at=new Date(stamp).toISOString(),d=domain.domain('scale');
  db.exec('BEGIN IMMEDIATE');
  try {
   db.prepare('INSERT INTO devices VALUES(?,?,?,?,?,?,?,?,?)').run('scale-device','Synthetic','fixture','1','[]',sha256(randomBytes(32)),stamp,stamp,0);
   const change=db.prepare('INSERT INTO change_events(event_id,kind,entity_id,occurred_at_ms,payload_json) VALUES(?,?,?,?,?)');
   const message=db.prepare('INSERT INTO chat_messages VALUES(?,?,?,?,?,?,?,?,?,?,?,?)');
   for(let i=1;i<=messages;i++){
    const m={sync_id:'scale-message-'+i,origin_device_id:'scale-device',origin_sequence:i,character_id:'lin-ai',sender:i%2?'user':'companion',content:body+body,created_at_ms:stamp+i,message_type:'chat',asset_refs:[],addenda:[]};
    const sequence=change.run(randomUUID(),'chat.message.upsert',m.sync_id,stamp+i,JSON.stringify(m)).lastInsertRowid;
    message.run(m.sync_id,m.origin_device_id,i,m.character_id,m.sender,m.content,m.created_at_ms,m.message_type,'[]','[]',sha256(canonicalJSON(m)),sequence);
   }
   const record=db.prepare('INSERT INTO domain_records VALUES(?,?,?,?,?,?)'),op=db.prepare('INSERT INTO domain_ops VALUES(?,?,?,?,?,?,?)'),receipt=db.prepare('INSERT INTO domain_receipts VALUES(?,?,?,?)');
   const changes=db.prepare('INSERT INTO domain_changes(namespace,domain,id,revision,domain_sequence,changed_at) VALUES(?,?,?,?,?,?)');
   const payload=db.prepare('INSERT INTO domain_op_payloads VALUES(?,?,?,?,?,?)');
   for(let i=1;i<=records;i++){
    const id='scale-record-'+i,opId=randomUUID(),targets=[{id,revision:1}];
    const envelope={domain:'scale',schema_version:1,id,revision:1,created_at:at,updated_at:at,deleted_at:null,deleted_by:null,merged_into:null,body_state:'present',purge_after:null,origin:{principal_id:'synthetic-scale',device_id:'scale-device',created_op_id:opId},policy_version:DOMAIN_POLICY.version,core_instance_id:f.nodeId};
    const data={title:body.slice(0,160)},provenance={source:'synthetic',source_refs:[],import_batch_id:null};
    record.run('production','scale',id,1,canonicalJSON(envelope),canonicalJSON({data,field_meta:{title:{rev:1,actor:'user_direct',at,op_id:opId}},provenance}));
    const sequence=Number(changes.run('production','scale',id,1,i,at).lastInsertRowid);
    const r={receipt_id:randomUUID(),core_instance_id:f.nodeId,authority_mode:'single_host',epoch:null,domain:'scale',accepted_op_id:opId,principal_id:'synthetic-scale',accepted_at:at,policy_version:DOMAIN_POLICY.version,targets,change_sequences:[sequence]};r.receipt_auth=domain.mac(r);
    receipt.run(r.receipt_id,'production','scale',canonicalJSON(r));
    const request={domain_protocol_version:1,core_instance_id:f.nodeId,op_id:opId,schema_version:1,kind:'create',id,base_revision:0,created_at:at,expires_at:new Date(stamp+DOMAIN_POLICY.intentTtl).toISOString(),actor:'user_direct',data,provenance};
    const result={status:201,body:{domain_protocol_version:1,domain:'scale',op_id:opId,outcome:'accepted',reason:null,receipt:r,problem:null}},digest=domain.mac(request);
    const metadata=domain.recoveryMetadata('production','synthetic-scale','scale',opId,digest,result,{kind:'create',id,base_revision:0,actor:'user_direct',at,policy_version:DOMAIN_POLICY.version,outcome:'accepted',targets});
    op.run('production','synthetic-scale','scale',opId,digest,canonicalJSON(result),canonicalJSON(metadata));
    payload.run('production','synthetic-scale','scale',opId,canonicalJSON(request),null);
   }
   d.runtime.highwaters.production=records;domain.saveRuntime(d);
   assert.equal(db.prepare('PRAGMA foreign_key_check').get(),undefined);
   db.exec('COMMIT');
  } catch(error){db.exec('ROLLBACK');throw error;}
 });
 return {messages,changeEvents:messages,domainRecords:records,domainOps:records,domainReceipts:records,seedSeconds:seconds(started)};
}

export async function startCore(f){const core=createICoreServer({databasePath:f.o.databasePath,activityEnabled:false,companionUploadMode:'legacy_b3',companionReplyJobsEnabled:false});await core.listen({host:'127.0.0.1',port:0});return core;}
export async function safeClose(f,core){const begin=performance.now();await core.close();f.seal();return seconds(begin);}
export async function killSyntheticWriter(f){
 const fixedNode=syntheticFixedNode(f.root);
 const code="import {DatabaseSync} from 'node:sqlite';const db=new DatabaseSync(process.argv[1]);db.exec('PRAGMA journal_mode=WAL;PRAGMA wal_autocheckpoint=0');db.prepare('INSERT INTO core_metadata(key,value) VALUES(?,?)').run('synthetic_scale_committed','yes');process.stdout.write('ready\\n');setInterval(()=>{},1000);";
 const child=spawn(fixedNode,['--input-type=module','-e',code,f.o.databasePath],{windowsHide:true,stdio:['ignore','pipe','pipe']});const exited=once(child,'exit');
 await Promise.race([once(child.stdout,'data'),exited.then(()=>{throw new Error('synthetic_writer_failed');})]);child.kill('SIGKILL');await exited;
 assert.equal(existsSync(f.o.databasePath+'-wal'),true);
}
export async function nextStartup(f){const begin=performance.now();f.recover();const core=await startCore(f);assert.equal(f.mutate(db=>db.prepare("SELECT value FROM core_metadata WHERE key='synthetic_scale_committed'").get().value),'yes');return {core,seconds:seconds(begin)};}

function backupSpec(f){
 const sources=path.join(f.root,'bundle-inputs'),release=f.release??path.join(sources,'release');mkdirSync(sources,{recursive:true});
 if(!f.release){mkdirSync(release);writeFileSync(path.join(release,'manifest.json'),JSON.stringify({synthetic:true}));}
 const entries=[{role:'database',name:'data/i-core.sqlite',source_path:f.o.databasePath,sha256:raw.rawFileHash(f.o.databasePath)}];
 const inventory=(directory,prefix='')=>{for(const item of readdirSync(directory,{withFileTypes:true})){const filename=plainPath(path.join(directory,item.name)),name=prefix+item.name;if(item.isDirectory())inventory(filename,name+'/');else entries.push({role:'release',name,source_path:filename,sha256:raw.rawFileHash(filename)});}};inventory(release);
 const head=JSON.parse(readFileSync(path.join(f.o.custodyDirectory,'current-head.json'))),floor=JSON.parse(readFileSync(path.join(f.o.custodyDirectory,head.custodySha256+'.floor.json')));
 for(const role of BACKUP_ROLES.filter(r=>!['database','release'].includes(r))){const filename=path.join(sources,role+'.json');writeFileSync(filename,JSON.stringify(role==='recovery_custody'?{format:'i-core-recovery-custody-v1',mode:'activity_floor',node_id:f.nodeId,database_path:f.o.databasePath,activity_recovery_floor:floor.activityRecoveryFloor}:{synthetic:true,role}));entries.push({role,name:'inputs/'+role+'.json',source_path:filename,sha256:raw.rawFileHash(filename)});}
 const context=entries.find(e=>e.role==='recovery_custody');context.custody_context=true;
 for(const [name,filename] of [['current-head.json',path.join(f.o.custodyDirectory,'current-head.json')],['floor.json',path.join(f.o.custodyDirectory,head.custodySha256+'.floor.json')]])entries.push({role:'recovery_custody',name:'custody/'+name,source_path:filename,sha256:raw.rawFileHash(filename)});
 const spec={format:'i-core-runtime-backup-spec-v1',source_schema:6,node_id:f.nodeId,canonical_database_path:f.o.databasePath,old_release_root:release,old_release_manifest_sha256:entries.find(e=>e.role==='release'&&e.name==='manifest.json').sha256,entries};
 return spec;
}
export function bundleBackup(f){
 const begin=performance.now(),spec=backupSpec(f);
 const result=createRuntimeBackup({spec,outputDirectory:path.join(f.root,'daily-bundle'),key:f.o.backupKey});assert.equal(verifyRuntimeBackup({...result,key:f.o.backupKey}).verified,true);
 return {seconds:seconds(begin),bytes:statSync(result.artifactPath).size,sha256:result.artifactSha256};
}
export async function dailyBackup(f){
 const setup=performance.now(),spec=backupSpec(f),backupSetId=sha256(randomBytes(32)),password=randomBytes(32);
 let envelope;try{envelope=wrapBackupKey({key:f.o.backupKey,password,backupSetId});}finally{password.fill(0);}
 const outputRoot=path.join(f.root,'automatic-daily');mkdirSync(outputRoot);backupFilePrimitives.protect(outputRoot);
 const policy={format:'i-core-automatic-backup-v1',outputRoot,retentionDays:30,backupSetId};
 const setupSeconds=seconds(setup),begin=performance.now();
 const result=await runDueAutomaticBackup({policy,specTemplate:spec,key:f.o.backupKey,envelope});assert.equal(result.status,'backed_up');
 const jobs=readdirSync(outputRoot).filter(n=>n.startsWith('daily-'));assert.equal(jobs.length,1);
 const job=path.join(outputRoot,jobs[0]),artifactPath=path.join(job,'artifact','runtime.aes256gcm');
 assert.equal(verifyRuntimeBackup({artifactPath,artifactSha256:result.artifactSha256,key:f.o.backupKey}).verified,true);
 verifyPortableBinding({key:f.o.backupKey,envelope,binding:JSON.parse(readFileSync(path.join(job,'portable-binding.json')))});
 assert.equal(existsSync(path.join(job,'receipt.json')),true);
 return {seconds:seconds(begin),setupSeconds,bytes:statSync(artifactPath).size,sha256:result.artifactSha256,pruned:result.pruned,mirrorIncluded:false,osSchedulingIncluded:false};
}
