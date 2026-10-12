import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import os from 'node:os';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,rmSync,existsSync,realpathSync,symlinkSync,linkSync} from 'node:fs';
import {sha256} from '../../release_schema6/package.mjs';
import {updateMcpSource,replaceJsonFields,fieldDiff,parseArguments} from '../../maintenance/update-mcp-source.mjs';
const H='a'.repeat(64);
const names=['i_remote_mcp/server.mjs','i_remote_mcp/oauth.mjs','i_remote_mcp/diagnostics.mjs','i_remote_mcp/mcp.mjs','i_remote_mcp/writeback.mjs','i_memory/i_memory_read.mjs'];
const put=(p,v)=>{mkdirSync(path.dirname(p),{recursive:true});writeFileSync(p,typeof v==='string'?v:JSON.stringify(v,null,2)+'\n');return sha256(readFileSync(p));};
const json=p=>JSON.parse(readFileSync(p,'utf8'));
export function createSourceUpdateFixture(t){
 const root=realpathSync(mkdtempSync(path.join(os.tmpdir(),'mcp-source-c1-')));t.after(()=>{assert.ok(path.basename(root).startsWith('mcp-source-c1-'));rmSync(root,{recursive:true,force:true});});
 const oldRoot=path.join(root,'old-source'),candidateDirectory=path.join(root,'candidate'),runtime=path.join(candidateDirectory,'runtime');
 const files=names.map((name,index)=>{const base=put(path.join(oldRoot,name),'// old '+name+'\n');const next=put(path.join(runtime,name),'// '+(index<4?'new':'old')+' '+name+'\n');return {path:name,base_sha256:base,result_sha256:next,changed:index<4};});
 const manifest={entry:names[0],source_commit:'b'.repeat(40),changed_files:4,files};put(path.join(candidateDirectory,'manifest.json'),manifest);
 const p=Object.fromEntries(['mcp','backup','login','task'].map(role=>[role,path.join(root,'settings',role+(role==='task'?'.xml':'.json'))]));
 const old={format:'schema6-mcp-v1',owner_sid:'S-1-5-21-100-200-300-1001',working_directory:oldRoot,entrypoint:names[0],source_files:files.map(e=>({path:e.path,sha256:e.base_sha256})),environment:{I_REMOTE_MCP_CHATGPT_ENABLED:'1',I_REMOTE_MCP_STATE_DIR:path.join(root,'mcp-state'),I_HOME:path.join(root,'home'),I_MEMORY_DB:path.join(root,'private','memory.sqlite'),I_MEMORY_POLICY:path.join(root,'private','policy.json')},database_path:path.join(root,'state','i-core.sqlite'),arguments:['serve','--public-url','https://synthetic.invalid'],listen_port:47862,unknown_future:{preserve:'verbatim'}};
 const mcpHash=put(p.mcp,old);
 const entries=[{role:'database',name:'core.sqlite',source_path:old.database_path,sha256:H},{role:'release',name:'manifest.json',source_path:path.join(root,'release','manifest.json'),sha256:H},...Object.entries(p).map(([role,filename])=>({role:role==='task'?'task':'configuration',name:role+(role==='task'?'.xml':'.json'),source_path:filename,sha256:role==='mcp'?mcpHash:H})),...files.map(e=>({role:'configuration',name:'mcp-source/'+e.path,source_path:path.join(oldRoot,e.path),sha256:e.base_sha256})),...['credentials','domain_policy','transcript_grants','replay_approvals','recovery_custody'].map(role=>({role,name:role+'.bin',source_path:path.join(root,'private',role+'.bin'),sha256:H}))];
 const backup={policy:{outputRoot:path.join(root,'backups'),retentionDays:30},sqliteEntryNames:['core.sqlite'],envelopePath:path.join(root,'private','envelope.json'),envelopeSha256:H,specTemplate:{format:'i-core-runtime-backup-spec-v1',source_schema:6,node_id:'synthetic-node',canonical_database_path:old.database_path,old_release_root:path.join(root,'release'),old_release_manifest_sha256:H,entries}};
 const backupHash=put(p.backup,backup);
 const login={format:'schema6-login-v1',owner_sid:old.owner_sid,state_directory:path.join(root,'state'),control_root:path.join(root,'sessions'),core_configuration_path:path.join(root,'settings','core.json'),core_configuration_sha256:H,core_port:47861,backup_key_directory:path.join(root,'keys'),mcp_configuration_path:p.mcp,mcp_configuration_sha256:mcpHash,backup_configuration_path:p.backup,backup_configuration_sha256:backupHash,unknown_future:'preserve'};
 let source={loginPath:p.login,loginSha256:put(p.login,login),taskXml:'<SyntheticOld enabled="true"/>',taskSddl:'synthetic-sddl'};
 const input={fromTask:'Synthetic-A',newTask:'Synthetic-B',candidateDirectory,outputDirectory:path.join(root,'output')};const operations=[];
 const taskBridge=request=>{operations.push(request);if(request.operation==='read')return structuredClone(source);if(request.operation==='check')return {taskXml:'<SyntheticNew enabled="false" login="'+request.loginPath+'" hash="'+request.loginSha256+'"/>'};if(request.operation==='register')return {registered:true};throw new Error('unexpected_adapter_operation');};
 const writeBundle=({out,files})=>{mkdirSync(out,{mode:0o700});for(const e of files)writeFileSync(path.join(out,e.name),e.text,{flag:'wx',mode:0o600});};
 const save=()=>{login.mcp_configuration_sha256=put(p.mcp,old);login.backup_configuration_sha256=put(p.backup,backup);source.loginSha256=put(p.login,login);};
 return {root,oldRoot,runtime,files,manifest,p,old,backup,login,source,input,operations,taskBridge,writeBundle,save};
}

test('C1 generates six-source configuration and registers disabled with only permitted fields',t=>{
 const f=createSourceUpdateFixture(t),before=Object.fromEntries(['mcp','backup','login'].map(k=>[k,readFileSync(f.p[k])]));
 const result=updateMcpSource(f.input,{taskBridge:f.taskBridge,writeBundle:f.writeBundle});
 assert.equal(result.generated,true);assert.equal(result.registered,true);assert.equal(result.dryRun,false);
 assert.deepEqual(result.diff,{mcp:['source_files','working_directory'],backup:['specTemplate.entries'],login:['backup_configuration_path','backup_configuration_sha256','mcp_configuration_path','mcp_configuration_sha256']});
 const next=json(path.join(f.input.outputDirectory,'mcp.json'));assert.equal(next.entrypoint,f.old.entrypoint);assert.deepEqual(next.environment,f.old.environment);assert.deepEqual(next.unknown_future,f.old.unknown_future);
 const login=json(result.loginPath);assert.equal(login.mcp_configuration_sha256,sha256(readFileSync(login.mcp_configuration_path)));assert.equal(login.backup_configuration_sha256,sha256(readFileSync(login.backup_configuration_path)));
 const backup=json(login.backup_configuration_path);assert.equal(backup.specTemplate.entries.length,f.backup.specTemplate.entries.length+10);
 for(const role of ['credentials','domain_policy','transcript_grants','replay_approvals','recovery_custody'])assert.deepEqual(backup.specTemplate.entries.find(e=>e.role===role),f.backup.specTemplate.entries.find(e=>e.role===role));
 for(const k of Object.keys(before))assert.deepEqual(readFileSync(f.p[k]),before[k]);
 assert.deepEqual(f.operations.map(e=>e.operation),['read','check','check','register']);assert.equal(f.operations.at(-1).loginSha256,result.loginSha256);
 // DB and key paths deliberately do not exist: generation never opens them.
 assert.equal(existsSync(f.old.database_path),false);assert.equal(existsSync(f.backup.envelopePath),false);
});

test('C1 dry-run completes prospective mapping and task validation with zero writes',t=>{
 const f=createSourceUpdateFixture(t);const result=updateMcpSource({...f.input,dryRun:true},{taskBridge:f.taskBridge,writeBundle:()=>assert.fail('write during dry-run')});
 assert.equal(result.generated,false);assert.equal(result.registered,false);assert.equal(existsSync(f.input.outputDirectory),false);assert.deepEqual(f.operations.map(e=>e.operation),['read','check']);
});

for(const kind of ['file-name','missing-file','extra-file','hash','entry','overlap','output-exists','login-hash','mcp-hash','backup-hash','backup-attachment','source-drift']){
 test('C1 rejects '+kind+' before writes',t=>{
  const f=createSourceUpdateFixture(t);
  if(kind==='file-name')f.manifest.files[0].path='i_remote_mcp/other.mjs';
  if(kind==='missing-file')rmSync(path.join(f.runtime,names[0]));
  if(kind==='extra-file')put(path.join(f.runtime,'extra.mjs'),'unexpected');
  if(kind==='hash')put(path.join(f.runtime,names[0]),'tampered');
  if(kind==='entry')f.manifest.entry=names[1];
  if(kind==='overlap')f.input.candidateDirectory=f.oldRoot;
  if(kind==='output-exists')mkdirSync(f.input.outputDirectory);
  if(kind==='login-hash')put(f.p.login,'{}');
  if(kind==='mcp-hash')put(f.p.mcp,'{}');
  if(kind==='backup-hash')put(f.p.backup,'{}');
  if(kind==='backup-attachment'){f.backup.specTemplate.entries=f.backup.specTemplate.entries.filter(e=>e.source_path!==f.p.mcp);f.save();}
  if(kind==='source-drift')put(path.join(f.oldRoot,names[0]),'tampered');
  put(path.join(f.input.candidateDirectory,'manifest.json'),f.manifest);
  assert.throws(()=>updateMcpSource(f.input,{taskBridge:f.taskBridge,writeBundle:()=>assert.fail('write before validation')}));
  assert.ok(!f.operations.some(e=>e.operation==='register'));
 });
}

test('C1 directory overlap rejects a valid candidate below state root',t=>{
 const f=createSourceUpdateFixture(t);f.login.state_directory=f.root;f.old.database_path=path.join(f.root,'i-core.sqlite');f.backup.specTemplate.canonical_database_path=f.old.database_path;f.backup.specTemplate.entries.find(e=>e.role==='database').source_path=f.old.database_path;f.save();
 assert.throws(()=>updateMcpSource(f.input,{taskBridge:f.taskBridge,writeBundle:f.writeBundle}),/directory_overlap/);assert.equal(existsSync(f.input.outputDirectory),false);
});

test('C1 retains previous switch backup history and preserves arbitrary commit/count',t=>{
 const f=createSourceUpdateFixture(t);f.backup.specTemplate.entries.push({role:'configuration',name:'preserved/mcp-config-switch-source/mcp.json',source_path:path.join(f.root,'previous','mcp.json'),sha256:H});f.save();
 f.manifest.source_commit='c'.repeat(40);f.manifest.changed_files=6;put(path.join(f.input.candidateDirectory,'manifest.json'),f.manifest);
 const result=updateMcpSource(f.input,{taskBridge:f.taskBridge,writeBundle:f.writeBundle});const next=json(path.join(f.input.outputDirectory,'daily-backup-config.json'));
 assert.deepEqual(next.specTemplate.entries[f.backup.specTemplate.entries.length-1],f.backup.specTemplate.entries.at(-1));assert.equal(result.registered,true);
});

test('C1 re-anchors input immediately before writes and preserves raw error text',t=>{
 const f=createSourceUpdateFixture(t),rows=[];let checks=0;
 const taskBridge=r=>{if(r.operation==='check'&&++checks===2)throw new Error('synthetic raw task definition changed');return f.taskBridge(r);};
 assert.throws(()=>updateMcpSource(f.input,{taskBridge,writeBundle:f.writeBundle,emit:r=>rows.push(r)}),/synthetic raw task definition changed/);
 assert.equal(existsSync(f.input.outputDirectory),false);assert.ok(rows.some(r=>!r.ok&&r.detail==='synthetic raw task definition changed'));
});

test('C1 keeps a failed registration bundle for review and does not retry',t=>{
 const f=createSourceUpdateFixture(t);let calls=0;const taskBridge=r=>{if(r.operation==='register'){calls++;throw new Error('synthetic create-only collision');}return f.taskBridge(r);};
 assert.throws(()=>updateMcpSource(f.input,{taskBridge,writeBundle:f.writeBundle}),/synthetic create-only collision/);assert.equal(calls,1);assert.equal(existsSync(path.join(f.input.outputDirectory,'login.json')),true);
});

test('top-level JSON editing keeps unrelated bytes including escapes, formatting and numbers',()=>{
 const text='{\r\n "working_directory" : "old", "source_files":[], "untouched" : {"escaped":"\\u0061","number":1e2}, "tricky": "},\\\"}"\r\n}\r\n';
 assert.equal(replaceJsonFields('\uFEFF'+text,{working_directory:'new'}).charCodeAt(0),0xFEFF);
 const next=replaceJsonFields(text,{working_directory:'new',source_files:[{path:'test.mjs',sha256:H}]});
 assert.ok(next.includes('"untouched" : {"escaped":"\\u0061","number":1e2}'));assert.ok(next.endsWith('"tricky": "},\\\"}"\r\n}\r\n'));assert.deepEqual(fieldDiff(JSON.parse(text),JSON.parse(next)),['source_files','working_directory']);
 assert.throws(()=>replaceJsonFields('{"x":1,"x":2}',{x:3}),/duplicate_json_key/);
});

test('CLI exposes only C1 inputs and rejects duplicate, unknown or missing flags',()=>{
 const args=['--from-task','A','--candidate','candidate','--out','output','--new-task','B'];assert.equal(parseArguments([...args,'--dry-run']).dryRun,true);
 for(const bad of [[...args,'--execute'],[...args,'--from-task','C'],args.slice(0,-1),['--dry-run']])assert.throws(()=>parseArguments(bad));
});

test('C1 preserves BOM and untouched Unicode bytes in all three generated configurations',t=>{
 const f=createSourceUpdateFixture(t);
 for(const role of ['mcp','backup'])writeFileSync(f.p[role],'\uFEFF'+readFileSync(f.p[role],'utf8'));
 f.login.mcp_configuration_sha256=sha256(readFileSync(f.p.mcp));f.login.backup_configuration_sha256=sha256(readFileSync(f.p.backup));
 put(f.p.login,f.login);writeFileSync(f.p.login,'\uFEFF'+readFileSync(f.p.login,'utf8'));f.source.loginSha256=sha256(readFileSync(f.p.login));
 const result=updateMcpSource(f.input,{taskBridge:f.taskBridge,writeBundle:f.writeBundle});assert.equal(result.registered,true);
 for(const name of ['mcp.json','daily-backup-config.json','login.json'])assert.deepEqual([...readFileSync(path.join(f.input.outputDirectory,name)).subarray(0,3)],[0xef,0xbb,0xbf]);
});

test('C1 rejects candidate hardlinks before creating output',t=>{
 const f=createSourceUpdateFixture(t);linkSync(path.join(f.runtime,names[0]),path.join(f.root,'linked-source.mjs'));
 assert.throws(()=>updateMcpSource(f.input,{taskBridge:f.taskBridge,writeBundle:f.writeBundle}));assert.equal(existsSync(f.input.outputDirectory),false);
});

test('C1 new Unicode path values use JSON escapes for the frozen ANSI-reading host',t=>{
 const f=createSourceUpdateFixture(t);f.input.outputDirectory=path.join(f.root,'新配置目录');
 const result=updateMcpSource(f.input,{taskBridge:f.taskBridge,writeBundle:f.writeBundle});
 const raw=readFileSync(result.loginPath,'utf8');assert.match(raw,/\\u65b0/);assert.equal(/[^\x00-\x7f]/.test(raw),false);
 const next=JSON.parse(raw);assert.equal(path.dirname(next.mcp_configuration_path),f.input.outputDirectory);
 const rawBackup=readFileSync(next.backup_configuration_path,'utf8');assert.equal(/[^\x00-\x7f]/.test(rawBackup),false);
});
