import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:memex/utils/logger.dart';

class PhoneUsageRecord {
  const PhoneUsageRecord({
    required this.packageName,
    required this.appName,
    required this.totalTime,
    this.lastUsedAt,
  });

  final String packageName;
  final String appName;
  final Duration totalTime;
  final DateTime? lastUsedAt;

  factory PhoneUsageRecord.fromJson(Map<dynamic, dynamic> json) {
    final totalTimeMs = (json['totalTimeMs'] as num?)?.toInt() ?? 0;
    final lastTimeUsedMs = (json['lastTimeUsedMs'] as num?)?.toInt() ?? 0;
    final packageName = json['packageName'] as String? ?? '';
    return PhoneUsageRecord(
      packageName: packageName,
      appName: (json['appName'] as String?)?.trim().isNotEmpty == true
          ? json['appName'] as String
          : packageName,
      totalTime: Duration(milliseconds: totalTimeMs),
      lastUsedAt: lastTimeUsedMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastTimeUsedMs)
          : null,
    );
  }
}

class PhoneUsageSnapshot {
  const PhoneUsageSnapshot({
    required this.startTime,
    required this.endTime,
    required this.records,
  });

  final DateTime startTime;
  final DateTime endTime;
  final List<PhoneUsageRecord> records;

  Duration get totalTime => records.fold(
        Duration.zero,
        (sum, record) => sum + record.totalTime,
      );
}

abstract class PhoneUsagePlatform {
  Future<bool> isUsageAccessGranted();

  Future<void> openUsageAccessSettings();

  Future<List<PhoneUsageRecord>> queryUsageStats({
    required DateTime startTime,
    required DateTime endTime,
    int limit = 20,
  });
}

class MethodChannelPhoneUsagePlatform implements PhoneUsagePlatform {
  const MethodChannelPhoneUsagePlatform();

  static const MethodChannel _channel =
      MethodChannel('com.memexlab.memex/phone_usage');

  bool get _isSupportedPlatform => !kIsWeb && Platform.isAndroid;

  @override
  Future<bool> isUsageAccessGranted() async {
    if (!_isSupportedPlatform) return false;
    return await _channel.invokeMethod<bool>('isUsageAccessGranted') ?? false;
  }

  @override
  Future<void> openUsageAccessSettings() async {
    if (!_isSupportedPlatform) return;
    await _channel.invokeMethod<void>('openUsageAccessSettings');
  }

  @override
  Future<List<PhoneUsageRecord>> queryUsageStats({
    required DateTime startTime,
    required DateTime endTime,
    int limit = 20,
  }) async {
    if (!_isSupportedPlatform) return const [];
    final rows = await _channel.invokeListMethod<dynamic>('queryUsageStats', {
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'limit': limit,
    });
    return (rows ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map(PhoneUsageRecord.fromJson)
        .where((record) => record.totalTime > Duration.zero)
        .toList(growable: false);
  }
}

class PhoneUsageService {
  PhoneUsageService({
    PhoneUsagePlatform? platform,
    DateTime Function()? now,
    bool? isSupported,
  })  : _platform = platform ?? const MethodChannelPhoneUsagePlatform(),
        _now = now ?? DateTime.now,
        _isSupportedOverride = isSupported;

  static final PhoneUsageService instance = PhoneUsageService();

  final PhoneUsagePlatform _platform;
  final DateTime Function() _now;
  final bool? _isSupportedOverride;
  final _logger = getLogger('PhoneUsageService');

  bool get isSupported =>
      _isSupportedOverride ?? (!kIsWeb && Platform.isAndroid);

  Future<bool> isUsageAccessGranted() => _platform.isUsageAccessGranted();

  Future<void> openUsageAccessSettings() {
    return _platform.openUsageAccessSettings();
  }

  Future<PhoneUsageSnapshot> loadToday({int limit = 20}) {
    final now = _now();
    final start = DateTime(now.year, now.month, now.day);
    return loadRange(startTime: start, endTime: now, limit: limit);
  }

  Future<PhoneUsageSnapshot> loadRange({
    required DateTime startTime,
    required DateTime endTime,
    int limit = 20,
  }) async {
    if (!isSupported) {
      return PhoneUsageSnapshot(
        startTime: startTime,
        endTime: endTime,
        records: const [],
      );
    }
    try {
      final records = await _platform.queryUsageStats(
        startTime: startTime,
        endTime: endTime,
        limit: limit,
      );
      return PhoneUsageSnapshot(
        startTime: startTime,
        endTime: endTime,
        records: records,
      );
    } on PlatformException catch (e, stackTrace) {
      _logger.warning('Failed to load phone usage: ${e.code}', e, stackTrace);
      rethrow;
    } catch (e, stackTrace) {
      _logger.warning('Failed to load phone usage', e, stackTrace);
      rethrow;
    }
  }
}
