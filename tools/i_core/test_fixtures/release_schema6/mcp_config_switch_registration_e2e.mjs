import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {mkdirSync,copyFileSync,writeFileSync,readFileSync} from 'node:fs';
import {INVENTORY,PINNED_NODE_SHA256,sha256} from '../../release_schema6/package.mjs';
import {backupFilePrimitives as f} from '../../release_schema6/backup_bundle.mjs';
import {syntheticRoot} from './synthetic_paths.mjs';
import {removeOwned} from '../../release_schema6/lifecycle/test-fixture.mjs';
import {MCP_SOURCE_NAMES,taskXml} from '../../maintenance/mcp-config-switch-bindings.mjs';
const repository=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../../..'),H='a'.repeat(64);
const put=(p,v)=>writeFileSync(p,typeof v==='string'?v:JSON.stringify(v));
const hash=p=>sha256(readFileSync(p)),ref=(role,p)=>({role,path:p,sha256:hash(p)});
export function staticRegistrationFixture(t,sid){
 const cleanup={allowed:true};const root=syntheticRoot('mcp-registration-e2e-');t.after(()=>{if(cleanup.allowed)removeOwned(root,'mcp-registration-e2e-');else t.diagnostic('Synthetic root retained because nonce-task cleanup was not confirmed');});
 f.protect(root);
 const release=path.join(root,'release'),settings=path.join(root,'settings'),oldSource=path.join(root,'old-source'),candidateRoot=path.join(root,'candidate'),runtime=path.join(candidateRoot,'runtime');
 for(const p of [release,settings,oldSource,candidateRoot,runtime])mkdirSync(p);
 for(const n of INVENTORY){const p=path.join(release,n);mkdirSync(path.dirname(p),{recursive:true});if(n==='runtime/node.exe')copyFileSync(process.execPath,p);else if(n.endsWith('/prepare_login_schema6.ps1'))copyFileSync(path.join(repository,n),p);else put(p,n.endsWith('.ps1')?'# Synthetic inert runtime; never starts a service\nexit 0':'// synthetic inert runtime '+n);}
 const manifest={format:'i-core-schema6-preflight-candidate-v1',source_commit:'a'.repeat(40),core_commit:'a'.repeat(40),wrapper_commit:'a'.repeat(40),core_schema_version:6,runtime_profile:'schema6-owned-lifecycle-v1',activation_supported:false,node_version:'v24.14.1',pinned_node_sha256:PINNED_NODE_SHA256,policy:{activity_enabled:false,companion_reply_jobs:false,companion_upload_mode:'legacy_b3',domain_policy:'owner_managed'},files:INVENTORY.map(n=>({path:n,bytes:readFileSync(path.join(release,n)).length,sha256:hash(path.join(release,n))}))};
 put(path.join(release,'manifest.json'),manifest);
 const core={releaseDirectory:release,manifestSha256:hash(path.join(release,'manifest.json')),configurationPath:path.join(settings,'core.json'),configurationSha256:null};
 const c={format:'schema6-config-v1',manifest_sha256:core.manifestSha256,database_path:path.join(root,'state/i-core.sqlite'),node_id:'synthetic-node',owner_sid:sid,companion_upload_mode:'legacy_b3',companion_reply_jobs:false,activity_enabled:false,domain_policy:'owner_managed',pairing_secret:'f'.repeat(64),grants_path:path.join(root,'private/grants.json'),grants_sha256:H,approvals_path:path.join(root,'private/approvals.json'),approvals_sha256:H,recovery_custody_directory:path.join(root,'custody'),recovery_key_path:path.join(root,'private/recovery.dpapi'),backup_directory:path.join(root,'backups'),backup_key_path:path.join(root,'private/backup.dpapi')};
 put(core.configurationPath,c);core.configurationSha256=hash(core.configurationPath);
 const changed=['i_remote_mcp/server.mjs','i_remote_mcp/oauth.mjs','i_remote_mcp/mcp.mjs'];
 const files=MCP_SOURCE_NAMES.map(n=>{const p=path.join(oldSource,'tools',n),q=path.join(runtime,n);mkdirSync(path.dirname(p),{recursive:true});mkdirSync(path.dirname(q),{recursive:true});put(p,'// old synthetic '+n);put(q,'// '+(changed.includes(n)?'new':'old')+' synthetic '+n);return {path:n,source_blob:'b'.repeat(40),base_sha256:hash(p),result_sha256:hash(q),bytes:readFileSync(q).length,changed:changed.includes(n)};});
 const cm={schema_version:1,status:'not_deployed',baseline_commit:'3ce7aacc75615faf31aab7d4d902598070ffa898',source_commit:'f90058f21049f514f8ab2af407227aee02e2f259',source_prefix:'tools/i_core/test_fixtures/release_schema6/mcp_reader/legacy/',chatgpt_flag:{name:'I_REMOTE_MCP_CHATGPT_ENABLED',default:'0'},entry:'i_remote_mcp/server.mjs',changed_files:3,unchanged_files:3,source_sha256:{server:H,oauth:H,mcp:H},files};
 const manifestPath=path.join(candidateRoot,'manifest.json');put(manifestPath,cm);const candidate={manifestPath,manifestSha256:hash(manifestPath),runtimeDirectory:runtime};
 const p=Object.fromEntries(['mcp','backup','login','task'].map(r=>[r,path.join(settings,r+(r==='task'?'.xml':'.json'))]));
 const m={format:'schema6-mcp-v1',owner_sid:sid,executable_path:path.join(release,'runtime/node.exe'),executable_sha256:PINNED_NODE_SHA256,working_directory:oldSource,entrypoint:'tools/i_remote_mcp/server.mjs',source_files:files.map(e=>({path:'tools/'+e.path,sha256:e.base_sha256})),arguments:['serve'],environment:{I_REMOTE_MCP_STATE_DIR:path.join(root,'mcp-state'),I_MEMORY_DB:path.join(root,'private/memory.sqlite'),I_MEMORY_POLICY:path.join(root,'private/policy.json'),I_HOME:path.join(root,'mcp-home')},database_path:c.database_path,listen_host:'127.0.0.1',listen_port:47862,grace_ms:100};
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
 const l={format:'schema6-login-v1',owner_sid:sid,release_directory:release,manifest_sha256:core.manifestSha256,state_directory:path.dirname(c.database_path),control_root:path.join(root,'sessions'),core_configuration_path:core.configurationPath,core_configuration_sha256:core.configurationSha256,core_port:47861,backup_configuration_path:p.backup,backup_configuration_sha256:hash(p.backup),backup_key_directory:path.join(root,'private'),backup_interval_seconds:300,mcp_configuration_path:p.mcp,mcp_configuration_sha256:hash(p.mcp)};
 put(p.login,l);put(p.task,taskXml(core,l,ref('login',p.login)));
 const fromArtifacts=Object.entries(p).map(([r,filename])=>ref(r,filename));
 return {root,cleanup,core,c,m,b,l,p,candidate,input:{format:'schema6-mcp-config-switch-generation-v1',core,fromArtifacts,candidate,oldTaskName:'SyntheticOld',newTaskName:'SyntheticNew',outputDirectory:path.join(root,'output')}};
}
