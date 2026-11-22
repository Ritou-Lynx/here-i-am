import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/mcp/mcp_protocol.dart';
import 'package:memex/data/services/i_mcp_service.dart';
import 'package:memex/ui/companion/models/life_digest_models.dart';
import 'package:memex/ui/companion/view_models/life_digest_view_model.dart';

void main() {
  group('IsoWeek & models', () {
    test('calculates ISO weeks accurately across year boundaries', () {
      expect(IsoWeek.fromDate(DateTime(2026, 1, 1)).formatted, '2026-W01');
      expect(IsoWeek.fromDate(DateTime(2025, 12, 29)).formatted, '2026-W01');
      expect(IsoWeek.fromDate(DateTime(2026, 12, 31)).formatted, '2026-W53');
      expect(IsoWeek.fromDate(DateTime(2026, 10, 15)).formatted, '2026-W42');

      const w42 = IsoWeek(2026, 42);
      expect(formatIsoDate(w42.monday), '2026-10-12');
      expect(formatIsoDate(w42.sunday), '2026-10-18');
      expect(w42.fallbackDateRange, '2026-10-12 ~ 2026-10-18');
      expect(w42.step(-1).formatted, '2026-W41');
      expect(w42.step(1).formatted, '2026-W43');
    });

    test('parses day, week, month, todos, and profile payloads defensively', () {
      final day = DayDigestData.fromJson({
        'available': true,
        'date': '2026-10-15',
        'stage': 'final',
        'morning': {'text': '早安，今天微雨', 'weather': '小雨 18°C'},
        'headline': '专注推进 M3 的一天',
        'your_day': [
          {'text': '完成周报整理', 'sources': ['diary:2026-10-15']},
        ],
        'us': [
          {'text': '晚上聊了很久', 'sources': ['chat']},
        ],
        'anomalies': [
          {'text': '连续两晚晚睡', 'sources': ['hr'], 'level': 'warn'},
        ],
      });
      expect(day.available, isTrue);
      expect(day.displayStageLabel, '定稿');
      expect(day.morning?.weather, '小雨 18°C');
      expect(day.anomalies.single.isWarn, isTrue);

      final week = WeekDigestData.fromJson({
        'available': true,
        'week': '2026-W42',
        'date_range': ['2026-10-12', '2026-10-18'],
        'headline': '节奏稳健的一周',
        'highlights': [
          {'text': '完成阶段目标', 'sources': ['2026-10-14']},
        ],
        'mood_rhythm': '整体平稳，周中略累',
        'todos_summary': '完成 3 项，剩余 2 项',
      });
      expect(week.dateRange, '2026-10-12 ~ 2026-10-18');
      expect(week.moodRhythm, '整体平稳，周中略累');

      final todos = LifeDigestTodosData.fromJson({
        'today': '2026-10-15',
        'todos': [
          {
            'id': 't1',
            'text': '预约体检',
            'quote': '这周一定要约体检',
            'first_seen': '2026-10-05',
            'days_open': 10,
          },
          {
            'id': 't2',
            'text': '买咖啡豆',
            'first_seen': '2026-10-13',
            'days_open': 2,
          },
        ],
      });
      expect(todos.todos[0].isOverdue, isTrue);
      expect(todos.todos[1].isOverdue, isFalse);

      final profile = LongTermProfileData.fromJson({
        'available': true,
        'categories': {
          'us': [
            {
              'id': 'p2',
              'category': 'us',
              'text': '喜欢一起在雨天散步',
              'status': 'pinned',
              'sources': ['2026-10'],
            },
          ],
          'health': [],
          'rhythm': [
            {
              'id': 'p1',
              'category': 'rhythm',
              'text': '习惯清晨喝一杯黑咖啡',
              'status': 'auto',
              'sources': ['2026-09', '2026-10'],
            },
          ],
        },
        'items': [
          {
            'id': 'p1',
            'category': 'rhythm',
            'text': '习惯清晨喝一杯黑咖啡',
            'status': 'auto',
          },
        ],
      });
      final ordered = profile.orderedNonEmptyCategories;
      expect(ordered.map((e) => e.key).toList(), ['rhythm', 'us']);
      expect(ordered[0].value.length, 1);
      expect(ordered[0].value.single.isPinned, isFalse);
      expect(ordered[1].value.single.isPinned, isTrue);
    });
  });

  group('LifeDigestViewModel', () {
    final fixedNow = DateTime(2026, 10, 15, 14, 30);

    test('calls life_digest with expected arguments across all 5 tabs', () async {
      final service = _FakeIMcpService(
        connected: true,
        handler: (name, args) {
          expect(name, 'life_digest');
          if (args?['section'] == 'todos') {
            return _jsonResult({
              'today': '2026-10-15',
              'todos': [
                {'id': 't1', 'text': '整理发票', 'days_open': 8},
              ],
            });
          }
          switch (args?['period']) {
            case 'week':
              return _jsonResult({
                'available': true,
                'week': args?['week'],
                'headline': '周摘要标题',
              });
            case 'month':
              return _jsonResult({
                'available': true,
                'month': args?['month'],
                'headline': '月摘要标题',
              });
            case 'profile':
              return _jsonResult({
                'available': true,
                'items': [
                  {
                    'id': 'p1',
                    'category': 'preferences',
                    'text': '偏爱清淡饮食',
                    'status': 'pinned',
                  },
                ],
              });
            default:
              return _jsonResult({
                'available': true,
                'date': args?['date'],
                'stage_label': '白天版',
                'headline': '日摘要标题',
              });
          }
        },
      );

      final vm = LifeDigestViewModel(service: service, clock: () => fixedNow);
      addTearDown(vm.dispose);

      // Day tab omits `period` for M1 server compatibility.
      await vm.load.execute();
      expect(service.recordedArgs.last, {'date': '2026-10-15'});
      expect(vm.dayData?.headline, '日摘要标题');
      expect(vm.dayData?.displayStageLabel, '白天版');

      // Week tab
      vm.selectTab(LifeDigestTab.week);
      await _drain();
      expect(service.recordedArgs.last, {'period': 'week', 'week': '2026-W42'});
      expect(vm.weekData?.headline, '周摘要标题');

      // Month tab
      vm.selectTab(LifeDigestTab.month);
      await _drain();
      expect(service.recordedArgs.last, {'period': 'month', 'month': '2026-10'});
      expect(vm.monthData?.headline, '月摘要标题');

      // Todos tab
      vm.selectTab(LifeDigestTab.todos);
      await _drain();
      expect(service.recordedArgs.last, {'section': 'todos'});
      expect(vm.todosData?.todos.single.text, '整理发票');

      // Profile tab
      vm.selectTab(LifeDigestTab.profile);
      await _drain();
      expect(service.recordedArgs.last, {'period': 'profile'});
      expect(vm.profileData?.orderedNonEmptyCategories.single.key, 'preferences');
    });

    test('steps date, week, and month backward and clamps at current period',
        () async {
      final service = _FakeIMcpService(
        connected: true,
        handler: (_, args) => _jsonResult({'available': false}),
      );
      final vm = LifeDigestViewModel(service: service, clock: () => fixedNow);
      addTearDown(vm.dispose);

      expect(vm.canStepDateForward, isFalse);
      vm.stepDate(1);
      expect(formatIsoDate(vm.selectedDate), '2026-10-15');

      vm.stepDate(-1);
      await _drain();
      expect(formatIsoDate(vm.selectedDate), '2026-10-14');
      expect(vm.canStepDateForward, isTrue);
      expect(service.recordedArgs.last, {'date': '2026-10-14'});

      vm.stepDate(1);
      await _drain();
      expect(formatIsoDate(vm.selectedDate), '2026-10-15');
      expect(vm.canStepDateForward, isFalse);

      // Week stepping
      vm.selectTab(LifeDigestTab.week);
      await _drain();
      expect(vm.canStepWeekForward, isFalse);
      vm.stepWeek(1);
      expect(vm.selectedWeek.formatted, '2026-W42');
      vm.stepWeek(-1);
      await _drain();
      expect(vm.selectedWeek.formatted, '2026-W41');
      expect(vm.canStepWeekForward, isTrue);

      // Month stepping
      vm.selectTab(LifeDigestTab.month);
      await _drain();
      expect(vm.canStepMonthForward, isFalse);
      vm.stepMonth(1);
      expect(formatIsoMonth(vm.selectedMonth), '2026-10');
      vm.stepMonth(-1);
      await _drain();
      expect(formatIsoMonth(vm.selectedMonth), '2026-09');
      expect(vm.canStepMonthForward, isTrue);
    });

    test('classifies disconnected i MCP as notConnected', () async {
      final service = _FakeIMcpService(
        connected: false,
        lastError: '还没连接 i MCP，请到设置里连接',
      );
      final vm = LifeDigestViewModel(service: service, clock: () => fixedNow);
      addTearDown(vm.dispose);

      await vm.load.execute();
      expect(vm.currentFailure?.kind, LifeDigestFailureKind.notConnected);
    });

    test('classifies offline network errors as offline', () async {
      final service = _FakeIMcpService(
        connected: true,
        error: const SocketException('Failed host lookup'),
      );
      final vm = LifeDigestViewModel(service: service, clock: () => fixedNow);
      addTearDown(vm.dispose);

      await vm.load.execute();
      expect(vm.currentFailure?.kind, LifeDigestFailureKind.offline);
    });

    test('classifies disconnected service with offline lastError as offline',
        () async {
      final service = _FakeIMcpService(
        connected: false,
        lastError: '暂时连不上 i MCP（家里电脑可能离线），稍后再试',
      );
      final vm = LifeDigestViewModel(service: service, clock: () => fixedNow);
      addTearDown(vm.dispose);

      await vm.load.execute();
      expect(vm.currentFailure?.kind, LifeDigestFailureKind.offline);
    });

    test('gracefully degrades on old M1 server rejecting period=week/month/profile',
        () async {
      final service = _FakeIMcpService(
        connected: true,
        handler: (_, args) => const McpToolCallResult(
          isError: true,
          content: [
            McpContentItem(
              type: 'text',
              text: 'invalid_life_digest_period: period not supported',
            ),
          ],
        ),
      );
      final vm = LifeDigestViewModel(
        service: service,
        initialTab: LifeDigestTab.profile,
        clock: () => fixedNow,
      );
      addTearDown(vm.dispose);

      await vm.load.execute();
      expect(vm.currentFailure?.kind, LifeDigestFailureKind.unsupportedPeriod);
      expect(
        vm.currentFailure?.message,
        '家里电脑尚未更新到此版本，部署后即可查看',
      );
    });

    test('handles TimeoutException as offline', () async {
      final service = _FakeIMcpService(
        connected: true,
        error: TimeoutException('request timed out'),
      );
      final vm = LifeDigestViewModel(service: service, clock: () => fixedNow);
      addTearDown(vm.dispose);

      await vm.load.execute();
      expect(vm.currentFailure?.kind, LifeDigestFailureKind.offline);
    });
  });
}

Future<void> _drain() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

McpToolCallResult _jsonResult(Map<String, dynamic> payload) =>
    McpToolCallResult(
      content: [McpContentItem(type: 'text', text: jsonEncode(payload))],
    );

class _FakeIMcpService implements IMcpQueryService {
  _FakeIMcpService({
    required bool connected,
    String? lastError,
    this.error,
    this.handler,
  })  : _connected = connected,
        _lastError = lastError;

  final bool _connected;
  final String? _lastError;
  final Object? error;
  final McpToolCallResult Function(String name, Map<String, dynamic>? args)?
      handler;

  final List<Map<String, dynamic>?> recordedArgs = [];

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
    recordedArgs.add(arguments);
    if (error != null) throw error!;
    if (handler != null) return handler!(name, arguments);
    return _jsonResult({'available': false});
  }
}
