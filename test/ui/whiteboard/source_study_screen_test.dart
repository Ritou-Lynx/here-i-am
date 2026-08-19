import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/ui/whiteboard/source_study_screen.dart';
import 'package:memex/ui/whiteboard/video/video_study_screen.dart';

void main() {
  late Directory root;
  late AppDatabase db;
  late UnifiedCardRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('f4_source_screen_');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
  });

  tearDown(() async {
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('ordinary source renders repository body metadata and version',
      (tester) async {
    repository = _StaticSourceRepository(
      db: db,
      root: root,
      source: _source(video: false),
      card: _card(video: false),
      object: const SourceObjectRecord(
        state: SourceObjectState.available,
        payload: {
          'body_text': '这是 Repository 对象中的完整正文。',
          'metadata': {'description': '真实描述'},
        },
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: SourceStudyScreen(
        sourceId: 'src_web_product',
        repository: repository,
      ),
    ));
    await _pumpSource(tester);

    expect(find.text('真实网页标题'), findsOneWidget);
    expect(find.textContaining('这是 Repository 对象中的完整正文'), findsOneWidget);
    expect(find.textContaining('正文对象可用'), findsOneWidget);
    expect(find.textContaining('example.com'), findsWidgets);
  });

  testWidgets('video source enters real provider path and never Fixture Player',
      (tester) async {
    repository = _StaticSourceRepository(
      db: db,
      root: root,
      source: _source(video: true),
      card: _card(video: true),
    );
    await tester.pumpWidget(MaterialApp(
      home: SourceStudyScreen(
        sourceId: 'src_youtube_product',
        repository: repository,
      ),
    ));
    await _pumpSource(tester);

    expect(find.byType(VideoStudyScreen), findsOneWidget);
    expect(find.text('Fixture Player'), findsNothing);
    expect(find.text('此平台不支持研读播放'), findsOneWidget,
        reason: 'VM tests run as native Windows, which has no embedded player');
  });

  testWidgets('missing source is an honest unavailable state', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SourceStudyScreen(
        sourceId: 'src_missing',
        repository: repository,
      ),
    ));
    await _pumpSource(tester);
    expect(find.text('找不到这个来源'), findsOneWidget);
    expect(find.text('src_missing'), findsOneWidget);
  });
}

Future<void> _pumpSource(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

SourceContent _source({required bool video}) {
  final now = DateTime.utc(2026, 8, 19, 12);
  final sourceId = video ? 'src_youtube_product' : 'src_web_product';
  final versionId = video ? 'ver_youtube_product_v1' : 'ver_web_product_v1';
  final canonical = video
      ? 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'
      : 'https://example.com/article';
  return SourceContent(
    sourceId: sourceId,
    mediaType: video ? SourceMediaType.video : SourceMediaType.web,
    title: video ? '真实视频标题' : '真实网页标题',
    origin: SourceOrigin.externalLink,
    provider: video ? 'youtube' : 'web',
    canonicalId: video ? 'dQw4w9WgXcQ' : null,
    currentVersionId: versionId,
    contentHash: 'v1',
    objectRef: 'ingestion/$sourceId/$versionId.json',
    metadata: {
      'canonical_url': canonical,
      if (!video) 'site_name': 'example.com',
      if (!video) 'description': '真实描述',
    },
    createdAt: now,
    updatedAt: now,
  );
}

CardContract _card({required bool video}) {
  final now = DateTime.utc(2026, 8, 19, 12);
  return CardContract(
    cardId: video ? 'card_youtube_product' : 'card_web_product',
    cardKind: CardKind.source,
    sourceId: video ? 'src_youtube_product' : 'src_web_product',
    title: video ? '真实视频标题' : '真实网页标题',
    body: video ? '' : '完整正文摘要',
    createdAt: now,
  );
}

class _StaticSourceRepository extends UnifiedCardRepository {
  _StaticSourceRepository({
    required super.db,
    required Directory root,
    required this.source,
    required this.card,
    this.object,
  }) : super(whiteboardRoot: root);

  final SourceContent source;
  final CardContract card;
  final SourceObjectRecord? object;

  SourceVersion get version => SourceVersion(
        versionId: source.currentVersionId!,
        sourceId: source.sourceId,
        contentHash: source.contentHash!,
        objectRef: 'objects/sources/${source.sourceId}/version.json',
        createdAt: source.createdAt,
      );

  @override
  Future<SourceContent?> getSource(String sourceId) async =>
      sourceId == source.sourceId ? source : null;

  @override
  Future<List<SourceVersion>> listSourceVersions(String sourceId) async =>
      sourceId == source.sourceId ? [version] : const [];

  @override
  Future<CardContract?> getCardForSource(String sourceId) async =>
      sourceId == source.sourceId ? card : null;

  @override
  Future<SourceObjectRecord> getSourceObject(SourceVersion version) async =>
      object ?? const SourceObjectRecord(state: SourceObjectState.missing);
}
