// N2 food rollout, step 2 (production switch, service goes down briefly).
// Order follows the D1b sequence in maintenance/README.md:
//   A  close live session -> disable old task -> old-task evidence -> approved plan
//      (any failure here re-enables and restarts the old task)
//   B  offline package switch -> register P -> C1 to P' -> switch -NoRollback
//      (after the offline switch there is no automatic way back; stop and report)
//   C  provision food domain -> MCP set-food-credential -> restart P'
// Tokens stay in memory only: never printed, logged or written by this script.
//
// Usage: run n2-step2.ps1 (Windows PowerShell 5.1, -File) with --git <git.exe>.
// Requires the outputs of step 1 under <OUT>. Builds <OUT>\tools-fb401d45 (old tools
// copy + the two files PR #69 changed) before anything else.
import {createHash,randomBytes} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {copyFileSync,existsSync,mkdirSync,readFileSync,readdirSync,statSync,writeFileSync,appendFileSync} from 'node:fs';
import path from 'node:path';

const ACTIVE='HereIAm-iCoreSchema6-d2b-mcp-20261025-129ec194';
const P='HereIAm-iCoreSchema6-n2-pkg-20261031';
const P2='HereIAm-iCoreSchema6-n2-food-20261031';
const M='9897fb4109f1e6dda4fa15c3a0a1ef34f4ed001160d3e458ae94860b1349af95';
const STEP1={login:'c5109636',xml:'b8df7804',receipt:'3d018a4d',server:'f42f291f'};
const PINNED_NODE='58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f';
// Maintenance tools: step 1 used tools-42ecf688 (tools/i_core at S). PR #69 changed only
// the two files below, so the new copy is the old one plus those blobs at V.
const S='42ecf688f61ff829f5f7bb1d5aadc2695c01436b',V='fb401d459e3ae56233558ba138ae0d7ec7c07c08';
const TOOLS_CHANGED=['tools/i_core/maintenance/package-switch-bindings.mjs','tools/i_core/release_schema6/maintenance_package_switch_bindings.test.mjs'];
const TOOLS_FILES=321;

class Stop extends Error{constructor(step,detail){super(detail);this.step=step;this.detail=detail;}}
const sha=b=>createHash('sha256').update(b).digest('hex');
const blobSha=b=>createHash('sha1').update(Buffer.concat([Buffer.from('blob '+b.length+'\0'),b])).digest('hex');
function files(root){const out=[];const go=d=>{for(const e of readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);if(e.isDirectory())go(p);else out.push(p);}};go(root);return out;}
const fileSha=p=>sha(readFileSync(p));
const short=h=>String(h).slice(0,8).toLowerCase();
let report=null;
function emit(step,ok,detail){const row=JSON.stringify({step,ok,detail});console.log(row);if(report)appendFileSync(report,row+'\n');}
function need(cond,step,detail){if(!cond)throw new Stop(step,detail);}
function plain(p){return typeof p==='string'&&path.win32.isAbsolute(p)&&path.win32.normalize(p)===p&&p.indexOf(':',2)<0&&!p.endsWith('\\')&&!p.startsWith('\\\\');}
function readJson(p,expected,step){const b=readFileSync(p);if(expected)need(sha(b)===String(expected).toLowerCase(),step,'hash_mismatch:'+path.basename(p));return JSON.parse(b.toString('utf8').replace(/^﻿/,''));}
const childEnv=()=>{const e={};for(const [k,v] of Object.entries(process.env))if(!/^(NODE_|I_CORE_)/i.test(k)&&!['OPENSSL_CONF','SSL_CERT_FILE','SSL_CERT_DIR'].includes(k.toUpperCase()))e[k]=v;e.PSModulePath=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','Modules');return e;};
function run(file,args,{cwd,input,step}={}){
 const r=spawnSync(file,args,{cwd,input,env:childEnv(),encoding:'utf8',windowsHide:true,maxBuffer:64*1024*1024,timeout:30*60*1000});
 if(r.error)throw new Stop(step,'spawn_failed:'+r.error.code);
 return {code:r.status,stdout:r.stdout??'',stderr:r.stderr??''};
}
const lines=t=>t.split(/\r?\n/).filter(Boolean).map(l=>{try{return JSON.parse(l);}catch{return null;}}).filter(Boolean);
const firstErr=r=>(r.stderr.trim().split(/\r?\n/).filter(Boolean).pop()??'').slice(0,240);
const PS=()=>path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');
const PSARGS=['-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass'];
function ps51(script,input,step){
 const body="$ErrorActionPreference='Stop'\nif($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'host_not_51'}\n$q=[Console]::In.ReadToEnd()|ConvertFrom-Json\n"+script;
 const r=run(PS(),[...PSARGS,'-EncodedCommand',Buffer.from(body,'utf16le').toString('base64')],{input:JSON.stringify(input??{}),step});
 need(r.code===0,step,'powershell_exit_'+r.code+':'+firstErr(r));
 return JSON.parse(r.stdout.trim().split(/\r?\n/).filter(Boolean).pop());
}
// Maintenance entry points: always a fresh Windows PowerShell 5.1 child with -File.
function psFile(script,args,step,{input}={}){return run(PS(),[...PSARGS,'-File',script,...args],{step,input});}
// Echo maintenance rows (step/ok/detail only) so a failure shows the exact row.
function relay(step,r){for(const row of lines(r.stdout))if(row.step!==undefined)emit(step+':'+row.step,row.ok!==false,typeof row.detail==='string'?row.detail.slice(0,240):row.detail);}

const TASKS_PS="ConvertTo-Json -InputObject @(Get-ScheduledTask|Where-Object{$_.TaskName -like 'HereIAm-iCoreSchema6-*'}|ForEach-Object{[pscustomobject]@{name=$_.TaskName;state=[string]$_.State;arguments=[string]$_.Actions[0].Arguments}}) -Compress -Depth 3";
function tasks(step){const t=ps51(TASKS_PS,{},step);return Array.isArray(t)?t:[t];}
function loginOf(task,step){
 const tok=[...task.arguments.matchAll(/"([^"]*)"|(\S+)/g)].map(m=>m[1]??m[2]);
 const arg=re=>{const i=tok.map((t,j)=>re.test(t)?j:-1).filter(j=>j>=0);need(i.length===1&&i[0]+1<tok.length,step,'login_argument_ambiguous');return tok[i[0]+1];};
 const p=arg(/^-(Login)?ConfigurationPath$/i),h=arg(/^-(Login)?ConfigurationSha256$/i).toLowerCase();
 const login=readJson(p,h,step);need(login.format==='schema6-login-v1',step,'login_format');return {path:p,sha256:h,login};
}
// New private directory: owner = current user, protected, only user/SYSTEM/Administrators.
const PROTECT_PS="$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User\nif(@(Get-ChildItem -LiteralPath $q.path -Force).Count -ne 0){throw 'new_empty_directory_required'}\n$a=New-Object Security.AccessControl.DirectorySecurity\n$a.SetOwner($sid)\n$a.SetAccessRuleProtection($true,$false)\nforeach($id in @($sid,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'),[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))){$a.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($id,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))}\nSet-Acl -LiteralPath $q.path -AclObject $a\n$v=Get-Acl -LiteralPath $q.path\n[pscustomobject]@{protected=$v.AreAccessRulesProtected}|ConvertTo-Json -Compress";
function privateDir(p,step){need(!existsSync(p),step,'directory_exists:'+path.basename(p));mkdirSync(p);need(ps51(PROTECT_PS,{path:p},step).protected===true,step,'private_dir_acl:'+path.basename(p));}
// Start a task and wait with the maintenance readiness check (same as switch-login-task).
const START_PS=". $q.switch\n$b=Get-Schema6LoginBinding $q.task\n$prev=@(Get-Schema6SessionDirectories $b)\nif($q.enable){Invoke-Schema6TaskOperation -Operation Enable -TaskName $q.task}\nInvoke-Schema6TaskOperation -Operation Start -TaskName $q.task\nWait-Schema6LoginReady -Name $q.task -Binding $b -PreviousSessions $prev -TimeoutSeconds 180 -HealthUrl ''\n[pscustomobject]@{ready=$true}|ConvertTo-Json -Compress";

function main(){
 const a=process.argv.slice(2);need(a.length===2&&a[0]==='--git','args','usage: --git <git.exe>');
 need(process.platform==='win32','args','windows_required');
 need(process.version==='v24.14.1'&&fileSha(process.execPath)===PINNED_NODE&&plain(process.execPath),'args','pinned_node_required');
 const G=a[1];need(plain(G)&&existsSync(G)&&statSync(G).nlink===1,'args','single_link_git_required');

 // 0. Preflight: read-only.
 const before=tasks('step0');
 const active=before.filter(t=>t.name===ACTIVE);need(active.length===1&&active[0].state==='Running','step0','active_task_not_running');
 need(before.every(t=>t.name===ACTIVE||t.state==='Disabled'),'step0','other_task_enabled');
 need(!before.some(t=>[P,P2].includes(t.name)),'step0','target_task_exists');
 const live=loginOf(active[0],'step0'),login=live.login;
 const mcp=readJson(login.mcp_configuration_path,login.mcp_configuration_sha256,'step0');
 const backup=readJson(login.backup_configuration_path,login.backup_configuration_sha256,'step0');
 const core=readJson(login.core_configuration_path,login.core_configuration_sha256,'step0');
 const oldCand=path.dirname(mcp.working_directory),OUT=path.dirname(oldCand);
 need(path.basename(mcp.working_directory)==='runtime'&&/^mcp-candidate-/.test(path.basename(oldCand))&&plain(OUT),'step0','live_candidate_layout');
 const TOOLS=path.join(OUT,'tools-'+V.slice(0,8)),TI=path.join(TOOLS,'tools','i_core'),MT=path.join(TI,'maintenance');
 {// New maintenance tools copy (outside production; reused if an earlier run already built it).
  const OLDT=path.join(OUT,'tools-42ecf688'),WT=path.join(OUT,'worktree-42ecf688');
  need(existsSync(path.join(OLDT,'tools','i_core','maintenance'))&&existsSync(WT),'step0','old_tools_or_worktree_missing');
  const git=(args,step)=>{const r=run(G,['-C',WT,...args],{step});need(r.code===0,step,'git_failed:'+args[0]);return r.stdout;};
  git(['fetch','origin','v3-lab'],'step0');
  need(run(G,['-C',WT,'merge-base','--is-ancestor',V,'origin/v3-lab'],{step:'step0'}).code===0,'step0','V_not_on_v3_lab');
  const changed=git(['diff','--name-only',S,V,'--','tools/i_core'],'step0').split(/\r?\n/).filter(Boolean).sort();
  need(JSON.stringify(changed)===JSON.stringify([...TOOLS_CHANGED].sort()),'step0','tools_diff:'+changed.join(','));
  const blobs=new Map(git(['ls-tree','-r',V,'--',...TOOLS_CHANGED],'step0').split(/\r?\n/).filter(Boolean).map(l=>{const m=l.match(/^100644 blob ([0-9a-f]{40})\t(.+)$/);need(m,'step0','ls_tree');return [m[2],m[1]];}));
  need(blobs.size===2,'step0','ls_tree_count');
  const oldFiles=files(OLDT);need(oldFiles.length===TOOLS_FILES,'step0','old_tools_count:'+oldFiles.length);
  if(!existsSync(TOOLS)){
   mkdirSync(TOOLS);
   const acl=ps51("$a=(Get-Item -LiteralPath $q.from).GetAccessControl('Access')\n$a.SetAccessRuleProtection($true,$true)\n(Get-Item -LiteralPath $q.to).SetAccessControl($a)\n$v=(Get-Item -LiteralPath $q.to).GetAccessControl('Access')\n[pscustomobject]@{protected=$v.AreAccessRulesProtected;rules=@($v.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])).Count}|ConvertTo-Json -Compress",{from:OLDT,to:TOOLS},'step0');
   need(acl.protected===true&&acl.rules>0,'step0','tools_acl');
   for(const p of oldFiles){const rel=path.relative(OLDT,p),dst=path.join(TOOLS,rel);mkdirSync(path.dirname(dst),{recursive:true});
    const repo=rel.split(path.sep).join('/');
    if(blobs.has(repo)){const r=spawnSync(G,['-C',WT,'cat-file','blob',blobs.get(repo)],{env:childEnv(),windowsHide:true,maxBuffer:16*1024*1024});need(r.status===0,'step0','cat_file');writeFileSync(dst,r.stdout,{flag:'wx'});}
    else copyFileSync(p,dst);}
  }
  const newFiles=files(TOOLS);need(newFiles.length===TOOLS_FILES,'step0','new_tools_count:'+newFiles.length);
  for(const p of newFiles){const rel=path.relative(TOOLS,p),repo=rel.split(path.sep).join('/');
   if(blobs.has(repo))need(blobSha(readFileSync(p))===blobs.get(repo),'step0','tools_blob:'+path.basename(p));
   else need(existsSync(path.join(OLDT,rel))&&fileSha(p)===fileSha(path.join(OLDT,rel)),'step0','tools_copy:'+rel);}
  emit('step0.tools',true,{tools:'tools-'+V.slice(0,8),files:TOOLS_FILES,changed:TOOLS_CHANGED.map(n=>path.basename(n))});
 }
 const REL=path.join(OUT,'release-42ecf688'),CAND=path.join(OUT,'mcp-candidate-42ecf688'),CFG=path.join(OUT,'n2-pkg-configs'),RUN=path.join(OUT,'n2-step2-run');
 need(existsSync(path.join(MT,'switch-login-task.ps1')),'step0','tools_copy_layout');
 need(fileSha(path.join(REL,'manifest.json'))===M,'step0','new_release_manifest_changed');
 const info=readJson(path.join(CFG,'static-inputs.json'),null,'step0');
 need(short(info.loginSha256)===STEP1.login&&short(fileSha(info.loginPath))===STEP1.login&&short(fileSha(info.preparedXml))===STEP1.xml&&short(fileSha(path.join(CFG,'prepare-receipt.json')))===STEP1.receipt,'step0','step1_outputs_changed');
 need(info.taskName===P&&info.oldTaskName===ACTIVE&&info.releaseDirectory===REL&&info.manifestSha256===M&&info.oldLoginPath===live.path,'step0','step1_inputs_mismatch');
 need(info.mcpPath===login.mcp_configuration_path&&info.mcpSha256===login.mcp_configuration_sha256,'step0','mcp_configuration_changed');
 need(short(fileSha(path.join(CAND,'runtime','i_remote_mcp','server.mjs')))===STEP1.server,'step0','candidate_changed');
 const taskEntries=backup.specTemplate.entries.filter(e=>e.role==='task'&&!e.name.startsWith('preserved/')&&e.name==='tasks/HereIAm-CoreSchema6-Session.xml');
 need(taskEntries.length===1,'step0','backup_task_attachment_missing');
 const pr=readJson(path.join(CFG,'prepare-receipt.json'),null,'step0');
 need(pr.prepared===true&&pr.registered===false&&pr.started===false&&pr.manifest_sha256===M&&pr.login_configuration_sha256===info.loginSha256,'step0','prepare_receipt_binding');
 // Exercise the package-switch binding validator now, before any downtime.
 const ref0=(role,p)=>({role,path:p,sha256:fileSha(p)});
 const bindPlan={from:{releaseDirectory:login.release_directory,manifestSha256:login.manifest_sha256,configurationPath:login.core_configuration_path,configurationSha256:login.core_configuration_sha256},
  to:{releaseDirectory:REL,manifestSha256:M,configurationPath:info.corePath,configurationSha256:fileSha(info.corePath)},
  artifacts:[ref0('login',info.loginPath),ref0('backup',info.backupPath),ref0('mcp',info.mcpPath),ref0('task',info.preparedXml)],
  fromArtifacts:[ref0('login',live.path),ref0('backup',login.backup_configuration_path),ref0('mcp',login.mcp_configuration_path),ref0('task',taskEntries[0].source_path)]};
 {const r=run(process.execPath,['--input-type=module','-e',"import {pathToFileURL} from 'node:url';let t='';process.stdin.on('data',d=>t+=d).on('end',async()=>{const q=JSON.parse(t);const m=await import(pathToFileURL(q.module).href);try{console.log(JSON.stringify(m.validatePackageSwitchBindings(q.plan,{fromArtifacts:q.plan.fromArtifacts})));}catch(e){console.log(JSON.stringify({validated:false,code:e.code??'unknown'}));process.exitCode=2;}});"],{step:'step0',input:JSON.stringify({module:path.join(MT,'package-switch-bindings.mjs'),plan:bindPlan})});
  const v=lines(r.stdout).pop();need(r.code===0&&v?.validated===true,'step0','switch_bindings:'+(v?.code??r.code));}
 const stateDir=login.state_directory,marker=path.join(stateDir,'s6-lifecycle.json'),head=path.join(core.recovery_custody_directory,'current-head.json');
 need(existsSync(head)&&existsSync(marker),'step0','marker_or_head_missing');
 const pending=[];const walk=d=>{for(const e of readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);if(e.isDirectory())walk(p);else if(/^(pair|food)\.request$/i.test(e.name))pending.push(p);}};walk(login.control_root);
 need(pending.length===0,'step0','pending_request_present');
 privateDir(RUN,'step0');
 report=path.join(RUN,'report.jsonl');
 const gen=path.join(MT,'generate-package-switch-evidence.mjs'),node=process.execPath;
 emit('step0',true,{active:'Running',login:short(live.sha256),out_run:'n2-step2-run'});

 // A. From here the service is down. Failures before the offline switch restart the old task.
 const t0=Date.now();
 let closed=false,switched=false;
 try{
  const closeInput=path.join(RUN,'close-input.json'),closeReceipt=path.join(RUN,'close-receipt.json');
  let r=run(node,[gen,'close-input','--task',ACTIVE,'--out',closeInput,'--maintenance-directory',MT,'--receipt',closeReceipt,'--approve'],{step:'A1'});
  need(r.code===0&&existsSync(closeInput),'A1','close_input:'+(lines(r.stdout).pop()?.code??r.code));
  emit('A1',true,{closeInput:short(fileSha(closeInput))});
  r=psFile(path.join(MT,'close-schema6-session.ps1'),['-ConfigurationPath',closeInput,'-ConfigurationSha256',fileSha(closeInput)],'A2');
  closed=existsSync(closeReceipt);
  need(r.code===0&&closed,'A2','close:'+r.code+':'+firstErr(r));
  const receipt=readJson(closeReceipt,null,'A2');need(receipt.closed===true,'A2','close_not_confirmed');
  const markerSnap=path.join(RUN,'original-marker.json');copyFileSync(marker,markerSnap);
  const m=readJson(markerSnap,null,'A2');need(m.phase==='clean_closed'&&fileSha(markerSnap)===fileSha(marker),'A2','marker_not_clean_closed');
  emit('A2',true,{receipt:short(fileSha(closeReceipt)),marker:short(fileSha(markerSnap)),downtime_start:new Date(t0).toISOString()});

  ps51(". $q.stop\nInvoke-Schema6TaskOperation -Operation Disable -TaskName $q.task\n[pscustomobject]@{disabled=$true}|ConvertTo-Json -Compress",{stop:path.join(MT,'stop-schema6-session.ps1'),task:ACTIVE},'A3');
  const oldXml=path.join(RUN,'old-task.xml'),security=path.join(RUN,'old-task-security.json');
  r=run(node,[gen,'old-task','--task',ACTIVE,'--xml-out',oldXml,'--security-out',security],{step:'A3'});
  const ev=lines(r.stdout).pop();need(r.code===0&&ev?.oldTaskStopped===true,'A3','old_task_evidence:'+(ev?.code??r.code));
  emit('A3',true,{disabled:true,xml:short(fileSha(oldXml)),security:short(fileSha(security))});

  const ref=(role,p)=>({role,path:p,sha256:fileSha(p)});
  const input={operationId:'n2-'+randomBytes(8).toString('hex'),
   from:{releaseDirectory:login.release_directory,manifestSha256:login.manifest_sha256,configurationPath:login.core_configuration_path},
   to:{releaseDirectory:REL,manifestSha256:M,configurationPath:info.corePath},headPath:head,markerPath:marker,
   artifacts:[ref('login',info.loginPath),ref('backup',info.backupPath),ref('mcp',info.mcpPath),ref('task',info.preparedXml)],
   fromArtifacts:[ref('login',live.path),ref('backup',login.backup_configuration_path),ref('mcp',login.mcp_configuration_path),ref('task',taskEntries[0].source_path)]};
  const planInput=path.join(RUN,'switch-input.json'),prepared=path.join(RUN,'switch-prepared.json'),approved=path.join(RUN,'switch-approved.json');
  writeFileSync(planInput,JSON.stringify(input,null,2)+'\n',{flag:'wx'});
  r=run(node,[path.join(MT,'prepare-package-switch.mjs'),'--input',planInput,'--output',prepared],{step:'A4'});
  need(r.code===0&&existsSync(prepared),'A4','prepare_switch:'+(lines(r.stdout).pop()?.code??r.code));
  const plan=readJson(prepared,null,'A4').plan;need(plan.approved===false&&plan.to.manifestSha256===M,'A4','plan_shape');
  plan.approved=true;writeFileSync(approved,JSON.stringify(plan,null,2)+'\n',{flag:'wx'});
  emit('A4',true,{operationId:plan.operationId,prepared:short(fileSha(prepared)),approved:short(fileSha(approved))});

  // B. Offline package switch. After this point never start the old task.
  const offline=path.join(RUN,'offline-control');privateDir(offline,'B1');
  switched=true;
  r=psFile(path.join(REL,'tools','i_core','release_schema6','lifecycle','start_schema6.ps1'),['-ManifestSha256',M,'-Start','-OfflineOperation','package-switch','-PackageSwitchPlan',approved,'-PackageSwitchSha256',fileSha(approved),'-StateDirectory',stateDir,'-ControlDirectory',offline,'-CorePort','0','-ConfigurationFile',info.corePath],'B1');
  const child=existsSync(path.join(offline,'child.json'))?readJson(path.join(offline,'child.json'),null,'B1'):null;
  need(r.code===0&&child?.reason==='package_switch_completed','B1','offline_switch:'+r.code+':'+(child?.reason??'')+':'+firstErr(r));
  const op=readJson(path.join(offline,'operation.json'),null,'B1');
  emit('B1',true,{switched:true,custody_generation:op.custody_generation,marker:short(fileSha(marker))});

  const regArgs=['registration','--switch-plan',approved,'--close-input',closeInput,'--close-receipt',closeReceipt,'--offline-control',offline,'--prepare-receipt',path.join(CFG,'prepare-receipt.json'),'--prepared-xml',info.preparedXml,'--old-task-name',ACTIVE,'--task-name',P,'--old-task-xml',oldXml,'--maintenance-snapshot',TOOLS,'--original-marker-snapshot',markerSnap,'--security',security,'--out',path.join(RUN,'registration.json'),'--human-approval-out',path.join(RUN,'human-approval.json'),'--registration-xml-out',path.join(RUN,'registration-task.xml'),'--receipt',path.join(RUN,'registration-receipt.json')];
  r=run(node,[gen,...regArgs,'--dry-run'],{step:'B2'});need(r.code===0,'B2','registration_dry_run:'+(lines(r.stdout).pop()?.code??r.code));
  r=run(node,[gen,...regArgs],{step:'B2'});const rg=lines(r.stdout).pop();need(r.code===0&&rg?.generated===true,'B2','registration:'+(rg?.code??r.code));
  const regPath=path.join(RUN,'registration.json');
  r=psFile(path.join(MT,'register-package-switch-login.ps1'),['-ConfigurationPath',regPath,'-ExpectedConfigurationSha256',fileSha(regPath),'-RegisterOnly'],'B2');
  const reg=lines(r.stdout).pop();need(r.code===0&&reg?.registered===true,'B2','register_only:'+r.code+':'+(reg?.code??'')+':'+(reg?.reason??'')+':'+(reg?.validatorReason??''));
  emit('B2',true,{task:P,registered:true,config:short(fileSha(regPath))});

  const c1Out=path.join(RUN,'c1-out'),c1=['--from-task',P,'--candidate',CAND,'--out',c1Out,'--new-task',P2];
  r=run(node,[path.join(MT,'update-mcp-source.mjs'),...c1,'--dry-run'],{step:'B3'});
  need(r.code===0&&lines(r.stdout).find(x=>x.step==='update.result')?.detail==='dry_run_passed','B3','c1_dry_run:'+(lines(r.stdout).find(x=>x.ok===false)?.detail??r.code));
  r=run(node,[path.join(MT,'update-mcp-source.mjs'),...c1],{step:'B3'});
  need(r.code===0&&lines(r.stdout).find(x=>x.step==='update.result')?.detail==='registered_disabled','B3','c1:'+(lines(r.stdout).find(x=>x.ok===false)?.detail??r.code));
  emit('B3',true,{task:P2,registered:'disabled'});

  const sw=path.join(MT,'switch-login-task.ps1');
  r=psFile(sw,['-FromTask',ACTIVE,'-ToTask',P2,'-DryRun'],'B4');relay('B4',r);need(r.code===0,'B4','switch_dry_run:'+r.code);
  r=psFile(sw,['-FromTask',ACTIVE,'-ToTask',P2,'-NoRollback','-ReadyTimeoutSeconds','180'],'B4');relay('B4',r);need(r.code===0,'B4','switch:'+r.code);
  emit('B4',true,{running:P2,downtime_seconds:Math.round((Date.now()-t0)/1000)});
 }catch(e){
  let down=closed;if(!switched&&!down){try{down=tasks('rollback').find(t=>t.name===ACTIVE)?.state!=='Running';}catch{down=true;}}
  if(down&&!switched){
   try{ps51(START_PS,{switch:path.join(MT,'switch-login-task.ps1'),task:ACTIVE,enable:true},'rollback');emit('rollback',true,'old_task_restarted');}
   catch(x){emit('rollback',false,x.detail??String(x.message).slice(0,240));}
  }else if(switched)emit('stopped',false,'after_offline_switch:do_not_start_old_task');
  throw e;
 }

 // C. Food domain: tokens pass from provision stdout to set-food-credential stdin in memory only.
 const p2=loginOf(tasks('C1').find(t=>t.name===P2),'C1'),mcp2=readJson(p2.login.mcp_configuration_path,p2.login.mcp_configuration_sha256,'C1');
 need(mcp2.working_directory===path.join(CAND,'runtime'),'C1','new_mcp_not_candidate');
 let r=psFile(path.join(MT,'provision-food-domain.ps1'),['-TaskName',P2],'C1');
 const prov=lines(r.stdout).pop();
 need(r.code===0&&prov?.status==='provisioned'&&typeof prov.writer_token==='string','C1','provision:'+(prov?.status??r.code)+':'+firstErr(r));
 emit('C1',true,{status:prov.status,registered:prov.registered,issued:prov.issued});
 const stateMcp=mcp2.environment.I_REMOTE_MCP_STATE_DIR;
 r=run(mcp2.executable_path,[path.join(CAND,'runtime','i_remote_mcp','server.mjs'),'set-food-credential','--state-dir',stateMcp,'--core-url','http://127.0.0.1:'+p2.login.core_port],{step:'C2',input:JSON.stringify(prov)+'\n'});
 for(const k of Object.keys(prov))delete prov[k];
 need(r.code===0&&existsSync(path.join(stateMcp,'core-food.json')),'C2','set_food_credential:'+r.code+':'+firstErr(r));
 emit('C2',true,{credential:'saved'});
 const t1=Date.now();
 r=psFile(path.join(MT,'stop-schema6-session.ps1'),['-TaskName',P2],'C3');relay('C3',r);need(r.code===0,'C3','stop:'+r.code);
 ps51(START_PS,{switch:path.join(MT,'switch-login-task.ps1'),task:P2,enable:false},'C3');
 emit('C3',true,{restarted:P2,downtime_seconds:Math.round((Date.now()-t1)/1000)});
 const after=tasks('done');
 need(after.find(t=>t.name===P2)?.state==='Running'&&after.every(t=>t.name===P2||t.state==='Disabled'),'done','final_task_states');
 emit('done',true,{running:P2,manifest:short(M)});
}
try{main();}catch(e){emit(e.step??'unexpected',false,e.detail??String(e.message).slice(0,300));process.exitCode=1;}
