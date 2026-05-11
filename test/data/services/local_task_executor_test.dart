import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/db/app_database.dart';

void main() {
  late AppDatabase db;
  late LocalTaskExecutor executor;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    executor = LocalTaskExecutor.forTesting(db: db);
  });

  tearDown(() async {
    executor.stop();
    await db.close();
  });

  test('scans past dependency-blocked queue head to run later tasks', () async {
    final completed = Completer<void>();
    executor.registerHandler('runnable_task', (_, __, ___) async {
      if (!completed.isCompleted) completed.complete();
    });

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: 'unresolved-dependency',
          type: 'dependency_task',
          payload: const Value('{}'),
          status: 'retrying',
          createdAt: Value(now),
          scheduledAt: Value(now + 3600),
        ));

    for (var i = 0; i < 50; i++) {
      await db.into(db.tasks).insert(TasksCompanion.insert(
            id: 'blocked-$i',
            type: 'blocked_task',
            payload: const Value('{}'),
            status: 'pending',
            createdAt: Value(now + i + 1),
            dependencies: Value(jsonEncode(['unresolved-dependency'])),
          ));
    }

    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: 'runnable',
          type: 'runnable_task',
          payload: const Value('{}'),
          status: 'pending',
          createdAt: Value(now + 100),
        ));

    await executor.start(userId: 'user-a');

    await completed.future.timeout(const Duration(seconds: 3));

    final runnable = await (db.select(db.tasks)
          ..where((t) => t.id.equals('runnable')))
        .getSingle();
    expect(runnable.status, anyOf('processing', 'completed'));

    final blocked = await (db.select(db.tasks)
          ..where((t) => t.id.equals('blocked-0')))
        .getSingle();
    expect(blocked.status, 'pending');
  });

  test('skips malformed dependencies and still runs a later valid task',
      () async {
    final completed = Completer<void>();
    executor.registerHandler('runnable_task', (_, __, ___) async {
      if (!completed.isCompleted) completed.complete();
    });

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: 'bad-dependency',
          type: 'blocked_task',
          payload: const Value('{}'),
          status: 'pending',
          priority: const Value(10),
          createdAt: Value(now),
          dependencies: const Value('not-json'),
        ));

    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: 'runnable',
          type: 'runnable_task',
          payload: const Value('{}'),
          status: 'pending',
          createdAt: Value(now + 1),
        ));

    await executor.start(userId: 'user-a');

    await completed.future.timeout(const Duration(seconds: 3));

    final malformed = await (db.select(db.tasks)
          ..where((t) => t.id.equals('bad-dependency')))
        .getSingle();
    expect(malformed.status, 'pending');
  });

  test('uses only available concurrency slots while backlog remains queued',
      () async {
    final release = Completer<void>();
    var startedCount = 0;
    executor.registerHandler('runnable_task', (_, __, ___) async {
      startedCount++;
      await release.future;
    });

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await executor.start(userId: 'user-a');

    for (var i = 0; i < 4; i++) {
      await db.into(db.tasks).insert(TasksCompanion.insert(
            id: 'active-$i',
            type: 'already_processing',
            payload: const Value('{}'),
            status: 'processing',
            createdAt: Value(now + i),
          ));
    }

    for (var i = 0; i < 3; i++) {
      await db.into(db.tasks).insert(TasksCompanion.insert(
            id: 'runnable-$i',
            type: 'runnable_task',
            payload: const Value('{}'),
            status: 'pending',
            createdAt: Value(now + 10 + i),
          ));
    }

    await _waitUntil(() => startedCount == 1);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(startedCount, 1);

    executor.stop();
    release.complete();
  });

  test('reports active task activity snapshot', () async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: 'pending-task',
          type: 'task',
          payload: const Value('{}'),
          status: 'pending',
          createdAt: Value(now),
        ));
    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: 'processing-task',
          type: 'task',
          payload: const Value('{}'),
          status: 'processing',
          createdAt: Value(now),
        ));
    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: 'retrying-task',
          type: 'task',
          payload: const Value('{}'),
          status: 'retrying',
          createdAt: Value(now),
        ));
    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: 'completed-task',
          type: 'task',
          payload: const Value('{}'),
          status: 'completed',
          createdAt: Value(now),
        ));

    final snapshot = await executor.getTaskActivitySnapshot();

    expect(
      snapshot,
      const TaskActivitySnapshot(
        pending: 1,
        processing: 1,
        retrying: 1,
      ),
    );
    expect(snapshot.total, 3);
    expect(snapshot.hasActiveTasks, isTrue);
  });
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
