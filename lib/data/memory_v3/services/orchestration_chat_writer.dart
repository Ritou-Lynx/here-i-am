/// PersonaChatLogWriter：把编排的对话回合写入 Memory V3（PersonaChatMessages）。
///
/// W5 Phase 2 编排层 [ConversationLogWriter] 的 Drift 实现。
/// 只写聊天记录（含 taskRoomId 软引用），**不写任何 User-truth**。
library;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../db/app_database.dart';
import '../../../domain/whiteboard/orchestration/lin_ai_orchestrator.dart';

/// 把 [ConversationTurnRecord] 写入 PersonaChatMessages 的实现。
class PersonaChatLogWriter implements ConversationLogWriter {
  final AppDatabase _db;
  final String characterId;
  final Uuid _uuid = const Uuid();

  PersonaChatLogWriter({
    required AppDatabase db,
    this.characterId = 'lin-ai',
  }) : _db = db;

  @override
  Future<void> append(ConversationTurnRecord turn) async {
    await _db.into(_db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            syncId: Value(_uuid.v4()),
            characterId: characterId,
            isFromCharacter: turn.isFromCharacter,
            content: turn.content,
            isRead: const Value(true),
            timestamp: DateTime.now(),
            taskRoomId: Value(turn.taskRoomId),
          ),
        );
  }
}
