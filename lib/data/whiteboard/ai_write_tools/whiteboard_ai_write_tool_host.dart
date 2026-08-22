library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:memex/data/whiteboard/ai_write_tools/whiteboard_ai_write_models.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/snapshot_integrity.dart';
import 'package:memex/domain/whiteboard/whiteboard_ids.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/domain/workbench_ai/permissions/whiteboard_permission_broker.dart';

typedef WhiteboardWriteClock = DateTime Function();
typedef WhiteboardWriteIdFactory = String Function(String prefix);
typedef WhiteboardSnapshotLoader = Future<WhiteboardSnapshot> Function(
  String boardId,
);
typedef WhiteboardSnapshotSaver = Future<bool> Function(
  String boardId,
  WhiteboardSnapshot snapshot,
);

/// Narrow, product-owned write host for the first reversible AI whiteboard
/// vertical. It accepts only stable board-item ids and never exposes Drift,
/// raw SQL, files, Card deletion, or arbitrary snapshot replacement to a
/// runtime provider.
class WhiteboardAiWriteToolHost {
  WhiteboardAiWriteToolHost({
    required this.permissionBroker,
    required WhiteboardSnapshotLoader loadSnapshot,
    required WhiteboardSnapshotSaver saveSnapshot,
    WhiteboardWriteClock? clock,
    WhiteboardWriteIdFactory? idFactory,
  })  : _loadSnapshot = loadSnapshot,
        _saveSnapshot = saveSnapshot,
        _clock = clock ?? (() => DateTime.now().toUtc()),
        _idFactory = idFactory ?? _defaultIdFactory;

  factory WhiteboardAiWriteToolHost.forDriftStore({
    required WhiteboardPermissionBroker permissionBroker,
    required WhiteboardDriftStore store,
    WhiteboardWriteClock? clock,
    WhiteboardWriteIdFactory? idFactory,
  }) {
    return WhiteboardAiWriteToolHost(
      permissionBroker: permissionBroker,
      loadSnapshot: (boardId) async {
        final result = await store.load(boardId);
        if (!result.isSuccess || result.snapshot == null) {
          throw StateError('whiteboard snapshot unavailable');
        }
        return result.snapshot!;
      },
      saveSnapshot: store.save,
      clock: clock,
      idFactory: idFactory,
    );
  }

  static const hardMaxGroups = 16;
  static const hardMaxEdges = 32;
  static const hardMaxGroupNameRunes = 120;
  static const hardMaxEdgeLabelRunes = 200;
  static const hardMaxSemanticTypeRunes = 64;

  final WhiteboardPermissionBroker permissionBroker;
  final WhiteboardSnapshotLoader _loadSnapshot;
  final WhiteboardSnapshotSaver _saveSnapshot;
  final WhiteboardWriteClock _clock;
  final WhiteboardWriteIdFactory _idFactory;

  final Map<String, _AppliedBatch> _appliedBatches = {};
  final Map<String, _UndoRecord> _undoRecords = {};
  final Map<String, WhiteboardAiWriteReceipt> _completedUndos = {};

  Future<WhiteboardAiWriteReceipt> groupAndConnect(
    WhiteboardAiGroupAndConnectRequest request,
  ) async {
    final now = _millisecondUtc(_clock());
    final requestIssue = _validateRequest(request);
    if (requestIssue != null) {
      return _failure(
        request: request,
        status: WhiteboardAiWriteStatus.invalidRequest,
        issue: requestIssue,
        now: now,
      );
    }

    final requestHash = _hashJson(request.toJson());
    final applied = _appliedBatches[request.operationBatchId];
    if (applied != null) {
      if (applied.requestHash == requestHash) return applied.receipt;
      return _failure(
        request: request,
        status: WhiteboardAiWriteStatus.conflict,
        issue: const WhiteboardAiWriteIssue('batch_id_reused'),
        now: now,
      );
    }

    final groupItemIds = <String>{};
    final targetItemIds = <String>{};
    for (final group in request.groups) {
      groupItemIds.addAll(group.itemIds);
      targetItemIds.addAll(group.itemIds);
    }
    for (final edge in request.edges) {
      targetItemIds
        ..add(edge.fromItemId)
        ..add(edge.toItemId);
    }
    final capabilities = <WhiteboardWriteCapability>{
      if (request.groups.isNotEmpty) WhiteboardWriteCapability.groupSelection,
      if (request.edges.isNotEmpty) WhiteboardWriteCapability.connectSelection,
    };
    final operationCount =
        request.groups.length + groupItemIds.length + request.edges.length;
    final decision = permissionBroker.reserve(
      authorizationId: request.authorizationId,
      operationBatchId: request.operationBatchId,
      runtimeTurnId: request.runtimeTurnId,
      boardId: request.boardId,
      targetItemIds: targetItemIds,
      requiredCapabilities: capabilities,
      operationCount: operationCount,
    );
    if (!decision.allowed) {
      return _failure(
        request: request,
        status: WhiteboardAiWriteStatus.denied,
        issue: WhiteboardAiWriteIssue(
          'permission_${decision.code.name}',
        ),
        now: now,
      );
    }
    final grant = decision.grant!;

    WhiteboardSnapshot before;
    try {
      before = await _loadSnapshot(request.boardId);
    } catch (_) {
      permissionBroker.release(
        authorizationId: request.authorizationId,
        operationBatchId: request.operationBatchId,
      );
      return _failure(
        request: request,
        status: WhiteboardAiWriteStatus.unavailable,
        issue: const WhiteboardAiWriteIssue('snapshot_unavailable'),
        now: now,
      );
    }

    final snapshotIssue = _validateSnapshotAndPlan(
      request: request,
      before: before,
      grant: grant,
      groupItemIds: groupItemIds,
    );
    if (snapshotIssue != null) {
      permissionBroker.release(
        authorizationId: request.authorizationId,
        operationBatchId: request.operationBatchId,
      );
      return _failure(
        request: request,
        status: WhiteboardAiWriteStatus.conflict,
        issue: snapshotIssue,
        now: now,
      );
    }

    final existingIds = <String>{
      request.operationBatchId,
      request.authorizationId,
      request.runtimeTurnId,
      ...before.sources.map((value) => value.sourceId),
      ...before.sourceVersions.map((value) => value.versionId),
      ...before.cards.map((value) => value.cardId),
      ...before.boards.map((value) => value.boardId),
      ...before.boardItems.map((value) => value.itemId),
      ...before.groups.map((value) => value.groupId),
      ...before.edges.map((value) => value.edgeId),
    };
    final groups = <BoardGroup>[];
    final members = <GroupMember>[];
    final edges = <BoardEdge>[];
    final operations = <WhiteboardOperation>[];

    for (final plan in request.groups) {
      final groupId = _nextUniqueId('group', existingIds);
      final group = BoardGroup(
        groupId: groupId,
        boardId: request.boardId,
        name: plan.name.trim(),
      );
      groups.add(group);
      final groupMembers = <GroupMember>[
        for (var index = 0; index < plan.itemIds.length; index++)
          GroupMember(
            groupId: groupId,
            itemId: plan.itemIds[index],
            order: index,
          ),
      ];
      members.addAll(groupMembers);
      operations.add(
        WhiteboardOperation(
          operationId: _nextUniqueId('op', existingIds),
          boardId: request.boardId,
          actor: OperationActor.i,
          operationKind: OperationKind.group,
          targetIds: plan.itemIds,
          payload: {
            'group': group.toJson(),
            'members': groupMembers.map((value) => value.toJson()).toList(),
          },
          inverse: {
            'operation_kind': OperationKind.ungroup.name,
            'group_id': groupId,
          },
          authorizationId: request.authorizationId,
          createdAt: now,
        ),
      );
    }

    for (final plan in request.edges) {
      final edgeId = _nextUniqueId('edge', existingIds);
      final edge = BoardEdge(
        edgeId: edgeId,
        boardId: request.boardId,
        fromItemId: plan.fromItemId,
        toItemId: plan.toItemId,
        direction: plan.direction,
        semanticType: plan.semanticType?.trim(),
        label: plan.label?.trim(),
        createdBy: CardCreatedBy.i,
        createdAt: now,
      );
      edges.add(edge);
      operations.add(
        WhiteboardOperation(
          operationId: _nextUniqueId('op', existingIds),
          boardId: request.boardId,
          actor: OperationActor.i,
          operationKind: OperationKind.edge,
          targetIds: [plan.fromItemId, plan.toItemId],
          payload: {'edge': edge.toJson()},
          inverse: {
            'operation_kind': OperationKind.removeEdge.name,
            'edge_id': edgeId,
          },
          authorizationId: request.authorizationId,
          createdAt: now,
        ),
      );
    }

    final after = _copySnapshot(
      before,
      boardId: request.boardId,
      groups: [...before.groups, ...groups],
      groupMembers: [...before.groupMembers, ...members],
      edges: [...before.edges, ...edges],
      updatedAt: now,
    );
    final integrity = validateSnapshotIntegrity(after);
    if (!integrity.isValid) {
      permissionBroker.release(
        authorizationId: request.authorizationId,
        operationBatchId: request.operationBatchId,
      );
      return _failure(
        request: request,
        status: WhiteboardAiWriteStatus.conflict,
        issue: const WhiteboardAiWriteIssue('result_integrity_failed'),
        now: now,
      );
    }

    final beforeHash = _snapshotHash(before);
    final afterHash = _snapshotHash(after);
    final undoToken = _nextUniqueId('undo', existingIds);
    final receipt = WhiteboardAiWriteReceipt(
      status: WhiteboardAiWriteStatus.applied,
      operationBatchId: request.operationBatchId,
      runtimeTurnId: request.runtimeTurnId,
      boardId: request.boardId,
      summary:
          'Created ${groups.length} groups and ${edges.length} connections.',
      authorizationId: request.authorizationId,
      userAuthorizationMessageId: grant.userAuthorizationMessageId,
      beforeSnapshotHash: beforeHash,
      afterSnapshotHash: afterHash,
      undoToken: undoToken,
      operations: List.unmodifiable(operations),
      occurredAt: now,
    );

    var saved = false;
    try {
      saved = await _saveSnapshot(request.boardId, after);
    } catch (_) {
      saved = false;
    }
    if (!saved) {
      permissionBroker.release(
        authorizationId: request.authorizationId,
        operationBatchId: request.operationBatchId,
      );
      return _failure(
        request: request,
        status: WhiteboardAiWriteStatus.unavailable,
        issue: const WhiteboardAiWriteIssue('save_failed'),
        now: now,
      );
    }
    if (!permissionBroker.commit(
      authorizationId: request.authorizationId,
      operationBatchId: request.operationBatchId,
    )) {
      try {
        await _saveSnapshot(request.boardId, before);
      } catch (_) {
        // The broker is synchronous and this path is defensive. Never report
        // success when authorization cannot be committed.
      }
      return _failure(
        request: request,
        status: WhiteboardAiWriteStatus.unavailable,
        issue: const WhiteboardAiWriteIssue('authorization_commit_failed'),
        now: now,
      );
    }

    _appliedBatches[request.operationBatchId] = _AppliedBatch(
      requestHash: requestHash,
      receipt: receipt,
    );
    _undoRecords[undoToken] = _UndoRecord(
      receipt: receipt,
      beforeSnapshot: before,
      afterSnapshotHash: afterHash,
    );
    return receipt;
  }

  Future<WhiteboardAiWriteReceipt> undo(
    WhiteboardAiUndoRequest request,
  ) async {
    final completed = _completedUndos[request.undoToken];
    if (completed != null) return completed;
    final record = _undoRecords[request.undoToken];
    final now = _millisecondUtc(_clock());
    if (record == null) {
      return WhiteboardAiWriteReceipt(
        status: WhiteboardAiWriteStatus.denied,
        operationBatchId: 'unknown_batch',
        runtimeTurnId: request.runtimeTurnId,
        boardId: 'unknown_board',
        summary: 'Undo was not applied.',
        issues: const [WhiteboardAiWriteIssue('undo_token_not_found')],
        occurredAt: now,
      );
    }
    if (record.receipt.runtimeTurnId != request.runtimeTurnId) {
      return WhiteboardAiWriteReceipt(
        status: WhiteboardAiWriteStatus.denied,
        operationBatchId: record.receipt.operationBatchId,
        runtimeTurnId: request.runtimeTurnId,
        boardId: record.receipt.boardId,
        summary: 'Undo was not applied.',
        issues: const [WhiteboardAiWriteIssue('undo_turn_mismatch')],
        occurredAt: now,
      );
    }

    WhiteboardSnapshot current;
    try {
      current = await _loadSnapshot(record.receipt.boardId);
    } catch (_) {
      return _undoFailure(
        record,
        request.runtimeTurnId,
        WhiteboardAiWriteStatus.unavailable,
        'snapshot_unavailable',
        now,
      );
    }
    if (_snapshotHash(current) != record.afterSnapshotHash) {
      return _undoFailure(
        record,
        request.runtimeTurnId,
        WhiteboardAiWriteStatus.conflict,
        'snapshot_changed_after_batch',
        now,
      );
    }

    var saved = false;
    try {
      saved = await _saveSnapshot(
        record.receipt.boardId,
        record.beforeSnapshot,
      );
    } catch (_) {
      saved = false;
    }
    if (!saved) {
      return _undoFailure(
        record,
        request.runtimeTurnId,
        WhiteboardAiWriteStatus.unavailable,
        'undo_save_failed',
        now,
      );
    }

    final targetIds = record.receipt.operations
        .expand((operation) => operation.targetIds)
        .toSet()
        .toList()
      ..sort();
    final auditIds = <String>{
      request.undoToken,
      record.receipt.operationBatchId,
      if (record.receipt.authorizationId != null)
        record.receipt.authorizationId!,
      ...record.receipt.operations.map((operation) => operation.operationId),
    };
    final undoOperation = WhiteboardOperation(
      operationId: _nextUniqueId('op', auditIds),
      boardId: record.receipt.boardId,
      actor: OperationActor.user,
      operationKind: OperationKind.undo,
      targetIds: targetIds,
      payload: {
        'operation_batch_id': record.receipt.operationBatchId,
        'restored_snapshot_hash': record.receipt.beforeSnapshotHash,
      },
      authorizationId: record.receipt.authorizationId,
      undoOf: record.receipt.operationBatchId,
      createdAt: now,
    );
    final receipt = WhiteboardAiWriteReceipt(
      status: WhiteboardAiWriteStatus.undone,
      operationBatchId: record.receipt.operationBatchId,
      runtimeTurnId: request.runtimeTurnId,
      boardId: record.receipt.boardId,
      summary: 'The operation batch was undone.',
      authorizationId: record.receipt.authorizationId,
      userAuthorizationMessageId: record.receipt.userAuthorizationMessageId,
      beforeSnapshotHash: record.receipt.afterSnapshotHash,
      afterSnapshotHash: record.receipt.beforeSnapshotHash,
      undoToken: request.undoToken,
      operations: [undoOperation],
      occurredAt: now,
    );
    _undoRecords.remove(request.undoToken);
    _completedUndos[request.undoToken] = receipt;
    return receipt;
  }

  WhiteboardAiWriteIssue? _validateRequest(
    WhiteboardAiGroupAndConnectRequest request,
  ) {
    if (!_isId(request.operationBatchId) ||
        !_isId(request.authorizationId) ||
        !_isId(request.runtimeTurnId) ||
        !_isId(request.boardId)) {
      return const WhiteboardAiWriteIssue('invalid_stable_id');
    }
    if (request.groups.isEmpty && request.edges.isEmpty) {
      return const WhiteboardAiWriteIssue('empty_operation_batch');
    }
    if (request.groups.length > hardMaxGroups ||
        request.edges.length > hardMaxEdges) {
      return const WhiteboardAiWriteIssue('plan_limit_exceeded');
    }
    final groupItems = <String>{};
    for (final group in request.groups) {
      if (!_isSafeText(group.name, hardMaxGroupNameRunes) ||
          group.itemIds.isEmpty) {
        return const WhiteboardAiWriteIssue('invalid_group');
      }
      for (final itemId in group.itemIds) {
        if (!_isId(itemId) || !groupItems.add(itemId)) {
          return const WhiteboardAiWriteIssue('invalid_group_membership');
        }
      }
    }
    final edgePairs = <String>{};
    for (final edge in request.edges) {
      if (!_isId(edge.fromItemId) ||
          !_isId(edge.toItemId) ||
          edge.fromItemId == edge.toItemId ||
          !_isSafeOptionalText(edge.label, hardMaxEdgeLabelRunes) ||
          !_isSafeOptionalText(
            edge.semanticType,
            hardMaxSemanticTypeRunes,
          )) {
        return const WhiteboardAiWriteIssue('invalid_edge');
      }
      if (!edgePairs.add(_edgePair(edge.fromItemId, edge.toItemId))) {
        return const WhiteboardAiWriteIssue('duplicate_edge');
      }
    }
    return null;
  }

  WhiteboardAiWriteIssue? _validateSnapshotAndPlan({
    required WhiteboardAiGroupAndConnectRequest request,
    required WhiteboardSnapshot before,
    required WhiteboardAuthorizationGrant grant,
    required Set<String> groupItemIds,
  }) {
    final integrity = validateSnapshotIntegrity(before);
    if (!integrity.isValid) {
      return const WhiteboardAiWriteIssue('source_integrity_failed');
    }
    final boardExists = before.boards.any(
      (board) => board.boardId == request.boardId && board.deletedAt == null,
    );
    if (!boardExists) {
      return const WhiteboardAiWriteIssue('board_not_found');
    }
    final boardItemIds = before.boardItems
        .where((item) => item.boardId == request.boardId)
        .map((item) => item.itemId)
        .toSet();
    final targets = <String>{
      ...groupItemIds,
      for (final edge in request.edges) edge.fromItemId,
      for (final edge in request.edges) edge.toItemId,
    };
    if (!boardItemIds.containsAll(targets)) {
      return const WhiteboardAiWriteIssue('target_not_on_board');
    }
    if (request.groups.isNotEmpty &&
        !_sameSet(groupItemIds, grant.selectedItemIds)) {
      return const WhiteboardAiWriteIssue('groups_must_partition_selection');
    }
    final alreadyGrouped = before.groupMembers
        .where((member) => groupItemIds.contains(member.itemId))
        .isNotEmpty;
    if (alreadyGrouped) {
      return const WhiteboardAiWriteIssue('target_already_grouped');
    }
    final existingPairs = {
      for (final edge in before.edges.where((edge) => edge.deletedAt == null))
        _edgePair(edge.fromItemId, edge.toItemId),
    };
    if (request.edges.any(
      (edge) => existingPairs.contains(
        _edgePair(edge.fromItemId, edge.toItemId),
      ),
    )) {
      return const WhiteboardAiWriteIssue('edge_already_exists');
    }
    return null;
  }

  WhiteboardAiWriteReceipt _failure({
    required WhiteboardAiGroupAndConnectRequest request,
    required WhiteboardAiWriteStatus status,
    required WhiteboardAiWriteIssue issue,
    required DateTime now,
  }) {
    return WhiteboardAiWriteReceipt(
      status: status,
      operationBatchId: request.operationBatchId,
      runtimeTurnId: request.runtimeTurnId,
      boardId: request.boardId,
      summary: 'The whiteboard operation batch was not applied.',
      authorizationId: request.authorizationId,
      issues: [issue],
      occurredAt: now,
    );
  }

  WhiteboardAiWriteReceipt _undoFailure(
    _UndoRecord record,
    String runtimeTurnId,
    WhiteboardAiWriteStatus status,
    String issue,
    DateTime now,
  ) {
    return WhiteboardAiWriteReceipt(
      status: status,
      operationBatchId: record.receipt.operationBatchId,
      runtimeTurnId: runtimeTurnId,
      boardId: record.receipt.boardId,
      summary: 'Undo was not applied.',
      authorizationId: record.receipt.authorizationId,
      issues: [WhiteboardAiWriteIssue(issue)],
      occurredAt: now,
    );
  }

  String _nextUniqueId(String prefix, Set<String> existingIds) {
    for (var attempt = 0; attempt < 8; attempt++) {
      final value = _idFactory(prefix);
      if (_isId(value) && existingIds.add(value)) return value;
    }
    throw StateError('idFactory could not produce a unique stable id');
  }

  static String _defaultIdFactory(String prefix) =>
      StableId.generate(prefix).value;

  static String _snapshotHash(WhiteboardSnapshot snapshot) =>
      _hashJson(_snapshotConflictJson(snapshot));

  /// Persistence may refresh revision timestamps while reopening an otherwise
  /// unchanged board. Those fields are not user edits and must not make a
  /// reversible batch look unsafe. All semantic board content remains in the
  /// conflict hash, including viewport, item geometry, groups, membership,
  /// edges, and card/source state.
  static Map<String, dynamic> _snapshotConflictJson(
    WhiteboardSnapshot snapshot,
  ) {
    final value = Map<String, dynamic>.from(snapshot.toJson())
      ..remove('updated_at');
    final boards = value['boards'];
    if (boards is List) {
      value['boards'] = [
        for (final raw in boards)
          if (raw is Map)
            (Map<String, dynamic>.from(raw)..remove('updated_at'))
          else
            raw,
      ];
    }
    const sortFields = <String, List<String>>{
      'sources': ['source_id'],
      'source_versions': ['version_id'],
      'cards': ['card_id'],
      'boards': ['board_id'],
      'board_items': ['item_id'],
      'groups': ['group_id'],
      'group_members': ['group_id', 'order', 'item_id'],
      'edges': ['edge_id'],
    };
    for (final entry in sortFields.entries) {
      final raw = value[entry.key];
      if (raw is! List) continue;
      raw.sort((a, b) => _entitySortKey(a, entry.value)
          .compareTo(_entitySortKey(b, entry.value)));
    }
    return value;
  }

  static String _entitySortKey(Object? raw, List<String> fields) {
    if (raw is! Map) return jsonEncode(raw);
    return fields.map((field) => '${raw[field] ?? ''}').join('\u0000');
  }

  static DateTime _millisecondUtc(DateTime value) =>
      DateTime.fromMillisecondsSinceEpoch(
        value.toUtc().millisecondsSinceEpoch,
        isUtc: true,
      );

  static String _hashJson(Map<String, dynamic> value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();

  static String _edgePair(String a, String b) =>
      a.compareTo(b) <= 0 ? '$a::$b' : '$b::$a';

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  static bool _isId(String value) =>
      value.isNotEmpty &&
      value.length <= 256 &&
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$').hasMatch(value);

  static bool _isSafeOptionalText(String? value, int maxRunes) =>
      value == null || _isSafeText(value, maxRunes);

  static bool _isSafeText(String value, int maxRunes) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.runes.length > maxRunes) return false;
    return !trimmed.runes.any(
      (rune) => rune < 0x20 && rune != 0x09,
    );
  }

  static WhiteboardSnapshot _copySnapshot(
    WhiteboardSnapshot source, {
    required String boardId,
    required List<BoardGroup> groups,
    required List<GroupMember> groupMembers,
    required List<BoardEdge> edges,
    required DateTime updatedAt,
  }) {
    return WhiteboardSnapshot(
      schemaVersion: source.schemaVersion,
      sources: source.sources,
      sourceVersions: source.sourceVersions,
      cards: source.cards,
      boards: [
        for (final board in source.boards)
          if (board.boardId == boardId)
            Board(
              boardId: board.boardId,
              name: board.name,
              ownerSpace: board.ownerSpace,
              createdBy: board.createdBy,
              createdAt: board.createdAt,
              updatedAt: updatedAt,
              deletedAt: board.deletedAt,
            )
          else
            board,
      ],
      boardItems: source.boardItems,
      groups: groups,
      groupMembers: groupMembers,
      edges: edges,
      viewport: source.viewport,
      updatedAt: updatedAt,
    );
  }
}

class _AppliedBatch {
  const _AppliedBatch({required this.requestHash, required this.receipt});

  final String requestHash;
  final WhiteboardAiWriteReceipt receipt;
}

class _UndoRecord {
  const _UndoRecord({
    required this.receipt,
    required this.beforeSnapshot,
    required this.afterSnapshotHash,
  });

  final WhiteboardAiWriteReceipt receipt;
  final WhiteboardSnapshot beforeSnapshot;
  final String afterSnapshotHash;
}
