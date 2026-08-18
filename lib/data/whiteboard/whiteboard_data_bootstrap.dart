/// One production entry for the unified whiteboard data layer.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:memex/data/whiteboard/legacy_whiteboard_data_migrator.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';

class WhiteboardDataBootstrap {
  WhiteboardDataBootstrap._();

  static Future<UnifiedCardRepository>? _productionRepository;

  /// Returns one production Repository and completes the idempotent F0
  /// legacy import before exposing it to UI consumers.
  static Future<UnifiedCardRepository> productionRepository() {
    return _productionRepository ??= _openProduction();
  }

  @visibleForTesting
  static void setRepositoryForTesting(UnifiedCardRepository? repository) {
    _productionRepository =
        repository == null ? null : Future.value(repository);
  }

  static Future<UnifiedCardRepository> _openProduction() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'whiteboard'));
    final repository = UnifiedCardRepository(
      db: AppDatabase.instance,
      whiteboardRoot: root,
    );
    await LegacyWhiteboardDataMigrator(
      repository: repository,
      legacyRichTextRoot: Directory(p.join(root.path, 'rich_text')),
      legacyIngestionRoot: Directory(p.join(root.path, 'ingestion')),
    ).run();
    return repository;
  }
}
