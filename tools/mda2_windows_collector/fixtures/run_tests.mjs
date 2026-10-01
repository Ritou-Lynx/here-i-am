import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { ICoreStore } from '../../i_core/i_core_store.mjs';
import { createICoreServer } from '../../i_core/i_core_server.mjs';
import { ACTIVITY_RAW_RETENTION_MS } from '../../i_core/activity_control_plane.mjs';
import { SurvivingBrokerAuthority } from '../../mda2_windows_queue/authority.mjs';
import { BOUNDED_ASYNC_TRANSPORT_V1,WindowsQueueBroker } from '../../mda2_windows_queue/broker.mjs';
import { createLoopbackActivityTransport,createLoopbackTestAuthority } from '../http_transport.mjs';
import { NativeCollectorChannel,NativeCollectorProcess } from '../native_channel.mjs';
import { WindowsCollectorWiring } from '../wiring.mjs';
import { coverageReport,initialNativeSignalState,parseNativeFrame,reduceNativePacket } from '../signals.mjs';

const workspace=fileURLToPath(new URL('../../../',import.meta.url));
const scratchBase=path.join(workspace,'tools','mda2_windows_collector','.scratch','tests');
fs.mkdirSync(scratchBase,{recursive:true});
const scratch=fs.mkdtempSync(path.join(scratchBase,'run-'));
const resultPath=path.join(workspace,'docs','development','activity','mda2','windows','w3','RESULT.json');
const evidence=[];let queueIndex=0,nativeBuild=null;
const wait=(ms)=>new Promise((resolve)=>setTimeout(resolve,ms));
const rejected=(promise,code)=>assert.rejects(promise,new RegExp(code));

class FakeClock{constructor(){this.age=100000;this.wall=1000000;}async sample(){if(this.lost)throw new Error('age_lost');return{age:this.age,wall:this.wall};}}
const packet=(overrides={})=>({nonce:'n'.repeat(43),epoch:'11111111-1111-4111-8111-111111111111',sessionId:7,
  source:'windows_wts',kind:'session.locked',captureAge:100000,captureWall:1000000,sequence:1,qualityEpoch:0,value:'',...overrides});
const frame=(value)=>['MDA2V1',value.nonce,value.epoch,value.sessionId,value.source,value.kind,value.captureAge,
  value.captureWall,value.sequence,value.qualityEpoch,value.value].join('|');

async function scenario(name,fn){
  try{const facts=await fn();evidence.push({name,passed:true,...(facts??{})});process.stdout.write(`PASS ${name}\n`);}
  catch(error){const code=/^[a-z_0-9]+$/.test(error.message)?error.message:'test_failed';evidence.push({name,passed:false,error:code});process.stderr.write(`FAIL ${name}: ${error.message}\n`);throw error;}
}

function safeRemoveOwned(target,parent){
  const parentReal=fs.realpathSync.native(parent),targetReal=fs.realpathSync.native(target);
  assert.equal(path.dirname(targetReal).toLowerCase(),parentReal.toLowerCase());
  assert.notEqual(targetReal.toLowerCase(),parentReal.toLowerCase());
  assert.equal(fs.lstatSync(targetReal).isSymbolicLink(),false);
  fs.rmSync(targetReal,{recursive:true,force:true});
}

function bindingsFromCore(clock){
  const core=new ICoreStore(':memory:',{activityEnabled:true,clock:()=>clock.wall});
  const bindings=[],principals=new Map();
  for(const source of ['windows_wts','windows_last_input']){
    const allowed=source==='windows_wts'?['session.locked','session.unlocked']:['input.idle_bucket'];
    const registration={device_id:'synthetic-w3',probe_id:`synthetic-${source}-${randomUUID()}`,display_name:'synthetic',
      capabilities:['activity.write'],source,coverage_mode:'discrete_best_effort',expected_report_interval_ms:100,
      expiry_slo_ms:ACTIVITY_RAW_RETENTION_MS,allowed_kinds:allowed};
    const paired=core.activity.pairProbe(registration);
    const binding={device_id:paired.device_id,probe_id:paired.probe_id,event_id_prefix:paired.event_id_prefix,source,
      coverage_mode:registration.coverage_mode,expected_report_interval_ms:100,allowed_kinds:allowed};
    bindings.push(binding);principals.set(binding.event_id_prefix,core.activity.authenticate(paired.probe_token));
  }
  return{core,bindings,principals};
}

function directReply(core,principals,bytes,binding){return core.activity.appendEvents(principals.get(binding.event_id_prefix),{events:[JSON.parse(bytes.toString())]});}
async function queueLab(transportFactory,options={}){
  const clock=new FakeClock(),issued=bindingsFromCore(clock),calls=[];
  const transport={kind:BOUNDED_ASYNC_TRANSPORT_V1,prepare(binding,context){
    let active,resolveCompletion,rejectCompletion,resolveExit,rejectExit;
    const completion=new Promise((resolve,reject)=>{resolveCompletion=resolve;rejectCompletion=reject;});
    const exited=new Promise((resolve,reject)=>{resolveExit=resolve;rejectExit=reject;});
    return{start(bytes){
      calls.push({source:binding.source,bytes:Buffer.from(bytes),context});
      let result;
      try{result=transportFactory({bytes,binding,context,calls,clock,...issued});}
      catch(error){rejectCompletion(error);resolveExit({closed:true});throw error;}
      if(result?.completion?.then&&result?.exited?.then&&typeof result.cancel==='function'){
        active=result;result.completion.then(resolveCompletion,rejectCompletion);result.exited.then(resolveExit,rejectExit);
      }else if(result?.then){
        rejectCompletion(new Error('fixture_async_contract_rejected'));rejectExit(new Error('fixture_async_contract_rejected'));
      }else{resolveCompletion(result);resolveExit({closed:true});}
      return true;
    },cancel(){return active?.cancel?.()??false;},completion,exited};
  }};
  const broker=new WindowsQueueBroker({clock,transport,maintenanceMs:60000,retryBaseMs:10,retryMaxMs:100,
    sendTimeoutMs:50,transportExitTimeoutMs:100,...options});
  const queues=new Map();
  for(const binding of issued.bindings){
    const root=path.join(scratch,`queue-${++queueIndex}`);await broker.registerFresh(binding,root);
    queues.set(binding.source,{binding,root,...await broker.start({binding,root,fresh:true})});
  }
  const enqueue=async(source,ttl=ACTIVITY_RAW_RETENTION_MS)=>{
    const q=queues.get(source),fact=source==='windows_wts'?{kind:'session.locked',payload:{}}:{kind:'input.idle_bucket',payload:{bucket:'lt_1m'}};
    const observation={contract:'device.activity.v1',schema_version:1,device_id:q.binding.device_id,probe_id:q.binding.probe_id,
      source,kind:fact.kind,signal_at_ms:clock.wall,ttl_ms:ttl,confidence:'high',coverage:{mode:'discrete_best_effort',
        window_start_ms:clock.wall,window_end_ms:clock.wall,expected_report_interval_ms:100},payload:fact.payload};
    const proof=await broker.capture(q.binding.event_id_prefix,observation);
    return broker.command(q.owner,'allocate',{observation,proof});
  };
  return{clock,broker,queues,calls,enqueue,...issued};
}

function deferred({ignoreCancel=false,autoExit=true}={}){
  let complete,rejectCompletion,resolveExit,rejectExit;
  const completion=new Promise((resolve,reject)=>{complete=resolve;rejectCompletion=reject;});
  const exited=new Promise((resolve,reject)=>{resolveExit=resolve;rejectExit=reject;});
  return{completion,exited,resolve(value){complete(value);if(autoExit)resolveExit({closed:true});},
    reject(error){rejectCompletion(error);if(autoExit)resolveExit({closed:true});},resolveExit,rejectExit,
    cancel(){if(ignoreCancel)return false;rejectCompletion(new Error('transport_cancelled'));resolveExit({closed:true});return true;}};
}
function failedTransport(error){return{completion:Promise.reject(error),exited:Promise.resolve({closed:true}),cancel(){return false;}};}
async function closeLab(lab){await lab.broker.close();lab.core.close();}

async function fakeHttp(handler){
  const sockets=new Set();const server=http.createServer(handler);server.on('connection',(socket)=>{sockets.add(socket);socket.on('close',()=>sockets.delete(socket));});
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
  const address=server.address();assert.notEqual(address.port,47841);
  return{baseUrl:`http://127.0.0.1:${address.port}`,port:address.port,async close(){for(const socket of sockets)socket.destroy();await new Promise((resolve)=>server.close(resolve));}};
}

async function transportCase(response,{maxResponseBytes=1024,timeoutMs=100}={}){
  const lab=await fakeHttp(response);const binding={device_id:'synthetic',probe_id:'synthetic-probe',event_id_prefix:'synthetic_prefix_1234567890',source:'windows_wts'};
  const bytes=Buffer.from(JSON.stringify({device_id:binding.device_id,probe_id:binding.probe_id,event_id:`${binding.event_id_prefix}.1`,origin_sequence:1,source:binding.source}));
  const transport=createLoopbackActivityTransport({baseUrl:lab.baseUrl,probeToken:'synthetic-probe-token-secret',testAuthority:createLoopbackTestAuthority(),timeoutMs,maxResponseBytes});
  const handle=transport.prepare(binding,{});handle.start(bytes);try{return await handle.completion;}finally{await handle.exited;await lab.close();}
}

async function pairHttp(baseUrl,token,source){
  const allowed=source==='windows_wts'?['session.locked','session.unlocked']:['input.idle_bucket'];
  const body={device_id:'synthetic-windows',probe_id:`synthetic-${source}`,display_name:'synthetic',capabilities:['activity.write'],source,
    coverage_mode:'discrete_best_effort',expected_report_interval_ms:100,expiry_slo_ms:ACTIVITY_RAW_RETENTION_MS,allowed_kinds:allowed};
  const response=await fetch(baseUrl+'/v1/core/activity/probes/pair',{method:'POST',headers:{'X-Core-Protocol':'0.1',Authorization:`Bearer ${token}`,'Content-Type':'application/json',Connection:'close'},body:JSON.stringify(body)});
  const paired=await response.json();if(response.status!==200)throw new Error(`pair_probe_${paired?.error?.code??response.status}`);
  return{binding:{device_id:paired.device_id,probe_id:paired.probe_id,event_id_prefix:paired.event_id_prefix,source,
    coverage_mode:body.coverage_mode,expected_report_interval_ms:100,allowed_kinds:allowed},probeToken:paired.probe_token};
}

try{
  await scenario('native_frame_strict_shape_and_privacy_rejection',async()=>{
    assert.deepEqual(parseNativeFrame(frame(packet())).kind,'session.locked');
    for(const bad of [frame(packet())+'|window-title',frame(packet({source:'windows_last_input'})),frame(packet({value:'private'}))])assert.throws(()=>parseNativeFrame(bad));
  });
  await scenario('lock_unlock_initial_unknown_and_current_session_only',async()=>{
    let state=initialNativeSignalState(packet());assert.deepEqual(state.observations,{});
    let reduced=reduceNativePacket(state,packet());assert.equal(reduced.fact.kind,'session.locked');state=reduced.state;
    assert.throws(()=>reduceNativePacket(state,packet({sequence:2,sessionId:8,captureAge:100001,captureWall:1000001})),/native_session_mismatch/);
  });
  await scenario('power_gap_requires_new_quality_epoch_and_new_observation',async()=>{
    let state=reduceNativePacket(initialNativeSignalState(packet()),packet()).state;
    state=reduceNativePacket(state,packet({source:'quality',kind:'power.suspended',sequence:2,captureAge:100001,captureWall:1000001,qualityEpoch:1})).state;
    assert.throws(()=>reduceNativePacket(state,packet({sequence:3,captureAge:100002,captureWall:1000002,qualityEpoch:0})),/native_quality_epoch_mismatch/);
    state=reduceNativePacket(state,packet({source:'quality',kind:'power.resumed',sequence:3,captureAge:100002,captureWall:1000002,qualityEpoch:2})).state;
    assert.deepEqual(state.observations,{});assert.equal(state.reason,'resume_gap');
  });
  await scenario('last_input_wrap_reconstructs_monotonic_absolute_coordinate',async()=>{
    const range=2**32;let state=initialNativeSignalState(packet());
    let value=reduceNativePacket(state,packet({source:'windows_last_input',kind:'input.sample',captureAge:range-500,captureWall:1000000,value:String(range-1000)}));
    assert.equal(value.fact.payload.bucket,'lt_1m');state=value.state;
    value=reduceNativePacket(state,packet({source:'windows_last_input',kind:'input.sample',captureAge:range+500,captureWall:1001000,sequence:2,value:'200'}));
    assert.equal(value.state.lastInputAbsolute,range+200);assert.equal(value.fact.payload.bucket,'lt_1m');
  });
  await scenario('same_dwtime_across_full_uint32_period_is_rejected',async()=>{
    const range=2**32;let state=reduceNativePacket(initialNativeSignalState(packet()),packet({source:'windows_last_input',kind:'input.sample',captureAge:range-1000,value:String(range-2000)})).state;
    assert.throws(()=>reduceNativePacket(state,packet({source:'windows_last_input',kind:'input.sample',captureAge:2*range-1000,captureWall:1000000+range,sequence:2,value:String(range-2000)})),/last_input_coordinate_untrusted/);
  });
  await scenario('non_increasing_source_age_and_tick_regression_rejected',async()=>{
    let state=reduceNativePacket(initialNativeSignalState(packet()),packet({source:'windows_last_input',kind:'input.sample',value:'99000'})).state;
    assert.throws(()=>reduceNativePacket(state,packet({source:'windows_last_input',kind:'input.sample',sequence:2,value:'99001'})),/native_source_age_non_increasing/);
    assert.throws(()=>reduceNativePacket(state,packet({source:'windows_last_input',kind:'input.sample',sequence:2,captureAge:100001,captureWall:1000001,value:'98000'})),/last_input_tick_regression/);
  });
  await scenario('coverage_never_projects_person_or_server_completeness',async()=>{
    const state=reduceNativePacket(initialNativeSignalState(packet()),packet()).state;const report=coverageReport(state,1000000,{maxGapMs:60000});
    assert.equal(report.person_state,'unknown');assert.equal(report.server_completeness,'unknown');
  });
  await scenario('authority_rejects_invalid_packet_before_any_channel_state_move',async()=>{
    const clock=new FakeClock(),authority=new SurvivingBrokerAuthority({clock}),issued=bindingsFromCore(clock);
    try{await authority.sample();for(const binding of issued.bindings)authority.registerFresh(binding,`C:/synthetic/${binding.source}`);
      const opened=authority.openNativeChannel(issued.bindings,{nonce:'n'.repeat(43),sessionId:7});const channel=authority.nativeChannels.get(opened.token);
      const before={sequence:channel.sequence,ageFloor:channel.ageFloor,qualityEpoch:channel.qualityEpoch};
      assert.throws(()=>authority.captureNative(opened.token,packet({epoch:opened.epoch,source:'quality',kind:'session.locked'}),null));
      assert.deepEqual({sequence:channel.sequence,ageFloor:channel.ageFloor,qualityEpoch:channel.qualityEpoch},before);
      const observation={source:'windows_wts',kind:'session.locked',signal_at_ms:1000000};
      const proof=authority.captureNative(opened.token,packet({epoch:opened.epoch}),observation);assert.equal(proof.value.origin,100000);
    }finally{issued.core.close();authority.dispose();}
  });
  await scenario('native_channel_capacity_close_and_terminal_invalid_frame',async()=>{
    const clock=new FakeClock(),issued=bindingsFromCore(clock),broker=new WindowsQueueBroker({clock,maintenanceMs:60000});
    try{for(const binding of issued.bindings)await broker.registerFresh(binding,`C:/synthetic/${binding.source}`);
      const first=await NativeCollectorChannel.open({broker,bindings:issued.bindings,sessionId:7,nonce:'n'.repeat(43)});
      await rejected(NativeCollectorChannel.open({broker,bindings:issued.bindings,sessionId:7,nonce:'m'.repeat(43)}),'native_channel_capacity');
      await rejected(first.submit(frame(packet({epoch:first.epoch,sessionId:8})),async()=>{}),'native_session_mismatch');assert.equal(first.closed,true);
      const second=await NativeCollectorChannel.open({broker,bindings:issued.bindings,sessionId:7,nonce:'m'.repeat(43)});await second.close();
    }finally{await broker.close();issued.core.close();}
  });

  const build=spawnSync('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(workspace,'tools','mda2_windows_collector','compile_native.ps1')],{encoding:'utf8',windowsHide:true});
  assert.equal(build.status,0,build.stderr);nativeBuild=JSON.parse(build.stdout.trim());
  await scenario('native_production_adapter_compiles_without_real_collection',async()=>{
    assert.ok(nativeBuild.bytes>0);assert.match(nativeBuild.sha256,/^[a-f0-9]{64}$/);return{compileExitCode:build.status,artifactSha256:nativeBuild.sha256,realOsCollection:false};
  });
  await scenario('native_unterminated_stdout_is_bounded_and_process_actually_exits',async()=>{
    const channel={nonce:'n'.repeat(43),epoch:'11111111-1111-4111-8111-111111111111',sessionId:7};
    const native=new NativeCollectorProcess({executable:nativeBuild.output,channel,onFrame:()=>{},mode:'synthetic',maxBufferedBytes:4096});
    await native.start();native.emitRawSynthetic(5000);const exit=await native.exited;
    assert.deepEqual(exit.frameErrors,['native_stdout_overflow']);assert.equal(exit.code,0);return{nativeExit:exit};
  });
  await scenario('native_callback_rejection_stops_reader_and_bounds_errors',async()=>{
    const channel={nonce:'n'.repeat(43),epoch:'11111111-1111-4111-8111-111111111111',sessionId:7};
    const native=new NativeCollectorProcess({executable:nativeBuild.output,channel,onFrame:async()=>{throw new Error('native_session_mismatch');},mode:'synthetic'});
    await native.start();native.emitSynthetic({source:'windows_wts',kind:'session.locked',captureAge:1,captureWall:1});
    const exit=await native.exited;assert.equal(exit.frames,1);assert.deepEqual(exit.frameErrors,['native_session_mismatch']);
    assert.throws(()=>native.emitSynthetic({source:'windows_wts',kind:'session.locked',captureAge:2,captureWall:2}),/synthetic_native_unavailable/);
    return{nativeExit:exit,subsequentFrames:0};
  });
  await scenario('native_bounded_queue_overflow_emits_contiguous_gap_then_recovers',async()=>{
    const channel={nonce:'n'.repeat(43),epoch:'11111111-1111-4111-8111-111111111111',sessionId:7},packets=[];
    const native=new NativeCollectorProcess({executable:nativeBuild.output,channel,onFrame:(line)=>packets.push(parseNativeFrame(line)),mode:'synthetic',maxBufferedBytes:1024*1024});
    await native.start();native.child.stdout.pause();
    for(let index=0;index<5000;index++)native.emitSynthetic({source:'windows_wts',kind:'session.locked',captureAge:index+1,captureWall:index+1});
    await wait(500);native.child.stdout.resume();await wait(500);
    native.emitSynthetic({source:'windows_wts',kind:'session.unlocked',captureAge:6000,captureWall:6000});await wait(500);
    const exit=await native.close();assert.equal(exit.code,0);assert.deepEqual(exit.frameErrors,[]);
    assert.ok(packets.some((value)=>value.kind==='source.gap'&&value.value==='native_overflow'));
    for(let index=0;index<packets.length;index++)assert.equal(packets[index].sequence,index+1);
    assert.equal(packets.at(-1).kind,'session.unlocked');return{nativeExit:exit,observedFrames:packets.length,gaps:packets.filter((value)=>value.kind==='source.gap').length};
  });
  await scenario('missing_native_executable_rolls_back_two_started_queues',async()=>{
    const clock=new FakeClock(),issued=bindingsFromCore(clock),broker=new WindowsQueueBroker({clock,maintenanceMs:60000});
    const roots=Object.fromEntries(issued.bindings.map((binding)=>[binding.source,path.join(scratch,'missing-'+binding.source)]));
    try{await rejected(WindowsCollectorWiring.open({broker,bindings:issued.bindings,roots,sessionId:7,nativeExecutable:path.join(scratch,'missing.exe'),nativeMode:'synthetic'}),'native_executable_missing');
      assert.equal(broker.closed,true);assert.equal(broker.children.size,0);assert.equal([...broker.authority.nativeChannels.values()].length,0);
      return{brokerRetired:true,liveQueues:0};
    }finally{await broker.close().catch(()=>{});issued.core.close();}
  });
  await scenario('native_channel_rejection_retires_process_queues_and_broker',async()=>{
    const clock=new FakeClock(),issued=bindingsFromCore(clock),broker=new WindowsQueueBroker({clock,maintenanceMs:60000});
    const roots=Object.fromEntries(issued.bindings.map((binding)=>[binding.source,path.join(scratch,'reject-'+binding.source)]));let wiring;
    try{wiring=await WindowsCollectorWiring.open({broker,bindings:issued.bindings,roots,sessionId:7,nativeExecutable:nativeBuild.output,nativeMode:'synthetic'});
      wiring.native.emitSynthetic({source:'windows_wts',kind:'session.locked',captureAge:100000,captureWall:1000000,sessionId:8});
      const nativeExit=await wiring.native.exited;for(let n=0;n<100&&!wiring.retirePromise;n++)await wait(5);assert.ok(wiring.retirePromise);const retired=await wiring.retirePromise;
      assert.deepEqual(nativeExit.frameErrors,['native_session_mismatch']);assert.equal(retired.retiredAfterNativeExit,true);assert.equal(broker.closed,true);assert.equal(broker.children.size,0);
      return{nativeExit,liveQueues:0,brokerRetired:true};
    }finally{await broker.close().catch(()=>{});issued.core.close();}
  });
  await scenario('second_source_start_failure_retires_first_worker_and_broker',async()=>{
    const clock=new FakeClock(),issued=bindingsFromCore(clock),broker=new WindowsQueueBroker({clock,maintenanceMs:60000}),shared=path.join(scratch,'shared-root');
    try{await assert.rejects(WindowsCollectorWiring.open({broker,bindings:issued.bindings,roots:{windows_wts:shared,windows_last_input:shared},sessionId:7}));
      assert.equal(broker.closed,true);assert.equal(broker.children.size,0);assert.ok(broker.events.some((event)=>event.type==='exit'));
      return{brokerRetired:true,liveQueues:0,workerExitObserved:true};
    }finally{await broker.close().catch(()=>{});issued.core.close();}
  });
  await scenario('hung_wts_allocation_does_not_block_last_input_allocation',async()=>{
    const clock=new FakeClock(),issued=bindingsFromCore(clock),broker=new WindowsQueueBroker({clock,maintenanceMs:60000});
    const roots=Object.fromEntries(issued.bindings.map((binding)=>[binding.source,path.join(scratch,'independent-'+binding.source)]));let wiring;
    try{wiring=await WindowsCollectorWiring.open({broker,bindings:issued.bindings,roots,sessionId:7});const original=broker.command.bind(broker),wts=wiring.queues.get('windows_wts');let release,held;
      broker.command=(owner,op,args)=>{if(owner===wts.owner&&op==='allocate'&&!held){held=new Promise((resolve)=>{release=()=>resolve(original(owner,op,args));});return held;}return original(owner,op,args);};
      clock.age=100001;clock.wall=1000001;const first=packet({nonce:wiring.channel.nonce,epoch:wiring.channel.epoch,sessionId:7});
      const wtsPending=wiring.consume(frame(first));for(let n=0;n<100&&!release;n++)await wait(5);assert.ok(release);
      const last={...first,source:'windows_last_input',kind:'input.sample',captureAge:100001,captureWall:1000001,sequence:2,value:'99501'};
      await wiring.consume(frame(last));const lastState=await original(wiring.queues.get('windows_last_input').owner,'inspect');assert.equal(lastState.rows.length,1);
      release();await wtsPending;assert.equal((await original(wts.owner,'inspect')).rows.length,1);return{wtsWasHeld:true,lastInputProgressed:true};
    }finally{if(wiring)await wiring.close().catch(()=>{});await broker.close().catch(()=>{});issued.core.close();}
  });
  await scenario('loopback_transport_rejects_active_port_and_nonloopback_targets',async()=>{
    const authority=createLoopbackTestAuthority(),options={probeToken:'synthetic-probe-token-secret',testAuthority:authority};
    for(const baseUrl of ['http://127.0.0.1:47841','http://localhost:49123','https://127.0.0.1:49123'])assert.throws(()=>createLoopbackActivityTransport({baseUrl,...options}),/loopback_transport_rejected/);
  });
  await scenario('unregistered_function_and_bare_promise_transport_rejected_before_dispatch',async()=>{
    const clock=new FakeClock();let calls=0;
    assert.throws(()=>new WindowsQueueBroker({clock,transport:()=>{calls++;return Promise.resolve();}}),/transport_contract_rejected/);
    assert.throws(()=>new WindowsQueueBroker({clock,transport:Promise.resolve()}),/transport_contract_rejected/);
    assert.equal(calls,0);
  });

  for(const [name,handler,code,options] of [
    ['http_429_is_retryable_unknown',(_q,r)=>{r.writeHead(429,{'content-type':'application/json'});r.end('{"error":{"code":"rate_limited"}}');},'transport_retryable'],
    ['http_5xx_is_retryable_unknown',(_q,r)=>{r.writeHead(503,{'content-type':'application/json'});r.end('{"error":{"code":"unavailable"}}');},'transport_retryable'],
    ['http_redirect_is_rejected',(_q,r)=>{r.writeHead(302,{'content-type':'application/json',location:'http://127.0.0.1:1/'});r.end('{}');},'transport_redirect_rejected'],
    ['http_malformed_response_is_rejected',(_q,r)=>{r.writeHead(200,{'content-type':'application/json'});r.end('{');},'transport_malformed_response'],
    ['http_oversize_response_is_rejected',(_q,r)=>{r.writeHead(200,{'content-type':'application/json'});r.end(JSON.stringify({padding:'x'.repeat(2048)}));},'transport_response_too_large',{maxResponseBytes:512}],
    ['http_wrong_event_receipt_is_rejected',(_q,r)=>{r.writeHead(200,{'content-type':'application/json'});r.end(JSON.stringify({results:[{status:'accepted',event_id:'wrong.1',receipt_id:'r',server_sequence:1}]}));},'transport_identity_rejected'],
    ['http_disconnect_is_unknown',(_q,r)=>r.destroy(),'transport_failed'],
    ['http_timeout_is_unknown',()=>{},'transport_(?:total|idle)_timeout',{timeoutMs:25}],
  ])await scenario(name,async()=>{await rejected(transportCase(handler,options),code);});
  await scenario('http_drip_response_hits_absolute_deadline_and_actual_socket_close',async()=>{
    let interval;const lab=await fakeHttp((_request,response)=>{response.writeHead(200,{'content-type':'application/json'});response.write('{"padding":"');interval=setInterval(()=>response.write('x'),10);response.on('close',()=>clearInterval(interval));});
    const binding={device_id:'synthetic',probe_id:'synthetic-probe',event_id_prefix:'synthetic_prefix_1234567890',source:'windows_wts'};
    const bytes=Buffer.from(JSON.stringify({device_id:binding.device_id,probe_id:binding.probe_id,event_id:`${binding.event_id_prefix}.1`,origin_sequence:1,source:binding.source}));
    const transport=createLoopbackActivityTransport({baseUrl:lab.baseUrl,probeToken:'synthetic-probe-token-secret',testAuthority:createLoopbackTestAuthority(),timeoutMs:80,maxResponseBytes:4096});
    try{const handle=transport.prepare(binding,{});handle.start(bytes);await rejected(handle.completion,'transport_total_timeout');const exit=await handle.exited;assert.equal(exit.closed,true);return{absoluteDeadline:true,actualSocketClose:true};}
    finally{clearInterval(interval);await lab.close();}
  });
  await scenario('http_premature_response_close_completes_once_and_observes_exit',async()=>{
    const lab=await fakeHttp((_request,response)=>{response.writeHead(200,{'content-type':'application/json'});response.write('{"results":');response.destroy();});
    const binding={device_id:'synthetic',probe_id:'synthetic-probe',event_id_prefix:'synthetic_prefix_1234567890',source:'windows_wts'};
    const bytes=Buffer.from(JSON.stringify({device_id:binding.device_id,probe_id:binding.probe_id,event_id:`${binding.event_id_prefix}.1`,origin_sequence:1,source:binding.source}));
    const transport=createLoopbackActivityTransport({baseUrl:lab.baseUrl,probeToken:'synthetic-probe-token-secret',testAuthority:createLoopbackTestAuthority(),timeoutMs:100});
    try{const handle=transport.prepare(binding,{});handle.start(bytes);await rejected(handle.completion,'transport_(?:failed|response_aborted)');assert.equal((await handle.exited).closed,true);}
    finally{await lab.close();}
  });
  await scenario('http_start_write_throw_waits_for_actual_request_close',async()=>{
    const lab=await fakeHttp(()=>{});let actualRequest,actualClosed=false;
    const binding={device_id:'synthetic',probe_id:'synthetic-probe',event_id_prefix:'synthetic_prefix_1234567890',source:'windows_wts'};
    const bytes=Buffer.from(JSON.stringify({device_id:binding.device_id,probe_id:binding.probe_id,event_id:`${binding.event_id_prefix}.1`,origin_sequence:1,source:binding.source}));
    const requestFactory=(options,callback)=>{actualRequest=http.request(options,callback);actualRequest.once('close',()=>{actualClosed=true;});
      actualRequest.write=()=>{throw new Error('synthetic_write_throw');};return actualRequest;};
    const transport=createLoopbackActivityTransport({baseUrl:lab.baseUrl,probeToken:'synthetic-probe-token-secret',
      testAuthority:createLoopbackTestAuthority(),timeoutMs:100,requestFactory});const handle=transport.prepare(binding,{});let exitSettled=false;
    handle.exited.then(()=>{exitSettled=true;});assert.throws(()=>handle.start(bytes),/synthetic_write_throw/);assert.equal(exitSettled,false);
    await rejected(handle.completion,'synthetic_write_throw');assert.equal((await handle.exited).closed,true);
    assert.equal(actualClosed,true);assert.equal(actualRequest.destroyed,true);await lab.close();
  });

  await scenario('cancellable_transport_handle_requires_independent_exit_proof',async()=>{
    let starts=0;const bad={kind:BOUNDED_ASYNC_TRANSPORT_V1,prepare(){return{
      start(){starts++;return true;},cancel(){return true;},completion:Promise.resolve({results:[]}),
    };}};const lab=await queueLab(()=>null,{transport:bad});
    try{
      await lab.enqueue('windows_wts');const q=lab.queues.get('windows_wts');
      await rejected(lab.broker.send(q.owner,1),'transport_exit_handle_required');
      assert.equal([...lab.broker.dispatches.values()].length,0);
      assert.equal((await lab.broker.command(q.owner,'inspect')).rows[0].status,'attempted_unknown');
      assert.equal(starts,0);
    }finally{await closeLab(lab);}
  });
  await scenario('started_transport_with_invalid_start_receipt_is_tracked_and_closed',async()=>{
    let starts=0,cancels=0,resolveExit,rejectCompletion;
    const completion=new Promise((_,reject)=>{rejectCompletion=reject;});const exited=new Promise((resolve)=>{resolveExit=resolve;});
    const transport={kind:BOUNDED_ASYNC_TRANSPORT_V1,prepare(){return{
      start(){starts++;return false;},cancel(){cancels++;rejectCompletion(new Error('transport_cancelled'));resolveExit({closed:true});return true;},completion,exited,
    };}};const lab=await queueLab(()=>null,{transport});
    try{
      await lab.enqueue('windows_wts');const q=lab.queues.get('windows_wts');const result=await lab.broker.send(q.owner,1);
      assert.equal(result.status,'attempted_unknown');const record=[...lab.broker.dispatches.values()][0];
      assert.equal(record.status,'complete');assert.equal(record.transportExited,true);assert.equal(starts,1);assert.equal(cancels,1);
    }finally{await closeLab(lab);}
  });
  await scenario('rejected_exit_proof_never_counts_as_transport_exit_or_success',async()=>{
    const gate=deferred({autoExit:false}),lab=await queueLab(({bytes,binding,core,principals})=>{
      queueMicrotask(()=>{gate.resolve(directReply(core,principals,bytes,binding));gate.rejectExit(new Error('no_exit_proof'));});return gate;
    });
    try{
      await lab.enqueue('windows_wts');const q=lab.queues.get('windows_wts');const result=await lab.broker.send(q.owner,1);
      assert.equal(result.status,'attempted_unknown');assert.equal(result.code,'transport_exit_unconfirmed');
      const record=[...lab.broker.dispatches.values()][0];assert.equal(record.transportExited,false);assert.equal(record.exitState,'unconfirmed');
      await rejected(lab.broker.stop(q.owner),'transport_exit_unconfirmed');
    }finally{await lab.broker.close().catch(()=>{});lab.core.close();}
  });
  await scenario('invalid_fulfilled_exit_receipt_never_counts_as_transport_exit',async()=>{
    const gate=deferred({autoExit:false}),lab=await queueLab(({bytes,binding,core,principals})=>{
      queueMicrotask(()=>{gate.resolve(directReply(core,principals,bytes,binding));gate.resolveExit({closed:false});});return gate;
    });
    try{
      await lab.enqueue('windows_wts');const q=lab.queues.get('windows_wts');const result=await lab.broker.send(q.owner,1);
      assert.equal(result.code,'transport_exit_unconfirmed');const record=[...lab.broker.dispatches.values()][0];
      assert.equal(record.transportExited,false);assert.equal(record.status,'exit_unconfirmed');
    }finally{await lab.broker.close().catch(()=>{});lab.core.close();}
  });
  await scenario('completed_response_stays_active_until_independent_exit_proof',async()=>{
    const gate=deferred({autoExit:false}),lab=await queueLab(({bytes,binding,core,principals,calls})=>{
      if(calls.length===1){queueMicrotask(()=>gate.resolve(directReply(core,principals,bytes,binding)));return gate;}
      return directReply(core,principals,bytes,binding);
    },{maxConcurrentTransports:1});
    try{
      await lab.enqueue('windows_wts');await lab.enqueue('windows_last_input');const a=lab.queues.get('windows_wts'),b=lab.queues.get('windows_last_input');
      const first=lab.broker.send(a.owner,1,{timeoutMs:1000});while(!lab.calls.length)await wait(5);await wait(10);
      const record=[...lab.broker.dispatches.values()][0];assert.equal(record.status,'pending');assert.equal(record.transportExited,false);
      await rejected(lab.broker.send(b.owner,1),'transport_concurrency_reached');gate.resolveExit({closed:true});assert.equal((await first).status,'accepted');
      assert.equal((await lab.broker.send(b.owner,1)).status,'accepted');
    }finally{await closeLab(lab);}
  });
  await scenario('close_rejects_when_completed_response_has_no_exit_proof',async()=>{
    const gate=deferred({autoExit:false,ignoreCancel:true}),lab=await queueLab(({bytes,binding,core,principals})=>{
      queueMicrotask(()=>gate.resolve(directReply(core,principals,bytes,binding)));return gate;
    },{transportExitTimeoutMs:30});
    await lab.enqueue('windows_wts');const q=lab.queues.get('windows_wts');const send=lab.broker.send(q.owner,1,{timeoutMs:20});
    while(!lab.calls.length)await wait(5);await rejected(send,'transport_wait_timeout');await rejected(lab.broker.close(),'transport_exit_unconfirmed');
    assert.equal(lab.broker.children.size,0);assert.equal([...lab.broker.dispatches.values()][0].transportExited,false);lab.core.close();
  });

  await scenario('pending_request_does_not_block_raw_expiry_maintenance_or_late_fence',async()=>{
    const gate=deferred({ignoreCancel:true}),lab=await queueLab(()=>gate);try{
      await lab.enqueue('windows_wts');const q=lab.queues.get('windows_wts');await rejected(lab.broker.send(q.owner,1,{timeoutMs:20}),'transport_wait_timeout');
      lab.clock.age+=ACTIVITY_RAW_RETENTION_MS;lab.clock.wall+=ACTIVITY_RAW_RETENTION_MS;await lab.broker.maintenance();
      const record=[...lab.broker.dispatches.values()].at(-1);assert.equal(record.bytes,null);assert.equal(record.cancelRequested,true);assert.equal(record.transportExited,false);
      gate.resolve(directReply(lab.core,lab.principals,lab.calls[0].bytes,q.binding));
      const late=await record.settlement;await record.actualExit;assert.equal(late.code,'late_transport_fenced');assert.equal(record.transportExited,true);
      const state=await lab.broker.command(q.owner,'inspect');assert.deepEqual(state.rows,[]);assert.equal(state.frozen,'retention_unresolved');assert.equal(lab.calls.length,1);
      return{lateReceipt:'discarded',dispatches:lab.calls.length};
    }finally{await closeLab(lab);}
  });
  await scenario('freeze_during_pending_allows_only_original_inflight_receipt',async()=>{
    const gate=deferred(),lab=await queueLab(()=>gate);try{
      await lab.enqueue('windows_wts');const q=lab.queues.get('windows_wts');const send=lab.broker.send(q.owner,1,{timeoutMs:1000});while(!lab.calls.length)await wait(5);
      await lab.broker.command(q.owner,'freeze');gate.resolve(directReply(lab.core,lab.principals,lab.calls[0].bytes,q.binding));
      assert.equal((await send).status,'accepted');await rejected(lab.enqueue('windows_wts'),'lineage_frozen');assert.equal(lab.calls.length,1);
    }finally{await closeLab(lab);}
  });
  await scenario('stop_cancels_transport_and_waits_for_actual_queue_exit',async()=>{
    const gate=deferred(),lab=await queueLab(()=>gate);try{
      await lab.enqueue('windows_wts');const q=lab.queues.get('windows_wts');const send=lab.broker.send(q.owner,1,{timeoutMs:1000});while(!lab.calls.length)await wait(5);
      const exit=await lab.broker.stop(q.owner);const outcome=await send;assert.equal(outcome.status,'attempted_unknown');assert.ok(exit.code===0||exit.signal==='SIGTERM');
      const events=lab.broker.events;assert.ok(events.some((e)=>e.type==='transport_cancel_requested'));assert.ok(events.some((e)=>e.type==='transport_exit'));
      return{queueExit:exit,transportCancelRequested:true,transportExited:true};
    }finally{await lab.broker.close();lab.core.close();}
  });
  await scenario('old_owner_late_reply_cannot_settle_reopened_owner',async()=>{
    const first=deferred();let count=0;const lab=await queueLab(({bytes,binding,core,principals})=>++count===1?first:directReply(core,principals,bytes,binding));
    try{await lab.enqueue('windows_wts');let q=lab.queues.get('windows_wts');const timed=lab.broker.send(q.owner,1,{timeoutMs:20});while(!lab.calls.length)await wait(5);await rejected(timed,'transport_wait_timeout');
      const old=lab.broker.children.get(q.owner);old.child.kill();await old.exited;q={...q,...await lab.broker.start({binding:q.binding,root:q.root})};lab.queues.set('windows_wts',q);
      first.resolve(directReply(lab.core,lab.principals,lab.calls[0].bytes,q.binding));const oldResult=await [...lab.broker.dispatches.values()][0].settlement;
      assert.ok(['owner_fenced','late_transport_fenced'].includes(oldResult.code));assert.equal((await lab.broker.command(q.owner,'inspect')).rows[0].status,'attempted_unknown');
      assert.equal((await lab.broker.send(q.owner,1)).status,'duplicate');return{oldReply:'fenced',newOwner:'settled_duplicate'};
    }finally{await closeLab(lab);}
  });
  await scenario('per_source_freeze_does_not_block_other_source',async()=>{
    const lab=await queueLab(({bytes,binding,core,principals})=>binding.source==='windows_wts'?{code:'scope_denied'}:directReply(core,principals,bytes,binding));
    try{await lab.enqueue('windows_wts');await lab.enqueue('windows_last_input');const wts=lab.queues.get('windows_wts'),last=lab.queues.get('windows_last_input');
      assert.equal((await lab.broker.send(wts.owner,1)).status,'terminal');assert.equal((await lab.broker.send(last.owner,1)).status,'accepted');
      assert.equal((await lab.broker.command(wts.owner,'inspect')).frozen,'transport_terminal');assert.equal((await lab.broker.command(last.owner,'inspect')).frozen,null);
    }finally{await closeLab(lab);}
  });
  await scenario('retry_backoff_preserves_original_bytes_without_busy_loop',async()=>{
    let retryNow=0,count=0;const lab=await queueLab(({bytes,binding,core,principals})=>++count===1?failedTransport(new Error('transport_retryable')):directReply(core,principals,bytes,binding),{retryNow:()=>retryNow});
    try{await lab.enqueue('windows_wts');const q=lab.queues.get('windows_wts');assert.equal((await lab.broker.send(q.owner,1)).status,'attempted_unknown');
      await rejected(lab.broker.send(q.owner,1),'transport_backoff');retryNow=10;assert.equal((await lab.broker.send(q.owner,1)).status,'accepted');
      assert.equal(lab.calls[0].bytes.equals(lab.calls[1].bytes),true);return{attempts:2,bytesPreserved:true};
    }finally{await closeLab(lab);}
  });
  await scenario('global_pending_limit_is_bounded_and_does_not_consume_new_sequence',async()=>{
    const gate=deferred();let count=0;const lab=await queueLab(({bytes,binding,core,principals})=>++count===1?gate:directReply(core,principals,bytes,binding),{maxConcurrentTransports:1});
    try{await lab.enqueue('windows_wts');await lab.enqueue('windows_last_input');const a=lab.queues.get('windows_wts'),b=lab.queues.get('windows_last_input');
      const first=lab.broker.send(a.owner,1,{timeoutMs:1000});while(!lab.calls.length)await wait(5);await rejected(lab.broker.send(b.owner,1),'transport_concurrency_reached');
      gate.resolve(directReply(lab.core,lab.principals,lab.calls[0].bytes,a.binding));assert.equal((await first).status,'accepted');assert.equal((await lab.broker.send(b.owner,1)).status,'accepted');
      assert.equal((await lab.broker.command(b.owner,'inspect')).next,2);
    }finally{await closeLab(lab);}
  });

  await scenario('synthetic_native_to_disk_to_random_loopback_core_to_summary',async()=>{
    const clock=new FakeClock(),directory=path.join(scratch,'core-http'),admin='synthetic-admin-'+randomUUID();fs.mkdirSync(directory,{recursive:true});
    const core=createICoreServer({databasePath:path.join(directory,'core.sqlite'),activityAdminSecret:admin,clock:()=>clock.wall});const address=await core.listen({host:'127.0.0.1',port:0});
    assert.notEqual(address.port,47841);const baseUrl=`http://127.0.0.1:${address.port}`;
    const pairs=[await pairHttp(baseUrl,admin,'windows_wts'),await pairHttp(baseUrl,admin,'windows_last_input')];
    const readerResponse=await fetch(baseUrl+'/v1/core/activity/readers/pair',{method:'POST',headers:{'X-Core-Protocol':'0.1',Authorization:`Bearer ${admin}`,'Content-Type':'application/json',Connection:'close'},body:JSON.stringify({installation_id:'synthetic-reader',display_name:'synthetic',capabilities:[]})});
    const reader=await readerResponse.json();if(readerResponse.status!==200)throw new Error(`pair_reader_${reader?.error?.code??readerResponse.status}`);const authority=createLoopbackTestAuthority();
    const transports=new Map(pairs.map((pair)=>[pair.binding.event_id_prefix,createLoopbackActivityTransport({baseUrl,probeToken:pair.probeToken,testAuthority:authority})]));
    const transport={kind:BOUNDED_ASYNC_TRANSPORT_V1,prepare(binding,context){return transports.get(binding.event_id_prefix).prepare(binding,context);}};
    const broker=new WindowsQueueBroker({clock,transport,maintenanceMs:60000});
    const roots=Object.fromEntries(pairs.map((pair)=>[pair.binding.source,path.join(scratch,'e2e-'+pair.binding.source)]));let wiring;
    try{
      wiring=await WindowsCollectorWiring.open({broker,bindings:pairs.map((pair)=>pair.binding),roots,sessionId:7,nativeExecutable:nativeBuild.output,nativeMode:'synthetic'});
      clock.age=100001;clock.wall=1000001;
      wiring.native.emitSynthetic({source:'windows_wts',kind:'session.unlocked',captureAge:100000,captureWall:1000000,qualityEpoch:0});
      wiring.native.emitSynthetic({source:'windows_last_input',kind:'input.sample',captureAge:100001,captureWall:1000001,qualityEpoch:0,value:'99501'});
      for(let n=0;n<100;n++){const a=await broker.command(wiring.queues.get('windows_wts').owner,'inspect'),b=await broker.command(wiring.queues.get('windows_last_input').owner,'inspect');if(a.rows.length===1&&b.rows.length===1)break;await wait(10);}
      assert.equal((await wiring.flush('windows_wts')).status,'accepted');assert.equal((await wiring.flush('windows_last_input')).status,'accepted');
      const local=await wiring.summary(clock.wall);assert.equal(local.person_state,'unknown');assert.equal(local.server_completeness,'unknown');
      const summaryResponse=await fetch(baseUrl+'/v1/core/activity/summary',{headers:{'X-Core-Protocol':'0.1',Authorization:`Bearer ${reader.reader_token}`,Connection:'close'}});assert.equal(summaryResponse.status,200);const summary=await summaryResponse.json();
      assert.equal(summary.devices[0].sources.length,2);const closed=await wiring.close();assert.equal(closed.nativeExit.code,0);assert.deepEqual(closed.nativeExit.frameErrors,[]);
      await broker.close();await core.close();return{loopbackPort:address.port,nativeExit:closed.nativeExit,queueExitCount:2,realOsCollection:false,realCredentials:false};
    }finally{if(wiring&&!wiring.closed)await wiring.close().catch(()=>{});await broker.close().catch(()=>{});await core.close().catch(()=>{});}
  });

  const preliminary={suite:'mda2-w3-windows-wiring-v1',passed:evidence.filter((item)=>item.passed).length,failed:0,
    scratchRemoved:false,realOsCollection:false,productionEndpointUsed:false,activePort47841Used:false,nativeBuild,evidence};
  fs.mkdirSync(path.dirname(resultPath),{recursive:true});fs.writeFileSync(resultPath,JSON.stringify(preliminary,null,2)+'\n');
  safeRemoveOwned(scratch,scratchBase);
  const nativeDir=path.join(workspace,'tools','mda2_windows_collector','.scratch','native');
  if(fs.existsSync(nativeDir))safeRemoveOwned(nativeDir,path.dirname(nativeDir));
  preliminary.scratchRemoved=!fs.existsSync(scratch)&&!fs.existsSync(nativeDir);fs.writeFileSync(resultPath,JSON.stringify(preliminary,null,2)+'\n');
  process.stdout.write(`RESULT ${resultPath}\nPASS_COUNT ${preliminary.passed}\nSCRATCH_REMOVED ${preliminary.scratchRemoved}\n`);
}catch(error){
  const failure={suite:'mda2-w3-windows-wiring-v1',passed:evidence.filter((item)=>item.passed).length,failed:1,
    scratchRemoved:false,realOsCollection:false,productionEndpointUsed:false,activePort47841Used:false,nativeBuild,evidence,
    failure:/^[a-z_0-9]+$/.test(error.message)?error.message:'test_failed'};
  fs.mkdirSync(path.dirname(resultPath),{recursive:true});fs.writeFileSync(resultPath,JSON.stringify(failure,null,2)+'\n');
  try{
    if(fs.existsSync(scratch))safeRemoveOwned(scratch,scratchBase);
    const nativeDir=path.join(workspace,'tools','mda2_windows_collector','.scratch','native');
    if(fs.existsSync(nativeDir))safeRemoveOwned(nativeDir,path.dirname(nativeDir));
    failure.scratchRemoved=!fs.existsSync(scratch)&&!fs.existsSync(nativeDir);
  }catch(cleanupError){failure.cleanupError=/^[a-z_0-9]+$/.test(cleanupError.message)?cleanupError.message:'cleanup_failed';}
  fs.writeFileSync(resultPath,JSON.stringify(failure,null,2)+'\n');
  process.stderr.write(`FAIL ${failure.failure}\n`);process.exitCode=1;
}
