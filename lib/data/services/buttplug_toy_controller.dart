import 'dart:async';
import 'dart:convert';

import 'package:memex/data/services/toy_controller.dart';
import 'package:memex/utils/logger.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Buttplug v3 (Intiface Central) WebSocket controller.
///
/// Intiface Central must be running with the server started.
/// Default URL: ws://127.0.0.1:12345
///
/// Workflow:
///   1. User pairs their toy in Magic Motion (or any supported) app.
///   2. User opens Intiface Central → Start Server → toy shows up.
///   3. Memex connects here and sends ScalarCmd.
class ButtplugToyController implements ToyController {
  final _log = getLogger('ButtplugToyController');
  final String wsUrl;

  WebSocketChannel? _ws;
  StreamSubscription? _sub;
  int _nextId = 1;

  // Index of the first device that Intiface reports.
  int? _deviceIndex;
  // Actuator descriptors per device — each has an index and a type string
  // like "Vibrate", "Oscillate", etc. Stored so ScalarCmd uses correct types.
  List<Map<String, dynamic>> _actuators = [];
  // Actuator count per device (how many independent motors).
  int _actuatorCount = 1;
  String? _serverName;
  String? _deviceName;
  Map<String, dynamic>? _deviceMessages;
  String? _lastCommandSummary;

  bool _connected = false;
  Timer? _patternTimer;

  // Completers keyed by message id for request→response pairing.
  final _pending = <int, Completer<Map<String, dynamic>>>{};

  ButtplugToyController({required this.wsUrl});

  @override
  bool get isReady => _connected && _deviceIndex != null;

  String get diagnosticSummary {
    return [
      'Server: ${_serverName ?? 'unknown'}',
      'Device: ${_deviceName ?? 'none'}',
      'DeviceIndex: ${_deviceIndex ?? 'none'}',
      'Actuators: ${_actuators.map((a) => '${a['Index']}:${a['ActuatorType']}').join(', ')}',
      'DeviceMessages: ${_deviceMessages?.keys.join(', ') ?? 'none'}',
      'LastCommand: ${_lastCommandSummary ?? 'none'}',
    ].join('\n');
  }

  // ── Connection ──────────────────────────────────────────────────────────────

  /// Connect to Intiface, handshake, and load already-paired devices.
  /// Call this before any vibrate/stop commands.
  Future<void> connect() async {
    _ws = WebSocketChannel.connect(Uri.parse(wsUrl));
    _sub = _ws!.stream.listen(
      _onMessage,
      onError: (e) => _log.warning('WS error: $e'),
      onDone: () {
        _connected = false;
        _log.info('Intiface WS closed');
      },
    );

    // 1. Handshake
    final info = await _sendMsg({
      'RequestServerInfo': {
        'Id': _id(),
        'ClientName': 'Memex',
        'MessageVersion': 3,
      }
    });
    if (info == null || !info.containsKey('ServerInfo')) {
      throw Exception('Buttplug handshake failed: $info');
    }
    _connected = true;
    _serverName = info['ServerInfo']['ServerName'] as String?;
    _log.info('Intiface connected: $_serverName');

    // 2. Request already-connected devices (no need to scan if toy is paired).
    final devResp = await _sendMsg({
      'RequestDeviceList': {'Id': _id()}
    });
    if (devResp != null && devResp.containsKey('DeviceList')) {
      _handleDeviceList(devResp['DeviceList']);
    }

    // 3. Start scanning so newly-paired toys are discovered too.
    _sendFire({
      'StartScanning': {'Id': _id()}
    });
  }

  void _handleDeviceList(Map<String, dynamic> body) {
    final devices = body['Devices'] as List?;
    if (devices == null || devices.isEmpty) return;
    final first = devices.first as Map<String, dynamic>;
    _deviceIndex = first['DeviceIndex'] as int;
    _deviceName = first['DeviceName'] as String?;
    _parseActuators(first);
    _log.info('Using device: ${first['DeviceName']} (index $_deviceIndex, '
        'actuators: $_actuatorCount, types: ${_actuators.map((a) => a['ActuatorType']).toList()})');
  }

  void _parseActuators(Map<String, dynamic> device) {
    final msgs = device['DeviceMessages'] as Map<String, dynamic>?;
    _deviceMessages = msgs;
    if (msgs != null && msgs.containsKey('ScalarCmd')) {
      final scalars = msgs['ScalarCmd'] as List? ?? [];
      _actuators = scalars.cast<Map<String, dynamic>>();
      _actuatorCount = _actuators.length.clamp(1, 10);
    } else {
      _actuators = [];
      _actuatorCount = 1;
    }
  }

  // ── ToyController interface ─────────────────────────────────────────────────

  @override
  Future<bool> vibrate(int intensity, {int durationSeconds = 0}) async {
    _cancelPattern();
    final ok = await _scalarCmd(intensity / 20.0);
    if (ok && durationSeconds > 0) {
      Future.delayed(Duration(seconds: durationSeconds), stop);
    }
    return ok;
  }

  @override
  Future<bool> stop() async {
    _cancelPattern();
    if (!_connected) return false;
    final idx = _deviceIndex;
    if (idx == null) return false;
    final resp = await _sendMsg({
      'StopDeviceCmd': {'Id': _id(), 'DeviceIndex': idx}
    });
    return _isOk(resp, 'StopDeviceCmd');
  }

  @override
  Future<String> playPattern(ToyPattern pattern, int peakIntensity) async {
    _cancelPattern();
    final peak = peakIntensity.clamp(1, 20);
    switch (pattern) {
      case ToyPattern.steady:
        await vibrate(peak);
        return 'steady vibration at intensity $peak';
      case ToyPattern.wave:
        return _startWave(peak);
      case ToyPattern.pulse:
        return _startPulse(peak);
      case ToyPattern.escalate:
        return _startEscalate(peak);
      case ToyPattern.tease:
        return _startTease(peak);
    }
  }

  // ── Pattern generation ──────────────────────────────────────────────────────

  String _startWave(int peak) {
    int step = 0;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 300), (_) async {
      final t = (step % 20) / 20.0;
      final level = peak * (0.5 + 0.5 * _triangleWave(t));
      await _scalarCmd(level / 20.0);
      step++;
    });
    return 'gentle wave pattern peaking at intensity $peak';
  }

  String _startPulse(int peak) {
    bool on = false;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 400), (_) async {
      on = !on;
      await _scalarCmd(on ? peak / 20.0 : 0.0);
    });
    return 'rhythmic pulse at intensity $peak';
  }

  String _startEscalate(int peak) {
    int current = 0;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) async {
      current = (current + 1).clamp(0, peak);
      await _scalarCmd(current / 20.0);
      if (current >= peak) _cancelPattern();
    });
    return 'slow escalation up to intensity $peak';
  }

  String _startTease(int peak) {
    int tick = 0;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 350), (_) async {
      await _scalarCmd((tick % 5) < 2 ? peak / 20.0 : 0.0);
      tick++;
    });
    return 'teasing bursts at intensity $peak';
  }

  double _triangleWave(double t) => 1.0 - (2 * t - 1).abs();

  void _cancelPattern() {
    _patternTimer?.cancel();
    _patternTimer = null;
  }

  // ── Buttplug wire protocol ──────────────────────────────────────────────────

  Future<bool> _scalarCmd(double scalar) async {
    if (!_connected) return false;
    final idx = _deviceIndex;
    if (idx == null) return false;
    final clamped = scalar.clamp(0.0, 1.0);
    final scalars = List.generate(
      _actuatorCount,
      (i) {
        // Use the actual actuator type from device info, fall back to Vibrate.
        final type = (i < _actuators.length)
            ? (_actuators[i]['ActuatorType'] as String? ?? 'Vibrate')
            : 'Vibrate';
        return {'Index': i, 'Scalar': clamped, 'ActuatorType': type};
      },
    );
    final resp = await _sendMsg({
      'ScalarCmd': {'Id': _id(), 'DeviceIndex': idx, 'Scalars': scalars}
    });
    return _isOk(resp, 'ScalarCmd');
  }

  bool _isOk(Map<String, dynamic>? resp, String command) {
    if (resp == null || resp.isEmpty) {
      _lastCommandSummary = '$command timeout';
      _log.warning('$command timed out waiting for Intiface response');
      return false;
    }
    if (resp.containsKey('Ok')) {
      _lastCommandSummary = '$command Ok';
      return true;
    }
    if (resp.containsKey('Error')) {
      final body = resp['Error'] as Map<String, dynamic>? ?? const {};
      final error = body['ErrorMessage'] ?? body;
      _lastCommandSummary = '$command Error: $error';
      _log.warning('$command error: $error');
      return false;
    }
    _lastCommandSummary = '$command unexpected: $resp';
    _log.warning('$command unexpected response: $resp');
    return false;
  }

  int _id() => _nextId++;

  /// Send a message and wait for the server's response with the same Id.
  Future<Map<String, dynamic>?> _sendMsg(Map<String, dynamic> msg) async {
    final id = (msg.values.first as Map)['Id'] as int;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _ws?.sink.add(jsonEncode([msg]));
    return c.future.timeout(const Duration(seconds: 5), onTimeout: () {
      _pending.remove(id);
      return {};
    });
  }

  /// Send and forget — no response tracking.
  void _sendFire(Map<String, dynamic> msg) {
    _ws?.sink.add(jsonEncode([msg]));
  }

  void _onMessage(dynamic raw) {
    List<dynamic> messages;
    try {
      messages = jsonDecode(raw as String) as List;
    } catch (_) {
      return;
    }

    for (final item in messages) {
      if (item is! Map) continue;
      final type = item.keys.first as String;
      final body = item[type] as Map<String, dynamic>;
      final id = body['Id'] as int? ?? 0;

      // Route to pending completer if any.
      if (_pending.containsKey(id)) {
        _pending.remove(id)?.complete({type: body});
        continue;
      }

      // Handle server-push events.
      switch (type) {
        case 'DeviceAdded':
          if (_deviceIndex == null) {
            _deviceIndex = body['DeviceIndex'] as int;
            _deviceName = body['DeviceName'] as String?;
            _parseActuators(body);
            _log.info(
                'Device added: ${body['DeviceName']} (index $_deviceIndex, '
                'actuators: $_actuatorCount, types: ${_actuators.map((a) => a['ActuatorType']).toList()})');
          }
          break;
        case 'DeviceRemoved':
          if (body['DeviceIndex'] == _deviceIndex) {
            _deviceIndex = null;
            _log.info('Device removed');
          }
          break;
        case 'Error':
          _log.warning('Buttplug error: ${body['ErrorMessage']}');
          break;
      }
    }
  }

  @override
  void dispose() {
    _cancelPattern();
    _sendFire({
      'StopAllDevices': {'Id': _id()}
    });
    _connected = false;
    _deviceIndex = null;
    _sub?.cancel();
    _ws?.sink.close();
  }
}
