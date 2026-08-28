library;

import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/whiteboard/domain_commands/whiteboard_domain_command_executor.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/data/workbench_ai/whiteboard_workbench_coordinator.dart';
import 'package:memex/data/workbench_ai/whiteboard_workbench_surface.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/domain_command.dart';
import 'package:memex/domain/whiteboard/domain_command_receipt.dart';
import 'package:memex/utils/user_storage.dart';

typedef WhiteboardCharacterIdResolver = Future<String?> Function();

/// Product host for direct whiteboard edits.
///
/// The canvas may preview a high-frequency gesture locally. Its commit point
/// enters here, where the visible surface, persisted baseline hash, audit
/// evidence, Receipt and persistent Undo all converge on the same Domain
/// facade used by Runtime tools.
class WhiteboardManualDomainCommandHost {
  WhiteboardManualDomainCommandHost({
    required WhiteboardDriftStore store,
    required WhiteboardWorkbenchCoordinator coordinator,
    required WhiteboardWorkbenchSurfaceController surfaceController,
    required WhiteboardCharacterIdResolver resolveCharacterId,
    DateTime Function()? clock,
  })  : _store = store,
        _coordinator = coordinator,
        _surfaceController = surfaceController,
        _resolveCharacterId = resolveCharacterId,
        _clock = clock ?? (() => DateTime.now().toUtc());

  factory WhiteboardManualDomainCommandHost.production() =>
      WhiteboardManualDomainCommandHost(
        store: WhiteboardDriftStore(AppDatabase.instance),
        coordinator: WhiteboardWorkbenchCoordinator.instance,
        surfaceController: WhiteboardWorkbenchSurfaceController.instance,
        resolveCharacterId: () async {
          final userId = await UserStorage.getUserId();
          if (userId == null) return null;
          return (await CharacterService.instance.getPrimaryCompanion(userId))
              ?.id;
        },
      );

  final WhiteboardDriftStore _store;
  final WhiteboardWorkbenchCoordinator _coordinator;
  final WhiteboardWorkbenchSurfaceController _surfaceController;
  final WhiteboardCharacterIdResolver _resolveCharacterId;
  final DateTime Function() _clock;

  Future<WhiteboardDomainCommandReceipt> execute({
    required Object surfaceOwner,
    required String boardId,
    required String operationBatchId,
    required List<WhiteboardDomainCommand> commands,
  }) async {
    final surface = _surfaceController.current;
    if (surface == null ||
        !identical(surface.owner, surfaceOwner) ||
        surface.boardId != boardId) {
      return _failure(
        operationBatchId: operationBatchId,
        boardId: boardId,
        commands: commands,
        code: 'whiteboard_surface_changed',
      );
    }
    surface.setInteractionLocked(true);
    try {
      final characterId = (await _resolveCharacterId())?.trim();
      if (characterId == null || characterId.isEmpty) {
        return _failure(
          operationBatchId: operationBatchId,
          boardId: boardId,
          commands: commands,
          code: 'whiteboard_character_unavailable',
        );
      }
      final loaded = await _store.load(boardId);
      if (!loaded.isSuccess || loaded.snapshot == null) {
        return _failure(
          operationBatchId: operationBatchId,
          boardId: boardId,
          commands: commands,
          code: 'snapshot_unavailable',
        );
      }
      final current = _surfaceController.current;
      if (current == null ||
          !identical(current.owner, surfaceOwner) ||
          current.boardId != boardId) {
        return _failure(
          operationBatchId: operationBatchId,
          boardId: boardId,
          commands: commands,
          code: 'whiteboard_surface_changed',
        );
      }
      final batch = WhiteboardDomainCommandBatch(
        operationBatchId: operationBatchId,
        boardId: boardId,
        expectedSnapshotHash:
            WhiteboardDomainCommandExecutor.snapshotHash(loaded.snapshot!),
        commands: List.unmodifiable(commands),
      );
      return await _coordinator.executeUserDomainCommands(
        characterId: characterId,
        batch: batch,
        userAuthorizationMessageId: 'ui-action:$operationBatchId',
      );
    } catch (_) {
      return _failure(
        operationBatchId: operationBatchId,
        boardId: boardId,
        commands: commands,
        code: 'whiteboard_manual_command_failed',
      );
    } finally {
      final current = _surfaceController.current;
      if (current != null &&
          identical(current.owner, surfaceOwner) &&
          current.boardId == boardId) {
        try {
          await current.reload();
        } catch (_) {
          // The persisted receipt remains authoritative. The route surfaces
          // refresh failures separately and can retry without re-executing.
        }
      }
      try {
        surface.setInteractionLocked(false);
      } catch (_) {
        // A disposed/switching surface cannot invalidate a committed receipt.
      }
    }
  }

  WhiteboardDomainCommandReceipt _failure({
    required String operationBatchId,
    required String boardId,
    required List<WhiteboardDomainCommand> commands,
    required String code,
  }) =>
      WhiteboardDomainCommandReceipt(
        status: WhiteboardDomainCommandStatus.unavailable,
        operationBatchId: operationBatchId,
        boardId: boardId,
        commandIds: commands.map((command) => command.commandId).toList(),
        summary: code,
        issues: [WhiteboardDomainCommandIssue(code)],
        occurredAt: _clock().toUtc(),
      );
}
