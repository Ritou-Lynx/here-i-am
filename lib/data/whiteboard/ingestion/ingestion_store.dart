/// Ingestion store — file-backed persistence for Source, SourceVersion,
/// and Card entities produced by link ingestion.
///
/// Uses a simple JSON file per source (with its versions) plus a Card
/// index file. This avoids a database migration for the W3 vertical
/// slice — the W0 integration workflow can later migrate this to Drift
/// tables without changing the domain contracts.
///
/// De-duplication rules:
///   - Same canonical URL → same sourceId → reuse Source, create new
///     SourceVersion if content hash changed.
///   - Same sourceId + same content hash → no new version (idempotent
///     re-import).
///   - Card creation is explicit: [LinkIngestionService] decides whether
///     to create a Card from an [IngestionResult]; the store only
///     upserts Source + SourceVersion.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/domain/whiteboard/source_content.dart';

/// A stored ingestion record: the Source, its versions, and an optional
/// Card referencing it.
class IngestionRecord {
  final SourceContent source;
  final List<SourceVersion> versions;
  final CardContract? card;

  const IngestionRecord({
    required this.source,
    required this.versions,
    this.card,
  });

  SourceVersion? get currentVersion {
    final vid = source.currentVersionId;
    if (vid == null) return null;
    return versions.where((v) => v.versionId == vid).firstOrNull;
  }
}

/// Result of upserting an ingestion.
class UpsertResult {
  final SourceContent source;
  final SourceVersion version;
  final bool versionIsNew;

  const UpsertResult({
    required this.source,
    required this.version,
    required this.versionIsNew,
  });
}

/// File-backed store for ingestion entities.
class IngestionStore {
  IngestionStore(this._rootDir);

  final Directory _rootDir;

  Directory get _sourcesDir => Directory('${_rootDir.path}/sources');
  File get _cardsIndex => File('${_rootDir.path}/cards.json');
  File get _sourceIndex => File('${_rootDir.path}/source_index.json');

  /// Ensures the store directory structure exists.
  Future<void> ensureInitialized() async {
    await _sourcesDir.create(recursive: true);
    if (!await _sourceIndex.exists()) {
      await _sourceIndex.writeAsString('[]');
    }
    if (!await _cardsIndex.exists()) {
      await _cardsIndex.writeAsString('[]');
    }
  }

  // -------------------------------------------------------------------------
  // Source + Version upsert (de-dup)
  // -------------------------------------------------------------------------

  /// Upserts a Source + SourceVersion from an [IngestionResult].
  ///
  /// - If the sourceId doesn't exist, creates it.
  /// - If it exists and the content hash matches the latest version,
  ///   returns the existing version (idempotent — no new version).
  /// - If it exists but the content hash differs, creates a new
  ///   SourceVersion and updates the Source's currentVersionId.
  Future<UpsertResult> upsertSource(IngestionResult result) async {
    await ensureInitialized();
    final source = result.source!;
    final versionJson = result.sourceVersion!;
    final newVersion = SourceVersion.fromJson(versionJson);

    final existing = await getRecord(source.sourceId);

    if (existing == null) {
      // New source.
      final record = IngestionRecord(
        source: source,
        versions: [newVersion],
        card: null,
      );
      await _writeRecord(record);
      await _addToSourceIndex(source);
      return UpsertResult(
        source: source,
        version: newVersion,
        versionIsNew: true,
      );
    }

    // Check if content hash matches any existing version.
    final match = existing.versions
        .where((v) => v.contentHash == newVersion.contentHash)
        .firstOrNull;
    if (match != null) {
      // Idempotent re-import — no new version.
      return UpsertResult(
        source: existing.source,
        version: match,
        versionIsNew: false,
      );
    }

    // New version for existing source.
    final updatedSource = SourceContent(
      sourceId: existing.source.sourceId,
      mediaType: source.mediaType,
      title: source.title.isNotEmpty ? source.title : existing.source.title,
      ownerSpace: existing.source.ownerSpace,
      origin: existing.source.origin,
      provider: source.provider,
      canonicalId: source.canonicalId,
      mimeType: source.mimeType,
      currentVersionId: newVersion.versionId,
      contentHash: newVersion.contentHash,
      objectRef: newVersion.objectRef,
      metadata: {...existing.source.metadata, ...source.metadata},
      createdAt: existing.source.createdAt,
      updatedAt: newVersion.createdAt,
      deletedAt: existing.source.deletedAt,
    );
    final record = IngestionRecord(
      source: updatedSource,
      versions: [...existing.versions, newVersion],
      card: existing.card,
    );
    await _writeRecord(record);
    await _updateSourceIndex(updatedSource);
    return UpsertResult(
      source: updatedSource,
      version: newVersion,
      versionIsNew: true,
    );
  }

  // -------------------------------------------------------------------------
  // Card management
  // -------------------------------------------------------------------------

  /// Creates a Card referencing a source, if one doesn't already exist.
  ///
  /// Returns the created or existing card.
  Future<CardContract> createOrUpdateCard({
    required IngestionResult result,
    CardKind kind = CardKind.source,
    OwnerSpace ownerSpace = OwnerSpace.user,
    CardCreatedBy createdBy = CardCreatedBy.user,
    String? cardId,
  }) async {
    final source = result.source!;
    final existing = await getCardForSource(source.sourceId);
    if (existing != null) {
      // Update title/body if the new version has richer content.
      final newTitle = source.title;
      final updated = CardContract(
        cardId: existing.cardId,
        cardKind: existing.cardKind,
        sourceId: existing.sourceId,
        ownerSpace: existing.ownerSpace,
        title: newTitle.isNotEmpty ? newTitle : existing.title,
        body: existing.body,
        tags: existing.tags,
        presentation: {
          ...existing.presentation,
          if (source.metadata['og_image'] != null)
            'thumbnail': source.metadata['og_image'],
        },
        createdBy: existing.createdBy,
        createdAt: existing.createdAt,
        updatedAt: DateTime.now().toUtc(),
        deletedAt: existing.deletedAt,
      );
      await _updateCardInIndex(updated);
      return updated;
    }

    final id = cardId ??
        'card_${source.sourceId.replaceAll('src_', '')}';
    final now = DateTime.now().toUtc();
    final card = CardContract(
      cardId: id,
      cardKind: kind,
      sourceId: source.sourceId,
      ownerSpace: ownerSpace,
      title: source.title,
      body: (result.metadata['body_excerpt'] as String?) ?? '',
      presentation: {
        if (source.metadata['og_image'] != null)
          'thumbnail': source.metadata['og_image'],
        if (source.metadata['description'] != null)
          'description': source.metadata['description'],
      },
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );
    await _addCardToIndex(card);

    // Link card to the source record.
    final record = await getRecord(source.sourceId);
    if (record != null) {
      await _writeRecord(IngestionRecord(
        source: record.source,
        versions: record.versions,
        card: card,
      ));
    }
    return card;
  }

  // -------------------------------------------------------------------------
  // Query
  // -------------------------------------------------------------------------

  /// Gets the full record for a source, or null if not found.
  Future<IngestionRecord?> getRecord(String sourceId) async {
    final file = File('${_sourcesDir.path}/$sourceId.json');
    if (!await file.exists()) return null;
    try {
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final source = SourceContent.fromJson(
          raw['source'] as Map<String, dynamic>);
      final versions = (raw['versions'] as List<dynamic>)
          .map((v) => SourceVersion.fromJson(v as Map<String, dynamic>))
          .toList();
      final card = raw['card'] != null
          ? CardContract.fromJson(raw['card'] as Map<String, dynamic>)
          : null;
      return IngestionRecord(
          source: source, versions: versions, card: card);
    } catch (_) {
      return null;
    }
  }

  /// Finds an existing card for a source, or null.
  Future<CardContract?> getCardForSource(String sourceId) async {
    final record = await getRecord(sourceId);
    return record?.card;
  }

  /// Lists all source IDs in the store.
  Future<List<String>> listSourceIds() async {
    if (!await _sourceIndex.exists()) return [];
    try {
      final raw = jsonDecode(await _sourceIndex.readAsString()) as List;
      return raw
          .map((e) => (e as Map<String, dynamic>)['source_id'] as String)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Lists all cards in the store.
  Future<List<CardContract>> listCards() async {
    if (!await _cardsIndex.exists()) return [];
    try {
      final raw = jsonDecode(await _cardsIndex.readAsString()) as List;
      return raw
          .map((e) => CardContract.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // -------------------------------------------------------------------------
  // Internal persistence
  // -------------------------------------------------------------------------

  Future<void> _writeRecord(IngestionRecord record) async {
    final file = File('${_sourcesDir.path}/${record.source.sourceId}.json');
    await file.writeAsString(jsonEncode({
      'source': record.source.toJson(),
      'versions': record.versions.map((v) => v.toJson()).toList(),
      if (record.card != null) 'card': record.card!.toJson(),
    }));
  }

  Future<void> _addToSourceIndex(SourceContent source) async {
    final ids = await listSourceIds();
    if (ids.contains(source.sourceId)) return;
    final entries = await _readSourceIndexEntries();
    entries.add({
      'source_id': source.sourceId,
      'canonical_url': source.metadata['canonical_url'] ?? '',
      'title': source.title,
      'provider': source.provider ?? '',
    });
    await _sourceIndex.writeAsString(jsonEncode(entries));
  }

  Future<void> _updateSourceIndex(SourceContent source) async {
    final entries = await _readSourceIndexEntries();
    final idx = entries.indexWhere(
        (e) => e['source_id'] == source.sourceId);
    if (idx >= 0) {
      entries[idx] = {
        'source_id': source.sourceId,
        'canonical_url': source.metadata['canonical_url'] ?? '',
        'title': source.title,
        'provider': source.provider ?? '',
      };
    } else {
      entries.add({
        'source_id': source.sourceId,
        'canonical_url': source.metadata['canonical_url'] ?? '',
        'title': source.title,
        'provider': source.provider ?? '',
      });
    }
    await _sourceIndex.writeAsString(jsonEncode(entries));
  }

  Future<List<Map<String, dynamic>>> _readSourceIndexEntries() async {
    if (!await _sourceIndex.exists()) return [];
    try {
      final raw = jsonDecode(await _sourceIndex.readAsString()) as List;
      return raw.cast<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _addCardToIndex(CardContract card) async {
    final cards = await listCards();
    if (cards.any((c) => c.cardId == card.cardId)) return;
    final raw = cards.map((c) => c.toJson()).toList();
    raw.add(card.toJson());
    await _cardsIndex.writeAsString(jsonEncode(raw));
  }

  Future<void> _updateCardInIndex(CardContract card) async {
    final cards = await listCards();
    final idx = cards.indexWhere((c) => c.cardId == card.cardId);
    final raw = cards.map((c) => c.toJson()).toList();
    if (idx >= 0) {
      raw[idx] = card.toJson();
    } else {
      raw.add(card.toJson());
    }
    await _cardsIndex.writeAsString(jsonEncode(raw));
  }
}