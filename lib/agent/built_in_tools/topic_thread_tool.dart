/// Topic Thread tools for Companion Agent.
///
/// Two tools:
/// - topic_thread_create: create a new thread from current conversation
/// - topic_thread_recall: load an existing thread's context for continuity
library;

import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/memory_v3/services/topic_thread_service.dart';
import 'package:memex/db/app_database.dart';

final _log = Logger('TopicThreadTool');

/// Build the topic_thread_create tool.
///
/// Called when user expresses intent to track a topic long-term.
/// Trigger phrases: 想追踪/持续关注/长期记录/以后想继续聊/记下这个话题.
Tool buildTopicThreadCreateTool() {
  return Tool(
    name: 'topic_thread_create',
    description: '当用户表达想长期追踪某个话题时，创建一个话题线索（Topic Thread）。'
        '触发词：想追踪/持续关注/长期记录/以后继续聊/记下这个话题。'
        '不要自主决定创建，必须有用户明确表达追踪意图才调用。',
    parameters: {
      'type': 'object',
      'properties': {
        'title': {
          'type': 'string',
          'description': '话题名称，2-10字，从用户表述中提炼',
        },
        'current_stage': {
          'type': 'string',
          'description': '当前讨论到的阶段，一句话，可为空',
        },
        'open_questions': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '当前还没想清楚的问题，从本次对话中提炼，可为空数组',
        },
        'core_positions': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '用户已明确表达的立场或洞察，严格从用户原话提炼，不得 AI 自行总结',
        },
        'tags': {
          'type': 'string',
          'description': '逗号分隔标签，如"阅读,女性主义"，可为空',
        },
      },
      'required': ['title'],
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> args) async {
      if (!AppDatabase.isInitialized) return '数据库未就绪';
      try {
        final svc = TopicThreadService(db: AppDatabase.instance);
        final title = args['title'] as String? ?? '';
        if (title.isEmpty) return '话题名称不能为空';

        final openQ = (args['open_questions'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        final core = (args['core_positions'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [];

        final id = await svc.createThread(
          title: title,
          currentStage: args['current_stage'] as String? ?? '',
          openQuestions: openQ,
          corePositions: core,
          tags: args['tags'] as String? ?? '',
        );
        _log.info('TopicThread created via tool: $id "$title"');
        return jsonEncode({
          'success': true,
          'thread_id': id,
          'title': title,
          'message': '话题「$title」已创建，以后随时可以继续聊这个话题。',
        });
      } catch (e) {
        _log.warning('topic_thread_create failed: $e');
        return jsonEncode({'success': false, 'error': e.toString()});
      }
    },
  );
}

/// Build the topic_thread_recall tool.
///
/// Called when user wants to resume a topic or Companion detects topic keywords.
Tool buildTopicThreadRecallTool() {
  return Tool(
    name: 'topic_thread_recall',
    description: '检索已有的话题线索，用于接续之前的讨论。'
        '用户说"继续聊XX话题"或提到之前追踪过的话题时调用。'
        '返回该话题的当前阶段、已确认洞察和最近讨论摘要。',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': '话题关键词，用于检索已有 Thread',
        },
        'thread_id': {
          'type': 'string',
          'description': '如果知道具体 thread_id 可直接传入，优先于 query',
        },
      },
      'required': ['query'],
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> args) async {
      if (!AppDatabase.isInitialized) return '数据库未就绪';
      try {
        final svc = TopicThreadService(db: AppDatabase.instance);
        final threadId = args['thread_id'] as String?;
        final query = args['query'] as String? ?? '';

        TopicThreadContext? ctx;
        if (threadId != null && threadId.isNotEmpty) {
          ctx = await svc.buildContext(threadId, recentSessions: 5);
        } else {
          final threads = await svc.searchThreads(query);
          if (threads.isEmpty) {
            return jsonEncode({
              'found': false,
              'message': '没有找到关于「$query」的话题线索。'
                  '如果你想开始追踪这个话题，告诉我一声。',
            });
          }
          ctx = await svc.buildContext(threads.first.id, recentSessions: 5);
        }

        if (ctx == null) {
          return jsonEncode({'found': false, 'message': '话题线索不存在或已归档。'});
        }

        return jsonEncode({
          'found': true,
          'thread_id': ctx.threadId,
          'context_block': ctx.toPromptBlock(),
        });
      } catch (e) {
        _log.warning('topic_thread_recall failed: $e');
        return jsonEncode({'success': false, 'error': e.toString()});
      }
    },
  );
}
