/// Transport for fetching remote text (used by platform subtitle auto-fetch).
///
/// Abstract so domain tests can inject a fake, and the real implementation can
/// adapt per platform: `package:http` uses a fetch-based client on web and an
/// IO client on native. No YouTube-specific knowledge lives here.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Fetches remote text over HTTP(S).
///
/// Returns `null` on any failure (network, timeout, non-200, empty body) —
/// callers treat null as "cannot obtain", never as fabricated content.
abstract class TimedTextTransport {
  Future<String?> getText(String url, {Map<String, String>? headers});
}

/// Real HTTP transport backed by `package:http`.
class HttpTimedTextTransport implements TimedTextTransport {
  final http.Client _client;
  final Duration timeout;
  final String userAgent;

  HttpTimedTextTransport({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    this.userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
  }) : _client = client ?? http.Client();

  @override
  Future<String?> getText(String url, {Map<String, String>? headers}) async {
    try {
      final res = await _client
          .get(
            Uri.parse(url),
            headers: {'User-Agent': userAgent, ...?headers},
          )
          .timeout(timeout);
      if (res.statusCode != 200) return null;
      if (res.bodyBytes.isEmpty) return null;
      // Prefer the charset-declared decoding; fall back to UTF-8 when the
      // declared decode produced replacement characters.
      final declared = res.body;
      if (!declared.contains('\uFFFD')) return declared;
      return utf8.decode(res.bodyBytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  /// Closes the underlying client. Call when the owning service is disposed.
  void dispose() {
    _client.close();
  }
}
