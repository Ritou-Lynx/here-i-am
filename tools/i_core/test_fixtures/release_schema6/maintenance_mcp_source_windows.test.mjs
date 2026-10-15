import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {existsSync,readFileSync,readdirSync,writeFileSync,mkdirSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {sha256,cleanEnvironment} from '../../release_schema6/package.mjs';
import {createRuntimeLab,repository,ps,cleanReceipt,protect,removeOwned} from '../../release_schema6/lifecycle/test-fixture.mjs';
import {loginConfig,loginArgs,refreshLogin,configureManagedMcp,host,connectManaged} from '../../release_schema6/lifecycle/mcp-session-test-fixture.mjs';
import {allocateSyntheticLoopbackPort} from './mcp_reader/helper.mjs';
import {syntheticRoot} from './synthetic_paths.mjs';
import {updateMcpSource,windowsTaskBridge} from '../../maintenance/update-mcp-source.mjs';
const here=path.dirname(fileURLToPath(import.meta.url));
const maintenance=path.join(repository,'tools/i_core/maintenance'),bridge=path.join(maintenance,'update-mcp-source-task.ps1');
const json=p=>JSON.parse(readFileSync(p,'utf8'));
const hash=p=>sha256(readFileSync(p));
const esc=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
const options={skip:process.platform!=='win32',timeout:720000};
const rows=result=>result.stdout.trim().split(/\r?\n/).filter(Boolean).map(line=>JSON.parse(line));
function invoke(script,args=[],input){
 return spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(here,script),...args],
  {env:cleanEnvironment(),input:input&&JSON.stringify(input),windowsHide:true,encoding:'utf8',timeout:540000});
}
function controls(root){return readdirSync(root,{withFileTypes:true}).filter(e=>e.isDirectory()&&e.name.startsWith('session-')).flatMap(e=>{
 const session=path.join(root,e.name);return readdirSync(session,{withFileTypes:true}).filter(c=>c.isDirectory()&&c.name.startsWith('control-')).map(c=>path.join(session,c.name));
});}
function assertClean(control){
 for(const [file,key] of [['session-close.json','clean_closed'],['mcp-stop.json','job_empty_confirmed'],['supervisor.json','lock_released_confirmed']])assert.equal(json(path.join(control,file))[key],true,file);
 const supervisor=json(path.join(control,'supervisor.json'));assert.equal(supervisor.result.job_empty_confirmed,true);assert.equal(supervisor.result.termination_requested,false);
 assert.equal(json(path.join(control,'child.json')).phase,'clean_closed');
 assert.equal(json(path.join(path.dirname(control),'session-exit.json')).clean_closed,true);
}

test('MCP source update: real A session, real generated files and registration, A switch to B without recovery',options,async t=>{
 const l=await createRuntimeLab(t),a=loginConfig(l,await allocateSyntheticLoopbackPort());
 const mcp=await configureManagedMcp(l,a);
 const settings=path.dirname(a.file),backupPath=path.join(settings,'daily-backup-config.json'),taskPath=path.join(settings,'login-task.xml'),H='a'.repeat(64);
 // This suite proves source/scheduler/session continuity, not daily backup success.
 // An unpublished synthetic portable envelope causes the existing backup worker's
 // normal isolated failure path; no backup or envelope validation is bypassed.
 const manifest=json(path.join(l.release,'manifest.json'));
 writeFileSync(path.join(settings,'icore-task.xml'),'<Task name="iCore"/>');writeFileSync(path.join(settings,'iremote-task.xml'),'<Task name="iRemoteMCP"/>');writeFileSync(path.join(settings,'previous-session.xml'),'<Task name="preserved"/>');
 const backup={policy:{format:'i-core-automatic-backup-v1',outputRoot:l.configuration.backup_directory,retentionDays:30,backupSetId:H},envelopePath:path.join(settings,'unpublished-synthetic-envelope.json'),envelopeSha256:H,sqliteEntryNames:['core.sqlite'],specTemplate:{format:'i-core-runtime-backup-spec-v1',source_schema:6,node_id:l.configuration.node_id,canonical_database_path:l.configuration.database_path,old_release_root:l.release,old_release_manifest_sha256:l.manifestHash,entries:[
  {role:'database',name:'core.sqlite',source_path:l.configuration.database_path,sha256:H},
  ...manifest.files.map(e=>({role:'release',name:e.path,source_path:path.join(l.release,e.path),sha256:e.sha256})),
  {role:'release',name:'manifest.json',source_path:path.join(l.release,'manifest.json'),sha256:l.manifestHash},
  ...[[l.configPath,'core.json'],[mcp.file,'mcp.json'],[backupPath,'daily-backup-config.json'],[a.file,'login.json']].map(([p,name])=>({role:'configuration',name,source_path:p,sha256:p===mcp.file?hash(p):H})),
  {role:'task',name:'tasks/HereIAm-iCore.xml',source_path:path.join(settings,'icore-task.xml'),sha256:H},
  {role:'task',name:'tasks/HereIAm-iRemoteMCP.xml',source_path:path.join(settings,'iremote-task.xml'),sha256:H},
  {role:'task',name:'tasks/HereIAm-CoreSchema6-Session.xml',source_path:taskPath,sha256:H},
  {role:'task',name:'preserved/mcp-config-switch-source/session.xml',source_path:path.join(settings,'previous-session.xml'),sha256:H},
  ...mcp.configuration.source_files.map(e=>({role:'configuration',name:'mcp-source/'+e.path,source_path:path.join(mcp.source,e.path),sha256:e.sha256})),
  ...['credentials','domain_policy','transcript_grants','replay_approvals','recovery_custody'].map(role=>({role,name:role+'.bin',source_path:path.join(settings,role+'.bin'),sha256:H}))
 ]}};
 writeFileSync(backupPath,JSON.stringify(backup));
 Object.assign(a.configuration,{backup_configuration_path:backupPath,backup_configuration_sha256:hash(backupPath),backup_key_directory:path.dirname(l.configuration.backup_key_path)});refreshLogin(a);
 const argumentsA=loginArgs(l,a).map(v=>'"'+v+'"').join(' ');
 const xml='<Task><Settings><Enabled>true</Enabled></Settings><Actions><Exec><Command>'+esc(ps)+'</Command><Arguments>'+esc(argumentsA)+'</Arguments><WorkingDirectory>'+esc(l.release)+'</WorkingDirectory></Exec></Actions></Task>';
 writeFileSync(taskPath,xml);
 const candidate=l.dir('source-candidate-中文'),runtime=path.join(candidate,'runtime');mkdirSync(runtime);protect(runtime);
 const files=mcp.configuration.source_files.map((e,i)=>{const destination=path.join(runtime,e.path);mkdirSync(path.dirname(destination),{recursive:true});const bytes=readFileSync(path.join(mcp.source,e.path));writeFileSync(destination,Buffer.concat([bytes,Buffer.from(i===0?'\n// Synthetic source-only update.\n':'')]));return {path:e.path,result_sha256:hash(destination)};});
 writeFileSync(path.join(candidate,'manifest.json'),JSON.stringify({entry:mcp.configuration.entrypoint,files}));
 const run=await host(l,a);await run.ready();await connectManaged(run,mcp,{requireMessage:false});
 const recoveryBefore=readdirSync(l.configuration.recovery_custody_directory).filter(n=>n.endsWith('.recovery.json')).sort();
 const oldTask={Name:'Synthetic-A',Path:ps,Arguments:argumentsA,WorkingDirectory:l.release,Enabled:true,State:4,ConfigurationSha256:a.hash,ControlRoot:a.controlRoot,taskXml:xml,taskSddl:'O:'+l.configuration.owner_sid+'G:'+l.configuration.owner_sid+'D:P(A;;FA;;;'+l.configuration.owner_sid+')(A;;FA;;;SY)(A;;FA;;;BA)'};
 const schedulerPath=path.join(l.root,'synthetic-scheduler.json');writeFileSync(schedulerPath,JSON.stringify({tasks:[oldTask]}));
 const calls=[];
 const taskBridge=request=>{
  calls.push(request.operation);
  if(request.operation==='write')return windowsTaskBridge(request);
  const invoked=invoke('mcp_source_update_adapter.ps1',['-StatePath',schedulerPath,'-Bridge',bridge],request);
  assert.equal(invoked.status,0,invoked.stdout+invoked.stderr);
  const result=rows(invoked).findLast(r=>r.step==='update.task.result');assert.equal(result.ok,true);return result.result;
 };
 const generated=updateMcpSource({fromTask:'Synthetic-A',newTask:'Synthetic-B',candidateDirectory:candidate,outputDirectory:path.join(l.root,'generated-中文')},{taskBridge});
 assert.equal(generated.registered,true);assert.equal(generated.generated,true);assert.ok(calls.includes('register'));assert.ok(calls.includes('write'));
 const registered=json(schedulerPath);assert.deepEqual(registered.tasks[0],oldTask);assert.equal(registered.tasks[1].Enabled,false);
 const bLogin=json(generated.loginPath),bMcp=json(bLogin.mcp_configuration_path);
 assert.equal(bMcp.working_directory,runtime);assert.deepEqual(bMcp.environment,mcp.configuration.environment);
 assert.equal(bLogin.control_root,a.controlRoot);assert.equal(bLogin.core_configuration_sha256,a.configuration.core_configuration_sha256);
 assert.equal(hash(generated.loginPath),generated.loginSha256);
 // Use the unchanged contract A orchestration and real native hosts. Scheduler
 // reads/starts are synthetic, and B uses the exact arguments registered above.
 const inputPath=path.join(l.root,'switch-input.json');writeFileSync(inputPath,'\uFEFF'+JSON.stringify({scenario:'success',from:'Synthetic-A',to:'Synthetic-B',initialPid:run.child.pid,tasks:registered.tasks}));
 const switched=invoke('safe_switch_session.ps1',['-InputPath',inputPath,'-MaintenanceDirectory',maintenance]);
 assert.equal(switched.status,0,switched.stdout+switched.stderr);
 const report=rows(switched).findLast(r=>r.format==='schema6-safe-switch-test-v1');
 assert.equal(report.code,0,switched.stdout+switched.stderr);assert.equal(report.error,null);assert.equal(report.cleanup,true);assert.equal(report.enabledA,false);assert.equal(report.enabledB,true);
 assert.deepEqual(report.active,['Synthetic-B']);assert.deepEqual(report.mutations,['Disable:Synthetic-A','Enable:Synthetic-B','Start:Synthetic-B']);
 await run.wait();cleanReceipt(run);
 const closed=controls(a.controlRoot);assert.equal(closed.length,2);
 for(const c of closed){assert.ok(existsSync(path.join(c,'ready.json')));assert.ok(existsSync(path.join(c,'mcp-start.json')));assertClean(c);}
 assert.equal(existsSync(path.join(l.state,'s6-recovery-pending.json')),false);
 for(const suffix of ['-wal','-shm','-journal'])assert.equal(existsSync(l.configuration.database_path+suffix),false);
 assert.deepEqual(readdirSync(l.configuration.recovery_custody_directory).filter(n=>n.endsWith('.recovery.json')).sort(),recoveryBefore);
 assert.equal(json(path.join(l.state,'s6-lifecycle.json')).phase,'clean_closed');
 l.completed=true;
});

test('MCP source update COM: create disabled, preserve old task and arguments, duplicate fails, clean nonce tasks',{
 skip:process.platform!=='win32'||process.env.CI!=='true'||process.env.SCHEMA6_SYNTHETIC_TASK_TEST!=='1',timeout:120000
},t=>{
 const root=syntheticRoot('mcp-source-com-');protect(root);let cleanup=false;
 t.after(()=>{if(cleanup)removeOwned(root,'mcp-source-com-');else t.diagnostic('Synthetic COM evidence retained because task deletion was not confirmed');});
 const invoked=spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(here,'mcp_source_update_com.ps1'),'-Bridge',bridge,'-Root',root],{windowsHide:true,encoding:'utf8',timeout:110000});
 const report=rows(invoked).findLast(r=>r.format==='schema6-mcp-source-com-v1');cleanup=report?.deleted===true;
 assert.equal(invoked.status,0,invoked.stdout+invoked.stderr);assert.ok(report);t.diagnostic(JSON.stringify(report));
 for(const key of ['created','disabled','arguments_preserved','old_unchanged','duplicate_rejected','candidate_acl_rejected','security_duplicate_equal','security_extra_principal_rejected','security_changed_rights_rejected','semantic_equal','owner_equal','group_equal','protected_equal','deleted'])assert.equal(report[key],true,key);
});

test('MCP source bridge preserves UTF-8 stdin and the original Chinese exception across processes',{skip:process.platform!=='win32'},t=>{
 const root=syntheticRoot('mcp-source-unicode-');t.after(()=>removeOwned(root,'mcp-source-unicode-'));
 const state=path.join(root,'合成登记状态.json');
 const out=path.join(root,'中文输出目录');const text=JSON.stringify({字段:'中文值保真'});
 assert.equal(windowsTaskBridge({operation:'write',out,files:[{name:'field-diff.json',text}]}).written,true);
 assert.equal(readFileSync(path.join(out,'field-diff.json'),'utf8'),text);
 const detail='合成登记失败：路径中文与异常原文保持一致';
 writeFileSync(state,JSON.stringify({tasks:[],injectedError:detail}));
 const invoked=invoke('mcp_source_update_adapter.ps1',['-StatePath',state,'-Bridge',bridge],{operation:'read',fromTask:'旧任务中文',newTask:'新任务中文'});
 assert.equal(invoked.status,2);
 const result=rows(invoked).findLast(r=>r.step==='update.task.result');assert.equal(result.ok,false);assert.equal(result.detail,detail);
});
