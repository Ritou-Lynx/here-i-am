import { isMainThread, workerData, MessagePort } from 'node:worker_threads';
import { lstatSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import { plainPath, fail } from './package.mjs';
import { publicLifecycleErrorCode } from './lifecycle/common.mjs';

const KIND='schema6-readonly-witness-v1';
const RESULT='schema6-readonly-witness-result-v1';
const COMPONENTS=new Set(['change_events','chat_messages','domain','activity']);
const KEYS=['kind','component','databasePath','priorWitness','context','resultPort','signalBuffer'].sort();
const plain=value=>value!==null&&typeof value==='object'&&Object.getPrototypeOf(value)===Object.prototype;
function validContext(component,context){
 if(component!=='activity')return context===null;
 if(!plain(context)||Object.keys(context).sort().join('|')!=='canonicalDatabasePath|floorMode|priorActivityFloor'
   ||typeof context.canonicalDatabasePath!=='string'||context.canonicalDatabasePath.length===0
   ||!['none','progress','exact'].includes(context.floorMode))return false;
 return context.floorMode==='none'?context.priorActivityFloor===null:plain(context.priorActivityFloor);
}

function fileIdentity(filename){
 plainPath(filename);
 const state=lstatSync(filename,{bigint:true});
 if(!state.isFile()||state.nlink!==1n)fail('unsafe_path');
 for(const suffix of ['-wal','-shm','-journal']){
  try{lstatSync(filename+suffix);}catch(error){if(error.code==='ENOENT')continue;throw error;}
  fail('state_sidecars_require_review');
 }
 return ['dev','ino','size','mtimeNs','ctimeNs','nlink'].map(key=>String(state[key])).join(':');
}

// This fixed entry receives only private in-memory capabilities. It has no
// custody key, no database write handle, and no authority to publish a floor.
async function run(){
 const port=workerData?.resultPort instanceof MessagePort?workerData.resultPort:null;
 const signal=workerData?.signalBuffer instanceof SharedArrayBuffer&&workerData.signalBuffer.byteLength===4
  ?new Int32Array(workerData.signalBuffer):null;
 const component=COMPONENTS.has(workerData?.component)?workerData.component:null;
 let message;
 try{
  if(!plain(workerData)||Object.keys(workerData).sort().join('|')!==KEYS.join('|')
    ||workerData.kind!==KIND||!component||!port||!signal||Atomics.load(signal,0)!==0
    ||(workerData.priorWitness!==null&&!plain(workerData.priorWitness))
    ||!validContext(component,workerData.context))fail('invalid_internal_arguments');
  // The fixed package dependency is loaded inside the private error boundary:
  // module initialization failures must wake a synchronously waiting parent.
  const {readRecoveryWitnessComponent}=await import('./recovery_adapter.mjs');
  const filename=workerData.databasePath,before=fileIdentity(filename);
  let result,db;
  try{
   db=new DatabaseSync(pathToFileURL(filename).href+'?mode=ro&immutable=1',{readOnly:true});
   db.exec('PRAGMA query_only=ON; PRAGMA trusted_schema=OFF');
   result=readRecoveryWitnessComponent(db,component,workerData.priorWitness,workerData.context);
   if(result?.then)fail('invalid_internal_arguments');
  } finally {db?.close();}
  if(fileIdentity(filename)!==before)fail('state_changed_during_preflight');
  if(Atomics.load(signal,0)!==0)fail('cancelled_before_store');
  message={kind:RESULT,component,ok:true,result};
 } catch(error){message={kind:RESULT,component,ok:false,errorCode:publicLifecycleErrorCode(error)};}
 if(!port||!signal){process.exitCode=1;port?.close();return;}
 try{
  port.postMessage(message);
  // A wake-up only says a result was posted. The parent must still validate
  // the private message, ok flag, its own deadline, and worker termination.
  // Cancellation (any nonzero value) is never overwritten by success.
  if(Atomics.compareExchange(signal,0,0,1)===0)Atomics.notify(signal,0);
 }catch{
  // Publishing can itself fail (for example a closed private transport).
  // The parent must reject promptly even while its event loop is blocked.
  process.exitCode=1;
  if(Atomics.compareExchange(signal,0,0,2)===0)Atomics.notify(signal,0);
 }finally{port.close();}
}

if(isMainThread)process.exitCode=1;
else await run();
