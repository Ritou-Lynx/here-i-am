import 'dart:async';
import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/built_in_tools/i_mcp_query_tool.dart';
import 'package:memex/agent/mcp/mcp_protocol.dart';
import 'package:memex/data/services/gpt_live/gpt_live_call.dart';
import 'package:memex/data/services/gpt_live/gpt_live_client_delegate.dart';
import 'package:memex/data/services/gpt_live/gpt_live_protocol.dart';
import 'package:memex/data/services/i_mcp_service.dart';

void main() {
  GptLiveTurn turn(bool fromUser, String text) =>
      GptLiveTurn(fromUser: fromUser, at: DateTime(2026, 11, 22, 9, 0))
        ..text.write(text);

  group('GptLiveClientDelegate', () {
    test('调用 i_query 只读工具并返回口语结论', () async {
      final fakeIMcp = _FakeIMcpQueryService(
        connected: true,
        responses: {
          'food_day': '早餐燕麦拿铁，午餐番茄牛腩饭，晚餐蔬菜沙拉。',
        },
      );
      final fakeLlm = _ScriptedLLMClient([
        ModelMessage(
          model: 'fake-chat',
          functionCalls: [
            FunctionCall(
              id: 'call_1',
              name: 'i_query',
              arguments: jsonEncode({
                'tool': 'food_day',
                'arguments': {'date': '2026-11-21'},
              }),
            ),
          ],
        ),
        ModelMessage(
          model: 'fake-chat',
          textOutput: '<think>整理结果</think>昨天记录了三餐，早餐喝了燕麦拿铁，午餐吃了番茄牛腩饭，晚餐是蔬菜沙拉。',
        ),
      ]);

      final delegate = GptLiveClientDelegate(
        loadLlmResources: () async => (
          client: fakeLlm,
          modelConfig: ModelConfig(model: 'fake-chat'),
        ),
        toolsBuilder: () => [buildIMcpQueryTool(service: fakeIMcp)],
      );

      final result = await delegate.handle(
        recentTurns: [
          turn(true, '帮我查一下昨天吃了什么'),
          turn(false, '好呀，我帮你看看'),
        ],
        now: DateTime(2026, 11, 22, 9, 30),
      );

      expect(fakeIMcp.calls, ['food_day']);
      expect(fakeIMcp.lastArguments, {'date': '2026-11-21'});
      expect(result, '昨天记录了三餐，早餐喝了燕麦拿铁，午餐吃了番茄牛腩饭，晚餐是蔬菜沙拉。');
      expect(fakeLlm.recordedMessages.length, 2);
      final secondRound = fakeLlm.recordedMessages[1];
      expect(secondRound.last, isA<FunctionExecutionResultMessage>());
      final toolResult =
          (secondRound.last as FunctionExecutionResultMessage).results.single;
      expect(toolResult.isError, isFalse);
      expect((toolResult.content.single as TextPart).text, contains('番茄牛腩饭'));
    });

    test('支持 function 参数模式的 coros_query 工具', () async {
      String? seenTool;
      Map<String, dynamic>? seenArgs;
      final fakeCoros = Tool(
        name: 'coros_query',
        description: 'fake coros',
        parameters: {
          'type': 'object',
          'properties': {
            'tool': {'type': 'string'},
            'arguments': {'type': 'object'},
          },
          'required': ['tool'],
        },
        executable: (String tool, Map<String, dynamic>? arguments) async {
          seenTool = tool;
          seenArgs = arguments;
          return '2026-11-22 睡眠得分 84，总时长 7 小时 20 分，深睡 1 小时 40 分。';
        },
      );

      final fakeLlm = _ScriptedLLMClient([
        ModelMessage(
          model: 'fake-chat',
          functionCalls: [
            FunctionCall(
              id: 'coros_1',
              name: 'coros_query',
              arguments: jsonEncode({
                'tool': 'querySleepData',
                'arguments': {'days': 1, 'timezone': 'Asia/Shanghai'},
              }),
            ),
          ],
        ),
        ModelMessage(
          model: 'fake-chat',
          textOutput: '昨晚你睡了七小时二十分钟，睡眠得分八十四分，深睡有一小时四十分钟，整体不错。',
        ),
      ]);

      final delegate = GptLiveClientDelegate(
        loadLlmResources: () async => (
          client: fakeLlm,
          modelConfig: ModelConfig(model: 'fake-chat'),
        ),
        toolsBuilder: () => [fakeCoros],
      );

      final result = await delegate.handle(
        recentTurns: [turn(true, '我昨晚睡得怎么样')],
        now: DateTime(2026, 11, 22, 8, 15),
      );

      expect(seenTool, 'querySleepData');
      expect(seenArgs, {'days': 1, 'timezone': 'Asia/Shanghai'});
      expect(result, contains('七小时二十分钟'));
    });

    test('工具报错时不崩溃，把错误反馈给模型由其如实回复', () async {
      final brokenTool = Tool(
        name: 'coros_query',
        description: 'broken coros',
        parameters: {
          'type': 'object',
          'properties': {
            'tool': {'type': 'string'},
            'arguments': {'type': 'object'},
          },
        },
        executable: (String tool, Map<String, dynamic>? arguments) async {
          throw StateError('COROS MCP not connected');
        },
      );

      final fakeLlm = _ScriptedLLMClient([
        ModelMessage(
          model: 'fake-chat',
          functionCalls: [
            FunctionCall(
              id: 'coros_err',
              name: 'coros_query',
              arguments: jsonEncode({'tool': 'querySleepData'}),
            ),
          ],
        ),
        ModelMessage(
          model: 'fake-chat',
          textOutput: '高驰手表这边现在还没连上，暂时查不到你的睡眠记录。',
        ),
      ]);

      final delegate = GptLiveClientDelegate(
        loadLlmResources: () async => (
          client: fakeLlm,
          modelConfig: ModelConfig(model: 'fake-chat'),
        ),
        toolsBuilder: () => [brokenTool],
      );

      final result = await delegate.handle(
        recentTurns: [turn(true, '查一下昨晚高驰睡眠')],
      );

      expect(result, '高驰手表这边现在还没连上，暂时查不到你的睡眠记录。');
      final toolMsg =
          fakeLlm.recordedMessages[1].last as FunctionExecutionResultMessage;
      expect(toolMsg.results.single.isError, isTrue);
      expect(
        (toolMsg.results.single.content.single as TextPart).text,
        contains('COROS MCP not connected'),
      );
    });

    test('超过 maxToolSteps 后强制禁止继续调工具并产出结论', () async {
      var toolCalls = 0;
      final countingTool = Tool(
        name: 'i_query',
        description: 'counter',
        parameters: {'type': 'object', 'properties': {}},
        parameterMode: ToolParameterMode.object,
        executable: (Map<String, dynamic> _) async {
          toolCalls++;
          return 'chunk $toolCalls';
        },
      );

      final fakeLlm = _ScriptedLLMClient([
        ModelMessage(
          model: 'fake-chat',
          functionCalls: [
            FunctionCall(id: 'c1', name: 'i_query', arguments: '{}'),
          ],
        ),
        ModelMessage(
          model: 'fake-chat',
          functionCalls: [
            FunctionCall(id: 'c2', name: 'i_query', arguments: '{}'),
          ],
        ),
        ModelMessage(
          model: 'fake-chat',
          textOutput: '最多查两轮后直接给出汇总结论。',
        ),
      ]);

      final delegate = GptLiveClientDelegate(
        maxToolSteps: 2,
        loadLlmResources: () async => (
          client: fakeLlm,
          modelConfig: ModelConfig(model: 'fake-chat'),
        ),
        toolsBuilder: () => [countingTool],
      );

      final result = await delegate.handle(
        recentTurns: [turn(true, '查一下最近日记')],
      );

      expect(toolCalls, 2);
      expect(result, '最多查两轮后直接给出汇总结论。');
      expect(fakeLlm.recordedToolChoices.last?.mode, ToolChoiceMode.none);
    });

    test('缺少 LLM 配置或超时时安全回退，不抛异常', () async {
      final missingConfigDelegate = GptLiveClientDelegate(
        loadLlmResources: () async => throw StateError('No LLM config'),
      );
      expect(
        await missingConfigDelegate.handle(recentTurns: [turn(true, '查日记')]),
        GptLiveClientDelegate.fallbackReply,
      );

      final timeoutDelegate = GptLiveClientDelegate(
        timeout: const Duration(milliseconds: 20),
        runner: ({
          required recentTurns,
          requestText,
          required now,
          isCancelled,
        }) =>
            Completer<String>().future,
      );
      expect(
        await timeoutDelegate.handle(recentTurns: [turn(true, '查日记')]),
        GptLiveClientDelegate.fallbackReply,
      );
    });

    test('已取消时直接返回空串且不调用 LLM', () async {
      var loaderCalled = false;
      final delegate = GptLiveClientDelegate(
        loadLlmResources: () async {
          loaderCalled = true;
          throw StateError('should not run');
        },
      );

      final result = await delegate.handle(
        recentTurns: [turn(true, '查日记')],
        isCancelled: () => true,
      );

      expect(result, isEmpty);
      expect(loaderCalled, isFalse);
    });
  });

  group('GptLiveCall client delegation flow', () {
    test('收到 session.delegation.created 发送 thinking 再回传 commentary', () async {
      final sent = <Map<String, dynamic>>[];
      final completer = Completer<String>();
      List<GptLiveTurn>? capturedTurns;
      String? capturedRequest;

      final call = GptLiveCall(
        characterId: 'char_1',
        clientDelegate: GptLiveClientDelegate(
          runner: ({
            required recentTurns,
            requestText,
            required now,
            isCancelled,
          }) {
            capturedTurns = recentTurns;
            capturedRequest = requestText;
            return completer.future;
          },
        ),
        sendEventOverride: (payload) async {
          sent.add(jsonDecode(payload) as Map<String, dynamic>);
        },
      );
      addTearDown(call.dispose);

      call.configureClientDelegationForTesting(
        enabled: true,
        phaseOverride: GptLiveCallPhase.live,
      );

      call.handleEventForTesting(
        jsonEncode({
          'type': 'session.input_transcript.delta',
          'delta': '昨天记了什么账？',
        }),
      );
      call.handleEventForTesting(
        jsonEncode({
          'type': 'session.delegation.created',
          'delegation': {
            'id': 'del_001',
            'type': 'delegation',
            'target': 'client',
            'instructions': '查询昨天记账',
          },
        }),
      );
      // Duplicate event for the same delegation_id must be ignored.
      call.handleEventForTesting(
        jsonEncode({
          'type': 'session.delegation.created',
          'delegation_id': 'del_001',
        }),
      );

      await Future<void>.delayed(Duration.zero);
      expect(sent.length, 1);
      expect(sent.first, {
        'type': 'session.thinking.append',
        'delegation_id': 'del_001',
        'content': '正在查询相关记录…',
      });
      expect(capturedTurns?.single.text.toString(), '昨天记了什么账？');
      expect(capturedRequest, '查询昨天记账');

      completer.complete('昨天一共记了一笔咖啡 28 元和一笔晚餐 65 元。');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(sent.length, 2);
      expect(sent[1], {
        'type': 'session.commentary.append',
        'delegation_id': 'del_001',
        'content': '昨天一共记了一笔咖啡 28 元和一笔晚餐 65 元。',
      });
    });

    test('收到 session.delegation.cancelled 后丢弃迟到结果', () async {
      final sent = <Map<String, dynamic>>[];
      final completer = Completer<String>();

      final call = GptLiveCall(
        characterId: 'char_1',
        clientDelegate: GptLiveClientDelegate(
          runner: ({
            required recentTurns,
            requestText,
            required now,
            isCancelled,
          }) =>
              completer.future,
        ),
        sendEventOverride: (payload) async {
          sent.add(jsonDecode(payload) as Map<String, dynamic>);
        },
      );
      addTearDown(call.dispose);

      call.configureClientDelegationForTesting(
        enabled: true,
        phaseOverride: GptLiveCallPhase.live,
      );

      call.handleEventForTesting(
        jsonEncode({
          'type': 'session.delegation.created',
          'delegation': {'id': 'del_cancel_1', 'target': 'client'},
        }),
      );
      call.handleEventForTesting(
        jsonEncode({
          'type': 'session.delegation.cancelled',
          'delegation_id': 'del_cancel_1',
        }),
      );

      completer.complete('这是一条迟到的查询结果');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(sent.length, 1);
      expect(sent.single['type'], 'session.thinking.append');
    });

    test('非 client 模式忽略 session.delegation.created', () async {
      final sent = <String>[];
      var runnerCalled = false;

      final call = GptLiveCall(
        characterId: 'char_1',
        clientDelegate: GptLiveClientDelegate(
          runner: ({
            required recentTurns,
            requestText,
            required now,
            isCancelled,
          }) async {
            runnerCalled = true;
            return 'should not send';
          },
        ),
        sendEventOverride: (payload) async => sent.add(payload),
      );
      addTearDown(call.dispose);

      call.configureClientDelegationForTesting(
        enabled: false,
        phaseOverride: GptLiveCallPhase.live,
      );

      call.handleEventForTesting(
        jsonEncode({
          'type': 'session.delegation.created',
          'delegation': {'id': 'del_responses_1', 'target': 'responses'},
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(runnerCalled, isFalse);
      expect(sent, isEmpty);
    });
  });
}

class _ScriptedLLMClient extends LLMClient {
  _ScriptedLLMClient(this._responses);

  final List<ModelMessage> _responses;
  final List<List<LLMMessage>> recordedMessages = [];
  final List<ToolChoice?> recordedToolChoices = [];
  int _index = 0;

  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    dynamic cancelToken,
  }) async {
    recordedMessages.add(List<LLMMessage>.from(messages));
    recordedToolChoices.add(toolChoice);
    if (_index >= _responses.length) {
      throw StateError('No more scripted LLM responses at index $_index');
    }
    return _responses[_index++];
  }

  @override
  Future<Stream<StreamingMessage>> stream(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    dynamic cancelToken,
  }) async {
    return const Stream.empty();
  }
}

class _FakeIMcpQueryService implements IMcpQueryService {
  _FakeIMcpQueryService({
    required bool connected,
    this.responses = const {},
  }) : _connected = connected;

  final bool _connected;
  final Map<String, String> responses;
  final List<String> calls = [];
  Map<String, dynamic>? lastArguments;

  @override
  bool get isConnected => _connected;

  @override
  String? get lastError => null;

  @override
  Future<void> ensureConnected() async {}

  @override
  Future<McpToolCallResult> callTool(
    String name, {
    Map<String, dynamic>? arguments,
  }) async {
    calls.add(name);
    lastArguments = arguments;
    return McpToolCallResult(
      content: [McpContentItem(type: 'text', text: responses[name] ?? 'ok')],
    );
  }
}
