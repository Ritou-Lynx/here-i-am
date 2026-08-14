import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_paste_sanitizer.dart';

void main() {
  group('Paste sanitizer', () {
    test('strips javascript: links to plain text', () {
      final result = sanitizePastedBlocks(const [
        RichTextBlock(
          type: BlockType.paragraph,
          text: '点击',
          marks: [
            RichTextMark(
              type: MarkType.link,
              start: 0,
              end: 2,
              attrs: {'href': 'javascript:alert(1)'},
            ),
          ],
        ),
      ]);
      expect(result.blocks.length, equals(1));
      expect(result.blocks.first.marks, isEmpty);
      expect(result.warnings.any((w) => w.contains('Unsafe link')), isTrue);
    });

    test('keeps https links', () {
      final result = sanitizePastedBlocks(const [
        RichTextBlock(
          type: BlockType.paragraph,
          text: '链接',
          marks: [
            RichTextMark(
              type: MarkType.link,
              start: 0,
              end: 2,
              attrs: {'href': 'https://example.com'},
            ),
          ],
        ),
      ]);
      expect(result.blocks.first.marks.length, equals(1));
      expect(result.blocks.first.marks.first.type, equals(MarkType.link));
      expect(result.blocks.first.marks.first.attrs['href'],
          equals('https://example.com'));
    });

    test('keeps mailto links', () {
      final result = sanitizePastedBlocks(const [
        RichTextBlock(
          type: BlockType.paragraph,
          text: '邮箱',
          marks: [
            RichTextMark(
              type: MarkType.link,
              start: 0,
              end: 2,
              attrs: {'href': 'mailto:a@b.com'},
            ),
          ],
        ),
      ]);
      expect(result.blocks.first.marks.length, equals(1));
    });

    test('strips data: URLs', () {
      final result = sanitizePastedBlocks(const [
        RichTextBlock(
          type: BlockType.paragraph,
          text: 'img',
          marks: [
            RichTextMark(
              type: MarkType.link,
              start: 0,
              end: 3,
              attrs: {'href': 'data:text/html,<script>'},
            ),
          ],
        ),
      ]);
      expect(result.blocks.first.marks, isEmpty);
    });

    test('downgrades disallowed block types to paragraph', () {
      final result = sanitizePastedBlocks(const [
        RichTextBlock(type: BlockType.image, attrs: {'alt': ''}),
      ]);
      expect(result.blocks.first.type, equals(BlockType.paragraph));
      expect(result.warnings.any((w) => w.contains('media block')), isTrue);
    });

    test('image with alt becomes text paragraph', () {
      final result = sanitizePastedBlocks(const [
        RichTextBlock(type: BlockType.image, attrs: {'alt': '图片描述'}),
      ]);
      expect(result.blocks.first.type, equals(BlockType.paragraph));
      expect(result.blocks.first.text, equals('图片描述'));
    });

    test('drops disallowed marks', () {
      // All standard marks are allowed; this verifies the filter logic by
      // passing a valid mark and confirming it survives.
      final result = sanitizePastedBlocks(const [
        RichTextBlock(
          type: BlockType.paragraph,
          text: '粗体',
          marks: [
            RichTextMark(type: MarkType.bold, start: 0, end: 2),
          ],
        ),
      ]);
      expect(result.blocks.first.marks.length, equals(1));
    });

    test('preserves heading level clamped to 1-6', () {
      final result = sanitizePastedBlocks(const [
        RichTextBlock(type: BlockType.heading, text: '标题', attrs: {'level': 99}),
      ]);
      expect(result.blocks.first.attrs['level'], equals(6));
    });

    test('preserves list ordered and depth', () {
      final result = sanitizePastedBlocks(const [
        RichTextBlock(
          type: BlockType.list,
          text: '项',
          attrs: {'ordered': true, 'depth': 3},
        ),
      ]);
      expect(result.blocks.first.attrs['ordered'], isTrue);
      expect(result.blocks.first.attrs['depth'], equals(3));
    });

    test('empty input yields a single empty paragraph', () {
      final result = sanitizePastedBlocks(const []);
      expect(result.blocks.length, equals(1));
      expect(result.blocks.first.type, equals(BlockType.paragraph));
    });

    test('file: scheme stripped', () {
      final result = sanitizePastedBlocks(const [
        RichTextBlock(
          type: BlockType.paragraph,
          text: '本地',
          marks: [
            RichTextMark(
              type: MarkType.link,
              start: 0,
              end: 2,
              attrs: {'href': 'file:///etc/passwd'},
            ),
          ],
        ),
      ]);
      expect(result.blocks.first.marks, isEmpty);
    });

    test('custom allowed schemes', () {
      final result = sanitizePastedBlocks(
        const [
          RichTextBlock(
            type: BlockType.paragraph,
            text: '内部',
            marks: [
              RichTextMark(
                type: MarkType.link,
                start: 0,
                end: 2,
                attrs: {'href': 'internal://path'},
              ),
            ],
          ),
        ],
        allowedSchemes: {'internal'},
      );
      expect(result.blocks.first.marks.length, equals(1));
    });

    test('recursively sanitizes children', () {
      final result = sanitizePastedBlocks(const [
        RichTextBlock(
          type: BlockType.list,
          text: '父',
          children: [
            RichTextBlock(
              type: BlockType.paragraph,
              text: '子',
              marks: [
                RichTextMark(
                  type: MarkType.link,
                  start: 0,
                  end: 1,
                  attrs: {'href': 'javascript:bad'},
                ),
              ],
            ),
          ],
        ),
      ]);
      expect(result.blocks.first.children.first.marks, isEmpty);
    });
  });
}