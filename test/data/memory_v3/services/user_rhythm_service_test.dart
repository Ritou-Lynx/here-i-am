import 'dart:io' show stderr;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/services/user_rhythm_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Regression tests for the "told you 100 times I get off work at 7pm"
/// bug chain: rhythm extraction → user_rhythms → snapshot injection.
///
/// The fixture mirrors the user's real routines:
/// - work_schedule: 10:00-19:00 daily ("我每天7点下班")
/// - class_schedule: TU/FR/SU 22:00-23:30 at home ("周二五日晚上兼职网课")
/// - sleep_pattern: 23:30-07:00 crossing midnight
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fts5Available = _checkFts5();

  group('parseRrule', () {
    test('weekly BYDAY pattern parses weekdays and time range', () {
      final slots = UserRhythmService.parseRrule(
          'FREQ=WEEKLY;BYDAY=TU,FR,SU;22:00-23:30');
      expect(slots, hasLength(1));
      expect(slots.first.weekdays, [2, 5, 7]); // ISO: Tue, Fri, Sun
      expect(slots.first.startTime, '22:00');
      expect(slots.first.endTime, '23:30');
    });

    test('daily pattern expands to all seven weekdays', () {
      final slots =
          UserRhythmService.parseRrule('FREQ=DAILY;10:00-19:00');
      expect(slots, hasLength(1));
      expect(slots.first.weekdays, [1, 2, 3, 4, 5, 6, 7]);
      expect(slots.first.startTime, '10:00');
      expect(slots.first.endTime, '19:00');
    });

    test('garbage rrule without time range yields no slots', () {
      expect(UserRhythmService.parseRrule('FREQ=DAILY'), isEmpty);
      expect(UserRhythmService.parseRrule(''), isEmpty);
    });
  });

  group('isWithinSlot', () {
    RhythmTimeSlot slot(String start, String end) =>
        RhythmTimeSlot(weekdays: const [1, 2, 3, 4, 5, 6, 7], startTime: start, endTime: end);

    test('normal slot: inside and outside boundaries', () {
      final work = slot('10:00', '19:00');
      expect(UserRhythmService.isWithinSlot('17:00', work), isTrue,
          reason: '17:00 is within 10:00-19:00 work hours');
      expect(UserRhythmService.isWithinSlot('09:59', work), isFalse);
      expect(UserRhythmService.isWithinSlot('19:01', work), isFalse);
    });

    test('cross-midnight sleep slot covers BOTH evening and morning sides',
        () {
      final sleep = slot('23:30', '07:00');
      expect(UserRhythmService.isWithinSlot('23:50', sleep), isTrue);
      expect(UserRhythmService.isWithinSlot('06:30', sleep), isTrue,
          reason: 'morning side of a cross-midnight slot must count as '
              'within — otherwise the companion pings the user at 6am '
              'while they are still asleep');
      expect(UserRhythmService.isWithinSlot('12:00', sleep), isFalse);
      expect(UserRhythmService.isWithinSlot('23:00', sleep), isFalse);
    });
  });

  group('isApproachingSlotStart / isAfterSlotEnd', () {
    test('approaching within N minutes before slot start', () {
      final cls = RhythmTimeSlot(
          weekdays: const [2, 5, 7], startTime: '22:00', endTime: '23:30');
      expect(UserRhythmService.isApproachingSlotStart('21:40', cls, 30),
          isTrue);
      expect(UserRhythmService.isApproachingSlotStart('21:20', cls, 30),
          isFalse);
      expect(UserRhythmService.isApproachingSlotStart('22:10', cls, 30),
          isFalse,
          reason: 'already started — not approaching');
    });

    test('after slot end within N minutes', () {
      final cls = RhythmTimeSlot(
          weekdays: const [2, 5, 7], startTime: '22:00', endTime: '23:30');
      expect(UserRhythmService.isAfterSlotEnd('23:45', cls, 60), isTrue);
      expect(UserRhythmService.isAfterSlotEnd('23:30', cls, 60), isTrue);
      expect(UserRhythmService.isAfterSlotEnd('00:45', cls, 60), isFalse,
          reason: 'cross-midnight diff is out of scope for afterEnd');
    });
  });

  group('snapshot injection (user_rhythms → Daily Rhythm section)', () {
    late AppDatabase db;

    setUp(() {
      if (!fts5Available) return;
      db = AppDatabase.forTesting(NativeDatabase.memory());
      UserRhythmService.init(db);
    });

    tearDown(() async {
      if (!fts5Available) return;
      await db.close();
    });

    Future<UserRhythmService> seedUserRoutines() async {
      final service = UserRhythmService(db: db);
      await service.createRhythm(
        kind: 'work_schedule',
        description: '实习上班',
        rrule: 'FREQ=DAILY;10:00-19:00',
        location: 'office',
        confidence: 0.9,
      );
      await service.createRhythm(
        kind: 'class_schedule',
        description: '兼职中文网课',
        rrule: 'FREQ=WEEKLY;BYDAY=TU,FR,SU;22:00-23:30',
        location: 'home',
        confidence: 0.9,
      );
      await service.createRhythm(
        kind: 'sleep_pattern',
        description: '作息',
        rrule: 'FREQ=DAILY;23:30-07:00',
        confidence: 0.7,
      );
      return service;
    }

    test('Tuesday 22:10 — class ongoing, work long ended', () async {
      final service = await seedUserRoutines();
      // 2026-08-04 is a Tuesday (weekday 2).
      final tuesdayNight = DateTime(2026, 8, 4, 22, 10);
      final section = await service.buildSnapshotSection(now: tuesdayNight);

      expect(section, contains("## User's Daily Rhythm (active today)"));
      expect(section, contains('兼职中文网课'));
      expect(section, contains('22:00-23:30'));
      expect(section, contains('ongoing'));
      expect(section, contains('at home'));
      // The sleep pattern is also within-slot at 22:10? No — 22:10 < 23:30.
      expect(section, isNot(contains('likely sleeping')));
    });

    test('Tuesday 21:40 — class starting soon (reminder window)', () async {
      final service = await seedUserRoutines();
      final tuesdayEvening = DateTime(2026, 8, 4, 21, 40);
      final section = await service.buildSnapshotSection(now: tuesdayEvening);

      expect(section, contains('兼职中文网课'));
      expect(section, contains('starting soon'));
    });

    test('Wednesday 17:00 — no class today, work ongoing until 19:00',
        () async {
      final service = await seedUserRoutines();
      final wednesdayAfternoon = DateTime(2026, 8, 5, 17, 0);
      final section =
          await service.buildSnapshotSection(now: wednesdayAfternoon);

      expect(section, contains('实习上班'));
      expect(section, contains('ongoing'));
      expect(section, isNot(contains('兼职中文网课')),
          reason: 'class is TU/FR/SU only — Wednesday must not show it');
    });

    test('Tuesday 06:30 — sleeping user flagged, no morning spam',
        () async {
      final service = await seedUserRoutines();
      final tuesdayMorning = DateTime(2026, 8, 4, 6, 30);
      final section = await service.buildSnapshotSection(now: tuesdayMorning);

      expect(section, contains('likely sleeping'),
          reason: 'cross-midnight sleep rhythm must flag the morning side');
    });

    test('empty table yields empty section (no injection)', () async {
      final service = UserRhythmService(db: db);
      final section = await service.buildSnapshotSection(
          now: DateTime(2026, 8, 4, 17, 0));
      expect(section, isEmpty);
    });

    test('one-off exception hides the rhythm for that date only', () async {
      final service = await seedUserRoutines();
      // Cancel Tuesday's class once: "今天这节课不上了".
      final classRhythm = (await service.getActiveRhythmsByKind(
              'class_schedule'))
          .first;
      await service.addException(classRhythm.id, '2026-08-04');
      // Idempotent: adding the same date again stays a single entry.
      await service.addException(classRhythm.id, '2026-08-04');
      expect(
          UserRhythmService.parseExceptions(
              (await service.getActiveRhythmsByKind('class_schedule'))
                  .first
                  .exceptionsJson),
          hasLength(1));

      final tuesdayNight = DateTime(2026, 8, 4, 22, 10);
      final section = await service.buildSnapshotSection(now: tuesdayNight);
      expect(section, isNot(contains('兼职中文网课')),
          reason: 'cancelled date must not be injected');
      expect(section, isNot(contains('ongoing')));

      // Friday the class is back — exception is per-date, not per-rhythm.
      final fridayNight = DateTime(2026, 8, 7, 22, 10);
      final fridaySection =
          await service.buildSnapshotSection(now: fridayNight);
      expect(fridaySection, contains('兼职中文网课'));
      expect(fridaySection, contains('ongoing'));
    });

    test('expired rhythm is never injected (termination)', () async {
      final service = await seedUserRoutines();
      final work =
          (await service.getActiveRhythmsByKind('work_schedule')).first;
      await service.expireRhythm(work.id);

      final section = await service.buildSnapshotSection(
          now: DateTime(2026, 8, 5, 17, 0));
      expect(section, isNot(contains('实习上班')),
          reason: '"实习结束了" must stop injection entirely');
    });
  }, skip: !fts5Available ? 'FTS5 unavailable on this platform' : null);
}

bool _checkFts5() {
  try {
    final db = sqlite3.sqlite3.openInMemory();
    db.execute('CREATE VIRTUAL TABLE t USING fts5(content)');
    db.dispose();
    return true;
  } catch (_) {
    stderr.writeln('FTS5 unavailable; user rhythm db tests skipped.');
    return false;
  }
}
