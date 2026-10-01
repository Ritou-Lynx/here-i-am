// Single-attempt lifecycle controller. The host supplies an already isolated,
// verified client/thread and the native child's close observer. This controller
// issues stop receipts only; it cannot attest or enable execution isolation.
import { randomUUID } from 'node:crypto';
import { WorkbenchTextStopReceiptLedger } from './workbench_text_stop_receipt.mjs';

const reject = code => { throw Object.assign(new Error(code), { code }); };
const validId = value => typeof value === 'string' && value.length > 0 && value.length <= 256;

export class WorkbenchTextTaskSession {
  #client; #broker; #closeChild; #ledger; #binding; #turn = null;
  #startPromise = null; #closePromise = null; #interruptPromise = null;
  #started = false; #dispatched = false; #closing = false; #terminal = null;
  #buffer = []; #events = []; #textSize = 0; #fault = null;
  #startSequence = 0; #notify; #serverRequest; #protocolError; #onFault;
  #terminalTimeoutMs;
  #startUnconfirmed = false; #childClosed = false; #detached = false;

  constructor({ client, broker, closeChild, localSessionId = randomUUID(),
    executionEpoch, providerThreadId, terminalTimeoutMs = 10000, onFault = null }) {
    if (!client?.isReady || typeof client.request !== 'function'
      || typeof broker?.arm !== 'function' || typeof broker?.close !== 'function'
      || typeof broker?.revoke !== 'function' || typeof broker?.snapshot !== 'function'
      || typeof closeChild !== 'function' || !validId(providerThreadId)
      || (onFault !== null && typeof onFault !== 'function')
      || !Number.isSafeInteger(terminalTimeoutMs) || terminalTimeoutMs < 1 || terminalTimeoutMs > 60000) {
      reject('text_session_binding_invalid');
    }
    this.#binding = Object.freeze({ local_session_id: localSessionId,
      execution_epoch: executionEpoch, provider_thread_id: providerThreadId });
    this.#client = client; this.#broker = broker; this.#closeChild = closeChild;
    this.#onFault = onFault;
    this.#terminalTimeoutMs = terminalTimeoutMs;
    this.#ledger = new WorkbenchTextStopReceiptLedger({ localSessionId, executionEpoch, providerThreadId });
    this.#notify = entry => this.#onNotification(entry);
    this.#serverRequest = request => {
      this.#fail('text_session_host_request_rejected');
      try { request.respondError({ code: -32601, message: 'Text tasks reject all host requests.' }); } catch { /* Still close the owned child. */ }
    };
    this.#protocolError = () => this.#fail('text_session_protocol_error');
    client.on('notification', this.#notify);
    client.on('serverRequest', this.#serverRequest);
    client.on('protocolError', this.#protocolError);
    client.on('processError', this.#protocolError);
  }

  get binding() { return this.#binding; }

  startTurn(input) {
    if (this.#started || this.#closing || this.#fault) reject('text_session_not_fresh');
    // A synchronous reservation fences concurrent callers, including the period
    // in which a start response/turn identity is not yet known.
    this.#started = true;
    this.#turn = { local: randomUUID(), provider: null };
    this.#startSequence = this.#client.notificationSequence;
    this.#startPromise = (async () => {
      let requestAttempted = false;
      try {
        this.#broker.arm(input);
        requestAttempted = true;
        const response = await this.#client.request('turn/start', {
          threadId: this.#binding.provider_thread_id,
          input: [{ type: 'text', text: input }], environments: [],
        }, { onDispatched: () => {
          if (this.#dispatched) return;
          this.#ledger.recordStartDispatched();
          this.#dispatched = true;
          // A timeout may precede the native stdin-write acknowledgement.
          // Keep the real dispatch fact without reviving this failed attempt.
          if (this.#startUnconfirmed) this.#ledger.recordStartOutcomeUnknown();
        } });
        if (!this.#dispatched || !validId(response?.turn?.id)) reject('text_turn_start_unknown');
        this.#turn.provider = response.turn.id;
        this.#ledger.recordTurnStarted({ ...this.#facts(), sequence: this.#startSequence });
        for (const entry of this.#buffer) this.#consume(entry);
        this.#buffer = [];
        if (this.#fault) reject(this.#fault);
        return Object.freeze({ turn_id: this.#turn.local, local_turn_id: this.#turn.local,
          provider_turn_id: this.#turn.provider, ...this.#binding });
      } catch {
        this.#startUnconfirmed = true;
        if (this.#dispatched && !this.#turn.provider) this.#ledger.recordStartOutcomeUnknown();
        else if (!requestAttempted) this.#ledger.recordStartNotDispatched();
        this.#fail('text_turn_start_unknown');
        reject('text_turn_start_unknown');
      }
    })();
    return this.#startPromise;
  }

  #facts() {
    return { executionEpoch: this.#binding.execution_epoch,
      providerThreadId: this.#binding.provider_thread_id,
      localTurnId: this.#turn?.local, turnId: this.#turn?.provider };
  }

  #onNotification(entry) {
    if (!this.#started || !this.#dispatched || entry.sequence <= this.#startSequence) return;
    if (entry.message?.params?.threadId !== this.#binding.provider_thread_id) return;
    if (!this.#turn?.provider) {
      if (this.#buffer.length >= 256) this.#fail('text_session_event_limit');
      else this.#buffer.push(entry);
      return;
    }
    this.#consume(entry);
  }

  #consume({ sequence, message }) {
    const params = message.params;
    if (message.method === 'turn/completed') {
      if (params.turn?.id !== this.#turn.provider) return;
      try {
        const result = this.#ledger.recordProviderTerminal({ ...this.#facts(),
          status: params.turn.status, sequence });
        if (result.code === 'recorded') {
          this.#terminal = { status: params.turn.status, sequence };
          this.#append('turn_status', { status: params.turn.status });
        }
      } catch { this.#fail('text_session_terminal_invalid'); }
    } else if (message.method === 'item/agentMessage/delta') {
      if (params.turnId !== this.#turn.provider) return;
      if (this.#terminal) { this.#fail('text_session_text_after_terminal'); return; }
      if (typeof params.delta !== 'string' || (this.#textSize += params.delta.length) > 24000) {
        this.#fail('text_session_output_limit'); return;
      }
      if (!this.#closing) this.#append('message_delta', { data: { text: params.delta } });
    }
  }

  #append(kind, fields) {
    if (this.#events.length >= 4096) { this.#fail('text_session_event_limit'); return; }
    this.#events.push(Object.freeze({ sequence: this.#events.length + 1,
      turn_id: this.#turn?.local ?? null, kind, ...fields }));
  }

  #fail(code) {
    if (this.#fault) return;
    this.#fault = code;
    this.#broker.revoke();
    if (this.#events.length < 4096) this.#append('error', { data: { code } });
    // Optional owner notification is intentionally side-channel only: no
    // receipt fact or public event depends on an observer being present.
    try { this.#onFault?.(code); } catch { /* Task failure remains fail-closed. */ }
  }

  readEvents(after = 0) {
    if (!Number.isSafeInteger(after) || after < 0) reject('invalid_event_cursor');
    return { status: this.#fault ? 'failed' : this.#closing ? 'closing' : 'ready',
      events: this.#events.filter(entry => entry.sequence > after), next_sequence: this.#events.length };
  }

  interruptTurn(localTurnId) {
    if (!this.#turn?.provider || localTurnId !== this.#turn.local) reject('text_turn_binding_mismatch');
    if (!this.#interruptPromise) this.#interruptPromise = (async () => {
      if (this.#terminal) return { interrupt_dispatched: false };
      let dispatched = false;
      await this.#client.interruptTurn(this.#binding.provider_thread_id, this.#turn.provider, {
        onDispatched: () => {
          this.#ledger.recordInterruptDispatched({ ...this.#facts(), sequence: this.#client.notificationSequence });
          dispatched = true;
        },
      });
      // This ACK is deliberately not converted into a stop/cancel success.
      this.#ledger.recordInterruptAcknowledged({ ...this.#facts(), sequence: this.#client.notificationSequence });
      return { interrupt_dispatched: dispatched };
    })();
    return this.#interruptPromise;
  }

  close() {
    if (this.#closePromise) return this.#closePromise;
    this.#closing = true;
    const attempt = Promise.resolve().then(async () => {
      try {
        if (this.#startPromise) { try { await this.#startPromise; } catch { /* Outcome remains unknown. */ } }
        if (!this.#started) this.#ledger.recordStartNotDispatched();
        if (this.#turn?.provider && !this.#terminal) {
          try { await this.interruptTurn(this.#turn.local); } catch { /* Still require an exact terminal. */ }
          this.#broker.revoke();
          try {
            await this.#client.waitForNotification('turn/completed', event =>
              event.params?.threadId === this.#binding.provider_thread_id
              && event.params?.turn?.id === this.#turn.provider,
            { afterSequence: this.#startSequence, timeoutMs: this.#terminalTimeoutMs });
          } catch { /* Local cleanup never fabricates provider terminal. */ }
        }
      } finally {
        this.#broker.revoke();
        // The caller must observe the exact native CLI process/Job, not merely
        // helper exit, stdin EOF, kill success or a generic HTTP DELETE reply.
        if (!this.#childClosed) {
          try {
            if (await this.#closeChild() === true) {
              this.#childClosed = true;
              this.#ledger.recordLocalChildCloseObserved();
            }
          } catch { /* Unknown is retryable; it is not a terminal close fact. */ }
        }
        try {
          await this.#broker.close();
          if (this.#broker.snapshot().drained === true) this.#ledger.recordProxyDrained();
        } finally {
          if (this.#childClosed && !this.#detached) {
            this.#detached = true;
            this.#client.off('notification', this.#notify);
            this.#client.off('serverRequest', this.#serverRequest);
            this.#client.off('protocolError', this.#protocolError);
            this.#client.off('processError', this.#protocolError);
          }
        }
      }
      const result = this.#ledger.finalize();
      if (!result.receipt || this.#fault) reject(this.#fault || result.code);
      return result.receipt;
    });
    this.#closePromise = attempt;
    // A failed wait must not strand the native owner. Retrying observes the
    // same owner operation; closeChild is required to be idempotent.
    void attempt.catch(() => { if (this.#closePromise === attempt) this.#closePromise = null; });
    return this.#closePromise;
  }
}
