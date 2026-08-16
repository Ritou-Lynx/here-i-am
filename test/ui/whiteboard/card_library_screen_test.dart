/// Widget tests for the card library search screen: querying the plain-text
/// projection of saved rich text documents, empty / no-match states, and
/// opening the editor for a hit.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_search.dart';
import 'package:memex/domain/whiteboard/rich_text_storage.dart';
import 'package:memex/ui/whiteboard/card_library_screen.dart';

void main() {
  late Directory baseDir;
  late RichTextStorage storage;
  late RichTextSearchIndex index;

  setUp(() {
    baseDir = Directory.systemTemp.createTempSync('card_library_test_');
    storage = RichTextStorage(baseDir);
    index = RichTextSearchIndex(baseDir);
  });

  tearDown(() {
    if (baseDir.existsSync()) baseDir.deleteSync(recursive: true);
  });

  Future<void> pumpLibrary(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CardLibraryScreen(index: index),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
  }

  testWidgets('empty query shows the search hint', (tester) async {
    await pumpLibrary(tester);
    expect(find.text('输入关键词搜索卡片内容'), findsOneWidget);
  });

  testWidgets('query finds matching cards by plain-text projection',
      (tester) async {
    storage.saveSync('card_a', const RichTextDocument(blocks: [
      RichTextBlock(type: BlockType.heading, text: '河边散步', attrs: {'level': 1}),
    ]));
    storage.saveSync('card_b', const RichTextDocument(blocks: [
      RichTextBlock(type: BlockType.paragraph, text: '读书笔记'),
    ]));

    await pumpLibrary(tester);
    await tester.enterText(find.byType(TextField), '河边');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('河边散步'), findsWidgets);
    expect(find.text('读书笔记'), findsNothing);
  });

  testWidgets('search matches text inside quote children and list items',
      (tester) async {
    storage.saveSync('card_q', const RichTextDocument(blocks: [
      RichTextBlock(
        type: BlockType.quote,
        text: '引言',
        children: [RichTextBlock(type: BlockType.paragraph, text: '引用里的关键词')],
      ),
    ]));
    storage.saveSync('card_l', const RichTextDocument(blocks: [
      RichTextBlock(
        type: BlockType.list,
        text: '列表关键词项',
        attrs: {'ordered': false, 'depth': 1},
      ),
    ]));

    await pumpLibrary(tester);
    await tester.enterText(find.byType(TextField), '关键词');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.textContaining('引用里的关键词'), findsWidgets);
    expect(find.textContaining('列表关键词项'), findsWidgets);
  });

  testWidgets('no match shows the empty state', (tester) async {
    storage.saveSync('card_a', const RichTextDocument(blocks: [
      RichTextBlock(type: BlockType.paragraph, text: '唯一内容'),
    ]));
    await pumpLibrary(tester);
    await tester.enterText(find.byType(TextField), '找不到的东西');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('没有匹配的卡片'), findsOneWidget);
  });

  testWidgets('clearing the query returns to the hint state', (tester) async {
    storage.saveSync('card_a', const RichTextDocument(blocks: [
      RichTextBlock(type: BlockType.paragraph, text: '内容'),
    ]));
    await pumpLibrary(tester);
    await tester.enterText(find.byType(TextField), '内容');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('内容'), findsWidgets);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('输入关键词搜索卡片内容'), findsOneWidget);
  });
}
