import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/whiteboard_data_bootstrap.dart';
import 'package:memex/db/app_database.dart';

void main() {
  late Directory whiteboardRoot;

  setUp(() {
    whiteboardRoot = Directory.systemTemp.createTempSync(
      'app_database_lifecycle_',
    );
    AppDatabase.setDatabaseFactoryForTesting(
      (_) => AppDatabase.forTesting(NativeDatabase.memory()),
    );
    WhiteboardDataBootstrap.setRepositoryForTesting(null);
    WhiteboardDataBootstrap.setProductionRootForTesting(whiteboardRoot);
  });

  tearDown(() async {
    WhiteboardDataBootstrap.setRepositoryForTesting(null);
    WhiteboardDataBootstrap.setProductionRootForTesting(null);
    if (AppDatabase.isInitialized) await AppDatabase.instance.close();
    AppDatabase.setDatabaseFactoryForTesting(null);
    if (whiteboardRoot.existsSync()) {
      whiteboardRoot.deleteSync(recursive: true);
    }
  });

  test('sequential same-user init preserves shared repository connection',
      () async {
    await AppDatabase.init('desktop_local');
    final database = AppDatabase.instance;
    final repository = await WhiteboardDataBootstrap.productionRepository();
    await repository.createTextCard(
      cardId: 'card_before_second_init',
      title: '连接仍然有效',
    );

    // Mirrors desktop main() followed later by MemexRouter._init().
    await AppDatabase.init('desktop_local');

    expect(AppDatabase.instance, same(database));
    expect(AppDatabase.activeUserId, 'desktop_local');
    expect(
      await WhiteboardDataBootstrap.productionRepository(),
      same(repository),
    );
    expect(await repository.listCards(), hasLength(1));
  });

  test('concurrent same-user init opens exactly one connection', () async {
    var opens = 0;
    AppDatabase.setDatabaseFactoryForTesting((_) {
      opens += 1;
      return AppDatabase.forTesting(NativeDatabase.memory());
    });

    await Future.wait([
      AppDatabase.init('desktop_local'),
      AppDatabase.init('desktop_local'),
      AppDatabase.init('desktop_local'),
    ]);

    expect(opens, 1);
    expect(AppDatabase.activeUserId, 'desktop_local');
  });

  test('real user switch replaces database and refreshes production repository',
      () async {
    await AppDatabase.init('alice');
    final aliceDatabase = AppDatabase.instance;
    final aliceRepository =
        await WhiteboardDataBootstrap.productionRepository();
    await aliceRepository.createTextCard(
      cardId: 'alice_card',
      title: 'Alice',
    );

    await AppDatabase.init('bob');
    final bobRepository = await WhiteboardDataBootstrap.productionRepository();

    expect(AppDatabase.activeUserId, 'bob');
    expect(AppDatabase.instance, isNot(same(aliceDatabase)));
    expect(bobRepository, isNot(same(aliceRepository)));
    expect(bobRepository.db, same(AppDatabase.instance));
    expect(await bobRepository.listCards(), isEmpty);
    await expectLater(aliceRepository.listCards(), throwsStateError);
  });

  test('closing singleton clears initialized state and permits clean reopen',
      () async {
    await AppDatabase.init('desktop_local');
    final first = AppDatabase.instance;

    await first.close();
    expect(AppDatabase.isInitialized, isFalse);
    expect(AppDatabase.activeUserId, isNull);

    await AppDatabase.init('desktop_local');
    expect(AppDatabase.instance, isNot(same(first)));
    expect(AppDatabase.activeUserId, 'desktop_local');
  });

  test('concurrent close callers await the same completed shutdown', () async {
    await AppDatabase.init('desktop_local');
    final database = AppDatabase.instance;

    final closes = [database.close(), database.close(), database.close()];
    await Future.wait(closes);

    expect(AppDatabase.isInitialized, isFalse);
    expect(AppDatabase.activeUserId, isNull);
    await expectLater(
      database.customSelect('SELECT 1').get(),
      throwsStateError,
    );
  });
}
