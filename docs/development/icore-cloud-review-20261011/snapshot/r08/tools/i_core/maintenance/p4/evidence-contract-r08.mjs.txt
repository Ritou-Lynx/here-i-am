// Reviewed candidate support only. No top-level filesystem/network/process operations.
// Native secure bridge contract is mandatory; never replace it with fs.readFile.
// A trusted launcher pins policy, native bridge, helper and native PowerShell bytes.
import {createHash} from 'node:crypto';
const HASH=/^[a-f0-9]{64}$/;
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const SAFEID=/^[a-z][a-z0-9_-]{0,47}$/;
const TASK='\\HereIAm-iCoreSchema6-chatgpt-20261009-f90058f2';
const OLD='\\HereIAm-iCoreSchema6-cleanclose-20261008-2c01de5b';
const deny=()=>{throw new Error('evidence_contract_rejected');};
export const sha256=b=>createHash('sha256').update(b).digest('hex');
export function canonical(v) {
 if(v===null||typeof v==='boolean'||typeof v==='string')return JSON.stringify(v);
 if(typeof v==='number'){if(!Number.isSafeInteger(v))deny();return JSON.stringify(v);}
 if(Array.isArray(v))return '['+v.map(canonical).join(',')+']';
 if(!v||Object.getPrototypeOf(v)!==Object.prototype)deny();
 return '{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+canonical(v[k])).join(',')+'}';
}
const bytes=v=>Buffer.from(canonical(v)+'\n','utf8');
const equal=(a,b)=>canonical(a)===canonical(b);
function keys(v,required){if(!v||Array.isArray(v)||!equal(Object.keys(v).sort(),[...required].sort()))deny();}
function bool(v){if(v!==true)deny();}
function hash(v){if(!HASH.test(v??''))deny();}
function guid(v){if(!UUID.test(v??''))deny();}
function pidticks(v){keys(v,['pid','startedTicks']);if(!Number.isSafeInteger(v.pid)||v.pid<1||!(/^[1-9][0-9]{10,18}$/).test(v.startedTicks??''))deny();}
function decodeCanonical(b,limit=262144) {
 if(!(b instanceof Uint8Array)||b.length<2||b.length>limit)deny();
 let s;try{s=new TextDecoder('utf-8',{fatal:true}).decode(b);}catch{deny();}
 let at=0,depth=0;
 const ws=()=>{while(/[ \r\n\t]/.test(s[at]??'!'))at++;};
 const str=()=>{if(s[at++]!=='"')deny();const begin=at-1;while(at<s.length){const c=s[at++];if(c==='"'){try{return JSON.parse(s.slice(begin,at));}catch{deny();}}if(c==='\\'){at++;if(s[at-1]==='u')at+=4;}else if(c.charCodeAt(0)<32)deny();}deny();};
 const val=()=>{ws();if(++depth>40)deny();const c=s[at];
 if(c==='{'){at++;ws();const seen=new Set();if(s[at]==='}')at++;else while(true){ws();const k=str();if(seen.has(k))deny();seen.add(k);ws();if(s[at++]!==':')deny();val();ws();const sep=s[at++];if(sep==='}')break;if(sep!==',')deny();}}
 else if(c==='['){at++;ws();if(s[at]===']')at++;else while(true){val();ws();const sep=s[at++];if(sep===']')break;if(sep!==',')deny();}}
 else if(c==='"')str();else{const m=/^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)/.exec(s.slice(at));if(!m)deny();at+=m[0].length;}depth--;};
 val();ws();if(at!==s.length)deny();try{return JSON.parse(s);}catch{deny();}
}
export function requestWhitelist(){
 const list=[{method:'GET',url:'http://127.0.0.1:47841/v1/core/health',body:null}];
 for(const base of ['http://127.0.0.1:47860','https://mcp.example.invalid']){
  for(const p of ['/.well-known/oauth-protected-resource','/.well-known/oauth-protected-resource/mcp','/.well-known/oauth-authorization-server'])list.push({method:'GET',url:base+p,body:null});
  list.push({method:'POST',url:base+'/mcp',body:'{"jsonrpc":"2.0","id":"p4-unauth","method":"tools/list","params":{}}'});
 }
 list.splice(5,0,{method:'GET',url:'http://127.0.0.1:47862/v1/remember/changes?after=0&limit=1',body:null});
 return list;
}
export const whitelistSha256=()=>sha256(bytes(requestWhitelist()));
const ROLES=['plan','source','manifest','core_config','mcp_config','backup_config','node','tool','native_bridge','owned_helper','powershell','entrypoint','session-window','launch','ready','mcp-start','identity-policy','task_projection','caller_context','identity_library','p3_producer','login_config','identity_policy','p3_frames','full_identity','activation_claim','run_returned'];
function validatePolicy(p) {
 const policyKeys=['format','mode','attemptId','bindingSha256','approvalSha256','p3ReceiptSha256','runLedgerSha256','planSha256','manifestSha256','outputRootId','ownerSid','identity','inventory','requestWhitelistSha256','notBeforeUtcMs','notAfterUtcMs'];
 if(p.format==='p4-evidence-policy-v2')policyKeys.push('evidenceNamespace');
 keys(p,policyKeys);
 if(!['p4-evidence-policy-v1','p4-evidence-policy-v2'].includes(p.format)||!['offline-synthetic','reviewed-live'].includes(p.mode))deny();
 guid(p.attemptId);for(const k of ['bindingSha256','approvalSha256','p3ReceiptSha256','runLedgerSha256','planSha256','manifestSha256','requestWhitelistSha256'])hash(p[k]);
 if(p.outputRootId!=='p4-private-evidence'||!/^S-1-5-21-[0-9-]+$/.test(p.ownerSid))deny();
 if(!Number.isSafeInteger(p.notBeforeUtcMs)||!Number.isSafeInteger(p.notAfterUtcMs)||p.notAfterUtcMs<=p.notBeforeUtcMs||p.notAfterUtcMs-p.notBeforeUtcMs>86400000)deny();
 keys(p.identity,['sessionId','controlId','runGuid','host','core','mcp']);
 for(const k of ['sessionId','controlId'])if(!UUID.test(p.identity[k]??''))deny();
 if(p.format==='p4-evidence-policy-v2')validateEvidenceNamespace(p.evidenceNamespace,p);
 guid(p.identity.runGuid);for(const k of ['host','core','mcp'])pidticks(p.identity[k]);
 if(!Array.isArray(p.inventory)||!p.inventory.length||p.inventory.length>256)deny();
 const ids=new Set(), roles=new Set();
 for(const a of p.inventory){keys(a,['id','role','sha256','maxBytes']);if(!SAFEID.test(a.id)||ids.has(a.id)||!ROLES.includes(a.role)||!Number.isSafeInteger(a.maxBytes)||a.maxBytes<1||a.maxBytes>268435456)deny();ids.add(a.id);roles.add(a.role);hash(a.sha256);}
 if(!ROLES.slice(0,11).every(r=>roles.has(r))||p.requestWhitelistSha256!==whitelistSha256())deny();
 for(const [r,h]of [['plan',p.planSha256],['manifest',p.manifestSha256]])if(!p.inventory.some(a=>a.role===r&&a.sha256===h))deny();
}
function validateDocuments(policy,approval,p3,ledger,utc) {
 keys(approval,['format','evidenceMode','approved','directHumanApproval','attemptId','planSha256','inventorySha256','requestWhitelistSha256','outputRootId','notBeforeUtcMs','notAfterUtcMs','scope','runBudget','failureContainment']);
 if(approval.evidenceMode!==policy.mode||approval.format!=='p4-direct-approval-v1')deny();bool(approval.approved);bool(approval.directHumanApproval);
 for(const k of ['attemptId','planSha256','requestWhitelistSha256','outputRootId','notBeforeUtcMs','notAfterUtcMs'])if(approval[k]!==policy[k])deny();
 if(approval.inventorySha256!==sha256(bytes(policy.inventory))||!['p3-p4-bounded-once','task-update-enable-run-attach-p3-p4-normal-close-once'].includes(approval.scope)||approval.runBudget!==1||approval.failureContainment!=='disable-and-exact-normal-close')deny();
 if(!Number.isSafeInteger(utc)||utc<policy.notBeforeUtcMs||utc>policy.notAfterUtcMs)deny();
 keys(p3,['format','evidenceMode','phase','returnedSource','observationFramesSha256','fullIdentitySha256','actual','passed','approvalSha256','attemptId','taskPath','oldTaskPath','registeredFlags','registeredNativeCount','registeredItems','psCount','serviceExactCount','registeredState','serviceState','returnedState','registeredGuid','serviceGuid','returnedGuid','oldDisabled','oldRegisteredCount','oldServiceCount','observationWindowMs','identity','receiptSequence','runLedgerSha256']);
 if(!['initial-activation','login-recovery','host-control-recovery'].includes(p3.phase)||p3.returnedSource!==ledger.source)deny();
 if(policy.format==='p4-evidence-policy-v2'){if(p3.phase!==policy.evidenceNamespace.phase||ledger.source!=='registered-item-attach'||ledger.runCalls!==0)deny();}else if(p3.phase!=='initial-activation')deny();
 hash(p3.observationFramesSha256);hash(p3.fullIdentitySha256);
 if(p3.evidenceMode!==policy.mode||p3.format!=='p3-actual-passed-v1'||p3.approvalSha256!==policy.approvalSha256||p3.attemptId!==policy.attemptId||p3.runLedgerSha256!==policy.runLedgerSha256||p3.taskPath!==TASK||p3.oldTaskPath!==OLD||p3.registeredFlags!==0||p3.observationWindowMs<30000||!Number.isSafeInteger(p3.observationWindowMs)||p3.receiptSequence!==1)deny();
 for(const k of ['actual','passed','oldDisabled'])bool(p3[k]);
 for(const k of ['registeredNativeCount','registeredItems','psCount','serviceExactCount'])if(p3[k]!==1)deny();
 for(const k of ['registeredState','serviceState','returnedState'])if(p3[k]!==4)deny();
 for(const k of ['oldRegisteredCount','oldServiceCount'])if(p3[k]!==0)deny();
 for(const k of ['registeredGuid','serviceGuid','returnedGuid'])if(p3[k]!==policy.identity.runGuid)deny();
 if(!equal(p3.identity,policy.identity))deny();
 keys(ledger,['format','evidenceMode','approvalSha256','attemptId','historicalProductionRuns','newRunBudget','consumed','source','runCalls','runGuid','p3Identity','activationClaimSha256','runReturnedSha256','activationStateSha256']);
 if(ledger.evidenceMode!==policy.mode||ledger.format!=='p3-run-consumption-v1'||ledger.approvalSha256!==policy.approvalSha256||ledger.attemptId!==policy.attemptId||ledger.historicalProductionRuns!==2||ledger.newRunBudget!==1||ledger.consumed!==true||ledger.runGuid!==policy.identity.runGuid||!equal(ledger.p3Identity,policy.identity))deny();
 hash(ledger.activationClaimSha256);hash(ledger.runReturnedSha256);hash(ledger.activationStateSha256);
 if(!((ledger.source==='original-run'&&ledger.runCalls===1)||(ledger.source==='registered-item-attach'&&ledger.runCalls===0)))deny();
}
function checkProof(a,p,limit) {
 keys(a,['bytes','sha256','proof']);
 if(!(a.bytes instanceof Uint8Array)||a.bytes.length>limit||a.sha256!==sha256(a.bytes))deny();
 keys(a.proof,['parentHandlesHeld','fileHandleHeld','noReparse','singleLink','sameIdentity','ownerSid','privateDacl','protectedDacl','deniedWriteDeleteSharing']);
 for(const k of ['parentHandlesHeld','fileHandleHeld','noReparse','singleLink','sameIdentity','privateDacl','protectedDacl','deniedWriteDeleteSharing'])bool(a.proof[k]);
 if(a.proof.ownerSid!==p.ownerSid)deny();
}
const failureCodes=new Set(['none','health_failed','identity_failed','authorization_failed','backup_evidence_failed','writer_failed','transport_failed','containment_pending']);
function validateReceiptPayload(p) {
 keys(p,['healthStable','localHealth','publicDiscovery','backupEvidenceComplete','overallP4Passed','requestsCompleted','sampleCount','failureCode','containmentRequired']);
 for(const k of ['healthStable','localHealth','publicDiscovery','containmentRequired'])if(typeof p[k]!=='boolean')deny();
 // This component must never sign the independent backup or complete P4 gate.
 if(p.backupEvidenceComplete!==false||p.overallP4Passed!==false||!Number.isSafeInteger(p.requestsCompleted)||p.requestsCompleted<0||p.requestsCompleted>20||!Number.isSafeInteger(p.sampleCount)||p.sampleCount<0||p.sampleCount>128||!failureCodes.has(p.failureCode))deny();
 if(p.healthStable&&(p.requestsCompleted!==20||!p.localHealth||!p.publicDiscovery||p.failureCode!=='none'))deny();
}
export function createEvidenceContract({policy,bridge,clock,launcher}={}) {
 // Construction performs no I/O. Caller policy is copied; no approval can be
 // produced by this module. Production bootstrap is an outer trusted boundary.
 const p=structuredClone(policy);validatePolicy(p);
 if(!bridge||!['withLockedArtifacts','createNewReceipt'].every(k=>typeof bridge[k]==='function')||typeof clock?.utcMs!=='function')deny();
 if(!launcher||launcher.policySha256!==sha256(bytes(p))||launcher.codePinsVerified!==true||launcher.nativeExeVerified!==true||launcher.helperVerified!==true||launcher.bridgeVerified!==true||launcher.mode!==p.mode)deny();
 const caps=new WeakSet();let active=null, next=0, previous=null, failed=false, ended=false, inFlight=false;
 async function verifyAuthorization(request){
  if(active||failed||ended||inFlight)deny();
  if(!request||request.bindingSha256!==p.bindingSha256||request.p3ReceiptSha256!==p.p3ReceiptSha256||request.approvalSha256!==p.approvalSha256||request.scope!=='p4-health-only'||request.requestCount!==20||request.authorization?.attemptId!==p.attemptId)deny();
  inFlight=true;
  try {
   const verified=await bridge.withLockedArtifacts({attemptId:p.attemptId,inventory:p.inventory,approvalSha256:p.approvalSha256,p3ReceiptSha256:p.p3ReceiptSha256,runLedgerSha256:p.runLedgerSha256},async bundle=>{
    keys(bundle,['approval','p3','ledger','frames','claim','returned','enabled','inventory']);
    for(const [name,h]of [['approval',p.approvalSha256],['p3',p.p3ReceiptSha256],['ledger',p.runLedgerSha256]]){
     checkProof(bundle[name],p,262144);if(bundle[name].sha256!==h)deny();
    }
    if(!Array.isArray(bundle.inventory)||bundle.inventory.length!==p.inventory.length)deny();
    for(let i=0;i<p.inventory.length;i++){
     const actual=bundle.inventory[i],expected=p.inventory[i];
     keys(actual,['id','sha256','byteCount','locked','noReparse','singleLink','actualLinkCount','sameIdentity','fixedSystemImagePinned']);
     if(actual.id!==expected.id||actual.sha256!==expected.sha256||!Number.isSafeInteger(actual.byteCount)||actual.byteCount<1||actual.byteCount>expected.maxBytes)deny();
     for(const k of ['locked','noReparse','sameIdentity'])bool(actual[k]);
     if(!Number.isSafeInteger(actual.actualLinkCount))deny();
     if(expected.role==='powershell'){if(actual.actualLinkCount!==2||actual.singleLink!==false||actual.fixedSystemImagePinned!==true||actual.sha256!=='8bb6fa8c283b4d92120b1ef249a9b311b0f804d4cabbe9981159976c8be76a5e')deny();}else if(actual.actualLinkCount!==1||actual.singleLink!==true)deny();
    }
    const approval=decodeCanonical(bundle.approval.bytes),p3=decodeCanonical(bundle.p3.bytes),ledger=decodeCanonical(bundle.ledger.bytes);
    validateDocuments(p,approval,p3,ledger,clock.utcMs());
    for(const name of ['frames','claim','returned','enabled'])checkProof(bundle[name],p,name==='frames'?1048576:262144);
    if(bundle.frames.sha256!==p3.observationFramesSha256||bundle.claim.sha256!==ledger.activationClaimSha256||bundle.returned.sha256!==ledger.runReturnedSha256||bundle.enabled.sha256!==ledger.activationStateSha256)deny();
    validateActualRecords(p,p3,ledger,decodeCanonical(bundle.frames.bytes,1048576),decodeCanonical(bundle.claim.bytes),decodeCanonical(bundle.returned.bytes),decodeCanonical(bundle.enabled.bytes));
    const cap=Object.freeze({attemptId:p.attemptId,bindingSha256:p.bindingSha256});caps.add(cap);active=cap;
    return Object.freeze({allowed:true,mode:p.mode==='reviewed-live'?'reviewed-live':'offline-mock',capability:cap});
   });return verified;
  }catch{failed=true;deny();}finally{inFlight=false;}
 }
 async function appendReceipt(capability,{phase,payload}={}) {
  if(!caps.has(capability)||capability!==active||failed||ended||inFlight)deny();
  if(!['intent','result','commit'].includes(phase)||phase!==['intent','result','commit'][next])deny();
  validateReceiptPayload(payload);inFlight=true;
  try{
   const now=clock.utcMs();if(!Number.isSafeInteger(now)||now<p.notBeforeUtcMs||now>p.notAfterUtcMs)deny();
   const record={format:'p4-evidence-receipt-v1',evidenceMode:p.mode,attemptId:p.attemptId,sequence:next,phase,previousSha256:previous,bindingSha256:p.bindingSha256,approvalSha256:p.approvalSha256,p3ReceiptSha256:p.p3ReceiptSha256,runLedgerSha256:p.runLedgerSha256,utcMs:now,identitySha256:sha256(bytes(p.identity)),payload};
   if(p.format==='p4-evidence-policy-v2'){record.format='p4-evidence-receipt-v2';record.evidenceNamespace=structuredClone(p.evidenceNamespace);}
   const content=bytes(record),digest=sha256(content),name=String(next).padStart(2,'0')+'-'+phase+'.json';
   // Bridge must hold approved root/attempt identities, reject pre-existing file,
   // Flush(true), compare same-handle bytes, then reopen and compare file ID/hash.
   const written=await bridge.createNewReceipt({capability,attemptId:p.attemptId,rootId:p.outputRootId,name,bytes:content,expectedSha256:digest,previousSha256:previous,approvalSha256:p.approvalSha256});
   keys(written,['name','sha256','byteCount','createNew','flushToDisk','sameHandleReadback','pathReadback','sameIdentity','privateProtectedAcl','singleLink','noReparse']);
   if(written.name!==name||written.sha256!==digest||written.byteCount!==content.length)deny();
   for(const k of ['createNew','flushToDisk','sameHandleReadback','pathReadback','sameIdentity','privateProtectedAcl','singleLink','noReparse'])bool(written[k]);
   previous=digest;next++;if(phase==='commit')ended=true;return Object.freeze({phase,sequence:next-1,sha256:digest,byteCount:content.length});
  }catch{failed=true;deny();}finally{inFlight=false;}
 }
 return Object.freeze({verifyAuthorization,appendReceipt,status:()=>Object.freeze({sequence:next,failed,ended,healthRunnerReady:false,backupEvidenceComplete:false,overallP4Passed:false})});
}

function validateActualRecords(p,p3,ledger,frames,claim,returned,enabled){
 keys(enabled,['format','evidenceMode','attemptId','approvalSha256','planSha256','taskPath','enableStartedTicks','actualRawXmlSha256','actualDefinitionSha256','taskSddlSha256','parentSddlSha256','enabled','actualExport']);
 if(enabled.format!=='i-core-enabled-task-state-v1'||enabled.evidenceMode!==p.mode||enabled.attemptId!==p.attemptId||enabled.approvalSha256!==p.approvalSha256||enabled.planSha256!==p.planSha256||enabled.taskPath!==TASK||enabled.enabled!==true||enabled.actualExport!==true||!(/^[1-9][0-9]{10,18}$/).test(enabled.enableStartedTicks)||BigInt(enabled.enableStartedTicks)>BigInt(p.identity.host.startedTicks))deny();
 for(const k of ['actualRawXmlSha256','actualDefinitionSha256','taskSddlSha256','parentSddlSha256'])hash(enabled[k]);
 keys(claim,['format','evidenceMode','attemptId','approvalSha256','planSha256','taskPath','historicalProductionRuns','newRunBudget','source','runCalls','consumed','createdAtUtc','mayHaveInvokedRun']);
 if(claim.format!=='i-core-activation-claim-v1'||claim.evidenceMode!==p.mode||claim.attemptId!==p.attemptId||claim.approvalSha256!==p.approvalSha256||claim.planSha256!==p.planSha256||claim.taskPath!==TASK||claim.historicalProductionRuns!==2||claim.newRunBudget!==1||claim.source!==ledger.source||claim.runCalls!==ledger.runCalls||claim.consumed!==true||claim.mayHaveInvokedRun!==(ledger.runCalls===1)||!Number.isFinite(Date.parse(claim.createdAtUtc)))deny();
 keys(returned,['format','evidenceMode','attemptId','approvalSha256','activationClaimSha256','source','runCalls','taskPath','instanceGuid','state','observedAtUtc']);
 if(returned.format!=='i-core-run-returned-v1'||returned.evidenceMode!==p.mode||returned.attemptId!==p.attemptId||returned.approvalSha256!==p.approvalSha256||returned.activationClaimSha256!==ledger.activationClaimSha256||returned.source!==ledger.source||returned.runCalls!==ledger.runCalls||returned.taskPath!==TASK||returned.instanceGuid!==p.identity.runGuid||returned.state!==4||!Number.isFinite(Date.parse(returned.observedAtUtc))||Date.parse(returned.observedAtUtc)<Date.parse(claim.createdAtUtc))deny();
 keys(frames,['format','evidenceMode','phase','attemptId','frames']);
 if(frames.format!=='p3-actual-observation-frames-v1'||frames.evidenceMode!==p.mode||frames.phase!==p3.phase||frames.attemptId!==p.attemptId||!Array.isArray(frames.frames)||frames.frames.length<7||frames.frames.length>128)deny();
 let prior=-1,first=null,stable=null;
 for(const frame of frames.frames){
  keys(frame,['elapsedMs','snapshotElapsedMs','identity']);
  if(!Number.isSafeInteger(frame.elapsedMs)||frame.elapsedMs<=prior||frame.elapsedMs<0||(prior>=0&&frame.elapsedMs-prior>7500)||!Number.isSafeInteger(frame.snapshotElapsedMs)||frame.snapshotElapsedMs<0||frame.snapshotElapsedMs>2500)deny();
  if(prior<0){first=frame.elapsedMs;if(first>2500)deny();}
  prior=frame.elapsedMs;const current=canonical(frame.identity);if(stable!==null&&current!==stable)deny();stable=current;
 }
 if(prior-first<30000||prior>35000||prior-first!==p3.observationWindowMs)deny();
 const full=frames.frames.at(-1).identity;
 if(sha256(bytes(full))!==p3.fullIdentitySha256)deny();
 const uuid=x=>{const m=/^(?:session|control)-([a-f0-9]{32})$/.exec(x??'');if(!m)deny();const a=m[1];return a.slice(0,8)+'-'+a.slice(8,12)+'-'+a.slice(12,16)+'-'+a.slice(16,20)+'-'+a.slice(20);};
 const reduced={sessionId:uuid(full.sessionId),controlId:uuid(full.controlId),runGuid:full.task?.registeredGuid};
 for(const k of ['host','core','mcp']){const q=full.processes?.[k];reduced[k]={pid:q?.pid,startedTicks:q?.startedTicks};}
 if(!equal(reduced,p.identity)||full.evidenceMode!==p.mode||full.approvalSha256!==p.approvalSha256)deny();
 const t=full.task;
 for(const k of ['registeredNativeCount','registeredItems','registeredMatchingItems','psCount','psExplicitCount','serviceExactCount'])if(t[k]!==1)deny();
 for(const k of ['registeredTaskState','registeredState','serviceState','returnedState'])if(t[k]!==4)deny();
 for(const k of ['registeredGuid','serviceGuid','returnedGuid'])if(t[k]!==p.identity.runGuid)deny();
 if(t.path!==TASK||t.oldPath!==OLD||t.returnedSource!==ledger.source||t.registeredFlags!==0||t.newEnabled!==true||t.oldDisabled!==true||t.oldRegisteredCount!==0||t.oldServiceCount!==0)deny();
}

export function validateEvidenceNamespace(n,p){
 keys(n,['version','phase','sessionId','controlId','leaf','recoveryPolicySha256','startSha256','permitSha256','firstAttemptId','firstAttemptSha256']);
 if(n.version!=='recovery-p4-evidence-namespace-v1'||!['login-recovery','host-control-recovery'].includes(n.phase)||!/^session-[a-f0-9]{32}$/.test(n.sessionId??'')||!/^control-[a-f0-9]{32}$/.test(n.controlId??'')||!/^[a-f0-9]{32}$/.test(n.firstAttemptId??''))deny();
 for(const k of Object.keys(n))if(typeof n[k]!=='string')deny();
 for(const k of ['recoveryPolicySha256','startSha256','permitSha256','firstAttemptSha256'])hash(n[k]);
 if(n.leaf!=='recovery-p4-v1--'+n.phase+'--'+n.sessionId+'--'+n.controlId)deny();
 const uuid=s=>{const h=s.slice(s.indexOf('-')+1);return h.slice(0,8)+'-'+h.slice(8,12)+'-'+h.slice(12,16)+'-'+h.slice(16,20)+'-'+h.slice(20)};
 if(uuid(n.sessionId)!==p.identity.sessionId||uuid(n.controlId)!==p.identity.controlId)deny();
 return true;
}
