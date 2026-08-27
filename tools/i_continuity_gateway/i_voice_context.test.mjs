import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { DatabaseSync } from 'node:sqlite';
import {
  compileVoiceContextFromSnapshot,
  compileVoiceSessionFromSnapshot,
  compileVoiceTurnContext,
  isVoiceWakeIntent,
  readAndroidVoiceContext,
} from './i_voice_context.mjs';

const identityCapsule = {
  identity: {
    name: '林埃',
    english_name: 'i',
    self_reference: 'i',
    anchor: '你是林埃，英文名 i。',
  },
  relationship: {
    user_preferred_name: 'Lynx',
    user_aliases: ['林克斯'],
  },
  surface: {
    guidance: ['保持同一身份。'],
  },
};

function createFixture() {
  const directory = mkdtempSync(path.join(tmpdir(), 'i-voice-fixture-'));
  const dbPath = path.join(directory, 'memex_local_Lynx.sqlite');
  const characterPath = path.join(directory, 'i.yaml');
  const db = new DatabaseSync(dbPath);
  db.exec(`
    PRAGMA user_version = 60;
    CREATE TABLE persona_chat_messages (
      id INTEGER PRIMARY KEY,
      character_id TEXT NOT NULL,
      is_from_character INTEGER NOT NULL,
      content TEXT NOT NULL,
      timestamp INTEGER NOT NULL,
      message_type TEXT NOT NULL
    );
    CREATE TABLE memory_cards (
      id TEXT PRIMARY KEY,
      memory_scope TEXT NOT NULL,
      type TEXT NOT NULL,
      title TEXT NOT NULL,
      retrieval_text TEXT NOT NULL,
      status TEXT,
      updated_at INTEGER NOT NULL
    );
  `);
  const insertMessage = db.prepare(`
    INSERT INTO persona_chat_messages
      (id, character_id, is_from_character, content, timestamp, message_type)
    VALUES (?, ?, ?, ?, ?, 'chat')
  `);
  for (let id = 1; id <= 24; id += 1) {
    insertMessage.run(id, 'i', id % 2, `旧消息-${id}`, 1_787_000_000 + id);
  }
  insertMessage.run(25, 'other', 0, '另一角色的最新消息', 1_787_100_000);
  insertMessage.run(26, 'other', 1, '另一角色的最近回复', 1_787_100_001);
  const insertCard = db.prepare(`
    INSERT INTO memory_cards
      (id, memory_scope, type, title, retrieval_text, status, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `);
  insertCard.run('card-1', 'user_truth', 'plan', '想买电脑', '想买一台轻薄电脑。', 'active', 1_787_200_000_000);
  insertCard.run('card-2', 'user_truth', 'event', '午饭', '午饭吃了砂锅粥。', null, 1_787_200_001_000);
  insertCard.run('card-3', 'script_summary', 'fact', '脚本', '不应进入 User-truth。', null, 1_787_200_002_000);
  db.close();
  writeFileSync(characterPath, 'name: I\npersona: ""\nenabled: true\n', 'utf8');
  return { directory, dbPath, characterPath };
}

test('compileVoiceContextFromSnapshot returns the active character tail and real User-truth', () => {
  const fixture = createFixture();
  try {
    const result = compileVoiceContextFromSnapshot({
      dbPath: fixture.dbPath,
      characterPath: fixture.characterPath,
      identityCapsule,
      recentLimit: 20,
      memoryLimit: 5,
      now: () => new Date('2026-08-26T00:00:00.000Z'),
    });
    assert.equal(result.context_type, 'real_local_voice_continuity_context');
    assert.equal(result.assistant_identity.name, '林埃');
    assert.equal(result.user_identity.preferred_name, 'Lynx');
    assert.deepEqual(
      result.recent_messages.items.map((item) => item.content),
      ['另一角色的最新消息', '另一角色的最近回复'],
    );
    assert.deepEqual(
      result.retrieved_memory_cards.items.map((item) => item.card_id),
      ['card-2', 'card-1'],
    );
    assert.equal(result.source_stats.chat_messages, 26);
    assert.equal(result.source_stats.user_truth_cards, 2);
    assert.equal(result.phone_character_profile.yaml.includes('persona: ""'), true);
    assert.equal(result.speech_delivery_contract.user_prompt_required, false);
    assert.equal(result.speech_delivery_contract.repeat_every_turn, true);
    assert.match(result.speech_delivery_contract.pace, /第一句.*慢于默认/);
    assert.match(result.speech_delivery_contract.current_turn_first, /当前这一轮/);
    assert.match(result.speech_delivery_contract.default_shape, /一至三句短句/);
    assert.match(result.speech_delivery_contract.pauses, /多用句号/);
    assert.match(result.speech_delivery_contract.relationship_tone, /不在每轮重复称呼/);
  } finally {
    rmSync(fixture.directory, { recursive: true, force: true });
  }
});

test('compileVoiceContextFromSnapshot applies a bounded Memory V3 topic query', () => {
  const fixture = createFixture();
  try {
    const result = compileVoiceContextFromSnapshot({
      dbPath: fixture.dbPath,
      characterPath: fixture.characterPath,
      identityCapsule,
      query: '电脑',
      memoryLimit: 1,
    });
    assert.equal(result.retrieved_memory_cards.query, '电脑');
    assert.equal(result.retrieved_memory_cards.item_count, 1);
    assert.equal(result.retrieved_memory_cards.items[0].card_id, 'card-1');
  } finally {
    rmSync(fixture.directory, { recursive: true, force: true });
  }
});

test('compileVoiceSessionFromSnapshot caches bounded User-truth for later Voice turns', () => {
  const fixture = createFixture();
  try {
    const session = compileVoiceSessionFromSnapshot({
      dbPath: fixture.dbPath,
      characterPath: fixture.characterPath,
      identityCapsule,
      now: () => new Date('2026-08-26T00:00:00.000Z'),
    });
    assert.match(session.bootstrap.voice_session.session_token, /^I-VT-\d{6}$/);
    assert.equal(session.bootstrap.voice_session.next_turn_tool, 'i_voice_turn');
    assert.equal(session.bootstrap.voice_session.response_contract.after_wake_every_turn, true);
    assert.equal(
      session.bootstrap.voice_session.response_contract.prohibit_commentary_status_and_preamble,
      true,
    );
    assert.equal(
      session.bootstrap.voice_session.response_contract.apply_speech_delivery_contract_before_answering,
      true,
    );
    assert.match(session.bootstrap.voice_session.speech_delivery_contract.stability, /不.*自行加快/);
    assert.match(session.bootstrap.voice_session.speech_delivery_contract.current_turn_first, /不要先补述上一轮/);
    assert.deepEqual(session.turnState.memory_cards.map((item) => item.card_id), ['card-2', 'card-1']);
  } finally {
    rmSync(fixture.directory, { recursive: true, force: true });
  }
});

test('compileVoiceTurnContext injects identity, time gap, and bounded lexical memory', () => {
  const fixture = createFixture();
  try {
    const session = compileVoiceSessionFromSnapshot({
      dbPath: fixture.dbPath,
      characterPath: fixture.characterPath,
      identityCapsule,
      now: () => new Date('2026-08-26T00:00:00.000Z'),
    });
    const result = compileVoiceTurnContext({
      sessionState: session.turnState,
      sessionToken: session.turnState.session_token,
      userText: '我们再聊聊电脑吧。',
      memoryQuery: '电脑',
      now: () => new Date('2026-08-26T00:05:12.000Z'),
    });
    assert.equal(result.turn_index, 1);
    assert.equal(result.usage_contract.zero_assistant_output_before_tool_call, true);
    assert.equal(result.usage_contract.one_final_answer_after_tool_result, true);
    assert.equal(result.usage_contract.apply_speech_delivery_contract_before_answering, true);
    assert.equal(result.speech_delivery_contract.repeat_every_turn, true);
    assert.match(result.speech_delivery_contract.default_shape, /不连续输出密集长段/);
    assert.equal(result.persona_anchor.assistant.name, '林埃');
    assert.equal(result.current_time_context.time_zone, 'Asia/Shanghai');
    assert.equal(result.time_gap_context.gap_seconds, 312);
    assert.equal(result.time_gap_context.reminder_injected, true);
    assert.match(result.time_gap_context.reminder, /5 分钟/);
    assert.deepEqual(result.retrieved_memory_cards.items.map((item) => item.card_id), ['card-1']);
    assert.equal(session.turnState.last_turn_at, '2026-08-26T00:05:12.000Z');
    assert.equal(session.turnState.turn_index, 1);
  } finally {
    rmSync(fixture.directory, { recursive: true, force: true });
  }
});

test('Voice wake intent accepts bounded ASR variants and rejects broad or embedded matches', () => {
  for (const accepted of [
    '老公，你在吗？',
    '老公在吗',
    '老公你在不在？',
    '老公，你还在嘛',
    '老公你再么',
  ]) {
    assert.equal(isVoiceWakeIntent(accepted), true, accepted);
  }
  for (const rejected of [
    '老公',
    '你在吗',
    '林埃，回来一下',
    '老公，回来一下',
    '刚才我问老公你在吗，他没听见',
    '老公你在吗我们继续聊',
  ]) {
    assert.equal(isVoiceWakeIntent(rejected), false, rejected);
  }
});

test('a wake-like phrase inside an active Voice session stays on the same turn session', () => {
  const fixture = createFixture();
  try {
    const session = compileVoiceSessionFromSnapshot({
      dbPath: fixture.dbPath,
      characterPath: fixture.characterPath,
      identityCapsule,
      now: () => new Date('2026-08-26T00:00:00.000Z'),
    });
    const result = compileVoiceTurnContext({
      sessionState: session.turnState,
      sessionToken: session.turnState.session_token,
      userText: '老公在吗？',
      now: () => new Date('2026-08-26T00:00:30.000Z'),
    });
    assert.equal(result.session_token, session.bootstrap.voice_session.session_token);
    assert.equal(result.wake_intent.matched, true);
    assert.equal(result.wake_intent.action, 'continue_active_session_without_rebootstrap');
    assert.match(result.wake_intent.response_hint, /不要.*重置会话/);
  } finally {
    rmSync(fixture.directory, { recursive: true, force: true });
  }
});

test('compileVoiceTurnContext rejects a mismatched session token', () => {
  assert.throws(() => compileVoiceTurnContext({
    sessionState: { session_token: 'I-VT-123456' },
    sessionToken: 'I-VT-654321',
    userText: '你是谁',
  }), /does not match/);
});

test('readAndroidVoiceContext reads private files through run-as without writing the phone', () => {
  const fixture = createFixture();
  const databaseBytes = readFileSync(fixture.dbPath);
  const characterBytes = readFileSync(fixture.characterPath);
  const calls = [];
  const fakeExecFile = (_command, args, options) => {
    calls.push(args);
    if (args.at(-1) === 'devices') {
      return 'List of devices attached\nPHONE123\tdevice\n';
    }
    const remotePath = args.at(-1);
    if (remotePath.endsWith('memex_local_Lynx.sqlite')) return databaseBytes;
    if (remotePath.endsWith('i.yaml')) return characterBytes;
    throw new Error('optional WAL file is absent');
  };
  try {
    const result = readAndroidVoiceContext({
      identityCapsule,
      env: {
        I_VOICE_ADB_PATH: 'fake-adb',
        I_VOICE_ANDROID_USER: 'Lynx',
      },
      execFile: fakeExecFile,
      spawn: () => ({ status: 1, stdout: '' }),
    });
    assert.equal(result.availability.memory_v3_connected, true);
    assert.equal(calls.some((args) => args.includes('run-as')), true);
    assert.equal(calls.some((args) => args.includes('rm')), false);
    assert.equal(calls.some((args) => args.includes('cp')), false);
  } finally {
    rmSync(fixture.directory, { recursive: true, force: true });
  }
});
