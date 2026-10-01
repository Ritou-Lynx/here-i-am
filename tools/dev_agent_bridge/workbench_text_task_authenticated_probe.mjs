// One explicitly selected fixed public sentence, one dedicated native attempt,
// one broker request. This candidate never enables a production runtime.
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { CodexAppServerClient } from './codex_app_server_client.mjs';
import { createTextTaskBroker, TEXT_TASK_MODEL } from './workbench_text_task_broker.mjs';
import { launchWorkbenchTextNativeExecutor } from './workbench_text_task_native_executor.mjs';
import { verifyNativeTaskConfig } from './workbench_text_task_native_probe.mjs';
import { WorkbenchTextTaskSession } from './workbench_text_task_session.mjs';
import { exchangeTextOnly, TextGateTransportError } from './workbench_text_gate_transport.mjs';

export const NATIVE_FIXED_TEXT = 'P6_R7_NATIVE_OK';
const INPUT = `Reply exactly: ${NATIVE_FIXED_TEXT}`;
const check = (condition, code) => { if (!condition) throw Object.assign(new Error(code), { code }); };
const sleep = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const ERROR_KINDS = new Set(['contextWindowExceeded', 'sessionBudgetExceeded', 'usageLimitExceeded',
  'rateLimitExceeded', 'serverOverloaded', 'cyberPolicy', 'misalignmentPolicyViolation',
  'internalServerError', 'unauthorized', 'badRequest', 'threadRollbackFailed', 'sandboxError', 'other']);
const HTTP_ERROR_KINDS = new Set(['httpConnectionFailed', 'responseStreamConnectionFailed',
  'responseStreamDisconnected', 'responseTooManyFailedAttempts']);
const TRANSPORT_CODES = new Set(['http_status', 'request_rejected', 'response_rejected', 'transport_failed',
  'timeout', 'aborted', 'unsupported_content_type', 'missing_body', 'invalid_headers', 'diagnostic_input_limit', 'invalid_diagnostic_scope']);
const RESPONSE_GATE_CODES = new Set(['unknown_field', 'invalid_shape', 'invalid_json', 'duplicate_json_key',
  'unsupported_content', 'unsupported_item', 'unknown_event', 'unsupported_event', 'unsupported_sse',
  'truncated_sse', 'invalid_terminal', 'event_after_terminal', 'input_limit', 'json_complexity_limit',
  'invalid_response_metadata', 'text_order_conflict', 'part_order_conflict', 'output_conflict',
  'text_conflict', 'item_order_conflict', 'item_id_conflict', 'response_id_conflict', 'sequence_conflict',
  'duplicate_item', 'duplicate_created', 'missing_created', 'invalid_progress', 'empty_message',
  'event_limit', 'output_limit', 'invalid_done_sentinel', 'event_type_conflict', 'duplicate_sse_event']);
const SCHEMA_LOCATIONS = new Set(['unclassified', 'text_part', 'message', 'response', 'sse_response',
  'sse_item', 'sse_content_part', 'sse_text_delta', 'sse_text_done']);

function fixedErrorObservation(params) {
  const info = params?.error?.codexErrorInfo;
  let kind = 'unknown'; let httpStatus = null;
  if (typeof info === 'string' && ERROR_KINDS.has(info)) kind = info;
  else if (info && typeof info === 'object' && !Array.isArray(info) && Object.keys(info).length === 1) {
    const family = Object.keys(info)[0]; const detail = info[family];
    if (HTTP_ERROR_KINDS.has(family) && detail && typeof detail === 'object' && !Array.isArray(detail)) {
      kind = family;
      const value = detail.httpStatusCode;
      if (Number.isInteger(value) && value >= 0 && value <= 65535) httpStatus = value;
    } else if (family === 'activeTurnNotSteerable' && ['review', 'compact'].includes(detail?.turnKind)) {
      kind = 'active_turn_not_steerable';
    }
  }
  return Object.freeze({ error_kind: kind, http_status_code: httpStatus,
    will_retry: typeof params?.willRetry === 'boolean' ? params.willRetry : null });
}

const safeHttpStatus = value => Number.isInteger(value) && value >= 100 && value <= 599 ? value : null;

// This copies only finite diagnostics from a transport error. It deliberately
// excludes Error.message, response headers/body, URL, request fields and all
// response-diagnostic/protocol-key data.
export function summarizeNativeProbeExchangeFailure(error) {
  if (!(error instanceof TextGateTransportError)) return null;
  const code = TRANSPORT_CODES.has(error.code) ? error.code : 'other';
  const httpStatus = safeHttpStatus(error.httpStatus)
    ?? safeHttpStatus(error.responseMetadata?.http_status);
  const responseGateCode = error.code === 'response_rejected'
    ? RESPONSE_GATE_CODES.has(error.gateCode) ? error.gateCode : 'other'
    : null;
  const schemaLocation = error.code === 'response_rejected' && SCHEMA_LOCATIONS.has(error.schemaLocation)
    ? error.schemaLocation : null;
  return Object.freeze({ transport_code: code, http_status: httpStatus,
    response_gate_code: responseGateCode, schema_location: schemaLocation });
}

export function createNativeProbeExchange(report, { exchange = exchangeTextOnly } = {}) {
  return async (outgoing, options) => {
    try { return await exchange(outgoing, options); }
    catch (error) {
      if (report.exchange_failure === null) {
        const summary = summarizeNativeProbeExchangeFailure(error);
        if (summary) report.exchange_failure = summary;
      }
      throw error;
    }
  };
}

// Bounded structural observations only: never retain a notification payload,
// dynamic method name, account field, provider error message or path.
export function createNativeProbeNotificationSummary() {
  const methods = new Map([['turn/started', 'turn_started'], ['turn/completed', 'turn_completed'],
    ['item/started', 'item_started'], ['item/completed', 'item_completed'],
    ['item/agentMessage/delta', 'text_delta'], ['error', 'error'],
    ['modelProvider/authRecoveryStarted', 'auth_recovery_started'],
    ['modelProvider/authRecoveryCompleted', 'auth_recovery_completed']]);
  const counts = Object.fromEntries([...methods.values(), 'other'].map(key => [key, 0]));
  let saturated = false; const errorSamples = []; let errorSamplesSaturated = false;
  return Object.freeze({
    observe(entry) {
      const key = methods.get(entry?.message?.method) ?? 'other';
      if (counts[key] < 65535) counts[key]++; else saturated = true;
      if (key === 'error') {
        if (errorSamples.length < 16) errorSamples.push(fixedErrorObservation(entry?.message?.params));
        else errorSamplesSaturated = true;
      }
    },
    snapshot() { return Object.freeze({ ...counts, saturated,
      error_samples: Object.freeze([...errorSamples]), error_samples_saturated: errorSamplesSaturated }); },
  });
}

export async function runAuthenticatedNativeProbe({ executable, sha256, scenario }) {
  check(['completed', 'interrupt'].includes(scenario), 'native_probe_scenario_invalid');
  const report = { schema: 'p6_r7_authenticated_native_probe_v1', attempt_id: randomUUID(), scenario,
    supervisor_sha256: sha256, started: false, config_verified: false, chatgpt_account_present: false,
    thread_verified: false, turn_started: false, terminal_status: null, fixed_text_observed: false,
    text_empty: true, cancellation_confirmed: false, stop_receipt_verified: false,
    process_close_observed: false, cleanup_pending: true, host_requests: 0, broker: null,
    exchange_failure: null, passed: false, code: null, production_isolation_passed: false, human_gate_passed: false };
  let owner; let client; let session; let closeReceipt; let sessionReceipt;
  let stage = 'broker_start';
  const notifications = createNativeProbeNotificationSummary();
  const broker = createTextTaskBroker({ verifyPeer: socket => owner?.verifyPeer(socket) ?? false,
    exchange: createNativeProbeExchange(report) });
  try {
    const baseUrl = await broker.listen();
    stage = 'native_start';
    owner = launchWorkbenchTextNativeExecutor({ executable, sha256, attemptId: report.attempt_id,
      brokerPort: Number(new URL(baseUrl).port), authMode: 'chatgpt', startupTimeoutMs: 120000, closeTimeoutMs: 120000 });
    const startup = await owner.ready; report.started = true;
    client = new CodexAppServerClient({ attachedTransport: owner, experimentalApi: true, requestTimeoutMs: 15000 });
    client.on('notification', notifications.observe);
    client.on('serverRequest', request => {
      report.host_requests++;
      request.respondError({ code: -32601, message: 'Text tasks reject host requests.' });
    });
    stage = 'client_start'; await client.start();
    stage = 'config_check';
    const config = await client.request('config/read', { cwd: startup.cwd, includeLayers: true });
    const requirements = await client.request('configRequirements/read', {});
    report.config_verified = verifyNativeTaskConfig(config, requirements, baseUrl, 'chatgpt');
    // The official CLI alone reads the existing login. No account values or
    // credential bytes are persisted, copied or returned in this report.
    stage = 'account_check';
    const account = await client.request('account/read', { refreshToken: false });
    report.chatgpt_account_present = account?.account?.type === 'chatgpt';
    check(report.chatgpt_account_present, 'native_probe_login_unconfirmed');
    stage = 'thread_start';
    const thread = await client.startThread({ cwd: startup.cwd, model: TEXT_TASK_MODEL,
      modelProvider: startup.provider, approvalPolicy: 'never', sandbox: 'read-only',
      ephemeral: true, dynamicTools: [], environments: [], runtimeWorkspaceRoots: [], selectedCapabilityRoots: [],
      baseInstructions: 'Complete the fixed public text verification. Return only text.' });
    check(typeof thread?.thread?.id === 'string' && thread.thread.id.length > 0
      && thread.model === TEXT_TASK_MODEL && thread.modelProvider === startup.provider, 'native_probe_thread_rejected');
    report.thread_verified = true;
    session = new WorkbenchTextTaskSession({ client, broker, executionEpoch: randomUUID(),
      providerThreadId: thread.thread.id, terminalTimeoutMs: 15000, closeChild: async () => {
        closeReceipt = await owner.close(); return closeReceipt.process_close_observed === true;
      } });
    const after = client.notificationSequence;
    stage = 'turn_start';
    const turn = await session.startTurn(INPUT); report.turn_started = true;
    if (scenario === 'interrupt') {
      stage = 'upstream_wait';
      const deadline = Date.now() + 15000;
      while (broker.snapshot().upstream_attempts === 0 && Date.now() < deadline) await sleep(20);
      check(broker.snapshot().upstream_attempts === 1, 'native_probe_request_missing');
      stage = 'interrupt'; await session.interruptTurn(turn.turn_id);
    }
    stage = 'terminal_wait';
    const terminal = await client.waitForNotification('turn/completed', event =>
      event.params?.threadId === thread.thread.id && event.params?.turn?.id === turn.provider_turn_id,
    { afterSequence: after, timeoutMs: 75000 });
    report.terminal_status = terminal.params.turn.status;
    const text = session.readEvents().events.filter(event => event.kind === 'message_delta').map(event => event.data.text).join('');
    report.fixed_text_observed = text === NATIVE_FIXED_TEXT; report.text_empty = text === '';
    stage = 'session_close'; sessionReceipt = await session.close();
    report.stop_receipt_verified = sessionReceipt.local_session_id === session.binding.local_session_id
      && sessionReceipt.execution_epoch === session.binding.execution_epoch
      && sessionReceipt.provider_thread_id === thread.thread.id && sessionReceipt.local_turn_id === turn.turn_id
      && sessionReceipt.turn_id === turn.provider_turn_id && sessionReceipt.provider_terminal_confirmed === true
      && sessionReceipt.local_child_close_observed === true && sessionReceipt.proxy_drained === true;
    report.cancellation_confirmed = sessionReceipt.cancellation_confirmed === true;
  } catch (error) {
    report.failure_stage = stage;
    report.code = ['notification_timeout', 'request_timeout'].includes(error.code)
      ? `native_probe_${error.code}`
      : /^native_[a-z_]{1,70}$/.test(error.code) ? error.code : 'native_probe_failed';
  } finally {
    report.notifications_before_cleanup = notifications.snapshot();
    broker.revoke();
    if (session && !sessionReceipt) { try { sessionReceipt = await session.close(); } catch { /* Keep the failed task outcome. */ } }
    if (owner && !closeReceipt) {
      try { closeReceipt = await owner.close(); } catch { report.code = 'native_probe_close_unconfirmed'; }
    }
    await broker.close(); report.broker = broker.snapshot();
    report.notifications_after_cleanup = notifications.snapshot();
    client?.off('notification', notifications.observe);
    Object.assign(report, owner?.diagnostics ?? { native_failure_code: null, native_owner_exit_code: null, native_close_receipt: null });
    report.process_close_observed = closeReceipt?.process_close_observed === true;
    report.cleanup_pending = owner ? owner.cleanupPending : false;
    report.passed = report.started && report.config_verified && report.chatgpt_account_present && report.thread_verified
      && report.turn_started && report.stop_receipt_verified && report.process_close_observed && !report.cleanup_pending
      && report.broker.drained && report.broker.upstream_attempts === 1 && report.broker.admitted_connections > 0
      && report.host_requests === 0 && report.code === null && (scenario === 'completed'
        ? report.terminal_status === 'completed' && report.fixed_text_observed && !report.cancellation_confirmed && report.broker.response_released
        : report.terminal_status === 'interrupted' && report.cancellation_confirmed && report.text_empty && !report.broker.response_released);
  }
  return report;
}

export async function main(argv = process.argv.slice(2)) {
  check(argv.length === 4 && ['--fixed-completed', '--fixed-interrupt'].includes(argv[0]) && path.isAbsolute(argv[3]),
    'native_probe_explicit_mode_required');
  const report = await runAuthenticatedNativeProbe({ executable: argv[1], sha256: argv[2],
    scenario: argv[0] === '--fixed-completed' ? 'completed' : 'interrupt' });
  const raw = `${JSON.stringify(report)}\n`; process.stdout.write(raw);
  writeFileSync(argv[3], raw, { flag: 'wx' }); process.exitCode = report.passed ? 0 : 2;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) await main();
