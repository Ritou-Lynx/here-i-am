/// Topic Thread Service — Memory V3 long-running topic tracking.
///
/// Authoritative design: docs/memory-research/TOPIC_THREAD_DESIGN.md
///
/// Governance rules:
/// - Thread creation requires user_confirmed authority.
/// - [corePositions] updates require user_confirmed (never agent_inferred).
/// - Session summaries use agent_inferred + low-friction user confirmation.
/// - [linkedProjectMemoryIds] references are read-only bridges; access
///   respects the originating project's data policy.
library;

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../../../db/app_database.dart';

final _log = Logger('TopicThreadService');
const _uuid = Uuid();

class TopicThreadService {
  final AppDatabase _db;

  TopicThreadService({required AppDatabase db}) : _db = db;

  // ──────────────────────────────────────────────────────────────────────
  // CRUD — TopicThreads
  // ──────────────────────────────────────────────────────────────────────

  /// Create a new Topic Thread.
  ///
  /// Requires explicit user intent — do NOT call from background agents.
  Future<String> createThread({
    required String title,
    String currentStage = '',
    List<String> corePositions = const [],
    List<String> openQuestions = const [],
    String tags = '',
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.topicThreads).insert(
          TopicThreadsCompanion.insert(
            id: id,
            title: title,
            currentStage: Value(currentStage),
            corePositionsJson: Value(_encodeList(corePositions)),
            openQuestionsJson: Value(_encodeList(openQuestions)),
            tags: Value(tags),
            status: const Value('active'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    _log.info('TopicThread created: $id "$title"');
    return id;
  }

  /// Return all threads with [status] (default: active).
  Future<List<TopicThread>> getThreads({String status = 'active'}) {
    return (_db.select(_db.topicThreads)
          ..where((t) => t.status.equals(status))
          ..orderBy([(t) => OrderingTerm.desc(t.lastDiscussedAt)]))
        .get();
  }

  /// Return a single thread by id, or null if not found.
  Future<TopicThread?> getThread(String id) {
    return (_db.select(_db.topicThreads)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Update [currentStage] and/or [openQuestions] (agent_inferred, low-friction).
  ///
  /// Do NOT use this to update [corePositions] — use [updateCorePositions].
  Future<void> updateStage({
    required String threadId,
    String? currentStage,
    List<String>? openQuestions,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.topicThreads)
          ..where((t) => t.id.equals(threadId)))
        .write(TopicThreadsCompanion(
      currentStage:
          currentStage != null ? Value(currentStage) : const Value.absent(),
      openQuestionsJson: openQuestions != null
          ? Value(_encodeList(openQuestions))
          : const Value.absent(),
      updatedAt: Value(now),
    ));
  }

  /// Update [corePositions]. MUST be called with explicit user confirmation.
  ///
  /// This is the only path that may modify confirmed insights.
  Future<void> updateCorePositions({
    required String threadId,
    required List<String> corePositions,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.topicThreads)
          ..where((t) => t.id.equals(threadId)))
        .write(TopicThreadsCompanion(
      corePositionsJson: Value(_encodeList(corePositions)),
      updatedAt: Value(now),
    ));
    _log.info('TopicThread $threadId corePositions updated (user_confirmed)');
  }

  /// Archive or pause a thread.
  Future<void> setStatus({required String threadId, required String status}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (_db.update(_db.topicThreads)
          ..where((t) => t.id.equals(threadId)))
        .write(TopicThreadsCompanion(
      status: Value(status),
      updatedAt: Value(now),
    ));
  }

  // ──────────────────────────────────────────────────────────────────────
  // CRUD — TopicThreadSessions
  // ──────────────────────────────────────────────────────────────────────

  /// Append a discussion session summary to a thread.
  ///
  /// [authority] should be 'agent_inferred' by default; pass 'user_confirmed'
  /// when the user explicitly triggers the save.
  Future<String> appendSession({
    required String threadId,
    required String summary,
    String sourceType = 'chat',
    Map<String, dynamic> sourceRef = const {},
    List<String> linkedCardIds = const [],
    List<String> linkedProjectMemoryIds = const [],
    String authority = 'agent_inferred',
    DateTime? occurredAt,
  }) async {
    final id = _uuid.v4();
    final ts = (occurredAt ?? DateTime.now()).millisecondsSinceEpoch;
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.transaction(() async {
      await _db.into(_db.topicThreadSessions).insert(
            TopicThreadSessionsCompanion.insert(
              id: id,
              threadId: threadId,
              occurredAt: ts,
              summary: summary,
              sourceType: Value(sourceType),
              sourceRefJson: Value(_encodeMap(sourceRef)),
              linkedCardIds: Value(_encodeList(linkedCardIds)),
              linkedProjectMemoryIds:
                  Value(_encodeList(linkedProjectMemoryIds)),
              authority: Value(authority),
              createdAt: now,
            ),
          );

      // Update lastDiscussedAt on the parent thread
      await (_db.update(_db.topicThreads)
            ..where((t) => t.id.equals(threadId)))
          .write(TopicThreadsCompanion(
        lastDiscussedAt: Value(ts),
        updatedAt: Value(now),
      ));
    });

    _log.fine('TopicThreadSession appended to $threadId: $id');
    return id;
  }

  /// Return sessions for a thread, newest first.
  Future<List<TopicThreadSession>> getSessions(
    String threadId, {
    int limit = 20,
  }) {
    return (_db.select(_db.topicThreadSessions)
          ..where((s) => s.threadId.equals(threadId))
          ..orderBy([(s) => OrderingTerm.desc(s.occurredAt)])
          ..limit(limit))
        .get();
  }

  // ──────────────────────────────────────────────────────────────────────
  // Search helpers
  // ──────────────────────────────────────────────────────────────────────

  /// Simple title/tags keyword search for Companion recall.
  Future<List<TopicThread>> searchThreads(String query) async {
    if (query.trim().isEmpty) return getThreads();
    final q = query.toLowerCase();
    return (_db.select(_db.topicThreads)
          ..where((t) =>
              t.status.equals('active') &
              (t.title.lower().contains(q) | t.tags.lower().contains(q)))
          ..orderBy([(t) => OrderingTerm.desc(t.lastDiscussedAt)]))
        .get();
  }

  /// Build a context snapshot for Companion injection.
  ///
  /// Returns state layer only (currentStage + corePositions + openQuestions).
  /// Caller decides whether to append recent sessions.
  Future<TopicThreadContext?> buildContext(
    String threadId, {
    int recentSessions = 3,
  }) async {
    final thread = await getThread(threadId);
    if (thread == null) return null;

    final sessions = await getSessions(threadId, limit: recentSessions);

    return TopicThreadContext(
      threadId: thread.id,
      title: thread.title,
      currentStage: thread.currentStage,
      corePositions: _decodeList(thread.corePositionsJson),
      openQuestions: _decodeList(thread.openQuestionsJson),
      recentSessions: sessions
          .map((s) => TopicSessionSummary(
                occurredAt: DateTime.fromMillisecondsSinceEpoch(s.occurredAt),
                summary: s.summary,
                sourceType: s.sourceType,
              ))
          .toList(),
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────────────────────────────

  static String _encodeList(List<String> list) {
    if (list.isEmpty) return '[]';
    final escaped =
        list.map((e) => '"${e.replaceAll('"', '\\"')}"').join(',');
    return '[$escaped]';
  }

  static String _encodeMap(Map<String, dynamic> map) {
    if (map.isEmpty) return '{}';
    // Simple single-level JSON serialisation
    final pairs = map.entries.map((e) {
      final v = e.value is String ? '"${e.value}"' : '${e.value}';
      return '"${e.key}": $v';
    }).join(', ');
    return '{$pairs}';
  }

  static List<String> _decodeList(String json) {
    if (json == '[]' || json.isEmpty) return [];
    try {
      // Simple extraction between outer brackets
      final inner = json.substring(1, json.length - 1).trim();
      if (inner.isEmpty) return [];
      return inner
          .split(RegExp(r'",\s*"'))
          .map((s) => s.replaceAll(RegExp(r'^"|"$'), ''))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Public bridge for UI/browser code that needs to decode stored JSON lists.
  static List<String> decodeListPublic(String json) => _decodeList(json);
}

/// Lightweight context snapshot passed to Companion Agent for topic continuity.
class TopicThreadContext {
  final String threadId;
  final String title;
  final String currentStage;
  final List<String> corePositions;
  final List<String> openQuestions;
  final List<TopicSessionSummary> recentSessions;

  const TopicThreadContext({
    required this.threadId,
    required this.title,
    required this.currentStage,
    required this.corePositions,
    required this.openQuestions,
    required this.recentSessions,
  });

  /// Format for injection into Companion system prompt.
  String toPromptBlock() {
    final sb = StringBuffer();
    sb.writeln('## 话题线索：$title');
    if (currentStage.isNotEmpty) sb.writeln('当前阶段：$currentStage');
    if (corePositions.isNotEmpty) {
      sb.writeln('已确认洞察：');
      for (final p in corePositions) {
        sb.writeln('  · $p');
      }
    }
    if (openQuestions.isNotEmpty) {
      sb.writeln('还在想的问题：');
      for (final q in openQuestions) {
        sb.writeln('  · $q');
      }
    }
    if (recentSessions.isNotEmpty) {
      sb.writeln('最近讨论：');
      for (final s in recentSessions) {
        final dateStr =
            '${s.occurredAt.month}/${s.occurredAt.day}';
        sb.writeln('  $dateStr (${s.sourceType}): ${s.summary}');
      }
    }
    return sb.toString();
  }
}

class TopicSessionSummary {
  final DateTime occurredAt;
  final String summary;
  final String sourceType;

  const TopicSessionSummary({
    required this.occurredAt,
    required this.summary,
    required this.sourceType,
  });
}
