import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/built_in_tools/phone_usage_tool.dart';
import 'package:memex/data/services/phone_usage_service.dart';

void main() {
  test('PhoneUsageQuery returns local usage summary', () async {
    final service = PhoneUsageService(
      platform: _FakePhoneUsagePlatform([
        const PhoneUsageRecord(
          packageName: 'com.example.chat',
          appName: 'Chat',
          totalTime: Duration(minutes: 35),
        ),
      ]),
      isSupported: true,
    );
    final tool = buildPhoneUsageQueryTool(service: service);

    final raw = await tool.executable!({
      'range': 'today',
      'limit': 5,
    });
    final json = jsonDecode(raw as String) as Map<String, dynamic>;

    expect(json['success'], true);
    expect(json['total_minutes'], 35);
    expect(json['apps'], isA<List<dynamic>>());
    expect((json['apps'] as List).first['app_name'], 'Chat');
  });
}

class _FakePhoneUsagePlatform implements PhoneUsagePlatform {
  _FakePhoneUsagePlatform(this.records);

  final List<PhoneUsageRecord> records;

  @override
  Future<bool> isUsageAccessGranted() async => true;

  @override
  Future<void> openUsageAccessSettings() async {}

  @override
  Future<List<PhoneUsageRecord>> queryUsageStats({
    required DateTime startTime,
    required DateTime endTime,
    int limit = 20,
  }) async {
    return records.take(limit).toList(growable: false);
  }
}
