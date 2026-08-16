/// Tests for the searchable plain-text projection: after a document is
/// saved, `RichTextSearchIndex` matches the query against `toPlainText()`
/// (including list markers, quote prefixes and media alt/caption), survives
/// schema migration, and returns deterministic hits.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_search.dart';
import 'package:memex/domain/whiteboard/rich_text_storage.dart';

void main() {
  late Directory baseDir;
  late RichTextStorage storage;
  late RichTextSearchIndex index;

  setUp(() {
    baseDir = Directory.systemTemp.createTempSync('search_test_');
    storage = RichTextStorage(baseDir);
    index = RichTextSearchIndex(baseDir);
  });

  tearDown(() {
    if (baseDir.existsSync()) baseDir.deleteSync(recursive: true);
  });

  test('saved document text is searchable immediately', () async {
    storage.saveSync('card_1', const RichTextDocument(blocks: [
      RichTextBlock(type: BlockType.heading, text: '夏日散步', attrs: {'level': 1}),
      RichTextBlock(type: BlockType.paragraph, text: '傍晚沿着河边走了一小时'),
    ]));
    final hits = index.search('河边');
    expect(hits.length, equals(1));
    expect(hits.first.cardId, equals('card_1'));
  });

  test('search matches list items and quote prefixes via the projection',
      () async {
    storage.saveSync('card_plan', const RichTextDocument(blocks: [
      RichTextBlock(type: BlockType.paragraph, text: '周末计划'),
      RichTextBlock(
        type: BlockType.list,
        text: '买牛奶',
        attrs: {'ordered': false},
      ),
      RichTextBlock(
        type: BlockType.quote,
        text: '记一句名言：行动胜于言辞',
      ),
    ]));
    // List item text.
    final byList = index.search('牛奶');
    expect(byList.length, equals(1));
    // Quote content text.
    final byQuote = index.search('行动胜于言辞');
    expect(byQuote.length, equals(1));
    expect(byQuote.first.plainText, contains('> 记一句名言'));
  });

  test('search matches media alt/caption text', () async {
    storage.saveSync('card_media', const RichTextDocument(blocks: [
      RichTextBlock(
        type: BlockType.image,
        attrs: {'alt': '晚霞照片', 'asset_ref_id': 'ref_1'},
      ),
    ]));
    final hits = index.search('晚霞');
    expect(hits.length, equals(1));
    expect(hits.first.plainText, contains('晚霞照片'));
  });

  test('search is case-insensitive for latin text', () async {
    storage.saveSync('card_en', const RichTextDocument(blocks: [
      RichTextBlock(type: BlockType.paragraph, text: 'Cascadia Code 混排'),
    ]));
    expect((index.search('cascadia')).length, equals(1));
    expect((index.search('CASCADIA')).length, equals(1));
  });

  test('old v0 schema documents are migrated before search', () async {
    // Raw v0 file: plain string body.
    final dir = Directory(
        '${baseDir.path}${Platform.pathSeparator}card_old');
    dir.createSync(recursive: true);
    File('${dir.path}${Platform.pathSeparator}rich_text.json')
        .writeAsStringSync('{"schema_version": 0, "body": "旧卡片里的关键内容"}');
    final hits = index.search('关键内容');
    expect(hits.length, equals(1));
    expect(hits.first.cardId, equals('old'));
  });

  test('empty or whitespace query returns no hits', () async {
    storage.saveSync('card_1', const RichTextDocument(blocks: [
      RichTextBlock(type: BlockType.paragraph, text: '任意内容'),
    ]));
    expect(index.search(''), isEmpty);
    expect(index.search('   '), isEmpty);
  });

  test('no match returns empty list; hits are deterministic', () async {
    storage.saveSync('card_b', const RichTextDocument(blocks: [
      RichTextBlock(type: BlockType.paragraph, text: '内容乙'),
    ]));
    storage.saveSync('card_a', const RichTextDocument(blocks: [
      RichTextBlock(type: BlockType.paragraph, text: '内容甲'),
    ]));
    expect(index.search('不存在'), isEmpty);
    final hits = index.search('内容');
    expect(hits.length, equals(2));
    expect(hits[0].cardId, equals('card_a'));
    expect(hits[1].cardId, equals('card_b'));
  });

  test('plainTextOf returns the projection or null when absent', () async {
    storage.saveSync('card_1', const RichTextDocument(blocks: [
      RichTextBlock(type: BlockType.heading, text: '标题行'),
      RichTextBlock(type: BlockType.paragraph, text: '正文行'),
    ]));
    final text = index.plainTextOf('card_1');
    expect(text, contains('标题行'));
    expect(text, contains('正文行'));
    expect(index.plainTextOf('card_missing'), isNull);
  });

  test('search hit title is the first non-empty projected line', () async {
    storage.saveSync('card_t', const RichTextDocument(blocks: [
      RichTextBlock(type: BlockType.paragraph, text: ''),
      RichTextBlock(type: BlockType.heading, text: '标题在此', attrs: {'level': 1}),
    ]));
    final hits = index.search('标题在此');
    expect(hits.first.title, equals('标题在此'));
  });
}
