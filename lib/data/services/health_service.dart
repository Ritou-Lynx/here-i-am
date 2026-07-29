import 'dart:io';

import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';
import 'package:workmanager/workmanager.dart'; // Added for Workmanager
import 'dart:isolate'; // Added for Isolate
import 'package:flutter/foundation.dart'; // Added for debugPrint
import 'package:memex/data/services/file_logger_service.dart'; // Added
import 'package:memex/db/app_database.dart'; // Added for checkin
import 'health_strategies.dart';
import 'checkin_service.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/data/services/background_task_drain_service.dart';
import 'package:memex/data/services/background_task_foreground_service.dart';
import 'package:memex/data/services/companion_foreground_task.dart';
import 'package:memex/agent/built_in_tools/initiate_call_tool.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/notification_service.dart';
import 'package:memex/data/memory_v3/services/dreaming_scheduler_service.dart';
import 'package:memex/data/memory_v3/services/dreaming_orchestrator_service.dart';
import 'package:memex/utils/user_storage.dart';

/// Configuration for handling a specific Health Data Type
class HealthStrategyConfig {
  final HealthDataType type;
  final String prefKeySuffix; // e.g., 'steps' -> last_report_time_steps
  final HealthDataFetcher primaryFetcher;
  final HealthDataFetcher? fallbackFetcher;
  final int reportIntervalMinutes;

  HealthStrategyConfig({
    required this.type,
    required this.prefKeySuffix,
    required this.primaryFetcher,
    this.fallbackFetcher,
    this.reportIntervalMinutes = 30,
  });
}

/// Generic Health Service
class HealthService {
  static final HealthService _instance = HealthService._internal();
  factory HealthService() => _instance;
  HealthService._internal() {
    _registerStrategies();
  }

  final Logger _logger = getLogger('HealthService');
  // Registry
  final Map<HealthDataType, HealthStrategyConfig> _configs = {};

  /// Returns the list of health data types registered for the current platform.
  List<HealthDataType> get registeredTypes => _configs.keys.toList();

  void _registerStrategies() {
    if (Platform.isAndroid) {
      // Android: Only steps via Pedometer (Health Connect permissions removed
      // to comply with Google Play policy).
      _configs[HealthDataType.STEPS] = HealthStrategyConfig(
        type: HealthDataType.STEPS,
        prefKeySuffix: 'steps',
        primaryFetcher: PedometerFetcher(),
        reportIntervalMinutes: 1,
      );
    } else {
      // iOS: Use HealthKit for accurate step count data.
      // Pedometer fallback removed — CMPedometer can crash on some devices/debug modes.
      _configs[HealthDataType.STEPS] = HealthStrategyConfig(
        type: HealthDataType.STEPS,
        prefKeySuffix: 'steps',
        primaryFetcher: HealthKitFetcher(),
        reportIntervalMinutes: 1,
      );
    }

    // Initialize Background Task for Pedometer (Ensure it's registered on app start)
    final stepsFallback = _configs[HealthDataType.STEPS]?.fallbackFetcher;
    final stepsPrimary = _configs[HealthDataType.STEPS]?.primaryFetcher;
    if (stepsFallback is PedometerFetcher) {
      stepsFallback.ensureBackgroundTaskRegistered();
    } else if (stepsPrimary is PedometerFetcher) {
      stepsPrimary.ensureBackgroundTaskRegistered();
    }
  }

  // --- Public API ---

  /// Request all necessary permissions in one batch prompt
  Future<void> requestAllPermissions() async {
    try {
      if (Platform.isAndroid) {
        // Android: only Pedometer
        if (_configs.containsKey(HealthDataType.STEPS)) {
          final primary = _configs[HealthDataType.STEPS]?.primaryFetcher;
          if (primary != null) {
            await primary.requestPermissions(HealthDataType.STEPS);
          }
        }
        return;
      }

      // iOS: request HealthKit authorization for registered types
      final health = Health();
      final typesToRequest = _configs.values
          .where((c) => c.primaryFetcher is HealthKitFetcher)
          .map((c) => c.type)
          .toList();

      if (typesToRequest.isNotEmpty) {
        _logger.info(
            'Requesting HealthKit permissions for ${typesToRequest.length} types...');
        final hasPermissions = await health.hasPermissions(typesToRequest);
        if (hasPermissions != true) {
          await health.requestAuthorization(typesToRequest);
        }
      }

      // Also request Pedometer permission as fallback
      if (_configs.containsKey(HealthDataType.STEPS)) {
        final fallback = _configs[HealthDataType.STEPS]?.fallbackFetcher;
        if (fallback != null) {
          await fallback.requestPermissions(HealthDataType.STEPS);
        }
      }
    } catch (e) {
      _logger.severe('Error batch requesting health permissions: $e');
    }
  }

  /// Generic Entry Point
  /// Returns data if reporting is needed and successful, null otherwise.
  Future<T?> checkAndPrepareData<T>(HealthDataType type) async {
    final config = _configs[type];
    if (config == null) {
      _logger.warning('No strategy configured for $type');
      return null;
    }

    try {
      _logger.info('Checking ${config.type}...');

      // 1. Check Interval
      if (!await _shouldReport(config)) {
        _logger.info('Not time to report ${config.type} yet, skipping.');
        return null; // Not time yet
      }
      _logger.info('Time to report ${config.type}, proceeding to fetch...');

      // 2. Fetch Data
      final data = await _fetchWithFallback<T>(config);

      // Check if data is empty (Logic depends on T, assuming Map or List)
      bool isEmpty = false;
      if (data is Map) isEmpty = data.isEmpty;
      if (data is List) isEmpty = data.isEmpty;

      if (data == null || isEmpty) {
        _logger.info('No data found for ${config.type}.');
        return null;
      }

      // 3. Mark check time
      await _saveLastCheckTime(config);

      return data;
    } catch (e) {
      _logger.severe('Error processing ${config.type}: $e');
      return null;
    }
  }

  /// Updates the "Last Reported Date" cursor for a specific type.
  /// This should be called by the UI/Main logic *after* successful API upload.
  Future<void> markReportSuccess(HealthDataType type, dynamic data) async {
    final config = _configs[type];
    if (config == null) return;

    // Update cursor for date maps
    if (data is Map && data.isNotEmpty) {
      await _markGenericSuccess(config, data as Map<String, dynamic>);
    }
  }

  // --- Internal Engine ---

  Future<T?> _fetchWithFallback<T>(HealthStrategyConfig config) async {
    // Determine Time Range
    final range = await _getReportTimeRange(config);
    final start = range.start;
    final end = range.end;

    // Primary
    _logger.info(
        'Trying Primary: ${config.primaryFetcher.name} for ${config.type}');
    try {
      final hasPermission =
          await config.primaryFetcher.requestPermissions(config.type);
      _logger.info('Primary permission result: $hasPermission');
      if (hasPermission) {
        _logger.info('Fetching data from primary (range: $start to $end)...');
        final data =
            await config.primaryFetcher.fetchData(config.type, start, end);

        bool hasData = false;
        if (data is Map) hasData = data.isNotEmpty;
        if (data is List) hasData = data.isNotEmpty;
        _logger.info(
            'Primary returned data: hasData=$hasData, type=${data.runtimeType}');

        if (hasData) {
          return data as T;
        } else {
          _logger.info('Primary returned empty.');
        }
      } else {
        _logger.warning('Primary denied.');
      }
    } catch (e) {
      _logger.warning('Primary failed: $e');
    }

    // Fallback
    if (config.fallbackFetcher != null) {
      _logger.info(
          'Trying Fallback: ${config.fallbackFetcher!.name} for ${config.type}');
      try {
        if (await config.fallbackFetcher!.requestPermissions(config.type)) {
          final data =
              await config.fallbackFetcher!.fetchData(config.type, start, end);
          return data as T;
        }
      } catch (e) {
        _logger.warning('Fallback failed: $e');
      }
    }

    return null; // Both failed
  }

  Future<bool> _shouldReport(HealthStrategyConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'last_report_time_${config.prefKeySuffix}';
    final lastStr = prefs.getString(key);
    if (lastStr == null) return true;

    final last = DateTime.parse(lastStr);
    return DateTime.now().difference(last).inMinutes >=
        config.reportIntervalMinutes;
  }

  Future<void> _saveLastCheckTime(HealthStrategyConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'last_report_time_${config.prefKeySuffix}';
    await prefs.setString(key, DateTime.now().toIso8601String());
  }

  Future<({DateTime start, DateTime end})> _getReportTimeRange(
      HealthStrategyConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'last_reported_date_${config.prefKeySuffix}';
    final lastDateStr = prefs.getString(key);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endOfToday = today.add(const Duration(days: 1));

    DateTime start;
    if (lastDateStr != null) {
      final lastDate = DateTime.parse(lastDateStr);
      start = lastDate.add(const Duration(days: 1));
    } else {
      start = today.subtract(const Duration(days: 7));
    }
    return (start: start, end: endOfToday);
  }

  // --- Type-Specific Helpers ---

  Future<void> _markGenericSuccess(
      HealthStrategyConfig config, Map<String, dynamic> dataByDate) async {
    if (dataByDate.isEmpty) return;

    final now = DateTime.now();
    final todayStr = now.toIso8601String().split('T')[0];
    final dates = dataByDate.keys.toList()..sort();

    String? lastPastDateStr;
    for (var d in dates) {
      if (d.compareTo(todayStr) < 0) lastPastDateStr = d;
    }

    if (lastPastDateStr != null) {
      final prefs = await SharedPreferences.getInstance();
      final key = 'last_reported_date_${config.prefKeySuffix}';
      await prefs.setString(key, lastPastDateStr);
      _logger.info('Updated cursor for ${config.type} to $lastPastDateStr');
    }
  }
}

// MUST be top-level function for Workmanager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // 0. Initialize Logger in Background Isolate
    // Use print() first to ensure we can see it in console/ADB even if file logger fails
    debugPrint(
        'BackgroundCallback: Starting... (Isolate: ${Isolate.current.debugName})');

    // Define logger early so it can be used in try block
    final logger = getLogger('PedometerFetcher');

    try {
      await setupLogger();
      logger.severe('BackgroundCallback: Logger setup complete');
    } catch (e) {
      debugPrint('BackgroundCallback: Logger setup failed: $e');
    }

    try {
      if (task == BackgroundTaskDrainService.taskName) {
        try {
          final started = await BackgroundTaskForegroundService.triggerDrain();
          if (started) {
            return Future.value(true);
          }
        } catch (e) {
          debugPrint(
              'Background task drain: failed to start foreground service: $e');
        }
        return Future.value(
          await BackgroundTaskDrainService.runFromWorkmanager(),
        );
      }

      if (task == CheckinService.checkinTaskName) {
        // ---------- Checkin pulse ----------
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('current_user_id');
        if (userId == null) {
          debugPrint('Checkin: no user ID stored, skipping');
          return Future.value(false);
        }
        if (!AppDatabase.isInitialized) {
          await AppDatabase.init(userId);
        }
        await UserStorage.initL10n();
        // Hard foreground gate: if the app is active, skip entirely.
        // maybeEnqueueCheckin has its own gate, but hasPendingWork does not —
        // this single check covers both before we trigger the visible notification.
        final hasDueReminder = await CheckinService.instance.hasDueReminders();
        if (await CheckinService.instance.isAppInForeground() &&
            !hasDueReminder) {
          debugPrint(
              'Checkin: app in foreground, skipping WorkManager trigger');
          return Future.value(false);
        }

        // ── Last-resort: due call reminders ──
        // If the alarm callback missed them (isolate spawn failure) and the
        // foreground service is dead, this 15-min periodic task is the final
        // safety net. Queue the call directly + show a notification.
        final wmDueCalls =
            await CheckinService.instance.claimDueCallReminders();
        if (wmDueCalls.isNotEmpty) {
          final wmChar =
              await CharacterService.instance.getPrimaryCompanion(userId);
          if (wmChar != null) {
            await queuePendingCall(
              characterId: wmChar.id,
              openingMessage:
                  alarmOpeningForDueCall(wmDueCalls.first.body),
            );
            try {
              await NotificationService.instance.initialize();
              await NotificationService.instance.showCallNotification(
                title: wmChar.name,
                body: '想给你打个电话 ☎️',
                payload: 'call:${wmChar.id}',
              );
            } catch (e) {
              debugPrint('Checkin WM: call notification failed: $e');
            }
            debugPrint('Checkin WM: call reminder handled directly');
          }
          for (final c in wmDueCalls) {
            await CheckinService.instance.markStatus(c.id, 'done');
          }
        }
        final enqueued = await CheckinService.instance.maybeEnqueueCheckin();
        debugPrint('Checkin pulse: ${enqueued ? "enqueued" : "skipped"}');
        // Also run if there's any pending work (existing checkin or due reminder).
        final hasPendingWork = await CheckinService.instance.hasPendingWork();
        if (!enqueued && !hasPendingWork) return Future.value(false);
        debugPrint(
            'Checkin: proceeding via ForegroundService (enqueued=$enqueued, hasPendingWork=$hasPendingWork)');

        // Start foreground service to run the agent.
        // The foreground service is immune to Samsung Freecess — the WorkManager
        // isolate only needs to survive long enough to fire startService(), then
        // the OS-managed foreground service takes over independently.
        try {
          await CompanionForegroundService.initialize();
          await CompanionForegroundService.triggerCheckin();
          debugPrint('Checkin: foreground service triggered successfully');
        } catch (e) {
          debugPrint('Checkin: failed to start foreground service: $e');
        }
        return Future.value(true);
      }

      if (task == DreamingSchedulerService.dailyBatchTaskName) {
        // ---------- Daily Dreaming batch ----------
        debugPrint('Dreaming batch: starting background run');
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('current_user_id');
        if (userId == null) {
          debugPrint('Dreaming batch: no user ID, skipping');
          return Future.value(false);
        }
        if (!AppDatabase.isInitialized) {
          await AppDatabase.init(userId);
        }
        if (!DreamingOrchestratorServiceV3.isInitialized) {
          DreamingOrchestratorServiceV3.init(AppDatabase.instance);
        }
        await UserStorage.initL10n();
        final charRow = await AppDatabase.instance
            .customSelect(
              'SELECT character_id FROM persona_chat_messages '
              'ORDER BY timestamp DESC, id DESC LIMIT 1',
            )
            .getSingleOrNull();
        final characterId = charRow?.read<String>('character_id') ?? 'i';
        final ok = await DreamingSchedulerService.runDailyDreamingFromBackground(
          db: AppDatabase.instance,
          characterId: characterId,
        );
        debugPrint('Dreaming batch: ${ok ? "completed" : "skipped"}');
        return Future.value(ok);
      }

      // ---------- Original pedometer logic ----------
      logger.severe('Background task triggered (1h periodic)');
      await PedometerFetcher.backgroundCallbackLogic();
      logger.severe('Background task completed successfully');
      return Future.value(true);
    } catch (e) {
      logger.severe('Error in background task execution: $e');
      return Future.value(false); // Retry if needed
    } finally {
      // Ensure isolate disposes before refresh and close file stream
      // FORCE FLUSH before isolate logic ends
      await FileLoggerService.instance.dispose();
    }
  });
}
