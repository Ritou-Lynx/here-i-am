import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { EventEmitter, once } from 'node:events';
import test from 'node:test';
import { MessageChannel, Worker } from 'node:worker_threads';
import { exchangeProbeFrame, MAX_PROBE_FRAME, readProbeFrame, receiveProbeReply, signProbeFrame, validateProbeRequest, verifyProbeResponse, verifyProbeReady, waitProbeReady } from './offline_probe_client.mjs';

const key=randomBytes(32).toString('hex');
const request=(sequence=1)=>({version:1,run_id:'a'.repeat(64),child_pid:123,server_pid:456,
 sequence,challenge:randomBytes(32).toString('hex'),check_database:true,action:'probe'});
const response=value=>signProbeFrame({...value,checked:true},key,'response');
const identity={runId:'a'.repeat(64),childPid:123,serverPid:456,pipeName:'synthetic-pipe'};
const ready=sequence=>({version:1,run_id:identity.runId,child_pid:identity.childPid,server_pid:identity.serverPid,pipe_name:identity.pipeName,sequence});

test('authenticated readiness binds the exact next sequence and original peer identities',()=>{
 assert.equal(verifyProbeReady(signProbeFrame(ready(1),key,'ready'),key,identity,2),true);
 assert.equal(verifyProbeReady(signProbeFrame(ready(0),key,'ready'),key,identity,2),false);
 for(const changed of [{...ready(1),sequence:2},{...ready(1),sequence:-1},{...ready(1),server_pid:789},
  {...ready(1),child_pid:789},{...ready(1),run_id:'b'.repeat(64)},{...ready(1),pipe_name:'different'},
  {...ready(1),extra:true}]){
  assert.throws(()=>verifyProbeReady(signProbeFrame(changed,key,'ready'),key,identity,2),/offline_probe_server_unbound/);
 }
 assert.throws(()=>verifyProbeReady(signProbeFrame(ready(1),key),key,identity,2),/offline_probe_authentication_failed/);
});
test('next request waits through the pipe recreation gap without connecting or reusing proof',async()=>{
 const signal=new Int32Array(new SharedArrayBuffer(8));let current=0,reads=0;
 const advance=setTimeout(()=>{current=1;},35);
 try{
  await waitProbeReady({readReady:()=>{reads++;return signProbeFrame(ready(current),key,'ready');},key,identity,sequence:2,signal,deadline:performance.now()+1000});
  assert.ok(reads>1);assert.equal(current,1);
 }finally{clearTimeout(advance);}
});
test('readiness timeout, future sequence, cancellation and wrong authentication fail closed',async()=>{
 for(const mode of ['timeout','future','cancel','auth']){
  const signal=new Int32Array(new SharedArrayBuffer(8));if(mode==='cancel')Atomics.store(signal,1,1);
  await assert.rejects(waitProbeReady({readReady:()=>signProbeFrame(ready(mode==='future'?2:0),mode==='auth'?'b'.repeat(64):key,'ready'),
   key,identity,sequence:2,signal,deadline:performance.now()+20}),/^Error: offline_probe_(timeout|server_unbound|thread_failed|authentication_failed)$/);
 }
});

test('probe response requires fresh sequence/challenge and the exact DB-check mode and identities',()=>{
 const first=request(),frame=response(first);
 assert.equal(verifyProbeResponse(frame,key,first).checked,true);
 for(const changed of [request(2),{...first,challenge:'b'.repeat(64)},{...first,check_database:false},
  {...first,child_pid:789},{...first,server_pid:789},{...first,run_id:'c'.repeat(64)}]){
  assert.throws(()=>verifyProbeResponse(frame,key,changed),/offline_probe_response_rejected/);
 }
});
test('probe authentication separates ready/request/response and rejects tampered content or key',()=>{
 const value=request(),frame=response(value);
 assert.throws(()=>verifyProbeResponse(frame,randomBytes(32).toString('hex'),value),/offline_probe_authentication_failed/);
 assert.throws(()=>verifyProbeResponse(signProbeFrame({...value,checked:true},key,'request'),key,value),/offline_probe_authentication_failed/);
 const changed=JSON.parse(frame);changed.payload=JSON.stringify({...value,checked:false});
 assert.throws(()=>verifyProbeResponse(JSON.stringify(changed),key,value),/offline_probe_authentication_failed/);
 assert.throws(()=>readProbeFrame(frame,key,'ready'),/offline_probe_authentication_failed/);
});
test('authenticated failure, unexpected fields, arbitrary commands and invalid sequences reject',()=>{
 const value=request();
 for(const body of [{...value,checked:false},{...value,checked:true,path:'synthetic-path'},null]){
  assert.throws(()=>verifyProbeResponse(signProbeFrame(body,key,'response'),key,value),/offline_probe_response_rejected/);
 }
 for(const body of [{...value,action:'execute'},{...value,phase:'arbitrary-code'},{...value,sequence:0},
  {...value,sequence:Number.MAX_SAFE_INTEGER+1},{...value,check_database:1},{...value,action:'stop'}]){
  assert.throws(()=>validateProbeRequest(body),/offline_probe_protocol_rejected/);
 }
 assert.equal(validateProbeRequest({...value,action:'stop',check_database:false}).action,'stop');
});
test('malformed or oversized frame rejects before it can authorize a probe',()=>{
 for(const frame of ['{',JSON.stringify({payload:'{}',authentication:'x'}),'x'.repeat(MAX_PROBE_FRAME+1)]){
  assert.throws(()=>readProbeFrame(frame,key),/offline_probe_protocol_rejected/);
 }
});

// In-memory socket only: these tests create no pipe, OS process, lease or DB.
function socketFactory(onWrite){
 let socket;
 return {connect(){
  socket=new EventEmitter();socket.destroyed=false;socket.setEncoding=()=>{};
  socket.destroy=()=>{socket.destroyed=true;};socket.write=value=>onWrite(socket,value);
  queueMicrotask(()=>socket.emit('connect'));return socket;
 },get socket(){return socket;}};
}
test('transport reads fragmented response and closes the only connection',async()=>{
 const value=request(),frame=response(value),fake=socketFactory((socket,input)=>{
  assert.equal(input,signProbeFrame(value,key)+'\n');
  queueMicrotask(()=>{socket.emit('data',frame.slice(0,10));socket.emit('data',frame.slice(10)+'\n');});
 });
 const actual=await exchangeProbeFrame('synthetic-pipe',signProbeFrame(value,key),{connect:fake.connect});
 assert.equal(actual,frame);assert.equal(fake.socket.destroyed,true);
});
test('transport timeout fails closed without retrying or returning cached success',async()=>{
 let writes=0;const fake=socketFactory(()=>{writes++;});
 await assert.rejects(exchangeProbeFrame('synthetic-pipe','synthetic-frame',{connect:fake.connect,timeout:10}),/offline_probe_timeout/);
 assert.equal(writes,1);assert.equal(fake.socket.destroyed,true);
});
test('transport rejects truncation, extra frames, overflow and redacts underlying errors',async()=>{
 for(const outcome of ['end','extra','overflow','error']){
  const fake=socketFactory(socket=>queueMicrotask(()=>{
   if(outcome==='end')socket.emit('end');
   if(outcome==='extra')socket.emit('data','{}\n{}\n');
   if(outcome==='overflow')socket.emit('data','x'.repeat(MAX_PROBE_FRAME+2));
   if(outcome==='error')socket.emit('error',new Error('synthetic-secret-must-not-escape'));
  }));
  await assert.rejects(exchangeProbeFrame('synthetic-pipe','synthetic-frame',{connect:fake.connect}),error=>{
   assert.match(error.message,/^offline_probe_(transport_failed|protocol_rejected)$/);return true;
  });
  assert.equal(fake.socket.destroyed,true);
 }
});

// Real small worker threads, private channels only: no native helper, files, DB
// or sockets. Exercise the synchronous main-thread wait and actual termination.
async function threadFixture(t,mode){
 const {port1,port2}=new MessageChannel(),signal=new Int32Array(new SharedArrayBuffer(8));
 const worker=new Worker(`
  const {parentPort,workerData}=require('node:worker_threads');
  const {port,mode,buffer}=workerData,signal=new Int32Array(buffer);
  port.on('message',message=>{
   if(mode==='silent')return;
   const reply={id:mode==='wrong-id'?message.id+1:message.id,ok:true,response:'reply-'+message.id};
   port.postMessage(reply);Atomics.add(signal,0,1);Atomics.notify(signal,0);
  });
  parentPort.postMessage('started');
  if(mode==='die')process.exit(0);
 `,{eval:true,execArgv:[],workerData:{mode,port:port2,buffer:signal.buffer},transferList:[port2]});
 let workerError=false;worker.on('error',()=>{workerError=true;});
 const exited=new Promise(resolve=>worker.once('exit',code=>resolve(code)));
 const ready=once(worker,'message');let closing;
 const close=()=>closing??=(async()=>{await worker.terminate();const code=await exited;port1.close();return code;})();
 t.after(close);await ready;
 return {worker,port:port1,signal,exited,close,error:()=>workerError};
}
test('private thread replies wake the main thread and never reuse the previous request',async t=>{
 const f=await threadFixture(t,'reply');
 for(const id of [1,2]){
  f.port.postMessage({id});assert.equal(receiveProbeReply(f.port,f.signal,id,1000),'reply-'+id);
 }
 assert.equal(await f.close(),1);assert.equal(f.worker.threadId,-1);assert.equal(f.error(),false);
});
test('thread reply with the wrong request identity fails closed',async t=>{
 const f=await threadFixture(t,'wrong-id');f.port.postMessage({id:1});
 assert.throws(()=>receiveProbeReply(f.port,f.signal,1,1000),/offline_probe_thread_failed/);
});
test('silent thread times out, records cancellation, and is actually terminated during cleanup',async t=>{
 const f=await threadFixture(t,'silent');f.port.postMessage({id:1});
 assert.throws(()=>receiveProbeReply(f.port,f.signal,1,20),/offline_probe_timeout/);
 assert.equal(Atomics.load(f.signal,1),1);
 assert.throws(()=>receiveProbeReply(f.port,f.signal,2,20),/offline_probe_thread_failed/);
 assert.equal(await f.close(),1);assert.equal(f.worker.threadId,-1);
});
test('already dead thread cannot supply success and its exit is confirmed',async t=>{
 const f=await threadFixture(t,'die');assert.equal(await f.exited,0);
 assert.throws(()=>receiveProbeReply(f.port,f.signal,1,20),/offline_probe_timeout/);
 await f.close();assert.equal(f.worker.threadId,-1);
});
test('thread deadline cannot be disabled or raised beyond fifteen seconds',async t=>{
 const f=await threadFixture(t,'silent');
 for(const timeout of [0,-1,Infinity,15001])assert.throws(()=>receiveProbeReply(f.port,f.signal,1,timeout),/offline_probe_protocol_rejected/);
});
