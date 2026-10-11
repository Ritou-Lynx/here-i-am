// Dormant production composition. Default Plan performs no filesystem, network or child I/O.
import {prepareP4EvidenceContext} from './evidence-context-r09.mjs';
import {createReviewedTransport} from './p4-bounded-transport-r05.mjs';
import {executeP4,plan} from './p4-health-policy-dormant-r01.mjs';
const payload = r => ({healthStable:r.healthStable,localHealth:r.localHealth,publicDiscovery:r.publicDiscovery,backupEvidenceComplete:false,overallP4Passed:false,requestsCompleted:r.checks.filter(x=>x.passed).length,sampleCount:r.samples.length,failureCode:r.failure===null?'none':'health_failed',containmentRequired:r.failure!==null});
export async function runPinnedP4({execute=false}={}) {
 if(execute!==true)return plan();
 const ctx=await prepareP4EvidenceContext();
 const empty={format:'p4-health-result-v1',mode:'reviewed-live',bindingSha256:ctx.expected.bindingSha256,localHealth:false,publicDiscovery:false,healthStable:false,backupEvidenceComplete:false,overallP4Passed:false,samples:[],checks:[],failure:null,automaticRestart:false,automaticClose:false};
 await ctx.appendReceipt({phase:'intent',payload:payload(empty)});
 let result;
 try{
  const transport=await createReviewedTransport({review:ctx.review,authorization:ctx.authorization,verifyAuthorization:ctx.verifyTransportAuthorization,endpointAllowlist:ctx.endpointAllowlist});
  result=await executeP4({execute:true,expected:ctx.expected,authorization:ctx.authorization,transport,observeIdentity:ctx.observeIdentity,clock:ctx.clock,verifyAuthorization:ctx.verifyAuthorization});
 }catch{result={...empty,failure:'dependency_or_transport_failure'};}
 await ctx.appendReceipt({phase:'result',payload:payload(result)});
 await ctx.appendReceipt({phase:'commit',payload:payload(result)});
 ctx.complete(result);
 return result;
}
// This pinned CLI accepts no caller-supplied dependencies, clock, observer or payload.
if(process.argv[1] && new URL(import.meta.url).pathname.toLowerCase().endsWith('/'+process.argv[1].replaceAll('\\','/').split('/').at(-1).toLowerCase())){
 const args=process.argv.slice(2);
 if(args.length===0)process.stdout.write(JSON.stringify(await runPinnedP4())+'\n');
 else if(args.length===1&&args[0]==='--execute-pinned-p4'){
  const watchdog=setTimeout(()=>{process.exitCode=124;process.stdin.destroy();},70000);watchdog.unref();
  try{await runPinnedP4({execute:true});}catch{process.exitCode=2;process.stdin.destroy();}finally{clearTimeout(watchdog);}
 }else{process.exitCode=2;}
}
