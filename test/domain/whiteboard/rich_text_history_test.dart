import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_history.dart';

void main() {
  group('RichTextDocumentHistory', () {
    test('commit and undo', () {
      final h = RichTextDocumentHistory(
        const RichTextDocument(blocks: [RichTextBlock(type: BlockType.paragraph, text: 'v0')]),
      );
      h.commit(const RichTextDocument(
        blocks: [RichTextBlock(type: BlockType.paragraph, text: 'v1')],
      ));
      expect(h.current.blocks.first.text, equals('v1'));
      expect(h.canUndo, isTrue);

      final undone = h.undo();
      expect(undone!.blocks.first.text, equals('v0'));
      expect(h.canRedo, isTrue);
    });

    test('redo after undo', () {
      final h = RichTextDocumentHistory(
        const RichTextDocument(blocks: [RichTextBlock(type: BlockType.paragraph, text: 'a')]),
      );
      h.commit(const RichTextDocument(
        blocks: [RichTextBlock(type: BlockType.paragraph, text: 'b')],
      ));
      h.undo();
      final redone = h.redo();
      expect(redone!.blocks.first.text, equals('b'));
      expect(h.canRedo, isFalse);
    });

    test('commit clears redo stack', () {
      final h = RichTextDocumentHistory(
        const RichTextDocument(blocks: [RichTextBlock(type: BlockType.paragraph, text: 'a')]),
      );
      h.commit(const RichTextDocument(
        blocks: [RichTextBlock(type: BlockType.paragraph, text: 'b')],
      ));
      h.undo();
      expect(h.canRedo, isTrue);
      h.commit(const RichTextDocument(
        blocks: [RichTextBlock(type: BlockType.paragraph, text: 'c')],
      ));
      expect(h.canRedo, isFalse);
    });

    test('undo on empty history returns null', () {
      final h = RichTextDocumentHistory(
        const RichTextDocument(blocks: [RichTextBlock(type: BlockType.paragraph, text: 'x')]),
      );
      expect(h.undo(), isNull);
      expect(h.redo(), isNull);
    });

    test('coalesce merges rapid commits', () {
      final h = RichTextDocumentHistory(
        const RichTextDocument(blocks: [RichTextBlock(type: BlockType.paragraph, text: 'start')]),
        coalesceWindow: const Duration(milliseconds: 500),
      );
      // Three rapid commits within the window.
      h.commit(const RichTextDocument(
        blocks: [RichTextBlock(type: BlockType.paragraph, text: 'a')],
      ));
      h.commit(const RichTextDocument(
        blocks: [RichTextBlock(type: BlockType.paragraph, text: 'ab')],
      ));
      h.commit(const RichTextDocument(
        blocks: [RichTextBlock(type: BlockType.paragraph, text: 'abc')],
      ));
      // One undo should go back to 'start' (coalesced).
      final undone = h.undo();
      expect(undone!.blocks.first.text, equals('start'));
    });

    test('identical explicit checkpoint does not create a no-op undo', () {
      const initial = RichTextDocument(
        blocks: [RichTextBlock(type: BlockType.paragraph, text: '初始')],
      );
      const edited = RichTextDocument(
        blocks: [RichTextBlock(type: BlockType.paragraph, text: '编辑后')],
      );
      const second = RichTextDocument(
        blocks: [RichTextBlock(type: BlockType.paragraph, text: '第二版')],
      );
      final h = RichTextDocumentHistory(initial);

      h.commit(edited);
      h.commit(edited, coalesce: false);
      h.commit(second);

      expect(h.undo()!.blocks.single.text, '编辑后');
      expect(h.undo()!.blocks.single.text, '初始');
      expect(h.undo(), isNull);
      expect(h.redo()!.blocks.single.text, '编辑后');
      expect(h.redo()!.blocks.single.text, '第二版');
    });

    test('reset clears stacks', () {
      final h = RichTextDocumentHistory(
        const RichTextDocument(blocks: [RichTextBlock(type: BlockType.paragraph, text: 'a')]),
      );
      h.commit(const RichTextDocument(
        blocks: [RichTextBlock(type: BlockType.paragraph, text: 'b')],
      ));
      h.reset(const RichTextDocument(
        blocks: [RichTextBlock(type: BlockType.paragraph, text: 'fresh')],
      ));
      expect(h.canUndo, isFalse);
      expect(h.canRedo, isFalse);
      expect(h.current.blocks.first.text, equals('fresh'));
    });
  });
}
