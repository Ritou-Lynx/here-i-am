import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:memex/config/dependencies.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/ui/insight/view_models/insight_viewmodel.dart';
import 'package:memex/ui/user_setup/widgets/user_setup_screen.dart';
import 'package:memex/ui/app_lock/widgets/lock_screen_page.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/core/themes/app_theme.dart';
import 'package:memex/ui/core/themes/here_iam_theme_controller.dart';
import 'dart:io';
import 'package:memex/data/services/reading/xhs/xhs_hidden_webview_host.dart';
import 'package:memex/ui/main_screen/widgets/radial_menu.dart';
import 'package:memex/domain/models/shortcut_item.dart' as app_shortcut;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:ui';
import 'package:memex/ui/main_screen/widgets/input_sheet.dart';
import 'package:memex/ui/settings/widgets/model_config_list_page.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/data/services/publish_timestamp_service.dart';
import 'package:memex/data/services/health_service.dart';
import 'package:memex/data/services/health_strategies.dart';
import 'package:memex/data/services/whisper_service.dart';
import 'package:memex/data/services/streaming_transcriber.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/data/services/checkin_service.dart';
import 'package:memex/data/services/proactive_outing_service.dart';
import 'package:memex/data/memory_v3/services/dreaming_scheduler_service.dart';
import 'package:memex/data/services/notification_service.dart';
import 'package:memex/agent/built_in_tools/initiate_call_tool.dart';
import 'package:memex/data/services/callkit_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/services/persona_chat_open_service.dart';
import 'package:memex/ui/character/widgets/persona_chat_navigation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:memex/data/services/companion_foreground_task.dart';
import 'package:health/health.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/ui/agent_activity/widgets/agent_activity_widget.dart';
import 'package:memex/ui/main_screen/widgets/ai_core_button.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/data/services/local_server_service.dart';
import 'package:memex/data/services/app_update_service.dart';
import 'package:memex/data/services/backup_service.dart';
import 'package:go_router/go_router.dart';
import 'package:memex/routing/router.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/data/services/onboarding_service.dart';
import 'package:memex/data/services/demo_service.dart';
import 'package:memex/ui/core/widgets/demo_overlay.dart';
import 'package:memex/ui/main_screen/widgets/share_intent_handler.dart';
import 'package:memex/ui/settings/widgets/backup_restore_confirm_dialog.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:memex/data/services/quick_action_service.dart';
import 'package:memex/data/services/speech_transcription_service.dart';
import 'package:memex/data/services/background_task_drain_service.dart';
import 'package:memex/ui/companion/widgets/companion_first_shell.dart';
import 'package:memex/ui/companion/widgets/floating_record_ball.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<RootShellState> rootShellKey = GlobalKey<RootShellState>();

void _openPersonaChatVoiceModeFromRoot(String characterId) {
  if (AppFlavor.isHereIAm) {
    _requestHereIamPersonaChat(characterId, startVoiceMode: true);
    return;
  }

  final context = rootNavigatorKey.currentContext;
  if (context == null) return;
  openPersonaChat(
    context,
    characterId: characterId,
    rootNavigator: true,
    initialVoiceMode: true,
  );
}

void _requestHereIamPersonaChat(
  String characterId, {
  bool startVoiceMode = false,
}) {
  PersonaChatOpenService.instance.requestOpen(
    characterId,
    startVoiceMode: startVoiceMode,
  );

  final context = rootNavigatorKey.currentContext;
  if (context == null) return;

  rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final currentContext = rootNavigatorKey.currentContext;
    if (currentContext == null || !currentContext.mounted) return;
    GoRouter.of(currentContext).go(AppRoutes.home);
  });
}

void _installGlobalErrorLogging() {
  final logger = getLogger('GlobalError');
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    logger.severe(
      'Unhandled Flutter error: ${details.exceptionAsString()}',
      details.exception,
      details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    logger.severe('Unhandled platform error', error, stack);
    return false;
  };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize flavor from platform (set by --flavor flag)
  AppFlavor.init(appFlavor);

  await setupLogger();
  _installGlobalErrorLogging();

  // Initialize l10n
  await UserStorage.initL10n();

  // Initialize Workmanager (for background tasks)
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );

  // Initialize AndroidAlarmManager (exact-time wakeups that bypass Doze)
  if (Platform.isAndroid) {
    await AndroidAlarmManager.initialize();
  }

  // Mark foreground immediately so any sticky ForegroundService restart
  // (START_STICKY behavior after being killed by Freecess/Doze) sees the app
  // is active and exits early before showing the "thinking" notification.
  if (Platform.isAndroid) {
    await CheckinService.instance.markForeground();
  }

  // Initialize foreground service (bypasses Samsung Freecess)
  if (Platform.isAndroid) {
    await CompanionForegroundService.initialize();
  }

  // Initialize notification service for agent checkins
  await NotificationService.instance.initialize();

  // Route notification taps into the character's chat screen. Call payloads
  // enter inline voice mode inside chat instead of opening a separate call UI.
  //
  // The tap may fire before runApp() has created the navigator (cold start
  // from a notification). When context is unavailable, store the payload and
  // retry after the first frame so the characterId routes correctly.
  String? pendingNotificationPayload;
  void handleNotificationPayload(String payload) {
    final context = rootNavigatorKey.currentContext;
    if (context == null) {
      pendingNotificationPayload = payload;
      return;
    }

    if (payload.startsWith('call:')) {
      final characterId = payload.substring(5);
      _openPersonaChatVoiceModeFromRoot(characterId);
    } else {
      unawaited(NotificationService.instance.cancelAgentNotification());
      if (AppFlavor.isHereIAm) {
        _requestHereIamPersonaChat(payload);
        return;
      }
      openPersonaChat(context, characterId: payload, rootNavigator: true);
    }
  }

  NotificationService.instance.setTapHandler((String? payload) {
    if (payload == null || payload.isEmpty) return;
    handleNotificationPayload(payload);
  });

  // Always register a post-frame hook: the notification callback may fire
  // before OR after runApp() creates the navigator. This catches both cases.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final payload = pendingNotificationPayload;
    if (payload != null) {
      pendingNotificationPayload = null;
      handleNotificationPayload(payload);
    }
  });

  // System-level incoming-call (CallKit) wiring.
  CallkitService.instance.init();
  CallkitService.instance.onAccept = (String characterId) async {
    // CallKit holds the call audio session while a call is "ongoing", which
    // mutes our own TTS. Once the user accepts, immediately end the CallKit
    // session so audio focus returns to the app, then open chat voice mode.
    await CallkitService.instance.endAll();
    // Give Android ~300 ms to return audio focus before chat voice mode
    // starts TTS. Without this delay the first spoken reply can be muted.
    await Future.delayed(const Duration(milliseconds: 300));
    _openPersonaChatVoiceModeFromRoot(characterId);
  };
  CallkitService.instance.onDecline = (String characterId) {
    // The CallKit service fires onDecline for BOTH explicit rejection
    // and timeout (missed).  Record it so the companion notices next turn.
    PersonaChatService.instance.addCharacterMessage(
      characterId,
      '📵 用户没有接你的电话。下次聊天时可以提一下。',
      timestamp: DateTime.now(),
      isRead: false,
    );
  };

  // Cancel any previously registered pedometer background tasks on iOS
  // (iOS now uses HealthKit only, not CMPedometer)
  if (Platform.isIOS) {
    await Workmanager().cancelAll();
  }

  // MemexRouter is provided via config/dependencies.dart and created on first read

  // Start local HTTP server
  await LocalServerService.start();

  // Set status bar style & enable edge-to-edge
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  final appRouter = createAppRouter(
    rootNavigatorKey,
    () => RootShell(
      key: rootShellKey,
    ),
  );

  // Initialize quick actions (app icon long-press shortcuts).
  const QuickActions quickActions = QuickActions();
  quickActions.initialize((String shortcutType) {
    QuickActionService.instance.handleAction(shortcutType);
  });

  runApp(MultiProvider(
    providers: dependencyProviders,
    child: MemexApp(router: appRouter),
  ));
}

/// Root route content: user check then loading / UserSetupScreen / MainScreen (Compass-style).
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => RootShellState();
}

class RootShellState extends State<RootShell> {
  bool _hasUser = false;
  bool _onboardingComplete = false;
  bool _isChecking = true;
  bool _isLoadingFromICloud = false;
  int _mainScreenEpoch =
      0; // incremented to force full rebuild on storage switch

  @override
  void initState() {
    super.initState();
    _checkUser();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        NotificationService.instance.requestNotificationsPermissionIfNeeded(),
      );
    });
  }

  Future<void> _checkUser() async {
    final hasUser = await UserStorage.hasUser();
    var onboardingDone = await OnboardingService.isOnboardingComplete();

    // Migration: existing users who set up before the onboarding flag was added
    // should be treated as onboarding-complete.
    if (hasUser && !onboardingDone) {
      final configs = await UserStorage.getLLMConfigs();
      final hasValidConfig = configs.any((c) => c.isValid);
      if (hasValidConfig) {
        await OnboardingService.markOnboardingComplete();
        onboardingDone = true;
      }
    }

    // Store for WorkManager background isolate access
    if (hasUser) {
      final userId = await UserStorage.getUserId();
      if (userId != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('current_user_id', userId);
      }
    }

    if (mounted) {
      setState(() {
        _hasUser = hasUser;
        _onboardingComplete = onboardingDone;
        _isChecking = false;
      });
    }
  }

  void _onUserCreated() async {
    // Check iCloud BEFORE any other awaits to avoid timing issues
    final userId = await UserStorage.getUserId();
    bool isICloud = false;
    if (userId != null) {
      // Store for WorkManager background isolate access
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_user_id', userId);
      final loc = await UserStorage.getWorkspaceStorageLocation(userId);
      isICloud = loc == StorageLocation.icloud;
    }

    await OnboardingService.markOnboardingComplete();

    if (isICloud && mounted) {
      setState(() => _isLoadingFromICloud = true);
      // Wait for the loading UI to actually render before starting heavy work
      await Future.delayed(const Duration(milliseconds: 100));
      await MemexRouter().applyWorkspaceStorageChange();
      if (mounted) {
        setState(() {
          _isLoadingFromICloud = false;
          _hasUser = true;
          _onboardingComplete = true;
        });
      }
    } else if (mounted) {
      setState(() {
        _hasUser = true;
        _onboardingComplete = true;
      });
    }
  }

  /// Reset state and re-check user. Called after account deletion or storage switch.
  void resetAndRecheck() {
    setState(() {
      _hasUser = false;
      _onboardingComplete = false;
      _isChecking = true;
      _mainScreenEpoch++;
    });
    _checkUser();
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(child: AgentLogoLoading()),
      );
    }
    if (_isLoadingFromICloud) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AgentLogoLoading(),
              const SizedBox(height: 16),
              Text(
                UserStorage.l10n.loadingFromICloud,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6366F1),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (!_hasUser || !_onboardingComplete) {
      return UserSetupScreen(onUserCreated: _onUserCreated);
    }
    return MultiProvider(
      key: ValueKey(_mainScreenEpoch),
      providers: [
        ChangeNotifierProvider<InsightViewModel>(
          create: (c) =>
              InsightViewModel(router: c.read<MemexRouter>())..loadData(),
        ),
      ],
      child: const MainScreen(),
    );
  }
}

class MemexApp extends StatefulWidget {
  const MemexApp({super.key, required this.router});

  final GoRouter router;

  @override
  State<MemexApp> createState() => _MemexAppState();
}

class _MemexAppState extends State<MemexApp> with WidgetsBindingObserver {
  bool _hasUser = false;
  bool _isLocked = true; // Default to locked on start
  bool _requiresAuth = true; // Whether actual authentication is required
  DateTime? _lastPausedTime; // Track when app was paused
  StreamSubscription<bool>? _taskKeepAliveSubscription;
  bool _hasActiveTasks = false;
  AppLifecycleState? _lastLifecycleState;
  Timer? _foregroundHeartbeatTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkUser();
    _checkLockSettings();
    // App starts in the foreground; begin the heartbeat so background checkins
    // stay silent while the user is actively using the app.
    _startForegroundHeartbeat();
  }

  /// Writes a foreground heartbeat now and every 60s so background checkin
  /// isolates can detect the app is in active use and skip proactive pushes.
  void _startForegroundHeartbeat() {
    unawaited(CheckinService.instance.markForeground());
    _foregroundHeartbeatTimer?.cancel();
    _foregroundHeartbeatTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(CheckinService.instance.markForeground()),
    );
  }

  /// Stops the heartbeat and expires it immediately so background checkins can
  /// resume the moment the app is backgrounded.
  void _stopForegroundHeartbeat() {
    _foregroundHeartbeatTimer?.cancel();
    _foregroundHeartbeatTimer = null;
    unawaited(CheckinService.instance.markBackground());
  }

  Future<void> _checkLockSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final isLockEnabled = prefs.getBool('app_lock_enabled') ?? false;
    if (mounted) {
      setState(() {
        // If lock is strictly required only when enabled, we update _isLocked.
        // Default _isLocked is true. If disabled, we unlock immediately.
        if (!isLockEnabled) {
          _isLocked = false;
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _taskKeepAliveSubscription?.cancel();
    _foregroundHeartbeatTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lastLifecycleState = state;
    if (state == AppLifecycleState.paused) {
      unawaited(LocalTaskExecutor.instance
          .recordGracefulShutdown(reason: 'app_lifecycle_paused'));
      _ensureTaskKeepAliveSubscription();
      unawaited(_syncTaskKeepAliveForLifecycle());
      _lastPausedTime = DateTime.now();
      _checkLockSettingsBeforeLocking();
      _stopForegroundHeartbeat();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(LocalTaskExecutor.instance.clearGracefulShutdownMarker());
      MemexRouter().scheduleAutoBackupCheck(trigger: 'foreground');
      _checkGracePeriod();
      _startForegroundHeartbeat();
      _checkPendingCallOnResume();
      // Ensure the persistent foreground service is running. If Android killed
      // it while the app was backgrounded, this restarts it (idempotent).
      if (Platform.isAndroid) {
        CompanionForegroundService.startPersistent().catchError((e) {
          debugPrint('[AppLifecycle] Failed to restart foreground service: $e');
        });
      }
    } else if (state == AppLifecycleState.detached) {
      unawaited(LocalTaskExecutor.instance
          .recordGracefulShutdown(reason: 'app_lifecycle_detached'));
      _stopForegroundHeartbeat();
    }
  }

  bool get _isBackgrounded =>
      _lastLifecycleState == AppLifecycleState.paused ||
      _lastLifecycleState == AppLifecycleState.hidden;

  void _checkPendingCallOnResume() {
    // When the app comes back to the foreground, check if a companion had
    // queued a voice call (e.g. from a scheduled reminder) that the system
    // couldn't deliver via CallKit while the app was backgrounded.
    Future.microtask(() async {
      try {
        final pending = await readPendingCall();
        if (pending == null) return;
        // If CallKit already rang (notified flag set), the user accepted via
        // the system screen and onAccept handles the navigation. Opening a
        // second voice-mode request here would create conflicting audio.
        // Only open directly when CallKit never showed.
        if (await isPendingCallAlreadyNotified()) return;
        _openPersonaChatVoiceModeFromRoot(pending.characterId);
      } catch (_) {}
    });
  }

  void _ensureTaskKeepAliveSubscription() {
    if (_taskKeepAliveSubscription != null || !AppDatabase.isInitialized) {
      return;
    }

    try {
      _taskKeepAliveSubscription =
          LocalTaskExecutor.instance.hasActiveTasksStream.listen((hasTasks) {
        _hasActiveTasks = hasTasks;
        if (hasTasks && _isBackgrounded) {
          unawaited(BackgroundTaskDrainService.scheduleDrain());
        }
      });
    } catch (_) {
      // The local DB can still be initializing during early app startup.
      // Lifecycle events retry this before background keep-alive is needed.
    }
  }

  Future<void> _syncTaskKeepAliveForLifecycle() async {
    if (!AppDatabase.isInitialized) return;

    try {
      final snapshot =
          await LocalTaskExecutor.instance.getTaskActivitySnapshot();
      _hasActiveTasks = snapshot.hasActiveTasks;
      if (_isBackgrounded && _hasActiveTasks) {
        await BackgroundTaskDrainService.scheduleDrain();
      }
    } catch (_) {}
  }

  Future<void> _checkLockSettingsBeforeLocking() async {
    final prefs = await SharedPreferences.getInstance();
    final isLockEnabled = prefs.getBool('app_lock_enabled') ?? false;
    if (isLockEnabled && mounted) {
      setState(() {
        _isLocked = true;
        _requiresAuth = false; // Just show privacy screen initially
      });
    }
  }

  Future<void> _checkGracePeriod() async {
    if (!_isLocked) return;

    if (_lastPausedTime != null) {
      final difference = DateTime.now().difference(_lastPausedTime!);
      // If less than 5 minutes, unlock automatically
      if (difference.inMinutes < 5) {
        if (mounted) {
          setState(() {
            _isLocked = false;
          });
        }
      } else {
        // More than 5 minutes, require auth
        if (mounted) {
          setState(() {
            _requiresAuth = true;
          });
        }
      }
    } else {
      // No pause time recorded (e.g. cold start), require auth
      if (mounted) {
        setState(() {
          _requiresAuth = true;
        });
      }
    }
  }

  Future<void> _checkUser() async {
    final hasUser = await UserStorage.hasUser();
    if (mounted) {
      setState(() {
        _hasUser = hasUser;
      });
    }
    if (hasUser) {
      _ensureTaskKeepAliveSubscription();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hereIamTheme = context.watch<HereIamThemeController>().tokens;
    return MaterialApp.router(
      title: 'Memex',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      theme: AppTheme.lightThemeFor(hereIamTheme),
      darkTheme: AppTheme.darkThemeFor(hereIamTheme),
      themeMode:
          ThemeMode.light, // Unified light mode, disabling adaptive dark mode
      routerConfig: widget.router,
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            if (_isLocked && _hasUser)
              _requiresAuth
                  ? LockScreen(
                      onUnlock: () {
                        setState(() {
                          _isLocked = false;
                        });
                      },
                    )
                  : const PrivacyScreen(),
            // Off-screen 1x1 WebView for Reading Companion's 灏忕孩涔?
            // background fetch pipeline. Stays mounted for the lifetime of
            // the app so the controller can navigate at any time.
            if (AppFlavor.isHereIAm)
              const Positioned(
                left: 0,
                bottom: 0,
                width: 1,
                height: 1,
                child: XhsHiddenWebViewHost(),
              ),
            if (AppFlavor.isHereIAm && !(_isLocked && _hasUser))
              FloatingRecordBall(navigatorKey: rootNavigatorKey),
          ],
        );
      },
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  bool get _useCompanionFirstShell => AppFlavor.isHereIAm;

  int _currentTab = 0;
  bool _isInputOpen = false;
  final MemexRouter _memexRouter = MemexRouter();
  final EventBusService _eventBus = EventBusService.instance;
  Timer? _memoryButtonTapTimer;
  int _memoryButtonTapCount = 0;
  bool _isRestoringExternalBackup = false;
  Timer? _knowledgeBaseButtonTapTimer;
  int _knowledgeBaseButtonTapCount = 0;
  final Logger _logger = getLogger('MainScreen');

  // Radial Menu & Recording State
  bool _isRadialMenuOpen = false;
  List<app_shortcut.ShortcutItem> _shortcuts = [];
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _recordingPath;
  StreamingTranscriber? _quickTranscriber;
  StreamSubscription<Uint8List>? _quickAudioSub;
  final List<int> _quickPcmBuffer = [];
  String _quickTranscribedText = '';
  String? _quickAudioPath;
  bool _isQuickCalibrating = false;
  Offset _centerButtonCenter = Offset.zero;
  final GlobalKey<RadialMenuState> _radialMenuKey =
      GlobalKey<RadialMenuState>();
  final GlobalKey _aiButtonKey = GlobalKey();
  final GlobalKey _mainStackKey = GlobalKey();
  bool _isInvalidConfigDialogShowing = false;
  bool _isErrorNotificationDialogShowing = false;
  bool _earlyUpdateCheckStarted = false;
  late final ShareIntentHandler _shareIntentHandler;
  InputData? _sharedDraft;

  // Agent Button Position - REMOVED (Moved to Main App)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DemoService.instance.addListener(_onDemoChanged);
    // Init event bus connection and local DB (delay to ensure token is loaded)
    Future.delayed(const Duration(seconds: 1), () async {
      final userId = await UserStorage.getUserId();
      if (userId != null && !AppDatabase.isInitialized) {
        await AppDatabase.init(userId);
      }
      if (userId != null && AppDatabase.isInitialized) {
        try {
          await ProactiveOutingService.instance.refreshSchedule();
        } catch (e) {
          _logger.warning('Failed to refresh proactive outing schedule: $e');
        }
      }
      _eventBus.connect();

      // Start onboarding demo on first launch
      if (userId != null) {
        DemoService.instance.start(userId);
      }
    });

    // Check and report all health data
    _logger.info('initState: Starting comprehensive health check...');
    _checkAndReportHealthData().catchError((error, stackTrace) {
      _logger.severe(
          '鉂?Error in _checkAndReportHealthData: $error', error, stackTrace);
    });

    // Register stochastic checkin pulse task (WorkManager, best-effort)
    CheckinService.instance.ensureCheckinTaskRegistered().catchError((e) {
      _logger.severe('Failed to register checkin task: $e');
    });

    // Register dreaming daily batch task (WorkManager, battery not low).
    Workmanager().registerPeriodicTask(
      DreamingSchedulerService.dailyBatchTaskName,
      DreamingSchedulerService.dailyBatchTaskName,
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: true,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      frequency: const Duration(hours: 4),
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(hours: 2),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    ).catchError((e) {
      _logger.warning('Failed to register dreaming daily batch task: $e');
    });
    // Schedule reliable AlarmManager alarm (bypasses Doze + Samsung Freecess).
    // This self-reschedules after each fire so it survives without WorkManager.
    // NOTE: on Android 14+/Samsung this alarm fires but often fails to spawn its
    // background Dart isolate, so it's now only a FALLBACK.
    if (Platform.isAndroid) {
      CheckinService.instance.scheduleProductionAlarm().catchError((e) {
        _logger.severe('Failed to schedule production alarm: $e');
      });
      // PRIMARY driver: persistent foreground service ticks the checkin loop.
      // Immune to background-start limits that break the alarm isolate.
      CompanionForegroundService.startPersistent().catchError((e) {
        _logger.severe('Failed to start persistent foreground service: $e');
      });
    }

    // Start auto input collection and quantity check
    _logger.info('initState: Starting Auto Input collection check...');

    _eventBus.addHandler(
        EventBusMessageType.invalidModelConfig, _handleInvalidModelConfig);
    _eventBus.addHandler(
        EventBusMessageType.errorNotification, _handleErrorNotification);

    _shareIntentHandler = ShareIntentHandler(
      logger: _logger,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      onSharedDraft: (data) {
        if (!mounted) return;
        setState(() {
          _sharedDraft = data;
          _isInputOpen = true;
        });
      },
      onBackupFileShared: _handleExternalBackupFile,
    )..init();

    // Consume pending quick action (app icon long-press shortcut).
    QuickActionService.instance.attach();
    _consumeQuickActionIfNeeded();

    _scheduleEarlyUpdateCheck();
  }

  void _scheduleEarlyUpdateCheck() {
    final service = AppUpdateService.instance;
    if (!service.isSupported || _earlyUpdateCheckStarted) return;
    _earlyUpdateCheckStarted = true;
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      unawaited(_checkEarlyUpdateInBackground());
    });
  }

  Future<void> _checkEarlyUpdateInBackground() async {
    final service = AppUpdateService.instance;
    if (!await service.shouldRunAutoCheck()) return;

    try {
      final settings = await service.loadSettings();
      final result = await service.checkForUpdate(manual: false);
      if (!mounted || result.status != AppUpdateCheckStatus.updateAvailable) {
        return;
      }

      final update = result.update!;
      if (settings.autoDownloadAndInstall) {
        await _downloadAndInstallEarlyUpdate(update);
      } else {
        _showEarlyUpdateDialog(update);
      }
    } catch (e, st) {
      _logger.warning('Early update check failed: $e', e, st);
    }
  }

  void _showEarlyUpdateDialog(AppUpdateInfo update) {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;

    showDialog<void>(
      context: context,
      builder: (context) {
        final notes = update.releaseNotes.trim();
        return AlertDialog(
          title: Text(UserStorage.l10n.earlyUpdateDialogTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UserStorage.l10n.earlyUpdateFound(
                    update.versionName,
                    update.buildNumber,
                  ),
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    UserStorage.l10n.earlyUpdateReleaseNotes,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notes,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(UserStorage.l10n.cancel),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(_downloadAndInstallEarlyUpdate(update));
              },
              icon: const Icon(Icons.download, size: 18),
              label: Text(UserStorage.l10n.earlyUpdateDownloadAndInstall),
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadAndInstallEarlyUpdate(AppUpdateInfo update) async {
    final context = rootNavigatorKey.currentContext;
    if (context != null) {
      ToastHelper.showInfo(
        context,
        UserStorage.l10n.earlyUpdateDownloadingPercent(0),
      );
    }

    try {
      final download = await AppUpdateService.instance.downloadUpdate(update);
      final install =
          await AppUpdateService.instance.installUpdate(download.apkPath);
      final currentContext = rootNavigatorKey.currentContext;
      if (currentContext == null) return;

      switch (install.status) {
        case AppUpdateInstallStatus.started:
          ToastHelper.showSuccess(
            currentContext,
            UserStorage.l10n.earlyUpdateInstallStarted,
          );
        case AppUpdateInstallStatus.permissionRequired:
          ToastHelper.showInfo(
            currentContext,
            UserStorage.l10n.earlyUpdateInstallPermissionRequired,
          );
        case AppUpdateInstallStatus.unsupported:
          break;
      }
    } catch (e) {
      final currentContext = rootNavigatorKey.currentContext;
      if (e is AppUpdateWifiRequiredException) {
        ToastHelper.showInfo(
          currentContext,
          UserStorage.l10n.earlyUpdateSkippedMobile,
        );
      } else {
        ToastHelper.showError(currentContext, e);
      }
    }
  }

  void _handleInvalidModelConfig(EventBusMessage message) {
    if (!mounted) return;
    if (message is! InvalidModelConfigMessage) return;

    // Check if dialog is already showing to prevent stacking
    if (_isInvalidConfigDialogShowing) return;

    final context = rootNavigatorKey.currentContext;
    if (context == null) return;

    setState(() => _isInvalidConfigDialogShowing = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(UserStorage.l10n.warning),
        content: Text(UserStorage.l10n
            .invalidModelConfigDetailed(message.agentId, message.configKey)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (mounted)
                setState(() => _isInvalidConfigDialogShowing = false);
            },
            child: Text(UserStorage.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (mounted)
                setState(() => _isInvalidConfigDialogShowing = false);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ModelConfigListPage(),
                ),
              );
            },
            child: Text(UserStorage.l10n.modelConfig),
          ),
        ],
      ),
    ).then((_) {
      if (mounted) setState(() => _isInvalidConfigDialogShowing = false);
    });
  }

  void _handleErrorNotification(EventBusMessage message) {
    if (!mounted) return;
    if (message is! ErrorNotificationMessage) return;
    if (_isErrorNotificationDialogShowing) return;

    final context = rootNavigatorKey.currentContext;
    if (context == null) return;

    setState(() => _isErrorNotificationDialogShowing = true);

    final isAuthError = message.errorCategory == 'authenticationError';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Text(UserStorage.l10n.llmErrorDialogTitle),
        content: Text(message.errorMessage),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (mounted)
                setState(() => _isErrorNotificationDialogShowing = false);
            },
            child: Text(UserStorage.l10n.cancel),
          ),
          if (isAuthError)
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (mounted)
                  setState(() => _isErrorNotificationDialogShowing = false);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ModelConfigListPage(),
                  ),
                );
              },
              child: Text(UserStorage.l10n.goToModelConfig),
            ),
        ],
      ),
    ).then((_) {
      if (mounted) setState(() => _isErrorNotificationDialogShowing = false);
    });
  }

  void _onDemoChanged() {
    if (!mounted) return;
    final demo = DemoService.instance;

    // When demo advances to tapKnowledgeTab, refresh the knowledge base
    // so the demo-written guide file appears.
    if (demo.currentStep == DemoStep.tapKnowledgeTab) {
      // KnowledgeBaseScreen has been removed.
    }

    setState(() {});
  }

  Future<void> _handleAICoreButtonTap() async {
    // No LLM config check; users can submit records without AI configured.

    if (mounted) {
      // Prefill text during demo
      if (DemoService.instance.currentStep == DemoStep.tapSend) {
        setState(() {
          _sharedDraft = InputData(text: DemoService.instance.prefillText);
          _isInputOpen = true;
        });
      } else {
        setState(() => _isInputOpen = true);
      }
    }
  }

  void _handleAICoreButtonLongPressStart() {
    // Determine button center for RadialMenu using GlobalKey
    final RenderBox? buttonBox =
        _aiButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? stackBox =
        _mainStackKey.currentContext?.findRenderObject() as RenderBox?;

    if (buttonBox != null && stackBox != null) {
      final buttonSize = buttonBox.size;
      final buttonPosition =
          stackBox.globalToLocal(buttonBox.localToGlobal(Offset.zero));
      _centerButtonCenter =
          buttonPosition + Offset(buttonSize.width / 2, buttonSize.height / 2);
    } else {
      // Fallback
      final size = MediaQuery.of(context).size;
      _centerButtonCenter = Offset(size.width / 2, size.height - 24 - 32);
    }

    setState(() {
      _isRadialMenuOpen = true;
    });
    _startRecording();
    HapticFeedback.mediumImpact();
  }

  void _handleAICoreButtonLongPressMoveUpdate(
      LongPressMoveUpdateDetails details) {
    if (_isRadialMenuOpen) {
      // coordinates in 'details' are local to the AICoreButton (64x64).
      // We need to transform them to be relative to the same space as _centerButtonCenter (the Stack).
      final touchPosInStack =
          _centerButtonCenter + (details.localPosition - const Offset(32, 32));
      _radialMenuKey.currentState?.handleUpdate(touchPosInStack);
    }
  }

  void _handleAICoreButtonLongPressEnd(LongPressEndDetails details) {
    if (_isRadialMenuOpen) {
      _radialMenuKey.currentState?.handleRelease();
    }
  }

  /// Check and report health data
  ///
  /// Flow:
  /// 1. Iterate all supported health data types
  /// 2. Check if report conditions are met (e.g. 30/60 min interval, permission, new data)
  /// 3. If met, aggregate data into dailySummary
  /// 4. If any new data, call API to report aggregated data
  /// 5. On success, update last report date for each type
  Future<void> _checkAndReportHealthData() async {
    try {
      _logger.info('=== Starting comprehensive health check ===');

      // Detect if previous pedometer access crashed the app; skip this launch only
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('pedometer_attempting') == true) {
        _logger.warning(
            'Pedometer crash detected from previous launch, skipping this session');
        await prefs.remove('pedometer_attempting');
        // Set in-memory flag only; will retry on next app launch
        PedometerFetcher.skipThisSession = true;
      }

      final healthService = HealthService();
      Map<String, Map<String, dynamic>> dailySummary = {};

      // Use only the types registered in HealthService (Android: STEPS only,
      // iOS: all types). This respects the platform-specific strategy config.
      final typesToCheck = healthService.registeredTypes;

      // Skip health data collection if fitness permission is not granted
      // (permissions are now requested via System Authorization page)
      final fitnessStatus = Platform.isIOS
          ? await Permission.sensors.status
          : await Permission.activityRecognition.status;
      _logger.info('Fitness permission status: $fitnessStatus');
      if (!fitnessStatus.isGranted && !fitnessStatus.isLimited) {
        _logger.info(
            'Fitness permission not granted, skipping health data collection');
        return;
      }

      _logger
          .info('Types to check: ${typesToCheck.map((t) => t.name).toList()}');
      Map<HealthDataType, dynamic> newlyFetchedData = {};

      for (var type in typesToCheck) {
        _logger.info('Checking and preparing $type...');
        final data = await healthService.checkAndPrepareData(type);
        if (data != null) {
          if (data is Map && data.isNotEmpty) {
            newlyFetchedData[type] = data;

            // Merge into dailySummary
            data.forEach((dateStr, val) {
              if (!dailySummary.containsKey(dateStr)) {
                dailySummary[dateStr] = {};
              }

              // Custom merging logic depends on the shape of data
              final typeName = type.name;
              if (val is Map) {
                // If it's already a map (like heart rate min/max), merge directly or nest
                if (type == HealthDataType.HEART_RATE ||
                    type == HealthDataType.RESTING_HEART_RATE) {
                  dailySummary[dateStr]![typeName.toLowerCase()] = val;
                } else if (type == HealthDataType.BLOOD_OXYGEN) {
                  dailySummary[dateStr]!['blood_oxygen'] = val;
                } else if (type == HealthDataType.SLEEP_ASLEEP) {
                  dailySummary[dateStr]!['sleep'] = val;
                } else {
                  dailySummary[dateStr]![typeName.toLowerCase()] = val;
                }
              } else if (val is List) {
                if (type == HealthDataType.BLOOD_PRESSURE_SYSTOLIC ||
                    type == HealthDataType.BLOOD_PRESSURE_DIASTOLIC) {
                  // Merge systolic and diastolic into a single 'blood_pressure' array based on the 'time' key
                  dailySummary[dateStr]!['blood_pressure'] ??= [];
                  List existing = dailySummary[dateStr]!['blood_pressure'];
                  for (var item in val) {
                    var found =
                        existing.where((e) => e['time'] == item['time']);
                    if (found.isNotEmpty) {
                      found.first.addAll(item);
                    } else {
                      existing.add(Map<String, dynamic>.from(item));
                    }
                  }
                } else if (type == HealthDataType.WORKOUT) {
                  dailySummary[dateStr]!['workout'] = val;
                } else {
                  dailySummary[dateStr]![typeName.toLowerCase()] = val;
                }
              } else {
                // primitive like int/double
                dailySummary[dateStr]![typeName.toLowerCase()] = val;
              }
            });
          }
        }
      }

      if (dailySummary.isEmpty) {
        _logger.info('No new health data to report');
        return;
      }

      _logger.info(
          'Reporting health summary to server for ${dailySummary.length} days...');
      final success = await _memexRouter.reportDailyHealthSummary(dailySummary);

      if (success) {
        _logger.info('鉁?Successfully reported health summary.');
        // Mark success for all types that were fetched
        for (var entry in newlyFetchedData.entries) {
          await healthService.markReportSuccess(entry.key, entry.value);
        }
      } else {
        _logger.warning(
            '鉂?Failed to report health summary to server, will retry next time');
      }
    } catch (e, stackTrace) {
      _logger.severe(
          '鉂?Failed to check and report health data: $e', e, stackTrace);
    }
  }

  @override
  void dispose() {
    DemoService.instance.removeListener(_onDemoChanged);
    WidgetsBinding.instance.removeObserver(this);
    _memoryButtonTapTimer?.cancel();
    _knowledgeBaseButtonTapTimer?.cancel();
    QuickActionService.instance.detach();
    _shareIntentHandler.dispose();
    _eventBus.removeHandler(
        EventBusMessageType.invalidModelConfig, _handleInvalidModelConfig);
    _eventBus.removeHandler(
        EventBusMessageType.errorNotification, _handleErrorNotification);
    // Note: do not disconnect event bus here; other screens may still use it
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      final speechService = SpeechTranscriptionService.instance;

      _logger.info('Starting quick recording');
      // Check if local speech model needs downloading
      if (await speechService.requiresLocalModelDownload()) {
        setState(() => _isRadialMenuOpen = false);
        if (!mounted) return;
        _showSpeechModelDownloadDialog();
        return;
      }

      if (await Permission.microphone.request().isGranted) {
        // Initialize streaming transcriber (only when local model is available)
        _quickTranscribedText = '';
        _quickPcmBuffer.clear();
        if (await speechService.supportsStreamingTranscription()) {
          _logger
              .info('Initializing streaming transcriber for quick recording');
          _quickTranscriber = StreamingTranscriber(
            onTextChanged: (fullText) {
              _quickTranscribedText = fullText;
              if (mounted) setState(() {});
            },
          );
          await _quickTranscriber!.init();
          _logger.info('Streaming transcriber initialized for quick recording');
        }

        // Start streaming PCM recording
        _logger.info('Starting PCM audio stream for quick recording');
        final audioStream = await _audioRecorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000,
            numChannels: 1,
          ),
        );

        _quickAudioSub = audioStream.listen((chunk) {
          _quickPcmBuffer.addAll(chunk);
          _quickTranscriber?.addAudioChunk(chunk);
        });

        _recordingPath = 'streaming'; // marker that recording is active
      }
    } catch (e, stackTrace) {
      _logger.severe('Error starting quick recording', e, stackTrace);
    }
  }

  void _showSpeechModelDownloadDialog() {
    final sizeMB = WhisperService.modelSizeMB.toInt();

    // CN flavor: single download button
    if (AppFlavor.isCN) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text(UserStorage.l10n.speechModelDownloadTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(UserStorage.l10n.speechModelDownloadDesc(sizeMB)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _downloadSpeechModel(useChineseMirror: true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(UserStorage.l10n.speechModelStartDownload),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(UserStorage.l10n.cancel),
            ),
          ],
        ),
      );
      return;
    }

    // Global flavor: two source options
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(UserStorage.l10n.speechModelDownloadTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(UserStorage.l10n.speechModelDownloadDesc(sizeMB)),
            const SizedBox(height: 20),
            Text(
              UserStorage.l10n.speechModelChooseSource,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _downloadSpeechModel(useChineseMirror: true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(UserStorage.l10n.speechModelChinaMirror),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _downloadSpeechModel(useChineseMirror: false);
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(UserStorage.l10n.speechModelGithub),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(UserStorage.l10n.cancel),
          ),
        ],
      ),
    );
  }

  double _speechDownloadProgress = 0;
  StateSetter? _speechDownloadSetState;

  Future<void> _downloadSpeechModel({required bool useChineseMirror}) async {
    final l10n = UserStorage.l10n;
    _speechDownloadProgress = 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          _speechDownloadSetState = setDialogState;
          return AlertDialog(
            backgroundColor: Colors.white,
            title: Text(l10n.speechModelDownloading),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: _speechDownloadProgress > 0
                      ? _speechDownloadProgress
                      : null,
                  backgroundColor: AppColors.background,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  _speechDownloadProgress > 0
                      ? '${(_speechDownloadProgress * 100).toInt()}%'
                      : l10n.speechModelConnecting,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    try {
      await WhisperService.instance.downloadModel(
        useChineseMirror: useChineseMirror,
        onProgress: (p) {
          _speechDownloadSetState?.call(() {
            _speechDownloadProgress = p;
          });
        },
      );
    } catch (e) {
      _logger.severe('Speech model download failed: $e');
    } finally {
      _speechDownloadProgress = 0;
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _stopRecording({bool cancel = false}) async {
    try {
      await _quickAudioSub?.cancel();
      _quickAudioSub = null;
      await _audioRecorder.stop();

      _quickTranscriber?.dispose();
      _quickTranscriber = null;

      if (cancel) {
        _quickPcmBuffer.clear();
        _quickTranscribedText = '';
        _quickAudioPath = null;
        _recordingPath = null;
        return;
      }

      // Final calibration from accumulated PCM
      if (_quickPcmBuffer.isNotEmpty) {
        final useLocal =
            await SpeechTranscriptionService.instance.isUsingLocalModel();
        final aligned = Uint8List.fromList(_quickPcmBuffer);
        final int16Data = Int16List.view(aligned.buffer);
        final samples = Float32List(int16Data.length);
        for (int i = 0; i < int16Data.length; i++) {
          samples[i] = int16Data[i] / 32768.0;
        }

        if (useLocal) {
          final calibrated = await SpeechTranscriptionService.instance
              .transcribeSamples(samples);
          if (calibrated != null && calibrated.isNotEmpty) {
            _quickTranscribedText = calibrated;
          }
        } else {
          // Cloud mode: save WAV and submit as audio file
          final directory = await getTemporaryDirectory();
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final wavPath = '${directory.path}/quick_audio_$timestamp.wav';
          await SpeechTranscriptionService.instance
              .savePcmAsWav(wavPath, Uint8List.fromList(_quickPcmBuffer));
          _quickAudioPath = wavPath;
        }
        _quickPcmBuffer.clear();
      }
    } catch (e) {
      _logger.severe('Error stopping recording: $e', e);
    }
  }

  void _handleShortcutSelect(app_shortcut.ShortcutItem? item) async {
    final hasRecording = _recordingPath != null;

    if (item != null) {
      if (mounted) setState(() => _isRadialMenuOpen = false);
      unawaited(_handleInputSubmit(InputData(text: item.content)));
    } else if (hasRecording) {
      // Show calibrating state; keep menu open
      if (mounted) setState(() => _isQuickCalibrating = true);

      await _stopRecording(cancel: false);

      // Now dismiss and submit
      if (mounted) {
        setState(() {
          _isRadialMenuOpen = false;
          _isQuickCalibrating = false;
        });
      }
      if (_quickTranscribedText.isNotEmpty) {
        unawaited(_handleInputSubmit(InputData(text: _quickTranscribedText)));
      } else if (_quickAudioPath != null) {
        final audioFile = File(_quickAudioPath!);
        String? audioHash;
        if (await audioFile.exists()) {
          final length = await audioFile.length();
          final fileName = _quickAudioPath!.split(Platform.pathSeparator).last;
          audioHash =
              md5.convert(utf8.encode('audio_${fileName}_$length')).toString();
        }
        unawaited(
          _handleInputSubmit(
            InputData(audioPath: _quickAudioPath, audioHash: audioHash),
          ),
        );
      }
      _quickTranscribedText = '';
      _quickAudioPath = null;
      _recordingPath = null;
    } else {
      if (mounted) setState(() => _isRadialMenuOpen = false);
    }
  }

  void _handleRadialCancel() async {
    await _stopRecording(cancel: true);
    if (mounted) {
      setState(() => _isRadialMenuOpen = false);
    }
  }

  /// Consume a pending quick action (e.g. "记一下" from app icon long-press).
  /// Handles cold-start (action queued before widget built) and warm-start
  /// (action arrives while app is in background).
  void _consumeQuickActionIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final action = await QuickActionService.instance.consumePendingAction();
      if (!mounted) return;
      if (action == 'quick_note') {
        _logger.info('Quick action: opening input sheet');
        setState(() {
          _isInputOpen = true;
        });
      }
    });
  }

  Future<void> _handleExternalBackupFile(String backupFilePath) async {
    if (_isRestoringExternalBackup) return;
    _isRestoringExternalBackup = true;

    try {
      final backupInfo = await BackupService.inspectBackup(backupFilePath);
      if (!mounted) return;

      final confirmed = await _confirmExternalBackupRestore(backupInfo);
      if (confirmed != true || !mounted) return;

      await _restoreExternalBackup(backupInfo.path);
    } catch (e) {
      if (mounted) {
        ToastHelper.showError(context, UserStorage.l10n.restoreFailed(e));
      }
    } finally {
      _isRestoringExternalBackup = false;
    }
  }

  Future<bool?> _confirmExternalBackupRestore(BackupFileInfo backupInfo) {
    final dialogContext = rootNavigatorKey.currentContext ?? context;

    return showDialog<bool>(
      context: dialogContext,
      builder: (_) => BackupRestoreConfirmDialog(backupInfo: backupInfo),
    );
  }

  Future<void> _restoreExternalBackup(String backupFilePath) async {
    final dialogContext = rootNavigatorKey.currentContext ?? context;
    final rootNavigator = Navigator.of(dialogContext, rootNavigator: true);
    var statusText = UserStorage.l10n.restoreInProgress;
    StateSetter? setProgressState;

    showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          setProgressState = setState;
          return AlertDialog(
            backgroundColor: Colors.white,
            content: Row(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(statusText)),
              ],
            ),
          );
        },
      ),
    );

    try {
      await BackupService.restoreBackup(
        backupFilePath,
        onProgress: (status) {
          setProgressState?.call(() {
            statusText = status;
          });
        },
      );

      if (!mounted || !rootNavigator.mounted) return;
      rootNavigator.pop();
      await showDialog<void>(
        context: rootNavigator.context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text(UserStorage.l10n.restoreComplete),
          content: Text(UserStorage.l10n.restoreRestartHint),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: Text(UserStorage.l10n.ok),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted && rootNavigator.mounted) {
        rootNavigator.pop();
      }
      rethrow;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Reset consumed-action dedup so the same shortcut can be triggered
      // on the next foreground session.
      QuickActionService.instance.resetConsumed();
    }
    // when app enters foreground, ensure event bus is connected
    if (state == AppLifecycleState.resumed) {
      if (!_eventBus.isConnected) {
        _eventBus.connect();
      }
      // Consume any quick action that arrived while in background.
      // Use synchronous check; platform callback fires before resumed,
      // so no need for the 2-sec wait (which could catch a re-delivered intent).
      final action = QuickActionService.instance.consumeIfPending();
      if (action == 'quick_note' && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _logger.info('Quick action (resumed): opening input sheet');
            setState(() => _isInputOpen = true);
          }
        });
      }
    }
  }

  Future<bool> _handleInputSubmit(InputData data) async {
    // During demo: advance tapSend 鈫?tapCard first, so the overlay
    // immediately shows a blocking scrim (cardReady is still false).
    DemoService.instance.tryAdvance(DemoStep.tapSend);

    // Close input sheet immediately
    if (mounted) {
      setState(() {
        _isInputOpen = false;
        _sharedDraft = null;
      });
    }

    // TimelineViewModel has been removed.

    try {
      // Call API
      final response = await _memexRouter.submitInput(
        text: data.text,
        images: data.images,
        audioPath: data.audioPath,
        textHash: data.textHash,
        imageHashes: data.imageHashes,
        audioHash: data.audioHash,
      );

      // Parse response and add card to timeline
      if (response.containsKey('card')) {
        // TimelineViewModel has been removed.

        // update last publish timestamp
        await PublishTimestampService.saveLastPublishTimestamp(
          DateTime.now().millisecondsSinceEpoch,
        );

        // During demo: write preset completed card with insight/comment
        if (DemoService.instance.isActive) {
          final userId = await UserStorage.getUserId();
          if (userId != null) {
            DemoService.instance.handleDemoSubmit(
              userId,
              response['fact_id'] as String,
              data.text ?? '',
            );
          }
        }
      }

      // Show success message
      if (mounted) {
        ToastHelper.showSuccess(
            context, UserStorage.l10n.recordSubmittedAiProcessing);
      }

      // Refresh auto-input count after manual input
      // since the manual input might have consumed items that were pending auto-publish.
      return true;
    } catch (e) {
      // TimelineViewModel has been removed.

      if (mounted) {
        ToastHelper.showError(context, e);
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return const CompanionFirstShell();
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The 393x120.5 Figma Canvas scaled flawlessly to screen width
          FittedBox(
            fit: BoxFit.fitWidth,
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 393,
              // PNG bounding box height: 120.5 (includes 20px top shadow + 80.5px white shape)
              height: 120.5,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Painted Native Vector Overlay
                  // Completely removing dependencies on Figma PNG/SVG transparent paddings!
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _NavBarPainter(),
                    ),
                  ),

                  // Shadow occluder mask
                  // The Figma export's shadow has a giant blur that leaks downward.
                  // Placed OVER the image at exactly y=100.0 (where the white shape ends)
                  // It completely masks out the grey blur and extends solidly into the Safe Area.
                  Positioned(
                    top: 100.0,
                    bottom: -100.0,
                    left: 0,
                    right: 0,
                    child: Container(color: Colors.white),
                  ),

                  // Center Action Button (88x88 widget, 68x68 nested circle)
                  // Dialed down to -16.0 for a more subdued hover gap.
                  Positioned(
                    top: -16.0,
                    left: 156.0,
                    child: AICoreButton(
                      key: DemoService.instance.isActive
                          ? DemoService.instance.addButtonKey
                          : _aiButtonKey,
                      onTap: () {
                        // Advance first so _handleAICoreButtonTap sees tapSend step for prefill
                        DemoService.instance.tryAdvance(DemoStep.tapAddButton);
                        _handleAICoreButtonTap();
                      },
                      onLongPress: _handleAICoreButtonLongPressStart,
                      onLongPressMoveUpdate:
                          _handleAICoreButtonLongPressMoveUpdate,
                      onLongPressEnd: _handleAICoreButtonLongPressEnd,
                    ),
                  ),

                  // Timeline Icon
                  Positioned(
                    top: 46.63, // 26.63 local + 20px shadow
                    left: 64.17,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _handleTimelineTabTap,
                      child: SvgPicture.asset(
                        'assets/icons/tab_timeline_active.svg',
                        width: 22,
                        height: 23,
                        colorFilter: ColorFilter.mode(
                          _currentTab == 0
                              ? const Color(0xFF1F1F1F)
                              : const Color(0xFF99A1AF),
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),

                  // Timeline Text
                  Positioned(
                    top: 76.0,
                    left: 25.17,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _handleTimelineTabTap,
                      child: SizedBox(
                        width:
                            100, // Widened from strict 58 to permit iOS text expansion
                        // Removed strict height boundary to prevent vertical ascender clipping
                        child: Text(
                          UserStorage.l10n.bottomNavTimeline,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: _currentTab == 0
                                ? const Color(0xFF1F1F1F)
                                : const Color(0xFF99A1AF),
                            letterSpacing: 0.14,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Library: single widget for both icon + text so the
                  // demo spotlight key covers the whole tab area.
                  Positioned(
                    top: 47.02,
                    left: 299.58,
                    child: GestureDetector(
                      key: DemoService.instance.knowledgeTabKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _handleLibraryTabTap();
                        DemoService.instance
                            .tryAdvance(DemoStep.tapKnowledgeTab);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset(
                            'assets/icons/tab_library_inactive.svg',
                            width: 25.06,
                            height: 21.15,
                            colorFilter: ColorFilter.mode(
                              _currentTab == 1
                                  ? const Color(0xFF1F1F1F)
                                  : const Color(0xFF99A1AF),
                              BlendMode.srcIn,
                            ),
                          ),
                          SizedBox(height: 76.0 - 47.02 - 21.15),
                          Text(
                            UserStorage.l10n.bottomNavLibrary,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: _currentTab == 1
                                  ? const Color(0xFF1F1F1F)
                                  : const Color(0xFF99A1AF),
                              letterSpacing: 0.14,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleTimelineTabTap() {
    _memoryButtonTapCount++;
    if (_memoryButtonTapCount == 1) {
      setState(() => _currentTab = 0);
      _memoryButtonTapTimer?.cancel();
      _memoryButtonTapTimer = Timer(const Duration(milliseconds: 300), () {
        _memoryButtonTapCount = 0;
      });
    } else if (_memoryButtonTapCount == 2) {
      _memoryButtonTapTimer?.cancel();
      _memoryButtonTapCount = 0;
      // TimelineScreen has been removed.
    }
  }

  void _handleLibraryTabTap() {
    _knowledgeBaseButtonTapCount++;
    if (_knowledgeBaseButtonTapCount == 1) {
      setState(() => _currentTab = 1);
      _knowledgeBaseButtonTapTimer?.cancel();
      _knowledgeBaseButtonTapTimer =
          Timer(const Duration(milliseconds: 300), () {
        _knowledgeBaseButtonTapCount = 0;
      });
    } else if (_knowledgeBaseButtonTapCount == 2) {
      _knowledgeBaseButtonTapTimer?.cancel();
      _knowledgeBaseButtonTapCount = 0;
      // KnowledgeBaseScreen has been removed.
    }
  }
}

class _NavBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path();
    path.moveTo(0, 20);
    path.lineTo(142.528, 20);
    path.cubicTo(148.501, 20, 153.977, 23.3275, 156.729, 28.6293);
    path.lineTo(164.497, 43.5965);
    path.cubicTo(179.426, 72.3609, 220.574, 72.3609, 235.503, 43.5966);
    path.lineTo(243.271, 28.6293);
    path.cubicTo(246.023, 23.3275, 251.499, 20, 257.472, 20);
    path.lineTo(size.width, 20);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.lineTo(0, 20);
    path.close();

    // Custom drop shadow that doesn't bleed weirdly
    // We clip the bottom so the shadow never goes below the nav bar visually
    canvas.save();
    canvas
        .clipRect(Rect.fromLTWH(-50, -50, size.width + 100, size.height + 50));
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withOpacity(0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0),
    );
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
