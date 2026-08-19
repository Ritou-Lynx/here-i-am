/// Link ingestion application service.
///
/// Fetching produces only an IngestionResult. Drift Source / SourceVersion /
/// Card rows are written together only after an explicit commit.
library;

import 'package:memex/data/whiteboard/ingestion/link_ingestor.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/domain/whiteboard/source_content.dart';

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
  })  : _repository = repository,
        _ingestor = ingestor ?? LinkIngestor();

  final UnifiedCardRepository _repository;
  final LinkIngestor _ingestor;

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
    final committed = await _repository.commitIngestion(
      result,
      cardKind: cardKind,
      ownerSpace: ownerSpace,
      createdBy: createdBy,
    );
    return LinkIngestionOutcome(
      result: result,
      upsert: committed,
      card: committed.card,
      cardCreated: committed.cardCreated,
      cardUpdated: !committed.cardCreated && committed.versionIsNew,
    );
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

  Future<List<CardContract>> listCards() async =>
      (await _repository.listCards()).map((record) => record.card).toList();
}
