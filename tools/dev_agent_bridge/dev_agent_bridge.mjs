import http from 'node:http';
import https from 'node:https';
import { spawn } from 'node:child_process';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { URL } from 'node:url';

const host = process.env.DEV_AGENT_BRIDGE_HOST || '127.0.0.1';
const port = Number(process.env.DEV_AGENT_BRIDGE_PORT || 47831);
const certPath = process.env.DEV_AGENT_BRIDGE_CERT;
const keyPath = process.env.DEV_AGENT_BRIDGE_KEY;
const codexModel = process.env.DEV_AGENT_CODEX_MODEL;
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
    for (const key of ['text', 'message', 'delta', 'content', 'summary', 'result']) {
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

function commandFor(agentType, project, prompt) {
  if (agentType === 'codex') {
    const args = [
      'exec',
      '--json',
      '--sandbox',
      'read-only',
      '--cd',
      project.rootPath,
    ];
    if (codexModel) args.push('-m', codexModel);
    args.push(prompt);
    return commandSpec('codex', args, 'Codex');
  }

  if (agentType === 'claude_code') {
    return commandSpec(
      'claude',
      [
        '-p',
        prompt,
        '--output-format',
        'stream-json',
        '--verbose',
        '--permission-mode',
        'plan',
        '--tools',
        'Read,Grep,Glob,LS',
      ],
      'Claude Code',
    );
  }

  throw new Error(`Unsupported agent_type: ${agentType}`);
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

function startProcess(run, agentType, project, prompt) {
  let spec;
  try {
    spec = commandFor(agentType, project, prompt);
  } catch (error) {
    setStatus(run, 'failed', error.message);
    return;
  }

  addEvent(run, 'tool_call', {
    name: spec.displayName || spec.command,
    description: `Start ${spec.displayName || spec.command} read-only run.`,
    risk: 'low',
  });

  const child = spawn(spec.command, spec.args, {
    cwd: project.rootPath,
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
      if (body.mode !== 'read_only') {
        json(res, 400, { error: 'only read_only mode is supported by this prototype' });
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
        status: 'pending',
        summary: null,
        startedAt: nowSeconds(),
        endedAt: null,
        lastSeq: 0,
        events: [],
        artifacts: new Map(),
        transcript: [],
        child: null,
      };
      runs.set(runId, run);
      addEvent(run, 'status', { status: 'pending', message: 'Run accepted by bridge.' });
      startProcess(run, run.agentType, project, prompt);
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
        branch: null,
        worktree_path: null,
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
      },
      handle,
    )
  : http.createServer(handle);

server.listen(port, host, () => {
  const protocol = certPath && keyPath ? 'https' : 'http';
  console.log(`Dev Agent Bridge listening on ${protocol}://${host}:${port}`);
  if (protocol === 'http') {
    console.log('Phone app requires HTTPS. Use Tailscale Serve or set DEV_AGENT_BRIDGE_CERT/KEY for phone testing.');
  }
});
