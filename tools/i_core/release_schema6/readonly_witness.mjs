import { Worker, MessageChannel, receiveMessageOnPort } from 'node:worker_threads';
import { performance } from 'node:perf_hooks';
import { fail } from './package.mjs';

const handles=new WeakMap();
const components=['change_events','chat_messages','domain','activity'];
// The capability is private, never an options callback or a persisted proof.
// Every worker reads the entire immutable file and closes its SQLite handle
// before posting. The parent also hashes the file after all reads complete.
export function startReadonlyWitness(databasePath,priorWitness,activityContext={canonicalDatabasePath:databasePath,priorActivityFloor:null,floorMode:'none'}){
 const handle={},jobs=[];
 try{
  for(const component of components){
   const {port1,port2}=new MessageChannel(),signalBuffer=new SharedArrayBuffer(4),signal=new Int32Array(signalBuffer);
   const worker=new Worker(new URL('./recovery_witness_worker.mjs',import.meta.url),{
    workerData:{kind:'schema6-readonly-witness-v1',component,databasePath,priorWitness,context:component==='activity'?activityContext:null,resultPort:port2,signalBuffer},
    transferList:[port2],execArgv:[]});
   worker.on('error',()=>{if(Atomics.compareExchange(signal,0,0,2)===0)Atomics.notify(signal,0);});
   worker.on('exit',code=>{if(code!==0&&Atomics.compareExchange(signal,0,0,2)===0)Atomics.notify(signal,0);});
   worker.unref();port1.unref();jobs.push({worker,port:port1,signal,component});
  }
  handles.set(handle,{jobs,deadline:performance.now()+300000});return handle;
 }catch(error){for(const job of jobs){Atomics.store(job.signal,0,2);job.port.close();void job.worker.terminate();}throw error;}
}
export function collectReadonlyWitness(handle){
 const state=handles.get(handle);if(!state)fail('invalid_internal_arguments');
 const parts={};
 for(const job of state.jobs){
  let response;
  for(;;){
   const remaining=state.deadline-performance.now(),observed=Atomics.load(job.signal,0);
   if(remaining<=0||(observed!==0&&observed!==1))fail('recovery_witness_unavailable');
   response??=receiveMessageOnPort(job.port)?.message;
   if(observed===1&&response)break;
   // postMessage and the final success signal are distinct operations. Keep
   // an early message, but never accept it after cancellation or the deadline.
   Atomics.wait(job.signal,0,observed,Math.min(remaining,observed===1?1:remaining));
  }
  if(response.kind!=='schema6-readonly-witness-result-v1'||response.component!==job.component||typeof response.ok!=='boolean')fail('invalid_internal_arguments');
  if(!response.ok)fail(response.errorCode);
  if(!response.result||typeof response.result!=='object')fail('invalid_internal_arguments');
  parts[job.component]=response.result;
 }
 return parts;
}
export function closeReadonlyWitness(handle){
 const state=handles.get(handle);if(!state)return;handles.delete(handle);
 for(const job of state.jobs){Atomics.store(job.signal,0,2);Atomics.notify(job.signal,0);job.port.close();void job.worker.terminate();}
}
