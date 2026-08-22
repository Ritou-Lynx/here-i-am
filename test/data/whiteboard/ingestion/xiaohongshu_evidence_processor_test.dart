import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/services/reading/ocr_recognizer.dart';
import 'package:memex/data/whiteboard/ingestion/link_ingestion_service.dart';
import 'package:memex/data/whiteboard/ingestion/link_ingestor.dart';
import 'package:memex/data/whiteboard/ingestion/safe_http_client.dart';
import 'package:memex/data/whiteboard/ingestion/xiaohongshu_evidence_processor.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/domain/whiteboard/rich_text_asset_ref.dart';
import 'package:memex/domain/whiteboard/rich_text_object_store.dart';
import 'package:memex/domain/whiteboard/source_content.dart';

class _Response {
  const _Response(this.bytes, this.mimeType);
  final Uint8List bytes;
  final String mimeType;
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.responses);
  final Map<String, _Response> responses;
  final List<String> requested = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    requested.add(options.path);
    final response = responses[options.path];
    if (response == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'No fixture for ${options.path}',
      );
    }
    return ResponseBody(
      Stream.value(response.bytes),
      200,
      headers: {
        'content-type': [response.mimeType],
        'content-length': [response.bytes.length.toString()],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FixtureRecognizer implements OcrRecognizer {
  const _FixtureRecognizer(this.result);
  final OcrRecognition result;

  @override
  Future<OcrRecognition> recognize(String imagePath) async {
    expect(File(imagePath).existsSync(), isTrue);
    return result;
  }
}

SafeHttpClient _client(
  Map<String, _Response> responses, {
  SafeHttpConfig config = const SafeHttpConfig(
    enforceDnsCheck: false,
    allowedMimePrefixes: {'image/'},
  ),
  _Adapter? adapter,
}) {
  final dio = Dio()..httpClientAdapter = adapter ?? _Adapter(responses);
  return SafeHttpClient(dio: dio, config: config);
}

Uint8List _png({int width = 2, int height = 3, int trailingBytes = 0}) {
  final bytes = Uint8List(24 + trailingBytes);
  bytes.setAll(0, const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  bytes[16] = (width >> 24) & 0xff;
  bytes[17] = (width >> 16) & 0xff;
  bytes[18] = (width >> 8) & 0xff;
  bytes[19] = width & 0xff;
  bytes[20] = (height >> 24) & 0xff;
  bytes[21] = (height >> 16) & 0xff;
  bytes[22] = (height >> 8) & 0xff;
  bytes[23] = height & 0xff;
  return bytes;
}

IngestionResult _imageResult(String url) {
  final now = DateTime.utc(2026, 8, 23, 1, 2, 3);
  final source = SourceContent(
    sourceId: 'src_xiaohongshu_note',
    mediaType: SourceMediaType.image,
    title: '笔记',
    provider: 'xiaohongshu',
    canonicalId: 'note',
    currentVersionId: 'ver_xiaohongshu_note_hash',
    contentHash: 'hash',
    objectRef: 'ingestion/note.html',
    metadata: const {
      'canonical_url': 'https://www.xiaohongshu.com/explore/note',
    },
    createdAt: now,
  );
  return IngestionResult(
    canonicalUrl: 'https://www.xiaohongshu.com/explore/note',
    provider: 'xiaohongshu',
    status: IngestionStatus.ok,
    source: source,
    sourceVersion: {
      'version_id': 'ver_xiaohongshu_note_hash',
      'source_id': source.sourceId,
      'content_hash': 'hash',
      'object_ref': 'ingestion/note.html',
      'parser_version': 'w3-html-parser-v1',
      'created_at': now.toIso8601String(),
    },
    hasMedia: true,
    metadata: {
      'xhs_note_kind': 'image',
      'xhs_parser_version': 'xhs-public-evidence-v1',
      'xhs_media_candidates': [
        {'original_url': url, 'order': 0, 'source': 'image_urls'},
      ],
    },
    resolvedAt: now,
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('xhs_evidence_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('stores content-addressed image and fixture OCR evidence', () async {
    final bytes = _png();
    final processor = XiaohongshuEvidenceProcessor(
      objectStore: RichTextObjectStore(tempDir),
      imageClient: _client({
        'https://sns-img.example/1.png': _Response(bytes, 'image/png'),
      }),
      recognizer: const _FixtureRecognizer(
        OcrRecognition(
          availability: OcrAvailability.available,
          text: '图中文字',
          confidence: 0.91,
          recognizerVersion: 'fixture-v1',
        ),
      ),
      clock: () => DateTime.utc(2026, 8, 23, 2),
    );

    final result = await processor.process(
      _imageResult('https://sns-img.example/1.png'),
    );
    final evidence =
        (result.metadata['xhs_image_evidence'] as List).single as Map;
    expect(evidence['status'], 'stored');
    expect(evidence['original_url'], 'https://sns-img.example/1.png');
    expect(evidence['mime_type'], 'image/png');
    expect(evidence['order'], 0);
    expect(evidence['width'], 2);
    expect(evidence['height'], 3);
    expect(evidence['parser_version'], 'xhs-public-evidence-v1');
    final ocr = evidence['ocr'] as Map;
    expect(ocr['status'], 'available');
    expect(ocr['text'], '图中文字');
    expect(ocr['confidence'], 0.91);
    expect(ocr['derived_from_object_ref'], evidence['object_ref']);

    final objectRef = evidence['object_ref'] as String;
    expect(objectRef, matches(RegExp(r'^objects/[0-9a-f]{64}\.png$')));
    final restarted = RichTextObjectStore(tempDir);
    expect(
      restarted.resolveFile(
        RichTextAssetRef(
          refId: 'test',
          objectRef: objectRef,
          mimeType: 'image/png',
        ),
      ),
      isNotNull,
    );
  });

  test(
    'records explicit OCR unavailable without losing original image',
    () async {
      final processor = XiaohongshuEvidenceProcessor(
        objectStore: RichTextObjectStore(tempDir),
        imageClient: _client({
          'https://sns-img.example/1.png': _Response(_png(), 'image/png'),
        }),
        recognizer: const _FixtureRecognizer(
          OcrRecognition.unavailable(
            reason: 'fixture platform has no OCR',
            recognizerVersion: 'fixture-none',
          ),
        ),
      );
      final result = await processor.process(
        _imageResult('https://sns-img.example/1.png'),
      );
      final evidence =
          (result.metadata['xhs_image_evidence'] as List).single as Map;
      expect(evidence['status'], 'stored');
      expect((evidence['ocr'] as Map)['status'], 'unavailable');
      expect((evidence['ocr'] as Map)['text'], '');
    },
  );

  test(
    'SSRF, MIME, byte and pixel policies fail closed with evidence',
    () async {
      Future<Map> run(
        String url,
        SafeHttpClient client, {
        int maxPixels = 40 * 1000 * 1000,
      }) async {
        final result = await XiaohongshuEvidenceProcessor(
          objectStore: RichTextObjectStore(tempDir),
          imageClient: client,
          recognizer: const _FixtureRecognizer(OcrRecognition.unavailable()),
          maxImagePixels: maxPixels,
        ).process(_imageResult(url));
        return (result.metadata['xhs_image_evidence'] as List).single as Map;
      }

      final ssrf = await run('http://127.0.0.1/private.png', SafeHttpClient());
      expect(ssrf['status'], 'rejected');
      expect(ssrf['failure'], contains('SSRF blocked'));

      final mime = await run(
        'https://sns-img.example/not-image',
        _client(
          {'https://sns-img.example/not-image': _Response(_png(), 'text/html')},
          config: const SafeHttpConfig(
            enforceDnsCheck: false,
            allowedMimePrefixes: {'image/'},
          ),
        ),
      );
      expect(mime['failure'], contains('Unsupported MIME'));

      final bytes = await run(
        'https://sns-img.example/large.png',
        _client(
          {
            'https://sns-img.example/large.png': _Response(
              _png(trailingBytes: 20),
              'image/png',
            ),
          },
          config: const SafeHttpConfig(
            enforceDnsCheck: false,
            maxBodyBytes: 24,
            allowedMimePrefixes: {'image/'},
          ),
        ),
      );
      expect(bytes['failure'], contains('exceeds max size'));

      final pixels = await run(
        'https://sns-img.example/pixels.png',
        _client(
          {
            'https://sns-img.example/pixels.png': _Response(
              _png(width: 100, height: 100),
              'image/png',
            ),
          },
          config: const SafeHttpConfig(
            enforceDnsCheck: false,
            allowedMimePrefixes: {'image/'},
          ),
        ),
        maxPixels: 100,
      );
      expect(pixels['failure'], contains('pixel limit'));
      expect(Directory('${tempDir.path}/objects').existsSync(), isFalse);
    },
  );

  test(
    'commit persists public comments, image and OCR evidence across restart',
    () async {
      final html = File(
        'test/data/whiteboard/ingestion/fixtures/xiaohongshu_public_image_note.html',
      ).readAsBytesSync();
      final pageClient = _client(
        {
          'https://www.xiaohongshu.com/explore/public-note': _Response(
            html,
            'text/html',
          ),
        },
        config: const SafeHttpConfig(
          enforceDnsCheck: false,
          allowedMimePrefixes: {'text/html'},
        ),
      );
      final imageClient = _client({
        'https://sns-img.example/first.png': _Response(_png(), 'image/png'),
        'https://sns-img.example/cover.png': _Response(_png(), 'image/png'),
      });
      final dbFile = File('${tempDir.path}/cards.sqlite');
      var db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(() async {
        try {
          await db.close();
        } catch (_) {}
      });
      var repository = UnifiedCardRepository(db: db, whiteboardRoot: tempDir);
      var service = LinkIngestionService(
        repository: repository,
        ingestor: LinkIngestor(httpClient: pageClient),
        xiaohongshuEvidenceProcessor: XiaohongshuEvidenceProcessor(
          objectStore: RichTextObjectStore(tempDir),
          imageClient: imageClient,
          recognizer: const _FixtureRecognizer(
            OcrRecognition(
              availability: OcrAvailability.available,
              text: '可搜索文字',
              confidence: 0.8,
              recognizerVersion: 'fixture-v1',
            ),
          ),
        ),
      );

      final preview = await service.ingestUrl(
        'https://www.xiaohongshu.com/explore/public-note',
      );
      expect(preview.result.status, IngestionStatus.ok);
      expect(preview.result.metadata['xhs_public_access'], 'anonymous');
      expect(Directory('${tempDir.path}/objects').existsSync(), isFalse);
      final committed = await service.commitResult(preview.result);
      final sourceId = committed.result.source!.sourceId;
      expect(committed.cardCreated, isTrue);

      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(dbFile));
      repository = UnifiedCardRepository(db: db, whiteboardRoot: tempDir);
      service = LinkIngestionService(
        repository: repository,
        ingestor: LinkIngestor(httpClient: pageClient),
      );
      final restored = await service.getSource(sourceId);
      final comments = restored!.source.metadata['xhs_public_comments'] as List;
      final images = restored.source.metadata['xhs_image_evidence'] as List;
      expect(comments, hasLength(2));
      expect((comments.first as Map)['author'], '小雨');
      expect(
        (comments.first as Map)['source_url'],
        'https://www.xiaohongshu.com/explore/public-note',
      );
      expect((images.first as Map)['object_ref'], isNotEmpty);
      expect(((images.first as Map)['ocr'] as Map)['text'], '可搜索文字');
      await db.close();
    },
  );

  test(
    'video note records link-only capability and never requests stream',
    () async {
      final html = File(
        'test/data/whiteboard/ingestion/fixtures/xiaohongshu_public_video_note.html',
      ).readAsBytesSync();
      final pageClient = _client(
        {
          'https://www.xiaohongshu.com/explore/video-note': _Response(
            html,
            'text/html',
          ),
        },
        config: const SafeHttpConfig(
          enforceDnsCheck: false,
          allowedMimePrefixes: {'text/html'},
        ),
      );
      final imageAdapter = _Adapter(const {});
      final processor = XiaohongshuEvidenceProcessor(
        objectStore: RichTextObjectStore(tempDir),
        imageClient: _client(const {}, adapter: imageAdapter),
        recognizer: const _FixtureRecognizer(OcrRecognition.unavailable()),
      );
      final preview = await LinkIngestor(
        httpClient: pageClient,
      ).ingest('https://www.xiaohongshu.com/explore/video-note');
      final result = await processor.process(preview);

      expect(result.source!.mediaType, SourceMediaType.video);
      expect(result.videoCapability, VideoCapabilityLevel.linkOnly);
      expect(result.metadata['playback_capability'], 'link_only');
      expect(
        (result.metadata['xhs_media_evidence'] as Map)['stream_extraction'],
        'not_attempted',
      );
      expect(imageAdapter.requested, isEmpty);
    },
  );
}
