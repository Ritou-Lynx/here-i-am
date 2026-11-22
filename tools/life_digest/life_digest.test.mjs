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

test('M2 ISO week and calendar month helpers handle year boundaries and 53-week years', () => {
  assert.equal(lib.validWeek('2026-W01'), true);
  assert.equal(lib.validWeek('2026-W53'), true);
  assert.equal(lib.validWeek('2025-W53'), false);
  assert.equal(lib.validWeek('2026-W00'), false);
  assert.equal(lib.validWeek('2026-W54'), false);
  assert.equal(lib.validWeek('2026-11'), false);
  assert.equal(lib.validMonth('2026-01'), true);
  assert.equal(lib.validMonth('2026-12'), true);
  assert.equal(lib.validMonth('2026-00'), false);
  assert.equal(lib.validMonth('2026-13'), false);
  assert.equal(lib.isoWeekOf('2025-12-28'), '2025-W52');
  assert.equal(lib.isoWeekOf('2025-12-29'), '2026-W01');
  assert.equal(lib.isoWeekOf('2026-12-31'), '2026-W53');
  assert.equal(lib.isoWeekOf('2027-01-03'), '2026-W53');
  assert.equal(lib.isoWeekOf('2027-01-04'), '2027-W01');
  // 04:00 boundary on Monday morning
  assert.equal(lib.isoWeekOf(at('2026-11-09T03:59:00+08:00')), '2026-W45');
  assert.equal(lib.isoWeekOf(at('2026-11-09T04:00:00+08:00')), '2026-W46');
  assert.deepEqual(lib.weekDates('2026-W45'), ['2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06', '2026-11-07', '2026-11-08']);
  assert.equal(lib.weekDates('2026-W01')[0], '2025-12-29');
  assert.deepEqual(lib.weekDates('2025-W53'), []);
  assert.equal(lib.previousWeek('2026-W01'), '2025-W52');
  assert.equal(lib.previousWeek('2027-W01'), '2026-W53');
  assert.equal(lib.previousWeek('2026-11-09'), '2026-W45');
  assert.equal(lib.previousWeek(at('2026-11-09T03:59:00+08:00')), '2026-W44');
  assert.equal(lib.previousMonth('2026-01'), '2025-12');
  assert.equal(lib.previousMonth('2026-11-09'), '2026-10');
  assert.equal(lib.monthDates('2024-02').length, 29);
  assert.equal(lib.monthDates('2026-02').length, 28);
  assert.equal(lib.monthDates('2026-11').length, 30);
  assert.deepEqual(lib.weeksInMonth('2026-11'), ['2026-W44', '2026-W45', '2026-W46', '2026-W47', '2026-W48', '2026-W49']);
});

test('M2 period scheduling: Monday 05:00 weekly, day-1 05:30 monthly, catch-up, and combined dueStages', () => {
  const none = () => false;
  // Monday 2026-11-09 (day 9 of month): week waits until 05:00; month (2026-10) is in catch-up.
  assert.deepEqual(lib.duePeriodStages(at('2026-11-09T04:59:00+08:00'), none), [{ kind: 'month', period: '2026-10' }]);
  assert.deepEqual(lib.duePeriodStages(at('2026-11-09T05:00:00+08:00'), none), [{ kind: 'week', period: '2026-W45' }, { kind: 'month', period: '2026-10' }]);
  // Tuesday 04:10 catch-up for week
  assert.deepEqual(lib.duePeriodStages(at('2026-11-10T04:10:00+08:00'), (k, p) => k === 'month' && p === '2026-10'), [{ kind: 'week', period: '2026-W45' }]);
  // Monday + Day 1 overlap: 2026-06-01 is Monday
  assert.deepEqual(lib.duePeriodStages(at('2026-06-01T04:59:00+08:00'), none), []);
  assert.deepEqual(lib.duePeriodStages(at('2026-06-01T05:00:00+08:00'), none), [{ kind: 'week', period: '2026-W22' }]);
  assert.deepEqual(lib.duePeriodStages(at('2026-06-01T05:29:00+08:00'), none), [{ kind: 'week', period: '2026-W22' }]);
  assert.deepEqual(lib.duePeriodStages(at('2026-06-01T05:30:00+08:00'), none), [{ kind: 'week', period: '2026-W22' }, { kind: 'month', period: '2026-05' }]);
  // Integrated 3-arg dueStages runs daily final before week and month
  assert.deepEqual(lib.dueStages(at('2026-06-01T05:30:00+08:00'), none, none), [
    { kind: 'final', date: '2026-05-31' }, { kind: 'week', period: '2026-W22' }, { kind: 'month', period: '2026-05' },
  ]);
  // Already generated periods are omitted
  assert.deepEqual(lib.duePeriodStages(at('2026-06-01T06:00:00+08:00'), () => true), []);
});

test('M2 week and month prompts and validators enforce source allowlists', () => {
  const days = [
    { date: '2026-11-02', stage: 'final', day: { headline: '周一开工', your_day: [{ text: '写方案' }], us: [{ text: '晚上聊了电影' }], anomalies: [] } },
    { date: '2026-11-05', stage: 'day', day: { headline: '周四加班', your_day: [{ text: '修 bug' }], us: [], anomalies: [{ text: '晚睡' }] } },
  ];
  const weekPrompt = lib.buildWeekPrompt({ week: '2026-W45', days, todos: [{ text: '买猫砂', days_open: 3 }] });
  assert.match(weekPrompt, /\[day:2026-11-02\]（定稿）/);
  assert.match(weekPrompt, /\[day:2026-11-05\]（白天版）/);
  assert.match(weekPrompt, /买猫砂（已拖 3 天）/);
  const weekValid = lib.validateWeekOutput({
    headline: '专注推进项目的一周',
    highlights: [{ text: '完成方案并修复关键问题', sources: ['day:2026-11-02', 'day:2026-11-02', 'day:2026-11-03', 'chat:m1'] }],
    us: [{ text: '聊了电影互相放松', sources: ['day:2026-11-02', 'week:2026-W45'] }],
    mood_rhythm: '前半周稳，周四略累。',
    todos_summary: '买猫砂还没划掉。',
    omitted: [],
  }, { sources: ['day:2026-11-02', 'day:2026-11-05'] });
  assert.deepEqual(weekValid.highlights[0].sources, ['day:2026-11-02']);
  assert.deepEqual(weekValid.us[0].sources, ['day:2026-11-02']);
  assert.throws(() => lib.validateWeekOutput({ highlights: [] }, { sources: ['day:2026-11-02'] }), /headline/);

  const monthPrompt = lib.buildMonthPrompt({
    month: '2026-11',
    weeks: [{ week: '2026-W45', date_range: ['2026-11-02', '2026-11-08'], headline: '推进项目', highlights: [{ text: '写方案' }], us: [], mood_rhythm: '平稳', todos_summary: '' }],
    days: [{ date: '2026-11-30', stage: 'final', day: { headline: '月底复盘', your_day: [], us: [], anomalies: [] } }],
  });
  assert.match(monthPrompt, /\[week:2026-W45\]/);
  assert.match(monthPrompt, /\[day:2026-11-30\]/);
  const monthValid = lib.validateMonthOutput({
    headline: '稳步收官的十一月',
    themes: [{ text: '核心项目落地', sources: ['week:2026-W45', 'week:2026-W46', 'chat:x'] }],
    us: [{ text: '节奏更默契', sources: ['week:2026-W45'] }],
    shifts: [{ text: '月底开始复盘作息', sources: ['day:2026-11-30', 'day:2026-11-01'] }],
    milestones: [{ text: '完成方案', sources: ['week:2026-W45'] }],
    omitted: [],
  }, { sources: ['week:2026-W45', 'day:2026-11-30'] });
  assert.deepEqual(monthValid.themes[0].sources, ['week:2026-W45']);
  assert.deepEqual(monthValid.shifts[0].sources, ['day:2026-11-30']);
  assert.throws(() => lib.validateMonthOutput({ themes: [] }, { sources: ['week:2026-W45'] }), /headline/);
});

test('M2 generator: week and month stages, no-data skip, store listing, and auto catch-up', async t => {
  const { digestDir, configPath } = generatorFixture(t, { ntfy: false });
  const st = openStore(digestDir);
  // Empty week and month skip model call
  const skipWeek = await main(['--config', configPath, '--stage', 'week', '--period', '2026-W44'], {
    now: () => at('2026-11-09T05:00:00+08:00'),
    runners: { codex: async () => { throw new Error('must not be called'); } },
  });
  assert.deepEqual(skipWeek, [{ stage: 'week', period: '2026-W44', ok: true, skipped: 'no_data' }]);
  assert.equal(st.week('2026-W44'), null);
  const skipMonth = await main(['--config', configPath, '--stage', 'month', '--period', '2026-10'], {
    now: () => at('2026-11-09T05:30:00+08:00'),
    runners: { codex: async () => { throw new Error('must not be called'); } },
  });
  assert.deepEqual(skipMonth, [{ stage: 'month', period: '2026-10', ok: true, skipped: 'no_data' }]);
  assert.equal(st.month('2026-10'), null);

  // Seed days in 2026-W45 (one final, one day fallback, one generator:'none' ignored)
  st.saveDay('2026-11-02', { stage: 'final', generator: 'codex', day: { headline: '周一写设计文档', your_day: [{ text: '写文档', sources: ['notes:a'] }], us: [{ text: '互相加油', sources: ['chat:1'] }], anomalies: [], omitted: [] } });
  st.saveDay('2026-11-04', { stage: 'day', generator: 'codex', day: { headline: '周三跑通测试', your_day: [{ text: '跑测试', sources: ['chat:2'] }], us: [], anomalies: [], omitted: [] } });
  st.saveDay('2026-11-05', { stage: 'final', generator: 'none', day: { headline: '这天没有聊天、日记、饮食或心率记录。', your_day: [], us: [], anomalies: [], omitted: [] } });
  // Also seed a trailing day in November outside W45 so month mixes weekly + uncovered daily
  st.saveDay('2026-11-30', { stage: 'final', generator: 'codex', day: { headline: '月底整理清单', your_day: [{ text: '整理清单', sources: ['notes:b'] }], us: [], anomalies: [], omitted: [] } });

  const weekPrompts = [];
  const weekRunners = { codex: async (_c, p) => {
    weekPrompts.push(p);
    return JSON.stringify({
      headline: '从设计文档到跑通测试的一周',
      highlights: [{ text: '写文档并跑通测试', sources: ['day:2026-11-02', 'day:2026-11-04', 'day:2026-11-05'] }],
      us: [{ text: '周一互相打气', sources: ['day:2026-11-02'] }],
      mood_rhythm: '节奏紧凑但踏实。',
      todos_summary: '暂无积压。',
      omitted: [],
    });
  } };
  const weekRows = await main(['--config', configPath, '--stage', 'week', '--period', '2026-W45'], { now: () => at('2026-11-09T05:05:00+08:00'), runners: weekRunners });
  assert.deepEqual(weekRows, [{ stage: 'week', period: '2026-W45', ok: true, generator: 'codex', source_days: 2, retries: 0 }]);
  assert.match(weekPrompts[0], /\[day:2026-11-02\]/);
  assert.match(weekPrompts[0], /\[day:2026-11-04\]/);
  assert.doesNotMatch(weekPrompts[0], /\[day:2026-11-05\]/);
  const savedWeek = st.week('2026-W45');
  assert.equal(savedWeek.format, 'life-digest-week-v1');
  assert.deepEqual(savedWeek.date_range, ['2026-11-02', '2026-11-08']);
  assert.deepEqual(savedWeek.source_days, ['2026-11-02', '2026-11-04']);
  assert.deepEqual(savedWeek.highlights[0].sources, ['day:2026-11-02', 'day:2026-11-04']);
  assert.deepEqual(st.listWeeks(), ['2026-W45']);

  // Auto mode on 2026-12-01 05:35: yesterday final (empty -> generator:'none') + month 2026-11 (has W45 + 11-30!)
  const monthPrompts = [];
  const autoRunners = { codex: async (_c, p) => {
    monthPrompts.push(p);
    return JSON.stringify({
      headline: '稳步推进与收尾的十一月',
      themes: [{ text: '设计落地与测试完善', sources: ['week:2026-W45'] }],
      us: [{ text: '稳定陪伴', sources: ['week:2026-W45'] }],
      shifts: [{ text: '月底转向梳理清单', sources: ['day:2026-11-30'] }],
      milestones: [{ text: '跑通核心测试', sources: ['week:2026-W45'] }],
      omitted: [],
    });
  } };
  const autoRows = await main(['--config', configPath], { now: () => at('2026-12-01T05:35:00+08:00'), runners: autoRunners });
  // 2026-11-30 already has final, 2026-W48 has no days, so only month 2026-11 runs!
  assert.deepEqual(autoRows, [{ stage: 'month', period: '2026-11', ok: true, generator: 'codex', source_weeks: 1, source_days: 1, retries: 0 }]);
  assert.match(monthPrompts[0], /\[week:2026-W45\]/);
  assert.match(monthPrompts[0], /\[day:2026-11-30\]/);
  const savedMonth = st.month('2026-11');
  assert.equal(savedMonth.format, 'life-digest-month-v1');
  assert.deepEqual(savedMonth.source_weeks, ['2026-W45']);
  assert.deepEqual(savedMonth.source_days, ['2026-11-30']);
  assert.deepEqual(st.listMonths(), ['2026-11']);

  // Running auto again finds nothing due
  const again = await main(['--config', configPath], { now: () => at('2026-12-01T05:40:00+08:00'), runners: autoRunners });
  assert.deepEqual(again, [{ stage: 'none', ok: true, detail: 'nothing_due' }]);

  // Invalid CLI combinations fail closed
  await assert.rejects(main(['--config', configPath, '--stage', 'week', '--period', '2025-W53']), /usage/);
  await assert.rejects(main(['--config', configPath, '--stage', 'week', '--date', '2026-11-08']), /usage/);
  await assert.rejects(main(['--config', configPath, '--stage', 'month', '--period', '2026-13']), /usage/);
});
