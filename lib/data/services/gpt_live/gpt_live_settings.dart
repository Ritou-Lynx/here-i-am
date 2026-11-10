import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gpt_live_protocol.dart';

const delegateModelOptions = <String, String>{
  '': '不委托（只用通话模型自己）',
  'gpt-5.6-luna': 'gpt-5.6-luna（最便宜，默认）',
  'gpt-5.6-terra': 'gpt-5.6-terra',
  'gpt-5.6-sol': 'gpt-5.6-sol（最强，最贵）',
};

/// GPT-Live 备选通话的配置：OpenAI API key 放 secure storage，声音名放偏好。
class GptLiveSettings {
  GptLiveSettings._();

  static const _keyApiKey = 'gpt_live.openai_api_key';
  static const _keyVoice = 'gpt_live.voice';
  static const _keyExtra = 'gpt_live.extra_instructions';
  static const _keyLastCall = 'gpt_live.last_call';
  static const _keyIdleHangupMinutes = 'gpt_live.idle_hangup_minutes';
  static const _keyDelegateModel = 'gpt_live.delegate_model';
  static const _defaultDelegateModel = 'gpt-5.6-luna';

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

  /// 通话附加说明：用户自己写的话，原样追加到 instructions 末尾。
  static Future<String> getExtraInstructions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyExtra)?.trim() ?? '';
  }

  static Future<void> setExtraInstructions(String text) async {
    final prefs = await SharedPreferences.getInstance();
    final v = text.trim();
    if (v.isEmpty) {
      await prefs.remove(_keyExtra);
    } else {
      await prefs.setString(_keyExtra, v);
    }
  }

  static Future<int> getIdleHangupMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_keyIdleHangupMinutes) ?? 5;
    return value < 0 ? 0 : value;
  }

  static Future<void> setIdleHangupMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyIdleHangupMinutes, minutes < 0 ? 0 : minutes);
  }

  static Future<String> getDelegateModel() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyDelegateModel);
    return delegateModelOptions.containsKey(value)
        ? value!
        : _defaultDelegateModel;
  }

  static Future<void> setDelegateModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDelegateModel, model.trim());
  }

  static Future<GptLiveCallRecord?> getLastCallRecord() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyLastCall);
    if (raw == null) return null;
    try {
      return GptLiveCallRecord.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setLastCallRecord(GptLiveCallRecord r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastCall, jsonEncode(r.toJson()));
  }
}

/// 最近一通 GPT-Live 的时长和结束原因（只存本机，只留一条）。
class GptLiveCallRecord {
  const GptLiveCallRecord({
    required this.startedAt,
    required this.seconds,
    required this.reason,
    this.serverError,
  });

  final DateTime startedAt;
  final int seconds;

  /// user / max_duration / screen_closed / server:<原因> / failed:<错误>
  final String reason;
  final String? serverError;

  Map<String, dynamic> toJson() => {
        'started_at': startedAt.toIso8601String(),
        'seconds': seconds,
        'reason': reason,
        if (serverError != null) 'server_error': serverError,
      };

  factory GptLiveCallRecord.fromJson(Map<String, dynamic> j) =>
      GptLiveCallRecord(
        startedAt: DateTime.parse(j['started_at'] as String),
        seconds: (j['seconds'] as num).toInt(),
        reason: j['reason'] as String,
        serverError: j['server_error'] as String?,
      );

  static String reasonTextFor(String reason) {
    if (reason == 'user') return '你挂断';
    if (reason == 'max_duration') return '到了单通上限';
    if (reason == 'screen_closed') return '通话页被关闭';
    if (reason == 'idle') return '太久没人说话，自动挂断';
    if (reason.startsWith('server:')) {
      return 'OpenAI 结束了会话（${reason.substring(7)}）';
    }
    if (reason.startsWith('failed:')) return '连接出错（${reason.substring(7)}）';
    return reason;
  }

  String get reasonText => reasonTextFor(reason);

  String describe() {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = startedAt;
    final when =
        '${t.month}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
    final dur = '${seconds ~/ 60} 分 ${seconds % 60} 秒';
    final err = serverError == null ? '' : '；服务端报错：$serverError';
    return '$when · $dur · $reasonText$err';
  }
}
