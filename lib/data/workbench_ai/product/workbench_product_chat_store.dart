import 'package:drift/drift.dart';
import 'package:memex/data/workbench_ai/workbench_desktop_user_message_store.dart';
import 'package:memex/db/app_database.dart';

/// Isolated persistence for the product-chat candidate.
///
/// The caller owns [database].  This store deliberately only touches the chat
/// table: it never creates a device identity, sync outbox item, or scheduler
/// work.  The candidate root, rather than this presentation-level store,
/// owns database closure.
class WorkbenchProductChatStore implements WorkbenchDesktopUserMessageStore {
  static const maximumSupportedInputLength = 8000;

  WorkbenchProductChatStore({
    required AppDatabase database,
    required this.conversationId,
    this.characterId = 'i',
    this.maximumInputLength = maximumSupportedInputLength,
  }) : _database = database {
    if (conversationId.trim().isEmpty) {
      throw ArgumentError.value(
          conversationId, 'conversationId', 'is required');
    }
    if (characterId != 'i') {
      throw ArgumentError.value(characterId, 'characterId', 'must be i');
    }
    if (maximumInputLength < 1 ||
        maximumInputLength > maximumSupportedInputLength) {
      throw ArgumentError.value(
        maximumInputLength,
        'maximumInputLength',
        'must be between 1 and $maximumSupportedInputLength',
      );
    }
  }

  final AppDatabase _database;
  final String conversationId;
  final String characterId;
  final int maximumInputLength;

  Future<List<PersonaChatMessage>> getMessages({int limit = 100}) =>
      (_database.select(_database.personaChatMessages)
            ..where((row) => row.characterId.equals(characterId))
            ..orderBy([
              (row) => OrderingTerm.desc(row.timestamp),
              (row) => OrderingTerm.desc(row.id),
            ])
            ..limit(limit))
          .get();

  Stream<List<PersonaChatMessage>> watchMessages({int limit = 100}) =>
      (_database.select(_database.personaChatMessages)
            ..where((row) => row.characterId.equals(characterId))
            ..orderBy([
              (row) => OrderingTerm.desc(row.timestamp),
              (row) => OrderingTerm.desc(row.id),
            ])
            ..limit(limit))
          .watch();

  @override
  Future<int> addUserMessage(
    String suppliedCharacterId,
    String content, {
    DateTime? timestamp,
    List<Map<String, String>>? attachments,
    bool appendTimeline = true,
  }) {
    _validateCharacter(suppliedCharacterId);
    _validateInput(content, attachments);
    return _database.into(_database.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            characterId: characterId,
            isFromCharacter: false,
            content: content,
            isRead: const Value(true),
            timestamp: timestamp ?? DateTime.now(),
          ),
        );
  }

  Future<int> addCharacterMessage(
    String suppliedCharacterId,
    String content, {
    bool isRead = true,
    DateTime? timestamp,
  }) {
    _validateCharacter(suppliedCharacterId);
    if (content.trim().isEmpty) {
      throw ArgumentError.value(content, 'content', 'must not be blank');
    }
    return _database.into(_database.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            characterId: characterId,
            isFromCharacter: true,
            content: content,
            isRead: Value(isRead),
            timestamp: timestamp ?? DateTime.now(),
          ),
        );
  }

  void _validateCharacter(String suppliedCharacterId) {
    if (suppliedCharacterId != characterId) {
      throw ArgumentError.value(
        suppliedCharacterId,
        'characterId',
        'does not belong to this product conversation',
      );
    }
  }

  void _validateInput(
    String content,
    List<Map<String, String>>? attachments,
  ) {
    if (attachments != null && attachments.isNotEmpty) {
      throw ArgumentError.value(attachments, 'attachments', 'not supported');
    }
    if (content.trim().isEmpty) {
      throw ArgumentError.value(content, 'content', 'must not be blank');
    }
    if (content.length > maximumInputLength) {
      throw ArgumentError.value(content, 'content', 'is too large');
    }
  }
}
