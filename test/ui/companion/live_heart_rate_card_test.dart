import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/ble_heart_rate_gateway.dart';
import 'package:memex/ui/companion/widgets/live_heart_rate_card.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';

import '../../data/services/ble_heart_rate_gateway_test.dart';

void main() {
  testWidgets('card renders unconfigured, live RR and stale states',
      (tester) async {
    final fake = FakeBleHeartRateGateway();
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: SpringRainUiTheme.build(ThemeData.light()),
        home: Scaffold(
          body: LiveHeartRateCard(
            gateway: fake,
            userId: 'lynx',
            onTap: () => opened = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('未配置实时心率设备'), findsOneWidget);

    fake.emitSnapshot(snapshot(BleHeartRateStatus.live, bpm: 68));
    await tester.pumpAndSettle();
    expect(find.text('68 BPM'), findsOneWidget);
    expect(find.textContaining('RR 已出现'), findsOneWidget);

    fake.emitSnapshot(snapshot(BleHeartRateStatus.stale, bpm: 68));
    await tester.pumpAndSettle();
    expect(find.text('心率样本已陈旧'), findsOneWidget);
    expect(find.textContaining('最后样本'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('live_heart_rate_card')));
    expect(opened, isTrue);
    await fake.dispose();
  });
}
