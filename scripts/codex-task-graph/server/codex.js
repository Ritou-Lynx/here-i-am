// Read ~/.codex/sessions/**/*.jsonl and build an in-memory thread catalog.
// No external deps. Tolerates malformed lines; only session_meta records are
// required, with optional thread_name/goal records picked up opportunistically.

import fs from 'node:fs';
import path from 'node:path';

const CODEX_HOME = process.env.CODEX_HOME ?? path.join(process.env.USERPROFILE ?? process.env.HOME ?? '~', '.codex');
const SESSIONS_DIR = path.join(CODEX_HOME, 'sessions');
const INDEX_FILE = path.join(CODEX_HOME, 'session_index.jsonl');

// Walk sessions dir, newest first. Limit keeps cold scans bounded without
// hiding real tasks; UI can request a rescan with a larger limit.
export async function scanSessions({ limit = 3000 } = {}) {
  const files = [];
  try {
    const years = (await fs.promises.readdir(SESSIONS_DIR, { withFileTypes: true }))
      .filter((d) => d.isDirectory())
      .map((d) => d.name)
      .sort()
      .reverse();
    for (const year of years) {
      const yearDir = path.join(SESSIONS_DIR, year);
      const months = (await fs.promises.readdir(yearDir, { withFileTypes: true }))
        .filter((d) => d.isDirectory())
        .map((d) => d.name)
        .sort()
        .reverse();
      for (const month of months) {
        const monthDir = path.join(yearDir, month);
        const days = (await fs.promises.readdir(monthDir, { withFileTypes: true }))
          .filter((d) => d.isDirectory())
          .map((d) => d.name)
          .sort()
          .reverse();
        for (const day of days) {
          const dayDir = path.join(monthDir, day);
          const entries = await fs.promises.readdir(dayDir, { withFileTypes: true });
          for (const e of entries) {
            if (e.isFile() && e.name.endsWith('.jsonl')) {
              files.push(path.join(dayDir, e.name));
            }
          }
        }
      }
    }
  } catch (err) {
    throw new Error(`cannot scan ${SESSIONS_DIR}: ${err.message}`);
  }

  files.sort().reverse(); // path contains date, so lexicographic works
  const taken = files.slice(0, limit);

  const threads = new Map();

  // Parse concurrently in small batches; single-threaded readline was the bottleneck.
  const concurrency = 16;
  for (let i = 0; i < taken.length; i += concurrency) {
    await Promise.all(taken.slice(i, i + concurrency).map((f) => parseSessionFile(f, threads)));
  }

  // Merge display names from session_index.jsonl (authoritative for renamed threads)
  await mergeIndexNames(threads);

  return [...threads.values()];
}

async function parseSessionFile(filePath, threads) {
  // Read whole file once (small: sessions are typically <200KB even when long,
  // and the meta record is on line 1). Then selectively parse only the lines we
  // care about, stopping after the first non-meta user message.
  let raw;
  try {
    raw = await fs.promises.readFile(filePath, 'utf8');
  } catch {
    return;
  }
  const lines = raw.split('\n');

  const fname = path.parse(filePath).name;
  const nameMatch = /rollout-(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})/.exec(fname);
  const fileDate = nameMatch
    ? `${nameMatch[1]}-${nameMatch[2]}-${nameMatch[3]}T${nameMatch[4]}:${nameMatch[5]}:${nameMatch[6]}Z`
    : null;

  let thread = null;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (!line) continue;

    // Quick pre-filter: marker substrings, no JSON parse unless we need it.
    const isMeta = line.includes('"session_meta"');
    const isNameSet = !isMeta && line.includes('"thread_name_set"');
    const isGoal = !isMeta && !isNameSet && line.includes('"session_goal"');
    const isTaskStarted = !isMeta && !isNameSet && !isGoal && line.includes('"task_started"');
    const hasUser = !isMeta && !isNameSet && !isGoal && !isTaskStarted
      && line.includes('"response_item"') && line.includes('"role":"user"');

    if (!isMeta && !thread) continue;
    if (!isMeta && !isNameSet && !isGoal && !isTaskStarted && !hasUser) continue;
    if (hasUser && thread?.lastSnippet != null) {
      // Already captured; stop — name / goal / task_started would already have
      // appeared by this point in nearly all sessions.
      if (i > 100) break;
      continue;
    }

    let rec;
    try { rec = JSON.parse(line); } catch { continue; }

    if (isMeta) {
      const p = rec.payload ?? {};
      const source = p.source ?? null;
      const subagent = typeof source === 'object' && source?.subagent ? source.subagent : null;
      const spawn = subagent?.thread_spawn ?? null;
      const id = p.id ?? p.session_id;
      if (!id) continue;
      if (!threads.has(id)) {
        thread = {
          id,
          sessionId: p.session_id ?? id,
          parentThreadId: p.parent_thread_id ?? spawn?.parent_thread_id ?? null,
          forkedFromId: p.forked_from_id ?? null,
          spawnDepth: spawn?.depth ?? null,
          agentPath: spawn?.agent_path ?? null,
          agentRole: subagent?.other ?? null,
          threadSource: p.thread_source ?? null,
          cwd: p.cwd ?? null,
          originator: p.originator ?? null,
          cliVersion: p.cli_version ?? null,
          createdAt: p.timestamp ?? rec.timestamp ?? null,
          path: filePath,
          name: null,
          goal: null,
          updatedAt: fileDate,
          lastSnippet: null,
        };
        threads.set(id, thread);
      } else {
        thread = threads.get(id);
      }
      continue;
    }

    if (isNameSet) {
      const p = rec.payload ?? {};
      const name = p.name ?? p.thread_name ?? p.threadName;
      if (name) thread.name = name;
      continue;
    }
    if (isGoal) {
      const p = rec.payload ?? {};
      if (p.goal) thread.goal = typeof p.goal === 'string' ? p.goal : p.goal.text ?? null;
      continue;
    }
    if (isTaskStarted) {
      if (rec.timestamp && (!thread.updatedAt || rec.timestamp > thread.updatedAt)) {
        thread.updatedAt = rec.timestamp;
      }
      continue;
    }

    if (hasUser) {
      const msg = rec.payload;
      const text = (msg.content ?? []).map((c) => c?.text ?? c?.input_text ?? '').join(' ');
      const clean = String(text).replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
      if (clean && !/^you are (codex|here)/i.test(clean) && clean.length > 8 && !clean.startsWith('# ')) {
        thread.lastSnippet = clean.slice(0, 220);
      }
      continue;
    }
  }
}

async function mergeIndexNames(threads) {
  if (!fs.existsSync(INDEX_FILE)) return;
  let raw;
  try {
    raw = await fs.promises.readFile(INDEX_FILE, 'utf8');
  } catch {
    return;
  }
  for (const line of raw.split('\n')) {
    if (!line.trim()) continue;
    try {
      const rec = JSON.parse(line);
      if (rec.id && threads.has(rec.id)) {
        const t = threads.get(rec.id);
        if (rec.thread_name) t.name = rec.thread_name;
        if (rec.updated_at && (!t.updatedAt || rec.updated_at > t.updatedAt)) {
          t.updatedAt = rec.updated_at;
        }
      }
    } catch {
      continue;
    }
  }
}

// Build a hierarchical forest: for each thread, walk parentThreadId / forkedFromId
// up to a root. Returns array of root nodes with `children`.
export function buildForest(threads) {
  const byId = new Map(threads.map((t) => [t.id, t]));

  const childrenOf = new Map();
  for (const t of threads) {
    const parent = t.parentThreadId ?? t.forkedFromId ?? null;
    if (parent && byId.has(parent)) {
      if (!childrenOf.has(parent)) childrenOf.set(parent, []);
      childrenOf.get(parent).push(t);
    }
  }

  function toNode(t) {
    return {
      ...t,
      // Strip internal helper
      _titleExtracted: undefined,
      children: (childrenOf.get(t.id) ?? []).map(toNode),
    };
  }

  const roots = threads
    .filter((t) => {
      const parent = t.parentThreadId ?? t.forkedFromId ?? null;
      return !parent || !byId.has(parent);
    })
    .map(toNode);

  // Sort by recency: newest updatedAt/createdAt first.
  roots.sort((a, b) => {
    const ka = a.updatedAt ?? a.createdAt ?? '';
    const kb = b.updatedAt ?? b.createdAt ?? '';
    return kb.localeCompare(ka);
  });

  return roots;
}
