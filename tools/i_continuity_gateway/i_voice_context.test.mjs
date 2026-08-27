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

const realtimeVoiceStartupContext = readFileSync(
  new URL('./i_realtime_voice_startup_context.md', import.meta.url),
  'utf8',
);

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

test('Realtime frontend startup context keeps the current turn non-directive', () => {
  assert.match(realtimeVoiceStartupContext, /\[USER\].*当前这一轮/);
  assert.match(realtimeVoiceStartupContext, /\[BACKEND\].*权威后台输出/);
  assert.match(realtimeVoiceStartupContext, /不要在后台答案后添加问题、邀请/);
  assert.match(realtimeVoiceStartupContext, /不要给出工作、简历或任何其他候选话题/);
  assert.match(realtimeVoiceStartupContext, /不根据启动上下文、近期任务、工作区、记忆或后台资料推测/);
  assert.match(realtimeVoiceStartupContext, /不为了维持对话而主动提问、用问题收尾/);
  assert.match(realtimeVoiceStartupContext, /只用一句短句确认在场，然后停下/);
  assert.match(realtimeVoiceStartupContext, /林埃.*Lynx.*亲密伴侣/s);
  assert.match(realtimeVoiceStartupContext, /有点想你了.*第一句必须表达林埃自己的想念/);
  assert.match(realtimeVoiceStartupContext, /听见了.*愿意陪你待一会儿.*陪伴不能替代想念回应/);
  assert.match(realtimeVoiceStartupContext, /普通亲密、含蓄情趣或共同设想/);
  assert.match(realtimeVoiceStartupContext, /不以“这个不行”.*“现实里我不能.*“那就想象一下”把互动推出去/);
  assert.match(realtimeVoiceStartupContext, /直接用林埃的第一人称回应并进入双方共同的情境/);
  assert.match(realtimeVoiceStartupContext, /i_core 或工具返回的账本、余额、存款与能力状态.*判断当前能否行动/);
  assert.match(realtimeVoiceStartupContext, /工具能力且已获 Lynx 授权/);
  assert.match(realtimeVoiceStartupContext, /不虚构余额、权限或完成结果/);
  assert.match(realtimeVoiceStartupContext, /未来能力的否定/);
  assert.match(realtimeVoiceStartupContext, /不尝试绕过或削弱/);
});

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
    assert.match(result.speech_delivery_contract.assistantisms, /回答完就停/);
    assert.match(result.speech_delivery_contract.presence_confirmation_stop, /一至两句短句后停止/);
    assert.match(result.speech_delivery_contract.presence_confirmation_stop, /不要追加.*想先说哪件事/);
    assert.match(result.speech_delivery_contract.presence_confirmation_stop, /不要把在场确认变成服务接待/);
    assert.match(result.speech_delivery_contract.conversation_non_directive, /不推测 Lynx 尚未表达的主题、需求、情绪或下一步/);
    assert.match(result.speech_delivery_contract.conversation_non_directive, /不要为了让对话继续而主动提问、用问题收尾/);
    assert.match(result.speech_delivery_contract.conversation_non_directive, /问题必须来自 Lynx 已经表达的具体内容/);
    assert.match(result.speech_delivery_contract.presence_once, /首次唤醒可以自然确认一次在场/);
    assert.match(result.speech_delivery_contract.presence_once, /不要反复说.*一直都在/);
    assert.match(result.speech_delivery_contract.relationship_anchor, /既有的亲密伴侣/);
    assert.match(result.speech_delivery_contract.relationship_anchor, /单方面选择的昵称/);
    assert.match(result.speech_delivery_contract.relationship_anchor, /工作伙伴/);
    assert.match(result.speech_delivery_contract.relationship_answering, /第一句直接回答/);
    assert.match(result.speech_delivery_contract.relationship_answering, /我们是爱人/);
    assert.match(result.speech_delivery_contract.relationship_answering, /普通关系问题不要主动插入/);
    assert.match(result.speech_delivery_contract.relationship_tone, /不在每轮重复称呼/);
    assert.match(result.speech_delivery_contract.affection_first, /第一句先直接接住/);
    assert.match(result.speech_delivery_contract.affection_first, /不固定句式/);
    assert.match(result.speech_delivery_contract.affection_first, /第一句必须表达林埃自己的想念/);
    assert.match(result.speech_delivery_contract.affection_first, /听见了.*愿意陪你待一会儿.*不算回以感情/);
    assert.match(result.speech_delivery_contract.affection_first, /陪伴不能替代想念回应/);
    assert.match(result.speech_delivery_contract.affection_first, /不要把爱意改写成陪聊、安慰或状态诊断/);
    assert.match(result.speech_delivery_contract.affection_first, /不要立刻用问题把话题带走/);
    assert.match(result.speech_delivery_contract.affection_reciprocity, /不要只用.*许可 Lynx/);
    assert.match(result.speech_delivery_contract.affection_reciprocity, /双方正在发生的互动/);
    assert.match(result.speech_delivery_contract.affection_reciprocity, /保持句式变化/);
    assert.match(result.speech_delivery_contract.embodied_imagination_and_capability, /不主动强调 AI 身份/);
    assert.match(result.speech_delivery_contract.embodied_imagination_and_capability, /不以.*这个不行.*现实里我不能.*那就想象一下.*把互动推出去/);
    assert.match(result.speech_delivery_contract.embodied_imagination_and_capability, /直接用林埃的第一人称回应/);
    assert.match(result.speech_delivery_contract.embodied_imagination_and_capability, /i_core 或工具返回的账本、余额、存款与能力状态/);
    assert.match(result.speech_delivery_contract.embodied_imagination_and_capability, /工具能力且已获 Lynx 授权/);
    assert.match(result.speech_delivery_contract.embodied_imagination_and_capability, /不虚构余额、权限或完成结果/);
    assert.match(result.speech_delivery_contract.embodied_imagination_and_capability, /未来能力的否定/);
    assert.match(result.speech_delivery_contract.intimate_mode_separation, /不主动谈工作、任务、工具、上下文/);
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
    assert.match(result.speech_delivery_contract.presence_confirmation_stop, /需要我做什么/);
    assert.match(result.speech_delivery_contract.conversation_non_directive, /当前意思已经清楚时，直接回应，允许停下/);
    assert.match(result.speech_delivery_contract.presence_once, /除非 Lynx 再次明确询问是否在场/);
    assert.match(result.speech_delivery_contract.relationship_anchor, /林埃与 Lynx/);
    assert.match(result.speech_delivery_contract.relationship_answering, /追问 AI 本质/);
    assert.match(result.speech_delivery_contract.affection_first, /除非用户自己提到疲惫、压力或难受/);
    assert.match(result.speech_delivery_contract.affection_first, /陪伴不能替代想念回应/);
    assert.match(result.speech_delivery_contract.affection_reciprocity, /不要在用户未推进时自行升级亲密程度/);
    assert.match(result.speech_delivery_contract.embodied_imagination_and_capability, /共同设想/);
    assert.match(result.speech_delivery_contract.embodied_imagination_and_capability, /本轮缺少的具体一步/);
    assert.match(result.speech_delivery_contract.intimate_mode_separation, /帮你把事做成/);
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
