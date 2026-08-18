import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/whiteboard/ingestion/link_ingestion_service.dart';
import 'package:memex/data/whiteboard/ingestion/safe_http_client.dart';
import 'package:memex/data/whiteboard/ingestion/link_ingestor.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/source_content.dart';

/// Real public URL smoke test — skipped unless a network is available.
///
/// The W3 completion criteria require one *compliance* smoke test against a
/// real public URL, but the suite must pass without network. This test is
/// gated: it tries a quick TCP connect to example.com and skips itself if
/// unreachable.
void main() {
  test('smoke: ingests a real public URL when network is available', () async {
    final canReachNetwork = await _canReachNetwork();
    if (!canReachNetwork) {
      markTestSkipped('No network available — smoke test skipped');
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp('w3_smoke_');
    AppDatabase? db;
    try {
      final dbFile = File('${tempDir.path}/smoke.sqlite');
      db = AppDatabase.forTesting(NativeDatabase(dbFile));
      final repository = UnifiedCardRepository(
        db: db,
        whiteboardRoot: tempDir,
      );
      final client = SafeHttpClient();
      final service = LinkIngestionService(
        repository: repository,
        ingestor: LinkIngestor(httpClient: client),
      );

      final outcome = await service.ingestUrl(
        'https://example.com/',
        createCard: true,
      );

      expect(outcome.succeeded, isTrue,
          reason:
              'example.com should be fetchable: ${outcome.result.errorMessage}');
      expect(outcome.result.canonicalUrl, isNotEmpty);
      expect(outcome.result.source, isNotNull);
      expect(outcome.result.source!.mediaType, SourceMediaType.web);
      expect(outcome.card, isNotNull);
      expect(outcome.cardCreated, isTrue);

      // Idempotent re-import — no new version / card.
      final again = await service.ingestUrl(
        'https://example.com/',
        createCard: true,
      );
      expect(again.upsert!.versionIsNew, isFalse);
      expect(again.cardCreated, isFalse);

      // Restart recovery: fresh connection reads the same temporary DB.
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(dbFile));
      final service2 = LinkIngestionService(
        repository: UnifiedCardRepository(
          db: db,
          whiteboardRoot: tempDir,
        ),
      );
      final record = await service2.getSource(outcome.result.source!.sourceId);
      expect(record, isNotNull);
      expect(record!.card, isNotNull);
    } finally {
      await db?.close();
      await tempDir.delete(recursive: true);
    }
  });
}

Future<bool> _canReachNetwork() async {
  try {
    final socket = await Socket.connect('example.com', 80,
        timeout: const Duration(seconds: 3));
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}
