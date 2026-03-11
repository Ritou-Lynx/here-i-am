import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/utils/logger.dart';
import 'package:path/path.dart' as p;

class PkmStatsService {
  static final Logger _logger = getLogger('PkmStatsService');
  static const String _statsFileName = 'pkm_stats.json';
  static const int _maxHistorySize = 5;

  // Singleton instance
  static final PkmStatsService _instance = PkmStatsService._internal();
  static PkmStatsService get instance => _instance;

  PkmStatsService._internal();

  /// Records a session of file edits for a user.
  ///
  /// [userId] The ID of the user.
  /// [editedFiles] A list of absolute file paths that were edited in this session.
  Future<void> recordSessionEdits(
      String userId, List<String> editedFiles) async {
    final statsFile = _getStatsFile(userId);
    Map<String, dynamic> stats = {};

    if (statsFile.existsSync()) {
      try {
        final content = await statsFile.readAsString();
        stats = jsonDecode(content);
      } catch (e) {
        _logger.warning('Failed to read stats file: $e');
        // If file is corrupted, we start fresh
      }
    }

    List<dynamic> recentSessions = [];
    if (stats.containsKey('recent_sessions')) {
      recentSessions = List.from(stats['recent_sessions']);
    }

    // Add new session
    recentSessions.add({
      'timestamp': DateTime.now().toIso8601String(),
      'edited_files': editedFiles,
    });

    // Trim history to max size
    if (recentSessions.length > _maxHistorySize) {
      recentSessions =
          recentSessions.sublist(recentSessions.length - _maxHistorySize);
    }

    stats['recent_sessions'] = recentSessions;

    try {
      if (!statsFile.parent.existsSync()) {
        statsFile.parent.createSync(recursive: true);
      }
      await statsFile.writeAsString(jsonEncode(stats));
    } catch (e) {
      _logger.warning('Failed to write stats file: $e');
    }
  }

  /// Gets the count of recent sessions where the file was edited.
  ///
  /// [userId] The ID of the user.
  /// [filePath] The absolute path of the file to check.
  /// Returns the number of sessions in the last [_maxHistorySize] sessions where this file was edited.
  Future<int> getRecentEditCount(String userId, String filePath) async {
    final statsFile = _getStatsFile(userId);
    if (!statsFile.existsSync()) {
      return 0;
    }

    try {
      final content = await statsFile.readAsString();
      final stats = jsonDecode(content);

      if (!stats.containsKey('recent_sessions')) {
        return 0;
      }

      final recentSessions = stats['recent_sessions'] as List;
      int count = 0;

      // Normalize filePath to ensure consistent matching
      // We assume paths stored are consistent (e.g. absolute)
      final normalizedPath = p.normalize(filePath);

      for (var session in recentSessions) {
        final editedFiles = (session['edited_files'] as List).cast<String>();
        // Check if file is in this session's edits
        // We use p.equals to handle path separators correctly across platforms if needed,
        // but simple string comparison might suffice if paths are consistently absolute.
        // Let's use simple normalization and comparison for now.
        if (editedFiles.any((f) => p.normalize(f) == normalizedPath)) {
          count++;
        }
      }
      _logger.info('File $filePath was edited $count times in the last $_maxHistorySize sessions.');
      return count;
    } catch (e) {
      _logger.warning('Failed to read stats file: $e');
      return 0;
    }
  }

  @visibleForTesting
  File Function(String userId)? getStatsFileOverride;

  File _getStatsFile(String userId) {
    if (getStatsFileOverride != null) {
      return getStatsFileOverride!(userId);
    }
    final systemPath = FileSystemService.instance.getSystemPath(userId);
    return File(p.join(systemPath, _statsFileName));
  }
}
