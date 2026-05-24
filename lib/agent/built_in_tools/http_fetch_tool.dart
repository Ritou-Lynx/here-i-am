import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';

/// Build a tool that performs HTTP requests to external APIs.
///
/// Intended for skill agents (WeRead, etc.) that need to call HTTPS endpoints
/// directly from the agent tool loop without a JavaScript bridge.
Tool buildHttpFetchTool() {
  return Tool(
    name: 'http_fetch',
    description:
        '''Perform an HTTP request to an external URL and return the response.

Use this tool when a skill needs to call an external API (e.g. WeRead gateway,
REST services) directly. Supports GET, POST, PUT, and DELETE.

Returns a JSON object:
- On success: {"status": <int>, "headers": {<key>: <value>}, "body": "<string>"}
- On error:   {"error": "<message>", "status": null}

Notes:
- Always set Content-Type in headers when sending a JSON body.
- The body field is always returned as a raw string; parse it with JSON tools
  if the response is JSON.
- Default timeout is 30 seconds.
''',
    parameters: {
      'type': 'object',
      'properties': {
        'url': {
          'type': 'string',
          'description': 'Full URL including scheme, e.g. https://example.com/api',
        },
        'method': {
          'type': 'string',
          'description': 'HTTP method: GET, POST, PUT, or DELETE (default: GET)',
        },
        'headers': {
          'type': 'object',
          'description':
              'Optional request headers as key-value pairs, '
              'e.g. {"Authorization": "Bearer token", "Content-Type": "application/json"}',
        },
        'body': {
          'type': 'string',
          'description':
              'Optional request body. For JSON APIs, pass a JSON-encoded string '
              'and set Content-Type: application/json in headers.',
        },
        'timeout_seconds': {
          'type': 'integer',
          'description': 'Request timeout in seconds (default: 30)',
        },
      },
      'required': ['url'],
    },
    executable: (
      String url,
      String? method,
      Map<String, dynamic>? headers,
      String? body,
      int? timeout_seconds,
    ) async {
      final effectiveMethod = (method ?? 'GET').toUpperCase();
      final effectiveTimeout = Duration(seconds: (timeout_seconds ?? 30).clamp(1, 120));

      final dio = Dio();
      dio.options.connectTimeout = effectiveTimeout;
      dio.options.receiveTimeout = effectiveTimeout;
      dio.options.sendTimeout = effectiveTimeout;
      // Return raw string instead of auto-decoded JSON
      dio.options.responseType = ResponseType.plain;

      final requestHeaders = headers?.map(
        (k, v) => MapEntry(k, v.toString()),
      );

      try {
        final response = await dio.request<String>(
          url,
          data: body,
          options: Options(
            method: effectiveMethod,
            headers: requestHeaders,
          ),
        );

        final responseHeaders = <String, String>{};
        response.headers.forEach((name, values) {
          responseHeaders[name] = values.join(', ');
        });

        return {
          'status': response.statusCode,
          'headers': responseHeaders,
          'body': response.data ?? '',
        };
      } on DioException catch (e) {
        if (e.response != null) {
          // Server responded with an error status
          final errHeaders = <String, String>{};
          e.response!.headers.forEach((name, values) {
            errHeaders[name] = values.join(', ');
          });
          return {
            'status': e.response!.statusCode,
            'headers': errHeaders,
            'body': e.response!.data?.toString() ?? '',
            'error': e.message ?? 'HTTP error',
          };
        }
        return {
          'error': e.message ?? e.toString(),
          'status': null,
        };
      } catch (e) {
        return {
          'error': e.toString(),
          'status': null,
        };
      }
    },
  );
}
