import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/repository_video_annotation_store.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/domain/whiteboard/video/video_domain.dart';

void main() {
  late Directory root;
  late File dbFile;
  late AppDatabase db;
  late UnifiedCardRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('f4_annotation_repository_');
    dbFile = File('${root.path}${Platform.pathSeparator}cards.sqlite');
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    await repository.commitIngestion(_videoIngestion(hash: 'v1'));
  });

  tearDown(() async {
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('annotation cards are repository-visible and survive restart', () async {
    final store = RepositoryVideoAnnotationStore(repository);
    final user = await store.createAnnotation(
      sourceId: 'src_youtube_demo',
      sourceVersionId: 'ver_youtube_demo_v1',
      request: const AnnotationCreationRequest(
        spec: TimeRangeAnchorSpec(startMs: 10000, endMs: 14000),
        title: '用户标注',
        body: '这一段值得保留',
      ),
    );
    final linAi = await store.createAnnotation(
      sourceId: 'src_youtube_demo',
      sourceVersionId: 'ver_youtube_demo_v1',
      request: const AnnotationCreationRequest(
        spec: TimeRangeAnchorSpec(startMs: 20000, endMs: 24000),
        title: '林埃标注',
        body: '这里的转折很清楚',
        createdBy: CardCreatedBy.i,
      ),
    );

    final library = await repository.listCards(
      const CardLibraryQuery(kinds: {CardKind.annotation}),
    );
    expect(library, hasLength(2));
    expect(library.map((record) => record.card.cardId),
        containsAll([user.card.cardId, linAi.card.cardId]));
    expect(user.card.ownerSpace, OwnerSpace.user);
    expect(linAi.card.ownerSpace, OwnerSpace.i);
    expect(linAi.card.createdBy, CardCreatedBy.i);
    expect(user.card.presentation['anchor'], user.anchor.toJson());

    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    final restarted = RepositoryVideoAnnotationStore(repository);
    final restored = await restarted.listAnnotations(
      sourceId: 'src_youtube_demo',
      currentVersionId: 'ver_youtube_demo_v1',
      currentDurationMs: 60000,
    );
    expect(restored, hasLength(2));
    expect(restored.every((item) => item.anchor.status == AnchorStatus.exact),
        isTrue);
    final restoredUser = restored.singleWhere(
      (item) => item.card.cardId == user.card.cardId,
    );
    expect(restoredUser.anchor.positionSpec['start_ms'], 10000);
    expect(restoredUser.anchor.positionSpec['end_ms'], 14000);
    expect(restoredUser.anchor.positionSpec['is_point'], isFalse);
  });

  for (final failurePoint in const [
    UnifiedCardRepositoryFaultPoint.annotationAfterMemoryCardInsert,
    UnifiedCardRepositoryFaultPoint.annotationAfterExtrasInsert,
  ]) {
    test('annotation transaction rolls back at ${failurePoint.name}', () async {
      var failOnce = true;
      final faultingRepository = UnifiedCardRepository(
        db: db,
        whiteboardRoot: root,
        faultInjector: (point) async {
          if (failOnce && point == failurePoint) {
            failOnce = false;
            throw StateError('injected annotation transaction failure');
          }
        },
      );
      final store = RepositoryVideoAnnotationStore(faultingRepository);
      const request = AnnotationCreationRequest(
        spec: TimeRangeAnchorSpec(startMs: 30000, endMs: 36000),
        title: '原子标注',
        body: '失败不应留卡',
      );

      await expectLater(
        store.createAnnotation(
          sourceId: 'src_youtube_demo',
          sourceVersionId: 'ver_youtube_demo_v1',
          request: request,
        ),
        throwsStateError,
      );
      expect(
        await faultingRepository.listCards(
          const CardLibraryQuery(kinds: {CardKind.annotation}),
        ),
        isEmpty,
      );
      expect(
        await faultingRepository.listCards(
          const CardLibraryQuery(
            kinds: {CardKind.annotation},
            includeDeleted: true,
          ),
        ),
        isEmpty,
      );

      await store.createAnnotation(
        sourceId: 'src_youtube_demo',
        sourceVersionId: 'ver_youtube_demo_v1',
        request: request,
      );
      final afterRetry = await faultingRepository.listCards(
        const CardLibraryQuery(
          kinds: {CardKind.annotation},
          includeDeleted: true,
        ),
      );
      expect(afterRetry, hasLength(1));
      expect(afterRetry.single.card.title, '原子标注');
    });
  }

  test('annotation entry rejects a mismatched summary', () async {
    final draft = VideoAnnotationService().createAnnotation(
      sourceId: 'src_youtube_demo',
      sourceVersionId: 'ver_youtube_demo_v1',
      request: const AnnotationCreationRequest(
        spec: TimeRangeAnchorSpec(startMs: 10000, endMs: 14000),
        title: '矛盾摘要',
      ),
    );
    await expectLater(
      repository.createVideoAnnotationCard(
        _completeAnnotationCard(draft, startMs: 10001),
      ),
      throwsArgumentError,
    );
    expect(
      await repository.listCards(
        const CardLibraryQuery(
          kinds: {CardKind.annotation},
          includeDeleted: true,
        ),
      ),
      isEmpty,
    );
  });

  test('annotation entry rejects an unknown SourceVersion', () async {
    final draft = VideoAnnotationService().createAnnotation(
      sourceId: 'src_youtube_demo',
      sourceVersionId: 'ver_youtube_demo_v1',
      request: const AnnotationCreationRequest(
        spec: TimeRangeAnchorSpec(startMs: 10000, endMs: 14000),
        title: '无效版本',
      ),
    );
    final invalidAnchor = AnchorContract.fromJson({
      ...draft.anchor.toJson(),
      'source_version_id': 'ver_missing',
    });
    await expectLater(
      repository.createVideoAnnotationCard(
        _completeAnnotationCard(draft, anchor: invalidAnchor),
      ),
      throwsStateError,
    );
    expect(
      await repository.listCards(
        const CardLibraryQuery(
          kinds: {CardKind.annotation},
          includeDeleted: true,
        ),
      ),
      isEmpty,
    );
  });

  test('video annotation entry rejects invalid time-range semantics', () async {
    final draft = VideoAnnotationService().createAnnotation(
      sourceId: 'src_youtube_demo',
      sourceVersionId: 'ver_youtube_demo_v1',
      request: const AnnotationCreationRequest(
        spec: TimeRangeAnchorSpec(startMs: 10000, endMs: 14000),
        title: '非法时间锚点',
      ),
    );
    final invalidAnchors = <AnchorContract>[
      AnchorContract.fromJson({
        ...draft.anchor.toJson(),
        'position_kind': 'text_range',
      }),
      AnchorContract.fromJson({
        ...draft.anchor.toJson(),
        'position_spec': {
          ...draft.anchor.positionSpec,
          'start_ms': -1,
        },
      }),
      AnchorContract.fromJson({
        ...draft.anchor.toJson(),
        'position_spec': {
          ...draft.anchor.positionSpec,
          'start_ms': 15000,
          'end_ms': 14000,
        },
      }),
      AnchorContract.fromJson({
        ...draft.anchor.toJson(),
        'position_spec': {
          ...draft.anchor.positionSpec,
          'is_point': true,
        },
      }),
    ];

    for (final anchor in invalidAnchors) {
      await expectLater(
        repository.createVideoAnnotationCard(
          _completeAnnotationCard(draft, anchor: anchor),
        ),
        throwsArgumentError,
      );
    }
    expect(
      await repository.listCards(
        const CardLibraryQuery(
          kinds: {CardKind.annotation},
          includeDeleted: true,
        ),
      ),
      isEmpty,
    );
  });

  test('fractional time range is rejected with zero card writes', () async {
    final memoryCountBefore = (await db.select(db.memoryCards).get()).length;
    final extrasCountBefore =
        (await db.select(db.whiteboardCardExtras).get()).length;
    final draft = VideoAnnotationService().createAnnotation(
      sourceId: 'src_youtube_demo',
      sourceVersionId: 'ver_youtube_demo_v1',
      request: const AnnotationCreationRequest(
        spec: TimeRangeAnchorSpec(startMs: 1, endMs: 2),
        title: '不得截断',
      ),
    );
    final fractionalAnchor = AnchorContract.fromJson({
      ...draft.anchor.toJson(),
      'position_spec': {
        'start_ms': 1.2,
        'end_ms': 1.8,
        'is_point': false,
      },
    });
    final card = CardContract(
      cardId: draft.card.cardId,
      cardKind: CardKind.annotation,
      sourceId: 'src_youtube_demo',
      ownerSpace: draft.card.ownerSpace,
      title: draft.card.title,
      body: draft.card.body,
      presentation: {
        'anchor': fractionalAnchor.toJson(),
        'anchor_id': fractionalAnchor.anchorId,
        'start_ms': 1.2,
        'end_ms': 1.8,
        'is_point': false,
      },
      createdBy: draft.card.createdBy,
      createdAt: draft.card.createdAt,
    );

    await expectLater(
      repository.createVideoAnnotationCard(card),
      throwsArgumentError,
    );
    expect(
      await repository.listCards(
        const CardLibraryQuery(
          kinds: {CardKind.annotation},
          includeDeleted: true,
        ),
      ),
      isEmpty,
    );
    expect(await db.select(db.memoryCards).get(), hasLength(memoryCountBefore));
    expect(
      await db.select(db.whiteboardCardExtras).get(),
      hasLength(extrasCountBefore),
    );
  });

  test('version changes orphan every range and preserve old version identity',
      () async {
    final store = RepositoryVideoAnnotationStore(repository);
    await store.createAnnotation(
      sourceId: 'src_youtube_demo',
      sourceVersionId: 'ver_youtube_demo_v1',
      request: const AnnotationCreationRequest(
        spec: TimeRangeAnchorSpec(startMs: 10000, endMs: 14000),
        title: '仍然有效',
      ),
    );
    await store.createAnnotation(
      sourceId: 'src_youtube_demo',
      sourceVersionId: 'ver_youtube_demo_v1',
      request: const AnnotationCreationRequest(
        spec: TimeRangeAnchorSpec(startMs: 80000, endMs: 90000),
        title: '超出新版时长',
      ),
    );
    await repository.commitIngestion(_videoIngestion(hash: 'v2'));

    final restored = await store.listAnnotations(
      sourceId: 'src_youtube_demo',
      currentVersionId: 'ver_youtube_demo_v2',
      currentDurationMs: 60000,
    );
    expect(
      restored.singleWhere((item) => item.card.title == '仍然有效').anchor.status,
      AnchorStatus.orphaned,
    );
    final orphan = restored.singleWhere((item) => item.card.title == '超出新版时长');
    expect(orphan.anchor.status, AnchorStatus.orphaned);
    expect(orphan.anchor.sourceVersionId, 'ver_youtube_demo_v1');
    expect(
      restored.every(
        (item) => item.anchor.sourceVersionId == 'ver_youtube_demo_v1',
      ),
      isTrue,
    );
  });
}

CardContract _completeAnnotationCard(
  VideoAnnotationResult draft, {
  AnchorContract? anchor,
  int? startMs,
}) {
  final effectiveAnchor = anchor ?? draft.anchor;
  return CardContract(
    cardId: draft.card.cardId,
    cardKind: CardKind.annotation,
    sourceId: draft.card.sourceId,
    ownerSpace: draft.card.ownerSpace,
    title: draft.card.title,
    body: draft.card.body,
    tags: draft.card.tags,
    presentation: {
      ...draft.card.presentation,
      'start_ms': startMs ?? effectiveAnchor.positionSpec['start_ms'],
      'end_ms': effectiveAnchor.positionSpec['end_ms'],
      'is_point': effectiveAnchor.positionSpec['is_point'],
      'anchor_id': effectiveAnchor.anchorId,
      'anchor': effectiveAnchor.toJson(),
    },
    createdBy: draft.card.createdBy,
    createdAt: draft.card.createdAt,
  );
}

IngestionResult _videoIngestion({required String hash}) {
  final now = DateTime.utc(2026, 8, 19, 12);
  final versionId = 'ver_youtube_demo_$hash';
  final source = SourceContent(
    sourceId: 'src_youtube_demo',
    mediaType: SourceMediaType.video,
    title: '真实视频来源',
    origin: SourceOrigin.externalLink,
    provider: 'youtube',
    canonicalId: 'dQw4w9WgXcQ',
    currentVersionId: versionId,
    contentHash: hash,
    objectRef: 'ingestion/src_youtube_demo/$versionId.json',
    metadata: const {
      'canonical_url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      'duration_ms': 60000,
    },
    createdAt: now,
    updatedAt: now,
  );
  return IngestionResult(
    canonicalUrl: source.metadata['canonical_url']! as String,
    provider: 'youtube',
    status: IngestionStatus.ok,
    source: source,
    sourceVersion: SourceVersion(
      versionId: versionId,
      sourceId: source.sourceId,
      contentHash: hash,
      objectRef: source.objectRef!,
      createdAt: now,
    ).toJson(),
    hasMedia: true,
    resolvedAt: now,
  );
}
