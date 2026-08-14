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

Dio _createDio(Map<String, _CannedResponse> responses) {
  return Dio(BaseOptions(
    followRedirects: false,
    validateStatus: (s) => s != null && s >= 200 && s < 400,
  ))..httpClientAdapter = _FakeAdapter(responses);
}

void main() {
  group('SafeHttpClient SSRF protection', () {
    test('blocks localhost', () async {
      final client = SafeHttpClient(
        dio: _createDio({}),
        config: const SafeHttpConfig(enforceDnsCheck: false),
      );
      final r = await client.fetch('http://localhost/admin');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
    });

    test('blocks 127.0.0.1', () async {
      final client = SafeHttpClient(
        dio: _createDio({}),
        config: const SafeHttpConfig(enforceDnsCheck: false),
      );
      final r = await client.fetch('http://127.0.0.1/admin');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
    });

    test('blocks 169.254.169.254 metadata', () async {
      final client = SafeHttpClient(
        dio: _createDio({}),
        config: const SafeHttpConfig(enforceDnsCheck: false),
      );
      final r = await client.fetch('http://169.254.169.254/latest/meta-data');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
    });

    test('blocks 10.x private range', () async {
      final client = SafeHttpClient(
        dio: _createDio({}),
        config: const SafeHttpConfig(enforceDnsCheck: false),
      );
      final r = await client.fetch('http://10.0.0.1/internal');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
    });

    test('blocks 192.168.x private range', () async {
      final client = SafeHttpClient(
        dio: _createDio({}),
        config: const SafeHttpConfig(enforceDnsCheck: false),
      );
      final r = await client.fetch('http://192.168.1.1/router');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
    });

    test('blocks 172.16-31.x private range', () async {
      final client = SafeHttpClient(
        dio: _createDio({}),
        config: const SafeHttpConfig(enforceDnsCheck: false),
      );
      final r = await client.fetch('http://172.16.0.1/internal');
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
      final client = SafeHttpClient(
        dio: _createDio({}),
        config: const SafeHttpConfig(enforceDnsCheck: false),
      );
      final r = await client.fetch('http://myhost.local/api');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('SSRF blocked'));
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
      final client = SafeHttpClient(dio: dio);
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
      final client = SafeHttpClient(dio: dio);
      final r = await client.fetch('https://example.com/old');
      expect(r.success, isTrue);
      expect(r.finalUrl, 'https://cdn.example.com/new');
      expect(r.body, contains('Redirected'));
    });

    test('blocks redirect to localhost', () async {
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
      final client = SafeHttpClient(dio: dio);
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
        config: const SafeHttpConfig(maxRedirects: 2),
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
      final client = SafeHttpClient(dio: dio);
      final r = await client.fetch('https://example.com/no-loc');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('without Location'));
    });

    test('rejects oversized body', () async {
      final bigBody = 'x' * (1024 * 10);
      final dio = _createDio({
        'https://example.com/big': _CannedResponse(
          bigBody, 200, 'text/html',
        ),
      });
      final client = SafeHttpClient(
        dio: dio,
        config: const SafeHttpConfig(maxBodyBytes: 1024),
      );
      final r = await client.fetch('https://example.com/big');
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('max size'));
    });
  });
}