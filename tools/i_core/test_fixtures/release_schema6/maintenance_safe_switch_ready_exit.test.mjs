import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync,utimesSync,realpathSync,rmSync,rmdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {cleanEnvironment} from '../../release_schema6/package.mjs';

const here=path.dirname(fileURLToPath(import.meta.url));
const maintenance=path.resolve(here,'../../maintenance');
const ps=process.platform==='win32'?path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe'):null;
function run(mode,scenario,setup=()=>{}){
 const parent=realpathSync.native(tmpdir());const root=mkdtempSync(path.join(parent,'schema6-ready-exit-'));
 try {
  setup(root);
  const result=spawnSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(here,'maintenance_safe_switch_ready_exit.ps1'),
   '-MaintenanceDirectory',maintenance,'-Root',root,'-Mode',mode,'-Scenario',scenario],
   {env:cleanEnvironment(),windowsHide:true,encoding:'utf8',timeout:35000});
  assert.ifError(result.error);assert.equal(result.status,0,result.stdout+result.stderr);
  return JSON.parse(result.stdout.trim());
 }finally{
  assert.equal(path.dirname(root),parent);assert.ok(path.basename(root).startsWith('schema6-ready-exit-'));
  rmSync(root,{recursive:true,force:true});
 }
}
for(const scenario of ['valid','exits','stays-alive']){
 test('ready native hidden window: '+scenario,{skip:process.platform!=='win32',timeout:40000},()=>{
  const report=run('native',scenario);
  assert.equal(report.liveLeaseConfirmed,true);
  if(scenario==='valid'){assert.equal(report.error,null);}
  if(scenario==='exits'){
   assert.equal(report.error,null);assert.equal(report.returnedNull,true);assert.equal(report.exited,true);
   assert.ok(report.elapsed<10000,'exiting process returns within the wait budget');
  }
  if(scenario==='stays-alive'){
   assert.equal(report.error,'session_host_window_mismatch');assert.equal(report.returnedNull,false);assert.equal(report.exited,false);
   assert.ok(report.elapsed>=9900&&report.elapsed<14000,'missing window waits at most the native ten-second timeout');
  }
 });
}
function setup(root,{child={error_code:'recovery_required'},exit=true,newSession=true}={}){
 const old=path.join(root,'session-old','control-old');mkdirSync(old,{recursive:true});
 writeFileSync(path.join(root,'session-old','session-exit.json'),'{}');writeFileSync(path.join(old,'child.json'),'{"error_code":"ignored_previous"}');
 if(!newSession)return;
 const control=path.join(root,'session-new','control-new');mkdirSync(control,{recursive:true});
 const earlier=path.join(root,'session-new','control-earlier');mkdirSync(earlier);
 writeFileSync(path.join(earlier,'child.json'),'{"error_code":"ignored_older_generation"}');utimesSync(earlier,1,1);
 if(exit)writeFileSync(path.join(root,'session-new','session-exit.json'),'{}');
 if(child!==null)writeFileSync(path.join(control,'child.json'),typeof child==='string'?child:JSON.stringify(child));
 // Ensure the old session cannot win diagnostics even if its control is newest.
 utimesSync(old,2000000000,2000000000);
}
const cases=[
 {name:'ended with child recovery code',expected:'recovery_required'},
 {name:'ended without child',child:null,expected:'none'},
 {name:'ended without error_code',child:{},expected:'none'},
 {name:'ended with illegal code',child:{error_code:'unsafe;value'},expected:'unreadable'},
 {name:'ended with uppercase code',child:{error_code:'Recovery_required'},expected:'unreadable'},
 {name:'ended with trailing newline',child:{error_code:'recovery_required\n'},expected:'unreadable'},
 {name:'ended with oversized code',child:{error_code:'a'.repeat(65)},expected:'unreadable'},
 {name:'ended with non-string code',child:{error_code:123},expected:'unreadable'},
 {name:'ended with malformed child',child:'{invalid',expected:'unreadable'},
 {name:'timeout with child',scenario:'timeout',exit:false,expected:'recovery_required',error:'new_session_ready_timeout'},
 {name:'timeout without new session',scenario:'timeout',newSession:false,expected:'none',error:'new_session_ready_timeout'},
 {name:'task assertion failure',scenario:'assert-error',expected:'recovery_required',error:'synthetic_task_changed'},
 {name:'live enumeration failure',scenario:'live-error',expected:'recovery_required',error:'synthetic_live_error'},
 {name:'diagnostic enumeration error preserves failure',scenario:'assert-error',expected:'unreadable',error:'synthetic_task_changed',missingRoot:true},
 {name:'exit receipt with live lease is not an early exit',scenario:'live-exit',expected:'recovery_required',error:'new_session_ready_timeout'},
];
for(const c of cases){
 test('ready orchestration: '+c.name,{skip:process.platform!=='win32',timeout:40000},()=>{
  const report=run('orchestration',c.scenario??'ended',root=>{
   if(c.missingRoot){rmdirSync(root);return;}
   setup(root,c);
  });
  assert.equal(report.message,(c.error??'new_session_ended_before_ready')+';child_error_code='+c.expected);
  assert.ok(report.elapsed<10000,'does not wait for the sixty-second readiness deadline');
  if(c.scenario==='live-exit')assert.equal(report.disposed,true,'live lease is disposed each poll');
 });
}
