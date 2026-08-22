import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/routing/router.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/whiteboard_canvas_route_screen.dart';
import 'package:memex/ui/whiteboard/whiteboard_index_screen.dart';

/// Task S — whiteboard index is now a real board list (Drift) with a create
/// action; tap opens the full-screen canvas route.
void main() {
  late AppDatabase db;
  late Directory tempDir;
  late File dbFile;
  late WhiteboardDriftStore store;
  late GoRouter router;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('m2a_board_index_');
    dbFile = File('${tempDir.path}${Platform.pathSeparator}whiteboard.sqlite');
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    store = WhiteboardDriftStore(db);
    AppDatabase.setTestInstance(db);
    router = createAppRouter(
      GlobalKey<NavigatorState>(),
      () => const Scaffold(body: SizedBox()),
      desktopPlatformOverride: true,
    );
  });

  tearDown(() async {
    router.dispose();
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> pumpIndex(WidgetTester tester) async {
    router.go(AppRoutes.whiteboard);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  testWidgets('index renders gray-paper page with real board list',
      (tester) async {
    final boardId = await store.createBoard(name: '桌面集成验证板');
    await pumpIndex(tester);

    expect(find.byType(WhiteboardIndexScreen), findsOneWidget);
    expect(find.text('白板'), findsWidgets);
    expect(find.text('桌面集成验证板'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('whiteboard_create_button')), findsOneWidget);
    expect(
      find.byKey(ValueKey('whiteboard_preview_$boardId')),
      findsOneWidget,
    );
  });

  testWidgets('index shows honest empty state when there are no boards',
      (tester) async {
    await pumpIndex(tester);
    expect(find.text('还没有白板'), findsOneWidget);
  });

  testWidgets('desktop scope is explicit and mobile keeps Spring Rain',
      (tester) async {
    await store.createBoard(name: '平台作用域白板');

    await tester.pumpWidget(
      const MaterialApp(home: WhiteboardIndexScreen()),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('whiteboard_mobile_index')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('whiteboard_mobile_list')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop_page_title')), findsNothing);
    expect(find.byKey(const ValueKey('whiteboard_grid')), findsNothing);
    expect(
      tester
          .widget<Scaffold>(
            find.byKey(const ValueKey('whiteboard_mobile_index')),
          )
          .backgroundColor,
      SpringRainUiTokens.daylightCanvas,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: DesktopWorkspaceTheme(child: WhiteboardIndexScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('whiteboard_desktop_index')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('desktop_page_title')), findsOneWidget);
    expect(find.byKey(const ValueKey('whiteboard_grid')), findsOneWidget);
    expect(find.byKey(const ValueKey('whiteboard_mobile_list')), findsNothing);
    expect(
      tester
          .widget<Scaffold>(
            find.byKey(const ValueKey('whiteboard_desktop_index')),
          )
          .backgroundColor,
      DesktopWorkspaceTokens.lieflatPalm.canvas,
    );
  });

  testWidgets('tapping a board opens the full-screen canvas route',
      (tester) async {
    final boardId = await store.createBoard(name: '跳转测试板');
    await pumpIndex(tester);

    await tester.tap(find.text('跳转测试板'));
    await tester.pump();
    await _pumpUntilFound(tester, find.byType(WhiteboardCanvasRouteScreen));

    expect(find.byType(WhiteboardCanvasRouteScreen), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path,
        AppRoutes.whiteboardCanvasPath(boardId));
  });

  testWidgets('create flow makes a board and opens its canvas', (tester) async {
    await pumpIndex(tester);

    await tester.tap(find.byKey(const ValueKey('whiteboard_create_button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新白板');
    await tester.tap(find.text('创建'));
    await tester.pump();
    await _pumpUntilFound(tester, find.byType(WhiteboardCanvasRouteScreen));

    final boards = await store.listBoards();
    expect(boards, hasLength(1));
    expect(boards.single.name, '新白板');
    expect(find.byType(WhiteboardCanvasRouteScreen), findsOneWidget);
  });

  testWidgets('board index survives a database restart', (tester) async {
    await store.createBoard(name: '重启仍在的白板');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await db.close();
    router.dispose();

    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    AppDatabase.setTestInstance(db);
    store = WhiteboardDriftStore(db);
    router = createAppRouter(
      GlobalKey<NavigatorState>(),
      () => const Scaffold(body: SizedBox()),
      desktopPlatformOverride: true,
    );

    await pumpIndex(tester);

    expect(find.text('重启仍在的白板'), findsOneWidget);
    expect(find.byKey(const ValueKey('whiteboard_grid')), findsOneWidget);
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets, reason: 'widget did not appear after 2 seconds');
}
