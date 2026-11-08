import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/gpt_live/gpt_live_call.dart';
import 'package:memex/ui/character/widgets/gpt_live_call_screen.dart';

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
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();

    expect(find.text('聊天页'), findsOneWidget);
    expect(find.byType(GptLiveCallScreen), findsNothing);
    expect(observer.pops, 1);
    expect(call.hangUps, 0);
  });

  testWidgets('接通后连接失败自动回聊天', (tester) async {
    final call = _FakeCall();
    await openCall(tester, call);

    call.fail();
    await tester.pumpAndSettle();

    expect(find.text('聊天页'), findsOneWidget);
    expect(find.byType(GptLiveCallScreen), findsNothing);
  });

  testWidgets('连接前失败保留错误提示和返回按钮', (tester) async {
    final call = _FakeCall(failBeforeConnecting: true);
    await openCall(tester, call);

    expect(find.text('没接通：no_api_key'), findsOneWidget);
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
    await tester.pumpAndSettle();
    expect(find.text('聊天页'), findsOneWidget);
    expect(call.hangUps, 1);
    expect(observer.pops, 1);
  });

  testWidgets('系统返回等待挂断完成后回聊天', (tester) async {
    final call = _FakeCall();
    final observer = _NavigationObserver();
    await openCall(tester, call, observer: observer);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    call.finish();
    await tester.pumpAndSettle();
    expect(find.text('其他页面'), findsOneWidget);
    expect(observer.removes, 1);
    expect(observer.pops, 0);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('聊天页'), findsOneWidget);
    expect(find.byType(GptLiveCallScreen), findsNothing);
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
