import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/drift.dart';
import 'package:memex/data/services/sqlite_retry.dart';
import 'package:memex/db/app_database.dart';

const _bucket = 'companion_call';
const _keyCharacterId = 'pending_character_id';
const _keyOpening = 'pending_opening';
const _keyNotified = 'pending_notified';

/// Reads the pending opening message (and characterId) from KVStore.
/// Does NOT delete; caller decides when to clear.
Future<({String characterId, String opening})?> readPendingCall() async {
  if (!AppDatabase.isInitialized) return null;
  final db = AppDatabase.instance;
  final rows = await (db.select(db.kvStore)
        ..where((kv) => kv.bucket.equals(_bucket)))
      .get();
  if (rows.isEmpty) return null;

  String? characterId;
  String? opening;
  for (final row in rows) {
    if (row.key == _keyCharacterId) characterId = row.value;
    if (row.key == _keyOpening) opening = row.value;
  }
  if (characterId == null) return null;
  return (characterId: characterId, opening: opening ?? '');
}

/// Check if a call notification has already been sent for the current pending call.
Future<bool> isPendingCallAlreadyNotified() async {
  if (!AppDatabase.isInitialized) return false;
  final db = AppDatabase.instance;
  final row = await (db.select(db.kvStore)
        ..where(
            (kv) => kv.bucket.equals(_bucket) & kv.key.equals(_keyNotified)))
      .getSingleOrNull();
  if (row == null) return false;
  final sentAt = int.tryParse(row.value ?? '');
  if (sentAt == null) return false;
  // Treat notifications older than 10 minutes as expired (allow re-notify).
  final age = DateTime.now().millisecondsSinceEpoch ~/ 1000 - sentAt;
  return age < 600;
}

/// Mark that a call notification has been sent so we don't re-notify.
Future<void> markPendingCallNotified() async {
  if (!AppDatabase.isInitialized) return;
  final db = AppDatabase.instance;
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  await retryOnSqliteLocked(() async {
    await db.into(db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: _keyNotified,
            bucket: const Value(_bucket),
            value: Value(now.toString()),
            updatedAt: Value(now),
          ),
        );
  });
}

/// Clear all pending call state (called when the user enters chat voice mode).
Future<void> clearPendingCall({String? characterId}) async {
  if (!AppDatabase.isInitialized) return;
  if (characterId != null) {
    final pending = await readPendingCall();
    if (pending?.characterId != characterId) return;
  }
  final db = AppDatabase.instance;
  await retryOnSqliteLocked(() async {
    await (db.delete(db.kvStore)..where((kv) => kv.bucket.equals(_bucket)))
        .go();
  });
}

Future<void> queuePendingCall({
  required String characterId,
  required String openingMessage,
}) async {
  final db = AppDatabase.instance;
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // A newly queued call must ring even if another call was notified in the
  // last ten minutes.
  await retryOnSqliteLocked(() async {
    await db.transaction(() async {
      await (db.delete(db.kvStore)
            ..where((kv) =>
                kv.bucket.equals(_bucket) & kv.key.equals(_keyNotified)))
          .go();
      await db.into(db.kvStore).insertOnConflictUpdate(
            KvStoreCompanion.insert(
              key: _keyCharacterId,
              bucket: const Value(_bucket),
              value: Value(characterId),
              updatedAt: Value(now),
            ),
          );
      await db.into(db.kvStore).insertOnConflictUpdate(
            KvStoreCompanion.insert(
              key: _keyOpening,
              bucket: const Value(_bucket),
              value: Value(openingMessage),
              updatedAt: Value(now),
            ),
          );
    });
  });
}

typedef InitiateCallPolicy = Future<String?> Function();

/// Agent tool: initiate a voice call to the user.
Tool buildInitiateCallTool({
  required String characterId,
  InitiateCallPolicy? beforeQueue,
}) {
  return Tool(
    name: 'initiate_voice_call',
    description: '''Initiate a voice call to the user.

Use this when you genuinely want to TALK, not just text. A call is more
personal and immediate. Good reasons:
- Something emotional or important that deserves a real conversation
- The user seems lonely or would benefit from hearing your voice
- You want a real exchange rather than a one-way notification

You will say opening_message first when the user picks up.
Keep it natural and open-ended; it is the first thing they hear.''',
    parameters: {
      'type': 'object',
      'properties': {
        'opening_message': {
          'type': 'string',
          'description':
              'What you say when the user picks up. Start with their name or '
                  'a warm greeting. Conversational, not scripted. 1-2 sentences max.',
        },
      },
      'required': ['opening_message'],
    },
    executable: (String openingMessage) async {
      if (beforeQueue != null) {
        final blockedReason = await beforeQueue();
        if (blockedReason != null && blockedReason.trim().isNotEmpty) {
          return 'Call blocked: $blockedReason';
        }
      }
      await queuePendingCall(
        characterId: characterId,
        openingMessage: openingMessage,
      );

      // ignore: avoid_print
      print('[initiate_voice_call] queued for $characterId: "$openingMessage"');
      return 'Call queued. System will notify the user.';
    },
  );
}
