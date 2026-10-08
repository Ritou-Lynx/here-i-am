// Read-only deployment bindings. This proves source/configuration consistency;
// Supplied protected configuration can contain inline secrets; no values are emitted.
// No database or separate key/credential file is opened, and no task is run.
import path from 'node:path';
import {readFileSync,readdirSync,lstatSync} from 'node:fs';
import {plainPath,sha256,PINNED_NODE_SHA256} from '../release_schema6/package.mjs';
import {verifySwitchRelease} from '../release_schema6/package_switch.mjs';
import {parseConfiguration} from '../release_schema6/lifecycle/configuration.mjs';
import {backupFilePrimitives} from '../release_schema6/backup_bundle.mjs';

const roles=['backup','login','mcp','task'];
const hex=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const object=x=>x!==null&&typeof x==='object'&&!Array.isArray(x);
const canonical=x=>Array.isArray(x)?x.map(canonical):object(x)?Object.fromEntries(Object.keys(x).sort().map(k=>[k,canonical(x[k])])):x;
const same=(a,b)=>JSON.stringify(canonical(a))===JSON.stringify(canonical(b));
function fail(code){throw Object.assign(new Error('switch_bindings_'+code),{code:'switch_bindings_'+code});}
function requireValue(value,code){if(!value)fail(code);}
function exact(value,keys,code){requireValue(object(value)&&same(Object.keys(value).sort(),[...keys].sort()),code);}
function lexical(p){
 requireValue(typeof p==='string'&&path.isAbsolute(p)&&path.normalize(p)===p&&!p.includes(':',2)&&!/[\0\r\n"]/.test(p),'path_invalid');
 return p;
}
function bytes(p,max=1024*1024){
 plainPath(lexical(p));requireValue(lstatSync(p).isFile()&&lstatSync(p).nlink===1&&lstatSync(p).size<=max,'file_invalid');
 return readFileSync(p);
}
function anchored(p,hash,max){requireValue(hex(hash),'anchor_invalid');const raw=bytes(p,max);requireValue(sha256(raw)===hash,'anchor_changed');return raw;}
function json(p,hash){return JSON.parse(anchored(p,hash).toString('utf8').replace(/^\uFEFF/,''));}
function without(value,keys){return Object.fromEntries(Object.entries(value).filter(([k])=>!keys.includes(k)));}
function artifacts(list){
 requireValue(Array.isArray(list)&&same(list.map(a=>a?.role).sort(),roles),'artifacts_required');
 return Object.fromEntries(list.map(a=>{exact(a,['role','path','sha256'],'artifact_invalid');anchored(a.path,a.sha256);return [a.role,a];}));
}
function scan(root,relative=''){
 plainPath(root);
 return readdirSync(path.join(root,relative),{withFileTypes:true}).flatMap(e=>{
  const name=relative?relative+'/'+e.name:e.name,p=plainPath(path.join(root,name));
  if(e.isDirectory())return scan(root,name);
  requireValue(e.isFile()&&lstatSync(p).nlink===1,'mcp_inventory_invalid');return [name];
 }).sort();
}
function core(end){
 exact(end,['releaseDirectory','manifestSha256','configurationPath','configurationSha256'],'endpoint_invalid');
 verifySwitchRelease(end.releaseDirectory,end.manifestSha256);
 const c=json(end.configurationPath,end.configurationSha256);
 lexical(c.database_path);
 requireValue(/^S-1-(?:[0-9]+-)*[0-9]+$/.test(c.owner_sid??''),'core_owner_invalid');
 parseConfiguration(c,{manifest_sha256:end.manifestSha256,database_path:c.database_path,node_id:c.node_id,owner_sid:c.owner_sid});
 for(const key of ['grants_path','approvals_path','recovery_custody_directory','recovery_key_path'])lexical(c[key]);
 requireValue(!!c.backup_directory===!!c.backup_key_path,'core_backup_invalid');
 for(const key of ['backup_directory','backup_key_path'])if(c[key])lexical(c[key]);
 return c;
}
function login(end,c,a){
 const l=json(a.login.path,a.login.sha256);
 exact(l,['format','owner_sid','release_directory','manifest_sha256','state_directory','control_root','core_configuration_path','core_configuration_sha256','core_port','backup_configuration_path','backup_configuration_sha256','backup_key_directory','backup_interval_seconds','mcp_configuration_path','mcp_configuration_sha256'],'login_invalid');
 requireValue(l.format==='schema6-login-v1'&&l.owner_sid===c.owner_sid&&l.release_directory===end.releaseDirectory&&l.manifest_sha256===end.manifestSha256,'login_binding_changed');
 requireValue(l.core_configuration_path===end.configurationPath&&l.core_configuration_sha256===end.configurationSha256&&path.join(l.state_directory,'i-core.sqlite')===c.database_path,'login_core_changed');
 requireValue(Number.isInteger(l.core_port)&&l.core_port>0&&l.core_port<=65535&&Number.isInteger(l.backup_interval_seconds)&&l.backup_interval_seconds>=10&&l.backup_interval_seconds<=86400,'login_policy_invalid');
 for(const key of ['state_directory','control_root','backup_key_directory'])lexical(l[key]);
 for(const role of ['backup','mcp'])requireValue(l[role+'_configuration_path']===a[role].path&&l[role+'_configuration_sha256']===a[role].sha256,'login_artifact_changed');
 return l;
}
function mcp(c,l,a){
 const m=json(a.mcp.path,a.mcp.sha256);
 exact(m,['format','owner_sid','executable_path','executable_sha256','working_directory','entrypoint','source_files','arguments','environment','database_path','listen_host','listen_port','grace_ms'],'mcp_invalid');
 requireValue(m.format==='schema6-mcp-v1'&&m.owner_sid===l.owner_sid&&m.database_path===c.database_path&&m.listen_host==='127.0.0.1','mcp_binding_changed');
 requireValue(Number.isInteger(m.listen_port)&&m.listen_port>0&&m.listen_port<=65535&&m.listen_port!==l.core_port&&Number.isInteger(m.grace_ms)&&m.grace_ms>=0&&m.grace_ms<=3000,'mcp_policy_invalid');
 requireValue(m.executable_sha256===PINNED_NODE_SHA256,'mcp_runtime_changed');
 anchored(m.executable_path,m.executable_sha256,256*1024*1024);
 lexical(m.working_directory);
 requireValue(Array.isArray(m.source_files)&&m.source_files.length>0,'mcp_inventory_invalid');
 const names=[];
 for(const entry of m.source_files){
  exact(entry,['path','sha256'],'mcp_inventory_invalid');
  requireValue(typeof entry.path==='string'&&/^[A-Za-z0-9_./-]+$/.test(entry.path)&&!entry.path.includes('..')&&!entry.path.startsWith('/')&&!entry.path.endsWith('/')&&!names.includes(entry.path),'mcp_inventory_invalid');
  names.push(entry.path);anchored(path.join(m.working_directory,entry.path),entry.sha256,16*1024*1024);
 }
 requireValue(names.includes(m.entrypoint)&&same(names.sort(),scan(m.working_directory)),'mcp_inventory_invalid');
 requireValue(Array.isArray(m.arguments)&&m.arguments.every(s=>typeof s==='string'&&!/["\0\r\n]/.test(s)&&!s.endsWith('\\')&&!/^--(core-db|core-url|host|port|state-dir|memory-db|policy)(=|$)/.test(s)),'mcp_arguments_invalid');
 requireValue(object(m.environment),'mcp_environment_invalid');
 for(const [k,v] of Object.entries(m.environment))requireValue(/^(I_|SCHEMA6_TEST_)[A-Z0-9_]+$/.test(k)&&!['I_CORE_DB','I_CORE_URL','I_REMOTE_MCP_HOST','I_REMOTE_MCP_PORT'].includes(k)&&typeof v==='string'&&!v.includes('\0'),'mcp_environment_invalid');
 for(const k of ['I_REMOTE_MCP_STATE_DIR','I_MEMORY_DB','I_MEMORY_POLICY','I_HOME'])lexical(m.environment[k]);
 return m;
}
const taskTemplate='<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><Triggers><LogonTrigger><Enabled>true</Enabled><UserId /></LogonTrigger></Triggers><Principals><Principal id="Owner"><UserId /><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals><Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><AllowHardTerminate>false</AllowHardTerminate><StartWhenAvailable>true</StartWhenAvailable><Enabled>true</Enabled><Hidden>true</Hidden><UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine><ExecutionTimeLimit>PT0S</ExecutionTimeLimit></Settings><Actions Context="Owner"><Exec><Command /><Arguments /></Exec></Actions></Task>';
const escapeXml=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
function task(end,l,a){
 const ps=path.join(process.env.SystemRoot??'', 'System32','WindowsPowerShell','v1.0','powershell.exe');
 lexical(ps);
 const args=['-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',path.join(end.releaseDirectory,'tools/i_core/release_schema6/lifecycle/login_schema6.ps1'),'-ReleaseDirectory',end.releaseDirectory,'-ManifestSha256',end.manifestSha256,'-LoginConfigurationPath',a.login.path,'-LoginConfigurationSha256',a.login.sha256];
 requireValue(args.every(s=>typeof s==='string'&&!/["\0\r\n]/.test(s)&&!s.endsWith('\\')),'task_arguments_invalid');
 const expected=taskTemplate.replaceAll('<UserId />','<UserId>'+escapeXml(l.owner_sid)+'</UserId>').replace('<Command />','<Command>'+escapeXml(ps)+'</Command>').replace('<Arguments />','<Arguments>'+escapeXml(args.map(s=>'"'+s+'"').join(' '))+'</Arguments>');
 let xml=anchored(a.task.path,a.task.sha256).toString('utf8').replace(/^\uFEFF/,'').trim();
 xml=xml.replace(/^<\?xml version="1\.0" encoding="utf-8"\?>\s*/i,'').replace(/>\s+</g,'><');
 requireValue(xml===expected,'task_xml_changed');
}
function backup(end,c,a){
 const b=json(a.backup.path,a.backup.sha256);
 exact(b,['policy','specTemplate','sqliteEntryNames','envelopePath','envelopeSha256'],'backup_invalid');
 const policy=b.policy;
 requireValue(object(policy)&&Object.keys(policy).every(k=>['format','outputRoot','retentionDays','mirrorRoot','backupSetId'].includes(k))&&policy.format==='i-core-automatic-backup-v1'&&hex(policy.backupSetId)&&Number.isInteger(policy.retentionDays??30)&&(policy.retentionDays??30)>=1&&(policy.retentionDays??30)<=3650,'backup_policy_invalid');
 lexical(policy.outputRoot);if(policy.mirrorRoot)lexical(policy.mirrorRoot);
 lexical(b.envelopePath);requireValue(hex(b.envelopeSha256),'backup_envelope_invalid');
 const spec=b.specTemplate;requireValue(object(spec),'backup_invalid');
 requireValue(spec.source_schema===6&&spec.canonical_database_path===c.database_path&&(c.node_id==='new'||spec.node_id===c.node_id)&&spec.old_release_root===end.releaseDirectory&&spec.old_release_manifest_sha256===end.manifestSha256,'backup_binding_changed');
 backupFilePrimitives.validate(spec);
 const manifest=json(path.join(end.releaseDirectory,'manifest.json'),end.manifestSha256);
 const expected=new Map(manifest.files.map(f=>[f.path,f.sha256]));expected.set('manifest.json',end.manifestSha256);
 const releaseEntries=spec.entries.filter(e=>e.role==='release');
 requireValue(same(releaseEntries.map(e=>e.name).sort(),[...expected.keys()].sort()),'backup_inventory_changed');
 for(const entry of releaseEntries)requireValue(entry.source_path===path.join(end.releaseDirectory,entry.name)&&entry.sha256===expected.get(entry.name)&&!entry.state&&!entry.custody_context,'backup_inventory_changed');
 requireValue(Array.isArray(b.sqliteEntryNames)&&new Set(b.sqliteEntryNames).size===b.sqliteEntryNames.length&&b.sqliteEntryNames.every(n=>spec.entries.some(e=>e.name===n&&['database','configuration'].includes(e.role))),'backup_sqlite_inventory_invalid');
 return b;
}
function compareBackup(from,to,oldEnd,newEnd,oldArtifacts,newArtifacts){
 requireValue(same(without(from,['specTemplate']),without(to,['specTemplate'])),'backup_policy_changed');
 requireValue(same(without(from.specTemplate,['entries','old_release_root','old_release_manifest_sha256']),without(to.specTemplate,['entries','old_release_root','old_release_manifest_sha256'])),'backup_scope_changed');
 const rebound=new Map([[oldEnd.configurationPath,{path:newEnd.configurationPath,sha256:newEnd.configurationSha256}]]);
 for(const role of roles)rebound.set(oldArtifacts[role].path,newArtifacts[role]);
 const oldEntries=from.specTemplate.entries.filter(e=>e.role!=='release').sort((a,b)=>a.name.localeCompare(b.name));
 const newEntries=to.specTemplate.entries.filter(e=>e.role!=='release').sort((a,b)=>a.name.localeCompare(b.name));
 requireValue(oldEntries.length===newEntries.length,'backup_scope_changed');
 for(let i=0;i<oldEntries.length;i++){
  const old=oldEntries[i],next=newEntries[i],mapping=rebound.get(old.source_path);
  if(!mapping){requireValue(same(old,next),'backup_scope_changed');continue;}
  // Online capture replaces mutable entry hashes. Keep an old template hash or
  // use the target's known hash; never demand a cyclic login<->backup digest.
  requireValue(same(without(old,['source_path','sha256']),without(next,['source_path','sha256']))&&next.source_path===mapping.path&&[old.sha256,mapping.sha256].includes(next.sha256),'backup_scope_changed');
 }
}
export function validatePackageSwitchBindings(plan,{fromArtifacts}={}){
 try{
  requireValue(object(plan)&&object(plan.from)&&object(plan.to),'plan_invalid');
  requireValue(plan.from.releaseDirectory!==plan.to.releaseDirectory&&plan.from.manifestSha256!==plan.to.manifestSha256,'distinct_packages_required');
  const oldArtifacts=artifacts(fromArtifacts),newArtifacts=artifacts(plan.artifacts);
  const oldCore=core(plan.from),newCore=core(plan.to);
  requireValue(same(without(oldCore,['manifest_sha256']),without(newCore,['manifest_sha256'])),'core_policy_changed');
  const oldLogin=login(plan.from,oldCore,oldArtifacts),newLogin=login(plan.to,newCore,newArtifacts);
  const reboundLogin=['release_directory','manifest_sha256','core_configuration_path','core_configuration_sha256','backup_configuration_path','backup_configuration_sha256','mcp_configuration_path','mcp_configuration_sha256'];
  requireValue(same(without(oldLogin,reboundLogin),without(newLogin,reboundLogin)),'login_policy_changed');
  const oldMcp=mcp(oldCore,oldLogin,oldArtifacts),newMcp=mcp(newCore,newLogin,newArtifacts);
  const relocated=oldMcp.executable_path===path.join(plan.from.releaseDirectory,'runtime/node.exe')&&newMcp.executable_path===path.join(plan.to.releaseDirectory,'runtime/node.exe');
  requireValue(oldMcp.executable_path===newMcp.executable_path||relocated,'mcp_runtime_changed');
  requireValue(same(without(oldMcp,['executable_path']),without(newMcp,['executable_path'])),'mcp_program_or_policy_changed');
  task(plan.from,oldLogin,oldArtifacts);task(plan.to,newLogin,newArtifacts);
  const oldBackup=backup(plan.from,oldCore,oldArtifacts),newBackup=backup(plan.to,newCore,newArtifacts);
  compareBackup(oldBackup,newBackup,plan.from,plan.to,oldArtifacts,newArtifacts);
  return {format:'schema6-package-switch-bindings-v1',validated:true,approved:false,deploymentReady:false,corePolicyPreserved:true,loginPolicyPreserved:true,mcpProgramAndPolicyPreserved:true,backupReleaseInventoryBound:true,backupPolicyPreserved:true,taskXmlBound:true,credentialFilesRead:false,databaseRead:false,registered:false,started:false};
 }catch(error){
  if(typeof error?.code==='string'&&/^switch_bindings_[a-z_]+$/.test(error.code))throw error;
  fail('input_rejected');
 }
}
