import 'dart:async';

import 'package:drift/drift.dart';
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

      // Recover stuck 'processing' rows before ANY gate. The alarm callback
      // (background isolate) can mark a row 'processing' then crash, leaving
      // it permanently stuck. Without this early recovery, a stuck row
      // blocks both hasDueReminders() and hasPendingWork(), which gate the
      // entire tick — a deadlock that can last hours.
      await CheckinService.instance.recoverStuckProcessing();

      // ── Pending-call check (runs every tick, before any early return) ──
      //
      // Due reminders (including scheduled calls) are left by the alarm callback
      // for the foreground service to process, because this context has a Flutter
      // engine and can display the CallKit incoming-call screen.
      //
      // This check catches calls queued by a previous tick's agent run that may
      // not have shown CallKit (e.g. the previous tick was killed mid-run).
      try {
        final pendingCall = await readPendingCall();
        if (pendingCall != null) {
          debugPrint(
              '[ForegroundTask] pending call: ${pendingCall.characterId}');
          final callChar =
              await CharacterService.instance.getPrimaryCompanion(userId);
          if (callChar != null && callChar.id == pendingCall.characterId) {
            final showed =
                await CallkitService.instance.showPendingIncomingCall(
              characterId: callChar.id,
              nameCaller: callChar.name,
              avatarUrl: callChar.avatar,
            );
            if (showed) {
              debugPrint(
                  '[ForegroundTask] CallKit shown via pending-call check');
              // Call is now ringing — don't run checkins while the call is
              // unresolved; the agent could call again and create a duplicate.
              return;
            }
            // showed=false means the call is already ringing (notified within
            // 10 min) or could not be shown. Don't block the tick — due
            // reminders still need processing. The notified flag prevents the
            // checkin agent from creating a duplicate.
          }
        }
      } catch (e) {
        debugPrint('[ForegroundTask] pending-call check error: $e');
      }

      final directCalls = await CheckinService.instance.claimDueCallReminders();
      if (directCalls.isNotEmpty) {
        final directCall = directCalls.first;
        final callChar =
            await CharacterService.instance.getPrimaryCompanion(userId);
        if (callChar == null) {
          for (final call in directCalls) {
            await CheckinService.instance.markStatus(call.id, 'pending');
          }
          debugPrint('[ForegroundTask] due call reminder: no character');
          return;
        }
        await queuePendingCall(
          characterId: callChar.id,
          openingMessage: _openingForDueCall(directCall.body),
        );
        final showed = await CallkitService.instance.showPendingIncomingCall(
          characterId: callChar.id,
          nameCaller: callChar.name,
          avatarUrl: callChar.avatar,
        );
        for (final call in directCalls) {
          await CheckinService.instance.markStatus(call.id, 'done');
        }
        debugPrint(
          '[ForegroundTask] due call reminders handled: '
          '${directCalls.map((call) => call.id).join(", ")}, showed=$showed',
        );
        return;
      }

      // Natural checkins stay quiet while the user is actively chatting.
      // Use DB (SQLite) instead of SharedPreferences because the foreground
      // service runs in a separate isolate where SharedPreferences cache may
      // never see updates from the main isolate — causing isAppInForeground()
      // to return stale data and permanently block background checkins.
      final hasDueReminder = await CheckinService.instance.hasDueReminders();
      if (!hasDueReminder) {
        final active = await _wasUserRecentlyActive(userId);
        if (active) {
          debugPrint('[ForegroundTask] user recently active, skipping checkin');
          return;
        }
      }

      // Interval gate: only proceed when the random interval has elapsed, OR
      // there is pending work (a due reminder / recovered trigger) that must
      // be handled now.
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

      // Keep the foreground notification in sync with the current primary
      // companion, so it doesn't show a stale name after the user changes
      // characters or after a reinstall where defaults were seeded.
      try {
        await FlutterForegroundTask.updateService(
          notificationTitle: character.name,
          notificationText: '在后台陪着你',
        );
      } catch (e) {
        debugPrint('[ForegroundTask] failed to update notification: $e');
      }

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
      await CallkitService.instance.showPendingIncomingCall(
        characterId: character.id,
        nameCaller: character.name,
        avatarUrl: character.avatar,
      );
    } catch (e, st) {
      debugPrint('[ForegroundTask] tick error: $e\n$st');
    } finally {
      _ticking = false;
    }
  }

  static String _openingForDueCall(String reminderBody) {
    final body = reminderBody.trim();
    if (body.startsWith('宝，') || body.startsWith('宝。')) {
      return body;
    }
    return '宝，到时间了，我打过来了。现在方便说话吗？';
  }

  /// Check if the user has sent any chat message in the last 10 minutes.
  /// Uses the database directly — safe across isolates where SharedPreferences
  /// cache may be stale.
  static Future<bool> _wasUserRecentlyActive(String userId) async {
    if (!AppDatabase.isInitialized) return false;
    try {
      final recent = DateTime.now().subtract(const Duration(minutes: 10));
      final db = AppDatabase.instance;
      final msg = await (db.select(db.personaChatMessages)
            ..where((t) =>
                t.isFromCharacter.equals(false) &
                t.timestamp.isBiggerThanValue(recent))
            ..limit(1))
          .getSingleOrNull();
      return msg != null;
    } catch (e) {
      debugPrint('[ForegroundTask] _wasUserRecentlyActive error: $e');
      return false;
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

  // Channel ID rev'd to v2 to force-recreate with LOW importance.
  // MIN importance causes Android to deprioritize the foreground service,
  // leading to suspended ticks and delayed notifications on Samsung devices.
  static const String notificationChannelId = 'companion_foreground_v2';
  static const String notificationChannelName = 'Companion';
  static const String _ownerPrefsKey = 'foreground_task_owner';
  static const String _versionPrefsKey = 'companion_foreground_config_version';
  static const String _ownerCompanion = 'companion';
  static const String _ownerVoiceCall = 'voice_call';
  static const int _configVersion = 2;

  // Tick cadence. The interval gate (CheckinService.dueForCheckin) decides when
  // a tick actually performs a checkin.
  // Reduced from 60s to 15s so scheduled calls show CallKit within 15s of the
  // alarm callback firing (which skips reminders and leaves them for us).
  static const int _tickIntervalMs = 15 * 1000;

  static Future<void> initialize() async {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: notificationChannelId,
        channelName: notificationChannelName,
        channelDescription: 'Keeps your companion present in the background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ownerPrefsKey, _ownerCompanion);
    await prefs.setInt(_versionPrefsKey, _configVersion);
  }

  /// Start the persistent service (idempotent). Safe to call on every app
  /// launch — if it's already running this is a no-op.
  static Future<void> startPersistent() async {
    final prefs = await SharedPreferences.getInstance();
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      final owner = prefs.getString(_ownerPrefsKey);
      final version = prefs.getInt(_versionPrefsKey);
      if (owner == _ownerVoiceCall) {
        debugPrint('[ForegroundTask] voice call service is active; skip');
        return;
      }
      if (owner == _ownerCompanion && version == _configVersion) {
        // Service is already running but the notification title may be stale
        // (user may have changed primary companion or enabled/disabled characters).
        // FlutterForegroundTask.updateService() refreshes the on-going notification.
        final title = await _buildNotificationTitle();
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: '在后台陪着你',
        );
        debugPrint('[ForegroundTask] persistent service already running, '
            'notification updated to "$title"');
        return;
      }
      debugPrint(
        '[ForegroundTask] restarting stale foreground service '
        '(owner=$owner version=$version)',
      );
      await FlutterForegroundTask.stopService();
    }
    await initialize();
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
