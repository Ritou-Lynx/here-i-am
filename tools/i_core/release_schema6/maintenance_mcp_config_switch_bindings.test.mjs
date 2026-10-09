import test from 'node:test';
import {execFileSync} from 'node:child_process';
import assert from 'node:assert/strict';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {existsSync,mkdirSync,copyFileSync,writeFileSync,readFileSync,linkSync,unlinkSync} from 'node:fs';
import {INVENTORY,PINNED_NODE_SHA256,sha256,cleanEnvironment} from './package.mjs';
import {syntheticRoot} from '../test_fixtures/release_schema6/synthetic_paths.mjs';
import {removeOwned} from './lifecycle/test-fixture.mjs';
import {MCP_SOURCE_NAMES,taskXml,validateMcpConfigSwitch} from '../maintenance/mcp-config-switch-bindings.mjs';
import {generateMcpConfigSwitch,finalizeMcpConfigSwitch} from '../maintenance/generate-mcp-config-switch.mjs';
const repository=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..'),H='a'.repeat(64),SID='S-1-5-21-111-222-333-444';
const put=(p,v)=>writeFileSync(p,typeof v==='string'?v:JSON.stringify(v));
const hash=p=>sha256(readFileSync(p)),ref=(role,p)=>({role,path:p,sha256:hash(p)});
function fixture(t){
 const root=syntheticRoot('mcp-config-bindings-');t.after(()=>removeOwned(root,'mcp-config-bindings-'));
 const release=path.join(root,'release'),settings=path.join(root,'settings'),oldSource=path.join(root,'old-source'),candidateRoot=path.join(root,'candidate'),runtime=path.join(candidateRoot,'runtime');
 for(const p of [release,settings,oldSource,candidateRoot,runtime])mkdirSync(p);
 for(const n of INVENTORY){const p=path.join(release,n);mkdirSync(path.dirname(p),{recursive:true});if(n==='runtime/node.exe')copyFileSync(process.execPath,p);else if(n.endsWith('/prepare_login_schema6.ps1'))copyFileSync(path.join(repository,n),p);else put(p,'// synthetic runtime '+n);}
 const manifest={format:'i-core-schema6-preflight-candidate-v1',source_commit:'a'.repeat(40),core_commit:'a'.repeat(40),wrapper_commit:'a'.repeat(40),core_schema_version:6,runtime_profile:'schema6-owned-lifecycle-v1',activation_supported:false,node_version:'v24.14.1',pinned_node_sha256:PINNED_NODE_SHA256,policy:{activity_enabled:false,companion_reply_jobs:false,companion_upload_mode:'legacy_b3',domain_policy:'owner_managed'},files:INVENTORY.map(n=>({path:n,bytes:readFileSync(path.join(release,n)).length,sha256:hash(path.join(release,n))}))};
 put(path.join(release,'manifest.json'),manifest);
 const core={releaseDirectory:release,manifestSha256:hash(path.join(release,'manifest.json')),configurationPath:path.join(settings,'core.json'),configurationSha256:null};
 const c={format:'schema6-config-v1',manifest_sha256:core.manifestSha256,database_path:path.join(root,'state/i-core.sqlite'),node_id:'synthetic-node',owner_sid:SID,companion_upload_mode:'legacy_b3',companion_reply_jobs:false,activity_enabled:false,domain_policy:'owner_managed',pairing_secret:'f'.repeat(64),grants_path:path.join(root,'private/grants.json'),grants_sha256:H,approvals_path:path.join(root,'private/approvals.json'),approvals_sha256:H,recovery_custody_directory:path.join(root,'custody'),recovery_key_path:path.join(root,'private/recovery.dpapi'),backup_directory:path.join(root,'backups'),backup_key_path:path.join(root,'private/backup.dpapi')};
 put(core.configurationPath,c);core.configurationSha256=hash(core.configurationPath);
 const changed=['i_remote_mcp/server.mjs','i_remote_mcp/oauth.mjs','i_remote_mcp/mcp.mjs'];
 const files=MCP_SOURCE_NAMES.map(n=>{const p=path.join(oldSource,'tools',n),q=path.join(runtime,n);mkdirSync(path.dirname(p),{recursive:true});mkdirSync(path.dirname(q),{recursive:true});put(p,'// old synthetic '+n);put(q,'// '+(changed.includes(n)?'new':'old')+' synthetic '+n);return {path:n,source_blob:'b'.repeat(40),base_sha256:hash(p),result_sha256:hash(q),bytes:readFileSync(q).length,changed:changed.includes(n)};});
 const cm={schema_version:1,status:'not_deployed',baseline_commit:'3ce7aacc75615faf31aab7d4d902598070ffa898',source_commit:'f90058f21049f514f8ab2af407227aee02e2f259',source_prefix:'tools/i_core/test_fixtures/release_schema6/mcp_reader/legacy/',chatgpt_flag:{name:'I_REMOTE_MCP_CHATGPT_ENABLED',default:'0'},entry:'i_remote_mcp/server.mjs',changed_files:3,unchanged_files:3,source_sha256:{server:H,oauth:H,mcp:H},files};
 const manifestPath=path.join(candidateRoot,'manifest.json');put(manifestPath,cm);const candidate={manifestPath,manifestSha256:hash(manifestPath),runtimeDirectory:runtime};
 const p=Object.fromEntries(['mcp','backup','login','task'].map(r=>[r,path.join(settings,r+(r==='task'?'.xml':'.json'))]));
 const m={format:'schema6-mcp-v1',owner_sid:SID,executable_path:path.join(release,'runtime/node.exe'),executable_sha256:PINNED_NODE_SHA256,working_directory:oldSource,entrypoint:'tools/i_remote_mcp/server.mjs',source_files:files.map(e=>({path:'tools/'+e.path,sha256:e.base_sha256})),arguments:['serve'],environment:{I_REMOTE_MCP_STATE_DIR:path.join(root,'mcp-state'),I_MEMORY_DB:path.join(root,'private/memory.sqlite'),I_MEMORY_POLICY:path.join(root,'private/policy.json'),I_HOME:path.join(root,'mcp-home')},database_path:c.database_path,listen_host:'127.0.0.1',listen_port:47862,grace_ms:100};
 put(p.mcp,m);
 const b={policy:{format:'i-core-automatic-backup-v1',outputRoot:path.join(root,'backup-output'),retentionDays:30,backupSetId:H},envelopePath:path.join(root,'private/envelope.json'),envelopeSha256:H,sqliteEntryNames:['core.sqlite'],specTemplate:{format:'i-core-runtime-backup-spec-v1',source_schema:6,node_id:c.node_id,canonical_database_path:c.database_path,old_release_root:release,old_release_manifest_sha256:core.manifestSha256,entries:[
 {role:'database',name:'core.sqlite',source_path:c.database_path,sha256:H},
 ...manifest.files.map(e=>({role:'release',name:e.path,source_path:path.join(release,e.path),sha256:e.sha256})),{role:'release',name:'manifest.json',source_path:path.join(release,'manifest.json'),sha256:core.manifestSha256},
 {role:'configuration',name:'core.json',source_path:core.configurationPath,sha256:core.configurationSha256},
 ...Object.entries(p).map(([r,filename])=>({role:r==='task'?'task':'configuration',name:r+(r==='task'?'.xml':'.json'),source_path:filename,sha256:r==='mcp'?hash(p.mcp):H})),
 ...files.map(e=>({role:'configuration',name:'mcp-source/tools/'+e.path,source_path:path.join(oldSource,'tools',e.path),sha256:e.base_sha256})),
 ...['credentials','domain_policy','transcript_grants','replay_approvals','recovery_custody'].map(role=>({role,name:role+'.bin',source_path:path.join(root,'private',role+'.bin'),sha256:H}))
 ]}};
 put(p.backup,b);
 const l={format:'schema6-login-v1',owner_sid:SID,release_directory:release,manifest_sha256:core.manifestSha256,state_directory:path.dirname(c.database_path),control_root:path.join(root,'sessions'),core_configuration_path:core.configurationPath,core_configuration_sha256:core.configurationSha256,core_port:47861,backup_configuration_path:p.backup,backup_configuration_sha256:hash(p.backup),backup_key_directory:path.join(root,'private'),backup_interval_seconds:300,mcp_configuration_path:p.mcp,mcp_configuration_sha256:hash(p.mcp)};
 put(p.login,l);put(p.task,taskXml(core,l,ref('login',p.login)));
 const fromArtifacts=Object.entries(p).map(([r,filename])=>ref(r,filename));
 return {root,core,c,m,b,l,p,candidate,input:{format:'schema6-mcp-config-switch-generation-v1',core,fromArtifacts,candidate,oldTaskName:'SyntheticOld',newTaskName:'SyntheticNew',outputDirectory:path.join(root,'output')}};
}
function complete(f){const out=generateMcpConfigSwitch(f.input),s=JSON.parse(readFileSync(out.staticInputsPath));put(out.outputXmlPath,readFileSync(s.reviewXml.path,'utf8'));const report=finalizeMcpConfigSwitch(s);return {out,report,proposal:JSON.parse(readFileSync(report.proposalPath))};}
function mutateArtifact(p,role,fn){const a=p.toArtifacts.find(a=>a.role===role),value=JSON.parse(readFileSync(a.path));fn(value);put(a.path,value);a.sha256=hash(a.path);if(role!=='login'&&role!=='task'){const login=p.toArtifacts.find(a=>a.role==='login'),l=JSON.parse(readFileSync(login.path));l[role+'_configuration_sha256']=a.sha256;put(login.path,l);login.sha256=hash(login.path);const task=p.toArtifacts.find(a=>a.role==='task');put(task.path,taskXml(p.core,l,login));task.sha256=hash(task.path);}}
test('MCP-only candidate chain preserves Core and all backup entries without database/key reads',{skip:process.platform!=='win32'},t=>{
 const f=fixture(t),before=readFileSync(f.core.configurationPath),r=complete(f);assert.equal(r.report.validated,true);assert.equal(r.report.deploymentReady,false);assert.equal(r.report.databaseRead,false);assert.deepEqual(readFileSync(f.core.configurationPath),before);
 const b=JSON.parse(readFileSync(r.proposal.toArtifacts.find(a=>a.role==='backup').path));assert.equal(b.specTemplate.entries.length,f.b.specTemplate.entries.length+10);assert.equal(b.specTemplate.entries.filter(e=>e.name.startsWith('preserved/mcp-config-switch-source/')).length,10);assert.throws(()=>generateMcpConfigSwitch(f.input));assert.throws(()=>finalizeMcpConfigSwitch(JSON.parse(readFileSync(r.out.staticInputsPath))));
});
test('MCP-only bindings reject policy, inventory and backup substitutions',{skip:process.platform!=='win32'},async t=>{
 const cases=[
 ['Core configuration replacement',p=>p.core.configurationSha256=H],
 ['Core package replacement',p=>p.core.manifestSha256=H],
 ['Node path',p=>mutateArtifact(p,'mcp',m=>m.executable_path=p.core.configurationPath)],
 ['data path',p=>mutateArtifact(p,'mcp',m=>m.environment.I_MEMORY_DB=path.join(path.dirname(m.environment.I_MEMORY_DB),'other.sqlite'))],
 ['scope environment',p=>mutateArtifact(p,'mcp',m=>m.environment.I_REMOTE_MCP_WRITE_ENABLED='0')],
 ['extra redirect',p=>mutateArtifact(p,'mcp',m=>m.environment.I_REMOTE_MCP_EXTRA_REDIRECT_URIS='https://example.invalid/callback')],
 ['flag',p=>mutateArtifact(p,'mcp',m=>m.environment.I_REMOTE_MCP_CHATGPT_ENABLED='0')],
 ['port',p=>mutateArtifact(p,'mcp',m=>m.listen_port++)],
 ['unknown field',p=>mutateArtifact(p,'mcp',m=>m.unknown=true)],
 ['missing source',p=>mutateArtifact(p,'mcp',m=>m.source_files.pop())],
 ['backup shrink',p=>mutateArtifact(p,'backup',b=>b.specTemplate.entries.pop())],
 ['backup policy',p=>mutateArtifact(p,'backup',b=>b.policy.retentionDays++)],
 ['backup state',p=>mutateArtifact(p,'backup',b=>b.specTemplate.entries.find(e=>e.role==='credentials').state='disabled')],
 ['same task name',p=>p.newTaskName=p.oldTaskName.toLowerCase()],
 ['unexpected file',p=>put(path.join(p.candidate.runtimeDirectory,'unknown.mjs'),'bad')],
 ['source hardlink',p=>{const q=path.join(p.candidate.runtimeDirectory,MCP_SOURCE_NAMES[0]);const linked=path.join(path.dirname(p.candidate.runtimeDirectory),'linked.mjs');linkSync(q,linked);return ()=>unlinkSync(linked);}],
 ];
 for(const [name,mutate] of cases)await t.test(name,sub=>{const f=fixture(sub),r=complete(f);const cleanup=mutate(r.proposal);try{assert.throws(()=>validateMcpConfigSwitch(r.proposal),e=>/^mcp_switch_/.test(e.code));}finally{if(typeof cleanup==='function')cleanup();}});
});
test('generator refuses output overlap, altered base source and missing backup attachment before writes',{skip:process.platform!=='win32'},async t=>{
 for(const kind of ['overlap','base','attachment'])await t.test(kind,sub=>{const f=fixture(sub);if(kind==='overlap')f.input.outputDirectory=path.join(f.candidate.runtimeDirectory,'nested');if(kind==='base')put(path.join(f.m.working_directory,f.m.source_files[0].path),'changed');if(kind==='attachment'){f.b.specTemplate.entries=f.b.specTemplate.entries.filter(e=>e.source_path!==f.p.mcp);put(f.p.backup,f.b);f.l.backup_configuration_sha256=hash(f.p.backup);put(f.p.login,f.l);put(f.p.task,taskXml(f.core,f.l,ref('login',f.p.login)));f.input.fromArtifacts=Object.entries(f.p).map(([r,p])=>ref(r,p));}assert.throws(()=>generateMcpConfigSwitch(f.input));});
});


test('candidate manifest origin is restricted to the reviewed compatibility commit',{skip:process.platform!=='win32'},t=>{
 const f=fixture(t),r=complete(f),m=JSON.parse(readFileSync(f.candidate.manifestPath));
 m.source_commit='0'.repeat(40);put(f.candidate.manifestPath,m);r.proposal.candidate.manifestSha256=hash(f.candidate.manifestPath);
 assert.throws(()=>validateMcpConfigSwitch(r.proposal),{code:'mcp_switch_candidate_contract'});
});


const inspectBackupAcl=(filename,addAdministrator=false)=>JSON.parse(execFileSync(path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe'),['-NoProfile','-NonInteractive','-Command',"$ErrorActionPreference='Stop';$env:PSModulePath=Join-Path $PSHOME 'Modules';$v=[Console]::In.ReadToEnd()|ConvertFrom-Json;$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User;$a=Get-Acl -LiteralPath $v.path;if($v.addAdministrator-eq $true){$a.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'),'FullControl','Allow'));$h=[IO.FileStream]::new($v.path,[IO.FileMode]::Open,[Security.AccessControl.FileSystemRights]::FullControl,[IO.FileShare]::None,4096,[IO.FileOptions]::None);try{$h.SetAccessControl($a)}finally{$h.Dispose()}};$a=Get-Acl -LiteralPath $v.path;$rules=@($a.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]));[pscustomobject]@{protected=$a.AreAccessRulesProtected;ownerMatches=($a.GetOwner([Security.Principal.SecurityIdentifier]).Value-ceq $sid.Value);rules=@($rules|ForEach-Object{[pscustomobject]@{sid=$_.IdentityReference.Value;rights=[string]$_.FileSystemRights;inherited=$_.IsInherited;type=[string]$_.AccessControlType}});owner=$sid.Value}|ConvertTo-Json -Depth 4 -Compress"],{input:JSON.stringify({path:filename,addAdministrator}),encoding:'utf8',env:cleanEnvironment(),windowsHide:true,stdio:['pipe','pipe','pipe']}));
test('backup file ACL is explicit protected owner and SYSTEM only',{skip:process.platform!=='win32'},t=>{
 const f=fixture(t),r=complete(f),backup=r.proposal.toArtifacts.find(a=>a.role==='backup');
 const a=inspectBackupAcl(backup.path);assert.equal(a.protected,true);assert.equal(a.ownerMatches,true);
 assert.deepEqual(a.rules.map(r=>r.sid).sort(),[a.owner,'S-1-5-18'].sort());
 for(const r of a.rules){assert.equal(r.rights,'FullControl');assert.equal(r.inherited,false);assert.equal(r.type,'Allow');}
});
test('backup file ACL drift rejects finalization before proposal publication',{skip:process.platform!=='win32'},t=>{
 const f=fixture(t),r=generateMcpConfigSwitch(f.input),s=JSON.parse(readFileSync(r.staticInputsPath));
 put(r.outputXmlPath,readFileSync(s.reviewXml.path,'utf8'));
 const p=s.toArtifacts.find(a=>a.role==='backup').path,oldHash=hash(p);
 assert.equal(inspectBackupAcl(p,true).rules.length,3);assert.equal(hash(p),oldHash);
 assert.throws(()=>finalizeMcpConfigSwitch(s),{code:'mcp_switch_backup_acl'});
 assert.equal(existsSync(path.join(f.input.outputDirectory,'proposal.json')),false);
});
