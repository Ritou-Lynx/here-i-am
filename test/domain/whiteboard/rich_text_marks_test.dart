import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_marks.dart';

void main() {
  group('applyMark', () {
    test('adds a bold mark', () {
      const block = RichTextBlock(type: BlockType.paragraph, text: 'hello');
      final result = applyMark(block, MarkType.bold, 0, 3);
      expect(result.marks.length, equals(1));
      expect(result.marks.first.type, equals(MarkType.bold));
      expect(result.marks.first.start, equals(0));
      expect(result.marks.first.end, equals(3));
    });

    test('merges overlapping same-type marks', () {
      const block = RichTextBlock(
        type: BlockType.paragraph,
        text: 'hello world',
        marks: [RichTextMark(type: MarkType.bold, start: 0, end: 3)],
      );
      final result = applyMark(block, MarkType.bold, 2, 6);
      expect(result.marks.length, equals(1));
      expect(result.marks.first.start, equals(0));
      expect(result.marks.first.end, equals(6));
    });

    test('clamps to text length', () {
      const block = RichTextBlock(type: BlockType.paragraph, text: 'abc');
      final result = applyMark(block, MarkType.italic, 0, 100);
      expect(result.marks.first.end, equals(3));
    });
  });

  group('removeMark', () {
    test('removes a mark entirely', () {
      const block = RichTextBlock(
        type: BlockType.paragraph,
        text: 'hello',
        marks: [RichTextMark(type: MarkType.bold, start: 0, end: 5)],
      );
      final result = removeMark(block, MarkType.bold, 0, 5);
      expect(result.marks, isEmpty);
    });

    test('splits a mark when removing a subrange', () {
      const block = RichTextBlock(
        type: BlockType.paragraph,
        text: 'hello world',
        marks: [RichTextMark(type: MarkType.bold, start: 0, end: 11)],
      );
      final result = removeMark(block, MarkType.bold, 3, 7);
      expect(result.marks.length, equals(2));
      expect(result.marks[0].start, equals(0));
      expect(result.marks[0].end, equals(3));
      expect(result.marks[1].start, equals(7));
      expect(result.marks[1].end, equals(11));
    });
  });

  group('toggleMark', () {
    test('applies when not present', () {
      const block = RichTextBlock(type: BlockType.paragraph, text: 'text');
      final result = toggleMark(block, MarkType.bold, 0, 4);
      expect(hasMark(result, MarkType.bold, 0, 4), isTrue);
    });

    test('removes when present over full range', () {
      const block = RichTextBlock(
        type: BlockType.paragraph,
        text: 'text',
        marks: [RichTextMark(type: MarkType.bold, start: 0, end: 4)],
      );
      final result = toggleMark(block, MarkType.bold, 0, 4);
      expect(hasMark(result, MarkType.bold, 0, 4), isFalse);
    });
  });

  group('hasMark', () {
    test('returns false for partial coverage', () {
      const block = RichTextBlock(
        type: BlockType.paragraph,
        text: 'hello',
        marks: [RichTextMark(type: MarkType.bold, start: 0, end: 3)],
      );
      expect(hasMark(block, MarkType.bold, 0, 5), isFalse);
      expect(hasMark(block, MarkType.bold, 0, 3), isTrue);
    });
  });
}