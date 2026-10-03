import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/sync/core_sync_client.dart';
import 'package:memex/data/services/sync/core_sync_protocol.dart';

/// Boots a throwaway i core via the Node harness. Returns base URL + process
/// so the test can terminate it.
Future<(String, Process)> _startCore() async {
  final process = await Process.start(
    'node',
    [
      'test/data/services/sync/_core_server_harness.mjs',
      '654321',
    ],
  );
  final url = await process.stdout
      .transform(utf8.decoder)
      .firstWhere((line) => line.trim().startsWith('http://'));
  return (url.trim(), process);
}

void main() {
  group('bounded connection timeout recovery', () {
    CoreSyncClient client(_ScriptedAdapter adapter) => CoreSyncClient(
          baseUrl: 'https://synthetic.invalid',
          deviceId: 'synthetic-device',
          deviceToken: 'synthetic-token',
          dio: Dio()..httpClientAdapter = adapter,
          connectionTimeoutRetryDelay: Duration.zero,
        );

    test('connection timeout then success retries the same GET once', () async {
      final adapter = _ScriptedAdapter((options, attempt) {
        if (attempt == 1) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
          );
        }
        return _jsonResponse({
          'events': [],
          'next_cursor': 'synthetic-cursor',
          'has_more': false,
        });
      });
      final page =
          await client(adapter).fetchChanges(cursor: 'synthetic-cursor');
      expect(page.events, isEmpty);
      expect(adapter.calls, 2);
      expect(adapter.requests[0].method, 'GET');
      expect(adapter.requests[0].uri, adapter.requests[1].uri);
    });

    test('consecutive connection timeouts stop after exactly two attempts',
        () async {
      final adapter = _ScriptedAdapter((options, _) => throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
          ));
      await expectLater(
          client(adapter).fetchChanges(cursor: 'synthetic-cursor'),
          throwsA(isA<CoreSyncException>()
              .having((e) => e.code, 'code', 'transport_error')
              .having((e) => e.retryable, 'retryable', isTrue)
              .having((e) => e.statusCode, 'status', isNull)));
      expect(adapter.calls, 2);
    });

    for (final entry in {
      401: 'unauthorized',
      409: 'immutable_message_conflict',
      426: 'protocol_mismatch',
    }.entries) {
      test('HTTP ${entry.key} is returned without retry', () async {
        final adapter = _ScriptedAdapter((_, __) => _jsonResponse({
              'error': {
                'code': entry.value,
                'message': 'synthetic failure',
                'retryable': false
              },
            }, status: entry.key));
        await expectLater(
            client(adapter).fetchChanges(cursor: 'synthetic-cursor'),
            throwsA(isA<CoreSyncException>()
                .having((e) => e.code, 'code', entry.value)
                .having((e) => e.statusCode, 'status', entry.key)));
        expect(adapter.calls, 1);
      });
    }

    for (final type in [
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.badCertificate,
      DioExceptionType.connectionError,
      DioExceptionType.cancel,
      DioExceptionType.unknown,
    ]) {
      test('$type is not retried', () async {
        final adapter = _ScriptedAdapter((options, _) => throw DioException(
              requestOptions: options,
              type: type,
            ));
        await expectLater(
            client(adapter).fetchChanges(cursor: 'synthetic-cursor'),
            throwsA(isA<CoreSyncException>()));
        expect(adapter.calls, 1);
      });
    }

    test('invalid successful protocol response is not retried', () async {
      final adapter = _ScriptedAdapter((_, __) => _jsonResponse({}));
      await expectLater(
          client(adapter).fetchChanges(cursor: 'synthetic-cursor'),
          throwsFormatException);
      expect(adapter.calls, 1);
    });

    test('retried POST preserves the complete frozen message body', () async {
      final addenda = <Map<String, dynamic>>[
        {'kind': 'synthetic', 'value': 'original'}
      ];
      final request =
          CoreChatSubmitRequest(deviceId: 'synthetic-device', messages: [
        CoreChatMessageWire(
            syncId: 'synthetic-message',
            originDeviceId: 'synthetic-device',
            originSequence: 42,
            characterId: 'synthetic-character',
            sender: CoreMessageSender.user,
            content: 'synthetic content',
            createdAtMs: 1700000000000,
            addenda: addenda),
      ]);
      final expectedBody = request.toJson();
      final expectedJson = jsonEncode(expectedBody);
      final adapter = _ScriptedAdapter((options, attempt) {
        if (attempt == 1) {
          // Caller-owned nested data may change during the retry backoff.
          addenda.single['value'] = 'changed after first attempt';
          throw DioException(
              requestOptions: options,
              type: DioExceptionType.connectionTimeout);
        }
        return _jsonResponse({
          'results': [
            {
              'sync_id': 'synthetic-message',
              'status': 'accepted',
              'server_sequence': 7,
            }
          ]
        });
      });
      final response = await client(adapter).submitMessages(request);
      expect(response.results.single.syncId, 'synthetic-message');
      expect(adapter.calls, 2);
      expect(adapter.requests.map((r) => r.method), everyElement('POST'));
      expect(adapter.requests[0].uri, adapter.requests[1].uri);
      expect(adapter.bodies, [expectedJson, expectedJson]);
    });

    test('one-time pair remains a single attempt on connection timeout',
        () async {
      final adapter = _ScriptedAdapter((options, _) => throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
          ));
      await expectLater(
          CoreSyncClient.pair(
            baseUrl: 'https://synthetic.invalid',
            dio: Dio()..httpClientAdapter = adapter,
            request: const CoreDevicePairRequest(
                deviceId: 'synthetic-device',
                displayName: 'Synthetic',
                platform: 'test',
                clientVersion: 'test',
                pairingCode: 'synthetic'),
          ),
          throwsA(isA<DioException>()));
      expect(adapter.calls, 1);
    });
  });

  test('pair, submit, fetch changes and ack round-trip against a real core',
      () async {
    final (baseUrl, core) = await _startCore();
    try {
      // Pair a device.
      final pair = await CoreSyncClient.pair(
        baseUrl: baseUrl,
        request: const CoreDevicePairRequest(
          deviceId: 'dart-client-a',
          displayName: 'Dart test client',
          platform: 'test',
          clientVersion: '0.1',
          pairingCode: '654321',
          capabilities: ['chat'],
        ),
      );
      expect(pair.coreNodeId, isNotEmpty);
      expect(pair.protocolVersion, CoreSyncProtocol.version);
      expect(pair.initialCursor, isNotEmpty);

      final client = CoreSyncClient(
        baseUrl: baseUrl,
        deviceId: pair.deviceId,
        deviceToken: pair.deviceToken,
      );

      // Health reports an authority core.
      final health = await client.health();
      expect(health.isAuthority, isTrue);
      expect(health.protocolVersion, CoreSyncProtocol.version);

      // Submit two messages; the second one duplicated is idempotent.
      final submit = await client.submitMessages(CoreChatSubmitRequest(
        deviceId: pair.deviceId,
        messages: [
          CoreChatMessageWire(
            syncId: 'msg-1',
            originDeviceId: pair.deviceId,
            originSequence: 1,
            characterId: 'lin-ai',
            sender: CoreMessageSender.user,
            content: '我到家了',
            createdAtMs: 1786550400000,
          ),
          CoreChatMessageWire(
            syncId: 'msg-2',
            originDeviceId: pair.deviceId,
            originSequence: 2,
            characterId: 'lin-ai',
            sender: CoreMessageSender.user,
            content: '晚饭想吃面',
            createdAtMs: 1786550460000,
          ),
        ],
      ));
      expect(submit.results, hasLength(2));
      expect(submit.results.every((r) => r.status == CoreSubmitStatus.accepted),
          isTrue);
      // server_sequence is strictly increasing by arrival order.
      expect(submit.results[0].serverSequence,
          lessThan(submit.results[1].serverSequence));

      final duplicate = await client.submitMessages(CoreChatSubmitRequest(
        deviceId: pair.deviceId,
        messages: [
          CoreChatMessageWire(
            syncId: 'msg-1',
            originDeviceId: pair.deviceId,
            originSequence: 1,
            characterId: 'lin-ai',
            sender: CoreMessageSender.user,
            content: '我到家了',
            createdAtMs: 1786550400000,
          ),
        ],
      ));
      expect(duplicate.results.single.status, CoreSubmitStatus.duplicate);

      // Change feed replays both messages in server order.
      var page = await client.fetchChanges(cursor: pair.initialCursor);
      final events = [...page.events];
      while (page.hasMore) {
        page = await client.fetchChanges(cursor: page.nextCursor);
        events.addAll(page.events);
      }
      expect(events.map((e) => e.kind), everyElement('chat.message.upsert'));
      expect(events.map((e) => e.entityId), containsAll(['msg-1', 'msg-2']));

      // Ack is accepted.
      await client.acknowledgeCursor(cursor: page.nextCursor);
    } finally {
      core.kill();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('protocol failures surface as typed CoreSyncException', () async {
    final (baseUrl, core) = await _startCore();
    try {
      // Pair, then talk with a garbage token -> 401 unauthorized.
      final pair = await CoreSyncClient.pair(
        baseUrl: baseUrl,
        request: const CoreDevicePairRequest(
          deviceId: 'dart-client-b',
          displayName: 'Dart test client B',
          platform: 'test',
          clientVersion: '0.1',
          pairingCode: '654321',
        ),
      );
      final bad = CoreSyncClient(
        baseUrl: baseUrl,
        deviceId: pair.deviceId,
        deviceToken: 'not-a-real-token',
      );
      // health is public; use an authenticated endpoint to exercise 401.
      await expectLater(
        bad.fetchChanges(cursor: pair.initialCursor),
        throwsA(isA<CoreSyncException>()
            .having((e) => e.code, 'code', 'unauthorized')
            .having((e) => e.retryable, 'retryable', isFalse)),
      );

      // Wrong protocol version -> 426 protocol_mismatch (authenticated
      // endpoint; health is public and skips protocol negotiation).
      final wrongProtocol = CoreSyncClient(
        baseUrl: baseUrl,
        deviceId: pair.deviceId,
        deviceToken: pair.deviceToken,
        protocolVersion: '9.9',
      );
      await expectLater(
        wrongProtocol.fetchChanges(cursor: pair.initialCursor),
        throwsA(isA<CoreSyncException>()
            .having((e) => e.code, 'code', 'protocol_mismatch')),
      );
    } finally {
      core.kill();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}

/// In-process transport following the adapter convention in the adjacent tests.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.respond);
  final ResponseBody Function(RequestOptions options, int attempt) respond;
  final requests = <RequestOptions>[];
  final bodies = <String>[];
  int get calls => requests.length;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    bodies.add(utf8.decode(bytes));
    return respond(options, calls);
  }
}

ResponseBody _jsonResponse(Map<String, dynamic> body, {int status = 200}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
