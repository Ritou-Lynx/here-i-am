import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/dev_agent_bridge_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';

Tool buildDevSessionStartOrContinueTool({
  required String characterId,
  required String characterName,
  DevAgentBridgeService? service,
}) {
  final bridgeService = service ?? DevAgentBridgeService.instance;
  final logger = getLogger('DevSessionTool');

  return Tool(
    name: 'dev_session_start_or_continue',
    description:
        'Summon Claude Code or Codex through Dev Room to read project files, '
        'review code, modify code, inspect a local archive, or continue a '
        'multi-turn development/research task. Use this when the user asks '
        'you to make Codex/Claude Code do project work, read a folder of '
        'articles, review a repo, or continue a prior Dev Session. The tool '
        'starts work asynchronously; you must still reply in your own '
        'character voice and tell the user that the Dev Session has started. '
        'Do not use it for ordinary emotional chat, memory writes, reminders, '
        'shopping, or questions you can answer directly.',
    parameters: {
      'type': 'object',
      'properties': {
        'message': {
          'type': 'string',
          'description':
              'The concrete instruction for Claude Code/Codex. Include the '
                  'user goal, relevant file/folder names, and what output is '
                  'expected.',
        },
        'agent_type': {
          'type': 'string',
          'enum': ['codex', 'claude_code'],
          'description':
              'Which coding agent to use. Prefer codex for reading, review, '
                  'analysis, and cautious implementation; use claude_code '
                  'when the user explicitly asks for Claude Code or when a '
                  'known existing Claude Code session should continue.',
        },
        'project_id': {
          'type': 'string',
          'description':
              'Optional exact Dev Project id. If omitted, project_name or the '
                  'only configured project will be used.',
        },
        'project_name': {
          'type': 'string',
          'description':
              'Optional Dev Project name. Use when the user names a project '
                  'but you do not know its id.',
        },
        'session_id': {
          'type': 'string',
          'description':
              'Optional existing Dev Session id. Pass this to continue a '
                  'known session directly.',
        },
        'reuse_latest': {
          'type': 'boolean',
          'description':
              'If true and session_id is omitted, continue the latest active '
                  'session for this character/project/agent instead of '
                  'creating a new one.',
        },
        'title': {
          'type': 'string',
          'description':
              'Short title for a new session. Use the user goal, not a generic title.',
        },
        'goal': {
          'type': 'string',
          'description':
              'Optional longer goal for a new session, useful for reading or '
                  'multi-step coding work.',
        },
        'mode': {
          'type': 'string',
          'enum': ['read_only', 'workspace_write'],
          'description':
              'Requested mode for the session record. Actual permissions are '
                  'still limited by the Dev Project permission tier.',
        },
      },
      'required': ['message'],
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> args) async {
      try {
        final message = (args['message'] as String?)?.trim() ?? '';
        if (message.isEmpty) {
          return jsonEncode({
            'success': false,
            'reason': 'message is required',
          });
        }

        final sessionId = (args['session_id'] as String?)?.trim();
        if (sessionId != null && sessionId.isNotEmpty) {
          final runId = await bridgeService.continueSession(
            sessionId: sessionId,
            message: message,
          );
          return jsonEncode({
            'success': true,
            'action': 'continued_session',
            'session_id': sessionId,
            'run_id': runId,
            'message':
                '$characterName continued the Dev Session. Tell the user it is underway.',
          });
        }

        final projects = await bridgeService.listProjects();
        final project = _resolveProject(
          projects: projects,
          projectId: (args['project_id'] as String?)?.trim(),
          projectName: (args['project_name'] as String?)?.trim(),
        );
        if (project == null) {
          return jsonEncode({
            'success': false,
            'reason': 'project_not_resolved',
            'projects': [
              for (final project in projects)
                {
                  'id': project.id,
                  'name': project.name,
                  'permission_tier': project.permissionTier,
                },
            ],
            'message':
                'Ask the user which Dev Project to use, or provide project_id/project_name.',
          });
        }

        final agentType = _parseAgentType(args['agent_type']);
        final reuseLatest = args['reuse_latest'] == true;
        DevAgentSession? session;
        if (reuseLatest) {
          final sessions = await bridgeService.listSessions(
            projectId: project.id,
            ownerCharacterId: characterId,
            agentType: agentType.value,
            status: 'active',
            limit: 1,
          );
          if (sessions.isNotEmpty) {
            session = sessions.first;
          }
        }

        session ??= await _createSession(
          service: bridgeService,
          project: project,
          agentType: agentType,
          title: (args['title'] as String?)?.trim(),
          goal: (args['goal'] as String?)?.trim(),
          message: message,
          characterId: characterId,
          mode: (args['mode'] as String?)?.trim(),
        );

        final runId = await bridgeService.continueSession(
          sessionId: session.id,
          message: message,
        );
        return jsonEncode({
          'success': true,
          'action':
              reuseLatest ? 'reused_or_created_session' : 'created_session',
          'session_id': session.id,
          'run_id': runId,
          'project_id': project.id,
          'project_name': project.name,
          'agent_type': agentType.value,
          'project_permission_tier': project.permissionTier,
          'message':
              '$characterName started a Dev Session. Tell the user it is underway and they can inspect it in Dev Room.',
        });
      } catch (e, stack) {
        logger.warning('dev_session_start_or_continue failed', e, stack);
        return jsonEncode({
          'success': false,
          'reason': 'tool_error',
          'message': e.toString(),
        });
      }
    },
  );
}

DevProject? _resolveProject({
  required List<DevProject> projects,
  String? projectId,
  String? projectName,
}) {
  if (projectId != null && projectId.isNotEmpty) {
    for (final project in projects) {
      if (project.id == projectId) return project;
    }
    return null;
  }
  if (projectName != null && projectName.isNotEmpty) {
    final normalized = projectName.toLowerCase();
    final exact = projects.where(
      (project) => project.name.toLowerCase() == normalized,
    );
    if (exact.length == 1) return exact.first;
    final fuzzy = projects.where(
      (project) => project.name.toLowerCase().contains(normalized),
    );
    if (fuzzy.length == 1) return fuzzy.first;
    return null;
  }
  if (projects.length == 1) return projects.single;
  return null;
}

DevAgentType _parseAgentType(Object? raw) {
  final value = raw?.toString().trim();
  return DevAgentType.values.firstWhere(
    (type) => type.value == value,
    orElse: () => DevAgentType.codex,
  );
}

Future<DevAgentSession> _createSession({
  required DevAgentBridgeService service,
  required DevProject project,
  required DevAgentType agentType,
  required String message,
  required String characterId,
  String? title,
  String? goal,
  String? mode,
}) async {
  final sessionId = await service.createSession(
    projectId: project.id,
    agentType: agentType,
    title: _deriveTitle(title, goal, message),
    goal: (goal != null && goal.isNotEmpty) ? goal : null,
    ownerCharacterId: characterId,
    mode: mode == 'workspace_write'
        ? 'workspace_write'
        : project.permissionTier == 'read_only'
            ? 'read_only'
            : 'workspace_write',
  );
  final session = await service.getSession(sessionId);
  if (session == null) {
    throw const DevAgentBridgeException('Dev session was not created.');
  }
  return session;
}

String _deriveTitle(String? title, String? goal, String message) {
  final source = [
    title,
    goal,
    message,
  ].firstWhere((value) => value != null && value.trim().isNotEmpty)!;
  final normalized = source.trim().replaceAll(RegExp(r'\s+'), ' ');
  return normalized.length > 36
      ? '${normalized.substring(0, 36)}...'
      : normalized;
}
