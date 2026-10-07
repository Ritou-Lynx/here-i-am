import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:memex/data/personal_data_hub/quick_capture_models.dart';
import 'package:memex/data/personal_data_hub/quick_capture_service.dart';
import 'package:memex/data/personal_data_hub/quick_capture_speech.dart';
import 'package:memex/ui/quick_capture/quick_capture_access_gate.dart';
import 'package:memex/ui/quick_capture/quick_capture_launch_bridge.dart';
import 'package:memex/ui/quick_capture/widgets/quick_capture_page.dart';

class _Speech implements QuickCaptureSpeech {
  int starts = 0, stops = 0;
  bool active = false;
  Completer<void>? ready;

  @override
  Future<String?> start(void Function(String) onText) async {
    starts++;
    active = true;
    await ready?.future;
    onText('合成语音草稿');
    return null;
  }

  @override
  Future<String?> finish() async {
    active = false;
    return '合成语音草稿';
  }

  @override
  Future<void> cancel() async {
    stops++;
    active = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'engine default denies cold capture without constructing its page',
      (tester) async {
    expect(QuickCaptureAccess.instance.value, isFalse);
    var pages = 0;
    final speech = _Speech();
    await tester
        .pumpWidget(MaterialApp(home: QuickCaptureAccessGate(builder: (_) {
      pages++;
      return QuickCapturePage(
          service: QuickCaptureService(
              submit: (_) => throw StateError('unexpected persistence')),
          speech: speech);
    })));
    await tester.pumpAndSettle();
    expect(pages, 0);
    expect(find.byType(QuickCapturePage), findsNothing);
    expect(speech.starts, 0);
  });

  testWidgets(
      'locked warm launch cannot create microphone; unlock starts once; relock disposes and reopening needs new access',
      (tester) async {
    final access = ValueNotifier<bool>(false);
    final instances = <_Speech>[];
    var saves = 0;
    final service = QuickCaptureService(submit: (draft) async {
      saves++;
      return QuickCaptureResult(captureId: draft.captureId!, text: draft.text);
    });
    final router = GoRouter(routes: [
      GoRoute(
          path: '/', builder: (_, __) => const Scaffold(body: Text('普通入口'))),
      GoRoute(
          path: '/quick-capture',
          builder: (_, __) => QuickCaptureAccessGate(
              access: access,
              builder: (_) {
                final speech = _Speech();
                instances.add(speech);
                return QuickCapturePage(service: service, speech: speech);
              })),
    ]);
    const channel = MethodChannel('test.capture.access.warm');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final bridge = QuickCaptureLaunchBridge(channel: channel);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await bridge.start(() => router.go('/quick-capture'));
    Future<void> launch(String id) async {
      await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall('capture', id)),
          (_) {});
      await tester.pumpAndSettle();
    }

    await launch('locked-launch-1');
    expect(router.routeInformationProvider.value.uri.path, '/quick-capture');
    expect(instances, isEmpty);
    expect(find.byType(QuickCapturePage), findsNothing);
    access.value = true;
    await tester.pumpAndSettle();
    expect(instances, hasLength(1));
    expect(instances.single.starts, 1);
    expect(instances.single.active, isTrue);
    await tester.pump();
    expect(instances.single.starts, 1);

    access.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(QuickCapturePage), findsNothing);
    expect(instances.single.stops, 1);
    expect(instances.single.active, isFalse);
    await launch('locked-launch-2');
    expect(instances, hasLength(1));
    expect(saves, 0);

    access.value = true;
    await tester.pumpAndSettle();
    expect(instances, hasLength(2));
    expect(instances.last.starts, 0);
    expect(instances.first.active, isFalse);
    expect(find.text('合成语音草稿'), findsOneWidget);
    expect(saves, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(instances.last.stops, 1);
    bridge.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    router.dispose();
    access.dispose();
  });

  testWidgets(
      'unsent edited text and capture ID survive lock without restarting voice',
      (tester) async {
    final access = ValueNotifier<bool>(true);
    final instances = <_Speech>[];
    final submitted = <QuickCaptureDraft>[];
    final service = QuickCaptureService(submit: (draft) async {
      submitted.add(draft);
      return QuickCaptureResult(captureId: draft.captureId!, text: draft.text);
    });
    await tester.pumpWidget(MaterialApp(
        home: QuickCaptureAccessGate(
            access: access,
            builder: (_) {
              final speech = _Speech();
              instances.add(speech);
              return QuickCapturePage(service: service, speech: speech);
            })));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成录音，编辑文字'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '未发送的修改原话');
    final original = QuickCaptureDraftSession.maybeOf(
            tester.element(find.byType(QuickCapturePage)))!
        .draft!;
    expect(original.captureId, isNotNull);
    access.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(QuickCapturePage), findsNothing);
    expect(instances.single.active, isFalse);
    expect(submitted, isEmpty);
    access.value = true;
    await tester.pumpAndSettle();
    expect(instances, hasLength(2));
    expect(instances.last.starts, 0);
    expect(find.text('未发送的修改原话'), findsOneWidget);
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(submitted.single.captureId, original.captureId);
    expect(submitted.single.text, '未发送的修改原话');
    expect(instances.last.starts, 0);
    await tester.tap(find.text('重新录音'));
    await tester.pumpAndSettle();
    expect(instances.last.starts, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    access.dispose();
  });

  testWidgets(
      'relock while speech startup waits disposes page and ignores late text',
      (tester) async {
    final access = ValueNotifier<bool>(true);
    final speech = _Speech()..ready = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: QuickCaptureAccessGate(
            access: access,
            builder: (_) => QuickCapturePage(
                service: QuickCaptureService(
                    submit: (_) => throw StateError('unexpected persistence')),
                speech: speech))));
    await tester.pump();
    expect(speech.starts, 1);
    access.value = false;
    await tester.pumpAndSettle();
    expect(speech.active, isFalse);
    expect(find.byType(QuickCapturePage), findsNothing);
    speech.ready!.complete();
    await tester.pumpAndSettle();
    expect(speech.active, isFalse);
    expect(find.text('合成语音草稿'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    access.dispose();
  });
}
