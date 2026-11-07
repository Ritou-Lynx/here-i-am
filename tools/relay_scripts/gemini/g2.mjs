// G2 rollout: switch the live MCP (G1 candidate) to one that gives Gemini the ChatGPT tool set
// (food_log/food_day, study_*, heart_rate). Only server.mjs changes. Core is not changed.
//   --mode inspect  read-only: live task, candidate hashes, tailnet entry, maintenance copy, protocol probe
//   --mode deploy   the same checks, then
//     1  six-file candidate built from this checkout, copied out with protected ACLs
//     2  read-check: candidate still accepts 2025-11-25; heart_rate.json already present (not touched)
//     3  update-mcp-source: register the new task disabled
//     4  switch (waits through a Core crash-recovery latch; falls back to the old task)
//     5  heart-rate listener back up, tailscale serve 8447 unchanged, health over the tailnet
// Output: one JSON row per step; no tokens, logins, domains, paths or SIDs.
// Usage: g2-inspect.ps1 / g2-deploy.ps1 (Windows PowerShell 5.1, -File) run this with --git <git.exe>.
import {createHash,randomBytes} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {copyFileSync,existsSync,mkdirSync,readFileSync,readdirSync,statSync,writeFileSync} from 'node:fs';
import {createServer} from 'node:net';
import https from 'node:https';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const ACTIVE='HereIAm-iCoreSchema6-g1-proto-20261106';
const NEW='HereIAm-iCoreSchema6-g2-tools-20261106';
const OLD_SERVER='77a8dd30',OLD_MCP='838810b2';
const MCP_EXPECTED={'i_remote_mcp/server.mjs':'e418eade','i_remote_mcp/oauth.mjs':'e2c88aca','i_remote_mcp/diagnostics.mjs':'67b0fbec',
 'i_remote_mcp/mcp.mjs':'838810b2','i_remote_mcp/writeback.mjs':'a7a6f95d','i_memory/i_memory_read.mjs':'cee18518'};
// Maintenance tools: the ST1/HR1 copy (tools-4603fb79) is reused; tools/i_core has not changed since.
const TOOLS_COMMIT='4603fb79';
const TOOLS_FILES=321;
const LISTEN_PORT=47866, HTTPS_PORT=8447;
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
const lastErr=r=>(r.stderr.trim().split(/\r?\n/).filter(Boolean).pop()??'').slice(0,240);
const PS=()=>path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');
const PSARGS=['-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass'];
const HEAD51="$ErrorActionPreference='Stop'\nif($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'host_not_51'}\n$q=[Console]::In.ReadToEnd()|ConvertFrom-Json\n";
function ps51(script,input,step,timeoutMin=5){return run(PS(),[...PSARGS,'-EncodedCommand',Buffer.from(HEAD51+script,'utf16le').toString('base64')],{input:JSON.stringify(input??{}),step,timeoutMin});}
function value(script,input,step){const r=ps51(script,input,step);need(r.code===0,step,'powershell_exit_'+r.code+':'+lastErr(r));return JSON.parse(r.stdout.trim().split(/\r?\n/).filter(Boolean).pop());}
const asList=v=>Array.isArray(v)?v:[v];

const TASKS_PS="ConvertTo-Json -InputObject @(Get-ScheduledTask|Where-Object{$_.TaskName -like 'HereIAm-iCoreSchema6-*'}|ForEach-Object{[pscustomobject]@{name=$_.TaskName;state=[string]$_.State;arguments=[string]$_.Actions[0].Arguments}}) -Compress -Depth 3";
const tasks=step=>asList(value(TASKS_PS,{},step));
function loginOf(task,step){
 const tok=[...task.arguments.matchAll(/"([^"]*)"|(\S+)/g)].map(m=>m[1]??m[2]);
 const arg=re=>{const i=tok.map((t,j)=>re.test(t)?j:-1).filter(j=>j>=0);need(i.length===1&&i[0]+1<tok.length,step,'login_argument_ambiguous');return tok[i[0]+1];};
 const p=arg(/^-(Login)?ConfigurationPath$/i),h=arg(/^-(Login)?ConfigurationSha256$/i).toLowerCase();
 const login=readJson(p,h,step);need(login.format==='schema6-login-v1',step,'login_format');return {path:p,sha256:h,login};
}
const mcpOf=l=>readJson(l.login.mcp_configuration_path,l.login.mcp_configuration_sha256,'mcp');
const serverOf=l=>short(mcpOf(l).source_files.find(f=>f.path==='i_remote_mcp/server.mjs')?.sha256);
// Copy the DACL (only) of each source directory onto its target, protected.
const ACL_PS="$o=@()\nforeach($p in $q.pairs){$a=(Get-Item -LiteralPath $p.from).GetAccessControl('Access');$a.SetAccessRuleProtection($true,$true);(Get-Item -LiteralPath $p.to).SetAccessControl($a);$v=(Get-Item -LiteralPath $p.to).GetAccessControl('Access');$o+=[pscustomobject]@{dir=$p.rel;protected=$v.AreAccessRulesProtected;rules=@($v.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])).Count}}\nConvertTo-Json -InputObject $o -Compress";
const CHECK_ACL_PS="$o=@()\nforeach($p in $q.dirs){$v=(Get-Item -LiteralPath $p.path).GetAccessControl('Access');$o+=[pscustomobject]@{dir=$p.rel;protected=$v.AreAccessRulesProtected;rules=@($v.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])).Count}}\nConvertTo-Json -InputObject $o -Compress";

function tailscaleExe(step){
 const r=run('where.exe',['tailscale.exe'],{step});
 const found=r.code===0?r.stdout.split(/\r?\n/).map(s=>s.trim()).find(s=>s&&existsSync(s)):null;
 const fallback=path.join(process.env.ProgramFiles??'','Tailscale','tailscale.exe');
 const exe=found??(existsSync(fallback)?fallback:null);
 need(exe,step,'tailscale_not_found');return exe;
}
function tailscaleSelf(ts,step){
 const r=run(ts,['status','--json'],{step});need(r.code===0,step,'tailscale_status_failed');
 const s=JSON.parse(r.stdout);const login=s?.User?.[String(s?.Self?.UserID)]?.LoginName;const dns=String(s?.Self?.DNSName??'').replace(/\.$/,'');
 need(typeof login==='string'&&login&&!/\s/.test(login),step,'tailscale_login_missing');need(/^[a-z0-9.-]+\.ts\.net$/i.test(dns),step,'tailscale_dns_missing');
 need(s?.BackendState==='Running',step,'tailscale_not_running');
 return {login,dns};
}
// 'present' when :8447 already serves anything (then it must already point at our listener).
function serveState(ts,step){
 const r=run(ts,['serve','status','--json'],{step});need(r.code===0,step,'tailscale_serve_status_failed');
 const text=r.stdout.trim()||'{}';let j;try{j=JSON.parse(text);}catch{throw new Stop(step,'tailscale_serve_status_unparsed');}
 const web=Object.entries(j?.Web??{}).filter(([host])=>host.endsWith(':'+HTTPS_PORT));
 const tcp=j?.TCP?.[String(HTTPS_PORT)];
 if(!web.length&&!tcp)return 'absent';
 const proxies=web.flatMap(([,v])=>Object.values(v?.Handlers??{}).map(h=>h?.Proxy));
 return proxies.length&&proxies.every(p=>p==='http://127.0.0.1:'+LISTEN_PORT)?'ours':'other';
}
function portFree(port){return new Promise(resolve=>{const s=createServer();s.once('error',()=>resolve(false));s.listen(port,'127.0.0.1',()=>s.close(()=>resolve(true)));});}
function health(dns){return new Promise(resolve=>{
 const req=https.get({host:dns,port:HTTPS_PORT,path:'/v1/heart-rate/health',timeout:15000},res=>{let b='';res.on('data',d=>b+=d);res.on('end',()=>{let j=null;try{j=JSON.parse(b);}catch{}resolve({status:res.statusCode,ok:j?.ok===true});});});
 req.on('timeout',()=>{req.destroy();resolve({status:0,error:'timeout'});});
 req.on('error',e=>resolve({status:0,error:String(e.code??'error')}));
});}

// One PS 5.1 child dot-sources the ST1 copy of switch-login-task.ps1 (import-safe) and drives the same
// functions the tool uses. A recovery latch means wait, not fail (ST1 round 3). Same body as st1-retry.
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
 need(a.length===4&&a[0]==='--mode'&&['inspect','deploy'].includes(a[1])&&a[2]==='--git','args','usage: --mode inspect|deploy --git <git.exe>');
 const deploy=a[1]==='deploy';
 need(process.platform==='win32'&&/^v24\./.test(process.version)&&plain(process.execPath),'args','windows_node24_required');
 const G=a[3];need(plain(G)&&existsSync(G)&&statSync(G).isFile(),'args','git_path_required');
 const git=(args,step)=>{const r=run(G,['-C',REPO,...args],{step});need(r.code===0,step,'git_failed:'+args[0]);return r.stdout;};

 // 0. Preflight (read-only in both modes).
 const before=tasks('step0');
 const active=before.find(t=>t.name===ACTIVE);need(active?.state==='Running','step0','active_task_not_running:'+(active?.state??'missing'));
 need(before.every(t=>t.name===ACTIVE||t.state==='Disabled'),'step0','other_task_enabled');
 need(!before.some(t=>t.name===NEW),'step0','target_task_exists');
 const live=loginOf(active,'step0'),mcp=mcpOf(live);
 need(!existsSync(path.join(live.login.state_directory,'s6-recovery-pending.json')),'step0','recovery_latch_present');
 const oldCand=path.dirname(mcp.working_directory),OUT=path.dirname(oldCand);
 need(path.basename(mcp.working_directory)==='runtime'&&/^mcp-candidate-/.test(path.basename(oldCand))&&plain(OUT),'step0','live_candidate_layout');
 need(serverOf(live)===OLD_SERVER&&short(fileSha(path.join(mcp.working_directory,'i_remote_mcp','server.mjs')))===OLD_SERVER,'step0','live_server_not_g1');
 need(short(fileSha(path.join(mcp.working_directory,'i_remote_mcp','mcp.mjs')))===OLD_MCP,'step0','live_mcp_not_g1');
 const stateMcp=mcp.environment?.I_REMOTE_MCP_STATE_DIR;
 need(plain(stateMcp)&&existsSync(stateMcp)&&statSync(stateMcp).isDirectory(),'step0','mcp_state_dir');
 need(!Object.keys(mcp.environment??{}).some(k=>k==='I_REMOTE_MCP_HEART_RATE_PORT'),'step0','heart_rate_port_env_set');
 const hrJson=path.join(stateMcp,'heart_rate.json'),hrDir=path.join(stateMcp,'heart_rate');
 const HEAD=git(['rev-parse','HEAD'],'step0').trim();
 need(git(['status','--porcelain','--untracked-files=no'],'step0').trim()==='','step0','checkout_dirty');
 const changed=git(['diff','--name-only',TOOLS_COMMIT,HEAD,'--','tools/i_core'],'step0').split(/\r?\n/).filter(Boolean);
 need(changed.length===0,'step0','tools_diff:'+changed.join(','));
 const TOOLS=path.join(OUT,'tools-'+TOOLS_COMMIT),MT=path.join(TOOLS,'tools','i_core','maintenance');
 need(existsSync(path.join(MT,'switch-login-task.ps1'))&&existsSync(path.join(MT,'update-mcp-source.mjs')),'step0','tools_copy_missing');
 need(files(TOOLS).length===TOOLS_FILES,'step0','tools_copy_count');
 const CAND=path.join(OUT,'mcp-candidate-'+HEAD.slice(0,8)),SETTINGS=path.join(OUT,'g2-mcp-settings-'+HEAD.slice(0,8));
 need(!existsSync(SETTINGS),'step0','settings_dir_exists');
 const ts=tailscaleExe('step0'),self=tailscaleSelf(ts,'step0'),serve=serveState(ts,'step0');
 need(serve==='ours','step0','serve_8447_not_ours:'+serve);
 const listening0=!(await portFree(LISTEN_PORT));need(listening0,'step0','heart_rate_listener_not_up');
 need(existsSync(hrJson)&&existsSync(hrDir),'step0','heart_rate_state_missing');
 emit('step0',true,{mode:a[1],active:'Running',live_server:OLD_SERVER,head:short(HEAD),tools:'tools-'+TOOLS_COMMIT,
  heart_rate_json:'present',heart_rate_dir:'present',listen_port:'live',tailscale:'running',serve_8447:serve});

 // 1. Six-file candidate (in inspect mode: built into this worktree's build/ only and compared).
 const dirs=['','runtime',path.join('runtime','i_remote_mcp'),path.join('runtime','i_memory')];
 const buildRel='build/g2-candidate-'+randomBytes(4).toString('hex'),build=path.join(REPO,...buildRel.split('/'));
 let r=run(process.execPath,[path.join(REPO,'tools','i_remote_mcp','chatgpt_candidate.mjs'),'--out',buildRel],{cwd:REPO,step:'step1'});
 need(r.code===0,'step1','candidate_build_failed:'+lastErr(r));
 const cm=readJson(path.join(build,'manifest.json'),null,'step1');
 need(cm.changed_files===5&&cm.source_commit===HEAD&&cm.files.length===6,'step1','candidate_manifest');
 for(const f of cm.files)need(MCP_EXPECTED[f.path]===short(f.result_sha256),'step1','candidate_hash:'+f.path+':'+short(f.result_sha256));
 const built=files(build).map(p=>path.relative(build,p)).sort();
 if(!deploy){
  // Read-only probes: protocol versions, and heart_rate from a throwaway state dir in build/.
  const proto=protoProbe(path.join(build,'runtime','i_remote_mcp'),'step1');
  const probe=hrProbe(path.join(build,'runtime','i_remote_mcp','server.mjs'),path.join(build,'probe-state'),self.login,'step1');
  emit('step1',true,{candidate:'built_in_worktree',server:MCP_EXPECTED['i_remote_mcp/server.mjs'],proto,probe});
  emit('done',true,{mode:'inspect',ready_to_deploy:true});
  return;
 }
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
 emit('step1',true,{candidate:'mcp-candidate-'+HEAD.slice(0,8),server:MCP_EXPECTED['i_remote_mcp/server.mjs'],acl:acl.map(x=>x.dir+':'+x.protected)});

 // 2. Read-checks only: copied candidate accepts 2025-11-25; heart_rate state untouched.
 const proto=protoProbe(path.join(CAND,'runtime','i_remote_mcp'),'step2');
 emit('step2',true,{proto,heart_rate_json:'kept'});

 // 3. New task, registered disabled.
 const c1=['--from-task',ACTIVE,'--candidate',CAND,'--out',SETTINGS,'--new-task',NEW];
 r=run(process.execPath,[path.join(MT,'update-mcp-source.mjs'),...c1,'--dry-run'],{step:'step3'});
 const dry=rows(r.stdout).find(x=>x.step==='update.result');
 need(r.code===0&&dry?.detail==='dry_run_passed','step3','c1_dry_run:'+(rows(r.stdout).find(x=>x.ok===false)?.detail??r.code));
 need(JSON.stringify(dry.result?.diff)===JSON.stringify({mcp:['source_files','working_directory'],backup:['specTemplate.entries'],login:['backup_configuration_path','backup_configuration_sha256','mcp_configuration_path','mcp_configuration_sha256']}),'step3','c1_field_diff:'+JSON.stringify(dry.result?.diff));
 r=run(process.execPath,[path.join(MT,'update-mcp-source.mjs'),...c1],{step:'step3'});
 need(r.code===0&&rows(r.stdout).find(x=>x.step==='update.result')?.detail==='registered_disabled','step3','c1:'+(rows(r.stdout).find(x=>x.ok===false)?.detail??r.code));
 const mid=tasks('step3'),nt=mid.find(t=>t.name===NEW);
 need(nt,'step3','new_task_missing');
 const ntMcp=mcpOf(loginOf(nt,'step3'));
 need(nt?.state==='Disabled'&&short(ntMcp.source_files.find(f=>f.path==='i_remote_mcp/server.mjs')?.sha256)===MCP_EXPECTED['i_remote_mcp/server.mjs'],'step3','new_task_not_candidate');
 emit('step3',true,{task:NEW,registered:'disabled'});

 // 4. Switch (or fall back) in one PS 5.1 child; relay its rows.
 const t0=Date.now();r=ps51(SWITCH_PS,{switch:path.join(MT,'switch-login-task.ps1'),from:ACTIVE,to:NEW},'step4',18);
 for(const row of rows(r.stdout))if(row.step!==undefined)emit('step4:'+row.step,row.ok!==false,typeof row.detail==='string'?row.detail.slice(0,240):row.detail);
 const after=tasks('step4'),running=after.filter(t=>t.state==='Running').map(t=>t.name);
 const seconds=Math.round((Date.now()-t0)/1000);
 emit('step4.tasks',true,after.filter(t=>[ACTIVE,NEW].includes(t.name)).map(t=>({name:t.name,state:t.state})));
 if(r.code!==0)throw new Stop('step4',(r.code===10?'switch_failed_old_restored':r.code===13?'not_started_old_untouched':'manual_review_required:'+r.code)+';running='+(running.join(',')||'none')+';seconds='+seconds);
 const cur=after.find(t=>t.name===NEW);
 need(cur?.state==='Running'&&short(mcpOf(loginOf(cur,'step4')).source_files.find(f=>f.path==='i_remote_mcp/server.mjs')?.sha256)===MCP_EXPECTED['i_remote_mcp/server.mjs'],'step4','new_not_running_candidate');
 need(after.every(t=>t.name===NEW||t.state==='Disabled'),'step4','final_task_states');
 need(mcpOf(loginOf(cur,'step4')).environment?.I_REMOTE_MCP_STATE_DIR===stateMcp,'step4','mcp_state_dir_changed');
 emit('step4',true,{running:NEW,old_task:'Disabled',seconds});

 // 5. Tailnet entry for the phone, then a health check through it (this computer's own login).
 let listening=false;for(let i=0;i<20&&!listening;i++){listening=!(await portFree(LISTEN_PORT));if(!listening)await new Promise(res=>setTimeout(res,1500));}
 need(listening,'step5','listener_not_up');
 let serveAction='kept';
 if(serveState(ts,'step5')==='absent'){
  r=run(ts,['serve','--bg','--https='+HTTPS_PORT,'http://127.0.0.1:'+LISTEN_PORT],{step:'step5',timeoutMin:2});
  need(r.code===0,'step5','tailscale_serve_failed:'+r.code);serveAction='added';
 }
 need(serveState(ts,'step5')==='ours','step5','tailscale_serve_not_ours');
 let h={status:0};for(let i=0;i<5&&h.status!==200;i++){h=await health(self.dns);if(h.status!==200)await new Promise(res=>setTimeout(res,3000));}
 emit('step5',h.status===200&&h.ok,{serve_8447:serveAction,tailnet_health:h.status,error:h.error});
 need(h.status===200&&h.ok,'done','tailnet_health_failed:'+h.status);
 emit('done',true,{running:NEW,server:MCP_EXPECTED['i_remote_mcp/server.mjs'],gemini:'chatgpt tool set'});
}

// Imports the candidate's mcp.mjs and diagnostics label in a separate node; nothing listens.
function protoProbe(dir,step){
 const code="import {pathToFileURL} from 'node:url';import path from 'node:path';let t='';process.stdin.on('data',d=>t+=d).on('end',async()=>{const q=JSON.parse(t);"+
  "const m=await import(pathToFileURL(path.join(q.dir,'mcp.mjs')).href);const d=await import(pathToFileURL(path.join(q.dir,'diagnostics.mjs')).href);"+
  "console.log(JSON.stringify({versions:m.SUPPORTED_PROTOCOL_VERSIONS.join(','),negotiated:m.negotiateProtocolVersion('2025-11-25'),label:d.protocolVersionLabel('2025-11-25')}));});";
 const r=run(process.execPath,['--disable-warning=ExperimentalWarning','--input-type=module','-e',code],{step,input:JSON.stringify({dir})});
 const pr=rows(r.stdout).pop();
 need(r.code===0&&pr?.versions==='2025-11-25,2025-06-18,2025-03-26'&&pr.negotiated==='2025-11-25'&&pr.label==='2025-11-25',step,'protocol_probe:'+(lastErr(r)||JSON.stringify(pr)));
 return pr.versions;
}

// Loads the candidate in a separate node and checks heart_rate.json and the tool without listening.
// throwaway=true writes a config into a fresh directory under build/ (inspect mode only).
function hrProbe(server,stateDir,login,step,throwaway=true){
 const code="import {pathToFileURL} from 'node:url';import {mkdirSync,writeFileSync} from 'node:fs';import path from 'node:path';let t='';process.stdin.on('data',d=>t+=d).on('end',async()=>{const q=JSON.parse(t);"+
  "if(q.throwaway){mkdirSync(q.state,{recursive:true});writeFileSync(path.join(q.state,'heart_rate.json'),JSON.stringify({format:'heart-rate-v1',tailscale_logins:[q.login]}));}"+
  "const m=await import(pathToFileURL(q.server).href);const c=m.loadHeartRateConfig(q.state);"+
  "const s=m.createHeartRateStore({stateDir:q.state});const now=await m.createHeartRateTools({store:s}).handlers.heart_rate({});"+
  "console.log(JSON.stringify({loaded:true,logins:c.tailscale_logins.length,tool:m.HEART_RATE_TOOLS.map(x=>x.name).join(','),has_latest:now.latest!==null}));});";
 const r=run(process.execPath,['--disable-warning=ExperimentalWarning','--input-type=module','-e',code],{step,input:JSON.stringify({server,state:stateDir,login,throwaway})});
 const pr=rows(r.stdout).pop();need(r.code===0&&pr?.loaded===true&&pr.logins===1&&pr.tool==='heart_rate',step,'heart_rate_probe:'+(lastErr(r)||r.code));
 return {logins:pr.logins,tool:pr.tool,has_latest:pr.has_latest};
}

main().catch(e=>{emit(e.step??'unexpected',false,e.detail??String(e.message).slice(0,300));process.exitCode=1;});
