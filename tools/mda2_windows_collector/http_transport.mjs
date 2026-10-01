import http from 'node:http';
import { randomBytes } from 'node:crypto';
import { reject } from './signals.mjs';
import { BOUNDED_ASYNC_TRANSPORT_V1 } from '../mda2_windows_queue/broker.mjs';

const TEST_AUTHORITY = Symbol('mda2-loopback-test-authority');
export const createLoopbackTestAuthority = () => Object.freeze({ marker:TEST_AUTHORITY, nonce:randomBytes(16).toString('hex') });

function fixedCode(error, fallback='transport_failed') {
  return /^[a-z_0-9]+$/.test(error?.message??'') ? error.message : fallback;
}

function validateReply(status, bytes, expectedEventId) {
  let body;
  try { body=JSON.parse(bytes.toString('utf8')); } catch { reject('transport_malformed_response'); }
  if(status>=300&&status<400)reject('transport_redirect_rejected');
  if(status===429||(status>=500&&status<=599))reject('transport_retryable');
  if(status===200){
    if(!body||Object.getPrototypeOf(body)!==Object.prototype||!Array.isArray(body.results)||body.results.length!==1)reject('transport_malformed_response');
    const result=body.results[0];
    if(!result||result.event_id!==expectedEventId||!['accepted','duplicate'].includes(result.status)
      ||typeof result.receipt_id!=='string'||!Number.isSafeInteger(result.server_sequence))reject('transport_identity_rejected');
    return body;
  }
  const code=body?.error?.code;
  if(typeof code!=='string'||!/^[a-z_0-9]+$/.test(code))reject('transport_malformed_response');
  return {code};
}

export function createLoopbackActivityTransport({baseUrl,probeToken,testAuthority,timeoutMs=5000,maxResponseBytes=16384,
  requestFactory=http.request}) {
  if(testAuthority?.marker!==TEST_AUTHORITY||typeof probeToken!=='string'||probeToken.length<17
    ||!Number.isSafeInteger(timeoutMs)||timeoutMs<1||!Number.isSafeInteger(maxResponseBytes)||maxResponseBytes<256
    ||typeof requestFactory!=='function') {
    reject('loopback_transport_rejected');
  }
  let endpoint;
  try {endpoint=new URL('/v1/core/activity/events',baseUrl);}catch{reject('loopback_transport_rejected');}
  const port=Number(endpoint.port);
  if(endpoint.protocol!=='http:'||endpoint.hostname!=='127.0.0.1'||!Number.isSafeInteger(port)||port<1||port>65535
    ||port===47841||endpoint.username||endpoint.password||endpoint.search||endpoint.hash)reject('loopback_transport_rejected');
  return Object.freeze({kind:BOUNDED_ASYNC_TRANSPORT_V1,prepare(binding){
    let request,settled=false,totalTimer,responseEnded=false,started=false,resolveExit,resolveCompletion,rejectCompletion;
    const exited=new Promise((resolve)=>{resolveExit=resolve;});
    const completion=new Promise((resolve,rejectPromise)=>{resolveCompletion=resolve;rejectCompletion=rejectPromise;});
    const finish=(fn,value)=>{if(settled)return;settled=true;clearTimeout(totalTimer);fn(value);};
    return{
      start(eventBytes){
        if(started)reject('transport_start_reused');started=true;
        let event;
        try{event=JSON.parse(eventBytes.toString('utf8'));}catch(error){
          finish(rejectCompletion,new Error('transport_event_rejected'));resolveExit({closed:true});throw error;
        }
        if(event.event_id!==`${binding.event_id_prefix}.${event.origin_sequence}`||event.source!==binding.source
          ||event.device_id!==binding.device_id||event.probe_id!==binding.probe_id){
          finish(rejectCompletion,new Error('transport_event_rejected'));resolveExit({closed:true});reject('transport_event_rejected');
        }
        const prefix=Buffer.from('{"events":['),suffix=Buffer.from(']}'),length=prefix.length+eventBytes.length+suffix.length;
        try{
          request=requestFactory({protocol:'http:',hostname:'127.0.0.1',port,path:'/v1/core/activity/events',method:'POST',agent:false,
            headers:{'X-Core-Protocol':'0.1','Authorization':`Bearer ${probeToken}`,'Content-Type':'application/json','Content-Length':length}},(response)=>{
            const chunks=[];let total=0;
            response.on('data',(chunk)=>{
              total+=chunk.length;
              if(total>maxResponseBytes){finish(rejectCompletion,new Error('transport_response_too_large'));response.destroy();return;}
              chunks.push(chunk);
            });
            response.on('error',(error)=>finish(rejectCompletion,new Error(fixedCode(error))));
            response.on('aborted',()=>finish(rejectCompletion,new Error('transport_response_aborted')));
            response.on('close',()=>{if(!responseEnded)finish(rejectCompletion,new Error('transport_response_aborted'));});
            response.on('end',()=>{
              responseEnded=true;
              try{
                if(!String(response.headers['content-type']??'').toLowerCase().startsWith('application/json'))reject('transport_content_type_rejected');
                finish(resolveCompletion,validateReply(response.statusCode??0,Buffer.concat(chunks),event.event_id));
              }catch(error){finish(rejectCompletion,new Error(fixedCode(error)));}
            });
          });
          request.on('error',(error)=>finish(rejectCompletion,new Error(fixedCode(error))));
          request.once('close',()=>resolveExit({closed:true}));
          request.setTimeout(Math.max(1,Math.min(timeoutMs,1000)),()=>request.destroy(new Error('transport_idle_timeout')));
          totalTimer=setTimeout(()=>request.destroy(new Error('transport_total_timeout')),timeoutMs);
          request.write(prefix);request.write(eventBytes);request.end(suffix);return true;
        }catch(error){
          finish(rejectCompletion,new Error(fixedCode(error)));
          if(request){try{if(!request.destroyed)request.destroy(error);}catch{/* absence of close remains unconfirmed */}}
          else resolveExit({closed:true});
          throw error;
        }
      },
      cancel(){if(!request||request.destroyed)return false;request.destroy(new Error('transport_cancelled'));return true;},
      completion,exited,
    };
  }});
}
