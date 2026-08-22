import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/rich_text_controller.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_object_store.dart';
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
      final controller =
          RichTextEditingController(const RichTextDocument(blocks: [
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

      final documentField = tester.widget<TextField>(
        find.byKey(const ValueKey('rich_text_continuous_document')),
      );
      expect(documentField.controller!.text, equals('标题\n正文'));
      // Toolbar buttons present.
      expect(find.text('B'), findsOneWidget);
      expect(find.text('H1'), findsOneWidget);
    });

    testWidgets('typing in a field updates the document on flush',
        (tester) async {
      final controller = RichTextEditingController(RichTextDocument.empty());
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
      final controller = RichTextEditingController(RichTextDocument.empty());
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
      final tc = tester.widget<TextField>(textField).controller!;
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
      final controller =
          RichTextEditingController(const RichTextDocument(blocks: [
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
      final controller =
          RichTextEditingController(const RichTextDocument(blocks: [
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
        RichTextBlock(
            type: BlockType.heading, text: '恢复标题', attrs: {'level': 2}),
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

      final documentField = tester.widget<TextField>(
        find.byKey(const ValueKey('rich_text_continuous_document')),
      );
      expect(documentField.controller!.text, equals('恢复标题\n恢复正文'));
    });

    testWidgets('undo and redo toolbar buttons work', (tester) async {
      final controller = RichTextEditingController(RichTextDocument.empty());
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
      final tc = tester
          .widget<TextField>(
              find.byKey(const ValueKey('rich_text_continuous_document')))
          .controller!;
      tc.value = const TextEditingValue(
        text: '第二版',
        selection: TextSelection.collapsed(offset: 3),
      );
      controller.commitHistory(coalesce: false);
      await tester.pump();

      expect(controller.document.blocks.first.text, equals('第二版'));

      // Undo.
      await tester.tap(find.byTooltip('撤销'));
      await tester.pump();
      expect(controller.document.blocks.first.text, equals('第一版'));

      // Redo.
      await tester.tap(find.byTooltip('重做'));
      await tester.pump();
      expect(controller.document.blocks.first.text, equals('第二版'));
    });

    testWidgets('link button applies a link mark over the selection',
        (tester) async {
      final controller = RichTextEditingController(RichTextDocument.empty());
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
      final tc = tester
          .widget<TextField>(
              find.byKey(const ValueKey('rich_text_continuous_document')))
          .controller!;
      tc.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
      // Confirm the field is focused so the toolbar targets the right block.
      expect(controller.focusNodeFor(0).hasFocus, isTrue);

      // Open the link dialog and enter a URL.
      await tester.tap(find.byTooltip('插入链接'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextField).last, 'https://example.com');
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
      final controller = RichTextEditingController(RichTextDocument.empty());
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
      final tc = tester
          .widget<TextField>(
              find.byKey(const ValueKey('rich_text_continuous_document')))
          .controller!;
      tc.selection = const TextSelection(baseOffset: 0, extentOffset: 4);

      await tester.tap(find.byTooltip('插入链接'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextField).last, 'javascript:alert(1)');
      await tester.tap(find.text('插入'));
      await tester.pumpAndSettle();

      // No link mark was applied.
      final block = controller.flushToDocument().blocks.first;
      expect(block.marks.where((m) => m.type == MarkType.link), isEmpty);
    });

    testWidgets('Ctrl+S triggers save', (tester) async {
      RichTextDocument? saved;
      final controller =
          RichTextEditingController(const RichTextDocument(blocks: [
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
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS, platform: 'macos');
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

  group('list nesting (Tab / Shift-Tab / Enter)', () {
    Future<RichTextEditingController> pumpList(tester) async {
      final controller = RichTextEditingController(const RichTextDocument(
        blocks: [
          RichTextBlock(
            type: BlockType.list,
            text: '第一项',
            attrs: {'ordered': false},
          ),
        ],
      ));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CardRichTextEditor(
            controller: controller,
            cardId: 'card_list',
          ),
        ),
      ));
      // Focus the list field.
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      return controller;
    }

    testWidgets(
        'desktop: toolbar tap keeps field focus, Tab/Enter still structure '
        'the list', (tester) async {
      // Windows target platform: InkWell toolbar buttons steal focus on
      // tap; the editor must hand it back so keyboard structure ops work.
      // The override must be reset inside the test body (foundation
      // invariant check runs before tearDowns).
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      final c = RichTextEditingController(const RichTextDocument(
        blocks: [
          RichTextBlock(type: BlockType.paragraph, text: '第一项'),
        ],
      ));
      try {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: CardRichTextEditor(
              controller: c,
              cardId: 'card_desktop_focus',
            ),
          ),
        ));
        await tester.tap(find.byType(TextField).first);
        await tester.pump();

        // Convert to a list via the toolbar (focus is stolen on desktop).
        await tester.tap(find.text('•'));
        await tester.pumpAndSettle();
        // The editor restores field focus after the toolbar action.
        expect(c.focusNodeFor(0).hasFocus, isTrue,
            reason: 'field focus restored after desktop toolbar tap');
        expect(c.blockAt(0).type, equals(BlockType.list));

        // Tab still indents and Enter still creates a sibling.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(c.blockAt(0).listDepth, equals(1));

        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(c.blockCount, equals(2));
        expect(c.blockAt(1).type, equals(BlockType.list));
        expect(c.blockAt(1).listDepth, equals(1));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Tab indents the focused list item', (tester) async {
      final c = await pumpList(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(c.blockAt(0).listDepth, equals(1));

      // Shift-Tab outdents back.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(c.blockAt(0).listDepth, equals(0));
    });

    testWidgets('Enter on a list item continues the same list', (tester) async {
      final c = await pumpList(tester);
      await tester.enterText(find.byType(TextField).first, '第二项');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(c.blockCount, equals(2));
      final sibling = c.blockAt(1);
      expect(sibling.type, equals(BlockType.list));
      expect(sibling.listOrdered, isFalse);
      expect(sibling.listDepth, equals(0));
      // The new sibling is focused.
      expect(c.focusNodeFor(1).hasFocus, isTrue);
    });

    testWidgets('Enter on a nested list item keeps the depth', (tester) async {
      final c = RichTextEditingController(const RichTextDocument(
        blocks: [
          RichTextBlock(
            type: BlockType.list,
            text: '深层项',
            attrs: {'ordered': true, 'depth': 2},
          ),
        ],
      ));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CardRichTextEditor(
            controller: c,
            cardId: 'card_list_nested',
          ),
        ),
      ));
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(c.blockCount, equals(2));
      expect(c.blockAt(1).listDepth, equals(2));
      expect(c.blockAt(1).listOrdered, isTrue);
    });

    testWidgets('Enter on an empty list item exits back to paragraph',
        (tester) async {
      final c = await pumpList(tester);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.blockCount, equals(1));
      expect(c.blockAt(0).type, equals(BlockType.paragraph));
    });
  });

  group('quote children editing', () {
    testWidgets('Enter on a quote creates an editable child paragraph',
        (tester) async {
      final c = RichTextEditingController(const RichTextDocument(
        blocks: [RichTextBlock(type: BlockType.quote, text: '引言')],
      ));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CardRichTextEditor(
            controller: c,
            cardId: 'card_quote',
          ),
        ),
      ));
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(c.childCount(0), equals(1));
      expect(c.childFocusNodeFor(0, 0).hasFocus, isTrue);

      // Type into the child; flush reads it back.
      await tester.enterText(find.byType(TextField).at(1), '引用正文');
      await tester.pump();
      final doc = c.flushToDocument();
      expect(doc.blocks.first.children.first.text, equals('引用正文'));
    });

    testWidgets('Enter on an empty quote child removes it', (tester) async {
      final c = RichTextEditingController(const RichTextDocument(
        blocks: [
          RichTextBlock(
            type: BlockType.quote,
            text: '引言',
            children: [RichTextBlock(type: BlockType.paragraph)],
          ),
        ],
      ));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CardRichTextEditor(
            controller: c,
            cardId: 'card_quote_empty',
          ),
        ),
      ));
      // Focus the child field (the second TextField).
      await tester.tap(find.byType(TextField).at(1));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.childCount(0), equals(0));
    });

    testWidgets('quote children survive flush and serialization',
        (tester) async {
      final c = RichTextEditingController(const RichTextDocument(
        blocks: [
          RichTextBlock(
            type: BlockType.quote,
            text: '引言',
            children: [
              RichTextBlock(type: BlockType.paragraph, text: '已有子段'),
            ],
          ),
        ],
      ));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CardRichTextEditor(
            controller: c,
            cardId: 'card_quote_rt',
          ),
        ),
      ));
      expect(find.text('已有子段'), findsOneWidget);
      final json = c.flushToDocument().toJson();
      expect(json['blocks'][0]['children'][0]['text'], equals('已有子段'));
    });
  });

  group('media import (image / attachment)', () {
    final onePng = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
        '/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==');

    Future<RichTextObjectStore> pumpWithImporter(
      WidgetTester tester,
      RichTextEditingController c,
      RichTextMediaImporter importer, {
      RichTextObjectStore? store,
    }) async {
      final objectStore = store ??
          RichTextObjectStore(Directory.systemTemp.createTempSync('media_ui_'));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CardRichTextEditor(
            controller: c,
            cardId: 'card_media',
            objectStore: objectStore,
            mediaImporter: importer,
          ),
        ),
      ));
      return objectStore;
    }

    testWidgets('image import inserts an image block with a stable asset ref',
        (tester) async {
      final c = RichTextEditingController(RichTextDocument.empty());
      final store = RichTextObjectStore(
          Directory.systemTemp.createTempSync('media_ui_img_'));
      await pumpWithImporter(tester, c, (kind) async {
        final f =
            File('${store.baseDir.path}${Platform.pathSeparator}tmp_pick.png');
        f.writeAsBytesSync(onePng);
        return [await store.importFile(f.path, alt: '临时截图.png')];
      }, store: store);

      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('导入图片'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      final doc = c.flushToDocument();
      expect(doc.assetRefs.length, equals(1));
      final ref = doc.assetRefs.first;
      expect(ref.objectRef, startsWith('objects/'));
      expect(ref.mimeType, equals('image/png'));
      expect(doc.blocks.last.type, equals(BlockType.image));
      expect(doc.blocks.last.assetRefId, equals(ref.refId));
      // The temporary pick path never enters the model.
      expect(ref.objectRef.contains('tmp_pick'), isFalse);
      // The object file exists under objects/.
      expect(store.resolveFile(ref), isNotNull);
    });

    testWidgets('attachment import inserts a reference block', (tester) async {
      final c = RichTextEditingController(RichTextDocument.empty());
      final store = RichTextObjectStore(
          Directory.systemTemp.createTempSync('media_ui_att_'));
      await pumpWithImporter(tester, c, (kind) async {
        final f =
            File('${store.baseDir.path}${Platform.pathSeparator}tmp_doc.pdf');
        f.writeAsBytesSync([1, 2, 3]);
        return [await store.importFile(f.path, alt: '报告.pdf')];
      }, store: store);

      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('导入附件'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      final doc = c.flushToDocument();
      expect(doc.blocks.last.type, equals(BlockType.reference));
      expect(doc.blocks.last.attrs['label'], equals('报告.pdf'));
      expect(doc.assetRefs.first.mimeType, equals('application/pdf'));
    });

    testWidgets('media block renders with preview and delete button',
        (tester) async {
      final c = RichTextEditingController(RichTextDocument.empty());
      final store = RichTextObjectStore(
          Directory.systemTemp.createTempSync('media_ui_render_'));
      await pumpWithImporter(tester, c, (kind) async {
        final f =
            File('${store.baseDir.path}${Platform.pathSeparator}tmp_pic.png');
        f.writeAsBytesSync(onePng);
        return [await store.importFile(f.path, alt: '示意图')];
      }, store: store);

      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('导入图片'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      // Delete removes the block.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      final doc = c.flushToDocument();
      expect(doc.blocks.where((b) => b.type == BlockType.image), isEmpty);
      expect(doc.assetRefs, isEmpty);
    });

    testWidgets('imported media round-trips through save → reload',
        (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('media_ui_rt_');
      final storage = RichTextStorage(tempDir);
      final store = RichTextObjectStore(tempDir);
      final c = RichTextEditingController(RichTextDocument.empty());
      await pumpWithImporter(tester, c, (kind) async {
        final f = File('${tempDir.path}${Platform.pathSeparator}tmp_rt.png');
        f.writeAsBytesSync(onePng);
        return [await store.importFile(f.path, alt: '恢复图.png')];
      }, store: store);

      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('导入图片'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      // Save and "restart": new controller loaded from storage.
      storage.saveSync('card_media', c.flushToDocument());
      final loaded = storage.loadSync('card_media')!;
      final restarted = RichTextEditingController(loaded);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CardRichTextEditor(
            controller: restarted,
            cardId: 'card_media',
            objectStore: store,
            mediaImporter: (kind) async => const [],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(loaded.assetRefs.length, equals(1));
      expect(loaded.assetRefs.first.objectRef, startsWith('objects/'));
      expect(store.resolveFile(loaded.assetRefs.first), isNotNull);
      expect(find.text('恢复图.png'), findsOneWidget);
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

    testWidgets('body block uses code-first + CJK-fallback token',
        (tester) async {
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

    testWidgets('inline code mark uses the Cascadia Code token',
        (tester) async {
      await pumpMixed(tester, blocks: const [
        RichTextBlock(
          type: BlockType.paragraph,
          text: '运行 flutter test 即可',
          marks: [
            RichTextMark(type: MarkType.code, start: 3, end: 15),
          ],
        ),
      ]);

      final blockController = tester
          .widget<TextField>(
              find.byKey(const ValueKey('rich_text_continuous_document')))
          .controller!;
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
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        contains('混排测试'),
      );
    });
  });
}

/// Depth-first search for a **leaf** [TextSpan] whose exact text equals
/// [needle]. Returns the first matching leaf span, or null.
TextSpan? _exactLeafSpan(TextSpan span, String needle) {
  final own = span.toPlainText();
  if ((span.children == null || span.children!.isEmpty) && own == needle) {
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
