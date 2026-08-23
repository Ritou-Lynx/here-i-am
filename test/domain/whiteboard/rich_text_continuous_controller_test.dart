import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/rich_text_controller.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_storage.dart';

void main() {
  test('rapid continuous replacements coalesce into one undo step', () {
    final controller = RichTextEditingController(
      const RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: '第一段'),
        RichTextBlock(type: BlockType.paragraph, text: '第二段'),
      ]),
    );

    controller.replaceContinuousBlocks(const [
      RichTextBlock(type: BlockType.paragraph, text: '连'),
    ]);
    controller.replaceContinuousBlocks(const [
      RichTextBlock(type: BlockType.paragraph, text: '连续'),
    ]);
    controller.replaceContinuousBlocks(const [
      RichTextBlock(
        type: BlockType.heading,
        text: '连续输入',
        attrs: {'level': 6},
      ),
    ]);

    final encoded = controller.flushToDocument().toJson();
    final restored = RichTextDocument.fromJson(encoded);
    expect(restored.blocks.single.text, '连续输入');
    expect(restored.blocks.single.headingLevel, 6);

    expect(controller.undo(), isTrue);
    expect(controller.document.blocks, hasLength(2));
    expect(controller.document.blocks.first.text, '第一段');
    expect(controller.undo(), isFalse);
    expect(controller.redo(), isTrue);
    expect(controller.document.blocks.single.text, '连续输入');
    expect(controller.document.blocks.single.headingLevel, 6);
  });

  test('continuous replacement keeps stable asset refs only while referenced',
      () {
    final controller = RichTextEditingController(
      const RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: '纯文字'),
      ]),
    );
    controller.replaceContinuousBlocks(const [
      RichTextBlock(type: BlockType.paragraph, text: '更新后的纯文字'),
    ]);

    final json = controller.flushToDocument().toJson();
    expect(json.containsKey('x'), isFalse);
    expect(json.containsKey('board_id'), isFalse);
  });

  test('H1 through H6 and Paragraph survive a storage restart', () {
    final directory = Directory.systemTemp.createTempSync('wave3_rt_restart_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final storage = RichTextStorage(directory);
    const original = RichTextDocument(blocks: [
      RichTextBlock(type: BlockType.heading, text: '一级', attrs: {'level': 1}),
      RichTextBlock(type: BlockType.heading, text: '六级', attrs: {'level': 6}),
      RichTextBlock(type: BlockType.paragraph, text: '正文'),
    ]);

    storage.saveSync('restart-card', original);
    final restored = storage.loadSync('restart-card');

    expect(restored, isNotNull);
    expect(restored!.blocks[0].headingLevel, 1);
    expect(restored.blocks[1].headingLevel, 6);
    expect(restored.blocks[2].type, BlockType.paragraph);
  });
}
