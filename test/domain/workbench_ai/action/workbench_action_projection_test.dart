import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/workbench_ai/action/workbench_action_projection.dart';

void main() {
  test('round-trips the strict action addendum contract', () {
    final createdAt = DateTime.utc(2026, 8, 21, 10);
    final action = WorkbenchActionProjection(
      actionId: 'action_1',
      actionType: 'whiteboard_group_and_connect',
      title: '整理所选卡片',
      status: WorkbenchActionStatus.completed,
      boardId: 'board_1',
      selectedItemCount: 4,
      groupCount: 2,
      edgeCount: 1,
      summary: '已完成。',
      runtimeSessionId: 'session_1',
      runtimeTurnId: 'turn_1',
      operationBatchId: 'batch_1',
      authorizationId: 'auth_1',
      userAuthorizationMessageId: 'chat-message-7',
      beforeSnapshotHash: List.filled(64, 'a').join(),
      afterSnapshotHash: List.filled(64, 'b').join(),
      undoToken: 'undo_1',
      undoReceipt: {
        'schema_version': 1,
        'status': 'applied',
        'operation_batch_id': 'batch_1',
        'runtime_turn_id': 'turn_1',
        'board_id': 'board_1',
      },
      tools: const [
        'whiteboard_read_selection',
        'whiteboard_group_and_connect',
      ],
      createdAt: createdAt,
      updatedAt: createdAt.add(const Duration(seconds: 2)),
    );

    final decoded = WorkbenchActionProjection.fromJson(action.toJson());

    expect(decoded.actionId, action.actionId);
    expect(decoded.status, WorkbenchActionStatus.completed);
    expect(decoded.undoToken, 'undo_1');
    expect(decoded.undoReceipt, isNotNull);
    expect(decoded.tools, action.tools);
    expect(decoded.toJson(), action.toJson());
  });

  test('rejects unknown addendum fields instead of silently trusting them', () {
    final now = DateTime.utc(2026, 8, 21);
    final json = WorkbenchActionProjection(
      actionId: 'action_1',
      actionType: 'whiteboard_group_and_connect',
      title: '整理所选卡片',
      status: WorkbenchActionStatus.running,
      boardId: 'board_1',
      selectedItemCount: 2,
      summary: '进行中。',
      createdAt: now,
      updatedAt: now,
    ).toJson()
      ..['raw_provider_log'] = 'must not be accepted';

    expect(
      () => WorkbenchActionProjection.fromJson(json),
      throwsFormatException,
    );
  });
}
