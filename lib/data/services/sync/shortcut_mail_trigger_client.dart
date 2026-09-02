import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// A separately-scoped credential for the explicit iOS Shortcut mail test.
///
/// This deliberately does not share the core sync device token: the test
/// endpoint receives only this narrowly-issued token.
class ShortcutMailTestTokenStore {
  ShortcutMailTestTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'i_shortcut_mail_manual_test_token_v0';
  final FlutterSecureStorage _storage;

  Future<String?> readForCore(String coreNodeId) async {
    final encoded = await _storage.read(key: _key);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final value = jsonDecode(encoded);
      if (value is! Map || value['core_node_id'] != coreNodeId) return null;
      final token = value['token'];
      return token is String && token.isNotEmpty ? token : null;
    } catch (_) {
      // Never send a malformed or unbound value to a possibly different core.
      return null;
    }
  }

  Future<void> saveForCore({
    required String token,
    required String coreNodeId,
  }) =>
      _storage.write(
        key: _key,
        value: jsonEncode({
          'version': 1,
          'core_node_id': coreNodeId,
          'token': token,
        }),
      );

  Future<void> clear() => _storage.delete(key: _key);
}

/// Persists only the last manual-test idempotency key so an uncertain request
/// can be inspected after an app restart. It is never used to resend a test.
class ShortcutMailTestRequestStore {
  ShortcutMailTestRequestStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'i_shortcut_mail_manual_test_last_request_v0';
  final FlutterSecureStorage _storage;

  Future<_ShortcutMailPendingRequest?> _read() async {
    final encoded = await _storage.read(key: _key);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final value = jsonDecode(encoded);
      if (value is! Map || value['version'] != 1) return null;
      final coreNodeId = value['core_node_id'];
      final tokenFingerprint = value['token_fingerprint'];
      final idempotencyKey = value['idempotency_key'];
      if (coreNodeId is! String ||
          coreNodeId.isEmpty ||
          tokenFingerprint is! String ||
          tokenFingerprint.isEmpty ||
          idempotencyKey is! String ||
          idempotencyKey.isEmpty) {
        return null;
      }
      return _ShortcutMailPendingRequest(
        coreNodeId: coreNodeId,
        tokenFingerprint: tokenFingerprint,
        idempotencyKey: idempotencyKey,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> readForScope({
    required String coreNodeId,
    required String scopedTestToken,
  }) async {
    final pending = await _read();
    if (pending == null ||
        pending.coreNodeId != coreNodeId ||
        pending.tokenFingerprint != _fingerprint(scopedTestToken)) {
      return null;
    }
    return pending.idempotencyKey;
  }

  /// Explicitly starts a new token/core cycle. Saving the same token retains
  /// its pending key; a genuinely new scope discards the old cycle.
  Future<void> prepareScope({
    required String coreNodeId,
    required String scopedTestToken,
  }) async {
    final pending = await _read();
    if (pending != null &&
        pending.coreNodeId == coreNodeId &&
        pending.tokenFingerprint == _fingerprint(scopedTestToken)) {
      return;
    }
    await clear();
  }

  Future<void> reserve({
    required String coreNodeId,
    required String scopedTestToken,
    required String idempotencyKey,
  }) async {
    final pending = await _read();
    final fingerprint = _fingerprint(scopedTestToken);
    if (pending != null) {
      if (pending.coreNodeId == coreNodeId &&
          pending.tokenFingerprint == fingerprint &&
          pending.idempotencyKey == idempotencyKey) {
        return;
      }
      throw StateError('已有另一项邮件测试 request，不能覆盖');
    }
    await _storage.write(
      key: _key,
      value: jsonEncode({
        'version': 1,
        'core_node_id': coreNodeId,
        'token_fingerprint': fingerprint,
        'idempotency_key': idempotencyKey,
      }),
    );
  }

  Future<void> clear() => _storage.delete(key: _key);

  static String _fingerprint(String token) =>
      sha256.convert(utf8.encode(token)).toString();
}

class _ShortcutMailPendingRequest {
  const _ShortcutMailPendingRequest({
    required this.coreNodeId,
    required this.tokenFingerprint,
    required this.idempotencyKey,
  });

  final String coreNodeId;
  final String tokenFingerprint;
  final String idempotencyKey;
}

enum ShortcutMailReceiptStatus {
  reserved,
  sendStarted,
  providerAccepted,
  failedBeforeSend,
  outcomeUnknown;

  static ShortcutMailReceiptStatus parse(Object? value) {
    return switch (value) {
      'reserved' => reserved,
      'send_started' => sendStarted,
      'provider_accepted' => providerAccepted,
      'failed_before_send' => failedBeforeSend,
      'outcome_unknown' => outcomeUnknown,
      _ => throw FormatException('未知的邮件测试状态：$value'),
    };
  }
}

class ShortcutMailReceipt {
  const ShortcutMailReceipt({
    required this.receiptId,
    required this.idempotencyKey,
    required this.subjectCode,
    required this.replay,
    required this.status,
    this.requestedAt,
    this.updatedAt,
    this.recipientHint,
    this.message,
  });

  final String receiptId;
  final String idempotencyKey;
  final String subjectCode;
  final bool replay;
  final ShortcutMailReceiptStatus status;
  final DateTime? requestedAt;
  final DateTime? updatedAt;
  final String? recipientHint;
  final String? message;

  factory ShortcutMailReceipt.fromJson(Map<String, dynamic> json) {
    final source = json['receipt'] is Map
        ? Map<String, dynamic>.from(json['receipt'] as Map)
        : json;
    final key = source['idempotency_key'] ?? source['idempotencyKey'];
    if (key is! String || key.isEmpty) {
      throw const FormatException('回执缺少 idempotency_key');
    }
    final receiptId = source['receipt_id'] ?? source['receiptId'];
    if (receiptId is! String || receiptId.isEmpty) {
      throw const FormatException('回执缺少 receipt_id');
    }
    final subjectCode = source['subject_code'] ?? source['subjectCode'];
    if (subjectCode != 'sleep_chat_v0') {
      throw const FormatException('回执 subject_code 不符合固定模板');
    }
    if (source['replay'] is! bool) {
      throw const FormatException('回执 replay 必须是布尔值');
    }
    return ShortcutMailReceipt(
      receiptId: receiptId,
      idempotencyKey: key,
      subjectCode: subjectCode,
      replay: source['replay'] as bool,
      status: ShortcutMailReceiptStatus.parse(source['status']),
      requestedAt: _optionalTimestamp(
        source['requested_at'] ?? source['requestedAt'],
        'requested_at',
      ),
      updatedAt: _optionalTimestamp(
        source['updated_at'] ?? source['updatedAt'],
        'updated_at',
      ),
      recipientHint: _optionalString(
        source['receiver_hint'] ??
            source['receiverHint'] ??
            source['recipient_hint'] ??
            source['recipientHint'],
      ),
      message: _optionalString(source['message']),
    );
  }

  static String? _optionalString(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static DateTime? _optionalTimestamp(Object? value, String field) {
    if (value == null) return null;
    if (value is! String || value.isEmpty) {
      throw FormatException('回执 $field 必须是 ISO-8601 时间');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw FormatException('回执 $field 格式不正确');
    return parsed;
  }
}

class ShortcutMailTriggerException implements Exception {
  const ShortcutMailTriggerException({
    required this.message,
    this.statusCode,
    this.requestId,
    this.traceId,
    this.code,
  });

  final String message;
  final int? statusCode;
  final String? requestId;
  final String? traceId;
  final String? code;

  @override
  String toString() => 'ShortcutMailTriggerException($message)';
}

/// Client for the one explicit manual Shortcut email test.
///
/// Requests are intentionally single-attempt. A caller can retain the returned
/// idempotency key after a timeout and query the receipt instead of resending.
class ShortcutMailTriggerClient {
  ShortcutMailTriggerClient({
    required String baseUrl,
    required String scopedTestToken,
    required String requestScope,
    Dio? dio,
    Uuid? uuid,
    ShortcutMailTestRequestStore? requestStore,
  })  : _baseUrl = _normalizeBaseUrl(baseUrl),
        _scopedTestToken = scopedTestToken,
        _requestScope = requestScope,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                sendTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
              ),
            ),
        _uuid = uuid ?? const Uuid(),
        _requestStore = requestStore ?? ShortcutMailTestRequestStore();

  final String _baseUrl;
  final String _scopedTestToken;
  final String _requestScope;
  final Dio _dio;
  final Uuid _uuid;
  final ShortcutMailTestRequestStore _requestStore;

  Future<ShortcutMailReceipt> sendManualTest({String? idempotencyKey}) async {
    final pending = await _requestStore.readForScope(
      coreNodeId: _requestScope,
      scopedTestToken: _scopedTestToken,
    );
    if (idempotencyKey != null &&
        pending != null &&
        idempotencyKey != pending) {
      throw StateError('不能用新的 idempotency key 覆盖待查询 request');
    }
    final key = pending ?? idempotencyKey ?? _uuid.v4();
    // Reserve before the one permitted attempt, including if its outcome times out.
    await _requestStore.reserve(
      coreNodeId: _requestScope,
      scopedTestToken: _scopedTestToken,
      idempotencyKey: key,
    );
    return _request(
      () => _dio.postUri<Map<String, dynamic>>(
        _endpoint(),
        data: const {'trigger': 'ios_shortcut_test_v0'},
        options: _options(idempotencyKey: key),
      ),
      fallbackRequestId: key,
    );
  }

  Future<ShortcutMailReceipt> queryReceipt(String idempotencyKey) {
    if (idempotencyKey.isEmpty) {
      throw ArgumentError.value(idempotencyKey, 'idempotencyKey', '不能为空');
    }
    return _request(
      () => _dio.getUri<Map<String, dynamic>>(
        _endpoint('receipts/${Uri.encodeComponent(idempotencyKey)}'),
        options: _options(),
      ),
      fallbackRequestId: idempotencyKey,
    );
  }

  Uri _endpoint([String? suffix]) {
    final path = suffix == null
        ? '/v1/core/actions/shortcut-email/manual-test'
        : '/v1/core/actions/shortcut-email/manual-test/$suffix';
    return Uri.parse('$_baseUrl$path');
  }

  Options _options({String? idempotencyKey}) => Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        headers: {
          'Authorization': 'Bearer $_scopedTestToken',
          'X-Core-Protocol': '0.1',
          if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
        },
      );

  Future<ShortcutMailReceipt> _request(
    Future<Response<Map<String, dynamic>>> Function() call, {
    required String fallbackRequestId,
  }) async {
    try {
      final response = await call();
      final receipt = ShortcutMailReceipt.fromJson(response.data ?? const {});
      if (receipt.idempotencyKey != fallbackRequestId) {
        throw const FormatException('回执 idempotency_key 与本次请求不一致');
      }
      return receipt;
    } on DioException catch (error) {
      throw ShortcutMailTriggerException(
        message: _errorMessage(error),
        statusCode: error.response?.statusCode,
        requestId: fallbackRequestId,
        traceId: error.response?.headers.value('x-request-id'),
        code: _errorCode(error),
      );
    } on FormatException catch (error) {
      throw ShortcutMailTriggerException(
        message: error.message,
        requestId: fallbackRequestId,
      );
    }
  }

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) throw const FormatException('核心地址不能为空');
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  static String _errorMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['error'] is Map) {
      final message = (data['error'] as Map)['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    return error.message ?? '无法联系核心服务';
  }

  static String? _errorCode(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['error'] is Map) {
      final code = (data['error'] as Map)['code'];
      if (code is String && code.isNotEmpty) return code;
    }
    return null;
  }
}
