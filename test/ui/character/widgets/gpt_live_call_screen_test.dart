import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/character/widgets/gpt_live_call/call_overlays.dart';

void main() {
  testWidgets('结束卡片显示时长和原因', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CallEndCard(
            duration: const Duration(seconds: 125),
            reason: '你挂断',
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('通话结束 · 2 分 5 秒 · 你挂断'), findsOneWidget);
  });

  testWidgets('失败态显示重拨和返回', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CallFailureCard(
            reason: '连接出错（network）',
            onRetry: () {},
            onBack: () {},
          ),
        ),
      ),
    );

    expect(find.text('没接通'), findsOneWidget);
    expect(find.text('重拨'), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);
  });

  testWidgets('催睡标签显示来电人和剩余时间', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CallNudgeBanner(
            name: '林埃',
            remaining: Duration(minutes: 3, seconds: 7),
          ),
        ),
      ),
    );

    expect(find.text('林埃来电 · 催睡'), findsOneWidget);
    expect(find.text('剩 03:07'), findsOneWidget);
  });

  test('计时满一小时显示小时', () {
    expect(
      formatCallClock(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });
}
