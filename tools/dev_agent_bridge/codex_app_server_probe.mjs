import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

import { CodexAppServerClient } from './codex_app_server_client.mjs';

function option(name, fallback = null) {
  const index = process.argv.indexOf(name);
  if (index < 0 || index + 1 >= process.argv.length) return fallback;
  return process.argv[index + 1];
}

function countNotifications(entries) {
  const counts = {};
  for (const entry of entries) {
    counts[entry.method] = (counts[entry.method] || 0) + 1;
  }
  return counts;
}

function markerSeen(deltas, marker) {
  return deltas.join('').includes(marker);
}

function diagnosticFor(message) {
  if (message.method === 'error') {
    return {
      method: message.method,
      message: String(message.params?.error?.message || 'unknown turn error').slice(0, 800),
      additional_details: message.params?.error?.additionalDetails == null
        ? null
        : String(message.params.error.additionalDetails).slice(0, 800),
      will_retry: message.params?.willRetry === true,
    };
  }
  if (message.method === 'warning') {
    return {
      method: message.method,
      message: String(message.params?.message || 'unknown warning').slice(0, 800),
    };
  }
  return null;
}

const cwd = path.resolve(option('--cwd', process.cwd()));
const reportPath = path.resolve(option(
  '--report',
  path.join(cwd, 'build', 'codex_app_server_phase_a_report.json'),
));
const existingThreadId = option('--thread-id');
const requestedModel = option('--model');
const archiveAtEnd = process.argv.includes('--archive');
const exerciseControl = process.argv.includes('--exercise-control');
const exerciseApproval = process.argv.includes('--exercise-approval');
const firstMarker = 'PHASE_A_OK';
const resumeMarker = 'PHASE_A_RESUME_OK';

const notifications = [];
const serverRequests = [];
const diagnostics = [];
let client = new CodexAppServerClient({ cwd });
client.on('notification', ({ message }) => {
  notifications.push(message);
  const diagnostic = diagnosticFor(message);
  if (diagnostic) diagnostics.push(diagnostic);
});
client.on('serverRequest', (request) => {
  serverRequests.push(request.method);
  request.respond({ decision: 'decline' });
});

const report = {
  schema_version: 1,
  checked_at: new Date().toISOString(),
  cwd,
  auth: null,
  models_visible: 0,
  model_ids: [],
  effective_model: null,
  model_provider: null,
  thread_id: null,
  thread_name: null,
  first_turn: null,
  restart_resume: null,
  thread_read: null,
  control: null,
  approval: null,
  notification_counts: {},
  server_request_methods: [],
  diagnostics: [],
  stderr_warning_count: 0,
  archived: false,
  passed: false,
};

try {
  await client.start();
  const account = await client.readAccount();
  report.auth = {
    type: account.account?.type || null,
    plan_type: account.account?.planType || null,
    requires_openai_auth: account.requiresOpenaiAuth === true,
  };
  if (report.auth.type !== 'chatgpt') {
    throw new Error(`Expected ChatGPT authentication, got ${report.auth.type || 'none'}.`);
  }

  const models = await client.listModels({ limit: 100 });
  report.models_visible = Array.isArray(models.data) ? models.data.length : 0;
  report.model_ids = Array.isArray(models.data)
    ? models.data.map((model) => model.id || model.model).filter(Boolean).slice(0, 20)
    : [];

  const threadConfig = {
    cwd,
    approvalPolicy: 'never',
    approvalsReviewer: 'user',
    sandbox: 'read-only',
    personality: 'pragmatic',
    ...(requestedModel ? { model: requestedModel } : {}),
  };
  const started = existingThreadId
    ? await client.resumeThread(existingThreadId, threadConfig)
    : await client.startThread({
        ...threadConfig,
        serviceName: 'here_i_am_phase_a',
        ephemeral: false,
      });
  const threadId = started.thread.id;
  const threadName = `Here I am Phase A probe ${new Date().toISOString()}`;
  report.thread_id = threadId;
  report.thread_name = threadName;
  report.effective_model = started.model || null;
  report.model_provider = started.modelProvider || null;
  await client.setThreadName(threadId, threadName);

  const firstDeltas = [];
  const firstDeltaListener = ({ message }) => {
    if (message.method === 'item/agentMessage/delta') {
      firstDeltas.push(message.params.delta || '');
    }
  };
  client.on('notification', firstDeltaListener);
  const first = await client.runTurn(
    threadId,
    `Reply with exactly ${firstMarker}. Do not call tools.`,
    {},
    { timeoutMs: 180_000 },
  );
  client.off('notification', firstDeltaListener);
  report.first_turn = {
    turn_id: first.started.turn.id,
    status: first.completed.params.turn.status,
    marker_seen: markerSeen(firstDeltas, firstMarker),
  };

  await client.stop();

  client = new CodexAppServerClient({ cwd });
  client.on('notification', ({ message }) => {
    notifications.push(message);
    const diagnostic = diagnosticFor(message);
    if (diagnostic) diagnostics.push(diagnostic);
  });
  client.on('serverRequest', (request) => {
    serverRequests.push(request.method);
    request.respond({ decision: 'decline' });
  });
  await client.start();
  const resumed = await client.resumeThread(threadId, {
    approvalPolicy: 'never',
    approvalsReviewer: 'user',
    sandbox: 'read-only',
  });
  const resumeDeltas = [];
  const resumeDeltaListener = ({ message }) => {
    if (message.method === 'item/agentMessage/delta') {
      resumeDeltas.push(message.params.delta || '');
    }
  };
  client.on('notification', resumeDeltaListener);
  const second = await client.runTurn(
    threadId,
    `Reply with exactly ${resumeMarker}. Do not call tools.`,
    {},
    { timeoutMs: 180_000 },
  );
  client.off('notification', resumeDeltaListener);
  report.restart_resume = {
    resumed_thread_id: resumed.thread.id,
    turn_id: second.started.turn.id,
    status: second.completed.params.turn.status,
    marker_seen: markerSeen(resumeDeltas, resumeMarker),
  };

  const read = await client.readThread(threadId, { includeTurns: true });
  report.thread_read = {
    id_matches: read.thread.id === threadId,
    turn_count: Array.isArray(read.thread.turns) ? read.thread.turns.length : null,
  };

  if (exerciseControl) {
    const controlThread = await client.startThread({
      ...threadConfig,
      serviceName: 'here_i_am_phase_a_control',
      ephemeral: true,
    });
    const controlThreadId = controlThread.thread.id;
    const afterSequence = client.notificationSequence;
    const controlTurn = await client.startTurn(
      controlThreadId,
      'Write 500 numbered one-sentence observations. Do not call tools.',
    );
    const controlTurnId = controlTurn.turn.id;
    await client.waitForNotification(
      'item/agentMessage/delta',
      (message) => message.params?.threadId === controlThreadId &&
        message.params?.turnId === controlTurnId,
      { afterSequence, timeoutMs: 180_000 },
    );
    const steered = await client.steerTurn(
      controlThreadId,
      controlTurnId,
      'Change direction: stop the list and reply with one short sentence only.',
    );
    await client.interruptTurn(controlThreadId, controlTurnId);
    const interrupted = await client.waitForNotification(
      'turn/completed',
      (message) => message.params?.threadId === controlThreadId &&
        message.params?.turn?.id === controlTurnId,
      { afterSequence, timeoutMs: 60_000 },
    );
    report.control = {
      ephemeral: controlThread.thread.ephemeral === true,
      steer_accepted: steered.turnId === controlTurnId,
      final_status: interrupted.params.turn.status,
    };
  }

  if (exerciseApproval) {
    const approvalDir = path.join(cwd, 'build', 'codex_app_server_phase_a_approval_probe');
    mkdirSync(approvalDir, { recursive: true });
    const probeFile = path.join(approvalDir, 'approval_probe.txt');
    const requestOffset = serverRequests.length;
    const approvalThread = await client.startThread({
      cwd: approvalDir,
      approvalPolicy: 'on-request',
      approvalsReviewer: 'user',
      sandbox: 'read-only',
      personality: 'pragmatic',
      ...(requestedModel ? { model: requestedModel } : {}),
      serviceName: 'here_i_am_phase_a_approval',
      ephemeral: true,
    });
    const approvalTurn = await client.runTurn(
      approvalThread.thread.id,
      'Run exactly one PowerShell command that writes PHASE_A to approval_probe.txt in the current directory. If approval is declined, do not retry and reply briefly.',
      {},
      { timeoutMs: 180_000 },
    );
    report.approval = {
      ephemeral: approvalThread.thread.ephemeral === true,
      request_methods: [...new Set(serverRequests.slice(requestOffset))],
      final_status: approvalTurn.completed.params.turn.status,
      write_blocked: !existsSync(probeFile),
    };
  }

  if (archiveAtEnd) {
    await client.archiveThread(threadId);
    report.archived = true;
  }

  report.notification_counts = countNotifications(notifications);
  report.server_request_methods = [...new Set(serverRequests)];
  report.diagnostics = diagnostics;
  report.stderr_warning_count = client.stderrLines.length;
  report.passed = Boolean(
    report.first_turn.marker_seen &&
    report.restart_resume.marker_seen &&
    report.restart_resume.resumed_thread_id === threadId &&
    report.thread_read.id_matches &&
    (!exerciseControl || (
      report.control?.ephemeral &&
      report.control?.steer_accepted &&
      report.control?.final_status === 'interrupted'
    )) &&
    (!exerciseApproval || (
      report.approval?.ephemeral &&
      report.approval?.request_methods.length > 0 &&
      report.approval?.write_blocked
    ))
  );
} catch (error) {
  report.error = error instanceof Error ? error.message : String(error);
} finally {
  await client.stop().catch(() => {});
  writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
}

if (!report.passed) process.exitCode = 1;
