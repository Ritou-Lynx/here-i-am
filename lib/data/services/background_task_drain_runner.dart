import 'package:shared_preferences/shared_preferences.dart';

import 'package:memex/data/services/custom_agent_config_service.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/local_task_registry.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/user_storage.dart';

class BackgroundTaskDrainRunner {
  BackgroundTaskDrainRunner._();

  static const foregroundMaxDuration = Duration(hours: 2);
  static const foregroundProcessingResetAge = Duration(minutes: 2);
  static const workmanagerMaxDuration = Duration(minutes: 9);

  static Future<TaskActivitySnapshot> run({
    Duration maxDuration = workmanagerMaxDuration,
    Duration processingResetAge = const Duration(seconds: 30),
    bool resetProcessingOnStart = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('current_user_id');
    if (userId == null || userId.isEmpty) {
      return const TaskActivitySnapshot.empty();
    }

    await UserStorage.initL10n();
    final dataRoot = await UserStorage.resolveDataRoot(userId);
    await FileSystemService.init(dataRoot);
    if (!AppDatabase.isInitialized) {
      await AppDatabase.init(userId);
    }
    SharedLifeMemoryService.init(AppDatabase.instance, userId);

    registerLocalTaskHandlers();
    await CustomAgentConfigService.instance.registerAll(userId);

    if (resetProcessingOnStart) {
      await LocalTaskExecutor.instance
          .resetProcessingTasksForBackgroundHandoff(minAge: processingResetAge);
    }

    return LocalTaskExecutor.instance.drainUntilIdle(
      userId: userId,
      maxDuration: maxDuration,
      processingResetAge: processingResetAge,
    );
  }
}
