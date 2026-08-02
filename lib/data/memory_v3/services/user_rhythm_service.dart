/// User Rhythm Service — 结构化用户日常节律。
///
/// 这是"用户的生活是怎样的"的事实层。不设目标、不做判断，只记录用户
/// 当前阶段的作息、工作、课表等周期性节律。
///
/// 数据来源：
///   - 对话信号（"我 7 点下班""周二有课"）→ Dreaming/Insights 推断后写入
///   - COROS 数据（14 天睡眠中位数）→ 自动推断 sleep_pattern
///   - Memory Cards（schedule/task）→ 补充/验证
///
/// 消费者：
///   - Check-in snapshot（"现在 06:00，用户通常 09:00 起，别打扰"）
///   - Life Insights（作为 baseline 推断输入）
///   - Growth Pacts（作为 target 的 dailyAdjust 依据）
library;

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../../../db/app_database.dart';

final _log = Logger('UserRhythmService');
const _uuid = Uuid();

class UserRhythmService {
  final AppDatabase _db;

  UserRhythmService({required AppDatabase db}) : _db = db;

  static bool _initialized = false;
  static UserRhythmService? _instance;

  static bool get isInitialized => _initialized;

  static void init(AppDatabase db) {
    _instance = UserRhythmService(db: db);
    _initialized = true;
  }

  static UserRhythmService get instance {
    if (!_initialized || _instance == null) {
      throw StateError('UserRhythmService not initialized. Call init() first.');
    }
    return _instance!;
  }

  // ──────────────────────────────────────────────────────────────────────
  // CRUD
  // ──────────────────────────────────────────────────────────────────────

  Future<String> createRhythm({
    required String kind,
    required String description,
    required String rrule,
    String location = 'unknown',
    String authority = 'agent_inferred',
    String origin = 'conversation',
    double confidence = 0.5,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.userRhythms).insert(
          UserRhythmsCompanion.insert(
            id: id,
            kind: kind,
            description: description,
            rrule: rrule,
            location: Value(location),
            authority: Value(authority),
            origin: Value(origin),
            confidence: Value(confidence),
            validFrom: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    _log.info('Rhythm created: $id kind=$kind "$description"');
    return id;
  }

  Future<void> updateRhythm(String id,
      {String? description,
      String? rrule,
      String? location,
      String? authority,
      double? confidence}) async {
    final companion = UserRhythmsCompanion(
      description: description != null ? Value(description) : const Value.absent(),
      rrule: rrule != null ? Value(rrule) : const Value.absent(),
      location: location != null ? Value(location) : const Value.absent(),
      authority: authority != null ? Value(authority) : const Value.absent(),
      confidence: confidence != null ? Value(confidence) : const Value.absent(),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    );
    await (_db.update(_db.userRhythms)
          ..where((t) => t.id.equals(id)))
        .write(companion);
  }

  Future<void> expireRhythm(String id) async {
    await (_db.update(_db.userRhythms)
          ..where((t) => t.id.equals(id)))
        .write(UserRhythmsCompanion(
      validUntil: Value(DateTime.now().millisecondsSinceEpoch),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  // ──────────────────────────────────────────────────────────────────────
  // Query — active rhythms
  // ──────────────────────────────────────────────────────────────────────

  /// 所有当前有效的节律（validUntil is null 或在未来）。
  Future<List<UserRhythm>> getActiveRhythms() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final query = _db.select(_db.userRhythms)
      ..where((t) =>
          t.validUntil.isNull() | t.validUntil.isBiggerThanValue(now))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return query.get();
  }

  /// 按 kind 过滤的活跃节律。
  Future<List<UserRhythm>> getActiveRhythmsByKind(String kind) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final query = _db.select(_db.userRhythms)
      ..where((t) =>
          t.kind.equals(kind) &
          (t.validUntil.isNull() | t.validUntil.isBiggerThanValue(now)))
      ..orderBy([(t) => OrderingTerm.desc(t.confidence)]);
    return query.get();
  }

  // ──────────────────────────────────────────────────────────────────────
  // RRULE parsing — 轻量解析，不引入第三方库
  // ──────────────────────────────────────────────────────────────────────

  /// 解析 rrule，返回星期几映射的时间段列表。
  ///
  /// rrule 格式：FREQ=DAILY|WEEKLY;BYDAY=MO,TU,WE,TH,FR;HH:MM-HH:MM
  /// 或 FREQ=DAILY;HH:MM-HH:MM（每天同一时段）
  ///
  /// 返回 [{weekdays: [1,3,5], startTime: "22:00", endTime: "23:30"}]
  /// weekdays 用 ISO 8601（1=Mon ... 7=Sun）
  static List<RhythmTimeSlot> parseRrule(String rrule) {
    final parts = rrule.split(';');
    String? freq;
    List<int>? byDays;
    String? startTime;
    String? endTime;

    for (final part in parts) {
      final eqIdx = part.indexOf('=');
      if (eqIdx < 0) continue;
      final key = part.substring(0, eqIdx).trim().toUpperCase();
      final value = part.substring(eqIdx + 1).trim();

      if (key == 'FREQ') {
        freq = value.toUpperCase();
      } else if (key == 'BYDAY') {
        byDays = value.split(',').map((d) {
          switch (d.trim().toUpperCase()) {
            case 'MO':
              return 1;
            case 'TU':
              return 2;
            case 'WE':
              return 3;
            case 'TH':
              return 4;
            case 'FR':
              return 5;
            case 'SA':
              return 6;
            case 'SU':
              return 7;
            default:
              return 0;
          }
        }).where((d) => d > 0).toList();
      } else if (value.contains('-')) {
        // 时间段 HH:MM-HH:MM
        final dash = value.indexOf('-');
        if (dash > 0) {
          startTime = value.substring(0, dash).trim();
          endTime = value.substring(dash + 1).trim();
        }
      }
    }

    if (startTime == null) return [];

    final weekdays = byDays ??
        (freq == 'DAILY' ? [1, 2, 3, 4, 5, 6, 7] : [1, 2, 3, 4, 5]);

    return [
      RhythmTimeSlot(
        weekdays: weekdays,
        startTime: startTime,
        endTime: endTime ?? startTime,
      ),
    ];
  }

  /// 查找今天（按星期几）活跃的节律时间槽。
  /// 返回当前时间生效的 slots，用于 check-in snapshot。
  Future<List<ActiveRhythmSlot>> getTodayActiveSlots({
    DateTime? now,
  }) async {
    final moment = now ?? DateTime.now();
    final weekday = moment.weekday; // 1=Mon ... 7=Sun
    final rhythms = await getActiveRhythms();

    final slots = <ActiveRhythmSlot>[];
    for (final r in rhythms) {
      final parsed = parseRrule(r.rrule);
      for (final slot in parsed) {
        if (slot.weekdays.contains(weekday)) {
          slots.add(ActiveRhythmSlot(
            rhythm: r,
            slot: slot,
          ));
        }
      }
    }
    return slots;
  }

  /// 判断当前时间是否在某个节律的活跃时段内（如"现在在工作时间内"）。
  /// 对于跨午夜的睡眠节律，startTime > endTime 表示跨午夜。
  static bool isWithinSlot(String currentTime, RhythmTimeSlot slot) {
    final cmp = _compareTime(currentTime, slot.startTime);
    if (cmp < 0) return false;

    if (slot.startTime.compareTo(slot.endTime) > 0) {
      // 跨午夜：如 23:00-07:00
      // currentTime >= startTime（今天）或 currentTime < endTime（明天早上）
      return true; // 已经过 startTime，且 endTime 在明天
    }
    return _compareTime(currentTime, slot.endTime) <= 0;
  }

  /// 判断当前时间是否在某个节律时段开始前的 N 分钟内。
  /// 用于"快到下班时间了""快到上课时间了"这类提醒。
  static bool isApproachingSlotStart(
      String currentTime, RhythmTimeSlot slot, int withinMinutes) {
    final diff = _timeDiffMinutes(currentTime, slot.startTime);
    return diff >= 0 && diff <= withinMinutes;
  }

  /// 判断当前时间是否在某个节律时段结束后的 N 分钟内。
  /// 用于"刚下班""刚下课"这类时机判断。
  static bool isAfterSlotEnd(
      String currentTime, RhythmTimeSlot slot, int withinMinutes) {
    final diff = _timeDiffMinutes(slot.endTime, currentTime);
    return diff >= 0 && diff <= withinMinutes;
  }

  // ──────────────────────────────────────────────────────────────────────
  // Snapshot text — 给 check-in snapshot 用
  // ──────────────────────────────────────────────────────────────────────

  /// 构建 check-in snapshot 用的 "User's Daily Rhythm" 文本段。
  Future<String> buildSnapshotSection({DateTime? now}) async {
    final moment = now ?? DateTime.now();
    final hh = moment.hour.toString().padLeft(2, '0');
    final mm = moment.minute.toString().padLeft(2, '0');
    final currentTimeStr = '$hh:$mm';

    final slots = await getTodayActiveSlots(now: moment);
    if (slots.isEmpty) {
      // 即使今天没有特定 slot，也注入睡眠节律（如果有），因为它是跨天的
      final sleepRhythms = await getActiveRhythmsByKind('sleep_pattern');
      if (sleepRhythms.isEmpty) return '';

      final lines = <String>['## User\'s Daily Rhythm (active today)'];
      for (final r in sleepRhythms) {
        final parsed = parseRrule(r.rrule);
        for (final slot in parsed) {
          final within = isWithinSlot(currentTimeStr, slot);
          lines.add(
              '- Sleep pattern: ${slot.startTime}-${slot.endTime} '
              '(from data, confidence ${r.confidence.toStringAsFixed(1)})'
              '${within ? ' — ⚠️ user likely sleeping right now' : ''}');
        }
      }
      return lines.join('\n');
    }

    final lines = <String>['## User\'s Daily Rhythm (active today)'];
    for (final entry in slots) {
      final r = entry.rhythm;
      final slot = entry.slot;
      final within = isWithinSlot(currentTimeStr, slot);
      final approaching =
          isApproachingSlotStart(currentTimeStr, slot, 30);
      final afterEnd = isAfterSlotEnd(currentTimeStr, slot, 60);

      final tags = <String>[];
      if (within) tags.add('ongoing');
      if (approaching) tags.add('starting soon');
      if (afterEnd) tags.add('just ended');
      if (r.location == 'home') tags.add('at home');

      lines.add(
          '- ${r.kind}/${r.description}: ${slot.startTime}-${slot.endTime}'
          '${tags.isNotEmpty ? ' (${tags.join(', ')})' : ''}');
    }

    // 检查睡眠状态
    final sleepRhythms = await getActiveRhythmsByKind('sleep_pattern');
    for (final r in sleepRhythms) {
      final parsed = parseRrule(r.rrule);
      for (final slot in parsed) {
        if (isWithinSlot(currentTimeStr, slot)) {
          lines.add(
              '- ⚠️ Sleep pattern: ${slot.startTime}-${slot.endTime} — '
              'user likely sleeping right now');
        }
      }
    }

    return lines.join('\n');
  }

  // ──────────────────────────────────────────────────────────────────────
  // Time helpers
  // ──────────────────────────────────────────────────────────────────────

  static int _compareTime(String a, String b) {
    final pa = a.split(':').map(int.parse).toList();
    final pb = b.split(':').map(int.parse).toList();
    if (pa[0] != pb[0]) return pa[0].compareTo(pb[0]);
    return pa[1].compareTo(pb[1]);
  }

  static int _timeDiffMinutes(String from, String to) {
    final pf = from.split(':').map(int.parse).toList();
    final pt = to.split(':').map(int.parse).toList();
    return (pt[0] * 60 + pt[1]) - (pf[0] * 60 + pf[1]);
  }
}

/// rrule 解析出的一个时间槽。
class RhythmTimeSlot {
  final List<int> weekdays; // ISO 8601: 1=Mon ... 7=Sun
  final String startTime; // "HH:MM"
  final String endTime; // "HH:MM"

  RhythmTimeSlot({
    required this.weekdays,
    required this.startTime,
    required this.endTime,
  });
}

/// 今天活跃的节律 + 其时间槽。
class ActiveRhythmSlot {
  final UserRhythm rhythm;
  final RhythmTimeSlot slot;

  ActiveRhythmSlot({required this.rhythm, required this.slot});
}