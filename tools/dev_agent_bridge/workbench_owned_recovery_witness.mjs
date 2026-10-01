import { createHash } from 'node:crypto';

const SCHEMA = 'p6_r7_owned_recovery_command_v1';
const REPLY = 'p6_r7_owned_recovery_reply_v1';
const SHA = /^[a-f0-9]{64}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const failureKinds = new WeakMap();
export function witnessFailureClassification(error) {
  if (!(error instanceof Error)) return 'unknown';
  return failureKinds.get(error)
    ?? (Object.getOwnPropertyDescriptor(error, 'message')?.value === 'deadline_exceeded' ? 'timeout' : 'unknown');
}
export function witnessFailure(error) {
  const result = new Error('owned_recovery_witness_rejected');
  failureKinds.set(result, witnessFailureClassification(error)); return result;
}
const fail = error => { throw witnessFailure(error); };
const exact = (v, keys) => v !== null && typeof v === 'object' && !Array.isArray(v)
  && Object.keys(v).length === keys.length && keys.every(k => Object.hasOwn(v, k));
const integer = v => Number.isSafeInteger(v) && v >= 0;
const identity = v => exact(v, ['pid', 'creation', 'imagePath', 'imageSha256'])
  && Number.isInteger(v.pid) && v.pid > 0 && typeof v.creation === 'string' && /^[1-9][0-9]{0,19}$/.test(v.creation)
  && typeof v.imagePath === 'string' && v.imagePath.length > 0 && SHA.test(v.imageSha256);
const childIdentity = v => exact(v, ['pid', 'creation']) && Number.isInteger(v.pid) && v.pid > 0
  && v.pid <= 0xffffffff && typeof v.creation === 'string' && /^[1-9][0-9]{0,19}$/.test(v.creation);

// Replies are closed, flat JSON objects. Validate decoded keys before JSON.parse
// so duplicate escaped keys cannot replace an earlier ACK/epoch/sequence.
function replyObject(raw) {
  if (typeof raw !== 'string' || Buffer.byteLength(raw) > 16384) fail();
  const token = /"(?:[^"\\\u0000-\u001f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*"|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?|true|false|null/y;
  let at = 0; const keys = new Set();
  const ws = () => { while (/[\x20\x09\x0a\x0d]/.test(raw[at] ?? '') && at < raw.length) at++; };
  ws(); if (raw[at++] !== '{') fail(); ws();
  for (;;) {
    token.lastIndex = at; const key = token.exec(raw);
    if (!key || key[0][0] !== '"') fail();
    const name = JSON.parse(key[0]); if (keys.has(name)) fail(); keys.add(name); at = token.lastIndex;
    ws(); if (raw[at++] !== ':') fail(); ws(); token.lastIndex = at;
    if (!token.exec(raw)) fail(); at = token.lastIndex; ws();
    if (raw[at] === '}') { at++; break; }
    if (raw[at++] !== ',') fail(); ws();
  }
  ws(); if (at !== raw.length) fail(); return JSON.parse(raw);
}

export function ownerManifestSha256(owners) {
  if (!Array.isArray(owners) || owners.length < 1 || owners.length > 16) fail();
  const values = owners.map((owner, index) => {
    if (!exact(owner, ['owner_index', 'attempt_id', 'broker_port', 'native_pid', 'native_creation', 'child_pid', 'child_creation',
      'native_exit_code', 'process_close_observed', 'job_empty_verified', 'stdio_eof_verified', 'rules_absent_verified',
      'handles_closed_verified', 'helper_exits_verified', 'cleanup_pending', 'broker_drained', 'native_postpin_verified',
      'preflight_upstream_attempts', 'preflight_arm_attempts'])) fail();
    if (owner.owner_index !== index || !UUID.test(owner.attempt_id) || !Number.isInteger(owner.broker_port)
      || !integer(owner.native_pid) || !integer(owner.child_pid) || !/^[1-9][0-9]{0,19}$/.test(owner.native_creation)
      || !/^[1-9][0-9]{0,19}$/.test(owner.child_creation)) fail();
    return Object.fromEntries(Object.keys(owner).sort().map(key => [key, owner[key]]));
  });
  return createHash('sha256').update(Buffer.from(JSON.stringify(values), 'utf8')).digest('hex');
}

export function createOwnedRecoveryWitness({ adapter, epoch, sourceClosureSha256, nativeSha256 } = {}) {
  if (!(exact(adapter, ['authenticated', 'exchange']) || exact(adapter, ['authenticated', 'exchange', 'exchangeFinal'])) || adapter.authenticated !== true || typeof adapter.exchange !== 'function'
    || (adapter.exchangeFinal !== undefined && typeof adapter.exchangeFinal !== 'function')
    || !SHA.test(epoch) || !SHA.test(sourceClosureSha256) || !SHA.test(nativeSha256)) fail();
  let sequence = 0, sticky = false, barrier = false, admission = null, closed = false;
  let serverQuarantined = false, eofReported = false, queue = Promise.resolve();
  const owners = [];
  function send(type, fields, expected, state) {
    const attempt = queue.then(async () => {
      if (sticky || closed) fail();
      // Recheck when this queued command actually acquires the wire. A prior
      // ACK may have observed App death after this intent was first queued.
      if (['preflight_barrier', 'owner_requested', 'admission_ready'].includes(type)
        && (serverQuarantined || eofReported)) fail();
      if (type === 'host_closed' && serverQuarantined && !eofReported) fail();
      const command = { schema: SCHEMA, epoch, sequence: ++sequence, type, ...fields };
      try {
        const exchange = type === 'host_closed' && adapter.exchangeFinal ? adapter.exchangeFinal : adapter.exchange;
        const raw = await exchange(JSON.stringify(command));
        const reply = replyObject(raw);
        if (!exact(reply, ['schema', 'epoch', 'type', 'state', 'sequence']) || reply.schema !== REPLY || reply.epoch !== epoch
          || reply.type !== expected || reply.sequence !== sequence) fail();
        if (['ping', 'owner_bound', 'owner_closed'].includes(type)) {
          // The independent server can observe original App death first. Only
          // already-owned work may advance across this single state transition.
          if (reply.state === 'app_quarantined') serverQuarantined = true;
          else if (reply.state !== 'live' || serverQuarantined) fail();
        } else {
          if (reply.state !== state) fail();
          if (type === 'app_stdin_eof') serverQuarantined = true;
        }
        return reply;
      } catch (error) { sticky = true; fail(error); }
    });
    queue = attempt.catch(() => {}); return attempt;
  }
  return Object.freeze({
    async ping() { if (!barrier || closed) fail(); await send('ping', {}, 'alive', 'live'); },
    async appStdinEof() {
      if (!barrier || closed || eofReported) fail();
      // Only the real original-stdin end path calls this method. A server ACK
      // can update serverQuarantined, but can never synthesize this obligation.
      eofReported = true;
      await send('app_stdin_eof', { stdin_eof_observed: true,
        stdin_end_handler_settled: true }, 'app_eof_recorded', 'app_quarantined');
    },
    async preflightBarrier() { if (barrier || owners.length) fail(); await send('preflight_barrier', {}, 'preflight_permitted', 'live'); barrier = true; return true; },
    async ownerRequested({ attempt_id, broker_port, preflight }) {
      if (!barrier || closed || serverQuarantined || eofReported || owners.length >= 16 || !UUID.test(attempt_id) || !Number.isInteger(broker_port) || broker_port < 1025 || broker_port > 65535 || typeof preflight !== 'boolean' || preflight !== (owners.length === 0)) fail();
      await send('owner_requested', { owner_index: owners.length, attempt_id, broker_port, preflight }, 'owner_registered', 'live');
      owners.push({ owner_index: owners.length, attempt_id, broker_port, preflight, bound: null, closed: null });
    },
    async ownerBound({ owner_index, attempt_id, native, child }) {
      const owner = owners[owner_index]; if (!owner || owner.attempt_id !== attempt_id || owner.bound || !identity(native) || native.imageSha256 !== nativeSha256 || !childIdentity(child) || native.pid === child.pid) fail();
      await send('owner_bound', { owner_index, attempt_id, native_pid:native.pid, native_creation:native.creation, native_sha256:native.imageSha256, child_pid:child.pid, child_creation:child.creation }, 'owner_binding_recorded', 'live');
      owner.bound = { native, child };
    },
    async ownerClosed(proof) {
      const owner = owners[proof?.owner_index]; if (!owner || owner.attempt_id !== proof.attempt_id || !owner.bound || owner.closed) fail();
      const record = { ...proof, native_pid:owner.bound.native.pid, native_creation:owner.bound.native.creation, child_pid:owner.bound.child.pid, child_creation:owner.bound.child.creation, broker_port:owner.broker_port };
      const facts=['process_close_observed','job_empty_verified','stdio_eof_verified','rules_absent_verified','handles_closed_verified','helper_exits_verified'];
      if (!facts.every(k => record[k]===true) || record.cleanup_pending!==false || record.broker_drained!==true || record.native_postpin_verified!==true || ![0,3].includes(record.native_exit_code)) fail();
      await send('owner_closed', record, 'owner_close_recorded', 'live'); owner.closed = record;
    },
    async admissionReady({ launch_id, admission_sha256 }) { if (!barrier || serverQuarantined || eofReported || admission || owners.length!==1 || !owners[0].preflight || !owners[0].closed || !UUID.test(launch_id) || !SHA.test(admission_sha256)) fail(); await send('admission_ready',{launch_id,admission_sha256,source_closure_sha256:sourceClosureSha256,native_sha256:nativeSha256},'admission_recorded','live'); admission={launch_id,admission_sha256}; },
    async hostClosed({ host_closed_sha256 }) { if (!admission || closed || (serverQuarantined && !eofReported) || !SHA.test(host_closed_sha256) || !owners.every(o=>o.closed)) fail(); const manifest=ownerManifestSha256(owners.map(o=>o.closed)); await send('host_closed',{owner_count:owners.length,host_closed_sha256,owner_manifest_sha256:manifest,launch_id:admission.launch_id,admission_sha256:admission.admission_sha256,source_closure_sha256:sourceClosureSha256,native_sha256:nativeSha256,runtime_closed:true,http_server_closed:true},'host_close_recorded',eofReported?'app_quarantined':'awaiting_app_close'); closed=true; return manifest; },
    get failed() { return sticky; }, get ownerCount() { return owners.length; },
    get serverQuarantined() { return serverQuarantined; }, get eofReported() { return eofReported; },
  });
}
