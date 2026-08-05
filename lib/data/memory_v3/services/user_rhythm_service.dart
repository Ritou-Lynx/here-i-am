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

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../../../db/app_database.dart';
import 'memory_card_query_service.dart';

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
      double? confidence,
      String? exceptionsJson}) async {
    final companion = UserRhythmsCompanion(
      description: description != null ? Value(description) : const Value.absent(),
      rrule: rrule != null ? Value(rrule) : const Value.absent(),
      location: location != null ? Value(location) : const Value.absent(),
      authority: authority != null ? Value(authority) : const Value.absent(),
      confidence: confidence != null ? Value(confidence) : const Value.absent(),
      exceptionsJson: exceptionsJson != null
          ? Value(exceptionsJson)
          : const Value.absent(),
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

  /// 追加一次单次取消（日历里的"删除单次事件"）。
  /// [dateStr] 格式 yyyy-MM-dd。幂等：重复日期不会重复写入。
  /// 节律本身（rrule）不动，只是 [dateStr] 当天 snapshot 不再展示该节律。
  Future<void> addException(String id, String dateStr) async {
    final rows = await (_db.select(_db.userRhythms)
          ..where((t) => t.id.equals(id)))
        .get();
    if (rows.isEmpty) return;
    final exceptions = parseExceptions(rows.first.exceptionsJson);
    if (exceptions.contains(dateStr)) return;
    exceptions.add(dateStr);
    await updateRhythm(id, exceptionsJson: jsonEncode(exceptions));
    _log.info('Rhythm exception added: $id date=$dateStr');
  }

  /// 解析 exceptionsJson → 日期列表（容错：空/坏 JSON 返回空列表）。
  static List<String> parseExceptions(String? exceptionsJson) {
    if (exceptionsJson == null || exceptionsJson.isEmpty) return [];
    try {
      final decoded = jsonDecode(exceptionsJson);
      if (decoded is List) return decoded.cast<String>();
    } catch (_) {}
    return [];
  }

  /// 该节律在 [day] 当天是否被单次取消。
  static bool isExceptedOn(UserRhythm rhythm, DateTime day) {
    final dateStr =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return parseExceptions(rhythm.exceptionsJson).contains(dateStr);
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

    final timeRangePattern = RegExp(r'^\s*(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s*$');

    for (final part in parts) {
      final eqIdx = part.indexOf('=');

      // Bare time range segment ("22:00-23:30") — no KEY= prefix. This is
      // the format the rhythm extractor prompt teaches; historically it was
      // dropped here because eqIdx < 0, making every parsed rrule empty.
      final rangeMatch = timeRangePattern.firstMatch(part);
      if (rangeMatch != null) {
        startTime = _normalizeHhMm(rangeMatch.group(1)!);
        endTime = _normalizeHhMm(rangeMatch.group(2)!);
        continue;
      }

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
        // 兼容 KEY=HH:MM-HH:MM 形式的时间段
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
      // 单次取消（"今天这节课不上了"）：当天跳过，节律本身仍在。
      if (isExceptedOn(r, moment)) continue;
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
  /// 对于跨午夜的睡眠节律，startTime > endTime 表示跨午夜，此时
  /// 晚间一侧（>= start）和次日早晨一侧（<= end）都算在时段内。
  static bool isWithinSlot(String currentTime, RhythmTimeSlot slot) {
    final crossesMidnight = slot.startTime.compareTo(slot.endTime) > 0;
    if (!crossesMidnight) {
      return _compareTime(currentTime, slot.startTime) >= 0 &&
          _compareTime(currentTime, slot.endTime) <= 0;
    }
    // 跨午夜：如 23:30-07:00。23:50（晚间）与 06:30（次日早晨）都在时段内。
    return _compareTime(currentTime, slot.startTime) >= 0 ||
        _compareTime(currentTime, slot.endTime) <= 0;
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
        if (isExceptedOn(r, moment)) continue;
        final parsed = parseRrule(r.rrule);
        for (final slot in parsed) {
          final within = isWithinSlot(currentTimeStr, slot);
          lines.add(
              '- Sleep pattern: ${slot.startTime}-${slot.endTime} '
              '(from data, confidence ${r.confidence.toStringAsFixed(1)})'
              '${within ? ' — ⚠️ user likely sleeping right now' : ''}');
        }
      }
      return lines.length > 1 ? lines.join('\n') : '';
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
      if (isExceptedOn(r, moment)) continue;
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

  /// "7:00" → "07:00"，保证字符串时间比较的位序一致。
  static String _normalizeHhMm(String t) {
    final parts = t.split(':');
    if (parts.length != 2) return t;
    final hh = parts[0].padLeft(2, '0');
    final mm = parts[1].padLeft(2, '0');
    return '$hh:$mm';
  }

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

  // ──────────────────────────────────────────────────────────────────────
  // Menstrual cycle tracking (special kind, no rrule)
  // ──────────────────────────────────────────────────────────────────────

  /// Record a menstrual period start/end and update the cycle rhythm.
  ///
  /// Called when a menstrual_record Memory Card is created or when
  /// RhythmSignalExtractor detects period mention in chat.
  ///
  /// This creates or updates a UserRhythm with kind="menstrual_cycle".
  /// The rrule field stores a JSON cycle prediction instead of an iCalendar
  /// recurrence rule.
  Future<void> recordMenstrualCycle({
    required DateTime startDate,
    DateTime? endDate,
    String? flowLevel,
    int? painLevel,
    List<String>? symptoms,
    String? notes,
  }) async {
    // Find existing menstrual_cycle rhythm
    final existing = await getActiveRhythmsByKind('menstrual_cycle');

    // Parse cycle history from existing rhythm
    List<Map<String, dynamic>> cycleHistory = [];
    String? rhythmId;
    if (existing.isNotEmpty) {
      rhythmId = existing.first.id;
      cycleHistory = _parseCycleHistory(existing.first.rrule);
    }

    // Check if this start date already exists in history
    final startDateStr = _dateStr(startDate);
    final existingEntry = cycleHistory.any((c) => c['start'] == startDateStr);
    if (!existingEntry) {
      // Add new cycle entry
      cycleHistory.add({
        'start': startDateStr,
        'end': endDate != null ? _dateStr(endDate) : null,
        'flow': flowLevel,
        'pain': painLevel,
        'symptoms': symptoms,
        'notes': notes,
      });
    } else if (endDate != null) {
      // Update end date for existing entry
      for (final c in cycleHistory) {
        if (c['start'] == startDateStr) {
          c['end'] = _dateStr(endDate);
          break;
        }
      }
    }

    // Sort by start date descending (most recent first)
    cycleHistory.sort((a, b) =>
        (b['start'] as String).compareTo(a['start'] as String));

    // Keep only last 12 cycles
    if (cycleHistory.length > 12) {
      cycleHistory = cycleHistory.sublist(0, 12);
    }

    // Calculate cycle metrics from history
    final cycleData = _calculateCycleMetrics(cycleHistory, startDate);

    // Build rrule JSON (stores cycle prediction, not an actual rrule)
    final rruleJson = _encodeCycleData(cycleData);

    if (rhythmId != null) {
      // Update existing rhythm
      await updateRhythm(rhythmId, rrule: rruleJson, confidence: cycleData.confidence);
      _log.info('Menstrual cycle rhythm updated: $rhythmId, '
          'cycles tracked: ${cycleHistory.length}, '
          'predicted next: ${cycleData.predictedNextStart}');
    } else {
      // Create new rhythm
      rhythmId = await createRhythm(
        kind: 'menstrual_cycle',
        description: '经期周期追踪',
        rrule: rruleJson,
        authority: 'agent_inferred',
        origin: 'mixed',
        confidence: cycleData.confidence,
      );
      _log.info('Menstrual cycle rhythm created: $rhythmId');
    }
  }

  /// Get current menstrual cycle status for check-in snapshot.
  Future<MenstrualCycleStatus?> getMenstrualCycleStatus({
    DateTime? now,
  }) async {
    final moment = now ?? DateTime.now();
    final rhythms = await getActiveRhythmsByKind('menstrual_cycle');
    if (rhythms.isEmpty) return null;

    final cycleData = _parseCycleData(rhythms.first.rrule);
    if (cycleData.cycleHistory.isEmpty) return null;

    final latest = cycleData.cycleHistory.first;
    final latestStart = _parseDate(latest['start'] as String);
    if (latestStart == null) return null;

    final latestEnd = latest['end'] != null
        ? _parseDate(latest['end'] as String)
        : null;

    // Determine current phase
    final daysSinceStart = moment.difference(latestStart).inDays;
    String phase;
    String phaseDescription;

    if (latestEnd == null && daysSinceStart <= 7) {
      // Period still ongoing (no end date, within 7 days of start)
      phase = 'menstrual';
      phaseDescription = '经期中（第 ${daysSinceStart + 1} 天）';
    } else if (latestEnd != null && daysSinceStart <= 7) {
      // Period ended recently
      final daysSinceEnd = moment.difference(latestEnd).inDays;
      if (daysSinceEnd < 7) {
        phase = 'follicular';
        phaseDescription = '卵泡期（经期结束后第 ${daysSinceEnd + 1} 天）';
      } else if (daysSinceEnd < 14) {
        phase = 'ovulation';
        phaseDescription = '排卵期附近';
      } else {
        phase = 'luteal';
        phaseDescription = '黄体期（经前阶段）';
      }
    } else if (daysSinceStart <= 14) {
      phase = 'follicular';
      phaseDescription = '卵泡期（经期后第 ${daysSinceStart - (latestEnd != null ? latestEnd.difference(latestStart).inDays + 1 : 7)} 天）';
    } else if (daysSinceStart <= 21) {
      phase = 'luteal';
      phaseDescription = '黄体期（经前阶段）';
    } else {
      phase = 'late';
      phaseDescription = '可能推迟了（已过 $daysSinceStart 天）';
    }

    // Check if period is predicted to start soon
    String? upcomingAlert;
    if (cycleData.predictedNextStart != null) {
      final daysUntil = cycleData.predictedNextStart!.difference(moment).inDays;
      if (daysUntil >= 0 && daysUntil <= 3 && phase != 'menstrual') {
        upcomingAlert = '预计 ${daysUntil == 0 ? '今天' : '$daysUntil 天后'}来';
      }
    }

    return MenstrualCycleStatus(
      phase: phase,
      phaseDescription: phaseDescription,
      latestStart: latestStart,
      latestEnd: latestEnd,
      avgCycleDays: cycleData.avgCycleDays,
      avgPeriodDays: cycleData.avgPeriodDays,
      predictedNextStart: cycleData.predictedNextStart,
      upcomingAlert: upcomingAlert,
      cycleCount: cycleData.cycleHistory.length,
      latestFlow: latest['flow'] as String?,
      latestPain: latest['pain'] as int?,
    );
  }

  /// Build menstrual cycle section for check-in snapshot.
  Future<String> buildMenstrualSnapshotSection({DateTime? now}) async {
    final status = await getMenstrualCycleStatus(now: now);
    if (status == null) return '';

    final lines = <String>['## Menstrual Cycle'];
    lines.add('- Phase: ${status.phase} - ${status.phaseDescription}');

    if (status.latestFlow != null) {
      lines.add('  Flow: ${status.latestFlow}');
    }
    if (status.latestPain != null) {
      lines.add('  Pain: ${status.latestPain}/10');
    }
    if (status.avgCycleDays != null) {
      lines.add('  Average cycle: ${status.avgCycleDays} days');
    }
    if (status.predictedNextStart != null) {
      lines.add('  Predicted next: ${_dateStr(status.predictedNextStart!)}');
    }
    if (status.upcomingAlert != null) {
      lines.add('  ⚠️ ${status.upcomingAlert}');
    }

    // Care hints for the companion
    if (status.phase == 'menstrual') {
      lines.add('  💡 Be gentle, ask about pain/cramps, don\'t suggest intense exercise.');
    } else if (status.phase == 'late') {
      lines.add('  💡 Period is late - ask if everything is okay, don\'t alarm.');
    } else if (status.upcomingAlert != null) {
      lines.add('  💡 Period coming soon - remind to prepare supplies, avoid cold food.');
    }

    return lines.join('\n');
  }

  /// Rebuild the `menstrual_cycle` rhythm from all surviving
  /// `menstrual_record` Memory Cards.
  ///
  /// Card is the source of truth; the rhythm row is a derived projection.
  /// Called after every card create / update / delete that touches a
  /// `menstrual_record` card, and once on backfill. Idempotent: running it
  /// twice with the same cards yields the same rhythm state.
  ///
  /// Dedupe rule: multiple cards with the same `startDate` are merged into a
  /// single cycle entry; the entry with the richest data (earliest `endDate`,
  /// non-null flow/pain/symptoms) wins per field. If two cards disagree on
  /// `endDate`, the earlier one is taken (periods can be re-recorded but the
  /// user's "it ended on X" statement is authoritative).
  Future<int> rebuildMenstrualRhythmFromCards() async {
    // Lazy-import to avoid a service-layer cycle (query service -> db).
    final queryService = MemoryCardQueryService(_db);
    final cards = await queryService.listCardsByStructuredFieldTypes(
      const {'menstrual_record'},
      limit: 60,
    );

    if (cards.isEmpty) {
      // No cards: expire any existing rhythm so the UI panel hides.
      final existing = await getActiveRhythmsByKind('menstrual_cycle');
      for (final r in existing) {
        await expireRhythm(r.id);
      }
      _log.info('rebuildMenstrualRhythmFromCards: 0 cards, expired '
          '${existing.length} rhythm(s)');
      return 0;
    }

    // Aggregate cards into per-startDate cycle entries.
    // Map<startDateStr, Map<field, value>>
    final byStart = <String, Map<String, dynamic>>{};
    for (final card in cards) {
      final fields = card.structuredFieldsMap;
      if (fields == null) continue;
      final startRaw = fields['startDate'] as String?;
      if (startRaw == null) continue;
      final startDate = DateTime.tryParse(startRaw);
      if (startDate == null) continue;
      final key = _dateStr(startDate);

      final existing = byStart[key];
      if (existing == null) {
        byStart[key] = {
          'start': key,
          'end': fields['endDate'] as String?,
          'flow': fields['flowLevel'] as String?,
          'pain': fields['painLevel'] is num
              ? (fields['painLevel'] as num).toInt()
              : int.tryParse('${fields['painLevel']}'),
          'symptoms': (fields['symptoms'] as List?)?.cast<String>(),
          'notes': fields['notes'] as String?,
        };
      } else {
        // Merge: prefer non-null / richer values.
        if (existing['end'] == null && fields['endDate'] != null) {
          existing['end'] = fields['endDate'] as String;
        } else if (fields['endDate'] != null &&
            existing['end'] != null) {
          // Both have end: take the earlier one.
          final a = DateTime.tryParse(existing['end'] as String);
          final b = DateTime.tryParse(fields['endDate'] as String);
          if (b != null && (a == null || b.isBefore(a))) {
            existing['end'] = fields['endDate'] as String;
          }
        }
        existing['flow'] ??= fields['flowLevel'] as String?;
        if (existing['pain'] == null) {
          existing['pain'] = fields['painLevel'] is num
              ? (fields['painLevel'] as num).toInt()
              : int.tryParse('${fields['painLevel']}');
        }
        if (existing['symptoms'] == null) {
          existing['symptoms'] = (fields['symptoms'] as List?)?.cast<String>();
        }
        existing['notes'] ??= fields['notes'] as String?;
      }
    }

    if (byStart.isEmpty) {
      // Cards exist but none had a parseable startDate - expire rhythm.
      final existing = await getActiveRhythmsByKind('menstrual_cycle');
      for (final r in existing) {
        await expireRhythm(r.id);
      }
      _log.warning('rebuildMenstrualRhythmFromCards: ${cards.length} card(s) '
          'but 0 had a valid startDate; expired ${existing.length} rhythm(s)');
      return 0;
    }

    var cycleHistory = byStart.values.toList();
    cycleHistory.sort((a, b) =>
        (b['start'] as String).compareTo(a['start'] as String));
    if (cycleHistory.length > 12) {
      cycleHistory = cycleHistory.sublist(0, 12);
    }

    final latestStart = _parseDate(cycleHistory.first['start'] as String)!;
    final cycleData = _calculateCycleMetrics(cycleHistory, latestStart);
    final rruleJson = _encodeCycleData(cycleData);

    final existing = await getActiveRhythmsByKind('menstrual_cycle');
    if (existing.isNotEmpty) {
      await updateRhythm(
        existing.first.id,
        rrule: rruleJson,
        confidence: cycleData.confidence,
      );
      _log.info('rebuildMenstrualRhythmFromCards: updated rhythm '
          '${existing.first.id}, cycles=${cycleHistory.length}, '
          'predictedNext=${cycleData.predictedNextStart}');
    } else {
      await createRhythm(
        kind: 'menstrual_cycle',
        description: '经期周期追踪',
        rrule: rruleJson,
        authority: 'agent_inferred',
        origin: 'memory_card',
        confidence: cycleData.confidence,
      );
      _log.info('rebuildMenstrualRhythmFromCards: created rhythm, '
          'cycles=${cycleHistory.length}, '
          'predictedNext=${cycleData.predictedNextStart}');
    }
    return cycleHistory.length;
  }

  // ── Cycle data helpers ──

  List<Map<String, dynamic>> _parseCycleHistory(String rruleJson) {
    try {
      final decoded = rruleJson;
      if (decoded.isEmpty || !decoded.startsWith('{')) return [];
      final data = _parseJson(decoded);
      final history = data?['cycleHistory'];
      if (history is List) {
        return history.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  _CycleData _parseCycleData(String rruleJson) {
    try {
      if (rruleJson.isEmpty || !rruleJson.startsWith('{')) {
        return _CycleData(cycleHistory: []);
      }
      final data = _parseJson(rruleJson);
      if (data == null) return _CycleData(cycleHistory: []);

      final history = (data['cycleHistory'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      return _CycleData(
        avgCycleDays: (data['avgCycleDays'] as num?)?.toInt(),
        avgPeriodDays: (data['avgPeriodDays'] as num?)?.toInt(),
        predictedNextStart: data['predictedNextStart'] != null
            ? _parseDate(data['predictedNextStart'] as String)
            : null,
        cycleHistory: history,
        confidence: (data['confidence'] as num?)?.toDouble() ?? 0.5,
      );
    } catch (_) {
      return _CycleData(cycleHistory: []);
    }
  }

  _CycleData _calculateCycleMetrics(
      List<Map<String, dynamic>> history, DateTime latestStart) {
    // Calculate cycle lengths (days between consecutive starts)
    final cycleLengths = <int>[];
    final periodLengths = <int>[];

    for (var i = 0; i < history.length - 1; i++) {
      final curr = _parseDate(history[i]['start'] as String);
      final prev = _parseDate(history[i + 1]['start'] as String);
      if (curr != null && prev != null) {
        cycleLengths.add(curr.difference(prev).inDays);
      }
    }

    for (final entry in history) {
      final start = _parseDate(entry['start'] as String);
      final end = entry['end'] != null ? _parseDate(entry['end'] as String) : null;
      if (start != null && end != null) {
        periodLengths.add(end.difference(start).inDays + 1);
      }
    }

    final avgCycle = cycleLengths.isEmpty
        ? null
        : (cycleLengths.reduce((a, b) => a + b) / cycleLengths.length).round();
    final avgPeriod = periodLengths.isEmpty
        ? null
        : (periodLengths.reduce((a, b) => a + b) / periodLengths.length).round();

    // Predict next start: use avg cycle if available, else default 28 days
    final cycleForPrediction = avgCycle ?? 28;
    final predictedNext = latestStart.add(Duration(days: cycleForPrediction));

    final confidence = history.length >= 3
        ? 0.9
        : history.length == 2
            ? 0.7
            : 0.5;

    return _CycleData(
      avgCycleDays: avgCycle,
      avgPeriodDays: avgPeriod,
      predictedNextStart: predictedNext,
      cycleHistory: history,
      confidence: confidence,
    );
  }

  String _encodeCycleData(_CycleData data) {
    final map = <String, dynamic>{
      'cycleHistory': data.cycleHistory,
      'confidence': data.confidence,
    };
    if (data.avgCycleDays != null) map['avgCycleDays'] = data.avgCycleDays;
    if (data.avgPeriodDays != null) map['avgPeriodDays'] = data.avgPeriodDays;
    if (data.predictedNextStart != null) {
      map['predictedNextStart'] = _dateStr(data.predictedNextStart!);
    }
    return _encodeJson(map);
  }

  Map<String, dynamic>? _parseJson(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  String _encodeJson(Map<String, dynamic> map) {
    return jsonEncode(map);
  }

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime? _parseDate(String s) {
    return DateTime.tryParse(s);
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

/// 经期周期当前状态快照。
class MenstrualCycleStatus {
  final String phase; // menstrual | follicular | ovulation | luteal | late
  final String phaseDescription;
  final DateTime latestStart;
  final DateTime? latestEnd;
  final int? avgCycleDays;
  final int? avgPeriodDays;
  final DateTime? predictedNextStart;
  final String? upcomingAlert;
  final int cycleCount;
  final String? latestFlow;
  final int? latestPain;

  MenstrualCycleStatus({
    required this.phase,
    required this.phaseDescription,
    required this.latestStart,
    this.latestEnd,
    this.avgCycleDays,
    this.avgPeriodDays,
    this.predictedNextStart,
    this.upcomingAlert,
    required this.cycleCount,
    this.latestFlow,
    this.latestPain,
  });
}

/// 经期周期预测内部数据。
class _CycleData {
  final int? avgCycleDays;
  final int? avgPeriodDays;
  final DateTime? predictedNextStart;
  final List<Map<String, dynamic>> cycleHistory;
  final double confidence;

  _CycleData({
    this.avgCycleDays,
    this.avgPeriodDays,
    this.predictedNextStart,
    required this.cycleHistory,
    this.confidence = 0.5,
  });
}