/// W6 — real desktop end-to-end loop.
///
/// Runs in a real Windows desktop window with the real Drift database:
/// home → 白板 entry → board index → create board → open full-screen canvas
/// → save via Drift → simulate restart → reopen → data recovered.
///
/// Run: flutter test integration_test -d windows
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/main.dart' as app;
import 'package:memex/utils/user_storage.dart' as memex_utils;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home → whiteboard → canvas → Drift → restart recovery',
      (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    debugPrint('ITEST: app started');

    // First desktop launch shows the user setup screen; complete it once
    // (subsequent launches go straight to the chat home).
    final homeVisible = await _waitForAny(
      tester,
      () => find.byIcon(Icons.more_horiz_rounded).evaluate().isNotEmpty,
      () => find.textContaining('下一步').evaluate().isNotEmpty ||
          find.textContaining('Continue').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 60),
      description: 'chat home or user setup',
    );
    debugPrint('ITEST: homeVisible=$homeVisible');
    if (!homeVisible) {
      // User setup flow: nickname → next → chat home.
      await tester.enterText(
        find.byType(TextField).first,
        '白板工作台',
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 250));
      final next = find.textContaining('下一步').evaluate().isNotEmpty
          ? find.textContaining('下一步')
          : find.textContaining('Continue');
      await tester.tap(next.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
    }

    await _waitFor(
      tester,
      () => find.byIcon(Icons.more_horiz_rounded).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 60),
      description: 'chat header actions trigger visible',
    );
    debugPrint('ITEST: chat header visible');

    // 2. Create the board in Drift FIRST so the index list (loaded on open)
    // shows it.
    final db = AppDatabase.instance;
    final store = WhiteboardDriftStore(db);
    await store.createBoard(name: '桌面集成验证板');
    final boards = await store.listBoards();
    expect(boards.map((b) => b.name), contains('桌面集成验证板'));
    final board = boards.firstWhere((b) => b.name == '桌面集成验证板');
    debugPrint('ITEST: board created in Drift');

    // 1. Home entry → whiteboard index (header actions panel).
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    await _waitFor(
      tester,
      () => find.byIcon(Icons.space_dashboard_outlined).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 10),
      description: '白板 entry visible in header actions',
    );
    debugPrint('ITEST: 白板 entry visible');
    await tester.tap(find.byIcon(Icons.space_dashboard_outlined));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(find.text('白板'), findsWidgets);
    debugPrint('ITEST: whiteboard index opened');

    // 3. Open the board from the index.
    await _waitFor(
      tester,
      () => find.text('桌面集成验证板').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 10),
      description: 'board listed in index',
    );
    await tester.tap(find.text('桌面集成验证板'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    debugPrint('ITEST: board tapped');

    // Full-screen canvas: no persistent top bar, board title in floating bar.
    await _waitFor(
      tester,
      () => find.text('桌面集成验证板').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 15),
      description: 'canvas floating bar shows board name',
    );
    debugPrint('ITEST: canvas opened');
    expect(find.byType(AppBar), findsNothing);

    // 4. Save the canvas (empty board) into Drift via the floating save
    // button, then verify the row exists in the database.
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    debugPrint('ITEST: save tapped');

    final saved = await store.load(board.boardId);
    expect(saved.isSuccess, isTrue);
    expect(saved.snapshot!.boards.any((b) => b.boardId == board.boardId),
        isTrue);
    debugPrint('ITEST: drifts save verified');

    // 5. Simulate restart: close the production database and reopen the real
    // file from disk (drift_flutter stores `memex_local_<userId>.sqlite` in
    // the documents directory), then recover the board.
    final userId = await memex_utils.UserStorage.getUserId();
    final docsDir = await getApplicationDocumentsDirectory();
    final dbFile =
        File('${docsDir.path}/memex_local_$userId.sqlite');
    expect(dbFile.existsSync(), isTrue,
        reason: 'real database file exists at $dbFile');

    await db.close();
    final reopened =
        AppDatabase.forTesting(NativeDatabase(dbFile));
    final reopenedStore = WhiteboardDriftStore(reopened);
    final afterRestart = await reopenedStore.load(board.boardId);
    expect(afterRestart.isSuccess, isTrue,
        reason: 'board must recover from Drift after restart');
    expect(afterRestart.snapshot!.boards.single.name, '桌面集成验证板');
    await reopened.close();
    debugPrint('ITEST: ALL DONE');
  });
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String description,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').where((s) => s.isNotEmpty).take(30).join(' | ');
      fail('timed out waiting for: $description\nvisible texts: $texts');
    }
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Waits for either [homeCondition] or [altCondition]; returns true when the
/// home condition won, false when the alternative won.
Future<bool> _waitForAny(
  WidgetTester tester,
  bool Function() homeCondition,
  bool Function() altCondition, {
  required Duration timeout,
  required String description,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!homeCondition() && !altCondition()) {
    if (DateTime.now().isAfter(deadline)) {
      final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').where((s) => s.isNotEmpty).take(30).join(' | ');
      fail('timed out waiting for: $description\nvisible texts: $texts');
    }
    await tester.pump(const Duration(milliseconds: 300));
  }
  return homeCondition();
}
