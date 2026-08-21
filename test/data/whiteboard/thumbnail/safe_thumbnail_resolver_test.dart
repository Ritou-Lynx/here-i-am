import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:memex/data/whiteboard/ingestion/safe_http_client.dart';
import 'package:memex/data/whiteboard/thumbnail/safe_thumbnail_resolver.dart';

class _BinaryAdapter implements HttpClientAdapter {
  _BinaryAdapter(this.responses, {this.gate});

  final Map<String, _BinaryResponse> responses;
  final Completer<void>? gate;
  int calls = 0;
  int activeCalls = 0;
  int maxActiveCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    calls++;
    activeCalls++;
    if (activeCalls > maxActiveCalls) maxActiveCalls = activeCalls;
    try {
      await gate?.future;
      final response = responses[options.path];
      if (response == null) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'No canned response for ${options.path}',
        );
      }
      return ResponseBody(
        Stream.value(response.bytes),
        200,
        headers: {
          'content-type': [response.mimeType],
          'content-length': ['${response.bytes.length}'],
        },
      );
    } finally {
      activeCalls--;
    }
  }

  @override
  void close({bool force = false}) {}
}

class _BinaryResponse {
  const _BinaryResponse(
    this.bytes, {
    this.mimeType = 'image/png',
  });

  final Uint8List bytes;
  final String mimeType;
}

SafeHttpClient _client(_BinaryAdapter adapter) {
  final dio = Dio(BaseOptions(
    followRedirects: false,
    validateStatus: (s) => s != null && s >= 200 && s < 400,
  ))
    ..httpClientAdapter = adapter;
  return SafeHttpClient(
    dio: dio,
    config: SafeThumbnailResolver.httpConfig.copyWith(
      enforceDnsCheck: false,
    ),
  );
}

Uint8List _png({
  int width = 40,
  int height = 24,
  img.Color? color,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: color ?? img.ColorRgb8(67, 89, 59));
  return img.encodePng(image);
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('safe_thumbnail_test_');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('downloads, decodes, transcodes and resolves a content-addressed PNG',
      () async {
    final adapter = _BinaryAdapter({
      'https://example.com/cover.png': _BinaryResponse(_png()),
    });
    final resolver = SafeThumbnailResolver(
      whiteboardRoot: root,
      httpClient: _client(adapter),
    );
    const request = ThumbnailResolveRequest(
      sourceId: 'src_cover',
      sourceVersionId: 'ver_cover_v1',
      candidateUrl: 'https://example.com/cover.png',
      canonicalUrl: 'https://example.com/article',
    );

    final resolved = await resolver.resolve(request);

    expect(resolved.status, ThumbnailResolveStatus.available);
    expect(resolved.objectRef,
        matches(RegExp(r'^objects/thumbnails/[0-9a-f]{64}\.png$')));
    expect(resolved.file, isNotNull);
    expect(await resolved.file!.exists(), isTrue);
    expect(resolved.width, 40);
    expect(resolved.height, 24);
    expect(resolved.mimeType, 'image/png');
    expect(adapter.calls, 1);

    final cached = await resolver.resolve(ThumbnailResolveRequest(
      sourceId: request.sourceId,
      sourceVersionId: request.sourceVersionId,
      candidateUrl: request.candidateUrl,
      canonicalUrl: request.canonicalUrl,
      cachedObjectRef: resolved.objectRef,
      cachedVersionId: request.sourceVersionId,
      cachedCandidateHash: resolved.candidateHash,
    ));
    expect(cached.status, ThumbnailResolveStatus.available);
    expect(cached.objectRef, resolved.objectRef);
    expect(adapter.calls, 1, reason: 'valid restart cache must not refetch');
  });

  test('concurrent identical requests share one network fetch', () async {
    final adapter = _BinaryAdapter({
      'https://example.com/shared.png': _BinaryResponse(_png()),
    });
    final resolver = SafeThumbnailResolver(
      whiteboardRoot: root,
      httpClient: _client(adapter),
    );
    const request = ThumbnailResolveRequest(
      sourceId: 'src_shared',
      sourceVersionId: 'ver_shared_v1',
      candidateUrl: 'https://example.com/shared.png',
      canonicalUrl: 'https://example.com/article',
    );

    final results = await Future.wait([
      resolver.resolve(request),
      resolver.resolve(request),
      resolver.resolve(request),
    ]);

    expect(results.every((item) => item.isAvailable), isTrue);
    expect(adapter.calls, 1);
  });

  test('distinct candidates queue before fetch and decode work begins',
      () async {
    final gate = Completer<void>();
    final adapter = _BinaryAdapter(
      {
        'https://example.com/one.png': _BinaryResponse(_png()),
        'https://example.com/two.png': _BinaryResponse(
          _png(color: img.ColorRgb8(112, 76, 48)),
        ),
        'https://example.com/three.png': _BinaryResponse(
          _png(color: img.ColorRgb8(128, 138, 100)),
        ),
      },
      gate: gate,
    );
    final resolver = SafeThumbnailResolver(
      whiteboardRoot: root,
      httpClient: _client(adapter),
    );
    final resolving = [
      for (final id in ['one', 'two', 'three'])
        resolver.resolve(ThumbnailResolveRequest(
          sourceId: 'src_$id',
          sourceVersionId: 'ver_${id}_v1',
          candidateUrl: 'https://example.com/$id.png',
          canonicalUrl: 'https://example.com/article',
        )),
    ];
    for (var attempt = 0; attempt < 20 && adapter.calls == 0; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    expect(adapter.calls, 1,
        reason: 'queued candidates must not start a network body concurrently');
    gate.complete();
    final resolved = await Future.wait(resolving);

    expect(resolved.every((item) => item.isAvailable), isTrue);
    expect(adapter.calls, 3);
    expect(adapter.maxActiveCalls, 1);
  });

  test('concurrent distinct writes cannot race past the cache quota', () async {
    final firstBytes = _png(color: img.ColorRgb8(67, 89, 59));
    final secondBytes = _png(color: img.ColorRgb8(112, 76, 48));
    final adapter = _BinaryAdapter({
      'https://example.com/first.png': _BinaryResponse(firstBytes),
      'https://example.com/second.png': _BinaryResponse(secondBytes),
    });
    final resolver = SafeThumbnailResolver(
      whiteboardRoot: root,
      httpClient: _client(adapter),
      maxCacheBytes: firstBytes.length + secondBytes.length - 1,
    );

    final resolved = await Future.wait([
      resolver.resolve(const ThumbnailResolveRequest(
        sourceId: 'src_first',
        sourceVersionId: 'ver_first_v1',
        candidateUrl: 'https://example.com/first.png',
        canonicalUrl: 'https://example.com/article',
      )),
      resolver.resolve(const ThumbnailResolveRequest(
        sourceId: 'src_second',
        sourceVersionId: 'ver_second_v1',
        candidateUrl: 'https://example.com/second.png',
        canonicalUrl: 'https://example.com/article',
      )),
    ]);

    expect(resolved.where((item) => item.isAvailable), hasLength(1));
    expect(
      resolved.where(
        (item) => item.errorMessage == 'Thumbnail cache reached its size limit',
      ),
      hasLength(1),
    );
    final files = await Directory(
      '${root.path}${Platform.pathSeparator}objects'
      '${Platform.pathSeparator}thumbnails',
    ).list().where((entity) => entity is File).cast<File>().toList();
    final used = files.fold<int>(0, (sum, file) => sum + file.lengthSync());
    expect(
      used,
      lessThanOrEqualTo(firstBytes.length + secondBytes.length - 1),
    );
  });

  test('relative candidate resolves against the canonical source URL',
      () async {
    final adapter = _BinaryAdapter({
      'https://example.com/assets/cover.png': _BinaryResponse(_png()),
    });
    final resolver = SafeThumbnailResolver(
      whiteboardRoot: root,
      httpClient: _client(adapter),
    );

    final resolved = await resolver.resolve(const ThumbnailResolveRequest(
      sourceId: 'src_relative',
      sourceVersionId: 'ver_relative_v1',
      candidateUrl: '../assets/cover.png',
      canonicalUrl: 'https://example.com/posts/article',
    ));

    expect(resolved.isAvailable, isTrue);
    expect(adapter.calls, 1);
  });

  test('a corrupt regular cache object is rebuilt from the safe candidate',
      () async {
    final adapter = _BinaryAdapter({
      'https://example.com/heal.png': _BinaryResponse(_png()),
    });
    final resolver = SafeThumbnailResolver(
      whiteboardRoot: root,
      httpClient: _client(adapter),
    );
    const request = ThumbnailResolveRequest(
      sourceId: 'src_heal',
      sourceVersionId: 'ver_heal_v1',
      candidateUrl: 'https://example.com/heal.png',
      canonicalUrl: 'https://example.com/article',
    );
    final first = await resolver.resolve(request);
    await first.file!.writeAsBytes([1, 2, 3], flush: true);

    final healed = await resolver.resolve(ThumbnailResolveRequest(
      sourceId: request.sourceId,
      sourceVersionId: request.sourceVersionId,
      candidateUrl: request.candidateUrl,
      canonicalUrl: request.canonicalUrl,
      cachedObjectRef: first.objectRef,
      cachedVersionId: request.sourceVersionId,
      cachedCandidateHash: first.candidateHash,
    ));

    expect(healed.isAvailable, isTrue);
    expect(adapter.calls, 2);
    expect(await resolver.resolveCached(healed.objectRef), isNotNull);
  });

  test('rejects MIME spoofing, SVG, oversized pixels and unsafe refs',
      () async {
    final htmlBytes = Uint8List.fromList('<script>alert(1)</script>'.codeUnits);
    final hugeHeader = _png(width: 40, height: 40);
    final adapter = _BinaryAdapter({
      'https://example.com/spoof.png':
          _BinaryResponse(htmlBytes, mimeType: 'image/png'),
      'https://example.com/vector.svg':
          _BinaryResponse(htmlBytes, mimeType: 'image/svg+xml'),
      'https://example.com/huge.png': _BinaryResponse(hugeHeader),
    });
    final resolver = SafeThumbnailResolver(
      whiteboardRoot: root,
      httpClient: _client(adapter),
      maxInputPixels: 1000,
    );

    final spoof = await resolver.resolve(const ThumbnailResolveRequest(
      sourceId: 'src_spoof',
      sourceVersionId: 'ver_spoof_v1',
      candidateUrl: 'https://example.com/spoof.png',
      canonicalUrl: 'https://example.com/article',
    ));
    final svg = await resolver.resolve(const ThumbnailResolveRequest(
      sourceId: 'src_svg',
      sourceVersionId: 'ver_svg_v1',
      candidateUrl: 'https://example.com/vector.svg',
      canonicalUrl: 'https://example.com/article',
    ));
    final huge = await resolver.resolve(const ThumbnailResolveRequest(
      sourceId: 'src_huge',
      sourceVersionId: 'ver_huge_v1',
      candidateUrl: 'https://example.com/huge.png',
      canonicalUrl: 'https://example.com/article',
    ));

    expect(spoof.status, ThumbnailResolveStatus.rejected);
    expect(svg.status, ThumbnailResolveStatus.rejected);
    expect(huge.status, ThumbnailResolveStatus.rejected);
    expect(await resolver.resolveCached('../outside.png'), isNull);
    expect(await resolver.resolveCached(r'C:\Windows\secret.png'), isNull);
    expect(
      await resolver.resolveCached('objects/thumbs/legacy.png'),
      isNull,
    );
  });

  test('literal private candidates are rejected before any socket request',
      () async {
    final resolver = SafeThumbnailResolver(whiteboardRoot: root);

    final resolved = await resolver.resolve(const ThumbnailResolveRequest(
      sourceId: 'src_private',
      sourceVersionId: 'ver_private_v1',
      candidateUrl: 'http://127.0.0.1/private.png',
      canonicalUrl: 'https://example.com/article',
    ));

    expect(resolved.status, ThumbnailResolveStatus.rejected);
    expect(resolved.errorMessage, contains('SSRF'));
  });

  test('filesystem failures return a typed failure instead of throwing',
      () async {
    final blockedRoot = File(
      '${root.path}${Platform.pathSeparator}not-a-directory',
    );
    await blockedRoot.writeAsString('occupied');
    final adapter = _BinaryAdapter({
      'https://example.com/blocked.png': _BinaryResponse(_png()),
    });
    final resolver = SafeThumbnailResolver(
      whiteboardRoot: Directory(blockedRoot.path),
      httpClient: _client(adapter),
    );

    final resolved = await resolver.resolve(const ThumbnailResolveRequest(
      sourceId: 'src_blocked',
      sourceVersionId: 'ver_blocked_v1',
      candidateUrl: 'https://example.com/blocked.png',
      canonicalUrl: 'https://example.com/article',
    ));

    expect(resolved.status, ThumbnailResolveStatus.failed);
    expect(resolved.errorMessage, 'Thumbnail resolution failed');
  });
}
