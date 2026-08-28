library;

import 'dart:async';
import 'dart:convert';

import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/whiteboard/ai_read_tools/whiteboard_ai_read_models.dart';
import 'package:memex/data/whiteboard/ai_read_tools/whiteboard_ai_read_tool_host.dart';
import 'package:memex/data/whiteboard/ai_write_tools/whiteboard_ai_write_models.dart';
import 'package:memex/data/whiteboard/ai_write_tools/whiteboard_ai_write_tool_host.dart';
import 'package:memex/data/whiteboard/domain_commands/whiteboard_domain_command_executor.dart';
import 'package:memex/data/whiteboard/domain_commands/whiteboard_domain_command_facade.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_data_bootstrap.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/data/workbench_ai/whiteboard_workbench_surface.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';
import 'package:memex/data/workbench_ai/workbench_action_reader.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/domain_command.dart';
import 'package:memex/domain/whiteboard/domain_command_receipt.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/domain/whiteboard/whiteboard_ids.dart';
import 'package:memex/domain/workbench_ai/action/workbench_action_projection.dart';
import 'package:memex/domain/workbench_ai/permissions/whiteboard_permission_broker.dart';

typedef WorkbenchActionAdd = Future<int> Function(
  String characterId,
  String content,
  Map<String, dynamic> projection,
);
typedef WorkbenchActionUpdate = Future<void> Function(
  int messageId,
  String content,
  Map<String, dynamic> projection,
);

class WhiteboardWorkbenchCoordinator {
  WhiteboardWorkbenchCoordinator({
    required WorkbenchRuntimeGateway runtime,
    required WhiteboardDriftStore store,
    required Future<UnifiedCardRepository> Function() repositoryLoader,
    required WhiteboardWorkbenchSurfaceController surfaceController,
    required WorkbenchActionAdd addAction,
    required WorkbenchActionUpdate updateAction,
    WorkbenchActionReader? readActions,
    WhiteboardPermissionBroker? permissionBroker,
    DateTime Function()? clock,
  })  : _runtime = runtime,
        _store = store,
        _repositoryLoader = repositoryLoader,
        _surfaceController = surfaceController,
        _addAction = addAction,
        _updateAction = updateAction,
        _readActions = readActions ??
            ((characterId) => readPersistedWorkbenchActions(
                  AppDatabase.instance,
                  characterId,
                )),
        _permissionBroker = permissionBroker ?? WhiteboardPermissionBroker(),
        _clock = clock ?? (() => DateTime.now().toUtc());

  static final instance = WhiteboardWorkbenchCoordinator(
    runtime: WorkbenchRuntimeClient(),
    store: WhiteboardDriftStore(AppDatabase.instance),
    repositoryLoader: WhiteboardDataBootstrap.productionRepository,
    surfaceController: WhiteboardWorkbenchSurfaceController.instance,
    addAction: (characterId, content, projection) => PersonaChatService.instance
        .addWorkbenchActionMessage(characterId, content, projection),
    updateAction: (messageId, content, projection) =>
        PersonaChatService.instance.updateWorkbenchActionMessage(
      messageId: messageId,
      content: content,
      projection: projection,
    ),
    readActions: (characterId) =>
        readPersistedWorkbenchActions(AppDatabase.instance, characterId),
  );

  static const readToolName = 'whiteboard_read_selection';
  static const writeToolName = 'whiteboard_group_and_connect';
  static const _terminalStatuses = {
    'completed',
    'failed',
    'interrupted',
    'closed',
    'unavailable',
  };

  final WorkbenchRuntimeGateway _runtime;
  final WhiteboardDriftStore _store;
  final Future<UnifiedCardRepository> Function() _repositoryLoader;
  final WhiteboardWorkbenchSurfaceController _surfaceController;
  final WorkbenchActionAdd _addAction;
  final WorkbenchActionUpdate _updateAction;
  final WorkbenchActionReader _readActions;
  final WhiteboardPermissionBroker _permissionBroker;
  final DateTime Function() _clock;
  final Map<String, _UndoBinding> _undoBindings = {};
  final Set<String> _restoredCharacters = {};
  WhiteboardDomainCommandFacade? _domainCommandFacade;

  bool _running = false;
  String? _activeCharacterId;

  WhiteboardDomainCommandFacade get _domainCommands =>
      _domainCommandFacade ??= WhiteboardDomainCommandFacade(
        executor: WhiteboardDomainCommandExecutor.forDriftStore(
          permissionBroker: _permissionBroker,
          store: _store,
        ),
        permissionBroker: _permissionBroker,
        addAction: _addAction,
        updateAction: _updateAction,
        readActions: _readActions,
        runTransaction: _store.db.transaction,
        clock: _clock,
      );

  /// Direct user mutations and Runtime tool mutations converge on the same
  /// product-owned facade/executor. Callers cannot supply an alternate undo,
  /// receipt, permission, or hash-conflict implementation.
  Future<WhiteboardDomainCommandReceipt> executeUserDomainCommands({
    required String characterId,
    required WhiteboardDomainCommandBatch batch,
    required String userAuthorizationMessageId,
  }) =>
      _domainCommands.executeUser(
        characterId: characterId,
        batch: batch,
        userAuthorizationMessageId: userAuthorizationMessageId,
      );

  Future<WhiteboardDomainCommandReceipt> executeRuntimeDomainCommands({
    required String characterId,
    required WhiteboardDomainCommandBatch batch,
    required String authorizationId,
    required String runtimeTurnId,
    required String userAuthorizationMessageId,
  }) =>
      _domainCommands.executeRuntime(
        characterId: characterId,
        batch: batch,
        authorizationId: authorizationId,
        runtimeTurnId: runtimeTurnId,
        userAuthorizationMessageId: userAuthorizationMessageId,
      );

  WhiteboardAuthorizationGrant authorizeRuntimeDomainCommands({
    required WhiteboardDomainCommandBatch batch,
    required String runtimeTurnId,
    required String userAuthorizationMessageId,
    Set<WhiteboardWriteCapability>? authorizedCapabilities,
    int? maxOperationCount,
    Map<WhiteboardWriteCapability, int>? maxOperationCountByCapability,
  }) =>
      _domainCommands.authorizeRuntime(
        batch: batch,
        runtimeTurnId: runtimeTurnId,
        userAuthorizationMessageId: userAuthorizationMessageId,
        authorizedCapabilities: authorizedCapabilities,
        maxOperationCount: maxOperationCount,
        maxOperationCountByCapability: maxOperationCountByCapability,
      );

  Future<WhiteboardDomainCommandReceipt?> undoDomainCommands({
    required String characterId,
    required String actionId,
  }) async {
    final receipt = await _domainCommands.undo(
      characterId: characterId,
      actionId: actionId,
    );
    if (receipt?.status == WhiteboardDomainCommandStatus.undone) {
      await _reloadIfBoardOpen(receipt!.boardId);
    }
    return receipt;
  }

  bool matches(String text) {
    final normalized = text.trim();
    final directAction = RegExp(
      r'^(请|麻烦|帮我)?按主题分组并连线[。！!]?$',
    ).hasMatch(normalized);
    final explicitTarget = RegExp(
      r'(所选|选中|这些卡片|这几张|帮我把|请把|把这些|将这些)',
    ).hasMatch(normalized);
    final explicitSelectionAction = explicitTarget &&
        normalized.contains('连线') &&
        (normalized.contains('分组') || normalized.contains('整理'));
    return directAction || explicitSelectionAction;
  }

  bool canUndo(String actionId) =>
      _undoBindings.containsKey(actionId) || _domainCommands.canUndo(actionId);

  /// Hydrates the synchronous action-card availability check from the real
  /// persisted chat action stream. Both legacy group/connect actions and the
  /// provider-neutral domain-command actions are routed by [actionType].
  Future<void> hydrateUndo(String characterId) async {
    final normalized = characterId.trim();
    if (normalized.isEmpty) return;
    _activeCharacterId = normalized;
    if (_restoredCharacters.contains(normalized) &&
        _domainCommands.isRestored(normalized)) {
      return;
    }
    List<PersistedWorkbenchAction> actions;
    try {
      actions = await _readActions(normalized);
    } catch (_) {
      // Persistence failures fail closed. A later hydration call may retry.
      return;
    }
    _restoreLegacyUndoBindings(normalized, actions);
    await _domainCommands.restore(normalized, persistedActions: actions);
  }

  Future<bool> run({
    required String characterId,
    required String userText,
    required int userMessageId,
  }) async {
    final normalizedCharacterId = characterId.trim();
    if (normalizedCharacterId.isNotEmpty) {
      await hydrateUndo(normalizedCharacterId);
    }
    if (!matches(userText)) return false;
    final surface = _surfaceController.current;
    if (surface == null) {
      await _persistImmediateFailure(
        characterId: characterId,
        userMessageId: userMessageId,
        boardId: 'whiteboard_unavailable',
        selectedItemCount: 0,
        summary: '请先打开一个白板，再选择要整理的卡片。',
        errorCode: 'whiteboard_not_open',
      );
      return true;
    }
    if (_running) {
      await _persistImmediateFailure(
        characterId: characterId,
        userMessageId: userMessageId,
        boardId: surface.boardId,
        selectedItemCount: surface.selectedItemIds.length,
        summary: '上一项白板操作还在进行，请等它完成。',
        errorCode: 'whiteboard_action_busy',
      );
      return true;
    }
    if (surface.selectedItemIds.length < 2) {
      await _persistImmediateFailure(
        characterId: characterId,
        userMessageId: userMessageId,
        boardId: surface.boardId,
        selectedItemCount: surface.selectedItemIds.length,
        summary: '至少选择两张卡片，才能分组并建立连线。',
        errorCode: 'selection_too_small',
      );
      return true;
    }

    _running = true;
    try {
      await _runAuthorized(
        surface: surface,
        characterId: characterId,
        userText: userText,
        userMessageId: userMessageId,
      );
    } finally {
      _running = false;
    }
    return true;
  }

  Future<void> _runAuthorized({
    required WhiteboardWorkbenchSurface surface,
    required String characterId,
    required String userText,
    required int userMessageId,
  }) async {
    final actionId = StableId.generate('action').value;
    final createdAt = _clock().toUtc();
    var projection = WorkbenchActionProjection(
      actionId: actionId,
      actionType: 'whiteboard_group_and_connect',
      title: '整理所选卡片',
      status: WorkbenchActionStatus.running,
      boardId: surface.boardId,
      selectedItemCount: surface.selectedItemIds.length,
      summary: '正在读取所选卡片，并准备可撤销的整理方案。',
      tools: const [readToolName, writeToolName],
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    final actionMessageId = await _addAction(
      characterId,
      projection.summary,
      projection.toJson(),
    );

    String? sessionId;
    try {
      if (!await surface.flush()) {
        throw const _ProductActionFailure(
          'whiteboard_save_failed',
          '当前白板还没有保存成功，暂未执行整理。',
        );
      }
      final loaded = await _store.load(surface.boardId);
      if (!loaded.isSuccess || loaded.snapshot == null) {
        throw const _ProductActionFailure(
          'snapshot_unavailable',
          '当前白板快照不可恢复，暂未执行整理。',
        );
      }
      final repository = await _repositoryLoader();
      final readHost = WhiteboardAiReadToolHost(
        cards: repository,
        boards: _store,
        limits: WhiteboardAiReadLimits(
          maxBodyRunes: 2000,
          maxSerializedUtf8Bytes: 64 * 1024,
        ),
      );
      final writeHost = WhiteboardAiWriteToolHost.forDriftStore(
        permissionBroker: _permissionBroker,
        store: _store,
      );
      final session = await _runtime.startSession(
        dynamicTools: _dynamicTools,
        contextManifest: {
          'surface': 'whiteboard',
          'board_id': surface.boardId,
          'selected_item_ids': surface.selectedItemIds.toList()..sort(),
        },
      );
      sessionId = session.sessionId;
      projection = projection.copyWith(
        runtimeSessionId: session.sessionId,
        summary: '已连接电脑执行能力，正在形成整理方案。',
      );
      await _updateProjection(actionMessageId, projection);

      final turn = await _runtime.startTurn(
        session.sessionId,
        _runtimeInstruction(userText, surface),
      );
      final grant = _permissionBroker.issueSelectionAuthorization(
        runtimeTurnId: turn.turnId,
        userAuthorizationMessageId: 'chat-message-$userMessageId',
        boardId: surface.boardId,
        selectedItemIds: surface.selectedItemIds,
        capabilities: const {
          WhiteboardWriteCapability.groupSelection,
          WhiteboardWriteCapability.connectSelection,
        },
      );
      final operationBatchId = StableId.generate('batch').value;
      projection = projection.copyWith(
        runtimeTurnId: turn.turnId,
        operationBatchId: operationBatchId,
        authorizationId: grant.authorizationId,
        userAuthorizationMessageId: grant.userAuthorizationMessageId,
      );
      await _updateProjection(actionMessageId, projection);

      final receipt = await _driveTurn(
        sessionId: session.sessionId,
        runtimeTurnId: turn.turnId,
        surface: surface,
        repository: repository,
        readHost: readHost,
        writeHost: writeHost,
        authorizationId: grant.authorizationId,
        operationBatchId: operationBatchId,
      );
      if (receipt == null ||
          receipt.status != WhiteboardAiWriteStatus.applied) {
        final issue = receipt?.issues.isNotEmpty == true
            ? receipt!.issues.first.code
            : 'runtime_completed_without_write';
        throw _ProductActionFailure(
          issue,
          receipt?.status == WhiteboardAiWriteStatus.denied
              ? '这次整理超出了刚才选择的范围，因此没有执行。'
              : '没有得到可安全执行的整理结果，白板保持不变。',
        );
      }

      projection = projection.copyWith(
        status: WorkbenchActionStatus.completed,
        groupCount: receipt.operations
            .where((operation) => operation.operationKind.name == 'group')
            .length,
        edgeCount: receipt.operations
            .where((operation) => operation.operationKind.name == 'edge')
            .length,
        summary: '已完成分组和连线；可以查看详情，也可以整批撤销。',
        beforeSnapshotHash: receipt.beforeSnapshotHash,
        afterSnapshotHash: receipt.afterSnapshotHash,
        undoToken: receipt.undoToken,
        undoReceipt: receipt.toUndoReceiptEnvelope(
          beforeSnapshot: loaded.snapshot!,
        ),
      );
      writeHost.restoreUndoReceipt(
        receipt: receipt,
        beforeSnapshot: loaded.snapshot!,
      );
      _undoBindings[actionId] = _UndoBinding(
        messageId: actionMessageId,
        projection: projection,
        host: writeHost,
        runtimeTurnId: turn.turnId,
        undoToken: receipt.undoToken!,
        reload: () => _reloadIfBoardOpen(surface.boardId),
      );
      await _updateProjection(actionMessageId, projection);
      await surface.reload();
    } on _ProductActionFailure catch (error) {
      projection = projection.copyWith(
        status: WorkbenchActionStatus.failed,
        summary: error.userMessage,
        errorCode: error.code,
      );
      await _updateProjection(actionMessageId, projection);
    } on WorkbenchRuntimeException catch (error) {
      projection = projection.copyWith(
        status: WorkbenchActionStatus.failed,
        summary: error.code == 'experimental_runtime_disabled'
            ? '电脑执行能力尚未开启，白板没有发生变化。'
            : '电脑执行能力当前不可用，白板没有发生变化。',
        errorCode: _portableErrorCode(error.code),
      );
      await _updateProjection(actionMessageId, projection);
    } catch (_) {
      projection = projection.copyWith(
        status: WorkbenchActionStatus.failed,
        summary: '这次整理没有完成，白板保持原样。',
        errorCode: 'whiteboard_action_failed',
      );
      await _updateProjection(actionMessageId, projection);
    } finally {
      if (sessionId != null) {
        try {
          await _runtime.closeSession(sessionId);
        } catch (_) {
          // The product action is already terminal; provider cleanup is best
          // effort and cannot rewrite the user-visible result.
        }
      }
    }
  }

  Future<WhiteboardAiWriteReceipt?> _driveTurn({
    required String sessionId,
    required String runtimeTurnId,
    required WhiteboardWorkbenchSurface surface,
    required UnifiedCardRepository repository,
    required WhiteboardAiReadToolHost readHost,
    required WhiteboardAiWriteToolHost writeHost,
    required String authorizationId,
    required String operationBatchId,
  }) async {
    var cursor = 0;
    WhiteboardAiWriteReceipt? receipt;
    // Codex may need to exhaust its WebSocket retries before automatically
    // falling back to HTTPS. On affected Windows networks that transition is
    // observed at roughly 112 seconds, so a two-minute deadline interrupts
    // the first useful provider response before either dynamic tool can run.
    final deadline = _clock().toUtc().add(const Duration(minutes: 3));
    while (_clock().toUtc().isBefore(deadline)) {
      final batch = await _runtime.readEvents(sessionId, afterSequence: cursor);
      cursor = batch.nextSequence;
      for (final event in batch.events) {
        if (event['turn_id'] != runtimeTurnId) continue;
        final kind = event['kind'];
        final data = _asMap(event['data']);
        if (kind == 'tool_call') {
          final callId = _requiredId(data, 'tool_call_id');
          final toolName = _requiredId(data, 'tool_name');
          try {
            if (toolName == readToolName) {
              _requireNoArguments(data['arguments']);
              final readResult = await _readSelection(
                surface: surface,
                repository: repository,
                readHost: readHost,
              );
              await _runtime.respondToToolCall(
                toolCallId: callId,
                success: true,
                text: jsonEncode(readResult.toJson()),
              );
            } else if (toolName == writeToolName) {
              if (receipt != null) {
                throw const FormatException('write tool may be called once');
              }
              final plan = _parsePlan(data['arguments']);
              receipt = await writeHost.groupAndConnect(
                WhiteboardAiGroupAndConnectRequest(
                  operationBatchId: operationBatchId,
                  authorizationId: authorizationId,
                  runtimeTurnId: runtimeTurnId,
                  boardId: surface.boardId,
                  groups: plan.groups,
                  edges: plan.edges,
                ),
              );
              await _runtime.respondToToolCall(
                toolCallId: callId,
                success: receipt.succeeded,
                text: jsonEncode(receipt.toJson()),
              );
            } else {
              throw const FormatException('unknown product tool');
            }
          } catch (error) {
            await _runtime.respondToToolCall(
              toolCallId: callId,
              success: false,
              text: jsonEncode({
                'status': 'rejected',
                'code': error is FormatException
                    ? 'invalid_tool_arguments'
                    : 'tool_execution_failed',
              }),
            );
          }
        }
        if (kind == 'turn_status' &&
            _terminalStatuses.contains(event['status'])) {
          if (event['status'] != 'completed') {
            throw _ProductActionFailure(
              'runtime_${event['status']}',
              '电脑执行没有正常完成，白板保持不变。',
            );
          }
          return receipt;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    throw const _ProductActionFailure('runtime_timeout', '电脑执行等待超时，白板保持不变。');
  }

  Future<WhiteboardAiReadSnapshot> _readSelection({
    required WhiteboardWorkbenchSurface surface,
    required UnifiedCardRepository repository,
    required WhiteboardAiReadToolHost readHost,
  }) async {
    final loaded = await _store.load(surface.boardId);
    if (!loaded.isSuccess || loaded.snapshot == null) {
      throw StateError('whiteboard unavailable');
    }
    final selected = surface.selectedItemIds;
    final cardIds = loaded.snapshot!.boardItems
        .where((item) => selected.contains(item.itemId))
        .map((item) => item.cardId)
        .toSet();
    final sourceIds = <String>{};
    for (final cardId in cardIds) {
      final record = await repository.getCard(cardId, loadDocument: false);
      final sourceId = record?.card.sourceId;
      if (sourceId != null && sourceId.isNotEmpty) sourceIds.add(sourceId);
    }
    return readHost.readSelection(
      WhiteboardAiReadRequest(
        boardId: surface.boardId,
        cardIds: cardIds.toList()..sort(),
        sourceIds: sourceIds.toList()..sort(),
      ),
    );
  }

  void _restoreLegacyUndoBindings(
    String characterId,
    List<PersistedWorkbenchAction> actions,
  ) {
    if (_restoredCharacters.contains(characterId)) return;
    for (final persisted in actions) {
      try {
        final action = persisted.projection;
        if (_undoBindings.containsKey(action.actionId)) continue;
        if (action.status != WorkbenchActionStatus.completed) continue;
        if (action.actionType != 'whiteboard_group_and_connect') continue;
        if (action.undoToken == null ||
            action.undoReceipt == null ||
            action.runtimeTurnId == null ||
            action.operationBatchId == null ||
            action.afterSnapshotHash == null) {
          continue;
        }
        if (utf8.encode(jsonEncode(action.undoReceipt)).length >
            WhiteboardAiWriteToolHost.hardMaxUndoEnvelopeUtf8Bytes) {
          continue;
        }
        final beforeSnapshot = _undoReceiptBeforeSnapshot(action.undoReceipt!);
        if (beforeSnapshot == null) continue;
        final receipt = _restoreReceiptFromProjection(
          action: action,
          actionUndoReceipt: action.undoReceipt!,
        );
        if (receipt == null ||
            receipt.status != WhiteboardAiWriteStatus.applied ||
            receipt.operationBatchId != action.operationBatchId ||
            receipt.runtimeTurnId != action.runtimeTurnId ||
            receipt.boardId != action.boardId ||
            receipt.undoToken != action.undoToken ||
            receipt.beforeSnapshotHash != action.beforeSnapshotHash ||
            receipt.afterSnapshotHash != action.afterSnapshotHash) {
          continue;
        }
        final host = WhiteboardAiWriteToolHost.forDriftStore(
          permissionBroker: _permissionBroker,
          store: _store,
        );
        host.restoreUndoReceipt(
          receipt: receipt,
          beforeSnapshot: beforeSnapshot,
        );
        _undoBindings[action.actionId] = _UndoBinding(
          messageId: persisted.messageId,
          projection: action,
          host: host,
          runtimeTurnId: action.runtimeTurnId!,
          undoToken: action.undoToken!,
          reload: () => _reloadIfBoardOpen(action.boardId),
        );
      } catch (_) {
        // Malformed or oversized historical records fail closed independently.
      }
    }
    _restoredCharacters.add(characterId);
  }

  Future<void> _reloadIfBoardOpen(String boardId) async {
    final surface = _surfaceController.current;
    if (surface != null && surface.boardId == boardId) {
      await surface.reload();
    }
  }

  Future<void> undo(String actionId) async {
    final characterId = _activeCharacterId ?? 'i';
    await hydrateUndo(characterId);
    final binding = _undoBindings[actionId];
    if (binding == null) {
      await undoDomainCommands(
        characterId: characterId,
        actionId: actionId,
      );
      return;
    }
    final activeSurface = _surfaceController.current;
    final activeBoardSurface = activeSurface != null &&
            activeSurface.boardId == binding.projection.boardId
        ? activeSurface
        : null;
    if (activeBoardSurface != null && !await activeBoardSurface.flush()) {
      final updated = binding.projection.copyWith(
        summary: '当前白板还没有保存成功，暂时不能安全撤销。',
        errorCode: 'undo_flush_failed',
      );
      await _updateProjection(binding.messageId, updated);
      return;
    }
    final receipt = await binding.host.undo(
      WhiteboardAiUndoRequest(
        undoToken: binding.undoToken,
        runtimeTurnId: binding.runtimeTurnId,
      ),
    );
    if (receipt.status == WhiteboardAiWriteStatus.undone) {
      final currentSurface = _surfaceController.current;
      if (currentSurface != null &&
          currentSurface.boardId == binding.projection.boardId) {
        await currentSurface.reload();
      } else {
        await binding.reload();
      }
      final restoredSurface = _surfaceController.current;
      if (restoredSurface != null &&
          restoredSurface.boardId == binding.projection.boardId &&
          !await restoredSurface.flush()) {
        final updated = binding.projection.copyWith(
          summary: '撤销结果没有保存成功，请保持白板打开并重试。',
          errorCode: 'undo_restore_flush_failed',
        );
        await _updateProjection(binding.messageId, updated);
        return;
      }
      final updated = binding.projection.copyWith(
        status: WorkbenchActionStatus.undone,
        summary: '已撤销这次分组和连线，白板恢复到执行前。',
      );
      _undoBindings.remove(actionId);
      await _updateProjection(binding.messageId, updated);
      return;
    }
    final updated = binding.projection.copyWith(
      summary: receipt.status == WhiteboardAiWriteStatus.conflict
          ? '白板在这次整理后又有变化。请先撤销或恢复后续改动，再重试本次撤销。'
          : '这次撤销暂时没有完成，可以稍后重试。',
      errorCode: receipt.issues.isEmpty
          ? 'undo_failed'
          : _portableErrorCode(receipt.issues.first.code),
    );
    final retryable = receipt.status == WhiteboardAiWriteStatus.conflict ||
        receipt.status == WhiteboardAiWriteStatus.unavailable;
    if (!retryable) _undoBindings.remove(actionId);
    await _updateProjection(binding.messageId, updated);
  }

  Future<void> _persistImmediateFailure({
    required String characterId,
    required int userMessageId,
    required String boardId,
    required int selectedItemCount,
    required String summary,
    required String errorCode,
  }) async {
    final now = _clock().toUtc();
    final projection = WorkbenchActionProjection(
      actionId: StableId.generate('action').value,
      actionType: 'whiteboard_group_and_connect',
      title: '整理所选卡片',
      status: WorkbenchActionStatus.failed,
      boardId: boardId,
      selectedItemCount: selectedItemCount,
      summary: summary,
      userAuthorizationMessageId: 'chat-message-$userMessageId',
      errorCode: errorCode,
      tools: const [readToolName, writeToolName],
      createdAt: now,
      updatedAt: now,
    );
    await _addAction(characterId, summary, projection.toJson());
  }

  Future<void> _updateProjection(
    int messageId,
    WorkbenchActionProjection projection,
  ) =>
      _updateAction(messageId, projection.summary, projection.toJson());

  static String _runtimeInstruction(
    String userText,
    WhiteboardWorkbenchSurface surface,
  ) {
    final ids = surface.selectedItemIds.toList()..sort();
    return '''你正在协助 Here I am 白板完成一次受限操作。
用户要求：${userText.trim()}
白板：${surface.boardId}
允许处理的所选 item_id：${ids.join(', ')}

必须先调用 $readToolName 获取受限快照，再调用 $writeToolName 一次。
写工具只接受 groups 和 edges。不要猜测、改写或提交 board_id、授权、批次号；这些由产品宿主管理。
groups 必须完整划分以上选择：每个所选 item_id 必须且只能出现一次，不能遗漏，也不能加入选择之外的 item_id。
每个组至少两个所选 item；若无法把全部选择拆成多个各含至少两个 item 的主题组，就把全部所选 item 放进一个较宽泛的组。连线端点只能来自以上 item_id。''';
  }

  static const List<Map<String, dynamic>> _dynamicTools = [
    {
      'name': readToolName,
      'description': '读取当前白板中用户已选择卡片的受限快照。',
      'input_schema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    {
      'name': writeToolName,
      'description':
          '对当前选择创建分组和连线；groups 必须完整划分选择，每个所选 item_id 恰好出现一次。范围和授权由产品宿主管理。',
      'input_schema': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['groups', 'edges'],
        'properties': {
          'groups': {
            'type': 'array',
            'maxItems': 16,
            'items': {
              'type': 'object',
              'additionalProperties': false,
              'required': ['name', 'item_ids'],
              'properties': {
                'name': {'type': 'string', 'maxLength': 120},
                'item_ids': {
                  'type': 'array',
                  'minItems': 2,
                  'maxItems': 64,
                  'items': {'type': 'string'},
                },
              },
            },
          },
          'edges': {
            'type': 'array',
            'maxItems': 32,
            'items': {
              'type': 'object',
              'additionalProperties': false,
              'required': ['from_item_id', 'to_item_id'],
              'properties': {
                'from_item_id': {'type': 'string'},
                'to_item_id': {'type': 'string'},
                'direction': {
                  'type': 'string',
                  'enum': ['undirected', 'directed'],
                },
                'semantic_type': {'type': 'string', 'maxLength': 64},
                'label': {'type': 'string', 'maxLength': 200},
              },
            },
          },
        },
      },
    },
  ];
}

WhiteboardAiWriteReceipt? _restoreReceiptFromProjection({
  required WorkbenchActionProjection action,
  required Map<String, dynamic> actionUndoReceipt,
}) {
  try {
    final receiptMap = Map<String, dynamic>.from(actionUndoReceipt)
      ..remove('before_snapshot');
    return WhiteboardAiWriteReceipt.fromJson({
      ...receiptMap,
      'runtime_turn_id':
          action.runtimeTurnId ?? actionUndoReceipt['runtime_turn_id'],
      'board_id': action.boardId,
      'operation_batch_id':
          action.operationBatchId ?? actionUndoReceipt['operation_batch_id'],
    });
  } catch (_) {
    return null;
  }
}

WhiteboardSnapshot? _undoReceiptBeforeSnapshot(
  Map<String, dynamic> actionUndoReceipt,
) {
  final rawBefore = actionUndoReceipt['before_snapshot'];
  if (rawBefore is! Map) return null;
  try {
    return WhiteboardSnapshot.fromJson(Map<String, dynamic>.from(rawBefore));
  } catch (_) {
    return null;
  }
}

class _UndoBinding {
  const _UndoBinding({
    required this.messageId,
    required this.projection,
    required this.host,
    required this.runtimeTurnId,
    required this.undoToken,
    required this.reload,
  });

  final int messageId;
  final WorkbenchActionProjection projection;
  final WhiteboardAiWriteToolHost host;
  final String runtimeTurnId;
  final String undoToken;
  final Future<void> Function() reload;
}

class _ParsedPlan {
  const _ParsedPlan(this.groups, this.edges);
  final List<WhiteboardAiGroupPlan> groups;
  final List<WhiteboardAiEdgePlan> edges;
}

class _ProductActionFailure implements Exception {
  const _ProductActionFailure(this.code, this.userMessage);
  final String code;
  final String userMessage;
}

_ParsedPlan _parsePlan(Object? value) {
  final map = _asMap(value);
  _requireExactKeys(map, const {'groups', 'edges'});
  final rawGroups = _asList(map['groups']);
  final rawEdges = _asList(map['edges']);
  if (rawGroups.length > 16 || rawEdges.length > 32) {
    throw const FormatException('plan exceeds bounds');
  }
  final groups = <WhiteboardAiGroupPlan>[];
  for (final raw in rawGroups) {
    final group = _asMap(raw);
    _requireExactKeys(group, const {'name', 'item_ids'});
    final name = _requiredText(group, 'name');
    final ids = _asList(group['item_ids']).map((id) {
      if (id is! String) throw const FormatException('item id required');
      return _validateId(id);
    }).toList(growable: false);
    groups.add(WhiteboardAiGroupPlan(name: name, itemIds: ids));
  }
  final edges = <WhiteboardAiEdgePlan>[];
  for (final raw in rawEdges) {
    final edge = _asMap(raw);
    _requireAllowedKeys(
      edge,
      const {
        'from_item_id',
        'to_item_id',
        'direction',
        'semantic_type',
        'label',
      },
      required: const {'from_item_id', 'to_item_id'},
    );
    edges.add(
      WhiteboardAiEdgePlan(
        fromItemId: _requiredId(edge, 'from_item_id'),
        toItemId: _requiredId(edge, 'to_item_id'),
        direction: switch (edge['direction']) {
          null || 'undirected' => EdgeDirection.undirected,
          'directed' => EdgeDirection.directed,
          _ => throw const FormatException('invalid edge direction'),
        },
        semanticType: _optionalText(edge['semantic_type']),
        label: _optionalText(edge['label']),
      ),
    );
  }
  if (groups.isEmpty && edges.isEmpty) {
    throw const FormatException('empty write plan');
  }
  return _ParsedPlan(groups, edges);
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is! Map) throw const FormatException('object required');
  return Map<String, dynamic>.from(value);
}

List<Object?> _asList(Object? value) {
  if (value is! List) throw const FormatException('array required');
  return List<Object?>.from(value);
}

void _requireNoArguments(Object? value) {
  final map = _asMap(value);
  if (map.isNotEmpty) throw const FormatException('no arguments allowed');
}

void _requireExactKeys(Map<String, dynamic> map, Set<String> keys) {
  _requireAllowedKeys(map, keys, required: keys);
}

void _requireAllowedKeys(
  Map<String, dynamic> map,
  Set<String> allowed, {
  required Set<String> required,
}) {
  if (map.keys.any((key) => !allowed.contains(key)) ||
      required.any((key) => !map.containsKey(key))) {
    throw const FormatException('unexpected object shape');
  }
}

String _requiredId(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! String) throw FormatException('$key must be a string');
  return _validateId(value);
}

String _validateId(String value) {
  if (value.isEmpty ||
      value.length > 256 ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$').hasMatch(value)) {
    throw const FormatException('invalid stable id');
  }
  return value;
}

String _requiredText(Map<String, dynamic> map, String key) {
  final value = _optionalText(map[key]);
  if (value == null) throw FormatException('$key is required');
  return value;
}

String? _optionalText(Object? value) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty || value.runes.length > 200) {
    throw const FormatException('invalid bounded text');
  }
  return value.trim();
}

String _portableErrorCode(String value) {
  final normalized = value.replaceAll(RegExp(r'[^A-Za-z0-9._:-]'), '_');
  return normalized.isEmpty
      ? 'runtime_error'
      : normalized.substring(
          0,
          normalized.length > 120 ? 120 : normalized.length,
        );
}
