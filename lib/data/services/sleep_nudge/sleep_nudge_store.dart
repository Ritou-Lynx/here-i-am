import 'package:drift/drift.dart';

import 'package:memex/data/services/sqlite_retry.dart';
import 'package:memex/db/app_database.dart';

import 'sleep_nudge_policy.dart';

/// 催睡来电的设置和状态存在 SQLite 的 KV 表里（不是 SharedPreferences）：
/// 设置页在主 isolate 写，常驻服务在前台服务 isolate 读，SharedPreferences
/// 的缓存跨 isolate 不同步。KV 表主键只有 key，所以 key 全部带前缀。
class SleepNudgeStore {
  SleepNudgeStore._();

  static const _bucket = 'sleep_nudge';
  static const _kEnabled = 'sleep_nudge.enabled';
  static const _kServer = 'sleep_nudge.server';
  static const _kTopic = 'sleep_nudge.topic';
  static const _kEngine = 'sleep_nudge.engine';
  static const _kMinGap = 'sleep_nudge.min_gap_minutes';
  static const _kMaxPerNight = 'sleep_nudge.max_per_night';
  static const _kMaxCall = 'sleep_nudge.max_call_minutes';
  static const _kLastId = 'sleep_nudge.last_message_id';
  static const _kLastCallAt = 'sleep_nudge.last_call_at';
  static const _kNightKey = 'sleep_nudge.night_key';
  static const _kNightCount = 'sleep_nudge.night_count';
  static const _kLastStatus = 'sleep_nudge.last_status';

  static Future<Map<String, String?>> _all() async {
    final db = AppDatabase.instance;
    final rows = await (db.select(db.kvStore)
          ..where((kv) => kv.bucket.equals(_bucket)))
        .get();
    return {for (final r in rows) r.key: r.value};
  }

  static Future<void> _put(Map<String, String?> values) async {
    final db = AppDatabase.instance;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await retryOnSqliteLocked(() async {
      await db.transaction(() async {
        for (final e in values.entries) {
          await db.into(db.kvStore).insertOnConflictUpdate(
                KvStoreCompanion.insert(
                  key: e.key,
                  bucket: const Value(_bucket),
                  value: Value(e.value),
                  updatedAt: Value(now),
                ),
              );
        }
      });
    });
  }

  static int _int(String? v, int fallback) {
    final n = int.tryParse(v ?? '');
    return n == null || n < 0 ? fallback : n;
  }

  static Future<SleepNudgeConfig> loadConfig() async {
    if (!AppDatabase.isInitialized) return const SleepNudgeConfig();
    final m = await _all();
    return SleepNudgeConfig(
      enabled: m[_kEnabled] == 'true',
      server: (m[_kServer]?.trim().isNotEmpty ?? false)
          ? m[_kServer]!.trim()
          : SleepNudgeConfig.defaultServer,
      topic: m[_kTopic]?.trim() ?? '',
      engine: SleepNudgeEngine.parse(m[_kEngine]),
      minGapMinutes: _int(m[_kMinGap], SleepNudgeConfig.defaultMinGapMinutes),
      maxPerNight: _int(m[_kMaxPerNight], SleepNudgeConfig.defaultMaxPerNight),
      maxCallMinutes:
          _int(m[_kMaxCall], SleepNudgeConfig.defaultMaxCallMinutes),
    );
  }

  static Future<void> saveConfig(SleepNudgeConfig c) async {
    final old = await loadConfig();
    final changedTopic =
        old.server != c.server.trim() || old.topic != c.topic.trim();
    await _put({
      _kEnabled: c.enabled.toString(),
      _kServer: c.server.trim(),
      _kTopic: c.topic.trim(),
      _kEngine: c.engine.id,
      _kMinGap: c.minGapMinutes.toString(),
      _kMaxPerNight: c.maxPerNight.toString(),
      _kMaxCall: c.maxCallMinutes.toString(),
      // 换了 topic 就从“现在”开始收，不翻旧消息。
      if (changedTopic || !c.enabled) _kLastId: null,
    });
  }

  static Future<String?> lastMessageId() async =>
      AppDatabase.isInitialized ? (await _all())[_kLastId] : null;

  static Future<void> setLastMessageId(String id) => _put({_kLastId: id});

  static Future<SleepNudgeHistory> loadHistory() async {
    if (!AppDatabase.isInitialized) return const SleepNudgeHistory();
    final m = await _all();
    final at = int.tryParse(m[_kLastCallAt] ?? '');
    return SleepNudgeHistory(
      lastCallAt:
          at == null ? null : DateTime.fromMillisecondsSinceEpoch(at * 1000),
      nightKey: m[_kNightKey],
      nightCount: _int(m[_kNightCount], 0),
    );
  }

  static Future<void> saveHistory(SleepNudgeHistory h) => _put({
        _kLastCallAt: h.lastCallAt == null
            ? null
            : (h.lastCallAt!.millisecondsSinceEpoch ~/ 1000).toString(),
        _kNightKey: h.nightKey,
        _kNightCount: h.nightCount.toString(),
      });

  /// 设置页显示的“最近一次”状态，只写时间和结果，不写推送内容。
  static Future<void> setLastStatus(String status) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return _put({
      _kLastStatus:
          '${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)} $status',
    });
  }

  static Future<String?> lastStatus() async =>
      AppDatabase.isInitialized ? (await _all())[_kLastStatus] : null;
}
