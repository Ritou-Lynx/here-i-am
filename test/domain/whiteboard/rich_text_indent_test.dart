/// Tests for list nesting (Tab / Shift-Tab) via the editing controller:
/// indent / outdent adjust the `depth` attr, clamp at 0–8, only affect list
/// blocks, and are undoable history steps.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/rich_text_controller.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';

void main() {
  RichTextEditingController controllerWith(List<RichTextBlock> blocks) =>
      RichTextEditingController(RichTextDocument(blocks: blocks));

  group('indent / outdent (Tab / Shift-Tab)', () {
    test('Tab indents a list block (depth 0 → 1)', () {
      final c = controllerWith(const [
        RichTextBlock(
          type: BlockType.list,
          text: '项',
          attrs: {'ordered': false},
        ),
      ]);
      final depth = c.indentListBlock(0);
      expect(depth, equals(1));
      expect(c.blockAt(0).listDepth, equals(1));
      expect(c.flushToDocument().blocks.first.attrs['depth'], equals(1));
    });

    test('Shift-Tab outdents a list block (depth 2 → 1)', () {
      final c = controllerWith(const [
        RichTextBlock(
          type: BlockType.list,
          text: '项',
          attrs: {'ordered': false, 'depth': 2},
        ),
      ]);
      final depth = c.outdentListBlock(0);
      expect(depth, equals(1));
      expect(c.blockAt(0).listDepth, equals(1));
    });

    test('depth clamps at 0 on outdent', () {
      final c = controllerWith(const [
        RichTextBlock(type: BlockType.list, text: '项'),
      ]);
      expect(c.outdentListBlock(0), isNull);
      expect(c.blockAt(0).listDepth, equals(0));
    });

    test('depth clamps at 8 on indent', () {
      final c = controllerWith(const [
        RichTextBlock(
          type: BlockType.list,
          text: '项',
          attrs: {'depth': 8},
        ),
      ]);
      expect(c.indentListBlock(0), isNull);
      expect(c.blockAt(0).listDepth, equals(8));
    });

    test('indent is a no-op for non-list blocks', () {
      final c = controllerWith(const [
        RichTextBlock(type: BlockType.paragraph, text: '正文'),
      ]);
      expect(c.indentListBlock(0), isNull);
      expect(c.outdentListBlock(0), isNull);
    });

    test('indent targets a nested child list when childIndex is given', () {
      final c = controllerWith(const [
        RichTextBlock(
          type: BlockType.quote,
          text: '引用',
          children: [
            RichTextBlock(type: BlockType.list, text: '引用内列表'),
          ],
        ),
      ]);
      final depth = c.indentListBlock(0, childIndex: 0);
      expect(depth, equals(1));
      expect(c.childBlockAt(0, 0).listDepth, equals(1));
      expect(c.flushToDocument().blocks.first.children.first.listDepth,
          equals(1));
    });

    test('indent keeps ordered marker and is undoable', () {
      final c = controllerWith(const [
        RichTextBlock(
          type: BlockType.list,
          text: '第一',
          attrs: {'ordered': true},
        ),
      ]);
      c.indentListBlock(0);
      expect(c.blockAt(0).listOrdered, isTrue);
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.blockAt(0).listDepth, equals(0));
    });
  });

  group('plain text projection honors list depth', () {
    test('depth-2 list item projects with four-space indent', () {
      const doc = RichTextDocument(blocks: [
        RichTextBlock(
          type: BlockType.list,
          text: '深层项',
          attrs: {'ordered': false, 'depth': 2},
        ),
      ]);
      final text = doc.toPlainText();
      expect(text, contains('    - 深层项'));
    });

    test('ordered depth-1 item keeps running number and indent', () {
      const doc = RichTextDocument(blocks: [
        RichTextBlock(
          type: BlockType.list,
          text: '乙',
          attrs: {'ordered': true, 'depth': 1},
        ),
      ]);
      final text = doc.toPlainText();
      expect(text, contains('  1. 乙'));
    });
  });
}
