import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:memex/domain/whiteboard/video/bilibili_safe_http_transport.dart';

class _QueueClient extends http.BaseClient {
  _QueueClient(this.responses);

  final List<http.StreamedResponse> responses;
  final List<http.BaseRequest> requests = [];
  var _index = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (_index >= responses.length) {
      throw StateError('unexpected request');
    }
    return responses[_index++];
  }
}

http.StreamedResponse _response(
  int statusCode, {
  Map<String, String> headers = const {},
  List<List<int>> chunks = const [],
  int? contentLength,
}) =>
    http.StreamedResponse(
      Stream<List<int>>.fromIterable(chunks),
      statusCode,
      headers: headers,
      contentLength: contentLength,
    );

const _headers = {
  'Accept': 'application/json',
  'Referer': 'https://www.bilibili.com/video/BV1E8KV6QEu7',
  'Cookie': 'must-not-leak',
};

void main() {
  test('rejects an off-site redirect before sending Referer to it', () async {
    final client = _QueueClient([
      _response(
        302,
        headers: {'location': 'https://attacker.example/capture'},
      ),
    ]);
    final transport = BilibiliSafeHttpTransport(client: client);

    final result = await transport.getText(
      Uri.parse('https://aisubtitle.hdslb.com/bcc.json?auth_key=short-lived'),
      headers: _headers,
      maxBytes: 1024,
    );

    expect(result.failureKind, BilibiliHttpFailureKind.redirectRejected);
    expect(client.requests, hasLength(1));
    expect(client.requests.single.url.host, 'aisubtitle.hdslb.com');
    expect(client.requests.single.followRedirects, isFalse);
    expect(client.requests.single.maxRedirects, 0);
    expect(client.requests.single.headers.containsKey('Cookie'), isFalse);
    expect(client.requests.single.headers.containsKey('cookie'), isFalse);
  });

  test('stops after the configured number of allowed redirects', () async {
    final client = _QueueClient([
      _response(302, headers: {'location': '/one'}),
      _response(302, headers: {'location': '/two'}),
    ]);
    final transport = BilibiliSafeHttpTransport(
      client: client,
      maxRedirects: 1,
    );

    final result = await transport.getText(
      Uri.parse('https://api.bilibili.com/start'),
      headers: _headers,
      maxBytes: 1024,
    );

    expect(result.failureKind, BilibiliHttpFailureKind.tooManyRedirects);
    expect(
        client.requests.map((request) => request.url.path), ['/start', '/one']);
  });

  test('reads response bytes incrementally and rejects the first excess chunk',
      () async {
    final client = _QueueClient([
      _response(200, chunks: [utf8.encode('1234'), utf8.encode('5678')]),
    ]);
    final transport = BilibiliSafeHttpTransport(client: client);

    final result = await transport.getText(
      Uri.parse('https://api.bilibili.com/payload'),
      headers: _headers,
      maxBytes: 5,
    );

    expect(result.body, isNull);
    expect(result.failureKind, BilibiliHttpFailureKind.responseTooLarge);
  });

  test('rejects an oversized declared content length before reading', () async {
    final client = _QueueClient([
      _response(
        200,
        chunks: [utf8.encode('small test body')],
        contentLength: 4096,
      ),
    ]);
    final transport = BilibiliSafeHttpTransport(client: client);

    final result = await transport.getText(
      Uri.parse('https://api.bilibili.com/payload'),
      headers: _headers,
      maxBytes: 1024,
    );

    expect(result.body, isNull);
    expect(result.failureKind, BilibiliHttpFailureKind.responseTooLarge);
  });

  test('allows a bounded same-owner redirect and returns UTF-8 text', () async {
    final client = _QueueClient([
      _response(
        307,
        headers: {'location': 'https://aisubtitle.hdslb.com/bcc.json'},
      ),
      _response(200, chunks: [utf8.encode('{"body":[]}')]),
    ]);
    final transport = BilibiliSafeHttpTransport(client: client);

    final result = await transport.getText(
      Uri.parse('https://api.bilibili.com/start'),
      headers: _headers,
      maxBytes: 1024,
    );

    expect(result.body, '{"body":[]}');
    expect(client.requests, hasLength(2));
    expect(client.requests.last.url.host, 'aisubtitle.hdslb.com');
    expect(client.requests.last.headers.containsKey('Cookie'), isFalse);
  });
}
