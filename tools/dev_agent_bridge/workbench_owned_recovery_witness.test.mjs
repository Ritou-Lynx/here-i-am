import assert from 'node:assert/strict';
import test from 'node:test';
import { createOwnedRecoveryWitness, ownerManifestSha256, witnessFailureClassification } from './workbench_owned_recovery_witness.mjs';
const H='a'.repeat(64), id='11111111-1111-4111-8111-111111111111';
const native={pid:10,creation:'123',imagePath:'D:\\n.exe',imageSha256:H}; const child={pid:11,creation:'124'};
function fake() { let seq=0; const seen=[]; return { seen, authenticated:true, async exchange(raw) { const c=JSON.parse(raw); seen.push(c); return JSON.stringify({schema:'p6_r7_owned_recovery_reply_v1',epoch:H,type:({preflight_barrier:'preflight_permitted',owner_requested:'owner_registered',owner_bound:'owner_binding_recorded',owner_closed:'owner_close_recorded',admission_ready:'admission_recorded',host_closed:'host_close_recorded'})[c.type],state:c.type==='host_closed'?'awaiting_app_close':'live',sequence:++seq}); } }; }
const proof={owner_index:0,attempt_id:id,broker_port:1025,native_pid:10,native_creation:'123',child_pid:11,child_creation:'124',native_exit_code:0,process_close_observed:true,job_empty_verified:true,stdio_eof_verified:true,rules_absent_verified:true,handles_closed_verified:true,helper_exits_verified:true,cleanup_pending:false,broker_drained:true,native_postpin_verified:true,preflight_upstream_attempts:0,preflight_arm_attempts:0};
test('strict witness lifecycle is ordered and compact manifest is stable', async()=>{const a=fake(),w=createOwnedRecoveryWitness({adapter:{authenticated:true,exchange:a.exchange.bind(a)},epoch:H,sourceClosureSha256:H,nativeSha256:H});await w.preflightBarrier();await w.ownerRequested({attempt_id:id,broker_port:1025,preflight:true});await w.ownerBound({owner_index:0,attempt_id:id,native,child});await w.ownerClosed(proof);await w.admissionReady({launch_id:id,admission_sha256:H});const m=await w.hostClosed({host_closed_sha256:H});assert.equal(m,ownerManifestSha256([proof]));assert.deepEqual(a.seen.map(x=>x.type),['preflight_barrier','owner_requested','owner_bound','owner_closed','admission_ready','host_closed']);});
test('bad ack is sticky and cannot enable a later owner',async()=>{const a=fake();a.exchange=async()=>'{"schema":"bad"}';const w=createOwnedRecoveryWitness({adapter:{authenticated:true,exchange:a.exchange.bind(a)},epoch:H,sourceClosureSha256:H,nativeSha256:H});await assert.rejects(w.preflightBarrier());assert.equal(w.failed,true);await assert.rejects(w.ownerRequested({attempt_id:id,broker_port:1025,preflight:true}));});
test('deadline classification survives protocol redaction and a late ACK cannot revive the failed barrier', async()=>{
  let resolveLate, rejectFirst, writes = 0;
  const wire = new Promise((resolve, reject) => { resolveLate = resolve; rejectFirst = reject; });
  const w = createOwnedRecoveryWitness({adapter:{authenticated:true,exchange:() => { writes++; return wire; }},
    epoch:H,sourceClosureSha256:H,nativeSha256:H});
  const first = w.preflightBarrier(); await new Promise(r => setImmediate(r));
  rejectFirst(new Error('deadline_exceeded'));
  await assert.rejects(first, error => { assert.equal(witnessFailureClassification(error), 'timeout');
    assert.equal(error.message, 'owned_recovery_witness_rejected'); return true; });
  resolveLate(JSON.stringify({schema:'p6_r7_owned_recovery_reply_v1',epoch:H,type:'preflight_permitted',state:'live',sequence:1}));
  await new Promise(r => setImmediate(r));
  assert.equal(w.failed, true); await assert.rejects(w.preflightBarrier());
  await assert.rejects(w.ownerRequested({attempt_id:id,broker_port:1025,preflight:true})); assert.equal(writes, 1);
});

test('decoded duplicate ACK keys, wrong sequence and oversized replies reject sticky', async()=>{
  for (const mutate of [
    raw => raw.replace('"type":', '"type":"rejected","ty\\u0070e":'),
    raw => raw.replace('"sequence":1', '"sequence":2'),
    raw => raw + ' '.repeat(16384),
    raw => raw + '{}',
  ]) {
    const a=fake();
    const w=createOwnedRecoveryWitness({adapter:{authenticated:true,exchange:async raw=>mutate(await a.exchange(raw))},epoch:H,sourceClosureSha256:H,nativeSha256:H});
    await assert.rejects(w.preflightBarrier()); assert.equal(w.failed,true);
    await assert.rejects(w.ownerRequested({attempt_id:id,broker_port:1025,preflight:true}));
    assert.equal(a.seen.length,1);
  }
});
test('ping frames serialize; final request uses explicit terminal channel operation only',async()=>{
  let sequence=0,busy=false,finals=0; const commands=[];
  const exchange=async raw=>{assert.equal(busy,false);busy=true;await new Promise(r=>setImmediate(r));
    const c=JSON.parse(raw);commands.push(c);assert.equal(c.sequence,++sequence);busy=false;
    return JSON.stringify({schema:'p6_r7_owned_recovery_reply_v1',epoch:H,
      type:({ping:'alive',preflight_barrier:'preflight_permitted',owner_requested:'owner_registered',owner_bound:'owner_binding_recorded',owner_closed:'owner_close_recorded',admission_ready:'admission_recorded',host_closed:'host_close_recorded'})[c.type],state:c.type==='host_closed'?'awaiting_app_close':'live',sequence});};
  const w=createOwnedRecoveryWitness({adapter:{authenticated:true,exchange,exchangeFinal:async raw=>{assert.equal(JSON.parse(raw).type,'host_closed');finals++;return exchange(raw);}},epoch:H,sourceClosureSha256:H,nativeSha256:H});
  await w.preflightBarrier(); await Promise.all([w.ping(),w.ping(),w.ping()]);
  await w.ownerRequested({attempt_id:id,broker_port:1025,preflight:true});await w.ownerBound({owner_index:0,attempt_id:id,native,child});await w.ownerClosed(proof);await w.admissionReady({launch_id:id,admission_sha256:H});await w.hostClosed({host_closed_sha256:H});
  assert.equal(finals,1);await assert.rejects(w.ping());assert.equal(commands.length,9);
});

const nextId = '22222222-2222-4222-8222-222222222222';
function independentlyQuarantiningServer() {
  const seen = []; let state = 'live', blockType = null, block = null, entered;
  let notifyEntered; const waiting = () => new Promise(resolve => { notifyEntered = resolve; });
  let nextState = null;
  const exchange = async raw => {
    const c = JSON.parse(raw); seen.push(c);
    if (c.type === blockType && block) { notifyEntered?.(); await block; block = null; blockType = null; }
    if (nextState) { state = nextState; nextState = null; }
    if (c.type === 'app_stdin_eof') state = 'app_quarantined';
    const replyState = c.type === 'host_closed' && state === 'live' ? 'awaiting_app_close' : state;
    return JSON.stringify({ schema:'p6_r7_owned_recovery_reply_v1',epoch:H,sequence:c.sequence,
      type:({ping:'alive',preflight_barrier:'preflight_permitted',owner_requested:'owner_registered',
        owner_bound:'owner_binding_recorded',owner_closed:'owner_close_recorded',admission_ready:'admission_recorded',
        app_stdin_eof:'app_eof_recorded',host_closed:'host_close_recorded'})[c.type],state:replyState });
  };
  const witness = createOwnedRecoveryWitness({ adapter:{authenticated:true,exchange,exchangeFinal:exchange},
    epoch:H,sourceClosureSha256:H,nativeSha256:H });
  return { witness, seen, setState(value) { state = value; },
    hold(type, stateOnReply = null) {
      blockType = type; entered = waiting(); let release;
      block = new Promise(resolve => { release = resolve; });
      return { entered, release() { nextState = stateOnReply; release(); } };
    } };
}
async function preparedWitness(server) {
  const w = server.witness;
  await w.preflightBarrier(); await w.ownerRequested({attempt_id:id,broker_port:1025,preflight:true});
  await w.ownerBound({owner_index:0,attempt_id:id,native,child}); await w.ownerClosed(proof);
  await w.admissionReady({launch_id:id,admission_sha256:H}); return w;
}
async function requestExistingSecondOwner(w) {
  await w.ownerRequested({attempt_id:nextId,broker_port:1026,preflight:false});
}
const nextBound = {owner_index:1,attempt_id:nextId,native,child};
const nextProof = {...proof,owner_index:1,attempt_id:nextId,broker_port:1026};

test('server App-death quarantine permits existing bound/closed but never substitutes for the real EOF report', async()=>{
  const s=independentlyQuarantiningServer(),w=await preparedWitness(s); await requestExistingSecondOwner(w);
  s.setState('app_quarantined'); await w.ownerBound(nextBound); await w.ownerClosed(nextProof);
  assert.equal(w.serverQuarantined,true); assert.equal(w.eofReported,false); assert.equal(w.failed,false);
  await assert.rejects(w.hostClosed({host_closed_sha256:H}));
  assert.equal(s.seen.filter(c=>c.type==='host_closed').length,0);
  await w.appStdinEof(); assert.equal(w.eofReported,true);
  await assert.rejects(w.appStdinEof()); assert.equal(s.seen.filter(c=>c.type==='app_stdin_eof').length,1);
  await w.hostClosed({host_closed_sha256:H}); assert.equal(w.failed,false);
});

test('queued pings may observe quarantine before EOF is sent, or remain live until the queued real EOF frame',async()=>{
  for (const state of ['live','app_quarantined']) {
    const s=independentlyQuarantiningServer(),w=await preparedWitness(s);
    const gate=s.hold('ping',state),first=w.ping(); await gate.entered;
    const second=w.ping(),eof=w.appStdinEof(); gate.release();
    await Promise.all([first,second,eof]);
    assert.deepEqual(s.seen.slice(-3).map(c=>c.type),['ping','ping','app_stdin_eof']);
    assert.equal(w.serverQuarantined,true); assert.equal(w.eofReported,true); assert.equal(w.failed,false);
  }
});

test('real EOF queued behind an existing owner-bound still emits exactly once after an automatic quarantine ACK',async()=>{
  const s=independentlyQuarantiningServer(),w=await preparedWitness(s); await requestExistingSecondOwner(w);
  const gate=s.hold('owner_bound','app_quarantined'),binding=w.ownerBound(nextBound); await gate.entered;
  const eof=w.appStdinEof(); gate.release(); await Promise.all([binding,eof]);
  await w.ownerClosed(nextProof); await w.hostClosed({host_closed_sha256:H});
  assert.deepEqual(s.seen.slice(-4).map(c=>c.type),['owner_bound','app_stdin_eof','owner_closed','host_closed']);
  assert.equal(w.failed,false);
});

test('quarantine cannot regress to live even on an otherwise valid ping ACK',async()=>{
  const s=independentlyQuarantiningServer(),w=await preparedWitness(s);
  s.setState('app_quarantined'); await w.ping(); s.setState('live');
  await assert.rejects(w.ping()); assert.equal(w.failed,true); assert.equal(w.eofReported,false);
});

test('an owner intent already queued behind a ping is rejected before write if that ping observes quarantine',async()=>{
  const s=independentlyQuarantiningServer(),w=await preparedWitness(s);
  const gate=s.hold('ping','app_quarantined'),ping=w.ping(); await gate.entered;
  const rejected=assert.rejects(w.ownerRequested({attempt_id:nextId,broker_port:1026,preflight:false}));
  gate.release(); await ping; await rejected;
  assert.equal(s.seen.filter(c=>c.type==='owner_requested').length,1); assert.equal(w.ownerCount,1);
  await w.appStdinEof(); await w.hostClosed({host_closed_sha256:H});
});

test('new-work ACKs cannot use automatic quarantine as permission to cross their live-only boundary',async()=>{
  const s=independentlyQuarantiningServer(),w=await preparedWitness(s);
  s.setState('app_quarantined'); await assert.rejects(w.ownerRequested({attempt_id:nextId,broker_port:1026,preflight:false}));
  assert.equal(w.failed,true); assert.equal(w.ownerCount,1); assert.equal(w.eofReported,false);
});
