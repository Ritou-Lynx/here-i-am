import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/ble_heart_rate_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/ble_heart_rate');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('platform gateway decodes a complete native snapshot', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getSnapshot');
      expect((call.arguments as Map)['userId'], 'lynx');
      return {
        'status': 'live',
        'configured': true,
        'enabled': true,
        'permissionState': 'granted',
        'notificationPermission': 'denied',
        'bluetoothState': 'on',
        'supported': true,
        'deviceName': 'COROS HR Monitor',
        'rrSeen': true,
        'lastSample': {
          'timestampMs': 1700000000000,
          'bpm': 63,
          'contactSupported': true,
          'contactDetected': true,
          'energyExpended': 12,
          'rrIntervalsSeconds': [1.0, 0.984375],
        },
      };
    });
    final gateway = PlatformBleHeartRateGateway(
      methodChannel: channel,
      isAndroid: true,
    );

    final snapshot = await gateway.getSnapshot('lynx');

    expect(snapshot.status, BleHeartRateStatus.live);
    expect(snapshot.deviceName, 'COROS HR Monitor');
    expect(snapshot.notificationPermission, 'denied');
    expect(snapshot.rrSeen, isTrue);
    expect(snapshot.lastSample?.bpm, 63);
    expect(snapshot.lastSample?.contactDetected, isTrue);
    expect(snapshot.lastSample?.rrIntervalsSeconds, [1.0, 0.984375]);
  });

  test('permission request reports pending system request, not grant',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'requestPermissions');
      return {
        'requested': true,
        'permissions': ['android.permission.BLUETOOTH_SCAN'],
      };
    });
    final gateway = PlatformBleHeartRateGateway(
      methodChannel: channel,
      isAndroid: true,
    );

    expect(await gateway.requestPermissions(), isTrue);
  });

  test('non-Android gateway never touches platform channels', () async {
    var channelTouched = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      channelTouched = true;
      throw StateError('must not be called');
    });
    final gateway = PlatformBleHeartRateGateway(
      methodChannel: channel,
      isAndroid: false,
    );

    expect(await gateway.events.toList(), isEmpty);
    expect((await gateway.getSnapshot('lynx')).configured, isFalse);
    expect(await gateway.requestPermissions(), isFalse);
    await gateway.openAppSettings();
    await gateway.openBluetoothSettings();
    await gateway.startScan('lynx');
    await gateway.stopScan();
    expect(await gateway.getRecentDiagnostics('lynx'), isEmpty);
    expect(channelTouched, isFalse);
  });

  test('fake gateway preserves ordered status flow', () async {
    final fake = FakeBleHeartRateGateway();
    final statuses = <BleHeartRateStatus>[];
    final subscription = fake.events.listen((event) {
      if (event is BleHeartRateSnapshotEvent) {
        statuses.add(event.snapshot.status);
      }
    });

    fake.emitSnapshot(snapshot(BleHeartRateStatus.connecting));
    fake.emitSnapshot(snapshot(BleHeartRateStatus.live, bpm: 71));
    fake.emitSnapshot(snapshot(BleHeartRateStatus.stale, bpm: 71));
    fake.emitSnapshot(snapshot(BleHeartRateStatus.reconnecting, bpm: 71));
    await Future<void>.delayed(Duration.zero);

    expect(statuses, [
      BleHeartRateStatus.connecting,
      BleHeartRateStatus.live,
      BleHeartRateStatus.stale,
      BleHeartRateStatus.reconnecting,
    ]);
    await subscription.cancel();
    await fake.dispose();
  });

  test('night methods send parameters and decode all summary fields', () async {
    final data = syntheticNightSummary();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'listNightSummaries'
          ? [data, {'night': '2026-10-19', 'samples': 0}]
          : {'jsonlPath': 'synthetic.jsonl', 'csvPath': 'synthetic.csv', 'summary': data};
    });
    final gateway = PlatformBleHeartRateGateway(methodChannel: channel, isAndroid: true);
    final nights = await gateway.listNightSummaries('synthetic-user');
    expect(calls.single.arguments, {'userId': 'synthetic-user', 'nights': 7});
    expect(nights.first.night, '2026-10-20');
    expect(nights.first.samples, 3);
    expect(nights.first.suspectSamples, 1);
    expect(nights.first.statusEvents, 5);
    expect(nights.first.disconnectEvents, 4);
    expect(nights.first.gapCount, 1);
    expect(nights.first.maxGapSeconds, 119);
    expect(nights.first.totalGapSeconds, 119);
    expect(nights.first.coveredMinutes, 2);
    expect(nights.first.spanMinutes, 3);
    expect(nights.first.bpmMedian, 80.5);
    expect(nights.first.bpmMin, 80);
    expect(nights.first.bpmMax, 81);
    expect(nights.first.malformedLines, 1);
    expect(nights.first.windowStartMs, data['windowStartMs']);
    expect(nights.first.windowEndMs, data['windowEndMs']);
    expect(nights.first.firstSampleMs, data['firstSampleMs']);
    expect(nights.first.lastSampleMs, data['lastSampleMs']);
    expect(nights.last.firstSampleMs, isNull);
    expect(nights.last.spanMinutes, isNull);
    expect(nights.last.bpmMedian, isNull);
    await gateway.listNightSummaries('synthetic-user', nights: 2);
    expect(calls.last.arguments, {'userId': 'synthetic-user', 'nights': 2});
    final exported = await gateway.exportNight('synthetic-user', '2026-10-20');
    expect(calls.last.method, 'exportNight');
    expect(calls.last.arguments, {'userId': 'synthetic-user', 'night': '2026-10-20'});
    expect(exported?.jsonlPath, 'synthetic.jsonl');
    expect(exported?.csvPath, 'synthetic.csv');
    expect(exported?.summary.night, '2026-10-20');
  });

  test('night methods preserve native error codes', () async {
    final gateway = PlatformBleHeartRateGateway(methodChannel: channel, isAndroid: true);
    for (final code in ['USER_REQUIRED', 'INVALID_NIGHT', 'EXPORT_FAILED']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: code));
      await expectLater(gateway.exportNight('synthetic-user', 'invalid'),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)));
      if (code != 'INVALID_NIGHT') {
        await expectLater(gateway.listNightSummaries('synthetic-user'),
            throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)));
      }
    }
  });

  test('non-Android night methods do not invoke channels', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => fail('unexpected platform call'));
    final gateway = PlatformBleHeartRateGateway(methodChannel: channel, isAndroid: false);
    expect(await gateway.listNightSummaries('synthetic-user'), isEmpty);
    expect(await gateway.exportNight('synthetic-user', '2026-10-20'), isNull);
  });
}

BleHeartRateSnapshot snapshot(BleHeartRateStatus status, {int? bpm}) {
  return BleHeartRateSnapshot(
    status: status,
    configured: status != BleHeartRateStatus.unconfigured,
    enabled: status != BleHeartRateStatus.unconfigured &&
        status != BleHeartRateStatus.stopped,
    permissionState: 'granted',
    notificationPermission: 'granted',
    bluetoothState: 'on',
    supported: true,
    deviceName: 'Test HRS',
    rrSeen: bpm != null,
    lastSample: bpm == null
        ? null
        : BleHeartRateSample(
            timestamp: DateTime(2026, 8, 29, 8, 0),
            bpm: bpm,
            contactSupported: true,
            contactDetected: true,
            energyExpended: null,
            rrIntervalsSeconds: const [1.0],
          ),
  );
}

class FakeBleHeartRateGateway implements BleHeartRateGateway {
  final controller = StreamController<BleHeartRateGatewayEvent>.broadcast();
  BleHeartRateSnapshot current = snapshot(BleHeartRateStatus.unconfigured);
  Map<String, dynamic> platformState = const {
    'supported': true,
    'permissionState': 'granted',
    'notificationPermission': 'granted',
    'bluetoothState': 'on',
  };
  bool permissionRequestOpened = true;
  int selectAndEnableCalls = 0;
  BleHeartRateDevice? lastSelectedDevice;
  String? lastSnapshotUserId;

  @override
  Stream<BleHeartRateGatewayEvent> get events => controller.stream;

  void emitSnapshot(BleHeartRateSnapshot value) {
    current = value;
    controller.add(BleHeartRateSnapshotEvent(value));
  }

  void emitScanResult(BleHeartRateDevice device) {
    controller.add(BleHeartRateScanResultEvent(device));
  }

  Future<void> dispose() => controller.close();

  @override
  Future<BleHeartRateSnapshot> getSnapshot(String userId) async {
    lastSnapshotUserId = userId;
    return current;
  }

  @override
  Future<Map<String, dynamic>> getPlatformState() async => platformState;

  @override
  Future<bool> requestPermissions() async => permissionRequestOpened;

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> openBluetoothSettings() async {}

  @override
  Future<void> startScan(String userId,
      {Duration timeout = const Duration(seconds: 10)}) async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<BleHeartRateSnapshot> selectAndEnable(
    String userId,
    BleHeartRateDevice device,
  ) async {
    selectAndEnableCalls += 1;
    lastSelectedDevice = device;
    return current;
  }

  @override
  Future<BleHeartRateSnapshot> stop(String userId) async => current;

  @override
  Future<BleHeartRateSnapshot> forget(String userId) async => current;

  @override
  Future<List<Map<String, dynamic>>> getRecentDiagnostics(
          String userId) async =>
      const [];

  List<BleHeartRateNightSummary> nightSummaries = [];
  bool failNightRead = false;
  bool failNightExport = false;
  int nightReadCalls = 0;
  String? exportedNight;
  String? exportUserId;

  @override
  Future<List<BleHeartRateNightSummary>> listNightSummaries(
      String userId, {int nights = 7}) async {
    nightReadCalls++;
    if (failNightRead) throw PlatformException(code: 'EXPORT_FAILED');
    return nightSummaries;
  }

  @override
  Future<BleHeartRateNightExport?> exportNight(String userId, String night) async {
    exportedNight = night;
    exportUserId = userId;
    if (failNightExport) throw PlatformException(code: 'EXPORT_FAILED', message: 'internal detail');
    return BleHeartRateNightExport.fromMap({
      'jsonlPath': 'synthetic.jsonl', 'csvPath': 'synthetic.csv',
      'summary': syntheticNightSummary(),
    });
  }
}

Map<String, dynamic> syntheticNightSummary() => {
  'night': '2026-10-20',
  'windowStartMs': DateTime.parse('2026-10-20T18:00:00+08:00').millisecondsSinceEpoch,
  'windowEndMs': DateTime.parse('2026-10-21T12:00:00+08:00').millisecondsSinceEpoch,
  'firstSampleMs': DateTime.parse('2026-10-20T23:59:00+08:00').millisecondsSinceEpoch,
  'lastSampleMs': DateTime.parse('2026-10-21T00:01:00+08:00').millisecondsSinceEpoch,
  'samples': 3, 'suspectSamples': 1, 'statusEvents': 5, 'disconnectEvents': 4,
  'gapCount': 1, 'maxGapSeconds': 119, 'totalGapSeconds': 119,
  'coveredMinutes': 2, 'spanMinutes': 3,
  'bpmMedian': 80.5, 'bpmMin': 80, 'bpmMax': 81, 'malformedLines': 1,
};
