/// Link ingestion application service.
///
/// Fetching produces only an IngestionResult. Drift Source / SourceVersion /
/// Card rows are written together only after an explicit commit.
library;

import 'dart:async';

import 'package:memex/data/whiteboard/ingestion/link_ingestor.dart';
import 'package:memex/data/whiteboard/ingestion/xiaohongshu_evidence_processor.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/domain/whiteboard/rich_text_object_store.dart';

class LinkIngestionRecord {
  const LinkIngestionRecord({
    required this.source,
    required this.versions,
    this.card,
  });

  final SourceContent source;
  final List<SourceVersion> versions;
  final CardContract? card;
}

class LinkIngestionOutcome {
  const LinkIngestionOutcome({
    required this.result,
    this.upsert,
    this.card,
    this.cardCreated = false,
    this.cardUpdated = false,
  });

  final IngestionResult result;
  final IngestionCommitResult? upsert;
  final CardContract? card;
  final bool cardCreated;
  final bool cardUpdated;

  bool get succeeded => result.status == IngestionStatus.ok;
}

class LinkIngestionService {
  LinkIngestionService({
    required UnifiedCardRepository repository,
    LinkIngestor? ingestor,
    XiaohongshuEvidenceProcessor? xiaohongshuEvidenceProcessor,
  })  : _repository = repository,
        _ingestor = ingestor ?? LinkIngestor(),
        _xiaohongshuEvidenceProcessor = xiaohongshuEvidenceProcessor ??
            XiaohongshuEvidenceProcessor(
              objectStore: RichTextObjectStore(repository.whiteboardRoot),
            );

  final UnifiedCardRepository _repository;
  final LinkIngestor _ingestor;
  final XiaohongshuEvidenceProcessor _xiaohongshuEvidenceProcessor;
  static final Map<String, Completer<void>> _commitLocks = {};

  /// Fetches [url] without persistence by default.
  ///
  /// [createCard] must be explicitly true for a caller-owned confirmation
  /// flow. Preview UIs should normally call [commitResult] with the exact
  /// result already shown to the user.
  Future<LinkIngestionOutcome> ingestUrl(
    String url, {
    bool createCard = false,
    CardKind cardKind = CardKind.source,
    OwnerSpace ownerSpace = OwnerSpace.user,
    CardCreatedBy createdBy = CardCreatedBy.user,
  }) async {
    final result = await _ingestor.ingest(url);
    if (!createCard || result.status != IngestionStatus.ok) {
      return LinkIngestionOutcome(result: result);
    }
    return commitResult(
      result,
      cardKind: cardKind,
      ownerSpace: ownerSpace,
      createdBy: createdBy,
    );
  }

  /// Commits a previously presented successful result without re-fetching.
  Future<LinkIngestionOutcome> commitResult(
    IngestionResult result, {
    CardKind cardKind = CardKind.source,
    OwnerSpace ownerSpace = OwnerSpace.user,
    CardCreatedBy createdBy = CardCreatedBy.user,
  }) async {
    if (result.status != IngestionStatus.ok) {
      return LinkIngestionOutcome(result: result);
    }
    final key = result.source?.sourceId ?? result.canonicalUrl;
    while (_commitLocks.containsKey(key)) {
      await _commitLocks[key]!.future;
    }
    final lock = Completer<void>();
    _commitLocks[key] = lock;
    try {
      final committedResult = result.provider == 'xiaohongshu'
          ? await _xiaohongshuEvidenceProcessor.process(result)
          : result;
      final committed = await _repository.commitIngestion(
        committedResult,
        cardKind: cardKind,
        ownerSpace: ownerSpace,
        createdBy: createdBy,
      );
      return LinkIngestionOutcome(
        result: committedResult,
        upsert: committed,
        card: committed.card,
        cardCreated: committed.cardCreated,
        cardUpdated: !committed.cardCreated && committed.versionIsNew,
      );
    } finally {
      if (identical(_commitLocks[key], lock)) _commitLocks.remove(key);
      lock.complete();
    }
  }

  Future<LinkIngestionRecord?> getSource(String sourceId) async {
    final source = await _repository.getSource(sourceId);
    if (source == null) return null;
    return LinkIngestionRecord(
      source: source,
      versions: await _repository.listSourceVersions(sourceId),
      card: await _repository.getCardForSource(sourceId),
    );
  }

  /// Cards created by the ingestion flow, for the import screen's recent
  /// history. Ordinary notes, annotations and task artifacts must never leak
  /// into this projection merely because they share the unified repository.
  Future<List<CardContract>> listCards() async => (await _repository.listCards(
        const CardLibraryQuery(kinds: {CardKind.source}),
      ))
          .map((record) => record.card)
          .where((card) => card.sourceId?.trim().isNotEmpty == true)
          .toList();
}
