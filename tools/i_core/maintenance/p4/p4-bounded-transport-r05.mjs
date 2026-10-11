// Offline candidate. Import is inert. No environment, proxy, cookie jar or HTTP agent.
import net from 'node:net';
import tls from 'node:tls';
import {performance} from 'node:perf_hooks';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
export const NODE_SHA256='58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f';
export const POST_BODY='{"jsonrpc":"2.0","id":"p4-unauth","method":"tools/list","params":{}}';
const BASE='https://mcp.example.invalid';
const sha=b=>createHash('sha256').update(b).digest('hex');
const frozen=x=>Object.freeze(x);
const specs=[{id:'core',url:'http://127.0.0.1:47841/v1/core/health',method:'GET',kind:'health',maxBodyBytes:16384,body:''}];
for(const [name,base] of [['local','http://127.0.0.1:47860'],['public',BASE]]){
 for(const path of ['/.well-known/oauth-protected-resource','/.well-known/oauth-protected-resource/mcp','/.well-known/oauth-authorization-server'])
  specs.push({id:name+path,url:base+path,method:'GET',kind:path.endsWith('authorization-server')?'authority':'resource',maxBodyBytes:8192,body:''});
 specs.push({id:name+'/mcp',url:base+'/mcp',method:'POST',kind:'unauth',maxBodyBytes:1024,body:POST_BODY});
}
specs.splice(5,0,{id:'phone',url:'http://127.0.0.1:47862/v1/remember/changes?after=0&limit=1',method:'GET',kind:'phone',maxBodyBytes:0,body:''});
export const REQUESTS=frozen(specs.map(s=>frozen({...s,requestBodyBytes:Buffer.byteLength(s.body),requestBodySha256:sha(s.body)})));
const digest=x=>sha(JSON.stringify(x));
export const ENDPOINT_MANIFEST_SHA256=digest(REQUESTS);
const hash=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const error=code=>Object.assign(new Error(code),{code});
const deny=code=>{throw error(code)};
const eq=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
function validate(spec,expected){
 if(!spec||typeof spec.onHeaders!=='function')deny('transport_spec');
 for(const key of ['id','url','method','kind','maxBodyBytes'])if(spec[key]!==expected[key])deny('transport_allowlist');
 if((spec.body??'')!==expected.body||spec.timeoutMs!==2000||spec.maxHeaderBytes!==8192||spec.redirect!=='error'||spec.credentials!=='omit'||spec.cookies!==false||spec.authorization!==false||spec.proxy!==false||spec.retries!==0)deny('transport_spec');
 if(!eq(spec.headers,expected.method==='POST'?{'content-type':'application/json'}:{}))deny('transport_headers');
}
function requestBytes(s,target){
 const u=new URL(s.url);
 const headers=[s.method+' '+u.pathname+u.search+' HTTP/1.1','Host: '+(target.synthetic?'127.0.0.1:'+target.port:u.host),'Connection: close','Accept: application/json','Accept-Encoding: identity'];
 if(s.method==='POST')headers.push('Content-Type: application/json','Content-Length: '+Buffer.byteLength(s.body));
 return Buffer.from(headers.join('\r\n')+'\r\n\r\n'+s.body,'ascii');
}
function parseHeaders(bytes){
 const text=bytes.toString('latin1');
 if(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(text)||text.replace(/\r\n/g,'').includes('\n')||text.replace(/\r\n/g,'').includes('\r'))deny('transport_header_syntax');
 const lines=text.slice(0,-4).split('\r\n');
 const m=/^HTTP\/1\.[01] ([1-5][0-9]{2})(?: [\x20-\x7e]*)?$/.exec(lines.shift());
 if(!m)deny('transport_status');
 const status=Number(m[1]),headers=Object.create(null);
 // No interim responses, upgrade, ambiguity, folding or duplicate headers.
 if(status<200)deny('transport_status');
 for(const line of lines){
  const h=/^([!#$%&'*+.^_`|~0-9A-Za-z-]+):[ \t]*([^\r\n]*)$/.exec(line);
  if(!h||Object.hasOwn(headers,h[1].toLowerCase()))deny('transport_header_syntax');
  headers[h[1].toLowerCase()]=h[2].trim();
 }
 if(headers.upgrade||headers['content-encoding']&&headers['content-encoding']!=='identity')deny('transport_framing');
 const cl=headers['content-length'],te=headers['transfer-encoding'];
 if(text.startsWith('HTTP/1.0')&&te!==undefined)deny('transport_framing');
 if(cl!==undefined&&(!/^(0|[1-9][0-9]*)$/.test(cl)||!Number.isSafeInteger(Number(cl)))||te!==undefined&&te.toLowerCase()!=='chunked'||cl!==undefined&&te!==undefined)deny('transport_framing');
 return {status,headers};
}
async function exchange(s,onHeaders,target){
 const began=performance.now(),metrics={headerBytes:0,bodyBytes:0,bodyCopyOperations:0,headerCallbacks:0,socketCreated:false,socketDestroyed:false,socketClosed:false,applicationHeaderReadBytes:0,applicationBodyReadBytes:0,internalBufferedBytesAtDiscard:0,dnsStarted:false,connectStarted:false,tlsStarted:false,deadlineDetectedMs:null,destroyCalledMs:null,elapsedMs:0};
 let socket,timer,settled=false,outcome=null,headerDone=false,hbuf=Buffer.alloc(8192),parts=[],framing,remaining=0,bodyTotal=0,chunkState='size',line=[],chunkRemaining=0,overhead=0,crlf=0;
 return await new Promise((resolve,reject)=>{
  const budget=()=>{if(performance.now()-began>=2000){finish('transport_timeout');return false;}return true};
  function finish(code,result){
   if(settled)return;settled=true;
   outcome=code?{code}:{result};if(code==='transport_timeout')metrics.deadlineDetectedMs=Math.ceil(performance.now()-began);
   // Drop all accumulated references before destroying the owned socket.
   if(code)parts=[];hbuf=null;
   if(socket){metrics.destroyCalledMs=Math.ceil(performance.now()-began);socket.destroy();metrics.socketDestroyed=socket.destroyed;}else complete();
  }
  function complete(){
   clearTimeout(timer);metrics.elapsedMs=Math.ceil(performance.now()-began);
   if(!outcome?.code&&metrics.elapsedMs>=2000){outcome={code:'transport_timeout'};metrics.deadlineDetectedMs??=metrics.elapsedMs;}
   if(outcome?.code){const e=error(outcome.code);e.metrics=frozen({...metrics});reject(e);}
   else resolve({...outcome.result,metrics:frozen({...metrics})});
  }
  function bodyAppend(buf,start,count){
   if(bodyTotal+count>s.maxBodyBytes){finish('transport_body_limit');return false;}
   if(count){parts.push(Buffer.from(buf.subarray(start,start+count)));bodyTotal+=count;metrics.bodyBytes=bodyTotal;metrics.bodyCopyOperations++;}
   return true;
  }
  function success(){finish(null,{body:new Uint8Array(Buffer.concat(parts,bodyTotal))});parts=[];}
  function body(buf,i){
   if(framing==='length'){
    const count=buf.length-i;
    if(count>remaining){finish('transport_framing');return;}
    if(!bodyAppend(buf,i,count))return;
    remaining-=count;if(remaining===0)success();return;
   }
   if(framing==='close'){bodyAppend(buf,i,buf.length-i);return;}
   while(i<buf.length&&!settled){
    if(!budget())return;
    if(chunkState==='data'){
     const n=Math.min(chunkRemaining,buf.length-i);if(!bodyAppend(buf,i,n))return;
     i+=n;chunkRemaining-=n;if(chunkRemaining===0){chunkState='dataCRLF';crlf=0;}
    }else{
     const byte=buf[i++];if(++overhead>8192){finish('transport_chunk_limit');return;}
     if(chunkState==='size'){
      if(line.length>=128){finish('transport_framing');return;}line.push(byte);
      if(byte===10){
       const value=Buffer.from(line).toString('latin1');line=[];
       if(!/^[0-9a-fA-F]{1,8}\r\n$/.test(value)){finish('transport_framing');return;}
       chunkRemaining=parseInt(value,16);
       if(chunkRemaining>s.maxBodyBytes-bodyTotal){finish('transport_body_limit');return;}
       chunkState=chunkRemaining===0?'lastCRLF':'data';crlf=0;
      }
     }else{
      if(byte!==(crlf===0?13:10)){finish('transport_framing');return;}crlf++;
      if(crlf===2){
       if(chunkState==='lastCRLF'){
        if(i!==buf.length){finish('transport_framing');return;}success();return;
       }chunkState='size';crlf=0;
      }
     }
    }
   }
  }
  function data(buf){
   if(settled||!budget())return;
   try{
    let i=0;
    if(!headerDone){
     while(i<buf.length){
      if(metrics.headerBytes===8192){finish('transport_header_limit');return;}
      hbuf[metrics.headerBytes++]=buf[i++];
      const n=metrics.headerBytes;
      if(n>=4&&hbuf[n-4]===13&&hbuf[n-3]===10&&hbuf[n-2]===13&&hbuf[n-1]===10){
       headerDone=true;
       const h=parseHeaders(hbuf.subarray(0,n));
       metrics.headerCallbacks++;
       // Never copy, slice, decode or expose the body region before this decision.
       const selected={};
       for(const k of ['content-type','content-encoding','content-length','transfer-encoding','www-authenticate'])if(Object.hasOwn(h.headers,k))selected[k]=h.headers[k];
       const decision=onHeaders(frozen({status:h.status,headerBytes:n,headers:frozen(selected)}));
       if(!budget())return;
       // Phone is independently forced to discard, even for a faulty callback.
       if(s.kind==='phone'||decision==='discard'){metrics.internalBufferedBytesAtDiscard=socket.readableLength;finish(null,{bodyDiscarded:true});return;}
       if(decision!=='read'){finish('transport_header_decision');return;}
       hbuf=null;
       if(h.headers['content-length']!==undefined){
        remaining=Number(h.headers['content-length']);framing='length';
        if(remaining>s.maxBodyBytes){finish('transport_body_limit');return;}
       }else framing=h.headers['transfer-encoding']?'chunked':'close';
       break;
      }
     }
    }
    if(headerDone)body(buf,i);
   }catch{finish('transport_header_or_parser_failure');}
  }
  timer=setTimeout(()=>finish('transport_timeout'),2000);
  try{
   // Timer starts before DNS/connect/TLS. No pooled socket, automatic retry, redirect or proxy.
   const opts={host:target.host,port:target.port,autoSelectFamily:false};
   metrics.connectStarted=true;
   if(target.fixtureFault==='dns-stall'){
    opts.host='p4-synthetic.invalid';
    opts.lookup=()=>{metrics.dnsStarted=true;}; // no OS/public DNS call
   }
   if(target.fixtureFault==='connect-stall'){
    // Explicit synthetic pre-connect fault; never opens an OS connection.
    socket=new net.Socket();
   }else if(target.tls){
    metrics.tlsStarted=true;
    socket=tls.connect({...opts,servername:net.isIP(target.host)?undefined:target.host,rejectUnauthorized:true,minVersion:'TLSv1.2',ALPNProtocols:['http/1.1'],...(target.synthetic?{ca:target.fixtureCA}:{})});
   }else socket=net.connect(opts);
   metrics.socketCreated=true;
   socket.on('error',()=>finish('transport_io'));
   // Paused readable mode: read exactly ONE header byte, never a whole
   // TCP chunk. Node/OS may buffer body internally; application receives none
   // before the synchronous header decision. read(0) is only an internal hint.
   socket.on('readable',()=>{
    while(!settled&&budget()){
     const take=headerDone?Math.min(socket.readableLength,s.maxBodyBytes-metrics.bodyBytes+1,4096):1;
     if(take<=0)break;
     const part=socket.read(take);if(part===null)break;
     if(headerDone)metrics.applicationBodyReadBytes+=part.length;
     else metrics.applicationHeaderReadBytes+=part.length;
     data(part);
    }
   });
   socket.on('end',()=>{if(settled)return;if(!budget())return;if(headerDone&&framing==='close')success();else finish('transport_truncated');});
   socket.on('close',()=>{metrics.socketClosed=true;if(!settled){settled=true;outcome={code:'transport_io'};}complete();});
   socket.once(target.tls?'secureConnect':'connect',()=>{
    if(settled||!budget())return;
    if(target.tls&&socket.alpnProtocol&&socket.alpnProtocol!=='http/1.1'){finish('transport_tls');return;}
    socket.write(requestBytes(s,target));
   });
  }catch{finish('transport_io');}
 });
}
function session(targetFor,mode){
 let count=0,busy=false,failed=false;
 return frozen({mode,async request(spec){
  if(busy||failed||count>=20)deny('transport_session_closed');
  const expected=REQUESTS[count%10];
  validate(spec,expected);
  count++;busy=true;
  try{return await exchange(expected,spec.onHeaders,targetFor(expected));}
  catch(e){failed=true;throw e;}
  finally{busy=false;}
 },snapshot(){return frozen({mode,requestCount:count,maxRequests:20,failed,busy,overallP4Passed:false});}});
}
// The verifier is a separately reviewed trust dependency; strings/booleans cannot
// substitute for it. It must authenticate approval, runtime/source hashes and P3.
// This source provides NO production approval and never creates a verifier.
export async function createReviewedTransport(options={}){
 const {review,authorization,verifyAuthorization,endpointAllowlist}=options;
 if(!review||review.reviewed!==true||!hash(review.sourceSha256)||!hash(review.bindingSha256)||!hash(review.verifierSha256)||typeof verifyAuthorization!=='function'||!eq(endpointAllowlist,REQUESTS))deny('transport_admission');
 const sourceSha256=sha(await readFile(new URL(import.meta.url)));
 const nodeSha256=sha(await readFile(process.execPath));
 if(sourceSha256!==review.sourceSha256||nodeSha256!==NODE_SHA256)deny('transport_dependency_hash');
 let v;
 try{v=await verifyAuthorization(frozen({authorization,review:frozen({...review}),sourceSha256,nodeSha256,endpointManifestSha256:ENDPOINT_MANIFEST_SHA256,scope:'p4-health-only',maxRequests:20}));}catch{deny('transport_admission');}
 if(v?.allowed!==true||v.mode!=='reviewed-live'||v.bindingSha256!==review.bindingSha256||v.sourceSha256!==sourceSha256||v.endpointManifestSha256!==ENDPOINT_MANIFEST_SHA256)deny('transport_admission');
 return session(s=>{const u=new URL(s.url);return {host:u.hostname,port:Number(u.port)||(u.protocol==='https:'?443:80),tls:u.protocol==='https:'};},'reviewed-live');
}
// Synthetic-only harness: all canonical targets map to a newly created 127.0.0.1
// fixture. It cannot address the application ports or any hostname/public address.
export function createOfflineTransport({fixturePort,fixtureHost='127.0.0.1',fixtureTLS=false,fixtureCA,fixtureFault=null}={}){
 if(fixtureHost!=='127.0.0.1'||!Number.isInteger(fixturePort)||fixturePort<1024||fixturePort>65535||[47841,47860,47862].includes(fixturePort))deny('transport_fixture');
 if(typeof fixtureTLS!=='boolean'||![null,'dns-stall','connect-stall'].includes(fixtureFault)||fixtureTLS&&(!fixtureCA||typeof fixtureCA!=='string'||Buffer.byteLength(fixtureCA)>8192)||!fixtureTLS&&fixtureCA!==undefined||fixtureTLS&&fixtureFault)deny('transport_fixture');
 return session(()=>({host:'127.0.0.1',port:fixturePort,tls:fixtureTLS,synthetic:true,fixtureCA,fixtureFault}),'offline-synthetic');
}
