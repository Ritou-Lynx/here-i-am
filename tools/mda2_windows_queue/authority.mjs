import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import { randomBytes, randomUUID, createHmac, timingSafeEqual } from 'node:crypto';
import { hash, encode, fail, windowsHelper } from './store.mjs';
import { ACTIVITY_RAW_RETENTION_MS, normalizeActivityEvent } from '../i_core/activity_control_plane.mjs';

export class WindowsAgeClock {
  constructor() {
    if (process.platform !== 'win32') fail('windows_required');
    this.pending = []; this.dead = false; this.floor = 0;
    this.child = windowsHelper(fileURLToPath(new URL('./windows_clock.ps1', import.meta.url)));
    this.child.stderr.resume();
    createInterface({ input: this.child.stdout }).on('line', (line) => {
      const pending = this.pending.shift(); if (!pending) return;
      const age = Number(line);
      if (!Number.isSafeInteger(age) || age < this.floor) pending.reject(new Error('age_authority_lost'));
      else { this.floor = age; pending.resolve({ age, wall: Date.now() }); }
    });
    this.child.on('error', () => this.lost()); this.child.on('exit', () => this.lost());
    this.child.stdin.on('error', () => this.lost());
  }
  lost() { this.dead = true; for (const p of this.pending.splice(0)) p.reject(new Error('age_authority_lost')); }
  sample() {
    if (this.dead) return Promise.reject(new Error('age_authority_lost'));
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => { this.child.kill(); reject(new Error('age_authority_lost')); }, 10000);
      this.pending.push({ resolve: (v) => { clearTimeout(timeout); resolve(v); }, reject: (e) => { clearTimeout(timeout); reject(e); } });
      this.child.stdin.write('sample\n');
    });
  }
  async close() {
    if (this.dead) return;
    const exit = new Promise((resolve) => this.child.once('exit', resolve));
    this.child.stdin.end('close\n'); await exit;
  }
}

// Authority lives in the broker process, outside every restorable queue file.
// No serialization/import API: losing this process permanently loses its epoch.
export class SurvivingBrokerAuthority {
  constructor({ clock, maxLineages = 8, maxNativeChannels = 1 }) {
    this.clock = clock; this.maxLineages = maxLineages; this.maxNativeChannels=maxNativeChannels;
    this.epoch = randomUUID(); this.key = randomBytes(32); this.lineages = new Map();
    this.nativeChannels = new Map();
    this.time = null; this.ageLost = false;
  }
  async sample() {
    try {
      const time = await this.clock.sample();
      if (!Number.isSafeInteger(time.age) || time.age < 0 || !Number.isSafeInteger(time.wall)
        || (this.time && time.age < this.time.age)) fail('age_authority_lost');
      this.time = time;
      for (const a of this.lineages.values()) {
        for (const [nonce, deadline] of a.consumed) if (time.age >= deadline) a.consumed.delete(nonce);
        for (const [attempt,deadline] of a.dispatched) if(time.age>=deadline) a.dispatched.delete(attempt);
        for (const view of [a.current, a.pending]) {
          if (!view) continue;
          if (view.rows.some(r=>time.age>=r.rawDeadline)) a.needsSweep = true;
          view.rows = view.rows.filter((r) => time.age < r.rawDeadline);
        }
      }
    } catch {
      this.ageLost = true;
      for(const a of this.lineages.values()) {
        a.needsSweep = true; a.consumed.clear(); a.dispatched.clear();
        for(const view of [a.current,a.pending]) if(view) view.rows=[];
      }
    }
    return this.context();
  }
  context() { return { ...this.time, epoch: this.epoch, lost: this.ageLost }; }
  mac(value) { return createHmac('sha256', this.key).update(encode(value)).digest('hex'); }
  sign(value) { return { value, mac: this.mac(value) }; }
  verify(proof) {
    if (!proof?.value || typeof proof.mac !== 'string' || !/^[a-f0-9]{64}$/.test(proof.mac)) fail('proof_unverified');
    if (!timingSafeEqual(Buffer.from(proof.mac, 'hex'), Buffer.from(this.mac(proof.value), 'hex'))) fail('proof_unverified');
    return proof.value;
  }
  // Called ONLY by the trusted acquisition adapter at capture, never the queue.
  capture(lineage, observation) {
    this.get(lineage);
    if (this.ageLost || !this.time) fail('age_authority_lost');
    return this.sign({ type: 'capture', lineage, epoch: this.epoch, nonce: randomUUID(),
      origin: this.time.age, observation: hash(encode(observation)) });
  }
  openNativeChannel(bindings, { nonce, sessionId }) {
    if (!Array.isArray(bindings) || bindings.length !== 2 || typeof nonce !== 'string'
      || !/^[A-Za-z0-9_-]{32,64}$/.test(nonce) || !Number.isSafeInteger(sessionId) || sessionId < 0) {
      fail('native_channel_rejected');
    }
    if(this.nativeChannels.size>=this.maxNativeChannels)fail('native_channel_capacity');
    const lineages = new Map();
    for (const binding of bindings) {
      const authority = this.get(binding.event_id_prefix);
      if (authority.binding !== hash(encode(binding)) || lineages.has(binding.source)
        || !['windows_wts','windows_last_input'].includes(binding.source)) fail('native_channel_rejected');
      lineages.set(binding.source, binding.event_id_prefix);
    }
    if (lineages.size !== 2) fail('native_channel_rejected');
    const token = randomUUID();
    this.nativeChannels.set(token, { nonce, sessionId, lineages, sequence: 0, ageFloor: -1,
      sourceAge: new Map(), qualityEpoch: 0, closed: false });
    return { token, epoch: this.epoch };
  }
  closeNativeChannel(token) {
    const channel = this.nativeChannels.get(token);
    if (channel) { channel.closed = true; this.nativeChannels.delete(token); }
  }
  captureNative(token, packet, observation = null) {
    const channel = this.nativeChannels.get(token);
    if (!channel || channel.closed || this.ageLost || !this.time) fail('native_channel_rejected');
    if (packet.nonce !== channel.nonce || packet.epoch !== this.epoch || packet.sessionId !== channel.sessionId
      || !Number.isSafeInteger(packet.sequence) || packet.sequence !== channel.sequence + 1
      || !Number.isSafeInteger(packet.captureAge) || packet.captureAge < channel.ageFloor || packet.captureAge > this.time.age
      || !Number.isSafeInteger(packet.captureWall) || packet.captureWall > this.time.wall + 1000
      || Math.abs((this.time.age - packet.captureAge) - (this.time.wall - packet.captureWall)) > 5000
      || !Number.isSafeInteger(packet.qualityEpoch) || packet.qualityEpoch < channel.qualityEpoch) {
      fail('native_packet_unverified');
    }
    const qualityChange = ['power.suspended','power.resumed'].includes(packet.kind);
    if (qualityChange ? packet.qualityEpoch !== channel.qualityEpoch + 1 : packet.qualityEpoch !== channel.qualityEpoch) {
      fail('native_quality_epoch_rejected');
    }
    const gap=packet.kind==='source.gap';
    const lineage=channel.lineages.get(packet.source);
    const factKind=packet.source==='windows_wts'&&['session.locked','session.unlocked'].includes(packet.kind)
      ?packet.kind:packet.source==='windows_last_input'&&packet.kind==='input.sample'?'input.idle_bucket':null;
    if(qualityChange){if(packet.source!=='quality'||observation!==null)fail('native_packet_unverified');}
    else if(gap){if(!lineage||observation!==null)fail('native_packet_unverified');}
    else if(!lineage||!factKind||!observation||observation.source!==packet.source
      ||observation.kind!==factKind||observation.signal_at_ms!==packet.captureWall)fail('native_capture_rejected');
    const previous=channel.sourceAge.get(packet.source)??-1;
    if(observation&&packet.captureAge<=previous)fail('native_capture_rejected');
    // No channel state moves until the entire packet and optional observation
    // have passed independent source/kind/quality/time validation.
    channel.sequence=packet.sequence;channel.ageFloor=packet.captureAge;
    if(qualityChange)channel.qualityEpoch=packet.qualityEpoch;
    if(gap)channel.sourceAge.delete(packet.source);
    if (!observation) return null;
    channel.sourceAge.set(packet.source,packet.captureAge);
    return this.sign({ type: 'capture', lineage, epoch: this.epoch, nonce: randomUUID(),
      origin: packet.captureAge, observation: hash(encode(observation)), nativeChannel: token,
      nativeSequence: packet.sequence, qualityEpoch: packet.qualityEpoch });
  }
  registerFresh(binding, root) {
    const lineage = binding.event_id_prefix;
    if (this.lineages.has(lineage) || this.lineages.size >= this.maxLineages) fail('lineage_registration_rejected');
    this.lineages.set(lineage, { binding: hash(encode(binding)), bindingValue: structuredClone(binding), root, current: null, pending: null,
      owner: null, fence: 0, frozen: null, consumed: new Map(), dispatched: new Map() });
  }
  get(lineage) { const a = this.lineages.get(lineage); if (!a) fail('lineage_authority_lost'); return a; }
  owned(lineage, owner) { const a = this.get(lineage); if (!owner || a.owner !== owner) fail('owner_fenced'); return a; }
  claim(lineage, owner, root, binding, disk) {
    const a = this.get(lineage);
    if (a.owner) fail('owner_busy');
    if (a.root !== root || a.binding !== hash(encode(binding))) fail('lineage_binding_rejected');
    a.owner = owner; a.fence++;
    a.diskRevision = disk?.revision ?? -1;
    if (a.pending) {
      if (disk?.digest === a.pending.digest && disk.revision === a.pending.revision) a.current = a.pending;
      else { a.frozen ??= 'authority_reservation_gap'; a.cleanupRequired = true; }
      a.pending = null;
    }
    if ((a.current?.digest ?? null) !== (disk?.digest ?? null) || (a.current?.revision ?? -1) !== (disk?.revision ?? -1)) {
      a.frozen ??= 'snapshot_rollback_or_missing';
      a.cleanupRequired = true;
    }
    return { ...this.context(), fence: a.fence, frozen: a.frozen,
      cleanupRequired: a.cleanupRequired ?? false, nextFloor: a.nextFloor ?? 1, revisionFloor: a.revisionFloor ?? -1 };
  }
  // Caller must wait for the actual child exit event (not timeout / PID alone).
  childExited(lineage, owner) { const a = this.lineages.get(lineage); if (a?.owner === owner) a.owner = null; }
  validateRows(a, lineage, owner, proposal, capture, receipt, cleanup) {
    const only = (obj,keys) => { if (!obj || Object.keys(obj).some(k=>!keys.includes(k))) fail('invalid_projection'); };
    only(proposal,['digest','revision','next','fence','frozen','rows']);
    if (!/^[a-f0-9]{64}$/.test(proposal.digest) || !Number.isSafeInteger(proposal.revision) || !Number.isSafeInteger(proposal.fence)
      || ![null,'operator_frozen','acquisition_age_unverified','transport_terminal','allocated_sequence_gap','retention_unresolved',
        'lineage_authority_lost','age_authority_lost','snapshot_rollback_or_missing','authority_reservation_gap'].includes(proposal.frozen)) fail('invalid_projection');
    if (!Array.isArray(proposal.rows) || proposal.rows.length > 1024 || !Number.isSafeInteger(proposal.next)) fail('invalid_projection');
    const previous = new Map((a.current?.rows ?? []).map(r => [r.sequence,r]));
    const nextBefore = a.current?.next ?? 1;
    if (cleanup) { if (proposal.rows.length) fail('cleanup_required'); return null; }
    if (proposal.next !== nextBefore + (capture ? 1 : 0)) fail('sequence_transition_rejected');
    let captured = null;
    if (capture) {
      captured = this.verify(capture.proof);
      if (!capture.observation || 'event_id' in capture.observation || 'origin_sequence' in capture.observation) fail('capture_observation_rejected');
      if (this.ageLost || captured.type !== 'capture' || captured.epoch !== this.epoch || captured.lineage !== lineage
        || captured.observation !== hash(encode(capture.observation)) || captured.origin > this.time.age) fail('acquisition_age_unverified');
      if (this.time.age >= captured.origin + ACTIVITY_RAW_RETENTION_MS) fail('capture_retention_expired');
      if (a.consumed.has(captured.nonce)) fail('capture_reused');
      if (a.consumed.size >= 1024) fail('capture_capacity');
    }
    let priorSequence = 0, additions = 0;
    for (const row of proposal.rows) {
      only(row,['sequence','status','rawDeadline','origin','ttlDeadline','attempts','attempt','fence','digest']);
      for (const k of ['sequence','rawDeadline','origin','ttlDeadline','attempts']) if (!Number.isSafeInteger(row[k]) || row[k]<0) fail('invalid_projection');
      if (row.digest !== null && !/^[a-f0-9]{64}$/.test(row.digest)) fail('invalid_projection');
      if (![null,undefined].includes(row.attempt) && !/^[a-f0-9-]{36}$/.test(row.attempt)) fail('invalid_projection');
      if (!['never_sent','attempted_unknown','accepted','duplicate','terminal','expired_unsent'].includes(row.status)) fail('invalid_projection');
      if (!Number.isSafeInteger(row.sequence) || row.sequence <= priorSequence || row.sequence >= proposal.next) fail('sequence_transition_rejected');
      priorSequence = row.sequence;
      const old = previous.get(row.sequence);
      if (!old) {
        if (!captured || row.sequence !== nextBefore || additions++) fail('capture_required_for_new_row');
        const b = a.bindingValue;
        const event = normalizeActivityEvent({ ...capture.observation, origin_sequence: nextBefore, event_id:`${lineage}.${nextBefore}` });
        for (const key of ['device_id','probe_id','source']) if (event[key] !== b[key]) fail('capture_binding_rejected');
        if (!b.allowed_kinds.includes(event.kind) || event.coverage.mode !== b.coverage_mode
          || event.coverage.expected_report_interval_ms !== b.expected_report_interval_ms) fail('capture_binding_rejected');
        if (this.time.wall > event.signal_at_ms + event.ttl_ms) fail('capture_ttl_expired');
        if (event.signal_at_ms > this.time.wall) fail('capture_future_clock');
        if (row.origin !== captured.origin || row.rawDeadline !== captured.origin + ACTIVITY_RAW_RETENTION_MS
          || row.ttlDeadline !== event.signal_at_ms + event.ttl_ms || row.digest !== hash(encode(event))
          || row.status !== 'never_sent' || row.attempts !== 0 || row.attempt != null || row.fence != null) fail('capture_projection_rejected');
      } else {
        previous.delete(row.sequence);
        for (const key of ['origin','rawDeadline','ttlDeadline']) if (row[key] !== old[key]) fail('immutable_row_rejected');
        if (row.digest !== old.digest && !(row.digest === null && ['accepted','duplicate','terminal','expired_unsent'].includes(row.status))) fail('immutable_digest_rejected');
        if (old.digest === null && row.digest !== null) fail('raw_resurrection_rejected');
        if (row.attempts === old.attempts + 1 && row.status === 'attempted_unknown' && ['never_sent','attempted_unknown'].includes(old.status)) {
          if (row.attempt === old.attempt || typeof row.attempt !== 'string' || row.fence !== a.fence || proposal.frozen) fail('attempt_transition_rejected');
        } else if (row.attempts !== old.attempts || row.attempt !== old.attempt || row.fence !== old.fence) fail('attempt_transition_rejected');
        if (row.status !== old.status) {
          if (old.status === 'never_sent' && row.status === 'attempted_unknown' && row.attempts === old.attempts + 1) { /* intent */ }
          else if (old.status === 'never_sent' && row.status === 'expired_unsent' && this.time.wall > old.ttlDeadline && row.digest === null && proposal.frozen) { /* unsent gap */ }
          else if (old.status === 'attempted_unknown' && ['accepted','duplicate','terminal'].includes(row.status)) {
            if (!receipt || receipt.attempt.sequence !== row.sequence || receipt.attempt.id !== old.attempt) fail('receipt_required');
            const reply = this.verifyReceipt(lineage,owner,receipt.attempt,receipt.proof);
            if (row.status === 'terminal') {
              if (!['ttl_expired','event_retained_out','scope_denied','unregistered_diagnostic','identity_binding_mismatch',
                'event_id_binding_mismatch','source_binding_mismatch','idempotency_conflict','credential_revoked','revoked_replay',
                'invalid_event_id','unsupported_kind','unknown_field','missing_required_field'].includes(reply?.code) || !proposal.frozen) fail('invalid_terminal_receipt');
            } else {
              const result = reply?.results?.[0];
              if (reply?.results?.length !== 1 || result.status !== row.status || result.event_id !== `${lineage}.${row.sequence}`
                || typeof result.receipt_id !== 'string' || !Number.isSafeInteger(result.server_sequence)) fail('invalid_receipt');
            }
            if (row.digest !== null) fail('resolved_raw_must_retire');
          } else fail('state_transition_rejected');
        }
      }
    }
    if (previous.size) fail('premature_row_removal');
    if (additions !== (capture ? 1 : 0)) fail('capture_row_missing');
    return captured;
  }
  prepare(lineage, owner, oldRevision, proposal, capture, receipt) {
    const a = this.owned(lineage, owner);
    const cleanup = (this.ageLost || a.cleanupRequired) && proposal.frozen && proposal.rows.length === 0;
    if (a.pending || oldRevision !== (cleanup ? a.diskRevision : (a.current?.revision ?? -1))) fail('authority_cas_conflict');
    if (proposal.revision <= (a.revisionFloor ?? -1) || proposal.next < (a.nextFloor ?? 1)) fail('authority_floor_rejected');
    if (proposal.fence !== a.fence) fail('owner_fenced');
    if ((this.ageLost || a.cleanupRequired) && (!proposal.frozen || proposal.rows.length)) fail('cleanup_required');
    if (a.current?.frozen && !proposal.frozen) fail('freeze_is_irreversible');
    const c = this.validateRows(a,lineage,owner,proposal,capture,receipt,cleanup);
    if (c) a.consumed.set(c.nonce,c.origin + ACTIVITY_RAW_RETENTION_MS);
    a.pending = structuredClone(proposal);
    a.nextFloor = Math.max(a.nextFloor ?? 1, proposal.next);
    a.revisionFloor = proposal.revision;
    return { reserved: true };
  }
  committed(lineage, owner, digest) {
    const a = this.owned(lineage, owner);
    if (a.pending?.digest !== digest) fail('authority_commit_mismatch');
    a.current = a.pending; a.pending = null;
    a.diskRevision = a.current.revision;
    a.needsSweep = false;
    a.frozen ??= a.current.frozen;
  }
  verifyCapture(lineage, owner, proof, observation) {
    const a = this.owned(lineage, owner), c = this.verify(proof);
    if (this.ageLost || c.type !== 'capture' || c.epoch !== this.epoch || c.lineage !== lineage
      || c.observation !== hash(encode(observation)) || c.origin > this.time.age || a.consumed.has(c.nonce)) fail('acquisition_age_unverified');
    return { origin: c.origin, ...this.context() };
  }
  authorizeSend(lineage, owner, attempt, bytes) {
    const a = this.owned(lineage, owner);
    if (this.ageLost || a.frozen || a.current?.frozen || a.pending) fail('send_frozen');
    const r = a.current?.rows.find((r) => r.sequence === attempt.sequence);
    if (!r || r.attempt !== attempt.id || r.fence !== a.fence || r.status !== 'attempted_unknown'
      || r.digest !== hash(bytes) || this.time.age >= r.rawDeadline) fail('send_fenced_or_expired');
    if (a.current.rows.some((v) => v.sequence < r.sequence && ['never_sent','attempted_unknown'].includes(v.status))) fail('fifo_required');
    if (a.dispatched.has(attempt.id)) fail('attempt_already_dispatched');
    if (a.dispatched.size >= 1024) fail('attempt_capacity');
    a.dispatched.set(attempt.id,r.rawDeadline);
    return r;
  }
  receipt(lineage, owner, attempt, reply) {
    this.owned(lineage, owner);
    return this.sign({ type: 'receipt', lineage, owner, attempt: attempt.id, sequence: attempt.sequence, reply });
  }
  completeSend(lineage, owner, attempt, reply) {
    const a = this.owned(lineage, owner);
    const row = a.current?.rows.find((value) => value.sequence === attempt.sequence);
    if (!row || row.attempt !== attempt.id || row.fence !== a.fence || attempt.fence !== a.fence
      || row.status !== 'attempted_unknown' || row.digest === null || this.time.age >= row.rawDeadline
      || !a.dispatched.has(attempt.id)) fail('late_transport_fenced');
    a.dispatched.delete(attempt.id);
    return this.sign({ type: 'receipt', lineage, owner, attempt: attempt.id, sequence: attempt.sequence, reply });
  }
  verifyReceipt(lineage, owner, attempt, proof) {
    this.owned(lineage, owner); const v = this.verify(proof);
    if (v.type !== 'receipt' || v.lineage !== lineage || v.owner !== owner || v.attempt !== attempt.id || v.sequence !== attempt.sequence) fail('receipt_unverified');
    return v.reply;
  }
  dispose() { this.key.fill(0); this.nativeChannels.clear(); this.lineages.clear(); }
}
