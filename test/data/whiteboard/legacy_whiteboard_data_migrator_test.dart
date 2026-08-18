import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/ingestion/ingestion_store.dart';
import 'package:memex/data/whiteboard/legacy_whiteboard_data_migrator.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/domain/whiteboard/source_content.dart';

void main() {
  late Directory tempDir;
  late Directory richRoot;
  late Directory ingestionRoot;
  late AppDatabase db;
  late UnifiedCardRepository repository;
  late LegacyWhiteboardDataMigrator migrator;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('f0_migration_');
    richRoot = Directory('${tempDir.path}/legacy_rich_text');
    ingestionRoot = Directory('${tempDir.path}/legacy_ingestion');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = UnifiedCardRepository(
      db: db,
      whiteboardRoot: Directory('${tempDir.path}/whiteboard'),
    );
    migrator = LegacyWhiteboardDataMigrator(
      repository: repository,
      legacyRichTextRoot: richRoot,
      legacyIngestionRoot: ingestionRoot,
    );
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('rich text, ingestion JSON and Drift notes migrate idempotently',
      () async {
    await _writeRichText(richRoot, 'legacy_rich', '旧富文本关键词');
    await db.customStatement('''
      INSERT INTO memory_cards(
        id,memory_scope,type,title,droplet_label,presentation_module,
        retrieval_text,valence,arousal,schema_version,created_at,updated_at
      ) VALUES (
        'legacy_drift','user_truth','note','旧 Drift','旧卡','[]',
        'Drift 正文',0,0,1,1,1
      )
    ''');
    await _seedIngestion(ingestionRoot);

    final first = await migrator.run();
    expect(first.failures, isEmpty);
    expect(first.driftExtrasBackfilled, 1);
    expect(first.richTextCardsCreated, 1);
    expect(first.ingestionRecordsImported, 1);
    expect(await repository.listCards(), hasLength(3));

    final sourceVersionsBefore =
        await repository.listSourceVersions('src_legacy_web');
    final second = await migrator.run();
    final sourceVersionsAfter =
        await repository.listSourceVersions('src_legacy_web');
    expect(await repository.listCards(), hasLength(3));
    expect(sourceVersionsAfter.length, sourceVersionsBefore.length);
    expect(second.failures, isEmpty);
    expect(await migrator.reportFile.exists(), isTrue);
  });

  test('newer production projection is not overwritten by older rich text',
      () async {
    await _writeRichText(richRoot, 'newer_card', '旧文件正文');
    final legacyFile = File(
      '${richRoot.path}/card_newer_card/rich_text.json',
    );
    await legacyFile.setLastModified(DateTime.utc(2026, 1, 1));
    await repository.createTextCard(
      cardId: 'newer_card',
      title: '新标题',
      body: '更新的用户正文',
      createdAt: DateTime.utc(2027, 1, 1),
    );

    await migrator.run();

    final card = await repository.getCard('newer_card');
    expect(card!.card.body, '更新的用户正文');
  });

  test('one corrupt record does not block good data and marked data migrates',
      () async {
    await _writeRichText(richRoot, 'good_card', '可迁移内容');
    final brokenDir = Directory('${richRoot.path}/card_broken_card');
    await brokenDir.create(recursive: true);
    await File('${brokenDir.path}/rich_text.json').writeAsString('{broken');
    await _writeRichText(richRoot, 'richtext_itest', '测试污染候选');

    final report = await migrator.run();

    expect(await repository.getCard('good_card'), isNotNull);
    expect(await repository.getCard('broken_card'), isNull);
    expect(report.failures.map((failure) => failure.reference),
        contains('broken_card'));
    expect(report.possibleTestArtifacts, contains('rich_text:richtext_itest'));
    final markedCard = await repository.getCard('richtext_itest');
    expect(markedCard, isNotNull);
    expect(markedCard!.card.body, '测试污染候选');
    expect(
      (await repository.listCards()).map((record) => record.card.cardId),
      contains('richtext_itest'),
      reason: 'a cleanup candidate remains part of the unified card library',
    );
    expect(
      File('${richRoot.path}/card_richtext_itest/rich_text.json').existsSync(),
      isTrue,
      reason: 'cleanup is opt-in; migration only reports candidates',
    );
  });

  test('migration report restores a valid backup after an interrupted swap',
      () async {
    await migrator.run();
    final report = migrator.reportFile;
    final original = await report.readAsString();
    await report.rename('${report.path}.bak');
    await File('${report.path}.tmp').writeAsString('{broken');

    expect(await migrator.recoverReportFile(), isTrue);
    expect(await report.readAsString(), original);
    expect(await File('${report.path}.tmp').exists(), isFalse);
    expect(await File('${report.path}.bak').exists(), isFalse);
  });
}

Future<void> _writeRichText(
  Directory root,
  String cardId,
  String text,
) async {
  final dir = Directory('${root.path}/card_$cardId');
  await dir.create(recursive: true);
  const schema = 2;
  await File('${dir.path}/rich_text.json').writeAsString(jsonEncode({
    'schema_version': schema,
    'blocks': [
      {'type': 'paragraph', 'text': text},
    ],
  }));
}

Future<void> _seedIngestion(Directory root) async {
  final store = IngestionStore(root);
  final now = DateTime.utc(2026, 8, 1);
  const sourceId = 'src_legacy_web';
  const versionId = 'ver_legacy_web_v1';
  final source = SourceContent(
    sourceId: sourceId,
    mediaType: SourceMediaType.web,
    title: '旧网页',
    origin: SourceOrigin.externalLink,
    provider: 'web',
    currentVersionId: versionId,
    contentHash: 'legacy_hash',
    objectRef: 'ingestion/$sourceId/$versionId.html',
    metadata: const {'canonical_url': 'https://example.com/legacy'},
    createdAt: now,
    updatedAt: now,
  );
  final version = SourceVersion(
    versionId: versionId,
    sourceId: sourceId,
    contentHash: 'legacy_hash',
    objectRef: source.objectRef!,
    createdAt: now,
  );
  final result = IngestionResult(
    canonicalUrl: 'https://example.com/legacy',
    status: IngestionStatus.ok,
    source: source,
    sourceVersion: version.toJson(),
    metadata: const {'body_excerpt': '旧网页正文'},
    resolvedAt: now,
  );
  await store.upsertSource(result);
  await store.createOrUpdateCard(result: result);
}
