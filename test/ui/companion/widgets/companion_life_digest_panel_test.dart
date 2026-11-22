import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/mcp/mcp_protocol.dart';
import 'package:memex/data/services/i_mcp_service.dart';
import 'package:memex/ui/companion/models/life_digest_models.dart';
import 'package:memex/ui/companion/view_models/life_digest_view_model.dart';
import 'package:memex/ui/companion/widgets/companion_life_digest_panel.dart';
import 'package:memex/ui/companion/widgets/companion_life_space_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  testWidgets('renders all 5 sub-tabs and displays day/week/month/todos/profile',
      (tester) async {
    final service = _MockDigestMcpService(
      connected: true,
      handler: (_, args) {
        if (args?['section'] == 'todos') {
          return _jsonResult({
            'today': '2026-10-15',
            'todos': [
              {
                'id': 't1',
                'text': '预约年度体检',
                'quote': '下周记得把体检约了',
                'first_seen': '2026-10-05',
                'days_open': 10,
              },
            ],
          });
        }
        return switch (args?['period']) {
          'week' => _jsonResult({
              'available': true,
              'week': '2026-W42',
              'date_range': '2026-10-12 ~ 2026-10-18',
              'headline': '本周主线清晰',
              'highlights': [
                {'text': '交付了核心模块', 'sources': ['2026-10-14']},
              ],
              'us': [
                {'text': '聊了秋天的旅行计划', 'sources': ['chat']},
              ],
              'mood_rhythm': '周初略紧张，周中后逐渐舒展',
              'todos_summary': '本周推进了 3 项待办',
            }),
          'month' => _jsonResult({
              'available': true,
              'month': '2026-10',
              'date_range': '2026-10-01 ~ 2026-10-31',
              'headline': '十月是稳定沉淀的一个月',
              'themes': [
                {'text': '时间金字塔落地', 'sources': ['2026-W42']},
              ],
              'us': [
                {'text': '默契度继续加深', 'sources': ['chat']},
              ],
              'shifts': [
                {'text': '作息比上月更早', 'sources': ['hr']},
              ],
              'milestones': [
                {'text': '完成 M3 里程碑', 'sources': ['2026-10-15']},
              ],
            }),
          'profile' => _jsonResult({
              'available': true,
              'categories': {
                'rhythm': [
                  {
                    'id': 'p1',
                    'category': 'rhythm',
                    'text': '通常在早上八点左右开始工作',
                    'status': 'auto',
                    'sources': ['2026-10'],
                  },
                ],
                'work_study': [],
                'us': [
                  {
                    'id': 'p2',
                    'category': 'us',
                    'text': '雨天喜欢安静聊天',
                    'status': 'pinned',
                    'sources': ['2026-09', '2026-10'],
                  },
                ],
              },
            }),
          _ => _jsonResult({
              'available': true,
              'date': '2026-10-15',
              'stage': 'final',
              'stage_label': '定稿',
              'morning': {'text': '早安，窗外下着细雨', 'weather': '小雨 17°C'},
              'headline': '节奏从容的一天',
              'your_day': [
                {'text': '上午写完了移动端摘要页', 'sources': ['diary']},
              ],
              'us': [
                {'text': '午后聊起最近看的书', 'sources': ['chat']},
              ],
              'anomalies': [
                {'text': '昨晚睡眠不足六小时', 'sources': ['hr'], 'level': 'warn'},
              ],
            }),
        };
      },
    );

    final vm = LifeDigestViewModel(
      service: service,
      clock: () => DateTime(2026, 10, 15, 12),
    );
    await vm.load.execute();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider.value(
            value: vm,
            child: const CompanionLifeDigestPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Day tab
    expect(find.text('日'), findsOneWidget);
    expect(find.text('周'), findsOneWidget);
    expect(find.text('月'), findsOneWidget);
    expect(find.text('待办'), findsOneWidget);
    expect(find.text('档案'), findsOneWidget);
    expect(find.text('定稿'), findsOneWidget);
    expect(find.text('早安，窗外下着细雨'), findsOneWidget);
    expect(find.text('节奏从容的一天'), findsOneWidget);
    expect(find.text('上午写完了移动端摘要页'), findsOneWidget);
    expect(find.text('昨晚睡眠不足六小时'), findsOneWidget);

    // Switch to Week tab
    await tester.tap(find.byKey(const ValueKey('life_digest_subtab_week')));
    await tester.pumpAndSettle();
    expect(find.text('2026-W42'), findsOneWidget);
    expect(find.text('本周主线清晰'), findsOneWidget);
    expect(find.text('交付了核心模块'), findsOneWidget);
    expect(find.text('周初略紧张，周中后逐渐舒展'), findsOneWidget);

    // Switch to Month tab
    await tester.tap(find.byKey(const ValueKey('life_digest_subtab_month')));
    await tester.pumpAndSettle();
    expect(find.text('2026-10'), findsOneWidget);
    expect(find.text('十月是稳定沉淀的一个月'), findsOneWidget);
    expect(find.text('时间金字塔落地'), findsOneWidget);
    expect(find.text('完成 M3 里程碑'), findsOneWidget);

    // Switch to Todos tab
    await tester.tap(find.byKey(const ValueKey('life_digest_subtab_todos')));
    await tester.pumpAndSettle();
    expect(find.text('预约年度体检'), findsOneWidget);
    expect(find.text('下周记得把体检约了'), findsOneWidget);
    expect(find.text('已拖 10 天'), findsOneWidget);
    expect(find.text('在和林埃聊天时说一声即可划掉或放弃待办'), findsOneWidget);

    // Switch to Profile tab
    await tester.tap(find.byKey(const ValueKey('life_digest_subtab_profile')));
    await tester.pumpAndSettle();
    expect(find.text('基本与生活节奏'), findsOneWidget);
    expect(find.text('工作与学习主线'), findsNothing); // empty category skipped
    expect(find.text('我们之间'), findsOneWidget);
    expect(find.text('自动整理'), findsOneWidget);
    expect(find.text('已确认'), findsOneWidget);
    expect(find.text('如需修改或删除条目，直接告诉林埃即可'), findsOneWidget);

    vm.dispose();
  });

  testWidgets('shows connect button when i MCP is not connected',
      (tester) async {
    final service = _MockDigestMcpService(
      connected: false,
      lastError: '还没连接 i MCP，请到设置里连接',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LifeDigestScreen(
          initialTab: LifeDigestTab.profile,
          iMcpService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('life_digest_rain_glass_background')),
      findsOneWidget,
    );
    expect(find.text('尚未连接 i MCP'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('life_digest_connect_button')),
      findsOneWidget,
    );
  });

  testWidgets('shows offline card with working retry button', (tester) async {
    var calls = 0;
    final service = _MockDigestMcpService(
      connected: true,
      handler: (_, __) {
        calls++;
        if (calls == 1) {
          throw const SocketException('Failed host lookup');
        }
        return _jsonResult({
          'available': true,
          'date': '2026-10-15',
          'headline': '重连成功后恢复显示',
        });
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LifeDigestScreen(iMcpService: service),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('家里电脑暂时离线'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('life_digest_retry_button')));
    await tester.pumpAndSettle();

    expect(find.text('重连成功后恢复显示'), findsOneWidget);
  });

  testWidgets('shows friendly upgrade card on old M1 server', (tester) async {
    final service = _MockDigestMcpService(
      connected: true,
      handler: (_, __) => const McpToolCallResult(
        isError: true,
        content: [
          McpContentItem(type: 'text', text: 'invalid_life_digest_period'),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LifeDigestScreen(
          initialTab: LifeDigestTab.week,
          iMcpService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('等待家里电脑更新'), findsOneWidget);
    expect(find.text('家里电脑尚未更新到此版本，部署后即可查看'), findsOneWidget);
  });

  testWidgets('CompanionLifeSpaceScreen exposes 摘要 tab and renders panel',
      (tester) async {
    final service = _MockDigestMcpService(
      connected: true,
      handler: (_, __) => _jsonResult({
        'available': true,
        'date': '2026-10-15',
        'headline': '来自生活空间摘要页',
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CompanionLifeSpaceScreen(iMcpService: service),
      ),
    );
    await tester.pump();

    expect(find.text('摘要'), findsOneWidget);
    await tester.tap(find.text('摘要'));
    await tester.pumpAndSettle();

    expect(find.text('来自生活空间摘要页'), findsOneWidget);
  });
}

McpToolCallResult _jsonResult(Map<String, dynamic> payload) =>
    McpToolCallResult(
      content: [McpContentItem(type: 'text', text: jsonEncode(payload))],
    );

class _MockDigestMcpService implements IMcpQueryService {
  _MockDigestMcpService({
    required bool connected,
    String? lastError,
    this.handler,
  })  : _connected = connected,
        _lastError = lastError;

  final bool _connected;
  final String? _lastError;
  final McpToolCallResult Function(String name, Map<String, dynamic>? args)?
      handler;

  @override
  bool get isConnected => _connected;

  @override
  String? get lastError => _lastError;

  @override
  Future<void> ensureConnected() async {}

  @override
  Future<McpToolCallResult> callTool(
    String name, {
    Map<String, dynamic>? arguments,
  }) async {
    if (handler != null) return handler!(name, arguments);
    return _jsonResult({'available': false});
  }
}
