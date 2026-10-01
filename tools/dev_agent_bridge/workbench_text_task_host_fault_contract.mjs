// Pure mirrors for fake witness tests. Actual file/process evidence is acquired
// and independently checked by the standalone C# witness.
import { createHash } from 'node:crypto';
import { TEXT_TASK_CLI_SHA256 } from './workbench_text_task_runtime_pin.mjs';
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const HEX = /^[A-Fa-f0-9]{64}$/;
const hashEq = (a,b) => typeof a==='string' && typeof b==='string' && HEX.test(a) && HEX.test(b) && a.toLowerCase()===b.toLowerCase();
const facts = ['process_close_observed', 'job_empty_verified', 'stdio_eof_verified', 'rules_absent_verified', 'handles_closed_verified', 'helper_exits_verified'];
const binding = ['attempt_id', 'scope_id', 'nonce', 'auth_mode', 'home_class', 'owner_pid', 'owner_creation', 'owner_sha256', 'cli_sha256', 'broker_port'];
const journal = ['schema', ...binding, 'owner_token_digest', 'phase', 'child_pid', 'child_creation'];
const exact = (v, keys) => v && typeof v === 'object' && !Array.isArray(v) && Object.keys(v).length === keys.length && keys.every(k => Object.hasOwn(v, k));
const need = ok => { if (!ok) throw new Error('host_fault_binding_rejected'); };
const pid = n => Number.isInteger(n) && n > 0 && n <= 0x7fffffff;
const time = s => typeof s === 'string' && /^[1-9][0-9]{0,19}$/.test(s) && BigInt(s) <= 0xffffffffffffffffn;
export function isHostFaultGracefulLine(line) {
  if (typeof line !== 'string') return false;
  return (line.endsWith('\r') ? line.slice(0,-1) : line) === '{"type":"graceful"}';
}
export function createHostFaultControlReader(onGraceful) {
  need(typeof onGraceful === 'function'); let line = ''; let overflow = false;
  return Object.freeze({ push(chunk) {
    need(typeof chunk === 'string');
    for (const character of chunk) {
      if (character === '\n') {
        if (!overflow && isHostFaultGracefulLine(line)) onGraceful();
        line = ''; overflow = false;
      } else if (line.length < 256 && !overflow) line += character;
      else overflow = true;
    }
  } });
}
export function hostFaultScope(attempt) {
  need(UUID.test(attempt)); const b = createHash('sha256').update(`HereIAm.P6R7.TaskExecutorV1/${attempt.replaceAll('-', '')}`, 'ascii').digest();
  const hex = bytes => Buffer.from(bytes).toString('hex');
  return `${hex(b.subarray(0,4).reverse())}-${hex(b.subarray(4,6).reverse())}-${hex(b.subarray(6,8).reverse())}-${hex(b.subarray(8,10))}-${hex(b.subarray(10,16))}`;
}
export function validateHostFaultReady(v) {
  need(exact(v, ['schema','attempt_id','child_pid','child_creation','cli_sha256','broker_port','http_created','no_model','default_three_pipes'])
    && v.schema === 'p6_r7_host_fault_ready_v1' && UUID.test(v.attempt_id) && pid(v.child_pid) && time(v.child_creation)
    && v.cli_sha256 === TEXT_TASK_CLI_SHA256 && Number.isInteger(v.broker_port) && v.broker_port > 0 && v.broker_port <= 65535
    && v.http_created === true && v.no_model === true && v.default_three_pipes === true); return true;
}
export function validateHostFaultJournals(prepared, bound, ready, held, expectedHash) {
  validateHostFaultReady(ready);
  for (const j of [prepared, bound]) need(exact(j, journal) && j.schema === 'p6_r7_task_owned_v2'
    && j.attempt_id === ready.attempt_id && j.scope_id === hostFaultScope(ready.attempt_id) && HEX.test(j.nonce)
    && j.auth_mode === 'chatgpt' && j.home_class === 'dedicated_existing' && pid(j.owner_pid) && time(j.owner_creation)
    && hashEq(j.owner_sha256,expectedHash) && hashEq(j.cli_sha256,TEXT_TASK_CLI_SHA256) && HEX.test(j.owner_token_digest)
    && j.broker_port === ready.broker_port);
  need(binding.concat('owner_token_digest').every(k => prepared[k] === bound[k])
    && prepared.phase === 'prepared' && prepared.child_pid === null && prepared.child_creation === null
    && bound.phase === 'bound' && bound.child_pid === ready.child_pid && bound.child_creation === ready.child_creation
    && bound.child_pid !== bound.owner_pid && held.held === true && held.alive === true
    && held.pid === bound.owner_pid && held.creation === bound.owner_creation && hashEq(held.image_sha256,expectedHash));
  return true;
}
export function validateHostFaultFinal(final, bound, held, { nodeKilled, nativeExit }) {
  need(exact(final, ['schema', ...binding, 'child_pid','child_creation','started','close_command_id','shutdown_trigger',
    'operation_failed','stdout_final_emit_succeeded','receipt','requires_actual_exit_0_or_3','receipt_write_state'])
    && final.schema === 'p6_r7_task_final_receipt_v1' && binding.concat('child_pid','child_creation').every(k => final[k] === bound[k])
    && held.held === true && held.pid === bound.owner_pid && held.creation === bound.owner_creation && hashEq(held.image_sha256,bound.owner_sha256)
    && nodeKilled === true && nativeExit === 3 && final.started === true && final.close_command_id === 0
    && final.shutdown_trigger === 'input_eof' && final.operation_failed === true && final.stdout_final_emit_succeeded === false
    && final.requires_actual_exit_0_or_3 === true && final.receipt_write_state === 'pending_actual_exit_commit'
    && exact(final.receipt, [...facts, 'cleanup_pending']) && facts.every(k => final.receipt[k] === true) && final.receipt.cleanup_pending === false);
  return { checks_passed: true, actual_native: false, passed: false };
}
