/// Card contract — the unified organizational unit.
///
/// A `Card` is the content identity in the product. It has no `x / y / width /
/// height` — those belong to `BoardItem` (a card's placement on a specific
/// board). The same card can appear on multiple boards via multiple
/// `BoardItem`s. Deleting a `BoardItem` does not delete the `Card` or its
/// `SourceContent`.
library;

import 'source_content.dart';
import 'whiteboard_ids.dart';

/// The kind of a card.
enum CardKind {
  source,
  note,
  annotation,
  taskArtifact,
  reference;

  static CardKind fromString(String? raw) {
    switch (raw) {
      case 'source':
        return CardKind.source;
      case 'note':
        return CardKind.note;
      case 'annotation':
        return CardKind.annotation;
      case 'task_artifact':
        return CardKind.taskArtifact;
      case 'reference':
        return CardKind.reference;
      default:
        throw ArgumentError('Unknown CardKind: $raw');
    }
  }

  String get name {
    switch (this) {
      case CardKind.taskArtifact:
        return 'task_artifact';
      default:
        return toString().split('.').last;
    }
  }
}

/// Who created the card.
enum CardCreatedBy {
  user,
  i,
  system;

  static CardCreatedBy fromString(String? raw) {
    switch (raw) {
      case 'user':
        return CardCreatedBy.user;
      case 'i':
        return CardCreatedBy.i;
      case 'system':
        return CardCreatedBy.system;
      default:
        return CardCreatedBy.user;
    }
  }
}

/// The stable content identity of a card.
///
/// Cards hold title, body (their own content — source cards don't copy the
/// full original), tags, and presentation preferences. Layout coordinates
/// (`x / y / width / height`) are NOT on the card; they belong to `BoardItem`.
class CardContract {
  final String cardId;
  final CardKind cardKind;
  final String? sourceId;
  final OwnerSpace ownerSpace;
  final String title;
  final String body;
  final List<String> tags;
  final Map<String, dynamic> presentation;
  final CardCreatedBy createdBy;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  const CardContract({
    required this.cardId,
    required this.cardKind,
    this.sourceId,
    this.ownerSpace = OwnerSpace.user,
    this.title = '',
    this.body = '',
    this.tags = const [],
    this.presentation = const {},
    this.createdBy = CardCreatedBy.user,
    required this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  factory CardContract.fromJson(Map<String, dynamic> json) {
    return CardContract(
      cardId: StableId(json['card_id']).value,
      cardKind: CardKind.fromString(json['card_kind'] as String?),
      sourceId: tryStableId(json['source_id']),
      ownerSpace: OwnerSpace.fromString(json['owner_space'] as String?),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      presentation:
          (json['presentation'] as Map<String, dynamic>?) ?? const {},
      createdBy: CardCreatedBy.fromString(json['created_by'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'card_id': cardId,
        'card_kind': cardKind.name,
        if (sourceId != null) 'source_id': sourceId,
        'owner_space': ownerSpace.name,
        'title': title,
        'body': body,
        if (tags.isNotEmpty) 'tags': tags,
        if (presentation.isNotEmpty) 'presentation': presentation,
        'created_by': createdBy.name,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
        if (deletedAt != null) 'deleted_at': deletedAt!.toUtc().toIso8601String(),
      };
}