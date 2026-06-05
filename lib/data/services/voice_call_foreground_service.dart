import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:memex/data/services/companion_foreground_task.dart';
import 'package:memex/utils/logger.dart';

@pragma('vm:entry-point')
void voiceCallForegroundTaskEntry() {
  FlutterForegroundTask.setTaskHandler(VoiceCallForegroundTaskHandler());
}

class VoiceCallForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      await setupLogger();
    } catch (_) {}
    debugPrint('[VoiceCallForeground] onStart starter=$starter');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[VoiceCallForeground] onDestroy');
  }
}

class VoiceCallForegroundService {
  VoiceCallForegroundService._();

  static const String notificationChannelId = 'voice_call_foreground';
  static const String notificationChannelName = 'Voice call';
  static const String _ownerPrefsKey = 'foreground_task_owner';
  static const String _ownerVoiceCall = 'voice_call';

  static Future<void> initialize() async {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: notificationChannelId,
        channelName: notificationChannelName,
        channelDescription: 'Keeps voice calls active in the background',
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
    await prefs.setString(_ownerPrefsKey, _ownerVoiceCall);
  }

  static Future<void> start({
    required String characterName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      final owner = prefs.getString(_ownerPrefsKey);
      if (owner == _ownerVoiceCall) return;
      await FlutterForegroundTask.stopService();
    }

    await initialize();
    await FlutterForegroundTask.startService(
      notificationTitle: characterName,
      notificationText: '语音通话中',
      callback: voiceCallForegroundTaskEntry,
    );
  }

  static Future<void> stopAndRestoreCompanion() async {
    final prefs = await SharedPreferences.getInstance();
    final owner = prefs.getString(_ownerPrefsKey);
    if (owner == _ownerVoiceCall &&
        await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    unawaited(CompanionForegroundService.startPersistent());
  }
}
