/// Read-only, provider-neutral whiteboard tool host.
///
/// The host accepts only explicit stable IDs and projects a bounded JSON-safe
/// selection snapshot. It deliberately exposes neither Drift, object refs,
/// raw metadata, presentation/view/style JSON, nor filesystem paths.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:memex/data/whiteboard/ai_read_tools/whiteboard_ai_read_models.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';

class WhiteboardAiReadToolHost {
  WhiteboardAiReadToolHost({
    required this.cards,
    required this.boards,
    WhiteboardAiReadLimits? limits,
  }) : limits = limits ?? WhiteboardAiReadLimits();

  final UnifiedCardRepository cards;
  final WhiteboardDriftStore boards;
  final WhiteboardAiReadLimits limits;

  Future<WhiteboardAiReadSnapshot> readSelection(
    WhiteboardAiReadRequest request,
  ) async {
    final validationIssues = _validateRequest(request);
    if (validationIssues.isNotEmpty) {
      return WhiteboardAiReadSnapshot(
        status: WhiteboardAiReadStatus.invalidRequest,
        request: _boundedRequestScope(request),
        issues: validationIssues,
      );
    }

    final scopedRequest = WhiteboardAiReadRequest(
      boardId: request.boardId,
      cardIds: _deduplicate(request.cardIds),
      sourceIds: _deduplicate(request.sourceIds),
    );
    final issues = <WhiteboardAiReadIssue>[];
    final truncations = <WhiteboardAiReadTruncation>[];

    final loaded = await boards.load(scopedRequest.boardId);
    if (!loaded.isSuccess || loaded.snapshot == null) {
      return WhiteboardAiReadSnapshot(
        status: WhiteboardAiReadStatus.unavailable,
        request: scopedRequest,
        issues: const [
          WhiteboardAiReadIssue(
            code: 'board_absent_deleted_or_unavailable',
            entityType: 'board',
          ),
        ],
      );
    }

    final snapshot = loaded.snapshot!;
    final matchingBoards = snapshot.boards.where(
      (board) =>
          board.boardId == scopedRequest.boardId && board.deletedAt == null,
    );
    if (matchingBoards.isEmpty) {
      return WhiteboardAiReadSnapshot(
        status: WhiteboardAiReadStatus.unavailable,
        request: scopedRequest,
        issues: const [
          WhiteboardAiReadIssue(
            code: 'board_absent_deleted_or_unavailable',
            entityType: 'board',
          ),
        ],
      );
    }
    final board = matchingBoards.first;

    final cardResults = <WhiteboardAiReadCard>[];
    final availableCardIds = <String>{};
    for (final cardId in scopedRequest.cardIds) {
      try {
        final record = await cards.getCard(cardId, loadDocument: false);
        if (record == null || record.card.deletedAt != null) {
          _addIssue(
            issues,
            WhiteboardAiReadIssue(
              code: 'card_absent_or_deleted',
              entityType: 'card',
              entityId: cardId,
            ),
            truncations,
          );
          continue;
        }
        final card = record.card;
        if (!_isSafeStableId(card.cardId) || card.cardId != cardId) {
          _addIssue(
            issues,
            const WhiteboardAiReadIssue(
              code: 'unsafe_persisted_identifier',
              entityType: 'card',
            ),
            truncations,
          );
          continue;
        }
        final body = _safeText(card.body, limits.maxBodyRunes);
        final bodyExcerpt = _safeText(card.body, limits.maxBodyExcerptRunes);
        if (bodyExcerpt.omittedCount > 0) {
          truncations.add(
            WhiteboardAiReadTruncation(
              field: 'cards.$cardId.body_excerpt',
              limit: limits.maxBodyExcerptRunes,
              omittedCount: bodyExcerpt.omittedCount,
            ),
          );
        }
        if (body.omittedCount > 0) {
          truncations.add(
            WhiteboardAiReadTruncation(
              field: 'cards.$cardId.body',
              limit: _nonNegative(limits.maxBodyRunes),
              omittedCount: body.omittedCount,
            ),
          );
        }
        final sourceId = _safeLinkedId(card.sourceId, issues, truncations);
        final sourceVersionId = _safeLinkedId(
          record.currentSourceVersion?.versionId,
          issues,
          truncations,
        );
        final tags = <String>[];
        final tagLimit = _nonNegative(limits.maxTagsPerCard);
        for (final tag in card.tags.take(tagLimit)) {
          tags.add(_safeText(tag, limits.maxLabelRunes).value);
        }
        if (card.tags.length > tagLimit) {
          truncations.add(
            WhiteboardAiReadTruncation(
              field: 'cards.$cardId.tags',
              limit: tagLimit,
              omittedCount: card.tags.length - tagLimit,
            ),
          );
        }
        cardResults.add(
          WhiteboardAiReadCard(
            cardId: cardId,
            cardKind: card.cardKind.name,
            title: _safeText(card.title, limits.maxTitleRunes).value,
            bodyExcerpt: bodyExcerpt.value,
            body: body.value,
            tags: tags,
            sourceId: sourceId,
            sourceVersionId: sourceVersionId,
            bodyTruncated: body.omittedCount > 0,
          ),
        );
        availableCardIds.add(cardId);
      } catch (_) {
        _addIssue(
          issues,
          WhiteboardAiReadIssue(
            code: 'card_unavailable',
            entityType: 'card',
            entityId: cardId,
          ),
          truncations,
        );
      }
    }

    final sourceResults = <WhiteboardAiReadSource>[];
    for (final sourceId in scopedRequest.sourceIds) {
      try {
        final source = await cards.getSource(sourceId);
        if (source == null || source.deletedAt != null) {
          _addIssue(
            issues,
            WhiteboardAiReadIssue(
              code: 'source_absent_or_deleted',
              entityType: 'source',
              entityId: sourceId,
            ),
            truncations,
          );
          continue;
        }
        if (!_isSafeStableId(source.sourceId) || source.sourceId != sourceId) {
          _addIssue(
            issues,
            const WhiteboardAiReadIssue(
              code: 'unsafe_persisted_identifier',
              entityType: 'source',
            ),
            truncations,
          );
          continue;
        }
        final rawVersions = await cards.listSourceVersions(sourceId);
        rawVersions.sort((a, b) {
          final byTime = b.createdAt.compareTo(a.createdAt);
          return byTime != 0 ? byTime : a.versionId.compareTo(b.versionId);
        });
        final validVersions = rawVersions
            .where(
              (version) =>
                  version.sourceId == sourceId &&
                  _isSafeStableId(version.versionId),
            )
            .toList();
        final versionLimit = _nonNegative(limits.maxVersionsPerSource);
        if (validVersions.length > versionLimit) {
          truncations.add(
            WhiteboardAiReadTruncation(
              field: 'sources.$sourceId.versions',
              limit: versionLimit,
              omittedCount: validVersions.length - versionLimit,
            ),
          );
        }
        final versions = [
          for (final version in validVersions.take(versionLimit))
            WhiteboardAiReadSourceVersion(
              versionId: version.versionId,
              sourceId: sourceId,
              contentHash: _safeText(
                version.contentHash,
                limits.maxLabelRunes,
              ).value,
              parserVersion: _safeOptionalText(
                version.parserVersion,
                limits.maxLabelRunes,
              ),
              createdAt: version.createdAt,
            ),
        ];
        sourceResults.add(
          WhiteboardAiReadSource(
            sourceId: sourceId,
            mediaType: source.mediaType.name,
            title: _safeText(source.title, limits.maxTitleRunes).value,
            origin: source.origin.name,
            provider: _safeOptionalText(source.provider, limits.maxLabelRunes),
            canonicalId: _safeOptionalText(
              source.canonicalId,
              limits.maxLabelRunes,
            ),
            mimeType: _safeOptionalText(source.mimeType, limits.maxLabelRunes),
            currentVersionId: _safeLinkedId(
              source.currentVersionId,
              issues,
              truncations,
            ),
            versions: versions,
            untrustedMetadataOmitted: source.metadata.isNotEmpty,
          ),
        );
      } catch (_) {
        _addIssue(
          issues,
          WhiteboardAiReadIssue(
            code: 'source_unavailable',
            entityType: 'source',
            entityId: sourceId,
          ),
          truncations,
        );
      }
    }

    final boardItems = snapshot.boardItems
        .where(
      (item) =>
          item.boardId == scopedRequest.boardId &&
          availableCardIds.contains(item.cardId),
    )
        .where((item) {
      final safe = _isSafeStableId(item.itemId) &&
          _isSafeStableId(item.boardId) &&
          _isSafeStableId(item.cardId);
      if (!safe) {
        _addIssue(
          issues,
          const WhiteboardAiReadIssue(
            code: 'unsafe_persisted_identifier',
            entityType: 'board_item',
          ),
          truncations,
        );
      }
      return safe;
    }).toList()
      ..sort((a, b) => a.itemId.compareTo(b.itemId));
    final boundedItems = _takeBounded(
      boardItems,
      limits.maxBoardItems,
      'board_items',
      truncations,
    );
    final itemResults = [
      for (final item in boundedItems)
        WhiteboardAiReadBoardItem(
          itemId: item.itemId,
          boardId: item.boardId,
          cardId: item.cardId,
          x: _finiteOrZero(item.x),
          y: _finiteOrZero(item.y),
          width: _finiteOrZero(item.width),
          height: _finiteOrZero(item.height),
          rotation: _finiteOrZero(item.rotation),
          zIndex: item.zIndex,
        ),
    ];
    final visibleItemIds = itemResults.map((item) => item.itemId).toSet();

    final candidateMembers = snapshot.groupMembers
        .where((member) => visibleItemIds.contains(member.itemId))
        .where((member) {
      final safe =
          _isSafeStableId(member.groupId) && _isSafeStableId(member.itemId);
      if (!safe) {
        _addIssue(
          issues,
          const WhiteboardAiReadIssue(
            code: 'unsafe_persisted_identifier',
            entityType: 'group_member',
          ),
          truncations,
        );
      }
      return safe;
    }).toList();
    final memberGroupIds =
        candidateMembers.map((member) => member.groupId).toSet();
    final candidateGroups = snapshot.groups
        .where(
      (group) =>
          group.boardId == scopedRequest.boardId &&
          memberGroupIds.contains(group.groupId),
    )
        .where((group) {
      final safe =
          _isSafeStableId(group.groupId) && _isSafeStableId(group.boardId);
      if (!safe) {
        _addIssue(
          issues,
          const WhiteboardAiReadIssue(
            code: 'unsafe_persisted_identifier',
            entityType: 'board_group',
          ),
          truncations,
        );
      }
      return safe;
    }).toList()
      ..sort((a, b) => a.groupId.compareTo(b.groupId));
    final boundedGroups = _takeBounded(
      candidateGroups,
      limits.maxGroups,
      'groups',
      truncations,
    );
    final groupResults = [
      for (final group in boundedGroups)
        WhiteboardAiReadGroup(
          groupId: group.groupId,
          boardId: group.boardId,
          name: _safeText(group.name, limits.maxLabelRunes).value,
          collapsed: group.collapsed,
        ),
    ];
    final visibleGroupIds = groupResults.map((group) => group.groupId).toSet();
    candidateMembers
      ..removeWhere((member) => !visibleGroupIds.contains(member.groupId))
      ..sort((a, b) {
        final byGroup = a.groupId.compareTo(b.groupId);
        if (byGroup != 0) return byGroup;
        final byOrder = a.order.compareTo(b.order);
        return byOrder != 0 ? byOrder : a.itemId.compareTo(b.itemId);
      });
    final boundedMembers = _takeBounded(
      candidateMembers,
      limits.maxGroupMembers,
      'group_members',
      truncations,
    );
    final memberResults = [
      for (final member in boundedMembers)
        WhiteboardAiReadGroupMember(
          groupId: member.groupId,
          itemId: member.itemId,
          order: member.order,
        ),
    ];

    final candidateEdges = snapshot.edges
        .where(
      (edge) =>
          edge.boardId == scopedRequest.boardId &&
          edge.deletedAt == null &&
          visibleItemIds.contains(edge.fromItemId) &&
          visibleItemIds.contains(edge.toItemId),
    )
        .where((edge) {
      final safe = _isSafeStableId(edge.edgeId) &&
          _isSafeStableId(edge.boardId) &&
          _isSafeStableId(edge.fromItemId) &&
          _isSafeStableId(edge.toItemId);
      if (!safe) {
        _addIssue(
          issues,
          const WhiteboardAiReadIssue(
            code: 'unsafe_persisted_identifier',
            entityType: 'board_edge',
          ),
          truncations,
        );
      }
      return safe;
    }).toList()
      ..sort((a, b) => a.edgeId.compareTo(b.edgeId));
    final boundedEdges = _takeBounded(
      candidateEdges,
      limits.maxEdges,
      'edges',
      truncations,
    );
    final edgeResults = [
      for (final edge in boundedEdges)
        WhiteboardAiReadEdge(
          edgeId: edge.edgeId,
          boardId: edge.boardId,
          fromItemId: edge.fromItemId,
          toItemId: edge.toItemId,
          direction: edge.direction.name,
          semanticType: _safeOptionalText(
            edge.semanticType,
            limits.maxLabelRunes,
          ),
          label: _safeOptionalText(edge.label, limits.maxLabelRunes),
        ),
    ];

    final result = WhiteboardAiReadSnapshot(
      status: issues.isEmpty && truncations.isEmpty
          ? WhiteboardAiReadStatus.ok
          : WhiteboardAiReadStatus.partial,
      request: scopedRequest,
      board: WhiteboardAiReadBoard(
        boardId: scopedRequest.boardId,
        name: _safeText(board.name, limits.maxTitleRunes).value,
      ),
      cards: cardResults,
      sources: sourceResults,
      boardItems: itemResults,
      groups: groupResults,
      groupMembers: memberResults,
      edges: edgeResults,
      issues: issues,
      truncations: truncations,
    );
    return _enforceSerializedBudget(result);
  }

  List<WhiteboardAiReadIssue> _validateRequest(
    WhiteboardAiReadRequest request,
  ) {
    final issues = <WhiteboardAiReadIssue>[];
    if (!_isSafeStableId(request.boardId)) {
      issues.add(
        const WhiteboardAiReadIssue(
          code: 'invalid_board_id',
          entityType: 'board',
        ),
      );
    }
    if (request.cardIds.length > _nonNegative(limits.maxCardIds)) {
      issues.add(
        const WhiteboardAiReadIssue(
          code: 'card_id_limit_exceeded',
          entityType: 'card',
        ),
      );
    }
    if (request.sourceIds.length > _nonNegative(limits.maxSourceIds)) {
      issues.add(
        const WhiteboardAiReadIssue(
          code: 'source_id_limit_exceeded',
          entityType: 'source',
        ),
      );
    }
    if (request.cardIds.any((id) => !_isSafeStableId(id))) {
      issues.add(
        const WhiteboardAiReadIssue(
          code: 'invalid_card_id',
          entityType: 'card',
        ),
      );
    }
    if (request.sourceIds.any((id) => !_isSafeStableId(id))) {
      issues.add(
        const WhiteboardAiReadIssue(
          code: 'invalid_source_id',
          entityType: 'source',
        ),
      );
    }
    return issues;
  }

  WhiteboardAiReadRequest _boundedRequestScope(
    WhiteboardAiReadRequest request,
  ) {
    final cardLimit = _nonNegative(limits.maxCardIds);
    final sourceLimit = _nonNegative(limits.maxSourceIds);
    return WhiteboardAiReadRequest(
      boardId: _isSafeStableId(request.boardId)
          ? request.boardId
          : 'invalid_board_id',
      cardIds: request.cardIds.where(_isSafeStableId).take(cardLimit).toList(),
      sourceIds:
          request.sourceIds.where(_isSafeStableId).take(sourceLimit).toList(),
    );
  }

  String? _safeLinkedId(
    String? value,
    List<WhiteboardAiReadIssue> issues,
    List<WhiteboardAiReadTruncation> truncations,
  ) {
    if (value == null) return null;
    if (_isSafeStableId(value)) return value;
    _addIssue(
      issues,
      const WhiteboardAiReadIssue(code: 'unsafe_linked_identifier_omitted'),
      truncations,
    );
    return null;
  }

  void _addIssue(
    List<WhiteboardAiReadIssue> issues,
    WhiteboardAiReadIssue issue,
    List<WhiteboardAiReadTruncation> truncations,
  ) {
    final issueLimit = _nonNegative(limits.maxIssues);
    if (issues.length < issueLimit) {
      issues.add(issue);
      return;
    }
    if (!truncations.any((item) => item.field == 'issues')) {
      truncations.add(
        WhiteboardAiReadTruncation(
          field: 'issues',
          limit: issueLimit,
          omittedCount: 1,
        ),
      );
    }
  }

  static List<String> _deduplicate(List<String> values) =>
      values.toSet().toList(growable: false);

  static bool _isSafeStableId(String value) {
    if (value.length > 256) return false;
    return RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$').hasMatch(value);
  }

  static double _finiteOrZero(double value) => value.isFinite ? value : 0;

  static int _nonNegative(int value) => math.max(0, value);

  static String? _safeOptionalText(String? value, int limit) {
    if (value == null) return null;
    return _safeText(value, limit).value;
  }

  static _BoundedText _safeText(String value, int limit) {
    final withoutControls = String.fromCharCodes(
      value.runes.where(
        (rune) => rune == 0x09 || rune == 0x0A || rune >= 0x20 && rune != 0x7F,
      ),
    );
    final withoutFileUris = withoutControls.replaceAll(
      RegExp(r'''file://[^\r\n"'<>]*''', caseSensitive: false),
      '[local_path_redacted]',
    );
    final withoutWindowsPaths = withoutFileUris.replaceAll(
      RegExp(r'''(?:[A-Za-z]:[\\/]|\\\\)[^\r\n"'<>]*'''),
      '[local_path_redacted]',
    );
    final withoutLocalPaths = withoutWindowsPaths.replaceAll(
      RegExp(
        r'''/(?:Users|home|var|tmp|private|opt|etc|root|mnt|Volumes)(?:/[^\r\n"'<>]*)?''',
        caseSensitive: false,
      ),
      '[local_path_redacted]',
    );
    final runes = withoutLocalPaths.runes.toList(growable: false);
    final safeLimit = _nonNegative(limit);
    if (runes.length <= safeLimit) {
      return _BoundedText(withoutLocalPaths, 0);
    }
    return _BoundedText(
      String.fromCharCodes(runes.take(safeLimit)),
      runes.length - safeLimit,
    );
  }

  static List<T> _takeBounded<T>(
    List<T> values,
    int limit,
    String field,
    List<WhiteboardAiReadTruncation> truncations,
  ) {
    final safeLimit = _nonNegative(limit);
    if (values.length > safeLimit) {
      truncations.add(
        WhiteboardAiReadTruncation(
          field: field,
          limit: safeLimit,
          omittedCount: values.length - safeLimit,
        ),
      );
    }
    return values.take(safeLimit).toList(growable: false);
  }

  WhiteboardAiReadSnapshot _enforceSerializedBudget(
    WhiteboardAiReadSnapshot input,
  ) {
    final byteLimit = limits.maxSerializedUtf8Bytes;
    final initialSize = _serializedSize(input);
    if (initialSize <= byteLimit) return input;

    var board = input.board;
    final cards = input.cards.toList();
    final sources = input.sources.toList();
    final boardItems = input.boardItems.toList();
    final groups = input.groups.toList();
    final groupMembers = input.groupMembers.toList();
    final edges = input.edges.toList();
    final issues = input.issues.toList();
    var truncations = input.truncations
        .where((item) => item.field != 'serialized_output_utf8_bytes')
        .toList();
    truncations.add(
      WhiteboardAiReadTruncation(
        field: 'serialized_output_utf8_bytes',
        limit: byteLimit,
        omittedCount: initialSize - byteLimit,
      ),
    );

    WhiteboardAiReadSnapshot build() => WhiteboardAiReadSnapshot(
          status: WhiteboardAiReadStatus.partial,
          request: input.request,
          board: board,
          cards: cards,
          sources: sources,
          boardItems: boardItems,
          groups: groups,
          groupMembers: groupMembers,
          edges: edges,
          issues: issues,
          truncations: truncations,
        );

    var candidate = build();
    var size = _serializedSize(candidate);

    // Preserve stable objects and relationships first. Reclaim payload bytes
    // from Card body/excerpt/tag text before dropping any entity projection.
    for (var index = cards.length - 1;
        index >= 0 && size > byteLimit;
        index--) {
      final card = cards[index];
      final over = size - byteLimit;
      final bodyBytes = utf8.encode(card.body).length;
      final shortenedBody = _truncateUtf8(
        card.body,
        math.max(0, bodyBytes - over - 64),
      );
      if (shortenedBody != card.body) {
        cards[index] = _copyCard(
          card,
          body: shortenedBody,
          bodyTruncated: true,
        );
        candidate = build();
        size = _serializedSize(candidate);
      }
      if (size > byteLimit) {
        final current = cards[index];
        final excerptBytes = utf8.encode(current.bodyExcerpt).length;
        final shortenedExcerpt = _truncateUtf8(
          current.bodyExcerpt,
          math.max(0, excerptBytes - (size - byteLimit) - 64),
        );
        if (shortenedExcerpt != current.bodyExcerpt) {
          cards[index] = _copyCard(
            current,
            bodyExcerpt: shortenedExcerpt,
          );
          candidate = build();
          size = _serializedSize(candidate);
        }
      }
      while (size > byteLimit && cards[index].tags.isNotEmpty) {
        final current = cards[index];
        cards[index] = _copyCard(
          current,
          tags: current.tags.sublist(0, current.tags.length - 1),
        );
        candidate = build();
        size = _serializedSize(candidate);
      }
    }

    // If text reclamation is insufficient, remove bounded relation/detail
    // records from the end of their stable sort order. The global truncation
    // receipt remains in the response, so this can never be a silent drop.
    void trimLast<T>(List<T> values) {
      while (size > byteLimit && values.isNotEmpty) {
        values.removeLast();
        candidate = build();
        size = _serializedSize(candidate);
      }
    }

    trimLast(edges);
    trimLast(groupMembers);
    trimLast(groups);
    trimLast(boardItems);

    for (var sourceIndex = sources.length - 1;
        sourceIndex >= 0 && size > byteLimit;
        sourceIndex--) {
      while (size > byteLimit && sources[sourceIndex].versions.isNotEmpty) {
        final source = sources[sourceIndex];
        sources[sourceIndex] = _copySource(
          source,
          versions: source.versions.sublist(0, source.versions.length - 1),
        );
        candidate = build();
        size = _serializedSize(candidate);
      }
    }
    trimLast(sources);
    trimLast(cards);

    // Issue ids are useful but not authoritative content. Strip them before
    // sacrificing issue codes, then collapse secondary receipts if required.
    for (var index = issues.length - 1;
        index >= 0 && size > byteLimit;
        index--) {
      final issue = issues[index];
      if (issue.entityId != null) {
        issues[index] = WhiteboardAiReadIssue(
          code: issue.code,
          entityType: issue.entityType,
        );
        candidate = build();
        size = _serializedSize(candidate);
      }
    }
    trimLast(issues);
    if (size > byteLimit && truncations.length > 1) {
      truncations = [truncations.last];
      candidate = build();
      size = _serializedSize(candidate);
    }
    if (size > byteLimit && board != null && board.name.isNotEmpty) {
      board = WhiteboardAiReadBoard(boardId: board.boardId, name: '');
      candidate = build();
      size = _serializedSize(candidate);
    }

    // The minimum configurable budget is sized to contain the largest valid
    // request scope plus this minimal receipt. Reaching this guard therefore
    // indicates a contract bug, not model-controlled input.
    if (size > byteLimit) {
      throw StateError('read snapshot could not satisfy UTF-8 hard budget');
    }
    return candidate;
  }

  static int _serializedSize(WhiteboardAiReadSnapshot value) =>
      utf8.encode(jsonEncode(value.toJson())).length;

  static String _truncateUtf8(String value, int maxBytes) {
    if (maxBytes <= 0 || value.isEmpty) return '';
    final buffer = StringBuffer();
    var used = 0;
    for (final rune in value.runes) {
      final encoded = utf8.encode(String.fromCharCode(rune));
      if (used + encoded.length > maxBytes) break;
      buffer.writeCharCode(rune);
      used += encoded.length;
    }
    return buffer.toString();
  }

  static WhiteboardAiReadCard _copyCard(
    WhiteboardAiReadCard card, {
    String? body,
    String? bodyExcerpt,
    List<String>? tags,
    bool? bodyTruncated,
  }) =>
      WhiteboardAiReadCard(
        cardId: card.cardId,
        cardKind: card.cardKind,
        title: card.title,
        bodyExcerpt: bodyExcerpt ?? card.bodyExcerpt,
        body: body ?? card.body,
        tags: tags ?? card.tags,
        sourceId: card.sourceId,
        sourceVersionId: card.sourceVersionId,
        bodyTruncated: bodyTruncated ?? card.bodyTruncated,
      );

  static WhiteboardAiReadSource _copySource(
    WhiteboardAiReadSource source, {
    required List<WhiteboardAiReadSourceVersion> versions,
  }) =>
      WhiteboardAiReadSource(
        sourceId: source.sourceId,
        mediaType: source.mediaType,
        title: source.title,
        origin: source.origin,
        provider: source.provider,
        canonicalId: source.canonicalId,
        mimeType: source.mimeType,
        currentVersionId: source.currentVersionId,
        versions: versions,
        untrustedMetadataOmitted: source.untrustedMetadataOmitted,
      );
}

class _BoundedText {
  const _BoundedText(this.value, this.omittedCount);

  final String value;
  final int omittedCount;
}
