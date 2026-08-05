import 'dart:io' show stderr;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/agents/life_insight_agent/rhythm_signal_extractor.dart';
import 'package:memex/data/memory_v3/services/user_rhythm_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Tests for the deterministic (regex, no-LLM) rhythm extraction layer.
/// Fixtures use the user's real routine statements.
void main() {
  final fts5Available = _checkFts5();

  PersonaChatMessage userMsg(String content) => PersonaChatMessage(
        id: 1,
        characterId: 'c1',
        isFromCharacter: false,
        content: content,
        factId: null,
        isRead: true,
        timestamp: DateTime(2026, 8, 4, 20, 0),
        messageType: 'chat',
      );

  PersonaChatMessage userMsgAt(String content, DateTime ts) =>
      PersonaChatMessage(
        id: 1,
        characterId: 'c1',
        isFromCharacter: false,
        content: content,
        factId: null,
        isRead: true,
        timestamp: ts,
        messageType: 'chat',
      );

  PersonaChatMessage charMsg(String content) => PersonaChatMessage(
        id: 2,
        characterId: 'c1',
        isFromCharacter: true,
        content: content,
        factId: null,
        isRead: true,
        timestamp: DateTime(2026, 8, 4, 20, 1),
        messageType: 'chat',
      );

  test('extracts daily off-work time ("我每天7点下班")', () {
    final signals = RhythmSignalExtractor.extractDeterministicSignals(
        [userMsg('我每天7点下班，别问了')]);
    final work = signals.where((s) => s.kind == 'work_schedule');
    expect(work, hasLength(1));
    expect(work.first.rrule, contains('19:00'),
        reason: '7点下班 → 19:00');
    expect(work.first.rrule, contains('BYDAY=MO,TU,WE,TH,FR'));
  });

  test('extracts weekly class schedule ("周二周五周日晚上10:00到11:30上网课")',
      () {
    final signals = RhythmSignalExtractor.extractDeterministicSignals([
      userMsg('我周二周五周日晚上10:00到11:30兼职网课，在家上课'),
    ]);
    final cls = signals.where((s) => s.kind == 'class_schedule');
    expect(cls, hasLength(1));
    expect(cls.first.rrule, contains('BYDAY=TU,FR,SU'));
    expect(cls.first.rrule, contains('22:00-23:30'));
    expect(cls.first.location, 'home');
  });

  test('supports 点/半 phrasing ("周二、周五和周日晚上10点到11点半上课")', () {
    final signals = RhythmSignalExtractor.extractDeterministicSignals([
      userMsg('我周二、周五和周日晚上10点到11点半上课，中文老师'),
    ]);
    final cls = signals.where((s) => s.kind == 'class_schedule');
    expect(cls, hasLength(1));
    expect(cls.first.rrule, contains('BYDAY=TU,FR,SU'));
    expect(cls.first.rrule, contains('22:00-23:30'));
  });

  test('extracts sleep pattern ("我一般1点才睡")', () {
    final signals = RhythmSignalExtractor.extractDeterministicSignals(
        [userMsg('我一般1点才睡')]);
    final sleep = signals.where((s) => s.kind == 'sleep_pattern');
    expect(sleep, hasLength(1));
    expect(sleep.first.rrule, contains('01:00'));
  });

  // ── Real-corpus phrasings (from the live phone DB) ──────────────

  test('Chinese numeral + 才 phrasing ("我晚上七点才下班宝宝")', () {
    final signals = RhythmSignalExtractor.extractDeterministicSignals(
        [userMsg('我晚上七点才下班宝宝')]);
    final work = signals.where((s) => s.kind == 'work_schedule');
    expect(work, hasLength(1));
    expect(work.first.rrule, contains('19:00'), reason: '七点 → 19:00');
  });

  test('complaint phrasing ("七点才下班，要说多少次你才能记住")', () {
    final signals = RhythmSignalExtractor.extractDeterministicSignals(
        [userMsg('七点才下班，要说多少次你才能记住')]);
    final work = signals.where((s) => s.kind == 'work_schedule');
    expect(work, hasLength(1));
    expect(work.first.rrule, contains('19:00'));
  });

  test('days-before-range phrasing '
      '("周日周五周二晚上是 10:00 到 11:30…兼职网课")', () {
    final signals = RhythmSignalExtractor.extractDeterministicSignals([
      userMsg('周日周五周二晚上是 10:00 到 11:30，其他几天是八点半到十点半，'
          '我在家上兼职网课'),
    ]);
    final cls = signals.where((s) => s.kind == 'class_schedule');
    expect(cls, hasLength(1));
    expect(cls.first.rrule, contains('BYDAY=TU,FR,SU'));
    expect(cls.first.rrule, contains('22:00-23:30'));
    expect(cls.first.location, 'home');
  });

  test('bare schedule-table phrasing with no 课/兼职 word '
      '("周日周五周二晚上是 10:00 到 11:30，其他几天是八点半到十点半")', () {
    // Real corpus (2026-08-02): the standalone 作息表 sentence that follows
    // "我的兼职课是从8点半到10点半" has no 课/兼职 token itself.
    final signals = RhythmSignalExtractor.extractDeterministicSignals([
      userMsg('周日周五周二晚上是 10:00 到 11:30，其他几天是八点半到十点半'),
    ]);
    final cls = signals.where((s) => s.kind == 'class_schedule');
    expect(cls, hasLength(1));
    expect(cls.first.rrule, contains('BYDAY=TU,FR,SU'));
    expect(cls.first.rrule, contains('22:00-23:30'));
  });

  test('one-off sleep mention without habit markers is NOT extracted', () {
    final signals = RhythmSignalExtractor.extractDeterministicSignals(
        [userMsg('今天太晚了3点才睡')]);
    expect(signals.where((s) => s.kind == 'sleep_pattern'), isEmpty,
        reason: 'no 一般/通常/都/最近 marker → not a routine');
  });

  test('ignores character messages (only user statements count)', () {
    final signals = RhythmSignalExtractor.extractDeterministicSignals(
        [charMsg('你每天7点下班对吧？')]);
    expect(signals, isEmpty);
  });

  test('empty / unrelated chat yields nothing', () {
    final signals = RhythmSignalExtractor.extractDeterministicSignals([
      userMsg('今天吃了猪杂粉'),
      userMsg('明天有个面试'),
    ]);
    expect(signals, isEmpty);
  });

  // ── Routine-change tracking ──────────────────────────────────

  test('newest mention wins within the window (messages newest-first)', () {
    // Window ordered newest-first: 8点下班 is the newer statement and
    // must override the older 7点下班.
    final signals = RhythmSignalExtractor.extractDeterministicSignals([
      userMsgAt('我现在每天8点下班', DateTime(2026, 8, 4, 20, 30)),
      userMsgAt('我每天7点下班', DateTime(2026, 8, 1, 20, 0)),
    ]);
    final work = signals.where((s) => s.kind == 'work_schedule');
    expect(work, hasLength(1));
    expect(work.first.rrule, contains('20:00'),
        reason: 'newest statement (8点) must win over the older 7点');
  });

  test('statements older than the rhythm updatedAt are ignored (freshness)',
      () {
    final rhythm = UserRhythm(
      id: 'r1',
      kind: 'work_schedule',
      description: '工作日上班，20:00 下班',
      rrule: 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;10:00-20:00',
      location: 'office',
      validFrom: DateTime(2026, 8, 4, 21, 0).millisecondsSinceEpoch,
      authority: 'agent_inferred',
      origin: 'conversation',
      confidence: 0.85,
      createdAt: DateTime(2026, 8, 4, 21, 0).millisecondsSinceEpoch,
      updatedAt: DateTime(2026, 8, 4, 21, 0).millisecondsSinceEpoch,
    );
    // Both statements predate the rhythm's last update — fifty old
    // "七点才下班" complaints must not resurrect the stale 7pm value.
    final signals = RhythmSignalExtractor.extractDeterministicSignals([
      userMsgAt('我晚上七点才下班宝宝', DateTime(2026, 8, 1, 19, 30)),
      userMsgAt('我每天7点下班', DateTime(2026, 7, 20, 19, 0)),
    ], [rhythm]);
    expect(signals, isEmpty);
  });

  test('a NEWER statement still updates after the freshness gate', () {
    final rhythm = UserRhythm(
      id: 'r1',
      kind: 'work_schedule',
      description: '工作日上班，19:00 下班',
      rrule: 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;10:00-19:00',
      location: 'office',
      validFrom: DateTime(2026, 8, 1).millisecondsSinceEpoch,
      authority: 'agent_inferred',
      origin: 'conversation',
      confidence: 0.85,
      createdAt: DateTime(2026, 8, 1).millisecondsSinceEpoch,
      updatedAt: DateTime(2026, 8, 1).millisecondsSinceEpoch,
    );
    final signals = RhythmSignalExtractor.extractDeterministicSignals([
      userMsgAt('从下周开始我8点下班', DateTime(2026, 8, 4, 20, 30)),
      userMsgAt('我晚上七点才下班宝宝', DateTime(2026, 8, 1, 19, 30)),
    ], [rhythm]);
    final work = signals.where((s) => s.kind == 'work_schedule');
    expect(work, hasLength(1));
    expect(work.first.rrule, contains('20:00'));
  });

  // ── Lifecycle: termination & one-off cancellation ───────────────

  group('resolveDayToken', () {
    final wed = DateTime(2026, 8, 5, 15, 0); // 2026-08-05 is a Wednesday

    test('今天/明天/后天', () {
      expect(RhythmSignalExtractor.resolveDayTokenForTest('今天', wed),
          '2026-08-05');
      expect(RhythmSignalExtractor.resolveDayTokenForTest('明天', wed),
          '2026-08-06');
      expect(RhythmSignalExtractor.resolveDayTokenForTest('后天', wed),
          '2026-08-07');
    });

    test('周几 = next occurrence (same day counts)', () {
      expect(RhythmSignalExtractor.resolveDayTokenForTest('周三', wed),
          '2026-08-05',
          reason: 'sent on a Wednesday → means today');
      expect(RhythmSignalExtractor.resolveDayTokenForTest('周五', wed),
          '2026-08-07');
      expect(RhythmSignalExtractor.resolveDayTokenForTest('周一', wed),
          '2026-08-10');
    });

    test('下周几 always jumps to next week', () {
      expect(RhythmSignalExtractor.resolveDayTokenForTest('下周三', wed),
          '2026-08-12');
    });
  });

  group('lifecycle actions (needs db)', () {
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

    Future<(String, String)> seedWorkAndClass() async {
      final service = UserRhythmService(db: db);
      final workId = await service.createRhythm(
        kind: 'work_schedule',
        description: '工作日上班，19:00 下班',
        rrule: 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;10:00-19:00',
        location: 'office',
        confidence: 0.9,
      );
      final classId = await service.createRhythm(
        kind: 'class_schedule',
        description: '固定课程（兼职/网课）',
        rrule: 'FREQ=WEEKLY;BYDAY=TU,FR,SU;22:00-23:30',
        location: 'home',
        confidence: 0.9,
      );
      return (workId, classId);
    }

    test('"今天这节课不上了" adds a one-off exception, rhythm survives',
        () async {
      final (workId, classId) = await seedWorkAndClass();
      final rhythms = await UserRhythmService(db: db).getActiveRhythms();
      await RhythmSignalExtractor.applyLifecycleActionsForTest(
        [userMsgAt('今天这节课不上了', DateTime(2026, 8, 4, 15, 0))],
        rhythms,
      );

      final service = UserRhythmService(db: db);
      final after = await service.getActiveRhythms();
      expect(after, hasLength(2), reason: 'exception never expires the row');
      final cls = after.firstWhere((r) => r.id == classId);
      expect(UserRhythmService.parseExceptions(cls.exceptionsJson),
          contains('2026-08-04'));
      final work = after.firstWhere((r) => r.id == workId);
      expect(work.exceptionsJson, isNull,
          reason: 'work rhythm untouched by a class cancellation');
    });

    test('"实习结束了" expires the work rhythm', () async {
      final (workId, _) = await seedWorkAndClass();
      final rhythms = await UserRhythmService(db: db).getActiveRhythms();
      await RhythmSignalExtractor.applyLifecycleActionsForTest(
        [userMsgAt('实习结束了宝宝', DateTime(2026, 9, 30, 20, 0))],
        rhythms,
      );

      final service = UserRhythmService(db: db);
      final active = await service.getActiveRhythms();
      expect(active.where((r) => r.id == workId), isEmpty,
          reason: 'terminated rhythm must stop being injected');
      expect(active.where((r) => r.kind == 'class_schedule'), hasLength(1),
          reason: 'termination of 实习 must not kill the class rhythm');
    });

    test('"这个班级结束了" expires the class rhythm only', () async {
      final (_, classId) = await seedWorkAndClass();
      final rhythms = await UserRhythmService(db: db).getActiveRhythms();
      await RhythmSignalExtractor.applyLifecycleActionsForTest(
        [userMsgAt('这个班级结束了', DateTime(2026, 10, 1, 21, 0))],
        rhythms,
      );
      final active = await UserRhythmService(db: db).getActiveRhythms();
      expect(active.where((r) => r.id == classId), isEmpty);
      expect(active.where((r) => r.kind == 'work_schedule'), hasLength(1));
    });

    test('daily "下班" phrasing never triggers termination', () async {
      await seedWorkAndClass();
      final rhythms = await UserRhythmService(db: db).getActiveRhythms();
      await RhythmSignalExtractor.applyLifecycleActionsForTest([
        userMsgAt('我晚上七点才下班宝宝', DateTime(2026, 8, 4, 19, 30)),
        userMsgAt('刚下班，累死了', DateTime(2026, 8, 4, 19, 40)),
      ], rhythms);
      final active = await UserRhythmService(db: db).getActiveRhythms();
      expect(active.where((r) => r.kind == 'work_schedule'), hasLength(1));
    });

    test('idempotent: same cancellation applied twice stays one entry',
        () async {
      final (_, classId) = await seedWorkAndClass();
      final rhythms = await UserRhythmService(db: db).getActiveRhythms();
      final msgs = [userMsgAt('今天这节课不上了', DateTime(2026, 8, 4, 15, 0))];
      await RhythmSignalExtractor.applyLifecycleActionsForTest(msgs, rhythms);
      await RhythmSignalExtractor.applyLifecycleActionsForTest(
          msgs, await UserRhythmService(db: db).getActiveRhythms());
      final cls = (await UserRhythmService(db: db).getActiveRhythms())
          .firstWhere((r) => r.id == classId);
      expect(UserRhythmService.parseExceptions(cls.exceptionsJson),
          hasLength(1));
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
    stderr.writeln('FTS5 unavailable; rhythm lifecycle db tests skipped.');
    return false;
  }
}
