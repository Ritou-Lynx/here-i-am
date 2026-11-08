// E3 (expense ledger) round 2: deploy. Production change with a short outage; run only after the user's 👍.
// Same order as N2 step 1 + step 2 (maintenance/README.md, D1b), from the live M1 task:
//   0  preflight (live m1-digest task, release-42ecf688, server bde3ff9f, tools-4603fb79, no pending markers)
//   1  new Core package <OUT>\release-78e11df7 (v3-lab at the #98 merge; only the two expense files differ)
//   2  six-file MCP candidate (server 63acb514) copied out with protected ACLs
//   3  package-switch configurations + fixed prepare (new private run directory)
//   4  zero-write checks: switch bindings, old-task preview, C1 dry run; then <MCP state>\expense.json
//   A  close live session -> disable old task -> old-task evidence -> approved plan
//      (any failure here re-enables and restarts the old task: nothing has changed yet)
//   B  offline package switch -> register P -> C1 to P' with the candidate -> switch -NoRollback
//      (after the offline switch there is no automatic way back; stop and report)
//   C  new Core enables the ledger on start (expense-receipt), heart-rate listener back
// Output: one JSON row per step; no tokens, logins, domains, paths, SIDs or record contents.
// Usage: e3-deploy.ps1 (Windows PowerShell 5.1, -File) runs this with --git <git.exe>.
import {randomBytes} from 'node:crypto';
import {appendFileSync,copyFileSync,existsSync,mkdirSync,readFileSync,statSync,writeFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {ACTIVE,P,P2,S,CHANGED,MCP_EXPECTED,PINNED_NODE,LISTEN_PORT,EXPENSE_JSON,ACL_PS,CHECK_ACL_PS,
 emit,need,plain,readJson,fileSha,short,files,run,rows,lastErr,value,psFile,relay,asList,tasks,loginOf,mcpOf,
 portFree,preflight,packageDiff,expenseReceipts,setReport,singleLinkGit} from './e3-common.mjs';

const REPO=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..','..','..');
const DRY_TASK='HereIAm-iCoreSchema6-e3-dryrun';
const sleep=ms=>new Promise(res=>setTimeout(res,ms));

// New private directory: owner = current user, protected, only user/SYSTEM/Administrators (same as N2).
const PROTECT_PS="$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User\nif(@(Get-ChildItem -LiteralPath $q.path -Force).Count -ne 0){throw 'new_empty_directory_required'}\n$a=New-Object Security.AccessControl.DirectorySecurity\n$a.SetOwner($sid)\n$a.SetAccessRuleProtection($true,$false)\nforeach($id in @($sid,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'),[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))){$a.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($id,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))}\nSet-Acl -LiteralPath $q.path -AclObject $a\n$v=Get-Acl -LiteralPath $q.path\n[pscustomobject]@{protected=$v.AreAccessRulesProtected}|ConvertTo-Json -Compress";
function privateDir(p,step){need(!existsSync(p),step,'directory_exists:'+path.basename(p));mkdirSync(p);need(value(PROTECT_PS,{path:p},step).protected===true,step,'private_dir_acl:'+path.basename(p));}
// Rollback: re-enable and start the old task, then wait for ready. A crash-recovery latch after an
// unclean close means wait, not fail (ST1 round 3); same loop as the M1/ST1 retry scripts.
const START_PS=String.raw`. $q.switch
function Test-Latch($b){Test-Path -LiteralPath (Join-Path $b.Login.state_directory 's6-recovery-pending.json')}
function Test-TaskActive([string]$n){(Invoke-Schema6TaskOperation -Operation State -TaskName $n) -in @(2,4)}
$b=Get-Schema6LoginBinding $q.task
$prev=@(Get-Schema6SessionDirectories $b)
Invoke-Schema6TaskOperation -Operation Enable -TaskName $q.task
Invoke-Schema6TaskOperation -Operation Start -TaskName $q.task
$w=[Diagnostics.Stopwatch]::StartNew();$seen=$false;$sec=300
while($true){
 $left=$sec-[int]$w.Elapsed.TotalSeconds
 if($left -le 0){throw 'ready_timeout'}
 if(Test-Latch $b){$seen=$true;if(-not (Test-TaskActive $q.task)){throw 'task_stopped_during_recovery'};Start-Sleep -Seconds 3;continue}
 try{$null=Wait-Schema6LoginReady -Name $q.task -Binding $b -PreviousSessions $prev -TimeoutSeconds $left -HealthUrl '';break}
 catch{if($_.Exception.Message -notlike 'recovery_pending_manual_review_required*'){throw};$seen=$true;Start-Sleep -Seconds 3}
}
[pscustomobject]@{ready=$true;recovery_seen=$seen}|ConvertTo-Json -Compress`;
const BIND_JS="import {pathToFileURL} from 'node:url';let t='';process.stdin.on('data',d=>t+=d).on('end',async()=>{const q=JSON.parse(t);const m=await import(pathToFileURL(q.module).href);try{console.log(JSON.stringify(m.validatePackageSwitchBindings(q.plan,{fromArtifacts:q.plan.fromArtifacts})));}catch(e){console.log(JSON.stringify({validated:false,code:e.code??'unknown'}));process.exitCode=2;}});";

async function main(){
 const T0=Date.now();
 const a=process.argv.slice(2);need(a.length===4&&a[0]==='--mode'&&a[1]==='deploy'&&a[2]==='--git','args','usage: --mode deploy --git <git.exe>');
 need(process.platform==='win32'&&process.version==='v24.14.1'&&fileSha(process.execPath)===PINNED_NODE&&plain(process.execPath),'args','pinned_node_required');
 need(plain(a[3])&&existsSync(a[3])&&statSync(a[3]).isFile(),'args','git_path_required');const G=singleLinkGit(a[3],'args');
 const node=process.execPath;

 // 0. Preflight (read-only).
 const f=preflight({G,REPO,step:'step0'});
 const {live,login,core,oldCand,OUT,stateMcp,expenseJson,stateDir,marker,head,taskEntries,HEAD,TOOLS,MT}=f;
 const changed=await packageDiff({REPO,G,login,step:'step0'});
 need(JSON.stringify(changed)===JSON.stringify([...CHANGED].sort()),'step0','package_diff:'+changed.join(','));
 need(expenseReceipts(login.control_root).length===0,'step0','expense_receipt_already_present');
 const REL=path.join(OUT,'release-'+S.slice(0,8)),CAND=path.join(OUT,'mcp-candidate-'+HEAD.slice(0,8));
 const RUN=path.join(OUT,'e3-run-'+new Date().toISOString().replace(/[:.]/g,'-'));
 privateDir(RUN,'step0');
 const report=path.join(RUN,'report.jsonl');setReport(row=>appendFileSync(report,row+'\n'));
 emit('step0',true,{active:'Running',release:path.basename(login.release_directory),server:'bde3ff9f',tools:path.basename(TOOLS),head:short(HEAD),run:path.basename(RUN)});

 // 1. New Core package (reused when an earlier run already built and verified it).
 const cli=path.join(REPO,'tools','i_core','release_schema6','cli.mjs');
 let r;
 if(!existsSync(REL)){
  r=run(node,[cli,'prepare',REPO,REL,G,S],{step:'step1'});need(r.code===0,'step1','prepare_failed:'+lastErr(r));
  const relAcl=value(ACL_PS,{pairs:[{rel:'.',from:login.release_directory,to:REL}]},'step1');
  for(const x of asList(relAcl))need(x.protected===true&&x.rules>0,'step1','release_acl');
 }
 const M=fileSha(path.join(REL,'manifest.json'));
 r=run(node,[cli,'verify',REL,M],{step:'step1'});need(r.code===0,'step1','verify_failed:'+lastErr(r));
 const newMan=readJson(path.join(REL,'manifest.json'),M,'step1'),oldMan=readJson(path.join(login.release_directory,'manifest.json'),login.manifest_sha256,'step1');
 need(newMan.source_commit===S&&newMan.files.length===48,'step1','manifest_shape');
 const oldBy=new Map(oldMan.files.map(x=>[x.path,x.sha256]));
 const relDiff=newMan.files.filter(x=>oldBy.get(x.path)!==x.sha256).map(x=>x.path).sort();
 need(JSON.stringify(relDiff)===JSON.stringify([...CHANGED].sort()),'step1','package_diff:'+relDiff.join(','));
 const relAclCheck=asList(value(CHECK_ACL_PS,{dirs:[{rel:'.',path:REL}]},'step1'));
 need(relAclCheck.every(x=>x.protected===true&&x.rules>0),'step1','release_acl_check');
 emit('step1',true,{release:path.basename(REL),manifest:short(M),changed:relDiff.map(n=>path.basename(n)),others_same:46});

 // 2. MCP candidate.
 const dirs=['','runtime',path.join('runtime','i_remote_mcp'),path.join('runtime','i_memory')];
 const buildRel='build/e3-candidate-'+randomBytes(4).toString('hex'),build=path.join(REPO,...buildRel.split('/'));
 r=run(node,[path.join(REPO,'tools','i_remote_mcp','chatgpt_candidate.mjs'),'--out',buildRel],{cwd:REPO,step:'step2'});
 need(r.code===0,'step2','candidate_build_failed:'+lastErr(r));
 const cm=readJson(path.join(build,'manifest.json'),null,'step2');
 need(cm.changed_files===5&&cm.source_commit===HEAD&&cm.files.length===6,'step2','candidate_manifest');
 for(const x of cm.files)need(MCP_EXPECTED[x.path]===short(x.result_sha256),'step2','candidate_hash:'+x.path+':'+short(x.result_sha256));
 const built=files(build).map(p=>path.relative(build,p)).sort();
 if(!existsSync(CAND)){
  for(const d of dirs){need(existsSync(path.join(oldCand,d)),'step2','old_candidate_dir_missing:'+(d||'.'));mkdirSync(path.join(CAND,d),{recursive:true});}
  const acl=asList(value(ACL_PS,{pairs:dirs.map(d=>({rel:d||'.',from:d?path.join(oldCand,d):oldCand,to:d?path.join(CAND,d):CAND}))},'step2'));
  for(const x of acl)need(x.protected===true&&x.rules>0,'step2','candidate_acl:'+x.dir);
  for(const rel of built)copyFileSync(path.join(build,rel),path.join(CAND,rel));
 }
 need(JSON.stringify(files(CAND).map(p=>path.relative(CAND,p)).sort())===JSON.stringify(built),'step2','candidate_inventory');
 for(const rel of built)need(fileSha(path.join(CAND,rel))===fileSha(path.join(build,rel)),'step2','copy_mismatch:'+rel);
 const candAcl=asList(value(CHECK_ACL_PS,{dirs:dirs.map(d=>({rel:d||'.',path:d?path.join(CAND,d):CAND}))},'step2'));
 need(candAcl.length===dirs.length&&candAcl.every(x=>x.protected===true&&x.rules>0),'step2','candidate_acl_check');
 emit('step2',true,{candidate:path.basename(CAND),server:MCP_EXPECTED['i_remote_mcp/server.mjs']});

 // 3. Package-switch configurations + fixed prepare (P = new Core + live MCP configuration).
 const CFG=path.join(RUN,'pkg-configs'),reqPath=path.join(RUN,'pkg-request.json');
 const request={oldLoginPath:live.path,oldLoginSha256:live.sha256,newReleaseDirectory:REL,newManifestSha256:M,outputDirectory:CFG,oldTaskXmlPath:taskEntries[0].source_path,taskName:P,oldTaskName:ACTIVE};
 writeFileSync(reqPath,JSON.stringify(request,null,2)+'\n',{flag:'wx'});
 r=run(node,[path.join(MT,'generate-package-switch-configurations.mjs'),'--input',reqPath,'--input-sha256',fileSha(reqPath)],{step:'step3'});
 const genCfg=rows(r.stdout).pop();need(r.code===0&&genCfg?.generated===true,'step3','generator:'+(genCfg?.code??r.code));
 const info=readJson(path.join(CFG,'static-inputs.json'),null,'step3');
 need(info.mcpPath===login.mcp_configuration_path&&info.mcpSha256===login.mcp_configuration_sha256,'step3','mcp_configuration_changed');
 need(info.taskName===P&&info.oldTaskName===ACTIVE&&info.releaseDirectory===REL&&info.manifestSha256===M&&info.oldLoginPath===live.path,'step3','static_inputs_mismatch');
 r=psFile(path.join(REL,'tools','i_core','release_schema6','lifecycle','prepare_login_schema6.ps1'),['-ReleaseDirectory',REL,'-ManifestSha256',M,'-LoginConfigurationPath',info.loginPath,'-LoginConfigurationSha256',info.loginSha256,'-OutputXml',info.preparedXml,'-PrepareOnly'],'step3');
 const receipt=rows(r.stdout).pop();need(r.code===0&&receipt?.prepared===true&&receipt.registered===false&&receipt.started===false,'step3','prepare_login:'+(lastErr(r)||r.code));
 const prepareReceipt=path.join(CFG,'prepare-receipt.json');writeFileSync(prepareReceipt,r.stdout,{flag:'wx'});
 const pr=readJson(prepareReceipt,null,'step3');
 need(pr.manifest_sha256===M&&pr.login_configuration_sha256===info.loginSha256,'step3','prepare_receipt_binding');
 emit('step3',true,{login:short(info.loginSha256),xml:short(fileSha(info.preparedXml)),receipt:short(fileSha(prepareReceipt)),newReleaseCount:genCfg.newReleaseCount,preservedLegacyCount:genCfg.preservedLegacyCount});

 // 4. Zero-write checks, then the ledger switch file for the new candidate.
 const ref=(role,p)=>({role,path:p,sha256:fileSha(p)});
 const fromArtifacts=()=>[ref('login',live.path),ref('backup',login.backup_configuration_path),ref('mcp',login.mcp_configuration_path),ref('task',taskEntries[0].source_path)];
 const toArtifacts=()=>[ref('login',info.loginPath),ref('backup',info.backupPath),ref('mcp',info.mcpPath),ref('task',info.preparedXml)];
 const bindPlan={from:{releaseDirectory:login.release_directory,manifestSha256:login.manifest_sha256,configurationPath:login.core_configuration_path,configurationSha256:login.core_configuration_sha256},
  to:{releaseDirectory:REL,manifestSha256:M,configurationPath:info.corePath,configurationSha256:fileSha(info.corePath)},artifacts:toArtifacts(),fromArtifacts:fromArtifacts()};
 r=run(node,['--input-type=module','-e',BIND_JS],{step:'step4',input:JSON.stringify({module:path.join(MT,'package-switch-bindings.mjs'),plan:bindPlan})});
 const bind=rows(r.stdout).pop();need(r.code===0&&bind?.validated===true,'step4','switch_bindings:'+(bind?.code??r.code));
 const gen=path.join(MT,'generate-package-switch-evidence.mjs');
 r=run(node,[gen,'old-task','--task',ACTIVE,'--preview'],{step:'step4'});
 const pv=rows(r.stdout).pop();need(r.code===0&&pv?.oldTaskStopped===false,'step4','old_task_preview:'+(pv?.code??r.code));
 const DRY=path.join(RUN,'c1-dryrun');
 r=run(node,[path.join(MT,'update-mcp-source.mjs'),'--from-task',ACTIVE,'--candidate',CAND,'--out',DRY,'--new-task',DRY_TASK,'--dry-run'],{step:'step4'});
 need(r.code===0&&rows(r.stdout).find(x=>x.step==='update.result')?.detail==='dry_run_passed'&&!existsSync(DRY),'step4','c1_dry_run:'+(rows(r.stdout).find(x=>x.ok===false)?.detail??r.code));
 if(!existsSync(expenseJson))writeFileSync(expenseJson,EXPENSE_JSON+'\n',{flag:'wx'});
 need(readFileSync(expenseJson,'utf8').trim()===EXPENSE_JSON,'step4','expense_json');
 const still=tasks('step4').find(t=>t.name===ACTIVE);need(still?.state==='Running','step4','active_task_changed');
 need(!existsSync(path.join(stateDir,'s6-recovery-pending.json')),'step4','recovery_latch_present');
 emit('step4',true,{bindings:'validated',old_task_preview:'ok',c1_dry_run:'passed',expense_json:'written',prepare_minutes:Math.round((Date.now()-T0)/6000)/10});

 // A. From here the service is down. Failures before the offline switch restart the old task.
 const t0=Date.now();
 let closed=false,switched=false;
 try{
  const closeInput=path.join(RUN,'close-input.json'),closeReceipt=path.join(RUN,'close-receipt.json');
  r=run(node,[gen,'close-input','--task',ACTIVE,'--out',closeInput,'--maintenance-directory',MT,'--receipt',closeReceipt,'--approve'],{step:'A1'});
  need(r.code===0&&existsSync(closeInput),'A1','close_input:'+(rows(r.stdout).pop()?.code??r.code));
  emit('A1',true,{closeInput:short(fileSha(closeInput))});
  r=psFile(path.join(MT,'close-schema6-session.ps1'),['-ConfigurationPath',closeInput,'-ConfigurationSha256',fileSha(closeInput)],'A2');
  closed=existsSync(closeReceipt);
  need(r.code===0&&closed,'A2','close:'+r.code+':'+lastErr(r));
  const cr=readJson(closeReceipt,null,'A2');need(cr.closed===true,'A2','close_not_confirmed');
  const markerSnap=path.join(RUN,'original-marker.json');copyFileSync(marker,markerSnap);
  const m=readJson(markerSnap,null,'A2');need(m.phase==='clean_closed'&&fileSha(markerSnap)===fileSha(marker),'A2','marker_not_clean_closed');
  emit('A2',true,{receipt:short(fileSha(closeReceipt)),marker:short(fileSha(markerSnap)),downtime_start:new Date(t0).toISOString()});

  value(". $q.stop\nInvoke-Schema6TaskOperation -Operation Disable -TaskName $q.task\n[pscustomobject]@{disabled=$true}|ConvertTo-Json -Compress",{stop:path.join(MT,'stop-schema6-session.ps1'),task:ACTIVE},'A3');
  const oldXml=path.join(RUN,'old-task.xml'),security=path.join(RUN,'old-task-security.json');
  r=run(node,[gen,'old-task','--task',ACTIVE,'--xml-out',oldXml,'--security-out',security],{step:'A3'});
  const ev=rows(r.stdout).pop();need(r.code===0&&ev?.oldTaskStopped===true,'A3','old_task_evidence:'+(ev?.code??r.code));
  emit('A3',true,{disabled:true,xml:short(fileSha(oldXml)),security:short(fileSha(security))});

  const input={operationId:'e3-'+randomBytes(8).toString('hex'),
   from:{releaseDirectory:login.release_directory,manifestSha256:login.manifest_sha256,configurationPath:login.core_configuration_path},
   to:{releaseDirectory:REL,manifestSha256:M,configurationPath:info.corePath},headPath:head,markerPath:marker,
   artifacts:toArtifacts(),fromArtifacts:fromArtifacts()};
  const planInput=path.join(RUN,'switch-input.json'),prepared=path.join(RUN,'switch-prepared.json'),approved=path.join(RUN,'switch-approved.json');
  writeFileSync(planInput,JSON.stringify(input,null,2)+'\n',{flag:'wx'});
  r=run(node,[path.join(MT,'prepare-package-switch.mjs'),'--input',planInput,'--output',prepared],{step:'A4'});
  need(r.code===0&&existsSync(prepared),'A4','prepare_switch:'+(rows(r.stdout).pop()?.code??r.code));
  const plan=readJson(prepared,null,'A4').plan;need(plan.approved===false&&plan.to.manifestSha256===M,'A4','plan_shape');
  plan.approved=true;writeFileSync(approved,JSON.stringify(plan,null,2)+'\n',{flag:'wx'});
  emit('A4',true,{operationId:plan.operationId,prepared:short(fileSha(prepared)),approved:short(fileSha(approved))});

  // B. Offline package switch. After this point never start the old task.
  const offline=path.join(RUN,'offline-control');privateDir(offline,'B1');
  switched=true;
  r=psFile(path.join(REL,'tools','i_core','release_schema6','lifecycle','start_schema6.ps1'),['-ManifestSha256',M,'-Start','-OfflineOperation','package-switch','-PackageSwitchPlan',approved,'-PackageSwitchSha256',fileSha(approved),'-StateDirectory',stateDir,'-ControlDirectory',offline,'-CorePort','0','-ConfigurationFile',info.corePath],'B1');
  const child=existsSync(path.join(offline,'child.json'))?readJson(path.join(offline,'child.json'),null,'B1'):null;
  need(r.code===0&&child?.reason==='package_switch_completed','B1','offline_switch:'+r.code+':'+(child?.reason??'')+':'+lastErr(r));
  const op=readJson(path.join(offline,'operation.json'),null,'B1');
  emit('B1',true,{switched:true,custody_generation:op.custody_generation,marker:short(fileSha(marker))});

  const regPath=path.join(RUN,'registration.json');
  const regArgs=['registration','--switch-plan',approved,'--close-input',closeInput,'--close-receipt',closeReceipt,'--offline-control',offline,'--prepare-receipt',prepareReceipt,'--prepared-xml',info.preparedXml,'--old-task-name',ACTIVE,'--task-name',P,'--old-task-xml',oldXml,'--maintenance-snapshot',TOOLS,'--original-marker-snapshot',markerSnap,'--security',security,'--out',regPath,'--human-approval-out',path.join(RUN,'human-approval.json'),'--registration-xml-out',path.join(RUN,'registration-task.xml'),'--receipt',path.join(RUN,'registration-receipt.json')];
  r=run(node,[gen,...regArgs,'--dry-run'],{step:'B2'});need(r.code===0,'B2','registration_dry_run:'+(rows(r.stdout).pop()?.code??r.code));
  r=run(node,[gen,...regArgs],{step:'B2'});const rg=rows(r.stdout).pop();need(r.code===0&&rg?.generated===true,'B2','registration:'+(rg?.code??r.code));
  r=psFile(path.join(MT,'register-package-switch-login.ps1'),['-ConfigurationPath',regPath,'-ExpectedConfigurationSha256',fileSha(regPath),'-RegisterOnly'],'B2');
  const reg=rows(r.stdout).pop();need(r.code===0&&reg?.registered===true,'B2','register_only:'+r.code+':'+(reg?.code??'')+':'+(reg?.reason??'')+':'+(reg?.validatorReason??''));
  emit('B2',true,{task:P,registered:true,config:short(fileSha(regPath))});

  const c1=['--from-task',P,'--candidate',CAND,'--out',path.join(RUN,'c1-out'),'--new-task',P2];
  r=run(node,[path.join(MT,'update-mcp-source.mjs'),...c1,'--dry-run'],{step:'B3'});
  need(r.code===0&&rows(r.stdout).find(x=>x.step==='update.result')?.detail==='dry_run_passed','B3','c1_dry_run:'+(rows(r.stdout).find(x=>x.ok===false)?.detail??r.code));
  r=run(node,[path.join(MT,'update-mcp-source.mjs'),...c1],{step:'B3'});
  need(r.code===0&&rows(r.stdout).find(x=>x.step==='update.result')?.detail==='registered_disabled','B3','c1:'+(rows(r.stdout).find(x=>x.ok===false)?.detail??r.code));
  emit('B3',true,{task:P2,registered:'disabled'});

  const sw=path.join(MT,'switch-login-task.ps1');
  r=psFile(sw,['-FromTask',ACTIVE,'-ToTask',P2,'-DryRun'],'B4');relay('B4',r);need(r.code===0,'B4','switch_dry_run:'+r.code);
  r=psFile(sw,['-FromTask',ACTIVE,'-ToTask',P2,'-NoRollback','-ReadyTimeoutSeconds','180'],'B4');relay('B4',r);need(r.code===0,'B4','switch:'+r.code);
  emit('B4',true,{running:P2,downtime_seconds:Math.round((Date.now()-t0)/1000)});
 }catch(e){
  let down=closed;if(!switched&&!down){try{down=tasks('rollback').find(t=>t.name===ACTIVE)?.state!=='Running';}catch{down=true;}}
  if(down&&!switched){
   try{value(START_PS,{switch:path.join(MT,'switch-login-task.ps1'),task:ACTIVE},'rollback',7);emit('rollback',true,'old_task_restarted');}
   catch(x){emit('rollback',false,x.detail??String(x.message).slice(0,240));}
  }else if(switched)emit('stopped',false,'after_offline_switch:do_not_start_old_task');
  throw e;
 }

 // C. Verify: new task runs the new package and candidate; Core enabled the ledger on start.
 const after=tasks('C1'),cur=after.find(t=>t.name===P2);
 need(cur?.state==='Running'&&after.every(t=>t.name===P2||t.state==='Disabled'),'C1','final_task_states');
 const nl=loginOf(cur,'C1'),nm=mcpOf(nl,'C1');
 need(nl.login.manifest_sha256===M&&nl.login.release_directory===REL,'C1','new_task_not_new_package');
 need(nm.working_directory===path.join(CAND,'runtime')&&short(nm.source_files.find(x=>x.path==='i_remote_mcp/server.mjs')?.sha256)===MCP_EXPECTED['i_remote_mcp/server.mjs'],'C1','new_task_not_candidate');
 let got=null;
 for(let i=0;i<30&&!got;i++){
  const list=expenseReceipts(nl.login.control_root).filter(p=>statSync(p).mtimeMs>=t0-5000).sort((x,y)=>statSync(x).mtimeMs-statSync(y).mtimeMs);
  if(list.length)got=readJson(list.at(-1),null,'C1');else await sleep(2000);
 }
 need(got,'C1','expense_receipt_missing');
 emit('C1',got.status==='provisioned',{running:P2,manifest:short(M),server:MCP_EXPECTED['i_remote_mcp/server.mjs'],expense:{status:got.status,registered:got.registered,upgraded:got.upgraded}});
 let listening=false;for(let i=0;i<20&&!listening;i++){listening=!(await portFree(LISTEN_PORT));if(!listening)await sleep(1500);}
 emit('C2',listening,{heart_rate_listener:listening});
 need(got.status==='provisioned','done','expense_not_provisioned:'+got.status);
 emit('done',true,{running:P2,manifest:short(M),server:MCP_EXPECTED['i_remote_mcp/server.mjs'],minutes:Math.round((Date.now()-T0)/6000)/10});
}
main().catch(e=>{emit(e.step??'unexpected',false,e.detail??String(e.message).slice(0,300));process.exitCode=1;});
