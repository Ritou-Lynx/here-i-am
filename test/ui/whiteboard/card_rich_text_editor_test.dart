import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/rich_text_controller.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_storage.dart';
import 'package:memex/ui/whiteboard/editor/card_rich_text_editor.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

void main() {
  late Directory tempDir;
  late RichTextStorage storage;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('editor_test_');
    storage = RichTextStorage(tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('CardRichTextEditor widget', () {
    testWidgets('renders blocks from document and allows typing',
        (tester) async {
      final controller = RichTextEditingController(const RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.heading, text: '标题', attrs: {'level': 1}),
        RichTextBlock(type: BlockType.paragraph, text: '正文'),
      ]));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CardRichTextEditor(
            controller: controller,
            cardId: 'card_test',
          ),
        ),
      ));

      // Heading text is visible.
      expect(find.text('标题'), findsOneWidget);
      // Paragraph text is visible.
      expect(find.text('正文'), findsOneWidget);
      // Toolbar buttons present.
      expect(find.text('B'), findsOneWidget);
      expect(find.text('H1'), findsOneWidget);
    });

    testWidgets('typing in a field updates the document on flush',
        (tester) async {
      final controller =
          RichTextEditingController(RichTextDocument.empty());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CardRichTextEditor(
            controller: controller,
            cardId: 'card_test',
          ),
        ),
      ));

      // Find the first TextField and type into it.
      await tester.enterText(find.byType(TextField).first, '你好世界');
      await tester.pump();

      final doc = controller.flushToDocument();
      expect(doc.blocks.first.text, equals('你好世界'));
    });

    testWidgets('Chinese IME composition state is handled by EditableText',
        (tester) async {
      // This test verifies that the editor uses real TextFields (which
      // handle IME composition) rather than a custom text painter. We
      // simulate a composing region update.
      final controller =
          RichTextEditingController(RichTextDocument.empty());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CardRichTextEditor(
            controller: controller,
            cardId: 'card_ime',
          ),
        ),
      ));

      final textField = find.byType(TextField).first;
      await tester.tap(textField);
      await tester.pump();

      // Simulate IME composition: set a composing region.
      final tc = controller.controllerFor(0);
      tc.value = const TextEditingValue(
        text: '你好',
        composing: TextRange(start: 0, end: 2),
      );
      await tester.pump();

      // Confirm the composing region is preserved.
      expect(tc.value.composing, equals(const TextRange(start: 0, end: 2)));

      // Commit the composition.
      tc.value = const TextEditingValue(
        text: '你好世界',
        selection: TextSelection.collapsed(offset: 4),
      );
      await tester.pump();

      final doc = controller.flushToDocument();
      expect(doc.blocks.first.text, equals('你好世界'));
    });

    testWidgets('mixed CJK and Latin text renders without error',
        (tester) async {
      final controller = RichTextEditingController(const RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: '中文 ABC 123 mixed 混排'),
      ]));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CardRichTextEditor(
            controller: controller,
            cardId: 'card_mixed',
          ),
        ),
      ));
      expect(find.text('中文 ABC 123 mixed 混排'), findsOneWidget);
    });

    testWidgets('save callback fires with current document', (tester) async {
      RichTextDocument? saved;
      final controller = RichTextEditingController(const RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: '保存测试'),
      ]));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CardRichTextEditor(
            controller: controller,
            cardId: 'card_save',
            onSave: (doc) => saved = doc,
          ),
        ),
      ));

      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(saved, isNotNull);
      expect(saved!.blocks.first.text, equals('保存测试'));
      expect(controller.isDirty, isFalse);
    });

    testWidgets('restart recovery: save to storage, reload, load into editor',
        (tester) async {
      // Save a document to storage.
      const original = RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.heading, text: '恢复标题', attrs: {'level': 2}),
        RichTextBlock(type: BlockType.paragraph, text: '恢复正文'),
      ]);
      storage.saveSync('card_recover', original);

      // Simulate restart: load from storage.
      final loaded = storage.loadSync('card_recover')!;
      final controller = RichTextEditingController(loaded);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CardRichTextEditor(
            controller: controller,
            cardId: 'card_recover',
          ),
        ),
      ));

      expect(find.text('恢复标题'), findsOneWidget);
      expect(find.text('恢复正文'), findsOneWidget);
    });

    testWidgets('undo and redo toolbar buttons work', (tester) async {
      final controller =
          RichTextEditingController(RichTextDocument.empty());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CardRichTextEditor(
            controller: controller,
            cardId: 'card_undo',
          ),
        ),
      ));

      // Type something and commit.
      await tester.enterText(find.byType(TextField).first, '第一版');
      await tester.pump();
      controller.commitHistory(coalesce: false);

      // Type more and commit.
      final tc = controller.controllerFor(0);
      tc.value = const TextEditingValue(
        text: '第二版',
        selection: TextSelection.collapsed(offset: 3),
      );
      controller.commitHistory(coalesce: false);
      await tester.pump();

      expect(controller.document.blocks.first.text, equals('第二版'));

      // Undo.
      await tester.tap(find.text('↶'));
      await tester.pump();
      expect(controller.document.blocks.first.text, equals('第一版'));

      // Redo.
      await tester.tap(find.text('↷'));
      await tester.pump();
      expect(controller.document.blocks.first.text, equals('第二版'));
    });

    testWidgets('link button applies a link mark over the selection',
        (tester) async {
      final controller = RichTextEditingController(
          RichTextDocument.empty());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CardRichTextEditor(
            controller: controller,
            cardId: 'card_link',
          ),
        ),
      ));

      // Type text and select a range.
      await tester.enterText(find.byType(TextField).first, '访问示例网站');
      await tester.pump();
      final tc = controller.controllerFor(0);
      tc.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
      // Confirm the field is focused so the toolbar targets the right block.
      expect(controller.focusNodeFor(0).hasFocus, isTrue);

      // Open the link dialog and enter a URL.
      await tester.tap(find.text('🔗'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'https://example.com');
      await tester.tap(find.text('插入'));
      await tester.pumpAndSettle();

      // The block now carries a link mark with the href.
      final block = controller.flushToDocument().blocks.first;
      final linkMarks =
          block.marks.where((m) => m.type == MarkType.link).toList();
      expect(linkMarks.length, equals(1));
      expect(linkMarks.first.attrs['href'], equals('https://example.com'));
      expect(linkMarks.first.start, equals(0));
      expect(linkMarks.first.end, equals(4));
    });

    testWidgets('link button rejects non-http schemes', (tester) async {
      final controller = RichTextEditingController(
          RichTextDocument.empty());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CardRichTextEditor(
            controller: controller,
            cardId: 'card_link_bad',
          ),
        ),
      ));

      await tester.enterText(find.byType(TextField).first, '危险链接');
      await tester.pump();
      final tc = controller.controllerFor(0);
      tc.selection = const TextSelection(baseOffset: 0, extentOffset: 4);

      await tester.tap(find.text('🔗'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'javascript:alert(1)');
      await tester.tap(find.text('插入'));
      await tester.pumpAndSettle();

      // No link mark was applied.
      final block = controller.flushToDocument().blocks.first;
      expect(block.marks.where((m) => m.type == MarkType.link), isEmpty);
    });

    testWidgets('Ctrl+S triggers save', (tester) async {
      RichTextDocument? saved;
      final controller = RichTextEditingController(const RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: '快捷键保存'),
      ]));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CardRichTextEditor(
            controller: controller,
            cardId: 'card_shortcut',
            onSave: (doc) => saved = doc,
          ),
        ),
      ));

      // Focus the editor and send Ctrl+S.
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS,
          platform: 'macos');
      // On macOS, Cmd is the modifier; we test the control path separately.
      // For cross-platform test, send with control modifier.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(saved, isNotNull);
      expect(saved!.blocks.first.text, equals('快捷键保存'));
    });
  });

  group('Rich text mixed-font typography', () {
    Future<RichTextEditingController> pumpMixed(
      WidgetTester tester, {
      required List<RichTextBlock> blocks,
    }) async {
      final controller = RichTextEditingController(
        RichTextDocument(blocks: blocks),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CardRichTextEditor(
            controller: controller,
            cardId: 'card_fonts',
          ),
        ),
      ));
      return controller;
    }

    testWidgets('body block uses code-first + CJK-fallback token', (tester) async {
      await pumpMixed(tester, blocks: const [
        RichTextBlock(
          type: BlockType.paragraph,
          text: '中文 English 123，标点。mixed code: let x = 1',
        ),
      ]);

      final field = tester.widget<TextField>(find.byType(TextField).first);
      final style = field.style!;
      // Latin / digits / code resolve to Cascadia Code first.
      expect(style.fontFamily, equals(richTextCodeFamily));
      // CJK falls back to 汇文明朝体 then system serif.
      expect(style.fontFamilyFallback, contains(richTextCjkFamily));
      for (final f in richTextCjkFallback) {
        expect(style.fontFamilyFallback, contains(f));
      }
      // The LXGW WenKai (霞鹜文楷) family must never appear.
      expect(style.fontFamily, isNot(equals('LXGW WenKai')));
      expect(style.fontFamilyFallback, isNot(contains('LXGW WenKai')));
    });

    testWidgets('code block uses the Cascadia Code token', (tester) async {
      await pumpMixed(tester, blocks: const [
        RichTextBlock(
          type: BlockType.code,
          text: 'var x = 1;\nprint("hi");',
          attrs: {'language': 'dart'},
        ),
      ]);

      final field = tester.widget<TextField>(find.byType(TextField).first);
      final style = field.style!;
      // Code blocks lead with the Cascadia Code family.
      expect(style.fontFamily, equals(richTextCodeFamily));
      // System monospace fallbacks are configured.
      for (final f in richTextCodeFallback) {
        expect(style.fontFamilyFallback, contains(f));
      }
      // CJK inside code comments still falls back through the serif chain.
      expect(style.fontFamilyFallback, contains(richTextCjkFamily));
    });

    testWidgets('inline code mark uses the Cascadia Code token', (tester) async {
      final controller = await pumpMixed(tester, blocks: const [
        RichTextBlock(
          type: BlockType.paragraph,
          text: '运行 flutter test 即可',
          marks: [
            RichTextMark(type: MarkType.code, start: 3, end: 15),
          ],
        ),
      ]);

      final blockController =
          controller.controllerFor(0) as RichTextBlockController;
      // Build the text span the field renders and inspect the code segment.
      final span = blockController.buildTextSpan(
        context: tester.element(find.byType(TextField).first),
        style: richTextBodyTextStyle(),
        withComposing: false,
      );
      // The code-marked segment is a leaf span whose exact text is
      // "flutter test" (start 3, end 15 of "运行 flutter test 即可").
      final codeSpan = _exactLeafSpan(span, 'flutter test');
      expect(codeSpan, isNotNull);
      expect(codeSpan!.style!.fontFamily, equals(richTextCodeFamily));
    });

    testWidgets('mixed CJK + Latin + digits renders without error',
        (tester) async {
      await pumpMixed(tester, blocks: const [
        RichTextBlock(
          type: BlockType.heading,
          text: '标题 Heading 2026 — 混排测试',
          attrs: {'level': 2},
        ),
        RichTextBlock(
          type: BlockType.paragraph,
          text: '中文，English. 数字 123 与标点「，。」mixed!',
        ),
      ]);
      // Both fields rendered (no layout exception).
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.textContaining('混排测试'), findsOneWidget);
    });
  });
}

/// Depth-first search for a **leaf** [TextSpan] whose exact text equals
/// [needle]. Returns the first matching leaf span, or null.
TextSpan? _exactLeafSpan(TextSpan span, String needle) {
  final own = span.toPlainText();
  if ((span.children == null || span.children!.isEmpty) &&
      own == needle) {
    return span;
  }
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is TextSpan) {
      final hit = _exactLeafSpan(child, needle);
      if (hit != null) return hit;
    }
  }
  return null;
}
