import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/agents/life_insight_agent/rhythm_signal_extractor.dart';
import 'package:memex/db/app_database.dart';

/// Tests for the deterministic (regex, no-LLM) rhythm extraction layer.
/// Fixtures use the user's real routine statements.
void main() {
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
}
