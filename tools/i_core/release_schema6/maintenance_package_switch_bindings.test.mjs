import assert from 'node:assert/strict';
import {copyFileSync,existsSync,mkdirSync,readFileSync,writeFileSync,unlinkSync,linkSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {buildPackageSwitchBackupTemplate,validatePackageSwitchBindings} from '../maintenance/package-switch-bindings.mjs';
import {generatePackageSwitchConfigurations} from '../maintenance/generate-package-switch-configurations.mjs';
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
const preservedPrefix='preserved/legacy-v4-release/';
function legacyRelease(root,{patched=true}={}){
 const names=['i_core_server.mjs','i_core_store.mjs','shortcut_mail_relay.mjs','send_shortcut_mail.ps1','strict_smtp_tls_validation.ps1','start_i_core_service.ps1'].map(n=>'tools/i_core/'+n).concat(['start_pinned_i_core.ps1','verify_v4_state.mjs','runtime/node.exe']);
 const end=release(root,'legacy-v4',names),filename=path.join(end.releaseDirectory,'manifest.json');
 const files=JSON.parse(readFileSync(filename)).files.map(f=>f.path.startsWith('tools/i_core/')?{...f,[patched&&['tools/i_core/i_core_server.mjs','tools/i_core/i_core_store.mjs'].includes(f.path)?'base_source_blob':'source_blob']:'a'.repeat(40)}:f);
 const manifest={format:'i-core-runtime-pin-v1',release:patched?'b3-v4-phone-transcripts-20261003':'v4-bbb8025d',source_commit:'bbb8025d99fc0acaa846d58b4e5a94cef90f8756',core_schema_version:4,node_version:'v24.14.1',files,
 ...(patched?{source_mode:'synthetic-patched-source',source_patch_base_commit:'b'.repeat(40),source_patch_commit:'c'.repeat(40),source_replay_store_sha256:H,replay_confirmation:'synthetic-confirmation',source_transcript_patch_commit:'d'.repeat(40),source_transcript_store_sha256:H,local_transcripts:'synthetic-local-transcripts'}:{}),
 state_policy:'External existing state only; no state, config, tokens or credentials are packaged.',platform_dependency:'Windows PowerShell 5.1 and Windows DPAPI remain host-maintained.'};
 write(filename,manifest);end.manifestSha256=hash(filename);
 return {end,entries:[...manifest.files.map(f=>({role:'release',name:f.path,source_path:path.join(end.releaseDirectory,f.path),sha256:f.sha256})),{role:'release',name:'manifest.json',source_path:filename,sha256:end.manifestSha256}]};
}
function fixture(t,{legacy=false,legacyProfile='patched'}={}){
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
   {role:'configuration',name:'backup.json',source_path:files.backup,sha256:H},
   {role:'configuration',name:'mcp.json',source_path:files.mcp,sha256:H},
   {role:'task',name:'task.xml',source_path:files.task,sha256:H},
   ...['credentials','domain_policy','transcript_grants','replay_approvals','recovery_custody'].map(role=>({role,name:role+'.bin',source_path:path.join(root,'private',role+'.bin'),sha256:H}))
  ]}};
  return {end,files,core,mcp,login,backup};
 });
 let legacyPackage;
 if(legacy){
  legacyPackage=legacyRelease(root,{patched:legacyProfile==='patched'});
  const old=sides[0],next=sides[1],spec=old.backup.specTemplate;
  const active=spec.entries.filter(e=>e.role==='release').map(e=>({...e,role:'configuration',name:'candidate/release/'+e.name}));
  const kept=spec.entries.filter(e=>e.role!=='release');
  while(kept.length+active.length<108){const name='unchanged-'+kept.length+'.json';kept.push({role:'configuration',name,source_path:path.join(root,'private',name),sha256:H});}
  spec.entries=[...kept,...active,...legacyPackage.entries];spec.old_release_root=legacyPackage.end.releaseDirectory;spec.old_release_manifest_sha256=legacyPackage.end.manifestSha256;
  const rebound=new Map([[old.end.configurationPath,next.end.configurationPath],...Object.keys(old.files).map(r=>[old.files[r],next.files[r]])]);
  next.backup.specTemplate.entries=[...kept,...active].map(e=>({...e,source_path:rebound.get(e.source_path)??e.source_path})).concat(legacyPackage.entries.map(e=>({...e,role:'configuration',name:preservedPrefix+e.name})),next.backup.specTemplate.entries.filter(e=>e.role==='release'));
 }
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
 return {root,source,sides,publish,args,reset,legacyPackage};
}
function editLegacyManifest(f,change){
 const filename=path.join(f.legacyPackage.end.releaseDirectory,'manifest.json'),before=readFileSync(filename),manifest=JSON.parse(before);
 change(manifest);write(filename,manifest);const sha256=hash(filename);
 const source=f.sides[0].backup.specTemplate;source.old_release_manifest_sha256=sha256;source.entries.find(e=>e.name==='manifest.json').sha256=sha256;
 f.sides[1].backup.specTemplate.entries.find(e=>e.name===preservedPrefix+'manifest.json').sha256=sha256;f.publish();
 return ()=>{writeFileSync(filename,before);f.reset();};
}
function rejects(f,pattern=/^switch_bindings_[a-z_]+$/){
 assert.throws(()=>validatePackageSwitchBindings(...f.args()),error=>{
  assert.match(error.code,pattern);assert.equal(error.message,error.code);
  assert.equal(String(error).includes('never-echo'),false);return true;
 });
}
test('read-only package-switch binding preparation preserves the complete deployment chain',{skip:process.platform!=='win32',timeout:900000},async t=>{
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


test('legacy schema4 backup inventory stays complete across a schema6 package switch',{skip:process.platform!=='win32',timeout:900000},async t=>{
 const f=fixture(t,{legacy:true}),old=()=>f.sides[0],target=()=>f.sides[1];
 const oldEntries=()=>old().backup.specTemplate.entries,nextEntries=()=>target().backup.specTemplate.entries;
 await t.test('historical v4 ten plus active schema6 configuration forty-eight preserve all 108 nonrelease entries',()=>{
  assert.equal(oldEntries().filter(e=>e.role==='release').length,10);
  assert.equal(oldEntries().filter(e=>e.name.startsWith('candidate/release/')).length,48);
  assert.equal(oldEntries().filter(e=>e.role!=='release').length,108);
  assert.equal(nextEntries().filter(e=>e.role==='release').length,49);
  assert.equal(nextEntries().filter(e=>e.name.startsWith(preservedPrefix)).length,10);
  assert.equal(validatePackageSwitchBindings(...f.args()).validated,true);
  assert.equal(existsSync(old().core.database_path),false);
 });
 await t.test('base schema4 profile remains supported independently of the patched profile',()=>{
  const base=fixture(t,{legacy:true,legacyProfile:'base'});
  assert.equal(validatePackageSwitchBindings(...base.args()).validated,true);
  const next=buildPackageSwitchBackupTemplate(base.sides[0].backup,{from:base.sides[0].end,to:base.sides[1].end});
  assert.equal(next.specTemplate.entries.filter(e=>e.name.startsWith(preservedPrefix)).length,10);
  const restore=editLegacyManifest(base,m=>{const entry=m.files.find(v=>v.path==='tools/i_core/i_core_server.mjs');delete entry.source_blob;entry.base_source_blob='a'.repeat(40);});
  try{rejects(base,/^switch_bindings_backup_legacy_inventory_invalid$/);}finally{restore();}
 });
 for(const [name,change] of [
  ['unknown v4 release profile',m=>m.release='unreviewed-v4-profile'],
  ['malformed patched base blob',m=>m.files.find(v=>v.path==='tools/i_core/i_core_server.mjs').base_source_blob='not-a-blob'],
  ['array patched base blob',m=>m.files.find(v=>v.path==='tools/i_core/i_core_server.mjs').base_source_blob=['a'.repeat(40)]],
  ['array ordinary source blob',m=>m.files.find(v=>v.path==='tools/i_core/shortcut_mail_relay.mjs').source_blob=['a'.repeat(40)]],
  ['missing patched base blob',m=>delete m.files.find(v=>v.path==='tools/i_core/i_core_store.mjs').base_source_blob],
  ['base blob on an unapproved file',m=>m.files.find(v=>v.path==='verify_v4_state.mjs').base_source_blob='a'.repeat(40)],
  ['substituted ordinary blob on patched store',m=>{const entry=m.files.find(v=>v.path==='tools/i_core/i_core_store.mjs');delete entry.base_source_blob;entry.source_blob='a'.repeat(40);}],
 ])await t.test(name,()=>{f.reset();const restore=editLegacyManifest(f,change);try{rejects(f,/^switch_bindings_backup_legacy_inventory_invalid$/);}finally{restore();}});
 await t.test('template helper leaves source untouched and derives exactly ten preserved records',()=>{
  f.reset();const before=structuredClone(old().backup);
  const next=buildPackageSwitchBackupTemplate(old().backup,{from:old().end,to:target().end});
  assert.deepEqual(old().backup,before);
  assert.deepEqual(next.specTemplate.entries.filter(e=>e.name.startsWith(preservedPrefix)),oldEntries().filter(e=>e.role==='release').map(e=>({...e,role:'configuration',name:preservedPrefix+e.name})));
  assert.deepEqual(next.specTemplate.entries.filter(e=>e.role!=='release'&&!e.name.startsWith(preservedPrefix)),oldEntries().filter(e=>e.role!=='release'));
  assert.equal(next.specTemplate.entries.filter(e=>e.role==='release').length,49);
  assert.deepEqual({...next,specTemplate:null},{...before,specTemplate:null});
 });
 const active=()=>oldEntries().find(e=>e.name==='candidate/release/runtime/node.exe');
 const preserved=()=>nextEntries().find(e=>e.name===preservedPrefix+'runtime/node.exe');
 const cases=[
  ['missing active schema6 file',()=>{old().backup.specTemplate.entries=oldEntries().filter(e=>e!==active());}],
  ['extra active schema6 item',()=>oldEntries().push({role:'configuration',name:'candidate/release/extra.mjs',source_path:path.join(f.root,'extra.mjs'),sha256:H})],
  ['active schema6 hash mismatch',()=>active().sha256=H],
  ['active schema6 path mismatch',()=>active().source_path=path.join(f.root,'elsewhere.exe')],
  ['active schema6 logical name mismatch',()=>active().name='candidate/release/renamed.exe'],
  ['active schema6 manifest anchor mismatch',()=>oldEntries().find(e=>e.name==='candidate/release/manifest.json').sha256=H],
  ['active schema6 disabled',()=>active().state='disabled'],
  ['active schema6 changed role',()=>active().role='task'],
  ['missing v4 release file',()=>{old().backup.specTemplate.entries=oldEntries().filter(e=>e.name!=='runtime/node.exe');}],
  ['v4 hash mismatch',()=>oldEntries().find(e=>e.name==='runtime/node.exe').sha256=H],
  ['v4 path mismatch',()=>oldEntries().find(e=>e.name==='runtime/node.exe').source_path=path.join(f.root,'wrong-v4.exe')],
  ['v4 disabled',()=>oldEntries().find(e=>e.name==='runtime/node.exe').state='disabled'],
  ['no legacy preservation',()=>{target().backup.specTemplate.entries=nextEntries().filter(e=>!e.name.startsWith(preservedPrefix));}],
  ['legacy preserved item missing',()=>{target().backup.specTemplate.entries=nextEntries().filter(e=>e!==preserved());}],
  ['legacy preserved hash changed',()=>preserved().sha256=H],
  ['legacy preserved path changed',()=>preserved().source_path=path.join(f.root,'wrong-preserved.exe')],
  ['legacy preserved name changed',()=>preserved().name='renamed.exe'],
  ['legacy preserved role changed',()=>preserved().role='task'],
  ['legacy preserved disabled',()=>preserved().state='disabled'],
  ['legacy preserved flag added',()=>preserved().custody_context=true],
  ['legacy duplicate entry',()=>nextEntries().push({...preserved()})],
  ['legacy unknown namespace entry',()=>nextEntries().push({role:'configuration',name:preservedPrefix+'extra.mjs',source_path:path.join(f.root,'extra.mjs'),sha256:H})],
  ['unknown extra outside namespace',()=>nextEntries().push({role:'configuration',name:'extra.mjs',source_path:path.join(f.root,'extra.mjs'),sha256:H})],
  ['source preservation namespace collision',()=>oldEntries().push({role:'configuration',name:preservedPrefix+'collision.mjs',source_path:path.join(f.root,'collision.mjs'),sha256:H})],
  ['legacy source node differs from Core',()=>old().backup.specTemplate.node_id='another-node'],
  ['legacy source database differs from Core',()=>old().backup.specTemplate.canonical_database_path=path.join(f.root,'wrong.sqlite')],
  ['legacy target retention changes',()=>target().backup.policy.retentionDays=1],
  ['legacy target scope changes',()=>target().backup.specTemplate.entries.find(e=>e.name==='unchanged-11.json').sha256='b'.repeat(64)],
  ['legacy target attachment changes',()=>target().backup.specTemplate.entries.find(e=>e.name==='core.json').source_path=path.join(f.root,'wrong-core.json')],
 ];
 for(const [name,change] of cases)await t.test(name,()=>{f.reset();change();f.publish();rejects(f);});
 for(const name of f.legacyPackage.entries.map(e=>e.name))await t.test('each old v4 item must survive: '+name,()=>{
  f.reset();target().backup.specTemplate.entries=nextEntries().filter(e=>e.name!==preservedPrefix+name);f.publish();rejects(f);
 });
 for(const name of ['preserved','preserved/legacy-v4-release'])await t.test('namespace file ancestor rejects source and preserved target: '+name,()=>{
  for(const side of [0,1]){
   f.reset();f.sides[side].backup.specTemplate.entries.push({role:'configuration',name:side?name.toUpperCase():name,source_path:path.join(f.root,'namespace-ancestor.bin'),sha256:H});
   f.publish();rejects(f,/^switch_bindings_backup_legacy_namespace_collision$/);
   if(side===0)assert.throws(()=>buildPackageSwitchBackupTemplate(old().backup,{from:old().end,to:target().end}),{code:'switch_bindings_backup_legacy_namespace_collision'});
  }
 });
 await t.test('v4 actual bytes and aliases reject despite unchanged template',()=>{
  const file=path.join(f.legacyPackage.end.releaseDirectory,'verify_v4_state.mjs'),before=readFileSync(file);
  f.reset();write(file,'tampered');try{rejects(f);}finally{writeFileSync(file,before);}
  const alias=path.join(f.root,'v4-hardlink.mjs');linkSync(file,alias);try{rejects(f);}finally{unlinkSync(alias);}
  const extra=path.join(f.legacyPackage.end.releaseDirectory,'unexpected.mjs');write(extra,'extra');try{rejects(f);}finally{unlinkSync(extra);}
 });
 await t.test('legacy task and backup attachment checks remain mandatory',()=>{
  f.reset();write(target().files.task,readFileSync(target().files.task,'utf8').replace('LeastPrivilege','HighestAvailable'));rejects(f,/^switch_bindings_task_xml_changed$/);
  f.reset();target().login.backup_configuration_sha256=H;write(target().files.login,target().login);write(target().files.task,xml(target().end,target().files.login,hash(target().files.login)));rejects(f,/^switch_bindings_login_artifact_changed$/);
 });
 await t.test('a standard future source preserves the existing legacy namespace without adding another copy',()=>{
  f.reset();const saved=structuredClone(old()),third=release(f.root,'third',INVENTORY);
  const built=buildPackageSwitchBackupTemplate(target().backup,{from:target().end,to:third});
  old().end=third;old().core.manifest_sha256=third.manifestSha256;old().login.release_directory=third.releaseDirectory;old().login.manifest_sha256=third.manifestSha256;old().login.core_configuration_path=third.configurationPath;old().mcp.executable_path=path.join(third.releaseDirectory,'runtime/node.exe');
  assert.equal(built.specTemplate.entries.filter(e=>e.name.startsWith(preservedPrefix)).length,10);
  assert.deepEqual(built.specTemplate.entries.filter(e=>e.role!=='release'),nextEntries().filter(e=>e.role!=='release'));
  const fromTarget=target().backup;
  const mapping=new Map([[target().end.configurationPath,old().end.configurationPath],...Object.keys(target().files).map(r=>[target().files[r],old().files[r]])]);
  built.specTemplate.entries=built.specTemplate.entries.map(e=>({...e,source_path:mapping.get(e.source_path)??e.source_path}));
  old().backup=built;f.publish();const [plan,options]=f.args();
  assert.equal(validatePackageSwitchBindings({...plan,from:plan.to,to:plan.from,artifacts:options.fromArtifacts},{fromArtifacts:plan.artifacts}).validated,true);
  Object.assign(old(),saved);target().backup=fromTarget;
 });
 await t.test('legacy source cannot switch to a historical 47-file target',()=>{
  f.reset();const saved=structuredClone(target()),historic=release(f.root,'historical-target',LEGACY_SWITCH_INVENTORY);
  assert.throws(()=>buildPackageSwitchBackupTemplate(old().backup,{from:old().end,to:historic}),{code:'switch_bindings_backup_target_inventory_invalid'});
  const manifest=JSON.parse(readFileSync(path.join(historic.releaseDirectory,'manifest.json')));
  target().end=historic;target().core.manifest_sha256=historic.manifestSha256;target().login.release_directory=historic.releaseDirectory;target().login.manifest_sha256=historic.manifestSha256;target().login.core_configuration_path=historic.configurationPath;target().mcp.executable_path=path.join(historic.releaseDirectory,'runtime/node.exe');
  const spec=target().backup.specTemplate;spec.old_release_root=historic.releaseDirectory;spec.old_release_manifest_sha256=historic.manifestSha256;
  spec.entries=spec.entries.filter(e=>e.role!=='release').map(e=>e.source_path===saved.end.configurationPath?{...e,source_path:historic.configurationPath}:e).concat(manifest.files.map(v=>({role:'release',name:v.path,source_path:path.join(historic.releaseDirectory,v.path),sha256:v.sha256})),[{role:'release',name:'manifest.json',source_path:path.join(historic.releaseDirectory,'manifest.json'),sha256:historic.manifestSha256}]);
  f.publish();rejects(f,/^switch_bindings_backup_target_inventory_invalid$/);Object.assign(target(),saved);
 });
 await t.test('standard source cannot invent additional legacy preservation',()=>{
  const standard=fixture(t);
  standard.sides[1].backup.specTemplate.entries.push(...f.legacyPackage.entries.map(e=>({...e,role:'configuration',name:preservedPrefix+e.name})));
  standard.publish();rejects(standard,/^switch_bindings_backup_scope_changed$/);
 });
 await t.test('repository generator preserves 108 plus ten and produces a complete synthetic binding chain',()=>{
  f.reset();const outputRoot=syntheticRoot('switch-bindings-');t.after(()=>removeOwned(outputRoot,'switch-bindings-'));
  const outputDirectory=path.join(outputRoot,'generated-candidate'),before=Object.values(old().files).concat(old().end.configurationPath).map(p=>[p,hash(p)]);
  const input={oldLoginPath:old().files.login,oldLoginSha256:hash(old().files.login),newReleaseDirectory:target().end.releaseDirectory,newManifestSha256:target().end.manifestSha256,outputDirectory,oldTaskXmlPath:old().files.task,taskName:'synthetic-next-task',oldTaskName:'synthetic-old-task'};
  const result=generatePackageSwitchConfigurations(input);
  assert.equal(result.generated,true);assert.equal(result.preservedLegacyCount,10);assert.equal(result.newReleaseCount,49);
  for(const key of ['productionApproved','registrationAllowed','deploymentReady','fixedPrepareExecuted','databaseRead','separateCredentialFilesRead'])assert.equal(result[key],false);
  const info=JSON.parse(readFileSync(path.join(outputDirectory,'static-inputs.json'))),diff=JSON.parse(readFileSync(path.join(outputDirectory,'configuration-diff-safe.json')));
  assert.equal(diff.originalNonreleaseCount,108);assert.equal(diff.preservedLegacyCount,10);assert.equal(diff.oldReleaseCount,10);assert.equal(diff.newReleaseCount,49);
  assert.equal(diff.mcpConfigurationUnchanged,true);assert.equal(diff.backupOutsideSpecUnchanged,true);
  assert.equal(diff.reboundNonreleaseEntries.length,4);
  assert.equal(existsSync(info.preparedXml),false,'only the synthetic test creates XML');
  const end={releaseDirectory:info.releaseDirectory,manifestSha256:info.manifestSha256,configurationPath:info.corePath,configurationSha256:hash(info.corePath)};
  write(info.preparedXml,xml(end,info.loginPath,hash(info.loginPath)));
  const artifacts=[['backup',info.backupPath],['login',info.loginPath],['mcp',info.mcpPath],['task',info.preparedXml]].map(([role,p])=>({role,path:p,sha256:hash(p)}));
  assert.equal(validatePackageSwitchBindings({from:old().end,to:end,artifacts},f.args()[1]).validated,true);
  assert.deepEqual(before,before.map(([p])=>[p,hash(p)]));
  assert.equal(JSON.stringify({result,diff,info}).includes(old().core.pairing_secret),false);
  assert.equal(existsSync(old().core.database_path),false);assert.equal(existsSync(old().core.recovery_key_path),false);
 });
 await t.test('generator rejects unsafe output, missing attachments and old target inventory before output creation',()=>{
  const outputRoot=syntheticRoot('switch-bindings-');t.after(()=>removeOwned(outputRoot,'switch-bindings-'));
  mkdirSync(path.dirname(old().core.database_path),{recursive:true});mkdirSync(old().login.control_root,{recursive:true});
  let sequence=0;
  const cases=[
   ['old release',input=>input.outputDirectory=path.join(old().end.releaseDirectory,'rejected-output')],
   ['new release',input=>input.outputDirectory=path.join(target().end.releaseDirectory,'rejected-output')],
   ['state',input=>input.outputDirectory=path.join(path.dirname(old().core.database_path),'rejected-output')],
   ['control',input=>input.outputDirectory=path.join(old().login.control_root,'rejected-output')],
   ['target historical inventory',input=>{input.newReleaseDirectory=old().end.releaseDirectory;input.newManifestSha256=old().end.manifestSha256;}],
   ...['core.json','login.json','backup.json','task.xml'].flatMap(name=>[
    ['missing '+name,()=>{old().backup.specTemplate.entries=oldEntries().filter(e=>e.name!==name);}],
    ['wrong role '+name,()=>{oldEntries().find(e=>e.name===name).role=name==='task.xml'?'configuration':'task';}],
   ]),
  ];
  for(const [name,change] of cases){
   f.reset();const input={oldLoginPath:old().files.login,oldLoginSha256:hash(old().files.login),newReleaseDirectory:target().end.releaseDirectory,newManifestSha256:target().end.manifestSha256,outputDirectory:path.join(outputRoot,'rejected-'+sequence++),oldTaskXmlPath:old().files.task,taskName:'synthetic-next-task',oldTaskName:'synthetic-old-task'};
   change(input);f.publish();input.oldLoginSha256=hash(old().files.login);
   assert.equal(existsSync(input.outputDirectory),false,name);
   assert.throws(()=>generatePackageSwitchConfigurations(input),e=>{assert.match(e.code,/^(?:(?:configuration_generation|switch_bindings)_[a-z_]+|manifest_contract_mismatch)$/);assert.equal(e.message,e.code);return true;},name);
   assert.equal(existsSync(input.outputDirectory),false,name+' must fail before writing');
  }
 });
 await t.test('helper errors disclose neither malformed input nor embedded secret',()=>{
  f.reset();const bad=structuredClone(old().backup);bad.specTemplate.entries.find(e=>e.role==='release').name='never-echo';
  assert.throws(()=>buildPackageSwitchBackupTemplate(bad,{from:old().end,to:target().end}),e=>{assert.match(e.code,/^switch_bindings_[a-z_]+$/);assert.equal(e.message,e.code);assert.equal(String(e).includes('never-echo'),false);return true;});
 });
});
