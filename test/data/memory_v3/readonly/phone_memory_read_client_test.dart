import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/readonly/phone_memory_read_client.dart';
import 'package:memex/utils/result.dart';

void main() {
  final expiry = DateTime.utc(2026, 9, 5, 12);
  final code = _code(expiry);

  test('authenticated wire is fixed localhost and exposes only receipt data',
      () async {
    final adapter = _Adapter([_status(expiry), _context(expiry)]);
    final dio = _dio(adapter);
    final client = PhoneMemoryReadClient(
      dio: dio,
      clock: () => DateTime.utc(2026, 9, 5, 11),
    );

    expect(await client.connect(code), isA<Ok<void>>());
    final context = await client.readContext(characterId: 'i', query: '今天');

    expect(context.status, 'available');
    expect(context.episodes.single.narrative, 'phone-only episode');
    expect(client.lastReceipt, isNot(contains('token')));
    expect(client.lastReceipt, isNot(contains('query')));
    expect(adapter.requests, hasLength(2));
    for (final request in adapter.requests) {
      expect(request.uri.host, '127.0.0.1');
      expect(request.uri.port, 47851);
      expect(request.followRedirects, isFalse);
      expect(request.headers['authorization'], isNotNull);
      expect(request.uri.query, isEmpty);
    }
    expect(adapter.requests.last.data, isA<Map>());
  });

  test('expiry keeps the selected phone source unavailable and revokes lease',
      () async {
    var now = DateTime.utc(2026, 9, 5, 11);
    final client = PhoneMemoryReadClient(
      dio: _dio(_Adapter([_status(expiry), _context(expiry)])),
      clock: () => now,
    );
    expect(await client.connect(code), isA<Ok<void>>());
    final assembled =
        await client.readContext(characterId: 'i', query: 'lease');
    expect(assembled.isAuthorizedNow?.call(), isTrue);
    now = expiry;
    expect(assembled.isAuthorizedNow?.call(), isFalse);
    expect(
      (await client.readContext(characterId: 'i', query: 'expired')).status,
      'unavailable',
    );
    expect(client.isConfigured, isTrue);
    expect(client.lastReceipt?['status'], 'unavailable');
  });

  test('bad status does not replace a configured phone source', () async {
    final client = PhoneMemoryReadClient(
      dio: _dio(_Adapter([
        _status(expiry),
        {'schema_version': 0}
      ])),
      clock: () => DateTime.utc(2026, 9, 5, 11),
    );
    expect(await client.connect(code), isA<Ok<void>>());
    expect(await client.connect(code), isA<Error<void>>());
    expect(client.isConfigured, isTrue);
  });

  test('rejects invalid code before making a network request', () async {
    final adapter = _Adapter([]);
    final client = PhoneMemoryReadClient(
      dio: _dio(adapter),
      clock: () => DateTime.utc(2026, 9, 5, 11),
    );
    final result = await client.connect('p5v1.not-a-code');
    expect(result, isA<Error<void>>());
    expect(adapter.requests, isEmpty);
  });

  test('rejects a streamed body at the byte cap before JSON parsing', () async {
    final adapter = _BodiesAdapter([
      _body(_status(expiry)),
      ResponseBody(
        Stream.value(Uint8List(33 * 1024)),
        200,
        headers: const {
          'content-type': ['application/json']
        },
      ),
    ]);
    final client = PhoneMemoryReadClient(
      dio: _dio(adapter),
      clock: () => DateTime.utc(2026, 9, 5, 11),
    );
    expect(await client.connect(code), isA<Ok<void>>());
    expect(
        (await client.readContext(characterId: 'i', query: 'bounded')).status,
        'unavailable');
    expect(client.isConfigured, isTrue);
  });

  test('stream drip past the overall deadline is unavailable', () async {
    final adapter = _BodiesAdapter([
      _body(_status(expiry)),
      ResponseBody(
        _delayedBytes(const Duration(milliseconds: 100)),
        200,
        headers: const {
          'content-type': ['application/json']
        },
      ),
    ]);
    final client = PhoneMemoryReadClient(
      dio: _dio(adapter),
      clock: () => DateTime.utc(2026, 9, 5, 11),
      requestDeadline: const Duration(milliseconds: 30),
    );
    expect(await client.connect(code), isA<Ok<void>>());
    expect((await client.readContext(characterId: 'i', query: 'drip')).status,
        'unavailable');
  });

  test('disconnect revokes an in-flight connect and read result', () async {
    final statusGate = Completer<ResponseBody>();
    final connectAdapter = _DeferredAdapter(statusGate.future);
    final connecting = PhoneMemoryReadClient(
      dio: _dio(connectAdapter),
      clock: () => DateTime.utc(2026, 9, 5, 11),
    );
    final pendingConnect = connecting.connect(code);
    connecting.disconnect();
    statusGate.complete(_body(_status(expiry)));
    expect(await pendingConnect, isA<Error<void>>());
    expect(connecting.isConfigured, isFalse);

    final readGate = Completer<ResponseBody>();
    final adapter = _BodiesAdapter([_body(_status(expiry)), readGate.future]);
    final client = PhoneMemoryReadClient(
      dio: _dio(adapter),
      clock: () => DateTime.utc(2026, 9, 5, 11),
    );
    expect(await client.connect(code), isA<Ok<void>>());
    final pendingRead = client.readContext(characterId: 'i', query: 'old');
    client.disconnect();
    readGate.complete(_body(_context(expiry)));
    expect((await pendingRead).status, 'unavailable');
    expect(client.lastReceipt, isNull);
  });

  test('reconnect revokes an older in-flight read result', () async {
    final oldRead = Completer<ResponseBody>();
    final adapter = _BodiesAdapter([
      _body(_status(expiry)),
      oldRead.future,
      _body(_status(expiry)),
    ]);
    final client = PhoneMemoryReadClient(
      dio: _dio(adapter),
      clock: () => DateTime.utc(2026, 9, 5, 11),
    );
    expect(await client.connect(code), isA<Ok<void>>());
    final pendingRead = client.readContext(characterId: 'i', query: 'old');
    expect(await client.connect(code), isA<Ok<void>>());
    oldRead.complete(_body(_context(expiry)));
    expect((await pendingRead).status, 'unavailable');
    expect(client.lastReceipt?['status'], 'connected');
  });
}

String _code(DateTime expiry) =>
    'p5v1.${base64Url.encode(utf8.encode(jsonEncode({
              'v': 1,
              'token': 'a' * 32,
              'session_id': 'session-1',
              'expires_at': expiry.toIso8601String(),
            }))).replaceAll('=', '')}';

Map<String, Object?> _status(DateTime expiry) => {
      'schema_version': 1,
      'source_kind': 'phone_v3_live',
      'character_id': 'i',
      'session_id': 'session-1',
      'captured_at': DateTime.utc(2026, 9, 5, 11).toIso8601String(),
      'expires_at': expiry.toIso8601String(),
    };

Map<String, Object?> _context(DateTime expiry) => {
      ..._status(expiry),
      'dreaming_status': 'available',
      'dreaming': {
        'episodes': [
          {'id': 'episode-1', 'narrative': 'phone-only episode', 'score': 7},
        ],
        'fragments': const [],
        'sagas': const [],
      },
    };

class _Adapter implements HttpClientAdapter {
  _Adapter(this.responses);
  final List<Map<String, Object?>> responses;
  final List<RequestOptions> requests = [];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<dynamic>? cancelFuture) async {
    requests.add(options);
    final value = responses.removeAt(0);
    return ResponseBody.fromString(jsonEncode(value), 200, headers: {
      'content-type': ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _body(Map<String, Object?> value) => ResponseBody.fromString(
      jsonEncode(value),
      200,
      headers: const {
        'content-type': ['application/json']
      },
    );

Stream<Uint8List> _delayedBytes(Duration delay) async* {
  await Future<void>.delayed(delay);
  yield Uint8List.fromList(utf8.encode(jsonEncode(_context(
    DateTime.utc(2026, 9, 5, 12),
  ))));
}

class _BodiesAdapter implements HttpClientAdapter {
  _BodiesAdapter(this._responses);
  final List<Object> _responses;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<dynamic>? cancelFuture) async {
    final next = _responses.removeAt(0);
    return next is Future<ResponseBody> ? next : next as ResponseBody;
  }

  @override
  void close({bool force = false}) {}
}

class _DeferredAdapter implements HttpClientAdapter {
  _DeferredAdapter(this.response);
  final Future<ResponseBody> response;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
          Future<dynamic>? cancelFuture) =>
      response;
  @override
  void close({bool force = false}) {}
}

Dio _dio(HttpClientAdapter adapter) => Dio(BaseOptions(
      baseUrl: 'http://127.0.0.1:47851',
      followRedirects: false,
    ))
      ..httpClientAdapter = adapter;
