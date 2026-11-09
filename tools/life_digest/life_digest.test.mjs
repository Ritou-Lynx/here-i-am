// Synthetic data only: no live accounts, databases, model calls or pushes.
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { test } from 'node:test';
import * as lib from './life_digest_lib.mjs';
import { readChatRange } from './chat_source.mjs';
import { generate, main, runStage, loadConfig, openStore } from './life_digest_run.mjs';
import { openReadModel } from '../i_core/test_fixtures/release_schema6/mcp_reader/legacy/i_memory/i_memory_read.mjs';
import { createLifeDigest } from '../i_remote_mcp/life_digest.mjs';

const at = iso => Date.parse(iso);
const PRIMARY = 'char-lin-ai';

test('day boundary and due stages follow 04:30 / 07:30 / 19:30', () => {
  assert.equal(lib.dayOf(at('2026-11-08T03:59:00+08:00')), '2026-11-07');
  assert.equal(lib.dayOf(at('2026-11-08T04:00:00+08:00')), '2026-11-08');
  const none = () => false;
  assert.deepEqual(lib.dueStages(at('2026-11-08T04:20:00+08:00'), none), []);
  assert.deepEqual(lib.dueStages(at('2026-11-08T04:30:00+08:00'), none), [{ kind: 'final', date: '2026-11-07' }]);
  assert.deepEqual(lib.dueStages(at('2026-11-08T07:31:00+08:00'), none).map(s => s.kind), ['final', 'morning']);
  assert.deepEqual(lib.dueStages(at('2026-11-08T13:00:00+08:00'), none).map(s => s.kind), ['final']);
  assert.deepEqual(lib.dueStages(at('2026-11-08T19:30:00+08:00'), none).map(s => s.kind), ['final', 'day']);
  // Logon catch-up at 01:00 still belongs to yesterday's day version.
  assert.deepEqual(lib.dueStages(at('2026-11-09T01:00:00+08:00'), (d, p) => d === '2026-11-07' && p === 'final'), [{ kind: 'day', date: '2026-11-08' }]);
  const done = (d, p) => p !== 'final';
  assert.deepEqual(lib.dueStages(at('2026-11-08T21:00:00+08:00'), done), [{ kind: 'final', date: '2026-11-07' }]);
});

test('weather says only what changed', () => {
  const casts = lib.parseAmapForecast({ status: '1', forecasts: [{ casts: [
    { date: '2026-11-08', dayweather: '小雨', nightweather: '阴', daytemp: '9', nighttemp: '2', daywind: '北', daypower: '5-6' }] }] });
  const yesterday = { date: '2026-11-07', dayweather: '晴', nightweather: '晴', daytemp: 15, nighttemp: 8, daywind: '南', daypower: '≤3' };
  assert.equal(lib.weatherText(casts[0], yesterday, '海淀'), '海淀今天小雨转阴，2–9°C，比昨天降温 6 度，有降水，记得带伞，北风 5-6 级。');
  assert.equal(lib.weatherText({ ...yesterday, date: '2026-11-08', daytemp: 16 }, yesterday), '今天晴，8–16°C，气温和昨天差不多。');
  assert.throws(() => lib.parseAmapForecast({ status: '0', info: 'INVALID_USER_KEY' }), /weather_response_invalid/);
});

test('todos: inbox, model findings, dedupe, staleness', () => {
  let state = lib.emptyTodos();
  ({ state } = lib.mergeTodos(state, { date: '2026-11-01', nowIso: 'x', newTodos: [{ text: '买猫砂', quote: '要买猫砂', source: 'notes:a' }, { text: '买猫砂。', quote: 'dup', source: 'chat:1' }] }));
  assert.equal(state.items.length, 1);
  const id = state.items[0].id;
  assert.match(id, /^td_[0-9a-f]{12}$/);
  assert.deepEqual(lib.staleTodos(state, '2026-11-07'), []);
  assert.deepEqual(lib.staleTodos(state, '2026-11-08').map(t => t.id), [id]);
  const merged = lib.mergeTodos(state, { date: '2026-11-08', nowIso: 'y', inbox: [{ id, action: 'done', at: 'z' }], newTodos: [{ text: '回房东', quote: '回房东', source: 'chat:2' }] });
  assert.deepEqual(merged.changed, { done: [id], dropped: [], added: [merged.state.items[1].id] });
  assert.equal(merged.state.items[0].closed_by, 'life_todo');
  assert.deepEqual(lib.openTodos(merged.state, '2026-11-08').map(t => t.text), ['回房东']);
});

test('nudges: skipped lunch only when food is being logged, quiet hours, no call keyword', () => {
  const food = entries => ({ entries: entries.map(time => ({ eaten_at: `2026-11-07T${time}:00+08:00` })) });
  assert.deepEqual(lib.nudgeTriggers({ kind: 'day', food: food(['08:00', '19:00']), stale: [] }).map(t => t.rule), ['no_lunch']);
  assert.deepEqual(lib.nudgeTriggers({ kind: 'day', food: food(['12:20']), stale: [] }), []);
  assert.deepEqual(lib.nudgeTriggers({ kind: 'day', food: food([]), stale: [] }), []);
  assert.deepEqual(lib.nudgeTriggers({ kind: 'final', food: food(['08:00']), stale: [] }), []);
  assert.equal(lib.canPush({ pushesToday: 0, nowMs: at('2026-11-07T19:30:00+08:00') }), true);
  assert.equal(lib.canPush({ pushesToday: 2, nowMs: at('2026-11-07T19:30:00+08:00') }), false);
  assert.equal(lib.canPush({ pushesToday: 0, nowMs: at('2026-11-08T01:00:00+08:00') }), false);
  assert.doesNotMatch(lib.sanitizeNudge('林埃来电：快睡'), /林埃来电/);
});

test('model output is checked: unknown sources dropped, todos need a real source, nudge required when asked', () => {
  const ok = lib.validateDayOutput({ headline: '平常的一天', your_day: [{ text: '上班', sources: ['notes:a', 'chat:invented'] }], us: [], anomalies: [{ text: '没吃午饭', sources: ['food:2026-11-07'], level: 'warn' }],
    todos_new: [{ text: '买猫砂', quote: '要买猫砂', source: 'notes:a' }, { text: '编的', quote: '', source: 'chat:invented' }], todos_done: ['td_x', 'td_unknown'], omitted: [], nudge: '' },
  { sources: ['notes:a', 'food:2026-11-07'], openIds: ['td_x'], wantNudge: false });
  assert.deepEqual(ok.your_day[0].sources, ['notes:a']);
  assert.deepEqual(ok.todos_new.map(t => t.text), ['买猫砂']);
  assert.deepEqual(ok.todos_done, ['td_x']);
  assert.throws(() => lib.validateDayOutput({ headline: 'x' }, { sources: [], openIds: [], wantNudge: true }), /nudge/);
  assert.throws(() => lib.validateDayOutput({ your_day: [] }, { sources: [], openIds: [], wantNudge: false }), /headline/);
  assert.deepEqual(lib.parseModelJson('```json\n{"broadcast":"早"}\n```'), { broadcast: '早' });
  assert.throws(() => lib.parseModelJson('抱歉，我不能'), /model_output_not_json/);
});

test('generate: Codex retry with feedback, then API fallback, then failure', async () => {
  const calls = [];
  const runners = { codex: async (_c, prompt) => { calls.push(['codex', prompt.includes('上一次的输出不合格')]); return calls.length === 1 ? 'nope' : '{"broadcast":"早安"}'; },
    openai: async () => { calls.push(['openai']); return '{}'; } };
  const r = await generate({ config: { openai: null }, st: null, prompt: 'p', validate: lib.validateMorningOutput, runners });
  assert.equal(r.generator, 'codex'); assert.deepEqual(calls, [['codex', false], ['codex', true]]);
  const r2 = await generate({ config: { openai: {} }, st: null, prompt: 'p', validate: lib.validateMorningOutput,
    runners: { codex: async () => { throw new Error('codex_failed:1'); }, openai: async () => '{"broadcast":"兜底"}' } });
  assert.equal(r2.generator, 'openai'); assert.equal(r2.errors.length, 2);
  await assert.rejects(generate({ config: { openai: null }, st: null, prompt: 'p', validate: lib.validateMorningOutput,
    runners: { codex: async () => { throw new Error('codex_failed:1'); } } }), /generation_failed/);
});

function chatFixture(dir) {
  const dbPath = join(dir, 'core.sqlite');
  const db = new DatabaseSync(dbPath);
  db.exec(`CREATE TABLE chat_messages (sync_id TEXT PRIMARY KEY, character_id TEXT, sender TEXT, content TEXT, created_at_ms INTEGER,
    message_type TEXT, origin_device_id TEXT, server_sequence INTEGER UNIQUE);
    CREATE TABLE devices (device_id TEXT PRIMARY KEY, platform TEXT);`);
  db.prepare('INSERT INTO devices VALUES (?, ?)').run('phone-1', 'android');
  const insert = db.prepare('INSERT INTO chat_messages VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
  const rows = [
    ['m1', PRIMARY, 'user', '今天要买猫砂', at('2026-11-07T09:00:00+08:00'), 'chat', 'frontend:claude_web'],
    ['m2', PRIMARY, 'companion', '好呀，记得买', at('2026-11-07T09:01:00+08:00'), 'chat', 'frontend:claude_web'],
    ['m3', PRIMARY, 'user', 'SECRET_WORD 不该出现', at('2026-11-07T10:00:00+08:00'), 'chat', 'frontend:claude_web'],
    ['m4', PRIMARY, 'user', '手机上说的话', at('2026-11-07T11:00:00+08:00'), 'chat', 'phone-1'],
    ['m5', PRIMARY, 'user', '没批准的设备', at('2026-11-07T11:30:00+08:00'), 'chat', 'other-device'],
    ['m6', 'other-character', 'user', '别的角色', at('2026-11-07T12:00:00+08:00'), 'chat', 'frontend:claude_web'],
    ['m7', PRIMARY, 'user', '前一天的话', at('2026-11-07T03:00:00+08:00'), 'chat', 'frontend:claude_web'],
    ['m8', PRIMARY, 'user', '私密类型', at('2026-11-07T13:00:00+08:00'), 'diary', 'frontend:claude_web'],
  ];
  rows.forEach((row, i) => insert.run(...row, i + 1));
  db.close();
  const policyPath = join(dir, 'policy.json');
  writeFileSync(policyPath, JSON.stringify({ schema_version: 1, primary_character_id: PRIMARY,
    messages: { default: 'private', shareable_character_ids: [PRIMARY], private_message_types: ['diary'], private_keywords: ['secret_word'],
      shareable_message_ids: [], shareable_message_hashes: {}, auto_share_origins: ['claude_web'],
      auto_share_devices: [{ device_id: 'phone-1', from_server_sequence: 1 }] },
    memory: { default: 'shareable', private_types: [], private_structured_types: [], private_card_ids: [], private_keywords: [] } }));
  return { dbPath, policyPath };
}

test('chat range uses exactly the MCP read model sharing filter', t => {
  const dir = mkdtempSync(join(tmpdir(), 'life-digest-chat-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const { dbPath, policyPath } = chatFixture(dir);
  const [from, to] = lib.dayRange('2026-11-07');
  const range = readChatRange({ coreDbPath: dbPath, policyPath, fromMs: from, toMs: to });
  assert.deepEqual(range.messages.map(m => m.id), ['m1', 'm2', 'm4']);
  const model = openReadModel({ coreDbPath: dbPath, memoryDbPath: join(dir, 'none.sqlite'), policyPath });
  const recent = model.recentMessages({ limit: 100 }).filter(m => m.createdAtMs >= from && m.createdAtMs < to).map(m => m.syncId);
  model.close();
  assert.deepEqual(range.messages.map(m => m.id), recent);
});

function generatorFixture(t, { ntfy = true } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'life-digest-run-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const { dbPath, policyPath } = chatFixture(dir);
  const digestDir = join(dir, 'digest'), hrDir = join(dir, 'heart_rate');
  mkdirSync(hrDir);
  writeFileSync(join(hrDir, 'minutes-2026-11-07.jsonl'), [
    { ms: at('2026-11-07T09:00:00+08:00'), n: 60, med: 72, min: 70, max: 75 }, { ms: at('2026-11-07T23:00:00+08:00'), n: 60, med: 60, min: 58, max: 63 }]
    .map(r => JSON.stringify(r)).join('\n') + '\n');
  const configPath = join(dir, 'generator.json');
  writeFileSync(configPath, JSON.stringify({ format: 'life-digest-generator-v1', digest_dir: digestDir, chat: { core_db: dbPath, policy: policyPath },
    heart_rate_dir: hrDir, codex: { argv: ['codex'], model: 'synthetic-model' },
    ...(ntfy ? { ntfy: { server: 'https://ntfy.example', topic: 'synthetic-topic-1234' } } : {}) }));
  return { dir, digestDir, configPath };
}

test('generator end to end: day version, todos, push into timeline file, then MCP snapshot reads it', async t => {
  const { digestDir, configPath } = generatorFixture(t);
  const prompts = [], pushes = [];
  const reply = { headline: '上班、买了猫砂，晚上聊得很开心。', your_day: [{ text: '上午说要买猫砂', sources: ['chat:m1'] }],
    us: [{ text: '早上互相打气', sources: ['chat:m2'] }], anomalies: [], todos_new: [{ text: '买猫砂', quote: '今天要买猫砂', source: 'chat:m1' }],
    todos_done: [], omitted: [], nudge: '' };
  const runners = { codex: async (_c, prompt) => { prompts.push(prompt); return JSON.stringify(reply); } };
  const rows = await main(['--config', configPath], { now: () => at('2026-11-07T19:30:00+08:00'), runners, notify: async (_c, text) => pushes.push(text) });
  // Catch-up: 11-06 final, then the 19:30 day version.
  assert.deepEqual(rows.map(r => [r.stage, r.date, r.ok]), [['final', '2026-11-06', true], ['day', '2026-11-07', true]]);
  // 11-06's day ends at 11-07 04:00, so the 03:00 line belongs to it.
  assert.match(prompts[0], /前一天的话/);
  const prompt = prompts[1];
  assert.match(prompt, /\[chat:m1\] 09:00 你：今天要买猫砂/); assert.match(prompt, /\[chat:m2\] 09:01 林埃：/);
  assert.doesNotMatch(prompt, /SECRET_WORD|私密类型|前一天的话|别的角色/);
  assert.match(prompt, /\[hr:2026-11-07\] 有数据 2 分钟/);
  assert.match(prompt, /日记暂缺/);
  const day = JSON.parse(readFileSync(join(digestDir, 'days', '2026-11-07.json'), 'utf8'));
  assert.equal(day.stage, 'day'); assert.equal(day.generator, 'codex'); assert.equal(day.day.headline, reply.headline);
  assert.equal(day.sources_status.notes, 'not_configured'); assert.equal(day.todos[0].text, '买猫砂');
  const todos = JSON.parse(readFileSync(join(digestDir, 'todos.json'), 'utf8'));
  assert.equal(todos.items.length, 1);
  assert.deepEqual(pushes, []); // no food logged → no skipped-lunch nudge
  // Nothing due a second time.
  const again = await main(['--config', configPath], { now: () => at('2026-11-07T19:40:00+08:00'), runners });
  assert.deepEqual(again, [{ stage: 'none', ok: true, detail: 'nothing_due' }]);
  // The MCP module reads the same directory.
  const stateDir = join(digestDir, '..', 'mcp-state'); mkdirSync(stateDir);
  writeFileSync(join(stateDir, 'life_digest.json'), JSON.stringify({ format: 'life-digest-v1', digest_dir: digestDir }));
  const life = createLifeDigest({ stateDir, now: () => at('2026-11-07T21:00:00+08:00') });
  assert.match(life.snapshot(), /今天（白天版）：上班、买了猫砂/); assert.match(life.snapshot(), /待办：买猫砂/);
  // life_todo done → applied (and inbox cleared) by the next generator run.
  const id = todos.items[0].id;
  await life.handlers.life_todo({ action: 'done', id });
  assert.equal(readdirSync(join(digestDir, 'inbox')).length, 1);
  await main(['--config', configPath, '--stage', 'final', '--date', '2026-11-07', '--no-push'], { now: () => at('2026-11-08T04:30:00+08:00'), runners });
  assert.equal(readdirSync(join(digestDir, 'inbox')).length, 0);
  const closed = JSON.parse(readFileSync(join(digestDir, 'todos.json'), 'utf8')).items.find(i => i.id === id);
  assert.equal(closed.status, 'done'); assert.equal(closed.closed_by, 'life_todo');
  assert.equal(JSON.parse(readFileSync(join(digestDir, 'days', '2026-11-07.json'), 'utf8')).stage, 'final');
});

test('generator pushes a skipped-lunch nudge once, and failure keeps the old content marked as failed', async t => {
  const { digestDir, configPath } = generatorFixture(t);
  const config = loadConfig(configPath);
  const breakfast = { eaten_at: '2026-11-07T08:10:00+08:00', items: [{ name: '面包' }], totals: { kcal: 300 }, local_date: '2026-11-07' };
  const db = new DatabaseSync(config.chat.coreDb);
  db.exec('CREATE TABLE domain_records (namespace TEXT, domain TEXT, id TEXT, revision INTEGER, envelope_json TEXT, body_json TEXT)');
  const add = db.prepare('INSERT INTO domain_records VALUES (?, ?, ?, 1, ?, ?)');
  add.run('production', 'food_entries', 'f1', JSON.stringify({ deleted_at: null }), JSON.stringify({ data: breakfast }));
  add.run('production', 'food_entries', 'f2', JSON.stringify({ deleted_at: '2026-11-07T13:00:00Z' }), JSON.stringify({ data: { ...breakfast, eaten_at: '2026-11-07T12:30:00+08:00' } }));
  add.run('shadow', 'food_entries', 'f3', JSON.stringify({ deleted_at: null }), JSON.stringify({ data: { ...breakfast, eaten_at: '2026-11-07T12:40:00+08:00' } }));
  add.run('production', 'food_entries', 'f4', JSON.stringify({ deleted_at: null }), JSON.stringify({ data: { ...breakfast, eaten_at: '2026-11-07T12:50:00+08:00', voided: true } }));
  db.close();
  const st = openStore(config.digestDir);
  const pushes = [];
  let prompt = '';
  const runners = { codex: async (_c, p) => { prompt = p; return JSON.stringify({ headline: '中午没吃饭', your_day: [], us: [],
    anomalies: [{ text: '中午没吃', sources: ['food:2026-11-07'] }], todos_new: [], todos_done: [], omitted: [], nudge: '林埃来电！中午怎么没吃饭呀，晚饭好好吃。' }); } };
  const notify = async (_c, text) => pushes.push(text);
  const result = await runStage({ config, st, kind: 'day', date: '2026-11-07', nowMs: at('2026-11-07T19:35:00+08:00'), runners, notify });
  assert.deepEqual(result.pushed, ['no_lunch']);
  assert.match(prompt, /【需要催的事】/); assert.match(prompt, /\[food:2026-11-07\]\n08:10 面包，约 300 kcal/);
  assert.equal(pushes.length, 1); assert.doesNotMatch(pushes[0], /林埃来电/);
  const lines = readFileSync(join(digestDir, 'pushes', '2026-11-07.jsonl'), 'utf8').trim().split('\n').map(l => JSON.parse(l));
  assert.equal(lines.length, 1); assert.match(lines[0].id, /^p_20261107_[0-9a-f]{8}$/);
  // The cap holds: with max_per_day 1 a second run does not push again.
  config.ntfy.max = 1;
  const second = await runStage({ config, st, kind: 'day', date: '2026-11-07', nowMs: at('2026-11-07T20:00:00+08:00'), runners, notify });
  assert.equal(second.pushed, null); assert.equal(pushes.length, 1);
  // A failing model keeps the day content and marks the failure.
  const failed = await runStage({ config, st, kind: 'final', date: '2026-11-07', nowMs: at('2026-11-08T04:30:00+08:00'),
    runners: { codex: async () => { throw new Error('codex_failed:1'); } } });
  assert.equal(failed.ok, false);
  const day = JSON.parse(readFileSync(join(digestDir, 'days', '2026-11-07.json'), 'utf8'));
  assert.equal(day.day.headline, '中午没吃饭'); assert.equal(day.failed.stage, 'final'); assert.equal(day.stage, 'day');
});

test('morning: AI broadcast, or a plain template when the model fails', async t => {
  const { digestDir, configPath } = generatorFixture(t, { ntfy: false });
  const runners = { codex: async () => '{"broadcast":"早上好呀，今天要记得买猫砂。"}' };
  const rows = await main(['--config', configPath, '--stage', 'morning', '--date', '2026-11-08'], { now: () => at('2026-11-08T07:30:00+08:00'), runners });
  assert.equal(rows[0].generator, 'codex'); assert.equal(rows[0].weather, 'not_configured');
  assert.equal(JSON.parse(readFileSync(join(digestDir, 'days', '2026-11-08.json'), 'utf8')).morning.text, '早上好呀，今天要记得买猫砂。');
  const rows2 = await main(['--config', configPath, '--stage', 'morning', '--date', '2026-11-09'], { now: () => at('2026-11-09T07:30:00+08:00'),
    runners: { codex: async () => { throw new Error('codex_failed:1'); } } });
  assert.equal(rows2[0].generator, 'template');
  assert.equal(JSON.parse(readFileSync(join(digestDir, 'days', '2026-11-09.json'), 'utf8')).morning.text, '早上好。');
});


test('an empty day needs no model call', async t => {
  const { digestDir, configPath } = generatorFixture(t, { ntfy: false });
  const rows = await main(['--config', configPath, '--stage', 'final', '--date', '2026-11-01'], { now: () => at('2026-11-02T04:30:00+08:00'),
    runners: { codex: async () => { throw new Error('must not be called'); } } });
  assert.deepEqual(rows.map(r => [r.ok, r.generator]), [[true, 'none']]);
  assert.match(JSON.parse(readFileSync(join(digestDir, 'days', '2026-11-01.json'), 'utf8')).day.headline, /没有/);
});

test('diary of the day (04:00 boundary) goes into the prompt as notes sources', async t => {
  const { dir, digestDir, configPath } = generatorFixture(t, { ntfy: false });
  const notes = join(dir, 'notes');
  mkdirSync(join(notes, '日记-日报'), { recursive: true });
  const index = { format: 'notes-v1', folders: [{ name: '日记/日报', dir: '日记-日报' }], last_run: { at: '2026-11-07T10:00:00.000Z' }, docs: {} };
  for (const [token, modified, body] of [['docToday', '2026-11-07T03:00:00.000Z', '下午写周报。明天要给房东回消息。'], ['docOld', '2026-11-06T10:00:00.000Z', '前一天']]) {
    const file = `日记-日报/${token}.md`;
    writeFileSync(join(notes, file), ['---', 'title: "日记"', '---', '', body].join('\n') + '\n');
    index.docs[token] = { title: '日记 ' + token, folder: '日记/日报', top: '日记-日报', url: null, modified, file, chars: body.length };
  }
  writeFileSync(join(notes, 'index.json'), JSON.stringify(index));
  const config = JSON.parse(readFileSync(configPath, 'utf8'));
  writeFileSync(configPath, JSON.stringify({ ...config, notes_dir: notes }));
  let prompt = '';
  const runners = { codex: async (_c, p) => { prompt = p; return JSON.stringify({ headline: '写周报的一天', your_day: [{ text: '写周报', sources: ['notes:docToday'] }], us: [], anomalies: [],
    todos_new: [{ text: '给房东回消息', quote: '明天要给房东回消息', source: 'notes:docToday' }], todos_done: [], omitted: [], nudge: '' }); } };
  const rows = await main(['--config', configPath, '--stage', 'day', '--date', '2026-11-07'], { now: () => at('2026-11-07T19:30:00+08:00'), runners });
  assert.equal(rows[0].ok, true); assert.equal(rows[0].sources.notes, 'ok');
  assert.match(prompt, /\[notes:docToday\] 《日记 docToday》/); assert.doesNotMatch(prompt, /前一天/);
  const day = JSON.parse(readFileSync(join(digestDir, 'days', '2026-11-07.json'), 'utf8'));
  assert.deepEqual(day.day.your_day[0].sources, ['notes:docToday']);
  assert.equal(day.todos[0].text, '给房东回消息');
});

 test('morning keeps carried tasks separate from today appointments, including fallback', () => {
  const todos = [{ text: '明天上午9:30出发看病', first_seen: '2026-11-07', days_open: 2 }];
  const input = { date: '2026-11-09', weather: null, yesterday: null, todos };
  const prompt = lib.buildMorningPrompt(input);
  assert.match(prompt, /记录日期：2026-11-07/);
  assert.match(prompt, /不得把旧预约或旧计划说成今天要做/);
  assert.doesNotMatch(prompt, /【今天的待办】/);
  const fallback = lib.fallbackMorning(input);
  assert.match(fallback, /不是今日预约/);
  assert.match(fallback, /2026-11-07/);
  assert.doesNotMatch(fallback, /今天记得/);
  assert.match(lib.morningTodoText({ text: '买书' }), /日期未知.*未确认执行日期/);
});
