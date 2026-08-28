import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/thumbnail/safe_thumbnail_resolver.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/source_content.dart';

class _RecordingThumbnailResolver implements ThumbnailResolver {
  _RecordingThumbnailResolver(this.result, {this.gate});

  final ResolvedThumbnail result;
  final Completer<void>? gate;
  final List<ThumbnailResolveRequest> requests = [];

  @override
  Future<ResolvedThumbnail> resolve(ThumbnailResolveRequest request) async {
    requests.add(request);
    await gate?.future;
    return result;
  }
}

void main() {
  late Directory tempDir;
  late File dbFile;
  late AppDatabase db;
  late UnifiedCardRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('f0_repository_');
    dbFile = File('${tempDir.path}/repository.sqlite');
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    repository = UnifiedCardRepository(db: db, whiteboardRoot: tempDir);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('clean database text card is immediately visible in unified list',
      () async {
    final created = await repository.createTextCard(
      title: '第一张卡',
      body: '立即可见的正文',
      tags: const ['想法'],
    );

    final listed = await repository.listCards();
    expect(listed, hasLength(1));
    expect(listed.single.card.cardId, created.cardId);
    expect(listed.single.card.body, '立即可见的正文');
  });

  test('distinct tags are live, case-insensitive and survive restart',
      () async {
    final note = await repository.createTextCard(
      cardId: 'tagged_note',
      tags: const ['  Focus ', '研究', 'focus', ''],
    );
    final sourceCommit = await repository.commitIngestion(
      _ingestion(hash: 'tagged_source_hash', body: '带标签的来源'),
    );
    await repository.updateCardMetadata(
      sourceCommit.card.cardId,
      tags: const ['FOCUS', '网页'],
    );
    final deleted = await repository.createTextCard(
      cardId: 'deleted_tagged_note',
      tags: const ['不应出现'],
    );
    await repository.softDeleteCard(deleted.cardId);

    expect(await repository.listDistinctTags(), ['Focus', '研究', '网页']);
    expect(
      await repository.listDistinctTags(includeDeleted: true),
      ['Focus', '不应出现', '研究', '网页'],
    );
    expect(
      await repository.listCards(
        const CardLibraryQuery(tags: {'focus'}),
      ),
      hasLength(2),
    );

    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    repository = UnifiedCardRepository(db: db, whiteboardRoot: tempDir);

    expect(await repository.listDistinctTags(), ['Focus', '研究', '网页']);
    final noteAfterRestart = await repository.getCard(note.cardId);
    expect(noteAfterRestart!.card.tags, ['Focus', '研究']);
    final sourceAfterRestart =
        await repository.getCard(sourceCommit.card.cardId);
    expect(sourceAfterRestart!.card.sourceId, sourceCommit.source.sourceId);
    expect(sourceAfterRestart.card.tags, ['FOCUS', '网页']);
    expect(
      await repository.listCards(
        const CardLibraryQuery(tags: {'FOCUS'}),
      ),
      hasLength(2),
    );
  });

  test('rich text keeps identity, updates searchable projection and restarts',
      () async {
    final card = await repository.createTextCard(title: '旧标题');
    const document = RichTextDocument(blocks: [
      RichTextBlock(type: BlockType.heading, text: '新标题'),
      RichTextBlock(type: BlockType.paragraph, text: '可搜索正文关键词'),
    ]);

    final saved = await repository.saveRichText(card.cardId, document);
    expect(saved.cardId, card.cardId);
    expect(saved.title, '新标题');
    expect(
      await repository.listCards(
        const CardLibraryQuery(search: '正文关键词'),
      ),
      hasLength(1),
    );

    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    final restarted = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
    );
    final recovered = await restarted.getCard(card.cardId);
    expect(recovered, isNotNull);
    expect(recovered!.card.cardId, card.cardId);
    expect(recovered.documentState, CardDocumentState.available);
    expect(recovered.document!.toPlainText(), contains('可搜索正文关键词'));
  });

  test('fetch result creates no truth until explicitly committed', () async {
    final result = _ingestion(hash: 'hash_a', body: '抓取预览');

    expect(await repository.listCards(), isEmpty);
    expect(await repository.getSource(result.source!.sourceId), isNull);

    final committed = await repository.commitIngestion(result);
    expect(committed.cardCreated, isTrue);
    expect(await repository.listCards(), hasLength(1));
    expect(await repository.getSource(result.source!.sourceId), isNotNull);
  });

  test('failed ingestion transaction removes its new object and sidecars',
      () async {
    var failOnce = true;
    final faulting = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      faultInjector: (point) async {
        if (failOnce &&
            point ==
                UnifiedCardRepositoryFaultPoint.ingestionAfterVersionInsert) {
          failOnce = false;
          throw StateError('injected transaction failure after object write');
        }
      },
    );
    final result = _ingestion(hash: 'object_rollback', body: '不留半成品');
    final target = File(
      '${tempDir.path}${Platform.pathSeparator}objects${Platform.pathSeparator}'
      'sources${Platform.pathSeparator}src_web_f0_example${Platform.pathSeparator}'
      'ver_web_f0_example_object_rollback.json',
    );

    await expectLater(faulting.commitIngestion(result), throwsStateError);
    expect(await faulting.listCards(), isEmpty);
    expect(await faulting.getSource(result.source!.sourceId), isNull);
    expect(await db.select(db.whiteboardSourceVersions).get(), isEmpty);
    expect(await target.exists(), isFalse);
    expect(await File('${target.path}.tmp').exists(), isFalse);
    expect(await File('${target.path}.bak').exists(), isFalse);

    final retried = await faulting.commitIngestion(result);
    expect(retried.cardCreated, isTrue);
    expect(await faulting.listCards(), hasLength(1));
    expect(await target.exists(), isTrue);
  });

  test('object exchange failure removes fresh partial files and can retry',
      () async {
    late File target;
    var failOnce = true;
    final faulting = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      faultInjector: (point) async {
        if (failOnce &&
            point ==
                UnifiedCardRepositoryFaultPoint.ingestionDuringObjectExchange) {
          failOnce = false;
          await target.writeAsString('{"partial":"final"}');
          await File('${target.path}.tmp').writeAsString('partial temp');
          await File('${target.path}.bak').writeAsString('partial backup');
          throw StateError('injected object exchange failure');
        }
      },
    );
    final result = _ingestion(hash: 'exchange_rollback', body: '交换失败');
    target = File(
      '${tempDir.path}${Platform.pathSeparator}objects${Platform.pathSeparator}'
      'sources${Platform.pathSeparator}src_web_f0_example${Platform.pathSeparator}'
      'ver_web_f0_example_exchange_rollback.json',
    );

    await expectLater(faulting.commitIngestion(result), throwsStateError);
    expect(await faulting.listCards(), isEmpty);
    expect(await db.select(db.whiteboardSourceVersions).get(), isEmpty);
    expect(await target.exists(), isFalse);
    expect(await File('${target.path}.tmp').exists(), isFalse);
    expect(await File('${target.path}.bak').exists(), isFalse);

    final retried = await faulting.commitIngestion(result);
    expect(retried.cardCreated, isTrue);
    expect(await faulting.listCards(), hasLength(1));
    expect(
      await faulting.listSourceVersions(result.source!.sourceId),
      hasLength(1),
    );
  });

  test('object exchange failure restores exact pre-existing sidecars',
      () async {
    late File target;
    final faulting = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      faultInjector: (point) async {
        if (point ==
            UnifiedCardRepositoryFaultPoint.ingestionDuringObjectExchange) {
          await target.writeAsString('{"partial":"final"}');
          await File('${target.path}.tmp').writeAsString('overwritten temp');
          await File('${target.path}.bak').writeAsString('overwritten backup');
          throw StateError('injected object exchange failure');
        }
      },
    );
    final result = _ingestion(hash: 'exchange_sidecars', body: '恢复现场');
    target = File(
      '${tempDir.path}${Platform.pathSeparator}objects${Platform.pathSeparator}'
      'sources${Platform.pathSeparator}src_web_f0_example${Platform.pathSeparator}'
      'ver_web_f0_example_exchange_sidecars.json',
    );
    final temp = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    await target.parent.create(recursive: true);
    await temp.writeAsBytes(const [1, 2, 3, 4]);
    await backup.writeAsBytes(const [5, 6, 7, 8]);

    await expectLater(faulting.commitIngestion(result), throwsStateError);

    expect(await faulting.listCards(), isEmpty);
    expect(await db.select(db.whiteboardSourceVersions).get(), isEmpty);
    expect(await target.exists(), isFalse);
    expect(await temp.readAsBytes(), const [1, 2, 3, 4]);
    expect(await backup.readAsBytes(), const [5, 6, 7, 8]);
  });

  test('failed ingestion restores pre-existing sidecars but removes new final',
      () async {
    final faulting = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      faultInjector: (point) async {
        if (point ==
            UnifiedCardRepositoryFaultPoint.ingestionAfterVersionInsert) {
          throw StateError('transaction fails after sidecar recovery');
        }
      },
    );
    final result = _ingestion(hash: 'sidecar_rollback', body: '不覆盖恢复现场');
    final target = File(
      '${tempDir.path}${Platform.pathSeparator}objects${Platform.pathSeparator}'
      'sources${Platform.pathSeparator}src_web_f0_example${Platform.pathSeparator}'
      'ver_web_f0_example_sidecar_rollback.json',
    );
    final temp = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    await target.parent.create(recursive: true);
    await temp.writeAsString('{"preexisting":"temp"}');
    await backup.writeAsString('{"preexisting":"backup"}');

    await expectLater(faulting.commitIngestion(result), throwsStateError);

    expect(await faulting.listCards(), isEmpty);
    expect(await db.select(db.whiteboardSourceVersions).get(), isEmpty);
    expect(await target.exists(), isFalse);
    expect(await temp.readAsString(), '{"preexisting":"temp"}');
    expect(await backup.readAsString(), '{"preexisting":"backup"}');
  });

  test('same object ref commits serialize across one failure', () async {
    var failOnce = true;
    final faulting = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      faultInjector: (point) async {
        if (failOnce &&
            point ==
                UnifiedCardRepositoryFaultPoint.ingestionAfterVersionInsert) {
          failOnce = false;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          throw StateError('first concurrent commit fails');
        }
      },
    );
    final result = _ingestion(hash: 'concurrent_ref', body: '并发对象');

    Future<Object> capture(Future<IngestionCommitResult> future) async {
      try {
        return await future;
      } catch (error) {
        return error;
      }
    }

    final first = capture(faulting.commitIngestion(result));
    await Future<void>.delayed(Duration.zero);
    final second = capture(faulting.commitIngestion(result));
    final outcomes = await Future.wait([first, second]);
    expect(outcomes.whereType<StateError>(), hasLength(1));
    expect(outcomes.whereType<IngestionCommitResult>(), hasLength(1));
    expect(await faulting.listCards(), hasLength(1));
    expect(
      await faulting.listSourceVersions(result.source!.sourceId),
      hasLength(1),
    );

    final idempotent = await faulting.commitIngestion(result);
    expect(idempotent.versionIsNew, isFalse);
    expect(idempotent.cardCreated, isFalse);
    expect(await faulting.listCards(), hasLength(1));
  });

  test(
      'same canonical identity serializes different incoming source ids into one truth',
      () async {
    final objectWritten = Completer<void>();
    final releaseFirst = Completer<void>();
    final firstRepository = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      faultInjector: (point) async {
        if (point ==
            UnifiedCardRepositoryFaultPoint
                .ingestionAfterObjectWriteBeforeVersionInsert) {
          if (!objectWritten.isCompleted) objectWritten.complete();
          await releaseFirst.future;
        }
      },
    );
    final secondRepository = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
    );
    final firstFuture = firstRepository.commitIngestion(
      _ingestion(
        hash: 'canonical_concurrent',
        body: '第一份来料',
        sourceId: 'src_canonical_first',
        canonicalId: 'shared-video-42',
      ),
    );
    await objectWritten.future;
    final secondFuture = secondRepository.commitIngestion(
      _ingestion(
        hash: 'canonical_concurrent',
        body: '第二份来料',
        sourceId: 'src_canonical_second',
        canonicalId: 'shared-video-42',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    releaseFirst.complete();

    final results = await Future.wait([firstFuture, secondFuture]);
    expect(results.map((item) => item.source.sourceId).toSet(), {
      'src_canonical_first',
    });
    expect(await db.select(db.whiteboardSources).get(), hasLength(1));
    expect(await db.select(db.whiteboardSourceVersions).get(), hasLength(1));
    expect(await repository.listCards(), hasLength(1));
    final objectRoot = Directory(
      '${tempDir.path}${Platform.pathSeparator}objects'
      '${Platform.pathSeparator}sources',
    );
    final files = await objectRoot
        .list(recursive: true)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    expect(files.where((file) => file.path.endsWith('.json')), hasLength(1));
    expect(
      files.where(
        (file) => file.path.endsWith('.tmp') || file.path.endsWith('.bak'),
      ),
      isEmpty,
    );
  });

  test('canonical URL and id equivalence classes serialize without divergence',
      () async {
    Future<List<IngestionCommitResult>> commitPair(
      String caseName,
      IngestionResult first,
      IngestionResult second,
    ) async {
      final objectWritten = Completer<void>();
      final release = Completer<void>();
      final firstRepository = UnifiedCardRepository(
        db: db,
        whiteboardRoot: tempDir,
        faultInjector: (point) async {
          if (point ==
              UnifiedCardRepositoryFaultPoint
                  .ingestionAfterObjectWriteBeforeVersionInsert) {
            if (!objectWritten.isCompleted) objectWritten.complete();
            await release.future;
          }
        },
      );
      final firstFuture = firstRepository.commitIngestion(first);
      await objectWritten.future;
      final secondFuture = repository.commitIngestion(second);
      await Future<void>.delayed(Duration.zero);
      release.complete();
      final results = await Future.wait([firstFuture, secondFuture]);
      expect(
        results.map((item) => item.source.sourceId).toSet(),
        hasLength(1),
        reason: caseName,
      );
      return results;
    }

    await commitPair(
      'id versus url-only',
      _ingestion(
        hash: 'equivalence_id_url',
        body: '有 ID',
        sourceId: 'src_equivalence_id',
        provider: 'video',
        canonicalUrl: 'https://example.com/equivalence/id-url',
        canonicalId: 'equivalence-1',
      ),
      _ingestion(
        hash: 'equivalence_id_url',
        body: '只有 URL',
        sourceId: 'src_equivalence_url',
        provider: 'video',
        canonicalUrl: 'https://example.com/equivalence/id-url',
      ),
    );
    await commitPair(
      'different ids but same url',
      _ingestion(
        hash: 'equivalence_diff_ids',
        body: 'ID A',
        sourceId: 'src_equivalence_diff_a',
        provider: 'video',
        canonicalUrl: 'https://example.com/equivalence/diff-ids',
        canonicalId: 'different-a',
      ),
      _ingestion(
        hash: 'equivalence_diff_ids',
        body: 'ID B',
        sourceId: 'src_equivalence_diff_b',
        provider: 'video',
        canonicalUrl: 'https://example.com/equivalence/diff-ids',
        canonicalId: 'different-b',
      ),
    );
    await commitPair(
      'same id but different urls',
      _ingestion(
        hash: 'equivalence_same_id',
        body: 'URL A',
        sourceId: 'src_equivalence_same_a',
        provider: 'video',
        canonicalUrl: 'https://example.com/equivalence/url-a',
        canonicalId: 'same-id',
      ),
      _ingestion(
        hash: 'equivalence_same_id',
        body: 'URL B',
        sourceId: 'src_equivalence_same_b',
        provider: 'video',
        canonicalUrl: 'https://example.com/equivalence/url-b',
        canonicalId: 'same-id',
      ),
    );

    expect(await db.select(db.whiteboardSources).get(), hasLength(3));
    expect(await db.select(db.whiteboardSourceVersions).get(), hasLength(3));
    expect(await repository.listCards(), hasLength(3));
  });

  test(
      'same object ref with different canonical identities survives one failure',
      () async {
    var failFirst = true;
    final firstRepository = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      faultInjector: (point) async {
        if (failFirst &&
            point ==
                UnifiedCardRepositoryFaultPoint.ingestionAfterVersionInsert) {
          failFirst = false;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          throw StateError('first object-ref writer fails');
        }
      },
    );
    final firstResult = _ingestion(
      hash: 'shared_object_identity_failure',
      body: '失败来料',
      sourceId: 'src_shared_object_identity',
      provider: 'provider-a',
      canonicalUrl: 'https://example.com/object/a',
      canonicalId: 'object-a',
    );
    final winningResult = _ingestion(
      hash: 'shared_object_identity_failure',
      body: '胜出来料',
      sourceId: 'src_shared_object_identity',
      provider: 'provider-b',
      canonicalUrl: 'https://example.com/object/b',
      canonicalId: 'object-b',
    );

    Future<Object> capture(Future<IngestionCommitResult> future) async {
      try {
        return await future;
      } catch (error) {
        return error;
      }
    }

    final first = capture(firstRepository.commitIngestion(firstResult));
    await Future<void>.delayed(Duration.zero);
    final second = capture(repository.commitIngestion(winningResult));
    final outcomes = await Future.wait([first, second]);
    expect(outcomes.whereType<StateError>(), hasLength(1));
    expect(outcomes.whereType<IngestionCommitResult>(), hasLength(1));

    final source = await repository.getSource('src_shared_object_identity');
    expect(source!.provider, 'provider-b');
    expect(source.canonicalId, 'object-b');
    expect(source.metadata['canonical_url'], 'https://example.com/object/b');
    final version =
        (await repository.listSourceVersions(source.sourceId)).single;
    final object = await repository.getSourceObject(version);
    expect(object.bodyText, '胜出来料');
    expect(object.payload!['canonical_url'], 'https://example.com/object/b');
  });

  test('same object ref with two successes preserves the first committed bytes',
      () async {
    final objectWritten = Completer<void>();
    final release = Completer<void>();
    final firstRepository = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      faultInjector: (point) async {
        if (point ==
            UnifiedCardRepositoryFaultPoint
                .ingestionAfterObjectWriteBeforeVersionInsert) {
          if (!objectWritten.isCompleted) objectWritten.complete();
          await release.future;
        }
      },
    );
    final firstResult = _ingestion(
      hash: 'shared_object_two_successes',
      body: '第一胜者',
      sourceId: 'src_shared_object_two_successes',
      provider: 'provider-first',
      canonicalUrl: 'https://example.com/object/first',
      canonicalId: 'object-first',
    );
    final secondResult = _ingestion(
      hash: 'shared_object_two_successes',
      body: '第二来料',
      sourceId: 'src_shared_object_two_successes',
      provider: 'provider-second',
      canonicalUrl: 'https://example.com/object/second',
      canonicalId: 'object-second',
    );

    final first = firstRepository.commitIngestion(firstResult);
    await objectWritten.future;
    final second = repository.commitIngestion(secondResult);
    await Future<void>.delayed(Duration.zero);
    release.complete();
    final results = await Future.wait([first, second]);
    expect(results.where((item) => item.versionIsNew), hasLength(1));

    final source =
        await repository.getSource('src_shared_object_two_successes');
    expect(source!.provider, 'provider-first');
    expect(source.canonicalId, 'object-first');
    expect(
        source.metadata['canonical_url'], 'https://example.com/object/first');
    final version =
        (await repository.listSourceVersions(source.sourceId)).single;
    final object = await repository.getSourceObject(version);
    expect(object.bodyText, '第一胜者');
    expect(
        object.payload!['canonical_url'], 'https://example.com/object/first');
    final card = await repository.getCardForSource(source.sourceId);
    expect(card!.body, '第一胜者');
  });

  test('startup intent removes a crash orphan and retry creates one truth',
      () async {
    final result = _ingestion(
      hash: 'crash_orphan',
      body: '进程退出前已写对象',
    );
    final crashing = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      faultInjector: (point) async {
        if (point ==
            UnifiedCardRepositoryFaultPoint
                .ingestionAfterObjectWriteBeforeVersionInsert) {
          throw const UnifiedCardRepositorySimulatedProcessExit();
        }
      },
    );
    final target = File(
      '${tempDir.path}${Platform.pathSeparator}objects${Platform.pathSeparator}'
      'sources${Platform.pathSeparator}src_web_f0_example${Platform.pathSeparator}'
      'ver_web_f0_example_crash_orphan.json',
    );

    await expectLater(
      crashing.commitIngestion(result),
      throwsA(isA<UnifiedCardRepositorySimulatedProcessExit>()),
    );
    expect(await target.exists(), isTrue);
    expect(await db.select(db.whiteboardSources).get(), isEmpty);
    expect(await db.select(db.whiteboardSourceVersions).get(), isEmpty);
    expect(await _intentFiles(tempDir), isNotEmpty);

    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    repository = UnifiedCardRepository(db: db, whiteboardRoot: tempDir);
    await repository.recoverFileReplacements();

    expect(await target.exists(), isFalse);
    expect(await File('${target.path}.tmp').exists(), isFalse);
    expect(await File('${target.path}.bak').exists(), isFalse);
    expect(await _intentFiles(tempDir), isEmpty);
    expect(await db.select(db.whiteboardSources).get(), isEmpty);
    expect(await db.select(db.whiteboardSourceVersions).get(), isEmpty);

    final retried = await repository.commitIngestion(result);
    expect(retried.cardCreated, isTrue);
    expect(await repository.listCards(), hasLength(1));
    expect(await db.select(db.whiteboardSourceVersions).get(), hasLength(1));
  });

  test('startup intent restores exact pre-write final and sidecar snapshots',
      () async {
    final result = _ingestion(
      hash: 'crash_snapshot_restore',
      body: '不应覆盖旧现场',
    );
    final target = File(
      '${tempDir.path}${Platform.pathSeparator}objects${Platform.pathSeparator}'
      'sources${Platform.pathSeparator}src_web_f0_example${Platform.pathSeparator}'
      'ver_web_f0_example_crash_snapshot_restore.json',
    );
    final temp = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    const oldFinal = <int>[123, 34, 111, 108, 100, 34, 58, 49, 125];
    const oldTemp = <int>[1, 3, 5, 7, 9];
    const oldBackup = <int>[2, 4, 6, 8];
    await target.parent.create(recursive: true);
    await target.writeAsBytes(oldFinal, flush: true);
    await temp.writeAsBytes(oldTemp, flush: true);
    await backup.writeAsBytes(oldBackup, flush: true);
    final crashing = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      faultInjector: (point) async {
        if (point ==
            UnifiedCardRepositoryFaultPoint
                .ingestionAfterObjectWriteBeforeVersionInsert) {
          throw const UnifiedCardRepositorySimulatedProcessExit();
        }
      },
    );

    await expectLater(
      crashing.commitIngestion(result),
      throwsA(isA<UnifiedCardRepositorySimulatedProcessExit>()),
    );
    expect(await target.readAsBytes(), isNot(oldFinal));
    expect(await db.select(db.whiteboardSourceVersions).get(), isEmpty);
    expect(await _intentFiles(tempDir), isNotEmpty);

    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    repository = UnifiedCardRepository(db: db, whiteboardRoot: tempDir);
    await repository.recoverFileReplacements();

    expect(await target.readAsBytes(), oldFinal);
    expect(await temp.readAsBytes(), oldTemp);
    expect(await backup.readAsBytes(), oldBackup);
    expect(await _intentFiles(tempDir), isEmpty);
    expect(await db.select(db.whiteboardSources).get(), isEmpty);
    expect(await db.select(db.whiteboardSourceVersions).get(), isEmpty);
  });

  test(
      'corrupt intents preserve object exchanges while an interrupted valid intent recovers',
      () async {
    final invalidCases = <String>[
      'bit_flip',
      'invalid_base64',
      'missing_hash',
      'unknown_version',
    ];
    final invalidIntents = <File>[];
    final invalidTargets = <File>[];
    final expectedExchanges = <List<List<int>?>>[];

    for (var index = 0; index < invalidCases.length; index++) {
      final name = invalidCases[index];
      final sourceId = 'src_web_intent_$name';
      final result = _ingestion(
        hash: name,
        body: '损坏 journal 不得改写 $name',
        sourceId: sourceId,
        canonicalUrl: 'https://example.com/intent/$name',
      );
      final target = _sourceObjectFile(tempDir, sourceId, name);
      await target.parent.create(recursive: true);
      await target.writeAsString('{"old":"$name"}', flush: true);
      final crashing = UnifiedCardRepository(
        db: db,
        whiteboardRoot: tempDir,
        faultInjector: (point) async {
          if (point ==
              UnifiedCardRepositoryFaultPoint
                  .ingestionAfterObjectWriteBeforeVersionInsert) {
            throw const UnifiedCardRepositorySimulatedProcessExit();
          }
        },
      );

      await expectLater(
        crashing.commitIngestion(result),
        throwsA(isA<UnifiedCardRepositorySimulatedProcessExit>()),
      );
      final objectRef =
          'objects/sources/$sourceId/${sourceId.replaceFirst('src_', 'ver_')}_$name.json';
      final intent = await _intentFileForObjectRef(tempDir, objectRef);
      final decoded =
          jsonDecode(await intent.readAsString()) as Map<String, dynamic>;
      final rawSnapshots =
          Map<String, dynamic>.from(decoded['pre_write_snapshot'] as Map);
      final finalSnapshot =
          Map<String, dynamic>.from(rawSnapshots['final'] as Map);
      switch (name) {
        case 'bit_flip':
          final encoded = finalSnapshot['bytes_base64'] as String;
          finalSnapshot['bytes_base64'] =
              '${encoded[0] == 'A' ? 'B' : 'A'}${encoded.substring(1)}';
          break;
        case 'invalid_base64':
          finalSnapshot['bytes_base64'] = '!!!';
          break;
        case 'missing_hash':
          finalSnapshot.remove('sha256');
          break;
        case 'unknown_version':
          decoded['schema_version'] = 99;
          break;
      }
      rawSnapshots['final'] = finalSnapshot;
      decoded['pre_write_snapshot'] = rawSnapshots;
      await intent.writeAsString(jsonEncode(decoded), flush: true);

      final temp = File('${target.path}.tmp');
      final backup = File('${target.path}.bak');
      await temp.writeAsBytes(<int>[index, 11, 12], flush: true);
      await backup.writeAsBytes(<int>[index, 21, 22], flush: true);
      invalidIntents.add(intent);
      invalidTargets.add(target);
      expectedExchanges.add(await _readFileExchange(target));
    }

    const validSourceId = 'src_web_interrupted_valid_intent';
    const validHash = 'interrupted_valid_intent';
    final validResult = _ingestion(
      hash: validHash,
      body: '合法 journal 应继续恢复',
      sourceId: validSourceId,
      canonicalUrl: 'https://example.com/intent/interrupted-valid',
    );
    final validTarget = _sourceObjectFile(tempDir, validSourceId, validHash);
    final crashing = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      faultInjector: (point) async {
        if (point ==
            UnifiedCardRepositoryFaultPoint
                .ingestionAfterObjectWriteBeforeVersionInsert) {
          throw const UnifiedCardRepositorySimulatedProcessExit();
        }
      },
    );
    await expectLater(
      crashing.commitIngestion(validResult),
      throwsA(isA<UnifiedCardRepositorySimulatedProcessExit>()),
    );
    final validObjectRef =
        'objects/sources/$validSourceId/${validSourceId.replaceFirst('src_', 'ver_')}_$validHash.json';
    final validIntent = await _intentFileForObjectRef(tempDir, validObjectRef);
    final validJournal = await validIntent.readAsString();
    final interruptedTemp = File('${validIntent.path}.tmp');
    final residualBackup = File('${validIntent.path}.bak');
    await validIntent.rename(interruptedTemp.path);
    await residualBackup.writeAsString(validJournal, flush: true);

    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    repository = UnifiedCardRepository(db: db, whiteboardRoot: tempDir);
    await repository.recoverFileReplacements();

    for (var index = 0; index < invalidTargets.length; index++) {
      expect(await _readFileExchange(invalidTargets[index]),
          expectedExchanges[index]);
      expect(await invalidIntents[index].exists(), isTrue);
    }
    expect(await validTarget.exists(), isFalse);
    expect(await validIntent.exists(), isFalse);
    expect(await interruptedTemp.exists(), isFalse);
    expect(await residualBackup.exists(), isFalse);
    expect(await db.select(db.whiteboardSources).get(), isEmpty);
    expect(await db.select(db.whiteboardSourceVersions).get(), isEmpty);
  });

  test(
      'semantic tmp and backup recover while an opaque intent freezes generic object repair',
      () async {
    Future<({File intent, File target, String journal})> leaveCrash({
      required String sourceId,
      required String hash,
    }) async {
      final result = _ingestion(
        hash: hash,
        body: '合法候选 $hash',
        sourceId: sourceId,
        canonicalUrl: 'https://example.com/intent-candidate/$hash',
      );
      final crashing = UnifiedCardRepository(
        db: db,
        whiteboardRoot: tempDir,
        faultInjector: (point) async {
          if (point ==
              UnifiedCardRepositoryFaultPoint
                  .ingestionAfterObjectWriteBeforeVersionInsert) {
            throw const UnifiedCardRepositorySimulatedProcessExit();
          }
        },
      );
      await expectLater(
        crashing.commitIngestion(result),
        throwsA(isA<UnifiedCardRepositorySimulatedProcessExit>()),
      );
      final objectRef =
          'objects/sources/$sourceId/${sourceId.replaceFirst('src_', 'ver_')}_$hash.json';
      final intent = await _intentFileForObjectRef(tempDir, objectRef);
      return (
        intent: intent,
        target: _sourceObjectFile(tempDir, sourceId, hash),
        journal: await intent.readAsString(),
      );
    }

    final tempRecovery = await leaveCrash(
      sourceId: 'src_web_semantic_temp',
      hash: 'semantic_temp',
    );
    await tempRecovery.intent.writeAsString('not-json', flush: true);
    await File('${tempRecovery.intent.path}.tmp')
        .writeAsString(tempRecovery.journal, flush: true);

    final backupRecovery = await leaveCrash(
      sourceId: 'src_web_semantic_backup',
      hash: 'semantic_backup',
    );
    await backupRecovery.intent.writeAsString('{"truncated":', flush: true);
    await File('${backupRecovery.intent.path}.bak')
        .writeAsString(backupRecovery.journal, flush: true);

    final intentRoot = Directory(
      '${tempDir.path}${Platform.pathSeparator}objects'
      '${Platform.pathSeparator}source_object_intents',
    );
    await intentRoot.create(recursive: true);
    final opaqueIntent = File(
      '${intentRoot.path}${Platform.pathSeparator}opaque.json',
    );
    await opaqueIntent.writeAsString('{"cut":', flush: true);
    await File('${opaqueIntent.path}.tmp')
        .writeAsString('not-json', flush: true);
    await File('${opaqueIntent.path}.bak')
        .writeAsString('{"also":"cut"', flush: true);
    final opaqueIntentBefore = await _readFileExchange(opaqueIntent);

    final unrelatedTarget = _sourceObjectFile(
      tempDir,
      'src_web_unresolved_freeze',
      'unresolved_freeze',
    );
    await unrelatedTarget.parent.create(recursive: true);
    await unrelatedTarget.writeAsString('{"valid":"final"}', flush: true);
    await File('${unrelatedTarget.path}.tmp')
        .writeAsBytes(const <int>[1, 2, 3], flush: true);
    await File('${unrelatedTarget.path}.bak')
        .writeAsBytes(const <int>[4, 5, 6], flush: true);
    final unrelatedBefore = await _readFileExchange(unrelatedTarget);

    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    repository = UnifiedCardRepository(db: db, whiteboardRoot: tempDir);
    await repository.recoverFileReplacements();

    expect(await tempRecovery.target.exists(), isFalse);
    expect(await _readFileExchange(tempRecovery.intent),
        const <List<int>?>[null, null, null]);
    expect(await backupRecovery.target.exists(), isFalse);
    expect(await _readFileExchange(backupRecovery.intent),
        const <List<int>?>[null, null, null]);
    expect(await _readFileExchange(opaqueIntent), opaqueIntentBefore);
    expect(await _readFileExchange(unrelatedTarget), unrelatedBefore);
    expect(await db.select(db.whiteboardSources).get(), isEmpty);
    expect(await db.select(db.whiteboardSourceVersions).get(), isEmpty);
  });

  test('oversized opaque intent is not loaded and freezes generic repair',
      () async {
    final intentRoot = Directory(
      '${tempDir.path}${Platform.pathSeparator}objects'
      '${Platform.pathSeparator}source_object_intents',
    );
    await intentRoot.create(recursive: true);
    final oversizedIntent = File(
      '${intentRoot.path}${Platform.pathSeparator}oversized.json',
    );
    const oversizedLength = 13 * 1024 * 1024;
    await oversizedIntent.writeAsBytes(
      List<int>.filled(oversizedLength, 65),
      flush: true,
    );

    final target = _sourceObjectFile(
      tempDir,
      'src_web_oversized_intent',
      'oversized_intent',
    );
    await target.parent.create(recursive: true);
    await target.writeAsString('{"valid":"final"}', flush: true);
    await File('${target.path}.tmp')
        .writeAsBytes(const <int>[7, 8], flush: true);
    await File('${target.path}.bak')
        .writeAsBytes(const <int>[9, 10], flush: true);
    final targetBefore = await _readFileExchange(target);

    await repository.recoverFileReplacements();

    expect(await oversizedIntent.length(), oversizedLength);
    expect(await _readFileExchange(target), targetBefore);
  });

  test('unprovable real-path containment preserves intent and object peers',
      () async {
    const sourceId = 'src_web_containment_escape';
    const hash = 'containment_escape';
    final result = _ingestion(
      hash: hash,
      body: '路径无法证明时不得恢复',
      sourceId: sourceId,
      canonicalUrl: 'https://example.com/containment-escape',
    );
    final crashing = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      faultInjector: (point) async {
        if (point ==
            UnifiedCardRepositoryFaultPoint
                .ingestionAfterObjectWriteBeforeVersionInsert) {
          throw const UnifiedCardRepositorySimulatedProcessExit();
        }
      },
    );
    await expectLater(
      crashing.commitIngestion(result),
      throwsA(isA<UnifiedCardRepositorySimulatedProcessExit>()),
    );
    final objectRef =
        'objects/sources/$sourceId/${sourceId.replaceFirst('src_', 'ver_')}_$hash.json';
    final intent = await _intentFileForObjectRef(tempDir, objectRef);
    final target = _sourceObjectFile(tempDir, sourceId, hash);
    await File('${target.path}.tmp')
        .writeAsBytes(const <int>[31, 32], flush: true);
    await File('${target.path}.bak')
        .writeAsBytes(const <int>[41, 42], flush: true);
    final intentBefore = await _readFileExchange(intent);
    final targetBefore = await _readFileExchange(target);
    final outside = await Directory.systemTemp.createTemp('source_escape_');
    addTearDown(() async {
      if (await outside.exists()) await outside.delete(recursive: true);
    });
    final targetParent = target.parent.absolute.path.toLowerCase();

    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    repository = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      sourceObjectPathCanonicalizer: (path) async {
        if (Directory(path).absolute.path.toLowerCase() == targetParent) {
          return outside.resolveSymbolicLinks();
        }
        return Directory(path).resolveSymbolicLinks();
      },
    );
    await repository.recoverFileReplacements();

    expect(await _readFileExchange(intent), intentBefore);
    expect(await _readFileExchange(target), targetBefore);
    expect(await db.select(db.whiteboardSources).get(), isEmpty);
    expect(await db.select(db.whiteboardSourceVersions).get(), isEmpty);
  });

  test('oversize recovery snapshot fails before journal or object mutation',
      () async {
    const sourceId = 'src_web_oversize_snapshot';
    const hash = 'oversize_snapshot';
    final result = _ingestion(
      hash: hash,
      body: '不得写入',
      sourceId: sourceId,
      canonicalUrl: 'https://example.com/oversize-snapshot',
    );
    final target = _sourceObjectFile(tempDir, sourceId, hash);
    final temp = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    final bytes = List<int>.filled(3 * 1024 * 1024, 73);
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes, flush: true);
    await temp.writeAsBytes(bytes, flush: true);
    await backup.writeAsBytes(bytes, flush: true);
    final before = await _readFileExchange(target);

    await expectLater(
      repository.commitIngestion(result),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'safe message',
          'Source object recovery snapshot exceeds safe limit',
        ),
      ),
    );

    expect(await _readFileExchange(target), before);
    expect(await _intentFiles(tempDir), isEmpty);
    expect(await db.select(db.whiteboardSources).get(), isEmpty);
    expect(await db.select(db.whiteboardSourceVersions).get(), isEmpty);
    expect(await db.select(db.memoryCards).get(), isEmpty);
  });

  test('startup intent keeps a DB-referenced object and removes only intent',
      () async {
    final result = _ingestion(
      hash: 'crash_after_commit',
      body: '数据库已提交',
    );
    final crashing = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      faultInjector: (point) async {
        if (point ==
            UnifiedCardRepositoryFaultPoint
                .ingestionAfterTransactionCommitBeforeIntentCleanup) {
          throw const UnifiedCardRepositorySimulatedProcessExit();
        }
      },
    );
    final target = File(
      '${tempDir.path}${Platform.pathSeparator}objects${Platform.pathSeparator}'
      'sources${Platform.pathSeparator}src_web_f0_example${Platform.pathSeparator}'
      'ver_web_f0_example_crash_after_commit.json',
    );

    await expectLater(
      crashing.commitIngestion(result),
      throwsA(isA<UnifiedCardRepositorySimulatedProcessExit>()),
    );
    expect(await target.exists(), isTrue);
    expect(await db.select(db.whiteboardSourceVersions).get(), hasLength(1));
    expect(await _intentFiles(tempDir), isNotEmpty);

    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    repository = UnifiedCardRepository(db: db, whiteboardRoot: tempDir);
    await repository.recoverFileReplacements();

    expect(await target.exists(), isTrue);
    expect(await _intentFiles(tempDir), isEmpty);
    final committed = await repository.commitIngestion(result);
    expect(committed.versionIsNew, isFalse);
    expect(await repository.listCards(), hasLength(1));
  });

  test('ordinary post-commit cleanup failure never compensates committed bytes',
      () async {
    final result = _ingestion(
      hash: 'cleanup_failure_after_commit',
      body: '数据库与新对象必须一致',
    );
    final target = File(
      '${tempDir.path}${Platform.pathSeparator}objects${Platform.pathSeparator}'
      'sources${Platform.pathSeparator}src_web_f0_example${Platform.pathSeparator}'
      'ver_web_f0_example_cleanup_failure_after_commit.json',
    );
    await target.parent.create(recursive: true);
    await target.writeAsString('{"old":"must-not-return"}', flush: true);
    final cleanupFailing = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      faultInjector: (point) async {
        if (point ==
            UnifiedCardRepositoryFaultPoint
                .ingestionAfterTransactionCommitBeforeIntentCleanup) {
          throw StateError('ordinary cleanup I/O failure');
        }
      },
    );

    final committed = await cleanupFailing.commitIngestion(result);
    expect(committed.cardCreated, isTrue);
    expect(await db.select(db.whiteboardSourceVersions).get(), hasLength(1));
    expect(await _intentFiles(tempDir), isNotEmpty);
    var payload =
        jsonDecode(await target.readAsString()) as Map<String, dynamic>;
    expect(payload['body_text'], '数据库与新对象必须一致');
    expect(payload.containsKey('old'), isFalse);

    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    repository = UnifiedCardRepository(db: db, whiteboardRoot: tempDir);
    await repository.recoverFileReplacements();

    expect(await _intentFiles(tempDir), isEmpty);
    expect(await db.select(db.whiteboardSourceVersions).get(), hasLength(1));
    payload = jsonDecode(await target.readAsString()) as Map<String, dynamic>;
    expect(payload['body_text'], '数据库与新对象必须一致');
    expect(payload.containsKey('old'), isFalse);
    final object = await repository.getSourceObject(committed.version);
    expect(object.bodyText, '数据库与新对象必须一致');
  });

  test('startup reconciliation never deletes an unjournaled managed object',
      () async {
    final existing = File(
      '${tempDir.path}${Platform.pathSeparator}objects${Platform.pathSeparator}'
      'sources${Platform.pathSeparator}legacy${Platform.pathSeparator}'
      'legal-unreferenced.json',
    );
    await existing.parent.create(recursive: true);
    await existing.writeAsString('{"legacy":"keep"}');

    await repository.recoverFileReplacements();

    expect(await existing.exists(), isTrue);
    expect(await existing.readAsString(), '{"legacy":"keep"}');
  });

  test('same canonical content is idempotent', () async {
    final first = await repository.commitIngestion(
      _ingestion(hash: 'same_hash', body: '相同内容'),
    );
    final second = await repository.commitIngestion(
      _ingestion(hash: 'same_hash', body: '相同内容'),
    );

    expect(second.versionIsNew, isFalse);
    expect(second.cardCreated, isFalse);
    expect(second.card.cardId, first.card.cardId);
    expect(await repository.listCards(), hasLength(1));
    expect(
      await repository.listSourceVersions(first.source.sourceId),
      hasLength(1),
    );
  });

  test('changed content adds SourceVersion without duplicating Card', () async {
    final first = await repository.commitIngestion(
      _ingestion(hash: 'hash_v1', body: '版本一'),
    );
    final second = await repository.commitIngestion(
      _ingestion(hash: 'hash_v2', body: '版本二'),
    );

    expect(second.versionIsNew, isTrue);
    expect(second.card.cardId, first.card.cardId);
    expect(await repository.listCards(), hasLength(1));
    expect(
      await repository.listSourceVersions(first.source.sourceId),
      hasLength(2),
    );
  });

  test('safe thumbnail projection persists on the existing Source card',
      () async {
    final thumbnailFile = File('${tempDir.path}/trusted-thumbnail.png');
    await thumbnailFile.writeAsBytes([1], flush: true);
    const objectRef =
        'objects/thumbnails/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png';
    final candidateHash = SafeThumbnailResolver.candidateHashFor(
      'https://example.com/cover.png',
      'https://example.com/f0',
    )!;
    final resolver = _RecordingThumbnailResolver(
      ResolvedThumbnail.available(
        file: thumbnailFile,
        objectRef: objectRef,
        width: 40,
        height: 24,
        candidateHash: candidateHash,
      ),
    );
    repository = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      thumbnailResolver: resolver,
    );
    final committed = await repository.commitIngestion(
      _ingestion(hash: 'thumbnail_projection', body: '缩略图投影'),
    );
    final before = await repository.getCard(
      committed.card.cardId,
      loadDocument: false,
    );

    final resolved = await repository.resolveThumbnail(before!);

    expect(resolved.isAvailable, isTrue);
    expect(resolver.requests, hasLength(1));
    expect(
        resolver.requests.single.candidateUrl, 'https://example.com/cover.png');
    expect(resolver.requests.single.cachedObjectRef, isNull);
    final recovered = await repository.getCard(
      committed.card.cardId,
      loadDocument: false,
    );
    expect(recovered!.card.cardId, committed.card.cardId);
    expect(recovered.card.sourceId, committed.source.sourceId);
    expect(
      recovered.card.updatedAt,
      before.card.updatedAt,
      reason: 'a rebuildable thumbnail must not masquerade as a card edit',
    );
    expect(recovered.card.presentation['thumbnail_ref'], objectRef);
    expect(
      recovered.card.presentation['thumbnail_version_id'],
      committed.version.versionId,
    );
    expect(
      recovered.card.presentation['thumbnail_candidate_hash'],
      candidateHash,
    );
  });

  test('thumbnail reference inventory protects Card and Source projections',
      () async {
    const cardRef =
        'objects/thumbnails/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png';
    const sourceRef =
        'objects/thumbnails/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.png';
    final thumbnailFile = File('${tempDir.path}/inventory-thumbnail.png');
    await thumbnailFile.writeAsBytes([1], flush: true);
    final candidateHash = SafeThumbnailResolver.candidateHashFor(
      'https://example.com/cover.png',
      'https://example.com/f0',
    )!;
    repository = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      thumbnailResolver: _RecordingThumbnailResolver(
        ResolvedThumbnail.available(
          file: thumbnailFile,
          objectRef: cardRef,
          width: 40,
          height: 24,
          candidateHash: candidateHash,
        ),
      ),
    );
    final committed = await repository.commitIngestion(
      _ingestion(
        hash: 'thumbnail_inventory',
        body: '引用清单',
        sourceThumbnailRef: sourceRef,
      ),
    );
    final card = await repository.getCard(
      committed.card.cardId,
      loadDocument: false,
    );
    await repository.resolveThumbnail(card!);
    await repository.softDeleteCard(committed.card.cardId);

    final refs = await repository.referencedThumbnailObjectRefs();

    expect(refs, containsAll([cardRef, sourceRef]));
  });

  test('background thumbnail projection cannot overwrite a concurrent edit',
      () async {
    final gate = Completer<void>();
    final resolver = _RecordingThumbnailResolver(
      ResolvedThumbnail.available(
        file: File('${tempDir.path}/trusted-concurrent.png'),
        objectRef:
            'objects/thumbnails/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.png',
        width: 40,
        height: 24,
        candidateHash: SafeThumbnailResolver.candidateHashFor(
          'https://example.com/cover.png',
          'https://example.com/f0',
        )!,
      ),
      gate: gate,
    );
    repository = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      thumbnailResolver: resolver,
    );
    final committed = await repository.commitIngestion(
      _ingestion(hash: 'thumbnail_concurrent', body: '原正文'),
    );
    final before = await repository.getCard(
      committed.card.cardId,
      loadDocument: false,
    );
    final resolving = repository.resolveThumbnail(before!);
    expect(resolver.requests, hasLength(1));

    final edited = await repository.updateCardMetadata(
      committed.card.cardId,
      title: '用户并发编辑后的标题',
      body: '用户并发编辑后的正文',
    );
    gate.complete();
    await resolving;

    final recovered = await repository.getCard(
      committed.card.cardId,
      loadDocument: false,
    );
    expect(recovered!.card.title, edited.title);
    expect(recovered.card.body, edited.body);
    expect(
      recovered.card.updatedAt?.millisecondsSinceEpoch,
      edited.updatedAt?.millisecondsSinceEpoch,
    );
    expect(recovered.card.presentation['thumbnail_ref'], isNotNull);
  });

  test('stale SourceVersion thumbnail cannot project after a new version',
      () async {
    final gate = Completer<void>();
    final resolver = _RecordingThumbnailResolver(
      ResolvedThumbnail.available(
        file: File('${tempDir.path}/stale-version.png'),
        objectRef:
            'objects/thumbnails/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee.png',
        width: 40,
        height: 24,
        candidateHash: SafeThumbnailResolver.candidateHashFor(
          'https://example.com/cover.png',
          'https://example.com/f0',
        )!,
      ),
      gate: gate,
    );
    repository = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      thumbnailResolver: resolver,
    );
    final first = await repository.commitIngestion(
      _ingestion(hash: 'thumbnail_version_v1', body: '版本一'),
    );
    final before = await repository.getCard(
      first.card.cardId,
      loadDocument: false,
    );
    final resolving = repository.resolveThumbnail(before!);
    expect(resolver.requests, hasLength(1));

    final second = await repository.commitIngestion(
      _ingestion(hash: 'thumbnail_version_v2', body: '版本二'),
    );
    gate.complete();
    final stale = await resolving;

    expect(stale.status, ThumbnailResolveStatus.missing);
    final recovered = await repository.getCard(
      first.card.cardId,
      loadDocument: false,
    );
    expect(
        recovered!.currentSourceVersion?.versionId, second.version.versionId);
    expect(recovered.card.presentation['thumbnail_ref'], isNull);
  });

  test('same SourceVersion cannot accept an older thumbnail candidate',
      () async {
    final gate = Completer<void>();
    final resolver = _RecordingThumbnailResolver(
      ResolvedThumbnail.available(
        file: File('${tempDir.path}/stale-candidate.png'),
        objectRef:
            'objects/thumbnails/9999999999999999999999999999999999999999999999999999999999999999.png',
        width: 40,
        height: 24,
        candidateHash: SafeThumbnailResolver.candidateHashFor(
          'https://example.com/cover.png',
          'https://example.com/f0',
        )!,
      ),
      gate: gate,
    );
    repository = UnifiedCardRepository(
      db: db,
      whiteboardRoot: tempDir,
      thumbnailResolver: resolver,
    );
    final first = await repository.commitIngestion(
      _ingestion(hash: 'same_body_hash', body: '相同正文'),
    );
    final before = await repository.getCard(
      first.card.cardId,
      loadDocument: false,
    );
    final resolving = repository.resolveThumbnail(before!);
    expect(resolver.requests, hasLength(1));

    final second = await repository.commitIngestion(
      _ingestion(
        hash: 'same_body_hash',
        body: '相同正文',
        ogImage: 'https://example.com/new-cover.png',
      ),
    );
    expect(second.version.versionId, first.version.versionId);
    gate.complete();
    final stale = await resolving;

    expect(stale.status, ThumbnailResolveStatus.missing);
    final recovered = await repository.getCard(
      first.card.cardId,
      loadDocument: false,
    );
    expect(recovered!.card.presentation['thumbnail_ref'], isNull);
    expect(
      recovered.card.presentation['thumbnail'],
      'https://example.com/new-cover.png',
    );
  });

  test('startup recovery restores a Source object backup after interruption',
      () async {
    final committed = await repository.commitIngestion(
      _ingestion(hash: 'recover_source', body: 'source object body'),
    );
    final target = File(
      '${tempDir.path}${Platform.pathSeparator}'
      '${committed.version.objectRef.replaceAll('/', Platform.pathSeparator)}',
    );
    final original = jsonDecode(await target.readAsString());
    await target.rename('${target.path}.bak');
    await File('${target.path}.tmp').writeAsString('{broken', flush: true);

    await repository.recoverFileReplacements();

    expect(jsonDecode(await target.readAsString()), original);
    expect(await File('${target.path}.tmp').exists(), isFalse);
    expect(await File('${target.path}.bak').exists(), isFalse);
  });

  test('delete BoardItem does not delete Card, Source, or RichText', () async {
    final committed = await repository.commitIngestion(
      _ingestion(hash: 'placed', body: '上板内容'),
    );
    await repository.saveRichText(
      committed.card.cardId,
      const RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: '持久富文本'),
      ]),
    );
    await db.customStatement(
      "INSERT INTO whiteboard_boards(id,name,created_at) VALUES ('board_f0','F0',1)",
    );
    await db.customStatement(
      "INSERT INTO whiteboard_board_items(id,board_id,card_id) "
      "VALUES ('item_f0','board_f0','${committed.card.cardId}')",
    );
    expect(await repository.isCardPlaced(committed.card.cardId), isTrue);

    await db.customStatement(
      "DELETE FROM whiteboard_board_items WHERE id='item_f0'",
    );

    expect(await repository.isCardPlaced(committed.card.cardId), isFalse);
    expect(await repository.getSource(committed.source.sourceId), isNotNull);
    final card = await repository.getCard(committed.card.cardId);
    expect(card, isNotNull);
    expect(card!.documentState, CardDocumentState.available);
  });

  test('missing and corrupt rich text states are reported honestly', () async {
    final card = await repository.createTextCard(
      title: '降级状态',
      body: '数据库投影仍在',
    );
    expect(
      (await repository.getCard(card.cardId))!.documentState,
      CardDocumentState.missing,
    );

    final dir = Directory(
        '${repository.richTextStorage.baseDir.path}/card_${card.cardId}');
    await dir.create(recursive: true);
    await File('${dir.path}/rich_text.json').writeAsString('{broken');
    final corrupt = await repository.getCard(card.cardId);
    expect(corrupt!.documentState, CardDocumentState.corrupt);
    expect(corrupt.card.body, '数据库投影仍在');
  });

  test('validated rich document uses strict canonical plain-text equality',
      () async {
    final card = await repository.createTextCard(
      cardId: 'strict_document',
      title: '原题',
      body: '正文\r\n第二行',
      tags: const ['原标签'],
    );
    const document = RichTextDocument(blocks: [
      RichTextBlock(type: BlockType.paragraph, text: '正文\r\n第二行'),
    ]);
    await repository.saveRichText(card.cardId, document, title: '原题');
    expect(
      (await repository.resolveCurrentDocument(card.cardId)).state,
      CardDocumentState.available,
    );

    await repository.updateCardMetadata(
      card.cardId,
      title: '只改标题',
      tags: const ['只改标签'],
    );
    expect(
      (await repository.resolveCurrentDocument(card.cardId)).state,
      CardDocumentState.available,
      reason: 'title and labels are outside the plain-body freshness guard',
    );

    for (final mismatch in <String>[
      '正文\n第二行',
      '正文\r\n第二行 ',
      '正文\r\n第二行é',
      '正文\r\n第二行e\u0301',
    ]) {
      await repository.updateCardMetadata(card.cardId, body: mismatch);
      final resolved = await repository.resolveCurrentDocument(card.cardId);
      expect(resolved.state, CardDocumentState.stale,
          reason: 'mismatch must remain strict: ${jsonEncode(mismatch)}');
      expect(resolved.document, isNull);
    }
  });

  test('notLoaded is distinct and stale validation ignores cached Card',
      () async {
    final cached = await repository.createTextCard(
      cardId: 'cached_document',
      body: 'A',
    );
    await repository.saveRichText(
      cached.cardId,
      const RichTextDocument(
        blocks: [RichTextBlock(type: BlockType.paragraph, text: 'A')],
      ),
    );
    final unloaded = await repository.listCards();
    expect(unloaded.single.documentState, CardDocumentState.notLoaded);
    expect(unloaded.single.document, isNull);

    await repository.updateCardMetadata(cached.cardId, body: 'B');
    final resolved = await repository.resolveCurrentDocument(cached.cardId);
    expect(resolved.state, CardDocumentState.stale);
    expect(resolved.document, isNull);

    final loaded = await repository.listCards(
      const CardLibraryQuery(loadDocuments: true),
    );
    expect(loaded.single.documentState, CardDocumentState.stale);
    expect(loaded.single.document, isNull);
  });

  test('soft delete and restore preserve stable identity and files', () async {
    final card = await repository.createTextCard(title: '可恢复');
    await repository.saveRichText(
        card.cardId,
        const RichTextDocument(blocks: [
          RichTextBlock(type: BlockType.paragraph, text: '不被删除'),
        ]));

    expect(await repository.softDeleteCard(card.cardId), isTrue);
    expect(await repository.getCard(card.cardId), isNull);
    expect(await repository.listCards(), isEmpty);
    expect(await repository.restoreCard(card.cardId), isTrue);

    final restored = await repository.getCard(card.cardId);
    expect(restored!.card.cardId, card.cardId);
    expect(restored.document!.toPlainText(), '不被删除');
  });

  test('kind, tag, source type, search and board placement filters compose',
      () async {
    final note = await repository.createTextCard(
      title: '研究笔记',
      body: '统一仓库',
      tags: const ['研究'],
    );
    final source = await repository.commitIngestion(
      _ingestion(hash: 'filter_hash', body: '网页正文'),
    );
    await db.customStatement(
      "INSERT INTO whiteboard_boards(id,name,created_at) VALUES ('board_filter','筛选',1)",
    );
    await db.customStatement(
      "INSERT INTO whiteboard_board_items(id,board_id,card_id) "
      "VALUES ('item_filter','board_filter','${note.cardId}')",
    );

    expect(
      await repository.listCards(const CardLibraryQuery(
        kinds: {CardKind.note},
        tags: {'研究'},
        search: '统一',
        boardId: 'board_filter',
        placedOnBoard: true,
      )),
      hasLength(1),
    );
    final web = await repository.listCards(const CardLibraryQuery(
      sourceTypes: {SourceMediaType.web},
    ));
    expect(web.single.card.cardId, source.card.cardId);
  });

  test('source object reader returns body and honest missing state', () async {
    final committed = await repository.commitIngestion(
      _ingestion(hash: 'object_reader', body: '可研读的完整正文'),
    );
    final available = await repository.getSourceObject(committed.version);
    expect(available.state, SourceObjectState.available);
    expect(available.bodyText, '可研读的完整正文');

    final missing = await repository.getSourceObject(SourceVersion(
      versionId: 'ver_missing',
      sourceId: committed.source.sourceId,
      contentHash: 'missing',
      objectRef: 'objects/sources/missing/version.json',
      createdAt: DateTime.utc(2026, 8, 19),
    ));
    expect(missing.state, SourceObjectState.missing);
  });

  test('all test persistence stays inside an explicit temporary directory',
      () async {
    await repository.createTextCard(title: '隔离测试');
    expect(dbFile.path, startsWith(tempDir.path));
    expect(repository.whiteboardRoot.path, tempDir.path);
  });
}

IngestionResult _ingestion({
  required String hash,
  required String body,
  String ogImage = 'https://example.com/cover.png',
  String? sourceThumbnailRef,
  String sourceId = 'src_web_f0_example',
  String provider = 'web',
  String canonicalUrl = 'https://example.com/f0',
  String? canonicalId,
}) {
  final now = DateTime.utc(2026, 8, 18, 12);
  final versionId = '${sourceId.replaceFirst(RegExp(r'^src_'), 'ver_')}_$hash';
  final source = SourceContent(
    sourceId: sourceId,
    mediaType: SourceMediaType.web,
    title: 'F0 网页',
    origin: SourceOrigin.externalLink,
    provider: provider,
    canonicalId: canonicalId,
    currentVersionId: versionId,
    contentHash: hash,
    objectRef: 'ingestion/$sourceId/$versionId.html',
    metadata: {
      'canonical_url': canonicalUrl,
      'og_image': ogImage,
      if (sourceThumbnailRef != null) 'thumbnail_ref': sourceThumbnailRef,
    },
    createdAt: now,
    updatedAt: now,
  );
  final version = SourceVersion(
    versionId: versionId,
    sourceId: sourceId,
    contentHash: hash,
    objectRef: source.objectRef!,
    parserVersion: 'test-v1',
    createdAt: now,
  );
  return IngestionResult(
    canonicalUrl: canonicalUrl,
    originalUrl: '$canonicalUrl?utm_source=test',
    provider: provider,
    status: IngestionStatus.ok,
    source: source,
    sourceVersion: version.toJson(),
    hasBody: true,
    metadata: {
      'body_text': body,
      'body_excerpt': body,
    },
    resolvedAt: now,
  );
}

Future<List<File>> _intentFiles(Directory root) async {
  final directory = Directory(
    '${root.path}${Platform.pathSeparator}objects${Platform.pathSeparator}'
    'source_object_intents',
  );
  if (!await directory.exists()) return const [];
  return directory
      .list()
      .where((entity) => entity is File)
      .cast<File>()
      .toList();
}

File _sourceObjectFile(Directory root, String sourceId, String hash) {
  final versionId = '${sourceId.replaceFirst('src_', 'ver_')}_$hash';
  return File(
    '${root.path}${Platform.pathSeparator}objects${Platform.pathSeparator}'
    'sources${Platform.pathSeparator}$sourceId${Platform.pathSeparator}'
    '$versionId.json',
  );
}

Future<File> _intentFileForObjectRef(Directory root, String objectRef) async {
  for (final file in await _intentFiles(root)) {
    if (file.path.endsWith('.tmp') || file.path.endsWith('.bak')) continue;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic> &&
          decoded['object_ref'] == objectRef) {
        return file;
      }
    } catch (_) {
      continue;
    }
  }
  throw StateError('Missing source object intent for $objectRef');
}

Future<List<List<int>?>> _readFileExchange(File target) async {
  final files = <File>[
    target,
    File('${target.path}.tmp'),
    File('${target.path}.bak'),
  ];
  final result = <List<int>?>[];
  for (final file in files) {
    result.add(await file.exists() ? await file.readAsBytes() : null);
  }
  return result;
}
