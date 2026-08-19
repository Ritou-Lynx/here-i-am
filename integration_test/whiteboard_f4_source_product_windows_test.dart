import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/ui/whiteboard/source_study_screen.dart';
import 'package:memex/ui/whiteboard/video/video_study_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows product Source route uses repository data honestly',
      (tester) async {
    final root = await Directory.systemTemp.createTemp('f4_windows_product_');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    addTearDown(() async {
      await db.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    await repository.commitIngestion(_webIngestion());
    await tester.pumpWidget(MaterialApp(
      home: SourceStudyScreen(
        sourceId: 'src_windows_article',
        repository: repository,
      ),
    ));
    await _settleSource(tester);
    expect(find.text('Windows 来源窗口验证'), findsOneWidget);
    expect(find.textContaining('真实 SourceVersion 正文'), findsOneWidget);

    await repository.commitIngestion(_videoIngestion());
    await tester.pumpWidget(MaterialApp(
      home: SourceStudyScreen(
        sourceId: 'src_windows_youtube',
        repository: repository,
      ),
    ));
    await _settleSource(tester);
    expect(find.byType(VideoStudyScreen), findsOneWidget);
    expect(find.text('Fixture Player'), findsNothing);
    expect(find.text('此平台不支持研读播放'), findsOneWidget);
  });
}

Future<void> _settleSource(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

IngestionResult _webIngestion() {
  final now = DateTime.utc(2026, 8, 19, 12);
  const sourceId = 'src_windows_article';
  const versionId = 'ver_windows_article_v1';
  final source = SourceContent(
    sourceId: sourceId,
    mediaType: SourceMediaType.web,
    title: 'Windows 来源窗口验证',
    origin: SourceOrigin.externalLink,
    provider: 'web',
    currentVersionId: versionId,
    contentHash: 'web-v1',
    objectRef: 'ingestion/$sourceId/$versionId.json',
    metadata: const {
      'canonical_url': 'https://example.com/windows-source',
      'site_name': 'example.com',
    },
    createdAt: now,
    updatedAt: now,
  );
  return IngestionResult(
    canonicalUrl: source.metadata['canonical_url']! as String,
    provider: 'web',
    source: source,
    sourceVersion: SourceVersion(
      versionId: versionId,
      sourceId: sourceId,
      contentHash: 'web-v1',
      objectRef: source.objectRef!,
      createdAt: now,
    ).toJson(),
    hasBody: true,
    metadata: const {'body_text': '来自真实 SourceVersion 正文对象。'},
    resolvedAt: now,
  );
}

IngestionResult _videoIngestion() {
  final now = DateTime.utc(2026, 8, 19, 12);
  const sourceId = 'src_windows_youtube';
  const versionId = 'ver_windows_youtube_v1';
  final source = SourceContent(
    sourceId: sourceId,
    mediaType: SourceMediaType.video,
    title: 'Windows YouTube 来源',
    origin: SourceOrigin.externalLink,
    provider: 'youtube',
    canonicalId: 'M7lc1UVf-VE',
    currentVersionId: versionId,
    contentHash: 'video-v1',
    objectRef: 'ingestion/$sourceId/$versionId.json',
    metadata: const {
      'canonical_url': 'https://www.youtube.com/watch?v=M7lc1UVf-VE',
      'duration_ms': 120000,
    },
    createdAt: now,
    updatedAt: now,
  );
  return IngestionResult(
    canonicalUrl: source.metadata['canonical_url']! as String,
    provider: 'youtube',
    source: source,
    sourceVersion: SourceVersion(
      versionId: versionId,
      sourceId: sourceId,
      contentHash: 'video-v1',
      objectRef: source.objectRef!,
      createdAt: now,
    ).toJson(),
    hasMedia: true,
    resolvedAt: now,
  );
}
