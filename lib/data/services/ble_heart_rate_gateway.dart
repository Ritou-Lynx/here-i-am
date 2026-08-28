import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

enum BleHeartRateStatus {
  unconfigured,
  stopped,
  connecting,
  live,
  stale,
  reconnecting,
  disconnected,
  permissionDenied,
  bluetoothOff,
  unsupported,
  malformedData,
  unknown,
}

class BleHeartRateSample {
  const BleHeartRateSample({
    required this.timestamp,
    required this.bpm,
    required this.contactSupported,
    required this.contactDetected,
    required this.energyExpended,
    required this.rrIntervalsSeconds,
  });

  factory BleHeartRateSample.fromMap(Map<String, dynamic> map) {
    return BleHeartRateSample(
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(_asInt(map['timestampMs'])),
      bpm: _asInt(map['bpm']),
      contactSupported: map['contactSupported'] == true,
      contactDetected: map['contactDetected'] as bool?,
      energyExpended: (map['energyExpended'] as num?)?.toInt(),
      rrIntervalsSeconds: (map['rrIntervalsSeconds'] as List? ?? const [])
          .whereType<num>()
          .map((value) => value.toDouble())
          .toList(growable: false),
    );
  }

  final DateTime timestamp;
  final int bpm;
  final bool contactSupported;
  final bool? contactDetected;
  final int? energyExpended;
  final List<double> rrIntervalsSeconds;
}

class BleHeartRateSnapshot {
  const BleHeartRateSnapshot({
    required this.status,
    required this.configured,
    required this.enabled,
    required this.permissionState,
    required this.notificationPermission,
    required this.bluetoothState,
    required this.supported,
    this.reason,
    this.deviceName,
    this.deviceId,
    this.lastSample,
    this.rrSeen = false,
    this.retryAt,
  });

  factory BleHeartRateSnapshot.fromMap(Map<String, dynamic> map) {
    final sample = _stringMap(map['lastSample']);
    return BleHeartRateSnapshot(
      status: _parseStatus(map['status'] as String?),
      configured: map['configured'] == true,
      enabled: map['enabled'] == true,
      permissionState: map['permissionState'] as String? ?? 'unknown',
      notificationPermission:
          map['notificationPermission'] as String? ?? 'unknown',
      bluetoothState: map['bluetoothState'] as String? ?? 'unknown',
      supported: map['supported'] != false,
      reason: map['reason'] as String?,
      deviceName: map['deviceName'] as String?,
      deviceId: map['deviceId'] as String?,
      lastSample: sample == null ? null : BleHeartRateSample.fromMap(sample),
      rrSeen: map['rrSeen'] == true,
      retryAt: _dateFromMs(map['retryAtMs']),
    );
  }

  static const empty = BleHeartRateSnapshot(
    status: BleHeartRateStatus.unconfigured,
    configured: false,
    enabled: false,
    permissionState: 'unknown',
    notificationPermission: 'unknown',
    bluetoothState: 'unknown',
    supported: true,
  );

  final BleHeartRateStatus status;
  final bool configured;
  final bool enabled;
  final String permissionState;
  final String notificationPermission;
  final String bluetoothState;
  final bool supported;
  final String? reason;
  final String? deviceName;
  final String? deviceId;
  final BleHeartRateSample? lastSample;
  final bool rrSeen;
  final DateTime? retryAt;
}

class BleHeartRateDevice {
  const BleHeartRateDevice({
    required this.deviceId,
    required this.name,
    required this.rssi,
  });

  factory BleHeartRateDevice.fromMap(Map<String, dynamic> map) =>
      BleHeartRateDevice(
        deviceId: map['deviceId'] as String? ?? '',
        name: (map['name'] as String?)?.trim().isNotEmpty == true
            ? (map['name'] as String).trim()
            : '未命名心率设备',
        rssi: (map['rssi'] as num?)?.toInt() ?? -127,
      );

  final String deviceId;
  final String name;
  final int rssi;
}

sealed class BleHeartRateGatewayEvent {
  const BleHeartRateGatewayEvent();
}

class BleHeartRateSnapshotEvent extends BleHeartRateGatewayEvent {
  const BleHeartRateSnapshotEvent(this.snapshot);
  final BleHeartRateSnapshot snapshot;
}

class BleHeartRateScanResultEvent extends BleHeartRateGatewayEvent {
  const BleHeartRateScanResultEvent(this.device);
  final BleHeartRateDevice device;
}

class BleHeartRateScanStateEvent extends BleHeartRateGatewayEvent {
  const BleHeartRateScanStateEvent(this.state, {this.count = 0});
  final String state;
  final int count;
}

abstract interface class BleHeartRateGateway {
  static BleHeartRateGateway instance = PlatformBleHeartRateGateway();

  Stream<BleHeartRateGatewayEvent> get events;
  Future<BleHeartRateSnapshot> getSnapshot(String userId);
  Future<Map<String, dynamic>> getPlatformState();
  Future<bool> requestPermissions();
  Future<void> openAppSettings();
  Future<void> openBluetoothSettings();
  Future<void> startScan(String userId, {Duration timeout});
  Future<void> stopScan();
  Future<BleHeartRateSnapshot> selectAndEnable(
    String userId,
    BleHeartRateDevice device,
  );
  Future<BleHeartRateSnapshot> stop(String userId);
  Future<BleHeartRateSnapshot> forget(String userId);
  Future<List<Map<String, dynamic>>> getRecentDiagnostics(String userId);
}

class PlatformBleHeartRateGateway implements BleHeartRateGateway {
  PlatformBleHeartRateGateway({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    bool? isAndroid,
  })  : _methodChannel = methodChannel ?? const MethodChannel(_methodName),
        _eventChannel = eventChannel ?? const EventChannel(_eventName),
        _isAndroid = isAndroid ?? Platform.isAndroid;

  static const _methodName = 'com.memexlab.memex/ble_heart_rate';
  static const _eventName = 'com.memexlab.memex/ble_heart_rate_events';
  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final bool _isAndroid;
  Stream<BleHeartRateGatewayEvent>? _events;

  @override
  Stream<BleHeartRateGatewayEvent> get events => _events ??= !_isAndroid
      ? const Stream<BleHeartRateGatewayEvent>.empty()
      : _eventChannel
          .receiveBroadcastStream()
          .map(_decodeEvent)
          .where((event) => event != null)
          .map((event) => event!);

  @override
  Future<BleHeartRateSnapshot> getSnapshot(String userId) async {
    if (!_isAndroid) return BleHeartRateSnapshot.empty;
    final value = await _methodChannel.invokeMapMethod<String, dynamic>(
      'getSnapshot',
      {'userId': userId},
    );
    return BleHeartRateSnapshot.fromMap(value ?? const {});
  }

  @override
  Future<Map<String, dynamic>> getPlatformState() async {
    if (!_isAndroid) {
      return const {
        'supported': false,
        'permissionState': 'unsupported',
        'notificationPermission': 'unsupported',
        'bluetoothState': 'unsupported',
      };
    }
    return await _methodChannel.invokeMapMethod<String, dynamic>(
          'getPlatformState',
        ) ??
        const {};
  }

  @override
  Future<bool> requestPermissions() async {
    if (!_isAndroid) return false;
    final value = await _methodChannel.invokeMapMethod<String, dynamic>(
      'requestPermissions',
    );
    return value?['requested'] == true;
  }

  @override
  Future<void> openAppSettings() => _isAndroid
      ? _methodChannel.invokeMethod<void>('openAppSettings')
      : Future<void>.value();

  @override
  Future<void> openBluetoothSettings() => _isAndroid
      ? _methodChannel.invokeMethod<void>('openBluetoothSettings')
      : Future<void>.value();

  @override
  Future<void> startScan(
    String userId, {
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _isAndroid
          ? _methodChannel.invokeMethod<void>('startScan', {
              'userId': userId,
              'timeoutMs': timeout.inMilliseconds,
            })
          : Future<void>.value();

  @override
  Future<void> stopScan() => _isAndroid
      ? _methodChannel.invokeMethod<void>('stopScan')
      : Future<void>.value();

  @override
  Future<BleHeartRateSnapshot> selectAndEnable(
    String userId,
    BleHeartRateDevice device,
  ) async {
    if (!_isAndroid) return BleHeartRateSnapshot.empty;
    final value = await _methodChannel.invokeMapMethod<String, dynamic>(
      'selectAndEnable',
      {'userId': userId, 'deviceId': device.deviceId, 'name': device.name},
    );
    return BleHeartRateSnapshot.fromMap(value ?? const {});
  }

  @override
  Future<BleHeartRateSnapshot> stop(String userId) =>
      _snapshotCommand('stop', userId);

  @override
  Future<BleHeartRateSnapshot> forget(String userId) =>
      _snapshotCommand('forget', userId);

  Future<BleHeartRateSnapshot> _snapshotCommand(
    String method,
    String userId,
  ) async {
    if (!_isAndroid) return BleHeartRateSnapshot.empty;
    final value = await _methodChannel.invokeMapMethod<String, dynamic>(
      method,
      {'userId': userId},
    );
    return BleHeartRateSnapshot.fromMap(value ?? const {});
  }

  @override
  Future<List<Map<String, dynamic>>> getRecentDiagnostics(String userId) async {
    if (!_isAndroid) return const [];
    final value = await _methodChannel.invokeListMethod<dynamic>(
      'getRecentDiagnostics',
      {'userId': userId},
    );
    return (value ?? const [])
        .map(_stringMap)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  BleHeartRateGatewayEvent? _decodeEvent(dynamic value) {
    final map = _stringMap(value);
    if (map == null) return null;
    switch (map['type']) {
      case 'snapshot':
        final snapshot = _stringMap(map['snapshot']);
        return snapshot == null
            ? null
            : BleHeartRateSnapshotEvent(BleHeartRateSnapshot.fromMap(snapshot));
      case 'scanResult':
        final device = _stringMap(map['device']);
        return device == null
            ? null
            : BleHeartRateScanResultEvent(BleHeartRateDevice.fromMap(device));
      case 'scanState':
        return BleHeartRateScanStateEvent(
          map['state'] as String? ?? 'unknown',
          count: (map['count'] as num?)?.toInt() ?? 0,
        );
      default:
        return null;
    }
  }
}

BleHeartRateStatus _parseStatus(String? value) {
  return BleHeartRateStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => BleHeartRateStatus.unknown,
  );
}

Map<String, dynamic>? _stringMap(dynamic value) {
  if (value is! Map) return null;
  return value.map((key, value) => MapEntry(key.toString(), value));
}

int _asInt(dynamic value) => (value as num?)?.toInt() ?? 0;

DateTime? _dateFromMs(dynamic value) {
  final milliseconds = (value as num?)?.toInt();
  return milliseconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(milliseconds);
}
