// ST1 rollout, resume after round 1 stopped at switch.stop_old (old host exit code not 0).
// r0 read-only task state; r1 retry switch-login-task; r2 if nothing runs, restart the old task.
// Output: one JSON row per step; no tokens, paths, SIDs or study content.
// Usage: st1-resume.ps1 (Windows PowerShell 5.1, -File) runs this with --git <git.exe>.
import {createHash,randomBytes} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {copyFileSync,existsSync,lstatSync,mkdirSync,readFileSync,readdirSync,realpathSync,statSync,writeFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';

const ACTIVE='HereIAm-iCoreSchema6-n2-food-20261031';
const NEW='HereIAm-iCoreSchema6-st1-study-20261103';
const ST1_MERGE='31332b5669228bf443b299d422e35554f13dbceb';
const OLD_SERVER='f42f291f';
const MCP_EXPECTED={'i_remote_mcp/server.mjs':'a0bd0491','i_remote_mcp/oauth.mjs':'e2c88aca','i_remote_mcp/diagnostics.mjs':'5303ef6d',
 'i_remote_mcp/mcp.mjs':'0ae610bf','i_remote_mcp/writeback.mjs':'a7a6f95d','i_memory/i_memory_read.mjs':'cee18518'};
// Maintenance tools: the N2 copy was built at V. Since then only this file changed on v3-lab.
const V='fb401d459e3ae56233558ba138ae0d7ec7c07c08';
const TOOLS_CHANGED=['tools/i_core/maintenance/stop-schema6-session.ps1'];
const TOOLS_FILES=321;
const REPO=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..','..','..');

class Stop extends Error{constructor(step,detail){super(detail);this.step=step;this.detail=detail;}}
const sha=b=>createHash('sha256').update(b).digest('hex');
const blobSha=b=>createHash('sha1').update(Buffer.concat([Buffer.from('blob '+b.length+'\0'),b])).digest('hex');
function files(root){const out=[];const go=d=>{for(const e of readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);if(e.isDirectory())go(p);else out.push(p);}};go(root);return out;}
const fileSha=p=>sha(readFileSync(p));
const short=h=>String(h).slice(0,8).toLowerCase();
function emit(step,ok,detail){console.log(JSON.stringify({step,ok,detail}));}
function need(cond,step,detail){if(!cond)throw new Stop(step,detail);}
function plain(p){return typeof p==='string'&&path.win32.isAbsolute(p)&&path.win32.normalize(p)===p&&p.indexOf(':',2)<0&&!p.endsWith('\\')&&!p.startsWith('\\\\');}
function readJson(p,expected,step){const b=readFileSync(p);if(expected)need(sha(b)===String(expected).toLowerCase(),step,'hash_mismatch:'+path.basename(p));return JSON.parse(b.toString('utf8').replace(/^﻿/,''));}
const childEnv=()=>{const e={};for(const [k,v] of Object.entries(process.env))if(!/^(NODE_|I_CORE_|I_REMOTE_MCP_|GIT_)/i.test(k)&&!['OPENSSL_CONF','SSL_CERT_FILE','SSL_CERT_DIR'].includes(k.toUpperCase()))e[k]=v;e.PSModulePath=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','Modules');return e;};
function run(file,args,{cwd,input,step,env}={}){
 const r=spawnSync(file,args,{cwd,input,env:env??childEnv(),encoding:'utf8',windowsHide:true,maxBuffer:64*1024*1024,timeout:30*60*1000});
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
function psFile(script,args,step){return run(PS(),[...PSARGS,'-File',script,...args],{step});}
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
// Copy the DACL (only) of each source directory onto its target, protected.
const ACL_PS="$o=@()\nforeach($p in $q.pairs){$a=(Get-Item -LiteralPath $p.from).GetAccessControl('Access');$a.SetAccessRuleProtection($true,$true);(Get-Item -LiteralPath $p.to).SetAccessControl($a);$v=(Get-Item -LiteralPath $p.to).GetAccessControl('Access');$o+=[pscustomobject]@{dir=$p.rel;protected=$v.AreAccessRulesProtected;rules=@($v.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])).Count}}\nConvertTo-Json -InputObject $o -Compress";
const CHECK_ACL_PS="$o=@()\nforeach($p in $q.dirs){$v=(Get-Item -LiteralPath $p.path).GetAccessControl('Access');$o+=[pscustomobject]@{dir=$p.rel;protected=$v.AreAccessRulesProtected;rules=@($v.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])).Count}}\nConvertTo-Json -InputObject $o -Compress";
const asList=v=>Array.isArray(v)?v:[v];
function realEntry(p,kind,step){
 let s;try{s=lstatSync(p);}catch{throw new Stop(step,'study_missing:'+path.basename(p));}
 need(!s.isSymbolicLink(),step,'study_link:'+path.basename(p));
 need(kind==='dir'?s.isDirectory():s.isFile(),step,'study_kind:'+path.basename(p));
}


function main(){
 const a=process.argv.slice(2);need(a.length===2&&a[0]==='--git','args','usage: --git <git.exe>');
 need(process.platform==='win32','args','windows_required');
 need(/^v24\./.test(process.version)&&plain(process.execPath),'args','node24_required');
 const G=a[1];need(plain(G)&&existsSync(G)&&statSync(G).isFile(),'args','git_path_required');
 const git=(args,step)=>{const r=run(G,['-C',REPO,...args],{step});need(r.code===0,step,'git_failed:'+args[0]);return r.stdout;};
 const HEAD=git(['rev-parse','HEAD'],'r0').trim();

 // r0. Read-only state after round 1 stopped at switch.stop_old.
 const info=ps51("ConvertTo-Json -InputObject @(Get-ScheduledTask|Where-Object{$_.TaskName -like 'HereIAm-iCoreSchema6-*'}|ForEach-Object{$i=Get-ScheduledTaskInfo -TaskName $_.TaskName -TaskPath $_.TaskPath;[pscustomobject]@{name=$_.TaskName;state=[string]$_.State;last='0x'+([uint32]$i.LastTaskResult).ToString('X8');at=$(if($i.LastRunTime){$i.LastRunTime.ToUniversalTime().ToString('o')}else{''})}}) -Compress -Depth 3",{},'r0');
 const list=asList(info);
 for(const t of list.filter(t=>[ACTIVE,NEW].includes(t.name)))emit('r0.task',true,t);
 const act=list.find(t=>t.name===ACTIVE),nw=list.find(t=>t.name===NEW);
 need(act&&nw,'r0','tasks_missing');
 need(list.every(t=>[ACTIVE,NEW].includes(t.name)||t.state==='Disabled'),'r0','other_task_enabled');
 const before=tasks('r0');
 const live=loginOf(before.find(t=>t.name===ACTIVE),'r0'),mcp=readJson(live.login.mcp_configuration_path,live.login.mcp_configuration_sha256,'r0');
 const OUT=path.dirname(path.dirname(mcp.working_directory)),MT=path.join(OUT,'tools-'+HEAD.slice(0,8),'tools','i_core','maintenance');
 need(existsSync(path.join(MT,'switch-login-task.ps1')),'r0','tools_copy_missing');
 if(nw.state==='Running'){emit('done',true,{running:NEW,note:'already_running'});return;}
 need(nw.state==='Disabled','r0','new_task_state:'+nw.state);

 // r1. Retry the switch. With the old host gone, stop reports already_stopped after
 // checking closed files, then the tool disables old, enables and starts new (rollback allowed).
 const sw=path.join(MT,'switch-login-task.ps1'),t0=Date.now();
 let r=psFile(sw,['-FromTask',ACTIVE,'-ToTask',NEW,'-ReadyTimeoutSeconds','180'],'r1');relay('r1',r);
 let after=tasks('r2'),cur=after.find(t=>t.name===NEW);
 if(r.code===0&&cur?.state==='Running'){
  const next=loginOf(cur,'r2'),mcp2=readJson(next.login.mcp_configuration_path,next.login.mcp_configuration_sha256,'r2');
  need(short(mcp2.source_files.find(f=>f.path==='i_remote_mcp/server.mjs')?.sha256)===MCP_EXPECTED['i_remote_mcp/server.mjs'],'r2','new_mcp_not_candidate');
  need(after.every(t=>t.name===NEW||t.state==='Disabled'),'r2','final_task_states');
  emit('done',true,{running:NEW,old_task:'Disabled',server:MCP_EXPECTED['i_remote_mcp/server.mjs'],seconds:Math.round((Date.now()-t0)/1000)});
  return;
 }
 emit('r1',false,'switch:'+r.code+':'+firstErr(r));
 // r2. Fallback: bring the service back on whichever task the switch left, preferring the old one.
 after=tasks('r2');
 if(after.some(t=>t.state==='Running')){emit('r2',true,{running:after.filter(t=>t.state==='Running').map(t=>t.name)});throw new Stop('r2','switch_failed_service_running');}
 const START_PS=". $q.switch\n$b=Get-Schema6LoginBinding $q.task\n$prev=@(Get-Schema6SessionDirectories $b)\nInvoke-Schema6TaskOperation -Operation Disable -TaskName $q.other\nInvoke-Schema6TaskOperation -Operation Enable -TaskName $q.task\nInvoke-Schema6TaskOperation -Operation Start -TaskName $q.task\nWait-Schema6LoginReady -Name $q.task -Binding $b -PreviousSessions $prev -TimeoutSeconds 180 -HealthUrl ''\n[pscustomobject]@{ready=$true}|ConvertTo-Json -Compress";
 try{ps51(START_PS,{switch:sw,task:ACTIVE,other:NEW},'r2');emit('r2',true,{restarted:ACTIVE});}
 catch(x){emit('r2',false,x.detail??String(x.message).slice(0,240));}
 throw new Stop('r2','switch_failed');
}
try{main();}catch(e){emit(e.step??'unexpected',false,e.detail??String(e.message).slice(0,300));process.exitCode=1;}
