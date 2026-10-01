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
    required this.provider,
    required this.providerSessionId,
  });

  final String sessionId;
  final String provider;
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
    required String provider,
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
    String bridgeUrl = const String.fromEnvironment(
      'GOAL1_P6_ORDINARY_BRIDGE_URL',
      defaultValue: 'http://127.0.0.1:47831',
    ),
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
      provider: _requiredString(metadata, 'provider'),
      providerSessionId: _requiredString(metadata, 'provider_session_id'),
    );
  }

  @override
  Future<WorkbenchRuntimeSession> resumeSession({
    required String provider,
    required String providerSessionId,
    required List<Map<String, dynamic>> dynamicTools,
  }) async {
    final data = await _post('$prefix/sessions/resume', {
      'provider': provider,
      'provider_session_id': providerSessionId,
      'config': {
        'ephemeral': false,
        'service_name': 'here_i_am_workbench',
        if (dynamicTools.isNotEmpty) 'dynamic_tools': dynamicTools,
      },
    });
    final metadata = _map(data['provider_metadata']);
    final sessionId = _requiredString(data, 'session_id');
    final resumedProvider = _requiredString(metadata, 'provider');
    if (resumedProvider != provider) {
      try {
        await closeSession(sessionId);
      } catch (_) {
        // Preserve the mismatch as the authoritative failure. The product
        // binding remains unavailable even if Bridge cleanup also fails.
      }
      throw const WorkbenchRuntimeException(
        'runtime_provider_mismatch',
        'Runtime resumed a different provider.',
      );
    }
    return WorkbenchRuntimeSession(
      sessionId: sessionId,
      provider: resumedProvider,
      providerSessionId: _requiredString(metadata, 'provider_session_id'),
    );
  }

  @override
  Future<WorkbenchRuntimeTurn> startTurn(String sessionId, String input) async {
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

  Uri _uri(String path, {Map<String, String>? queryParameters}) {
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

/// Dedicated queue transport. A profile name is a request, never evidence of
/// isolation. Production remains unavailable until the Bridge supplies the
/// versioned isolation and provider-terminal receipts below.
class WorkbenchTextTaskIsolationException extends WorkbenchRuntimeException {
  const WorkbenchTextTaskIsolationException({required this.cleanupConfirmed})
      : super('unsupported_capability',
            'Text-only execution isolation has not been verified.');
  final bool cleanupConfirmed;
}

/// Versioned facts about the isolated queue session.  These bindings are
/// deliberately separate from [WorkbenchRuntimeSession], whose fields are
/// also used by the ordinary conversation runtime.
class WorkbenchTextTaskSession extends WorkbenchRuntimeSession {
  const WorkbenchTextTaskSession({
    required super.sessionId,
    required super.provider,
    required super.providerSessionId,
    required this.executionEpoch,
    required this.providerThreadId,
  });

  final String executionEpoch;
  final String providerThreadId;
}

class WorkbenchTextTaskTurn extends WorkbenchRuntimeTurn {
  const WorkbenchTextTaskTurn({
    required this.localTurnId,
    required this.providerTurnId,
    required this.executionEpoch,
  }) : super(turnId: localTurnId);

  final String localTurnId;
  final String providerTurnId;
  final String executionEpoch;
}

class WorkbenchTextTaskStopResult {
  const WorkbenchTextTaskStopResult({
    required this.ordinaryCloseConfirmed,
    required this.cancellationConfirmed,
  });

  final bool ordinaryCloseConfirmed;
  final bool cancellationConfirmed;
}

/// This port is intentionally narrower than the normal runtime close API.
/// A generic close response or interrupt ACK has no authority to close a
/// task queue attempt.
abstract interface class WorkbenchTextTaskStopGateway
    implements WorkbenchConversationRuntimeGateway {
  Future<WorkbenchTextTaskTurn> startTextTaskTurn(
    WorkbenchTextTaskSession session,
    String input,
  );

  Future<WorkbenchTextTaskStopResult> closeTextTaskSession({
    required WorkbenchTextTaskSession session,
    WorkbenchTextTaskTurn? turn,
    required bool interruptRequested,
  });
}

class WorkbenchTextTaskRuntimeClient extends WorkbenchRuntimeClient
    implements WorkbenchTextTaskStopGateway {
  WorkbenchTextTaskRuntimeClient({super.bridgeUrl, super.dio});

  static const profile = 'workbench_text_only_v1';
  final Map<String, _TextTaskTurnState> _verifiedSessions = {};
  final Map<String, Future<WorkbenchTextTaskStopResult>> _closeAttempts = {};
  final Map<String, _TextTaskCloseBinding> _closeBindings = {};

  Future<WorkbenchTextTaskSession> startTextTaskSession({
    Map<String, dynamic> contextManifest = const {},
  }) async {
    final executionEpoch =
        _requiredBoundedString(contextManifest, 'execution_epoch');
    final data = await _post('${WorkbenchRuntimeClient.prefix}/sessions', {
      'config': {'runtime_profile': profile},
      'context_manifest': contextManifest,
    });
    final sessionId = _requiredString(data, 'session_id');
    try {
      final receipt = _map(data['execution_profile_receipt']);
      if (receipt['profile'] != profile ||
          receipt['version'] != 2 ||
          receipt['local_session_id'] != sessionId ||
          receipt['execution_epoch'] != executionEpoch ||
          receipt['isolation_verified'] != true ||
          receipt['tools_disabled'] != true) {
        throw const WorkbenchRuntimeException(
            'invalid_response', 'Text task isolation receipt is invalid.');
      }
      final metadata = _map(data['provider_metadata']);
      final providerThreadId = _requiredString(receipt, 'provider_thread_id');
      final providerSessionId =
          _requiredString(metadata, 'provider_session_id');
      if (providerThreadId != providerSessionId) {
        throw const WorkbenchRuntimeException(
            'invalid_response', 'Text task provider binding is invalid.');
      }
      final session = WorkbenchTextTaskSession(
          sessionId: sessionId,
          provider: _requiredString(metadata, 'provider'),
          providerSessionId: providerSessionId,
          executionEpoch: executionEpoch,
          providerThreadId: providerThreadId);
      _verifiedSessions[sessionId] = _TextTaskTurnState.notStarted(session);
      return session;
    } on Object {
      try {
        await super.closeSession(sessionId);
      } on Object {
        // The generic endpoint can still be asked to release the newly
        // allocated ID, but an HTTP success is not proof that a native child,
        // Job and broker binding closed. The creation receipt was invalid, so
        // there is no trusted binding against which a native stop receipt can
        // be checked.
      }
      throw const WorkbenchTextTaskIsolationException(cleanupConfirmed: false);
    }
  }

  @override
  Future<WorkbenchRuntimeSession> startSession({
    required List<Map<String, dynamic>> dynamicTools,
    Map<String, dynamic> contextManifest = const {},
  }) {
    if (dynamicTools.isNotEmpty) {
      throw const WorkbenchRuntimeException('unsupported_capability',
          'Product tools are not available in text tasks.');
    }
    return startTextTaskSession(contextManifest: contextManifest);
  }

  @override
  Future<WorkbenchRuntimeSession> resumeSession({
    required String provider,
    required String providerSessionId,
    required List<Map<String, dynamic>> dynamicTools,
  }) =>
      throw const WorkbenchRuntimeException('unsupported_capability',
          'Text tasks require a new isolated execution attempt.');

  @override
  Future<WorkbenchRuntimeTurn> startTurn(String sessionId, String input) async {
    final state = _verifiedSessions[sessionId];
    if (state == null || !state.isNotStarted) {
      throw const WorkbenchRuntimeException('unsupported_capability',
          'This session is not a fresh verified text execution session.');
    }
    throw const WorkbenchRuntimeException('unsupported_capability',
        'Text task turns require an isolated session binding.');
  }

  @override
  Future<WorkbenchTextTaskTurn> startTextTaskTurn(
      WorkbenchTextTaskSession session, String input) async {
    final state = _verifiedSessions[session.sessionId];
    if (state == null || state.session != session || !state.isNotStarted) {
      throw const WorkbenchRuntimeException('unsupported_capability',
          'This session is not a fresh verified text execution session.');
    }
    // Reserve before transport. A timeout or malformed response remains an
    // unknown start, and can never be reclassified as a no-turn close.
    _verifiedSessions[session.sessionId] = _TextTaskTurnState.reserved(session);
    try {
      final data = await _post(
        '${WorkbenchRuntimeClient.prefix}/sessions/${Uri.encodeComponent(session.sessionId)}/turns',
        {'input': input},
      );
      if (data['local_session_id'] != session.sessionId ||
          data['provider_thread_id'] != session.providerThreadId ||
          data['execution_epoch'] != session.executionEpoch) {
        throw const WorkbenchRuntimeException(
            'invalid_response', 'Text task turn binding is invalid.');
      }
      final turn = WorkbenchTextTaskTurn(
        localTurnId: _requiredString(data, 'local_turn_id'),
        providerTurnId: _requiredString(data, 'provider_turn_id'),
        executionEpoch: session.executionEpoch,
      );
      final current = _verifiedSessions[session.sessionId];
      if (current == null ||
          current.session != session ||
          !current.isReserved) {
        throw const WorkbenchRuntimeException('runtime_stop_unconfirmed',
            'Text task turn started after its session began closing.');
      }
      _verifiedSessions[session.sessionId] =
          _TextTaskTurnState.started(session, turn);
      return turn;
    } on DioException catch (error) {
      throw _normalizeDio(error);
    }
  }

  @override
  Future<WorkbenchTextTaskStopResult> closeTextTaskSession({
    required WorkbenchTextTaskSession session,
    WorkbenchTextTaskTurn? turn,
    required bool interruptRequested,
  }) {
    final state = _verifiedSessions[session.sessionId];
    if (state == null || state.session != session) {
      return Future<WorkbenchTextTaskStopResult>.error(
        const WorkbenchRuntimeException('runtime_stop_unconfirmed',
            'Text execution stop binding is unknown.'),
      );
    }
    final binding = _closeBindings[session.sessionId];
    if (binding != null) {
      if (!binding.matches(
          session: session,
          turn: turn,
          interruptRequested: interruptRequested)) {
        return Future<WorkbenchTextTaskStopResult>.error(
          const WorkbenchRuntimeException('runtime_stop_unconfirmed',
              'Text execution stop binding is unknown.'),
        );
      }
      final existing = _closeAttempts[session.sessionId];
      if (existing != null) return existing;
      return _beginTextTaskClose(binding);
    }
    if ((turn != null && state.turn != turn) ||
        (turn == null && state.turn != null) ||
        state.isClosing) {
      return Future<WorkbenchTextTaskStopResult>.error(
        const WorkbenchRuntimeException('runtime_stop_unconfirmed',
            'Text execution stop binding is unknown.'),
      );
    }
    if (turn == null && !state.isNotStarted && !state.isReserved) {
      return Future<WorkbenchTextTaskStopResult>.error(
        const WorkbenchRuntimeException('runtime_stop_unconfirmed',
            'Text execution stop binding is unknown.'),
      );
    }
    _verifiedSessions[session.sessionId] =
        _TextTaskTurnState.closing(session, state.turn);
    final newBinding = _TextTaskCloseBinding(
      session: session,
      turn: turn,
      interruptRequested: interruptRequested,
      unknownStart: state.isReserved,
    );
    _closeBindings[session.sessionId] = newBinding;
    return _beginTextTaskClose(newBinding);
  }

  Future<WorkbenchTextTaskStopResult> _beginTextTaskClose(
      _TextTaskCloseBinding binding) {
    final sessionId = binding.session.sessionId;
    final close = Future<WorkbenchTextTaskStopResult>.microtask(
        () => _consumeTextTaskClose(
              session: binding.session,
              turn: binding.turn,
              interruptRequested: binding.interruptRequested,
              unknownStart: binding.unknownStart,
            ));
    _closeAttempts[sessionId] = close;
    close.then<void>(
      (_) {},
      onError: (_) {
        // Only an in-flight close is shared. A failed HTTP/receipt attempt
        // remains bound but can reissue the same idempotent DELETE.
        if (identical(_closeAttempts[sessionId], close)) {
          _closeAttempts.remove(sessionId);
        }
      },
    );
    return close;
  }

  Future<WorkbenchTextTaskStopResult> _consumeTextTaskClose({
    required WorkbenchTextTaskSession session,
    required WorkbenchTextTaskTurn? turn,
    required bool interruptRequested,
    required bool unknownStart,
  }) async {
    try {
      final response = await _dio.deleteUri(_uri(
          '${WorkbenchRuntimeClient.prefix}/sessions/${Uri.encodeComponent(session.sessionId)}'));
      if (unknownStart) {
        // The DELETE is deliberately sent so the host can tear down its child
        // and proxy. A turn whose POST outcome is unknown can never become a
        // successful no-turn close, regardless of this response.
        throw const WorkbenchRuntimeException('runtime_stop_unconfirmed',
            'Text task turn start outcome is unknown after teardown.');
      }
      final data = _map(response.data);
      final receipt = data['stop_receipt'];
      if (receipt is! Map ||
          receipt['profile'] != profile ||
          receipt['version'] != 2 ||
          receipt['local_session_id'] != session.sessionId ||
          receipt['execution_epoch'] != session.executionEpoch ||
          receipt['provider_thread_id'] != session.providerThreadId ||
          receipt['local_child_close_observed'] != true ||
          receipt['proxy_drained'] != true) {
        throw const WorkbenchRuntimeException('runtime_stop_unconfirmed',
            'The text task stop receipt is incomplete.');
      }
      if (turn == null) {
        if (receipt['outcome'] != 'closed_without_turn' ||
            receipt['interrupt_dispatched'] != false ||
            !receipt.containsKey('local_turn_id') ||
            receipt['local_turn_id'] != null ||
            !receipt.containsKey('turn_id') ||
            receipt['turn_id'] != null ||
            !receipt.containsKey('interrupt_dispatch_sequence') ||
            receipt['interrupt_dispatch_sequence'] != null ||
            receipt['cancellation_confirmed'] != false ||
            receipt['provider_terminal_confirmed'] != false ||
            receipt['provider_terminal_status'] != null ||
            receipt['provider_terminal_sequence'] != null) {
          throw const WorkbenchRuntimeException('runtime_stop_unconfirmed',
              'A no-turn close receipt is invalid.');
        }
        return const WorkbenchTextTaskStopResult(
            ordinaryCloseConfirmed: true, cancellationConfirmed: false);
      }
      final status = receipt['provider_terminal_status'];
      final ordinary = receipt['outcome'] == 'closed' &&
          receipt['local_turn_id'] == turn.localTurnId &&
          receipt['turn_id'] == turn.providerTurnId &&
          receipt['provider_terminal_confirmed'] == true &&
          const {'completed', 'failed', 'interrupted'}.contains(status) &&
          _isPositiveInt(receipt['provider_terminal_sequence']);
      if (!ordinary) {
        throw const WorkbenchRuntimeException('runtime_stop_unconfirmed',
            'The provider did not confirm the bound text task turn.');
      }
      final dispatchSequence = receipt['interrupt_dispatch_sequence'];
      final cancellation = interruptRequested &&
          receipt['interrupt_dispatched'] == true &&
          _isNonnegativeSafeInt(dispatchSequence) &&
          status == 'interrupted' &&
          (receipt['provider_terminal_sequence'] as int) >
              (dispatchSequence as int) &&
          receipt['cancellation_confirmed'] == true;
      return WorkbenchTextTaskStopResult(
          ordinaryCloseConfirmed: true, cancellationConfirmed: cancellation);
    } on DioException catch (error) {
      if (unknownStart) {
        throw const WorkbenchRuntimeException('runtime_stop_unconfirmed',
            'Text task start outcome remains unknown after teardown failed.');
      }
      throw _normalizeDio(error);
    }
  }

  @override
  Future<void> closeSession(String sessionId) =>
      throw const WorkbenchRuntimeException('runtime_stop_unconfirmed',
          'Text tasks require a versioned stop receipt.');

  @override
  Future<void> respondToToolCall(
          {required String toolCallId,
          required bool success,
          required String text}) =>
      throw const WorkbenchRuntimeException(
          'unsupported_capability', 'Text tasks cannot respond to tool calls.');
}

class _TextTaskCloseBinding {
  const _TextTaskCloseBinding({
    required this.session,
    required this.turn,
    required this.interruptRequested,
    required this.unknownStart,
  });

  final WorkbenchTextTaskSession session;
  final WorkbenchTextTaskTurn? turn;
  final bool interruptRequested;
  final bool unknownStart;

  bool matches({
    required WorkbenchTextTaskSession session,
    required WorkbenchTextTaskTurn? turn,
    required bool interruptRequested,
  }) =>
      identical(this.session, session) &&
      identical(this.turn, turn) &&
      this.interruptRequested == interruptRequested;
}

class _TextTaskTurnState {
  const _TextTaskTurnState.notStarted(this.session)
      : turn = null,
        isReserved = false,
        isClosing = false;
  const _TextTaskTurnState.reserved(this.session)
      : turn = null,
        isReserved = true,
        isClosing = false;
  const _TextTaskTurnState.started(this.session, this.turn)
      : isReserved = false,
        isClosing = false;
  const _TextTaskTurnState.closing(this.session, this.turn)
      : isReserved = false,
        isClosing = true;

  final WorkbenchTextTaskSession session;
  final WorkbenchTextTaskTurn? turn;
  final bool isReserved;
  final bool isClosing;
  bool get isNotStarted => turn == null && !isReserved;
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

String _requiredBoundedString(Map<String, dynamic> value, String key) {
  final result = value[key];
  if (result is! String || result.isEmpty || result.length > 256) {
    throw WorkbenchRuntimeException(
      'invalid_response',
      'Runtime response is missing a bounded $key.',
    );
  }
  return result;
}

bool _isPositiveInt(Object? value) =>
    value is int && value > 0 && value <= 9007199254740991;

bool _isNonnegativeSafeInt(Object? value) =>
    value is int && value >= 0 && value <= 9007199254740991;
