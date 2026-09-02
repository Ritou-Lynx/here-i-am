import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/sync/shortcut_mail_trigger_client.dart';

void main() {
  group('ShortcutMailTriggerClient', () {
    test('posts only the fixed trigger with scoped authorization', () async {
      final adapter = _RecordingAdapter((options) {
        expect(options.method, 'POST');
        expect(options.uri.toString(),
            'https://core.example/v1/core/actions/shortcut-email/manual-test');
        expect(options.data, {'trigger': 'ios_shortcut_test_v0'});
        expect(options.headers['Authorization'], 'Bearer scoped-only-token');
        expect(options.headers['X-Core-Protocol'], '0.1');
        final key = options.headers['Idempotency-Key'] as String;
        expect(
            RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
                .hasMatch(key),
            isTrue);
        return {
          'receipt': {
            'receipt_id': 'receipt-123',
            'idempotency_key': key,
            'subject_code': 'sleep_chat_v0',
            'replay': false,
            'status': 'provider_accepted',
            'requested_at': '2026-08-30T00:00:00Z',
            'updated_at': '2026-08-30T00:00:01Z',
            'receiver_hint': 'te***@icloud.com',
          },
        };
      });
      final requestStore = _RequestStore();
      final client = ShortcutMailTriggerClient(
        baseUrl: 'https://core.example/',
        scopedTestToken: 'scoped-only-token',
        requestScope: 'core-node-one',
        dio: Dio()..httpClientAdapter = adapter,
        requestStore: requestStore,
      );

      final receipt = await client.sendManualTest();

      expect(receipt.status, ShortcutMailReceiptStatus.providerAccepted);
      expect(receipt.receiptId, 'receipt-123');
      expect(receipt.subjectCode, 'sleep_chat_v0');
      expect(receipt.replay, isFalse);
      expect(receipt.requestedAt, DateTime.utc(2026, 8, 30));
      expect(receipt.recipientHint, 'te***@icloud.com');
      expect(requestStore.saved, receipt.idempotencyKey);
      expect(adapter.calls, 1);
    });

    test('queries an encoded receipt path without resending', () async {
      final adapter = _RecordingAdapter((options) {
        expect(options.method, 'GET');
        expect(
          options.uri.path,
          '/v1/core/actions/shortcut-email/manual-test/receipts/'
          '00000000-0000-4000-8000-000000000000',
        );
        expect(options.headers.containsKey('Idempotency-Key'), isFalse);
        return {
          'receipt_id': 'receipt-456',
          'idempotency_key': '00000000-0000-4000-8000-000000000000',
          'subject_code': 'sleep_chat_v0',
          'replay': true,
          'status': 'outcome_unknown',
        };
      });
      final client = ShortcutMailTriggerClient(
        baseUrl: 'https://core.example',
        scopedTestToken: 'scoped-token',
        requestScope: 'core-node-one',
        dio: Dio()..httpClientAdapter = adapter,
        requestStore: _RequestStore(),
      );

      final receipt = await client.queryReceipt(
        '00000000-0000-4000-8000-000000000000',
      );

      expect(receipt.status, ShortcutMailReceiptStatus.outcomeUnknown);
      expect(adapter.calls, 1);
    });

    test('rejects unknown receipt status', () {
      expect(
        () => ShortcutMailReceipt.fromJson(
          const {
            'receipt_id': 'receipt',
            'idempotency_key': 'request',
            'subject_code': 'sleep_chat_v0',
            'replay': false,
            'status': 'delivered',
          },
        ),
        throwsFormatException,
      );
    });

    test('keeps legacy recipient hint aliases compatible', () {
      for (final entry in const {
        'receiverHint': 'receiver-camel',
        'recipient_hint': 'recipient-snake',
        'recipientHint': 'recipient-camel',
      }.entries) {
        final receipt = ShortcutMailReceipt.fromJson({
          'receipt_id': 'receipt',
          'idempotency_key': 'request',
          'subject_code': 'sleep_chat_v0',
          'replay': false,
          'status': 'provider_accepted',
          entry.key: entry.value,
        });

        expect(receipt.recipientHint, entry.value);
      }
    });

    test('keeps the current request id when an error envelope is returned',
        () async {
      final requestStore = _RequestStore();
      final adapter = _ErrorAdapter();
      final client = ShortcutMailTriggerClient(
        baseUrl: 'https://core.example',
        scopedTestToken: 'scoped-token',
        requestScope: 'core-node-one',
        dio: Dio()..httpClientAdapter = adapter,
        requestStore: requestStore,
      );
      const requestId = '00000000-0000-4000-8000-000000000001';

      await expectLater(
        client.sendManualTest(idempotencyKey: requestId),
        throwsA(
          isA<ShortcutMailTriggerException>()
              .having(
                (error) => error.requestId,
                'idempotency request id',
                requestId,
              )
              .having(
                (error) => error.traceId,
                'transport trace id',
                'proxy-trace-id',
              )
              .having(
                (error) => error.code,
                'typed error code',
                'shortcut_mail_disabled',
              ),
        ),
      );

      expect(requestStore.saved, requestId);
      expect(adapter.calls, 1);
    });

    test('response loss keeps and reuses the original pending request id',
        () async {
      final requestStore = _RequestStore();
      final adapter = _LostThenReplayAdapter();
      final client = ShortcutMailTriggerClient(
        baseUrl: 'https://core.example',
        scopedTestToken: 'scoped-token',
        requestScope: 'core-node-one',
        dio: Dio()..httpClientAdapter = adapter,
        requestStore: requestStore,
      );

      await expectLater(
        client.sendManualTest(),
        throwsA(isA<ShortcutMailTriggerException>()),
      );
      final original = requestStore.saved;
      expect(original, isNotNull);

      final replay = await client.sendManualTest();

      expect(replay.idempotencyKey, original);
      expect(replay.replay, isTrue);
      expect(adapter.keys, [original, original]);
      expect(requestStore.saved, original);
    });
  });
}

class _RequestStore extends ShortcutMailTestRequestStore {
  String? saved;
  String? scope;
  String? token;

  @override
  Future<String?> readForScope({
    required String coreNodeId,
    required String scopedTestToken,
  }) async =>
      scope == coreNodeId && token == scopedTestToken ? saved : null;

  @override
  Future<void> prepareScope({
    required String coreNodeId,
    required String scopedTestToken,
  }) async {
    if (scope != coreNodeId || token != scopedTestToken) saved = null;
    scope = coreNodeId;
    token = scopedTestToken;
  }

  @override
  Future<void> reserve({
    required String coreNodeId,
    required String scopedTestToken,
    required String idempotencyKey,
  }) async {
    if (saved != null &&
        (scope != coreNodeId ||
            token != scopedTestToken ||
            saved != idempotencyKey)) {
      throw StateError('pending conflict');
    }
    scope = coreNodeId;
    token = scopedTestToken;
    saved = idempotencyKey;
  }
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._response);
  final Map<String, dynamic> Function(RequestOptions options) _response;
  int calls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString(
      _encode(_response(options)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _ErrorAdapter implements HttpClientAdapter {
  int calls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString(
      jsonEncode({
        'error': {
          'code': 'shortcut_mail_disabled',
          'message': '核心拒绝了这次测试',
        },
      }),
      503,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        'x-request-id': ['proxy-trace-id'],
      },
    );
  }
}

class _LostThenReplayAdapter implements HttpClientAdapter {
  final List<String> keys = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = options.headers['Idempotency-Key'] as String;
    keys.add(key);
    if (keys.length == 1) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'response lost',
      );
    }
    return ResponseBody.fromString(
      jsonEncode({
        'receipt_id': 'receipt-replayed',
        'idempotency_key': key,
        'subject_code': 'sleep_chat_v0',
        'replay': true,
        'status': 'provider_accepted',
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

String _encode(Map<String, dynamic> value) {
  return jsonEncode(value);
}
