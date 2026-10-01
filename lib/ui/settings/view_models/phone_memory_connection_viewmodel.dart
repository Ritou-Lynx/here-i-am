import 'package:flutter/foundation.dart';
import 'package:memex/data/memory_v3/readonly/phone_memory_read_client.dart';
import 'package:memex/data/memory_v3/readonly/phone_memory_read_server.dart';
import 'package:memex/utils/command.dart';
import 'package:memex/utils/result.dart';

/// The deliberately small session projection a settings surface needs.
///
/// The connection code is held only long enough for the phone page's explicit
/// copy action. It must never be rendered, logged, persisted, or included in a
/// receipt. Bearer tokens never enter this type.
class PhoneMemoryConnectionSession {
  const PhoneMemoryConnectionSession({
    required this.expiresAt,
    required this.port,
    required this.connectionCode,
  });

  final DateTime expiresAt;
  final int port;

  /// Only used briefly by the phone page to copy the code. Do not render it.
  final String connectionCode;
}

/// Injectable boundary for the P5 settings page.
///
/// Production delegates to the two in-memory P5 transports; widget tests can
/// provide a fake without starting an HTTP server or touching a device.
abstract class PhoneMemoryConnectionFacade extends ChangeNotifier {
  bool get isPhoneRunning;
  PhoneMemoryConnectionSession? get phoneSession;
  bool get isDesktopConfigured;
  DateTime? get desktopExpiresAt;

  /// Only source/status/counts/time are allowed here. Never expose a token,
  /// code, query, or memory content to the settings UI.
  Map<String, Object?>? get lastReceipt;

  Future<Result<PhoneMemoryConnectionSession>> startPhone();
  Future<Result<void>> stopPhone();
  Future<Result<void>> connect(String connectionCode);
  void disconnect();
}

class LivePhoneMemoryConnectionFacade extends PhoneMemoryConnectionFacade {
  LivePhoneMemoryConnectionFacade({
    PhoneMemoryReadServer? server,
    PhoneMemoryReadClient? client,
  })  : _server = server ?? PhoneMemoryReadServer.instance,
        _client = client ?? PhoneMemoryReadClient.instance {
    _server.addListener(notifyListeners);
    _client.addListener(notifyListeners);
  }

  final PhoneMemoryReadServer _server;
  final PhoneMemoryReadClient _client;

  @override
  bool get isPhoneRunning => _server.isRunning;

  @override
  PhoneMemoryConnectionSession? get phoneSession {
    final session = _server.session;
    if (session == null) return null;
    return PhoneMemoryConnectionSession(
      expiresAt: session.expiresAt,
      port: session.port,
      connectionCode: session.connectionCode,
    );
  }

  @override
  bool get isDesktopConfigured => _client.isConfigured;

  @override
  DateTime? get desktopExpiresAt => _client.expiresAt;

  @override
  Map<String, Object?>? get lastReceipt {
    return sanitizePhoneMemoryReceipt(_client.lastReceipt);
  }

  @override
  Future<Result<PhoneMemoryConnectionSession>> startPhone() async {
    final result = await _server.start();
    return switch (result) {
      Ok(:final value) => Ok(
          PhoneMemoryConnectionSession(
            expiresAt: value.expiresAt,
            port: value.port,
            connectionCode: value.connectionCode,
          ),
        ),
      Error(:final error, :final stackTrace) => Error(error, stackTrace),
    };
  }

  @override
  Future<Result<void>> stopPhone() => _server.stop();

  @override
  Future<Result<void>> connect(String connectionCode) =>
      _client.connect(connectionCode);

  @override
  void disconnect() => _client.disconnect();

  @override
  void dispose() {
    _server.removeListener(notifyListeners);
    _client.removeListener(notifyListeners);
    super.dispose();
  }
}

class PhoneMemoryConnectionViewModel extends ChangeNotifier {
  PhoneMemoryConnectionViewModel({required PhoneMemoryConnectionFacade facade})
      : _facade = facade {
    startPhone = Command0<void>(_startPhone);
    stopPhone = Command0<void>(_stopPhone);
    connect = Command1<void, String>(_connect);
    _facade.addListener(_onFacadeChanged);
  }

  final PhoneMemoryConnectionFacade _facade;
  late final Command0<void> startPhone;
  late final Command0<void> stopPhone;
  late final Command1<void, String> connect;

  bool get isPhoneRunning => _facade.isPhoneRunning;
  PhoneMemoryConnectionSession? get phoneSession => _facade.phoneSession;
  bool get isDesktopConfigured => _facade.isDesktopConfigured;
  DateTime? get desktopExpiresAt => _facade.desktopExpiresAt;
  Map<String, Object?>? get lastReceipt =>
      sanitizePhoneMemoryReceipt(_facade.lastReceipt);

  Future<Result<void>> _startPhone() async {
    final result = await _facade.startPhone();
    return switch (result) {
      Ok() => const Ok.v(),
      Error(:final error, :final stackTrace) => Error(error, stackTrace),
    };
  }

  Future<Result<void>> _stopPhone() => _facade.stopPhone();

  Future<Result<void>> _connect(String connectionCode) {
    if (connectionCode.trim().isEmpty) {
      return Future.value(Error<void>(
        const FormatException('请输入手机上复制的连接码'),
      ));
    }
    return _facade.connect(connectionCode.trim());
  }

  void disconnect() => _facade.disconnect();

  void _onFacadeChanged() => notifyListeners();

  @override
  void dispose() {
    _facade.removeListener(_onFacadeChanged);
    _disposeCommandWhenIdle(startPhone);
    _disposeCommandWhenIdle(stopPhone);
    _disposeCommandWhenIdle(connect);
    super.dispose();
  }

  /// [Command] notifies once in its async `finally` block. A page can be
  /// popped while that future is pending, so disposing a running command here
  /// would make that final notification target a disposed ChangeNotifier.
  /// Keep only the command alive until it becomes idle; the ViewModel itself
  /// has already detached from both the facade and the command UI listeners.
  void _disposeCommandWhenIdle<T>(Command<T> command) {
    if (!command.running) {
      command.dispose();
      return;
    }
    late VoidCallback release;
    release = () {
      if (command.running) return;
      command.removeListener(release);
      // ChangeNotifier cannot be disposed inside its own notification stack.
      Future.microtask(command.dispose);
    };
    command.addListener(release);
  }
}

/// Produces the sole receipt shape the settings UI may observe. In particular,
/// this does not pass through a nested `counts` map: only three known integer
/// counters are reconstructed, so an upstream body, query, code, or token
/// cannot become visible through a future receipt extension.
Map<String, Object?>? sanitizePhoneMemoryReceipt(Map<String, Object?>? value) {
  if (value == null) return null;
  const statuses = {
    'connected',
    'available',
    'empty',
    'unavailable',
    'not_configured',
    'isolated',
  };
  final rawStatus = value['status'];
  final status = rawStatus is String && statuses.contains(rawStatus)
      ? rawStatus
      : 'unavailable';
  final rawCounts = value['counts'];
  final countsSource = rawCounts is Map ? rawCounts : value;
  final counts = <String, int>{
    for (final name in const ['episodes', 'fragments', 'sagas'])
      if (countsSource[name] is int && (countsSource[name] as int) >= 0)
        name: countsSource[name] as int,
  };
  DateTime? parsedTime;
  for (final key in const ['captured_at', 'time']) {
    final candidate = value[key];
    if (candidate is String) {
      parsedTime = DateTime.tryParse(candidate)?.toUtc();
      if (parsedTime != null) break;
    }
  }
  return Map.unmodifiable({
    'source': 'phone_v3_live',
    'status': status,
    if (counts.isNotEmpty) 'counts': Map.unmodifiable(counts),
    if (parsedTime != null) 'time': parsedTime.toIso8601String(),
  });
}
