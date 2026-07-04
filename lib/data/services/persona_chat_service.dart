import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/db/app_database.dart';

/// Service for managing persona chat messages.
class PersonaChatService {
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

  Future<int> addUserMessage(
    String characterId,
    String content, {
    DateTime? timestamp,
    List<Map<String, String>>? attachments,
    bool appendTimeline = true,
  }) async {
    final createdAt = timestamp ?? DateTime.now();
    final attachmentsJson = attachments != null && attachments.isNotEmpty
        ? jsonEncode(attachments)
        : null;
    final id = await _db.into(_db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            characterId: characterId,
            isFromCharacter: false,
            content: content,
            isRead: const Value(true),
            timestamp: createdAt,
            attachmentsJson: Value(attachmentsJson),
          ),
        );
    _notifyMessageAdded(characterId);
    _ignoreLegacyTimelineFlag(appendTimeline);
    return id;
  }

  Future<void> appendUserMessageTimeline(
      String characterId, int messageId) async {
    // Legacy character_memory timeline is frozen. Dreaming/Memory V3 owns
    // extraction and recall, so chat persistence must not create side records.
  }

  Future<int> retractUserMessage(String characterId, int messageId) async {
    final deleted = await (_db.delete(_db.personaChatMessages)
          ..where((t) =>
              t.id.equals(messageId) &
              t.characterId.equals(characterId) &
              t.isFromCharacter.equals(false)))
        .go();
    if (deleted > 0) {
      _notifyMessageAdded(characterId);
    }
    return deleted;
  }

  Future<int> addCharacterMessage(
    String characterId,
    String content, {
    String? factId,
    bool isRead = false,
    DateTime? timestamp,
    List<Map<String, dynamic>>? addenda,
  }) async {
    final createdAt = timestamp ?? DateTime.now();
    final attachmentsJson =
        (addenda != null && addenda.isNotEmpty) ? jsonEncode(addenda) : null;
    final id = await _db.into(_db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            characterId: characterId,
            isFromCharacter: true,
            content: content,
            factId: Value(factId),
            isRead: Value(isRead),
            timestamp: createdAt,
            attachmentsJson: Value(attachmentsJson),
          ),
        );
    _notifyMessageAdded(characterId);
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

  /// Adds a narrative/action message from the character (e.g. *leans closer*).
  /// Rendered differently in the UI — no bubble, italic, centered.
  Future<int> addActionMessage(String characterId, String content,
      {String? factId, bool isRead = false, DateTime? timestamp}) async {
    final createdAt = timestamp ?? DateTime.now();
    final id = await _db.into(_db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
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
}
