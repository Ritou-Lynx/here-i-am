/// Video annotation service — creates and restores time anchors + annotation cards.
///
/// This service bridges the video player domain with the shared [AnchorContract]
/// and [CardContract]. It creates time_range anchors and annotation cards that
/// reference those anchors. On restart, it restores annotations and re-resolves
/// anchor status against the current source version.
///
/// **No User-truth writing.** Annotations are standalone cards in the
/// whiteboard domain. The user must explicitly choose to record something
/// via the Record Organizer for it to enter User-truth.
library;

import '../anchor_contract.dart';
import '../card_contract.dart';
import '../source_content.dart';
import '../whiteboard_ids.dart';
import 'time_range_anchor_spec.dart';

/// A snapshot of a video annotation session, persisted for restart recovery.
class VideoAnnotationSession {
  final String sourceId;
  final String sourceVersionId;
  final int lastPositionMs;
  final List<AnchorContract> anchors;
  final List<CardContract> annotationCards;
  final Map<String, String> anchorToCard;
  final DateTime savedAt;

  const VideoAnnotationSession({
    required this.sourceId,
    required this.sourceVersionId,
    required this.lastPositionMs,
    required this.anchors,
    required this.annotationCards,
    required this.anchorToCard,
    required this.savedAt,
  });

  factory VideoAnnotationSession.fromJson(Map<String, dynamic> json) {
    return VideoAnnotationSession(
      sourceId: json['source_id'] as String,
      sourceVersionId: json['source_version_id'] as String,
      lastPositionMs: (json['last_position_ms'] as num?)?.toInt() ?? 0,
      anchors: (json['anchors'] as List<dynamic>)
          .map((a) => AnchorContract.fromJson(a as Map<String, dynamic>))
          .toList(),
      annotationCards: (json['annotation_cards'] as List<dynamic>)
          .map((c) => CardContract.fromJson(c as Map<String, dynamic>))
          .toList(),
      anchorToCard: (json['anchor_to_card'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          const {},
      savedAt: DateTime.parse(json['saved_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'source_id': sourceId,
        'source_version_id': sourceVersionId,
        'last_position_ms': lastPositionMs,
        'anchors': anchors.map((a) => a.toJson()).toList(),
        'annotation_cards': annotationCards.map((c) => c.toJson()).toList(),
        'anchor_to_card': anchorToCard,
        'saved_at': savedAt.toUtc().toIso8601String(),
      };
}

/// Creates a point or range anchor with an associated annotation card.
class AnnotationCreationRequest {
  final TimeRangeAnchorSpec spec;
  final String title;
  final String body;
  final String? quote;
  final CardCreatedBy createdBy;

  const AnnotationCreationRequest({
    required this.spec,
    this.title = '',
    this.body = '',
    this.quote,
    this.createdBy = CardCreatedBy.user,
  });
}

/// Result of creating a video annotation.
class VideoAnnotationResult {
  final AnchorContract anchor;
  final CardContract card;

  const VideoAnnotationResult({required this.anchor, required this.card});
}

/// Service for creating, saving, and restoring video annotations.
class VideoAnnotationService {
  /// Creates a time anchor + annotation card for a video source.
  VideoAnnotationResult createAnnotation({
    required String sourceId,
    required String sourceVersionId,
    required AnnotationCreationRequest request,
    DateTime? createdAt,
  }) {
    final now = createdAt ?? DateTime.now().toUtc();
    final anchorId = StableId.generate('anchor').value;
    final cardId = StableId.generate('card').value;

    final anchor = TimeRangeAnchorSpec.buildAnchor(
      anchorId: anchorId,
      sourceId: sourceId,
      sourceVersionId: sourceVersionId,
      spec: request.spec,
      quote: request.quote,
      createdAt: now,
    );

    final card = CardContract(
      cardId: cardId,
      cardKind: CardKind.annotation,
      sourceId: sourceId,
      ownerSpace: request.createdBy == CardCreatedBy.i
          ? OwnerSpace.i
          : OwnerSpace.user,
      title: request.title,
      body: request.body,
      tags: const ['video_annotation'],
      presentation: {
        'anchor_id': anchorId,
        'start_ms': request.spec.startMs,
        'end_ms': request.spec.endMs,
        'is_point': request.spec.isPoint,
      },
      createdBy: request.createdBy,
      createdAt: now,
    );

    return VideoAnnotationResult(anchor: anchor, card: card);
  }

  /// Saves a session snapshot for restart recovery.
  VideoAnnotationSession saveSession({
    required String sourceId,
    required String sourceVersionId,
    required int lastPositionMs,
    required List<AnchorContract> anchors,
    required List<CardContract> annotationCards,
    required Map<String, String> anchorToCard,
  }) {
    return VideoAnnotationSession(
      sourceId: sourceId,
      sourceVersionId: sourceVersionId,
      lastPositionMs: lastPositionMs,
      anchors: anchors,
      annotationCards: annotationCards,
      anchorToCard: anchorToCard,
      savedAt: DateTime.now().toUtc(),
    );
  }

  /// Restores a session from a saved snapshot, re-resolving anchor status
  /// against the current source version.
  ///
  /// If [currentVersionId] differs from the saved version, anchors that
  /// pointed to the old version get [AnchorStatus.reanchored] (we preserve
  /// the time position but mark it as re-anchored). If the source itself
  /// changed fundamentally, anchors become [AnchorStatus.orphaned].
  VideoAnnotationSession restoreSession({
    required VideoAnnotationSession saved,
    required String currentVersionId,
  }) {
    if (saved.sourceVersionId == currentVersionId) {
      return saved;
    }

    // Version changed — re-anchor time positions (timestamps are stable
    // for video content unless the video itself was replaced).
    final reanchored = saved.anchors.map((a) {
      if (a.status == AnchorStatus.orphaned) return a;
      return AnchorContract(
        anchorId: a.anchorId,
        sourceId: a.sourceId,
        sourceVersionId: currentVersionId,
        positionKind: a.positionKind,
        positionSpec: a.positionSpec,
        quote: a.quote,
        prefix: a.prefix,
        suffix: a.suffix,
        fingerprint: a.fingerprint,
        status: AnchorStatus.reanchored,
        createdAt: a.createdAt,
      );
    }).toList();

    return VideoAnnotationSession(
      sourceId: saved.sourceId,
      sourceVersionId: currentVersionId,
      lastPositionMs: saved.lastPositionMs,
      anchors: reanchored,
      annotationCards: saved.annotationCards,
      anchorToCard: saved.anchorToCard,
      savedAt: saved.savedAt,
    );
  }
}