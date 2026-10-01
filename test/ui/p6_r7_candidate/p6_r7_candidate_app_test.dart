import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/workbench_ai/candidate/p6_r7_candidate_session_resources.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_runtime_task_queue_tool.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_lifecycle_owner.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/p6_r7_candidate/view_models/p6_r7_candidate_view_model.dart';
import 'package:memex/ui/p6_r7_candidate/widgets/p6_r7_candidate_app.dart';

void main() {
  late AppDatabase db;
  late WorkbenchTaskQueueLifecycleOwner owner;
  late _LifecycleProbe probe;
  late P6R7CandidateViewModel viewModel;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final service = TaskRoomService(db: db);
    owner = WorkbenchTaskQueueLifecycleOwner();
    probe = _LifecycleProbe();
    owner.register(probe);
    viewModel = P6R7CandidateViewModel(
      tool: WorkbenchRuntimeTaskQueueTool(loadService: () async => service),
      service: service,
      lifecycleOwner: owner,
      conversationId: 'p6-r7-widget',
      initialTaskId: null,
      persistTaskId: (_) async {},
    );
  });

  tearDown(() async => db.close());

  testWidgets('session close follows host and waits for the remaining monitor',
      (tester) async {
    final host = Completer<bool>();
    final monitor = Completer<void>();
    final calls = <String>[];
    probe.onClose = () async {
      calls.add('owner');
      return true;
    };
    final resources = P6R7CandidateSessionResources(
      drainExecution: () {
        calls.add('monitor');
        return monitor.future;
      },
      closeStore: () async {
        calls.add('store');
      },
      closeClient: () => calls.add('client'),
    );
    await tester.pumpWidget(P6R7CandidateApp(
      viewModel: viewModel,
      lifecycleOwner: owner,
      closeOwnedHost: () {
        calls.add('host');
        return host.future;
      },
      closeSession: resources.close,
    ));
    final exit = tester.binding.handleRequestAppExit();
    var completed = false;
    exit.then((_) => completed = true);
    await tester.pump();
    expect(calls, ['owner', 'host']);
    host.complete(true);
    await tester.pump();
    expect(calls, ['owner', 'host', 'monitor']);
    expect(completed, isFalse);
    monitor.complete();
    expect(await exit, AppExitResponse.exit);
    expect(calls, ['owner', 'host', 'monitor', 'store', 'client']);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(calls.length, 5);
  });

  testWidgets('VM quiescence completes before owner close starts',
      (tester) async {
    final service = TaskRoomService(db: db);
    final vm = _QuiescenceProbe(service, owner);
    probe.onClose = () async => true;
    await tester
        .pumpWidget(P6R7CandidateApp(viewModel: vm, lifecycleOwner: owner));
    final exit = tester.binding.handleRequestAppExit();
    await tester.pump();
    expect(probe.closeCalls, 0);
    vm.completion.complete();
    expect(await exit, AppExitResponse.exit);
    expect(probe.closeCalls, 1);
  });

  testWidgets(
      'session exception is sticky while successful owner and host stay cached',
      (tester) async {
    var hosts = 0;
    var sessions = 0;
    probe.onClose = () async => true;
    await tester.pumpWidget(P6R7CandidateApp(
      viewModel: viewModel,
      lifecycleOwner: owner,
      closeOwnedHost: () async {
        hosts++;
        return true;
      },
      closeSession: () async {
        sessions++;
        throw StateError('fixture');
      },
    ));
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    expect(probe.closeCalls, 1);
    expect(hosts, 1);
    expect(sessions, 1);
  });

  testWidgets('unconfirmed host prevents all session resource closure',
      (tester) async {
    probe.onClose = () async => true;
    await tester.pumpWidget(P6R7CandidateApp(
      viewModel: viewModel,
      lifecycleOwner: owner,
      closeOwnedHost: () async => false,
      closeSession: () async {
        fail('host is still owned');
      },
    ));
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
  });

  testWidgets('navigation does not close the lifecycle owner', (tester) async {
    await tester.pumpWidget(P6R7CandidateApp(
      viewModel: viewModel,
      lifecycleOwner: owner,
    ));
    await tester.tap(find.text('查看持续状态'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(probe.closeCalls, 0);
  });

  testWidgets('only detached asks the owner for best-effort close',
      (tester) async {
    await tester.pumpWidget(P6R7CandidateApp(
      viewModel: viewModel,
      lifecycleOwner: owner,
    ));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(probe.closeCalls, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();
    expect(probe.closeCalls, 1);
  });

  testWidgets('app exit waits for a confirmed lifecycle close', (tester) async {
    final completion = Completer<bool>();
    probe.onClose = () => completion.future;
    await tester.pumpWidget(P6R7CandidateApp(
      viewModel: viewModel,
      lifecycleOwner: owner,
    ));

    final exit = tester.binding.handleRequestAppExit();
    var resolved = false;
    exit.then((_) => resolved = true);
    await tester.pump();
    expect(probe.closeCalls, 1);
    expect(resolved, isFalse);
    expect(find.text('正在停止任务…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '创建验收任务'),
          )
          .onPressed,
      isNull,
    );

    completion.complete(true);
    expect(await exit, AppExitResponse.exit);
  });

  testWidgets('app exit waits for the owned host after lifecycle close',
      (tester) async {
    final lifecycle = Completer<bool>();
    final host = Completer<bool>();
    var hostCloses = 0;
    probe.onClose = () => lifecycle.future;
    await tester.pumpWidget(P6R7CandidateApp(
      viewModel: viewModel,
      lifecycleOwner: owner,
      closeOwnedHost: () {
        hostCloses++;
        return host.future;
      },
    ));

    final exit = tester.binding.handleRequestAppExit();
    await tester.pump();
    expect(probe.closeCalls, 1);
    expect(hostCloses, 0);

    lifecycle.complete(true);
    await tester.pump();
    expect(hostCloses, 1);
    var resolved = false;
    exit.then((_) => resolved = true);
    await tester.pump();
    expect(resolved, isFalse);

    host.complete(true);
    expect(await exit, AppExitResponse.exit);
  });

  testWidgets('app exit cancels when lifecycle close is unconfirmed',
      (tester) async {
    probe.onClose = () async => false;
    await tester.pumpWidget(P6R7CandidateApp(
      viewModel: viewModel,
      lifecycleOwner: owner,
    ));

    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    await tester.pump();
    expect(probe.closeCalls, 1);
    expect(find.text('任务停止未确认；可再次关闭重试。'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '创建验收任务'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('app exit cancels when lifecycle close throws', (tester) async {
    probe.onClose = () => Future<bool>.error(StateError('close failed'));
    await tester.pumpWidget(P6R7CandidateApp(
      viewModel: viewModel,
      lifecycleOwner: owner,
    ));

    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    expect(probe.closeCalls, 1);
  });

  testWidgets('unconfirmed or failed lifecycle close never closes owned host',
      (tester) async {
    var hostCloses = 0;
    probe.onClose = () async => false;
    await tester.pumpWidget(P6R7CandidateApp(
      viewModel: viewModel,
      lifecycleOwner: owner,
      closeOwnedHost: () async {
        hostCloses++;
        return true;
      },
    ));

    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    expect(hostCloses, 0);
  });

  testWidgets(
      'owned host failure cancels and retries without duplicating a success',
      (tester) async {
    var hostCloses = 0;
    probe.onClose = () async => true;
    await tester.pumpWidget(P6R7CandidateApp(
      viewModel: viewModel,
      lifecycleOwner: owner,
      closeOwnedHost: () async => ++hostCloses > 1,
    ));

    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(hostCloses, 2);
  });

  testWidgets('owned host exception cancels and permits the same exit retry',
      (tester) async {
    var hostCloses = 0;
    probe.onClose = () async => true;
    await tester.pumpWidget(P6R7CandidateApp(
      viewModel: viewModel,
      lifecycleOwner: owner,
      closeOwnedHost: () {
        hostCloses++;
        if (hostCloses == 1) {
          return Future<bool>.error(StateError('host failed'));
        }
        return Future<bool>.value(true);
      },
    ));

    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(hostCloses, 2);
  });

  testWidgets('concurrent app exit requests share one lifecycle close',
      (tester) async {
    final completion = Completer<bool>();
    final host = Completer<bool>();
    var hostCloses = 0;
    probe.onClose = () => completion.future;
    await tester.pumpWidget(P6R7CandidateApp(
      viewModel: viewModel,
      lifecycleOwner: owner,
      closeOwnedHost: () {
        hostCloses++;
        return host.future;
      },
    ));

    final first = tester.binding.handleRequestAppExit();
    final second = tester.binding.handleRequestAppExit();
    await tester.pump();
    expect(probe.closeCalls, 1);

    completion.complete(true);
    await tester.pump();
    expect(hostCloses, 1);
    host.complete(true);
    expect(await first, AppExitResponse.exit);
    expect(await second, AppExitResponse.exit);
    expect(probe.closeCalls, 1);
    expect(hostCloses, 1);
  });

  testWidgets('a canceled exit can retry the lifecycle close', (tester) async {
    var attempt = 0;
    probe.onClose = () async => ++attempt > 1;
    await tester.pumpWidget(P6R7CandidateApp(
      viewModel: viewModel,
      lifecycleOwner: owner,
    ));

    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(probe.closeCalls, 2);
  });

  testWidgets('failed exit remains visible on the retained state page',
      (tester) async {
    probe.onClose = () async => false;
    await tester.pumpWidget(P6R7CandidateApp(
      viewModel: viewModel,
      lifecycleOwner: owner,
    ));
    await tester.tap(find.text('查看持续状态'));
    await tester.pumpAndSettle();

    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    await tester.pump();
    expect(find.text('持续状态'), findsOneWidget);
    expect(find.text('任务停止未确认；可再次关闭重试。'), findsOneWidget);
  });
}

class _LifecycleProbe implements WorkbenchTaskQueueLifecycleController {
  int closeCalls = 0;
  Future<bool> Function()? onClose;

  @override
  Future<bool> closeForHostLifecycle() async {
    closeCalls++;
    return onClose?.call() ?? false;
  }
}

class _QuiescenceProbe extends P6R7CandidateViewModel {
  _QuiescenceProbe(
      TaskRoomService service, WorkbenchTaskQueueLifecycleOwner owner)
      : super(
            tool:
                WorkbenchRuntimeTaskQueueTool(loadService: () async => service),
            service: service,
            lifecycleOwner: owner,
            conversationId: 'p6-r7-widget',
            initialTaskId: null,
            persistTaskId: (_) async {});
  final completion = Completer<void>();
  @override
  Future<void> quiesceForExit() => completion.future;
}
