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
