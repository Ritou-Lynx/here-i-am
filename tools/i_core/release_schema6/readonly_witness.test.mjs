import assert from 'node:assert/strict';
import test from 'node:test';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';

// Exercise the actual parent protocol with test-local transport and clock.
// Only this independent source module substitutes imports/Worker construction;
// the shipped helper has no factory, clock, callback, or test capability.
async function protocol(t){
 const key='schema6-witness-protocol-'+randomUUID();
 const state={now:0,workers:[],ports:[],receiveCalls:0,waitCalls:0,onWait:null};
 class Port {
  constructor(){this.queue=[];this.closed=false;state.ports.push(this);}
  postMessage(message){this.peer.queue.push(message);}
  unref(){}
  close(){this.closed=true;}
 }
 class MessageChannel {constructor(){this.port1=new Port();this.port2=new Port();this.port1.peer=this.port2;this.port2.peer=this.port1;}}
 class Worker {
  constructor(url,options){assert.equal(url.href,new URL('./recovery_witness_worker.mjs',import.meta.url).href);this.data=options.workerData;this.signal=new Int32Array(this.data.signalBuffer);this.listeners={};this.terminated=false;state.workers.push(this);}
  on(event,callback){this.listeners[event]=callback;return this;}
  unref(){}
  terminate(){this.terminated=true;return Promise.resolve(0);}
  emit(event,value){this.listeners[event]?.(value);}
  post(message,signal=1){this.data.resultPort.postMessage(message);Atomics.store(this.signal,0,signal);}
 }
 state.transport={Worker,MessageChannel,receiveMessageOnPort(port){state.receiveCalls++;const message=port.queue.shift();return message===undefined?undefined:{message};}};
 state.performance={now:()=>state.now};
 state.atomics={load:Atomics.load,store:Atomics.store,compareExchange:Atomics.compareExchange,notify:Atomics.notify,
  wait(signal,index,value,timeout){state.waitCalls++;if(state.onWait)state.onWait(signal,index,value,timeout);else state.now+=timeout+1;return 'ok';}};
 globalThis[key]=state;t.after(()=>{delete globalThis[key];});
 const anchor=new URL('./readonly_witness.mjs',import.meta.url);let source=readFileSync(anchor,'utf8');
 source=source.replace("import { Worker, MessageChannel, receiveMessageOnPort } from 'node:worker_threads';",`const {Worker,MessageChannel,receiveMessageOnPort}=globalThis[${JSON.stringify(key)}].transport;`)
  .replace("import { performance } from 'node:perf_hooks';",`const {performance,atomics:Atomics}=globalThis[${JSON.stringify(key)}];`)
  .replace("new URL('./recovery_witness_worker.mjs',import.meta.url)",`new URL(${JSON.stringify(new URL('./recovery_witness_worker.mjs',import.meta.url).href)})`)
  .replace(/from '([^']+)'/g,(all,dependency)=>dependency.startsWith('.')?`from '${new URL(dependency,anchor).href}'`:all);
 const parent=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
 const context={canonicalDatabasePath:'synthetic-unused.sqlite',priorActivityFloor:null,floorMode:'none'};
 const handle=parent.startReadonlyWitness('synthetic-unused.sqlite',null,context);
 t.after(()=>parent.closeReadonlyWitness(handle));
 const success=worker=>({kind:'schema6-readonly-witness-result-v1',component:worker.data.component,ok:true,result:{sha256:'a'.repeat(64)}});
 const fill=()=>{for(const worker of state.workers)worker.post(success(worker));};
 return {state,parent,handle,success,fill,context};
}

test('queued success cannot bypass cancelled signal',async t=>{
 const f=await protocol(t);f.fill();Atomics.store(f.state.workers[0].signal,0,2);
 assert.throws(()=>f.parent.collectReadonlyWitness(f.handle),error=>error.code==='recovery_witness_unavailable');
 assert.equal(f.state.receiveCalls,0);
});
test('queued success cannot bypass expired deadline',async t=>{
 const f=await protocol(t);f.fill();f.state.now=300001;
 assert.throws(()=>f.parent.collectReadonlyWitness(f.handle),error=>error.code==='recovery_witness_unavailable');
 assert.equal(f.state.receiveCalls,0);
});
test('early post is retained until final CAS without consuming the message twice',async t=>{
 const f=await protocol(t);for(const worker of f.state.workers)worker.post(f.success(worker),0);
 f.state.onWait=(signal,index)=>{Atomics.compareExchange(signal,index,0,1);};
 const result=f.parent.collectReadonlyWitness(f.handle);
 assert.deepEqual(Object.keys(result),['change_events','chat_messages','domain','activity']);
 assert.equal(f.state.receiveCalls,4);assert.equal(f.state.waitCalls,4);
});
test('cancellation or deadline during post-to-CAS gap still rejects cached success',async t=>{
 for(const mode of ['cancel','expire']){
  const f=await protocol(t);for(const worker of f.state.workers)worker.post(f.success(worker),0);
  f.state.onWait=signal=>{if(mode==='cancel')Atomics.store(signal,0,2);else{f.state.now=300001;Atomics.store(signal,0,1);}};
  assert.throws(()=>f.parent.collectReadonlyWitness(f.handle),error=>error.code==='recovery_witness_unavailable');
 }
});
test('wrong component, malformed envelope and bounded component failures reject',async t=>{
 for(const mode of ['component','kind','ok','result','failure']){
  const f=await protocol(t);f.fill();const queue=f.state.workers[0].data.resultPort.peer.queue,message=queue[0];
  if(mode==='component')message.component='domain';
  if(mode==='kind')message.kind='untrusted';
  if(mode==='ok')message.ok='yes';
  if(mode==='result')message.result=null;
  if(mode==='failure'){message.ok=false;delete message.result;message.errorCode='recovery_history_diverged';}
  assert.throws(()=>f.parent.collectReadonlyWitness(f.handle),error=>error.code===(mode==='failure'?'recovery_history_diverged':'invalid_internal_arguments'));
 }
});
test('worker errors and failed exits cancel the pending component',async t=>{
 for(const event of ['error','exit']){
  const f=await protocol(t);f.state.workers[0].emit(event,event==='error'?new Error('synthetic'):1);
  assert.equal(Atomics.load(f.state.workers[0].signal,0),2);
  assert.throws(()=>f.parent.collectReadonlyWitness(f.handle),error=>error.code==='recovery_witness_unavailable');
 }
});
test('close cancels every worker, closes result ports and retires its private handle',async t=>{
 const f=await protocol(t);f.fill();f.parent.closeReadonlyWitness(f.handle);
 assert.equal(f.state.workers.length,4);
 for(const worker of f.state.workers){assert.equal(Atomics.load(worker.signal,0),2);assert.equal(worker.terminated,true);assert.equal(worker.data.resultPort.peer.closed,true);}
 assert.throws(()=>f.parent.collectReadonlyWitness(f.handle),error=>error.code==='invalid_internal_arguments');
 assert.doesNotThrow(()=>f.parent.closeReadonlyWitness(f.handle));
});

test('only the activity worker receives the exact read-only floor context',async t=>{
 const f=await protocol(t);
 assert.deepEqual(f.state.workers.map(worker=>worker.data.component),['change_events','chat_messages','domain','activity']);
 for(const worker of f.state.workers){
  assert.deepEqual(Object.keys(worker.data).sort(),['component','context','databasePath','kind','priorWitness','resultPort','signalBuffer']);
  assert.deepEqual(worker.data.context,worker.data.component==='activity'?f.context:null);
 }
});
