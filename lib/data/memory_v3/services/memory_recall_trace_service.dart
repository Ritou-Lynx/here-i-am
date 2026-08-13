/// Message-level recall provenance for Memory V3.
///
/// Each companion turn writes the exact memory targets that were injected into
/// that turn to `memory_recall_events`. The read side resolves Dreaming targets
/// back through fragments to their original chat messages, so the UI can show
/// not only "which memory matched" but also "which conversation created it".
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:memex/db/app_database.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class MemoryRecallTarget {
  const MemoryRecallTarget({
    required this.targetTable,
    required this.targetId,
    required this.score,
  });

  final String targetTable;
  final String targetId;
  final double score;
}

class MemoryRecallSourceMessage {
  const MemoryRecallSourceMessage({
    required this.id,
    required this.isFromCharacter,
    required this.content,
    required this.timestamp,
  });

  final int id;
  final bool isFromCharacter;
  final String content;
  final DateTime timestamp;
}

enum MemoryRecallFeedback { helpful, irrelevant }

class MemoryRecallSignalSummary {
  const MemoryRecallSignalSummary({
    required this.recallCount,
    required this.helpfulCount,
    required this.irrelevantCount,
  });

  final int recallCount;
  final int helpfulCount;
  final int irrelevantCount;

  int get effectivePenaltyCount =>
      (recallCount + irrelevantCount * 3 - helpfulCount * 2).clamp(0, 9999);
}

class MemoryRecallTraceItem {
  const MemoryRecallTraceItem({
    required this.targetTable,
    required this.targetId,
    required this.title,
    required this.body,
    required this.score,
    required this.sourceMessages,
    this.feedback,
  });

  final String targetTable;
  final String targetId;
  final String title;
  final String body;
  final double score;
  final List<MemoryRecallSourceMessage> sourceMessages;
  final MemoryRecallFeedback? feedback;

  MemoryRecallTraceItem withFeedback(MemoryRecallFeedback? value) =>
      MemoryRecallTraceItem(
        targetTable: targetTable,
        targetId: targetId,
        title: title,
        body: body,
        score: score,
        sourceMessages: sourceMessages,
        feedback: value,
      );

  bool get isDirectMatch => score > 0;

  String get typeLabel => switch (targetTable) {
        MemoryRecallTraceService.memoryCardsTable => 'Memory Card',
        MemoryRecallTraceService.memoryEpisodesTable => 'Episode',
        MemoryRecallTraceService.memoryFragmentsTable => 'Fragment',
        MemoryRecallTraceService.memorySagasTable => 'Saga',
        MemoryRecallTraceService.projectMemoryTable => 'Project Memory',
        _ => targetTable,
      };
}

class MemoryRecallTrace {
  const MemoryRecallTrace({
    required this.chatMessageId,
    required this.query,
    required this.wasCaptured,
    required this.items,
  });

  final int chatMessageId;
  final String query;
  final bool wasCaptured;
  final List<MemoryRecallTraceItem> items;

  int get directMatchCount => items.where((item) => item.isDirectMatch).length;
  int get fallbackCount => items.length - directMatchCount;
}

class MemoryRecallTraceService {
  MemoryRecallTraceService(this._db);

  final AppDatabase _db;

  static const turnMarkerTable = '_recall_turn';
  static const turnAliasTable = '_recall_turn_alias';
  static const feedbackTablePrefix = '_recall_feedback:';
  static const memoryCardsTable = 'memory_cards';
  static const memoryEpisodesTable = 'memory_episodes';
  static const memoryFragmentsTable = 'memory_fragments';
  static const memorySagasTable = 'memory_sagas';
  static const projectMemoryTable = 'project_memory_items';

  /// Starts (or restarts) one recall trace.
  ///
  /// Retrying the same persisted user message replaces its previous trace, so
  /// the long-press UI always reflects the response the user currently sees.
  ///
  /// [chatMessageSyncId] is the stable cross-device id of [chatMessageId]; when
  /// provided it is dual-written so the trace survives device replication.
  Future<void> startTurn({
    required int chatMessageId,
    required String query,
    Iterable<int> relatedChatMessageIds = const [],
    String? chatMessageSyncId,
  }) async {
    if (chatMessageId <= 0) return;
    final messageKey = chatMessageId.toString();
    final messageKeys = <String>{
      messageKey,
      ...relatedChatMessageIds.where((id) => id > 0).map((id) => '$id'),
    };
    // Resolve stable ids for the primary and any alias messages, so every row
    // gets dual-written. Missing sync_ids are left null (legacy rows).
    final syncById = await _resolveSyncIds({
      chatMessageId,
      ...relatedChatMessageIds,
    });
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await (_db.delete(_db.memoryRecallEvents)
            ..where((table) => table.chatMessageId.isIn(messageKeys.toList())))
          .go();
      await (_db.delete(_db.memoryRecallEvents)
            ..where((table) =>
                table.targetTable.equals(turnAliasTable) &
                table.targetId.equals(messageKey)))
          .go();
      await _db.into(_db.memoryRecallEvents).insert(
            MemoryRecallEventsCompanion.insert(
              id: _uuid.v4(),
              targetTable: turnMarkerTable,
              targetId: messageKey,
              chatMessageId: Value(messageKey),
              chatMessageSyncId: Value(chatMessageSyncId ?? syncById[chatMessageId]),
              query: Value(query.trim()),
              score: 0.0,
              createdAt: now,
            ),
          );
      for (final aliasKey in messageKeys.where((key) => key != messageKey)) {
        final aliasId = int.tryParse(aliasKey);
        await _db.into(_db.memoryRecallEvents).insert(
              MemoryRecallEventsCompanion.insert(
                id: _uuid.v4(),
                targetTable: turnAliasTable,
                targetId: messageKey,
                chatMessageId: Value(aliasKey),
                chatMessageSyncId: Value(
                    aliasId == null ? null : syncById[aliasId]),
                query: Value(query.trim()),
                score: 0.0,
                createdAt: now,
              ),
            );
      }
    });
  }

  /// Counts distinct recent turns that received each target.
  ///
  /// The result is the input for novelty penalty. Turn markers and aliases are
  /// naturally excluded because callers provide a concrete target table.
  Future<Map<String, int>> recentRecallCounts({
    required String targetTable,
    required Iterable<String> targetIds,
    Duration window = const Duration(days: 7),
    int? excludeChatMessageId,
  }) async {
    final summaries = await recentRecallSignals(
      targetTable: targetTable,
      targetIds: targetIds,
      window: window,
      excludeChatMessageId: excludeChatMessageId,
    );
    return {
      for (final entry in summaries.entries)
        entry.key: entry.value.effectivePenaltyCount,
    };
  }

  Future<Map<String, MemoryRecallSignalSummary>> recentRecallSignals({
    required String targetTable,
    required Iterable<String> targetIds,
    Duration window = const Duration(days: 7),
    int? excludeChatMessageId,
  }) async {
    final ids = targetIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return const {};
    final cutoff = DateTime.now().subtract(window).millisecondsSinceEpoch;
    final feedbackTable = _feedbackTable(targetTable);
    final query = _db.select(_db.memoryRecallEvents)
      ..where((table) =>
          table.targetTable.isIn([targetTable, feedbackTable]) &
          table.targetId.isIn(ids.toList()) &
          table.createdAt.isBiggerOrEqualValue(cutoff));
    if (excludeChatMessageId != null && excludeChatMessageId > 0) {
      query.where((table) =>
          table.chatMessageId.isNotValue(excludeChatMessageId.toString()));
    }
    final rows = await query.get();
    final turnsByTarget = <String, Set<String>>{};
    final helpfulByTarget = <String, int>{};
    final irrelevantByTarget = <String, int>{};
    for (final row in rows) {
      if (row.targetTable == targetTable) {
        turnsByTarget
            .putIfAbsent(row.targetId, () => <String>{})
            .add(row.chatMessageId ?? row.id);
      } else if (row.score > 0) {
        helpfulByTarget.update(row.targetId, (count) => count + 1,
            ifAbsent: () => 1);
      } else if (row.score < 0) {
        irrelevantByTarget.update(row.targetId, (count) => count + 1,
            ifAbsent: () => 1);
      }
    }
    return {
      for (final id in ids)
        if (turnsByTarget.containsKey(id) ||
            helpfulByTarget.containsKey(id) ||
            irrelevantByTarget.containsKey(id))
          id: MemoryRecallSignalSummary(
            recallCount: turnsByTarget[id]?.length ?? 0,
            helpfulCount: helpfulByTarget[id] ?? 0,
            irrelevantCount: irrelevantByTarget[id] ?? 0,
          ),
    };
  }

  Future<void> setFeedback({
    required int chatMessageId,
    required String targetTable,
    required String targetId,
    MemoryRecallFeedback? feedback,
  }) async {
    final canonicalId = await _canonicalChatMessageId(chatMessageId);
    final feedbackTable = _feedbackTable(targetTable);
    await (_db.delete(_db.memoryRecallEvents)
          ..where((table) =>
              table.chatMessageId.equals('$canonicalId') &
              table.targetTable.equals(feedbackTable) &
              table.targetId.equals(targetId)))
        .go();
    if (feedback == null) return;
    await _db.into(_db.memoryRecallEvents).insert(
          MemoryRecallEventsCompanion.insert(
            id: _uuid.v4(),
            targetTable: feedbackTable,
            targetId: targetId,
            chatMessageId: Value('$canonicalId'),
            query: Value(feedback.name),
            score: feedback == MemoryRecallFeedback.helpful ? 1 : -1,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Future<void> recordTargets({
    required int chatMessageId,
    required String query,
    required Iterable<MemoryRecallTarget> targets,
    String? chatMessageSyncId,
  }) async {
    if (chatMessageId <= 0) return;
    final targetList = targets
        .where((target) =>
            target.targetTable.isNotEmpty && target.targetId.isNotEmpty)
        .toList(growable: false);
    if (targetList.isEmpty) return;

    final messageKey = chatMessageId.toString();
    final syncId = chatMessageSyncId ??
        (await _resolveSyncIds({chatMessageId}))[chatMessageId];
    final existing = await (_db.select(_db.memoryRecallEvents)
          ..where((table) => table.chatMessageId.equals(messageKey)))
        .get();
    final existingKeys = {
      for (final row in existing) '${row.targetTable}\u0000${row.targetId}',
    };
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.batch((batch) {
      for (final target in targetList) {
        final key = '${target.targetTable}\u0000${target.targetId}';
        if (!existingKeys.add(key)) continue;
        batch.insert(
          _db.memoryRecallEvents,
          MemoryRecallEventsCompanion.insert(
            id: _uuid.v4(),
            targetTable: target.targetTable,
            targetId: target.targetId,
            chatMessageId: Value(messageKey),
            chatMessageSyncId: Value(syncId),
            query: Value(query.trim()),
            score: target.score,
            createdAt: now,
          ),
        );
      }
    });
  }

  Future<MemoryRecallTrace> loadTrace(int chatMessageId) async {
    var rows = await (_db.select(_db.memoryRecallEvents)
          ..where(
              (table) => table.chatMessageId.equals(chatMessageId.toString()))
          ..orderBy([
            (table) => OrderingTerm.desc(table.score),
            (table) => OrderingTerm.asc(table.createdAt),
          ]))
        .get();
    final alias = rows.where((row) => row.targetTable == turnAliasTable);
    if (alias.isNotEmpty) {
      rows = await (_db.select(_db.memoryRecallEvents)
            ..where((table) => table.chatMessageId.equals(alias.first.targetId))
            ..orderBy([
              (table) => OrderingTerm.desc(table.score),
              (table) => OrderingTerm.asc(table.createdAt),
            ]))
          .get();
    }
    final marker = rows.where((row) => row.targetTable == turnMarkerTable);
    final feedbackByTarget = <String, MemoryRecallFeedback>{};
    for (final row in rows
        .where((row) => row.targetTable.startsWith(feedbackTablePrefix))) {
      final originalTable =
          row.targetTable.substring(feedbackTablePrefix.length);
      feedbackByTarget['$originalTable\u0000${row.targetId}'] = row.score > 0
          ? MemoryRecallFeedback.helpful
          : MemoryRecallFeedback.irrelevant;
    }
    final query = marker.isNotEmpty
        ? marker.first.query ?? ''
        : rows.isNotEmpty
            ? rows.first.query ?? ''
            : '';

    final items = <MemoryRecallTraceItem>[];
    for (final row in rows) {
      if (row.targetTable == turnMarkerTable ||
          row.targetTable == turnAliasTable ||
          row.targetTable.startsWith(feedbackTablePrefix)) {
        continue;
      }
      final item = await _resolveItem(row);
      items.add(item.withFeedback(
          feedbackByTarget['${row.targetTable}\u0000${row.targetId}']));
    }

    return MemoryRecallTrace(
      chatMessageId: chatMessageId,
      query: query,
      wasCaptured: marker.isNotEmpty,
      items: List.unmodifiable(items),
    );
  }

  Future<MemoryRecallTraceItem> _resolveItem(MemoryRecallEvent event) async {
    return switch (event.targetTable) {
      memoryCardsTable => _resolveCard(event),
      memoryFragmentsTable => _resolveFragment(event),
      memoryEpisodesTable => _resolveEpisode(event),
      memorySagasTable => _resolveSaga(event),
      projectMemoryTable => _resolveProjectMemory(event),
      _ => _unknownItem(event),
    };
  }

  Future<MemoryRecallTraceItem> _resolveCard(MemoryRecallEvent event) async {
    final card = await (_db.select(_db.memoryCards)
          ..where((table) => table.id.equals(event.targetId)))
        .getSingleOrNull();
    final source = await (_db.select(_db.memoryCardSources)
          ..where((table) => table.cardId.equals(event.targetId)))
        .getSingleOrNull();
    final sourceIds = _messageIdsFromSourceRef(source?.sourceRef);
    return MemoryRecallTraceItem(
      targetTable: event.targetTable,
      targetId: event.targetId,
      title: card == null
          ? '已删除的 Memory Card'
          : '${card.dropletLabel} · ${card.title}',
      body: card?.retrievalText ?? source?.rawInput ?? '这张卡片已不存在。',
      score: event.score,
      sourceMessages: await _loadMessages(sourceIds),
    );
  }

  Future<MemoryRecallTraceItem> _resolveFragment(
      MemoryRecallEvent event) async {
    final fragment = await (_db.select(_db.memoryFragments)
          ..where((table) => table.id.equals(event.targetId)))
        .getSingleOrNull();
    return MemoryRecallTraceItem(
      targetTable: event.targetTable,
      targetId: event.targetId,
      title: '过往碎片',
      body: fragment?.content ?? '这个 Fragment 已不存在。',
      score: event.score,
      sourceMessages:
          await _loadMessages(_decodeIntList(fragment?.sourceMessageIds)),
    );
  }

  Future<MemoryRecallTraceItem> _resolveEpisode(MemoryRecallEvent event) async {
    final episode = await (_db.select(_db.memoryEpisodes)
          ..where((table) => table.id.equals(event.targetId)))
        .getSingleOrNull();
    final sourceIds = episode == null
        ? const <int>{}
        : await _messageIdsForFragmentIds(
            _decodeStringList(episode.sourceFragmentIds));
    final topic = episode?.topicId;
    return MemoryRecallTraceItem(
      targetTable: event.targetTable,
      targetId: event.targetId,
      title: topic == null || topic.isEmpty || topic == '__ungrouped__'
          ? '过往章节'
          : '过往章节 · $topic',
      body: episode?.narrative ?? '这个 Episode 已不存在。',
      score: event.score,
      sourceMessages: await _loadMessages(sourceIds),
    );
  }

  Future<MemoryRecallTraceItem> _resolveSaga(MemoryRecallEvent event) async {
    final saga = await (_db.select(_db.memorySagas)
          ..where((table) => table.id.equals(event.targetId)))
        .getSingleOrNull();
    final episodeIds = _decodeStringList(saga?.episodeIds);
    final fragmentIds = <String>{};
    if (episodeIds.isNotEmpty) {
      final episodes = await (_db.select(_db.memoryEpisodes)
            ..where((table) => table.id.isIn(episodeIds.toList())))
          .get();
      for (final episode in episodes) {
        fragmentIds.addAll(_decodeStringList(episode.sourceFragmentIds));
      }
    }
    final sourceIds = await _messageIdsForFragmentIds(fragmentIds);
    return MemoryRecallTraceItem(
      targetTable: event.targetTable,
      targetId: event.targetId,
      title: saga == null ? '已删除的长期弧线' : '长期弧线 · ${saga.title}',
      body: saga?.description ?? '这个 Saga 已不存在。',
      score: event.score,
      sourceMessages: await _loadMessages(sourceIds),
    );
  }

  Future<MemoryRecallTraceItem> _resolveProjectMemory(
      MemoryRecallEvent event) async {
    final item = await (_db.select(_db.projectMemoryItems)
          ..where((table) => table.id.equals(event.targetId)))
        .getSingleOrNull();
    return MemoryRecallTraceItem(
      targetTable: event.targetTable,
      targetId: event.targetId,
      title: item == null ? '已删除的项目记忆' : '项目 · ${item.projectKey}',
      body: item?.summary ?? '这条 Project Memory 已不存在。',
      score: event.score,
      sourceMessages: const [],
    );
  }

  MemoryRecallTraceItem _unknownItem(MemoryRecallEvent event) =>
      MemoryRecallTraceItem(
        targetTable: event.targetTable,
        targetId: event.targetId,
        title: event.targetTable,
        body: event.targetId,
        score: event.score,
        sourceMessages: const [],
      );

  Future<int> _canonicalChatMessageId(int chatMessageId) async {
    final alias = await (_db.select(_db.memoryRecallEvents)
          ..where((table) =>
              table.chatMessageId.equals('$chatMessageId') &
              table.targetTable.equals(turnAliasTable)))
        .getSingleOrNull();
    return int.tryParse(alias?.targetId ?? '') ?? chatMessageId;
  }

  /// Resolves local persona_chat_messages integer IDs to their stable sync_ids.
  /// Used for dual-writing recall trace rows so they survive device replication.
  Future<Map<int, String>> _resolveSyncIds(Iterable<int> ids) async {
    final unique = ids.where((id) => id > 0).toSet();
    if (unique.isEmpty) return const {};
    final rows = await (_db.select(_db.personaChatMessages)
          ..where((t) => t.id.isIn(unique)))
        .get();
    return {
      for (final row in rows)
        if (row.syncId != null && row.syncId!.isNotEmpty) row.id: row.syncId!,
    };
  }

  static String _feedbackTable(String targetTable) =>
      '$feedbackTablePrefix$targetTable';

  Future<Set<int>> _messageIdsForFragmentIds(
      Iterable<String> fragmentIds) async {
    final ids = fragmentIds.toSet();
    if (ids.isEmpty) return const {};
    final fragments = await (_db.select(_db.memoryFragments)
          ..where((table) => table.id.isIn(ids.toList())))
        .get();
    return {
      for (final fragment in fragments)
        ..._decodeIntList(fragment.sourceMessageIds),
    };
  }

  Future<List<MemoryRecallSourceMessage>> _loadMessages(
      Iterable<int> messageIds) async {
    final ids = messageIds.toSet();
    if (ids.isEmpty) return const [];
    final rows = await (_db.select(_db.personaChatMessages)
          ..where((table) => table.id.isIn(ids.toList())))
        .get();
    rows.sort((a, b) {
      final byTime = a.timestamp.compareTo(b.timestamp);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    return rows
        .map((row) => MemoryRecallSourceMessage(
              id: row.id,
              isFromCharacter: row.isFromCharacter,
              content: row.content,
              timestamp: row.timestamp,
            ))
        .toList(growable: false);
  }

  static Set<int> _decodeIntList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final value = jsonDecode(raw);
      if (value is List) {
        return value
            .map((item) => item is int ? item : int.tryParse('$item'))
            .whereType<int>()
            .toSet();
      }
    } catch (_) {}
    return const {};
  }

  static Set<String> _decodeStringList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final value = jsonDecode(raw);
      if (value is List) {
        return value
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toSet();
      }
    } catch (_) {}
    return const {};
  }

  static Set<int> _messageIdsFromSourceRef(String? sourceRef) {
    if (sourceRef == null || sourceRef.trim().isEmpty) return const {};
    final raw = sourceRef.trim();
    final direct = int.tryParse(raw);
    if (direct != null) return {direct};
    try {
      final value = jsonDecode(raw);
      if (value is List) {
        return value
            .map((item) => item is int ? item : int.tryParse('$item'))
            .whereType<int>()
            .toSet();
      }
      if (value is Map) {
        final ids = <int>{};
        final single = value['messageId'];
        final parsedSingle =
            single is int ? single : int.tryParse(single?.toString() ?? '');
        if (parsedSingle != null) ids.add(parsedSingle);
        final many = value['messageIds'];
        if (many is List) {
          ids.addAll(many
              .map((item) => item is int ? item : int.tryParse('$item'))
              .whereType<int>());
        }
        return ids;
      }
    } catch (_) {}
    return RegExp(r'\d+')
        .allMatches(raw)
        .map((match) => int.tryParse(match.group(0)!))
        .whereType<int>()
        .toSet();
  }
}
