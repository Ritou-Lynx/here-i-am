import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/whiteboard/ingestion/link_ingestion_service.dart';
import 'package:memex/data/whiteboard/ingestion/ingestion_store.dart';
import 'package:memex/data/whiteboard/ingestion/safe_http_client.dart';
import 'package:memex/data/whiteboard/ingestion/link_ingestor.dart';
import 'package:memex/domain/whiteboard/source_content.dart';

/// Real public URL smoke test — skipped unless a network is available.
///
/// The W3 completion criteria require one *compliance* smoke test against a
/// real public URL, but the suite must pass without network. This test is
/// gated: it tries a quick TCP connect to example.com and skips itself if
/// unreachable.
void main() {
  test('smoke: ingests a real public URL when network is available',
      () async {
    final canReachNetwork = await _canReachNetwork();
    if (!canReachNetwork) {
      markTestSkipped('No network available — smoke test skipped');
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp('w3_smoke_');
    try {
      final store = IngestionStore(tempDir);
      final client = SafeHttpClient();
      final service = LinkIngestionService(
        store: store,
        ingestor: LinkIngestor(httpClient: client),
      );

      final outcome = await service.ingestUrl(
        'https://example.com/',
        createCard: true,
      );

      expect(outcome.succeeded, isTrue,
          reason: 'example.com should be fetchable: ${outcome.result.errorMessage}');
      expect(outcome.result.canonicalUrl, isNotEmpty);
      expect(outcome.result.source, isNotNull);
      expect(outcome.result.source!.mediaType, SourceMediaType.web);
      expect(outcome.card, isNotNull);
      expect(outcome.cardCreated, isTrue);

      // Idempotent re-import — no new version / card.
      final again = await service.ingestUrl('https://example.com/');
      expect(again.upsert!.versionIsNew, isFalse);
      expect(again.cardCreated, isFalse);

      // Restart recovery: fresh store reads persisted data.
      final store2 = IngestionStore(tempDir);
      final record = await store2.getRecord(outcome.result.source!.sourceId);
      expect(record, isNotNull);
      expect(record!.card, isNotNull);
    } finally {
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