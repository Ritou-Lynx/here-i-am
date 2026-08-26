import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/services/dreaming_orchestrator_service.dart';
import 'package:memex/db/app_database.dart';

void main() {
  test('strict recent context reports deterministic recall outage', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final service = DreamingOrchestratorServiceV3(db);
    await db.customStatement('DROP TABLE memory_episodes_fts');
    await db.customStatement('DROP TABLE memory_episodes');

    await expectLater(
      service.queryRecentDreamingContext(
        queryHint: 'relationship query',
        strictDiagnostics: true,
      ),
      throwsA(
        isA<DreamingContextQueryException>()
            .having((error) => error.layer, 'layer', 'episodes'),
      ),
    );
    await db.close();
  });

  test('saga diagnostics are opt-in and preserve default empty fallback',
      () async {
    final defaultDb = AppDatabase.forTesting(NativeDatabase.memory());
    final defaultService = DreamingOrchestratorServiceV3(defaultDb);
    await defaultDb.customStatement('DROP TABLE memory_sagas_fts');
    expect(
      await defaultService.querySagasForContext(queryHint: 'long arc'),
      isEmpty,
    );
    await expectLater(
      defaultService.querySagasForContext(
        queryHint: 'long arc',
        strictDiagnostics: true,
      ),
      throwsA(
        isA<DreamingContextQueryException>()
            .having((error) => error.layer, 'layer', 'sagas'),
      ),
    );
    await defaultDb.close();
  });

  test('fragment deterministic outage is empty by default and strict on opt-in',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final service = DreamingOrchestratorServiceV3(db);
    await db.customStatement('DROP TABLE memory_fragments_fts');
    await db.customStatement('DROP TABLE memory_fragments');

    final fallback = await service.queryRecentDreamingContext(
      queryHint: 'relationship detail',
    );
    expect(fallback.episodeHits, isEmpty);
    expect(fallback.fragmentHits, isEmpty);

    await expectLater(
      service.queryRecentDreamingContext(
        queryHint: 'relationship detail',
        strictDiagnostics: true,
      ),
      throwsA(
        isA<DreamingContextQueryException>()
            .having((error) => error.layer, 'layer', 'fragments'),
      ),
    );
    await db.close();
  });
}
