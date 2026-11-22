import 'dart:async';
import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:memex/agent/built_in_tools/coros_mcp_tool.dart';
import 'package:memex/agent/built_in_tools/i_mcp_query_tool.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/time_context.dart';
import 'package:memex/utils/user_storage.dart';

import 'gpt_live_protocol.dart';

typedef GptLiveLlmResources = ({LLMClient client, ModelConfig modelConfig});
typedef GptLiveLlmResourcesLoader = Future<GptLiveLlmResources> Function();
typedef GptLiveDelegationRunner = Future<String> Function({
  required List<GptLiveTurn> recentTurns,
  String? requestText,
  required DateTime now,
  bool Function()? isCancelled,
});

/// Handles OpenAI GPT-Live client delegation (`delegation: {type: "client"}`)
/// locally on the phone using the App's configured companion chat LLM and
/// read-only personal data tools (`i_query` + `coros_query`).
class GptLiveClientDelegate {
  GptLiveClientDelegate({
    GptLiveLlmResourcesLoader? loadLlmResources,
    List<Tool> Function()? toolsBuilder,
    GptLiveDelegationRunner? runner,
    this.maxToolSteps = 4,
    this.timeout = const Duration(seconds: 25),
    this.maxTranscriptTurns = 12,
  }) : _loadLlmResources = loadLlmResources ?? _defaultLoadLlmResources,
       _toolsBuilder = toolsBuilder ?? _defaultTools,
       _runner = runner;

  static final _log = getLogger('GptLiveClientDelegate');

  /// Safe fallback when LLM config is missing, times out, or fails at runtime.
  static const fallbackReply = '后台查不到这个信息，直接自然地跟用户说暂时查不到，不要编造。';

  final GptLiveLlmResourcesLoader _loadLlmResources;
  final List<Tool> Function() _toolsBuilder;
  final GptLiveDelegationRunner? _runner;
  final int maxToolSteps;
  final Duration timeout;
  final int maxTranscriptTurns;

  static Future<GptLiveLlmResources> _defaultLoadLlmResources() {
    return UserStorage.getAgentLLMResources(
      AgentDefinitions.companionAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );
  }

  static List<Tool> _defaultTools() => [
        buildIMcpQueryTool(),
        buildCorosMcpTool(),
      ];

  /// Executes a single client-delegation lookup and returns concise plain
  /// Chinese text suitable for `session.commentary.append`.
  ///
  /// Never throws unhandled exceptions so a failing backend lookup cannot
  /// disrupt an active voice call. Returns empty string if cancelled.
  Future<String> handle({
    required List<GptLiveTurn> recentTurns,
    String? requestText,
    DateTime? now,
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() ?? false) return '';
    final effectiveNow = now ?? DateTime.now();

    try {
      final runner = _runner;
      final raw = runner != null
          ? await runner(
              recentTurns: recentTurns,
              requestText: requestText,
              now: effectiveNow,
              isCancelled: isCancelled,
            ).timeout(timeout)
          : await _runWithLlm(
              recentTurns: recentTurns,
              requestText: requestText,
              now: effectiveNow,
              isCancelled: isCancelled,
            ).timeout(timeout);

      if (isCancelled?.call() ?? false) return '';
      return sanitizeSpokenReply(raw) ?? fallbackReply;
    } on TimeoutException {
      _log.warning('client delegation timed out after ${timeout.inSeconds}s');
      return (isCancelled?.call() ?? false) ? '' : fallbackReply;
    } catch (e, st) {
      _log.warning('client delegation failed: $e\n$st');
      return (isCancelled?.call() ?? false) ? '' : fallbackReply;
    }
  }

  Future<String?> _runWithLlm({
    required List<GptLiveTurn> recentTurns,
    String? requestText,
    required DateTime now,
    bool Function()? isCancelled,
  }) async {
    final resources = await _loadLlmResources();
    if (isCancelled?.call() ?? false) return null;

    final tools = _toolsBuilder();
    final toolByName = <String, Tool>{
      for (final tool in tools) tool.name: tool,
    };

    final messages = <LLMMessage>[
      SystemMessage(buildSystemPrompt(now: now)),
      UserMessage.text(
        buildUserPrompt(
          recentTurns: recentTurns,
          requestText: requestText,
          maxTurns: maxTranscriptTurns,
        ),
      ),
    ];

    final effectiveMaxSteps = maxToolSteps < 0 ? 0 : maxToolSteps;
    for (var step = 0; step <= effectiveMaxSteps; step++) {
      if (isCancelled?.call() ?? false) return null;

      final allowTools = tools.isNotEmpty && step < effectiveMaxSteps;
      final response = await resources.client.generate(
        List<LLMMessage>.unmodifiable(messages),
        tools: tools.isEmpty ? null : tools,
        toolChoice: tools.isEmpty
            ? null
            : ToolChoice(
                mode: allowTools ? ToolChoiceMode.auto : ToolChoiceMode.none,
              ),
        modelConfig: resources.modelConfig,
      );
      if (isCancelled?.call() ?? false) return null;

      if (!allowTools || response.functionCalls.isEmpty) {
        return response.textOutput;
      }

      messages.add(response);
      final results = <FunctionExecutionResult>[];
      for (final call in response.functionCalls) {
        if (isCancelled?.call() ?? false) return null;
        results.add(await _executeToolCall(call, toolByName));
      }
      messages.add(FunctionExecutionResultMessage(results: results));
    }

    return null;
  }

  Future<FunctionExecutionResult> _executeToolCall(
    FunctionCall call,
    Map<String, Tool> toolByName,
  ) async {
    final tool = toolByName[call.name];
    if (tool == null || tool.executable == null) {
      return FunctionExecutionResult(
        id: call.id,
        name: call.name,
        isError: true,
        arguments: call.arguments,
        content: [TextPart('工具 ${call.name} 不可用')],
      );
    }

    Map<String, dynamic> decodedArgs;
    try {
      decodedArgs = _decodeArguments(call.arguments);
    } catch (e) {
      return FunctionExecutionResult(
        id: call.id,
        name: call.name,
        isError: true,
        arguments: call.arguments,
        content: [TextPart('工具参数解析失败：$e')],
      );
    }

    try {
      final rawResult = await _invokeTool(tool, decodedArgs);
      final text = _stringifyToolResult(rawResult);
      return FunctionExecutionResult(
        id: call.id,
        name: call.name,
        isError: false,
        arguments: call.arguments,
        content: [TextPart(text)],
      );
    } catch (e) {
      _log.warning('tool ${call.name} failed: $e');
      return FunctionExecutionResult(
        id: call.id,
        name: call.name,
        isError: true,
        arguments: call.arguments,
        content: [TextPart('工具调用失败：$e')],
      );
    }
  }

  static Map<String, dynamic> _decodeArguments(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    throw FormatException('Expected JSON object, got ${decoded.runtimeType}');
  }

  static Future<dynamic> _invokeTool(
    Tool tool,
    Map<String, dynamic> decodedArgs,
  ) async {
    final executable = tool.executable!;
    if (tool.parameterMode == ToolParameterMode.object) {
      return await executable(decodedArgs);
    }

    final properties = (tool.parameters['properties'] as Map? ?? const {})
        .cast<String, dynamic>();
    final positionalArgs = <dynamic>[];
    final namedArgs = <Symbol, dynamic>{};

    for (final key in properties.keys) {
      if (decodedArgs.containsKey(key)) {
        final casted = _castSchemaValue(decodedArgs[key], properties[key]);
        if (tool.namedParameters.contains(key)) {
          namedArgs[Symbol(key)] = casted;
        } else {
          positionalArgs.add(casted);
        }
      } else if (!tool.namedParameters.contains(key)) {
        positionalArgs.add(null);
      }
    }

    return await Function.apply(executable, positionalArgs, namedArgs);
  }

  static dynamic _castSchemaValue(dynamic value, dynamic schema) {
    if (value == null || schema is! Map) return value;
    final type = schema['type'];
    if (type == 'object' && value is Map) {
      return Map<String, dynamic>.from(value);
    }
    if (type == 'integer' && value is num) {
      return value.toInt();
    }
    if (type == 'number' && value is num) {
      return value.toDouble();
    }
    if (type == 'array' && value is List) {
      final items = schema['items'];
      if (items is Map) {
        final itemType = items['type'];
        if (itemType == 'string') {
          return value.map((e) => e.toString()).toList();
        }
        if (itemType == 'integer') {
          return value.map((e) => (e as num).toInt()).toList();
        }
        if (itemType == 'number') {
          return value.map((e) => (e as num).toDouble()).toList();
        }
        if (itemType == 'boolean') {
          return value.cast<bool>();
        }
      }
    }
    return value;
  }

  static String _stringifyToolResult(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is AgentToolResult) {
      final parts = <UserContentPart>[
        if (value.content != null) value.content!,
        if (value.contents != null) ...value.contents!,
      ];
      return parts
          .whereType<TextPart>()
          .map((p) => p.text)
          .join('\n')
          .trim();
    }
    return value.toString();
  }

  @visibleForTesting
  static String buildSystemPrompt({required DateTime now}) {
    String two(int n) => n.toString().padLeft(2, '0');
    final dateStr = '${now.year}-${two(now.month)}-${two(now.day)}';
    final timeStr = '${two(now.hour)}:${two(now.minute)}';
    final weekday = cnWeekday(now.weekday);
    return '''你是语音通话的手机端后台只读助手，查询结果会交给前台语音模型用自己的口吻转述给用户。

当前本地时间：$dateStr $timeStr 周$weekday。

可用只读工具：
- `i_query`：查询用户已授权的 i MCP 只读数据，包括日记（notes_recent/notes_search/notes_read）、日摘要（life_digest）、学习（study_today/study_source/study_progress）、历史心率或睡眠（heart_rate）、某日饮食（food_day）、某日记账（expense_day）。
- `coros_query`：查询用户的高驰（COROS）手表健康与运动数据（睡眠、心率、HRV、压力、恢复度、训练负荷、运动记录等）。注意高驰睡眠按起床日期归属：昨晚的睡眠查今天（$dateStr），X 日晚上的睡眠查 X+1 日；若对应日期无数据，不要拿相邻日期替代。

回复要求：
- 用自然简洁的纯中文，先给结论，控制在 2 到 5 句，适合直接口语转述。
- 不要使用 Markdown、项目符号、编号列表、代码块或链接。
- 引用日记、饮食、记账或睡眠数据时说明具体日期或相对时间。
- 如果工具未连接、查询失败或没有记录，如实说暂时查不到或没有相关记录，严禁编造任何数字、日期或事实。''';
  }

  @visibleForTesting
  static String buildUserPrompt({
    required List<GptLiveTurn> recentTurns,
    String? requestText,
    int maxTurns = 12,
  }) {
    final nonEmpty = recentTurns
        .where((t) => t.text.toString().trim().isNotEmpty)
        .toList();
    final slice = nonEmpty.length <= maxTurns
        ? nonEmpty
        : nonEmpty.sublist(nonEmpty.length - maxTurns);

    final buf = StringBuffer();
    if (requestText != null && requestText.trim().isNotEmpty) {
      buf
        ..writeln('前台委托说明：')
        ..writeln(requestText.trim())
        ..writeln();
    }
    if (slice.isNotEmpty) {
      buf.writeln('最近通话转写（按时间先后）：');
      for (final turn in slice) {
        final speaker = turn.fromUser ? '用户' : '前台语音';
        buf.writeln('$speaker：${turn.text.toString().trim()}');
      }
      buf.writeln();
    }
    buf.write('请根据用户最新的问题调用所需只读工具查询，并给出 2 到 5 句简洁纯中文结论供前台口语转述。');
    return buf.toString();
  }

  @visibleForTesting
  static String? sanitizeSpokenReply(String? raw) {
    if (raw == null) return null;
    var text = raw
        .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'</?visible_reply>', caseSensitive: false), '');
    text = text
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .trim();
    return text.isEmpty ? null : text;
  }
}
