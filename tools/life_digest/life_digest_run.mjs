#!/usr/bin/env node
// M1 daily life digest generator, run by a scheduled task at 04:30, 07:30 and 19:30 (and at logon to catch up).
//   node life_digest_run.mjs --config <generator.json> [--stage auto|morning|day|final] [--date YYYY-MM-DD] [--no-push] [--check]
// Reads chat (MCP sharing policy) and food from the Core database (read-only), heart-rate minute files, the Feishu notes mirror and
// AMap weather; writes <digest_dir>/days/<date>.json, todos.json, pushes/<date>.jsonl, weather/<date>.json and logs/.
// The model is the local Codex CLI (fixed model, JSON checked, one retry); the OpenAI API is only a fallback.
// Output: one JSON line per stage, never secrets or message text.
import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { appendFileSync, existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import * as lib from './life_digest_lib.mjs';
import { readChatRange } from './chat_source.mjs';
import { DatabaseSync } from 'node:sqlite';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const NOTES_MODULE = path.resolve(HERE, '..', 'i_remote_mcp', 'notes_tools.mjs');
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);

// ---------- config ----------
const absolute = (value, field, optional = false) => {
  if (optional && (value === undefined || value === null)) return null;
  if (typeof value !== 'string' || !path.isAbsolute(value) || value.includes('\0')) throw new Error('config_invalid:' + field);
  return path.resolve(value);
};
export function loadConfig(configPath) {
  let value;
  try { value = JSON.parse(readFileSync(configPath, 'utf8').replace(/^﻿/, '')); } catch { throw new Error('config_unreadable'); }
  if (!object(value) || value.format !== 'life-digest-generator-v1') throw new Error('config_invalid:format');
  const codex = value.codex;
  if (!object(codex) || !Array.isArray(codex.argv) || !codex.argv.length || codex.argv.some(a => typeof a !== 'string' || !a)
    || typeof codex.model !== 'string' || !/^[A-Za-z0-9._:-]{1,80}$/.test(codex.model)) throw new Error('config_invalid:codex');
  const ntfy = value.ntfy ?? null;
  if (ntfy !== null && (!object(ntfy) || !/^https:\/\/[^/\s]+$/.test(String(ntfy.server)) || !/^[A-Za-z0-9_-]{8,64}$/.test(String(ntfy.topic)))) throw new Error('config_invalid:ntfy');
  const weather = value.weather ?? null;
  if (weather !== null && (!object(weather) || !/^[0-9a-f]{32}$/i.test(String(weather.amap_key)) || !/^\d{6}$/.test(String(weather.adcode)))) throw new Error('config_invalid:weather');
  const openai = value.openai ?? null;
  if (openai !== null && (!object(openai) || typeof openai.model !== 'string' || !openai.model)) throw new Error('config_invalid:openai');
  return {
    digestDir: absolute(value.digest_dir, 'digest_dir'),
    chat: object(value.chat) ? { coreDb: absolute(value.chat.core_db, 'chat.core_db'), policy: absolute(value.chat.policy, 'chat.policy') } : null,
    heartRateDir: absolute(value.heart_rate_dir, 'heart_rate_dir', true),
    notesDir: absolute(value.notes_dir, 'notes_dir', true),
    weather: weather && { key: String(weather.amap_key), adcode: String(weather.adcode), label: typeof weather.label === 'string' ? weather.label : '' },
    codex: { argv: codex.argv, model: codex.model, extraArgs: Array.isArray(codex.extra_args) ? codex.extra_args.map(String) : [],
      timeoutMs: Math.min(30, Math.max(1, Number(codex.timeout_minutes) || 8)) * 60000 },
    openai: openai && { model: openai.model, keyFile: absolute(openai.api_key_file, 'openai.api_key_file', true), keyEnv: typeof openai.api_key_env === 'string' ? openai.api_key_env : 'OPENAI_API_KEY' },
    ntfy: ntfy && { server: String(ntfy.server), topic: String(ntfy.topic), max: Math.min(5, Math.max(0, Number(ntfy.max_per_day ?? lib.LIMITS.pushesPerDay))) },
  };
}

// ---------- digest directory ----------
export function openStore(root) {
  for (const dir of ['', 'days', 'inbox', 'pushes', 'weather', 'logs', 'work']) {
    const p = path.join(root, dir);
    if (!existsSync(p)) mkdirSync(p, { recursive: true });
    if (lstatSync(p).isSymbolicLink() || !lstatSync(p).isDirectory()) throw new Error('digest_dir_invalid');
  }
  const file = (...parts) => path.join(root, ...parts);
  const readJson = (p, fallback = null) => { try { return JSON.parse(readFileSync(p, 'utf8').replace(/^﻿/, '')); } catch (error) { if (error.code === 'ENOENT') return fallback; throw new Error('digest_file_invalid:' + path.basename(p)); } };
  const writeJson = (p, value) => { const tmp = p + '.' + randomBytes(4).toString('hex') + '.tmp'; writeFileSync(tmp, JSON.stringify(value, null, 1) + '\n', { mode: 0o600 }); renameSync(tmp, p); };
  return {
    root, file, readJson, writeJson,
    day: date => readJson(file('days', date + '.json')),
    saveDay(date, patch) {
      const prior = this.day(date) ?? { format: 'life-digest-day-v1', date, stage: null, generated_at: null, generator: null, morning: null, day: null, todos: [], sources_status: {} };
      const next = { ...prior, ...patch };
      writeJson(file('days', date + '.json'), next);
      return next;
    },
    todos: () => { const value = readJson(file('todos.json')); return value && Array.isArray(value.items) ? value : lib.emptyTodos(); },
    saveTodos: value => writeJson(file('todos.json'), value),
    inbox() {
      const out = [];
      for (const name of readdirSync(file('inbox'))) {
        if (!/^todo-\d{13}-[0-9a-f]{8}\.json$/.test(name)) continue;
        try { const v = readJson(file('inbox', name)); if (v?.format === 'life-todo-inbox-v1' && typeof v.id === 'string') out.push({ ...v, name }); } catch { /* skipped below */ }
      }
      return out.sort((a, b) => a.name.localeCompare(b.name));
    },
    clearInbox: names => { for (const name of names) rmSync(file('inbox', name), { force: true }); },
    pushes(date) {
      try { return readFileSync(file('pushes', date + '.jsonl'), 'utf8').split(/\r?\n/).filter(Boolean).map(l => JSON.parse(l)); }
      catch (error) { if (error.code === 'ENOENT') return []; throw error; }
    },
    addPush: (date, row) => appendFileSync(file('pushes', date + '.jsonl'), JSON.stringify(row) + '\n', { mode: 0o600 }),
    log: row => appendFileSync(file('logs', 'run-' + row.at.slice(0, 7) + '.jsonl'), JSON.stringify(row) + '\n'),
    lock() {
      const p = file('work', 'run.lock');
      try { if (Date.now() - statSync(p).mtimeMs > 45 * 60000) rmSync(p, { force: true }); } catch { /* no lock */ }
      try { writeFileSync(p, String(process.pid), { flag: 'wx' }); } catch { throw new Error('already_running'); }
      return () => rmSync(p, { force: true });
    },
  };
}
const hasPart = st => (date, part) => {
  const d = st.day(date);
  if (!d) return false;
  if (part === 'morning') return Boolean(d.morning);
  if (part === 'final') return d.stage === 'final' && Boolean(d.day);
  return Boolean(d.day);
};

// ---------- sources ----------
// Food straight from the Core database, read-only (production namespace, live records, this local day).
function readFood(config, date) {
  if (!config.chat) return { status: 'not_configured' };
  const db = new DatabaseSync(config.chat.coreDb, { readOnly: true });
  try {
    const rows = db.prepare("SELECT envelope_json, body_json FROM domain_records WHERE namespace = 'production' AND domain = 'food_entries'").all();
    const entries = [];
    for (const row of rows) {
      let envelope, body;
      try { envelope = JSON.parse(row.envelope_json); body = row.body_json ? JSON.parse(row.body_json) : null; } catch { continue; }
      const data = body?.data;
      if (envelope?.deleted_at || !object(data) || data.voided === true || data.local_date !== date) continue;
      entries.push(data);
    }
    entries.sort((a, b) => Date.parse(a.eaten_at) - Date.parse(b.eaten_at));
    return { status: 'ok', entries, day_totals: { kcal: entries.reduce((sum, e) => sum + (Number(e.totals?.kcal) || 0), 0) } };
  } catch (error) {
    if (/no such table/.test(String(error?.message))) return { status: 'ok', entries: [], day_totals: { kcal: 0 } };
    throw error;
  } finally { db.close(); }
}
function readHeart(config, date) {
  if (!config.heartRateDir) return { status: 'not_configured', rows: [] };
  const [from, to] = lib.dayRange(date), rows = [];
  for (const d of [date, lib.addDays(date, 1)]) {
    const p = path.join(config.heartRateDir, `minutes-${d}.jsonl`);
    if (!existsSync(p)) continue;
    for (const line of readFileSync(p, 'utf8').split(/\r?\n/)) {
      try { const row = JSON.parse(line); if (row.ms >= from && row.ms < to) rows.push(row); } catch { /* partial line */ }
    }
  }
  return { status: 'ok', rows };
}
async function readNotes(config, date) {
  if (!config.notesDir) return { status: 'not_configured', docs: [] };
  if (!existsSync(NOTES_MODULE)) return { status: 'module_missing', docs: [] };
  const notes = await import(pathToFileURL(NOTES_MODULE));
  const result = notes.notesByDate(config.notesDir, date);
  return { status: 'ok', docs: result.docs, synced_at: result.synced_at };
}
async function readWeather(config, st, date) {
  if (!config.weather) return { status: 'not_configured', text: null };
  const url = new URL('https://restapi.amap.com/v3/weather/weatherInfo');
  url.searchParams.set('key', config.weather.key); url.searchParams.set('city', config.weather.adcode); url.searchParams.set('extensions', 'all');
  const response = await fetch(url, { redirect: 'error', signal: AbortSignal.timeout(15000) });
  const casts = lib.parseAmapForecast(await response.json());
  const today = casts.find(c => c.date === date) ?? null;
  st.writeJson(st.file('weather', date + '.json'), { format: 'life-digest-weather-v1', date, adcode: config.weather.adcode, fetched_at: lib.isoLocal(Date.now()), today, casts });
  const prior = st.readJson(st.file('weather', lib.addDays(date, -1) + '.json'));
  return { status: today ? 'ok' : 'no_forecast', text: lib.weatherText(today, prior?.today ?? null, config.weather.label) };
}
async function settle(name, fn) {
  try { return await fn(); } catch (error) { return { status: 'error', error: String(error?.message ?? error).replace(/[^\w:.-]/g, '').slice(0, 80) }; }
}

// ---------- model ----------
function runCodex(config, prompt, st) {
  const out = st.file('work', `codex-${Date.now()}-${randomBytes(3).toString('hex')}.txt`);
  const [file, ...prefix] = config.codex.argv;
  const args = [...prefix, 'exec', '--model', config.codex.model, '--sandbox', 'read-only', '--skip-git-repo-check', '--color', 'never',
    ...config.codex.extraArgs, '--output-last-message', out, '-'];
  return new Promise((resolve, reject) => {
    const child = spawn(file, args, { cwd: st.file('work'), windowsHide: true, stdio: ['pipe', 'ignore', 'pipe'] });
    let stderr = '';
    const timer = setTimeout(() => { child.kill(); }, config.codex.timeoutMs);
    child.stderr.on('data', chunk => { stderr = (stderr + chunk).slice(-2000); });
    child.on('error', error => { clearTimeout(timer); reject(new Error('codex_spawn_failed:' + error.code)); });
    child.on('close', code => {
      clearTimeout(timer);
      let text = null;
      try { text = readFileSync(out, 'utf8'); } catch { /* no output */ }
      rmSync(out, { force: true });
      if (code !== 0 || !text) return reject(new Error('codex_failed:' + code));
      resolve(text);
    });
    child.stdin.end(prompt);
  });
}
async function runOpenAI(config, prompt) {
  const key = config.openai.keyFile ? readFileSync(config.openai.keyFile, 'utf8').trim() : process.env[config.openai.keyEnv];
  if (!key) throw new Error('openai_key_missing');
  const response = await fetch('https://api.openai.com/v1/chat/completions', { method: 'POST', signal: AbortSignal.timeout(180000),
    headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json' },
    body: JSON.stringify({ model: config.openai.model, response_format: { type: 'json_object' }, messages: [{ role: 'user', content: prompt }] }) });
  const body = await response.json();
  const text = body?.choices?.[0]?.message?.content;
  if (response.status !== 200 || typeof text !== 'string') throw new Error('openai_failed:' + response.status);
  return text;
}
// Codex twice (the second time with the validation error), then the API once if configured.
export async function generate({ config, st, prompt, validate, runners = { codex: runCodex, openai: runOpenAI } }) {
  const errors = [];
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const fix = attempt && errors.length ? `\n\n上一次的输出不合格（${errors.at(-1)}），请严格按格式只输出 JSON。` : '';
      return { value: validate(lib.parseModelJson(await runners.codex(config, prompt + fix, st))), generator: 'codex', errors };
    } catch (error) { errors.push(String(error.message).slice(0, 80)); }
  }
  if (config.openai) {
    try { return { value: validate(lib.parseModelJson(await runners.openai(config, prompt))), generator: 'openai', errors }; }
    catch (error) { errors.push(String(error.message).slice(0, 80)); }
  }
  const failure = new Error('generation_failed'); failure.errors = errors; throw failure;
}

async function sendNtfy(config, text) {
  const response = await fetch(config.ntfy.server, { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(15000),
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ topic: config.ntfy.topic, title: '林埃', message: text, tags: ['two_hearts'], priority: 4 }) });
  if (response.status !== 200) throw new Error('ntfy_failed:' + response.status);
}

// ---------- stages ----------
export async function runStage({ config, st, kind, date, nowMs, push = true, runners, notify = sendNtfy }) {
  const nowIso = lib.isoLocal(nowMs);
  if (kind === 'morning') {
    const weather = await settle('weather', () => readWeather(config, st, date));
    const y = st.day(lib.addDays(date, -1));
    const merged = lib.mergeTodos(st.todos(), { date, nowIso, inbox: st.inbox() });
    const todos = lib.openTodos(merged.state, date);
    const input = { weather: weather.text ?? null, yesterday: y?.day?.headline ?? null, todos };
    let text, generator;
    try { ({ value: { broadcast: text }, generator } = await generate({ config, st, prompt: lib.buildMorningPrompt({ date, ...input }), validate: lib.validateMorningOutput, runners })); }
    catch { text = lib.fallbackMorning(input); generator = 'template'; }
    st.saveDay(date, { stage: st.day(date)?.day ? st.day(date).stage : 'morning', generated_at: nowIso,
      morning: { text, weather: input.weather, generated_at: nowIso, generator }, failed: null,
      sources_status: { ...(st.day(date)?.sources_status ?? {}), weather: weather.status } });
    return { stage: kind, date, ok: true, generator, weather: weather.status };
  }

  const [from, to] = lib.dayRange(date);
  const until = kind === 'final' ? to : Math.min(to, nowMs);
  const chat = await settle('chat', async () => config.chat
    ? { status: 'ok', ...readChatRange({ coreDbPath: config.chat.coreDb, policyPath: config.chat.policy, fromMs: from, toMs: until }) } : { status: 'not_configured', messages: [] });
  const food = await settle('food', async () => readFood(config, date));
  const heart = await settle('heart_rate', async () => readHeart(config, date));
  const notes = await settle('notes', () => readNotes(config, date));
  const status = { chat: chat.status, food: food.status, heart_rate: heart.status, notes: notes.status };

  const inbox = st.inbox();
  const before = lib.mergeTodos(st.todos(), { date, nowIso, inbox });
  const open = lib.openTodos(before.state, date);
  const stale = lib.staleTodos(before.state, date);
  const triggers = lib.nudgeTriggers({ kind, food: food.status === 'ok' ? food : null, stale });
  const pushesToday = st.pushes(date).length;
  const wantNudge = push && Boolean(config.ntfy) && triggers.length > 0 && lib.canPush({ pushesToday, nowMs, max: config.ntfy?.max });

  const chatPart = lib.chatText(chat.messages ?? []);
  const notesPart = lib.notesText(notes.docs ?? []);
  const foodPart = lib.foodText(date, food.status === 'ok' ? food : null);
  const heartPart = lib.heartText(date, heart.rows ?? []);
  const sources = [...chatPart.sources, ...notesPart.sources, ...foodPart.sources, ...heartPart.sources];
  const prompt = lib.buildDayPrompt({ date, kind, nowIso, chat: chatPart, notes: { ...notesPart, status: notes.status },
    food: { ...foodPart, status: food.status }, heart: heartPart, todos: open, triggers: wantNudge ? triggers : [] });

  if (!sources.length && !open.length) {
    // Nothing recorded at all (computer off, no chat): no model call, just say so.
    st.saveDay(date, { stage: kind, generated_at: nowIso, generator: 'none', failed: null, todos: [], sources_status: { ...(st.day(date)?.sources_status ?? {}), ...status },
      day: { headline: '这天没有聊天、日记、饮食或心率记录。', your_day: [], us: [], anomalies: [], omitted: [] } });
    return { stage: kind, date, ok: true, generator: 'none', sources: status };
  }
  let result;
  try {
    result = await generate({ config, st, prompt, runners,
      validate: value => lib.validateDayOutput(value, { sources, openIds: open.map(t => t.id), wantNudge }) });
  } catch (error) {
    // Keep whatever was there, mark the failure; the snapshot says the digest is missing instead of reusing an old one.
    st.saveDay(date, { failed: { stage: kind, at: nowIso, reasons: error.errors ?? [String(error.message)] }, sources_status: status });
    if (inbox.length) { st.saveTodos(before.state); st.clearInbox(inbox.map(a => a.name)); }
    return { stage: kind, date, ok: false, detail: 'generation_failed', sources: status };
  }
  const { value, generator } = result;
  const after = lib.mergeTodos(before.state, { date, nowIso, doneIds: value.todos_done, newTodos: value.todos_new });
  let pushed = null;
  if (wantNudge) {
    const text = value.nudge || lib.fallbackNudge(triggers, date);
    try {
      await notify(config, text);
      const id = 'p_' + date.replaceAll('-', '') + '_' + randomBytes(4).toString('hex');
      st.addPush(date, { id, at: nowIso, rules: triggers.map(t => t.rule), text });
      const asked = new Set(triggers.flatMap(t => t.ids ?? []));
      for (const item of after.state.items) if (asked.has(item.id)) item.asked_at = nowIso;
      pushed = triggers.map(t => t.rule);
    } catch (error) { pushed = 'failed:' + String(error.message).slice(0, 40); }
  }
  st.saveTodos(after.state);
  st.clearInbox(inbox.map(a => a.name));
  const { todos_new: _n, todos_done: _d, nudge: _u, ...day } = value;
  st.saveDay(date, { stage: kind, generated_at: nowIso, generator, day, failed: null,
    todos: lib.openTodos(after.state, date).map(({ id, text, first_seen, days_open, source }) => ({ id, text, first_seen, days_open, source })),
    sources_status: { ...(st.day(date)?.sources_status ?? {}), ...status } });
  return { stage: kind, date, ok: true, generator, sources: status, todos: { added: after.changed.added.length, done: before.changed.done.length + after.changed.done.length },
    pushed, retries: result.errors.length };
}

export async function main(argv, { now = () => Date.now(), runners, notify } = {}) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const key = argv[i];
    if (key === '--no-push' || key === '--check') args[key.slice(2)] = true;
    else if (['--config', '--stage', '--date'].includes(key)) args[key.slice(2)] = argv[++i];
    else throw new Error('usage');
  }
  if (!args.config) throw new Error('usage');
  const config = loadConfig(path.resolve(args.config));
  const st = openStore(config.digestDir);
  if (args.check) {
    const rows = { chat: config.chat ? existsSync(config.chat.coreDb) && existsSync(config.chat.policy) : 'not_configured',
heart_rate: config.heartRateDir ? existsSync(config.heartRateDir) : 'not_configured',
      notes: config.notesDir ? existsSync(config.notesDir) && existsSync(NOTES_MODULE) : 'not_configured', weather: Boolean(config.weather), ntfy: Boolean(config.ntfy), openai: Boolean(config.openai) };
    return [{ stage: 'check', ok: true, ...rows }];
  }
  const release = st.lock();
  try {
    const nowMs = now();
    let stages;
    if (!args.stage || args.stage === 'auto') stages = lib.dueStages(nowMs, hasPart(st));
    else {
      if (!['morning', 'day', 'final'].includes(args.stage) || (args.date !== undefined && !lib.validDate(args.date))) throw new Error('usage');
      stages = [{ kind: args.stage, date: args.date ?? (args.stage === 'final' ? lib.addDays(lib.dayOf(nowMs), -1) : lib.dayOf(nowMs)) }];
    }
    const out = [];
    for (const stage of stages) {
      const row = await runStage({ config, st, ...stage, nowMs: now(), push: !args['no-push'], runners, notify })
        .catch(error => ({ stage: stage.kind, date: stage.date, ok: false, detail: String(error.message).slice(0, 80) }));
      st.log({ at: lib.isoLocal(now()), ...row });
      out.push(row);
    }
    if (!out.length) out.push({ stage: 'none', ok: true, detail: 'nothing_due' });
    return out;
  } finally { release(); }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).then(rows => {
    for (const row of rows) process.stdout.write(JSON.stringify(row) + '\n');
    process.exitCode = rows.every(row => row.ok) ? 0 : 1;
  }, error => { process.stdout.write(JSON.stringify({ stage: 'start', ok: false, detail: String(error.message).slice(0, 80) }) + '\n'); process.exitCode = 1; });
}
