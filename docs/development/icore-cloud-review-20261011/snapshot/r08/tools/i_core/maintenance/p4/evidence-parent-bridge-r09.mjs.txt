// Only used by the Node entrypoint started under Invoke-P4PinnedSession.
// No filesystem or network imports. Native parent holds all artifact leases.
import {performance} from 'node:perf_hooks';
import {canonical,sha256} from './evidence-contract-r08.mjs';
export async function openPinnedParentBridge() {
 const input=process.stdin;input.setEncoding('utf8');
 let pending='',waiter=null,queue=[],ended=false,failed=false;const waiters=[];
 input.on('data',chunk=>{pending+=chunk;if(pending.length>4000000){failed=true;input.destroy();for(const w of waiters.splice(0))w.reject(new Error('evidence_protocol_rejected'));return;}let at;while((at=pending.indexOf('\n'))>=0){const line=pending.slice(0,at);pending=pending.slice(at+1);let v;try{v=JSON.parse(line);}catch{failed=true;continue;}const w=waiters.shift();if(w)w.resolve(v);else if(queue.length<4)queue.push(v);else failed=true;}});
 input.on('end',()=>{ended=true;for(const w of waiters.splice(0))w.reject(new Error('evidence_parent_eof'));});
 const next=()=>queue.length?Promise.resolve(queue.shift()):ended||failed?Promise.reject(new Error('evidence_protocol_rejected')):new Promise((resolve,reject)=>waiters.push({resolve,reject}));
 const send=value=>process.stdout.write(JSON.stringify(value)+'\n');
 const init=await next();if(init?.format!=='p4-locked-bootstrap-v1')throw new Error('evidence_bootstrap_rejected');
 const p=init.policy,b=init.bundle;
 for(const n of ['approval','p3','ledger','frames','claim','returned','enabled']){b[n].bytes=Buffer.from(b[n].bytesBase64,'base64');delete b[n].bytesBase64;}
 let issued=false,sequence=0;
 const bridge=Object.freeze({
  async withLockedArtifacts(spec,fn){if(issued)throw new Error('evidence_verify_repeat');issued=true;const result=await fn(b);
   send({op:'verified',allowed:result.allowed,policySha256:sha256(Buffer.from(canonical(p)+'\n')),identitySha256:sha256(Buffer.from(canonical(p.identity)+'\n'))});
   const ack=await next();if(ack?.op!=='verified-ack'||ack.allowed!==true)throw new Error('evidence_parent_rejected');return result;},
  async createNewReceipt({name,bytes,expectedSha256}){const id=String(sequence++);send({op:'write',requestId:id,name,bytesBase64:Buffer.from(bytes).toString('base64'),sha256:expectedSha256});
   const ack=await next();if(ack?.op!=='write-ack'||ack.requestId!==id)throw new Error('evidence_parent_rejected');return ack.result;}
 });
 // These flags are derived only from the pinned parent bridge path; live entry
 // must never construct them from user JSON. The real check occurs in native PS.
 const launcher=Object.freeze({policySha256:sha256(Buffer.from(canonical(p)+'\n')),codePinsVerified:true,nativeExeVerified:true,helperVerified:true,bridgeVerified:true,mode:p.mode});
 return {policy:p,bridge,launcher,expected:init.expected,endpointAllowlist:init.endpointAllowlist,async observeIdentity(spec){
 if(spec?.bindingSha256!==p.bindingSha256||spec.timeoutMs!==2500)throw new Error('identity_binding');
 send({op:'observe',bindingSha256:p.bindingSha256,timeoutMs:2500});const answer=await next();
 if(answer?.op!=='observe-ack'||!answer.snapshot)throw new Error('identity_binding');
 return {...answer.snapshot,observedMono:performance.now()};
},complete(healthResult){send({op:'complete',completed:true,healthResult});input.destroy();}};
}
