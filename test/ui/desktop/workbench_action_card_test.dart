import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/workbench_ai/action/workbench_action_projection.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/desktop/widgets/desktop_persona_chat_view.dart';
import 'package:memex/ui/desktop/widgets/workbench_action_card.dart';

void main() {
  testWidgets('shows auditable details and invokes whole-action undo',
      (tester) async {
    final now = DateTime.utc(2026, 8, 21);
    final action = WorkbenchActionProjection(
      actionId: 'action_1',
      actionType: 'whiteboard_group_and_connect',
      title: '整理所选卡片',
      status: WorkbenchActionStatus.completed,
      boardId: 'board_1',
      selectedItemCount: 4,
      groupCount: 2,
      edgeCount: 1,
      summary: '已完成分组和连线。',
      operationBatchId: 'batch_1',
      authorizationId: 'auth_1',
      undoToken: 'undo_1',
      tools: const [
        'whiteboard_read_selection',
        'whiteboard_group_and_connect',
      ],
      createdAt: now,
      updatedAt: now,
    );
    String? undone;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 350,
            child: WorkbenchActionCard(
              action: action,
              undoAvailable: true,
              onUndo: (actionId) async => undone = actionId,
            ),
          ),
        ),
      ),
    );

    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('4 项 · 2 组 · 1 条连线'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('workbench_action_details_action_1')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workbench_action_detail_drawer')),
      findsOneWidget,
    );
    expect(find.text('batch_1'), findsOneWidget);
    expect(find.text('auth_1'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('workbench_action_detail_close')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('workbench_action_undo_action_1')),
    );
    await tester.pump();
    expect(undone, 'action_1');
  });

  testWidgets('desktop chat exposes hydrated undo for a domain action addendum',
      (tester) async {
    final now = DateTime.utc(2026, 8, 21);
    final action = WorkbenchActionProjection(
      actionId: 'action_chat',
      actionType: 'whiteboard_domain_commands',
      title: '白板卡片操作',
      status: WorkbenchActionStatus.completed,
      boardId: 'board_1',
      selectedItemCount: 2,
      groupCount: 1,
      edgeCount: 1,
      summary: '白板卡片操作已完成，可撤销。',
      undoToken: 'undo_1',
      createdAt: now,
      updatedAt: now,
    );
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 350,
          height: 480,
          child: DesktopPersonaChatView(
            loading: false,
            messagesNewestFirst: [
              PersonaChatMessage(
                id: 1,
                characterId: 'i',
                isFromCharacter: true,
                content: action.summary,
                isRead: true,
                timestamp: now,
                messageType: 'action',
                attachmentsJson: jsonEncode([
                  {'type': 'workbench_action', 'action': action.toJson()},
                ]),
              ),
            ],
            isStreaming: false,
            streamingText: '',
            controller: controller,
            composerFocusNode: focusNode,
            scrollController: scrollController,
            onSend: () async {},
            canUndoWorkbenchAction: (_) => true,
            onUndoWorkbenchAction: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('workbench_action_action_chat')),
      findsOneWidget,
    );
    expect(find.text('已完成'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workbench_action_undo_action_chat')),
      findsOneWidget,
    );
  });
}
