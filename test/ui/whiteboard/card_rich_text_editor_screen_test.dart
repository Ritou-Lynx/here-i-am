import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/rich_text_controller.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_storage.dart';
import 'package:memex/ui/whiteboard/editor/card_rich_text_editor_screen.dart';

void main() {
  late Directory tempDir;
  late RichTextStorage storage;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('editor_screen_test_');
    storage = RichTextStorage(tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('CardRichTextEditorScreen closed loop', () {
    /// Pumps the editor screen pushed onto a navigator so the app bar shows a
    /// back button (needed for the PopScope exit-guard tests).
    Future<void> pumpScreen(
      WidgetTester tester,
      String cardId, {
      RichTextEditingController? controller,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CardRichTextEditorScreen(
                    storage: storage,
                    cardId: cardId,
                    controller: controller,
                  ),
                )),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('loads saved document on start (restart recovery)',
        (tester) async {
      // Persist a document as if it was saved in a previous session.
      storage.saveSync('card_closed', const RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: '上次保存的内容'),
      ]));

      await pumpScreen(tester, 'card_closed');

      expect(find.text('上次保存的内容'), findsOneWidget);
    });

    testWidgets('typing then save persists, and a fresh screen reloads it',
        (tester) async {
      await pumpScreen(tester, 'card_persist');

      // Type into the paragraph and save via the app bar.
      await tester.enterText(find.byType(TextField).first, '写入并保存');
      await tester.pump();
      await tester.tap(find.text('保存').first);
      await tester.pumpAndSettle();

      // Verify it landed on disk.
      final saved = storage.loadSync('card_persist')!;
      expect(saved.blocks.first.text, equals('写入并保存'));

      // Simulate restart: a brand-new screen loads it again.
      await tester.pumpWidget(Container(key: UniqueKey())); // tear down
      await pumpScreen(tester, 'card_persist');
      expect(find.text('写入并保存'), findsOneWidget);
    });

    testWidgets('unsaved exit shows confirmation dialog', (tester) async {
      final controller =
          RichTextEditingController(RichTextDocument.empty());
      await pumpScreen(tester, 'card_unsaved', controller: controller);

      // Type without saving, then press the app bar back button (which goes
      // through PopScope).
      await tester.enterText(find.byType(TextField).first, '未保存');
      await tester.pump();

      // Sanity: the text field really holds the value and the controller is
      // dirty (typing must mark unsaved changes).
      final tf = tester.widget<TextField>(find.byType(TextField).first);
      expect(tf.controller!.text, equals('未保存'));
      expect(controller.isDirty, isTrue,
          reason: 'typing should mark the document dirty');

      // Trigger a back navigation through the navigator (like the app bar
      // back button / system back). PopScope should intercept it.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await navigator.maybePop();
      await tester.pumpAndSettle();

      // The confirm dialog is shown.
      expect(find.text('尚未保存'), findsOneWidget);
    });

    testWidgets('discard from confirm dialog leaves storage untouched',
        (tester) async {
      await pumpScreen(tester, 'card_discard');

      await tester.enterText(find.byType(TextField).first, '会被放弃');
      await tester.pump();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('尚未保存'), findsOneWidget);

      // Choose 放弃.
      await tester.tap(find.text('放弃'));
      await tester.pumpAndSettle();

      // Nothing persisted.
      expect(storage.exists('card_discard'), isFalse);
    });
  });
}
