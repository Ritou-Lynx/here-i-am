// HR1 heart-rate channel. Self-contained (node: imports only) so the legacy candidate can inline this file verbatim.
// The phone pushes 1 Hz samples to a 127.0.0.1 listener that is reachable only through `tailscale serve`;
// requests are accepted only when Tailscale-User-Login is on the configured list. The last 15 minutes stay in
// memory; completed minutes are appended to <stateDir>/heart_rate/minutes-YYYY-MM-DD.jsonl and kept 14 days.
import * as hrFs from 'node:fs';
import * as hrPath from 'node:path';
import * as hrHttp from 'node:http';

export class HeartRateInputError extends Error {}
const hrFail = code => { throw new HeartRateInputError(code); };
const hrObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
export const HEART_RATE_FRONTENDS = Object.freeze(['claude_web', 'chatgpt_web', 'antigravity', 'sesame']);
export const HEART_RATE_DEFAULT_PORT = 47866;
const HR_OFFSET_MS = 8 * 3600 * 1000; // Asia/Shanghai, no DST.
const HR_LIMITS = Object.freeze({body:16 * 1024, batch:300, ringMs:15 * 60 * 1000, ringSamples:4000, liveMs:15 * 1000,
  futureMs:60 * 1000, pastMs:24 * 3600 * 1000, retentionDays:14, fileBytes:4 * 1024 * 1024, rangeMs:12 * 3600 * 1000,
  flushGraceMs:15 * 1000, minBpm:30, maxBpm:220, logins:8});
const hrReadOnly = {readOnlyHint:true, destructiveHint:false, idempotentHint:true, openWorldHint:false};
export const HEART_RATE_TOOLS = Object.freeze([
  {name:'heart_rate', requiredScope:'i.read',
    description:'读取用户臂带心率（手机经 tailnet 实时推到家里电脑）。mode=now（默认）：最新读数、距今秒数、是否实时（live，15 秒内）、最近 1/5/15 分钟的中位/最低/最高、最近 5 分钟每 30 秒的走势、过去 7 天同一小时的平常水平；mode=range：start/end 为带时区的 ISO 时间，跨度不超过 12 小时，默认最近 60 分钟，返回每分钟汇总；mode=night：night=YYYY-MM-DD，返回当晚 18:00 到次日 12:00 的每 5 分钟汇总和最低 30 分钟均值。需要跟着心跳变化时可以每轮调一次 now。只给读数和走势：不做医学诊断，不凭心率断言用户的情绪、是否睡着或身体状况；live 为 false 时如实说臂带现在没在线，不要把旧读数当成现在。',
    inputSchema:{type:'object', properties:{
      mode:{type:'string', enum:['now', 'range', 'night'], description:'默认 now。'},
      start:{type:'string', maxLength:40, description:'mode=range：起点，带时区的 ISO 时间，如 2026-11-05T21:00:00+08:00。'},
      end:{type:'string', maxLength:40, description:'mode=range：终点，默认现在。'},
      night:{type:'string', minLength:10, maxLength:10, description:'mode=night：夜晚的日期（当晚 18:00 起）。'},
    }, additionalProperties:false}, annotations:hrReadOnly},
]);

export function loadHeartRateConfig(stateDir) {
  let text;
  try { text = hrFs.readFileSync(hrPath.resolve(stateDir, 'heart_rate.json'), 'utf8'); }
  catch (error) { if (error.code === 'ENOENT') return null; throw new Error('heart_rate_config_invalid'); }
  try {
    const value = JSON.parse(text.replace(/^﻿/, ''));
    const logins = value?.tailscale_logins;
    if (!hrObject(value) || Object.keys(value).length !== 2 || value.format !== 'heart-rate-v1' || !Array.isArray(logins)
      || logins.length < 1 || logins.length > HR_LIMITS.logins
      || logins.some(login => typeof login !== 'string' || !/^[^\s\0-\x1f\x7f]{1,254}$/.test(login))) throw new Error();
    return {format:value.format, tailscale_logins:logins.map(login => login.toLowerCase())};
  } catch { throw new Error('heart_rate_config_invalid'); }
}

// ---------- time (fixed +08:00) ----------
const hrPad = value => String(value).padStart(2, '0');
function hrLocal(ms) {
  const d = new Date(ms + HR_OFFSET_MS);
  return {date:`${d.getUTCFullYear()}-${hrPad(d.getUTCMonth() + 1)}-${hrPad(d.getUTCDate())}`,
    time:`${hrPad(d.getUTCHours())}:${hrPad(d.getUTCMinutes())}:${hrPad(d.getUTCSeconds())}`, hour:d.getUTCHours()};
}
const hrIso = ms => { const local = hrLocal(ms); return `${local.date}T${local.time}+08:00`; };
const hrValidDate = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)
  && Number.isFinite(Date.parse(value + 'T00:00:00Z')) && new Date(value + 'T00:00:00Z').toISOString().slice(0, 10) === value;
const hrMidnight = date => Date.parse(date + 'T00:00:00+08:00');
const hrAddDays = (date, delta) => hrLocal(hrMidnight(date) + delta * 86400000 + 12 * 3600000).date;
function hrParseTime(value, code) {
  if (typeof value !== 'string' || value.length > 40 || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) hrFail(code);
  const ms = Date.parse(value);
  if (!Number.isFinite(ms)) hrFail(code);
  return ms;
}

// ---------- stats ----------
function hrMedian(values) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b), mid = sorted.length >> 1;
  return sorted.length % 2 ? sorted[mid] : Math.round((sorted[mid - 1] + sorted[mid]) / 2 * 10) / 10;
}
function hrStats(values) {
  if (!values.length) return null;
  return {median:hrMedian(values), min:Math.min(...values), max:Math.max(...values), samples:values.length};
}

// ---------- files ----------
function hrSameRoot(a, b) { return process.platform === 'win32' ? a.toLowerCase() === b.toLowerCase() : a === b; }
function hrDataDir(stateDir) {
  const dir = hrPath.resolve(stateDir, 'heart_rate');
  let stat;
  try { stat = hrFs.lstatSync(dir); }
  catch (error) {
    if (error.code !== 'ENOENT') throw new Error('heart_rate_dir_invalid');
    try { hrFs.mkdirSync(dir, {mode:0o700}); stat = hrFs.lstatSync(dir); } catch { throw new Error('heart_rate_dir_invalid'); }
  }
  if (stat.isSymbolicLink() || !stat.isDirectory()) throw new Error('heart_rate_dir_invalid');
  let real;
  try { real = hrFs.realpathSync.native(dir); } catch { throw new Error('heart_rate_dir_invalid'); }
  const parent = hrFs.realpathSync.native(hrPath.resolve(stateDir));
  if (!hrSameRoot(real, hrPath.join(parent, 'heart_rate'))) throw new Error('heart_rate_dir_invalid');
  return dir;
}
const hrFileName = date => `minutes-${date}.jsonl`;
// Returns the file path only if it is absent or a regular file (never a link).
function hrFilePath(dir, date) {
  const path = hrPath.join(dir, hrFileName(date));
  try { const stat = hrFs.lstatSync(path); if (stat.isSymbolicLink() || !stat.isFile()) return null; }
  catch (error) { if (error.code !== 'ENOENT') return null; }
  return path;
}
function hrReadRows(dir, date) {
  const path = hrFilePath(dir, date);
  if (!path) return [];
  let bytes;
  try {
    const stat = hrFs.statSync(path);
    if (stat.size > HR_LIMITS.fileBytes) return [];
    bytes = hrFs.readFileSync(path, 'utf8');
  } catch { return []; }
  const rows = [];
  for (const line of bytes.split('\n')) {
    if (!line.trim()) continue;
    try {
      const row = JSON.parse(line);
      if (hrObject(row) && Number.isSafeInteger(row.ms) && row.ms % 60000 === 0 && Number.isSafeInteger(row.n) && row.n > 0
        && [row.med, row.min, row.max].every(Number.isFinite)) rows.push({ms:row.ms, n:row.n, med:row.med, min:row.min, max:row.max});
    } catch { /* skip malformed line */ }
  }
  return rows;
}

// ---------- store ----------
export function createHeartRateStore({stateDir, now = () => Date.now()}) {
  const dir = hrDataDir(stateDir);
  const ring = [];
  let bucket = null, lastT = null, phone = null, prunedFor = null;

  function prune() {
    const today = hrLocal(now()).date;
    if (prunedFor === today) return;
    prunedFor = today;
    const oldest = hrAddDays(today, -HR_LIMITS.retentionDays);
    let names = [];
    try { names = hrFs.readdirSync(dir); } catch { return; }
    for (const name of names) {
      const match = /^minutes-(\d{4}-\d{2}-\d{2})\.jsonl$/.exec(name);
      if (!match || match[1] >= oldest) continue;
      const path = hrFilePath(dir, match[1]);
      if (path) { try { hrFs.unlinkSync(path); } catch { /* retry tomorrow */ } }
    }
  }
  function flush() {
    if (!bucket || !bucket.values.length) { bucket = null; return; }
    const values = bucket.values, row = {ms:bucket.ms, n:values.length, med:hrMedian(values), min:Math.min(...values), max:Math.max(...values)};
    bucket = null;
    const path = hrFilePath(dir, hrLocal(row.ms).date);
    if (!path) return;
    let fd;
    try { fd = hrFs.openSync(path, 'a', 0o600); hrFs.writeSync(fd, JSON.stringify(row) + '\n'); }
    catch { /* a lost minute must not break ingestion */ }
    finally { if (fd !== undefined) hrFs.closeSync(fd); }
    prune();
  }
  function tick() {
    if (bucket && now() >= bucket.ms + 60000 + HR_LIMITS.flushGraceMs) flush();
  }
  function trimRing() {
    const floor = (lastT ?? 0) - HR_LIMITS.ringMs;
    let drop = 0;
    while (drop < ring.length && (ring[drop].t < floor || ring.length - drop > HR_LIMITS.ringSamples)) drop++;
    if (drop) ring.splice(0, drop);
  }

  function ingest(body) {
    if (!hrObject(body) || Object.keys(body).some(key => !['format', 'device', 'status', 'samples'].includes(key))
      || body.format !== 'hr-samples-v1' || !Array.isArray(body.samples) || body.samples.length < 1 || body.samples.length > HR_LIMITS.batch
      || (body.device !== undefined && (typeof body.device !== 'string' || !/^[^\0-\x1f\x7f]{1,64}$/.test(body.device)))
      || (body.status !== undefined && (typeof body.status !== 'string' || !/^[A-Za-z]{1,32}$/.test(body.status)))) hrFail('invalid_request');
    if (body.samples.some(sample => !hrObject(sample) || Object.keys(sample).some(key => !['t', 'bpm'].includes(key))
      || !Number.isSafeInteger(sample.t) || !Number.isSafeInteger(sample.bpm))) hrFail('invalid_request');
    const t0 = now();
    let accepted = 0, duplicates = 0, rejected = 0;
    for (const sample of body.samples) {
      if (sample.bpm < HR_LIMITS.minBpm || sample.bpm > HR_LIMITS.maxBpm || sample.t > t0 + HR_LIMITS.futureMs || sample.t < t0 - HR_LIMITS.pastMs) { rejected++; continue; }
      if (lastT !== null && sample.t <= lastT) { duplicates++; continue; }
      const minute = sample.t - (((sample.t + HR_OFFSET_MS) % 60000) + 60000) % 60000;
      if (bucket && bucket.ms !== minute) flush();
      if (!bucket) bucket = {ms:minute, values:[]};
      bucket.values.push(sample.bpm);
      ring.push({t:sample.t, bpm:sample.bpm});
      lastT = sample.t;
      accepted++;
    }
    trimRing();
    phone = {device:body.device ?? phone?.device ?? null, status:body.status ?? null, received_at:t0};
    tick();
    return {accepted, duplicates, rejected, latest_t:lastT};
  }

  function minuteRows(start, end) {
    const byMs = new Map();
    for (let date = hrLocal(start).date; hrMidnight(date) < end; date = hrAddDays(date, 1)) {
      for (const row of hrReadRows(dir, date)) {
        if (row.ms < start || row.ms >= end) continue;
        const seen = byMs.get(row.ms);
        if (!seen || row.n > seen.n) byMs.set(row.ms, row);
      }
    }
    if (bucket && bucket.values.length && bucket.ms >= start && bucket.ms < end) {
      const values = bucket.values, seen = byMs.get(bucket.ms);
      if (!seen || values.length > seen.n) byMs.set(bucket.ms, {ms:bucket.ms, n:values.length, med:hrMedian(values), min:Math.min(...values), max:Math.max(...values), partial:true});
    }
    return [...byMs.values()].sort((a, b) => a.ms - b.ms);
  }

  function nowPayload() {
    tick();
    const t = now(), latest = ring.at(-1) ?? null;
    const since = ms => ring.filter(item => item.t > t - ms && item.t <= t).map(item => item.bpm);
    const trend = [];
    for (let start = t - 5 * 60000; start < t; start += 30000) {
      const values = ring.filter(item => item.t > start && item.t <= start + 30000).map(item => item.bpm);
      if (values.length) trend.push({at:hrLocal(start + 30000).time, bpm:hrMedian(values)});
    }
    const today = hrLocal(t), hourValues = [], days = new Set();
    for (let back = 1; back <= 7; back++) {
      const date = hrAddDays(today.date, -back), from = hrMidnight(date) + today.hour * 3600000;
      for (const row of minuteRows(from, from + 3600000)) { hourValues.push(row.med); days.add(date); }
    }
    const age = latest ? Math.max(0, Math.round((t - latest.t) / 1000)) : null;
    const live = Boolean(latest && t - latest.t <= HR_LIMITS.liveMs && t >= latest.t - HR_LIMITS.futureMs);
    return {now:hrIso(t),
      latest:latest ? {bpm:latest.bpm, at:hrIso(latest.t), age_seconds:age, live} : null,
      live,
      phone:phone ? {device:phone.device, status:phone.status, received_at:hrIso(phone.received_at)} : null,
      windows:{'1m':hrStats(since(60000)), '5m':hrStats(since(5 * 60000)), '15m':hrStats(since(15 * 60000))},
      trend_5m:trend,
      usual_this_hour:hourValues.length >= 10 ? {median:hrMedian(hourValues), days:days.size, minutes:hourValues.length} : null,
      ...(live ? {} : {note:latest ? '臂带当前没有实时数据；latest 是最后一次收到的读数。' : '还没有收到过心率数据。'})};
  }

  function rangePayload(args) {
    const t = now();
    const end = args.end === undefined ? t : hrParseTime(args.end, 'invalid_heart_rate_range');
    const start = args.start === undefined ? end - 3600000 : hrParseTime(args.start, 'invalid_heart_rate_range');
    if (start >= end || end - start > HR_LIMITS.rangeMs || start > t + HR_LIMITS.futureMs) hrFail('invalid_heart_rate_range');
    tick();
    const rows = minuteRows(start - ((start + HR_OFFSET_MS) % 60000 + 60000) % 60000, end);
    return {start:hrIso(start), end:hrIso(end), covered_minutes:rows.length,
      minutes:rows.map(row => ({at:hrIso(row.ms), median:row.med, min:row.min, max:row.max, samples:row.n, ...(row.partial ? {partial:true} : {})}))};
  }

  function nightPayload(args) {
    if (!hrValidDate(args.night)) hrFail('invalid_heart_rate_night');
    tick();
    const start = hrMidnight(args.night) + 18 * 3600000, end = start + 18 * 3600000;
    const rows = minuteRows(start, end);
    const blocks = new Map();
    for (const row of rows) {
      const key = row.ms - (row.ms - start) % 300000;
      if (!blocks.has(key)) blocks.set(key, []);
      blocks.get(key).push(row);
    }
    let lowest = null;
    for (let i = 0; i < rows.length; i++) {
      const window = [];
      for (let j = i; j < rows.length && rows[j].ms < rows[i].ms + 30 * 60000; j++) window.push(rows[j].med);
      if (window.length < 20) continue;
      const mean = Math.round(window.reduce((a, b) => a + b, 0) / window.length * 10) / 10;
      if (!lowest || mean < lowest.mean) lowest = {start:hrIso(rows[i].ms), mean, minutes:window.length};
    }
    return {night:args.night, window_start:hrIso(start), window_end:hrIso(end), covered_minutes:rows.length,
      first_minute:rows.length ? hrIso(rows[0].ms) : null, last_minute:rows.length ? hrIso(rows.at(-1).ms) : null,
      blocks_5m:[...blocks.entries()].map(([ms, items]) => ({at:hrIso(ms), median:hrMedian(items.map(row => row.med)),
        min:Math.min(...items.map(row => row.min)), max:Math.max(...items.map(row => row.max)), minutes:items.length})),
      lowest_30m:lowest};
  }

  prune();
  return {ingest, tick, flush, close:flush, nowPayload, rangePayload, nightPayload};
}

export function createHeartRateTools({store}) {
  if (!store || typeof store.nowPayload !== 'function') throw new Error('invalid_heart_rate_configuration');
  const handlers = {
    async heart_rate(args = {}) {
      if (!hrObject(args)) hrFail('invalid_request');
      const mode = args.mode ?? 'now';
      const allowed = {now:['mode'], range:['mode', 'start', 'end'], night:['mode', 'night']}[mode];
      if (!allowed) hrFail('invalid_heart_rate_mode');
      if (Object.keys(args).some(key => !allowed.includes(key))) hrFail('invalid_request');
      if (mode === 'night' && args.night === undefined) hrFail('invalid_heart_rate_night');
      return mode === 'now' ? store.nowPayload() : mode === 'range' ? store.rangePayload(args) : store.nightPayload(args);
    },
  };
  return {tools:HEART_RATE_TOOLS, handlers};
}

// ---------- ingest listener (bind to 127.0.0.1 only; exposed solely through `tailscale serve`) ----------
function hrSend(res, status, body) {
  const text = JSON.stringify(body);
  res.writeHead(status, {'Content-Type':'application/json; charset=utf-8', 'Content-Length':Buffer.byteLength(text),
    'Cache-Control':'no-store', 'X-Content-Type-Options':'nosniff'});
  res.end(text);
}
export function createHeartRateIngestServer({store, config}) {
  if (!store || !config || !Array.isArray(config.tailscale_logins)) throw new Error('invalid_heart_rate_configuration');
  const allowed = new Set(config.tailscale_logins.map(login => login.toLowerCase()));
  const server = hrHttp.createServer((req, res) => {
    const login = req.headers['tailscale-user-login'];
    if (typeof login !== 'string' || !login) return hrSend(res, 401, {error:'unauthorized'});
    if (!allowed.has(login.toLowerCase())) return hrSend(res, 403, {error:'forbidden'});
    const path = new URL(req.url, 'http://heart-rate.local').pathname;
    if (req.method === 'GET' && path === '/v1/heart-rate/health') return hrSend(res, 200, {ok:true, format:'hr-samples-v1'});
    if (path !== '/v1/heart-rate/samples') return hrSend(res, 404, {error:'not_found'});
    if (req.method !== 'POST') return hrSend(res, 405, {error:'method_not_allowed'});
    const chunks = [];
    let size = 0, tooLarge = false;
    req.on('data', chunk => {
      if (tooLarge) return;
      size += chunk.length;
      if (size > HR_LIMITS.body) { tooLarge = true; chunks.length = 0; hrSend(res, 413, {error:'too_large'}); req.resume(); return; }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (tooLarge) return;
      let body;
      try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { return hrSend(res, 400, {error:'invalid_request'}); }
      try { return hrSend(res, 200, store.ingest(body)); }
      catch (error) {
        if (error instanceof HeartRateInputError) return hrSend(res, 400, {error:error.message});
        return hrSend(res, 500, {error:'server_error'});
      }
    });
    req.on('error', () => { if (!res.headersSent) hrSend(res, 400, {error:'invalid_request'}); });
  });
  const timer = setInterval(() => { try { store.tick(); } catch { /* keep serving */ } }, 30000);
  timer.unref?.();
  server.on('close', () => { clearInterval(timer); try { store.flush(); } catch { /* best effort */ } });
  return {server};
}
