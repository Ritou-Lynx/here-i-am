import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:memex/data/services/checkin_service.dart';
import 'package:memex/data/services/reminder_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';

/// Turns explicit upcoming User-truth plans into one quiet pre-outing
/// checkpoint for the companion. The checkpoint wakes the agent; the agent
/// still decides whether weather/route context warrants contacting the user.
class ProactiveOutingService {
  ProactiveOutingService({AppDatabase? db}) : _testDb = db;

  static final ProactiveOutingService instance = ProactiveOutingService();

  static const Duration defaultLeadTime = Duration(minutes: 45);
  static const Duration defaultHorizon = Duration(days: 7);
  static const String contextKind = 'proactive_outing';
  static const String _kvBucket = 'proactive_outing';

  final AppDatabase? _testDb;
  final _logger = getLogger('ProactiveOutingService');

  AppDatabase get _db => _testDb ?? AppDatabase.instance;

  /// Reconciles exact-time checkpoints for upcoming outings.
  ///
  /// No card is created here: this consumes only explicit User-truth cards and
  /// writes internal system queue rows. [alarmScheduler] is injectable so the
  /// database behavior can be tested without Android alarm APIs.
  Future<int> refreshSchedule({
    DateTime? now,
    Duration leadTime = defaultLeadTime,
    Duration horizon = defaultHorizon,
    Future<void> Function(String reminderId, DateTime dueAt)? alarmScheduler,
  }) async {
    if (!AppDatabase.isInitialized) return 0;
    if (!await CheckinService.instance.isEnabled()) return 0;

    final effectiveNow = now ?? DateTime.now();
    final candidates = await findUpcomingCandidates(
      now: effectiveNow,
      horizon: horizon,
    );
    var scheduled = 0;

    for (final candidate in candidates) {
      final dedupeKey = _dedupeKey(candidate);
      final existing = await _db.kvStoreLookup(
        key: dedupeKey,
        bucket: _kvBucket,
      );
      if (existing != null) continue;

      var dueAt = candidate.eventAt.subtract(leadTime);
      final earliest = effectiveNow.add(const Duration(minutes: 1));
      if (dueAt.isBefore(earliest)) dueAt = earliest;
      if (!dueAt.isBefore(candidate.eventAt)) continue;

      await _supersedeOlderCheckpoint(candidate.cardId);
      final context = jsonEncode({
        'kind': contextKind,
        'card_id': candidate.cardId,
        'title': candidate.title,
        'event_at': candidate.eventAt.toIso8601String(),
        if (candidate.placeHint != null) 'place_hint': candidate.placeHint,
        if (candidate.walkingMinutes != null)
          'walking_minutes': candidate.walkingMinutes,
      });
      final reminderId = await ReminderService.instance.createReminder(
        text: '出门前检查“${candidate.title}”的天气、路线暴露和是否需要提醒。',
        dueAt: dueAt,
        contextJson: context,
      );
      await (alarmScheduler ?? _scheduleAlarm)(reminderId, dueAt);

      final nowSec = effectiveNow.millisecondsSinceEpoch ~/ 1000;
      await _db.into(_db.kvStore).insertOnConflictUpdate(
            KvStoreCompanion.insert(
              key: dedupeKey,
              bucket: const Value(_kvBucket),
              value: Value(reminderId),
              updatedAt: Value(nowSec),
            ),
          );
      scheduled++;
    }

    if (scheduled > 0) {
      _logger.info('Scheduled $scheduled proactive outing checkpoint(s)');
    }
    return scheduled;
  }

  /// Finds timed plans that carry an explicit place field or clear outing
  /// language. Generic deadlines and online tasks are intentionally excluded.
  Future<List<ProactiveOutingCandidate>> findUpcomingCandidates({
    required DateTime now,
    Duration horizon = defaultHorizon,
  }) async {
    if (!AppDatabase.isInitialized) return const [];

    final rows = await (_db.select(_db.memoryCardStructuredFields).join([
      innerJoin(
        _db.memoryCards,
        _db.memoryCards.id.equalsExp(_db.memoryCardStructuredFields.cardId),
      ),
      leftOuterJoin(
        _db.memoryCardSources,
        _db.memoryCardSources.cardId.equalsExp(
          _db.memoryCardStructuredFields.cardId,
        ),
      ),
    ])
          ..where(
            _db.memoryCards.status.isNull() |
                _db.memoryCards.status.equals('active'),
          ))
        .get();

    final horizonEnd = now.add(horizon);
    final result = <ProactiveOutingCandidate>[];
    for (final row in rows) {
      final card = row.readTable(_db.memoryCards);
      if (card.type != 'schedule' &&
          card.type != 'plan' &&
          card.type != 'event' &&
          card.type != 'task') {
        continue;
      }
      final structured = row.readTable(_db.memoryCardStructuredFields);
      final source = row.readTableOrNull(_db.memoryCardSources);
      final fields = _decodeFields(structured.fieldsJson);
      final eventAt = _extractEventTime(fields);
      if (eventAt == null ||
          !eventAt.isAfter(now) ||
          eventAt.isAfter(horizonEnd)) {
        continue;
      }

      final placeHint = _extractPlaceHint(fields) ?? source?.recordedPlace;
      final searchable = [
        card.title,
        card.retrievalText,
        source?.rawInput ?? '',
      ].join('\n');
      if (placeHint == null && !_outingLanguage.hasMatch(searchable)) continue;

      result.add(ProactiveOutingCandidate(
        cardId: card.id,
        title: card.title,
        eventAt: eventAt,
        placeHint: placeHint,
        walkingMinutes: _extractWalkingMinutes(fields),
      ));
    }
    result.sort((a, b) => a.eventAt.compareTo(b.eventAt));
    return result;
  }

  /// Stops only automatically-created outing checkpoints. Explicit user
  /// reminders remain untouched.
  Future<int> cancelPendingCheckpoints() async {
    if (!AppDatabase.isInitialized) return 0;
    final count = await (_db.update(_db.systemMessageQueue)
          ..where((t) =>
              t.status.equals('pending') &
              t.context.like('%"kind":"$contextKind"%')))
        .write(const SystemMessageQueueCompanion(status: Value('failed')));
    await (_db.delete(_db.kvStore)..where((t) => t.bucket.equals(_kvBucket)))
        .go();
    return count;
  }

  Future<void> _scheduleAlarm(String reminderId, DateTime dueAt) {
    return CheckinService.instance.scheduleReminderAlarm(
      reminderId: reminderId,
      dueAt: dueAt,
    );
  }

  Future<void> _supersedeOlderCheckpoint(String cardId) async {
    await (_db.update(_db.systemMessageQueue)
          ..where((t) =>
              t.status.equals('pending') &
              t.context.like('%"kind":"$contextKind"%') &
              t.context.like('%"card_id":"$cardId"%')))
        .write(const SystemMessageQueueCompanion(status: Value('failed')));
  }

  static String _dedupeKey(ProactiveOutingCandidate candidate) =>
      '${candidate.cardId}_${candidate.eventAt.millisecondsSinceEpoch}';

  static Map<String, dynamic> _decodeFields(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? decoded.map((key, value) => MapEntry(key.toString(), value))
          : const {};
    } catch (_) {
      return const {};
    }
  }

  static DateTime? _extractEventTime(Map<String, dynamic> fields) {
    for (final key in const [
      'startAt',
      'nextActionAt',
      'dueAt',
      'remindAt',
    ]) {
      final value = fields[key];
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static String? _extractPlaceHint(Map<String, dynamic> fields) {
    for (final key in const [
      'city',
      'location',
      'destination',
      'place',
      'address',
    ]) {
      final value = fields[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  static int? _extractWalkingMinutes(Map<String, dynamic> fields) {
    final value = fields['walkingMinutes'] ?? fields['walking_minutes'];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static final RegExp _outingLanguage = RegExp(
    r'(出门|出发|通勤|上班|下班|约会|去.{0,12}(医院|诊所|牙医|机场|车站|高铁|火车|商场|餐厅|影院|公司|学校|朋友家|公园)|赶(车|飞机|高铁)|接人|送人|散步|徒步|跑步|骑车|搬家|看电影|吃饭|逛街|commute|appointment|go to|leave for|walk|hike|flight|train)',
    caseSensitive: false,
  );
}

class ProactiveOutingCandidate {
  const ProactiveOutingCandidate({
    required this.cardId,
    required this.title,
    required this.eventAt,
    this.placeHint,
    this.walkingMinutes,
  });

  final String cardId;
  final String title;
  final DateTime eventAt;
  final String? placeHint;
  final int? walkingMinutes;
}
