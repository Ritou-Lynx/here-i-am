import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/routing/router.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/whiteboard/whiteboard_canvas_route_screen.dart';
import 'package:memex/ui/whiteboard/whiteboard_index_screen.dart';

/// Task S — whiteboard index is now a real board list (Drift) with a create
/// action; tap opens the full-screen canvas route.
void main() {
  late AppDatabase db;
  late WhiteboardDriftStore store;
  late GoRouter router;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = WhiteboardDriftStore(db);
    AppDatabase.setTestInstance(db);
    router = createAppRouter(
      GlobalKey<NavigatorState>(),
      () => const Scaffold(body: SizedBox()),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpIndex(WidgetTester tester) async {
    router.go(AppRoutes.whiteboard);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  testWidgets('index renders gray-paper page with real board list',
      (tester) async {
    await store.createBoard(name: '桌面集成验证板');
    await pumpIndex(tester);

    expect(find.byType(WhiteboardIndexScreen), findsOneWidget);
    // The page title '白板' appears in both the shell sidebar nav and the
    // desktop page head; assert the board name is rendered instead.
    expect(find.text('桌面集成验证板'), findsOneWidget);
    expect(find.byKey(const ValueKey('whiteboard_create_button')), findsOneWidget);
  });

  testWidgets('index shows honest empty state when there are no boards',
      (tester) async {
    await pumpIndex(tester);
    expect(find.text('还没有白板'), findsOneWidget);
  });

  testWidgets('tapping a board opens the full-screen canvas route',
      (tester) async {
    final boardId = await store.createBoard(name: '跳转测试板');
    await pumpIndex(tester);

    await tester.tap(find.text('跳转测试板'));
    await tester.pumpAndSettle();

    expect(find.byType(WhiteboardCanvasRouteScreen), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path,
        AppRoutes.whiteboardCanvasPath(boardId));
  });

  testWidgets('create flow makes a board and opens its canvas',
      (tester) async {
    await pumpIndex(tester);

    await tester.tap(find.byKey(const ValueKey('whiteboard_create_button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新白板');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    final boards = await store.listBoards();
    expect(boards, hasLength(1));
    expect(boards.single.name, '新白板');
    expect(find.byType(WhiteboardCanvasRouteScreen), findsOneWidget);
  });
}
