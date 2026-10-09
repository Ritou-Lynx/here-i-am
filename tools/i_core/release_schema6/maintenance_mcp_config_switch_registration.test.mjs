import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync,writeFileSync,mkdtempSync,mkdirSync,rmSync,copyFileSync,renameSync,existsSync} from 'node:fs';
import {closedStateSnapshot} from './lifecycle/common.mjs';
import {execFileSync,spawnSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {sha256,cleanEnvironment} from './package.mjs';
import {backupFilePrimitives as backupFiles} from './backup_bundle.mjs';
import {generateMcpConfigSwitch,finalizeMcpConfigSwitch} from '../maintenance/generate-mcp-config-switch.mjs';
import {staticRegistrationFixture} from '../test_fixtures/release_schema6/mcp_config_switch_registration_e2e.mjs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {validateMcpRegistrationApproval,validateMcpRegistrationEvidence,validateMcpClosedState,MCP_REGISTRATION_FIELDS,MCP_REGISTRATION_SOURCES} from '../maintenance/mcp-config-switch-registration.mjs';
const H='a'.repeat(64),N='b'.repeat(64),T='c'.repeat(64),C='d'.repeat(64);
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..');
function evidence(){
 const database=path.join(root,'synthetic-i-core.sqlite'),core={database_path:database,node_id:'synthetic-node'};
 const proposal={core:{releaseDirectory:path.join(root,'synthetic-release'),manifestSha256:H,configurationPath:path.join(root,'synthetic-core.json'),configurationSha256:N},toArtifacts:[{role:'login',sha256:C}]};
 const marker={format:'schema6-lifecycle-v1',phase:'clean_closed',token:T,database_path:database,node_id:core.node_id,database_sha256:H,state_tree_sha256:N,custody_sha256:C,manifest_sha256:H,configuration_sha256:N,supervisor:{job_empty_confirmed:true,child_exit_code:0,guardian_exit_code:0,termination_requested:false}};
 const head={format:'i-core-custody-head-v1',generation:7,custodySha256:C,receiptId:T,databasePath:database,nodeId:core.node_id,authentication:H};
 const result={job_empty_confirmed:true,child_exit_confirmed:true,child_exit_code_confirmed:true,guardian_exit_confirmed:true,guardian_exit_code_confirmed:true,child_exit_code:0,guardian_exit_code:0,termination_requested:false};
 const original={child:{mode:'start',token:T,manifest_sha256:H,phase:'clean_closed',store_construction_attempted:true,store_close_confirmed:true,listener_closed_confirmed:true},supervisor:{mode:'start',token:T,manifest_sha256:H,child_receipt_confirmed:true,guardian_receipt_confirmed:true,lock_released_confirmed:true,result},guardian:{run_id:T,result:{job_empty_confirmed:true,parent_exit_observed:false}},close:{clean_closed:true,completion_confirmed:true,core_forced:false,database_exclusive_open_confirmed:true,manifest_sha256:H,budget_ms:30000,elapsed_ms:123},exit:{clean_closed:true,core_job_empty_confirmed:true,backup_job_empty_confirmed:true,mcp_job_empty_confirmed:true,mcp_owned_tree_handles_released_confirmed:true,forced_timeout:false,termination_requested:false,mcp_failure:false,manifest_sha256:H,budget_ms:30000,elapsed_ms:321}};
 const launch={mode:'start',token:T,manifest_sha256:H,release:proposal.core.releaseDirectory,configuration_file:proposal.core.configurationPath,state:path.dirname(database)},ready={pid:40,token:T,manifest_sha256:H,configuration_sha256:N};
 const mcpStart={core_token:T,manifest_sha256:H,core_ready_bound:true,core_pid:40,pid:41,started_ticks:'synthetic-ticks'},mcpStop={pid:41,started_ticks:'synthetic-ticks',scope:'owned_mcp_job_only',database_path:database,mcp_failure:false,job_empty_confirmed:true,process_exit_confirmed:true,owned_tree_handles_released_confirmed:true};
 const closeInput={format:'schema6-session-close-approved-v1',approved:true,releaseDirectory:proposal.core.releaseDirectory,manifestSha256:H};
 const close={format:'schema6-approved-session-close-v1',closed:true,originalHostExitConfirmed:true,wmCloseOnly:true,coreForced:false,databaseExclusiveOpenConfirmed:true,budgetMs:30000,externalCloseElapsedMs:1000,manifestSha256:H,configurationSha256:N,receiptSha256:{marker:C}};
 return {proposal,core,marker,head,markerSha256:C,close,closeInput,closeInputSha256:N,original,launch,ready,mcpStart,mcpStop,prepare:{prepared:true,registered:false,started:false,manifest_sha256:H,login_configuration_sha256:C}};
}
test('same-Core RegisterOnly validates the linked six terminal receipts without an offline switch',()=>{
 assert.deepEqual(validateMcpRegistrationEvidence(evidence()),{validated:true,registered:false,started:false,coreUnchanged:true,custodyUnchanged:true,originalCloseReceiptsBound:true,hmacRechecked:false});
});
const mutations={
 'missing original host exit':x=>x.close.originalHostExitConfirmed=false,
 'missing exclusive close proof':x=>x.close.databaseExclusiveOpenConfirmed=false,
 'wrong close input hash':x=>x.close.configurationSha256=H,
 'close marker hash changed':x=>x.close.receiptSha256.marker=N,
 'over-budget host':x=>x.close.externalCloseElapsedMs=30000,
 'negative close time':x=>x.close.externalCloseElapsedMs=-1,
 'different Core manifest':x=>x.marker.manifest_sha256=N,
 'different Core configuration':x=>x.marker.configuration_sha256=H,
 'different database':x=>x.marker.database_path='other',
 'different node':x=>x.marker.node_id='other',
 'marker opening':x=>x.marker.phase='opening',
 'marker supervisor nonempty':x=>x.marker.supervisor.job_empty_confirmed=false,
 'marker forced':x=>x.marker.supervisor.termination_requested=true,
 'head from other session':x=>x.head.receiptId=H,
 'different custody digest':x=>x.head.custodySha256=H,
 'head wrong node':x=>x.head.nodeId='other',
 'head missing authentication':x=>delete x.head.authentication,
 'launch other configuration':x=>x.launch.configuration_file='other',
 'ready other configuration':x=>x.ready.configuration_sha256=H,
 'child not closed':x=>x.original.child.phase='recovery_required',
 'child listener open':x=>x.original.child.listener_closed_confirmed=false,
 'child never opened store':x=>x.original.child.store_construction_attempted=false,
 'offline operation cannot substitute online close':x=>x.original.child.mode='offline-package-switch',
 'supervisor old token':x=>x.original.supervisor.token=N,
 'supervisor termination':x=>x.original.supervisor.result.termination_requested=true,
 'guardian nonempty':x=>x.original.guardian.result.job_empty_confirmed=false,
 'guardian wrong run':x=>x.original.guardian.run_id=H,
 'session close exclusive missing':x=>x.original.close.database_exclusive_open_confirmed=false,
 'session close over budget':x=>x.original.close.elapsed_ms=30000,
 'exit manifest absent':x=>delete x.original.exit.manifest_sha256,
 'exit MCP owned handles remain':x=>x.original.exit.mcp_owned_tree_handles_released_confirmed=false,
 'exit backup job remains':x=>x.original.exit.backup_job_empty_confirmed=false,
 'MCP failure':x=>x.original.exit.mcp_failure=true,
 'MCP start other core':x=>x.mcpStart.core_pid=999,
 'MCP stop different instance':x=>x.mcpStop.started_ticks='other',
 'MCP stop job remains':x=>x.mcpStop.job_empty_confirmed=false,
 'MCP stop scope broadened':x=>x.mcpStop.scope='all_processes',
 'MCP stop different database':x=>x.mcpStop.database_path='other',
 'close input not approved':x=>x.closeInput.approved=false,
 'prepare wrong login':x=>x.prepare.login_configuration_sha256=H,
 'prepare already started':x=>x.prepare.started=true,
};
for(const [name,mutate] of Object.entries(mutations))test('rejects '+name,()=>{const x=evidence();mutate(x);assert.throws(()=>validateMcpRegistrationEvidence(x));});
for(const key of ['child','guardian','supervisor','close','exit'])test('rejects missing terminal '+key,()=>{const x=evidence();delete x.original[key];assert.throws(()=>validateMcpRegistrationEvidence(x));});
function approvalPair(){
 const config=Object.fromEntries(MCP_REGISTRATION_FIELDS.map(k=>[k,{path:'synthetic-'+k,sha256:H}]));
 Object.assign(config,{format:'schema6-mcp-config-switch-registration-v1',approved:true,registerOnly:true,registerDisabled:true,registrationDerivation:'fixed_prepare_settings_enabled_false_only',taskName:'Synthetic-New',oldTask:{name:'Synthetic-Old'}});
 const {format,humanApproval,...rest}=config;
 return {config,approval:{...rest,format:'schema6-mcp-config-switch-registration-human-approval-v1',action:'create_new_disabled_login_task_only',authorized:true}};
}
test('human approval binds every config field except its own hash',()=>{
 const {config,approval}=approvalPair();validateMcpRegistrationApproval(config,approval);
 for(const key of MCP_REGISTRATION_FIELDS.filter(k=>!['format','humanApproval'].includes(k))){const changed=structuredClone(config);changed[key]='changed';assert.throws(()=>validateMcpRegistrationApproval(changed,approval),key);}
 for(const extra of ['offline','switchEvent','targetFloor','switchPlan'])assert.throws(()=>validateMcpRegistrationApproval({...config,[extra]:{}},approval));
 const sameTask=structuredClone(config);sameTask.oldTask.name='synthetic-new';assert.throws(()=>validateMcpRegistrationApproval(sameTask,approval));
});
test('wrapper pins exactly the module source closure before imports and creates only disabled tasks',()=>{
 const source=readFileSync(new URL('../maintenance/register-mcp-config-switch-login.ps1',import.meta.url),'utf8');
 const required=source.match(/\$required=@\((.*?)\)\|ForEach-Object/s)[1];
 const paths=[...required.matchAll(/'([^']+)'/g)].map(x=>x[1]).sort();assert.deepEqual(paths,[...MCP_REGISTRATION_SOURCES]);
 assert.doesNotMatch(source,/freeze-legacy|prepare-production-login|\.Run(?:Ex)?\(|\.DeleteTask\(|config\.offline|config\.switchEvent|targetFloor|NativeLease\(/);
 assert.ok(source.indexOf('foreach($entry in $config.maintenanceFiles){Pin-Ref $entry}')<source.indexOf('. (Join-Path $PSScriptRoot'));
 assert.ok(source.indexOf('$gate=Invoke-SwitchRegistrationValidator')<source.indexOf('New-ApprovedTask $service'));
 for(const term of ['shortcut-mail-relay.runtime.lock','custody.lock','Assert-BackupPrivateAcl','Assert-OldPackageTask','$expected.Settings.Enabled=$false','$registered.Enabled=$false','Assert-TaskSecurityPolicy','Assert-RegisteredTask','FileAccess]::Read,[IO.FileShare]::None'])assert.ok(source.includes(term),term);
});
test('RegisterOnly PowerShell syntax parses', {skip:process.platform!=='win32'},()=>{
 const file=path.join(root,'tools/i_core/maintenance/register-mcp-config-switch-login.ps1');
 const command="$t=$null;$e=$null;$null=[Management.Automation.Language.Parser]::ParseFile('"+file.replaceAll("'","''")+"',[ref]$t,[ref]$e);if($e.Count){throw ($e|Out-String)}";
 execFileSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',command],{windowsHide:true});
});
test('real COM uses CREATE-only disabled nonce tasks with dual security readback', {skip:process.platform!=='win32'||process.env.SCHEMA6_SYNTHETIC_TASK_TEST!=='1',timeout:90000},()=>{
 const out=execFileSync('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(root,'tools/i_core/test_fixtures/release_schema6/mcp_config_switch_registration.ps1'),'-SourceRoot',root],{encoding:'utf8',windowsHide:true,timeout:85000});
 const result=JSON.parse(out.trim());assert.equal(result.passed,true);assert.equal(result.created,2);assert.equal(result.cleaned,2);assert.equal(result.started,false);assert.equal(result.existingRejected,true);assert.equal(result.changedActionRejected,true);assert.equal(result.inventoryProfiles,true);
});

test('closed state tree drift is rejected without parsing state files or opening SQLite',()=>{
 const parent=path.join(root,'build');mkdirSync(parent,{recursive:true});const dir=mkdtempSync(path.join(parent,'mcp-reg-state-'));
 try{
  writeFileSync(path.join(dir,'i-core.sqlite'),'synthetic raw bytes, not a SQLite database');
  writeFileSync(path.join(dir,'ledger.bin'),'synthetic ledger');
  writeFileSync(path.join(dir,'s6-lifecycle.json'),'synthetic excluded marker');
  writeFileSync(path.join(dir,'shortcut-mail-relay.runtime.lock'),'synthetic excluded lock');
  const initial=closedStateSnapshot(dir),marker={state_tree_sha256:initial.stateTreeSha256,database_sha256:initial.databaseSha256};
  assert.equal(validateMcpClosedState(initial,marker),true);
  writeFileSync(path.join(dir,'ledger.bin'),'changed ledger');
  assert.throws(()=>validateMcpClosedState(closedStateSnapshot(dir),marker),/closed_state_changed/);
  writeFileSync(path.join(dir,'ledger.bin'),'synthetic ledger');
  writeFileSync(path.join(dir,'i-core.sqlite'),'changed raw database bytes');
  assert.throws(()=>validateMcpClosedState(closedStateSnapshot(dir),marker),/closed_state_changed/);
 }finally{assert.ok(path.resolve(dir).startsWith(path.resolve(parent)+path.sep+'mcp-reg-state-'));rmSync(dir,{recursive:true,force:true});}
});


test('complete RegisterOnly wrapper: private synthetic proof, locks, XML, CREATE and pre-create denials', {skip:process.platform!=='win32'||process.env.SCHEMA6_SYNTHETIC_TASK_TEST!=='1',timeout:180000},async t=>{
 const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
 const sid=execFileSync(ps,['-NoProfile','-NonInteractive','-Command','[Security.Principal.WindowsIdentity]::GetCurrent().User.Value'],{encoding:'utf8',windowsHide:true}).trim();
 const f=staticRegistrationFixture(t,sid),nonce=randomUUID().replaceAll('-','');
 f.input.oldTaskName='HereIAm-Synthetic-McpFull-'+nonce+'-Old';f.input.newTaskName='HereIAm-Synthetic-McpFull-'+nonce+'-New';
 backupFiles.protect(f.core.releaseDirectory);
 const out=generateMcpConfigSwitch(f.input),staticInputs=JSON.parse(readFileSync(out.staticInputsPath));
 // Synthetic fixed-Prepare evidence; the XML is the exact fixed-release template.
 // This fixture tests registration, never claims a real Native session close.
 copyFileSync(staticInputs.reviewXml.path,out.outputXmlPath);
 const finalized=finalizeMcpConfigSwitch(staticInputs),proposal=JSON.parse(readFileSync(finalized.proposalPath));
 const fileHash=p=>sha256(readFileSync(p)),ref=p=>({path:p,sha256:fileHash(p)}),put=(p,v)=>writeFileSync(p,typeof v==='string'?v:JSON.stringify(v));
 const sourceRoot=path.join(f.root,'registration-source');mkdirSync(sourceRoot);backupFiles.protect(sourceRoot);
 const maintenanceFiles=MCP_REGISTRATION_SOURCES.map(relative=>{const target=path.join(sourceRoot,relative);mkdirSync(path.dirname(target),{recursive:true});copyFileSync(path.join(root,relative),target);return ref(target);});
 const state=path.dirname(f.c.database_path),custody=f.c.recovery_custody_directory,session=path.join(f.l.control_root,'synthetic-session'),control=path.join(session,'synthetic-control');
 for(const directory of [state,custody,control,path.join(f.root,'private')])mkdirSync(directory,{recursive:true});
 put(f.c.database_path,'SYNTHETIC RAW BYTES: not an SQLite database');put(path.join(state,'ledger.bin'),'synthetic ledger');
 put(path.join(state,'shortcut-mail-relay.runtime.lock'),'');put(path.join(custody,'custody.lock'),'');
 const snapshot=closedStateSnapshot(state),token='e'.repeat(64),manifest=f.core.manifestSha256;
 const marker={format:'schema6-lifecycle-v1',phase:'clean_closed',token,database_path:f.c.database_path,node_id:f.c.node_id,database_sha256:snapshot.databaseSha256,state_tree_sha256:snapshot.stateTreeSha256,custody_sha256:H,manifest_sha256:manifest,configuration_sha256:f.core.configurationSha256,supervisor:{job_empty_confirmed:true,child_exit_code:0,guardian_exit_code:0,termination_requested:false}};
 const markerPath=path.join(state,'s6-lifecycle.json');put(markerPath,marker);
 const headPath=path.join(custody,'current-head.json');put(headPath,{format:'i-core-custody-head-v1',generation:7,custodySha256:H,receiptId:token,databasePath:f.c.database_path,nodeId:f.c.node_id,authentication:H});
 const native=evidence().original;for(const r of [native.child,native.supervisor]){r.token=token;r.manifest_sha256=manifest;}native.guardian.run_id=token;native.close.manifest_sha256=manifest;native.exit.manifest_sha256=manifest;
 const terminal={};for(const name of ['child','guardian','supervisor','close','exit']){const target=path.join(name==='exit'?session:control,name==='close'?'session-close.json':name==='exit'?'session-exit.json':name+'.json');put(target,native[name]);terminal[name]=target;}
 const launchPath=path.join(control,'launch.json'),readyPath=path.join(control,'ready.json');
 put(launchPath,{mode:'start',token,manifest_sha256:manifest,release:f.core.releaseDirectory,configuration_file:f.core.configurationPath,state});
 put(readyPath,{token,pid:42,manifest_sha256:manifest,configuration_sha256:f.core.configurationSha256});
 const mcpStart=path.join(control,'mcp-start.json'),mcpStop=path.join(control,'mcp-stop.json');
 put(mcpStart,{core_token:token,manifest_sha256:manifest,core_ready_bound:true,core_pid:42,pid:43,started_ticks:'synthetic-ticks'});
 put(mcpStop,{pid:43,started_ticks:'synthetic-ticks',scope:'owned_mcp_job_only',database_path:f.c.database_path,mcp_failure:false,job_empty_confirmed:true,process_exit_confirmed:true,owned_tree_handles_released_confirmed:true});
 const closePath=path.join(f.root,'synthetic-close-receipt.json'),inputPath=path.join(f.root,'synthetic-close-input.json');
 const closeInput={format:'schema6-session-close-approved-v1',approved:true,releaseDirectory:f.core.releaseDirectory,manifestSha256:manifest,loginConfigurationPath:f.p.login,loginConfigurationSha256:fileHash(f.p.login),outputPath:closePath,host:{ownerSid:sid},sessionDirectory:session,controlDirectory:control,launchSha256:fileHash(launchPath),readySha256:fileHash(readyPath),maintenanceScriptSha256:fileHash(path.join(sourceRoot,'tools/i_core/maintenance/close-schema6-session.ps1')),processImageBindingSha256:fileHash(path.join(sourceRoot,'tools/i_core/maintenance/process_image_binding.ps1'))};
 put(inputPath,closeInput);
 put(closePath,{format:'schema6-approved-session-close-v1',closed:true,manifestSha256:manifest,configurationSha256:fileHash(inputPath),originalHostExitConfirmed:true,externalCloseElapsedMs:100,budgetMs:30000,wmCloseOnly:true,coreForced:false,databaseExclusiveOpenConfirmed:true,receiptSha256:{...Object.fromEntries(Object.entries(terminal).map(([k,p])=>[k,fileHash(p)])),marker:fileHash(markerPath),mcpStop:fileHash(mcpStop)}});
 const preparePath=path.join(f.root,'synthetic-fixed-prepare-receipt.json');put(preparePath,{prepared:true,registered:false,started:false,manifest_sha256:manifest,login_configuration_sha256:out.loginSha256});
 // Match the production registration's independently protected backup-file requirement.
 const backupPath=proposal.toArtifacts.find(a=>a.role==='backup').path;
 const quoted=backupPath.replaceAll("'","''");
 execFileSync(ps,['-NoProfile','-NonInteractive','-Command',"$env:PSModulePath=Join-Path $PSHOME 'Modules';$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User;$a=Get-Acl -LiteralPath '"+quoted+"';$a.SetAccessRuleProtection($true,$false);foreach($who in @($sid,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'))){$a.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($who,'FullControl','Allow'))};[IO.File]::SetAccessControl('"+quoted+"',$a)"],{windowsHide:true});
 const comInputPath=path.join(f.root,'synthetic-com-input.json'),registrationXml=path.join(f.root,'registration-disabled.xml'),oldSnapshot=path.join(f.root,'old-task-snapshot.xml');
 put(comInputPath,{format:'synthetic-mcp-registration-e2e-v1',root:f.root,nonce,oldName:f.input.oldTaskName,newName:f.input.newTaskName,sourceRoot,release:f.core.releaseDirectory,oldXml:f.p.task,newXml:out.outputXmlPath,registrationXml,oldSnapshot});
 const com=mode=>JSON.parse(execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(root,'tools/i_core/test_fixtures/release_schema6/mcp_config_switch_registration_e2e.ps1'),'-InputPath',comInputPath,'-Mode',mode],{encoding:'utf8',windowsHide:true,timeout:45000}).trim());
 let created=false,completed=false;
 try{
  created=true;f.cleanup.allowed=false;const security=com('Prepare');
  const config={format:'schema6-mcp-config-switch-registration-v1',approved:true,registerOnly:true,registerDisabled:true,registrationDerivation:'fixed_prepare_settings_enabled_false_only',ownerSid:sid,taskName:f.input.newTaskName,oldTask:{name:f.input.oldTaskName,xml:ref(oldSnapshot),sddl:security.oldSddl,sddlSha256:security.oldSddlSha256},registrationSddl:security.registrationSddl,expectedRegisteredSddl:security.expectedRegisteredSddl,parentSddlSha256:security.parentSddlSha256,taskSecurityPolicyVersion:security.taskSecurityPolicyVersion,inheritedReadOnlyPrincipals:security.inheritedReadOnlyPrincipals,releaseDirectory:f.core.releaseDirectory,manifestSha256:manifest,proposal:ref(finalized.proposalPath),closedMarker:ref(markerPath),currentHead:ref(headPath),originalCloseInput:ref(inputPath),originalCloseReceipt:ref(closePath),mcpStart:ref(mcpStart),fixedPrepareReceipt:ref(preparePath),preparedXml:ref(out.outputXmlPath),approvedXml:ref(out.outputXmlPath),registrationXml:ref(registrationXml),maintenanceFiles,registrationReceiptPath:path.join(f.root,'registration-result.json')};
  const approvalPath=path.join(f.root,'synthetic-human-approval.json'),configPath=path.join(f.root,'synthetic-registration.json');
  const publish=()=>{const {format,humanApproval,...approved}=config;put(approvalPath,{...approved,format:'schema6-mcp-config-switch-registration-human-approval-v1',action:'create_new_disabled_login_task_only',authorized:true});config.humanApproval=ref(approvalPath);put(configPath,config);};
  const invoke=()=>spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(sourceRoot,'tools/i_core/maintenance/register-mcp-config-switch-login.ps1'),'-ConfigurationPath',configPath,'-ExpectedConfigurationSha256',fileHash(configPath),'-RegisterOnly'],{env:cleanEnvironment(),encoding:'utf8',windowsHide:true,timeout:90000});
  publish();renameSync(terminal.guardian,terminal.guardian+'.missing');try{const r=invoke();assert.equal(r.status,2,r.stdout+r.stderr);assert.equal(com('CheckAbsent').absent,true);}finally{renameSync(terminal.guardian+'.missing',terminal.guardian);}
  put(path.join(state,'ledger.bin'),'drifted synthetic ledger');try{const r=invoke();assert.equal(r.status,2,r.stdout+r.stderr);assert.equal(com('CheckAbsent').absent,true);}finally{put(path.join(state,'ledger.bin'),'synthetic ledger');}
  const approved=config.parentSddlSha256;config.parentSddlSha256='0'.repeat(64);put(configPath,config);try{const r=invoke();assert.equal(r.status,2,r.stdout+r.stderr);assert.equal(com('CheckAbsent').absent,true);}finally{config.parentSddlSha256=approved;publish();}
  com('EnableOld');try{const r=invoke();assert.equal(r.status,2,r.stdout+r.stderr);assert.equal(com('CheckAbsent').absent,true);}finally{com('DisableOld');}
  // A rejected registration may leave a rejected receipt, so every attempt gets a fresh approved output.
  config.registrationReceiptPath=path.join(f.root,'registration-success.json');publish();
  const result=invoke();assert.equal(result.status,0,result.stdout+result.stderr);
  const actual=com('Check');assert.equal(actual.disabled,true);assert.equal(actual.instancesZero,true);assert.equal(actual.oldDisabled,true);assert.equal(actual.oldInstancesZero,true);
  const receipt=JSON.parse(readFileSync(config.registrationReceiptPath));assert.equal(receipt.passed,true);assert.equal(receipt.started,false);assert.equal(receipt.createdTaskDisabled,true);assert.equal(receipt.instancesZero,true);assert.equal(receipt.registrationSddlSha256,sha256(config.registrationSddl));assert.equal(receipt.expectedRegisteredSddlSha256,sha256(config.expectedRegisteredSddl));assert.equal(receipt.parentSddlSha256,config.parentSddlSha256);
  assert.equal(fileHash(markerPath),config.closedMarker.sha256);assert.equal(fileHash(headPath),config.currentHead.sha256);assert.equal(fileHash(f.c.database_path),marker.database_sha256);
  completed=true;t.diagnostic('Full wrapper executed with synthetic anchored closure and raw state; CREATE-only new task disabled, no action started.');
 }finally{if(created){const cleanup=com('Cleanup');if(completed)assert.equal(cleanup.cleaned,2);f.cleanup.allowed=true;}}
});
