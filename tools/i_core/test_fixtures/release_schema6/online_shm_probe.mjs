import assert from 'node:assert/strict';
import {fork, spawnSync} from 'node:child_process';
import {once} from 'node:events';
import {createHash} from 'node:crypto';
import {existsSync,lstatSync,readFileSync,realpathSync,rmSync} from 'node:fs';
import {endianness} from 'node:os';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {DatabaseSync} from 'node:sqlite';
import {syntheticRoot} from './synthetic_paths.mjs';
import {cleanEnvironment,plainPath,verifyRelease} from '../../release_schema6/package.mjs';

const worker=fileURLToPath(new URL('./online_shm_worker.mjs',import.meta.url));
const sha=b=>createHash('sha256').update(b).digest('hex');
const expectedRows=[{id:1,value:'synthetic-one'},{id:2,value:'synthetic-two'}];
const u32=(b,n)=>endianness()==='LE'?b.readUInt32LE(n):b.readUInt32BE(n);
function file(filename){
  if(!existsSync(filename))return {exists:false};
  plainPath(filename);
  const st=lstatSync(filename,{bigint:true}), bytes=readFileSync(filename);
  return {exists:true,size:Number(st.size),sha256:sha(bytes),dev:String(st.dev),ino:String(st.ino),bytes};
}
function snapshot(filename){return Object.fromEntries(['db','wal','shm'].map((name,i)=>[name,file(filename+['','-wal','-shm'][i]) ]));}
function publicSnapshot(s){return Object.fromEntries(Object.entries(s).map(([name,{bytes,...meta}])=>[name,{...meta,...(name==='shm'&&bytes?.length>=136?{
  nativeEndian:endianness(),prefix136Hex:bytes.subarray(0,136).toString('hex'),headerHex:bytes.subarray(0,96).toString('hex'),mxFrame:u32(bytes,16),nBackfill:u32(bytes,96),aReadMark:[100,104,108,112,116].map(n=>u32(bytes,n)),
  lockRegionHex:bytes.subarray(120,128).toString('hex'),nBackfillAttempted:u32(bytes,128)
}:{})}]));}
function changes(a,b){return Object.fromEntries(['db','wal','shm'].map(name=>{
  const x=a[name],y=b[name];const changed=[];
  if(x.exists&&y.exists)for(let i=0;i<Math.max(x.bytes.length,y.bytes.length);i++)if(x.bytes[i]!==y.bytes[i])changed.push({offset:i,before:x.bytes[i]??null,after:y.bytes[i]??null});
  return [name,{existenceChanged:x.exists!==y.exists,identityChanged:x.exists&&y.exists?(x.dev!==y.dev||x.ino!==y.ino):null,bytesChanged:changed.length,changedBytes:changed}];
}));}
function equalFile(a,b,name){assert.deepEqual(publicSnapshot({[name]:a[name]})[name],publicSnapshot({[name]:b[name]})[name],name+' changed');}
async function message(child,type){
  return new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>done(new Error('synthetic worker IPC timeout')),10000);
    const onMessage=m=>{if(m.type===type)done(null,m);};
    const onExit=(code,signal)=>done(new Error(`worker exited before ${type}: ${code}/${signal}`));
    function done(error,value){clearTimeout(timer);child.off('message',onMessage);child.off('exit',onExit);error?reject(error):resolve(value);}
    child.on('message',onMessage);child.once('exit',onExit);
  });
}
async function status(child){const result=message(child,'status');child.send('status');return result;}
async function stop(child,force=false){if(child.exitCode!==null||child.signalCode!==null)return;const exited=once(child,'exit');force?child.kill('SIGKILL'):child.send('close');await exited;}
export async function reproduce({captureModule=fileURLToPath(new URL('../../release_schema6/automatic_backup.mjs',import.meta.url)),releaseRoot,manifestSha256,nodeSha256,repeats=1}={}){
  // Windows process creation may reinsert OS account plumbing; remove it before any database work.
  const allowed=cleanEnvironment(process.env);for(const key of Object.keys(process.env))if(!(key in allowed))delete process.env[key];
  assert.ok(Object.keys(process.env).length===Object.keys(allowed).length,'probe environment must be clean');
  const nodeHash=sha(readFileSync(process.execPath));if(nodeSha256)assert.equal(nodeHash,nodeSha256);
  let release=null;
  if(releaseRoot){release=verifyRelease(releaseRoot,manifestSha256);assert.equal(captureModule,path.join(releaseRoot,'tools','i_core','release_schema6','automatic_backup.mjs'));}
  const {captureConsistentSqlite}=await import(pathToFileURL(captureModule).href);
  const report={format:'schema6-online-shm-synthetic-v1',nodeVersion:process.version,sqliteVersion:process.versions.sqlite,platform:process.platform,nativeEndian:endianness(),nodeSha256:nodeHash,captureModuleSha256:sha(readFileSync(captureModule)),release,repeats,scenarios:[]};
  for(let iteration=1;iteration<=repeats;iteration++)for(const scenario of ['idle-writer-capture','closed-writer-capture','killed-writer-capture','idle-writer-select']){
    const root=syntheticRoot('schema6-online-shm-'),identity=lstatSync(root),source=path.join(root,'synthetic.sqlite'),destination=path.join(root,'copy.sqlite');
    let child;
    try{
      child=fork(worker,['writer',root,source],{execPath:process.execPath,execArgv:[],env:cleanEnvironment(),cwd:root,windowsHide:true,stdio:['ignore','ignore','pipe','ipc']});
      const ready=await message(child,'ready');
      assert.notEqual(ready.pid,process.pid);assert.equal(ready.sealed,true);assert.equal(ready.sqlCallsAfterReady,0);
      const readySnapshot=snapshot(source);assert.ok(readySnapshot.wal.exists&&readySnapshot.wal.size>32,'committed nonempty WAL required');
      if(scenario==='closed-writer-capture')await stop(child);
      if(scenario==='killed-writer-capture')await stop(child,true);
      const before=snapshot(source);
      const live=scenario.startsWith('idle-');
      const beforeStatus=live?await status(child):null;
      let action;
      if(scenario.endsWith('select')){
        const r=spawnSync(process.execPath,[worker,'reader',root,source],{env:cleanEnvironment(),cwd:root,windowsHide:true,encoding:'utf8',timeout:10000});
        assert.equal(r.status,0,r.stderr);action=JSON.parse(r.stdout);assert.equal(action.selectCalls,1);assert.notEqual(action.pid,ready.pid);assert.notEqual(action.pid,process.pid);assert.deepEqual(action.rows,expectedRows);
      }else action=await captureConsistentSqlite({sourcePath:source,destinationPath:destination});
      const after=snapshot(source),afterStatus=live?await status(child):null,diff=changes(before,after);
      let copyCorrect=null;
      if(!scenario.endsWith('select')){const copy=new DatabaseSync(pathToFileURL(destination).href+'?mode=ro&immutable=1',{readOnly:true});try{assert.deepEqual(copy.prepare('SELECT id,value FROM synthetic_payload ORDER BY id').all().map(r=>({...r})),expectedRows);copyCorrect=true;}finally{copy.close();}}
      const evidence={scenario,iteration,ready,writerAliveAfter:live?(child.exitCode===null&&child.signalCode===null):false,beforeStatus,afterStatus,readySnapshot:publicSnapshot(readySnapshot),before:publicSnapshot(before),after:publicSnapshot(after),diff,copyCorrect,action};
      report.scenarios.push(evidence);
      // Emit evidence before assertions: a failed reproduction is never hidden by retries.
      process.stdout.write(JSON.stringify({evidence})+'\n');
      equalFile(before,after,'db');
      if(scenario!=='closed-writer-capture')equalFile(before,after,'wal');
      if(live){
        assert.deepEqual(beforeStatus,afterStatus);assert.equal(afterStatus.sqlCallsAfterReady,0);assert.equal(afterStatus.backgroundSql,false);assert.equal(evidence.writerAliveAfter,true);
        assert.equal(diff.shm.existenceChanged,false);assert.equal(diff.shm.identityChanged,false);assert.equal(before.shm.size,after.shm.size);
        assert.ok(diff.shm.bytesChanged>0,'SHM did not change; report this negative result');
        assert.ok(diff.shm.changedBytes.every(x=>x.offset>=100&&x.offset<120),'unexpected SHM change outside aReadMark');
        assert.equal(evidence.before.shm.headerHex,evidence.after.shm.headerHex);
        assert.equal(evidence.after.shm.aReadMark[1],evidence.after.shm.mxFrame);
      }
    }finally{
      if(child)await stop(child,true);
      plainPath(root);const now=lstatSync(root);assert.equal(realpathSync.native(root),root);assert.equal(now.dev,identity.dev);assert.equal(now.ino,identity.ino);assert.match(path.basename(root),/^schema6-online-shm-/);
      rmSync(root,{recursive:true,force:true});
    }
  }
  return report;
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
  const options=JSON.parse(process.argv[2]??'{}');
  process.stdout.write(JSON.stringify({report:await reproduce(options)})+'\n');
}
