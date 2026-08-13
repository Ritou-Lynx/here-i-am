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
import 'package:memex/data/memory_v3/agents/dreaming_agent/saga_weaver.dart';
import 'package:memex/data/memory_v3/models/dreaming_fragment.dart';
import 'package:memex/data/memory_v3/retrieval/recall_novelty_policy.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/data/memory_v3/services/embedding_service.dart';
import 'package:memex/data/memory_v3/services/memory_recall_trace_service.dart';
import 'package:memex/data/services/search/query_matcher.dart';
import 'package:memex/utils/logger.dart';
import 'package:uuid/uuid.dart';

final _logger = getLogger('memory_v3.DreamingOrchestratorService');

class DreamingFragmentPersistResult {
  DreamingFragmentPersistResult({
    required this.fragmentIds,
    this.fragmentContents = const {},
    required this.entityIds,
    required this.processedMessageCount,
    required this.lastProcessedMessageId,
    required this.isEmpty,
    this.coveredMessageIds = const [],
  });

  final List<String> fragmentIds;
  final Map<String, String> fragmentContents;
  final List<String> entityIds;
  final int processedMessageCount;
  final int lastProcessedMessageId;
  final bool isEmpty;

  /// Message ids that were referenced by at least one persisted fragment in
  /// this batch. Used by [runDailyFragmentBatch] to advance the watermark only
  /// past messages the model actually evaluated, preventing silent drops
  /// when the LLM only processes the first few messages of a large batch.
  final List<int> coveredMessageIds;
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

class SagaWeavingRunResult {
  SagaWeavingRunResult({
    required this.sagaIds,
    required this.updatedSagaIds,
    required this.skippedReasons,
  });

  final List<String> sagaIds;
  final List<String> updatedSagaIds;
  final List<String> skippedReasons;

  bool get isEmpty => sagaIds.isEmpty && updatedSagaIds.isEmpty;
}

/// Audit record of a Dreaming batch window that produced no memory.
///
/// reason 'error': extraction threw; the window never reached memory and
/// can be re-run via [retrySkippedRange].
/// reason 'empty': the LLM evaluated the window and returned zero drafts.
/// Also re-runnable — the model may have under-extracted.
class DreamingSkipRecord {
  const DreamingSkipRecord({
    required this.fromId,
    required this.toId,
    required this.reason,
    required this.at,
    this.error,
  });

  final int fromId;
  final int toId;
  final String reason; // 'error' | 'empty'
  final int at; // ms epoch
  final String? error; // truncated error text, error records only

  Map<String, dynamic> toJson() => {
        'fromId': fromId,
        'toId': toId,
        'reason': reason,
        'at': at,
        if (error != null) 'error': error,
      };

  static DreamingSkipRecord? fromJson(Object? raw) {
    try {
      final map = raw as Map;
      return DreamingSkipRecord(
        fromId: (map['fromId'] as num).toInt(),
        toId: (map['toId'] as num).toInt(),
        reason: map['reason'] as String,
        at: (map['at'] as num).toInt(),
        error: map['error'] as String?,
      );
    } catch (_) {
      return null; // corrupted entry — skip it, don't abort the list
    }
  }
}

/// Outcome of [retrySkippedRange] for Lab display.
class DreamingRetryResult {
  const DreamingRetryResult({
    required this.processedMessageCount,
    required this.fragmentCount,
    required this.message,
  });

  final int processedMessageCount;
  final int fragmentCount;
  final String message;
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
  static const _sagaWeaverVersion = 'dreaming.saga_weaver.v3.0';

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
        final sg = await _instance!.reindexAllSagas();
        _logger.info(
            'Dreaming FTS backfill: $ep episode(s), $fr fragment(s), $sg saga(s) indexed');
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
  /// The batch is capped to [batchSize] (default 30). This method does not
  /// decide charging/Wi-Fi/idle policy; callers should invoke it only when
  /// the environment is appropriate.
  ///
  /// Watermark advancement (coverage-aware):
  /// - **Extraction throws** (model refusal, invalid JSON, API error): the
  ///   watermark advances past the whole batch so the next run does not
  ///   re-read and re-fail on the same messages. The batch's fragments are
  ///   lost; this is the correct trade-off to avoid permanently stalling
  ///   Dreaming for a character.
  /// - **Extraction succeeds with fragments**: the watermark advances only
  ///   to the last message id actually referenced by a persisted fragment.
  ///   If the model only processed the first N of M messages (attention
  ///   decay on large batches), the remaining M-N messages will be re-read
  ///   by the next batch. This prevents silent permanent loss of memories.
  /// - **Extraction succeeds with zero fragments**: the model evaluated all
  ///   messages and found no relationship evidence. The watermark advances
  ///   past the whole batch.
  Future<DreamingFragmentPersistResult> runDailyFragmentBatch({
    required String characterId,
    required LLMClient client,
    required ModelConfig modelConfig,
    int batchSize = 30,
    int? startAfterId,
    String sourceScope = 'main_chat',
    DreamingFragmentExtractorV3 agent = const DreamingFragmentExtractorV3(),
  }) async {
    final cappedBatchSize = batchSize.clamp(1, 30).toInt();
    final lastMessageId = startAfterId ?? await _readWatermark(characterId);
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

    DreamingFragmentExtraction extracted;
    try {
      extracted = await agent.extract(
        client: client,
        modelConfig: modelConfig,
        messages: inputs,
        now: DateTime.now(),
        existingFragmentSummaries: existing,
      );
    } catch (e, s) {
      // Advance the watermark past this batch so the next run does not
      // re-read and re-fail on the same messages. The batch's fragments are
      // lost, but future batches will process future messages normally.
      _logger.warning(
        'Fragment extraction failed for $characterId; advancing watermark '
        'to ${rows.last.id} to avoid retrying the same failed batch. '
        'Error: $e',
        e,
        s,
      );
      // Never regress the watermark: a manual retry of an OLD range that
      // fails again must not pull the scheduler back over already-processed
      // messages. The failure window itself is audited so it can be retried.
      await _advanceWatermark(characterId, rows.last.id);
      await _appendSkipRecord(
        characterId: characterId,
        fromId: lastMessageId + 1,
        toId: rows.last.id,
        reason: 'error',
        error: e.toString().length > 200
            ? e.toString().substring(0, 200)
            : e.toString(),
      );
      rethrow;
    }
    final result = await persistFragments(
      extraction: extracted,
      processedMessageCount: rows.length,
      lastProcessedMessageId: rows.last.id,
      sourceScope: sourceScope,
    );

    // Coverage-aware watermark advancement.
    //
    // When the LLM only extracts fragments for the first few messages of a
    // large batch (a common attention-decay failure mode), advancing the
    // watermark to rows.last.id would silently drop the remaining messages
    // forever. Instead, advance only to the last message id that the model
    // actually referenced in a persisted fragment. The un-processed tail will
    // be re-read by the next batch.
    //
    // When the model returns zero fragments (it evaluated all messages and
    // found no relationship evidence), coveredMessageIds is empty — in that
    // case we advance to rows.last.id because the messages were evaluated,
    // just not worth extracting.
    final batchMessageIds = rows.map((r) => r.id).toSet();
    final coveredInBatch = result.coveredMessageIds
        .where((id) => batchMessageIds.contains(id))
        .toList();
    final int newWatermark;
    if (coveredInBatch.isEmpty) {
      // Model returned empty (all evaluated, no evidence) or all fragments
      // were dropped by dedupe. Advance past the whole batch.
      newWatermark = rows.last.id;
      // Audit only genuine zero-draft evaluations (nothing was skipped there
      // — but the user deserves to know the window produced no memory).
      // All-deduped batches (content already in memory) are NOT recorded.
      if (extracted.fragments.isEmpty) {
        await _appendSkipRecord(
          characterId: characterId,
          fromId: lastMessageId + 1,
          toId: rows.last.id,
          reason: 'empty',
        );
      }
    } else {
      // Advance to the last covered message, but never beyond the batch.
      final maxCovered = coveredInBatch.reduce((a, b) => a > b ? a : b);
      newWatermark = maxCovered < rows.last.id ? maxCovered : rows.last.id;
    }
    await _advanceWatermark(characterId, newWatermark);

    if (newWatermark < rows.last.id) {
      _logger.warning(
        'Fragment batch partial coverage for $characterId: '
        '${rows.length} messages read (id ${rows.first.id}→${rows.last.id}), '
        'but model only covered up to id $newWatermark. '
        'Watermark advanced to $newWatermark; ${rows.last.id - newWatermark} '
        'message(s) will be re-read next batch.',
      );
    }

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
        coveredMessageIds: const [],
      );
    }

    final result = await _db.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final existingKeys = await _existingFragmentKeys();
      final coveredSourceIds = await _coveredSourceMessageIds();
      final seenThisBatch = <String>{};
      final fragmentIds = <String>[];
      final fragmentContents = <String, String>{}; // id → content
      final entityIds = <String>[];
      final batchCoveredMessageIds = <int>{};

      for (final draft in extraction.fragments) {
        final key = _dedupeKey(draft.content);
        if (key.isEmpty ||
            existingKeys.contains(key) ||
            seenThisBatch.contains(key) ||
            draft.sourceMessageIds.isEmpty) {
          continue;
        }
        // Source-message dedupe: if every source message this draft
        // references is already covered by an existing fragment, drop
        // it. This prevents a watermark-reset batch from producing
        // near-duplicates of fragments the previous model already
        // extracted (LLMs re-extract with slightly different wording,
        // so content-hash alone is not enough). Partial overlap is
        // allowed, so the new batch can still produce complementary
        // observations for messages it never got to before.
        final uncoveredSources = draft.sourceMessageIds
            .where((id) => !coveredSourceIds.contains(id))
            .toList();
        if (uncoveredSources.isEmpty) {
          _logger.info(
            'Drop fragment whose source messages are already covered: '
            '${draft.content.substring(0, draft.content.length.clamp(0, 60))}',
          );
          continue;
        }
        final sourceMessages = await _sourceMessagesFor(draft.sourceMessageIds);
        if (!_passesRelationshipEvidenceGuard(draft, sourceMessages)) {
          continue;
        }
        seenThisBatch.add(key);
        // Mark these source ids as covered for subsequent drafts in
        // the same batch, so a single model pass that emits the same
        // set twice in one batch can't sneak both through.
        coveredSourceIds.addAll(draft.sourceMessageIds);
        batchCoveredMessageIds.addAll(draft.sourceMessageIds);

        final fragmentId = _uuid.v4();
        fragmentIds.add(fragmentId);
        fragmentContents[fragmentId] = draft.content;

        final eventTime = _computeEventTime(sourceMessages);
        // Dual-write stable sync_ids alongside legacy int ids so fragments
        // remain traceable after cross-device replication.
        final sourceSyncIds =
            await _resolveFragmentSourceSyncIds(draft.sourceMessageIds);
        await _db.into(_db.memoryFragments).insert(
              MemoryFragmentsCompanion.insert(
                id: fragmentId,
                content: draft.content,
                sourceMessageIds: Value(jsonEncode(draft.sourceMessageIds)),
                sourceSyncIds: sourceSyncIds.isEmpty
                    ? const Value(null)
                    : Value(jsonEncode(sourceSyncIds)),
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
        fragmentContents: fragmentContents,
        entityIds: entityIds.toSet().toList(),
        processedMessageCount: processedMessageCount,
        lastProcessedMessageId: lastProcessedMessageId,
        isEmpty: fragmentIds.isEmpty,
        coveredMessageIds: batchCoveredMessageIds.toList()..sort(),
      );
    });

    // Fire-and-forget: generate embeddings for new fragments.
    if (result.fragmentIds.isNotEmpty) {
      _generateFragmentEmbeddings(result.fragmentContents);
    }
    return result;
  }

  /// Async embedding generation — runs outside the DB transaction.
  void _generateFragmentEmbeddings(Map<String, String> fragmentContents) {
    EmbeddingService.instance.init().then((_) async {
      if (!EmbeddingService.instance.isAvailable) return;
      final ids = fragmentContents.keys.toList();
      final texts = fragmentContents.values.toList();
      final vectors = await EmbeddingService.instance.embedBatch(texts);
      for (var i = 0; i < vectors.length && i < ids.length; i++) {
        await EmbeddingService.instance.storeEmbedding(
          targetTable: 'memory_fragments',
          targetId: ids[i],
          vector: vectors[i],
          contentHash: texts[i].hashCode.toRadixString(16),
        );
      }
      _logger.info(
        'Generated ${vectors.length} embedding(s) for new fragments',
      );
    }).catchError((e, s) {
      _logger.warning('Fragment embedding generation failed', e, s);
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

  /// Advance the watermark only forward. Re-reads the stored value at write
  /// time so a manual retry of an OLD range (below the stored watermark) can
  /// never regress it. Residual race: two concurrent batches could still
  /// both read-then-write; worst case is a few messages re-scanned next run,
  /// which persistFragments dedupe makes harmless.
  Future<void> _advanceWatermark(String characterId, int candidate) async {
    final stored = await _readWatermark(characterId);
    if (candidate > stored) {
      await _writeWatermark(characterId, candidate);
    }
  }

  String _watermarkKey(String characterId) =>
      'dreaming.fragment.last_message_id.$characterId';

  // ──────────────────────────────────────────────────────────────────────
  // Skip-window audit (kvStore JSON, per character)
  // ──────────────────────────────────────────────────────────────────────

  static const _maxSkipRecords = 50;
  String _skipRecordsKey(String characterId) =>
      'dreaming.skip.records.$characterId';

  /// Read audit records for the Lab/About UIs, oldest first.
  /// Corrupted JSON degrades to an empty list; the next write replaces it.
  Future<List<DreamingSkipRecord>> getSkipRecords(String characterId) async {
    final row = await (_db.select(_db.kvStore)
          ..where((t) =>
              t.key.equals(_skipRecordsKey(characterId)) &
              t.bucket.equals(_bucket)))
        .getSingleOrNull();
    if (row?.value == null || row!.value!.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(row.value!);
      if (decoded is! List) return const [];
      return decoded
          .map(DreamingSkipRecord.fromJson)
          .whereType<DreamingSkipRecord>()
          .toList();
    } catch (_) {
      _logger.warning(
          'Skip records corrupted for $characterId; treating as empty');
      return const [];
    }
  }

  Future<void> _writeSkipRecords(
    String characterId,
    List<DreamingSkipRecord> records,
  ) async {
    await _db.into(_db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: _skipRecordsKey(characterId),
            value: Value(jsonEncode(records.map((r) => r.toJson()).toList())),
            bucket: const Value(_bucket),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  Future<void> _appendSkipRecord({
    required String characterId,
    required int fromId,
    required int toId,
    required String reason,
    String? error,
  }) async {
    if (toId < fromId) return;
    final records = await getSkipRecords(characterId);
    final now = DateTime.now().millisecondsSinceEpoch;

    // Identical record already present (e.g. the same window was re-run and
    // skipped again) — replace instead of duplicating.
    records.removeWhere(
        (r) => r.fromId == fromId && r.toId == toId && r.reason == reason);

    // Merge a new 'empty' record into a consecutive trailing 'empty' record
    // so sequential zero-draft batches collapse into one window.
    if (reason == 'empty' && records.isNotEmpty) {
      final last = records.last;
      if (last.reason == 'empty' && last.toId + 1 >= fromId) {
        records[records.length - 1] = DreamingSkipRecord(
          fromId: last.fromId < fromId ? last.fromId : fromId,
          toId: toId,
          reason: 'empty',
          at: now,
        );
        await _writeSkipRecords(characterId, records);
        return;
      }
    }

    records.add(DreamingSkipRecord(
      fromId: fromId,
      toId: toId,
      reason: reason,
      at: now,
      error: error,
    ));
    if (records.length > _maxSkipRecords) {
      records.removeRange(0, records.length - _maxSkipRecords); // drop oldest
    }
    await _writeSkipRecords(characterId, records);
  }

  /// Remove a skip record (either reason) matching [fromId]/[toId]. Used at
  /// retry start: the fresh evaluation re-audits its own outcome, so a stale
  /// record must not linger after a successful re-run.
  Future<void> _removeSkipRecord(
    String characterId, {
    required int fromId,
    required int toId,
  }) async {
    final records = await getSkipRecords(characterId);
    final before = records.length;
    records.removeWhere((r) => r.fromId == fromId && r.toId == toId);
    if (records.length != before) {
      await _writeSkipRecords(characterId, records);
    }
  }

  /// Reset the fragment-extraction watermark for [characterId] so the next
  /// batch re-scans messages from id 0. Used when the user switches to a
  /// model that previously failed (e.g. NSFW-tolerant) and wants to
  /// retry processing of older messages that were skipped after the model
  /// rejected them. The persistFragments dedupe logic uses content hashes
  /// so already-stored fragments won't be duplicated.
  ///
  /// Returns the number of rows deleted (0 means there was no
  /// watermark, 1 means we cleared the active one).
  Future<int> resetFragmentWatermark(String characterId) async {
    final deleted = await (_db.delete(_db.kvStore)
          ..where((t) =>
              t.key.equals(_watermarkKey(characterId)) &
              t.bucket.equals(_bucket)))
        .go();
    if (deleted > 0) {
      _logger.info(
        'Reset fragment watermark for $characterId; next batch will '
        're-scan from id 0',
      );
    }
    return deleted;
  }

  // ──────────────────────────────────────────────────────────────────────
  // Manual re-extraction of skipped windows (audit-driven retry)
  // ──────────────────────────────────────────────────────────────────────

  /// Re-run Dreaming extraction over a previously skipped message range.
  ///
  /// Does NOT reset or move the global watermark backwards: batches run with
  /// [startAfterId] and the watermark write is max-guarded, so the
  /// scheduler's position is untouched (dedupe in persistFragments makes
  /// re-reading already-covered messages harmless).
  ///
  /// The record is removed up-front; each sub-batch re-audits its own
  /// outcome (zero drafts → 'empty' record, throw → 'error' record), so
  /// failures never lose their trail. Throws propagate to the caller (UI
  /// shows the error); the inner catch has already recorded the failure.
  Future<DreamingRetryResult> retrySkippedRange({
    required String characterId,
    required LLMClient client,
    required ModelConfig modelConfig,
    required int fromId,
    required int toId,
    int batchSize = 30,
    DreamingFragmentExtractorV3 agent = const DreamingFragmentExtractorV3(),
  }) async {
    // 1) Range sanity: last extractable chat message inside [fromId, toId].
    final tail = await (_db.select(_db.personaChatMessages)
          ..where((t) =>
              t.characterId.equals(characterId) &
              t.id.isBetweenValues(fromId, toId) &
              t.content.isNotValue('') &
              t.messageType.equals('chat'))
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(1))
        .get();
    final lastChatId = tail.isEmpty ? null : tail.single.id;
    if (lastChatId == null) {
      await _removeSkipRecord(characterId, fromId: fromId, toId: toId);
      return const DreamingRetryResult(
        processedMessageCount: 0,
        fragmentCount: 0,
        message: '区间内没有可补提取的聊天消息，已清除该记录',
      );
    }

    // 2) Remove the record up-front; per-iteration audits below recreate it
    //    for any sub-range that still yields zero drafts.
    await _removeSkipRecord(characterId, fromId: fromId, toId: toId);

    // 3) Loop batches over the window. The cursor mirrors the coverage-aware
    //    watermark semantics: advance only past the last message a persisted
    //    fragment actually referenced, so a partially-evaluated tail is
    //    re-read on the next iteration. Do NOT read the stored watermark as
    //    the cursor — it is max-guarded and will not move below itself.
    var cursor = fromId - 1;
    var lastAdvanced = cursor;
    var processed = 0;
    var fragments = 0;
    while (true) {
      final result = await runDailyFragmentBatch(
        characterId: characterId,
        client: client,
        modelConfig: modelConfig,
        batchSize: batchSize,
        startAfterId: cursor,
        agent: agent,
      );
      if (result.isEmpty && result.processedMessageCount == 0) {
        break; // no more rows
      }
      processed += result.processedMessageCount;
      fragments += result.fragmentIds.length;
      final covered = result.coveredMessageIds
          .where((id) => id <= result.lastProcessedMessageId);
      cursor = covered.isEmpty
          ? result.lastProcessedMessageId
          : covered.reduce((a, b) => a > b ? a : b);
      if (cursor <= lastAdvanced) break; // no-progress guard
      lastAdvanced = cursor;
      if (cursor >= lastChatId) break;
    }
    return DreamingRetryResult(
      processedMessageCount: processed,
      fragmentCount: fragments,
      message: '补提取完成：处理 $processed 条消息，产生 $fragments 个片段',
    );
  }

  /// Convenience: retry every recorded range sequentially. One failure does
  /// not abort the rest; per-range results are returned for the Lab to show.
  Future<List<DreamingRetryResult>> retryAllSkipped({
    required String characterId,
    required LLMClient client,
    required ModelConfig modelConfig,
  }) async {
    final snapshot = await getSkipRecords(characterId);
    final results = <DreamingRetryResult>[];
    for (final r in snapshot) {
      try {
        results.add(await retrySkippedRange(
          characterId: characterId,
          client: client,
          modelConfig: modelConfig,
          fromId: r.fromId,
          toId: r.toId,
        ));
      } catch (e, s) {
        _logger.warning(
            'retryAllSkipped: range ${r.fromId}..${r.toId} failed', e, s);
        results.add(DreamingRetryResult(
          processedMessageCount: 0,
          fragmentCount: 0,
          message: '补跑 ${r.fromId}–${r.toId} 失败：$e',
        ));
      }
    }
    return results;
  }

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

  /// Set of source-message ids already referenced by any non-deleted
  /// fragment. Used to drop re-extracted near-duplicates after a
  /// watermark reset (LLMs paraphrase instead of producing identical
  /// text, so content-hash dedupe alone misses them). Partial overlap
  /// is allowed; a draft is dropped only when every one of its source
  /// ids is already covered.
  Future<Set<int>> _coveredSourceMessageIds() async {
    final rows = await (_db.select(_db.memoryFragments)
          ..where((t) => t.status.isNotIn(const ['deleted'])))
        .get();
    final covered = <int>{};
    for (final row in rows) {
      final raw = row.sourceMessageIds;
      if (raw == null || raw.isEmpty) continue;
      try {
        final ids = jsonDecode(raw).cast<int>();
        covered.addAll(ids);
      } catch (_) {
        // ignore malformed rows
      }
    }
    return covered;
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
    result.sort((a, b) => a.id.compareTo(b.id));
    return result;
  }

  /// Resolves legacy int message ids to stable sync_ids for dual-writing
  /// fragments. Returns an ordered list mirroring [ids] (missing sync_ids
  /// dropped), so evidence survives cross-device replication.
  Future<List<String>> _resolveFragmentSourceSyncIds(List<int> ids) async {
    final unique = ids.where((id) => id > 0).toSet();
    if (unique.isEmpty) return const [];
    final rows = await (_db.select(_db.personaChatMessages)
          ..where((t) => t.id.isIn(unique)))
        .get();
    final byId = {
      for (final row in rows)
        if (row.syncId != null && row.syncId!.isNotEmpty) row.id: row.syncId!,
    };
    return ids
        .map((id) => byId[id])
        .whereType<String>()
        .toSet()
        .toList(growable: false);
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
      final fragIds = (jsonDecode(ep.sourceFragmentIds) as List).cast<String>();
      final range = await _computeOccurredAtRange(fragIds);
      if (range != null && range != ep.occurredAtRange) {
        await (_db.update(_db.memoryEpisodes)..where((t) => t.id.equals(ep.id)))
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
    _logger
        .info('backfillFragmentEventTimes: ${rows.length} fragments to fill');
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

  /// Record batch completion with data-driven metadata for next trigger check.
  Future<void> markDailyBatchComplete(String characterId) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Get the current watermark (last processed message ID)
    final watermarkRow = await (_db.select(_db.kvStore)
          ..where((t) =>
              t.bucket.equals(_bucket) &
              t.key.equals(_watermarkKey(characterId))))
        .getSingleOrNull();
    final currentWatermark = watermarkRow?.value ?? '0';

    // Record batch completion time and watermark for next data-driven check
    await _db.into(_db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion(
            bucket: const Value(_bucket),
            key: Value('dreaming.batch.last_run_time.$characterId'),
            value: Value(now.toString()),
          ),
        );
    await _db.into(_db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion(
            bucket: const Value(_bucket),
            key: Value('dreaming.batch.last_watermark.$characterId'),
            value: Value(currentWatermark),
          ),
        );

    // Keep legacy key for backward compatibility
    await _db.into(_db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion(
            bucket: const Value(_bucket),
            key: Value('daily_batch.last_run.$characterId'),
            value: Value(now.toString()),
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
    int recentFragmentLimit = 12,
    int? currentChatMessageId,
  }) async {
    final trimmedHint = queryHint.trim();

    final episodeCandidates = await _queryEpisodesForContext(
      queryHint: trimmedHint,
      limit: episodeLimit * 3,
    );
    final fragmentCandidates = await _queryFragmentsForContext(
      queryHint: trimmedHint,
      limit: recentFragmentLimit * 3,
    );
    final traceService = MemoryRecallTraceService(_db);
    final episodeCounts = await traceService.recentRecallCounts(
      targetTable: MemoryRecallTraceService.memoryEpisodesTable,
      targetIds: episodeCandidates.map((hit) => hit.episode.id),
      excludeChatMessageId: currentChatMessageId,
    );
    final fragmentCounts = await traceService.recentRecallCounts(
      targetTable: MemoryRecallTraceService.memoryFragmentsTable,
      targetIds: fragmentCandidates.map((hit) => hit.fragment.id),
      excludeChatMessageId: currentChatMessageId,
    );
    final episodeHits = _rankEpisodeNovelty(
      episodeCandidates,
      episodeCounts,
      episodeLimit,
    );
    final fragmentHits = _rankFragmentNovelty(
      fragmentCandidates,
      fragmentCounts,
      recentFragmentLimit,
    );

    return DreamingContextQueryResult(
      episodeHits: episodeHits,
      fragmentHits: fragmentHits,
    );
  }

  List<DreamingEpisodeContextHit> _rankEpisodeNovelty(
    List<DreamingEpisodeContextHit> candidates,
    Map<String, int> recallCounts,
    int limit,
  ) {
    final ranked = candidates.indexed
        .map((entry) => (
              originalIndex: entry.$1,
              hit: entry.$2,
              adjusted: RecallNoveltyPolicy.adjustedScore(
                baseScore: entry.$2.score.toDouble(),
                recentRecallCount: recallCounts[entry.$2.episode.id] ?? 0,
              ),
            ))
        .toList()
      ..sort((a, b) {
        final byScore = b.adjusted.compareTo(a.adjusted);
        return byScore != 0
            ? byScore
            : a.originalIndex.compareTo(b.originalIndex);
      });
    return ranked
        .take(limit)
        .map((entry) => DreamingEpisodeContextHit(
              episode: entry.hit.episode,
              score: entry.hit.score <= 0
                  ? 0
                  : entry.adjusted.round().clamp(1, 9999),
            ))
        .toList(growable: false);
  }

  List<DreamingFragmentContextHit> _rankFragmentNovelty(
    List<DreamingFragmentContextHit> candidates,
    Map<String, int> recallCounts,
    int limit,
  ) {
    final ranked = candidates.indexed
        .map((entry) => (
              originalIndex: entry.$1,
              hit: entry.$2,
              adjusted: RecallNoveltyPolicy.adjustedScore(
                baseScore: entry.$2.score.toDouble(),
                recentRecallCount: recallCounts[entry.$2.fragment.id] ?? 0,
              ),
            ))
        .toList()
      ..sort((a, b) {
        final byScore = b.adjusted.compareTo(a.adjusted);
        return byScore != 0
            ? byScore
            : a.originalIndex.compareTo(b.originalIndex);
      });
    return ranked
        .take(limit)
        .map((entry) => DreamingFragmentContextHit(
              fragment: entry.hit.fragment,
              score: entry.hit.score <= 0
                  ? 0
                  : entry.adjusted.round().clamp(1, 9999),
            ))
        .toList(growable: false);
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
          activeRows
              .sort((a, b) => (ranks[a.id] ?? 0).compareTo(ranks[b.id] ?? 0));
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
            final hits = keywords.where((kw) => narrative.contains(kw)).length;
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
    final allHits = <DreamingFragmentContextHit>[];
    final seenIds = <String>{};

    if (queryHint.isNotEmpty) {
      // ── Primary: embedding semantic search ──────────────────────────
      try {
        await EmbeddingService.instance.init();
        if (EmbeddingService.instance.isAvailable) {
          final similar = await EmbeddingService.instance.searchSimilar(
            query: queryHint,
            targetTable: 'memory_fragments',
            limit: limit * 3,
            minScore: 0.3,
          );
          if (similar.isNotEmpty) {
            final idToScore = {
              for (final s in similar) s.targetId: s.score,
            };
            final embRows = await (_db.select(_db.memoryFragments)
                  ..where((t) =>
                      t.id.isIn(idToScore.keys.toList(growable: false)) &
                      t.status.isIn(const ['active', 'consolidated'])))
                .get();
            embRows.sort((a, b) =>
                (idToScore[b.id] ?? 0).compareTo(idToScore[a.id] ?? 0));
            for (final fr in embRows) {
              if (allHits.length >= limit) break;
              if (seenIds.add(fr.id)) {
                allHits.add(DreamingFragmentContextHit(
                  fragment: fr,
                  // Cosine sim 0..1 → score 0..100
                  score: ((idToScore[fr.id] ?? 0) * 100).round(),
                ));
              }
            }
            _logger.info(
              'Embedding recall: ${embRows.length} hits for "$queryHint"',
            );
          }
        }
      } catch (e, s) {
        _logger.warning('Fragment embedding search failed', e, s);
      }

      // ── Supplementary: FTS keyword search (fills gaps) ─────────────
      if (allHits.length < limit) {
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
                      t.status.isIn(const ['active', 'consolidated'])))
                .get();
            activeRows
                .sort((a, b) => (ranks[a.id] ?? 0).compareTo(ranks[b.id] ?? 0));
            for (final fr in activeRows) {
              if (allHits.length >= limit) break;
              if (seenIds.add(fr.id)) {
                allHits.add(DreamingFragmentContextHit(
                  fragment: fr,
                  score: _bm25ToScore(ranks[fr.id]),
                ));
              }
            }
          }
        } catch (e, s) {
          _logger.warning('Fragment FTS search failed', e, s);
        }
      }

      // ── Safety net: keyword substring scan ─────────────────────────
      if (allHits.length < limit) {
        try {
          final keywords = await QueryMatcher.contentKeywords(queryHint);
          if (keywords.isNotEmpty) {
            final pool = await (_db.select(_db.memoryFragments)
                  ..where(
                      (t) => t.status.isIn(const ['active', 'consolidated']))
                  ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
                  ..limit(limit * 6))
                .get();
            for (final fr in pool) {
              if (allHits.length >= limit) break;
              final content = fr.content.toLowerCase();
              final hits = keywords.where((kw) => content.contains(kw)).length;
              if (hits > 0 && seenIds.add(fr.id)) {
                allHits.add(DreamingFragmentContextHit(
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
    }

    // ── Recency fill ───────────────────────────────────────────────────
    if (allHits.length < limit) {
      final fillQuery = _db.select(_db.memoryFragments)
        ..where((t) => t.status.isIn(const ['active', 'consolidated']))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
        ..limit(limit + seenIds.length);
      if (seenIds.isNotEmpty) {
        fillQuery.where((t) => t.id.isNotIn(seenIds.toList(growable: false)));
      }
      final fillRows = await fillQuery.get();
      for (final fr in fillRows) {
        if (allHits.length >= limit) break;
        allHits.add(DreamingFragmentContextHit(fragment: fr, score: 0));
      }
    }
    return List.unmodifiable(allHits);
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

  /// Correct one or more fields of an existing memory fragment.
  ///
  /// This is the Lab-screen / user-initiated edit path. It does NOT touch
  /// immutable evidence fields ([id], [sourceMessageIds], [generatedByVersion],
  /// [schemaVersion], [createdAt]) — those are the Dreaming pipeline's own
  /// provenance. If you want to change a fragment's source, delete this one
  /// and let the next extraction pass recreate it from messages.
  ///
  /// Writable fields:
  /// - [content] (≤80 chars, matching the extractor hard cap)
  /// - [emotionalWeight] (0.0..1.0)
  /// - [isUserTruthCandidate]
  /// - [status] (active / consolidated / ignored / deleted)
  /// - [eventTime] (ms epoch, when the user says "actually this was on X")
  ///
  /// On any successful edit, [userCorrected] is flipped to true so future
  /// extractors can avoid overwriting. Content edits also rewrite the FTS
  /// row. Returns the updated fragment, or null if [fragmentId] not found.
  Future<MemoryFragment?> updateFragment(
    String fragmentId, {
    String? content,
    double? emotionalWeight,
    bool? isUserTruthCandidate,
    String? status,
    int? eventTime,
    String sourceKind = 'lab_edit',
  }) async {
    return _db.transaction(() async {
      final row = await (_db.select(_db.memoryFragments)
            ..where((t) => t.id.equals(fragmentId)))
          .getSingleOrNull();
      if (row == null) {
        _logger.warning('updateFragment: $fragmentId not found, no-op');
        return null;
      }

      // Validate content length matches the extractor hard cap.
      if (content != null && content.length > 80) {
        throw ArgumentError(
          'fragment content exceeds 80 chars (${content.length}); '
          'match the extractor cap',
        );
      }
      if (emotionalWeight != null &&
          (emotionalWeight < 0.0 || emotionalWeight > 1.0)) {
        throw ArgumentError(
          'emotionalWeight must be in [0.0, 1.0], got $emotionalWeight',
        );
      }
      if (status != null &&
          !const {'active', 'consolidated', 'ignored', 'deleted'}
              .contains(status)) {
        throw ArgumentError('invalid fragment status: $status');
      }

      // Build diff for audit (only fields that actually change).
      final changes = <String, dynamic>{};
      if (content != null && content != row.content) {
        changes['content'] = {'old': row.content, 'new': content};
      }
      if (emotionalWeight != null && emotionalWeight != row.emotionalWeight) {
        changes['emotionalWeight'] = {
          'old': row.emotionalWeight,
          'new': emotionalWeight,
        };
      }
      if (isUserTruthCandidate != null &&
          isUserTruthCandidate != row.isUserTruthCandidate) {
        changes['isUserTruthCandidate'] = {
          'old': row.isUserTruthCandidate,
          'new': isUserTruthCandidate,
        };
      }
      if (status != null && status != row.status) {
        changes['status'] = {'old': row.status, 'new': status};
      }
      if (eventTime != null && eventTime != row.eventTime) {
        changes['eventTime'] = {'old': row.eventTime, 'new': eventTime};
      }

      if (changes.isEmpty) {
        _logger.info('updateFragment: no changes for $fragmentId');
        return row;
      }

      // Apply update. Mark userCorrected=true so future extractors know
      // the human has reviewed this row.
      await (_db.update(_db.memoryFragments)
            ..where((t) => t.id.equals(fragmentId)))
          .write(MemoryFragmentsCompanion(
        content: content != null ? Value(content) : const Value.absent(),
        emotionalWeight: emotionalWeight != null
            ? Value(emotionalWeight)
            : const Value.absent(),
        isUserTruthCandidate: isUserTruthCandidate != null
            ? Value(isUserTruthCandidate)
            : const Value.absent(),
        status: status != null ? Value(status) : const Value.absent(),
        eventTime: eventTime != null ? Value(eventTime) : const Value.absent(),
        userCorrected: const Value(true),
      ));

      // FTS handling. We don't have a fragment_operations audit table yet
      // (deferred to a future migration); for now content changes rewrite
      // the FTS row, and status='deleted' clears it so it's invisible to
      // context injection.
      final becameDeleted = (status == 'deleted');
      final contentChanged = content != null && content != row.content;
      try {
        if (becameDeleted) {
          await _db.searchDao.deleteMemoryFragmentFts(fragmentId);
        } else if (contentChanged) {
          await _db.searchDao.upsertMemoryFragmentFts(
            fragmentId: fragmentId,
            content: content,
          );
        }
      } catch (e, s) {
        _logger.warning(
            'updateFragment: FTS update failed for $fragmentId', e, s);
      }

      _logger
          .info('updateFragment: $fragmentId fields=${changes.keys.join(',')} '
              'source=$sourceKind');
      final updated = await (_db.select(_db.memoryFragments)
            ..where((t) => t.id.equals(fragmentId)))
          .getSingle();
      return updated;
    });
  }

  /// Correct one or more fields of an existing memory episode.
  ///
  /// Mirror of [updateFragment] for episodes. Immutable evidence fields
  /// ([id], [primaryEntityId], [sourceFragmentIds], [generatedByVersion],
  /// [schemaVersion], [createdAt]) are not writable; they encode the
  /// pipeline's own provenance and changing them would silently break the
  /// link back to source fragments.
  ///
  /// Writable fields:
  /// - [narrative] (the first-person summary; the user-visible "what I
  ///   remember about us" text)
  /// - [topicId] (e.g. `relationship_care`, `__ungrouped__`)
  /// - [confidence] (`high` / `medium` / `low`)
  /// - [significance] (1..10)
  /// - [valence] (-1.0..1.0)
  /// - [arousal] (0.0..1.0)
  /// - [occurredAtRange] (JSON `{start, end}` ms or null to clear)
  /// - [status] (`active` / `hidden` / `stale` / `deleted`)
  ///
  /// On any successful edit, [userCorrected] flips to true so future
  /// consolidators know the human has reviewed this row. Narrative edits
  /// rewrite the FTS row; status=`deleted` clears it.
  Future<MemoryEpisode?> updateEpisode(
    String episodeId, {
    String? narrative,
    String? topicId,
    String? confidence,
    int? significance,
    double? valence,
    double? arousal,
    String? occurredAtRange,
    String? status,
    String sourceKind = 'lab_edit',
  }) async {
    return _db.transaction(() async {
      final row = await (_db.select(_db.memoryEpisodes)
            ..where((t) => t.id.equals(episodeId)))
          .getSingleOrNull();
      if (row == null) {
        _logger.warning('updateEpisode: $episodeId not found, no-op');
        return null;
      }

      // Validate.
      if (significance != null && (significance < 1 || significance > 10)) {
        throw ArgumentError(
          'significance must be in [1, 10], got $significance',
        );
      }
      if (valence != null && (valence < -1.0 || valence > 1.0)) {
        throw ArgumentError('valence must be in [-1.0, 1.0], got $valence');
      }
      if (arousal != null && (arousal < 0.0 || arousal > 1.0)) {
        throw ArgumentError('arousal must be in [0.0, 1.0], got $arousal');
      }
      if (confidence != null &&
          !const {'high', 'medium', 'low'}.contains(confidence)) {
        throw ArgumentError(
          'confidence must be one of high/medium/low, got $confidence',
        );
      }
      if (status != null &&
          !const {'active', 'hidden', 'stale', 'deleted'}.contains(status)) {
        throw ArgumentError('invalid episode status: $status');
      }
      // If occurredAtRange is provided, it must be a valid JSON object
      // string (or null/empty to clear).
      if (occurredAtRange != null && occurredAtRange.isNotEmpty) {
        try {
          final decoded = jsonDecode(occurredAtRange);
          if (decoded is! Map) {
            throw const FormatException('not a JSON object');
          }
        } catch (e) {
          throw ArgumentError(
            'occurredAtRange must be a JSON object string like '
            '\'{"start": <ms>, "end": <ms>}\', got: $e',
          );
        }
      }

      // Build diff for audit.
      final changes = <String, dynamic>{};
      if (narrative != null && narrative != row.narrative) {
        changes['narrative'] = {'old': row.narrative, 'new': narrative};
      }
      if (topicId != null && topicId != row.topicId) {
        changes['topicId'] = {'old': row.topicId, 'new': topicId};
      }
      if (confidence != null && confidence != row.confidence) {
        changes['confidence'] = {'old': row.confidence, 'new': confidence};
      }
      if (significance != null && significance != row.significance) {
        changes['significance'] = {
          'old': row.significance,
          'new': significance,
        };
      }
      if (valence != null && valence != row.valence) {
        changes['valence'] = {'old': row.valence, 'new': valence};
      }
      if (arousal != null && arousal != row.arousal) {
        changes['arousal'] = {'old': row.arousal, 'new': arousal};
      }
      if (occurredAtRange != null && occurredAtRange != row.occurredAtRange) {
        changes['occurredAtRange'] = {
          'old': row.occurredAtRange,
          'new': occurredAtRange.isEmpty ? null : occurredAtRange,
        };
      }
      if (status != null && status != row.status) {
        changes['status'] = {'old': row.status, 'new': status};
      }

      if (changes.isEmpty) {
        _logger.info('updateEpisode: no changes for $episodeId');
        return row;
      }

      // Apply update.
      await (_db.update(_db.memoryEpisodes)
            ..where((t) => t.id.equals(episodeId)))
          .write(MemoryEpisodesCompanion(
        narrative: narrative != null ? Value(narrative) : const Value.absent(),
        topicId: topicId != null ? Value(topicId) : const Value.absent(),
        confidence:
            confidence != null ? Value(confidence) : const Value.absent(),
        significance:
            significance != null ? Value(significance) : const Value.absent(),
        valence: valence != null ? Value(valence) : const Value.absent(),
        arousal: arousal != null ? Value(arousal) : const Value.absent(),
        occurredAtRange: occurredAtRange != null
            ? Value(occurredAtRange.isEmpty ? null : occurredAtRange)
            : const Value.absent(),
        status: status != null ? Value(status) : const Value.absent(),
        userCorrected: const Value(true),
      ));

      // FTS handling.
      final becameDeleted = (status == 'deleted');
      final narrativeChanged = narrative != null && narrative != row.narrative;
      final topicChanged = topicId != null && topicId != row.topicId;
      try {
        if (becameDeleted) {
          await _db.searchDao.deleteMemoryEpisodeFts(episodeId);
        } else if (narrativeChanged || topicChanged) {
          await _db.searchDao.upsertMemoryEpisodeFts(
            episodeId: episodeId,
            narrative: narrative ?? row.narrative,
            topicId: topicId ?? row.topicId,
          );
        }
      } catch (e, s) {
        _logger.warning(
            'updateEpisode: FTS update failed for $episodeId', e, s);
      }

      _logger.info('updateEpisode: $episodeId fields=${changes.keys.join(',')} '
          'source=$sourceKind');
      final updated = await (_db.select(_db.memoryEpisodes)
            ..where((t) => t.id.equals(episodeId)))
          .getSingle();
      return updated;
    });
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

  // ===========================================================================
  // Saga Weaving (Deep Dreaming)
  // ===========================================================================

  /// V3 § 10.7 trigger threshold: run saga weaving only when:
  /// - active episodes >= [minEpisodes]
  /// - episode time span >= [minTimeSpanDays]
  /// - last saga update was >= [minDaysSinceLastSaga] days ago (or never)
  static const _sagaMinEpisodes = 5;
  static const _sagaMinTimeSpanDays = 14;
  static const _sagaMinDaysSinceLastSaga = 7;

  /// Check whether saga weaving should run based on V3 § 10.7 thresholds.
  Future<bool> shouldRunSagaWeaving() async {
    final activeEpisodes = await (_db.select(_db.memoryEpisodes)
          ..where((t) => t.status.equals('active')))
        .get();
    if (activeEpisodes.length < _sagaMinEpisodes) return false;

    // Check time span: earliest vs latest episode createdAt.
    final createdAts = activeEpisodes.map((e) => e.createdAt).toList()..sort();
    final spanDays =
        (createdAts.last - createdAts.first) / (1000 * 60 * 60 * 24);
    if (spanDays < _sagaMinTimeSpanDays) return false;

    // Check last saga update time.
    final lastSaga = await (_db.select(_db.memorySagas)
          ..where((t) => t.status.equals('active'))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
          ..limit(1))
        .getSingleOrNull();
    if (lastSaga != null) {
      final daysSince =
          (DateTime.now().millisecondsSinceEpoch - lastSaga.updatedAt) /
              (1000 * 60 * 60 * 24);
      if (daysSince < _sagaMinDaysSinceLastSaga) return false;
    }

    return true;
  }

  /// Run Deep Dreaming: weave active episodes into long-term sagas.
  ///
  /// Persistence: new sagas are inserted; updated sagas get a snapshot of
  /// the old version in [MemorySagaSnapshots] before being overwritten.
  /// FTS is updated for each new/changed saga.
  Future<SagaWeavingRunResult> runSagaWeaving({
    required LLMClient client,
    required ModelConfig modelConfig,
    SagaWeaverV3 agent = const SagaWeaverV3(),
    bool forceRun = false,
  }) async {
    if (!forceRun && !await shouldRunSagaWeaving()) {
      return SagaWeavingRunResult(
        sagaIds: const [],
        updatedSagaIds: const [],
        skippedReasons: ['threshold not met'],
      );
    }

    final episodes = await (_db.select(_db.memoryEpisodes)
          ..where((t) => t.status.equals('active'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    final existingSagas = await (_db.select(_db.memorySagas)
          ..where((t) => t.status.equals('active')))
        .get();

    _logger.info(
      'Saga: weaving ${episodes.length} episodes, '
      '${existingSagas.length} existing saga(s)',
    );

    final result = await agent.weave(
      client: client,
      modelConfig: modelConfig,
      episodes: episodes,
      existingSagas: existingSagas,
    );

    if (result.isEmpty) {
      _logger.info('Saga: weaver returned no sagas. '
          'Reasons: ${result.skippedReasons.join('; ')}');
      return SagaWeavingRunResult(
        sagaIds: const [],
        updatedSagaIds: const [],
        skippedReasons: result.skippedReasons,
      );
    }

    final newSagaIds = <String>[];
    final updatedSagaIds = <String>[];
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.transaction(() async {
      for (final draft in result.sagas) {
        final episodeIdsJson = jsonEncode(draft.episodeIds);
        final axisJson = jsonEncode(draft.emotionalAxis.toJson());

        if (draft.existingSagaId != null && draft.existingSagaId!.isNotEmpty) {
          // ── Update existing saga: snapshot old version first ──
          final oldSaga = await (_db.select(_db.memorySagas)
                ..where((t) =>
                    t.id.equals(draft.existingSagaId!) &
                    t.status.equals('active')))
              .getSingleOrNull();

          if (oldSaga != null) {
            // Archive old version.
            await _db.into(_db.memorySagaSnapshots).insert(
                  MemorySagaSnapshotsCompanion(
                    id: Value(_uuid.v4()),
                    sagaId: Value(oldSaga.id),
                    title: Value(oldSaga.title),
                    description: Value(oldSaga.description),
                    episodeIds: Value(oldSaga.episodeIds),
                    emotionalAxis: Value(oldSaga.emotionalAxis),
                    generatedByVersion: Value(oldSaga.generatedByVersion),
                    snapshotAt: Value(now),
                  ),
                );

            // Overwrite current saga.
            await (_db.update(_db.memorySagas)
                  ..where((t) => t.id.equals(oldSaga.id)))
                .write(MemorySagasCompanion(
              title: Value(draft.title),
              description: Value(draft.description),
              episodeIds: Value(episodeIdsJson),
              emotionalAxis: Value(axisJson),
              generatedByVersion: const Value(_sagaWeaverVersion),
              updatedAt: Value(now),
            ));
            updatedSagaIds.add(oldSaga.id);

            // FTS update.
            try {
              await _db.searchDao.upsertMemorySagaFts(
                sagaId: oldSaga.id,
                title: draft.title,
                description: draft.description,
              );
            } catch (e, s) {
              _logger.warning('Saga FTS update failed for ${oldSaga.id}', e, s);
            }
            continue;
          }
          // Old saga not found — fall through to create new.
        }

        // ── Create new saga ──
        final sagaId = _uuid.v4();
        await _db.into(_db.memorySagas).insert(
              MemorySagasCompanion(
                id: Value(sagaId),
                title: Value(draft.title),
                description: Value(draft.description),
                episodeIds: Value(episodeIdsJson),
                emotionalAxis: Value(axisJson),
                status: const Value('active'),
                generatedByVersion: const Value(_sagaWeaverVersion),
                userCorrected: const Value(false),
                schemaVersion: const Value(1),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
        newSagaIds.add(sagaId);

        // FTS insert.
        try {
          await _db.searchDao.upsertMemorySagaFts(
            sagaId: sagaId,
            title: draft.title,
            description: draft.description,
          );
        } catch (e, s) {
          _logger.warning('Saga FTS insert failed for $sagaId', e, s);
        }
      }
    });

    _logger.info(
      'Saga: created ${newSagaIds.length}, updated ${updatedSagaIds.length}',
    );
    return SagaWeavingRunResult(
      sagaIds: newSagaIds,
      updatedSagaIds: updatedSagaIds,
      skippedReasons: result.skippedReasons,
    );
  }

  /// Query active sagas for companion context injection.
  ///
  /// When [queryHint] is non-empty, FTS search ranks sagas by relevance.
  /// Remaining slots filled by recency. Returns at most [limit] sagas.
  Future<List<MemorySaga>> querySagasForContext({
    String queryHint = '',
    int limit = 3,
  }) async {
    final trimmedHint = queryHint.trim();
    final results = <MemorySaga>[];
    final seenIds = <String>{};

    if (trimmedHint.isNotEmpty) {
      try {
        final ftsHits = await _db.searchDao.searchMemorySagas(
          trimmedHint,
          limit: limit * 2,
        );
        if (ftsHits.isNotEmpty) {
          final ids = ftsHits
              .map((h) => h['saga_id'] as String)
              .toList(growable: false);
          final rows = await (_db.select(_db.memorySagas)
                ..where((t) => t.id.isIn(ids) & t.status.equals('active')))
              .get();
          // Sort by FTS rank order.
          final idOrder = {for (var i = 0; i < ids.length; i++) ids[i]: i};
          rows.sort(
              (a, b) => (idOrder[a.id] ?? 999).compareTo(idOrder[b.id] ?? 999));
          for (final saga in rows) {
            if (results.length >= limit) break;
            if (seenIds.add(saga.id)) results.add(saga);
          }
        }
      } catch (e, s) {
        _logger.warning(
            'Saga FTS search failed; falling back to recency', e, s);
      }
    }

    // Recency fill.
    if (results.length < limit) {
      final fillQuery = _db.select(_db.memorySagas)
        ..where((t) => t.status.equals('active'))
        ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
        ..limit(limit);
      final fillRows = await fillQuery.get();
      for (final saga in fillRows) {
        if (results.length >= limit) break;
        if (seenIds.add(saga.id)) results.add(saga);
      }
    }

    return results;
  }

  /// Rebuild the saga FTS index from all active sagas. Idempotent.
  Future<int> reindexAllSagas() async {
    final rows = await (_db.select(_db.memorySagas)
          ..where((t) => t.status.equals('active')))
        .get();
    var count = 0;
    for (final row in rows) {
      try {
        await _db.searchDao.upsertMemorySagaFts(
          sagaId: row.id,
          title: row.title,
          description: row.description,
        );
        count++;
      } catch (e, s) {
        _logger.warning('reindexAllSagas: failed for ${row.id}', e, s);
      }
    }
    return count;
  }

  /// Delete all sagas and their snapshots. For Lab/dev reset only.
  Future<void> clearAllSagas() async {
    await _db.delete(_db.memorySagaSnapshots).go();
    await _db.delete(_db.memorySagas).go();
    await _db.searchDao.clearMemorySagaFts();
    _logger.info('clearAllSagas: all sagas and snapshots deleted');
  }

  /// Update a saga's fields from Lab UI. Marks [userCorrected] = true.
  Future<MemorySaga> updateSaga(
    String sagaId, {
    String? title,
    String? description,
    String? status,
  }) async {
    return _db.transaction(() async {
      final row = await (_db.select(_db.memorySagas)
            ..where((t) => t.id.equals(sagaId)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('Saga not found: $sagaId');
      }

      await (_db.update(_db.memorySagas)..where((t) => t.id.equals(sagaId)))
          .write(MemorySagasCompanion(
        title: title != null ? Value(title) : const Value.absent(),
        description:
            description != null ? Value(description) : const Value.absent(),
        status: status != null ? Value(status) : const Value.absent(),
        userCorrected: const Value(true),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));

      // FTS handling.
      final becameDeleted = (status == 'deleted');
      final contentChanged = (title != null && title != row.title) ||
          (description != null && description != row.description);
      try {
        if (becameDeleted) {
          await _db.searchDao.deleteMemorySagaFts(sagaId);
        } else if (contentChanged) {
          await _db.searchDao.upsertMemorySagaFts(
            sagaId: sagaId,
            title: title ?? row.title,
            description: description ?? row.description,
          );
        }
      } catch (e, s) {
        _logger.warning('updateSaga: FTS update failed for $sagaId', e, s);
      }

      final updated = await (_db.select(_db.memorySagas)
            ..where((t) => t.id.equals(sagaId)))
          .getSingle();
      return updated;
    });
  }
}
