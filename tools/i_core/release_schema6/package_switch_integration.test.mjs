import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, existsSync, unlinkSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { sha256, cleanEnvironment } from './package.mjs';
import { createRuntimeLab, repository, ps, until, cleanReceipt, protect, api } from './lifecycle/test-fixture.mjs';
import { preparePackageSwitch } from '../maintenance/prepare-package-switch.mjs';
import { loginConfig, configureManagedMcp } from './lifecycle/mcp-session-test-fixture.mjs';
const BASE='b71799706719b0e603124d108c2795caa0a98933';
const hashFile=p=>sha256(readFileSync(p));
test('real 47-file historical binary upgrades to new package and zero-business reverses to the unchanged old binary',{skip:process.platform!=='win32',timeout:1800000},async t=>{
 const l=await createRuntimeLab(t);
 const execPath=execFileSync('git',['--exec-path'],{encoding:'utf8',windowsHide:true}).trim(),gitPath=path.resolve(execPath,'../../../bin/git.exe');
 const oldSource=execFileSync(gitPath,['-C',repository,'show',BASE+':tools/i_core/release_schema6/package.mjs'],{windowsHide:true,env:cleanEnvironment()});
 const oldApi=await import('data:text/javascript;base64,'+oldSource.toString('base64'));
 const built=path.join(l.root,'old-built');const oldPrepared=oldApi.prepareRelease({repository,sourceCommit:BASE,output:built,nodePath:path.join(l.release,'runtime/node.exe'),gitPath});
 const oldRelease=l.dir('old-release');for(const name of [...oldApi.INVENTORY,'manifest.json']){const p=path.join(oldRelease,name);mkdirSync(path.dirname(p),{recursive:true});copyFileSync(path.join(built,name),p);}
 assert.equal(oldApi.INVENTORY.length,47);assert.equal(hashFile(path.join(oldRelease,'tools/i_core/release_schema6/package.mjs')),sha256(oldSource));
 const oldConfig=path.join(path.dirname(l.configPath),'old.json');writeFileSync(oldConfig,JSON.stringify({...l.configuration,manifest_sha256:oldPrepared.manifest_sha256}));
 const old={releaseDirectory:oldRelease,manifestSha256:oldPrepared.manifest_sha256,configurationPath:oldConfig,configurationSha256:hashFile(oldConfig)};
 const next={releaseDirectory:l.release,manifestSha256:l.manifestHash,configurationPath:l.configPath,configurationSha256:hashFile(l.configPath)};
 function launch(end,{initial=false,args=[]}={}){
  const control=l.dir('switch-control-'+randomBytes(5).toString('hex')),entry=path.join(end.releaseDirectory,'tools/i_core/release_schema6/lifecycle');
  const child=spawn(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(entry,'start_schema6.ps1'),'-ManifestSha256',end.manifestSha256,'-Start','-StateDirectory',l.state,'-ControlDirectory',control,'-ConfigurationFile',end.configurationPath,...(initial?['-InitializeEmpty']:[]),...args],
   {env:cleanEnvironment(),windowsHide:true,stdio:['ignore','pipe','pipe']});
  const run={child,control,closed:false,exit:null,stdout:'',stderr:''};child.stdout.on('data',x=>run.stdout+=x);child.stderr.on('data',x=>run.stderr+=x);child.on('close',code=>{run.closed=true;run.exit=code;});
  run.read=n=>existsSync(path.join(control,n))?JSON.parse(readFileSync(path.join(control,n))):null;
  run.wait=async()=>{await until(()=>run.closed,180000);return run;};
  run.ready=async()=>{await until(()=>run.read('ready.json')||run.closed,180000);assert.equal(run.closed,false,run.stdout+run.stderr+JSON.stringify(run.read('child.json')));return run.read('ready.json');};
  run.stop=(action='close')=>execFileSync(ps,['-NoProfile','-NonInteractive','-File',path.join(entry,'request_stop.ps1'),'-ControlDirectory',control,'-RunId',run.read('launch.json').token,'-ManifestSha256',end.manifestSha256,'-Action',action],{env:cleanEnvironment(),windowsHide:true});
  l.registerRun(run);return run;
 }
 const oldRun=launch(old,{initial:true});await oldRun.ready();oldRun.stop();await oldRun.wait();cleanReceipt(oldRun);
 // These configurations use the real package bytes and the fixed legacy MCP
 // source. Preparation validates every cross-binding; no task is registered.
 const stagedLogin=loginConfig(l,47861),managed=await configureManagedMcp(l,stagedLogin);
 const template=readFileSync(path.join(l.lifecycle,'prepare_login_schema6.ps1'),'utf8').match(/\$document\.LoadXml\('([^']+)'\)/)?.[1];assert.ok(template);
 const esc=v=>v.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
 const placeholder='a'.repeat(64),settings=path.dirname(l.configPath);
 const deployment=new Map([old,next].map((end,index)=>{
  const names=Object.fromEntries(['backup','login','mcp','task'].map(role=>[role,path.join(settings,'prepared-'+index+'-'+role+(role==='task'?'.xml':'.json'))]));
  const core=JSON.parse(readFileSync(end.configurationPath)),mcp={...managed.configuration,executable_path:path.join(end.releaseDirectory,'runtime/node.exe')};
  const manifest=JSON.parse(readFileSync(path.join(end.releaseDirectory,'manifest.json')));
  const backup={policy:{format:'i-core-automatic-backup-v1',outputRoot:l.configuration.backup_directory,retentionDays:30,backupSetId:placeholder},envelopePath:path.join(settings,'synthetic-portable-envelope.json'),envelopeSha256:placeholder,sqliteEntryNames:['core.sqlite'],specTemplate:{format:'i-core-runtime-backup-spec-v1',source_schema:6,node_id:'synthetic-node',canonical_database_path:core.database_path,old_release_root:end.releaseDirectory,old_release_manifest_sha256:end.manifestSha256,entries:[
   {role:'database',name:'core.sqlite',source_path:core.database_path,sha256:placeholder},
   ...manifest.files.map(e=>({role:'release',name:e.path,source_path:path.join(end.releaseDirectory,e.path),sha256:e.sha256})),
   {role:'release',name:'manifest.json',source_path:path.join(end.releaseDirectory,'manifest.json'),sha256:end.manifestSha256},
   {role:'configuration',name:'core.json',source_path:end.configurationPath,sha256:placeholder},
   ...['login','mcp'].map(role=>({role:'configuration',name:role+'.json',source_path:names[role],sha256:placeholder})),
   {role:'task',name:'task.xml',source_path:names.task,sha256:placeholder},
   ...['credentials','domain_policy','transcript_grants','replay_approvals','recovery_custody'].map(role=>({role,name:role+'.bin',source_path:path.join(settings,role+'.bin'),sha256:placeholder}))
  ]}};
  writeFileSync(names.mcp,JSON.stringify(mcp));writeFileSync(names.backup,JSON.stringify(backup));
  const login={...stagedLogin.configuration,release_directory:end.releaseDirectory,manifest_sha256:end.manifestSha256,core_configuration_path:end.configurationPath,core_configuration_sha256:end.configurationSha256,backup_configuration_path:names.backup,backup_configuration_sha256:hashFile(names.backup),backup_key_directory:path.dirname(core.backup_key_path),mcp_configuration_path:names.mcp,mcp_configuration_sha256:hashFile(names.mcp)};
  writeFileSync(names.login,JSON.stringify(login));
  const args=['-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',path.join(end.releaseDirectory,'tools/i_core/release_schema6/lifecycle/login_schema6.ps1'),'-ReleaseDirectory',end.releaseDirectory,'-ManifestSha256',end.manifestSha256,'-LoginConfigurationPath',names.login,'-LoginConfigurationSha256',hashFile(names.login)];
  const xml=template.replaceAll('<UserId />','<UserId>'+esc(core.owner_sid)+'</UserId>').replace('<Command />','<Command>'+esc(ps)+'</Command>').replace('<Arguments />','<Arguments>'+esc(args.map(v=>'"'+v+'"').join(' '))+'</Arguments>');writeFileSync(names.task,xml);
  return [end.manifestSha256,Object.entries(names).map(([role,p])=>({role,path:p,sha256:hashFile(p)}))];
 }));
 const makePlan=(from,to,rollbackOf=null)=>{
  const prepared=preparePackageSwitch({operationId:'native-'+randomBytes(5).toString('hex'),from,to,rollbackOf,
   headPath:path.join(l.configuration.recovery_custody_directory,'current-head.json'),markerPath:path.join(l.state,'s6-lifecycle.json'),artifacts:deployment.get(to.manifestSha256),fromArtifacts:deployment.get(from.manifestSha256)});
  assert.equal(prepared.bindingReport.validated,true);assert.equal(prepared.bindingReport.taskXmlBound,true);assert.equal(prepared.bindingReport.mcpProgramAndPolicyPreserved,true);
  assert.equal(prepared.plan.approved,false);assert.equal(prepared.report.deploymentReady,false);assert.equal(prepared.report.registered,false);
  // This synthetic fixture supplies approval only after inspecting the complete
  // preparation report. Production remains an independent human approval gate.
  const value={...prepared.plan,approved:true};
  const p=path.join(settings,value.operationId+'.json');writeFileSync(p,JSON.stringify(value));return {p,sha:hashFile(p)};
 };
 const apply=async plan=>{const input=JSON.parse(readFileSync(plan.p)),begin=performance.now();const run=launch(next,{args:['-OfflineOperation','package-switch','-PackageSwitchPlan',plan.p,'-PackageSwitchSha256',plan.sha]});await run.wait();cleanReceipt(run);t.diagnostic(JSON.stringify({operationId:input.operationId,forwardReverse:input.rollbackOf?'reverse':'forward',elapsedMs:Math.round(performance.now()-begin)}));return run.read('operation.json');};

 // Fault injection exists only in this synthetic test copy of the adapter.
 // Both restart attempts below execute the actual unmodified package binaries.
 const adapterUrl=new URL('./recovery_adapter.mjs',import.meta.url);
 let adapterSource=readFileSync(adapterUrl,'utf8').replaceAll("'./lifecycle/offline_lease.mjs'","'../test_fixtures/release_schema6/recovery/synthetic_lease.mjs'");
 adapterSource=adapterSource.replace(/from '([^']+)'/g,(all,n)=>n.startsWith('.')?`from '${new URL(n,adapterUrl).href}'`:all);
 const syntheticAdapter=await import('data:text/javascript;base64,'+Buffer.from(adapterSource).toString('base64'));
 const {syntheticLease}=await import('../test_fixtures/release_schema6/recovery/synthetic_lease.mjs');
 const custodyKey=execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(l.release,'tools/i_core/release_schema6/key_custody.ps1'),'-Action','Read','-KeyDirectory',path.dirname(l.configuration.recovery_key_path),'-Purpose','recovery'],{env:cleanEnvironment(),windowsHide:true});
 try{
  for(const phase of ['package_switch_after_pending','package_switch_after_head']){
   const plan=makePlan(old,next),databasePath=path.join(l.state,'i-core.sqlite');
   // Prior native cleanReceipt confirms this synthetic root has no lock holder.
   unlinkSync(path.join(l.configuration.recovery_custody_directory,'custody.lock'));
   const capability=syntheticLease({databasePath,origin:'package_switch',cleanCloseReceipt:null},at=>{if(at===phase)throw new Error('synthetic durable interruption');});
   assert.throws(()=>syntheticAdapter.switchClosedPackage({databasePath,custodyDirectory:l.configuration.recovery_custody_directory,custodyKey,supervisorLease:capability,planPath:plan.p,planSha256:plan.sha,receiptId:randomBytes(32).toString('hex')}),/synthetic durable interruption/);
   for(const end of [old,next]){
    const denied=launch(end);await denied.wait();assert.notEqual(denied.exit,0);
    assert.equal(denied.read('ready.json'),null);
    assert.equal(denied.read('child.json')?.store_construction_attempted,false,denied.stdout+denied.stderr+JSON.stringify(denied.read('child.json')));
   }
   const resumed=await apply(plan);await apply(makePlan(next,old,resumed.event_sha256));
   t.diagnostic(phase+': actual old/new restart rejected before store; native resume/reverse passed');
  }

  for(const checkpoint of ['target_marker_committed','custody_pending_deleted']){
   let forwardEvent=null;
   for(const reverse of [false,true]){
    const plan=makePlan(reverse?next:old,reverse?old:next,reverse?forwardEvent:null),databasePath=path.join(l.state,'i-core.sqlite');
    unlinkSync(path.join(l.configuration.recovery_custody_directory,'custody.lock'));
    const capability=syntheticLease({databasePath,origin:'package_switch',cleanCloseReceipt:null});
    const committed=syntheticAdapter.switchClosedPackage({databasePath,custodyDirectory:l.configuration.recovery_custody_directory,custodyKey,supervisorLease:capability,planPath:plan.p,planSha256:plan.sha,receiptId:randomBytes(32).toString('hex')});
    writeFileSync(path.join(l.state,'s6-lifecycle.json'),JSON.stringify({...committed.marker,phase:'clean_closed',supervisor:{job_empty_confirmed:true,child_exit_code:0,guardian_exit_code:0,termination_requested:false}}));
    if(checkpoint==='custody_pending_deleted')unlinkSync(path.join(l.configuration.recovery_custody_directory,'package-switch-pending.json'));
    for(const end of [old,next]){
     const denied=launch(end);await denied.wait();assert.notEqual(denied.exit,0);assert.equal(denied.read('ready.json'),null);
     assert.equal(denied.read('child.json')?.store_construction_attempted,false);
    }
    const resumed=await apply(plan);if(!reverse)forwardEvent=resumed.event_sha256;
    t.diagnostic(checkpoint+' '+(reverse?'reverse':'forward')+': actual old/new rejected; native resume passed');
   }
  }

 }finally{custodyKey.fill(0);}

 const forward=await apply(makePlan(old,next));assert.ok(forward.event_sha256);
 const newRun=launch(next),newReady=await newRun.ready();assert.equal(newReady.health.schema_version,6);newRun.stop();await newRun.wait();cleanReceipt(newRun);
 const absentProof=makePlan(next,old),absentRun=launch(next,{args:['-OfflineOperation','package-switch','-PackageSwitchPlan',absentProof.p,'-PackageSwitchSha256',absentProof.sha]});await absentRun.wait();assert.notEqual(absentRun.exit,0);assert.equal(absentRun.read('child.json')?.error_code,'switch_reverse_proof_required');
 const reverse=await apply(makePlan(next,old,forward.event_sha256));assert.ok(reverse.custody_generation>forward.custody_generation);
 const unchangedOld=launch(old);await unchangedOld.ready();unchangedOld.stop();await unchangedOld.wait();cleanReceipt(unchangedOld);
 const forward2=await apply(makePlan(old,next));const writer=launch(next),ready=await writer.ready();
 await api(ready,'/devices/pair',null,{device_id:'package-switch-writer',display_name:'synthetic',platform:'test',client_version:'1',capabilities:['chat'],pairing_code:l.configuration.pairing_secret});
 writer.stop();await writer.wait();cleanReceipt(writer);
 const refusePlan=makePlan(next,old,forward2.event_sha256),refuse=launch(next,{args:['-OfflineOperation','package-switch','-PackageSwitchPlan',refusePlan.p,'-PackageSwitchSha256',refusePlan.sha]});
 await refuse.wait();assert.notEqual(refuse.exit,0);assert.equal(refuse.read('ready.json'),null);assert.equal(refuse.read('child.json')?.error_code,'switch_business_changed');
 const bypassPlan=makePlan(next,old),bypass=launch(next,{args:['-OfflineOperation','package-switch','-PackageSwitchPlan',bypassPlan.p,'-PackageSwitchSha256',bypassPlan.sha]});await bypass.wait();assert.notEqual(bypass.exit,0);assert.equal(bypass.read('child.json')?.error_code,'switch_reverse_proof_required');
 assert.equal(hashFile(path.join(oldRelease,'tools/i_core/release_schema6/package.mjs')),sha256(oldSource));
 l.completed=true;
});
