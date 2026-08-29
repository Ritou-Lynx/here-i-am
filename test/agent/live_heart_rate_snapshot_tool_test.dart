import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/built_in_tools/live_heart_rate_snapshot_tool.dart';
import 'package:memex/data/services/ble_heart_rate_gateway.dart';

import '../data/services/ble_heart_rate_gateway_test.dart';

void main() {
  test('returns only a fresh live sample to the companion', () async {
    final fake = FakeBleHeartRateGateway()
      ..current = _snapshot(
        status: BleHeartRateStatus.live,
        sampleTime: DateTime(2026, 8, 29, 18, 0, 5),
        bpm: 72,
      );
    final tool = buildLiveHeartRateSnapshotTool(
      userId: 'lynx',
      gateway: fake,
      now: () => DateTime(2026, 8, 29, 18, 0, 10),
    );

    final raw = await tool.executable!(const <String, dynamic>{});
    final json = jsonDecode(raw as String) as Map<String, dynamic>;

    expect(json['success'], isTrue);
    expect(json['status'], 'live');
    expect(json['bpm'], 72);
    expect(json['age_ms'], 5000);
    expect(json['rr_present'], isFalse);
    expect(json['contact'], {'supported': false});
    expect(json['sleep_inference'], 'not_supported_from_single_sample');
    expect(json, isNot(contains('device_id')));
    expect(fake.lastSnapshotUserId, 'lynx');
    await fake.dispose();
  });

  test('fails closed when a nominally live sample is older than 15 seconds',
      () async {
    final fake = FakeBleHeartRateGateway()
      ..current = _snapshot(
        status: BleHeartRateStatus.live,
        sampleTime: DateTime(2026, 8, 29, 18, 0),
        bpm: 72,
      );
    final tool = buildLiveHeartRateSnapshotTool(
      userId: 'lynx',
      gateway: fake,
      now: () => DateTime(2026, 8, 29, 18, 0, 16),
    );

    final raw = await tool.executable!(const <String, dynamic>{});
    final json = jsonDecode(raw as String) as Map<String, dynamic>;

    expect(json['success'], isFalse);
    expect(json['status'], 'stale');
    expect(json['reason'], 'sample_stale');
    expect(json, isNot(contains('bpm')));
    expect(json, isNot(contains('timestamp')));
    expect(json, isNot(contains('contact')));
    await fake.dispose();
  });

  test('accepts a live sample exactly at the 15 second boundary', () async {
    final fake = FakeBleHeartRateGateway()
      ..current = _snapshot(
        status: BleHeartRateStatus.live,
        sampleTime: DateTime(2026, 8, 29, 18, 0),
        bpm: 72,
      );
    final tool = buildLiveHeartRateSnapshotTool(
      userId: 'lynx',
      gateway: fake,
      now: () => DateTime(2026, 8, 29, 18, 0, 15),
    );

    final raw = await tool.executable!(const <String, dynamic>{});
    final json = jsonDecode(raw as String) as Map<String, dynamic>;

    expect(json['success'], isTrue);
    expect(json['age_ms'], 15000);
    await fake.dispose();
  });

  test('fails closed for a future-dated sample', () async {
    final fake = FakeBleHeartRateGateway()
      ..current = _snapshot(
        status: BleHeartRateStatus.live,
        sampleTime: DateTime(2026, 8, 29, 18, 0, 11),
        bpm: 72,
      );
    final tool = buildLiveHeartRateSnapshotTool(
      userId: 'lynx',
      gateway: fake,
      now: () => DateTime(2026, 8, 29, 18, 0, 10),
    );

    final raw = await tool.executable!(const <String, dynamic>{});
    final json = jsonDecode(raw as String) as Map<String, dynamic>;

    expect(json['success'], isFalse);
    expect(json['reason'], 'invalid_sample_time');
    expect(json, isNot(contains('bpm')));
    await fake.dispose();
  });

  test('fails closed for a zero BPM sample', () async {
    final fake = FakeBleHeartRateGateway()
      ..current = _snapshot(
        status: BleHeartRateStatus.live,
        sampleTime: DateTime(2026, 8, 29, 18, 0, 9),
        bpm: 0,
      );
    final tool = buildLiveHeartRateSnapshotTool(
      userId: 'lynx',
      gateway: fake,
      now: () => DateTime(2026, 8, 29, 18, 0, 10),
    );

    final raw = await tool.executable!(const <String, dynamic>{});
    final json = jsonDecode(raw as String) as Map<String, dynamic>;

    expect(json['success'], isFalse);
    expect(json['reason'], 'sample_unavailable');
    expect(json, isNot(contains('bpm')));
    await fake.dispose();
  });

  test('fails closed when a live-looking snapshot is disabled', () async {
    final fake = FakeBleHeartRateGateway()
      ..current = _snapshot(
        status: BleHeartRateStatus.live,
        sampleTime: DateTime(2026, 8, 29, 18, 0, 9),
        bpm: 72,
        enabled: false,
      );
    final tool = buildLiveHeartRateSnapshotTool(
      userId: 'lynx',
      gateway: fake,
      now: () => DateTime(2026, 8, 29, 18, 0, 10),
    );

    final raw = await tool.executable!(const <String, dynamic>{});
    final json = jsonDecode(raw as String) as Map<String, dynamic>;

    expect(json['success'], isFalse);
    expect(json['reason'], 'not_enabled');
    expect(json, isNot(contains('bpm')));
    await fake.dispose();
  });

  test('does not expose the last sample from a disconnected snapshot',
      () async {
    final fake = FakeBleHeartRateGateway()
      ..current = _snapshot(
        status: BleHeartRateStatus.disconnected,
        sampleTime: DateTime(2026, 8, 29, 18, 0, 9),
        bpm: 72,
        reason: 'sample_timeout_reconnect',
      );
    final tool = buildLiveHeartRateSnapshotTool(
      userId: 'lynx',
      gateway: fake,
      now: () => DateTime(2026, 8, 29, 18, 0, 10),
    );

    final raw = await tool.executable!(const <String, dynamic>{});
    final json = jsonDecode(raw as String) as Map<String, dynamic>;

    expect(json['success'], isFalse);
    expect(json['status'], 'disconnected');
    expect(json['reason'], 'sample_timeout_reconnect');
    expect(json, isNot(contains('bpm')));
    await fake.dispose();
  });

  test('platform failures stay unavailable instead of escaping to the agent',
      () async {
    final fake = _ThrowingGateway();
    final tool = buildLiveHeartRateSnapshotTool(
      userId: 'lynx',
      gateway: fake,
    );

    final raw = await tool.executable!(const <String, dynamic>{});
    final json = jsonDecode(raw as String) as Map<String, dynamic>;

    expect(json, {
      'success': false,
      'status': 'unavailable',
      'reason': 'query_failed',
    });
    await fake.dispose();
  });
}

BleHeartRateSnapshot _snapshot({
  required BleHeartRateStatus status,
  required DateTime sampleTime,
  required int bpm,
  String? reason,
  bool enabled = true,
}) {
  return BleHeartRateSnapshot(
    status: status,
    configured: true,
    enabled: enabled,
    permissionState: 'granted',
    notificationPermission: 'granted',
    bluetoothState: 'on',
    supported: true,
    reason: reason,
    deviceName: 'COROS HEART RATE',
    deviceId: 'C7:C1:82:0F:70:4C',
    lastSample: BleHeartRateSample(
      timestamp: sampleTime,
      bpm: bpm,
      contactSupported: false,
      contactDetected: null,
      energyExpended: null,
      rrIntervalsSeconds: const [],
    ),
  );
}

class _ThrowingGateway extends FakeBleHeartRateGateway {
  @override
  Future<BleHeartRateSnapshot> getSnapshot(String userId) {
    throw StateError('platform unavailable');
  }
}
