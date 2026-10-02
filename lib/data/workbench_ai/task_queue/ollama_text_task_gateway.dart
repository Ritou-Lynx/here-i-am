library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../workbench_runtime_client.dart';

/// Where long tasks run. Each attempt is one plain Ollama `/api/chat` request
/// that carries no tools, so nothing executes on this machine and no native
/// isolation, elevation or Bridge profile is involved.
class OllamaTextTaskConfig {
  const OllamaTextTaskConfig({
    required this.baseUri,
    required this.model,
    this.apiKey,
  });

  static const modelVariable = 'HIA_TASK_OLLAMA_MODEL';
  static const urlVariable = 'HIA_TASK_OLLAMA_URL';
  static const apiKeyVariable = 'OLLAMA_API_KEY';
  static const localUrl = 'http://127.0.0.1:11434';
  static const cloudUrl = 'https://ollama.com';

  final Uri baseUri;
  final String model;
  final String? apiKey;

  /// Null when no model is configured, which keeps long tasks fail-closed.
  /// Without [urlVariable], an API key selects ollama.com directly and no key
  /// selects the local Ollama app (which serves `-cloud` models after sign-in).
  /// Throws [FormatException] for a malformed model or an unsafe URL.
  static OllamaTextTaskConfig? fromEnvironment(
      [Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    final model = (env[modelVariable] ?? '').trim();
    if (model.isEmpty) return null;
    if (model.length > 200 || model.contains(RegExp(r'\s'))) {
      throw const FormatException('Invalid long-task model name.');
    }
    final key = (env[apiKeyVariable] ?? '').trim();
    final apiKey = key.isEmpty ? null : key;
    final rawUrl = (env[urlVariable] ?? '').trim();
    final uri = Uri.tryParse(
        rawUrl.isNotEmpty ? rawUrl : (apiKey == null ? localUrl : cloudUrl));
    // Task text and the key leave this machine only over TLS; plain HTTP is
    // limited to a local Ollama app.
    final allowed = uri != null &&
        (uri.scheme == 'https' ||
            (uri.scheme == 'http' && _loopbackHosts.contains(uri.host)));
    if (!allowed ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
          'The long-task Ollama URL must use https or a local http address.');
    }
    return OllamaTextTaskConfig(baseUri: uri, model: model, apiKey: apiKey);
  }

  Uri get chatUri {
    final path =
        baseUri.path.endsWith('/') ? baseUri.path : '${baseUri.path}/';
    return baseUri.replace(path: '${path}api/chat');
  }
}

const _loopbackHosts = {'127.0.0.1', 'localhost', '::1'};

/// Production long-task backend: Ollama when configured, otherwise a backend
/// that rejects every start while the task is still pending.
WorkbenchTextTaskBackend defaultWorkbenchTextTaskBackend(
    {Map<String, String>? environment}) {
  try {
    final config = OllamaTextTaskConfig.fromEnvironment(environment);
    if (config != null) return OllamaTextTaskGateway(config: config);
  } on FormatException {
    // An unsafe value is treated like a missing one: nothing is sent anywhere.
  }
  return const UnconfiguredTextTaskBackend();
}

/// Streams one text-only Ollama chat per execution attempt and exposes it
/// through the event contract that [WorkbenchTaskQueueExecution] consumes.
class OllamaTextTaskGateway implements WorkbenchTextTaskBackend {
  OllamaTextTaskGateway({required OllamaTextTaskConfig config, Dio? dio})
      : _config = config,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(minutes: 3),
            ));

  static const provider = 'ollama';
  static const _maxErrorBytes = 4096;

  final OllamaTextTaskConfig _config;
  final Dio _dio;
  final Map<String, _OllamaAttempt> _attempts = {};
  final Random _random = Random.secure();

  @override
  Future<void> ensureAvailable() async {}

  @override
  Future<WorkbenchTextTaskSession> startTextTaskSession({
    Map<String, dynamic> contextManifest = const {},
  }) async {
    final epoch = contextManifest['execution_epoch'];
    if (epoch is! String || epoch.isEmpty || epoch.length > 128) {
      throw const WorkbenchRuntimeException(
          'invalid_request', 'A text task attempt needs its execution epoch.');
    }
    final id = _newId('ollama-task');
    final session = WorkbenchTextTaskSession(
      sessionId: id,
      provider: provider,
      providerSessionId: id,
      executionEpoch: epoch,
      providerThreadId: id,
    );
    _attempts[id] = _OllamaAttempt();
    return session;
  }

  @override
  Future<WorkbenchTextTaskTurn> startTextTaskTurn(
    WorkbenchTextTaskSession session,
    String input,
  ) async {
    final attempt = _attempts[session.sessionId];
    if (attempt == null) {
      throw const WorkbenchRuntimeException(
          'session_not_found', 'The text task attempt is closed.');
    }
    if (attempt.turn != null) {
      throw const WorkbenchRuntimeException(
          'invalid_request', 'A text task attempt runs a single turn.');
    }
    final turn = WorkbenchTextTaskTurn(
      localTurnId: _newId('turn'),
      providerTurnId: _newId('ollama-turn'),
      executionEpoch: session.executionEpoch,
    );
    attempt.turn = turn;
    final Response<ResponseBody> response;
    try {
      response = await _dio.postUri<ResponseBody>(
        _config.chatUri,
        data: {
          'model': _config.model,
          'messages': [
            {'role': 'user', 'content': input},
          ],
          'stream': true,
        },
        options: Options(
          responseType: ResponseType.stream,
          validateStatus: (_) => true,
          headers: {
            if (_config.apiKey != null)
              'Authorization': 'Bearer ${_config.apiKey}',
          },
        ),
        cancelToken: attempt.cancelToken,
      );
    } on DioException catch (error) {
      attempt.ended = true;
      throw WorkbenchRuntimeException(
        attempt.closed ? 'interrupted' : 'runtime_unavailable',
        'The Ollama request failed (${error.type.name}).',
      );
    }
    final body = response.data;
    if (response.statusCode != 200 || body == null) {
      attempt.ended = true;
      final detail = body == null ? '' : await _readError(body);
      throw WorkbenchRuntimeException(
        'provider_rejected',
        'Ollama answered HTTP ${response.statusCode}'
            '${detail.isEmpty ? '' : ': $detail'}',
      );
    }
    if (attempt.closed) {
      await body.stream.listen(null).cancel();
      throw const WorkbenchRuntimeException(
          'interrupted', 'The text task attempt was closed.');
    }
    attempt.listen(body.stream);
    return turn;
  }

  @override
  Future<WorkbenchRuntimeEvents> readEvents(
    String sessionId, {
    int afterSequence = 0,
  }) async {
    final attempt = _attempts[sessionId];
    if (attempt == null) {
      throw const WorkbenchRuntimeException(
          'session_not_found', 'The text task attempt is closed.');
    }
    return WorkbenchRuntimeEvents(
      status: 'active',
      events: [
        for (final event in attempt.events)
          if ((event['sequence'] as int) > afterSequence) event,
      ],
      nextSequence: attempt.events.length,
    );
  }

  @override
  Future<void> interruptTurn({
    required String sessionId,
    required String turnId,
  }) async {
    final attempt = _attempts[sessionId];
    if (attempt == null || attempt.turn?.turnId != turnId) return;
    attempt.interrupt();
  }

  /// The request and its stream are cancelled in this process, so no output
  /// can arrive after this returns: closing is always confirmed.
  @override
  Future<WorkbenchTextTaskStopResult> closeTextTaskSession({
    required WorkbenchTextTaskSession session,
    WorkbenchTextTaskTurn? turn,
    required bool interruptRequested,
  }) async {
    await _attempts.remove(session.sessionId)?.close();
    return WorkbenchTextTaskStopResult(
      ordinaryCloseConfirmed: true,
      cancellationConfirmed: turn == null || interruptRequested,
    );
  }

  @override
  Future<void> closeSession(String sessionId) async {
    await _attempts.remove(sessionId)?.close();
  }

  // Long tasks never use the conversation runtime surface: there are no tools
  // to answer and no provider threads to resume.
  @override
  Future<WorkbenchRuntimeSession> startSession({
    required List<Map<String, dynamic>> dynamicTools,
    Map<String, dynamic> contextManifest = const {},
  }) async =>
      throw _unsupported;

  @override
  Future<WorkbenchRuntimeTurn> startTurn(String sessionId, String input) async =>
      throw _unsupported;

  @override
  Future<WorkbenchRuntimeSession> resumeSession({
    required String provider,
    required String providerSessionId,
    required List<Map<String, dynamic>> dynamicTools,
  }) async =>
      throw _unsupported;

  @override
  Future<void> respondToToolCall({
    required String toolCallId,
    required bool success,
    required String text,
  }) async =>
      throw _unsupported;

  static const _unsupported = WorkbenchRuntimeException(
      'unsupported_operation', 'Long tasks run plain text attempts only.');

  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '-${_random.nextInt(1 << 32).toRadixString(36)}';

  static Future<String> _readError(ResponseBody body) async {
    final bytes = <int>[];
    try {
      await for (final chunk in body.stream) {
        bytes.addAll(chunk.take(_maxErrorBytes - bytes.length));
        if (bytes.length >= _maxErrorBytes) break;
      }
    } on Object {
      // The status code alone still explains the rejection.
    }
    final text = utf8.decode(bytes, allowMalformed: true).trim();
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } on FormatException {
      // Fall through to the bounded raw text.
    }
    return text.length > 300 ? text.substring(0, 300) : text;
  }
}

class _OllamaAttempt {
  final CancelToken cancelToken = CancelToken();
  final List<Map<String, dynamic>> events = [];
  WorkbenchTextTaskTurn? turn;
  StreamSubscription<String>? _subscription;

  /// A terminal event was recorded or the request failed; later chunks are
  /// ignored.
  bool ended = false;
  bool closed = false;

  void listen(Stream<Uint8List> stream) {
    _subscription = stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _onLine,
          onError: (Object _) => _end(
              _error('runtime_unavailable', 'The Ollama stream failed.')),
          onDone: () => _end(_error('runtime_unavailable',
              'The Ollama stream ended before completion.')),
          cancelOnError: true,
        );
  }

  void _onLine(String line) {
    if (ended) return;
    final text = line.trim();
    if (text.isEmpty) return;
    final Object? chunk;
    try {
      chunk = jsonDecode(text);
    } on FormatException {
      _end(_error('provider_invalid_stream', 'Ollama sent an unreadable chunk.'));
      return;
    }
    if (chunk is! Map) {
      _end(_error('provider_invalid_stream', 'Ollama sent an unreadable chunk.'));
      return;
    }
    final error = chunk['error'];
    if (error != null) {
      _end(_error('provider_error', '$error'));
      return;
    }
    // Reasoning models stream `message.thinking` separately; only the answer
    // content becomes task output.
    final message = chunk['message'];
    final content = message is Map ? message['content'] : null;
    if (content is String && content.isNotEmpty) {
      _append({
        'kind': 'message_delta',
        'data': {'text': content},
      });
    }
    if (chunk['done'] == true) {
      final reason = chunk['done_reason'];
      // A length cut-off is an incomplete result, not a finished task.
      _end({
        'kind': 'turn_status',
        'status': reason == null || reason == 'stop' ? 'completed' : 'failed',
        if (reason is String) 'data': {'done_reason': reason},
      });
    }
  }

  Map<String, dynamic> _error(String code, String message) => {
        'kind': 'error',
        'data': {'code': code, 'message': message},
      };

  void _append(Map<String, dynamic> event) => events.add({
        'sequence': events.length + 1,
        'turn_id': turn!.turnId,
        ...event,
      });

  void _end(Map<String, dynamic> terminal) {
    if (ended) return;
    ended = true;
    _append(terminal);
    unawaited(_subscription?.cancel());
  }

  void interrupt() {
    if (ended) return;
    _end({'kind': 'turn_status', 'status': 'interrupted'});
    cancelToken.cancel('interrupted');
  }

  Future<void> close() async {
    if (closed) return;
    closed = true;
    ended = true;
    cancelToken.cancel('closed');
    await _subscription?.cancel();
  }
}

/// Production backend when no long-task model is configured. Every start is
/// rejected before the task leaves pending, and nothing is sent anywhere.
class UnconfiguredTextTaskBackend implements WorkbenchTextTaskBackend {
  const UnconfiguredTextTaskBackend();

  static const unavailable = WorkbenchRuntimeException(
      'text_task_model_unconfigured', 'No long-task model is configured.');

  @override
  Future<void> ensureAvailable() async => throw unavailable;

  @override
  Future<WorkbenchTextTaskSession> startTextTaskSession({
    Map<String, dynamic> contextManifest = const {},
  }) async =>
      throw unavailable;

  @override
  Future<WorkbenchTextTaskTurn> startTextTaskTurn(
    WorkbenchTextTaskSession session,
    String input,
  ) async =>
      throw unavailable;

  @override
  Future<WorkbenchRuntimeEvents> readEvents(
    String sessionId, {
    int afterSequence = 0,
  }) async =>
      throw unavailable;

  @override
  Future<void> interruptTurn({
    required String sessionId,
    required String turnId,
  }) async {}

  @override
  Future<WorkbenchTextTaskStopResult> closeTextTaskSession({
    required WorkbenchTextTaskSession session,
    WorkbenchTextTaskTurn? turn,
    required bool interruptRequested,
  }) async =>
      const WorkbenchTextTaskStopResult(
          ordinaryCloseConfirmed: true, cancellationConfirmed: true);

  @override
  Future<void> closeSession(String sessionId) async {}

  @override
  Future<WorkbenchRuntimeSession> startSession({
    required List<Map<String, dynamic>> dynamicTools,
    Map<String, dynamic> contextManifest = const {},
  }) async =>
      throw unavailable;

  @override
  Future<WorkbenchRuntimeTurn> startTurn(String sessionId, String input) async =>
      throw unavailable;

  @override
  Future<WorkbenchRuntimeSession> resumeSession({
    required String provider,
    required String providerSessionId,
    required List<Map<String, dynamic>> dynamicTools,
  }) async =>
      throw unavailable;

  @override
  Future<void> respondToToolCall({
    required String toolCallId,
    required bool success,
    required String text,
  }) async =>
      throw unavailable;
}
