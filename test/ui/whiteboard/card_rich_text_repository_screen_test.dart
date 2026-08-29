import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_object_store.dart';
import 'package:memex/ui/whiteboard/card_rich_text_editor_screen.dart';
import 'package:memex/ui/whiteboard/editor/card_rich_text_editor_screen.dart'
    as editor;
import 'package:memex/ui/whiteboard/widgets/card_local_media_preview.dart';

void main() {
  late Directory root;
  late AppDatabase db;
  late UnifiedCardRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('f2_editor_repository_');
    db = AppDatabase.forTesting(NativeDatabase(
      File('${root.path}${Platform.pathSeparator}whiteboard.sqlite'),
    ));
    repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
  });

  tearDown(() async {
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('missing rich text retains the searchable Drift body projection',
      () async {
    await repository.createTextCard(
      cardId: 'missing_doc',
      title: '投影标题',
      body: '数据库里的恢复正文',
    );
    final record = await repository.getCard('missing_doc');
    expect(record!.documentState, CardDocumentState.missing);
    expect(record.card.body, '数据库里的恢复正文');
  });

  testWidgets(
      'plain card uses neutral notice and tag-only save does not materialize rich text',
      (tester) async {
    await tester.runAsync(() => repository.createTextCard(
          cardId: 'plain_tags',
          title: '白板新卡',
          body: '白板正文',
          tags: const ['old'],
        ));
    CardRichTextEditorScreen.setRepositoryForTesting(repository);
    addTearDown(
      () => CardRichTextEditorScreen.setRepositoryForTesting(null),
    );

    await tester.pumpWidget(const MaterialApp(
      home: CardRichTextEditorScreen(cardId: 'plain_tags'),
    ));
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('card-tag-input')),
    );

    final editorWidget = tester.widget<editor.CardRichTextEditorScreen>(
      find.byType(editor.CardRichTextEditorScreen),
    );
    expect(editorWidget.degradedMessage, contains('当前没有可用的富文本版本'));
    expect(editorWidget.degradedMessage, isNot(contains('缺失')));
    expect(editorWidget.degradedMessage, isNot(contains('恢复')));
    expect(
      find.byKey(const ValueKey('rich_text_degraded_notice')),
      findsOneWidget,
    );
    expect(repository.richTextStorage.exists('plain_tags'), isFalse);

    await tester.enterText(
      find.byKey(const ValueKey('card-tag-input')),
      'new',
    );
    await tester.tap(find.byKey(const ValueKey('card-tag-add')));
    await tester.tap(find.byKey(const ValueKey('rich_text_save_button')));
    await _pumpUntilFound(tester, find.text('已保存'));

    final stored = await tester.runAsync(
      () async => (await repository.getCard('plain_tags'))!,
    );
    expect(stored!.card.tags, ['old', 'new']);
    expect(stored.documentState, CardDocumentState.missing);
    expect(repository.richTextStorage.exists('plain_tags'), isFalse);
  });

  testWidgets(
      'first rich save materializes plain card and a later missing file warns honestly',
      (tester) async {
    await tester.runAsync(() => repository.createTextCard(
          cardId: 'plain_materialize',
          title: '白板新卡',
          body: '白板正文',
        ));
    CardRichTextEditorScreen.setRepositoryForTesting(repository);
    addTearDown(
      () => CardRichTextEditorScreen.setRepositoryForTesting(null),
    );

    Future<void> openEditor() async {
      await tester.pumpWidget(MaterialApp(
        home: CardRichTextEditorScreen(
          key: UniqueKey(),
          cardId: 'plain_materialize',
        ),
      ));
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('rich_text_continuous_document')),
      );
    }

    await openEditor();
    final initialNotice = tester.widget<editor.CardRichTextEditorScreen>(
      find.byType(editor.CardRichTextEditorScreen),
    );
    expect(initialNotice.degradedMessage, contains('当前没有可用的富文本版本'));
    expect(initialNotice.degradedMessage, isNot(contains('缺失')));
    expect(initialNotice.degradedMessage, isNot(contains('恢复')));
    await tester.enterText(
      find.byKey(const ValueKey('rich_text_continuous_document')),
      '首次富文本保存',
    );
    await tester.tap(find.byKey(const ValueKey('rich_text_save_button')));
    await _pumpUntilFound(tester, find.text('已保存'));
    expect(
      (await tester.runAsync(
        () async => (await repository.getCard('plain_materialize'))!,
      ))!
          .documentState,
      CardDocumentState.available,
    );

    await openEditor();
    expect(
      find.byKey(const ValueKey('rich_text_degraded_notice')),
      findsNothing,
    );
    final richFile = File(
      '${repository.richTextStorage.baseDir.path}${Platform.pathSeparator}'
      'card_plain_materialize${Platform.pathSeparator}rich_text.json',
    );
    await tester.runAsync(richFile.delete);

    await openEditor();
    final missing = await tester.runAsync(
      () async => (await repository.getCard('plain_materialize'))!,
    );
    expect(missing!.documentState, CardDocumentState.missing);
    expect(
      tester
          .widget<editor.CardRichTextEditorScreen>(
            find.byType(editor.CardRichTextEditorScreen),
          )
          .degradedMessage,
      contains('当前没有可用的富文本版本'),
    );
    final missingMessage = tester
        .widget<editor.CardRichTextEditorScreen>(
          find.byType(editor.CardRichTextEditorScreen),
        )
        .degradedMessage;
    expect(missingMessage, isNot(contains('缺失')));
    expect(missingMessage, isNot(contains('恢复')));
    expect(
      find.byKey(const ValueKey('rich_text_degraded_notice')),
      findsOneWidget,
    );
  });

  test('corrupt rich text is reported and saveRichText repairs it', () async {
    await repository.createTextCard(
      cardId: 'corrupt_doc',
      title: '损坏标题',
      body: '损坏时仍可恢复的正文',
    );
    final cardDir = Directory(
      '${repository.richTextStorage.baseDir.path}'
      '${Platform.pathSeparator}card_corrupt_doc',
    );
    await cardDir.create(recursive: true);
    await File('${cardDir.path}${Platform.pathSeparator}rich_text.json')
        .writeAsString('{broken');

    final corrupt = await repository.getCard('corrupt_doc');
    expect(corrupt!.documentState, CardDocumentState.corrupt);
    expect(corrupt.card.body, '损坏时仍可恢复的正文');

    await repository.saveRichText(
      'corrupt_doc',
      const RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: '修复后的标题'),
        RichTextBlock(type: BlockType.paragraph, text: '修复正文'),
      ]),
    );
    final repaired = await repository.getCard('corrupt_doc');
    expect(repaired!.documentState, CardDocumentState.available);
    expect(repaired.card.title, '修复后的标题');
    expect(repaired.card.body, contains('修复正文'));
  });

  test('unknown card cannot create an orphan document', () async {
    await expectLater(
      repository.saveRichText('does_not_exist', RichTextDocument.empty()),
      throwsStateError,
    );
    expect(repository.richTextStorage.exists('does_not_exist'), isFalse);
  });

  test('cached Card cannot make stale rich media current again', () async {
    final card = await repository.createTextCard(
      cardId: 'cached_media',
      body: 'A',
    );
    final objects = RichTextObjectStore(repository.richTextStorage.baseDir);
    final ref = await objects.importBytes(
      Uint8List.fromList([1, 2, 3]),
      mimeType: 'image/png',
      extension: 'png',
    );
    await repository.saveRichText(
      card.cardId,
      RichTextDocument(
        blocks: [
          const RichTextBlock(type: BlockType.paragraph, text: 'A'),
          RichTextBlock(
            type: BlockType.image,
            attrs: {'asset_ref_id': ref.refId},
          ),
        ],
        assetRefs: [ref],
      ),
    );
    final cachedA = (await repository.getCard(card.cardId))!.card;
    final richFile = File(
      '${repository.richTextStorage.baseDir.path}${Platform.pathSeparator}'
      'card_${card.cardId}${Platform.pathSeparator}rich_text.json',
    );
    final bytes = await richFile.readAsBytes();
    final assetFile = objects.resolveFile(ref)!;

    await repository.updateCardMetadata(card.cardId, body: 'B');
    final projection = await CardLocalMediaResolver(repository).resolve(
      card.cardId,
      card: cachedA,
    );
    expect(projection.state, CardLocalMediaState.none);
    expect(await richFile.readAsBytes(), bytes);
    expect(await assetFile.exists(), isTrue);
  });

  testWidgets('stale full editor saves labels without rewriting rich file',
      (tester) async {
    late CardContract card;
    late File richFile;
    late List<int> bytes;
    await tester.runAsync(() async {
      card = await repository.createTextCard(
        cardId: 'stale_tags',
        body: 'A',
        tags: const ['old'],
      );
      await repository.saveRichText(
        card.cardId,
        const RichTextDocument(
          blocks: [
            RichTextBlock(
              type: BlockType.paragraph,
              text: 'A',
              marks: [RichTextMark(type: MarkType.bold, start: 0, end: 1)],
            ),
          ],
        ),
      );
      richFile = File(
        '${repository.richTextStorage.baseDir.path}${Platform.pathSeparator}'
        'card_${card.cardId}${Platform.pathSeparator}rich_text.json',
      );
      bytes = await richFile.readAsBytes();
      await repository.updateCardMetadata(card.cardId, body: 'B');
      final stale = await repository.getCard(card.cardId);
      expect(stale!.documentState, CardDocumentState.stale);
    });
    CardRichTextEditorScreen.setRepositoryForTesting(repository);
    addTearDown(
      () => CardRichTextEditorScreen.setRepositoryForTesting(null),
    );

    await tester.pumpWidget(MaterialApp(
      home: CardRichTextEditorScreen(cardId: card.cardId),
    ));
    for (var i = 0;
        i < 50 &&
            find.byKey(const ValueKey('card-tag-input')).evaluate().isEmpty;
        i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
    final loadedEditor = tester.widget<editor.CardRichTextEditorScreen>(
      find.byType(editor.CardRichTextEditorScreen),
    );
    expect(loadedEditor.degradedMessage, contains('旧文件和媒体已保留'));
    final notice = find.byKey(const ValueKey('rich_text_degraded_notice'));
    expect(notice, findsOneWidget);
    expect(
      tester
          .widget<Text>(
              find.descendant(of: notice, matching: find.byType(Text)))
          .data,
      contains('旧文件和媒体已保留'),
    );
    await tester.enterText(
      find.byKey(const ValueKey('card-tag-input')),
      'new',
    );
    await tester.tap(find.byKey(const ValueKey('card-tag-add')));
    await tester.tap(find.byKey(const ValueKey('rich_text_save_button')));
    for (var i = 0; i < 50 && find.text('已保存').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.text('已保存'), findsOneWidget);

    expect(await tester.runAsync(richFile.readAsBytes), bytes);
    final stored = await tester.runAsync(
      () async => (await repository.getCard(card.cardId))!,
    );
    expect(stored!.card.body, 'B');
    expect(stored.card.tags, ['old', 'new']);
    expect(stored.documentState, CardDocumentState.stale);
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var index = 0; index < 50; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 40));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets, reason: 'widget did not appear after 2 seconds');
}
