// Host-owned, single-lifecycle ledger. It never parses RPC bodies and has no
// externally supplied confirmation boolean. Receipt facts live in # fields.
const PROFILE = 'workbench_text_only_v1';
const VERSION = 2;
const BRAND = new WeakSet();
const TERMINAL_STATUSES = new Set(['completed', 'failed', 'interrupted']);

export class WorkbenchTextStopReceiptError extends Error {
  constructor(code) {
    super(code);
    this.name = 'WorkbenchTextStopReceiptError';
    this.code = code;
  }
}

function identifier(value, code) {
  if (typeof value !== 'string' || value.length === 0 || value.length > 256) {
    throw new WorkbenchTextStopReceiptError(code);
  }
  return value;
}

function boundedExecutionEpoch(value) {
  if (typeof value !== 'string' || value.length === 0 || value.length > 256) {
    throw new WorkbenchTextStopReceiptError('invalid_execution_epoch');
  }
  return value;
}

function sequence(value, code = 'invalid_sequence') {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new WorkbenchTextStopReceiptError(code);
  }
  return value;
}

function freeze(value) {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
}

function outcome(code, receipt = null) { return freeze({ code, receipt }); }

export function isWorkbenchTextStopReceipt(value) {
  return !!value && typeof value === 'object' && BRAND.has(value);
}

export class WorkbenchTextStopReceiptLedger {
  #localSessionId;
  #executionEpoch;
  #providerThreadId;
  #start = 'unrecorded';
  #localTurnId = null;
  #providerTurnId = null;
  #interrupt = null;
  #terminal = null;
  #localChildClose = null;
  #proxyDrained = null;
  #lastProviderSequence = -1;
  #receipt = null;

  constructor({ localSessionId, executionEpoch, providerThreadId }) {
    this.#localSessionId = identifier(localSessionId, 'invalid_local_session_id');
    this.#executionEpoch = boundedExecutionEpoch(executionEpoch);
    this.#providerThreadId = identifier(providerThreadId, 'invalid_provider_thread_id');
  }

  recordStartNotDispatched() {
    this.#mutable();
    if (this.#start === 'not_dispatched') return outcome('duplicate_ignored');
    if (this.#start !== 'unrecorded') throw new WorkbenchTextStopReceiptError('invalid_start_transition');
    this.#start = 'not_dispatched';
    return outcome('recorded');
  }

  recordStartDispatched() {
    this.#mutable();
    if (this.#start === 'dispatched') return outcome('duplicate_ignored');
    if (this.#start !== 'unrecorded') throw new WorkbenchTextStopReceiptError('invalid_start_transition');
    this.#start = 'dispatched';
    return outcome('recorded');
  }

  recordStartOutcomeUnknown() {
    this.#mutable();
    if (this.#start === 'unknown') return outcome('duplicate_ignored');
    if (this.#start !== 'dispatched') throw new WorkbenchTextStopReceiptError('invalid_start_transition');
    this.#start = 'unknown';
    return outcome('recorded');
  }

  // localTurnId is the bridge-local turn binding; turnId is the provider turn.
  recordTurnStarted({ executionEpoch, providerThreadId, localTurnId, turnId, sequence: eventSequence }) {
    this.#mutable(); this.#epoch(executionEpoch); this.#thread(providerThreadId);
    const next = sequence(eventSequence);
    if (this.#start !== 'dispatched') throw new WorkbenchTextStopReceiptError('turn_without_dispatched_start');
    if (next <= this.#lastProviderSequence) return outcome('stale_ignored');
    const local = identifier(localTurnId, 'invalid_local_turn_id');
    const provider = identifier(turnId, 'invalid_turn_id');
    if (this.#localTurnId || this.#providerTurnId) {
      if (this.#localTurnId === local && this.#providerTurnId === provider) return outcome('duplicate_ignored');
      throw new WorkbenchTextStopReceiptError('multiple_turns_rejected');
    }
    this.#localTurnId = local;
    this.#providerTurnId = provider;
    this.#lastProviderSequence = next;
    return outcome('recorded');
  }

  // ACK is audit-only. It cannot produce a receipt or a cancellation claim.
  recordInterruptAcknowledged({ executionEpoch, providerThreadId, localTurnId, turnId, sequence: eventSequence }) {
    this.#mutable(); this.#epoch(executionEpoch); this.#turn(providerThreadId, localTurnId, turnId);
    const next = sequence(eventSequence);
    if (next <= this.#lastProviderSequence) return outcome('stale_ignored');
    this.#lastProviderSequence = next;
    return outcome('acknowledged');
  }

  // Call only after the host successfully handed turn/interrupt to stdin.
  recordInterruptDispatched({ executionEpoch, providerThreadId, localTurnId, turnId, sequence: dispatchSequence }) {
    this.#mutable(); this.#epoch(executionEpoch); this.#turn(providerThreadId, localTurnId, turnId);
    const next = sequence(dispatchSequence);
    if (next < this.#lastProviderSequence) return outcome('stale_ignored');
    if (this.#interrupt) {
      if (this.#interrupt.sequence === next) return outcome('duplicate_ignored');
      throw new WorkbenchTextStopReceiptError('multiple_interrupts_rejected');
    }
    this.#interrupt = { sequence: next };
    return outcome('recorded');
  }

  // Call only from a parsed, matching turn/completed notification.
  recordProviderTerminal({ executionEpoch, providerThreadId, localTurnId, turnId, status, sequence: terminalSequence }) {
    this.#mutable(); this.#epoch(executionEpoch); this.#turn(providerThreadId, localTurnId, turnId);
    const next = sequence(terminalSequence);
    if (!TERMINAL_STATUSES.has(status)) throw new WorkbenchTextStopReceiptError('invalid_terminal_status');
    if (this.#terminal) {
      if (this.#terminal.sequence === next && this.#terminal.status === status) return outcome('duplicate_ignored');
      return outcome('stale_ignored');
    }
    if (next <= this.#lastProviderSequence) return outcome('stale_ignored');
    this.#terminal = { status, sequence: next };
    this.#lastProviderSequence = next;
    return outcome('recorded');
  }

  recordLocalChildCloseObserved() {
    this.#mutable();
    if (this.#localChildClose === true) return outcome('duplicate_ignored');
    if (this.#localChildClose === false) throw new WorkbenchTextStopReceiptError('local_close_already_failed');
    this.#localChildClose = true;
    return outcome('recorded');
  }

  recordLocalChildCloseFailed() {
    this.#mutable();
    if (this.#localChildClose === false) return outcome('duplicate_ignored');
    if (this.#localChildClose === true) throw new WorkbenchTextStopReceiptError('local_close_already_observed');
    this.#localChildClose = false;
    return outcome('recorded');
  }

  recordProxyDrained() {
    this.#mutable();
    if (this.#proxyDrained) return outcome('duplicate_ignored');
    this.#proxyDrained = true;
    return outcome('recorded');
  }

  finalize() {
    if (this.#receipt) return outcome('receipt_available', this.#receipt);
    if (this.#start === 'unknown') return outcome('start_outcome_unknown');
    if (this.#localChildClose !== true) return outcome('local_close_unconfirmed');
    if (this.#proxyDrained !== true) return outcome('proxy_not_drained');
    if (this.#start === 'not_dispatched' && this.#providerTurnId === null) {
      return this.#issue(null, 'closed_without_turn');
    }
    if (this.#start !== 'dispatched' || !this.#localTurnId || !this.#providerTurnId) {
      return outcome('turn_unconfirmed');
    }
    if (!this.#terminal) return outcome('provider_terminal_unconfirmed');
    return this.#issue(this.#terminal, 'closed');
  }

  #issue(terminal, outcomeName) {
    const receipt = freeze({
      profile: PROFILE,
      version: VERSION,
      local_session_id: this.#localSessionId,
      execution_epoch: this.#executionEpoch,
      provider_thread_id: this.#providerThreadId,
      local_turn_id: this.#localTurnId,
      turn_id: this.#providerTurnId,
      outcome: outcomeName,
      interrupt_dispatched: this.#interrupt !== null,
      interrupt_dispatch_sequence: this.#interrupt?.sequence ?? null,
      provider_terminal_confirmed: terminal !== null,
      provider_terminal_status: terminal?.status ?? null,
      provider_terminal_sequence: terminal?.sequence ?? null,
      cancellation_confirmed: terminal?.status === 'interrupted' && this.#interrupt !== null &&
        terminal.sequence > this.#interrupt.sequence,
      local_child_close_observed: true,
      proxy_drained: true,
    });
    BRAND.add(receipt);
    this.#receipt = receipt;
    return outcome('receipt_issued', receipt);
  }

  #mutable() {
    if (this.#receipt) throw new WorkbenchTextStopReceiptError('ledger_finalized');
  }

  #thread(providerThreadId) {
    if (identifier(providerThreadId, 'invalid_provider_thread_id') !== this.#providerThreadId) {
      throw new WorkbenchTextStopReceiptError('provider_thread_mismatch');
    }
  }

  #epoch(executionEpoch) {
    if (boundedExecutionEpoch(executionEpoch) !== this.#executionEpoch) {
      throw new WorkbenchTextStopReceiptError('execution_epoch_mismatch');
    }
  }

  #turn(providerThreadId, localTurnId, turnId) {
    this.#thread(providerThreadId);
    if (!this.#localTurnId || !this.#providerTurnId ||
        identifier(localTurnId, 'invalid_local_turn_id') !== this.#localTurnId ||
        identifier(turnId, 'invalid_turn_id') !== this.#providerTurnId) {
      throw new WorkbenchTextStopReceiptError('turn_mismatch');
    }
  }
}
