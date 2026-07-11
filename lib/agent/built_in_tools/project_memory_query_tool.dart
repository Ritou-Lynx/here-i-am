import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/memory_v3/retrieval/project_memory_intent_classifier.dart';
import 'package:memex/data/memory_v3/services/project_memory_service.dart';
import 'package:memex/db/app_database.dart';

/// Explicit project-work recall. Never searches User-truth or Dreaming.
Tool buildProjectMemoryQueryTool() {
  return Tool(
    name: 'project_memory_query',
    description: '''Search policy-approved Project Memory only.

Use this when the user explicitly asks about a software/product/research/writing project, its progress, decisions, completed work, open loops, or artifacts. Do not use it for ordinary life recall, relationship memory, schedules, health, shopping, or generic conversation.''',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description':
              'Distinctive project keywords and the requested progress/decision.',
        },
      },
      'required': ['query'],
    },
    executable: (String query) async {
      if (!AppDatabase.isInitialized) return 'Project Memory is unavailable.';
      final isProjectIntent =
          ProjectMemoryIntentClassifier.isProjectIntent(query);
      if (!isProjectIntent) {
        return 'Project Memory was not searched because this is not an explicit project-work query.';
      }

      final service = ProjectMemoryService(AppDatabase.instance);
      final allowedProjectIds = await service.projectedProjectIds();
      final hits = await service.search(
        query,
        scope: ProjectMemoryQueryScope(
          isProjectIntent: true,
          allowedProjectIds: allowedProjectIds,
        ),
      );
      if (hits.isEmpty) return 'No matching Project Memory was found.';

      final out =
          StringBuffer('Found ${hits.length} project memory item(s):\n');
      for (final hit in hits.take(8)) {
        out.writeln('\n- [${hit.projectKey}] ${hit.summary}');
        if (hit.decisions.isNotEmpty) {
          out.writeln('  Decisions: ${hit.decisions.join('; ')}');
        }
        if (hit.openLoops.isNotEmpty) {
          out.writeln('  Open loops: ${hit.openLoops.join('; ')}');
        }
        if (hit.artifactRefs.isNotEmpty) {
          out.writeln('  Artifacts: ${hit.artifactRefs.join(', ')}');
        }
        out.writeln('  Source: ${hit.sourceTool}; '
            '${DateTime.fromMillisecondsSinceEpoch(hit.occurredAt).toIso8601String()}');
      }
      return out.toString();
    },
  );
}
