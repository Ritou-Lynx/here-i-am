import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_data_bootstrap.dart';
import 'dart:io';

import 'package:memex/domain/whiteboard/rich_text_storage.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/routing/desktop_route_wrapper.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/routing/router.dart';
import 'package:memex/ui/desktop/widgets/desktop_sidebar.dart';
import 'package:memex/ui/whiteboard/card_library_screen.dart';
import 'package:memex/ui/whiteboard/card_rich_text_editor_screen.dart';
import 'package:memex/ui/whiteboard/link_import_screen.dart';
import 'package:memex/ui/whiteboard/source_study_screen.dart';
import 'package:memex/ui/whiteboard/whiteboard_canvas_route_screen.dart';
import 'package:memex/ui/whiteboard/whiteboard_index_screen.dart';

/// W6 — whiteboard route registration & frozen parameter signature tests.
///
/// These lock the route table once: parallel windows must only fill screen
/// bodies, never edit router.dart.
void main() {
  late AppDatabase db;
  late WhiteboardDriftStore store;
  late GoRouter router;
  late Directory repositoryRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = WhiteboardDriftStore(db);
    // The canvas route screen defaults to AppDatabase.instance in production;
    // point it at the in-memory test database so the real route wiring is
    // exercised end to end.
    AppDatabase.setTestInstance(db);
    repositoryRoot = Directory.systemTemp.createTempSync('route_repository_');
    WhiteboardDataBootstrap.setRepositoryForTesting(
      UnifiedCardRepository(db: db, whiteboardRoot: repositoryRoot),
    );
    // The card editor resolves its storage via path_provider, whose platform
    // channel is unavailable under `flutter test`; point it at a temp dir.
    CardRichTextEditorScreen.setStorageForTesting(
      RichTextStorage(Directory.systemTemp.createTempSync('route_rt_')),
    );
    router = createAppRouter(
      GlobalKey<NavigatorState>(),
      () => const Scaffold(body: SizedBox()),
    );
  });

  tearDown(() async {
    WhiteboardDataBootstrap.setRepositoryForTesting(null);
    await db.close();
    if (repositoryRoot.existsSync()) {
      repositoryRoot.deleteSync(recursive: true);
    }
  });

  Future<void> pumpRoute(
    WidgetTester tester,
    String path, {
    required Finder until,
    Finder? andAbsent,
  }) async {
    router.go(path);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    // Drift-backed screens complete work on the real event loop. Keep the
    // widget clock moving while yielding briefly until the route's content is
    // visible; do not use pumpAndSettle around indeterminate progress widgets.
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (until.evaluate().isNotEmpty &&
          (andAbsent == null || andAbsent.evaluate().isEmpty)) {
        return;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    fail('Route $path did not become ready');
  }

  testWidgets('whiteboard index route resolves', (tester) async {
    await pumpRoute(
      tester,
      AppRoutes.whiteboard,
      until: find.byType(WhiteboardIndexScreen),
    );
    expect(find.byType(WhiteboardIndexScreen), findsOneWidget);
    expect(
        find.byKey(const ValueKey('desktop_standard_shell')), findsOneWidget);
    expect(find.byType(DesktopSidebar), findsOneWidget);
  });

  testWidgets(
      'canvas route resolves with boardId and renders full-screen '
      'canvas for an existing board (direct route entry)', (tester) async {
    final boardId = await store.createBoard(name: '路由测试板');
    await pumpRoute(
      tester,
      AppRoutes.whiteboardCanvasPath(boardId),
      until: find.byKey(const ValueKey('wb_canvas_chrome_launcher')),
      andAbsent: find.byType(CircularProgressIndicator),
    );

    expect(find.byType(WhiteboardCanvasRouteScreen), findsOneWidget);
    // Loaded from Drift: the full-screen canvas appears (no persistent AppBar).
    expect(find.byType(AppBar), findsNothing);
    expect(
        find.byKey(const ValueKey('desktop_immersive_shell')), findsOneWidget);
    expect(find.byType(DesktopSidebar), findsNothing);
    expect(find.byKey(const ValueKey('desktop_sidebar_handle')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('wb_canvas_chrome_launcher')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('wb_navigation_group')), findsNothing);
    expect(find.byKey(const ValueKey('wb_action_tools')), findsNothing);
    expect(find.byKey(const ValueKey('wb_view_tools')), findsNothing);
    expect(find.byKey(const ValueKey('wb_card_library_panel')), findsNothing);
    expect(find.text('路由测试板'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('wb_canvas_chrome_launcher')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('wb_navigation_group')), findsOneWidget);
    expect(find.text('路由测试板'), findsOneWidget);
  });

  testWidgets('canvas route for missing board shows error state',
      (tester) async {
    await pumpRoute(
      tester,
      AppRoutes.whiteboardCanvasPath('board_missing'),
      until: find.text('返回'),
    );
    expect(find.byType(WhiteboardCanvasRouteScreen), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);
  });

  testWidgets('canvas route saves to Drift when the save button is tapped',
      (tester) async {
    final boardId = await store.createBoard(name: '保存测试板');
    await pumpRoute(
      tester,
      AppRoutes.whiteboardCanvasPath(boardId),
      until: find.byKey(const ValueKey('wb_canvas_chrome_launcher')),
      andAbsent: find.byType(CircularProgressIndicator),
    );
    expect(find.byType(WhiteboardCanvasRouteScreen), findsOneWidget);
    expect(find.text('保存测试板'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('wb_canvas_chrome_launcher')),
    );
    await tester.pumpAndSettle();
    expect(find.text('保存测试板'), findsOneWidget);
    await tester.tap(find.byTooltip('画布工具'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wb_action_tools')), findsOneWidget);
    expect(find.byKey(const ValueKey('wb_view_tools')), findsOneWidget);

    await tester.tap(find.byTooltip('保存快照 (Ctrl+S)'));
    await tester.pump(const Duration(milliseconds: 500));

    final saved = await store.load(boardId);
    expect(saved.isSuccess, isTrue);
    expect(saved.snapshot!.boards.single.name, '保存测试板');
  });

  testWidgets('card library route resolves', (tester) async {
    await pumpRoute(
      tester,
      AppRoutes.cardLibrary,
      until: find.text('卡片库还是空的'),
    );
    expect(find.byType(CardLibraryScreen), findsOneWidget);
    expect(
        find.byKey(const ValueKey('desktop_standard_shell')), findsOneWidget);
    expect(find.byType(DesktopSidebar), findsOneWidget);
  });

  testWidgets('card edit route resolves with cardId parameter', (tester) async {
    await pumpRoute(
      tester,
      AppRoutes.cardEditPath('card_abc'),
      until: find.textContaining('card_abc'),
    );
    expect(find.byType(CardRichTextEditorScreen), findsOneWidget);
    // The real editor screen opens (W2 body) with the card id in its title.
    expect(find.textContaining('card_abc'), findsOneWidget);
  });

  testWidgets('direct card edit back falls back to the card library',
      (tester) async {
    await pumpRoute(
      tester,
      AppRoutes.cardEditPath('card_direct'),
      until: find.byType(CardRichTextEditorScreen),
    );

    await tester.tap(find.byTooltip('返回'));
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(CardLibraryScreen).evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }

    expect(find.byType(CardLibraryScreen), findsOneWidget);
  });

  testWidgets('pushed card edit back restores card library state',
      (tester) async {
    await pumpRoute(
      tester,
      AppRoutes.cardLibrary,
      until: find.byType(CardLibraryScreen),
    );
    await tester.enterText(
      find.byKey(const ValueKey('card-library-search')),
      '保留筛选',
    );
    await tester.pump();

    final pending = router.push(AppRoutes.cardEditPath('card_pushed'));
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(CardRichTextEditorScreen).evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.tap(find.byTooltip('返回'));
    await pending;
    await tester.pump();

    expect(find.byType(CardLibraryScreen), findsOneWidget);
    final search = tester.widget<TextField>(
      find.byKey(const ValueKey('card-library-search')),
    );
    expect(search.controller!.text, '保留筛选');
  });

  testWidgets('direct dirty card edit confirms before library fallback',
      (tester) async {
    await pumpRoute(
      tester,
      AppRoutes.cardEditPath('card_dirty_direct'),
      until: find.byType(CardRichTextEditorScreen),
    );
    await tester.enterText(find.byType(TextField).first, '尚未保存的内容');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('desktop_page_back')));
    await tester.pumpAndSettle();
    expect(find.text('尚未保存'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(CardRichTextEditorScreen), findsOneWidget);
    expect(find.text('尚未保存的内容'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('desktop_page_back')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃'));
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(CardLibraryScreen).evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }

    expect(find.byType(CardLibraryScreen), findsOneWidget);
  });

  testWidgets('source study route resolves with sourceId parameter',
      (tester) async {
    WhiteboardDataBootstrap.setRepositoryForTesting(
      _MissingSourceRepository(db: db, whiteboardRoot: repositoryRoot),
    );
    await pumpRoute(
      tester,
      AppRoutes.sourceStudyPath('src_video_1'),
      until: find.text('找不到这个来源'),
    );
    expect(find.byType(SourceStudyScreen), findsOneWidget);
    expect(
        find.byKey(const ValueKey('desktop_immersive_shell')), findsOneWidget);
    expect(find.byType(DesktopSidebar), findsNothing);
    expect(
      tester.widget<SourceStudyScreen>(find.byType(SourceStudyScreen)).sourceId,
      'src_video_1',
    );
  });

  testWidgets('link import route resolves', (tester) async {
    await pumpRoute(
      tester,
      AppRoutes.linkImport,
      until: find.byType(LinkImportScreen),
    );
    expect(find.byType(LinkImportScreen), findsOneWidget);
    expect(
        find.byKey(const ValueKey('desktop_standard_shell')), findsOneWidget);
    expect(find.byType(DesktopSidebar), findsOneWidget);
  });

  testWidgets('desktop-only wrapper does not build its child off desktop',
      (tester) async {
    var childBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopRouteWrapper(
          title: '白板',
          desktopOnly: true,
          desktopPlatformOverride: false,
          childBuilder: (_) {
            childBuilds += 1;
            return const ColoredBox(
              key: ValueKey('desktop_business_child'),
              color: Colors.red,
            );
          },
        ),
      ),
    );

    expect(childBuilds, 0);
    expect(
      find.byKey(const ValueKey('desktop_only_unavailable')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop_business_child')),
      findsNothing,
    );
  });

  testWidgets('ordinary wrapped routes still pass through off desktop',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DesktopRouteWrapper(
          title: '记忆',
          desktopPlatformOverride: false,
          child: ColoredBox(
            key: ValueKey('ordinary_mobile_child'),
            color: Colors.green,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('ordinary_mobile_child')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop_only_unavailable')),
      findsNothing,
    );
  });

  testWidgets('all six frozen whiteboard routes are desktop-only on mobile',
      (tester) async {
    final mobileRouter = createAppRouter(
      GlobalKey<NavigatorState>(),
      () => const Scaffold(key: ValueKey('mobile_home')),
      desktopPlatformOverride: false,
    );
    addTearDown(mobileRouter.dispose);
    final cases = <(String, Finder)>[
      (AppRoutes.whiteboard, find.byType(WhiteboardIndexScreen)),
      (
        AppRoutes.whiteboardCanvasPath('mobile_board'),
        find.byType(WhiteboardCanvasRouteScreen),
      ),
      (AppRoutes.cardLibrary, find.byType(CardLibraryScreen)),
      (
        AppRoutes.cardEditPath('mobile_card'),
        find.byType(CardRichTextEditorScreen),
      ),
      (
        AppRoutes.sourceStudyPath('mobile_source'),
        find.byType(SourceStudyScreen),
      ),
      (AppRoutes.linkImport, find.byType(LinkImportScreen)),
    ];

    for (final routeCase in cases) {
      mobileRouter.go(routeCase.$1);
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: mobileRouter),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('desktop_only_unavailable')),
        findsOneWidget,
        reason: routeCase.$1,
      );
      expect(routeCase.$2, findsNothing, reason: routeCase.$1);
      expect(find.byType(DesktopSidebar), findsNothing, reason: routeCase.$1);
      expect(find.textContaining('仅在桌面端提供'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('desktop_only_return_home')),
        findsOneWidget,
      );
    }

    await tester.tap(
      find.byKey(const ValueKey('desktop_only_return_home')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile_home')), findsOneWidget);
  });
}

class _MissingSourceRepository extends UnifiedCardRepository {
  _MissingSourceRepository({required super.db, required super.whiteboardRoot});

  @override
  Future<SourceContent?> getSource(String sourceId) async => null;
}
