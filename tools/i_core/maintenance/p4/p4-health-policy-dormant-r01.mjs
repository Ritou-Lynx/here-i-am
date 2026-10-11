// Offline-preparation candidate. No network, process, filesystem or task imports.
// No top-level execution; execute=false is a zero-I/O plan.
const BASE='https://mcp.example.invalid';
export const TASK_PATH='\\HereIAm-iCoreSchema6-chatgpt-20261009-f90058f2';
export const OLD_TASK_PATH='\\HereIAm-iCoreSchema6-cleanclose-20261008-2c01de5b';
function guid(x){if(typeof x!=='string')return null;const m=/^(?:\{([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\}|([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}))$/i.exec(x);return m?(m[1]??m[2]).toLowerCase():null;}
export const LIMITS=Object.freeze({headerBytes:8192,healthBytes:16384,metadataBytes:8192,errorBytes:1024,requestMs:2000,snapshotMs:2500,windowMs:30000,sampleMs:5000,maxGapMs:7500,totalMs:60000});
const fail=code=>{throw new Error(code)};
const plain=x=>x!==null&&typeof x==='object'&&!Array.isArray(x);
export function equal(a,b){if(Object.is(a,b))return true;if(Array.isArray(a))return Array.isArray(b)&&a.length===b.length&&a.every((v,i)=>equal(v,b[i]));if(!plain(a)||!plain(b))return false;const ka=Object.keys(a).sort(),kb=Object.keys(b).sort();return equal(ka,kb)&&ka.every(k=>equal(a[k],b[k]));}
const hash=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const pos=x=>Number.isSafeInteger(x)&&x>0;
const ticks=x=>typeof x==='string'&&/^[1-9][0-9]{10,18}$/.test(x);
export const RESOURCE=Object.freeze({resource:BASE+'/mcp',authorization_servers:[BASE],scopes_supported:['i.read','i.write'],bearer_methods_supported:['header'],resource_name:'i (林埃) 连续性'});
export const AUTHORITY=Object.freeze({issuer:BASE,authorization_response_iss_parameter_supported:true,authorization_endpoint:BASE+'/authorize',token_endpoint:BASE+'/token',registration_endpoint:BASE+'/register',response_types_supported:['code'],grant_types_supported:['authorization_code','refresh_token'],code_challenge_methods_supported:['S256'],token_endpoint_auth_methods_supported:['none'],scopes_supported:['i.read','i.write','offline_access']});
export function challenge(value){
 if(typeof value!=='string'||value.length>1024)return false;
 const match=/^Bearer\s+(.+)$/i.exec(value);if(!match)return false;
 const attrs={};let rest=match[1];
 while(rest.length){const m=/^\s*([a-z_]+)\s*=\s*"([^"\\]*)"\s*(,|$)/i.exec(rest);if(!m||Object.hasOwn(attrs,m[1].toLowerCase()))return false;attrs[m[1].toLowerCase()]=m[2];rest=rest.slice(m[0].length);if(m[3]===','&&!rest.trim())return false;}
 return equal(attrs,{resource_metadata:BASE+'/.well-known/oauth-protected-resource',scope:'i.read i.write'});
}
export function validateIdentity(i){
 if(!plain(i)||i.p3Passed!==true||!hash(i.p3ReceiptSha256)||!hash(i.approvalSha256)||!hash(i.manifestSha256)||!hash(i.coreConfigSha256)||!hash(i.mcpConfigSha256)||!hash(i.nodeSha256))fail('identity_anchors');
 if(typeof i.sessionId!=='string'||!i.sessionId||typeof i.controlId!=='string'||!i.controlId||i.newSessionCount!==1||i.newControlCount!==1)fail('identity_session');
 for(const k of ['sessionWindowSha256','launchSha256','readySha256','mcpStartSha256'])if(!hash(i[k]))fail('identity_file_hash');
 for(const k of ['tokenEqual','readyManifestEqual','mcpManifestEqual','coreConfigEqual','coreReadyBound','readyNodeEqual','authorityNodeEqual'])if(i[k]!==true)fail('identity_binding');
 if(typeof i.nodeId!=='string'||!i.nodeId)fail('identity_node');
 const t=i.task;if(!plain(t)||t.registeredFlags!==0||t.registeredNativeCount!==1||t.registeredItems!==1||t.psCount!==1||t.serviceExactCount!==1||t.oldDisabled!==true||t.oldRegisteredCount!==0||t.oldServiceCount!==0)fail('identity_strict_task');
 if(t.path!==TASK_PATH||t.oldPath!==OLD_TASK_PATH||!guid(t.registeredGuid)||!guid(t.serviceGuid)||!guid(t.returnedGuid))fail('identity_task_key');
 if(guid(t.registeredGuid)!==guid(t.serviceGuid)||guid(t.registeredGuid)!==guid(t.returnedGuid)||t.registeredState!==4||t.serviceState!==4||t.returnedState!==4)fail('identity_task_instance');
 const p=i.processes;
 if(!plain(p))fail('identity_processes');
 const ids=[];
 for(const name of ['host','supervisor','core','mcp']){
  const q=p[name];if(!plain(q)||!pos(q.pid)||!ticks(q.startedTicks)||!hash(q.imageSha256)||q.ownerSid!==i.ownerSid||q.sessionId!==i.windowsSessionId||!Number.isSafeInteger(q.parentPid))fail('identity_process');
  ids.push(q.pid);
 }
 if(new Set(ids).size!==4||typeof i.ownerSid!=='string'||!/^S-1-5-/.test(i.ownerSid)||!Number.isSafeInteger(i.windowsSessionId))fail('identity_process_unique');
 if(p.supervisor.parentPid!==p.host.pid||p.core.parentPid!==p.supervisor.pid||p.mcp.parentPid!==p.host.pid||p.core.imageSha256!==i.nodeSha256||p.mcp.imageSha256!==i.nodeSha256)fail('identity_chain');
 if(i.hostSystemPowerShell!==true||i.hiddenWindow!==true||!pos(i.hwnd)||!pos(i.threadId)||!ticks(i.enableStartedTicks)||BigInt(p.host.startedTicks)<BigInt(i.enableStartedTicks))fail('identity_host');
 if(i.launchParentPid!==p.supervisor.pid||i.launchParentStartedTicks!==p.supervisor.startedTicks||i.readyPid!==p.core.pid||i.mcpCorePid!==p.core.pid||i.mcpStartedTicks!==p.mcp.startedTicks)fail('identity_launch_chain');
 if(!equal(i.listeners,[{address:'127.0.0.1',port:47841,count:1,pid:p.core.pid},{address:'127.0.0.1',port:47860,count:1,pid:p.mcp.pid},{address:'127.0.0.1',port:47862,count:1,pid:p.mcp.pid}]))fail('identity_listeners');
 return true;
}
export const CONTRACT_REVISION='p4-dormant-owner-unconfigured-v1';
export const DORMANT_HTTP_FEATURES=Object.freeze(["device_pairing","chat_submit","change_feed","cursor_ack","domains_v1"]);
export const DORMANT_HTTP_ACTIVITY=Object.freeze({"contract":"device.activity.v1","feature_version":1,"schema_version":5,"status":"owner_principal_unconfigured","control_plane_available":false,"database_role":"live","runtime_fence":null,"takeover_supported":false,"backup_activation_supported":false,"clean_close_in_place_only":true,"crash_recovery_supported":false,"lease_takeover_supported":false,"backup_verification_supported":true,"e2e_available":false,"collector_available":false,"summary_client_available":false});
export function validateHealth(body,expected,wallMs){
 if(!equal(expected?.httpFeatures,DORMANT_HTTP_FEATURES)||!equal(expected?.httpActivity,DORMANT_HTTP_ACTIVITY))fail('expected_contract_missing');
 if(!plain(body)||body.ok!==true||body.role!=='authority'||body.schema_version!==6||body.protocol_version!=='0.1'||body.minimum_protocol_version!=='0.1'||body.node_id!==expected.identity.nodeId)fail('health_core');
 if(!Number.isSafeInteger(body.server_time_ms)||Math.abs(body.server_time_ms-wallMs)>5000)fail('health_clock');
 if(!equal(body.features,expected.httpFeatures)||!equal(body.activity,expected.httpActivity))fail('health_activity_or_features');
 const a=body.activity;
 if(!equal(a,DORMANT_HTTP_ACTIVITY))fail('health_not_authority_ready');
 const keys=['ok','node_id','role','protocol_version','minimum_protocol_version','schema_version','server_time_ms','features','activity'];
 if(!equal(Object.keys(body).sort(),keys.sort()))fail('health_unreviewed_fields');
}
export function plan(){return {format:'p4-narrow-plan-v1',execution:false,requestsPerSweep:10,sweeps:2,windowMs:30000,backupEvidenceComplete:false,overallP4Passed:false};}
function requests(){
 const a=[{id:'core',url:'http://127.0.0.1:47841/v1/core/health',method:'GET',kind:'health',maxBodyBytes:LIMITS.healthBytes}];
 for(const [name,base] of [['local','http://127.0.0.1:47860'],['public',BASE]]){
  for(const path of ['/.well-known/oauth-protected-resource','/.well-known/oauth-protected-resource/mcp','/.well-known/oauth-authorization-server'])a.push({id:name+path,url:base+path,method:'GET',kind:path.endsWith('authorization-server')?'authority':'resource',maxBodyBytes:LIMITS.metadataBytes});
  a.push({id:name+'/mcp',url:base+'/mcp',method:'POST',kind:'unauth',maxBodyBytes:LIMITS.errorBytes,body:'{"jsonrpc":"2.0","id":"p4-unauth","method":"tools/list","params":{}}'});
 }
 a.splice(5,0,{id:'phone',url:'http://127.0.0.1:47862/v1/remember/changes?after=0&limit=1',method:'GET',kind:'phone',maxBodyBytes:0});return a;
}
// The reviewed transport must call onHeaders synchronously BEFORE acquiring,
// buffering, decoding or exposing body bytes. "discard" cancels/destroys stream.
// It must independently enforce byte/time bounds; never follow redirects, use
// cookies, ambient credentials/proxies/client certs, decompress or retry.
// A body byte string is returned ONLY after "read". Phone always discards.
export async function executeP4({execute=false,expected,authorization,transport,observeIdentity,clock,verifyAuthorization}={}){
 if(execute!==true)return plan();
 const result={format:'p4-health-result-v1',mode:'injected',localHealth:false,publicDiscovery:false,healthStable:false,backupEvidenceComplete:false,overallP4Passed:false,samples:[],checks:[],failure:null,automaticRestart:false,automaticClose:false};
 try{
  expected=structuredClone(expected);
  validateIdentity(expected?.identity);
  if(!hash(expected.bindingSha256)||!Array.isArray(expected.httpFeatures)||!plain(expected.httpActivity))fail('expected_contract_missing');
  if(!transport||typeof transport.request!=='function'||typeof observeIdentity!=='function'||typeof verifyAuthorization!=='function'||!clock||!['mono','utcMs','sleep'].every(k=>typeof clock[k]==='function'))fail('dependencies_missing');
  const verified=await verifyAuthorization({authorization,bindingSha256:expected.bindingSha256,p3ReceiptSha256:expected.identity.p3ReceiptSha256,approvalSha256:expected.identity.approvalSha256,scope:'p4-health-only',requestCount:20});
  if(verified?.allowed!==true||!['offline-mock','reviewed-live'].includes(verified.mode))fail('authorization_rejected');
  result.mode=verified.mode;result.bindingSha256=expected.bindingSha256;
  const startAll=clock.mono();let lastMono=startAll;
  const now=()=>{const n=clock.mono();if(!Number.isFinite(n)||n<lastMono||n-startAll>LIMITS.totalMs)fail('monotonic_or_total_budget');lastMono=n;return n;};
  async function identity(){
   const begin=now();const s=await observeIdentity({timeoutMs:LIMITS.snapshotMs,bindingSha256:expected.bindingSha256});
   const end=now();if(end-begin>LIMITS.snapshotMs||!plain(s)||!Number.isFinite(s.observedMono)||s.observedMono<begin||s.observedMono>end)fail('identity_sample_budget');
   validateIdentity(s.identity);if(!equal(s.identity,expected.identity))fail('identity_changed');
   result.samples.push({mono:end,utcMs:clock.utcMs(),identityUnchanged:true});return end;
  }
  async function request(spec){
   await identity();const began=now();let headersSeen=false,decision,headerOK=false,status=null,ended=null;
   const item={id:spec.id,status:null,passed:false,bodyDiscarded:false};result.checks.push(item);
   try{
    const response=await transport.request(Object.freeze({...spec,headers:Object.freeze(spec.method==='POST'?{'content-type':'application/json'}:{}),redirect:'error',credentials:'omit',cookies:false,authorization:false,proxy:false,retries:0,maxHeaderBytes:LIMITS.headerBytes,timeoutMs:LIMITS.requestMs,onHeaders(h){
     if(headersSeen)fail('duplicate_headers');headersSeen=true;
     status=h.status;item.status=status;
     if(!Number.isInteger(status)||!Number.isSafeInteger(h.headerBytes)||h.headerBytes<0||h.headerBytes>LIMITS.headerBytes)fail('headers_invalid');
     const hs={};for(const [k,v]of Object.entries(h.headers??{})){const key=k.toLowerCase();if(Object.hasOwn(hs,key))fail('duplicate_header');hs[key]=v;}
     if(spec.kind==='phone'){headerOK=status===401;decision='discard';item.bodyDiscarded=true;return decision;}
     const target=spec.kind==='unauth'?401:200;
     if(status!==target){decision='discard';item.bodyDiscarded=true;return decision;}
     if(!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(hs['content-type']??'')||hs['content-encoding']&&hs['content-encoding']!=='identity'){decision='discard';item.bodyDiscarded=true;return decision;}
     if(Object.hasOwn(hs,'content-length')&&(!/^[0-9]+$/.test(String(hs['content-length']))||Number(hs['content-length'])>spec.maxBodyBytes)){decision='discard';item.bodyDiscarded=true;return decision;}
     if(spec.kind==='unauth'&&!challenge(hs['www-authenticate'])){decision='discard';item.bodyDiscarded=true;return decision;}
     headerOK=true;decision='read';return decision;
    }}));
    ended=now();if(ended-began>LIMITS.requestMs)fail('request_timeout');
    if(!headersSeen)fail('headers_missing');
    if(decision==='discard'){
     if(response?.bodyDiscarded!==true||Object.hasOwn(response??{},'body'))fail('discard_contract');
     if(!headerOK)fail(spec.kind==='phone'?'phone_auth_boundary':'unexpected_status_or_headers');
    }else{
     if(!headerOK||!(response?.body instanceof Uint8Array)||response.body.byteLength>spec.maxBodyBytes)fail('body_bounds');
     let parsed;try{parsed=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(response.body));}catch{fail('invalid_json');}
     if(spec.kind==='health')validateHealth(parsed,expected,clock.utcMs());
     if(spec.kind==='resource'&&!equal(parsed,RESOURCE))fail('resource_metadata');
     if(spec.kind==='authority'&&!equal(parsed,AUTHORITY))fail('authority_metadata');
     if(spec.kind==='unauth'&&!equal(parsed,{error:'unauthorized',error_description:'Bearer token required'}))fail('unauth_body');
    }
    await identity();item.passed=true;item.elapsedMs=ended-began;
   }catch(e){item.failure=knownCode(e);throw e;}
  }
  async function sweep(){let rejected=null;const offset=result.checks.length;
   for(const spec of requests()){
    try{await request(spec);}catch(e){rejected=e;break;}
   }
   const checks=result.checks.slice(offset);
   const local=checks.filter(x=>!x.id.startsWith('public'));
   result.localHealth=local.length===6&&local.every(x=>x.passed);
   const pub=checks.filter(x=>x.id.startsWith('public'));result.publicDiscovery=pub.length===4&&pub.every(x=>x.passed);
   if(rejected)throw rejected;
  }
  await sweep();const stableStart=await identity();result.startedUtcMs=clock.utcMs();result.startedMono=stableStart;
  let prior=stableStart;
  for(let target=stableStart+LIMITS.sampleMs;target<=stableStart+LIMITS.windowMs;target+=LIMITS.sampleMs){
   const wait=target-now();if(wait>0)await clock.sleep(wait);
   if(now()>target+LIMITS.snapshotMs)fail('sample_admission_late');
   const observed=await identity();if(observed-prior>LIMITS.maxGapMs)fail('sample_gap');prior=observed;
  }
  // Admission window ends here. No restart, renewed window or acceptance of
  // changed identity. End HTTP sweep and final identity are also mandatory.
  if(now()-stableStart<LIMITS.windowMs)fail('stability_short');
  await sweep();await identity();result.completedUtcMs=clock.utcMs();result.elapsedMonoMs=now()-stableStart;result.healthStable=true;
 }catch(e){result.failure=knownCode(e);}
 return result;
}
function knownCode(error){
 // Never include transport/server error text, body bytes, tokens or paths.
 const allowed=new Set(["authority_metadata","authorization_rejected","body_bounds","dependencies_missing","discard_contract","duplicate_header","duplicate_headers","expected_contract_missing","headers_invalid","headers_missing","health_activity_or_features","health_clock","health_core","health_not_authority_ready","health_unreviewed_fields","identity_anchors","identity_binding","identity_chain","identity_changed","identity_file_hash","identity_host","identity_launch_chain","identity_listeners","identity_node","identity_process","identity_process_unique","identity_processes","identity_sample_budget","identity_session","identity_strict_task","identity_task_instance","identity_task_key","invalid_json","monotonic_or_total_budget","phone_auth_boundary","request_timeout","resource_metadata","sample_admission_late","sample_gap","stability_short","unauth_body","unexpected_status_or_headers"]);
 return typeof error?.message==='string'&&allowed.has(error.message)?error.message:'dependency_or_transport_failure';
}
