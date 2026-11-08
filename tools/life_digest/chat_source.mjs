// Chat messages of one time range, read-only, under the same sharing policy as the i MCP read model.
// The MCP runs the frozen read model (SOURCE_PREFIX in i_remote_mcp/chatgpt_candidate.mjs); it has no range query, so the
// filter below mirrors its typeFilter line for line. chat_source.test.mjs checks parity against its recentMessages.
import { DatabaseSync } from 'node:sqlite';
import { hashMessageContent, loadPolicy } from '../i_core/test_fixtures/release_schema6/mcp_reader/legacy/i_memory/i_memory_read.mjs';

export function readChatRange({ coreDbPath, policyPath, fromMs, toMs, limit = 2000 }) {
  const policy = loadPolicy(policyPath);
  const core = new DatabaseSync(coreDbPath, { readOnly: true });
  try {
    core.function('i_message_hash', { deterministic: true }, hashMessageContent);
    const privateTypeList = policy.messages.privateMessageTypes;
    const privateMessageKeywords = policy.messages.privateKeywords;
    const privateMessageIds = policy.messages.privateMessageIds;
    const shareableMessageIds = policy.messages.shareableMessageIds;
    const shareableMessageHashes = policy.messages.shareableMessageHashes;
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
    const allowlistClauses = [
      shareableMessageIds === null ? null : 'sync_id IN (SELECT value FROM json_each(?))',
      shareableMessageHashes === null ? null
        : '(sync_id, i_message_hash(content)) IN (SELECT key, value FROM json_each(?))',
    ].filter(Boolean);
    let allowlistFilter = '';
    if (allowlistActive) {
      const automatic = [];
      if (autoShareOriginIds.length) automatic.push('origin_device_id IN (SELECT value FROM json_each(?))');
      if (autoShareDeviceRules.length) {
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
    const typeFilter = [
      privateTypeList.length ? `AND message_type NOT IN (${privateTypeList.map(() => '?').join(', ')})` : '',
      ...privateMessageKeywords.map(() => 'AND instr(lower(content), ?) = 0'),
      'AND sync_id NOT IN (SELECT value FROM json_each(?))',
      allowlistFilter,
    ].join(' ');
    const id = policy.primaryCharacterId;
    if (!policy.messages.shareableCharacterIds.has(id)) return { messages: [], primaryCharacterId: id };
    const rows = core.prepare(`
      SELECT sync_id, sender, content, created_at_ms, message_type
      FROM chat_messages
      WHERE character_id = ? ${typeFilter} AND created_at_ms >= ? AND created_at_ms < ?
      ORDER BY created_at_ms ASC, server_sequence ASC
      LIMIT ?
    `).all(id, ...filterParams, fromMs, toMs, limit);
    return { primaryCharacterId: id, messages: rows.filter(row => typeof row.content === 'string' && row.content.trim())
      .map(row => ({ id: row.sync_id, sender: row.sender, content: row.content, at: Number(row.created_at_ms), type: row.message_type })) };
  } finally { core.close(); }
}
