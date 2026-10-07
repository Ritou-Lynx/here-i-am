import 'dart:convert';
import 'package:dio/dio.dart';
import 'domain_protocol.dart';

/// Credentials are injected by the owner. This adapter neither issues tokens
/// nor falls back to the chat device token or worker secret.
class DomainHttpTransport implements DomainTransport {
  DomainHttpTransport(
      {required String baseUrl,
      required this.token,
      required this.binding,
      this.verifyCredential,
      Dio? dio})
      : base = Uri.parse(baseUrl),
        dio = dio ??
            Dio(BaseOptions(connectTimeout: const Duration(seconds: 15))) {
    final local = base.host == '127.0.0.1' || base.host == 'localhost';
    if (base.scheme != 'https' && !(local && base.scheme == 'http') ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        !['', '/'].contains(base.path)) {
      throw const DomainFailure('invalid_endpoint');
    }
  }
  final Uri base;
  final String token;
  final DomainBinding binding;
  final Dio dio;
  final Future<void> Function()? verifyCredential;
  Future<Json> _call(String method, String domain, String path,
      {Json? data, Json? query}) async {
    if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(domain)) {
      throw const DomainFailure('invalid_domain');
    }
    await verifyCredential?.call();
    final uri = base.replace(
        path: '/v1/core/domains/$domain/$path',
        queryParameters: query?.map((k, v) => MapEntry(k, v.toString())));
    try {
      final response = await dio.requestUri<String>(uri,
          data: data,
          options: Options(
              method: method,
              responseType: ResponseType.plain,
              followRedirects: false,
              validateStatus: (_) => true,
              sendTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: {
                'Authorization': 'Bearer $token',
                'X-I-Core-Domain-Protocol': '1'
              },
              contentType: Headers.jsonContentType));
      final text = response.data ?? '';
      if (utf8.encode(text).length > DomainPolicy.maxPageBytes) {
        throw const DomainFailure('response_too_large');
      }
      final body = jsonObject(jsonDecode(text));
      if (response.statusCode! >= 200 && response.statusCode! < 300 ||
          body['outcome'] != null) {
        return body;
      }
      final error = jsonObject(body['error']);
      final retryHeader = response.headers.value('retry-after');
      final seconds = int.tryParse(retryHeader ?? '');
      final retryAt =
          retryHeader == null ? null : DateTime.tryParse(retryHeader);
      final retryAfter = seconds != null && seconds >= 0
          ? Duration(seconds: seconds)
          : retryAt?.difference(DateTime.now());
      throw DomainFailure(error['code'] as String,
          retryAfter: retryAfter,
          retryable: error['retryable'] == true ||
              response.statusCode! >= 500 ||
              response.statusCode == 429);
    } on DioException {
      throw const DomainFailure('transport_error', retryable: true);
    } on FormatException {
      throw const DomainFailure('invalid_response');
    }
  }

  Json get _query => {'core_instance_id': binding.coreInstanceId};
  @override
  Future<Json> submit(String domain, Json intent) =>
      _call('POST', domain, 'ops', data: intent);
  @override
  Future<Json> operation(String domain, String opId) =>
      _call('GET', domain, 'ops/${Uri.encodeComponent(opId)}', query: _query);
  @override
  Future<Json> changes(String domain, String? cursor) => _call(
      'GET', domain, 'changes',
      query: {..._query, if (cursor != null) 'cursor': cursor, 'limit': 100});
  @override
  Future<Json> snapshot(String domain,
          {String? snapshotToken, String? pageToken}) =>
      _call('GET', domain, 'snapshot', query: {
        ..._query,
        if (snapshotToken != null) 'snapshot_token': snapshotToken,
        if (pageToken != null) 'page_token': pageToken,
        'limit': 100
      });
  @override
  Future<void> acknowledge(String domain, String cursor,
      {String? snapshotId}) async {
    await _call('POST', domain, 'ack', data: {
      'domain_protocol_version': 1,
      ..._query,
      'cursor': cursor,
      if (snapshotId != null) 'snapshot_id': snapshotId
    });
  }
}
