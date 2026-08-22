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
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/routing/router.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/character/widgets/persona_chat_screen.dart';
import 'package:memex/ui/core/widgets/app_opening_splash.dart';
import 'package:memex/ui/desktop/desktop_workbench_shell.dart';
import 'package:memex/ui/desktop/view_models/desktop_home_view_model.dart';
import 'package:memex/ui/desktop/widgets/desktop_chat_overlay.dart';
import 'package:memex/ui/desktop/widgets/desktop_home_charts.dart';
import 'package:memex/ui/desktop/widgets/desktop_sidebar.dart';
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
      desktopPlatformOverride: true,
    );
  });

  tearDown(() async {
    router.dispose();
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

  Future<void> seedWebSourceCard() async {
    final now = DateTime.now().toUtc();
    const sourceId = 'source_home_web';
    const versionId = 'version_home_web';
    await cardRepository.importLegacyIngestion(
      source: SourceContent(
        sourceId: sourceId,
        mediaType: SourceMediaType.web,
        title: '真实网页来源',
        origin: SourceOrigin.import,
        currentVersionId: versionId,
        contentHash: 'home_web_hash',
        objectRef: 'objects/home_web.txt',
        createdAt: now,
        updatedAt: now,
      ),
      versions: [
        SourceVersion(
          versionId: versionId,
          sourceId: sourceId,
          contentHash: 'home_web_hash',
          objectRef: 'objects/home_web.txt',
          createdAt: now,
        ),
      ],
      card: CardContract(
        cardId: 'card_home_web',
        cardKind: CardKind.source,
        sourceId: sourceId,
        title: '真实网页来源',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  testWidgets('home renders six compact whiteboard-native modules', (
    tester,
  ) async {
    await seedBoardAndTask();
    await seedNoteCard(id: 'card_pending_1', title: '待分类视频笔记');

    await pumpWorkbench(tester);

    expect(find.byKey(const ValueKey('workbench_module_grid')), findsOneWidget);
    for (final title in ['最近白板', '待整理卡片']) {
      expect(find.text(title), findsOneWidget, reason: 'missing module $title');
    }
    for (final key in const [
      'module_card_activity',
      'module_card_composition',
      'module_card_placement',
      'module_board_growth',
      'module_continue_work',
      'module_pending_cards',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(find.text('工作面'), findsNothing);
    for (final removed in [
      '林埃观察',
      '日程与待办',
      '今日总结',
      '继续阅读',
      '记忆回顾',
      '后台任务',
      '任务中心',
    ]) {
      expect(find.text(removed), findsNothing,
          reason: 'desktop leaked $removed');
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
    expect(find.textContaining('尚无新增卡片'), findsWidgets);
    expect(find.textContaining('还没有卡片'), findsWidgets);
    expect(find.textContaining('演示数据'), findsNothing);
    expect(find.textContaining('mock'), findsNothing);
  });

  testWidgets(
      '1280x720 and 1440x900 keep desktop modules in the first viewport', (
    tester,
  ) async {
    const moduleKeys = [
      'module_card_activity',
      'module_card_composition',
      'module_card_placement',
      'module_board_growth',
      'module_continue_work',
      'module_pending_cards',
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

  testWidgets('charts project real card source placement and board data', (
    tester,
  ) async {
    await seedNoteCard(id: 'card_note_real', title: '真实文字卡');
    await seedNoteCard(id: 'card_annotation_real', title: '真实批注卡');
    await cardRepository.updateCardMetadata(
      'card_annotation_real',
      cardKind: CardKind.annotation,
    );
    await seedWebSourceCard();
    final boardId = await store.createBoard(name: '真实研究板');
    await db.into(db.whiteboardBoardItems).insert(
          WhiteboardBoardItemsCompanion.insert(
            id: 'item_real_annotation',
            boardId: boardId,
            cardId: 'card_annotation_real',
          ),
        );

    await pumpWorkbench(tester);

    expect(find.textContaining('近 30 天新增 3 张'), findsOneWidget);
    expect(find.textContaining('1 张已上板 · 2 张待整理'), findsOneWidget);
    expect(find.byType(DesktopCardActivityChart), findsOneWidget);
    expect(find.byType(DesktopCardCompositionChart), findsOneWidget);
    expect(find.byType(DesktopPlacementChart), findsOneWidget);
    expect(find.byType(DesktopBoardGrowthChart), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktop_board_growth_palm_chart')),
      findsOneWidget,
    );
    expect(find.textContaining('来源媒介'), findsOneWidget);
    expect(find.textContaining('网页 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop sibling routes preserve shell without splash or zoom', (
    tester,
  ) async {
    var mobileRootBuilds = 0;
    final localRouter = createAppRouter(
      GlobalKey<NavigatorState>(),
      () {
        mobileRootBuilds += 1;
        return const AppOpeningSplash(playVideo: false);
      },
      desktopPlatformOverride: true,
    );
    addTearDown(localRouter.dispose);
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp.router(routerConfig: localRouter));
    await pumpUntilVisible(
      tester,
      find.byKey(const ValueKey('workbench_module_grid')),
      failure: 'Desktop home did not load',
    );
    expect(mobileRootBuilds, 0);
    expect(find.byType(AppOpeningSplash), findsNothing);

    await tester.tap(find.byKey(const ValueKey('desktop_sidebar_toggle')));
    await tester.pump();
    expect(find.byKey(const ValueKey('desktop_sidebar')), findsNothing);

    localRouter.go(AppRoutes.cardLibrary);
    await pumpUntilVisible(
      tester,
      find.byType(CardLibraryScreen),
      failure: 'Card library did not load',
    );
    await pumpUntilNoProgress(tester);
    expect(
      find.ancestor(
        of: find.byType(CardLibraryScreen),
        matching: find.byType(ScaleTransition),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('desktop_sidebar')), findsNothing);

    localRouter.go(AppRoutes.home);
    await pumpUntilVisible(
      tester,
      find.byKey(const ValueKey('workbench_module_grid')),
      failure: 'Desktop home did not return',
    );
    expect(find.byType(AppOpeningSplash), findsNothing);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('workbench_module_grid')),
        matching: find.byType(ScaleTransition),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('desktop_sidebar')), findsNothing);
    expect(mobileRootBuilds, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mobile router keeps the original root outside desktop shell', (
    tester,
  ) async {
    var rootBuilds = 0;
    final localRouter = createAppRouter(
      GlobalKey<NavigatorState>(),
      () {
        rootBuilds += 1;
        return const SizedBox(key: ValueKey('unchanged_mobile_root'));
      },
      desktopPlatformOverride: false,
    );
    addTearDown(localRouter.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: localRouter));
    await tester.pump();
    expect(find.byKey(const ValueKey('unchanged_mobile_root')), findsOneWidget);
    expect(find.byType(DesktopSidebar), findsNothing);
    expect(rootBuilds, 1);

    localRouter.go(AppRoutes.cardLibrary);
    await tester.pumpAndSettle();
    expect(find.text('卡片库目前仅在桌面端提供'), findsOneWidget);
    localRouter.go(AppRoutes.home);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('unchanged_mobile_root')), findsOneWidget);
    expect(find.byType(DesktopSidebar), findsNothing);
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
      pendingCards: [],
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

  testWidgets(
      'floating Lin Ai chat opens as frameless popover above the persistent '
      'ball', (tester) async {
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
    expect(find.byKey(const ValueKey('desktop_chat_popover')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('desktop_floating_ball')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('desktop_chat_popover')), findsOneWidget);
    expect(find.byType(PersonaChatScreen), findsOneWidget);
    expect(
      tester
          .widget<PersonaChatScreen>(find.byType(PersonaChatScreen))
          .presentation,
      PersonaChatPresentation.desktopFloating,
    );
    expect(find.byKey(const ValueKey('desktop_floating_ball')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('desktop_floating_ball')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('desktop_chat_popover')), findsNothing);
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
