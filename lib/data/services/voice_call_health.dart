import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 通话体检：每次语音会话（通话、耳机键、聊天语音模式）一条记录，
/// 只存数字不存对话内容，保留最近 [maxSessions] 条，设置页可查看和复制。
///
/// 会话从 [begin] 开始（TtsService.prepareForVoiceSession 调用），之后每轮的
/// 延迟和每句家里电脑声音的结果都记到当前会话上，并立即落盘，所以不需要显式结束。
class VoiceCallHealth {
  VoiceCallHealth._();
  static final VoiceCallHealth instance = VoiceCallHealth._();

  static const prefsKey = 'voice_call_health_v1';
  static const maxSessions = 20;
  static const _maxSamples = 200;

  /// 测试注入点。
  Future<SharedPreferences> Function() prefsFactory =
      SharedPreferences.getInstance;
  DateTime Function() now = DateTime.now;

  VoiceCallSession? _current;
  Future<void> _pending = Future.value();

  VoiceCallSession? get current => _current;

  /// 开始一段新的语音会话。[health] 是家里电脑声音的体检结论，其他声音为 null。
  Future<void> begin({required String provider, String? health}) {
    _current = VoiceCallSession(
      startedAt: now(),
      provider: provider,
      health: health,
    );
    return _save();
  }

  /// 家里电脑声音的开场体检结论，体检完成后补到当前会话上。
  Future<void> setHealth(String health) {
    final s = _current;
    if (s == null) return Future.value();
    s.health = health;
    return _save();
  }

  /// 一轮对话结束时的延迟记录（VoiceLatencyTracker.toMap 的字段，-1 表示缺失）。
  Future<void> recordTurn(Map<String, dynamic> latency) {
    final s = _current;
    if (s == null) return Future.value();
    s.turns++;
    for (final key in VoiceCallSession.latencyKeys) {
      final v = latency[key];
      if (v is int && v >= 0) s._add(key, v);
    }
    return _save();
  }

  /// 家里电脑声音的一句：成功（带往返耗时）、失败，或没送过去（中文/太长/熔断中）。
  Future<void> recordTurbo(TurboOutcome outcome, {int? totalMs}) {
    final s = _current;
    if (s == null) return Future.value();
    switch (outcome) {
      case TurboOutcome.ok:
        s.turboOk++;
        if (totalMs != null) s._add('turbo_ms', totalMs);
      case TurboOutcome.failed:
        s.turboFailed++;
      case TurboOutcome.skipped:
        s.turboSkipped++;
    }
    return _save();
  }

  Future<List<VoiceCallSession>> load() async {
    await _pending;
    final prefs = await prefsFactory();
    return _decode(prefs.getString(prefsKey));
  }

  Future<void> clear() async {
    _current = null;
    final prefs = await prefsFactory();
    await prefs.remove(prefsKey);
  }

  /// 复制给 Claude 调参用的纯文本，一行一个会话。
  static String formatForCopy(List<VoiceCallSession> sessions) =>
      sessions.map((s) => s.summaryLine).join('\n');

  Future<void> _save() {
    final s = _current;
    if (s == null) return _pending;
    final snapshot = s.toJson();
    _pending = _pending.then((_) async {
      final prefs = await prefsFactory();
      final list = _decode(prefs.getString(prefsKey))
          .where((e) => e.id != snapshot['id'])
          .map((e) => e.toJson())
          .toList();
      list.insert(0, snapshot);
      if (list.length > maxSessions) list.removeRange(maxSessions, list.length);
      await prefs.setString(prefsKey, jsonEncode(list));
    }).catchError((_) {});
    return _pending;
  }

  static List<VoiceCallSession> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((m) => VoiceCallSession.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

enum TurboOutcome { ok, failed, skipped }

class VoiceCallSession {
  VoiceCallSession({
    required this.startedAt,
    required this.provider,
    this.health,
    String? id,
  }) : id = id ?? startedAt.microsecondsSinceEpoch.toString();

  /// 从 VoiceLatencyTracker 记录里取的阶段。
  static const latencyKeys = [
    'model_first_text_ms',
    'tts_first_audio_ms',
    'first_sound_ms',
    'formal_first_sound_ms',
  ];

  final String id;
  final DateTime startedAt;
  final String provider;
  String? health;
  int turns = 0;
  int turboOk = 0;
  int turboFailed = 0;
  int turboSkipped = 0;
  final Map<String, List<int>> samples = {};

  void _add(String key, int value) {
    final list = samples.putIfAbsent(key, () => []);
    list.add(value);
    if (list.length > VoiceCallHealth._maxSamples) list.removeAt(0);
  }

  int? median(String key) {
    final list = samples[key];
    if (list == null || list.isEmpty) return null;
    final sorted = [...list]..sort();
    return sorted[sorted.length ~/ 2];
  }

  String get summaryLine {
    String ms(String key) => median(key)?.toString() ?? '-';
    final t = startedAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final when =
        '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
    final parts = <String>[
      when,
      provider,
      '轮数 $turns',
      '模型首字 ${ms('model_first_text_ms')}',
      '首段音频 ${ms('tts_first_audio_ms')}',
      '首次出声 ${ms('first_sound_ms')}',
    ];
    if (provider == 'home_turbo') {
      parts.add('电脑声音 成功 $turboOk / 失败 $turboFailed / 跳过 $turboSkipped');
      parts.add('电脑往返 ${ms('turbo_ms')}');
      if (health != null) parts.add('开场体检 $health');
    }
    return parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'started_at': startedAt.toIso8601String(),
        'provider': provider,
        if (health != null) 'health': health,
        'turns': turns,
        'turbo_ok': turboOk,
        'turbo_failed': turboFailed,
        'turbo_skipped': turboSkipped,
        'samples': samples,
      };

  factory VoiceCallSession.fromJson(Map<String, dynamic> json) {
    final s = VoiceCallSession(
      id: json['id'] as String?,
      startedAt: DateTime.tryParse(json['started_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      provider: json['provider'] as String? ?? 'unknown',
      health: json['health'] as String?,
    );
    s.turns = (json['turns'] as num?)?.toInt() ?? 0;
    s.turboOk = (json['turbo_ok'] as num?)?.toInt() ?? 0;
    s.turboFailed = (json['turbo_failed'] as num?)?.toInt() ?? 0;
    s.turboSkipped = (json['turbo_skipped'] as num?)?.toInt() ?? 0;
    final raw = json['samples'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String && v is List) {
          s.samples[k] = v.whereType<num>().map((n) => n.toInt()).toList();
        }
      });
    }
    return s;
  }
}
