// E3 (expense ledger) round 1: read-only inspection before the deploy round.
// Checks the live task, Core package, MCP candidate, maintenance copy and state markers,
// compares the committed package at S with the live manifest, previews the old-task
// evidence (zero-write) and reports free disk space. Writes nothing, starts nothing.
// Usage: e3-inspect.ps1 (Windows PowerShell 5.1, -File) runs this with --git <git.exe>.
import {existsSync,statSync,statfsSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {ACTIVE,CHANGED,LISTEN_PORT,S,emit,expenseReceipts,need,packageDiff,plain,portFree,preflight,rows,run,short,singleLinkGit} from './e3-common.mjs';

const REPO=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..','..','..');

async function main(){
 const a=process.argv.slice(2);need(a.length===2&&a[0]==='--git','args','usage: --git <git.exe>');
 need(process.platform==='win32'&&process.version==='v24.14.1'&&plain(process.execPath),'args','pinned_node_required');
 need(plain(a[1])&&existsSync(a[1])&&statSync(a[1]).isFile(),'args','git_path_required');const G=singleLinkGit(a[1],'args');
 const f=preflight({G,REPO,step:'step0'});
 emit('step0',true,{active:'Running',others:'Disabled',release:path.basename(f.login.release_directory),manifest:short(f.login.manifest_sha256),
  server:short(f.mcp.source_files.find(x=>x.path==='i_remote_mcp/server.mjs').sha256),candidate:path.basename(f.oldCand),tools:path.basename(f.TOOLS),
  expense_json:existsSync(f.expenseJson)?'present':'absent',head:short(f.HEAD),S:short(S),git:path.basename(path.dirname(G))+'\\git.exe'});

 let ok=true;
 const changed=await packageDiff({REPO,G,login:f.login,step:'step1'});
 const diffOk=JSON.stringify(changed)===JSON.stringify([...CHANGED].sort());ok&&=diffOk;
 emit('step1',diffOk,{package_diff:changed.map(n=>path.basename(n))});

 const r=run(process.execPath,[path.join(f.MT,'generate-package-switch-evidence.mjs'),'old-task','--task',ACTIVE,'--preview'],{step:'step2'});
 const ev=rows(r.stdout).pop();
 const evOk=r.code===0&&ev?.oldTaskStopped===false;ok&&=evOk;
 emit('step2',evOk,{old_task_preview:r.code===0?'ok':(ev?.code??r.code),oldTaskStopped:ev?.oldTaskStopped});

 const disk=statfsSync(f.OUT);const freeGb=Math.round(Number(disk.bavail)*Number(disk.bsize)/1e8)/10;
 const used=['release-'+S.slice(0,8),'e3-pkg-configs'].map(n=>({n,exists:existsSync(path.join(f.OUT,n))}));
 ok&&=freeGb>=2;
 emit('step3',freeGb>=2,{free_gb:freeGb,out_names_taken:used.filter(x=>x.exists).map(x=>x.n)});

 emit('step4',true,{expense_receipts:expenseReceipts(f.login.control_root).length,heart_rate_listener:!(await portFree(LISTEN_PORT)),core_port:f.login.core_port?'set':'missing'});
 emit('done',ok,{ready_for_deploy:ok});
 if(!ok)process.exitCode=1;
}
main().catch(e=>{emit(e.step??'unexpected',false,e.detail??String(e.message).slice(0,300));process.exitCode=1;});
