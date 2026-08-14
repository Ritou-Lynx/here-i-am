/// Safe HTTP client for link ingestion.
///
/// Enforces the security boundaries required by the W3 contract:
///   - Only http/https schemes;
///   - DNS-level SSRF protection: every host (initial URL and each
///     redirect hop) is resolved and every returned address is checked
///     against loopback / private / link-local / unspecified / multicast /
///     reserved / cloud-metadata blocklists for both IPv4 and IPv6. If ANY
///     resolved address is dangerous the request fails.
///   - Redirect host re-checked against the same allowlist on every hop;
///   - Connect / receive timeouts;
///   - True streaming max response body: `Content-Length` pre-check rejects
///     oversize responses before reading; the stream is read in raw bytes
///     and cancelled the moment the accumulated byte count exceeds the cap,
///     so oversized content never fully enters memory and the limit is
///     counted in bytes, not Dart characters;
///   - MIME type validation (must be HTML or XML-ish for web ingestion);
///   - Max redirect count;
///   - Retry with backoff (limited); policy errors are never retried.
///
/// ## DNS rebinding
///
/// This client validates DNS at request time and before each redirect hop,
/// but it does NOT pin the connection to a validated address. There is a
/// time-of-check/time-of-use window between resolution+validation and the
/// actual TCP/TLS connection (DNS can be re-answered differently). See
/// `_checkDns` and the W3 handoff for the honest statement of this limit.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Resolves a hostname to its IP addresses.
///
/// Injectable so tests can control resolution without real DNS. Production
/// uses [SystemDnsResolver].
abstract class DnsResolver {
  /// Resolves [host] to its addresses. Throws on resolution failure.
  Future<List<InternetAddress>> lookup(String host);
}

/// Production DNS resolver backed by `dart:io`.
class SystemDnsResolver implements DnsResolver {
  const SystemDnsResolver();

  @override
  Future<List<InternetAddress>> lookup(String host) =>
      InternetAddress.lookup(host);
}

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

  /// Max response body size in **raw bytes**.
  final int maxBodyBytes;

  /// Max retries on transient failures.
  final int maxRetries;

  /// Allowed response MIME types (prefix match).
  final Set<String> allowedMimePrefixes;

  /// User-Agent string.
  final String userAgent;

  /// Whether to resolve and blocklist-check DNS for every host (initial URL
  /// and each redirect hop) before connecting. **Defaults to true** —
  /// production SSRF protection. Setting this to `false` is only allowed for
  /// explicit test configuration that injects a mock transport; it must never
  /// be the production default.
  final bool enforceDnsCheck;

  const SafeHttpConfig({
    this.maxRedirects = 5,
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 15),
    this.maxBodyBytes = 2 * 1024 * 1024, // 2 MB raw bytes
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
/// Wraps a [Dio] instance. Tests inject a mock dio and (optionally) a mock
/// [DnsResolver]; production callers use the default constructor, which
/// enables DNS check with [SystemDnsResolver].
class SafeHttpClient {
  SafeHttpClient({
    Dio? dio,
    SafeHttpConfig config = SafeHttpConfig.defaultConfig,
    DnsResolver? resolver,
  })  : _dio = dio ??
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
        _config = config,
        _resolver = resolver ?? const SystemDnsResolver();

  final Dio _dio;
  final SafeHttpConfig _config;
  final DnsResolver _resolver;

  /// Fetches [url], following redirects up to [_config.maxRedirects].
  ///
  /// Every hop (initial URL and each redirect target) is passed through
  /// [validateHost] before connecting. Returns [SafeHttpResult.failure] for
  /// any policy violation (SSRF via literal or DNS, oversized body, wrong
  /// MIME, too many redirects, timeout). Never throws.
  Future<SafeHttpResult> fetch(String url) async {
    String currentUrl = url;
    int redirects = 0;

    while (true) {
      final violation = await _validateHost(currentUrl);
      if (violation != null) {
        return SafeHttpResult.failure(violation);
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
        // The next loop iteration re-runs _validateHost (literal + DNS) on
        // the redirect target before any connection is attempted.
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
  // Host validation (literal blocklist + DNS check)
  // -----------------------------------------------------------------------

  /// Returns an error string if [url] violates the SSRF policy, else null.
  ///
  /// Two layers:
  ///   1. Synchronous literal check — scheme allowlist, literal
  ///      private/loopback/metadata hosts.
  ///   2. DNS resolution (when [SafeHttpConfig.enforceDnsCheck] is true) —
  ///      every resolved address must be public; any dangerous address
  ///      fails the whole request.
  Future<String?> _validateHost(String url) async {
    final literalViolation = _validateUrlLiteral(url);
    if (literalViolation != null) return literalViolation;
    if (_config.enforceDnsCheck) {
      final host = Uri.parse(url).host;
      return _checkDns(host);
    }
    return null;
  }

  Future<String?> _checkDns(String host) async {
    final List<InternetAddress> addresses;
    try {
      addresses = await _resolver.lookup(host);
    } catch (e) {
      return 'DNS resolution failed for host $host';
    }
    for (final addr in addresses) {
      if (_isBlockedAddress(addr)) {
        return 'SSRF blocked: host $host resolves to dangerous address ${addr.address}';
      }
    }
    return null;
  }

  String? _validateUrlLiteral(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return 'Invalid URL: $url';
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return 'Disallowed scheme: $scheme';
    }
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return 'Empty host in URL: $url';
    if (_isBlockedHostLiteral(host)) {
      return 'SSRF blocked: host $host is private/loopback/metadata';
    }
    return null;
  }

  bool _isBlockedHostLiteral(String host) {
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
      return _isBlockedIpv4(ipv4);
    }
    // IPv6 literal.
    final ipv6 = _parseIpv6Literal(host);
    if (ipv6 != null) {
      return _isBlockedIpv6(ipv6);
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

  /// Parses a raw IPv6 literal host (may include brackets) to 16 bytes, or
  /// null when it's not a literal IPv6 address.
  List<int>? _parseIpv6Literal(String host) {
    var h = host.replaceAll('[', '').replaceAll(']', '');
    // Strip zone id (fe80::1%eth0).
    final zoneIdx = h.indexOf('%');
    if (zoneIdx >= 0) h = h.substring(0, zoneIdx);
    final addr = InternetAddress.tryParse(h);
    if (addr == null || addr.type != InternetAddressType.IPv6) return null;
    return addr.rawAddress;
  }

  /// True when ANY address in [addresses] is dangerous (used by DNS path:
  /// mixed public + private → fail).
  bool _isBlockedAddress(InternetAddress addr) {
    if (addr.type == InternetAddressType.IPv4) {
      return _isBlockedIpv4(addr.rawAddress);
    }
    if (addr.type == InternetAddressType.IPv6) {
      return _isBlockedIpv6(addr.rawAddress);
    }
    return false;
  }

  /// IPv4 blocklist, operates on 4 raw bytes.
  ///
  /// Blocks: unspecified (0/8), loopback (127/8), private (10/8, 172.16/12,
  /// 192.168/16), CGNAT (100.64/10), link-local + metadata (169.254/16),
  /// IETF protocol assignments / TEST-NET (192.0.0/24, 192.0.2/24,
  /// 198.18/15, 198.51.100/24, 203.0.113/24), multicast (224/4), reserved
  /// (240/4).
  bool _isBlockedIpv4(List<int> b) {
    if (b[0] == 0) return true; // 0.0.0.0/8 unspecified
    if (b[0] == 127) return true; // 127.0.0.0/8 loopback
    if (b[0] == 10) return true; // 10.0.0.0/8 private
    if (b[0] == 100 && (b[1] & 0xC0) == 64) return true; // 192.0.2.1/10 CGNAT
    if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true; // 172.16/12
    if (b[0] == 192 && b[1] == 168) return true; // 192.168.0.0/16
    if (b[0] == 169 && b[1] == 254) return true; // 169.254/16 link-local+metadata
    if (b[0] == 192 && b[1] == 0) return true; // 192.0.0.0/24 + TEST-NET-1
    if (b[0] == 198 && (b[1] == 18 || b[1] == 19)) return true; // 198.18/15
    if (b[0] == 198 && b[1] == 51 && b[2] == 100) return true; // TEST-NET-2
    if (b[0] == 203 && b[1] == 0 && b[2] == 113) return true; // TEST-NET-3
    if (b[0] >= 224) return true; // multicast 224/4 + reserved 240/4
    return false;
  }

  /// IPv6 blocklist, operates on 16 raw bytes.
  ///
  /// Blocks: ::/8 (unspecified + loopback ::1 + other reserved),
  /// IPv4-mapped ::ffff:0:0/96 (re-checks embedded IPv4), fe80::/10
  /// link-local, fc00::/7 ULA, ff00::/8 multicast.
  bool _isBlockedIpv6(List<int> b) {
    // IPv4-mapped IPv6 (::ffff:0:0/96) — re-check the embedded IPv4.
    final leadingZeros = b.sublist(0, 10).every((x) => x == 0);
    if (leadingZeros && b[10] == 0xFF && b[11] == 0xFF) {
      return _isBlockedIpv4([b[12], b[13], b[14], b[15]]);
    }
    if (b[0] == 0) return true; // ::/8 reserved (covers :: and ::1)
    if (b[0] == 0xFE && (b[1] & 0xC0) == 0x80) return true; // fe80::/10
    if ((b[0] & 0xFE) == 0xFC) return true; // fc00::/7 ULA
    if (b[0] == 0xFF) return true; // ff00::/8 multicast
    return false;
  }

  // -----------------------------------------------------------------------
  // Single request with true streaming byte cap
  // -----------------------------------------------------------------------

  Future<SafeHttpResult> _fetchOnce(String url) async {
    final cancelToken = CancelToken();
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(responseType: ResponseType.stream),
        cancelToken: cancelToken,
      );

      final status = response.statusCode ?? 200;
      final contentType = response.headers.value('content-type') ?? '';
      final mime = contentType.split(';').first.trim().toLowerCase();
      final location = response.headers.value('location');

      // Redirect: no body needed, just return location.
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

      final responseBody = response.data;
      if (responseBody == null) {
        return const SafeHttpResult.failure('Empty response body');
      }

      // Content-Length pre-check: reject before reading anything. Dio
      // reports -1 when the header is absent.
      final contentLength = responseBody.contentLength;
      if (contentLength > 0 && contentLength > _config.maxBodyBytes) {
        cancelToken.cancel();
        return SafeHttpResult.failure(
            'Response body exceeds max size (${_config.maxBodyBytes} bytes)');
      }

      // Stream the body in raw bytes, counting bytes (not characters).
      // The moment the count exceeds the cap we stop reading — oversized
      // content never fully enters memory.
      final builder = BytesBuilder(copy: false);
      var received = 0;
      var overLimit = false;
      await for (final chunk in responseBody.stream) {
        received += chunk.length;
        if (received > _config.maxBodyBytes) {
          overLimit = true;
          cancelToken.cancel();
          break;
        }
        builder.add(chunk);
      }
      if (overLimit) {
        return SafeHttpResult.failure(
            'Response body exceeds max size (${_config.maxBodyBytes} bytes)');
      }

      // Decode only after the body is confirmed within the limit.
      final body = utf8.decode(builder.takeBytes(), allowMalformed: true);

      return SafeHttpResult.ok(
        body: body,
        finalUrl: response.realUri.toString(),
        mimeType: mime,
        statusCode: status,
      );
    } on DioException catch (e) {
      if (cancelToken.isCancelled) {
        return SafeHttpResult.failure(
            'Response body exceeds max size (${_config.maxBodyBytes} bytes)');
      }
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

  bool _isRedirect(int status) =>
      status == 301 || status == 302 || status == 303 ||
      status == 307 || status == 308;

  bool _isPolicyError(String? message) {
    if (message == null) return false;
    return message.startsWith('SSRF blocked:') ||
        message.startsWith('DNS resolution failed') ||
        message.startsWith('Disallowed scheme:') ||
        message.startsWith('Unsupported MIME type:') ||
        message.startsWith('Response body exceeds max size') ||
        message.startsWith('Too many redirects') ||
        message.startsWith('Redirect') && message.contains('without Location');
  }
}