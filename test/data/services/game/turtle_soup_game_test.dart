import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/game_agent/turtle_soup_prompt.dart';
import 'package:memex/data/services/game/game_session_service.dart';
import 'package:memex/data/services/game/turtle_soup_catalog.dart';
import 'package:memex/db/app_database.dart';

void main() {
  late AppDatabase db;
  late GameSessionService service;

  const puzzle = TurtleSoupPuzzle(
    id: 'test_soup',
    title: '固定的谜面',
    surface: '一个人关灯后，远处发生了事故。为什么？',
    solution: '他关掉的是灯塔的导航灯。',
    difficulty: '测试',
  );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = GameSessionService(db);
  });

  tearDown(() => db.close());

  test('turtle soup session snapshots one immutable puzzle and opening turn',
      () async {
    final session = await service.createTurtleSoupSession(puzzle: puzzle);
    final snapshot = jsonDecode(session.definitionSnapshotJson);
    final messages = await service.getMessages(session.id);

    expect(session.gameType, 'turtle_soup');
    expect(session.definitionId, isNull);
    expect(session.status, 'active');
    expect(snapshot['surface'], puzzle.surface);
    expect(snapshot['solution'], puzzle.solution);
    expect(messages, hasLength(1));
    expect(messages.single.role, 'assistant');
    expect(messages.single.content, contains('汤面已经钉在上面'));
  });

  test('every question is persisted so an unfinished round can resume',
      () async {
    final session = await service.createTurtleSoupSession(puzzle: puzzle);
    await service.appendMessage(
      sessionId: session.id,
      role: 'user',
      content: '那盏灯很重要吗？',
    );
    await service.appendMessage(
      sessionId: session.id,
      role: 'assistant',
      content: '是',
    );

    final resumed = await service.getSession(session.id);
    final history = await service.getMessages(session.id);

    expect(resumed?.status, 'active');
    expect(history.map((m) => m.content),
        containsAllInOrder(['那盏灯很重要吗？', '是']));
  });

  test('visible referee reply is always one of the three allowed verdicts',
      () {
    expect(TurtleSoupPrompt.normalizeVerdict('是。因为灯很重要'), '是');
    expect(TurtleSoupPrompt.normalizeVerdict('答案：不是'), '不是');
    expect(TurtleSoupPrompt.normalizeVerdict('是也不是，需要看情况'), '是也不是');
    expect(TurtleSoupPrompt.normalizeVerdict('无法判断'), '是也不是');
  });

  test('prompt freezes both surface and canonical solution', () {
    final prompt = TurtleSoupPrompt.build(puzzle);

    expect(prompt, contains(puzzle.surface));
    expect(prompt, contains(puzzle.solution));
    expect(prompt, contains('永久固定'));
    expect(prompt, contains('只能是下面三个字符串之一'));
  });
}
