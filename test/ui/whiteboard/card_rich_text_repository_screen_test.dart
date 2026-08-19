import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';

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
}
