import http from 'node:http';
import https from 'node:https';
import { spawn, spawnSync } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { randomUUID } from 'node:crypto';
import { homedir } from 'node:os';
import path from 'node:path';
import { URL } from 'node:url';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createIActivityStore } from '../i_continuity_gateway/i_activity_store.mjs';
import { loadProjectRegistry } from '../i_continuity_gateway/i_project_registry.mjs';
import { persistDevRoomCloseout } from './project_memory_closeout.mjs';

const host = process.env.DEV_AGENT_BRIDGE_HOST || '127.0.0.1';
const port = Number(process.env.DEV_AGENT_BRIDGE_PORT || 47831);
const certPath = process.env.DEV_AGENT_BRIDGE_CERT;
const keyPath = process.env.DEV_AGENT_BRIDGE_KEY;
const codexModel = process.env.DEV_AGENT_CODEX_MODEL;
const scriptDir = dirname(fileURLToPath(import.meta.url));
const statePath = process.env.DEV_AGENT_BRIDGE_STATE ||
  join(scriptDir, '.state', 'runs.json');
const runs = new Map();
const iHome = process.env.I_HOME || join(homedir(), '.i');

const terminalStatuses = new Set(['done', 'failed', 'aborted']);

function nowSeconds() {
  return Math.floor(Date.now() / 1000);
}

function json(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
  });
  res.end(body);
}

function notFound(res) {
  json(res, 404, { error: 'not_found' });
}

function serializeRun(run) {
  return {
    id: run.id,
    sessionId: run.sessionId,
    agentType: run.agentType,
    project: run.project,
    status: run.status,
    summary: run.summary,
    startedAt: run.startedAt,
    endedAt: run.endedAt,
    lastSeq: run.lastSeq,
    events: run.events,
    artifacts: Array.from(run.artifacts.values()),
    transcript: run.transcript,
  };
}

function persistState() {
  mkdirSync(dirname(statePath), { recursive: true });
  writeFileSync(
    statePath,
    JSON.stringify({ runs: Array.from(runs.values()).map(serializeRun) }, null, 2),
  );
}

function loadState() {
  if (!existsSync(statePath)) return;
  const raw = JSON.parse(readFileSync(statePath, 'utf8'));
  if (!raw || !Array.isArray(raw.runs)) return;
  for (const saved of raw.runs) {
    const run = {
      id: String(saved.id),
      sessionId: String(saved.sessionId || saved.id),
      agentType: String(saved.agentType || ''),
      project: saved.project || {},
      status: String(saved.status || 'failed'),
      summary: saved.summary ?? null,
      startedAt: Number(saved.startedAt || nowSeconds()),
      endedAt: saved.endedAt == null ? null : Number(saved.endedAt),
      lastSeq: Number(saved.lastSeq || 0),
      events: Array.isArray(saved.events) ? saved.events : [],
      artifacts: new Map(
        Array.isArray(saved.artifacts)
          ? saved.artifacts.map((artifact) => [String(artifact.id), artifact])
          : [],
      ),
      transcript: Array.isArray(saved.transcript) ? saved.transcript : [],
      child: null,
    };
    runs.set(run.id, run);
    if (!terminalStatuses.has(run.status)) {
      setStatus(run, 'failed', 'Bridge restarted; the local agent process cannot be resumed.');
    }
  }
}

async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  if (chunks.length === 0) return {};
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

function addEvent(run, kind, payload) {
  const event = {
    seq: ++run.lastSeq,
    ts: nowSeconds(),
    kind,
    payload,
  };
  run.events.push(event);
  persistState();
  return event;
}

function setStatus(run, status, summary = null) {
  if (terminalStatuses.has(run.status)) return;
  run.status = status;
  if (summary) run.summary = summary;
  if (terminalStatuses.has(status)) run.endedAt = nowSeconds();
  addEvent(run, 'status', {
    status,
    ...(summary ? { summary } : {}),
  });
}

function validateProject(project) {
  if (!project || typeof project !== 'object') {
    throw new Error('project is required');
  }
  const rootPath = String(project.root_path || '').trim();
  if (!rootPath) throw new Error('project.root_path is required');
  if (!existsSync(rootPath) || !statSync(rootPath).isDirectory()) {
    throw new Error(`project.root_path does not exist: ${rootPath}`);
  }
  return {
    id: String(project.id || ''),
    name: String(project.name || 'Project'),
    rootPath,
    defaultBranch: String(project.default_branch || 'main'),
    permissionTier: String(project.permission_tier || 'read_only'),
  };
}

function splitLines(buffer, chunk, onLine) {
  buffer.value += chunk.toString('utf8');
  const lines = buffer.value.split(/\r?\n/);
  buffer.value = lines.pop() || '';
  for (const line of lines) {
    if (line.trim()) onLine(line);
  }
}

function flushLine(buffer, onLine) {
  if (!buffer.value.trim()) return;
  onLine(buffer.value);
  buffer.value = '';
}

function findText(value, depth = 0) {
  if (depth > 5 || value == null) return null;
  if (typeof value === 'string') return value;
  if (Array.isArray(value)) {
    const parts = value
      .map((item) => {
        if (item && typeof item === 'object' && item.type && item.type !== 'text') {
          return null;
        }
        return findText(item, depth + 1);
      })
      .filter(Boolean);
    return parts.length ? parts.join('\n') : null;
  }
  if (typeof value === 'object') {
    for (const key of ['text', 'message', 'delta', 'content', 'summary', 'result', 'item']) {
      const found = findText(value[key], depth + 1);
      if (found) return found;
    }
  }
  return null;
}

function normalizeJsonLine(run, rawLine) {
  let parsed;
  try {
    parsed = JSON.parse(rawLine);
  } catch (_) {
    addEvent(run, 'text', { text: rawLine, role: 'assistant' });
    run.transcript.push(rawLine);
    return;
  }

  // OpenCode emits flat top-level events (text/tool_use/step_start/...) with
  // a `part` payload hanging off the event root. The Claude/Codex stream
  // shapes are different enough that sharing one parser mangles both. Route
  // OpenCode runs through a dedicated normalizer.
  if (run.agentType === 'opencode') {
    normalizeOpencodeEvent(run, parsed);
    return;
  }

  const type = String(parsed.type || parsed.event || 'event');
  if (type === 'system' && parsed.subtype === 'thinking_tokens') return;

  if (type.includes('error') || parsed.error) {
    const message = findText(parsed.error) || findText(parsed) || rawLine;
    addEvent(run, 'error', { message, raw: parsed });
    run.transcript.push(message);
    return;
  }

  if (type.includes('tool') || type.includes('command')) {
    addEvent(run, 'tool_call', {
      name: String(parsed.name || parsed.tool || type),
      description: findText(parsed) || type,
      risk: 'low',
      raw: parsed,
    });
    return;
  }

  if (type.endsWith('.started') || type === 'system') {
    addEvent(run, 'status', {
      status: run.status,
      message: type,
    });
    return;
  }

  const text = findText(parsed);
  if (text) {
    if (run.transcript[run.transcript.length - 1] === text) return;
    addEvent(run, 'text', { text, role: 'assistant', raw_type: type });
    run.transcript.push(text);
    run.summary = text;
    return;
  }

  addEvent(run, 'status', { status: run.status, message: type });
}

// ---------------------------------------------------------------------------
// OpenCode event normalization
// ---------------------------------------------------------------------------
//
// OpenCode's CLI emits newline-delimited JSON where the top-level `type` is
// the semantic event kind (step_start / text / tool_use / step_finish /
// permission / session.* / file.edited / error). The payload lives in a
// top-level `part` object (NOT under `properties` — the SDK spec wraps it,
// but the CLI stream is flat). See sample-runs saved in the tools/dev_agent_bridge
// directory; schema reference: https://github.com/anomalyco/opencode/blob/dev/
// packages/sdk/js/src/gen/types.gen.ts.
//
// We translate into the Bridge's normalized event kinds:
//
//   text          -> text        (assistant output the chat-native flow
//                                concatenates into the user-visible reply)
//   tool_use      -> tool_call + tool_result (OpenCode's tool events always
//                                arrive `status=completed` so we collapse
//                                pending/running/completed into one event)
//   tool_use(edit) + metadata.filediff -> file_change (per edited file)
//   step_start    -> status      (activity indicator; no UI payload)
//   step_finish    -> (ignored)   (internal model-loop bookkeeping)
//   permission    -> approval_request (mobile-side Approve/Deny flow)
//   file.edited   -> file_change
//   session.error -> error
//
// Reasoning, snapshot, subtask, retry, compaction, pty.*, lsp.*,
// installation.*, tui.*, server.* events are not user-visible progress; we
// ignore them.

function normalizeOpencodeEvent(run, raw) {
  const type = String(raw.type || '');
  const part = raw.part && typeof raw.part === 'object' ? raw.part : null;

  // Assistant text output. The CLI delivers one `text` event per turn
  // (already the full snippet, not a streaming delta), so we just push it.
  if (type === 'text') {
    const text = String(part?.text || '');
    if (!text) return;
    if (run.transcript[run.transcript.length - 1] === text) return;
    addEvent(run, 'text', { text, role: 'assistant' });
    run.transcript.push(text);
    run.summary = text;
    return;
  }

  // Tool invocation. OpenCode's `tool_use` event always arrives with
  // `state.status === 'completed'` (no separate pending/running stream),
  // so we emit a tool_call followed by tool_result on the same event.
  // For `edit` tool calls we also emit a file_change per file diff in
  // `state.metadata.filediff`.
  if (type === 'tool_use' && part) {
    const state = part.state && typeof part.state === 'object' ? part.state : null;
    const toolName = String(part.tool || 'tool');
    const title = String(state?.title || toolName);
    const status = String(state?.status || 'completed');
    const input = state && state.input && typeof state.input === 'object'
      ? state.input
      : null;
    const filePathFromInput = typeof input?.filePath === 'string'
      ? input.filePath
      : null;

    // tool_call marks that a tool started — the chat-native card shows
    // a per-tool chip and keeps the spinner going.
    addEvent(run, 'tool_call', {
      name: toolName,
      description: title,
      target: filePathFromInput,
      risk: _riskForOpencodeTool(toolName),
      raw: part,
    });

    // tool_result: status=completed → success, status=error → failure.
    // OpenCode collapses pending/running into the completed event, so we
    // always emit tool_result in the same line.
    if (status === 'completed') {
      const outputSummary =
        typeof state?.output === 'string' && state.output.length > 0
          ? state.output.split('\n').first.slice(0, 240)
          : title;
      addEvent(run, 'tool_result', {
        name: toolName,
        ok: true,
        summary: outputSummary,
        target: filePathFromInput,
        raw: part,
      });
      // Edit invocations may carry a per-file diff in state.metadata.
      // Emit a file_change event per entry so the chat-native card can
      // render per-file chips.
      const filediff =
        state?.metadata?.filediff && typeof state.metadata.filediff === 'object'
          ? state.metadata.filediff
          : null;
      if (filediff && typeof filediff.file === 'string') {
        addEvent(run, 'file_change', {
          path: String(filediff.file),
          change: 'modified',
          lines_added: Number(filediff.additions || 0),
          lines_removed: Number(filediff.deletions || 0),
          raw: filediff,
        });
      }
      return;
    }

    if (status === 'error') {
      addEvent(run, 'tool_result', {
        name: toolName,
        ok: false,
        summary: String(state?.error || 'tool error'),
        target: filePathFromInput,
        raw: part,
      });
      return;
    }

    // pending / running — RC for future OpenCode builds; emit a tool_call
    // and let the follow-up completion event close the loop.
    return;
  }

  // step boundaries. step_start is a useful "I'm working" heartbeat for
  // the chat-native card; step_finish is internal model-loop telemetry
  // (token counts, reason="tool-calls"/"stop") so we ignore it.
  if (type === 'step_start') {
    addEvent(run, 'status', {
      status: run.status,
      message: 'opencode.step.start',
    });
    return;
  }

  if (type === 'step_finish') {
    return;
  }

  if (type === 'permission') {
    const id = String(part?.id || raw.id || '');
    const title = String(part?.title || 'Permission requested');
    const kind = String(part?.type || part?.metadata?.type || 'command');
    addEvent(run, 'approval_request', {
      approval_id: id,
      kind,
      title,
      reason: '',
      risk: 'medium',
      raw,
    });
    return;
  }

  if (type === 'file.edited') {
    addEvent(run, 'file_change', {
      path: String(part?.file || raw.file || ''),
      change: 'modified',
      raw,
    });
    return;
  }

  if (type === 'session.error' || type === 'error') {
    const message =
      findText(raw.error || part?.error || raw) || 'session error';
    addEvent(run, 'error', { message, raw });
    run.transcript.push(message);
    return;
  }

  // Everything else (session.created / session.idle / session.status /
  // message.updated / etc.) is not user-visible progress; ignore so we
  // don't spam the chat-native card with no-op events.
}

function _riskForOpencodeTool(name) {
  switch (name) {
    case 'edit':
    case 'write':
    case 'rm':
    case 'bash':
      return 'medium';
    default:
      return 'low';
  }
}

function commandFor(agentType, project, prompt, mode, cwd) {
  const isWrite = mode === 'workspace_write';

  if (agentType === 'codex') {
    const args = [
      'exec',
      '--json',
      '--sandbox',
      isWrite ? 'workspace-write' : 'read-only',
      '--skip-git-repo-check',
      '--cd',
      cwd,
    ];
    if (isWrite) {
      // Codex 0.141 removed the --ask-for-approval CLI flag; approval policy
      // is now only configurable via config file or -c override. Without
      // approval=never, sandbox=workspace-write still pops user approval on
      // every write, and in --json (non-interactive) mode that auto-rejects.
      args.push('-c', 'approval_policy="never"');
    }
    if (codexModel) args.push('-m', codexModel);
    args.push(prompt);
    return commandSpec('codex', args, 'Codex');
  }

  if (agentType === 'claude_code') {
    const tools = isWrite
      ? 'Read,Grep,Glob,LS,Edit,Write,MultiEdit'
      : 'Read,Grep,Glob,LS';
    return commandSpec(
      'claude',
      [
        '-p',
        prompt,
        '--output-format',
        'stream-json',
        '--verbose',
        '--permission-mode',
        isWrite ? 'acceptEdits' : 'plan',
        '--tools',
        tools,
      ],
      'Claude Code',
    );
  }

  if (agentType === 'opencode') {
    // OpenCode CLI: `opencode run --format json <prompt>` streams
    // newline-delimited JSON events (SDK types.gen.ts Event union). It
    // shares ~/.config/opencode and ~/.local/share/opencode with the
    // Desktop app, so provider credentials configured there are reused.
    //
    // Permission control: OpenCode has no CLI flag for inline
    // approval/deny. Instead, either pass `--auto` (auto-approve
    // non-denied permissions — fine for read_only) or rely on a
    // pre-configured agent in opencode.jsonc with `permission.edit:
    // 'allow'` for workspace_write. For now we use --auto for both
    // modes; the App's Accept/Discard flow operates at the git-worktree
    // level post-run, not at the OpenCode tool level.
    const ocModel = process.env.DEV_AGENT_OPENCODE_MODEL;
    const args = [
      'run',
      '--format',
      'json',
      '--auto',
      '--dir',
      cwd,
    ];
    if (ocModel) args.push('-m', ocModel);
    args.push(prompt);
    return commandSpec('opencode', args, 'OpenCode');
  }

  throw new Error(`Unsupported agent_type: ${agentType}`);
}

// ---------------------------------------------------------------------------
// Git / worktree helpers
// ---------------------------------------------------------------------------

function runGit(cwd, args, { allowFail = false } = {}) {
  const result = spawnSync('git', args, {
    cwd,
    encoding: 'utf8',
    windowsHide: true,
  });
  if (result.error) {
    if (allowFail) return result;
    throw new Error(`git ${args.join(' ')} failed to spawn: ${result.error.message}`);
  }
  if (!allowFail && result.status !== 0) {
    const stderr = (result.stderr || '').trim();
    const stdout = (result.stdout || '').trim();
    throw new Error(
      `git ${args.join(' ')} exited ${result.status}: ${stderr || stdout || 'unknown error'}`,
    );
  }
  return result;
}

function ensureGitRepo(rootPath) {
  const result = runGit(rootPath, ['rev-parse', '--git-dir'], { allowFail: true });
  if (result.status !== 0) {
    throw new Error(`project root is not a git repository: ${rootPath}`);
  }
}

function shortRunId(runId) {
  return String(runId).replace(/-/g, '').slice(0, 8);
}

function findProject(projectId) {
  for (const run of runs.values()) {
    if (run.project?.id === projectId) return run.project;
  }
  return null;
}

function projectFromQuery(url, projectId) {
  const rootPath = String(url.searchParams.get('root_path') || '').trim();
  if (!rootPath) return null;
  return validateProject({
    id: projectId,
    name: url.searchParams.get('name') || 'Dev Project',
    root_path: rootPath,
    default_branch: url.searchParams.get('default_branch') || 'main',
    permission_tier: url.searchParams.get('permission_tier') || 'read_only',
  });
}

function getCommitList(cwd, range) {
  if (!range || range === '..') return [];
  const result = runGit(cwd, ['log', '--format=%H %s', range], { allowFail: true });
  if (result.status !== 0) return [];
  return (result.stdout || '').trim().split('\n').filter(Boolean).map((line) => {
    const space = line.indexOf(' ');
    return {
      hash: space > 0 ? line.slice(0, space) : line,
      message: space > 0 ? line.slice(space + 1) : '',
    };
  });
}

function createWorktree(project, runId) {
  ensureGitRepo(project.rootPath);
  const short = shortRunId(runId);
  const relPath = path.join('.dev-agent', 'worktrees', short);
  const absPath = path.join(project.rootPath, relPath);
  const branch = `dev-agent/${short}`;

  // Make sure parent dir exists; git will create the leaf.
  mkdirSync(path.dirname(absPath), { recursive: true });

  // If a stale worktree at this path exists, prune first.
  if (existsSync(absPath)) {
    runGit(project.rootPath, ['worktree', 'remove', '--force', relPath], {
      allowFail: true,
    });
  }
  runGit(project.rootPath, ['branch', '-D', branch], { allowFail: true });

  runGit(project.rootPath, [
    'worktree', 'add', '-b', branch, relPath, project.defaultBranch,
  ]);
  return { worktreePath: absPath, branch };
}

function autoCommitWorktree(run, project) {
  if (!run.worktreePath || !run.branch) return { committed: false };
  // Stage everything the agent touched (new, modified, deleted).
  runGit(run.worktreePath, ['add', '-A'], { allowFail: true });
  // If there is nothing staged, --cached --quiet exits 0; we skip commit.
  const dirty = runGit(run.worktreePath, ['diff', '--cached', '--quiet'], {
    allowFail: true,
  });
  if (dirty.status === 0) return { committed: false };

  const shortId = shortRunId(run.id);
  const summary = (run.summary || '').replace(/\s+/g, ' ').slice(0, 80);
  const message = summary
    ? `dev-agent ${shortId}: ${summary}`
    : `dev-agent run ${shortId}`;
  const commit = runGit(
    run.worktreePath,
    ['commit', '-m', message, '--author=Dev Agent <dev-agent@local>'],
    { allowFail: true },
  );
  if (commit.status !== 0) {
    addEvent(run, 'error', {
      message: `auto-commit failed: ${(commit.stderr || '').trim()}`,
    });
    return { committed: false };
  }
  addEvent(run, 'tool_call', {
    name: 'git commit',
    description: `Auto-committed agent changes to ${run.branch}.`,
    risk: 'low',
  });
  return { committed: true };
}

function generateDiffArtifact(run, project) {
  if (!run.worktreePath || !run.branch) return;
  const result = runGit(project.rootPath, [
    'diff', '--no-color', `${project.defaultBranch}...${run.branch}`,
  ], { allowFail: true });
  if (result.status !== 0) return;
  const diff = (result.stdout || '').trim();
  if (!diff) return;
  run.artifacts.set('diff-final', {
    id: 'diff-final',
    kind: 'diff',
    title: `Diff vs ${project.defaultBranch}`,
    content: diff,
    created_at: nowSeconds(),
  });
}

function cleanupWorktree(run, project) {
  if (!run.worktreePath || !run.branch) return { ok: true };
  const relPath = path.relative(project.rootPath, run.worktreePath);
  const removeResult = runGit(
    project.rootPath,
    ['worktree', 'remove', '--force', relPath],
    { allowFail: true },
  );
  // Delete the branch even if worktree-remove had nothing to do.
  runGit(project.rootPath, ['branch', '-D', run.branch], { allowFail: true });
  return {
    ok: removeResult.status === 0 || !existsSync(run.worktreePath),
    message: (removeResult.stderr || '').trim() || null,
  };
}

function applyWorktree(run, project) {
  if (!run.worktreePath || !run.branch) {
    return { ok: false, reason: 'no_worktree' };
  }
  // Make sure the default branch is checked out and the merge will be ff-only.
  const checkout = runGit(
    project.rootPath,
    ['checkout', project.defaultBranch],
    { allowFail: true },
  );
  if (checkout.status !== 0) {
    return {
      ok: false,
      reason: 'checkout_failed',
      message: (checkout.stderr || '').trim(),
    };
  }
  const merge = runGit(
    project.rootPath,
    ['merge', '--ff-only', run.branch],
    { allowFail: true },
  );
  if (merge.status !== 0) {
    return {
      ok: false,
      reason: 'merge_not_fast_forward',
      message: (merge.stderr || '').trim() ||
        'Default branch has moved on; cannot fast-forward.',
    };
  }
  // Merge succeeded — safe to clean up worktree and branch.
  cleanupWorktree(run, project);
  return { ok: true };
}

function commandSpec(name, args, displayName) {
  if (process.platform !== 'win32') {
    return { command: name, args, displayName };
  }

  const npmRoot = process.env.APPDATA
    ? `${process.env.APPDATA}\\npm\\node_modules`
    : null;
  if (name === 'claude' && npmRoot) {
    const claudeExe = `${npmRoot}\\@anthropic-ai\\claude-code\\bin\\claude.exe`;
    if (existsSync(claudeExe)) return { command: claudeExe, args, displayName };
  }
  if (name === 'codex' && npmRoot) {
    const codexJs = `${npmRoot}\\@openai\\codex\\bin\\codex.js`;
    if (existsSync(codexJs)) {
      return { command: 'node', args: [codexJs, ...args], displayName };
    }
  }
  return { command: name, args, displayName };
}

function startProcess(run, agentType, project, prompt, mode) {
  // For write mode we need a worktree before launching the agent so any file
  // changes are isolated. Read-only runs execute directly in the project root.
  let cwd = project.rootPath;
  if (mode === 'workspace_write') {
    try {
      const { worktreePath, branch } = createWorktree(project, run.id);
      run.worktreePath = worktreePath;
      run.branch = branch;
      cwd = worktreePath;
      addEvent(run, 'tool_call', {
        name: 'git worktree add',
        description: `Created isolated worktree ${branch} at ${path.relative(project.rootPath, worktreePath)}`,
        risk: 'low',
      });
    } catch (error) {
      setStatus(run, 'failed', `worktree setup failed: ${error.message}`);
      return;
    }
  }

  let spec;
  try {
    spec = commandFor(agentType, project, prompt, mode, cwd);
  } catch (error) {
    setStatus(run, 'failed', error.message);
    return;
  }

  addEvent(run, 'tool_call', {
    name: spec.displayName || spec.command,
    description: `Start ${spec.displayName || spec.command} ${mode} run.`,
    risk: mode === 'workspace_write' ? 'medium' : 'low',
  });

  const child = spawn(spec.command, spec.args, {
    cwd,
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  });
  run.child = child;
  setStatus(run, 'running');

  const stdoutBuffer = { value: '' };
  const stderrBuffer = { value: '' };

  child.stdout.on('data', (chunk) => {
    splitLines(stdoutBuffer, chunk, (line) => normalizeJsonLine(run, line));
  });

  child.stderr.on('data', (chunk) => {
    splitLines(stderrBuffer, chunk, (line) => {
      addEvent(run, 'error', { message: line, stream: 'stderr' });
    });
  });

  child.on('error', (error) => {
    setStatus(run, 'failed', error.message);
  });

  child.on('close', (code, signal) => {
    flushLine(stdoutBuffer, (line) => normalizeJsonLine(run, line));
    flushLine(stderrBuffer, (line) => {
      addEvent(run, 'error', { message: line, stream: 'stderr' });
    });
    run.child = null;
    if (run.status === 'aborted') return;
    if (code === 0) {
      setStatus(run, 'done', run.summary || 'Run completed.');
    } else {
      setStatus(run, 'failed', `Process exited with code ${code ?? 'unknown'}${signal ? ` (${signal})` : ''}.`);
    }
    if (run.transcript.length) {
      run.artifacts.set('transcript', {
        id: 'transcript',
        kind: 'review',
        title: 'Run transcript',
        content: run.transcript.join('\n\n'),
        created_at: nowSeconds(),
      });
      persistState();
    }
    // Write-mode runs: auto-commit whatever the agent left in the worktree, then
    // produce a diff artifact comparing the dev branch to default. Without the
    // auto-commit, apply (git merge --ff-only) would have nothing to merge.
    if (run.mode === 'workspace_write' && run.status === 'done') {
      try {
        autoCommitWorktree(run, run.project);
        generateDiffArtifact(run, run.project);
      } catch (err) {
        addEvent(run, 'error', { message: `post-run finalize failed: ${err.message}` });
      }
    }
    if (run.status === 'done') {
      try {
        const closeout = persistDevRoomCloseout({ run, iHome });
        addEvent(run, 'project_memory_closeout', {
          persisted: closeout.persisted === true,
          duplicate: closeout.duplicate === true,
          reason: closeout.reason || null,
        });
      } catch (err) {
        addEvent(run, 'error', {
          message: `Project Memory closeout skipped: ${err.message}`,
        });
      }
    }
  });
}

async function handle(req, res) {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const path = url.pathname;

  try {
    if (req.method === 'GET' && path === '/v1/health') {
      json(res, 200, {
        ok: true,
        bridge_id: 'local-dev-agent-bridge',
        version: '0.1.0',
        agents: ['claude_code', 'codex', 'opencode'],
        features: ['git_status', 'git_pull', 'git_push', 'project_memory_projection', 'project_memory_auto_closeout'],
        transport: certPath && keyPath ? 'https' : 'http-local',
      });
      return;
    }

    if (req.method === 'POST' && path === '/v1/runs') {
      const body = await readJson(req);
      const mode = String(body.mode || 'read_only');
      if (!['read_only', 'workspace_write'].includes(mode)) {
        json(res, 400, { error: `unsupported mode: ${mode}` });
        return;
      }
      const project = validateProject(body.project);
      const prompt = String(body.prompt || '').trim();
      if (!prompt) {
        json(res, 400, { error: 'prompt is required' });
        return;
      }

      const runId = String(body.client_run_id || randomUUID());
      const run = {
        id: runId,
        sessionId: runId,
        agentType: String(body.agent_type || ''),
        project,
        mode,
        status: 'pending',
        summary: null,
        startedAt: nowSeconds(),
        endedAt: null,
        lastSeq: 0,
        events: [],
        artifacts: new Map(),
        transcript: [],
        child: null,
        worktreePath: null,
        branch: null,
      };
      runs.set(runId, run);
      persistState();
      addEvent(run, 'status', { status: 'pending', message: 'Run accepted by bridge.' });
      console.log(
        `[runs] new run ${runId.slice(0, 8)} agent=${run.agentType} mode=${mode} tier=${project.permissionTier} project="${project.name}" id=${project.id.slice(0, 8)}`,
      );
      startProcess(run, run.agentType, project, prompt, mode);
      json(res, 200, {
        run_id: runId,
        session_id: runId,
        status: run.status,
      });
      return;
    }

    const runMatch = path.match(/^\/v1\/runs\/([^/]+)$/);
    if (req.method === 'GET' && runMatch) {
      const run = runs.get(decodeURIComponent(runMatch[1]));
      if (!run) return notFound(res);
      json(res, 200, {
        run_id: run.id,
        status: run.status,
        summary: run.summary,
        branch: run.branch,
        worktree_path: run.worktreePath,
      });
      return;
    }

    const eventsMatch = path.match(/^\/v1\/runs\/([^/]+)\/events$/);
    if (req.method === 'GET' && eventsMatch) {
      const run = runs.get(decodeURIComponent(eventsMatch[1]));
      if (!run) return notFound(res);
      const after = Number(url.searchParams.get('after') || 0);
      json(res, 200, {
        events: run.events.filter((event) => event.seq > after),
      });
      return;
    }

    const abortMatch = path.match(/^\/v1\/runs\/([^/]+)\/abort$/);
    if (req.method === 'POST' && abortMatch) {
      const run = runs.get(decodeURIComponent(abortMatch[1]));
      if (!run) return notFound(res);
      if (run.child) run.child.kill();
      setStatus(run, 'aborted', 'Run aborted by user.');
      json(res, 200, { ok: true, status: run.status });
      return;
    }

    const decisionMatch = path.match(/^\/v1\/runs\/([^/]+)\/decision$/);
    if (req.method === 'POST' && decisionMatch) {
      const run = runs.get(decodeURIComponent(decisionMatch[1]));
      if (!run) return notFound(res);
      if (!terminalStatuses.has(run.status)) {
        json(res, 409, {
          ok: false,
          error: 'run_not_terminal',
          message: `Run is still ${run.status}; abort or wait before deciding.`,
        });
        return;
      }
      const body = await readJson(req);
      const decision = String(body.decision || '').trim();
      if (!['leave', 'discard', 'apply'].includes(decision)) {
        json(res, 400, {
          ok: false,
          error: 'invalid_decision',
          message: 'decision must be one of leave | discard | apply',
        });
        return;
      }

      // discard / apply require a worktree. read-only runs never have one.
      if ((decision === 'discard' || decision === 'apply') && !run.worktreePath) {
        addEvent(run, 'decision', {
          decision,
          status: 'rejected',
          reason: 'no_worktree',
        });
        json(res, 422, {
          ok: false,
          status: 'rejected',
          reason: 'no_worktree',
          message: `Run has no worktree to ${decision}. Only write-mode runs produce worktrees.`,
        });
        return;
      }

      try {
        if (decision === 'discard') {
          const result = cleanupWorktree(run, run.project);
          run.worktreePath = null;
          run.branch = null;
          addEvent(run, 'decision', {
            decision,
            status: result.ok ? 'accepted' : 'rejected',
            ...(result.message ? { message: result.message } : {}),
          });
          if (!result.ok) {
            json(res, 500, {
              ok: false,
              status: 'rejected',
              reason: 'worktree_cleanup_failed',
              message: result.message,
            });
            return;
          }
        } else if (decision === 'apply') {
          const result = applyWorktree(run, run.project);
          addEvent(run, 'decision', {
            decision,
            status: result.ok ? 'accepted' : 'rejected',
            ...(result.reason ? { reason: result.reason } : {}),
            ...(result.message ? { message: result.message } : {}),
          });
          if (!result.ok) {
            json(res, 422, {
              ok: false,
              status: 'rejected',
              reason: result.reason || 'apply_failed',
              message: result.message ||
                `Could not apply ${run.branch} onto ${run.project.defaultBranch}.`,
            });
            return;
          }
          run.worktreePath = null;
          run.branch = null;
        } else {
          // leave — keep worktree and branch around; just record the decision.
          addEvent(run, 'decision', {
            decision,
            status: 'accepted',
            responded_at: body.responded_at || nowSeconds(),
          });
        }
      } catch (err) {
        addEvent(run, 'decision', {
          decision,
          status: 'rejected',
          message: err.message,
        });
        json(res, 500, {
          ok: false,
          status: 'rejected',
          reason: 'bridge_error',
          message: err.message,
        });
        return;
      }

      json(res, 200, { ok: true, status: 'accepted', decision });
      return;
    }

    const approvalsMatch = path.match(/^\/v1\/runs\/([^/]+)\/approvals\/([^/]+)$/);
    if (req.method === 'POST' && approvalsMatch) {
      const run = runs.get(decodeURIComponent(approvalsMatch[1]));
      if (!run) return notFound(res);
      const body = await readJson(req);
      const status = body.decision === 'approved' ? 'approved' : 'denied';
      addEvent(run, 'status', {
        status: `approval_${status}`,
        approval_id: decodeURIComponent(approvalsMatch[2]),
      });
      json(res, 200, { ok: true, status });
      return;
    }

    const artifactsMatch = path.match(/^\/v1\/runs\/([^/]+)\/artifacts$/);
    if (req.method === 'GET' && artifactsMatch) {
      const run = runs.get(decodeURIComponent(artifactsMatch[1]));
      if (!run) return notFound(res);
      json(res, 200, {
        artifacts: Array.from(run.artifacts.values()),
      });
      return;
    }

    if (req.method === 'POST' && path === '/v1/cleanup/worktrees') {
      const body = await readJson(req);
      const projectId = String(body.project_id || '').trim();
      if (!projectId) {
        json(res, 400, { error: 'project_id is required' });
        return;
      }
      let removed = 0;
      const failures = [];
      for (const run of runs.values()) {
        if (run.project?.id !== projectId) continue;
        if (!run.worktreePath || !run.branch) continue;
        if (!terminalStatuses.has(run.status)) continue;
        try {
          const result = cleanupWorktree(run, run.project);
          if (result.ok) {
            run.worktreePath = null;
            run.branch = null;
            addEvent(run, 'decision', {
              decision: 'discard',
              status: 'accepted',
              reason: 'bulk_cleanup',
            });
            removed++;
          } else {
            failures.push({ run_id: run.id, message: result.message });
          }
        } catch (err) {
          failures.push({ run_id: run.id, message: err.message });
        }
      }
      console.log(`[cleanup] project=${projectId.slice(0, 8)} removed=${removed} failed=${failures.length}`);
      json(res, 200, { ok: true, removed, failures });
      return;
    }

    // -----------------------------------------------------------------------
    // Project-level git operations (Phase 4a+)
    // These operate on the main working copy, not on worktrees.
    // -----------------------------------------------------------------------

    const gitStatusMatch = path.match(/^\/v1\/projects\/([^/]+)\/git-status$/);
    if (req.method === 'GET' && gitStatusMatch) {
      const projectId = decodeURIComponent(gitStatusMatch[1]);
      let project;
      try {
        project = projectFromQuery(url, projectId) || findProject(projectId);
      } catch (err) {
        return json(res, 422, {
          error: 'invalid_project',
          message: err.message,
        });
      }
      if (!project) return json(res, 404, { error: 'project_not_found', message: `No runs recorded for project ${projectId.slice(0, 8)}. Start an agent run first.` });
      try {
        ensureGitRepo(project.rootPath);
        const branch = runGit(project.rootPath, ['rev-parse', '--abbrev-ref', 'HEAD']).stdout.trim();
        let ahead = 0;
        let behind = 0;
        // rev-list --left-right --count: first column = behind, second = ahead
        try {
          const counts = runGit(project.rootPath, [
            'rev-list', '--left-right', '--count',
            `origin/${project.defaultBranch}...HEAD`,
          ]).stdout.trim().split(/\s+/);
          behind = parseInt(counts[0] || '0', 10);
          ahead = parseInt(counts[1] || '0', 10);
        } catch (_) {
          // No remote tracking branch yet — both remain 0.
        }
        const statusCheck = runGit(project.rootPath, ['status', '--porcelain'], { allowFail: true });
        const hasUncommittedChanges = (statusCheck.stdout || '').trim().length > 0;
        json(res, 200, {
          branch,
          ahead,
          behind,
          lastFetch: null,
          hasUncommittedChanges,
        });
      } catch (err) {
        json(res, 422, { error: 'git_status_error', message: err.message });
      }
      return;
    }

    if (req.method === 'GET' && path === '/v1/project-memory/projections') {
      const registry = loadProjectRegistry({ iHome });
      if (registry.status !== 'ready') {
        json(res, 503, { error: 'i_registry_unavailable', status: registry.status });
        return;
      }
      const store = createIActivityStore({ iHome });
      const payload = store.getMemoryV3Projections({
        projects: registry.projects,
        after: url.searchParams.get('after') || undefined,
        limit: Number(url.searchParams.get('limit') || 100),
      });
      json(res, 200, payload);
      return;
    }

    const gitPullMatch = path.match(/^\/v1\/projects\/([^/]+)\/git-pull$/);
    if (req.method === 'POST' && gitPullMatch) {
      const projectId = decodeURIComponent(gitPullMatch[1]);
      const project = findProject(projectId);
      if (!project) return json(res, 404, { error: 'project_not_found', message: `No runs recorded for project ${projectId.slice(0, 8)}.` });
      try {
        ensureGitRepo(project.rootPath);
        const before = runGit(project.rootPath, ['rev-parse', 'HEAD']).stdout.trim();
        // Ensure we are on the default branch so merge targets the right ref.
        runGit(project.rootPath, ['checkout', project.defaultBranch], { allowFail: true });
        runGit(project.rootPath, ['fetch', 'origin', project.defaultBranch]);
        const merge = runGit(project.rootPath, [
          'merge', '--ff-only', `origin/${project.defaultBranch}`,
        ], { allowFail: true });
        if (merge.status === 0) {
          const after = runGit(project.rootPath, ['rev-parse', 'HEAD']).stdout.trim();
          const commits = getCommitList(project.rootPath, `${before}..${after}`);
          const msg = commits.length
            ? `Pulled ${commits.length} commit(s).`
            : 'Already up to date.';
          console.log(`[git-pull] project=${projectId.slice(0, 8)} branch=${project.defaultBranch} commits=${commits.length}`);
          json(res, 200, { ok: true, message: msg, commits });
        } else {
          const stderr = (merge.stderr || '').trim();
          json(res, 200, {
            ok: false,
            message: stderr || 'Pull failed: not fast-forward.',
            commits: [],
          });
        }
      } catch (err) {
        json(res, 200, { ok: false, message: err.message, commits: [] });
      }
      return;
    }

    const gitPushMatch = path.match(/^\/v1\/projects\/([^/]+)\/git-push$/);
    if (req.method === 'POST' && gitPushMatch) {
      const projectId = decodeURIComponent(gitPushMatch[1]);
      const project = findProject(projectId);
      if (!project) return json(res, 404, { error: 'project_not_found', message: `No runs recorded for project ${projectId.slice(0, 8)}.` });
      try {
        ensureGitRepo(project.rootPath);
        // Snapshot the remote ref before pushing so we can report what was sent.
        const beforeResult = runGit(project.rootPath, [
          'rev-parse', `origin/${project.defaultBranch}`,
        ], { allowFail: true });
        runGit(project.rootPath, ['push', 'origin', project.defaultBranch]);
        let commits = [];
        if (beforeResult.status === 0) {
          const beforeHash = beforeResult.stdout.trim();
          const afterResult = runGit(project.rootPath, [
            'rev-parse', `origin/${project.defaultBranch}`,
          ]);
          commits = getCommitList(project.rootPath, `${beforeHash}..${afterResult.stdout.trim()}`);
        }
        const msg = commits.length
          ? `Pushed ${commits.length} commit(s).`
          : 'Push completed.';
        console.log(`[git-push] project=${projectId.slice(0, 8)} branch=${project.defaultBranch} commits=${commits.length}`);
        json(res, 200, { ok: true, message: msg, commits });
      } catch (err) {
        json(res, 200, { ok: false, message: err.message, commits: [] });
      }
      return;
    }

    notFound(res);
  } catch (error) {
    json(res, 500, {
      error: 'bridge_error',
      message: error instanceof Error ? error.message : String(error),
    });
  }
}

const server = certPath && keyPath
  ? https.createServer(
      {
        cert: readFileSync(certPath),
        key: readFileSync(keyPath),
        minVersion: 'TLSv1.2',
        maxVersion: 'TLSv1.2',
      },
      handle,
    )
  : http.createServer(handle);

server.on('error', (error) => {
  console.error(`Dev Agent Bridge failed to start: ${error.message}`);
  process.exitCode = 1;
});

loadState();

server.listen(port, host, () => {
  const protocol = certPath && keyPath ? 'https' : 'http';
  console.log(`Dev Agent Bridge listening on ${protocol}://${host}:${port}`);
  if (protocol === 'http') {
    console.log('Phone app requires HTTPS. Use Tailscale Serve or set DEV_AGENT_BRIDGE_CERT/KEY for phone testing.');
  }
});
