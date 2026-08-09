import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/companion/widgets/insight_strip.dart';

void main() {
  testWidgets('renders a full-width chart for two or more numeric points',
      (tester) async {
    await _pumpInsightStrip(
      tester,
      [
        _insight(
          id: 'trend',
          dataPointsJson:
              '[{"date":"周一","value":"00:31"},{"date":"周日","value":"01:18"}]',
        ),
      ],
    );

    expect(find.byKey(const ValueKey('insight_chart')), findsOneWidget);
    expect(find.byKey(const ValueKey('insight_metric')), findsNothing);
  });

  testWidgets('renders a metric block for one numeric point', (tester) async {
    await _pumpInsightStrip(
      tester,
      [
        _insight(
          id: 'metric',
          dataPointsJson: '[{"date":"本周","value":"4 次"}]',
        ),
      ],
    );

    expect(find.byKey(const ValueKey('insight_chart')), findsNothing);
    expect(find.byKey(const ValueKey('insight_metric')), findsOneWidget);
    expect(find.text('4 次'), findsOneWidget);
  });

  testWidgets('does not reserve visual space without numeric evidence',
      (tester) async {
    await _pumpInsightStrip(
      tester,
      [
        _insight(
          id: 'narrative',
          dataPointsJson: '[{"date":"本周","value":"记录不足"}]',
        ),
      ],
    );

    expect(find.byKey(const ValueKey('insight_chart')), findsNothing);
    expect(find.byKey(const ValueKey('insight_metric')), findsNothing);
    expect(find.text('基于 1 条已记录内容'), findsOneWidget);
  });

  testWidgets('keeps secondary insights compact and promotes one when tapped',
      (tester) async {
    final first = _insight(id: 'first', narrative: '第一条洞察');
    final second = _insight(id: 'second', narrative: '第二条洞察');

    await _pumpInsightStrip(tester, [first, second]);

    expect(find.byKey(const ValueKey('insight_compact_list')), findsOneWidget);
    await tester.tap(find.text('第二条洞察'));
    await tester.pump();

    final leadCard = find.byKey(const ValueKey('insight_lead_card'));
    expect(
      find.descendant(of: leadCard, matching: find.text('第二条洞察')),
      findsOneWidget,
    );
  });
}

Future<void> _pumpInsightStrip(
  WidgetTester tester,
  List<LifeInsight> insights,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF252A22),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: InsightStrip(
              domain: 'health',
              initialInsights: insights,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

LifeInsight _insight({
  required String id,
  String narrative = '入睡时间正在向后滑，平均比上周晚了 47 分钟。',
  String dataPointsJson = '[]',
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return LifeInsight(
    id: id,
    domain: 'health',
    insightType: 'trend',
    period: 'weekly',
    periodStart: now - const Duration(days: 7).inMilliseconds,
    periodEnd: now,
    dataPointsJson: dataPointsJson,
    narrative: narrative,
    confidence: 0.82,
    authority: 'agent_inferred',
    createdAt: now,
    updatedAt: now,
  );
}
