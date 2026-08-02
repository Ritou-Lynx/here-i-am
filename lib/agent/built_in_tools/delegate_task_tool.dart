import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/agent_activity_service.dart';
import 'package:memex/data/services/local_task_executor.dart';

const _delegationTaskType = 'companion_delegation';

const _categoryLabels = {
  'card_ops': '整理记录',
  'insight': '生成洞察',
  'query': '查询信息',
};

/// Agent tool that lets the companion delegate card/PKM/insight operations
/// to a background agent. The companion stays responsive while the work
/// happens asynchronously.
Tool buildDelegateTaskTool({
  required String userId,
  required String characterId,
  required String characterName,
}) {
  return Tool(
    name: 'delegate_task',
    description:
        '''Delegate a PKM archive/insight/query operation to a background agent.

Choose `task_category` based on what the user wants:

- **card_ops**: Modify or archive EXISTING legacy PKM notes/files that were
  NOT created via LifeMemoryCapture or AiFinanceRecord. This is a narrow,
  rarely-needed legacy path — results do NOT appear in the Memory Review tab.
  Use ONLY for "改一下那篇笔记", "把这份 PKM 文档归档" — i.e. explicit references
  to old note/document files, never for new facts/events/expenses.
- **insight**: Generate a one-shot analysis, summary, or chart. Results appear
  ONLY in chat — nothing is saved to the Review tab. Use for "总结这周",
  "分析我的睡眠模式", "这段时间我花了多少钱".
- **query**: Search, read, or summarize existing information without modifying
  anything. Results appear only in chat. Use for "查一下XX", "最近有没有YY",
  "帮我找ZZ".

Examples:
- "总结这周干了什么" → insight
- "最近三个月有哪些关于面试的记录" → query

⛔ Do NOT use `card_ops` for recording/saving new facts, events, expenses, or
income — even if the user says "记一下"、"帮我记账"、"归档"、"创建记录". Those go
through `LifeMemoryCapture` or `AiFinanceRecord` directly, which write to the
store the user actually sees in Memory Review / the ledger. `card_ops` writes
to a different legacy store that Memory Review cannot show.
Do NOT use for memory writes, reminders, or shopping — those have dedicated tools.
Always reply in text first, then call this tool.''',
    parameters: {
      'type': 'object',
      'properties': {
        'task_category': {
          'type': 'string',
          'enum': ['card_ops', 'insight', 'query'],
          'description':
              'The category of work. card_ops=modify/create card files (results in Review). '
                  'insight=generate analysis/chart (chat only). query=read/search (chat only).',
        },
        'description': {
          'type': 'string',
          'description':
              'What to do, in natural Chinese. Be specific about facts, tags, '
                  'time ranges, or fact_ids.',
        },
        'context': {
          'type': 'string',
          'description':
              'Optional extra context: fact_ids, tag names, time ranges, etc.',
        },
      },
      'required': ['task_category', 'description'],
    },
    executable: (
      String taskCategory,
      String description,
      String? context,
    ) async {
      final payload = {
        'character_id': characterId,
        'user_id': userId,
        'task_category': taskCategory,
        'description': description,
        if (context != null) 'context': context,
      };

      final bizId = 'companion_del:${DateTime.now().millisecondsSinceEpoch}';
      await LocalTaskExecutor.instance.enqueueTask(
        userId: userId,
        taskType: _delegationTaskType,
        payload: payload,
        priority: 0,
        maxRetries: 2,
        bizId: bizId,
      );

      final label = _categoryLabels[taskCategory] ?? '处理任务';
      if (AgentActivityService.isInitialized) {
        await AgentActivityService.instance.pushMessage(
          type: AgentActivityType.agent_start,
          title: '$characterName 正在$label…',
          content: description,
          agentName: 'companion_delegation',
          agentId: characterId,
          userId: userId,
        );
      }

      final summary = description.length > 60
          ? '${description.substring(0, 60)}…'
          : description;
      return 'Task queued (category=$taskCategory): "$summary". '
          'Tell the user the task is underway.';
    },
  );
}
