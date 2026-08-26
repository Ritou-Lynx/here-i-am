import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:memex/data/repositories/update_card_ui_config.dart'
    as update_config_endpoint;
import 'package:memex/data/services/search_service.dart';
import 'package:memex/data/services/backup_service.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/domain/models/calendar_model.dart';
import 'package:memex/data/repositories/hydrate_card.dart';
import 'package:memex/data/services/table_change_notifier.dart';
import 'package:memex/data/services/card_attachment_service.dart';
import 'package:memex/data/services/card_detail_notifier.dart';
import 'package:memex/data/services/clarification_request_service.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/data/services/dev_agent_bridge_service.dart';
import 'package:memex/data/services/sync/memory_data_sync_service.dart';
import 'package:memex/data/memory_v3/services/dreaming_orchestrator_service.dart';
import 'package:memex/data/memory_v3/services/dreaming_scheduler_service.dart';
import 'package:memex/data/memory_v3/services/life_insight_service.dart';
import 'package:memex/data/memory_v3/services/life_insight_scheduler.dart';
import 'package:memex/data/memory_v3/services/user_rhythm_service.dart';
import 'package:memex/data/memory_v3/services/growth_pact_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';
import 'package:memex/data/services/reading/fetchers/web_fetcher.dart';
import 'package:memex/data/services/reading/fetchers/xiaohongshu_fetcher.dart';
import 'package:memex/data/services/reading/reading_capture_service.dart';
import 'package:memex/data/services/reading/reading_fetch_coordinator.dart';
import 'package:memex/data/services/reading/transient_fetch_cache.dart';
import 'package:memex/data/services/reading/xhs/xhs_cookie_repository.dart';
import 'package:memex/data/services/comic/comic_remote_service.dart';
import 'package:memex/data/services/comic/comic_library_service.dart';
import 'package:memex/data/services/comic/comic_reading_progress_service.dart';
import 'package:memex/data/services/comic/comic_screenplay_service.dart';
import 'package:memex/data/services/book/book_remote_service.dart';
import 'package:memex/data/services/book/book_library_service.dart';
import 'package:memex/data/services/book/co_reading_note_service.dart';
import 'package:memex/data/services/app_update_service.dart';
import 'package:memex/data/services/user_notification_service.dart';
import 'package:path/path.dart' as path;
import 'package:image_picker/image_picker.dart';
import 'package:memex/data/repositories/get_timeline_card.dart'; // Import for fetchTimelineCard
import 'package:logging/logging.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/card_detail_model.dart';
import 'package:memex/domain/models/tag_model.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/domain/models/agent_config.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/local_task_registry.dart';
import 'package:memex/data/services/global_event_bus.dart';
import 'package:memex/data/repositories/submit_input.dart'
    as submit_input_endpoint;
import 'package:memex/data/services/custom_agent_config_service.dart';
import 'package:memex/data/repositories/get_tags.dart';
import 'package:memex/data/repositories/get_timeline_cards.dart';
import 'package:memex/data/repositories/get_aggregated_timeline.dart';
import 'package:memex/data/repositories/get_cards_by_ids.dart';
import 'package:memex/data/repositories/get_calendar_data.dart';
import 'package:memex/data/repositories/card.dart';
import 'package:memex/data/repositories/character.dart';
import 'package:memex/data/repositories/health.dart' as health_endpoint;
import 'package:memex/data/repositories/pkm.dart' as pkm_endpoint;
import 'package:memex/data/repositories/chat.dart' as chat_endpoint;
import 'package:memex/data/services/llm_call_record_service.dart';
import 'package:memex/data/services/agent_activity_service.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/domain/models/system_event.dart';

/// Local data service for Memex. Handles all data operations via local storage (FileSystemService, DB).
class MemexRouter {
  static final MemexRouter _instance = MemexRouter._();
  factory MemexRouter() => _instance;

  final Logger _logger = getLogger('MemexRouter');

  Future<void>? _initFuture;

  FileSystemService get fileSystemService => FileSystemService.instance;

  MemexRouter._() {
    AgentActivityService.setInstance(LocalAgentActivityService.instance);
    _ensureInitialized();
  }

  Future<void> _init() async {
    try {
      // 1. Resolve data root for current user (per-user workspace storage; logs/DB stay in app dir)
      final userId = await UserStorage.getUserId();
      final dataRoot = await UserStorage.resolveDataRoot(userId);
      await FileSystemService.init(dataRoot);

      if (userId == null) {
        _logger.warning(
          'No user ID found during initialization. Local DB will NOT be initialized until login.',
        );
        return; // Do not initialize DB yet.
      }

      // Use userId to init DB (drift_flutter handles path isolation via name)
      _logger.info('Initializing Local DB for user: $userId');
      await AppDatabase.init(userId);
      if (AppFlavor.isHereIAm) {
        SharedLifeMemoryService.init(AppDatabase.instance, userId);
        final sharedLifeMemory = SharedLifeMemoryService.instance;
        // Record Organizer V3 is the sole explicit User-truth write path.
        RecordOrganizerServiceV3.init(AppDatabase.instance);
        // One-time backfill: re-bridge finance memory cards to the shared
        // ledger for devices that recorded them while the transfer_direction
        // column was missing (see app_database.dart v44 migration). Idempotent
        // via a kv_store marker; safe to run on every startup.
        unawaited(
          RecordOrganizerServiceV3.instance
              .backfillMissingLedgerEntries()
              .catchError((error) {
            _logger.warning(
                'MemexRouter: ledger backfill failed (non-fatal): $error');
            return 0;
          }),
        );
        DreamingOrchestratorServiceV3.init(AppDatabase.instance);
        LifeInsightService.init(AppDatabase.instance);
        // One-shot cleanup: remove legacy duplicate rows left by the old
        // periodStart-based upsert (which inserted a new row every run because
        // periodStart drifted with `now`). Idempotent.
        unawaited(
          LifeInsightService.instance
              .deduplicateLegacyRows()
              .catchError((e) {
            _logger.warning(
                'MemexRouter: LifeInsight legacy dedup failed (non-fatal): $e');
            return 0;
          }),
        );
        UserRhythmService.init(AppDatabase.instance);
        // Rebuild the menstrual_cycle rhythm from surviving menstrual_record
        // cards on every startup. This is the backfill path for devices that
        // recorded period cards while the card->rhythm bridge was not wired,
        // and also resyncs the rhythm if any card was edited outside the
        // normal write path. Idempotent (rebuild-from-cards).
        unawaited(
          UserRhythmService.instance
              .rebuildMenstrualRhythmFromCards()
              .catchError((error) {
            _logger.warning(
                'MemexRouter: menstrual rhythm rebuild failed (non-fatal): $error');
            return 0;
          }),
        );
        GrowthPactService.init(AppDatabase.instance);
        TaskRoomService.init(AppDatabase.instance);
        // Persisted queue recovery is awaited once before any Bridge or UI can
        // observe TaskRoom state, so an interrupted task is never presented as
        // still running after an App/Bridge restart.
        await TaskRoomService.instance.restoreInterruptedTaskRoomsOnce();
        unawaited(
          DreamingSchedulerService.scheduleExistingBacklog(
            AppDatabase.instance,
          ),
        );
        // Life Insight: run a weekly analysis on startup so the companion
        // has fresh insights for check-in and the observation panel.
        unawaited(
          LifeInsightScheduler(db: AppDatabase.instance)
              .runWeeklyAnalysis()
              .catchError((e) {
            _logger.warning(
                'MemexRouter: LifeInsight startup analysis failed: $e');
          }),
        );
        // Project Memory is policy-filtered and idempotent. Refresh configured
        // Bridges on startup so normal companion chat does not depend on the
        // user manually pressing "test connection" in Dev Room settings.
        unawaited(
          DevAgentBridgeService.instance.syncConfiguredProjectMemory(),
        );
        // Reading Companion: share-intent → reading_item entity pipeline.
        ReadingCaptureService.init(
          db: AppDatabase.instance,
          sharedLifeMemory: sharedLifeMemory,
        );
        // Reading Companion: platform-aware fetcher pipeline.
        // 微信公众号 HTML fetcher is always available; the 小红书 fetcher
        // is registered too but short-circuits with a "please connect"
        // message when there's no live session.
        ReadingFetchCoordinator.init(
          db: AppDatabase.instance,
          sharedLifeMemory: sharedLifeMemory,
        );
        ReadingFetchCoordinator.instance.registerFetcher(XiaohongshuFetcher());
        ReadingFetchCoordinator.instance.registerFetcher(WebFetcher());
        // Transient fetch cache: lets the companion read article bodies from
        // chat-sent / share-intent links WITHOUT creating a reading_item
        // entity. Shares the same fetcher instances as the coordinator.
        TransientFetchCache.init(
          fetchersByPlatform:
              ReadingFetchCoordinator.instance.fetchersByPlatform,
        );
        // Restore the persisted "user marked connected" bit for 小红书 so
        // a previously-confirmed session survives app restarts. (The
        // system WebView keeps the cookie itself; this restores OUR flag.)
        unawaited(XhsCookieRepository.instance.restoreFromPrefs());
        // Comic co-reading: Hermes HTTP server pipeline.
        // See docs/companion-first/COMIC_CO_READING_PLAN.md
        final comicRemote = ComicRemoteService(db: AppDatabase.instance);
        ComicLibraryService.init(db: AppDatabase.instance, remote: comicRemote);
        ComicReadingProgressService.init(db: AppDatabase.instance);
        ComicScreenplayService.init(db: AppDatabase.instance);
        // Book co-reading: Hermes book server pipeline.
        final bookRemote = BookRemoteService(db: AppDatabase.instance);
        BookLibraryService.init(db: AppDatabase.instance, remote: bookRemote);
        CoReadingNoteService.init(AppDatabase.instance);
        await _resetCharacterMemoryIfNeeded(userId);
        await _resetWorkspaceDirsIfNeeded(userId);
        await _resetSystemMemoryIfNeeded(userId);
        await sharedLifeMemory.repairOrphanedEntities();
        await FileSystemService.instance.ensureTagsFileInitialized(userId);
        final tagDefinitions =
            await FileSystemService.instance.readTagsFile(userId);
        await sharedLifeMemory.repairTagsAgainstKnownTags(
          tagDefinitions
              .map((tag) => tag['name']?.toString().trim() ?? '')
              .where((tag) => tag.isNotEmpty)
              .toList(growable: false),
        );
      }
      await LocalTaskExecutor.instance.start(userId: userId);

      // Start table change notifier (binlog-style listener for Drift tables)
      TableChangeNotifier.instance.init();
      // Register attachment table watchers
      CardAttachmentService.instance.init();
      // Register user notification table watch (must precede CardDetailNotifier)
      UserNotificationService.instance.init();
      // Register card-detail change notifier (subscribes to GlobalEventBus)
      CardDetailNotifier.instance.init();
      // Register clarification request table watcher (creates timeline cards for global Ask)
      ClarificationRequestService.instance.init();

      registerLocalTaskHandlers();
      // Generic failure handler for all other agent tasks — emits ErrorNotificationMessage

      // Register event subscriptions after task handlers are ready.
      _registerEventSubscriptions();

      // Initialize custom agent handler and register user-defined agents.
      registerBuiltInEventSerializers();
      await CustomAgentConfigService.instance.registerAll(userId);

      // Register file change callback and FTS event subscriptions.
      // Also triggers a one-time full rebuild when FTS tables were just created
      // via migration (existing users upgrading to schema v10).
      SearchService.instance.init(userId);

      scheduleAutoBackupCheck(trigger: 'app_start');
    } catch (e) {
      _logger.severe('Failed to initialize MemexRouter: $e');
      // Reset future to allow retry if needed, or keep failed state
      // _initFuture = null;
      rethrow;
    }
  }

  String?
      _targetUserIdForInit; // Track the user ID we are currently initializing for

  static const _characterMemoryResetMarkerKey =
      'character_memory_full_reset_v1';
  static const _workspaceDirsResetMarkerKey = 'workspace_dirs_reset_v25';
  static const _systemMemoryResetMarkerKey = 'system_memory_reset_v29';

  Future<void> _resetCharacterMemoryIfNeeded(String userId) async {
    final db = AppDatabase.instance;
    final marker = await (db.select(db.kvStore)
          ..where((t) => t.key.equals(_characterMemoryResetMarkerKey)))
        .getSingleOrNull();
    if (marker == null) return;

    final memDir = Directory(path.join(
      FileSystemService.instance.getSystemPath(userId),
      'character_memory',
    ));
    if (await memDir.exists()) {
      await memDir.delete(recursive: true);
      _logger.info('Data reset v24: cleared character_memory dir');
    }

    await (db.delete(db.kvStore)
          ..where((t) => t.key.equals(_characterMemoryResetMarkerKey)))
        .go();
    _logger
        .info('Data reset v24 complete — chat/SharedLife/card tables cleared');
  }

  Future<void> _resetWorkspaceDirsIfNeeded(String userId) async {
    final db = AppDatabase.instance;
    final marker = await (db.select(db.kvStore)
          ..where((t) => t.key.equals(_workspaceDirsResetMarkerKey)))
        .getSingleOrNull();
    if (marker == null) return;

    final fs = FileSystemService.instance;
    final dirsToWipe = [
      fs.getFactsPath(userId),
      fs.getCardsPath(userId),
      fs.getPkmPath(userId),
    ];
    for (final dirPath in dirsToWipe) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      await for (final entry in dir.list(recursive: false)) {
        try {
          if (entry is Directory) {
            await entry.delete(recursive: true);
          } else {
            await entry.delete();
          }
        } catch (e) {
          _logger
              .warning('workspace reset: could not delete ${entry.path}: $e');
        }
      }
      _logger.info('Data reset v25: wiped contents of $dirPath');
    }

    await (db.delete(db.kvStore)
          ..where((t) => t.key.equals(_workspaceDirsResetMarkerKey)))
        .go();
    _logger.info(
        'Data reset v25 complete — Facts/Cards/KnowledgeInsights/PKM wiped');
  }

  Future<void> _resetSystemMemoryIfNeeded(String userId) async {
    final db = AppDatabase.instance;
    final marker = await (db.select(db.kvStore)
          ..where((t) => t.key.equals(_systemMemoryResetMarkerKey)))
        .getSingleOrNull();
    if (marker == null) return;

    final memDir = Directory(path.join(
      FileSystemService.instance.getSystemPath(userId),
      'memory',
    ));
    if (await memDir.exists()) {
      await for (final entry in memDir.list(recursive: false)) {
        try {
          if (entry is Directory) {
            await entry.delete(recursive: true);
          } else {
            await entry.delete();
          }
        } catch (e) {
          _logger.warning(
              'system_memory reset: could not delete ${entry.path}: $e');
        }
      }
      _logger.info('Data reset v29: wiped _System/memory/ contents');
    }

    await (db.delete(db.kvStore)
          ..where((t) => t.key.equals(_systemMemoryResetMarkerKey)))
        .go();
    _logger.info('Data reset v29 complete — settings memory view cleared');
  }

  void _registerEventSubscriptions() {
    final eventBus = GlobalEventBus.instance;

    eventBus.subscribe(
      eventType: SystemEventTypes.userInputSubmitted,
      subscription: EventTaskSubscription(
        subscriptionId: 'analyze_assets',
        taskType: 'handle_analyze_assets',
        payloadBuilder: (_, event) {
          final p = event.payload as UserInputSubmittedPayload;
          return Future.value({
            'fact_id': p.factId,
            'asset_paths': p.assetPaths,
          });
        },
      ),
    );

    // Removed: card_agent / pkm_agent / comment_agent subscriptions and the
    // process_ai_reply (cardCommentPosted) subscription. The legacy Memex card
    // pipeline (analyze_assets -> card_agent -> pkm_agent -> comment_agent ->
    // AI reply) has been retired. User-truth is now written only via explicit
    // Memory V3 record entrypoints (RecordOrganizerServiceV3). analyze_assets
    // is kept because media analysis and the schedule refresh router still
    // depend on it.

    eventBus.subscribe(
      eventType: SystemEventTypes.userInputSubmitted,
      subscription: EventTaskSubscription(
        subscriptionId: 'schedule_refresh_router',
        taskType: 'schedule_refresh_router_task',
        dependsOn: const ['analyze_assets'],
        priority: -1,
        payloadBuilder: (_, event) {
          final p = event.payload as UserInputSubmittedPayload;
          return Future.value({
            'fact_id': p.factId,
            'combined_text': p.combinedText,
            'created_at_ts': p.createdAtTs,
          });
        },
      ),
    );

    eventBus.subscribe(
      eventType: SystemEventTypes.scheduleAggregationRequested,
      subscription: EventTaskSubscription(
        subscriptionId: 'schedule_aggregation_refresh',
        taskType: 'schedule_aggregator_task',
        payloadBuilder: (_, event) => Future.value(const {}),
      ),
    );

    eventBus.subscribe(
      eventType: SystemEventTypes.clarificationAnswered,
      subscription: EventTaskSubscription(
        subscriptionId: 'clarification_resolution',
        taskType: 'clarification_resolution_task',
        payloadBuilder: (_, event) {
          final p = event.payload as ClarificationAnsweredPayload;
          return Future.value({'request_id': p.requestId});
        },
      ),
    );
  }

  Future<void> _ensureInitialized() async {
    // We double check if a user is logged in now, and if we need to re-init.
    final currentUser = await UserStorage.getUserId();

    // If we are already initializing (or have initialized) for this user, return the existing future.
    // This prevents infinite loops when multiple calls happen while initialization is in progress.
    if (_targetUserIdForInit == currentUser && _initFuture != null) {
      return _initFuture!;
    }

    _logger.info(
      'Re-initializing MemexRouter. Previous Target: $_targetUserIdForInit, New Target: $currentUser',
    );

    _targetUserIdForInit = currentUser;
    _initFuture = _init();
    return _initFuture!;
  }

  /// External hook to force switch user (e.g. on login)
  Future<void> switchUser(String userId) async {
    _logger.info('Switching user to $userId');
    _targetUserIdForInit = null;
    _initFuture = null;
    await _ensureInitialized();
  }

  /// Apply latest per-user workspace storage configuration immediately.
  /// Rebuilds card cache for current user so reads reflect new workspace root.
  Future<void> applyWorkspaceStorageChange() async {
    final userId = await UserStorage.getUserId();
    final dataRoot = await UserStorage.resolveDataRoot(userId);
    await FileSystemService.init(dataRoot);
    if (userId != null && userId.isNotEmpty) {
      try {
        await FileSystemService.instance.rebuildCardCache(userId);
      } catch (e) {
        _logger.warning('Failed to rebuild cache after storage switch: $e');
      }
    }
  }

  Future<BackupSnapshot?> maybeRunAutoBackup({
    required String trigger,
    bool force = false,
  }) async {
    await _ensureInitialized();
    return BackupService.maybeCreateAutoBackup(trigger: trigger, force: force);
  }

  void scheduleAutoBackupCheck({required String trigger}) {
    unawaited(
      maybeRunAutoBackup(trigger: trigger)
          .catchError((Object e, StackTrace st) {
        _logger.warning('Automatic backup check failed: $e', e, st);
        return null;
      }),
    );
  }

  void scheduleAutoCloudSyncCheck() {
    unawaited(
      MemoryDataSyncService.maybeAutoUploadToCloud()
          .catchError((Object e, StackTrace st) {
        _logger.warning('Automatic cloud sync check failed: $e', e, st);
      }),
    );
  }

  /// Clear init state and stop executor on logout so next login re-inits for new user.
  void resetForLogout() {
    _logger.info('Resetting MemexRouter for logout');
    _targetUserIdForInit = null;
    _initFuture = null;
    LocalTaskExecutor.instance.stop();
    SearchService.instance.reset();
  }

  void dispose() {
    LocalTaskExecutor.instance.stop();
  }

  AgentActivityService get agentActivityService =>
      LocalAgentActivityService.instance;

  Future<String?> getToken() async {
    return null;
  }

  Future<Map<String, dynamic>> submitInput({
    String? text,
    List<XFile> images = const [],
    String? audioPath,
    String? textHash,
    List<String>? imageHashes,
    String? audioHash,
  }) async {
    await _ensureInitialized();
    _logger.info(
      'LocalMode: submitInput called. Text: $text, Images: ${images.length}, Audio: $audioPath',
    );

    final content = <Map<String, dynamic>>[];

    // Add Text
    if (text != null && text.isNotEmpty) {
      content.add({'type': 'text', 'text': text, 'client_hash': textHash});
    }

    // Add Images
    for (var i = 0; i < images.length; i++) {
      final image = images[i];
      final hash = (imageHashes != null && i < imageHashes.length)
          ? imageHashes[i]
          : null;

      // Local Optimization: Pass file path directly
      content.add({
        'type': 'image_url',
        'client_hash': hash,
        'image_url': {'filePath': image.path},
      });
    }

    // Add Audio
    if (audioPath != null) {
      final audioFile = File(audioPath);
      if (await audioFile.exists()) {
        // Local Optimization: Pass file path directly
        content.add({
          'type': 'input_audio',
          'client_hash': audioHash,
          'input_audio': {'filePath': audioPath},
        });
      }
    }

    // Get current user ID
    final userId = await UserStorage.getUserId();
    if (userId == null) {
      throw Exception('User not logged in, cannot submit local data');
    }

    return submit_input_endpoint.submitInput(userId, content);
  }

  Future<List<String>> checkProcessedHashes(List<String> hashes) async {
    await _ensureInitialized();
    if (hashes.isEmpty) return [];

    final userId = await UserStorage.getUserId();
    if (userId == null) return hashes;

    return submit_input_endpoint.checkUnprocessedHashes(userId, hashes);
  }

  Future<Result<List<TagModel>>> fetchTags() async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info('LocalMode: fetchTags called');
      return getTags();
    });
  }

  Future<List<TagModel>> fetchTagsByPeriod({
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    await _ensureInitialized();
    _logger.info(
      'LocalMode: fetchTagsByPeriod called: dateFrom=$dateFrom, dateTo=$dateTo',
    );

    // Get all cards in the period with a large limit to capture all tags
    final cards = await getTimelineCards(
      page: 1,
      limit: 1000, // Large limit to get all cards in period
      dateFrom: dateFrom,
      dateTo: dateTo,
    );

    // Extract unique tag names from cards
    final Set<String> uniqueTagNames = {};
    for (final card in cards) {
      uniqueTagNames.addAll(card.tags);
    }

    // Get all tag definitions
    final allTags = await getTags();

    // Filter to only tags that exist in the period
    return allTags.where((tag) => uniqueTagNames.contains(tag.name)).toList();
  }

  Future<Result<List<TimelineCardModel>>> fetchTimelineCards({
    int page = 1,
    int limit = 20,
    List<String>? tags,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info(
        'LocalMode: fetchTimelineCards called: page=$page, limit=$limit, tags=$tags, dateFrom=$dateFrom, dateTo=$dateTo',
      );
      return getTimelineCards(
        page: page,
        limit: limit,
        tags: tags,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );
    });
  }

  Future<Result<Map<String, dynamic>>> fetchAggregatedTimeline({
    required String groupBy,
    int page = 1,
    int limit = 20,
    List<String>? tags,
  }) async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info(
        'LocalMode: fetchAggregatedTimeline called: groupBy=$groupBy, page=$page, limit=$limit, tags=$tags',
      );
      return getAggregatedTimeline(
        groupBy: groupBy,
        page: page,
        limit: limit,
        tags: tags,
      );
    });
  }

  Future<List<TimelineCardModel>> fetchCardByIds(List<String> ids) async {
    await _ensureInitialized();
    _logger.info('LocalMode: fetchCardByIds called: ids=$ids');
    return getCardsByIds(ids);
  }

  Future<Result<List<CalendarDay>>> fetchCalendarData(
    int fromTimestamp,
    int toTimestamp,
  ) async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info(
        'LocalMode: fetchCalendarData called: fromTimestamp=$fromTimestamp, toTimestamp=$toTimestamp',
      );
      return getCalendarData(fromTimestamp, toTimestamp);
    });
  }

  Future<TimelineCardModel?> fetchTimelineCard(String cardId) async {
    await _ensureInitialized();
    _logger.info('LocalMode: fetchTimelineCard called: cardId=$cardId');
    return getTimelineCard(cardId);
  }

  Future<CardDetailModel> fetchCardDetail(String cardId) async {
    await _ensureInitialized();
    _logger.info('LocalMode: fetchCardDetail called: cardId=$cardId');
    return getCardDetail(cardId);
  }

  Future<AppUpdateSettings> getAppUpdateSettings() {
    return AppUpdateService.instance.loadSettings();
  }

  Future<void> saveAppUpdateSettings(AppUpdateSettings settings) {
    return AppUpdateService.instance.saveSettings(settings);
  }

  Future<Result<AppUpdateCheckResult>> checkEarlyUpdate({
    bool manual = false,
    bool respectWifi = false,
  }) {
    return runResult(() {
      return AppUpdateService.instance.checkForUpdate(
        manual: manual,
        respectWifi: respectWifi,
      );
    });
  }

  Future<Result<AppUpdateDownloadResult>> downloadEarlyUpdate(
    AppUpdateInfo update, {
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) {
    return runResult(() {
      return AppUpdateService.instance.downloadUpdate(
        update,
        onProgress: onProgress,
      );
    });
  }

  Future<Result<AppUpdateInstallResult>> installEarlyUpdate(String apkPath) {
    return runResult(() => AppUpdateService.instance.installUpdate(apkPath));
  }

  Future<void> enqueueTask({
    required String taskType,
    required Map<String, dynamic> payload,
    String? bizId,
  }) async {
    await _ensureInitialized();
    _logger.info('LocalMode: enqueueTask called: type=$taskType, bizId=$bizId');

    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      await LocalTaskExecutor.instance.enqueueTask(
        userId: userId,
        taskType: taskType,
        payload: payload,
        bizId: bizId,
      );
    } catch (e) {
      _logger.severe('Failed to enqueue task $taskType: $e');
      rethrow;
    }
  }

  /// Clears all workspace data except the Facts directory.
  /// Only the Facts directory is kept; all other subdirectories are deleted.
  Future<void> clearData() async {
    await _ensureInitialized();
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) throw Exception('User not logged in');

      final workspacePath = fileSystemService.getWorkspacePath(userId);
      final workspaceDir = Directory(workspacePath);
      if (!await workspaceDir.exists()) return;

      await for (final entity in workspaceDir.list(followLinks: false)) {
        if (entity is Directory) {
          final name = path.basename(entity.path);
          if (name == 'Facts') continue;
          try {
            await entity.delete(recursive: true);
            _logger.info('Deleted directory: ${entity.path}');
          } catch (e) {
            _logger.warning('Failed to delete ${entity.path}: $e');
          }
        }
      }

      // Clear card cache
      await AppDatabase.instance.cardDao.clearCache();
    } catch (e) {
      _logger.severe('Failed to clear data locally: $e');
      rethrow;
    }
  }

  Future<bool> deleteCard(String id) async {
    await _ensureInitialized();
    _logger.info('LocalMode: deleteCard called: id=$id');

    try {
      return await deleteCardEndpoint(id);
    } catch (e) {
      _logger.severe('Failed to delete card $id: $e');
      return false;
    }
  }

  Future<bool> updateCardUiConfig(
    String cardId,
    int configIndex,
    Map<String, dynamic> data,
  ) async {
    await _ensureInitialized();
    _logger.info(
      'LocalMode: updateCardUiConfig called: cardId=$cardId, index=$configIndex',
    );

    try {
      return await update_config_endpoint.updateCardUiConfigEndpoint(
        cardId,
        configIndex,
        data,
      );
    } catch (e) {
      _logger.severe('Failed to update card ui config for $cardId: $e');
      return false;
    }
  }

  Future<bool> updateCardTime(String cardId, int timestamp) async {
    await _ensureInitialized();
    _logger.info(
      'LocalMode: updateCardTime called: cardId=$cardId, timestamp=$timestamp',
    );

    try {
      return await updateCardTimeEndpoint(cardId, timestamp);
    } catch (e) {
      _logger.severe('Failed to update card time for $cardId: $e');
      return false;
    }
  }

  Future<bool> updateCardLocation(
    String cardId,
    double lat,
    double lng,
    String name,
  ) async {
    await _ensureInitialized();
    _logger.info(
      'LocalMode: updateCardLocation called: cardId=$cardId, lat=$lat, lng=$lng, name=$name',
    );

    try {
      return await updateCardLocationEndpoint(cardId, lat, lng, name);
    } catch (e) {
      _logger.severe('Failed to update card location for $cardId: $e');
      return false;
    }
  }

  Future<Result<List<Map<String, dynamic>>>> fetchChatSessions({
    String? agentName,
    int? limit,
  }) async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info(
        'LocalMode: fetchChatSessions called: agentName=$agentName, limit=$limit',
      );
      return await chat_endpoint.fetchChatSessionsEndpoint(
        agentName: agentName,
        limit: limit,
      );
    });
  }

  Future<Map<String, dynamic>> fetchChatSessionDetail(String sessionId) async {
    await _ensureInitialized();
    _logger.info(
      'LocalMode: fetchChatSessionDetail called: sessionId=$sessionId',
    );

    try {
      return await chat_endpoint.fetchChatSessionDetailEndpoint(sessionId);
    } catch (e) {
      _logger.severe('Failed to fetch chat session detail: $e');
      rethrow;
    }
  }

  Future<bool> deleteChatSession(String sessionId) async {
    await _ensureInitialized();
    _logger.info('LocalMode: deleteChatSession called: sessionId=$sessionId');

    try {
      return await chat_endpoint.deleteChatSessionEndpoint(sessionId);
    } catch (e) {
      _logger.severe('Failed to delete chat session: $e');
      return false;
    }
  }

  Future<Result<List<CharacterModel>>> fetchCharacters() async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info('LocalMode: fetchCharacters called');
      return await getCharacters();
    });
  }

  Future<CharacterModel> fetchCharacter(String characterId) async {
    await _ensureInitialized();
    _logger.info('LocalMode: fetchCharacter called: characterId=$characterId');

    try {
      return await getCharacter(characterId);
    } catch (e) {
      _logger.severe('Failed to fetch character $characterId: $e');
      rethrow;
    }
  }

  Future<CharacterModel> createCharacter({
    required String name,
    required List<String> tags,
    required String persona,
  }) async {
    await _ensureInitialized();
    _logger.info('LocalMode: createCharacter called: name=$name');

    try {
      return await createCharacterEndpoint(
        name: name,
        tags: tags,
        persona: persona,
      );
    } catch (e) {
      _logger.severe('Failed to create character: $e');
      rethrow;
    }
  }

  Future<CharacterModel> updateCharacter({
    required String characterId,
    String? name,
    List<String>? tags,
    String? persona,
  }) async {
    await _ensureInitialized();
    _logger.info('LocalMode: updateCharacter called: characterId=$characterId');

    try {
      return await updateCharacterEndpoint(
        characterId: characterId,
        name: name,
        tags: tags,
        persona: persona,
      );
    } catch (e) {
      _logger.severe('Failed to update character $characterId: $e');
      rethrow;
    }
  }

  Future<bool> deleteCharacter(String characterId) async {
    await _ensureInitialized();
    _logger.info('LocalMode: deleteCharacter called: characterId=$characterId');

    try {
      return await deleteCharacterEndpoint(characterId);
    } catch (e) {
      _logger.severe('Failed to delete character $characterId: $e');
      rethrow;
    }
  }

  Future<Result<bool>> setCharacterEnabled(
    String characterId,
    bool enabled,
  ) async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info(
        'LocalMode: setCharacterEnabled called: characterId=$characterId, enabled=$enabled',
      );
      return await setCharacterEnabledEndpoint(characterId, enabled);
    });
  }

  Future<Result<bool>> setCharacterPrimary(String characterId) async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info(
        'LocalMode: setCharacterPrimary called: characterId=$characterId',
      );
      return await setCharacterPrimaryEndpoint(characterId);
    });
  }

  Future<bool> reportDailyHealthSummary(
    Map<String, Map<String, dynamic>> dailySummary,
  ) async {
    await _ensureInitialized();
    _logger.info(
      'LocalMode: reportDailyHealthSummary called: ${dailySummary.length} days',
    );

    try {
      // We will create health_endpoint.dart to handle this
      return await health_endpoint.reportDailyHealthSummaryEndpoint(
        dailySummary,
      );
    } catch (e) {
      _logger.severe('Failed to report daily health summary: $e');
      return false;
    }
  }

  Future<Result<Map<String, dynamic>>> getMemory() async {
    return runResult(() async {
      await _ensureInitialized();
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        throw Exception('User ID not found');
      }

      final systemPath = fileSystemService.getSystemPath(userId);
      final memoryPath = path.join(systemPath, 'memory', 'memory.json');
      final file = File(memoryPath);

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isEmpty) {
          return {'archived_memory': '', 'recent_buffer': []};
        }
        return jsonDecode(content) as Map<String, dynamic>;
      }
      return {'archived_memory': '', 'recent_buffer': []};
    });
  }

  Future<Result<List<Map<String, dynamic>>>> getRecentPkmFiles({
    int limit = 10,
  }) async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info('LocalMode: getRecentPkmFiles called: limit=$limit');
      final userId = await UserStorage.getUserId();
      if (userId == null) return <Map<String, dynamic>>[];
      return await fileSystemService.getRecentPkmFiles(userId, limit: limit);
    });
  }

  Future<Result<Map<String, int>>> countPkmItems(List<String> paths) async {
    return runResult(() async {
      await _ensureInitialized();
      final userId = await UserStorage.getUserId();
      if (userId == null) return <String, int>{};
      return await fileSystemService.countPkmItems(userId, paths);
    });
  }

  Future<Result<Map<String, dynamic>>> listPkmDirectory({String? path}) async {
    return runResult(() async {
      await _ensureInitialized();
      _logger.info('LocalMode: listPkmDirectory called: path=$path');
      return await pkm_endpoint.listPkmDirectory(path: path);
    });
  }

  Future<Result<List<Map<String, dynamic>>>> searchPkmFiles(
    String query,
  ) async {
    return runResult(() async {
      await _ensureInitialized();
      final userId = await UserStorage.getUserId();
      if (userId == null) return <Map<String, dynamic>>[];
      return await SearchService.instance.searchPkmFiles(userId, query);
    });
  }

  /// Search timeline cards using FTS5 full-text search.
  ///
  /// Returns hydrated [TimelineCardModel] list, same format as [fetchTimelineCards].
  Future<Result<List<TimelineCardModel>>> searchCards(
    String query, {
    int limit = 50,
  }) async {
    return runResult(() async {
      await _ensureInitialized();
      final userId = await UserStorage.getUserId();
      if (userId == null) return <TimelineCardModel>[];

      final ftsResults = await SearchService.instance.searchCards(
        query,
        limit: limit,
      );

      final cards = <TimelineCardModel>[];
      for (final r in ftsResults) {
        final factId = r['fact_id'] as String;
        try {
          final card = await hydrateCard(userId, factId);
          if (card != null) cards.add(card);
        } catch (e) {
          _logger.warning('Failed to hydrate search result: $e');
        }
      }
      return cards;
    });
  }

  /// Rebuild the PKM FTS index (e.g. after import or manual trigger).
  Future<void> rebuildPkmFtsIndex() async {
    await _ensureInitialized();
    final userId = await UserStorage.getUserId();
    if (userId == null) return;
    await SearchService.instance.rebuildPkmFtsIndex(userId);
  }

  /// Rebuild all FTS indexes (card + PKM). Intended for debugging / manual trigger.
  Future<void> rebuildAllFtsIndexes() async {
    await _ensureInitialized();
    final userId = await UserStorage.getUserId();
    if (userId == null) return;
    await SearchService.instance.rebuildAll(userId);
  }

  Future<Map<String, dynamic>> readPkmFile(String filePath) async {
    await _ensureInitialized();
    _logger.info('LocalMode: readPkmFile called: path=$filePath');

    try {
      return await pkm_endpoint.readPkmFileEndpoint(filePath);
    } catch (e) {
      _logger.severe('Failed to read PKM file: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getAggregatedStatistics({
    DateTime? startDate,
    DateTime? endDate,
    String? scene,
  }) async {
    await _ensureInitialized();
    _logger.info('LocalMode: getAggregatedStatistics called');

    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        _logger.warning(
          'getAggregatedStatistics called without logged in user, returning empty',
        );
        return {};
      }

      return await LLMCallRecordService.instance.getAggregatedStatistics(
        userId: userId,
        startDate: startDate,
        endDate: endDate,
        scene: scene,
      );
    } catch (e) {
      _logger.severe('Failed to get aggregated statistics: $e');
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getAgentUsages({
    DateTime? startDate,
    DateTime? endDate,
    String? scene,
  }) async {
    await _ensureInitialized();
    _logger.info('LocalMode: getAgentUsages called');

    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        return [];
      }

      return await LLMCallRecordService.instance.getAllRecords(
        userId: userId,
        startDate: startDate,
        endDate: endDate,
        scene: scene,
      );
    } catch (e) {
      _logger.severe('Failed to get agent usages: $e');
      return [];
    }
  }

  Future<bool> uploadWorkspace(String targetUserId) async {
    await _ensureInitialized();
    _logger.info('LocalMode: uploadWorkspace not supported (client-only)');
    return false;
  }

  Future<List<Map<String, dynamic>>> listSharedWorkspaces() async {
    await _ensureInitialized();
    return [];
  }

  Future<bool> downloadWorkspace(
    String workspaceName, {
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    await _ensureInitialized();
    _logger.info('LocalMode: downloadWorkspace not supported (client-only)');
    return false;
  }

  Future<List<LLMConfig>> getLLMConfigs() => UserStorage.getLLMConfigs();

  Future<String?> getUserAvatar() async {
    await _ensureInitialized();
    final userId = await UserStorage.getUserId();
    if (userId == null || userId.isEmpty) return null;

    final meta = await fileSystemService.readProfileMeta(userId);
    var avatar = meta['avatar'] as String?;
    if (avatar == null || avatar.isEmpty) {
      final legacyAvatar = await UserStorage.getUserAvatar();
      if (legacyAvatar != null && legacyAvatar.isNotEmpty) {
        meta['avatar'] = legacyAvatar;
        await fileSystemService.writeProfileMeta(userId, meta);
        avatar = legacyAvatar;
      }
    }
    if (avatar == null || avatar.isEmpty) {
      return null;
    }

    final lower = avatar.toLowerCase();
    final isRelativeImagePath = !avatar.startsWith('/') &&
        (lower.endsWith('.png') ||
            lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg') ||
            lower.endsWith('.webp'));

    if (isRelativeImagePath) {
      return fileSystemService.toAbsolutePath(avatar);
    }
    return avatar;
  }

  Future<void> updateUserAvatar(String avatar) async {
    await _ensureInitialized();
    final userId = await UserStorage.getUserId();
    if (userId == null || userId.isEmpty) {
      throw Exception('User not logged in');
    }

    final meta = await fileSystemService.readProfileMeta(userId);
    meta['avatar'] = avatar;
    await fileSystemService.writeProfileMeta(userId, meta);
  }

  Future<void> saveLLMConfigs(List<LLMConfig> configs) async {
    await UserStorage.saveLLMConfigs(configs);
    // Legacy: on first valid LLM config we used to call reprocessPendingCards()
    // to re-run the Memex card pipeline (card -> pkm -> comment). That pipeline
    // has been retired, so there is nothing to reprocess here anymore.
  }

  Future<void> resetLLMConfigs() => UserStorage.resetLLMConfigs();

  Future<String> getDefaultLLMConfigKey() =>
      UserStorage.getDefaultLLMConfigKey();

  Future<void> setDefaultLLMConfigKey(String configKey) =>
      UserStorage.setDefaultLLMConfigKey(configKey);

  Future<AgentConfig> getAgentConfig(String agentId) =>
      UserStorage.getAgentConfig(agentId);

  Future<void> saveAgentConfig(String agentId, AgentConfig config) =>
      UserStorage.saveAgentConfig(agentId, config);

  Future<void> saveOpenAiAuth(Map<String, dynamic> authData) async {
    // local_todo: to be implemented
    // Usually local mode doesn't need to sync to backend, but we can implement it as a no-op
    // or log it here.
    return;
  }

  Future<void> resetAllAgentConfigs() => UserStorage.resetAllAgentConfigs();

  Future<Result<void>> refreshScheduleAggregation() => runResultVoid(() async {
        await _ensureInitialized();
        final userId = await UserStorage.getUserId();
        if (userId == null) {
          throw Exception('User not logged in');
        }

        await GlobalEventBus.instance.publish(
          userId: userId,
          event: SystemEvent(
            type: SystemEventTypes.scheduleAggregationRequested,
            source: 'memex_router.refreshScheduleAggregation',
            payload: const {},
          ),
        );
      });

  Future<List<Task>> getTasks({int limit = 10, int offset = 0}) =>
      LocalTaskExecutor.instance.getTasks(limit: limit, offset: offset);

  Future<TaskActivitySnapshot> getTaskActivitySnapshot() async {
    await _ensureInitialized();
    return LocalTaskExecutor.instance.getTaskActivitySnapshot();
  }

  // ---------------------------------------------------------------------------
  // Card-detail notification helpers
  // ---------------------------------------------------------------------------

  /// Resolve the [CardData] for a notification's subject card.
  /// Returns `null` if the card no longer exists or the user is not logged in.
  Future<CardData?> resolveCardForNotification(String factId) async {
    await _ensureInitialized();
    final userId = await UserStorage.getUserId();
    if (userId == null) return null;
    return FileSystemService.instance.readCardFile(userId, factId);
  }

  /// Dismiss a user notification by its primary key.
  Future<void> dismissNotification(String id) async {
    await _ensureInitialized();
    await UserNotificationService.instance.dismiss(id);
  }

  /// Register a card detail page as viewing [factId] (foreground suppression).
  void registerCardDetailForeground(String factId) {
    CardDetailNotifier.instance.registerForeground(factId);
  }

  /// Unregister a card detail page for [factId].
  void unregisterCardDetailForeground(String factId) {
    CardDetailNotifier.instance.unregisterForeground(factId);
  }

  /// Dismiss any pending card-detail notification after the user has viewed
  /// the card's latest content.
  Future<void> dismissCardDetailOnViewed(String factId) async {
    final userId = await UserStorage.getUserId();
    if (userId == null) return;
    await CardDetailNotifier.instance.dismissOnViewed(userId, factId);
  }
}
