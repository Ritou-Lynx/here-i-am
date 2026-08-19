/// Durable, short-lived routing context for a Topic Thread conversation.
///
/// Tool results are not persisted into later visible chat turns. When the
/// Companion recalls a thread, this service keeps the selected thread id and
/// the message boundary needed by a later "整理到这个话题" request.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:memex/db/app_database.dart';

class TopicThreadChatContext {
  const TopicThreadChatContext({
    required this.characterId,
    required this.threadId,
    required this.threadTitle,
    required this.afterMessageId,
    required this.updatedAt,
  });

  final String characterId;
  final String threadId;
  final String threadTitle;

  /// Messages with ids greater than this value belong to the active
  /// discussion. The final save command is excluded separately by the tool.
  final int afterMessageId;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'characterId': characterId,
        'threadId': threadId,
        'threadTitle': threadTitle,
        'afterMessageId': afterMessageId,
        'updatedAt': updatedAt.toIso8601String(),
      };

  static TopicThreadChatContext? fromJson(Map<String, dynamic> json) {
    final characterId = json['characterId'] as String?;
    final threadId = json['threadId'] as String?;
    final threadTitle = json['threadTitle'] as String?;
    final afterMessageId = json['afterMessageId'] as int?;
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    if (characterId == null ||
        threadId == null ||
        threadTitle == null ||
        afterMessageId == null ||
        updatedAt == null) {
      return null;
    }
    return TopicThreadChatContext(
      characterId: characterId,
      threadId: threadId,
      threadTitle: threadTitle,
      afterMessageId: afterMessageId,
      updatedAt: updatedAt,
    );
  }
}

class TopicThreadChatContextService {
  TopicThreadChatContextService({
    required AppDatabase db,
    this.maxAge = const Duration(hours: 24),
  }) : _db = db;

  static const _bucket = 'topic_thread_chat_context';
  final AppDatabase _db;
  final Duration maxAge;

  String _key(String characterId) => 'active_topic_thread.$characterId';

  Future<TopicThreadChatContext?> load(
    String characterId, {
    DateTime? now,
  }) async {
    final row = await (_db.select(_db.kvStore)
          ..where((t) => t.key.equals(_key(characterId))))
        .getSingleOrNull();
    if (row?.value == null) return null;
    try {
      final decoded = jsonDecode(row!.value!);
      if (decoded is! Map<String, dynamic>) return null;
      final context = TopicThreadChatContext.fromJson(decoded);
      if (context == null || context.characterId != characterId) return null;
      if ((now ?? DateTime.now()).difference(context.updatedAt) > maxAge) {
        await clear(characterId);
        return null;
      }
      return context;
    } catch (_) {
      await clear(characterId);
      return null;
    }
  }

  Future<void> save(TopicThreadChatContext context) async {
    await _db.into(_db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: _key(context.characterId),
            bucket: const Value(_bucket),
            value: Value(jsonEncode(context.toJson())),
            updatedAt:
                Value(context.updatedAt.millisecondsSinceEpoch ~/ 1000),
          ),
        );
  }

  Future<void> clear(String characterId) {
    return (_db.delete(_db.kvStore)
          ..where((t) => t.key.equals(_key(characterId))))
        .go();
  }
}
