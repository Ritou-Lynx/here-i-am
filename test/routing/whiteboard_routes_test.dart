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
import 'package:memex/routing/routes.dart';
import 'package:memex/routing/router.dart';
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

  Future<void> pumpRoute(WidgetTester tester, String path) async {
    router.go(path);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  testWidgets('whiteboard index route resolves', (tester) async {
    await pumpRoute(tester, AppRoutes.whiteboard);
    expect(find.byType(WhiteboardIndexScreen), findsOneWidget);
  });

  testWidgets(
      'canvas route resolves with boardId and renders full-screen '
      'canvas for an existing board (direct route entry)', (tester) async {
    final boardId = await store.createBoard(name: '路由测试板');
    await pumpRoute(tester, AppRoutes.whiteboardCanvasPath(boardId));

    expect(find.byType(WhiteboardCanvasRouteScreen), findsOneWidget);
    // Loaded from Drift: the full-screen canvas appears (no persistent AppBar).
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('路由测试板'), findsOneWidget);
  });

  testWidgets('canvas route for missing board shows error state',
      (tester) async {
    await pumpRoute(tester, AppRoutes.whiteboardCanvasPath('board_missing'));
    expect(find.byType(WhiteboardCanvasRouteScreen), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);
  });

  testWidgets('canvas route saves to Drift when the save button is tapped',
      (tester) async {
    final boardId = await store.createBoard(name: '保存测试板');
    await pumpRoute(tester, AppRoutes.whiteboardCanvasPath(boardId));

    // Give the loader time to finish (real Drift store, async initState).
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.byType(WhiteboardCanvasRouteScreen), findsOneWidget);
    expect(find.text('保存测试板'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle();

    final saved = await store.load(boardId);
    expect(saved.isSuccess, isTrue);
    expect(saved.snapshot!.boards.single.name, '保存测试板');
  });

  testWidgets('card library route resolves', (tester) async {
    await pumpRoute(tester, AppRoutes.cardLibrary);
    expect(find.byType(CardLibraryScreen), findsOneWidget);
  });

  testWidgets('card edit route resolves with cardId parameter', (tester) async {
    await pumpRoute(tester, AppRoutes.cardEditPath('card_abc'));
    expect(find.byType(CardRichTextEditorScreen), findsOneWidget);
    // The real editor screen opens (W2 body) with the card id in its title.
    expect(find.textContaining('card_abc'), findsOneWidget);
  });

  testWidgets('source study route resolves with sourceId parameter',
      (tester) async {
    await pumpRoute(tester, AppRoutes.sourceStudyPath('src_video_1'));
    expect(find.byType(SourceStudyScreen), findsOneWidget);
    expect(find.text('src_video_1'), findsOneWidget);
  });

  testWidgets('link import route resolves', (tester) async {
    await pumpRoute(tester, AppRoutes.linkImport);
    expect(find.byType(LinkImportScreen), findsOneWidget);
  });
}
