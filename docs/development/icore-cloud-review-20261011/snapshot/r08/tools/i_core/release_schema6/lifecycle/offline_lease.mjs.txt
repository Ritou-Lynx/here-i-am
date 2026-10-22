import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { MessageChannel, Worker } from 'node:worker_threads';
import { cleanEnvironment, plainPath, verifyRelease, fail } from '../package.mjs';
import { assertNode } from './common.mjs';
import { receiveProbeReply, validateProbeRequest, verifyProbeResponse } from './offline_probe_client.mjs';
const leases=new WeakMap();
const ownedTransports=new Set();
const clientPath=fileURLToPath(new URL('./offline_probe_client.mjs',import.meta.url));
function startTransport(data){
 const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');
 data.pipeName='ICoreSchema6Probe-'+randomBytes(16).toString('hex');data.readyName=data.pipeName+'.ready.json';
 data.sequence=0;data.closed=false;data.failed=false;
 data.key=readFileSync(plainPath(path.join(data.control,'stop.key')),'utf8');
 if(!/^[a-f0-9]{64}$/.test(data.key))fail('offline_probe_key_rejected');
 data.server=spawn(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',fileURLToPath(new URL('./probe_offline.ps1',import.meta.url)),
  '-ControlDirectory',data.control,'-RunId',data.token,'-ChildPid',String(process.pid),'-Server','-PipeName',data.pipeName],
  {env:cleanEnvironment(),windowsHide:true,stdio:'ignore'});
 ownedTransports.add(data);
 data.exited=new Promise(resolve=>{
  data.server.on('error',()=>{
   data.failed=true;
   // An error while killing a started helper is not proof that it exited.
   if(!data.server.pid){data.exitResult={code:null,notStarted:true};resolve(data.exitResult);}
  });
  data.server.once('exit',(code,signal)=>{data.exitResult={code,signal};if(code!==0)data.failed=true;resolve(data.exitResult);});
 });
 const {port1,port2}=new MessageChannel();data.port=port1;data.signal=new Int32Array(new SharedArrayBuffer(8));
 try{
  data.worker=new Worker(clientPath,{workerData:{mode:'offline-probe-thread-v1',control:data.control,runId:data.token,pipeName:data.pipeName,
   readyName:data.readyName,key:data.key,childPid:process.pid,serverPid:data.server.pid,port:port2,signal:data.signal.buffer},
   transferList:[port2],execArgv:[],env:cleanEnvironment(),stdout:true,stderr:true});
 }catch{port1.close();port2.close();throw new Error('offline_probe_thread_failed');}
 // Worker diagnostics never expose arbitrary source, exceptions, or key material.
 data.worker.stdout.on('data',()=>{});data.worker.stderr.on('data',()=>{});
 data.workerExited=new Promise(resolve=>{
  data.worker.on('error',()=>{data.failed=true;});
  data.worker.once('exit',code=>{data.workerExitResult={code};if(!data.workerClosing)data.failed=true;resolve(data.workerExitResult);});
 });
}
function probe(data,checkDatabase=true,action='probe') {
 if(data.closed||data.failed||data.exitResult||data.workerExitResult||!data.server?.pid||!data.worker)fail('offline_probe_unavailable');
 const request=validateProbeRequest({version:1,run_id:data.token,child_pid:process.pid,server_pid:data.server.pid,
  sequence:++data.sequence,challenge:randomBytes(32).toString('hex'),check_database:checkDatabase,action});
 try{
  // Same fixed Node process and Job, private channel, fresh native proof. The
  // synchronous wait has one absolute 15s deadline, including first-use startup.
  data.port.postMessage({id:request.sequence,request});
  const response=receiveProbeReply(data.port,data.signal,request.sequence);
  verifyProbeResponse(response,data.key,request);
 }catch{data.failed=true;fail('offline_probe_failed');}
}
// Exported only for the fixed runtime child. A caller-supplied JSON object cannot
// satisfy the native Job membership and original-process/lock evidence.
export function createOfflineLease({control,token,config,cleanCloseReceipt,origin='canonical_restart'}) {
 assertNode();
 if(process.platform!=='win32' || process.argv[1]!==fileURLToPath(new URL('./runtime_child.mjs',import.meta.url))
  || process.argv[2]!==control || process.argv[3]!==token) fail('fixed_supervisor_child_required');
 verifyRelease(config.release,config.manifest_sha256);
 const onDisk=JSON.parse(readFileSync(plainPath(path.join(control,'launch.json'))));
 if(JSON.stringify(onDisk)!==JSON.stringify(config)) fail('offline_launch_unbound');
 let settings;try{settings=JSON.parse(readFileSync(plainPath(config.configuration_file)));}catch{fail('config_json_rejected');}
 const custodyDirectory=plainPath(settings.recovery_custody_directory);
 const data={control,token,config,databasePath:path.join(config.state,'i-core.sqlite'),custodyDirectory,cleanCloseReceipt,origin};
 const lease=Object.freeze({}); leases.set(lease,data);
 try{startTransport(data);probe(data,origin!=='empty_provision');return lease;}
 catch{data.failed=true;data.server?.kill();fail('offline_probe_failed');}
}
// The fixed parent owns an actual FileShare.None handle throughout the child
// lifetime. A leftover filename is harmless after kernel handle cleanup.
export function withOfflineCustodyLock(lease,{databasePath,custodyDirectory},work){
 const data=leases.get(lease);
 if(!data||data.databasePath!==databasePath||data.custodyDirectory!==custodyDirectory)fail('trusted_custody_lease_required');
 probe(data);return work();
}
export function assertOfflineLease(lease,{databasePath,phase}) {
 const data=leases.get(lease);
 if(!data || data.databasePath!==databasePath || typeof phase!=='string') fail('trusted_offline_lease_required');
 plainPath(databasePath);
 const transactionPhases=new Set(['domain_before_backup','domain_before_ddl','domain_before_commit',
  'activity_after_ddl','activity_before_commit','activity_after_commit']);
 // Only reviewed migration checkpoints own a SQLite handle here. At these
 // checkpoints the Core holds its own transaction; retain OS identity/lock checks.
 probe(data,!transactionPhases.has(phase));
 return {databasePath,checkedAt:Date.now(),allCoreWritersStopped:true,origin:data.origin,cleanCloseReceipt:data.cleanCloseReceipt};
}
// Called only after a fixed child's store.close() has returned and a native
// exclusive DB-handle probe succeeds. Update never changes the branded lease.
export function recordClosedDatabase(lease,receipt) {
 const data=leases.get(lease); if(!data || receipt.databasePath!==data.databasePath) fail('trusted_offline_lease_required');
 probe(data); data.cleanCloseReceipt=Object.freeze({...receipt});
}

async function waitExit(data,milliseconds){
 let timer;try{return await Promise.race([data.exited,new Promise(resolve=>{timer=setTimeout(()=>resolve(null),milliseconds);})]);}
 finally{clearTimeout(timer);}
}
async function stopWorker(data){
 if(!data.worker)return true;
 data.workerClosing=true;Atomics.store(data.signal,1,1);
 try{
  // terminate() resolves only after the real thread exit. Its intentional exit
  // code is 1; an earlier unexpected exit/error has already poisoned the lease.
  await data.worker.terminate();
  const result=await data.workerExited;
  return !!result&&[0,1].includes(result.code);
 }catch{return false;}
 finally{data.port.close();}
}
function closeTransport(data){
 if(data.closePromise)return data.closePromise;
 data.closePromise=(async()=>{
  let clean=!data.failed;
  try{if(!data.exitResult&&!data.failed)probe(data,false,'stop');else if(data.exitResult)clean=false;}
  catch{clean=false;}
  data.closed=true;
  if(!clean&&!data.exitResult)data.server.kill();
  const workerStopped=await stopWorker(data);if(!workerStopped)clean=false;
  let result=await waitExit(data,5000);
  if(!result){clean=false;data.server.kill();result=await waitExit(data,5000);}
  data.key=null;
  if(result&&workerStopped)ownedTransports.delete(data);
  if(data.failed)clean=false;
  if(!clean||!result||result.code!==0)fail('offline_probe_cleanup_failed');
 })();
 return data.closePromise;
}
// Always await in runtime_child shutdown finally, including undefined after a
// failed createOfflineLease. Only ChildProcess objects created here are reaped.
export async function closeOfflineLease(lease){
 if(lease!==undefined&&lease!==null){const data=leases.get(lease);if(!data)fail('trusted_offline_lease_required');await closeTransport(data);return;}
 const results=await Promise.allSettled([...ownedTransports].map(closeTransport));
 if(results.some(result=>result.status==='rejected'))fail('offline_probe_cleanup_failed');
}
