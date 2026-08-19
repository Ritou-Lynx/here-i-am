/// Topic Thread tools for Companion Agent.
///
/// Three tools:
/// - topic_thread_create: create a new thread from current conversation
/// - topic_thread_recall: load an existing thread's context for continuity
/// - topic_thread_append_session: summarize this discussion into that thread
library;

import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/memory_v3/services/topic_thread_backfill_service.dart';
import 'package:memex/data/memory_v3/services/topic_thread_chat_context_service.dart';
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
        final title = (args['title'] as String? ?? '').trim();
        if (title.isEmpty) return '话题名称不能为空';

        final existing = await svc.findActiveThreadByTitle(title);
        if (existing != null) {
          return jsonEncode({
            'success': false,
            'reason': 'existing_thread',
            'thread_id': existing.id,
            'title': existing.title,
            'message': '已存在同名话题「${existing.title}」。不要新建；需要继续讨论时召回它，需要整理时追加到它。',
          });
        }

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
Tool buildTopicThreadRecallTool({
  required String characterId,
  int? currentUserMessageId,
}) {
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
          final thread = await svc.getThread(threadId);
          if (thread?.status == 'active') {
            ctx = await svc.buildContext(threadId, recentSessions: 5);
          }
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

        if (currentUserMessageId != null && currentUserMessageId > 0) {
          await TopicThreadChatContextService(db: AppDatabase.instance).save(
            TopicThreadChatContext(
              characterId: characterId,
              threadId: ctx.threadId,
              threadTitle: ctx.title,
              afterMessageId: currentUserMessageId,
              updatedAt: DateTime.now(),
            ),
          );
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

/// Build the tool that writes the active discussion back into an existing
/// Topic Thread. It never creates a thread as a fallback.
Tool buildTopicThreadAppendSessionTool({
  required String characterId,
  required String characterName,
  int? currentUserMessageId,
  LLMClient? client,
  ModelConfig? modelConfig,
}) {
  return Tool(
    name: 'topic_thread_append_session',
    description: '把当前这段讨论整理成摘要，追加到已经存在的话题线索。'
        '用户说“整理到这个话题里”“并入原话题”“补进秋招话题”等话时必须调用。'
        '此工具只追加已有话题，绝不会新建话题。',
    parameters: {
      'type': 'object',
      'properties': {
        'thread_id': {
          'type': 'string',
          'description': '已知的原话题 ID；通常留空，使用刚召回的当前话题',
        },
        'query': {
          'type': 'string',
          'description': '用户明确说出的话题名称；“这个话题”时留空',
        },
        'close_after_save': {
          'type': 'boolean',
          'description': '用户说结束/先聊到这里时为 true；还要继续聊时为 false',
        },
      },
      'required': [],
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> args) async {
      if (!AppDatabase.isInitialized) {
        return jsonEncode({'success': false, 'reason': 'database_not_ready'});
      }
      if (currentUserMessageId == null || currentUserMessageId <= 0) {
        return jsonEncode({
          'success': false,
          'reason': 'missing_message_boundary',
          'message': '当前聊天缺少消息边界，未写入任何话题。',
        });
      }

      try {
        final db = AppDatabase.instance;
        final threadService = TopicThreadService(db: db);
        final contextService = TopicThreadChatContextService(db: db);
        final active = await contextService.load(characterId);
        final requestedId = (args['thread_id'] as String?)?.trim() ?? '';
        final query = (args['query'] as String?)?.trim() ?? '';

        String? targetId;
        final deicticQuery = RegExp(r'^(这个|刚才|当前|原来|原先|之前)(的)?话题(线索)?$')
            .hasMatch(query.replaceAll(RegExp(r'\s+'), ''));
        if (requestedId.isNotEmpty) {
          targetId = requestedId;
        } else if (query.isEmpty || deicticQuery) {
          targetId = active?.threadId;
        } else if (query.isNotEmpty) {
          final exact = await threadService.findActiveThreadByTitle(query);
          if (exact != null) {
            targetId = exact.id;
          } else {
            final matches = await threadService.searchThreads(query);
            if (matches.length == 1) {
              targetId = matches.single.id;
            } else if (matches.length > 1) {
              return jsonEncode({
                'success': false,
                'reason': 'ambiguous_thread',
                'candidates': matches
                    .take(5)
                    .map((t) => {'thread_id': t.id, 'title': t.title})
                    .toList(),
                'message': '找到多个可能的话题，请让用户指定一个。不要新建话题。',
              });
            }
          }
        }

        if (targetId == null || targetId.isEmpty) {
          return jsonEncode({
            'success': false,
            'reason': 'no_active_thread',
            'message': '当前没有已召回的话题，请让用户指定原话题。不要新建话题。',
          });
        }

        final target = await threadService.getThread(targetId);
        if (target == null || target.status != 'active') {
          return jsonEncode({
            'success': false,
            'reason': 'thread_unavailable',
            'message': '目标话题不存在或已归档，未写入任何内容。',
          });
        }
        if (active == null || active.threadId != targetId) {
          return jsonEncode({
            'success': false,
            'reason': 'no_active_discussion',
            'thread_id': targetId,
            'title': target.title,
            'message': '找到了原话题，但没有本轮讨论的起始锚点。请先召回该话题，或使用聊天多选“加入话题”。不要新建话题。',
          });
        }

        final result =
            await TopicThreadBackfillService(db: db).summarizeRangeAndAppend(
          threadId: targetId,
          characterId: characterId,
          characterName: characterName,
          afterMessageId: active.afterMessageId,
          beforeMessageId: currentUserMessageId,
          client: client,
          modelConfig: modelConfig,
        );

        final closeAfterSave = args['close_after_save'] as bool? ?? true;
        if (closeAfterSave) {
          await contextService.clear(characterId);
        } else {
          await contextService.save(TopicThreadChatContext(
            characterId: characterId,
            threadId: target.id,
            threadTitle: target.title,
            afterMessageId: currentUserMessageId,
            updatedAt: DateTime.now(),
          ));
        }

        _log.info(
            'TopicThread session appended via tool: ${result.sessionId} -> $targetId');
        return jsonEncode({
          'success': true,
          'thread_id': targetId,
          'title': target.title,
          'session_id': result.sessionId,
          'message_count': result.messageCount,
          'summary': result.summary,
          'closed': closeAfterSave,
          'message': '已把本轮讨论整理到原话题「${target.title}」。',
        });
      } catch (e) {
        _log.warning('topic_thread_append_session failed: $e');
        return jsonEncode({
          'success': false,
          'reason': 'append_failed',
          'error': e.toString(),
        });
      }
    },
  );
}
