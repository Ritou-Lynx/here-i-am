import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/memory_v3/services/dreaming_scheduler_service.dart';
import 'package:memex/data/services/event_bus_service.dart';
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
    this.coreNodeId,
    this.scheduleImportedChat,
    String? initialCursor,
  }) : _initialCursor = initialCursor;

  final AppDatabase db;
  final CoreSyncClient client;
  final String deviceId;
  final String? coreNodeId;

  /// Test seam for the post-import scheduler; never generates a chat reply.
  final Future<void> Function(AppDatabase db, String characterId)?
      scheduleImportedChat;

  /// Cursor returned by the pair response for this device. Used as the start
  /// of the change feed until the first successful pull persists a cursor.
  /// Clients never construct cursors themselves (CORE_API_V0).
  final String? _initialCursor;

  static const _bucket = 'core_sync';
  final _logger = Logger('CoreSyncEngine');

  String get _cursorKey => coreNodeId == null || coreNodeId!.isEmpty
      ? 'cursor.$deviceId'
      : 'cursor.$deviceId.$coreNodeId';

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
          ..where((t) => t.key.equals(_cursorKey) & t.bucket.equals(_bucket)))
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
    var resolved = 0;
    for (final result in response.results) {
      // Both outcomes mean the authority core durably owns this exact
      // immutable message. `duplicate` is the expected recovery path when
      // the first response was lost after the core committed the write.
      if (result.status == CoreSubmitStatus.accepted ||
          result.status == CoreSubmitStatus.duplicate) {
        await PersonaChatService.instance.markOutboxAccepted(result.syncId);
        resolved++;
      }
    }
    return resolved;
  }

  /// Pulls change events from [cursor] until the feed is exhausted, applying
  /// chat upserts locally, then acks and persists the final cursor.
  Future<void> _pullChanges({int pageLimit = 500}) async {
    var cursor = await loadCursor();
    // Apply at most a bounded number of pages per pass to keep each syncOnce
    // short; remaining pages arrive on the next pass via the persisted cursor.
    var pages = 0;
    while (pages < 12) {
      final page = await client.fetchChanges(cursor: cursor, limit: pageLimit);
      if (page.events.isEmpty) break;
      final importedCharacters = <String>{};
      for (final event in page.events) {
        if (event.kind == 'chat.message.upsert') {
          final characterId = await _applyChatUpsert(event);
          if (characterId != null) importedCharacters.add(characterId);
        }
        // Unknown kinds are ignored but the cursor still advances, so old
        // clients never get stuck on future event kinds.
      }
      for (final characterId in importedCharacters) {
        EventBusService.instance.emitEvent(
          PersonaChatMessageAddedMessage(characterId: characterId),
        );
        // Only schedule the existing Dreaming backlog. Imported messages must
        // never enter the local send/outbox or companion reply generation path.
        if (scheduleImportedChat case final schedule?) {
          await schedule(db, characterId);
        } else {
          await DreamingSchedulerService.scheduleEventDrivenBatchIfNeeded(
            db: db,
            characterId: characterId,
          );
        }
      }
      cursor = page.nextCursor;
      pages++;
      if (!page.hasMore) break;
    }
    await saveCursor(cursor);
    await client.acknowledgeCursor(cursor: cursor);
  }

  /// Inserts one user or companion row from a `chat.message.upsert` event.
  /// Companion history can come from the core or a restricted frontend device.
  /// Provenance is retained; both are history imports, never reply requests.
  Future<String?> _applyChatUpsert(CoreChangeEvent event) async {
    final payload = event.payload;
    final syncId = event.entityId;
    final sender = CoreMessageSender.parse(payload['sender']);
    if (sender == CoreMessageSender.system) return null;

    final content = payload['content']?.toString() ?? '';
    final characterId = payload['character_id']?.toString() ?? '';
    if (syncId.isEmpty || content.isEmpty || characterId.isEmpty) return null;

    final createdAtMs = payload['created_at_ms'];
    final timestamp = createdAtMs is int
        ? DateTime.fromMillisecondsSinceEpoch(createdAtMs)
        : DateTime.now();

    final existing = await (db.select(db.personaChatMessages)
          ..where((row) => row.syncId.equals(syncId)))
        .getSingleOrNull();
    if (existing != null) {
      // Enrich an own submission / earlier import with authoritative ordering.
      // Keep its content and local id; replay must not notify or schedule twice.
      if (existing.serverSequence == null || existing.createdAtMs == null) {
        await (db.update(db.personaChatMessages)
              ..where((row) => row.id.equals(existing.id)))
            .write(PersonaChatMessagesCompanion(
          createdAtMs: Value(timestamp.millisecondsSinceEpoch),
          serverSequence: Value(event.serverSequence),
        ));
      }
      return null;
    }

    final originDeviceId = payload['origin_device_id']?.toString() ?? deviceId;
    final messageType = payload['message_type']?.toString() ?? 'chat';

    await db.into(db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            syncId: Value(syncId),
            originDeviceId: Value(originDeviceId),
            characterId: characterId,
            isFromCharacter: sender == CoreMessageSender.companion,
            content: content,
            isRead: const Value(true),
            timestamp: timestamp,
            createdAtMs: Value(timestamp.millisecondsSinceEpoch),
            serverSequence: Value(event.serverSequence),
            messageType: Value(messageType),
          ),
        );
    _logger.info('CoreSyncEngine: applied chat.message.upsert $syncId');
    return messageType == 'chat' ? characterId : null;
  }

  /// One full sync pass. Returns the number of outbox messages submitted.
  /// Throws [CoreSyncException] on terminal errors for the caller to surface.
  Future<int> syncOnce({int submitLimit = 100}) async {
    final submitted = await _submitOutbox(limit: submitLimit);
    await _pullChanges();
    return submitted;
  }
}
