import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fork, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { randomUUID, createDecipheriv } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { ProtectedStore } from '../store.mjs';

const workspace = fileURLToPath(new URL('../../../',import.meta.url));
const scratchBase = path.join(workspace,'tools','mda2_windows_queue','.scratch');
fs.mkdirSync(scratchBase,{recursive:true});
const scratch = fs.mkdtempSync(path.join(scratchBase,'test-'));
const evidence = [];
class Host {
  constructor() {
    this.pending=new Map();this.id=0;
    this.child=fork(fileURLToPath(new URL('./broker_host.mjs',import.meta.url)),[],{windowsHide:true,stdio:['ignore','ignore','pipe','ipc']});
    this.stderr='';this.child.stderr.on('data',b=>{this.stderr+=b.toString();});
    this.child.on('message',m=>{const p=this.pending.get(m.id);if(!p)return;this.pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(new Error(m.error)):p.resolve(m.result);});
    this.exited=new Promise(resolve=>this.child.once('exit',(code,signal)=>{for(const p of this.pending.values()){clearTimeout(p.timer);p.reject(new Error('host_exited'));}this.pending.clear();resolve({code,signal});}));
  }
  call(op,args={}) {return new Promise((resolve,reject)=>{const id=++this.id;const timer=setTimeout(()=>reject(new Error('host_timeout')),45000);this.pending.set(id,{resolve,reject,timer});this.child.send({id,op,args});});}
  async close() {if(this.child.exitCode!==null||this.child.signalCode!==null)return;const result=await this.call('close');assert.equal(result.live,0);this.child.disconnect();await this.exited;return result;}
}
async function scenario(name,fn,{realClock=false,maintenanceMs=60000}={}) {
  if (process.argv[2] && !name.includes(process.argv[2])) return;
  const host=new Host();
  try {const init=await host.call('init',{realClock,maintenanceMs});const facts=await fn(host);const close=await host.close();const exits=await host.exited;assert.equal(exits.code,0);
    for(const event of close.events.filter(e=>e.type==='clean_close')){assert.equal(event.guardExit.code,0);assert.equal(event.databaseClosed,true);}
    evidence.push({name,passed:true,brokerPid:init.pid,clock:init.clock,hostExit:exits,processEvents:close.events,sends:close.sends,facts:facts??null});process.stdout.write(`PASS ${name}\n`);}
  catch(e){process.stderr.write(`FAIL ${name}: ${e.message}\n${host.stderr}\n`);await host.close().catch(()=>host.child.kill());throw e;}
}
let index=0;
async function fresh(h,limits={}) {const root=path.join(scratch,`queue-${++index}`);const {binding}=await h.call('new',{root});const owner=await h.call('start',{root,binding,fresh:true,limits});return {root,binding,...owner};}
const cmd=(h,q,op,args={})=>h.call('command',{owner:q.owner,op,args});
const capture=(h,q,ttl)=>h.call('capture',{lineage:q.binding.event_id_prefix,ttl});
const enqueue=async(h,q,ttl)=>cmd(h,q,'allocate',await capture(h,q,ttl));
async function reopen(h,q){await h.call('stop',{owner:q.owner}).catch(()=>{});return {...q,...await h.call('start',{root:q.root,binding:q.binding})};}
async function settle(h,q,attempt){const proof=await cmd(h,q,'deliver',{attempt});return cmd(h,q,'settle',{attempt,proof});}
const reject=(promise,code)=>assert.rejects(promise,new RegExp(code));
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function diskState(q){const store=await ProtectedStore.open(q.root,q.binding);try{return store.read().state;}finally{await store.close();}}
async function snapshot(q){return fs.readFileSync(path.join(q.root,'queue','state.sqlite'));}
async function restore(q,bytes){fs.writeFileSync(path.join(q.root,'queue','state.sqlite'),bytes);}
function removeOwnedScratch() {
  const resolved=fs.realpathSync.native(scratch);
  assert.ok(resolved.toLowerCase().startsWith(fs.realpathSync.native(scratchBase).toLowerCase()+path.sep));
  assert.equal(path.dirname(resolved),fs.realpathSync.native(scratchBase));
  fs.rmSync(resolved,{recursive:true,force:true});
}

try {
  await scenario('native_clock_cross_process_replay',async h=>{
    let q=await fresh(h);await enqueue(h,q);const attempt=await cmd(h,q,'begin',{sequence:1});
    const first=await cmd(h,q,'deliver',{attempt});assert.equal(first.value.reply.results[0].status,'accepted');
    const oldPid=q.pid;await h.call('stop',{owner:q.owner,crash:true});
    q=await reopen(h,q);assert.notEqual(q.pid,oldPid);
    const state=await cmd(h,q,'inspect');assert.equal(state.rows[0].status,'attempted_unknown');
    const retry=await cmd(h,q,'begin',{sequence:1});assert.equal(await settle(h,q,retry),'duplicate');
    const final=await cmd(h,q,'inspect');assert.equal(final.rows[0].rawPresent,false);assert.equal(final.next,2);
    assert.equal(final.rows[0].receipt.receipt_id,first.value.reply.results[0].receipt_id);
    assert.equal(final.rows[0].receipt.server_sequence,first.value.reply.results[0].server_sequence);
    const {sends}=await h.call('events');assert.equal(sends.length,2);assert.equal(sends[0].digest,sends[1].digest);
  },{realClock:true});
  for(const point of ['before_reserve','after_reserve','during_sqlite','after_sqlite','after_authority_commit']) {
    await scenario(`allocation_crash_${point}`,async h=>{
      let q=await fresh(h);const cap=await capture(h,q);
      await cmd(h,q,'arm',{point:`allocate:${point}`});await reject(cmd(h,q,'allocate',cap),'queue_process_exited');
      const ev=await h.call('events');assert.equal(ev.events.at(-2).point,`allocate:${point}`);assert.equal(ev.sends.length,0);
      q=await reopen(h,q);const state=await cmd(h,q,'inspect');
      if(point==='before_reserve'){assert.equal(state.next,1);assert.equal(state.rows.length,0);assert.equal(state.frozen,null);await enqueue(h,q);assert.equal((await cmd(h,q,'inspect')).next,2);}
      else if(['after_reserve','during_sqlite'].includes(point)){assert.equal(state.next,2);assert.equal(state.rows.length,0);assert.equal(state.frozen,'authority_reservation_gap');}
      else {assert.equal(state.next,2);assert.equal(state.rows[0].status,'never_sent');assert.equal(await settle(h,q,await cmd(h,q,'begin',{sequence:1})),'accepted');}
    });
  }
  for(const point of ['attempt:after_authority_commit','delivery:after_core','receipt:during_sqlite','receipt:after_sqlite','receipt:after_authority_commit']) {
    await scenario(`delivery_crash_${point.replaceAll(':','_')}`,async h=>{
      let q=await fresh(h);await enqueue(h,q);let attempt;
      if(point.startsWith('attempt')) {await cmd(h,q,'arm',{point});await reject(cmd(h,q,'begin',{sequence:1}),'queue_process_exited');}
      else {
        attempt=await cmd(h,q,'begin',{sequence:1});
        if(point.startsWith('delivery')){await cmd(h,q,'arm',{point});await reject(cmd(h,q,'deliver',{attempt}),'queue_process_exited');}
        else {const proof=await cmd(h,q,'deliver',{attempt});await cmd(h,q,'arm',{point});await reject(cmd(h,q,'settle',{attempt,proof}),'queue_process_exited');}
      }
      q=await reopen(h,q);const state=await cmd(h,q,'inspect');assert.equal(state.next,2);
      if(point==='receipt:during_sqlite'){assert.equal(state.frozen,'authority_reservation_gap');assert.equal(state.rows.length,0);}
      else if(point.startsWith('receipt')){assert.equal(state.rows[0].rawPresent,false);assert.equal(state.rows[0].status,'accepted');await reject(cmd(h,q,'begin',{sequence:1}),'not_sendable');}
      else {assert.equal(state.rows[0].status,'attempted_unknown');const outcome=await settle(h,q,await cmd(h,q,'begin',{sequence:1}));assert.equal(outcome,point.startsWith('attempt')?'accepted':'duplicate');}
    });
  }
  await scenario('freeze_inflight_receipt_and_next_fenced',async h=>{
    let q=await fresh(h);await enqueue(h,q);await enqueue(h,q);const attempt=await cmd(h,q,'begin',{sequence:1});const proof=await cmd(h,q,'deliver',{attempt});
    await cmd(h,q,'freeze');assert.equal(await cmd(h,q,'settle',{attempt,proof}),'accepted');
    await reject(cmd(h,q,'begin',{sequence:2}),'lineage_frozen');q=await reopen(h,q);
    const state=await cmd(h,q,'inspect');assert.equal(state.frozen,'operator_frozen');assert.equal(state.rows[1].attempts,0);assert.equal(state.rows[0].rawPresent,false);
  });
  await scenario('two_process_owner_and_old_callback',async h=>{
    let q=await fresh(h);await enqueue(h,q);const attempt=await cmd(h,q,'begin',{sequence:1});const old=q.owner;
    await reject(h.call('start',{root:q.root,binding:q.binding}),'windows_protection_rejected_owner_lock');
    await h.call('stop',{owner:q.owner,crash:true});q=await reopen(h,q);
    await reject(h.call('staleSend',{lineage:q.binding.event_id_prefix,owner:old,attempt}),'owner_fenced');
    await reject(cmd(h,q,'settle',{attempt,proof:{}}),'attempt_not_pending');assert.equal((await h.call('events')).sends.length,0);
  });
  await scenario('old_snapshot_rejected_without_reset',async h=>{
    let q=await fresh(h);await h.call('stop',{owner:q.owner});const old=await snapshot(q);q=await reopen(h,q);await enqueue(h,q);
    await h.call('stop',{owner:q.owner});await restore(q,old);q=await reopen(h,q);
    const state=await cmd(h,q,'inspect');assert.equal(state.frozen,'snapshot_rollback_or_missing');assert.equal(state.next,2);assert.equal(state.rows.length,0);
    await reject(enqueue(h,q),'lineage_frozen');assert.equal((await h.call('events')).sends.length,0);
  });
  await scenario('late_capture_original_age_and_boundaries',async h=>{
    let q=await fresh(h);const cap=await capture(h,q);await h.call('setTime',{age:105000,wall:1005000});
    const row=await cmd(h,q,'allocate',cap);assert.equal(row.rawDeadline,86500000);q=await reopen(h,q);assert.equal((await cmd(h,q,'inspect')).rows[0].origin,100000);
    assert.equal(await settle(h,q,await cmd(h,q,'begin',{sequence:1})),'accepted');
    for(const excess of [0,1]) {
      const p=await fresh(h);const late=await capture(h,p);const origin=late.proof.value.origin;
      await h.call('setTime',{age:origin+86400000+excess});await reject(cmd(h,p,'allocate',late),'capture_retention_expired');
      const state=await cmd(h,p,'inspect');assert.equal(state.next,1);assert.equal(state.rows.length,0);
    }
  });
  await scenario('ttl_equal_accepts_late_expired_unallocated',async h=>{
    const q=await fresh(h);const cap=await capture(h,q,1000);await h.call('setTime',{age:101000,wall:1001000});
    await cmd(h,q,'allocate',cap);assert.equal(await settle(h,q,await cmd(h,q,'begin',{sequence:1})),'accepted');
    const p=await fresh(h);const late=await capture(h,p,1000);await h.call('setTime',{age:102001,wall:1002001});
    await reject(cmd(h,p,'allocate',late),'capture_ttl_expired');assert.equal((await cmd(h,p,'inspect')).next,1);
  });
  await scenario('ttl_expired_unknown_replays_same_bytes',async h=>{
    const q=await fresh(h);await enqueue(h,q,1000);const attempt=await cmd(h,q,'begin',{sequence:1});await cmd(h,q,'deliver',{attempt});
    await h.call('stop',{owner:q.owner,crash:true});await h.call('setTime',{age:102000,wall:1002000});const resumed=await reopen(h,q);
    assert.equal(await settle(h,resumed,await cmd(h,resumed,'begin',{sequence:1})),'duplicate');const {sends}=await h.call('events');assert.equal(sends[0].digest,sends[1].digest);
  });
  await scenario('never_sent_ttl_freezes_then_horizon_removes_all_detail',async h=>{
    const q=await fresh(h);await enqueue(h,q,1000);await h.call('setTime',{age:101001,wall:1001001});await cmd(h,q,'sweep');
    let s=await cmd(h,q,'inspect');assert.equal(s.rows[0].status,'expired_unsent');assert.equal(s.rows[0].rawPresent,false);assert.equal(s.frozen,'allocated_sequence_gap');
    await h.call('setTime',{age:86500000});await cmd(h,q,'sweep');await h.call('stop',{owner:q.owner});
    const disk=await diskState(q);assert.deepEqual(disk.rows,[]);assert.equal(disk.next,2);
  });
  await scenario('raw_horizon_beats_late_receipt',async h=>{
    const q=await fresh(h);await enqueue(h,q);const attempt=await cmd(h,q,'begin',{sequence:1});const proof=await cmd(h,q,'deliver',{attempt});
    await h.call('setTime',{age:86500000});assert.equal(await cmd(h,q,'settle',{attempt,proof}),'discarded_after_retention');
    const state=await cmd(h,q,'inspect');assert.deepEqual(state.rows,[]);assert.equal(state.frozen,'retention_unresolved');
  });
  await scenario('independent_timer_cleanup_without_enqueue_or_send',async h=>{
    const q=await fresh(h);await enqueue(h,q);await h.call('setTime',{age:86500000});
    let state;for(let n=0;n<30;n++){await pause(100);state=await cmd(h,q,'inspect');if(!state.rows.length)break;}
    assert.deepEqual(state.rows,[]);assert.equal((await h.call('events')).sends.length,0);
  },{maintenanceMs:100});
  await scenario('capacity_limits_do_not_allocate_or_evict',async h=>{
    const q=await fresh(h,{rows:1,pending:1});await enqueue(h,q);await reject(enqueue(h,q),'capacity_reached');assert.equal((await cmd(h,q,'inspect')).next,2);
    const p=await fresh(h,{eventBytes:1});await reject(enqueue(h,p),'capacity_reached');assert.equal((await cmd(h,p,'inspect')).next,1);
    const r=await fresh(h,{bytes:1});await reject(enqueue(h,r),'capacity_reached');assert.equal((await cmd(h,r,'inspect')).next,1);
    const s=await fresh(h,{pending:1});await enqueue(h,s);await cmd(h,s,'begin',{sequence:1});await reject(enqueue(h,s),'capacity_reached');assert.equal((await cmd(h,s,'inspect')).rows[0].status,'attempted_unknown');
    const m=await fresh(h,{metadataBytes:1024});await reject(enqueue(h,m),'metadata_capacity');assert.equal((await cmd(h,m,'inspect')).next,1);
  });
  await scenario('proof_forgery_binding_and_reuse_fail_closed',async h=>{
    const q=await fresh(h);const cap=await capture(h,q);cap.observation.kind='session.locked';await reject(cmd(h,q,'allocate',cap),'acquisition_age_unverified');assert.equal((await cmd(h,q,'inspect')).frozen,'acquisition_age_unverified');
    const p=await fresh(h);await reject(cmd(h,p,'allocate',{observation:(await capture(h,p)).observation,proof:{trusted:true}}),'acquisition_age_unverified');
    const r=await fresh(h);const same=await capture(h,r);await cmd(h,r,'allocate',same);await reject(cmd(h,r,'allocate',same),'acquisition_age_unverified');assert.equal((await cmd(h,r,'inspect')).next,2);
  });
  await scenario('wall_rollback_does_not_extend_raw_age',async h=>{
    const q=await fresh(h);await enqueue(h,q);await h.call('setTime',{wall:900000,age:100100});await cmd(h,q,'sweep');
    assert.equal((await cmd(h,q,'inspect')).clockUncertain,true);await reject(cmd(h,q,'begin',{sequence:1}),'lineage_frozen');
    await h.call('setTime',{age:86500000});await cmd(h,q,'sweep');assert.deepEqual((await cmd(h,q,'inspect')).rows,[]);
  });
  await scenario('age_provider_loss_cleans_and_freezes',async h=>{
    let q=await fresh(h);await enqueue(h,q);await h.call('lostAge');await cmd(h,q,'sweep');q=await reopen(h,q);
    const state=await cmd(h,q,'inspect');assert.equal(state.frozen,'age_authority_lost');assert.deepEqual(state.rows,[]);assert.equal(state.next,2);
  });
  await scenario('wrong_key_tampered_ciphertext_path_and_version_rejected',async h=>{
    let q=await fresh(h);await enqueue(h,q);await h.call('stop',{owner:q.owner});
    const keyfile=path.join(q.root,'keys','queue.dpapi'),key=fs.readFileSync(keyfile);fs.writeFileSync(keyfile,Buffer.alloc(key.length,9));
    await reject(h.call('start',{root:q.root,binding:q.binding}),'windows_protection_rejected_dpapi');fs.writeFileSync(keyfile,key);key.fill(0);
    const dbfile=path.join(q.root,'queue','state.sqlite'), original=fs.readFileSync(dbfile);
    const db=new DatabaseSync(dbfile);db.prepare('UPDATE sealed_state SET envelope=?').run(Buffer.alloc(30,1));db.close();
    await reject(h.call('start',{root:q.root,binding:q.binding}),'queue_integrity_rejected');fs.writeFileSync(dbfile,original);
    const versionDb=new DatabaseSync(dbfile), versionRow=versionDb.prepare('SELECT envelope FROM sealed_state').get();const changed=Buffer.from(versionRow.envelope);changed[0]=2;
    versionDb.prepare('UPDATE sealed_state SET envelope=?').run(changed);versionDb.close();await reject(h.call('start',{root:q.root,binding:q.binding}),'queue_integrity_rejected');fs.writeFileSync(dbfile,original);
    await reject(h.call('start',{root:q.root,binding:{...q.binding,probe_id:'wrong-binding'}}),'windows_protection_rejected_dpapi');
    q=await reopen(h,q);assert.equal((await cmd(h,q,'inspect')).rows[0].rawPresent,true);
  });
  await scenario('acl_reparse_hardlink_rejected_and_ciphertext_at_rest',async h=>{
    let q=await fresh(h);await enqueue(h,q);await h.call('stop',{owner:q.owner});
    const raw=fs.readFileSync(path.join(q.root,'queue','state.sqlite'));assert.equal(raw.includes(Buffer.from('device.activity.v1')),false);assert.equal(raw.includes(Buffer.from(q.binding.event_id_prefix)),false);
    const link=path.join(scratch,'junction-'+randomUUID());fs.symlinkSync(q.root,link,'junction');
    await reject(h.call('start',{root:link,binding:q.binding}),'windows_protection_rejected_request');fs.unlinkSync(link);
    const stray=path.join(q.root,'queue','linked.bin');fs.linkSync(path.join(q.root,'keys','queue.dpapi'),stray);
    await reject(h.call('start',{root:q.root,binding:q.binding}),'hardlink_rejected');fs.unlinkSync(stray);
    const acl=spawnSync('icacls.exe',[q.root,'/grant','*S-1-1-0:(OI)(CI)R'],{windowsHide:true,encoding:'utf8'});assert.equal(acl.status,0);
    await reject(h.call('start',{root:q.root,binding:q.binding}),'windows_protection_rejected_acl');
    assert.equal(spawnSync('icacls.exe',[q.root,'/remove:g','*S-1-1-0'],{windowsHide:true,encoding:'utf8'}).status,0);
    q=await reopen(h,q);assert.equal((await cmd(h,q,'inspect')).next,2);
  });
  await scenario('broker_rejects_forged_new_and_existing_row_projections',async h=>{
    const q=await fresh(h), cap=await capture(h,q), lineage=q.binding.event_id_prefix;
    const before=await h.call('authorityState',{lineage});
    for(const attack of ['new_deadline','new_ttl','new_digest','new_sequence','new_without_capture']) {
      await reject(h.call('forgePrepare',{lineage,owner:q.owner,capture:cap,attack}),'rejected|required');
      assert.deepEqual(await h.call('authorityState',{lineage}),before);
    }
    await cmd(h,q,'allocate',cap);
    for(const attack of ['later_deadline','later_origin','later_ttl','later_digest','later_sequence','later_add_without_capture','premature_remove']) {
      await reject(h.call('forgePrepare',{lineage,owner:q.owner,capture:cap,attack}),'rejected|required|removal');
    }
    assert.equal(await settle(h,q,await cmd(h,q,'begin',{sequence:1})),'accepted');
    await reject(h.call('forgePrepare',{lineage,owner:q.owner,capture:cap,attack:'resurrect_resolved'}),'rejected');
    await h.call('setTime',{age:86500000});await cmd(h,q,'sweep');
    await reject(h.call('forgePrepare',{lineage,owner:q.owner,capture:cap,attack:'resurrect_retired'}),'required|rejected');
    assert.deepEqual((await cmd(h,q,'inspect')).rows,[]);
    return {rejectedBrokerProjections:14};
  });
  await scenario('cleanup_after_queue_process_exit',async h=>{
    const q=await fresh(h);await enqueue(h,q);await h.call('stop',{owner:q.owner,crash:true});
    await h.call('setTime',{age:86500000});await h.call('maintenance');
    const disk=await diskState(q);assert.deepEqual(disk.rows,[]);assert.equal(disk.frozen,'retention_unresolved');assert.equal(disk.next,2);
    const result=await h.call('events');assert.equal(result.sends.length,0);assert.equal(result.live.length,0);
  });
  await scenario('old_authority_death_rejected_and_local_cleanup',async h=>{
    const other=new Host();await other.call('init',{realClock:true});let q;
    try {
      q=await fresh(other);await enqueue(other,q);
      other.child.kill();const dead=await other.exited;assert.equal(dead.signal,'SIGTERM');
      let exited=false;for(let n=0;n<100;n++){try{process.kill(q.pid,0);}catch{exited=true;break;}await pause(50);}assert.equal(exited,true);
      const before=await diskState(q);const rawRowsBeforeReopen=before.rows.filter(r=>r.bytes).length;
      await reject(h.call('start',{root:q.root,binding:q.binding}),'lineage_authority_lost');
      const disk=await diskState(q);assert.deepEqual(disk.rows,[]);assert.equal(disk.frozen,'lineage_authority_lost');assert.equal(disk.next,2);
      return {terminatedBrokerPid:other.child.pid,queuePid:q.pid,queueExitedAfterBrokerDeath:exited,rawRowsBeforeReopen,
        clearedOnRefusedReopen:true,authorityEpochRestored:false,oldLineageExport:false,instantCleanupOnBrokerTerminationGuaranteed:false};
    } finally {await other.close().catch(()=>other.child.kill());}
  });
  await scenario('native_age_helper_death_cleans_and_freezes',async h=>{
    const q=await fresh(h);await enqueue(h,q);const attempt=await cmd(h,q,'begin',{sequence:1});await cmd(h,q,'deliver',{attempt});
    await h.call('lostAge');await cmd(h,q,'sweep');
    const state=await cmd(h,q,'inspect');assert.deepEqual(state.rows,[]);assert.equal(state.frozen,'age_authority_lost');assert.equal(state.next,2);
    const authority=await h.call('authorityState',{lineage:q.binding.event_id_prefix});assert.equal(authority.retainedProofs,0);assert.equal(authority.retainedDispatches,0);assert.equal(authority.retainedRows,0);
  },{realClock:true});
  await scenario('unknown_and_malformed_receipts_never_accept',async h=>{
    const q=await fresh(h);await enqueue(h,q);await h.call('mode',{value:'offline'});
    assert.equal(await settle(h,q,await cmd(h,q,'begin',{sequence:1})),'attempted_unknown');
    let state=await cmd(h,q,'inspect');assert.equal(state.frozen,null);assert.equal(state.rows[0].rawPresent,true);
    await h.call('mode',{value:'malformed'});const attempt=await cmd(h,q,'begin',{sequence:1});const proof=await cmd(h,q,'deliver',{attempt});
    await reject(cmd(h,q,'settle',{attempt,proof}),'invalid_receipt');state=await cmd(h,q,'inspect');
    assert.equal(state.rows[0].status,'attempted_unknown');assert.equal(state.rows[0].receiptPresent,false);assert.equal(state.rows[0].rawPresent,true);
  });
  await scenario('authoritative_terminal_receipt_freezes_lineage',async h=>{
    const q=await fresh(h);await enqueue(h,q,1000);const attempt=await cmd(h,q,'begin',{sequence:1});
    await h.call('setTime',{wall:1001001,age:101001});assert.equal(await settle(h,q,attempt),'terminal');
    const state=await cmd(h,q,'inspect');assert.equal(state.frozen,'transport_terminal');assert.equal(state.rows[0].rawPresent,false);assert.equal(state.next,2);
    await reject(enqueue(h,q),'lineage_frozen');
  });
  await scenario('same_attempt_cannot_dispatch_twice',async h=>{
    const q=await fresh(h);await enqueue(h,q);const attempt=await cmd(h,q,'begin',{sequence:1});const proof=await cmd(h,q,'deliver',{attempt});
    await reject(cmd(h,q,'deliver',{attempt}),'attempt_already_dispatched');assert.equal((await h.call('events')).sends.length,1);
    assert.equal(await cmd(h,q,'settle',{attempt,proof}),'accepted');
  });
  await scenario('lost_protection_owner_blocks_transport',async h=>{
    const q=await fresh(h);await enqueue(h,q);const attempt=await cmd(h,q,'begin',{sequence:1});await h.call('lostGuard',{owner:q.owner});await pause(100);
    await reject(cmd(h,q,'deliver',{attempt}),'protection_owner_lost');assert.equal((await h.call('events')).sends.length,0);
    await h.call('stop',{owner:q.owner,crash:true});
  });
  await scenario('logical_deletion_does_not_destroy_archived_ciphertext',async h=>{
    let q=await fresh(h);await enqueue(h,q);await h.call('stop',{owner:q.owner});
    const archiveDb=new DatabaseSync(path.join(q.root,'queue','state.sqlite'));const envelope=Buffer.from(archiveDb.prepare('SELECT envelope FROM sealed_state').get().envelope);archiveDb.close();
    q=await reopen(h,q);await h.call('setTime',{age:86500000});await cmd(h,q,'sweep');await h.call('stop',{owner:q.owner});
    const current=await ProtectedStore.open(q.root,q.binding);
    try {
      assert.deepEqual(current.read().state.rows,[]);
      const decipher=createDecipheriv('aes-256-gcm',current.key,envelope.subarray(1,13));decipher.setAAD(current.aad);decipher.setAuthTag(envelope.subarray(-16));
      const oldPlain=Buffer.concat([decipher.update(envelope.subarray(13,-16)),decipher.final()]);
      assert.ok(JSON.parse(oldPlain.toString()).rows[0].bytes);oldPlain.fill(0);
      return {logicalRowsAfterHorizon:0,archivedCiphertextStillDecryptable:true,physicalHardDeleteSupported:false};
    }finally{await current.close();envelope.fill(0);}
  });
  const output=path.join(workspace,'docs','development','activity','mda2','windows','w2','RESULT.json');fs.mkdirSync(path.dirname(output),{recursive:true});
  removeOwnedScratch();
  fs.writeFileSync(output,JSON.stringify({suite:'w2-protected-disk-v1',filter:process.argv[2]??null,passed:evidence.length,scratchRemoved:true,evidence},null,2)+'\n');
  process.stdout.write(`RESULT ${output}\n`);
} catch {process.exitCode=1;}
