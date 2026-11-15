// CAM1 on-demand camera. Self-contained (node: imports only) so the legacy candidate can inline this file verbatim.
// The bedside phone keeps a long poll open to a listener bound to one private LAN address; camera_look queues a
// single request, the phone (optionally turning its pan-tilt mount) captures one JPEG and posts it back, and the
// image is returned to the model straight from memory. Images are never written to disk; only the time, position
// and outcome of each look are appended to <stateDir>/camera/looks-YYYY-MM-DD.jsonl (kept 30 days).
import * as camFs from 'node:fs';
import * as camPath from 'node:path';
import * as camHttp from 'node:http';
import * as camCrypto from 'node:crypto';
import * as camChild from 'node:child_process';

export class CameraInputError extends Error {}
const camFail = code => { throw new CameraInputError(code); };
const camObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
export const CAMERA_FRONTENDS = Object.freeze(['claude_web', 'chatgpt_web', 'gemini_web', 'antigravity']);
export const CAMERA_DEFAULT_PORT = 47867;
const CAM_OFFSET_MS = 8 * 3600 * 1000; // Asia/Shanghai, no DST.
export const CAMERA_LIMITS = Object.freeze({jpegBytes:1536 * 1024, metaBytes:2048, pollMs:25 * 1000, onlineMs:45 * 1000,
  lookMs:20 * 1000, findMs:45 * 1000, retentionDays:30, positions:8, homeCacheMs:20 * 1000, homeTimeoutMs:4000});
const CAM_DEFAULT_POSITIONS = Object.freeze(['床', '书桌', '门口']);
const CAM_SPECIAL = Object.freeze(['current', 'find_me']);

// ---------- config ----------
// <stateDir>/camera.json (local only, never committed):
// {"format":"camera-v1","listen_host":"<private IPv4 of this PC>","token_sha256":"<64 hex>",
//  "home_peer":"<tailscale host name of the user's phone>","positions":["床","书桌","门口"],
//  "min_interval_seconds":120,"daily_limit":30}
const camPrivateIpv4 = host => {
  if (typeof host !== 'string' || !/^\d{1,3}(?:\.\d{1,3}){3}$/.test(host)) return false;
  const p = host.split('.').map(Number);
  if (p.some(n => n > 255)) return false;
  return p[0] === 10 || (p[0] === 172 && p[1] >= 16 && p[1] <= 31) || (p[0] === 192 && p[1] === 168);
};
export { camPrivateIpv4 as isPrivateIpv4 };
const camPositionName = name => typeof name === 'string' && /^[^\s\0-\x1f\x7f,;=]{1,16}$/u.test(name) && !CAM_SPECIAL.includes(name);

export function loadCameraConfig(stateDir) {
  let text;
  try { text = camFs.readFileSync(camPath.resolve(stateDir, 'camera.json'), 'utf8'); }
  catch (error) { if (error.code === 'ENOENT') return null; throw new Error('camera_config_invalid'); }
  try {
    const v = JSON.parse(text.replace(/^﻿/, ''));
    const keys = ['format', 'listen_host', 'token_sha256', 'home_peer', 'positions', 'min_interval_seconds', 'daily_limit'];
    if (!camObject(v) || Object.keys(v).some(key => !keys.includes(key)) || v.format !== 'camera-v1'
      || !camPrivateIpv4(v.listen_host) || typeof v.token_sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(v.token_sha256)
      || typeof v.home_peer !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$/.test(v.home_peer)) throw new Error();
    const positions = v.positions ?? [...CAM_DEFAULT_POSITIONS];
    if (!Array.isArray(positions) || positions.length < 1 || positions.length > CAMERA_LIMITS.positions
      || positions.some(name => !camPositionName(name)) || new Set(positions).size !== positions.length) throw new Error();
    const minInterval = v.min_interval_seconds ?? 120, dailyLimit = v.daily_limit ?? 30;
    if (!Number.isSafeInteger(minInterval) || minInterval < 30 || minInterval > 3600
      || !Number.isSafeInteger(dailyLimit) || dailyLimit < 1 || dailyLimit > 200) throw new Error();
    return {format:v.format, listen_host:v.listen_host, token_sha256:v.token_sha256, home_peer:v.home_peer.toLowerCase(),
      positions, min_interval_seconds:minInterval, daily_limit:dailyLimit};
  } catch { throw new Error('camera_config_invalid'); }
}

export function cameraTools(config) {
  const positions = config.positions;
  return [{name:'camera_look', requiredScope:'i.read',
    description:`用家里床头的摄像头看用户一眼：只拍一张照片，不录像；照片只在内存里转给你，家里不保存。只有用户在家时可用；用户不在家、床头手机暂停了“现在别看”、相机不在线或次数用完时会返回原因，如实转告，不要猜。position：current（默认，不转动）、预置位（${positions.join(' / ')}）、find_me（云台扫一圈找到人、转到画面中间再拍）。每次至少间隔 ${Math.round(config.min_interval_seconds / 60 * 10) / 10} 分钟，每天最多 ${config.daily_limit} 次。只描述画面里看得到的东西，不凭一张照片断言情绪、健康或在做什么私密的事；用户说不想被看就不要调。`,
    inputSchema:{type:'object', properties:{
      position:{type:'string', enum:['current', ...positions, 'find_me'], description:'默认 current。'},
    }, additionalProperties:false},
    annotations:{readOnlyHint:true, destructiveHint:false, idempotentHint:false, openWorldHint:false}}];
}

// ---------- time ----------
const camPad = value => String(value).padStart(2, '0');
function camLocal(ms) {
  const d = new Date(ms + CAM_OFFSET_MS);
  return {date:`${d.getUTCFullYear()}-${camPad(d.getUTCMonth() + 1)}-${camPad(d.getUTCDate())}`,
    time:`${camPad(d.getUTCHours())}:${camPad(d.getUTCMinutes())}:${camPad(d.getUTCSeconds())}`};
}
const camIso = ms => { const l = camLocal(ms); return `${l.date}T${l.time}+08:00`; };

// ---------- home check (Tailscale: is the user's phone reached directly over a private LAN address?) ----------
export function parseTailscaleHome(statusJson, peerName) {
  if (!camObject(statusJson) || !camObject(statusJson.Peer)) return {home:null, reason:'tailscale_status_invalid'};
  const want = String(peerName).toLowerCase();
  const peer = Object.values(statusJson.Peer).find(item => camObject(item)
    && (String(item.HostName ?? '').toLowerCase() === want || String(item.DNSName ?? '').toLowerCase().split('.')[0] === want));
  if (!peer) return {home:null, reason:'phone_not_in_tailnet'};
  if (!peer.Online) return {home:false, reason:'phone_offline'};
  const addr = typeof peer.CurAddr === 'string' ? peer.CurAddr : '';
  const host = addr.startsWith('[') ? '' : addr.replace(/:\d+$/, '');
  if (!host) return {home:false, reason:peer.Relay ? 'phone_via_relay' : 'phone_not_direct'};
  return camPrivateIpv4(host) ? {home:true, reason:'phone_on_lan'} : {home:false, reason:'phone_not_on_lan'};
}
export function createTailscaleHomeCheck({peerName, exec = camChild.execFile, now = () => Date.now()}) {
  let cache = null;
  return async function homeCheck() {
    if (cache && now() - cache.at < CAMERA_LIMITS.homeCacheMs) return cache.value;
    const value = await new Promise(resolve => {
      try {
        exec('tailscale', ['status', '--json'], {timeout:CAMERA_LIMITS.homeTimeoutMs, windowsHide:true, maxBuffer:4 * 1024 * 1024},
          (error, stdout) => {
            if (error) return resolve({home:null, reason:'tailscale_unavailable'});
            try { resolve(parseTailscaleHome(JSON.parse(String(stdout)), peerName)); }
            catch { resolve({home:null, reason:'tailscale_status_invalid'}); }
          });
      } catch { resolve({home:null, reason:'tailscale_unavailable'}); }
    });
    cache = {at:now(), value};
    return value;
  };
}

// ---------- look log (time only) ----------
function camLogDir(stateDir) {
  const dir = camPath.resolve(stateDir, 'camera');
  let stat;
  try { stat = camFs.lstatSync(dir); }
  catch (error) {
    if (error.code !== 'ENOENT') throw new Error('camera_dir_invalid');
    try { camFs.mkdirSync(dir, {mode:0o700}); stat = camFs.lstatSync(dir); } catch { throw new Error('camera_dir_invalid'); }
  }
  if (stat.isSymbolicLink() || !stat.isDirectory()) throw new Error('camera_dir_invalid');
  return dir;
}
function camLogFile(dir, date) {
  const path = camPath.join(dir, `looks-${date}.jsonl`);
  try { const stat = camFs.lstatSync(path); if (stat.isSymbolicLink() || !stat.isFile()) return null; }
  catch (error) { if (error.code !== 'ENOENT') return null; }
  return path;
}

// ---------- hub ----------
const CAM_MESSAGES = Object.freeze({
  not_home:'用户现在不在家，看不了。', home_unknown:'现在判断不了用户在不在家，为安全起见没有拍。',
  phone_offline:'床头相机现在不在线。', camera_busy:'上一次拍摄还没结束，稍后再试。',
  rate_limited:'距离上次看太近了，稍后再看。', daily_limit:'今天看的次数已经用完了。',
  paused:'用户在床头手机上按了“现在别看”，这次没有拍。', timeout:'床头相机没有按时回传照片。',
  camera_error:'床头相机拍摄失败。', gimbal_error:'云台没有转到位，这次没有拍。', not_found:'云台扫了一圈，没有在画面里找到人。',
});
const CAM_PHONE_FAILS = Object.freeze(['paused', 'camera_error', 'gimbal_error', 'not_found']);

export function createCameraHub({config, stateDir, homeCheck, now = () => Date.now()}) {
  if (!config || typeof homeCheck !== 'function') throw new Error('invalid_camera_configuration');
  const dir = camLogDir(stateDir);
  const waiters = new Set(); // pending long polls: {deliver(request), timer}
  let pending = null; // {id, position, expiresAt, resolve, delivered}
  let lastPollAt = null, lastDispatchAt = null, prunedFor = null;
  let day = null, dayCount = 0;

  function today() {
    const date = camLocal(now()).date;
    if (day !== date) {
      day = date; dayCount = 0;
      const path = camLogFile(dir, date);
      if (path) {
        try { dayCount = camFs.readFileSync(path, 'utf8').split('\n').filter(line => line.includes('"dispatched":true')).length; }
        catch { /* missing file means zero */ }
      }
      prune(date);
    }
    return date;
  }
  function prune(date) {
    if (prunedFor === date) return;
    prunedFor = date;
    const oldest = camLocal(now() - CAMERA_LIMITS.retentionDays * 86400000).date;
    let names = [];
    try { names = camFs.readdirSync(dir); } catch { return; }
    for (const name of names) {
      const match = /^looks-(\d{4}-\d{2}-\d{2})\.jsonl$/.exec(name);
      if (!match || match[1] >= oldest) continue;
      const path = camLogFile(dir, match[1]);
      if (path) { try { camFs.unlinkSync(path); } catch { /* retry tomorrow */ } }
    }
  }
  function log(position, outcome, dispatched) {
    const t = now(), path = camLogFile(dir, today());
    if (!path) return;
    let fd;
    try { fd = camFs.openSync(path, 'a', 0o600); camFs.writeSync(fd, JSON.stringify({at:camIso(t), position, outcome, dispatched}) + '\n'); }
    catch { /* a lost log line must not break looking */ }
    finally { if (fd !== undefined) camFs.closeSync(fd); }
  }
  const phoneOnline = () => waiters.size > 0 || (lastPollAt !== null && now() - lastPollAt <= CAMERA_LIMITS.onlineMs);
  const refusal = (code, extra = {}) => ({ok:false, error:code, message:CAM_MESSAGES[code], ...extra});

  function settle(result) {
    if (!pending) return;
    const current = pending;
    pending = null;
    clearTimeout(current.timer);
    current.resolve(result);
  }

  async function look(args = {}) {
    if (!camObject(args) || Object.keys(args).some(key => key !== 'position')) camFail('invalid_request');
    const position = args.position ?? 'current';
    if (!CAM_SPECIAL.includes(position) && !config.positions.includes(position)) camFail('invalid_camera_position');
    today();
    const home = await homeCheck();
    if (home?.home !== true) {
      const code = home?.home === false ? 'not_home' : 'home_unknown';
      log(position, code, false);
      return refusal(code, {detail:home?.reason ?? null});
    }
    if (!phoneOnline()) { log(position, 'phone_offline', false); return refusal('phone_offline'); }
    if (pending) return refusal('camera_busy');
    const t = now();
    if (lastDispatchAt !== null && t - lastDispatchAt < config.min_interval_seconds * 1000) {
      return refusal('rate_limited', {retry_after_seconds:Math.ceil((lastDispatchAt + config.min_interval_seconds * 1000 - t) / 1000)});
    }
    if (dayCount >= config.daily_limit) return refusal('daily_limit');
    lastDispatchAt = t;
    dayCount++;
    const id = camCrypto.randomBytes(12).toString('hex');
    const timeoutMs = position === 'find_me' ? CAMERA_LIMITS.findMs : CAMERA_LIMITS.lookMs;
    const result = await new Promise(resolve => {
      pending = {id, position, resolve, delivered:false, timer:setTimeout(() => settle({kind:'fail', code:'timeout'}), timeoutMs)};
      pending.timer.unref?.();
      const [waiter] = waiters;
      if (waiter) waiter.deliver();
    });
    if (result.kind === 'fail') { log(position, result.code, true); return refusal(result.code); }
    log(position, 'ok', true);
    const meta = result.meta;
    return {ok:true, taken_at:camIso(result.at), position, ...meta,
      note:'照片只在这一轮里给你看，家里没有保存。只描述看得到的内容。',
      __content:[{type:'image', data:result.jpeg.toString('base64'), mimeType:'image/jpeg'}]};
  }

  // ---- phone side ----
  function nextRequest() {
    if (!pending || pending.delivered) return null;
    pending.delivered = true;
    return {id:pending.id, position:pending.position};
  }
  function poll(onRequest) {
    lastPollAt = now();
    const ready = nextRequest();
    if (ready) { onRequest(ready); return () => {}; }
    const waiter = {deliver() {
      const request = nextRequest();
      if (!request) return;
      waiters.delete(waiter); clearTimeout(waiter.timer); onRequest(request);
    }};
    waiter.timer = setTimeout(() => { waiters.delete(waiter); lastPollAt = now(); onRequest(null); }, CAMERA_LIMITS.pollMs);
    waiter.timer.unref?.();
    waiters.add(waiter);
    return () => { if (waiters.delete(waiter)) { clearTimeout(waiter.timer); lastPollAt = now(); } };
  }
  function submitFrame(id, jpeg, meta) {
    if (!pending || pending.id !== id || !pending.delivered) return false;
    settle({kind:'frame', jpeg, meta, at:now()});
    return true;
  }
  function submitFailure(id, code) {
    if (!pending || pending.id !== id || !pending.delivered || !CAM_PHONE_FAILS.includes(code)) return false;
    settle({kind:'fail', code});
    return true;
  }
  function close() {
    for (const waiter of waiters) clearTimeout(waiter.timer);
    waiters.clear();
    settle({kind:'fail', code:'phone_offline'});
  }
  return {look, poll, submitFrame, submitFailure, close, status:() => ({online:phoneOnline(), pending:Boolean(pending), today:dayCount})};
}

export function createCameraTools({hub, config}) {
  if (!hub || typeof hub.look !== 'function') throw new Error('invalid_camera_configuration');
  return {tools:cameraTools(config), handlers:{camera_look:args => hub.look(args)}};
}

// ---------- meta from the phone (small, numeric, no pixels) ----------
export function parseCameraMeta(header) {
  if (header === undefined) return {};
  if (typeof header !== 'string' || header.length > CAMERA_LIMITS.metaBytes) camFail('invalid_meta');
  let value;
  try { value = JSON.parse(Buffer.from(header, 'base64').toString('utf8')); } catch { camFail('invalid_meta'); }
  if (!camObject(value)) camFail('invalid_meta');
  const out = {};
  if (value.face !== undefined) { if (typeof value.face !== 'boolean') camFail('invalid_meta'); out.face = value.face; }
  for (const key of ['eyes_open', 'luma']) {
    if (value[key] === undefined || value[key] === null) continue;
    if (!Number.isFinite(value[key])) camFail('invalid_meta');
    out[key] = Math.round(value[key] * 100) / 100;
  }
  if (value.found !== undefined) { if (typeof value.found !== 'boolean') camFail('invalid_meta'); out.found = value.found; }
  if (value.reached !== undefined) {
    if (typeof value.reached !== 'string' || !/^[^\0-\x1f\x7f]{1,24}$/u.test(value.reached)) camFail('invalid_meta');
    out.reached = value.reached;
  }
  if (Object.keys(value).some(key => !['face', 'eyes_open', 'luma', 'found', 'reached'].includes(key))) camFail('invalid_meta');
  return out;
}

// ---------- LAN listener for the bedside phone (bind to config.listen_host only) ----------
function camSend(res, status, body) {
  if (res.headersSent || res.writableEnded) return;
  if (status === 204) { res.writeHead(204, {'Cache-Control':'no-store'}); res.end(); return; }
  const text = JSON.stringify(body);
  res.writeHead(status, {'Content-Type':'application/json; charset=utf-8', 'Content-Length':Buffer.byteLength(text),
    'Cache-Control':'no-store', 'X-Content-Type-Options':'nosniff'});
  res.end(text);
}
export function cameraTokenMatches(header, tokenSha256) {
  if (typeof header !== 'string' || !header.startsWith('Bearer ')) return false;
  const token = header.slice(7);
  if (token.length < 32 || token.length > 256) return false;
  const got = camCrypto.createHash('sha256').update(token, 'utf8').digest();
  return camCrypto.timingSafeEqual(got, Buffer.from(tokenSha256, 'hex'));
}
export function createCameraPhoneServer({hub, config}) {
  if (!hub || !config) throw new Error('invalid_camera_configuration');
  const server = camHttp.createServer((req, res) => {
    if (!cameraTokenMatches(req.headers.authorization, config.token_sha256)) { req.resume(); return camSend(res, 401, {error:'unauthorized'}); }
    const url = new URL(req.url, 'http://camera.local');
    const id = url.searchParams.get('id');
    if (req.method === 'GET' && url.pathname === '/v1/camera/next') {
      let answered = false;
      const cancel = hub.poll(request => {
        if (answered) return;
        answered = true;
        if (request) camSend(res, 200, request); else camSend(res, 204);
      });
      res.on('close', () => { if (!answered) { answered = true; cancel(); } });
      return;
    }
    if (req.method === 'POST' && url.pathname === '/v1/camera/fail') {
      req.resume();
      const code = url.searchParams.get('code');
      return camSend(res, hub.submitFailure(id, code) ? 200 : 409, {ok:true});
    }
    if (req.method === 'POST' && url.pathname === '/v1/camera/frame') {
      let meta;
      try { meta = parseCameraMeta(req.headers['x-camera-meta']); } catch { req.resume(); return camSend(res, 400, {error:'invalid_meta'}); }
      if (!String(req.headers['content-type'] ?? '').startsWith('image/jpeg')) { req.resume(); return camSend(res, 415, {error:'jpeg_required'}); }
      const chunks = [];
      let size = 0, tooLarge = false;
      req.on('data', chunk => {
        if (tooLarge) return;
        size += chunk.length;
        if (size > CAMERA_LIMITS.jpegBytes) { tooLarge = true; chunks.length = 0; camSend(res, 413, {error:'too_large'}); return; }
        chunks.push(chunk);
      });
      req.on('end', () => {
        if (tooLarge) return;
        const jpeg = Buffer.concat(chunks);
        chunks.length = 0;
        if (jpeg.length < 4 || jpeg[0] !== 0xff || jpeg[1] !== 0xd8) return camSend(res, 400, {error:'not_jpeg'});
        return camSend(res, hub.submitFrame(id, jpeg, meta) ? 200 : 409, {ok:true});
      });
      req.on('error', () => camSend(res, 400, {error:'invalid_request'}));
      return;
    }
    req.resume();
    return camSend(res, 404, {error:'not_found'});
  });
  server.requestTimeout = 60 * 1000;
  server.on('close', () => hub.close());
  return {server};
}

// MCP result for camera_look: the image goes out as an image content block, never as JSON text.
// CAM2 wires this into mcp.mjs toolResult (payloads without __content keep the existing text-only shape).
export function cameraToolResult(payload) {
  if (!camObject(payload) || !Array.isArray(payload.__content)) return null;
  const {__content, ...rest} = payload;
  return {content:[...__content, {type:'text', text:JSON.stringify(rest, null, 2)}], structuredContent:rest, isError:false};
}
