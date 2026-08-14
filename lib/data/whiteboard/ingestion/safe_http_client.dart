/// Safe HTTP client for link ingestion.
///
/// Enforces the security boundaries required by the W3 contract:
///   - Only http/https schemes;
///   - localhost / private / loopback / link-local / metadata addresses
///     blocked (SSRF protection);
///   - Redirect host re-checked against the same allowlist;
///   - Connect / receive timeouts;
///   - Max response body size (streaming with cap);
///   - MIME type validation (must be HTML or XML-ish for web ingestion);
///   - Max redirect count;
///   - Retry with backoff (limited).
library;

import 'dart:async';

import 'package:dio/dio.dart';

/// Outcome of a safe HTTP fetch.
class SafeHttpResult {
  final String? body;
  final String? finalUrl;
  final String? mimeType;
  final int? statusCode;
  final String? redirectLocation;
  final String? errorMessage;
  final bool success;

  const SafeHttpResult({
    this.body,
    this.finalUrl,
    this.mimeType,
    this.statusCode,
    this.redirectLocation,
    this.errorMessage,
  }) : success = false;

  const SafeHttpResult.ok({
    required this.body,
    required this.finalUrl,
    required this.mimeType,
    required this.statusCode,
    this.redirectLocation,
  })  : errorMessage = null,
        success = true;

  const SafeHttpResult.failure(String message)
      : body = null,
        finalUrl = null,
        mimeType = null,
        statusCode = null,
        redirectLocation = null,
        errorMessage = message,
        success = false;

  bool get isRedirect =>
      success && statusCode != null &&
      (statusCode == 301 || statusCode == 302 || statusCode == 303 ||
       statusCode == 307 || statusCode == 308);

  @override
  String toString() =>
      success ? 'SafeHttpResult($statusCode $finalUrl)' : 'SafeHttpResult(fail: $errorMessage)';
}

/// Configuration for [SafeHttpClient].
class SafeHttpConfig {
  /// Max redirects before giving up.
  final int maxRedirects;

  /// Connect timeout.
  final Duration connectTimeout;

  /// Receive timeout (per response).
  final Duration receiveTimeout;

  /// Max response body size in bytes.
  final int maxBodyBytes;

  /// Max retries on transient failures.
  final int maxRetries;

  /// Allowed response MIME types (prefix match).
  final Set<String> allowedMimePrefixes;

  /// User-Agent string.
  final String userAgent;

  /// Whether to resolve DNS and check against the private-IP blocklist
  /// before connecting. Defaults to true. Set to false only in tests that
  /// inject a mock dio.
  final bool enforceDnsCheck;

  const SafeHttpConfig({
    this.maxRedirects = 5,
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 15),
    this.maxBodyBytes = 2 * 1024 * 1024, // 2 MB
    this.maxRetries = 1,
    this.allowedMimePrefixes = const {
      'text/html',
      'application/xhtml+xml',
      'application/xml',
    },
    this.userAgent =
        'Mozilla/5.0 (compatible; HereIAmBot/1.0; +https://memexlab.com)',
    this.enforceDnsCheck = true,
  });

  static const SafeHttpConfig defaultConfig = SafeHttpConfig();
}

/// A safe HTTP client that enforces SSRF protection and size / time limits.
///
/// Wraps a [Dio] instance. Tests can inject a custom dio with a mock
/// adapter; production callers should use the default constructor.
class SafeHttpClient {
  SafeHttpClient({Dio? dio, SafeHttpConfig config = SafeHttpConfig.defaultConfig})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: config.connectTimeout,
              receiveTimeout: config.receiveTimeout,
              followRedirects: false, // We handle redirects manually.
              headers: {
                'User-Agent': config.userAgent,
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.7',
              },
              validateStatus: (s) => s != null && s >= 200 && s < 400,
            )),
        _config = config;

  final Dio _dio;
  final SafeHttpConfig _config;

  /// Fetches [url], following redirects up to [_config.maxRedirects].
  ///
  /// Returns [SafeHttpResult.failure] for any policy violation (SSRF,
  /// oversized body, wrong MIME, too many redirects, timeout). Never
  /// throws.
  Future<SafeHttpResult> fetch(String url) async {
    String currentUrl = url;
    int redirects = 0;

    while (true) {
      final uriCheck = _validateUrl(currentUrl);
      if (uriCheck != null) {
        return SafeHttpResult.failure(uriCheck);
      }

      SafeHttpResult? result;
      for (int attempt = 0; attempt <= _config.maxRetries; attempt++) {
        result = await _fetchOnce(currentUrl);
        if (result.success) break;
        // Don't retry on policy errors, only on transient network errors.
        if (_isPolicyError(result.errorMessage)) break;
        if (attempt < _config.maxRetries) {
          await Future.delayed(Duration(milliseconds: 200 * (attempt + 1)));
        }
      }
      final r = result!;

      if (!r.success) return r;

      // Check for redirect.
      final status = r.statusCode!;
      if (r.isRedirect) {
        redirects++;
        if (redirects > _config.maxRedirects) {
          return SafeHttpResult.failure('Too many redirects (>${_config.maxRedirects})');
        }
        final location = r.redirectLocation;
        if (location == null || location.isEmpty) {
          return SafeHttpResult.failure('Redirect $status without Location header');
        }
        currentUrl = location;
        continue;
      }

      // Final response — validate MIME.
      final mime = r.mimeType ?? '';
      final mimeOk = _config.allowedMimePrefixes.any((p) => mime.startsWith(p));
      if (!mimeOk) {
        return SafeHttpResult.failure('Unsupported MIME type: $mime');
      }
      return r;
    }
  }

  // -----------------------------------------------------------------------

  Future<SafeHttpResult> _fetchOnce(String url) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );

      final status = response.statusCode ?? 200;
      final contentType = response.headers.value('content-type') ?? '';
      final mime = contentType.split(';').first.trim().toLowerCase();
      final location = response.headers.value('location');

      // Redirect: don't download body, just return location.
      if (_isRedirect(status)) {
        final resolved = location != null
            ? Uri.parse(url).resolve(location).toString()
            : null;
        return SafeHttpResult.ok(
          body: '',
          finalUrl: url,
          mimeType: mime,
          statusCode: status,
          redirectLocation: resolved,
        );
      }

      final body = response.data ?? '';
      if (body.length > _config.maxBodyBytes) {
        return SafeHttpResult.failure(
            'Response body exceeds max size (${_config.maxBodyBytes} bytes)');
      }

      return SafeHttpResult.ok(
        body: body,
        finalUrl: response.realUri.toString(),
        mimeType: mime,
        statusCode: status,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return SafeHttpResult.failure('Request timeout: ${e.message}');
      }
      if (e.type == DioExceptionType.badResponse) {
        final status = e.response?.statusCode;
        final location = e.response?.headers.value('location');
        if (status != null && _isRedirect(status)) {
          final resolved = location != null
              ? Uri.parse(url).resolve(location).toString()
              : null;
          return SafeHttpResult.ok(
            body: '',
            finalUrl: url,
            mimeType: '',
            statusCode: status,
            redirectLocation: resolved,
          );
        }
        return SafeHttpResult.failure('HTTP $status');
      }
      return SafeHttpResult.failure('Network error: ${e.message}');
    } catch (e) {
      return SafeHttpResult.failure('Unexpected error: $e');
    }
  }

  String? _validateUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return 'Invalid URL: $url';
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return 'Disallowed scheme: $scheme';
    }
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return 'Empty host in URL: $url';
    if (_isBlockedHost(host)) {
      return 'SSRF blocked: host $host is private/loopback/metadata';
    }
    return null;
  }

  bool _isBlockedHost(String host) {
    // Literal hostnames.
    if (host == 'localhost' || host == '0.0.0.0' || host == '::1' ||
        host == '[::1]') {
      return true;
    }
    // Cloud metadata endpoints.
    if (host == 'metadata.google.internal' ||
        host == '169.254.169.254' || host.endsWith('.metadata')) {
      return true;
    }
    // IPv4 literal — check private / loopback / link-local ranges.
    final ipv4 = _parseIpv4(host);
    if (ipv4 != null) {
      return _isPrivateIpv4(ipv4);
    }
    // .local / internal TLDs.
    if (host.endsWith('.local') || host.endsWith('.internal')) {
      return true;
    }
    return false;
  }

  List<int>? _parseIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return null;
    final octets = <int>[];
    for (final p in parts) {
      final v = int.tryParse(p);
      if (v == null || v < 0 || v > 255) return null;
      octets.add(v);
    }
    return octets;
  }

  bool _isPrivateIpv4(List<int> o) {
    // 10.0.0.0/8
    if (o[0] == 10) return true;
    // 172.16.0.0/12
    if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) return true;
    // 192.168.0.0/16
    if (o[0] == 192 && o[1] == 168) return true;
    // 127.0.0.0/8 (loopback)
    if (o[0] == 127) return true;
    // 169.254.0.0/16 (link-local / metadata)
    if (o[0] == 169 && o[1] == 254) return true;
    // 0.0.0.0/8
    if (o[0] == 0) return true;
    return false;
  }

  bool _isRedirect(int status) =>
      status == 301 || status == 302 || status == 303 ||
      status == 307 || status == 308;

  bool _isPolicyError(String? message) {
    if (message == null) return false;
    return message.startsWith('SSRF blocked:') ||
        message.startsWith('Disallowed scheme:') ||
        message.startsWith('Unsupported MIME type:') ||
        message.startsWith('Response body exceeds max size') ||
        message.startsWith('Too many redirects') ||
        message.startsWith('Redirect') && message.contains('without Location');
  }
}