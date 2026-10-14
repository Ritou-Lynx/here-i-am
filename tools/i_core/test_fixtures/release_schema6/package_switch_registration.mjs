import assert from 'node:assert/strict';
import {execFileSync,spawn,spawnSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import {readFileSync,writeFileSync,mkdirSync,copyFileSync,existsSync,readdirSync,lstatSync} from 'node:fs';
import path from 'node:path';
import {INVENTORY,sha256,cleanEnvironment} from '../../release_schema6/package.mjs';
import {createRuntimeLab,repository,ps,until,cleanReceipt,protect} from '../../release_schema6/lifecycle/test-fixture.mjs';
import {loginConfig,configureManagedMcp,host,connectManaged} from '../../release_schema6/lifecycle/mcp-session-test-fixture.mjs';
import {allocateSyntheticLoopbackPort} from './mcp_reader/helper.mjs';
import {preparePackageSwitch} from '../../maintenance/prepare-package-switch.mjs';
import {generateRegistrationEvidence,generateCloseInput,generateOldTaskEvidence} from '../../maintenance/generate-package-switch-evidence.mjs';
import {validatePackageSwitchRegistration} from '../../maintenance/package-switch-registration.mjs';
const BASE='b71799706719b0e603124d108c2795caa0a98933',hashFile=p=>sha256(readFileSync(p));
const ref=p=>({path:p,sha256:hashFile(p)}),quote=s=>"'"+s.replaceAll("'","''")+"'";
export async function registrationLab(t){
 assert.equal(process.env.GITHUB_ACTIONS,'true','r2_fixture_ci_only');
 assert.equal(process.env.SCHEMA6_SYNTHETIC_TASK_TEST,'1','r2_fixture_synthetic_task_opt_in_required');
 // Run task cleanup before createRuntimeLab removes its private artifact root.
 let cleanupTasks=()=>{};t.after(()=>cleanupTasks());
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
 // These configurations use the real package bytes and the fixed legacy MCP
 // source. Preparation validates every cross-binding; no task is registered.
 const stagedLogin=loginConfig(l,await allocateSyntheticLoopbackPort()),managed=await configureManagedMcp(l,stagedLogin);
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

 // Backup validation is private even for synthetic templates. No real key or
 // database is referenced; failed scheduled fixture backup is not a success claim.
 const backupPaths=[old,next].map(e=>deployment.get(e.manifestSha256).find(a=>a.role==='backup').path);
 const aclScript='$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User;$a=New-Object Security.AccessControl.FileSecurity;$a.SetOwner($sid);$a.SetAccessRuleProtection($true,$false);foreach($id in @($sid,[Security.Principal.SecurityIdentifier]::new("S-1-5-18"))){$a.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($id,"FullControl","Allow"))};foreach($p in @('+backupPaths.map(quote).join(',')+')){Set-Acl -LiteralPath $p -AclObject $a}';
 const aclPath=path.join(settings,'protect-synthetic-backup.ps1');writeFileSync(aclPath,aclScript);
 execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',aclPath],{env:cleanEnvironment(),windowsHide:true});
 const oldLogin=deployment.get(old.manifestSha256).find(a=>a.role==='login');
 const c={file:oldLogin.path,hash:oldLogin.sha256,configuration:JSON.parse(readFileSync(oldLogin.path)),controlRoot:stagedLogin.controlRoot};
 const run=await host({...l,release:old.releaseDirectory,lifecycle:path.join(old.releaseDirectory,'tools/i_core/release_schema6/lifecycle'),manifestHash:old.manifestSha256,configPath:old.configurationPath,configuration:JSON.parse(readFileSync(old.configurationPath))},c);
 await run.ready();await connectManaged(run,managed,{requireMessage:false});
 const maintenance=l.dir('maintenance');
 for(const file of ['close-schema6-session.ps1','process_image_binding.ps1'])copyFileSync(path.join(repository,'tools/i_core/maintenance',file),path.join(maintenance,file));
 const script=path.join(maintenance,'close-schema6-session.ps1'),helper=path.join(maintenance,'process_image_binding.ps1');
 // The production inspector uses the existing task boundary's read-only CI
 // adapter to locate this real live host. No scheduler task is started here.
 const bindingPath=path.join(maintenance,'synthetic-task-binding.json');
 const closeTaskName='HereIAm-Synthetic-R1-Pairing-'+randomBytes(16).toString('hex');
 writeFileSync(bindingPath,JSON.stringify({initialPid:run.child.pid,task:{Name:closeTaskName,Path:ps,WorkingDirectory:'',
  Arguments:['-LoginConfigurationPath',c.file,'-LoginConfigurationSha256',c.hash].map(v=>'"'+v+'"').join(' ')}}));
 let inspectionSequence=0;
 const runPowerShell=(source,request)=>{
  const wrapper=path.join(maintenance,'close-inspector-'+(++inspectionSequence)+'.ps1');
  writeFileSync(wrapper,[
   "$ErrorActionPreference='Stop';Set-StrictMode -Version 2",
   '. '+quote(path.join(repository,'tools/i_core/test_fixtures/release_schema6/r1_pairing_session.ps1'))+' -InputPath '+quote(bindingPath)+' -MaintenanceDirectory '+quote(path.join(repository,'tools/i_core/maintenance')),
   '$request=[Console]::In.ReadToEnd()|ConvertFrom-Json',source
  ].join('\n'));
  return JSON.parse(execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',wrapper],
   {env:{...cleanEnvironment(),GITHUB_ACTIONS:'true'},windowsHide:true,encoding:'utf8',timeout:120000,input:JSON.stringify(request)}));
 };
 const receiptPath=path.join(maintenance,'close-receipt.json');
 const draftPath=path.join(maintenance,'close-unapproved.json');
 generateCloseInput({task:closeTaskName,out:draftPath,maintenanceDirectory:maintenance,receipt:receiptPath},{runPowerShell});
 const draft=JSON.parse(readFileSync(draftPath));assert.equal(draft.approved,false);
 const invokeClose=p=>spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',script,'-ConfigurationPath',p,'-ConfigurationSha256',hashFile(p)],{env:cleanEnvironment(),windowsHide:true,encoding:'utf8',timeout:120000});
 const unapproved=invokeClose(draftPath);assert.equal(unapproved.status,2,unapproved.stdout+unapproved.stderr);
 assert.equal(run.closed,false);assert.equal(existsSync(receiptPath),false);
 const draftHash=hashFile(draftPath);
 assert.throws(()=>generateCloseInput({task:closeTaskName,out:draftPath,maintenanceDirectory:maintenance,receipt:receiptPath},{runPowerShell}));
 assert.equal(hashFile(draftPath),draftHash);
 const inputPath=path.join(maintenance,'approved.json');
 generateCloseInput({task:closeTaskName,out:inputPath,approve:true,maintenanceDirectory:maintenance,receipt:receiptPath},{runPowerShell});
 const input=JSON.parse(readFileSync(inputPath));assert.equal(input.approved,true);
 const stopped=invokeClose(inputPath);assert.equal(stopped.status,0,stopped.stdout+stopped.stderr);await run.wait();cleanReceipt(run);
 const originalMarkerSnapshot=path.join(settings,'original-marker.json');copyFileSync(path.join(l.state,'s6-lifecycle.json'),originalMarkerSnapshot);
 const targetLogin=deployment.get(next.manifestSha256).find(a=>a.role==='login'),targetTask=deployment.get(next.manifestSha256).find(a=>a.role==='task');
 const preparedXml=path.join(settings,'fixed-prepared.xml');
 const prepared=JSON.parse(execFileSync(ps,['-NoProfile','NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(l.lifecycle,'prepare_login_schema6.ps1'),'-ReleaseDirectory',next.releaseDirectory,'-ManifestSha256',next.manifestSha256,'-LoginConfigurationPath',targetLogin.path,'-LoginConfigurationSha256',targetLogin.sha256,'-OutputXml',preparedXml,'-PrepareOnly'].map(a=>a==='NonInteractive'?'-NonInteractive':a),{env:cleanEnvironment(),windowsHide:true,encoding:'utf8',timeout:120000}));
 const prepareReceipt=path.join(settings,'fixed-prepare.json');writeFileSync(prepareReceipt,JSON.stringify(prepared));copyFileSync(preparedXml,targetTask.path);targetTask.sha256=hashFile(targetTask.path);
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
 let appliedRun;
 const apply=async plan=>{const input=JSON.parse(readFileSync(plan.p)),begin=performance.now();const run=launch(next,{args:['-OfflineOperation','package-switch','-PackageSwitchPlan',plan.p,'-PackageSwitchSha256',plan.sha]});await run.wait();cleanReceipt(run);appliedRun=run;t.diagnostic(JSON.stringify({operationId:input.operationId,forwardReverse:input.rollbackOf?'reverse':'forward',elapsedMs:Math.round(performance.now()-begin)}));return run.read('operation.json');};


 const switchPlan=makePlan(old,next);await apply(switchPlan);
 const marker=JSON.parse(readFileSync(path.join(l.state,'s6-lifecycle.json')));
 const snapshot=l.dir('registration-source');
 const maintained=['register-package-switch-login.ps1','package-switch-registration.mjs','package-switch-bindings.mjs','register_task_primitives.ps1','task_security_policy.ps1','owned_artifacts.ps1','close-schema6-session.ps1','process_image_binding.ps1'];
 const sourceNames=[...INVENTORY.filter(n=>n!=='runtime/node.exe'),...maintained.map(n=>'tools/i_core/maintenance/'+n)];
 const maintenanceFiles=sourceNames.map(n=>{const p=path.join(snapshot,n);mkdirSync(path.dirname(p),{recursive:true});copyFileSync(path.join(repository,n),p);return ref(p);});
 const registrationScript=path.join(snapshot,'tools/i_core/maintenance/register-package-switch-login.ps1');
 const oldXml=path.join(settings,'old-task-snapshot.xml'),oldApproved=deployment.get(old.manifestSha256).find(a=>a.role==='task');
 const sid=l.configuration.owner_sid,registrationSddl='O:'+sid+'G:'+sid+'D:(A;;FA;;;'+sid+')(A;;FA;;;SY)(A;;FA;;;BA)';
 const id=randomBytes(16).toString('hex');
 const taskName='HereIAm-Synthetic-Switch-New-'+id,oldTaskName='HereIAm-Synthetic-Switch-Old-'+id;
 const fixture=path.join(repository,'tools/i_core/test_fixtures/release_schema6/package_switch_registration.ps1');
 const probePath=path.join(settings,'registration-com-bootstrap.json');let fixtureSequence=0;
 const taskStep=(mode,configurationPath=probePath)=>{
  const output=path.join(settings,'registration-com-'+(++fixtureSequence)+'.json');
  execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',fixture,'-ConfigurationPath',configurationPath,'-Mode',mode,'-OutputPath',output],{env:cleanEnvironment(),windowsHide:true,encoding:'utf8',timeout:90000});
  return JSON.parse(readFileSync(output));
 };
 const bootstrap={taskName,oldTask:{name:oldTaskName,xml:{path:oldXml}},switchPlan:ref(switchPlan.p),maintenanceFiles,
  preparedXml:ref(preparedXml),ownerSid:sid,registrationSddl};
 writeFileSync(probePath,JSON.stringify(bootstrap));
 cleanupTasks=()=>taskStep('CleanupOld');
 const com=taskStep('BootstrapOld');
 bootstrap.oldTask=com.oldTask;writeFileSync(probePath,JSON.stringify(bootstrap));
 // The production inspector reads the actual disabled COM task. Its two
 // artifacts go directly into registration; the fixture supplies no policy.
 const security=path.join(settings,'old-task-security.json');
 generateOldTaskEvidence({task:oldTaskName,xmlOut:oldXml,securityOut:security});
 const inspected=JSON.parse(readFileSync(security));
 assert.equal(readFileSync(oldXml,'utf8'),com.xml);
 assert.equal(inspected.oldTaskSddl,com.oldTask.sddl);assert.equal(inspected.registrationSddl,com.oldTask.sddl);
 assert.equal(inspected.parentSddlSha256,sha256(com.parentSddl));
 const baseOptions={switchPlan:switchPlan.p,closeInput:inputPath,closeReceipt:input.outputPath,offlineControl:appliedRun.control,
  prepareReceipt,preparedXml,oldTaskName,taskName,maintenanceSnapshot:snapshot,originalMarkerSnapshot,oldTaskXml:oldXml,security};
 let generation=0;
 const freshOptions=(changes={})=>{
  const root=l.dir('generated-registration-'+(++generation));
  return {...baseOptions,out:path.join(root,'registration-approved.json'),humanApprovalOut:path.join(root,'human-approval.json'),
   registrationXmlOut:path.join(root,'disabled-definition.xml'),receipt:path.join(root,'registered.json'),...changes};
 };
 const initialOptions=freshOptions();
 const outputRoot=path.dirname(initialOptions.out);
 const tree=()=>JSON.stringify(readdirSync(outputRoot,{recursive:true}).sort().map(p=>[p,lstatSync(path.join(outputRoot,p)).isDirectory()?'directory':hashFile(path.join(outputRoot,p))]));
 const anchors=[baseOptions.switchPlan,baseOptions.closeInput,baseOptions.closeReceipt,baseOptions.prepareReceipt,baseOptions.preparedXml,baseOptions.originalMarkerSnapshot,baseOptions.oldTaskXml,baseOptions.security];
 const before=tree(),anchorHashes=anchors.map(hashFile),namesBefore=readdirSync(l.root,{recursive:true}).sort();
 const dry=generateRegistrationEvidence({...initialOptions,dryRun:true});
 assert.equal(tree(),before,'registration dry-run must not write output bytes');
 assert.deepEqual(readdirSync(l.root,{recursive:true}).sort(),namesBefore,'registration dry-run must not create any files or directories');
 assert.deepEqual(anchors.map(hashFile),anchorHashes,'registration dry-run must preserve source evidence');
 for(const p of [initialOptions.out,initialOptions.humanApprovalOut,initialOptions.registrationXmlOut,initialOptions.receipt])assert.equal(existsSync(p),false);
 const generated=generateRegistrationEvidence(initialOptions),config=generated.config;
 let configurationPath=initialOptions.out,approvalPath=initialOptions.humanApprovalOut;
 cleanupTasks=()=>taskStep('Cleanup',configurationPath);
 assert.equal(validatePackageSwitchRegistration(config).validated,true);
 const initialHash=hashFile(configurationPath);
 assert.throws(()=>generateRegistrationEvidence(initialOptions));assert.equal(hashFile(configurationPath),initialHash);
 // Negative cases intentionally alter reviewed evidence. This helper is not a
 // generation API and is kept distinct so existing rejection checks stay exact.
 const publish=()=>{const approval={...config,format:'schema6-package-switch-registration-human-approval-v1',action:'create_new_disabled_login_task_only',authorized:true};delete approval.humanApproval;writeFileSync(approvalPath,JSON.stringify(approval));config.humanApproval=ref(approvalPath);writeFileSync(configurationPath,JSON.stringify(config));};
 const invoke=()=>{
  // Positive calls consume fresh generator artifacts from the real old-task
  // files. Preserve the retained caller's explicit bad-parent negative case.
  const parentHash=config.parentSddlSha256;
  const current=freshOptions({taskName:config.taskName,receipt:config.registrationReceiptPath});
  const actual=generateRegistrationEvidence(current);Object.assign(config,actual.config);
  configurationPath=current.out;approvalPath=current.humanApprovalOut;
  if(parentHash!==inspected.parentSddlSha256){config.parentSddlSha256=parentHash;publish();}
  return spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',registrationScript,'-ConfigurationPath',configurationPath,'-ExpectedConfigurationSha256',hashFile(configurationPath),'-RegisterOnly'],{env:cleanEnvironment(),windowsHide:true,encoding:'utf8',timeout:180000});
 };
 return {l,config,publish,get configurationPath(){return configurationPath;},script:registrationScript,oldApproved:oldApproved.path,
  validate:()=>validatePackageSwitchRegistration(config),invoke,generatorOptions:baseOptions,freshOptions,dryRunSummary:dry,
  oldTaskEvidence:{xml:oldXml,security,actual:com},
  closeEvidence:{defaultApproved:draft.approved,closeReceipt:input.outputPath,unapprovedExitCode:unapproved.status}};
}
