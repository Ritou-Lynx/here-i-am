import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Main-isolate wrapper for the host call-audio channels:
///
/// - `com.memexlab.memex/audio_route` — speaker route (earpiece vs loudspeaker).
///   (The `call_control` channel — in-call control notification — is driven
///   entirely by the foreground-task isolate; no main-isolate wrapper needed.)
///
/// The default speaker preference is remembered (`call_speakerphone_default`,
/// default true — 外放) and applied on every call start via [CallVoiceRouter].
class AudioRouteService {
  AudioRouteService._();

  static final AudioRouteService instance = AudioRouteService._();

  static const _audioRouteChannel =
      MethodChannel('com.memexlab.memex/audio_route');

  static const _speakerPrefKey = 'call_speakerphone_default';

  /// Remembered default for the speaker route (true = loudspeaker 外放).
  Future<bool> loadSpeakerPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_speakerPrefKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> saveSpeakerPreference(bool speakerOn) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_speakerPrefKey, speakerOn);
    } catch (_) {}
  }

  /// Route call audio to the loudspeaker (外放) or earpiece (听筒).
  Future<bool> setSpeakerphone(bool enabled) async {
    try {
      await _audioRouteChannel
          .invokeMethod('setSpeakerphone', {'enabled': enabled});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> getSpeakerphone() async {
    try {
      return await _audioRouteChannel.invokeMethod<bool>('getSpeakerphone') ??
          true;
    } catch (_) {
      return true;
    }
  }
}
