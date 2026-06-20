import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:memex/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceAppBlockerConfig {
  final bool enabled;
  final int defaultDurationMinutes;

  const DeviceAppBlockerConfig({
    this.enabled = false,
    this.defaultDurationMinutes = 45,
  });

  bool get isReady => enabled;

  factory DeviceAppBlockerConfig.fromJson(Map<String, dynamic> json) {
    return DeviceAppBlockerConfig(
      enabled: json['enabled'] as bool? ?? false,
      defaultDurationMinutes:
          (json['defaultDurationMinutes'] as num?)?.toInt() ?? 45,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'defaultDurationMinutes': defaultDurationMinutes,
      };

  DeviceAppBlockerConfig copyWith({
    bool? enabled,
    int? defaultDurationMinutes,
  }) {
    return DeviceAppBlockerConfig(
      enabled: enabled ?? this.enabled,
      defaultDurationMinutes:
          defaultDurationMinutes ?? this.defaultDurationMinutes,
    );
  }
}

class DeviceAppBlockerState {
  final bool active;
  final DateTime? until;
  final String reason;
  final String lastError;
  final DateTime? updatedAt;

  const DeviceAppBlockerState({
    this.active = false,
    this.until,
    this.reason = '',
    this.lastError = '',
    this.updatedAt,
  });

  factory DeviceAppBlockerState.fromJson(Map<String, dynamic> json) {
    return DeviceAppBlockerState(
      active: json['active'] as bool? ?? false,
      until: DateTime.tryParse(json['until'] as String? ?? ''),
      reason: json['reason'] as String? ?? '',
      lastError: json['lastError'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'active': active,
        if (until != null) 'until': until!.toIso8601String(),
        'reason': reason,
        'lastError': lastError,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };
}

class DeviceAppBlockerResult {
  final bool ok;
  final String action;
  final String message;
  final int? statusCode;
  final DateTime? until;

  const DeviceAppBlockerResult({
    required this.ok,
    required this.action,
    required this.message,
    this.statusCode,
    this.until,
  });

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'action': action,
        'message': message,
        if (statusCode != null) 'status_code': statusCode,
        if (until != null) 'until': until!.toIso8601String(),
      };
}

class DeviceAppBlockerService {
  DeviceAppBlockerService._();

  static final DeviceAppBlockerService instance = DeviceAppBlockerService._();

  static const int companionMaxDurationMinutes = 360;
  static const int settingsMaxDurationMinutes = 720;

  static const _configKey = 'device_app_blocker_config';
  static const _stateKey = 'device_app_blocker_state';
  static const _channel =
      MethodChannel('com.memexlab.memex/device_app_blocker');

  final _logger = getLogger('DeviceAppBlockerService');

  Future<DeviceAppBlockerConfig> getConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configKey);
    if (raw == null || raw.isEmpty) {
      return const DeviceAppBlockerConfig();
    }
    try {
      return DeviceAppBlockerConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (e) {
      _logger.warning('Failed to parse app blocker config: $e');
      return const DeviceAppBlockerConfig();
    }
  }

  Future<void> saveConfig(DeviceAppBlockerConfig config) async {
    final safeDuration =
        config.defaultDurationMinutes.clamp(1, settingsMaxDurationMinutes);
    final normalized = config.copyWith(
      defaultDurationMinutes: safeDuration,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(normalized.toJson()));
  }

  Future<DeviceAppBlockerState> getState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_stateKey);
    if (raw == null || raw.isEmpty) {
      return const DeviceAppBlockerState();
    }
    try {
      return DeviceAppBlockerState.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (e) {
      _logger.warning('Failed to parse app blocker state: $e');
      return const DeviceAppBlockerState();
    }
  }

  Future<DeviceAppBlockerResult> status() async {
    final config = await getConfig();
    final state = await getState();
    final nativeAvailable = await isNativeAccessibilityServiceEnabled();
    final nativeActive = await isNativeFocusLockActive();
    return DeviceAppBlockerResult(
      ok: config.isReady,
      action: 'status',
      message: jsonEncode({
        'configured': config.enabled,
        'enabled': config.enabled,
        'native_accessibility_enabled': nativeAvailable,
        'native_focus_lock_active': nativeActive,
        'active': state.active,
        'until': state.until?.toIso8601String(),
        'reason': state.reason,
        'last_error': state.lastError,
      }),
      until: state.until,
    );
  }

  Future<DeviceAppBlockerResult> testConnection() {
    return sendCommand(
        action: 'ping', reason: 'Connection test', source: 'settings');
  }

  Future<bool> isNativeAccessibilityServiceEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel
              .invokeMethod<bool>('isAccessibilityServiceEnabled') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isNativeFocusLockActive() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isNativeFocusLockActive') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openNativeAccessibilitySettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<bool>('openAccessibilitySettings');
  }

  Future<DeviceAppBlockerResult> sendCommand({
    required String action,
    int? durationMinutes,
    String? reason,
    String source = 'companion',
  }) async {
    final normalizedAction = action.trim().toLowerCase();
    if (!{'lock', 'unlock', 'ping'}.contains(normalizedAction)) {
      return DeviceAppBlockerResult(
        ok: false,
        action: normalizedAction,
        message: 'Unsupported app blocker action: $action',
      );
    }

    final config = await getConfig();
    if (!config.isReady) {
      return DeviceAppBlockerResult(
        ok: false,
        action: normalizedAction,
        message: 'Device app blocker is not enabled.',
      );
    }

    final lock = normalizedAction == 'lock';
    final maxDuration = _maxDurationForSource(source);
    final effectiveDuration = lock
        ? (durationMinutes ?? config.defaultDurationMinutes)
            .clamp(1, maxDuration)
        : null;
    final until = effectiveDuration == null
        ? null
        : DateTime.now().add(Duration(minutes: effectiveDuration));
    return _sendNativeAccessibilityCommand(
      action: normalizedAction,
      until: until,
      reason: reason?.trim() ?? '',
    );
  }

  int _maxDurationForSource(String source) {
    final normalized = source.trim().toLowerCase();
    if (normalized.startsWith('companion')) {
      return companionMaxDurationMinutes;
    }
    return settingsMaxDurationMinutes;
  }

  Future<DeviceAppBlockerResult> _sendNativeAccessibilityCommand({
    required String action,
    DateTime? until,
    required String reason,
  }) async {
    if (!Platform.isAndroid) {
      return DeviceAppBlockerResult(
        ok: false,
        action: action,
        message: 'Native focus lock is only available on Android.',
      );
    }
    if (action == 'ping') {
      final enabled = await isNativeAccessibilityServiceEnabled();
      return DeviceAppBlockerResult(
        ok: enabled,
        action: action,
        message: enabled
            ? 'Native Accessibility focus lock is ready.'
            : 'Enable Here I am in Android Accessibility settings first.',
      );
    }

    final enabled = action == 'lock';
    try {
      final active = await _channel.invokeMethod<bool>('setNativeFocusLock', {
            'enabled': enabled,
            if (until != null) 'untilMs': until.millisecondsSinceEpoch,
          }) ??
          false;
      final nextState = DeviceAppBlockerState(
        active: active,
        until: active ? until : null,
        reason: active ? reason : '',
        lastError: '',
        updatedAt: DateTime.now(),
      );
      await _saveState(nextState);
      return DeviceAppBlockerResult(
        ok: enabled ? active : true,
        action: action,
        message: enabled
            ? 'Native focus lock is active.'
            : 'Native focus lock is off.',
        until: active ? until : null,
      );
    } on PlatformException catch (e) {
      final message = switch (e.code) {
        'SERVICE_NOT_ENABLED' =>
          'Enable Here I am in Android Accessibility settings first.',
        'SERVICE_NOT_RUNNING' =>
          'Restart Here I am in Android Accessibility settings, then try again.',
        _ => 'Failed to control native focus lock: ${e.message ?? e.code}',
      };
      final previous = await getState();
      await _saveState(DeviceAppBlockerState(
        active: previous.active,
        until: previous.until,
        reason: previous.reason,
        lastError: message,
        updatedAt: DateTime.now(),
      ));
      return DeviceAppBlockerResult(
        ok: false,
        action: action,
        message: message,
      );
    } catch (e) {
      final message = 'Failed to control native focus lock: $e';
      final previous = await getState();
      await _saveState(DeviceAppBlockerState(
        active: previous.active,
        until: previous.until,
        reason: previous.reason,
        lastError: message,
        updatedAt: DateTime.now(),
      ));
      return DeviceAppBlockerResult(
        ok: false,
        action: action,
        message: message,
      );
    }
  }

  Future<void> _saveState(DeviceAppBlockerState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateKey, jsonEncode(state.toJson()));
  }
}
