#!/usr/bin/env node
// Read-only mirror of chosen Feishu Drive folders into a local notes directory,
// for the i MCP to read later. One file per document, keyed by its token: an
// edited document is overwritten in place, a document gone from Feishu is
// removed locally. Nothing is ever written to Feishu.
import { readFile, writeFile, mkdir, rename, open, unlink, access } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { callCli, fail, SyncError } from './cli.mjs';
import { assertSeparateDirectories, resolvedPath } from './layout.mjs';
import { object } from './schema.mjs';

export const HELP = `Feishu notes mirror (Node 24)
Usage: node <tool>/sync/notes_mirror.mjs --notes <notes dir> --state <study>/state --config <tool>/config.json [--max-minutes N]
       node sync/notes_mirror.mjs --help
Mirrors the docx documents under config.notes.folders (top-level Drive folder names,
subfolders included) into <notes dir>/<folder>/<token>.md plus index.json.
Read-only towards Feishu. Skips quietly while feishu_sync holds <study>/state/.sync.lock.
--max-minutes (0-120, default 20) stops fetching after that long; the rest waits for the next run.
`;
export const INDEX_FORMAT = 'notes-v1';
const MAX_DEPTH = 4, MAX_DOCS = 5000, MAX_PAGES = 200, DEFAULT_MINUTES = 20;
const TOKEN = /^[A-Za-z0-9_-]{1,128}$/u;

async function exists(file) { try { await access(file); return true; } catch { return false; } }
async function atomicWrite(file, text) {
  await mkdir(path.dirname(file), { recursive: true });
  const temp = `${file}.pending-${randomUUID()}`;
  try { await writeFile(temp, text, { mode: 0o600 }); await rename(temp, file); }
  finally { if (await exists(temp)) await unlink(temp); }
}
function code(error) { return error instanceof SyncError ? error.code : 'notes_failed'; }

export function notesFolders(config) {
  const folders = config?.notes?.folders;
  if (!object(config?.notes) || !Array.isArray(folders) || !folders.length || folders.length > 10 ||
      folders.some(v => typeof v !== 'string' || !v.trim() || v.length > 100 || /[\u0000-\u001f]/u.test(v)) ||
      new Set(folders).size !== folders.length) fail('notes_config_invalid');
  return folders;
}

// Local directory per configured top folder. Names like 日记/日报 keep their
// words but lose path separators; collisions get a numeric suffix.
export function folderSlugs(folders) {
  const used = new Set();
  return folders.map(name => {
    const base = name.replace(/[\\/:*?"<>|]/gu, '-').replace(/^\.+/u, '_').slice(0, 80);
    let slug = base, n = 2;
    while (used.has(slug.toLowerCase())) slug = `${base}-${n++}`;
    used.add(slug.toLowerCase());
    return slug;
  });
}

async function listFolder(config, folder) {
  const files = [], seen = new Set();
  let page = '';
  for (let i = 0; i < MAX_PAGES; i++) {
    const data = await callCli(config, 'folder_list', { folder, page });
    if (!Array.isArray(data?.files)) fail('notes_listing_invalid');
    files.push(...data.files);
    if (!folder || data.has_more !== true) return files;
    const next = data.next_page_token;
    if (typeof next !== 'string' || !next || seen.has(next)) fail('notes_pagination_invalid');
    seen.add(next); page = next;
  }
  fail('notes_pagination_invalid');
}

function modifiedSeconds(value) {
  if (typeof value !== 'string' || !/^\d{1,12}$/u.test(value)) fail('notes_listing_invalid');
  return value;
}

async function walk(config, token, folderPath, top, depth, out, stats) {
  for (const file of await listFolder(config, token)) {
    if (!object(file) || typeof file.token !== 'string' || typeof file.type !== 'string' || typeof file.name !== 'string') fail('notes_listing_invalid');
    if (file.type === 'folder') {
      if (!TOKEN.test(file.token)) fail('notes_listing_invalid');
      if (depth >= MAX_DEPTH) { stats.skipped++; continue; }
      await walk(config, file.token, `${folderPath}/${file.name}`, top, depth + 1, out, stats);
    } else if (file.type === 'docx') {
      if (!TOKEN.test(file.token)) fail('notes_listing_invalid');
      if (out.has(file.token)) continue;
      if (out.size >= MAX_DOCS) fail('notes_too_many_documents');
      out.set(file.token, { title: file.name, folder: folderPath, top, modified_time: modifiedSeconds(file.modified_time),
        url: typeof file.url === 'string' && file.url.startsWith('https://') ? file.url : null });
    } else stats.skipped++; // sheets, bases, uploads, shortcuts, legacy docs
  }
}

async function loadIndex(notesDir) {
  const file = path.join(notesDir, 'index.json');
  if (!await exists(file)) return { format: INDEX_FORMAT, docs: {} };
  let index;
  try { index = JSON.parse(await readFile(file, 'utf8')); } catch { fail('notes_index_invalid'); }
  if (!object(index) || index.format !== INDEX_FORMAT || !object(index.docs) ||
      Object.entries(index.docs).some(([token, doc]) => !TOKEN.test(token) || !object(doc) || typeof doc.file !== 'string')) fail('notes_index_invalid');
  return index;
}

function render(token, doc, content) {
  const header = [
    '---',
    `title: ${JSON.stringify(doc.title)}`,
    `folder: ${JSON.stringify(doc.folder)}`,
    ...(doc.url ? [`url: ${JSON.stringify(doc.url)}`] : []),
    `modified: ${doc.modified}`,
    `token: ${token}`,
    '---',
    '',
  ];
  return `${header.join('\n')}\n${content.endsWith('\n') ? content : `${content}\n`}`;
}

// deadline (ms since epoch): documents not fetched by then keep their last copy
// and are counted as deferred, so a large first run spreads over several runs
// instead of being killed by the scheduler before index.json is written.
export async function mirror(config, notesDir, now = () => new Date(), { deadline = Infinity } = {}) {
  const folders = notesFolders(config), slugs = folderSlugs(folders);
  const index = await loadIndex(notesDir);

  // Every listing finishes before any local write, so a failed or partial
  // listing never deletes local copies.
  const root = await listFolder(config, '');
  const listed = new Map(), stats = { fetched: 0, unchanged: 0, deferred: 0, removed: 0, failed: 0, skipped: 0 };
  for (const [i, name] of folders.entries()) {
    const matches = root.filter(f => object(f) && f.type === 'folder' && f.name === name);
    if (!matches.length) fail('notes_folder_not_found');
    if (matches.length > 1) fail('notes_folder_ambiguous');
    if (typeof matches[0].token !== 'string' || !TOKEN.test(matches[0].token)) fail('notes_listing_invalid');
    const before = listed.size;
    await walk(config, matches[0].token, name, slugs[i], 0, listed, stats);
    // An empty listing for a folder that had documents looks like lost access,
    // not a mass deletion. Keep everything and report instead.
    if (listed.size === before && Object.values(index.docs).some(d => d.top === slugs[i])) fail('notes_listing_empty');
  }

  const docs = {};
  for (const [token, doc] of listed) {
    const file = `${doc.top}/${token}.md`, old = index.docs[token];
    const modified = new Date(Number(doc.modified_time) * 1000).toISOString();
    const entry = { title: doc.title, folder: doc.folder, top: doc.top, url: doc.url, modified_time: doc.modified_time, modified, file };
    const current = old && old.modified_time === doc.modified_time && old.title === doc.title &&
      old.folder === doc.folder && old.file === file && await exists(path.join(notesDir, file));
    if (current) { docs[token] = old; stats.unchanged++; continue; }
    if (Date.now() >= deadline) { if (old) docs[token] = old; stats.deferred++; continue; }
    try {
      const data = await callCli(config, 'doc_fetch', { doc: token });
      if (typeof data?.document?.content !== 'string') fail('cli_invalid_response');
      await atomicWrite(path.join(notesDir, file), render(token, entry, data.document.content));
      if (old && old.file !== file) await unlink(path.join(notesDir, old.file)).catch(() => {});
      docs[token] = { ...entry, chars: data.document.content.length, synced_at: now().toISOString() };
      stats.fetched++;
    } catch {
      // Keep the last good copy; the next run retries.
      if (old) docs[token] = old;
      stats.failed++;
    }
  }
  for (const [token, old] of Object.entries(index.docs)) {
    if (listed.has(token)) continue;
    await unlink(path.join(notesDir, old.file)).catch(error => { if (error.code !== 'ENOENT') throw error; });
    stats.removed++;
  }
  const result = { at: now().toISOString(), ...stats, documents: Object.keys(docs).length };
  await atomicWrite(path.join(notesDir, 'index.json'),
    `${JSON.stringify({ format: INDEX_FORMAT, folders: folders.map((name, i) => ({ name, dir: slugs[i] })), last_run: result, docs }, null, 2)}\n`);
  return result;
}

async function acquire(file) {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const handle = await open(file, 'wx');
      await handle.writeFile(`${JSON.stringify({ pid: process.pid, started_at: new Date().toISOString() })}\n`);
      return handle;
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      let owner;
      try { owner = JSON.parse(await readFile(file, 'utf8')); } catch { fail('notes_locked'); }
      let alive = true;
      if (Number.isSafeInteger(owner?.pid) && owner.pid > 0) {
        try { process.kill(owner.pid, 0); } catch (probe) { if (probe.code === 'ESRCH') alive = false; }
      }
      // Our own lock only: a crashed mirror run must not block every later run.
      if (alive || attempt) fail('notes_locked');
      await unlink(file).catch(() => {});
    }
  }
  fail('notes_locked');
}

export async function run(argv, output = console.log) {
  if (argv.length === 1 && ['--help', '-h'].includes(argv[0])) { output(HELP); return 0; }
  const toolDirectory = fileURLToPath(new URL('../', import.meta.url));
  let configFile = path.join(toolDirectory, 'config.json'), state, notes, suppliedConfig = false, minutes;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--config' && argv[i + 1] && !suppliedConfig) { configFile = path.resolve(argv[++i]); suppliedConfig = true; }
    else if (argv[i] === '--state' && argv[i + 1] && !state) state = path.resolve(argv[++i]);
    else if (argv[i] === '--notes' && argv[i + 1] && !notes) notes = path.resolve(argv[++i]);
    else if (argv[i] === '--max-minutes' && /^\d{1,3}$/u.test(argv[i + 1] ?? '') && Number(argv[i + 1]) <= 120 && minutes === undefined) minutes = Number(argv[++i]);
    else fail('usage_invalid');
  }
  if (!state || !notes) fail('usage_invalid');
  // The notes copy stays apart from the tools (code, config) and from the
  // study directory that the scheduled Codex may write.
  await assertSeparateDirectories(notes, [toolDirectory, path.dirname(configFile), path.dirname(await resolvedPath(configFile)), path.dirname(state)]);
  let config;
  try { config = JSON.parse(await readFile(configFile, 'utf8')); } catch { fail('local_json_invalid'); }
  notesFolders(config);
  // feishu_sync and this mirror share one CLI login; never refresh it from two
  // processes at once. A busy sync means try again next run.
  if (await exists(path.join(state, '.sync.lock'))) { output('notes_skipped_sync_busy'); return 0; }
  await mkdir(notes, { recursive: true });
  const lockFile = path.join(notes, '.mirror.lock'), lock = await acquire(lockFile);
  try {
    const result = await mirror(config, notes, undefined, { deadline: Date.now() + (minutes ?? DEFAULT_MINUTES) * 60000 });
    output(`notes_ok fetched=${result.fetched} unchanged=${result.unchanged} deferred=${result.deferred} removed=${result.removed} failed=${result.failed}`);
    if (result.failed || result.deferred) { console.error(result.failed ? 'notes_partial' : 'notes_deferred'); return 2; }
    return 0;
  } finally { await lock.close(); await unlink(lockFile).catch(() => {}); }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { process.exitCode = await run(process.argv.slice(2)); }
  catch (error) { console.error(code(error)); process.exitCode = 1; }
}
