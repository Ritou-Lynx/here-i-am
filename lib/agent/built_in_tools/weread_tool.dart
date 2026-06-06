import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:path/path.dart' as p;

/// Built-in tool that lets the companion read locally-cached WeRead data.
///
/// WeReadSyncService periodically fetches shelf data from the WeRead API and
/// writes a human-readable summary to a local file. This tool exposes that
/// cached summary to the companion agent so it can mention reading progress,
/// recent books, etc. without hitting the network itself.
///
/// If WeRead has not been configured or no data has been synced yet, the tool
/// returns an informative message instead of throwing.
Tool buildWereadTool({required String userId}) {
  return Tool(
    name: 'weread_read',
    description: '''Read the user's WeRead (微信读书) reading data.

Use this tool when you want to know what the user is currently reading, their
reading progress, recently finished books, or reading statistics.

Good moments to call this:
- You noticed a book-related record in recent_activity_snapshot
- The user mentioned reading or a specific book in a recent chat
- You want to find a natural conversation opener related to their reading life
- You haven't checked in a while and are curious about their reading progress

Returns the cached reading summary (updated periodically). If WeRead is not
configured, returns a message indicating data is unavailable.''',
    parameters: {
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <String>[],
    },
    executable: () async {
      try {
        final fileService = FileSystemService.instance;
        final summaryPath = p.join(
          fileService.getUserSettingsPath(userId),
          'external_data',
          'weread',
          'reading_summary.md',
        );
        final file = File(summaryPath);
        if (!await file.exists()) {
          return 'WeRead data is not available (not configured or not yet synced).';
        }
        final content = await file.readAsString();
        if (content.trim().isEmpty) {
          return 'WeRead data file exists but is empty.';
        }
        return content;
      } catch (e) {
        return 'Failed to read WeRead data: $e';
      }
    },
  );
}
