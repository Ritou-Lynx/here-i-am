import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:memex/agent/agent_controller.util.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

final Logger _logger = getLogger('DevSessionFollowup');

Future<void> handleDevSessionFollowup(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
) async {
  final characterId = payload['character_id']?.toString() ?? '';
  final sessionId = payload['session_id']?.toString() ?? '';
  final runId = payload['run_id']?.toString() ?? '';
  final summary = payload['summary']?.toString() ?? '';
  final status = payload['status']?.toString() ?? 'done';
  final agentType = payload['agent_type']?.toString() ?? 'codex';
  final sessionTitle = payload['session_title']?.toString() ?? 'Dev Session';

  if (characterId.isEmpty || sessionId.isEmpty || runId.isEmpty) {
    throw StateError('dev_session_followup payload missing required ids');
  }

  final character =
      await CharacterService.instance.getCharacter(userId, characterId);
  if (character == null) {
    throw StateError('character not found: $characterId');
  }

  final resources = await UserStorage.getAgentLLMResources(
    AgentDefinitions.companionAgent,
    defaultClientKey: LLMConfig.defaultClientKey,
  );
  final agentName = _agentLabel(agentType);

  final systemPrompt = _buildSystemPrompt(
    characterName: character.name,
  );

  final userPrompt = '''
SYSTEM EVENT — do not treat this as a new user command.

You previously summoned $agentName through Dev Room. That Dev Session has now finished.

Session title: $sessionTitle
Run status: $status

Raw result summary:
$summary

Write ONE visible chat message to the user in your own character voice.

Rules:
- Explain what came back from $agentName, naturally and concretely.
- If status is done, summarize the useful result and suggest one natural next step or question.
- If status is failed/aborted, be honest and tell the user they can open the Dev Session card to inspect details.
- Mention that the card below can open the Dev Session if useful.
- Do NOT claim you personally edited files; say $agentName/Codex/Claude Code did the run.
- Do NOT call tools. Do NOT create records. Do NOT schedule reminders.
- Keep it compact: 1-3 short paragraphs, Chinese.
''';

  final controller = AgentController();
  addAgentLogger(controller);

  final state = AgentState.empty()
    ..sessionId =
        'dev_session_followup_${userId}_${context.taskId}_${DateTime.now().microsecondsSinceEpoch}';

  final agent = StatefulAgent(
    name: 'dev_session_followup',
    client: resources.client,
    modelConfig: resources.modelConfig,
    state: state,
    tools: const [],
    skills: const [],
    systemPrompts: [systemPrompt],
    disableSubAgents: true,
    controller: controller,
    withGeneralPrinciples: false,
  );

  final messages =
      await agent.run([UserMessage.text(userPrompt)], useStream: false);
  final reply = _lastModelText(messages).trim();
  if (reply.isEmpty) {
    throw StateError('dev_session_followup produced empty reply');
  }

  await _postToChat(
    characterId: characterId,
    content: reply,
    payload: payload,
  );
  await _insertCharacterSessionMessage(
    sessionId: sessionId,
    runId: runId,
    content: reply,
  );
  await LocalTaskExecutor.instance.updateTaskResult(
    context.taskId,
    jsonEncode({
      'character_id': characterId,
      'session_id': sessionId,
      'run_id': runId,
      'status': status,
      'reply': reply,
    }),
  );
}

Future<void> handleDevSessionFollowupFailure(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
  Object error,
  StackTrace? stackTrace,
) async {
  _logger.warning('Dev session follow-up failed', error, stackTrace);
  final characterId = payload['character_id']?.toString() ?? '';
  if (characterId.isEmpty) return;

  final status = payload['status']?.toString() ?? 'failed';
  final agentType = payload['agent_type']?.toString() ?? 'codex';
  final summary = payload['summary']?.toString() ?? '';
  final content = _fallbackMessage(
    agentType: agentType,
    status: status,
    summary: summary,
  );
  await _postToChat(
    characterId: characterId,
    content: content,
    payload: payload,
  );
}

String _buildSystemPrompt({
  required String characterName,
}) {
  final buffer = StringBuffer();
  buffer
    ..writeln('# You Are $characterName')
    ..writeln()
    ..writeln('## Task')
    ..writeln(
      'You are writing a normal chat message after a Dev Room task completed. '
      'Stay in character. Be warm, concrete, and concise. No markdown tables. '
      'No tool calls are available.',
    );
  return buffer.toString();
}

Future<void> _postToChat({
  required String characterId,
  required String content,
  required Map<String, dynamic> payload,
}) {
  return PersonaChatService.instance.addCharacterMessage(
    characterId,
    content,
    isRead: false,
    timestamp: DateTime.now(),
    addenda: [
      {
        'type': 'dev_session',
        'sessionId': payload['session_id'],
        'runId': payload['run_id'],
        'title': payload['session_title'] ?? 'Dev Session',
        'agentType': payload['agent_type'] ?? 'codex',
        'status': payload['status'] ?? 'done',
        if (payload['branch'] != null) 'branch': payload['branch'],
        if (payload['worktree_path'] != null)
          'worktreePath': payload['worktree_path'],
      },
    ],
  );
}

Future<void> _insertCharacterSessionMessage({
  required String sessionId,
  required String runId,
  required String content,
}) async {
  final db = AppDatabase.instance;
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  await db.into(db.devAgentSessionMessages).insert(
        DevAgentSessionMessagesCompanion.insert(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          sessionId: sessionId,
          role: 'character',
          content: content,
          linkedRunId: Value(runId),
          createdAt: now,
        ),
      );
  await (db.update(db.devAgentSessions)..where((t) => t.id.equals(sessionId)))
      .write(DevAgentSessionsCompanion(updatedAt: Value(now)));
}

String _lastModelText(List<LLMMessage> messages) {
  for (final message in messages.reversed) {
    if (message is ModelMessage) {
      final text = message.textOutput ?? '';
      if (text.trim().isNotEmpty) return text;
    }
  }
  return '';
}

String _fallbackMessage({
  required String agentType,
  required String status,
  required String summary,
}) {
  final agentName = _agentLabel(agentType);
  final body = summary.trim().isEmpty ? '这轮没有返回摘要。' : summary.trim();
  if (status == 'done') {
    return '我让 $agentName 跑完了，结果回来了：\n\n$body\n\n详情我放在下面这张 Dev Session 卡片里了，你可以点进去继续追问。';
  }
  return '$agentName 这轮没有顺利完成：\n\n$body\n\n我把详情放在 Dev Room 里了，我们可以点进去看哪里卡住。';
}

String _agentLabel(String agentType) {
  return agentType == 'claude_code' ? 'Claude Code' : 'Codex';
}
