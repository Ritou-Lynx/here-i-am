import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/ingestion/ingestion_store.dart';
import 'package:memex/data/whiteboard/ingestion/link_ingestion_service.dart';
import 'package:memex/data/whiteboard/ingestion/link_ingestor.dart';
import 'package:memex/data/whiteboard/ingestion/safe_http_client.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/domain/whiteboard/source_content.dart';

String _fixture(String name) =>
    File('test/data/whiteboard/ingestion/fixtures/$name').readAsStringSync();

// ---------------------------------------------------------------------------
// Fake HTTP adapter for integration tests
// ---------------------------------------------------------------------------

class _FakeAdapter implements HttpClientAdapter {
  final Map<String, _Canned> responses;
  _FakeAdapter(this.responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    final url = options.path;
    final canned = responses[url];
    if (canned == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'No canned response for $url',
      );
    }
    return ResponseBody.fromString(
      canned.body,
      canned.statusCode,
      headers: {
        'content-type': [canned.contentType],
        if (canned.location != null) 'location': [canned.location!],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Canned {
  final String body;
  final int statusCode;
  final String contentType;
  final String? location;
  _Canned(this.body, this.statusCode, this.contentType, {this.location});
}

Dio _dio(Map<String, _Canned> responses) {
  return Dio(BaseOptions(
    followRedirects: false,
    validateStatus: (s) => s != null && s >= 200 && s < 400,
  ))..httpClientAdapter = _FakeAdapter(responses);
}

// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('w3_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  LinkIngestionService buildService(Map<String, _Canned> responses) {
    final store = IngestionStore(tempDir);
    final client = SafeHttpClient(
      dio: _dio(responses),
      config: const SafeHttpConfig(enforceDnsCheck: false),
    );
    final ingestor = LinkIngestor(httpClient: client);
    return LinkIngestionService(store: store, ingestor: ingestor);
  }

  group('LinkIngestor end-to-end', () {
    test('successful ingestion produces IngestionResult with source+version',
        () async {
      final svc = buildService({
        'https://example.com/doc': _Canned(
          _fixture('open_graph.html'), 200, 'text/html; charset=utf-8',
        ),
      });

      final outcome = await svc.ingestUrl('https://example.com/doc');

      expect(outcome.succeeded, isTrue);
      expect(outcome.result.status, IngestionStatus.ok);
      expect(outcome.result.source, isNotNull);
      expect(outcome.result.source!.mediaType, SourceMediaType.web);
      expect(outcome.result.source!.title, '春雨昼眠主题设计文档');
      expect(outcome.result.source!.provider, 'web');
      expect(outcome.result.sourceVersion, isNotNull);
      expect(outcome.result.hasBody, isTrue);
      expect(outcome.result.hasMedia, isTrue);
      expect(outcome.card, isNotNull);
      expect(outcome.cardCreated, isTrue);
    });

    test('failed URL returns failed status without throwing', () async {
      final svc = buildService({});

      final outcome = await svc.ingestUrl('https://example.com/missing');

      expect(outcome.succeeded, isFalse);
      expect(outcome.result.status, IngestionStatus.failed);
      expect(outcome.result.source, isNull);
      expect(outcome.card, isNull);
    });
  });

  group('De-duplication and versioning', () {
    test('re-importing same URL reuses Source and does not create new Card',
        () async {
      final responses = {
        'https://example.com/dup': _Canned(
          _fixture('duplicate_import.html'), 200, 'text/html',
        ),
      };
      final svc = buildService(responses);

      final first = await svc.ingestUrl('https://example.com/dup');
      final second = await svc.ingestUrl('https://example.com/dup');

      expect(first.succeeded, isTrue);
      expect(second.succeeded, isTrue);

      // Same source ID
      expect(second.result.source!.sourceId, first.result.source!.sourceId);

      // No new version
      expect(second.upsert!.versionIsNew, isFalse);

      // No new card
      expect(first.cardCreated, isTrue);
      expect(second.cardCreated, isFalse);
      expect(second.cardUpdated, isTrue);
      expect(second.card!.cardId, first.card!.cardId);

      // Only one card in store
      final cards = await svc.listCards();
      expect(cards.length, 1);
    });

    test('changed content creates new SourceVersion, same Card', () async {
      var body = _fixture('duplicate_import.html');
      final responses = <String, _Canned>{
        'https://example.com/dup': _Canned(body, 200, 'text/html'),
      };
      final svc = buildService(responses);

      final first = await svc.ingestUrl('https://example.com/dup');

      // Swap the canned response to updated content.
      responses['https://example.com/dup'] =
          _Canned(_fixture('updated_content.html'), 200, 'text/html');

      final second = await svc.ingestUrl('https://example.com/dup');

      expect(first.succeeded, isTrue);
      expect(second.succeeded, isTrue);

      // New version
      expect(second.upsert!.versionIsNew, isTrue);

      // Same source
      expect(second.result.source!.sourceId, first.result.source!.sourceId);

      // Different version id
      expect(second.upsert!.version.versionId,
          isNot(first.upsert!.version.versionId));

      // Card reused (not created)
      expect(second.cardCreated, isFalse);
      expect(second.card!.cardId, first.card!.cardId);

      // Source has 2 versions
      final record = await svc.getSource(first.result.source!.sourceId);
      expect(record, isNotNull);
      expect(record!.versions.length, 2);
    });
  });

  group('Redirect handling', () {
    test('canonical URL updated after redirect', () async {
      final svc = buildService({
        'https://example.com/old': _Canned(
          '', 302, 'text/html',
          location: 'https://cdn.example.com/new',
        ),
        'https://cdn.example.com/new': _Canned(
          _fixture('redirect_target.html'), 200, 'text/html',
        ),
      });

      final outcome = await svc.ingestUrl('https://example.com/old');

      expect(outcome.succeeded, isTrue);
      expect(outcome.result.canonicalUrl, 'https://cdn.example.com/new');
      expect(outcome.result.source, isNotNull);
      expect(outcome.result.source!.metadata['canonical_url'],
          'https://cdn.example.com/new');
    });
  });

  group('Restart recovery', () {
    test('data persists across store instances', () async {
      final responses = {
        'https://example.com/doc': _Canned(
          _fixture('open_graph.html'), 200, 'text/html',
        ),
      };

      // First instance ingests.
      final store1 = IngestionStore(tempDir);
      final client1 = SafeHttpClient(
        dio: _dio(responses),
        config: const SafeHttpConfig(enforceDnsCheck: false),
      );
      final svc1 = LinkIngestionService(
          store: store1, ingestor: LinkIngestor(httpClient: client1));
      final outcome = await svc1.ingestUrl('https://example.com/doc');
      expect(outcome.succeeded, isTrue);
      final sourceId = outcome.result.source!.sourceId;
      final cardId = outcome.card!.cardId;

      // Second instance reads from the same directory.
      final store2 = IngestionStore(tempDir);
      final record = await store2.getRecord(sourceId);
      expect(record, isNotNull);
      expect(record!.source.title, '春雨昼眠主题设计文档');
      expect(record.versions.length, 1);
      expect(record.card, isNotNull);
      expect(record.card!.cardId, cardId);

      final cards = await store2.listCards();
      expect(cards.length, 1);
      expect(cards.first.cardId, cardId);
      expect(cards.first.sourceId, sourceId);
    });

    test('re-import after restart deduplicates', () async {
      final responses = {
        'https://example.com/dup': _Canned(
          _fixture('duplicate_import.html'), 200, 'text/html',
        ),
      };

      // First session.
      final svc1 = buildService(responses);
      final first = await svc1.ingestUrl('https://example.com/dup');
      expect(first.cardCreated, isTrue);

      // Second session with a fresh store pointing at the same dir.
      final store2 = IngestionStore(tempDir);
      final client2 = SafeHttpClient(
        dio: _dio(responses),
        config: const SafeHttpConfig(enforceDnsCheck: false),
      );
      final svc2 = LinkIngestionService(
          store: store2, ingestor: LinkIngestor(httpClient: client2));
      final second = await svc2.ingestUrl('https://example.com/dup');

      expect(second.upsert!.versionIsNew, isFalse);
      expect(second.cardCreated, isFalse);
      expect(second.card!.cardId, first.card!.cardId);

      final cards = await svc2.listCards();
      expect(cards.length, 1);
    });
  });

  group('createCard=false', () {
    test('persists source without creating a card', () async {
      final svc = buildService({
        'https://example.com/doc': _Canned(
          _fixture('open_graph.html'), 200, 'text/html',
        ),
      });

      final outcome = await svc.ingestUrl(
        'https://example.com/doc',
        createCard: false,
      );

      expect(outcome.succeeded, isTrue);
      expect(outcome.card, isNull);
      expect(outcome.cardCreated, isFalse);

      final cards = await svc.listCards();
      expect(cards, isEmpty);
    });
  });

  group('Error MIME and parse failure', () {
    test('wrong MIME type produces failed result', () async {
      final svc = buildService({
        'https://example.com/img': _Canned('binary', 200, 'image/png'),
      });

      final outcome = await svc.ingestUrl('https://example.com/img');

      expect(outcome.succeeded, isFalse);
      expect(outcome.result.status, IngestionStatus.failed);
      expect(outcome.result.errorMessage, contains('MIME'));
    });

    test('empty/garbage HTML produces failed result', () async {
      final svc = buildService({
        'https://example.com/empty': _Canned('', 200, 'text/html'),
      });

      final outcome = await svc.ingestUrl('https://example.com/empty');

      expect(outcome.succeeded, isFalse);
      expect(outcome.result.status, IngestionStatus.failed);
    });
  });

  group('Card contract integrity', () {
    test('created card references source_id and is kind=source', () async {
      final svc = buildService({
        'https://example.com/doc': _Canned(
          _fixture('open_graph.html'), 200, 'text/html',
        ),
      });

      final outcome = await svc.ingestUrl('https://example.com/doc');
      final card = outcome.card!;

      expect(card.cardKind, CardKind.source);
      expect(card.sourceId, outcome.result.source!.sourceId);
      expect(card.title, outcome.result.source!.title);
      expect(card.presentation['thumbnail'],
          'https://example.com/images/spring-rain.png');
    });
  });
}