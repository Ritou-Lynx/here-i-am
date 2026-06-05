import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:memex/data/services/active_persona_chat_service.dart';
import 'package:memex/utils/logger.dart';

typedef NotificationTapCallback = void Function(String? payload);

/// Wraps [flutter_local_notifications] for agent-initiated push notifications.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _logger = getLogger('NotificationService');
  final _plugin = FlutterLocalNotificationsPlugin();

  // v2: high-importance channel to bypass Android background deferral.
  // Channels are immutable after creation, so we rev the ID to force recreate.
  static const String channelAgentCheckin = 'agent_checkin_v2';
  static const String channelCompanionCall = 'companion_call_v1';

  bool _initialized = false;
  NotificationTapCallback? _onTap;

  /// Register a handler called when the user taps a notification.
  /// [payload] is the characterId (or null for non-character notifications).
  void setTapHandler(NotificationTapCallback handler) {
    _onTap = handler;
  }

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _onTap?.call(response.payload);
      },
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelAgentCheckin,
        'Agent Check-ins',
        description: 'AI agent proactive check-in notifications',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelCompanionCall,
        'Companion Call',
        description: 'Incoming voice call from your companion',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
      ),
    );

    _initialized = true;
    _logger.info('NotificationService initialized');
  }

  /// Show a local notification from the agent.
  /// [payload] is forwarded to the tap handler (e.g. the characterId).
  Future<void> showAgentNotification({
    required String title,
    required String body,
    String? payload,
    int id = 0,
  }) async {
    if (!_initialized) {
      _logger.warning('NotificationService not initialized');
      return;
    }

    if (payload != null &&
        payload.isNotEmpty &&
        await ActivePersonaChatService.instance.isActive(payload)) {
      _logger.info(
        'Agent notification suppressed: active persona chat ($payload)',
      );
      return;
    }

    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelAgentCheckin,
          'Agent Check-ins',
          channelDescription: 'AI agent proactive notifications',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          playSound: true,
          fullScreenIntent: false, // popup, but not lock-screen takeover
          category: AndroidNotificationCategory.message,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      payload: payload,
    );
    _logger.info('Agent notification shown: $title');
  }

  /// Show an incoming-call style notification.
  /// [payload] should be `call:<characterId>` so the tap handler can route correctly.
  Future<void> showCallNotification({
    required String title,
    required String body,
    required String payload,
    int id = 1,
  }) async {
    if (!_initialized) {
      _logger.warning('NotificationService not initialized');
      return;
    }

    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelCompanionCall,
          'Companion Call',
          channelDescription: 'Incoming voice call from your companion',
          importance: Importance.max,
          priority: Priority.max,
          enableVibration: true,
          playSound: true,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
          autoCancel: true,
        ),
      ),
      payload: payload,
    );
    _logger.info('Call notification shown: $title');
  }

  Future<bool?> canScheduleExactNotifications() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return androidPlugin?.canScheduleExactNotifications();
  }

  Future<void> cancelScheduledNotification(int id) async {
    if (!_initialized) {
      await initialize();
    }
    await _plugin.cancel(id);
    _logger.info('Scheduled notification cancelled (id=$id)');
  }

  /// Ask for Android 13+ notification permission from a foreground screen.
  Future<bool?> requestNotificationsPermissionIfNeeded() async {
    if (!Platform.isAndroid) return null;
    if (!_initialized) {
      await initialize();
    }

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final enabled = await androidPlugin?.areNotificationsEnabled();
    if (enabled != false) return enabled;

    final granted = await androidPlugin?.requestNotificationsPermission();
    _logger.info('Notification permission granted: $granted');
    return granted;
  }
}
