import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/phone_usage_service.dart';

void main() {
  test('parses usage records from platform rows', () {
    final record = PhoneUsageRecord.fromJson({
      'packageName': 'com.example.app',
      'appName': 'Example',
      'totalTimeMs': 90 * 1000,
      'lastTimeUsedMs': 1718000000000,
    });

    expect(record.packageName, 'com.example.app');
    expect(record.appName, 'Example');
    expect(record.totalTime, const Duration(seconds: 90));
    expect(
        record.lastUsedAt, DateTime.fromMillisecondsSinceEpoch(1718000000000));
  });

  test('loadToday queries from local midnight to now', () async {
    final now = DateTime(2026, 6, 14, 15, 30);
    final platform = _FakePhoneUsagePlatform([
      const PhoneUsageRecord(
        packageName: 'com.chat',
        appName: 'Chat',
        totalTime: Duration(minutes: 42),
      ),
    ]);
    final service = PhoneUsageService(
      platform: platform,
      now: () => now,
      isSupported: true,
    );

    final snapshot = await service.loadToday();

    expect(snapshot.startTime, DateTime(2026, 6, 14));
    expect(snapshot.endTime, now);
    expect(snapshot.totalTime, const Duration(minutes: 42));
    expect(platform.lastStartTime, DateTime(2026, 6, 14));
    expect(platform.lastEndTime, now);
  });
}

class _FakePhoneUsagePlatform implements PhoneUsagePlatform {
  _FakePhoneUsagePlatform(this.records);

  final List<PhoneUsageRecord> records;
  DateTime? lastStartTime;
  DateTime? lastEndTime;

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
    lastStartTime = startTime;
    lastEndTime = endTime;
    return records;
  }
}
