import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:memex/data/memory_v3/services/dreaming_scheduler_service.dart';
import 'package:memex/data/services/device_identity_service.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:uuid/uuid.dart';
import '../workbench_ai/workbench_desktop_user_message_store.dart';

/// Service for managing persona chat messages.
class PersonaChatService implements WorkbenchDesktopUserMessageStore {
  static const _uuid = Uuid();
  static const _outboxBucket = 'core_sync_outbox';
  static PersonaChatService? _instance;
  static PersonaChatService get instance {
    _instance ??= PersonaChatService._();
    return _instance!;
  }

  PersonaChatService._();

  AppDatabase get _db => AppDatabase.instance;

  Future<List<PersonaChatMessage>> getMessages(String characterId,
      {int limit = 50, int offset = 0}) async {
    return (_db.select(_db.personaChatMessages)
          ..where((t) => t.characterId.equals(characterId))
          ..orderBy([
            (t) => OrderingTerm.desc(t.timestamp),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(limit, offset: offset))
        .get();
  }

  Future<List<PersonaChatMessage>> searchMessages(
    String characterId,
    String query, {
    int limit = 50,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    return (_db.select(_db.personaChatMessages)
          ..where((t) =>
              t.characterId.equals(characterId) & t.content.like('%$trimmed%'))
          ..orderBy([
            (t) => OrderingTerm.desc(t.timestamp),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(limit))
        .get();
  }

  Future<PersonaChatMessage?> getMessageById(int messageId) {
    return (_db.select(_db.personaChatMessages)
          ..where((table) => table.id.equals(messageId)))
        .getSingleOrNull();
  }

  Future<PersonaChatMessage?> getMessageBySyncId(String syncId) {
    return (_db.select(_db.personaChatMessages)
          ..where((table) => table.syncId.equals(syncId)))
        .getSingleOrNull();
  }

  /// Pending chat submissions for a device, oldest-first by origin sequence.
  /// Consumed by the sync client to build a submit batch (CORE_API_V0).
  Future<List<SyncOutboxMessage>> pendingOutboxMessages(
    String originDeviceId, {
    int limit = 100,
    String? sender,
    String? characterId,
    int? fromCreatedAtMs,
    bool plainChatOnly = false,
  }) {
    return (_db.select(_db.syncOutboxMessages)
          ..where((t) =>
              t.originDeviceId.equals(originDeviceId) &
              (sender == null
                  ? const Constant(true)
                  : t.sender.equals(sender)) &
              (characterId == null
                  ? const Constant(true)
                  : t.characterId.equals(characterId)) &
              (fromCreatedAtMs == null
                  ? const Constant(true)
                  : t.createdAtMs.isBiggerOrEqualValue(fromCreatedAtMs)) &
              (plainChatOnly
                  ? t.messageType.equals('chat') &
                      t.content.equals('').not() &
                      (t.assetRefsJson.isNull() |
                          t.assetRefsJson.equals('[]')) &
                      existsQuery(_db.select(_db.personaChatMessages)
                        ..where((chat) =>
                            chat.syncId.equalsExp(t.syncId) &
                            (chat.attachmentsJson.isNull() |
                                chat.attachmentsJson.equals('[]'))))
                  : const Constant(true)))
          ..orderBy([(t) => OrderingTerm.asc(t.originSequence)])
          ..limit(limit))
        .get();
  }

  /// Removes an outbox row once the core accepts its sync_id. No-op when the
  /// message was already retracted while pending.
  Future<void> markOutboxAccepted(String syncId) async {
    await _db.transaction(() async {
      final queued = await (_db.select(_db.syncOutboxMessages)
            ..where((t) => t.syncId.equals(syncId)))
          .getSingleOrNull();
      if (queued?.sender == 'companion') {
        await _markCompanionEnqueued(syncId);
      }
      await (_db.delete(_db.syncOutboxMessages)
            ..where((t) => t.syncId.equals(syncId)))
          .go();
    });
  }

  /// Schema 62 defaults old PR10 outbox rows to user. PR10 actually sent
  /// those rows using their local chat role, so persist that same role once.
  /// Never regenerate identity, sequence, timestamp, content, or existing B3 sender.
  Future<void> repairLegacyCompanionOutboxSenders(String deviceId) async {
    await _db.transaction(() async {
      final rows = await _db.customSelect(
        "SELECT q.sync_id, q.origin_device_id, q.character_id, "
        "c.origin_device_id AS chat_origin, c.character_id AS chat_character "
        "FROM sync_outbox_messages q JOIN persona_chat_messages c ON c.sync_id=q.sync_id "
        "WHERE q.origin_device_id=? AND q.sender='user' AND c.is_from_character=1",
        variables: [Variable<String>(deviceId)],
        readsFrom: {_db.syncOutboxMessages, _db.personaChatMessages},
      ).get();
      for (final row in rows) {
        if (row.read<String>('origin_device_id') !=
                row.readNullable<String>('chat_origin') ||
            row.read<String>('character_id') !=
                row.read<String>('chat_character')) {
          throw StateError('Legacy outbox provenance mismatch');
        }
        final syncId = row.read<String>('sync_id');
        await (_db.update(_db.syncOutboxMessages)
              ..where((t) => t.syncId.equals(syncId) & t.sender.equals('user')))
            .write(
                const SyncOutboxMessagesCompanion(sender: Value('companion')));
        await _markCompanionEnqueued(syncId);
      }
    });
  }

  Future<int> countMessagesNewerThan(
    String characterId,
    PersonaChatMessage message,
  ) async {
    final countExp = _db.personaChatMessages.id.count();
    final row = await (_db.selectOnly(_db.personaChatMessages)
          ..addColumns([countExp])
          ..where(
            _db.personaChatMessages.characterId.equals(characterId) &
                (_db.personaChatMessages.timestamp
                        .isBiggerThanValue(message.timestamp) |
                    (_db.personaChatMessages.timestamp
                            .equals(message.timestamp) &
                        _db.personaChatMessages.id
                            .isBiggerThanValue(message.id))),
          ))
        .getSingle();
    return row.read(countExp) ?? 0;
  }

  @override
  Future<int> addUserMessage(
    String characterId,
    String content, {
    DateTime? timestamp,
    List<Map<String, String>>? attachments,
    bool appendTimeline = true,
  }) async {
    final createdAt = timestamp ?? DateTime.now();
    final syncId = _uuid.v4();
    final originDeviceId = await DeviceIdentityService.getOrCreate();
    final attachmentsJson = attachments != null && attachments.isNotEmpty
        ? jsonEncode(attachments)
        : null;

    // Chat row + sync outbox row commit atomically: every locally visible
    // user message has a durable pending copy for the authority core. The
    // outbox copy is removed once the core accepts sync_id (CORE_API_V0).
    late int id;
    await _db.transaction(() async {
      id = await _db.into(_db.personaChatMessages).insert(
            PersonaChatMessagesCompanion.insert(
              syncId: Value(syncId),
              originDeviceId: Value(originDeviceId),
              characterId: characterId,
              isFromCharacter: false,
              content: content,
              isRead: const Value(true),
              timestamp: createdAt,
              createdAtMs: Value(createdAt.millisecondsSinceEpoch),
              attachmentsJson: Value(attachmentsJson),
            ),
          );
      await _enqueueOutbox(
        syncId: syncId,
        originDeviceId: originDeviceId,
        characterId: characterId,
        content: content,
        createdAt: createdAt,
        messageType: 'chat',
        assetRefsJson: null,
      );
    });
    _notifyMessageAdded(characterId);
    _scheduleDreaming(characterId);
    _ignoreLegacyTimelineFlag(appendTimeline);
    return id;
  }

  /// Appends one pending sync submission with a strictly increasing
  /// per-device origin sequence. Must be called inside a transaction with the
  /// chat row write so the visible message and its outbox copy never diverge.
  ///
  /// The sequence counter lives in kvStore (not the outbox table): outbox rows
  /// are deleted once accepted, so max(outbox.origin_sequence) would restart
  /// at 1 and collide with the core's per-device uniqueness after a restart.
  Future<void> _enqueueOutbox({
    required String syncId,
    required String originDeviceId,
    required String characterId,
    required String content,
    required DateTime createdAt,
    required String messageType,
    String sender = 'user',
    String? assetRefsJson,
  }) async {
    final counterKey = 'outbox.max_sequence.$originDeviceId';
    final counterRow = await (_db.select(_db.kvStore)
          ..where(
              (t) => t.key.equals(counterKey) & t.bucket.equals(_outboxBucket)))
        .getSingleOrNull();
    final nextSequence = (int.tryParse(counterRow?.value ?? '') ?? 0) + 1;
    await _db.into(_db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: counterKey,
            value: Value('$nextSequence'),
            bucket: const Value(_outboxBucket),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
    await _db.into(_db.syncOutboxMessages).insert(
          SyncOutboxMessagesCompanion.insert(
            syncId: syncId,
            originDeviceId: originDeviceId,
            originSequence: nextSequence,
            characterId: characterId,
            content: content,
            createdAtMs: createdAt.millisecondsSinceEpoch,
            messageType: Value(messageType),
            sender: Value(sender),
            assetRefsJson: Value(assetRefsJson),
          ),
        );
    if (sender == 'companion') await _markCompanionEnqueued(syncId);
  }

  // Kept after acceptance: deleting an outbox copy must never allocate a second
  // origin sequence for this same immutable reply while awaiting its feed echo.
  Future<void> _markCompanionEnqueued(String syncId) async {
    await _db.into(_db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: 'companion.enqueued.$syncId',
            value: const Value('1'),
            bucket: const Value(_outboxBucket),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  /// Backfill only this installation's authorized plain-chat replies.
  /// Imported rows keep their original origin/server sequence and are excluded.
  Future<int> enqueueLocalCompanionBacklog({
    required String originDeviceId,
    required String characterId,
    required int fromCreatedAtMs,
  }) async {
    return _db.transaction(() async {
      final rows = await (_db.select(_db.personaChatMessages)
            ..where((t) =>
                t.originDeviceId.equals(originDeviceId) &
                t.characterId.equals(characterId) &
                t.isFromCharacter.equals(true) &
                t.messageType.equals('chat') &
                t.content.equals('').not() &
                t.syncId.isNotNull() &
                t.syncId.equals('').not() &
                t.serverSequence.isNull() &
                (t.attachmentsJson.isNull() | t.attachmentsJson.equals('[]')) &
                coalesce([
                  t.createdAtMs,
                  t.timestamp.unixepoch * const Constant(1000)
                ]).isBiggerOrEqualValue(fromCreatedAtMs) &
                notExistsQuery(_db.select(_db.kvStore)
                  ..where((marker) =>
                      marker.bucket.equals(_outboxBucket) &
                      marker.key.equalsExp(
                          const Constant('companion.enqueued.') + t.syncId))) &
                notExistsQuery(_db.select(_db.syncOutboxMessages)
                  ..where((queued) => queued.syncId.equalsExp(t.syncId))))
            ..orderBy([
              (t) => OrderingTerm.asc(coalesce([
                    t.createdAtMs,
                    t.timestamp.unixepoch * const Constant(1000)
                  ])),
              (t) => OrderingTerm.asc(t.id),
            ])
            ..limit(100))
          .get();
      var added = 0;
      for (final row in rows) {
        final syncId = row.syncId!;
        await _enqueueOutbox(
          syncId: syncId,
          originDeviceId: originDeviceId,
          characterId: characterId,
          content: row.content,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
              row.createdAtMs ?? row.timestamp.millisecondsSinceEpoch),
          messageType: 'chat',
          sender: 'companion',
        );
        added++;
      }
      return added;
    });
  }

  Future<void> appendUserMessageTimeline(
      String characterId, int messageId) async {
    // Legacy character_memory timeline is frozen. Dreaming/Memory V3 owns
    // extraction and recall, so chat persistence must not create side records.
  }

  Future<int> deleteMessage(String characterId, int messageId) async {
    final message = await getMessageById(messageId);
    final deleted = await (_db.delete(_db.personaChatMessages)
          ..where((t) =>
              t.id.equals(messageId) & t.characterId.equals(characterId)))
        .go();
    if (deleted > 0) {
      await _dropOutboxIfPending(message?.syncId);
      _notifyMessageAdded(characterId);
    }
    return deleted;
  }

  Future<int> retractUserMessage(String characterId, int messageId) async {
    final message = await getMessageById(messageId);
    final deleted = await (_db.delete(_db.personaChatMessages)
          ..where((t) =>
              t.id.equals(messageId) &
              t.characterId.equals(characterId) &
              t.isFromCharacter.equals(false)))
        .go();
    if (deleted > 0) {
      await _dropOutboxIfPending(message?.syncId);
      _notifyMessageAdded(characterId);
    }
    return deleted;
  }

  /// Removes a pending outbox copy when its chat row is deleted/retracted.
  /// A message that never reached the core needs no retraction sync — the
  /// outbox copy simply disappears. Messages already accepted by the core are
  /// never in the outbox, so nothing to do there either.
  Future<void> _dropOutboxIfPending(String? syncId) async {
    if (syncId == null || syncId.isEmpty) return;
    await (_db.delete(_db.syncOutboxMessages)
          ..where((t) => t.syncId.equals(syncId)))
        .go();
  }

  /// Owner-controlled local enqueue gate. It does not grant server permission.
  /// Only the registered phone's one primary character may use this queue.
  Future<void> configureCompanionOutbox({required String deviceId,
      required String characterId, required bool enabled}) async {
    await _db.into(_db.kvStore).insertOnConflictUpdate(KvStoreCompanion.insert(
      key: 'phone_companion_outbox.$deviceId',
      bucket: const Value(_outboxBucket),
      value: Value(enabled ? characterId : ''),
    ));
  }

  Future<String?> configuredCompanionOutboxCharacter(String deviceId) async {
    final row = await (_db.select(_db.kvStore)
          ..where((t) =>
              t.key.equals('phone_companion_outbox.$deviceId') &
              t.bucket.equals(_outboxBucket)))
        .getSingleOrNull();
    final value = row?.value;
    return value == null || value.isEmpty ? null : value;
  }

  Future<bool> companionOutboxEnabled(
          String deviceId, String characterId) async =>
      characterId.isNotEmpty &&
      await configuredCompanionOutboxCharacter(deviceId) == characterId;

  Future<int> addCharacterMessage(
    String characterId,
    String content, {
    String? factId,
    bool isRead = false,
    DateTime? timestamp,
    List<Map<String, dynamic>>? addenda,
  }) async {
    final createdAt = timestamp ?? DateTime.now();
    final syncId = _uuid.v4();
    final originDeviceId = await DeviceIdentityService.getOrCreate();
    final attachmentsJson =
        (addenda != null && addenda.isNotEmpty) ? jsonEncode(addenda) : null;
    late int id;
    await _db.transaction(() async {
      id = await _db.into(_db.personaChatMessages).insert(
            PersonaChatMessagesCompanion.insert(
              syncId: Value(syncId),
              originDeviceId: Value(originDeviceId),
              characterId: characterId,
              isFromCharacter: true,
              content: content,
              factId: Value(factId),
              isRead: Value(isRead),
              timestamp: createdAt,
              createdAtMs: Value(createdAt.millisecondsSinceEpoch),
              attachmentsJson: Value(attachmentsJson),
            ),
          );
      if (attachmentsJson == null &&
          content.isNotEmpty &&
          await companionOutboxEnabled(originDeviceId, characterId)) {
        await _enqueueOutbox(
            syncId: syncId,
            originDeviceId: originDeviceId,
            characterId: characterId,
            content: content,
            createdAt: createdAt,
            messageType: 'chat',
            sender: 'companion');
      }
    });
    _notifyMessageAdded(characterId);
    _scheduleDreaming(characterId);
    return id;
  }

  /// Writes per-image vision analysis text back into the attachmentsJson
  /// so the Record Organizer can reuse it later without re-running the
  /// vision model. Each [analyses][i] corresponds to the i-th attachment.
  Future<void> enrichAttachmentsWithAnalysis(
    int messageId,
    List<String> analyses,
  ) async {
    if (analyses.isEmpty) return;
    try {
      final message = await (_db.select(_db.personaChatMessages)
            ..where((t) => t.id.equals(messageId)))
          .getSingleOrNull();
      final raw = message?.attachmentsJson;
      if (raw == null || raw.trim().isEmpty) return;
      final attachments = jsonDecode(raw) as List;
      if (attachments.isEmpty) return;
      var dirty = false;
      for (var i = 0; i < attachments.length && i < analyses.length; i++) {
        final att = attachments[i];
        if (att is! Map || analyses[i].trim().isEmpty) continue;
        att['analysis'] = analyses[i].trim();
        dirty = true;
      }
      if (!dirty) return;
      await (_db.update(_db.personaChatMessages)
            ..where((t) => t.id.equals(messageId)))
          .write(PersonaChatMessagesCompanion(
        attachmentsJson: Value(jsonEncode(attachments)),
      ));
    } catch (e) {
      // Best-effort; analysis can still run inline during record.
    }
  }

  /// Replaces the addenda list on an existing message. Used by features that
  /// emit a message first (to get a real messageId) and then patch in
  /// addenda referencing the just-created entity (e.g. ReadingCaptureService).
  ///
  /// Pass `addenda: null` or an empty list to clear addenda.
  Future<void> updateMessageAddenda(
    int messageId, {
    List<Map<String, dynamic>>? addenda,
  }) async {
    final attachmentsJson =
        (addenda != null && addenda.isNotEmpty) ? jsonEncode(addenda) : null;
    await (_db.update(_db.personaChatMessages)
          ..where((t) => t.id.equals(messageId)))
        .write(
      PersonaChatMessagesCompanion(
        attachmentsJson: Value(attachmentsJson),
      ),
    );
    // Notify the open chat screen to repaint that bubble with the new addendum.
    final row = await (_db.select(_db.personaChatMessages)
          ..where((t) => t.id.equals(messageId)))
        .getSingleOrNull();
    if (row != null) {
      _notifyMessageAdded(row.characterId);
    }
  }

  /// Persists a Dev Room Accept / Discard / Leave decision onto the matching
  /// `dev_session` addendum carried by [messageId].
  ///
  /// The Dev Session card renders its action row from addendum data in
  /// attachmentsJson. Without this, the decision lives only in widget State
  /// and is lost every time the chat refreshes (every 2s) or the user
  /// navigates away and back, so the buttons would reappear and the user
  /// would think the click had no effect. We stamp `decision` on the
  /// addendum matching [runId] (defensive: a message could carry multiple
  /// dev_session addenda) and notify the chat to repaint.
  ///
  /// When [accepted] is false (Bridge rejected the decision, e.g.
  /// `no_worktree`), [resultText] is stored so the card can show the reason
  /// and stay collapsed instead of re-offering the buttons. Network failures
  /// (DioException before the Bridge responds) should NOT call this — they
  /// leave the row actionable so the user can retry once connectivity is
  /// restored.
  Future<void> persistDevSessionDecision({
    required int messageId,
    required String runId,
    required String decision,
    bool accepted = true,
    String? resultText,
  }) async {
    try {
      final row = await (_db.select(_db.personaChatMessages)
            ..where((t) => t.id.equals(messageId)))
          .getSingleOrNull();
      final raw = row?.attachmentsJson;
      if (raw == null || raw.trim().isEmpty) return;
      final attachments = jsonDecode(raw) as List;
      var dirty = false;
      for (final att in attachments) {
        if (att is! Map) continue;
        if (att['type'] != 'dev_session') continue;
        if (att['runId'] != runId) continue;
        att['decision'] = decision;
        att['decisionAccepted'] = accepted;
        if (resultText != null && resultText.isNotEmpty) {
          att['decisionResult'] = resultText;
        }
        dirty = true;
        break;
      }
      if (!dirty) return;
      await (_db.update(_db.personaChatMessages)
            ..where((t) => t.id.equals(messageId)))
          .write(PersonaChatMessagesCompanion(
        attachmentsJson: Value(jsonEncode(attachments)),
      ));
      if (row != null) {
        _notifyMessageAdded(row.characterId);
      }
    } catch (_) {
      // Best-effort; the decision is already sent to the bridge and the
      // in-memory state is the source of truth for the current session.
    }
  }

  /// Adds a narrative/action message from the character (e.g. *leans closer*).
  /// Rendered differently in the UI — no bubble, italic, centered.
  Future<int> addActionMessage(String characterId, String content,
      {String? factId, bool isRead = false, DateTime? timestamp}) async {
    final createdAt = timestamp ?? DateTime.now();
    final syncId = _uuid.v4();
    final originDeviceId = await DeviceIdentityService.getOrCreate();
    final id = await _db.into(_db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            syncId: Value(syncId),
            originDeviceId: Value(originDeviceId),
            characterId: characterId,
            isFromCharacter: true,
            content: content,
            factId: Value(factId),
            isRead: Value(isRead),
            timestamp: createdAt,
            messageType: const Value('action'),
          ),
        );
    _notifyMessageAdded(characterId);
    return id;
  }

  /// Persists a structured workbench action in the existing chat stream.
  /// The projection remains product-owned addendum data; it is not User-truth.
  Future<int> addWorkbenchActionMessage(
    String characterId,
    String content,
    Map<String, dynamic> projection, {
    bool isRead = true,
    DateTime? timestamp,
  }) async {
    final createdAt = timestamp ?? DateTime.now();
    final syncId = _uuid.v4();
    final originDeviceId = await DeviceIdentityService.getOrCreate();
    final id = await _db.into(_db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            syncId: Value(syncId),
            originDeviceId: Value(originDeviceId),
            characterId: characterId,
            isFromCharacter: true,
            content: content,
            isRead: Value(isRead),
            timestamp: createdAt,
            messageType: const Value('action'),
            attachmentsJson: Value(jsonEncode([
              {'type': 'workbench_action', 'action': projection},
            ])),
          ),
        );
    _notifyMessageAdded(characterId);
    return id;
  }

  Future<void> updateWorkbenchActionMessage({
    required int messageId,
    required String content,
    required Map<String, dynamic> projection,
  }) async {
    final affectedRows = await (_db.update(_db.personaChatMessages)
          ..where((table) => table.id.equals(messageId)))
        .write(
      PersonaChatMessagesCompanion(
        content: Value(content),
        attachmentsJson: Value(jsonEncode([
          {'type': 'workbench_action', 'action': projection},
        ])),
      ),
    );
    if (affectedRows != 1) {
      throw StateError(
        'Workbench action terminal update must affect exactly one row; '
        'affected $affectedRows for message $messageId',
      );
    }
    final row = await getMessageById(messageId);
    if (row != null) _notifyMessageAdded(row.characterId);
  }

  void _ignoreLegacyTimelineFlag(bool appendTimeline) {
    if (!appendTimeline) return;
    // Kept for API compatibility with older callers while the old character
    // memory timeline is intentionally disconnected from chat.
  }

  Stream<int> watchUnreadCount(String characterId) {
    final query = _db.selectOnly(_db.personaChatMessages)
      ..addColumns([_db.personaChatMessages.id.count()])
      ..where(_db.personaChatMessages.characterId.equals(characterId) &
          _db.personaChatMessages.isFromCharacter.equals(true) &
          _db.personaChatMessages.isRead.equals(false));
    return query
        .watchSingle()
        .map((row) => row.read(_db.personaChatMessages.id.count()) ?? 0);
  }

  Stream<int> watchTotalUnreadCount() {
    final query = _db.selectOnly(_db.personaChatMessages)
      ..addColumns([_db.personaChatMessages.id.count()])
      ..where(_db.personaChatMessages.isFromCharacter.equals(true) &
          _db.personaChatMessages.isRead.equals(false));
    return query
        .watchSingle()
        .map((row) => row.read(_db.personaChatMessages.id.count()) ?? 0);
  }

  Future<int> markAllRead(String characterId) async {
    return (_db.update(_db.personaChatMessages)
          ..where((t) =>
              t.characterId.equals(characterId) &
              t.isFromCharacter.equals(true) &
              t.isRead.equals(false)))
        .write(const PersonaChatMessagesCompanion(isRead: Value(true)));
  }

  Future<PersonaChatMessage?> getLastMessage(String characterId) async {
    final results = await (_db.select(_db.personaChatMessages)
          ..where((t) => t.characterId.equals(characterId))
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
          ..limit(1))
        .get();
    return results.isEmpty ? null : results.first;
  }

  Future<int> clearMessages(String characterId) async {
    return (_db.delete(_db.personaChatMessages)
          ..where((t) => t.characterId.equals(characterId)))
        .go();
  }

  void _notifyMessageAdded(String characterId) {
    EventBusService.instance.emitEvent(
      PersonaChatMessageAddedMessage(characterId: characterId),
    );
  }

  void _scheduleDreaming(String characterId) {
    unawaited(
      DreamingSchedulerService.scheduleEventDrivenBatchIfNeeded(
        db: _db,
        characterId: characterId,
      ),
    );
  }
}
