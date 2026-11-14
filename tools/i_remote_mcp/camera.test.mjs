import assert from 'node:assert/strict';
import {createHash, randomUUID} from 'node:crypto';
import {mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test, mock} from 'node:test';
import {CAMERA_LIMITS, cameraTokenMatches, cameraToolResult, createCameraHub, createCameraPhoneServer, createCameraTools,
  createTailscaleHomeCheck, isPrivateIpv4, loadCameraConfig, parseCameraMeta, parseTailscaleHome} from './camera.mjs';

// All addresses, names and tokens below are synthetic.
const TOKEN = 'synthetic-camera-token-' + 'x'.repeat(24);
const TOKEN_SHA = createHash('sha256').update(TOKEN).digest('hex');
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 0xff, 0xd9]);
const CONFIG = {format:'camera-v1', listen_host:'192.168.50.10', token_sha256:TOKEN_SHA, home_peer:'phone-test',
  positions:['床', '书桌', '门口'], min_interval_seconds:120, daily_limit:3};

function stateDir(t) {
  const dir = join(tmpdir(), 'camera-test-' + randomUUID());
  mkdirSync(dir, {recursive:true});
  t.after(() => rmSync(dir, {recursive:true, force:true}));
  return dir;
}
function hub(t, {home = {home:true, reason:'phone_on_lan'}, clock} = {}) {
  const dir = stateDir(t);
  const now = clock ?? (() => Date.parse('2026-11-07T22:00:00+08:00'));
  const h = createCameraHub({config:CONFIG, stateDir:dir, homeCheck:async () => home, now});
  t.after(() => h.close());
  return {h, dir};
}
// Simulates the bedside phone: answers the next request with a frame or a failure.
function phone(h, answer) {
  h.poll(request => { if (request) answer(request); });
}

test('config: absent, valid, and rejected shapes', t => {
  const dir = stateDir(t);
  assert.equal(loadCameraConfig(dir), null);
  writeFileSync(join(dir, 'camera.json'), '﻿' + JSON.stringify({format:'camera-v1', listen_host:'192.168.1.5', token_sha256:TOKEN_SHA, home_peer:'Phone-Test'}));
  const config = loadCameraConfig(dir);
  assert.deepEqual(config.positions, ['床', '书桌', '门口']);
  assert.equal(config.home_peer, 'phone-test');
  assert.equal(config.min_interval_seconds, 120);
  for (const bad of [
    {listen_host:'0.0.0.0'}, {listen_host:'8.8.8.8'}, {listen_host:'127.0.0.1'}, {token_sha256:'abc'},
    {positions:['current']}, {positions:['床', '床']}, {positions:[]}, {min_interval_seconds:5}, {daily_limit:0}, {extra:1},
  ]) {
    writeFileSync(join(dir, 'camera.json'), JSON.stringify({...CONFIG, ...bad}));
    assert.throws(() => loadCameraConfig(dir), /camera_config_invalid/, JSON.stringify(bad));
  }
});

test('private IPv4 detection', () => {
  for (const ok of ['10.0.0.1', '172.16.0.1', '172.31.255.255', '192.168.0.2']) assert.ok(isPrivateIpv4(ok), ok);
  for (const bad of ['172.15.0.1', '172.32.0.1', '100.64.0.1', '127.0.0.1', '8.8.8.8', '192.168.1', '300.1.1.1', 'fe80::1']) assert.ok(!isPrivateIpv4(bad), bad);
});

test('tailscale home check: direct LAN only counts as home', async () => {
  const status = peer => ({Peer:{k:{HostName:'Phone-Test', DNSName:'phone-test.tail0000.ts.net.', ...peer}}});
  assert.deepEqual(parseTailscaleHome(status({Online:true, CurAddr:'192.168.50.23:41641'}), 'phone-test'), {home:true, reason:'phone_on_lan'});
  assert.equal(parseTailscaleHome(status({Online:true, CurAddr:'203.0.113.9:41641'}), 'phone-test').home, false);
  assert.equal(parseTailscaleHome(status({Online:true, CurAddr:'', Relay:'tok'}), 'phone-test').reason, 'phone_via_relay');
  assert.equal(parseTailscaleHome(status({Online:false, CurAddr:'192.168.50.23:41641'}), 'phone-test').home, false);
  assert.equal(parseTailscaleHome(status({Online:true}), 'other').home, null);
  assert.equal(parseTailscaleHome({}, 'phone-test').home, null);
  let calls = 0, t = 0;
  const check = createTailscaleHomeCheck({peerName:'phone-test', now:() => t,
    exec:(file, args, options, cb) => { calls++; assert.equal(file, 'tailscale'); cb(null, JSON.stringify(status({Online:true, CurAddr:'10.0.0.8:1'}))); }});
  assert.equal((await check()).home, true);
  await check();
  assert.equal(calls, 1, 'cached');
  t += CAMERA_LIMITS.homeCacheMs + 1;
  await check();
  assert.equal(calls, 2);
  const failing = createTailscaleHomeCheck({peerName:'phone-test', exec:(f, a, o, cb) => cb(new Error('missing'))});
  assert.deepEqual(await failing(), {home:null, reason:'tailscale_unavailable'});
});

test('look returns the image in memory and logs only time/position/outcome', async t => {
  const {h, dir} = hub(t);
  let seen;
  phone(h, request => { seen = request; h.submitFrame(request.id, JPEG, {face:true, eyes_open:0.9, reached:'书桌'}); });
  const result = await h.look({position:'书桌'});
  assert.equal(seen.position, '书桌');
  assert.equal(result.ok, true);
  assert.equal(result.face, true);
  assert.equal(result.__content[0].type, 'image');
  assert.equal(Buffer.from(result.__content[0].data, 'base64').compare(JPEG), 0);
  const mcp = cameraToolResult(result);
  assert.equal(mcp.content[0].mimeType, 'image/jpeg');
  assert.ok(!('__content' in mcp.structuredContent));
  assert.ok(!mcp.content[1].text.includes(JPEG.toString('base64')));
  assert.equal(cameraToolResult({ok:true}), null);
  const files = readdirSync(join(dir, 'camera'));
  assert.deepEqual(files, ['looks-2026-11-07.jsonl']);
  const line = JSON.parse(readFileSync(join(dir, 'camera', files[0]), 'utf8').trim());
  assert.deepEqual(Object.keys(line).sort(), ['at', 'dispatched', 'outcome', 'position']);
  assert.equal(line.outcome, 'ok');
  assert.ok(!readdirSync(dir).some(name => /\.(jpe?g|png)$/i.test(name)));
});

test('refusals: not home, unknown home, phone offline, bad args', async t => {
  assert.equal((await hub(t, {home:{home:false, reason:'phone_not_on_lan'}}).h.look()).error, 'not_home');
  assert.equal((await hub(t, {home:{home:null, reason:'tailscale_unavailable'}}).h.look()).error, 'home_unknown');
  const {h} = hub(t);
  assert.equal((await h.look()).error, 'phone_offline');
  await assert.rejects(h.look({position:'厨房'}), /invalid_camera_position/);
  await assert.rejects(h.look({position:'床', extra:1}), /invalid_request/);
});

test('rate limit and daily limit', async t => {
  let clock = Date.parse('2026-11-07T10:00:00+08:00');
  const {h, dir} = hub(t, {clock:() => clock});
  const shoot = () => { phone(h, r => h.submitFrame(r.id, JPEG, {})); return h.look(); };
  assert.equal((await shoot()).ok, true);
  const limited = await shoot();
  assert.equal(limited.error, 'rate_limited');
  assert.equal(limited.retry_after_seconds, 120);
  clock += 121000; assert.equal((await shoot()).ok, true);
  clock += 121000; assert.equal((await shoot()).ok, true);
  clock += 121000; assert.equal((await shoot()).error, 'daily_limit');
  // A restarted hub reads today's count back from the log.
  const again = createCameraHub({config:CONFIG, stateDir:dir, homeCheck:async () => ({home:true}), now:() => clock});
  t.after(() => again.close());
  phone(again, r => again.submitFrame(r.id, JPEG, {}));
  assert.equal((await again.look()).error, 'daily_limit');
  clock += 86400000;
  assert.equal((await again.look()).ok, true, 'new day resets');
});

test('phone-side failures and timeout', async t => {
  let clock = Date.parse('2026-11-07T10:00:00+08:00');
  const {h} = hub(t, {clock:() => clock});
  phone(h, r => h.submitFailure(r.id, 'paused'));
  assert.equal((await h.look()).error, 'paused');
  clock += 121000;
  phone(h, r => assert.equal(h.submitFailure(r.id, 'made_up'), false));
  mock.timers.enable({apis:['setTimeout']});
  t.after(() => mock.timers.reset());
  const waiting = h.look({position:'find_me'});
  await new Promise(resolve => setImmediate(resolve));
  mock.timers.tick(CAMERA_LIMITS.findMs + 1);
  assert.equal((await waiting).error, 'timeout');
});

test('meta parser accepts only small numeric fields', () => {
  const enc = value => Buffer.from(JSON.stringify(value)).toString('base64');
  assert.deepEqual(parseCameraMeta(enc({face:false, luma:12.345, found:true, reached:'床'})), {face:false, luma:12.35, found:true, reached:'床'});
  assert.deepEqual(parseCameraMeta(undefined), {});
  for (const bad of [enc({face:'yes'}), enc({pixels:[1]}), enc([1]), 'not base64 json', 'x'.repeat(3000)]) assert.throws(() => parseCameraMeta(bad), /invalid_meta/);
});

test('token check', () => {
  assert.ok(cameraTokenMatches('Bearer ' + TOKEN, TOKEN_SHA));
  assert.ok(!cameraTokenMatches('Bearer ' + TOKEN + 'y', TOKEN_SHA));
  assert.ok(!cameraTokenMatches(TOKEN, TOKEN_SHA));
  assert.ok(!cameraTokenMatches(undefined, TOKEN_SHA));
});

test('tool schema lists configured positions', () => {
  const {tools, handlers} = createCameraTools({hub:{look:async () => ({})}, config:CONFIG});
  assert.equal(tools[0].name, 'camera_look');
  assert.deepEqual(tools[0].inputSchema.properties.position.enum, ['current', '床', '书桌', '门口', 'find_me']);
  assert.equal(typeof handlers.camera_look, 'function');
});

test('HTTP: long poll, frame upload, auth, and size checks', async t => {
  const {h} = hub(t);
  const {server} = createCameraPhoneServer({hub:h, config:CONFIG});
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections?.(); server.close(resolve); }));
  const base = `http://127.0.0.1:${server.address().port}`;
  const auth = {authorization:'Bearer ' + TOKEN};
  assert.equal((await fetch(base + '/v1/camera/next')).status, 401);
  assert.equal((await fetch(base + '/v1/camera/nope', {headers:auth})).status, 404);
  const poll = fetch(base + '/v1/camera/next', {headers:auth});
  await new Promise(resolve => setTimeout(resolve, 50));
  const looking = h.look({position:'床'});
  const response = await poll;
  assert.equal(response.status, 200);
  const request = await response.json();
  assert.equal(request.position, '床');
  const meta = Buffer.from(JSON.stringify({face:true})).toString('base64');
  assert.equal((await fetch(`${base}/v1/camera/frame?id=${request.id}`, {method:'POST', headers:{...auth, 'content-type':'text/plain'}, body:'x'})).status, 415);
  assert.equal((await fetch(`${base}/v1/camera/frame?id=${request.id}`, {method:'POST', headers:{...auth, 'content-type':'image/jpeg'}, body:Buffer.from('nope')})).status, 400);
  assert.equal((await fetch(`${base}/v1/camera/frame?id=${request.id}`, {method:'POST', headers:{...auth, 'content-type':'image/jpeg'},
    body:Buffer.alloc(CAMERA_LIMITS.jpegBytes + 10, 0xff)})).status, 413);
  assert.equal((await fetch(`${base}/v1/camera/frame?id=wrong`, {method:'POST', headers:{...auth, 'content-type':'image/jpeg'}, body:JPEG})).status, 409);
  const ok = await fetch(`${base}/v1/camera/frame?id=${request.id}`, {method:'POST', headers:{...auth, 'content-type':'image/jpeg', 'x-camera-meta':meta}, body:JPEG});
  assert.equal(ok.status, 200);
  const result = await looking;
  assert.equal(result.ok, true);
  assert.equal(result.face, true);
});
