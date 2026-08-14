/// Link ingestion service — the application layer that decides whether
/// to create or update a Card from an [IngestionResult].
///
/// This is the public API for W3. UI / other services call [ingestUrl],
/// which:
///   1. Runs [LinkIngestor] to produce an [IngestionResult];
///   2. Persists Source + SourceVersion via [IngestionStore] (with
///      de-dup);
///   3. If [createCard] is true (default), creates or updates a Card
///      referencing the source.
///
/// The ingestor itself never writes Cards — this service makes the
/// explicit "yes, create a card" decision on behalf of the application.
library;

import 'package:memex/data/whiteboard/ingestion/ingestion_store.dart';
import 'package:memex/data/whiteboard/ingestion/link_ingestor.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/domain/whiteboard/source_content.dart';

/// Outcome of a full ingestion with persistence + card creation.
class LinkIngestionOutcome {
  final IngestionResult result;
  final UpsertResult? upsert;
  final CardContract? card;
  final bool cardCreated;
  final bool cardUpdated;

  const LinkIngestionOutcome({
    required this.result,
    this.upsert,
    this.card,
    this.cardCreated = false,
    this.cardUpdated = false,
  });

  bool get succeeded => result.status == IngestionStatus.ok;
}

/// Application-layer service for ingesting links.
class LinkIngestionService {
  LinkIngestionService({
    required IngestionStore store,
    LinkIngestor? ingestor,
  })  : _store = store,
        _ingestor = ingestor ?? LinkIngestor();

  final IngestionStore _store;
  final LinkIngestor _ingestor;

  /// Ingests [url] and optionally creates/updates a Card.
  ///
  /// Set [createCard] to false to only persist the Source + Version
  /// without creating a Card (e.g. for a "fetch only" preview flow).
  Future<LinkIngestionOutcome> ingestUrl(
    String url, {
    bool createCard = true,
    CardKind cardKind = CardKind.source,
    OwnerSpace ownerSpace = OwnerSpace.user,
    CardCreatedBy createdBy = CardCreatedBy.user,
  }) async {
    final result = await _ingestor.ingest(url);

    if (result.status != IngestionStatus.ok || result.source == null) {
      return LinkIngestionOutcome(result: result);
    }

    final upsert = await _store.upsertSource(result);

    CardContract? card;
    bool cardCreated = false;
    bool cardUpdated = false;

    if (createCard) {
      final existing = await _store.getCardForSource(result.source!.sourceId);
      card = await _store.createOrUpdateCard(
        result: result,
        kind: cardKind,
        ownerSpace: ownerSpace,
        createdBy: createdBy,
      );
      if (existing == null) {
        cardCreated = true;
      } else {
        cardUpdated = true;
      }
    }

    return LinkIngestionOutcome(
      result: result,
      upsert: upsert,
      card: card,
      cardCreated: cardCreated,
      cardUpdated: cardUpdated,
    );
  }

  /// Returns the stored record for a source, or null.
  Future<IngestionRecord?> getSource(String sourceId) =>
      _store.getRecord(sourceId);

  /// Lists all cards.
  Future<List<CardContract>> listCards() => _store.listCards();
}