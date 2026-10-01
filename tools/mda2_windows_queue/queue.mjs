import { randomUUID } from 'node:crypto';
import { ProtectedStore, hash, encode, fail } from './store.mjs';
import { ACTIVITY_RAW_RETENTION_MS, normalizeActivityEvent } from '../i_core/activity_control_plane.mjs';

const TERMINAL = new Set(['ttl_expired','event_retained_out','scope_denied','unregistered_diagnostic',
  'identity_binding_mismatch','event_id_binding_mismatch','source_binding_mismatch','idempotency_conflict',
  'credential_revoked','revoked_replay','invalid_event_id','unsupported_kind','unknown_field','missing_required_field']);

// One instance, one source, one actual OS owner. broker.call is a PRIVATE IPC
// capability. The broker also controls the sole transport exit.
export class WindowsDurableQueue {
  static async open({ root, binding, broker, fresh = false, limits = {}, barrier = () => {} }) {
    const q = new WindowsDurableQueue();
    q.binding = structuredClone(binding); q.broker = broker; q.barrier = barrier;
    q.limits = { rows: 64, bytes: 65536, eventBytes: 8192, pending: 64, metadataBytes: 131072, ...limits };
    for (const v of Object.values(q.limits)) if (!Number.isSafeInteger(v) || v < 1) fail('invalid_limits');
    q.store = await ProtectedStore.open(root, binding, { fresh });
    try {
      const disk = q.store.read();
      let claim;
      try { claim = await broker.call('claim', { root: q.store.root, binding, disk: disk && { digest: disk.digest, revision: disk.state.revision } }); }
      catch (e) {
        // No old authority: decryptable state can be minimized locally, never sent.
        if (disk && e.message === 'lineage_authority_lost') {
          const next = { ...disk.state, revision: disk.state.revision + 1, rows: [], frozen: 'lineage_authority_lost' };
          q.store.write(disk.state.revision, next, q.store.seal(next));
        }
        throw e;
      }
      q.fence = claim.fence;
      q.state = disk?.state ?? { version: 1, binding, epoch: claim.epoch, revision: -1, next: 1,
        fence: q.fence, rows: [], frozen: null, wallFloor: claim.wall, ageFloor: claim.age, clockUncertain: false };
      if (!disk && !fresh) fail('queue_missing');
      if (hash(encode(q.state.binding)) !== hash(encode(binding))) fail('lineage_binding_rejected');
      if (claim.cleanupRequired || claim.lost || q.state.epoch !== claim.epoch) {
        const next = { ...q.state, rows: [], frozen: claim.frozen ?? 'age_authority_lost',
          next: Math.max(q.state.next, claim.nextFloor), revision: Math.max(q.state.revision, claim.revisionFloor) };
        // Revision may advance to the external floor; CAS still uses actual disk revision.
        await q.commit(next, { expected: q.state.revision });
      } else {
        await q.sweep();
      }
      return q;
    } catch (e) { await q.store.close(); throw e; }
  }
  projection(state, digest) {
    return { digest, revision: state.revision, next: state.next, fence: state.fence, frozen: state.frozen,
      rows: state.rows.map((r) => ({ sequence: r.sequence, status: r.status, rawDeadline: r.rawDeadline,
        origin: r.origin, ttlDeadline: r.ttlDeadline, attempts: r.attempts,
        attempt: r.attempt?.id ?? null, fence: r.attempt?.fence ?? null, digest: r.digest })) };
  }
  async commit(next, { expected = this.state.revision, capture, receipt, phase = 'maintenance' } = {}) {
    if (this.poisoned) fail('instance_requires_recovery');
    next.revision++; next.fence = this.fence;
    if (encode(next).length > this.limits.metadataBytes) fail('metadata_capacity');
    await this.store.validate();
    const envelope = this.store.seal(next), digest = hash(envelope);
    this.barrier(`${phase}:before_reserve`);
    try {
      await this.broker.call('prepare', { oldRevision: expected, proposal: this.projection(next, digest), capture, receipt });
      this.barrier(`${phase}:after_reserve`);
      this.store.write(expected, next, envelope, (point) => this.barrier(`${phase}:${point}`));
      await this.broker.call('committed', { digest });
      this.state = next;
      this.barrier(`${phase}:after_authority_commit`);
    } catch (e) {
      // Even a lost prepare reply may have reserved. No same-instance retry.
      this.poisoned = true; throw e;
    }
  }
  async sweep() {
    const time = await this.broker.call('context');
    const next = structuredClone(this.state);
    if (time.lost || time.epoch !== next.epoch || time.age < next.ageFloor) {
      next.rows = []; next.frozen ??= 'age_authority_lost'; next.clockUncertain = true;
    } else {
      if (time.wall < next.wallFloor) next.clockUncertain = true;
      next.wallFloor = Math.max(time.wall, next.wallFloor); next.ageFloor = time.age;
      for (const row of next.rows) {
        if (time.age >= row.rawDeadline) {
          if (!['accepted','duplicate'].includes(row.status)) next.frozen ??= 'retention_unresolved';
        } else if (row.status === 'never_sent' && next.wallFloor > row.ttlDeadline) {
          row.status = 'expired_unsent'; row.bytes = null; row.digest = null;
          next.frozen ??= 'allocated_sequence_gap';
        }
      }
      next.rows = next.rows.filter((r) => time.age < r.rawDeadline);
    }
    await this.commit(next);
    if (this.inflight && !this.state.rows.some((row) => row.attempt?.id === this.inflight.id)) this.inflight = null;
    return this.inspect();
  }
  async allocate(observation, proof) {
    await this.sweep();
    if (this.state.frozen) fail('lineage_frozen');
    let time;
    try { time = await this.broker.call('verifyCapture', { proof, observation }); }
    catch { await this.freeze('acquisition_age_unverified'); fail('acquisition_age_unverified'); }
    const rawDeadline = time.origin + ACTIVITY_RAW_RETENTION_MS;
    if (time.age >= rawDeadline) fail('capture_retention_expired');
    if (this.state.clockUncertain) fail('clock_uncertain');
    if ('event_id' in observation || 'origin_sequence' in observation) fail('observation_already_materialized');
    const seq = this.state.next;
    const event = normalizeActivityEvent({ ...observation, origin_sequence: seq, event_id: `${this.binding.event_id_prefix}.${seq}` });
    for (const key of ['device_id','probe_id','source']) if (event[key] !== this.binding[key]) fail('binding_mismatch');
    if (!this.binding.allowed_kinds.includes(event.kind) || event.coverage.mode !== this.binding.coverage_mode
      || event.coverage.expected_report_interval_ms !== this.binding.expected_report_interval_ms) fail('binding_mismatch');
    const ttlDeadline = event.signal_at_ms + event.ttl_ms;
    if (time.wall > ttlDeadline) fail('capture_ttl_expired');
    if (event.signal_at_ms > time.wall) fail('capture_future_clock');
    const bytes = encode(event);
    const pending = this.state.rows.filter((r) => ['never_sent','attempted_unknown'].includes(r.status));
    const used = this.state.rows.reduce((n,r) => n + (r.bytes ? Buffer.byteLength(r.bytes, 'base64') : 0), 0);
    if (this.state.rows.length >= this.limits.rows || pending.length >= this.limits.pending
      || bytes.length > this.limits.eventBytes || used + bytes.length > this.limits.bytes) { bytes.fill(0); fail('capacity_reached'); }
    const next = structuredClone(this.state);
    next.next++;
    next.rows.push({ sequence: seq, bytes: bytes.toString('base64'), digest: hash(bytes), status: 'never_sent',
      attempts: 0, attempt: null, receipt: null, origin: time.origin, rawDeadline, ttlDeadline });
    bytes.fill(0);
    await this.commit(next, { capture: { proof, observation }, phase: 'allocate' });
    return { sequence: seq, rawDeadline };
  }
  async freeze(reason = 'operator_frozen') {
    // Reason classes only; callers cannot store arbitrary diagnostic text.
    const allowed = new Set(['operator_frozen','acquisition_age_unverified','transport_terminal']);
    if (!allowed.has(reason)) fail('invalid_freeze_reason');
    const next = structuredClone(this.state); next.frozen ??= reason; await this.commit(next);
  }
  async begin(sequence) {
    await this.sweep();
    if (this.state.frozen || this.state.clockUncertain) fail('lineage_frozen');
    if (this.inflight) fail('send_busy');
    const next = structuredClone(this.state), row = next.rows.find((r) => r.sequence === sequence);
    if (!row?.bytes || !['never_sent','attempted_unknown'].includes(row.status)) fail('not_sendable');
    if (next.rows.some((r) => r.sequence < sequence && ['never_sent','attempted_unknown'].includes(r.status))) fail('fifo_required');
    row.status = 'attempted_unknown'; row.attempts++;
    row.attempt = { id: randomUUID(), sequence, fence: this.fence };
    await this.commit(next, { phase: 'attempt' });
    this.inflight = structuredClone(row.attempt);
    return this.inflight;
  }
  async deliver(attempt) {
    if (!this.inflight || this.inflight.id !== attempt.id) fail('attempt_not_pending');
    await this.store.validate();
    const row = this.state.rows.find((r) => r.sequence === attempt.sequence);
    if (!row?.bytes) fail('not_sendable');
    // No API releases raw to an uncontrolled caller. Transport is broker-gated.
    return this.broker.call('deliver', { attempt, bytes: row.bytes });
  }
  release(attempt) {
    if (!this.inflight || this.inflight.id !== attempt.id || this.inflight.fence !== attempt.fence) fail('attempt_not_pending');
    this.inflight = null;
    return { released:true };
  }
  async settle(attempt, receiptProof) {
    if (!this.inflight || this.inflight.id !== attempt.id || attempt.fence !== this.fence) fail('attempt_not_pending');
    await this.sweep();
    const next = structuredClone(this.state), row = next.rows.find((r) => r.sequence === attempt.sequence);
    if (!row) { this.inflight = null; return 'discarded_after_retention'; }
    const reply = await this.broker.call('verifyReceipt', { attempt, proof: receiptProof });
    if (row.attempt.id !== attempt.id) fail('attempt_not_pending');
    if (reply?.results) {
      if (reply.results.length !== 1) fail('invalid_receipt');
      const result = reply.results[0];
      if (!['accepted','duplicate'].includes(result.status)
        || result.event_id !== `${this.binding.event_id_prefix}.${row.sequence}`
        || typeof result.receipt_id !== 'string' || !Number.isSafeInteger(result.server_sequence)) fail('invalid_receipt');
      row.status = result.status; row.receipt = { receipt_id: result.receipt_id, server_sequence: result.server_sequence };
      row.bytes = null; row.digest = null;
    } else if (TERMINAL.has(reply?.code)) {
      row.status = 'terminal'; row.bytes = null; row.digest = null; next.frozen ??= 'transport_terminal';
    }
    await this.commit(next, { phase: 'receipt', receipt: { attempt, proof: receiptProof } }); this.inflight = null;
    return row.status;
  }
  inspect() {
    return { revision: this.state.revision, next: this.state.next, fence: this.state.fence, frozen: this.state.frozen,
      ageFloor: this.state.ageFloor, clockUncertain: this.state.clockUncertain,
      rows: this.state.rows.map(({ bytes, digest, receipt, ...r }) => ({ ...r, rawPresent: !!bytes,
        receiptPresent: !!receipt, ...(receipt ? { receipt } : {}) })) };
  }
  async close() {
    // Best-effort mutable buffer cleanup; JS strings/IPC/GC are not secure erasure.
    if (this.state) this.state.rows = [];
    return this.store.close();
  }
  async authorityDisconnected() {
    // Cleanup never grants authority or new pairing. Handles/ACL remain required.
    if (this.store?.db && this.state) {
      await this.store.validate();
      const disk = this.store.read();
      if (disk) {
        const next = { ...disk.state, revision: disk.state.revision + 1, rows: [], frozen: 'lineage_authority_lost' };
        this.store.write(disk.state.revision, next, this.store.seal(next));
      }
    }
    await this.close();
  }
}
