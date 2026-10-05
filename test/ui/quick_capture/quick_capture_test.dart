import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub_runtime.dart';
import 'package:memex/ui/quick_capture/widgets/quick_capture_host_screen.dart';
import 'package:memex/data/personal_data_hub/quick_capture_models.dart';
import 'package:memex/data/personal_data_hub/quick_capture_service.dart';
import 'package:memex/data/personal_data_hub/quick_capture_speech.dart';
import 'package:memex/ui/quick_capture/widgets/quick_capture_page.dart';
import 'package:memex/ui/quick_capture/view_models/quick_capture_view_model.dart';
import 'package:memex/ui/quick_capture/quick_capture_launch_bridge.dart';

class Speech implements QuickCaptureSpeech {
  bool cancelled = false;
  @override
  Future<String?> start(void Function(String) onText) async {
    onText('午饭 30 元，明天买牛奶');
    return null;
  }

  @override
  Future<String?> finish() async => '午饭 30 元，明天买牛奶。';
  @override
  Future<void> cancel() async {
    cancelled = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('com.memexlab.memex/quick_capture'),
          (_) async => true);

  testWidgets(
      'host distinguishes loading from initialization failure without exposing errors',
      (tester) async {
    await tester.pumpWidget(Provider<Result<PersonalDataHubRuntime>?>.value(
        value: null, child: const MaterialApp(home: QuickCaptureHostScreen())));
    expect(find.text('正在打开记录入口…'), findsOneWidget);
    expect(find.byType(QuickCapturePage), findsNothing);
    await tester.pumpWidget(Provider<Result<PersonalDataHubRuntime>?>.value(
        value: Error(StateError('secret synthetic token')),
        child: const MaterialApp(home: QuickCaptureHostScreen())));
    expect(find.text('记录入口暂时无法打开，请返回后重试'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    expect(find.byType(QuickCapturePage), findsNothing);
  });

  testWidgets(
      'independent capture close finishes native task without navigating home',
      (tester) async {
    var finishes = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.memexlab.memex/quick_capture'),
            (call) async {
      if (call.method == 'finishCapture') finishes++;
      return null;
    });
    await tester.pumpWidget(Provider<Result<PersonalDataHubRuntime>?>.value(
        value: Error(StateError('fixture')),
        child: const MaterialApp(
            home: QuickCaptureHostScreen(independentTask: true))));
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(finishes, 1);
    expect(find.byType(QuickCaptureHostScreen), findsOneWidget);
  });

  testWidgets(
      'ordinary capture close navigates home even when native bridge is unavailable',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.memexlab.memex/quick_capture'),
            (_) async => throw MissingPluginException());
    final router = GoRouter(initialLocation: '/capture', routes: [
      GoRoute(path: '/', builder: (_, __) => const Text('首页夹具')),
      GoRoute(
          path: '/capture', builder: (_, __) => const QuickCaptureHostScreen()),
    ]);
    await tester.pumpWidget(Provider<Result<PersonalDataHubRuntime>?>.value(
        value: Error(StateError('fixture')),
        child: MaterialApp.router(routerConfig: router)));
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('首页夹具'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.memexlab.memex/quick_capture'),
            (_) async => true);
  });

  testWidgets(
      'change events only refresh recent results and unsubscribe on disposal',
      (tester) async {
    final events = StreamController<void>.broadcast();
    var reads = 0, sends = 0;
    var label = '生活记录：待处理';
    final service = QuickCaptureService(submit: (draft) async {
      sends++;
      return QuickCaptureResult(captureId: draft.captureId!, text: draft.text);
    });
    await tester.pumpWidget(MaterialApp(
        home: QuickCapturePage(
            service: service,
            changes: events.stream,
            recent: () async {
              reads++;
              return [
                QuickCaptureResult(
                    captureId: 'saved-id',
                    text: '已存原话',
                    organizerMessage: label)
              ];
            })));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '尚未发送的草稿');
    expect(reads, 1);
    expect(events.hasListener, true);
    label = '生活记录：已处理';
    events.add(null);
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(sends, 0);
    expect(find.text('生活记录：已处理'), findsOneWidget);
    expect(find.text('尚未发送的草稿'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(events.hasListener, false);
    events.add(null);
    await tester.pump();
    expect(reads, 2);
    await events.close();
  });

  testWidgets(
      'newer recent refresh wins when asynchronous reads complete out of order',
      (tester) async {
    final events = StreamController<void>.broadcast();
    final old = Completer<List<QuickCaptureResult>>();
    var reads = 0;
    await tester.pumpWidget(MaterialApp(
        home: QuickCapturePage(
            service: QuickCaptureService(
                submit: (_) => throw StateError('must not save')),
            changes: events.stream,
            recent: () {
              reads++;
              return reads == 1
                  ? old.future
                  : Future.value(const [
                      QuickCaptureResult(captureId: 'new', text: '最新结果')
                    ]);
            })));
    events.add(null);
    await tester.pumpAndSettle();
    expect(find.text('最新结果'), findsOneWidget);
    old.complete(const [QuickCaptureResult(captureId: 'old', text: '旧结果')]);
    await tester.pumpAndSettle();
    expect(find.text('最新结果'), findsOneWidget);
    expect(find.text('旧结果'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await events.close();
  });
  test(
      'production speech adapter without a local model falls back before opening microphone',
      () async {
    final speech = LocalQuickCaptureSpeech(localModelReady: () async => false);
    expect(await speech.start((_) => fail('no recognition expected')),
        contains('键盘'));
    expect(await speech.finish(), isNull);
    await speech.cancel();
    await speech.cancel();
  });
  test('service rejects empty and missing id, preserves retry id', () async {
    final seen = <String?>[];
    final service = QuickCaptureService(
      submit: (draft) async {
        seen.add(draft.captureId);
        return QuickCaptureResult(
          captureId: draft.captureId!,
          text: draft.text,
        );
      },
    );
    expect(() => service.send(service.newDraft()), throwsFormatException);
    expect(
      () => service.send(const QuickCaptureDraft('x')),
      throwsFormatException,
    );
    final draft = service.newDraft('原话');
    await service.send(draft);
    await service.send(draft);
    expect(seen, [draft.captureId, draft.captureId]);
  });
  testWidgets(
    'voice calibration editable; sends only on explicit tap; status and outputs',
    (tester) async {
      var calls = 0;
      final speech = Speech();
      final service = QuickCaptureService(
        submit: (draft) async {
          calls++;
          expect(draft.text, '午饭 35 元，明天买牛奶');
          return QuickCaptureResult(
            captureId: draft.captureId!,
            text: draft.text,
            organizerMessage: '生活记录：已处理',
            organizerOutputs: const ['card-a'],
            plannerMessage: '待办与时间：待处理',
            pendingIssues: const ['保留用户改卡'],
          );
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: QuickCapturePage(service: service, speech: speech),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.text('完成录音，编辑文字'));
      await tester.pumpAndSettle();
      expect(find.text('午饭 30 元，明天买牛奶。'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '午饭 35 元，明天买牛奶');
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('查看生活记录 1'), findsOneWidget);
      expect(find.text('保留用户改卡'), findsOneWidget);
      expect(find.text('待办与时间：待处理'), findsOneWidget);
    },
  );
  testWidgets('cancel aborts mic and has no persistence', (tester) async {
    var saves = 0, closes = 0;
    final speech = Speech();
    await tester.pumpWidget(
      MaterialApp(
        home: QuickCapturePage(
          speech: speech,
          onClose: () => closes++,
          service: QuickCaptureService(
            submit: (draft) async {
              saves++;
              return QuickCaptureResult(
                captureId: draft.captureId!,
                text: draft.text,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(speech.cancelled, true);
    expect(saves, 0);
    expect(closes, 1);
  });
  test(
    'failed send retains draft and double send uses one in-flight request',
    () async {
      final pending = Completer<QuickCaptureResult>();
      var calls = 0;
      final vm = QuickCaptureViewModel(
        QuickCaptureService(
          submit: (_) {
            calls++;
            return pending.future;
          },
        ),
      );
      vm.setText('重试');
      final id = vm.draft.captureId;
      final a = vm.send.execute();
      await vm.send.execute();
      pending.completeError(StateError('disk full'));
      await a;
      expect(vm.error, isNotNull);
      expect(vm.draft.captureId, id);
      expect(calls, 1);
      vm.dispose();
    },
  );
  test(
    'launch bridge deduplicates warm notification and pending replay',
    () async {
      const channel = MethodChannel('test.quick_capture');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => 'same-action');
      final bridge = QuickCaptureLaunchBridge(channel: channel);
      var calls = 0;
      await bridge.start(() => calls++);
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('capture', 'same-action'),
        ),
        (_) {},
      );
      expect(calls, 1);
      bridge.dispose();
    },
  );
}
