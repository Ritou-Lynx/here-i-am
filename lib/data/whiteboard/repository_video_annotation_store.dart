/// Repository-backed persistence for video Anchor + Annotation Card pairs.
///
/// The unified card repository is the only card truth. Session JSON may keep
/// playback UI state, but production restore always queries annotation cards
/// from this store.
library;

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/domain/whiteboard/anchor_contract.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/video/video_annotation_service.dart';

abstract interface class VideoAnnotationStore {
  Future<VideoAnnotationResult> createAnnotation({
    required String sourceId,
    required String sourceVersionId,
    required AnnotationCreationRequest request,
  });

  Future<List<VideoAnnotationResult>> listAnnotations({
    required String sourceId,
    required String currentVersionId,
    int? currentDurationMs,
  });

  Future<CardContract> updateAnnotationCard({
    required String cardId,
    required String title,
    required String body,
  });
}

class RepositoryVideoAnnotationStore implements VideoAnnotationStore {
  const RepositoryVideoAnnotationStore(this.repository);

  final UnifiedCardRepository repository;

  /// Persists the complete Source-bound Annotation Card atomically.
  @override
  Future<VideoAnnotationResult> createAnnotation({
    required String sourceId,
    required String sourceVersionId,
    required AnnotationCreationRequest request,
  }) async {
    final draft = VideoAnnotationService().createAnnotation(
      sourceId: sourceId,
      sourceVersionId: sourceVersionId,
      request: request,
    );
    final persisted = await repository.createVideoAnnotationCard(
      CardContract(
        cardId: draft.card.cardId,
        cardKind: CardKind.annotation,
        sourceId: sourceId,
        ownerSpace: draft.card.ownerSpace,
        title: draft.card.title,
        body: draft.card.body,
        tags: draft.card.tags,
        presentation: {
          ...draft.card.presentation,
          'anchor': draft.anchor.toJson(),
        },
        createdBy: draft.card.createdBy,
        createdAt: draft.card.createdAt,
        updatedAt: draft.card.updatedAt,
      ),
    );
    return VideoAnnotationResult(anchor: draft.anchor, card: persisted);
  }

  /// Updates the editable Card projection without changing its immutable
  /// Anchor identity or time range.
  @override
  Future<CardContract> updateAnnotationCard({
    required String cardId,
    required String title,
    required String body,
  }) {
    return repository.updateCardMetadata(
      cardId,
      title: title,
      body: body,
    );
  }

  /// Restores annotation cards for one Source from the unified repository.
  /// A changed version preserves the old identity and is always exposed as
  /// orphaned. Duration overlap alone is not valid re-anchor evidence.
  @override
  Future<List<VideoAnnotationResult>> listAnnotations({
    required String sourceId,
    required String currentVersionId,
    int? currentDurationMs,
  }) async {
    final records = await repository.listCards(
      const CardLibraryQuery(kinds: {CardKind.annotation}),
    );
    final restored = <VideoAnnotationResult>[];
    for (final record in records) {
      final card = record.card;
      if (card.sourceId != sourceId) continue;
      final raw = card.presentation['anchor'];
      if (raw is! Map) continue;
      try {
        final anchor = AnchorContract.fromJson(Map<String, dynamic>.from(raw));
        restored.add(
          VideoAnnotationResult(
            anchor: _resolveAnchor(
              anchor,
              currentVersionId: currentVersionId,
            ),
            card: card,
          ),
        );
      } catch (_) {
        // The card remains visible in the card library for repair/export.
      }
    }
    return restored;
  }

  static AnchorContract _resolveAnchor(
    AnchorContract anchor, {
    required String currentVersionId,
  }) {
    if (anchor.sourceVersionId == currentVersionId) return anchor;
    return AnchorContract(
      anchorId: anchor.anchorId,
      sourceId: anchor.sourceId,
      sourceVersionId: anchor.sourceVersionId,
      positionKind: anchor.positionKind,
      positionSpec: anchor.positionSpec,
      quote: anchor.quote,
      prefix: anchor.prefix,
      suffix: anchor.suffix,
      fingerprint: anchor.fingerprint,
      status: AnchorStatus.orphaned,
      createdAt: anchor.createdAt,
    );
  }
}
