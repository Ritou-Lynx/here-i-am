import 'dart:async';
import 'dart:math';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:memex/data/services/toy_controller.dart';
import 'package:memex/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Direct BLE controller for Magic Motion Flamingo Max.
///
/// Uses the VTrump BLE SDK — same SCRIPT channel as the Magic Motion S1230.
///
/// GATT layout (confirmed via nRF Connect):
///   Service:    6f488c05-f91f-11e3-a847-b2227cce2b54
///   Write char: 6f488c06-f91f-11e3-a847-b2227cce2b54  (WRITE NO RESPONSE + NOTIFY)
///
/// Command format (VTrump script protocol):
///   [0x02, 0x07, payloadLen,
///     0x02, freqLo, freqHi,          -- frequency tag + value (units: 0.1 Hz)
///     0x04, s10Lo, s10Hi,            -- strength tag + value (units: strength*10, 0–1000)
///     delayLo, delayHi,              -- start delay (ms)
///     durLo, durHi,                  -- duration (ms, 0xFFFF = continuous)
///     0x03]                          -- end marker
///
/// ⚠️ SAFETY: Only write to 6f488c06. Never touch 6f488c03 or 6f488c07
///   (unknown channels — may have side effects). Ignore 6f468792 and
///   78667579 entirely.
class MagicMotionFlamingoController implements ToyController {
  static const _serviceUuid = '6f488c05-f91f-11e3-a847-b2227cce2b54';
  static const _writeUuid = '6f488c06-f91f-11e3-a847-b2227cce2b54';

  // Forbidden — do not write to these
  static const _forbidden = [
    '6f488c03', '6f488c07', // unknown VTrump channels
    '6f468792', // different prefix, unknown
    '78667579', // unknown
  ];

  final _log = getLogger('FlamingoMaxController');
  final String deviceId;
  final String deviceName;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  bool _connected = false;
  bool _writing = false; // write lock — prevents concurrent BLE writes
  Timer? _keepAliveTimer;
  Timer? _heartbeatTimer; // prevent device idle-disconnect when not vibrating
  Timer? _patternTimer;
  Timer? _autoStopTimer;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  // Keep-alive state
  int _keepAliveFreq = 500; // 50 Hz in 0.1 Hz units
  int _keepAliveStr = 0; // 0 = stopped

  MagicMotionFlamingoController({
    required this.deviceId,
    required this.deviceName,
  });

  @override
  bool get isReady => _connected && _writeChar != null;

  // ── Connection ──────────────────────────────────────────────────────────────

  Future<void> connect() async {
    if (isReady) return;

    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      if (attempt > 1) {
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
      await _resetBleHandle();
      try {
        await _connectOnce();
        return;
      } catch (e) {
        lastError = e;
        _log.warning(
          'Flamingo connect attempt $attempt failed for $deviceName: $e',
        );
      }
    }

    throw Exception('Could not connect to Flamingo Max: $lastError');
  }

  Future<void> _connectOnce() async {
    _device = BluetoothDevice.fromId(deviceId);
    try {
      await _device!.connect(timeout: const Duration(seconds: 6));
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (!message.contains('already')) {
        rethrow;
      }
      _log.info('$deviceName was already connected; rediscovering services');
    }

    // Track connection drops — update _connected so isReady reflects reality
    _connectionSub?.cancel();
    _connectionSub = _device!.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _log.warning('$deviceName disconnected');
        _connected = false;
        _writeChar = null;
        _stopHeartbeat();
        _cancelAutoStop();
        _cancelPattern();
      }
    });

    final services = await _device!.discoverServices();
    for (final svc in services) {
      final svcId = svc.uuid.toString().toLowerCase();
      // Only enter the known control service
      if (!svcId.startsWith(_serviceUuid.substring(0, 8))) continue;

      for (final char in svc.characteristics) {
        final charId = char.uuid.toString().toLowerCase();
        // Safety: skip any forbidden characteristic
        if (_forbidden.any((f) => charId.contains(f))) {
          _log.warning('Skipping forbidden characteristic $charId');
          continue;
        }
        if (charId.startsWith(_writeUuid.substring(0, 8)) &&
            char.properties.writeWithoutResponse) {
          _writeChar = char;
          _log.info('Found Flamingo Max write char: $charId');
        }
      }
    }

    if (_writeChar != null) {
      // Enable notifications — some VTrump devices refuse commands until the
      // NOTIFY descriptor is subscribed.
      try {
        await _writeChar!.setNotifyValue(true);
        _log.info('Notifications enabled on $deviceName');
      } catch (e) {
        _log.warning('setNotifyValue failed (non-fatal): $e');
      }
      _connected = true;
      _log.info('Connected to $deviceName');
      // Start heartbeat immediately to prevent device idle-disconnect.
      // Flamingo Max auto-disconnects if no BLE command is received within ~5s.
      _startHeartbeat();
    } else {
      await _device!.disconnect();
      throw Exception('Could not find Flamingo Max write characteristic');
    }
  }

  @override
  Future<bool> ensureReady({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (isReady) return true;
    try {
      await connect().timeout(timeout);
      return isReady;
    } catch (e) {
      _log.warning('Flamingo reconnect failed: $e');
      return false;
    }
  }

  Future<void> _resetBleHandle() async {
    _cancelPattern();
    _cancelAutoStop();
    _stopHeartbeat();
    await _connectionSub?.cancel();
    _connectionSub = null;
    _connected = false;
    _writeChar = null;
    _writing = false;

    final device = _device;
    _device = null;
    if (device == null) return;
    try {
      await device.disconnect();
    } catch (e) {
      _log.fine('Ignoring Flamingo disconnect during reset: $e');
    }
  }

  /// Sends a zero-strength command every 3 s to keep the device from
  /// applying its application-level idle-disconnect timeout.
  /// Stops automatically once a vibration keep-alive takes over.
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      // Only needed when idle (no active vibration keep-alive)
      if (_connected && _keepAliveStr == 0) {
        // Send a 1-ms zero-strength command — keeps BLE alive, no vibration
        await _sendScript(
          freq: 500, strength: 0, durationMs: 0x01,
          skipIfBusy: true, // timer tick — skip if user command is in flight
        );
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // ── ToyController interface ─────────────────────────────────────────────────

  @override
  Future<bool> vibrate(int intensity, {int durationSeconds = 0}) async {
    _cancelAutoStop();
    _cancelPattern();
    final str = _mapStrength(intensity);
    const freq = 500; // 50 Hz
    final ok = await _sendUserScript(
      freq: freq,
      strength: str,
      durationMs: 0xFFFF,
    );
    if (ok) _startKeepAlive(freq, str);
    if (ok && durationSeconds > 0) {
      _autoStopTimer = Timer(Duration(seconds: durationSeconds), () {
        _autoStopTimer = null;
        unawaited(stop());
      });
    }
    return ok;
  }

  @override
  Future<bool> stop() async {
    _cancelAutoStop();
    _cancelPattern();
    _stopKeepAlive();
    _keepAliveStr = 0;
    final ok = await _sendUserScript(freq: 500, strength: 0, durationMs: 0);
    // Restart heartbeat so device doesn't idle-disconnect while waiting for next command
    if (_connected) _startHeartbeat();
    return ok;
  }

  @override
  Future<String> playPattern(ToyPattern pattern, int peakIntensity) async {
    _cancelAutoStop();
    _cancelPattern();
    final peak = _mapStrength(peakIntensity.clamp(1, 20));
    switch (pattern) {
      case ToyPattern.steady:
        final ok = await _sendUserScript(
            freq: 500, strength: peak, durationMs: 0xFFFF);
        if (ok) _startKeepAlive(500, peak);
        return ok ? 'steady vibration' : 'steady (BLE write failed)';
      case ToyPattern.wave:
        // Prime the connection with one synchronous write before starting the timer
        final waveOk = await _sendUserScript(
            freq: 500, strength: peak, durationMs: 0xFFFF);
        if (!waveOk) return 'wave (BLE write failed)';
        _startWave(peak);
        return 'gentle wave pattern';
      case ToyPattern.pulse:
        final pulseOk = await _sendUserScript(
            freq: 500, strength: peak, durationMs: 0xFFFF);
        if (!pulseOk) return 'pulse (BLE write failed)';
        _startPulse(peak);
        return 'rhythmic pulse';
      case ToyPattern.escalate:
        final escOk = await _sendUserScript(
            freq: 500, strength: peak ~/ 4, durationMs: 0xFFFF);
        if (!escOk) return 'escalate (BLE write failed)';
        _startEscalate(peak);
        return 'slow escalation';
      case ToyPattern.tease:
        final teaseOk = await _sendUserScript(
            freq: 500, strength: peak, durationMs: 0xFFFF);
        if (!teaseOk) return 'tease (BLE write failed)';
        _startTease(peak);
        return 'teasing bursts';
    }
  }

  // ── Patterns ────────────────────────────────────────────────────────────────

  void _startWave(int peak) {
    int step = 0;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 350), (_) async {
      final t = (step % 20) / 20.0;
      final str = max(1, (peak * (0.4 + 0.6 * _triangle(t))).round());
      await _sendScript(
          freq: 500, strength: str, durationMs: 0xFFFF, skipIfBusy: true);
      step++;
    });
  }

  void _startPulse(int peak) {
    bool on = false;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 450), (_) async {
      on = !on;
      if (on) {
        await _sendScript(
            freq: 500, strength: peak, durationMs: 0xFFFF, skipIfBusy: true);
      } else {
        await _sendScript(
            freq: 500, strength: 0, durationMs: 0, skipIfBusy: true);
      }
    });
  }

  void _startEscalate(int peak) {
    int current = peak ~/ 5;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 700), (_) async {
      await _sendScript(
          freq: 500, strength: current, durationMs: 0xFFFF, skipIfBusy: true);
      if (current < peak) current = min(peak, current + peak ~/ 8);
    });
  }

  void _startTease(int peak) {
    int tick = 0;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 280), (_) async {
      final on = tick % 5 < 2;
      await _sendScript(
        freq: 500,
        strength: on ? peak : 0,
        durationMs: 0xFFFF,
        skipIfBusy: true,
      );
      tick++;
    });
  }

  double _triangle(double t) => 1.0 - (2 * t - 1).abs();

  void _cancelPattern() {
    _patternTimer?.cancel();
    _patternTimer = null;
    _stopKeepAlive();
  }

  void _cancelAutoStop() {
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
  }

  // ── Keep-alive ───────────────────────────────────────────────────────────────

  void _startKeepAlive(int freq, int strength) {
    _stopKeepAlive();
    _stopHeartbeat(); // heartbeat not needed while vibrating
    _keepAliveFreq = freq;
    _keepAliveStr = strength;
    _keepAliveTimer =
        Timer.periodic(const Duration(milliseconds: 800), (_) async {
      if (_keepAliveStr > 0) {
        await _sendScript(
          freq: _keepAliveFreq, strength: _keepAliveStr, durationMs: 0xFFFF,
          skipIfBusy: true, // timer tick — skip if user command is in flight
        );
      }
    });
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  // ── VTrump script protocol ───────────────────────────────────────────────────

  /// Maps 0–20 AI intensity to VTrump strength*10 scale (0–1000).
  int _mapStrength(int intensity) {
    if (intensity <= 0) return 0;
    return ((intensity / 20.0) * 1000).round().clamp(1, 1000);
  }

  /// [skipIfBusy] = true for keep-alive / heartbeat timers: if another write is
  /// already in flight, just skip this periodic tick rather than stacking up.
  /// User commands (vibrate, stop, pattern) leave it false and wait briefly.
  Future<bool> _sendUserScript({
    required int freq,
    required int strength,
    required int durationMs,
  }) async {
    if (!isReady &&
        !(await ensureReady(timeout: const Duration(seconds: 22)))) {
      return false;
    }

    final ok = await _sendScript(
      freq: freq,
      strength: strength,
      durationMs: durationMs,
    );
    if (ok) return true;

    _log.warning('Flamingo write failed; reconnecting before retry');
    if (!(await ensureReady(timeout: const Duration(seconds: 22)))) {
      return false;
    }
    return _sendScript(
      freq: freq,
      strength: strength,
      durationMs: durationMs,
    );
  }

  Future<bool> _sendScript({
    required int freq, // frequency in 0.1 Hz units (e.g. 500 = 50 Hz)
    required int strength, // strength * 10 (0–1000)
    required int durationMs,
    bool skipIfBusy = false,
  }) async {
    if (!isReady) return false;

    // Serialize writes — Android BLE GATT can't handle concurrent writes.
    // Dart timers fire while we're awaiting a write, so we need this guard.
    if (_writing) {
      if (skipIfBusy) return true; // skip this keep-alive tick, that's fine
      // User command: wait up to 250 ms for the in-flight write to finish
      for (int i = 0; i < 5 && _writing; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (_writing || !isReady) return false;
    }
    _writing = true;

    final freqLo = freq & 0xFF;
    final freqHi = (freq >> 8) & 0xFF;
    final s10Lo = strength & 0xFF;
    final s10Hi = (strength >> 8) & 0xFF;
    final durLo = durationMs & 0xFF;
    final durHi = (durationMs >> 8) & 0xFF;

    // Payload: [tag(0x02), freqLo, freqHi, tag(0x04), s10Lo, s10Hi, 0,0, durLo, durHi, end(0x03)]
    final payload = [
      0x02,
      freqLo,
      freqHi,
      0x04,
      s10Lo,
      s10Hi,
      0x00,
      0x00,
      durLo,
      durHi,
      0x03
    ];
    final cmd = [0x02, 0x07, payload.length, ...payload];

    try {
      // Attempt 1
      try {
        await _writeChar!.write(cmd, withoutResponse: true);
        if (!skipIfBusy) {
          _log.info(
            'Flamingo write ok strength=$strength durationMs=$durationMs',
          );
        }
        return true;
      } catch (e) {
        _log.warning('Write failed (attempt 1): $e — retrying in 200 ms');
      }
      // Retry once: Android BLE sometimes needs a moment after reconnect
      await Future.delayed(const Duration(milliseconds: 200));
      if (!isReady) return false;
      try {
        await _writeChar!.write(cmd, withoutResponse: true);
        if (!skipIfBusy) {
          _log.info(
            'Flamingo write ok on retry strength=$strength '
            'durationMs=$durationMs',
          );
        }
        return true;
      } catch (e2) {
        _log.warning('Write failed (attempt 2): $e2');
        _connected = false;
        return false;
      }
    } finally {
      _writing = false;
    }
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _stopHeartbeat();
    _cancelAutoStop();
    _cancelPattern();
    _connected = false;
    _writeChar = null;
    _device?.disconnect();
  }
}

// ── Scanner & prefs ───────────────────────────────────────────────────────────

const _kFlamingoDeviceId = 'flamingo_device_id';
const _kFlamingoDeviceName = 'flamingo_device_name';

class FlamingoScanResult {
  final String deviceId;
  final String name;
  final int rssi;
  const FlamingoScanResult(
      {required this.deviceId, required this.name, required this.rssi});
}

Stream<List<FlamingoScanResult>> scanForFlamingo({
  Duration timeout = const Duration(seconds: 10),
}) async* {
  final results = <String, FlamingoScanResult>{};
  await FlutterBluePlus.startScan(timeout: timeout);
  yield* FlutterBluePlus.scanResults.map((scanResults) {
    for (final r in scanResults) {
      final name = r.device.platformName.toLowerCase();
      if (name.contains('flamingo') ||
          name.contains('magic motion') ||
          name.contains('magicmotion') ||
          name.contains('mm ')) {
        results[r.device.remoteId.str] = FlamingoScanResult(
          deviceId: r.device.remoteId.str,
          name: r.device.platformName,
          rssi: r.rssi,
        );
      }
    }
    return results.values.toList();
  });
}

Future<({String id, String name})?> loadFlamingoDevice() async {
  final prefs = await SharedPreferences.getInstance();
  final id = prefs.getString(_kFlamingoDeviceId);
  final name = prefs.getString(_kFlamingoDeviceName);
  if (id == null || name == null) return null;
  return (id: id, name: name);
}

Future<void> saveFlamingoDevice(String id, String name) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kFlamingoDeviceId, id);
  await prefs.setString(_kFlamingoDeviceName, name);
}

Future<void> clearFlamingoDevice() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kFlamingoDeviceId);
  await prefs.remove(_kFlamingoDeviceName);
}
