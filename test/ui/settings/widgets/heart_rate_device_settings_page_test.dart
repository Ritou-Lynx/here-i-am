import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/ble_heart_rate_gateway.dart';
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

  testWidgets('selected live scan result shows receiving state, not select',
      (tester) async {
    const selectedId = 'C7:C1:82:0F:70:4C';
    final fake = FakeBleHeartRateGateway()
      ..current = _deviceSnapshot(
        status: BleHeartRateStatus.live,
        enabled: true,
        deviceId: selectedId,
        bpm: 68,
      );
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

    fake.emitScanResult(const BleHeartRateDevice(
      deviceId: selectedId,
      name: 'COROS HEART RATE',
      rssi: -53,
    ));
    fake.emitScanResult(const BleHeartRateDevice(
      deviceId: 'AA:BB:CC:DD:EE:FF',
      name: 'Other HRS',
      rssi: -70,
    ));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('heart_rate_device_$selectedId')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.textContaining('已选择 · 已启用'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('heart_rate_selected_device_state_$selectedId'),
      ),
      findsOneWidget,
    );
    expect(find.text('正在接收'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('heart_rate_select_$selectedId')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('heart_rate_select_AA:BB:CC:DD:EE:FF'),
      ),
      findsOneWidget,
    );
    expect(fake.selectAndEnableCalls, 0);
    await fake.dispose();
  });

  testWidgets('selected stopped scan result can be explicitly re-enabled',
      (tester) async {
    const selectedId = 'C7:C1:82:0F:70:4C';
    final fake = FakeBleHeartRateGateway()
      ..current = _deviceSnapshot(
        status: BleHeartRateStatus.stopped,
        enabled: false,
        deviceId: selectedId,
      );
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
    fake.emitScanResult(const BleHeartRateDevice(
      deviceId: selectedId,
      name: 'COROS HEART RATE',
      rssi: -53,
    ));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('heart_rate_device_$selectedId')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.textContaining('已选择 · 已停止'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('heart_rate_reenable_$selectedId')),
    );
    await tester.pump();

    expect(fake.selectAndEnableCalls, 1);
    expect(fake.lastSelectedDevice?.deviceId, selectedId);
    await fake.dispose();
  });
}

BleHeartRateSnapshot _deviceSnapshot({
  required BleHeartRateStatus status,
  required bool enabled,
  required String deviceId,
  int? bpm,
}) {
  return BleHeartRateSnapshot(
    status: status,
    configured: true,
    enabled: enabled,
    permissionState: 'granted',
    notificationPermission: 'granted',
    bluetoothState: 'on',
    supported: true,
    deviceName: 'COROS HEART RATE',
    deviceId: deviceId,
    lastSample: bpm == null
        ? null
        : BleHeartRateSample(
            timestamp: DateTime(2026, 8, 29, 18, 0),
            bpm: bpm,
            contactSupported: false,
            contactDetected: null,
            energyExpended: null,
            rrIntervalsSeconds: const [],
          ),
  );
}
