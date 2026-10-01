import { WindowsDurableQueue } from './queue.mjs';

// Broker-owned IPC only. No CLI containing bindings, raw bytes, or secrets.
if (!process.send) throw new Error('private_broker_ipc_required');
let q, sequence = 0, chain = Promise.resolve(), fault = null, armed = false;
const pending = new Map();
const call = (op, args = {}) => new Promise((resolve, reject) => {
  const id = ++sequence;
  if (!process.connected) { reject(new Error('lineage_authority_lost')); return; }
  const timer = setTimeout(() => { pending.delete(id); reject(new Error('authority_timeout')); }, 15000);
  pending.set(id, { resolve, reject, timer }); process.send({ type: 'authority', id, op, args });
});
function barrier(point) {
  if (armed && point === fault) {
    process.send({ type: 'barrier', point });
    // Broker terminates this owned process while the SQLite stack is still here.
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0);
  }
}
process.on('message', (m) => {
  if (m.type === 'authority_reply') {
    const p = pending.get(m.id); if (!p) return;
    pending.delete(m.id); clearTimeout(p.timer); m.error ? p.reject(new Error(m.error)) : p.resolve(m.result); return;
  }
  if (m.type !== 'command') return;
  chain = chain.then(async () => {
    try {
      let result;
      if (m.op === 'open') {
        q = await WindowsDurableQueue.open({ ...m.args, broker: { call }, barrier });
        process.send({ type: 'guard', pid: q.store.guard.pid }); result = q.inspect();
      } else if (m.op === 'arm') { fault = m.args.point; armed = true; result = true; }
      else if (m.op === 'allocate') result = await q.allocate(m.args.observation, m.args.proof);
      else if (m.op === 'begin') result = await q.begin(m.args.sequence);
      else if (m.op === 'deliver') {
        result = await q.deliver(m.args.attempt); barrier('delivery:after_core');
      } else if (m.op === 'settle') result = await q.settle(m.args.attempt, m.args.proof);
      else if (m.op === 'release') result = q.release(m.args.attempt);
      else if (m.op === 'freeze') result = await q.freeze();
      else if (m.op === 'sweep') result = await q.sweep();
      else if (m.op === 'inspect') result = q.inspect();
      else if (m.op === 'close') {
        const cleanup=await q.close(); process.send({ type: 'result', id: m.id, result: { closed: true,cleanup } }, () => process.exit(0)); return;
      } else throw new Error('invalid_worker_command');
      if(process.connected) process.send({ type: 'result', id: m.id, result });
    } catch (e) {
      if (e.fatal) return;
      if(process.connected) process.send({ type: 'result', id: m.id, error: /^[a-z_0-9]+$/.test(e.message) ? e.message : 'queue_operation_rejected' });
    }
  });
});
process.on('disconnect', () => {
  for (const p of pending.values()) { clearTimeout(p.timer); p.reject(new Error('lineage_authority_lost')); }
  pending.clear();
  chain.finally(async () => { try { await q?.authorityDisconnected(); } finally { process.exit(23); } });
});
