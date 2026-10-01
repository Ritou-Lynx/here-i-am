import assert from 'node:assert/strict';
import test from 'node:test';
import {
  WorkbenchTextStopReceiptError,
  WorkbenchTextStopReceiptLedger,
  isWorkbenchTextStopReceipt,
} from './workbench_text_stop_receipt.mjs';

const epoch = '3c59a405-023e-447d-8ad2-8ce6fa995821';
const ids = { localSessionId: 'local-1', executionEpoch: epoch, providerThreadId: 'thread-1' };
const turn = 'turn-1';
const localTurn = 'local-turn-1';
function ledger() { return new WorkbenchTextStopReceiptLedger(ids); }
function event(value) { return { executionEpoch: epoch, localTurnId: localTurn, ...value }; }
function closes(value) { value.recordLocalChildCloseObserved(); value.recordProxyDrained(); }
function start(value) { value.recordStartDispatched(); value.recordTurnStarted(event({ providerThreadId: 'thread-1', turnId: turn, sequence: 1 })); }
function error(code, fn) { assert.throws(fn, value => value instanceof WorkbenchTextStopReceiptError && value.code === code); }

test('issues an exact completed receipt only after matching terminal, child close, and proxy drain', () => {
  const value = ledger(); start(value);
  value.recordProviderTerminal(event({ providerThreadId: 'thread-1', turnId: turn, status: 'completed', sequence: 2 }));
  assert.equal(value.finalize().code, 'local_close_unconfirmed');
  closes(value);
  const result = value.finalize();
  assert.equal(result.code, 'receipt_issued');
  assert.equal(result.receipt.outcome, 'closed');
  assert.equal(result.receipt.execution_epoch, epoch);
  assert.equal(result.receipt.local_turn_id, localTurn);
  assert.equal(result.receipt.cancellation_confirmed, false);
  assert.equal(isWorkbenchTextStopReceipt(result.receipt), true);
  assert.equal(Object.isFrozen(result.receipt), true);
  assert.equal(isWorkbenchTextStopReceipt({ ...result.receipt }), false);
});

test('interrupted terminal confirms cancellation only after this interrupt was dispatched first', () => {
  const value = ledger(); start(value);
  value.recordInterruptDispatched(event({ providerThreadId: 'thread-1', turnId: turn, sequence: 2 }));
  value.recordProviderTerminal(event({ providerThreadId: 'thread-1', turnId: turn, status: 'interrupted', sequence: 3 }));
  value.recordInterruptAcknowledged(event({ providerThreadId: 'thread-1', turnId: turn, sequence: 4 }));
  closes(value);
  const receipt = value.finalize().receipt;
  assert.equal(receipt.cancellation_confirmed, true);
  assert.equal(receipt.provider_terminal_sequence, 3);
});

test('terminal before a later interrupt is closed but never called a cancellation', () => {
  const value = ledger(); start(value);
  value.recordProviderTerminal(event({ providerThreadId: 'thread-1', turnId: turn, status: 'interrupted', sequence: 2 }));
  value.recordInterruptDispatched(event({ providerThreadId: 'thread-1', turnId: turn, sequence: 3 }));
  closes(value);
  assert.equal(value.finalize().receipt.cancellation_confirmed, false);
});

test('ACK alone never confirms provider terminal or cancellation', () => {
  const value = ledger(); start(value);
  value.recordInterruptDispatched(event({ providerThreadId: 'thread-1', turnId: turn, sequence: 2 }));
  value.recordInterruptAcknowledged(event({ providerThreadId: 'thread-1', turnId: turn, sequence: 3 }));
  closes(value);
  assert.equal(value.finalize().code, 'provider_terminal_unconfirmed');
});

test('completed and failed terminal events never confirm cancellation', () => {
  for (const status of ['completed', 'failed']) {
    const value = ledger(); start(value);
    value.recordInterruptDispatched(event({ providerThreadId: 'thread-1', turnId: turn, sequence: 2 }));
    value.recordProviderTerminal(event({ providerThreadId: 'thread-1', turnId: turn, status, sequence: 3 }));
    closes(value);
    assert.equal(value.finalize().receipt.cancellation_confirmed, false);
  }
});

test('wrong provider thread, wrong turn, and second turn are rejected', () => {
  const value = ledger(); start(value);
  error('provider_thread_mismatch', () => value.recordProviderTerminal(event({ providerThreadId: 'thread-2', turnId: turn, status: 'completed', sequence: 2 })));
  error('turn_mismatch', () => value.recordProviderTerminal(event({ providerThreadId: 'thread-1', turnId: 'turn-2', status: 'completed', sequence: 2 })));
  error('multiple_turns_rejected', () => value.recordTurnStarted(event({ providerThreadId: 'thread-1', turnId: 'turn-2', sequence: 2 })));
  error('multiple_turns_rejected', () => value.recordTurnStarted(event({ providerThreadId: 'thread-1', localTurnId: 'local-turn-2', turnId: turn, sequence: 2 })));
  error('execution_epoch_mismatch', () => value.recordProviderTerminal(event({ executionEpoch: '00da9540-e724-4f99-998f-6e856cb9cae0', providerThreadId: 'thread-1', turnId: turn, status: 'completed', sequence: 2 })));
});

test('dispatch older than an already-observed provider sequence is ignored', () => {
  const value = ledger(); start(value);
  value.recordInterruptAcknowledged(event({ providerThreadId: 'thread-1', turnId: turn, sequence: 4 }));
  assert.equal(value.recordInterruptDispatched(event({ providerThreadId: 'thread-1', turnId: turn, sequence: 3 })).code, 'stale_ignored');
  value.recordProviderTerminal(event({ providerThreadId: 'thread-1', turnId: turn, status: 'interrupted', sequence: 5 }));
  closes(value);
  assert.equal(value.finalize().receipt.cancellation_confirmed, false);
});

test('stale and duplicate provider events cannot replace the first matching terminal', () => {
  const value = ledger(); start(value);
  assert.equal(value.recordProviderTerminal(event({ providerThreadId: 'thread-1', turnId: turn, status: 'completed', sequence: 2 })).code, 'recorded');
  assert.equal(value.recordProviderTerminal(event({ providerThreadId: 'thread-1', turnId: turn, status: 'completed', sequence: 2 })).code, 'duplicate_ignored');
  assert.equal(value.recordProviderTerminal(event({ providerThreadId: 'thread-1', turnId: turn, status: 'interrupted', sequence: 3 })).code, 'stale_ignored');
  closes(value);
  assert.equal(value.finalize().receipt.provider_terminal_status, 'completed');
});

test('local close failure and undrained proxy block receipt issuance', () => {
  const failed = ledger(); start(failed);
  failed.recordProviderTerminal(event({ providerThreadId: 'thread-1', turnId: turn, status: 'completed', sequence: 2 }));
  failed.recordLocalChildCloseFailed(); failed.recordProxyDrained();
  assert.equal(failed.finalize().code, 'local_close_unconfirmed');
  const pending = ledger(); start(pending);
  pending.recordProviderTerminal(event({ providerThreadId: 'thread-1', turnId: turn, status: 'completed', sequence: 2 }));
  pending.recordLocalChildCloseObserved();
  assert.equal(pending.finalize().code, 'proxy_not_drained');
});

test('only an explicitly not-dispatched start can close without a turn', () => {
  const safe = ledger(); safe.recordStartNotDispatched(); closes(safe);
  const receipt = safe.finalize().receipt;
  assert.equal(receipt.outcome, 'closed_without_turn');
  assert.equal(receipt.local_turn_id, null);
  assert.equal(receipt.turn_id, null);
  assert.equal(receipt.provider_terminal_confirmed, false);
  const unknown = ledger(); unknown.recordStartDispatched(); unknown.recordStartOutcomeUnknown(); closes(unknown);
  assert.equal(unknown.finalize().code, 'start_outcome_unknown');
});

test('public property injection and a fake _issue cannot create receipt facts', () => {
  const value = ledger();
  value.terminal = { status: 'interrupted', sequence: 99 };
  value.localChildClose = true;
  value.proxyDrained = true;
  value._issue = () => ({ code: 'receipt_issued', receipt: { forged: true } });
  value.recordStartNotDispatched();
  assert.equal(value.finalize().code, 'local_close_unconfirmed');
  closes(value);
  const receipt = value.finalize().receipt;
  assert.equal(receipt.outcome, 'closed_without_turn');
  assert.equal(isWorkbenchTextStopReceipt(receipt), true);
  assert.equal(isWorkbenchTextStopReceipt({ forged: true }), false);
});

test('unknown start and finalization reject later evidence', () => {
  const value = ledger(); value.recordStartDispatched(); value.recordStartOutcomeUnknown();
  error('turn_without_dispatched_start', () => value.recordTurnStarted(event({ providerThreadId: 'thread-1', turnId: turn, sequence: 1 })));
  const done = ledger(); done.recordStartNotDispatched(); closes(done); done.finalize();
  error('ledger_finalized', () => done.recordLocalChildCloseObserved());
  assert.equal(done.finalize().code, 'receipt_available');
});

test('constructor and event shapes use fixed validation codes', () => {
  for (const invalidEpoch of ['', 7, -1, 'x'.repeat(257)]) {
    error('invalid_execution_epoch', () => new WorkbenchTextStopReceiptLedger({ ...ids, executionEpoch: invalidEpoch }));
  }
  const value = ledger();
  error('invalid_start_transition', () => value.recordStartOutcomeUnknown());
  value.recordStartDispatched();
  error('invalid_sequence', () => value.recordTurnStarted(event({ providerThreadId: 'thread-1', turnId: turn, sequence: -1 })));
  value.recordTurnStarted(event({ providerThreadId: 'thread-1', turnId: turn, sequence: 1 }));
  error('invalid_terminal_status', () => value.recordProviderTerminal(event({ providerThreadId: 'thread-1', turnId: turn, status: 'unknown', sequence: 1 })));
  for (const invalidEpoch of ['', 7, -1, 'x'.repeat(257)]) {
    error('invalid_execution_epoch', () => value.recordProviderTerminal(event({ executionEpoch: invalidEpoch, providerThreadId: 'thread-1', turnId: turn, status: 'completed', sequence: 2 })));
  }
});

test('execution epoch stays an opaque bounded lease string without normalization', () => {
  const opaque = '  lease:as-issued  ';
  const value = new WorkbenchTextStopReceiptLedger({ ...ids, executionEpoch: opaque });
  value.recordStartNotDispatched(); closes(value);
  assert.equal(value.finalize().receipt.execution_epoch, opaque);
});
