import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/ingestion/link_ingestion_service.dart';
import 'package:memex/data/whiteboard/thumbnail/safe_thumbnail_resolver.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/rich_text_asset_ref.dart';
import 'package:memex/domain/whiteboard/rich_text_object_store.dart';
import 'package:memex/domain/whiteboard/source_content.dart';

/// Anonymous, single-note production smoke test.
///
/// It is deliberately environment-gated so no share token or user-supplied
/// URL is committed to the repository. The production service is used end to
/// end: public HTML -> exact-note evidence -> safe image download -> object
/// store -> Drift metadata -> restart recovery. No Cookie or WebView profile
/// is read.
void main() {
  test('smoke: public XHS note persists image evidence and limitations',
      () async {
    final url = Platform.environment['XHS_PUBLIC_SMOKE_URL'];
    if (url == null || url.trim().isEmpty) {
      markTestSkipped('Set XHS_PUBLIC_SMOKE_URL for the anonymous smoke test');
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp('w3_xhs_smoke_');
    final dbFile = File('${tempDir.path}/smoke.sqlite');
    AppDatabase? db;
    try {
      db = AppDatabase.forTesting(NativeDatabase(dbFile));
      final repository = UnifiedCardRepository(
        db: db,
        whiteboardRoot: tempDir,
        thumbnailResolver: SafeThumbnailResolver(whiteboardRoot: tempDir),
      );
      final service = LinkIngestionService(repository: repository);
      final outcome = await service.ingestUrl(url, createCard: true);

      expect(outcome.succeeded, isTrue,
          reason: outcome.result.errorMessage ?? 'XHS ingestion failed');
      expect(outcome.result.source?.mediaType, SourceMediaType.image);
      expect(outcome.card, isNotNull);
      expect(outcome.card!.presentation['thumbnail_ref'], isA<String>());
      final evidence = outcome.result.metadata['xhs_image_evidence'];
      expect(evidence, isA<List>());
      final stored = (evidence as List)
          .whereType<Map>()
          .where((item) => item['status'] == 'stored')
          .toList();
      expect(stored, isNotEmpty);
      final objectRef = stored.first['object_ref'] as String;
      final assetRef = RichTextAssetRef(
        refId: 'smoke',
        objectRef: objectRef,
        mimeType: stored.first['mime_type'] as String,
      );
      expect(RichTextObjectStore(tempDir).resolveFile(assetRef), isNotNull);
      expect(outcome.result.metadata['xhs_public_comments'], isA<List>());
      final capabilities =
          outcome.result.metadata['xhs_evidence_capabilities'] as Map;
      expect(capabilities['images'], 'stored');
      expect(
        capabilities['ocr'],
        anyOf('available', 'unavailable', 'failed'),
      );

      final sourceId = outcome.result.source!.sourceId;
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(dbFile));
      final restarted = LinkIngestionService(
        repository: UnifiedCardRepository(db: db, whiteboardRoot: tempDir),
      );
      final restored = await restarted.getSource(sourceId);
      expect(restored?.source.metadata['xhs_image_evidence'], isA<List>());
      expect(restored?.card, isNotNull);
      expect(restored?.card?.presentation['thumbnail_ref'], isA<String>());
    } finally {
      await db?.close();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    }
  });
}
