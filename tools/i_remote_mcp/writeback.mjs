// B3 写回：i_chat_turn（聊天轮次写进 i_core 时间线）与 i_remember（显式记录账本）。
// 设计见 docs/development/B3_WRITEBACK_DESIGN.md。只用 Node 内置模块。
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

export const FRONTEND_NAME = 'claude_web';
export const FRONTEND_DEVICE_ID = `frontend:${FRONTEND_NAME}`;
export const FRONTEND_PLATFORM = 'external-frontend';
export const CORE_PROTOCOL_VERSION = '0.1';

export const LIMITS = Object.freeze({
  maxTurnsPerCall: 20,
  maxTurnChars: 8000,
  maxCallChars: 60000,
  maxNoteChars: 2000,
  maxActiveNotes: 500,
  coreBatch: 50,
  maxPendingFlush: 200,
  alignWindow: 200,
  globalDedupWindowMs: 24 * 60 * 60 * 1000,
});

export const DEFAULT_RATE_LIMITS = Object.freeze({
  i_chat_turn: [{ windowMs: 60_000, max: 20 }, { windowMs: 86_400_000, max: 1500 }],
  i_remember: [{ windowMs: 60_000, max: 10 }, { windowMs: 86_400_000, max: 200 }],
});

const THREAD_ID = /^t_[A-Za-z0-9_-]{8,48}$/;
const NOTE_ID = /^note_[A-Za-z0-9_-]{8,48}$/;

export class WritebackInputError extends Error {}
export class RateLimitedError extends Error {}

export function sha256(value) {
  return createHash('sha256').update(String(value), 'utf8').digest('hex');
}

// 去重用的归一化：NFC、统一换行、去掉行尾空白和首尾空白。存进 i_core 的是原文。
export function normalizeText(text) {
  return String(text).normalize('NFC').replace(/\r\n?/g, '\n').replace(/[ \t]+$/gm, '').trim();
}

export function turnKey(role, content) {
  return `${role}:${sha256(normalizeText(content))}`;
}

function charLength(text) {
  return Array.from(text).length;
}

function newId(prefix) {
  return `${prefix}_${randomBytes(12).toString('base64url')}`;
}

// ---------- 限流（单用户，进程内滑动窗口） ----------

export class RateLimiter {
  constructor(rules = DEFAULT_RATE_LIMITS, now = () => Date.now()) {
    this.rules = rules;
    this.now = now;
    this.hits = new Map();
  }

  take(bucket) {
    const rules = this.rules[bucket] ?? [];
    const t = this.now();
    const longest = Math.max(0, ...rules.map((r) => r.windowMs));
    const list = (this.hits.get(bucket) ?? []).filter((x) => t - x < longest);
    for (const rule of rules) {
      if (list.filter((x) => t - x < rule.windowMs).length >= rule.max) {
        this.hits.set(bucket, list);
        throw new RateLimitedError('写入太频繁，请稍后再试。');
      }
    }
    list.push(t);
    this.hits.set(bucket, list);
  }
}

// ---------- 本机账本 ----------

export function openLedger(path) {
  mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  const db = new DatabaseSync(path);
  try { chmodSync(path, 0o600); } catch { /* Windows */ }
  db.exec(`
    PRAGMA journal_mode = WAL;
    PRAGMA busy_timeout = 5000;
    CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS threads (
      thread_id TEXT PRIMARY KEY,
      created_at_ms INTEGER NOT NULL,
      last_seen_ms INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS turns (
      thread_id TEXT NOT NULL,
      seq INTEGER NOT NULL,
      role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
      turn_key TEXT NOT NULL,
      sync_id TEXT NOT NULL UNIQUE,
      origin_sequence INTEGER NOT NULL UNIQUE,
      character_id TEXT NOT NULL,
      created_at_ms INTEGER NOT NULL,
      content TEXT,
      status TEXT NOT NULL CHECK(status IN ('pending', 'committed', 'rejected')),
      server_sequence INTEGER,
      error_code TEXT,
      PRIMARY KEY(thread_id, seq)
    );
    CREATE INDEX IF NOT EXISTS turns_status_idx ON turns(status, origin_sequence);
    CREATE INDEX IF NOT EXISTS turns_created_idx ON turns(created_at_ms);
    CREATE TABLE IF NOT EXISTS notes (
      note_id TEXT PRIMARY KEY,
      revision INTEGER NOT NULL,
      text TEXT,
      text_hash TEXT,
      status TEXT NOT NULL CHECK(status IN ('active', 'deleted')),
      created_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      feed_seq INTEGER NOT NULL UNIQUE,
      delivered_revision INTEGER NOT NULL DEFAULT 0,
      phone_card_id TEXT
    );
    CREATE INDEX IF NOT EXISTS notes_active_idx ON notes(status, updated_at_ms);
  `);
  db.prepare("INSERT INTO meta(key, value) VALUES ('schema_version', '1') ON CONFLICT(key) DO NOTHING").run();
  return db;
}

function metaGet(db, key) {
  return db.prepare('SELECT value FROM meta WHERE key = ?').get(key)?.value ?? null;
}

function metaSet(db, key, value) {
  db.prepare('INSERT INTO meta(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value')
    .run(key, String(value));
}

function transaction(db, fn) {
  db.exec('BEGIN IMMEDIATE');
  try {
    const result = fn();
    db.exec('COMMIT');
    return result;
  } catch (error) {
    db.exec('ROLLBACK');
    throw error;
  }
}

// 账本重建时 origin_sequence 仍需单调且不与旧值碰撞：以毫秒时间 ×1000 为起点。
function nextOriginSequence(db, now) {
  const stored = Number(metaGet(db, 'next_origin_sequence') ?? 0);
  const value = Math.max(stored, now * 1000);
  metaSet(db, 'next_origin_sequence', value + 1);
  return value;
}

function nextFeedSeq(db) {
  const value = Number(metaGet(db, 'next_feed_seq') ?? 1);
  metaSet(db, 'next_feed_seq', value + 1);
  return value;
}

// ---------- 轮次对齐（去重 + 补漏） ----------

// 返回 incoming 中真正新的下标起点。
// 1) 线程尾部与 incoming 开头的最长重叠视为重传；
// 2) 之后开头连续出现、且线程（新线程则最近 24 小时全局）里已有的轮次也视为重传；
//    遇到第一个未见过的轮次就停止，之后的一律保留（允许用户重复说“嗯”）。
export function alignTurns(existingKeys, incomingKeys, knownKeys) {
  let overlap = 0;
  for (let len = Math.min(existingKeys.length, incomingKeys.length); len > 0; len -= 1) {
    let match = true;
    for (let i = 0; i < len; i += 1) {
      if (existingKeys[existingKeys.length - len + i] !== incomingKeys[i]) { match = false; break; }
    }
    if (match) { overlap = len; break; }
  }
  let start = overlap;
  while (start < incomingKeys.length && knownKeys.has(incomingKeys[start])) start += 1;
  return start;
}

// ---------- i_core 前端客户端 ----------

export class CoreUnavailableError extends Error {}
export class CoreRejectedError extends Error {
  constructor(code, status) {
    super(`i_core rejected: ${code}`);
    this.code = code;
    this.status = status;
  }
}

export function loadFrontendCredential(stateDir) {
  const path = join(stateDir, 'core-frontend.json');
  if (!existsSync(path)) return null;
  const parsed = JSON.parse(readFileSync(path, 'utf8'));
  if (parsed?.device_id !== FRONTEND_DEVICE_ID || typeof parsed.device_token !== 'string') {
    throw new Error('core-frontend.json is invalid');
  }
  return parsed;
}

export function saveJsonPrivate(path, value) {
  mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  const tmp = `${path}.${process.pid}.tmp`;
  writeFileSync(tmp, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  renameSync(tmp, path);
  try { chmodSync(path, 0o600); } catch { /* Windows */ }
}

export async function pairFrontendDevice({ coreUrl, pairingCode, stateDir, fetchImpl = fetch }) {
  const res = await fetchImpl(`${coreUrl}/v1/core/devices/pair`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      device_id: FRONTEND_DEVICE_ID,
      display_name: 'claude.ai 网页端',
      platform: FRONTEND_PLATFORM,
      client_version: '0.1',
      pairing_code: pairingCode,
      capabilities: ['chat.frontend_turns'],
    }),
  });
  const body = await res.json().catch(() => null);
  if (!res.ok || typeof body?.device_token !== 'string') {
    throw new Error(`pairing failed: ${body?.error?.code ?? res.status}`);
  }
  saveJsonPrivate(join(stateDir, 'core-frontend.json'), {
    device_id: FRONTEND_DEVICE_ID,
    device_token: body.device_token,
    core_node_id: body.core_node_id ?? null,
    paired_at: new Date().toISOString(),
  });
  return { device_id: FRONTEND_DEVICE_ID, core_node_id: body.core_node_id ?? null };
}

export function createCoreFrontendClient({ coreUrl, deviceToken, fetchImpl = fetch, timeoutMs = 10_000 }) {
  return {
    async submit(messages) {
      let res;
      try {
        res = await fetchImpl(`${coreUrl}/v1/core/chat/messages`, {
          method: 'POST',
          headers: {
            'content-type': 'application/json',
            'x-core-protocol': CORE_PROTOCOL_VERSION,
            authorization: `Bearer ${deviceToken}`,
          },
          body: JSON.stringify({ device_id: FRONTEND_DEVICE_ID, messages }),
          signal: AbortSignal.timeout(timeoutMs),
        });
      } catch {
        throw new CoreUnavailableError('i_core unreachable');
      }
      const body = await res.json().catch(() => null);
      if (res.ok && Array.isArray(body?.results)) return body.results;
      if (res.status >= 500 || res.status === 426 || res.status === 401 || body?.error?.retryable) {
        throw new CoreUnavailableError(`i_core status ${res.status}`);
      }
      throw new CoreRejectedError(String(body?.error?.code ?? 'rejected').slice(0, 64), res.status);
    },
  };
}

// ---------- 写回服务 ----------

export function createWriteback({
  ledger,
  coreClient,
  now = () => Date.now(),
  rateLimiter = new RateLimiter(DEFAULT_RATE_LIMITS, now),
}) {
  const db = ledger;

  function validateTurns(args) {
    const { turns } = args;
    if (!Array.isArray(turns) || turns.length === 0) throw new WritebackInputError('turns 至少要有一条');
    if (turns.length > LIMITS.maxTurnsPerCall) {
      throw new WritebackInputError(`turns 一次最多 ${LIMITS.maxTurnsPerCall} 条；更早的轮次请分次提交`);
    }
    let total = 0;
    const out = turns.map((turn, index) => {
      if (!turn || typeof turn !== 'object' || Array.isArray(turn)) throw new WritebackInputError(`turns[${index}] 必须是对象`);
      if (turn.role !== 'user' && turn.role !== 'assistant') throw new WritebackInputError(`turns[${index}].role 只能是 user 或 assistant`);
      if (typeof turn.content !== 'string' || !normalizeText(turn.content)) throw new WritebackInputError(`turns[${index}].content 不能为空`);
      const length = charLength(turn.content);
      if (length > LIMITS.maxTurnChars) throw new WritebackInputError(`turns[${index}].content 超过 ${LIMITS.maxTurnChars} 字`);
      total += length;
      return { role: turn.role, content: turn.content.normalize('NFC') };
    });
    if (total > LIMITS.maxCallChars) throw new WritebackInputError(`一次提交总字数超过 ${LIMITS.maxCallChars}`);
    return out;
  }

  function planTurns(threadId, turns, characterId) {
    const t = now();
    return transaction(db, () => {
      const thread = db.prepare('SELECT thread_id FROM threads WHERE thread_id = ?').get(threadId);
      if (thread) db.prepare('UPDATE threads SET last_seen_ms = ? WHERE thread_id = ?').run(t, threadId);
      else db.prepare('INSERT INTO threads(thread_id, created_at_ms, last_seen_ms) VALUES (?, ?, ?)').run(threadId, t, t);
      const existing = db.prepare(`
        SELECT turn_key FROM turns WHERE thread_id = ? ORDER BY seq DESC LIMIT ?
      `).all(threadId, LIMITS.alignWindow).map((r) => r.turn_key).reverse();
      const known = new Set(existing);
      if (!thread || existing.length === 0) {
        // 新线程（Claude 丢了 thread_id 或新对话）：用最近 24 小时的全局轮次识别重传。
        for (const row of db.prepare('SELECT turn_key FROM turns WHERE created_at_ms >= ?').all(t - LIMITS.globalDedupWindowMs)) {
          known.add(row.turn_key);
        }
      }
      const keys = turns.map((turn) => turnKey(turn.role, turn.content));
      const start = alignTurns(existing, keys, known);
      const fresh = turns.slice(start);
      let seq = Number(db.prepare('SELECT COALESCE(MAX(seq), 0) AS s FROM turns WHERE thread_id = ?').get(threadId).s);
      let lastCreated = Number(metaGet(db, 'last_created_at_ms') ?? 0);
      const insert = db.prepare(`
        INSERT INTO turns(thread_id, seq, role, turn_key, sync_id, origin_sequence, character_id,
          created_at_ms, content, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')
      `);
      fresh.forEach((turn, index) => {
        seq += 1;
        // 同一批按顺序递增；漏调后补上的轮次用本次时间（无法得知原始时间）。
        const created = Math.max(t - (fresh.length - 1 - index), lastCreated + 1);
        lastCreated = created;
        insert.run(threadId, seq, turn.role, keys[start + index], `${FRONTEND_NAME}:${threadId}:${seq}`,
          nextOriginSequence(db, t), characterId, created, turn.content);
      });
      metaSet(db, 'last_created_at_ms', lastCreated);
      return { added: fresh.length, skipped: start };
    });
  }

  function markCommitted(rows, results) {
    const bySync = new Map(results.map((r) => [r.sync_id, r]));
    const update = db.prepare(`
      UPDATE turns SET status = 'committed', server_sequence = ?, content = NULL, error_code = NULL WHERE sync_id = ?
    `);
    transaction(db, () => {
      for (const row of rows) {
        const result = bySync.get(row.sync_id);
        if (result && (result.status === 'accepted' || result.status === 'duplicate')) {
          update.run(Number(result.server_sequence) || null, row.sync_id);
        }
      }
    });
  }

  function toCoreMessage(row) {
    return {
      sync_id: row.sync_id,
      origin_device_id: FRONTEND_DEVICE_ID,
      origin_sequence: Number(row.origin_sequence),
      character_id: row.character_id,
      sender: row.role === 'user' ? 'user' : 'companion',
      content: row.content,
      created_at_ms: Number(row.created_at_ms),
      message_type: 'chat',
      asset_refs: [],
      addenda: [],
    };
  }

  // 把所有待提交轮次（包括以前失败的）按顺序交给 i_core。
  async function flush() {
    const rows = db.prepare(`
      SELECT * FROM turns WHERE status = 'pending' ORDER BY origin_sequence LIMIT ?
    `).all(LIMITS.maxPendingFlush);
    let rejected = 0;
    for (let i = 0; i < rows.length; i += LIMITS.coreBatch) {
      const batch = rows.slice(i, i + LIMITS.coreBatch);
      try {
        markCommitted(batch, await coreClient.submit(batch.map(toCoreMessage)));
      } catch (error) {
        if (error instanceof CoreUnavailableError) return { status: 'unavailable', rejected };
        if (!(error instanceof CoreRejectedError)) throw error;
        // 批量被拒：逐条重试，隔离出真正有问题的那条。
        for (const row of batch) {
          try {
            markCommitted([row], await coreClient.submit([toCoreMessage(row)]));
          } catch (single) {
            if (single instanceof CoreUnavailableError) return { status: 'unavailable', rejected };
            if (!(single instanceof CoreRejectedError)) throw single;
            db.prepare("UPDATE turns SET status = 'rejected', error_code = ? WHERE sync_id = ?").run(single.code, row.sync_id);
            rejected += 1;
          }
        }
      }
    }
    return { status: 'ok', rejected };
  }

  function threadSyncIds(threadId) {
    return new Set(db.prepare('SELECT sync_id FROM turns WHERE thread_id = ?').all(threadId).map((r) => r.sync_id));
  }

  function projectNote(row) {
    return {
      note_id: row.note_id,
      revision: Number(row.revision),
      text: row.text,
      status: row.status,
      phone_status: Number(row.delivered_revision) >= Number(row.revision) ? 'on_phone' : 'waiting_for_phone',
      created_at: new Date(Number(row.created_at_ms)).toISOString(),
      updated_at: new Date(Number(row.updated_at_ms)).toISOString(),
    };
  }

  function getNote(noteId) {
    return db.prepare('SELECT * FROM notes WHERE note_id = ?').get(noteId) ?? null;
  }

  return {
    async chatTurn(args, { characterId }) {
      const threadId = args.thread_id === undefined || args.thread_id === null || args.thread_id === ''
        ? newId('t') : args.thread_id;
      if (typeof threadId !== 'string' || !THREAD_ID.test(threadId)) {
        throw new WritebackInputError('thread_id 格式不对；请原样使用上次返回的 thread_id，或者省略');
      }
      const turns = validateTurns(args);
      if (typeof characterId !== 'string' || !characterId) throw new Error('character id unavailable');
      rateLimiter.take('i_chat_turn');
      const plan = planTurns(threadId, turns, characterId);
      const result = await flush();
      const pending = Number(db.prepare("SELECT COUNT(*) AS n FROM turns WHERE status = 'pending'").get().n);
      return {
        thread_id: threadId,
        recorded: { new_turns: plan.added, duplicate_turns_skipped: plan.skipped, waiting_for_retry: pending },
        core_status: result.status,
        excludeSyncIds: threadSyncIds(threadId),
      };
    },

    remember(args) {
      const action = args.action ?? 'add';
      if (!['add', 'update', 'delete', 'list'].includes(action)) {
        throw new WritebackInputError('action 只能是 add、update、delete 或 list');
      }
      if (action === 'list') return { action, notes: this.activeNotes(50) };
      const t = now();
      const readText = () => {
        if (typeof args.text !== 'string' || !normalizeText(args.text)) throw new WritebackInputError('text 不能为空');
        if (charLength(args.text) > LIMITS.maxNoteChars) throw new WritebackInputError(`text 最多 ${LIMITS.maxNoteChars} 字`);
        return normalizeText(args.text);
      };
      const readNote = () => {
        if (typeof args.note_id !== 'string' || !NOTE_ID.test(args.note_id)) throw new WritebackInputError('note_id 格式不对');
        const row = getNote(args.note_id);
        if (!row) throw new WritebackInputError('没有这条记录');
        return row;
      };
      if (action === 'add') {
        const text = readText();
        const hash = sha256(text);
        const same = db.prepare("SELECT * FROM notes WHERE status = 'active' AND text_hash = ?").get(hash);
        if (same) return { action, duplicate: true, note: projectNote(same) };
        rateLimiter.take('i_remember');
        const count = Number(db.prepare("SELECT COUNT(*) AS n FROM notes WHERE status = 'active'").get().n);
        if (count >= LIMITS.maxActiveNotes) throw new WritebackInputError('待同步的记录太多，请先在手机上处理');
        const noteId = newId('note');
        transaction(db, () => db.prepare(`
          INSERT INTO notes(note_id, revision, text, text_hash, status, created_at_ms, updated_at_ms, feed_seq)
          VALUES (?, 1, ?, ?, 'active', ?, ?, ?)
        `).run(noteId, text, hash, t, t, nextFeedSeq(db)));
        return { action, duplicate: false, note: projectNote(getNote(noteId)) };
      }
      const row = readNote();
      if (action === 'update') {
        if (row.status !== 'active') throw new WritebackInputError('这条记录已经删除，不能修改');
        const text = readText();
        if (sha256(text) === row.text_hash) return { action, unchanged: true, note: projectNote(row) };
        rateLimiter.take('i_remember');
        transaction(db, () => db.prepare(`
          UPDATE notes SET revision = revision + 1, text = ?, text_hash = ?, updated_at_ms = ?, feed_seq = ? WHERE note_id = ?
        `).run(text, sha256(text), t, nextFeedSeq(db), row.note_id));
        return { action, note: projectNote(getNote(row.note_id)) };
      }
      // delete：真正删除正文，只留不含内容的删除标记，手机据此删掉对应卡片。
      if (row.status === 'deleted') return { action, unchanged: true, note: projectNote(row) };
      rateLimiter.take('i_remember');
      transaction(db, () => db.prepare(`
        UPDATE notes SET revision = revision + 1, text = NULL, text_hash = NULL, status = 'deleted',
          updated_at_ms = ?, feed_seq = ? WHERE note_id = ?
      `).run(t, nextFeedSeq(db), row.note_id));
      return { action, note: projectNote(getNote(row.note_id)) };
    },

    activeNotes(limit = 10) {
      return db.prepare("SELECT * FROM notes WHERE status = 'active' ORDER BY updated_at_ms DESC LIMIT ?")
        .all(limit).map(projectNote);
    },

    searchNotes(query, limit = 8) {
      const terms = String(query).trim().toLowerCase().split(/\s+/).filter(Boolean);
      if (!terms.length) return [];
      return db.prepare("SELECT * FROM notes WHERE status = 'active' ORDER BY updated_at_ms DESC").all()
        .filter((row) => terms.some((term) => row.text.toLowerCase().includes(term)))
        .slice(0, limit).map(projectNote);
    },

    // ---------- 手机拉取通道 ----------

    noteChanges({ after = 0, limit = 100 } = {}) {
      const rows = db.prepare('SELECT * FROM notes WHERE feed_seq > ? ORDER BY feed_seq LIMIT ?').all(after, limit + 1);
      const page = rows.slice(0, limit);
      return {
        notes: page.map((row) => ({
          note_id: row.note_id,
          revision: Number(row.revision),
          op: row.status === 'deleted' ? 'delete' : 'upsert',
          text: row.status === 'deleted' ? null : row.text,
          source: FRONTEND_NAME,
          created_at_ms: Number(row.created_at_ms),
          updated_at_ms: Number(row.updated_at_ms),
          feed_seq: Number(row.feed_seq),
        })),
        next_after: page.length ? Number(page.at(-1).feed_seq) : after,
        has_more: rows.length > limit,
      };
    },

    ackNote({ note_id: noteId, revision, card_id: cardId }) {
      if (typeof noteId !== 'string' || !NOTE_ID.test(noteId)) throw new WritebackInputError('note_id invalid');
      if (!Number.isSafeInteger(revision) || revision < 1) throw new WritebackInputError('revision invalid');
      if (cardId !== undefined && cardId !== null && (typeof cardId !== 'string' || cardId.length > 200)) {
        throw new WritebackInputError('card_id invalid');
      }
      const row = getNote(noteId);
      if (!row || revision > Number(row.revision)) throw new WritebackInputError('unknown note revision');
      db.prepare(`
        UPDATE notes SET delivered_revision = MAX(delivered_revision, ?), phone_card_id = COALESCE(?, phone_card_id)
        WHERE note_id = ?
      `).run(revision, cardId ?? null, noteId);
      return { ok: true };
    },

    close() { db.close(); },
  };
}

// ---------- 手机拉取令牌 ----------

export function issuePhoneToken(stateDir) {
  const token = `iph_${randomBytes(32).toString('base64url')}`;
  saveJsonPrivate(join(stateDir, 'phone-feed.json'), { token_sha256: sha256(token), issued_at: new Date().toISOString() });
  return token;
}

export function loadPhoneTokenHash(stateDir) {
  const path = join(stateDir, 'phone-feed.json');
  if (!existsSync(path)) return null;
  const hash = JSON.parse(readFileSync(path, 'utf8'))?.token_sha256;
  return typeof hash === 'string' && /^[a-f0-9]{64}$/.test(hash) ? hash : null;
}

export function verifyPhoneToken(header, tokenHash) {
  const match = /^Bearer\s+(iph_[A-Za-z0-9_-]{20,100})\s*$/.exec(String(header ?? ''));
  if (!match || !tokenHash) return false;
  const a = Buffer.from(sha256(match[1]));
  const b = Buffer.from(tokenHash);
  return a.length === b.length && timingSafeEqual(a, b);
}
