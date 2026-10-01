// Self-created synthetic resources only. This executable is not an OS collector.
import { WindowsQueueBroker } from '../broker.mjs';
import { WindowsAgeClock } from '../authority.mjs';
import { ICoreStore } from '../../i_core/i_core_store.mjs';
import { hash, encode } from '../store.mjs';
import { normalizeActivityEvent } from '../../i_core/activity_control_plane.mjs';

let broker, core, clock, mode = 'core', counter = 0;
const bindings = new Map(), principals = new Map(), sends = [];
class FixtureClock {
  constructor() { this.age = 100000; this.wall = 1000000; }
  async sample() { if (this.lost) throw new Error('lost'); return { age: this.age, wall: this.wall }; }
}
async function dispatch(op,args) {
  if (op === 'init') {
    clock = args.realClock ? new WindowsAgeClock() : new FixtureClock();
    const initial = await clock.sample();
    core = new ICoreStore(':memory:', { activityEnabled: true, clock: () => broker?.authority.time?.wall ?? initial.wall });
    broker = new WindowsQueueBroker({ clock, maintenanceMs: args.maintenanceMs ?? 60000, allowSynchronousFixtureTransport:true, transport: (bytes,binding) => {
      if (mode === 'offline') return { code: 'transport_unavailable' };
      if (mode === 'malformed') return { results: [{ status:'accepted',event_id:'wrong',receipt_id:'bad',server_sequence:1 }] };
      const event = JSON.parse(bytes.toString());
      sends.push({ digest: hash(bytes), sequence: event.origin_sequence, lineage: binding.event_id_prefix });
      try { return core.activity.appendEvents(principals.get(binding.event_id_prefix), { events: [event] }); }
      catch (e) { return { code: e.code ?? 'unknown_core_error' }; }
    } });
    return { pid: process.pid, clock: args.realClock ? 'native_GetTickCount64' : 'explicit_fixture_clock' };
  }
  if (op === 'new') {
    const source = args.source ?? 'windows_wts';
    const allowed = source === 'windows_wts' ? ['session.unlocked','session.locked'] : ['input.idle_bucket'];
    const registration = { device_id:'synthetic-w2', probe_id:`synthetic-w2-${++counter}`, display_name:'synthetic',
      capabilities:['activity.write'], source, coverage_mode:'discrete_best_effort', expected_report_interval_ms:100,
      expiry_slo_ms:86400000, allowed_kinds:allowed };
    const paired = core.activity.pairProbe(registration);
    const binding = { device_id:paired.device_id,probe_id:paired.probe_id,event_id_prefix:paired.event_id_prefix,
      source,coverage_mode:registration.coverage_mode,expected_report_interval_ms:100,allowed_kinds:allowed };
    principals.set(binding.event_id_prefix,core.activity.authenticate(paired.probe_token));
    bindings.set(binding.event_id_prefix,binding);
    await broker.registerFresh(binding,args.root);
    return { binding };
  }
  if (op === 'capture') {
    const binding = bindings.get(args.lineage), time = await clock.sample();
    const observation = { contract:'device.activity.v1',schema_version:1,device_id:binding.device_id,probe_id:binding.probe_id,
      kind:args.kind ?? binding.allowed_kinds[0],signal_at_ms:time.wall,ttl_ms:args.ttl ?? 86400000,confidence:'high',
      source:binding.source,coverage:{mode:binding.coverage_mode,window_start_ms:time.wall,window_end_ms:time.wall,
        expected_report_interval_ms:100},payload:binding.source === 'windows_wts' ? {} : {bucket:'lt_1m'} };
    const proof = await broker.capture(args.lineage,observation);
    return { observation,proof };
  }
  if (op === 'start') return broker.start(args);
  if (op === 'command') return broker.command(args.owner,args.op,args.args);
  if (op === 'stop') return broker.stop(args.owner,args.crash);
  if (op === 'setTime') { if (!(clock instanceof FixtureClock)) throw new Error('fixture_only'); Object.assign(clock,args); return true; }
  if (op === 'mode') { mode=args.value; return true; }
  if (op === 'events') return { events:broker.events,sends,live:[...broker.children.values()].filter(r=>!r.dead).map(r=>({pid:r.child.pid,owner:r.owner})),epoch:broker.authority.epoch };
  if (op === 'authorityState') {
    const a=broker.authority.get(args.lineage); return { nextFloor:a.nextFloor,revisionFloor:a.revisionFloor,frozen:a.frozen,owner:a.owner,
      retainedProofs:a.consumed.size,retainedDispatches:a.dispatched.size,retainedRows:(a.current?.rows.length??0)+(a.pending?.rows.length??0) };
  }
  if (op === 'maintenance') { await broker.maintenance(); return true; }
  if (op === 'lostAge') { if (clock instanceof FixtureClock) clock.lost=true; else clock.child.kill(); await broker.authority.sample(); return true; }
  if (op === 'lostGuard') {const r=broker.children.get(args.owner);process.kill(r.guardPid);return {pid:r.guardPid};}
  if (op === 'staleSend') {
    // Direct test of owner gating, including a still-reachable old callback.
    return broker.authority.authorizeSend(args.lineage,args.owner,args.attempt,Buffer.from('synthetic'));
  }
  if (op === 'forgePrepare') {
    await broker.authority.sample();
    const a=broker.authority.get(args.lineage), proposal=structuredClone(a.current);
    proposal.revision=(a.revisionFloor??-1)+1;proposal.fence=a.fence;proposal.digest='a'.repeat(64);
    let cap;
    const newRow=()=>{
      const observation=args.capture.observation, c=args.capture.proof.value, seq=a.current.next;
      const event=normalizeActivityEvent({...observation,origin_sequence:seq,event_id:`${args.lineage}.${seq}`});
      return {sequence:seq,status:'never_sent',rawDeadline:c.origin+86400000,origin:c.origin,
        ttlDeadline:event.signal_at_ms+event.ttl_ms,attempts:0,attempt:null,fence:null,digest:hash(encode(event))};
    };
    if(args.attack.startsWith('new_')) {
      const row=newRow();proposal.rows.push(row);proposal.next++;
      cap=args.capture;
      if(args.attack==='new_deadline')row.rawDeadline++;
      if(args.attack==='new_ttl')row.ttlDeadline++;
      if(args.attack==='new_digest')row.digest='b'.repeat(64);
      if(args.attack==='new_sequence')row.sequence++;
      if(args.attack==='new_without_capture')cap=undefined;
    } else if(args.attack==='later_deadline')proposal.rows[0].rawDeadline++;
    else if(args.attack==='later_origin')proposal.rows[0].origin++;
    else if(args.attack==='later_ttl')proposal.rows[0].ttlDeadline++;
    else if(args.attack==='later_digest')proposal.rows[0].digest='b'.repeat(64);
    else if(args.attack==='later_sequence')proposal.rows[0].sequence++;
    else if(args.attack==='later_add_without_capture'){const row=newRow();proposal.rows.push(row);proposal.next++;}
    else if(args.attack==='premature_remove')proposal.rows=[];
    else if(args.attack==='resurrect_resolved'){proposal.rows[0].digest='b'.repeat(64);proposal.rows[0].status='never_sent';}
    else if(args.attack==='resurrect_retired'){const row=newRow();row.sequence=1;proposal.rows.push(row);}
    else throw new Error('unknown_attack');
    return broker.authority.prepare(args.lineage,args.owner,a.current.revision,proposal,cap);
  }
  if (op === 'close') { await broker.close(); core.close(); return { closed:true, live:[...broker.children.values()].filter(r=>!r.dead).length,events:broker.events,sends:sends.length }; }
  throw new Error('invalid_fixture_operation');
}
let serial=Promise.resolve();
process.on('message', (m) => {
  serial=serial.then(async () => {
    try { const result=await dispatch(m.op,m.args??{}); process.send({id:m.id,result}); }
    catch(e) { process.send({id:m.id,error:/^[a-z_0-9]+$/.test(e.message)?e.message:'fixture_rejected'}); }
  });
});
process.on('disconnect',async()=>{ try { await broker?.close(); core?.close(); } finally { process.exit(0); } });
