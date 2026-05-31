import 'dart:io';

import 'package:workmanager/workmanager.dart';

import 'package:memex/data/services/background_task_drain_runner.dart';
import 'package:memex/data/services/background_task_foreground_service.dart';
import 'package:memex/utils/logger.dart';

class BackgroundTaskDrainService {
  BackgroundTaskDrainService._();

  static const taskName = 'memex_background_task_drain';
  static final _logger = getLogger('BackgroundTaskDrainService');

  static Future<void> scheduleDrain() async {
    if (!Platform.isAndroid) return;

    try {
      final started = await BackgroundTaskForegroundService.triggerDrain();
      if (started) {
        _logger.info('Started Android foreground task drain');
        return;
      }
    } catch (e, st) {
      _logger.warning('Failed to start Android foreground task drain', e, st);
    }

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
      _logger.warning(
          'Failed to schedule Android background task drain', e, st);
    }
  }

  static Future<bool> runFromWorkmanager() async {
    final snapshot = await BackgroundTaskDrainRunner.run();
    _logger.info(
      'Background task drain finished: pending=${snapshot.pending}, '
      'processing=${snapshot.processing}, retrying=${snapshot.retrying}',
    );

    return !snapshot.hasActiveTasks;
  }
}
