import { createHmac } from 'node:crypto';
import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { cleanEnvironment, plainPath, sha256, verifyRelease } from '../package.mjs';
import { assertNode, inspectExisting, closedStateSnapshot, validatePrevious, MARKER, separatePaths, readConfigurationDeclaration, publicLifecycleErrorCode } from './common.mjs';
import { readConfiguration, protectedPath } from './configuration.mjs';
import { createOfflineLease, recordClosedDatabase, closeOfflineLease } from './offline_lease.mjs';
import { sealClosedRecovery, verifyCanonicalRestart, migrateToSchema6, rollbackEmptySchema6, switchClosedPackage } from '../recovery_adapter.mjs';
import { needsStartupRecovery, recoverAtStartup } from '../automatic_recovery.mjs';
import { SWITCH_PENDING, readSwitchPlan, verifySwitchConfigurations } from '../package_switch.mjs';
import { isInspectionDatabasePath } from '../../inspection_read_only.mjs';

const [control,token,mode,...extra]=process.argv.slice(2);
let config,core,lifecycle,settings,lease,poll,started=false,closed=false,offlineCompleted=false;
function writeControl(name,value) {
 const target=path.join(control,name),pending=target+'.pending';
 plainPath(target,{missing:true});plainPath(pending,{missing:true});
 if(existsSync(target)) throw new Error('control_receipt_exists');
 writeFileSync(pending,JSON.stringify(value)+'\n',{flag:'wx',flush:true});renameSync(pending,target);
}
function saveMarker(value) {
 const target=path.join(config.state,MARKER),pending=path.join(config.state,'s6-marker-'+token+'.tmp');
 plainPath(target,{missing:true});plainPath(pending,{missing:true});
 writeFileSync(pending,JSON.stringify(value)+'\n',{flag:'wx',flush:true});renameSync(pending,target);
}
function closedReceipt(snapshot) {
 return {receiptId:token,databasePath:path.join(config.state,'i-core.sqlite'),nodeId:snapshot.nodeId,
 databaseSha256:snapshot.database_sha256,custodySha256:lifecycle.custody_sha256??null};
}
async function shutdown(reason,failure=null) {
 if(closed)return;closed=true;clearInterval(poll);let clean=false;
 try {
  if(core || offlineCompleted) {
   if(core) await core.close();
   if(core && (core.server.listening || core.store.db.isOpen)) throw new Error('resource_close_unconfirmed');
   // The seal's immutable inspect verifies actual identity/schema/claim and full
   // integrity against this exact closed hash; do not duplicate that scan here.
   const snapshot=closedStateSnapshot(config.state);
   const final={nodeId:lifecycle.node_id,database_sha256:snapshot.databaseSha256};
   recordClosedDatabase(lease,closedReceipt(final));
   const custody=await sealClosedRecovery({databasePath:path.join(config.state,'i-core.sqlite'),supervisorLease:lease,
     custodyDirectory:settings.value.recovery_custody_directory,custodyKey:settings.custodyKey});
   lifecycle={...lifecycle,phase:'close_prepared',database_sha256:final.database_sha256,
    state_tree_sha256:snapshot.stateTreeSha256,custody_sha256:custody.custodySha256};
   saveMarker(lifecycle);clean=true;
  }
 } catch(error){failure??=error;clean=false;}
 try{await closeOfflineLease(lease);}catch(error){failure??=error;clean=false;}
 if(failure)clean=false;
 writeControl('child.json',{token,mode,manifest_sha256:config.manifest_sha256,
  phase:clean?'clean_closed':started?'recovery_required':'rejected_before_store',reason,
  store_construction_attempted:started,store_close_confirmed:clean,listener_closed_confirmed:core?core.server.listening===false:true,
  ...(failure?{error_code:publicLifecycleErrorCode(failure)}:{})});
 process.exitCode=clean?0:1;
}
try {
 if(extra.length || !['start','initialize-empty','offline-verify','offline-migrate','offline-rollback','offline-package-switch'].includes(mode) || !/^[a-f0-9]{64}$/.test(token??''))throw new Error('invalid_internal_arguments');
 assertNode();plainPath(control);
 config=JSON.parse(readFileSync(plainPath(path.join(control,'launch.json'))));
 if(config.token!==token || config.mode!==mode || config.lifecycle!==path.dirname(fileURLToPath(import.meta.url))
   || !Number.isInteger(config.port) || config.port<0 || config.port>65535)throw new Error('launch_identity_mismatch');
 separatePaths(config.release,config.state,control);
 verifyRelease(config.release,config.manifest_sha256);
 const cleanEnv=cleanEnvironment();for(const name of Object.keys(process.env))if(!(name in cleanEnv))delete process.env[name];
 protectedPath(control,true);protectedPath(path.join(control,'launch.json'));protectedPath(path.join(control,'stop.key'));
 const filename=path.join(config.state,'i-core.sqlite'),markerPath=path.join(config.state,MARKER);
 if(isInspectionDatabasePath(filename))throw new Error('inspection_activation_unsupported');
 const initial=mode==='initialize-empty';
 let previous=null,before=null,recovered=null;
 if(initial) {
  if(existsSync(filename) || existsSync(markerPath))throw new Error('initialize_requires_empty_state');
 } else {
  plainPath(filename);
  if(existsSync(markerPath))previous=JSON.parse(readFileSync(plainPath(markerPath)));
 }
 // Read only protected JSON here. Opening even immutable SQLite before raw
 // preservation would erase the guarantee for a dirty WAL/journal source.
 protectedPath(config.configuration_file);
 const declared=readConfigurationDeclaration(config.configuration_file);
 settings=readConfiguration(config.configuration_file,{manifest_sha256:config.manifest_sha256,database_path:filename,
  node_id:initial?'new':previous?.node_id??declared.node_id,owner_sid:config.owner_sid,release:config.release,provisioned_empty:initial||previous?.provisioned_empty===true});
 const packageSwitch=mode==='offline-package-switch';
 if(!packageSwitch&&(existsSync(path.join(config.state,SWITCH_PENDING))||existsSync(path.join(settings.value.recovery_custody_directory,'package-switch-pending.json'))))throw new Error('switch_pending_review_required');
 if(packageSwitch){
  const plan=readSwitchPlan(config.package_switch_plan,config.package_switch_sha256);
  verifySwitchConfigurations(plan);
  if(![plan.from,plan.to].some(e=>e.releaseDirectory===config.release&&e.manifestSha256===config.manifest_sha256&&e.configurationPath===config.configuration_file&&e.configurationSha256===settings.configurationHash))throw new Error('switch_executor_unbound');
  lease=createOfflineLease({control,token,config,origin:'package_switch',cleanCloseReceipt:null});
  const result=switchClosedPackage({databasePath:filename,supervisorLease:lease,custodyDirectory:settings.value.recovery_custody_directory,custodyKey:settings.custodyKey,
   planPath:config.package_switch_plan,planSha256:config.package_switch_sha256,receiptId:token});
  writeControl('package-switch-marker.json',result.marker);
  writeControl('operation.json',{operation:mode,event_sha256:result.eventSha256,head_sha256:result.headSha256,custody_generation:result.custodyGeneration,target_manifest_sha256:plan.to.manifestSha256});
  await closeOfflineLease(lease);lease=null;closed=true;
  writeControl('child.json',{token,mode,manifest_sha256:config.manifest_sha256,phase:'clean_closed',reason:'package_switch_completed',
    store_construction_attempted:false,store_close_confirmed:true,listener_closed_confirmed:true});
 }else{
 const recoveryNeeded=!initial&&needsStartupRecovery(filename,previous);
 lease=createOfflineLease({control,token,config,origin:initial?'empty_provision':recoveryNeeded?'canonical_recovery':'canonical_restart',cleanCloseReceipt:null});
 if(recoveryNeeded){
  if(mode!=='start')throw new Error('recovery_requires_normal_start');
  recovered=recoverAtStartup({config,settings,previous,supervisorLease:lease});
  before=inspectExisting(filename,['6']);
  recordClosedDatabase(lease,{receiptId:token,databasePath:filename,nodeId:before.nodeId,databaseSha256:before.database_sha256,custodySha256:recovered.custodySha256});
 }else if(!initial){
  before=inspectExisting(filename,mode.startsWith('offline-')?['5','6']:['6']);
  validatePrevious(previous,config,before,settings.configurationHash);
  recordClosedDatabase(lease,{receiptId:previous.token,databasePath:filename,nodeId:before.nodeId,databaseSha256:before.database_sha256,custodySha256:previous.custody_sha256});
 }
 const secretValues=[settings.value.pairing_secret,settings.custodyKey.toString('hex'),readFileSync(path.join(control,'stop.key'),'utf8')].filter(Boolean);
 if(secretValues.some(secret=>process.argv.some(arg=>arg.includes(secret))))throw new Error('secret_in_argument_path_rejected');
 lifecycle={format:'schema6-lifecycle-v1',token,database_path:filename,node_id:before?.nodeId??null,manifest_sha256:config.manifest_sha256,
  configuration_sha256:settings.configurationHash,phase:'opening',provisioned_empty:initial||previous?.provisioned_empty===true,custody_sha256:recovered?.custodySha256??previous?.custody_sha256??null};
 if(!initial && !['offline-migrate','offline-rollback','offline-package-switch'].includes(mode))await verifyCanonicalRestart({databasePath:filename,supervisorLease:lease,custodyDirectory:settings.value.recovery_custody_directory,custodyKey:settings.custodyKey});
 if(existsSync(path.join(control,'stop')))throw new Error('cancelled_before_store');
 saveMarker(lifecycle);
 if(mode.startsWith('offline-')) {
  if(mode!=='offline-verify') {
   if(!settings.value.backup_key_path || !settings.value.backup_directory)throw new Error('offline_backup_configuration_required');
   started=true;
   const transition=mode==='offline-migrate'?migrateToSchema6:rollbackEmptySchema6;
   const result=await transition({databasePath:filename,supervisorLease:lease,custodyDirectory:settings.value.recovery_custody_directory,custodyKey:settings.custodyKey,
    backupKey:settings.backupKey,backupDirectory:settings.value.backup_directory});
   lifecycle.custody_sha256=result.custodySha256;
   writeControl('operation.json',{operation:mode,database_schema_version:result.schemaVersion,canonical_path_preserved:result.canonicalPathPreserved,legacy_digest_verified:result.legacyDigestVerified});
  }
  offlineCompleted=true;await shutdown('offline_completed');
 } else {
 const {createICoreServer}=await import(pathToFileURL(path.join(config.release,'tools/i_core/i_core_server.mjs')));
 started=true;core=createICoreServer({databasePath:filename,...settings.options});
 if(core.store.health().schema_version!==(initial?5:6) || (before && core.store.nodeId!==before.nodeId))throw new Error('runtime_identity_mismatch');
 lifecycle.node_id=core.store.nodeId;
 if(initial) {
  // Establish the independent empty genesis before any caller can pair or write.
  await core.close();
  if(core.server.listening || core.store.db.isOpen)throw new Error('genesis_close_unconfirmed');
  const genesis=inspectExisting(filename,['5']);
  recordClosedDatabase(lease,closedReceipt(genesis));
  const sealed=await sealClosedRecovery({databasePath:filename,supervisorLease:lease,custodyDirectory:settings.value.recovery_custody_directory,custodyKey:settings.custodyKey});
  lifecycle.custody_sha256=sealed.custodySha256;saveMarker(lifecycle);
  recordClosedDatabase(lease,closedReceipt(genesis));
  if(!settings.backupKey || !settings.value.backup_directory)throw new Error('empty_provision_backup_required');
  const migrated=await migrateToSchema6({databasePath:filename,supervisorLease:lease,custodyDirectory:settings.value.recovery_custody_directory,custodyKey:settings.custodyKey,
   backupKey:settings.backupKey,backupDirectory:settings.value.backup_directory});
  lifecycle.custody_sha256=migrated.custodySha256;
  recordClosedDatabase(lease,closedReceipt(inspectExisting(filename)));
  saveMarker(lifecycle);
  await verifyCanonicalRestart({databasePath:filename,supervisorLease:lease,custodyDirectory:settings.value.recovery_custody_directory,custodyKey:settings.custodyKey});
  core=createICoreServer({databasePath:filename,...settings.options});
 }
 lifecycle.phase='store_created';saveMarker(lifecycle);
 const address=await core.listen({host:'127.0.0.1',port:config.port});
 lifecycle.phase='listening';saveMarker(lifecycle);
 writeControl('ready.json',{token,manifest_sha256:config.manifest_sha256,node_sha256:sha256(readFileSync(process.execPath)),
  configuration_sha256:settings.configurationHash,pid:process.pid,address,health:core.store.health(),activity_enabled:core.store.activity.active,
  companion_upload_mode:'legacy_b3',companion_reply_jobs:false,domain_policy:'owner_managed',relay:'disabled',
  commandline_secret_free:true,inherited_core_keys:Object.keys(process.env).filter(k=>k.toUpperCase().startsWith('I_CORE_'))});
 poll=setInterval(()=>{
  try {
   for(const name of ['close','stop']) {
    const target=path.join(control,name);
    let value;try{value=readFileSync(plainPath(target),'utf8');}catch(e){if(e.code==='ENOENT'||e.code==='input_missing_or_aliased')continue;throw e;}
    const expected=createHmac('sha256',readFileSync(path.join(control,'stop.key'),'utf8')).update(token+'|'+config.manifest_sha256+'|'+name).digest('hex');
    if(value===expected)void shutdown(name+'_requested');
   }
  }catch(error){void shutdown('control_failed',error);}
 },25);
 process.once('SIGINT',()=>{void shutdown('signal');});
 process.once('SIGTERM',()=>{void shutdown('signal');});
 }
}}catch(error){if(config)await shutdown('startup_failed',error);else{process.stderr.write('fixed_child_rejected\n');process.exitCode=2;}}
