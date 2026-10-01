import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/p6_r7_candidate/widgets/p6_r7_candidate_startup.dart';

void main() {
  testWidgets('startup error is fixed text and failed host close can retry',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(P6R7CandidateStartup(
      prepare: (_) async => throw StateError('private headers and token'),
      closeOwnedHost: () async => ++calls > 1,
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('private'), findsNothing);
    expect(find.textContaining('隔离验收尚未就绪'), findsOneWidget);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    await tester.pump();
    expect(find.text('停止尚未确认；可再次关闭重试。'), findsOneWidget);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(calls, 2);
  });

  testWidgets('each reported startup failure shows only its fixed stage label',
      (tester) async {
    for (final stage in P6R7CandidateStartupStage.values) {
      await tester.pumpWidget(P6R7CandidateStartup(
        key: ValueKey(stage),
        prepare: (reportStage) async {
          reportStage(stage);
          throw StateError('private path headers token $stage');
        },
        closeOwnedHost: () async => true,
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('当前阶段：${stage.label}'), findsOneWidget);
      expect(find.textContaining('private path'), findsNothing);
      expect(find.textContaining('headers'), findsNothing);
      expect(find.textContaining('token'), findsNothing);
    }
  });

  testWidgets(
      'exit signals owned close immediately while retaining preparation ownership',
      (tester) async {
    final prepared = Completer<Widget>();
    final closed = Completer<bool>();
    var calls = 0;
    await tester.pumpWidget(P6R7CandidateStartup(
      prepare: (_) => prepared.future,
      closeOwnedHost: () {
        calls++;
        return closed.future;
      },
    ));
    final first = tester.binding.handleRequestAppExit();
    final second = tester.binding.handleRequestAppExit();
    var resolved = false;
    unawaited(first.then((_) => resolved = true));
    await tester.pump();
    expect(calls, 1);
    expect(resolved, isFalse);
    prepared.complete(const MaterialApp(home: Text('ready task controls')));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('ready task controls'), findsNothing);
    expect(resolved, isFalse);
    closed.complete(true);
    expect(await first, AppExitResponse.exit);
    expect(await second, AppExitResponse.exit);
  });

  testWidgets('scheduled ready root without a mounted observer cancels exit',
      (tester) async {
    final prepared = Completer<Widget>();
    var rootMounted = false;
    var rootExits = 0;
    var startupCloses = 0;
    await tester.pumpWidget(P6R7CandidateStartup(
      prepare: (_) => prepared.future,
      closeOwnedHost: () async {
        startupCloses++;
        return true;
      },
    ));
    prepared.complete(_ExitProbe(
      onMount: () => rootMounted = true,
      onExit: () async {
        rootExits++;
        return AppExitResponse.exit;
      },
    ));
    // Flush preparation's microtasks, deliberately do not run the ready frame.
    await tester.idle();
    expect(rootMounted, isFalse);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    expect(startupCloses, 0);
    expect(rootExits, 0);
    await tester.pump();
    expect(rootMounted, isTrue);
    expect(find.text('ready root'), findsOneWidget);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(rootExits, 1);
    expect(startupCloses, 0);
  });

  testWidgets(
      'reentrant mount exit traverses both observers but host follows root gate',
      (tester) async {
    final prepared = Completer<Widget>();
    final lifecycle = Completer<bool>();
    late Future<AppExitResponse> exitDuringMount;
    final calls = <String>[];
    var startupCloses = 0;
    var rootDisposed = false;
    await tester.pumpWidget(P6R7CandidateStartup(
      prepare: (_) => prepared.future,
      closeOwnedHost: () async {
        startupCloses++;
        return true;
      },
    ));
    prepared.complete(_ExitProbe(
      // A programmatic reentrant request constructs the overlap precisely. This
      // does not assert that an ordinary OS message interrupts synchronous build.
      onMount: () => exitDuringMount = tester.binding.handleRequestAppExit(),
      onDispose: () => rootDisposed = true,
      onExit: () async {
        calls.add('lifecycle');
        if (!await lifecycle.future) return AppExitResponse.cancel;
        calls.add('host');
        return AppExitResponse.exit;
      },
    ));
    await tester.idle();
    await tester.pump();
    expect(calls, ['lifecycle']);
    expect(startupCloses, 0);
    expect(rootDisposed, isFalse);
    expect(find.text('ready root'), findsOneWidget);
    lifecycle.complete(true);
    expect(await exitDuringMount, AppExitResponse.cancel);
    expect(calls, ['lifecycle', 'host']);
    expect(startupCloses, 0);
    expect(rootDisposed, isFalse);
    // Once transfer finishes, the next exit reaches only the root observer.
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(startupCloses, 0);
  });

  testWidgets('close exception preserves startup owner for another attempt',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(P6R7CandidateStartup(
      prepare: (_) async => throw StateError('not ready'),
      closeOwnedHost: () async {
        if (++calls == 1) throw StateError('raw host error');
        return true;
      },
    ));
    await tester.pumpAndSettle();
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    await tester.pump();
    expect(find.textContaining('raw host error'), findsNothing);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
  });

  testWidgets(
      'ready application receives exit after startup observer is removed',
      (tester) async {
    var startupCloses = 0;
    await tester.pumpWidget(P6R7CandidateStartup(
      prepare: (_) async => const MaterialApp(home: Text('ready')),
      closeOwnedHost: () async {
        startupCloses++;
        return true;
      },
    ));
    await tester.pumpAndSettle();
    expect(find.text('ready'), findsOneWidget);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(startupCloses, 0);
  });
}

class _ExitProbe extends StatefulWidget {
  const _ExitProbe(
      {required this.onMount, required this.onExit, this.onDispose});
  final VoidCallback onMount;
  final Future<AppExitResponse> Function() onExit;
  final VoidCallback? onDispose;
  @override
  State<_ExitProbe> createState() => _ExitProbeState();
}

class _ExitProbeState extends State<_ExitProbe> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.onMount();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() => widget.onExit();
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: Text('ready root'));
}

