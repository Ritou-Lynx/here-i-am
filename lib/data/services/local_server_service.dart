import 'dart:io';
import 'package:logging/logging.dart';

class LocalServerService {
  static final Logger _logger = Logger('LocalServerService');
  static HttpServer? _server;
  static String? Function(Uri)? _authCallback;

  static void setAuthCallback(String? Function(Uri) callback) {
    _authCallback = callback;
  }

  static void clearAuthCallback() {
    _authCallback = null;
  }

  static Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 1455);
      _logger.info('Local server running on localhost:1455');

      _server!.listen((HttpRequest request) {
        final uri = request.uri;
        _logger.info('Local server received request: ${uri.path}');

        if (_authCallback != null) {
          final htmlResponse = _authCallback!(uri);
          if (htmlResponse != null) {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.html
              ..write(htmlResponse)
              ..close();
            return;
          }
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.text
          ..write('hello world')
          ..close();
      });
    } catch (e) {
      _logger.severe('Failed to start local server: $e');
    }
  }

  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
