/// Hermetic desktop persistence loop for the Drift-backed whiteboard.
///
/// Run: flutter test integration_test/whiteboard_desktop_loop_test.dart -d windows
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/whiteboard/whiteboard_canvas_route_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('canvas save survives a real database reconnect', (tester) async {
    final root = await Directory.systemTemp.createTemp('memex_wb_desktop_');
    final dbFile =
        File('${root.path}${Platform.pathSeparator}whiteboard.sqlite');
    addTearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    final store = WhiteboardDriftStore(db);
    final boardId = await store.createBoard(name: 'F0 isolated desktop board');

    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardCanvasRouteScreen(
          boardId: boardId,
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('F0 isolated desktop board'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle();

    final saved = await store.load(boardId);
    expect(saved.isSuccess, isTrue);
    expect(saved.snapshot!.boards.map((entry) => entry.boardId),
        contains(boardId));

    // Dispose widgets and the first connection before simulating restart.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await db.close();

    final reopened = AppDatabase.forTesting(NativeDatabase(dbFile));
    final afterRestart = await WhiteboardDriftStore(reopened).load(boardId);
    expect(afterRestart.isSuccess, isTrue);
    expect(
      afterRestart.snapshot!.boards.any(
        (entry) =>
            entry.boardId == boardId &&
            entry.name == 'F0 isolated desktop board',
      ),
      isTrue,
    );
    await reopened.close();
  });
}
