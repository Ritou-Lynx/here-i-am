import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/location_context_config.dart';
import 'package:memex/ui/settings/widgets/location_context_settings_page.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('updates location context settings from the page',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'language': 'en',
      'location_context_config': jsonEncode(
        const LocationContextConfig(
          enabled: false,
          provider: GeocodingProvider.openStreetMap,
          granularity: LocationContextGranularity.neighborhood,
          ttlMinutes: 15,
        ).toJson(),
      ),
    });
    await UserStorage.initL10n();

    await tester.pumpWidget(
      const MaterialApp(
        home: LocationContextSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Location Context'), findsOneWidget);
    expect(find.text('Attach current location to chat'), findsOneWidget);
    expect(find.text('OpenStreetMap / Nominatim'), findsOneWidget);
    expect(find.text('Amap API Key'), findsNothing);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    var config = await UserStorage.getLocationContextConfig();
    expect(config.enabled, isTrue);

    await tester.tap(find.text('OpenStreetMap / Nominatim'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amap').last);
    await tester.pumpAndSettle();

    expect(find.text('Amap API Key'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'test-amap-key');
    await tester.pumpAndSettle();

    config = await UserStorage.getLocationContextConfig();
    expect(config.provider, GeocodingProvider.amap);
    expect(config.amapApiKey, 'test-amap-key');

    await tester.tap(find.text('Neighborhood'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Street').last);
    await tester.pumpAndSettle();

    config = await UserStorage.getLocationContextConfig();
    expect(config.granularity, LocationContextGranularity.street);
  });

  testWidgets('renders localized Chinese labels', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'language': 'zh',
      'location_context_config': jsonEncode(
        const LocationContextConfig().toJson(),
      ),
    });
    await UserStorage.initL10n();

    await tester.pumpWidget(
      const MaterialApp(
        home: LocationContextSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('位置上下文'), findsOneWidget);
    expect(find.text('为对话附加当前位置'), findsOneWidget);
    expect(find.text('逆地理编码服务商'), findsOneWidget);
    expect(find.text('上下文粒度'), findsOneWidget);
  });
}
