import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:memex/data/services/custom_agent_config_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/local_task_registry.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

class BackgroundTaskDrainService {
  BackgroundTaskDrainService._();

  static const taskName = 'memex_background_task_drain';
  static final _logger = getLogger('BackgroundTaskDrainService');

  static Future<void> scheduleDrain() async {
    if (!Platform.isAndroid) return;

    try {
      await Workmanager().registerOneOffTask(
        taskName,
        taskName,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        existingWorkPolicy: ExistingWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(seconds: 30),
      );
      _logger.info('Scheduled Android background task drain');
    } catch (e, st) {
      _logger.warning('Failed to schedule Android background task drain', e, st);
    }
  }

  static Future<bool> runFromWorkmanager() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('current_user_id');
    if (userId == null || userId.isEmpty) {
      _logger.warning('No current user ID for background task drain');
      return false;
    }

    await UserStorage.initL10n();
    final dataRoot = await UserStorage.resolveDataRoot(userId);
    await FileSystemService.init(dataRoot);
    if (!AppDatabase.isInitialized) {
      await AppDatabase.init(userId);
    }

    registerLocalTaskHandlers();
    await CustomAgentConfigService.instance.registerAll(userId);

    final snapshot = await LocalTaskExecutor.instance.drainUntilIdle(
      userId: userId,
    );
    _logger.info(
      'Background task drain finished: pending=${snapshot.pending}, '
      'processing=${snapshot.processing}, retrying=${snapshot.retrying}',
    );

    return snapshot.processing == 0;
  }
}
