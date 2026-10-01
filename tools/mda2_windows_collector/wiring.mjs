import { NativeCollectorChannel, NativeCollectorProcess } from './native_channel.mjs';
import { WINDOWS_SOURCES, coverageReport, reject } from './signals.mjs';

function bindingMap(bindings) {
  if(!Array.isArray(bindings)||bindings.length!==2)reject('invalid_authorized_bindings');
  const map=new Map();
  for(const binding of bindings){
    if(!binding||!WINDOWS_SOURCES.includes(binding.source)||map.has(binding.source))reject('invalid_authorized_bindings');
    const expected=binding.source==='windows_wts'?['session.locked','session.unlocked']:['input.idle_bucket'];
    if(JSON.stringify(binding.allowed_kinds)!==JSON.stringify(expected)||binding.coverage_mode!=='discrete_best_effort')reject('invalid_authorized_bindings');
    map.set(binding.source,structuredClone(binding));
  }
  if(map.size!==2)reject('invalid_authorized_bindings');
  return map;
}

function observation(binding,fact,ttlMs){
  return {contract:'device.activity.v1',schema_version:1,device_id:binding.device_id,probe_id:binding.probe_id,
    kind:fact.kind,signal_at_ms:fact.signal_at_ms,ttl_ms:ttlMs,confidence:'high',source:binding.source,
    coverage:{mode:binding.coverage_mode,window_start_ms:fact.signal_at_ms,window_end_ms:fact.signal_at_ms,
      expected_report_interval_ms:binding.expected_report_interval_ms},payload:structuredClone(fact.payload)};
}

export class WindowsCollectorWiring {
  static async open({broker,bindings,roots,sessionId,ttlMs=300000,fresh=true,nativeExecutable=null,
    nativeMode='disabled',productionAuthorized=false}){
    if(!broker||!roots||!Number.isSafeInteger(ttlMs)||ttlMs<1)reject('invalid_wiring');
    const wiring=new WindowsCollectorWiring();wiring.broker=broker;wiring.bindings=bindingMap(bindings);
    wiring.queues=new Map();wiring.ttlMs=ttlMs;wiring.closed=false;
    try{
      for(const source of WINDOWS_SOURCES){
        const binding=wiring.bindings.get(source),root=roots[source];
        if(typeof root!=='string')reject('invalid_queue_root');
        await broker.registerFresh(binding,root);
        const opened=await broker.start({binding,root,fresh});wiring.queues.set(source,{...opened,binding,root});
      }
      wiring.channel=await NativeCollectorChannel.open({broker,bindings:[...wiring.bindings.values()],sessionId});
      wiring.consume=async(line)=>{
        const accepted=await wiring.channel.submit(line,(fact)=>{
          const queue=wiring.queues.get(fact.source),value=observation(queue.binding,fact,wiring.ttlMs);
          return{observation:value,allocate:(proof)=>broker.command(queue.owner,'allocate',{observation:value,proof})};
        });
        return accepted.allocation;
      };
      if(nativeMode!=='disabled'){
        wiring.native=new NativeCollectorProcess({executable:nativeExecutable,channel:wiring.channel,onFrame:wiring.consume,mode:nativeMode});
        wiring.nativeStart=await wiring.native.start({productionAuthorized});
        wiring.native.exited.then((exit)=>{if(!wiring.closed)wiring.retirePromise=wiring.retireAfterNativeExit(exit);}).catch(()=>{});
      }
      return wiring;
    }catch(error){
      await wiring.native?.close().catch(()=>{});await wiring.channel?.close().catch(()=>{});
      for(const queue of wiring.queues.values())await broker.stop(queue.owner).catch(()=>{});
      await broker.close().catch(()=>{});wiring.closed=true;throw error;
    }
  }
  async flush(source,{timeoutMs}={}){
    const queue=this.queues.get(source);if(!queue||this.closed)reject('wiring_closed');
    const state=await this.broker.command(queue.owner,'inspect');
    const row=state.rows.find((value)=>['never_sent','attempted_unknown'].includes(value.status));
    if(!row)return {status:'empty',transport:'unobserved'};
    return this.broker.send(queue.owner,row.sequence,{...(timeoutMs?{timeoutMs}:{})});
  }
  async summary(nowMs,{maxGapMs=60000}={}){
    const deliveryBySource={};const queues={};
    for(const [source,queue] of this.queues){
      queues[source]=await this.broker.command(queue.owner,'inspect');
      deliveryBySource[source]=queues[source].rows.some((row)=>row.status==='attempted_unknown')?'attempted_unknown'
        :queues[source].rows.some((row)=>['accepted','duplicate'].includes(row.status))?'acknowledged':'pending';
    }
    return {...coverageReport(this.channel.state,nowMs,{maxGapMs,deliveryBySource}),queues};
  }
  async close(){
    if(this.closed)return this.closeResult;this.closed=true;
    const nativeExit=await this.native?.close();await this.channel.close();
    const queueExits={};for(const [source,queue] of this.queues)queueExits[source]=await this.broker.stop(queue.owner).catch((error)=>({error:error.message}));
    await this.broker.close();this.closeResult={nativeExit,queueExits,brokerClosed:true};return this.closeResult;
  }
  async retireAfterNativeExit(nativeExit){
    this.closed=true;await this.channel.close().catch(()=>{});const queueExits={};
    for(const [source,queue] of this.queues)queueExits[source]=await this.broker.stop(queue.owner).catch((error)=>({error:error.message}));
    await this.broker.close().catch(()=>{});this.closeResult={nativeExit,queueExits,brokerClosed:true,retiredAfterNativeExit:true};return this.closeResult;
  }
}
