/// V3 Record Organizer service.
///
/// Persists [OrganizedRecord] outputs across the Memory V3 table family.
/// Implements V3 § 9 — single explicit-write path for User-truth Memory Cards.
///
/// Boundary:
/// - Does NOT contain the LLM prompt or call. That lives in
///   [RecordOrganizerAgent] / [organizeRawInputV3]. Pass it the
///   pre-organized [OrganizedRecord].
/// - Does NOT auto-capture. Only called from explicit user write paths.
/// - All writes go through [memory_card_operations] as audit log; the I-facing
///   query layer reads only the projection tables.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/drift.dart';
import 'package:memex/data/services/ai_finance_service.dart';
import 'package:memex/data/services/proactive_outing_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';
import 'package:uuid/uuid.dart';

import '../agents/record_organizer_agent/agent.dart';
import '../models/organized_record.dart';

final _logger = getLogger('memory_v3.RecordOrganizerService');

/// Result of a Record Organizer write.
class RecordPersistResult {
  RecordPersistResult({
    required this.cardIds,
    required this.entityIds,
    required this.assetIds,
    required this.isEmpty,
  });

  final List<String> cardIds;
  final List<String> entityIds;
  final List<String> assetIds;
  final bool isEmpty;
}

/// Source descriptor for a write.
class RecordSource {
  RecordSource({
    required this.sourceKind,
    required this.rawInput,
    this.sourceRef,
    this.recordedPlace,
    DateTime? recordedAt,
  }) : recordedAt = recordedAt ?? DateTime.now();

  /// `record_button` / `fab` / `natural_command` / `import` / `system` / `tool_call`
  final String sourceKind;
  final String rawInput;

  /// Soft reference to upstream object: chat message id / asset id / batch id.
  final String? sourceRef;
  final String? recordedPlace;
  final DateTime recordedAt;
}

class RecordOrganizerServiceV3 {
  RecordOrganizerServiceV3(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();
  static const _organizerVersion = 'record_organizer.v3.0';

  static RecordOrganizerServiceV3? _instance;

  static RecordOrganizerServiceV3 get instance {
    final inst = _instance;
    if (inst == null) {
      throw StateError(
          'RecordOrganizerServiceV3 has not been initialized. Call init() first.');
    }
    return inst;
  }

  static bool get isInitialized => _instance != null;

  static void init(AppDatabase db) {
    _instance = RecordOrganizerServiceV3(db);
    // Schedule a one-time FTS backfill if needed. Non-blocking; runs in the
    // next microtask so it does not delay app startup.
    Future.microtask(() async {
      try {
        // Ensure FTS tables exist before backfilling — this is a no-op if
        // they were already created by migration, but catches cases where
        // the migration ran before createFtsTables was added to the step.
        await _instance!._db.searchDao.createFtsTables();
        // Always backfill on init — upsertMemoryV3Fts is idempotent and
        // cheap for typical card counts.
        final count = await _instance!.reindexAllCards();
        getLogger('RecordOrganizerServiceV3')
            .info('FTS backfill: $count card(s) indexed');
      } catch (_) {
        // Backfill is best-effort; never fail init for it.
      }
    });
  }

  static void reset() => _instance = null;

  /// Persist an [OrganizedRecord] into the V3 table family.
  ///
  /// Writes within a single transaction. On any failure, nothing is committed.
  /// Caller should have already produced the [organized] payload via the
  /// agent layer; this service only handles persistence.
  Future<RecordPersistResult> persist({
    required OrganizedRecord organized,
    required RecordSource source,
    List<Map<String, String>>? inputMedia,
  }) async {
    if (organized.isEmpty) {
      _logger.info('persist called with empty record; skipping');
      return RecordPersistResult(
        cardIds: const [],
        entityIds: const [],
        assetIds: const [],
        isEmpty: true,
      );
    }

    return _db.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;

      // ── Pre-pass: normalize media assetPaths BEFORE persisting cards ──
      // The LLM may omit media blocks, output UUIDs, or invent paths. The
      // app already knows the ground-truth saved media from inputMedia, so
      // rebuild all media blocks from that source before the card is stored.
      if (inputMedia != null && inputMedia.isNotEmpty) {
        for (var i = 0; i < organized.cards.length; i++) {
          final card = organized.cards[i];
          card.presentationModule['blocks'] = _normalizePresentationMediaBlocks(
            card.presentationModule['blocks'],
            inputMedia,
          );

          // Inject image analysis text into retrievalText so FTS can match
          // against what the image contains, not just the user's raw text.
          final analyses = <String>[];
          for (final m in inputMedia) {
            final analysis = m['analysis'];
            if (analysis != null && analysis.isNotEmpty) {
              analyses.add(analysis);
            }
          }
          if (analyses.isNotEmpty) {
            final existing = card.retrievalText.trim();
            card.retrievalText = '$existing\n[图片内容：${analyses.join("；")}]';
          }
        }
      }

      final cardIds = <String>[];
      final entityIds = <String>[];

      for (final card in organized.cards) {
        final cardId = _uuid.v4();
        cardIds.add(cardId);

        await _db.into(_db.memoryCards).insert(
              MemoryCardsCompanion.insert(
                id: cardId,
                memoryScope: const Value('user_truth'),
                type: card.type,
                title: card.title,
                dropletLabel: card.dropletLabel,
                presentationModule: jsonEncode(card.presentationModule),
                retrievalText: card.retrievalText,
                valence: card.valence,
                arousal: card.arousal,
                status: Value(card.status),
                needsFollowUp: Value(card.needsFollowUp != null
                    ? jsonEncode(card.needsFollowUp)
                    : null),
                createdAt: now,
                updatedAt: now,
              ),
            );

        await _db.into(_db.memoryCardSources).insert(
              MemoryCardSourcesCompanion.insert(
                cardId: cardId,
                rawInput: source.rawInput,
                recordedAt: source.recordedAt.millisecondsSinceEpoch,
                recordedPlace: Value(source.recordedPlace),
                sourceRef: Value(source.sourceRef),
                sourceKind: source.sourceKind,
              ),
            );

        if (card.structuredFieldsType != null &&
            card.structuredFields != null &&
            card.structuredFields!.isNotEmpty) {
          await _db.into(_db.memoryCardStructuredFields).insert(
                MemoryCardStructuredFieldsCompanion.insert(
                  cardId: cardId,
                  structuredFieldsType: card.structuredFieldsType!,
                  fieldsJson: jsonEncode(card.structuredFields),
                  generatedByVersion: const Value(_organizerVersion),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        }

        for (final link in card.entityLinks) {
          final entityId = await _resolveEntity(link, now: now);
          entityIds.add(entityId);
          await _db.into(_db.memoryEntityLinks).insert(
                MemoryEntityLinksCompanion.insert(
                  id: _uuid.v4(),
                  sourceTable: 'memory_cards',
                  sourceId: cardId,
                  entityId: entityId,
                  relation: link.relation,
                  confidence: Value(link.confidence),
                  createdAt: now,
                ),
              );
        }

        // Audit log entry
        await _db.into(_db.memoryCardOperations).insert(
              MemoryCardOperationsCompanion.insert(
                id: _uuid.v4(),
                cardId: cardId,
                operationType: 'create',
                payload: jsonEncode({
                  'card': card.toJson(),
                  'source': {
                    'sourceKind': source.sourceKind,
                    'sourceRef': source.sourceRef,
                    'recordedAt': source.recordedAt.millisecondsSinceEpoch,
                    'recordedPlace': source.recordedPlace,
                  },
                }),
                sourceKind: source.sourceKind,
                createdAt: now,
              ),
            );

        // FTS index for retrieval
        try {
          await _db.searchDao.upsertMemoryV3Fts(
            cardId: cardId,
            dropletLabel: card.dropletLabel,
            title: card.title,
            retrievalText: card.retrievalText,
          );
        } catch (e, s) {
          _logger.warning('Failed to index card $cardId in FTS', e, s);
        }
      }

      // Create memoryCardAssets links for all input media (the pre-pass
      // already rebuilt display blocks from saved media).
      final assetIds = <String>[];
      if (inputMedia != null) {
        for (var i = 0; i < organized.cards.length; i++) {
          for (final m in inputMedia) {
            final assetId = m['assetId'];
            if (assetId != null) {
              await _ensureAssetLink(
                  cardId: cardIds[i], assetId: assetId, now: now);
              assetIds.add(assetId);
            }
          }
        }
      }

      _logger.info(
          'Persisted ${cardIds.length} memory card(s); ${entityIds.length} entity link(s); ${assetIds.length} asset(s)');

      return RecordPersistResult(
        cardIds: cardIds,
        entityIds: entityIds.toSet().toList(),
        assetIds: assetIds,
        isEmpty: false,
      );
    });
  }

  /// Idempotent insert into [memoryCardAssets]. No-op if link already exists.
  Future<void> _ensureAssetLink({
    required String cardId,
    required String assetId,
    required int now,
  }) async {
    final existing = await (_db.select(_db.memoryCardAssets)
          ..where((t) => t.cardId.equals(cardId) & t.assetId.equals(assetId)))
        .getSingleOrNull();
    if (existing != null) return;
    await _db.into(_db.memoryCardAssets).insert(
          MemoryCardAssetsCompanion.insert(
            id: _uuid.v4(),
            cardId: cardId,
            assetId: assetId,
            role: 'display',
            createdAt: now,
          ),
        );
  }

  /// Resolve an entity by name (case-insensitive). Creates a new entity in
  /// `status=active` (per V3 § 9.5: user-explicit links skip seed) if no
  /// match found.
  Future<String> _resolveEntity(OrganizedEntityLink link,
      {required int now}) async {
    final existing = await (_db.select(_db.memoryEntities)
          ..where((t) =>
              t.name.lower().equals(link.name.toLowerCase()) &
              t.status.isNotIn(const ['deleted', 'merged'])))
        .getSingleOrNull();

    if (existing != null) {
      // Bump lastMentionedAt + fragmentCount
      await (_db.update(_db.memoryEntities)
            ..where((t) => t.id.equals(existing.id)))
          .write(
        MemoryEntitiesCompanion(
          lastMentionedAt: Value(now),
          fragmentCount: Value(existing.fragmentCount + 1),
        ),
      );
      return existing.id;
    }

    final id = _uuid.v4();
    await _db.into(_db.memoryEntities).insert(
          MemoryEntitiesCompanion.insert(
            id: id,
            name: link.name,
            category: link.category,
            status: const Value('active'),
            relationshipToUser: Value(link.relationshipToUser),
            firstMentionedAt: Value(now),
            lastMentionedAt: Value(now),
            fragmentCount: const Value(1),
            generatedByVersion: const Value(_organizerVersion),
          ),
        );
    return id;
  }

  /// Record a user-edited field as a [UserCorrections] row.
  ///
  /// Per V3 § 11.3, this is the contract that lets us re-generate derivatives
  /// later without losing user judgment.
  Future<void> recordUserCorrection({
    required String targetTable,
    required String targetId,
    required String field,
    Object? oldValue,
    required Object newValue,
    required String correctionType,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.userCorrections).insert(
          UserCorrectionsCompanion.insert(
            id: _uuid.v4(),
            targetTable: targetTable,
            targetId: targetId,
            field: field,
            oldValue: Value(oldValue != null ? jsonEncode(oldValue) : null),
            newValue: jsonEncode(newValue),
            correctionType: correctionType,
            createdAt: now,
          ),
        );
  }

  /// High-level convenience: run the V3 Record Organizer agent on [rawInput]
  /// and persist the resulting [OrganizedRecord].
  ///
  /// This is the single end-to-end entry point that explicit write paths
  /// (record button / floating ball / natural command / external import)
  /// should call. Picks up model config from the caller (per V3 § 10.3
  /// "记忆抽取" function category — caller chooses which user-configured
  /// model to pass in).
  Future<RecordPersistResult> organizeAndPersist({
    required LLMClient client,
    required ModelConfig modelConfig,
    required RecordSource source,
    List<String> relevantExistingCardSummaries = const [],
    List<String> recentEntityNames = const [],
    List<Map<String, String>>? inputMedia,
    RecordOrganizerAgentV3 agent = const RecordOrganizerAgentV3(),
  }) async {
    // Register media files as Assets so the LLM can reference them by ID.
    List<Map<String, String>>? enrichedMedia;
    if (inputMedia != null && inputMedia.isNotEmpty) {
      enrichedMedia = [];
      for (final m in inputMedia) {
        _logger.info(
            '_registerMediaAssets: processing ${m['kind']} path=${m['path']}');
        final assetId = _uuid.v4();
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        await _db.into(_db.assets).insert(
              AssetsCompanion.insert(
                id: assetId,
                assetType: m['kind'] ?? 'image',
                storagePath: Value(m['path']),
                originatorRef: Value(source.sourceRef),
                createdAt: nowMs,
              ),
            );
        _logger.info(
            '_registerMediaAssets: inserted asset $assetId storagePath=${m['path']}');
        enrichedMedia.add({
          ...m,
          'assetId': assetId,
        });
      }
    } else {
      _logger.info('_registerMediaAssets: inputMedia is null or empty');
    }

    final organized = await agent.organize(
      client: client,
      modelConfig: modelConfig,
      rawInput: source.rawInput,
      now: source.recordedAt,
      relevantExistingCardSummaries: relevantExistingCardSummaries,
      recentEntityNames: recentEntityNames,
      inputMedia: enrichedMedia,
    );
    _logger.info('organizeAndPersist: ${organized.cards.length} card(s), '
        'inputMedia: ${enrichedMedia != null ? enrichedMedia.map((m) => '${m['kind']}:${m['path']}').join(', ') : 'none'}');
    for (var i = 0; i < organized.cards.length; i++) {
      _logger.info('card[$i] type=${organized.cards[i].type} '
          'blocks=${jsonEncode(organized.cards[i].presentationModule['blocks'])}');
    }
    final result = await persist(
      organized: organized,
      source: source,
      inputMedia: enrichedMedia,
    );
    if (!result.isEmpty) {
      unawaited(
        _bridgeToLedger(
          organized: organized,
          cardIds: result.cardIds,
          source: source,
        ).catchError((error) {
          _logger.warning(
            'organizeAndPersist: ledger bridge failed: $error',
          );
        }),
      );
      unawaited(
        ProactiveOutingService.instance.refreshSchedule().catchError((error) {
          _logger.warning(
            'organizeAndPersist: proactive outing refresh failed: $error',
          );
          return 0;
        }),
      );
    }
    return result;
  }

  /// Bridge financial memory cards to the shared AI finance ledger.
  ///
  /// When a user records an expense or shopping order via any explicit write
  /// path (floating ball, record button, natural command), this automatically
  /// creates a corresponding ledger entry so the finance panel stays in sync
  /// without requiring a separate manual "记一笔" step.
  ///
  /// Only `expense_entry` and `shopping_order` structured field types are
  /// bridged. The AI share defaults to 0 (pure user expense) — the companion
  /// can later adjust via AiFinanceRecord if the expense is shared.
  Future<void> _bridgeToLedger({
    required OrganizedRecord organized,
    required List<String> cardIds,
    required RecordSource source,
  }) async {
    final financeService = AiFinanceService(db: _db);
    for (var i = 0; i < organized.cards.length; i++) {
      final card = organized.cards[i];
      final sfType = card.structuredFieldsType;
      if (sfType != 'expense_entry' && sfType != 'shopping_order') continue;

      final fields = card.structuredFields;
      if (fields == null) continue;

      final amountRaw = fields['amount_cny'];
      if (amountRaw == null) continue;
      final amount = (amountRaw is num) ? amountRaw.toDouble() : double.tryParse('$amountRaw');
      if (amount == null || amount <= 0) continue;

      final cardId = i < cardIds.length ? cardIds[i] : null;
      final purpose = card.title;

      // Parse occurredAt from structured fields
      DateTime? occurredAt;
      final paidAtRaw = fields['paidAt'] as String?;
      if (paidAtRaw != null) {
        occurredAt = DateTime.tryParse(paidAtRaw);
      }
      occurredAt ??= source.recordedAt;

      try {
        await financeService.recordEntry(
          characterId: 'system:card_bridge',
          entryType: 'cost',
          totalAmount: amount,
          aiAmount: 0,
          purpose: purpose,
          linkedFactId: cardId,
          occurredAt: occurredAt,
        );
        _logger.info(
          '_bridgeToLedger: created ledger entry for card ${cardId ?? '?'} '
          '($sfType, ¥$amount, "$purpose")',
        );
      } catch (e) {
        _logger.warning('_bridgeToLedger: failed for card ${cardId ?? '?'}: $e');
      }
    }
  }

  /// Soft-delete a memory card. Per V3 § 8 contract, this writes a `delete`
  /// audit row and clears the projection. The I-facing query layer must
  /// filter by row existence (no row = deleted = invisible).
  Future<void> deleteCard(String cardId,
      {String sourceKind = 'user_action'}) async {
    await _db.transaction(() async {
      final card = await (_db.select(_db.memoryCards)
            ..where((t) => t.id.equals(cardId)))
          .getSingleOrNull();
      if (card == null) {
        _logger.warning('deleteCard: $cardId not found, no-op');
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db.into(_db.memoryCardOperations).insert(
            MemoryCardOperationsCompanion.insert(
              id: _uuid.v4(),
              cardId: cardId,
              operationType: 'delete',
              payload: jsonEncode({'previousScope': card.memoryScope}),
              sourceKind: sourceKind,
              createdAt: now,
            ),
          );
      // Remove projection rows (memory_card_sources, structured_fields,
      // entity_links from this card, relations both directions, card_assets).
      await (_db.delete(_db.memoryCardSources)
            ..where((t) => t.cardId.equals(cardId)))
          .go();
      await (_db.delete(_db.memoryCardStructuredFields)
            ..where((t) => t.cardId.equals(cardId)))
          .go();
      await (_db.delete(_db.memoryEntityLinks)
            ..where((t) =>
                t.sourceTable.equals('memory_cards') &
                t.sourceId.equals(cardId)))
          .go();
      await (_db.delete(_db.memoryCardRelations)
            ..where(
                (t) => t.fromCardId.equals(cardId) | t.toCardId.equals(cardId)))
          .go();
      await (_db.delete(_db.memoryCardAssets)
            ..where((t) => t.cardId.equals(cardId)))
          .go();
      // Card itself
      await (_db.delete(_db.memoryCards)..where((t) => t.id.equals(cardId)))
          .go();
      // FTS index
      try {
        await _db.searchDao.deleteMemoryV3Fts(cardId);
      } catch (e, s) {
        _logger.warning('Failed to remove FTS index for $cardId', e, s);
      }
    });
  }

  /// Rebuild FTS indexes for all existing memory cards.
  ///
  /// Call once after the FTS5 virtual table is first created (migration has no
  /// mechanism to backfill virtual tables), or anytime the index is suspected
  /// to be out of sync.
  Future<int> reindexAllCards() async {
    final rows = await _db.select(_db.memoryCards).get();
    var count = 0;
    for (final row in rows) {
      try {
        await _db.searchDao.upsertMemoryV3Fts(
          cardId: row.id,
          dropletLabel: row.dropletLabel,
          title: row.title,
          retrievalText: row.retrievalText,
        );
        count++;
      } catch (e, s) {
        _logger.warning('reindexAllCards: failed for ${row.id}', e, s);
      }
    }
    _logger.info('reindexAllCards: indexed $count/${rows.length} cards');
    return count;
  }
}

List<Map<String, dynamic>> _normalizePresentationMediaBlocks(
  Object? rawBlocks,
  List<Map<String, String>> inputMedia,
) {
  final mediaBlocks = _groundTruthMediaBlocks(inputMedia);
  final contentBlocks = rawBlocks is List
      ? rawBlocks
          .whereType<Object>()
          .map((item) => item is Map
              ? Map<String, dynamic>.from(item)
              : <String, dynamic>{})
          .where((block) => block.isNotEmpty && !_isMediaBlock(block))
          .toList(growable: false)
      : const <Map<String, dynamic>>[];

  if (mediaBlocks.isEmpty) return contentBlocks;
  return [...mediaBlocks, ...contentBlocks];
}

List<Map<String, dynamic>> _groundTruthMediaBlocks(
  List<Map<String, String>> inputMedia,
) {
  final seenPaths = <String>{};
  final blocks = <Map<String, dynamic>>[];
  for (final media in inputMedia) {
    final path = media['path'] ?? media['storagePath'] ?? media['assetPath'];
    if (path == null || path.trim().isEmpty || !seenPaths.add(path)) {
      continue;
    }
    final kind = media['kind'];
    blocks.add({
      'type': 'media',
      'assetPath': path,
      'kind': kind == null || kind == 'media' ? 'image' : kind,
    });
  }
  return blocks;
}

bool _isMediaBlock(Map<String, dynamic> block) {
  final blockType = block['type']?.toString() ?? block['kind']?.toString();
  return blockType == 'media';
}
