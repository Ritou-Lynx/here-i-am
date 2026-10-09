// RegisterOnly for a reviewed MCP configuration chain. Core bytes and custody stay unchanged.
// Only hashes closed-state bytes. Never opens SQLite, parses state contents, reads independent credentials, or acquires a NativeLease.
import {readFileSync,existsSync,lstatSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {sha256,plainPath,INVENTORY} from '../release_schema6/package.mjs';
import {closedStateSnapshot} from '../release_schema6/lifecycle/common.mjs';
import {validateMcpConfigSwitch} from './mcp-config-switch-bindings.mjs';
const hex=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const canonical=x=>Array.isArray(x)?x.map(canonical):x&&typeof x==='object'?Object.fromEntries(Object.keys(x).sort().map(k=>[k,canonical(x[k])])):x;
const same=(a,b)=>JSON.stringify(canonical(a))===JSON.stringify(canonical(b));
const need=(v,c)=>{if(!v)throw Object.assign(new Error('mcp_registration_'+c),{code:'mcp_registration_'+c});};
function bytes(ref){need(ref&&same(Object.keys(ref).sort(),['path','sha256'])&&hex(ref.sha256),'anchor_required');const p=plainPath(ref.path),st=lstatSync(p);need(st.isFile()&&st.nlink===1&&st.size<=16*1024*1024,'file_rejected');const b=readFileSync(p);need(sha256(b)===ref.sha256,'anchor_changed');return b;}
const ref=a=>({path:a.path,sha256:a.sha256});
const json=r=>JSON.parse(bytes(r).toString('utf8').replace(/^\uFEFF/,''));
const maintained=['register-mcp-config-switch-login.ps1','mcp-config-switch-registration.mjs','mcp-config-switch-bindings.mjs','register_task_primitives.ps1','task_security_policy.ps1','owned_artifacts.ps1','close-schema6-session.ps1','process_image_binding.ps1'];
export const MCP_REGISTRATION_SOURCES=Object.freeze([...INVENTORY.filter(p=>p!=='runtime/node.exe'),...maintained.map(p=>'tools/i_core/maintenance/'+p)].sort());
export const MCP_REGISTRATION_FIELDS=Object.freeze(['format','approved','registerOnly','registerDisabled','registrationDerivation','ownerSid','taskName','oldTask','registrationSddl','expectedRegisteredSddl','parentSddlSha256','taskSecurityPolicyVersion','inheritedReadOnlyPrincipals','releaseDirectory','manifestSha256','proposal','closedMarker','currentHead','originalCloseInput','originalCloseReceipt','mcpStart','fixedPrepareReceipt','preparedXml','approvedXml','registrationXml','maintenanceFiles','registrationReceiptPath','humanApproval']);
export function validateMcpRegistrationApproval(c,approval){
 need(c&&same(Object.keys(c).sort(),[...MCP_REGISTRATION_FIELDS].sort()),'configuration_shape');
 need(c.format==='schema6-mcp-config-switch-registration-v1'&&c.approved===true&&c.registerOnly===true&&c.registerDisabled===true&&c.registrationDerivation==='fixed_prepare_settings_enabled_false_only','approval_required');
 need(/^[A-Za-z0-9][A-Za-z0-9_.-]{0,180}$/.test(c.taskName??'')&&/^[A-Za-z0-9][A-Za-z0-9_.-]{0,180}$/.test(c.oldTask?.name??'')&&c.oldTask.name.toLowerCase()!==c.taskName.toLowerCase(),'task_name');
 const {format,humanApproval,...approved}=c;
 need(same(approval,{...approved,format:'schema6-mcp-config-switch-registration-human-approval-v1',action:'create_new_disabled_login_task_only',authorized:true}),'human_approval');
}
// Pure evidence verifier: a fixture may exercise this function, but production always
// obtains all inputs via the pinned wrapper and validateMcpConfigSwitchRegistration.
export function validateMcpRegistrationEvidence({proposal,core,marker,head,markerSha256,close,closeInput,closeInputSha256,original,launch,ready,mcpStart,mcpStop,prepare}){
 const end=proposal.core;
 need(close.format==='schema6-approved-session-close-v1'&&close.closed===true&&close.originalHostExitConfirmed===true&&close.wmCloseOnly===true&&close.coreForced===false&&close.databaseExclusiveOpenConfirmed===true&&close.budgetMs===30000&&Number.isFinite(close.externalCloseElapsedMs)&&close.externalCloseElapsedMs>=0&&close.externalCloseElapsedMs<30000,'original_close_rejected');
 need(close.manifestSha256===end.manifestSha256&&close.configurationSha256===closeInputSha256&&close.receiptSha256?.marker===markerSha256,'original_close_binding');
 need(marker.format==='schema6-lifecycle-v1'&&marker.phase==='clean_closed'&&marker.manifest_sha256===end.manifestSha256&&marker.configuration_sha256===end.configurationSha256&&marker.database_path===core.database_path&&marker.node_id===core.node_id&&hex(marker.database_sha256)&&hex(marker.custody_sha256)&&hex(marker.token)&&hex(marker.state_tree_sha256),'marker_binding');
 need(head.format==='i-core-custody-head-v1'&&head.custodySha256===marker.custody_sha256&&head.receiptId===marker.token&&head.databasePath===marker.database_path&&head.nodeId===marker.node_id&&Number.isSafeInteger(head.generation)&&head.generation>=1&&hex(head.authentication),'head_binding');
 need(launch.token===marker.token&&launch.manifest_sha256===end.manifestSha256&&launch.release===end.releaseDirectory&&launch.configuration_file===end.configurationPath&&launch.state===path.dirname(core.database_path)&&ready.token===marker.token&&ready.manifest_sha256===end.manifestSha256&&ready.configuration_sha256===end.configurationSha256,'launch_binding');
 need(marker.supervisor?.job_empty_confirmed===true&&marker.supervisor.child_exit_code===0&&marker.supervisor.guardian_exit_code===0&&marker.supervisor.termination_requested===false,'marker_supervisor');
 for(const k of ['child','supervisor'])need(original[k]?.token===marker.token&&original[k].manifest_sha256===end.manifestSha256,'native_binding');
 const child=original.child,s=original.supervisor,g=original.guardian,x=s.result;
 need(child.phase==='clean_closed'&&child.store_close_confirmed===true&&child.listener_closed_confirmed===true&&child.mode==='start'&&child.store_construction_attempted===true&&launch.mode==='start'&&s.mode==='start','native_not_closed');
 for(const k of ['child_receipt_confirmed','guardian_receipt_confirmed','lock_released_confirmed'])need(s[k]===true,'native_not_closed');
 for(const k of ['job_empty_confirmed','child_exit_confirmed','child_exit_code_confirmed','guardian_exit_confirmed','guardian_exit_code_confirmed'])need(x?.[k]===true,'native_not_closed');
 need(x.child_exit_code===0&&x.guardian_exit_code===0&&x.termination_requested===false&&g.run_id===marker.token&&g.result?.job_empty_confirmed===true&&g.result.parent_exit_observed===false,'native_not_closed');
 need(original.close.clean_closed===true&&original.close.completion_confirmed===true&&original.close.core_forced===false&&original.close.database_exclusive_open_confirmed===true,'close_binding');
 for(const r of [original.close,original.exit])need(r.manifest_sha256===end.manifestSha256&&r.budget_ms===30000&&Number.isFinite(r.elapsed_ms)&&r.elapsed_ms>=0&&r.elapsed_ms<30000,'close_budget');
 for(const k of ['clean_closed','core_job_empty_confirmed','backup_job_empty_confirmed','mcp_job_empty_confirmed','mcp_owned_tree_handles_released_confirmed'])need(original.exit[k]===true,'exit_binding');
 need(original.exit.forced_timeout===false&&original.exit.termination_requested===false&&original.exit.mcp_failure===false,'exit_binding');
 need(mcpStart.core_token===marker.token&&mcpStart.manifest_sha256===end.manifestSha256&&mcpStart.core_ready_bound===true&&mcpStart.core_pid===ready.pid&&Number.isInteger(mcpStart.pid)&&mcpStart.pid>0&&mcpStart.pid===mcpStop.pid&&mcpStart.started_ticks===mcpStop.started_ticks&&mcpStop.scope==='owned_mcp_job_only'&&mcpStop.database_path===core.database_path&&mcpStop.mcp_failure===false,'mcp_binding');
 for(const k of ['job_empty_confirmed','process_exit_confirmed','owned_tree_handles_released_confirmed'])need(mcpStop[k]===true,'mcp_not_closed');
 need(closeInput.format==='schema6-session-close-approved-v1'&&closeInput.approved===true&&closeInput.releaseDirectory===end.releaseDirectory&&closeInput.manifestSha256===end.manifestSha256,'close_input');
 need(prepare.prepared===true&&prepare.registered===false&&prepare.started===false&&prepare.manifest_sha256===end.manifestSha256&&prepare.login_configuration_sha256===proposal.toArtifacts.find(a=>a.role==='login').sha256,'prepare_binding');
 return {validated:true,registered:false,started:false,coreUnchanged:true,custodyUnchanged:true,originalCloseReceiptsBound:true,hmacRechecked:false};
}
export function validateMcpClosedState(snapshot,marker){
 need(snapshot.stateTreeSha256===marker.state_tree_sha256&&snapshot.databaseSha256===marker.database_sha256,'closed_state_changed');
 return true;
}
export function validateMcpConfigSwitchRegistration(c){
 validateMcpRegistrationApproval(c,json(c.humanApproval));
 const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..');
 need(Array.isArray(c.maintenanceFiles)&&same(c.maintenanceFiles.map(f=>f.path).sort(),MCP_REGISTRATION_SOURCES.map(f=>path.join(root,f)).sort()),'maintenance_inventory');
 for(const f of c.maintenanceFiles)bytes(f);
 const proposal=json(c.proposal);validateMcpConfigSwitch(proposal);
 const end=proposal.core;need(end.releaseDirectory===c.releaseDirectory&&end.manifestSha256===c.manifestSha256&&proposal.oldTaskName===c.oldTask.name&&proposal.newTaskName===c.taskName,'proposal_binding');
 const core=json({path:end.configurationPath,sha256:end.configurationSha256});need(core.owner_sid===c.ownerSid,'owner_binding');
 const oldArtifacts=Object.fromEntries(proposal.fromArtifacts.map(a=>[a.role,a])),artifacts=Object.fromEntries(proposal.toArtifacts.map(a=>[a.role,a]));
 const oldLogin=json(ref(oldArtifacts.login));
 need(c.closedMarker.path===path.join(path.dirname(core.database_path),'s6-lifecycle.json')&&c.currentHead.path===path.join(core.recovery_custody_directory,'current-head.json'),'canonical_binding');
 for(const p of [path.join(path.dirname(core.database_path),'s6-package-switch-pending.json'),path.join(core.recovery_custody_directory,'package-switch-pending.json')])need(!existsSync(p),'pending');
 const close=json(c.originalCloseReceipt),ci=json(c.originalCloseInput);
 need(ci.loginConfigurationPath===oldArtifacts.login.path&&ci.loginConfigurationSha256===oldArtifacts.login.sha256&&ci.outputPath===c.originalCloseReceipt.path&&ci.host?.ownerSid===c.ownerSid&&path.dirname(ci.sessionDirectory)===oldLogin.control_root&&path.dirname(ci.controlDirectory)===ci.sessionDirectory,'original_close_binding');
 need(!existsSync(path.join(ci.sessionDirectory,'session-exit-over-budget.json')),'close_budget');
 for(const [name,key] of [['close-schema6-session.ps1','maintenanceScriptSha256'],['process_image_binding.ps1','processImageBindingSha256']])need(c.maintenanceFiles.find(f=>path.basename(f.path)===name)?.sha256===ci[key],'close_source');
 const original={};for(const name of ['child','guardian','supervisor','close','exit']){const p=path.join(name==='exit'?ci.sessionDirectory:ci.controlDirectory,name==='close'?'session-close.json':name==='exit'?'session-exit.json':name+'.json');original[name]=json({path:p,sha256:close.receiptSha256?.[name]});}
 const launch=json({path:path.join(ci.controlDirectory,'launch.json'),sha256:ci.launchSha256}),ready=json({path:path.join(ci.controlDirectory,'ready.json'),sha256:ci.readySha256});
 need(c.mcpStart.path===path.join(ci.controlDirectory,'mcp-start.json'),'mcp_path');
 const mcpStart=json(c.mcpStart),mcpStop=json({path:path.join(ci.controlDirectory,'mcp-stop.json'),sha256:close.receiptSha256?.mcpStop});
 need(bytes(c.preparedXml).equals(bytes(c.approvedXml))&&bytes(c.preparedXml).equals(bytes(ref(artifacts.task))),'prepare_xml_changed');
 bytes(c.registrationXml);bytes(c.oldTask.xml);need(sha256(c.oldTask.sddl)===c.oldTask.sddlSha256,'old_task_sddl');
 const result=validateMcpRegistrationEvidence({proposal,core,marker:json(c.closedMarker),head:json(c.currentHead),markerSha256:c.closedMarker.sha256,close,closeInput:ci,closeInputSha256:c.originalCloseInput.sha256,original,launch,ready,mcpStart,mcpStop,prepare:json(c.fixedPrepareReceipt)});
 const marker=json(c.closedMarker),snapshot=closedStateSnapshot(path.dirname(core.database_path));
 validateMcpClosedState(snapshot,marker);
 return {...result,stateTreeSha256:snapshot.stateTreeSha256,databasePath:core.database_path,databaseSha256:marker.database_sha256,stateDirectory:path.dirname(core.database_path),custodyDirectory:core.recovery_custody_directory,oldXmlPath:oldArtifacts.task.path,newBackupPath:artifacts.backup.path};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
 try{need(process.argv.length===4,'usage');const c=json({path:process.argv[2],sha256:process.argv[3]});process.stdout.write(JSON.stringify(validateMcpConfigSwitchRegistration(c))+'\n');}
 catch{process.stdout.write(JSON.stringify({validated:false,registered:false,started:false,code:'mcp_config_switch_registration_rejected'})+'\n');process.exitCode=2;}
}
