import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_asset_ref.dart';
import 'package:memex/domain/whiteboard/rich_text_migration.dart';

Map<String, dynamic> loadRichTextFixture(String filename) {
  final path = 'test/domain/whiteboard/fixtures/$filename';
  return jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  group('RichTextDocument schema v2', () {
    test('empty document has one empty paragraph', () {
      final doc = RichTextDocument.empty();
      expect(doc.blocks.length, equals(1));
      expect(doc.blocks.first.type, equals(BlockType.paragraph));
      expect(doc.blocks.first.text, isEmpty);
    });

    test('round-trips blocks, marks, attrs, and asset refs', () {
      const doc = RichTextDocument(
        blocks: [
          RichTextBlock(
            type: BlockType.heading,
            text: '标题',
            attrs: {'level': 2},
          ),
          RichTextBlock(
            type: BlockType.paragraph,
            text: 'Hello 世界',
            marks: [
              RichTextMark(type: MarkType.bold, start: 0, end: 5),
              RichTextMark(
                type: MarkType.link,
                start: 6,
                end: 8,
                attrs: {'href': 'https://example.com'},
              ),
            ],
          ),
          RichTextBlock(
            type: BlockType.list,
            text: '第一项',
            attrs: {'ordered': true, 'depth': 0},
            children: [
              RichTextBlock(type: BlockType.list, text: '嵌套项', attrs: {'ordered': false, 'depth': 1}),
            ],
          ),
          RichTextBlock(type: BlockType.quote, text: '引用'),
          RichTextBlock(
            type: BlockType.code,
            text: 'var x = 1;',
            attrs: {'language': 'dart'},
          ),
          RichTextBlock(
            type: BlockType.image,
            attrs: {
              'asset_ref_id': 'ref_img_1',
              'alt': '示意图',
              'caption': '图 1',
            },
          ),
        ],
        assetRefs: [
          RichTextAssetRef(
            refId: 'ref_img_1',
            objectRef: 'objects/sha256:img1',
            mimeType: 'image/png',
            width: 800,
            height: 600,
            alt: '示意图',
          ),
        ],
      );
      final json = doc.toJson();
      final encoded = jsonEncode(json);
      final restored = RichTextDocument.fromJson(jsonDecode(encoded) as Map<String, dynamic>);

      expect(restored.schemaVersion, equals(richTextSchemaVersion));
      expect(restored.blocks.length, equals(6));
      expect(restored.blocks[0].type, equals(BlockType.heading));
      expect(restored.blocks[0].headingLevel, equals(2));
      expect(restored.blocks[1].marks.length, equals(2));
      expect(restored.blocks[1].marks[1].type, equals(MarkType.link));
      expect(restored.blocks[1].marks[1].attrs['href'], equals('https://example.com'));
      expect(restored.blocks[2].listOrdered, isTrue);
      expect(restored.blocks[2].children.length, equals(1));
      expect(restored.blocks[2].children.first.listDepth, equals(1));
      expect(restored.blocks[4].codeLanguage, equals('dart'));
      expect(restored.blocks[5].assetRefId, equals('ref_img_1'));
      expect(restored.assetRefs.length, equals(1));
      expect(restored.assetRefs.first.width, equals(800));
      expect(restored.assetRefById('ref_img_1')?.mimeType, equals('image/png'));
    });

    test('plain text projection handles all block types', () {
      const doc = RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.heading, text: '标题', attrs: {'level': 1}),
        RichTextBlock(type: BlockType.paragraph, text: '正文'),
        RichTextBlock(type: BlockType.list, text: '项 A', attrs: {'ordered': false}),
        RichTextBlock(type: BlockType.list, text: '项 B', attrs: {'ordered': true}),
        RichTextBlock(type: BlockType.quote, text: '引用文字'),
        RichTextBlock(type: BlockType.code, text: 'print(1)'),
        RichTextBlock(type: BlockType.image, attrs: {'caption': '图说明'}),
      ]);
      final text = doc.toPlainText();
      expect(text, contains('标题'));
      expect(text, contains('正文'));
      expect(text, contains('- 项 A'));
      expect(text, contains('1. 项 B'));
      expect(text, contains('> 引用文字'));
      expect(text, contains('print(1)'));
      expect(text, contains('图说明'));
    });

    test('plain text projection for nested lists', () {
      const doc = RichTextDocument(blocks: [
        RichTextBlock(
          type: BlockType.list,
          text: '外层',
          attrs: {'ordered': false},
          children: [
            RichTextBlock(type: BlockType.list, text: '内层', attrs: {'ordered': false, 'depth': 1}),
          ],
        ),
      ]);
      final text = doc.toPlainText();
      expect(text, contains('- 外层'));
      expect(text, contains('  - 内层'));
    });

    test('image block without caption uses alt text', () {
      const doc = RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.image, attrs: {'alt': '替代文字'}),
      ]);
      expect(doc.toPlainText(), contains('替代文字'));
    });

    test('empty blocks list still serializes schema_version', () {
      const doc = RichTextDocument();
      final json = doc.toJson();
      expect(json['schema_version'], equals(richTextSchemaVersion));
      expect(json.containsKey('blocks'), isFalse);
    });
  });

  group('RichTextMark shift and clamp', () {
    test('shift moves start and end', () {
      const mark = RichTextMark(type: MarkType.bold, start: 5, end: 10);
      final shifted = mark.shift(3);
      expect(shifted.start, equals(8));
      expect(shifted.end, equals(13));
    });

    test('clamp drops collapsed marks', () {
      const mark = RichTextMark(type: MarkType.bold, start: 8, end: 12);
      expect(mark.clamp(5), isNull);
    });

    test('clamp clamps to text length', () {
      const mark = RichTextMark(type: MarkType.bold, start: 3, end: 12);
      final clamped = mark.clamp(5);
      expect(clamped!.start, equals(3));
      expect(clamped.end, equals(5));
    });
  });

  group('Backward compatibility — old schema migration', () {
    test('v0 plain string body migrates to paragraphs', () {
      final migrated = migrateRichTextDocument({
        'schema_version': 0,
        'body': '第一行\n第二行\n第三行',
      });
      expect(migrated.schemaVersion, equals(richTextSchemaVersion));
      expect(migrated.blocks.length, equals(3));
      expect(migrated.blocks[0].text, equals('第一行'));
      expect(migrated.blocks[1].text, equals('第二行'));
      expect(migrated.blocks[2].text, equals('第三行'));
    });

    test('v0 empty body degrades to empty document', () {
      final migrated = migrateRichTextDocument({'schema_version': 0});
      expect(migrated.blocks.length, equals(1));
      expect(migrated.blocks.first.text, isEmpty);
    });

    test('v1 blocks migrate to v2 with marks preserved', () {
      final v1 = {
        'schema_version': 1,
        'blocks': [
          {
            'type': 'paragraph',
            'text': '旧版文字',
            'marks': [
              {'type': 'bold', 'start': 0, 'end': 2},
            ],
          },
        ],
      };
      final migrated = migrateRichTextDocument(v1);
      expect(migrated.schemaVersion, equals(richTextSchemaVersion));
      expect(migrated.blocks.length, equals(1));
      expect(migrated.blocks.first.text, equals('旧版文字'));
      expect(migrated.blocks.first.marks.length, equals(1));
      expect(migrated.blocks.first.marks.first.type, equals(MarkType.bold));
    });

    test('corrupt JSON degrades to empty document', () {
      final migrated = migrateRichTextDocument({
        'schema_version': 99,
        'blocks': 'not a list',
      });
      expect(migrated.blocks.length, equals(1));
      expect(migrated.blocks.first.type, equals(BlockType.paragraph));
    });

    test('marks clamped to text length during migration', () {
      final migrated = migrateRichTextDocument({
        'schema_version': 1,
        'blocks': [
          {
            'type': 'paragraph',
            'text': '短',
            'marks': [
              {'type': 'bold', 'start': 0, 'end': 100},
            ],
          },
        ],
      });
      expect(migrated.blocks.first.marks.first.end, equals(1));
    });

    test('migration is idempotent on current schema', () {
      const doc = RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: 'abc'),
      ]);
      final json = doc.toJson();
      final migrated = migrateRichTextDocument(json);
      expect(migrated.schemaVersion, equals(richTextSchemaVersion));
      expect(migrated.blocks.first.text, equals('abc'));
    });

    test('fixture: v0 plain body migrates to paragraphs', () {
      final raw = loadRichTextFixture('rich_text_v0_plain_body.json');
      expect(raw['schema_version'], equals(0));
      final migrated = migrateRichTextDocument(raw);
      expect(migrated.schemaVersion, equals(richTextSchemaVersion));
      // "line1\nline2\n\nline3" splits into 4 paragraphs, the empty line
      // between becoming an empty paragraph (preserving vertical space).
      expect(migrated.blocks.length, equals(4));
      expect(migrated.blocks[0].text, equals('这是旧版纯文本卡片正文'));
      expect(migrated.blocks[1].text, equals('第二行内容'));
      expect(migrated.blocks[2].text, isEmpty);
      expect(migrated.blocks[3].text, equals('第三段，中间有空行'));
    });

    test('fixture: v1 W0 shell migrates preserving marks and attrs', () {
      final raw = loadRichTextFixture('rich_text_v1_w0_shell.json');
      expect(raw['schema_version'], equals(1));
      final migrated = migrateRichTextDocument(raw);
      expect(migrated.schemaVersion, equals(richTextSchemaVersion));
      expect(migrated.blocks.length, equals(2));
      expect(migrated.blocks[0].type, equals(BlockType.heading));
      expect(migrated.blocks[0].headingLevel, equals(2));
      expect(migrated.blocks[1].marks.first.type, equals(MarkType.bold));
      expect(migrated.blocks[1].marks.first.start, equals(6));
      expect(migrated.blocks[1].marks.first.end, equals(8));
    });
  });

  group('Asset references', () {
    test('asset ref round-trips', () {
      const ref = RichTextAssetRef(
        refId: 'ref_1',
        objectRef: 'objects/sha256:abc',
        mimeType: 'image/jpeg',
        width: 1024,
        height: 768,
        alt: '封面',
      );
      final json = ref.toJson();
      final restored = RichTextAssetRef.fromJson(json);
      expect(restored.refId, equals('ref_1'));
      expect(restored.objectRef, equals('objects/sha256:abc'));
      expect(restored.mimeType, equals('image/jpeg'));
      expect(restored.width, equals(1024));
      expect(restored.alt, equals('封面'));
    });

    test('asset ref defaults mime type on fromJson', () {
      final ref = RichTextAssetRef.fromJson({'ref_id': 'r', 'object_ref': 'o'});
      expect(ref.mimeType, equals('application/octet-stream'));
    });
  });
}