import { existsSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';

const MAX_RECENT = 100;
const MAX_SEARCH = 50;
const MAX_IDS = 100;
const SEARCH_CANDIDATES = 2000;
const SNIPPET_RADIUS = 40;
const TRIGRAM_MIN_CHARS = 3;

function fail(message) {
  throw new Error(`i_memory policy invalid: ${message}`);
}

function stringArray(value, label) {
  if (!Array.isArray(value) || value.some((item) => typeof item !== 'string' || !item.trim())) {
    fail(`${label} must be an array of non-empty strings`);
  }
  return value.map((item) => item.trim());
}

function optionalHashes(value, label) {
  if (value === undefined) return null;
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail(label + ' must be an object of SHA-256 hashes');
  const entries = Object.entries(value);
  for (const [id, hash] of entries) {
    if (!id.trim() || typeof hash !== 'string' || !/^[a-f0-9]{64}$/i.test(hash)) {
      fail(label + ' must contain non-empty IDs and SHA-256 hex strings');
    }
  }
  return new Map(entries.map(([id, hash]) => [id, hash.toLowerCase()]));
}

export function hashMessageContent(content) {
  return createHash('sha256').update(String(content), 'utf8').digest('hex');
}

// Stable reviewed-content fingerprint; accepts the database row's snake_case fields.
export function hashMemoryCard(row) {
  return hashMessageContent(JSON.stringify([
    row.type, row.title, row.droplet_label, row.retrieval_text, row.status ?? null,
    row.structured_type ?? null, row.fields_json ?? '',
  ]));
}

export const FRONTEND_ORIGIN_PREFIX = 'frontend:';

function autoShareOrigins(value) {
  if (value === undefined) return [];
  const names = stringArray(value, 'messages.auto_share_origins');
  if (names.some((name) => !/^[a-z][a-z0-9_]{1,31}$/.test(name))) {
    fail('messages.auto_share_origins must contain frontend names such as "claude_web"');
  }
  return [...new Set(names)].map((name) => `${FRONTEND_ORIGIN_PREFIX}${name}`);
}

// Exact approved Android sources; receive-sequence boundaries keep prior core
// history under its original review lists. Private exclusions still apply.
function autoShareDevices(value) {
  if (value === undefined) return [];
  const label = 'messages.auto_share_devices';
  if (!Array.isArray(value)) fail(label + ' must be an array of device rules');
  const seen = new Set();
  return value.map((rule) => {
    if (!rule || typeof rule !== 'object' || Array.isArray(rule)
      || Object.keys(rule).some(key => !['device_id', 'from_server_sequence', 'senders', 'history_window'].includes(key))
      || !Object.hasOwn(rule, 'device_id') || !Object.hasOwn(rule, 'from_server_sequence')) {
      fail(label + ' rules require device_id and from_server_sequence, with only optional senders and history_window');
    }
    const id = rule.device_id;
    if (typeof id !== 'string' || !id.trim() || id !== id.trim()
      || id.startsWith(FRONTEND_ORIGIN_PREFIX) || seen.has(id)) {
      fail(label + '.device_id must be an exact, unique non-frontend device ID');
    }
    if (!Number.isSafeInteger(rule.from_server_sequence) || rule.from_server_sequence < 1) {
      fail(label + '.from_server_sequence must be a positive safe integer');
    }
    seen.add(id);
    const result = { device_id: id, from_server_sequence: rule.from_server_sequence };
    if (Object.hasOwn(rule, 'senders')) {
      if (!Array.isArray(rule.senders) || rule.senders.length < 1 || rule.senders.length > 2
        || rule.senders.some(sender => !['user', 'companion'].includes(sender))
        || new Set(rule.senders).size !== rule.senders.length) {
        fail(label + '.senders must explicitly select unique user or companion values');
      }
      result.senders = [...rule.senders];
    }
    if (Object.hasOwn(rule, 'history_window')) {
      const history = rule.history_window;
      if (!history || typeof history !== 'object' || Array.isArray(history)
        || Object.keys(history).length !== 2
        || !Object.hasOwn(history, 'from_created_at_ms') || !Object.hasOwn(history, 'to_created_at_ms')
        || !Number.isSafeInteger(history.from_created_at_ms) || history.from_created_at_ms < 1
        || !Number.isSafeInteger(history.to_created_at_ms)
        || history.to_created_at_ms <= history.from_created_at_ms) {
        fail(label + '.history_window must be an explicit positive half-open creation-time range');
      }
      result.history_window = { ...history };
    }
    return result;
  });
}

function exposure(value, label) {
  if (value !== 'private' && value !== 'shareable') fail(`${label} must be "private" or "shareable"`);
  return value;
}

// Fail closed: any missing or malformed field throws instead of falling back.
export function loadPolicy(policyPath) {
  if (!policyPath || !existsSync(policyPath)) {
    throw new Error(`i_memory policy file is missing: ${policyPath}`);
  }
  let raw;
  try {
    raw = JSON.parse(readFileSync(policyPath, 'utf8'));
  } catch (error) {
    fail(`cannot parse JSON (${error.message})`);
  }
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) fail('root must be an object');
  if (![1,2].includes(raw.schema_version)) fail('schema_version must be 1 or 2');
  // v1 compatibility is permanently restricted to its two original domains.
  // New Core domains always use scoped HTTP; database visibility never grants access.
  const domains = raw.schema_version === 1 && raw.domains === undefined
    ? ['chat','memory_v3'] : stringArray(raw.domains, 'domains');
  if(new Set(domains).size!==domains.length || domains.some(domain=>!['chat','memory_v3'].includes(domain)))fail('unsupported domain');
  if (typeof raw.primary_character_id !== 'string' || !raw.primary_character_id.trim()) {
    fail('primary_character_id must be a non-empty string');
  }
  const { messages, memory } = raw;
  if (!messages || typeof messages !== 'object' || Array.isArray(messages)) fail('messages must be an object');
  if (!memory || typeof memory !== 'object' || Array.isArray(memory)) fail('memory must be an object');
  return {
    domains: new Set(domains),
    primaryCharacterId: raw.primary_character_id.trim(),
    messages: {
      default: exposure(messages.default, 'messages.default'),
      shareableCharacterIds: new Set(stringArray(messages.shareable_character_ids, 'messages.shareable_character_ids')),
      privateMessageTypes: stringArray(messages.private_message_types, 'messages.private_message_types'),
      privateMessageIds: messages.private_message_ids === undefined
        ? [] : stringArray(messages.private_message_ids, 'messages.private_message_ids'),
      // null preserves legacy behavior; an explicit empty allowlist shares nothing.
      shareableMessageIds: messages.shareable_message_ids === undefined
        ? null : stringArray(messages.shareable_message_ids, 'messages.shareable_message_ids'),
      shareableMessageHashes: optionalHashes(messages.shareable_message_hashes, 'messages.shareable_message_hashes'),
      // External frontends whose written-back messages skip the ID/hash allowlists
      // (never the private rules). Omitted keeps legacy behavior.
      autoShareOriginDeviceIds: autoShareOrigins(messages.auto_share_origins),
      autoShareDevices: autoShareDevices(messages.auto_share_devices),
      // Optional for backward compatibility; when present it must be valid.
      privateKeywords: (messages.private_keywords === undefined
        ? []
        : stringArray(messages.private_keywords, 'messages.private_keywords')).map((k) => k.toLowerCase()),
    },
    memory: {
      default: exposure(memory.default, 'memory.default'),
      privateTypes: new Set(stringArray(memory.private_types, 'memory.private_types')),
      privateStructuredTypes: new Set(stringArray(memory.private_structured_types, 'memory.private_structured_types')),
      privateCardIds: new Set(stringArray(memory.private_card_ids, 'memory.private_card_ids')),
      shareableCardIds: memory.shareable_card_ids === undefined
        ? null : new Set(stringArray(memory.shareable_card_ids, 'memory.shareable_card_ids')),
      shareableCardHashes: optionalHashes(memory.shareable_card_hashes, 'memory.shareable_card_hashes'),
      privateKeywords: stringArray(memory.private_keywords, 'memory.private_keywords').map((k) => k.toLowerCase()),
    },
  };
}

function clampLimit(value, fallback, max) {
  const number = Number(value ?? fallback);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(1, Math.min(max, Math.floor(number)));
}

function queryTerms(query) {
  return String(query ?? '').trim().split(/\s+/).filter(Boolean);
}

function charLength(text) {
  return Array.from(text).length;
}

function makeSnippet(content, terms) {
  const lower = content.toLowerCase();
  let at = -1;
  let termLength = 0;
  for (const term of terms) {
    const index = lower.indexOf(term.toLowerCase());
    if (index >= 0 && (at < 0 || index < at)) {
      at = index;
      termLength = term.length;
    }
  }
  if (at < 0) at = 0;
  const start = Math.max(0, at - SNIPPET_RADIUS);
  const end = Math.min(content.length, at + termLength + SNIPPET_RADIUS);
  return `${start > 0 ? '…' : ''}${content.slice(start, end)}${end < content.length ? '…' : ''}`;
}

function countOccurrences(haystack, needle) {
  let count = 0;
  let from = 0;
  while (needle && (from = haystack.indexOf(needle, from)) >= 0) {
    count += 1;
    from += needle.length;
  }
  return count;
}

function mapMessage(row) {
  return {
    syncId: row.sync_id,
    characterId: row.character_id,
    sender: row.sender === 'companion' ? 'companion' : 'user',
    content: row.content,
    createdAtMs: Number(row.created_at_ms),
    messageType: row.message_type,
    originDeviceId: row.origin_device_id,
  };
}

function parseFields(raw) {
  try {
    const parsed = JSON.parse(raw ?? '{}');
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    return {};
  }
}

function mapCard(row) {
  return {
    id: row.id,
    type: row.type,
    title: row.title,
    dropletLabel: row.droplet_label,
    retrievalText: row.retrieval_text,
    status: row.status ?? null,
    structured: row.structured_type == null
      ? null
      : { type: row.structured_type, fields: parseFields(row.fields_json) },
    recordedAt: row.recorded_at == null ? null : Number(row.recorded_at),
    updatedAt: Number(row.updated_at),
  };
}

const CARD_COLUMNS = `id, type, title, droplet_label, retrieval_text, status,
  structured_type, fields_json, recorded_at, updated_at`;

export function openReadModel({ coreDbPath, memoryDbPath, policyPath }) {
  const policy = loadPolicy(policyPath);
  if (!coreDbPath || !existsSync(coreDbPath)) {
    throw new Error(`i_core database does not exist: ${coreDbPath}`);
  }
  const core = new DatabaseSync(coreDbPath, { readOnly: true });
  core.function('i_message_hash', { deterministic: true }, hashMessageContent);
  let memory = null;

  const privateTypeList = policy.messages.privateMessageTypes;
  const privateMessageKeywords = policy.messages.privateKeywords;
  const privateMessageIds = policy.messages.privateMessageIds;
  const shareableMessageIds = policy.messages.shareableMessageIds;
  const shareableMessageHashes = policy.messages.shareableMessageHashes;
  // ID lists use one JSON parameter each, avoiding SQLite's bound-variable limit.
  // Bound parameters for typeFilter, in placeholder order.
  const autoShareOriginIds = policy.messages.autoShareOriginDeviceIds;
  const autoShareDeviceRules = policy.messages.autoShareDevices;
  const allowlistActive = shareableMessageIds !== null || shareableMessageHashes !== null;
  const filterParams = [
    ...privateTypeList, ...privateMessageKeywords,
    JSON.stringify(privateMessageIds),
    ...(allowlistActive && autoShareOriginIds.length ? [JSON.stringify(autoShareOriginIds)] : []),
    ...(allowlistActive && autoShareDeviceRules.length ? [JSON.stringify(autoShareDeviceRules)] : []),
    ...(shareableMessageIds === null ? [] : [JSON.stringify(shareableMessageIds)]),
    ...(shareableMessageHashes === null ? [] : [JSON.stringify(Object.fromEntries(shareableMessageHashes))]),
  ];
  // Positive allowlists; auto-shared frontend origins bypass only this part.
  const allowlistClauses = [
    shareableMessageIds === null ? null : 'sync_id IN (SELECT value FROM json_each(?))',
    shareableMessageHashes === null ? null
      : '(sync_id, i_message_hash(content)) IN (SELECT key, value FROM json_each(?))',
  ].filter(Boolean);
  let allowlistFilter = '';
  if (allowlistActive) {
    const automatic = [];
    if (autoShareOriginIds.length) {
      automatic.push('origin_device_id IN (SELECT value FROM json_each(?))');
    }
    if (autoShareDeviceRules.length) {
      // Registration/platform narrow the approved ID; they are not independent
      // attestation. Authenticated submit and local maintenance remain core trust boundaries.
      automatic.push(`(message_type = 'chat' AND EXISTS (
        SELECT 1 FROM json_each(?) AS approved
        JOIN devices AS d ON d.device_id = json_extract(approved.value, '$.device_id')
        WHERE d.platform = 'android'
          AND d.device_id = chat_messages.origin_device_id
          AND chat_messages.sender IN (
            SELECT value FROM json_each(COALESCE(json_extract(approved.value, '$.senders'), '["user"]'))
          )
          AND (
            chat_messages.server_sequence >= json_extract(approved.value, '$.from_server_sequence')
            OR (
              chat_messages.server_sequence < json_extract(approved.value, '$.from_server_sequence')
              AND chat_messages.created_at_ms >= json_extract(approved.value, '$.history_window.from_created_at_ms')
              AND chat_messages.created_at_ms < json_extract(approved.value, '$.history_window.to_created_at_ms')
            )
          )
      ))`);
    }
    allowlistFilter = `AND (${[...automatic, '(' + allowlistClauses.join(' AND ') + ')'].join(' OR ')})`;
  }
  // Private exclusions always apply, including to auto-shared origins.
  const typeFilter = [
    privateTypeList.length
      ? `AND message_type NOT IN (${privateTypeList.map(() => '?').join(', ')})`
      : '',
    ...privateMessageKeywords.map(() => 'AND instr(lower(content), ?) = 0'),
    'AND sync_id NOT IN (SELECT value FROM json_each(?))',
    allowlistFilter,
  ].join(' ');

  function messageCharacter(characterId) {
    const id = characterId ?? policy.primaryCharacterId;
    return policy.messages.shareableCharacterIds.has(id) ? id : null;
  }

  function memoryDb() {
    if (memory) return memory;
    if (!memoryDbPath || !existsSync(memoryDbPath)) return null;
    memory = new DatabaseSync(memoryDbPath, { readOnly: true });
    return memory;
  }

  function memoryMeta(key) {
    const db = memoryDb();
    if (!db) return null;
    return db.prepare('SELECT value FROM memory_metadata WHERE key = ?').get(key)?.value ?? null;
  }

  function isPrivateCard(row) {
    const rules = policy.memory;
    if (rules.default === 'private') return true;
    if (rules.shareableCardIds !== null && !rules.shareableCardIds.has(row.id)) return true;
    if (rules.shareableCardHashes !== null && rules.shareableCardHashes.get(row.id) !== hashMemoryCard(row)) return true;
    if (rules.privateCardIds.has(row.id)) return true;
    if (rules.privateTypes.has(row.type)) return true;
    if (row.structured_type != null && rules.privateStructuredTypes.has(row.structured_type)) return true;
    if (rules.privateKeywords.length) {
      // Conservative superset of the contract: label and structured fields are checked too.
      const text = [row.title, row.retrieval_text, row.droplet_label, row.fields_json ?? '']
        .join('\n').toLowerCase();
      if (rules.privateKeywords.some((keyword) => text.includes(keyword))) return true;
    }
    return false;
  }

  function shareableCards(rows, limit) {
    const out = [];
    for (const row of rows) {
      if (isPrivateCard(row)) continue;
      out.push(mapCard(row));
      if (out.length >= limit) break;
    }
    return out;
  }

  return {
    policySummary() {
      const snapshot = policy.domains.has('memory_v3') ? memoryMeta('snapshot_at_ms') : null;
      return {
        primaryCharacterId: policy.primaryCharacterId,
        memorySnapshotAtMs: snapshot == null ? null : Number(snapshot),
      };
    },

    recentMessages({ limit = 20, characterId } = {}) {
      if(!policy.domains.has('chat'))return [];
      const id = messageCharacter(characterId);
      if (!id) return [];
      const rows = core.prepare(`
        SELECT sync_id, character_id, sender, content, created_at_ms, message_type, origin_device_id
        FROM chat_messages
        WHERE character_id = ? ${typeFilter}
        ORDER BY created_at_ms DESC, server_sequence DESC
        LIMIT ?
      `).all(id, ...filterParams, clampLimit(limit, 20, MAX_RECENT));
      return rows.reverse().map(mapMessage);
    },

    searchMessages({ query, limit = 10, characterId } = {}) {
      if(!policy.domains.has('chat'))return [];
      const id = messageCharacter(characterId);
      const terms = queryTerms(query);
      if (!id || terms.length === 0) return [];
      const lowered = terms.map((term) => term.toLowerCase());
      const match = lowered.map(() => 'instr(lower(content), ?) > 0').join(' OR ');
      const rows = core.prepare(`
        SELECT sync_id, character_id, sender, content, created_at_ms, message_type, origin_device_id
        FROM chat_messages
        WHERE character_id = ? ${typeFilter} AND (${match})
        ORDER BY created_at_ms DESC, server_sequence DESC
        LIMIT ?
      `).all(id, ...filterParams, ...lowered, SEARCH_CANDIDATES);
      const scored = rows.map((row, recency) => {
        const content = row.content.toLowerCase();
        const matchedTerms = lowered.filter((term) => content.includes(term)).length;
        const hits = lowered.reduce((sum, term) => sum + countOccurrences(content, term), 0);
        return { row, recency, score: matchedTerms * 1000 + Math.min(hits, 999) };
      });
      scored.sort((a, b) => b.score - a.score || a.recency - b.recency);
      return scored.slice(0, clampLimit(limit, 10, MAX_SEARCH)).map(({ row }) => ({
        ...mapMessage(row),
        snippet: makeSnippet(row.content, terms),
      }));
    },

    searchMemory({ query, limit = 8 } = {}) {
      if(!policy.domains.has('memory_v3'))return [];
      const db = memoryDb();
      const terms = queryTerms(query);
      if (!db || terms.length === 0) return [];
      const max = clampLimit(limit, 8, MAX_SEARCH);
      let rows;
      if (terms.every((term) => charLength(term) >= TRIGRAM_MIN_CHARS)) {
        const ftsQuery = terms.map((term) => `"${term.replaceAll('"', '""')}"`).join(' OR ');
        rows = db.prepare(`
          SELECT ${CARD_COLUMNS.split(',').map((c) => `c.${c.trim()}`).join(', ')}
          FROM memory_cards_fts f
          JOIN memory_cards c ON c.id = f.card_id
          WHERE memory_cards_fts MATCH ?
          ORDER BY bm25(memory_cards_fts), c.updated_at DESC
        `).all(ftsQuery);
      } else {
        // Trigram cannot match terms shorter than 3 characters; fall back to LIKE.
        const lowered = terms.map((term) => term.toLowerCase());
        const haystack = "lower(title || ' ' || droplet_label || ' ' || retrieval_text)";
        const candidates = db.prepare(`
          SELECT ${CARD_COLUMNS} FROM memory_cards
          WHERE ${lowered.map(() => `${haystack} LIKE ? ESCAPE '\\'`).join(' OR ')}
          ORDER BY updated_at DESC
        `).all(...lowered.map((term) => `%${term.replace(/[\\%_]/g, (c) => `\\${c}`)}%`));
        rows = candidates
          .map((row, recency) => {
            const text = `${row.title} ${row.droplet_label} ${row.retrieval_text}`.toLowerCase();
            const score = lowered.filter((term) => text.includes(term)).length * 1000
              + Math.min(lowered.reduce((sum, term) => sum + countOccurrences(text, term), 0), 999);
            return { row, recency, score };
          })
          .sort((a, b) => b.score - a.score || a.recency - b.recency)
          .map(({ row }) => row);
      }
      return shareableCards(rows, max);
    },

    getMemoryCards({ ids } = {}) {
      if(!policy.domains.has('memory_v3'))return [];
      const db = memoryDb();
      if (!db || !Array.isArray(ids) || ids.length === 0) return [];
      const unique = [...new Set(ids.filter((id) => typeof id === 'string'))].slice(0, MAX_IDS);
      if (unique.length === 0) return [];
      const rows = db.prepare(`
        SELECT ${CARD_COLUMNS} FROM memory_cards WHERE id IN (${unique.map(() => '?').join(', ')})
      `).all(...unique);
      const byId = new Map(rows.map((row) => [row.id, row]));
      return shareableCards(unique.map((id) => byId.get(id)).filter(Boolean), MAX_IDS);
    },

    stats() {
      const shareableIds = policy.domains.has('chat') ? [...policy.messages.shareableCharacterIds] : [];
      const total = policy.domains.has('chat') ? Number(core.prepare('SELECT COUNT(*) AS n FROM chat_messages').get().n) : 0;
      const shareable = shareableIds.length
        ? Number(core.prepare(`
            SELECT COUNT(*) AS n FROM chat_messages
            WHERE character_id IN (${shareableIds.map(() => '?').join(', ')}) ${typeFilter}
          `).get(...shareableIds, ...filterParams).n)
        : 0;
      const db = policy.domains.has('memory_v3') ? memoryDb() : null;
      let memoryStats = { shareable: 0, private: 0 };
      if (db) {
        const rows = db.prepare(`SELECT ${CARD_COLUMNS} FROM memory_cards`).all();
        const privateCount = rows.filter(isPrivateCard).length;
        memoryStats = { shareable: rows.length - privateCount, private: privateCount };
      }
      const snapshot = policy.domains.has('memory_v3') ? memoryMeta('snapshot_at_ms') : null;
      return {
        messages: { shareable, private: total - shareable },
        memory: memoryStats,
        memorySnapshotAtMs: snapshot == null ? null : Number(snapshot),
      };
    },

    close() {
      core.close();
      if (memory) {
        memory.close();
        memory = null;
      }
    },
  };
}
