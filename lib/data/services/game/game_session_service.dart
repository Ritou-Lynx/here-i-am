import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../../../db/app_database.dart';

const _uuid = Uuid();
final _log = Logger('GameSessionService');

/// Service for managing game sessions, messages, save points, and branching.
///
/// Isolation guarantee: this service only reads/writes [GameDefinitions],
/// [GameSessions], and [GameMessages] during normal gameplay.
/// The single exception is [endSession], which injects a `game_log` entry
/// into [SharedLifeEntities] — clearly labelled as fictional content so
/// companions can reference "you played X" without accessing raw dialogue.
class GameSessionService {
  final AppDatabase db;

  GameSessionService(this.db);

  // ── Session lifecycle ────────────────────────────────────────────────────

  /// Create a new [GameSession] from a game definition snapshot.
  ///
  /// If [firstMessage] is provided (non-empty), it is injected as the first
  /// assistant message so the character speaks first — matching SillyTavern
  /// convention where `first_mes` opens the session before the user replies.
  Future<GameSession> createSession({
    required String definitionId,
    required String gameType,
    required String definitionTitle,
    required String definitionSnapshotJson,
    String? sessionTitle,
    String? firstMessage,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final id = _uuid.v4();
    final title = sessionTitle ?? '$definitionTitle — 第1局';

    await db.into(db.gameSessions).insert(GameSessionsCompanion.insert(
          id: id,
          definitionId: Value(definitionId),
          gameType: Value(gameType),
          definitionTitle: definitionTitle,
          definitionSnapshotJson: definitionSnapshotJson,
          sessionTitle: title,
          createdAt: now,
          lastPlayedAt: now,
        ));

    // Inject the card's opening line as the first assistant turn.
    final greeting = firstMessage?.trim() ?? '';
    if (greeting.isNotEmpty) {
      await appendMessage(
        sessionId: id,
        role: 'assistant',
        content: greeting,
      );
    }

    return (await getSession(id))!;
  }

  /// Fetch a single session row; returns null when not found.
  Future<GameSession?> getSession(String sessionId) =>
      (db.select(db.gameSessions)..where((t) => t.id.equals(sessionId)))
          .getSingleOrNull();

  /// List sessions, newest played first. Excludes archived by default.
  Future<List<GameSession>> listSessions({
    String? definitionId,
    String? gameType,
    bool includeArchived = false,
  }) async {
    final q = db.select(db.gameSessions);
    if (definitionId != null) q.where((t) => t.definitionId.equalsNullable(definitionId));
    if (gameType != null) q.where((t) => t.gameType.equals(gameType));
    if (!includeArchived) q.where((t) => t.status.isNotIn(['archived']));
    q.orderBy([(t) => OrderingTerm.desc(t.lastPlayedAt)]);
    return q.get();
  }

  // ── Messages ─────────────────────────────────────────────────────────────

  /// Append a message to [sessionId] and update [lastPlayedAt].
  Future<GameMessage> appendMessage({
    required String sessionId,
    required String role,
    required String content,
    String messageType = 'normal',
    String? savepointLabel,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final row = await db.into(db.gameMessages).insertReturning(
          GameMessagesCompanion.insert(
            sessionId: sessionId,
            role: role,
            content: content,
            messageType: Value(messageType),
            savepointLabel: Value(savepointLabel),
            timestamp: now,
          ),
        );
    await (db.update(db.gameSessions)..where((t) => t.id.equals(sessionId)))
        .write(GameSessionsCompanion(lastPlayedAt: Value(now)));
    return row;
  }

  /// All messages for [sessionId], ordered by insertion id (chronological).
  Future<List<GameMessage>> getMessages(String sessionId) =>
      (db.select(db.gameMessages)
            ..where((t) => t.sessionId.equals(sessionId))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();

  // ── Save points ──────────────────────────────────────────────────────────

  /// Snapshot the session state and insert a `save_marker` message.
  /// Returns the marker row (its [GameMessage.id] is the branch handle).
  Future<GameMessage> saveSession(
    String sessionId, {
    String? savepointLabel,
    String? worldStateJson,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final label = savepointLabel ?? _autoSavepointLabel(now);

    await (db.update(db.gameSessions)..where((t) => t.id.equals(sessionId)))
        .write(GameSessionsCompanion(
      worldStateJson: Value(worldStateJson),
      lastPlayedAt: Value(now),
    ));

    return appendMessage(
      sessionId: sessionId,
      role: 'system',
      content: label,
      messageType: 'save_marker',
      savepointLabel: label,
    );
  }

  /// All `save_marker` messages for [sessionId], oldest first.
  Future<List<GameMessage>> getSaveMarkers(String sessionId) =>
      (db.select(db.gameMessages)
            ..where((t) =>
                t.sessionId.equals(sessionId) &
                t.messageType.equals('save_marker'))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();

  // ── Branching ────────────────────────────────────────────────────────────

  /// Fork [parentSessionId] at [savepointMessageId].
  /// Copies all messages up to (and including) the marker into a new session.
  Future<GameSession> branchFromSaveMarker({
    required String parentSessionId,
    required int savepointMessageId,
  }) async {
    final parent = await getSession(parentSessionId);
    if (parent == null) {
      throw StateError('Parent session $parentSessionId not found');
    }

    final sourceMessages = await (db.select(db.gameMessages)
          ..where((t) =>
              t.sessionId.equals(parentSessionId) &
              t.id.isSmallerOrEqualValue(savepointMessageId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final branchId = _uuid.v4();
    final branchNum = await _countBranches(parentSessionId) + 1;

    await db.into(db.gameSessions).insert(GameSessionsCompanion.insert(
          id: branchId,
          definitionId: Value(parent.definitionId),
          gameType: Value(parent.gameType),
          definitionTitle: parent.definitionTitle,
          definitionSnapshotJson: parent.definitionSnapshotJson,
          sessionTitle: '${parent.sessionTitle} — 分支 $branchNum',
          parentSessionId: Value(parentSessionId),
          branchFromMessageId: Value(savepointMessageId),
          worldStateJson: Value(parent.worldStateJson),
          createdAt: now,
          lastPlayedAt: now,
        ));

    for (final msg in sourceMessages) {
      await db.into(db.gameMessages).insert(GameMessagesCompanion.insert(
            sessionId: branchId,
            role: msg.role,
            content: msg.content,
            messageType: Value(msg.messageType),
            savepointLabel: Value(msg.savepointLabel),
            timestamp: msg.timestamp,
          ));
    }

    _log.fine('Branched $parentSessionId → $branchId at msg $savepointMessageId');
    return (await getSession(branchId))!;
  }

  // ── End session ──────────────────────────────────────────────────────────

  /// Mark session as ended and auto-inject a `game_log` into User-truth.
  Future<void> endSession(
    String sessionId, {
    required String storySummary,
  }) async {
    final session = await getSession(sessionId);
    if (session == null) return;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await (db.update(db.gameSessions)..where((t) => t.id.equals(sessionId)))
        .write(GameSessionsCompanion(
      status: const Value('ended'),
      storySummary: Value(storySummary),
      lastPlayedAt: Value(now),
    ));

    if (!session.gameLogInjected) {
      await _injectGameLog(session, storySummary, now);
      await (db.update(db.gameSessions)..where((t) => t.id.equals(sessionId)))
          .write(const GameSessionsCompanion(gameLogInjected: Value(true)));
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Write one [SharedLifeEntities] + [SharedLifeEventOperations] row pair
  /// with [entityType] = `game_log` and [primaryDomain] = `game`.
  /// The stateJson carries `isFictional: true` so companions and Memory Review
  /// can render / filter it appropriately.
  Future<void> _injectGameLog(
    GameSession session,
    String storySummary,
    int now,
  ) async {
    final entityId = _uuid.v4();
    final operationId = _uuid.v4();

    final msgCount = await (db.selectOnly(db.gameMessages)
          ..addColumns([db.gameMessages.id.count()])
          ..where(db.gameMessages.sessionId.equals(session.id)))
        .map((r) => r.read(db.gameMessages.id.count())!)
        .getSingle();

    final stateJson = jsonEncode({
      'gameSessionId': session.id,
      'gameType': session.gameType,
      'definitionTitle': session.definitionTitle,
      'sessionTitle': session.sessionTitle,
      'summary': storySummary,
      'messageCount': msgCount,
      'playedAt': now,
      'isFictional': true,
    });

    await db.into(db.sharedLifeEventOperations).insert(
      SharedLifeEventOperationsCompanion.insert(
        id: operationId,
        entityId: entityId,
        operationType: 'create',
        entityType: 'game_log',
        title: session.sessionTitle,
        patchJson: stateJson,
        sourceMessageIds: '[]',
        sourceCharacterId: '',
        createdAt: now,
        sourceKind: const Value('game_session'),
        sourceRef: Value(session.id),
        primaryDomain: const Value('game'),
      ),
    );

    await db.into(db.sharedLifeEntities).insert(
      SharedLifeEntitiesCompanion.insert(
        id: entityId,
        entityType: 'game_log',
        title: session.sessionTitle,
        stateJson: stateJson,
        sourceCharacterId: '',
        lastOperationId: operationId,
        createdAt: now,
        updatedAt: now,
        primaryDomain: const Value('game'),
      ),
    );

    _log.fine('Injected game_log entity $entityId for session ${session.id}');
  }

  Future<int> _countBranches(String parentSessionId) async =>
      (await (db.selectOnly(db.gameSessions)
                ..addColumns([db.gameSessions.id.count()])
                ..where(
                    db.gameSessions.parentSessionId.equals(parentSessionId)))
              .map((r) => r.read(db.gameSessions.id.count())!)
              .getSingle());

  String _autoSavepointLabel(int epochSeconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
    return '存档 ${dt.month}/${dt.day} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
