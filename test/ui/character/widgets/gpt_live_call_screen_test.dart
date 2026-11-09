import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/gpt_live/gpt_live_call.dart';
import 'package:memex/ui/character/widgets/gpt_live_call/call_overlays.dart';
import 'package:memex/ui/character/widgets/gpt_live_call_screen.dart';

/// 结束卡片停留 2 秒后才退出。
Future<void> waitEndCard(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

void main() {
  Future<void> openCall(
    WidgetTester tester,
    _FakeCall call, {
    GlobalKey<NavigatorState>? navigatorKey,
    NavigatorObserver? observer,
  }) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [if (observer != null) observer],
      home: Builder(builder: (context) {
        return Scaffold(
          body: Column(children: [
            const Text('聊天页'),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GptLiveCallScreen(
                    characterId: 'test',
                    call: call,
                  ),
                ),
              ),
              child: const Text('拨号'),
            ),
          ]),
        );
      }),
    ));
    await tester.tap(find.text('拨号'));
    // 通话中呼吸动画一直在跑，pumpAndSettle 不会收敛，改为推进固定时长。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('服务端结束后自动回聊天，重复通知只退一层', (tester) async {
    final call = _FakeCall();
    final observer = _NavigationObserver();
    await openCall(tester, call, observer: observer);

    call.finish();
    call.finish();
    await tester.pump();
    expect(find.textContaining('通话结束'), findsOneWidget);
    await waitEndCard(tester);

    expect(find.text('聊天页'), findsOneWidget);
    expect(find.byType(GptLiveCallScreen), findsNothing);
    expect(observer.pops, 1);
    expect(call.hangUps, 0);
  });

  testWidgets('接通后连接失败自动回聊天', (tester) async {
    final call = _FakeCall();
    await openCall(tester, call);

    call.fail();
    await tester.pump();
    expect(find.textContaining('通话结束'), findsOneWidget);
    await waitEndCard(tester);

    expect(find.text('聊天页'), findsOneWidget);
    expect(find.byType(GptLiveCallScreen), findsNothing);
  });

  testWidgets('连接前失败保留错误提示和返回按钮', (tester) async {
    final call = _FakeCall(failBeforeConnecting: true);
    await openCall(tester, call);

    expect(find.text('没接通'), findsOneWidget);
    expect(find.text('连接出错（no_api_key）'), findsOneWidget);
    expect(find.text('重拨'), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(find.text('聊天页'), findsOneWidget);
  });

  testWidgets('慢挂断期间反复点按和系统返回只挂断一次', (tester) async {
    final completion = Completer<void>();
    final call = _FakeCall(hangUpCompletion: completion.future);
    final observer = _NavigationObserver();
    await openCall(tester, call, observer: observer);

    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(call.hangUps, 1);
    expect(find.byType(GptLiveCallScreen), findsOneWidget);
    expect(observer.pops, 0);

    completion.complete();
    await waitEndCard(tester);
    expect(find.text('聊天页'), findsOneWidget);
    expect(call.hangUps, 1);
    expect(observer.pops, 1);
  });

  testWidgets('系统返回等待挂断完成后回聊天', (tester) async {
    final call = _FakeCall();
    final observer = _NavigationObserver();
    await openCall(tester, call, observer: observer);

    await tester.binding.handlePopRoute();
    await waitEndCard(tester);

    expect(find.text('聊天页'), findsOneWidget);
    expect(call.hangUps, 1);
    expect(observer.pops, 1);
  });

  testWidgets('通话页被覆盖时只移除通话页', (tester) async {
    final call = _FakeCall();
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = _NavigationObserver();
    await openCall(tester, call,
        navigatorKey: navigatorKey, observer: observer);
    unawaited(navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('其他页面')),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    call.finish();
    await waitEndCard(tester);
    expect(find.text('其他页面'), findsOneWidget);
    expect(observer.removes, 1);
    expect(observer.pops, 0);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('聊天页'), findsOneWidget);
    expect(find.byType(GptLiveCallScreen), findsNothing);
  });

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

  testWidgets('失败卡片显示重拨和返回', (tester) async {
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

class _FakeCall extends GptLiveCall {
  _FakeCall({this.failBeforeConnecting = false, this.hangUpCompletion})
      : super(characterId: 'test');

  final bool failBeforeConnecting;
  final Future<void>? hangUpCompletion;
  int hangUps = 0;

  @override
  Future<void> start() async {
    if (failBeforeConnecting) {
      error = 'no_api_key';
      phase = GptLiveCallPhase.failed;
    } else {
      startedAt = DateTime.now();
      phase = GptLiveCallPhase.live;
    }
    notifyListeners();
  }

  @override
  Future<void> hangUp({String reason = 'user'}) async {
    hangUps++;
    phase = GptLiveCallPhase.ending;
    notifyListeners();
    await hangUpCompletion;
    finish();
  }

  void finish() {
    phase = GptLiveCallPhase.ended;
    notifyListeners();
  }

  void fail() {
    error = 'connection_lost';
    phase = GptLiveCallPhase.failed;
    notifyListeners();
  }
}

class _NavigationObserver extends NavigatorObserver {
  int pops = 0;
  int removes = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    removes++;
  }
}
