/// Unified whiteboard content repository (F0 data convergence).
///
/// Drift owns Card / Source / SourceVersion identity and query projections.
/// Rich-text documents and source bodies remain filesystem objects referenced
/// by stable ids. UI code must consume this repository instead of querying
/// MemoryCards directly or treating a JSON directory as a card library.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_storage.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/domain/whiteboard/whiteboard_ids.dart';

/// Filesystem availability of a card's rich-text body.
enum CardDocumentState { available, missing, corrupt }

/// A unified card projection returned to all card-library consumers.
class UnifiedCardRecord {
  const UnifiedCardRecord({
    required this.card,
    this.source,
    this.currentSourceVersion,
    this.document,
    required this.documentState,
    required this.isPlaced,
  });

  final CardContract card;
  final SourceContent? source;
  final SourceVersion? currentSourceVersion;
  final RichTextDocument? document;
  final CardDocumentState documentState;
  final bool isPlaced;

  String? get thumbnail => card.presentation['thumbnail'] as String?;
}

/// Filters for [UnifiedCardRepository.listCards].
class CardLibraryQuery {
  const CardLibraryQuery({
    this.kinds,
    this.tags,
    this.sourceTypes,
    this.search,
    this.boardId,
    this.placedOnBoard,
    this.includeDeleted = false,
    this.loadDocuments = false,
    this.limit,
  });

  final Set<CardKind>? kinds;
  final Set<String>? tags;
  final Set<SourceMediaType>? sourceTypes;
  final String? search;
  final String? boardId;
  final bool? placedOnBoard;
  final bool includeDeleted;
  final bool loadDocuments;
  final int? limit;
}

/// Result of atomically committing one confirmed ingestion result.
class IngestionCommitResult {
  const IngestionCommitResult({
    required this.source,
    required this.version,
    required this.versionIsNew,
    required this.card,
    required this.cardCreated,
    required this.cardRestored,
  });

  final SourceContent source;
  final SourceVersion version;
  final bool versionIsNew;
  final CardContract card;
  final bool cardCreated;
  final bool cardRestored;
}

/// Repository for the single production Card / Source data truth.
///
/// The database is constructor-injected. This file intentionally has no
/// dependency on MemexRouter or AppDatabase.instance.
class UnifiedCardRepository {
  UnifiedCardRepository({
    required this.db,
    required this.whiteboardRoot,
    RichTextStorage? richTextStorage,
  }) : richTextStorage = richTextStorage ??
            RichTextStorage(Directory(_join(whiteboardRoot.path, 'rich_text')));

  final AppDatabase db;
  final Directory whiteboardRoot;
  final RichTextStorage richTextStorage;

  /// Returns an active card by stable id, or null when it is absent/deleted.
  Future<UnifiedCardRecord?> getCard(
    String cardId, {
    bool includeDeleted = false,
    bool loadDocument = true,
  }) async {
    final row = await (db.select(
      db.memoryCards,
    )..where((t) => t.id.equals(cardId)))
        .getSingleOrNull();
    final extra = await (db.select(
      db.whiteboardCardExtras,
    )..where((t) => t.cardId.equals(cardId)))
        .getSingleOrNull();
    if (row == null || extra == null) return null;
    if (!includeDeleted && extra.deletedAt != null) return null;

    final source =
        extra.sourceId == null ? null : await _sourceById(extra.sourceId!);
    final currentVersion = source?.currentVersionId == null
        ? null
        : await _versionById(source!.currentVersionId!);
    final placed = await isCardPlaced(cardId);
    final rich =
        loadDocument ? await richTextStorage.loadWithStatus(cardId) : null;
    return UnifiedCardRecord(
      card: _toCard(row, extra),
      source: source,
      currentSourceVersion: currentVersion,
      document: rich?.document,
      documentState: _documentState(rich?.status),
      isPlaced: placed,
    );
  }

  /// Lists cards from Drift. It never scans the rich-text directory.
  Future<List<UnifiedCardRecord>> listCards([
    CardLibraryQuery query = const CardLibraryQuery(),
  ]) async {
    final extras = await db.select(db.whiteboardCardExtras).get();
    final selectedExtras = extras.where((extra) {
      if (!query.includeDeleted && extra.deletedAt != null) return false;
      if (query.kinds != null &&
          !query.kinds!.contains(CardKind.fromString(extra.cardKind))) {
        return false;
      }
      return true;
    }).toList();
    if (selectedExtras.isEmpty) return const [];

    final ids = selectedExtras.map((e) => e.cardId).toList();
    final rows = await (db.select(
      db.memoryCards,
    )..where((t) => t.id.isIn(ids)))
        .get();
    final rowsById = {for (final row in rows) row.id: row};

    final sourceIds = selectedExtras
        .map((e) => e.sourceId)
        .whereType<String>()
        .toSet()
        .toList();
    final sourceRows = sourceIds.isEmpty
        ? <WhiteboardSource>[]
        : await (db.select(
            db.whiteboardSources,
          )..where((t) => t.id.isIn(sourceIds)))
            .get();
    final sourcesById = {for (final row in sourceRows) row.id: _toSource(row)};

    Set<String> placedIds = const {};
    if (query.boardId != null || query.placedOnBoard != null) {
      final itemQuery = db.select(db.whiteboardBoardItems);
      if (query.boardId != null) {
        itemQuery.where((t) => t.boardId.equals(query.boardId!));
      }
      placedIds = (await itemQuery.get()).map((e) => e.cardId).toSet();
    }

    final normalizedSearch = query.search?.trim().toLowerCase() ?? '';
    final normalizedTags =
        query.tags?.map((tag) => tag.trim().toLowerCase()).toSet();
    final records = <UnifiedCardRecord>[];
    for (final extra in selectedExtras) {
      final row = rowsById[extra.cardId];
      if (row == null) continue;
      final card = _toCard(row, extra);
      final source =
          extra.sourceId == null ? null : sourcesById[extra.sourceId!];
      if (query.sourceTypes != null &&
          (source == null || !query.sourceTypes!.contains(source.mediaType))) {
        continue;
      }
      if (normalizedTags != null &&
          !normalizedTags.every(
            (tag) => card.tags.any((value) => value.toLowerCase() == tag),
          )) {
        continue;
      }
      if (normalizedSearch.isNotEmpty) {
        final haystack = <String>[
          card.title,
          card.body,
          ...card.tags,
        ].join('\n').toLowerCase();
        if (!haystack.contains(normalizedSearch)) continue;
      }
      final placed = placedIds.contains(card.cardId);
      if (query.placedOnBoard != null && query.placedOnBoard != placed) {
        continue;
      }
      final rich = query.loadDocuments
          ? await richTextStorage.loadWithStatus(card.cardId)
          : null;
      records.add(
        UnifiedCardRecord(
          card: card,
          source: source,
          currentSourceVersion: source?.currentVersionId == null
              ? null
              : await _versionById(source!.currentVersionId!),
          document: rich?.document,
          documentState: _documentState(rich?.status),
          isPlaced: placed,
        ),
      );
    }
    records.sort((a, b) {
      final aTime = a.card.updatedAt ?? a.card.createdAt;
      final bTime = b.card.updatedAt ?? b.card.createdAt;
      final byTime = bTime.compareTo(aTime);
      return byTime != 0 ? byTime : a.card.cardId.compareTo(b.card.cardId);
    });
    final limit = query.limit;
    if (limit != null && records.length > limit) {
      return records.take(limit).toList();
    }
    return records;
  }

  /// Creates an explicit user-authored text card.
  Future<CardContract> createTextCard({
    String? cardId,
    String title = '',
    String body = '',
    List<String> tags = const [],
    OwnerSpace ownerSpace = OwnerSpace.user,
    CardCreatedBy createdBy = CardCreatedBy.user,
    DateTime? createdAt,
  }) async {
    final id = cardId ?? StableId.generate('card').value;
    final existing = await (db.select(
      db.memoryCards,
    )..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (existing != null) {
      throw StateError('Card already exists: $id');
    }
    final now = (createdAt ?? DateTime.now()).toUtc();
    final card = CardContract(
      cardId: id,
      cardKind: CardKind.note,
      ownerSpace: ownerSpace,
      title: title,
      body: body,
      tags: _normalizeTags(tags),
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );
    await db.transaction(() => _insertNewCard(card));
    return card;
  }

  /// Updates card metadata and its searchable projection in one transaction.
  Future<CardContract> updateCardMetadata(
    String cardId, {
    String? title,
    String? body,
    List<String>? tags,
    CardKind? cardKind,
    Map<String, dynamic>? presentation,
  }) async {
    final current = await getCard(cardId, loadDocument: false);
    if (current == null) throw StateError('Card not found: $cardId');
    final now = DateTime.now().toUtc();
    final updated = _copyCard(
      current.card,
      title: title,
      body: body,
      tags: tags == null ? null : _normalizeTags(tags),
      cardKind: cardKind,
      presentation: presentation,
      updatedAt: now,
    );
    await db.transaction(() => _updateExistingCard(updated));
    return updated;
  }

  /// Saves full rich text and synchronizes title/body/update projections.
  ///
  /// A Drift Card must already exist, so this path cannot create an orphan
  /// rich-text card id. The JSON is written atomically before the projection
  /// transaction; a later read reports a missing/corrupt file honestly.
  Future<CardContract> saveRichText(
    String cardId,
    RichTextDocument document, {
    String? title,
  }) async {
    final current = await getCard(cardId, loadDocument: false);
    if (current == null) throw StateError('Card not found: $cardId');
    await richTextStorage.save(cardId, document);
    final projection = document.toPlainText().trim();
    final projectedTitle = title?.trim().isNotEmpty == true
        ? title!.trim()
        : _firstNonEmptyLine(projection, fallback: current.card.title);
    return updateCardMetadata(cardId, title: projectedTitle, body: projection);
  }

  /// Associates an existing source with an existing card.
  Future<CardContract> linkSourceToCard(String cardId, String sourceId) async {
    final current = await getCard(cardId, loadDocument: false);
    if (current == null) throw StateError('Card not found: $cardId');
    final source = await _sourceById(sourceId);
    if (source == null) throw StateError('Source not found: $sourceId');
    final now = DateTime.now().toUtc();
    final updated = _copyCard(
      current.card,
      sourceId: sourceId,
      setSourceId: true,
      updatedAt: now,
    );
    await db.transaction(() => _updateExistingCard(updated));
    return updated;
  }

  Future<SourceContent?> getSource(String sourceId) => _sourceById(sourceId);

  Future<List<SourceVersion>> listSourceVersions(String sourceId) async {
    final rows = await (db.select(db.whiteboardSourceVersions)
          ..where((t) => t.sourceId.equals(sourceId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    return rows.map(_toVersion).toList();
  }

  Future<CardContract?> getCardForSource(String sourceId) =>
      _cardForSource(sourceId);

  /// Atomically writes Source + SourceVersion + Card after user confirmation.
  Future<IngestionCommitResult> commitIngestion(
    IngestionResult result, {
    CardKind cardKind = CardKind.source,
    OwnerSpace ownerSpace = OwnerSpace.user,
    CardCreatedBy createdBy = CardCreatedBy.user,
  }) async {
    if (result.status != IngestionStatus.ok ||
        result.source == null ||
        result.sourceVersion == null) {
      throw StateError('Only successful ingestion results can create cards');
    }
    final incomingSource = result.source!;
    final incomingVersion = SourceVersion.fromJson(result.sourceVersion!);
    final existingSource = await _findCanonicalSource(result, incomingSource);
    final sourceId = existingSource?.sourceId ?? incomingSource.sourceId;
    final sameHash = await _versionByHash(
      sourceId,
      incomingVersion.contentHash,
    );
    final version = sameHash ??
        SourceVersion(
          versionId: _versionId(sourceId, incomingVersion.contentHash),
          sourceId: sourceId,
          contentHash: incomingVersion.contentHash,
          objectRef: _sourceObjectRef(sourceId, incomingVersion.contentHash),
          parserVersion: incomingVersion.parserVersion,
          createdAt: incomingVersion.createdAt.toUtc(),
        );
    if (sameHash == null) {
      await _writeSourceObject(version, result);
    }

    late IngestionCommitResult committed;
    await db.transaction(() async {
      if (sameHash == null) {
        await db.into(db.whiteboardSourceVersions).insert(
              WhiteboardSourceVersionsCompanion.insert(
                id: version.versionId,
                sourceId: version.sourceId,
                contentHash: version.contentHash,
                objectRef: version.objectRef,
                parserVersion: Value(version.parserVersion),
                createdAt: _millis(version.createdAt),
              ),
            );
      }
      final now = result.resolvedAt.toUtc();
      final source = SourceContent(
        sourceId: sourceId,
        mediaType: incomingSource.mediaType,
        title: incomingSource.title,
        ownerSpace: existingSource?.ownerSpace ?? ownerSpace,
        origin: incomingSource.origin,
        provider: incomingSource.provider,
        canonicalId: incomingSource.canonicalId,
        mimeType: incomingSource.mimeType,
        currentVersionId: sameHash == null
            ? version.versionId
            : (existingSource?.currentVersionId ?? version.versionId),
        contentHash: sameHash == null
            ? version.contentHash
            : (existingSource?.contentHash ?? version.contentHash),
        objectRef: sameHash == null
            ? version.objectRef
            : (existingSource?.objectRef ?? version.objectRef),
        metadata: {
          ...?existingSource?.metadata,
          ...incomingSource.metadata,
          'canonical_url': result.canonicalUrl,
          if (result.originalUrl != null) 'original_url': result.originalUrl,
        },
        createdAt: existingSource?.createdAt ?? incomingSource.createdAt,
        updatedAt: sameHash == null ? now : existingSource?.updatedAt,
        deletedAt: null,
      );
      await _upsertSource(source);

      final existingCard = await _cardForSource(sourceId);
      final thumbnail =
          incomingSource.metadata['og_image'] ?? result.metadata['og_image'];
      final description = incomingSource.metadata['description'] ??
          result.metadata['description'];
      final excerpt = result.metadata['body_excerpt'] as String? ?? '';
      final wasDeleted = existingCard?.deletedAt != null;
      final cardCreated = existingCard == null;
      final nowForCard = result.resolvedAt.toUtc();
      final card = existingCard == null
          ? CardContract(
              cardId: _cardIdForSource(sourceId),
              cardKind: cardKind,
              sourceId: sourceId,
              ownerSpace: ownerSpace,
              title: source.title,
              body: excerpt,
              presentation: {
                if (thumbnail != null) 'thumbnail': thumbnail,
                if (description != null) 'description': description,
              },
              createdBy: createdBy,
              createdAt: nowForCard,
              updatedAt: nowForCard,
            )
          : _copyCard(
              existingCard,
              title: source.title.isEmpty ? null : source.title,
              body: excerpt.isEmpty ? null : excerpt,
              presentation: {
                ...existingCard.presentation,
                if (thumbnail != null) 'thumbnail': thumbnail,
                if (description != null) 'description': description,
              },
              deletedAt: null,
              setDeletedAt: true,
              updatedAt: sameHash == null || wasDeleted
                  ? nowForCard
                  : existingCard.updatedAt,
            );
      if (cardCreated) {
        await _insertNewCard(card);
      } else {
        await _updateExistingCard(card);
      }
      committed = IngestionCommitResult(
        source: source,
        version: version,
        versionIsNew: sameHash == null,
        card: card,
        cardCreated: cardCreated,
        cardRestored: wasDeleted,
      );
    });
    return committed;
  }

  /// Soft-deletes a Card without deleting Source, versions, rich text, or
  /// BoardItems. Existing placements become honest orphan/deleted references.
  Future<bool> softDeleteCard(String cardId, {DateTime? at}) async {
    final current = await getCard(
      cardId,
      includeDeleted: true,
      loadDocument: false,
    );
    if (current == null || current.card.deletedAt != null) return false;
    final when = (at ?? DateTime.now()).toUtc();
    final updated = _copyCard(
      current.card,
      deletedAt: when,
      setDeletedAt: true,
      updatedAt: when,
    );
    await db.transaction(() => _updateExistingCard(updated));
    return true;
  }

  /// Restores a soft-deleted Card with the same stable id.
  Future<bool> restoreCard(String cardId, {DateTime? at}) async {
    final current = await getCard(
      cardId,
      includeDeleted: true,
      loadDocument: false,
    );
    if (current == null || current.card.deletedAt == null) return false;
    final updated = _copyCard(
      current.card,
      deletedAt: null,
      setDeletedAt: true,
      updatedAt: (at ?? DateTime.now()).toUtc(),
    );
    await db.transaction(() => _updateExistingCard(updated));
    return true;
  }

  /// Whether a card has at least one placement (optionally on one board).
  Future<bool> isCardPlaced(String cardId, {String? boardId}) async {
    final query = db.select(db.whiteboardBoardItems)
      ..where((t) => t.cardId.equals(cardId));
    if (boardId != null) query.where((t) => t.boardId.equals(boardId));
    query.limit(1);
    return await query.getSingleOrNull() != null;
  }

  // Migration-only API -----------------------------------------------------

  /// Imports a legacy Card without overwriting a newer production row.
  Future<bool> importLegacyCard(CardContract legacy) async {
    final current = await getCard(
      legacy.cardId,
      includeDeleted: true,
      loadDocument: false,
    );
    if (current == null) {
      await db.transaction(() => _insertNewCard(legacy));
      return true;
    }
    final currentTime = current.card.updatedAt ?? current.card.createdAt;
    final legacyTime = legacy.updatedAt ?? legacy.createdAt;
    if (!legacyTime.isAfter(currentTime)) return false;
    await db.transaction(() => _updateExistingCard(legacy));
    return true;
  }

  /// Adds the missing Extras half for a legacy Drift note without changing
  /// its MemoryCards row.
  Future<bool> backfillLegacyMemoryCardExtra(String cardId) async {
    final row = await (db.select(db.memoryCards)
          ..where((t) => t.id.equals(cardId)))
        .getSingleOrNull();
    if (row == null) return false;
    final existing = await (db.select(db.whiteboardCardExtras)
          ..where((t) => t.cardId.equals(cardId)))
        .getSingleOrNull();
    if (existing != null) return false;
    await db.into(db.whiteboardCardExtras).insert(
          WhiteboardCardExtrasCompanion.insert(
            cardId: cardId,
            cardKind: CardKind.note.name,
            body: Value(row.retrievalText),
            updatedAt: Value(row.updatedAt),
          ),
        );
    return true;
  }

  /// Imports a legacy Source / version set and optional confirmed Card.
  Future<void> importLegacyIngestion({
    required SourceContent source,
    required List<SourceVersion> versions,
    CardContract? card,
  }) async {
    await db.transaction(() async {
      final existing = await _sourceById(source.sourceId);
      for (final version in versions) {
        if (await _versionByHash(source.sourceId, version.contentHash) !=
            null) {
          continue;
        }
        await db.into(db.whiteboardSourceVersions).insert(
              WhiteboardSourceVersionsCompanion.insert(
                id: version.versionId,
                sourceId: version.sourceId,
                contentHash: version.contentHash,
                objectRef: version.objectRef,
                parserVersion: Value(version.parserVersion),
                createdAt: _millis(version.createdAt),
              ),
            );
      }
      final existingTime = existing?.updatedAt ?? existing?.createdAt;
      final legacyTime = source.updatedAt ?? source.createdAt;
      if (existing == null || legacyTime.isAfter(existingTime!)) {
        await _upsertSource(source);
      }
      if (card != null) {
        final currentCard = await getCard(
          card.cardId,
          includeDeleted: true,
          loadDocument: false,
        );
        if (currentCard == null) {
          await _insertNewCard(card);
        } else {
          final currentTime =
              currentCard.card.updatedAt ?? currentCard.card.createdAt;
          final legacyCardTime = card.updatedAt ?? card.createdAt;
          if (legacyCardTime.isAfter(currentTime)) {
            await _updateExistingCard(card);
          }
        }
      }
    });
  }

  // Internal mapping / persistence ----------------------------------------

  Future<void> _insertNewCard(CardContract card) async {
    await db.into(db.memoryCards).insert(
          MemoryCardsCompanion.insert(
            id: card.cardId,
            memoryScope: const Value('user_truth'),
            type: 'note',
            title: card.title,
            dropletLabel: _dropletLabel(card.title),
            presentationModule: '[]',
            retrievalText: card.body,
            valence: 0,
            arousal: 0,
            createdAt: _millis(card.createdAt),
            updatedAt: _millis(card.updatedAt ?? card.createdAt),
          ),
        );
    await db.into(db.whiteboardCardExtras).insert(
          WhiteboardCardExtrasCompanion.insert(
            cardId: card.cardId,
            cardKind: card.cardKind.name,
            sourceId: Value(card.sourceId),
            ownerSpace: Value(card.ownerSpace.name),
            body: Value(card.body),
            tagsJson: Value(jsonEncode(card.tags)),
            presentationJson: Value(
              card.presentation.isEmpty ? null : jsonEncode(card.presentation),
            ),
            createdBy: Value(card.createdBy.name),
            updatedAt: Value(
              card.updatedAt == null ? null : _millis(card.updatedAt!),
            ),
            deletedAt: Value(
              card.deletedAt == null ? null : _millis(card.deletedAt!),
            ),
          ),
        );
  }

  Future<void> _updateExistingCard(CardContract card) async {
    await (db.update(
      db.memoryCards,
    )..where((t) => t.id.equals(card.cardId)))
        .write(
      MemoryCardsCompanion(
        title: Value(card.title),
        dropletLabel: Value(_dropletLabel(card.title)),
        retrievalText: Value(card.body),
        updatedAt: Value(_millis(card.updatedAt ?? card.createdAt)),
      ),
    );
    await db.into(db.whiteboardCardExtras).insertOnConflictUpdate(
          WhiteboardCardExtrasCompanion.insert(
            cardId: card.cardId,
            cardKind: card.cardKind.name,
            sourceId: Value(card.sourceId),
            ownerSpace: Value(card.ownerSpace.name),
            body: Value(card.body),
            tagsJson: Value(jsonEncode(card.tags)),
            presentationJson: Value(
              card.presentation.isEmpty ? null : jsonEncode(card.presentation),
            ),
            createdBy: Value(card.createdBy.name),
            updatedAt: Value(
              card.updatedAt == null ? null : _millis(card.updatedAt!),
            ),
            deletedAt: Value(
              card.deletedAt == null ? null : _millis(card.deletedAt!),
            ),
          ),
        );
  }

  Future<void> _upsertSource(SourceContent source) async {
    await db.into(db.whiteboardSources).insertOnConflictUpdate(
          WhiteboardSourcesCompanion.insert(
            id: source.sourceId,
            mediaType: source.mediaType.name,
            title: source.title,
            ownerSpace: Value(source.ownerSpace.name),
            origin: Value(source.origin.name),
            provider: Value(source.provider),
            canonicalId: Value(source.canonicalId),
            mimeType: Value(source.mimeType),
            currentVersionId: Value(source.currentVersionId),
            contentHash: Value(source.contentHash),
            objectRef: Value(source.objectRef),
            metadataJson: Value(
              source.metadata.isEmpty ? null : jsonEncode(source.metadata),
            ),
            createdAt: _millis(source.createdAt),
            updatedAt: Value(
              source.updatedAt == null ? null : _millis(source.updatedAt!),
            ),
            deletedAt: Value(
              source.deletedAt == null ? null : _millis(source.deletedAt!),
            ),
          ),
        );
  }

  Future<CardContract?> _cardForSource(String sourceId) async {
    final extra = await (db.select(
      db.whiteboardCardExtras,
    )
          ..where((t) => t.sourceId.equals(sourceId))
          ..limit(1))
        .getSingleOrNull();
    if (extra == null) return null;
    final row = await (db.select(
      db.memoryCards,
    )..where((t) => t.id.equals(extra.cardId)))
        .getSingleOrNull();
    return row == null ? null : _toCard(row, extra);
  }

  Future<SourceContent?> _sourceById(String sourceId) async {
    final row = await (db.select(
      db.whiteboardSources,
    )..where((t) => t.id.equals(sourceId)))
        .getSingleOrNull();
    return row == null ? null : _toSource(row);
  }

  Future<SourceVersion?> _versionById(String versionId) async {
    final row = await (db.select(
      db.whiteboardSourceVersions,
    )..where((t) => t.id.equals(versionId)))
        .getSingleOrNull();
    return row == null ? null : _toVersion(row);
  }

  Future<SourceVersion?> _versionByHash(
    String sourceId,
    String contentHash,
  ) async {
    final row = await (db.select(db.whiteboardSourceVersions)
          ..where(
            (t) =>
                t.sourceId.equals(sourceId) & t.contentHash.equals(contentHash),
          )
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _toVersion(row);
  }

  Future<SourceContent?> _findCanonicalSource(
    IngestionResult result,
    SourceContent incoming,
  ) async {
    final byId = await _sourceById(incoming.sourceId);
    if (byId != null) return byId;
    final rows = await db.select(db.whiteboardSources).get();
    for (final row in rows) {
      if (incoming.canonicalId != null &&
          row.provider == incoming.provider &&
          row.canonicalId == incoming.canonicalId) {
        return _toSource(row);
      }
      final metadata = _decodeMap(row.metadataJson);
      if (metadata?['canonical_url'] == result.canonicalUrl) {
        return _toSource(row);
      }
    }
    return null;
  }

  Future<void> _writeSourceObject(
    SourceVersion version,
    IngestionResult result,
  ) async {
    final file = _objectFile(version.objectRef);
    await file.parent.create(recursive: true);
    final payload = <String, dynamic>{
      'schema_version': 1,
      'source_id': version.sourceId,
      'source_version_id': version.versionId,
      'canonical_url': result.canonicalUrl,
      if (result.originalUrl != null) 'original_url': result.originalUrl,
      if (result.metadata['body_text'] is String)
        'body_text': result.metadata['body_text'],
      'metadata': {
        for (final entry in result.metadata.entries)
          if (entry.key != 'body_text') entry.key: entry.value,
      },
    };
    await _writeJsonAtomically(file, payload);
  }

  File _objectFile(String objectRef) {
    if (objectRef.contains('..') ||
        objectRef.contains('\\') ||
        objectRef.startsWith('/') ||
        objectRef.contains(':') ||
        !objectRef.startsWith('objects/')) {
      throw StateError('Unsafe object_ref: $objectRef');
    }
    return File(_join(whiteboardRoot.path, objectRef));
  }

  static Future<void> _writeJsonAtomically(
    File target,
    Map<String, dynamic> json,
  ) async {
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    if (await target.exists()) await target.delete();
    await temp.rename(target.path);
  }

  static CardContract _toCard(MemoryCard row, WhiteboardCardExtra extra) =>
      CardContract(
        cardId: row.id,
        cardKind: CardKind.fromString(extra.cardKind),
        sourceId: extra.sourceId,
        ownerSpace: OwnerSpace.fromString(extra.ownerSpace),
        title: row.title,
        body: row.retrievalText,
        tags: _decodeStringList(extra.tagsJson),
        presentation: _decodeMap(extra.presentationJson) ?? const {},
        createdBy: CardCreatedBy.fromString(extra.createdBy),
        createdAt: _date(row.createdAt),
        updatedAt: extra.updatedAt == null ? null : _date(extra.updatedAt!),
        deletedAt: extra.deletedAt == null ? null : _date(extra.deletedAt!),
      );

  static SourceContent _toSource(WhiteboardSource row) => SourceContent(
        sourceId: row.id,
        mediaType: SourceMediaType.fromString(row.mediaType),
        title: row.title,
        ownerSpace: OwnerSpace.fromString(row.ownerSpace),
        origin: SourceOrigin.fromString(row.origin),
        provider: row.provider,
        canonicalId: row.canonicalId,
        mimeType: row.mimeType,
        currentVersionId: row.currentVersionId,
        contentHash: row.contentHash,
        objectRef: row.objectRef,
        metadata: _decodeMap(row.metadataJson) ?? const {},
        createdAt: _date(row.createdAt),
        updatedAt: row.updatedAt == null ? null : _date(row.updatedAt!),
        deletedAt: row.deletedAt == null ? null : _date(row.deletedAt!),
      );

  static SourceVersion _toVersion(WhiteboardSourceVersion row) => SourceVersion(
        versionId: row.id,
        sourceId: row.sourceId,
        contentHash: row.contentHash,
        objectRef: row.objectRef,
        parserVersion: row.parserVersion,
        createdAt: _date(row.createdAt),
      );

  static CardContract _copyCard(
    CardContract card, {
    CardKind? cardKind,
    String? sourceId,
    bool setSourceId = false,
    String? title,
    String? body,
    List<String>? tags,
    Map<String, dynamic>? presentation,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool setDeletedAt = false,
  }) =>
      CardContract(
        cardId: card.cardId,
        cardKind: cardKind ?? card.cardKind,
        sourceId: setSourceId ? sourceId : card.sourceId,
        ownerSpace: card.ownerSpace,
        title: title ?? card.title,
        body: body ?? card.body,
        tags: tags ?? card.tags,
        presentation: presentation ?? card.presentation,
        createdBy: card.createdBy,
        createdAt: card.createdAt,
        updatedAt: updatedAt ?? card.updatedAt,
        deletedAt: setDeletedAt ? deletedAt : card.deletedAt,
      );

  static CardDocumentState _documentState(RichTextLoadStatus? status) {
    switch (status) {
      case RichTextLoadStatus.available:
        return CardDocumentState.available;
      case RichTextLoadStatus.corrupt:
        return CardDocumentState.corrupt;
      case RichTextLoadStatus.missing:
      case null:
        return CardDocumentState.missing;
    }
  }

  static Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static List<String> _decodeStringList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.whereType<String>().toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  static List<String> _normalizeTags(List<String> tags) {
    final result = <String>[];
    final seen = <String>{};
    for (final tag in tags) {
      final trimmed = tag.trim();
      if (trimmed.isEmpty || !seen.add(trimmed.toLowerCase())) continue;
      result.add(trimmed);
    }
    return result;
  }

  static String _firstNonEmptyLine(String text, {required String fallback}) {
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return fallback;
  }

  static String _dropletLabel(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return '卡片';
    return trimmed.length <= 4 ? trimmed : trimmed.substring(0, 4);
  }

  static String _cardIdForSource(String sourceId) =>
      'card_${sourceId.replaceFirst(RegExp(r'^src_'), '')}';

  static String _versionId(String sourceId, String hash) =>
      '${sourceId.replaceFirst(RegExp(r'^src_'), 'ver_')}_$hash';

  static String _sourceObjectRef(String sourceId, String hash) =>
      'objects/sources/$sourceId/${_versionId(sourceId, hash)}.json';

  static int _millis(DateTime value) => value.toUtc().millisecondsSinceEpoch;

  static DateTime _date(int value) =>
      DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);

  static String _join(String a, String b) =>
      '$a${Platform.pathSeparator}${b.replaceAll('/', Platform.pathSeparator)}';
}
