// N2 (Feishu notes tools in the i MCP) deploy. Production change, run only after the user's 👍.
//   0  preflight, read-only: live task e3-expense (server 63acb514, mcp 838810b2, release ded493e5), nothing else
//      enabled, no recovery latch, clean checkout, maintenance copy tools-4603fb79 unchanged, home notes mirror
//      readable by notes_tools, heart-rate listener up
//   1  <MCP state>\notes.json, then the six-file candidate (server 4b1014e0) copied out with protected ACLs
//   2  update-mcp-source registers the new task disabled (dry run first); switch (falls back to e3-expense on failure)
//   3  heart-rate listener still up
// Only the MCP candidate changes; the Core package, its data and the other tasks are untouched.
// Output: one JSON row per step; no tokens, logins, domains, paths, SIDs, titles or document text.
// Usage: n2-deploy.ps1 (Windows PowerShell 5.1, -File) runs this with --mode deploy --git <git.exe>.
import {createHash,randomBytes} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {copyFileSync,existsSync,mkdirSync,readFileSync,readdirSync,statSync,writeFileSync} from 'node:fs';
import {createServer} from 'node:net';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';

const ACTIVE='HereIAm-iCoreSchema6-e3-expense-20261108';
const NEW='HereIAm-iCoreSchema6-n2-notes-20261108';
const OLD_SERVER='63acb514',OLD_MCP='838810b2',OLD_MANIFEST='ded493e5';
const MCP_EXPECTED={'i_remote_mcp/server.mjs':'4b1014e0','i_remote_mcp/oauth.mjs':'e2c88aca','i_remote_mcp/diagnostics.mjs':'67b0fbec',
 'i_remote_mcp/mcp.mjs':'838810b2','i_remote_mcp/writeback.mjs':'a7a6f95d','i_memory/i_memory_read.mjs':'cee18518'};
// Maintenance copy used since ST1. Since then tools/i_core changed only in these files (none under maintenance/).
const TOOLS_COMMIT='4603fb79',TOOLS_FILES=321;
const TOOLS_DRIFT=['tools/i_core/expense_domains.test.mjs','tools/i_core/personal_data_domains.mjs','tools/i_core/release_schema6/lifecycle/runtime_child.mjs'];
const LISTEN_PORT=47866;
const REPO=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..','..','..');

class Stop extends Error{constructor(step,detail){super(detail);this.step=step;this.detail=detail;}}
const sha=b=>createHash('sha256').update(b).digest('hex');
function files(root){const out=[];const go=d=>{for(const e of readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);if(e.isDirectory())go(p);else out.push(p);}};go(root);return out;}
const fileSha=p=>sha(readFileSync(p));
const short=h=>String(h).slice(0,8).toLowerCase();
function emit(step,ok,detail){console.log(JSON.stringify({step,ok,detail}));}
function need(cond,step,detail){if(!cond)throw new Stop(step,detail);}
function plain(p){return typeof p==='string'&&path.win32.isAbsolute(p)&&path.win32.normalize(p)===p&&p.indexOf(':',2)<0&&!p.endsWith('\\')&&!p.startsWith('\\\\');}
function readJson(p,expected,step){const b=readFileSync(p);if(expected)need(sha(b)===String(expected).toLowerCase(),step,'hash_mismatch:'+path.basename(p));return JSON.parse(b.toString('utf8').replace(/^﻿/,''));}
const childEnv=()=>{const e={};for(const [k,v] of Object.entries(process.env))if(!/^(NODE_|I_CORE_|I_REMOTE_MCP_|GIT_)/i.test(k)&&!['OPENSSL_CONF','SSL_CERT_FILE','SSL_CERT_DIR'].includes(k.toUpperCase()))e[k]=v;e.PSModulePath=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','Modules');return e;};
function run(file,args,{cwd,input,step,timeoutMin=30}={}){
 const r=spawnSync(file,args,{cwd,input,env:childEnv(),encoding:'utf8',windowsHide:true,maxBuffer:64*1024*1024,timeout:timeoutMin*60*1000});
 if(r.error)throw new Stop(step,'spawn_failed:'+r.error.code);
 return {code:r.status,stdout:r.stdout??'',stderr:r.stderr??''};
}
const rows=t=>t.split(/\r?\n/).filter(Boolean).map(l=>{try{return JSON.parse(l);}catch{return null;}}).filter(Boolean);
const lastErr=r=>(r.stderr.trim().split(/\r?\n/).filter(Boolean).pop()??'').replace(/[A-Za-z]:\\[^\s'"]*/g,'<path>').slice(0,240);
const PS=()=>path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');
const PSARGS=['-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass'];
const HEAD51="$ErrorActionPreference='Stop'\nif($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'host_not_51'}\n$q=[Console]::In.ReadToEnd()|ConvertFrom-Json\n";
function ps51(script,input,step,timeoutMin=5){return run(PS(),[...PSARGS,'-EncodedCommand',Buffer.from(HEAD51+script,'utf16le').toString('base64')],{input:JSON.stringify(input??{}),step,timeoutMin});}
function value(script,input,step){const r=ps51(script,input,step);need(r.code===0,step,'powershell_exit_'+r.code+':'+lastErr(r));return JSON.parse(r.stdout.trim().split(/\r?\n/).filter(Boolean).pop());}
const asList=v=>v==null?[]:Array.isArray(v)?v:[v];

const TASKS_PS="ConvertTo-Json -InputObject @(Get-ScheduledTask|Where-Object{$_.TaskName -like 'HereIAm-iCoreSchema6-*'}|ForEach-Object{[pscustomobject]@{name=$_.TaskName;state=[string]$_.State;actions=@($_.Actions).Count;arguments=[string]$_.Actions[0].Arguments}}) -Compress -Depth 3";
const tasks=step=>asList(value(TASKS_PS,{},step));
function loginOf(task,step){
 const tok=[...task.arguments.matchAll(/"([^"]*)"|(\S+)/g)].map(m=>m[1]??m[2]);
 const arg=re=>{const i=tok.map((t,j)=>re.test(t)?j:-1).filter(j=>j>=0);need(i.length===1&&i[0]+1<tok.length,step,'login_argument_ambiguous');return tok[i[0]+1];};
 const p=arg(/^-(Login)?ConfigurationPath$/i),h=arg(/^-(Login)?ConfigurationSha256$/i).toLowerCase();
 const login=readJson(p,h,step);need(login.format==='schema6-login-v1',step,'login_format');return {path:p,sha256:h,login};
}
const mcpOf=(l,step='mcp')=>readJson(l.login.mcp_configuration_path,l.login.mcp_configuration_sha256,step);
const serverOf=(l,step)=>short(mcpOf(l,step).source_files?.find(f=>f.path==='i_remote_mcp/server.mjs')?.sha256);
function portFree(port){return new Promise(resolve=>{const s=createServer();s.once('error',()=>resolve(false));s.listen(port,'127.0.0.1',()=>s.close(()=>resolve(true)));});}
// Copy the DACL (only) of each source directory onto its target, protected.
const ACL_PS="$o=@()\nforeach($p in $q.pairs){$a=(Get-Item -LiteralPath $p.from).GetAccessControl('Access');$a.SetAccessRuleProtection($true,$true);(Get-Item -LiteralPath $p.to).SetAccessControl($a);$v=(Get-Item -LiteralPath $p.to).GetAccessControl('Access');$o+=[pscustomobject]@{dir=$p.rel;protected=$v.AreAccessRulesProtected;rules=@($v.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])).Count}}\nConvertTo-Json -InputObject $o -Compress";
const CHECK_ACL_PS="$o=@()\nforeach($p in $q.dirs){$v=(Get-Item -LiteralPath $p.path).GetAccessControl('Access');$o+=[pscustomobject]@{dir=$p.rel;protected=$v.AreAccessRulesProtected;rules=@($v.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])).Count}}\nConvertTo-Json -InputObject $o -Compress";

// One PS 5.1 child dot-sources the maintenance copy of switch-login-task.ps1 (import-safe) and drives the same
// functions the tool uses. A recovery latch means wait, not fail (ST1 round 3). Same body as M1 deploy.
const SWITCH_PS=String.raw`. $q.switch
function Test-Latch($b){Test-Path -LiteralPath (Join-Path $b.Login.state_directory 's6-recovery-pending.json')}
function Test-TaskActive([string]$n){(Invoke-Schema6TaskOperation -Operation State -TaskName $n) -in @(2,4)}
function Assert-NotLive($b,[string]$what){$s=@(Get-Schema6LiveSessions $b);try{if($s.Count -ne 0){throw ($what+'_session_still_live')}}finally{foreach($x in $s){$x.Lease.Dispose()}}}
function Wait-LatchClear($b,[string]$n,[int]$sec){
 $w=[Diagnostics.Stopwatch]::StartNew()
 while(Test-Latch $b){if($w.Elapsed.TotalSeconds -ge $sec){throw 'recovery_latch_not_cleared'};if(-not (Test-TaskActive $n)){throw 'task_stopped_during_recovery'};Start-Sleep -Seconds 3}
}
function Wait-ReadyThroughRecovery([string]$n,$b,[string[]]$prev,[int]$sec){
 $w=[Diagnostics.Stopwatch]::StartNew();$seen=$false
 while($true){
  $left=$sec-[int]$w.Elapsed.TotalSeconds
  if($left -le 0){throw 'ready_timeout'}
  if(Test-Latch $b){
   if(-not $seen){$seen=$true;Write-Schema6Step 'wait.recovery_running' $true $n}
   if(-not (Test-TaskActive $n)){throw 'task_stopped_during_recovery'}
   Start-Sleep -Seconds 3;continue
  }
  try{$null=Wait-Schema6LoginReady -Name $n -Binding $b -PreviousSessions $prev -TimeoutSeconds $left -HealthUrl '';return $seen}
  catch{if($_.Exception.Message -notlike 'recovery_pending_manual_review_required*'){throw};$seen=$true;Write-Schema6Step 'wait.recovery_running' $true $n;Start-Sleep -Seconds 3}
 }
}
$old=$null;$new=$null
try{
 $pair=Invoke-Schema6Step 'switch.preflight' {
  $o=Get-Schema6LoginBinding $q.from;$n=Get-Schema6LoginBinding $q.to
  if(-not $o.Login.state_directory.Equals($n.Login.state_directory,[StringComparison]::OrdinalIgnoreCase)){throw 'same_data_root_required'}
  if(-not $o.McpPort -or -not $n.McpPort){throw 'both_core_and_mcp_ports_required'}
  Assert-Schema6NoRecovery $o;Assert-Schema6NoRecovery $n
  [pscustomobject]@{From=$o;To=$n}
 }
 $old=$pair.From;$new=$pair.To
 $clean=$true
 try{Assert-Schema6TaskUnchanged $q.from $old;$null=Invoke-Schema6StopBinding $old}catch{$clean=$false;Write-Schema6Step 'switch.stop_old_unclean' $false $_.Exception.Message}
 Invoke-Schema6Step 'switch.old_gone' {Assert-NotLive $old 'old';$w=[Diagnostics.Stopwatch]::StartNew();while(Test-TaskActive $q.from){if($w.Elapsed.TotalSeconds -ge 30){throw 'old_task_still_running'};Start-Sleep -Milliseconds 200}}
 Write-Schema6Step 'switch.stop_old_clean' $clean ''
}catch{Write-Schema6Step 'switch.not_started' $false $_.Exception.Message;exit 13}
$prev=@(Get-Schema6SessionDirectories $new)
try{
 Invoke-Schema6Step 'switch.disable_old' {Invoke-Schema6TaskOperation -Operation Disable -TaskName $q.from}
 Invoke-Schema6Step 'switch.enable_new' {Assert-Schema6TaskUnchanged $q.to $new;Invoke-Schema6TaskOperation -Operation Enable -TaskName $q.to}
 Invoke-Schema6Step 'switch.start_new' {Assert-Schema6TaskUnchanged $q.to $new;Invoke-Schema6TaskOperation -Operation Start -TaskName $q.to}
 $r=Wait-ReadyThroughRecovery $q.to $new $prev 360
 Write-Schema6Step 'switch.ready_new' $true $(if($r){'after_recovery'}else{'direct'})
 exit 0
}catch{Write-Schema6Step 'switch.failure' $false $_.Exception.Message}
try{
 Invoke-Schema6Step 'fallback.latch_clear' {if(Test-TaskActive $q.to){Wait-LatchClear $new $q.to 180}elseif(Test-Latch $new){throw 'recovery_latch_left_manual_review'}}
 try{$null=Invoke-Schema6StopBinding -Binding $new -PreviousSessions $prev}catch{Write-Schema6Step 'fallback.stop_new_note' $false $_.Exception.Message}
 Invoke-Schema6Step 'fallback.new_gone' {Assert-NotLive $new 'new';$w=[Diagnostics.Stopwatch]::StartNew();while(Test-TaskActive $q.to){if($w.Elapsed.TotalSeconds -ge 30){throw 'new_task_still_running'};Start-Sleep -Milliseconds 200}}
 Invoke-Schema6Step 'fallback.disable_new' {Invoke-Schema6TaskOperation -Operation Disable -TaskName $q.to}
 $prev2=@(Get-Schema6SessionDirectories $old)
 Invoke-Schema6Step 'fallback.enable_old' {Assert-Schema6TaskUnchanged $q.from $old;Invoke-Schema6TaskOperation -Operation Enable -TaskName $q.from}
 Invoke-Schema6Step 'fallback.start_old' {Invoke-Schema6TaskOperation -Operation Start -TaskName $q.from}
 $r=Wait-ReadyThroughRecovery $q.from $old $prev2 360
 Write-Schema6Step 'fallback.ready_old' $true $(if($r){'after_recovery'}else{'direct'})
 exit 10
}catch{Write-Schema6Step 'fallback.manual_review' $false $_.Exception.Message;exit 12}
`;

async function main(){
 const a=process.argv.slice(2);
 need(a.length===4&&a[0]==='--mode'&&a[1]==='deploy'&&a[2]==='--git','args','usage: --mode deploy --git <git.exe>');
 need(process.platform==='win32'&&/^v24\./.test(process.version)&&plain(process.execPath),'args','windows_node24_required');
 const G=a[3];need(plain(G)&&existsSync(G)&&statSync(G).isFile(),'args','git_path_required');
 const git=(args,step)=>{const r=run(G,['-C',REPO,...args],{step});need(r.code===0,step,'git_failed:'+args[0]);return r.stdout;};
 const home=process.env.USERPROFILE;need(plain(home),'args','userprofile_missing');

 // 0. Preflight (read-only).
 const before=tasks('step0');
 const active=before.filter(t=>t.name===ACTIVE);
 need(active.length===1&&active[0].state==='Running'&&active[0].actions===1,'step0','active_task_not_running:'+(active[0]?.state??'missing'));
 const others=before.filter(t=>t.name!==ACTIVE&&t.state!=='Disabled');need(others.length===0,'step0','other_task_enabled:'+others.map(t=>t.name).join(','));
 need(!before.some(t=>t.name===NEW),'step0','target_task_exists');
 const live=loginOf(active[0],'step0'),login=live.login,mcp=mcpOf(live,'step0');
 need(short(login.manifest_sha256)===OLD_MANIFEST,'step0','live_release_not_e3:'+short(login.manifest_sha256));
 need(!existsSync(path.join(login.state_directory,'s6-recovery-pending.json')),'step0','recovery_latch_present');
 need(!existsSync(path.join(login.state_directory,'s6-package-switch-pending.json')),'step0','package_switch_pending');
 const oldCand=path.dirname(mcp.working_directory),OUT=path.dirname(oldCand);
 need(path.basename(mcp.working_directory)==='runtime'&&/^mcp-candidate-/.test(path.basename(oldCand))&&plain(OUT),'step0','live_candidate_layout');
 need(serverOf(live,'step0')===OLD_SERVER&&short(fileSha(path.join(mcp.working_directory,'i_remote_mcp','server.mjs')))===OLD_SERVER,'step0','live_server_not_e3');
 need(short(fileSha(path.join(mcp.working_directory,'i_remote_mcp','mcp.mjs')))===OLD_MCP,'step0','live_mcp_not_e3');
 const stateMcp=mcp.environment?.I_REMOTE_MCP_STATE_DIR;
 need(plain(stateMcp)&&existsSync(stateMcp)&&statSync(stateMcp).isDirectory(),'step0','mcp_state_dir');
 const notesDir=path.join(home,'feishu-notes'),notesJson=path.join(stateMcp,'notes.json');
 need(plain(notesDir)&&existsSync(path.join(notesDir,'index.json')),'step0','notes_mirror_missing');
 const notesConfig={format:'notes-config-v1',notes_dir:notesDir};
 if(existsSync(notesJson))need(JSON.stringify(readJson(notesJson,null,'step0'))===JSON.stringify(notesConfig),'step0','notes_json_differs');
 const HEAD=git(['rev-parse','HEAD'],'step0').trim();
 need(git(['status','--porcelain','--untracked-files=no'],'step0').trim()==='','step0','checkout_dirty');
 const drift=git(['diff','--name-only',TOOLS_COMMIT,HEAD,'--','tools/i_core'],'step0').split(/\r?\n/).filter(Boolean).sort();
 need(JSON.stringify(drift)===JSON.stringify([...TOOLS_DRIFT].sort()),'step0','tools_drift:'+drift.join(','));
 const TOOLS=path.join(OUT,'tools-'+TOOLS_COMMIT),MT=path.join(TOOLS,'tools','i_core','maintenance');
 need(existsSync(path.join(MT,'switch-login-task.ps1'))&&existsSync(path.join(MT,'update-mcp-source.mjs')),'step0','tools_copy_missing');
 need(files(TOOLS).length===TOOLS_FILES,'step0','tools_copy_count');
 // Maintenance scripts in the copy must equal the committed ones (a CRLF copy is accepted when it equals them after CRLF->LF).
 for(const p of files(MT)){const rel='tools/i_core/maintenance/'+path.relative(MT,p).split(path.sep).join('/');
  const r=spawnSync(G,['-C',REPO,'show',HEAD+':'+rel],{env:childEnv(),windowsHide:true,maxBuffer:16*1024*1024});
  const b=readFileSync(p);need(r.status===0&&[sha(b),sha(Buffer.from(b.toString('latin1').replaceAll('\r\n','\n'),'latin1'))].includes(sha(r.stdout)),'step0','tools_copy_differs:'+path.basename(p));}
 const CAND=path.join(OUT,'mcp-candidate-'+HEAD.slice(0,8)),SETTINGS=path.join(OUT,'n2-mcp-settings-'+HEAD.slice(0,8));
 need(!existsSync(SETTINGS),'step0','settings_dir_exists');
 need(!(await portFree(LISTEN_PORT)),'step0','heart_rate_listener_not_up');
 // The same module the candidate inlines must read the home mirror (counts only).
 const notes=await import(pathToFileURL(path.join(REPO,'tools','i_remote_mcp','notes_tools.mjs')).href);
 let idx,recent;
 try{idx=notes.loadNotesIndex(notesDir);recent=notes.notesRecent(notesDir,{days:7});}
 catch(e){throw new Stop('step0','notes_unreadable:'+String(e.message).slice(0,60));}
 need(idx.docs.length>0,'step0','notes_index_empty');
 emit('step0',true,{active:'Running',live_server:OLD_SERVER,head:short(HEAD),tools:'tools-'+TOOLS_COMMIT,notes_json:existsSync(notesJson)?'present':'absent',
  notes_folders:idx.folders.length,notes_docs:idx.docs.length,notes_last_7_days:recent.docs.length,notes_synced_at:idx.synced_at});

 // 1. notes.json and the candidate. Both are inert until the new task starts.
 if(!existsSync(notesJson))writeFileSync(notesJson,JSON.stringify(notesConfig)+'\n',{flag:'wx'});
 need(JSON.stringify(notes.loadNotesConfig(stateMcp))===JSON.stringify(notesConfig),'step1','notes_json_check');
 const dirs=['','runtime',path.join('runtime','i_remote_mcp'),path.join('runtime','i_memory')];
 const buildRel='build/n2-candidate-'+randomBytes(4).toString('hex'),build=path.join(REPO,...buildRel.split('/'));
 let r=run(process.execPath,[path.join(REPO,'tools','i_remote_mcp','chatgpt_candidate.mjs'),'--out',buildRel],{cwd:REPO,step:'step1'});
 need(r.code===0,'step1','candidate_build_failed:'+lastErr(r));
 const cm=readJson(path.join(build,'manifest.json'),null,'step1');
 need(cm.changed_files===5&&cm.source_commit===HEAD&&cm.files.length===6,'step1','candidate_manifest');
 for(const f of cm.files)need(MCP_EXPECTED[f.path]===short(f.result_sha256),'step1','candidate_hash:'+f.path+':'+short(f.result_sha256));
 const built=files(build).map(p=>path.relative(build,p)).sort();
 if(!existsSync(CAND)){
  for(const d of dirs){need(existsSync(path.join(oldCand,d)),'step1','old_candidate_dir_missing:'+(d||'.'));mkdirSync(path.join(CAND,d),{recursive:true});}
  const acl=asList(value(ACL_PS,{pairs:dirs.map(d=>({rel:d||'.',from:d?path.join(oldCand,d):oldCand,to:d?path.join(CAND,d):CAND}))},'step1'));
  for(const x of acl)need(x.protected===true&&x.rules>0,'step1','candidate_acl:'+x.dir);
  for(const rel of built)copyFileSync(path.join(build,rel),path.join(CAND,rel));
 }
 need(JSON.stringify(files(CAND).map(p=>path.relative(CAND,p)).sort())===JSON.stringify(built),'step1','candidate_inventory');
 for(const rel of built)need(fileSha(path.join(CAND,rel))===fileSha(path.join(build,rel)),'step1','copy_mismatch:'+rel);
 const acl=asList(value(CHECK_ACL_PS,{dirs:dirs.map(d=>({rel:d||'.',path:d?path.join(CAND,d):CAND}))},'step1'));
 need(acl.length===dirs.length&&acl.every(x=>x.protected===true&&x.rules>0),'step1','candidate_acl_check');
 emit('step1',true,{candidate:'mcp-candidate-'+HEAD.slice(0,8),server:MCP_EXPECTED['i_remote_mcp/server.mjs'],notes_json:'written'});

 // 2. New task registered disabled, then switch (or fall back to the live task).
 const c1=['--from-task',ACTIVE,'--candidate',CAND,'--out',SETTINGS,'--new-task',NEW];
 r=run(process.execPath,[path.join(MT,'update-mcp-source.mjs'),...c1,'--dry-run'],{step:'step2'});
 const dry=rows(r.stdout).find(x=>x.step==='update.result');
 need(r.code===0&&dry?.detail==='dry_run_passed','step2','c1_dry_run:'+(rows(r.stdout).find(x=>x.ok===false)?.detail??r.code));
 r=run(process.execPath,[path.join(MT,'update-mcp-source.mjs'),...c1],{step:'step2'});
 need(r.code===0&&rows(r.stdout).find(x=>x.step==='update.result')?.detail==='registered_disabled','step2','c1:'+(rows(r.stdout).find(x=>x.ok===false)?.detail??r.code));
 const t0=Date.now();r=ps51(SWITCH_PS,{switch:path.join(MT,'switch-login-task.ps1'),from:ACTIVE,to:NEW},'step2',18);
 for(const row of rows(r.stdout))if(row.step!==undefined)emit('step2:'+row.step,row.ok!==false,typeof row.detail==='string'?row.detail.slice(0,240):row.detail);
 const after=tasks('step2'),running=after.filter(t=>t.state==='Running').map(t=>t.name),seconds=Math.round((Date.now()-t0)/1000);
 if(r.code!==0)throw new Stop('step2',(r.code===10?'switch_failed_old_restored':r.code===13?'not_started_old_untouched':'manual_review_required:'+r.code)+';running='+(running.join(',')||'none')+';seconds='+seconds);
 const cur=after.find(t=>t.name===NEW);
 need(cur?.state==='Running'&&serverOf(loginOf(cur,'step2'),'step2')===MCP_EXPECTED['i_remote_mcp/server.mjs'],'step2','new_not_running_candidate');
 need(after.every(t=>t.name===NEW||t.state==='Disabled'),'step2','final_task_states');
 emit('step2',true,{running:NEW,old_task:'Disabled',seconds});

 // 3. Heart-rate listener (inside the MCP process) came back.
 let listening=false;for(let i=0;i<20&&!listening;i++){listening=!(await portFree(LISTEN_PORT));if(!listening)await new Promise(res=>setTimeout(res,1500));}
 need(listening,'step3','heart_rate_listener_not_up');
 emit('step3',true,{heart_rate_listener:'up'});
 emit('done',true,{running:NEW,server:MCP_EXPECTED['i_remote_mcp/server.mjs'],tools:'notes_recent,notes_search,notes_read'});
}

main().catch(e=>{emit(e.step??'unexpected',false,e.detail??String(e.message).slice(0,300));process.exitCode=1;});
