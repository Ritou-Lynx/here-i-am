import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/i_mcp_service.dart';

const iMcpReadTools = <String>{
  'notes_recent',
  'notes_search',
  'notes_read',
  'life_digest',
  'study_today',
  'study_source',
  'study_progress',
  'heart_rate',
  'food_day',
  'expense_day',
};

const _notConnectedMessage = '还没连接 i MCP，请到设置里连接';
const _maxResultLength = 20000;
const _truncationNotice = '\n\n[结果超过 20000 字，已截断]';

/// Read-only gateway from the companion agent to the i MCP frontend.
Tool buildIMcpQueryTool({IMcpQueryService? service}) {
  final queryService = service ?? IMcpService.instance;
  return Tool(
    name: 'i_query',
    description: '''查询用户已授权给 i MCP 的只读数据。仅在相关问题需要时调用，不要每轮都查。

可用工具：
- notes_recent：最近日记；常用参数 days、date、folder。
- notes_search：按内容搜索日记；参数 query。
- notes_read：读取搜索命中的正文；参数 token，可选 offset。
- life_digest：日摘要。
- study_today：今日学习；study_source：学习资料；study_progress：学习进度。
- heart_rate：历史心率或睡眠数据。
- food_day：某日饮食；参数 date。
- expense_day：ChatGPT 中记录的某日账目；参数 date。

查不到就如实说没有，不要编造。引用日记内容时说明来自哪一天。''',
    parameters: {
      'type': 'object',
      'properties': {
        'tool': {
          'type': 'string',
          'enum': iMcpReadTools.toList(),
          'description': '要调用的只读 i MCP 工具名。',
        },
        'arguments': {
          'type': 'object',
          'description': '原样传给该工具的参数；无参数时可省略。',
        },
      },
      'required': ['tool'],
    },
    executable: (Map<String, dynamic> input) async {
      final tool = input['tool'];
      if (tool is! String || !iMcpReadTools.contains(tool)) {
        return 'i MCP 拒绝调用：不允许的只读工具名';
      }
      final rawArguments = input['arguments'];
      if (rawArguments != null && rawArguments is! Map) {
        return 'i MCP 拒绝调用：arguments 必须是对象';
      }
      final arguments = rawArguments == null
          ? null
          : Map<String, dynamic>.from(rawArguments as Map);

      try {
        await queryService.ensureConnected();
        if (!queryService.isConnected) return _notConnectedMessage;
        final result = await queryService.callTool(
          tool,
          arguments: arguments,
        );
        final text = result.text;
        if (text.length <= _maxResultLength) return text;
        return '${text.substring(0, _maxResultLength)}$_truncationNotice';
      } catch (error) {
        return 'i MCP 查询失败：$error';
      }
    },
  );
}
