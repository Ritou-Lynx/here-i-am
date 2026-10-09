// Candidate-only bindings. Reads anchored configuration/source bytes, never databases or keys.
import path from 'node:path';
import {readFileSync,readdirSync,lstatSync} from 'node:fs';
import {verifyRelease,plainPath,sha256,PINNED_NODE_SHA256} from '../release_schema6/package.mjs';
import {parseConfiguration} from '../release_schema6/lifecycle/configuration.mjs';
import {backupFilePrimitives as f} from '../release_schema6/backup_bundle.mjs';

export const MCP_SOURCE_NAMES=Object.freeze(['i_remote_mcp/server.mjs','i_remote_mcp/oauth.mjs','i_remote_mcp/diagnostics.mjs','i_remote_mcp/mcp.mjs','i_remote_mcp/writeback.mjs','i_memory/i_memory_read.mjs']);
const CHANGED=['i_remote_mcp/server.mjs','i_remote_mcp/oauth.mjs','i_remote_mcp/mcp.mjs'];
const FLAG='I_REMOTE_MCP_CHATGPT_ENABLED';
export const PRESERVED_PREFIX='preserved/mcp-config-switch-source/';
const roles=['backup','login','mcp','task'];
const object=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
const canonical=v=>Array.isArray(v)?v.map(canonical):object(v)?Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonical(v[k])])):v;
export const same=(a,b)=>JSON.stringify(canonical(a))===JSON.stringify(canonical(b));
const without=(v,keys)=>Object.fromEntries(Object.entries(v).filter(([k])=>!keys.includes(k)));
export function need(v,code){if(!v)throw Object.assign(new Error('mcp_switch_'+code),{code:'mcp_switch_'+code});}
export function exact(v,keys,code='shape'){need(object(v)&&same(Object.keys(v).sort(),[...keys].sort()),code);}
const hex=v=>typeof v==='string'&&/^[a-f0-9]{64}$/.test(v);
export function lexical(p){need(typeof p==='string'&&path.isAbsolute(p)&&path.normalize(p)===p&&!p.includes(':',2)&&!/[\0\r\n"]/.test(p),'path');return p;}
export function anchored(p,h,max=1024*1024){lexical(p);plainPath(p);const s=lstatSync(p);need(s.isFile()&&s.nlink===1&&s.size<=max&&hex(h),'file');const b=readFileSync(p);need(sha256(b)===h,'anchor');return b;}
export const jsonRef=r=>JSON.parse(anchored(r.path,r.sha256).toString('utf8').replace(/^\uFEFF/,''));
export function artifactMap(list){need(Array.isArray(list)&&same(list.map(a=>a?.role).sort(),roles),'artifacts');return Object.fromEntries(list.map(a=>{exact(a,['role','path','sha256']);anchored(a.path,a.sha256);return [a.role,a];}));}
function scan(root,relative=''){plainPath(root);return readdirSync(path.join(root,relative),{withFileTypes:true}).flatMap(e=>{const n=relative?relative+'/'+e.name:e.name,p=plainPath(path.join(root,n));if(e.isDirectory())return scan(root,n);need(e.isFile()&&lstatSync(p).nlink===1,'inventory');return [n];}).sort();}
export function independent(a,b){a=lexical(a).toLowerCase();b=lexical(b).toLowerCase();const nested=(x,y)=>{const r=path.relative(y,x);return r===''||(!path.isAbsolute(r)&&r!=='..'&&!r.startsWith('..'+path.sep));};need(!nested(a,b)&&!nested(b,a),'overlap');}
export function readCore(core){
 exact(core,['releaseDirectory','manifestSha256','configurationPath','configurationSha256']);
 lexical(core.releaseDirectory);const release=verifyRelease(core.releaseDirectory,core.manifestSha256);need(release.files===48,'core_inventory');
 const c=jsonRef({path:core.configurationPath,sha256:core.configurationSha256});
 parseConfiguration(c,{manifest_sha256:core.manifestSha256,database_path:c.database_path,node_id:c.node_id,owner_sid:c.owner_sid});
 need(/^S-1-(?:[0-9]+-)*[0-9]+$/.test(c.owner_sid),'owner');lexical(c.database_path);for(const k of ['grants_path','approvals_path','recovery_custody_directory','recovery_key_path'])lexical(c[k]);
 return c;
}
export function readLogin(core,c,a){
 const l=jsonRef(a.login);exact(l,['format','owner_sid','release_directory','manifest_sha256','state_directory','control_root','core_configuration_path','core_configuration_sha256','core_port','backup_configuration_path','backup_configuration_sha256','backup_key_directory','backup_interval_seconds','mcp_configuration_path','mcp_configuration_sha256']);
 need(l.format==='schema6-login-v1'&&l.owner_sid===c.owner_sid&&l.release_directory===core.releaseDirectory&&l.manifest_sha256===core.manifestSha256&&l.core_configuration_path===core.configurationPath&&l.core_configuration_sha256===core.configurationSha256&&path.join(l.state_directory,'i-core.sqlite')===c.database_path,'login_core');
 for(const r of ['mcp','backup'])need(l[r+'_configuration_path']===a[r].path&&l[r+'_configuration_sha256']===a[r].sha256,'login_artifact');
 need(Number.isInteger(l.core_port)&&l.core_port>0&&l.core_port<=65535&&Number.isInteger(l.backup_interval_seconds)&&l.backup_interval_seconds>=10&&l.backup_interval_seconds<=86400,'login_policy');
 for(const k of ['state_directory','control_root','backup_key_directory'])lexical(l[k]);return l;
}
export function readMcp(c,l,ref){
 const m=jsonRef(ref);exact(m,['format','owner_sid','executable_path','executable_sha256','working_directory','entrypoint','source_files','arguments','environment','database_path','listen_host','listen_port','grace_ms']);
 need(m.format==='schema6-mcp-v1'&&m.owner_sid===c.owner_sid&&m.database_path===c.database_path&&m.listen_host==='127.0.0.1','mcp_binding');
 need(Number.isInteger(m.listen_port)&&m.listen_port>0&&m.listen_port<=65535&&m.listen_port!==l.core_port&&Number.isInteger(m.grace_ms)&&m.grace_ms>=0&&m.grace_ms<=3000,'mcp_policy');
 need(m.executable_sha256===PINNED_NODE_SHA256,'node');anchored(m.executable_path,m.executable_sha256,256*1024*1024);
 lexical(m.working_directory);need(Array.isArray(m.source_files),'inventory');
 const names=m.source_files.map(e=>{exact(e,['path','sha256']);need(typeof e.path==='string'&&/^[A-Za-z0-9_./-]+$/.test(e.path)&&!e.path.includes('..')&&!e.path.startsWith('/')&&!e.path.endsWith('/'),'inventory');anchored(path.join(m.working_directory,e.path),e.sha256,16*1024*1024);return e.path;});
 need(new Set(names).size===names.length&&same([...names].sort(),scan(m.working_directory))&&names.includes(m.entrypoint),'inventory');
 need(Array.isArray(m.arguments)&&m.arguments.every(s=>typeof s==='string'&&!/["\0\r\n]/.test(s)&&!s.endsWith('\\')&&!/^--(core-db|core-url|host|port|state-dir|memory-db|policy)(=|$)/.test(s)),'arguments');
 need(object(m.environment),'environment');for(const [k,v] of Object.entries(m.environment))need(/^(I_|SCHEMA6_TEST_)[A-Z0-9_]+$/.test(k)&&!['I_CORE_DB','I_CORE_URL','I_REMOTE_MCP_HOST','I_REMOTE_MCP_PORT'].includes(k)&&typeof v==='string'&&!v.includes('\0'),'environment');
 for(const k of ['I_REMOTE_MCP_STATE_DIR','I_MEMORY_DB','I_MEMORY_POLICY','I_HOME']){lexical(m.environment[k]);independent(m.working_directory,m.environment[k]);}
 for(const p of [l.state_directory,l.control_root])independent(m.working_directory,p);
 return m;
}
export function validateCandidate(candidate,old){
 exact(candidate,['manifestPath','manifestSha256','runtimeDirectory']);lexical(candidate.runtimeDirectory);independent(candidate.runtimeDirectory,old.working_directory);
 const manifest=jsonRef({path:candidate.manifestPath,sha256:candidate.manifestSha256});
 exact(manifest,['schema_version','status','baseline_commit','source_commit','source_prefix','chatgpt_flag','entry','changed_files','unchanged_files','source_sha256','files']);
 need(manifest.schema_version===1&&manifest.status==='not_deployed'&&manifest.baseline_commit==='3ce7aacc75615faf31aab7d4d902598070ffa898'&&manifest.source_commit==='f90058f21049f514f8ab2af407227aee02e2f259'&&manifest.source_prefix==='tools/i_core/test_fixtures/release_schema6/mcp_reader/legacy/'&&manifest.entry==='i_remote_mcp/server.mjs'&&manifest.changed_files===3&&manifest.unchanged_files===3&&same(manifest.chatgpt_flag,{name:FLAG,default:'0'}),'candidate_contract');
 exact(manifest.source_sha256,['server','oauth','mcp']);need(Object.values(manifest.source_sha256).every(hex),'candidate_contract');
 need(Array.isArray(manifest.files)&&same(manifest.files.map(e=>e.path).sort(),[...MCP_SOURCE_NAMES].sort())&&same(scan(candidate.runtimeDirectory),[...MCP_SOURCE_NAMES].sort()),'candidate_inventory');
 need(old.entrypoint==='tools/i_remote_mcp/server.mjs'&&same(old.source_files.map(e=>e.path).sort(),MCP_SOURCE_NAMES.map(n=>'tools/'+n).sort()),'source_inventory');
 for(const e of manifest.files){exact(e,['path','source_blob','base_sha256','result_sha256','bytes','changed']);need(/^[a-f0-9]{40}$/.test(e.source_blob)&&hex(e.base_sha256)&&hex(e.result_sha256)&&Number.isSafeInteger(e.bytes)&&e.bytes>=0&&e.changed===CHANGED.includes(e.path)&&e.changed===(e.base_sha256!==e.result_sha256),'candidate_entry');
 need(old.source_files.find(s=>s.path==='tools/'+e.path).sha256===e.base_sha256,'source_base');
 const b=anchored(path.join(candidate.runtimeDirectory,e.path),e.result_sha256,16*1024*1024);need(b.length===e.bytes,'candidate_bytes');}
 return manifest;
}
export function taskXml(core,l,loginRef){
 const source=anchored(path.join(core.releaseDirectory,'tools/i_core/release_schema6/lifecycle/prepare_login_schema6.ps1'),JSON.parse(readFileSync(path.join(core.releaseDirectory,'manifest.json'))).files.find(e=>e.path==='tools/i_core/release_schema6/lifecycle/prepare_login_schema6.ps1').sha256).toString('utf8');
 const matches=[...source.matchAll(/\$document\.LoadXml\('([^']+)'\)/g)];need(matches.length===1,'task_template');
 const esc=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
 const ps=lexical(path.join(process.env.SystemRoot??'', 'System32','WindowsPowerShell','v1.0','powershell.exe'));
 const args=['-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',path.join(core.releaseDirectory,'tools/i_core/release_schema6/lifecycle/login_schema6.ps1'),'-ReleaseDirectory',core.releaseDirectory,'-ManifestSha256',core.manifestSha256,'-LoginConfigurationPath',loginRef.path,'-LoginConfigurationSha256',loginRef.sha256];
 need(args.every(s=>!/[\0\r\n"]/.test(s)&&!s.endsWith('\\')),'task_arguments');
 return matches[0][1].replaceAll('<UserId />','<UserId>'+esc(l.owner_sid)+'</UserId>').replace('<Command />','<Command>'+esc(ps)+'</Command>').replace('<Arguments />','<Arguments>'+esc(args.map(s=>'"'+s+'"').join(' '))+'</Arguments>');
}
export function validateTask(core,l,a){const normalized=anchored(a.task.path,a.task.sha256).toString('utf8').replace(/^\uFEFF/,'').trim().replace(/^<\?xml version="1\.0" encoding="utf-8"\?>\s*/i,'').replace(/>\s+</g,'><');need(normalized===taskXml(core,l,a.login),'task_xml');}
export function validateBackupBase(b,core,c){
 exact(b,['policy','specTemplate','sqliteEntryNames','envelopePath','envelopeSha256']);f.validate(b.specTemplate);
 need(b.policy?.format==='i-core-automatic-backup-v1'&&hex(b.envelopeSha256),'backup');lexical(b.envelopePath);
 const s=b.specTemplate;need(s.source_schema===6&&s.node_id===c.node_id&&s.canonical_database_path===c.database_path&&s.old_release_root===core.releaseDirectory&&s.old_release_manifest_sha256===core.manifestSha256,'backup_core');
 const release=JSON.parse(readFileSync(path.join(core.releaseDirectory,'manifest.json'))),entries=s.entries.filter(e=>e.role==='release');
 const expected=[...release.files.map(e=>({role:'release',name:e.path,source_path:path.join(core.releaseDirectory,e.path),sha256:e.sha256})),{role:'release',name:'manifest.json',source_path:path.join(core.releaseDirectory,'manifest.json'),sha256:core.manifestSha256}];
 need(same([...entries].sort((a,b)=>a.name.localeCompare(b.name)),expected.sort((a,b)=>a.name.localeCompare(b.name))),'backup_release');
 need(Array.isArray(b.sqliteEntryNames)&&new Set(b.sqliteEntryNames).size===b.sqliteEntryNames.length&&b.sqliteEntryNames.every(n=>s.entries.some(e=>e.name===n&&['database','configuration'].includes(e.role))),'backup_sqlite');
}
export function backupMapping(old,from,to,candidateManifest,candidate){
 const map=new Map();for(const r of roles)map.set(from[r].path,{path:to[r].path,sha256:to[r].sha256,role:r==='task'?'task':'configuration',preserved:r+(r==='task'?'.xml':'.json')});
 for(const e of candidateManifest.files)map.set(path.join(old.working_directory,'tools/'+e.path),{path:path.join(candidate.runtimeDirectory,e.path),sha256:e.result_sha256,oldSha256:e.base_sha256,role:'configuration',preserved:'runtime/tools/'+e.path});
 return map;
}
export function buildMcpSwitchBackup(original,map){
 const b=structuredClone(original),entries=b.specTemplate.entries;need(!entries.some(e=>e.name.toLowerCase().startsWith('preserved/mcp-config-switch-source')||PRESERVED_PREFIX.toLowerCase().startsWith(e.name.toLowerCase()+'/')),'backup_preserved_collision');
 const preserved=[];for(const [p,m] of map){const found=entries.filter(e=>e.source_path===p);need(found.length===1&&found[0].role===m.role&&found[0].state!=='disabled','backup_attachment');const e=found[0];need(!m.oldSha256||e.sha256===m.oldSha256,'backup_source_hash');preserved.push({...e,name:PRESERVED_PREFIX+m.preserved});}
 b.specTemplate.entries=entries.map(e=>{const m=map.get(e.source_path);return m?{...e,source_path:m.path,sha256:m.sha256??e.sha256}:e;}).concat(preserved);f.validate(b.specTemplate);return b;
}
export function validateMcpConfigSwitch(p){
 try{
 exact(p,['format','core','fromArtifacts','toArtifacts','candidate','oldTaskName','newTaskName']);need(p.format==='schema6-mcp-config-switch-v1','format');
 for(const n of [p.oldTaskName,p.newTaskName])need(typeof n==='string'&&/^[A-Za-z0-9][A-Za-z0-9_.-]{0,180}$/.test(n),'task_name');need(p.oldTaskName.toLowerCase()!==p.newTaskName.toLowerCase(),'task_name');
 const c=readCore(p.core),from=artifactMap(p.fromArtifacts),to=artifactMap(p.toArtifacts);
 need(new Set([...roles.map(r=>from[r].path.toLowerCase()),...roles.map(r=>to[r].path.toLowerCase()),p.core.configurationPath.toLowerCase()]).size===9,'artifact_alias');
 const oldLogin=readLogin(p.core,c,from),nextLogin=readLogin(p.core,c,to);
 need(same(without(oldLogin,['mcp_configuration_path','mcp_configuration_sha256','backup_configuration_path','backup_configuration_sha256']),without(nextLogin,['mcp_configuration_path','mcp_configuration_sha256','backup_configuration_path','backup_configuration_sha256'])),'login_policy');
 const old=readMcp(c,oldLogin,from.mcp),next=readMcp(c,nextLogin,to.mcp),manifest=validateCandidate(p.candidate,old);
 need(same(without(old,['working_directory','entrypoint','source_files','environment']),without(next,['working_directory','entrypoint','source_files','environment'])),'mcp_policy');
 need(!Object.hasOwn(old.environment,FLAG)&&same({...old.environment,[FLAG]:'1'},next.environment),'environment_delta');
 need(next.working_directory===p.candidate.runtimeDirectory&&next.entrypoint===manifest.entry&&same([...next.source_files].sort((a,b)=>a.path.localeCompare(b.path)),manifest.files.map(e=>({path:e.path,sha256:e.result_sha256})).sort((a,b)=>a.path.localeCompare(b.path))),'candidate_binding');
 validateTask(p.core,oldLogin,from);validateTask(p.core,nextLogin,to);
 const oldBackup=jsonRef(from.backup),newBackup=jsonRef(to.backup);validateBackupBase(oldBackup,p.core,c);validateBackupBase(newBackup,p.core,c);
 const map=backupMapping(old,from,to,manifest,p.candidate);
 // Self/login/task cyclic template hashes stay at their original declared values.
 for(const r of ['backup','login','task'])map.get(from[r].path).sha256=undefined;
 const expected=buildMcpSwitchBackup(oldBackup,map);need(same(expected,newBackup),'backup_delta');
 return {format:'schema6-mcp-config-switch-bindings-v1',validated:true,approved:false,deploymentReady:false,registered:false,started:false,databaseRead:false,credentialFilesRead:false,corePreserved:true,backupPreserved:true,ownerSid:c.owner_sid,databasePath:c.database_path,stateDirectory:oldLogin.state_directory,custodyDirectory:c.recovery_custody_directory,releaseDirectory:p.core.releaseDirectory,manifestSha256:p.core.manifestSha256,configurationPath:p.core.configurationPath,configurationSha256:p.core.configurationSha256,oldTaskName:p.oldTaskName,newTaskName:p.newTaskName,oldXmlPath:from.task.path,newBackupPath:to.backup.path};
 }catch(e){if(/^mcp_switch_[a-z_]+$/.test(e?.code??''))throw e;need(false,'input_rejected');}
}
