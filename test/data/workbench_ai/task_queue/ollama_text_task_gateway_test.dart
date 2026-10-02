import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';
import 'package:memex/data/workbench_ai/task_queue/ollama_text_task_gateway.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_runtime_task_queue_tool.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_execution.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_execution_controller.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_lifecycle_owner.dart';
import 'package:memex/db/app_database.dart';

const scope = TaskQueueHostScope(
    profileId: 'test_text_queue',
    scopeType: 'conversation',
    scopeId: 'synthetic_conversation');
const goal = 'Write a short fictional paragraph';

void main() {
  group('OllamaTextTaskConfig', () {
    test('no model keeps long tasks fail-closed', () {
      expect(OllamaTextTaskConfig.fromEnvironment(const {}), isNull);
      expect(defaultWorkbenchTextTaskBackend(environment: const {}),
          isA<UnconfiguredTextTaskBackend>());
    });

    test('an API key selects ollama.com, no key selects the local app', () {
      final cloud = OllamaTextTaskConfig.fromEnvironment(const {
        'HIA_TASK_OLLAMA_MODEL': 'gpt-oss:120b',
        'OLLAMA_API_KEY': 'secret',
      })!;
      expect(cloud.chatUri.toString(), 'https://ollama.com/api/chat');
      expect(cloud.apiKey, 'secret');
      final local = OllamaTextTaskConfig.fromEnvironment(
          const {'HIA_TASK_OLLAMA_MODEL': 'gpt-oss:120b-cloud'})!;
      expect(local.chatUri.toString(), 'http://127.0.0.1:11434/api/chat');
      expect(local.apiKey, isNull);
      final custom = OllamaTextTaskConfig.fromEnvironment(const {
        'HIA_TASK_OLLAMA_MODEL': 'm',
        'HIA_TASK_OLLAMA_URL': 'https://proxy.example/ollama',
      })!;
      expect(custom.chatUri.toString(), 'https://proxy.example/ollama/api/chat');
      expect(
          defaultWorkbenchTextTaskBackend(
              environment: const {'HIA_TASK_OLLAMA_MODEL': 'm'}),
          isA<OllamaTextTaskGateway>());
    });

    test('remote plain HTTP and malformed models are refused', () {
      for (final env in const [
        {'HIA_TASK_OLLAMA_MODEL': 'm', 'HIA_TASK_OLLAMA_URL': 'http://lan-box:11434'},
        {'HIA_TASK_OLLAMA_MODEL': 'm', 'HIA_TASK_OLLAMA_URL': 'https://u:p@ollama.com'},
        {'HIA_TASK_OLLAMA_MODEL': 'two words'},
      ]) {
        expect(() => OllamaTextTaskConfig.fromEnvironment(env),
            throwsFormatException);
        expect(defaultWorkbenchTextTaskBackend(environment: env),
            isA<UnconfiguredTextTaskBackend>());
      }
    });
  });

  group('Ollama long-task execution', () {
    late FakeOllama ollama;
    late AppDatabase db;
    late TaskRoomService service;
    late OllamaTextTaskGateway gateway;
    late WorkbenchTaskQueueExecution execution;

    setUp(() async {
      ollama = await FakeOllama.start();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      service = TaskRoomService(db: db);
      gateway = OllamaTextTaskGateway(
          config: OllamaTextTaskConfig(
              baseUri: ollama.baseUri, model: 'test-model', apiKey: 'secret'));
      execution = WorkbenchTaskQueueExecution(
        service: service,
        runtime: gateway,
        ensureAvailable: gateway.ensureAvailable,
        startTextSession: (manifest) =>
            gateway.startTextTaskSession(contextManifest: manifest),
        pollInterval: const Duration(milliseconds: 15),
      );
    });

    tearDown(() async {
      await execution.closeForHostLifecycle();
      await ollama.close();
      await db.close();
    });

    Future<String> enqueue() => service.enqueueTaskRoom(
          title: 'synthetic text task',
          goal: goal,
          taskType: TaskType.other,
          executor: 'workbench_runtime',
          conversationId: scope.scopeId,
          queueHostScope: scope,
          maxRetries: 2,
          permissions: {
            'profile_id': scope.profileId,
            'scope_type': scope.scopeType,
            'scope_id': scope.scopeId,
          },
        );

    Future<TaskQueueSnapshot> snapshot(String id) async =>
        (await service.getTaskQueueSnapshot(id))!;

    test('one plain no-tools stream becomes the exact persisted result',
        () async {
      ollama.respond = (request) => request.stream(['Hello', ', ', 'world.']);
      final id = await enqueue();
      expect(await execution.start(id: id, scope: scope, requestId: 'start'),
          isTrue);
      await execution.waitForAttempt(id);

      final done = await snapshot(id);
      expect(done.status, TaskStatus.completed);
      expect(done.progressPercent, 100);
      expect(done.resultPreview, 'Hello, world.');
      final sent = ollama.requests.single;
      expect(sent.path, '/api/chat');
      expect(sent.authorization, 'Bearer secret');
      expect(sent.body['model'], 'test-model');
      expect(sent.body['stream'], isTrue);
      expect(sent.body.containsKey('tools'), isFalse);
      final messages = sent.body['messages'] as List;
      expect(messages, hasLength(1));
      expect((messages.single as Map)['role'], 'user');
      expect((messages.single as Map)['content'], contains(goal));
    });

    test('an HTTP rejection fails the start honestly and retry can succeed',
        () async {
      ollama.respond = (request) =>
          request.reject(404, {'error': "model 'test-model' not found"});
      final id = await enqueue();
      await expectLater(
          execution.start(id: id, scope: scope, requestId: 'start'),
          throwsA(isA<WorkbenchTaskQueueExecutionException>()));
      final failed = await snapshot(id);
      expect(failed.status, TaskStatus.failed);
      expect(failed.failureReason, 'runtime_start_failed');
      expect(failed.resultPreview, isNull);

      ollama.respond = (request) => request.stream(['Recovered.']);
      expect(await execution.retry(id: id, scope: scope, requestId: 'retry'),
          isTrue);
      await execution.waitForAttempt(id);
      final done = await snapshot(id);
      expect(done.status, TaskStatus.completed);
      expect(done.retryCount, 1);
      expect(done.resultPreview, 'Recovered.');
    });

    test('a provider error mid-stream fails the attempt', () async {
      ollama.respond = (request) => request.stream(['partial'],
          trailer: {'error': 'upstream overloaded'});
      final id = await enqueue();
      await execution.start(id: id, scope: scope, requestId: 'start');
      await execution.waitForAttempt(id);
      final failed = await snapshot(id);
      expect(failed.status, TaskStatus.failed);
      expect(failed.failureReason, 'provider_execution_failed');
    });

    test('a length cut-off is not reported as a completed result', () async {
      ollama.respond =
          (request) => request.stream(['truncated'], doneReason: 'length');
      final id = await enqueue();
      await execution.start(id: id, scope: scope, requestId: 'start');
      await execution.waitForAttempt(id);
      expect((await snapshot(id)).status, TaskStatus.failed);
    });

    test('a dropped stream waits for explicit resume with the partial text',
        () async {
      ollama.respond = (request) => request.stream(['Half of it'], done: false);
      final id = await enqueue();
      await execution.start(id: id, scope: scope, requestId: 'start');
      await execution.waitForAttempt(id);
      final blocked = await snapshot(id);
      expect(blocked.status, TaskStatus.blocked);
      expect(blocked.interruptedReason, 'runtime_connection_lost');
      expect(blocked.resultPreview, 'Half of it');

      ollama.respond = (request) => request.stream(['Complete answer.']);
      expect(await execution.resume(id: id, scope: scope, requestId: 'resume'),
          isTrue);
      await execution.waitForAttempt(id);
      final done = await snapshot(id);
      expect(done.status, TaskStatus.completed);
      expect(done.resultPreview, 'Complete answer.');
      final resumedPrompt = ((ollama.requests.last.body['messages'] as List)
          .single as Map)['content'] as String;
      expect(resumedPrompt, contains('Half of it'));
    });

    test('pause stops the stream in-process and resume reruns it', () async {
      final hold = Completer<void>();
      ollama.respond = (request) => request.stream(['Draft'], holdUntil: hold);
      final id = await enqueue();
      await execution.start(id: id, scope: scope, requestId: 'start');
      await until(() async => (await snapshot(id)).resultPreview == 'Draft');

      expect(await execution.pause(id: id, scope: scope, requestId: 'pause'),
          isTrue);
      final paused = await snapshot(id);
      expect(paused.status, TaskStatus.blocked);
      expect(paused.executionPhase, 'paused');
      hold.complete();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect((await snapshot(id)).resultPreview, 'Draft');

      ollama.respond = (request) => request.stream(['Final.']);
      await execution.resume(id: id, scope: scope, requestId: 'resume');
      await execution.waitForAttempt(id);
      expect((await snapshot(id)).status, TaskStatus.completed);
      expect(ollama.requests, hasLength(2));
    });

    test('cancel ends a running stream and keeps the task cancelled',
        () async {
      final hold = Completer<void>();
      ollama.respond = (request) => request.stream(['Start'], holdUntil: hold);
      final id = await enqueue();
      await execution.start(id: id, scope: scope, requestId: 'start');
      await until(() async => (await snapshot(id)).resultPreview == 'Start');
      expect(await execution.cancel(id: id, scope: scope, requestId: 'cancel'),
          isTrue);
      hold.complete();
      expect((await snapshot(id)).status, TaskStatus.cancelled);
    });

    test('host shutdown stops a running attempt and confirms cleanup',
        () async {
      final hold = Completer<void>();
      ollama.respond = (request) => request.stream(['Mid'], holdUntil: hold);
      final id = await enqueue();
      await execution.start(id: id, scope: scope, requestId: 'start');
      await until(() async => (await snapshot(id)).resultPreview == 'Mid');
      expect(await execution.closeForHostLifecycle(), isTrue);
      hold.complete();
      final stopped = await snapshot(id);
      expect(stopped.status, TaskStatus.blocked);
      expect(stopped.interruptedReason, 'runtime_connection_lost');
    });
  });

  test('without a model the production tool keeps the task pending', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    TaskRoomService.init(db);
    final tool = WorkbenchRuntimeTaskQueueTool.production(
      runtime: const UnconfiguredTextTaskBackend(),
      lifecycleOwner: WorkbenchTaskQueueLifecycleOwner(),
    );
    final enqueued = await tool.invoke({
      'request_id': 'synthetic-enqueue',
      'action': 'enqueue',
      'title': 'synthetic',
      'goal': 'Write fictional text',
    },
        authorization: tool.authorizationForTurn(
            conversationId: 'synthetic', userText: '创建后台任务'));
    expect(enqueued.success, isTrue);
    final id = (jsonDecode(enqueued.text)['task'] as Map)['task_id'] as String;

    final started = await tool.invoke(
        {'request_id': 'synthetic-start', 'action': 'start', 'task_id': id},
        authorization: tool.authorizationForTurn(
            conversationId: 'synthetic', userText: '启动长任务 $id'));
    expect(started.success, isFalse);
    final output = jsonDecode(started.text) as Map<String, dynamic>;
    expect(output['error_code'], 'text_task_model_unconfigured');
    expect(output['message'], contains('HIA_TASK_OLLAMA_MODEL'));
    final state = (await TaskRoomService.instance.getTaskQueueSnapshot(id))!;
    expect(state.status, TaskStatus.pending);
    expect(state.retryCount, 0);
    expect(state.failureReason, isNull);
  });
}

Future<void> until(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class RecordedRequest {
  RecordedRequest(this.path, this.authorization, this.body);
  final String path;
  final String? authorization;
  final Map<String, dynamic> body;
}

/// Minimal `/api/chat` stand-in on loopback with real HTTP streaming.
class FakeOllama {
  FakeOllama._(this._server);

  static Future<FakeOllama> start() async {
    final fake =
        FakeOllama._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    fake._server.listen(fake._handle);
    return fake;
  }

  final HttpServer _server;
  final List<RecordedRequest> requests = [];
  late Future<void> Function(FakeOllamaRequest request) respond;

  Uri get baseUri => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> _handle(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    requests.add(RecordedRequest(
      request.uri.path,
      request.headers.value(HttpHeaders.authorizationHeader),
      jsonDecode(raw) as Map<String, dynamic>,
    ));
    try {
      await respond(FakeOllamaRequest(request.response));
    } on Object {
      // The client may abort a held stream; that is the behaviour under test.
    }
  }

  Future<void> close() => _server.close(force: true);
}

class FakeOllamaRequest {
  FakeOllamaRequest(this.response);
  final HttpResponse response;

  Future<void> reject(int status, Map<String, dynamic> body) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> stream(
    List<String> parts, {
    bool done = true,
    String doneReason = 'stop',
    Map<String, dynamic>? trailer,
    Completer<void>? holdUntil,
  }) async {
    response.bufferOutput = false;
    response.headers.contentType = ContentType('application', 'x-ndjson');
    for (final part in parts) {
      response.writeln(jsonEncode({
        'model': 'test-model',
        'message': {'role': 'assistant', 'content': part},
        'done': false,
      }));
      await response.flush();
    }
    if (holdUntil != null) {
      await holdUntil.future;
      response.writeln(jsonEncode({
        'model': 'test-model',
        'message': {'role': 'assistant', 'content': ' late output'},
        'done': false,
      }));
    }
    if (trailer != null) response.writeln(jsonEncode(trailer));
    if (done && trailer == null) {
      response.writeln(jsonEncode({
        'model': 'test-model',
        'message': {'role': 'assistant', 'content': ''},
        'done': true,
        'done_reason': doneReason,
      }));
    }
    await response.close();
  }
}
