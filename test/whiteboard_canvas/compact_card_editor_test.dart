import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/ui/whiteboard_canvas/widgets/compact_card_editor.dart';

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 50 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 40));
  }
  expect(finder, findsOneWidget);
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required UnifiedCardRepository repository,
  required String cardId,
  required VoidCallback onClose,
  ValueChanged<CardContract>? onSaved,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 280,
            height: 190,
            child: CompactCardEditor(
              cardId: cardId,
              repository: repository,
              embedded: true,
              onSaved: onSaved ?? (_) {},
              onClose: onClose,
              onExpand: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await _pumpUntil(
    tester,
    find.byKey(const Key('rich_text_continuous_document')),
  );
}

class _FailingSaveRepository extends UnifiedCardRepository {
  _FailingSaveRepository({required super.db, required super.whiteboardRoot});

  var remainingFailures = 1;

  @override
  Future<CardContract> saveRichText(
    String cardId,
    RichTextDocument document, {
    String? title,
    bool preserveEmptyTitle = false,
  }) {
    if (remainingFailures > 0) {
      remainingFailures--;
      throw StateError('scripted save failure');
    }
    return super.saveRichText(
      cardId,
      document,
      title: title,
      preserveEmptyTitle: preserveEmptyTitle,
    );
  }
}

void main() {
  testWidgets(
      'Domain inline surface accepts only canonical plain text and format media only creates no commit',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('inline_domain_plain_');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    addTearDown(() async {
      await db.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    await tester.runAsync(() async {
      await repository.createTextCard(
        cardId: 'card_domain_plain',
        title: '标题',
      );
      await repository.saveRichText(
        'card_domain_plain',
        const RichTextDocument(
          blocks: [
            RichTextBlock(
              type: BlockType.paragraph,
              text: '正文',
              marks: [RichTextMark(type: MarkType.bold, start: 0, end: 2)],
            ),
            RichTextBlock(
              type: BlockType.image,
              attrs: {'asset_ref_id': 'asset_preserved'},
            ),
          ],
        ),
        title: '标题',
      );
    });
    final richFile = File(
      '${repository.richTextStorage.baseDir.path}${Platform.pathSeparator}'
      'card_card_domain_plain${Platform.pathSeparator}rich_text.json',
    );
    final before = await tester.runAsync(richFile.readAsBytes);
    var commits = 0;
    var closed = false;
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 280,
        height: 190,
        child: CompactCardEditor(
          cardId: 'card_domain_plain',
          repository: repository,
          embedded: true,
          domainSave: ({required cardId, required title, required body}) async {
            commits++;
            return (await repository.getCard(cardId, loadDocument: false))
                ?.card;
          },
          onSaved: (_) {},
          onClose: () => closed = true,
          onExpand: (_) {},
        ),
      ),
    ));
    final field = find.byKey(const Key('rich_text_continuous_document'));
    await _pumpUntil(tester, field);
    expect(find.textContaining('插入图片'), findsNothing);
    expect(find.byKey(const ValueKey('rich_text_toolbar')), findsNothing);
    expect(tester.widget<TextField>(field).controller!.text, '标题\n正文');

    await tester.enterText(field, '标题\n正文');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 20 && !closed; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(closed, isTrue);
    expect(commits, 0,
        reason: 'format/media-only state is not a canonical body mutation');
    expect(await tester.runAsync(richFile.readAsBytes), before);
  });

  testWidgets('Domain rejection shows failure and keeps the inline draft open',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('inline_domain_failure_');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    addTearDown(() async {
      await db.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    await tester.runAsync(() => repository.createTextCard(
          cardId: 'card_domain_failure',
          title: '原标题',
          body: '原正文',
        ));
    var saveAttempts = 0;
    var savedCallbacks = 0;
    var closed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 280,
          height: 190,
          child: CompactCardEditor(
            cardId: 'card_domain_failure',
            repository: repository,
            embedded: true,
            domainSave: (
                {required cardId, required title, required body}) async {
              saveAttempts++;
              return null;
            },
            onSaved: (_) => savedCallbacks++,
            onClose: () => closed = true,
            onExpand: (_) {},
          ),
        ),
      ),
    ));
    final field = find.byKey(const Key('rich_text_continuous_document'));
    await _pumpUntil(tester, field);
    await tester.enterText(field, '草稿标题\n草稿正文');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0;
        i < 20 && find.textContaining('保存失败').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    expect(saveAttempts, 1);
    expect(savedCallbacks, 0);
    expect(closed, isFalse);
    expect(find.byKey(const Key('wb_compact_card_editor')), findsOneWidget);
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, '草稿标题\n草稿正文');
    final persisted = (await tester.runAsync(
      () => repository.getCard('card_domain_failure', loadDocument: false),
    ))!;
    expect(persisted.card.title, '原标题');
    expect(persisted.card.body, '原正文');
  });

  testWidgets('空标题与正文 H1 通过稳定 synthetic 边界无损编辑并重启恢复', (tester) async {
    final root = Directory.systemTemp.createTempSync('inline_card_restart_');
    final dbFile = File('${root.path}${Platform.pathSeparator}cards.sqlite');
    var db = AppDatabase.forTesting(NativeDatabase(dbFile));
    var repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await db.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    const cardId = 'card_empty_title_heading_body';
    await tester.runAsync(() async {
      await repository.createTextCard(cardId: cardId, title: '');
      await repository.saveRichText(
        cardId,
        const RichTextDocument(
          blocks: [
            RichTextBlock(
              type: BlockType.heading,
              text: '正文 H1',
              attrs: {'level': 1},
            ),
            RichTextBlock(type: BlockType.paragraph, text: '第二段'),
          ],
        ),
        title: '',
        preserveEmptyTitle: true,
      );
    });

    var closed = false;
    await _pumpEditor(
      tester,
      repository: repository,
      cardId: cardId,
      onClose: () => closed = true,
    );
    final field = find.byKey(const Key('rich_text_continuous_document'));
    final editor = find.byKey(const Key('wb_compact_card_editor'));
    expect(find.byKey(const Key('wb_compact_title')), findsNothing);
    expect(
      find.descendant(of: editor, matching: find.byType(TextField)),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(field).controller!.text, '\n正文 H1\n第二段');

    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '\n组合中\n第二段',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 1, end: 4),
    ));
    await tester.pump();
    expect(
      tester.widget<TextField>(field).controller!.value.composing,
      const TextRange(start: 1, end: 4),
    );

    await tester.enterText(field, '\n正文 H1 已改\n第二段');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '\n正文 H1\n第二段');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '\n正文 H1 已改\n第二段');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 30 && !closed; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(closed, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    final restored = (await tester.runAsync(() => repository.getCard(cardId)))!;
    expect(restored.card.title, isEmpty);
    expect(restored.document!.blocks, hasLength(2));
    expect(restored.document!.blocks.first.type, BlockType.heading);
    expect(restored.document!.blocks.first.headingLevel, 1);
    expect(restored.document!.blocks.first.text, '正文 H1 已改');
    expect(
      restored.document!.blocks.any(
        (block) => block.attrs.containsKey('_inline_card_title_boundary'),
      ),
      isFalse,
    );

    await _pumpEditor(
      tester,
      repository: repository,
      cardId: cardId,
      onClose: () {},
    );
    expect(tester.widget<TextField>(field).controller!.text, '\n正文 H1 已改\n第二段');
  });

  testWidgets('保存失败保留编辑态，重试后才退出', (tester) async {
    final root = Directory.systemTemp.createTempSync('inline_card_failure_');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = _FailingSaveRepository(db: db, whiteboardRoot: root);
    addTearDown(() async {
      await db.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    await tester.runAsync(() => repository.createTextCard(
          cardId: 'card_save_retry',
          title: '原标题',
          body: '原正文',
        ));
    var closeCount = 0;
    await _pumpEditor(
      tester,
      repository: repository,
      cardId: 'card_save_retry',
      onClose: () => closeCount++,
    );
    final field = find.byKey(const Key('rich_text_continuous_document'));
    await tester.enterText(field, '新标题\n新正文');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 200));
    expect(closeCount, 0);
    expect(find.byKey(const Key('wb_compact_card_editor')), findsOneWidget);
    expect(find.textContaining('保存失败'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 30 && closeCount == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(closeCount, 1);
    final stored =
        (await tester.runAsync(() => repository.getCard('card_save_retry')))!;
    expect(stored.card.title, '新标题');
    expect(stored.card.body, '新正文');
  });
}
