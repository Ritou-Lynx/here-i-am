import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:memex/agent/companion_agent/companion_agent.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/checkin_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/notification_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

/// Top-level entry point invoked by the foreground service isolate.
@pragma('vm:entry-point')
void companionForegroundTaskEntry() {
  FlutterForegroundTask.setTaskHandler(CompanionTaskHandler());
}

/// Foreground Task handler that runs the companion agent checkin.
///
/// Unlike WorkManager/AlarmManager, this is a real Android foreground service —
/// it shows a persistent notification but is immune to Samsung Freecess and
/// Doze-related freezing. The handler runs the checkin once (in onStart),
/// then stops the service.
class CompanionTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[ForegroundTask] onStart fired (starter=$starter)');
    try {
      await setupLogger();
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('current_user_id');
      if (userId == null) {
        debugPrint('[ForegroundTask] no userId, stopping');
        await FlutterForegroundTask.stopService();
        return;
      }

      if (!AppDatabase.isInitialized) {
        await AppDatabase.init(userId);
      }
      await UserStorage.initL10n();

      // Even if no fresh checkin gets enqueued, run if any pending work exists.
      final enqueued = await CheckinService.instance.maybeEnqueueCheckin();
      final hasPendingWork = await CheckinService.instance.hasPendingWork();
      debugPrint(
          '[ForegroundTask] enqueued=$enqueued hasPendingWork=$hasPendingWork');
      if (!enqueued && !hasPendingWork) {
        debugPrint('[ForegroundTask] nothing to do, stopping');
        await FlutterForegroundTask.stopService();
        return;
      }

      final dataRoot = await UserStorage.resolveDataRoot(userId);
      await FileSystemService.init(dataRoot);
      await NotificationService.instance.initialize();

      final character =
          await CharacterService.instance.getPrimaryCompanion(userId);
      if (character == null) {
        debugPrint('[ForegroundTask] no character, stopping');
        await FlutterForegroundTask.stopService();
        return;
      }
      debugPrint('[ForegroundTask] running agent as "${character.name}"');

      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.checkinAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      await CompanionAgent.runBackgroundCheckin(
        client: resources.client,
        modelConfig: resources.modelConfig,
        userId: userId,
        characterId: character.id,
      );
      debugPrint('[ForegroundTask] agent run complete');
    } catch (e, st) {
      debugPrint('[ForegroundTask] error: $e\n$st');
    } finally {
      // Always stop the service so the persistent notification disappears.
      await FlutterForegroundTask.stopService();
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // We don't use periodic events — onStart does the work and stops.
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[ForegroundTask] onDestroy');
  }
}

/// Helper to start the companion foreground service.
class CompanionForegroundService {
  CompanionForegroundService._();

  static const String notificationChannelId = 'companion_foreground';
  static const String notificationChannelName = 'Companion thinking';

  static Future<void> initialize() async {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: notificationChannelId,
        channelName: notificationChannelName,
        channelDescription: 'Brief notification while companion is thinking',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Triggers a one-off checkin via foreground service.
  /// The persistent notification appears for a few seconds while the agent
  /// works, then disappears automatically.
  static Future<void> triggerCheckin() async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      debugPrint('[ForegroundTask] already running, skipping trigger');
      return;
    }
    await FlutterForegroundTask.startService(
      notificationTitle: '闻屿夏在想你',
      notificationText: '正在判断要不要打扰你...',
      callback: companionForegroundTaskEntry,
    );
  }
}
