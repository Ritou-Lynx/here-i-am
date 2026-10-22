import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,readdirSync,realpathSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {cleanEnvironment} from '../../release_schema6/package.mjs';

const here=path.dirname(fileURLToPath(import.meta.url));
const maintenance=path.resolve(here,'../../maintenance');
const ps=process.platform==='win32'?path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe'):null;
function snapshot(root,relative=''){
 return readdirSync(path.join(root,relative),{withFileTypes:true}).sort((a,b)=>a.name<b.name?-1:1).flatMap(entry=>{
  const name=path.join(relative,entry.name);
  return entry.isDirectory()?[[name,'directory'],...snapshot(root,name)]:[[name,createHash('sha256').update(readFileSync(path.join(root,name))).digest('hex')]];
 });
}
const scenarios=[
 {name:'other sidecars and nested core sidecar',files:['z-wal','A-shm','a-journal','nested/i-core.sqlite-wal'],detail:'A-shm,a-journal,z-wal'},
 ...['wal','shm','journal'].flatMap(suffix=>[suffix,suffix.toUpperCase()].map(value=>({name:'core sidecar '+value,files:['I-CORE.SQLITE-'+value],error:'database_sidecars_present'}))),
 {name:'exclusive relay lock',files:['shortcut-mail-relay.runtime.lock'],held:true,error:'relay_lock_held'},
 {name:'unoccupied relay lock',files:['shortcut-mail-relay.runtime.lock']},
 {name:'recovery pending takes precedence',files:['s6-recovery-pending.json','i-core.sqlite-wal','other-shm','shortcut-mail-relay.runtime.lock'],held:true,error:'recovery_pending_manual_review_required'},
 {name:'empty state',files:[]},
];
for(const scenario of scenarios){
 test('closed files: '+scenario.name,{skip:process.platform!=='win32',timeout:20000},()=>{
  const parent=realpathSync.native(tmpdir());const root=mkdtempSync(path.join(parent,'schema6-closed-files-'));
  try {
   for(const name of scenario.files){const file=path.join(root,name);mkdirSync(path.dirname(file),{recursive:true});writeFileSync(file,'synthetic:'+name);}
   const before=snapshot(root);
   const result=spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',
    path.join(here,'maintenance_safe_switch_closed_files.ps1'),'-MaintenanceDirectory',maintenance,'-StateDirectory',root,...(scenario.held?['-HoldLock']:[])],
    {env:cleanEnvironment(),windowsHide:true,encoding:'utf8',timeout:15000});
   assert.deepEqual(snapshot(root),before,'STATE file collection and hashes are unchanged, including on failure');
   assert.ifError(result.error);assert.equal(result.status,0,result.stdout+result.stderr);
   const rows=result.stdout.trim().split(/\r?\n/).map(JSON.parse);
   assert.equal(rows.at(-1).error,scenario.error??null);
   const sidecars=rows.filter(row=>row.step==='stop.closed_files_other_sidecars');
   assert.deepEqual(sidecars,scenario.detail?[{step:'stop.closed_files_other_sidecars',ok:true,detail:scenario.detail}]:[]);
  }finally{
   assert.equal(path.dirname(root),parent);assert.ok(path.basename(root).startsWith('schema6-closed-files-'));
   rmSync(root,{recursive:true});
  }
 });
}
