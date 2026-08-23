import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/rich_text_controller.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/ui/whiteboard/editor/card_rich_text_editor.dart';

void main() {
  Future<RichTextEditingController> pumpEditor(
    WidgetTester tester,
    List<RichTextBlock> blocks,
  ) async {
    final controller = RichTextEditingController(
      RichTextDocument(blocks: blocks),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardRichTextEditor(
            controller: controller,
            cardId: 'continuous-card',
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets('paragraph and heading blocks share one native editing value',
      (tester) async {
    final controller = await pumpEditor(tester, const [
      RichTextBlock(type: BlockType.paragraph, text: '第一段'),
      RichTextBlock(type: BlockType.heading, text: '第二段', attrs: {'level': 2}),
      RichTextBlock(type: BlockType.paragraph, text: '第三段'),
    ]);

    final field = find.byKey(const ValueKey('rich_text_continuous_document'));
    expect(field, findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text,
        equals('第一段\n第二段\n第三段'));

    tester.widget<TextField>(field).controller!.value = const TextEditingValue(
      text: '第一段第二段\n第三段',
      selection: TextSelection.collapsed(offset: 6),
    );
    await tester.pump();

    final saved = controller.flushToDocument();
    expect(saved.blocks, hasLength(2));
    expect(saved.blocks.first.text, equals('第一段第二段'));
    expect(saved.blocks.last.text, equals('第三段'));
  });

  testWidgets('cross-block replacement and Ctrl+A use the whole document',
      (tester) async {
    final controller = await pumpEditor(tester, const [
      RichTextBlock(type: BlockType.paragraph, text: '甲甲'),
      RichTextBlock(type: BlockType.paragraph, text: '乙乙'),
      RichTextBlock(type: BlockType.paragraph, text: '丙丙'),
    ]);
    final field = find.byKey(const ValueKey('rich_text_continuous_document'));
    await tester.tap(field);
    final textController = tester.widget<TextField>(field).controller!;

    textController.value = const TextEditingValue(
      text: '甲替换丙',
      selection: TextSelection.collapsed(offset: 4),
    );
    await tester.pump();
    expect(controller.flushToDocument().toPlainText(), equals('甲替换丙'));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(textController.selection.start, 0);
    expect(textController.selection.end, textController.text.length);
  });

  testWidgets('Chinese composing range is not committed by block mirroring',
      (tester) async {
    final controller = await pumpEditor(tester, const [
      RichTextBlock(type: BlockType.paragraph, text: ''),
      RichTextBlock(type: BlockType.paragraph, text: ''),
    ]);
    final field = find.byKey(const ValueKey('rich_text_continuous_document'));
    final textController = tester.widget<TextField>(field).controller!;
    textController.value = const TextEditingValue(
      text: 'ni\n第二段',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    await tester.pump();

    expect(textController.value.composing, const TextRange(start: 0, end: 2));
    expect(controller.flushToDocument().blocks.first.text, equals('ni'));
    expect(controller.canUndo, isTrue);
  });

  testWidgets('Ctrl+Z undoes coalesced typing and Ctrl+Y restores it',
      (tester) async {
    final controller = await pumpEditor(tester, const [
      RichTextBlock(type: BlockType.paragraph, text: '编辑前'),
    ]);
    final field = find.byKey(const ValueKey('rich_text_continuous_document'));
    await tester.tap(field);
    final textController = tester.widget<TextField>(field).controller!;

    textController.value = const TextEditingValue(
      text: '编辑前，连续',
      selection: TextSelection.collapsed(offset: 6),
    );
    textController.value = const TextEditingValue(
      text: '编辑前，连续输入',
      selection: TextSelection.collapsed(offset: 8),
    );
    await tester.pump();
    expect(controller.document.blocks.single.text, '编辑前，连续输入');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(textController.text, '编辑前');
    expect(controller.document.blocks.single.text, '编辑前');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(textController.text, '编辑前，连续输入');
    expect(controller.document.blocks.single.text, '编辑前，连续输入');
  });

  testWidgets('current block cycles Paragraph to H1 to H6 to Paragraph',
      (tester) async {
    final controller = await pumpEditor(tester, const [
      RichTextBlock(type: BlockType.paragraph, text: '标题候选'),
    ]);
    final field = find.byKey(const ValueKey('rich_text_continuous_document'));
    await tester.tap(field);

    await tester.tap(find.text('H1'));
    await tester.pump();
    expect(controller.document.blocks.single.headingLevel, 1);

    await tester.tap(find.text('H6'));
    await tester.pump();
    expect(controller.document.blocks.single.headingLevel, 6);

    await tester.tap(find.text('正文'));
    await tester.pump();
    expect(controller.document.blocks.single.type, BlockType.paragraph);
    expect(controller.document.blocks.single.attrs.containsKey('level'), isFalse);
  });

  testWidgets('continuous surface has no persistent Palm action rectangle',
      (tester) async {
    await pumpEditor(tester, const [
      RichTextBlock(type: BlockType.paragraph, text: '正文'),
      RichTextBlock(type: BlockType.paragraph, text: '下一段'),
    ]);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('rich_text_continuous_document')),
    );
    final decoration = field.decoration!;
    expect((decoration.enabledBorder! as OutlineInputBorder).borderSide.color,
        Colors.transparent);
  });

  testWidgets('compact surface embeds without a toolbar and can be read-only',
      (tester) async {
    final controller = RichTextEditingController(
      const RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: '画布内编辑'),
      ]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 140,
            child: CardRichTextEditor(
              controller: controller,
              cardId: 'compact-card',
              compact: true,
              showToolbar: false,
              readOnly: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('rich_text_toolbar')), findsNothing);
    expect(
      tester
          .widget<TextField>(
              find.byKey(const ValueKey('rich_text_continuous_document')))
          .readOnly,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
