// Goal 1 whiteboard acceptance, replayed by a scripted model.
//
// The P4 human Gate walked one candidate through create, body edit, labels,
// move, selected-card resize, persistent Undo, remove-from-board and restart.
// This scenario replays the same requests through the production paths: the
// desktop chat window, the persisted user row, the production conversation
// composition with its default whiteboard tool, the live canvas route and a
// file-backed SQLite database. Only the model is scripted; it reads the
// host-built whiteboard context exactly as the real provider would.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/device_identity_service.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_data_bootstrap.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/data/workbench_ai/whiteboard_manual_domain_command_host.dart';
import 'package:memex/data/workbench_ai/whiteboard_runtime_domain_tool.dart';
import 'package:memex/data/workbench_ai/whiteboard_workbench_coordinator.dart';
import 'package:memex/data/workbench_ai/whiteboard_workbench_surface.dart';
import 'package:memex/data/workbench_ai/workbench_action_reader.dart';
import 'package:memex/data/workbench_ai/workbench_conversation_coordinator.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/ui/character/widgets/persona_chat_screen.dart';
import 'package:memex/ui/whiteboard/whiteboard_canvas_route_screen.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'scripted_workbench_runtime.dart';

const _characterId = 'i';
const _boardId = 'board_acceptance';
const _title = 'Runtime 创建验收 R14';
const _toolName = WorkbenchRuntimeWhiteboardDomainTool.toolName;

const _createRequest = '请在当前白板创建一张标题为「$_title」、正文为「R14 Runtime 旧正文」的卡片。';

void main() {
  testWidgets('Goal 1 whiteboard acceptance replays through production paths',
      (tester) async {
    _stubAudioPlugins();
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final root = Directory.systemTemp.createTempSync('wb_ai_acceptance_');
    final databaseFile = File('${root.path}/acceptance.sqlite');
    final db = AppDatabase.forTesting(NativeDatabase(databaseFile));
    SharedPreferences.setMockInitialValues({'user_id': 'acceptance-user'});
    DeviceIdentityService.resetForTesting();
    AppDatabase.setTestInstance(db);
    final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    WhiteboardDataBootstrap.setRepositoryForTesting(repository);
    var dbClosed = false;
    addTearDown(() async {
      final owner =
          WhiteboardWorkbenchSurfaceController.instance.current?.owner;
      if (owner != null) {
        WhiteboardWorkbenchSurfaceController.instance.detach(owner);
      }
      WhiteboardDataBootstrap.setRepositoryForTesting(null);
      if (!dbClosed) await db.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    final store = WhiteboardDriftStore(db);
    final now = DateTime.utc(2026, 10, 2, 9);
    await tester.runAsync(() => store.save(
          _boardId,
          WhiteboardSnapshot(
            boards: [Board(boardId: _boardId, name: '验收', createdAt: now)],
            updatedAt: now,
          ),
        ));

    final runtime = ScriptedWorkbenchRuntime([
      _turn(
          ['create_card'],
          (context) => {
                'kind': 'create_card',
                'title': _title,
                'body': 'R14 Runtime 旧正文',
                'x': 0,
                'y': 0,
                'width': 320,
                'height': 220,
              }),
      _turn(
          ['edit_card_body'],
          (context) => {
                'kind': 'edit_card_body',
                'card_id': _single(context['target_card_ids']),
                'body': 'R15 Runtime 正文编辑通过',
              }),
      _turn(
          ['set_card_labels'],
          (context) => {
                'kind': 'set_card_labels',
                'card_id': _single(context['target_card_ids']),
                'labels': ['runtime验收'],
              }),
      _turn(['move_placement'], (context) {
        final geometry = _geometry(context);
        return {
          'kind': 'move_placement',
          'item_id': geometry['item_id'],
          'x': (geometry['x'] as num) + 120,
          'y': geometry['y'],
        };
      }),
      _turn(['resize_placement'], (context) {
        expect(context['target_scope_source'], 'selection');
        final geometry = _geometry(context);
        return {
          'kind': 'resize_placement',
          'item_id': geometry['item_id'],
          'width': (geometry['width'] as num) + 120,
          'height': geometry['height'],
        };
      }),
      _turn(
          ['remove_placement'],
          (context) => {
                'kind': 'remove_placement',
                'item_id': _single(context['target_item_ids']),
              }),
    ]);
    final conversation = WorkbenchConversationCoordinator.productionComposition(
      runtime: runtime,
      addReply: (characterId, content) => PersonaChatService.instance
          .addCharacterMessage(characterId, content, isRead: true),
      pollInterval: Duration.zero,
      turnTimeout: const Duration(seconds: 10),
    );
    Future<WorkbenchConversationResult> connector({
      required WorkbenchConversationCoordinator coordinator,
      required String conversationId,
      required String characterId,
      required String userText,
      required int userMessageId,
      WorkbenchReplyDelta? onDelta,
    }) =>
        conversation.send(
          conversationId: conversationId,
          characterId: characterId,
          userText: userText,
          userMessageId: userMessageId,
          onDelta: onDelta,
        );

    final character = CharacterModel(
      id: _characterId,
      name: '林埃',
      tags: const [],
      persona: 'acceptance persona',
      enabled: true,
    );
    await tester.pumpWidget(MaterialApp(
      home: Stack(
        children: [
          Positioned.fill(
            child: WhiteboardCanvasRouteScreen(
              boardId: _boardId,
              store: store,
              cardRepository: repository,
              manualCommandHost: WhiteboardManualDomainCommandHost.production(),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            width: 420,
            height: 560,
            child: PersonaChatScreen(
              characterId: _characterId,
              presentation: PersonaChatPresentation.desktopFloating,
              desktopConversationConnector: connector,
              initialCharacterForTesting: character,
            ),
          ),
        ],
      ),
    ));
    await _pumpUntil(
        tester, () => find.byType(WhiteboardCanvasArea).evaluate().isNotEmpty);
    await _pumpUntil(
      tester,
      () =>
          WhiteboardWorkbenchSurfaceController.instance.current?.boardId ==
          _boardId,
    );
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('desktop_chat_input'))
          .evaluate()
          .isNotEmpty,
    );
    final area =
        tester.widget<WhiteboardCanvasArea>(find.byType(WhiteboardCanvasArea));

    // 1. Create through chat.
    await _say(tester, _createRequest);
    await _pumpUntil(
      tester,
      () => area.viewModel.exportForSave().boardItems.length == 1,
    );
    var actions = await _actions(tester, db, 1);
    _expectApplied(runtime, actions, 'create_card');
    final created = area.viewModel.exportForSave().boardItems.single;
    final itemId = created.itemId;
    final cardId = created.cardId;
    expect(find.byKey(Key('wb_card_$itemId')), findsOneWidget);
    await _pumpUntil(tester, () => _replyShown('已完成'));

    // 2. Edit the body of the card named in the request.
    await _say(tester, _bodyRequest);
    actions = await _actions(tester, db, 2);
    _expectApplied(runtime, actions, 'edit_card_body');
    var card = await _card(tester, repository, cardId);
    expect(card.title, _title);
    expect(card.body, 'R15 Runtime 正文编辑通过');

    // 3. Set its labels.
    await _say(tester, _labelsRequest);
    actions = await _actions(tester, db, 3);
    _expectApplied(runtime, actions, 'set_card_labels');
    card = await _card(tester, repository, cardId);
    expect(card.tags, ['runtime验收']);
    expect(card.body, 'R15 Runtime 正文编辑通过');

    // 4. Move it 120 px right of where the host says it is.
    await _say(tester, _moveRequest);
    actions = await _actions(tester, db, 4);
    _expectApplied(runtime, actions, 'move_placement');
    await _pumpUntil(tester, () => _item(area, itemId).x == created.x + 120);
    expect(_item(area, itemId).y, created.y);
    expect(_item(area, itemId).width, created.width);

    // 5. Select it on the canvas, then ask in chat to widen "the selected card".
    await tester.tap(find.byKey(Key('wb_card_$itemId')));
    await tester.pump();
    expect(area.viewModel.selection.selectedItemIds, {itemId});
    await _say(tester, _resizeRequest);
    actions = await _actions(tester, db, 5);
    _expectApplied(runtime, actions, 'resize_placement');
    await _pumpUntil(
      tester,
      () => _item(area, itemId).width == created.width + 120,
    );
    expect(_item(area, itemId).height, created.height);
    expect(_item(area, itemId).x, created.x + 120);

    // 6. Undo is ordered: the move cannot be undone while the later resize
    // stands, keeps its token, and succeeds once the resize is undone.
    final moveAction = _action(actions, 'move_placement');
    final resizeAction = _action(actions, 'resize_placement');
    await _undo(tester, moveAction.projection.actionId);
    await _pumpUntil(
      tester,
      () => true,
      refresh: () async => actions = (await _actions(tester, db, 5)),
    );
    expect(
        _action(actions, 'move_placement').projection.status.name, 'completed');
    expect(_item(area, itemId).x, created.x + 120);
    expect(
      find.byKey(
          ValueKey('workbench_action_undo_${moveAction.projection.actionId}')),
      findsOneWidget,
    );

    await _undo(tester, resizeAction.projection.actionId);
    await _pumpUntil(tester, () => _item(area, itemId).width == created.width);
    await _undo(tester, moveAction.projection.actionId);
    await _pumpUntil(tester, () => _item(area, itemId).x == created.x);
    actions = await _actions(tester, db, 5);
    expect(
        _action(actions, 'resize_placement').projection.status.name, 'undone');
    expect(_action(actions, 'move_placement').projection.status.name, 'undone');
    for (final action in [resizeAction, moveAction]) {
      final id = action.projection.actionId;
      final card = find.byKey(ValueKey('workbench_action_$id'));
      await _scrollChatTo(tester, card);
      await _pumpUntil(
        tester,
        () => find
            .descendant(of: card, matching: find.text('已撤销'))
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.descendant(of: card, matching: find.text('已撤销')),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('workbench_action_undo_$id')), findsNothing);
    }

    // 7. Remove it from the board; the card itself must survive.
    await _say(tester, _removeRequest);
    actions = await _actions(tester, db, 6);
    _expectApplied(runtime, actions, 'remove_placement');
    await _pumpUntil(
      tester,
      () => area.viewModel.exportForSave().boardItems.isEmpty,
    );
    card = await _card(tester, repository, cardId);
    expect(card.body, 'R15 Runtime 正文编辑通过');
    expect(card.tags, ['runtime验收']);
    expect(runtime.remainingTurns, 0);
    final removeActionId =
        _action(actions, 'remove_placement').projection.actionId;

    // 8. Restart: close everything, reopen the same database file with fresh
    // stores and coordinators, and undo the removal from the persisted token.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    final owner = WhiteboardWorkbenchSurfaceController.instance.current?.owner;
    if (owner != null) {
      WhiteboardWorkbenchSurfaceController.instance.detach(owner);
    }
    await tester.runAsync(db.close);
    dbClosed = true;

    final reopened = AppDatabase.forTesting(NativeDatabase(databaseFile));
    addTearDown(reopened.close);
    AppDatabase.setTestInstance(reopened);
    final reopenedRepository =
        UnifiedCardRepository(db: reopened, whiteboardRoot: root);
    WhiteboardDataBootstrap.setRepositoryForTesting(reopenedRepository);
    final reopenedStore = WhiteboardDriftStore(reopened);
    final persisted =
        (await tester.runAsync(() => reopenedStore.load(_boardId)))!.snapshot!;
    expect(persisted.boardItems, isEmpty);
    card = await _card(tester, reopenedRepository, cardId);
    expect(card.title, _title);
    expect(card.body, 'R15 Runtime 正文编辑通过');
    expect(card.tags, ['runtime验收']);
    actions = (await tester.runAsync(
      () => readPersistedWorkbenchActions(reopened, _characterId),
    ))!;
    expect(
      {
        for (final action in actions)
          _kind(action): action.projection.status.name,
      },
      {
        'create_card': 'completed',
        'edit_card_body': 'completed',
        'set_card_labels': 'completed',
        'move_placement': 'undone',
        'resize_placement': 'undone',
        'remove_placement': 'completed',
      },
    );

    final restarted = WhiteboardWorkbenchCoordinator(
      runtime: WorkbenchRuntimeClient(),
      store: reopenedStore,
      repositoryLoader: () async => reopenedRepository,
      surfaceController: WhiteboardWorkbenchSurfaceController.instance,
      addAction: (characterId, content, projection) => PersonaChatService
          .instance
          .addWorkbenchActionMessage(characterId, content, projection),
      updateAction: (messageId, content, projection) =>
          PersonaChatService.instance.updateWorkbenchActionMessage(
        messageId: messageId,
        content: content,
        projection: projection,
      ),
      readActions: (characterId) =>
          readPersistedWorkbenchActions(reopened, characterId),
    );
    await tester.pumpWidget(MaterialApp(
      home: WhiteboardCanvasRouteScreen(
        boardId: _boardId,
        store: reopenedStore,
        cardRepository: reopenedRepository,
      ),
    ));
    await _pumpUntil(
      tester,
      () =>
          WhiteboardWorkbenchSurfaceController.instance.current?.boardId ==
          _boardId,
    );
    await tester.runAsync(() => restarted.hydrateUndo(_characterId));
    expect(restarted.canUndo(removeActionId), isTrue);
    await tester.runAsync(() => restarted.undo(removeActionId));
    List<BoardItem> visibleItems() {
      final areas = find.byType(WhiteboardCanvasArea).evaluate();
      if (areas.isEmpty) return const [];
      return (areas.single.widget as WhiteboardCanvasArea)
          .viewModel
          .exportForSave()
          .boardItems;
    }

    await _pumpUntil(tester, () => visibleItems().length == 1);
    final restored = visibleItems().single;
    expect(restored.cardId, cardId);
    expect(restored.x, created.x);
    expect(restored.width, created.width);
    final persistedAfterUndo =
        (await tester.runAsync(() => reopenedStore.load(_boardId)))!.snapshot!;
    expect(persistedAfterUndo.boardItems.single.cardId, cardId);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}

const _bodyRequest = '把当前白板上标题为「$_title」的卡片正文改成「R15 Runtime 正文编辑通过」。'
    '不要改标题、标签、位置或大小。';
const _labelsRequest = '把当前白板上标题为「$_title」的卡片标签设为「runtime验收」。';
const _moveRequest = '把当前白板上标题为「$_title」的卡片移动到当前位置右侧 120 像素。'
    '标题、正文、标签和大小保持不变。';
const _resizeRequest = '当前选中卡片宽度增加 120 像素';
const _removeRequest = '把当前白板上标题为「$_title」的卡片从白板移除。';

/// One scripted model turn that checks the host granted exactly [capabilities]
/// and then issues a single whiteboard command built from the host context.
ScriptedTurn _turn(
  List<String> capabilities,
  Map<String, dynamic> Function(Map<String, dynamic> context) command,
) =>
    (input) {
      final context = input.whiteboardContext;
      expect(context, isNotNull, reason: 'host attached no whiteboard context');
      expect(context!['capabilities'], capabilities);
      return ScriptedTurnPlan(
        toolCalls: [
          ScriptedToolCall(_toolName, {
            'commands': [command(context)],
          }),
        ],
        reply: (responses) {
          final status = responses.single.json?['status'];
          return status == 'applied' ? '已完成。' : '没有改动：$status';
        },
      );
    };

String _single(Object? ids) => (ids as List).single as String;

Map<String, dynamic> _geometry(Map<String, dynamic> context) {
  expect(
    context['target_placement_geometry_source'],
    'host_authoritative_snapshot_for_absolute_move_or_resize',
  );
  return Map<String, dynamic>.from(
    (context['target_placement_geometry'] as List).single as Map,
  );
}

String _kind(PersistedWorkbenchAction action) =>
    ((action.projection.domainCommandBatch?['commands'] as List).single
        as Map)['kind'] as String;

PersistedWorkbenchAction _action(
  List<PersistedWorkbenchAction> actions,
  String kind,
) =>
    actions.singleWhere((action) => _kind(action) == kind);

void _expectApplied(
  ScriptedWorkbenchRuntime runtime,
  List<PersistedWorkbenchAction> actions,
  String kind,
) {
  final response = runtime.responses.last;
  expect(response.success, isTrue, reason: response.text);
  expect(response.json?['status'], 'applied', reason: response.text);
  final action = _action(actions, kind);
  expect(action.projection.status.name, 'completed');
  expect(action.projection.domainCommandReceipt?['status'], 'applied');
}

BoardItem _item(WhiteboardCanvasArea area, String itemId) => area.viewModel
    .exportForSave()
    .boardItems
    .singleWhere((item) => item.itemId == itemId);

bool _replyShown(String text) =>
    find.textContaining(text, findRichText: true).evaluate().isNotEmpty;

Future<CardContract> _card(
  WidgetTester tester,
  UnifiedCardRepository repository,
  String cardId,
) async =>
    (await tester.runAsync(
      () => repository.getCard(cardId, loadDocument: false),
    ))!
        .card;

Future<void> _undo(WidgetTester tester, String actionId) async {
  // The newest-first list builds lazily; an older action need not be mounted.
  await _scrollChatTo(
      tester, find.byKey(ValueKey('workbench_action_$actionId')));
  final button = find.byKey(ValueKey('workbench_action_undo_$actionId'));
  final hitTarget = button.hitTestable();
  // ensureVisible changes the scroll offset without laying out the next frame.
  // Use the existing wait budget for a real pointer target, not just a built row.
  await _pumpUntil(tester, () => hitTarget.evaluate().isNotEmpty,
      refresh: () async {
    if (button.evaluate().isEmpty) return;
    await tester.ensureVisible(button);
    await tester.pump();
  });
  expect(hitTarget, findsOneWidget,
      reason: 'Undo $actionId must receive the tap after scroll layout');
  await tester.tap(hitTarget);
  await tester.pump();
  for (var index = 0; index < 10; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// The chat screen touches the recorder and sound-effect players; widget
/// tests have no platform side for them.
void _stubAudioPlugins() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in const [
    'com.llfbandit.record/messages',
    'xyz.luan/audioplayers.global',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
  }
  // Each player listens on its own event channel, named by its id.
  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers'),
    (call) async {
      final playerId = (call.arguments as Map?)?['playerId'];
      if (call.method == 'create' && playerId is String) {
        messenger.setMockStreamHandler(
          EventChannel('xyz.luan/audioplayers/events/$playerId'),
          MockStreamHandler.inline(onListen: (_, __) {}),
        );
      }
      return null;
    },
  );
  messenger.setMockStreamHandler(
    const EventChannel('xyz.luan/audioplayers.global/events'),
    MockStreamHandler.inline(onListen: (_, __) {}),
  );
}

/// Scrolls the newest-first chat list from its newest end until [target] is
/// built and visible.
Future<void> _scrollChatTo(WidgetTester tester, Finder target) async {
  final chatList = find
      .descendant(
        of: find.byType(PersonaChatScreen),
        matching: find.byType(Scrollable),
      )
      .first;
  tester.state<ScrollableState>(chatList).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(target, 120, scrollable: chatList);
  await tester.pump();
}

Future<void> _say(WidgetTester tester, String text) async {
  final input = find.byKey(const ValueKey('desktop_chat_input'));
  await tester.enterText(input, text);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('desktop_chat_send')));
  await tester.pump();
}

Future<List<PersistedWorkbenchAction>> _actions(
  WidgetTester tester,
  AppDatabase db,
  int count,
) async {
  var actions = <PersistedWorkbenchAction>[];
  await _pumpUntil(tester, () => actions.length >= count, refresh: () async {
    actions = (await tester.runAsync(
      () => readPersistedWorkbenchActions(db, _characterId),
    ))!;
  });
  expect(actions, hasLength(count));
  return actions;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Future<void> Function()? refresh,
}) async {
  for (var index = 0; index < 200; index++) {
    await refresh?.call();
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await refresh?.call();
  expect(condition(), isTrue);
}
