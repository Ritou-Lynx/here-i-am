import assert from 'node:assert/strict';
import {copyFileSync,existsSync,mkdirSync,readFileSync,writeFileSync,unlinkSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {validatePackageSwitchBindings} from '../maintenance/package-switch-bindings.mjs';
import {preparePackageSwitch} from '../maintenance/prepare-package-switch.mjs';
import {INVENTORY,PINNED_NODE_SHA256,sha256} from './package.mjs';
import {LEGACY_SWITCH_INVENTORY} from './package_switch.mjs';
import {syntheticRoot} from '../test_fixtures/release_schema6/synthetic_paths.mjs';
import {removeOwned} from './lifecycle/test-fixture.mjs';

const H='a'.repeat(64),SID='S-1-5-21-111-222-333-444';
const repository=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..');
const prepareSource=readFileSync(path.join(repository,'tools/i_core/release_schema6/lifecycle/prepare_login_schema6.ps1'),'utf8');
const xmlTemplate=prepareSource.match(/\$document\.LoadXml\('([^']+)'\)/)?.[1];
assert.ok(xmlTemplate,'fixture reads the fixed production XML schema');
const esc=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
const hash=p=>sha256(readFileSync(p));
const write=(p,v)=>writeFileSync(p,typeof v==='string'?v:JSON.stringify(v));
function release(root,name,inventory){
 const directory=path.join(root,name);mkdirSync(directory);
 for(const relative of inventory){
  const p=path.join(directory,relative);mkdirSync(path.dirname(p),{recursive:true});
  if(relative==='runtime/node.exe')copyFileSync(process.execPath,p);else write(p,'synthetic fixed '+name+' '+relative);
 }
 const manifest={format:'i-core-schema6-preflight-candidate-v1',source_commit:'a'.repeat(40),core_commit:'a'.repeat(40),wrapper_commit:'a'.repeat(40),core_schema_version:6,runtime_profile:'schema6-owned-lifecycle-v1',activation_supported:false,node_version:'v24.14.1',pinned_node_sha256:PINNED_NODE_SHA256,
 policy:{activity_enabled:false,companion_reply_jobs:false,companion_upload_mode:'legacy_b3',domain_policy:'owner_managed'},
 files:inventory.map(p=>({path:p,bytes:readFileSync(path.join(directory,p)).length,sha256:hash(path.join(directory,p))}))};
 write(path.join(directory,'manifest.json'),manifest);
 return {releaseDirectory:directory,manifestSha256:hash(path.join(directory,'manifest.json')),configurationPath:path.join(root,name+'-core.json'),configurationSha256:null};
}
function xml(end,loginPath,loginHash){
 const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
 const args=['-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',path.join(end.releaseDirectory,'tools/i_core/release_schema6/lifecycle/login_schema6.ps1'),'-ReleaseDirectory',end.releaseDirectory,'-ManifestSha256',end.manifestSha256,'-LoginConfigurationPath',loginPath,'-LoginConfigurationSha256',loginHash];
 return '<?xml version="1.0" encoding="utf-8"?>\r\n'+xmlTemplate.replaceAll('<UserId />','<UserId>'+SID+'</UserId>').replace('<Command />','<Command>'+esc(ps)+'</Command>').replace('<Arguments />','<Arguments>'+esc(args.map(s=>'"'+s+'"').join(' '))+'</Arguments>');
}
function fixture(t){
 const root=syntheticRoot('switch-bindings-');t.after(()=>removeOwned(root,'switch-bindings-'));
 const from=release(root,'old',LEGACY_SWITCH_INVENTORY),to=release(root,'next',INVENTORY);
 const source=path.join(root,'mcp-source');mkdirSync(source);write(path.join(source,'cli.mjs'),'// synthetic MCP program never executed\n');
 const baselineCore={format:'schema6-config-v1',database_path:path.join(root,'state/i-core.sqlite'),node_id:'synthetic-node',owner_sid:SID,companion_upload_mode:'legacy_b3',companion_reply_jobs:false,activity_enabled:false,domain_policy:'owner_managed',pairing_secret:'f'.repeat(64),
 grants_path:path.join(root,'private/grants.json'),grants_sha256:H,approvals_path:path.join(root,'private/approvals.json'),approvals_sha256:H,recovery_custody_directory:path.join(root,'custody'),recovery_key_path:path.join(root,'private/runtime-recovery.dpapi'),backup_directory:path.join(root,'backups'),backup_key_path:path.join(root,'private/runtime-backup.dpapi')};
 const sides=[from,to].map((end,i)=>{
  const prefix=i?'to':'from',files=Object.fromEntries(['backup','login','mcp','task'].map(role=>[role,path.join(root,prefix+'-'+role+(role==='task'?'.xml':'.json'))]));
  const core={...baselineCore,manifest_sha256:end.manifestSha256};
  const mcp={format:'schema6-mcp-v1',owner_sid:SID,executable_path:path.join(end.releaseDirectory,'runtime/node.exe'),executable_sha256:PINNED_NODE_SHA256,working_directory:source,entrypoint:'cli.mjs',source_files:[{path:'cli.mjs',sha256:hash(path.join(source,'cli.mjs'))}],arguments:['serve'],environment:{I_REMOTE_MCP_STATE_DIR:path.join(root,'mcp-state'),I_MEMORY_DB:path.join(root,'private/memory.sqlite'),I_MEMORY_POLICY:path.join(root,'private/policy.json'),I_HOME:path.join(root,'mcp-home')},database_path:core.database_path,listen_host:'127.0.0.1',listen_port:47862,grace_ms:100};
  const login={format:'schema6-login-v1',owner_sid:SID,release_directory:end.releaseDirectory,manifest_sha256:end.manifestSha256,state_directory:path.dirname(core.database_path),control_root:path.join(root,'sessions'),core_configuration_path:end.configurationPath,core_configuration_sha256:H,core_port:47861,backup_configuration_path:files.backup,backup_configuration_sha256:H,backup_key_directory:path.join(root,'private'),backup_interval_seconds:300,mcp_configuration_path:files.mcp,mcp_configuration_sha256:H};
  const manifest=JSON.parse(readFileSync(path.join(end.releaseDirectory,'manifest.json')));
  const releaseEntries=[...manifest.files.map(f=>({role:'release',name:f.path,source_path:path.join(end.releaseDirectory,f.path),sha256:f.sha256})),{role:'release',name:'manifest.json',source_path:path.join(end.releaseDirectory,'manifest.json'),sha256:end.manifestSha256}];
  const backup={policy:{format:'i-core-automatic-backup-v1',outputRoot:path.join(root,'backup-output'),retentionDays:30,backupSetId:H},envelopePath:path.join(root,'private/portable-key.json'),envelopeSha256:H,sqliteEntryNames:['core.sqlite'],specTemplate:{format:'i-core-runtime-backup-spec-v1',source_schema:6,node_id:core.node_id,canonical_database_path:core.database_path,old_release_root:end.releaseDirectory,old_release_manifest_sha256:end.manifestSha256,entries:[
   {role:'database',name:'core.sqlite',source_path:core.database_path,sha256:H},...releaseEntries,
   {role:'configuration',name:'core.json',source_path:end.configurationPath,sha256:H},
   {role:'configuration',name:'login.json',source_path:files.login,sha256:H},
   {role:'configuration',name:'mcp.json',source_path:files.mcp,sha256:H},
   {role:'task',name:'task.xml',source_path:files.task,sha256:H},
   ...['credentials','domain_policy','transcript_grants','replay_approvals','recovery_custody'].map(role=>({role,name:role+'.bin',source_path:path.join(root,'private',role+'.bin'),sha256:H}))
  ]}};
  return {end,files,core,mcp,login,backup};
 });
 const original=sides.map(s=>structuredClone(s));
 function publish(){
  for(const s of sides){
   write(s.end.configurationPath,s.core);s.end.configurationSha256=hash(s.end.configurationPath);
   write(s.files.mcp,s.mcp);write(s.files.backup,s.backup);
   s.login.core_configuration_sha256=s.end.configurationSha256;s.login.mcp_configuration_sha256=hash(s.files.mcp);s.login.backup_configuration_sha256=hash(s.files.backup);
   write(s.files.login,s.login);write(s.files.task,xml(s.end,s.files.login,hash(s.files.login)));
  }
 }
 function args(){
  const listed=s=>Object.entries(s.files).map(([role,p])=>({role,path:p,sha256:hash(p)}));
  return [{approved:false,from:sides[0].end,to:sides[1].end,artifacts:listed(sides[1])},{fromArtifacts:listed(sides[0])}];
 }
 function reset(){for(let i=0;i<2;i++){for(const key of ['core','mcp','login','backup'])sides[i][key]=structuredClone(original[i][key]);}write(path.join(source,'cli.mjs'),'// synthetic MCP program never executed\n');publish();}
 publish();
 return {root,source,sides,publish,args,reset};
}
function rejects(f,pattern=/^switch_bindings_[a-z_]+$/){
 assert.throws(()=>validatePackageSwitchBindings(...f.args()),error=>{
  assert.match(error.code,pattern);assert.equal(error.message,error.code);
  assert.equal(String(error).includes('never-echo'),false);return true;
 });
}
test('read-only package-switch binding preparation preserves the complete deployment chain',{skip:process.platform!=='win32',timeout:180000},async t=>{
 const f=fixture(t),target=()=>f.sides[1],old=()=>f.sides[0];
 await t.test('exact 47 to 48 packages and real configuration schemas pass without opening DB or separate credential files',()=>{
  const result=validatePackageSwitchBindings(...f.args());
  for(const key of ['validated','corePolicyPreserved','loginPolicyPreserved','mcpProgramAndPolicyPreserved','backupReleaseInventoryBound','backupPolicyPreserved','taskXmlBound'])assert.equal(result[key],true);
  for(const key of ['approved','deploymentReady','credentialFilesRead','databaseRead','registered','started'])assert.equal(result[key],false);
  assert.equal(JSON.stringify(result).includes(target().core.pairing_secret),false);
  assert.equal(existsSync(target().core.database_path),false);assert.equal(existsSync(target().core.recovery_key_path),false);
 });
 await t.test('prepare entry binds real synthetic artifacts but remains unapproved and undeployed',()=>{
  f.reset();const [plan,options]=f.args(),headPath=path.join(f.root,'synthetic-head.json'),markerPath=path.join(f.root,'synthetic-marker.json');
  write(headPath,{synthetic:true,generation:7});
  write(markerPath,{format:'schema6-lifecycle-v1',phase:'clean_closed',manifest_sha256:plan.from.manifestSha256,configuration_sha256:plan.from.configurationSha256});
  const input={...plan,...options,operationId:'synthetic-binding-prepare',headPath,markerPath};
  const result=preparePackageSwitch(input);
  assert.equal(result.bindingReport.validated,true);
  assert.equal(result.plan.approved,false);assert.equal(result.report.approved,false);assert.equal(result.report.deploymentReady,false);
  assert.equal(result.report.registered,false);assert.equal(result.report.started,false);
  assert.equal(result.plan.expectedHeadSha256,hash(headPath));assert.equal(result.plan.expectedMarkerSha256,hash(markerPath));
  assert.ok(result.report.unverifiedDeploymentGates.includes('fixed_prepare_receipt_and_approved_xml_equality'));
  assert.ok(result.report.unverifiedDeploymentGates.includes('owner_sid_registration_sddl_expected_registered_sddl_and_parent_sddl_pins'));
  assert.throws(()=>preparePackageSwitch({...input,fromArtifacts:undefined}),{code:'switch_bindings_artifacts_required'});
  target().backup.specTemplate.old_release_root=old().end.releaseDirectory;f.publish();
  const [changedPlan,changedOptions]=f.args();
  assert.throws(()=>preparePackageSwitch({...input,...changedPlan,...changedOptions}),{code:'switch_bindings_backup_binding_changed'});
 });
 const cases=[
  ['stale old backup package',()=>{target().backup.specTemplate.old_release_root=old().end.releaseDirectory;target().backup.specTemplate.old_release_manifest_sha256=old().end.manifestSha256;}],
  ['wrong Core manifest',()=>target().core.manifest_sha256=old().end.manifestSha256],
  ['PR10 cannot be enabled',()=>target().core.companion_upload_mode='pr10'],
  ['reply jobs cannot be enabled',()=>target().core.companion_reply_jobs=true],
  ['Core port cannot silently change',()=>target().login.core_port=47863],
  ['MCP port cannot silently change',()=>target().mcp.listen_port=47864],
  ['MCP environment policy cannot change',()=>target().mcp.environment.I_MEMORY_POLICY=path.join(f.root,'private/another-policy.json')],
  ['backup retention cannot change',()=>target().backup.policy.retentionDays=1],
  ['backup cannot capture another database',()=>{target().backup.specTemplate.canonical_database_path=path.join(f.root,'private/another.sqlite');target().backup.specTemplate.entries.find(e=>e.role==='database').source_path=target().backup.specTemplate.canonical_database_path;}],
  ['new backup must include pinned runtime',()=>target().backup.specTemplate.entries=target().backup.specTemplate.entries.filter(e=>e.name!=='runtime/node.exe')],
  ['nonrelease credential source cannot change',()=>target().backup.specTemplate.entries.find(e=>e.role==='credentials').source_path=path.join(f.root,'private/another-secret')],
 ];
 for(const [name,change] of cases)await t.test(name,()=>{f.reset();change();f.publish();rejects(f);});
 await t.test('wrong XML binding and changed task policies reject even with updated file hash',()=>{
  for(const replace of [s=>s.replace(target().end.manifestSha256,old().end.manifestSha256),s=>s.replace('LeastPrivilege','HighestAvailable')]){
   f.reset();write(target().files.task,replace(readFileSync(target().files.task,'utf8')));rejects(f,/^switch_bindings_task_xml_changed$/);
  }
 });
 await t.test('actual MCP program bytes cannot drift',()=>{f.reset();write(path.join(f.source,'cli.mjs'),'// changed bytes');rejects(f,/^switch_bindings_anchor_changed$/);});
 await t.test('new MCP program cannot be substituted with self-consistent new hashes',()=>{
  f.reset();const alternate=path.join(f.root,'alternate-mcp');mkdirSync(alternate);write(path.join(alternate,'cli.mjs'),'// another valid-looking program');
  target().mcp.working_directory=alternate;target().mcp.source_files[0].sha256=hash(path.join(alternate,'cli.mjs'));f.publish();rejects(f,/^switch_bindings_mcp_program_or_policy_changed$/);
 });
 await t.test('extra release file rejects exact package verification',()=>{
  f.reset();const extra=path.join(target().end.releaseDirectory,'extra.txt');write(extra,'unreviewed');try{rejects(f);}finally{unlinkSync(extra);}
 });
 await t.test('identical package endpoints cannot masquerade as a switch',()=>{
  f.reset();const [plan,options]=f.args();assert.throws(()=>validatePackageSwitchBindings({...plan,to:plan.from},options),{code:'switch_bindings_distinct_packages_required'});
 });
 await t.test('missing old artifact anchors reject without guessing policies',()=>{
  f.reset();assert.throws(()=>validatePackageSwitchBindings(f.args()[0]),{code:'switch_bindings_artifacts_required'});
 });
 await t.test('malformed secret-bearing input never appears in error text',()=>{
  f.reset();write(target().end.configurationPath,'{"pairing_secret":"never-echo", broken');target().end.configurationSha256=hash(target().end.configurationPath);rejects(f,/^switch_bindings_input_rejected$/);
 });
});
