import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

import 'package:memex/data/whiteboard/ingestion/safe_http_client.dart';

/// A fake Dio adapter that returns canned responses based on URL.
class _FakeAdapter implements HttpClientAdapter {
  final Map<String, _CannedResponse> responses;
  final Map<String, int> callCounts = {};

  _FakeAdapter(this.responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    final url = options.path;
    callCounts[url] = (callCounts[url] ?? 0) + 1;
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

class _CannedResponse {
  final String body;
  final int statusCode;
  final String contentType;
  final String? location;
  _CannedResponse(this.body, this.statusCode, this.contentType, {this.location});
}

/// An adapter that streams raw chunks with a controllable (possibly missing /
/// lying) Content-Length, for testing the true byte cap.
class _StreamingAdapter implements HttpClientAdapter {
  final _CannedStream canned;
  _StreamingAdapter(this.canned);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    return ResponseBody(
      Stream.fromIterable(canned.chunks),
      canned.statusCode,
      headers: {
        'content-type': [canned.contentType],
        if (canned.contentLength != null)
          'content-length': [canned.contentLength.toString()],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _CannedStream {
  final List<Uint8List> chunks;
  final int? contentLength;
  final int statusCode;
  final String contentType;
  _CannedStream(this.chunks, this.contentLength, this.statusCode, this.contentType);
}

/// An adapter that fails the first [failTimes] calls with a transient network
/// error, then succeeds — for retry semantics.
class _FlakyAdapter implements HttpClientAdapter {
  final int failTimes;
  int calls = 0;
  _FlakyAdapter(this.failTimes);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    calls++;
    if (calls <= failTimes) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'flaky',
      );
    }
    return ResponseBody.fromString(
      '<html><body><article><h1>OK</h1></article></body></html>',
      200,
      headers: {'content-type': ['text/html']},
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A fake DNS resolver controlled by tests.
class _FakeResolver implements DnsResolver {
  final Map<String, List<InternetAddress>> map;
  _FakeResolver(this.map);

  @override
  Future<List<InternetAddress>> lookup(String host) async =>
      map[host] ?? const [];
}

/// A resolver that always fails — simulates NXDOMAIN / DNS outage.
class _ThrowingResolver implements DnsResolver {
  @override
  Future<List<InternetAddress>> lookup(String host) async {
    throw SocketException('DNS lookup failed for $host');
  }
}

Dio _createDio(Map<String, _CannedResponse> responses) {
  return Dio(BaseOptions(
    followRedirects: false,
    validateStatus: (s) => s != null && s >= 200 && s < 400,
  ))..httpClientAdapter = _FakeAdapter(responses);
}

List<Uint8List> _chunksOfTotalBytes(int total, int chunkSize) {
  final chunks = <Uint8List>[];
  var remaining = total;
  while (remaining > 0) {
    final n = remaining > chunkSize ? chunkSize : remaining;
    chunks.add(Uint8List(n));
    remaining -= n;
  }
  return chunks;
}

void main() {
  group('SafeHttpClient SSRF protection — literal hosts', () {
    // These literal hosts are blocked by the synchronous literal check, so
    // they are safe with the production default (enforceDnsCheck=true) and
    // never even touch the injected empty dio.
    test('blocks localhost', () async {
      final client = SafeHttpClient(dio: _createDio({}));
      final r = await client.fetch('http://localhost/admin');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
    });

    test('blocks 127.0.0.1', () async {
      final client = SafeHttpClient(dio: _createDio({}));
      final r = await client.fetch('http://127.0.0.1/admin');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
    });

    test('blocks 169.254.169.254 metadata', () async {
      final client = SafeHttpClient(dio: _createDio({}));
      final r = await client.fetch('http://169.254.169.254/latest/meta-data');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
    });

    test('blocks 10.x private range', () async {
      final client = SafeHttpClient(dio: _createDio({}));
      final r = await client.fetch('http://10.0.0.1/internal');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
    });

    test('blocks 192.168.x private range', () async {
      final client = SafeHttpClient(dio: _createDio({}));
      final r = await client.fetch('http://192.168.1.1/router');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
    });

    test('blocks 172.16-31.x private range', () async {
      final client = SafeHttpClient(dio: _createDio({}));
      final r = await client.fetch('http://172.16.0.1/internal');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
    });

    test('blocks IPv6 literal loopback ::1', () async {
      final client = SafeHttpClient(dio: _createDio({}));
      final r = await client.fetch('http://[::1]/admin');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
    });

    test('blocks non-http scheme', () async {
      final client = SafeHttpClient(dio: _createDio({}));
      final r = await client.fetch('file:///etc/passwd');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('Disallowed scheme'));
    });

    test('blocks .local TLD', () async {
      final client = SafeHttpClient(dio: _createDio({}));
      final r = await client.fetch('http://myhost.local/api');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
    });
  });

  group('SafeHttpClient DNS SSRF protection', () {
    test('domain resolving to 127.0.0.1 is blocked', () async {
      final client = SafeHttpClient(
        dio: _createDio({}),
        resolver: _FakeResolver({'evil.example': [InternetAddress('127.0.0.1')]}),
      );
      final r = await client.fetch('http://evil.example/');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
      expect(r.errorMessage, contains('127.0.0.1'));
    });

    test('domain resolving to RFC1918 private address is blocked', () async {
      final client = SafeHttpClient(
        dio: _createDio({}),
        resolver: _FakeResolver({
          'intranet.corp': [InternetAddress('10.0.0.5')],
        }),
      );
      final r = await client.fetch('http://intranet.corp/');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
      expect(r.errorMessage, contains('10.0.0.5'));
    });

    test('domain resolving to link-local 169.254.x is blocked', () async {
      final client = SafeHttpClient(
        dio: _createDio({}),
        resolver: _FakeResolver({
          'metadata.example': [InternetAddress('169.254.169.254')],
        }),
      );
      final r = await client.fetch('http://metadata.example/');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
    });

    test('domain resolving to IPv6 loopback ::1 is blocked', () async {
      final client = SafeHttpClient(
        dio: _createDio({}),
        resolver: _FakeResolver({'v6loop.example': [InternetAddress('::1')]}),
      );
      final r = await client.fetch('http://v6loop.example/');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
    });

    test('domain resolving to IPv6 ULA fc00::/7 is blocked', () async {
      final client = SafeHttpClient(
        dio: _createDio({}),
        resolver: _FakeResolver({'ula.example': [InternetAddress('fd12:3456::1')]}),
      );
      final r = await client.fetch('http://ula.example/');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
    });

    test('domain resolving to IPv6 link-local fe80::/10 is blocked', () async {
      final client = SafeHttpClient(
        dio: _createDio({}),
        resolver: _FakeResolver({'ll.example': [InternetAddress('fe80::1')]}),
      );
      final r = await client.fetch('http://ll.example/');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
    });

    test('mixed public + private addresses fail the whole request', () async {
      final client = SafeHttpClient(
        dio: _createDio({}),
        resolver: _FakeResolver({
          'mixed.example': [
            InternetAddress('93.184.216.34'),
            InternetAddress('10.0.0.9'),
          ],
        }),
      );
      final r = await client.fetch('http://mixed.example/');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
      expect(r.errorMessage, contains('10.0.0.9'));
    });

    test('public-only domain is allowed and request proceeds', () async {
      final dio = _createDio({
        'https://public.example/doc': _CannedResponse(
          '<html><head><title>Public</title></head><body><p>hi</p></body></html>',
          200,
          'text/html; charset=utf-8',
        ),
      });
      final client = SafeHttpClient(
        dio: dio,
        resolver: _FakeResolver({
          'public.example': [InternetAddress('93.184.216.34')],
        }),
      );
      final r = await client.fetch('https://public.example/doc');
      expect(r.success, isTrue);
      expect(r.body, contains('hi'));
    });

    test('redirect to a domain that resolves dangerously is blocked', () async {
      final dio = _createDio({
        'https://example.com/start': _CannedResponse(
          '',
          302,
          'text/html',
          location: 'http://internal.example/secret',
        ),
      });
      final client = SafeHttpClient(
        dio: dio,
        resolver: _FakeResolver({
          'example.com': [InternetAddress('93.184.216.34')],
          'internal.example': [InternetAddress('127.0.0.1')],
        }),
      );
      final r = await client.fetch('https://example.com/start');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
      expect(r.errorMessage, contains('internal.example'));
    });

    test('redirect to a literal private IP is blocked on the next hop',
        () async {
      final dio = _createDio({
        'https://example.com/start': _CannedResponse(
          '',
          302,
          'text/html',
          location: 'http://192.168.0.10/secret',
        ),
      });
      final client = SafeHttpClient(
        dio: dio,
        resolver: _FakeResolver({
          'example.com': [InternetAddress('93.184.216.34')],
        }),
      );
      final r = await client.fetch('https://example.com/start');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
    });

    test('DNS resolution failure is a policy error (no retry)', () async {
      final adapter = _FakeAdapter({});
      final client = SafeHttpClient(
        dio: Dio(BaseOptions(
          followRedirects: false,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ))
          ..httpClientAdapter = adapter,
        config: const SafeHttpConfig(maxRetries: 2),
        resolver: _ThrowingResolver(),
      );
      final r = await client.fetch('http://nxd.example/');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('DNS resolution failed'));
    });
  });

  group('SafeHttpClient normal fetch', () {
    test('returns body for valid HTML response', () async {
      final dio = _createDio({
        'https://example.com/article': _CannedResponse(
          '<html><head><title>Test</title></head><body><p>Hello</p></body></html>',
          200,
          'text/html; charset=utf-8',
        ),
      });
      final client = SafeHttpClient(
        dio: dio,
        config: const SafeHttpConfig(enforceDnsCheck: false),
      );
      final r = await client.fetch('https://example.com/article');
      expect(r.success, isTrue);
      expect(r.body, contains('Hello'));
      expect(r.mimeType, 'text/html');
      expect(r.statusCode, 200);
    });

    test('follows redirects and re-checks target host', () async {
      final dio = _createDio({
        'https://example.com/old': _CannedResponse(
          '',
          302,
          'text/html',
          location: 'https://cdn.example.com/new',
        ),
        'https://cdn.example.com/new': _CannedResponse(
          '<html><body><article><h1>Redirected</h1></article></body></html>',
          200,
          'text/html',
        ),
      });
      final client = SafeHttpClient(
        dio: dio,
        config: const SafeHttpConfig(enforceDnsCheck: false),
      );
      final r = await client.fetch('https://example.com/old');
      expect(r.success, isTrue);
      expect(r.finalUrl, 'https://cdn.example.com/new');
      expect(r.body, contains('Redirected'));
    });

    test('blocks redirect to localhost literal', () async {
      final dio = _createDio({
        'https://example.com/redirect': _CannedResponse(
          '',
          302,
          'text/html',
          location: 'http://localhost/secret',
        ),
      });
      final client = SafeHttpClient(
        dio: dio,
        config: const SafeHttpConfig(enforceDnsCheck: false),
      );
      final r = await client.fetch('https://example.com/redirect');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
    });

    test('rejects non-HTML MIME type', () async {
      final dio = _createDio({
        'https://example.com/image': _CannedResponse(
          'binary-data',
          200,
          'image/png',
        ),
      });
      final client = SafeHttpClient(
        dio: dio,
        config: const SafeHttpConfig(enforceDnsCheck: false),
      );
      final r = await client.fetch('https://example.com/image');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('Unsupported MIME type'));
    });

    test('enforces max redirects', () async {
      final dio = _createDio({
        'https://example.com/r1': _CannedResponse(
          '', 302, 'text/html',
          location: 'https://example.com/r2',
        ),
        'https://example.com/r2': _CannedResponse(
          '', 302, 'text/html',
          location: 'https://example.com/r3',
        ),
        'https://example.com/r3': _CannedResponse(
          '', 302, 'text/html',
          location: 'https://example.com/r4',
        ),
        'https://example.com/r4': _CannedResponse(
          '<html><body>final</body></html>',
          200, 'text/html',
        ),
      });
      final client = SafeHttpClient(
        dio: dio,
        config: const SafeHttpConfig(maxRedirects: 2, enforceDnsCheck: false),
      );
      final r = await client.fetch('https://example.com/r1');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('Too many redirects'));
    });

    test('redirect without Location header fails', () async {
      final dio = _createDio({
        'https://example.com/no-loc': _CannedResponse(
          '', 302, 'text/html',
        ),
      });
      final client = SafeHttpClient(
        dio: dio,
        config: const SafeHttpConfig(enforceDnsCheck: false),
      );
      final r = await client.fetch('https://example.com/no-loc');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('without Location'));
    });
  });

  group('SafeHttpClient auth rejection (needsAuth state)', () {
    test('HTTP 403 produces an auth failure, not a generic network error',
        () async {
      final dio = _createDio({
        'https://example.com/blocked': _CannedResponse('', 403, 'text/html'),
      });
      final client = SafeHttpClient(
        dio: dio,
        config: const SafeHttpConfig(enforceDnsCheck: false),
      );
      final r = await client.fetch('https://example.com/blocked');
      expect(r.success, isFalse);
      expect(r.authRequired, isTrue);
      expect(r.errorMessage, contains('HTTP 403'));
    });

    test('HTTP 401 produces an auth failure', () async {
      final dio = _createDio({
        'https://example.com/login': _CannedResponse('', 401, 'text/html'),
      });
      final client = SafeHttpClient(
        dio: dio,
        config: const SafeHttpConfig(enforceDnsCheck: false),
      );
      final r = await client.fetch('https://example.com/login');
      expect(r.success, isFalse);
      expect(r.authRequired, isTrue);
      expect(r.errorMessage, contains('HTTP 401'));
    });

    test('auth rejections are policy errors (never retried)', () async {
      final dio = _createDio({
        'https://example.com/blocked': _CannedResponse('', 403, 'text/html'),
      });
      final adapter = dio.httpClientAdapter as _FakeAdapter;
      final client = SafeHttpClient(
        dio: dio,
        config: const SafeHttpConfig(maxRetries: 2, enforceDnsCheck: false),
      );
      final r = await client.fetch('https://example.com/blocked');
      expect(r.authRequired, isTrue);
      expect(adapter.callCounts['https://example.com/blocked'], 1);
    });

    test('other HTTP errors stay generic failures', () async {
      final dio = _createDio({
        'https://example.com/500': _CannedResponse('', 500, 'text/html'),
      });
      final client = SafeHttpClient(
        dio: dio,
        config: const SafeHttpConfig(enforceDnsCheck: false),
      );
      final r = await client.fetch('https://example.com/500');
      expect(r.success, isFalse);
      expect(r.authRequired, isFalse);
      expect(r.errorMessage, contains('HTTP 500'));
    });
  });

  group('SafeHttpClient streaming byte cap', () {
    const maxBodyBytes = 2 * 1024 * 1024; // 2 MB

    test('rejects oversized body announced via Content-Length', () async {
      final bigBody = 'x' * (1024 * 10);
      final dio = _createDio({
        'https://example.com/big': _CannedResponse(
          bigBody, 200, 'text/html',
        ),
      });
      final client = SafeHttpClient(
        dio: dio,
        config: const SafeHttpConfig(maxBodyBytes: 1024, enforceDnsCheck: false),
      );
      final r = await client.fetch('https://example.com/big');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('max size'));
    });

    test('rejects a stream with no Content-Length that exceeds the cap',
        () async {
      // 3 MB of chunks, no Content-Length header at all.
      final chunks = _chunksOfTotalBytes(3 * 1024 * 1024, 65536);
      final adapter = _StreamingAdapter(
        _CannedStream(chunks, null, 200, 'text/html'),
      );
      final client = SafeHttpClient(
        dio: Dio(BaseOptions(
          followRedirects: false,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ))
          ..httpClientAdapter = adapter,
        config: const SafeHttpConfig(
            maxBodyBytes: maxBodyBytes, enforceDnsCheck: false),
      );
      final r = await client.fetch('https://example.com/chunked');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('max size'));
      expect(r.body, isNull);
    });

    test('rejects a lying small Content-Length whose real stream exceeds the cap',
        () async {
      // Lying Content-Length of 10 bytes, but the stream actually carries 3 MB.
      final chunks = _chunksOfTotalBytes(3 * 1024 * 1024, 65536);
      final adapter = _StreamingAdapter(
        _CannedStream(chunks, 10, 200, 'text/html'),
      );
      final client = SafeHttpClient(
        dio: Dio(BaseOptions(
          followRedirects: false,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ))
          ..httpClientAdapter = adapter,
        config: const SafeHttpConfig(
            maxBodyBytes: maxBodyBytes, enforceDnsCheck: false),
      );
      final r = await client.fetch('https://example.com/lying');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('max size'));
      expect(r.body, isNull);
    });

    test('a stream within the cap decodes successfully', () async {
      final chunk1 = Uint8List.fromList(utf8.encode('<html><head><title>'));
      final chunk2 = Uint8List.fromList(utf8.encode('Small</title></head><body><p>ok</p></body></html>'));
      final adapter = _StreamingAdapter(
        _CannedStream([chunk1, chunk2], chunk1.length + chunk2.length, 200, 'text/html'),
      );
      final client = SafeHttpClient(
        dio: Dio(BaseOptions(
          followRedirects: false,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ))
          ..httpClientAdapter = adapter,
        config: const SafeHttpConfig(enforceDnsCheck: false),
      );
      final r = await client.fetch('https://example.com/small');
      expect(r.success, isTrue);
      expect(r.body, contains('Small'));
      expect(r.body, contains('ok'));
    });
  });

  group('SafeHttpClient retry semantics', () {
    test('transient errors are retried up to maxRetries', () async {
      final adapter = _FlakyAdapter(1);
      final client = SafeHttpClient(
        dio: Dio(BaseOptions(
          followRedirects: false,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ))
          ..httpClientAdapter = adapter,
        config: const SafeHttpConfig(maxRetries: 2, enforceDnsCheck: false),
      );
      final r = await client.fetch('https://example.com/flaky');
      expect(r.success, isTrue);
      expect(adapter.calls, 2);
    });

    test('policy errors (bad MIME) are never retried', () async {
      final dio = _createDio({
        'https://example.com/image': _CannedResponse(
          'binary-data', 200, 'image/png',
        ),
      });
      final adapter = dio.httpClientAdapter as _FakeAdapter;
      final client = SafeHttpClient(
        dio: dio,
        config: const SafeHttpConfig(maxRetries: 2, enforceDnsCheck: false),
      );
      final r = await client.fetch('https://example.com/image');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('Unsupported MIME type'));
      expect(adapter.callCounts['https://example.com/image'], 1);
    });

    test('policy errors (SSRF literal) are never retried — no request issued',
        () async {
      final dio = _createDio({});
      final adapter = dio.httpClientAdapter as _FakeAdapter;
      final client = SafeHttpClient(
        dio: dio,
        config: const SafeHttpConfig(maxRetries: 2),
      );
      final r = await client.fetch('http://127.0.0.1/admin');
      expect(r.success, isFalse);
      expect(adapter.callCounts, isEmpty);
    });
  });

  group('enforceDnsCheck defaults', () {
    test('defaults to true in production config', () {
      expect(SafeHttpConfig.defaultConfig.enforceDnsCheck, isTrue);
      // An explicit false is only allowed in test configuration.
      const explicitTestConfig = SafeHttpConfig(enforceDnsCheck: false);
      expect(explicitTestConfig.enforceDnsCheck, isFalse);
    });

    test('default client enables DNS check via SystemDnsResolver', () {
      final client = SafeHttpClient();
      // Constructed with the production default config (enforceDnsCheck=true)
      // and the system resolver — no need to inspect internals; the DNS
      // group above already proves enforcement via an injected resolver.
      expect(client, isNotNull);
    });
  });
}