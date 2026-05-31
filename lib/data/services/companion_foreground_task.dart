import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:memex/agent/built_in_tools/initiate_call_tool.dart';
import 'package:memex/agent/companion_agent/companion_agent.dart';
import 'package:memex/data/services/callkit_service.dart';
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

/// PERSISTENT foreground service that drives the companion checkin loop.
///
/// This replaces the unreliable android_alarm_manager path: that plugin's
/// alarm fired but failed to spawn a background Dart isolate on this device
/// (Android 14+/Samsung background-start limits), so checkins never ran. A real
/// foreground service is immune to that — the OS keeps our isolate alive and
/// `onRepeatEvent` ticks on a fixed cadence. The actual checkin cadence stays
/// random/natural via [CheckinService.dueForCheckin] (an interval gate), so a
/// 60s tick does NOT mean a checkin every 60s.
class CompanionTaskHandler extends TaskHandler {
  static bool _ticking = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[ForegroundTask] onStart (persistent) starter=$starter');
    try {
      await setupLogger();
    } catch (_) {}
    // Run one tick right away so a fresh (re)start doesn't idle a full interval.
    await _tick();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Fire-and-forget; _ticking guards against overlapping runs.
    unawaited(_tick());
  }

  Future<void> _tick() async {
    if (_ticking) {
      debugPrint('[ForegroundTask] tick skipped (already running)');
      return;
    }
    _ticking = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('current_user_id');
      if (userId == null) return;

      if (!AppDatabase.isInitialized) {
        await AppDatabase.init(userId);
      }
      await UserStorage.initL10n();

      // Never interrupt while the user is actively using the app.
      if (await CheckinService.instance.isAppInForeground()) {
        return;
      }

      // Interval gate: only proceed when the random interval has elapsed
      // (or the high-frequency sleep-push window), OR there is pending work
      // (a due reminder / recovered trigger) that must be handled now.
      final due = await CheckinService.instance.dueForCheckin();
      final hasPendingWork = await CheckinService.instance.hasPendingWork();
      if (!due && !hasPendingWork) return;

      debugPrint('[ForegroundTask] tick: due=$due pending=$hasPendingWork');

      final enqueued = await CheckinService.instance.maybeEnqueueCheckin();
      final stillPending = await CheckinService.instance.hasPendingWork();
      if (!enqueued && !stillPending) {
        debugPrint('[ForegroundTask] nothing to process');
        return;
      }

      final dataRoot = await UserStorage.resolveDataRoot(userId);
      await FileSystemService.init(dataRoot);
      await NotificationService.instance.initialize();

      final character =
          await CharacterService.instance.getPrimaryCompanion(userId);
      if (character == null) {
        debugPrint('[ForegroundTask] no character');
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

      // If the agent queued a voice call, fire the CallKit incoming call now.
      await _maybeFireCallNotification(
          character.name, character.id, character.avatar);
    } catch (e, st) {
      debugPrint('[ForegroundTask] tick error: $e\n$st');
    } finally {
      _ticking = false;
    }
  }

  static Future<void> _maybeFireCallNotification(
    String characterName,
    String characterId,
    String? characterAvatar,
  ) async {
    try {
      final pending = await readPendingCall();
      if (pending == null) return;

      final alreadyNotified = await isPendingCallAlreadyNotified();
      if (alreadyNotified) {
        debugPrint('[ForegroundTask] call already notified, skipping');
        return;
      }

      // System-level CallKit incoming call (full-screen, persistent ring).
      await CallkitService.instance.showIncomingCall(
        characterId: characterId,
        nameCaller: characterName,
        avatarUrl: characterAvatar,
      );
      await markPendingCallNotified();
      debugPrint('[ForegroundTask] CallKit incoming call shown for $characterId');
    } catch (e) {
      debugPrint('[ForegroundTask] callkit error: $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[ForegroundTask] onDestroy');
  }
}

/// Manages the persistent companion foreground service.
class CompanionForegroundService {
  CompanionForegroundService._();

  static const String notificationChannelId = 'companion_foreground';
  static const String notificationChannelName = 'Companion';

  // Tick cadence. The interval gate (CheckinService.dueForCheckin) decides when
  // a tick actually performs a checkin, so this only needs to be frequent
  // enough to catch the sleep-push 1–2 min window.
  static const int _tickIntervalMs = 60 * 1000;

  static Future<void> initialize() async {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: notificationChannelId,
        channelName: notificationChannelName,
        channelDescription: 'Keeps your companion present in the background',
        channelImportance: NotificationChannelImportance.MIN,
        priority: NotificationPriority.MIN,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(_tickIntervalMs),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Start the persistent service (idempotent). Safe to call on every app
  /// launch — if it's already running this is a no-op.
  static Future<void> startPersistent() async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      debugPrint('[ForegroundTask] persistent service already running');
      return;
    }
    final title = await _buildNotificationTitle();
    await FlutterForegroundTask.startService(
      notificationTitle: title,
      notificationText: '在后台陪着你',
      callback: companionForegroundTaskEntry,
    );
    debugPrint('[ForegroundTask] persistent service started');
  }

  /// Back-compat alias: callers that used to fire a one-off checkin now just
  /// ensure the persistent service is running (the tick loop handles checkins).
  static Future<void> triggerCheckin() => startPersistent();

  static Future<String> _buildNotificationTitle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('current_user_id');
      if (userId == null) return 'Memex';

      if (!AppDatabase.isInitialized) {
        await AppDatabase.init(userId);
      }
      await UserStorage.initL10n();

      final dataRoot = await UserStorage.resolveDataRoot(userId);
      await FileSystemService.init(dataRoot);

      final character =
          await CharacterService.instance.getPrimaryCompanion(userId);
      final name = character?.name.trim();
      if (name == null || name.isEmpty) return 'Memex';
      return name;
    } catch (e) {
      debugPrint('[ForegroundTask] failed to resolve notification title: $e');
      return 'Memex';
    }
  }
}
