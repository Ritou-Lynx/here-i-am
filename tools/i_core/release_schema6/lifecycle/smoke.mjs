// Synthetic-only smoke for an already assembled, externally anchored candidate.
// This test tool is deliberately excluded from the production release inventory.
import assert from 'node:assert/strict';
import { spawn, execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync, existsSync, realpathSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { verifyRelease, sha256, plainPath, cleanEnvironment, PINNED_NODE_SHA256 } from '../package.mjs';
const [release,manifestHash,...extra]=process.argv.slice(2);
assert.equal(extra.length,0);assert.equal(process.platform,'win32');assert.equal(sha256(readFileSync(process.execPath)),PINNED_NODE_SHA256);
const verified=verifyRelease(release,manifestHash),started=Date.now();
const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
const lifecycle=path.join(release,'tools/i_core/release_schema6/lifecycle');
const env=cleanEnvironment(),quote=s=>"'"+s.replaceAll("'","''")+"'";
const protect=root=>execFileSync(ps,['-NoProfile','-NonInteractive','-Command',". "+quote(path.join(lifecycle,'protected_paths.ps1'))+"; Protect-NewDirectory "+quote(root)],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});
const root=realpathSync.native(mkdtempSync(path.join(tmpdir(),'schema6-fixed-smoke-')));protect(root);
const directory=name=>{const p=path.join(root,name);mkdirSync(p);protect(p);return p;};
const state=directory('state'),control=directory('control'),settings=directory('settings'),custody=directory('custody'),backups=directory('backups');
for(const purpose of ['backup','recovery'])execFileSync(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(release,'tools/i_core/release_schema6/key_custody.ps1'),'-Action','Create','-KeyDirectory',path.join(root,purpose+'-key'),'-Purpose',purpose],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});
const grants=path.join(settings,'grants.json'),approvals=path.join(settings,'approvals.json');
writeFileSync(grants,JSON.stringify({version:1,grants:[]}));writeFileSync(approvals,JSON.stringify({version:1,approved_replays:[]}));
const owner_sid=execFileSync(ps,['-NoProfile','-NonInteractive','-Command','[Security.Principal.WindowsIdentity]::GetCurrent().User.Value'],{env,windowsHide:true,encoding:'utf8'}).trim();
const config=path.join(settings,'runtime.json');
writeFileSync(config,JSON.stringify({format:'schema6-config-v1',manifest_sha256:manifestHash,database_path:path.join(state,'i-core.sqlite'),node_id:'new',owner_sid,
 companion_upload_mode:'legacy_b3',companion_reply_jobs:false,activity_enabled:false,domain_policy:'owner_managed',pairing_secret:null,
 grants_path:grants,grants_sha256:sha256(readFileSync(grants)),approvals_path:approvals,approvals_sha256:sha256(readFileSync(approvals)),
 recovery_custody_directory:custody,recovery_key_path:path.join(root,'recovery-key','runtime-recovery.dpapi'),
 backup_directory:backups,backup_key_path:path.join(root,'backup-key','runtime-backup.dpapi')}));
const read=name=>existsSync(path.join(control,name))?JSON.parse(readFileSync(path.join(control,name))):null;
const wait=async(fn,timeout=120000)=>{const end=Date.now()+timeout;while(Date.now()<end){const value=fn();if(value)return value;await new Promise(r=>setTimeout(r,50));}throw new Error('synthetic_smoke_timeout');};
const child=spawn(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(lifecycle,'start_schema6.ps1'),'-ManifestSha256',manifestHash,'-Start','-InitializeEmpty','-StateDirectory',state,'-ControlDirectory',control,'-ConfigurationFile',config],{env,windowsHide:true,stdio:['ignore','ignore','pipe']});
let closed=false,exit=null;child.on('close',code=>{closed=true;exit=code;});child.stderr.resume();
const stop=()=>{const launch=read('launch.json');if(launch)execFileSync(ps,['-NoProfile','-NonInteractive','-File',path.join(lifecycle,'request_stop.ps1'),'-ControlDirectory',control,'-RunId',launch.token,'-ManifestSha256',manifestHash],{env,windowsHide:true,stdio:['ignore','pipe','pipe'],timeout:15000});};
let confirmed=false;
try {
 await wait(()=>read('ready.json')||closed);assert.equal(closed,false,JSON.stringify(read('child.json')));
 const ready=read('ready.json');assert.equal(ready.health.schema_version,6);assert.equal(ready.address.address,'127.0.0.1');
 assert.equal(ready.activity_enabled,false);assert.equal(ready.companion_reply_jobs,false);assert.equal(ready.companion_upload_mode,'legacy_b3');
 assert.equal((await fetch('http://127.0.0.1:'+ready.address.port+'/v1/core/health',{signal:AbortSignal.timeout(5000)})).status,200);
 stop();await wait(()=>closed);assert.equal(exit,0,JSON.stringify(read('child.json')));
 const receipt=read('supervisor.json');
 assert.equal(receipt.manifest_sha256,manifestHash);assert.equal(receipt.child_receipt_confirmed,true);assert.equal(receipt.guardian_receipt_confirmed,true);
 assert.equal(receipt.lock_released_confirmed,true);assert.equal(receipt.result.job_empty_confirmed,true);
 assert.equal(receipt.result.child_exit_code,0);assert.equal(receipt.result.guardian_exit_code,0);assert.equal(receipt.result.termination_requested,false);
 assert.equal(JSON.parse(readFileSync(path.join(state,'s6-lifecycle.json'))).phase,'clean_closed');
 verifyRelease(release,manifestHash);confirmed=true;
 console.log(JSON.stringify({...verified,synthetic_fixed_candidate_smoke:true,schema6:true,loopback_health:true,authenticated_stop:true,
  native_child_exit:true,native_guardian_exit:true,job_empty:true,runtime_lock_released:true,release_unchanged:true,elapsed_ms:Date.now()-started}));
} finally {
 if(!closed){try{stop();await wait(()=>closed,90000);}catch{child.kill();await wait(()=>closed,15000);}}
 if(confirmed){
  const parent=realpathSync.native(tmpdir());plainPath(root);
  assert.equal(path.dirname(root),parent);assert.match(path.basename(root),/^schema6-fixed-smoke-/);
  const inspect=dir=>{plainPath(dir);for(const item of readdirSync(dir,{withFileTypes:true})){const filename=plainPath(path.join(dir,item.name));if(item.isDirectory())inspect(filename);}};
  inspect(root);rmSync(root,{recursive:true});assert.equal(existsSync(root),false);
 } else console.error(JSON.stringify({synthetic_smoke_failed:true,evidence_root:root,child_error_code:read('child.json')?.error_code??null}));
}
