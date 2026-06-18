import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/reading/fetchers/reading_fetcher.dart';
import 'package:memex/data/services/reading/fetchers/wechat_mp_fetcher.dart';
import 'package:memex/data/services/reading/reading_image_processor.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

/// Coordinates "platform-aware fetch + persist back into reading_item entity"
/// for the Reading Companion pipeline.
///
/// Lifecycle:
///   1. ReadingCaptureService creates the reading_item entity with
///      `fetch_status` implicitly absent (== not yet attempted).
///   2. It fires `fetchAndPersist(entityId)` fire-and-forget.
///   3. This coordinator picks a fetcher based on entity.platform, runs it,
///      writes the body to `{userId}/reading/{entityId}.md`, and applies an
///      `update` operation patching the entity stateJson with metadata.
///
/// The full body lives on disk to keep stateJson small (entity state is
/// scanned in-memory by queryRelevantEntities). The excerpt (~500 chars)
/// stays in state so haystack search can match content keywords.
///
/// Like ReadingCaptureService, this uses constructor injection + a static
/// instance for global wiring.
class ReadingFetchCoordinator {
  // ---- static singleton wiring -----------------------------------------
  static ReadingFetchCoordinator? _instance;

  static bool get isInitialized => _instance != null;

  static ReadingFetchCoordinator get instance {
    final svc = _instance;
    if (svc == null) {
      throw StateError('ReadingFetchCoordinator has not been initialized');
    }
    return svc;
  }

  static void init({
    required AppDatabase db,
    required SharedLifeMemoryService sharedLifeMemory,
    List<ReadingFetcher>? fetchers,
    ReadingImageProcessor? imageProcessor,
  }) {
    _instance = ReadingFetchCoordinator(
      db: db,
      sharedLifeMemory: sharedLifeMemory,
      fetchers: fetchers ?? [WechatMpFetcher()],
      imageProcessor: imageProcessor ?? ReadingImageProcessor(),
    );
  }

  // ---- instance -------------------------------------------------------
  ReadingFetchCoordinator({
    required this.db,
    required this.sharedLifeMemory,
    required List<ReadingFetcher> fetchers,
    required this.imageProcessor,
  }) : _fetchersByPlatform = {for (final f in fetchers) f.platform: f};

  final AppDatabase db;
  final SharedLifeMemoryService sharedLifeMemory;
  final ReadingImageProcessor imageProcessor;
  final Map<String, ReadingFetcher> _fetchersByPlatform;
  final Logger _logger = getLogger('ReadingFetchCoordinator');

  /// Fires whenever an entity's fetch result has been persisted. UI widgets
  /// (e.g. ReadingCardAddendumWidget) listen and re-query the entity to
  /// pick up cover_url / author / content_excerpt / fetch_status.
  ///
  /// The value carries the just-updated entity id so listeners can filter.
  final ValueNotifier<String?> entityFetchUpdates = ValueNotifier(null);

  /// Registers an additional fetcher at runtime (e.g. the 小红书 fetcher
  /// after the user has logged in via the dedicated WebView page).
  void registerFetcher(ReadingFetcher fetcher) {
    _fetchersByPlatform[fetcher.platform] = fetcher;
  }

  /// Resolve a fetcher for a platform. Null when nothing is registered —
  /// callers should treat that as "fetch unsupported, leave entity in
  /// placeholder state".
  ReadingFetcher? fetcherFor(String platform) => _fetchersByPlatform[platform];

  /// Main entry point. Look up the entity, run its platform's fetcher,
  /// persist the result. Idempotent: re-running for an already-fetched
  /// entity overwrites with the latest fetch (useful for the future
  /// "retry fetch" affordance).
  Future<void> fetchAndPersist(String entityId) async {
    try {
      final detail = await sharedLifeMemory.getEntityDetail(entityId);
      if (detail == null) {
        _logger.warning('fetchAndPersist: entity not found $entityId');
        return;
      }
      if (detail.entity.entityType != 'reading_item') {
        _logger.warning(
            'fetchAndPersist: entity $entityId is not a reading_item');
        return;
      }
      final state = detail.entity.state;
      final url = state['url'] as String?;
      final platform = state['platform'] as String?;
      if (url == null || url.isEmpty || platform == null || platform.isEmpty) {
        _logger.warning('fetchAndPersist: entity $entityId missing url/platform');
        return;
      }

      // Pick the original create operation's sourceMessageId to attach as
      // evidence for this update operation. applyOperations refuses ops
      // without source evidence by design (event-sourcing integrity), and
      // we don't want to invent a fake message — reusing the create's
      // source is the cleanest thing to do.
      final originSourceMessageId = _originSourceMessageId(detail.operations);
      if (originSourceMessageId == null) {
        _logger.warning(
            'fetchAndPersist: no origin source message for $entityId');
        return;
      }

      final sourceCharacterId = detail.operations.isNotEmpty
          ? detail.operations.first.sourceCharacterId
          : null;
      if (sourceCharacterId == null || sourceCharacterId.isEmpty) {
        _logger.warning(
            'fetchAndPersist: no sourceCharacterId for $entityId');
        return;
      }

      final fetcher = _fetchersByPlatform[platform];
      if (fetcher == null) {
        _logger.info(
            'fetchAndPersist: no fetcher for platform=$platform, marking pending');
        await _patchEntity(
          entityId: entityId,
          sourceCharacterId: sourceCharacterId,
          sourceMessageId: originSourceMessageId,
          patch: {
            'fetch_status': 'unsupported',
            'fetched_at': DateTime.now().toIso8601String(),
          },
        );
        return;
      }

      _logger.info('Fetching $platform article for entity=$entityId');
      final result = await fetcher.fetch(url);

      if (!result.success) {
        _logger.warning(
            'Fetch failed for $entityId: ${result.errorMessage}');
        await _patchEntity(
          entityId: entityId,
          sourceCharacterId: sourceCharacterId,
          sourceMessageId: originSourceMessageId,
          patch: {
            'fetch_status': 'failed',
            'fetch_error': result.errorMessage,
            'fetched_at': DateTime.now().toIso8601String(),
          },
        );
        return;
      }

      // Run on-device OCR over every article image. This is the heavy
      // step (downloads + ML Kit), so it runs *after* the metadata patch
      // would have surfaced the cover/title — but in this version we
      // batch them so the file body written below already includes OCR
      // results. Image processor failures are non-fatal: the body still
      // gets written, just without "[图 N - 文字识别 ...]" tails.
      final imageUrls = result.imageUrls;
      List<ImageOcrResult> ocrResults = const [];
      if (imageUrls.isNotEmpty) {
        try {
          _logger.info(
              'Running OCR on ${imageUrls.length} images for $entityId');
          ocrResults = await imageProcessor.processAll(
            entityId: entityId,
            imageUrls: imageUrls,
          );
        } catch (e) {
          _logger.warning('Image OCR pipeline failed for $entityId: $e');
        }
      }

      // Persist the full body to disk. The path lives in stateJson; the
      // body itself does not — keeps the entity state cheap to scan.
      String? contentFilePath;
      final fullBody = _assembleBody(
        baseBody: result.contentFull,
        ocrResults: ocrResults,
      );
      if (fullBody != null && fullBody.isNotEmpty) {
        contentFilePath = await _writeBodyToDisk(entityId, fullBody);
      }

      final refinedTitle = result.title?.trim();
      final shouldOverrideTitle =
          refinedTitle != null && refinedTitle.isNotEmpty;
      final imagesWithText =
          ocrResults.where((r) => r.recognisedText.isNotEmpty).length;

      await _patchEntity(
        entityId: entityId,
        sourceCharacterId: sourceCharacterId,
        sourceMessageId: originSourceMessageId,
        title: shouldOverrideTitle ? refinedTitle : null,
        patch: {
          if (shouldOverrideTitle) 'summary': refinedTitle,
          if (result.author != null && result.author!.isNotEmpty)
            'author': result.author,
          if (result.coverUrl != null && result.coverUrl!.isNotEmpty)
            'cover_url': result.coverUrl,
          if (result.contentExcerpt != null &&
              result.contentExcerpt!.isNotEmpty)
            'content_excerpt': result.contentExcerpt,
          if (contentFilePath != null) 'content_file_path': contentFilePath,
          if (imageUrls.isNotEmpty) 'image_count': imageUrls.length,
          if (imagesWithText > 0) 'images_with_text': imagesWithText,
          'fetch_status': 'success',
          'fetched_at': DateTime.now().toIso8601String(),
        },
      );
      _logger.info('Fetch succeeded for $entityId');
    } catch (e, stack) {
      _logger.severe('fetchAndPersist crashed for $entityId', e, stack);
    } finally {
      // Notify listeners regardless of outcome — the reading_card widget
      // uses this to leave its "loading" state.
      entityFetchUpdates.value = entityId;
    }
  }

  // -------------------------------------------------------------------------

  /// Loads the body that was saved to disk during a previous successful
  /// fetch. Returns null if the file is missing or the path was never
  /// recorded. Used by the "和 TA 聊聊" discussion flow (Phase 3) to feed
  /// the full article into the LLM context.
  Future<String?> loadFullBody(String contentFilePath) async {
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) return null;
      final abs = _absoluteBodyPath(userId, contentFilePath);
      final file = File(abs);
      if (!await file.exists()) return null;
      return file.readAsString();
    } catch (e) {
      _logger.warning('loadFullBody failed: $e');
      return null;
    }
  }

  // -------------------------------------------------------------------------

  Future<void> _patchEntity({
    required String entityId,
    required String sourceCharacterId,
    required int sourceMessageId,
    String? title,
    required Map<String, dynamic> patch,
  }) async {
    await sharedLifeMemory.applyOperations(
      sourceCharacterId: sourceCharacterId,
      captureTaskId: null,
      operations: [
        SharedLifeOperationDraft(
          operationType: 'update',
          entityType: 'reading_item',
          title: title ?? '',
          patch: patch,
          sourceMessageIds: [sourceMessageId],
          entityId: entityId,
        ),
      ],
      allowedSourceMessageIds: {sourceMessageId},
    );
  }

  int? _originSourceMessageId(List<SharedLifeEventOperation> operations) {
    for (final op in operations) {
      if (op.operationType == 'create' || op.operationType == 'derive') {
        final decoded = _decodeIntList(op.sourceMessageIds);
        if (decoded.isNotEmpty) return decoded.first;
      }
    }
    return null;
  }

  List<int> _decodeIntList(String json) {
    try {
      final raw = jsonDecode(json);
      if (raw is List) {
        return raw.whereType<int>().toList(growable: false);
      }
    } catch (_) {}
    return const [];
  }

  /// Assembles the article body that gets written to disk and exposed to
  /// the agent via LoadReadingContent. The base body (plain article text)
  /// comes first, then OCR results from each image are appended in a
  /// labelled section. Returns null when there's nothing to write.
  String? _assembleBody({
    required String? baseBody,
    required List<ImageOcrResult> ocrResults,
  }) {
    final hasBody = baseBody != null && baseBody.trim().isNotEmpty;
    final ocrLines = <String>[];
    for (final r in ocrResults) {
      if (r.recognisedText.trim().isEmpty) continue;
      ocrLines
          .add('[图 ${r.index} - 文字识别]\n${r.recognisedText.trim()}');
    }
    if (!hasBody && ocrLines.isEmpty) return null;
    final buf = StringBuffer();
    if (hasBody) buf.write(baseBody.trim());
    if (ocrLines.isNotEmpty) {
      if (buf.isNotEmpty) buf.write('\n\n');
      buf.write('---\n图片文字识别（OCR）：\n\n');
      buf.write(ocrLines.join('\n\n'));
    }
    return buf.toString();
  }

  Future<String> _writeBodyToDisk(String entityId, String body) async {
    final userId = await UserStorage.getUserId();
    if (userId == null) {
      throw StateError('No userId — cannot persist reading body');
    }
    // Relative path stored in the entity state — resolution to absolute
    // happens through FileSystemService both when reading and writing,
    // so backups/migrations don't break.
    final relativePath = 'reading/$entityId.md';
    final abs = _absoluteBodyPath(userId, relativePath);
    final file = File(abs);
    await file.parent.create(recursive: true);
    await file.writeAsString(body);
    return relativePath;
  }

  String _absoluteBodyPath(String userId, String relativePath) {
    final userRoot = FileSystemService.instance.getWorkspacePath(userId);
    return '$userRoot/$relativePath';
  }
}
