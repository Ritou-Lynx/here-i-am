import { createHash } from 'node:crypto';
import { existsSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { backup, DatabaseSync } from 'node:sqlite';
import { ICoreStore } from './i_core_store.mjs';

const REQUIRED_COLUMNS = [
  'id',
  'sync_id',
  'origin_device_id',
  'character_id',
  'is_from_character',
  'content',
  'timestamp',
  'message_type',
  'attachments_json',
];

function parseArgs(argv) {
  const options = { apply: false, coreStopped: false };
  for (let index = 0; index < argv.length; index++) {
    const argument = argv[index];
    if (argument === '--apply') options.apply = true;
    else if (argument === '--core-stopped') options.coreStopped = true;
    else if (argument === '--source') options.source = argv[++index];
    else if (argument === '--core') options.core = argv[++index];
    else if (argument === '--backup-dir') options.backupDir = argv[++index];
    else throw new Error(`Unknown argument: ${argument}`);
  }
  if (!options.source || !options.core) {
    throw new Error('Usage: node import_v3_chat.mjs --source <v3.sqlite> --core <i-core.sqlite> [--apply --core-stopped]');
  }
  options.source = path.resolve(options.source);
  options.core = path.resolve(options.core);
  options.backupDir = path.resolve(
    options.backupDir ?? path.join(path.dirname(options.core), 'backups'),
  );
  if (options.source === options.core) {
    throw new Error('Source and authority core database paths must be different.');
  }
  if (options.apply && !options.coreStopped) {
    throw new Error('--apply requires --core-stopped after the authority service has been stopped.');
  }
  return options;
}

function attachmentCount(raw) {
  if (typeof raw !== 'string' || !raw.trim()) return 0;
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.length : 0;
  } catch (_) {
    return 0;
  }
}

function toMilliseconds(value) {
  const timestamp = Number(value);
  if (!Number.isSafeInteger(timestamp) || timestamp < 0) {
    throw new Error(`Invalid V3 chat timestamp: ${value}`);
  }
  return timestamp < 100_000_000_000 ? timestamp * 1000 : timestamp;
}

export function readV3ChatSnapshot(sourcePath) {
  if (!existsSync(sourcePath)) throw new Error(`Source database does not exist: ${sourcePath}`);
  const source = new DatabaseSync(sourcePath, { readOnly: true });
  try {
    const integrity = source.prepare('PRAGMA integrity_check').get().integrity_check;
    if (integrity !== 'ok') throw new Error(`Source integrity check failed: ${integrity}`);
    const columns = new Set(
      source.prepare('PRAGMA table_info(persona_chat_messages)').all().map((row) => row.name),
    );
    const missing = REQUIRED_COLUMNS.filter((column) => !columns.has(column));
    if (missing.length > 0) {
      throw new Error(`Source chat schema is missing: ${missing.join(', ')}`);
    }
    const duplicate = source.prepare(`
      SELECT sync_id, COUNT(*) AS count
      FROM persona_chat_messages
      GROUP BY sync_id
      HAVING sync_id IS NULL OR trim(sync_id) = '' OR COUNT(*) > 1
      LIMIT 1
    `).get();
    if (duplicate) throw new Error('Source contains a missing or duplicate sync_id.');

    const rows = source.prepare(`
      SELECT id, sync_id, origin_device_id, character_id, is_from_character,
             content, timestamp, message_type, attachments_json
      FROM persona_chat_messages
      ORDER BY timestamp ASC, id ASC
    `).all();
    const sourceOrigins = [...new Set(rows.map((row) => row.origin_device_id ?? ''))].sort();
    const sourceKey = createHash('sha256')
      .update(`hereiam-v3-chat\n${sourceOrigins.join('\n')}`)
      .digest('hex');
    const importDeviceId = `v3-history-${sourceKey.slice(0, 20)}`;
    let attachmentsOmitted = 0;
    const messages = [];
    let emptyMessagesOmitted = 0;
    for (const row of rows) {
      const count = attachmentCount(row.attachments_json);
      if (count > 0) attachmentsOmitted += count;
      if (row.content.length === 0) {
        emptyMessagesOmitted += 1;
        continue;
      }
      const sourceLocalId = Number(row.id);
      if (!Number.isSafeInteger(sourceLocalId) || sourceLocalId < 0) {
        throw new Error(`Invalid V3 chat id: ${row.id}`);
      }
      messages.push({
        sync_id: row.sync_id,
        origin_device_id: importDeviceId,
        origin_sequence: sourceLocalId,
        character_id: row.character_id,
        sender: Number(row.is_from_character) === 1 ? 'companion' : 'user',
        content: row.content,
        created_at_ms: toMilliseconds(row.timestamp),
        message_type: row.message_type || 'chat',
        asset_refs: [],
        addenda: [{
          kind: 'historical_import',
          source: 'hereiam_v3',
          source_local_id: sourceLocalId,
          source_origin_device_id: row.origin_device_id,
          attachment_count_omitted: count,
        }],
      });
    }
    return {
      importDeviceId,
      messages,
      summary: {
        source_schema_version: Number(source.prepare('PRAGMA user_version').get().user_version),
        source_total: rows.length,
        total: messages.length,
        user: messages.filter((message) => message.sender === 'user').length,
        companion: messages.filter((message) => message.sender === 'companion').length,
        empty_messages_omitted: emptyMessagesOmitted,
        attachments_omitted: attachmentsOmitted,
      },
    };
  } finally {
    source.close();
  }
}

function existingCount(corePath, syncIds) {
  if (!existsSync(corePath)) return 0;
  const core = new DatabaseSync(corePath, { readOnly: true });
  try {
    const table = core.prepare(`
      SELECT 1 AS found FROM sqlite_master
      WHERE type = 'table' AND name = 'chat_messages'
    `).get();
    if (!table) return 0;
    const lookup = core.prepare('SELECT 1 AS found FROM chat_messages WHERE sync_id = ?');
    return syncIds.reduce((count, syncId) => count + (lookup.get(syncId)?.found === 1 ? 1 : 0), 0);
  } finally {
    core.close();
  }
}

function backupName() {
  return `i-core-before-v3-chat-${new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-')}.sqlite`;
}

export async function runImport(options) {
  const snapshot = readV3ChatSnapshot(options.source);
  const alreadyPresent = existingCount(
    options.core,
    snapshot.messages.map((message) => message.sync_id),
  );
  const result = {
    mode: options.apply ? 'apply' : 'dry-run',
    ...snapshot.summary,
    already_present: alreadyPresent,
    would_insert: snapshot.messages.length - alreadyPresent,
    import_device_id: snapshot.importDeviceId,
  };
  if (!options.apply) return result;

  mkdirSync(path.dirname(options.core), { recursive: true });
  let backupPath = null;
  if (existsSync(options.core)) {
    mkdirSync(options.backupDir, { recursive: true });
    backupPath = path.join(options.backupDir, backupName());
    const liveCore = new DatabaseSync(options.core, { readOnly: true });
    try {
      await backup(liveCore, backupPath);
    } finally {
      liveCore.close();
    }
  }

  const store = new ICoreStore(options.core);
  try {
    const imported = store.importMessages(snapshot.importDeviceId, snapshot.messages);
    result.inserted = imported.results.filter((item) => item.status === 'accepted').length;
    result.duplicates = imported.results.filter((item) => item.status === 'duplicate').length;
    result.backup = backupPath;
    return result;
  } finally {
    store.close();
  }
}

const isMain = process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);
if (isMain) {
  try {
    const options = parseArgs(process.argv.slice(2));
    console.log(JSON.stringify(await runImport(options), null, 2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
