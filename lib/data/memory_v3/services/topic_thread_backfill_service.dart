/// Topic Thread backfill service — user-triggered session summarization.
///
/// The user multi-selects chat messages in the persona chat screen, picks a
/// Topic Thread, and this service summarizes the transcript (≤200 chars) and
/// appends a session with user_confirmed authority. This is the manual entry
/// for attaching past conversations to a long-running topic.
library;

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/user_storage.dart';

import 'topic_thread_backfill_prompt.dart';
import 'topic_thread_service.dart';

class TopicThreadBackfillResult {
  const TopicThreadBackfillResult({
    required this.sessionId,
    required this.summary,
    required this.messageCount,
  });

  final String sessionId;
  final String summary;
  final int messageCount;
}

class TopicThreadBackfillService {
  TopicThreadBackfillService({required AppDatabase db})
      : _threads = TopicThreadService(db: db);

  final TopicThreadService _threads;

  static const _maxInputChars = 4000;
  static const _maxSummaryChars = 200;

  /// Summarize [messages] and append a session to [threadId].
  ///
  /// Only `chat`-type messages with non-empty content are included (the same
  /// filter Dreaming extraction uses). [occurredAt] is the last selected
  /// message's timestamp, so the session lands under the real discussion
  /// date and the thread's lastDiscussedAt follows.
  ///
  /// [client]/[modelConfig] are optional test injection points; when absent
  /// the service resolves resources via the recordOrganizerAgent config
  /// (the same model the chat batch-record path uses).
  Future<TopicThreadBackfillResult> summarizeAndAppend({
    required String threadId,
    required List<PersonaChatMessage> messages,
    required String characterName,
    LLMClient? client,
    ModelConfig? modelConfig,
  }) async {
    // Filter to extractable chat rows, ascending by id.
    final chat = messages
        .where((m) => m.messageType == 'chat' && m.content.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    if (chat.isEmpty) {
      throw ArgumentError('没有可加入话题的聊天消息');
    }

    final transcript = _truncateHeadTail(_buildTranscript(chat, characterName));
    final resources = (client != null && modelConfig != null)
        ? (client: client, modelConfig: modelConfig)
        : await UserStorage.getAgentLLMResources(
            AgentDefinitions.recordOrganizerAgent,
            defaultClientKey: LLMConfig.defaultClientKey,
          );

    final response = await resources.client.generate(
      [
        SystemMessage(topicThreadBackfillSystemPrompt),
        UserMessage([TextPart(transcript)]),
      ],
      modelConfig: ModelConfig(
        model: resources.modelConfig.model,
        maxTokens: 512,
        extra: {
          ...?resources.modelConfig.extra,
          'thinking': {'type': 'disabled'},
        },
      ),
    );

    final summary = _normalizeSummary(response.textOutput);
    if (summary.isEmpty) {
      throw StateError('话题摘要生成为空');
    }

    final sessionId = await _threads.appendSession(
      threadId: threadId,
      summary: summary,
      sourceType: 'chat',
      sourceRef: {'messageIds': chat.map((m) => m.id).toList()},
      authority: 'user_confirmed',
      occurredAt: chat.last.timestamp,
    );

    return TopicThreadBackfillResult(
      sessionId: sessionId,
      summary: summary,
      messageCount: chat.length,
    );
  }

  String _buildTranscript(List<PersonaChatMessage> chat, String characterName) {
    final sb = StringBuffer();
    for (final m in chat) {
      sb.writeln('${m.isFromCharacter ? characterName : '用户'}: ${m.content}');
    }
    return sb.toString();
  }

  /// Keep head + tail when the transcript exceeds the cap.
  String _truncateHeadTail(String text) {
    if (text.length <= _maxInputChars) return text;
    const half = _maxInputChars ~/ 2;
    return '${text.substring(0, half)}\n'
        '[…中间省略 ${text.length - _maxInputChars} 字…]\n'
        '${text.substring(text.length - half)}';
  }

  String _normalizeSummary(String? raw) {
    if (raw == null) return '';
    var s = raw.trim();
    if (s.startsWith('"') && s.endsWith('"') ||
        s.startsWith('「') && s.endsWith('」')) {
      s = s.substring(1, s.length - 1);
    }
    if (s.length > _maxSummaryChars) s = s.substring(0, _maxSummaryChars);
    return s;
  }
}
