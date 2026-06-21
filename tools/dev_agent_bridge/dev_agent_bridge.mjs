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
import path from 'node:path';
import { URL } from 'node:url';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const host = process.env.DEV_AGENT_BRIDGE_HOST || '127.0.0.1';
const port = Number(process.env.DEV_AGENT_BRIDGE_PORT || 47831);
const certPath = process.env.DEV_AGENT_BRIDGE_CERT;
const keyPath = process.env.DEV_AGENT_BRIDGE_KEY;
const codexModel = process.env.DEV_AGENT_CODEX_MODEL;
const scriptDir = dirname(fileURLToPath(import.meta.url));
const statePath = process.env.DEV_AGENT_BRIDGE_STATE ||
  join(scriptDir, '.state', 'runs.json');
const runs = new Map();

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
    run.summary = text.length > 280 ? `${text.slice(0, 277)}...` : text;
    return;
  }

  addEvent(run, 'status', { status: run.status, message: type });
}

function commandFor(agentType, project, prompt, mode, cwd) {
  const isWrite = mode === 'workspace_write';

  if (agentType === 'codex') {
    const args = [
      'exec',
      '--json',
      '--sandbox',
      isWrite ? 'workspace-write' : 'read-only',
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
        agents: ['claude_code', 'codex'],
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
