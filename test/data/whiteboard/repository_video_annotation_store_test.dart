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
  });

  test('version changes re-anchor valid ranges and orphan invalid ranges',
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
      AnchorStatus.reanchored,
    );
    final orphan = restored.singleWhere((item) => item.card.title == '超出新版时长');
    expect(orphan.anchor.status, AnchorStatus.orphaned);
    expect(orphan.anchor.sourceVersionId, 'ver_youtube_demo_v1');
  });
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
