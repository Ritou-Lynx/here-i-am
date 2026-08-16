/// Tests for quote children editing: insert / delete / type change / marks
/// on nested child blocks, flush round-trips, undo/redo, and the plain-text
/// projection with `> ` prefixes.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/rich_text_controller.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';

void main() {
  group('quote children editing', () {
    test('insertChildAfter appends a child and focuses its own controller',
        () {
      final c = RichTextEditingController(const RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.quote, text: '引用'),
      ]));
      expect(c.childCount(0), equals(0));

      final idx = c.insertChildAfter(
          0, -1, const RichTextBlock(type: BlockType.paragraph, text: '子段'));
      expect(idx, equals(0));
      expect(c.childCount(0), equals(1));
      expect(c.childBlockAt(0, 0).text, equals('子段'));

      // The child has its own controller with the text.
      expect(c.childControllerFor(0, 0).text, equals('子段'));
    });

    test('typed child text is read back by flushToDocument', () {
      final c = RichTextEditingController(const RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.quote, text: '引用'),
      ]));
      c.insertChildAfter(
          0, -1, const RichTextBlock(type: BlockType.paragraph));
      c.childControllerFor(0, 0).text = '引用里写的内容';
      final doc = c.flushToDocument();
      expect(doc.blocks.first.children.first.text, equals('引用里写的内容'));
    });

    test('quote children survive save → load → edit → save round-trip', () {
      const doc = RichTextDocument(blocks: [
        RichTextBlock(
          type: BlockType.quote,
          text: '引言',
          children: [
            RichTextBlock(type: BlockType.paragraph, text: '子段 A'),
            RichTextBlock(type: BlockType.paragraph, text: '子段 B'),
          ],
        ),
      ]);
      final json = doc.toJson();
      final restored = RichTextDocument.fromJson(json);
      expect(restored.blocks.first.children.length, equals(2));
      expect(restored.blocks.first.children[1].text, equals('子段 B'));

      // Continue editing the restored document.
      final c = RichTextEditingController(restored);
      final idx = c.insertChildAfter(
          0, 1, const RichTextBlock(type: BlockType.paragraph, text: '子段 C'));
      expect(idx, equals(2));
      expect(c.childBlockAt(0, 2).text, equals('子段 C'));
    });

    test('deleteChild removes a child and supports undo', () {
      final c = RichTextEditingController(const RichTextDocument(blocks: [
        RichTextBlock(
          type: BlockType.quote,
          text: '引用',
          children: [
            RichTextBlock(type: BlockType.paragraph, text: 'A'),
            RichTextBlock(type: BlockType.paragraph, text: 'B'),
          ],
        ),
      ]));
      c.deleteChild(0, 0);
      expect(c.childCount(0), equals(1));
      expect(c.childBlockAt(0, 0).text, equals('B'));

      c.undo();
      expect(c.childCount(0), equals(2));
      expect(c.childBlockAt(0, 0).text, equals('A'));
    });

    test('setChildBlockType changes the child block type', () {
      final c = RichTextEditingController(const RichTextDocument(blocks: [
        RichTextBlock(
          type: BlockType.quote,
          text: '引用',
          children: [RichTextBlock(type: BlockType.paragraph, text: '列表')],
        ),
      ]));
      c.setChildBlockType(
          0, 0, BlockType.list,
          attrs: const {'ordered': false, 'depth': 1});
      final child = c.childBlockAt(0, 0);
      expect(child.type, equals(BlockType.list));
      expect(child.listDepth, equals(1));
    });

    test('applyMarkToChild marks a range in the child text', () {
      final c = RichTextEditingController(const RichTextDocument(blocks: [
        RichTextBlock(
          type: BlockType.quote,
          text: '引用',
          children: [RichTextBlock(type: BlockType.paragraph, text: '加粗文字')],
        ),
      ]));
      c.applyMarkToChild(0, 0, MarkType.bold, 0, 2);
      final marks = c.childBlockAt(0, 0).marks;
      expect(marks.length, equals(1));
      expect(marks.first.type, equals(MarkType.bold));
      expect(marks.first.start, equals(0));
      expect(marks.first.end, equals(2));
    });

    test('undo/redo across child edits restores the whole tree', () {
      final c = RichTextEditingController(const RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.quote, text: '引用'),
      ]));
      c.insertChildAfter(
          0, -1, const RichTextBlock(type: BlockType.paragraph, text: '一'));
      c.insertChildAfter(
          0, 0, const RichTextBlock(type: BlockType.paragraph, text: '二'));
      expect(c.childCount(0), equals(2));

      // Rapid consecutive edits coalesce into one undo step (800ms window),
      // so a single undo returns to the pre-edit state.
      c.undo();
      expect(c.childCount(0), equals(0));
      expect(c.canUndo, isFalse);

      c.redo();
      expect(c.childCount(0), equals(2));
      expect(c.childBlockAt(0, 0).text, equals('一'));
      expect(c.childBlockAt(0, 1).text, equals('二'));
    });
  });

  group('quote projection', () {
    test('quote children project with continued > prefix', () {
      const doc = RichTextDocument(blocks: [
        RichTextBlock(
          type: BlockType.quote,
          text: '引言',
          children: [
            RichTextBlock(type: BlockType.paragraph, text: '第一段'),
            RichTextBlock(type: BlockType.paragraph, text: '第二段'),
          ],
        ),
      ]);
      final text = doc.toPlainText();
      expect(text, contains('> 引言'));
      expect(text, contains('> 第一段'));
      expect(text, contains('> 第二段'));
    });
  });
}
