// Manual diagnostic, not a CI pass/fail stress test. Counts vary with scheduling.
// Usage: node tools/i_core/test_fixtures/release_schema6/probe_control_path_churn.mjs [iterations=1000]
import {Worker,isMainThread,parentPort,workerData} from 'node:worker_threads';
import {once} from 'node:events';
import {readFileSync,writeFileSync,renameSync,unlinkSync,rmSync,existsSync,lstatSync,readdirSync,realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {plainPath} from '../../release_schema6/package.mjs';
import {syntheticRoot} from './synthetic_paths.mjs';

const codes=new Set(['ENOENT','EPERM','EACCES','EBUSY','EINVAL','UNKNOWN','ENOTDIR','EIO','ENOSYS','EISDIR','EBADF','ENAMETOOLONG','EINTR','EMFILE','ENFILE','ESTALE','input_missing_or_aliased','linked_path_rejected']);
const syscalls=new Set(['open','read','realpath','lstat','stat','unlink','rename']);
function count(counts,stage,error){const key=[stage,codes.has(error?.code)?error.code:'OTHER',syscalls.has(error?.syscall)?error.syscall:'other'].join('|');counts[key]=(counts[key]??0)+1;}

if(!isMainThread){
 const signal=new Int32Array(workerData.signal),counts={},deadline=Date.now()+20000;
 let successes=0,ignored=0,controlFailures=0;
 parentPort.postMessage('ready');
 while(!Atomics.load(signal,0)&&Date.now()<deadline){
  let stage='plainPath';
  try{
   const target=workerData.mode==='publish-only'?workerData.target+'-'+Atomics.load(signal,1):workerData.target;
   const resolved=plainPath(target);stage='readFileSync';readFileSync(resolved,'utf8');successes++;
  }catch(error){
   count(counts,stage,error);
   // Match runtime_child's current missing-file handling without changing it.
   if(error.code==='ENOENT'||error.code==='input_missing_or_aliased')ignored++;else controlFailures++;
  }
 }
 parentPort.postMessage({mode:workerData.mode,successes,ignored,controlFailures,counts,readerBudgetExpired:!Atomics.load(signal,0)});
}else{
 async function run(){
  const iterations=Number(process.argv[2]??1000);
  if(process.argv.length>3||!Number.isInteger(iterations)||iterations<1||iterations>5000)throw Error('iterations_rejected');
  const parent=realpathSync.native(tmpdir()),root=syntheticRoot('schema6-control-churn-',parent),results=[];
  try{
   for(const mode of ['unlink-recreate','unlink-rename','publish-only','stable-read']){
    const target=path.join(root,mode),pending=target+'.pending',signal=new SharedArrayBuffer(8),writerErrors={};
    writeFileSync(mode==='publish-only'?target+'-0':target,'forged');
    const worker=new Worker(new URL(import.meta.url),{workerData:{mode,target,signal}});
    let writerOperations=0,writerBudgetExpired=false;
    try{
     await once(worker,'message');const done=once(worker,'message'),deadline=Date.now()+10000;
     for(let i=0;i<iterations;i++){
      if(Date.now()>=deadline){writerBudgetExpired=true;break;}
      try{
       if(mode==='publish-only'){
        const next=target+'-'+(i+1);writeFileSync(next+'.pending','a'.repeat(64));
        Atomics.store(new Int32Array(signal),1,i+1);renameSync(next+'.pending',next);
       }else if(mode==='stable-read'){readFileSync(target,'utf8');}
       else{
        unlinkSync(target);
        if(mode==='unlink-recreate')writeFileSync(target,'forged');
        else{writeFileSync(pending,'a'.repeat(64));renameSync(pending,target);}
       }
       writerOperations++;
      }catch(error){
       count(writerErrors,'writer',error);
       if(mode.startsWith('unlink-')&&!existsSync(target)){if(existsSync(pending))renameSync(pending,target);else writeFileSync(target,'forged');}
      }
     }
     Atomics.store(new Int32Array(signal),0,1);const [result]=await done;
     results.push({...result,writerOperations,writerErrors,writerBudgetExpired});
    }finally{Atomics.store(new Int32Array(signal),0,1);await worker.terminate();}
   }
  }finally{
   // No cleanup until our workers have exited; reject unexpected directories/links.
   if(path.dirname(root)!==parent||!/^schema6-control-churn-[a-zA-Z0-9]+$/.test(path.basename(root)))throw Error('cleanup_scope_rejected');
   plainPath(root);
   for(const name of readdirSync(root)){const file=plainPath(path.join(root,name));const stat=lstatSync(file);if(!stat.isFile()||stat.nlink!==1)throw Error('cleanup_shape_rejected');}
   rmSync(root,{recursive:true});
  }
  return {format:'schema6-control-path-churn-diagnostic-v1',nodeVersion:process.version,uvVersion:process.versions.uv,syntheticOnly:true,iterations,taskCreates:0,productionBytesChanged:false,results};
 }
 try{console.log(JSON.stringify(await run(),null,2));}
 catch(error){console.error(JSON.stringify({probeFailed:true,code:codes.has(error?.code)?error.code:'diagnostic_failed'}));process.exitCode=1;}
}
