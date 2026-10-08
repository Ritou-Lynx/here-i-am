// Candidate-only, reproducible configuration generation. No DB/key reads, task
// operations, service changes, XML fabrication or production activation.
import {existsSync,mkdirSync,readFileSync,writeFileSync,openSync,fsyncSync,closeSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {plainPath,sha256,verifyRelease} from '../release_schema6/package.mjs';
import {backupFilePrimitives as f} from '../release_schema6/backup_bundle.mjs';
import {buildPackageSwitchBackupTemplate} from './package-switch-bindings.mjs';

const HASH=/^[a-f0-9]{64}$/;
const fail=code=>{throw Object.assign(new Error(code),{code});};
const changedKeys=(a,b)=>[...new Set([...Object.keys(a),...Object.keys(b)])].filter(k=>JSON.stringify(a[k])!==JSON.stringify(b[k]));
const hash=p=>sha256(readFileSync(plainPath(p)));
function load(p,anchor){
 if(!HASH.test(anchor??''))fail('configuration_generation_anchor_required');
 f.safe(p);const bytes=readFileSync(p);if(bytes.length>1024*1024||sha256(bytes)!==anchor)fail('configuration_generation_anchor_changed');
 try{return JSON.parse(bytes.toString('utf8').replace(/^\uFEFF/,''));}catch{fail('configuration_generation_json_rejected');}
}
function writeNew(p,value){
 plainPath(p,{missing:true});const b=Buffer.from(JSON.stringify(value,null,2)+'\n');
 const fd=openSync(p,'wx',0o600);try{writeFileSync(fd,b);fsyncSync(fd);}finally{closeSync(fd);}
 f.safe(p);
}
function newDirectory(p){f.safe(path.dirname(p),true);plainPath(p,{missing:true});if(existsSync(p))fail('configuration_generation_fresh_output_required');mkdirSync(p);f.protect(p);f.safe(p,true);}
function same(a,b){return JSON.stringify(a)===JSON.stringify(b);}
function separateOutput(output,forbidden){
 const normalized=p=>path.resolve(p).toLowerCase();
 const inside=(a,b)=>{const r=path.relative(b,a);return r===''||(!path.isAbsolute(r)&&r!=='..'&&!r.startsWith('..'+path.sep));};
 for(const p of forbidden){
  if(typeof p!=='string'||!path.isAbsolute(p)||path.normalize(p)!==p)fail('configuration_generation_path_rejected');
  if(inside(normalized(output),normalized(p))||inside(normalized(p),normalized(output)))fail('configuration_generation_output_not_independent');
 }
}

export function generatePackageSwitchConfigurations(input){
 const keys=['oldLoginPath','oldLoginSha256','newReleaseDirectory','newManifestSha256','outputDirectory','oldTaskXmlPath','taskName','oldTaskName'];
 if(!input||Object.keys(input).sort().join('|')!==keys.sort().join('|'))fail('configuration_generation_input_rejected');
 const {oldLoginPath,oldLoginSha256,newReleaseDirectory,newManifestSha256,outputDirectory,oldTaskXmlPath,taskName,oldTaskName}=input;
 for(const p of [oldLoginPath,newReleaseDirectory,oldTaskXmlPath,outputDirectory]){
  if(typeof p!=='string'||!path.isAbsolute(p)||path.normalize(p)!==p||/[\0\r\n"]/.test(p))fail('configuration_generation_path_rejected');
 }
 for(const name of [taskName,oldTaskName])if(typeof name!=='string'||!/^[A-Za-z0-9][A-Za-z0-9_.-]{0,180}$/.test(name))fail('configuration_generation_task_name_rejected');
 if(taskName===oldTaskName)fail('configuration_generation_distinct_task_required');
 if(!HASH.test(newManifestSha256??''))fail('configuration_generation_anchor_required');
 const originalLogin=load(oldLoginPath,oldLoginSha256),l=structuredClone(originalLogin);
 if(l.format!=='schema6-login-v1')fail('configuration_generation_login_rejected');
 const originalCore=load(l.core_configuration_path,l.core_configuration_sha256),core=structuredClone(originalCore);
 const originalBackup=load(l.backup_configuration_path,l.backup_configuration_sha256);
 const originalMcp=load(l.mcp_configuration_path,l.mcp_configuration_sha256);
 const attachmentPaths=[[l.core_configuration_path,'configuration'],[oldLoginPath,'configuration'],[l.backup_configuration_path,'configuration'],[oldTaskXmlPath,'task']];
 for(const [p,role] of attachmentPaths){
  const entries=originalBackup.specTemplate?.entries?.filter(e=>e.source_path===p);
  if(entries?.length!==1||entries[0].role!==role||entries[0].state==='disabled')fail('configuration_generation_attachment_required');
 }
 // A candidate cannot be nested into state, keys, packages, live configuration,
 // source or backup directories, including a previously absent child. Validate
 // every input and the complete target inventory before the first mkdir/ACL.
 f.safe(path.dirname(outputDirectory),true);
 separateOutput(outputDirectory,[l.release_directory,newReleaseDirectory,l.state_directory,l.control_root,l.backup_key_directory,
  originalCore.recovery_custody_directory,path.dirname(originalCore.recovery_key_path),path.dirname(originalCore.grants_path),path.dirname(originalCore.approvals_path),
  ...(originalCore.backup_directory?[originalCore.backup_directory]:[]),...(originalCore.backup_key_path?[path.dirname(originalCore.backup_key_path)]:[]),
  originalBackup.policy.outputRoot,...(originalBackup.policy.mirrorRoot?[originalBackup.policy.mirrorRoot]:[]),path.dirname(originalBackup.envelopePath),
  originalMcp.working_directory,originalMcp.environment.I_REMOTE_MCP_STATE_DIR,originalMcp.environment.I_HOME,path.dirname(originalMcp.environment.I_MEMORY_DB),path.dirname(originalMcp.environment.I_MEMORY_POLICY),
  ...[oldLoginPath,l.core_configuration_path,l.backup_configuration_path,l.mcp_configuration_path,oldTaskXmlPath].map(p=>path.dirname(p))]);
 verifyRelease(newReleaseDirectory,newManifestSha256);
 const anchors=[oldLoginPath,l.core_configuration_path,l.backup_configuration_path,l.mcp_configuration_path,oldTaskXmlPath,path.join(l.release_directory,'manifest.json')].map(p=>({path:p,sha256:hash(p)}));
 // A fresh output is mandatory. Failure retains candidate evidence; no input is
 // overwritten and retry must name a different output directory.
 const settings=path.join(outputDirectory,'settings');
 const cp=path.join(settings,'core.json'),bp=path.join(settings,'daily-backup-config.json'),lp=path.join(settings,'login.json'),xp=path.join(outputDirectory,'login-task.prepared.xml');
 const from={releaseDirectory:l.release_directory,manifestSha256:l.manifest_sha256,configurationPath:l.core_configuration_path,configurationSha256:l.core_configuration_sha256};
 core.manifest_sha256=newManifestSha256;
 const coreSha256=sha256(Buffer.from(JSON.stringify(core,null,2)+'\n'));
 const to={releaseDirectory:newReleaseDirectory,manifestSha256:newManifestSha256,configurationPath:cp,configurationSha256:coreSha256};
 const backup=buildPackageSwitchBackupTemplate(originalBackup,{from,to});
 newDirectory(outputDirectory);newDirectory(settings);writeNew(cp,core);
 const rebound=new Map([[l.core_configuration_path,{path:cp,sha256:hash(cp)}],[oldLoginPath,{path:lp}],[l.backup_configuration_path,{path:bp}],[oldTaskXmlPath,{path:xp}]]);
 backup.specTemplate.entries=backup.specTemplate.entries.map(e=>{
  const mapping=rebound.get(e.source_path);return mapping?{...e,source_path:mapping.path,sha256:mapping.sha256??e.sha256}:e;
 });
 f.validate(backup.specTemplate);
 writeNew(bp,backup);
 l.release_directory=newReleaseDirectory;l.manifest_sha256=newManifestSha256;l.core_configuration_path=cp;l.core_configuration_sha256=hash(cp);l.backup_configuration_path=bp;l.backup_configuration_sha256=hash(bp);writeNew(lp,l);
 const coreChanges=changedKeys(originalCore,core),loginChanges=changedKeys(originalLogin,l);
 if(!same(coreChanges,['manifest_sha256'])||!same([...loginChanges].sort(),['release_directory','manifest_sha256','core_configuration_path','core_configuration_sha256','backup_configuration_path','backup_configuration_sha256'].sort()))fail('configuration_generation_policy_changed');
 const originalNonrelease=originalBackup.specTemplate.entries.filter(e=>e.role!=='release');
 const preserved=backup.specTemplate.entries.filter(e=>e.name.startsWith('preserved/legacy-v4-release/'));
 const info={format:'schema6-static-approval-inputs-v1',productionApproved:false,registrationAllowed:false,deploymentReady:false,
  sourceRoot:path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..'),releaseDirectory:newReleaseDirectory,manifestSha256:newManifestSha256,
  oldReleaseDirectory:from.releaseDirectory,oldManifestSha256:from.manifestSha256,oldLoginPath,oldTaskXml:oldTaskXmlPath,oldSourceAnchors:anchors,
  corePath:cp,backupPath:bp,loginPath:lp,loginSha256:hash(lp),mcpPath:l.mcp_configuration_path,mcpSha256:l.mcp_configuration_sha256,preparedXml:xp,taskName,oldTaskName};
 const safeDiff={format:'schema6-production-safe-diff-v2',coreChangedFields:coreChanges,loginChangedFields:loginChanges,mcpConfigurationUnchanged:l.mcp_configuration_path===originalLogin.mcp_configuration_path&&l.mcp_configuration_sha256===originalLogin.mcp_configuration_sha256,
  backupPolicyUnchanged:same(originalBackup.policy,backup.policy),backupOutsideSpecUnchanged:same({...originalBackup,specTemplate:null},{...backup,specTemplate:null}),backupSpecChangedFields:changedKeys(originalBackup.specTemplate,backup.specTemplate),
  originalNonreleaseCount:originalNonrelease.length,newReleaseCount:backup.specTemplate.entries.filter(e=>e.role==='release').length,
  oldReleaseCount:originalBackup.specTemplate.entries.filter(e=>e.role==='release').length,preservedLegacyCount:preserved.length,
  preservedLegacyEntries:preserved.map(e=>({role:e.role,name:e.name,source_path:e.source_path,sha256:e.sha256})),
  reboundNonreleaseEntries:originalNonrelease.filter(e=>rebound.has(e.source_path)).map(e=>({name:e.name,changedFields:changedKeys(e,backup.specTemplate.entries.find(v=>v.name===e.name))})),
  cyclicTemplateHashesPreserved:true,fixedPrepareExecuted:false,databaseRead:false,separateCredentialFilesRead:false,oldConfigurationWritten:false};
 if(safeDiff.reboundNonreleaseEntries.length!==4)fail('configuration_generation_attachment_required');
 if(!safeDiff.mcpConfigurationUnchanged||!safeDiff.backupPolicyUnchanged||!safeDiff.backupOutsideSpecUnchanged)fail('configuration_generation_policy_changed');
 for(const a of anchors)if(hash(a.path)!==a.sha256)fail('configuration_generation_source_changed');
 writeNew(path.join(outputDirectory,'static-inputs.json'),info);writeNew(path.join(outputDirectory,'configuration-diff-safe.json'),safeDiff);
 return {generated:true,productionApproved:false,registrationAllowed:false,deploymentReady:false,configurationCount:3,mcpConfigurationUnchanged:true,preservedLegacyCount:preserved.length,newReleaseCount:safeDiff.newReleaseCount,fixedPrepareExecuted:false,databaseRead:false,separateCredentialFilesRead:false};
}

if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
 try{
  const args=process.argv.slice(2);if(args.length!==4||args[0]!=='--input'||args[2]!=='--input-sha256')fail('configuration_generation_usage');
  const result=generatePackageSwitchConfigurations(load(path.resolve(args[1]),args[3]));process.stdout.write(JSON.stringify(result)+'\n');
 }catch(error){const code=/^configuration_generation_[a-z_]+$/.test(error.code??'')?error.code:'configuration_generation_rejected';process.stdout.write(JSON.stringify({generated:false,productionApproved:false,deploymentReady:false,code})+'\n');process.exitCode=2;}
}
