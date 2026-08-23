import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/data/workbench_ai/whiteboard_workbench_coordinator.dart';
import 'package:memex/data/workbench_ai/whiteboard_workbench_surface.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/domain/workbench_ai/action/workbench_action_projection.dart';

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late UnifiedCardRepository repository;
  late WhiteboardDriftStore store;
  late WhiteboardWorkbenchSurfaceController surfaceController;
  late Object surfaceOwner;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('workbench_coordinator_');
    db = AppDatabase.forTesting(
      NativeDatabase(File('${tempDir.path}/whiteboard.sqlite')),
    );
    repository = UnifiedCardRepository(db: db, whiteboardRoot: tempDir);
    store = WhiteboardDriftStore(db);
    surfaceController = WhiteboardWorkbenchSurfaceController.instance;
    final previousOwner = surfaceController.current?.owner;
    if (previousOwner != null) surfaceController.detach(previousOwner);
    surfaceOwner = Object();

    final now = DateTime.utc(2026, 8, 21, 10);
    for (var index = 1; index <= 3; index++) {
      await repository.createTextCard(
        cardId: 'card_$index',
        title: 'Card $index',
        body: 'Body $index',
        createdAt: now,
      );
    }
    expect(
      await store.save(
        'board_1',
        WhiteboardSnapshot(
          boards: [Board(boardId: 'board_1', name: 'Board', createdAt: now)],
          boardItems: [
            for (var index = 1; index <= 3; index++)
              BoardItem(
                itemId: 'item_$index',
                boardId: 'board_1',
                cardId: 'card_$index',
              ),
          ],
          updatedAt: now,
        ),
      ),
      isTrue,
    );
  });

  tearDown(() async {
    surfaceController.detach(surfaceOwner);
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('executes read then product-owned write and supports whole-batch undo',
      () async {
    var reloads = 0;
    surfaceController.attach(
      owner: surfaceOwner,
      boardId: 'board_1',
      selectedItemIds: {'item_1', 'item_2', 'item_3'},
      flush: () async => true,
      reload: () async {
        reloads += 1;
      },
    );
    final runtime = _FakeRuntime();
    final projections = <WorkbenchActionProjection>[];
    final coordinator = WhiteboardWorkbenchCoordinator(
      runtime: runtime,
      store: store,
      repositoryLoader: () async => repository,
      surfaceController: surfaceController,
      addAction: (_, __, projection) async {
        projections.add(WorkbenchActionProjection.fromJson(projection));
        return 41;
      },
      updateAction: (_, __, projection) async {
        projections.add(WorkbenchActionProjection.fromJson(projection));
      },
      clock: () => DateTime.utc(2026, 8, 21, 10),
    );

    expect(
      await coordinator.run(
        characterId: 'i',
        userText: '把这些卡片分组并连线',
        userMessageId: 7,
      ),
      isTrue,
    );

    final completed = projections.last;
    expect(
      completed.status,
      WorkbenchActionStatus.completed,
      reason:
          '${completed.errorCode}: ${completed.summary}; success=${runtime.responseSuccess}; responses=${runtime.responses}',
    );
    expect(completed.groupCount, 1);
    expect(completed.edgeCount, 1);
    expect(completed.userAuthorizationMessageId, 'chat-message-7');
    expect(runtime.calledTools, [
      WhiteboardWorkbenchCoordinator.readToolName,
      WhiteboardWorkbenchCoordinator.writeToolName,
    ]);
    expect(runtime.responses, hasLength(2));
    expect(runtime.responseSuccess, [true, true]);
    expect(runtime.closed, isTrue);
    final applied = (await store.load('board_1')).snapshot!;
    expect(applied.groups, hasLength(1));
    expect(applied.edges, hasLength(1));
    expect(reloads, 1);

    var reopenedFlushes = 0;
    var reopenedReloads = 0;
    surfaceController.detach(surfaceOwner);
    surfaceOwner = Object();
    surfaceController.attach(
      owner: surfaceOwner,
      boardId: 'board_1',
      selectedItemIds: {'item_1', 'item_2', 'item_3'},
      flush: () async {
        reopenedFlushes += 1;
        return true;
      },
      reload: () async {
        reopenedReloads += 1;
      },
    );

    expect(coordinator.canUndo(completed.actionId), isTrue);
    await coordinator.undo(completed.actionId);
    expect(
      projections.last.status,
      WorkbenchActionStatus.undone,
      reason: '${projections.last.errorCode}: ${projections.last.summary}',
    );
    final restored = (await store.load('board_1')).snapshot!;
    expect(restored.groups, isEmpty);
    expect(restored.edges, isEmpty);
    expect(reloads, 1, reason: 'the disposed page must not be reloaded');
    expect(reopenedFlushes, 2,
        reason: 'flushes once before undo and once after current-page reload');
    expect(reopenedReloads, 1);
  });

  test('does not intercept an ordinary discussion of grouping and links',
      () async {
    final coordinator = WhiteboardWorkbenchCoordinator(
      runtime: _FakeRuntime(),
      store: store,
      repositoryLoader: () async => repository,
      surfaceController: surfaceController,
      addAction: (_, __, ___) async => 1,
      updateAction: (_, __, ___) async {},
    );

    expect(coordinator.matches('我们讨论一下分组和连线的设计'), isFalse);
    expect(coordinator.matches('按主题分组并连线'), isTrue);
    expect(coordinator.matches('请把所选卡片分组并连线'), isTrue);
  });
}

class _FakeRuntime implements WorkbenchRuntimeGateway {
  final responses = <String>[];
  final responseSuccess = <bool>[];
  final calledTools = <String>[];
  bool closed = false;

  @override
  Future<WorkbenchRuntimeSession> startSession({
    required List<Map<String, dynamic>> dynamicTools,
    Map<String, dynamic> contextManifest = const {},
  }) async {
    expect(contextManifest['board_id'], 'board_1');
    final writeTool = dynamicTools.singleWhere(
      (tool) => tool['name'] == WhiteboardWorkbenchCoordinator.writeToolName,
    );
    expect(writeTool['description'], contains('每个所选 item_id 恰好出现一次'));
    return const WorkbenchRuntimeSession(
      sessionId: 'session_1',
      provider: 'fake-runtime',
      providerSessionId: 'provider_1',
    );
  }

  @override
  Future<WorkbenchRuntimeTurn> startTurn(String sessionId, String input) async {
    expect(input, contains('不要猜测'));
    expect(input, contains('每个所选 item_id 必须且只能出现一次'));
    expect(input, contains('就把全部所选 item 放进一个较宽泛的组'));
    return const WorkbenchRuntimeTurn(turnId: 'turn_1');
  }

  @override
  Future<WorkbenchRuntimeEvents> readEvents(
    String sessionId, {
    int afterSequence = 0,
  }) async {
    if (afterSequence == 0) {
      calledTools.add(WhiteboardWorkbenchCoordinator.readToolName);
      return WorkbenchRuntimeEvents(
        status: 'running',
        nextSequence: 1,
        events: [
          _event(
            sequence: 1,
            kind: 'tool_call',
            data: {
              'tool_call_id': 'call_read',
              'tool_name': WhiteboardWorkbenchCoordinator.readToolName,
              'arguments': <String, dynamic>{},
            },
          ),
        ],
      );
    }
    if (afterSequence == 1) {
      calledTools.add(WhiteboardWorkbenchCoordinator.writeToolName);
      return WorkbenchRuntimeEvents(
        status: 'running',
        nextSequence: 2,
        events: [
          _event(
            sequence: 2,
            kind: 'tool_call',
            data: {
              'tool_call_id': 'call_write',
              'tool_name': WhiteboardWorkbenchCoordinator.writeToolName,
              'arguments': {
                'groups': [
                  {
                    'name': 'Research',
                    'item_ids': ['item_1', 'item_2', 'item_3'],
                  },
                ],
                'edges': [
                  {
                    'from_item_id': 'item_2',
                    'to_item_id': 'item_3',
                    'direction': 'directed',
                    'label': 'next',
                  },
                ],
              },
            },
          ),
        ],
      );
    }
    return WorkbenchRuntimeEvents(
      status: 'idle',
      nextSequence: 3,
      events: [
        _event(
          sequence: 3,
          kind: 'turn_status',
          status: 'completed',
        ),
      ],
    );
  }

  @override
  Future<void> respondToToolCall({
    required String toolCallId,
    required bool success,
    required String text,
  }) async {
    responseSuccess.add(success);
    responses.add(text);
  }

  @override
  Future<void> closeSession(String sessionId) async => closed = true;
}

Map<String, dynamic> _event({
  required int sequence,
  required String kind,
  String status = 'running',
  Map<String, dynamic> data = const {},
}) {
  return {
    'schema_version': 1,
    'event_id': 'session_1:$sequence',
    'sequence': sequence,
    'occurred_at': '2026-08-21T10:00:00.000Z',
    'session_id': 'session_1',
    'turn_id': 'turn_1',
    'kind': kind,
    'status': status,
    'data': data,
  };
}
