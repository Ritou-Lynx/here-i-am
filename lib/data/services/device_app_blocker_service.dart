import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:memex/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceAppBlockerConfig {
  static const defaultIntentAction = 'com.memexlab.hereiam.APP_BLOCKER_COMMAND';
  static const defaultIntentUrl = 'intent://$defaultIntentAction';

  final bool enabled;
  final String webhookUrl;
  final String authToken;
  final int defaultDurationMinutes;
  final List<String> blockedPackages;

  const DeviceAppBlockerConfig({
    this.enabled = false,
    this.webhookUrl = '',
    this.authToken = '',
    this.defaultDurationMinutes = 45,
    this.blockedPackages = const ['com.xingin.xhs'],
  });

  String get effectiveEndpoint {
    final trimmed = webhookUrl.trim();
    return trimmed;
  }

  bool get useNativeAccessibility => effectiveEndpoint.isEmpty;

  bool get isReady => enabled;

  factory DeviceAppBlockerConfig.fromJson(Map<String, dynamic> json) {
    final rawPackages = json['blockedPackages'];
    final packages = rawPackages is List
        ? rawPackages
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList()
        : const <String>[];
    return DeviceAppBlockerConfig(
      enabled: json['enabled'] as bool? ?? false,
      webhookUrl: json['webhookUrl'] as String? ?? '',
      authToken: json['authToken'] as String? ?? '',
      defaultDurationMinutes:
          (json['defaultDurationMinutes'] as num?)?.toInt() ?? 45,
      blockedPackages: packages.isEmpty ? const ['com.xingin.xhs'] : packages,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'webhookUrl': webhookUrl,
        'authToken': authToken,
        'defaultDurationMinutes': defaultDurationMinutes,
        'blockedPackages': blockedPackages,
      };

  DeviceAppBlockerConfig copyWith({
    bool? enabled,
    String? webhookUrl,
    String? authToken,
    int? defaultDurationMinutes,
    List<String>? blockedPackages,
  }) {
    return DeviceAppBlockerConfig(
      enabled: enabled ?? this.enabled,
      webhookUrl: webhookUrl ?? this.webhookUrl,
      authToken: authToken ?? this.authToken,
      defaultDurationMinutes:
          defaultDurationMinutes ?? this.defaultDurationMinutes,
      blockedPackages: blockedPackages ?? this.blockedPackages,
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
    final normalizedUrl = _stripTrailingSlash(config.webhookUrl.trim());
    final normalizedPackages = config.blockedPackages
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final safeDuration = config.defaultDurationMinutes.clamp(1, 720);
    final normalized = config.copyWith(
      webhookUrl: normalizedUrl,
      defaultDurationMinutes: safeDuration,
      blockedPackages: normalizedPackages.isEmpty
          ? const ['com.xingin.xhs']
          : normalizedPackages,
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
        'mode':
            config.useNativeAccessibility ? 'native_accessibility' : 'tasker',
        'native_accessibility_enabled': nativeAvailable,
        'native_focus_lock_active': nativeActive,
        'active': state.active,
        'until': state.until?.toIso8601String(),
        'reason': state.reason,
        'blocked_packages': config.blockedPackages,
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
    final effectiveDuration = lock
        ? (durationMinutes ?? config.defaultDurationMinutes).clamp(1, 720)
        : null;
    final until = effectiveDuration == null
        ? null
        : DateTime.now().add(Duration(minutes: effectiveDuration));
    final endpoint = config.effectiveEndpoint;
    if (config.useNativeAccessibility) {
      return _sendNativeAccessibilityCommand(
        action: normalizedAction,
        until: until,
        reason: reason?.trim() ?? '',
      );
    }

    final uri = Uri.tryParse(endpoint);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return DeviceAppBlockerResult(
        ok: false,
        action: normalizedAction,
        message: 'Invalid Tasker endpoint.',
      );
    }

    final body = {
      'action': normalizedAction,
      'block_mode': lock,
      'duration_minutes': effectiveDuration,
      'until': until?.toIso8601String(),
      'reason': reason?.trim() ?? '',
      'source': source,
      'blocked_packages': config.blockedPackages,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (uri.scheme == 'intent') {
      return _sendIntentCommand(
        intentAction: uri.host,
        action: normalizedAction,
        body: body,
        until: until,
      );
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (config.authToken.trim().isNotEmpty) ...{
        'Authorization': 'Bearer ${config.authToken.trim()}',
        'X-Memex-Token': config.authToken.trim(),
      },
    };

    try {
      final response = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 10));
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      final message = ok
          ? 'Tasker accepted $normalizedAction.'
          : 'Tasker returned HTTP ${response.statusCode}: ${response.body}';
      final previous = await getState();
      final nextState = normalizedAction == 'ping'
          ? DeviceAppBlockerState(
              active: previous.active,
              until: previous.until,
              reason: previous.reason,
              lastError: ok ? '' : message,
              updatedAt: DateTime.now(),
            )
          : DeviceAppBlockerState(
              active: ok && lock,
              until: ok ? until : previous.until,
              reason: ok ? (reason?.trim() ?? '') : previous.reason,
              lastError: ok ? '' : message,
              updatedAt: DateTime.now(),
            );
      await _saveState(nextState);
      return DeviceAppBlockerResult(
        ok: ok,
        action: normalizedAction,
        message: message,
        statusCode: response.statusCode,
        until: until,
      );
    } catch (e) {
      final message = 'Failed to call Tasker webhook: $e';
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
        action: normalizedAction,
        message: message,
      );
    }
  }

  Future<DeviceAppBlockerResult> _sendIntentCommand({
    required String intentAction,
    required String action,
    required Map<String, dynamic> body,
    DateTime? until,
  }) async {
    if (!Platform.isAndroid) {
      return DeviceAppBlockerResult(
        ok: false,
        action: action,
        message: 'Tasker intent bridge is only available on Android.',
      );
    }
    try {
      await _channel.invokeMethod<bool>('sendTaskerIntent', {
        'intentAction': intentAction,
        'payloadJson': jsonEncode(body),
      });
      final lock = action == 'lock';
      final previous = await getState();
      final nextState = action == 'ping'
          ? DeviceAppBlockerState(
              active: previous.active,
              until: previous.until,
              reason: previous.reason,
              lastError: '',
              updatedAt: DateTime.now(),
            )
          : DeviceAppBlockerState(
              active: lock,
              until: until,
              reason: (body['reason'] as String?) ?? '',
              lastError: '',
              updatedAt: DateTime.now(),
            );
      await _saveState(nextState);
      return DeviceAppBlockerResult(
        ok: true,
        action: action,
        message: 'Tasker intent sent: $intentAction',
        until: until,
      );
    } catch (e) {
      final message = 'Failed to send Tasker intent: $e';
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
      final message = e.code == 'SERVICE_NOT_ENABLED'
          ? 'Enable Here I am in Android Accessibility settings first.'
          : 'Failed to control native focus lock: ${e.message ?? e.code}';
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

  String _stripTrailingSlash(String value) {
    var out = value;
    while (out.endsWith('/')) {
      out = out.substring(0, out.length - 1);
    }
    return out;
  }
}
