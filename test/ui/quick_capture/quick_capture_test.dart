import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
