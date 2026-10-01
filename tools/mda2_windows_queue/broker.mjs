import path from 'node:path';
import { fork } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { SurvivingBrokerAuthority, WindowsAgeClock } from './authority.mjs';
import { fail } from './store.mjs';

export const BOUNDED_ASYNC_TRANSPORT_V1 = 'mda2_bounded_async_transport_v1';

function promiseLike(value) { return !!value && typeof value.then === 'function'; }
function exactObject(value, keys) {
  return !!value && Object.getPrototypeOf(value) === Object.prototype
    && Reflect.ownKeys(value).length === keys.length && keys.every((key) => Object.hasOwn(value,key));
}
function validExitReceipt(value) { return exactObject(value,['closed']) && value.closed === true; }

export class WindowsQueueBroker {
  constructor({ clock = null, transport = null, allowSynchronousFixtureTransport = false, maintenanceMs = 1000,
    maxConcurrentTransports = 2, sendTimeoutMs = 15000, retryBaseMs = 250, retryMaxMs = 30000,
    transportExitTimeoutMs = 5000, retryNow = () => Date.now() } = {}) {
    for (const value of [maxConcurrentTransports,sendTimeoutMs,retryBaseMs,retryMaxMs,transportExitTimeoutMs]) {
      if (!Number.isSafeInteger(value) || value < 1) fail('invalid_transport_limits');
    }
    if (transport === null) { this.transport=null; this.transportMode='none'; }
    else if (typeof transport === 'function' && allowSynchronousFixtureTransport === true) {
      this.transport=transport;this.transportMode='sync_fixture';
    } else if (exactObject(transport,['kind','prepare']) && transport.kind === BOUNDED_ASYNC_TRANSPORT_V1
      && typeof transport.prepare === 'function') { this.transport=transport; this.transportMode='bounded_async'; }
    else fail('transport_contract_rejected');
    clock??=new WindowsAgeClock();this.authority = new SurvivingBrokerAuthority({ clock }); this.clock = clock;
    this.children = new Map(); this.registrations = new Map(); this.closed = false; this.serial = Promise.resolve(); this.events = [];
    this.dispatches = new Map(); this.maxConcurrentTransports = maxConcurrentTransports;
    this.sendTimeoutMs = sendTimeoutMs; this.retryBaseMs = retryBaseMs; this.retryMaxMs = retryMaxMs;
    this.transportExitTimeoutMs=transportExitTimeoutMs;this.retryNow = retryNow;
    this.timer = setInterval(() => this.maintenance().catch(() => {}), maintenanceMs);
  }
  async registerFresh(binding, root) {
    await this.authority.sample(); this.authority.registerFresh(binding, path.resolve(root));
    this.registrations.set(binding.event_id_prefix,{binding:structuredClone(binding),root:path.resolve(root)});
  }
  record(event) { this.events.push(event); if(this.events.length>128)this.events.shift(); }
  async capture(lineage, observation) { await this.authority.sample(); return this.authority.capture(lineage, observation); }
  async openNativeChannel(bindings, options) {
    if (this.closed) fail('broker_closed');
    await this.authority.sample();
    return this.authority.openNativeChannel(bindings,options);
  }
  captureNativePacket(token, packet, observation = null) {
    const operation=this.serial.then(async()=>{
      await this.authority.sample();
      return this.authority.captureNative(token,packet,observation);
    });
    this.serial=operation.catch(()=>{});
    return operation;
  }
  closeNativeChannel(token) { this.authority.closeNativeChannel(token); }
  async start({ binding, root, fresh = false, limits = {} }) {
    if (this.closed) fail('broker_closed');
    const owner = randomUUID(), lineage = binding.event_id_prefix;
    const child = fork(fileURLToPath(new URL('./worker.mjs', import.meta.url)), [], {
      windowsHide: true, env: { SystemRoot: process.env.SystemRoot, PATH: process.env.PATH, TEMP: process.env.TEMP, TMP: process.env.TMP },
      stdio: ['ignore','ignore','ignore','ipc'], serialization: 'json' });
    const record = { child, owner, lineage, binding, root, pending: new Map(), sequence: 0, dead: false,
      stopping: false, retryFailures: 0, retryAfter: 0 };
    this.children.set(owner, record);
    this.record({type:'start',owner,pid:child.pid});
    record.exited = new Promise((resolve) => child.once('exit', (code, signal) => {
      record.dead = true; this.authority.childExited(lineage, owner);
      const result = { owner, pid: child.pid, code, signal, guardPid: record.guardPid ?? null };
      this.record({ type: 'exit', ...result });
      for (const p of record.pending.values()) { clearTimeout(p.timer); p.reject(new Error('queue_process_exited')); }
      record.pending.clear(); resolve(result);
      this.children.delete(owner); // retired owners cannot grow an unbounded registry
    }));
    child.on('message', (m) => {
      if (m.type === 'guard') record.guardPid = m.pid;
      if (m.type === 'barrier') { this.record({ type: 'barrier', owner, pid: child.pid, point: m.point }); child.kill(); }
      if (m.type === 'result') {
        const p = record.pending.get(m.id); if (!p) return;
        record.pending.delete(m.id); clearTimeout(p.timer);
        m.error ? p.reject(new Error(m.error)) : p.resolve(m.result);
      }
      if (m.type === 'authority') {
        this.serial = this.serial.then(async () => {
          try {
            await this.authority.sample();
            const result = await this.authorityCall(record, m.op, m.args);
            if (child.connected) child.send({ type: 'authority_reply', id: m.id, result });
          } catch (e) { if (child.connected) child.send({ type: 'authority_reply', id: m.id, error: /^[a-z_]+$/.test(e.message) ? e.message : 'authority_rejected' }); }
        });
      }
    });
    try {
      const state = await this.command(owner, 'open', { root, binding, fresh, limits });
      return { owner, pid: child.pid, state };
    } catch (e) { if (!record.dead) child.kill(); await record.exited; throw e; }
  }
  authorityCall(r, op, args) {
    const a = this.authority, l = r.lineage, o = r.owner;
    if (op === 'context') { a.owned(l,o); return a.context(); }
    if (op === 'claim') return a.claim(l,o,args.root,args.binding,args.disk);
    if (op === 'prepare') return a.prepare(l,o,args.oldRevision,args.proposal,args.capture,args.receipt);
    if (op === 'committed') return a.committed(l,o,args.digest);
    if (op === 'verifyCapture') return a.verifyCapture(l,o,args.proof,args.observation);
    if (op === 'verifyReceipt') return a.verifyReceipt(l,o,args.attempt,args.proof);
    if (op === 'deliver') {
      if (r.stopping || this.closed) fail('send_frozen');
      if (!this.transport) fail('transport_not_configured');
      if ([...this.dispatches.values()].filter((value) => value.status !== 'complete').length >= this.maxConcurrentTransports) {
        fail('transport_concurrency_reached');
      }
      const bytes = Buffer.from(args.bytes,'base64');
      try {
        if(this.transportMode==='bounded_async'){
          // prepare() is the trusted adapter's side-effect-free phase. The
          // complete handle is validated before raw bytes are authorized or start() runs.
          const handle=this.transport.prepare(r.binding,{owner:o,attempt:structuredClone(args.attempt)});
          if(!exactObject(handle,['start','cancel','completion','exited'])||typeof handle.start!=='function'
            ||typeof handle.cancel!=='function'||!promiseLike(handle.completion)||!promiseLike(handle.exited)){
            fail('transport_exit_handle_required');
          }
          const authorized=a.authorizeSend(l,o,args.attempt,bytes);
          return this.trackAsyncDispatch(r,args.attempt,bytes,handle,authorized.rawDeadline);
        }
        const authorized=a.authorizeSend(l,o,args.attempt,bytes);
        // Legacy synchronous fixture transports stay compatible, but they may
        // not smuggle an asynchronous outlet behind a Promise or handle.
        const reply = this.transport(bytes, r.binding, { owner:o, attempt:structuredClone(args.attempt) });
        if(promiseLike(reply)||promiseLike(reply?.completion))fail('sync_transport_async_result_rejected');
        return a.receipt(l,o,args.attempt,reply);
      } finally {
        if (![...this.dispatches.values()].some((value) => value.bytes === bytes)) bytes.fill(0);
      }
    }
    fail('invalid_authority_operation');
  }
  trackAsyncDispatch(r, attempt, bytes, handle, rawDeadline) {
    const id = randomUUID();
    let resolveSettlement;
    const settlement = new Promise((resolve) => { resolveSettlement = resolve; });
    const record = { id, owner:r.owner, lineage:r.lineage, attempt:structuredClone(attempt), bytes,
      cancel:()=>handle.cancel(), status:'pending', settlement, resolveSettlement,rawDeadline,
      cancelRequested:false, transportExited:false, exitState:'pending', finishing:false, startedAt:this.retryNow() };
    this.dispatches.set(id,record); this.record({type:'transport_dispatch',owner:r.owner,id});
    record.actualExit=Promise.resolve(handle.exited).then((receipt)=>{
      if(!validExitReceipt(receipt))fail('transport_exit_unconfirmed');
      record.transportExited=true;record.exitState='verified';
      this.record({type:'transport_actual_exit',owner:r.owner,id});return receipt;
    },(error)=>{
      record.exitCause=/^[a-z_0-9]+$/.test(error?.message??'')?error.message:'transport_exit_rejected';
      fail('transport_exit_unconfirmed');
    });
    record.actualExit.catch((error)=>{
      record.exitState='unconfirmed';record.exitError=/^[a-z_0-9]+$/.test(error?.message??'')?error.message:'transport_exit_unconfirmed';
      this.record({type:'transport_exit_unconfirmed',owner:r.owner,id,code:record.exitError});
      this.finishAsyncDispatch(record,{error:new Error('transport_exit_unconfirmed'),exitFailed:true}).catch(()=>{});
    });
    Promise.resolve(handle.completion).then(
      (reply) => this.finishAsyncDispatch(record,{reply}),
      (error) => this.finishAsyncDispatch(record,{error}),
    ).catch(() => {});
    try{
      if(handle.start(bytes)!==true){
        record.cancelRequested=true;try{record.cancel();}catch{}
        this.finishAsyncDispatch(record,{error:new Error('transport_start_unconfirmed')}).catch(()=>{});
      }
    }catch(error){
      record.cancelRequested=true;try{record.cancel();}catch{}
      this.finishAsyncDispatch(record,{error}).catch(()=>{});
    }
    return { pending:true, dispatchId:id };
  }
  finishAsyncDispatch(record, result) {
    if(record.status!=='pending')return Promise.resolve(record.outcome);
    if(record.finishing)return record.finishPromise;
    record.finishing=true;record.finishPromise=this.finalizeAsyncDispatch(record,result);return record.finishPromise;
  }
  async finalizeAsyncDispatch(record, { reply, error, exitFailed=false }) {
    if(record.bytes){record.bytes.fill(0);record.bytes=null;}
    if(!exitFailed){
      try{await record.actualExit;}catch{error=new Error('transport_exit_unconfirmed');exitFailed=true;}
    }
    let outcome;
    if (error || exitFailed) {
      const code=exitFailed?'transport_exit_unconfirmed':(/^[a-z_0-9]+$/.test(error.message)?error.message:'transport_failed');
      outcome = { status:'attempted_unknown', transport:exitFailed?'unconfirmed_exit':'failed', code };
      await this.command(record.owner,'release',{attempt:record.attempt}).catch(()=>{});
    } else {
      const verify = this.serial.then(async () => {
        await this.authority.sample();
        return this.authority.completeSend(record.lineage,record.owner,record.attempt,reply);
      });
      this.serial = verify.catch(()=>{});
      try {
        const proof = await verify;
        const status = await this.command(record.owner,'settle',{attempt:record.attempt,proof});
        outcome = { status, transport:'completed' };
      } catch (settleError) {
        await this.command(record.owner,'release',{attempt:record.attempt}).catch(()=>{});
        outcome = { status:'attempted_unknown', transport:'discarded',
          code:/^[a-z_0-9]+$/.test(settleError.message) ? settleError.message : 'receipt_rejected' };
      }
    }
    const owner = this.children.get(record.owner);
    if (owner) {
      if (['accepted','duplicate'].includes(outcome.status)) { owner.retryFailures=0; owner.retryAfter=0; }
      else {
        owner.retryFailures++;
        owner.retryAfter=this.retryNow()+Math.min(this.retryMaxMs,this.retryBaseMs*(2**Math.min(owner.retryFailures-1,10)));
      }
    }
    record.status=exitFailed?'exit_unconfirmed':'complete'; record.outcome=outcome;record.finishing=false;
    this.record({type:'transport_exit',owner:record.owner,id:record.id,outcome:outcome.transport,status:outcome.status});
    record.resolveSettlement(structuredClone(outcome));
    const completed=[...this.dispatches.values()].filter((value)=>value.status==='complete');
    while(completed.length>128){const old=completed.shift();this.dispatches.delete(old.id);}
  }
  command(owner, op, args = {}) {
    const r = this.children.get(owner); if (!r || r.dead) return Promise.reject(new Error('owner_fenced'));
    const id = ++r.sequence;
    return new Promise((resolve,reject) => {
      const timer = setTimeout(() => { r.pending.delete(id); reject(new Error('worker_timeout')); }, 25000);
      r.pending.set(id,{resolve,reject,timer}); r.child.send({ type: 'command', id, op, args });
    });
  }
  async stop(owner, crash = false) {
    const r = this.children.get(owner); if (!r) fail('unknown_owner');
    r.stopping = true;
    const ownedDispatches=[...this.dispatches.values()].filter((dispatch)=>dispatch.owner===owner&&dispatch.status!=='complete');
    for (const dispatch of ownedDispatches) if (!dispatch.cancelRequested) {
      dispatch.cancelRequested=true; this.record({type:'transport_cancel_requested',owner,id:dispatch.id});
      if(dispatch.bytes){dispatch.bytes.fill(0);dispatch.bytes=null;}
      try { dispatch.cancel?.(); } catch { /* actual completion remains authoritative */ }
    }
    if (!r.dead) {
      if (crash) r.child.kill();
      else { const result=await this.command(owner,'close'); this.record({type:'clean_close',owner,...result.cleanup}); }
    }
    const exit=await r.exited;
    if(ownedDispatches.length){
      await Promise.race([Promise.all(ownedDispatches.map((dispatch)=>dispatch.actualExit)),
        new Promise((_,reject)=>setTimeout(()=>reject(new Error('transport_exit_unconfirmed')),this.transportExitTimeoutMs))]).catch(()=>{});
      if(ownedDispatches.some((dispatch)=>!dispatch.transportExited))fail('transport_exit_unconfirmed');
      await Promise.all(ownedDispatches.map((dispatch)=>this.finishAsyncDispatch(dispatch,{error:new Error('transport_cancelled')})));
    }
    return exit;
  }
  async send(owner, sequence, { timeoutMs = this.sendTimeoutMs } = {}) {
    const r=this.children.get(owner);
    if (!r || r.dead || r.stopping || this.closed) fail('owner_fenced');
    if (!Number.isSafeInteger(timeoutMs) || timeoutMs<1) fail('invalid_transport_limits');
    if (this.retryNow()<r.retryAfter) fail('transport_backoff');
    const attempt=await this.command(owner,'begin',{sequence});
    let dispatched;
    try { dispatched=await this.command(owner,'deliver',{attempt}); }
    catch(e) { await this.command(owner,'release',{attempt}).catch(()=>{}); throw e; }
    if (!dispatched?.pending) {
      const status=await this.command(owner,'settle',{attempt,proof:dispatched});
      return { status,transport:'completed' };
    }
    const record=this.dispatches.get(dispatched.dispatchId);
    if (!record) fail('transport_record_lost');
    return Promise.race([record.settlement,new Promise((_,reject)=>setTimeout(()=>reject(new Error('transport_wait_timeout')),timeoutMs))]);
  }
  async maintenance() {
    if (this.closed || this.maintaining) return;
    this.maintaining = true;
    try {
      const time=await this.authority.sample();
      for(const dispatch of this.dispatches.values())if(dispatch.status==='pending'&&time.age>=dispatch.rawDeadline&&!dispatch.cancelRequested){
        dispatch.cancelRequested=true;if(dispatch.bytes){dispatch.bytes.fill(0);dispatch.bytes=null;}
        this.record({type:'transport_retention_cancel_requested',owner:dispatch.owner,id:dispatch.id});
        try{dispatch.cancel?.();}catch{/* actual exit remains separately observed */}
      }
      for (const [lineage,a] of this.authority.lineages) {
        const active = [...this.children.values()].find((r) => r.lineage === lineage && !r.dead && a.owner === r.owner);
        // Cleanup while active is independent of enqueue and transport.
        if (active && active.pending.size === 0 && !active.maintenanceDisabled) {
          await this.command(active.owner,'sweep').catch(() => {});
        } else if (!active && !a.owner && a.needsSweep && a.current) {
          // Dedicated cleanup owner: no capture, no transport, no user action.
          const config=this.registrations.get(lineage);
          const cleaner=await this.start(config).catch(()=>null);
          if(cleaner) await this.stop(cleaner.owner);
        }
      }
    } finally { this.maintaining = false; }
  }
  async close() {
    this.closed = true; clearInterval(this.timer);
    while(this.maintaining) await new Promise(resolve=>setTimeout(resolve,10));
    for (const r of [...this.children.values()]) if (!r.dead) await this.stop(r.owner).catch(async () => { r.child.kill(); await r.exited; });
    const pending=[...this.dispatches.values()].filter((value)=>value.status!=='complete');
    for(const dispatch of pending) if(!dispatch.cancelRequested){dispatch.cancelRequested=true;if(dispatch.bytes){dispatch.bytes.fill(0);dispatch.bytes=null;}try{dispatch.cancel?.();}catch{}}
    if(pending.length) await Promise.race([
      Promise.all(pending.map((value)=>value.actualExit)),
      new Promise((resolve)=>setTimeout(resolve,this.transportExitTimeoutMs)),
    ]).catch(()=>{});
    const unconfirmed=pending.some((value)=>!value.transportExited);
    if(!unconfirmed)await Promise.all(pending.map((dispatch)=>this.finishAsyncDispatch(dispatch,{error:new Error('transport_cancelled')})));
    await this.clock.close?.(); this.authority.dispose();
    if(unconfirmed)fail('transport_exit_unconfirmed');
  }
}
