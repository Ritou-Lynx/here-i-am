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
        'Summon OpenCode, Codex, or Claude Code through Dev Room to read '
        'project files, review code, modify code, inspect a local archive, '
        'or continue a multi-turn development/research task. Use this when '
        'the user asks you to make a coding agent do project work, read a '
        'folder of articles, review a repo, or continue a prior Dev Session. '
        'The tool starts work asynchronously; you must still reply in your '
        'own character voice and tell the user that the Dev Session has '
        'started. If the user says things like "continue", "next one", "read '
        'the next article", "接着", "下一篇", "继续刚才那个", or otherwise '
        'refers to prior Dev Room work, reuse the latest active Dev Session '
        'for this character unless the user clearly asks to start a new '
        'task. Do not use it for ordinary emotional chat, memory writes, '
        'reminders, shopping, or questions you can answer directly.',
    parameters: {
      'type': 'object',
      'properties': {
        'message': {
          'type': 'string',
          'description':
              'The concrete instruction for the coding agent. Include the '
                  'user goal, relevant file/folder names, and what output is '
                  'expected.',
        },
        'agent_type': {
          'type': 'string',
          'enum': ['opencode', 'codex', 'claude_code'],
          'description':
              'Which coding agent to use. Prefer opencode (the user\'s '
                  'current primary coding tool) for reading, review, '
                  'analysis, and implementation; use codex only when the '
                  'user explicitly asks for Codex; use claude_code only '
                  'when the user explicitly asks for Claude Code or a '
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
                  'creating a new one. Set this for "继续", "下一篇", "接着看", '
                  '"刚才那个", or similar follow-up requests.',
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
        final requestedProjectId = (args['project_id'] as String?)?.trim();
        final requestedProjectName = (args['project_name'] as String?)?.trim();
        final explicitAgentType = _tryParseAgentType(args['agent_type']);
        final requestedAgentType = explicitAgentType ?? DevAgentType.opencode;
        final reuseLatest = args['reuse_latest'] == true ||
            _looksLikeSessionContinuation(message);

        DevAgentSession? session;
        if (reuseLatest) {
          session = await _findLatestReusableSession(
            service: bridgeService,
            characterId: characterId,
            agentType: explicitAgentType?.value,
            projectId: requestedProjectId,
            projectName: requestedProjectName,
            projects: projects,
          );
          if (session != null) {
            final project = await bridgeService.getProject(session.projectId);
            if (project == null) {
              throw const DevAgentBridgeException(
                'Dev session project not found.',
              );
            }
            final runId = await bridgeService.continueSession(
              sessionId: session.id,
              message: message,
            );
            return jsonEncode({
              'success': true,
              'action': 'reused_session',
              'session_id': session.id,
              'run_id': runId,
              'project_id': session.projectId,
              'project_name': project.name,
              'agent_type': session.agentType,
              'project_permission_tier': project.permissionTier,
              'message':
                  '$characterName continued the existing Dev Session. Tell the user it is underway.',
            });
          }
        }

        final project = _resolveProject(
          projects: projects,
          projectId: requestedProjectId,
          projectName: requestedProjectName,
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

        session ??= await _createSession(
          service: bridgeService,
          project: project,
          agentType: requestedAgentType,
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
          'agent_type': requestedAgentType.value,
          'project_permission_tier': project.permissionTier,
'message':
                '$characterName started a Dev Session. Tell the user the run is underway and the result will show up here in chat when it finishes.',
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

DevAgentType? _tryParseAgentType(Object? raw) {
  final value = raw?.toString().trim();
  if (value == null || value.isEmpty) return null;
  for (final type in DevAgentType.values) {
    if (type.value == value) return type;
  }
  return null;
}

Future<DevAgentSession?> _findLatestReusableSession({
  required DevAgentBridgeService service,
  required String characterId,
  required List<DevProject> projects,
  String? agentType,
  String? projectId,
  String? projectName,
}) async {
  String? resolvedProjectId =
      projectId?.trim().isEmpty == true ? null : projectId?.trim();
  if ((resolvedProjectId == null || resolvedProjectId.isEmpty) &&
      projectName != null &&
      projectName.trim().isNotEmpty) {
    resolvedProjectId = _resolveProject(
      projects: projects,
      projectName: projectName.trim(),
    )?.id;
    if (resolvedProjectId == null) return null;
  }

  var sessions = await service.listSessions(
    projectId: resolvedProjectId,
    ownerCharacterId: characterId,
    agentType: agentType,
    status: 'active',
    limit: 1,
  );
  if (sessions.isNotEmpty) return sessions.first;

  if (agentType != null && agentType.isNotEmpty) {
    sessions = await service.listSessions(
      projectId: resolvedProjectId,
      ownerCharacterId: characterId,
      status: 'active',
      limit: 1,
    );
    if (sessions.isNotEmpty) return sessions.first;
  }
  return null;
}

bool _looksLikeSessionContinuation(String message) {
  final text = message.toLowerCase();
  const markers = [
    '继续',
    '接着',
    '刚才',
    '上一个',
    '上次',
    '下一篇',
    '下一条',
    '下一段',
    '下一个',
    '再读',
    '继续看',
    '接着看',
    'next',
    'continue',
    'keep going',
    'the next',
    'next one',
    'same session',
    'previous session',
  ];
  return markers.any(text.contains);
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
