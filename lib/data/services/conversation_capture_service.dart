import 'dart:async';

import 'package:drift/drift.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';

typedef ConversationCaptureEnqueue = Future<String> Function({
  required String userId,
  required String taskType,
  required Map<String, dynamic> payload,
  int priority,
  int maxRetries,
  String? bizId,
});

class ConversationCaptureSlice {
  const ConversationCaptureSlice({
    required this.characterId,
    required this.afterMessageId,
    required this.throughMessageId,
    required this.messages,
  });

  final String characterId;
  final int afterMessageId;
  final int throughMessageId;
  final List<PersonaChatMessage> messages;

  Set<int> get userMessageIds => messages
      .where((message) => !message.isFromCharacter)
      .map((message) => message.id)
      .toSet();

  String get combinedText => messages
      .map((message) =>
          '${message.isFromCharacter ? 'character' : 'user'}: ${message.content}')
      .join('\n');
}

class ConversationCaptureBaselineResetResult {
  const ConversationCaptureBaselineResetResult({
    required this.characterCount,
    required this.discardedTaskCount,
    required this.undoneOperationCount,
  });

  final int characterCount;
  final int discardedTaskCount;
  final int undoneOperationCount;
}

/// Creates durable background extraction slices from companion chat messages.
///
/// Scheduling is deterministic and cheap. The LLM work is performed later by
/// `conversation_capture_task`, never inline with a visible chat response.
class ConversationCaptureService {
  ConversationCaptureService(
    this.db, {
    ConversationCaptureEnqueue? enqueueTask,
    SharedLifeMemoryService? sharedLifeMemory,
    this.minimumMessageCount = 2,
    this.minimumCharacterCount = 240,
    this.idleDelay = const Duration(minutes: 2),
  })  : _enqueueTask = enqueueTask ?? _enqueueWithLocalTaskExecutor,
        sharedLifeMemory = sharedLifeMemory ?? SharedLifeMemoryService(db);

  static const taskType = 'conversation_capture_task';
  static const _baselineResetMarkerKey =
      'conversation_capture_baseline_reset_v1';

  static ConversationCaptureService? _instance;

  static ConversationCaptureService get instance {
    final service = _instance;
    if (service == null) {
      throw StateError('ConversationCaptureService has not been initialized');
    }
    return service;
  }

  static bool get isInitialized => _instance != null;

  static void init(AppDatabase db, String userId) {
    _instance?.dispose();
    _instance = ConversationCaptureService(db);
    _instance!.sharedLifeMemory.attachUserId(userId);
  }

  final AppDatabase db;
  final ConversationCaptureEnqueue _enqueueTask;
  final SharedLifeMemoryService sharedLifeMemory;
  final int minimumMessageCount;
  final int minimumCharacterCount;
  final Duration idleDelay;
  final _logger = getLogger('ConversationCaptureService');
  final Map<String, Timer> _idleTimers = {};

  Future<bool> noteConversationActivity({
    required String userId,
    required String characterId,
    bool force = false,
    String trigger = 'message_threshold',
  }) async {
    _armIdleCapture(userId: userId, characterId: characterId);
    return scheduleIfNeeded(
      userId: userId,
      characterId: characterId,
      force: force,
      trigger: trigger,
    );
  }

  /// Auto-capture is disabled pending migration to RecordOrganizerService.
  /// User-truth is now only written via explicit user actions (record button,
  /// floating ball, natural language "记一下", external data streams).
  /// When true, scheduleIfNeeded() always returns false — force:true is NOT
  /// a bypass; that loophole was the source of repeated phantom card generation.
  static bool autoCapturePaused = true;

  Future<bool> scheduleIfNeeded({
    required String userId,
    required String characterId,
    bool force = false,
    String trigger = 'message_threshold',
  }) async {
    if (autoCapturePaused) return false;
    var cursor = await _readOrCreateCursor(characterId);
    if (cursor.lastQueuedMessageId > cursor.lastExtractedMessageId) {
      final hasActiveTask = await _hasActiveQueuedCaptureTask(
        characterId: characterId,
        throughMessageId: cursor.lastQueuedMessageId,
      );
      if (hasActiveTask) return false;

      _logger.info(
        'Released stale queued conversation capture slice for $characterId '
        'through message ${cursor.lastQueuedMessageId}',
      );
      await _writeCursor(
        characterId: characterId,
        lastExtractedMessageId: cursor.lastExtractedMessageId,
        lastQueuedMessageId: cursor.lastExtractedMessageId,
      );
      cursor = await _readOrCreateCursor(characterId);
    }
    final pendingMessages = await _messagesAfter(
      characterId,
      cursor.lastExtractedMessageId,
    );
    if (pendingMessages.isEmpty) return false;

    final characterCount = pendingMessages.fold<int>(
      0,
      (sum, message) => sum + message.content.length,
    );
    if (!force &&
        pendingMessages.length < minimumMessageCount &&
        characterCount < minimumCharacterCount) {
      return false;
    }

    final throughMessageId = pendingMessages.last.id;
    await _enqueueTask(
      userId: userId,
      taskType: taskType,
      payload: {
        'character_id': characterId,
        'after_message_id': cursor.lastExtractedMessageId,
        'through_message_id': throughMessageId,
        'trigger': trigger,
      },
      priority: -1,
      maxRetries: 3,
      bizId: 'conversation_capture:$characterId:$throughMessageId',
    );
    await _writeCursor(
      characterId: characterId,
      lastExtractedMessageId: cursor.lastExtractedMessageId,
      lastQueuedMessageId: throughMessageId,
    );
    return true;
  }

  Future<ConversationCaptureSlice?> loadSlice({
    required String characterId,
    required int afterMessageId,
    required int throughMessageId,
  }) async {
    final messages = await (db.select(db.personaChatMessages)
          ..where((t) =>
              t.characterId.equals(characterId) &
              t.id.isBiggerThanValue(afterMessageId) &
              t.id.isSmallerOrEqualValue(throughMessageId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    if (messages.isEmpty) return null;
    return ConversationCaptureSlice(
      characterId: characterId,
      afterMessageId: afterMessageId,
      throughMessageId: throughMessageId,
      messages: messages,
    );
  }

  Future<void> markSliceExtracted({
    required String userId,
    required String characterId,
    required int throughMessageId,
  }) async {
    final cursor = await _readOrCreateCursor(characterId);
    await _writeCursor(
      characterId: characterId,
      lastExtractedMessageId: throughMessageId > cursor.lastExtractedMessageId
          ? throughMessageId
          : cursor.lastExtractedMessageId,
      lastQueuedMessageId: throughMessageId >= cursor.lastQueuedMessageId
          ? throughMessageId
          : cursor.lastQueuedMessageId,
    );
    await scheduleIfNeeded(
      userId: userId,
      characterId: characterId,
      trigger: 'backlog',
    );
  }

  Future<void> releaseSlice({
    required String characterId,
    required int throughMessageId,
  }) async {
    final cursor = await _readOrCreateCursor(characterId);
    if (cursor.lastQueuedMessageId != throughMessageId) return;
    await _writeCursor(
      characterId: characterId,
      lastExtractedMessageId: cursor.lastExtractedMessageId,
      lastQueuedMessageId: cursor.lastExtractedMessageId,
    );
  }

  Future<int> releaseStaleQueuedSlices() async {
    final cursors = await (db.select(db.conversationCaptureCursors)
          ..where((t) => t.lastQueuedMessageId.isBiggerThan(
                t.lastExtractedMessageId,
              )))
        .get();
    var released = 0;
    for (final cursor in cursors) {
      final hasActiveTask = await _hasActiveQueuedCaptureTask(
        characterId: cursor.characterId,
        throughMessageId: cursor.lastQueuedMessageId,
      );
      if (hasActiveTask) continue;
      await _writeCursor(
        characterId: cursor.characterId,
        lastExtractedMessageId: cursor.lastExtractedMessageId,
        lastQueuedMessageId: cursor.lastExtractedMessageId,
      );
      released++;
    }
    if (released > 0) {
      _logger.info('Released $released stale conversation capture cursor(s)');
    }
    return released;
  }

  Future<void> undoOperations(List<String> operationIds) {
    return sharedLifeMemory.undoOperations(operationIds);
  }

  List<SharedLifeOperationDraft> filterBackgroundOperations({
    required ConversationCaptureSlice slice,
    required List<SharedLifeOperationDraft> operations,
  }) {
    final userMessageIds = slice.userMessageIds;
    final filtered = operations.where((operation) {
      final hasUserEvidence =
          operation.sourceMessageIds.any(userMessageIds.contains);
      if (!hasUserEvidence) return false;
      if (_isEphemeralBackgroundTask(
        operationType: operation.operationType,
        entityType: operation.entityType,
        title: operation.title,
      )) {
        return false;
      }
      return true;
    }).toList(growable: false);
    if (filtered.length != operations.length) {
      _logger.info(
        'Discarded ${operations.length - filtered.length} unsafe '
        'background capture operation(s)',
      );
    }
    return filtered;
  }

  /// Removes short-lived background artifacts written by older builds. These
  /// belong in raw chat or the reminder queue, not the durable life store.
  Future<int> repairEphemeralBackgroundRecords() async {
    final rows = await db.select(db.sharedLifeEventOperations).get();
    final revertedIds =
        rows.map((row) => row.revertsOperationId).whereType<String>().toSet();
    final operationIds = rows
        .where((row) =>
            row.captureTaskId != null &&
            !revertedIds.contains(row.id) &&
            _isEphemeralBackgroundTask(
              operationType: row.operationType,
              entityType: row.entityType,
              title: row.title,
            ))
        .map((row) => row.id)
        .toList(growable: false);
    await sharedLifeMemory.undoOperations(operationIds);
    if (operationIds.isNotEmpty) {
      _logger.info(
        'Removed ${operationIds.length} ephemeral background record(s)',
      );
    }
    return operationIds.length;
  }

  /// Establishes a start-at-now cursor for chats that existed before capture
  /// was enabled. It never advances an existing cursor.
  Future<int> initializeCaptureBaselines() async {
    final latestIds = await _latestMessageIdsByCharacter();
    var initialized = 0;
    for (final entry in latestIds.entries) {
      final inserted = await db.into(db.conversationCaptureCursors).insert(
            ConversationCaptureCursorsCompanion.insert(
              characterId: entry.key,
              lastExtractedMessageId: Value(entry.value),
              lastQueuedMessageId: Value(entry.value),
              updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      if (inserted > 0) initialized++;
    }
    return initialized;
  }

  Future<bool> needsHistoricalBackfillReset() async {
    final marker = await (db.select(db.kvStore)
          ..where((t) => t.key.equals(_baselineResetMarkerKey)))
        .getSingleOrNull();
    return marker != null;
  }

  /// One-time repair for builds that accidentally treated old chat history as
  /// new capture input. Explicit foreground records are preserved.
  Future<ConversationCaptureBaselineResetResult>
      resetHistoricalBackfill() async {
    final activeBackgroundOperationIds = await _activeBackgroundOperationIds();
    await sharedLifeMemory.undoOperations(activeBackgroundOperationIds);

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final discardedTaskCount = await (db.update(db.tasks)
          ..where((t) =>
              t.type.equals(taskType) &
              t.status.isIn(['pending', 'processing', 'retrying'])))
        .write(
      TasksCompanion(
        status: const Value('completed'),
        result: const Value('{"discarded":"capture_baseline_reset"}'),
        completedAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    final latestIds = await _latestMessageIdsByCharacter();
    for (final entry in latestIds.entries) {
      await _writeCursor(
        characterId: entry.key,
        lastExtractedMessageId: entry.value,
        lastQueuedMessageId: entry.value,
      );
    }
    await (db.delete(db.kvStore)
          ..where((t) => t.key.equals(_baselineResetMarkerKey)))
        .go();
    _logger.info(
      'Reset historical capture backfill: ${latestIds.length} chats, '
      '$discardedTaskCount tasks, '
      '${activeBackgroundOperationIds.length} operations',
    );
    return ConversationCaptureBaselineResetResult(
      characterCount: latestIds.length,
      discardedTaskCount: discardedTaskCount,
      undoneOperationCount: activeBackgroundOperationIds.length,
    );
  }

  void dispose() {
    for (final timer in _idleTimers.values) {
      timer.cancel();
    }
    _idleTimers.clear();
  }

  void _armIdleCapture({
    required String userId,
    required String characterId,
  }) {
    _idleTimers.remove(characterId)?.cancel();
    _idleTimers[characterId] = Timer(idleDelay, () {
      _idleTimers.remove(characterId);
      unawaited(
        scheduleIfNeeded(
          userId: userId,
          characterId: characterId,
          force: autoCapturePaused ? false : true,
          trigger: 'idle',
        ).catchError((Object error, StackTrace stackTrace) {
          _logger.warning(
              'Idle conversation capture failed', error, stackTrace);
          return false;
        }),
      );
    });
  }

  Future<ConversationCaptureCursor> _readOrCreateCursor(
      String characterId) async {
    final existing = await (db.select(db.conversationCaptureCursors)
          ..where((t) => t.characterId.equals(characterId)))
        .getSingleOrNull();
    if (existing != null) return existing;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.into(db.conversationCaptureCursors).insert(
          ConversationCaptureCursorsCompanion.insert(
            characterId: characterId,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return (db.select(db.conversationCaptureCursors)
          ..where((t) => t.characterId.equals(characterId)))
        .getSingle();
  }

  Future<List<PersonaChatMessage>> _messagesAfter(
    String characterId,
    int messageId,
  ) {
    return (db.select(db.personaChatMessages)
          ..where((t) =>
              t.characterId.equals(characterId) &
              t.id.isBiggerThanValue(messageId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  Future<Map<String, int>> _latestMessageIdsByCharacter() async {
    final rows = await db.customSelect(
      'SELECT character_id, MAX(id) AS max_message_id '
      'FROM persona_chat_messages GROUP BY character_id',
      readsFrom: {db.personaChatMessages},
    ).get();
    return {
      for (final row in rows)
        row.read<String>('character_id'): row.read<int>('max_message_id'),
    };
  }

  Future<bool> _hasActiveQueuedCaptureTask({
    required String characterId,
    required int throughMessageId,
  }) async {
    final bizId = 'conversation_capture:$characterId:$throughMessageId';
    final task = await (db.select(db.tasks)
          ..where((t) =>
              t.type.equals(taskType) &
              t.bizId.equals(bizId) &
              t.status.isIn(['pending', 'processing', 'retrying'])))
        .getSingleOrNull();
    return task != null;
  }

  Future<List<String>> _activeBackgroundOperationIds() async {
    final rows = await db.select(db.sharedLifeEventOperations).get();
    final revertedIds =
        rows.map((row) => row.revertsOperationId).whereType<String>().toSet();
    return rows
        .where((row) =>
            row.operationType != 'undo' &&
            row.captureTaskId != null &&
            !revertedIds.contains(row.id))
        .map((row) => row.id)
        .toList(growable: false);
  }

  Future<void> _writeCursor({
    required String characterId,
    required int lastExtractedMessageId,
    required int lastQueuedMessageId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.into(db.conversationCaptureCursors).insertOnConflictUpdate(
          ConversationCaptureCursorsCompanion.insert(
            characterId: characterId,
            lastExtractedMessageId: Value(lastExtractedMessageId),
            lastQueuedMessageId: Value(lastQueuedMessageId),
            updatedAt: now,
          ),
        );
  }
}

bool _isEphemeralBackgroundTask({
  required String operationType,
  required String entityType,
  required String title,
}) {
  operationType = operationType.trim().toLowerCase();
  if (operationType != 'create' && operationType != 'derive') return false;
  if (entityType.trim().toLowerCase() != 'task') return false;
  title = title.trim().toLowerCase();
  if (const {
    'sleep',
    'go to sleep',
    'going to sleep',
    'go to bed',
    'going to bed',
    '去睡觉',
    '睡觉',
    '睡觉了',
    '上床睡觉',
    '现在睡',
  }.contains(title)) {
    return true;
  }
  final isCallOrReminder = title.contains('打电话') ||
      title.contains('电话') ||
      title.contains('提醒') ||
      title.contains('call') ||
      title.contains('remind');
  final hasShortTermTime = RegExp(
    r'(\d+|[一二两三四五六七八九十两]+)\s*(分钟|分|小时|点|minutes?|mins?|hours?)',
  ).hasMatch(title);
  return isCallOrReminder && hasShortTermTime;
}

Future<String> _enqueueWithLocalTaskExecutor({
  required String userId,
  required String taskType,
  required Map<String, dynamic> payload,
  int priority = 0,
  int maxRetries = 5,
  String? bizId,
}) {
  return LocalTaskExecutor.instance.enqueueTask(
    userId: userId,
    taskType: taskType,
    payload: payload,
    priority: priority,
    maxRetries: maxRetries,
    bizId: bizId,
  );
}
