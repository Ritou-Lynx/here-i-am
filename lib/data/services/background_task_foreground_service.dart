import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'package:memex/data/services/background_task_drain_runner.dart';
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
      await FlutterForegroundTask.stopService();
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
  }

  static Future<bool> triggerDrain() async {
    await initialize();

    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      debugPrint('[TaskDrainForeground] foreground service already running');
      return false;
    }

    await FlutterForegroundTask.startService(
      notificationTitle: 'Memex is processing',
      notificationText: 'AI tasks are continuing in the background.',
      callback: backgroundTaskForegroundEntry,
    );
    return true;
  }
}
