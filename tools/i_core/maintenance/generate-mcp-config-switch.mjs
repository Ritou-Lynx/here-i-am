// Writes fresh candidate files only. No task/service/database/key operation.
import path from 'node:path';
import {existsSync,mkdirSync,readFileSync,openSync,writeFileSync,fsyncSync,closeSync,chmodSync,lstatSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {sha256,plainPath,cleanEnvironment} from '../release_schema6/package.mjs';
import {backupFilePrimitives as f} from '../release_schema6/backup_bundle.mjs';
import {exact,need,lexical,independent,artifactMap,jsonRef,readCore,readLogin,readMcp,validateCandidate,validateBackupBase,backupMapping,buildMcpSwitchBackup,taskXml,validateTask,validateMcpConfigSwitch} from './mcp-config-switch-bindings.mjs';

const hash=p=>sha256(readFileSync(plainPath(p)));
function writeNew(p,value){const b=Buffer.from(typeof value==='string'?value:JSON.stringify(value,null,2)+'\n');plainPath(p,{missing:true});const fd=openSync(p,'wx',0o600);try{writeFileSync(fd,b);fsyncSync(fd);}finally{closeSync(fd);}f.safe(p);return {path:p,sha256:sha256(b)};}
function directory(p){f.safe(path.dirname(p),true);plainPath(p,{missing:true});need(!existsSync(p),'fresh_output');mkdirSync(p);f.protect(p);f.safe(p,true);}

const backupAclScript="$ErrorActionPreference='Stop'\n$env:PSModulePath=Join-Path $PSHOME 'Modules'\n$stream=$null\ntry {\n if($PSVersionTable.PSVersion.Major-ne 5 -or $PSVersionTable.PSEdition-ne 'Desktop'){throw 'powershell_51_required'}\n $inputSpec=[Console]::In.ReadToEnd()|ConvertFrom-Json\n $target=[string]$inputSpec.path\n if($target-notmatch '^[A-Za-z]:\\\\' -or [IO.Path]::GetFullPath($target)-cne $target -or $target.Substring(2).Contains(':')){throw 'path_rejected'}\n for($q=$target;$q;$q=[IO.Path]::GetDirectoryName($q)){if(([IO.File]::GetAttributes($q)-band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'linked_path_rejected'}}\n $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User\n $access=if($inputSpec.protect-eq $true){[IO.FileAccess]::ReadWrite}else{[IO.FileAccess]::Read}\n $stream=if($inputSpec.protect-eq $true){[IO.FileStream]::new($target,[IO.FileMode]::Open,[Security.AccessControl.FileSystemRights]::FullControl,[IO.FileShare]::None,4096,[IO.FileOptions]::None)}else{[IO.File]::Open($target,[IO.FileMode]::Open,$access,[IO.FileShare]::None)}\n if($inputSpec.protect-eq $true){\n  $acl=New-Object Security.AccessControl.FileSecurity\n  $acl.SetOwner($sid);$acl.SetAccessRuleProtection($true,$false)\n  foreach($who in @($sid,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'))){$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($who,'FullControl','Allow'))}\n  $stream.SetAccessControl($acl)\n }\n $actual=$stream.GetAccessControl()\n if(!$actual.AreAccessRulesProtected -or $actual.GetOwner([Security.Principal.SecurityIdentifier]).Value-cne $sid.Value){throw 'backup_acl_rejected'}\n $rules=@($actual.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]));$seen=@{}\n if($rules.Count-ne 2){throw 'backup_acl_rejected'}\n foreach($rule in $rules){\n  $id=$rule.IdentityReference.Value\n  if($id-notin @($sid.Value,'S-1-5-18') -or $seen.ContainsKey($id) -or $rule.IsInherited -or $rule.AccessControlType-ne 'Allow' -or $rule.FileSystemRights-ne [Security.AccessControl.FileSystemRights]::FullControl -or $rule.InheritanceFlags-ne 'None' -or $rule.PropagationFlags-ne 'None'){throw 'backup_acl_rejected'}\n  $seen[$id]=$true\n }\n if(!$seen.ContainsKey($sid.Value)-or !$seen.ContainsKey('S-1-5-18')){throw 'backup_acl_rejected'}\n [Console]::Out.Write('{\"validated\":true}')\n} catch {exit 2} finally {if($stream){$stream.Dispose()}}";
// The target travels only as JSON stdin to fixed PowerShell source.
function backupFileAcl(p,protect=false){
 f.safe(p);
 if(process.platform!=='win32'){
  if(protect)chmodSync(p,0o600);
  need((lstatSync(p).mode&0o777)===0o600,'backup_acl');
  return;
 }
 try{
  const raw=execFileSync(path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe'),['-NoProfile','-NonInteractive','-Command',backupAclScript],{input:JSON.stringify({path:p,protect}),encoding:'utf8',env:cleanEnvironment(),windowsHide:true,stdio:['pipe','pipe','pipe'],timeout:30000,maxBuffer:1024});
  need(JSON.parse(raw).validated===true,'backup_acl');f.safe(p);
 }catch{need(false,'backup_acl');}
}

export function generateMcpConfigSwitch(input){
 exact(input,['format','core','fromArtifacts','candidate','oldTaskName','newTaskName','outputDirectory']);need(input.format==='schema6-mcp-config-switch-generation-v1','generation_format');
 const {core,fromArtifacts,candidate,oldTaskName,newTaskName,outputDirectory}=input,c=readCore(core),from=artifactMap(fromArtifacts),l=readLogin(core,c,from),old=readMcp(c,l,from.mcp),manifest=validateCandidate(candidate,old),backup=jsonRef(from.backup);
 validateBackupBase(backup,core,c);validateTask(core,l,from);lexical(outputDirectory);
 need(typeof oldTaskName==='string'&&typeof newTaskName==='string'&&/^[A-Za-z0-9][A-Za-z0-9_.-]{0,180}$/.test(oldTaskName)&&/^[A-Za-z0-9][A-Za-z0-9_.-]{0,180}$/.test(newTaskName)&&oldTaskName.toLowerCase()!==newTaskName.toLowerCase(),'task_name');
 need(!Object.hasOwn(old.environment,'I_REMOTE_MCP_CHATGPT_ENABLED'),'environment_delta');
 const forbidden=[core.releaseDirectory,path.dirname(core.configurationPath),...fromArtifacts.map(a=>path.dirname(a.path)),candidate.runtimeDirectory,path.dirname(candidate.manifestPath),old.working_directory,l.state_directory,l.control_root,l.backup_key_directory,c.recovery_custody_directory,path.dirname(c.recovery_key_path),path.dirname(c.grants_path),path.dirname(c.approvals_path),backup.policy.outputRoot,path.dirname(backup.envelopePath),old.environment.I_REMOTE_MCP_STATE_DIR,old.environment.I_HOME,path.dirname(old.environment.I_MEMORY_DB),path.dirname(old.environment.I_MEMORY_POLICY),...(backup.policy.mirrorRoot?[backup.policy.mirrorRoot]:[]),...(c.backup_directory?[c.backup_directory]:[]),...(c.backup_key_path?[path.dirname(c.backup_key_path)]:[])];
 for(const p of forbidden)independent(outputDirectory,p);
 const to=Object.fromEntries(['mcp','backup','login','task'].map(role=>[role,{role,path:path.join(outputDirectory,{mcp:'mcp.json',backup:'daily-backup-config.json',login:'login.json',task:'login-task.prepared.xml'}[role]),sha256:undefined}]));
 const m={...old,working_directory:candidate.runtimeDirectory,entrypoint:manifest.entry,source_files:manifest.files.map(e=>({path:e.path,sha256:e.result_sha256})),environment:{...old.environment,I_REMOTE_MCP_CHATGPT_ENABLED:'1'}};
 // Validate every prospective mapping before the first write.
 const mapping=backupMapping(old,from,to,manifest,candidate);buildMcpSwitchBackup(backup,mapping);
 directory(outputDirectory);
 Object.assign(to.mcp,writeNew(to.mcp.path,m));
 const nextBackup=buildMcpSwitchBackup(backup,backupMapping(old,from,to,manifest,candidate));Object.assign(to.backup,writeNew(to.backup.path,nextBackup));backupFileAcl(to.backup.path,true);
 const nextLogin={...l,mcp_configuration_path:to.mcp.path,mcp_configuration_sha256:to.mcp.sha256,backup_configuration_path:to.backup.path,backup_configuration_sha256:to.backup.sha256};
 Object.assign(to.login,writeNew(to.login.path,nextLogin));
 const review=writeNew(path.join(outputDirectory,'login-task.review.xml'),taskXml(core,nextLogin,to.login)+'\n');
 const staticInputs={format:'schema6-mcp-config-switch-static-inputs-v1',core,fromArtifacts,candidate,oldTaskName,newTaskName,toArtifacts:Object.values(to).map(a=>({...a,sha256:a.sha256??null})),outputDirectory,reviewXml:review,productionApproved:false,registrationAllowed:false,deploymentReady:false,fixedPrepareExecuted:false};
 writeNew(path.join(outputDirectory,'static-inputs.json'),staticInputs);
 writeNew(path.join(outputDirectory,'configuration-diff-safe.json'),{format:'schema6-mcp-config-switch-safe-diff-v1',coreUnchanged:true,coreConfigurationMoved:false,nodeUnchanged:true,mcpChangedFields:['working_directory','entrypoint','source_files','environment.I_REMOTE_MCP_CHATGPT_ENABLED'],sourceFiles:6,changedFiles:3,unchangedFiles:3,preservedEntries:10,loginChangedFields:['mcp_configuration_path','mcp_configuration_sha256','backup_configuration_path','backup_configuration_sha256'],cyclicTemplateHashesPreserved:true,fixedPrepareExecuted:false,databaseRead:false,credentialFilesRead:false,productionApproved:false,registrationAllowed:false,deploymentReady:false});
 // Source artifacts are re-anchored after output, preserving evidence on failure.
 artifactMap(fromArtifacts);validateCandidate(candidate,old);readCore(core);
 return {generated:true,staticInputsPath:path.join(outputDirectory,'static-inputs.json'),staticInputsSha256:hash(path.join(outputDirectory,'static-inputs.json')),loginPath:to.login.path,loginSha256:to.login.sha256,outputXmlPath:to.task.path,fixedPrepareExecuted:false,productionApproved:false,registrationAllowed:false,deploymentReady:false};
}
export function finalizeMcpConfigSwitch(staticInputs){
 exact(staticInputs,['format','core','fromArtifacts','candidate','oldTaskName','newTaskName','toArtifacts','outputDirectory','reviewXml','productionApproved','registrationAllowed','deploymentReady','fixedPrepareExecuted']);
 need(staticInputs.format==='schema6-mcp-config-switch-static-inputs-v1'&&['productionApproved','registrationAllowed','deploymentReady','fixedPrepareExecuted'].every(k=>staticInputs[k]===false),'static_inputs');
 const {core,fromArtifacts,candidate,oldTaskName,newTaskName,outputDirectory}=staticInputs;lexical(outputDirectory);
 const toArtifacts=staticInputs.toArtifacts.map(a=>a.role==='task'?{...a,sha256:hash(a.path)}:a);
 const names={mcp:'mcp.json',backup:'daily-backup-config.json',login:'login.json',task:'login-task.prepared.xml'};
 for(const a of toArtifacts)need(a.path===path.join(outputDirectory,names[a.role]??''),'static_output');
 const proposal={format:'schema6-mcp-config-switch-v1',core,fromArtifacts,toArtifacts,candidate,oldTaskName,newTaskName};
 backupFileAcl(toArtifacts.find(a=>a.role==='backup').path);
 const report=validateMcpConfigSwitch(proposal),ref=writeNew(path.join(outputDirectory,'proposal.json'),proposal);
 return {...report,proposalPath:ref.path,proposalSha256:ref.sha256,fixedPrepareReceiptRequired:true};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
 try{const a=process.argv.slice(2);need(a.length===4&&['--input','--finalize'].includes(a[0])&&a[2]==='--input-sha256','usage');const input=jsonRef({path:path.resolve(a[1]),sha256:a[3]});console.log(JSON.stringify(a[0]==='--finalize'?finalizeMcpConfigSwitch(input):generateMcpConfigSwitch(input)));}
 catch(e){console.log(JSON.stringify({generated:false,productionApproved:false,registrationAllowed:false,deploymentReady:false,code:/^mcp_switch_[a-z_]+$/.test(e?.code??'')?e.code:'mcp_switch_generation_rejected'}));process.exitCode=2;}
}
