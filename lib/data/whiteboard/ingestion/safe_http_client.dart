/// Safe HTTP client for link ingestion.
///
/// Enforces the security boundaries required by the W3 contract:
///   - Only http/https schemes;
///   - DNS-level SSRF protection: every host (initial URL and each
///     redirect hop) is resolved and every returned address is checked
///     against loopback / private / link-local / unspecified / multicast /
///     reserved / cloud-metadata blocklists for both IPv4 and IPv6. If ANY
///     resolved address is dangerous the request fails.
///   - **DNS rebinding defense (connection pinning)**: the transport
///     connects directly to one verified `InternetAddress`, so DNS is
///     never consulted again at connect time. A rebinding DNS that changes
///     its answers after validation cannot redirect the connection to an
///     unvalidated target. HTTPS keeps SNI + hostname + certificate
///     verification (`SecureSocket.secure(host:)`) — only the TCP endpoint
///     is pinned.
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
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

enum _SafeResponseKind { text, bytes }

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
  final Uint8List? bytes;
  final String? finalUrl;
  final String? mimeType;
  final int? statusCode;
  final String? redirectLocation;
  final String? errorMessage;

  /// True when the failure is an auth / anti-crawler rejection
  /// (HTTP 401 / 403). The application layer maps this to the `needsAuth`
  /// ingestion state.
  final bool authRequired;

  final bool success;

  const SafeHttpResult({
    this.body,
    this.bytes,
    this.finalUrl,
    this.mimeType,
    this.statusCode,
    this.redirectLocation,
    this.errorMessage,
  })  : authRequired = false,
        success = false;

  const SafeHttpResult.ok({
    this.body,
    this.bytes,
    required this.finalUrl,
    required this.mimeType,
    required this.statusCode,
    this.redirectLocation,
  })  : errorMessage = null,
        authRequired = false,
        success = true;

  const SafeHttpResult.failure(String message)
      : body = null,
        bytes = null,
        finalUrl = null,
        mimeType = null,
        statusCode = null,
        redirectLocation = null,
        errorMessage = message,
        authRequired = false,
        success = false;

  const SafeHttpResult.authFailure(String message)
      : body = null,
        bytes = null,
        finalUrl = null,
        mimeType = null,
        statusCode = null,
        redirectLocation = null,
        errorMessage = message,
        authRequired = true,
        success = false;

  bool get isRedirect =>
      success &&
      statusCode != null &&
      (statusCode == 301 ||
          statusCode == 302 ||
          statusCode == 303 ||
          statusCode == 307 ||
          statusCode == 308);

  @override
  String toString() => success
      ? 'SafeHttpResult($statusCode $finalUrl)'
      : 'SafeHttpResult(fail: $errorMessage)';
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

  /// Value for the HTTP `Accept` request header. HTML ingestion keeps its
  /// browser-like default; binary asset callers provide an image-only value.
  final String acceptHeader;

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
    this.acceptHeader =
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    this.enforceDnsCheck = true,
  });

  static const SafeHttpConfig defaultConfig = SafeHttpConfig();

  SafeHttpConfig copyWith({
    int? maxRedirects,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    int? maxBodyBytes,
    int? maxRetries,
    Set<String>? allowedMimePrefixes,
    String? userAgent,
    String? acceptHeader,
    bool? enforceDnsCheck,
  }) {
    return SafeHttpConfig(
      maxRedirects: maxRedirects ?? this.maxRedirects,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      maxBodyBytes: maxBodyBytes ?? this.maxBodyBytes,
      maxRetries: maxRetries ?? this.maxRetries,
      allowedMimePrefixes: allowedMimePrefixes ?? this.allowedMimePrefixes,
      userAgent: userAgent ?? this.userAgent,
      acceptHeader: acceptHeader ?? this.acceptHeader,
      enforceDnsCheck: enforceDnsCheck ?? this.enforceDnsCheck,
    );
  }
}

/// Connect hook: replaces the real TCP (+TLS for https) connect so tests can
/// observe the exact pinned target without touching the network. Production
/// uses the default implementation backed by `Socket` / `SecureSocket`.
typedef SocketConnectFn = Future<Socket> Function({
  required InternetAddress address,
  required int port,
  required String host,
  required bool isSecure,
});

/// The default production connector: TCP to the pinned address, and for
/// https a TLS handshake **over that same socket** with the original
/// hostname (SNI + certificate verification against [host]).
///
/// [host] is the request host; connecting to a validated `InternetAddress`
/// never triggers a second DNS resolution.
Future<Socket> _defaultSocketConnect({
  required InternetAddress address,
  required int port,
  required String host,
  required bool isSecure,
  Duration connectTimeout = const Duration(seconds: 10),
  Duration receiveTimeout = const Duration(seconds: 15),
}) async {
  final task = await Socket.startConnect(address, port);
  final Socket socket;
  try {
    socket = await task.socket.timeout(
      connectTimeout,
      onTimeout: () {
        task.cancel();
        throw SocketException(
            'HTTP connection timed out after $connectTimeout');
      },
    );
  } on SocketException {
    rethrow;
  }
  if (!isSecure) return socket;
  try {
    return await SecureSocket.secure(
      socket,
      host: host,
      onBadCertificate: (_) => false, // Strict: never accept bad certs.
    ).timeout(receiveTimeout);
  } catch (_) {
    socket.destroy();
    rethrow;
  }
}

/// A dio [HttpClientAdapter] whose TCP + TLS endpoint is **pinned** to a
/// pre-validated `InternetAddress`.
///
/// - Every connection is established directly to the verified address — no
///   DNS resolution happens at connect time.
/// - https performs the TLS handshake on the pinned socket with the original
///   hostname, preserving SNI and hostname certificate checks.
/// - `Connection: close` semantics: one request per connection, so every hop
///   (initial URL or redirect target) always uses the pin validated for that
///   exact hop.
/// - Direct connections only (no proxies): proxying would move the endpoint
///   decision out of the pinning layer.
class PinnedHttpAdapter implements HttpClientAdapter {
  PinnedHttpAdapter({
    required this.config,
    required SocketConnectFn connectFn,
    required InternetAddress? Function(String host) pinProvider,
  })  : _connectFn = connectFn,
        _pinProvider = pinProvider;

  final SafeHttpConfig config;
  final SocketConnectFn _connectFn;
  final InternetAddress? Function(String host) _pinProvider;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    final uri = options.uri;
    final isSecure = uri.scheme == 'https';
    final host = uri.host;
    final port = uri.hasPort ? uri.port : (isSecure ? 443 : 80);

    final pin = _pinProvider(host);
    if (pin == null) {
      // Fail closed: with DNS enforcement every host is validated and pinned
      // before any fetch; reaching the socket layer without a pin is a bug
      // and must never fall back to an unvalidated resolution.
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'SSRF guard: no validated IP pin for host $host',
      );
    }

    final Socket socket;
    try {
      socket = await _connectFn(
        address: pin,
        port: port,
        host: host,
        isSecure: isSecure,
      );
    } on DioException {
      rethrow;
    } catch (e) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Connect failed: $e',
      );
    }

    cancelFuture?.then((_) {
      socket.destroy();
    }, onError: (_) {});

    try {
      await _writeRequest(socket, options, requestStream);
      return await _readResponse(socket, options);
    } catch (e) {
      socket.destroy();
      if (e is DioException) rethrow;
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Request failed: $e',
      );
    }
  }

  @override
  void close({bool force = false}) {}

  // -----------------------------------------------------------------------
  // Request over the pinned socket
  // -----------------------------------------------------------------------

  Future<void> _writeRequest(
    Socket socket,
    RequestOptions options,
    Stream<Uint8List>? requestStream,
  ) async {
    final uri = options.uri;
    final path = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    final requestTarget = path.isEmpty ? '/' : path;

    final buffer = StringBuffer()
      ..write('${options.method} $requestTarget HTTP/1.1\r\n')
      ..write('Host: ${uri.host}${uri.hasPort ? ':${uri.port}' : ''}\r\n');
    options.headers.forEach((key, value) {
      final lower = key.toLowerCase();
      if (lower == 'host' ||
          lower == 'content-length' ||
          lower == 'accept-encoding') {
        return;
      }
      if (value is List) {
        for (final v in value) {
          buffer.write('$key: $v\r\n');
        }
      } else if (value != null) {
        buffer.write('$key: $value\r\n');
      }
    });
    // Raw bytes, no transparent decompression in the adapter.
    buffer.write('Accept-Encoding: identity\r\n');
    buffer.write('Connection: close\r\n\r\n');
    socket.add(utf8.encode(buffer.toString()));
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        socket.add(chunk);
      }
    }
    await socket.flush();
  }

  // -----------------------------------------------------------------------
  // Response over the pinned socket
  // -----------------------------------------------------------------------

  Future<ResponseBody> _readResponse(
    Socket socket,
    RequestOptions options,
  ) async {
    final conn = _PinnedConnection(socket, config.receiveTimeout);
    final statusCode = await conn.readStatusLine();
    final headers = await conn.readHeaders();

    if (statusCode >= 300 && statusCode < 400) {
      // Redirect: no body needed. Drop the connection immediately so the
      // next hop always gets a fresh, freshly-pinned connection.
      socket.destroy();
      return ResponseBody(
        const Stream<Uint8List>.empty(),
        statusCode,
        statusMessage: conn.statusMessage,
        isRedirect: true,
        headers: headers,
      );
    }

    final chunked =
        (headers['transfer-encoding']?.first ?? '').toLowerCase().contains(
              'chunked',
            );
    final contentLength =
        int.tryParse(headers['content-length']?.first ?? '') ?? -1;

    Stream<Uint8List> body;
    if (chunked) {
      body = conn.bodyChunked();
    } else if (contentLength >= 0) {
      body = conn.bodyByLength(contentLength);
    } else {
      body = conn.bodyToEof();
    }

    return ResponseBody(
      // Release the pinned socket once the body is fully read, errored, or
      // the consumer cancels (dio calls body.close() on cancel/timeout too).
      _withSocketCleanup(body, socket),
      statusCode,
      statusMessage: conn.statusMessage,
      isRedirect: false,
      headers: headers,
    );
  }

  /// Wraps [body] so the pinned socket is destroyed when the stream is done,
  /// errored, or cancelled.
  Stream<Uint8List> _withSocketCleanup(
    Stream<Uint8List> body,
    Socket socket,
  ) async* {
    try {
      yield* body;
    } finally {
      socket.destroy();
    }
  }
}

/// A safe HTTP client that enforces SSRF protection and size / time limits.
///
/// The production client uses [PinnedHttpAdapter]: every host is validated
/// (literal blocklist + DNS) in [_validateHost], then the connection is
/// pinned to one verified `InternetAddress` so the DNS result used for the
/// check is the one used for the connection — rebinding between check and
/// connect cannot redirect the request to an unvalidated address.
///
/// Tests inject a fake dio (and optionally a fake [DnsResolver]); the fake
/// transport never touches the socket layer, so pinning is inert there.
class SafeHttpClient {
  SafeHttpClient({
    Dio? dio,
    SafeHttpConfig config = SafeHttpConfig.defaultConfig,
    DnsResolver? resolver,
    SocketConnectFn? connectFn,
  })  : _config = config,
        _resolver = resolver ?? const SystemDnsResolver() {
    final baseOptions = BaseOptions(
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
      followRedirects: false, // We handle redirects manually.
      headers: {
        'User-Agent': config.userAgent,
        'Accept': config.acceptHeader,
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.7',
      },
      validateStatus: (s) => s != null && s >= 200 && s < 400,
    );
    if (dio != null) {
      _dio = dio;
    } else if (config.enforceDnsCheck) {
      _dio = Dio(baseOptions)
        ..httpClientAdapter = PinnedHttpAdapter(
          config: config,
          connectFn: connectFn ?? _defaultConnect(config),
          pinProvider: (host) => _pins[host],
        );
    } else {
      _dio = Dio(baseOptions);
    }
  }

  late final Dio _dio;
  final SafeHttpConfig _config;
  final DnsResolver _resolver;

  /// host → validated `InternetAddress`. Written by [_validateHost] after the
  /// DNS check passes; consumed by [PinnedHttpAdapter] at connect time.
  final Map<String, InternetAddress> _pins = {};

  /// Production connect implementation (TCP to the pin; TLS over it with the
  /// original hostname for https).
  static SocketConnectFn _defaultConnect(SafeHttpConfig config) {
    return ({
      required InternetAddress address,
      required int port,
      required String host,
      required bool isSecure,
    }) =>
        _defaultSocketConnect(
          address: address,
          port: port,
          host: host,
          isSecure: isSecure,
          connectTimeout: config.connectTimeout,
          receiveTimeout: config.receiveTimeout,
        );
  }

  /// Fetches [url], following redirects up to [_config.maxRedirects].
  ///
  /// Every hop (initial URL and each redirect target) is passed through
  /// [_validateHost] before connecting. Returns [SafeHttpResult.failure] /
  /// [SafeHttpResult.authFailure] for any policy violation (SSRF via literal
  /// or DNS, oversized body, wrong MIME, too many redirects, timeout, auth
  /// rejection). Never throws.
  Future<SafeHttpResult> fetch(String url) =>
      _fetch(url, responseKind: _SafeResponseKind.text);

  /// Fetches a binary body through exactly the same SSRF, DNS pinning,
  /// redirect, timeout, MIME and byte-limit policy as [fetch]. Bytes are
  /// returned verbatim and are never round-tripped through UTF-8.
  Future<SafeHttpResult> fetchBytes(String url) =>
      _fetch(url, responseKind: _SafeResponseKind.bytes);

  Future<SafeHttpResult> _fetch(
    String url, {
    required _SafeResponseKind responseKind,
  }) async {
    String currentUrl = url;
    int redirects = 0;

    while (true) {
      final violation = await _validateHost(currentUrl);
      if (violation != null) {
        return SafeHttpResult.failure(violation);
      }

      SafeHttpResult? result;
      for (int attempt = 0; attempt <= _config.maxRetries; attempt++) {
        result = await _fetchOnce(currentUrl, responseKind: responseKind);
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
          return SafeHttpResult.failure(
              'Too many redirects (>${_config.maxRedirects})');
        }
        final location = r.redirectLocation;
        if (location == null || location.isEmpty) {
          return SafeHttpResult.failure(
              'Redirect $status without Location header');
        }
        // The next loop iteration re-runs _validateHost (literal + DNS +
        // re-pin) on the redirect target before any connection is attempted.
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
  // Host validation (literal blocklist + DNS check + connection pin)
  // -----------------------------------------------------------------------

  /// Returns an error string if [url] violates the SSRF policy, else null.
  ///
  /// Two layers:
  ///   1. Synchronous literal check — scheme allowlist, literal
  ///      private/loopback/metadata hosts.
  ///   2. DNS resolution (when [SafeHttpConfig.enforceDnsCheck] is true) —
  ///      every resolved address must be public; any dangerous address
  ///      fails the whole request. On success the connection for this host
  ///      is pinned to one verified address.
  Future<String?> _validateHost(String url) async {
    final literalViolation = _validateUrlLiteral(url);
    if (literalViolation != null) return literalViolation;
    if (_config.enforceDnsCheck) {
      final host = Uri.parse(url).host;
      final check = await _checkDns(host);
      if (check.$1 != null) return check.$1;
      final addresses = check.$2;
      if (addresses.isEmpty) {
        return 'DNS resolution failed for host $host';
      }
      // Pin the connection to a validated address: the transport connects to
      // exactly this InternetAddress (no re-resolution at connect time), so
      // a rebinding DNS that answers differently after this check cannot
      // redirect the connection to an unvalidated target.
      _pins[host] = _preferredAddress(addresses);
    }
    return null;
  }

  /// Prefer IPv4 (most servers) over IPv6 when both are available.
  InternetAddress _preferredAddress(List<InternetAddress> addresses) {
    for (final a in addresses) {
      if (a.type == InternetAddressType.IPv4) return a;
    }
    return addresses.first;
  }

  /// Resolves and blocklist-checks [host]. Returns
  /// `(violationOrNull, addresses)`; the address list is only meaningful
  /// when the violation is null. The returned list is the **same** list the
  /// pin is chosen from — no second lookup happens after validation.
  Future<(String?, List<InternetAddress>)> _checkDns(String host) async {
    final List<InternetAddress> addresses;
    try {
      addresses = await _resolver.lookup(host);
    } catch (e) {
      return (
        'DNS resolution failed for host $host',
        const <InternetAddress>[]
      );
    }
    for (final addr in addresses) {
      if (_isBlockedAddress(addr)) {
        return (
          'SSRF blocked: host $host resolves to dangerous address ${addr.address}',
          const <InternetAddress>[],
        );
      }
    }
    return (null, addresses);
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
    if (host == 'localhost' ||
        host == '0.0.0.0' ||
        host == '::1' ||
        host == '[::1]') {
      return true;
    }
    // Cloud metadata endpoints.
    if (host == 'metadata.google.internal' ||
        host == '169.254.169.254' ||
        host.endsWith('.metadata')) {
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
    if (b[0] == 169 && b[1] == 254) {
      return true; // 169.254/16 link-local+metadata
    }
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

  Future<SafeHttpResult> _fetchOnce(
    String url, {
    required _SafeResponseKind responseKind,
  }) async {
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
          body: responseKind == _SafeResponseKind.text ? '' : null,
          bytes: responseKind == _SafeResponseKind.bytes ? Uint8List(0) : null,
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

      // Decode only for text callers. Binary asset callers receive the exact
      // bytes so invalid UTF-8 and embedded zeroes cannot be changed.
      final bytes = builder.takeBytes();
      final body = responseKind == _SafeResponseKind.text
          ? utf8.decode(bytes, allowMalformed: true)
          : null;

      return SafeHttpResult.ok(
        body: body,
        bytes: responseKind == _SafeResponseKind.bytes ? bytes : null,
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
            body: responseKind == _SafeResponseKind.text ? '' : null,
            bytes:
                responseKind == _SafeResponseKind.bytes ? Uint8List(0) : null,
            finalUrl: url,
            mimeType: '',
            statusCode: status,
            redirectLocation: resolved,
          );
        }
        // 401 / 403: auth or anti-crawler rejection — surfaced honestly as
        // an auth-required failure instead of a generic network error.
        if (status == 401 || status == 403) {
          return SafeHttpResult.authFailure(
              'HTTP $status — 站点要求登录或拒绝了抓取（可能被反爬拦截）');
        }
        return SafeHttpResult.failure('HTTP $status');
      }
      return SafeHttpResult.failure('Network error: ${e.message}');
    } catch (e) {
      return SafeHttpResult.failure('Unexpected error: $e');
    }
  }

  bool _isRedirect(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  bool _isPolicyError(String? message) {
    if (message == null) return false;
    return message.startsWith('SSRF blocked:') ||
        message.startsWith('SSRF guard:') ||
        message.startsWith('DNS resolution failed') ||
        message.startsWith('Disallowed scheme:') ||
        message.startsWith('Unsupported MIME type:') ||
        message.startsWith('Response body exceeds max size') ||
        message.startsWith('Too many redirects') ||
        message.startsWith('HTTP 401') ||
        message.startsWith('HTTP 403') ||
        message.startsWith('Redirect') && message.contains('without Location');
  }
}

/// Low-level reader over the pinned socket: status line, headers, and the
/// three body modes (content-length / chunked / until EOF). Every socket read
/// is bounded by the receive timeout.
///
/// Bytes are buffered across socket chunks: a single TCP segment can carry
/// the status line, headers and body together, and each reader consumes only
/// what it needs from the buffer.
class _PinnedConnection {
  _PinnedConnection(Socket socket, this.receiveTimeout)
      : _iterator = StreamIterator(socket);

  final Duration receiveTimeout;
  final StreamIterator<Uint8List> _iterator;

  /// Unconsumed bytes received from the socket (may span multiple events).
  final List<int> _pending = [];
  bool _eof = false;

  String? statusMessage;

  Future<bool> _moveNext() => _iterator.moveNext().timeout(
        receiveTimeout,
        onTimeout: () => throw const SocketException('receive timeout'),
      );

  Future<bool> _ensureBytes() async {
    if (_pending.isNotEmpty) return true;
    if (_eof) return false;
    if (!await _moveNext()) {
      _eof = true;
      return false;
    }
    _pending.addAll(_iterator.current);
    return true;
  }

  /// Reads one line (without trailing CRLF), or null at EOF.
  Future<String?> _readLine() async {
    final line = <int>[];
    while (true) {
      if (!await _ensureBytes()) {
        if (line.isEmpty) return null;
        return utf8.decode(line, allowMalformed: true).trim();
      }
      final idx = _pending.indexOf(0x0A);
      if (idx < 0) {
        line.addAll(_pending);
        _pending.clear();
        if (line.length > 65536) {
          throw const SocketException('response header line too long');
        }
        continue;
      }
      line.addAll(_pending.sublist(0, idx));
      _pending.removeRange(0, idx + 1);
      return utf8.decode(line, allowMalformed: true).trim();
    }
  }

  /// Reads up to [max] bytes; returns null at EOF.
  Future<Uint8List?> _readBytes(int max) async {
    if (!await _ensureBytes()) return null;
    if (_pending.length <= max) {
      final out = Uint8List.fromList(_pending);
      _pending.clear();
      return out;
    }
    final out = Uint8List.fromList(_pending.sublist(0, max));
    _pending.removeRange(0, max);
    return out;
  }

  Future<int> readStatusLine() async {
    final line = await _readLine();
    if (line == null) {
      throw const SocketException('connection closed before response');
    }
    final parts = line.split(' ');
    if (parts.length > 2) {
      statusMessage = parts.sublist(2).join(' ');
    }
    return int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  }

  Future<Map<String, List<String>>> readHeaders() async {
    final headers = <String, List<String>>{};
    while (true) {
      final line = await _readLine();
      if (line == null || line.isEmpty) break;
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final name = line.substring(0, idx).trim().toLowerCase();
      final value = line.substring(idx + 1).trim();
      (headers[name] ??= []).add(value);
    }
    return headers;
  }

  /// Body of exactly [length] raw bytes.
  Stream<Uint8List> bodyByLength(int length) async* {
    var remaining = length;
    while (remaining > 0) {
      final chunk = await _readBytes(remaining);
      if (chunk == null) break;
      remaining -= chunk.length;
      yield chunk;
    }
  }

  /// Chunked-transfer body (size lines are hex; trailers are discarded).
  Stream<Uint8List> bodyChunked() async* {
    while (true) {
      final sizeLine = await _readLine();
      if (sizeLine == null) break;
      final sizeStr = sizeLine.split(';').first.trim();
      final size = int.tryParse(sizeStr, radix: 16);
      if (size == null) break;
      if (size == 0) {
        while (true) {
          final trailer = await _readLine();
          if (trailer == null || trailer.isEmpty) break;
        }
        break;
      }
      yield* bodyByLength(size);
      await _readLine(); // trailing CRLF after chunk data
    }
  }

  /// Body until the server closes the connection.
  Stream<Uint8List> bodyToEof() async* {
    while (true) {
      final chunk = await _readBytes(64 * 1024);
      if (chunk == null) break;
      yield chunk;
    }
  }
}
