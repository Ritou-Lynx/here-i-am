import assert from 'node:assert/strict';
import {execFileSync,spawn,spawnSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import {readFileSync,writeFileSync,mkdirSync,copyFileSync,existsSync} from 'node:fs';
import path from 'node:path';
import {INVENTORY,sha256,cleanEnvironment} from '../../release_schema6/package.mjs';
import {createRuntimeLab,repository,ps,until,cleanReceipt,protect} from '../../release_schema6/lifecycle/test-fixture.mjs';
import {loginConfig,configureManagedMcp,host,connectManaged} from '../../release_schema6/lifecycle/mcp-session-test-fixture.mjs';
import {allocateSyntheticLoopbackPort} from './mcp_reader/helper.mjs';
import {preparePackageSwitch} from '../../maintenance/prepare-package-switch.mjs';
import {validatePackageSwitchRegistration} from '../../maintenance/package-switch-registration.mjs';
const BASE='b71799706719b0e603124d108c2795caa0a98933',hashFile=p=>sha256(readFileSync(p));
const ref=p=>({path:p,sha256:hashFile(p)}),quote=s=>"'"+s.replaceAll("'","''")+"'";
export async function registrationLab(t){
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
 execFileSync(ps,['-NoProfile','-NonInteractive','-Command',aclScript],{env:cleanEnvironment(),windowsHide:true});
 const oldLogin=deployment.get(old.manifestSha256).find(a=>a.role==='login');
 const c={file:oldLogin.path,hash:oldLogin.sha256,configuration:JSON.parse(readFileSync(oldLogin.path)),controlRoot:stagedLogin.controlRoot};
 const run=await host({...l,release:old.releaseDirectory,lifecycle:path.join(old.releaseDirectory,'tools/i_core/release_schema6/lifecycle'),manifestHash:old.manifestSha256,configPath:old.configurationPath,configuration:JSON.parse(readFileSync(old.configurationPath))},c);
 await run.ready();await connectManaged(run,managed,{requireMessage:false});
 const maintenance=l.dir('maintenance');
 for(const file of ['close-schema6-session.ps1','process_image_binding.ps1'])copyFileSync(path.join(repository,'tools/i_core/maintenance',file),path.join(maintenance,file));
 const script=path.join(maintenance,'close-schema6-session.ps1'),helper=path.join(maintenance,'process_image_binding.ps1');
 const metadata=JSON.parse(execFileSync(ps,['-NoProfile','NonInteractive','-Command',
  'Add-Type -TypeDefinition \'using System;using System.Runtime.InteropServices;public static class FixtureWindowThread{[DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr w,out uint p);}\';'+
  '$p=Get-Process -Id '+run.child.pid+';$windowPid=0;$tid=[FixtureWindowThread]::GetWindowThreadProcessId([IntPtr]::new('+run.window.hwnd+'),[ref]$windowPid);'+
  '@{startedTicks=$p.StartTime.ToUniversalTime().Ticks.ToString();imagePath=$p.Path;sessionId=$p.SessionId;threadId=$tid;ownerSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}|ConvertTo-Json -Compress'
 ].map(a=>a==='NonInteractive'?'-NonInteractive':a),{env:cleanEnvironment(),windowsHide:true,encoding:'utf8'}));
 const input={format:'schema6-session-close-approved-v1',approved:true,releaseDirectory:old.releaseDirectory,manifestSha256:old.manifestSha256,loginConfigurationPath:c.file,loginConfigurationSha256:c.hash,
  sessionDirectory:run.session,controlDirectory:run.control,windowSha256:hashFile(path.join(run.session,'session-window.json')),launchSha256:hashFile(path.join(run.control,'launch.json')),readySha256:hashFile(path.join(run.control,'ready.json')),
  maintenanceScriptSha256:hashFile(script),processImageBindingSha256:hashFile(helper),host:{...metadata,pid:run.child.pid,hwnd:run.window.hwnd,imageSha256:hashFile(metadata.imagePath)},outputPath:path.join(maintenance,'close-receipt.json')};
 const inputPath=path.join(maintenance,'approved.json');
 const invoke=value=>{writeFileSync(inputPath,JSON.stringify(value));return spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',script,'-ConfigurationPath',inputPath,'-ConfigurationSha256',hashFile(inputPath)],{env:cleanEnvironment(),windowsHide:true,encoding:'utf8',timeout:120000});};

 const stopped=invoke(input);assert.equal(stopped.status,0,stopped.stdout+stopped.stderr);await run.wait();cleanReceipt(run);
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
 writeFileSync(oldXml,readFileSync(oldApproved.path,'utf8').replace('<Enabled>true</Enabled><Hidden>true</Hidden>','<Enabled>false</Enabled><Hidden>true</Hidden>'));
 const sid=l.configuration.owner_sid,registrationSddl='O:'+sid+'G:'+sid+'D:(A;;FA;;;'+sid+')(A;;FA;;;SY)(A;;FA;;;BA)';
 const id=randomBytes(16).toString('hex');
 const config={format:'schema6-package-switch-registration-v1',approved:true,registerOnly:true,registerDisabled:true,registrationDerivation:'fixed_prepare_settings_enabled_false_only',ownerSid:sid,taskName:'HereIAm-Synthetic-Switch-New-'+id,oldTask:{name:'HereIAm-Synthetic-Switch-Old-'+id,xml:ref(oldXml),sddl:registrationSddl,sddlSha256:sha256(registrationSddl)},registrationSddl,expectedRegisteredSddl:registrationSddl,parentSddlSha256:sha256(registrationSddl),taskSecurityPolicyVersion:'windows-file-oi-v1',inheritedReadOnlyPrincipals:[],
 releaseDirectory:next.releaseDirectory,manifestSha256:next.manifestSha256,switchPlan:ref(switchPlan.p),targetMarker:ref(path.join(l.state,'s6-lifecycle.json')),currentHead:ref(path.join(l.configuration.recovery_custody_directory,'current-head.json')),switchEvent:ref(path.join(l.configuration.recovery_custody_directory,marker.package_switch_event_sha256+'.package-switch.json')),targetFloor:ref(path.join(l.configuration.recovery_custody_directory,marker.custody_sha256+'.floor.json')),originalCloseInput:ref(inputPath),originalCloseReceipt:ref(input.outputPath),originalMarkerSnapshot:ref(originalMarkerSnapshot),fixedPrepareReceipt:ref(prepareReceipt),preparedXml:ref(preparedXml),approvedXml:ref(targetTask.path),registrationXml:{path:path.join(settings,'approved-disabled-definition.xml'),sha256:'0'.repeat(64)},offline:Object.fromEntries(['launch','child','guardian','supervisor','operation'].map(n=>[n,ref(path.join(appliedRun.control,n+'.json'))])),maintenanceFiles,registrationReceiptPath:path.join(settings,'registered.json')};
 const approvalPath=path.join(settings,'registration-human-approval.json'),configurationPath=path.join(settings,'registration-approved.json');
 const publish=()=>{const approval={...config,format:'schema6-package-switch-registration-human-approval-v1',action:'create_new_disabled_login_task_only',authorized:true};delete approval.humanApproval;writeFileSync(approvalPath,JSON.stringify(approval));config.humanApproval=ref(approvalPath);writeFileSync(configurationPath,JSON.stringify(config));};publish();
 return {l,config,publish,configurationPath,script:registrationScript,oldApproved:oldApproved.path,validate:()=>validatePackageSwitchRegistration(config),invoke:()=>spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',registrationScript,'-ConfigurationPath',configurationPath,'-ExpectedConfigurationSha256',hashFile(configurationPath),'-RegisterOnly'],{env:cleanEnvironment(),windowsHide:true,encoding:'utf8',timeout:180000})};
}
