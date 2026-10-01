import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_runtime_task_queue_tool.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';
import 'package:memex/db/app_database.dart';

void main() {
  test(
      'production composition enqueues without transport, fixed profile refusal never sends a turn',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    TaskRoomService.init(db);
    final adapter = TextAdapter(rejectProfile: true);
    final wrapper = WorkbenchRuntimeTaskQueueTool.production(
        runtime: WorkbenchTextTaskRuntimeClient(
            dio: Dio()..httpClientAdapter = adapter));
    final enqueue = await wrapper.invoke({
      'request_id': 'synthetic-enqueue',
      'action': 'enqueue',
      'title': 'synthetic',
      'goal': 'Write fictional text'
    },
        authorization: wrapper.authorizationForTurn(
            conversationId: 'synthetic', userText: '创建后台任务'));
    expect(enqueue.success, true);
    expect(adapter.requests, isEmpty);
    final id = jsonDecode(enqueue.text)['task']['task_id'] as String? ??
        jsonDecode(enqueue.text)['task']['id'] as String;
    final started = await wrapper.invoke(
        {'request_id': 'synthetic-start', 'action': 'start', 'task_id': id},
        authorization: wrapper.authorizationForTurn(
            conversationId: 'synthetic', userText: '启动长任务 $id'));
    expect(started.success, false);
    expect(jsonDecode(started.text)['error_code'],
        'text_only_isolation_unverified');
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.path, endsWith('/sessions'));
    final state = (await TaskRoomService.instance.getTaskQueueSnapshot(id))!;
    expect(state.status.value, 'failed');
    expect(state.failureReason, 'text_only_isolation_unverified');
    expect(state.progressPercent, 0);
    expect(state.resultPreview, isNull);
    expect(state.currentStep, contains('未启动任务'));
    await db.close();
  });

  test(
      'production text request chooses only fixed profile, 501 never falls back',
      () async {
    final adapter = TextAdapter(rejectProfile: true);
    final client =
        WorkbenchTextTaskRuntimeClient(dio: Dio()..httpClientAdapter = adapter);
    await expectLater(
        client.startTextTaskSession(contextManifest: const {
          'task_id': 'synthetic',
          'execution_epoch': 'epoch-1'
        }),
        runtimeError('unsupported_capability'));
    expect(adapter.requests, hasLength(1));
    expect((adapter.requests.single.data as Map)['config'],
        {'runtime_profile': 'workbench_text_only_v1'});
    expect(adapter.requests.single.path, endsWith('/sessions'));
  });

  test('generic DELETE after an invalid creation receipt cannot confirm cleanup',
      () async {
    final adapter = TextAdapter(verifyIsolation: false);
    final client =
        WorkbenchTextTaskRuntimeClient(dio: Dio()..httpClientAdapter = adapter);
    await expectLater(
        client.startTextTaskSession(
            contextManifest: const {'execution_epoch': 'epoch-1'}),
        throwsA(isA<WorkbenchTextTaskIsolationException>()
            .having((e) => e.cleanupConfirmed, 'cleanupConfirmed', false)));
    await expectLater(client.startTurn('text-session', 'do work'),
        runtimeError('unsupported_capability'));
    expect(adapter.requests.map((r) => r.method), ['POST', 'DELETE']);
    expect(adapter.requests.where((r) => r.path.endsWith('/turns')), isEmpty);
  });

  test(
      'synthetic verified receipt permits one turn; terminal receipt closes it',
      () async {
    final adapter = TextAdapter();
    final client =
        WorkbenchTextTaskRuntimeClient(dio: Dio()..httpClientAdapter = adapter);
    final session = await client.startTextTaskSession(
        contextManifest: const {'execution_epoch': 'epoch-1'});
    final turn = await client.startTextTaskTurn(session, 'fictional input');
    await expectLater(client.startTextTaskTurn(session, 'duplicate'),
        runtimeError('unsupported_capability'));
    await client.closeTextTaskSession(
        session: session, turn: turn, interruptRequested: true);
    expect(
        adapter.requests.where((r) => r.path.endsWith('/turns')), hasLength(1));
  });

  test('unverified session cleanup failure is explicit and cannot start a turn',
      () async {
    final adapter = TextAdapter(verifyIsolation: false, closeFails: true);
    final client =
        WorkbenchTextTaskRuntimeClient(dio: Dio()..httpClientAdapter = adapter);
    await expectLater(
        client.startTextTaskSession(
            contextManifest: const {'execution_epoch': 'epoch-1'}),
        throwsA(isA<WorkbenchTextTaskIsolationException>()
            .having((e) => e.cleanupConfirmed, 'cleanupConfirmed', false)));
    await expectLater(client.startTurn('text-session', 'work'),
        runtimeError('unsupported_capability'));
    expect(adapter.requests.map((r) => r.method), ['POST', 'DELETE']);
  });

  test('malformed provider metadata does not make generic cleanup proof valid',
      () async {
    final adapter = TextAdapter(malformedProviderMetadata: true);
    final client =
        WorkbenchTextTaskRuntimeClient(dio: Dio()..httpClientAdapter = adapter);
    await expectLater(
        client.startTextTaskSession(
            contextManifest: const {'execution_epoch': 'epoch-1'}),
        throwsA(isA<WorkbenchTextTaskIsolationException>()
            .having((e) => e.cleanupConfirmed, 'cleanupConfirmed', false)));
    expect(
        adapter.requests.map((request) => request.method), ['POST', 'DELETE']);
  });

  test('concurrent turn starts reserve the verified session before transport',
      () async {
    final adapter = TextAdapter();
    final client =
        WorkbenchTextTaskRuntimeClient(dio: Dio()..httpClientAdapter = adapter);
    final session = await client.startTextTaskSession(
        contextManifest: const {'execution_epoch': 'epoch-1'});
    final first = client.startTextTaskTurn(session, 'first');
    await expectLater(client.startTextTaskTurn(session, 'duplicate'),
        runtimeError('unsupported_capability'));
    await first;
    expect(
        adapter.requests.where((r) => r.path.endsWith('/turns')), hasLength(1));
  });

  test('a reserved turn start can retry teardown but remains unconfirmed',
      () async {
    final adapter = TextAdapter(turnGate: Completer<void>());
    final client =
        WorkbenchTextTaskRuntimeClient(dio: Dio()..httpClientAdapter = adapter);
    final session = await client.startTextTaskSession(
        contextManifest: const {'execution_epoch': 'epoch-1'});
    final starting = client.startTextTaskTurn(session, 'fictional input');
    await expectLater(
        client.closeTextTaskSession(
            session: session, interruptRequested: false),
        runtimeError('runtime_stop_unconfirmed'));
    expect(adapter.requests.where((request) => request.method == 'DELETE'),
        hasLength(1));
    adapter.turnGate!.complete();
    await expectLater(starting, runtimeError('runtime_stop_unconfirmed'));
    await expectLater(
        client.closeTextTaskSession(
            session: session, interruptRequested: false),
        runtimeError('runtime_stop_unconfirmed'));
    expect(adapter.requests.where((request) => request.method == 'DELETE'),
        hasLength(2));
  });

  for (final wrongSession in [false, true]) {
    test(
        'close requires provider confirmation bound to exact session ($wrongSession)',
        () async {
      final adapter = TextAdapter(
          confirmStop: wrongSession, wrongStopSession: wrongSession);
      final client = WorkbenchTextTaskRuntimeClient(
          dio: Dio()..httpClientAdapter = adapter);
      final session = await client.startTextTaskSession(
          contextManifest: const {'execution_epoch': 'epoch-1'});
      final turn = await client.startTextTaskTurn(session, 'fictional input');
      await expectLater(
          client.closeTextTaskSession(
              session: session, turn: turn, interruptRequested: true),
          runtimeError('runtime_stop_unconfirmed'));
    });
  }

  test('completed terminal permits ordinary cleanup but never confirms cancel',
      () async {
    final adapter = TextAdapter(stopStatus: 'completed');
    final client =
        WorkbenchTextTaskRuntimeClient(dio: Dio()..httpClientAdapter = adapter);
    final session = await client.startTextTaskSession(
        contextManifest: const {'execution_epoch': 'epoch-1'});
    final turn = await client.startTextTaskTurn(session, 'fictional input');
    final result = await client.closeTextTaskSession(
        session: session, turn: turn, interruptRequested: true);
    expect(result.ordinaryCloseConfirmed, true);
    expect(result.cancellationConfirmed, false);
  });

  test('terminal sequence must follow this interrupt dispatch', () async {
    final adapter = TextAdapter(dispatchSequence: 2, terminalSequence: 2);
    final client =
        WorkbenchTextTaskRuntimeClient(dio: Dio()..httpClientAdapter = adapter);
    final session = await client.startTextTaskSession(
        contextManifest: const {'execution_epoch': 'epoch-1'});
    final turn = await client.startTextTaskTurn(session, 'fictional input');
    final result = await client.closeTextTaskSession(
        session: session, turn: turn, interruptRequested: true);
    expect(result.ordinaryCloseConfirmed, true);
    expect(result.cancellationConfirmed, false);
  });

  test('dispatch sequence zero can precede an interrupted terminal', () async {
    final adapter = TextAdapter(dispatchSequence: 0, terminalSequence: 1);
    final client =
        WorkbenchTextTaskRuntimeClient(dio: Dio()..httpClientAdapter = adapter);
    final session = await client.startTextTaskSession(
        contextManifest: const {'execution_epoch': 'epoch-1'});
    final turn = await client.startTextTaskTurn(session, 'fictional input');
    final result = await client.closeTextTaskSession(
        session: session, turn: turn, interruptRequested: true);
    expect(result.cancellationConfirmed, true);
  });

  test('concurrent canonical closes issue one physical delete', () async {
    final adapter = TextAdapter();
    final client =
        WorkbenchTextTaskRuntimeClient(dio: Dio()..httpClientAdapter = adapter);
    final session = await client.startTextTaskSession(
        contextManifest: const {'execution_epoch': 'epoch-1'});
    final turn = await client.startTextTaskTurn(session, 'fictional input');
    final results = await Future.wait([
      client.closeTextTaskSession(
          session: session, turn: turn, interruptRequested: true),
      client.closeTextTaskSession(
          session: session, turn: turn, interruptRequested: true),
    ]);
    expect(results.map((result) => result.cancellationConfirmed), [true, true]);
    expect(adapter.requests.where((request) => request.method == 'DELETE'),
        hasLength(1));
  });

  test('failed close retries the same bound session and can later confirm',
      () async {
    final adapter = TextAdapter(closeFailures: 1);
    final client =
        WorkbenchTextTaskRuntimeClient(dio: Dio()..httpClientAdapter = adapter);
    final session = await client.startTextTaskSession(
        contextManifest: const {'execution_epoch': 'epoch-1'});
    final turn = await client.startTextTaskTurn(session, 'fictional input');
    await expectLater(
        client.closeTextTaskSession(
            session: session, turn: turn, interruptRequested: true),
        runtimeError('runtime_unavailable'));
    final result = await client.closeTextTaskSession(
        session: session, turn: turn, interruptRequested: true);
    expect(result.ordinaryCloseConfirmed, true);
    expect(result.cancellationConfirmed, true);
    expect(adapter.requests.where((request) => request.method == 'DELETE'),
        hasLength(2));
    expect(adapter.requests.where((request) => request.method == 'POST'),
        hasLength(2));
  });

  test(
      'unknown start remains unconfirmed across retry even with a no-turn receipt',
      () async {
    final gate = Completer<void>();
    final adapter =
        TextAdapter(turnGate: gate, closeFailures: 1, noTurnReceipt: true);
    final client =
        WorkbenchTextTaskRuntimeClient(dio: Dio()..httpClientAdapter = adapter);
    final session = await client.startTextTaskSession(
        contextManifest: const {'execution_epoch': 'epoch-1'});
    final starting = client.startTextTaskTurn(session, 'fictional input');
    await expectLater(
        client.closeTextTaskSession(
            session: session, interruptRequested: false),
        runtimeError('runtime_stop_unconfirmed'));
    await expectLater(
        client.closeTextTaskSession(
            session: session, interruptRequested: false),
        runtimeError('runtime_stop_unconfirmed'));
    expect(adapter.requests.where((request) => request.method == 'DELETE'),
        hasLength(2));
    gate.complete();
    await expectLater(starting, runtimeError('runtime_stop_unconfirmed'));
  });

  test('retry rejects changed stop policy or turn without another delete',
      () async {
    final adapter = TextAdapter(closeFailures: 1);
    final client =
        WorkbenchTextTaskRuntimeClient(dio: Dio()..httpClientAdapter = adapter);
    final session = await client.startTextTaskSession(
        contextManifest: const {'execution_epoch': 'epoch-1'});
    final turn = await client.startTextTaskTurn(session, 'fictional input');
    await expectLater(
        client.closeTextTaskSession(
            session: session, turn: turn, interruptRequested: true),
        runtimeError('runtime_unavailable'));
    await expectLater(
        client.closeTextTaskSession(
            session: session, turn: turn, interruptRequested: false),
        runtimeError('runtime_stop_unconfirmed'));
    const forged = WorkbenchTextTaskTurn(
      localTurnId: 'forged-local-turn',
      providerTurnId: 'forged-provider-turn',
      executionEpoch: 'epoch-1',
    );
    await expectLater(
        client.closeTextTaskSession(
            session: session, turn: forged, interruptRequested: true),
        runtimeError('runtime_stop_unconfirmed'));
    expect(adapter.requests.where((request) => request.method == 'DELETE'),
        hasLength(1));
  });

  test('successful close remains cached for its exact binding', () async {
    final adapter = TextAdapter();
    final client =
        WorkbenchTextTaskRuntimeClient(dio: Dio()..httpClientAdapter = adapter);
    final session = await client.startTextTaskSession(
        contextManifest: const {'execution_epoch': 'epoch-1'});
    final turn = await client.startTextTaskTurn(session, 'fictional input');
    await client.closeTextTaskSession(
        session: session, turn: turn, interruptRequested: true);
    await client.closeTextTaskSession(
        session: session, turn: turn, interruptRequested: true);
    expect(adapter.requests.where((request) => request.method == 'DELETE'),
        hasLength(1));
  });

  test('a forged turn cannot inherit a cached canonical close receipt',
      () async {
    final adapter = TextAdapter();
    final client =
        WorkbenchTextTaskRuntimeClient(dio: Dio()..httpClientAdapter = adapter);
    final session = await client.startTextTaskSession(
        contextManifest: const {'execution_epoch': 'epoch-1'});
    final turn = await client.startTextTaskTurn(session, 'fictional input');
    await client.closeTextTaskSession(
        session: session, turn: turn, interruptRequested: true);
    const forged = WorkbenchTextTaskTurn(
      localTurnId: 'forged-local-turn',
      providerTurnId: 'forged-provider-turn',
      executionEpoch: 'epoch-1',
    );
    await expectLater(
        client.closeTextTaskSession(
            session: session, turn: forged, interruptRequested: true),
        runtimeError('runtime_stop_unconfirmed'));
    expect(adapter.requests.where((request) => request.method == 'DELETE'),
        hasLength(1));
  });

  test('no-turn cleanup requires the explicit closed-without-turn outcome',
      () async {
    final adapter = TextAdapter(noTurnReceipt: true);
    final client =
        WorkbenchTextTaskRuntimeClient(dio: Dio()..httpClientAdapter = adapter);
    final session = await client.startTextTaskSession(
        contextManifest: const {'execution_epoch': 'epoch-1'});
    final result = await client.closeTextTaskSession(
        session: session, interruptRequested: false);
    expect(result.ordinaryCloseConfirmed, true);
    expect(result.cancellationConfirmed, false);
  });

  test('forged session bindings are rejected before turn or close transport',
      () async {
    final adapter = TextAdapter();
    final client =
        WorkbenchTextTaskRuntimeClient(dio: Dio()..httpClientAdapter = adapter);
    final session = await client.startTextTaskSession(
        contextManifest: const {'execution_epoch': 'epoch-1'});
    final forged = WorkbenchTextTaskSession(
      sessionId: session.sessionId,
      provider: session.provider,
      providerSessionId: session.providerSessionId,
      providerThreadId: session.providerThreadId,
      executionEpoch: 'epoch-2',
    );
    await expectLater(client.startTextTaskTurn(forged, 'fictional input'),
        runtimeError('unsupported_capability'));
    await expectLater(
        client.closeTextTaskSession(session: forged, interruptRequested: false),
        runtimeError('runtime_stop_unconfirmed'));
    expect(adapter.requests.where((request) => request.method == 'DELETE'),
        isEmpty);
  });

  test(
      'product tools and persisted persona resume are rejected before transport',
      () async {
    final adapter = TextAdapter();
    final client =
        WorkbenchTextTaskRuntimeClient(dio: Dio()..httpClientAdapter = adapter);
    expect(
        () => client.startSession(dynamicTools: const [
              {'name': 'any_tool'}
            ]),
        runtimeError('unsupported_capability'));
    expect(
        () => client.resumeSession(
            provider: 'codex',
            providerSessionId: 'persona-session',
            dynamicTools: const []),
        runtimeError('unsupported_capability'));
    expect(adapter.requests, isEmpty);
  });
}

Matcher runtimeError(String code) => throwsA(isA<WorkbenchRuntimeException>()
    .having((error) => error.code, 'code', code));

class TextAdapter implements HttpClientAdapter {
  TextAdapter(
      {this.rejectProfile = false,
      this.verifyIsolation = true,
      this.confirmStop = true,
      this.wrongStopSession = false,
      this.stopStatus = 'interrupted',
      this.noTurnReceipt = false,
      this.malformedProviderMetadata = false,
      this.dispatchSequence = 1,
      this.terminalSequence = 2,
      this.turnGate,
      this.closeFails = false,
      int closeFailures = 0})
      : _remainingCloseFailures = closeFailures;
  final bool rejectProfile;
  final bool verifyIsolation;
  final bool confirmStop;
  final bool wrongStopSession;
  final String stopStatus;
  final bool noTurnReceipt;
  final bool malformedProviderMetadata;
  final int dispatchSequence;
  final int terminalSequence;
  final Completer<void>? turnGate;
  final bool closeFails;
  int _remainingCloseFailures;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<dynamic>? cancelFuture) async {
    requests.add(options);
    if (options.method == 'DELETE' &&
        (closeFails || _remainingCloseFailures > 0)) {
      if (_remainingCloseFailures > 0) _remainingCloseFailures--;
      throw DioException(
          requestOptions: options, type: DioExceptionType.connectionError);
    }
    final rejected = rejectProfile && options.path.endsWith('/sessions');
    final Map<String, dynamic> body;
    if (rejected) {
      body = {
        'error': {
          'code': 'unsupported_capability',
          'message': 'text_only_isolation_unverified'
        }
      };
    } else if (options.method == 'DELETE') {
      body = {
        'status': 'closed',
        'stop_receipt': {
          'profile': 'workbench_text_only_v1',
          'version': 2,
          'local_session_id':
              wrongStopSession ? 'another-session' : 'text-session',
          'execution_epoch': 'epoch-1',
          'provider_thread_id': 'synthetic-provider-session',
          'outcome': noTurnReceipt ? 'closed_without_turn' : 'closed',
          'local_turn_id': noTurnReceipt ? null : 'local-turn',
          'turn_id': noTurnReceipt ? null : 'provider-turn',
          'interrupt_dispatched': !noTurnReceipt,
          'interrupt_dispatch_sequence':
              noTurnReceipt ? null : dispatchSequence,
          'provider_terminal_confirmed': noTurnReceipt ? false : confirmStop,
          'provider_terminal_status': noTurnReceipt ? null : stopStatus,
          'provider_terminal_sequence': noTurnReceipt ? null : terminalSequence,
          'cancellation_confirmed':
              noTurnReceipt || stopStatus != 'interrupted' ? false : true,
          'local_child_close_observed': true,
          'proxy_drained': true,
        }
      };
    } else if (options.path.endsWith('/turns')) {
      await turnGate?.future;
      body = {
        'local_session_id': 'text-session',
        'provider_thread_id': 'synthetic-provider-session',
        'execution_epoch': 'epoch-1',
        'local_turn_id': 'local-turn',
        'provider_turn_id': 'provider-turn',
      };
    } else {
      final request = options.data as Map;
      final manifest = request['context_manifest'] as Map;
      final epoch = manifest['execution_epoch'];
      body = {
        'session_id': 'text-session',
        'provider_metadata': {
          'provider': 'synthetic',
          if (!malformedProviderMetadata)
            'provider_session_id': 'synthetic-provider-session'
        },
        if (verifyIsolation)
          'execution_profile_receipt': {
            'profile': 'workbench_text_only_v1',
            'version': 2,
            'local_session_id': 'text-session',
            'execution_epoch': epoch,
            'provider_thread_id': 'synthetic-provider-session',
            'isolation_verified': true,
            'tools_disabled': true,
          },
      };
    }
    return ResponseBody.fromString(jsonEncode(body), rejected ? 501 : 200,
        headers: {
          'content-type': ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}
