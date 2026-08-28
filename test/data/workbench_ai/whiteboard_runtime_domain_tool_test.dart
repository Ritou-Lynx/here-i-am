import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/data/workbench_ai/whiteboard_runtime_domain_tool.dart';
import 'package:memex/data/workbench_ai/whiteboard_workbench_coordinator.dart';
import 'package:memex/data/workbench_ai/whiteboard_workbench_surface.dart';
import 'package:memex/data/workbench_ai/workbench_action_reader.dart';
import 'package:memex/data/workbench_ai/workbench_conversation_coordinator.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';

void main() {
  late _Harness harness;

  setUp(() async {
    harness = await _Harness.create();
  });

  tearDown(() => harness.dispose());

  test('schema exposes six exact shapes and negative language grants nothing',
      () async {
    final commands = WorkbenchRuntimeWhiteboardDomainTool
        .toolDefinition['input_schema']['properties']['commands'];
    expect(commands['items']['oneOf'], hasLength(6));
    for (final shape in commands['items']['oneOf'] as List) {
      expect(shape['additionalProperties'], isFalse);
      expect(shape['properties']['kind']['const'], isNotEmpty);
    }

    for (final text in [
      '不要在白板创建卡片',
      '别把选中卡片移动到右边',
      '不许修改白板卡片正文',
      '请勿从白板移除卡片',
    ]) {
      expect(
        await harness.tool.prepareAuthorization(
          conversationId: 'persona-i',
          characterId: 'i',
          userText: text,
          userAuthorizationMessageId: 'chat-message-7',
        ),
        isNull,
        reason: text,
      );
    }

    final switchAuthorization = await harness.authorize(
      '请移动白板选中卡片',
      messageId: 'chat-message-switch',
    );
    final missingEvidence = await harness.tool.prepareAuthorization(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '请移动白板选中卡片',
      userAuthorizationMessageId: null,
    );
    expect(missingEvidence?.unavailableReason,
        'authorization_evidence_missing');
    harness.detachSurface();
    final unavailable = await harness.tool.prepareAuthorization(
      conversationId: 'persona-i',
      characterId: 'i',
      userText: '在白板创建一张卡片',
      userAuthorizationMessageId: 'chat-message-8',
    );
    expect(unavailable?.unavailableReason, 'whiteboard_not_open');
    expect(unavailable?.toPromptBlock(), contains('不要改用浏览器工具'));

    final switchedOwner = Object();
    WhiteboardWorkbenchSurfaceController.instance.attach(
      owner: switchedOwner,
      boardId: 'board_1',
      selectedItemIds: {'item_a'},
      flush: () async => true,
      reload: () async {},
    );
    final switched = await harness.tool.invoke(
      {
        'commands': [
          {
            'kind': 'move_placement',
            'item_id': 'item_a',
            'x': 1,
            'y': 2,
          },
        ],
      },
      authorization: switchAuthorization!,
      runtimeTurnId: 'turn-switched',
      isCancelled: () => false,
    );
    expect(jsonDecode(switched.text)['error_code'],
        'whiteboard_surface_changed');
    expect(await harness.actions(), isEmpty);
    WhiteboardWorkbenchSurfaceController.instance.detach(switchedOwner);
  });

  test('ordinary conversation registers and dispatches all six commands',
      () async {
    final runtime = _ToolCallRuntime(_sixCommandPayload);
    final conversation = WorkbenchConversationCoordinator.productionComposition(
      runtime: runtime,
      whiteboardToolFactory: () => harness.tool,
      addReply: (_, __) async => 1,
      pollInterval: Duration.zero,
      turnTimeout: const Duration(seconds: 5),
    );
    final result = await conversation.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userMessageId: 41,
      userText: '请在白板创建卡片，编辑正文和标签，移动、缩放并从白板移除选中卡片',
    );

    expect(result.outcome, WorkbenchConversationOutcome.completed);
    expect(runtime.dynamicTools.single['name'],
        WorkbenchRuntimeWhiteboardDomainTool.toolName);
    expect(runtime.responses.single.success, isTrue);
    final receipt = jsonDecode(runtime.responses.single.text);
    expect(receipt['status'], 'applied');
    expect(receipt['command_ids'], hasLength(6));
    final snapshot = (await harness.store.load('board_1')).snapshot!;
    expect(snapshot.boardItems, hasLength(1));
    expect(snapshot.boardItems.single.cardId, startsWith('card:'));
    expect(snapshot.cards.any((card) => card.cardId == 'card_a'), isTrue,
        reason: 'remove placement must not delete the existing Card truth');
    expect(await harness.repository.getCard('card_a'), isNotNull);
    final actions = await harness.actions();
    expect(actions, hasLength(1));
    expect(actions.single.projection.status.name, 'completed');
    expect(actions.single.projection.userAuthorizationMessageId,
        'chat-message-41');

    final authorization = await harness.authorize(
      '请在白板创建卡片，编辑正文和标签，移动、缩放并从白板移除选中卡片',
      messageId: 'chat-message-42',
    );
    expect(authorization, isNotNull);
    final malformed = await harness.tool.invoke(
      {
        ..._sixCommandPayload,
        'board_id': 'model-expanded-scope',
      },
      authorization: authorization!,
      runtimeTurnId: 'turn-malformed',
      isCancelled: () => false,
    );
    expect(malformed.success, isFalse);
    expect(
        jsonDecode(malformed.text)['error_code'], 'invalid_whiteboard_request');
  });

  test('same turn retry is idempotent and target/hash expansion fails closed',
      () async {
    final authorization = await harness.authorize(
      '请移动白板选中卡片',
      messageId: 'chat-message-50',
    );
    final payload = {
      'commands': [
        {
          'kind': 'move_placement',
          'item_id': 'item_a',
          'x': 45,
          'y': 12,
        },
      ],
    };
    final first = await harness.tool.invoke(
      payload,
      authorization: authorization!,
      runtimeTurnId: 'turn-retry',
      isCancelled: () => false,
    );
    final second = await harness.tool.invoke(
      payload,
      authorization: authorization,
      runtimeTurnId: 'turn-retry',
      isCancelled: () => false,
    );
    expect(first.success, isTrue);
    expect(second.text, first.text);
    expect(await harness.actions(), hasLength(1));

    final outOfScope = await harness.tool.invoke(
      {
        'commands': [
          {
            'kind': 'move_placement',
            'item_id': 'item_not_selected',
            'x': 1,
            'y': 2,
          },
        ],
      },
      authorization: authorization,
      runtimeTurnId: 'turn-overreach',
      isCancelled: () => false,
    );
    expect(jsonDecode(outOfScope.text)['error_code'],
        'whiteboard_target_outside_scope');

    final capabilityExpansion = await harness.tool.invoke(
      {
        'commands': [
          {
            'kind': 'resize_placement',
            'item_id': 'item_a',
            'width': 400,
            'height': 300,
          },
        ],
      },
      authorization: authorization,
      runtimeTurnId: 'turn-capability-expansion',
      isCancelled: () => false,
    );
    expect(jsonDecode(capabilityExpansion.text)['error_code'],
        'whiteboard_capability_denied');

    final conflictAuthorization = await harness.authorize(
      '请移动白板选中卡片',
      messageId: 'chat-message-51',
    );
    final current = (await harness.store.load('board_1')).snapshot!;
    expect(
      await harness.store.seed(
        'board_1',
        WhiteboardSnapshot.fromJson({
          ...current.toJson(),
          'viewport': const BoardViewport(centerX: 99).toJson(),
        }),
      ),
      isTrue,
    );
    final conflict = await harness.tool.invoke(
      payload,
      authorization: conflictAuthorization!,
      runtimeTurnId: 'turn-conflict',
      isCancelled: () => false,
    );
    expect(conflict.success, isFalse);
    expect(jsonDecode(conflict.text)['status'], 'conflict');
    expect(
      (await harness.store.load('board_1')).snapshot!.viewport.centerX,
      99,
    );
  });

  test('save failure retries safely and reload/unlock cannot hide a receipt',
      () async {
    final authorization = await harness.authorize(
      '请移动白板选中卡片',
      messageId: 'chat-message-55',
    );
    final payload = {
      'commands': [
        {
          'kind': 'move_placement',
          'item_id': 'item_a',
          'x': 33,
          'y': 11,
        },
      ],
    };
    harness.store.failNextSave = true;
    final failed = await harness.tool.invoke(
      payload,
      authorization: authorization!,
      runtimeTurnId: 'turn-save-retry',
      isCancelled: () => false,
    );
    expect(failed.success, isFalse);
    expect(
        (await harness.store.load('board_1')).snapshot!.boardItems.single.x, 0);

    final retried = await harness.tool.invoke(
      payload,
      authorization: authorization,
      runtimeTurnId: 'turn-save-retry',
      isCancelled: () => false,
    );
    expect(retried.success, isTrue);
    expect((await harness.store.load('board_1')).snapshot!.boardItems.single.x,
        33);

    harness.detachSurface();
    WhiteboardWorkbenchSurfaceController.instance.attach(
      owner: harness.surfaceOwner,
      boardId: 'board_1',
      selectedItemIds: {'item_a'},
      flush: () async => true,
      reload: () async => throw StateError('visual reload failed'),
      setInteractionLocked: (locked) {
        if (!locked) throw StateError('disposed visual lock');
      },
    );
    final throwingSurfaceAuthorization = await harness.authorize(
      '请移动白板选中卡片',
      messageId: 'chat-message-56',
    );
    final receipt = await harness.tool.invoke(
      {
        'commands': [
          {
            'kind': 'move_placement',
            'item_id': 'item_a',
            'x': 44,
            'y': 12,
          },
        ],
      },
      authorization: throwingSurfaceAuthorization!,
      runtimeTurnId: 'turn-throwing-surface',
      isCancelled: () => false,
    );
    expect(receipt.success, isTrue,
        reason: 'post-commit visual failures cannot replace the receipt');
    expect((await harness.store.load('board_1')).snapshot!.boardItems.single.x,
        44);
  });

  test(
      'stop after invoke starts waits for receipt before reporting interrupted',
      () async {
    harness.store.gateNextSave();
    final runtime = _ToolCallRuntime({
      'commands': [
        {
          'kind': 'move_placement',
          'item_id': 'item_a',
          'x': 77,
          'y': 8,
        },
      ],
    });
    final conversation = WorkbenchConversationCoordinator(
      runtime: runtime,
      whiteboardTool: harness.tool,
      addReply: (_, __) async => 1,
      pollInterval: Duration.zero,
      turnTimeout: const Duration(seconds: 5),
    );
    final send = conversation.send(
      conversationId: 'persona-i',
      characterId: 'i',
      userMessageId: 60,
      userText: '请移动白板选中卡片',
    );
    await harness.store.saveEntered.future.timeout(const Duration(seconds: 3));
    expect(await conversation.stop('persona-i'), isTrue);
    var sendCompleted = false;
    send.whenComplete(() => sendCompleted = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(sendCompleted, isFalse,
        reason: 'a started Domain commit must not be detached on stop');

    harness.store.releaseSave();
    final result = await send.timeout(const Duration(seconds: 3));
    expect(result.outcome, WorkbenchConversationOutcome.interrupted);
    final atReturn = (await harness.store.load('board_1')).snapshot!;
    expect(atReturn.boardItems.single.x, 77);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      (await harness.store.load('board_1')).snapshot!.toJson(),
      atReturn.toJson(),
      reason: 'no background commit may land after interrupted is returned',
    );
    expect(
        (await harness.actions()).single.projection.status.name, 'completed');
  });

  test('conversation receipt restores undo after restart and stays undone',
      () async {
    final runtime = _ToolCallRuntime({
      'commands': [
        {
          'kind': 'move_placement',
          'item_id': 'item_a',
          'x': 64,
          'y': 32,
        },
      ],
    });
    final conversation = WorkbenchConversationCoordinator.productionComposition(
      runtime: runtime,
      whiteboardToolFactory: () => harness.tool,
      addReply: (_, __) async => 1,
      pollInterval: Duration.zero,
      turnTimeout: const Duration(seconds: 5),
    );
    expect(
      (await conversation.send(
        conversationId: 'persona-i',
        characterId: 'i',
        userMessageId: 70,
        userText: '请移动白板选中卡片',
      ))
          .outcome,
      WorkbenchConversationOutcome.completed,
    );
    final actionId = (await harness.actions()).single.projection.actionId;
    final root = harness.root;

    await harness.closeForRestart();
    harness = await _Harness.reopen(root);
    await harness.coordinator.hydrateUndo('i');
    expect(harness.coordinator.canUndo(actionId), isTrue);
    final undo = await harness.coordinator.undoDomainCommands(
      characterId: 'i',
      actionId: actionId,
    );
    expect(undo?.status.name, 'undone');
    expect(
      (await harness.store.load('board_1')).snapshot!.boardItems.single.x,
      0,
    );

    await harness.closeForRestart();
    harness = await _Harness.reopen(root);
    await harness.coordinator.hydrateUndo('i');
    expect(harness.coordinator.canUndo(actionId), isFalse);
    expect((await harness.actions()).single.projection.status.name, 'undone');
    expect(
      (await harness.store.load('board_1')).snapshot!.boardItems.single.x,
      0,
    );
  });
}

const _sixCommandPayload = {
  'commands': [
    {
      'kind': 'create_card',
      'title': 'Runtime card',
      'body': 'Created by the runtime tool',
      'labels': ['runtime'],
      'x': 10,
      'y': 20,
      'width': 240,
      'height': 180,
    },
    {'kind': 'edit_card_body', 'card_id': 'card_a', 'body': 'Edited body'},
    {
      'kind': 'set_card_labels',
      'card_id': 'card_a',
      'labels': ['edited'],
    },
    {'kind': 'move_placement', 'item_id': 'item_a', 'x': 80, 'y': 90},
    {
      'kind': 'resize_placement',
      'item_id': 'item_a',
      'width': 320,
      'height': 220,
    },
    {'kind': 'remove_placement', 'item_id': 'item_a'},
  ],
};

class _Harness {
  _Harness({
    required this.root,
    required this.db,
    required this.repository,
    required this.store,
    required this.coordinator,
    required this.tool,
    required this.surfaceOwner,
  });

  final Directory root;
  final AppDatabase db;
  final UnifiedCardRepository repository;
  final _GatedStore store;
  final WhiteboardWorkbenchCoordinator coordinator;
  final WorkbenchRuntimeWhiteboardDomainTool tool;
  final Object surfaceOwner;
  bool _closed = false;

  static Future<_Harness> create() async {
    final root = Directory.systemTemp.createTempSync('p4_runtime_tool_');
    return _open(root, seed: true);
  }

  static Future<_Harness> reopen(Directory root) => _open(root, seed: false);

  static Future<_Harness> _open(
    Directory root, {
    required bool seed,
  }) async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File('${root.path}/runtime.sqlite')),
    );
    final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    final store = _GatedStore(db);
    final surface = WhiteboardWorkbenchSurfaceController.instance;
    final previous = surface.current?.owner;
    if (previous != null) surface.detach(previous);
    final owner = Object();
    final now = DateTime.utc(2026, 8, 28, 10);
    if (seed) {
      await repository.createTextCard(
        cardId: 'card_a',
        title: 'Card A',
        body: 'Body A',
        createdAt: now,
      );
      await store.seed(
        'board_1',
        WhiteboardSnapshot(
          boards: [Board(boardId: 'board_1', name: 'Board', createdAt: now)],
          boardItems: const [
            BoardItem(
              itemId: 'item_a',
              boardId: 'board_1',
              cardId: 'card_a',
              width: 180,
              height: 140,
            ),
          ],
          updatedAt: now,
        ),
      );
    }
    surface.attach(
      owner: owner,
      boardId: 'board_1',
      selectedItemIds: {'item_a'},
      flush: () async => true,
      reload: () async {},
      setInteractionLocked: (_) {},
    );
    final coordinator = WhiteboardWorkbenchCoordinator(
      runtime: _UnusedRuntime(),
      store: store,
      repositoryLoader: () async => repository,
      surfaceController: surface,
      addAction: (characterId, content, projection) =>
          _addAction(db, characterId, content, projection),
      updateAction: (messageId, content, projection) =>
          _updateAction(db, messageId, content, projection),
      readActions: (characterId) =>
          readPersistedWorkbenchActions(db, characterId),
      clock: () => now,
    );
    final tool = WorkbenchRuntimeWhiteboardDomainTool(
      store: store,
      coordinator: coordinator,
      surfaceController: surface,
    );
    return _Harness(
      root: root,
      db: db,
      repository: repository,
      store: store,
      coordinator: coordinator,
      tool: tool,
      surfaceOwner: owner,
    );
  }

  Future<WhiteboardRuntimeTurnAuthorization?> authorize(
    String text, {
    required String messageId,
  }) =>
      tool.prepareAuthorization(
        conversationId: 'persona-i',
        characterId: 'i',
        userText: text,
        userAuthorizationMessageId: messageId,
      );

  Future<List<PersistedWorkbenchAction>> actions() =>
      readPersistedWorkbenchActions(db, 'i');

  void detachSurface() =>
      WhiteboardWorkbenchSurfaceController.instance.detach(surfaceOwner);

  Future<void> closeForRestart() async {
    if (_closed) return;
    detachSurface();
    await db.close();
    _closed = true;
  }

  Future<void> dispose() async {
    await closeForRestart();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

class _GatedStore extends WhiteboardDriftStore {
  _GatedStore(super.db);

  Completer<void> saveEntered = Completer<void>();
  Completer<void>? _release;
  bool failNextSave = false;

  Future<bool> seed(String boardId, WhiteboardSnapshot snapshot) =>
      super.save(boardId, snapshot);

  void gateNextSave() {
    saveEntered = Completer<void>();
    _release = Completer<void>();
  }

  void releaseSave() => _release?.complete();

  @override
  Future<bool> save(String boardId, WhiteboardSnapshot snapshot) async {
    if (failNextSave) {
      failNextSave = false;
      return false;
    }
    final release = _release;
    if (release != null) {
      saveEntered.complete();
      await release.future;
      _release = null;
    }
    return super.save(boardId, snapshot);
  }
}

Future<int> _addAction(
  AppDatabase db,
  String characterId,
  String content,
  Map<String, dynamic> projection,
) =>
    db.into(db.personaChatMessages).insert(
          PersonaChatMessagesCompanion.insert(
            characterId: characterId,
            isFromCharacter: true,
            content: content,
            timestamp: DateTime.utc(2026, 8, 28, 10),
            messageType: const Value('action'),
            attachmentsJson: Value(jsonEncode([
              {'type': 'workbench_action', 'action': projection},
            ])),
          ),
        );

Future<void> _updateAction(
  AppDatabase db,
  int messageId,
  String content,
  Map<String, dynamic> projection,
) async {
  await (db.update(db.personaChatMessages)
        ..where((row) => row.id.equals(messageId)))
      .write(PersonaChatMessagesCompanion(
    content: Value(content),
    attachmentsJson: Value(jsonEncode([
      {'type': 'workbench_action', 'action': projection},
    ])),
  ));
}

class _ToolCallRuntime implements WorkbenchConversationRuntimeGateway {
  _ToolCallRuntime(this.arguments);

  final Map<String, dynamic> arguments;
  final List<Map<String, dynamic>> dynamicTools = [];
  final List<_ToolResponse> responses = [];
  bool _delivered = false;

  @override
  Future<WorkbenchRuntimeSession> startSession({
    required List<Map<String, dynamic>> dynamicTools,
    Map<String, dynamic> contextManifest = const {},
  }) async {
    this.dynamicTools.addAll(dynamicTools);
    return const WorkbenchRuntimeSession(
      sessionId: 'session-1',
      provider: 'fake',
      providerSessionId: 'provider-1',
    );
  }

  @override
  Future<WorkbenchRuntimeSession> resumeSession({
    required String provider,
    required String providerSessionId,
    required List<Map<String, dynamic>> dynamicTools,
  }) =>
      startSession(dynamicTools: dynamicTools);

  @override
  Future<WorkbenchRuntimeTurn> startTurn(
          String sessionId, String input) async =>
      const WorkbenchRuntimeTurn(turnId: 'turn-1');

  @override
  Future<WorkbenchRuntimeEvents> readEvents(
    String sessionId, {
    int afterSequence = 0,
  }) async {
    if (_delivered) {
      return WorkbenchRuntimeEvents(
        status: 'idle',
        events: const [],
        nextSequence: afterSequence,
      );
    }
    _delivered = true;
    return WorkbenchRuntimeEvents(
      status: 'idle',
      events: [
        {
          'sequence': 1,
          'turn_id': 'turn-1',
          'kind': 'tool_call',
          'status': 'running',
          'data': {
            'tool_call_id': 'call-1',
            'tool_name': WorkbenchRuntimeWhiteboardDomainTool.toolName,
            'arguments': arguments,
          },
        },
        {
          'sequence': 2,
          'turn_id': 'turn-1',
          'kind': 'message_delta',
          'status': 'running',
          'data': {'text': '完成'},
        },
        {
          'sequence': 3,
          'turn_id': 'turn-1',
          'kind': 'turn_status',
          'status': 'completed',
          'data': <String, dynamic>{},
        },
      ],
      nextSequence: 3,
    );
  }

  @override
  Future<void> respondToToolCall({
    required String toolCallId,
    required bool success,
    required String text,
  }) async {
    responses.add(_ToolResponse(success, text));
  }

  @override
  Future<void> interruptTurn({
    required String sessionId,
    required String turnId,
  }) async {}

  @override
  Future<void> closeSession(String sessionId) async {}
}

class _ToolResponse {
  const _ToolResponse(this.success, this.text);
  final bool success;
  final String text;
}

class _UnusedRuntime implements WorkbenchRuntimeGateway {
  Never _unused() => throw StateError('unused');

  @override
  Future<void> closeSession(String sessionId) async => _unused();
  @override
  Future<WorkbenchRuntimeEvents> readEvents(
    String sessionId, {
    int afterSequence = 0,
  }) async =>
      _unused();
  @override
  Future<void> respondToToolCall({
    required String toolCallId,
    required bool success,
    required String text,
  }) async =>
      _unused();
  @override
  Future<WorkbenchRuntimeSession> startSession({
    required List<Map<String, dynamic>> dynamicTools,
    Map<String, dynamic> contextManifest = const {},
  }) async =>
      _unused();
  @override
  Future<WorkbenchRuntimeTurn> startTurn(
          String sessionId, String input) async =>
      _unused();
}
