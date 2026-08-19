/// Hermetic desktop loop for Card -> rich text -> library -> recovery.
///
/// Run: flutter test integration_test/whiteboard_rich_text_loop_test.dart -d windows
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/whiteboard/card_library_screen.dart';
import 'package:memex/ui/whiteboard/card_rich_text_editor_screen.dart';
import 'package:memex/ui/whiteboard/editor/card_rich_text_editor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('edit, save, query and recover one stable Card', (tester) async {
    final root = await Directory.systemTemp.createTemp('memex_wb_rich_');
    final dbFile =
        File('${root.path}${Platform.pathSeparator}whiteboard.sqlite');
    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    const cardId = 'f0_rich_text_loop';
    await repository.createTextCard(cardId: cardId, title: 'F0 card');
    CardRichTextEditorScreen.setRepositoryForTesting(repository);
    addTearDown(() async {
      CardRichTextEditorScreen.setRepositoryForTesting(null);
      await db.close();
      if (root.existsSync()) await root.delete(recursive: true);
    });

    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/cards/$cardId',
      routes: [
        GoRoute(
          path: '/cards',
          builder: (_, __) => CardLibraryScreen(repository: repository),
        ),
        GoRoute(
          path: '/cards/:cardId',
          builder: (_, state) => CardRichTextEditorScreen(
            cardId: state.pathParameters['cardId']!,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    Finder inEditor(Finder finder) => find.descendant(
          of: find.byType(CardRichTextEditor),
          matching: finder,
        );
    expect(inEditor(find.byType(TextField)), findsWidgets);
    await tester.enterText(
      inEditor(find.byType(TextField)).first,
      '中文 mixed English — searchable recovery keyword',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final persisted = await repository.getCard(cardId);
    expect(persisted!.card.body, contains('searchable recovery keyword'));
    expect(persisted.documentState, CardDocumentState.available);

    router.go('/cards');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'recovery keyword',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('searchable recovery keyword'), findsWidgets);

    await tester.tap(find.textContaining('searchable recovery keyword').last);
    await tester.pumpAndSettle();
    final restoredField = tester.widget<TextField>(
      inEditor(find.byType(TextField)).first,
    );
    expect(restoredField.controller!.text,
        contains('searchable recovery keyword'));
  });
}
