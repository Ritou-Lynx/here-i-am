import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/settings/widgets/heart_rate_device_settings_page.dart';

import '../../../data/services/ble_heart_rate_gateway_test.dart';

void main() {
  testWidgets('permission request stays pending until lifecycle refresh',
      (tester) async {
    final fake = FakeBleHeartRateGateway()
      ..platformState = const {
        'supported': true,
        'permissionState': 'denied',
        'notificationPermission': 'denied',
        'bluetoothState': 'on',
      };
    await tester.pumpWidget(
      MaterialApp(
        theme: SpringRainUiTheme.build(ThemeData.light()),
        home: HeartRateDeviceSettingsPage(
          gateway: fake,
          userId: 'lynx',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('heart_rate_request_permission')));
    await tester.pump();

    expect(find.textContaining('不会提前显示为已授权'), findsOneWidget);
    expect(find.text('授权蓝牙'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('授权蓝牙'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await fake.dispose();
  });
}
