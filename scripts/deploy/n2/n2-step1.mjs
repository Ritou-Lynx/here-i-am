// N2 food rollout, step 1 (preparation only). Builds the new Core package, the
// N2b MCP candidate, package-switch configurations and the prepared task XML,
// then runs two zero-write checks. Never stops the session, never registers,
// starts or disables a task, never writes STATE, policy, credentials or live
// configuration. Fails closed on the first mismatch; never retries.
//
// Usage: run n2-step1.ps1 (Windows PowerShell 5.1, -File); it starts this file
// with the pinned node.exe of the live release. Optional: --git <git.exe>.
// <OUT> is derived from the live MCP candidate location; reuses
// <OUT>\worktree-42ecf688 and <OUT>\tools-42ecf688 from the earlier run.
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {copyFileSync,existsSync,mkdirSync,readFileSync,readdirSync,rmdirSync,statSync,writeFileSync,appendFileSync} from 'node:fs';
import path from 'node:path';

const S='42ecf688f61ff829f5f7bb1d5aadc2695c01436b';
const OLD_SOURCE='6a063386';
const ACTIVE='HereIAm-iCoreSchema6-d2b-mcp-20261025-129ec194';
const NEW_TASK='HereIAm-iCoreSchema6-n2-pkg-20261031';
const DRY_TASK='HereIAm-iCoreSchema6-n2-dryrun';
const PINNED_NODE='58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f';
const CHANGED=['tools/i_core/i_core_server.mjs','tools/i_core/personal_data_domains.mjs','tools/i_core/release_schema6/lifecycle/runtime_child.mjs','tools/i_core/shortcut_mail_relay.mjs'];
const MCP_EXPECTED={'i_remote_mcp/server.mjs':'f42f291f','i_remote_mcp/oauth.mjs':'e2c88aca','i_remote_mcp/diagnostics.mjs':'5303ef6d','i_remote_mcp/mcp.mjs':'0ae610bf','i_remote_mcp/writeback.mjs':'a7a6f95d','i_memory/i_memory_read.mjs':'cee18518'};
const TOOLS_FILES=321;

class Stop extends Error{constructor(step,detail){super(detail);this.step=step;this.detail=detail;}}
const sha=b=>createHash('sha256').update(b).digest('hex');
const fileSha=p=>sha(readFileSync(p));
const short=h=>String(h).slice(0,8).toLowerCase();
let report=null;
function emit(step,ok,detail){const row=JSON.stringify({step,ok,detail});console.log(row);if(report)appendFileSync(report,row+'\n');}
function need(cond,step,detail){if(!cond)throw new Stop(step,detail);}
function plain(p){return typeof p==='string'&&path.win32.isAbsolute(p)&&path.win32.normalize(p)===p&&p.indexOf(':',2)<0&&!p.endsWith('\\')&&!p.startsWith('\\\\');}
function readJson(p,expected,step){const b=readFileSync(p);if(expected)need(sha(b)===String(expected).toLowerCase(),step,'hash_mismatch:'+path.basename(p));return JSON.parse(b.toString('utf8').replace(/^﻿/,''));}

const childEnv=()=>{const e={};for(const [k,v] of Object.entries(process.env))if(!/^(NODE_|I_CORE_)/i.test(k))e[k]=v;e.PSModulePath=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','Modules');return e;};
function run(file,args,{cwd,input,step}={}){
 const r=spawnSync(file,args,{cwd,input,env:childEnv(),encoding:'utf8',windowsHide:true,maxBuffer:64*1024*1024,timeout:30*60*1000});
 if(r.error)throw new Stop(step,'spawn_failed:'+r.error.code);
 return {code:r.status,stdout:r.stdout??'',stderr:r.stderr??''};
}
const lines=t=>t.split(/\r?\n/).filter(Boolean).map(l=>{try{return JSON.parse(l);}catch{return null;}}).filter(Boolean);
const PS=()=>path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');
function ps51(script,input,step){
 const body="$ErrorActionPreference='Stop'\nif($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'host_not_51'}\n"+script;
 const r=run(PS(),['-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',Buffer.from(body,'utf16le').toString('base64')],{input:JSON.stringify(input??{}),step});
 need(r.code===0,step,'powershell_exit_'+r.code+':'+r.stderr.trim().split(/\r?\n/)[0]);
 const out=r.stdout.trim().split(/\r?\n/).filter(Boolean).pop();
 return JSON.parse(out);
}
const git=(G,wt,args,step)=>{const r=run(G,['-C',wt,...args],{step});need(r.code===0,step,'git_failed:'+args[0]);return r.stdout.trim();};
function walk(root){const out=[];const go=d=>{for(const e of readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);if(e.isDirectory())go(p);else out.push(p);}};go(root);return out;}

function main(){
 const a=process.argv.slice(2);need(a.length===0||(a.length===2&&a[0]==='--git'),'args','usage: [--git <git.exe>]');
 need(process.platform==='win32','args','windows_required');
 need(process.version==='v24.14.1'&&fileSha(process.execPath)===PINNED_NODE&&plain(process.execPath),'args','pinned_node_required');

 // 1. Preflight (task state and live configuration, read-only)
 const tasks=ps51("$r=@(Get-ScheduledTask|Where-Object{$_.TaskName -like 'HereIAm-iCoreSchema6-*'}|ForEach-Object{[pscustomobject]@{name=$_.TaskName;state=[string]$_.State;actions=@($_.Actions).Count;arguments=[string]$_.Actions[0].Arguments}})\nConvertTo-Json -InputObject $r -Compress -Depth 3",{},'step1');
 const list=Array.isArray(tasks)?tasks:[tasks];
 const active=list.filter(t=>t.name===ACTIVE);need(active.length===1&&active[0].state==='Running'&&active[0].actions===1,'step1','active_task_not_running');
 const others=list.filter(t=>t.name!==ACTIVE&&t.state!=='Disabled');need(others.length===0,'step1','other_task_enabled:'+others.map(t=>t.name).join(','));
 const tok=[...active[0].arguments.matchAll(/"([^"]*)"|(\S+)/g)].map(m=>m[1]??m[2]);
 const arg=re=>{const i=tok.map((t,j)=>re.test(t)?j:-1).filter(j=>j>=0);need(i.length===1&&i[0]+1<tok.length,'step1','login_argument_ambiguous');return tok[i[0]+1];};
 const loginPath=arg(/^-(Login)?ConfigurationPath$/i),loginSha=arg(/^-(Login)?ConfigurationSha256$/i).toLowerCase();
 const login=readJson(loginPath,loginSha,'step1');need(login.format==='schema6-login-v1','step1','login_format');
 const mcp=readJson(login.mcp_configuration_path,login.mcp_configuration_sha256,'step1');
 const backup=readJson(login.backup_configuration_path,login.backup_configuration_sha256,'step1');
 const oldCand=path.dirname(mcp.working_directory);need(path.basename(mcp.working_directory)==='runtime'&&/^mcp-candidate-/.test(path.basename(oldCand)),'step1','live_candidate_layout');
 const OUT=path.dirname(oldCand);
 const WT=path.join(OUT,'worktree-42ecf688'),TOOLS=path.join(OUT,'tools-42ecf688'),REL=path.join(OUT,'release-42ecf688'),CAND=path.join(OUT,'mcp-candidate-42ecf688'),CFG=path.join(OUT,'n2-pkg-configs'),DRY=path.join(OUT,'n2-c1-dryrun');
 need(plain(OUT)&&existsSync(WT)&&existsSync(TOOLS),'step1','out_layout:worktree_or_tools_missing');
 const pf=process.env.ProgramFiles??'';
 const gitCandidates=a.length?[a[1]]:[path.join(pf,'Git','cmd','git.exe'),path.join(pf,'Git','mingw64','bin','git.exe'),path.join(pf,'Git','bin','git.exe')];
 const G=gitCandidates.find(p=>plain(p)&&existsSync(p)&&statSync(p).nlink===1);need(G,'step1','single_link_git_not_found');
 report=path.join(OUT,'n2-step1-report.jsonl');need(!existsSync(report),'step1','report_exists_rename_old_report_first');
 git(G,WT,['fetch','origin','v3-lab'],'step1');
 need(git(G,WT,['rev-parse','HEAD'],'step1')===S,'step1','worktree_head_not_S');
 need(git(G,WT,['status','--porcelain','--untracked-files=no'],'step1')==='','step1','worktree_dirty');
 need(run(G,['-C',WT,'merge-base','--is-ancestor',S,'origin/v3-lab'],{step:'step1'}).code===0,'step1','S_not_ancestor');
 const pkgMod=JSON.parse(run(process.execPath,['--input-type=module','-e',"import('./tools/i_core/release_schema6/package.mjs').then(m=>console.log(JSON.stringify(m.INVENTORY)))"],{cwd:WT,step:'step1'}).stdout.trim());
 const inv=pkgMod.filter(x=>x!=='runtime/node.exe');need(inv.length===47,'step1','inventory_size:'+inv.length);
 const diff=git(G,WT,['diff','--name-only',OLD_SOURCE,S,'--',...inv],'step1').split(/\r?\n/).filter(Boolean).sort();
 need(JSON.stringify(diff)===JSON.stringify([...CHANGED].sort()),'step1','inventory_diff:'+diff.join(','));
 const pending=walk(login.control_root).filter(p=>/^(pair|food)\.request$/i.test(path.basename(p)));need(pending.length===0,'step1','pending_request_present');
 emit('step1',true,{git:path.basename(path.dirname(G))+'\\git.exe',S:short(S),diff:4,active:'Running',others:'Disabled',login:short(loginSha),mcp:short(login.mcp_configuration_sha256),backup:short(login.backup_configuration_sha256)});

 // 2. Reused tools copy
 const src=path.join(WT,'tools','i_core');const files=walk(TOOLS);need(files.length===TOOLS_FILES,'step2','tools_file_count:'+files.length);
 for(const p of files){const rel=path.relative(TOOLS,p);need(existsSync(path.join(src,rel))&&fileSha(p)===fileSha(path.join(src,rel)),'step2','tools_mismatch:'+rel);}
 need(walk(src).length===TOOLS_FILES,'step2','worktree_tools_count');
 emit('step2',true,{files:TOOLS_FILES,reused:true});

 // 3. New Core package
 if(existsSync(REL)){need(statSync(REL).isDirectory()&&readdirSync(REL).length===0,'step3','release_dir_not_empty');rmdirSync(REL);}
 const cli=path.join(WT,'tools','i_core','release_schema6','cli.mjs');
 let r=run(process.execPath,[cli,'prepare',WT,REL,G,S],{step:'step3'});need(r.code===0,'step3','prepare_failed:'+(r.stderr.trim()||r.stdout.trim()));
 const prep=JSON.parse(r.stdout.trim().split(/\r?\n/).pop());const M=prep.manifest_sha256;need(/^[a-f0-9]{64}$/.test(M)&&prep.source_commit===S,'step3','prepare_result');
 r=run(process.execPath,[cli,'verify',REL,M],{step:'step3'});need(r.code===0,'step3','verify_failed:'+r.stderr.trim());
 const newMan=readJson(path.join(REL,'manifest.json'),M,'step3'),oldMan=readJson(path.join(login.release_directory,'manifest.json'),login.manifest_sha256,'step3');
 need(newMan.files.length===48&&oldMan.files.length===48,'step3','manifest_size');
 const oldBy=new Map(oldMan.files.map(f=>[f.path,f.sha256]));const changed=newMan.files.filter(f=>oldBy.get(f.path)!==f.sha256).map(f=>f.path).sort();
 need(JSON.stringify(changed)===JSON.stringify([...CHANGED].sort()),'step3','package_diff:'+changed.join(','));
 const relAcl=ps51("$q=[Console]::In.ReadToEnd()|ConvertFrom-Json\n$a=(Get-Item -LiteralPath $q.from).GetAccessControl('Access')\n$a.SetAccessRuleProtection($true,$true)\n(Get-Item -LiteralPath $q.to).SetAccessControl($a)\n$v=(Get-Item -LiteralPath $q.to).GetAccessControl('Access')\n[pscustomobject]@{protected=$v.AreAccessRulesProtected;rules=@($v.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])).Count}|ConvertTo-Json -Compress",{from:login.release_directory,to:REL},'step3');
 need(relAcl.protected===true&&relAcl.rules>0,'step3','release_acl');
 emit('step3',true,{manifest:M,source_commit:short(S),changed:newMan.files.filter(f=>CHANGED.includes(f.path)).map(f=>path.basename(f.path)+':'+short(f.sha256)),others_same:44,acl:relAcl});

 // 4. MCP candidate
 const build=path.join(WT,'build','n2-mcp-candidate');need(!existsSync(build),'step4','build_dir_exists');
 r=run(process.execPath,[path.join(WT,'tools','i_remote_mcp','chatgpt_candidate.mjs'),'--out','build/n2-mcp-candidate'],{cwd:WT,step:'step4'});need(r.code===0,'step4','candidate_build_failed:'+r.stderr.trim());
 const cm=readJson(path.join(build,'manifest.json'),null,'step4');
 need(cm.changed_files===5&&cm.source_commit===S&&cm.files.length===6,'step4','candidate_manifest');
 for(const f of cm.files)need(MCP_EXPECTED[f.path]===short(f.result_sha256),'step4','candidate_hash:'+f.path+':'+short(f.result_sha256));
 need(!existsSync(CAND),'step4','candidate_dir_exists');
 const dirs=['','runtime',path.join('runtime','i_remote_mcp'),path.join('runtime','i_memory')];
 for(const d of dirs){need(existsSync(path.join(oldCand,d)),'step4','old_candidate_dir_missing:'+d);mkdirSync(path.join(CAND,d),{recursive:true});}
 for(const p of walk(build)){const rel=path.relative(build,p);copyFileSync(p,path.join(CAND,rel));need(fileSha(path.join(CAND,rel))===fileSha(p),'step4','copy_mismatch:'+rel);}
 const acl=ps51("$q=[Console]::In.ReadToEnd()|ConvertFrom-Json\n$o=@()\nforeach($p in $q.pairs){$a=(Get-Item -LiteralPath $p.from).GetAccessControl('Access');$a.SetAccessRuleProtection($true,$true);(Get-Item -LiteralPath $p.to).SetAccessControl($a);$v=(Get-Item -LiteralPath $p.to).GetAccessControl('Access');$o+=[pscustomobject]@{dir=$p.rel;protected=$v.AreAccessRulesProtected;rules=@($v.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])).Count}}\nConvertTo-Json -InputObject $o -Compress",{pairs:dirs.map(d=>({rel:d||'.',from:d?path.join(oldCand,d):oldCand,to:d?path.join(CAND,d):CAND}))},'step4');
 for(const x of acl)need(x.protected===true&&x.rules>0,'step4','candidate_acl:'+x.dir);
 emit('step4',true,{server:short(cm.files.find(f=>f.path==='i_remote_mcp/server.mjs').result_sha256),acl});

 // 5. Package-switch configurations + fixed prepare
 const taskEntries=backup.specTemplate.entries.filter(e=>e.role==='task'&&!e.name.startsWith('preserved/')&&e.name==='tasks/HereIAm-CoreSchema6-Session.xml');
 need(taskEntries.length===1,'step5','backup_task_attachment_missing');
 const reqPath=path.join(OUT,'n2-pkg-request.json');need(!existsSync(reqPath)&&!existsSync(CFG),'step5','step5_output_exists');
 const request={oldLoginPath:loginPath,oldLoginSha256:loginSha,newReleaseDirectory:REL,newManifestSha256:M,outputDirectory:CFG,oldTaskXmlPath:taskEntries[0].source_path,taskName:NEW_TASK,oldTaskName:ACTIVE};
 writeFileSync(reqPath,JSON.stringify(request,null,2)+'\n',{flag:'wx'});
 r=run(process.execPath,[path.join(TOOLS,'maintenance','generate-package-switch-configurations.mjs'),'--input',reqPath,'--input-sha256',fileSha(reqPath)],{step:'step5'});
 const gen=lines(r.stdout).pop();need(r.code===0&&gen?.generated===true,'step5','generator:'+(gen?.code??r.code));
 const info=readJson(path.join(CFG,'static-inputs.json'),null,'step5');
 need(info.mcpPath===login.mcp_configuration_path&&info.mcpSha256===login.mcp_configuration_sha256,'step5','mcp_configuration_changed');
 r=run(PS(),['-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(REL,'tools','i_core','release_schema6','lifecycle','prepare_login_schema6.ps1'),'-ReleaseDirectory',REL,'-ManifestSha256',M,'-LoginConfigurationPath',info.loginPath,'-LoginConfigurationSha256',info.loginSha256,'-OutputXml',info.preparedXml,'-PrepareOnly'],{step:'step5'});
 const receipt=lines(r.stdout).pop();need(r.code===0&&receipt?.prepared===true&&receipt.registered===false&&receipt.started===false,'step5','prepare_login:'+(r.stderr.trim().split(/\r?\n/)[0]||r.code));
 writeFileSync(path.join(CFG,'prepare-receipt.json'),r.stdout,{flag:'wx'});
 emit('step5',true,{request:short(fileSha(reqPath)),login:short(info.loginSha256),core:short(fileSha(info.corePath)),backup:short(fileSha(info.backupPath)),mcp:short(info.mcpSha256),xml:short(fileSha(info.preparedXml)),receipt:short(fileSha(path.join(CFG,'prepare-receipt.json'))),newReleaseCount:gen.newReleaseCount,preservedLegacyCount:gen.preservedLegacyCount});

 // 6. Zero-write checks
 r=run(process.execPath,[path.join(TOOLS,'maintenance','generate-package-switch-evidence.mjs'),'old-task','--task',ACTIVE,'--preview'],{step:'step6'});
 const ev=lines(r.stdout).pop();need(r.code===0&&ev?.oldTaskStopped===false,'step6','old_task_preview:'+(ev?.code??r.code));
 r=run(process.execPath,[path.join(TOOLS,'maintenance','update-mcp-source.mjs'),'--from-task',ACTIVE,'--candidate',CAND,'--out',DRY,'--new-task',DRY_TASK,'--dry-run'],{step:'step6'});
 const c1=lines(r.stdout).find(x=>x.step==='update.result');const c1fail=lines(r.stdout).find(x=>x.ok===false);
 need(r.code===0&&c1?.detail==='dry_run_passed'&&!existsSync(DRY),'step6','c1_dry_run:'+(c1fail?.step??'')+':'+(c1fail?.detail??r.code));
 const after=ps51("ConvertTo-Json -InputObject @(Get-ScheduledTask|Where-Object{$_.TaskName -like 'HereIAm-iCoreSchema6-*'}|ForEach-Object{[pscustomobject]@{name=$_.TaskName;state=[string]$_.State}}) -Compress",{},'step6');
 const afterList=Array.isArray(after)?after:[after];
 need(JSON.stringify(afterList.map(t=>t.name+':'+t.state).sort())===JSON.stringify(list.map(t=>t.name+':'+t.state).sort()),'step6','task_list_changed');
 emit('step6',true,{oldTask:Object.fromEntries(Object.entries(ev).map(([k,v])=>[k,typeof v==='string'?short(v):v])),c1:{diff:c1.result.diff},tasksUnchanged:true});
 emit('done',true,{manifest:M,newTask:NEW_TASK});
}
try{main();}catch(e){emit(e.step??'unexpected',false,e.detail??String(e.message).slice(0,300));process.exitCode=1;}
