import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/location_context_config.dart';
import 'package:memex/ui/settings/widgets/location_context_settings_page.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpLocationSettingsPage(
    WidgetTester tester, {
    String language = 'en',
    LocationContextConfig config = const LocationContextConfig(),
    CurrentLocationContextLoader? loadCurrentContext,
  }) async {
    SharedPreferences.setMockInitialValues({
      'language': language,
      'location_context_config': jsonEncode(config.toJson()),
    });
    await UserStorage.initL10n();

    await tester.pumpWidget(
      MaterialApp(
        home: LocationContextSettingsPage(
          loadCurrentContext: loadCurrentContext,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openAdvancedSettings(WidgetTester tester) async {
    final advancedFinder = find.text('高级设置');
    if (advancedFinder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        advancedFinder,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }
    if (find.text('Reverse geocoding provider').evaluate().isEmpty) {
      await tester.tap(advancedFinder);
      await tester.pumpAndSettle();
    }
  }

  Future<void> scrollToTestButton(WidgetTester tester) async {
    await openAdvancedSettings(tester);
    await tester.scrollUntilVisible(
      find.text('Test current location'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollToText(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      find.text(text),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('updates location context settings from the page', (
    WidgetTester tester,
  ) async {
    await pumpLocationSettingsPage(
      tester,
      config: const LocationContextConfig(
        enabled: false,
        provider: GeocodingProvider.openStreetMap,
        granularity: LocationContextGranularity.neighborhood,
        ttlMinutes: 15,
      ),
    );

    expect(find.text('位置、地图与天气'), findsOneWidget);
    expect(find.text('让 I 知道你的位置'), findsOneWidget);
    expect(find.text('高德 Key'), findsOneWidget);
    expect(find.text('路线陪跑提醒'), findsOneWidget);
    expect(find.text('高级设置'), findsOneWidget);

    await tester.tap(find.widgetWithText(SwitchListTile, '让 I 知道你的位置'));
    await tester.pumpAndSettle();
    var config = await UserStorage.getLocationContextConfig();
    expect(config.enabled, isTrue);

    await tester.enterText(find.byType(TextField), 'test-amap-key');
    await tester.pumpAndSettle();
    config = await UserStorage.getLocationContextConfig();
    expect(config.amapApiKey, 'test-amap-key');

    await tester.tap(find.widgetWithText(SwitchListTile, '路线陪跑提醒'));
    await tester.pumpAndSettle();
    config = await UserStorage.getLocationContextConfig();
    expect(config.transitCompanionEnabled, isTrue);

    await openAdvancedSettings(tester);
    await scrollToText(tester, 'OpenStreetMap / Nominatim');
    await tester.tap(find.text('OpenStreetMap / Nominatim'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amap').last);
    await tester.pumpAndSettle();

    config = await UserStorage.getLocationContextConfig();
    expect(config.provider, GeocodingProvider.amap);
    expect(config.amapApiKey, 'test-amap-key');

    await scrollToText(tester, 'Amap');
    await tester.tap(find.text('Amap'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenStreetMap / Nominatim').last);
    await tester.pumpAndSettle();

    config = await UserStorage.getLocationContextConfig();
    expect(config.provider, GeocodingProvider.openStreetMap);
    expect(config.amapApiKey, 'test-amap-key');

    await scrollToText(tester, 'Neighborhood');
    await tester.tap(find.text('Neighborhood'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Street').last);
    await tester.pumpAndSettle();

    config = await UserStorage.getLocationContextConfig();
    expect(config.granularity, LocationContextGranularity.street);

    await scrollToText(tester, '15 minutes');
    await tester.tap(find.text('15 minutes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 minutes').last);
    await tester.pumpAndSettle();

    config = await UserStorage.getLocationContextConfig();
    expect(config.ttlMinutes, 30);
  });

  testWidgets('renders localized Chinese labels', (WidgetTester tester) async {
    await pumpLocationSettingsPage(tester, language: 'zh');

    expect(find.text('位置、地图与天气'), findsOneWidget);
    expect(find.text('让 I 知道你的位置'), findsOneWidget);
    expect(find.text('高德 Key'), findsOneWidget);
    expect(find.text('路线陪跑提醒'), findsOneWidget);
    expect(find.text('高级设置'), findsOneWidget);

    await openAdvancedSettings(tester);
    expect(find.text('逆地理编码服务商'), findsOneWidget);
    expect(find.text('上下文粒度'), findsOneWidget);
  });

  testWidgets('test button displays a fresh reverse-geocoded location', (
    WidgetTester tester,
  ) async {
    var receivedForceRefresh = false;
    var receivedIgnoreEnabled = false;
    final now = DateTime.utc(2026, 5, 15, 10);
    await pumpLocationSettingsPage(
      tester,
      config: const LocationContextConfig(
        enabled: false,
        granularity: LocationContextGranularity.neighborhood,
      ),
      loadCurrentContext: ({
        bool forceRefresh = false,
        bool ignoreEnabled = false,
      }) async {
        receivedForceRefresh = forceRefresh;
        receivedIgnoreEnabled = ignoreEnabled;
        return CurrentLocationContext(
          status: 'fresh',
          latitude: 31.230416,
          longitude: 121.473701,
          accuracyMeters: 8.5,
          source: 'device_gps + reverse_geocode',
          updatedAt: now,
          granularity: LocationContextGranularity.neighborhood,
          address: GeocodedAddress(
            city: 'Shanghai',
            district: 'Huangpu',
            neighborhood: 'People Square',
            street: 'Xizang Middle Road',
            fullAddress: 'People Square, Huangpu, Shanghai',
            provider: 'amap',
            updatedAt: now,
            confidence: 'high',
          ),
        );
      },
    );

    await scrollToTestButton(tester);
    await tester.tap(find.text('Test current location'));
    await tester.pumpAndSettle();

    expect(receivedForceRefresh, isTrue);
    expect(receivedIgnoreEnabled, isTrue);
    expect(find.textContaining('GPS: fresh'), findsOneWidget);
    expect(find.textContaining('Reverse geocode: OK'), findsOneWidget);
    expect(find.textContaining('Agent context: injected'), findsOneWidget);
    expect(
      find.textContaining('Shanghai · Huangpu · People Square'),
      findsOneWidget,
    );
    expect(
      find.textContaining('People Square, Huangpu, Shanghai'),
      findsOneWidget,
    );
    expect(find.textContaining('31.230416, 121.473701'), findsOneWidget);
  });

  testWidgets('test button displays unavailable status without crashing', (
    WidgetTester tester,
  ) async {
    await pumpLocationSettingsPage(
      tester,
      loadCurrentContext: ({
        bool forceRefresh = false,
        bool ignoreEnabled = false,
      }) async {
        return CurrentLocationContext(
          status: 'unavailable',
          source: 'device_gps',
          updatedAt: DateTime.utc(2026, 5, 15, 10),
          granularity: LocationContextGranularity.neighborhood,
          reason: 'location permission denied',
        );
      },
    );

    await scrollToTestButton(tester);
    await tester.tap(find.text('Test current location'));
    await tester.pumpAndSettle();

    expect(find.textContaining('GPS: unavailable'), findsOneWidget);
    expect(find.textContaining('Reverse geocode: unavailable'), findsOneWidget);
    expect(
      find.textContaining('Reason: location permission denied'),
      findsOneWidget,
    );
  });

  testWidgets('test button explains GPS-only reverse geocode failure', (
    WidgetTester tester,
  ) async {
    await pumpLocationSettingsPage(
      tester,
      config: const LocationContextConfig(
        enabled: true,
        provider: GeocodingProvider.amap,
        granularity: LocationContextGranularity.neighborhood,
      ),
      loadCurrentContext: ({
        bool forceRefresh = false,
        bool ignoreEnabled = false,
      }) async {
        return CurrentLocationContext(
          status: 'fresh',
          latitude: 31.230416,
          longitude: 121.473701,
          accuracyMeters: 8.5,
          source: 'device_gps',
          updatedAt: DateTime.utc(2026, 5, 15, 10),
          granularity: LocationContextGranularity.neighborhood,
          reason: 'reverse geocode unavailable (amap): amap api key is empty',
        );
      },
    );

    await scrollToTestButton(tester);
    await tester.tap(find.text('Test current location'));
    await tester.pumpAndSettle();

    expect(find.textContaining('GPS: fresh'), findsOneWidget);
    expect(find.textContaining('Provider: Amap'), findsOneWidget);
    expect(find.textContaining('Reverse geocode: unavailable'), findsOneWidget);
    expect(find.textContaining('Agent context: not injected'), findsOneWidget);
    expect(
      find.textContaining('Coordinates: 31.230416, 121.473701'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Reason: reverse geocode unavailable (amap)'),
      findsOneWidget,
    );
  });

  testWidgets('test button explains Amap fallback after OSM address failure', (
    WidgetTester tester,
  ) async {
    final now = DateTime.utc(2026, 5, 15, 10);
    await pumpLocationSettingsPage(
      tester,
      config: const LocationContextConfig(
        enabled: true,
        provider: GeocodingProvider.openStreetMap,
        granularity: LocationContextGranularity.district,
      ),
      loadCurrentContext: ({
        bool forceRefresh = false,
        bool ignoreEnabled = false,
      }) async {
        return CurrentLocationContext(
          status: 'fresh',
          latitude: 39.904200,
          longitude: 116.407400,
          accuracyMeters: 12,
          source: 'device_gps + reverse_geocode',
          updatedAt: now,
          granularity: LocationContextGranularity.district,
          reason:
              'OpenStreetMap reverse geocode failed; used Amap fallback: OSM reverse geocode error: TimeoutException',
          address: GeocodedAddress(
            city: '北京市',
            district: '东城区',
            neighborhood: '东华门街道',
            fullAddress: '北京市东城区东华门街道',
            provider: 'amap',
            updatedAt: now,
          ),
        );
      },
    );

    await scrollToTestButton(tester);
    await tester.tap(find.text('Test current location'));
    await tester.pumpAndSettle();

    expect(find.textContaining('GPS: fresh'), findsOneWidget);
    expect(
      find.textContaining('Provider: OpenStreetMap / Nominatim（实际使用：Amap）'),
      findsOneWidget,
    );
    expect(find.textContaining('Reverse geocode: OK'), findsOneWidget);
    expect(find.textContaining('北京市 · 东城区'), findsOneWidget);
    expect(
      find.textContaining('GPS 已可用；OpenStreetMap 地址解析失败，已使用高德兜底。'),
      findsOneWidget,
    );
  });

  testWidgets('test button displays a localized failure message', (
    WidgetTester tester,
  ) async {
    await pumpLocationSettingsPage(
      tester,
      loadCurrentContext: ({
        bool forceRefresh = false,
        bool ignoreEnabled = false,
      }) async {
        throw StateError('mock location failure');
      },
    );

    await scrollToTestButton(tester);
    await tester.tap(find.text('Test current location'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Failed: Bad state: mock location failure'),
      findsOneWidget,
    );
  });
}
