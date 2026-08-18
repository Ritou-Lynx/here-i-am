import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/legacy_whiteboard_data_migrator.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/desktop/view_models/desktop_home_view_model.dart';

void main() {
  test('first home load sees a card imported from legacy rich text', () async {
    final tempDir = await Directory.systemTemp.createTemp('desktop_home_f0_');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    final whiteboardRoot = Directory('${tempDir.path}/whiteboard');
    final legacyRichRoot = Directory('${tempDir.path}/legacy_rich_text');
    final cardDir = Directory('${legacyRichRoot.path}/card_legacy_home');
    await cardDir.create(recursive: true);
    await File('${cardDir.path}/rich_text.json').writeAsString(jsonEncode({
      'schema_version': 2,
      'blocks': [
        {'type': 'paragraph', 'text': '首次启动迁移卡'},
      ],
    }));

    final repository = UnifiedCardRepository(
      db: db,
      whiteboardRoot: whiteboardRoot,
    );
    await LegacyWhiteboardDataMigrator(
      repository: repository,
      legacyRichTextRoot: legacyRichRoot,
      legacyIngestionRoot: Directory('${tempDir.path}/legacy_ingestion'),
    ).run();

    final viewModel = DesktopHomeViewModel(
      db: db,
      cardRepository: repository,
    );
    await viewModel.load();

    expect(viewModel.error, isNull);
    expect(
      viewModel.data!.pendingCards.map((card) => card.id),
      contains('legacy_home'),
    );
  });
}
