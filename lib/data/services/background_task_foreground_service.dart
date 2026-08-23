import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:memex/data/services/background_task_drain_runner.dart';
import 'package:memex/data/services/companion_foreground_task.dart';
import 'package:memex/utils/logger.dart';

@pragma('vm:entry-point')
void backgroundTaskForegroundEntry() {
  FlutterForegroundTask.setTaskHandler(BackgroundTaskForegroundHandler());
}

class BackgroundTaskForegroundHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[TaskDrainForeground] onStart fired (starter=$starter)');
    try {
      await setupLogger();
    } catch (_) {}

    try {
      final snapshot = await BackgroundTaskDrainRunner.run(
        maxDuration: BackgroundTaskDrainRunner.foregroundMaxDuration,
        processingResetAge:
            BackgroundTaskDrainRunner.foregroundProcessingResetAge,
        resetProcessingOnStart: true,
      );
      debugPrint(
        '[TaskDrainForeground] drain complete: '
        'pending=${snapshot.pending} processing=${snapshot.processing} '
        'retrying=${snapshot.retrying}',
      );
      if (snapshot.hasActiveTasks) {
        debugPrint(
          '[TaskDrainForeground] active tasks remain after foreground window',
        );
      }
    } catch (e, st) {
      debugPrint('[TaskDrainForeground] error: $e\n$st');
    } finally {
      try {
        final stopResult = await FlutterForegroundTask.stopService();
        if (stopResult is ServiceRequestFailure) {
          debugPrint(
            '[TaskDrainForeground] stopService failed; will rely on '
            'system stopWithTask: ${stopResult.error}',
          );
        }
      } catch (e) {
        // Native side may throw if the service was already reaped by the
        // system; swallow and continue with the companion hand-off.
        debugPrint('[TaskDrainForeground] stopService threw: $e');
      }
      unawaited(CompanionForegroundService.startPersistent());
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[TaskDrainForeground] onDestroy');
  }
}

class BackgroundTaskForegroundService {
  BackgroundTaskForegroundService._();

  static const String notificationChannelId = 'memex_background_tasks';
  static const String notificationChannelName = 'Memex background tasks';
  static const String _ownerPrefsKey = 'foreground_task_owner';
  static const String _ownerTaskDrain = 'task_drain';

  static Future<void> initialize() async {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: notificationChannelId,
        channelName: notificationChannelName,
        channelDescription: 'Keeps Memex processing local AI tasks',
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
        allowWifiLock: true,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ownerPrefsKey, _ownerTaskDrain);
  }

  static Future<bool> triggerDrain() async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      debugPrint('[TaskDrainForeground] foreground service already running');
      return false;
    }

    await initialize();
    final startResult = await FlutterForegroundTask.startService(
      notificationTitle: 'Memex is processing',
      notificationText: 'AI tasks are continuing in the background.',
      callback: backgroundTaskForegroundEntry,
    );
    if (startResult is ServiceRequestFailure) {
      // Android 12+ background-start restriction. The drain caller
      // (WorkManager callback / health_service) already has a fallback
      // non-FGS path (BackgroundTaskDrainRunner.runFromWorkmanager).
      debugPrint(
        '[TaskDrainForeground] startService denied (background); '
        'caller should fall back to WorkManager drain: ${startResult.error}',
      );
      return false;
    }
    return true;
  }
}
