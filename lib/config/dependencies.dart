import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:memex/data/memory_v3/notes/claude_web_note_feed_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/memory_v3/agents/record_organizer_agent/agent.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub_runtime.dart';
import 'package:memex/data/personal_data_hub/domain_access.dart';
import 'package:memex/data/personal_data_hub/planning_models.dart';
import 'package:memex/data/personal_data_hub/planning_reminders.dart';
import 'package:memex/data/personal_data_hub/quick_capture_organizer_adapter.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/ui/companion/widgets/personal_data_hub_runtime_scope.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub_runtime_owner.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub.dart';
// Copyright 2024 The Memex team. All rights reserved.
// Aligned with Flutter Compass app: config registers only Repository/Service,
// not ViewModels. ViewModels are created where the screen is built.

import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/memory_v3/services/topic_thread_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/game/game_definition_import_service.dart';
import 'package:memex/data/services/game/game_session_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/chat_view_mode_controller.dart';
import 'package:memex/ui/core/themes/here_iam_theme_controller.dart';
import 'package:memex/ui/core/themes/spring_rain_chat_color_controller.dart';

/// Shared dependency providers for the app.
/// Only register Repository and Service here; do not register ViewModels.
/// ViewModels are created in the place that builds the screen (route builder
/// or parent widget), using context.read<MemexRouter>() etc.
List<SingleChildWidget> get dependencyProviders => [
      Provider<ClaudeWebNoteFeedService>(
        create: (_) => ClaudeWebNoteFeedService(
          storage: ClaudeWebNoteFeedStorage(),
          importerFactory: () => ClaudeWebNoteImporter(
            db: AppDatabase.instance,
            organizer: RecordOrganizerServiceV3(AppDatabase.instance),
            organize: (source) async {
              final resources = await UserStorage.getAgentLLMResources(
                  AgentDefinitions.recordOrganizerAgent,
                  defaultClientKey: LLMConfig.defaultClientKey);
              return const RecordOrganizerAgentV3().organize(
                  client: resources.client,
                  modelConfig: resources.modelConfig,
                  rawInput: source.rawInput,
                  now: source.recordedAt);
            },
          ),
        ),
        dispose: (_, service) => unawaited(service.dispose()),
      ),
      ChangeNotifierProvider<PersonalDataHubRuntimeOwner>(
        lazy: false,
        create: (_) => PersonalDataHubRuntimeOwner(create: _createHubRuntime),
        builder: (_, child) => PersonalDataHubRuntimeScope(child: child!),
      ),
      Provider<PersonalDataHub>(
          create: (_) => PersonalDataHub.forDatabase(AppDatabase.instance)),
      Provider<MemexRouter>(
        create: (_) => MemexRouter(),
      ),
      // Memory V3 services — constructor-injected with AppDatabase.instance.
      // AppDatabase.init() is called before these providers are accessed.
      Provider<TopicThreadService>(
        create: (_) => TopicThreadService(db: AppDatabase.instance),
      ),
      // Game services — constructor-injected with AppDatabase.instance.
      // FileSystemService.instance is initialised before any provider is first
      // accessed, so dataRoot is available at create() time.
      Provider<GameSessionService>(
        create: (_) => GameSessionService(AppDatabase.instance),
      ),
      Provider<GameDefinitionImportService>(
        create: (_) => GameDefinitionImportService(
          AppDatabase.instance,
          avatarDirectory: p.join(
            FileSystemService.instance.dataRoot,
            'game_cards',
          ),
        ),
      ),
      ChangeNotifierProvider<HereIamThemeController>(
        create: (_) => HereIamThemeController()..load(),
      ),
      ChangeNotifierProvider<SpringRainChatColorController>(
        create: (_) => SpringRainChatColorController()..load(),
      ),
      ChangeNotifierProvider<ChatViewModeController>(
        create: (_) => ChatViewModeController()..load(),
      ),
    ];

/// Domain credentials and trusted authorization remain owner-configured.
/// The default only records explicitly requested captures on this installation.
Future<PersonalDataHubRuntime> _createHubRuntime() async {
  var userId = await UserStorage.getUserId();
  if (userId == null) {
    await UserStorage.saveUser('Lynx');
    userId = await UserStorage.getUserId();
  }
  if (userId == null) throw StateError('No local account');
  await AppDatabase.init(userId);
  final db = AppDatabase.instance;
  final hub = PersonalDataHub.forDatabase(db);
  final domainAccess = await loadOptionalDomainAccess(
    hub: hub,
    reportError: debugPrint,
  );
  return PersonalDataHubRuntime.create(
    db: db,
    hub: hub,
    alarms: const CheckinPlanningAlarmScheduler(),
    enablePlanningReminders:
        PlatformDispatcher.instance.defaultRouteName != '/quick-capture',
    ownsCaptureConnectionLifetime:
        PlatformDispatcher.instance.defaultRouteName != '/quick-capture',
    quickCaptureAuthorize: domainAccess?.authorizeCapture,
    planningAuthorize: domainAccess?.authorizePlanning,
    connection: () {
      final configured =
          planningDomains.where((name) => hub.storeFor(name) != null);
      if (configured.isEmpty) return PlanningConnection.unknown;
      if (configured.any(hub.lastSyncErrors.containsKey)) {
        return PlanningConnection.offline;
      }
      return configured.every(hub.syncedDomains.contains)
          ? PlanningConnection.online
          : PlanningConnection.unknown;
    },
    extract: (text) async {
      final resources = await UserStorage.getAgentLLMResources(
          AgentDefinitions.recordOrganizerAgent,
          defaultClientKey: LLMConfig.defaultClientKey);
      return QuickCaptureOrganizerAdapter(
              client: resources.client, modelConfig: resources.modelConfig)
          .extract(text);
    },
  );
}
