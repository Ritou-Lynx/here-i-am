import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/services/sync/core_sync_client.dart';
import 'package:memex/data/services/sync/core_sync_protocol.dart';
import 'package:memex/db/app_database.dart';

/// One-shot sync loop against the i core (CORE_API_V0).
///
/// Each [syncOnce] pass: submits pending outbox messages, pulls the change
/// feed from the persisted cursor, applies `chat.message.upsert` events to the
/// local chat table (by stable sync_id, never duplicating bubbles), then acks
/// the cursor. Cursor and device token persist in kvStore under the
/// `core_sync` bucket, per device.
///
/// Only retryable errors are retried by the caller; auth / protocol / conflict
/// errors surface immediately as [CoreSyncException].
class CoreSyncEngine {
  CoreSyncEngine({
    required this.db,
    required this.client,
    required this.deviceId,
    String? initialCursor,
  }) : _initialCursor = initialCursor;

  final AppDatabase db;
  final CoreSyncClient client;
  final String deviceId;

  /// Cursor returned by the pair response for this device. Used as the start
  /// of the change feed until the first successful pull persists a cursor.
  /// Clients never construct cursors themselves (CORE_API_V0).
  final String? _initialCursor;

  static const _bucket = 'core_sync';
  final _logger = Logger('CoreSyncEngine');

  String get _cursorKey => 'cursor.$deviceId';

  /// Persists an opaque cursor (never parsed or constructed client-side).
  Future<void> saveCursor(String cursor) async {
    await db.into(db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: _cursorKey,
            value: Value(cursor),
            bucket: const Value(_bucket),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  /// Reads the last persisted cursor; falls back to the pair-time
  /// [initialCursor] when this device has never pulled successfully.
  Future<String> loadCursor() async {
    final row = await (db.select(db.kvStore)
          ..where((t) =>
              t.key.equals(_cursorKey) & t.bucket.equals(_bucket)))
        .getSingleOrNull();
    return row?.value ?? _initialCursor ?? '';
  }

  /// Submits up to [limit] oldest pending outbox rows, dropping each from the
  /// outbox once the core accepts its sync_id.
  Future<int> _submitOutbox({int limit = 100}) async {
    final pending = await PersonaChatService.instance
        .pendingOutboxMessages(deviceId, limit: limit);
    if (pending.isEmpty) return 0;

    final request = CoreChatSubmitRequest(
      deviceId: deviceId,
      messages: [
        for (final row in pending)
          CoreChatMessageWire(
            syncId: row.syncId,
            originDeviceId: row.originDeviceId,
            originSequence: row.originSequence,
            characterId: row.characterId,
            sender: CoreMessageSender.user,
            content: row.content,
            createdAtMs: row.createdAtMs,
            messageType: row.messageType,
          ),
      ],
    );
    final response = await client.submitMessages(request);
    var accepted = 0;
    for (final result in response.results) {
      if (result.status == CoreSubmitStatus.accepted) {
        await PersonaChatService.instance.markOutboxAccepted(result.syncId);
        accepted++;
      }
    }
    return accepted;
  }

  /// Pulls change events from [cursor] until the feed is exhausted, applying
  /// chat upserts locally, then acks and persists the final cursor.
  Future<void> _pullChanges({int pageLimit = 100}) async {
    var cursor = await loadCursor();
    // Apply at most a bounded number of pages per pass to keep each syncOnce
    // short; remaining pages arrive on the next pass via the persisted cursor.
    var pages = 0;
    while (pages < 10) {
      final page = await client.fetchChanges(cursor: cursor, limit: pageLimit);
      if (page.events.isEmpty) break;
      for (final event in page.events) {
        if (event.kind == 'chat.message.upsert') {
          await _applyChatUpsert(event);
        }
        // Unknown kinds are ignored but the cursor still advances, so old
        // clients never get stuck on future event kinds.
      }
      cursor = page.nextCursor;
      pages++;
      if (!page.hasMore) break;
    }
    await saveCursor(cursor);
    await client.acknowledgeCursor(cursor: cursor);
  }

  /// Inserts or updates one chat row from a `chat.message.upsert` event.
  /// Only `sender=user` messages are stored locally — character replies are
  /// core-owned and v0 does not generate them yet.
  Future<void> _applyChatUpsert(CoreChangeEvent event) async {
    final payload = event.payload;
    final syncId = event.entityId;
    final sender = CoreMessageSender.parse(payload['sender']);
    if (sender != CoreMessageSender.user) return;

    final content = payload['content']?.toString() ?? '';
    final characterId = payload['character_id']?.toString() ?? '';
    if (syncId.isEmpty || content.isEmpty || characterId.isEmpty) return;

    final createdAtMs = payload['created_at_ms'];
    final timestamp = createdAtMs is int
        ? DateTime.fromMillisecondsSinceEpoch(createdAtMs)
        : DateTime.now();

    final existing =
        await PersonaChatService.instance.getMessageBySyncId(syncId);
    if (existing != null) {
      // Already local (own submission or earlier pull); never duplicate.
      return;
    }

    final originDeviceId =
        payload['origin_device_id']?.toString() ?? deviceId;
    final messageType = payload['message_type']?.toString() ?? 'chat';

    await db.into(db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            syncId: Value(syncId),
            originDeviceId: Value(originDeviceId),
            characterId: characterId,
            isFromCharacter: false,
            content: content,
            isRead: const Value(true),
            timestamp: timestamp,
            messageType: Value(messageType),
          ),
        );
    _logger.info('CoreSyncEngine: applied chat.message.upsert $syncId');
  }

  /// One full sync pass. Returns the number of outbox messages submitted.
  /// Throws [CoreSyncException] on terminal errors for the caller to surface.
  Future<int> syncOnce({int submitLimit = 100}) async {
    final submitted = await _submitOutbox(limit: submitLimit);
    await _pullChanges();
    return submitted;
  }
}
