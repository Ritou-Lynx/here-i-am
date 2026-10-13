import assert from 'node:assert/strict';
import {execFileSync,spawn} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import {readFileSync,writeFileSync,mkdirSync,copyFileSync,existsSync} from 'node:fs';
import path from 'node:path';
import {INVENTORY,sha256,cleanEnvironment} from '../../release_schema6/package.mjs';
import {createRuntimeLab,repository,ps,until,cleanReceipt} from '../../release_schema6/lifecycle/test-fixture.mjs';
import {loginConfig,configureManagedMcp} from '../../release_schema6/lifecycle/mcp-session-test-fixture.mjs';
import {allocateSyntheticLoopbackPort} from './mcp_reader/helper.mjs';
import {preparePackageSwitch} from '../../maintenance/prepare-package-switch.mjs';
const BASE='69d9eb0d28816e5047ac14fe6f39f755fbf1222e',hashFile=p=>sha256(readFileSync(p));
const quote=s=>"'"+s.replaceAll("'","''")+"'";
export async function r1PackageSwitchLab(t){
 if(process.platform!=='win32'||process.env.GITHUB_ACTIONS!=='true')throw new Error('r1_fixture_ci_only');
 const l=await createRuntimeLab(t);
 const execPath=execFileSync('git',['--exec-path'],{encoding:'utf8',windowsHide:true}).trim(),gitPath=path.resolve(execPath,'../../../bin/git.exe');
 const oldSource=execFileSync(gitPath,['-C',repository,'show',BASE+':tools/i_core/release_schema6/package.mjs'],{windowsHide:true,env:cleanEnvironment()});
 const oldApi=await import('data:text/javascript;base64,'+oldSource.toString('base64'));
 const built=path.join(l.root,'old-built');const oldPrepared=oldApi.prepareRelease({repository,sourceCommit:BASE,output:built,nodePath:path.join(l.release,'runtime/node.exe'),gitPath});
 const oldRelease=l.dir('old-release');for(const name of [...oldApi.INVENTORY,'manifest.json']){const p=path.join(oldRelease,name);mkdirSync(path.dirname(p),{recursive:true});copyFileSync(path.join(built,name),p);}
 assert.equal(JSON.parse(readFileSync(path.join(oldRelease,'manifest.json'))).source_commit,BASE);assert.equal(oldApi.INVENTORY.length,48);assert.deepEqual(oldApi.INVENTORY,INVENTORY);assert.equal(hashFile(path.join(oldRelease,'tools/i_core/release_schema6/package.mjs')),sha256(oldSource));
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
  // Both task XMLs come from each package's actual fixed Prepare entry.
  const prepared=JSON.parse(execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(end.releaseDirectory,'tools/i_core/release_schema6/lifecycle/prepare_login_schema6.ps1'),'-ReleaseDirectory',end.releaseDirectory,'-ManifestSha256',end.manifestSha256,'-LoginConfigurationPath',names.login,'-LoginConfigurationSha256',hashFile(names.login),'-OutputXml',names.task,'-PrepareOnly'],{env:cleanEnvironment(),windowsHide:true,encoding:'utf8',timeout:180000}));
  assert.equal(prepared.prepared,true);assert.equal(prepared.registered,false);assert.equal(prepared.started,false);
  return [end.manifestSha256,Object.entries(names).map(([role,p])=>({role,path:p,sha256:hashFile(p)}))];
 }));

 // Backup validation is private even for synthetic templates. No real key or
 // database is referenced; failed scheduled fixture backup is not a success claim.
 const backupPaths=[old,next].map(e=>deployment.get(e.manifestSha256).find(a=>a.role==='backup').path);
 const aclScript='$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User;$a=New-Object Security.AccessControl.FileSecurity;$a.SetOwner($sid);$a.SetAccessRuleProtection($true,$false);foreach($id in @($sid,[Security.Principal.SecurityIdentifier]::new("S-1-5-18"))){$a.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($id,"FullControl","Allow"))};foreach($p in @('+backupPaths.map(quote).join(',')+')){Set-Acl -LiteralPath $p -AclObject $a}';
 execFileSync(ps,['-NoProfile','-NonInteractive','-Command',aclScript],{env:cleanEnvironment(),windowsHide:true});
 const configurationFor=end=>{
  const login=deployment.get(end.manifestSha256).find(a=>a.role==='login');
  const configuration=JSON.parse(readFileSync(login.path));
  return {file:login.path,hash:login.sha256,configuration,controlRoot:configuration.control_root};
 };
 const oldLab={...l,release:old.releaseDirectory,lifecycle:path.join(old.releaseDirectory,'tools/i_core/release_schema6/lifecycle'),manifestHash:old.manifestSha256,configPath:old.configurationPath,configuration:JSON.parse(readFileSync(old.configurationPath))};
 const apply=async()=>{
  const prepared=preparePackageSwitch({operationId:'r1-'+randomBytes(5).toString('hex'),from:old,to:next,
   headPath:path.join(l.configuration.recovery_custody_directory,'current-head.json'),markerPath:path.join(l.state,'s6-lifecycle.json'),artifacts:deployment.get(next.manifestSha256),fromArtifacts:deployment.get(old.manifestSha256)});
  for(const key of ['validated','taskXmlBound','mcpProgramAndPolicyPreserved'])assert.equal(prepared.bindingReport[key],true,key);
  assert.equal(prepared.plan.approved,false);assert.equal(prepared.report.registered,false);
  // Local fixture approval applies only to these newly created synthetic roots.
  const planPath=path.join(path.dirname(l.configPath),'r1-switch-plan.json');writeFileSync(planPath,JSON.stringify({...prepared.plan,approved:true}));
  const run=launch(next,{args:['-OfflineOperation','package-switch','-PackageSwitchPlan',planPath,'-PackageSwitchSha256',hashFile(planPath)]});
  await run.wait();cleanReceipt(run);
  assert.equal(JSON.parse(readFileSync(path.join(l.state,'s6-lifecycle.json'))).manifest_sha256,next.manifestSha256);
  return run;
 };
 return {l,old,next,oldLab,oldLogin:configurationFor(old),nextLogin:configurationFor(next),managed,apply};
}
