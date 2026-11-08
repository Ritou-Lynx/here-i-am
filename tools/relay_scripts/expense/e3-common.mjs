// Shared helpers for the E3 (expense ledger) script rounds. Imported by e3-inspect.mjs and
// e3-deploy.mjs only; the launchers pin all three files by SHA256.
// Output: one JSON row per step; no tokens, logins, domains, paths, SIDs or record contents.
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {existsSync,mkdirSync,readFileSync,readdirSync,writeFileSync} from 'node:fs';
import {createServer} from 'node:net';
import path from 'node:path';

export const ACTIVE='HereIAm-iCoreSchema6-m1-digest-20261107';
export const P='HereIAm-iCoreSchema6-e3-pkg-20261108';
export const P2='HereIAm-iCoreSchema6-e3-expense-20261108';
// Live Core package (N2, release-42ecf688) and MCP candidate (M1).
export const OLD_MANIFEST='9897fb4109f1e6dda4fa15c3a0a1ef34f4ed001160d3e458ae94860b1349af95';
export const OLD_SERVER='bde3ff9f',OLD_MCP='838810b2';
// New Core package: v3-lab at the #98 merge. Only these inventory files differ from the live package.
export const S='78e11df7cccec184a6d7697b395016d8f2cfa1c1';
export const CHANGED=['tools/i_core/personal_data_domains.mjs','tools/i_core/release_schema6/lifecycle/runtime_child.mjs'];
export const MCP_EXPECTED={'i_remote_mcp/server.mjs':'63acb514','i_remote_mcp/oauth.mjs':'e2c88aca','i_remote_mcp/diagnostics.mjs':'67b0fbec',
 'i_remote_mcp/mcp.mjs':'838810b2','i_remote_mcp/writeback.mjs':'a7a6f95d','i_memory/i_memory_read.mjs':'cee18518'};
// Maintenance copy used by ST1/HR1/G2/M1. Since then tools/i_core changed only in these files (none under maintenance/).
export const TOOLS_COMMIT='4603fb79',TOOLS_FILES=321;
export const TOOLS_DRIFT=['tools/i_core/expense_domains.test.mjs',...CHANGED];
export const PINNED_NODE='58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f';
export const LISTEN_PORT=47866;
export const EXPENSE_JSON='{"format":"expense-v1"}';

export class Stop extends Error{constructor(step,detail){super(detail);this.step=step;this.detail=detail;}}
export const sha=b=>createHash('sha256').update(b).digest('hex');
export const fileSha=p=>sha(readFileSync(p));
export const short=h=>String(h).slice(0,8).toLowerCase();
export function files(root){const out=[];const go=d=>{for(const e of readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);if(e.isDirectory())go(p);else out.push(p);}};go(root);return out;}
let reportSink=null;
export function setReport(fn){reportSink=fn;}
export function emit(step,ok,detail){const row=JSON.stringify({step,ok,detail});console.log(row);if(reportSink)try{reportSink(row);}catch{}}
export function need(cond,step,detail){if(!cond)throw new Stop(step,detail);}
export function plain(p){return typeof p==='string'&&path.win32.isAbsolute(p)&&path.win32.normalize(p)===p&&p.indexOf(':',2)<0&&!p.endsWith('\\')&&!p.startsWith('\\\\');}
export function readJson(p,expected,step){const b=readFileSync(p);if(expected)need(sha(b)===String(expected).toLowerCase(),step,'hash_mismatch:'+path.basename(p));return JSON.parse(b.toString('utf8').replace(/^﻿/,''));}
export const childEnv=()=>{const e={};for(const [k,v] of Object.entries(process.env))if(!/^(NODE_|I_CORE_|I_REMOTE_MCP_|GIT_)/i.test(k)&&!['OPENSSL_CONF','SSL_CERT_FILE','SSL_CERT_DIR'].includes(k.toUpperCase()))e[k]=v;e.PSModulePath=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','Modules');return e;};
export function run(file,args,{cwd,input,step,timeoutMin=30}={}){
 const r=spawnSync(file,args,{cwd,input,env:childEnv(),encoding:'utf8',windowsHide:true,maxBuffer:64*1024*1024,timeout:timeoutMin*60*1000});
 if(r.error)throw new Stop(step,'spawn_failed:'+r.error.code);
 return {code:r.status,stdout:r.stdout??'',stderr:r.stderr??''};
}
export const rows=t=>t.split(/\r?\n/).filter(Boolean).map(l=>{try{return JSON.parse(l);}catch{return null;}}).filter(Boolean);
export const lastErr=r=>(r.stderr.trim().split(/\r?\n/).filter(Boolean).pop()??'').replace(/[A-Za-z]:\\[^\s'"]*/g,'<path>').slice(0,240);
export const PS=()=>path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');
export const PSARGS=['-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass'];
const HEAD51="$ErrorActionPreference='Stop'\nif($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'host_not_51'}\n$q=[Console]::In.ReadToEnd()|ConvertFrom-Json\n";
export function ps51(script,input,step,timeoutMin=5){return run(PS(),[...PSARGS,'-EncodedCommand',Buffer.from(HEAD51+script,'utf16le').toString('base64')],{input:JSON.stringify(input??{}),step,timeoutMin});}
export function value(script,input,step,timeoutMin=5){const r=ps51(script,input,step,timeoutMin);need(r.code===0,step,'powershell_exit_'+r.code+':'+lastErr(r));return JSON.parse(r.stdout.trim().split(/\r?\n/).filter(Boolean).pop());}
// Maintenance entry points: always a fresh Windows PowerShell 5.1 child with -File.
export function psFile(script,args,step,{input,timeoutMin=20}={}){return run(PS(),[...PSARGS,'-File',script,...args],{step,input,timeoutMin});}
export const asList=v=>v==null?[]:Array.isArray(v)?v:[v];
// Echo maintenance rows (step/ok/detail only) so a failure shows the exact row.
export function relay(step,r){for(const row of rows(r.stdout))if(row.step!==undefined)emit(step+':'+row.step,row.ok!==false,typeof row.detail==='string'?row.detail.slice(0,240):row.detail);}

const TASKS_PS="ConvertTo-Json -InputObject @(Get-ScheduledTask|Where-Object{$_.TaskName -like 'HereIAm-iCoreSchema6-*'}|ForEach-Object{[pscustomobject]@{name=$_.TaskName;state=[string]$_.State;actions=@($_.Actions).Count;arguments=[string]$_.Actions[0].Arguments}}) -Compress -Depth 3";
export const tasks=step=>asList(value(TASKS_PS,{},step));
export function loginOf(task,step){
 const tok=[...task.arguments.matchAll(/"([^"]*)"|(\S+)/g)].map(m=>m[1]??m[2]);
 const arg=re=>{const i=tok.map((t,j)=>re.test(t)?j:-1).filter(j=>j>=0);need(i.length===1&&i[0]+1<tok.length,step,'login_argument_ambiguous');return tok[i[0]+1];};
 const p=arg(/^-(Login)?ConfigurationPath$/i),h=arg(/^-(Login)?ConfigurationSha256$/i).toLowerCase();
 const login=readJson(p,h,step);need(login.format==='schema6-login-v1',step,'login_format');return {path:p,sha256:h,login};
}
export const mcpOf=(l,step='mcp')=>readJson(l.login.mcp_configuration_path,l.login.mcp_configuration_sha256,step);
export const serverOf=(l,step)=>short(mcpOf(l,step).source_files?.find(f=>f.path==='i_remote_mcp/server.mjs')?.sha256);
export function portFree(port){return new Promise(resolve=>{const s=createServer();s.once('error',()=>resolve(false));s.listen(port,'127.0.0.1',()=>s.close(()=>resolve(true)));});}
// Copy the DACL (only) of each source directory onto its target, protected.
export const ACL_PS="$o=@()\nforeach($p in $q.pairs){$a=(Get-Item -LiteralPath $p.from).GetAccessControl('Access');$a.SetAccessRuleProtection($true,$true);(Get-Item -LiteralPath $p.to).SetAccessControl($a);$v=(Get-Item -LiteralPath $p.to).GetAccessControl('Access');$o+=[pscustomobject]@{dir=$p.rel;protected=$v.AreAccessRulesProtected;rules=@($v.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])).Count}}\nConvertTo-Json -InputObject $o -Compress";
export const CHECK_ACL_PS="$o=@()\nforeach($p in $q.dirs){$v=(Get-Item -LiteralPath $p.path).GetAccessControl('Access');$o+=[pscustomobject]@{dir=$p.rel;protected=$v.AreAccessRulesProtected;rules=@($v.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])).Count}}\nConvertTo-Json -InputObject $o -Compress";

// Everything both rounds check before touching anything. Read-only.
export function preflight({G,REPO,step}){
 const git=(args)=>{const r=run(G,['-C',REPO,...args],{step});need(r.code===0,step,'git_failed:'+args[0]);return r.stdout;};
 const list=tasks(step);
 const active=list.filter(t=>t.name===ACTIVE);need(active.length===1&&active[0].state==='Running'&&active[0].actions===1,step,'active_task_not_running:'+(active[0]?.state??'missing'));
 const others=list.filter(t=>t.name!==ACTIVE&&t.state!=='Disabled');need(others.length===0,step,'other_task_enabled:'+others.map(t=>t.name).join(','));
 need(!list.some(t=>[P,P2].includes(t.name)),step,'target_task_exists');
 const live=loginOf(active[0],step),login=live.login;
 need(login.manifest_sha256===OLD_MANIFEST&&fileSha(path.join(login.release_directory,'manifest.json'))===OLD_MANIFEST,step,'live_release_not_n2:'+short(login.manifest_sha256));
 const mcp=mcpOf(live,step),backup=readJson(login.backup_configuration_path,login.backup_configuration_sha256,step),core=readJson(login.core_configuration_path,login.core_configuration_sha256,step);
 const oldCand=path.dirname(mcp.working_directory),OUT=path.dirname(oldCand);
 need(path.basename(mcp.working_directory)==='runtime'&&/^mcp-candidate-/.test(path.basename(oldCand))&&plain(OUT),step,'live_candidate_layout');
 need(serverOf(live,step)===OLD_SERVER&&short(fileSha(path.join(mcp.working_directory,'i_remote_mcp','server.mjs')))===OLD_SERVER,step,'live_server_not_m1');
 need(short(fileSha(path.join(mcp.working_directory,'i_remote_mcp','mcp.mjs')))===OLD_MCP,step,'live_mcp_not_m1');
 const stateMcp=mcp.environment?.I_REMOTE_MCP_STATE_DIR;need(plain(stateMcp)&&existsSync(stateMcp),step,'mcp_state_dir');
 need(existsSync(path.join(stateMcp,'core-food.json')),step,'food_credential_missing');
 const expenseJson=path.join(stateMcp,'expense.json');
 if(existsSync(expenseJson))need(readFileSync(expenseJson,'utf8').replace(/^﻿/,'').trim()===EXPENSE_JSON,step,'expense_json_differs');
 const stateDir=login.state_directory;
 need(!existsSync(path.join(stateDir,'s6-recovery-pending.json')),step,'recovery_latch_present');
 for(const f of ['s6-package-switch-pending.json'])need(!existsSync(path.join(stateDir,f)),step,'package_switch_pending');
 const marker=path.join(stateDir,'s6-lifecycle.json'),head=path.join(core.recovery_custody_directory,'current-head.json');
 need(existsSync(marker)&&existsSync(head)&&!existsSync(path.join(core.recovery_custody_directory,'package-switch-pending.json')),step,'marker_or_head');
 const pending=files(login.control_root).filter(p=>/^(pair|food)\.request$/i.test(path.basename(p)));need(pending.length===0,step,'pending_request_present');
 const taskEntries=backup.specTemplate.entries.filter(e=>e.role==='task'&&!e.name.startsWith('preserved/')&&e.name==='tasks/HereIAm-CoreSchema6-Session.xml');
 need(taskEntries.length===1&&existsSync(taskEntries[0].source_path),step,'backup_task_attachment_missing');
 // Source: the new package commit must be on v3-lab history of this checkout.
 const HEAD=git(['rev-parse','HEAD']).trim();
 need(git(['status','--porcelain','--untracked-files=no']).trim()==='',step,'checkout_dirty');
 need(run(G,['-C',REPO,'merge-base','--is-ancestor',S,HEAD],{step}).code===0,step,'S_not_in_checkout');
 const drift=git(['diff','--name-only',TOOLS_COMMIT,S,'--','tools/i_core']).split(/\r?\n/).filter(Boolean).sort();
 need(JSON.stringify(drift)===JSON.stringify([...TOOLS_DRIFT].sort()),step,'tools_drift:'+drift.join(','));
 const TOOLS=path.join(OUT,'tools-'+TOOLS_COMMIT),MT=path.join(TOOLS,'tools','i_core','maintenance');
 for(const n of ['switch-login-task.ps1','update-mcp-source.mjs','generate-package-switch-configurations.mjs','generate-package-switch-evidence.mjs','prepare-package-switch.mjs','register-package-switch-login.ps1','close-schema6-session.ps1','stop-schema6-session.ps1','package-switch-bindings.mjs'])
  need(existsSync(path.join(MT,n)),step,'tools_copy_missing:'+n);
 need(files(TOOLS).length===TOOLS_FILES,step,'tools_copy_count');
 // Maintenance scripts in the copy must equal the committed ones at S (they did not change since TOOLS_COMMIT);
 // a CRLF checkout copy is accepted when it equals the committed bytes after CRLF->LF.
 for(const p of files(MT)){const rel='tools/i_core/maintenance/'+path.relative(MT,p).split(path.sep).join('/');
  const r=spawnSync(G,['-C',REPO,'show',S+':'+rel],{env:childEnv(),windowsHide:true,maxBuffer:16*1024*1024});
  const b=readFileSync(p);need(r.status===0&&[sha(b),sha(Buffer.from(b.toString('latin1').replaceAll('\r\n','\n'),'latin1'))].includes(sha(r.stdout)),step,'tools_copy_differs:'+path.basename(p));}
 return {list,live,login,mcp,backup,core,oldCand,OUT,stateMcp,expenseJson,stateDir,marker,head,taskEntries,HEAD,TOOLS,MT};
}

// Committed package sources at S, read with plain `git show` (the package CLI insists on a
// single-link git.exe, which this machine does not have; round 2). Same bytes and checks as
// package.mjs readCommittedSources/validateImports.
async function committedSources({REPO,G,step}){
 const {pathToFileURL}=await import('node:url');
 const pkg=await import(pathToFileURL(path.join(REPO,'tools','i_core','release_schema6','package.mjs')).href);
 const rev=run(G,['-C',REPO,'rev-parse','--verify',S+'^{commit}'],{step});need(rev.code===0&&rev.stdout.trim()===S,step,'source_commit');
 const content=new Map();
 for(const name of [...pkg.SOURCES,...pkg.WRAPPERS.map(n=>'tools/i_core/release_schema6/'+n)]){
  const r=spawnSync(G,['-C',REPO,'show',S+':'+name],{env:childEnv(),windowsHide:true,maxBuffer:16*1024*1024});
  need(r.status===0,step,'git_show:'+path.posix.basename(name));content.set(name,r.stdout);
 }
 const known=new Set(pkg.INVENTORY);
 need(JSON.stringify([...content.keys(),'runtime/node.exe'].sort())===JSON.stringify([...pkg.INVENTORY].sort()),step,'inventory_mismatch');
 for(const [name,bytes] of content){
  if(!name.endsWith('.mjs'))continue;
  const source=bytes.toString('utf8');
  need(!(pkg.SOURCES.includes(name)&&/\bimport\s*\(|\brequire\s*\(/.test(source)),step,'dynamic_dependency_requires_review');
  for(const m of source.matchAll(/\bfrom\s+['"]([^'"]+)['"]|\bimport\s+['"]([^'"]+)['"]/g)){
   const dep=m[1]??m[2];if(dep.startsWith('node:'))continue;
   need(dep.startsWith('.')&&known.has(path.posix.normalize(path.posix.join(path.posix.dirname(name),dep))),step,'unlisted_runtime_dependency');
  }
 }
 return {pkg,content};
}

// Changed inventory paths between the committed package at S and the live manifest.
export async function packageDiff({REPO,G,login,step}){
 const {pkg,content}=await committedSources({REPO,G,step});
 const oldMan=readJson(path.join(login.release_directory,'manifest.json'),login.manifest_sha256,step);
 const inv=pkg.INVENTORY.filter(n=>n!=='runtime/node.exe');
 need(oldMan.files.length===48&&inv.length===47,step,'inventory_size');
 const oldBy=new Map(oldMan.files.map(f=>[f.path,f.sha256]));
 return inv.filter(n=>oldBy.get(n)!==sha(content.get(n))).sort();
}

// Same output as package.mjs prepareRelease (manifest built field for field), then its verifyRelease.
export async function buildRelease({REPO,G,REL,step}){
 const {pkg,content}=await committedSources({REPO,G,step});
 need(!existsSync(REL),step,'fresh_output_required');
 const nodeBytes=readFileSync(process.execPath);need(sha(nodeBytes)===pkg.PINNED_NODE_SHA256,step,'node_hash_mismatch');
 content.set('runtime/node.exe',nodeBytes);
 const manifest=Buffer.from(JSON.stringify({format:'i-core-schema6-preflight-candidate-v1',source_commit:S,core_commit:S,wrapper_commit:S,
  core_schema_version:6,runtime_profile:'schema6-owned-lifecycle-v1',
  pinned_node_sha256:pkg.PINNED_NODE_SHA256,node_version:'v24.14.1',
  policy:{companion_upload_mode:'legacy_b3',companion_reply_jobs:false,activity_enabled:false,domain_policy:'owner_managed'},
  activation_supported:false,files:pkg.INVENTORY.map(name=>({path:name,bytes:content.get(name).length,sha256:sha(content.get(name))}))},null,2)+'\n');
 mkdirSync(REL);
 for(const [name,bytes] of [...content,['manifest.json',manifest]]){mkdirSync(path.dirname(path.join(REL,name)),{recursive:true});writeFileSync(path.join(REL,name),bytes,{flag:'wx'});}
 const v=pkg.verifyRelease(REL,sha(manifest));need(v.source_commit===S,step,'verify_source_commit');
 return sha(manifest);
}

export function expenseReceipts(controlRoot){
 return files(controlRoot).filter(p=>/^expense-receipt-\d+\.json$/.test(path.basename(p)));
}
