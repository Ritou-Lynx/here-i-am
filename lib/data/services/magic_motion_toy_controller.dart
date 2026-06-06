import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:memex/data/services/toy_controller.dart';
import 'package:memex/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prefs key where we store the last-connected device remote ID.
const _kDeviceId = 'toy_magic_motion_device_id';
const _kDeviceName = 'toy_magic_motion_device_name';

// ── Persistence helpers ───────────────────────────────────────────────────────

Future<void> saveMagicMotionDevice(String remoteId, String name) async {
  final p = await SharedPreferences.getInstance();
  await p.setString(_kDeviceId, remoteId);
  await p.setString(_kDeviceName, name);
}

Future<({String id, String name})?> loadMagicMotionDevice() async {
  final p = await SharedPreferences.getInstance();
  final id = p.getString(_kDeviceId);
  if (id == null || id.isEmpty) return null;
  return (id: id, name: p.getString(_kDeviceName) ?? id);
}

Future<void> clearMagicMotionDevice() async {
  final p = await SharedPreferences.getInstance();
  await p.remove(_kDeviceId);
  await p.remove(_kDeviceName);
}

// ── Controller ────────────────────────────────────────────────────────────────

/// Direct BLE controller for Magic Motion toys.
///
/// No third-party app required — connects directly via flutter_blue_plus.
/// Uses the VTrump SCRIPT command channel from the official Magic Motion app.
class MagicMotionToyController implements ToyController {
  final _log = getLogger('MagicMotionToyController');

  final String deviceId;
  final String deviceName;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _writeChar2; // secondary channel (6f488c06)
  StreamSubscription? _connectionSub;
  final List<StreamSubscription> _notifySubs = [];
  bool _connected = false;
  Timer? _patternTimer;

  // Last notification received per characteristic UUID → for debugging
  final Map<String, List<int>> lastNotifications = {};

  MagicMotionToyController({
    required this.deviceId,
    required this.deviceName,
  });

  @override
  bool get isReady => _connected && (_writeChar2 != null || _writeChar != null);

  // ── Connection ──────────────────────────────────────────────────────────────

  Future<void> connect() async {
    _device = BluetoothDevice.fromId(deviceId);

    _connectionSub = _device!.connectionState.listen((state) {
      _connected = state == BluetoothConnectionState.connected;
      if (!_connected) _writeChar = null;
      _log.info('BLE state: $state');
    });

    await _device!.connect(
      timeout: const Duration(seconds: 12),
      autoConnect: false,
    );

    final services = await _device!.discoverServices();
    _log.info(
        '$deviceName services: ${services.map((s) => s.serviceUuid).join(', ')}');

    // ── STRICT WHITELIST (hardware-safety critical) ──────────────────────────
    // We ONLY ever touch these exact UUIDs. We NEVER fall back to "any writable
    // characteristic", because the device's OAD firmware-update channel
    // (f000ffc*) is also writable — writing vibration bytes there puts the toy
    // into firmware-download/repair mode and can brick it.
    const kvdbCmdUuid = '6f488c04-f91f-11e3-a847-b2227cce2b54'; // KVDB command
    const scriptCmdUuid =
        '6f488c06-f91f-11e3-a847-b2227cce2b54'; // SCRIPT command (primary)
    // Characteristics we are allowed to subscribe-notify on (sensor/command only).
    const safeNotifyUuids = {
      '6f488c04-f91f-11e3-a847-b2227cce2b54',
      '6f488c06-f91f-11e3-a847-b2227cce2b54',
      '6f488c08-f91f-11e3-a847-b2227cce2b54',
      '6f468bfc-f91f-11e3-a847-b2227cce2b54',
      '6f468bfe-f91f-11e3-a847-b2227cce2b54',
    };
    // Service UUID prefixes that are absolutely forbidden to touch.
    bool isForbidden(String uuid) {
      final u = uuid.toLowerCase();
      return u.startsWith('f000ff') || // TI OAD firmware update
          u.contains('ffc0') ||
          u.contains('ffc1') ||
          u.contains('ffc2');
    }

    BluetoothCharacteristic? findExact(String uuid) {
      for (final svc in services) {
        if (isForbidden(svc.serviceUuid.toString())) continue;
        for (final c in svc.characteristics) {
          if (c.characteristicUuid.toString().toLowerCase() == uuid) return c;
        }
      }
      return null;
    }

    _writeChar2 = findExact(scriptCmdUuid); // primary control channel
    _writeChar = findExact(kvdbCmdUuid); // fallback (same envelope)

    if (_writeChar2 == null && _writeChar == null) {
      _log.warning('SAFETY: control characteristic not found — refusing to use '
          'any other writable characteristic. Aborting setup for $deviceName.');
      return; // do NOT touch anything else
    }
    _log.info(
        'Control char: ${(_writeChar2 ?? _writeChar)!.characteristicUuid}');

    // Subscribe ONLY to whitelisted notify characteristics.
    for (final svc in services) {
      if (isForbidden(svc.serviceUuid.toString())) continue;
      for (final char in svc.characteristics) {
        final uuid = char.characteristicUuid.toString().toLowerCase();
        if (!safeNotifyUuids.contains(uuid)) continue;
        if (char.properties.notify || char.properties.indicate) {
          try {
            await char.setNotifyValue(true);
            final sub = char.lastValueStream.listen((data) {
              if (data.isEmpty) return;
              lastNotifications[uuid] = data;
            });
            _notifySubs.add(sub);
            await Future.delayed(const Duration(milliseconds: 120));
          } catch (_) {}
        }
      }
    }
    await Future.delayed(const Duration(milliseconds: 300));
  }

  // ── ToyController interface ─────────────────────────────────────────────────

  // Keep-alive: the device only vibrates for the script's duration, so we
  // re-send the current level periodically to sustain continuous vibration
  // until stop() is called or a new command replaces it.
  Timer? _keepAlive;
  int _activeLevel = 0;

  void _startKeepAlive() {
    _keepAlive?.cancel();
    _keepAlive = Timer.periodic(const Duration(milliseconds: 800), (_) async {
      if (_activeLevel > 0 && _connected) {
        await _writeLevel(_activeLevel);
      }
    });
  }

  void _stopKeepAlive() {
    _keepAlive?.cancel();
    _keepAlive = null;
  }

  @override
  Future<bool> vibrate(int intensity, {int durationSeconds = 0}) async {
    _cancelPattern();
    _activeLevel = intensity.clamp(0, 20);
    final ok = await _writeLevel(_activeLevel);
    _startKeepAlive(); // sustain until stop or next command
    if (durationSeconds > 0) {
      Future.delayed(Duration(seconds: durationSeconds), stop);
    }
    return ok;
  }

  @override
  Future<bool> stop() async {
    _cancelPattern();
    _stopKeepAlive();
    _activeLevel = 0;
    return _writeLevel(0);
  }

  @override
  Future<String> playPattern(ToyPattern pattern, int peakIntensity) async {
    _cancelPattern();
    _stopKeepAlive(); // patterns drive their own repeating timer
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

  // ── BLE write (VTrump SCRIPT protocol, reverse-engineered from official app) ──

  /// Build a VTrump PWM-script command for continuous vibration.
  ///
  /// Format (from com.vtrump.vtble.kvdb.a + class i.z2):
  ///   envelope: [0xFF, 0x07, payloadLen, ...payload]
  ///   payload  = freqSeg + strengthSeg + terminator
  ///     freqSeg     = [0x02, freqLo, freqHi]            (kvdb.l)
  ///     strengthSeg = [0x04, (s*10)Lo, (s*10)Hi, delayLo, delayHi, durLo, durHi]  (kvdb.d)
  ///     terminator  = [0x03]                            (kvdb.a)
  /// All multi-byte values are little-endian (kvdb.t.h). strength s is 0-100.
  List<int> _buildScript(int strength100,
      {int freq = 50, int durationMs = 65535}) {
    final s10 = (strength100 * 10).clamp(0, 65535);
    final d = durationMs.clamp(0, 65535);
    final payload = <int>[
      0x02,
      freq & 0xff,
      (freq >> 8) & 0xff,
      0x04,
      s10 & 0xff,
      (s10 >> 8) & 0xff,
      0x00,
      0x00,
      d & 0xff,
      (d >> 8) & 0xff,
      0x03,
    ];
    // Lead byte 0x02 (warmup cmd) confirmed working on S1230/Unicorn via probe.
    return [0x02, 0x07, payload.length, ...payload];
  }

  /// Build a per-channel set command: [0x05, channel, strength, 0x00] segment.
  /// Channels (kvdb.a$a): 0=LED_0, 1=MOTOR_0, 2=LED_1, 3=MOTOR_1.
  /// strength is 0-100. Wrapped in the same [0x02,0x07,len,...] envelope.
  List<int> _buildChannelCmd(int channel, int strength100) {
    final s = strength100.clamp(0, 100);
    final payload = <int>[0x05, channel & 0xff, s & 0xff, 0x00];
    return [0x02, 0x07, payload.length, ...payload];
  }

  /// [intensity] is on the 0–20 AI scale; converts to 0–100 for the device.
  Future<bool> _writeLevel(int intensity) async {
    // SCRIPT command channel is 6f488c06 (_writeChar2); fall back to KVDB 6f488c04.
    final char = _writeChar2 ?? _writeChar;
    if (char == null || !_connected) return false;
    final level = (intensity.clamp(0, 20) * 5).clamp(0, 100);
    try {
      final cmd = _buildScript(level);
      final withoutResp = char.properties.writeWithoutResponse;
      await char.write(cmd, withoutResponse: withoutResp);
      return true;
    } catch (e) {
      _log.warning('script write failed: $e');
      return false;
    }
  }

  // ── Diagnostic probe ────────────────────────────────────────────────────────

  /// Try every known command format one by one.
  ///
  /// Calls [onTrying] with a 1-based index and description before each attempt.
  /// Each attempt vibrates for [holdMs] milliseconds then stops.
  /// Returns the index (1-based) of the first format that produced a BLE
  /// write-success — or -1 if none worked.
  ///
  /// Note: BLE write success != motor response. The user must confirm by feel.
  Future<int> probeCommandFormats({
    required void Function(int index, String description) onTrying,
    int holdMs = 2000,
  }) async {
    if (!_connected) return -1;
    final scriptChar =
        _writeChar2 ?? _writeChar; // 6f488c06 SCRIPT command (whitelisted)

    // Probe each channel individually so we can map channel→physical effect.
    // 0=LED_0, 1=MOTOR_0, 2=LED_1, 3=MOTOR_1.
    final attempts = <(String, BluetoothCharacteristic?, List<int>)>[
      ('通道0 (LED_0) 强度90', scriptChar, _buildChannelCmd(0, 90)),
      ('通道1 (MOTOR_0) 强度90', scriptChar, _buildChannelCmd(1, 90)),
      ('通道2 (LED_1) 强度90', scriptChar, _buildChannelCmd(2, 90)),
      ('通道3 (MOTOR_1) 强度90', scriptChar, _buildChannelCmd(3, 90)),
    ];

    for (int i = 0; i < attempts.length; i++) {
      final (desc, ch, bytes) = attempts[i];
      onTrying(i + 1, desc);
      if (ch == null) continue;
      try {
        final withoutResp = ch.properties.writeWithoutResponse;
        await ch.write(bytes, withoutResponse: withoutResp);
        await Future.delayed(Duration(milliseconds: holdMs));
        // Stop: zero out all 4 channels so each test is isolated.
        for (int chn = 0; chn < 4; chn++) {
          await ch
              .write(_buildChannelCmd(chn, 0), withoutResponse: withoutResp)
              .catchError((_) async {});
        }
        await Future.delayed(const Duration(milliseconds: 700));
      } catch (e) {
        _log.fine('probe $i failed: $e');
      }
    }
    return -1;
  }

  // ── Patterns ────────────────────────────────────────────────────────────────

  String _startWave(int peak) {
    int step = 0;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 300), (_) async {
      final t = (step % 20) / 20.0;
      final level = (peak * (0.5 + 0.5 * (1 - (2 * t - 1).abs()))).round();
      await _writeLevel(level);
      step++;
    });
    return 'gentle wave pattern peaking at intensity $peak';
  }

  String _startPulse(int peak) {
    bool on = false;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 400), (_) async {
      on = !on;
      await _writeLevel(on ? peak : 0);
    });
    return 'rhythmic pulse at intensity $peak';
  }

  String _startEscalate(int peak) {
    int current = 0;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) async {
      current = (current + 1).clamp(0, peak);
      await _writeLevel(current);
      if (current >= peak) _cancelPattern();
    });
    return 'slow escalation up to intensity $peak';
  }

  String _startTease(int peak) {
    int tick = 0;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 350), (_) async {
      await _writeLevel((tick % 5) < 2 ? peak : 0);
      tick++;
    });
    return 'teasing bursts at intensity $peak';
  }

  void _cancelPattern() {
    _patternTimer?.cancel();
    _patternTimer = null;
  }

  @override
  void dispose() {
    _cancelPattern();
    _stopKeepAlive();
    _writeLevel(0).then((_) => _device?.disconnect());
    _connectionSub?.cancel();
    for (final sub in _notifySubs) {
      sub.cancel();
    }
    _notifySubs.clear();
  }
}

// ── Scanner helper ────────────────────────────────────────────────────────────

/// A scan result entry shown in the settings UI.
class MagicMotionScanResult {
  final String deviceId;
  final String name;
  final int rssi;
  final bool isMagicMotion;
  const MagicMotionScanResult({
    required this.deviceId,
    required this.name,
    required this.rssi,
    this.isMagicMotion = false,
  });
}

/// Known Magic Motion BLE name prefixes (case-insensitive).
const _magicMotionNameHints = [
  'magic',
  'mm_',
  'unicorn',
  'flamingo',
  'umi',
  'zenith',
  'candy',
  'equinox',
  'krush',
  'kegel',
  'nyx',
  'solstice',
];

bool _isMagicMotionDevice(String name) {
  if (name.isEmpty) return false;
  final lower = name.toLowerCase();
  return _magicMotionNameHints.any((h) => lower.contains(h));
}

/// Scan for ALL nearby BLE devices.
///
/// Returns two categories:
///   - Magic Motion devices (name matches known patterns) — shown first
///   - Everything else — shown below, so the user can identify unknown names
///
/// No service UUID filter: different Magic Motion models advertise
/// different (or no) service UUIDs at scan time.
Stream<List<MagicMotionScanResult>> scanForMagicMotion({
  Duration timeout = const Duration(seconds: 10),
}) async* {
  await FlutterBluePlus.startScan(timeout: timeout);

  yield* FlutterBluePlus.scanResults.map((results) {
    final all = results.where((r) => r.rssi > -85).map((r) {
      final name = r.device.platformName.isNotEmpty
          ? r.device.platformName
          : r.advertisementData.advName.isNotEmpty
              ? r.advertisementData.advName
              : '';
      return MagicMotionScanResult(
        deviceId: r.device.remoteId.str,
        name: name.isNotEmpty
            ? name
            : '未知设备 (${r.device.remoteId.str.substring(0, 8)})',
        rssi: r.rssi,
        isMagicMotion: _isMagicMotionDevice(name),
      );
    }).toList();

    // Magic Motion devices first, then others by signal strength
    all.sort((a, b) {
      if (a.isMagicMotion && !b.isMagicMotion) return -1;
      if (!a.isMagicMotion && b.isMagicMotion) return 1;
      return b.rssi.compareTo(a.rssi);
    });
    return all;
  });
}
