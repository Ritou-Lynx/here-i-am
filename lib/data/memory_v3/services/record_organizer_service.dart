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

import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/drift.dart';
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
                    'recordedAt':
                        source.recordedAt.millisecondsSinceEpoch,
                    'recordedPlace': source.recordedPlace,
                  },
                }),
                sourceKind: source.sourceKind,
                createdAt: now,
              ),
            );
      }

      // Link media blocks → assets
      final assetIds = <String>[];
      for (var i = 0; i < organized.cards.length; i++) {
        final card = organized.cards[i];
        final blocks = (card.presentationModule['blocks'] as List<dynamic>?) ?? [];
        for (final block in blocks) {
          if (block is Map && block['kind'] == 'media') {
            final ref = block['assetRef'] as String?;
            if (ref != null) {
              assetIds.add(ref);
              await _db.into(_db.memoryCardAssets).insert(
                    MemoryCardAssetsCompanion.insert(
                      id: _uuid.v4(),
                      cardId: cardIds[i],
                      assetId: ref,
                      role: 'display',
                      createdAt: now,
                    ),
                  );
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
        enrichedMedia.add({
          ...m,
          'assetId': assetId,
        });
      }
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
    return persist(organized: organized, source: source);
  }

  /// Soft-delete a memory card. Per V3 § 8 contract, this writes a `delete`
  /// audit row and clears the projection. The I-facing query layer must
  /// filter by row existence (no row = deleted = invisible).
  Future<void> deleteCard(String cardId, {String sourceKind = 'user_action'}) async {
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
            ..where((t) =>
                t.fromCardId.equals(cardId) | t.toCardId.equals(cardId)))
          .go();
      await (_db.delete(_db.memoryCardAssets)
            ..where((t) => t.cardId.equals(cardId)))
          .go();
      // Card itself
      await (_db.delete(_db.memoryCards)..where((t) => t.id.equals(cardId)))
          .go();
    });
  }
}
