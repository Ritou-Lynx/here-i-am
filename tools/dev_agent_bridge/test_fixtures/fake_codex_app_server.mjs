import readline from 'node:readline';
import { appendFileSync, writeFileSync } from 'node:fs';

const threads = new Map();
const pendingApprovals = new Map();
const pendingToolCalls = new Map();
let nextThread = 1;
let nextTurn = 1;

function send(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

function result(id, payload) {
  send({ id, result: payload });
}

function fail(id, code, message) {
  send({ id, error: { code, message } });
}

function threadResult(thread) {
  return {
    thread: { ...thread },
    model: 'fake-model',
    modelProvider: 'fake-provider',
    cwd: process.cwd(),
    approvalPolicy: 'never',
    approvalsReviewer: 'user',
    sandbox: { type: 'readOnly' },
    instructionSources: [],
  };
}

function completeTurn(threadId, turn, status = 'completed') {
  turn.status = status;
  send({
    method: 'turn/completed',
    params: { threadId, turn: { ...turn } },
  });
}

function handleRequest(message) {
  const { id, method, params = {} } = message;
  if (method === 'initialized') return;
  if (method === 'test/hang') return;
  if (method === 'test/exit') {
    result(id, {});
    setTimeout(() => process.exit(23), 10);
    return;
  }
  if (method === 'initialize') {
    result(id, { userAgent: 'fake-codex-app-server/1.0' });
    return;
  }
  if (method === 'account/read') {
    result(id, {
      account: { type: 'chatgpt', email: 'hidden@example.invalid', planType: 'pro' },
      requiresOpenaiAuth: true,
    });
    return;
  }
  if (method === 'model/list') {
    result(id, { data: [{ id: 'fake-model', displayName: 'Fake Model' }] });
    return;
  }
  if (method === 'thread/start') {
    const thread = {
      id: `fake-thread-${nextThread++}`,
      sessionId: null,
      name: null,
      preview: '',
      status: { type: 'idle' },
      turns: [],
      ephemeral: params.ephemeral === true,
      dynamicTools: params.dynamicTools || [],
    };
    thread.sessionId = thread.id;
    threads.set(thread.id, thread);
    result(id, threadResult(thread));
    send({ method: 'thread/started', params: { thread: { ...thread } } });
    return;
  }
  if (method === 'thread/resume') {
    const thread = threads.get(params.threadId) || {
      id: params.threadId,
      sessionId: params.threadId,
      name: null,
      preview: '',
      status: { type: 'idle' },
      turns: [],
      ephemeral: false,
    };
    threads.set(thread.id, thread);
    result(id, threadResult(thread));
    return;
  }
  if (method === 'thread/fork') {
    const source = threads.get(params.threadId);
    if (!source) return fail(id, -32_001, 'thread not found');
    const thread = {
      ...source,
      id: `fake-thread-${nextThread++}`,
      sessionId: source.sessionId,
      turns: [...source.turns],
    };
    threads.set(thread.id, thread);
    result(id, threadResult(thread));
    return;
  }
  if (method === 'thread/read') {
    const thread = threads.get(params.threadId);
    if (!thread) return fail(id, -32_001, 'thread not found');
    result(id, { thread: { ...thread } });
    return;
  }
  if (method === 'thread/list') {
    result(id, { data: Array.from(threads.values()), nextCursor: null });
    return;
  }
  if (method === 'thread/name/set') {
    const thread = threads.get(params.threadId);
    if (!thread) return fail(id, -32_001, 'thread not found');
    thread.name = params.name;
    result(id, {});
    send({
      method: 'thread/name/updated',
      params: { threadId: thread.id, name: thread.name },
    });
    return;
  }
  if (method === 'thread/archive') {
    const thread = threads.get(params.threadId);
    if (!thread) return fail(id, -32_001, 'thread not found');
    thread.archived = true;
    result(id, {});
    return;
  }
  if (method === 'turn/start') {
    const thread = threads.get(params.threadId);
    if (!thread) return fail(id, -32_001, 'thread not found');
    const text = params.input?.find((item) => item.type === 'text')?.text || '';
    const turn = {
      id: `fake-turn-${nextTurn++}`,
      status: 'inProgress',
      items: [],
      activityObserved: false,
    };
    thread.turns.push(turn);
    if (text.includes('complete-before-response')) {
      send({ method: 'turn/started', params: { threadId: thread.id, turn: { ...turn } } });
      completeTurn(thread.id, turn);
      result(id, { turn: { ...turn } });
      return;
    }
    result(id, { turn: { ...turn } });
    send({ method: 'turn/started', params: { threadId: thread.id, turn: { ...turn } } });
    if (text.includes('approval')) {
      const requestId = `approval-${turn.id}`;
      pendingApprovals.set(requestId, { threadId: thread.id, turn });
      send({
        id: requestId,
        method: 'item/commandExecution/requestApproval',
        params: {
          threadId: thread.id,
          turnId: turn.id,
          itemId: `item-${turn.id}`,
          command: 'fake-command',
          cwd: process.cwd(),
        },
      });
      return;
    }
    if (text.includes('dynamic-tool')) {
      const tool = thread.dynamicTools[0];
      if (!tool) return completeTurn(thread.id, turn, 'failed');
      const requestId = `tool-request-${turn.id}`;
      const callId = `tool-call-${turn.id}`;
      pendingToolCalls.set(requestId, {
        threadId: thread.id,
        turn,
        callId,
        tool,
      });
      send({
        method: 'item/started',
        params: {
          threadId: thread.id,
          turnId: turn.id,
          item: {
            id: `item-${turn.id}`,
            type: 'dynamicToolCall',
            tool: tool.name,
            arguments: { selected_item_ids: ['item-1', 'item-2'] },
            status: 'inProgress',
          },
        },
      });
      send({
        id: requestId,
        method: 'item/tool/call',
        params: {
          threadId: thread.id,
          turnId: turn.id,
          itemId: `item-${turn.id}`,
          callId,
          tool: tool.name,
          arguments: { selected_item_ids: ['item-1', 'item-2'] },
        },
      });
      return;
    }
    const delay = text.includes('slow') ? 50 : 5;
    setTimeout(() => {
      if (turn.status !== 'inProgress') return;
      turn.activityObserved = true;
      send({
        method: 'item/agentMessage/delta',
        params: {
          threadId: thread.id,
          turnId: turn.id,
          itemId: `message-${turn.id}`,
          delta: 'FAKE_OK',
        },
      });
      if (text.includes('slow')) {
        setTimeout(() => {
          if (turn.status === 'inProgress') completeTurn(thread.id, turn);
        }, 500);
      } else {
        completeTurn(thread.id, turn);
      }
    }, delay);
    return;
  }
  if (method === 'turn/steer') {
    const thread = threads.get(params.threadId);
    const turn = thread?.turns.find((item) => item.id === params.expectedTurnId);
    if (!turn?.activityObserved) return fail(id, -32_000, 'turn not active yet');
    result(id, { turnId: params.expectedTurnId });
    return;
  }
  if (method === 'turn/interrupt') {
    const thread = threads.get(params.threadId);
    const turn = thread?.turns.find((item) => item.id === params.turnId);
    if (!turn) return fail(id, -32_001, 'turn not found');
    result(id, {});
    if (turn.status !== 'inProgress') return;
    completeTurn(thread.id, turn, 'interrupted');
    return;
  }

  if (Object.hasOwn(message, 'result') && pendingApprovals.has(id)) {
    const pending = pendingApprovals.get(id);
    pendingApprovals.delete(id);
    completeTurn(pending.threadId, pending.turn, 'declined');
    return;
  }
  if (Object.hasOwn(message, 'result') && pendingToolCalls.has(id)) {
    const pending = pendingToolCalls.get(id);
    pendingToolCalls.delete(id);
    send({
      method: 'item/completed',
      params: {
        threadId: pending.threadId,
        turnId: pending.turn.id,
        item: {
          id: `item-${pending.turn.id}`,
          type: 'dynamicToolCall',
          tool: pending.tool.name,
          arguments: { selected_item_ids: ['item-1', 'item-2'] },
          status: message.result.success ? 'completed' : 'failed',
          contentItems: message.result.contentItems,
          success: message.result.success,
        },
      },
    });
    completeTurn(
      pending.threadId,
      pending.turn,
      message.result.success ? 'completed' : 'failed',
    );
    return;
  }
  fail(id, -32_601, `unsupported method: ${method}`);
}

const reader = readline.createInterface({ input: process.stdin });
reader.on('close', () => {
  if (process.env.FAKE_CODEX_EXIT_MARKER) {
    writeFileSync(process.env.FAKE_CODEX_EXIT_MARKER, 'stdin_closed\n', 'utf8');
  }
});
process.on('exit', () => {
  if (process.env.FAKE_CODEX_EXIT_MARKER) {
    appendFileSync(process.env.FAKE_CODEX_EXIT_MARKER, 'process_exit\n', 'utf8');
  }
});
reader.on('line', (line) => {
  if (!line.trim()) return;
  const message = JSON.parse(line);
  if (!message.method && Object.hasOwn(message, 'id')) {
    handleRequest(message);
    return;
  }
  handleRequest(message);
});
