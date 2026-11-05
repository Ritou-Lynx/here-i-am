// ST1 rollout, read-only inspection after rounds 1-3. Changes nothing.
// Reports task states, the recovery latch, lifecycle marker, custody recovery events,
// leftover recovery stages/sidecars and the newest session exit receipts.
// Output: one JSON row per item; booleans, enums, counts and UTC times only.
// Usage: st1-inspect.ps1 (Windows PowerShell 5.1, -File).
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {existsSync,readFileSync,readdirSync,statSync} from 'node:fs';
import path from 'node:path';

const OLD='HereIAm-iCoreSchema6-n2-food-20261031';
const NEW='HereIAm-iCoreSchema6-st1-study-20261103';
const sha=b=>createHash('sha256').update(b).digest('hex');
const short=h=>String(h).slice(0,8).toLowerCase();
const emit=(step,ok,detail)=>console.log(JSON.stringify({step,ok,detail}));
const iso=ms=>Number.isFinite(ms)?new Date(ms).toISOString():null;
function json(p){try{return JSON.parse(readFileSync(p,'utf8').replace(/^﻿/,''));}catch{return null;}}
// Keep only scalar fields that cannot carry paths, tokens or content.
function scalars(o,keys){const out={};if(!o)return null;for(const k of keys)if(Object.hasOwn(o,k)){const v=o[k];out[k]=typeof v==='boolean'||typeof v==='number'||v===null?v:typeof v==='string'&&/^[A-Za-z0-9_.:-]{0,64}$/.test(v)?v:'<omitted>';}return out;}
const PS=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');
function ps(script){
 const body="$ErrorActionPreference='Stop'\n"+script;
 const r=spawnSync(PS,['-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',Buffer.from(body,'utf16le').toString('base64')],{encoding:'utf8',windowsHide:true,maxBuffer:16*1024*1024});
 if(r.status!==0)throw new Error('powershell_exit_'+r.status);
 return JSON.parse(r.stdout.trim().split(/\r?\n/).filter(Boolean).pop());
}
function loginOf(args){
 const tok=[...String(args).matchAll(/"([^"]*)"|(\S+)/g)].map(m=>m[1]??m[2]);
 const at=re=>{const i=tok.findIndex(t=>re.test(t));return i>=0?tok[i+1]:null;};
 const p=at(/^-(Login)?ConfigurationPath$/i),h=at(/^-(Login)?ConfigurationSha256$/i);
 if(!p||!existsSync(p))return null;const b=readFileSync(p);
 return {hash_ok:sha(b)===String(h).toLowerCase(),login:JSON.parse(b.toString('utf8').replace(/^﻿/,''))};
}
function step(name,body){try{body();}catch(e){emit(name,false,String(e.message).slice(0,200));}}

const tasks=(()=>{const t=ps("ConvertTo-Json -InputObject @(Get-ScheduledTask|Where-Object{$_.TaskName -like 'HereIAm-iCoreSchema6-*'}|ForEach-Object{$i=Get-ScheduledTaskInfo -TaskName $_.TaskName -TaskPath $_.TaskPath;[pscustomobject]@{name=$_.TaskName;state=[string]$_.State;last='0x'+([uint32]$i.LastTaskResult).ToString('X8');at=$(if($i.LastRunTime){$i.LastRunTime.ToUniversalTime().ToString('o')}else{''});arguments=[string]$_.Actions[0].Arguments}}) -Compress -Depth 3");return Array.isArray(t)?t:[t];})();
for(const t of tasks)if([OLD,NEW].includes(t.name)||t.state!=='Disabled')emit('task',true,{name:t.name,state:t.state,last:t.last,at:t.at});
emit('task.others_disabled',tasks.every(t=>[OLD,NEW].includes(t.name)||t.state==='Disabled'),tasks.length);

let login=null,mcpOld=null;
step('mcp',()=>{
 for(const name of [OLD,NEW]){
  const t=tasks.find(x=>x.name===name);if(!t){emit('mcp',false,{task:name,missing:true});continue;}
  const l=loginOf(t.arguments);if(!l){emit('mcp',false,{task:name,login:'missing'});continue;}
  const m=json(l.login.mcp_configuration_path),server=m?.source_files?.find(f=>f.path==='i_remote_mcp/server.mjs');
  if(name===OLD){login=l.login;mcpOld=m;}
  emit('mcp',true,{task:name,login_hash_ok:l.hash_ok,server:short(server?.sha256),candidate:path.basename(path.dirname(m?.working_directory??''))});
 }
});
if(!login){emit('done',false,'old_login_unreadable');process.exit(1);}
const state=login.state_directory;
step('state',()=>{
 const latch=path.join(state,'s6-recovery-pending.json');
 emit('state.recovery_pending',!existsSync(latch),existsSync(latch)?scalars(json(latch),['format','kind','commitStarted','startedAtMs']):'absent');
 const marker=json(path.join(state,'s6-lifecycle.json'));
 const lc=path.join(state,'s6-lifecycle.json');
 emit('state.lifecycle',!!marker,{...scalars(marker,['format','phase']),manifest:short(marker?.manifest_sha256),updated:existsSync(lc)?iso(statSync(lc).mtimeMs):null});
 const names=readdirSync(state);
 emit('state.sidecars',true,names.filter(n=>/-(wal|shm|journal)$/.test(n)));
 emit('state.recovery_stages',true,names.filter(n=>/^s6-copy-/.test(n)).length);
 const mstate=mcpOld?.environment?.I_REMOTE_MCP_STATE_DIR;
 emit('state.study_json',!!mstate&&existsSync(path.join(mstate,'study.json')),mstate?'checked':'mcp_state_dir_unknown');
});
step('custody',()=>{
 const core=json(login.core_configuration_path),dir=core?.recovery_custody_directory;
 if(!dir||!existsSync(dir)){emit('custody',false,'directory_missing');return;}
 const ev=readdirSync(dir).filter(n=>n.endsWith('.recovery.json')).map(n=>json(path.join(dir,n))).filter(Boolean).sort((a,b)=>(b.recoveredAtMs??0)-(a.recoveredAtMs??0));
 emit('custody.recovery_events',true,{count:ev.length,newest:ev.slice(0,3).map(e=>({kind:e.kind,at:iso(e.recoveredAtMs)}))});
 const head=json(path.join(dir,'current-head.json'));
 emit('custody.head',!!head,{updated:existsSync(path.join(dir,'current-head.json'))?iso(statSync(path.join(dir,'current-head.json')).mtimeMs):null});
});
step('sessions',()=>{
 const root=login.control_root;
 const dirs=readdirSync(root,{withFileTypes:true}).filter(d=>d.isDirectory()&&d.name.startsWith('session-')).map(d=>path.join(root,d.name)).sort((a,b)=>statSync(b).mtimeMs-statSync(a).mtimeMs).slice(0,4);
 for(const d of dirs){
  const exit=json(path.join(d,'session-exit.json'));
  const controls=readdirSync(d,{withFileTypes:true}).filter(x=>x.isDirectory()&&x.name.startsWith('control-')).map(x=>path.join(d,x.name)).sort((a,b)=>statSync(b).mtimeMs-statSync(a).mtimeMs);
  const c=controls[0],child=c?json(path.join(c,'child.json')):null,sup=c?json(path.join(c,'supervisor.json')):null;
  emit('session',true,{modified:iso(statSync(d).mtimeMs),manifest:short(json(path.join(d,'session-window.json'))?.manifest_sha256),
   exit:scalars(exit,['clean_closed','forced_timeout','termination_requested','mcp_failure','core_job_empty_confirmed','mcp_job_empty_confirmed']),
   over_budget:existsSync(path.join(d,'session-exit-over-budget.json')),controls:controls.length,
   child:scalars(child,['phase','reason','error_code','store_close_confirmed','listener_closed_confirmed']),
   supervisor:scalars(sup?.result,['child_exit_code','guardian_exit_code','termination_requested']),
   mcp_start:c?existsSync(path.join(c,'mcp-start.json')):null,mcp_stop:c?existsSync(path.join(c,'mcp-stop.json')):null});
 }
});
emit('done',true,'read_only');
