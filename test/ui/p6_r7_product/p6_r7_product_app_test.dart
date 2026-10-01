import 'dart:async';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/workbench_ai/candidate/p6_r7_candidate_session_resources.dart';
import 'package:memex/data/workbench_ai/product/workbench_product_chat_store.dart';
import 'package:memex/data/workbench_ai/product/workbench_task_product_close.dart';
import 'package:memex/data/workbench_ai/workbench_conversation_coordinator.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/p6_r7_product/view_models/p6_r7_product_chat_view_model.dart';
import 'package:memex/ui/p6_r7_product/widgets/p6_r7_product_app.dart';

void main() {
  testWidgets(
      'unknown conversation close keeps root and Store; confirmed retry closes in order',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    // Open Drift's executor in real async time before the widget subscription
    // can begin opening it inside Flutter's fake clock.
    await tester.runAsync(() => db.customSelect('SELECT 1').get());
    final chat = _StaticChatStore(db);
    final vm = P6R7ProductChatViewModel(
        store: chat,
        conversationId: 'synthetic',
        coordinator: WorkbenchConversationCoordinator(
            runtime: _NoRuntime(), addReply: chat.addCharacterMessage));
    final steps = <String>[];
    final gate = Completer<bool>();
    var attempts = 0;
    Future<void>? quiesce;
    final resources = P6R7CandidateSessionResources(drainExecution: () async {
      steps.add('tails');
    }, closeStore: () async {
      steps.add('store');
      await db.close();
    }, closeClient: () {
      steps.add('client');
    });
    final close = WorkbenchTaskProductClose(
        fenceNewWork: () {
          steps.add('fence');
          quiesce = vm.quiesce();
        },
        closeConversation: () async {
          steps.add('conversation');
          if (++attempts == 1) return gate.future;
          await quiesce;
          return true;
        },
        joinQueueInvocations: () async {
          steps.add('join');
        },
        closeQueue: () async {
          steps.add('queue');
          return true;
        },
        closeOwnedHost: () async {
          steps.add('host');
          return true;
        },
        closeResources: resources.close,
        recordAppClosed: () async {
          steps.add('witness');
          return true;
        });
    final key = GlobalKey<P6R7ProductAppState>();
    await tester
        .pumpWidget(P6R7ProductApp(key: key, viewModel: vm, close: close));
    await tester.pump();
    final pending = key.currentState!.didRequestAppExit();
    await tester.pump();
    expect(find.text('正在等待对话与任务安全关闭…'), findsOneWidget);
    expect(vm.acceptsNewTurns, isFalse);
    gate.complete(false);
    expect(await pending, ui.AppExitResponse.cancel);
    await tester.pump();
    expect(find.text('关闭尚未确认，窗口已保留。请稍后再次关闭。'), findsOneWidget);
    expect(steps, ['fence', 'conversation']);
    expect(await tester.runAsync(() => db.select(db.taskRooms).get()), isEmpty);
    expect(await tester.runAsync(() => key.currentState!.didRequestAppExit()),
        ui.AppExitResponse.exit);
    expect(steps, [
      'fence',
      'conversation',
      'conversation',
      'join',
      'queue',
      'host',
      'tails',
      'store',
      'client',
      'witness'
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _NoRuntime implements WorkbenchConversationRuntimeGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No runtime calls allowed');
}

class _StaticChatStore extends WorkbenchProductChatStore {
  _StaticChatStore(AppDatabase db)
      : super(database: db, conversationId: 'synthetic');

  @override
  Stream<List<PersonaChatMessage>> watchMessages({int limit = 100}) =>
      Stream.value(const []);
}
