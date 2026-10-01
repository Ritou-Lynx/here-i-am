import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/workbench_ai/product/workbench_product_chat_store.dart';
import 'package:memex/data/workbench_ai/workbench_conversation_coordinator.dart';
import 'package:memex/data/workbench_ai/workbench_desktop_conversation_entry.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';
import 'package:memex/db/app_database.dart';

void main() {
  late AppDatabase database;
  late WorkbenchProductChatStore store;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    store = WorkbenchProductChatStore(
      database: database,
      conversationId: 'candidate-conversation',
    );
  });

  tearDown(() => database.close());

  test('keeps original text and never creates an outbox row', () async {
    await store.addUserMessage('i', '  保留这一段原话  ');
    final messages = await store.getMessages();

    expect(messages.single.content, '  保留这一段原话  ');
    expect(messages.single.originDeviceId, isNull);
    expect(await database.select(database.syncOutboxMessages).get(), isEmpty);
  });

  test('rejects a different role, attachments, blank, and oversized input',
      () async {
    expect(() => store.addUserMessage('other', 'hello'), throwsArgumentError);
    expect(
      () => store.addUserMessage('i', 'hello', attachments: const [{}]),
      throwsArgumentError,
    );
    expect(() => store.addUserMessage('i', '  '), throwsArgumentError);
    expect(
      () => WorkbenchProductChatStore(
        database: database,
        conversationId: 'candidate-conversation',
        maximumInputLength: 2,
      ).addUserMessage('i', 'abc'),
      throwsArgumentError,
    );
    expect(
      () => WorkbenchProductChatStore(
        database: database,
        conversationId: 'candidate-conversation',
        maximumInputLength:
            WorkbenchProductChatStore.maximumSupportedInputLength + 1,
      ),
      throwsArgumentError,
    );
  });

  test('shared entry persists before it calls the real coordinator seam',
      () async {
    final coordinator = WorkbenchConversationCoordinator(
      runtime: _CompletedRuntime(),
      addReply: store.addCharacterMessage,
      pollInterval: Duration.zero,
    );
    var persistedBeforeConnector = false;

    final result = await sendPersonaDesktopConversationEntry(
      chatService: store,
      coordinator: coordinator,
      conversationId: store.conversationId,
      characterId: 'i',
      userText: '普通入口原话',
      connector: ({
        required coordinator,
        required conversationId,
        required characterId,
        required userText,
        required userMessageId,
        onDelta,
      }) async {
        final persisted = await store.getMessages();
        persistedBeforeConnector = persisted.single.id == userMessageId &&
            persisted.single.content == userText;
        return const WorkbenchConversationResult(
          outcome: WorkbenchConversationOutcome.completed,
          message: 'fixture',
        );
      },
    );

    expect(result.outcome, WorkbenchConversationOutcome.completed);
    expect(persistedBeforeConnector, isTrue);
  });
}

class _CompletedRuntime implements WorkbenchConversationRuntimeGateway {
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
  }) async =>
      const WorkbenchRuntimeEvents(
        status: 'idle',
        events: [],
        nextSequence: 0,
      );

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
  }) async =>
      const WorkbenchRuntimeSession(
        sessionId: 'session',
        provider: 'fixture',
        providerSessionId: 'fixture',
      );

  @override
  Future<WorkbenchRuntimeTurn> startTurn(
          String sessionId, String input) async =>
      const WorkbenchRuntimeTurn(turnId: 'turn');
}
