import { createHmac, timingSafeEqual } from 'node:crypto';
import { existsSync, lstatSync, readFileSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
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
import { provisionFoodDomain } from '../../personal_data_domains.mjs';

// Food provisioning is isolated from pairing and from the shutdown boundary.
export function createFoodProvisionPoller({control, token, manifestSha256, core, writeReceipt, now = Date.now}) {
 const requestPath = path.join(control, 'food.request');
 const seen = new Set();
 let sequence = 0;
 return function pollFoodProvision() {
  let requestId = null, status = 'rejected_invalid_request';
  const emit = value => {
   try { writeReceipt('food-receipt-' + (++sequence) + '.json', {...value, at_ms: now()}); }
   catch { /* Receipt failures never stop Core. */ }
  };
  try {
   let info;
   try { info = lstatSync(requestPath); } catch (error) { if (error.code === 'ENOENT') return; throw error; }
   let raw;
   try {
    if (!info.isFile() || info.isSymbolicLink()) throw new Error('food_input_type');
    plainPath(requestPath);
    if (info.size > 1024) throw new Error('food_input_size');
    raw = readFileSync(requestPath);
    if (raw.length > 1024) throw new Error('food_input_size');
   } finally {
    // No parsed request, credential issuance or host callback before consumption.
    unlinkSync(requestPath);
   }
   const request = JSON.parse(raw.toString('utf8'));
   if (!request || Array.isArray(request) || Object.keys(request).sort().join(',') !== 'expires_at_ms,hmac,request_id,rotate'
     || typeof request.request_id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(request.request_id)
     || !Array.isArray(request.rotate) || new Set(request.rotate).size !== request.rotate.length
     || request.rotate.some(role => !['writer', 'phone'].includes(role))
     || !Number.isSafeInteger(request.expires_at_ms) || typeof request.hmac !== 'string' || !/^[a-f0-9]{64}$/.test(request.hmac)) throw new Error('food_input_request');
   requestId = request.request_id.toLowerCase();
   status = 'rejected_expired';
   if (request.expires_at_ms <= now() || request.expires_at_ms > now() + 600000) throw new Error('food_input_expiry');
   status = 'rejected_authentication';
   const key = readFileSync(plainPath(path.join(control, 'stop.key')), 'utf8');
   const expected = createHmac('sha256', key).update(token + '|' + manifestSha256 + '|food|' + request.request_id + '|' + [...request.rotate].sort().join(',') + '|' + request.expires_at_ms).digest();
   if (!timingSafeEqual(expected, Buffer.from(request.hmac, 'hex'))) throw new Error('food_input_authentication');
   status = 'rejected_replay';
   if (seen.has(requestId)) throw new Error('food_input_replay');
   seen.add(requestId);
   status = 'rejected_provision_failed';
   const result = provisionFoodDomain(core.store.domains, {rotate: request.rotate});
   const issued = Object.keys(result.issued);
   if (issued.length) {
    const tokens = {format: 'food-tokens-v1', request_id: request.request_id};
    for (const role of issued) tokens[role + '_token'] = result.issued[role];
    writeFileSync(path.join(control, 'food-tokens-' + request.request_id + '.json'), JSON.stringify(tokens), {flag: 'wx', mode: 0o600});
   }
   emit({status: 'provisioned', request_id: request.request_id, registered: result.registered, issued, hooks_version: 'food-v1'});
  } catch (error) {
   emit({status: error.code === 'food_domain_conflict' ? 'rejected_food_domain_conflict' : status, request_id: requestId});
  }
 };
}

// Pairing is an independent control channel. Its inputs and receipt failures must
// never reach the shutdown handler used by close/stop.
export function createPairingRequestPoller({control, token, manifestSha256, core, writeReceipt, now = Date.now}) {
 const codePath = path.join(control, 'pair.code');
 const requestPath = path.join(control, 'pair.request');
 const publishingPath = path.join(control, 'pair.request.pending');
 const seen = new Set();
 let active = null, sequence = 0;
 const emit = (status, codeHash = null) => {
  try {
   writeReceipt('pair-receipt-' + (++sequence) + '.json', {
    status, code_hash_prefix: codeHash?.slice(0, 16) ?? null, at_ms: now(),
   });
  } catch { /* A failed receipt cannot stop a running Core. */ }
 };
 const removeInputs = () => {
  for (const filename of [codePath, requestPath]) {
   try { unlinkSync(filename); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
 };
 return function pollPairingRequest() {
  try {
   if (active && (now() >= active.expiresAt || !core.hasActivePairingCode())) {
    const reason = now() >= active.expiresAt ? 'closed_expired' : 'closed_paired';
    core.closePairingWindow();
    emit(reason, active.codeHash); active = null;
   }
  } catch { emit('rejected_window_state'); }
  let codeHash = null, rejection = 'rejected_invalid_request';
  try {
   if (!existsSync(requestPath)) {
    // A live publisher's bounded reservation bridges its two atomic renames.
    // A crashed publisher cannot block another window beyond its expiry.
    if (existsSync(publishingPath)) {
     let abandoned = false, observed;
     try {
      plainPath(publishingPath); observed = lstatSync(publishingPath);
      // A malformed/locked reservation gets a full bounded publication grace.
      abandoned = observed.mtimeMs + 600000 <= now();
      if (observed.size <= 4096) {
       const pending = JSON.parse(readFileSync(publishingPath, 'utf8'));
       if (Number.isSafeInteger(pending.expires_at_ms)) abandoned = pending.expires_at_ms <= now();
      }
     } catch { return; /* Partial writes and sharing conflicts are not abandonment. */ }
     if (!abandoned || !observed || existsSync(requestPath)) return;
     let current; try { current = lstatSync(publishingPath); } catch { return; }
     if (current.ino !== observed.ino || current.mtimeMs !== observed.mtimeMs || current.size !== observed.size) return;
     // Never delete a final request based on an older reservation snapshot.
     for (const filename of [codePath, codePath + '.pending', publishingPath]) {
      try { unlinkSync(filename); } catch (error) { if (error.code !== 'ENOENT') { emit('rejected_abandoned_publish'); return; } }
     }
     emit('rejected_abandoned_publish');
    } else if (existsSync(codePath)) {
     removeInputs(); emit('rejected_orphan_code');
    }
    return;
   }
   plainPath(requestPath); plainPath(codePath);
   if (lstatSync(requestPath).size > 4096 || lstatSync(codePath).size !== 64) throw new Error('pair_input_size');
   const code = readFileSync(codePath, 'utf8');
   if (!/^[a-f0-9]{64}$/.test(code)) throw new Error('pair_input_code');
   codeHash = sha256(Buffer.from(code));
   const request = JSON.parse(readFileSync(requestPath, 'utf8'));
   if (!request || Object.keys(request).sort().join(',') !== 'expires_at_ms,hmac'
     || !Number.isSafeInteger(request.expires_at_ms) || !/^[a-f0-9]{64}$/.test(request.hmac ?? '')) throw new Error('pair_input_request');
   rejection = 'rejected_expired';
   if (request.expires_at_ms <= now() || request.expires_at_ms > now() + 600000) throw new Error('pair_input_expiry');
   rejection = 'rejected_authentication';
   const key = readFileSync(plainPath(path.join(control, 'stop.key')), 'utf8');
   const expected = createHmac('sha256', key).update(token + '|' + manifestSha256 + '|pair|' + codeHash + '|' + request.expires_at_ms).digest();
   if (!timingSafeEqual(expected, Buffer.from(request.hmac, 'hex'))) throw new Error('pair_input_authentication');
   rejection = 'rejected_replay';
   if (seen.has(request.hmac)) throw new Error('pair_input_replay');
   // Mark consumed before deleting either input or exposing the code to Core.
   seen.add(request.hmac);
   rejection = 'rejected_consumption';
   removeInputs();
   core.replacePairingCode(code, {singleUseWindow: true, expiresAtMs: request.expires_at_ms});
   active = {expiresAt: request.expires_at_ms, codeHash};
   emit('opened', codeHash);
  } catch {
   try { removeInputs(); } catch { /* Preserve the original rejection, stay alive. */ }
   emit(rejection, codeHash);
  }
 };
}

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
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
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
 const {createFoodDomainHooks,FOOD_WRITER_PRINCIPAL_ID}=await import(pathToFileURL(path.join(config.release,'tools/i_core/personal_data_domains.mjs')));
 const domainHooks=createFoodDomainHooks({writerPrincipalIds:[FOOD_WRITER_PRINCIPAL_ID]});
 started=true;core=createICoreServer({databasePath:filename,...settings.options,domainHooks});
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
  core=createICoreServer({databasePath:filename,...settings.options,domainHooks});
 }
 lifecycle.phase='store_created';saveMarker(lifecycle);
 const address=await core.listen({host:'127.0.0.1',port:config.port});
 lifecycle.phase='listening';saveMarker(lifecycle);
 writeControl('ready.json',{token,manifest_sha256:config.manifest_sha256,node_sha256:sha256(readFileSync(process.execPath)),
  configuration_sha256:settings.configurationHash,pid:process.pid,address,health:core.store.health(),activity_enabled:core.store.activity.active,
  companion_upload_mode:'legacy_b3',companion_reply_jobs:false,domain_policy:'owner_managed',relay:'disabled',
  commandline_secret_free:true,inherited_core_keys:Object.keys(process.env).filter(k=>k.toUpperCase().startsWith('I_CORE_'))});
 const pollPairingRequest=createPairingRequestPoller({control,token,manifestSha256:config.manifest_sha256,core,writeReceipt:writeControl});
 const pollFoodProvision=createFoodProvisionPoller({control,token,manifestSha256:config.manifest_sha256,core,writeReceipt:writeControl});
 poll=setInterval(()=>{
  try {pollPairingRequest();}catch{/* Pairing never shares the shutdown boundary. */}
  try {pollFoodProvision();}catch{/* Food never shares the shutdown boundary. */}
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
}
