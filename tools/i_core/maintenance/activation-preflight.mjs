import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {DatabaseSync} from 'node:sqlite';

const digest=b=>crypto.createHash('sha256').update(b).digest('hex');
function pinnedJson(ref){if(!ref||!/^[a-f0-9]{64}$/.test(ref.sha256))throw Error('pin_required');const b=fs.readFileSync(ref.path);if(digest(b)!==ref.sha256)throw Error('pin_changed');return JSON.parse(b.toString('utf8').replace(/^\uFEFF/,''));}
function validate(spec){
 if(spec?.format!=='continuous-activation-preflight-input-v1'||spec.evidenceMode!=='reviewed-live'||!['closed','pending','post-switch'].includes(spec.operation))throw Error('preflight_context');
 if(!Array.isArray(spec.sourceFiles)||spec.sourceFiles.length!==55)throw Error('baseline_source_inventory');
 const root=path.resolve(spec.sourceRoot);
 for(const x of spec.sourceFiles){const target=path.resolve(x.path);if(!target.startsWith(root+path.sep)||fs.lstatSync(target).isSymbolicLink()||digest(fs.readFileSync(target))!==x.sha256)throw Error('baseline_source_pin');}
 for(const name of ['tools/i_core/release_schema6/lifecycle/common.mjs','tools/i_core/release_schema6/lifecycle/configuration.mjs','tools/i_core/release_schema6/package.mjs','tools/i_core/release_schema6/backup_bundle.mjs'])if(!spec.sourceFiles.some(x=>path.resolve(x.path)===path.join(root,name)))throw Error('baseline_module_missing');
 if(spec.operation==='pending'){const parent=path.dirname(path.resolve(spec.capture));if(parent!==path.resolve(spec.attemptDirectory)||path.basename(spec.capture)!=='pending-private-capture')throw Error('capture_scope');}
}
async function closed(spec){const source=spec.sourceRoot;
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const read=p=>fs.readFileSync(p),json=p=>JSON.parse(read(p).toString('utf8').replace(/^\uFEFF/,'')),need=(v,c)=>{if(!v)throw Object.assign(new Error(c),{code:c})};

let keys=null,report={format:'schema6-failure-closed-state-proof-v1',passed:false,observedAt:new Date().toISOString(),sqliteOpened:false,accountCredentialsRead:false,stateOrCustodyWritten:false,secretMaterialEmitted:false};
try{
 const cfg=pinnedJson(spec.baselineRegistration);
 for(const r of cfg.maintenanceFiles)need(sha(read(r.path))===r.sha256,'frozen_source_changed');
 const common=await import(pathToFileURL(path.join(source,'tools/i_core/release_schema6/lifecycle/common.mjs')));
 const config=await import(pathToFileURL(path.join(source,'tools/i_core/release_schema6/lifecycle/configuration.mjs')));
 const pkg=await import(pathToFileURL(path.join(source,'tools/i_core/release_schema6/package.mjs')));
 common.assertNode();pkg.verifyRelease(cfg.releaseDirectory,cfg.manifestSha256);
 const login=pinnedJson(spec.baselineLogin),corePath=login.core_configuration_path;
 need(sha(read(corePath))===login.core_configuration_sha256,'core_configuration_changed');
 const declaration=json(corePath),state=login.state_directory,custody=declaration.recovery_custody_directory;
 const markerPath=path.join(state,'s6-lifecycle.json'),headPath=path.join(custody,'current-head.json');
 const marker=json(markerPath),headRaw=read(headPath),head=json(headPath);
 need(sha(headRaw)==='bc6d6941bc9d93e4c56d1dd11a7f9d11d66a09f9c83a4afc1f426d4bd24d1ce8','current_head_raw_sha_changed');
 need(marker.phase==='clean_closed'&&marker.manifest_sha256===cfg.manifestSha256&&marker.configuration_sha256===login.core_configuration_sha256,'closed_marker_binding');
 need(head.generation===12&&head.previousHeadSha256==='58fa18a25fc78e2f2d1c7bd75e80d282d33c9adace6ea928ea46d6c1348faf18','head_progress_changed');
 need(head.receiptId===marker.token&&head.custodySha256===marker.custody_sha256&&head.nodeId===marker.node_id&&head.databasePath===declaration.database_path,'head_marker_binding');
 const sidecars=['-wal','-shm','-journal'].filter(s=>fs.existsSync(declaration.database_path+s));
 need(sidecars.length===0,'core_sidecar_present');
 const snap=common.closedStateSnapshot(state);
 need(snap.databaseSha256===marker.database_sha256&&snap.stateTreeSha256===marker.state_tree_sha256,'closed_state_mismatch');
 const family=()=>fs.readdirSync(custody).filter(n=>n!=='custody.lock').sort().map(n=>{const p=path.join(custody,n),st=fs.lstatSync(p);need(st.isFile()&&!st.isSymbolicLink()&&st.nlink===1,'custody_file_identity');return {name:n,bytes:st.size,sha256:sha(read(p))}});
 const before=family();
 keys=config.readConfiguration(corePath,{manifest_sha256:cfg.manifestSha256,database_path:declaration.database_path,owner_sid:login.owner_sid,node_id:marker.node_id,release:cfg.releaseDirectory,provisioned_empty:false});
 function auth(raw,format){const envelope=JSON.parse(raw),{authentication,...body}=envelope;
  need(/^[a-f0-9]{64}$/.test(authentication??''),'custody_authentication_missing');
  const mac=crypto.createHmac('sha256',keys.custodyKey).update('i-core-floor-custody-v1\0').update(JSON.stringify(body)).digest();
  need(crypto.timingSafeEqual(mac,Buffer.from(authentication,'hex'))&&body.format===format,'custody_authentication_failed');return body;
 }
 const seen=[],floors=new Set();let raw=headRaw,body=auth(raw,'i-core-custody-head-v1');
 for(;;){
  const hash=sha(raw),stored=read(path.join(custody,hash+'.head.json'));
  need(raw.equals(stored),'head_immutable_copy_mismatch');
  need(body.databasePath===declaration.database_path&&body.nodeId===marker.node_id&&Number.isSafeInteger(body.generation)&&body.generation>=1,'head_identity');
  const floorRaw=read(path.join(custody,body.custodySha256+'.floor.json'));
  need(sha(floorRaw)===body.custodySha256,'floor_digest');
  const floor=auth(floorRaw,'i-core-floor-custody-v1');
  need(floor.databasePath===body.databasePath&&floor.nodeId===body.nodeId&&floor.cleanCloseReceiptId===body.receiptId,'floor_identity');
  if(body.generation===head.generation)need(floor.databaseSha256===snap.databaseSha256&&floor.schemaVersion===6,'latest_floor_database_binding');
  seen.push({generation:body.generation,headSha256:hash,floorSha256:body.custodySha256});floors.add(body.custodySha256);
  if(body.generation===1){need(body.previousHeadSha256===null,'genesis_predecessor');break}
  need(/^[a-f0-9]{64}$/.test(body.previousHeadSha256??''),'head_predecessor');
  const priorRaw=read(path.join(custody,body.previousHeadSha256+'.head.json'));
  need(sha(priorRaw)===body.previousHeadSha256,'head_chain_digest');
  const prior=auth(priorRaw,'i-core-custody-head-v1');
  need(prior.generation===body.generation-1,'head_chain_generation');
  raw=priorRaw;body=prior;
 }
 need(JSON.stringify(before)===JSON.stringify(family()),'custody_changed_during_check');
 need(sha(read(markerPath))==='7ea847cae5b9a1f0d44f7b6f757162d407089a28373fa31bcc28cfc05cffa2cb'&&read(headPath).equals(headRaw),'closed_marker_or_head_changed');
 need(JSON.stringify(snap)===JSON.stringify(common.closedStateSnapshot(state)),'state_changed_during_check');
 const {backupFilePrimitives:f}=await import(pathToFileURL(path.join(source,'tools/i_core/release_schema6/backup_bundle.mjs')));
 const dailyPath=spec.baselineDaily.path;need(sha(read(dailyPath))===spec.baselineDaily.sha256,'daily_configuration_changed');
 const policy=json(dailyPath).policy;need(policy.retentionDays===30&&policy.backupSetId==='18eb2d735abb417cbc60702f41480d19c2fce86e11c84300bb48ef7a065b6b25','daily_policy_changed');
 const retention=[];for(const root of [policy.outputRoot,policy.mirrorRoot]){
 f.safe(root,true);const entries=[];for(const d of fs.readdirSync(root,{withFileTypes:true})){if(!d.isDirectory())continue;const p=path.join(root,d.name,'receipt.json');if(!fs.existsSync(p))continue;const r=json(p);if(r.backupSetId===policy.backupSetId){need(Number(r.completedAt)>=Date.now()-30*86400000,'retention_deletion_candidate_found');entries.push({name:d.name,completedAt:r.completedAt,receiptSha256:sha(read(p))})}}
 need(entries.length===2,'daily_metadata_changed');retention.push({root,entries,expiredCount:0});}
 report={...report,retention,passed:true,sourceFiles:55,releaseFiles:48,closedMarkerSha256:sha(read(markerPath)),headSha256:sha(headRaw),generation:head.generation,previousHeadSha256:head.previousHeadSha256,databaseSha256:snap.databaseSha256,stateTreeSha256:snap.stateTreeSha256,sidecarsAbsent:true,sourceGen10DatabaseUnchanged:snap.databaseSha256==='848fb6b71ce767fc548ededc8d63e0b06ae055bffbfd7f037f196ab98f660491',sourceGen10StateUnchanged:snap.stateTreeSha256==='4e24db96421f763f803ca8126c11ce9eb0151284e1991c0b563a5d559bc54649',custodyHmacVerified:true,custodyKeyUsedOnlyInMemory:true,authenticatedHeadCount:seen.length,authenticatedDistinctFloorCount:floors.size,custodyChain:seen,custodyFiles:before,coreStateUnchangedDuringCheck:true,custodyLockFileExcludedFromContentHash:true,floorProgressAgainstSqliteRecomputed:false,completedAt:new Date().toISOString()};
}catch(e){report={...report,passed:false,code:String(e.code??e.message??'closed_proof_rejected')};/* returned failure */}
finally{keys?.custodyKey?.fill(0);keys?.backupKey?.fill(0)}
return report;
}
async function pending(spec){const capture=spec.capture;
const sha=b=>crypto.createHash('sha256').update(b).digest('hex'),json=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,'')),need=(v,c)=>{if(!v)throw Object.assign(new Error(c),{code:c})};
const {backupFilePrimitives:f}=await import(pathToFileURL(path.join(spec.sourceRoot,'tools/i_core/release_schema6/backup_bundle.mjs')));
let report={format:'schema6-postfailure-global-pending-v1',passed:false,observedAt:new Date().toISOString(),originalSqliteOpened:false,messageContentQueried:false,privateSqliteOpened:false};
let before=null,ledger=null;
try {
 f.safe(capture,true);need(fs.readdirSync(capture).length===0,'fresh_capture_required');
 const mp=spec.launchMcp.path;need(sha(fs.readFileSync(mp))===spec.launchMcp.sha256,'mcp_configuration_changed');
 ledger=path.join(json(mp).environment.I_REMOTE_MCP_STATE_DIR,'writeback.sqlite');
 const family=()=>['','-wal','-shm','-journal'].filter(s=>fs.existsSync(ledger+s)).map(s=>({suffix:s,path:ledger+s,...f.readStable(ledger+s)}));
 before=family();
 for(const x of before){const p=path.join(capture,'writeback.sqlite'+x.suffix);fs.copyFileSync(x.path,p,fs.constants.COPYFILE_EXCL);f.safe(p);need(f.readStable(p).sha256===x.sha256,'copy_hash_mismatch')}
 need(JSON.stringify(before)===JSON.stringify(family()),'source_changed_during_capture');
 const db=new DatabaseSync(path.join(capture,'writeback.sqlite'));report.privateSqliteOpened=true;let counts;
 try{db.exec('PRAGMA query_only=ON');counts=db.prepare('SELECT status,COUNT(*) AS count FROM turns GROUP BY status ORDER BY status').all().map(x=>({status:x.status,count:Number(x.count)}))}finally{db.close()}
 need(JSON.stringify(before)===JSON.stringify(family()),'original_family_changed');
 const pending=counts.find(x=>x.status==='pending')?.count??0;
 const p0=pinnedJson(spec.baselineP0);
 report={...report,globalStatusCounts:counts,globalPending:pending,originalFamily:before,
 mainAndWalUnchangedSinceP0:['','-wal'].every(s=>before.find(x=>x.suffix===s)?.sha256===p0.ledgerFamily.find(x=>x.suffix===s)?.sha256),
 sharedMemoryChangedSinceP0:before.find(x=>x.suffix==='-shm')?.sha256!==p0.ledgerFamily.find(x=>x.suffix==='-shm')?.sha256,
 originalFamilyUnchangedDuringCapture:true,passed:pending===0};
 if(pending!==0)report.code='global_pending_nonzero';
}catch(e){report={...report,passed:false,code:String(e.code??'pending_check_rejected')}}
finally{
 try{
  f.safe(capture,true);const names=fs.readdirSync(capture);
  need(names.every(n=>['writeback.sqlite','writeback.sqlite-wal','writeback.sqlite-shm','writeback.sqlite-journal'].includes(n)),'unexpected_scratch_file');
  for(const n of names){const p=path.join(capture,n);need(path.dirname(p)===capture&&p!==ledger,'scratch_scope');f.safe(p);fs.unlinkSync(p)}
  need(fs.readdirSync(capture).length===0,'scratch_not_empty');fs.rmdirSync(capture);report.privateCaptureCleaned=true;
 }catch{report.privateCaptureCleaned=false;report.passed=false;report.cleanupCode='scratch_cleanup_unconfirmed'}
}
report.completedAt=new Date().toISOString();return report;
}

function needSwitch(ok,code){if(!ok)throw Error(code);}
const hashPattern=/^[a-f0-9]{64}$/;
function exactKeys(v,names,code){needSwitch(v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).sort().join('|')===names.slice().sort().join('|'),code);}
export function validateSwitchFacts(f){
 const {plan,policy,marker,head,event,sourceMarker,sourceHead,floor,sourceFloor,operation,supervisor,child,guardian,snapshot}=f;
 needSwitch(plan.approved===true&&plan.format==='schema6-package-switch-approved-v1'&&plan.rollbackOf===null,'switch_plan_not_approved');
 needSwitch(policy.format==='i-core-activation-package-switch-policy-v1'&&policy.evidenceMode==='reviewed-live'&&policy.fromTaskEvidence==='baseline-actual-task-xml'&&policy.toTaskEvidence==='exact-two-slot-rules-expected-only'&&policy.timeoutMs===120000,'switch_policy');
 needSwitch(plan.operationId===policy.operationId&&plan.expectedHeadSha256===policy.expectedHeadSha256&&plan.expectedMarkerSha256===policy.expectedMarkerSha256&&f.planSha256===policy.switchPlanSha256,'switch_plan_policy');
 needSwitch(f.sourceMarkerSha256===plan.expectedMarkerSha256&&f.sourceHeadSha256===plan.expectedHeadSha256&&sourceHead.generation===policy.expectedGeneration,'switch_source_anchors');
 needSwitch(plan.from.manifestSha256!==plan.to.manifestSha256&&plan.from.releaseDirectory!==plan.to.releaseDirectory&&sourceMarker.phase==='clean_closed'&&sourceMarker.manifest_sha256===plan.from.manifestSha256&&sourceMarker.configuration_sha256===plan.from.configurationSha256,'switch_from_binding');
 needSwitch(marker.phase==='clean_closed'&&marker.manifest_sha256===plan.to.manifestSha256&&marker.configuration_sha256===plan.to.configurationSha256&&marker.package_switch_plan_sha256===f.planSha256&&marker.package_switch_event_sha256===f.eventSha256,'switch_target_marker');
 needSwitch(event.operationId===plan.operationId&&event.planSha256===f.planSha256&&event.previousHeadSha256===plan.expectedHeadSha256&&event.rollbackOf===null&&JSON.stringify(event.from)===JSON.stringify(plan.from)&&JSON.stringify(event.to)===JSON.stringify(plan.to)&&JSON.stringify(event.sourceMarker)===JSON.stringify(sourceMarker),'switch_event_binding');
 needSwitch(head.generation===policy.expectedGeneration+1&&head.previousHeadSha256===plan.expectedHeadSha256&&head.receiptId===marker.token&&head.custodySha256===marker.custody_sha256&&head.databasePath===event.databasePath&&head.nodeId===marker.node_id&&event.nodeId===marker.node_id,'switch_head_binding');
 needSwitch(sourceHead.databasePath===head.databasePath&&sourceHead.nodeId===head.nodeId&&sourceHead.receiptId===sourceMarker.token&&sourceHead.custodySha256===sourceMarker.custody_sha256,'switch_source_identity');
 needSwitch(event.databaseSha256===snapshot.databaseSha256&&snapshot.databaseSha256===marker.database_sha256&&snapshot.databaseSha256===sourceMarker.database_sha256&&snapshot.stateTreeSha256===marker.state_tree_sha256&&snapshot.stateTreeSha256===sourceMarker.state_tree_sha256,'switch_business_state');
 const witness=event.businessWitness;
 exactKeys(witness,['format','sha256','tables','rows'],'switch_witness_schema');
 needSwitch(witness.format==='schema6-all-business-v1'&&typeof witness.sha256==='string'&&hashPattern.test(witness.sha256)&&Number.isSafeInteger(witness.tables)&&witness.tables>=0&&Number.isSafeInteger(witness.rows)&&witness.rows>=0,'switch_witness');
 needSwitch(floor.origin==='same_schema_package_switch'&&floor.packageSwitchEventSha256===f.eventSha256&&floor.cleanCloseReceiptId===marker.token&&floor.databaseSha256===snapshot.databaseSha256,'switch_floor');
 const stable=x=>Object.fromEntries(Object.entries(x).filter(([k])=>!['authentication','cleanCloseReceiptId','origin','packageSwitchEventSha256','databaseSha256'].includes(k)));
 needSwitch(JSON.stringify(stable(floor))===JSON.stringify(stable(sourceFloor)),'switch_floor_progress');
 needSwitch(operation.operation==='offline-package-switch'&&operation.event_sha256===f.eventSha256&&operation.head_sha256===f.headSha256&&operation.custody_generation===head.generation&&operation.target_manifest_sha256===plan.to.manifestSha256,'switch_operation_receipt');
 const r=supervisor.result;
 needSwitch(supervisor.token===marker.token&&supervisor.mode==='offline-package-switch'&&supervisor.manifest_sha256===plan.to.manifestSha256&&supervisor.guardian_receipt_confirmed===true&&supervisor.lock_released_confirmed===true&&supervisor.child_receipt_confirmed===true&&r?.child_started===true&&r.child_exit_confirmed===true&&r.child_exit_code_confirmed===true&&r.child_exit_code===0&&r.job_empty_confirmed===true&&r.guardian_started===true&&r.guardian_exit_confirmed===true&&r.guardian_exit_code_confirmed===true&&r.guardian_exit_code===0&&r.termination_requested===false,'switch_supervisor');
 needSwitch(guardian.run_id===marker.token&&guardian.result?.job_empty_confirmed===true&&guardian.result.parent_exit_observed===false,'switch_guardian');
 needSwitch(child.token===marker.token&&child.mode==='offline-package-switch'&&child.manifest_sha256===plan.to.manifestSha256&&child.phase==='clean_closed'&&child.reason==='package_switch_completed'&&child.store_construction_attempted===false&&child.store_close_confirmed===true&&child.listener_closed_confirmed===true,'switch_child');
 needSwitch(marker.supervisor?.job_empty_confirmed===true&&marker.supervisor.child_exit_code===0&&marker.supervisor.guardian_exit_code===0&&marker.supervisor.termination_requested===false,'switch_marker_supervisor');
 needSwitch(f.pendingAbsent===true&&f.sidecarsAbsent===true,'switch_pending_or_sidecar');
 return true;
}
async function postSwitch(spec){
 let keys=null;
 try{
 const plan=pinnedJson(spec.switchPlan),policy=pinnedJson(spec.switchPolicy),login=pinnedJson(spec.baselineLogin),core=pinnedJson(spec.targetCore);
 needSwitch(path.resolve(spec.switchControl)===path.join(path.resolve(spec.attemptDirectory),'package-switch-control'),'switch_control_scope');
 needSwitch(path.resolve(spec.beforeMarker.path)===path.join(path.resolve(spec.attemptDirectory),'pre-switch-marker.json')&&path.resolve(spec.beforeHead.path)===path.join(path.resolve(spec.attemptDirectory),'pre-switch-head.json'),'switch_before_scope');
 const common=await import(pathToFileURL(path.join(spec.sourceRoot,'tools/i_core/release_schema6/lifecycle/common.mjs')));
 const configuration=await import(pathToFileURL(path.join(spec.sourceRoot,'tools/i_core/release_schema6/lifecycle/configuration.mjs')));
 needSwitch(spec.targetCore.path===plan.to.configurationPath&&spec.targetCore.sha256===plan.to.configurationSha256,'switch_target_config');
 const reads=new Map();
 function read(p){const st=fs.lstatSync(p);needSwitch(st.isFile()&&!st.isSymbolicLink()&&st.nlink===1,'switch_file_identity');const b=fs.readFileSync(p);reads.set(p,b);return b;}
 const json=p=>JSON.parse(read(p).toString('utf8').replace(/^\uFEFF/,''));
 const state=login.state_directory,custody=core.recovery_custody_directory,markerPath=path.join(state,'s6-lifecycle.json'),headPath=path.join(custody,'current-head.json');
 const marker=json(markerPath),headRaw=read(headPath),headHash=digest(headRaw);
 keys=configuration.readConfiguration(spec.targetCore.path,{manifest_sha256:plan.to.manifestSha256,database_path:core.database_path,owner_sid:login.owner_sid,node_id:marker.node_id,release:plan.to.releaseDirectory,provisioned_empty:false});
 function auth(raw,format){const {authentication,...body}=JSON.parse(raw);needSwitch(typeof authentication==='string'&&hashPattern.test(authentication),'switch_auth_schema');const h=crypto.createHmac('sha256',keys.custodyKey).update('i-core-floor-custody-v1\0').update(JSON.stringify(body)).digest();needSwitch(crypto.timingSafeEqual(h,Buffer.from(authentication,'hex'))&&body.format===format,'switch_authentication');return body;}
 const head=auth(headRaw,'i-core-custody-head-v1');needSwitch(headRaw.equals(read(path.join(custody,headHash+'.head.json'))),'switch_head_copy');
 const sourceMarker=pinnedJson(spec.beforeMarker),sourceHeadRaw=read(spec.beforeHead.path);
 needSwitch(digest(sourceHeadRaw)===spec.beforeHead.sha256&&sourceHeadRaw.equals(read(path.join(custody,plan.expectedHeadSha256+'.head.json'))),'switch_predecessor_copy');
 const sourceHead=auth(sourceHeadRaw,'i-core-custody-head-v1');
 const floorRead=h=>{needSwitch(typeof h==='string'&&hashPattern.test(h),'switch_floor_hash');const b=read(path.join(custody,h+'.floor.json'));needSwitch(digest(b)===h,'switch_floor_digest');return auth(b,'i-core-floor-custody-v1')};
 const floor=floorRead(head.custodySha256),sourceFloor=floorRead(sourceHead.custodySha256);
 const eventHash=marker.package_switch_event_sha256;needSwitch(typeof eventHash==='string'&&hashPattern.test(eventHash),'switch_event_hash');
 const eventPath=path.join(custody,eventHash+'.package-switch.json'),eventRaw=read(eventPath);needSwitch(digest(eventRaw)===eventHash,'switch_event_digest');
 const event=auth(eventRaw,'i-core-package-switch-event-v1'),snapshot=common.closedStateSnapshot(state);
 const receipt=n=>json(path.join(spec.switchControl,n+'.json'));
 const facts={plan,policy,marker,head,event,sourceMarker,sourceHead,floor,sourceFloor,snapshot,planSha256:spec.switchPlan.sha256,sourceMarkerSha256:spec.beforeMarker.sha256,sourceHeadSha256:spec.beforeHead.sha256,eventSha256:eventHash,headSha256:headHash,operation:receipt('operation'),supervisor:receipt('supervisor'),child:receipt('child'),guardian:receipt('guardian'),pendingAbsent:!fs.existsSync(path.join(state,'s6-package-switch-pending.json'))&&!fs.existsSync(path.join(custody,'package-switch-pending.json')),sidecarsAbsent:['-wal','-shm','-journal'].every(s=>!fs.existsSync(core.database_path+s))};
 validateSwitchFacts(facts);
 needSwitch(JSON.stringify(snapshot)===JSON.stringify(common.closedStateSnapshot(state)),'switch_state_changed');
 for(const [p,b] of reads)needSwitch(b.equals(fs.readFileSync(p)),'switch_evidence_changed');
 return {format:'schema6-post-switch-closed-proof-v1',passed:true,custodyHmacVerified:true,planSha256:spec.switchPlan.sha256,operationId:plan.operationId,generation:head.generation,headSha256:headHash,previousHeadSha256:head.previousHeadSha256,eventSha256:eventHash,markerSha256:digest(reads.get(markerPath)),databaseSha256:snapshot.databaseSha256,stateTreeSha256:snapshot.stateTreeSha256,nodeId:head.nodeId,databasePath:head.databasePath,markerPath,headPath,eventPath,floorPath:path.join(custody,head.custodySha256+'.floor.json'),floorSha256:head.custodySha256,businessWitness:event.businessWitness,businessWitnessRecomputed:false,pendingAbsent:true,sidecarsAbsent:true,coreStateUnchangedDuringCheck:true};
 }catch{return {format:'schema6-post-switch-closed-proof-v1',passed:false,code:'post_switch_rejected'}}
 finally{keys?.custodyKey?.fill(0);keys?.backupKey?.fill(0)}
}

export async function runPreflight(spec){validate(spec);return spec.operation==='closed'?closed(spec):spec.operation==='post-switch'?postSwitch(spec):pending(spec);}
async function main(){
 try{let size=0;const chunks=[];for await(const c of process.stdin){size+=c.length;if(size>131072)throw Error('input_limit');chunks.push(c);}
 const spec=JSON.parse(Buffer.concat(chunks).toString('utf8'));const r=await runPreflight(spec);
 const summary=spec.operation==='post-switch'?r:spec.operation==='closed'?{passed:r.passed,code:r.passed?null:'closed_gate_failed',generation:r.generation,headSha256:r.headSha256,custodyHmacVerified:r.custodyHmacVerified,authenticatedHeadCount:r.authenticatedHeadCount,sourceGen10DatabaseUnchanged:r.sourceGen10DatabaseUnchanged,sourceGen10StateUnchanged:r.sourceGen10StateUnchanged,sidecarsAbsent:r.sidecarsAbsent,coreStateUnchangedDuringCheck:r.coreStateUnchangedDuringCheck}: {passed:r.passed,code:r.passed?null:'pending_gate_failed',globalPending:r.globalPending,privateCaptureCleaned:r.privateCaptureCleaned,mainAndWalUnchangedSinceP0:r.mainAndWalUnchangedSinceP0,originalFamilyUnchangedDuringCapture:r.originalFamilyUnchangedDuringCapture};
 process.stdout.write(JSON.stringify(summary));if(!r.passed)process.exitCode=2;
 }catch{process.stdout.write(JSON.stringify({passed:false,code:'preflight_rejected'}));process.exitCode=2;}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href)await main();
