// Persistence for the semantic overlay that sits on top of Codex read-only data.
// Codex gives us threads, parents, and timestamps; users add goals/notes/
// blocked-reasons and explicit edges. Both layers merge at /api/graph.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_DIR = path.join(__dirname, '..', 'data');
const FILE = path.join(DATA_DIR, 'task-graph.json');

const EMPTY = {
  version: '1',
  nodes: {},   // threadId -> { pinnedTitle?, goal?, kind?, runState?, acceptanceState?, blocker?, nextAction?, note?, updatedAt? }
  edges: {},   // "from->to:type" -> { from, to, type, note?, updatedAt? }
};

async function ensureDir() {
  await fs.promises.mkdir(DATA_DIR, { recursive: true });
}

export async function readOverlay() {
  try {
    const raw = await fs.promises.readFile(FILE, 'utf8');
    const parsed = JSON.parse(raw);
    return { ...EMPTY, ...parsed };
  } catch (err) {
    if (err.code === 'ENOENT') return structuredClone(EMPTY);
    throw new Error(`cannot read ${FILE}: ${err.message}`);
  }
}

export async function writeOverlay(data) {
  await ensureDir();
  const next = { ...EMPTY, ...data, version: '1' };
  const tmp = FILE + '.tmp';
  await fs.promises.writeFile(tmp, JSON.stringify(next, null, 2), 'utf8');
  await fs.promises.rename(tmp, FILE);
  return next;
}

// Convenience mutators used by the routes.

export async function upsertNode(threadId, patch) {
  const o = await readOverlay();
  o.nodes[threadId] = {
    ...(o.nodes[threadId] ?? {}),
    ...patch,
    updatedAt: new Date().toISOString(),
  };
  await writeOverlay(o);
  return o.nodes[threadId];
}

export async function upsertEdge(from, to, type, note) {
  const o = await readOverlay();
  const key = `${from}->${to}:${type}`;
  o.edges[key] = { from, to, type, note: note ?? null, updatedAt: new Date().toISOString() };
  await writeOverlay(o);
  return o.edges[key];
}

export async function deleteEdge(from, to, type) {
  const o = await readOverlay();
  const key = `${from}->${to}:${type}`;
  if (o.edges[key]) {
    delete o.edges[key];
    await writeOverlay(o);
  }
  return true;
}
