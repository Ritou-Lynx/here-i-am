// M1 (daily life digest) rollout, round 2: deploy. Production changes, run only after the user's 👍.
//   0  same preflight as prepare (live G2 task e418eade, sources, maintenance copy tools-4603fb79, tailnet entry)
//   1  decrypt the AMap key and ntfy topic (RSA-OAEP, key made by round 1; only ciphertext is in the repo)
//   2  generator copied to %USERPROFILE%\life-digest\tool-<head8>, config written (protected folder), --check, one test push
//   3  <MCP state>\life_digest.json, then the six-file candidate (server bde3ff9f) copied out with protected ACLs
//   4  update-mcp-source registers the new task disabled; switch (falls back to G2 on failure)
//   5  heart-rate listener and tailscale serve 8447 still healthy
//   6  scheduled task HereIAm-LifeDigest: 04:30 / 07:30 / 19:30 and at logon, hidden, StartWhenAvailable
//   7  trial runs inside the time left: one day version without push, one morning broadcast (weather)
// Output: one JSON row per step; no tokens, logins, domains, paths, SIDs or message text.
// Usage: m1-deploy.ps1 (Windows PowerShell 5.1, -File) runs this with --git <git.exe>.
import {createHash,createPrivateKey,createPublicKey as createPublicKeyFrom,privateDecrypt,constants as cryptoConstants,randomBytes} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {copyFileSync,existsSync,mkdirSync,readFileSync,readdirSync,statSync,writeFileSync} from 'node:fs';
import {createServer} from 'node:net';
import https from 'node:https';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const ACTIVE='HereIAm-iCoreSchema6-g2-tools-20261106';
const NEW='HereIAm-iCoreSchema6-m1-digest-20261107';
const OLD_SERVER='e418eade',OLD_MCP='838810b2';
const MCP_EXPECTED={'i_remote_mcp/server.mjs':'bde3ff9f','i_remote_mcp/oauth.mjs':'e2c88aca','i_remote_mcp/diagnostics.mjs':'67b0fbec',
 'i_remote_mcp/mcp.mjs':'838810b2','i_remote_mcp/writeback.mjs':'a7a6f95d','i_memory/i_memory_read.mjs':'cee18518'};
const TOOLS_COMMIT='4603fb79';
const TOOLS_FILES=321;
const LISTEN_PORT=47866, HTTPS_PORT=8447;
const REPO=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..','..','..');
// Filled from round 1: Codex model and launcher style, deploy key fingerprint, encrypted settings.
const CODEX_MODEL='gpt-5.6-sol';
const CODEX_EXTRA=['-c','mcp_servers={}'];
const KEY_FINGERPRINT='a2b6f83d';
const SETTINGS_CIPHERTEXT='kfp0jeVQv0IA7biR8ruh0Pp92cYxFuIcJUGe/F2Ocd0Q6nasRO6dMq9ldH7r2DDCQ34zpHXWp2fKIvbFYuh1D+ccwKB46nVrUh7Jg4mdmRfuf+Bk33vt0vXVJbT/eYwJ6BDjD0uw0GmZqR+Hbj5He29ve/NeyGX3LF2Zqq02xyJOn3NzFfputaz6bzMSWoseWzMJD7sghF9QEjFXyzhgMi+hrvEiw+O9mT6Sow0dQ0f+4gJ8S3s5LBusJYxe4LZyQ+QSa0DnGpsEzxK79bKcDfnvjMdW0jlAls4SHqgkblvuRUqCLu5hStAS32u+3u5wW6wD9SjgplWl5N2oV4jiPeVBOiPkW53Mb2iqj0yVa16ySd3bos/rvD2BvmLR8F9ok6zTigeOE8pjXco1J9nSdXp/3xKlhI5lvPSlCMOpYY408W0cfESHcyVhgMf9Po6OA/sSA5xrVvXw1mvSZk/M9axN/z8NsBxPEk5bkf8dV0F79el3QEtsx6SuZdXc6cHg';
const ADCODE='110108', WEATHER_LABEL='海淀', NTFY_SERVER='https://ntfy.sh';
// Generator files copied out of this checkout (layout kept so relative imports work).
const GENERATOR_FILES=['tools/life_digest/life_digest_run.mjs','tools/life_digest/life_digest_lib.mjs','tools/life_digest/chat_source.mjs',
 'tools/i_core/test_fixtures/release_schema6/mcp_reader/legacy/i_memory/i_memory_read.mjs','tools/i_remote_mcp/notes_tools.mjs'];
const TASK='HereIAm-LifeDigest';

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


function findCodex(step){
 const r=run('where.exe',['codex'],{step});
 const hits=r.code===0?r.stdout.split(/\r?\n/).map(s=>s.trim()).filter(s=>s&&existsSync(s)):[];
 const exe=hits.find(h=>/\.exe$/i.test(h));if(exe)return [exe];
 for(const hit of hits){const js=path.join(path.dirname(hit),'node_modules','@openai','codex','bin','codex.js');if(existsSync(js))return [process.execPath,js];}
 const fb=path.join(process.env.APPDATA??'','npm','node_modules','@openai','codex','bin','codex.js');
 return existsSync(fb)?[process.execPath,fb]:null;
}
const label=t=>(String(t).trim().split(/\r?\n/).find(Boolean)??'').replace(/[A-Za-z]:\\[^\s]*/g,'<path>').replace(/[^\w .:@()\/<>=+-]/g,'').slice(0,160);
// Scheduled task for the generator: wscript runs a hidden cmd that appends output to logs\task.log.
const TASK_PS=String.raw`$vbsText=[string]$q.vbsText
[IO.File]::WriteAllText($q.vbs,$vbsText,[Text.Encoding]::Unicode)
$wscript=Join-Path $env:SystemRoot 'System32\wscript.exe'
$existing=Get-ScheduledTask -TaskName $q.task -ErrorAction SilentlyContinue
if($existing){$a=$existing.Actions[0];if($a.Execute -ne $wscript -or -not ([string]$a.Arguments).Contains('life-digest')){throw 'task_name_taken'}}
$action=New-ScheduledTaskAction -Execute $wscript -Argument ('//B //NoLogo "'+$q.vbs+'"')
$triggers=@((New-ScheduledTaskTrigger -Daily -At '04:30'),(New-ScheduledTaskTrigger -Daily -At '07:30'),(New-ScheduledTaskTrigger -Daily -At '19:30'))
$logon=New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name);$logon.Delay='PT5M';$triggers+=$logon
$principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
$settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 40) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $q.task -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description 'Lin Ai daily life digest (04:30 final, 07:30 morning, 19:30 day).' -Force|Out-Null
$t=Get-ScheduledTask -TaskName $q.task;$i=Get-ScheduledTaskInfo -TaskName $q.task
ConvertTo-Json -Compress -InputObject ([pscustomobject]@{state=[string]$t.State;logon=[string]$t.Principal.LogonType;triggers=$t.Triggers.Count;next=$(if($i.NextRunTime){$i.NextRunTime.ToString('yyyy-MM-ddTHH:mm')}else{'none'});replaced=[bool]$existing})`;

async function main(){
 const T_START=Date.now();
 const a=process.argv.slice(2);
 need(a.length===4&&a[0]==='--mode'&&a[1]==='deploy'&&a[2]==='--git','args','usage: --mode deploy --git <git.exe>');
 need(process.platform==='win32'&&/^v24\./.test(process.version)&&plain(process.execPath),'args','windows_node24_required');
 const G=a[3];need(plain(G)&&existsSync(G)&&statSync(G).isFile(),'args','git_path_required');
 const git=(args,step)=>{const r=run(G,['-C',REPO,...args],{step});need(r.code===0,step,'git_failed:'+args[0]);return r.stdout;};
 const home=process.env.USERPROFILE;need(plain(home),'args','userprofile_missing');

 // 0. Preflight (read-only).
 const before=tasks('step0');
 const active=before.find(t=>t.name===ACTIVE);need(active?.state==='Running','step0','active_task_not_running:'+(active?.state??'missing'));
 need(before.every(t=>t.name===ACTIVE||t.state==='Disabled'),'step0','other_task_enabled');
 need(!before.some(t=>t.name===NEW),'step0','target_task_exists');
 const live=loginOf(active,'step0'),mcp=mcpOf(live);
 need(!existsSync(path.join(live.login.state_directory,'s6-recovery-pending.json')),'step0','recovery_latch_present');
 const oldCand=path.dirname(mcp.working_directory),OUT=path.dirname(oldCand);
 need(path.basename(mcp.working_directory)==='runtime'&&/^mcp-candidate-/.test(path.basename(oldCand))&&plain(OUT),'step0','live_candidate_layout');
 need(serverOf(live)===OLD_SERVER&&short(fileSha(path.join(mcp.working_directory,'i_remote_mcp','server.mjs')))===OLD_SERVER,'step0','live_server_not_g2');
 need(short(fileSha(path.join(mcp.working_directory,'i_remote_mcp','mcp.mjs')))===OLD_MCP,'step0','live_mcp_not_g2');
 const stateMcp=mcp.environment?.I_REMOTE_MCP_STATE_DIR,coreDb=mcp.database_path,policy=mcp.environment?.I_MEMORY_POLICY;
 need(plain(stateMcp)&&existsSync(stateMcp)&&statSync(stateMcp).isDirectory(),'step0','mcp_state_dir');
 need(plain(coreDb)&&existsSync(coreDb)&&plain(policy)&&existsSync(policy),'step0','chat_sources_missing');
 const lifeJson=path.join(stateMcp,'life_digest.json');
 const HEAD=git(['rev-parse','HEAD'],'step0').trim();
 need(git(['status','--porcelain','--untracked-files=no'],'step0').trim()==='','step0','checkout_dirty');
 const changed=git(['diff','--name-only',TOOLS_COMMIT,HEAD,'--','tools/i_core'],'step0').split(/\r?\n/).filter(Boolean);
 need(changed.length===0,'step0','tools_diff:'+changed.join(','));
 const TOOLS=path.join(OUT,'tools-'+TOOLS_COMMIT),MT=path.join(TOOLS,'tools','i_core','maintenance');
 need(existsSync(path.join(MT,'switch-login-task.ps1'))&&existsSync(path.join(MT,'update-mcp-source.mjs')),'step0','tools_copy_missing');
 need(files(TOOLS).length===TOOLS_FILES,'step0','tools_copy_count');
 const CAND=path.join(OUT,'mcp-candidate-'+HEAD.slice(0,8)),SETTINGS=path.join(OUT,'m1-mcp-settings-'+HEAD.slice(0,8));
 need(!existsSync(SETTINGS),'step0','settings_dir_exists');
 const ts=tailscaleExe('step0'),self=tailscaleSelf(ts,'step0'),serve=serveState(ts,'step0');
 need(serve==='ours','step0','serve_8447_not_ours:'+serve);
 need(!(await portFree(LISTEN_PORT)),'step0','heart_rate_listener_not_up');
 const base=path.join(home,'life-digest'),cfgDir=path.join(base,'config'),keyFile=path.join(cfgDir,'deploy-key.pem');
 need(existsSync(keyFile),'step0','deploy_key_missing');
 const codex=findCodex('step0');need(codex,'step0','codex_not_found');
 emit('step0',true,{active:'Running',live_server:OLD_SERVER,head:short(HEAD),tools:'tools-'+TOOLS_COMMIT,serve_8447:serve,life_digest_json:existsSync(lifeJson)?'present':'absent'});

 // 1. Settings.
 const key=createPrivateKey(readFileSync(keyFile,'utf8'));
 const fpr=short(createHash('sha256').update(createPublicKeyDer(key)).digest('hex'));
 need(fpr===KEY_FINGERPRINT,'step1','deploy_key_fingerprint');
 let secrets;
 try{secrets=JSON.parse(privateDecrypt({key,padding:cryptoConstants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256'},Buffer.from(SETTINGS_CIPHERTEXT,'base64')).toString('utf8'));}
 catch{throw new Stop('step1','settings_decrypt_failed');}
 need(/^[0-9a-f]{32}$/i.test(String(secrets?.amap_key))&&/^[A-Za-z0-9_-]{8,64}$/.test(String(secrets?.ntfy_topic)),'step1','settings_invalid');
 emit('step1',true,{settings:'decrypted',fingerprint:fpr});

 // 2. Generator.
 const tool=path.join(base,'tool-'+HEAD.slice(0,8)),data=path.join(base,'data'),logs=path.join(base,'logs');
 for(const d of [tool,data,logs])mkdirSync(d,{recursive:true});
 for(const rel of GENERATOR_FILES){const to=path.join(tool,...rel.split('/'));mkdirSync(path.dirname(to),{recursive:true});copyFileSync(path.join(REPO,...rel.split('/')),to);need(fileSha(to)===fileSha(path.join(REPO,...rel.split('/'))),'step2','copy_mismatch:'+path.basename(rel));}
 const configFile=path.join(cfgDir,'generator.json');
 const config={format:'life-digest-generator-v1',digest_dir:data,chat:{core_db:coreDb,policy},heart_rate_dir:path.join(stateMcp,'heart_rate'),
  notes_dir:existsSync(path.join(home,'feishu-notes','index.json'))?path.join(home,'feishu-notes'):null,
  weather:{amap_key:secrets.amap_key,adcode:ADCODE,label:WEATHER_LABEL},
  codex:{argv:codex,model:CODEX_MODEL,extra_args:CODEX_EXTRA,timeout_minutes:6},
  ntfy:{server:NTFY_SERVER,topic:secrets.ntfy_topic,max_per_day:2},openai:null};
 writeFileSync(configFile,JSON.stringify(config,null,1)+'\n',{mode:0o600});
 const runner=path.join(tool,'tools','life_digest','life_digest_run.mjs');
 const gen=(args,min)=>{const r=run(process.execPath,[runner,'--config',configFile,...args],{step:'step2',timeoutMin:min});return {code:r.code,rows:rows(r.stdout),err:lastErr(r)};};
 const check=gen(['--check'],2);need(check.code===0,'step2','generator_check:'+check.err);
 emit('step2.check',true,check.rows[0]);
 let pushed='failed';
 try{const res=await fetch(NTFY_SERVER,{method:'POST',signal:AbortSignal.timeout(15000),headers:{'content-type':'application/json'},
  body:JSON.stringify({topic:secrets.ntfy_topic,title:'林埃',message:'日摘要上线测试：以后白天发现你没好好吃饭、待办拖太久，我会这样提醒你。',tags:['two_hearts']})});pushed=String(res.status);}catch(e){pushed='error:'+String(e.code??e.name);}
 emit('step2.test_push',pushed==='200',{ntfy:pushed});

 // 3. MCP config and candidate.
 if(existsSync(lifeJson))need(JSON.stringify(readJson(lifeJson,null,'step3'))===JSON.stringify({format:'life-digest-v1',digest_dir:data}),'step3','life_digest_json_differs');
 else writeFileSync(lifeJson,JSON.stringify({format:'life-digest-v1',digest_dir:data})+'\n',{flag:'wx'});
 const dirs=['','runtime',path.join('runtime','i_remote_mcp'),path.join('runtime','i_memory')];
 const buildRel='build/m1-candidate-'+randomBytes(4).toString('hex'),build=path.join(REPO,...buildRel.split('/'));
 let r=run(process.execPath,[path.join(REPO,'tools','i_remote_mcp','chatgpt_candidate.mjs'),'--out',buildRel],{cwd:REPO,step:'step3'});
 need(r.code===0,'step3','candidate_build_failed:'+lastErr(r));
 const cm=readJson(path.join(build,'manifest.json'),null,'step3');
 need(cm.changed_files===5&&cm.source_commit===HEAD&&cm.files.length===6,'step3','candidate_manifest');
 for(const f of cm.files)need(MCP_EXPECTED[f.path]===short(f.result_sha256),'step3','candidate_hash:'+f.path+':'+short(f.result_sha256));
 const built=files(build).map(p=>path.relative(build,p)).sort();
 if(!existsSync(CAND)){
  for(const d of dirs){need(existsSync(path.join(oldCand,d)),'step3','old_candidate_dir_missing:'+(d||'.'));mkdirSync(path.join(CAND,d),{recursive:true});}
  const acl=asList(value(ACL_PS,{pairs:dirs.map(d=>({rel:d||'.',from:d?path.join(oldCand,d):oldCand,to:d?path.join(CAND,d):CAND}))},'step3'));
  for(const x of acl)need(x.protected===true&&x.rules>0,'step3','candidate_acl:'+x.dir);
  for(const rel of built)copyFileSync(path.join(build,rel),path.join(CAND,rel));
 }
 need(JSON.stringify(files(CAND).map(p=>path.relative(CAND,p)).sort())===JSON.stringify(built),'step3','candidate_inventory');
 for(const rel of built)need(fileSha(path.join(CAND,rel))===fileSha(path.join(build,rel)),'step3','copy_mismatch:'+rel);
 const acl=asList(value(CHECK_ACL_PS,{dirs:dirs.map(d=>({rel:d||'.',path:d?path.join(CAND,d):CAND}))},'step3'));
 need(acl.length===dirs.length&&acl.every(x=>x.protected===true&&x.rules>0),'step3','candidate_acl_check');
 emit('step3',true,{candidate:'mcp-candidate-'+HEAD.slice(0,8),server:MCP_EXPECTED['i_remote_mcp/server.mjs'],life_digest_json:'written'});

 // 4. New task registered disabled, then switch (or fall back).
 const c1=['--from-task',ACTIVE,'--candidate',CAND,'--out',SETTINGS,'--new-task',NEW];
 r=run(process.execPath,[path.join(MT,'update-mcp-source.mjs'),...c1,'--dry-run'],{step:'step4'});
 const dry=rows(r.stdout).find(x=>x.step==='update.result');
 need(r.code===0&&dry?.detail==='dry_run_passed','step4','c1_dry_run:'+(rows(r.stdout).find(x=>x.ok===false)?.detail??r.code));
 r=run(process.execPath,[path.join(MT,'update-mcp-source.mjs'),...c1],{step:'step4'});
 need(r.code===0&&rows(r.stdout).find(x=>x.step==='update.result')?.detail==='registered_disabled','step4','c1:'+(rows(r.stdout).find(x=>x.ok===false)?.detail??r.code));
 const t0=Date.now();r=ps51(SWITCH_PS,{switch:path.join(MT,'switch-login-task.ps1'),from:ACTIVE,to:NEW},'step4',18);
 for(const row of rows(r.stdout))if(row.step!==undefined)emit('step4:'+row.step,row.ok!==false,typeof row.detail==='string'?row.detail.slice(0,240):row.detail);
 const after=tasks('step4'),running=after.filter(t=>t.state==='Running').map(t=>t.name),seconds=Math.round((Date.now()-t0)/1000);
 if(r.code!==0)throw new Stop('step4',(r.code===10?'switch_failed_old_restored':r.code===13?'not_started_old_untouched':'manual_review_required:'+r.code)+';running='+(running.join(',')||'none')+';seconds='+seconds);
 const cur=after.find(t=>t.name===NEW);
 need(cur?.state==='Running'&&short(mcpOf(loginOf(cur,'step4')).source_files.find(f=>f.path==='i_remote_mcp/server.mjs')?.sha256)===MCP_EXPECTED['i_remote_mcp/server.mjs'],'step4','new_not_running_candidate');
 need(after.every(t=>t.name===NEW||t.state==='Disabled'),'step4','final_task_states');
 emit('step4',true,{running:NEW,old_task:'Disabled',seconds});

 // 5. Heart-rate entry still healthy.
 let listening=false;for(let i=0;i<20&&!listening;i++){listening=!(await portFree(LISTEN_PORT));if(!listening)await new Promise(res=>setTimeout(res,1500));}
 need(listening&&serveState(ts,'step5')==='ours','step5','heart_rate_entry');
 let h={status:0};for(let i=0;i<5&&h.status!==200;i++){h=await health(self.dns);if(h.status!==200)await new Promise(res=>setTimeout(res,3000));}
 emit('step5',h.status===200&&h.ok,{tailnet_health:h.status,error:h.error});

 // 6. Generator schedule.
 const q='"',inner=q+process.execPath+q+' '+q+runner+q+' --config '+q+configFile+q+' >> '+q+path.join(logs,'task.log')+q+' 2>&1';
 for(const p of [process.execPath,runner,configFile,logs])need(!p.includes('"')&&!p.includes('%'),'step6','path_unsupported_character');
 const cmdLine='cmd.exe /d /s /c '+q+inner+q;
 const vbsText="' HereIAm-LifeDigest launcher (generated by m1-deploy). Hidden window, waits, passes the exit code on.\r\nWScript.Quit CreateObject(\"WScript.Shell\").Run(\""+cmdLine.replaceAll('"','""')+"\", 0, True)\r\n";
 const sched=value(TASK_PS,{task:TASK,vbs:path.join(base,'life-digest.vbs'),vbsText},'step6');
 emit('step6',sched.state==='Ready'&&sched.triggers===4,sched);
 // 7. Trial runs last, so a slow model cannot leave the MCP switch half done. Bounded to stay inside the round limit.
 const left=()=>17-(Date.now()-T_START)/60000;
 if(left()>4){const day=gen(['--stage','day','--no-push'],Math.min(13,Math.floor(left()-1)));
  emit('step7.day',day.code===0,day.rows[0]??{exit:day.code,err:label(day.err)});}
 else emit('step7.day',true,{skipped:'time_budget'});
 if(left()>2){const morning=gen(['--stage','morning'],Math.floor(left()-0.5));
  emit('step7.morning',morning.code===0,morning.rows[0]??{exit:morning.code,err:label(morning.err)});}
 else emit('step7.morning',true,{skipped:'time_budget'});
 emit('done',true,{running:NEW,server:MCP_EXPECTED['i_remote_mcp/server.mjs'],generator:TASK});
}
function createPublicKeyDer(privateKey){return createPublicKeyFrom(privateKey).export({type:'spki',format:'der'});}

main().catch(e=>{emit(e.step??'unexpected',false,e.detail??String(e.message).slice(0,300));process.exitCode=1;});
