import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/readonly/phone_memory_read_server.dart';
import 'package:memex/utils/result.dart';

const _empty = {
  'episodes': <Object>[],
  'fragments': <Object>[],
  'sagas': <Object>[]
};
void main() {
  late PhoneMemoryReadServer server;
  late HttpClient client;
  late PhoneMemoryReadSession session;
  late String token;
  late PhoneMemoryReadIdentity? identity;
  late DateTime now;
  late Future<Map<String, Object?>> Function(String) read;
  setUp(() async {
    identity = const PhoneMemoryReadIdentity('account', Object());
    now = DateTime.utc(2026, 9, 5);
    read = (_) async => _empty;
    server = PhoneMemoryReadServer(
        identity: () async => identity,
        read: (query) => read(query),
        now: () => now,
        port: 0,
        queryTimeout: const Duration(milliseconds: 150),
        requestTimeout: const Duration(milliseconds: 250));
    client = HttpClient()..findProxy = (_) => 'DIRECT';
    session = (await server.start() as Ok<PhoneMemoryReadSession>).value;
    final decoded = jsonDecode(utf8.decode(base64Url
        .decode(base64Url.normalize(session.connectionCode.substring(5)))));
    token = decoded['token'] as String;
    expect(base64Url.decode(base64Url.normalize(token)).length,
        greaterThanOrEqualTo(24));
    expect((decoded as Map).keys.toSet(),
        {'v', 'token', 'session_id', 'expires_at'});
  });
  tearDown(() async {
    await server.stop();
    server.dispose();
    client.close(force: true);
  });
  Future<(int, Map<String, dynamic>)> request(
      {String method = 'POST',
      String path = '/v1/memory/read-context',
      Object? body = const {
        'schema_version': 1,
        'character_id': 'i',
        'query': 'orchard'
      },
      String? authorization,
      String? origin}) async {
    final req = await client.openUrl(
        method, Uri.parse('http://127.0.0.1:${session.port}$path'));
    req.headers.set('authorization', authorization ?? 'Bearer $token');
    if (origin != null) req.headers.set('origin', origin);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final response = await req.close();
    return (
      response.statusCode,
      jsonDecode(await utf8.decoder.bind(response).join())
          as Map<String, dynamic>
    );
  }

  test('authenticated status has no memory read and correct fixed metadata',
      () async {
    read = (_) => throw StateError('must_not_read');
    final (status, body) =
        await request(method: 'GET', path: '/v1/memory/status', body: null);
    expect(status, 200);
    expect(body['source_kind'], 'phone_v3_live');
    expect(body['character_id'], 'i');
    expect(body.containsKey('dreaming'), isFalse);
    expect(body.containsKey('token'), isFalse);
  });
  test('auth origin paths methods scopes and caller limits are rejected',
      () async {
    expect((await request(authorization: 'Bearer wrong')).$1, 401);
    expect((await request(origin: 'http://localhost')).$1, 403);
    expect((await request(path: '/v1/memory/read-context?token=x')).$1, 400);
    expect((await request(path: '/unknown')).$1, 404);
    expect((await request(method: 'DELETE')).$1, 405);
    for (final body in [
      {'schema_version': 1, 'character_id': 'other', 'query': 'orchard'},
      {'schema_version': 1, 'character_id': 'i', 'query': ''},
      {'schema_version': 1, 'character_id': 'i', 'query': 'x' * 2001},
      {
        'schema_version': 1,
        'character_id': 'i',
        'query': 'orchard',
        'limit': 20
      },
    ]) {
      expect((await request(body: body)).$1, 400);
    }
    expect((await request(body: {'padding': 'x' * 17000})).$1, 413);
  });
  test(
      'empty and unavailable have empty data, errors never contain private detail',
      () async {
    expect((await request()).$2['dreaming_status'], 'empty');
    read = (_) => throw StateError('sensitive query token SQL body');
    final response = await request();
    expect(response.$1, 200);
    expect(response.$2['dreaming_status'], 'unavailable');
    expect(response.$2['dreaming'], _empty);
    expect(jsonEncode(response.$2), isNot(contains('sensitive')));
  });
  test(
      'one read at a time and timeout retains lock until underlying read finishes',
      () async {
    final pending = Completer<Map<String, Object?>>();
    final entered = Completer<void>();
    read = (_) {
      entered.complete();
      return pending.future;
    };
    final first = request();
    await entered.future;
    expect((await request()).$1, 429);
    expect((await first).$2['dreaming_status'], 'unavailable');
    expect((await request()).$1, 429);
    pending.complete(_empty);
    await Future<void>.delayed(Duration.zero);
    read = (_) async => _empty;
    expect((await request()).$1, 200);
  });
  test('identity changes invalidate pending result and connection secret',
      () async {
    final pending = Completer<Map<String, Object?>>();
    final entered = Completer<void>();
    read = (_) {
      entered.complete();
      return pending.future;
    };
    final response = request().then<Object>((v) => v, onError: (Object e) => e);
    await entered.future;
    identity = const PhoneMemoryReadIdentity('different', Object());
    pending.complete({
      'episodes': [
        {'id': 'secret'}
      ],
      'fragments': [],
      'sagas': []
    });
    final outcome = await response;
    expect(outcome.toString(), isNot(contains('secret')));
    expect(server.isRunning, isFalse);
    expect(server.session, isNull);
  });
  test('expiry and explicit stop clear session; restart uses a new secret',
      () async {
    final oldCode = session.connectionCode;
    await server.stop();
    expect(server.session, isNull);
    session = (await server.start() as Ok<PhoneMemoryReadSession>).value;
    expect(session.connectionCode, isNot(oldCode));
    now = now.add(const Duration(minutes: 31));
    expect(server.isRunning, isFalse);
  });
  test('oversized response is bounded and reports fixed error', () async {
    read = (_) async => {
          'episodes': [
            {'narrative': 'x' * 40000}
          ],
          'fragments': [],
          'sagas': []
        };
    final result = await request();
    expect(result.$1, 503);
    expect(result.$2, {
      'error': {'code': 'response_too_large'}
    });
  });
}
