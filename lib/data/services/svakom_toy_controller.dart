import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:memex/data/services/toy_controller.dart';
import 'package:memex/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Direct BLE controller for Svakom devices.
///
/// Protocol reverse-engineered from Svakom's official app BLE traffic.
/// Main-function service UUID:  0000ffe0-0000-1000-8000-00805f9b34fb
/// Main-function write UUID:    0000ffe1-0000-1000-8000-00805f9b34fb
/// Vibration service UUID:      0000ae30-0000-1000-8000-00805f9b34fb
/// Vibration write UUID:        0000ae01-0000-1000-8000-00805f9b34fb
///
/// Command format (7 bytes):
///   [0x55, 0x09, 0x00, 0x00, mode, intensity, 0x00]
///   mode:      0x01–0x08 (vibration patterns)
///   intensity: 0x01–0x05
///
/// Stop command: [0x55, 0xFE, 0x09, 0x00, 0x00, 0x00, 0x00]
///
/// ⚠️ SAFETY: Never write to 0xAE00 — that is the Telink OTA firmware
/// channel. Writing incorrect data there can brick the device.
class SvakomToyController implements ToyController {
  static const _mainServiceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static const _mainWriteUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';
  static const _vibrationServiceUuid = '0000ae30-0000-1000-8000-00805f9b34fb';
  static const _vibrationWriteUuid = '0000ae01-0000-1000-8000-00805f9b34fb';

  // OTA firmware UUID — NEVER write here
  static const _forbiddenUuid = '0000ae00-0000-1000-8000-00805f9b34fb';

  final _log = getLogger('SvakomToyController');
  final String deviceId;
  final String deviceName;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _mainWriteChar;
  BluetoothCharacteristic? _vibrationWriteChar;
  bool _connected = false;
  Timer? _keepAliveTimer;
  Timer? _patternTimer;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  // Current state for keep-alive
  int _currentMode = 1;
  int _currentIntensity = 0;

  SvakomToyController({required this.deviceId, required this.deviceName});

  @override
  bool get isReady => _connected && _mainWriteChar != null;

  // ── Connection ──────────────────────────────────────────────────────────────

  Future<void> connect() async {
    _device = BluetoothDevice.fromId(deviceId);
    await _device!.connect(timeout: const Duration(seconds: 10));

    _connectionSub?.cancel();
    _connectionSub = _device!.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _log.warning('$deviceName disconnected');
        _connected = false;
        _mainWriteChar = null;
        _vibrationWriteChar = null;
        _cancelPattern();
      }
    });

    final services = await _device!.discoverServices();
    for (final svc in services) {
      final svcUuid = svc.uuid.toString().toLowerCase();
      if (svcUuid.contains('ae00')) {
        _log.warning(
            'Found OTA service $svcUuid — skipping entirely (firmware damage risk)');
        continue;
      }
      final isMainService = svcUuid.contains(_mainServiceUuid.substring(4, 8));
      final isVibrationService =
          svcUuid.contains(_vibrationServiceUuid.substring(4, 8));
      if (!isMainService && !isVibrationService) continue;

      for (final char in svc.characteristics) {
        final charUuid = char.uuid.toString().toLowerCase();
        if (charUuid.contains(_forbiddenUuid)) {
          _log.warning('Skipping forbidden OTA characteristic $charUuid');
          continue;
        }
        if (isMainService &&
            charUuid.contains(_mainWriteUuid.substring(4, 8)) &&
            char.properties.writeWithoutResponse) {
          _mainWriteChar = char;
          _log.info('Found Svakom main-function write characteristic: '
              '$charUuid');
        }
        if (isVibrationService &&
            charUuid.contains(_vibrationWriteUuid.substring(4, 8)) &&
            char.properties.writeWithoutResponse) {
          _vibrationWriteChar = char;
          _log.info('Found Svakom vibration write characteristic: $charUuid');
        }
      }
    }

    if (_mainWriteChar != null) {
      _connected = true;
      final hasSecondary = _vibrationWriteChar != null ? ' with AE30 seen' : '';
      _log.info('Connected to $deviceName using FFE1 command channel'
          '$hasSecondary');
    } else {
      await _device!.disconnect();
      throw Exception('Could not find Svakom write characteristic');
    }
  }

  // ── ToyController interface ─────────────────────────────────────────────────

  @override
  Future<bool> vibrate(int intensity, {int durationSeconds = 0}) async {
    _cancelPattern();
    final mapped = _mapIntensity(intensity);
    final ok = await _sendCommand(_currentMode, mapped);
    if (ok) _startKeepAlive(_currentMode, mapped);
    if (ok && durationSeconds > 0) {
      Future.delayed(Duration(seconds: durationSeconds), stop);
    }
    return ok;
  }

  @override
  Future<bool> stop() async {
    _cancelPattern();
    _stopKeepAlive();
    _currentIntensity = 0;
    return _sendStop();
  }

  @override
  Future<String> playPattern(ToyPattern pattern, int peakIntensity) async {
    _cancelPattern();
    final peak = _mapIntensity(peakIntensity.clamp(1, 20));
    switch (pattern) {
      case ToyPattern.steady:
        final ok = await _sendCommand(1, peak);
        if (ok) _startKeepAlive(1, peak);
        return 'steady vibration at intensity $peakIntensity';
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

  // ── Patterns ────────────────────────────────────────────────────────────────

  String _startWave(int peak) {
    int step = 0;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 400), (_) async {
      final t = (step % 10) / 10.0;
      final level = (peak * (0.4 + 0.6 * _triangle(t))).round().clamp(1, 5);
      await _sendCommand(1, level);
      step++;
    });
    return 'gentle wave pattern';
  }

  String _startPulse(int peak) {
    bool on = false;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) async {
      on = !on;
      if (on) {
        await _sendCommand(1, peak);
      } else {
        await _sendStop();
      }
    });
    return 'rhythmic pulse';
  }

  String _startEscalate(int peak) {
    int current = 1;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 800), (_) async {
      await _sendCommand(1, current);
      if (current < peak) current++;
    });
    return 'slow escalation';
  }

  String _startTease(int peak) {
    int tick = 0;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 300), (_) async {
      if (tick % 5 < 2) {
        await _sendCommand(1, peak);
      } else {
        await _sendStop();
      }
      tick++;
    });
    return 'teasing bursts';
  }

  double _triangle(double t) => 1.0 - (2 * t - 1).abs();

  void _cancelPattern() {
    _patternTimer?.cancel();
    _patternTimer = null;
    _stopKeepAlive();
  }

  // ── Keep-alive ───────────────────────────────────────────────────────────────

  void _startKeepAlive(int mode, int intensity) {
    _stopKeepAlive();
    _currentMode = mode;
    _currentIntensity = intensity;
    // Svakom holds state server-side, but re-send every 2s to be safe
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_currentIntensity > 0) {
        await _sendCommand(_currentMode, _currentIntensity);
      }
    });
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  // ── Wire protocol ────────────────────────────────────────────────────────────

  /// Maps 0–20 intensity scale to Svakom's 1–5 scale.
  int _mapIntensity(int intensity) {
    if (intensity <= 0) return 0;
    return ((intensity / 20.0) * 9 + 1).round().clamp(1, 10);
  }

  Future<bool> _sendCommand(int mode, int intensity) async {
    if (!isReady) return false;
    final cmd = _command(0x03, mode, intensity);
    try {
      await _mainWriteChar!.write(cmd, withoutResponse: true);
      return true;
    } catch (e) {
      _log.warning('Write failed: $e');
      _connected = false;
      _mainWriteChar = null;
      _vibrationWriteChar = null;
      return false;
    }
  }

  Future<bool> _sendStop() async {
    if (!isReady) return false;
    final stopCommands = [
      _command(0x03, 0x00, 0x00),
      _command(0x03, 0x01, 0x00),
      _command(0x09, 0x00, 0x00),
      _command(0x09, 0x01, 0x00),
      [0x55, 0xFE, 0x03, 0x00, 0x00, 0x00, 0x00],
      [0x55, 0xFE, 0x09, 0x00, 0x00, 0x00, 0x00],
    ];
    try {
      for (final cmd in stopCommands) {
        await _mainWriteChar!.write(cmd, withoutResponse: true);
      }
      return true;
    } catch (e) {
      _log.warning('Stop failed: $e');
      _connected = false;
      _mainWriteChar = null;
      _vibrationWriteChar = null;
      return false;
    }
  }

  List<int> _command(int function, int mode, int intensity) =>
      [0x55, function, 0x00, 0x00, mode, intensity, 0x00];

  @override
  void dispose() {
    _connectionSub?.cancel();
    _cancelPattern();
    _sendStop();
    _connected = false;
    _mainWriteChar = null;
    _vibrationWriteChar = null;
    _device?.disconnect();
  }
}

// ── Device scanner ───────────────────────────────────────────────────────────

/// BLE scan result for a Svakom device.
class SvakomScanResult {
  final String deviceId;
  final String name;
  final int rssi;

  const SvakomScanResult({
    required this.deviceId,
    required this.name,
    required this.rssi,
  });
}

/// Known Svakom BLE advertisement name hints.
const _svakomNameHints = [
  'svakom',
  'ella',
  'edeny',
  'echo',
  'phoenix',
  'vick',
  'emma',
  'ava',
  'jordan',
  'aravinda',
  'pulse',
  'alex',
  'hannes',
  'sam',
];

bool _isSvakomDevice(String name) {
  final lower = name.toLowerCase();
  if (_svakomNameHints.any((hint) => lower.contains(hint))) return true;
  return RegExp(r'^sx[0-9a-z]{3,}$').hasMatch(lower);
}

/// Scan for nearby Svakom BLE devices.
Stream<List<SvakomScanResult>> scanForSvakom({
  Duration timeout = const Duration(seconds: 10),
}) async* {
  final results = <String, SvakomScanResult>{};

  await FlutterBluePlus.startScan(timeout: timeout);

  yield* FlutterBluePlus.scanResults.map((scanResults) {
    for (final r in scanResults) {
      final name = r.device.platformName;
      if (name.isNotEmpty && _isSvakomDevice(name)) {
        results[r.device.remoteId.str] = SvakomScanResult(
          deviceId: r.device.remoteId.str,
          name: name,
          rssi: r.rssi,
        );
      }
    }
    return results.values.toList();
  });
}

// ── Saved device prefs ───────────────────────────────────────────────────────

const _kSvakomDeviceId = 'svakom_device_id';
const _kSvakomDeviceName = 'svakom_device_name';

Future<({String id, String name})?> loadSvakomDevice() async {
  final prefs = await SharedPreferences.getInstance();
  final id = prefs.getString(_kSvakomDeviceId);
  final name = prefs.getString(_kSvakomDeviceName);
  if (id == null || name == null) return null;
  return (id: id, name: name);
}

Future<void> saveSvakomDevice(String id, String name) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kSvakomDeviceId, id);
  await prefs.setString(_kSvakomDeviceName, name);
}

Future<void> clearSvakomDevice() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kSvakomDeviceId);
  await prefs.remove(_kSvakomDeviceName);
}
