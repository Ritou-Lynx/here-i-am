import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/workbench_ai/permissions/whiteboard_permission_broker.dart';

void main() {
  final now = DateTime.utc(2026, 8, 21, 12);

  WhiteboardPermissionBroker broker({
    DateTime Function()? clock,
  }) {
    var id = 0;
    return WhiteboardPermissionBroker(
      clock: clock ?? (() => now),
      authorizationIdFactory: () => 'auth_${++id}',
    );
  }

  test('issues a scoped grant and reserves only the exact selection', () {
    final subject = broker();
    final grant = subject.issueSelectionAuthorization(
      runtimeTurnId: 'turn_1',
      userAuthorizationMessageId: 'message_1',
      boardId: 'board_1',
      selectedItemIds: {'item_1', 'item_2'},
      capabilities: {
        WhiteboardWriteCapability.groupSelection,
        WhiteboardWriteCapability.connectSelection,
      },
    );

    final allowed = subject.reserve(
      authorizationId: grant.authorizationId,
      operationBatchId: 'batch_1',
      runtimeTurnId: 'turn_1',
      boardId: 'board_1',
      targetItemIds: {'item_1', 'item_2'},
      requiredCapabilities: {
        WhiteboardWriteCapability.groupSelection,
      },
      operationCount: 3,
    );
    expect(allowed.allowed, isTrue);
    expect(
      allowed.grant!.toAuditJson()['user_authorization_message_id'],
      'message_1',
    );

    final outsideScope = subject.reserve(
      authorizationId: grant.authorizationId,
      operationBatchId: 'batch_1',
      runtimeTurnId: 'turn_1',
      boardId: 'board_1',
      targetItemIds: {'item_3'},
      requiredCapabilities: {
        WhiteboardWriteCapability.groupSelection,
      },
      operationCount: 1,
    );
    expect(outsideScope.allowed, isFalse);
    expect(
      outsideScope.code,
      WhiteboardPermissionDecisionCode.targetOutsideSelection,
    );
  });

  test('denies capability, board, turn, busy, consumed, and expired grants',
      () {
    var current = now;
    final subject = broker(clock: () => current);
    final grant = subject.issueSelectionAuthorization(
      runtimeTurnId: 'turn_1',
      userAuthorizationMessageId: 'message_1',
      boardId: 'board_1',
      selectedItemIds: {'item_1'},
      capabilities: {WhiteboardWriteCapability.groupSelection},
    );

    WhiteboardPermissionDecision decide({
      String batch = 'batch_1',
      String turn = 'turn_1',
      String board = 'board_1',
      Set<WhiteboardWriteCapability> capabilities = const {
        WhiteboardWriteCapability.groupSelection,
      },
    }) {
      return subject.reserve(
        authorizationId: grant.authorizationId,
        operationBatchId: batch,
        runtimeTurnId: turn,
        boardId: board,
        targetItemIds: {'item_1'},
        requiredCapabilities: capabilities,
        operationCount: 1,
      );
    }

    expect(
      decide(
        capabilities: {WhiteboardWriteCapability.connectSelection},
      ).code,
      WhiteboardPermissionDecisionCode.capabilityDenied,
    );
    expect(
      decide(board: 'board_2').code,
      WhiteboardPermissionDecisionCode.boardMismatch,
    );
    expect(
      decide(turn: 'turn_2').code,
      WhiteboardPermissionDecisionCode.runtimeTurnMismatch,
    );
    expect(decide().allowed, isTrue);
    expect(
      decide(batch: 'batch_2').code,
      WhiteboardPermissionDecisionCode.authorizationBusy,
    );
    expect(
      subject.commit(
        authorizationId: grant.authorizationId,
        operationBatchId: 'batch_1',
      ),
      isTrue,
    );
    expect(
      decide().code,
      WhiteboardPermissionDecisionCode.authorizationConsumed,
    );

    final expiring = subject.issueSelectionAuthorization(
      runtimeTurnId: 'turn_2',
      userAuthorizationMessageId: 'message_2',
      boardId: 'board_1',
      selectedItemIds: {'item_1'},
      capabilities: {WhiteboardWriteCapability.groupSelection},
    );
    current = now.add(const Duration(minutes: 16));
    expect(
      subject
          .reserve(
            authorizationId: expiring.authorizationId,
            operationBatchId: 'batch_3',
            runtimeTurnId: 'turn_2',
            boardId: 'board_1',
            targetItemIds: {'item_1'},
            requiredCapabilities: {
              WhiteboardWriteCapability.groupSelection,
            },
            operationCount: 1,
          )
          .code,
      WhiteboardPermissionDecisionCode.authorizationExpired,
    );
  });

  test('release permits retry but operation and selection ceilings are hard',
      () {
    final subject = broker();
    final grant = subject.issueSelectionAuthorization(
      runtimeTurnId: 'turn_1',
      userAuthorizationMessageId: 'message_1',
      boardId: 'board_1',
      selectedItemIds: {'item_1'},
      capabilities: {WhiteboardWriteCapability.groupSelection},
      maxOperationCount: 2,
    );
    final first = subject.reserve(
      authorizationId: grant.authorizationId,
      operationBatchId: 'batch_1',
      runtimeTurnId: 'turn_1',
      boardId: 'board_1',
      targetItemIds: {'item_1'},
      requiredCapabilities: {WhiteboardWriteCapability.groupSelection},
      operationCount: 2,
    );
    expect(first.allowed, isTrue);
    subject.release(
      authorizationId: grant.authorizationId,
      operationBatchId: 'batch_1',
    );
    expect(
      subject
          .reserve(
            authorizationId: grant.authorizationId,
            operationBatchId: 'batch_1',
            runtimeTurnId: 'turn_1',
            boardId: 'board_1',
            targetItemIds: {'item_1'},
            requiredCapabilities: {
              WhiteboardWriteCapability.groupSelection,
            },
            operationCount: 2,
          )
          .allowed,
      isTrue,
    );
    subject.release(
      authorizationId: grant.authorizationId,
      operationBatchId: 'batch_1',
    );
    expect(
      subject
          .reserve(
            authorizationId: grant.authorizationId,
            operationBatchId: 'batch_1',
            runtimeTurnId: 'turn_1',
            boardId: 'board_1',
            targetItemIds: {'item_1'},
            requiredCapabilities: {
              WhiteboardWriteCapability.groupSelection,
            },
            operationCount: 3,
          )
          .code,
      WhiteboardPermissionDecisionCode.operationLimitExceeded,
    );
  });
}
