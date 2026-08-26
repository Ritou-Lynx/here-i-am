import 'dart:io';

import 'package:logging/logging.dart';
import 'package:memex/data/memory_v3/services/life_insight_scheduler.dart';
import 'package:memex/data/services/coros_mcp_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/mcp_token_storage.dart';
import 'package:memex/db/app_database.dart';

/// Syncs COROS health/fitness data to local files so the insight agent can
/// discover and analyze it alongside other workspace data.
///
/// Data is written to `_UserSettings/external_data/coros/`.
class CorosSyncService {
  static final _logger = Logger('CorosSyncService');

  /// Fetch COROS data and write summary files to local storage.
  ///
  /// Returns true if data was synced, false if COROS is not connected.
  /// Never throws — failures are logged and swallowed.
  static Future<bool> syncIfConfigured(String userId) async {
    final result = await syncDetailed(userId);
    return result.synced;
  }

  static Future<CorosSyncResult> syncDetailed(String userId) async {
    final storage = McpTokenStorage(userId: userId);
    final token = await storage.load();
    if (token == null) {
      _logger.info('COROS not connected, skipping sync');
      return const CorosSyncResult(
        synced: false,
        message: 'COROS 尚未连接，请先在设置中完成授权',
      );
    }

    final fileService = FileSystemService.instance;
    final dirPath =
        '${fileService.getUserSettingsPath(userId)}/external_data/coros';
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final service = CorosMcpService.instance;
    var anySuccess = false;
    String? userInfoText;
    final failures = <String>[];

    void recordFailure(String label, Object e) {
      final short = e.toString().split('\n').first;
      failures.add('$label: ${short.length > 120 ? short.substring(0, 120) : short}');
    }

    try {
      await service.ensureConnected(userId: userId);
      if (!service.isConnected) {
        final detail = service.lastError ?? 'MCP连接失败(no detail)';
        return CorosSyncResult(
          synced: false,
          message: 'COROS 连接失败，请检查授权状态',
          detail: detail,
        );
      }

      // 1. User profile
      try {
        final info = await service.queryUserInfo();
        userInfoText = info.text;
        await File('$dirPath/user_info.txt').writeAsString(info.text);
        anySuccess = true;
      } catch (e) {
        recordFailure('用户信息', e);
        _logger.warning('Failed to sync user info: $e');
      }

      // 2. Daily health data (last 7 days)
      try {
        final health = await service.queryDailyHealthData(days: 7);
        await File('$dirPath/daily_health.json').writeAsString(health.text);
        anySuccess = true;
      } catch (e) {
        recordFailure('日常健康', e);
        _logger.warning('Failed to sync daily health: $e');
      }

      // 3. Sleep data (last 7 days)
      try {
        final sleep = await service.querySleepData(days: 7);
        await File('$dirPath/sleep_data.json').writeAsString(sleep.text);
        anySuccess = true;
      } catch (e) {
        recordFailure('睡眠', e);
        _logger.warning('Failed to sync sleep data: $e');
      }

      // 4. Fitness assessment overview
      try {
        final fitness = await service.queryFitnessAssessmentOverview();
        await File('$dirPath/fitness_assessment.txt')
            .writeAsString(fitness.text);
        anySuccess = true;
      } catch (e) {
        recordFailure('体能评估', e);
        _logger.warning('Failed to sync fitness assessment: $e');
      }

      // 5. Recovery status
      try {
        final recovery = await service.queryRecoveryStatus();
        await File('$dirPath/recovery_status.txt').writeAsString(recovery.text);
        anySuccess = true;
      } catch (e) {
        recordFailure('恢复状态', e);
        _logger.warning('Failed to sync recovery status: $e');
      }

      // 6. Recent sport records (last 7 days)
      try {
        final records = await service.querySportRecords(limit: 10);
        await File('$dirPath/recent_sport_records.json')
            .writeAsString(records.text);
        anySuccess = true;
      } catch (e) {
        recordFailure('运动记录', e);
        _logger.warning('Failed to sync sport records: $e');
      }

      // 7. Training schedule
      try {
        final schedule = await service.queryTrainingSchedule();
        await File('$dirPath/training_schedule.json')
            .writeAsString(schedule.text);
        anySuccess = true;
      } catch (e) {
        recordFailure('训练计划', e);
        _logger.warning('Failed to sync training schedule: $e');
      }

      // 8. Write a human-readable summary
      if (anySuccess) {
        await _writeSummary(dirPath, userInfoText);
      }
    } finally {
      // Don't disconnect — keep the session alive for agent queries
    }

    _logger.info('COROS sync ${anySuccess ? 'completed' : 'failed'}');

    // Trigger LifeInsight analysis after fresh health data is available.
    if (anySuccess && AppDatabase.isInitialized) {
      try {
        LifeInsightScheduler(db: AppDatabase.instance).scheduleEventDriven();
      } catch (e) {
        _logger.fine('COROS sync: LifeInsight trigger failed: $e');
      }
    }

    return CorosSyncResult(
      synced: anySuccess,
      message: anySuccess ? 'COROS MCP 数据已同步' : '同步失败，请查看详情',
      detail: failures.isEmpty ? null : failures.join('\n'),
    );
  }

  static Future<void> _writeSummary(
      String dirPath, String? userInfoText) async {
    final buf = StringBuffer();
    buf.writeln('# COROS Health Data Summary');
    buf.writeln();
    buf.writeln('Last synced: ${DateTime.now().toIso8601String()}');
    buf.writeln();

    if (userInfoText != null) {
      buf.writeln('## User Profile');
      buf.writeln(userInfoText);
      buf.writeln();
    }

    buf.writeln('## Available Data Files');
    buf.writeln('- user_info.txt — Basic profile');
    buf.writeln(
        '- daily_health.json — Steps, calories, HR, stress, sleep (7 days)');
    buf.writeln('- sleep_data.json — Detailed sleep (7 days)');
    buf.writeln(
        '- fitness_assessment.txt — VO2max, running level, race predictions');
    buf.writeln('- recovery_status.txt — Current recovery percentage');
    buf.writeln('- recent_sport_records.json — Recent workouts');
    buf.writeln('- training_schedule.json — Current training plan');

    await File('$dirPath/README.md').writeAsString(buf.toString());
  }
}

class CorosSyncResult {
  const CorosSyncResult({
    required this.synced,
    required this.message,
    this.detail,
  });

  final bool synced;
  final String message;

  /// Raw per-request or connection failure details for debugging/UI display.
  final String? detail;
}
