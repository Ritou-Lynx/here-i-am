import assert from 'node:assert/strict';
import test from 'node:test';
import { TextGateTransportError } from './workbench_text_gate_transport.mjs';
import {
  createNativeProbeExchange,
  createNativeProbeNotificationSummary,
  summarizeNativeProbeExchangeFailure,
} from './workbench_text_task_authenticated_probe.mjs';

test('probe observations retain fixed counters and never notification payloads or dynamic names', () => {
  const summary = createNativeProbeNotificationSummary();
  summary.observe({ message: { method: 'turn/started', params: { threadId: 'private-thread' } } });
  summary.observe({ message: { method: 'error', params: { error: { message: 'private-provider-message', token: 'secret' } } } });
  summary.observe({ message: { method: 'private-account-method', params: { account: 'private-account' } } });
  summary.observe({ message: { method: 'modelProvider/authRecoveryStarted', params: { provider: 'private-provider' } } });
  summary.observe({ message: { method: 'modelProvider/authRecoveryCompleted', params: { error: 'secret' } } });
  const result = summary.snapshot();
  assert.deepEqual(result, { turn_started: 1, turn_completed: 0, item_started: 0,
    item_completed: 0, text_delta: 0, error: 1, auth_recovery_started: 1,
    auth_recovery_completed: 1, other: 1, saturated: false,
    error_samples: [{ error_kind: 'unknown', http_status_code: null, will_retry: null }],
    error_samples_saturated: false });
  assert.equal(Object.isFrozen(result), true);
  assert.equal(/private|secret/.test(JSON.stringify(result)), false);
});

test('snapshots distinguish task observations from later cleanup without retaining mutable state', () => {
  const summary = createNativeProbeNotificationSummary();
  summary.observe({ message: { method: 'turn/started' } });
  const before = summary.snapshot();
  summary.observe({ message: { method: 'turn/completed' } });
  assert.equal(before.turn_completed, 0);
  assert.equal(summary.snapshot().turn_completed, 1);
});

test('notification observations saturate and malformed inputs cannot create report keys', () => {
  const summary = createNativeProbeNotificationSummary();
  for (let count = 0; count < 70000; count++) summary.observe(null);
  summary.observe({ message: { method: '__proto__' } });
  assert.equal(summary.snapshot().other, 65535);
  assert.equal(summary.snapshot().saturated, true);
  assert.equal(Object.hasOwn(summary.snapshot(), '__proto__'), false);
});

test('error observations normalize only fixed schema fields and discard private or malformed values', () => {
  const summary = createNativeProbeNotificationSummary();
  const observe = (codexErrorInfo, willRetry) => summary.observe({ message: { method: 'error', params: {
    error: { codexErrorInfo, message: 'private text', additionalDetails: 'secret', misalignment: { steer: 'secret' } },
    threadId: 'private-thread', turnId: 'private-turn', willRetry,
  } } });
  observe('unauthorized', false);
  observe({ responseStreamConnectionFailed: { httpStatusCode: 503, private: 'secret' } }, true);
  observe({ httpConnectionFailed: { httpStatusCode: 65536 } }, 'secret');
  observe({ activeTurnNotSteerable: { turnKind: 'review' } }, false);
  observe({ private: 'secret' }, null);
  observe({ httpConnectionFailed: { httpStatusCode: 401 }, private: 'secret' }, true);
  const before = summary.snapshot();
  assert.deepEqual(before.error_samples, [
    { error_kind: 'unauthorized', http_status_code: null, will_retry: false },
    { error_kind: 'responseStreamConnectionFailed', http_status_code: 503, will_retry: true },
    { error_kind: 'httpConnectionFailed', http_status_code: null, will_retry: null },
    { error_kind: 'active_turn_not_steerable', http_status_code: null, will_retry: false },
    { error_kind: 'unknown', http_status_code: null, will_retry: null },
    { error_kind: 'unknown', http_status_code: null, will_retry: true },
  ]);
  for (let count = 0; count < 20; count++) observe('private-method', true);
  const after = summary.snapshot();
  assert.equal(before.error_samples.length, 6);
  assert.equal(after.error_samples.length, 16);
  assert.equal(after.error_samples_saturated, true);
  assert.equal(Object.isFrozen(before.error_samples), true);
  assert.equal(Object.isFrozen(before.error_samples[0]), true);
  assert.equal(/private|secret/.test(JSON.stringify(after)), false);
});

test('exchange failure diagnostics retain only fixed transport fields and rethrow the original error', async () => {
  const rejected = new TextGateTransportError('response_rejected', { gateCode: 'unknown_field' });
  rejected.httpStatus = 503;
  rejected.responseMetadata = { http_status: 404, headers: 'private', body: 'secret' };
  rejected.schemaLocation = 'sse_response';
  assert.deepEqual(summarizeNativeProbeExchangeFailure(rejected), {
    transport_code: 'response_rejected', http_status: 503,
    response_gate_code: 'unknown_field', schema_location: 'sse_response',
  });
  const malformed = new TextGateTransportError('private_transport', { gateCode: 'private_gate' });
  malformed.responseMetadata = { http_status: 99, url: 'private' };
  malformed.schemaLocation = 'private_location';
  assert.deepEqual(summarizeNativeProbeExchangeFailure(malformed), {
    transport_code: 'other', http_status: null,
    response_gate_code: null, schema_location: null,
  });
  const report = { exchange_failure: null };
  const outgoing = Object.freeze({ fixed: true });
  const options = Object.freeze({ fixed: true });
  let calls = 0;
  const exchange = createNativeProbeExchange(report, { exchange: async (body, receivedOptions) => {
    calls++;
    assert.strictEqual(body, outgoing);
    assert.strictEqual(receivedOptions, options);
    throw calls === 1 ? rejected : malformed;
  } });
  await assert.rejects(() => exchange(outgoing, options), error => error === rejected);
  await assert.rejects(() => exchange(outgoing, options), error => error === malformed);
  assert.deepEqual(report.exchange_failure, summarizeNativeProbeExchangeFailure(rejected));
  assert.equal(Object.isFrozen(report.exchange_failure), true);
  assert.equal(/private|secret/.test(JSON.stringify(report.exchange_failure)), false);
});
