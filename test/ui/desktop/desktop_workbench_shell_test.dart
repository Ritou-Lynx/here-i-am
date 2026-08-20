import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_data_bootstrap.dart';
import 'package:memex/routing/router.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/character/widgets/persona_chat_screen.dart';
import 'package:memex/ui/desktop/desktop_workbench_shell.dart';
import 'package:memex/ui/desktop/view_models/desktop_home_view_model.dart';
import 'package:memex/ui/desktop/widgets/desktop_chat_overlay.dart';
import 'package:memex/ui/desktop/widgets/global_desktop_chat_overlay.dart';
import 'package:memex/ui/whiteboard/card_library_screen.dart';
import 'package:memex/ui/whiteboard/whiteboard_canvas_route_screen.dart';

/// Task S — desktop workbench home: module grid renders real data, module
/// taps land on the frozen routes, and the Lin Ai chat floats / collapses.
void main() {
  late AppDatabase db;
  late WhiteboardDriftStore store;
  late UnifiedCardRepository cardRepository;
  late GoRouter router;
  late Directory repositoryRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = WhiteboardDriftStore(db);
    AppDatabase.setTestInstance(db);
    repositoryRoot = Directory.systemTemp.createTempSync('workbench_repo_');
    cardRepository = UnifiedCardRepository(
      db: db,
      whiteboardRoot: repositoryRoot,
    );
    WhiteboardDataBootstrap.setRepositoryForTesting(cardRepository);
    router = createAppRouter(
      GlobalKey<NavigatorState>(),
      () => const DesktopWorkbenchShell(characterId: 'i'),
    );
  });

  tearDown(() async {
    WhiteboardDataBootstrap.setRepositoryForTesting(null);
    await db.close();
    if (repositoryRoot.existsSync()) {
      repositoryRoot.deleteSync(recursive: true);
    }
  });

  Future<void> pumpUntilVisible(
    WidgetTester tester,
    Finder finder, {
    required String failure,
  }) async {
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (finder.evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    fail(failure);
  }

  Future<void> pumpUntilNoProgress(WidgetTester tester) async {
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    fail('Routed screen did not finish loading');
  }

  Future<void> pumpWorkbench(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    router.go(AppRoutes.home);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await pumpUntilVisible(
      tester,
      find.byKey(const ValueKey('workbench_module_grid')),
      failure: 'Desktop workbench did not become ready',
    );
  }

  Future<void> seedBoardAndTask() async {
    await store.createBoard(name: '白板甲');
    await store.createBoard(name: '白板乙');
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.taskRooms).insert(
          TaskRoomsCompanion.insert(
            id: 'task_room_1',
            title: '整理本周阅读笔记',
            goal: '把本周阅读材料整理进白板',
            taskType: 'whiteboard',
            status: 'running',
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> seedNoteCard({required String id, required String title}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.memoryCards).insert(
          MemoryCardsCompanion.insert(
            id: id,
            memoryScope: const Value('user_truth'),
            type: 'note',
            title: title,
            dropletLabel: '待整理',
            presentationModule: '[]',
            retrievalText: title,
            valence: 0,
            arousal: 0,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await cardRepository.backfillLegacyMemoryCardExtra(id);
  }

  testWidgets('module grid renders all eight spine-contract 3.2 modules', (
    tester,
  ) async {
    await seedBoardAndTask();
    await seedNoteCard(id: 'card_pending_1', title: '待分类视频笔记');

    await pumpWorkbench(tester);

    expect(find.byKey(const ValueKey('workbench_module_grid')), findsOneWidget);
    for (final title in [
      '林埃观察',
      '日程与待办',
      '今日总结',
      '继续工作',
      '继续阅读',
      '待整理卡片',
      '记忆回顾',
      '后台任务',
    ]) {
      expect(find.text(title), findsOneWidget, reason: 'missing module $title');
    }
  });

  testWidgets('继续工作 opens a real board canvas route on board tap', (
    tester,
  ) async {
    await seedBoardAndTask();

    await pumpWorkbench(tester);

    expect(find.text('白板甲'), findsOneWidget);
    await tester.tap(find.text('白板甲'));
    await pumpUntilVisible(
      tester,
      find.byType(WhiteboardCanvasRouteScreen),
      failure: 'Board route did not open',
    );
    await pumpUntilNoProgress(tester);

    expect(find.byType(WhiteboardCanvasRouteScreen), findsOneWidget);
  });

  testWidgets(
      '待整理卡片 shows real unplaced cards and opens the card '
      'library route', (tester) async {
    await seedNoteCard(id: 'card_pending_1', title: '待分类视频笔记');
    await seedNoteCard(id: 'card_placed', title: '已上板卡片');
    // 已上板的卡片不再出现在「待整理」模块。
    final boardId = await store.createBoard(name: '承载板');
    await db.into(db.whiteboardBoardItems).insert(
          WhiteboardBoardItemsCompanion.insert(
            id: 'item_1',
            boardId: boardId,
            cardId: 'card_placed',
          ),
        );

    await pumpWorkbench(tester);

    final pendingModule = find.byKey(const ValueKey('module_pending_cards'));
    await pumpUntilVisible(
      tester,
      find.descendant(
        of: pendingModule,
        matching: find.textContaining('待分类视频笔记'),
      ),
      failure: 'Pending card data did not become ready',
    );
    expect(
      find.descendant(
        of: pendingModule,
        matching: find.textContaining('待分类视频笔记'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: pendingModule,
        matching: find.textContaining('已上板卡片'),
      ),
      findsNothing,
    );

    await tester.tap(
      find.descendant(
        of: pendingModule,
        matching: find.textContaining('待分类视频笔记'),
      ),
    );
    await pumpUntilVisible(
      tester,
      find.byType(CardLibraryScreen),
      failure: 'Card library route did not open',
    );
    await pumpUntilNoProgress(tester);
    expect(find.byType(CardLibraryScreen), findsOneWidget);
  });

  testWidgets('empty home shows honest empty states, not decorative buttons', (
    tester,
  ) async {
    await pumpWorkbench(tester);

    expect(find.textContaining('还没有白板'), findsOneWidget);
    expect(find.textContaining('暂无待整理卡片'), findsOneWidget);
    expect(find.textContaining('暂无可续接的阅读进度'), findsOneWidget);
    expect(find.textContaining('演示数据'), findsNothing);
    expect(find.textContaining('mock'), findsNothing);
  });

  testWidgets('1280x720 and 1440x900 keep all modules in the first viewport', (
    tester,
  ) async {
    const moduleKeys = [
      'module_observation',
      'module_schedule',
      'module_today_summary',
      'module_continue_work',
      'module_pending_cards',
      'module_continue_reading',
      'module_memory_review',
      'module_background_tasks',
    ];
    for (final size in const [Size(1280, 720), Size(1440, 900)]) {
      await pumpWorkbench(tester, size: size);
      for (final key in moduleKeys) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(rect.top, greaterThanOrEqualTo(0), reason: '$key at $size');
        expect(
          rect.bottom,
          lessThanOrEqualTo(size.height),
          reason: '$key at $size',
        );
      }
      expect(tester.takeException(), isNull, reason: 'viewport $size');
    }
  });

  testWidgets('loading and error states recover into the empty home', (
    tester,
  ) async {
    final completer = Completer<DesktopHomeData>();
    final loadingViewModel = DesktopHomeViewModel(
      db: db,
      loader: () => completer.future,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopWorkbenchShell(
          characterId: 'i',
          viewModel: loadingViewModel,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('正在读取工作台…'), findsOneWidget);

    const emptyData = DesktopHomeData(
      boards: [],
      continueWork: [],
      activeTaskCount: 0,
      pendingCards: [],
      scheduleCards: [],
      scheduleOverview: {},
      recentMemoryCards: [],
      todayRecordCount: 0,
      followUpCount: 0,
      taskStatusCounts: {},
    );
    completer.complete(emptyData);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('workbench_module_grid')), findsOneWidget);

    var attempts = 0;
    final retryViewModel = DesktopHomeViewModel(
      db: db,
      loader: () async {
        attempts += 1;
        if (attempts == 1) throw StateError('offline');
        return emptyData;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopWorkbenchShell(
          key: const ValueKey('retry_workbench'),
          characterId: 'i',
          viewModel: retryViewModel,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('workbench_module_grid')), findsOneWidget);
  });

  testWidgets('今日总结的继续对话打开全局林埃面板', (tester) async {
    final controller = GlobalDesktopChatOverlayController.instance;
    controller.reset();
    addTearDown(controller.reset);
    await pumpWorkbench(tester);

    await tester.tap(find.text('继续对话'));

    expect(controller.isOpen, isTrue);
    expect(controller.expectedCharacterId, 'i');
    expect(controller.temporaryContextLabel, '首页');
  });

  testWidgets(
      'floating Lin Ai chat opens as overlay panel and collapses back '
      'to the ball', (tester) async {
    var open = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Stack(
            children: [
              Positioned.fill(
                child: DesktopChatOverlay(
                  open: open,
                  characterId: 'i',
                  initialVoiceMode: false,
                  onOpen: () => setState(() => open = true),
                  onClose: () => setState(() => open = false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('desktop_floating_ball')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop_chat_panel')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('desktop_floating_ball')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('desktop_chat_panel')), findsOneWidget);
    expect(find.byType(PersonaChatScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop_floating_ball')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('desktop_chat_close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('desktop_chat_panel')), findsNothing);
    expect(find.byKey(const ValueKey('desktop_floating_ball')), findsOneWidget);

    // 冲掉 PersonaChatScreen 启动期可能残留的定时器。
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('sidebar collapses to handle and restores content width', (
    tester,
  ) async {
    await pumpWorkbench(tester);

    expect(find.text('卡片库'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('desktop_sidebar_handle')));
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('卡片库'), findsNothing);
    expect(
      find.byKey(const ValueKey('desktop_sidebar_handle')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('desktop_sidebar_handle')));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('卡片库'), findsOneWidget);
  });
}
