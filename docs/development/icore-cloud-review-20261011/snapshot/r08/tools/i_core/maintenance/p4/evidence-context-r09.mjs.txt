// Production composition must be launched by the native pinned parent.
import {performance} from 'node:perf_hooks';
import {createEvidenceContract,canonical,sha256} from './evidence-contract-r08.mjs';
import {openPinnedParentBridge} from './evidence-parent-bridge-r09.mjs';
export async function prepareP4EvidenceContext(){
 const host=await openPinnedParentBridge(),p=host.policy;
 const clock={mono:()=>performance.now(),utcMs:()=>Date.now(),sleep:ms=>new Promise(resolve=>setTimeout(resolve,ms))};
 const contract=createEvidenceContract({...host,clock});
 const request={authorization:{attemptId:p.attemptId},bindingSha256:p.bindingSha256,p3ReceiptSha256:p.p3ReceiptSha256,approvalSha256:p.approvalSha256,scope:'p4-health-only',requestCount:20};
 const verified=await contract.verifyAuthorization(request);
 const id=name=>{const a=p.inventory.filter(x=>x.id===name);if(a.length!==1)throw new Error('evidence_inventory');return a[0].sha256;};
 const source=id('transport-source'),verifier=id('verifier-source'),endpoint=id('transport-endpoints'),node=p.inventory.find(x=>x.role==='node')?.sha256;
 const review=Object.freeze({reviewed:true,sourceSha256:source,bindingSha256:p.bindingSha256,verifierSha256:verifier});
 let transportUsed=false,healthUsed=false;
 const expected=host.expected;
 if(!expected||expected.bindingSha256!==p.bindingSha256||expected.identity?.p3ReceiptSha256!==p.p3ReceiptSha256||expected.identity?.approvalSha256!==p.approvalSha256)throw new Error('identity_binding');
 const uuid=x=>{const m=/^(?:session|control)-([0-9a-f]{32})$/.exec(x);if(!m)return x;const h=m[1];return h.slice(0,8)+'-'+h.slice(8,12)+'-'+h.slice(12,16)+'-'+h.slice(16,20)+'-'+h.slice(20);};
 const reduced={sessionId:uuid(expected.identity.sessionId),controlId:uuid(expected.identity.controlId),runGuid:expected.identity.task.registeredGuid,
 host:{pid:expected.identity.processes.host.pid,startedTicks:expected.identity.processes.host.startedTicks},
 core:{pid:expected.identity.processes.core.pid,startedTicks:expected.identity.processes.core.startedTicks},
 mcp:{pid:expected.identity.processes.mcp.pid,startedTicks:expected.identity.processes.mcp.startedTicks}};
 if(canonical(reduced)!==canonical(p.identity))throw new Error('identity_binding');
 return Object.freeze({
 review,authorization:request.authorization,expected,clock,observeIdentity:host.observeIdentity,endpointAllowlist:host.endpointAllowlist,
 async verifyTransportAuthorization(q){
  if(transportUsed||q?.scope!=='p4-health-only'||q.maxRequests!==20||q.sourceSha256!==source||q.nodeSha256!==node||q.endpointManifestSha256!==endpoint||canonical(q.authorization)!==canonical(request.authorization)||canonical(q.review)!==canonical(review))throw new Error('authorization_rejected');
  transportUsed=true;return {allowed:true,mode:verified.mode,bindingSha256:p.bindingSha256,sourceSha256:source,endpointManifestSha256:endpoint};
 },
 async verifyAuthorization(q){if(healthUsed||!transportUsed||canonical(q)!==canonical(request))throw new Error('authorization_rejected');healthUsed=true;return verified;},
 appendReceipt:record=>contract.appendReceipt(verified.capability,record),complete:host.complete
 });
}
