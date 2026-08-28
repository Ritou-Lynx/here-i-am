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

  @override
  Stream<BleHeartRateGatewayEvent> get events => controller.stream;

  void emitSnapshot(BleHeartRateSnapshot value) {
    current = value;
    controller.add(BleHeartRateSnapshotEvent(value));
  }

  Future<void> dispose() => controller.close();

  @override
  Future<BleHeartRateSnapshot> getSnapshot(String userId) async => current;

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
  ) async =>
      current;

  @override
  Future<BleHeartRateSnapshot> stop(String userId) async => current;

  @override
  Future<BleHeartRateSnapshot> forget(String userId) async => current;

  @override
  Future<List<Map<String, dynamic>>> getRecentDiagnostics(
          String userId) async =>
      const [];
}
