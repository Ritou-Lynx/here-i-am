import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/workbench_ai/product/workbench_product_chat_store.dart';
import 'package:memex/data/workbench_ai/workbench_conversation_coordinator.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/p6_r7_product/view_models/p6_r7_product_chat_view_model.dart';
import 'package:memex/ui/p6_r7_product/widgets/p6_r7_product_chat_surface.dart';

void main() {
  late AppDatabase database;
  late _DelayedRuntime runtime;
  late P6R7ProductChatViewModel viewModel;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    runtime = _DelayedRuntime();
    final store = WorkbenchProductChatStore(
      database: database,
      conversationId: 'product-chat',
    );
    viewModel = P6R7ProductChatViewModel(
      store: store,
      conversationId: 'product-chat',
      coordinator: WorkbenchConversationCoordinator(
        runtime: runtime,
        addReply: store.addCharacterMessage,
        pollInterval: Duration.zero,
      ),
    );
  });

  tearDown(() => database.close());

  test('rejects concurrent sends and quiesce fences while joining the turn',
      () async {
    final first = viewModel.send('第一条原话');
    await runtime.turnStarted.future;
    final busy = await viewModel.send('第二条原话');
    var drained = false;
    final drain = viewModel.quiesce().then((_) => drained = true);

    expect(busy.errorCode, 'conversation_busy');
    expect(drained, isFalse);
    runtime.complete();
    await first;
    await drain;
    expect(drained, isTrue);
    expect((await viewModel.store.getMessages()).map((row) => row.content),
        contains('第一条原话'));
    expect((await viewModel.store.getMessages()).map((row) => row.content),
        isNot(contains('第二条原话')));
  });

  test('dispose fences asynchronous notifications', () async {
    var notifications = 0;
    viewModel.addListener(() => notifications++);
    final pending = viewModel.send('晚到的结果');
    await runtime.turnStarted.future;
    viewModel.dispose();
    final before = notifications;
    runtime.complete();
    await pending;
    await Future<void>.delayed(Duration.zero);
    expect(notifications, before);
  });

  test(
      'invalid input returns a readable failure without persistence or runtime',
      () async {
    final result = await viewModel.send('  ');

    expect(result.errorCode, 'product_chat_input_rejected');
    expect(await viewModel.store.getMessages(), isEmpty);
    expect(runtime.startSessionCalls, 0);
  });

  test('fence after persistence does not start an ordinary coordinator turn',
      () async {
    final delayedStore = _DelayedStore(database, 'product-chat-race');
    final raceRuntime = _DelayedRuntime();
    final raceViewModel = P6R7ProductChatViewModel(
      store: delayedStore,
      conversationId: 'product-chat-race',
      coordinator: WorkbenchConversationCoordinator(
        runtime: raceRuntime,
        addReply: delayedStore.addCharacterMessage,
        pollInterval: Duration.zero,
      ),
    );
    final send = raceViewModel.send('已经保存的原话');
    await delayedStore.insertStarted.future;
    final drain = raceViewModel.quiesce();
    delayedStore.releaseInsert.complete();

    final result = await send;
    await drain;
    expect(result.errorCode, 'conversation_closing_after_persist');
    expect(raceRuntime.startSessionCalls, 0);
    expect((await delayedStore.getMessages()).single.content, '已经保存的原话');
    raceViewModel.dispose();
  });

  test('a completed accepted send only clears its unchanged draft', () {
    expect(
      shouldClearP6R7ProductChatDraft(
        persisted: true,
        submittedText: '已发送原话',
        currentDraft: '等待时新写的草稿',
      ),
      isFalse,
    );
    expect(
      shouldClearP6R7ProductChatDraft(
        persisted: true,
        submittedText: '已发送原话',
        currentDraft: '已发送原话',
      ),
      isTrue,
    );
    expect(
      shouldClearP6R7ProductChatDraft(
        persisted: false,
        submittedText: '无效输入',
        currentDraft: '无效输入',
      ),
      isFalse,
    );
  });
}

class _DelayedStore extends WorkbenchProductChatStore {
  _DelayedStore(AppDatabase database, String conversationId)
      : super(database: database, conversationId: conversationId);

  final insertStarted = Completer<void>();
  final releaseInsert = Completer<void>();

  @override
  Future<int> addUserMessage(
    String characterId,
    String content, {
    DateTime? timestamp,
    List<Map<String, String>>? attachments,
    bool appendTimeline = true,
  }) async {
    insertStarted.complete();
    await releaseInsert.future;
    return super.addUserMessage(
      characterId,
      content,
      timestamp: timestamp,
      attachments: attachments,
      appendTimeline: appendTimeline,
    );
  }
}

class _DelayedRuntime implements WorkbenchConversationRuntimeGateway {
  final turnStarted = Completer<void>();
  final _completion = Completer<void>();
  int startSessionCalls = 0;

  void complete() => _completion.complete();

  @override
  Future<void> closeSession(String sessionId) async {}

  @override
  Future<void> interruptTurn({
    required String sessionId,
    required String turnId,
  }) async {}

  @override
  Future<WorkbenchRuntimeEvents> readEvents(
    String sessionId, {
    int afterSequence = 0,
  }) async {
    await _completion.future;
    return const WorkbenchRuntimeEvents(
      status: 'idle',
      nextSequence: 2,
      events: [
        {
          'sequence': 1,
          'turn_id': 'turn',
          'kind': 'message_delta',
          'status': 'running',
          'data': {'text': '已完成'},
        },
        {
          'sequence': 2,
          'turn_id': 'turn',
          'kind': 'turn_status',
          'status': 'completed',
          'data': {},
        },
      ],
    );
  }

  @override
  Future<void> respondToToolCall({
    required String toolCallId,
    required bool success,
    required String text,
  }) async {}

  @override
  Future<WorkbenchRuntimeSession> resumeSession({
    required String provider,
    required String providerSessionId,
    required List<Map<String, dynamic>> dynamicTools,
  }) async =>
      const WorkbenchRuntimeSession(
        sessionId: 'session',
        provider: 'fixture',
        providerSessionId: 'fixture',
      );

  @override
  Future<WorkbenchRuntimeSession> startSession({
    required List<Map<String, dynamic>> dynamicTools,
    Map<String, dynamic> contextManifest = const {},
  }) async {
    startSessionCalls++;
    return const WorkbenchRuntimeSession(
      sessionId: 'session',
      provider: 'fixture',
      providerSessionId: 'fixture',
    );
  }

  @override
  Future<WorkbenchRuntimeTurn> startTurn(String sessionId, String input) async {
    turnStarted.complete();
    return const WorkbenchRuntimeTurn(turnId: 'turn');
  }
}
