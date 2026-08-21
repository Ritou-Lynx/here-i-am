/// Provider-neutral, JSON-serializable contracts for the read-only
/// whiteboard AI tool host.
library;

/// Output bounds for one read-tool call.
///
/// Callers may tune values within this contract (lower values are preferred
/// for narrower runtime profiles). Every value is validated against a
/// non-overridable hard ceiling, so configuration can never expand the trust
/// boundary established by this contract.
class WhiteboardAiReadLimits {
  factory WhiteboardAiReadLimits({
    int maxCardIds = 32,
    int maxSourceIds = 32,
    int maxBoardItems = 256,
    int maxGroups = 128,
    int maxGroupMembers = 512,
    int maxEdges = 512,
    int maxVersionsPerSource = 20,
    int maxTagsPerCard = 32,
    int maxIssues = 128,
    int maxTitleRunes = 512,
    int maxBodyExcerptRunes = 600,
    int maxBodyRunes = 6000,
    int maxLabelRunes = 512,
    int maxSerializedUtf8Bytes = 128 * 1024,
  }) {
    _validate('maxCardIds', maxCardIds, hardMaxCardIds);
    _validate('maxSourceIds', maxSourceIds, hardMaxSourceIds);
    _validate('maxBoardItems', maxBoardItems, hardMaxBoardItems);
    _validate('maxGroups', maxGroups, hardMaxGroups);
    _validate('maxGroupMembers', maxGroupMembers, hardMaxGroupMembers);
    _validate('maxEdges', maxEdges, hardMaxEdges);
    _validate(
      'maxVersionsPerSource',
      maxVersionsPerSource,
      hardMaxVersionsPerSource,
    );
    _validate('maxTagsPerCard', maxTagsPerCard, hardMaxTagsPerCard);
    _validate('maxIssues', maxIssues, hardMaxIssues);
    _validate('maxTitleRunes', maxTitleRunes, hardMaxTitleRunes);
    _validate(
      'maxBodyExcerptRunes',
      maxBodyExcerptRunes,
      hardMaxBodyExcerptRunes,
    );
    _validate('maxBodyRunes', maxBodyRunes, hardMaxBodyRunes);
    _validate('maxLabelRunes', maxLabelRunes, hardMaxLabelRunes);
    if (maxSerializedUtf8Bytes < minSerializedUtf8Bytes ||
        maxSerializedUtf8Bytes > hardMaxSerializedUtf8Bytes) {
      throw RangeError.range(
        maxSerializedUtf8Bytes,
        minSerializedUtf8Bytes,
        hardMaxSerializedUtf8Bytes,
        'maxSerializedUtf8Bytes',
      );
    }
    return WhiteboardAiReadLimits._(
      maxCardIds: maxCardIds,
      maxSourceIds: maxSourceIds,
      maxBoardItems: maxBoardItems,
      maxGroups: maxGroups,
      maxGroupMembers: maxGroupMembers,
      maxEdges: maxEdges,
      maxVersionsPerSource: maxVersionsPerSource,
      maxTagsPerCard: maxTagsPerCard,
      maxIssues: maxIssues,
      maxTitleRunes: maxTitleRunes,
      maxBodyExcerptRunes: maxBodyExcerptRunes,
      maxBodyRunes: maxBodyRunes,
      maxLabelRunes: maxLabelRunes,
      maxSerializedUtf8Bytes: maxSerializedUtf8Bytes,
    );
  }

  const WhiteboardAiReadLimits._({
    required this.maxCardIds,
    required this.maxSourceIds,
    required this.maxBoardItems,
    required this.maxGroups,
    required this.maxGroupMembers,
    required this.maxEdges,
    required this.maxVersionsPerSource,
    required this.maxTagsPerCard,
    required this.maxIssues,
    required this.maxTitleRunes,
    required this.maxBodyExcerptRunes,
    required this.maxBodyRunes,
    required this.maxLabelRunes,
    required this.maxSerializedUtf8Bytes,
  });

  static const hardMaxCardIds = 64;
  static const hardMaxSourceIds = 64;
  static const hardMaxBoardItems = 512;
  static const hardMaxGroups = 256;
  static const hardMaxGroupMembers = 1024;
  static const hardMaxEdges = 1024;
  static const hardMaxVersionsPerSource = 64;
  static const hardMaxTagsPerCard = 64;
  static const hardMaxIssues = 256;
  static const hardMaxTitleRunes = 2048;
  static const hardMaxBodyExcerptRunes = 2048;
  static const hardMaxBodyRunes = 32768;
  static const hardMaxLabelRunes = 2048;
  static const minSerializedUtf8Bytes = 64 * 1024;
  static const hardMaxSerializedUtf8Bytes = 256 * 1024;

  static void _validate(String name, int value, int ceiling) {
    if (value < 0 || value > ceiling) {
      throw RangeError.range(value, 0, ceiling, name);
    }
  }

  final int maxCardIds;
  final int maxSourceIds;
  final int maxBoardItems;
  final int maxGroups;
  final int maxGroupMembers;
  final int maxEdges;
  final int maxVersionsPerSource;
  final int maxTagsPerCard;
  final int maxIssues;
  final int maxTitleRunes;
  final int maxBodyExcerptRunes;
  final int maxBodyRunes;
  final int maxLabelRunes;
  final int maxSerializedUtf8Bytes;
}

class WhiteboardAiReadRequest {
  const WhiteboardAiReadRequest({
    required this.boardId,
    required this.cardIds,
    required this.sourceIds,
  });

  final String boardId;
  final List<String> cardIds;
  final List<String> sourceIds;

  Map<String, dynamic> toJson() => {
        'board_id': boardId,
        'card_ids': cardIds,
        'source_ids': sourceIds,
      };
}

enum WhiteboardAiReadStatus {
  ok,
  partial,
  invalidRequest,
  unavailable;

  String get wireName => switch (this) {
        WhiteboardAiReadStatus.invalidRequest => 'invalid_request',
        _ => name,
      };
}

class WhiteboardAiReadIssue {
  const WhiteboardAiReadIssue({
    required this.code,
    this.entityType,
    this.entityId,
  });

  final String code;
  final String? entityType;
  final String? entityId;

  Map<String, dynamic> toJson() => {
        'code': code,
        if (entityType != null) 'entity_type': entityType,
        if (entityId != null) 'entity_id': entityId,
      };
}

class WhiteboardAiReadTruncation {
  const WhiteboardAiReadTruncation({
    required this.field,
    required this.limit,
    required this.omittedCount,
  });

  final String field;
  final int limit;
  final int omittedCount;

  Map<String, dynamic> toJson() => {
        'field': field,
        'limit': limit,
        'omitted_count': omittedCount,
      };
}

class WhiteboardAiReadProvenance {
  const WhiteboardAiReadProvenance({
    required this.entityType,
    required this.entityId,
    this.sourceId,
    this.sourceVersionId,
  });

  final String entityType;
  final String entityId;
  final String? sourceId;
  final String? sourceVersionId;

  Map<String, dynamic> toJson() => {
        'entity_type': entityType,
        'entity_id': entityId,
        if (sourceId != null) 'source_id': sourceId,
        if (sourceVersionId != null) 'source_version_id': sourceVersionId,
      };
}

class WhiteboardAiReadBoard {
  const WhiteboardAiReadBoard({required this.boardId, required this.name});

  final String boardId;
  final String name;

  Map<String, dynamic> toJson() => {
        'board_id': boardId,
        'name': name,
        'provenance': WhiteboardAiReadProvenance(
          entityType: 'board',
          entityId: boardId,
        ).toJson(),
      };
}

class WhiteboardAiReadCard {
  const WhiteboardAiReadCard({
    required this.cardId,
    required this.cardKind,
    required this.title,
    required this.bodyExcerpt,
    required this.body,
    required this.tags,
    this.sourceId,
    this.sourceVersionId,
    required this.bodyTruncated,
  });

  final String cardId;
  final String cardKind;
  final String title;

  /// Deterministic prefix of [body], not an AI-generated semantic summary.
  final String bodyExcerpt;
  final String body;
  final List<String> tags;
  final String? sourceId;
  final String? sourceVersionId;
  final bool bodyTruncated;

  Map<String, dynamic> toJson() => {
        'card_id': cardId,
        'card_kind': cardKind,
        'title': title,
        'body_excerpt': bodyExcerpt,
        'body': body,
        'tags': tags,
        if (sourceId != null) 'source_id': sourceId,
        if (sourceVersionId != null)
          'current_source_version_id': sourceVersionId,
        'body_truncated': bodyTruncated,
        'provenance': WhiteboardAiReadProvenance(
          entityType: 'card',
          entityId: cardId,
          sourceId: sourceId,
          sourceVersionId: sourceVersionId,
        ).toJson(),
      };
}

class WhiteboardAiReadSourceVersion {
  const WhiteboardAiReadSourceVersion({
    required this.versionId,
    required this.sourceId,
    required this.contentHash,
    this.parserVersion,
    required this.createdAt,
  });

  final String versionId;
  final String sourceId;
  final String contentHash;
  final String? parserVersion;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'version_id': versionId,
        'source_id': sourceId,
        'content_hash': contentHash,
        if (parserVersion != null) 'parser_version': parserVersion,
        'created_at': createdAt.toUtc().toIso8601String(),
        'provenance': WhiteboardAiReadProvenance(
          entityType: 'source_version',
          entityId: versionId,
          sourceId: sourceId,
          sourceVersionId: versionId,
        ).toJson(),
      };
}

class WhiteboardAiReadSource {
  const WhiteboardAiReadSource({
    required this.sourceId,
    required this.mediaType,
    required this.title,
    required this.origin,
    this.provider,
    this.canonicalId,
    this.mimeType,
    this.currentVersionId,
    required this.versions,
    required this.untrustedMetadataOmitted,
  });

  final String sourceId;
  final String mediaType;
  final String title;
  final String origin;
  final String? provider;
  final String? canonicalId;
  final String? mimeType;
  final String? currentVersionId;
  final List<WhiteboardAiReadSourceVersion> versions;
  final bool untrustedMetadataOmitted;

  Map<String, dynamic> toJson() => {
        'source_id': sourceId,
        'media_type': mediaType,
        'title': title,
        'origin': origin,
        if (provider != null) 'provider': provider,
        if (canonicalId != null) 'canonical_id': canonicalId,
        if (mimeType != null) 'mime_type': mimeType,
        if (currentVersionId != null) 'current_version_id': currentVersionId,
        'versions': versions.map((version) => version.toJson()).toList(),
        'untrusted_metadata_omitted': untrustedMetadataOmitted,
        'provenance': WhiteboardAiReadProvenance(
          entityType: 'source',
          entityId: sourceId,
          sourceId: sourceId,
          sourceVersionId: currentVersionId,
        ).toJson(),
      };
}

class WhiteboardAiReadBoardItem {
  const WhiteboardAiReadBoardItem({
    required this.itemId,
    required this.boardId,
    required this.cardId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rotation,
    required this.zIndex,
  });

  final String itemId;
  final String boardId;
  final String cardId;
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
  final int zIndex;

  Map<String, dynamic> toJson() => {
        'item_id': itemId,
        'board_id': boardId,
        'card_id': cardId,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'rotation': rotation,
        'z_index': zIndex,
        'provenance': WhiteboardAiReadProvenance(
          entityType: 'board_item',
          entityId: itemId,
        ).toJson(),
      };
}

class WhiteboardAiReadGroup {
  const WhiteboardAiReadGroup({
    required this.groupId,
    required this.boardId,
    required this.name,
    required this.collapsed,
  });

  final String groupId;
  final String boardId;
  final String name;
  final bool collapsed;

  Map<String, dynamic> toJson() => {
        'group_id': groupId,
        'board_id': boardId,
        'name': name,
        'collapsed': collapsed,
        'provenance': WhiteboardAiReadProvenance(
          entityType: 'board_group',
          entityId: groupId,
        ).toJson(),
      };
}

class WhiteboardAiReadGroupMember {
  const WhiteboardAiReadGroupMember({
    required this.groupId,
    required this.itemId,
    required this.order,
  });

  final String groupId;
  final String itemId;
  final int order;

  Map<String, dynamic> toJson() => {
        'group_id': groupId,
        'item_id': itemId,
        'order': order,
        'provenance': {
          'entity_type': 'group_member',
          'entity_id': '$groupId:$itemId',
        },
      };
}

class WhiteboardAiReadEdge {
  const WhiteboardAiReadEdge({
    required this.edgeId,
    required this.boardId,
    required this.fromItemId,
    required this.toItemId,
    required this.direction,
    this.semanticType,
    this.label,
  });

  final String edgeId;
  final String boardId;
  final String fromItemId;
  final String toItemId;
  final String direction;
  final String? semanticType;
  final String? label;

  Map<String, dynamic> toJson() => {
        'edge_id': edgeId,
        'board_id': boardId,
        'from_item_id': fromItemId,
        'to_item_id': toItemId,
        'direction': direction,
        if (semanticType != null) 'semantic_type': semanticType,
        if (label != null) 'label': label,
        'provenance': WhiteboardAiReadProvenance(
          entityType: 'board_edge',
          entityId: edgeId,
        ).toJson(),
      };
}

class WhiteboardAiReadSnapshot {
  const WhiteboardAiReadSnapshot({
    required this.status,
    required this.request,
    this.board,
    this.cards = const [],
    this.sources = const [],
    this.boardItems = const [],
    this.groups = const [],
    this.groupMembers = const [],
    this.edges = const [],
    this.issues = const [],
    this.truncations = const [],
  });

  final WhiteboardAiReadStatus status;
  final WhiteboardAiReadRequest request;
  final WhiteboardAiReadBoard? board;
  final List<WhiteboardAiReadCard> cards;
  final List<WhiteboardAiReadSource> sources;
  final List<WhiteboardAiReadBoardItem> boardItems;
  final List<WhiteboardAiReadGroup> groups;
  final List<WhiteboardAiReadGroupMember> groupMembers;
  final List<WhiteboardAiReadEdge> edges;
  final List<WhiteboardAiReadIssue> issues;
  final List<WhiteboardAiReadTruncation> truncations;

  Map<String, dynamic> toJson() => {
        'schema_version': 1,
        'status': status.wireName,
        'request_scope': request.toJson(),
        if (board != null) 'board': board!.toJson(),
        'cards': cards.map((card) => card.toJson()).toList(),
        'sources': sources.map((source) => source.toJson()).toList(),
        'board_items': boardItems.map((item) => item.toJson()).toList(),
        'groups': groups.map((group) => group.toJson()).toList(),
        'group_members': groupMembers.map((member) => member.toJson()).toList(),
        'edges': edges.map((edge) => edge.toJson()).toList(),
        if (issues.isNotEmpty)
          'issues': issues.map((issue) => issue.toJson()).toList(),
        if (truncations.isNotEmpty)
          'truncations':
              truncations.map((truncation) => truncation.toJson()).toList(),
      };
}
