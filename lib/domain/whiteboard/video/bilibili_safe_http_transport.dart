/// Redirect-safe, bounded HTTP transport for anonymous Bilibili subtitles.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

enum BilibiliHttpFailureKind {
  network,
  accessRestricted,
  redirectRejected,
  tooManyRedirects,
  responseTooLarge,
  invalidResponse,
}

class BilibiliHttpFetchResult {
  const BilibiliHttpFetchResult({
    this.body,
    this.failureKind,
    this.message,
  });

  final String? body;
  final BilibiliHttpFailureKind? failureKind;
  final String? message;

  bool get isSuccess => body != null;
}

abstract class BilibiliHttpTransport {
  Future<BilibiliHttpFetchResult> getText(
    Uri uri, {
    required Map<String, String> headers,
    required int maxBytes,
  });

  void dispose();
}

class BilibiliSafeHttpTransport implements BilibiliHttpTransport {
  BilibiliSafeHttpTransport({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    this.maxRedirects = 3,
    this.userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
  })  : assert(maxRedirects >= 0),
        _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;
  final int maxRedirects;
  final String userAgent;

  bool _disposed = false;

  static bool isAllowedUri(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.host.isEmpty ||
        uri.hasPort && uri.port != 443) {
      return false;
    }
    final host = uri.host.toLowerCase();
    return host == 'api.bilibili.com' ||
        host.endsWith('.bilibili.com') ||
        host.endsWith('.bilivideo.com') ||
        host.endsWith('.hdslb.com');
  }

  @override
  Future<BilibiliHttpFetchResult> getText(
    Uri uri, {
    required Map<String, String> headers,
    required int maxBytes,
  }) async {
    if (_disposed) return _networkFailure;
    if (maxBytes <= 0) {
      return const BilibiliHttpFetchResult(
        failureKind: BilibiliHttpFailureKind.invalidResponse,
        message: '响应大小预算无效',
      );
    }

    var current = uri;
    var redirectCount = 0;
    while (true) {
      if (!isAllowedUri(current)) {
        return const BilibiliHttpFetchResult(
          failureKind: BilibiliHttpFailureKind.redirectRejected,
          message: '重定向目标不在受信任的 Bilibili HTTPS 主机范围内',
        );
      }

      final request = http.Request('GET', current)
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers.addAll({
          'User-Agent': userAgent,
          for (final entry in headers.entries)
            if (entry.key.toLowerCase() != 'cookie') entry.key: entry.value,
        });

      http.StreamedResponse response;
      try {
        response = await _client.send(request).timeout(timeout);
      } on TimeoutException {
        return _networkFailure;
      } catch (_) {
        return _networkFailure;
      }
      if (_disposed) {
        await _cancelStream(response.stream);
        return _networkFailure;
      }

      if (_isRedirect(response.statusCode)) {
        final location = response.headers['location'];
        await _cancelStream(response.stream);
        if (location == null || location.trim().isEmpty) {
          return const BilibiliHttpFetchResult(
            failureKind: BilibiliHttpFailureKind.invalidResponse,
            message: '平台重定向缺少 Location',
          );
        }
        if (redirectCount >= maxRedirects) {
          return const BilibiliHttpFetchResult(
            failureKind: BilibiliHttpFailureKind.tooManyRedirects,
            message: '平台重定向次数超过安全上限',
          );
        }
        Uri next;
        try {
          next = current.resolve(location.trim());
        } catch (_) {
          return const BilibiliHttpFetchResult(
            failureKind: BilibiliHttpFailureKind.invalidResponse,
            message: '平台重定向 Location 无效',
          );
        }
        if (!isAllowedUri(next)) {
          return const BilibiliHttpFetchResult(
            failureKind: BilibiliHttpFailureKind.redirectRejected,
            message: '重定向目标不在受信任的 Bilibili HTTPS 主机范围内',
          );
        }
        redirectCount++;
        current = next;
        continue;
      }

      if (response.statusCode != 200) {
        await _cancelStream(response.stream);
        if (response.statusCode == 401 ||
            response.statusCode == 403 ||
            response.statusCode == 451) {
          return const BilibiliHttpFetchResult(
            failureKind: BilibiliHttpFailureKind.accessRestricted,
            message: '平台拒绝匿名字幕请求',
          );
        }
        return BilibiliHttpFetchResult(
          failureKind: BilibiliHttpFailureKind.network,
          message: '平台请求失败（HTTP ${response.statusCode}）',
        );
      }

      final declaredLength = response.contentLength;
      if (declaredLength != null && declaredLength > maxBytes) {
        await _cancelStream(response.stream);
        return const BilibiliHttpFetchResult(
          failureKind: BilibiliHttpFailureKind.responseTooLarge,
          message: '平台响应超过安全大小上限',
        );
      }

      return _readBounded(response.stream, maxBytes);
    }
  }

  Future<BilibiliHttpFetchResult> _readBounded(
    Stream<List<int>> stream,
    int maxBytes,
  ) async {
    final bytes = BytesBuilder(copy: false);
    var byteCount = 0;
    final stopwatch = Stopwatch()..start();
    try {
      await for (final chunk in stream.timeout(timeout)) {
        if (_disposed || stopwatch.elapsed >= timeout) {
          return _networkFailure;
        }
        if (byteCount + chunk.length > maxBytes) {
          return const BilibiliHttpFetchResult(
            failureKind: BilibiliHttpFailureKind.responseTooLarge,
            message: '平台响应超过安全大小上限',
          );
        }
        bytes.add(chunk);
        byteCount += chunk.length;
      }
    } on TimeoutException {
      return _networkFailure;
    } catch (_) {
      return _networkFailure;
    }
    if (byteCount == 0) return _networkFailure;
    try {
      return BilibiliHttpFetchResult(body: utf8.decode(bytes.takeBytes()));
    } catch (_) {
      return const BilibiliHttpFetchResult(
        failureKind: BilibiliHttpFailureKind.invalidResponse,
        message: '平台响应不是有效 UTF-8',
      );
    }
  }

  static bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  static Future<void> _cancelStream(Stream<List<int>> stream) async {
    try {
      final subscription = stream.listen(null);
      await subscription.cancel();
    } catch (_) {
      // The response is already being rejected; cancellation is best effort.
    }
  }

  static const _networkFailure = BilibiliHttpFetchResult(
    failureKind: BilibiliHttpFailureKind.network,
    message: 'Bilibili 网络请求失败或已结束',
  );

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      _client.close();
    } catch (_) {
      // Disposal must remain idempotent and non-throwing.
    }
  }
}
