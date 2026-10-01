import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/settings/view_models/phone_memory_connection_viewmodel.dart';
import 'package:memex/ui/settings/widgets/phone_memory_connection_page.dart';
import 'package:memex/utils/result.dart';

void main() {
  testWidgets('phone is closed by default and only copies its code on request',
      (tester) async {
    final facade = _FakeFacade();
    await _pump(tester, facade: facade, desktop: false);

    expect(find.text('默认关闭'), findsOneWidget);
    expect(find.byKey(const ValueKey('phone_memory_start')), findsOneWidget);
    expect(find.textContaining('p5v1.'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('phone_memory_start')));
    await tester.pumpAndSettle();

    expect(find.text('短时会话已开启'), findsOneWidget);
    expect(find.byKey(const ValueKey('phone_memory_copy_code')), findsOneWidget);
    expect(find.textContaining('p5v1.'), findsNothing);
  });

  testWidgets('desktop code field is protected and clears after connection',
      (tester) async {
    final facade = _FakeFacade();
    await _pump(tester, facade: facade, desktop: true);
    final input = find.byKey(const ValueKey('phone_memory_connection_code'));
    expect(input, findsOneWidget);
    expect(tester.widget<TextField>(input).obscureText, isTrue);
    expect(tester.widget<TextField>(input).autocorrect, isFalse);

    await tester.enterText(input, 'p5v1.secret-code');
    await tester.tap(find.byKey(const ValueKey('phone_memory_connect')));
    await tester.pumpAndSettle();

    expect(facade.lastConnectionCode, 'p5v1.secret-code');
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    expect(find.textContaining('p5v1.secret-code'), findsNothing);
  });

  testWidgets('desktop names manual USB forwarding and never claims automation',
      (tester) async {
    await _pump(tester, facade: _FakeFacade(), desktop: true);

    expect(find.textContaining('不会自动执行'), findsOneWidget);
    expect(find.textContaining('手机 App 运行'), findsOneWidget);
  });

  testWidgets('expired desktop authorization remains explicitly disconnectable',
      (tester) async {
    final facade = _FakeFacade()
      ..configured = true
      ..expiresAt = DateTime.now().subtract(const Duration(minutes: 1));
    await _pump(tester, facade: facade, desktop: true);

    expect(find.text('本次会话已过期'), findsOneWidget);
    expect(find.byKey(const ValueKey('phone_memory_disconnect')), findsOneWidget);
  });

  testWidgets('pending connect can complete after the settings page is popped',
      (tester) async {
    final facade = _FakeFacade()..pendingConnect = Completer<Result<void>>();
    await _pump(tester, facade: facade, desktop: true);
    await tester.enterText(
      find.byKey(const ValueKey('phone_memory_connection_code')),
      'p5v1.pending',
    );
    await tester.tap(find.byKey(const ValueKey('phone_memory_connect')));
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    facade.pendingConnect!.complete(const Ok.v());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeFacade facade,
  required bool desktop,
}) => tester.pumpWidget(
      MaterialApp(
        theme: SpringRainUiTheme.build(ThemeData.light()),
        home: PhoneMemoryConnectionPage(
          facade: facade,
          desktopPlatformOverride: desktop,
        ),
      ),
    );

class _FakeFacade extends PhoneMemoryConnectionFacade {
  bool configured = false;
  DateTime? expiresAt;
  Completer<Result<void>>? pendingConnect;
  bool running = false;
  PhoneMemoryConnectionSession? session;
  String? lastConnectionCode;

  @override
  bool get isDesktopConfigured => configured;

  @override
  DateTime? get desktopExpiresAt => expiresAt;

  @override
  bool get isPhoneRunning => running;

  @override
  Map<String, Object?>? get lastReceipt => null;

  @override
  PhoneMemoryConnectionSession? get phoneSession => session;

  @override
  Future<Result<void>> connect(String connectionCode) async {
    lastConnectionCode = connectionCode;
    final pending = pendingConnect;
    if (pending != null) return pending.future;
    return const Ok.v();
  }

  @override
  void disconnect() {}

  @override
  Future<Result<PhoneMemoryConnectionSession>> startPhone() async {
    running = true;
    session = PhoneMemoryConnectionSession(
      expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      port: 47851,
      connectionCode: 'p5v1.secret-code',
    );
    notifyListeners();
    return Ok(session!);
  }

  @override
  Future<Result<void>> stopPhone() async {
    running = false;
    session = null;
    notifyListeners();
    return const Ok.v();
  }
}
