// Same-schema RegisterOnly proof checks. This module never starts/stops a task,
// opens SQLite, reads a key, or authenticates a floor in place of NativeLease.
import {readFileSync,existsSync,lstatSync} from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {sha256,plainPath} from '../release_schema6/package.mjs';
import {readSwitchPlan} from '../release_schema6/package_switch.mjs';
import {validatePackageSwitchBindings} from './package-switch-bindings.mjs';
const hex=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const need=(v,c)=>{if(!v)throw Object.assign(new Error(c),{code:c});};
function bytes(ref){need(ref&&hex(ref.sha256),'registration_anchor_required');const p=plainPath(ref.path),st=lstatSync(p);need(st.isFile()&&st.nlink===1&&st.size<=16*1024*1024,'registration_file_rejected');const b=readFileSync(p);need(sha256(b)===ref.sha256,'registration_anchor_changed');return b;}
const json=ref=>JSON.parse(bytes(ref).toString('utf8').replace(/^\uFEFF/,''));
function nativeClosed(r,token,manifest,mode){
 for(const name of ['child','supervisor'])need(r[name]?.token===token&&r[name].manifest_sha256===manifest,'registration_native_binding');
 need(r.child.phase==='clean_closed'&&r.child.store_close_confirmed===true&&r.child.listener_closed_confirmed===true,'registration_native_not_closed');
 if(mode)need(r.child.mode===mode&&r.child.reason==='package_switch_completed'&&r.child.store_construction_attempted===false&&r.supervisor.mode===mode,'registration_offline_mode');
 const s=r.supervisor,g=r.guardian,x=s.result;
 for(const k of ['child_receipt_confirmed','guardian_receipt_confirmed','lock_released_confirmed'])need(s[k]===true,'registration_native_not_closed');
 for(const k of ['job_empty_confirmed','child_exit_confirmed','child_exit_code_confirmed','guardian_exit_confirmed','guardian_exit_code_confirmed'])need(x?.[k]===true,'registration_native_not_closed');
 need(x.child_exit_code===0&&x.guardian_exit_code===0&&x.termination_requested===false&&g.run_id===token&&g.result?.job_empty_confirmed===true&&g.result.parent_exit_observed===false,'registration_native_not_closed');
}
export function validateSwitchRegistrationEvidence({plan,planSha256,marker,head,event,floor,operation,offline,close,closeInput,sourceMarker,originalToken,prepare,markerSha256,headSha256,eventSha256,floorSha256}){
 need(plan.approved===true&&hex(planSha256),'registration_approval_required');
 need(close.closed===true&&close.originalHostExitConfirmed===true&&close.wmCloseOnly===true&&close.coreForced===false&&close.databaseExclusiveOpenConfirmed===true&&close.budgetMs===30000&&Number.isFinite(close.externalCloseElapsedMs)&&close.externalCloseElapsedMs>=0&&close.externalCloseElapsedMs<30000,'registration_original_close_rejected');
 need(close.manifestSha256===plan.from.manifestSha256&&close.configurationSha256===closeInput.sha256&&close.receiptSha256?.marker===plan.expectedMarkerSha256,'registration_original_close_binding');
 need(marker.format==='schema6-lifecycle-v1'&&marker.phase==='clean_closed'&&marker.manifest_sha256===plan.to.manifestSha256&&marker.configuration_sha256===plan.to.configurationSha256&&marker.package_switch_plan_sha256===planSha256&&marker.package_switch_event_sha256===eventSha256&&marker.custody_sha256===floorSha256,'registration_marker_binding');
 need(operation.operation==='offline-package-switch'&&operation.event_sha256===eventSha256&&operation.head_sha256===headSha256&&operation.target_manifest_sha256===plan.to.manifestSha256&&operation.custody_generation===head.generation,'registration_operation_binding');
 need(head.format==='i-core-custody-head-v1'&&head.custodySha256===floorSha256&&head.receiptId===marker.token&&head.databasePath===marker.database_path&&head.nodeId===marker.node_id&&hex(head.authentication),'registration_head_binding');
 need(floor.format==='i-core-floor-custody-v1'&&floor.schemaVersion===6&&floor.databasePath===marker.database_path&&floor.nodeId===marker.node_id&&floor.packageSwitchEventSha256===eventSha256&&floor.cleanCloseReceiptId===marker.token&&floor.databaseSha256===marker.database_sha256&&hex(floor.authentication),'registration_floor_binding');
 need(event.format==='i-core-package-switch-event-v1'&&event.planSha256===planSha256&&event.previousHeadSha256===plan.expectedHeadSha256&&event.databaseSha256===marker.database_sha256&&same(event.sourceMarker,sourceMarker)&&sourceMarker.token===originalToken&&sourceMarker.phase==='clean_closed'&&sourceMarker.database_sha256===marker.database_sha256&&same(event.from,plan.from)&&same(event.to,plan.to)&&event.databasePath===marker.database_path&&event.nodeId===marker.node_id&&event.sourceMarker?.manifest_sha256===plan.from.manifestSha256&&event.sourceMarker.configuration_sha256===plan.from.configurationSha256&&hex(event.authentication),'registration_event_binding');
 nativeClosed(offline,marker.token,plan.to.manifestSha256,'offline-package-switch');
 need(prepare.prepared===true&&prepare.registered===false&&prepare.started===false&&prepare.manifest_sha256===plan.to.manifestSha256&&prepare.login_configuration_sha256===plan.artifacts.find(a=>a.role==='login').sha256,'registration_prepare_binding');
 return {validated:true,registered:false,started:false,markerSha256,headSha256,eventSha256,floorSha256,nativeOfflineReceiptsBound:true,hmacRechecked:false};
}
export function validatePackageSwitchRegistration(c){
 need(c.format==='schema6-package-switch-registration-v1'&&c.approved===true&&c.registerOnly===true&&c.registerDisabled===true&&c.registrationDerivation==='fixed_prepare_settings_enabled_false_only','registration_approval_required');
 need(/^[A-Za-z0-9][A-Za-z0-9_.-]{0,180}$/.test(c.taskName??'')&&c.oldTask?.name!==c.taskName,'registration_task_name');
 const approval=json(c.humanApproval);
 const security=['registrationDerivation','registerDisabled','ownerSid','taskName','oldTask','registrationSddl','expectedRegisteredSddl','parentSddlSha256','taskSecurityPolicyVersion','inheritedReadOnlyPrincipals'];
 need(approval.format==='schema6-package-switch-registration-human-approval-v1'&&approval.action==='create_new_disabled_login_task_only'&&approval.authorized===true,'registration_human_approval');
 for(const k of security)need(same(approval[k],c[k]),'registration_human_approval');
 for(const k of ['switchPlan','targetMarker','currentHead','switchEvent','targetFloor','originalCloseInput','originalCloseReceipt','originalMarkerSnapshot','fixedPrepareReceipt','preparedXml','approvedXml','registrationXml','offline'])need(same(approval[k],c[k]),'registration_human_approval');
 const plan=readSwitchPlan(c.switchPlan.path,c.switchPlan.sha256);validatePackageSwitchBindings(plan,{fromArtifacts:plan.fromArtifacts});
 need(plan.to.releaseDirectory===c.releaseDirectory&&plan.to.manifestSha256===c.manifestSha256,'registration_release_binding');
 const oldArtifacts=Object.fromEntries(plan.fromArtifacts.map(a=>[a.role,a])),artifacts=Object.fromEntries(plan.artifacts.map(a=>[a.role,a]));
 const core=json({path:plan.to.configurationPath,sha256:plan.to.configurationSha256});
 need(core.owner_sid===c.ownerSid,'registration_owner_binding');
 const markerPath=path.join(path.dirname(core.database_path),'s6-lifecycle.json'),custody=core.recovery_custody_directory;
 need(c.targetMarker.path===markerPath&&c.currentHead.path===path.join(custody,'current-head.json'),'registration_canonical_binding');
 const marker=json(c.targetMarker),head=json(c.currentHead),sourceMarker=json(c.originalMarkerSnapshot);need(c.originalMarkerSnapshot.sha256===plan.expectedMarkerSha256,'registration_original_marker_changed');
 need(c.switchEvent.path===path.join(custody,c.switchEvent.sha256+'.package-switch.json')&&c.targetFloor.path===path.join(custody,c.targetFloor.sha256+'.floor.json'),'registration_canonical_binding');
 for(const p of [path.join(path.dirname(core.database_path),'s6-package-switch-pending.json'),path.join(custody,'package-switch-pending.json')])need(!existsSync(p),'registration_pending');
 const close=json(c.originalCloseReceipt),closeInput=json(c.originalCloseInput);
 need(closeInput.format==='schema6-session-close-approved-v1'&&closeInput.approved===true&&closeInput.manifestSha256===plan.from.manifestSha256&&closeInput.loginConfigurationPath===oldArtifacts.login.path&&closeInput.loginConfigurationSha256===oldArtifacts.login.sha256,'registration_original_close_binding');
 // The approved close input must identify the same reviewed helper closure.
 for(const [name,key] of [['close-schema6-session.ps1','maintenanceScriptSha256'],['process_image_binding.ps1','processImageBindingSha256']]){
  const listed=c.maintenanceFiles.find(f=>path.basename(f.path)===name);need(listed&&listed.sha256===closeInput[key],'registration_original_close_source');
 }
 const original={};for(const name of ['child','guardian','supervisor','close','exit']){const p=path.join(name==='exit'?closeInput.sessionDirectory:closeInput.controlDirectory,name==='close'?'session-close.json':name==='exit'?'session-exit.json':name+'.json');original[name]=json({path:p,sha256:close.receiptSha256[name]});}
 nativeClosed(original,original.child.token,plan.from.manifestSha256);
 need(original.close.clean_closed===true&&original.close.completion_confirmed===true&&original.close.core_forced===false&&original.close.manifest_sha256===plan.from.manifestSha256,'registration_original_close_binding');
 for(const k of ['clean_closed','core_job_empty_confirmed','backup_job_empty_confirmed','mcp_job_empty_confirmed','mcp_owned_tree_handles_released_confirmed'])need(original.exit[k]===true,'registration_original_close_binding');
 need(original.exit.forced_timeout===false&&original.exit.termination_requested===false,'registration_original_close_binding');
 const offline=Object.fromEntries(['launch','child','guardian','supervisor','operation'].map(k=>[k,json(c.offline[k])]));
 const control=path.dirname(c.offline.launch.path);
 for(const k of Object.keys(offline))need(c.offline[k].path===path.join(control,k+'.json'),'registration_offline_path');
 need(offline.launch.token===marker.token&&offline.launch.manifest_sha256===c.manifestSha256&&offline.launch.release===c.releaseDirectory&&offline.launch.configuration_file===plan.to.configurationPath&&offline.launch.state===path.dirname(core.database_path)&&offline.launch.package_switch_plan===c.switchPlan.path&&offline.launch.package_switch_sha256===c.switchPlan.sha256,'registration_offline_binding');
 need(bytes(c.preparedXml).equals(bytes(c.approvedXml))&&bytes(c.preparedXml).equals(bytes(artifacts.task)),'registration_prepare_xml_changed');
 bytes(c.registrationXml);bytes(c.oldTask.xml);need(sha256(c.oldTask.sddl)===c.oldTask.sddlSha256,'registration_old_task_sddl');
 const result=validateSwitchRegistrationEvidence({plan,planSha256:c.switchPlan.sha256,marker,head,event:json(c.switchEvent),floor:json(c.targetFloor),operation:offline.operation,offline,close,closeInput:c.originalCloseInput,sourceMarker,originalToken:original.child.token,prepare:json(c.fixedPrepareReceipt),markerSha256:c.targetMarker.sha256,headSha256:c.currentHead.sha256,eventSha256:c.switchEvent.sha256,floorSha256:c.targetFloor.sha256});
 return {...result,databasePath:core.database_path,databaseSha256:marker.database_sha256,stateDirectory:path.dirname(core.database_path),custodyDirectory:custody,oldXmlPath:oldArtifacts.task.path,newBackupPath:artifacts.backup.path};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
 try{need(process.argv.length===4,'registration_usage');const p=process.argv[2],hash=process.argv[3];const c=json({path:p,sha256:hash});process.stdout.write(JSON.stringify(validatePackageSwitchRegistration(c))+'\n');}
 catch{process.stdout.write(JSON.stringify({validated:false,registered:false,started:false,code:'package_switch_registration_rejected'})+'\n');process.exitCode=2;}
}
