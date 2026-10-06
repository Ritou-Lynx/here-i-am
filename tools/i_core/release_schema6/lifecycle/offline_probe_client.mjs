import { createHmac, timingSafeEqual } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import net from 'node:net';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { isMainThread, MessagePort, receiveMessageOnPort, workerData } from 'node:worker_threads';
import { plainPath, verifyRelease, fail } from '../package.mjs';
import { assertNode } from './common.mjs';

const HEX=/^[a-f0-9]{64}$/;
const REQUEST_KEYS='action,challenge,check_database,child_pid,run_id,sequence,server_pid,version';
export const MAX_PROBE_FRAME=8192;
export function validateProbeRequest(value){
 if(!value||Object.keys(value).sort().join(',')!==REQUEST_KEYS||value.version!==1
  ||!['probe','stop'].includes(value.action)||!HEX.test(value.run_id??'')||!HEX.test(value.challenge??'')
  ||!Number.isSafeInteger(value.sequence)||value.sequence<1||typeof value.check_database!=='boolean'
  ||!Number.isSafeInteger(value.child_pid)||value.child_pid<1||!Number.isSafeInteger(value.server_pid)||value.server_pid<1
  ||(value.action==='stop'&&value.check_database))fail('offline_probe_protocol_rejected');
 return value;
}
export function signProbeFrame(body,key,kind='request'){
 if(!HEX.test(key??'')||!['request','response','ready'].includes(kind))fail('offline_probe_protocol_rejected');
 const payload=JSON.stringify(body),authentication=createHmac('sha256',key).update('i-core-native-probe-'+kind+'-v1\0').update(payload).digest('hex');
 const frame=JSON.stringify({payload,authentication});
 if(Buffer.byteLength(frame)>MAX_PROBE_FRAME)fail('offline_probe_protocol_rejected');
 return frame;
}
export function readProbeFrame(frame,key,kind='response'){
 if(typeof frame!=='string'||Buffer.byteLength(frame)>MAX_PROBE_FRAME||!HEX.test(key??''))fail('offline_probe_protocol_rejected');
 let envelope;try{envelope=JSON.parse(frame);}catch{fail('offline_probe_protocol_rejected');}
 if(!envelope||Object.keys(envelope).sort().join(',')!=='authentication,payload'||typeof envelope.payload!=='string'
  ||!HEX.test(envelope.authentication??''))fail('offline_probe_protocol_rejected');
 const expected=createHmac('sha256',key).update('i-core-native-probe-'+kind+'-v1\0').update(envelope.payload).digest();
 if(!timingSafeEqual(Buffer.from(envelope.authentication,'hex'),expected))fail('offline_probe_authentication_failed');
 try{return JSON.parse(envelope.payload);}catch{fail('offline_probe_protocol_rejected');}
}
export function verifyProbeResponse(frame,key,request){
 validateProbeRequest(request);
 const value=readProbeFrame(frame,key);
 if(!value||Object.keys(value).sort().join(',')!=='action,challenge,check_database,checked,child_pid,run_id,sequence,server_pid,version')fail('offline_probe_response_rejected');
 if(value.checked!==true||Object.keys(request).some(key=>value[key]!==request[key]))fail('offline_probe_response_rejected');
 return value;
}
export function verifyProbeReady(frame,key,identity,sequence){
 const ready=readProbeFrame(frame,key,'ready');
 if(!ready||Object.keys(ready).sort().join(',')!=='child_pid,pipe_name,run_id,sequence,server_pid,version'||ready.version!==1
  ||ready.run_id!==identity.runId||ready.pipe_name!==identity.pipeName||ready.child_pid!==identity.childPid||ready.server_pid!==identity.serverPid
  ||!Number.isSafeInteger(sequence)||sequence<1||!Number.isSafeInteger(ready.sequence)||ready.sequence<0||ready.sequence>=sequence)fail('offline_probe_server_unbound');
 return ready.sequence===sequence-1;
}
export async function waitProbeReady({readReady,key,identity,sequence,signal,deadline}){
 if(!Number.isFinite(deadline)||deadline-performance.now()>15000)fail('offline_probe_protocol_rejected');
 for(;;){
  if(Atomics.load(signal,1))fail('offline_probe_thread_failed');
  if(performance.now()>=deadline)fail('offline_probe_timeout');
  const frame=readReady();
  if(frame!==null&&verifyProbeReady(frame,key,identity,sequence))return;
  // A stale authenticated sequence is only a readiness wait, never a reused
  // OS proof. A connection is attempted exactly once after this request's ready.
  await new Promise(resolve=>setTimeout(resolve,Math.min(10,Math.max(1,deadline-performance.now()))));
 }
}

// One connection, one bounded frame. No success cache, retry, or fallback path.
export function exchangeProbeFrame(pipe,frame,{timeout=15000,connect=net.createConnection}={}){
 return new Promise((resolve,reject)=>{
  let socket,received='',settled=false;
  const finish=(error,value)=>{if(settled)return;settled=true;clearTimeout(timer);socket?.destroy();error?reject(new Error(error)):resolve(value);};
  const timer=setTimeout(()=>finish('offline_probe_timeout'),timeout);
  try{
   socket=connect(pipe);
   socket.setEncoding('utf8');
   socket.on('connect',()=>socket.write(frame+'\n'));
   socket.on('data',chunk=>{
    received+=chunk;
    if(Buffer.byteLength(received)>MAX_PROBE_FRAME+1)return finish('offline_probe_protocol_rejected');
    const newline=received.indexOf('\n');
    if(newline>=0){if(newline!==received.length-1)return finish('offline_probe_protocol_rejected');finish(null,received.slice(0,newline));}
   });
   socket.on('error',()=>finish('offline_probe_transport_failed'));
   socket.on('end',()=>finish('offline_probe_transport_failed'));
   socket.on('close',()=>{if(!settled)finish('offline_probe_transport_failed');});
  }catch{finish('offline_probe_transport_failed');}
 });
}
// Read the notification counter BEFORE inspecting the private message queue.
// A response racing between either operation and wait changes the counter, so
// Atomics.wait cannot sleep through it. The deadline covers the entire request.
export function receiveProbeReply(port,signal,id,timeout=15000){
 if(!Number.isFinite(timeout)||timeout<=0||timeout>15000)fail('offline_probe_protocol_rejected');
 const deadline=performance.now()+timeout;
 for(;;){
  if(performance.now()>=deadline){Atomics.store(signal,1,1);fail('offline_probe_timeout');}
  if(Atomics.load(signal,1))fail('offline_probe_thread_failed');
  const observed=Atomics.load(signal,0),entry=receiveMessageOnPort(port);
  if(entry){
   const value=entry.message;
   if(!value||value.ok!==true||value.id!==id||Object.keys(value).sort().join(',')!=='id,ok,response'
    ||typeof value.response!=='string'||Buffer.byteLength(value.response)>MAX_PROBE_FRAME)fail('offline_probe_thread_failed');
   return value.response;
  }
  const remaining=deadline-performance.now();
  if(remaining<=0){Atomics.store(signal,1,1);fail('offline_probe_timeout');}
  Atomics.wait(signal,0,observed,remaining);
 }
}
function postReply(port,signal,message){
 port.postMessage(message);Atomics.add(signal,0,1);Atomics.notify(signal,0);
}
async function serveThread(){
 const {control,runId,pipeName,readyName,key,childPid,serverPid,port,signal:buffer}=workerData;
 if(workerData.mode!=='offline-probe-thread-v1'||!(port instanceof MessagePort)||!(buffer instanceof SharedArrayBuffer)||buffer.byteLength!==8
  ||!HEX.test(key??'')||!HEX.test(runId??'')||!/^ICoreSchema6Probe-[a-f0-9]{32}$/.test(pipeName??'')||readyName!==pipeName+'.ready.json'
  ||childPid!==process.pid||!Number.isSafeInteger(serverPid)||serverPid<1)fail('offline_probe_protocol_rejected');
 const signal=new Int32Array(buffer);
 // The worker shares the fixed Node process. Source/manifest verification runs
 // once before loading requests; modules remain in memory for its lifetime.
 assertNode();plainPath(control);
 const config=JSON.parse(readFileSync(plainPath(path.join(control,'launch.json'))));
 if(config.token!==runId||process.execPath.toLowerCase()!==path.join(config.release,'runtime','node.exe').toLowerCase()
  ||fileURLToPath(import.meta.url)!==path.join(config.lifecycle,'offline_probe_client.mjs'))fail('offline_probe_client_unbound');
 verifyRelease(config.release,config.manifest_sha256);
 const readyPath=path.join(control,readyName),identity={runId,pipeName,childPid,serverPid};
 let busy=false,sequence=0,failed=false;
 port.on('message',async message=>{
  try{
   if(failed||busy||Atomics.load(signal,1)||!message||Object.keys(message).sort().join(',')!=='id,request')fail('offline_probe_thread_failed');
   const request=validateProbeRequest(message.request);
   if(message.id!==request.sequence||request.sequence!==sequence+1||request.run_id!==runId||request.child_pid!==childPid||request.server_pid!==serverPid)fail('offline_probe_thread_failed');
   busy=true;
   const deadline=performance.now()+15000;
   // Each published readiness file is immutable. Replacing one shared path can
   // race Windows final-path validation; never weaken that path check or retry
   // a rejected path. The sequence chooses one exact owned control filename.
   const requestReadyPath=request.sequence===1?readyPath:path.join(control,pipeName+'.ready-'+(request.sequence-1)+'.json');
   await waitProbeReady({readReady:()=>existsSync(requestReadyPath)?readFileSync(plainPath(requestReadyPath),'utf8'):null,
    key,identity,sequence:request.sequence,signal,deadline});
   const remaining=deadline-performance.now();if(remaining<=0)fail('offline_probe_timeout');
   const response=await exchangeProbeFrame('\\\\.\\pipe\\'+pipeName,signProbeFrame(request,key),{timeout:remaining});
   verifyProbeResponse(response,key,request);
   if(Atomics.load(signal,1))fail('offline_probe_timeout');
   sequence=request.sequence;postReply(port,signal,{id:message.id,ok:true,response});
  }catch{
   failed=true;Atomics.store(signal,1,1);postReply(port,signal,{id:message?.id??0,ok:false});
  }finally{busy=false;}
 });
}
if(!isMainThread&&workerData?.mode==='offline-probe-thread-v1'&&process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{await serveThread();}catch{
  // No arbitrary exception text or secret crosses the private channel.
  if(workerData?.port instanceof MessagePort&&workerData.signal instanceof SharedArrayBuffer&&workerData.signal.byteLength===8){
   const signal=new Int32Array(workerData.signal);Atomics.store(signal,1,1);postReply(workerData.port,signal,{id:0,ok:false});
  }
  process.exitCode=2;
 }
}
