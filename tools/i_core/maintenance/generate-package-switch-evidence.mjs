// Source-only evidence preparation. No task mutation, Core launch, or key reads.
import {execFileSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import {existsSync,lstatSync,mkdtempSync,readFileSync,rmdirSync,unlinkSync,writeFileSync} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {INVENTORY,cleanEnvironment,plainPath,sha256} from '../release_schema6/package.mjs';
import {readSwitchPlan} from '../release_schema6/package_switch.mjs';
import {validatePackageSwitchBindings} from './package-switch-bindings.mjs';
import {validatePackageSwitchRegistration,validateSwitchRegistrationEvidence} from './package-switch-registration.mjs';

const directory=path.dirname(fileURLToPath(import.meta.url));
const need=(value,code)=>{if(!value)throw Object.assign(new Error(code),{code});};
const encode=value=>Buffer.from(JSON.stringify(value,null,2)+'\n');
const json=filename=>JSON.parse(bytes(filename).toString('utf8').replace(/^\uFEFF/,''));
function bytes(filename){const p=plainPath(filename),s=lstatSync(p);need(s.isFile()&&s.nlink===1&&s.size<=16*1024*1024,'evidence_file_rejected');return readFileSync(p);}
const ref=filename=>({path:plainPath(filename),sha256:sha256(bytes(filename))});
function fresh(filename){plainPath(filename,{missing:true});need(!existsSync(filename),'evidence_output_exists');need(lstatSync(plainPath(path.dirname(filename))).isDirectory(),'evidence_parent_required');return filename;}
function separate(paths){need(new Set(paths.map(p=>p.toLowerCase())).size===paths.length,'evidence_output_collision');paths.forEach(fresh);}
function outside(filename,roots){for(const root of roots){const relative=path.relative(root,filename);need(relative!==''&&(relative.startsWith('..'+path.sep)||relative==='..'||path.isAbsolute(relative)),'evidence_output_scope_rejected');}}
const maintenanceNames=['register-package-switch-login.ps1','package-switch-registration.mjs','package-switch-bindings.mjs','register_task_primitives.ps1','task_security_policy.ps1','owned_artifacts.ps1','close-schema6-session.ps1','process_image_binding.ps1'];

// Exported for synthetic tests to reuse the exact read-only locator in a process
// with the existing Schema6TaskAdapter. The CLI has no alternate task adapter.
export const CLOSE_INPUT_INSPECTOR=String.raw`
function Get-PackageSwitchCloseInput($Request) {
 . $Request.locatorScript
 $binding=Get-Schema6LoginBinding $Request.task
 Assert-Schema6NoRecovery $binding
 $sessions=@(Get-Schema6LiveSessions $binding)
 try {
  if($sessions.Count -ne 1){throw 'close_input_single_live_session_required'}
  $session=$sessions[0];$login=$binding.Login
  if($session.Window.manifest_sha256 -cne $login.manifest_sha256){throw 'close_input_window_binding'}
  $live=@()
  foreach($d in @(Get-ChildItem -LiteralPath $session.Directory -Directory -Filter 'control-*')){
   $readyPath=Join-Path $d.FullName 'ready.json'
   if(!(Test-Path -LiteralPath $readyPath) -or (Test-Path -LiteralPath (Join-Path $d.FullName 'child.json'))){continue}
   $launch=Read-Schema6Json (Join-Path $d.FullName 'launch.json');$ready=Read-Schema6Json $readyPath
   if($launch.token -cnotmatch '^[a-f0-9]{64}$' -or $launch.token -cne $ready.token -or $launch.manifest_sha256 -cne $login.manifest_sha256 -or $ready.manifest_sha256 -cne $login.manifest_sha256 -or $launch.release -cne $login.release_directory -or $launch.state -cne $login.state_directory -or $launch.configuration_file -cne $login.core_configuration_path -or $ready.configuration_sha256 -cne $login.core_configuration_sha256 -or $launch.owner_sid -cne $login.owner_sid -or $launch.mode -cnotin @('start','initialize-empty')){throw 'close_input_control_binding'}
   $marker=Read-Schema6Json (Join-Path $login.state_directory 's6-lifecycle.json')
   if($marker.phase -cne 'listening' -or $marker.token -cne $launch.token -or $marker.manifest_sha256 -cne $launch.manifest_sha256 -or $marker.configuration_sha256 -cne $ready.configuration_sha256){throw 'close_input_core_not_live'}
   foreach($name in @('stop','close','session-close.json','supervisor.json')){if(Test-Path -LiteralPath (Join-Path $d.FullName $name)){throw 'close_input_close_pending'}}
   $core=$null
   try{$core=[Diagnostics.Process]::GetProcessById([int]$ready.pid);if($core.HasExited -or !$core.MainModule.FileName.Equals((Join-Path $login.release_directory 'runtime\node.exe'),[StringComparison]::OrdinalIgnoreCase) -or $core.StartTime.ToUniversalTime().Ticks -gt (Get-Item -LiteralPath $readyPath).LastWriteTimeUtc.Ticks){throw 'close_input_core_not_live'}}finally{if($core){$core.Dispose()}}
   $live+=@($d.FullName)
  }
  if($live.Count -ne 1){throw 'close_input_single_live_control_required'}
  if(-not ('PackageSwitchWindowInfo' -as [type])){Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class PackageSwitchWindowInfo{[DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);}'}
  $process=Get-Process -Id ([int]$session.Window.pid) -ErrorAction Stop
  try{
   $windowPid=[uint32]0;$tid=[PackageSwitchWindowInfo]::GetWindowThreadProcessId([IntPtr]::new([long]$session.Window.hwnd),[ref]$windowPid)
   if($tid -eq 0 -or $windowPid -ne [uint32]$process.Id){throw 'close_input_window_changed'}
   $image=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
   if(!$process.Path.Equals($image,[StringComparison]::OrdinalIgnoreCase)){throw 'close_input_host_image'}
   . (Join-Path $Request.maintenanceDirectory 'process_image_binding.ps1')
   $imageHash=(Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash.ToLowerInvariant()
   $imageEvidence=Assert-ProcessImageFile -Path $image -ExpectedSha256 $imageHash
   try {
   $result=[ordered]@{format='schema6-session-close-approved-v1';approved=[bool]$Request.approve;releaseDirectory=$login.release_directory;manifestSha256=$login.manifest_sha256;loginConfigurationPath=$binding.ConfigurationPath;loginConfigurationSha256=$binding.ConfigurationSha256;sessionDirectory=$session.Directory;controlDirectory=$live[0];windowSha256=(Get-FileHash -LiteralPath (Join-Path $session.Directory 'session-window.json') -Algorithm SHA256).Hash.ToLowerInvariant();launchSha256=(Get-FileHash -LiteralPath (Join-Path $live[0] 'launch.json') -Algorithm SHA256).Hash.ToLowerInvariant();readySha256=(Get-FileHash -LiteralPath (Join-Path $live[0] 'ready.json') -Algorithm SHA256).Hash.ToLowerInvariant();maintenanceScriptSha256=(Get-FileHash -LiteralPath (Join-Path $Request.maintenanceDirectory 'close-schema6-session.ps1') -Algorithm SHA256).Hash.ToLowerInvariant();processImageBindingSha256=(Get-FileHash -LiteralPath (Join-Path $Request.maintenanceDirectory 'process_image_binding.ps1') -Algorithm SHA256).Hash.ToLowerInvariant();host=@{pid=$process.Id;hwnd=$session.Window.hwnd;startedTicks=$process.StartTime.ToUniversalTime().Ticks.ToString();imagePath=$image;imageSha256=$imageEvidence.sha256;ownerSid=$login.owner_sid;sessionId=$process.SessionId;threadId=$tid};outputPath=$Request.receipt}
   return $result
   }finally{$imageEvidence.lease.Dispose()}
  }finally{$process.Dispose()}
 }finally{foreach($session in $sessions){$session.Lease.Dispose()}}
}
`;

// This inspector only reads Scheduler state. Disabling the reviewed task is a
// separate, explicit D1b action and is never performed by evidence generation.
export const OLD_TASK_INSPECTOR=String.raw`
. $request.policyScript
. (Join-Path (Split-Path -Parent $request.policyScript) 'register_task_primitives.ps1')
$service=New-Object -ComObject 'Schedule.Service';$service.Connect()
$folder=$service.GetFolder('\');$task=$folder.GetTask($request.task)
$stopped=(!$task.Enabled -and $task.GetInstances(0).Count -eq 0)
if(!$request.preview -and !$stopped){throw 'old_task_not_stopped'}
if($task.Path -cne ('\'+$request.task)){throw 'old_task_path_changed'}
$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$xml=[string]$task.Xml;$sddl=[string]$task.GetSecurityDescriptor(7)
$current=Read-TaskPolicySecurity $sddl
$explicit=[Security.AccessControl.RawAcl]::new($current.DiscretionaryAcl.Revision,$current.DiscretionaryAcl.Count)
foreach($ace in $current.DiscretionaryAcl){
 if(([int]$ace.AceFlags -band 16) -ne 0){continue}
 if([int]$ace.AceFlags -ne 0 -or $ace.SecurityIdentifier.Value -notin @($owner,'S-1-5-18','S-1-5-32-544')){throw 'task_policy_explicit_principal_rejected'}
 $explicit.InsertAce($explicit.Count,$ace)
}
Assert-TaskAllowedRights $sddl $owner
$registration=[Security.AccessControl.RawSecurityDescriptor]::new([Security.AccessControl.ControlFlags]::DiscretionaryAclPresent,$current.Owner,$current.Group,$null,$explicit)
$registrationSddl=$registration.GetSddlForm([Security.AccessControl.AccessControlSections]::All)
$parent=[string]$folder.GetSecurityDescriptor(7)
$expected=Get-TaskPolicyExpectedSecurity $registrationSddl $parent $owner
if((Convert-TaskSecurity $expected) -cne (Convert-TaskSecurity $sddl)){throw 'old_task_security_not_derivable'}
$principals=Get-TaskInheritedReadOnlyPrincipals $expected $owner
$security=[ordered]@{oldTaskSddl=$sddl;registrationSddl=$registrationSddl;parentSddlSha256=(Get-TaskSecuritySha256 $parent);expectedRegisteredSddl=$expected;inheritedReadOnlyPrincipals=@($principals);taskSecurityPolicyVersion='windows-file-oi-v1'}
$again=$folder.GetTask($request.task)
$stopped=(!$again.Enabled -and $again.GetInstances(0).Count -eq 0)
if(!$request.preview -and !$stopped){throw 'old_task_not_stopped'}
if($again.Path -cne $task.Path -or [string]$again.Xml -cne $xml -or [string]$again.GetSecurityDescriptor(7) -cne $sddl -or [string]$folder.GetSecurityDescriptor(7) -cne $parent){throw 'old_task_snapshot_changed'}
@{xml=$xml;security=$security;oldTaskStopped=$stopped}|ConvertTo-Json -Depth 12 -Compress
`;

const PRIVATE_CHECK=String.raw`
function Assert-EvidencePrivate([string]$Value){
 if($Value -notmatch '^[A-Za-z]:\\' -or [IO.Path]::GetFullPath($Value) -cne $Value -or $Value.Substring(2).Contains(':')){throw 'evidence_private_path_required'}
 $cursor=$Value
 while($cursor){if(([IO.File]::GetAttributes($cursor)-band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'evidence_link_rejected'};$parent=[IO.Directory]::GetParent($cursor);$cursor=if($parent){$parent.FullName}else{$null}}
 $acl=Get-Acl -LiteralPath $Value;$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 if(!$acl.AreAccessRulesProtected -or $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne $sid){throw 'evidence_private_owner_required'}
 $own=$false
 foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){if($rule.AccessControlType-eq 'Allow' -and $rule.IdentityReference.Value-eq $sid -and ($rule.FileSystemRights-band [Security.AccessControl.FileSystemRights]::FullControl)-eq [Security.AccessControl.FileSystemRights]::FullControl){$own=$true};if($rule.AccessControlType-eq 'Allow' -and $rule.IdentityReference.Value-notin @($sid,'S-1-5-18','S-1-5-32-544')){throw 'evidence_private_acl_required'}}
 if(!$own){throw 'evidence_private_control_required'}
}
`;

// Ordinary inspections use a private .ps1 in PS 5.1; preview uses fixed encoded
// code and stdin without generator artifacts. Neither inherits NODE_*/I_CORE_*.
export function evidenceInspectionError(error){
 const stderr=Buffer.isBuffer(error?.stderr)?error.stderr.toString('utf8'):typeof error?.stderr==='string'?error.stderr:'';
 const detail=stderr.trim();
 const code=/^[a-z0-9_]{1,64}$/.test(detail)?detail:/^[a-z0-9_]{1,64}$/.test(error?.code??'')?error.code:'evidence_inspection_rejected';
 const tagged='evidence_inspection_rejected:'+code;
 return Object.assign(new Error(tagged),{code:tagged});
}
export function runEvidencePowerShell(source,request,{readOnly=false}={}){
 need(process.platform==='win32','evidence_windows_required');
 const system=path.join(process.env.SystemRoot??'C:\\Windows','System32');
 if(readOnly){
  // Preview has no temporary files. Fixed repository code is encoded for PS 5.1;
  // all request values remain data on stdin, never executable command text.
  const script='$ErrorActionPreference="Stop";$ProgressPreference="SilentlyContinue";Set-StrictMode -Version 2\n$env:PSModulePath=Join-Path $PSHOME "Modules"\n$OutputEncoding=[Text.UTF8Encoding]::new($false);[Console]::OutputEncoding=$OutputEncoding\ntry {\n$reader=[IO.StreamReader]::new([Console]::OpenStandardInput(),[Text.Encoding]::UTF8)\ntry{$request=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}\n'+source+'\n}catch{$code=$_.Exception.Message;if($code -cnotmatch "\\A[a-z0-9_]{1,64}\\z"){$code="evidence_inspection_rejected"};[Console]::Error.WriteLine($code);exit 2}\n';
  const encoded=Buffer.from(script,'utf16le').toString('base64');
  need(encoded.length<30000,'evidence_inspection_source_rejected');
  try{
   const output=execFileSync(path.join(system,'WindowsPowerShell/v1.0/powershell.exe'),['-NoProfile','-NonInteractive','-OutputFormat','Text','-EncodedCommand',encoded],{windowsHide:true,env:cleanEnvironment(),input:encode(request),stdio:['pipe','pipe','pipe'],encoding:'utf8',timeout:120000,maxBuffer:4*1024*1024});
   return JSON.parse(output.replace(/^\uFEFF/,'').trim());
  }catch(error){throw evidenceInspectionError(error);}
 }
 const temp=mkdtempSync(path.join(os.tmpdir(),'schema6-evidence-'));
 const script=path.join(temp,'inspect.ps1'),input=path.join(temp,'request.json');
 try{
  const sid=execFileSync(path.join(system,'whoami.exe'),['/user','/fo','csv','/nh'],{encoding:'utf8',windowsHide:true,env:cleanEnvironment()}).match(/S-1-5-[0-9-]+/)?.[0];
  need(sid,'evidence_owner_unavailable');
  execFileSync(path.join(system,'icacls.exe'),[temp,'/inheritance:r','/grant:r','*'+sid+':(OI)(CI)F','*S-1-5-18:(OI)(CI)F'],{windowsHide:true,stdio:'pipe',env:cleanEnvironment()});
  writeFileSync(script,'\uFEFFparam([string]$InputPath)\n$ErrorActionPreference="Stop";Set-StrictMode -Version 2\n$env:PSModulePath=Join-Path $PSHOME "Modules"\n$OutputEncoding=[Text.UTF8Encoding]::new($false);[Console]::OutputEncoding=$OutputEncoding\ntry {\n$request=[IO.File]::ReadAllText($InputPath,[Text.Encoding]::UTF8)|ConvertFrom-Json\n'+source+'\n}catch{$code=$_.Exception.Message;if($code -cnotmatch "\\A[a-z0-9_]{1,64}\\z"){$code="evidence_inspection_rejected"};[Console]::Error.WriteLine($code);exit 2}\n',{flag:'wx',mode:0o600});
  writeFileSync(input,encode(request),{flag:'wx',mode:0o600});
  const output=execFileSync(path.join(system,'WindowsPowerShell/v1.0/powershell.exe'),['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',script,'-InputPath',input],{windowsHide:true,env:cleanEnvironment(),stdio:['pipe','pipe','pipe'],encoding:'utf8',timeout:120000,maxBuffer:4*1024*1024});
  return JSON.parse(output.replace(/^\uFEFF/,'').trim());
 }catch(error){throw evidenceInspectionError(error);}
 finally{for(const p of [script,input]){if(existsSync(p))unlinkSync(p);}rmdirSync(temp);}
}
function privateParents(paths,runPowerShell){
 const parents=[...new Set(paths.map(p=>path.dirname(p)))];
 if(process.platform==='win32')runPowerShell(PRIVATE_CHECK+'\nforeach($p in $request.parents){Assert-EvidencePrivate $p};@{private=$true}|ConvertTo-Json -Compress',{parents});
 else for(const p of parents){const s=lstatSync(p);need((s.mode&0o077)===0&&(!process.getuid||s.uid===process.getuid()),'evidence_private_acl_required');}
}

export function generateOldTaskEvidence(options,{runPowerShell=runEvidencePowerShell}={}){
 const {task,xmlOut,securityOut,preview=false}=options;
 need(typeof task==='string'&&/^[A-Za-z0-9][A-Za-z0-9_.-]{0,180}$/.test(task),'old_task_name_required');
 need(typeof preview==='boolean','evidence_usage');
 if(!preview){separate([xmlOut,securityOut]);privateParents([xmlOut,securityOut],runPowerShell);}
 const result=runPowerShell(OLD_TASK_INSPECTOR,{task,preview,policyScript:path.join(directory,'task_security_policy.ps1')},{readOnly:preview});
 const security=result?.security;
 need(typeof result?.xml==='string'&&result.xml.length>0&&typeof result.oldTaskStopped==='boolean'&&security&&typeof security.oldTaskSddl==='string'&&security.oldTaskSddl.length>0&&typeof security.registrationSddl==='string'&&security.registrationSddl.length>0&&typeof security.expectedRegisteredSddl==='string'&&/^[a-f0-9]{64}$/.test(security.parentSddlSha256??'')&&Array.isArray(security.inheritedReadOnlyPrincipals)&&security.taskSecurityPolicyVersion==='windows-file-oi-v1','old_task_inspection_rejected');
 const hashes={xmlSha256:sha256(Buffer.from(result.xml,'utf8')),securitySha256:sha256(encode(security)),oldTaskSddlSha256:sha256(security.oldTaskSddl),registrationSddlSha256:sha256(security.registrationSddl),expectedRegisteredSddlSha256:sha256(security.expectedRegisteredSddl),parentSddlSha256:security.parentSddlSha256,inheritedReadOnlyPrincipalsSha256:sha256(encode(security.inheritedReadOnlyPrincipals)),oldTaskStopped:result.oldTaskStopped};
 if(preview)return {summary:hashes};
 const created=[];
 try{
  fresh(xmlOut);writeFileSync(xmlOut,Buffer.from(result.xml,'utf8'),{flag:'wx',mode:0o600,flush:true});created.push(xmlOut);
  fresh(securityOut);writeFileSync(securityOut,encode(security),{flag:'wx',mode:0o600,flush:true});created.push(securityOut);
  return {xmlPath:xmlOut,securityPath:securityOut,security,summary:{format:'schema6-old-task-evidence-generation-v1',generated:true,registered:false,started:false,oldTasksChanged:false,...hashes}};
 }catch(error){for(const p of created.reverse()){try{unlinkSync(p);}catch{}}throw error;}
}

export function generateCloseInput(options,{runPowerShell=runEvidencePowerShell}={}){
 const {task,out,approve=false,maintenanceDirectory=directory,receipt=out+'.receipt.json'}=options;
 need(typeof task==='string'&&task.length>0&&task.length<=240,'close_input_task_required');
 need(typeof approve==='boolean','close_input_approval_invalid');
 separate([out,receipt]);privateParents([out,receipt],runPowerShell);
 const request={task,approve,receipt,maintenanceDirectory:plainPath(maintenanceDirectory),locatorScript:path.join(directory,'stop-schema6-session.ps1')};
 const input=runPowerShell(CLOSE_INPUT_INSPECTOR+'\nGet-PackageSwitchCloseInput $request|ConvertTo-Json -Depth 12 -Compress',request);
 need(input?.format==='schema6-session-close-approved-v1'&&input.approved===approve&&input.outputPath===receipt,'close_input_inspection_rejected');
 const login=json(input.loginConfigurationPath);
 outside(out,[login.state_directory,login.control_root,input.releaseDirectory]);outside(receipt,[login.state_directory,login.control_root,input.releaseDirectory]);
 // Hash the exact locator result again before publication; never read key paths.
 for(const [p,hash] of [[input.loginConfigurationPath,input.loginConfigurationSha256],[path.join(input.sessionDirectory,'session-window.json'),input.windowSha256],[path.join(input.controlDirectory,'launch.json'),input.launchSha256],[path.join(input.controlDirectory,'ready.json'),input.readySha256],[path.join(maintenanceDirectory,'close-schema6-session.ps1'),input.maintenanceScriptSha256],[path.join(maintenanceDirectory,'process_image_binding.ps1'),input.processImageBindingSha256]])need(ref(p).sha256===hash,'close_input_anchor_changed');
 fresh(out);writeFileSync(out,encode(input),{flag:'wx',mode:0o600,flush:true});
 return {input,configurationPath:out,summary:{format:'schema6-close-input-generation-v1',generated:true,approved:approve,closed:false,started:false,registered:false,configurationSha256:ref(out).sha256}};
}

export function buildRegistrationCandidate(options){
 const switchPlan=ref(options.switchPlan),plan=readSwitchPlan(switchPlan.path,switchPlan.sha256);
 need(plan.approved===true,'registration_approval_required');validatePackageSwitchBindings(plan,{fromArtifacts:plan.fromArtifacts});
 const core=json(plan.to.configurationPath),markerPath=path.join(path.dirname(core.database_path),'s6-lifecycle.json'),marker=json(markerPath);
 const security=typeof options.security==='string'?json(options.security):options.security;
 need(security&&typeof security==='object','registration_security_required');
 for(const name of ['registrationSddl','expectedRegisteredSddl','parentSddlSha256','taskSecurityPolicyVersion','inheritedReadOnlyPrincipals','oldTaskSddl'])need(Object.hasOwn(security,name),'registration_security_required');
 need(security.taskSecurityPolicyVersion==='windows-file-oi-v1'&&Array.isArray(security.inheritedReadOnlyPrincipals)&&/^[a-f0-9]{64}$/.test(security.parentSddlSha256),'registration_security_rejected');
 need(/^[A-Za-z0-9][A-Za-z0-9_.-]{0,180}$/.test(options.taskName??'')&&/^[A-Za-z0-9][A-Za-z0-9_.-]{0,180}$/.test(options.oldTaskName??'')&&options.taskName.toLowerCase()!==options.oldTaskName.toLowerCase(),'registration_task_name');
 const targetTask=plan.artifacts.find(a=>a.role==='task');
 need(bytes(options.preparedXml).equals(bytes(targetTask.path)),'registration_prepare_xml_changed');
 const maintenanceRoot=plainPath(options.maintenanceSnapshot);
 const maintenanceFiles=[...INVENTORY.filter(n=>n!=='runtime/node.exe'),...maintenanceNames.map(n=>'tools/i_core/maintenance/'+n)].map(n=>ref(path.join(maintenanceRoot,n)));
 const config={format:'schema6-package-switch-registration-v1',approved:true,registerOnly:true,registerDisabled:true,registrationDerivation:'fixed_prepare_settings_enabled_false_only',ownerSid:core.owner_sid,taskName:options.taskName,
  oldTask:{name:options.oldTaskName,xml:ref(options.oldTaskXml),sddl:security.oldTaskSddl,sddlSha256:sha256(security.oldTaskSddl)},registrationSddl:security.registrationSddl,expectedRegisteredSddl:security.expectedRegisteredSddl,parentSddlSha256:security.parentSddlSha256,taskSecurityPolicyVersion:security.taskSecurityPolicyVersion,inheritedReadOnlyPrincipals:security.inheritedReadOnlyPrincipals,
  releaseDirectory:plan.to.releaseDirectory,manifestSha256:plan.to.manifestSha256,switchPlan,targetMarker:ref(markerPath),currentHead:ref(path.join(core.recovery_custody_directory,'current-head.json')),switchEvent:ref(path.join(core.recovery_custody_directory,marker.package_switch_event_sha256+'.package-switch.json')),targetFloor:ref(path.join(core.recovery_custody_directory,marker.custody_sha256+'.floor.json')),
  originalCloseInput:ref(options.closeInput),originalCloseReceipt:ref(options.closeReceipt),originalMarkerSnapshot:ref(options.originalMarkerSnapshot),fixedPrepareReceipt:ref(options.prepareReceipt),preparedXml:ref(options.preparedXml),approvedXml:ref(targetTask.path),registrationXml:{path:options.registrationXmlOut,sha256:null},offline:Object.fromEntries(['launch','child','guardian','supervisor','operation'].map(n=>[n,ref(path.join(options.offlineControl,n+'.json'))])),maintenanceFiles,registrationReceiptPath:options.receipt};
 const outputs=[options.out,options.humanApprovalOut,options.registrationXmlOut,options.receipt];separate(outputs);
 for(const p of outputs)outside(p,[path.dirname(core.database_path),core.recovery_custody_directory,plan.from.releaseDirectory,plan.to.releaseDirectory,options.offlineControl]);
 for(const p of [path.join(path.dirname(core.database_path),'s6-package-switch-pending.json'),path.join(core.recovery_custody_directory,'package-switch-pending.json')])need(!existsSync(p),'registration_pending');
 const closed=json(options.closeInput),receipt=json(options.closeReceipt),prepare=json(options.prepareReceipt);
 need(closed.approved===true&&closed.format==='schema6-session-close-approved-v1'&&closed.outputPath===options.closeReceipt&&receipt.configurationSha256===config.originalCloseInput.sha256&&receipt.closed===true,'registration_original_close_binding');
 need(config.originalMarkerSnapshot.sha256===plan.expectedMarkerSha256&&receipt.receiptSha256?.marker===plan.expectedMarkerSha256,'registration_original_marker_changed');
 need(prepare.prepared===true&&prepare.registered===false&&prepare.started===false&&prepare.manifest_sha256===plan.to.manifestSha256&&prepare.login_configuration_sha256===plan.artifacts.find(a=>a.role==='login').sha256,'registration_prepare_binding');
 // Exercise the frozen, file-independent proof validator during zero-write
 // preflight too. Full file/approval validation remains a publication gate.
 const offline=Object.fromEntries(Object.entries(config.offline).map(([name,anchor])=>[name,json(anchor.path)]));
 const originalChild=json(path.join(closed.controlDirectory,'child.json'));
 for(const [name,key] of [['close-schema6-session.ps1','maintenanceScriptSha256'],['process_image_binding.ps1','processImageBindingSha256']])need(config.maintenanceFiles.find(f=>path.basename(f.path)===name)?.sha256===closed[key],'registration_original_close_source');
 validateSwitchRegistrationEvidence({plan,planSha256:switchPlan.sha256,marker,head:json(config.currentHead.path),event:json(config.switchEvent.path),floor:json(config.targetFloor.path),operation:offline.operation,offline,close:receipt,closeInput:config.originalCloseInput,sourceMarker:json(config.originalMarkerSnapshot.path),originalToken:originalChild.token,prepare,markerSha256:config.targetMarker.sha256,headSha256:config.currentHead.sha256,eventSha256:config.switchEvent.sha256,floorSha256:config.targetFloor.sha256});
 return {config,plan,security};
}

// Task Scheduler's own serializer is required: hand-editing XML does not produce
// the same bytes the frozen RegisterOnly entry derives from NewTask.XmlText.
export function deriveDisabledTaskXml(preparedXml,{runPowerShell=runEvidencePowerShell}={}){
 bytes(preparedXml);
 const preparedSha256=ref(preparedXml).sha256;
 const value=runPowerShell(String.raw`
$service=New-Object -ComObject 'Schedule.Service';$service.Connect()
$stream=[IO.File]::Open($request.preparedXml,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try{
 $digest=[Security.Cryptography.SHA256]::Create()
 try{$actual=([BitConverter]::ToString($digest.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$digest.Dispose()}
 if($actual -cne $request.preparedSha256){throw 'registration_prepare_xml_changed'}
 $stream.Position=0;$reader=[IO.StreamReader]::new($stream)
 try{$xml=$reader.ReadToEnd()}finally{$reader.Dispose()}
}finally{$stream.Dispose()}
$definition=$service.NewTask(0);$definition.XmlText=$xml
if(!$definition.Settings.Enabled){throw 'registration_prepare_enabled_required'}
$definition.Settings.Enabled=$false
@{xml=[string]$definition.XmlText}|ConvertTo-Json -Depth 4 -Compress
`,{preparedXml,preparedSha256});
 need(typeof value?.xml==='string'&&value.xml.length>0,'registration_xml_derivation_rejected');return Buffer.from(value.xml,'utf8');
}

function recheckAnchors(value){
 if(!value||typeof value!=='object')return;
 if(typeof value.path==='string'&&typeof value.sha256==='string')need(ref(value.path).sha256===value.sha256,'registration_anchor_changed');
 for(const child of Object.values(value))recheckAnchors(child);
}

export function generateRegistrationEvidence(options,{runPowerShell=runEvidencePowerShell}={}){
 const {config}=buildRegistrationCandidate(options);
 const summary={format:'schema6-package-switch-evidence-generation-v1',dryRun:options.dryRun===true,generated:false,registered:false,started:false,oldTasksChanged:false,databaseChanged:false,taskNamesChecked:true,maintenanceFileCount:config.maintenanceFiles.length,registrationValidatorPending:true};
 // A zero-write rehearsal cannot create the two files required by the frozen
 // validator. It truthfully reports this pending gate; publication always runs it.
 if(options.dryRun===true)return {config,summary:{...summary,readOnlyPreflightPassed:true,privateOutputAclPending:process.platform==='win32',disabledXmlDerivationPending:true}};
 privateParents([options.out,options.humanApprovalOut,options.registrationXmlOut,options.receipt],runPowerShell);
 const disabled=deriveDisabledTaskXml(options.preparedXml,{runPowerShell});
 const stage=path.join(path.dirname(options.humanApprovalOut),'.registration-approval-'+randomBytes(16).toString('hex')+'.tmp');fresh(stage);
 const created=[];
 try{
  // XML is a prerequisite evidence artifact, not a published registration input.
  // Keep its final path stable so approval bytes stay identical after validation.
  fresh(options.registrationXmlOut);writeFileSync(options.registrationXmlOut,disabled,{flag:'wx',mode:0o600,flush:true});created.push(options.registrationXmlOut);config.registrationXml=ref(options.registrationXmlOut);
  const approval={...config,format:'schema6-package-switch-registration-human-approval-v1',action:'create_new_disabled_login_task_only',authorized:true};
  const approvalBytes=encode(approval);writeFileSync(stage,approvalBytes,{flag:'wx',mode:0o600,flush:true});created.push(stage);config.humanApproval=ref(stage);
  recheckAnchors(config);const validated=validatePackageSwitchRegistration(config);need(validated.validated===true,'registration_proof_rejected');
  need(bytes(stage).equals(approvalBytes)&&bytes(options.registrationXmlOut).equals(disabled),'registration_staged_evidence_changed');
  fresh(options.humanApprovalOut);writeFileSync(options.humanApprovalOut,approvalBytes,{flag:'wx',mode:0o600,flush:true});created.push(options.humanApprovalOut);
  config.humanApproval=ref(options.humanApprovalOut);need(config.humanApproval.sha256===sha256(approvalBytes),'registration_approval_publish_changed');
  // Recheck exact final references before publishing the usable configuration.
  recheckAnchors(config);validatePackageSwitchRegistration(config);
  fresh(options.out);writeFileSync(options.out,encode(config),{flag:'wx',mode:0o600,flush:true});created.push(options.out);
  unlinkSync(stage);created.splice(created.indexOf(stage),1);
  return {config,approval,configurationPath:options.out,summary:{...summary,generated:true,registrationValidatorPending:false,validated:true,configurationSha256:ref(options.out).sha256,humanApprovalSha256:config.humanApproval.sha256,registrationXmlSha256:config.registrationXml.sha256}};
 }catch(error){
  // Only remove exact files exclusively created by this invocation. No recursive
  // cleanup, no input modifications, and no overwriting an existing destination.
  for(const p of created.reverse()){try{unlinkSync(p);}catch{}}
  throw error;
 }
}

export function parseEvidenceArguments(args){
 const command=args.shift(),flags={};
 const booleans=new Set(['approve','dry-run','preview']);
 const allowed=command==='close-input'?new Set(['task','out','approve','maintenance-directory','receipt']):command==='old-task'?new Set(['task','xml-out','security-out','preview']):command==='registration'?new Set(['switch-plan','close-input','close-receipt','offline-control','prepare-receipt','prepared-xml','old-task-name','task-name','maintenance-snapshot','original-marker-snapshot','old-task-xml','security','out','human-approval-out','registration-xml-out','receipt','dry-run']):null;
 need(allowed,'evidence_usage');
 while(args.length){const flag=args.shift();need(flag.startsWith('--')&&allowed.has(flag.slice(2))&&!Object.hasOwn(flags,flag.slice(2)),'evidence_usage');const key=flag.slice(2);if(booleans.has(key))flags[key]=true;else{need(args.length>0&&!args[0].startsWith('--'),'evidence_usage');flags[key]=args.shift();}}
 const options=Object.fromEntries(Object.entries(flags).map(([k,v])=>[k.replace(/-([a-z])/g,(_,c)=>c.toUpperCase()),v]));
 const required=command==='close-input'?['task','out']:command==='old-task'?(options.preview?['task']:['task','xmlOut','securityOut']):['switchPlan','closeInput','closeReceipt','offlineControl','prepareReceipt','preparedXml','oldTaskName','taskName','maintenanceSnapshot','originalMarkerSnapshot','oldTaskXml','security','out','humanApprovalOut','registrationXmlOut','receipt'];
 for(const key of required)need(typeof options[key]==='string'&&options[key].length>0,'evidence_usage');
 return {command,options};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
 try{const {command,options}=parseEvidenceArguments(process.argv.slice(2));const result=command==='close-input'?generateCloseInput(options):command==='old-task'?generateOldTaskEvidence(options):generateRegistrationEvidence(options);process.stdout.write(JSON.stringify(result.summary)+'\n');}
 catch(error){const code=/^(?:evidence_inspection_rejected:)?[a-z0-9_]{1,64}$/.test(error.code??'')?error.code:'package_switch_evidence_rejected';process.stdout.write(JSON.stringify({generated:false,registered:false,started:false,code})+'\n');process.exitCode=2;}
}
