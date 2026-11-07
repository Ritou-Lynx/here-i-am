import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gpt_live_protocol.dart';

/// GPT-Live 备选通话的配置：OpenAI API key 放 secure storage，声音名放偏好。
class GptLiveSettings {
  GptLiveSettings._();

  static const _keyApiKey = 'gpt_live.openai_api_key';
  static const _keyVoice = 'gpt_live.voice';

  static FlutterSecureStorage storage = const FlutterSecureStorage();

  static Future<String?> getApiKey() async {
    try {
      final v = await storage.read(key: _keyApiKey);
      return (v == null || v.trim().isEmpty) ? null : v.trim();
    } catch (_) {
      return null;
    }
  }

  static Future<void> setApiKey(String? key) async {
    final v = key?.trim() ?? '';
    if (v.isEmpty) {
      await storage.delete(key: _keyApiKey);
    } else {
      await storage.write(key: _keyApiKey, value: v);
    }
  }

  static Future<String> getVoice() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_keyVoice)?.trim();
    return (v == null || v.isEmpty) ? GptLiveProtocol.defaultVoice : v;
  }

  static Future<void> setVoice(String voice) async {
    final prefs = await SharedPreferences.getInstance();
    final v = voice.trim();
    if (v.isEmpty) {
      await prefs.remove(_keyVoice);
    } else {
      await prefs.setString(_keyVoice, v);
    }
  }
}
