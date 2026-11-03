// ST1 rollout: switch the live MCP to the study-tools candidate (service goes down briefly).
// Core is not changed. Order follows the D2b MCP-only update:
//   0  read-only preflight (live task, candidate, study directory, maintenance diff)
//   1  maintenance tools copy (previous copy + the one file changed since)
//   2  build the six-file candidate from this checkout, copy it out with protected ACLs
//   3  write <MCP state>/study.json (new file only) and read-check it with the candidate
//   4  update-mcp-source: register the new task disabled
//   5  switch-login-task (rollback allowed), then final checks
// Output: one JSON row per step; no tokens, paths, SIDs or study content.
//
// Usage: st1-deploy.ps1 (Windows PowerShell 5.1, -File) runs this with --git <git.exe>.
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

 // 0. Preflight: read-only.
 const before=tasks('step0');
 const active=before.filter(t=>t.name===ACTIVE);need(active.length===1&&active[0].state==='Running','step0','active_task_not_running');
 need(before.every(t=>t.name===ACTIVE||t.state==='Disabled'),'step0','other_task_enabled');
 need(!before.some(t=>t.name===NEW),'step0','target_task_exists');
 const live=loginOf(active[0],'step0'),login=live.login;
 const mcp=readJson(login.mcp_configuration_path,login.mcp_configuration_sha256,'step0');
 const oldCand=path.dirname(mcp.working_directory),OUT=path.dirname(oldCand);
 need(path.basename(mcp.working_directory)==='runtime'&&/^mcp-candidate-/.test(path.basename(oldCand))&&plain(OUT),'step0','live_candidate_layout');
 const liveServer=mcp.source_files?.find(f=>f.path==='i_remote_mcp/server.mjs');
 need(short(liveServer?.sha256)===OLD_SERVER&&short(fileSha(path.join(mcp.working_directory,'i_remote_mcp','server.mjs')))===OLD_SERVER,'step0','live_server_not_n2b');
 const stateMcp=mcp.environment?.I_REMOTE_MCP_STATE_DIR;
 need(plain(stateMcp)&&existsSync(stateMcp)&&statSync(stateMcp).isDirectory(),'step0','mcp_state_dir');
 const studyDir=path.join(process.env.USERPROFILE??'','feishu-study');
 need(plain(studyDir),'step0','study_dir_path');
 realEntry(studyDir,'dir','step0');
 need(realpathSync.native(studyDir).toLowerCase()===studyDir.toLowerCase(),'step0','study_dir_alias');
 for(const [rel,kind] of [['today.md','file'],['state','dir'],[path.join('state','ledger.json'),'file'],[path.join('state','sources.json'),'file'],['inbox','dir']])
  realEntry(path.join(studyDir,rel),kind,'step0');
 const studyJson=path.join(stateMcp,'study.json'),studyText=JSON.stringify({format:'study-v1',study_dir:studyDir})+'\n';
 const studyExists=existsSync(studyJson);
 need(!studyExists||readFileSync(studyJson,'utf8')===studyText,'step0','study_json_differs');
 const HEAD=git(['rev-parse','HEAD'],'step0').trim();
 need(run(G,['-C',REPO,'merge-base','--is-ancestor',ST1_MERGE,HEAD],{step:'step0'}).code===0,'step0','st1_not_in_checkout');
 need(git(['status','--porcelain','--untracked-files=no'],'step0').trim()==='','step0','checkout_dirty');
 const changed=git(['diff','--name-only',V,HEAD,'--','tools/i_core'],'step0').split(/\r?\n/).filter(Boolean).sort();
 need(JSON.stringify(changed)===JSON.stringify([...TOOLS_CHANGED].sort()),'step0','tools_diff:'+changed.join(','));
 const OLDT=path.join(OUT,'tools-'+V.slice(0,8)),TOOLS=path.join(OUT,'tools-'+HEAD.slice(0,8)),MT=path.join(TOOLS,'tools','i_core','maintenance');
 need(existsSync(path.join(OLDT,'tools','i_core','maintenance','switch-login-task.ps1')),'step0','old_tools_missing');
 const CAND=path.join(OUT,'mcp-candidate-'+HEAD.slice(0,8)),SETTINGS=path.join(OUT,'st1-mcp-settings-'+HEAD.slice(0,8));
 need(!existsSync(SETTINGS),'step0','settings_dir_exists');
 emit('step0',true,{active:'Running',login:short(live.sha256),live_server:OLD_SERVER,head:short(HEAD),study_json:studyExists?'present_same':'absent'});

 // 1. Maintenance tools copy (outside production; reused if an earlier run built it).
 const blobs=new Map(git(['ls-tree','-r',HEAD,'--',...TOOLS_CHANGED],'step1').split(/\r?\n/).filter(Boolean).map(l=>{const m=l.match(/^100644 blob ([0-9a-f]{40})\t(.+)$/);need(m,'step1','ls_tree');return [m[2],m[1]];}));
 need(blobs.size===TOOLS_CHANGED.length,'step1','ls_tree_count');
 const oldFiles=files(OLDT);need(oldFiles.length===TOOLS_FILES,'step1','old_tools_count:'+oldFiles.length);
 if(!existsSync(TOOLS)){
  mkdirSync(TOOLS);
  const acl=asList(ps51(ACL_PS,{pairs:[{rel:'.',from:OLDT,to:TOOLS}]},'step1'));
  need(acl[0]?.protected===true&&acl[0].rules>0,'step1','tools_acl');
  for(const p of oldFiles){const rel=path.relative(OLDT,p),dst=path.join(TOOLS,rel);mkdirSync(path.dirname(dst),{recursive:true});
   const repo=rel.split(path.sep).join('/');
   if(blobs.has(repo)){const r=spawnSync(G,['-C',REPO,'cat-file','blob',blobs.get(repo)],{env:childEnv(),windowsHide:true,maxBuffer:16*1024*1024});need(r.status===0,'step1','cat_file');writeFileSync(dst,r.stdout,{flag:'wx'});}
   else copyFileSync(p,dst);}
 }
 const newFiles=files(TOOLS);need(newFiles.length===TOOLS_FILES,'step1','new_tools_count:'+newFiles.length);
 for(const p of newFiles){const rel=path.relative(TOOLS,p),repo=rel.split(path.sep).join('/');
  if(blobs.has(repo))need(blobSha(readFileSync(p))===blobs.get(repo),'step1','tools_blob:'+path.basename(p));
  else need(existsSync(path.join(OLDT,rel))&&fileSha(p)===fileSha(path.join(OLDT,rel)),'step1','tools_copy:'+rel);}
 emit('step1',true,{tools:'tools-'+HEAD.slice(0,8),files:TOOLS_FILES,changed:TOOLS_CHANGED.map(n=>path.basename(n))});

 // 2. Six-file candidate, built from this checkout, copied out byte for byte.
 const dirs=['','runtime',path.join('runtime','i_remote_mcp'),path.join('runtime','i_memory')];
 const buildRel='build/st1-candidate-'+randomBytes(4).toString('hex'),build=path.join(REPO,...buildRel.split('/'));
 let r=run(process.execPath,[path.join(REPO,'tools','i_remote_mcp','chatgpt_candidate.mjs'),'--out',buildRel],{cwd:REPO,step:'step2'});
 need(r.code===0,'step2','candidate_build_failed:'+r.stderr.trim().slice(0,240));
 const cm=readJson(path.join(build,'manifest.json'),null,'step2');
 need(cm.changed_files===5&&cm.source_commit===HEAD&&cm.files.length===6,'step2','candidate_manifest');
 for(const f of cm.files)need(MCP_EXPECTED[f.path]===short(f.result_sha256),'step2','candidate_hash:'+f.path+':'+short(f.result_sha256));
 const built=files(build).map(p=>path.relative(build,p)).sort();
 if(!existsSync(CAND)){
  for(const d of dirs){need(existsSync(path.join(oldCand,d)),'step2','old_candidate_dir_missing:'+(d||'.'));mkdirSync(path.join(CAND,d),{recursive:true});}
  const acl=asList(ps51(ACL_PS,{pairs:dirs.map(d=>({rel:d||'.',from:d?path.join(oldCand,d):oldCand,to:d?path.join(CAND,d):CAND}))},'step2'));
  for(const x of acl)need(x.protected===true&&x.rules>0,'step2','candidate_acl:'+x.dir);
  for(const rel of built)copyFileSync(path.join(build,rel),path.join(CAND,rel));
 }
 need(JSON.stringify(files(CAND).map(p=>path.relative(CAND,p)).sort())===JSON.stringify(built),'step2','candidate_inventory');
 for(const rel of built)need(fileSha(path.join(CAND,rel))===fileSha(path.join(build,rel)),'step2','copy_mismatch:'+rel);
 const acl=asList(ps51(CHECK_ACL_PS,{dirs:dirs.map(d=>({rel:d||'.',path:d?path.join(CAND,d):CAND}))},'step2'));
 need(acl.length===dirs.length&&acl.every(x=>x.protected===true&&x.rules>0),'step2','candidate_acl_check');
 emit('step2',true,{candidate:'mcp-candidate-'+HEAD.slice(0,8),server:short(cm.files.find(f=>f.path==='i_remote_mcp/server.mjs').result_sha256),acl:acl.map(x=>x.dir+':'+x.protected)});

 // 3. study.json (new file only) and a read-only check through the candidate's own loader.
 if(!studyExists)writeFileSync(studyJson,studyText,{flag:'wx'});
 const probe="import {pathToFileURL} from 'node:url';let t='';process.stdin.on('data',d=>t+=d).on('end',async()=>{const q=JSON.parse(t);const m=await import(pathToFileURL(q.server).href);"+
  "const c=m.loadStudyConfig(q.state);const s=m.createStudyTools({studyDir:c.study_dir,frontend:'chatgpt_web'}).handlers;"+
  "const today=await s.study_today({}),progress=await s.study_progress({}),sources=await s.study_source({});"+
  "console.log(JSON.stringify({loaded:true,sheet_date:today.date,is_today:today.is_today,subjects:today.subjects.length,progress_subjects:progress.subjects.length,sources:sources.sources.length}));});";
 r=run(process.execPath,['--disable-warning=ExperimentalWarning','--input-type=module','-e',probe],{step:'step3',input:JSON.stringify({server:path.join(CAND,'runtime','i_remote_mcp','server.mjs'),state:stateMcp})});
 const pr=lines(r.stdout).pop();need(r.code===0&&pr?.loaded===true,'step3','study_probe:'+(firstErr(r)||r.code));
 emit('step3',true,{study_json:studyExists?'kept':'written',sheet_date:pr.sheet_date,is_today:pr.is_today,subjects:pr.subjects,progress_subjects:pr.progress_subjects,sources:pr.sources});

 // 4. New task, registered disabled.
 const c1=['--from-task',ACTIVE,'--candidate',CAND,'--out',SETTINGS,'--new-task',NEW];
 r=run(process.execPath,[path.join(MT,'update-mcp-source.mjs'),...c1,'--dry-run'],{step:'step4'});
 const dry=lines(r.stdout).find(x=>x.step==='update.result');
 need(r.code===0&&dry?.detail==='dry_run_passed','step4','c1_dry_run:'+(lines(r.stdout).find(x=>x.ok===false)?.detail??r.code));
 need(JSON.stringify(dry.result?.diff)===JSON.stringify({mcp:['source_files','working_directory'],backup:['specTemplate.entries'],login:['backup_configuration_path','backup_configuration_sha256','mcp_configuration_path','mcp_configuration_sha256']}),'step4','c1_field_diff:'+JSON.stringify(dry.result?.diff));
 r=run(process.execPath,[path.join(MT,'update-mcp-source.mjs'),...c1],{step:'step4'});
 need(r.code===0&&lines(r.stdout).find(x=>x.step==='update.result')?.detail==='registered_disabled','step4','c1:'+(lines(r.stdout).find(x=>x.ok===false)?.detail??r.code));
 emit('step4',true,{task:NEW,registered:'disabled'});

 // 5. Switch (the maintenance tool restores the old task if the new one does not get ready).
 const sw=path.join(MT,'switch-login-task.ps1'),t0=Date.now();
 r=psFile(sw,['-FromTask',ACTIVE,'-ToTask',NEW,'-DryRun'],'step5');relay('step5',r);need(r.code===0,'step5','switch_dry_run:'+r.code+':'+firstErr(r));
 r=psFile(sw,['-FromTask',ACTIVE,'-ToTask',NEW,'-ReadyTimeoutSeconds','180'],'step5');relay('step5',r);need(r.code===0,'step5','switch:'+r.code+':'+firstErr(r));
 emit('step5',true,{running:NEW,downtime_seconds:Math.round((Date.now()-t0)/1000)});

 const after=tasks('done');
 need(after.find(t=>t.name===NEW)?.state==='Running'&&after.every(t=>t.name===NEW||t.state==='Disabled'),'done','final_task_states');
 const next=loginOf(after.find(t=>t.name===NEW),'done'),mcp2=readJson(next.login.mcp_configuration_path,next.login.mcp_configuration_sha256,'done');
 need(mcp2.working_directory===path.join(CAND,'runtime')&&short(mcp2.source_files.find(f=>f.path==='i_remote_mcp/server.mjs')?.sha256)===MCP_EXPECTED['i_remote_mcp/server.mjs'],'done','new_mcp_not_candidate');
 need(mcp2.environment?.I_REMOTE_MCP_STATE_DIR===stateMcp,'done','mcp_state_dir_changed');
 emit('done',true,{running:NEW,old_task:'Disabled',server:MCP_EXPECTED['i_remote_mcp/server.mjs']});
}
try{main();}catch(e){emit(e.step??'unexpected',false,e.detail??String(e.message).slice(0,300));process.exitCode=1;}
