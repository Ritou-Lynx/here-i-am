// N2 notes tools: read-only access to the local Feishu notes mirror (tools/feishu_tutor/sync/notes_mirror.mjs).
// Self-contained (node: imports only) so the legacy candidate can inline this file verbatim, and so other
// home jobs (the daily summary) can import the store functions directly without going through MCP.
// Reads only index.json and the <dir>/<token>.md files it lists. Never writes, follows links or lists directories.
import * as notesFs from 'node:fs';
import * as notesPath from 'node:path';

export class NotesInputError extends Error {}
const notesFail = code => { throw new NotesInputError(code); };
const notesObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const NOTES_TIME_ZONE = 'Asia/Shanghai';
// A "day" runs from 04:00 to 04:00 local time, like the food log: late-night writing belongs to the day before.
const NOTES_DAY_START_HOUR = 4;
const NOTES_LIMITS = Object.freeze({index:16*1024*1024, file:4*1024*1024, readChars:20000, snippet:60, searchHits:20, recentDays:31, contextChars:240});
const NOTES_TOKEN = /^[A-Za-z0-9_-]{1,128}$/;
const NOTES_FILE = /^[^/\\\0]{1,80}\/[A-Za-z0-9_-]{1,128}\.md$/;
const notesReadOnly = {readOnlyHint:true,destructiveHint:false,idempotentHint:true,openWorldHint:false};
const NOTES_HINT = '这些是用户自己在飞书写的日记和工作文档（家里电脑每 30 分钟同步一次副本，见 synced_at）。用户聊到最近的生活、工作、心情或计划时，可以主动查，不必等用户要求；引用时说明出自哪篇，不编造没写过的内容。';
export const NOTES_TOOLS = Object.freeze([
  {name:'notes_recent',requiredScope:'i.read',description:'列出最近修改过的日记和工作文档（标题、所在文件夹、修改时间、token、字数、开头一小段）。默认最近 3 天；传 date（YYYY-MM-DD）只看那一天（以凌晨 4 点为日界）。需要全文时用 notes_read。'+NOTES_HINT,
    inputSchema:{type:'object',properties:{days:{type:'integer',minimum:1,maximum:31,description:'最近几天，默认 3。'},date:{type:'string',pattern:'^\\d{4}-\\d{2}-\\d{2}$',description:'只看这一天，和 days 二选一。'},folder:{type:'string',minLength:1,maxLength:100,description:'只看这个顶层文件夹，如 日记/日报、工作。'}},additionalProperties:false},annotations:notesReadOnly},
  {name:'notes_search',requiredScope:'i.read',description:'在日记和工作文档的标题和正文里搜索关键词（不区分大小写），按修改时间从新到旧返回命中的篇目和上下文片段，最多 20 篇。'+NOTES_HINT,
    inputSchema:{type:'object',properties:{query:{type:'string',minLength:1,maxLength:100},folder:{type:'string',minLength:1,maxLength:100},limit:{type:'integer',minimum:1,maximum:20}},required:['query'],additionalProperties:false},annotations:notesReadOnly},
  {name:'notes_read',requiredScope:'i.read',description:'按 token 读一篇日记或工作文档的正文，单次最多 20000 字，超出时用 offset 续读。token 来自 notes_recent 或 notes_search。',
    inputSchema:{type:'object',properties:{token:{type:'string',pattern:'^[A-Za-z0-9_-]{1,128}$'},offset:{type:'integer',minimum:0}},required:['token'],additionalProperties:false},annotations:notesReadOnly},
]);

function notesSameRoot(a, b) {
  return process.platform === 'win32' ? a.toLowerCase() === b.toLowerCase() : a === b;
}
export function loadNotesConfig(stateDir) {
  let text;
  try { text = notesFs.readFileSync(notesPath.resolve(stateDir, 'notes.json'), 'utf8'); }
  catch (error) { if (error.code === 'ENOENT') return null; throw new Error('notes_config_invalid'); }
  try {
    const value = JSON.parse(text.replace(/^﻿/, ''));
    if (!notesObject(value) || Object.keys(value).length !== 2 || value.format !== 'notes-config-v1' || typeof value.notes_dir !== 'string'
      || !notesPath.isAbsolute(value.notes_dir) || notesPath.resolve(value.notes_dir) !== value.notes_dir || value.notes_dir.includes('\0')) throw new Error();
    return {format:value.format, notes_dir:value.notes_dir};
  } catch { throw new Error('notes_config_invalid'); }
}

// Every component under the root must be a real entry, never a symlink or junction.
function notesEntry(root, parts) {
  let stat, real;
  try { stat = notesFs.lstatSync(root); } catch { notesFail('notes_dir_unavailable'); }
  if (stat.isSymbolicLink() || !stat.isDirectory()) notesFail('notes_path_forbidden');
  // The configured root itself may be spelled differently from its real path (8.3 short names on
  // Windows); below the root, every component is checked against the real root.
  try { real = notesFs.realpathSync.native(root); } catch { notesFail('notes_dir_unavailable'); }
  let current = root;
  for (const part of parts) {
    current = notesPath.join(current, part);
    try { stat = notesFs.lstatSync(current); }
    catch (error) { notesFail(error.code === 'ENOENT' ? 'notes_file_missing' : 'notes_dir_unavailable'); }
    if (stat.isSymbolicLink()) notesFail('notes_path_forbidden');
  }
  if (!stat.isFile()) notesFail('notes_path_forbidden');
  let resolved;
  try { resolved = notesFs.realpathSync.native(current); } catch { notesFail('notes_dir_unavailable'); }
  if (!notesSameRoot(resolved, notesPath.join(real, ...parts))) notesFail('notes_path_forbidden');
  return current;
}
function notesRead(root, parts, limit) {
  const file = notesEntry(root, parts);
  let fd;
  try {
    fd = notesFs.openSync(file, 'r');
    const stat = notesFs.fstatSync(fd);
    if (!stat.isFile()) notesFail('notes_path_forbidden');
    if (stat.size > limit) notesFail('notes_file_too_large');
    const bytes = notesFs.readFileSync(fd);
    if (bytes.length > limit) notesFail('notes_file_too_large');
    return bytes.toString('utf8').replace(/^﻿/, '');
  } catch (error) {
    if (error instanceof NotesInputError) throw error;
    notesFail('notes_dir_unavailable');
  } finally { if (fd !== undefined) notesFs.closeSync(fd); }
}

const notesValidDate = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)
  && new Date(value + 'T00:00:00Z').toISOString().slice(0, 10) === value;
const notesShiftDay = (date, delta) => { const d = new Date(date + 'T00:00:00Z'); d.setUTCDate(d.getUTCDate() + delta); return d.toISOString().slice(0, 10); };
// The diary day (04:00 boundary, Asia/Shanghai) that a moment belongs to.
export function notesDayOf(time) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-CA', {timeZone:NOTES_TIME_ZONE, year:'numeric', month:'2-digit', day:'2-digit',
    hour:'2-digit', hourCycle:'h23'}).formatToParts(new Date(time)).map(part => [part.type, part.value]));
  const date = `${parts.year}-${parts.month}-${parts.day}`;
  return Number(parts.hour) < NOTES_DAY_START_HOUR ? notesShiftDay(date, -1) : date;
}

// index.json written by notes_mirror (format notes-v1). Entries that do not look right are dropped, not trusted.
export function loadNotesIndex(notesDir) {
  let index;
  try { index = JSON.parse(notesRead(notesDir, ['index.json'], NOTES_LIMITS.index)); }
  catch (error) { if (error instanceof NotesInputError) throw error; notesFail('notes_index_invalid'); }
  if (!notesObject(index) || index.format !== 'notes-v1' || !notesObject(index.docs) || !Array.isArray(index.folders)) notesFail('notes_index_invalid');
  const folders = index.folders.filter(f => notesObject(f) && typeof f.name === 'string' && typeof f.dir === 'string').map(f => ({name:f.name, dir:f.dir}));
  const byDir = new Map(folders.map(f => [f.dir, f.name]));
  const docs = [];
  for (const [token, d] of Object.entries(index.docs)) {
    if (!NOTES_TOKEN.test(token) || !notesObject(d) || typeof d.file !== 'string' || !NOTES_FILE.test(d.file) || !byDir.has(d.top)
      || d.file !== `${d.top}/${token}.md` || typeof d.title !== 'string' || typeof d.modified !== 'string' || !Number.isFinite(Date.parse(d.modified))) continue;
    docs.push({token, title:d.title, top:byDir.get(d.top), folder:typeof d.folder === 'string' ? d.folder : byDir.get(d.top),
      modified:d.modified, day:notesDayOf(Date.parse(d.modified)), url:typeof d.url === 'string' ? d.url : null,
      chars:Number.isSafeInteger(d.chars) ? d.chars : null, synced_at:typeof d.synced_at === 'string' ? d.synced_at : null, file:d.file});
  }
  docs.sort((a, b) => Date.parse(b.modified) - Date.parse(a.modified) || a.token.localeCompare(b.token));
  const lastRun = notesObject(index.last_run) && typeof index.last_run.at === 'string' ? index.last_run.at : null;
  return {folders:folders.map(f => f.name), docs, synced_at:lastRun};
}

// Body of a mirrored document without its front matter.
export function readNoteBody(notesDir, doc) {
  const text = notesRead(notesDir, doc.file.split('/'), NOTES_LIMITS.file).replace(/\r\n/g, '\n');
  if (!text.startsWith('---\n')) return text;
  const end = text.indexOf('\n---\n', 4);
  return end < 0 ? text : text.slice(end + 5).replace(/^\n/, '');
}

const notesPublic = doc => ({token:doc.token, title:doc.title, folder:doc.folder, top:doc.top, modified:doc.modified, day:doc.day, url:doc.url, chars:doc.chars});
const notesClip = (text, n) => { const c = [...text.replace(/\s+/g, ' ').trim()]; return c.length > n ? c.slice(0, n).join('') + '…' : c.join(''); };
function notesFolderFilter(index, folder) {
  if (folder === undefined) return () => true;
  if (typeof folder !== 'string' || !folder.trim() || [...folder].length > 100) notesFail('invalid_notes_folder');
  if (!index.folders.includes(folder.trim())) notesFail('notes_folder_not_found');
  return doc => doc.top === folder.trim();
}

// Documents last modified on a diary day (04:00 boundary), with full bodies. For the daily summary job.
export function notesByDate(notesDir, date) {
  if (!notesValidDate(date)) notesFail('invalid_notes_date');
  const index = loadNotesIndex(notesDir);
  return {date, synced_at:index.synced_at, docs:index.docs.filter(doc => doc.day === date).map(doc => ({...notesPublic(doc), content:readNoteBody(notesDir, doc)}))};
}

export function notesRecent(notesDir, {days, date, folder} = {}, now = Date.now()) {
  if (days !== undefined && date !== undefined) notesFail('invalid_request');
  if (days !== undefined && (!Number.isSafeInteger(days) || days < 1 || days > NOTES_LIMITS.recentDays)) notesFail('invalid_notes_days');
  if (date !== undefined && !notesValidDate(date)) notesFail('invalid_notes_date');
  const index = loadNotesIndex(notesDir), inFolder = notesFolderFilter(index, folder), today = notesDayOf(now);
  const from = date ?? notesShiftDay(today, -((days ?? 3) - 1)), to = date ?? today;
  const docs = index.docs.filter(doc => inFolder(doc) && doc.day >= from && doc.day <= to).map(doc => {
    let preview = null;
    try { preview = notesClip(readNoteBody(notesDir, doc), 120); } catch (error) { if (!(error instanceof NotesInputError)) throw error; }
    return {...notesPublic(doc), preview};
  });
  return {today, from, to, synced_at:index.synced_at, folders:index.folders, docs};
}

export function notesSearch(notesDir, {query, folder, limit} = {}) {
  if (typeof query !== 'string' || !query.trim() || [...query].length > 100 || /[\0\r\n]/.test(query)) notesFail('invalid_notes_query');
  if (limit !== undefined && (!Number.isSafeInteger(limit) || limit < 1 || limit > NOTES_LIMITS.searchHits)) notesFail('invalid_notes_limit');
  const index = loadNotesIndex(notesDir), inFolder = notesFolderFilter(index, folder), needle = query.trim().toLowerCase(), max = limit ?? 10;
  const hits = [];
  for (const doc of index.docs) {
    if (!inFolder(doc)) continue;
    let body;
    try { body = readNoteBody(notesDir, doc); } catch (error) { if (error instanceof NotesInputError) continue; throw error; }
    const inTitle = doc.title.toLowerCase().includes(needle), at = body.toLowerCase().indexOf(needle);
    if (!inTitle && at < 0) continue;
    let snippet = null;
    if (at >= 0) {
      const before = [...body.slice(0, at)], after = [...body.slice(at)];
      snippet = (before.length > NOTES_LIMITS.snippet ? '…' : '') + before.slice(-NOTES_LIMITS.snippet).join('') + after.slice(0, [...query.trim()].length + NOTES_LIMITS.snippet).join('') + (after.length > [...query.trim()].length + NOTES_LIMITS.snippet ? '…' : '');
      snippet = snippet.replace(/\s+/g, ' ');
    }
    hits.push({...notesPublic(doc), in_title:inTitle, snippet});
    if (hits.length >= max) break;
  }
  return {query:query.trim(), synced_at:index.synced_at, hits};
}

export function notesReadDoc(notesDir, {token, offset} = {}) {
  if (typeof token !== 'string' || !NOTES_TOKEN.test(token)) notesFail('invalid_notes_token');
  if (offset !== undefined && (!Number.isSafeInteger(offset) || offset < 0)) notesFail('invalid_notes_offset');
  const index = loadNotesIndex(notesDir), doc = index.docs.find(item => item.token === token);
  if (!doc) notesFail('notes_doc_not_found');
  const chars = [...readNoteBody(notesDir, doc)], start = offset ?? 0;
  if (start > chars.length) notesFail('invalid_notes_offset');
  const end = Math.min(chars.length, start + NOTES_LIMITS.readChars);
  return {...notesPublic(doc), synced_at:index.synced_at, total_chars:chars.length, offset:start, content:chars.slice(start, end).join(''), next_offset:end < chars.length ? end : null};
}

// Short "recently written" lines for i_context: titles and days only, newest first, about 200 characters.
// Replaced by the daily summary once that exists. Returns null when there is nothing recent or no mirror.
export function notesContextLines(notesDir, now = Date.now(), days = 3) {
  let recent;
  try { recent = notesRecent(notesDir, {days}, now); } catch (error) { if (error instanceof NotesInputError) return null; throw error; }
  if (!recent.docs.length) return null;
  const lines = [];let used = 0;
  for (const doc of recent.docs) {
    const line = `${doc.day.slice(5)} ${doc.top}：${notesClip(doc.title, 40)}`;
    if (used + line.length > NOTES_LIMITS.contextChars && lines.length) { lines.push(`……另有 ${recent.docs.length - lines.length} 篇`); break; }
    lines.push(line);used += line.length;
  }
  return {heading:'最近写的日记和工作文档（可用 notes_recent / notes_read 读全文）', lines, synced_at:recent.synced_at};
}

function notesArgs(args, allowed, required = []) {
  if (!notesObject(args) || Object.keys(args).some(key => !allowed.includes(key)) || required.some(key => !Object.hasOwn(args, key))) notesFail('invalid_request');
}
export function createNotesTools({notesDir, now = () => Date.now()}) {
  if (typeof notesDir !== 'string' || !notesPath.isAbsolute(notesDir)) throw new Error('invalid_notes_configuration');
  const handlers = {
    async notes_recent(args = {}) { notesArgs(args, ['days', 'date', 'folder']); return notesRecent(notesDir, args, now()); },
    async notes_search(args = {}) { notesArgs(args, ['query', 'folder', 'limit'], ['query']); return notesSearch(notesDir, args); },
    async notes_read(args = {}) { notesArgs(args, ['token', 'offset'], ['token']); return notesReadDoc(notesDir, args); },
  };
  return {tools:NOTES_TOOLS, handlers};
}
