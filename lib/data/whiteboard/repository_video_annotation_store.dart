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

class RepositoryVideoAnnotationStore {
  const RepositoryVideoAnnotationStore(this.repository);

  final UnifiedCardRepository repository;

  /// Creates the Card first, then links Source and installs annotation kind +
  /// the complete Anchor presentation, matching the F4 write-order contract.
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
    await repository.createTextCard(
      cardId: draft.card.cardId,
      title: draft.card.title,
      body: draft.card.body,
      tags: draft.card.tags,
      ownerSpace: draft.card.ownerSpace,
      createdBy: draft.card.createdBy,
      createdAt: draft.card.createdAt,
    );
    await repository.linkSourceToCard(draft.card.cardId, sourceId);
    final persisted = await repository.updateCardMetadata(
      draft.card.cardId,
      cardKind: CardKind.annotation,
      presentation: {
        ...draft.card.presentation,
        'anchor': draft.anchor.toJson(),
      },
    );
    return VideoAnnotationResult(anchor: draft.anchor, card: persisted);
  }

  /// Restores annotation cards for one Source from the unified repository.
  /// A changed version re-anchors only when the time range still fits the
  /// current duration; otherwise the Anchor is exposed as orphaned.
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
              currentDurationMs: currentDurationMs,
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
    int? currentDurationMs,
  }) {
    if (anchor.sourceVersionId == currentVersionId) return anchor;
    final endMs = (anchor.positionSpec['end_ms'] as num?)?.toInt();
    final canReanchor =
        endMs != null &&
        endMs >= 0 &&
        currentDurationMs != null &&
        currentDurationMs > 0 &&
        endMs <= currentDurationMs;
    return AnchorContract(
      anchorId: anchor.anchorId,
      sourceId: anchor.sourceId,
      sourceVersionId: canReanchor ? currentVersionId : anchor.sourceVersionId,
      positionKind: anchor.positionKind,
      positionSpec: anchor.positionSpec,
      quote: anchor.quote,
      prefix: anchor.prefix,
      suffix: anchor.suffix,
      fingerprint: anchor.fingerprint,
      status: canReanchor ? AnchorStatus.reanchored : AnchorStatus.orphaned,
      createdAt: anchor.createdAt,
    );
  }
}
