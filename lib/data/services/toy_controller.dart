import 'package:shared_preferences/shared_preferences.dart';

/// Vibration pattern names the AI can reference.
enum ToyPattern { steady, wave, pulse, escalate, tease }

/// Protocol backend for toy control.
enum ToyProtocol { lovense, buttplug, magicMotion, svakom }

/// Abstract controller interface shared by all backends.
///
/// Intensity is always on a 0–20 scale (matching the AI tool parameters).
/// Implementations translate to the hardware protocol's native scale internally.
abstract class ToyController {
  bool get isReady;

  /// Vibrate at [intensity] (0–20) for [durationSeconds] (0 = continuous).
  Future<bool> vibrate(int intensity, {int durationSeconds = 0});

  /// Stop all motors immediately.
  Future<bool> stop();

  /// Play a named software pattern at peak [intensity] (0–20).
  /// Returns a short description of what was started.
  Future<String> playPattern(ToyPattern pattern, int peakIntensity);

  void dispose();
}

// ── Persistent config ─────────────────────────────────────────────────────────

class ToyConfig {
  static const _kProtocol = 'toy_control_protocol';
  static const _kUrl = 'toy_control_url';
  static const _kAutoConnect = 'toy_control_auto_connect';

  final ToyProtocol protocol;
  final String url;
  final bool autoConnect;

  const ToyConfig({
    required this.protocol,
    required this.url,
    required this.autoConnect,
  });

  bool get isConfigured => url.isNotEmpty;

  static Future<ToyConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kProtocol);
    final url = prefs.getString(_kUrl) ?? '';
    final autoConnect = prefs.getBool(_kAutoConnect) ?? false;
    if (url.isEmpty) return null;
    final protocol = switch (raw) {
      'buttplug' => ToyProtocol.buttplug,
      'magic_motion' => ToyProtocol.magicMotion,
      'svakom' => ToyProtocol.svakom,
      _ => ToyProtocol.lovense,
    };
    return ToyConfig(
      protocol: protocol,
      url: url,
      autoConnect: autoConnect,
    );
  }

  static Future<void> save({
    required ToyProtocol protocol,
    required String url,
    bool autoConnect = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final tag = switch (protocol) {
      ToyProtocol.buttplug => 'buttplug',
      ToyProtocol.magicMotion => 'magic_motion',
      ToyProtocol.svakom => 'svakom',
      ToyProtocol.lovense => 'lovense',
    };
    await prefs.setString(_kProtocol, tag);
    await prefs.setString(_kUrl, url.trim().replaceAll(RegExp(r'/$'), ''));
    await prefs.setBool(_kAutoConnect, autoConnect);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kProtocol);
    await prefs.remove(_kUrl);
    await prefs.remove(_kAutoConnect);
  }
}
