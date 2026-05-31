import 'package:drift/drift.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/db/tables.dart';

part 'voice_call_dao.g.dart';

@DriftAccessor(tables: [VoiceCallSessions, VoiceCallMessages])
class VoiceCallDao extends DatabaseAccessor<AppDatabase>
    with _$VoiceCallDaoMixin {
  VoiceCallDao(super.db);

  Future<void> createSession(VoiceCallSessionsCompanion session) =>
      into(voiceCallSessions).insert(session);

  Future<void> endSession(String sessionId,
      {required int endedAt, String? summary}) =>
      (update(voiceCallSessions)..where((t) => t.id.equals(sessionId))).write(
        VoiceCallSessionsCompanion(
          endedAt: Value(endedAt),
          summary:
              summary != null ? Value(summary) : const Value.absent(),
        ),
      );

  Future<void> addMessage(VoiceCallMessagesCompanion message) =>
      into(voiceCallMessages).insert(message);

  /// All sessions for [characterId], newest first.
  Future<List<VoiceCallSession>> sessionsForCharacter(String characterId) =>
      (select(voiceCallSessions)
            ..where((t) => t.characterId.equals(characterId))
            ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
          .get();

  /// All messages for a session, chronological.
  Future<List<VoiceCallMessage>> messagesForSession(String sessionId) =>
      (select(voiceCallMessages)
            ..where((t) => t.sessionId.equals(sessionId))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();
}
