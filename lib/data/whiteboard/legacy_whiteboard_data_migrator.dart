/// Idempotent importer for the three pre-F0 whiteboard data paths.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:memex/data/whiteboard/ingestion/ingestion_store.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/domain/whiteboard/rich_text_storage.dart';

class LegacyMigrationFailure {
  const LegacyMigrationFailure({
    required this.kind,
    required this.reference,
    required this.message,
  });

  final String kind;
  final String reference;
  final String message;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'reference': reference,
        'message': message,
      };
}

class LegacyMigrationReport {
  LegacyMigrationReport({required this.startedAt});

  final DateTime startedAt;
  DateTime? completedAt;
  int driftExtrasBackfilled = 0;
  int richTextCardsCreated = 0;
  int richTextProjectionsUpdated = 0;
  int ingestionRecordsImported = 0;
  int skippedExistingOrOlder = 0;
  final List<String> possibleTestArtifacts = [];
  final List<LegacyMigrationFailure> failures = [];

  Map<String, dynamic> toJson() => {
        'schema_version': 1,
        'started_at': startedAt.toUtc().toIso8601String(),
        if (completedAt != null)
          'completed_at': completedAt!.toUtc().toIso8601String(),
        'drift_extras_backfilled': driftExtrasBackfilled,
        'rich_text_cards_created': richTextCardsCreated,
        'rich_text_projections_updated': richTextProjectionsUpdated,
        'ingestion_records_imported': ingestionRecordsImported,
        'skipped_existing_or_older': skippedExistingOrOlder,
        'possible_test_artifacts': possibleTestArtifacts,
        'failures': failures.map((failure) => failure.toJson()).toList(),
      };
}

class LegacyWhiteboardDataMigrator {
  LegacyWhiteboardDataMigrator({
    required this.repository,
    required this.legacyRichTextRoot,
    required this.legacyIngestionRoot,
  });

  final UnifiedCardRepository repository;
  final Directory legacyRichTextRoot;
  final Directory legacyIngestionRoot;

  File get reportFile => File(
        p.join(
          repository.whiteboardRoot.path,
          'migrations',
          'f0_data_convergence_report.json',
        ),
      );

  Future<LegacyMigrationReport> run() async {
    final report = LegacyMigrationReport(startedAt: DateTime.now().toUtc());
    await _backfillDrift(report);
    await _migrateRichText(report);
    await _migrateIngestion(report);
    report.completedAt = DateTime.now().toUtc();
    await _writeReport(report);
    return report;
  }

  Future<void> _backfillDrift(LegacyMigrationReport report) async {
    final rows = await repository.db.select(repository.db.memoryCards).get();
    for (final row in rows) {
      if (row.memoryScope != 'user_truth' || row.type != 'note') continue;
      if (isLikelyTestArtifact(row.id, row.title)) {
        report.possibleTestArtifacts.add('drift:${row.id}:${row.title}');
        continue;
      }
      try {
        if (await repository.backfillLegacyMemoryCardExtra(row.id)) {
          report.driftExtrasBackfilled++;
        } else {
          report.skippedExistingOrOlder++;
        }
      } catch (error) {
        report.failures.add(LegacyMigrationFailure(
          kind: 'drift',
          reference: row.id,
          message: error.toString(),
        ));
      }
    }
  }

  Future<void> _migrateRichText(LegacyMigrationReport report) async {
    if (!await legacyRichTextRoot.exists()) return;
    final storage = RichTextStorage(legacyRichTextRoot);
    await for (final entity in legacyRichTextRoot.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (!name.startsWith('card_')) continue;
      final cardId = name.substring('card_'.length);
      if (isLikelyTestArtifact(cardId, '')) {
        report.possibleTestArtifacts.add('rich_text:$cardId');
        continue;
      }
      try {
        final loaded = await storage.loadWithStatus(cardId);
        if (loaded.status == RichTextLoadStatus.missing) continue;
        if (loaded.status == RichTextLoadStatus.corrupt ||
            loaded.document == null) {
          report.failures.add(LegacyMigrationFailure(
            kind: 'rich_text',
            reference: cardId,
            message: loaded.error ?? 'corrupt rich_text.json',
          ));
          continue;
        }
        final projection = loaded.document!.toPlainText().trim();
        final file = File(p.join(entity.path, 'rich_text.json'));
        final fileModified = (await file.stat()).modified.toUtc();
        final existing = await repository.getCard(
          cardId,
          includeDeleted: true,
          loadDocument: false,
        );
        if (existing == null) {
          await repository.createTextCard(
            cardId: cardId,
            title: _title(projection, cardId),
            body: projection,
            createdAt: fileModified,
          );
          report.richTextCardsCreated++;
        }
        final current = existing?.card;
        final currentTime = current == null
            ? null
            : (current.updatedAt ?? current.createdAt).toUtc();
        if (currentTime != null && currentTime.isAfter(fileModified)) {
          report.skippedExistingOrOlder++;
        } else if (current == null || current.body != projection) {
          await repository.saveRichText(cardId, loaded.document!);
          report.richTextProjectionsUpdated++;
        } else {
          report.skippedExistingOrOlder++;
        }
      } catch (error) {
        report.failures.add(LegacyMigrationFailure(
          kind: 'rich_text',
          reference: cardId,
          message: error.toString(),
        ));
      }
    }
  }

  Future<void> _migrateIngestion(LegacyMigrationReport report) async {
    final sourcesDir = Directory(p.join(legacyIngestionRoot.path, 'sources'));
    if (!await sourcesDir.exists()) return;
    final store = IngestionStore(legacyIngestionRoot);
    await for (final entity in sourcesDir.list(followLinks: false)) {
      if (entity is! File ||
          p.extension(entity.path).toLowerCase() != '.json') {
        continue;
      }
      final sourceId = p.basenameWithoutExtension(entity.path);
      try {
        final record = await store.getRecord(sourceId);
        if (record == null) {
          report.failures.add(LegacyMigrationFailure(
            kind: 'ingestion',
            reference: sourceId,
            message: 'corrupt or unreadable source record',
          ));
          continue;
        }
        if (record.card != null &&
            isLikelyTestArtifact(record.card!.cardId, record.card!.title)) {
          report.possibleTestArtifacts.add(
            'ingestion:${record.card!.cardId}:${record.card!.title}',
          );
          continue;
        }
        await repository.importLegacyIngestion(
          source: record.source,
          versions: record.versions,
          card: record.card,
        );
        report.ingestionRecordsImported++;
      } catch (error) {
        report.failures.add(LegacyMigrationFailure(
          kind: 'ingestion',
          reference: sourceId,
          message: error.toString(),
        ));
      }
    }
  }

  Future<void> _writeReport(LegacyMigrationReport report) async {
    await reportFile.parent.create(recursive: true);
    final temp = File('${reportFile.path}.tmp');
    await temp.writeAsString(jsonEncode(report.toJson()), flush: true);
    if (await reportFile.exists()) await reportFile.delete();
    await temp.rename(reportFile.path);
  }

  /// Identifies cleanup candidates but never deletes them.
  static bool isLikelyTestArtifact(String id, String title) {
    final value = '$id\n$title'.toLowerCase();
    return value.contains('itest') ||
        value.contains('integration_test') ||
        value.contains('test_card') ||
        value.contains('perf_card') ||
        value.contains('demo_card') ||
        title.contains('测试卡片') ||
        title.contains('桌面集成验证板') ||
        title.contains('交互验收') ||
        title.contains('帧率验收');
  }

  static String _title(String projection, String fallback) {
    for (final line in projection.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return fallback;
  }
}
