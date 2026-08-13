import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:memex/data/services/device_identity_service.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/services/sync/core_sync_client.dart';
import 'package:memex/data/services/sync/core_sync_connection_store.dart';
import 'package:memex/data/services/sync/core_sync_engine.dart';
import 'package:memex/data/services/sync/core_sync_protocol.dart';
import 'package:memex/db/app_database.dart';

enum CoreSyncRuntimePhase { notConfigured, idle, syncing, error }

class CoreSyncRuntimeStatus {
  const CoreSyncRuntimeStatus({
    required this.phase,
    this.pendingMessages = 0,
    this.message,
    this.lastSuccessAt,
    this.baseUrl,
    this.coreNodeId,
  });

  final CoreSyncRuntimePhase phase;
  final int pendingMessages;
  final String? message;
  final DateTime? lastSuccessAt;
  final String? baseUrl;
  final String? coreNodeId;

  bool get isConfigured => phase != CoreSyncRuntimePhase.notConfigured;
}

/// Foreground coordinator for the first cross-device text-chat slice.
///
/// It deliberately does not run a background isolate or companion inference.
/// It performs a short sync after a local chat write, on foreground resume,
/// and when the user taps "立即同步" in settings.
class CoreSyncRuntimeService extends ChangeNotifier {
  CoreSyncRuntimeService._();

  static final CoreSyncRuntimeService instance = CoreSyncRuntimeService._();

  final _logger = Logger('CoreSyncRuntimeService');
  final _connectionStore = CoreSyncConnectionStore.instance;

  CoreSyncRuntimeStatus _status = const CoreSyncRuntimeStatus(
    phase: CoreSyncRuntimePhase.notConfigured,
  );
  CoreSyncRuntimeStatus get status => _status;

  bool _initialized = false;
  Future<void>? _activeSync;
  Timer? _messageDebounce;

  Future<void> initialize() async {
    if (_initialized || !AppDatabase.isInitialized) return;
    _initialized = true;
    EventBusService.instance.addHandler(
      EventBusMessageType.personaChatMessageAdded,
      _onChatMessageAdded,
    );
    await refreshStatus();
    if (_status.isConfigured) unawaited(syncNow(reason: 'startup'));
  }

  void _onChatMessageAdded(EventBusMessage _) {
    _messageDebounce?.cancel();
    _messageDebounce = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(syncNow(reason: 'message_added')),
    );
  }

  Future<void> refreshStatus() async {
    if (!AppDatabase.isInitialized) return;
    CoreSyncConnection? connection;
    try {
      connection = await _connectionStore.read();
    } catch (error, stack) {
      _logger.warning('Failed to read core credentials', error, stack);
      _setStatus(const CoreSyncRuntimeStatus(
        phase: CoreSyncRuntimePhase.notConfigured,
        message: '无法读取这台设备的安全凭据',
      ));
      return;
    }
    if (connection == null) {
      _setStatus(const CoreSyncRuntimeStatus(
        phase: CoreSyncRuntimePhase.notConfigured,
      ));
      return;
    }
    final deviceId = await DeviceIdentityService.getOrCreate();
    final pending = await PersonaChatService.instance
        .pendingOutboxMessages(deviceId, limit: 500);
    _setStatus(CoreSyncRuntimeStatus(
      phase: CoreSyncRuntimePhase.idle,
      pendingMessages: pending.length,
      baseUrl: connection.baseUrl,
      coreNodeId: connection.coreNodeId,
      lastSuccessAt: _status.lastSuccessAt,
    ));
  }

  Future<void> pair({
    required String baseUrl,
    required String pairingCode,
    required String displayName,
  }) async {
    if (!AppDatabase.isInitialized) {
      throw StateError('本地数据库尚未就绪');
    }
    final normalizedUrl = CoreSyncConnection.normalizeBaseUrl(baseUrl);
    final code = pairingCode.trim();
    if (code.isEmpty) throw const FormatException('配对码不能为空');
    // Do not let a startup/resume pass race a deliberate authority switch.
    // The old pass may finish or fail, but pairing starts from a quiet state.
    final running = _activeSync;
    if (running != null) {
      try {
        await running;
      } catch (_) {
        // Pairing with a new credential is allowed to recover an old failure.
      }
    }
    final deviceId = await DeviceIdentityService.getOrCreate();
    final package = await PackageInfo.fromPlatform();
    final response = await CoreSyncClient.pair(
      baseUrl: normalizedUrl,
      request: CoreDevicePairRequest(
        deviceId: deviceId,
        displayName:
            displayName.trim().isEmpty ? _platformName : displayName.trim(),
        platform: _platformName,
        clientVersion: '${package.version}+${package.buildNumber}',
        pairingCode: code,
        capabilities: const ['chat', 'share'],
      ),
    );
    final connection = CoreSyncConnection(
      baseUrl: normalizedUrl,
      deviceToken: response.deviceToken,
      initialCursor: response.initialCursor,
      coreNodeId: response.coreNodeId,
    );
    await _connectionStore.save(connection);
    await CoreSyncEngine(
      db: AppDatabase.instance,
      client: _client(connection, deviceId),
      deviceId: deviceId,
      coreNodeId: connection.coreNodeId,
      initialCursor: connection.initialCursor,
    ).saveCursor(connection.initialCursor);
    await syncNow(reason: 'paired');
  }

  Future<void> disconnect() async {
    await _connectionStore.clear();
    _setStatus(const CoreSyncRuntimeStatus(
      phase: CoreSyncRuntimePhase.notConfigured,
    ));
  }

  Future<void> syncNow({String reason = 'manual'}) {
    final running = _activeSync;
    if (running != null) return running;
    late final Future<void> tracked;
    tracked = _performSync(reason).whenComplete(() {
      if (identical(_activeSync, tracked)) _activeSync = null;
    });
    _activeSync = tracked;
    return tracked;
  }

  Future<void> _performSync(String reason) async {
    if (!AppDatabase.isInitialized) return;
    CoreSyncConnection? connection;
    try {
      connection = await _connectionStore.read();
    } catch (error, stack) {
      _logger.warning(
          'Failed to read core credentials ($reason)', error, stack);
      _setStatus(const CoreSyncRuntimeStatus(
        phase: CoreSyncRuntimePhase.error,
        message: '无法读取这台设备的安全凭据',
      ));
      if (reason == 'manual' || reason == 'paired') rethrow;
      return;
    }
    if (connection == null) {
      _setStatus(const CoreSyncRuntimeStatus(
        phase: CoreSyncRuntimePhase.notConfigured,
      ));
      return;
    }
    final previous = _status;
    _setStatus(CoreSyncRuntimeStatus(
      phase: CoreSyncRuntimePhase.syncing,
      pendingMessages: previous.pendingMessages,
      message: '正在同步',
      lastSuccessAt: previous.lastSuccessAt,
      baseUrl: connection.baseUrl,
      coreNodeId: connection.coreNodeId,
    ));
    try {
      final deviceId = await DeviceIdentityService.getOrCreate();
      final engine = CoreSyncEngine(
        db: AppDatabase.instance,
        client: _client(connection, deviceId),
        deviceId: deviceId,
        coreNodeId: connection.coreNodeId,
        initialCursor: connection.initialCursor,
      );
      await engine.syncOnce();
      final pending = await PersonaChatService.instance
          .pendingOutboxMessages(deviceId, limit: 500);
      _setStatus(CoreSyncRuntimeStatus(
        phase: CoreSyncRuntimePhase.idle,
        pendingMessages: pending.length,
        message: pending.isEmpty ? '已同步' : '${pending.length} 条待发送',
        lastSuccessAt: DateTime.now(),
        baseUrl: connection.baseUrl,
        coreNodeId: connection.coreNodeId,
      ));
    } catch (error, stack) {
      _logger.warning('Core sync failed ($reason): $error', error, stack);
      final deviceId = await DeviceIdentityService.getOrCreate();
      final pending = await PersonaChatService.instance
          .pendingOutboxMessages(deviceId, limit: 500);
      _setStatus(CoreSyncRuntimeStatus(
        phase: CoreSyncRuntimePhase.error,
        pendingMessages: pending.length,
        message: _friendlyError(error),
        lastSuccessAt: previous.lastSuccessAt,
        baseUrl: connection.baseUrl,
        coreNodeId: connection.coreNodeId,
      ));
      if (reason == 'manual' || reason == 'paired') rethrow;
    }
  }

  CoreSyncClient _client(CoreSyncConnection connection, String deviceId) {
    return CoreSyncClient(
      baseUrl: connection.baseUrl,
      deviceId: deviceId,
      deviceToken: connection.deviceToken,
    );
  }

  String _friendlyError(Object error) {
    if (error is CoreSyncException) {
      return switch (error.code) {
        'transport_error' => '核心暂时离线，消息会保留并稍后补交',
        'unauthorized' => '设备凭据已失效，请重新配对',
        'protocol_mismatch' => '核心与当前 App 版本不兼容',
        _ => error.message,
      };
    }
    return '同步失败，消息已安全保留';
  }

  String get _platformName {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  void _setStatus(CoreSyncRuntimeStatus value) {
    _status = value;
    notifyListeners();
  }
}
