import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {after, before, test} from 'node:test';
import {buildChatgptCandidate, REPO_ROOT} from './chatgpt_candidate.mjs';
import {LIFE_DIGEST_TOOLS, createLifeDigest, lifeDayOf, loadLifeDigestConfig} from './life_digest.mjs';
import {createLifeDigestDomainTools, DomainToolInputError} from './domain_tools.mjs';
import * as mainServer from './server.mjs';
import * as mainOauth from './oauth.mjs';
import * as mainWriteback from './writeback.mjs';
import {createFakeReadModel, PASSPHRASE, PUBLIC_URL, pkcePair, registerClient, submitPassphrase, authorizeParams, postToken, initSession, mcpPost} from './fixtures.mjs';
import {listenForFetch} from './fetch_test_listener.mjs';

// All digest content below is synthetic.
const root = join(REPO_ROOT, 'build', 'life-digest-test-' + randomUUID());
const EVENING = Date.parse('2026-11-07T21:10:00+08:00');
const MORNING = Date.parse('2026-11-07T08:05:00+08:00');
let built, candidate, candidateOauth, candidateWriteback;
before(async () => {
  mkdirSync(root, {recursive:true});
  built = buildChatgptCandidate({outputDirectory:join('build', 'life-digest-test-' + randomUUID())});
  const load = name => import(pathToFileURL(join(built.root, 'i_remote_mcp', name + '.mjs')));
  [candidate, candidateOauth, candidateWriteback] = await Promise.all([load('server'), load('oauth'), load('writeback')]);
});
after(() => { rmSync(root, {recursive:true, force:true}); if (built) rmSync(built.outputRoot, {recursive:true, force:true}); });

const day = (date, extra = {}) => ({format:'life-digest-day-v1', date, stage:'day', generated_at:date + 'T19:31:00+08:00', generator:'codex',
  morning:{text:'早上好，今天比昨天降温 6 度，下午有小雨，出门带伞。', weather:'降温 6 度', generated_at:date + 'T07:30:20+08:00'},
  day:{headline:'上班写完周报，中午只吃了面包，晚上和林埃聊了秋招。', your_day:[{text:'写完周报', sources:['notes:docA']}],
    us:[{text:'聊了秋招面试', sources:['chat:m1']}], anomalies:[{text:'中午没吃正餐', sources:['food:' + date], level:'warn'}], omitted:[]},
  todos:[], sources_status:{chat:'ok', food:'ok', heart_rate:'ok', notes:'missing', weather:'ok'}, ...extra});
const todos = items => ({format:'life-digest-todos-v1', updated_at:'2026-11-07T19:31:00+08:00', items});
const CLOSERS = new WeakMap();
function fixture(t, {withConfig = true} = {}) {
  const base = join(root, randomUUID()), stateDir = join(base, 'state'), digestDir = join(base, 'digest');
  for (const dir of [stateDir, join(digestDir, 'days'), join(digestDir, 'inbox'), join(digestDir, 'pushes')]) mkdirSync(dir, {recursive:true});
  if (withConfig) writeFileSync(join(stateDir, 'life_digest.json'), JSON.stringify({format:'life-digest-v1', digest_dir:digestDir}));
  writeFileSync(join(digestDir, 'days', '2026-11-07.json'), JSON.stringify(day('2026-11-07')));
  writeFileSync(join(digestDir, 'days', '2026-11-06.json'), JSON.stringify(day('2026-11-06', {stage:'final'})));
  writeFileSync(join(digestDir, 'todos.json'), JSON.stringify(todos([
    {id:'td_cat00001', text:'买猫砂', quote:'今天要买猫砂', source:'notes:docA', first_seen:'2026-11-05', status:'open'},
    {id:'td_rent0001', text:'给房东回消息', quote:'记得回房东', source:'chat:m2', first_seen:'2026-11-07', status:'open'},
    {id:'td_old00001', text:'已完成的事', first_seen:'2026-11-01', status:'done'}])));
  writeFileSync(join(digestDir, 'pushes', '2026-11-07.jsonl'), JSON.stringify({id:'p_20261107a', at:'2026-11-07T19:32:00+08:00', rule:'no_lunch', text:'中午只吃了个面包吧？晚饭好好吃。'}) + '\n');
  // Windows cannot delete files the server still holds (writeback.sqlite), so servers close before the folder goes.
  const closers = [];
  CLOSERS.set(t, closers);
  t.after(async () => { for (const close of closers.reverse()) await close(); rmSync(base, {recursive:true, force:true}); });
  return {stateDir, digestDir};
}

const CALLBACK = 'https://claude.ai/api/mcp/auth_callback';
async function start(t, {server, oauth, writebackModule, stateDir, now = () => EVENING}) {
  oauth.setPassphrase(stateDir, PASSPHRASE);
  const submitted = [];
  const writeback = writebackModule.createWriteback({ledger:writebackModule.openLedger(join(stateDir, 'writeback.sqlite')), now,
    coreClient:{async submit(messages) { submitted.push(...messages); return messages.map((m, i) => ({sync_id:m.sync_id, status:'accepted', server_sequence:submitted.length + i})); }}});
  const app = server.createApp({stateDir, publicUrl:PUBLIC_URL, getReadModel:async () => createFakeReadModel(), now, writeback,
    chatgptEnabled:true, geminiEnabled:true, antigravityEnabled:true, sesameEnabled:true});
  await listenForFetch(app.server);
  const close = () => new Promise(resolve => app.server.close(() => { writeback.close(); resolve(); }));
  const closers = CLOSERS.get(t);
  if (closers) closers.push(close); else t.after(close);
  const base = 'http://127.0.0.1:' + app.server.address().port;
  const registered = await registerClient(base, [CALLBACK]); assert.equal(registered.status, 201);
  const {verifier, challenge} = pkcePair();
  const auth = await submitPassphrase(base, {...Object.fromEntries(authorizeParams({clientId:registered.body.client_id, challenge})), redirect_uri:CALLBACK, scope:'i.read i.write'});
  assert.equal(auth.status, 302);
  const token = await postToken(base, {grant_type:'authorization_code', code:new URL(auth.headers.get('location')).searchParams.get('code'),
    client_id:registered.body.client_id, redirect_uri:CALLBACK, code_verifier:verifier, resource:PUBLIC_URL + '/mcp'});
  assert.equal(token.status, 200);
  const {init, sessionId} = await initSession(base, token.body.access_token); assert.equal(init.status, 200);
  let id = 2;
  const rpc = async (method, params) => {
    const response = await mcpPost(base, token.body.access_token, {jsonrpc:'2.0', id:id++, method, params}, {sessionId});
    assert.equal(response.status, 200); return response.body;
  };
  return {rpc, submitted, call:async (name, args) => (await rpc('tools/call', {name, arguments:args})).result};
}

test('M1 candidate inlines life_digest.mjs verbatim with node-only imports', () => {
  const server = readFileSync(join(built.root, 'i_remote_mcp', 'server.mjs'), 'utf8').replaceAll('\r\n', '\n');
  const source = readFileSync(new URL('./life_digest.mjs', import.meta.url), 'utf8').replaceAll('\r\n', '\n');
  assert.equal(server.split(source.trimEnd()).length, 2, 'life_digest.mjs must appear exactly once, byte for byte');
  assert.deepEqual(candidate.LIFE_DIGEST_TOOLS, LIFE_DIGEST_TOOLS);
  assert.doesNotMatch(source, /domain_tools|personal_data_domains|coreRemember|domain-config/);
  const imports = [...source.matchAll(/(?:from\s*|import\s*\()(['"])([^'"]+)\1/g)].map(match => match[2]);
  assert.deepEqual(imports, ['node:fs', 'node:path', 'node:crypto']);
});

for (const [label, pick] of [['candidate', () => ({server:candidate, oauth:candidateOauth, writebackModule:candidateWriteback})],
  ['mainline', () => ({server:mainServer, oauth:mainOauth, writebackModule:mainWriteback})]]) {
  test(`M1 ${label}: life_digest, life_todo and the i_chat_turn snapshot`, {timeout:60000}, async t => {
    const {stateDir, digestDir} = fixture(t);
    const {rpc, call, submitted} = await start(t, {...pick(), stateDir});
    const listed = (await rpc('tools/list')).result.tools.filter(tool => tool.name.startsWith('life_'));
    assert.deepEqual(listed.map(tool => tool.name), ['life_digest', 'life_todo']);
    assert.deepEqual(listed[0].inputSchema, LIFE_DIGEST_TOOLS[0].inputSchema);

    const full = (await call('life_digest', {})).structuredContent;
    assert.equal(full.date, '2026-11-07'); assert.equal(full.available, true); assert.equal(full.stage, 'day');
    assert.match(full.headline, /周报/); assert.equal(full.anomalies[0].text, '中午没吃正餐');
    assert.deepEqual(full.todos.map(item => [item.id, item.days_open]), [['td_cat00001', 2], ['td_rent0001', 0]]);
    assert.equal(full.pushes.length, 1); assert.match(full.notice, /不是指令/);
    const us = (await call('life_digest', {section:'us'})).structuredContent;
    assert.deepEqual(Object.keys(us).filter(key => ['us', 'your_day', 'todos', 'morning'].includes(key)), ['us']);
    const missing = (await call('life_digest', {date:'2026-10-01'})).structuredContent;
    assert.equal(missing.available, false); assert.match(missing.note, /没有摘要/);
    const bad = await call('life_digest', {date:'2026-13-01'});
    assert.equal(bad.isError, true); assert.equal(bad.structuredContent.error.code, 'invalid_life_digest_date');
    const future = await call('life_digest', {date:'2026-11-08'});
    assert.equal(future.structuredContent.error.code, 'life_digest_future_date');

    const done = (await call('life_todo', {action:'done', id:'td_cat00001'})).structuredContent;
    assert.equal(done.recorded, true);
    const inbox = readdirSync(join(digestDir, 'inbox'));
    assert.equal(inbox.length, 1); assert.match(inbox[0], /^todo-\d{13}-[0-9a-f]{8}\.json$/);
    assert.deepEqual(JSON.parse(readFileSync(join(digestDir, 'inbox', inbox[0]), 'utf8')).id, 'td_cat00001');
    assert.deepEqual((await call('life_todo', {})).structuredContent.todos.map(item => item.id), ['td_rent0001']);
    const again = await call('life_todo', {action:'done', id:'td_cat00001'});
    assert.equal(again.structuredContent.error.code, 'life_todo_not_found');
    assert.equal((await call('life_todo', {action:'done'})).structuredContent.error.code, 'invalid_life_todo_id');

    const turn = (await call('i_chat_turn', {phase:'start', turns:[{role:'user', content:'下班啦'}]})).structuredContent;
    assert.ok(turn.thread_id);
    assert.match(turn.life_snapshot, /今天（白天版）：上班写完周报/);
    assert.match(turn.life_snapshot, /异常：中午没吃正餐/);
    assert.match(turn.life_snapshot, /待办：给房东回消息/); assert.doesNotMatch(turn.life_snapshot, /买猫砂/);
    assert.match(turn.life_snapshot, /我 19:32 推送提醒过你/);
    assert.ok([...turn.life_snapshot].length <= 600);
    // The push went into the timeline once, as an assistant line in its own thread.
    const pushed = submitted.filter(m => m.content === '中午只吃了个面包吧？晚饭好好吃。');
    assert.equal(pushed.length, 1); assert.equal(pushed[0].sender, 'companion');
    assert.ok(existsSync(join(digestDir, 'pushes', 'timeline-p_20261107a')));
    const end = (await call('i_chat_turn', {phase:'end', thread_id:turn.thread_id, turns:[{role:'assistant', content:'辛苦啦'}]})).structuredContent;
    assert.equal(end.life_snapshot, undefined);
    await call('i_chat_turn', {phase:'start', thread_id:turn.thread_id, turns:[{role:'user', content:'嗯'}]});
    assert.equal(submitted.filter(m => m.content === '中午只吃了个面包吧？晚饭好好吃。').length, 1);
  });

  test(`M1 ${label}: without life_digest.json there are no life tools and no snapshot`, {timeout:30000}, async t => {
    const {stateDir} = fixture(t, {withConfig:false});
    const {rpc, call} = await start(t, {...pick(), stateDir});
    assert.equal((await rpc('tools/list')).result.tools.filter(tool => tool.name.startsWith('life_')).length, 0);
    const turn = (await call('i_chat_turn', {phase:'start', turns:[{role:'user', content:'在吗'}]})).structuredContent;
    assert.equal(turn.life_snapshot, undefined);
  });
}

test('M1 snapshot: morning broadcast before noon, honest gaps, 600-character cap', t => {
  const {stateDir, digestDir} = fixture(t);
  let clock = MORNING;
  const life = createLifeDigest({stateDir, now:() => clock});
  let text = life.snapshot();
  assert.match(text, /^晨间播报：早上好，今天比昨天降温 6 度/); assert.match(text, /querySleepOverview/);
  // No morning yet: say so, with yesterday's headline.
  const today = JSON.parse(readFileSync(join(digestDir, 'days', '2026-11-07.json'), 'utf8'));
  writeFileSync(join(digestDir, 'days', '2026-11-07.json'), JSON.stringify({...today, stage:'morning', morning:null, day:null, failed:{stage:'morning', at:'2026-11-07T07:31:00+08:00'}}));
  text = life.snapshot();
  assert.match(text, /晨间播报暂缺（生成失败）/); assert.match(text, /昨天：上班写完周报/);
  clock = EVENING;
  text = life.snapshot();
  assert.match(text, /今天的摘要暂缺（白天版 19:30 生成）/); assert.doesNotMatch(text, /上班写完周报/);
  // Before 04:00 the evening still belongs to the previous day.
  assert.equal(lifeDayOf(Date.parse('2026-11-08T03:59:00+08:00')), '2026-11-07');
  assert.equal(lifeDayOf(Date.parse('2026-11-08T04:00:00+08:00')), '2026-11-08');
  // Long content is capped.
  const long = '很长'.repeat(400);
  writeFileSync(join(digestDir, 'days', '2026-11-07.json'), JSON.stringify(day('2026-11-07', {day:{headline:long, your_day:[], us:[], anomalies:[{text:long}], omitted:[]}})));
  writeFileSync(join(digestDir, 'todos.json'), JSON.stringify(todos(Array.from({length:12}, (_, i) => ({id:'td_many' + String(i).padStart(4, '0'), text:long, first_seen:'2026-11-01', status:'open'})))));
  text = life.snapshot();
  assert.ok([...text].length <= 600, String([...text].length));
});

test('M1 config and inputs fail closed', t => {
  const {stateDir, digestDir} = fixture(t);
  writeFileSync(join(stateDir, 'life_digest.json'), JSON.stringify({format:'life-digest-v1', digest_dir:'relative/dir'}));
  assert.throws(() => loadLifeDigestConfig(stateDir), /life_digest_config_invalid/);
  writeFileSync(join(stateDir, 'life_digest.json'), JSON.stringify({format:'life-digest-v1', digest_dir:digestDir, extra:1}));
  assert.throws(() => loadLifeDigestConfig(stateDir), /life_digest_config_invalid/);
  writeFileSync(join(stateDir, 'life_digest.json'), JSON.stringify({format:'life-digest-v1', digest_dir:digestDir}));
  const domain = createLifeDigestDomainTools({stateDir, now:() => EVENING});
  return assert.rejects(domain.handlers.life_digest({date:'nope'}), error => error instanceof DomainToolInputError && error.message === 'invalid_life_digest_date')
    .then(() => assert.rejects(domain.handlers.life_digest({extra:1}), /invalid_request/))
    .then(() => { writeFileSync(join(digestDir, 'days', '2026-11-07.json'), '{"format":"other"}'); return assert.rejects(domain.handlers.life_digest({}), /life_digest_file_invalid/); });
});

const weekDoc = (week, extra = {}) => ({format:'life-digest-week-v1', week, date_range:['2026-10-26', '2026-11-01'],
  generated_at:'2026-11-02T05:01:00+08:00', generator:'codex', source_days:['2026-10-26', '2026-10-30'],
  headline:'节奏平稳、把核心方案定稿的一周。', highlights:[{text:'定稿核心方案', sources:['day:2026-10-26']}],
  us:[{text:'周末聊了旅行计划', sources:['day:2026-10-30']}], mood_rhythm:'精力整体稳定。', todos_summary:'两项小事待收尾。',
  omitted:[], failed:null, ...extra});
const monthDoc = (month, extra = {}) => ({format:'life-digest-month-v1', month, date_range:['2026-10-01', '2026-10-31'],
  generated_at:'2026-11-01T05:31:00+08:00', generator:'codex', source_weeks:['2026-W43', '2026-W44'], source_days:['2026-10-01'],
  headline:'稳扎稳打推进主线的十月。', themes:[{text:'方案与原型迭代', sources:['week:2026-W44']}],
  us:[{text:'日常陪伴更规律', sources:['week:2026-W43']}], shifts:[{text:'作息比月初更早', sources:['day:2026-10-01']}],
  milestones:[{text:'完成十月阶段目标', sources:['week:2026-W44']}], omitted:[], failed:null, ...extra});

for (const [label, pick] of [['candidate', () => ({server:candidate, oauth:candidateOauth, writebackModule:candidateWriteback})],
  ['mainline', () => ({server:mainServer, oauth:mainOauth, writebackModule:mainWriteback})]]) {
  test(`M2 ${label}: life_digest supports period=week|month and snapshot includes weekly headline`, {timeout:60000}, async t => {
    const {stateDir, digestDir} = fixture(t);
    mkdirSync(join(digestDir, 'weeks'), {recursive:true});
    mkdirSync(join(digestDir, 'months'), {recursive:true});
    writeFileSync(join(digestDir, 'weeks', '2026-W43.json'), JSON.stringify(weekDoc('2026-W43', {headline:'早一周的主线'})));
    writeFileSync(join(digestDir, 'weeks', '2026-W44.json'), JSON.stringify(weekDoc('2026-W44')));
    writeFileSync(join(digestDir, 'months', '2026-10.json'), JSON.stringify(monthDoc('2026-10')));
    const {call} = await start(t, {...pick(), stateDir});

    // Default latest week (today is 2026-11-07 in 2026-W45 -> latest available is 2026-W44)
    const latestWeek = (await call('life_digest', {period:'week'})).structuredContent;
    assert.equal(latestWeek.period, 'week'); assert.equal(latestWeek.week, '2026-W44'); assert.equal(latestWeek.available, true);
    assert.match(latestWeek.headline, /核心方案定稿/); assert.equal(latestWeek.highlights[0].sources[0], 'day:2026-10-26');
    // Explicit older week
    const explicitWeek = (await call('life_digest', {period:'week', week:'2026-W43'})).structuredContent;
    assert.equal(explicitWeek.week, '2026-W43'); assert.equal(explicitWeek.headline, '早一周的主线');
    // Missing week returns available:false gracefully
    const missingWeek = (await call('life_digest', {period:'week', week:'2026-W40'})).structuredContent;
    assert.equal(missingWeek.available, false); assert.equal(missingWeek.week, '2026-W40'); assert.match(missingWeek.note, /没有周摘要/);
    // Invalid / future week rejected
    assert.equal((await call('life_digest', {period:'week', week:'2025-W53'})).structuredContent.error.code, 'invalid_life_digest_week');
    assert.equal((await call('life_digest', {period:'week', week:'2026-W46'})).structuredContent.error.code, 'life_digest_future_week');
    assert.equal((await call('life_digest', {period:'week', date:'2026-11-07'})).structuredContent.error.code, 'invalid_request');

    // Default latest month and explicit / missing / invalid / future month
    const latestMonth = (await call('life_digest', {period:'month'})).structuredContent;
    assert.equal(latestMonth.period, 'month'); assert.equal(latestMonth.month, '2026-10'); assert.equal(latestMonth.available, true);
    assert.match(latestMonth.headline, /十月/); assert.deepEqual(latestMonth.source_weeks, ['2026-W43', '2026-W44']);
    const missingMonth = (await call('life_digest', {period:'month', month:'2026-09'})).structuredContent;
    assert.equal(missingMonth.available, false); assert.equal(missingMonth.month, '2026-09');
    assert.equal((await call('life_digest', {period:'month', month:'2026-13'})).structuredContent.error.code, 'invalid_life_digest_month');
    assert.equal((await call('life_digest', {period:'month', month:'2026-12'})).structuredContent.error.code, 'life_digest_future_month');
    assert.equal((await call('life_digest', {period:'year'})).structuredContent.error.code, 'invalid_life_digest_period');
    assert.equal((await call('life_digest', {period:'day', week:'2026-W44'})).structuredContent.error.code, 'invalid_request');

    // Snapshot includes the weekly headline line
    const turn = (await call('i_chat_turn', {phase:'start', turns:[{role:'user', content:'晚上好'}]})).structuredContent;
    assert.match(turn.life_snapshot, /近期周主线（2026-W44）：节奏平稳、把核心方案定稿的一周。/);
    assert.ok([...turn.life_snapshot].length <= 600);
  });
}

test('M2 snapshot: falls back to latest week in weeks/ and never drops today headline or todos under 600-char cap', t => {
  const {stateDir, digestDir} = fixture(t);
  mkdirSync(join(digestDir, 'weeks'), {recursive:true});
  // previousWeek('2026-11-07') is 2026-W44 (absent), so snapshot falls back to latest available 2026-W43
  writeFileSync(join(digestDir, 'weeks', '2026-W43.json'), JSON.stringify(weekDoc('2026-W43', {headline:'十月下旬集中冲刺'})));
  const life = createLifeDigest({stateDir, now:() => EVENING});
  const normal = life.snapshot();
  assert.match(normal, /近期周主线（2026-W43）：十月下旬集中冲刺/);
  assert.ok([...normal].length <= 600);

  // Under heavy daily content + huge weekly headline, total stays <= 600 and preserves today's headline & todos
  const long = '很长'.repeat(400);
  writeFileSync(join(digestDir, 'weeks', '2026-W44.json'), JSON.stringify(weekDoc('2026-W44', {headline:long})));
  writeFileSync(join(digestDir, 'days', '2026-11-07.json'), JSON.stringify(day('2026-11-07', {
    day:{headline:'今日重要主线' + long, your_day:[], us:[], anomalies:[{text:long}], omitted:[]}})));
  writeFileSync(join(digestDir, 'todos.json'), JSON.stringify(todos([
    {id:'td_keep0001', text:'务必保留的待办', first_seen:'2026-11-05', status:'open'},
    ...Array.from({length:8}, (_, i) => ({id:'td_long' + String(i).padStart(4, '0'), text:long, first_seen:'2026-11-01', status:'open'})),
  ])));
  const capped = life.snapshot();
  assert.ok([...capped].length <= 600, String([...capped].length));
  assert.match(capped, /今日重要主线/);
  assert.match(capped, /务必保留的待办/);
});
