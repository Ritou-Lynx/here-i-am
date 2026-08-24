library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/domain_command.dart';
import 'package:memex/domain/whiteboard/domain_command_receipt.dart';
import 'package:memex/domain/whiteboard/snapshot_integrity.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/domain/whiteboard/whiteboard_ids.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/domain/workbench_ai/permissions/whiteboard_permission_broker.dart';

typedef WhiteboardDomainClock = DateTime Function();
typedef WhiteboardDomainIdFactory = String Function(String prefix);
typedef WhiteboardDomainSnapshotLoader = Future<WhiteboardSnapshot> Function(
  String boardId,
);
typedef WhiteboardDomainSnapshotSaver = Future<bool> Function(
  String boardId,
  WhiteboardSnapshot snapshot,
);

class WhiteboardDomainCommandExecutor {
  WhiteboardDomainCommandExecutor({
    required this.permissionBroker,
    required WhiteboardDomainSnapshotLoader loadSnapshot,
    required WhiteboardDomainSnapshotSaver saveSnapshot,
    WhiteboardDomainClock? clock,
    WhiteboardDomainIdFactory? idFactory,
  })  : _loadSnapshot = loadSnapshot,
        _saveSnapshot = saveSnapshot,
        _clock = clock ?? (() => DateTime.now().toUtc()),
        _idFactory = idFactory ?? ((prefix) => StableId.generate(prefix).value);

  factory WhiteboardDomainCommandExecutor.forDriftStore({
    required WhiteboardPermissionBroker permissionBroker,
    required WhiteboardDriftStore store,
    WhiteboardDomainClock? clock,
    WhiteboardDomainIdFactory? idFactory,
  }) =>
      WhiteboardDomainCommandExecutor(
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

  static const hardMaxCommands = 64;
  static const hardMaxUndoUtf8Bytes = 32 * 1024;
  static const hardMaxBodyRunes = 16 * 1024;
  static const hardMaxLabels = 64;
  static const hardMaxLabelRunes = 120;

  final WhiteboardPermissionBroker permissionBroker;
  final WhiteboardDomainSnapshotLoader _loadSnapshot;
  final WhiteboardDomainSnapshotSaver _saveSnapshot;
  final WhiteboardDomainClock _clock;
  final WhiteboardDomainIdFactory _idFactory;
  final Map<String, _AppliedDomainBatch> _appliedBatches = {};
  final Map<String, WhiteboardDomainUndoReceipt> _undoReceipts = {};
  final Map<String, WhiteboardDomainCommandReceipt> _completedUndos = {};

  static String snapshotHash(WhiteboardSnapshot snapshot) => sha256
      .convert(utf8.encode(jsonEncode(_canonicalSnapshot(snapshot))))
      .toString();

  void restoreAppliedAction({
    required WhiteboardDomainCommandBatch batch,
    required WhiteboardDomainCommandReceipt receipt,
  }) {
    if (receipt.status != WhiteboardDomainCommandStatus.applied ||
        receipt.undoReceipt == null) {
      return;
    }
    final hash = _hashJson(batch.toJson());
    _appliedBatches.putIfAbsent(
      batch.operationBatchId,
      () => _AppliedDomainBatch(hash, receipt),
    );
    _undoReceipts.putIfAbsent(
      receipt.undoReceipt!.undoToken,
      () => receipt.undoReceipt!,
    );
  }

  Future<WhiteboardDomainCommandReceipt> execute(
    WhiteboardDomainExecutionRequest request,
  ) async {
    final now = _millisecondUtc(_clock());
    final batch = request.batch;
    final requestHash = _hashJson(batch.toJson());
    final applied = _appliedBatches[batch.operationBatchId];
    if (applied != null) {
      if (applied.requestHash == requestHash) return applied.receipt;
      return _failure(
        request,
        WhiteboardDomainCommandStatus.conflict,
        'batch_id_reused',
        now,
      );
    }
    final validationIssue = _validateBatch(batch);
    if (validationIssue != null) {
      return _failure(
        request,
        WhiteboardDomainCommandStatus.invalidRequest,
        validationIssue,
        now,
      );
    }

    final capabilities = batch.commands.map(_capability).toSet();
    final targetCardIds = batch.commands.expand((c) => c.targetCardIds).toSet();
    final targetItemIds = batch.commands.expand((c) => c.targetItemIds).toSet();
    final decision = permissionBroker.reserve(
      authorizationId: request.authorizationId,
      operationBatchId: batch.operationBatchId,
      runtimeTurnId: request.actorTurnId,
      boardId: batch.boardId,
      targetItemIds: targetItemIds,
      targetCardIds: targetCardIds,
      requiredCapabilities: capabilities,
      operationCount: batch.commands.length,
    );
    if (!decision.allowed) {
      return _failure(
        request,
        WhiteboardDomainCommandStatus.denied,
        'permission_${decision.code.name}',
        now,
      );
    }

    WhiteboardSnapshot before;
    try {
      before = await _loadSnapshot(batch.boardId);
    } catch (_) {
      permissionBroker.release(
        authorizationId: request.authorizationId,
        operationBatchId: batch.operationBatchId,
      );
      return _failure(
        request,
        WhiteboardDomainCommandStatus.unavailable,
        'snapshot_unavailable',
        now,
      );
    }
    final beforeHash = snapshotHash(before);
    if (batch.expectedSnapshotHash != null &&
        batch.expectedSnapshotHash != beforeHash) {
      permissionBroker.release(
        authorizationId: request.authorizationId,
        operationBatchId: batch.operationBatchId,
      );
      return _failure(
        request,
        WhiteboardDomainCommandStatus.conflict,
        'snapshot_conflict',
        now,
        beforeHash: beforeHash,
      );
    }

    final mutation = _MutableSnapshot.from(before);
    final inverseSteps = <Map<String, dynamic>>[];
    try {
      for (final command in batch.commands) {
        inverseSteps.insert(
          0,
          _apply(command, mutation, batch.boardId, now, request.actor),
        );
      }
    } on _DomainCommandException catch (error) {
      permissionBroker.release(
        authorizationId: request.authorizationId,
        operationBatchId: batch.operationBatchId,
      );
      return _failure(
        request,
        error.conflict
            ? WhiteboardDomainCommandStatus.conflict
            : WhiteboardDomainCommandStatus.invalidRequest,
        error.code,
        now,
        beforeHash: beforeHash,
      );
    }
    final after = mutation.toSnapshot(updatedAt: now);
    final integrity = validateSnapshotIntegrity(after);
    if (!integrity.isValid) {
      permissionBroker.release(
        authorizationId: request.authorizationId,
        operationBatchId: batch.operationBatchId,
      );
      return _failure(
        request,
        WhiteboardDomainCommandStatus.conflict,
        'result_integrity_failed',
        now,
        beforeHash: beforeHash,
      );
    }
    final afterHash = snapshotHash(after);
    final undoToken = _idFactory('undo');
    final undo = WhiteboardDomainUndoReceipt(
      undoToken: undoToken,
      operationBatchId: batch.operationBatchId,
      boardId: batch.boardId,
      afterSnapshotHash: afterHash,
      inverseSteps: inverseSteps,
    );
    if (utf8.encode(jsonEncode(undo.toJson())).length > hardMaxUndoUtf8Bytes) {
      permissionBroker.release(
        authorizationId: request.authorizationId,
        operationBatchId: batch.operationBatchId,
      );
      return _failure(
        request,
        WhiteboardDomainCommandStatus.invalidRequest,
        'undo_payload_too_large',
        now,
        beforeHash: beforeHash,
      );
    }

    final saved = await _saveSnapshot(batch.boardId, after);
    if (!saved) {
      permissionBroker.release(
        authorizationId: request.authorizationId,
        operationBatchId: batch.operationBatchId,
      );
      return _failure(
        request,
        WhiteboardDomainCommandStatus.unavailable,
        'save_failed',
        now,
        beforeHash: beforeHash,
      );
    }
    if (!permissionBroker.commit(
      authorizationId: request.authorizationId,
      operationBatchId: batch.operationBatchId,
    )) {
      throw StateError('authorization commit failed after durable save');
    }
    final receipt = WhiteboardDomainCommandReceipt(
      status: WhiteboardDomainCommandStatus.applied,
      operationBatchId: batch.operationBatchId,
      boardId: batch.boardId,
      commandIds: batch.commands.map((c) => c.commandId).toList(),
      summary: 'Applied ${batch.commands.length} domain commands',
      authorizationId: request.authorizationId,
      beforeSnapshotHash: beforeHash,
      afterSnapshotHash: afterHash,
      undoReceipt: undo,
      occurredAt: now,
    );
    _appliedBatches[batch.operationBatchId] = _AppliedDomainBatch(
      requestHash,
      receipt,
    );
    _undoReceipts[undoToken] = undo;
    return receipt;
  }

  Future<WhiteboardDomainCommandReceipt> undo({
    required String undoToken,
  }) async {
    final completed = _completedUndos[undoToken];
    if (completed != null) return completed;
    final undo = _undoReceipts[undoToken];
    final now = _millisecondUtc(_clock());
    if (undo == null) {
      return WhiteboardDomainCommandReceipt(
        status: WhiteboardDomainCommandStatus.invalidRequest,
        operationBatchId: 'unknown_batch',
        boardId: 'unknown_board',
        commandIds: const [],
        summary: 'Undo receipt not found',
        issues: const [WhiteboardDomainCommandIssue('undo_not_found')],
        occurredAt: now,
      );
    }
    WhiteboardSnapshot current;
    try {
      current = await _loadSnapshot(undo.boardId);
    } catch (_) {
      return _undoFailure(
        undo,
        WhiteboardDomainCommandStatus.unavailable,
        'snapshot_unavailable',
        now,
      );
    }
    if (snapshotHash(current) != undo.afterSnapshotHash) {
      return _undoFailure(
        undo,
        WhiteboardDomainCommandStatus.conflict,
        'snapshot_changed_after_batch',
        now,
      );
    }
    final mutation = _MutableSnapshot.from(current);
    try {
      for (final step in undo.inverseSteps) {
        _applyInverse(step, mutation, now);
      }
    } catch (_) {
      return _undoFailure(
        undo,
        WhiteboardDomainCommandStatus.conflict,
        'inverse_invalid',
        now,
      );
    }
    final restored = mutation.toSnapshot(updatedAt: now);
    if (!validateSnapshotIntegrity(restored).isValid) {
      return _undoFailure(
        undo,
        WhiteboardDomainCommandStatus.conflict,
        'inverse_integrity_failed',
        now,
      );
    }
    if (!await _saveSnapshot(undo.boardId, restored)) {
      return _undoFailure(
        undo,
        WhiteboardDomainCommandStatus.unavailable,
        'save_failed',
        now,
      );
    }
    final receipt = WhiteboardDomainCommandReceipt(
      status: WhiteboardDomainCommandStatus.undone,
      operationBatchId: undo.operationBatchId,
      boardId: undo.boardId,
      commandIds: const [],
      summary: 'Domain command batch undone',
      beforeSnapshotHash: undo.afterSnapshotHash,
      afterSnapshotHash: snapshotHash(restored),
      occurredAt: now,
    );
    _completedUndos[undoToken] = receipt;
    _undoReceipts.remove(undoToken);
    return receipt;
  }

  WhiteboardDomainCommandReceipt _failure(
    WhiteboardDomainExecutionRequest request,
    WhiteboardDomainCommandStatus status,
    String code,
    DateTime now, {
    String? beforeHash,
  }) =>
      WhiteboardDomainCommandReceipt(
        status: status,
        operationBatchId: request.batch.operationBatchId,
        boardId: request.batch.boardId,
        commandIds: request.batch.commands.map((c) => c.commandId).toList(),
        summary: code,
        authorizationId: request.authorizationId,
        beforeSnapshotHash: beforeHash,
        issues: [WhiteboardDomainCommandIssue(code)],
        occurredAt: now,
      );

  WhiteboardDomainCommandReceipt _undoFailure(
    WhiteboardDomainUndoReceipt undo,
    WhiteboardDomainCommandStatus status,
    String code,
    DateTime now,
  ) =>
      WhiteboardDomainCommandReceipt(
        status: status,
        operationBatchId: undo.operationBatchId,
        boardId: undo.boardId,
        commandIds: const [],
        summary: code,
        issues: [WhiteboardDomainCommandIssue(code)],
        occurredAt: now,
      );
}

String? _validateBatch(WhiteboardDomainCommandBatch batch) {
  if (batch.commands.isEmpty ||
      batch.commands.length > WhiteboardDomainCommandExecutor.hardMaxCommands) {
    return 'invalid_command_count';
  }
  final ids = <String>{};
  for (final command in batch.commands) {
    if (!ids.add(command.commandId)) return 'duplicate_command_id';
    if (command is CreateCardCommand) {
      if (command.title.runes.length > 500 ||
          command.body.runes.length >
              WhiteboardDomainCommandExecutor.hardMaxBodyRunes ||
          !_validLabels(command.labels) ||
          !_validSize(command.width, command.height)) {
        return 'invalid_create_card';
      }
    } else if (command is EditCardBodyCommand &&
        command.body.runes.length >
            WhiteboardDomainCommandExecutor.hardMaxBodyRunes) {
      return 'body_too_large';
    } else if (command is SetCardLabelsCommand &&
        !_validLabels(command.labels)) {
      return 'invalid_labels';
    } else if (command is MovePlacementCommand &&
        (!command.x.isFinite || !command.y.isFinite)) {
      return 'invalid_position';
    } else if (command is ResizePlacementCommand &&
        !_validSize(command.width, command.height)) {
      return 'invalid_size';
    }
  }
  return null;
}

bool _validLabels(List<String> labels) =>
    labels.length <= WhiteboardDomainCommandExecutor.hardMaxLabels &&
    labels.every(
      (label) =>
          label.trim().isNotEmpty &&
          label.runes.length <=
              WhiteboardDomainCommandExecutor.hardMaxLabelRunes,
    );

bool _validSize(double width, double height) =>
    width.isFinite &&
    height.isFinite &&
    width >= 80 &&
    height >= 60 &&
    width <= 3000 &&
    height <= 3000;

WhiteboardWriteCapability _capability(WhiteboardDomainCommand command) =>
    switch (command) {
      CreateCardCommand() => WhiteboardWriteCapability.createCard,
      EditCardBodyCommand() => WhiteboardWriteCapability.editCardBody,
      SetCardLabelsCommand() => WhiteboardWriteCapability.setCardLabels,
      MovePlacementCommand() => WhiteboardWriteCapability.movePlacement,
      ResizePlacementCommand() => WhiteboardWriteCapability.resizePlacement,
      RemovePlacementCommand() => WhiteboardWriteCapability.removePlacement,
    };

Map<String, dynamic> _apply(
  WhiteboardDomainCommand command,
  _MutableSnapshot snapshot,
  String boardId,
  DateTime now,
  WhiteboardDomainCommandActor actor,
) {
  if (!snapshot.boards.any(
    (board) => board.boardId == boardId && board.deletedAt == null,
  )) {
    throw const _DomainCommandException('board_not_found', conflict: true);
  }
  switch (command) {
    case CreateCardCommand():
      if (snapshot.cards.any((card) => card.cardId == command.cardId) ||
          snapshot.items.any((item) => item.itemId == command.itemId)) {
        throw const _DomainCommandException('create_id_exists', conflict: true);
      }
      snapshot.cards.add(
        CardContract(
          cardId: command.cardId,
          cardKind: CardKind.note,
          title: command.title,
          body: command.body,
          tags: _normalizeLabels(command.labels),
          createdBy: actor == WhiteboardDomainCommandActor.i
              ? CardCreatedBy.i
              : CardCreatedBy.user,
          createdAt: now,
          updatedAt: now,
        ),
      );
      snapshot.items.add(
        BoardItem(
          itemId: command.itemId,
          boardId: boardId,
          cardId: command.cardId,
          x: command.x,
          y: command.y,
          width: command.width,
          height: command.height,
        ),
      );
      return {
        'kind': 'remove_created_card',
        'card_id': command.cardId,
        'item_id': command.itemId,
      };
    case EditCardBodyCommand():
      final index = _cardIndex(snapshot.cards, command.cardId);
      final card = snapshot.cards[index];
      snapshot.cards[index] = _copyCard(
        card,
        body: command.body,
        updatedAt: now,
      );
      return {
        'kind': 'restore_body',
        'card_id': command.cardId,
        'body': card.body,
      };
    case SetCardLabelsCommand():
      final index = _cardIndex(snapshot.cards, command.cardId);
      final card = snapshot.cards[index];
      snapshot.cards[index] = _copyCard(
        card,
        tags: _normalizeLabels(command.labels),
        updatedAt: now,
      );
      return {
        'kind': 'restore_labels',
        'card_id': command.cardId,
        'labels': card.tags,
      };
    case MovePlacementCommand():
      final index = _itemIndex(snapshot.items, command.itemId, boardId);
      final item = snapshot.items[index];
      snapshot.items[index] = _copyItem(item, x: command.x, y: command.y);
      return {
        'kind': 'restore_move',
        'item_id': command.itemId,
        'x': item.x,
        'y': item.y,
      };
    case ResizePlacementCommand():
      final index = _itemIndex(snapshot.items, command.itemId, boardId);
      final item = snapshot.items[index];
      snapshot.items[index] = _copyItem(
        item,
        width: command.width,
        height: command.height,
      );
      return {
        'kind': 'restore_resize',
        'item_id': command.itemId,
        'width': item.width,
        'height': item.height,
      };
    case RemovePlacementCommand():
      final index = _itemIndex(snapshot.items, command.itemId, boardId);
      final item = snapshot.items.removeAt(index);
      final memberGroupIds = snapshot.members
          .where((member) => member.itemId == command.itemId)
          .map((member) => member.groupId)
          .toSet();
      final members = snapshot.members
          .where((member) => member.itemId == command.itemId)
          .map((member) => member.toJson())
          .toList();
      final groups = snapshot.groups
          .where((group) => memberGroupIds.contains(group.groupId))
          .map((group) => group.toJson())
          .toList();
      final edges = snapshot.edges
          .where(
            (edge) =>
                edge.fromItemId == command.itemId ||
                edge.toItemId == command.itemId,
          )
          .map((edge) => edge.toJson())
          .toList();
      snapshot.members.removeWhere((member) => member.itemId == command.itemId);
      snapshot.edges.removeWhere(
        (edge) =>
            edge.fromItemId == command.itemId ||
            edge.toItemId == command.itemId,
      );
      snapshot.groups.removeWhere(
        (group) =>
            memberGroupIds.contains(group.groupId) &&
            !snapshot.members.any((member) => member.groupId == group.groupId),
      );
      return {
        'kind': 'restore_placement',
        'item': item.toJson(),
        'groups': groups,
        'members': members,
        'edges': edges,
      };
  }
}

void _applyInverse(
  Map<String, dynamic> step,
  _MutableSnapshot snapshot,
  DateTime now,
) {
  switch (step['kind']) {
    case 'remove_created_card':
      final cardId = step['card_id'] as String;
      snapshot.items.removeWhere((item) => item.itemId == step['item_id']);
      final index = _cardIndex(snapshot.cards, cardId);
      snapshot.cards[index] = _copyCard(
        snapshot.cards[index],
        deletedAt: now,
        setDeletedAt: true,
        updatedAt: now,
      );
    case 'restore_body':
      final index = _cardIndex(snapshot.cards, step['card_id'] as String);
      snapshot.cards[index] = _copyCard(
        snapshot.cards[index],
        body: step['body'] as String,
        updatedAt: now,
      );
    case 'restore_labels':
      final index = _cardIndex(snapshot.cards, step['card_id'] as String);
      snapshot.cards[index] = _copyCard(
        snapshot.cards[index],
        tags: (step['labels'] as List).cast<String>(),
        updatedAt: now,
      );
    case 'restore_move':
      final index = snapshot.items.indexWhere(
        (item) => item.itemId == step['item_id'],
      );
      if (index < 0) throw StateError('item missing');
      snapshot.items[index] = _copyItem(
        snapshot.items[index],
        x: (step['x'] as num).toDouble(),
        y: (step['y'] as num).toDouble(),
      );
    case 'restore_resize':
      final index = snapshot.items.indexWhere(
        (item) => item.itemId == step['item_id'],
      );
      if (index < 0) throw StateError('item missing');
      snapshot.items[index] = _copyItem(
        snapshot.items[index],
        width: (step['width'] as num).toDouble(),
        height: (step['height'] as num).toDouble(),
      );
    case 'restore_placement':
      for (final value in step['groups'] as List) {
        final group = BoardGroup.fromJson(
          Map<String, dynamic>.from(value as Map),
        );
        if (!snapshot.groups
            .any((existing) => existing.groupId == group.groupId)) {
          snapshot.groups.add(group);
        }
      }
      snapshot.items.add(
        BoardItem.fromJson(Map<String, dynamic>.from(step['item'] as Map)),
      );
      snapshot.members.addAll(
        (step['members'] as List).map(
          (value) =>
              GroupMember.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      );
      snapshot.edges.addAll(
        (step['edges'] as List).map(
          (value) =>
              BoardEdge.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      );
    default:
      throw const FormatException('unknown inverse step');
  }
}

int _cardIndex(List<CardContract> cards, String cardId) {
  final index = cards.indexWhere(
    (card) => card.cardId == cardId && card.deletedAt == null,
  );
  if (index < 0) {
    throw const _DomainCommandException('card_not_found', conflict: true);
  }
  return index;
}

int _itemIndex(List<BoardItem> items, String itemId, String boardId) {
  final index = items.indexWhere(
    (item) => item.itemId == itemId && item.boardId == boardId,
  );
  if (index < 0) {
    throw const _DomainCommandException('placement_not_found', conflict: true);
  }
  return index;
}

List<String> _normalizeLabels(List<String> labels) {
  final seen = <String>{};
  return [
    for (final label in labels)
      if (seen.add(label.trim().toLowerCase())) label.trim(),
  ];
}

CardContract _copyCard(
  CardContract card, {
  String? body,
  List<String>? tags,
  DateTime? updatedAt,
  DateTime? deletedAt,
  bool setDeletedAt = false,
}) =>
    CardContract(
      cardId: card.cardId,
      cardKind: card.cardKind,
      sourceId: card.sourceId,
      ownerSpace: card.ownerSpace,
      title: card.title,
      body: body ?? card.body,
      tags: tags ?? card.tags,
      presentation: card.presentation,
      createdBy: card.createdBy,
      createdAt: card.createdAt,
      updatedAt: updatedAt ?? card.updatedAt,
      deletedAt: setDeletedAt ? deletedAt : card.deletedAt,
    );

BoardItem _copyItem(
  BoardItem item, {
  double? x,
  double? y,
  double? width,
  double? height,
}) =>
    BoardItem(
      itemId: item.itemId,
      boardId: item.boardId,
      cardId: item.cardId,
      x: x ?? item.x,
      y: y ?? item.y,
      width: width ?? item.width,
      height: height ?? item.height,
      rotation: item.rotation,
      zIndex: item.zIndex,
      viewState: item.viewState,
    );

class _MutableSnapshot {
  _MutableSnapshot.from(WhiteboardSnapshot source)
      : schemaVersion = source.schemaVersion,
        sources = source.sources,
        versions = source.sourceVersions,
        cards = List.of(source.cards),
        boards = source.boards,
        items = List.of(source.boardItems),
        groups = List.of(source.groups),
        members = List.of(source.groupMembers),
        edges = List.of(source.edges),
        viewport = source.viewport;

  final int schemaVersion;
  final List<SourceContent> sources;
  final List<SourceVersion> versions;
  final List<CardContract> cards;
  final List<Board> boards;
  final List<BoardItem> items;
  final List<BoardGroup> groups;
  final List<GroupMember> members;
  final List<BoardEdge> edges;
  final BoardViewport viewport;

  WhiteboardSnapshot toSnapshot({required DateTime updatedAt}) =>
      WhiteboardSnapshot(
        schemaVersion: schemaVersion,
        sources: sources,
        sourceVersions: versions,
        cards: cards,
        boards: boards,
        boardItems: items,
        groups: groups,
        groupMembers: members,
        edges: edges,
        viewport: viewport,
        updatedAt: updatedAt,
      );
}

Map<String, dynamic> _canonicalSnapshot(WhiteboardSnapshot snapshot) {
  List<Map<String, dynamic>> sorted<T>(
    Iterable<T> values,
    String Function(T value) id,
    Map<String, dynamic> Function(T value) encode,
  ) {
    final list = values.toList()..sort((a, b) => id(a).compareTo(id(b)));
    return list.map((value) {
      final json = Map<String, dynamic>.from(encode(value));
      json.remove('updated_at');
      return json;
    }).toList();
  }

  return {
    'schema_version': snapshot.schemaVersion,
    'sources': sorted(snapshot.sources, (v) => v.sourceId, (v) => v.toJson()),
    'source_versions': sorted(
      snapshot.sourceVersions,
      (v) => v.versionId,
      (v) => v.toJson(),
    ),
    'cards': sorted(snapshot.cards, (v) => v.cardId, (v) => v.toJson()),
    'boards': sorted(snapshot.boards, (v) => v.boardId, (v) => v.toJson()),
    'board_items': sorted(
      snapshot.boardItems,
      (v) => v.itemId,
      (v) => v.toJson(),
    ),
    'groups': sorted(snapshot.groups, (v) => v.groupId, (v) => v.toJson()),
    'group_members': sorted(
      snapshot.groupMembers,
      (v) => '${v.groupId}:${v.itemId}',
      (v) => v.toJson(),
    ),
    'edges': sorted(snapshot.edges, (v) => v.edgeId, (v) => v.toJson()),
    'viewport': snapshot.viewport.toJson(),
  };
}

String _hashJson(Map<String, dynamic> value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

DateTime _millisecondUtc(DateTime value) => DateTime.fromMillisecondsSinceEpoch(
      value.toUtc().millisecondsSinceEpoch,
      isUtc: true,
    );

class _AppliedDomainBatch {
  const _AppliedDomainBatch(this.requestHash, this.receipt);
  final String requestHash;
  final WhiteboardDomainCommandReceipt receipt;
}

class _DomainCommandException implements Exception {
  const _DomainCommandException(this.code, {this.conflict = false});
  final String code;
  final bool conflict;
}
