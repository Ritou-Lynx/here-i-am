import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/agent/context/user_knowledge_context_service.dart';

Tool buildUserKnowledgeQueryTool({required String userId}) {
  return Tool(
    name: 'UserKnowledgeQuery',
    description: '''Query the user's legacy Memex timeline cards and PKM files.

Use this before answering exact questions about facts the user may have
recorded previously. This complements `LifeMemoryQuery`: legacy Memex records
cover the existing card and knowledge-base history, while shared-life records
cover newly extracted companion conversations. Query instead of guessing.''',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description':
              'Keywords or a focused natural-language question about prior records.',
        },
        'limit': {
          'type': 'integer',
          'description': 'Maximum number of results. Defaults to 8.',
        },
      },
      'required': ['query'],
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> args) async {
      try {
        final query = args['query']?.toString().trim() ?? '';
        if (query.isEmpty) {
          throw const FormatException('Missing required field: query');
        }
        final rawLimit = args['limit'];
        final parsedLimit =
            rawLimit is num ? rawLimit.toInt() : int.tryParse('$rawLimit');
        final limit = (parsedLimit ?? 8).clamp(1, 20);
        final context =
            await UserKnowledgeContextService.instance.buildKnowledgeCards(
          userId: userId,
          queryHint: query,
          maxCards: limit,
          exhaustiveLegacyFallback: true,
        );
        return jsonEncode({
          'success': true,
          'query': query,
          'context': context,
        });
      } catch (e) {
        return jsonEncode({'success': false, 'error': e.toString()});
      }
    },
  );
}
