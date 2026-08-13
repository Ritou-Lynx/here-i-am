import 'package:dio/dio.dart';
import 'package:memex/data/services/sync/core_sync_protocol.dart';

/// Typed transport for the private i core API v0 (CORE_API_V0).
///
/// Speaks to `tools/i_core/i_core_server.mjs` over Tailscale HTTPS + JSON.
/// Uses the wire models from [CoreSyncProtocol] verbatim; local integer
/// database ids never appear on the wire. Errors are surfaced as typed
/// [CoreSyncException]s so the sync loop can decide whether to retry.
class CoreSyncClient {
  CoreSyncClient({
    required this.baseUrl,
    required this.deviceId,
    required this.deviceToken,
    this.protocolVersion = CoreSyncProtocol.version,
    Dio? dio,
  }) : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 15),
              headers: {
                'Authorization': 'Bearer $deviceToken',
                'X-Core-Protocol': protocolVersion,
              },
            ));

  final String baseUrl;
  final String deviceId;
  final String deviceToken;

  /// Wire protocol version. Overridable for tests exercising mismatch paths.
  final String protocolVersion;
  final Dio _dio;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$base${CoreSyncProtocol.basePath}/$path')
        .replace(queryParameters: query);
  }

  Future<CoreHealthResponse> health() async {
    final body = await _guard(() => _dio.getUri<Map<String, dynamic>>(
          _uri('health'),
          options: Options(responseType: ResponseType.json),
        ));
    return CoreHealthResponse.fromJson(body);
  }

  Future<CoreChatSubmitResponse> submitMessages(
    CoreChatSubmitRequest request,
  ) async {
    final body = await _guard(() => _dio.postUri<Map<String, dynamic>>(
          _uri('chat/messages'),
          data: request.toJson(),
          options: Options(
            contentType: Headers.jsonContentType,
            responseType: ResponseType.json,
          ),
        ));
    return CoreChatSubmitResponse.fromJson(body);
  }

  Future<CoreChangePage> fetchChanges({
    required String cursor,
    int limit = 100,
  }) async {
    final body = await _guard(() => _dio.getUri<Map<String, dynamic>>(
          _uri('changes', {'cursor': cursor, 'limit': '$limit'}),
          options: Options(responseType: ResponseType.json),
        ));
    return CoreChangePage.fromJson(body);
  }

  Future<void> acknowledgeCursor({
    required String cursor,
  }) async {
    await _guard(() => _dio.postUri<Map<String, dynamic>>(
          _uri('devices/ack'),
          data: CoreCursorAckRequest(deviceId: deviceId, cursor: cursor)
              .toJson(),
          options: Options(
            contentType: Headers.jsonContentType,
            responseType: ResponseType.json,
          ),
        ));
  }

  /// Runs [call] (a dio request) and normalizes transport + protocol failures
  /// into a typed [CoreSyncException]. Returns the decoded response body.
  /// Non-2xx bodies follow the v0 error envelope
  /// `{error: {code, message, retryable, details}}`.
  Future<Map<String, dynamic>> _guard(
    Future<Response<Map<String, dynamic>>> Function() call,
  ) async {
    try {
      final response = await call();
      return response.data ?? const {};
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map) {
        final error = body['error'];
        if (error is Map) {
          throw CoreSyncException(
            code: error['code']?.toString() ?? 'unknown',
            message: error['message']?.toString() ?? e.message ?? 'Core error',
            retryable: error['retryable'] == true,
            statusCode: e.response?.statusCode,
          );
        }
      }
      // Transport-level failure (timeout, connection refused, TLS).
      throw CoreSyncException(
        code: 'transport_error',
        message: e.message ?? 'Failed to reach i core',
        retryable: e.type != DioExceptionType.badResponse,
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Convenience for manual pairing against a fresh core (debug / test use).
  static Future<CoreDevicePairResponse> pair({
    required String baseUrl,
    required CoreDevicePairRequest request,
    Dio? dio,
  }) async {
    final client = dio ??
        Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));
    final normalizedBase =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final url = '$normalizedBase${CoreSyncProtocol.basePath}/devices/pair';
    final response = await client.post<Map<String, dynamic>>(
      url,
      data: request.toJson(),
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );
    return CoreDevicePairResponse.fromJson(response.data!);
  }
}

/// Typed failure from the i core API.
///
/// [retryable] mirrors the server envelope: only retryable errors should be
/// retried with backoff. 401 / 409 / protocol mismatches are terminal.
class CoreSyncException implements Exception {
  const CoreSyncException({
    required this.code,
    required this.message,
    required this.retryable,
    this.statusCode,
  });

  final String code;
  final String message;
  final bool retryable;
  final int? statusCode;

  @override
  String toString() =>
      'CoreSyncException($code, retryable=$retryable, http=$statusCode): $message';
}
