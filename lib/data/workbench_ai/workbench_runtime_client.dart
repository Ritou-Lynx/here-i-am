library;

import 'package:dio/dio.dart';

class WorkbenchRuntimeException implements Exception {
  const WorkbenchRuntimeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class WorkbenchRuntimeSession {
  const WorkbenchRuntimeSession({
    required this.sessionId,
    required this.providerSessionId,
  });

  final String sessionId;
  final String providerSessionId;
}

class WorkbenchRuntimeTurn {
  const WorkbenchRuntimeTurn({required this.turnId});
  final String turnId;
}

class WorkbenchRuntimeEvents {
  const WorkbenchRuntimeEvents({
    required this.status,
    required this.events,
    required this.nextSequence,
  });

  final String status;
  final List<Map<String, dynamic>> events;
  final int nextSequence;
}

abstract interface class WorkbenchRuntimeGateway {
  Future<WorkbenchRuntimeSession> startSession({
    required List<Map<String, dynamic>> dynamicTools,
    Map<String, dynamic> contextManifest = const {},
  });

  Future<WorkbenchRuntimeTurn> startTurn(String sessionId, String input);

  Future<WorkbenchRuntimeEvents> readEvents(
    String sessionId, {
    int afterSequence = 0,
  });

  Future<void> respondToToolCall({
    required String toolCallId,
    required bool success,
    required String text,
  });

  Future<void> closeSession(String sessionId);
}

/// Runtime controls needed by a product-owned, continuing conversation.
///
/// The narrower [WorkbenchRuntimeGateway] remains sufficient for isolated
/// action turns. Keeping the continuity controls separate avoids forcing
/// short-lived tool coordinators to pretend that they support resume/stop.
abstract interface class WorkbenchConversationRuntimeGateway
    implements WorkbenchRuntimeGateway {
  Future<WorkbenchRuntimeSession> resumeSession({
    required String providerSessionId,
    required List<Map<String, dynamic>> dynamicTools,
  });

  Future<void> interruptTurn({
    required String sessionId,
    required String turnId,
  });
}

class WorkbenchRuntimeClient implements WorkbenchConversationRuntimeGateway {
  WorkbenchRuntimeClient({
    String bridgeUrl = 'http://127.0.0.1:47831',
    Dio? dio,
  })  : _baseUri = _validateBridgeUrl(bridgeUrl),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 3),
                receiveTimeout: const Duration(seconds: 15),
                sendTimeout: const Duration(seconds: 10),
                responseType: ResponseType.json,
              ),
            );

  static const prefix = '/experimental/v1/runtime';

  final Uri _baseUri;
  final Dio _dio;

  @override
  Future<WorkbenchRuntimeSession> startSession({
    required List<Map<String, dynamic>> dynamicTools,
    Map<String, dynamic> contextManifest = const {},
  }) async {
    final config = <String, dynamic>{
        'ephemeral': false,
        'service_name': 'here_i_am_workbench',
      if (dynamicTools.isNotEmpty) 'dynamic_tools': dynamicTools,
    };
    final data = await _post('$prefix/sessions', {
      'config': config,
      'context_manifest': contextManifest,
    });
    final sessionId = _requiredString(data, 'session_id');
    final metadata = _map(data['provider_metadata']);
    return WorkbenchRuntimeSession(
      sessionId: sessionId,
      providerSessionId: _requiredString(metadata, 'provider_session_id'),
    );
  }

  @override
  Future<WorkbenchRuntimeSession> resumeSession({
    required String providerSessionId,
    required List<Map<String, dynamic>> dynamicTools,
  }) async {
    final data = await _post('$prefix/sessions/resume', {
      'provider_session_id': providerSessionId,
      'config': {
        'ephemeral': false,
        'service_name': 'here_i_am_workbench',
        if (dynamicTools.isNotEmpty) 'dynamic_tools': dynamicTools,
      },
    });
    final metadata = _map(data['provider_metadata']);
    return WorkbenchRuntimeSession(
      sessionId: _requiredString(data, 'session_id'),
      providerSessionId: _requiredString(metadata, 'provider_session_id'),
    );
  }

  @override
  Future<WorkbenchRuntimeTurn> startTurn(
    String sessionId,
    String input,
  ) async {
    final data = await _post(
      '$prefix/sessions/${Uri.encodeComponent(sessionId)}/turns',
      {'input': input},
    );
    return WorkbenchRuntimeTurn(turnId: _requiredString(data, 'turn_id'));
  }

  @override
  Future<WorkbenchRuntimeEvents> readEvents(
    String sessionId, {
    int afterSequence = 0,
  }) async {
    try {
      final response = await _dio.getUri(
        _uri(
          '$prefix/sessions/${Uri.encodeComponent(sessionId)}/events',
          queryParameters: {'after': '$afterSequence'},
        ),
      );
      final data = _map(response.data);
      final rawEvents = data['events'];
      if (rawEvents is! List) {
        throw const WorkbenchRuntimeException(
          'invalid_response',
          'Runtime event response is invalid.',
        );
      }
      return WorkbenchRuntimeEvents(
        status: _requiredString(data, 'status'),
        events: rawEvents.map((value) => _map(value)).toList(growable: false),
        nextSequence: (data['next_sequence'] as num?)?.toInt() ?? afterSequence,
      );
    } on DioException catch (error) {
      throw _normalizeDio(error);
    }
  }

  @override
  Future<void> respondToToolCall({
    required String toolCallId,
    required bool success,
    required String text,
  }) async {
    await _post('$prefix/tool-calls/${Uri.encodeComponent(toolCallId)}', {
      'success': success,
      'content_items': [
        {'type': 'text', 'text': text},
      ],
    });
  }

  @override
  Future<void> interruptTurn({
    required String sessionId,
    required String turnId,
  }) async {
    await _post(
      '$prefix/sessions/${Uri.encodeComponent(sessionId)}'
      '/turns/${Uri.encodeComponent(turnId)}/interrupt',
      const {},
    );
  }

  @override
  Future<void> closeSession(String sessionId) async {
    try {
      await _dio.deleteUri(
        _uri('$prefix/sessions/${Uri.encodeComponent(sessionId)}'),
      );
    } on DioException catch (error) {
      throw _normalizeDio(error);
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.postUri(_uri(path), data: body);
      return _map(response.data);
    } on DioException catch (error) {
      throw _normalizeDio(error);
    }
  }

  Uri _uri(
    String path, {
    Map<String, String>? queryParameters,
  }) {
    return _baseUri.replace(
      path: '${_baseUri.path.replaceFirst(RegExp(r'/$'), '')}$path',
      queryParameters: queryParameters,
    );
  }

  static Uri _validateBridgeUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        !_isLoopback(uri.host)) {
      throw ArgumentError('Workbench Runtime bridge must be a loopback URL');
    }
    return uri;
  }

  static bool _isLoopback(String host) {
    final normalized = host.toLowerCase();
    return normalized == '127.0.0.1' ||
        normalized == 'localhost' ||
        normalized == '::1';
  }
}

WorkbenchRuntimeException _normalizeDio(DioException error) {
  final data = error.response?.data;
  if (data is Map) {
    final envelope = data['error'];
    if (envelope is Map) {
      return WorkbenchRuntimeException(
        envelope['code']?.toString() ?? 'runtime_error',
        envelope['message']?.toString() ?? 'Runtime request failed.',
      );
    }
    return WorkbenchRuntimeException(
      data['error']?.toString() ?? 'runtime_error',
      data['message']?.toString() ?? 'Runtime request failed.',
    );
  }
  return WorkbenchRuntimeException(
    'runtime_unavailable',
    error.type == DioExceptionType.connectionTimeout
        ? '连接林埃的电脑执行能力超时。'
        : '电脑执行能力当前不可用。',
  );
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) {
    throw const WorkbenchRuntimeException(
      'invalid_response',
      'Runtime response is invalid.',
    );
  }
  return Map<String, dynamic>.from(value);
}

String _requiredString(Map<String, dynamic> value, String key) {
  final result = value[key];
  if (result is! String || result.isEmpty) {
    throw WorkbenchRuntimeException(
      'invalid_response',
      'Runtime response is missing $key.',
    );
  }
  return result;
}
