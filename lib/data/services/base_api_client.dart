import 'dart:convert';
import 'package:dio/dio.dart';
import 'api_exception.dart';

import 'package:logging/logging.dart';

/// Base API client, shared request handling
/// Template method pattern to reduce duplication
abstract class BaseApiClient {
  final Dio dio;
  final String baseUrl;
  final _logger = Logger('ApiClient');

  BaseApiClient({
    required this.baseUrl,
    Dio? dio,
  }) : dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 300),
              receiveTimeout: const Duration(seconds: 300),
              sendTimeout: const Duration(seconds: 300),
            )) {
    this.dio.interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.next(options);
          },
          onResponse: (response, handler) {
            _logRequestAndResponse(response);
            return handler.next(response);
          },
          onError: (DioException e, handler) {
            _logError(e);
            return handler.next(e);
          },
        ));
  }

  String _formatBody(dynamic body) {
    if (body == null) return 'null';
    try {
      if (body is Map || body is List) {
        const encoder = JsonEncoder.withIndent('  ');
        return encoder.convert(body);
      }
    } catch (e) {
      // Ignore conversion errors and return string representation
    }
    return body.toString();
  }

  void _logRequestAndResponse(Response response) {
    final request = response.requestOptions;
    final sb = StringBuffer();
    sb.writeln(
        '\n┌────────────────────────────────────────────────────────────────────────');
    sb.writeln('│ Request: ${request.method} ${request.uri}');
    sb.writeln('│ Headers:');
    request.headers.forEach((k, v) => sb.writeln('│   $k: $v'));
    if (request.data != null) {
      sb.writeln('│ Body:');
      final formattedBody = _formatBody(request.data);
      formattedBody.split('\n').forEach((line) => sb.writeln('│   $line'));
    }
    sb.writeln(
        '├────────────────────────────────────────────────────────────────────────');
    sb.writeln('│ Response: status ${response.statusCode}');
    sb.writeln('│ Headers:');
    response.headers.forEach((k, v) => sb.writeln('│   $k: $v'));
    if (response.data != null) {
      sb.writeln('│ Body:');
      final formattedBody = _formatBody(response.data);
      formattedBody.split('\n').forEach((line) => sb.writeln('│   $line'));
    }
    sb.writeln(
        '└────────────────────────────────────────────────────────────────────────');
    _logger.info(sb.toString());
  }

  void _logError(DioException e) {
    final request = e.requestOptions;
    final sb = StringBuffer();
    sb.writeln(
        '\n┌────────────────────────────────────────────────────────────────────────');
    sb.writeln('│ Request: ${request.method} ${request.uri}');
    sb.writeln('│ Headers:');
    request.headers.forEach((k, v) => sb.writeln('│   $k: $v'));
    if (request.data != null) {
      sb.writeln('│ Body:');
      final formattedBody = _formatBody(request.data);
      formattedBody.split('\n').forEach((line) => sb.writeln('│   $line'));
    }
    sb.writeln(
        '├────────────────────────────────────────────────────────────────────────');
    sb.writeln('│ Error Type: ${e.type}');
    sb.writeln('│ Error Message: ${e.message}');
    if (e.response != null) {
      sb.writeln('│ Response Status: ${e.response?.statusCode}');
      if (e.response?.data != null) {
        sb.writeln('│ Response Body:');
        final formattedBody = _formatBody(e.response?.data);
        formattedBody.split('\n').forEach((line) => sb.writeln('│   $line'));
      }
    } else {
      sb.writeln('│ No response received');
    }
    sb.writeln(
        '└────────────────────────────────────────────────────────────────────────');
    _logger.info(sb.toString());
  }

  /// Get auth token (override in subclass)
  Future<String?> getToken() async {
    // Default impl, override in subclass
    return 'sahd9iw6ha21ljl';
  }

  /// Build request headers
  Future<Map<String, String>> buildHeaders({
    Map<String, String>? additionalHeaders,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ...?additionalHeaders,
    };

    final token = await getToken();
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  /// Process response data
  T processResponse<T>(
    dynamic responseData,
    T Function(dynamic data) parser,
  ) {
    if (responseData is! Map<String, dynamic>) {
      throw ApiException('Invalid response format');
    }

    // Check success field
    if (responseData.containsKey('success') &&
        responseData['success'] == false) {
      final message = responseData['message'] as String? ?? 'Operation failed';
      throw ApiException(message);
    }

    // Extract data field
    if (responseData.containsKey('data')) {
      final data = responseData['data'];
      // Allow null data to be passed to parser
      return parser(data);
    }

    // If no data field, parse whole response
    return parser(responseData);
  }

  /// Handle DioException
  Never handleDioException(DioException e) {
    if (e.response != null) {
      final responseData = e.response?.data;
      if (responseData is Map<String, dynamic>) {
        if (responseData.containsKey('success') &&
            responseData['success'] == false) {
          final message = responseData['message'] as String? ?? 'Request failed';
          throw ApiException(message, statusCode: e.response?.statusCode);
        }
      }
    }

    // Handle timeout error
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      throw ApiException('Request timeout, please check network', statusCode: e.response?.statusCode);
    }

    // Handle connection error (no response)
    if (e.type == DioExceptionType.connectionError) {
      throw ApiException('Network connection failed, please check network settings', statusCode: e.response?.statusCode);
    }

    // Handle HTTP error response
    if (e.type == DioExceptionType.badResponse) {
      final statusCode = e.response?.statusCode;
      String message = 'Request failed';

      // Try extract error from response body
      if (e.response?.data != null) {
        try {
          if (e.response!.data is Map<String, dynamic>) {
            final responseData = e.response!.data as Map<String, dynamic>;
            if (responseData.containsKey('detail')) {
              message = responseData['detail'] as String? ?? message;
            } else if (responseData.containsKey('message')) {
              message = responseData['message'] as String? ?? message;
            }
          } else if (e.response!.data is String) {
            message = e.response!.data as String;
          }
        } catch (_) {
          // If parse fails, use default message
        }
      }

      // If no message from body, use status default
      if (message == 'Request failed') {
        if (statusCode == 401) {
          message = 'Unauthorized, please check token';
        } else if (statusCode == 403) {
          message = 'Access denied';
        } else if (statusCode == 404) {
          message = 'Resource not found';
        } else if (statusCode == 500) {
          message = 'Internal server error';
        }
      }

      throw ApiException(message, statusCode: statusCode);
    }

    // Other error types
    final errorMsg = e.message ?? e.error?.toString() ?? 'Network request failed';
    throw ApiException(
      'Network request failed: $errorMsg (type: ${e.type})',
      statusCode: e.response?.statusCode,
    );
  }

  /// Unified exception wrapper
  Future<T> executeRequest<T>(
    Future<T> Function() request,
  ) async {
    try {
      return await request();
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      handleDioException(e);
    } catch (e) {
      throw ApiException('Unknown error: ${e.toString()}');
    }
  }

  /// GET request
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic data)? parser,
    Map<String, String>? additionalHeaders,
  }) async {
    return executeRequest(() async {
      final headers = await buildHeaders(additionalHeaders: additionalHeaders);
      final response = await dio.get(
        '$baseUrl$path',
        queryParameters: queryParameters,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200) {
        if (parser != null) {
          return processResponse(response.data, parser);
        }
        return response.data as T;
      } else {
        throw ApiException(
          'Request failed with status: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    });
  }

  /// POST request (JSON)
  Future<T> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic data)? parser,
    Map<String, String>? additionalHeaders,
  }) async {
    return executeRequest(() async {
      final headers = await buildHeaders(additionalHeaders: additionalHeaders);
      final response = await dio.post(
        '$baseUrl$path',
        data: data,
        queryParameters: queryParameters,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (parser != null) {
          return processResponse(response.data, parser);
        }
        return response.data as T;
      } else {
        throw ApiException(
          'Request failed with status: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    });
  }

  /// POST FormData request
  ///
  /// Pure FormData; build MultipartFile outside.
  ///
  /// Example:
  /// ```dart
  /// // single file
  /// final file = await MultipartFile.fromFile('/path/to/file.jpg');
  /// await postFormData('/upload',
  ///   files: {'file': file},
  ///   fields: {'description': 'My file'},
  /// );
  ///
  /// // multiple files
  /// await postFormData('/upload', files: {
  ///   'avatar': await MultipartFile.fromFile('/path/to/avatar.jpg'),
  ///   'cover': await MultipartFile.fromFile('/path/to/cover.jpg'),
  /// });
  ///
  /// // fields only, no files
  /// await postFormData('/submit', fields: {'name': 'value'});
  ///
  /// // pass FormData directly
  /// final formData = FormData.fromMap({
  ///   'field': 'value',
  ///   'file': await MultipartFile.fromFile('/path/to/file.jpg'),
  /// });
  /// await postFormData('/upload', formData: formData);
  /// ```
  Future<T> postFormData<T>(
    String path, {
    // Pass FormData directly (most flexible)
    FormData? formData,

    // Or pass files and fields separately
    Map<String, MultipartFile>? files,
    Map<String, String>? fields,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic data)? parser,
    Map<String, String>? additionalHeaders,
    Duration? sendTimeout,
  }) async {
    return executeRequest(() async {
      // Build FormData
      FormData data;
      if (formData != null) {
        // Use passed FormData as-is
        data = formData;
      } else {
        // Build from files and fields
        data = FormData();

        // Add files
        if (files != null && files.isNotEmpty) {
          files.forEach((fieldName, file) {
            data.files.add(MapEntry(fieldName, file));
          });
        }

        // Add fields
        if (fields != null && fields.isNotEmpty) {
          fields.forEach((key, value) {
            data.fields.add(MapEntry(key, value));
          });
        }
      }

      // Build headers (Dio sets Content-Type/Content-Length for FormData)
      final token = await getToken();
      final headers = <String, String>{
        ...?additionalHeaders,
      };

      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await dio.post(
        '$baseUrl$path',
        data: data,
        queryParameters: queryParameters,
        options: Options(
          headers: headers,
          sendTimeout: sendTimeout,
          // Let Dio handle Content-Length (done in interceptor)
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (parser != null) {
          return processResponse(response.data, parser);
        }
        return response.data as T;
      } else {
        throw ApiException(
          'Request failed with status: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    });
  }

  /// PUT request
  Future<T> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic data)? parser,
    Map<String, String>? additionalHeaders,
  }) async {
    return executeRequest(() async {
      final headers = await buildHeaders(additionalHeaders: additionalHeaders);
      final response = await dio.put(
        '$baseUrl$path',
        data: data,
        queryParameters: queryParameters,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        if (parser != null) {
          return processResponse(response.data, parser);
        }
        return response.data as T;
      } else {
        throw ApiException(
          'Request failed with status: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    });
  }

  /// PATCH request
  Future<T> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic data)? parser,
    Map<String, String>? additionalHeaders,
  }) async {
    return executeRequest(() async {
      final headers = await buildHeaders(additionalHeaders: additionalHeaders);
      final response = await dio.patch(
        '$baseUrl$path',
        data: data,
        queryParameters: queryParameters,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        if (parser != null) {
          return processResponse(response.data, parser);
        }
        return response.data as T;
      } else {
        throw ApiException(
          'Request failed with status: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    });
  }

  /// DELETE request
  Future<T> delete<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic data)? parser,
    Map<String, String>? additionalHeaders,
  }) async {
    return executeRequest(() async {
      final headers = await buildHeaders(additionalHeaders: additionalHeaders);
      final response = await dio.delete(
        '$baseUrl$path',
        queryParameters: queryParameters,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        if (parser != null) {
          return processResponse(response.data, parser);
        }
        return response.data as T;
      } else {
        throw ApiException(
          'Request failed with status: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    });
  }

  /// POST request (streaming response)
  Stream<List<int>> postStream(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? additionalHeaders,
  }) async* {
    try {
      final headers = await buildHeaders(additionalHeaders: additionalHeaders);
      final response = await dio.post<ResponseBody>(
        '$baseUrl$path',
        data: data,
        queryParameters: queryParameters,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        yield* response.data!.stream;
      } else {
        throw ApiException(
          'Request failed with status: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      handleDioException(e);
    } catch (e) {
      throw ApiException('Unknown error: ${e.toString()}');
    }
  }
}
