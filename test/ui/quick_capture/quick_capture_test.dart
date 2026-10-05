import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/personal_data_hub/quick_capture_models.dart';
import 'package:memex/data/personal_data_hub/quick_capture_service.dart';
import 'package:memex/ui/quick_capture/quick_capture_controller.dart';
import 'package:memex/ui/quick_capture/quick_capture_page.dart';

void main() {
  test('service rejects empty text and preserves capture id', () async {
    final service = QuickCaptureService(submit: (draft) async => QuickCaptureResult(captureId: draft.captureId!, text: draft.text));
    final draft = service.newDraft();
    expect(draft.captureId, isNotEmpty);
    expect(() => service.send(draft), throwsA(isA<FormatException>()));
  });

  testWidgets('page edits text and exposes two processor results', (tester) async {
    final service = QuickCaptureService(submit: (draft) async => QuickCaptureResult(
      captureId: draft.captureId!, text: draft.text, organizerMessage: '生活事实已处理', plannerMessage: '待办已安排'));
    final controller = QuickCaptureController(service);
    await tester.pumpWidget(MaterialApp(home: QuickCapturePage(controller: controller)));
    await tester.enterText(find.byType(TextField), '买牛奶');
    await tester.tap(find.text('完成')); await tester.pump();
    expect(find.text('已保存到收件箱'), findsOneWidget);
    expect(find.text('生活事实已处理'), findsOneWidget);
    expect(find.text('待办已安排'), findsOneWidget);
  });

  test('failed submission remains visible', () async {
    final service = QuickCaptureService(submit: (_) => Future.error(StateError('offline')));
    final controller = QuickCaptureController(service); controller.setText('稍后补发');
    await controller.send();
    expect(controller.state, QuickCaptureState.failed);
    expect(controller.error, contains('offline'));
  });
}
