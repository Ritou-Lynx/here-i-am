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

/// Field names inside `structuredFields` that represent time anchors for the
/// recorded event. These are intentionally NEVER writable through the
/// companion-facing `memory_v3_update_card` tool's `structured_fields`
/// parameter — the LLM can only change them via the explicit `time_overrides`
/// parameter, and only when the user says the event time is wrong. This stops
/// accidental time drift when the LLM regenerates a card's business fields.
const Set<String> _timeFieldNames = {
  'occurredAt',
  'occurredEndAt',
  'nextActionAt',
  'dueAt',
  'startAt',
  'endAt',
  'remindAt',
  'paidAt',
  'receivedAt',
  'sleepStart',
  'sleepEnd',
  'wakeDate',
};

/// When the caller updates `retrievalText` without explicitly passing a new
/// `presentationModule`, we try to keep the visible summary card in sync by
/// rewriting the text inside text blocks. Non-text blocks are preserved so
/// number/quote/table/media layouts stay intact.
///
/// Returns the updated JSON-decoded PresentationModule map, or null if there
/// is nothing to change (e.g. no existing blocks, or no text blocks).
Map<String, dynamic>? _syncRetrievalTextIntoBlocks(
  String existingJson,
  String newRetrievalText,
) {
  final parsed = _safeParseJson(existingJson);
  if (parsed is! Map) return null;
  final existing = Map<String, dynamic>.from(parsed);
  final rawBlocks = existing['blocks'];
  if (rawBlocks is! List || rawBlocks.isEmpty) return null;
  final hasTextBlock = rawBlocks.any(
    (b) => b is Map && (b['type'] ?? b['kind']) == 'text',
  );
  if (!hasTextBlock) return null;

  // Split retrievalText into sentences by Chinese/English punctuation.
  // We keep block order: each existing text block gets the next sentence,
  // and any leftover sentences get appended as new text blocks at the end.
  final sentences = _splitIntoSentences(newRetrievalText);
  if (sentences.isEmpty) return null;

  final newBlocks = <Map<String, dynamic>>[];
  var nextSentenceIdx = 0;
  for (final block in rawBlocks) {
    if (block is! Map) {
      newBlocks.add(Map<String, dynamic>.from(block));
      continue;
    }
    final isText = (block['type'] ?? block['kind']) == 'text';
    if (isText && nextSentenceIdx < sentences.length) {
      newBlocks.add({
        ...Map<String, dynamic>.from(block),
        'text': sentences[nextSentenceIdx++],
      });
    } else {
      newBlocks.add(Map<String, dynamic>.from(block));
    }
  }
  while (nextSentenceIdx < sentences.length) {
    newBlocks.add({'type': 'text', 'text': sentences[nextSentenceIdx++]});
  }
  return {...existing, 'blocks': newBlocks};
}

/// Split a paragraph into sentences by major punctuation. Conservative — keeps
/// short sentences together to avoid breaking text that uses commas lightly.
List<String> _splitIntoSentences(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  final regex = RegExp(r'[^。！？!?\.]+[。！？!?\.]|[^。！？!?\.]+$');
  final matches = regex.allMatches(trimmed).map((m) => m.group(0)!.trim()).where((s) => s.isNotEmpty);
  final list = matches.toList();
  if (list.isEmpty) return [trimmed];
  return list;
}

/// Best-effort JSON parse that returns null instead of throwing.
Object? _safeParseJson(String raw) {
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}

/// Extract just the text content of text blocks for audit logging.
List<String> _extractTextBlocks(String presentationJson) {
  final parsed = _safeParseJson(presentationJson);
  if (parsed is! Map) return const [];
  final rawBlocks = parsed['blocks'];
  if (rawBlocks is! List) return const [];
  return rawBlocks
      .where((b) => b is Map && (b['type'] ?? b['kind']) == 'text')
      .map((b) => (b as Map)['text']?.toString() ?? '')
      .where((s) => s.isNotEmpty)
      .toList();
}

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
  /// When a user records an expense, shopping order or income via any
  /// explicit write path (floating ball, record button, natural command),
  /// this automatically creates a corresponding ledger entry so the finance
  /// panel stays in sync without requiring a separate manual "记一笔" step.
  ///
  /// Only `expense_entry`, `shopping_order` and `income_entry` structured
  /// field types are bridged. Expenses/shopping map to `cost`, income maps
  /// to `income`. The AI share defaults to 0 (pure user money movement).
  /// For income, if the Record Organizer extracted an `ai_share_ratio`
  /// (only present when the user explicitly stated a split), the bridge
  /// computes aiAmount = totalAmount × ratio and stores the contribution
  /// descriptions. The companion can still adjust later via AiFinanceRecord.
  Future<void> _bridgeToLedger({
    required OrganizedRecord organized,
    required List<String> cardIds,
    required RecordSource source,
  }) async {
    final financeService = AiFinanceService(db: _db);
    for (var i = 0; i < organized.cards.length; i++) {
      final card = organized.cards[i];
      final sfType = card.structuredFieldsType;
      if (sfType != 'expense_entry' &&
          sfType != 'shopping_order' &&
          sfType != 'income_entry') {
        continue;
      }

      final fields = card.structuredFields;
      if (fields == null) continue;

      final amountRaw = fields['amount_cny'];
      if (amountRaw == null) continue;
      final amount = (amountRaw is num) ? amountRaw.toDouble() : double.tryParse('$amountRaw');
      if (amount == null || amount <= 0) continue;

      final cardId = i < cardIds.length ? cardIds[i] : null;
      final purpose = card.title;

      // Parse occurredAt from structured fields.
      // expense_entry/shopping_order use `paidAt`; income_entry uses `receivedAt`.
      DateTime? occurredAt;
      final timeRaw = fields['paidAt'] as String? ??
          fields['receivedAt'] as String?;
      if (timeRaw != null) {
        occurredAt = DateTime.tryParse(timeRaw);
      }
      occurredAt ??= source.recordedAt;

      final isIncome = sfType == 'income_entry';

      // For income, check if the user explicitly stated a companion share.
      // The Record Organizer extracts `ai_share_ratio` (0.0–1.0) only when
      // the user mentions a split; absent means pure user income (aiAmount 0).
      double aiAmount = 0;
      double? contributionRatio;
      String? myContributionDesc;
      String? aiContributionDesc;
      if (isIncome) {
        final ratioRaw = fields['ai_share_ratio'];
        if (ratioRaw != null) {
          final ratio = (ratioRaw is num)
              ? ratioRaw.toDouble()
              : double.tryParse('$ratioRaw');
          if (ratio != null && ratio > 0 && ratio <= 1) {
            contributionRatio = ratio;
            aiAmount = (amount * ratio).clamp(0.0, amount).toDouble();
            myContributionDesc =
                fields['my_contribution'] as String?;
            aiContributionDesc =
                fields['ai_contribution'] as String?;
          }
        }
      }

      try {
        await financeService.recordEntry(
          characterId: 'system:card_bridge',
          entryType: isIncome ? 'income' : 'cost',
          totalAmount: amount,
          aiAmount: aiAmount,
          contributionRatio: contributionRatio,
          myContributionDesc: myContributionDesc,
          aiContributionDesc: aiContributionDesc,
          purpose: purpose,
          linkedFactId: cardId,
          occurredAt: occurredAt,
        );
        _logger.info(
          '_bridgeToLedger: created ledger entry for card ${cardId ?? '?'} '
          '($sfType, ¥$amount, aiShare ¥$aiAmount, "$purpose")',
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

  /// Update one or more fields of an existing memory card.
  ///
  /// Writes an `update` operation to the audit log, updates the projection
  /// row(s), and rebuilds the FTS index. Only the fields you pass are changed;
  /// null/absent parameters leave the existing value untouched.
  ///
  /// [structuredFields] and [structuredFieldsType] are updated together: if
  /// you pass one you should pass the other. Passing a non-null [structuredFields]
  /// with null [structuredFieldsType] clears the type.
  ///
  /// Returns the updated card row, or null if [cardId] was not found.
  Future<MemoryCard?> updateCard(
    String cardId, {
    String? title,
    String? retrievalText,
    String? dropletLabel,
    String? type,
    String? status,
    Map<String, dynamic>? structuredFields,
    String? structuredFieldsType,
    Map<String, dynamic>? timeOverrides,
    Map<String, dynamic>? presentationModule,
    String sourceKind = 'companion_edit',
  }) async {
    return _db.transaction(() async {
      final card = await (_db.select(_db.memoryCards)
            ..where((t) => t.id.equals(cardId)))
          .getSingleOrNull();
      if (card == null) {
        _logger.warning('updateCard: $cardId not found, no-op');
        return null;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final changes = <String, dynamic>{};

      String? newTitle;
      String? newRetrievalText;
      String? newDropletLabel;
      String? newType;
      Value<String?> newStatus = const Value.absent();
      if (title != null && title != card.title) {
        newTitle = title;
        changes['title'] = {'old': card.title, 'new': title};
      }
      if (retrievalText != null && retrievalText != card.retrievalText) {
        newRetrievalText = retrievalText;
        changes['retrievalText'] = {'old': card.retrievalText, 'new': retrievalText};
      }
      if (dropletLabel != null && dropletLabel != card.dropletLabel) {
        newDropletLabel = dropletLabel;
        changes['dropletLabel'] = {'old': card.dropletLabel, 'new': dropletLabel};
      }
      if (type != null && type != card.type) {
        newType = type;
        changes['type'] = {'old': card.type, 'new': type};
      }
      if (status != null && status != card.status) {
        newStatus = Value(status);
        changes['status'] = {'old': card.status, 'new': status};
      }

      // Update structured fields if requested.
      if (structuredFields != null || timeOverrides != null) {
        final existing = await (_db.select(_db.memoryCardStructuredFields)
              ..where((t) => t.cardId.equals(cardId)))
            .getSingleOrNull();

        // Merge with existing JSON. Time fields in [structuredFields] are
        // stripped — only [timeOverrides] can change them. Unspecified fields
        // are preserved from the original.
        Map<String, dynamic> merged = <String, dynamic>{};
        if (existing != null) {
          final decoded = jsonDecode(existing.fieldsJson);
          if (decoded is Map<String, dynamic>) {
            merged.addAll(decoded);
          }
        }

if (structuredFields != null) {
          final filtered = Map<String, dynamic>.from(structuredFields);
          for (final key in _timeFieldNames) {
            filtered.remove(key);
          }
          for (final entry in filtered.entries) {
            if (merged[entry.key] != entry.value) {
              changes['structuredFields.${entry.key}'] = {
                'old': merged[entry.key],
                'new': entry.value,
              };
            }
          }
          merged.addAll(filtered);
        }

        if (timeOverrides != null) {
          for (final entry in timeOverrides.entries) {
            if (!_timeFieldNames.contains(entry.key)) {
              _logger.warning(
                'updateCard: timeOverrides ignored non-time field "${entry.key}" on $cardId',
              );
              continue;
            }
            if (merged[entry.key] != entry.value) {
              changes['timeOverrides.${entry.key}'] = {
                'old': merged[entry.key],
                'new': entry.value,
              };
            }
            merged[entry.key] = entry.value;
          }
        }

        final mergedJson = jsonEncode(merged);
        if (existing != null) {
          await (_db.update(_db.memoryCardStructuredFields)
                ..where((t) => t.cardId.equals(cardId)))
              .write(MemoryCardStructuredFieldsCompanion(
            structuredFieldsType: structuredFieldsType != null
                ? Value(structuredFieldsType)
                : const Value.absent(),
            fieldsJson: Value(mergedJson),
            userCorrected: const Value(true),
            updatedAt: Value(now),
          ));
        } else {
          await _db.into(_db.memoryCardStructuredFields).insert(
                MemoryCardStructuredFieldsCompanion.insert(
                  cardId: cardId,
                  structuredFieldsType: structuredFieldsType ?? 'general',
                  fieldsJson: mergedJson,
                  userCorrected: const Value(true),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        }
        if (structuredFieldsType != null) {
          changes['structuredFieldsType'] = structuredFieldsType;
        }
      } else if (structuredFieldsType != null) {
        // Only updating the type without changing fields.
        await (_db.update(_db.memoryCardStructuredFields)
              ..where((t) => t.cardId.equals(cardId)))
            .write(MemoryCardStructuredFieldsCompanion(
          structuredFieldsType: Value(structuredFieldsType),
          userCorrected: const Value(true),
          updatedAt: Value(now),
        ));
        changes['structuredFieldsType'] = structuredFieldsType;
      }

      // Compute presentationModule update.
      //
      // Priority:
      // 1. If caller passed `presentationModule` directly, use it verbatim.
      // 2. Else if `retrievalText` is changing, auto-sync: update text blocks
      //    in the existing presentationModule with the new retrievalText.
      //    Non-text blocks (number/quote/table/media/...) are preserved.
      // 3. Else no presentationModule change.
      String? newPresentationModuleJson;
      if (presentationModule != null) {
        newPresentationModuleJson = jsonEncode(presentationModule);
        if (newPresentationModuleJson != card.presentationModule) {
          changes['presentationModule'] = {
            'old': _safeParseJson(card.presentationModule),
            'new': presentationModule,
          };
        } else {
          newPresentationModuleJson = null;
        }
      } else if (newRetrievalText != null) {
        final newText = newRetrievalText;
        final synced = _syncRetrievalTextIntoBlocks(
          card.presentationModule,
          newText,
        );
        if (synced != null) {
          final json = jsonEncode(synced);
          newPresentationModuleJson = json;
          changes['presentationModule.blocks.text'] = {
            'old': _extractTextBlocks(card.presentationModule),
            'new': _extractTextBlocks(json),
          };
        }
      }

      // Apply card row update if anything changed.
      //
      // NOTE: we deliberately do NOT refresh memory_cards.updatedAt here.
      // That column is the card's "last-modified" time and is used by the
      // Memory Review list as the display+sort key. Refreshing it on every
      // edit would make the card jump to the top of the list and make its
      // list timestamp show the edit time instead of the event time.
      // Modifications are tracked in memory_card_operations (audit log).
      if (changes.isNotEmpty) {
        await (_db.update(_db.memoryCards)
              ..where((t) => t.id.equals(cardId)))
            .write(MemoryCardsCompanion(
          title: newTitle != null ? Value(newTitle) : const Value.absent(),
          retrievalText: newRetrievalText != null
              ? Value(newRetrievalText)
              : const Value.absent(),
          dropletLabel: newDropletLabel != null
              ? Value(newDropletLabel)
              : const Value.absent(),
          type: newType != null ? Value(newType) : const Value.absent(),
          status: newStatus,
          presentationModule: newPresentationModuleJson != null
              ? Value(newPresentationModuleJson)
              : const Value.absent(),
        ));

        // Audit log.
        await _db.into(_db.memoryCardOperations).insert(
              MemoryCardOperationsCompanion.insert(
                id: _uuid.v4(),
                cardId: cardId,
                operationType: 'update',
                payload: jsonEncode(changes),
                sourceKind: sourceKind,
                createdAt: now,
              ),
            );

        // Rebuild FTS with potentially new title/retrievalText/dropletLabel.
        final updatedCard = await (_db.select(_db.memoryCards)
              ..where((t) => t.id.equals(cardId)))
            .getSingle();
        try {
          await _db.searchDao.upsertMemoryV3Fts(
            cardId: cardId,
            dropletLabel: updatedCard.dropletLabel,
            title: updatedCard.title,
            retrievalText: updatedCard.retrievalText,
          );
        } catch (e, s) {
          _logger.warning('updateCard: FTS re-index failed for $cardId', e, s);
        }
        _logger.info('updateCard: updated $cardId, fields: ${changes.keys.join(", ")}');
        return updatedCard;
      }

      _logger.info('updateCard: no changes for $cardId');
      return card;
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
