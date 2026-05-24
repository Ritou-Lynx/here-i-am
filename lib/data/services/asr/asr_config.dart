import 'package:shared_preferences/shared_preferences.dart';

/// Persisted ASR provider credentials.
///
/// Stored in SharedPreferences (per-device, not per-user). Currently only
/// Alibaba NLS is wired up; the field shape generalizes to any provider that
/// needs an AccessKey/AppKey triple.
class AsrConfig {
  final String accessKeyId;
  final String accessKeySecret;
  final String appKey;

  const AsrConfig({
    required this.accessKeyId,
    required this.accessKeySecret,
    required this.appKey,
  });

  bool get isComplete =>
      accessKeyId.isNotEmpty && accessKeySecret.isNotEmpty && appKey.isNotEmpty;

  static const _kAccessKeyId = 'asr_alibaba_access_key_id';
  static const _kAccessKeySecret = 'asr_alibaba_access_key_secret';
  static const _kAppKey = 'asr_alibaba_appkey';
  static const _kUseMediaKeys = 'voice_input_use_media_keys';

  /// Returns null if no credentials have been saved yet (any field missing).
  static Future<AsrConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final cfg = AsrConfig(
      accessKeyId: prefs.getString(_kAccessKeyId) ?? '',
      accessKeySecret: prefs.getString(_kAccessKeySecret) ?? '',
      appKey: prefs.getString(_kAppKey) ?? '',
    );
    return cfg.isComplete ? cfg : null;
  }

  static Future<void> save({
    required String accessKeyId,
    required String accessKeySecret,
    required String appKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessKeyId, accessKeyId);
    await prefs.setString(_kAccessKeySecret, accessKeySecret);
    await prefs.setString(_kAppKey, appKey);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessKeyId);
    await prefs.remove(_kAccessKeySecret);
    await prefs.remove(_kAppKey);
  }

  static Future<bool> getUseMediaKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kUseMediaKeys) ?? false;
  }

  static Future<void> setUseMediaKeys(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUseMediaKeys, enabled);
  }
}
