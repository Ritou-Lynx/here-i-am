import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { afterEach, beforeEach, describe, test } from 'node:test';

import { runImport } from './import_v3_memory.mjs';
import { hashMemoryCard, hashMessageContent, loadPolicy, openReadModel } from './i_memory_read.mjs';

// All fixture data below is synthetic.
const LIN = 'char-lin-synthetic';
const OTHER = 'char-other-synthetic';

const BASE_CARDS = [
  { id: 'card-coffee', type: 'fact', title: '喜欢手冲咖啡', droplet_label: '咖啡', retrieval_text: '用户每天早上喝一杯手冲咖啡，偏好浅烘焙。', status: null },
  { id: 'card-run', type: 'event', title: '周末晨跑十公里', droplet_label: '晨跑', retrieval_text: '周六早上在河边跑了十公里，配速稳定。', status: null, structured: ['sport_record', { distanceKm: 10 }] },
  { id: 'card-health', type: 'fact', title: '体检复查', droplet_label: '体检', retrieval_text: '医院复查安排在下月。', status: null },
  { id: 'card-expense', type: 'event', title: '买了新耳机', droplet_label: '耳机', retrieval_text: '花了八百元买降噪耳机。', status: null, structured: ['expense_entry', { amount: 800 }] },
  { id: 'card-secret-id', type: 'fact', title: '书店会员', droplet_label: '书店', retrieval_text: '在街角书店办了会员卡。', status: null },
  { id: 'card-keyword', type: 'fact', title: '旅行计划', droplet_label: '旅行', retrieval_text: '想去海边旅行，这是秘密行程。', status: null },
  { id: 'card-task', type: 'task', title: '整理书架', droplet_label: '书架', retrieval_text: '周末整理书架上的旧书。', status: 'active' },
  { id: 'card-label-kw', type: 'fact', title: '散步路线', droplet_label: '秘密', retrieval_text: '晚饭后沿公园散步。', status: null },
];

function createV3(file, cards, { dropColumn } = {}) {
  const db = new DatabaseSync(file);
  const cardColumns = [
    'id TEXT PRIMARY KEY', "memory_scope TEXT NOT NULL DEFAULT 'user_truth'", 'type TEXT NOT NULL',
    'title TEXT NOT NULL', 'droplet_label TEXT NOT NULL', "presentation_module TEXT NOT NULL DEFAULT '[]'",
    'retrieval_text TEXT NOT NULL', 'valence REAL NOT NULL DEFAULT 0', 'arousal REAL NOT NULL DEFAULT 0',
    'status TEXT', 'needs_follow_up TEXT', 'schema_version INTEGER NOT NULL DEFAULT 1',
    'created_at INTEGER NOT NULL', 'updated_at INTEGER NOT NULL',
  ].filter((column) => column.split(' ')[0] !== dropColumn);
  db.exec(`
    CREATE TABLE memory_cards (${cardColumns.join(', ')});
    CREATE TABLE memory_card_sources (
      card_id TEXT PRIMARY KEY, raw_input TEXT NOT NULL, recorded_at INTEGER NOT NULL,
      recorded_place TEXT, source_ref TEXT, source_sync_id TEXT, source_kind TEXT NOT NULL,
      schema_version INTEGER NOT NULL DEFAULT 1
    );
    CREATE TABLE memory_card_structured_fields (
      card_id TEXT PRIMARY KEY, structured_fields_type TEXT NOT NULL, fields_json TEXT NOT NULL,
      user_corrected INTEGER NOT NULL DEFAULT 0, schema_version INTEGER NOT NULL DEFAULT 1,
      generated_by_version TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
    );
  `);
  const columns = ['id', 'type', 'title', 'droplet_label', 'retrieval_text', 'status', 'created_at', 'updated_at']
    .filter((column) => column !== dropColumn);
  const insert = db.prepare(`INSERT INTO memory_cards (${columns.join(', ')}) VALUES (${columns.map(() => '?').join(', ')})`);
  cards.forEach((card, index) => {
    const at = 1_790_000_000_000 + index * 60_000;
    const values = { ...card, created_at: at, updated_at: at + 1000 };
    insert.run(...columns.map((column) => values[column] ?? null));
    db.prepare(`INSERT INTO memory_card_sources (card_id, raw_input, recorded_at, source_kind) VALUES (?, ?, ?, 'record_button')`)
      .run(card.id, `原始输入 ${card.id}`, at - 5000);
    if (card.structured) {
      db.prepare(`INSERT INTO memory_card_structured_fields (card_id, structured_fields_type, fields_json, created_at, updated_at) VALUES (?, ?, ?, ?, ?)`)
        .run(card.id, card.structured[0], JSON.stringify(card.structured[1]), at, at);
    }
  });
  db.close();
}

const MESSAGES = [
  [LIN, 'user', '今天早上喝了手冲咖啡', 'chat'],
  [LIN, 'companion', '浅烘焙的咖啡香气很好', 'chat'],
  [OTHER, 'user', '别的角色的咖啡私聊', 'chat'],
  [LIN, 'user', '日记：私密类型的咖啡记录', 'diary'],
  [LIN, 'user', '周末去跑步了', 'chat'],
  [OTHER, 'companion', '只属于另一角色的回答', 'chat'],
  [LIN, 'companion', '跑步记得补水，咖啡少喝点', 'chat'],
];

function createCore(file) {
  const db = new DatabaseSync(file);
  db.exec(`
    CREATE TABLE chat_messages (
      sync_id TEXT PRIMARY KEY, origin_device_id TEXT NOT NULL, origin_sequence INTEGER NOT NULL,
      character_id TEXT NOT NULL, sender TEXT NOT NULL, content TEXT NOT NULL,
      created_at_ms INTEGER NOT NULL, message_type TEXT NOT NULL, asset_refs_json TEXT NOT NULL,
      addenda_json TEXT NOT NULL, canonical_digest TEXT NOT NULL, server_sequence INTEGER NOT NULL UNIQUE
    );
  `);
  const insert = db.prepare(`INSERT INTO chat_messages VALUES (?, 'dev-synthetic', ?, ?, ?, ?, ?, ?, '[]', '[]', 'digest', ?)`);
  MESSAGES.forEach(([character, sender, content, type], index) => {
    insert.run(`msg-${index}`, index, character, sender, content, 1_790_000_000_000 + index * 1000, type, index + 1);
  });
  db.close();
}

function policy(overrides = {}) {
  return {
    schema_version: 1,
    primary_character_id: LIN,
    messages: { default: 'private', shareable_character_ids: [LIN], private_message_types: ['diary'] },
    memory: {
      default: 'shareable',
      private_types: ['task'],
      private_structured_types: ['expense_entry'],
      private_card_ids: ['card-secret-id'],
      private_keywords: ['秘密', '医院'],
    },
    ...overrides,
  };
}

const PRIVATE_CARD_IDS = ['card-health', 'card-expense', 'card-secret-id', 'card-keyword', 'card-task', 'card-label-kw'];
const PRIVATE_TEXT = ['体检', '耳机', '书店', '旅行', '书架', '散步', '秘密', '医院'];

let dir;
let v3;
let core;
let out;
let policyPath;

beforeEach(() => {
  dir = mkdtempSync(path.join(tmpdir(), 'i-memory-test-'));
  v3 = path.join(dir, 'v3.sqlite');
  core = path.join(dir, 'core.sqlite');
  out = path.join(dir, 'state', 'i-memory.sqlite');
  policyPath = path.join(dir, 'policy.json');
  createV3(v3, BASE_CARDS);
  createCore(core);
  writeFileSync(policyPath, JSON.stringify(policy()));
});

afterEach(() => rmSync(dir, { recursive: true, force: true }));

function openModel(extra = {}) {
  return openReadModel({ coreDbPath: core, memoryDbPath: out, policyPath, ...extra });
}

function readOut(sql) {
  const db = new DatabaseSync(out, { readOnly: true });
  try {
    return db.prepare(sql).all();
  } finally {
    db.close();
  }
}

describe('import_v3_memory', () => {
  test('dry-run reports counts without writing', () => {
    const result = runImport({ source: v3, out });
    assert.equal(result.mode, 'dry-run');
    assert.equal(result.cards, BASE_CARDS.length);
    assert.equal(result.with_structured, 2);
    assert.equal(result.would_add, BASE_CARDS.length);
    assert.match(result.source_sha256, /^[0-9a-f]{64}$/);
    assert.throws(() => readOut('SELECT 1'));
  });

  test('apply writes cards, FTS and metadata', () => {
    const result = runImport({ source: v3, out, apply: true, now: () => 1_795_000_000_000 });
    assert.equal(result.imported, BASE_CARDS.length);
    assert.equal(readOut('SELECT COUNT(*) AS n FROM memory_cards')[0].n, BASE_CARDS.length);
    assert.equal(readOut('SELECT COUNT(*) AS n FROM memory_cards_fts')[0].n, BASE_CARDS.length);
    const meta = Object.fromEntries(readOut('SELECT key, value FROM memory_metadata').map((r) => [r.key, r.value]));
    assert.equal(meta.snapshot_at_ms, '1795000000000');
    assert.equal(meta.card_count, String(BASE_CARDS.length));
    assert.equal(meta.source_sha256, result.source_sha256);
    const run = readOut("SELECT * FROM memory_cards WHERE id = 'card-run'")[0];
    assert.equal(run.structured_type, 'sport_record');
    assert.equal(run.recorded_at, 1_790_000_000_000 + 60_000 - 5000);
  });

  test('re-import is idempotent', () => {
    runImport({ source: v3, out, apply: true, now: () => 1 });
    const first = readOut('SELECT * FROM memory_cards ORDER BY id');
    const second = runImport({ source: v3, out, apply: true, now: () => 1 });
    assert.equal(second.would_add, 0);
    assert.equal(second.would_remove, 0);
    assert.deepEqual(readOut('SELECT * FROM memory_cards ORDER BY id'), first);
    assert.equal(readOut('SELECT COUNT(*) AS n FROM memory_cards_fts')[0].n, BASE_CARDS.length);
  });

  test('snapshot replace propagates deletes and edits', () => {
    runImport({ source: v3, out, apply: true });
    rmSync(v3);
    const edited = BASE_CARDS.filter((card) => card.id !== 'card-coffee')
      .map((card) => (card.id === 'card-run' ? { ...card, title: '周末晨跑二十公里' } : card));
    createV3(v3, edited);
    const result = runImport({ source: v3, out, apply: true });
    assert.equal(result.would_remove, 1);
    assert.equal(readOut("SELECT COUNT(*) AS n FROM memory_cards WHERE id = 'card-coffee'")[0].n, 0);
    assert.equal(readOut("SELECT COUNT(*) AS n FROM memory_cards_fts WHERE card_id = 'card-coffee'")[0].n, 0);
    assert.equal(readOut("SELECT title FROM memory_cards WHERE id = 'card-run'")[0].title, '周末晨跑二十公里');
    const model = openModel();
    try {
      assert.deepEqual(model.searchMemory({ query: '手冲咖啡' }), []);
      assert.deepEqual(model.getMemoryCards({ ids: ['card-coffee'] }), []);
      assert.equal(model.searchMemory({ query: '二十公里' })[0].id, 'card-run');
    } finally {
      model.close();
    }
  });

  test('missing source column fails with a clear error', () => {
    rmSync(v3);
    createV3(v3, BASE_CARDS, { dropColumn: 'retrieval_text' });
    assert.throws(() => runImport({ source: v3, out }), /memory_cards is missing: retrieval_text/);
  });

  test('missing source table fails', () => {
    const db = new DatabaseSync(v3);
    db.exec('DROP TABLE memory_card_structured_fields');
    db.close();
    assert.throws(() => runImport({ source: v3, out }), /table memory_card_structured_fields is missing/);
  });

  test('rejects same source and output path', () => {
    assert.throws(() => runImport({ source: v3, out: v3, apply: true }), /must be different/);
  });
});

describe('policy', () => {
  test('missing policy fails closed', () => {
    rmSync(policyPath);
    assert.throws(() => openModel(), /policy file is missing/);
  });

  test('malformed policy fails closed', () => {
    writeFileSync(policyPath, '{ not json');
    assert.throws(() => openModel(), /policy invalid/);
    for (const bad of [
      { ...policy(), schema_version: 2 },
      { ...policy(), primary_character_id: '' },
      { ...policy(), messages: { ...policy().messages, shareable_character_ids: 'x' } },
      { ...policy(), memory: { ...policy().memory, private_keywords: undefined } },
      { ...policy(), memory: { ...policy().memory, default: 'public' } },
    ]) {
      writeFileSync(policyPath, JSON.stringify(bad));
      assert.throws(() => loadPolicy(policyPath), /policy invalid/);
    }
  });
});

describe('read model', () => {
  beforeEach(() => runImport({ source: v3, out, apply: true, now: () => 1_795_000_000_000 }));

  function everything(model) {
    const ids = BASE_CARDS.map((card) => card.id);
    return JSON.stringify([
      model.recentMessages({ limit: 100 }),
      model.recentMessages({ characterId: OTHER }),
      model.searchMessages({ query: '咖啡', limit: 50 }),
      model.searchMessages({ query: '角色', characterId: OTHER }),
      ...PRIVATE_TEXT.map((query) => model.searchMemory({ query, limit: 50 })),
      ...['体检复查', '降噪耳机', '书店会员', '海边旅行', '整理书架', '公园散步', '复查安排'].map((query) => model.searchMemory({ query, limit: 50 })),
      model.getMemoryCards({ ids }),
      model.policySummary(),
      model.stats(),
    ]);
  }

  test('private content never appears in any method', () => {
    const model = openModel();
    try {
      const dump = everything(model);
      for (const id of PRIVATE_CARD_IDS) assert.ok(!dump.includes(id), `leaked card id ${id}`);
      for (const text of PRIVATE_TEXT) assert.ok(!dump.includes(text), `leaked text ${text}`);
      for (const leak of ['别的角色', '另一角色', '日记', 'msg-2', 'msg-3', 'msg-5', OTHER, 'diary']) {
        assert.ok(!dump.includes(leak), `leaked message ${leak}`);
      }
    } finally {
      model.close();
    }
  });

  test('each memory privacy rule filters its card', () => {
    const model = openModel();
    try {
      const visible = model.getMemoryCards({ ids: BASE_CARDS.map((card) => card.id) }).map((card) => card.id);
      assert.deepEqual(visible.sort(), ['card-coffee', 'card-run']);
      assert.deepEqual(model.getMemoryCards({ ids: ['card-task'] }), []); // private_types
      assert.deepEqual(model.getMemoryCards({ ids: ['card-expense'] }), []); // private_structured_types
      assert.deepEqual(model.getMemoryCards({ ids: ['card-secret-id'] }), []); // private_card_ids
      assert.deepEqual(model.getMemoryCards({ ids: ['card-keyword'] }), []); // keyword in retrieval_text
      assert.deepEqual(model.getMemoryCards({ ids: ['card-health'] }), []); // keyword in retrieval_text (医院)
      assert.deepEqual(model.getMemoryCards({ ids: ['missing'] }), []);
    } finally {
      model.close();
    }
  });

  test('memory default private hides every card', () => {
    writeFileSync(policyPath, JSON.stringify(policy({ memory: { ...policy().memory, default: 'private' } })));
    const model = openModel();
    try {
      assert.deepEqual(model.searchMemory({ query: '手冲咖啡' }), []);
      assert.deepEqual(model.stats().memory, { shareable: 0, private: BASE_CARDS.length });
    } finally {
      model.close();
    }
  });

  test('messages: only shareable characters and non-private types', () => {
    const model = openModel();
    try {
      const recent = model.recentMessages();
      assert.deepEqual(recent.map((m) => m.syncId), ['msg-0', 'msg-1', 'msg-4', 'msg-6']);
      assert.deepEqual(recent[0], {
        syncId: 'msg-0', characterId: LIN, sender: 'user', content: '今天早上喝了手冲咖啡',
        createdAtMs: 1_790_000_000_000, messageType: 'chat', originDeviceId: 'dev-synthetic',
      });
      assert.deepEqual(model.recentMessages({ characterId: OTHER }), []);
      assert.deepEqual(model.searchMessages({ query: '角色', characterId: OTHER }), []);
      assert.deepEqual(model.recentMessages({ limit: 2 }).map((m) => m.syncId), ['msg-4', 'msg-6']);
      assert.equal(model.recentMessages({ limit: 1000 }).length, 4);
    } finally {
      model.close();
    }
  });

  test('messages: private_keywords hide matching messages everywhere', () => {
    writeFileSync(policyPath, JSON.stringify(policy({
      messages: {
        default: 'private', shareable_character_ids: [LIN], private_message_types: ['diary'],
        private_keywords: ['手冲'],
      },
    })));
    const model = openModel();
    try {
      assert.deepEqual(model.recentMessages().map((m) => m.syncId), ['msg-1', 'msg-4', 'msg-6']);
      const hits = model.searchMessages({ query: '咖啡' });
      assert.ok(hits.length > 0);
      assert.ok(hits.every((m) => !m.content.includes('手冲')));
      assert.deepEqual(model.stats().messages, { shareable: 3, private: 4 });
    } finally {
      model.close();
    }
  });

  test('messages.private_keywords must be valid when present', () => {
    writeFileSync(policyPath, JSON.stringify(policy({
      messages: { default: 'private', shareable_character_ids: [LIN], private_message_types: [], private_keywords: [''] },
    })));
    assert.throws(() => openModel(), /messages\.private_keywords/);
  });

  test('optional ID lists preserve omitted defaults and reject malformed values', () => {
    const legacy = loadPolicy(policyPath);
    assert.deepEqual(legacy.messages.privateMessageIds, []);
    assert.equal(legacy.messages.shareableMessageIds, null);
    assert.equal(legacy.memory.shareableCardIds, null);
    for (const [section, field] of [
      ['messages', 'private_message_ids'], ['messages', 'shareable_message_ids'],
      ['memory', 'shareable_card_ids'],
    ]) {
      for (const invalid of [null, 'id', {}, [''], ['  '], [1], ['id', null]]) {
        const configured = policy();
        configured[section][field] = invalid;
        writeFileSync(policyPath, JSON.stringify(configured));
        assert.throws(() => openModel(), (error) => error.message.includes(section + '.' + field));
      }
    }
  });

  test('private message IDs exclude keyword-free context and keep stats consistent', () => {
    writeFileSync(policyPath, JSON.stringify(policy({ messages: {
      ...policy().messages, private_message_ids: [' msg-0 ', 'msg-1', 'msg-1', 'msg-3', 'missing'],
    } })));
    const model = openModel();
    try {
      assert.deepEqual(model.recentMessages({ limit: 2 }).map((m) => m.syncId), ['msg-4', 'msg-6']);
      assert.deepEqual(model.searchMessages({ query: '浅烘焙' }), []);
      assert.deepEqual(model.searchMessages({ query: '咖啡' }).map((m) => m.syncId), ['msg-6']);
      assert.deepEqual(model.stats().messages, { shareable: 2, private: 5 });
    } finally { model.close(); }
  });

  test('explicit empty allowlists suppress all methods and private counts include withheld items', () => {
    writeFileSync(policyPath, JSON.stringify(policy({
      messages: { ...policy().messages, private_message_ids: [], shareable_message_ids: [] },
      memory: { ...policy().memory, shareable_card_ids: [] },
    })));
    const model = openModel();
    try {
      assert.deepEqual(model.recentMessages(), []);
      assert.deepEqual(model.searchMessages({ query: '咖啡' }), []);
      assert.deepEqual(model.searchMemory({ query: '手冲咖啡' }), []);
      assert.deepEqual(model.searchMemory({ query: '咖啡' }), []);
      assert.deepEqual(model.getMemoryCards({ ids: BASE_CARDS.map((c) => c.id) }), []);
      assert.deepEqual(model.stats().messages, { shareable: 0, private: MESSAGES.length });
      assert.deepEqual(model.stats().memory, { shareable: 0, private: BASE_CARDS.length });
    } finally { model.close(); }
  });

  test('allowlists never override private rules and apply to both memory search branches', () => {
    writeFileSync(policyPath, JSON.stringify(policy({
      messages: {
        ...policy().messages, shareable_message_ids: MESSAGES.map((_, i) => 'msg-' + i),
        private_message_ids: ['msg-1'], private_keywords: ['手冲'],
      },
      memory: { ...policy().memory, shareable_card_ids: BASE_CARDS.filter((c) => c.id !== 'card-run').map((c) => c.id) },
    })));
    const model = openModel();
    try {
      assert.deepEqual(model.recentMessages().map((m) => m.syncId), ['msg-4', 'msg-6']);
      assert.deepEqual(model.searchMessages({ query: '咖啡' }).map((m) => m.syncId), ['msg-6']);
      assert.deepEqual(model.recentMessages({ characterId: OTHER }), []);
      assert.deepEqual(model.stats().messages, { shareable: 2, private: 5 });
      assert.deepEqual(model.getMemoryCards({ ids: BASE_CARDS.map((c) => c.id) }).map((c) => c.id), ['card-coffee']);
      assert.deepEqual(model.searchMemory({ query: '十公里' }), []);
      assert.deepEqual(model.searchMemory({ query: '晨' }), []);
      assert.deepEqual(model.searchMemory({ query: '手冲咖啡' }).map((c) => c.id), ['card-coffee']);
      assert.deepEqual(model.searchMemory({ query: '咖啡' }).map((c) => c.id), ['card-coffee']);
      assert.deepEqual(model.stats().memory, { shareable: 1, private: 7 });
    } finally { model.close(); }
    const configured = policy({ memory: { ...policy().memory, default: 'private', shareable_card_ids: ['card-coffee'] } });
    writeFileSync(policyPath, JSON.stringify(configured));
    const closed = openModel();
    try {
      assert.deepEqual(closed.getMemoryCards({ ids: ['card-coffee'] }), []);
      assert.deepEqual(closed.stats().memory, { shareable: 0, private: BASE_CARDS.length });
    } finally { closed.close(); }
  });

  test('newly synced messages and imported cards remain withheld until explicitly allowed', () => {
    writeFileSync(policyPath, JSON.stringify(policy({
      messages: { ...policy().messages, shareable_message_ids: ['msg-0'] },
      memory: { ...policy().memory, shareable_card_ids: ['card-coffee'] },
    })));
    const model = openModel();
    try {
      assert.equal(model.recentMessages().length, 1);
      assert.equal(model.searchMemory({ query: '咖啡' }).length, 1);
      const writer = new DatabaseSync(core);
      try {
        writer.prepare("INSERT INTO chat_messages VALUES ('msg-new', 'dev-synthetic', 100, ?, 'user', '新增的咖啡聊天', 1790000100000, 'chat', '[]', '[]', 'digest', 100)").run(LIN);
      } finally { writer.close(); }
      const source = new DatabaseSync(v3);
      try {
        source.exec("INSERT INTO memory_cards (id, type, title, droplet_label, retrieval_text, created_at, updated_at) VALUES ('card-new', 'fact', '新增的咖啡记忆', '咖啡', '新增的咖啡偏好', 1790000100000, 1790000100000)");
      } finally { source.close(); }
      runImport({ source: v3, out, apply: true });
      assert.deepEqual(model.recentMessages().map((m) => m.syncId), ['msg-0']);
      assert.deepEqual(model.searchMessages({ query: '新增' }), []);
      assert.deepEqual(model.searchMemory({ query: '新增的咖啡' }), []);
      assert.deepEqual(model.searchMemory({ query: '新增' }), []);
      assert.deepEqual(model.getMemoryCards({ ids: ['card-new'] }), []);
      assert.deepEqual(model.stats().messages, { shareable: 1, private: MESSAGES.length });
      assert.deepEqual(model.stats().memory, { shareable: 1, private: BASE_CARDS.length });
    } finally { model.close(); }
  });

  test('policy changes take effect only after reopening the read model', () => {
    writeFileSync(policyPath, JSON.stringify(policy({
      messages: { ...policy().messages, shareable_message_ids: [] },
      memory: { ...policy().memory, shareable_card_ids: [] },
    })));
    const original = openModel();
    try {
      writeFileSync(policyPath, JSON.stringify(policy({
        messages: { ...policy().messages, shareable_message_ids: [' msg-0 ', 'msg-0'] },
        memory: { ...policy().memory, shareable_card_ids: [' card-coffee ', 'card-coffee'] },
      })));
      assert.deepEqual(original.recentMessages(), []);
      assert.deepEqual(original.getMemoryCards({ ids: ['card-coffee'] }), []);
    } finally { original.close(); }
    const reopened = openModel();
    try {
      assert.deepEqual(reopened.recentMessages().map((m) => m.syncId), ['msg-0']);
      assert.deepEqual(reopened.getMemoryCards({ ids: ['card-coffee'] }).map((c) => c.id), ['card-coffee']);
      assert.deepEqual(reopened.stats().messages, { shareable: 1, private: 6 });
      assert.deepEqual(reopened.stats().memory, { shareable: 1, private: 7 });
    } finally { reopened.close(); }
  });

  test('large message ID lists do not exceed SQLite bound-variable limits', () => {
    const absent = Array.from({ length: 33000 }, (_, i) => 'absent-' + i);
    writeFileSync(policyPath, JSON.stringify(policy({ messages: {
      ...policy().messages, private_message_ids: absent, shareable_message_ids: [...absent, 'msg-0'],
    } })));
    const model = openModel();
    try {
      assert.deepEqual(model.recentMessages().map((m) => m.syncId), ['msg-0']);
      assert.deepEqual(model.searchMessages({ query: '咖啡' }).map((m) => m.syncId), ['msg-0']);
      assert.deepEqual(model.stats().messages, { shareable: 1, private: 6 });
    } finally { model.close(); }
  });

  test('reviewed-content hash helpers use stable UTF-8 and canonical field ordering', () => {
    assert.equal(hashMessageContent('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    const row = { type: 'fact', title: '咖啡', droplet_label: '日常', retrieval_text: '普通记忆' };
    assert.equal(hashMemoryCard(row), hashMessageContent(JSON.stringify(['fact', '咖啡', '日常', '普通记忆', null, null, ''])));
    assert.equal(hashMemoryCard({ ...row, status: null, structured_type: null, fields_json: null }), hashMemoryCard(row));
  });

  test('hash maps reject malformed objects, keys and hashes; omitted maps remain compatible', () => {
    const legacy = loadPolicy(policyPath);
    assert.equal(legacy.messages.shareableMessageHashes, null);
    assert.equal(legacy.memory.shareableCardHashes, null);
    for (const [section, field] of [['messages', 'shareable_message_hashes'], ['memory', 'shareable_card_hashes']]) {
      for (const invalid of [null, [], 'hash', 3, { '': 'a'.repeat(64) }, { '  ': 'a'.repeat(64) }, { id: null }, { id: 3 }, { id: 'a'.repeat(63) }, { id: 'g'.repeat(64) }]) {
        const configured = policy(); configured[section][field] = invalid;
        writeFileSync(policyPath, JSON.stringify(configured));
        assert.throws(() => openModel(), (error) => error.message.includes(section + '.' + field));
      }
    }
  });

  test('empty hash maps independently withhold all items despite nonempty ID allowlists', () => {
    writeFileSync(policyPath, JSON.stringify(policy({
      messages: { ...policy().messages, shareable_message_ids: ['msg-0'], shareable_message_hashes: {} },
      memory: { ...policy().memory, shareable_card_ids: ['card-coffee'], shareable_card_hashes: {} },
    })));
    const model = openModel();
    try {
      assert.deepEqual(model.recentMessages(), []);
      assert.deepEqual(model.searchMessages({ query: '咖啡' }), []);
      assert.deepEqual(model.searchMemory({ query: '手冲咖啡' }), []);
      assert.deepEqual(model.searchMemory({ query: '咖啡' }), []);
      assert.deepEqual(model.getMemoryCards({ ids: ['card-coffee'] }), []);
      assert.deepEqual(model.stats().messages, { shareable: 0, private: MESSAGES.length });
      assert.deepEqual(model.stats().memory, { shareable: 0, private: BASE_CARDS.length });
    } finally { model.close(); }
  });

  test('hash maps intersect with ID allowlists and never bypass private rules', () => {
    const messageHashes = Object.fromEntries(MESSAGES.map((m, i) => ['msg-' + i, hashMessageContent(m[2]).toUpperCase()]));
    const cardHashes = Object.fromEntries(readOut('SELECT * FROM memory_cards').map((c) => [c.id, hashMemoryCard(c).toUpperCase()]));
    delete messageHashes['msg-6']; delete cardHashes['card-run'];
    writeFileSync(policyPath, JSON.stringify(policy({
      messages: { ...policy().messages, shareable_message_ids: ['msg-0', 'msg-2', 'msg-3', 'msg-6'], shareable_message_hashes: messageHashes },
      memory: { ...policy().memory, shareable_card_ids: BASE_CARDS.filter((c) => c.id !== 'card-coffee').map((c) => c.id), shareable_card_hashes: cardHashes },
    })));
    const model = openModel();
    try {
      assert.deepEqual(model.recentMessages().map((m) => m.syncId), ['msg-0']);
      assert.deepEqual(model.searchMessages({ query: '咖啡' }).map((m) => m.syncId), ['msg-0']);
      assert.deepEqual(model.getMemoryCards({ ids: BASE_CARDS.map((c) => c.id) }), []);
      assert.deepEqual(model.stats().messages, { shareable: 1, private: 6 });
      assert.deepEqual(model.stats().memory, { shareable: 0, private: BASE_CARDS.length });
    } finally { model.close(); }
  });

  test('same-ID message and card content changes fail closed across all read exits', () => {
    const cardRows = readOut('SELECT * FROM memory_cards');
    writeFileSync(policyPath, JSON.stringify(policy({
      messages: { ...policy().messages, shareable_message_hashes: Object.fromEntries(MESSAGES.map((m, i) => ['msg-' + i, hashMessageContent(m[2])])) },
      memory: { ...policy().memory, shareable_card_hashes: Object.fromEntries(cardRows.map((c) => [c.id, hashMemoryCard(c)])) },
    })));
    const model = openModel();
    try {
      assert.equal(model.recentMessages().length, 4);
      assert.deepEqual(model.getMemoryCards({ ids: ['card-run'] }).map((c) => c.id), ['card-run']);
      const messagesWriter = new DatabaseSync(core);
      try { messagesWriter.prepare("UPDATE chat_messages SET content = ? WHERE sync_id = 'msg-0'").run('咖啡之后的未审核色情段落'); }
      finally { messagesWriter.close(); }
      assert.ok(model.recentMessages().every((m) => m.syncId !== 'msg-0'));
      assert.ok(model.searchMessages({ query: '咖啡' }).every((m) => m.syncId !== 'msg-0'));
      assert.deepEqual(model.searchMessages({ query: '未审核色情' }), []);
      assert.deepEqual(model.stats().messages, { shareable: 3, private: 4 });
      const original = cardRows.find((c) => c.id === 'card-run');
      for (const [field, value] of [
        ['type', 'event_edited'], ['title', '未审核色情标题'], ['droplet_label', '未审核标签'],
        ['retrieval_text', '未审核正文'], ['status', 'edited'], ['structured_type', 'edited_record'],
        ['fields_json', JSON.stringify({ description: '未审核色情字段' })],
      ]) {
        const writer = new DatabaseSync(out);
        try {
          writer.prepare('UPDATE memory_cards SET ' + field + ' = ? WHERE id = ?').run(value, 'card-run');
          assert.deepEqual(model.getMemoryCards({ ids: ['card-run'] }), [], field);
          assert.deepEqual(model.searchMemory({ query: '十公里' }), [], field);
          assert.deepEqual(model.searchMemory({ query: '晨' }), [], field);
          assert.deepEqual(model.stats().memory, { shareable: 1, private: 7 }, field);
          writer.prepare('UPDATE memory_cards SET ' + field + ' = ? WHERE id = ?').run(original[field], 'card-run');
        } finally { writer.close(); }
      }
      assert.equal(model.getMemoryCards({ ids: ['card-run'] }).length, 1);
    } finally { model.close(); }
  });

  test('searchMessages ranks by relevance and returns snippets', () => {
    const model = openModel();
    try {
      const results = model.searchMessages({ query: '咖啡 跑步' });
      assert.equal(results[0].syncId, 'msg-6'); // matches both terms
      assert.deepEqual(results.map((m) => m.syncId).sort(), ['msg-0', 'msg-1', 'msg-4', 'msg-6']);
      assert.ok(results.every((m) => typeof m.snippet === 'string' && m.snippet.length > 0));
      assert.deepEqual(model.searchMessages({ query: '   ' }), []);
    } finally {
      model.close();
    }
  });

  test('Chinese memory search: trigram for >=3 chars, LIKE for shorter', () => {
    const model = openModel();
    try {
      assert.deepEqual(model.searchMemory({ query: '手冲咖啡' }).map((c) => c.id), ['card-coffee']);
      assert.deepEqual(model.searchMemory({ query: '十公里' }).map((c) => c.id), ['card-run']);
      assert.deepEqual(model.searchMemory({ query: '咖啡' }).map((c) => c.id), ['card-coffee']);
      assert.deepEqual(model.searchMemory({ query: '晨' }).map((c) => c.id), ['card-run']);
      assert.deepEqual(model.searchMemory({ query: '100%' }), []);
      const card = model.searchMemory({ query: '晨跑' })[0];
      assert.deepEqual(card, {
        id: 'card-run', type: 'event', title: '周末晨跑十公里', dropletLabel: '晨跑',
        retrievalText: '周六早上在河边跑了十公里，配速稳定。', status: null,
        structured: { type: 'sport_record', fields: { distanceKm: 10 } },
        recordedAt: 1_790_000_000_000 + 60_000 - 5000, updatedAt: 1_790_000_000_000 + 60_000 + 1000,
      });
    } finally {
      model.close();
    }
  });

  test('stats and policySummary expose only totals', () => {
    const model = openModel();
    try {
      assert.deepEqual(model.stats(), {
        messages: { shareable: 4, private: 3 },
        memory: { shareable: 2, private: 6 },
        memorySnapshotAtMs: 1_795_000_000_000,
      });
      assert.deepEqual(model.policySummary(), { primaryCharacterId: LIN, memorySnapshotAtMs: 1_795_000_000_000 });
    } finally {
      model.close();
    }
  });
});

test('missing memory database: memory methods empty, messages still work', () => {
  const model = openModel({ memoryDbPath: path.join(dir, 'absent.sqlite') });
  try {
    assert.deepEqual(model.searchMemory({ query: '手冲咖啡' }), []);
    assert.deepEqual(model.getMemoryCards({ ids: ['card-coffee'] }), []);
    assert.equal(model.recentMessages().length, 4);
    assert.deepEqual(model.stats().memory, { shareable: 0, private: 0 });
    assert.equal(model.policySummary().memorySnapshotAtMs, null);
  } finally {
    model.close();
  }
});

test('read model sees a snapshot imported after it was opened', () => {
  const model = openModel();
  try {
    assert.deepEqual(model.searchMemory({ query: '手冲咖啡' }), []);
    runImport({ source: v3, out, apply: true });
    assert.equal(model.searchMemory({ query: '手冲咖啡' })[0].id, 'card-coffee');
  } finally {
    model.close();
  }
});

describe('auto_share_origins (B3 claude_web write-back)', () => {
  function addFrontendMessages() {
    const db = new DatabaseSync(core);
    const insert = db.prepare(`INSERT INTO chat_messages VALUES (?, ?, ?, ?, ?, ?, ?, 'chat', '[]', '[]', 'digest', ?)`);
    insert.run('web-0', 'frontend:claude_web', 1000, LIN, 'user', '网页端聊到了咖啡豆', 1_790_000_100_000, 100);
    insert.run('web-1', 'frontend:claude_web', 1001, LIN, 'companion', '网页端的手冲建议', 1_790_000_101_000, 101);
    insert.run('web-2', 'frontend:claude_web', 1002, LIN, 'user', '网页端提到秘密咖啡', 1_790_000_102_000, 102);
    insert.run('web-3', 'frontend:other_web', 1003, LIN, 'user', '另一个前端的咖啡', 1_790_000_103_000, 103);
    insert.run('web-4', 'frontend:claude_web', 1004, OTHER, 'user', '网页端别的角色咖啡', 1_790_000_104_000, 104);
    db.close();
  }

  test('omitted field keeps the allowlist strict for frontend messages', () => {
    addFrontendMessages();
    writeFileSync(policyPath, JSON.stringify(policy({
      messages: { ...policy().messages, shareable_message_ids: ['msg-0'] },
    })));
    const model = openModel();
    try {
      assert.deepEqual(model.recentMessages().map((m) => m.syncId), ['msg-0']);
    } finally { model.close(); }
  });

  test('listed origins bypass ID/hash allowlists but never private rules', () => {
    addFrontendMessages();
    writeFileSync(policyPath, JSON.stringify(policy({
      messages: {
        ...policy().messages,
        shareable_message_ids: ['msg-0'],
        shareable_message_hashes: { 'msg-0': hashMessageContent(MESSAGES[0][2]) },
        private_message_ids: ['web-1'],
        private_keywords: ['秘密'],
        auto_share_origins: ['claude_web'],
      },
    })));
    const model = openModel();
    try {
      // web-1 private id, web-2 private keyword, web-3 unlisted origin, web-4 other character.
      assert.deepEqual(model.recentMessages().map((m) => m.syncId), ['msg-0', 'web-0']);
      assert.deepEqual(model.searchMessages({ query: '咖啡' }).map((m) => m.syncId).sort(), ['msg-0', 'web-0']);
      assert.deepEqual(model.recentMessages({ characterId: OTHER }), []);
      assert.equal(model.stats().messages.shareable, 2);
    } finally { model.close(); }
  });

  test('invalid origin names fail closed', () => {
    for (const invalid of ['claude_web', ['Claude-Web'], ['frontend:claude_web'], [''], [1]]) {
      writeFileSync(policyPath, JSON.stringify(policy({
        messages: { ...policy().messages, auto_share_origins: invalid },
      })));
      assert.throws(() => openModel(), /auto_share_origins/);
    }
  });
});
