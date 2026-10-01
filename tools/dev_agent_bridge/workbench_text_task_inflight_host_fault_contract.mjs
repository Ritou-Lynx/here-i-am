// Candidate-only finite observations. No response text, account data or headers.
import { validateHostFaultReady } from './workbench_text_task_host_fault_contract.mjs';
export { validateHostFaultFinal, validateHostFaultJournals } from './workbench_text_task_host_fault_contract.mjs';
export const INFLIGHT_FIXED_INPUT = 'Reply exactly: P6_R7_NATIVE_OK';
const need = value => { if (!value) throw new Error('inflight_host_fault_unconfirmed'); };
const exact = (v, keys) => v && typeof v === 'object' && !Array.isArray(v)
  && Object.keys(v).length === keys.length && keys.every(k => Object.hasOwn(v,k));
const id = value => typeof value === 'string' && value.length>=1 && value.length<=128 && !/[^a-zA-Z0-9_-]/.test(value);
const sessionKeys = ['local_session_id','execution_epoch','provider_thread_id'];
export function validateInflightInitial(value) {
  need(exact(value,['schema','native_ready',...sessionKeys]) && value.schema === 'p6_r7_inflight_initial_v1');
  validateHostFaultReady(value.native_ready); need(sessionKeys.every(k => id(value[k]))); return true;
}
export function validateInflightReady(value, initial) {
  validateInflightInitial(initial);
  need(exact(value,['schema','attempt_id',...sessionKeys,'local_turn_id','provider_turn_id','start_command_id',
    'turn_start_dispatched','exchange_entered','exchange_settled','response_released','terminal_observed','text_observed',
    'upstream_attempts','default_three_pipes','snapshot_claim']) && value.schema === 'p6_r7_inflight_ready_v1'
    && value.attempt_id === initial.native_ready.attempt_id && sessionKeys.every(k => value[k] === initial[k])
    && id(value.local_turn_id) && id(value.provider_turn_id) && value.start_command_id === 1
    && value.turn_start_dispatched === true && value.exchange_entered === 1 && value.exchange_settled === false
    && value.response_released === false && value.terminal_observed === false && value.text_observed === false
    && value.upstream_attempts === 1 && value.default_three_pipes === true
    && value.snapshot_claim === 'local_exchange_pending_at_ready'); return true;
}
export function makeInflightReady(initial,turn,{closing,turns,arms,dispatched,exchange,broker,events,terminalObserved,textObserved}) {
  need(closing===false && turns===1 && arms===1 && dispatched===true && events.status==='ready' && events.events.length===0
    && broker.rejected_connections===0 && broker.rejected_requests===0 && broker.metadata_rejections<=8
    && broker.parsed_requests===broker.metadata_rejections+1);
  const ready={schema:'p6_r7_inflight_ready_v1',attempt_id:initial.native_ready.attempt_id,
    local_session_id:turn.local_session_id,execution_epoch:turn.execution_epoch,provider_thread_id:turn.provider_thread_id,
    local_turn_id:turn.local_turn_id,provider_turn_id:turn.provider_turn_id,start_command_id:1,
    turn_start_dispatched:dispatched,exchange_entered:exchange.entered,exchange_settled:exchange.settled,
    response_released:broker.response_released,terminal_observed:terminalObserved,text_observed:textObserved,
    upstream_attempts:broker.upstream_attempts,default_three_pipes:true,snapshot_claim:'local_exchange_pending_at_ready'};
  validateInflightReady(ready,initial);return Object.freeze(ready);
}
// The actual target supplies exchangeTextOnly, unmodified. The wrapper forwards
// exactly the caller's arguments and never parks a settled result for a kill.
export function observeInflightExchange(exchange) {
  need(typeof exchange === 'function'); let entered = 0; let settled = false;
  return Object.freeze({ snapshot: () => Object.freeze({entered,settled}),
    async exchange(...args) {
      need(++entered === 1);
      try { return await exchange(...args); } finally { settled = true; }
    } });
}
// One fixed start command, repeatable graceful cleanup. The Framework witness's
// inherited UTF-8 StreamWriter may emit a BOM on its first write. Accept it only
// at the absolute start of this stream; never trim or normalize command frames.
// Invalid/oversized lines are discarded whole, without accepting their suffix.
export function createInflightControlReader({onStart,onGraceful}) {
  need(typeof onStart === 'function' && typeof onGraceful === 'function');
  let line = ''; let overflow = false; let started = false; let closing = false; let atStreamStart = true;
  return Object.freeze({ push(chunk) {
    need(typeof chunk === 'string');
    for (const ch of chunk) {
      if (atStreamStart) { atStreamStart = false; if (ch === '\uFEFF') continue; }
      if (ch === '\n') {
        const current = line.endsWith('\r') ? line.slice(0,-1) : line;
        if (!overflow && current === '{"type":"graceful"}') { closing = true; onGraceful(); }
        else if (!overflow && current === '{"type":"start_turn"}' && !started && !closing) { started = true; onStart(); }
        line = ''; overflow = false;
      } else if (line.length < 256 && !overflow) line += ch;
      else overflow = true;
    }
  } });
}
