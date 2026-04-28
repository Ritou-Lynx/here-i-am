import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/schedule_refresh_router_agent/schedule_refresh_router_agent.dart';
import 'package:memex/domain/models/card_model.dart';

void main() {
  group('ScheduleRefreshRouterAgent helpers', () {
    test('detects temporal card templates as schedule relevant', () {
      const card = CardData(
        factId: '2026/04/26.md#ts_1',
        timestamp: 1777188000,
        status: 'completed',
        tags: [],
        uiConfigs: [
          UiConfig(
            templateId: 'task',
            data: {'due_date': '2026-04-27T10:00:00'},
          ),
        ],
      );

      expect(hasScheduleRelevantTemplates(card), isTrue);
    });

    test('ignores non temporal card templates', () {
      const card = CardData(
        factId: '2026/04/26.md#ts_2',
        timestamp: 1777188000,
        status: 'completed',
        tags: [],
        uiConfigs: [
          UiConfig(
            templateId: 'classic_card',
            data: {'content': '普通记录'},
          ),
        ],
      );

      expect(hasScheduleRelevantTemplates(card), isFalse);
    });

    test('router context contains raw input and structured card data', () {
      const card = CardData(
        factId: '2026/04/26.md#ts_3',
        timestamp: 1777188000,
        status: 'completed',
        title: '明早收拾家里',
        tags: ['home'],
        uiConfigs: [
          UiConfig(
            templateId: 'task',
            data: {
              'title': '收拾家里',
              'due_date': '2026-04-27T10:00:00',
            },
          ),
        ],
      );

      final context = buildScheduleRefreshRouterContext(
        factId: card.factId,
        combinedText: '提醒我明天早上十点收拾家里',
        cardData: card,
        recentScheduleContext: const {'count': 0, 'cards': []},
        refreshState: const {'is_dirty': false},
      );

      expect(context['new_input']['combined_text'], contains('收拾家里'));
      expect(context['new_card']['title'], '明早收拾家里');
      expect(context['new_card']['ui_configs'].single['template_id'], 'task');
      expect(context['recent_schedule_context']['count'], 0);
    });
  });
}
