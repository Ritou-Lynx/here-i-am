/// V3 Dreaming orchestration service.
///
/// Orchestrates Fragment extraction, Episode consolidation, and Saga
/// weaving across the Dreaming pipeline.
library;

import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/drift.dart';
import 'package:memex/data/memory_v3/agents/dreaming_agent/episode_consolidator.dart';
import 'package:memex/data/memory_v3/agents/dreaming_agent/fragment_extractor.dart';
import 'package:memex/data/memory_v3/models/dreaming_fragment.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/data/services/search/query_matcher.dart';
import 'package:memex/utils/logger.dart';
import 'package:uuid/uuid.dart';

final _logger = getLogger('memory_v3.DreamingOrchestratorService');

class DreamingFragmentPersistResult {
  DreamingFragmentPersistResult({
    required this.fragmentIds,
    required this.entityIds,
    required this.processedMessageCount,
    required this.lastProcessedMessageId,
    required this.isEmpty,
  });

  final List<String> fragmentIds;
  final List<String> entityIds;
  final int processedMessageCount;
  final int lastProcessedMessageId;
  final bool isEmpty;
}

class EpisodeConsolidationRunResult {
  EpisodeConsolidationRunResult({
    required this.episodeIds,
    required this.consolidatedEntities,
    required this.skippedEntities,
    required this.consolidatedFragmentCount,
  });

  final List<String> episodeIds;
  final List<String> consolidatedEntities;
  final List<String> skippedEntities;
  final int consolidatedFragmentCount;

  bool get isEmpty => episodeIds.isEmpty;
}

class DreamingContextQueryResult {
  const DreamingContextQueryResult({
    required this.episodeHits,
    required this.fragmentHits,
  });

  final List<DreamingEpisodeContextHit> episodeHits;
  final List<DreamingFragmentContextHit> fragmentHits;

  List<MemoryEpisode> get episodes =>
      episodeHits.map((hit) => hit.episode).toList(growable: false);

  List<MemoryFragment> get fragments =>
      fragmentHits.map((hit) => hit.fragment).toList(growable: false);
}

class DreamingEpisodeContextHit {
  const DreamingEpisodeContextHit({
    required this.episode,
    required this.score,
  });

  final MemoryEpisode episode;
  final int score;
}

class DreamingFragmentContextHit {
  const DreamingFragmentContextHit({
    required this.fragment,
    required this.score,
  });

  final MemoryFragment fragment;
  final int score;
}

class DreamingOrchestratorServiceV3 {
  DreamingOrchestratorServiceV3(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();
  static const _bucket = 'memory_v3.dreaming';
  static const _extractorVersion = 'dreaming.fragment_extractor.v3.1';
  static const _episodeConsolidatorVersion =
      'dreaming.episode_consolidator.v3.1';

  static DreamingOrchestratorServiceV3? _instance;

  static DreamingOrchestratorServiceV3 get instance {
    final inst = _instance;
    if (inst == null) {
      throw StateError(
        'DreamingOrchestratorServiceV3 has not been initialized. Call init() first.',
      );
    }
    return inst;
  }

  static bool get isInitialized => _instance != null;

  static void init(AppDatabase db) {
    _instance = DreamingOrchestratorServiceV3(db);
    // Schedule a one-time FTS backfill for Dreaming episodes and fragments.
    // Non-blocking; runs in the next microtask so it does not delay startup.
    // upsertMemoryEpisodeFts / upsertMemoryFragmentFts are idempotent (they
    // DELETE-then-INSERT), so this is safe on every launch. Cost scales with
    // active fragment / episode count, which is bounded in the MVP.
    Future.microtask(() async {
      try {
        // Ensure the FTS virtual tables exist; migration should have run this
        // but createFtsTables is idempotent and cheap.
        await db.searchDao.createFtsTables();
        final ep = await _instance!.reindexAllEpisodes();
        final fr = await _instance!.reindexAllFragments();
        _logger.info(
            'Dreaming FTS backfill: $ep episode(s), $fr fragment(s) indexed');
        await _instance!.backfillFragmentEventTimes();
        await _instance!.recomputeAllEpisodeOccurredAtRange();
      } catch (e, s) {
        _logger.warning('Dreaming FTS backfill failed', e, s);
      }
    });
  }

  static void reset() => _instance = null;

  /// Run one bounded Daily Dreaming fragment extraction batch for a character.
  ///
  /// The batch is capped to V3 § 10.4's 60-message limit. This method does not
  /// decide charging/Wi-Fi/idle policy; callers should invoke it only when the
  /// environment is appropriate.
  Future<DreamingFragmentPersistResult> runDailyFragmentBatch({
    required String characterId,
    required LLMClient client,
    required ModelConfig modelConfig,
    int batchSize = 60,
    String sourceScope = 'main_chat',
    DreamingFragmentExtractorV3 agent = const DreamingFragmentExtractorV3(),
  }) async {
    final cappedBatchSize = batchSize.clamp(1, 60).toInt();
    final lastMessageId = await _readWatermark(characterId);
    final rows = await (_db.select(_db.personaChatMessages)
          ..where((t) =>
              t.characterId.equals(characterId) &
              t.id.isBiggerThanValue(lastMessageId) &
              t.content.isNotValue('') &
              t.messageType.equals('chat'))
          ..orderBy([
            (t) => OrderingTerm.asc(t.id),
          ])
          ..limit(cappedBatchSize))
        .get();

    if (rows.isEmpty) {
      return DreamingFragmentPersistResult(
        fragmentIds: const [],
        entityIds: const [],
        processedMessageCount: 0,
        lastProcessedMessageId: lastMessageId,
        isEmpty: true,
      );
    }

    final inputs = rows
        .map((row) => DreamingChatMessageInput(
              id: row.id,
              isFromCharacter: row.isFromCharacter,
              content: row.content,
              timestamp: row.timestamp,
              messageType: row.messageType,
            ))
        .toList(growable: false);
    final existing = await _recentFragmentSummaries();
    final extracted = await agent.extract(
      client: client,
      modelConfig: modelConfig,
      messages: inputs,
      now: DateTime.now(),
      existingFragmentSummaries: existing,
    );
    final result = await persistFragments(
      extraction: extracted,
      processedMessageCount: rows.length,
      lastProcessedMessageId: rows.last.id,
      sourceScope: sourceScope,
    );
    await _writeWatermark(characterId, rows.last.id);
    return result;
  }

  /// Persist already-extracted Dreaming fragments.
  ///
  /// This is useful for tests and for future schedulers that may split LLM
  /// extraction from storage.
  Future<DreamingFragmentPersistResult> persistFragments({
    required DreamingFragmentExtraction extraction,
    required int processedMessageCount,
    required int lastProcessedMessageId,
    String sourceScope = 'main_chat',
  }) async {
    // Diagnostic: log entity link status for each fragment.
    for (final f in extraction.fragments) {
      _logger.info(
        'Fragment entityLinks diag: content="${f.content.length > 40 ? f.content.substring(0, 40) : f.content}..." '
        'entityLinkCount=${f.entityLinks.length}'
        '${f.entityLinks.isNotEmpty ? " first=${f.entityLinks.first.name}" : ""}',
      );
    }

    if (extraction.isEmpty) {
      return DreamingFragmentPersistResult(
        fragmentIds: const [],
        entityIds: const [],
        processedMessageCount: processedMessageCount,
        lastProcessedMessageId: lastProcessedMessageId,
        isEmpty: true,
      );
    }

    return _db.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final existingKeys = await _existingFragmentKeys();
      final seenThisBatch = <String>{};
      final fragmentIds = <String>[];
      final entityIds = <String>[];

      for (final draft in extraction.fragments) {
        final key = _dedupeKey(draft.content);
        if (key.isEmpty ||
            existingKeys.contains(key) ||
            seenThisBatch.contains(key) ||
            draft.sourceMessageIds.isEmpty) {
          continue;
        }
        final sourceMessages = await _sourceMessagesFor(draft.sourceMessageIds);
        if (!_passesRelationshipEvidenceGuard(draft, sourceMessages)) {
          continue;
        }
        seenThisBatch.add(key);

        final fragmentId = _uuid.v4();
        fragmentIds.add(fragmentId);

        final eventTime = _computeEventTime(sourceMessages);
        await _db.into(_db.memoryFragments).insert(
              MemoryFragmentsCompanion.insert(
                id: fragmentId,
                content: draft.content,
                sourceMessageIds: Value(jsonEncode(draft.sourceMessageIds)),
                sourceScope: Value(draft.sourceScope.isNotEmpty
                    ? draft.sourceScope
                    : sourceScope),
                emotionalWeight: Value(draft.emotionalWeight),
                isUserTruthCandidate: Value(draft.isUserTruthCandidate),
                generatedByVersion: const Value(_extractorVersion),
                createdAt: now,
                eventTime: Value(eventTime),
              ),
            );

        try {
          await _db.searchDao.upsertMemoryFragmentFts(
            fragmentId: fragmentId,
            content: draft.content,
          );
        } catch (e, s) {
          _logger.warning('FTS upsert failed for fragment $fragmentId', e, s);
        }

        for (final link in draft.entityLinks) {
          final entityId = await _resolveDreamingEntity(link, now: now);
          entityIds.add(entityId);
          await _db.into(_db.memoryEntityLinks).insert(
                MemoryEntityLinksCompanion.insert(
                  id: _uuid.v4(),
                  sourceTable: 'memory_fragments',
                  sourceId: fragmentId,
                  entityId: entityId,
                  relation: link.relation,
                  confidence: Value(link.confidence),
                  createdAt: now,
                ),
              );
        }
      }

      _logger.info(
        'Persisted ${fragmentIds.length} Dreaming fragment(s); '
        '${entityIds.toSet().length} linked entity/entities',
      );

      return DreamingFragmentPersistResult(
        fragmentIds: fragmentIds,
        entityIds: entityIds.toSet().toList(),
        processedMessageCount: processedMessageCount,
        lastProcessedMessageId: lastProcessedMessageId,
        isEmpty: fragmentIds.isEmpty,
      );
    });
  }

  /// Delete ALL Dreaming fragments, their entity links, and watermarks.
  ///
  /// This is a destructive reset for development / model-switching
  /// experiments. It does NOT touch memory_entities (they may be shared
  /// with memory_cards), nor does it touch any other table.
  ///
  /// Returns the number of fragment rows deleted.
  Future<int> clearAllFragments() async {
    return _db.transaction(() async {
      // 1) Delete entity links that point to fragments.
      final linkAffected = await (_db.delete(_db.memoryEntityLinks)
            ..where((t) => t.sourceTable.equals('memory_fragments')))
          .go();
      _logger.info('clearAllFragments: removed $linkAffected entity link(s)');

      // 2) Delete all fragments.
      final fragmentCount = await (_db.delete(_db.memoryFragments)).go();
      _logger.info('clearAllFragments: removed $fragmentCount fragment(s)');

      try {
        await _db.searchDao.clearMemoryFragmentFts();
      } catch (e, s) {
        _logger.warning('clearAllFragments: failed to clear FTS', e, s);
      }

      // 3) Wipe all dreaming watermarks so the next run starts from message 0.
      final wmAffected = await (_db.delete(_db.kvStore)
            ..where((t) => t.bucket.equals(_bucket)))
          .go();
      _logger.info('clearAllFragments: removed $wmAffected watermark(s)');

      return fragmentCount;
    });
  }

  /// Delete ALL Dreaming episodes and their entity links.
  ///
  /// This is a development reset for Episode prompt / model experiments. Any
  /// source fragments referenced by the deleted episodes are moved back to
  /// active so Episode consolidation can be rerun without re-extracting.
  ///
  /// Returns the number of episode rows deleted.
  Future<int> clearAllEpisodes() async {
    return _db.transaction(() async {
      final episodes = await _db.select(_db.memoryEpisodes).get();
      final sourceFragmentIds = <String>{};

      for (final episode in episodes) {
        try {
          final decoded = jsonDecode(episode.sourceFragmentIds);
          if (decoded is List) {
            sourceFragmentIds.addAll(decoded.whereType<String>());
          }
        } catch (_) {
          _logger.info(
            'clearAllEpisodes: ignored invalid sourceFragmentIds for '
            '${episode.id}',
          );
        }
      }

      final linkAffected = await (_db.delete(_db.memoryEntityLinks)
            ..where((t) => t.sourceTable.equals('memory_episodes')))
          .go();
      _logger.info('clearAllEpisodes: removed $linkAffected entity link(s)');

      final episodeCount = await (_db.delete(_db.memoryEpisodes)).go();
      _logger.info('clearAllEpisodes: removed $episodeCount episode(s)');

      try {
        await _db.searchDao.clearMemoryEpisodeFts();
      } catch (e, s) {
        _logger.warning('clearAllEpisodes: failed to clear FTS', e, s);
      }

      // Reset ALL consolidated fragments, not just the ones referenced by
      // episodes. Fragments can end up consolidated-but-unreferenced when the
      // LLM skips them during consolidation, leaving orphaned rows that would
      // otherwise be silently excluded from future consolidation runs.
      final fragmentAffected = await (_db.update(_db.memoryFragments)
            ..where((t) => t.status.equals('consolidated')))
          .write(const MemoryFragmentsCompanion(
        status: Value('active'),
      ));
      _logger.info(
        'clearAllEpisodes: reactivated $fragmentAffected fragment(s) '
        '(all consolidated, including ${sourceFragmentIds.length} episode-referenced)',
      );

      return episodeCount;
    });
  }

  /// Run Episode consolidation for all eligible active entities.
  ///
  /// Queries active entities that have ≥ 3 unconsolidated fragments, calls
  /// the Episode Consolidator (MAIN model) for each, and persists resulting
  /// episodes. Source fragments are marked status=consolidated.
  ///
  /// This is the MVP lab entry point. In production the threshold will be 5
  /// and the method will be called automatically after each Daily Dreaming
  /// fragment batch.
  Future<EpisodeConsolidationRunResult> runEpisodeConsolidation({
    required LLMClient client,
    required ModelConfig modelConfig,
    int minFragments = 2,
    int chunkSize = 40,
    EpisodeConsolidatorV3 agent = const EpisodeConsolidatorV3(),
  }) async {
    // Self-heal: reactivate any fragment stuck in 'consolidated' that is not
    // actually referenced by an episode. Such orphans arise when a prior bug
    // (or an episode deletion) retired a fragment without it ever being folded
    // into an episode. Without this, those fragments are invisible to
    // consolidation forever and never make it into an episode.
    final reactivated = await _reactivateOrphanConsolidatedFragments();
    if (reactivated > 0) {
      _logger.info(
        'Episode: reactivated $reactivated orphaned consolidated fragment(s) '
        'before consolidation',
      );
    }

    // Fetch all active fragments. Entity links are optional — the LLM
    // may not have generated them. We send ALL active fragments to the
    // consolidator and let it group related ones into episodes.
    final allFragments = await (_db.select(_db.memoryFragments)
          ..where((t) => t.status.equals('active'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();

    if (allFragments.isEmpty) {
      return EpisodeConsolidationRunResult(
        episodeIds: const [],
        consolidatedEntities: const [],
        skippedEntities: ['no active fragments'],
        consolidatedFragmentCount: 0,
      );
    }

    if (allFragments.length < minFragments) {
      return EpisodeConsolidationRunResult(
        episodeIds: const [],
        consolidatedEntities: const [],
        skippedEntities: [
          'only ${allFragments.length} fragments (need ≥$minFragments)'
        ],
        consolidatedFragmentCount: 0,
      );
    }

    // Split into chunks to stay under the ~130s API proxy timeout.
    final chunks = <List<MemoryFragment>>[];
    for (var i = 0; i < allFragments.length; i += chunkSize) {
      chunks.add(allFragments.sublist(
        i,
        i + chunkSize > allFragments.length
            ? allFragments.length
            : i + chunkSize,
      ));
    }

    _logger.info(
      'Episode: consolidating ${allFragments.length} active fragments '
      'in ${chunks.length} chunk(s) of ≤$chunkSize (entity-agnostic mode)',
    );

    final episodeIds = <String>[];
    final skippedEntities = <String>[];
    var totalConsolidatedFragments = 0;

    for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
      final chunk = chunks[chunkIndex];
      _logger.info(
        'Episode: chunk ${chunkIndex + 1}/${chunks.length} — ${chunk.length} fragments',
      );

      try {
        final result = await agent.consolidateAll(
          client: client,
          modelConfig: modelConfig,
          fragments: chunk,
        );

        if (result.episodes.isEmpty) {
          skippedEntities.add(result.skippedEntityIds.isNotEmpty
              ? result.skippedEntityIds.first
              : 'chunk ${chunkIndex + 1}: LLM returned no episodes');
          continue;
        }

        await _db.transaction(() async {
          final now = DateTime.now().millisecondsSinceEpoch;

          for (final episode in result.episodes) {
            final episodeId = _uuid.v4();
            final sourceEntityIds =
                await _entityIdsForFragments(episode.sourceFragmentIds);
            final primaryEntityId = await _primaryEntityIdForEpisode(
              sourceEntityIds: sourceEntityIds,
              preferredEntityId: episode.primaryEntityId,
              now: now,
            );
            final linkedEntityIds = {
              ...sourceEntityIds,
              ...episode.linkedEntityIds,
              primaryEntityId,
            };

            final computedRange =
                await _computeOccurredAtRange(episode.sourceFragmentIds);

            await _db.into(_db.memoryEpisodes).insert(
                  MemoryEpisodesCompanion.insert(
                    id: episodeId,
                    primaryEntityId: primaryEntityId,
                    topicId: Value(episode.topicId),
                    narrative: episode.narrative,
                    sourceFragmentIds: jsonEncode(episode.sourceFragmentIds),
                    significance: episode.significance,
                    confidence: episode.confidence,
                    valence: episode.valence,
                    arousal: episode.arousal,
                    occurredAtRange: Value(computedRange),
                    generatedByVersion:
                        const Value(_episodeConsolidatorVersion),
                    createdAt: now,
                    updatedAt: now,
                  ),
                );

            // Link each episode to the evidence-derived entities it actually
            // summarizes, so retrieval does not depend on topic labels.
            for (final linkedId in linkedEntityIds) {
              await _db.into(_db.memoryEntityLinks).insert(
                    MemoryEntityLinksCompanion.insert(
                      id: _uuid.v4(),
                      sourceTable: 'memory_episodes',
                      sourceId: episodeId,
                      entityId: linkedId,
                      relation:
                          linkedId == primaryEntityId ? 'about' : 'mentioned',
                      confidence: const Value(0.8),
                      createdAt: now,
                    ),
                  );
            }

            try {
              await _db.searchDao.upsertMemoryEpisodeFts(
                episodeId: episodeId,
                narrative: episode.narrative,
                topicId: episode.topicId,
              );
            } catch (e, s) {
              _logger.warning('FTS upsert failed for episode $episodeId', e, s);
            }

            episodeIds.add(episodeId);
          }

          // Mark source fragments as consolidated.
          for (final episode in result.episodes) {
            for (final fid in episode.sourceFragmentIds) {
              await (_db.update(_db.memoryFragments)
                    ..where((t) => t.id.equals(fid)))
                  .write(const MemoryFragmentsCompanion(
                status: Value('consolidated'),
              ));
            }
            totalConsolidatedFragments += episode.sourceFragmentIds.length;
          }
        });

        _logger.info(
          'Episode: chunk ${chunkIndex + 1}/${chunks.length} persisted '
          '${result.episodes.length} episode(s)',
        );
      } catch (e, stack) {
        _logger.warning(
          'Episode consolidation failed at chunk ${chunkIndex + 1}/${chunks.length}',
          e,
          stack,
        );
        skippedEntities.add('chunk ${chunkIndex + 1} error: $e');
      }
    }

    _logger.info(
      'Episode: persisted ${episodeIds.length} total episode(s) from '
      '$totalConsolidatedFragments fragments across ${chunks.length} chunk(s)',
    );

    return EpisodeConsolidationRunResult(
      episodeIds: episodeIds,
      consolidatedEntities: episodeIds,
      skippedEntities: skippedEntities,
      consolidatedFragmentCount: totalConsolidatedFragments,
    );
  }

  Future<int> _readWatermark(String characterId) async {
    final row = await (_db.select(_db.kvStore)
          ..where((t) =>
              t.key.equals(_watermarkKey(characterId)) &
              t.bucket.equals(_bucket)))
        .getSingleOrNull();
    return int.tryParse(row?.value ?? '') ?? 0;
  }

  Future<void> _writeWatermark(String characterId, int messageId) async {
    await _db.into(_db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: _watermarkKey(characterId),
            value: Value('$messageId'),
            bucket: const Value(_bucket),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  String _watermarkKey(String characterId) =>
      'dreaming.fragment.last_message_id.$characterId';

  Future<List<String>> _recentFragmentSummaries({int limit = 120}) async {
    final rows = await (_db.select(_db.memoryFragments)
          ..where((t) => t.status.isNotIn(const ['deleted']))
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
          ])
          ..limit(limit))
        .get();
    return rows.map((row) => row.content).toList(growable: false);
  }

  Future<Set<String>> _existingFragmentKeys() async {
    final rows = await (_db.select(_db.memoryFragments)
          ..where((t) => t.status.isNotIn(const ['deleted'])))
        .get();
    return rows.map((row) => _dedupeKey(row.content)).toSet();
  }

  String _dedupeKey(String content) =>
      content.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  Future<List<PersonaChatMessage>> _sourceMessagesFor(List<int> ids) async {
    final result = <PersonaChatMessage>[];
    for (final id in ids.toSet()) {
      final row = await (_db.select(_db.personaChatMessages)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row != null) {
        result.add(row);
      }
    }
    return result;
  }

  int? _computeEventTime(List<PersonaChatMessage> messages) {
    if (messages.isEmpty) return null;
    final timestamps = messages.map((m) => m.timestamp.millisecondsSinceEpoch);
    return timestamps.reduce((a, b) => a < b ? a : b);
  }

  Future<String?> _computeOccurredAtRange(List<String> fragmentIds) async {
    if (fragmentIds.isEmpty) return null;
    final rows = await (_db.select(_db.memoryFragments)
          ..where((t) => t.id.isIn(fragmentIds) & t.eventTime.isNotNull()))
        .get();
    if (rows.isEmpty) return null;
    final times = rows.map((r) => r.eventTime!).toList();
    final minMs = times.reduce((a, b) => a < b ? a : b);
    final maxMs = times.reduce((a, b) => a > b ? a : b);
    final start = DateTime.fromMillisecondsSinceEpoch(minMs).toIso8601String();
    final end = DateTime.fromMillisecondsSinceEpoch(maxMs).toIso8601String();
    return jsonEncode({'start': start, 'end': end});
  }

  Future<int> recomputeAllEpisodeOccurredAtRange() async {
    final episodes = await _db.select(_db.memoryEpisodes).get();
    _logger.info(
        'recomputeAllEpisodeOccurredAtRange: ${episodes.length} episodes');
    var updated = 0;
    for (final ep in episodes) {
      final fragIds =
          (jsonDecode(ep.sourceFragmentIds) as List).cast<String>();
      final range = await _computeOccurredAtRange(fragIds);
      if (range != null && range != ep.occurredAtRange) {
        await (_db.update(_db.memoryEpisodes)
              ..where((t) => t.id.equals(ep.id)))
            .write(MemoryEpisodesCompanion(occurredAtRange: Value(range)));
        updated++;
      }
    }
    _logger.info('recomputeAllEpisodeOccurredAtRange: updated $updated');
    return updated;
  }

  Future<void> backfillFragmentEventTimes() async {
    final rows = await (_db.select(_db.memoryFragments)
          ..where((t) => t.eventTime.isNull() & t.sourceMessageIds.isNotNull()))
        .get();
    _logger.info('backfillFragmentEventTimes: ${rows.length} fragments to fill');
    var filled = 0;
    for (final frag in rows) {
      final ids = (jsonDecode(frag.sourceMessageIds!) as List).cast<int>();
      if (ids.isEmpty) continue;
      final messages = await _sourceMessagesFor(ids);
      final et = _computeEventTime(messages);
      if (et != null) {
        await (_db.update(_db.memoryFragments)
              ..where((t) => t.id.equals(frag.id)))
            .write(MemoryFragmentsCompanion(eventTime: Value(et)));
        filled++;
      }
    }
    _logger.info('backfillFragmentEventTimes: filled $filled');
  }

  Future<List<String>> _entityIdsForFragments(List<String> fragmentIds) async {
    if (fragmentIds.isEmpty) {
      return const [];
    }
    final links = await (_db.select(_db.memoryEntityLinks)
          ..where((t) =>
              t.sourceTable.equals('memory_fragments') &
              t.sourceId.isIn(fragmentIds)))
        .get();
    return links
        .map((link) => link.entityId)
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  Future<String> _primaryEntityIdForEpisode({
    required List<String> sourceEntityIds,
    required String preferredEntityId,
    required int now,
  }) async {
    final preferred = preferredEntityId.trim();
    if (preferred.isNotEmpty &&
        await _memoryEntityExists(preferred) &&
        !_isKnownDreamingTopic(preferred)) {
      return preferred;
    }

    if (sourceEntityIds.contains('user_self')) {
      return 'user_self';
    }
    if (sourceEntityIds.isNotEmpty) {
      return sourceEntityIds.first;
    }
    return _ensureUserSelfEntity(now: now);
  }

  Future<bool> _memoryEntityExists(String entityId) async {
    final row = await (_db.select(_db.memoryEntities)
          ..where((t) =>
              t.id.equals(entityId) &
              t.status.isNotIn(const ['deleted', 'merged'])))
        .getSingleOrNull();
    return row != null;
  }

  bool _isKnownDreamingTopic(String value) {
    const topics = {
      'work_routine',
      'commute',
      'sleep_environment',
      'self_image',
      'food_place',
      'creative_project',
      'product_interest',
      'relationship_care',
      'intimacy_private',
      '__ungrouped__',
    };
    return topics.contains(value);
  }

  Future<String> _ensureUserSelfEntity({required int now}) async {
    final existing = await (_db.select(_db.memoryEntities)
          ..where((t) => t.id.equals('user_self')))
        .getSingleOrNull();
    if (existing != null) {
      return existing.id;
    }
    await _db.into(_db.memoryEntities).insert(
          MemoryEntitiesCompanion.insert(
            id: 'user_self',
            name: 'user_self',
            category: 'self',
            status: const Value('seed'),
            relationshipToUser: const Value('self'),
            firstMentionedAt: Value(now),
            lastMentionedAt: Value(now),
            fragmentCount: const Value(0),
            generatedByVersion: const Value(_episodeConsolidatorVersion),
          ),
        );
    return 'user_self';
  }

  bool _passesRelationshipEvidenceGuard(
    DreamingFragmentDraft draft,
    List<PersonaChatMessage> sourceMessages,
  ) {
    final content = draft.content.trim();
    if (content.isEmpty || sourceMessages.isEmpty) {
      _logger.info('Rejected Dreaming fragment with missing source evidence');
      return false;
    }
    if (content.contains('用户') || content.contains('对方')) {
      _logger.info('Rejected Dreaming fragment with system/vague subject: '
          '$content');
      return false;
    }
    if (_containsRuntimeError(content) ||
        sourceMessages.any((m) => _containsRuntimeError(m.content))) {
      _logger.info('Rejected Dreaming fragment sourced from runtime error: '
          '$content');
      return false;
    }
    if (_looksLikeBarePsychDoctorJoke(draft, sourceMessages)) {
      _logger.info('Rejected Dreaming fragment: bare psych-doctor joke: '
          '$content');
      return false;
    }
    if (_addsUnsupportedCounselingConclusion(draft, sourceMessages)) {
      _logger.info('Rejected Dreaming fragment: unsupported counseling '
          'conclusion: $content');
      return false;
    }
    return true;
  }

  bool _containsRuntimeError(String text) {
    return text.contains('Connection interrupted') ||
        text.contains('AgentException') ||
        text.contains('model_not_found') ||
        text.contains('503 Service Unavailable');
  }

  bool _looksLikeBarePsychDoctorJoke(
    DreamingFragmentDraft draft,
    List<PersonaChatMessage> sourceMessages,
  ) {
    final content = draft.content;
    if (!content.contains('心理医生')) return false;

    final userTexts = sourceMessages
        .where((m) => !m.isFromCharacter)
        .map((m) => _compactChinese(m.content))
        .toList(growable: false);
    final hasBareReply = userTexts.any((text) =>
        RegExp(r'^(嗯+|嗯嗯|哈哈|哈|行|好)?，?心理医生来了[。！!～~]*$').hasMatch(text));
    if (!hasBareReply) return false;

    const explicitLifeCues = [
      '预约',
      '咨询',
      '复诊',
      '治疗',
      '见心理医生',
      '我的心理医生',
      '心理咨询',
      '医生到了',
      '到了医院',
    ];
    return !userTexts.any(
      (text) => explicitLifeCues.any(text.contains),
    );
  }

  bool _addsUnsupportedCounselingConclusion(
    DreamingFragmentDraft draft,
    List<PersonaChatMessage> sourceMessages,
  ) {
    final content = draft.content;
    if (!content.contains('心理医生') &&
        !content.contains('心理咨询') &&
        !content.contains('咨询')) {
      return false;
    }
    const conclusionCues = [
      '刚结束',
      '结束咨询',
      '刚做完',
      '刚咨询',
      '心理咨询',
    ];
    if (!conclusionCues.any(content.contains)) return false;

    final sourceText = sourceMessages.map((m) => m.content).join('\n');
    return !conclusionCues.any(sourceText.contains);
  }

  String _compactChinese(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('，', ',')
        .replaceAll(',', '，')
        .trim();
  }

  Future<String> _resolveDreamingEntity(
    DreamingEntityLinkDraft link, {
    required int now,
  }) async {
    final canonicalSelf = link.name.trim() == 'user_self';
    // When searching for user_self, prefer the canonical id='user_self' entity,
    // then fall back to name match (there may be a pre-canonical clone).
    final candidates = <MemoryEntity>[];
    if (canonicalSelf) {
      candidates.addAll(await (_db.select(_db.memoryEntities)
            ..where((t) =>
                t.id.equals('user_self') &
                t.status.isNotIn(const ['deleted', 'merged'])))
          .get());
    }
    if (candidates.isEmpty) {
      candidates.addAll(await (_db.select(_db.memoryEntities)
            ..where((t) =>
                t.name.lower().equals(link.name.toLowerCase()) &
                t.status.isNotIn(const ['deleted', 'merged'])))
          .get());
    }
    // Prefer the entity with the most fragments (the active one).
    candidates.sort((a, b) => b.fragmentCount.compareTo(a.fragmentCount));
    final existing = candidates.isNotEmpty ? candidates.first : null;

    if (existing != null) {
      final nextCount = existing.fragmentCount + 1;
      final firstMentionedAt = existing.firstMentionedAt ?? now;
      final shouldPromote = existing.status == 'seed' &&
          nextCount >= 3 &&
          now - firstMentionedAt >= const Duration(days: 2).inMilliseconds;
      await (_db.update(_db.memoryEntities)
            ..where((t) => t.id.equals(existing.id)))
          .write(
        MemoryEntitiesCompanion(
          lastMentionedAt: Value(now),
          firstMentionedAt: Value(firstMentionedAt),
          fragmentCount: Value(nextCount),
          status: shouldPromote ? const Value('active') : const Value.absent(),
        ),
      );
      return existing.id;
    }

    final id = canonicalSelf ? 'user_self' : _uuid.v4();
    await _db.into(_db.memoryEntities).insert(
          MemoryEntitiesCompanion.insert(
            id: id,
            name: link.name,
            category: link.category,
            status: const Value('seed'),
            relationshipToUser: Value(link.relationshipToUser),
            firstMentionedAt: Value(now),
            lastMentionedAt: Value(now),
            fragmentCount: const Value(1),
            generatedByVersion: const Value(_extractorVersion),
          ),
        );
    return id;
  }

  // ---------------------------------------------------------------------------
  // Non-LLM maintenance (Lightweight Tick)
  // ---------------------------------------------------------------------------

  /// Mark fragments as `consolidated` when they are linked to an existing
  /// episode via entity_links. Returns the number of fragments updated.
  Future<int> resolveStaleFragments(String characterId) async {
    // A fragment is "consumed" only when it has actually been folded into an
    // episode — i.e. its id appears in some episode's sourceFragmentIds.
    //
    // NOTE: we must NOT use memory_entity_links as the signal here. Entity
    // links are created at fragment EXTRACTION time (every extracted fragment
    // gets one), so keying off link presence retires fragments the moment they
    // are born — before consolidation ever runs. That silently starved episode
    // consolidation of its inputs (it always saw 0 active fragments).
    final episodeRows = await (_db.select(_db.memoryEpisodes)).get();
    final consumedIds = <String>{};
    for (final ep in episodeRows) {
      try {
        final decoded = jsonDecode(ep.sourceFragmentIds);
        if (decoded is List) {
          consumedIds.addAll(decoded.whereType<String>());
        }
      } catch (_) {
        // Malformed JSON — skip, don't let one bad row abort the sweep.
      }
    }

    if (consumedIds.isEmpty) return 0;

    final affected = await (_db.update(_db.memoryFragments)
          ..where((t) => t.id.isIn(consumedIds) & t.status.equals('active')))
        .write(const MemoryFragmentsCompanion(status: Value('consolidated')));

    return affected;
  }

  /// Reactivate fragments stuck in status='consolidated' that are not
  /// referenced by any episode's sourceFragmentIds. Returns the count changed.
  ///
  /// Shares the "consumed = referenced by an episode" definition with
  /// [resolveStaleFragments] — the two are inverses and must stay consistent.
  Future<int> _reactivateOrphanConsolidatedFragments() async {
    final episodeRows = await (_db.select(_db.memoryEpisodes)).get();
    final consumedIds = <String>{};
    for (final ep in episodeRows) {
      try {
        final decoded = jsonDecode(ep.sourceFragmentIds);
        if (decoded is List) {
          consumedIds.addAll(decoded.whereType<String>());
        }
      } catch (_) {
        // Malformed JSON — skip.
      }
    }

    final query = _db.update(_db.memoryFragments)
      ..where((t) => t.status.equals('consolidated'));
    // Exclude genuinely-consumed fragments from reactivation.
    if (consumedIds.isNotEmpty) {
      query.where((t) => t.id.isNotIn(consumedIds));
    }
    return query.write(const MemoryFragmentsCompanion(status: Value('active')));
  }

  /// table. Returns the number of entities updated.
  Future<int> syncEntityFragmentCounts() async {
    final entities = await (_db.select(_db.memoryEntities)
          ..where((t) => t.status.isNotIn(const ['deleted', 'merged'])))
        .get();

    var updated = 0;
    for (final entity in entities) {
      final count = await (_db.select(_db.memoryEntityLinks)
            ..where((t) =>
                t.entityId.equals(entity.id) &
                t.sourceTable.equals('memory_fragments')))
          .get()
          .then((rows) => rows.length);

      if (count != entity.fragmentCount) {
        await (_db.update(_db.memoryEntities)
              ..where((t) => t.id.equals(entity.id)))
            .write(MemoryEntitiesCompanion(fragmentCount: Value(count)));
        updated++;
      }
    }

    return updated;
  }

  /// Returns true if today's daily dreaming batch has already completed for
  /// [characterId].
  Future<bool> hasDailyBatchRunToday(String characterId) async {
    final row = await (_db.select(_db.kvStore)
          ..where((t) =>
              t.bucket.equals(_bucket) &
              t.key.equals('daily_batch.last_run.$characterId')))
        .getSingleOrNull();
    if (row == null) return false;

    final lastRun = int.tryParse(row.value ?? '');
    if (lastRun == null) return false;

    final lastRunDate = DateTime.fromMillisecondsSinceEpoch(lastRun);
    final today = DateTime.now();
    return lastRunDate.year == today.year &&
        lastRunDate.month == today.month &&
        lastRunDate.day == today.day;
  }

  /// Record that today's daily dreaming batch completed for [characterId].
  Future<void> markDailyBatchComplete(String characterId) async {
    await _db.into(_db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion(
            bucket: const Value(_bucket),
            key: Value('daily_batch.last_run.$characterId'),
            value: Value(DateTime.now().millisecondsSinceEpoch.toString()),
          ),
        );
  }

  /// Return recent dreaming output for companion context injection.
  ///
  /// When [queryHint] is non-empty, episodes and fragments are ranked by FTS5
  /// bm25 (jieba-tokenized) first, then any remaining slots are filled with
  /// significance/recency-ordered rows so the companion never sees an empty
  /// context. FTS-matched entries carry a positive [score]; recency fills
  /// carry score=0, which the Lab recall log surfaces plainly.
  Future<DreamingContextQueryResult> queryRecentDreamingContext({
    String queryHint = '',
    int episodeLimit = 8,
    int recentFragmentLimit = 6,
  }) async {
    final trimmedHint = queryHint.trim();

    final episodeHits = await _queryEpisodesForContext(
      queryHint: trimmedHint,
      limit: episodeLimit,
    );
    final fragmentHits = await _queryFragmentsForContext(
      queryHint: trimmedHint,
      limit: recentFragmentLimit,
    );

    return DreamingContextQueryResult(
      episodeHits: episodeHits,
      fragmentHits: fragmentHits,
    );
  }

  Future<List<DreamingEpisodeContextHit>> _queryEpisodesForContext({
    required String queryHint,
    required int limit,
  }) async {
    final ftsHits = <DreamingEpisodeContextHit>[];
    final seenIds = <String>{};

    if (queryHint.isNotEmpty) {
      try {
        final rows = await _db.searchDao.searchMemoryEpisodes(
          queryHint,
          limit: limit * 3,
        );
        if (rows.isNotEmpty) {
          final ranks = <String, double>{
            for (final row in rows)
              row['episode_id'] as String: (row['rank'] as num).toDouble(),
          };
          final activeRows = await (_db.select(_db.memoryEpisodes)
                ..where((t) =>
                    t.id.isIn(ranks.keys.toList(growable: false)) &
                    t.status.equals('active')))
              .get();
          activeRows.sort(
              (a, b) => (ranks[a.id] ?? 0).compareTo(ranks[b.id] ?? 0));
          for (final ep in activeRows) {
            if (ftsHits.length >= limit) break;
            if (seenIds.add(ep.id)) {
              ftsHits.add(DreamingEpisodeContextHit(
                episode: ep,
                score: _bm25ToScore(ranks[ep.id]),
              ));
            }
          }
        }
      } catch (e, s) {
        _logger.warning(
            'Episode FTS search failed; falling back to recency', e, s);
      }
    }

    // Substring fallback: when FTS returned nothing but we have content
    // keywords, do an in-memory substring scan over a broader pool of active
    // episodes. This catches short queries like "破甲" that FTS misses.
    if (ftsHits.isEmpty && queryHint.isNotEmpty) {
      try {
        final keywords = await QueryMatcher.contentKeywords(queryHint);
        if (keywords.isNotEmpty) {
          final pool = await (_db.select(_db.memoryEpisodes)
                ..where((t) => t.status.equals('active'))
                ..orderBy([
                  (t) => OrderingTerm.desc(t.significance),
                  (t) => OrderingTerm.desc(t.createdAt),
                ])
                ..limit(limit * 5))
              .get();
          for (final ep in pool) {
            if (ftsHits.length >= limit) break;
            final narrative = ep.narrative.toLowerCase();
            final hits =
                keywords.where((kw) => narrative.contains(kw)).length;
            if (hits > 0 && seenIds.add(ep.id)) {
              ftsHits.add(DreamingEpisodeContextHit(
                episode: ep,
                score: hits * 5,
              ));
            }
          }
        }
      } catch (e, s) {
        _logger.warning('Episode substring fallback failed', e, s);
      }
    }

    if (ftsHits.length >= limit) {
      return List.unmodifiable(ftsHits);
    }

    final fillQuery = _db.select(_db.memoryEpisodes)
      ..where((t) => t.status.equals('active'))
      ..orderBy([
        (t) => OrderingTerm.desc(t.significance),
        (t) => OrderingTerm.desc(t.createdAt),
      ])
      ..limit(limit + seenIds.length);
    if (seenIds.isNotEmpty) {
      fillQuery.where((t) => t.id.isNotIn(seenIds.toList(growable: false)));
    }
    final fillRows = await fillQuery.get();

    final result = List<DreamingEpisodeContextHit>.of(ftsHits);
    for (final ep in fillRows) {
      if (result.length >= limit) break;
      result.add(DreamingEpisodeContextHit(episode: ep, score: 0));
    }
    return List.unmodifiable(result);
  }

  Future<List<DreamingFragmentContextHit>> _queryFragmentsForContext({
    required String queryHint,
    required int limit,
  }) async {
    final ftsHits = <DreamingFragmentContextHit>[];
    final seenIds = <String>{};

    if (queryHint.isNotEmpty) {
      try {
        final rows = await _db.searchDao.searchMemoryFragments(
          queryHint,
          limit: limit * 4,
        );
        if (rows.isNotEmpty) {
          final ranks = <String, double>{
            for (final row in rows)
              row['fragment_id'] as String: (row['rank'] as num).toDouble(),
          };
          final activeRows = await (_db.select(_db.memoryFragments)
                ..where((t) =>
                    t.id.isIn(ranks.keys.toList(growable: false)) &
                    t.status.equals('active')))
              .get();
          activeRows.sort(
              (a, b) => (ranks[a.id] ?? 0).compareTo(ranks[b.id] ?? 0));
          for (final fr in activeRows) {
            if (ftsHits.length >= limit) break;
            if (seenIds.add(fr.id)) {
              ftsHits.add(DreamingFragmentContextHit(
                fragment: fr,
                score: _bm25ToScore(ranks[fr.id]),
              ));
            }
          }
        }
      } catch (e, s) {
        _logger.warning(
            'Fragment FTS search failed; falling back to recency', e, s);
      }
    }

    if (ftsHits.isEmpty && queryHint.isNotEmpty) {
      try {
        final keywords = await QueryMatcher.contentKeywords(queryHint);
        if (keywords.isNotEmpty) {
          final pool = await (_db.select(_db.memoryFragments)
                ..where((t) => t.status.equals('active'))
                ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
                ..limit(limit * 6))
              .get();
          for (final fr in pool) {
            if (ftsHits.length >= limit) break;
            final content = fr.content.toLowerCase();
            final hits =
                keywords.where((kw) => content.contains(kw)).length;
            if (hits > 0 && seenIds.add(fr.id)) {
              ftsHits.add(DreamingFragmentContextHit(
                fragment: fr,
                score: hits * 5,
              ));
            }
          }
        }
      } catch (e, s) {
        _logger.warning('Fragment substring fallback failed', e, s);
      }
    }

    if (ftsHits.length >= limit) {
      return List.unmodifiable(ftsHits);
    }

    final fillQuery = _db.select(_db.memoryFragments)
      ..where((t) => t.status.equals('active'))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit + seenIds.length);
    if (seenIds.isNotEmpty) {
      fillQuery.where((t) => t.id.isNotIn(seenIds.toList(growable: false)));
    }
    final fillRows = await fillQuery.get();

    final result = List<DreamingFragmentContextHit>.of(ftsHits);
    for (final fr in fillRows) {
      if (result.length >= limit) break;
      result.add(DreamingFragmentContextHit(fragment: fr, score: 0));
    }
    return List.unmodifiable(result);
  }

  /// Convert an FTS5 bm25 rank (negative float, more-negative = better match)
  /// into the positive integer score the recall log stores. A typical strong
  /// bm25 match ~ -3.0 → 30; borderline ~ -0.5 → 5. Clamped defensively.
  int _bm25ToScore(double? rank) {
    if (rank == null) return 0;
    final score = (-rank * 10).round();
    if (score < 0) return 0;
    if (score > 9999) return 9999;
    return score;
  }

  /// Rebuild the fragment FTS index from all non-deleted rows. Idempotent and
  /// safe to run on every launch; scheduled from [init].
  Future<int> reindexAllFragments() async {
    final rows = await (_db.select(_db.memoryFragments)
          ..where((t) => t.status.isNotIn(const ['deleted'])))
        .get();
    var count = 0;
    for (final row in rows) {
      try {
        await _db.searchDao.upsertMemoryFragmentFts(
          fragmentId: row.id,
          content: row.content,
        );
        count++;
      } catch (e, s) {
        _logger.warning('reindexAllFragments: failed for ${row.id}', e, s);
      }
    }
    return count;
  }

  /// Rebuild the episode FTS index from all non-deleted rows. Idempotent and
  /// safe to run on every launch; scheduled from [init].
  Future<int> reindexAllEpisodes() async {
    final rows = await (_db.select(_db.memoryEpisodes)
          ..where((t) => t.status.isNotIn(const ['deleted'])))
        .get();
    var count = 0;
    for (final row in rows) {
      try {
        await _db.searchDao.upsertMemoryEpisodeFts(
          episodeId: row.id,
          narrative: row.narrative,
          topicId: row.topicId,
        );
        count++;
      } catch (e, s) {
        _logger.warning('reindexAllEpisodes: failed for ${row.id}', e, s);
      }
    }
    return count;
  }
}
