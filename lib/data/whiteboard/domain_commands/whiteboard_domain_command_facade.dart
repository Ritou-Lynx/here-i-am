library;

import 'dart:convert';

import 'package:memex/data/whiteboard/domain_commands/whiteboard_domain_command_executor.dart';
import 'package:memex/data/workbench_ai/workbench_action_reader.dart';
import 'package:memex/domain/whiteboard/domain_command.dart';
import 'package:memex/domain/whiteboard/domain_command_receipt.dart';
import 'package:memex/domain/workbench_ai/action/workbench_action_projection.dart';
import 'package:memex/domain/workbench_ai/permissions/whiteboard_permission_broker.dart';

typedef DomainWorkbenchActionAdd = Future<int> Function(
  String characterId,
  String content,
  Map<String, dynamic> projection,
);
typedef DomainWorkbenchActionUpdate = Future<void> Function(
  int messageId,
  String content,
  Map<String, dynamic> projection,
);

/// The single product facade used by direct user actions and Runtime tools.
/// Both paths persist the same command batch, receipt, bounded inverse payload,
/// hash guard, permission decision, idempotency state, and undo semantics.
class WhiteboardDomainCommandFacade {
  WhiteboardDomainCommandFacade({
    required this.executor,
    required this.permissionBroker,
    required DomainWorkbenchActionAdd addAction,
    required DomainWorkbenchActionUpdate updateAction,
    required WorkbenchActionReader readActions,
    DateTime Function()? clock,
  })  : _addAction = addAction,
        _updateAction = updateAction,
        _readActions = readActions,
        _clock = clock ?? (() => DateTime.now().toUtc());

  final WhiteboardDomainCommandExecutor executor;
  final WhiteboardPermissionBroker permissionBroker;
  final DomainWorkbenchActionAdd _addAction;
  final DomainWorkbenchActionUpdate _updateAction;
  final WorkbenchActionReader _readActions;
  final DateTime Function() _clock;
  final Map<String, _DomainUndoBinding> _undoBindings = {};
  final Set<String> _restoredCharacters = {};

  bool canUndo(String actionId) => _undoBindings.containsKey(actionId);

  bool isRestored(String characterId) =>
      _restoredCharacters.contains(characterId);

  WhiteboardAuthorizationGrant authorizeRuntime({
    required WhiteboardDomainCommandBatch batch,
    required String runtimeTurnId,
    required String userAuthorizationMessageId,
  }) =>
      permissionBroker.issueSelectionAuthorization(
        runtimeTurnId: runtimeTurnId,
        userAuthorizationMessageId: userAuthorizationMessageId,
        boardId: batch.boardId,
        selectedItemIds:
            batch.commands.expand((command) => command.targetItemIds).toSet(),
        selectedCardIds:
            batch.commands.expand((command) => command.targetCardIds).toSet(),
        capabilities: batch.commands.map(_capability).toSet(),
        maxOperationCount: batch.commands.length,
      );

  Future<WhiteboardDomainCommandReceipt> executeUser({
    required String characterId,
    required WhiteboardDomainCommandBatch batch,
    required String userAuthorizationMessageId,
  }) {
    final actorTurnId = 'user-${batch.operationBatchId}';
    final grant = authorizeRuntime(
      batch: batch,
      runtimeTurnId: actorTurnId,
      userAuthorizationMessageId: userAuthorizationMessageId,
    );
    return _executePersisted(
      characterId: characterId,
      batch: batch,
      authorizationId: grant.authorizationId,
      actorTurnId: actorTurnId,
      actor: WhiteboardDomainCommandActor.user,
      userAuthorizationMessageId: userAuthorizationMessageId,
    );
  }

  Future<WhiteboardDomainCommandReceipt> executeRuntime({
    required String characterId,
    required WhiteboardDomainCommandBatch batch,
    required String authorizationId,
    required String runtimeTurnId,
    required String userAuthorizationMessageId,
  }) =>
      _executePersisted(
        characterId: characterId,
        batch: batch,
        authorizationId: authorizationId,
        actorTurnId: runtimeTurnId,
        actor: WhiteboardDomainCommandActor.i,
        userAuthorizationMessageId: userAuthorizationMessageId,
      );

  Future<WhiteboardDomainCommandReceipt> _executePersisted({
    required String characterId,
    required WhiteboardDomainCommandBatch batch,
    required String authorizationId,
    required String actorTurnId,
    required WhiteboardDomainCommandActor actor,
    required String userAuthorizationMessageId,
  }) async {
    final now = _clock().toUtc();
    var projection = WorkbenchActionProjection(
      actionId: batch.operationBatchId,
      actionType: 'whiteboard_domain_commands',
      title: '白板卡片操作',
      status: WorkbenchActionStatus.running,
      boardId: batch.boardId,
      selectedItemCount: batch.commands
          .expand((command) => command.targetItemIds)
          .toSet()
          .length,
      summary: '正在执行白板卡片操作。',
      runtimeTurnId: actorTurnId,
      operationBatchId: batch.operationBatchId,
      authorizationId: authorizationId,
      userAuthorizationMessageId: userAuthorizationMessageId,
      domainCommandBatch: batch.toJson(),
      tools: const ['whiteboard_domain_commands'],
      createdAt: now,
      updatedAt: now,
    );
    final messageId = await _addAction(
      characterId,
      projection.summary,
      projection.toJson(),
    );
    final receipt = await executor.execute(
      WhiteboardDomainExecutionRequest(
        batch: batch,
        authorizationId: authorizationId,
        actorTurnId: actorTurnId,
        actor: actor,
      ),
    );
    projection = projection.copyWith(
      status: receipt.status == WhiteboardDomainCommandStatus.applied
          ? WorkbenchActionStatus.completed
          : WorkbenchActionStatus.failed,
      summary: receipt.succeeded ? '白板卡片操作已完成，可撤销。' : receipt.summary,
      beforeSnapshotHash: receipt.beforeSnapshotHash,
      afterSnapshotHash: receipt.afterSnapshotHash,
      undoToken: receipt.undoReceipt?.undoToken,
      undoReceipt: receipt.undoReceipt?.toJson(),
      domainCommandReceipt: receipt.toJson(),
      errorCode: receipt.succeeded || receipt.issues.isEmpty
          ? null
          : receipt.issues.first.code,
    );
    await _updateAction(messageId, projection.summary, projection.toJson());
    if (receipt.status == WhiteboardDomainCommandStatus.applied &&
        receipt.undoReceipt != null) {
      _undoBindings[projection.actionId] = _DomainUndoBinding(
        messageId: messageId,
        projection: projection,
        undoToken: receipt.undoReceipt!.undoToken,
      );
    }
    return receipt;
  }

  Future<void> restore(
    String characterId, {
    List<PersistedWorkbenchAction>? persistedActions,
  }) async {
    if (_restoredCharacters.contains(characterId)) return;
    final persisted = persistedActions ?? await _readActions(characterId);
    for (final record in persisted) {
      final action = record.projection;
      if (action.actionType != 'whiteboard_domain_commands' ||
          action.status != WorkbenchActionStatus.completed ||
          action.domainCommandBatch == null ||
          action.domainCommandReceipt == null ||
          action.undoToken == null ||
          action.undoReceipt == null) {
        continue;
      }
      try {
        final batch = WhiteboardDomainCommandBatch.fromJson(
          action.domainCommandBatch!,
        );
        final receipt = WhiteboardDomainCommandReceipt.fromJson(
          action.domainCommandReceipt!,
        );
        final projectedUndo = WhiteboardDomainUndoReceipt.fromJson(
          action.undoReceipt!,
        );
        if (receipt.undoReceipt == null ||
            receipt.undoReceipt!.undoToken != action.undoToken ||
            jsonEncode(receipt.undoReceipt!.toJson()) !=
                jsonEncode(projectedUndo.toJson()) ||
            batch.operationBatchId != action.actionId ||
            action.operationBatchId != batch.operationBatchId ||
            batch.boardId != action.boardId ||
            receipt.beforeSnapshotHash != action.beforeSnapshotHash ||
            receipt.afterSnapshotHash != action.afterSnapshotHash ||
            !executor.restoreAppliedAction(batch: batch, receipt: receipt)) {
          continue;
        }
        _undoBindings.putIfAbsent(
          action.actionId,
          () => _DomainUndoBinding(
            messageId: record.messageId,
            projection: action,
            undoToken: action.undoToken!,
          ),
        );
      } catch (_) {
        // Malformed historical records fail closed and do not create Undo.
      }
    }
    _restoredCharacters.add(characterId);
  }

  Future<WhiteboardDomainCommandReceipt?> undo({
    required String characterId,
    required String actionId,
  }) async {
    await restore(characterId);
    final binding = _undoBindings[actionId];
    if (binding == null) return null;
    final receipt = await executor.undo(undoToken: binding.undoToken);
    final projection = binding.projection.copyWith(
      status: receipt.status == WhiteboardDomainCommandStatus.undone
          ? WorkbenchActionStatus.undone
          : binding.projection.status,
      summary: receipt.status == WhiteboardDomainCommandStatus.undone
          ? '已撤销白板卡片操作。'
          : receipt.summary,
      domainCommandReceipt:
          receipt.status == WhiteboardDomainCommandStatus.undone
              ? receipt.toJson()
              : binding.projection.domainCommandReceipt,
      errorCode: receipt.succeeded || receipt.issues.isEmpty
          ? null
          : receipt.issues.first.code,
    );
    await _updateAction(
      binding.messageId,
      projection.summary,
      projection.toJson(),
    );
    if (receipt.status == WhiteboardDomainCommandStatus.undone) {
      _undoBindings.remove(actionId);
    }
    return receipt;
  }
}

WhiteboardWriteCapability _capability(WhiteboardDomainCommand command) =>
    switch (command) {
      CreateCardCommand() => WhiteboardWriteCapability.createCard,
      EditCardBodyCommand() => WhiteboardWriteCapability.editCardBody,
      SetCardLabelsCommand() => WhiteboardWriteCapability.setCardLabels,
      MovePlacementCommand() => WhiteboardWriteCapability.movePlacement,
      ResizePlacementCommand() => WhiteboardWriteCapability.resizePlacement,
      RemovePlacementCommand() => WhiteboardWriteCapability.removePlacement,
    };

class _DomainUndoBinding {
  const _DomainUndoBinding({
    required this.messageId,
    required this.projection,
    required this.undoToken,
  });
  final int messageId;
  final WorkbenchActionProjection projection;
  final String undoToken;
}
