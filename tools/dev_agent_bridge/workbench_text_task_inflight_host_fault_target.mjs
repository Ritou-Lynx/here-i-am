// Witness-only candidate. Native retains its default three private pipes.
import http from 'node:http';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { ExperimentalRuntimeApi, EXPERIMENTAL_RUNTIME_PREFIX } from './experimental_runtime_api.mjs';
import { WorkbenchTextTaskRuntimeAdapter } from './workbench_text_task_runtime_adapter.mjs';
import { createTextTaskBroker } from './workbench_text_task_broker.mjs';
import { launchWorkbenchTextNativeExecutor } from './workbench_text_task_native_executor.mjs';
import { CodexAppServerClient } from './codex_app_server_client.mjs';
import { createBridgeRuntimeShutdown } from './bridge_runtime_shutdown.mjs';
import { exchangeTextOnly } from './workbench_text_gate_transport.mjs';
import { INFLIGHT_FIXED_INPUT, validateInflightInitial, makeInflightReady, observeInflightExchange,
  createInflightControlReader } from './workbench_text_task_inflight_host_fault_contract.mjs';

const fail = () => new Error('inflight_host_fault_target_unconfirmed');
const need = value => { if (!value) throw fail(); };
const emit = value => new Promise((resolve,reject) => process.stdout.write(`${JSON.stringify(value)}\n`,error => error ? reject(fail()) : resolve()));
export async function runInflightHostFaultTarget({executable,sha256}) {
  need(path.isAbsolute(executable) && /^[a-f0-9]{64}$/.test(sha256));
  let owner,broker,startup,attempt,port,adapter,initial,closePromise;
  let closing=false,initialSent=false,turns=0,arms=0,dispatched=false,terminalObserved=false,textObserved=false;
  const observed=observeInflightExchange(exchangeTextOnly);
  const localAgent=new http.Agent({keepAlive:false,proxyEnv:Object.freeze(Object.create(null))});
  const api=new ExperimentalRuntimeApi({enabled:true,adapterFactory:()=>{throw fail();},textAdapterFactory:()=>{
    need(!adapter);
    adapter=new WorkbenchTextTaskRuntimeAdapter({nativeOptions:{executable,sha256},factories:{
      createBroker(options) {
        need(!broker); broker=createTextTaskBroker({...options,exchange:observed.exchange});
        return {listen:()=>broker.listen(),close:()=>broker.close(),revoke:()=>broker.revoke(),snapshot:()=>broker.snapshot(),
          arm(input){need(!closing && initialSent && ++arms===1 && input===INFLIGHT_FIXED_INPUT);broker.arm(input);}};
      },
      createOwner(options) {
        need(!owner);attempt=options.attemptId;port=options.brokerPort;owner=launchWorkbenchTextNativeExecutor(options);
        void owner.ready.then(value=>{startup=value;},()=>{});return owner;
      },
      createClient(options) {
        const client=new CodexAppServerClient(options);const request=client.request.bind(client);
        client.request=(method,params,options)=>{
          if(method!=='turn/start')return request(method,params,options);
          need(!closing && initialSent && ++turns===1);
          const prior=options?.onDispatched;
          return request(method,params,{...options,onDispatched:()=>{dispatched=true;prior?.();}});
        };
        client.on('notification',entry=>{
          if(turns===0)return;
          // Conservative: any terminal/text while this single turn is pending
          // prevents a ready frame, even if it has an unexpected binding.
          if(entry.message?.method==='turn/completed')terminalObserved=true;
          if(entry.message?.method==='item/agentMessage/delta')textObserved=true;
        });return client;
      },
    }});return adapter;
  }});
  const server=http.createServer((req,res)=>{void api.handle(req,res,new URL(req.url,'http://127.0.0.1')).catch(()=>res.destroy());});
  const shutdown=createBridgeRuntimeShutdown({runtimeApi:api,server,httpGraceMs:1000});
  const close=()=>{
    if(closePromise)return closePromise;
    closing=true;
    closePromise=(async()=>{
      try {await shutdown.shutdown();localAgent.destroy();
        await emit({schema:'p6_r7_host_fault_control_v1',type:'closed',cleanup_confirmed:true});
        process.stdin.pause();process.exitCode=0;
      } catch {await emit({schema:'p6_r7_host_fault_control_v1',type:'unconfirmed',cleanup_confirmed:false}).catch(()=>{});
        closePromise=null; // Same API/owner retained for an explicit retry.
      }
    })();return closePromise;
  };
  const request=(suffix,body)=>new Promise((resolve,reject)=>{
    const bytes=Buffer.from(JSON.stringify(body));
    const req=http.request({host:'127.0.0.1',port:server.address().port,path:`${EXPERIMENTAL_RUNTIME_PREFIX}${suffix}`,
      method:'POST',agent:localAgent,headers:{'content-type':'application/json','content-length':bytes.length}},res=>{
      const chunks=[];let size=0;res.on('data',chunk=>{size+=chunk.length;if(size>16384){req.destroy();reject(fail());}else chunks.push(chunk);});
      res.on('error',()=>reject(fail()));res.on('end',()=>{try{need(res.statusCode===200);resolve(JSON.parse(Buffer.concat(chunks)));}catch{reject(fail());}});
    });req.setTimeout(180000,()=>{req.destroy();reject(fail());});req.on('error',()=>reject(fail()));req.end(bytes);
  });
  const start=async()=>{
    try {
      need(initialSent && !closing);
      // Fully consume the real HTTP response; never trigger its disconnect cleanup.
      const turn=await request(`/sessions/${initial.local_session_id}/turns`,{input:INFLIGHT_FIXED_INPUT});
      const deadline=performance.now()+20000;
      while(observed.snapshot().entered===0){
        need(!closing && !terminalObserved && !textObserved && performance.now()<deadline);
        await new Promise(resolve=>setTimeout(resolve,5));
      }
      // No await between this snapshot, its checks, and stdout write. It is a
      // readiness observation, never an atomic statement about the later kill.
      const ready=makeInflightReady(initial,turn,{closing,turns,arms,dispatched,exchange:observed.snapshot(),
        broker:broker.snapshot(),events:adapter.readEvents(initial.local_session_id),terminalObserved,textObserved});
      await emit(ready);
    } catch {await close();}
  };
  const control=createInflightControlReader({onStart:()=>{void start();},onGraceful:()=>{void close();}});
  process.stdin.setEncoding('utf8');process.stdin.on('data',chunk=>control.push(chunk));
  process.stdin.on('end',()=>{void close();});process.on('SIGINT',()=>{void close();});process.on('SIGTERM',()=>{void close();});
  const watchdog=setTimeout(()=>{void close();},300000);watchdog.unref();
  try {
    await new Promise((resolve,reject)=>{server.once('error',()=>reject(fail()));server.listen(0,'127.0.0.1',resolve);});need(!closing);
    const epoch=randomUUID();const result=await request('/sessions',{config:{runtime_profile:'workbench_text_only_v1'},context_manifest:{execution_epoch:epoch}});
    const r=result.execution_profile_receipt;
    need(!closing && r?.profile==='workbench_text_only_v1' && r.version===2 && r.local_session_id===result.session_id
      && r.execution_epoch===epoch && r.provider_thread_id===result.provider_metadata?.provider_session_id
      && r.isolation_verified===true && r.tools_disabled===true && startup && turns===0 && arms===0);
    const b=broker.snapshot();need(b.upstream_attempts===0 && !b.response_released && b.rejected_connections===0
      && b.rejected_requests===0 && b.metadata_rejections<=8 && b.parsed_requests===b.metadata_rejections
      && b.admitted_connections===b.metadata_rejections);
    initial={schema:'p6_r7_inflight_initial_v1',local_session_id:r.local_session_id,execution_epoch:epoch,provider_thread_id:r.provider_thread_id,
      native_ready:{schema:'p6_r7_host_fault_ready_v1',attempt_id:attempt,child_pid:startup.pid,child_creation:startup.creation_time,
        cli_sha256:startup.cli_sha256,broker_port:port,http_created:true,no_model:true,default_three_pipes:true}};
    validateInflightInitial(initial);initialSent=true;await emit(initial);
  } catch {await close();}
}
export async function main(argv=process.argv.slice(2)) {
  need(argv.length===3 && argv[0]==='--inflight-host-fault-target');await runInflightHostFaultTarget({executable:argv[1],sha256:argv[2]});
}
if(process.argv[1] && import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href)await main();
