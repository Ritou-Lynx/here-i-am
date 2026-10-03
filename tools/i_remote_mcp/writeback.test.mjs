// B3 写回单元测试：对齐去重、漏轮补齐、重试、拒收隔离、记录增改删、手机拉取、限流与大小限制。
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, test } from 'node:test';
import {
  CoreRejectedError,
  CoreUnavailableError,
  LIMITS,
  RateLimitedError,
  RateLimiter,
  WritebackInputError,
  alignTurns,
  createWriteback,
  issuePhoneToken,
  loadPhoneTokenHash,
  openLedger,
  verifyPhoneToken,
} from './writeback.mjs';

const CHAR = 'char-lin-ai';

function fakeCore() {
  const stored = new Map();
  const core = {
    down: false,
    rejectSyncIds: new Set(),
    calls: 0,
    stored,
    async submit(messages) {
      core.calls += 1;
      if (core.down) throw new CoreUnavailableError('down');
      if (messages.some((m) => core.rejectSyncIds.has(m.sync_id))) throw new CoreRejectedError('immutable_message_conflict', 409);
      return messages.map((m) => {
        if (stored.has(m.sync_id)) return { sync_id: m.sync_id, status: 'duplicate', server_sequence: stored.get(m.sync_id).seq };
        stored.set(m.sync_id, { ...m, seq: stored.size + 1 });
        return { sync_id: m.sync_id, status: 'accepted', server_sequence: stored.size };
      });
    },
    contents() {
      return [...stored.values()].sort((a, b) => a.seq - b.seq).map((m) => `${m.sender}:${m.content}`);
    },
  };
  return core;
}

const u = (content) => ({ role: 'user', content });
const a = (content) => ({ role: 'assistant', content });

describe('alignTurns', () => {
  test('tail overlap, leading retransmissions and repeated short replies', () => {
    assert.equal(alignTurns(['u1', 'a1', 'u2'], ['a1', 'u2', 'a2', 'u3'], new Set(['u1', 'a1', 'u2'])), 2);
    assert.equal(alignTurns(['u1', 'a1'], ['u1', 'a1', 'u2'], new Set(['u1', 'a1'])), 2);
    // Not contiguous with the tail but already known at the start → retransmission.
    assert.equal(alignTurns(['u1', 'a1', 'u2', 'a2'], ['u1', 'a1', 'u3'], new Set(['u1', 'a1', 'u2', 'a2'])), 2);
    // A known turn after the first new one is kept (the user repeated "嗯").
    assert.equal(alignTurns(['u嗯', 'a1'], ['a2', 'u嗯'], new Set(['u嗯', 'a1'])), 0);
    assert.equal(alignTurns([], ['u1'], new Set()), 0);
  });
});

describe('createWriteback', () => {
  let dir;
  let core;
  let clock;
  let wb;

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'i-writeback-'));
    core = fakeCore();
    clock = { t: Date.UTC(2026, 9, 3, 2, 0, 0) };
    wb = createWriteback({
      ledger: openLedger(join(dir, 'writeback.sqlite')),
      coreClient: core,
      now: () => clock.t,
      rateLimiter: new RateLimiter({}, () => clock.t),
    });
  });

  afterEach(() => {
    wb.close();
    rmSync(dir, { recursive: true, force: true });
  });

  const turn = (args) => wb.chatTurn(args, { characterId: CHAR });

  test('normal flow: each call adds the previous reply and the new user message, in order', async () => {
    const first = await turn({ turns: [u('早上好')] });
    assert.match(first.thread_id, /^t_/);
    assert.deepEqual(first.recorded, { new_turns: 1, duplicate_turns_skipped: 0, waiting_for_retry: 0 });
    clock.t += 60_000;
    await turn({ thread_id: first.thread_id, turns: [a('早，睡得好吗'), u('还行')] });
    clock.t += 60_000;
    await turn({ thread_id: first.thread_id, turns: [a('那就好'), u('今天去散步')] });
    assert.deepEqual(core.contents(), ['user:早上好', 'companion:早，睡得好吗', 'user:还行', 'companion:那就好', 'user:今天去散步']);
    const messages = [...core.stored.values()];
    assert.ok(messages.every((m) => m.origin_device_id === 'frontend:claude_web' && m.character_id === CHAR));
    assert.ok(messages.every((m, i) => i === 0 || m.created_at_ms > messages[i - 1].created_at_ms));
    assert.ok(messages.every((m, i) => i === 0 || m.origin_sequence > messages[i - 1].origin_sequence));
    assert.equal(new Set(messages.map((m) => m.sync_id)).size, 5);
  });

  test('overlapping resubmission and full replay are deduplicated', async () => {
    const { thread_id } = await turn({ turns: [u('第一句')] });
    await turn({ thread_id, turns: [a('回复一'), u('第二句')] });
    const overlap = await turn({ thread_id, turns: [u('第一句'), a('回复一'), u('第二句'), a('回复二'), u('第三句')] });
    assert.deepEqual(overlap.recorded, { new_turns: 2, duplicate_turns_skipped: 3, waiting_for_retry: 0 });
    const replay = await turn({ thread_id, turns: [a('回复二'), u('第三句')] });
    assert.equal(replay.recorded.new_turns, 0);
    // Whitespace/CRLF differences do not defeat dedup.
    const crlf = await turn({ thread_id, turns: [a('回复二  \r\n'), u(' 第三句 ')] });
    assert.equal(crlf.recorded.new_turns, 0);
    assert.equal(core.stored.size, 5);
  });

  test('missed calls are filled in by the next call', async () => {
    const { thread_id } = await turn({ turns: [u('一')] });
    // Claude skipped the call for turn 二; the next call carries everything since the last success.
    await turn({ thread_id, turns: [a('回一'), u('二'), a('回二'), u('三')] });
    assert.deepEqual(core.contents(), ['user:一', 'companion:回一', 'user:二', 'companion:回二', 'user:三']);
  });

  test('a lost thread_id still deduplicates recent retransmissions', async () => {
    const { thread_id } = await turn({ turns: [u('甲')] });
    await turn({ thread_id, turns: [a('回甲'), u('乙')] });
    const lost = await turn({ turns: [a('回甲'), u('乙'), a('回乙'), u('丙')] });
    assert.notEqual(lost.thread_id, thread_id);
    assert.equal(lost.recorded.new_turns, 2);
    assert.equal(core.stored.size, 5);
  });

  test('i_core outage keeps turns pending and the next call retries them in order', async () => {
    core.down = true;
    const first = await turn({ turns: [u('离线时说的话')] });
    assert.equal(first.core_status, 'unavailable');
    assert.equal(first.recorded.waiting_for_retry, 1);
    assert.equal(core.stored.size, 0);
    core.down = false;
    const second = await turn({ thread_id: first.thread_id, turns: [a('收到'), u('恢复了')] });
    assert.equal(second.core_status, 'ok');
    assert.equal(second.recorded.waiting_for_retry, 0);
    assert.deepEqual(core.contents(), ['user:离线时说的话', 'companion:收到', 'user:恢复了']);
  });

  test('a rejected message is isolated and does not block the rest', async () => {
    const { thread_id } = await turn({ turns: [u('好的一句')] });
    core.rejectSyncIds.add(`claude_web:${thread_id}:2`);
    const r = await turn({ thread_id, turns: [a('会被拒'), u('后面这句')] });
    assert.equal(r.core_status, 'ok');
    assert.deepEqual(core.contents(), ['user:好的一句', 'user:后面这句']);
    assert.equal(r.recorded.waiting_for_retry, 0);
  });

  test('input validation and size limits', async () => {
    const bad = [
      {},
      { turns: [] },
      { turns: [{ role: 'system', content: 'x' }] },
      { turns: [u('   ')] },
      { turns: [u('x'.repeat(LIMITS.maxTurnChars + 1))] },
      { turns: Array.from({ length: LIMITS.maxTurnsPerCall + 1 }, (_, i) => u(`第${i}句`)) },
      { turns: Array.from({ length: 8 }, () => u('字'.repeat(LIMITS.maxTurnChars))) },
      { thread_id: '../etc', turns: [u('x')] },
    ];
    for (const args of bad) await assert.rejects(turn(args), WritebackInputError, JSON.stringify(args).slice(0, 60));
    assert.equal(core.calls, 0);
  });

  test('rate limits apply per tool', async () => {
    wb.close();
    wb = createWriteback({
      ledger: openLedger(join(dir, 'writeback.sqlite')),
      coreClient: core,
      now: () => clock.t,
      rateLimiter: new RateLimiter({ i_chat_turn: [{ windowMs: 60_000, max: 2 }], i_remember: [{ windowMs: 60_000, max: 1 }] }, () => clock.t),
    });
    await turn({ turns: [u('1')] });
    await turn({ turns: [u('2')] });
    await assert.rejects(turn({ turns: [u('3')] }), RateLimitedError);
    wb.remember({ text: '第一条记录' });
    assert.throws(() => wb.remember({ text: '第二条记录' }), RateLimitedError);
    clock.t += 61_000;
    await turn({ turns: [u('3')] });
    wb.remember({ text: '第二条记录' });
  });

  test('remember: add is idempotent, update bumps revision, delete erases text', () => {
    const added = wb.remember({ text: '  周六下午三点去看牙医 ' });
    assert.equal(added.note.text, '周六下午三点去看牙医');
    assert.equal(added.note.revision, 1);
    assert.equal(added.note.phone_status, 'waiting_for_phone');
    assert.equal(wb.remember({ text: '周六下午三点去看牙医' }).duplicate, true);
    const id = added.note.note_id;
    const updated = wb.remember({ action: 'update', note_id: id, text: '周六下午四点去看牙医' });
    assert.equal(updated.note.revision, 2);
    assert.deepEqual(wb.remember({ action: 'list' }).notes.map((n) => n.text), ['周六下午四点去看牙医']);
    assert.equal(wb.searchNotes('牙医').length, 1);
    const deleted = wb.remember({ action: 'delete', note_id: id });
    assert.equal(deleted.note.status, 'deleted');
    assert.equal(deleted.note.text, null);
    assert.equal(wb.remember({ action: 'delete', note_id: id }).unchanged, true);
    assert.throws(() => wb.remember({ action: 'update', note_id: id, text: '复活' }), WritebackInputError);
    assert.deepEqual(wb.activeNotes(), []);
    assert.deepEqual(wb.searchNotes('牙医'), []);
    for (const args of [{ action: 'drop' }, { text: '' }, { text: 'x'.repeat(LIMITS.maxNoteChars + 1) }, { action: 'delete', note_id: 'note_missing123' }, { action: 'update', note_id: 'bad', text: 'x' }]) {
      assert.throws(() => wb.remember(args), WritebackInputError);
    }
  });

  test('phone feed: latest revision per note, tombstones without text, acknowledgements', () => {
    const one = wb.remember({ text: '记录一' }).note;
    const two = wb.remember({ text: '记录二' }).note;
    let page = wb.noteChanges({ after: 0, limit: 1 });
    assert.equal(page.has_more, true);
    assert.equal(page.notes[0].note_id, one.note_id);
    page = wb.noteChanges({ after: page.next_after });
    assert.deepEqual(page.notes.map((n) => [n.note_id, n.op, n.text, n.source]), [[two.note_id, 'upsert', '记录二', 'claude_web']]);
    const cursor = page.next_after;
    wb.ackNote({ note_id: one.note_id, revision: 1, card_id: 'card-abc' });
    assert.equal(wb.remember({ action: 'list' }).notes.find((n) => n.note_id === one.note_id).phone_status, 'on_phone');
    wb.remember({ action: 'update', note_id: one.note_id, text: '记录一（改）' });
    wb.remember({ action: 'delete', note_id: two.note_id });
    const changes = wb.noteChanges({ after: cursor });
    assert.deepEqual(changes.notes.map((n) => [n.note_id, n.op, n.revision, n.text]), [
      [one.note_id, 'upsert', 2, '记录一（改）'],
      [two.note_id, 'delete', 2, null],
    ]);
    // Full resync from zero no longer contains deleted text anywhere.
    assert.ok(!JSON.stringify(wb.noteChanges({ after: 0 })).includes('记录二'));
    assert.throws(() => wb.ackNote({ note_id: one.note_id, revision: 9 }), WritebackInputError);
    assert.throws(() => wb.ackNote({ note_id: 'x', revision: 1 }), WritebackInputError);
  });

  test('ledger survives reopen; origin sequences stay monotonic', async () => {
    const { thread_id } = await turn({ turns: [u('重启前')] });
    wb.close();
    wb = createWriteback({ ledger: openLedger(join(dir, 'writeback.sqlite')), coreClient: core, now: () => clock.t, rateLimiter: new RateLimiter({}) });
    const r = await turn({ thread_id, turns: [u('重启前'), a('回复'), u('重启后')] });
    assert.equal(r.recorded.new_turns, 2);
    const seqs = [...core.stored.values()].map((m) => m.origin_sequence);
    assert.deepEqual(seqs, [...seqs].sort((x, y) => x - y));
  });
});

test('phone token is shown once, stored as a hash and verified in constant time', () => {
  const dir = mkdtempSync(join(tmpdir(), 'i-phone-token-'));
  try {
    const token = issuePhoneToken(dir);
    const hash = loadPhoneTokenHash(dir);
    assert.match(hash, /^[a-f0-9]{64}$/);
    assert.ok(!hash.includes(token));
    assert.equal(verifyPhoneToken(`Bearer ${token}`, hash), true);
    assert.equal(verifyPhoneToken(`Bearer ${token}x`, hash), false);
    assert.equal(verifyPhoneToken(undefined, hash), false);
    const rotated = issuePhoneToken(dir);
    assert.equal(verifyPhoneToken(`Bearer ${token}`, loadPhoneTokenHash(dir)), false);
    assert.equal(verifyPhoneToken(`Bearer ${rotated}`, loadPhoneTokenHash(dir)), true);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
