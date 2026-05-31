import 'package:shared_preferences/shared_preferences.dart';

/// Vibration pattern names the AI can reference.
enum ToyPattern { steady, wave, pulse, escalate, tease }

/// Protocol backend for toy control.
enum ToyProtocol { lovense, buttplug }

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

  final ToyProtocol protocol;
  final String url;

  const ToyConfig({required this.protocol, required this.url});

  bool get isConfigured => url.isNotEmpty;

  static Future<ToyConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kProtocol);
    final url = prefs.getString(_kUrl) ?? '';
    if (url.isEmpty) return null;
    final protocol = raw == 'buttplug' ? ToyProtocol.buttplug : ToyProtocol.lovense;
    return ToyConfig(protocol: protocol, url: url);
  }

  static Future<void> save({
    required ToyProtocol protocol,
    required String url,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProtocol, protocol == ToyProtocol.buttplug ? 'buttplug' : 'lovense');
    await prefs.setString(_kUrl, url.trim().replaceAll(RegExp(r'/$'), ''));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kProtocol);
    await prefs.remove(_kUrl);
  }
}
