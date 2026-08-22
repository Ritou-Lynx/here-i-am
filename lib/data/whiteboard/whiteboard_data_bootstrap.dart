/// One production entry for the unified whiteboard data layer.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:memex/data/whiteboard/legacy_whiteboard_data_migrator.dart';
import 'package:memex/data/whiteboard/thumbnail/safe_thumbnail_resolver.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';

class WhiteboardDataBootstrap {
  WhiteboardDataBootstrap._();

  static Future<UnifiedCardRepository>? _productionRepository;
  static AppDatabase? _productionDatabase;
  static UnifiedCardRepository? _repositoryForTesting;
  static Directory? _productionRootForTesting;

  /// Returns one production Repository and completes the idempotent F0
  /// legacy import before exposing it to UI consumers.
  static Future<UnifiedCardRepository> productionRepository() {
    final testingRepository = _repositoryForTesting;
    if (testingRepository != null) return Future.value(testingRepository);

    final database = AppDatabase.instance;
    if (!identical(_productionDatabase, database)) {
      _productionDatabase = database;
      _productionRepository = _openProduction(database);
    }
    return _productionRepository!;
  }

  @visibleForTesting
  static void setRepositoryForTesting(UnifiedCardRepository? repository) {
    _repositoryForTesting = repository;
    _productionRepository = null;
    _productionDatabase = null;
  }

  @visibleForTesting
  static void setProductionRootForTesting(Directory? root) {
    _productionRootForTesting = root;
    _productionRepository = null;
    _productionDatabase = null;
  }

  static Future<UnifiedCardRepository> _openProduction(
    AppDatabase database,
  ) async {
    final testingRoot = _productionRootForTesting;
    final root = testingRoot ??
        Directory(
          p.join((await getApplicationSupportDirectory()).path, 'whiteboard'),
        );
    late final UnifiedCardRepository repository;
    final thumbnailResolver = SafeThumbnailResolver(
      whiteboardRoot: root,
      referencedObjectRefs: () => repository.referencedThumbnailObjectRefs(),
    );
    repository = UnifiedCardRepository(
      db: database,
      whiteboardRoot: root,
      thumbnailResolver: thumbnailResolver,
    );
    await repository.recoverFileReplacements();
    await LegacyWhiteboardDataMigrator(
      repository: repository,
      legacyRichTextRoot: Directory(p.join(root.path, 'rich_text')),
      legacyIngestionRoot: Directory(p.join(root.path, 'ingestion')),
    ).run();
    return repository;
  }
}
