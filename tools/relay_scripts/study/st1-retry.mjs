// ST1 rollout, retry the switch after round 4's read-only check (old task Running, new
// Disabled, no recovery latch). Round 3 failed because the switch tool's ready wait treats
// the transient crash-recovery latch as fatal: round 1's forced stop left the lifecycle
// marker unclean, so the new Core first ran automatic recovery. This retry uses the same
// maintenance functions but waits through a recovery latch instead of failing on it.
// Fallback: if the new task does not become ready, stop it, then restart the old task.
// Output: one JSON row per step; no tokens, paths, SIDs or study content.
// Usage: st1-retry.ps1 (Windows PowerShell 5.1, -File).
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {existsSync,readFileSync} from 'node:fs';
import path from 'node:path';

const ACTIVE='HereIAm-iCoreSchema6-n2-food-20261031';
const NEW='HereIAm-iCoreSchema6-st1-study-20261103';
const NEW_SERVER='a0bd0491';

class Stop extends Error{constructor(step,detail){super(detail);this.step=step;this.detail=detail;}}
const sha=b=>createHash('sha256').update(b).digest('hex');
const short=h=>String(h).slice(0,8).toLowerCase();
function emit(step,ok,detail){console.log(JSON.stringify({step,ok,detail}));}
function need(cond,step,detail){if(!cond)throw new Stop(step,detail);}
function readJson(p,expected,step){const b=readFileSync(p);if(expected)need(sha(b)===String(expected).toLowerCase(),step,'hash_mismatch:'+path.basename(p));return JSON.parse(b.toString('utf8').replace(/^﻿/,''));}
const childEnv=()=>{const e={};for(const [k,v] of Object.entries(process.env))if(!/^(NODE_|I_CORE_|I_REMOTE_MCP_|GIT_)/i.test(k))e[k]=v;e.PSModulePath=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','Modules');return e;};
const PS=()=>path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');
const PSARGS=['-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass'];
const HEAD51="$ErrorActionPreference='Stop'\nif($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'host_not_51'}\n$q=[Console]::In.ReadToEnd()|ConvertFrom-Json\n";
function ps51(script,input,step,timeoutMin=5){
 const r=spawnSync(PS(),[...PSARGS,'-EncodedCommand',Buffer.from(HEAD51+script,'utf16le').toString('base64')],{input:JSON.stringify(input??{}),env:childEnv(),encoding:'utf8',windowsHide:true,maxBuffer:64*1024*1024,timeout:timeoutMin*60*1000});
 if(r.error)throw new Stop(step,'spawn_failed:'+r.error.code);
 return {code:r.status,stdout:r.stdout??'',stderr:r.stderr??''};
}
const rows=t=>t.split(/\r?\n/).filter(Boolean).map(l=>{try{return JSON.parse(l);}catch{return null;}}).filter(Boolean);
const lastErr=r=>(r.stderr.trim().split(/\r?\n/).filter(Boolean).pop()??'').slice(0,240);
function value(script,input,step){const r=ps51(script,input,step);need(r.code===0,step,'powershell_exit_'+r.code+':'+lastErr(r));return JSON.parse(r.stdout.trim().split(/\r?\n/).filter(Boolean).pop());}
const asList=v=>Array.isArray(v)?v:[v];

const TASKS_PS="ConvertTo-Json -InputObject @(Get-ScheduledTask|Where-Object{$_.TaskName -like 'HereIAm-iCoreSchema6-*'}|ForEach-Object{$i=Get-ScheduledTaskInfo -TaskName $_.TaskName -TaskPath $_.TaskPath;[pscustomobject]@{name=$_.TaskName;state=[string]$_.State;last='0x'+([uint32]$i.LastTaskResult).ToString('X8');arguments=[string]$_.Actions[0].Arguments}}) -Compress -Depth 3";
const tasks=step=>asList(value(TASKS_PS,{},step));
function loginOf(task,step){
 const tok=[...task.arguments.matchAll(/"([^"]*)"|(\S+)/g)].map(m=>m[1]??m[2]);
 const arg=re=>{const i=tok.map((t,j)=>re.test(t)?j:-1).filter(j=>j>=0);need(i.length===1&&i[0]+1<tok.length,step,'login_argument_ambiguous');return tok[i[0]+1];};
 const p=arg(/^-(Login)?ConfigurationPath$/i),h=arg(/^-(Login)?ConfigurationSha256$/i).toLowerCase();
 const login=readJson(p,h,step);need(login.format==='schema6-login-v1',step,'login_format');return {path:p,sha256:h,login};
}
const serverOf=l=>short(readJson(l.login.mcp_configuration_path,l.login.mcp_configuration_sha256,'mcp').source_files.find(f=>f.path==='i_remote_mcp/server.mjs')?.sha256);

// One PS 5.1 child dot-sources the round 1 copy of switch-login-task.ps1 (import-safe)
// and drives the same functions the tool uses, in the same order.
const SWITCH_PS=String.raw`. $q.switch
function Test-Latch($b){Test-Path -LiteralPath (Join-Path $b.Login.state_directory 's6-recovery-pending.json')}
function Test-TaskActive([string]$n){(Invoke-Schema6TaskOperation -Operation State -TaskName $n) -in @(2,4)}
function Assert-NotLive($b,[string]$what){$s=@(Get-Schema6LiveSessions $b);try{if($s.Count -ne 0){throw ($what+'_session_still_live')}}finally{foreach($x in $s){$x.Lease.Dispose()}}}
function Wait-LatchClear($b,[string]$n,[int]$sec){
 $w=[Diagnostics.Stopwatch]::StartNew()
 while(Test-Latch $b){if($w.Elapsed.TotalSeconds -ge $sec){throw 'recovery_latch_not_cleared'};if(-not (Test-TaskActive $n)){throw 'task_stopped_during_recovery'};Start-Sleep -Seconds 3}
}
# Same readiness checks as the tool; a recovery latch seen at any point means wait, not fail.
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
 # Continue only when the old host is really gone; otherwise nothing has changed.
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
# Fallback: never stop a Core mid-recovery; let it finish first.
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

function main(){
 need(process.argv.length===2,'args','no_arguments');
 need(process.platform==='win32'&&/^v24\./.test(process.version),'args','windows_node24_required');
 // r0. Must match round 4's read-only check.
 const list=tasks('r0');
 const act=list.find(t=>t.name===ACTIVE),nw=list.find(t=>t.name===NEW);
 need(act&&nw,'r0','tasks_missing');
 emit('r0.task',true,{old:act.state,new:nw.state});
 need(act.state==='Running','r0','old_not_running:'+act.state);
 need(nw.state==='Disabled','r0','new_not_disabled:'+nw.state);
 need(list.every(t=>[ACTIVE,NEW].includes(t.name)||t.state==='Disabled'),'r0','other_task_enabled');
 const live=loginOf(act,'r0'),next=loginOf(nw,'r0');
 need(serverOf(next)===NEW_SERVER,'r0','new_mcp_not_candidate');
 need(!existsSync(path.join(live.login.state_directory,'s6-recovery-pending.json')),'r0','recovery_latch_present');
 const mcp=readJson(live.login.mcp_configuration_path,live.login.mcp_configuration_sha256,'r0');
 const OUT=path.dirname(path.dirname(mcp.working_directory));
 const sw=path.join(OUT,'tools-4603fb79','tools','i_core','maintenance','switch-login-task.ps1');
 need(existsSync(sw),'r0','tools_copy_missing');
 emit('r0',true,{old_server:serverOf(live),new_server:NEW_SERVER,latch:'absent'});

 // r1. Switch (or fall back) in one PS 5.1 child; relay its rows.
 const t0=Date.now(),r=ps51(SWITCH_PS,{switch:sw,from:ACTIVE,to:NEW},'r1',18);
 for(const row of rows(r.stdout))if(row.step!==undefined)emit('r1:'+row.step,row.ok!==false,typeof row.detail==='string'?row.detail.slice(0,240):row.detail);
 if(![0,10,12,13].includes(r.code))emit('r1',false,'powershell_exit_'+r.code+':'+lastErr(r));

 // r2. Final task states, whatever happened.
 const after=tasks('r2'),running=after.filter(t=>t.state==='Running').map(t=>t.name);
 emit('r2.tasks',true,after.filter(t=>[ACTIVE,NEW].includes(t.name)).map(t=>({name:t.name,state:t.state})));
 const seconds=Math.round((Date.now()-t0)/1000);
 if(r.code===0){
  const cur=after.find(t=>t.name===NEW);
  need(cur?.state==='Running'&&serverOf(loginOf(cur,'r2'))===NEW_SERVER,'r2','new_not_running_candidate');
  need(after.every(t=>t.name===NEW||t.state==='Disabled'),'r2','final_task_states');
  emit('done',true,{running:NEW,old_task:'Disabled',server:NEW_SERVER,seconds});return;
 }
 throw new Stop('done',(r.code===10?'switch_failed_old_restored':r.code===13?'not_started_old_untouched':'manual_review_required')+';running='+(running.join(',')||'none')+';seconds='+seconds);
}
try{main();}catch(e){emit(e.step??'unexpected',false,e.detail??String(e.message).slice(0,300));process.exitCode=1;}
